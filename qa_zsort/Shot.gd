extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СТЕНД: БОЕЦ ПЕРЕД КАМНЕМ (ПОРЯДОК ПЕРЕКРЫТИЯ)
## ═══════════════════════════════════════════════════════════════════════════
## ЖАЛОБА ВЛАДЕЛЬЦА: «пехотинцы проваливаются под спрайты камней — камень
## перекрывает ноги солдата, стоящего ПЕРЕД ним».
##
## Судить это можно только глазом: в headless вызовов отрисовки ноль, а порядок
## перекрытия решает буфер глубины, который headless не заполняет вовсе.
##
## ── ДВА СНИМКА В ОДНОМ ПРОГОНЕ, И ЭТО ГЛАВНОЕ В СТЕНДЕ ────────────────────
## Мир генерируется по СЛУЧАЙНОМУ зерну, и два запуска дают разные карты — на
## них не сравнить ничего. Поэтому оба состояния снимаются в ОДНОМ кадре одной
## и той же сцены: ручка `ground_depth` в обоих шейдерах переключается прямо
## между снимками. Разница на двух картинках — это ровно правка, и ничего кроме.
##
##   godot --path . res://qa_zsort/Shot.tscn -- --out=<абс.путь без .png>

var _out := ""
var main = null
var _mats: Array = []          # материалы, у которых крутим ground_depth

func _ready() -> void:
	call_deferred("_run")

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _shot(suffix: String) -> void:
	for _i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %-10s вызовов отрисовки: %d, FPS %d" % [suffix,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Engine.get_frames_per_second())])

func _spawn(at: Vector3) -> Unit:
	var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Свободное от декораций место: свою декорацию ставим туда, где ей никто не
## мешает, иначе снимок судит о случайном лесе, а не о нашем камне
func _clear_spot(x0: float) -> Vector3:
	for r in range(0, 60, 3):
		for a in range(0, 12):
			var ang: float = TAU * float(a) / 12.0
			var p := Vector3(x0 + cos(ang) * float(r), 0.0, sin(ang) * float(r))
			if absf(p.x) > 110.0 or absf(p.z) > 55.0:
				continue
			if main.is_water(p.x, p.z):
				continue
			var ok := true
			for n in get_tree().get_nodes_in_group("resource_nodes"):
				var rn := n as ResourceNode
				if rn != null and rn.global_position.distance_to(p) < 16.0:
					ok = false
					break
			if ok:
				return p
	return Vector3(x0, 0.0, 0.0)

## Собрать все шейдерные материалы сцены, у которых есть ручка ground_depth
func _collect_mats(n: Node) -> void:
	var mi := n as GeometryInstance3D
	if mi != null:
		var m := mi.material_override as ShaderMaterial
		if m != null and m.shader != null:
			_mats.append(m)
		var mesh_holder := n as MeshInstance3D
		if mesh_holder != null and mesh_holder.mesh != null:
			for si in range(mesh_holder.mesh.get_surface_count()):
				var sm := mesh_holder.mesh.surface_get_material(si) as ShaderMaterial
				if sm != null:
					_mats.append(sm)
		var mm := n as MultiMeshInstance3D
		if mm != null and mm.multimesh != null and mm.multimesh.mesh != null:
			for si2 in range(mm.multimesh.mesh.get_surface_count()):
				var sm2 = mm.multimesh.mesh.surface_get_material(si2) as ShaderMaterial
				if sm2 != null:
					_mats.append(sm2)
	for c in n.get_children():
		_collect_mats(c)

func _set_ground_depth(v: float) -> void:
	_mats.clear()
	_collect_mats(main)
	var n := 0
	for m in _mats:
		var sm: ShaderMaterial = m
		if sm.shader == null:
			continue
		var code: String = sm.shader.code
		if code.find("ground_depth") >= 0:
			sm.set_shader_parameter("ground_depth", v)
			n += 1
	print("  ground_depth = %.0f у %d материалов" % [v, n])

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	if _out == "":
		push_error("нужен --out=<путь без расширения>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_tree().root.content_scale_size = Vector2i(1280, 720)

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	main.set_process(false)
	var cam = main.get("_camera")
	if cam != null:
		cam.set_process(false)
		cam.min_height = 5.0
	for node in get_tree().get_nodes_in_group("all_units"):
		(node as Node).queue_free()
	await pframes(6)

	# ── КАМЕНЬ БЕРЁМ С КАРТЫ, А НЕ СТРОИМ СВОЙ ─────────────────────────────
	# ResourceNode.new() без настройки рисуется не тем, чем видит игрок (проверено
	# снимком: вышел куст вместо каменной гряды). А сравнивать надо ТУ ЖЕ
	# декорацию, что в партии. Случайность карты при этом не мешает: оба снимка
	# делаются в ОДНОМ прогоне, на одном и том же камне
	# САМЫЙ КРУПНЫЙ: мелкий осколок бойца не перекроет вовсе, и снимок покажет
	# «всё хорошо» там, где просто нечему было ломаться
	var stone: ResourceNode = null
	var best_sz := -1.0
	for n2 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn2 := n2 as ResourceNode
		if rn2 == null or not is_instance_valid(rn2):
			continue
		if rn2.resource_type != Constants.RESOURCE_STONE:
			continue
		if rn2.size_scale > best_sz:
			best_sz = rn2.size_scale
			stone = rn2
	if stone == null:
		push_error("на карте нет камня")
		get_tree().quit(1)
		return
	print("  камень в %s, размер %.2f" % [str(stone.global_position), best_sz])
	await pframes(8)

	# ── БОЙЦЫ ЛЕСЕНКОЙ ПЕРЕД КАМНЕМ И ОДИН ПОЗАДИ ─────────────────────────
	# «Перед» — в сторону камеры, то есть БОЛЬШЕЕ z (камера смотрит вдоль −Z)
	for d in [0.8, 1.8, 3.0]:
		_spawn(stone.global_position + Vector3(float(d) * 0.5 - 0.8, 0.0, float(d)))
	_spawn(stone.global_position + Vector3(0.4, 0.0, -2.0))
	if cam != null:
		cam.jump_to(stone.global_position + Vector3(0.0, 0.0, 2.0), 6.5)
	await pframes(12)

	# СНАЧАЛА ПРЕЖНЕЕ ПОВЕДЕНИЕ, ПОТОМ ПРАВКА — в одном и том же кадре
	_set_ground_depth(0.0)
	await _shot("before")
	_set_ground_depth(1.0)
	await _shot("after")

	print("\n=== ZSORT SHOT DONE ===")
	get_tree().quit(0)
