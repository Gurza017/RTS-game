extends Node

## СНИМКИ ДЕРЕВНИ И ОРДЫ. headless не рисует ничего — окно обязательно.
## Запуск: <godot> --path . res://qa_goblin/Shot.tscn -- --out=<абс.путь без .png>
## Пишет три файла: _village (деревня целиком), _horde (отряд крупно),
## _scale (гоблин рядом с человеком — сравнение пропорций).

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var _out := ""
var _size := Vector2i(1280, 720)
var main = null

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

func _shot(suffix: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок: %s_%s.png" % [_out, suffix])

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--size="):
			var p := s.substr(7).split("x")
			if p.size() == 2:
				_size = Vector2i(int(p[0]), int(p[1]))
	if _out == "":
		push_error("нужен --out=<путь без расширения>")
		get_tree().quit(1)
		return
	# Окно проекта открывается Maximized, и window_set_size в этом режиме
	# молча игнорируется (см. qa_shotvis)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_size)
	get_tree().root.content_scale_size = _size

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(14)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	# ЧУЖИЕ ЗДАНИЯ ПРЯЧУТСЯ В МОМЕНТ РОЖДЕНИЯ (Building._ready -> set_fog_hidden),
	# а вернуть их обратно должен такт пелены — которого при выключенном тумане
	# уже не будет. Без этой строки деревня на снимке была пустой поляной
	for b in get_tree().get_nodes_in_group("all_buildings"):
		if is_instance_valid(b) and b.has_method("set_fog_hidden"):
			b.set_fog_hidden(false)
	main.set_process(false)
	var cam = main.get("_camera")
	if cam == null:
		push_error("нет камеры")
		get_tree().quit(1)
		return
	cam.set_process(false)
	cam.min_height = 6.0

	var village: Vector3 = main.goblin_village_center()
	# ── 1. Деревня целиком ──────────────────────────────────────────────────
	cam.jump_to(village, 46.0)
	await _shot("village")

	# ── 2. Отряд крупно ─────────────────────────────────────────────────────
	var sq := GameManager.squads_of_faction(Constants.FACTION_GOBLIN)
	var probe: int = 0
	for s2 in sq:
		var d: Dictionary = s2
		if String(d["type"]) == "goblin_spearman":
			probe = int(d["id"])
			break
	if probe > 0:
		cam.jump_to(GameManager.squad_centroid(probe), 16.0)
		await _shot("horde")

	# ── 3. Гоблин рядом с человеком: сравнение роста ────────────────────────
	var spot := Vector3(village.x, 0.0, village.z + 40.0)
	var pairs: Array = [
		["res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER, -2.0],
		["res://scenes/units/GoblinSpearman.tscn", Constants.FACTION_GOBLIN, 0.0],
		["res://scenes/units/GoblinPigRider.tscn", Constants.FACTION_GOBLIN, 2.0],
		["res://scenes/units/Warrior.tscn", Constants.FACTION_PLAYER, 4.0],
	]
	for pr in pairs:
		var a: Array = pr
		var u: Unit = load(String(a[0])).instantiate()
		u.faction = int(a[1])
		main.world_add(u)
		var x: float = spot.x + float(a[2])
		u.global_position = Vector3(x, GameManager.get_terrain_height(x, spot.z), spot.z)
		u.sync_row()
	await frames(10)
	cam.jump_to(Vector3(spot.x + 1.0, 0.0, spot.z), 8.0)
	await _shot("scale")

	print("=== QA_GOBLIN SHOT DONE ===")
	get_tree().quit(0)
