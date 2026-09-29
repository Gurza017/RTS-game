extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЭКОНОМИКА КРАСНОГО БЕЗ ПОДМОГИ (ТЗ 29.09.2026, второе письмо, п. 1)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: красный ИИ всю партию держит 0-3 полевых отряда. Причина — еда: с
## ТЗ 23.09 отряд и рабочий стоят еду, а у ИИ не было ни одного её источника
## (400 стартовой уходили на рабочих к 140-й секунде). Все прежние стенды ИИ
## накачивали склад или снимали мир — поломку не видел ни один.
## Здесь склад НЕ ТРОГАЕТСЯ. Живая сцена Main ускорена ×4; мир сокращён до
## PEACE_TEST_SEC (длину мира стережёт qa_ai_loop A1, здесь меряется петля
## экономики). Раз в минуту печатается склад, дома, рабочие, полевые.
## Запуск: godot --headless --path . res://qa_red_economy/Test.tscn [-- minutes=N]

const TICKS_MULT := 4
const PEACE_TEST_SEC := 300.0
var MINUTES := 12.0

var main = null
var eai = null
var _last_min: int = -1
var _done := false
var _pass := 0
var _fail := 0
var _zero_food_run := 0
var _zero_food_worst := 0
var _field_max := 0
var _houses_max := 0
var _workers_max := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("minutes="):
			MINUTES = float(s.substr(8))
	call_deferred("_run")
	get_tree().create_timer(2400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	print("\n═════ ИТОГ qa_red_economy: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	eai = main.enemy_ai
	Engine.physics_ticks_per_second = 60 * TICKS_MULT
	Engine.max_physics_steps_per_frame = 8 * TICKS_MULT
	Engine.time_scale = float(TICKS_MULT)
	print("  стенд: %.0f минут, ускорение ×%d, мир ИИ %.0f с, склад не трогается" % [MINUTES, TICKS_MULT, PEACE_TEST_SEC])

func _houses() -> int:
	return int(eai.call("_houses_count"))

func _workers() -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(u) and u is Worker and not (u as Unit).is_dead():
			n += 1
	return n

func _field() -> int:
	var n := 0
	for s in eai.squads:
		if String((s as Dictionary)["role"]) != "retreat":
			n += 1
	return n

func _process(_d: float) -> void:
	if main == null or eai == null or _done:
		return
	# Мир ИИ — короче (см. шапку): таймер мира ставится на отметку один раз
	if not eai._peace_over and float(eai._peace_timer) < 1.0:
		eai._peace_timer = maxf(0.0, _Diff_peace() - PEACE_TEST_SEC)
	var clock: float = float(main._match_clock)
	var m: int = int(clock / 60.0)
	if m == _last_min:
		return
	_last_min = m
	var food: float = ResourceManager.get_amount(Constants.FACTION_ENEMY, Constants.RESOURCE_FOOD)
	var wood: float = ResourceManager.get_amount(Constants.FACTION_ENEMY, Constants.RESOURCE_WOOD)
	var gold: float = ResourceManager.get_amount(Constants.FACTION_ENEMY, Constants.RESOURCE_GOLD)
	var stone: float = ResourceManager.get_amount(Constants.FACTION_ENEMY, Constants.RESOURCE_STONE)
	var h: int = _houses()
	var w: int = _workers()
	var f: int = _field()
	_field_max = maxi(_field_max, f)
	_houses_max = maxi(_houses_max, h)
	_workers_max = maxi(_workers_max, w)
	if m >= 4:
		if food < 36.0:
			_zero_food_run += 1
			_zero_food_worst = maxi(_zero_food_worst, _zero_food_run)
		else:
			_zero_food_run = 0
	print("  мин %2d: еда %5.0f дерево %5.0f золото %5.0f камень %5.0f | дома %d рабочих %d полевых %d мир=%s | %s" % [
		m, food, wood, gold, stone, h, w, f, str(not eai._peace_over), String(eai.last_action)])
	if float(m) >= MINUTES:
		verdict("E1 ИИ строит дома — источник еды (домов %d, нужно ≥ 4)" % _houses_max, _houses_max >= 4)
		verdict("E2 еда не сидит на нуле: худшая серия минут без еды на отряд %d (≤ 2)" % _zero_food_worst, _zero_food_worst <= 2)
		verdict("E3 бригада не меньше AI_WORKER_FLOOR (%d)" % _workers_max, _workers_max >= 8)
		verdict("E4 после мира нанята полевая армия (полевых %d, нужно ≥ 3)" % _field_max, _field_max >= 3)
		_finish()

func _Diff_peace() -> float:
	return float(load("res://scripts/game_difficulty_config.gd").ai_peace_seconds())
