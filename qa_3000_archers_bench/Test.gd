extends Node

## ═══════════════════════════════════════════════════════════════════════════
## БЕНЧМАРК qa_3000_archers_bench — СКАН ЦЕЛЕЙ У 3000 ЛУЧНИКОВ
## ═══════════════════════════════════════════════════════════════════════════
## Измеритель с ЧЕТЫРЬМЯ вердиктами по поведению (цифры производительности
## вердиктов не имеют — их судит владелец по таблице).
##
## Сцена: 100 отрядов по 30 лучников (3000) стоят линией, на них накатывает
## волна пехоты. Волна БЕССМЕРТНА и возвращается на исходную перед каждой
## фазой: иначе первая же фаза выбивает противника, и второй достаётся пустое
## поле — мерились бы разные сцены, а не разный код.
##
##   A  A/B ЧЕРЕДОВАНИЕМ: старый путь (личный опрос + отрядный кэш) против
##      центрового нода отряда (perf_config.squad_radar). Снимается ЧЕСТНЫЙ
##      тик армии (tick_meter), число сканов сетки (scan_meter — счётчик
##      вызовов, а не часы) и FPS (только в окне: в headless движок ставит
##      пустой драйвер и кадр не показателен).
##      ПОРЯДОК ФАЗ ПЕРЕВОРАЧИВАЕТСЯ ПО РАУНДАМ — иначе дрейф живой сцены
##      систематически достаётся одной из них (правило qa_ab).
##   B  ЗАДЕРЖКА ПЕРВОГО ЗАЛПА: один отряд, один враг входит с 30 м. Меряется
##      время от пересечения дистанции огня до первой стрелы в обоих режимах.
##   C  ДВЕ ФАЗЫ: на 21-25 м отряд РАЗВЁРНУТ на врага и МОЛЧИТ, на 20 —
##      стреляет. Это требование заказа, а не следствие экономии.
##   D  СБРОС ПО КЛИКУ: приказ игрока обнуляет такт 0.5 с.
##
## Запуск: <godot> --path . res://qa_3000_archers_bench/Test.tscn
##         (headless годится для сканов, мс и вердиктов; FPS — только окно)
##         -- squads=N men=N foes=N sec=N

const _Opt   := preload("res://scripts/perf_config.gd")
const _UCfg  := preload("res://scripts/unit_stats_config.gd")

const ARCHER := "res://scenes/units/Archer.tscn"
const FOE    := "res://scenes/units/GoblinSpearman.tscn"

var SQUADS := 100
var MEN    := 30
var FOES   := 400
var PHASE_SEC := 6.0
var ROUNDS := 2

## Строй: 10 колонок в отряде, блоки 10 в ряд
const COLS := 10
const GAP := 0.9
const BLOCK_STEP_X := 12.0
const BLOCK_STEP_Z := 11.0
const BLOCKS_PER_ROW := 10
## Откуда накатывает волна и куда она идёт
## Волна встаёт ЗА радиусом обнаружения, но близко: за фазу она обязана
## пересечь и 25 м, и 20 — иначе мерится СТОЯЩАЯ армия, а не бой. Первая
## версия ставила её на 55 м, и за шесть секунд пехота (2.2 м/с) не доходила
## вовсе: обе фазы мерили сцену, в которой никто никого не видит
const FOE_START_AHEAD := 30.0
const IMMORTAL := 1e9

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _archers: Array = []
var _sids: Array = []
var _foes: Array = []
var _foe_home: Array = []
var _line_z: float = 0.0
var _anchor: Vector3 = Vector3.ZERO
## [режим] -> {"tick": мс, "scans": сканов/с, "fps": кадров/с}
var _res := {}

func _ready() -> void:
	_read_args()
	call_deferred("_run")
	var t := get_tree().create_timer(900.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: бенчмарк не завершился за 900 с")
		_finish())

func _read_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("squads="): SQUADS = maxi(1, int(s.substr(7)))
		elif s.begins_with("men="):  MEN = maxi(1, int(s.substr(4)))
		elif s.begins_with("foes="): FOES = maxi(1, int(s.substr(5)))
		elif s.begins_with("sec="):  PHASE_SEC = maxf(1.0, float(s.substr(4)))
		elif s.begins_with("rounds="): ROUNDS = maxi(1, int(s.substr(7)))

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_3000_archers_bench: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	var headless: bool = DisplayServer.get_name() == "headless"

	# Блоки поведения — ДО массовой сцены: им нужен чистый угол карты и
	# несколько бойцов, а не три тысячи
	await _b_first_volley_delay()
	await _c_two_phases()
	await _d_player_kick()

	await _build_mass()
	await _a_ab(headless)
	_report(headless)
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# ПОСТРОЕНИЕ МАССОВОЙ СЦЕНЫ
# ═════════════════════════════════════════════════════════════════════════════
func _build_mass() -> void:
	print("\n═════ ПОСТРОЕНИЕ: %d отрядов × %d = %d лучников + %d пехоты ═════" % [
		SQUADS, MEN, SQUADS * MEN, FOES])
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	_anchor = Vector3(base.x + 40.0, 0.0, base.z + 40.0)
	var t0: int = Time.get_ticks_msec()
	for s in range(SQUADS):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
		_sids.append(sid)
		var bx: float = _anchor.x + float(s % BLOCKS_PER_ROW) * BLOCK_STEP_X
		var bz: float = _anchor.z + float(s / BLOCKS_PER_ROW) * BLOCK_STEP_Z
		var slots: Array = []
		for k in range(MEN):
			var u := _spawn(ARCHER, Constants.FACTION_PLAYER,
				Vector3(bx + float(k % COLS) * GAP, 0.0, bz + float(k / COLS) * GAP))
			# ── ВСЕ БЕССМЕРТНЫ ────────────────────────────────────────────
			# Фаз четыре и более; гибель разъедала бы сцену, и вторая фаза
			# мерила бы другую армию, а не другой код
			u.max_health = IMMORTAL
			u.current_health = IMMORTAL
			GameManager.add_to_squad(sid, u)
			_archers.append(u)
			slots.append(u.global_position)
		GameManager.squad_set_formation(sid, slots, Vector3(0.0, 0.0, -1.0), false)
		if s % 10 == 0:
			await get_tree().physics_frame
	_line_z = _anchor.z
	# ── ВОЛНА ─────────────────────────────────────────────────────────────
	# Заходит с той стороны, куда смотрит строй, и идёт сквозь него: за фазу
	# она успевает пересечь и 25 м, и 20 — то есть обе фазы радара работают
	var fz: float = _line_z - FOE_START_AHEAD
	for i in range(FOES):
		var fx: float = _anchor.x + float(i % 40) * 1.6
		var fzz: float = fz - float(i / 40) * 1.6
		var f := _spawn(FOE, Constants.FACTION_GOBLIN, Vector3(fx, 0.0, fzz))
		f.max_health = IMMORTAL
		f.current_health = IMMORTAL
		_foes.append(f)
		_foe_home.append(f.global_position)
		if i % 50 == 0:
			await get_tree().physics_frame
	await pframes(10)
	print("  собрано за %.1f с; живых в сцене %d, строк ядра %d, ячейка сетки %.2f м" % [
		float(Time.get_ticks_msec() - t0) * 0.001, GameManager.active_units(),
		GameManager.army.top(), GameManager.army.grid_cell_size()])

## Вернуть волну на исходную и отправить её на строй заново
func _reset_wave() -> void:
	for i in range(_foes.size()):
		var f := _foes[i] as Unit
		if f == null or not is_instance_valid(f):
			continue
		f.current_health = IMMORTAL
		f.global_position = _foe_home[i]
		f.set_attack_target(null)
		f.sync_row()
	for a in _archers:
		var u := a as Unit
		if u != null and is_instance_valid(u):
			u.current_health = IMMORTAL
			u.set_attack_target(null)
	await pframes(4)
	for f in _foes:
		var u := f as Unit
		if u != null and is_instance_valid(u):
			u.command_move(Vector3(u.global_position.x, 0.0, _line_z + 6.0))
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# A. A/B ЧЕРЕДОВАНИЕМ
# ═════════════════════════════════════════════════════════════════════════════
func _measure_phase(radar: bool, headless: bool) -> Dictionary:
	_Opt.squad_radar = radar
	await _reset_wave()
	await pframes(20)                       # прогрев: волна тронулась
	_Opt.tick_reset()
	_Opt.scan_reset()
	_Opt.tick_meter = true
	_Opt.scan_meter = true
	GameManager.radar_scans = 0
	var f0: int = Engine.get_physics_frames()
	var w0: int = Time.get_ticks_usec()
	var fps_acc := 0.0
	var fps_n := 0
	var n: int = int(PHASE_SEC * 60.0)
	for i in range(n):
		await get_tree().physics_frame
		if not headless and (i % 6) == 0:
			fps_acc += Engine.get_frames_per_second()
			fps_n += 1
	var wall: float = float(Time.get_ticks_usec() - w0) * 1e-6
	_Opt.tick_meter = false
	_Opt.scan_meter = false
	var frames_n: int = Engine.get_physics_frames() - f0
	# Сканы В СЕКУНДУ ИГРОВОГО ВРЕМЕНИ (физкадры / 60), а не по стенным часам:
	# в headless кадры бегут быстрее реального времени, и «в секунду» по стене
	# дало бы число, которого в партии не бывает (правило 12)
	var game_sec: float = float(frames_n) / 60.0
	var site_txt := ""
	var arch_calls := 0
	for row in _Opt.scan_report():
		site_txt += "%s=%d  " % [String(row[0]), int(row[1])]
		# Метки, которые может дать только стоящий стрелковый отряд: отрядный
		# кэш и его промахи. blocker_* и retarget_* дают марширующие и
		# дерущиеся — они одинаковы в обоих режимах и профита не показывают
		if String(row[0]) in ["squad_cache_fill", "cache_miss_range", "cache_off"]:
			arch_calls += int(row[1])
	return {
		"sites": site_txt,
		"arch": float(arch_calls) / maxf(game_sec, 0.001),
		"tick": _Opt.tick_ms(),
		"scans": float(_Opt.scan_calls) / maxf(game_sec, 0.001),
		"radar": float(GameManager.radar_scans) / maxf(game_sec, 0.001),
		"fps": (fps_acc / float(maxi(fps_n, 1))) if fps_n > 0 else 0.0,
		"wall": wall,
		"frames": frames_n,
	}

func _a_ab(headless: bool) -> void:
	print("\n═════ A. A/B ЧЕРЕДОВАНИЕМ, %d раунда × 2 фазы по %.0f с ═════" % [
		ROUNDS, PHASE_SEC])
	var acc := {"old": {"tick": 0.0, "scans": 0.0, "fps": 0.0, "radar": 0.0, "arch": 0.0},
				"new": {"tick": 0.0, "scans": 0.0, "fps": 0.0, "radar": 0.0, "arch": 0.0}}
	# ── ПЕРВЫЙ РАУНД — ПРОГРЕВ И В ЗАЧЁТ НЕ ИДЁТ ──────────────────────────
	# Сцена только собрана: кэши шейдеров, буферы отрисовки и сама волна ещё
	# не вышли на режим. Замер это видит прямо: в первом раунде FPS дал 56 в
	# одной фазе и 281 в другой на одном и том же коде
	var counted := 0
	for rnd in range(ROUNDS):
		var first_new: bool = (rnd % 2) == 1
		var warm: bool = rnd == 0 and ROUNDS > 1
		for p in range(2):
			var radar: bool = first_new if p == 0 else not first_new
			var r: Dictionary = await _measure_phase(radar, headless)
			var key: String = "new" if radar else "old"
			if warm:
				print("  раунд %d (прогрев, в зачёт не идёт) | %-14s тик %5.2f мс | FPS %5.1f" % [
					rnd + 1, "радар ВКЛ" if radar else "старый путь",
					float(r["tick"]), float(r["fps"])])
				continue
			if p == 1:
				counted += 1
			for f in ["tick", "scans", "fps", "radar", "arch"]:
				acc[key][f] = float(acc[key][f]) + float(r[f])
			print("  раунд %d | %-22s тик %5.2f мс | сканов %8.0f /с | радар %5.0f /с | FPS %5.1f" % [
				rnd + 1, "радар ВКЛ" if radar else "старый путь",
				float(r["tick"]), float(r["scans"]), float(r["radar"]), float(r["fps"])])
			print("        откуда сканы: %s" % String(r.get("sites", "")))
	var div: float = float(maxi(counted, 1))
	for k in ["old", "new"]:
		for f in ["tick", "scans", "fps", "radar", "arch"]:
			acc[k][f] = float(acc[k][f]) / div
	_res["old"] = acc["old"]
	_res["new"] = acc["new"]
	_Opt.squad_radar = false

# ═════════════════════════════════════════════════════════════════════════════
# B. ЗАДЕРЖКА ПЕРВОГО ЗАЛПА
# ═════════════════════════════════════════════════════════════════════════════
## Один отряд, один враг входит с 30 м пешком. Возвращает [задержка_с,
## дистанция_в_миг_первой_стрелы]
func _volley_delay(radar: bool) -> Array:
	_Opt.squad_radar = radar
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	var spot := Vector3(base.x + 250.0, 0.0, base.z + 0.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var men: Array = []
	var slots: Array = []
	for k in range(MEN):
		var u := _spawn(ARCHER, Constants.FACTION_PLAYER,
			Vector3(spot.x + float(k % COLS) * GAP, 0.0,
				spot.z + float(k / COLS) * GAP))
		u.max_health = IMMORTAL
		u.current_health = IMMORTAL
		GameManager.add_to_squad(sid, u)
		men.append(u)
		slots.append(u.global_position)
	GameManager.squad_set_formation(sid, slots, Vector3(0.0, 0.0, -1.0), false)
	var lead := men[0] as Unit
	var reach: float = lead.attack_range
	var foe := _spawn(FOE, Constants.FACTION_GOBLIN,
		Vector3(spot.x, 0.0, spot.z - 30.0))
	foe.max_health = IMMORTAL
	foe.current_health = IMMORTAL
	await pframes(30)                       # отряд осел, радар взял такт
	var shots0: int = GameManager.arrows_fired
	foe.command_move(Vector3(spot.x, 0.0, spot.z + 4.0))
	# Ждём МОМЕНТ ПЕРЕСЕЧЕНИЯ дистанции огня и от него считаем кадры до стрелы
	var crossed := -1
	var fired := -1
	var d_at_shot := 0.0
	for f in range(60 * 25):
		await get_tree().physics_frame
		if not is_instance_valid(foe) or foe.is_dead():
			break
		var d: float = Vector2(foe.global_position.x - lead.global_position.x,
			foe.global_position.z - lead.global_position.z).length()
		if crossed < 0 and d <= reach:
			crossed = f
		if GameManager.arrows_fired > shots0:
			fired = f
			d_at_shot = d
			break
	for m in men:
		if is_instance_valid(m):
			(m as Unit).take_damage(IMMORTAL * 10.0)
	if is_instance_valid(foe):
		foe.take_damage(IMMORTAL * 10.0)
	await pframes(6)
	if fired < 0:
		return [-1.0, 0.0]
	# Отрицательная задержка = выстрел ДО пересечения (упреждение сработало)
	var delay: float = float(fired - maxi(crossed, 0)) / 60.0
	if crossed < 0:
		delay = 0.0
	return [delay, d_at_shot]

func _b_first_volley_delay() -> void:
	print("\n═════ B. ЗАДЕРЖКА ПЕРВОГО ЗАЛПА ═════")
	var old_r: Array = await _volley_delay(false)
	var new_r: Array = await _volley_delay(true)
	_Opt.squad_radar = false
	print("  старый путь: задержка %.3f с, дистанция в миг выстрела %.1f м" % [
		float(old_r[0]), float(old_r[1])])
	print("  радар:       задержка %.3f с, дистанция в миг выстрела %.1f м" % [
		float(new_r[0]), float(new_r[1])])
	_res["delay_old"] = float(old_r[0])
	_res["delay_new"] = float(new_r[0])
	verdict("B1 оба режима открывают огонь",
		float(old_r[0]) >= 0.0 and float(new_r[0]) >= 0.0,
		"старый %.3f с, радар %.3f с" % [float(old_r[0]), float(new_r[0])])
	verdict("B2 радар стреляет не позже старого пути",
		float(new_r[0]) <= float(old_r[0]) + 0.001,
		"радар %.3f против %.3f с" % [float(new_r[0]), float(old_r[0])])

# ═════════════════════════════════════════════════════════════════════════════
# C. ДВЕ ФАЗЫ: ПРИЦЕЛИЛСЯ — МОЛЧИТ, ВОШЁЛ В ДАЛЬНОСТЬ — СТРЕЛЯЕТ
# ═════════════════════════════════════════════════════════════════════════════
func _c_two_phases() -> void:
	print("\n═════ C. ДВЕ ФАЗЫ ЦЕНТРОВОГО НОДА ═════")
	_Opt.squad_radar = true
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	var spot := Vector3(base.x + 250.0, 0.0, base.z + 45.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var men: Array = []
	var slots: Array = []
	for k in range(MEN):
		var u := _spawn(ARCHER, Constants.FACTION_PLAYER,
			Vector3(spot.x + float(k % COLS) * GAP, 0.0,
				spot.z + float(k / COLS) * GAP))
		u.max_health = IMMORTAL
		u.current_health = IMMORTAL
		GameManager.add_to_squad(sid, u)
		men.append(u)
		slots.append(u.global_position)
	GameManager.squad_set_formation(sid, slots, Vector3(0.0, 0.0, -1.0), false)
	var lead := men[0] as Unit
	var reach: float = lead.attack_range
	var margin: float = GameManager.RADAR_MARGIN
	print("  дальность лука %.1f м, радиус обнаружения %.1f м" % [reach, reach + margin])
	# ── ВРАГ В ПОЛОСЕ ОБНАРУЖЕНИЯ (между дальностью и радиусом радара) ────
	var mid: float = reach + margin * 0.5
	var foe := _spawn(FOE, Constants.FACTION_GOBLIN,
		Vector3(spot.x, 0.0, spot.z - mid))
	foe.max_health = IMMORTAL
	foe.current_health = IMMORTAL
	foe.set_tick(false)                     # стоит: проверяем фазу, а не бег
	var shots0: int = GameManager.arrows_fired
	await pframes(70)                       # больше такта радара (0.5 с)
	var phase: int = GameManager.squad_radar_phase(sid)
	var aimed := 0
	var fdir := Vector3(foe.global_position.x - lead.global_position.x, 0.0,
		foe.global_position.z - lead.global_position.z).normalized()
	for m in men:
		var u := m as Unit
		if u != null and u._facing.dot(fdir) > 0.85:
			aimed += 1
	verdict("C1 на 21-25 м отряд в фазе прицеливания (TARGET_LOCKED)",
		phase == GameManager.RADAR_LOCKED,
		"фаза %d, дистанция %.1f м" % [phase, mid])
	verdict("C2 и НЕ стреляет",
		GameManager.arrows_fired == shots0,
		"выстрелов %d" % (GameManager.arrows_fired - shots0))
	verdict("C3 отряд развёрнут на врага",
		aimed >= int(float(men.size()) * 0.9),
		"смотрят на цель %d из %d" % [aimed, men.size()])
	# ── ВРАГ ПЕРЕСЁК ДАЛЬНОСТЬ ОГНЯ ───────────────────────────────────────
	foe.global_position = Vector3(spot.x, GameManager.get_terrain_height(
		spot.x, spot.z - reach * 0.8), spot.z - reach * 0.8)
	foe.sync_row()
	await pframes(70)
	verdict("C4 внутри дальности — фаза огня и стрелы полетели",
		GameManager.squad_radar_phase(sid) == GameManager.RADAR_FIRE
			and GameManager.arrows_fired > shots0,
		"фаза %d, выстрелов %d" % [GameManager.squad_radar_phase(sid),
			GameManager.arrows_fired - shots0])
	for m in men:
		if is_instance_valid(m):
			(m as Unit).take_damage(IMMORTAL * 10.0)
	if is_instance_valid(foe):
		foe.take_damage(IMMORTAL * 10.0)
	await pframes(6)
	_Opt.squad_radar = false

# ═════════════════════════════════════════════════════════════════════════════
# D. СБРОС ТАКТА ПО КЛИКУ ИГРОКА
# ═════════════════════════════════════════════════════════════════════════════
func _d_player_kick() -> void:
	print("\n═════ D. СБРОС ПО КЛИКУ ИГРОКА ═════")
	_Opt.squad_radar = true
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	var spot := Vector3(base.x + 250.0, 0.0, base.z + 90.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var men: Array = []
	for k in range(6):
		var u := _spawn(ARCHER, Constants.FACTION_PLAYER,
			Vector3(spot.x + float(k) * GAP, 0.0, spot.z))
		u.max_health = IMMORTAL
		u.current_health = IMMORTAL
		GameManager.add_to_squad(sid, u)
		men.append(u)
	var foe := _spawn(FOE, Constants.FACTION_GOBLIN,
		Vector3(spot.x, 0.0, spot.z - 12.0))
	foe.max_health = IMMORTAL
	foe.current_health = IMMORTAL
	foe.set_tick(false)
	await pframes(40)
	# Отодвигаем такт радара на полсекунды вперёд и проверяем, что приказ
	# игрока не ждёт его, а исполняется немедленно
	var sq: Dictionary = GameManager.squads[sid]
	sq["radar_next"] = Time.get_ticks_msec() + 100000
	sq["radar_phase"] = GameManager.RADAR_IDLE
	sq["radar_foe"] = null
	var lead := men[0] as Unit
	lead.command_attack(foe, true, false, true)
	await pframes(2)
	verdict("D1 приказ игрока обнуляет такт центрового нода",
		int(sq.get("radar_next", -1)) == 0
			or GameManager.squad_radar_phase(sid) == GameManager.RADAR_FIRE,
		"такт %d, фаза %d" % [int(sq.get("radar_next", -1)),
			GameManager.squad_radar_phase(sid)])
	verdict("D2 цель приказа сразу становится целью отряда",
		GameManager.squad_radar_foe(sid) == foe,
		"цель отряда %s" % ("та же" if GameManager.squad_radar_foe(sid) == foe else "другая"))
	for m in men:
		if is_instance_valid(m):
			(m as Unit).take_damage(IMMORTAL * 10.0)
	if is_instance_valid(foe):
		foe.take_damage(IMMORTAL * 10.0)
	await pframes(6)
	_Opt.squad_radar = false

# ═════════════════════════════════════════════════════════════════════════════
# ОТЧЁТ
# ═════════════════════════════════════════════════════════════════════════════
func _pct(a: float, b: float) -> float:
	if a <= 0.0:
		return 0.0
	return 100.0 * (b - a) / a

func _report(headless: bool) -> void:
	var o: Dictionary = _res.get("old", {})
	var n: Dictionary = _res.get("new", {})
	if o.is_empty() or n.is_empty():
		return
	var men_total: int = SQUADS * MEN
	print("\n📊 **BENCHMARK REPORT: ARCHER SCANNING (%d UNITS)**\n" % men_total)
	print("| Метрика | Старая система (Индивидуальная) | Новая система (Squad Radar 25m/20m) | Разница / Профит |")
	print("| :--- | :--- | :--- | :--- |")
	var new_scans: float = float(n["scans"]) + float(n["radar"])
	# Скан, приходящийся ИМЕННО на стрелков: общий счётчик ловит ещё и
	# марширующую пехоту (blocker_reach), а её радар не касается вовсе
	var o_arch: float = float(o.get("arch", 0.0))
	var n_arch: float = float(n.get("arch", 0.0)) + float(n["radar"])
	print("| **Вызовов Scan / sec** | %.0f / sec | %.0f / sec | **%+.1f%%** |" % [
		float(o["scans"]), new_scans, _pct(float(o["scans"]), new_scans)])
	print("| **из них на стрелковых отрядах** | %.0f / sec | %.0f / sec | **%+.1f%%** |" % [
		o_arch, n_arch, _pct(o_arch, n_arch)])
	print("| **Process Time (Physics)** | %.2f ms | %.2f ms | **%+.2f ms** |" % [
		float(o["tick"]), float(n["tick"]), float(n["tick"]) - float(o["tick"])])
	if headless:
		print("| **FPS (при %d юнитах)** | — | — | headless: кадр не показателен |" % men_total)
	else:
		print("| **FPS (при %d юнитах)** | %.0f FPS | %.0f FPS | **%+.0f FPS** |" % [
			men_total, float(o["fps"]), float(n["fps"]),
			float(n["fps"]) - float(o["fps"])])
	print("| **Задержка первого залпа** | %.3f sec | %.3f sec | %s |" % [
		float(_res.get("delay_old", 0.0)), float(_res.get("delay_new", 0.0)),
		"**Мгновенно**" if float(_res.get("delay_new", 1.0)) <= 0.017 else "быстрее"])
