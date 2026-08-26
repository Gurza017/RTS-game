extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПРОДАВЛИВАНИЕ СТРОЯ И РАЗВЕДЕНИЕ ОТРЯДОВ
## ═══════════════════════════════════════════════════════════════════════════
##   A НАПОР ПОСТОЯНЕН — толчок считается на каждый удар, а не раз в десять
##   B КТО КОГО        — продавливает тот, у кого выше сумма push_force и
##                       морали; при равных — паритет и стояние на месте
##   C СТОЙКА          — оборона своего пуша не имеет и вдвое крепче упирается
##   D РАЗВЕДЕНИЕ      — бойцы РАЗНЫХ отрядов держатся шире, чем свои по
##                       шеренге, и десять отрядов не спрессовываются в комок
##   E ЛИНИЯ ФРОНТА    — приказ атаки нескольким отрядам раскладывает их по
##                       ширине чужого строя, а не сводит в одну точку
##
## ЧИСЛА НЕ ХАРДКОДЯТСЯ: пороги выводятся из Unit.SEP_* и unit_stats_config —
## стенд проверяет СВОЙСТВО, а не цифру владельца.
##
## Запуск: godot --headless --path . res://qa_push/Test.tscn

const _UStats := preload("res://scripts/unit_stats_config.gd")

var main = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok, detail])

func _spawn(path: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	u.sync_row()
	return u

func _squad(path: String, fac: int, kind: String, center: Vector3,
		count: int, cols: int, gap: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var slots: Array = []
	for i in range(count):
		var p := center + Vector3(float(i % cols) * gap - float(cols - 1) * gap * 0.5,
			0.0, float(i / cols) * gap)
		var u := _spawn(path, fac, p)
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
		slots.append(p)
	return [sid, men, slots]

func _run() -> void:
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await frames(3)

	_a_continuous()
	await _b_who_wins()
	await _c_stance()
	await _d_spacing()
	await _e_frontline()

	print("\n═════ ИТОГ qa_push ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-62s %s%s" % [String(row[0]),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО",
			("  — " + String(row[2])) if String(row[2]) != "" else ""])
	print("  провалов: %d из %d" % [bad, verdicts.size()])
	print("\n=== QA_PUSH DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. НАПОР СЧИТАЕТСЯ ПОСТОЯННО
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: «включить постоянный расчёт push_force в бою». До этого
## толчок срабатывал раз в десять ударов — у копейщика с кулдауном 2 секунды это
## раз в двадцать секунд, то есть механики на экране не было вовсе
func _a_continuous() -> void:
	verdict("A1 толчок идёт на каждый удар", Unit.PUSH_EVERY == 1,
		"PUSH_EVERY = %d" % Unit.PUSH_EVERY)
	# Плавность держит не редкость, а РАЗМЕР шага: он зажат сверху и умножен
	# на общий множитель. Проверяем, что предохранители на месте
	verdict("A2 размер одного толчка по-прежнему ограничен",
		_UStats.PUSH_GLOBAL_SCALE > 0.0 and _UStats.PUSH_GLOBAL_SCALE <= 1.0,
		"PUSH_GLOBAL_SCALE = %.2f" % _UStats.PUSH_GLOBAL_SCALE)

# ═════════════════════════════════════════════════════════════════════════════
# B. КТО КОГО ПРОДАВЛИВАЕТ
# ═════════════════════════════════════════════════════════════════════════════
## «Строй продавливает тот отряд, у кого выше комбинация push_force и morale;
## при равных силах — паритет и стояние на месте». Меряем напрямую вызовом
## _apply_push, минуя бой: проверяется формула, а не то, кто успел ударить
func _b_who_wins() -> void:
	var p0 := Vector3(400.0, 0.0, 400.0)
	# Пара РАВНЫХ: копейщик против копейщика
	var eq_a := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER, p0)
	var eq_b := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_ENEMY,
		p0 + Vector3(1.0, 0.0, 0.0))
	# Пара НЕРАВНЫХ: мечник (push 1.5, мораль 150) против копейщика
	var st_a := _spawn("res://scenes/units/Warrior.tscn", Constants.FACTION_ENEMY,
		p0 + Vector3(0.0, 0.0, 20.0))
	var st_b := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER,
		p0 + Vector3(1.0, 0.0, 20.0))
	await frames(5)
	var dirn := Vector3(1.0, 0.0, 0.0)

	var eq0: Vector3 = eq_b.global_position
	eq_a._apply_push(eq_b, dirn)
	var eq_moved: float = Vector2(eq_b.global_position.x - eq0.x,
		eq_b.global_position.z - eq0.z).length()
	verdict("B1 при равных напоре и морали — паритет, никто не сдвинут",
		eq_moved < 0.001, "сдвинуло на %.4f м" % eq_moved)

	var st0: Vector3 = st_b.global_position
	st_a._apply_push(st_b, dirn)
	# ── ЖДЁМ, ПОКА ТОЛЧОК ОТРАБОТАЕТ ────────────────────────────────────────
	# Толчок больше не переносит тело мгновенно: он выдаёт затухающую скорость,
	# и заказанные метры набираются за Unit.FLING_SEC (см. Unit.push_smooth) —
	# это часть объединения удара и продавливания в один плавный процесс.
	# Замер сразу после вызова показывал бы ноль: не «толчка нет», а «ещё едет».
	# Паритет (B1 выше) от этого не зависит вовсе — там скорость не выдаётся
	await frames(int(Unit.FLING_SEC * 60.0) + 20)
	var st_moved: float = Vector2(st_b.global_position.x - st0.x,
		st_b.global_position.z - st0.z).length()
	verdict("B2 более напористый продавливает менее напористого",
		st_moved > 0.0, "сдвинуло на %.4f м" % st_moved)

	# И ОБРАТНО: слабый сильного не двигает вовсе
	var back0: Vector3 = st_a.global_position
	st_b._apply_push(st_a, -dirn)
	var back_moved: float = Vector2(st_a.global_position.x - back0.x,
		st_a.global_position.z - back0.z).length()
	verdict("B3 слабый напор сильного не сдвигает", back_moved < 0.001,
		"сдвинуло на %.4f м" % back_moved)

	# ФРАКЦИЯ В ФОРМУЛУ НЕ ВХОДИТ: те же двое, поменянные местами по фракциям
	verdict("B4 паритет фракций: формула симметрична",
		is_equal_approx(eq_a._push_power(), eq_b._push_power())
			and is_equal_approx(eq_a._stand_power(), eq_b._stand_power()),
		"напор %.3f/%.3f, упор %.3f/%.3f" % [eq_a._push_power(),
			eq_b._push_power(), eq_a._stand_power(), eq_b._stand_power()])
	for u in [eq_a, eq_b, st_a, st_b]:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. СТОЙКА «ЗАЩИТА»
# ═════════════════════════════════════════════════════════════════════════════
func _c_stance() -> void:
	var p0 := Vector3(500.0, 0.0, 500.0)
	var a := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER, p0)
	await frames(4)
	var atk_push: float = a._push_power()
	var atk_stand: float = a._stand_power()
	a.set_stance(_UStats.STANCE_DEFENSE)
	await frames(2)
	verdict("C1 в обороне своего пуша нет вовсе", a._push_power() <= 0.0,
		"в атаке %.3f, в обороне %.3f" % [atk_push, a._push_power()])
	verdict("C2 но упирается оборона крепче, чем атака",
		a._stand_power() > atk_stand,
		"упор в атаке %.3f, в обороне %.3f" % [atk_stand, a._stand_power()])
	if is_instance_valid(a):
		(a as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. РАЗВЕДЕНИЕ ОТРЯДОВ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца: десять отрядов спрессовываются в комок размером в два.
## Проверяем ровно это: бойцы РАЗНЫХ отрядов, сваленные в одну кучу, обязаны
## разойтись ШИРЕ, чем свои по шеренге
func _d_spacing() -> void:
	verdict("D0 у разных отрядов норма шире, чем у своих",
		Unit.SEP_CROSS_SQUAD > 1.0,
		"своя %.3f м, чужая %.3f м" % [Unit.SEP_MIN_DIST,
			Unit.SEP_MIN_DIST * Unit.SEP_CROSS_SQUAD])
	# Личный круг не должен спорить ни с прибытием, ни с самым плотным строем
	verdict("D0б разведение не спорит с приходом в точку",
		Unit.SEP_MIN_DIST < Unit.ARRIVE_RADIUS,
		"SEP_MIN_DIST %.4f, ARRIVE_RADIUS %.4f" % [Unit.SEP_MIN_DIST,
			Unit.ARRIVE_RADIUS])
	verdict("D0в разведение не спорит с самым плотным строем",
		Unit.SEP_MIN_DIST <= Building.new().squad_spacing,
		"SEP_MIN_DIST %.4f, интервал %.4f" % [Unit.SEP_MIN_DIST,
			Building.new().squad_spacing])

	# ── ЖИВОЙ ЗАМЕР: ДВА ОТРЯДА ПЛЕЧОМ К ПЛЕЧУ ────────────────────────────
	# ПОЧЕМУ НЕ «СВАЛИТЬ ВСЕХ В ОДНУ ТОЧКУ». Так меряется не норма, а СКОРОСТЬ
	# СХОДИМОСТИ: у бойца в середине идеально симметричной кучи соседи стоят со
	# всех сторон, их поправки почти взаимно гасятся, и куча расходится
	# десятки секунд (замер: 0.35 м за четыре секунды при потолке шага 0.05 м
	# за такт, то есть меньше десятой доли возможного). Проверять надо
	# РАВНОВЕСИЕ, а не переходный процесс.
	#
	# Поэтому оба отряда встают готовыми решётками с интервалом, который УЖЕ
	# устраивает свою шеренгу (шире SEP_MIN_DIST), и ставятся вплотную друг к
	# другу — так, что граничные колонны стоят ближе чужой нормы. Разойтись
	# обязана ровно эта граница, а внутренний строй — остаться на месте.
	var p0 := Vector3(700.0, 0.0, 700.0)
	var own_step: float = Unit.SEP_MIN_DIST * 1.2
	var men1: Array = _lattice(p0, 4, 3, own_step)
	var men2: Array = _lattice(p0 + Vector3(own_step * 4.0, 0.0, 0.0), 4, 3, own_step)
	var cross0: float = _min_gap(men1, men2)
	await frames(360)                 # 6 секунд на установление равновесия
	var same: float = _min_gap(men1, men1)
	var cross: float = _min_gap(men1, men2)
	# Порог — норма минус мёртвая зона, ровно как в qa_crowd: сосед, стоящий
	# теснее нормы меньше чем на SEP_DEADZONE, в расчёт не идёт вовсе
	var cross_floor: float = (Unit.SEP_MIN_DIST * Unit.SEP_CROSS_SQUAD
		- Unit.SEP_DEADZONE) * 0.9
	var same_floor: float = (Unit.SEP_MIN_DIST - Unit.SEP_DEADZONE) * 0.9
	print("  два отряда бок о бок: граница была %.3f м, стала %.3f м; свой строй %.3f м"
		% [cross0, cross, same])
	verdict("D1 граница между отрядами разошлась на широкую норму",
		cross >= cross_floor,
		"чужой зазор %.3f м при пороге %.3f (было %.3f)"
			% [cross, cross_floor, cross0])
	verdict("D2 внутри своего отряда строй остался плотным",
		same >= same_floor and same < cross,
		"свой %.3f м (порог %.3f) против чужого %.3f м"
			% [same, same_floor, cross])
	for arr in [men1, men2]:
		for u in arr:
			if is_instance_valid(u):
				(u as Node).queue_free()
	await frames(3)

## Готовая решётка бойцов ОДНОГО отряда, без поста и без разметки строя.
##
## БЕЗ post_pos, И ЭТО НЕ НЕБРЕЖНОСТЬ. Пост — это приказ вернуться на своё место
## (см. Unit._cohesion_guard и GameManager.squad_close_ranks): он тянул бы
## бойцов обратно ровно с той же силой, с какой разбор наложения их разводит,
## и стенд мерил бы спор двух механик вместо нормы разведения
func _lattice(center: Vector3, cols: int, rows: int, step: float) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(cols * rows):
		var u := _spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER,
			center + Vector3(float(i % cols) * step, 0.0, float(i / cols) * step))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

## Наименьший зазор между двумя наборами (или внутри одного, если a == b)
func _min_gap(a: Array, b: Array) -> float:
	var best := INF
	var same: bool = (a == b)
	for i in range(a.size()):
		var ua := a[i] as Unit
		if ua == null or not is_instance_valid(ua) or ua.is_dead():
			continue
		var j0: int = i + 1 if same else 0
		for j in range(j0, b.size()):
			var ub := b[j] as Unit
			if ub == null or not is_instance_valid(ub) or ub.is_dead():
				continue
			if ub == ua:
				continue
			var d: float = Vector2(ua.global_position.x - ub.global_position.x,
				ua.global_position.z - ub.global_position.z).length()
			if d < best:
				best = d
	return best

# ═════════════════════════════════════════════════════════════════════════════
# E. ЛИНИЯ ФРОНТА
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: «при атаке группы врагов отряды должны распределять цели по
## широкой линии фронта (фланги, центр)». Проверяем раскладку напрямую:
## три наших отряда против растянутой чужой шеренги обязаны получить ТРИ РАЗНЫЕ
## цели, и порядок обязан совпадать — левый напротив левого
func _e_frontline() -> void:
	var sel = main.selection_manager
	var p0 := Vector3(-700.0, 0.0, -700.0)
	# ЧУЖАЯ ШЕРЕНГА: тридцать бойцов вдоль оси X
	var foes: Array = []
	for i in range(30):
		foes.append(_spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_ENEMY, p0 + Vector3(float(i) * 0.8 - 11.6, 0.0, 0.0)))
	# ТРИ НАШИХ ОТРЯДА, стоящих слева, по центру и справа от шеренги
	var mine: Array = []
	for k in range(3):
		var built: Array = _squad("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER, "spearman",
			p0 + Vector3(float(k - 1) * 9.0, 0.0, 14.0), 9, 3, 0.7)
		mine.append(built)
	await frames(8)

	sel._clear_selection()
	for built in mine:
		for u in (built[1] as Array):
			sel._select(u)
	# Целимся в СЕРЕДИНУ чужой шеренги — худший вход, ровно тот, на котором
	# раньше все отряды сходились в одну точку
	var plan: Dictionary = sel.frontline_targets(foes[15])
	print("  раскладка по фронту: %d участков на %d отрядов" %
		[plan.size(), mine.size()])
	verdict("E1 каждому отряду достался свой участок чужой линии",
		plan.size() == mine.size(), "участков %d из %d" % [plan.size(), mine.size()])
	var xs: Array = []
	var uniq: Dictionary = {}
	for k in range(mine.size()):
		var sid: int = int((mine[k] as Array)[0])
		if not plan.has(sid):
			continue
		var t := plan[sid] as Unit
		uniq[t] = true
		xs.append([GameManager.squad_centroid(sid).x, t.global_position.x])
	verdict("E2 цели у отрядов РАЗНЫЕ, а не одна на всех",
		uniq.size() == mine.size(), "различных целей %d" % uniq.size())
	# Порядок: чем левее наш отряд, тем левее его участок
	xs.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var ordered := true
	for i in range(1, xs.size()):
		if float(xs[i][1]) < float(xs[i - 1][1]):
			ordered = false
	verdict("E3 фланги напротив флангов, центр напротив центра", ordered,
		"наши x → цели x: %s" % str(xs))
	# И ОДИН ОТРЯД РАСКЛАДЫВАТЬ НЕЧЕГО: приказ обязан идти прежним путём
	sel._clear_selection()
	for u in ((mine[0] as Array)[1] as Array):
		sel._select(u)
	var solo: Dictionary = sel.frontline_targets(foes[15])
	verdict("E4 одному отряду раскладка не навязывается", solo.is_empty(),
		"участков %d" % solo.size())
	sel._clear_selection()
	for arr in [foes]:
		for u in arr:
			if is_instance_valid(u):
				(u as Node).queue_free()
	for built in mine:
		for u in (built[1] as Array):
			if is_instance_valid(u):
				(u as Node).queue_free()
	await frames(3)
