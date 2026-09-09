extends Node

## ЗОНД (не стенд): печатает числа по воротам замка, кольцам гарнизона и клику.
## Запуск: godot --headless --path . res://qa_keep/Probe.tscn

const _BBUtil := preload("res://scripts/BillboardUtil.gd")

var main = null
var sm = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await frames(4)

	var c := Castle.new()
	c.faction = Constants.FACTION_PLAYER
	main.world_add(c)
	c.global_position = Vector3(-90.0, GameManager.get_terrain_height(-90.0, 90.0), 90.0)
	await frames(6)

	print("\n===== ГЕОМЕТРИЯ ЗАМКА =====")
	print("  global_position      : %s" % str(c.global_position))
	print("  build_size           : %s" % str(c.build_size))
	print("  _draw_half_w         : %.3f" % c._draw_half_w)
	print("  _draw_cx             : %.3f" % c._draw_cx)
	print("  _draw_base_y         : %.3f" % c._draw_base_y)
	var spr: MeshInstance3D = c.get_node_or_null("BuildingSprite") as MeshInstance3D
	if spr != null:
		var q: QuadMesh = spr.mesh as QuadMesh
		var mat: ShaderMaterial = q.material as ShaderMaterial
		var tex: Texture2D = mat.get_shader_parameter("albedo_tex") as Texture2D
		var r: Rect2 = _BBUtil.opaque_rect(tex)
		var vs: float = _BBUtil.V_STRETCH
		print("  quad size            : %s" % str(q.size))
		print("  opaque_rect          : %s" % str(r))
		print("  нарисован от %.3f до %.3f м (с V_STRETCH)" % [
			q.size.y * (1.0 - r.end.y) * vs, q.size.y * (1.0 - r.position.y) * vs])
	print("  GATE_DISTANCE        : %.3f" % Castle.GATE_DISTANCE)
	print("  gate_depth()         : %.3f" % c.gate_depth())
	print("  facade_dir()         : %s" % str(c.facade_dir()))
	print("  spawn_offset         : %s" % str(c.spawn_offset))
	print("  _gate_position()     : %s" % str(c._gate_position()))
	print("  ворота от центра     : dx=%.3f dz=%.3f" % [
		c._gate_position().x - c.global_position.x,
		c._gate_position().z - c.global_position.z])
	print("  ring_center          : %s  ring_radius %.3f" % [str(c.ring_center()), c.ring_radius()])
	print("  SQUAD_EXIT_DISTANCE  : %.2f  SINGLE %.2f" % [
		c.SQUAD_EXIT_DISTANCE, c.SINGLE_AGENT_EXIT_DISTANCE])

	# ── КЛИК ПО КАРТИНКЕ ПРИ БОЙЦЕ ЗА ЗДАНИЕМ ──────────────────────────────
	var cam: Camera3D = main.get("_camera") as Camera3D
	main.focus_camera_on(c.global_position)
	await frames(3)
	var top_y: float = 0.0
	if spr != null:
		var q2: QuadMesh = spr.mesh as QuadMesh
		var m2: ShaderMaterial = q2.material as ShaderMaterial
		var t2: Texture2D = m2.get_shader_parameter("albedo_tex") as Texture2D
		var r2: Rect2 = _BBUtil.opaque_rect(t2)
		top_y = q2.size.y * (1.0 - r2.position.y) * _BBUtil.V_STRETCH
	print("\n===== КЛИК =====")
	for frac in [0.30, 0.55, 0.78, 0.92]:
		var aim: Vector3 = c.global_position + Vector3(c._draw_cx, c._draw_base_y + (top_y - c._draw_base_y) * frac, 0.0)
		var scr: Vector2 = cam.unproject_position(aim)
		# точка земли под этим курсором
		var from := cam.project_ray_origin(scr)
		var dirn := cam.project_ray_normal(scr)
		var t_g: float = -from.y / dirn.y
		var gp: Vector3 = from + dirn * t_g
		var pick: Dictionary = sm._pick_at(scr, Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS)
		print("  доля %.2f (y=%.2f): земля под курсором %s, отрыв от центра %.2f м -> %s" % [
			frac, aim.y, str(Vector2(gp.x, gp.z)),
			Vector2(gp.x - c.global_position.x, gp.z - c.global_position.z).length(),
			str(pick.get("target"))])

	# ── РАБОЧИЙ РОВНО В ТОЧКЕ ЗЕМЛИ ПОД ВЕРХОМ КАРТИНКИ ────────────────────
	var aim3: Vector3 = c.global_position + Vector3(c._draw_cx,
		c._draw_base_y + (top_y - c._draw_base_y) * 0.78, 0.0)
	var scr3: Vector2 = cam.unproject_position(aim3)
	var f3 := cam.project_ray_origin(scr3)
	var d3 := cam.project_ray_normal(scr3)
	var g3: Vector3 = f3 + d3 * (-f3.y / d3.y)
	var w: Unit = load("res://scenes/units/Worker.tscn").instantiate()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = Vector3(g3.x, GameManager.get_terrain_height(g3.x, g3.z), g3.z)
	w.sync_row()
	await pframes(6)
	# КАМЕРА МОГЛА ДОЕХАТЬ: экранную точку и точку земли пересчитываем ЗАНОВО,
	# иначе курсор указывает мимо замка и под ним честно нет ничего
	scr3 = cam.unproject_position(aim3)
	f3 = cam.project_ray_origin(scr3)
	d3 = cam.project_ray_normal(scr3)
	g3 = f3 + d3 * (-f3.y / d3.y)
	w.global_position = Vector3(g3.x, GameManager.get_terrain_height(g3.x, g3.z), g3.z)
	w.sync_row()
	await pframes(2)
	scr3 = cam.unproject_position(aim3)
	print("  рабочий в %s, соседей в сетке: %d, камера %s" % [
		str(w.global_position),
		GameManager.unit_grid.query_radius(w.global_position, 2.0).size(),
		str(sm.camera)])
	print("  слой замка: %d, здоровье рабочего %.1f, мёртв=%s" % [
		c.collision_layer, w.current_health, str(w.is_dead())])
	var pick3: Dictionary = sm._pick_at(scr3,
		Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS)
	print("  ПРИ РАБОЧЕМ В ТОЧКЕ ЗЕМЛИ (%.1f м за замком): под курсором %s" % [
		Vector2(g3.x - c.global_position.x, g3.z - c.global_position.z).length(),
		str(pick3.get("target"))])
	print("  замок=%s рабочий=%s" % [str(c), str(w)])

	# ── ГАРНИЗОН: ЧТО ОСТАЁТСЯ НА КАРТЕ ────────────────────────────────────
	print("\n===== ГАРНИЗОН =====")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(6):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = c.global_position + Vector3(float(i) * 0.7, 0.0, 9.0)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		u.set_selected(true)
		men.append(u)
	await pframes(4)
	print("  колец до входа: %d" % GameManager.sel_decals.registered_count())
	c.request_garrison(sid)
	for _i in range(600):
		await get_tree().physics_frame
		var inside := 0
		for m in men:
			if is_instance_valid(m) and (m as Unit).garrisoned:
				inside += 1
		if inside == men.size():
			break
	var inside2 := 0
	var still := 0
	for m in men:
		if is_instance_valid(m):
			if (m as Unit).garrisoned:
				inside2 += 1
			if GameManager.sel_decals.is_registered(m as Unit):
				still += 1
	print("  внутри: %d из %d" % [inside2, men.size()])
	print("  КОЛЕЦ ОСТАЛОСЬ НА КАРТЕ: %d" % still)
	for m in men:
		var u := m as Unit
		if is_instance_valid(u) and u.garrisoned:
			print("    боец: логическая %s, НАРИСОВАННАЯ %s" % [
				str(u.global_position), str(u.draw_position())])
			break
	print("  выделено в SM: %d" % sm.selected_units.size())

	print("\n=== PROBE DONE ===")
	get_tree().quit(0)
