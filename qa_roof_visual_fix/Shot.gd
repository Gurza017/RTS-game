extends Node

## ОКОННЫЙ СНИМОК: бараки (30 лучников на крыше), крепость (60) и башня (10)
## с гарнизоном — положение ног на скате и порядок перекрытия рядов судятся
## глазом. Вердиктов нет.
## Запуск: godot --path . res://qa_roof_visual_fix/Shot.tscn -- --out=<путь без .png>
##   --size=N  — ортографическая высота кадра (м), по умолчанию 30

var main = null
var _out: String = ""
var _size: float = 30.0
var _fx: float = 1.0
var _fz: float = -2.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--size="):
			_size = float(s.substr(7))
		elif s.begins_with("--fx="):
			_fx = float(s.substr(5))
		elif s.begins_with("--fz="):
			_fz = float(s.substr(5))
	call_deferred("_run")
	get_tree().create_timer(180.0).timeout.connect(func():
		print("  СТОРОЖ"); get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x - float(i / cols) * 0.9, 0.0,
			at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0), Vector3(0.0, 0.0, 12.0), Vector3(0.0, 0.0, -8.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
			if GameManager.is_water(p.x, p.z) or GameManager.is_water(p.x + 20.0, p.z) or GameManager.is_water(p.x - 20.0, p.z):
				h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _place(b: Building, at: Vector3) -> void:
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _inside(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and (u as Unit).garrisoned:
			n += 1
	return n

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
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(4)
	var base: Vector3 = _flat_spot(Vector3(-60.0, 0.0, -30.0))
	main._clear_area_of_resources(base, 45.0)
	await frames(2)
	print("  площадка: %s" % str(base))
	var F := Constants.FACTION_PLAYER
	var bar: Building = Barracks.new()
	_place(bar, base + Vector3(-16.0, 0.0, 0.0))
	var keep: Castle = Castle.new()
	_place(keep, base + Vector3(2.0, 0.0, 0.0))
	var tower: Building = load("res://scripts/Tower.gd").new()
	_place(tower, base + Vector3(18.0, 0.0, 0.0))
	await pframes(6)
	var s1: Array = _squad("archer", F, base + Vector3(-16.0, 0.0, 12.0), 30)
	var s2: Array = _squad("archer", F, base + Vector3(0.0, 0.0, 12.0), 30)
	var s3: Array = _squad("archer", F, base + Vector3(6.0, 0.0, 12.0), 30)
	var s4: Array = _squad("archer", F, base + Vector3(18.0, 0.0, 12.0), 30)
	await pframes(30)
	bar.request_garrison(int(s1[0]))
	keep.request_garrison(int(s2[0]))
	keep.request_garrison(int(s3[0]))
	tower.request_garrison(int(s4[0]))
	var all: Array = s1[1] + s2[1] + s3[1] + s4[1]
	for _i in range(60 * 40):
		await get_tree().physics_frame
		if _inside(all) == all.size():
			break
	print("  ЗОНД: внутри %d из %d" % [_inside(all), all.size()])
	await pframes(10)
	main.focus_camera_on(base + Vector3(_fx, 0.0, _fz))
	await frames(4)
	(main._camera as Node).set_process(false)
	(get_viewport().get_camera_3d() as Camera3D).size = _size
	await pframes(20)
	await frames(6)
	if _out != "":
		get_viewport().get_texture().get_image().save_png(_out + ".png")
		print("снимок: %s.png" % _out)
	print("=== QA_ROOF_VISUAL_SHOT DONE ===")
	get_tree().quit()
