extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПЛОЩАДКА СБОРА У ЗДАНИЯ (хак №3, 09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ГЕОМЕТРИЯ — прямоугольник лежит ПЕРЕД воротами по фасаду, покрывает
##     все ряды выхода, не заходит в коробку здания.
##   B СПАВН — три заказа подряд: каждый боец появляется НА площадке с первого
##     кадра, никто не появляется в проёме ворот, отряды разных заказов не
##     накладываются (разные ряды), никто не толпится у ворот во время выхода.
##   C ФЛАЖОК — с точкой сбора отряд собирается на площадке и оттуда доходит
##     до флажка.
##   D МАРКЕР — рамка площадки СКРЫТА (заказ 10.09.2026), даже у выделенного.
##
## Числа — из конфигов (правило 10), ожидание физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_rally_zone/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с"); _finish())

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
	print("\n═════ ИТОГ qa_rally_zone: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _new_barracks(at: Vector3) -> Building:
	var b: Building = Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return b

## Один заказ; возвращает бойцов; попутно следит за проёмом ворот и первым
## кадром каждого появления (внутри ли площадки)
func _train(b: Building, size: int, watch: Dictionary) -> Array:
	var before: Array = get_tree().get_nodes_in_group("player_units").duplicate()
	var seen: Array = []
	b.squad_size = size
	b.queue_unit("spearman", {}, 0.01)
	if not b.production_queue.is_empty():
		(b.production_queue[0] as Dictionary)["time"] = 0.01
	var gate: Vector3 = b._gate_position()
	var guard := 0
	while guard < 900 and seen.size() < size:
		guard += 1
		await get_tree().physics_frame
		var at_gate := 0
		# ПРОЁМ — это круг ДО первой шеренги площадки (10.09.2026: она в
		# SQUAD_EXIT_DISTANCE от ворот, а не в четырёх метрах)
		var door_r: float = b.SQUAD_EXIT_DISTANCE - b.squad_spacing * 0.5 - 0.05
		for n in get_tree().get_nodes_in_group("player_units"):
			var p: Vector3 = (n as Node3D).global_position
			if Vector2(p.x - gate.x, p.z - gate.z).length() < door_r:
				at_gate += 1
			if n in before or n in seen:
				continue
			seen.append(n)
			if not b.in_rally_zone(p, 0.6):
				watch["outside"] = int(watch.get("outside", 0)) + 1
		watch["gate_max"] = maxi(int(watch.get("gate_max", 0)), at_gate)
	return seen

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	await pframes(4)

	# ── A. Геометрия ───────────────────────────────────────────────────────
	print("\n═════ A. ГЕОМЕТРИЯ ПЛОЩАДКИ ═════")
	var b: Building = _new_barracks(Vector3(20.0, 0.0, -50.0))
	# Фасад и ворота встают после отложенной загрузки картинки (_face_front):
	# площадка считается от них, спрашивать её в первый же кадр нельзя
	await frames(8)
	await pframes(4)
	var z: Dictionary = b.rally_zone()
	var gate: Vector3 = b._gate_position()
	var c: Vector3 = z["centre"]
	var dir: Vector3 = z["dir"]
	var along: float = (c - gate).dot(dir)
	verdict("A1 центр площадки лежит ПЕРЕД воротами по оси выхода",
		along > 0.0 and absf((c - gate).dot(z["side"])) < 0.05,
		"вперёд %.2f м, вбок %.2f м" % [along, (c - gate).dot(z["side"])])
	var near_edge: float = along - float(z["half_d"])
	verdict("A2 ближний край площадки не заходит в здание (за воротами)", near_edge >= -0.01
		and near_edge <= b.SQUAD_EXIT_DISTANCE, "ближний край в %.2f м от ворот" % near_edge)
	verdict("A3 площадка вмещает уставной отряд по ширине",
		float(z["half_w"]) * 2.0 >= float(Building.square_cols(b.squad_size, b.squad_cols)) * b.squad_spacing,
		"ширина %.2f м" % (float(z["half_w"]) * 2.0))
	verdict("A4 точка ворот на площадке не лежит, точка в 5 м перед ними — лежит",
		not b.in_rally_zone(gate, 0.0) and b.in_rally_zone(gate + dir * 5.0, 0.0),
		"ворота=%s, +5м=%s, полуглубина %.2f, dir=%s" % [str(b.in_rally_zone(gate, 0.0)),
			str(b.in_rally_zone(gate + dir * 5.0, 0.0)), float(z["half_d"]), str(dir)])

	# ── B. Три заказа подряд ───────────────────────────────────────────────
	print("\n═════ B. ТРИ ЗАКАЗА ПОДРЯД ═════")
	var watch: Dictionary = {}
	var squads: Array = []
	for k in range(3):
		var men: Array = await _train(b, 20, watch)
		squads.append(men)
		await pframes(10)
	var total := 0
	for m in squads:
		total += (m as Array).size()
	verdict("B1 все %d бойцов трёх заказов появились на площадке с первого кадра" % total,
		total == 60 and int(watch.get("outside", 0)) == 0,
		"вышло %d, вне площадки при появлении %d" % [total, int(watch.get("outside", 0))])
	verdict("B2 в проёме ворот никто не толпится (не больше одного до первой шеренги)",
		int(watch.get("gate_max", 0)) <= 1, "максимум в проёме %d" % int(watch.get("gate_max", 0)))
	# Отряды разных заказов не накладываются: минимальное расстояние между
	# бойцами разных отрядов не меньше строевого интервала
	var min_cross := INF
	for i in range(squads.size()):
		for j in range(i + 1, squads.size()):
			for u in squads[i]:
				if not is_instance_valid(u): continue
				for v in squads[j]:
					if not is_instance_valid(v): continue
					var d: float = (u as Node3D).global_position.distance_to((v as Node3D).global_position)
					min_cross = minf(min_cross, d)
	verdict("B3 отряды разных заказов не накладываются (ближайшая пара не ближе интервала)",
		min_cross >= b.squad_spacing * 0.9, "ближайшая пара %.2f м при интервале %.2f" % [min_cross, b.squad_spacing])
	var all_on := 0
	for m in squads:
		for u in m:
			if is_instance_valid(u) and b.in_rally_zone((u as Node3D).global_position, 0.6):
				all_on += 1
	verdict("B4 после выхода все стоят на площадке (никто не ушёл в поле)",
		all_on == total, "на площадке %d из %d" % [all_on, total])
	for m in squads:
		for u in m:
			if is_instance_valid(u):
				(u as Unit).take_damage(1.0e9)
	await pframes(3)

	# ── C. Флажок: собрались на площадке, дошли до точки сбора ─────────────
	print("\n═════ C. ТОЧКА СБОРА ═════")
	var target: Vector3 = b.global_position + Vector3(0.0, 0.0, 40.0)
	b.set_rally_point(target)
	var watch2: Dictionary = {}
	var men2: Array = await _train(b, 20, watch2)
	verdict("C1 с флажком бойцы тоже появляются на площадке, а не в воротах",
		men2.size() == 20 and int(watch2.get("outside", 0)) == 0,
		"вне площадки %d" % int(watch2.get("outside", 0)))
	var guard := 0
	var near_flag := 0
	while guard < 60 * 40:
		await get_tree().physics_frame
		guard += 1
		near_flag = 0
		for u in men2:
			if is_instance_valid(u) and Vector2((u as Node3D).global_position.x - target.x,
					(u as Node3D).global_position.z - target.z).length() < 6.0:
				near_flag += 1
		if near_flag == men2.size():
			break
	verdict("C2 отряд с площадки дошёл к флажку строем", near_flag == men2.size(),
		"у флажка %d из %d за %d физкадров" % [near_flag, men2.size(), guard])
	b.clear_rally_point()
	for u in men2:
		if is_instance_valid(u):
			(u as Unit).take_damage(1.0e9)
	await pframes(3)

	# ── D. Маркер ──────────────────────────────────────────────────────────
	print("\n═════ D. МАРКЕР ═════")
	b.set_selected(true)
	await frames(2)
	var mk := b.get_parent().get_node_or_null("RallyZone") as MeshInstance3D
	verdict("D1 рамка площадки не рисуется даже у выделенного здания (заказ 10.09.2026)",
		mk == null or not mk.visible)
	verdict("D1б площадка не длиннее ZONE_DEPTH и не короче её половины",
		float(z["half_d"]) * 2.0 <= b.ZONE_DEPTH + 0.6 and float(z["half_d"]) * 2.0 >= b.ZONE_DEPTH * 0.5,
		"длина %.1f м при ZONE_DEPTH %.0f" % [float(z["half_d"]) * 2.0, b.ZONE_DEPTH])
	b.set_selected(false)
	await frames(2)
	verdict("D2 без выделения площадка спрятана", mk == null or not mk.visible)
	_finish()
