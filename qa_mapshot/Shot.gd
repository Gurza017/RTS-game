extends Node

## ЗОНД КАРТЫ СВЕРХУ (ТЗ 29.09.2026, третье письмо, блоки 1 и 5): рудники,
## стены леса у баз, брод. Вердиктов нет — печать и снимок. Запуск (окно за
## экраном, требование владельца 28.09):
##   godot --windowed --position -5000,-5000 --path . res://qa_mapshot/Shot.tscn -- bg=1 --out=<путь без .png>

var main = null
var _out: String = ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	print("  игрок %s, красный %s, брод %s, деревня %s" % [str(main.PLAYER_BASE_ANCHOR), str(main.ENEMY_BASE_ANCHOR),
		str(main.ford_point()), str(main.goblin_village_center())])
	print("  стена игрока: %d деревьев, стены красного и орды: %d" % [int(main.wall_trees_placed), int(main.get("base_wall_trees"))])
	for grp in ["neutral_buildings", "enemy_buildings", "goblin_buildings", "player_buildings"]:
		for b in get_tree().get_nodes_in_group(grp):
			if b is Mine:
				var p: Vector3 = (b as Node3D).global_position
				print("  рудник %s в (%.0f, %.0f), владелец %d, до брода %.0f м" % [grp, p.x, p.z, int((b as Mine).get("owner_faction")) if (b as Mine).get("owner_faction") != null else -1,
					Vector2(p.x - main.ford_point().x, p.z - main.ford_point().z).length()])
	var line := ""
	for xi in range(-160, -50, 5):
		line += "X" if GameManager.is_cliff(float(xi), 8.0) else "."
	print("  маска вдоль z=8, x -160..-55 шаг 5: %s" % line)
	for zz in [0.0, 8.0, 16.0, 24.0]:
		var rt: PackedVector3Array = GameManager.nav_route(Vector3(-143.0, 0.0, zz), Vector3(-70.0, 0.0, zz), 1.5)
		print("  маршрут (-143,%.0f)→(-70,%.0f): %d точек %s" % [zz, zz, rt.size(), str(rt)])
	if _out == "":
		get_tree().quit()
		return
	main.set_process(false)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if main._camera != null:
		(main._camera as Node).set_process(false)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 300.0
	cam.global_position = Vector3(-20.0, 260.0, 230.0)
	cam.look_at(Vector3(-20.0, 0.0, 10.0), Vector3.UP)
	cam.far = 2000.0
	await frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + ".png")
	print("  снимок: %s.png" % _out)
	get_tree().quit()
