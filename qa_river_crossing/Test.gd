extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПЕРЕПРАВА ЧЕРЕЗ БРОД ШИРОКОЙ ГРУППОЙ (спринт 15, блок 6)
## ═══════════════════════════════════════════════════════════════════════════
## ЗАКАЗ ВЛАДЕЛЬЦА ПО СКРИНШОТУ, ДВЕ ЖАЛОБЫ СРАЗУ:
##   1. «Юниты сидят ногами в воде у береговой линии» — ходить по воде нельзя.
##   2. «Армия выстраивается в тонкую шеренгу по одному вдоль края воды» —
##      войска обязаны переходить брод плотной широкой группой, а не гуськом.
##
## ЧТО ЗДЕСЬ МЕРЯЕТСЯ И ПОЧЕМУ ИМЕННО ТАК:
##   A ДОРОГА — сама геометрия перехода (Main.ford_route) без единого бойца:
##     на одном берегу дороги нет, на разных — два конца на СУХОЙ земле и на
##     своей полосе брода. Это дешёвая проверка правила; живой отряд ниже
##     проверяет, что правило доезжает до ног.
##   B ПЕРЕПРАВА — отряд из 24 копейщиков идёт с берега на берег. Три разных
##     вопроса, и все три задаются В МИГ ПЕРЕХОДА, а не по итогу:
##     ширина фронта поперёк реки (гуськом — значит её нет), вытянутость
##     вдоль марша (ниточка — значит она огромна) и ноги в воде.
##
## МЕРИТЬ НАДО В ДИНАМИКЕ, А НЕ СНИМКОМ В КОНЦЕ. «Гуськом» — это СОБЫТИЕ на
## переправе: к концу пути отряд смыкается сам, и по итоговому снимку строй
## всегда выглядит целым (та же оговорка, что у просачивания в qa_mega_battle).
##
## Числа берутся из констант Main (правило 10), ожидание — физкадрами
## (правило 11). Вода — правило партии, поэтому границы мира включаются явно.
## Запуск: godot --headless --path . res://qa_river_crossing/Test.tscn

## Сколько бойцов ведём через брод
const MEN := 24
## Раскладка стартового блока: колонн поперёк реки (по Z) × шеренг вдоль марша
const COLS := 6
const RANKS := 4
const SPACING := 1.2
## Доля исходной ширины фронта, ниже которой переправа считается «ниточкой»
const WIDTH_KEEP := 0.6
## Во сколько раз отряду позволено быть длиннее вдоль марша, чем поперёк него
const THREAD_RATIO := 2.5

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(300.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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
	print("\n═════ ИТОГ qa_river_crossing: прошло %d, провалов: %d ═════"
		% [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

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
	# ВОДА — ПРАВИЛО ПАРТИИ, КАК И ГРАНИЦЫ МИРА: стенд, снявший границы, реки
	# не видит вовсе (см. GameManager.water_active и оба пакетных прохода)
	GameManager.world_bounds_enabled = true
	await pframes(4)
	_check_route()
	await _check_crossing()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ДОРОГА ЧЕРЕЗ БРОД — ЧИСТАЯ ГЕОМЕТРИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _check_route() -> void:
	print("\n═════ A. ДОРОГА ═════")
	var z0: float = main.FORD_Z - main.FORD_HALF - 40.0
	var ax: float = main.river_x(z0)
	var off: float = main.RIVER_HALF_W + main.RIVER_BANK + 6.0
	var west := Vector3(ax - off, 0.0, z0)
	var east := Vector3(ax + off, 0.0, z0)

	verdict("A1 на своём берегу дороги через брод нет",
		main.ford_route(west, west + Vector3(-20.0, 0.0, 10.0), 0.0).is_empty())
	var r: Array = main.ford_route(west, east, 0.0)
	verdict("A2 на другой берег дорога есть, и она из двух концов", r.size() == 2,
		"концов %d" % r.size())
	if r.size() != 2:
		return
	var a: Vector3 = r[0]
	var b: Vector3 = r[1]
	print("  вход %s, выход %s" % [str(a), str(b)])
	verdict("A3 оба конца — СУХАЯ земля",
		not main.is_water(a.x, a.z) and not main.is_water(b.x, b.z))
	verdict("A4 концы по разные стороны русла",
		signf(a.x - main.river_x(a.z)) == -signf(b.x - main.river_x(b.z)),
		"%.1f и %.1f от оси" % [a.x - main.river_x(a.z), b.x - main.river_x(b.z)])
	verdict("A5 вход на своём берегу, а не за рекой",
		signf(a.x - main.river_x(a.z)) == signf(west.x - main.river_x(west.z)))
	verdict("A6 дорога идёт полосой брода", main.in_ford(a.z) and main.in_ford(b.z),
		"z входа %.1f, брод ±%.0f" % [a.z, main.FORD_HALF])
	# ── СВОЯ ПОЛОСА У КАЖДОГО: ЭТИМ И ДЕРЖИТСЯ ШИРИНА ФРОНТА ──────────────
	# Если бы дорога у всех была одна, отряд входил бы в воду по одному — ровно
	# та жалоба, ради которой всё и писалось
	var r_left: Array = main.ford_route(west, east, -6.0)
	var r_right: Array = main.ford_route(west, east, 6.0)
	verdict("A7 смещение бойца в отряде переносится на его полосу брода",
		r_left.size() == 2 and r_right.size() == 2
			and absf((r_right[0] as Vector3).z - (r_left[0] as Vector3).z - 12.0) < 0.01,
		"разнос полос %.2f м" % ((r_right[0] as Vector3).z - (r_left[0] as Vector3).z
			if r_left.size() == 2 and r_right.size() == 2 else -1.0))
	# …но не шире самого брода: крайняя полоса обязана остаться на мелководье
	var r_far: Array = main.ford_route(west, east, main.FORD_HALF * 4.0)
	verdict("A8 полоса зажата шириной брода",
		r_far.size() == 2 and main.in_ford((r_far[0] as Vector3).z)
			and absf((r_far[0] as Vector3).z - main.FORD_Z)
				<= main.FORD_HALF - main.FORD_LANE_MARGIN + 0.01,
		"z %.1f" % ((r_far[0] as Vector3).z if r_far.size() == 2 else 0.0))
	# Оба конца в полосе брода — вести некуда, отрезок из неё не выходит
	var in_a := Vector3(main.river_x(main.FORD_Z) - off, 0.0, main.FORD_Z)
	var in_b := Vector3(main.river_x(main.FORD_Z) + off, 0.0, main.FORD_Z)
	verdict("A9 внутри брода дорога не нужна",
		main.ford_route(in_a, in_b, 0.0).is_empty())

# ═════════════════════════════════════════════════════════════════════════════
# B. ПЕРЕПРАВА ЖИВОГО ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _check_crossing() -> void:
	print("\n═════ B. ПЕРЕПРАВА ОТРЯДОМ ═════")
	# Отряд ставим ДАЛЕКО от брода по Z: иначе он перешёл бы напрямую, и
	# проверять было бы нечего. ПО +Z, а не по −Z (спринт 18): на −58 стоит
	# плато рудника, и со скалами (Main.CLIFFS_ENABLED) отряд обходит его
	# кольцом до спуска — переправа честно идёт, но в бюджет замера не
	# укладывается; по +Z площадка ровная
	var z0: float = main.FORD_Z + main.FORD_HALF + 40.0
	var ax: float = main.river_x(z0)
	var off: float = main.RIVER_HALF_W + main.RIVER_BANK + 14.0
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array[Unit] = []
	for i in range(MEN):
		var col: int = i % COLS
		var rank: int = i / COLS
		var px: float = ax - off - float(rank) * SPACING
		var pz: float = z0 + (float(col) - float(COLS - 1) * 0.5) * SPACING
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(6)

	var w0: float = _spread(men).y
	var goal := Vector3(ax + off, 0.0, z0)
	# ── ПРИКАЗ ПЕРЕНОСИТ СТРОЙ ЦЕЛИКОМ ────────────────────────────────────
	# Каждому даётся ЕГО точка, смещённая на тот же вектор, каким сдвигается
	# центр отряда, — тот же приём, что у переноса стены (Unit._wall_goal).
	# Одна общая точка на всех схлопнула бы отряд сама, и стенд мерил бы
	# собственную раскладку, а не переправу
	var c0: Vector2 = GameManager.squad_centre_xz(sid)
	for u in men:
		var p: Vector3 = u.global_position
		var tgt := Vector3(goal.x + (p.x - c0.x), 0.0, goal.z + (p.z - c0.y))
		u.command_move(GameManager.land_target(tgt), false, Vector3.ZERO, false, true)

	var wet_frames: int = 0
	var wet_men: int = 0
	var worst_ratio: float = 0.0
	var narrow: float = 1e9
	var seen_cross: bool = false
	var waited: int = 0
	while waited < 60 * 180:
		await get_tree().physics_frame
		waited += 1
		var alive: Array[Unit] = []
		for u in men:
			if is_instance_valid(u) and not u.is_dead():
				alive.append(u)
		if alive.is_empty():
			break
		# Ноги в воде — считаем ЛЮДЕЙ, а не кадры: один и тот же зашедший
		# в реку давал бы сотню кадров и выглядел бы сотней нарушителей
		var wet_now: int = 0
		for u in alive:
			var p: Vector3 = u.global_position
			if main.is_water(p.x, p.z):
				wet_now += 1
		if wet_now > 0:
			wet_frames += 1
			wet_men = maxi(wet_men, wet_now)
		# ── МИГ ПЕРЕХОДА: ЦЕНТР ОТРЯДА НАД РУСЛОМ ─────────────────────────
		var c: Vector2 = GameManager.squad_centre_xz(sid)
		if c.x != INF and absf(c.x - main.river_x(c.y)) < main.RIVER_HALF_W:
			seen_cross = true
			var sp: Vector2 = _spread(alive)
			narrow = minf(narrow, sp.y)
			if sp.y > 0.01:
				worst_ratio = maxf(worst_ratio, sp.x / sp.y)
		if _done(alive, goal.x, ax):
			break
	var arrived: int = 0
	for u in men:
		if is_instance_valid(u) and not u.is_dead() \
				and u.global_position.x > ax + main.RIVER_HALF_W:
			arrived += 1
	print("  переправа: %d физкадров, на том берегу %d из %d" % [waited, arrived, MEN])
	print("  фронт до приказа %.1f м, самый узкий на переправе %.1f м, вытянутость ×%.1f"
		% [w0, narrow if narrow < 1e8 else -1.0, worst_ratio])
	print("  кадров с ногами в воде %d, худший разом %d человек" % [wet_frames, wet_men])

	verdict("B1 отряд перешёл на другой берег", arrived >= MEN - 2,
		"дошло %d из %d" % [arrived, MEN])
	verdict("B2 замер переправы состоялся (центр отряда был над руслом)", seen_cross)
	verdict("B3 никто не идёт по воде", wet_men == 0,
		"худший кадр: %d человек в воде" % wet_men)
	verdict("B4 фронт на переправе не схлопнулся в ниточку",
		seen_cross and narrow >= w0 * WIDTH_KEEP,
		"%.1f м против %.1f м до приказа" % [narrow if narrow < 1e8 else -1.0, w0])
	verdict("B5 отряд переходит группой, а не гуськом",
		seen_cross and worst_ratio <= THREAD_RATIO,
		"вдоль марша ×%.1f поперёк (предел ×%.1f)" % [worst_ratio, THREAD_RATIO])
	for u in men:
		if is_instance_valid(u):
			u.take_damage(1e9)
	await pframes(2)

## Габарит группы: x — вдоль марша, y — поперёк реки (по Z)
func _spread(men: Array) -> Vector2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for u in men:
		var p: Vector3 = (u as Unit).global_position
		lo.x = minf(lo.x, p.x); hi.x = maxf(hi.x, p.x)
		lo.y = minf(lo.y, p.z); hi.y = maxf(hi.y, p.z)
	return hi - lo

## Все ли добрались на тот берег и встали
func _done(alive: Array, goal_x: float, axis_x: float) -> bool:
	for u in alive:
		var p: Vector3 = (u as Unit).global_position
		if p.x < axis_x + main.RIVER_HALF_W:
			return false
		if absf(p.x - goal_x) > 6.0:
			return false
	return true
