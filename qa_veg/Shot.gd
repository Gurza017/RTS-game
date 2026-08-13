extends Node

## СНИМОК ЛЕСА. Растительность переехала в общий MultiMesh, и единственный
## способ проверить, что картинка осталась ПРЕЖНЕЙ, — посмотреть на неё.
## В headless не рисуется ничего, поэтому стенд ОКОННЫЙ (как qa_shot9/qa_shot10).
##
## Запуск: godot --path . res://qa_veg/Shot.tscn -- --out=<абс.путь>.png [--size=1280x720]
##         [--h=<высота камеры>] [--wait=<кадров>]

var _out := ""
var _size := Vector2i(1280, 720)
var _height := -1.0
var _wait := 150
var _at := Vector3.ZERO
var _at_set := false
var _near := ""

func _ready() -> void:
	call_deferred("_run")

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--size="):
			var p := s.substr(7).split("x")
			if p.size() == 2:
				_size = Vector2i(int(p[0]), int(p[1]))
		elif s.begins_with("--h="):
			_height = float(s.substr(4))
		elif s.begins_with("--wait="):
			_wait = int(s.substr(7))
		elif s.begins_with("--at="):
			var c := s.substr(5).split(",")
			if c.size() == 2:
				_at = Vector3(float(c[0]), 0.0, float(c[1]))
				_at_set = true
		elif s.begins_with("--near="):
			# Навести камеру на ближайшую кучу заданного ресурса: gold|stone
			_near = s.substr(7)
	if _out == "":
		push_error("нужен --out=<путь>.png")
		get_tree().quit(1)
		return

	DisplayServer.window_set_size(_size)
	get_tree().root.content_scale_size = _size

	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(10):
		await get_tree().process_frame

	# Туман мешает разглядывать арт — для снимков его гасим (enabled = false
	# заставляет is_lit отвечать «видно» везде, см. FogOfWar)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		# enabled=false только заставляет is_lit отвечать «видно»; сама пелена —
		# отдельная плоскость в мире, её надо ещё и спрятать
		(GameManager.fog as Node3D).visible = false
	var look_at := Vector3(-40.0, 0.0, 10.0)
	if _at_set:
		look_at = _at
	elif _near != "":
		var want: int = Constants.RESOURCE_GOLD if _near == "gold" else Constants.RESOURCE_STONE
		var best_d := INF
		for n in get_tree().get_nodes_in_group("resource_nodes"):
			var rn := n as ResourceNode
			if rn == null or rn.resource_type != want:
				continue
			var d: float = rn.global_position.length()
			if d < best_d:
				best_d = d
				look_at = rn.global_position
	var cam = main.get("_camera")
	if cam != null:
		cam.set_process(false)
		# Смотрим на лес, а не на пустое поле: точка выбрана в стороне от баз
		cam.jump_to(look_at,
			cam.min_height * 2.2 if _height < 0.0 else _height)

	# Ждём: у растительности своя анимация колыхания, и кадр надо брать после
	# того, как всё встало на места
	for _i in range(_wait):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("снимок: %s  (%dx%d)" % [_out, img.get_width(), img.get_height()])
	print("вызовов отрисовки: %d" % int(
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	get_tree().quit(0)
