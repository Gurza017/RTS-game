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

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %-58s%s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== LEASH TEST DONE ===")
	get_tree().quit()
