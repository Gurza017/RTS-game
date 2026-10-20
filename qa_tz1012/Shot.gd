extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ ЗОНД ТЗ 12.10.2026 (вердиктов нет — снимки для глаза)
## ═══════════════════════════════════════════════════════════════════════════
## blds — башня, бараки, крепость, стрелковая и дом на ровном месте, вокруг
##        каждой — кольцо бойцов на ring_radius (как кольцо трупов у башни):
##        рисунок обязан стоять в СЕРЕДИНЕ кольца;
## banner — отряды с рангами 1, 2, 3, 7 (римский штандарт, звезда, цифра);
## panel — выделен отряд: нижняя панель по центру, плашка ресурсов (нож);
## pen / mine — панели загона и рудника.
## Запуск: godot --windowed --position -5000,-5000 --path . res://qa_tz1012/Shot.tscn -- --out=<путь> bg=1

const F := Constants.FACTION_PLAYER
const _Tower := preload("res://scripts/Tower.gd")
const _House := preload("res://scripts/House.gd")
const _Archery := preload("res://scripts/Archery.gd")
var main = null
var _out := ""
var _off := false

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(200.0).timeout.connect(func(): get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(suffix: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

func _crop(suffix: String, r: Rect2i, k: int) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var c: Image = img.get_region(r)
	if k > 1:
		c.resize(r.size.x * k, r.size.y * k, Image.INTERPOLATE_NEAREST)
	c.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

func _place(b: Building, at: Vector3) -> void:
	b.faction = F
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _spawn(kind: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = F
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _ring(b: Building) -> void:
	var r: float = b.ring_radius() * 1.15 + 0.6
	var sid: int = GameManager.new_squad(F, "spearman")
	for k in range(16):
		var a: float = TAU * float(k) / 16.0
		var u := _spawn("spearman", b.global_position + Vector3(cos(a) * r, 0, sin(a) * r))
		GameManager.add_to_squad(sid, u)
		u.set_tick(false)

func _run() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		if s == "off=1":
			_off = true
	if _off:
		Building.sprite_front_on = false
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	var cam = main.get("_camera")
	main.set_process(false)
	var base := Vector3(-60.0, 0.0, 60.0)
	main._clear_trees(base, 40.0)
	var tw: Building = _Tower.new(); _place(tw, base + Vector3(-18, 0, -6))
	var br: Building = Barracks.new(); _place(br, base + Vector3(-4, 0, -6))
	var hs: Building = _House.new(); _place(hs, base + Vector3(9, 0, -6))
	var ar: Building = _Archery.new(); _place(ar, base + Vector3(20, 0, -6))
	var cs: Building = Castle.new(); _place(cs, base + Vector3(0, 0, 14))
	await frames(5)
	for b in [tw, br, hs, ar, cs]:
		print("  %s: draw_z=%.2f ring=%.2f half_w=%.2f" % [b.building_id, b._draw_z, b.ring_radius(), b._draw_half_w])
		_ring(b)
	cam.jump_to(base + Vector3(0, 0, 2), 34.0)
	await frames(30)
	cam.set_process(false)
	await _shot("blds")
	# ЗНАМЁНА: отряды с рангом 1, 2, 3, 7
	var bb := base + Vector3(0, 0, -28)
	main._clear_trees(bb, 20.0)
	var sids: Array = []
	for i in range(4):
		var sid: int = GameManager.new_squad(F, "spearman")
		for k in range(12):
			var u := _spawn("spearman", bb + Vector3(-15.0 + float(i) * 10.0 + float(k % 4) * 0.7, 0, float(k / 4) * 0.7))
			GameManager.add_to_squad(sid, u)
		sids.append(sid)
	var lv := [1, 2, 3, 7]
	for i in range(4):
		var sq: Dictionary = GameManager.squads[sids[i]]
		sq["level"] = lv[i]
		if GameManager.has_method("refresh_squad_banner"):
			GameManager.refresh_squad_banner(sids[i])
		elif main.has_method("refresh_squad_banner"):
			main.refresh_squad_banner(sids[i])
	cam.set_process(true)
	cam.jump_to(bb - Vector3(0, 0, 9), 14.0)
	await frames(40)
	cam.set_process(false)
	await _shot("banner")
	await _crop("bannerz", Rect2i(0, 120, 1280, 160), 2)
	# ПАНЕЛЬ ОТРЯДА — по центру
	var sm = main.selection_manager
	var men: Array = (GameManager.squads[sids[1]] as Dictionary)["members"].duplicate()
	if sm.has_method("select_units"):
		sm.select_units(men)
	else:
		sm.selected_units = men
		GameManager.on_selection_changed(men)
	await frames(20)
	await _shot("panel")
	await _crop("res", Rect2i(0, 0, 720, 70), 2)
	# ЗАГОН — панель с подробностями
	var pen_cls = load("res://scripts/SheepPen.gd")
	var pen: Building = pen_cls.new()
	_place(pen, base + Vector3(-30, 0, 30))
	await frames(10)
	sm.select_units([pen])
	await frames(20)
	await _crop("pen", Rect2i(380, 640, 860, 260), 1)
	# РУДНИК ИГРОКА с тремя рабочими
	var mine: Mine = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Mine:
			mine = b
			break
	if mine == null:
		for b in GameManager.nodes_in_group_cached(Constants.building_group(Constants.FACTION_NEUTRAL)):
			if b is Mine:
				mine = b
				break
	if mine != null:
		mine.set_owner_faction(F)
		for k in range(3):
			var w := _spawn("worker", mine.global_position + Vector3(3, 0, 3))
			GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
			mine._absorb(w)
		await frames(30)
		sm.select_units([mine])
		await frames(20)
		await _crop("mine", Rect2i(380, 640, 860, 260), 1)
		await _crop("res2", Rect2i(0, 0, 720, 70), 2)
	else:
		print("  рудника нет")
	print("=== TZ1012 SHOT DONE ===")
	get_tree().quit()
