extends Node

## ОКОННЫЙ СНИМОК РЕЛЬЕФА (10.09.2026): плато с ничейным рудником и спуском,
## река в низине с зеркалом воды и откосами. Вердиктов нет — картинка для глаза.
## Запуск: godot --path . res://qa_map/Shot.tscn -- --out=<путь без .png>

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

func _shot(at: Vector3, size: float, suffix: String) -> void:
	main.focus_camera_on(at)
	await frames(4)
	(get_viewport().get_camera_3d() as Camera3D).size = size
	await frames(30)
	if _out != "":
		get_viewport().get_texture().get_image().save_png(_out + "_" + suffix + ".png")
		print("снимок: %s_%s.png" % [_out, suffix])

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
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	var plats: Array = main.plateau_list()
	var p0: Array = plats[0]
	await _shot(Vector3(float(p0[0]), 0.0, float(p0[1])), 70.0, "plateau")
	var zq: float = main.FORD_Z + main.FORD_HALF + 20.0
	await _shot(Vector3(main.river_x(zq), 0.0, zq), 50.0, "river")
	await _shot(Vector3(main.river_x(main.FORD_Z), 0.0, main.FORD_Z), 50.0, "ford")
	print("=== QA_MAP_SHOT DONE ===")
	get_tree().quit()
