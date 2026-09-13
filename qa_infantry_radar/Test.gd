extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД qa_infantry_radar — ЦЕНА ПЕРЕХВАТА ЗАСЛОНА НА МАРШЕ (blocker_reach)
## ═══════════════════════════════════════════════════════════════════════════
## Заказ: перевести проверку заслонов на двухфазный «РЛС отряда» (10 м раз в
## 2-3 с, ближний скан только при контакте). ПЕРЕД ТЕМ КАК СТРОИТЬ — МЕРИМ
## ПОТОЛОК: сколько вообще можно выиграть, если этих сканов не будет совсем.
## Никакая двухфазная схема не выиграет больше, чем их полное отсутствие.
## Тот же приём, которым измерен потолок «хака №2» (ArmyCore.SkipBodyScan).
##
##   A  СКОЛЬКО СКАНОВ И ОТКУДА — разметка мест вызова (perf_config.scan_sites)
##      на марширующей пехоте. Отвечает на вопрос «правда ли blocker_reach
##      даёт ~700 сканов/с и чьи они».
##   B  ЦЕНА ОДНОГО СКАНА — микробенч `unit_grid.best_enemy` на живой сцене
##      при радиусе перехвата пехоты (AGGRO_RADIUS) и при «упёрся телом».
##   C  ПОТОЛОК — A/B чередованием по tick_meter: штатный путь против полного
##      отсутствия таймерного скана (perf_config.march_blocker_scan = false).
##   D  ПОВЕДЕНИЕ БЕЗ СКАНА — что именно теряется: доля перехваченных на
##      марше. Скан отвечает НЕ за проход сквозь тела (его держит пакетный
##      шаг ядра), а за то, вступит ли идущий в бой с тем, мимо кого идёт.
##
## Запуск: <godot> --headless --path . res://qa_infantry_radar/Test.tscn
##         -- men=N foes=N sec=N rounds=N

const _Opt := preload("res://scripts/perf_config.gd")

const INF_SCENE := "res://scenes/units/GoblinSpearman.tscn"
const FOE_SCENE := "res://scenes/units/Spearman.tscn"

var MEN := 400
var FOES := 400
var PHASE_SEC := 6.0
var ROUNDS := 3

const COLS := 20
const GAP := 0.9
const SQUAD_SIZE := 40
const MARCH_AHEAD := 45.0
const IMMORTAL := 1e9

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _men: Array = []
var _home: Array = []
var _foes: Array = []
var _anchor: Vector3 = Vector3.ZERO
var _goal_z: float = 0.0
var _res_tick := {}
var _res_blk := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("men="):     MEN = maxi(1, int(s.substr(4)))
		elif s.begins_with("foes="):  FOES = maxi(0, int(s.substr(5)))
		elif s.begins_with("sec="):   PHASE_SEC = maxf(1.0, float(s.substr(4)))
		elif s.begins_with("rounds="): ROUNDS = maxi(1, int(s.substr(7)))
	call_deferred("_run")
	var t := get_tree().create_timer(900.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился за 900 с")
		_finish())

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
	print("\n═════ ИТОГ qa_infantry_radar: прошло %d, провалов: %d ═════" % [_pass, _fail])
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
	await _build()
	await _a_sites()
	await _b_scan_cost()
	await _c_ceiling()
	await _d_behaviour()
	await _e_flank()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# ПОСТРОЕНИЕ: ПЕХОТА ИДЁТ НА ЧУЖОЙ СТРОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _build() -> void:
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	_anchor = Vector3(base.x + 60.0, 0.0, base.z + 120.0)
	var sid: int = 0
	for i in range(MEN):
		if i % SQUAD_SIZE == 0:
			sid = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_spearman")
		var u := _spawn(INF_SCENE, Constants.FACTION_GOBLIN,
			_anchor + Vector3(float(i % COLS) * GAP, 0.0, float(i / COLS) * GAP))
		u.max_health = IMMORTAL
		u.current_health = IMMORTAL
		GameManager.add_to_squad(sid, u)
		_men.append(u)
		_home.append(u.global_position)
		if i % 50 == 0:
			await get_tree().physics_frame
	_goal_z = _anchor.z - MARCH_AHEAD
	# ── ЧУЖОЙ СТРОЙ НА ПУТИ ───────────────────────────────────────────────
	# Без него отрядный ответ `_clear_enemy` гасит скан у ВСЕХ, и зонд мерил
	# бы пустую дорогу. Строй стоит поперёк маршрута
	var fsid: int = 0
	for i in range(FOES):
		if i % SQUAD_SIZE == 0:
			fsid = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		var f := _spawn(FOE_SCENE, Constants.FACTION_PLAYER,
			Vector3(_anchor.x + float(i % COLS) * GAP, 0.0,
				_goal_z - float(i / COLS) * GAP))
		f.max_health = IMMORTAL
		f.current_health = IMMORTAL
		GameManager.add_to_squad(fsid, f)
		_foes.append(f)
		if i % 50 == 0:
			await get_tree().physics_frame
	await pframes(10)
	print("\n═════ ЗОНД ПЕРЕХВАТА НА МАРШЕ ═════")
	print("  пехоты %d (отрядами по %d), чужого строя %d; ходячих %d, ячейка сетки %.2f м" % [
		_men.size(), SQUAD_SIZE, _foes.size(), GameManager.active_units(),
		GameManager.army.grid_cell_size()])

## Вернуть пехоту на исходную и отправить маршем заново
func _reset() -> void:
	for i in range(_men.size()):
		var u := _men[i] as Unit
		if u == null or not is_instance_valid(u):
			continue
		u.current_health = IMMORTAL
		u.global_position = _home[i]
		u.set_attack_target(null)
		u.sync_row()
	for f in _foes:
		var fu := f as Unit
		if fu != null and is_instance_valid(fu):
			fu.current_health = IMMORTAL
			fu.set_attack_target(null)
	await pframes(4)
	for u in _men:
		var mu := u as Unit
		if mu != null and is_instance_valid(mu):
			mu.command_move(Vector3(mu.global_position.x, 0.0, _goal_z - 10.0))
	await pframes(4)

## mode: "base" — как в игре, "radar" — трёхточечный РЛС, "none" — потолок
func _set_mode(mode: String) -> void:
	_Opt.march_blocker_scan = mode != "none"
	_Opt.march_radar = mode == "radar"

func _measure(mode: String) -> Dictionary:
	_set_mode(mode)
	await _reset()
	await pframes(20)
	_Opt.tick_reset()
	_Opt.scan_reset()
	_Opt.tick_meter = true
	_Opt.scan_meter = true
	GameManager.march_radar_scans = 0
	var f0: int = Engine.get_physics_frames()
	await pframes(int(PHASE_SEC * 60.0))
	_Opt.tick_meter = false
	_Opt.scan_meter = false
	var game_sec: float = float(Engine.get_physics_frames() - f0) / 60.0
	var sites := {}
	var txt := ""
	for row in _Opt.scan_report():
		sites[String(row[0])] = float(row[1]) / maxf(game_sec, 0.001)
		txt += "%s=%.0f/с  " % [String(row[0]), float(row[1]) / maxf(game_sec, 0.001)]
	return {
		"tick": _Opt.tick_ms(),
		"scans": float(_Opt.scan_calls) / maxf(game_sec, 0.001),
		"blocker": float(sites.get("blocker_reach", 0.0)),
		"radar": float(GameManager.march_radar_scans) / maxf(game_sec, 0.001),
		"txt": txt,
	}

# ═════════════════════════════════════════════════════════════════════════════
# A. СКОЛЬКО СКАНОВ И ОТКУДА
# ═════════════════════════════════════════════════════════════════════════════
func _a_sites() -> void:
	print("\n── A. СКАНЫ НА МАРШЕ, ПО МЕСТАМ ВЫЗОВА")
	var r: Dictionary = await _measure("base")
	print("  всего %.0f сканов/с; %s" % [float(r["scans"]), String(r["txt"])])
	print("  на одного идущего приходится %.2f скана/с (при таймере перехвата 0.5 с)" % [
		float(r["blocker"]) / float(maxi(_men.size(), 1))])

# ═════════════════════════════════════════════════════════════════════════════
# B. ЦЕНА ОДНОГО СКАНА
# ═════════════════════════════════════════════════════════════════════════════
func _b_scan_cost() -> void:
	print("\n── B. ЦЕНА ОДНОГО `best_enemy` НА ЖИВОЙ СЦЕНЕ")
	var u := _men[0] as Unit
	if u == null:
		return
	var reach: float = u.attack_range + Unit.INTERCEPT_MARGIN
	var wide: float = Unit.AGGRO_RADIUS
	var n := 3000
	for _w in range(300):
		GameManager.unit_grid.best_enemy(u, wide, Unit.CROWD_PENALTY)
	var t0: int = Time.get_ticks_usec()
	for _i in range(n):
		GameManager.unit_grid.best_enemy(u, reach, Unit.CROWD_PENALTY)
	var us_near: float = float(Time.get_ticks_usec() - t0) / float(n)
	t0 = Time.get_ticks_usec()
	for _i in range(n):
		GameManager.unit_grid.best_enemy(u, wide, Unit.CROWD_PENALTY)
	var us_wide: float = float(Time.get_ticks_usec() - t0) / float(n)
	print("  упор r=%.1f м: %.2f мкс | марш-перехват r=%.1f м: %.2f мкс" % [
		reach, us_near, wide, us_wide])
	print("  СПРАВКА: ядро отсекает пустую округу грубой сеткой (EnemyNear) ДО")
	print("  перебора ячеек — скан по пустому полю стоит доли микросекунды")

# ═════════════════════════════════════════════════════════════════════════════
# C. ПОТОЛОК: A/B ЧЕРЕДОВАНИЕМ
# ═════════════════════════════════════════════════════════════════════════════
func _c_ceiling() -> void:
	print("
── C. A/B ЧЕРЕДОВАНИЕМ: %d раунда × 3 фазы по %.0f с" % [ROUNDS, PHASE_SEC])
	var t := {"base": 0.0, "radar": 0.0, "none": 0.0}
	var sc := {"base": 0.0, "radar": 0.0, "none": 0.0}
	var bl := {"base": 0.0, "radar": 0.0, "none": 0.0}
	var rd := {"base": 0.0, "radar": 0.0, "none": 0.0}
	var order := ["base", "radar", "none"]
	for rnd in range(ROUNDS):
		# Порядок фаз крутится: дрейф живой сцены иначе достаётся одной из них
		var seq: Array = order.slice(rnd % 3) + order.slice(0, rnd % 3)
		for mode in seq:
			var r: Dictionary = await _measure(String(mode))
			t[mode] = float(t[mode]) + float(r["tick"])
			sc[mode] = float(sc[mode]) + float(r["scans"])
			bl[mode] = float(bl[mode]) + float(r["blocker"])
			rd[mode] = float(rd[mode]) + float(r["radar"])
			print("  раунд %d | %-14s тик %5.2f мс | сканов %6.0f /с | перехват %5.0f /с | РЛС %4.0f /с" % [
				rnd + 1, _label(String(mode)), float(r["tick"]),
				float(r["scans"]), float(r["blocker"]), float(r["radar"])])
	var n := float(ROUNDS)
	for k in order:
		t[k] = float(t[k]) / n
		sc[k] = float(sc[k]) / n
		bl[k] = float(bl[k]) / n
		rd[k] = float(rd[k]) / n
	_set_mode("base")
	print("
  СВОДКА (%d идущих, %d в чужом строю):" % [_men.size(), _foes.size()])
	for k in order:
		print("    %-14s тик %5.2f мс | сканов %6.0f /с | перехват %5.0f /с | щупов РЛС %4.0f /с" % [
			_label(String(k)), float(t[k]), float(sc[k]), float(bl[k]), float(rd[k])])
	print("  РЛС против штатного: %+.2f мс/тик, перехватов %.0f -> %.0f /с (%+.1f %%)" % [
		float(t["radar"]) - float(t["base"]), float(bl["base"]), float(bl["radar"]),
		-100.0 * (1.0 - float(bl["radar"]) / maxf(float(bl["base"]), 0.001))])
	print("  ПОТОЛОК (скана нет вовсе): %+.2f мс/тик — больше этого не выиграет никакая схема" % [
		float(t["none"]) - float(t["base"])])
	_res_tick = t
	_res_blk = bl
	verdict("C1 РЛС режет число перехватов", float(bl["radar"]) < float(bl["base"]),
		"%.0f против %.0f /с" % [float(bl["radar"]), float(bl["base"])])

func _label(m: String) -> String:
	match m:
		"base": return "штатный"
		"radar": return "РЛС 3 точки"
		_: return "скана НЕТ"

# ═════════════════════════════════════════════════════════════════════════════
# D. ЧТО ТЕРЯЕТСЯ БЕЗ СКАНА
# ═════════════════════════════════════════════════════════════════════════════
func _engaged() -> int:
	var k := 0
	for u in _men:
		var mu := u as Unit
		if mu != null and is_instance_valid(mu) and mu.attack_target != null \
				and is_instance_valid(mu.attack_target):
			k += 1
	return k

## Насколько глубоко идущие зашли ЗА чужой строй (проход сквозь тела)
func _past_line() -> int:
	var k := 0
	for u in _men:
		var mu := u as Unit
		if mu != null and is_instance_valid(mu) and mu.global_position.z < _goal_z - 2.0:
			k += 1
	return k

func _d_behaviour() -> void:
	print("
── D. ПОВЕДЕНИЕ: ЧТО ДЕРЖИТ ЭТОТ СКАН")
	# МАРШ ОБЯЗАН ДОЙТИ ДО СТРОЯ. Первая версия ждала 12 с при пути в 35 м и
	# шаге 2.2 м/с — пехота не доходила, и обе проверки давали «0 против 0»,
	# то есть ЛОЖНОЕ зелёное на любом коде
	var need_f: int = int((MARCH_AHEAD / 2.0 + 12.0) * 60.0)
	var res := {}
	for mode in ["base", "radar", "none"]:
		_set_mode(String(mode))
		await _reset()
		await pframes(need_f)
		res[mode] = [_engaged(), _past_line()]
		print("  %-14s в бою %d из %d, зашло ЗА чужой строй %d" % [
			_label(String(mode)), int((res[mode] as Array)[0]), _men.size(),
			int((res[mode] as Array)[1])])
	_set_mode("base")
	var b_eng: int = int((res["base"] as Array)[0])
	var r_eng: int = int((res["radar"] as Array)[0])
	var n_eng: int = int((res["none"] as Array)[0])
	var b_past: int = int((res["base"] as Array)[1])
	var r_past: int = int((res["radar"] as Array)[1])
	var n_past: int = int((res["none"] as Array)[1])
	verdict("D0 замер состоялся: марш дошёл до чужого строя",
		b_eng > 0, "в бою %d из %d при штатном пути" % [b_eng, _men.size()])
	verdict("D1 сквозь чужой строй не проходит никто — ни с РЛС, ни без скана",
		r_past == 0 and n_past == 0 and b_past == 0,
		"за линией: штатный %d, РЛС %d, без скана %d" % [b_past, r_past, n_past])
	verdict("D2 с РЛС в бой вступает не меньше, чем при штатном пути",
		r_eng >= int(float(b_eng) * 0.9),
		"в бою %d против %d" % [r_eng, b_eng])
	# D3 СНЯТ КАК ОШИБОЧНОЕ ТРЕБОВАНИЕ. Он утверждал «без скана в бой вступает
	# меньше», а замер показал 400 из 400 во ВСЕХ трёх режимах: при марше ЛБОМ
	# в строй перехват не нужен вовсе — упор телом (`wall`, его ставит пакетный
	# шаг ядра) и авто-агро в покое делают всё сами. Таймерный скан заведён под
	# ДРУГОЙ случай — марш МИМО противника по касательной (MARCH_INTERCEPT_MELEE,
	# спринт 15), и меряет его блок E
	print("  (лбом в строй перехват не нужен вовсе: %d/%d/%d — упор телом и" % [
		b_eng, r_eng, n_eng])
	print("   авто-агро делают всё сами. Касательный марш — блок E)")

# ═════════════════════════════════════════════════════════════════════════════
# E. КАСАТЕЛЬНЫЙ МАРШ — ТО, РАДИ ЧЕГО СКАН И ЗАВЕДЁН
# ═════════════════════════════════════════════════════════════════════════════
## Отряд идёт МИМО чужой группы, отстоящей вбок на FLANK_OFFSET (внутри
## AGGRO_RADIUS, но не на пути). Лбом он в неё не упрётся — значит, `wall` не
## сработает, а авто-агро в покое не поможет: марш это MOVING. Зацепит ли?
const FLANK_OFFSET := 6.0
const FLANK_MEN := 40
const FLANK_FOES := 40

func _e_flank() -> void:
	print("
── E. МАРШ МИМО ПРОТИВНИКА (касательный перехват)")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	var spot := Vector3(base.x + 220.0, 0.0, base.z + 60.0)
	var res := {}
	for mode in ["base", "radar", "none"]:
		_set_mode(String(mode))
		var men: Array = []
		var sid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_spearman")
		for i in range(FLANK_MEN):
			var u := _spawn(INF_SCENE, Constants.FACTION_GOBLIN,
				spot + Vector3(float(i % 8) * GAP, 0.0, float(i / 8) * GAP))
			u.max_health = IMMORTAL
			u.current_health = IMMORTAL
			GameManager.add_to_squad(sid, u)
			men.append(u)
		var fsid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		var foes: Array = []
		for i in range(FLANK_FOES):
			# Вбок от маршрута: лбом отряд в них не упирается
			var f := _spawn(FOE_SCENE, Constants.FACTION_PLAYER,
				spot + Vector3(FLANK_OFFSET + float(i % 6) * GAP, 0.0,
					-25.0 - float(i / 6) * GAP))
			f.max_health = IMMORTAL
			f.current_health = IMMORTAL
			GameManager.add_to_squad(fsid, f)
			foes.append(f)
		await pframes(20)
		for u in men:
			(u as Unit).command_move(Vector3((u as Unit).global_position.x, 0.0,
				spot.z - 55.0))
		# ── МЕРИМ «КОГДА», А НЕ «СКОЛЬКО» ─────────────────────────────────
		# Первая версия считала зацепивших через 22 с — и дала 40 из 40 во
		# ВСЕХ режимах, в том числе без скана вовсе. Это правда, но не про
		# перехват: отряд доходит до точки приказа, встаёт в покой, и чужих
		# в десяти метрах подбирает обычное авто-агро. Перехват отвечает за
		# то, вступит ли отряд в бой НА ХОДУ — значит, мерить надо МОМЕНТ
		var first_f := -1
		var eng_marching := 0
		for f in range(60 * 22):
			await get_tree().physics_frame
			var e := 0
			var still_moving := false
			for u in men:
				var mu := u as Unit
				if mu == null or not is_instance_valid(mu):
					continue
				if mu.state == Unit.State.MOVING:
					still_moving = true
				if mu.attack_target != null and is_instance_valid(mu.attack_target):
					e += 1
			if e > 0 and first_f < 0:
				first_f = f
			if still_moving:
				eng_marching = maxi(eng_marching, e)
		res[mode] = eng_marching
		res[String(mode) + "_t"] = float(first_f) / 60.0 if first_f >= 0 else -1.0
		print("  %-14s зацепили НА ХОДУ: %d из %d, первый контакт на %.1f с" % [
			_label(String(mode)), eng_marching, men.size(),
			float(res[String(mode) + "_t"])])
		for u in men:
			if is_instance_valid(u):
				(u as Unit).take_damage(IMMORTAL * 10.0)
		for f in foes:
			if is_instance_valid(f):
				(f as Unit).take_damage(IMMORTAL * 10.0)
		await pframes(8)
	_set_mode("base")
	verdict("E1 штатный путь цепляет противника сбоку",
		int(res["base"]) > 0, "зацепили %d из %d" % [int(res["base"]), FLANK_MEN])
	verdict("E2 РЛС сохраняет касательный перехват",
		int(res["radar"]) >= int(int(res["base"]) * 0.8),
		"РЛС %d против штатного %d" % [int(res["radar"]), int(res["base"])])
	verdict("E3 без скана касательный перехват теряется",
		int(res["none"]) < int(res["base"]),
		"на ходу %d против %d; первый контакт %.1f против %.1f с" % [
			int(res["none"]), int(res["base"]),
			float(res["none_t"]), float(res["base_t"])])
	print("  первый контакт: штатный %.1f с | РЛС %.1f с | без скана %.1f с" % [
		float(res["base_t"]), float(res["radar_t"]), float(res["none_t"])])
