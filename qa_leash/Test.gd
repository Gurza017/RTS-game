extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ОТРЯД НЕ УБЕГАЕТ НАЗАД ПОСЛЕ БОЯ НА МАРШЕ
## ═══════════════════════════════════════════════════════════════════════════
## Отряд с разметкой строя (как после растягивания ПКМ, GameManager.
## squad_set_formation) отправлен через "карту" слева направо, посреди пути
## стоит враг. Отряд обязан снести его и либо встать на месте боя, либо
## продолжить путь вправо — но НИКОГДА не разворачиваться и не бежать назад
## к стартовой точке (см. отчёт про "возврат на исходную позицию").
##
## Запуск: godot --headless --path . res://qa_leash/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	return u

func _squad(kind: String, fac: int, center: Vector3, count: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(count):
		var p := center + Vector3(0.0, 0.0, float(i % 5) * 0.6 - 1.2) \
			+ Vector3(-float(i / 5) * 0.6, 0.0, 0.0)
		var u := _new(kind, fac, p)
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _alive(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

## Точная копия SelectionManager._issue_march_keeping_shape: разметка строя
## переносится КАК ЕСТЬ в точку приказа и запоминается за отрядом — ровно то,
## что делает растягивание ПКМ в игре
func _issue_line_march(sid: int, movable: Array, center: Vector3, slow: bool) -> void:
	var centroid := Vector3.ZERO
	for u in movable:
		centroid += (u as Node3D).global_position
	centroid /= float(movable.size())
	centroid.y = 0.0
	var course := center - centroid
	course.y = 0.0
	course = course.normalized()
	var ordered: Array = movable.duplicate()
	ordered.sort_custom(func(a, b):
		return (a as Node3D).global_position.dot(course) \
			> (b as Node3D).global_position.dot(course))
	var slots: Array = []
	for u in ordered:
		var offset: Vector3 = (u as Node3D).global_position - centroid
		offset.y = 0.0
		var slot: Vector3 = center + offset
		slots.append(slot)
		(u as Unit).command_move(slot, slow, course)
	GameManager.squad_set_formation(sid, slots, course, slow)

func _run() -> void:
	seed(4242)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	GameManager.world_bounds_enabled = false
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  ЛЕВЫЙ КРАЙ → ПРАВЫЙ КРАЙ: ОТРЯД НЕ ДОЛЖЕН БЕЖАТЬ НАЗАД           ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	const LEFT_X  := -15.0
	const RIGHT_X := 15.0
	const START_TOL := 6.0   # "вернулся к старту" — оказался ближе этого к LEFT_X

	var col := _squad("spearman", Constants.FACTION_PLAYER, Vector3(LEFT_X, 0, 0), 16)
	# Половинное здоровье — заслон обязан выбить хотя бы часть отряда, иначе
	# смыкание рядов по гибели (Unit._die -> squad_close_ranks, БЕЗ force) ни разу
	# не сработает и останется непроверенным путём
	for u in col:
		(u as Unit).max_health = 50.0
		(u as Unit).current_health = 50.0
	var blocker := _squad("spearman", Constants.FACTION_ENEMY, Vector3(0, 0, 0), 8)
	await frames(30)

	var sid: int = (col[0] as Unit).squad_id
	_issue_line_march(sid, col, Vector3(RIGHT_X, 0, 0), true)

	var peak_x: Dictionary = {}
	for u in col:
		peak_x[u] = (u as Node3D).global_position.x

	# ─── Фаза 1: до полной гибели заслона ───────────────────────────────────
	var t0: int = Time.get_ticks_msec()
	var worst_regress := 0.0
	var min_seen_after_start := 1e9
	while Time.get_ticks_msec() - t0 < 45000:
		await get_tree().process_frame
		for u in col:
			if not is_instance_valid(u) or (u as Unit).is_dead():
				continue
			var x: float = (u as Node3D).global_position.x
			if x > float(peak_x.get(u, LEFT_X)):
				peak_x[u] = x
			var regress: float = float(peak_x[u]) - x
			worst_regress = maxf(worst_regress, regress)
		if _alive(blocker) == 0:
			break
	verdict("L1 заслон на пути снесён", _alive(blocker) == 0,
		"живых в заслоне %d из %d" % [_alive(blocker), blocker.size()])

	# ─── Фаза 2: после гибели заслона — отряд НЕ уходит назад ───────────────
	var t1: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 25000:
		await get_tree().process_frame
		for u in col:
			if not is_instance_valid(u) or (u as Unit).is_dead():
				continue
			var x: float = (u as Node3D).global_position.x
			if x > float(peak_x.get(u, LEFT_X)):
				peak_x[u] = x
			var regress: float = float(peak_x[u]) - x
			worst_regress = maxf(worst_regress, regress)
			min_seen_after_start = minf(min_seen_after_start, x)

	var final_xs: Array = []
	var ran_home := 0
	for u in col:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var x: float = (u as Node3D).global_position.x
		final_xs.append(x)
		if x < LEFT_X + START_TOL:
			ran_home += 1

	var avg_final := 0.0
	for x in final_xs:
		avg_final += float(x)
	if final_xs.size() > 0:
		avg_final /= float(final_xs.size())

	print("  живых бойцов отряда к концу: %d из %d" % [final_xs.size(), col.size()])
	print("  наибольший откат от собственного максимума X: %.2f м" % worst_regress)
	print("  средний X к концу: %.2f (старт %.1f, цель %.1f, заслон на 0.0)"
		% [avg_final, LEFT_X, RIGHT_X])

	verdict("L2 никто не скатился обратно к старту", ran_home == 0,
		"вернулось к старту %d из %d (X < %.0f)" % [ran_home, final_xs.size(), LEFT_X + START_TOL])
	verdict("L3 откат от максимума в пределах строевой возни (<6 м)", worst_regress < 6.0,
		"худший откат %.2f м" % worst_regress)
	verdict("L4 отряд стоит на месте боя или идёт дальше вправо", avg_final > -5.0,
		"средний X = %.2f (заслон стоял на X=0)" % avg_final)

	for u in col + blocker:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

	await _test_pursuit_limit()
	await _test_sprint_cost()

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %-58s%s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== LEASH TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# P. ПОВОДОК ПОГОНИ: ЗА ОТСТУПИВШИМ ГОНИМСЯ ДО ПРЕДЕЛА, А НЕ ДО КРАЯ КАРТЫ
# ═════════════════════════════════════════════════════════════════════════════
## Приказ атаковать выдан, боец цель ДОСТАЛ, после чего цель убегает. Проверяем,
## что погоня обрывается сама и боец возвращается на пост, а не тянется за
## жертвой через полкарты, растягивая отряд в нитку.
##
## Числа читаются из кода (Unit.PURSUIT_LIMIT), а не хардкодятся: заказана
## вилка «10 шагов, 5-8 м», её и проверяем как СВОЙСТВО
func _test_pursuit_limit() -> void:
	verdict("P1 поводок погони — заказанные 5-8 м",
		Unit.PURSUIT_LIMIT >= 5.0 and Unit.PURSUIT_LIMIT <= 8.0,
		"PURSUIT_LIMIT = %.1f м" % Unit.PURSUIT_LIMIT)

	var post := Vector3(300.0, 0.0, 300.0)
	var hunter := _new("warrior", Constants.FACTION_PLAYER, post)
	var prey := _new("worker", Constants.FACTION_ENEMY, post + Vector3(1.0, 0.0, 0.0))
	await frames(2)
	# Пост назначается приказом на движение: от него боец и считает возврат
	hunter.command_move(post)
	await frames(20)
	hunter.command_attack(prey, true, true)
	var touched := false
	for _i in range(240):
		await get_tree().physics_frame
		if hunter._engaged_once:
			touched = true
			break
	verdict("P2 боец достал цель — отсюда считается погоня", touched,
		"первое касание: %s" % str(touched))

	# Жертва убегает по прямой, заведомо дальше поводка
	var fled := 0.0
	for _i in range(900):
		await get_tree().physics_frame
		if not is_instance_valid(prey) or prey.is_dead():
			break
		fled += 0.05
		prey.global_position = post + Vector3(1.0 + fled, 0.0, 0.0)
		prey.sync_row()
		if hunter.attack_target == null:
			break
	var gave_up: bool = is_instance_valid(hunter) and hunter.attack_target == null
	var chased: float = hunter.global_position.distance_to(post) if is_instance_valid(hunter) else -1.0
	verdict("P3 погоня оборвана сама, цель забыта", gave_up,
		"цель у преследователя: %s" % ("снята" if gave_up else "есть"))
	verdict("P4 ушёл в пределах поводка, а не через полкарты",
		chased >= 0.0 and chased <= Unit.PURSUIT_LIMIT * 2.0,
		"удалился на %.1f м при поводке %.1f м" % [chased, Unit.PURSUIT_LIMIT])

	for u in [hunter, prey]:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# S. ЦЕНА БЕГА: БЫСТРЕЕ НА 35% И БОЛЬНЕЕ НА 35%
# ═════════════════════════════════════════════════════════════════════════════
## Бег по двойному ПКМ раньше был ходом без единого минуса. Заказ владельца:
## +35% скорости и +35% входящего урона. Проверяем оба числа и то, что второе
## реально доходит до здоровья, а не только записано константой
func _test_sprint_cost() -> void:
	verdict("S1 бег даёт заказанные +35% скорости",
		absf(Unit.SPRINT_SPEED_FACTOR - 1.35) < 0.001,
		"SPRINT_SPEED_FACTOR = %.2f" % Unit.SPRINT_SPEED_FACTOR)
	verdict("S2 бег стоит заказанных +30-35% входящего урона",
		Unit.SPRINT_DAMAGE_MULT >= 1.30 and Unit.SPRINT_DAMAGE_MULT <= 1.35,
		"SPRINT_DAMAGE_MULT = %.2f" % Unit.SPRINT_DAMAGE_MULT)

	# ЗАМЕР, А НЕ КОНСТАНТА: одинаковый удар по стоящему и по бегущему
	var calm := _new("warrior", Constants.FACTION_PLAYER, Vector3(400.0, 0.0, 400.0))
	var runner := _new("warrior", Constants.FACTION_PLAYER, Vector3(404.0, 0.0, 400.0))
	await frames(2)
	runner._set_sprinting(true)
	var hp0: float = calm.current_health
	var hp1: float = runner.current_health
	calm.take_damage(100.0, null)
	runner.take_damage(100.0, null)
	var d_calm: float = hp0 - calm.current_health
	var d_run: float = hp1 - runner.current_health
	var ratio: float = d_run / maxf(d_calm, 0.0001)
	verdict("S3 по бегущему удар доходит сильнее ровно на множитель",
		absf(ratio - Unit.SPRINT_DAMAGE_MULT) < 0.02,
		"стоящему %.1f, бегущему %.1f, отношение %.2f при множителе %.2f"
			% [d_calm, d_run, ratio, Unit.SPRINT_DAMAGE_MULT])

	for u in [calm, runner]:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)
