extends Node
## Зонд разбора партии 26.10.2026 (performance_log_2026-10-26_1423.json):
## поднимает автосейв владельца (то же зерно карты) и печатает клетки
## навигации 2 м вокруг точки cx= cz= (по умолчанию — куча 56 копейщиков
## у прохода в стене базы красных, t=2594). Вердиктов нет.
## F лес, W вода, B фундамент, # закрыто сеткой, p непроходимо, . свободно
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
	var cx := -174.3
	var cz := 37.4
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("cx="): cx = float(String(a).substr(3))
		if String(a).begins_with("cz="): cz = float(String(a).substr(3))
	var st: Dictionary = _read(OS.get_user_data_dir().path_join("autosave.tts"))
	print("слепок: ключей %d" % st.size())
	if not st.is_empty():
		GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(40):
		await get_tree().physics_frame
	var x0: float = floor((cx + 225.0) / 2.0) * 2.0 - 225.0 + 1.0
	var z0: float = floor((cz + 126.5625) / 2.0) * 2.0 - 126.5625 + 1.0
	var head := "         "
	for i in range(-14, 15):
		head += "|" if i == 0 else " "
	print(head)
	for j in range(-10, 11):
		var z: float = z0 + float(j) * 2.0
		var row := "%8.2f " % z
		for i in range(-14, 15):
			var x: float = x0 + float(i) * 2.0
			var ch := "."
			if absf(x) > 225.0 or absf(z) > 126.5625: ch = " "
			elif GameManager.army.forest_at(x, z): ch = "F"
			elif GameManager.is_water(x, z): ch = "W"
			elif GameManager.in_building(x, z): ch = "B"
			elif not GameManager.army.nav_free(x, z): ch = "#"
			elif not GameManager.is_passable(x, z): ch = "p"
			row += ch
		print(row + ("  <" if j == 0 else ""))
	print("x от %.1f до %.1f, шаг 2 м; | — столбец точки" % [x0 - 28.0, x0 + 28.0])
	for g in ["buildings", "enemy_buildings"]:
		for b in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(b):
				continue
			var p: Vector3 = (b as Node3D).global_position
			if Vector2(p.x - cx, p.z - cz).length() < 40.0:
				print("постройка %s (%s) у (%.1f, %.1f)" % [b.name, g, p.x, p.z])
	get_tree().quit()
