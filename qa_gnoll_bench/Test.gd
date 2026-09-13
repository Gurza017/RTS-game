extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД qa_gnoll_bench — ЦЕНА ТИКА ГНОЛЛА (аудит класса, сент. 2026)
## ═══════════════════════════════════════════════════════════════════════════
## Вердиктов НЕТ — это измеритель, а не проверка, и в шлюз он не входит.
## Отвечает на один вопрос: почему тик гнолла стоит вдесятеро дороже тика
## гоблина-копейщика (стресс-отчёт спринта 20: 0.056 против 0.007 мс).
##
##   A  ЦЕНА ОДНОГО СКАНА — `army.nearest_of_side` на живой сцене при радиусах
##      кайта (GNOLL_KITE_IN) и обороны пня (GNOLL_DEFEND_RANGE). Сетка ядра
##      квадратная, с ячейкой 1 м: цена растёт как r², и разница радиусов
##      6 и 34 м — это не «вшестеро», а тридцать два раза по площади.
##   B  ЦЕНА ТИКА ПО РОДАМ — class_meter на РАВНЫХ условиях: гноллы и
##      гоблины-копейщики стоят в одной куче у пня, врагов рядом нет.
##      Это и есть штатное состояние стаи большую часть партии.
##   C  ТО ЖЕ С ВРАГОМ У ПНЯ — взведённый фланг против невзведённого.
##   D  A/B ГЕЙТА СКАНОВ (`perf_config.gnoll_scan_gate`) ЧЕРЕДОВАНИЕМ.
##
## Сцена держится В ПОЛЕ КАРТЫ намеренно: габарит армии задаёт размер ячейки
## сетки ядра (ArmyCore: cell удваивается, пока w×h не влезет в MaxCells), и
## зонд, поставивший бойцов за тысячу метров от карты, померил бы ячейку 4 м
## вместо игровой 1 м — то есть скан вшестнадцатеро дешевле настоящего.
## Запуск: godot --headless --path . res://qa_gnoll_bench/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Opt    := preload("res://scripts/perf_config.gd")
const _Lair   := preload("res://scripts/goblin/TrollLair.gd")

const GNOLLS := 20
const GOBS   := 20
const WARM_FRAMES := 40
const MEASURE_FRAMES := 240

var main = null
var _lair = null
var _gnolls: Array = []
var _gobs: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(420.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился за 420 с")
		get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var sc: PackedScene = Building.PRELOAD_SCENES.get(uid)
	if sc == null:
		return null
	var u: Unit = sc.instantiate()
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

	# ── ПЛОЩАДКА В ПОЛЕ КАРТЫ ─────────────────────────────────────────────
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	var spot := Vector3(base.x + 70.0, 0.0, base.z + 70.0)
	_lair = _Lair.new()
	_lair.faction = Constants.FACTION_GOBLIN
	main.world_add(_lair)
	_lair.global_position = Vector3(spot.x,
		GameManager.get_terrain_height(spot.x, spot.z), spot.z)
	await pframes(4)
	# Свою стаю логово заводит само; её состав задаёт конфиг, а нам нужно
	# ровно GNOLLS штук — прежнюю уводим с площадки
	for raw in _lair.gnolls.duplicate():
		if raw != null and is_instance_valid(raw):
			(raw as Unit).take_damage(1e9)
	for raw in _lair.trolls.duplicate():
		if raw != null and is_instance_valid(raw):
			(raw as Unit).take_damage(1e9)
	await pframes(4)

	for i in range(GNOLLS):
		var a: float = TAU * float(i) / float(GNOLLS)
		var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN,
			spot + Vector3(cos(a) * 7.0, 0.0, sin(a) * 7.0))
		if g == null:
			print("  сцены gnoll нет в PRELOAD_SCENES — зонд бесполезен")
			get_tree().quit()
			return
		g.set("lair", _lair)
		_gnolls.append(g)
	for i in range(GOBS):
		var a2: float = TAU * float(i) / float(GOBS)
		var s: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN,
			spot + Vector3(cos(a2) * 12.0, 0.0, sin(a2) * 12.0))
		if s != null:
			_gobs.append(s)
	await pframes(WARM_FRAMES)

	print("\n═════ ЗОНД ЦЕНЫ ГНОЛЛА ═════")
	print("  сетка ядра: ячейка %.2f м, ячеек %d, строк %d" % [
		GameManager.army.grid_cell_size(), GameManager.army.grid_cells(),
		GameManager.army.top()])
	print("  гноллов %d, гоблинов-копейщиков %d, ходящих %d" % [
		_gnolls.size(), _gobs.size(), GameManager.active_units()])

	await _a_scan_cost()
	await _b_idle_cost()
	await _c_with_foe()
	await _d_ab_gate()
	print("\n═════ ИТОГ qa_gnoll_bench: измеритель, вердиктов нет ═════")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ЦЕНА ОДНОГО nearest_of_side
# ═════════════════════════════════════════════════════════════════════════════
func _bench_scan(r: float, n: int) -> float:
	var p: Vector3 = _lair.global_position
	var t0: int = Time.get_ticks_usec()
	for _i in range(n):
		for f in Constants.other_factions(Constants.FACTION_GOBLIN):
			GameManager.army.nearest_of_side(p.x, p.z, int(f), r)
	return float(Time.get_ticks_usec() - t0) / float(n)

func _a_scan_cost() -> void:
	print("\n── A. ЦЕНА СКАНА (мкс на ОДИН заход из кода гнолла: две чужие стороны)")
	var n := 2000
	_bench_scan(_GobCfg.GNOLL_KITE_IN, 200)
	var us_kite: float = _bench_scan(_GobCfg.GNOLL_KITE_IN, n)
	var us_def: float = _bench_scan(_GobCfg.GNOLL_DEFEND_RANGE, n)
	var cell: float = maxf(GameManager.army.grid_cell_size(), 0.01)
	var c_kite: float = pow(2.0 * _GobCfg.GNOLL_KITE_IN / cell + 1.0, 2.0)
	var c_def: float = pow(2.0 * _GobCfg.GNOLL_DEFEND_RANGE / cell + 1.0, 2.0)
	print("  кайт    r=%.0f м: %6.2f мкс  (ячеек в квадрате скана ~%d × 2 стороны)" % [
		_GobCfg.GNOLL_KITE_IN, us_kite, int(c_kite)])
	print("  оборона r=%.0f м: %6.2f мкс  (ячеек в квадрате скана ~%d × 2 стороны)" % [
		_GobCfg.GNOLL_DEFEND_RANGE, us_def, int(c_def)])
	print("  отношение по времени %.1f×, по площади %.1f×" % [
		us_def / maxf(us_kite, 0.001), c_def / maxf(c_kite, 0.001)])

# ═════════════════════════════════════════════════════════════════════════════
# B. ЦЕНА ТИКА: ГНОЛЛ ПРОТИВ ГОБЛИНА В ОДНИХ УСЛОВИЯХ
# ═════════════════════════════════════════════════════════════════════════════
func _measure(label: String) -> Dictionary:
	_Opt.class_reset()
	_Opt.class_meter = true
	await pframes(MEASURE_FRAMES)
	_Opt.class_meter = false
	var out := {}
	for r in _Opt.class_report():
		out[String(r[0])] = [float(r[1]), float(r[2]), int(r[3])]
	var g: Array = out.get("gnoll", [0.0, 0.0, 0])
	var s: Array = out.get("goblin_spearman", [0.0, 0.0, 0])
	print("  %-22s гнолл %6.2f мкс/тик (%.2f мс/кадр) | гоблин %5.2f мкс/тик (%.2f мс/кадр) | ×%.1f" % [
		label, float(g[1]), float(g[0]), float(s[1]), float(s[0]),
		float(g[1]) / maxf(float(s[1]), 0.01)])
	return out

func _b_idle_cost() -> void:
	print("\n── B. ТИК В ПОКОЕ У ПНЯ (врагов на карте рядом нет)")
	await _measure("покой/патруль:")

# ═════════════════════════════════════════════════════════════════════════════
# C. ВРАГ У ПНЯ
# ═════════════════════════════════════════════════════════════════════════════
func _c_with_foe() -> void:
	print("\n── C. ТИК, КОГДА ВРАГ У ПНЯ (фланг взводится, кайт ищет)")
	var at: Vector3 = _lair.global_position + Vector3(18.0, 0.0, 0.0)
	var e: Unit = _spawn("spearman", Constants.FACTION_PLAYER, at)
	if e != null:
		e.set_tick(false)
		e.max_health = 1e12
		e.current_health = e.max_health
	await pframes(20)
	await _measure("враг в 18 м от пня:")
	if e != null and is_instance_valid(e):
		e.take_damage(1e15)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# D. A/B ГЕЙТА СКАНОВ ЧЕРЕДОВАНИЕМ
# ═════════════════════════════════════════════════════════════════════════════
func _d_ab_gate() -> void:
	print("\n── D. A/B ГЕЙТА СКАНОВ, 3 раунда чередованием (покой у пня)")
	var base_sum := 0.0
	var fix_sum := 0.0
	for rnd in range(3):
		# Порядок фаз переворачивается: дрейф живой сцены иначе систематически
		# достаётся одной из них (правило qa_ab)
		var first_fix: bool = (rnd % 2) == 1
		for phase in range(2):
			var on: bool = first_fix if phase == 0 else not first_fix
			_Opt.gnoll_scan_gate = on
			await pframes(20)
			var r: Dictionary = await _measure(
				("гейт ВКЛ:" if on else "гейт выкл:"))
			var us: float = float((r.get("gnoll", [0.0, 0.0, 0]) as Array)[1])
			if on: fix_sum += us
			else:  base_sum += us
	_Opt.gnoll_scan_gate = false
	print("  ИТОГ A/B: без гейта %.2f мкс/тик, с гейтом %.2f мкс/тик (−%.0f %%)" % [
		base_sum / 3.0, fix_sum / 3.0,
		100.0 * (1.0 - (fix_sum / 3.0) / maxf(base_sum / 3.0, 0.01))])
