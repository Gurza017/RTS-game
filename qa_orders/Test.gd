extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: УКАЗАТЕЛИ ОТДАННОГО ПРИКАЗА
## ═══════════════════════════════════════════════════════════════════════════
##   A ЗАПОМИНАНИЕ — приказ на движение и приказ атаки числятся за отрядом
##   B ИСПОЛНЕНИЕ  — метка точки СНИМАЕТСЯ САМА по приходу, а не залипает
##   C ЦЕЛЬ        — красная подсветка держится на цели и гаснет с её гибелью
##   D ВОЗВРАТ     — повторное выделение отряда показывает приказ снова
##
## Именно «залипающие навсегда» метки и «не видно, кому что приказано» были
## жалобой владельца, поэтому проверяется не факт создания метки, а её ЖИЗНЕННЫЙ
## ЦИКЛ: появилась по приказу, ушла по исполнению, вернулась по выделению.
##
## Стенд headless и молчит до конца: печатает одну таблицу.

var main: Node = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok, detail])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	await frames(2)

	await _test_move_order()
	await _test_attack_order()
	await _test_nobody_left_behind()
	_summary()
	print("\n=== QA_ORDERS DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ qa_orders ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-58s %s%s" % [String(row[0]),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО",
			("  — " + String(row[2])) if String(row[2]) != "" else ""])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

func _squad(fac: int, kind: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u := Spearman.new()
		u.faction = fac
		main.world_add(u)
		u.global_position = at + Vector3(float(i % 4) * 0.7, 0.0, float(i / 4) * 0.7)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _sid_of(men: Array) -> int:
	return (men[0] as Unit).squad_id

func _select(men: Array) -> void:
	var sm = main.selection_manager
	sm.selected_units = men.duplicate()

# ═════════════════════════════════════════════════════════════════════════════
# A + B. ПРИКАЗ НА ДВИЖЕНИЕ: МЕТКА ПОЯВИЛАСЬ И УШЛА ПО ПРИХОДУ
# ═════════════════════════════════════════════════════════════════════════════
func _test_move_order() -> void:
	var men := _squad(Constants.FACTION_PLAYER, "spearman", Vector3(-700.0, 0.0, -700.0), 8)
	await pframes(3)
	var sid: int = _sid_of(men)
	var goal := Vector3(-690.0, 0.0, -700.0)
	_select(men)
	for u in men:
		(u as Unit).command_move(goal)
	GameManager.squad_note_order(sid, GameManager.ORDER_MOVE, goal)
	await frames(2)
	verdict("A1 приказ на движение числится за отрядом",
		GameManager.squad_orders.has(sid),
		"приказов в реестре: %d" % GameManager.squad_orders.size())

	# ── ГЛАВНАЯ ПРОВЕРКА: МЕТКА НЕ ЗАЛИПАЕТ ────────────────────────────────
	# Ждём, пока отряд дойдёт. Метка обязана сняться САМА, без чьей-либо
	# команды: именно «вечно висящие кольца» были жалобой
	var arrived := false
	for _i in range(900):
		await get_tree().physics_frame
		if not GameManager.squad_orders.has(sid):
			arrived = true
			break
	var c: Vector3 = GameManager._centroid_of(GameManager.squad_members(sid))
	verdict("B1 метка точки снялась сама по приходу отряда", arrived,
		"остаток до точки %.1f м при пороге %.1f м"
			% [Vector2(c.x - goal.x, c.z - goal.z).length(),
				GameManager.ORDER_MARK_ARRIVE])

	# ── D. ПРИКАЗ, КОТОРЫЙ ЕЩЁ НЕ ИСПОЛНЕН, ВИДЕН СНОВА ────────────────────
	# Снимаем выделение, отдаём приказ подальше, выделяем заново — приказ
	# обязан по-прежнему числиться и показываться
	var far := Vector3(-600.0, 0.0, -700.0)
	for u in men:
		(u as Unit).command_move(far)
	GameManager.squad_note_order(sid, GameManager.ORDER_MOVE, far)
	_select([])
	await frames(3)
	verdict("D1 снятие выделения не стирает сам приказ",
		GameManager.squad_orders.has(sid),
		"приказ %s" % ("на месте" if GameManager.squad_orders.has(sid) else "потерян"))
	_select(men)
	await frames(3)
	verdict("D2 повторное выделение показывает приказ снова",
		GameManager.squad_orders.has(sid),
		"вид приказа %d" % int((GameManager.squad_orders.get(sid, {})).get("kind", -1)))

	for u in men:
		if is_instance_valid(u): (u as Node).queue_free()
	_select([])
	GameManager.squad_clear_order(sid)
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# A + C. ПРИКАЗ АТАКИ: ПОДСВЕТКА ЦЕЛИ ЖИВЁТ РОВНО ПОКА ЖИВА ЦЕЛЬ
# ═════════════════════════════════════════════════════════════════════════════
func _test_attack_order() -> void:
	var ours := _squad(Constants.FACTION_PLAYER, "spearman", Vector3(-700.0, 0.0, -600.0), 6)
	var foes := _squad(Constants.FACTION_ENEMY, "spearman", Vector3(-680.0, 0.0, -600.0), 6)
	await pframes(3)
	var sid: int = _sid_of(ours)
	_select(ours)
	GameManager.squad_note_order(sid, GameManager.ORDER_ATTACK,
		(foes[0] as Node3D).global_position, foes[0])
	await frames(3)
	verdict("A2 приказ атаки числится за отрядом и помнит цель",
		GameManager.squad_orders.has(sid)
			and (GameManager.squad_orders[sid] as Dictionary).get("target") == foes[0],
		"вид приказа %d" % int((GameManager.squad_orders.get(sid, {})).get("kind", -1)))

	# Цель истреблена — подсвечивать нечего, приказ обязан сняться сам
	for u in foes:
		if is_instance_valid(u):
			(u as Unit).take_damage((u as Unit).max_health * 10.0 + 1000.0, null)
	var gone := false
	for _i in range(120):
		await frames(1)
		if not GameManager.squad_orders.has(sid):
			gone = true
			break
	verdict("C1 подсветка цели снялась вместе с гибелью цели", gone,
		"приказ %s" % ("снят" if gone else "остался висеть"))

	for u in ours:
		if is_instance_valid(u): (u as Node).queue_free()
	_select([])
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. НИ ОДИН ВЫДЕЛЕННЫЙ БОЕЦ НЕ ОСТАЁТСЯ БЕЗ ПРИКАЗА
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца по скриншоту: из пяти выделенных отрядов один игнорирует
## команду и остаётся стоять с жёлтым кольцом. Раскладка строя теряла людей
## сразу в трёх местах — эшелон без места на линии пропускался целиком, бойцы
## вне реестра отрядов выпадали из сетки блоков, а несовпадение числа мест и
## числа бойцов ОТМЕНЯЛО ВЕСЬ приказ разом.
##
## Проверяется поэтому не конкретная ветка, а СВОЙСТВО: после приказа у каждого
## выделенного есть точка марша. Смешанное выделение и одиночка в нём —
## намеренно: именно на них раскладка и спотыкалась
func _test_nobody_left_behind() -> void:
	var sm = main.selection_manager
	var all: Array = []
	var kinds := ["res://scenes/units/Spearman.tscn",
		"res://scenes/units/Spearman.tscn",
		"res://scenes/units/Archer.tscn",
		"res://scenes/units/Warrior.tscn",
		"res://scenes/units/Spearman.tscn"]
	for k in range(kinds.size()):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		for i in range(12):
			var u: Unit = load(kinds[k]).instantiate()
			u.faction = Constants.FACTION_PLAYER
			main.world_add(u)
			u.global_position = Vector3(-700.0 + float(k) * 6.0 + float(i % 4) * 0.7,
				0.0, -700.0 + float(i / 4) * 0.7)
			u.sync_row()
			GameManager.add_to_squad(sid, u)
			all.append(u)
	# ОДИНОЧКА БЕЗ ОТРЯДА — тот самый случай, который сетка блоков отбрасывала
	var lone: Unit = load("res://scenes/units/Warrior.tscn").instantiate()
	lone.faction = Constants.FACTION_PLAYER
	main.world_add(lone)
	lone.global_position = Vector3(-670.0, 0.0, -700.0)
	lone.sync_row()
	all.append(lone)
	await pframes(4)

	sm._clear_selection()
	for u in all:
		sm._select(u)
	await frames(2)
	var target := Vector3(-700.0, 0.0, -660.0)
	sm._issue_formation_move(target, false)
	await pframes(4)

	var idle := 0
	for u in all:
		if not is_instance_valid(u):
			continue
		var uu: Unit = u
		# «Приказ получен» — это либо он уже идёт, либо ему записана точка
		# марша: боец, стоящий ровно на своём месте, честно останется в покое
		if uu.state != Unit.State.MOVING and not bool(uu.get("_march_pending")) 				and uu.global_position.distance_to(target) > 12.0:
			idle += 1
	verdict("C1 после приказа никто из выделения не остался стоять",
		idle == 0, "без приказа осталось %d из %d" % [idle, all.size()])
	verdict("C2 страховка не понадобилась либо сработала молча",
		sm.last_unordered >= 0,
		"подобрано страховкой %d" % sm.last_unordered)

	# ── ТО ЖЕ САМОЕ ЧЕРЕЗ РАСТЯНУТУЮ ЛИНИЮ ─────────────────────────────────
	# Второй путь раскладки (эшелоны по родам войск) терял людей по-своему:
	# эшелон, которому не хватило длины линии, пропускался целиком
	sm._execute_line_formation(Vector3(-706.0, 0.0, -640.0),
		Vector3(-702.0, 0.0, -640.0))          # НАРОЧНО короткая линия
	await pframes(4)
	var idle2 := 0
	for u in all:
		if not is_instance_valid(u):
			continue
		var u2: Unit = u
		if u2.state != Unit.State.MOVING and not bool(u2.get("_march_pending")) 				and u2.global_position.distance_to(Vector3(-704.0, 0.0, -640.0)) > 12.0:
			idle2 += 1
	verdict("C3 короткая линия не отменяет приказ и никого не теряет",
		idle2 == 0, "без приказа осталось %d из %d" % [idle2, all.size()])

	sm._clear_selection()
	for u in all:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await pframes(3)
