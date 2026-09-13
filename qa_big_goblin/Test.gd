extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_big_goblin — ТУША, ЕЁ СВИП И СКАН-ПО-ПЕРЕЗАРЯДКЕ
## ═══════════════════════════════════════════════════════════════════════════
##   A  ЧИСЛА    — запас = отряд гоблинов, шаг −30 %, удар ×3, стрелы ×2
##   B  ГАБАРИТ  — кликбокс, кольцо, прицел, радиус расталкивания
##   C  СВИП     — сектор перед взглядом, отброс, комбо каждый третий взмах
##   D  СКАНЫ    — сколько сканов сберегает заморозка на перезарядке
##   E  СПАВН    — пятёрки, три отряда на базе, два защитных по удару в логово
##
## «Клетка» из заказа — это МЕТР: тайловой сетки в проекте нет, расстояния
## везде в метрах (ячейка сетки соседей ядра = 1 м).
## Запуск: <godot> --headless --path . res://qa_big_goblin/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Lair   := preload("res://scripts/goblin/TrollLair.gd")
const _Opt    := preload("res://scripts/perf_config.gd")

const BIG := "res://scenes/units/BigGoblin.tscn"
const FOE := "res://scenes/units/Spearman.tscn"

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(420.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
		_finish())

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
	print("\n═════ ИТОГ qa_big_goblin: прошло %d, провалов: %d ═════" % [_pass, _fail])
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
	for _i in range(8):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	print("\n═════ qa_big_goblin ═════")
	_a_numbers()
	await _b_size()
	await _c_sweep()
	await _d_scans()
	await _e_spawn()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_numbers() -> void:
	print("\n═════ A. ЧИСЛА ═════")
	var hp: float = _UCfg.stat("big_goblin", "health", 0.0)
	var gob_hp: float = _UCfg.stat("goblin_spearman", "health", 0.0)
	var squad: int = int(_GobCfg.SQUAD_SIZE.get("goblin_spearman", 0))
	print("  запас туши %.0f; стандартный отряд орды %d × %.0f = %.0f" % [
		hp, squad, gob_hp, float(squad) * gob_hp])
	verdict("A1 запас = суммарный запас стандартного отряда гоблинов",
		absf(hp - float(squad) * gob_hp) < 1.0,
		"%.0f против %.0f" % [hp, float(squad) * gob_hp])
	verdict("A1б размер отряда орды в двух конфигах совпадает",
		squad == _UCfg.BIG_GOBLIN_HORDE_SQUAD,
		"%d против %d" % [squad, _UCfg.BIG_GOBLIN_HORDE_SQUAD])
	var sp: float = _UCfg.stat("big_goblin", "movement_speed", 0.0)
	var gob_sp: float = _UCfg.stat("goblin_spearman", "movement_speed", 0.0)
	verdict("A2 шаг на 30 % медленнее гоблинского",
		absf(sp - gob_sp * 0.7) < 0.01,
		"%.2f против %.2f (гоблин %.2f)" % [sp, gob_sp * 0.7, gob_sp])
	var dm: float = _UCfg.stat("big_goblin", "attack_1", 0.0)
	verdict("A3 удар втрое сильнее гоблинского",
		absf(dm - _UCfg.stat("goblin_spearman", "attack_1", 0.0) * 3.0) < 0.01,
		"%.0f" % dm)
	verdict("A4 перезарядка четыре секунды",
		absf(_UCfg.stat("big_goblin", "attack_cooldown", 0.0) - 4.0) < 0.01)
	verdict("A5 дальность удара 4-5 «клеток» (метров)",
		_UCfg.stat("big_goblin", "attack_range", 0.0) >= 4.0
			and _UCfg.stat("big_goblin", "attack_range", 0.0) <= 5.0,
		"%.1f м" % _UCfg.stat("big_goblin", "attack_range", 0.0))

# ═════════════════════════════════════════════════════════════════════════════
func _b_size() -> void:
	print("\n═════ B. ГАБАРИТ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(150.0, 0.0, 0.0)
	var big: Unit = _spawn(BIG, Constants.FACTION_GOBLIN, spot)
	var gob: Unit = _spawn("res://scenes/units/GoblinSpearman.tscn",
		Constants.FACTION_GOBLIN, spot + Vector3(6.0, 0.0, 0.0))
	await pframes(6)
	print("  туша: кликбокс h=%.1f r=%.1f, кольцо ×%.1f, прицел %.1f, разведение %.2f" % [
		big.pick_body_h(), big.pick_radius(), big.ring_scale(),
		big.aim_height(), big.sep_radius()])
	verdict("B1 кликбокс у туши есть (у обычного гоблина его нет вовсе)",
		big.pick_body_h() > 0.0 and big.pick_radius() > 0.0
			and gob.pick_body_h() == 0.0,
		"h=%.1f r=%.1f" % [big.pick_body_h(), big.pick_radius()])
	verdict("B2 кольцо и разведение крупнее гоблинских",
		big.ring_scale() > gob.ring_scale()
			and big.sep_radius() > gob.sep_radius(),
		"кольцо ×%.1f против ×%.1f, разведение %.2f против %.2f" % [
			big.ring_scale(), gob.ring_scale(), big.sep_radius(), gob.sep_radius()])
	verdict("B3 стрелок целится в корпус, а не в ступни",
		big.aim_height() > 1.0, "%.1f м" % big.aim_height())
	verdict("B4 спрайт втрое крупнее людского",
		absf(_GobCfg.BIG_PIXEL_SIZE / 0.0108 - 3.0) < 0.01,
		"×%.2f" % (_GobCfg.BIG_PIXEL_SIZE / 0.0108))
	# ── ×2 ОТ СТРЕЛ ───────────────────────────────────────────────────────
	verdict("B5 стрела бьёт тушу вдвое больнее",
		absf(big.ranged_damage_mult() - 2.0) < 0.01
			and absf(gob.ranged_damage_mult() - 1.0) < 0.01,
		"туша ×%.1f, гоблин ×%.1f" % [big.ranged_damage_mult(),
			gob.ranged_damage_mult()])
	big.take_damage(1e12)
	gob.take_damage(1e12)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
func _c_sweep() -> void:
	print("\n═════ C. СВИП, ОТБРОС, КОМБО ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(150.0, 0.0, 60.0)
	var big: Unit = _spawn(BIG, Constants.FACTION_GOBLIN, spot)
	big.max_health = 1e9
	big.current_health = 1e9
	# Три цели ПЕРЕД тушей в полосе «три клетки», одна ЗА спиной
	var front: Array = []
	for k in range(3):
		var f: Unit = _spawn(FOE, Constants.FACTION_PLAYER,
			spot + Vector3(float(k - 1) * 1.2, 0.0, -3.0))
		f.max_health = 1e9
		f.current_health = 1e9
		# ЗАМОРАЖИВАТЬ ЦЕЛИ НЕЛЬЗЯ: отлёт интегрирует тик ЖЕРТВЫ, и у
		# set_tick(false) сдвиг всегда 0.00 (известная ловушка спринта 15).
		# Стоять на месте их заставляет не заморозка, а отсутствие приказа
		front.append(f)
	var back: Unit = _spawn(FOE, Constants.FACTION_PLAYER,
		spot + Vector3(0.0, 0.0, 3.0))
	back.max_health = 1e9
	back.current_health = 1e9
	await pframes(10)
	# Взгляд строго вперёд и удар вручную: стенд про ГЕОМЕТРИЮ, а не про подход
	big._facing = Vector3(0.0, 0.0, -1.0)
	var hp0: Array = []
	for f in front:
		hp0.append((f as Unit).current_health)
	var back0: float = back.current_health
	var pos0: Array = []
	for f in front:
		pos0.append((f as Unit).global_position)
	big.call("_sweep_now", true)
	await pframes(30)
	var hurt := 0
	for i in range(front.size()):
		if (front[i] as Unit).current_health < float(hp0[i]) - 0.01:
			hurt += 1
	verdict("C1 свип накрывает ТРИ цели перед собой, а не одну",
		hurt == 3, "ранено %d из 3" % hurt)
	verdict("C2 за спину свип не достаёт",
		back.current_health >= back0 - 0.01,
		"тыловая цель потеряла %.1f" % (back0 - back.current_health))
	var moved := 0
	for i in range(front.size()):
		var d: float = Vector2(
			(front[i] as Unit).global_position.x - (pos0[i] as Vector3).x,
			(front[i] as Unit).global_position.z - (pos0[i] as Vector3).z).length()
		if d >= 0.3:
			moved += 1
	verdict("C3 накрытых отбрасывает назад",
		moved >= 2, "сдвинулось %d из 3" % moved)
	# ── КОМБО: КАЖДЫЙ ТРЕТИЙ ВЗМАХ ДВОЙНОЙ ────────────────────────────────
	var sw0: int = int(big.get("sweeps"))
	for k in range(_GobCfg.BIG_COMBO_EVERY):
		big.call("_strike_damage")
		await pframes(int(_GobCfg.BIG_COMBO_GAP * 60.0) + 10)
	var sw1: int = int(big.get("sweeps"))
	print("  взмахов за %d ударов: %d" % [_GobCfg.BIG_COMBO_EVERY, sw1 - sw0])
	verdict("C4 каждый третий удар — двойной взмах",
		sw1 - sw0 == _GobCfg.BIG_COMBO_EVERY + 1,
		"%d взмахов на %d ударов" % [sw1 - sw0, _GobCfg.BIG_COMBO_EVERY])
	big.take_damage(1e12)
	for f in front:
		(f as Unit).take_damage(1e12)
	back.take_damage(1e12)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# D. ЭКОНОМИЯ СКАНОВ
# ═════════════════════════════════════════════════════════════════════════════
func _d_scans() -> void:
	print("\n═════ D. СКАН-ПО-ПЕРЕЗАРЯДКЕ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(150.0, 0.0, 120.0)
	var big: Unit = _spawn(BIG, Constants.FACTION_GOBLIN, spot)
	big.max_health = 1e9
	big.current_health = 1e9
	var foe: Unit = _spawn(FOE, Constants.FACTION_PLAYER, spot + Vector3(0.0, 0.0, -3.0))
	foe.max_health = 1e12
	foe.current_health = 1e12
	# Эталон: обычный гоблин в тех же условиях
	var gob: Unit = _spawn("res://scenes/units/GoblinSpearman.tscn",
		Constants.FACTION_GOBLIN, spot + Vector3(4.0, 0.0, 0.0))
	gob.max_health = 1e9
	gob.current_health = 1e9
	_Opt.scan_reset()
	_Opt.scan_meter = true
	await pframes(60 * 12)
	_Opt.scan_meter = false
	var skipped: int = int(big.get("scans_skipped"))
	var done: int = int(big.get("scans_done"))
	var total: int = skipped + done
	var grid: int = 0
	for row in _Opt.scan_report():
		grid += int(row[1])
	print("  за 12 с боя: запросов скана у туши %d (просканировано %d, пропущено %d)" % [total, done, skipped])
	print("  сканов сетки во ВСЕЙ сцене за это время: %d" % grid)
	# ── ГЛАВНЫЙ ЗАМЕР: ПОЛЛИНГА НЕТ И БЕЗ НАШЕЙ ЗАМОРОЗКИ ────────────────
	# Базовый автомат опрашивает округу ТОЛЬКО в покое (State.IDLE): боец с
	# живой целью не сканирует вовсе. За двенадцать секунд боя туша просит
	# скан считанные разы — экономить там почти нечего, и это и есть ответ
	# на вопрос «сколько сберегает Scan-on-Cooldown» (см. отчёт)
	verdict("D1 туша в бою почти не просит сканов (поллинга нет по построению)",
		total <= 4, "запросов за 12 с боя: %d" % total)
	verdict("D2 заморозка на КД не мешает бить: цель получает урон",
		foe.current_health < 1e12 - 1.0,
		"цель потеряла %.0f" % (1e12 - foe.current_health))
	verdict("D3 счётчики скана у туши заведены и считают",
		total >= 1, "всего %d" % total)
	gob.take_damage(1e12)
	big.take_damage(1e12)
	foe.take_damage(1e13)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
func _e_spawn() -> void:
	print("\n═════ E. СПАВН ═════")
	verdict("E1 отряд туш — пятёрка",
		int(_GobCfg.SQUAD_SIZE.get("big_goblin", 0)) == 5,
		"%d" % int(_GobCfg.SQUAD_SIZE.get("big_goblin", 0)))
	var base_rows := 0
	for row in _GobCfg.START_SQUADS:
		if String((row as Dictionary).get("unit", "")) == "big_goblin":
			base_rows += 1
	verdict("E2 на базе орды три отряда туш",
		base_rows == _GobCfg.BIG_BASE_SQUADS,
		"%d отряда" % base_rows)
	# ── ЗАЩИТА ЛОГОВА ─────────────────────────────────────────────────────
	var p0: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(190.0, 0.0, 40.0)
	var lair = _Lair.new()
	lair.faction = Constants.FACTION_GOBLIN
	main.world_add(lair)
	lair.global_position = Vector3(p0.x,
		GameManager.get_terrain_height(p0.x, p0.z), p0.z)
	await pframes(8)
	var before: int = int(lair.get("big_squads_total"))
	lair.call("on_lair_attacked")
	await pframes(10)
	var after: int = int(lair.get("big_squads_total"))
	print("  отрядов туш у логова: %d → %d" % [before, after])
	verdict("E3 удар по логову мгновенно выпускает два защитных отряда",
		after - before == _GobCfg.BIG_DEFENSE_SQUADS,
		"выпущено %d" % (after - before))
	var n := 0
	for sid in lair.get("big_squads"):
		n += GameManager.squad_members(int(sid)).size()
	verdict("E4 в защитных отрядах ровно по пять туш",
		n == _GobCfg.BIG_DEFENSE_SQUADS * 5, "бойцов %d" % n)
