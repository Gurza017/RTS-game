extends Node
## Зонд разбора партии 25.10.2026 (performance_log_2026-10-25_0006.json):
## поднимает автосейв владельца (конец партии) и смотрит, что под отрядами
## орды, 11 минут стоявшими у восточной кромки (x 223.5, z -27…-33).
## Вердиктов нет.
const _Save = preload("res://scripts/SaveLoadManager.gd")
var main: Node

func _ready() -> void:
	call_deferred("_run")

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.get_32()
	f.get_32()
	f.get_32()
	var d: Variant = f.get_var(false)
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _run() -> void:
	var st: Dictionary = _read("user://autosave.tts")
	print("слепок: ключей %d, зерно %s" % [st.size(), str(st.get("meta", {}).get("world_seed", "?"))])
	for b in st.get("buildings", []):
		var bd: Dictionary = b
		if float(str(bd.get("x", bd.get("pos", [0])[0] if bd.has("pos") else 0))) > 100.0 or str(bd).find("goblin") >= 0:
			print("постройка слепка ", str(bd).substr(0, 160))
	GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(40):
		await get_tree().physics_frame
	print("лимит карты %.1f x %.1f" % [GameManager.map_lim_x, GameManager.map_lim_z])
	var n := 0
	for u in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_GOBLIN)):
		if not is_instance_valid(u):
			continue
		var p: Vector3 = (u as Node3D).global_position
		if p.x > 200.0 and absf(p.z + 30.0) < 20.0:
			n += 1
			if n <= 12:
				print("гоблин sid %d (%.1f, %.1f) pass=%s cliff=%s navfree=%s" % [(u as Unit).squad_id, p.x, p.z,
					GameManager.is_passable(p.x, p.z), GameManager.is_cliff(p.x, p.z), GameManager.army.nav_free(p.x, p.z)])
	print("гоблинов у кромки: %d" % n)
	# карта клеток 2 м: # непроходимо, . свободно
	for zi in range(-46, -10, 2):
		var row := "z%4d " % zi
		for xi in range(190, 226, 2):
			var x: float = float(xi) + 1.0
			var z: float = float(zi) + 1.0
			var ch := "."
			if GameManager.is_cliff(x, z): ch = "C"
			elif GameManager.army.forest_at(x, z): ch = "F"
			elif GameManager.is_water(x, z): ch = "W"
			elif GameManager.in_building(x, z): ch = "B"
			elif not GameManager.army.nav_free(x, z): ch = "n"
			elif not GameManager.is_passable(x, z): ch = "#"
			row += ch
		print(row)
	for zi in range(-46, -10, 2):
		var row2 := "n%6.2f " % (float(zi) + 0.4375)
		for xi in range(190, 226, 2):
			row2 += "." if GameManager.army.nav_free(float(xi) + 2.0, float(zi) + 0.4375) else "#"
		row2 += "   h:"
		for xi in range(190, 226, 4):
			row2 += " %.1f" % main.get_terrain_height(float(xi) + 1.0, float(zi) + 1.0)
		print(row2)
	var r: PackedVector3Array = GameManager.nav_route(Vector3(223.4, 0, -30.0), Vector3(150.0, 0, -25.0))
	print("маршрут 223.4,-30 → 150,-25: точек %d %s" % [r.size(), str(r)])
	for pr in [[Vector3(223.4, 0, -18.0), Vector3(150.0, 0, -25.0)], [Vector3(223.4, 0, -30.0), Vector3(223.4, 0, -14.0)],
			[Vector3(221.0, 0, -29.0), Vector3(150.0, 0, -25.0)], [Vector3(215.0, 0, -29.0), Vector3(150.0, 0, -25.0)]]:
		var rr: PackedVector3Array = GameManager.nav_route(pr[0], pr[1])
		print("маршрут %s → %s: точек %d" % [str(pr[0]), str(pr[1]), rr.size()])
	var tr := 0
	for t in get_tree().get_nodes_in_group("trees"):
		var q: Vector3 = (t as Node3D).global_position
		if q.x > 190.0 and q.x < 222.0 and q.z > -44.0 and q.z < -24.0:
			tr += 1
	print("деревьев в массиве: %d" % tr)
	for b in get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_GOBLIN)):
		var q2: Vector3 = (b as Node3D).global_position
		if q2.x > 180.0:
			print("здание орды %s (%.1f, %.1f)" % [b.name, q2.x, q2.z])
	print("комп. старт %d, цель %d" % [GameManager.army.nav_component(223.4, -30.0) if GameManager.army.has_method("nav_component") else -9, 0])
	var rr2: PackedVector3Array = GameManager.nav_route(Vector3(223.4, 0, -30.0), Vector3(150.0, 0, -25.0))
	print("nav_on %s bounds %s line_blocked %s" % [GameManager.nav_on(), GameManager.world_bounds_enabled, GameManager.army.nav_line_blocked(223.4, -30.0, 150.0, -25.0, 1.5)])
	for sp in [Vector2(223.4, -30.0), Vector2(223.0, -21.0), Vector2(223.0, -24.0), Vector2(221.0, -20.0), Vector2(205.0, -28.0)]:
		var fl: PackedFloat32Array = GameManager.army.nav_path(sp.x, sp.y, 150.0, -25.0, 1.5, 0.0)
		print("nav_path из %s: %s found=%s" % [str(sp), str(fl), GameManager.army.nav_last_found()])
	print("сетка: начало %s ячейка %s колонок %s" % [str(GameManager.army.get("_c").get("NavOriginX") if false else "?"), "?", "?"])
	for q in [Vector2(223.2, -25.8), Vector2(224.0, -25.5625), Vector2(223.5, -27.0), Vector2(224.9, -27.0), Vector2(222.0, -27.0)]:
		print("точка %s navfree=%s cliff=%s forest=%s pass=%s" % [str(q), GameManager.army.nav_free(q.x, q.y), GameManager.army.is_cliff(q.x, q.y), GameManager.army.forest_at(q.x, q.y), GameManager.is_passable(q.x, q.y)])
	print("найден путь: %s, точек %d" % [GameManager.army.nav_last_found(), rr2.size()])
	# Приказ застрявшим идти на запад: выберутся ли
	var stuck: Array = []
	for u in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_GOBLIN)):
		if is_instance_valid(u) and (u as Node3D).global_position.x > 220.0 and absf((u as Node3D).global_position.z + 30.0) < 8.0:
			stuck.append(u)
	if main.get("goblin_ai") != null:
		(main.get("goblin_ai") as Node).set_process(false)
	if not stuck.is_empty():
		var u0: Unit = stuck[0]
		print("боец: state %d dormant %s tick %s phys %s sid %d" % [u0.state, u0.get("_dormant"), u0.get("_tick_on"), u0.is_physics_processing(), u0.squad_id])
	for u in stuck:
		(u as Unit).command_move(Vector3(170.0, 0, -15.0))
	for t in range(6):
		for _i in range(300):
			await get_tree().physics_frame
		var out := 0
		var sx := 0.0
		for u in stuck:
			if is_instance_valid(u):
				sx += (u as Node3D).global_position.x
				if (u as Node3D).global_position.x < 215.0:
					out += 1
		print("через %d с: выбрались %d из %d, средний x %.1f" % [(t + 1) * 5, out, stuck.size(), sx / maxf(1.0, float(stuck.size()))])
	get_tree().quit()
