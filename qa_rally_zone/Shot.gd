extends Node

## ОКОННЫЙ СНИМОК: площадка сбора у выделенных бараков и два заказа, стоящие
## на ней рядами. Вердиктов нет — картинка для глаза.
## Запуск: godot --path . res://qa_rally_zone/Shot.tscn -- --out=<путь без .png>

var main = null
var _out: String = ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func():
		print("  СТОРОЖ"); get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1600, 900)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	var b: Building = Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	var at := Vector3(20.0, 0.0, -50.0)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	await frames(10)
	for k in range(2):
		b.squad_size = 20
		b.queue_unit("spearman", {}, 0.01)
		if not b.production_queue.is_empty():
			(b.production_queue[0] as Dictionary)["time"] = 0.01
		for _i in range(90):
			b._row_gate = 0.0
			await get_tree().physics_frame
	var z: Dictionary = b.rally_zone()
	var c: Vector3 = z["centre"]
	var n_units: int = get_tree().get_nodes_in_group("player_units").size()
	var first: Vector3 = Vector3.INF
	for u in get_tree().get_nodes_in_group("player_units"):
		first = (u as Node3D).global_position
		break
	print("  ЗОНД: бойцов %d, первый в %s, барак %s, ворота %s, центр площадки %s, dir %s, полу %.1f x %.1f, очередь %d, ожидают %d" % [
		n_units, str(first), str(b.global_position), str(b._gate_position()), str(c), str(z["dir"]),
		float(z["half_w"]), float(z["half_d"]), b.production_queue.size(), b._pending_spawns.size()])
	main.focus_camera_on(Vector3((c.x + at.x) * 0.5, 0.0, (c.z + at.z) * 0.5))
	await frames(4)
	(main._camera as Node).set_process(false)
	(get_viewport().get_camera_3d() as Camera3D).size = 46.0
	if not ("--nomarker" in OS.get_cmdline_user_args()):
		b.set_selected(true)
	await pframes(30)
	await frames(6)
	if _out != "":
		get_viewport().get_texture().get_image().save_png(_out + ".png")
		print("снимок: %s.png" % _out)
	print("=== QA_RALLY_ZONE_SHOT DONE ===")
	get_tree().quit()
