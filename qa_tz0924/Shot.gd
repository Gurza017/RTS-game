extends Node

## ОКОННЫЙ ЗОНД ТЗ 24.09.2026: снимки для глаза (вердиктов нет).
##   ford   — брод: мелководье, галька, песчаные косы, тела в воде
##   wall   — лес-стена у зоны игрока и проход
##   smithy — рамка выделения кузницы перед кроной дерева
##   pen    — снесённый загон: пепелище плашмя, туши поверх
## Запуск: <godot> --path . res://qa_tz0924/Shot.tscn -- --out=<путь без .png>

const _CSiteS := preload("res://scripts/ConstructionSite.gd")
var main = null
var cam: RTSCamera = null
var _out: String = "user://tz0924"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			_out = String(a).substr(6)
	call_deferred("_run")
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _shot(tag: String, at: Vector3, h: float) -> void:
	cam.jump_to(at, h)
	for _i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, tag])
	print("  снимок %s_%s.png" % [_out, tag])

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(10):
		await get_tree().process_frame
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	main.set_process(false)
	cam = main.get("_camera") as RTSCamera
	cam.set_process(false)
	await pframes(4)
	# ── Брод: тела в воде ──────────────────────────────────────────────────
	var fx: float = main.river_x(main.FORD_Z)
	for i in range(6):
		var u := _unit("spearman", Constants.FACTION_PLAYER, Vector3(fx - 4.0 + float(i) * 1.6, 0.0, main.FORD_Z + 2.0))
		u.take_damage(99999.0)
	var t := _unit("big_goblin", Constants.FACTION_GOBLIN, Vector3(fx + 3.0, 0.0, main.FORD_Z - 3.0))
	t.take_damage(999999.0)
	await pframes(10)
	await _shot("ford", Vector3(fx, 0.0, main.FORD_Z), 30.0)
	await _shot("ford_wide", Vector3(fx, 0.0, main.FORD_Z), 70.0)
	# ── Лес-стена и проход вниз ────────────────────────────────────────────
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	var gx: float = a.x + main.WALL_GAP_DOWN_AT
	await _shot("wall", Vector3(gx, 0.0, main._wall_bottom_z(gx)), 70.0)
	# ── Кузница за деревом: рамка поверх кроны ─────────────────────────────
	var sp := Vector3(a.x + 25.0, 0.0, a.z + 8.0)
	var sm: Building = _CSiteS.make_building("smithy")
	sm.faction = Constants.FACTION_PLAYER
	main.world_add(sm)
	sm.global_position = Vector3(sp.x, GameManager.get_terrain_height(sp.x, sp.z), sp.z)
	var tree := ResourceNode.new()
	tree.resource_type = Constants.RESOURCE_WOOD
	tree.tree_variant = 2
	main.world_add(tree)
	tree.global_position = Vector3(sp.x + 1.5, GameManager.get_terrain_height(sp.x + 1.5, sp.z + 3.0), sp.z + 3.0)
	await pframes(4)
	sm.set_selected(true)
	await _shot("smithy", sp, 18.0)
	# ── Загон: снос, пепелище и туши ───────────────────────────────────────
	var pp := Vector3(a.x + 40.0, 0.0, a.z + 25.0)
	var pen: Building = _CSiteS.make_building("sheep_pen")
	pen.faction = Constants.FACTION_PLAYER
	pen.set("stock_on_ready", true)
	main.world_add(pen)
	pen.global_position = Vector3(pp.x, GameManager.get_terrain_height(pp.x, pp.z), pp.z)
	await pframes(6)
	await _shot("pen_alive", pp, 20.0)
	pen.call("_die")
	await pframes(6)
	await _shot("pen_ruin", pp, 20.0)
	get_tree().quit()
