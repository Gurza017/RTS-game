extends Node
## Оконный зонд: копейщики лицом ВНИЗ (к камере) — видны ли наконечники копий.
## Ряды: идут вниз, стоят в «защите» лицом вниз, стоят в атаке, лицом вверх.
## Запуск: godot --windowed --position -5000,-5000 --path . res://qa_tz1012/SpearShot.tscn -- --out=<путь> bg=1
const P := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
var main = null
var _out := ""

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _crop(suffix: String, r: Rect2i, k: int) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var c: Image = img.get_region(r)
	if k > 1:
		c.resize(r.size.x * k, r.size.y * k, Image.INTERPOLATE_NEAREST)
	c.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

func _row(fac: int, at: Vector3, face: Vector3, stance: String) -> Array:
	var sid: int = GameManager.new_squad(fac, "spearman")
	var men: Array = []
	for i in range(8):
		var u := _spawn("spearman", fac, at + Vector3(float(i) * 0.9, 0, 0))
		GameManager.add_to_squad(sid, u)
		if u.has_method("set_stance"):
			u.set_stance(stance)
		men.append(u)
	var slots: Array = []
	for u in men:
		slots.append((u as Unit).global_position)
	GameManager.squad_set_formation(sid, slots, face, false)
	for u in men:
		(u as Unit).command_move((u as Unit).global_position + face * 0.05, false, face)
	return men

func _run() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.goblin_ai != null: main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	var cam = main.get("_camera")
	main.set_process(false)
	cam.jump_to(Vector3(-60, 0, 60), 14.0)
	await frames(10)
	cam.set_process(false)
	var c3: Camera3D = cam as Camera3D
	var sc: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var o: Vector3 = c3.project_ray_origin(sc)
	var dv: Vector3 = c3.project_ray_normal(sc)
	var base: Vector3 = o + dv * (-o.y / dv.y)
	base.y = 0.0
	main._clear_trees(base, 30.0)
	var down := Vector3(0, 0, 1)
	_row(P, base + Vector3(-9, 0, -3), down, "defense")
	_row(E, base + Vector3(1, 0, -3), down, "defense")
	_row(P, base + Vector3(-9, 0, 2), down, "attack")
	_row(E, base + Vector3(1, 0, 2), down, "attack")
	var walkers := _row(E, base + Vector3(-4, 0, -8), down, "attack")
	for u in walkers:
		(u as Unit).command_move((u as Unit).global_position + Vector3(0, 0, 30), false, down)
	await frames(60)
	await _crop("spear", Rect2i(0, 0, 1280, 720), 1)
	get_tree().quit()
