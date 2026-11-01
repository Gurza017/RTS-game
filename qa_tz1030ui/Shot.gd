extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ ЗОНД ТЗ 30.10.2026 (интерфейс): панель рабочего, панель армии,
## смешанное выделение с рабочими, разблокировка построек, золото и тени
## ═══════════════════════════════════════════════════════════════════════════
## Снимки: a_worker, a_crew, b_army, b_army_tab, c_mixed, c_mixed_workers,
## d_lock_*, e_gold. Вердикты — в qa_tz1030ui/Test (headless).
## Запуск: godot --audio-driver Dummy --windowed --position -5000,-5000 --path .
##         res://qa_tz1030ui/Shot.tscn -- --out=<путь без .png> bg=1

const F := Constants.FACTION_PLAYER
var main = null
var _out := ""

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("СТОРОЖ: зонд не уложился в 240 с")
		get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(suffix: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if not _out.is_empty():
		img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

func _place(b: Building, at: Vector3, fac: int = F) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _spawn(kind: String, at: Vector3, fac: int = F) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int = F) -> int:
	var sid: int = GameManager.new_squad(fac, kind)
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % 5) * 0.7, 0, float(k / 5) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
	return sid

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var r := InputEventKey.new()
	r.keycode = code
	r.physical_keycode = code
	r.pressed = false
	Input.parse_input_event(r)
	await frames(4)

func _run() -> void:
	var stage := "all"
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		if s.begins_with("stage="):
			stage = s.substr(6)
		if s == "bg=1":
			GameManager._apply_background_window()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	for n in ["enemy_ai", "goblin_ai"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(F, r, 50000.0)
	var cam = main.get("_camera")
	cam.set_process(false)
	main.set_process(false)
	var sm = main.selection_manager
	var base := Vector3(-60.0, 0.0, 60.0)
	main._clear_trees(base, 45.0)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(base) < 70.0:
			u.queue_free()
	await frames(5)
	cam.jump_to(base, 34.0)
	var workers: Array = []
	for i in range(3):
		var w := _spawn("worker", base + Vector3(2.0 + float(i), 0, 2))
		workers.append(w)
	var sp_sid: int = _squad("spearman", base + Vector3(-8, 0, 6), 20)
	var mk_sid: int = _squad("monk", base + Vector3(8, 0, 6), 6)
	var ar_sid: int = _squad("archer", base + Vector3(-8, 0, -8), 15)
	var wr_sid: int = _squad("warrior", base + Vector3(8, 0, -8), 15)
	await frames(20)

	# A. панель рабочего (стадии разблокировки — если stage задан)
	sm.select_units([workers[0]])
	await frames(12)
	await _shot("a_worker")
	sm.select_units(workers.duplicate())
	await frames(12)
	await _shot("a_crew")

	# B. армия: несколько отрядов
	var army: Array = []
	for sid in [sp_sid, ar_sid, wr_sid, mk_sid]:
		army.append_array((GameManager.squads[sid]["members"] as Array).duplicate())
	sm.select_units(army)
	await frames(12)
	await _shot("b_army")
	# C. смешанное: копейщики + монахи + три рабочих
	var mixed: Array = []
	mixed.append_array((GameManager.squads[sp_sid]["members"] as Array).duplicate())
	mixed.append_array((GameManager.squads[mk_sid]["members"] as Array).duplicate())
	mixed.append_array(workers)
	sm.select_units(mixed)
	await frames(12)
	await _shot("c_mixed")
	await _key(KEY_TAB)
	await _shot("c_mixed_tab")
	await _key(KEY_TAB)
	await _key(KEY_TAB)
	await frames(8)
	await _shot("c_mixed_tab_workers")
	# B2. один род, три отряда: бейдж = 3, Tab раскрывает карточки
	var sp2: int = _squad("spearman", base + Vector3(-14, 0, 0), 20)
	var sp3: int = _squad("spearman", base + Vector3(-2, 0, 0), 20)
	await frames(10)
	var spears: Array = []
	for sid in [sp_sid, sp2, sp3]:
		spears.append_array((GameManager.squads[sid]["members"] as Array).duplicate())
	sm.select_units(spears)
	await frames(12)
	await _shot("b_spear3")
	await _key(KEY_TAB)
	await frames(8)
	await _shot("b_spear3_tab")

	# E. золото и постройки
	sm.select_units([])
	var gp: Vector3 = Vector3.INF
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(n) and int(n.get("resource_type")) == Constants.RESOURCE_GOLD:
			gp = (n as Node3D).global_position
			break
	if gp != Vector3.INF:
		cam.jump_to(gp, 22.0)
		await frames(20)
		await _shot("e_gold")
	var castle: Building = Castle.new()
	_place(castle, base + Vector3(-12, 0, -20))
	var house: Building = load("res://scripts/House.gd").new()
	_place(house, base + Vector3(6, 0, -22))
	var tw: Building = load("res://scripts/Tower.gd").new()
	_place(tw, base + Vector3(18, 0, -22))
	cam.jump_to(base + Vector3(0, 0, -20), 24.0)
	await frames(20)
	await _shot("e_buildings")
	# A2. крепость стоит — открылась овцеферма
	GameManager.note_building_done(F)
	sm.select_units([workers[0]])
	await frames(12)
	await _shot("a_worker_s1")
	print("=== QA_TZ1030UI SHOT DONE ===")
	get_tree().quit()
