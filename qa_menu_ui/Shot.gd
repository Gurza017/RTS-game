extends Node

## ОКОННЫЙ ЗОНД РЕДИЗАЙНА МЕНЮ (ТЗ 21.10.2026): снимки главного меню, трёх
## вкладок настроек, экрана загрузки, паузы, настроек поверх паузы и панели
## замка с колоколом. Вердиктов нет — снимки смотрит человек.
## Запуск: godot --audio-driver Dummy --windowed --position -5000,-5000
##   --path . res://qa_menu_ui/Shot.tscn -- --out=<папка> bg=1 [w=1600 h=900]

const _Loading := preload("res://scripts/ui/LoadingScreen.gd")

var _out := "user://menu_ui"
var _w := 1600
var _h := 900

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="): _out = s.substr(6)
		elif s.begins_with("w="): _w = int(s.substr(2))
		elif s.begins_with("h="): _h = int(s.substr(2))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(_w, _h))
	DirAccess.make_dir_recursive_absolute(_out)
	call_deferred("_run")
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, nm])
	print("  снимок %s/%s.png" % [_out, nm])

func _find(root: Node, nm: String) -> Node:
	if root.name == nm:
		return root
	for c in root.get_children():
		var r := _find(c, nm)
		if r != null:
			return r
	return null

func _run() -> void:
	await frames(5)
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	await frames(30)
	await _shot("1_menu")
	menu.show_page("options")
	var tabs := _find(menu, "SettingsTabs") as TabContainer
	for i in range(3):
		tabs.current_tab = i
		await frames(8)
		await _shot("2_options_%d" % i)
	menu.show_page("load")
	await frames(6)
	await _shot("3_load_page")
	menu.show_page("main")
	var ls = menu._show_loader()
	_Loading.stage("Генерация рельефа…", 0.46)
	await frames(60)
	await _shot("4_loading")
	_Loading.finish()
	await frames(80)
	remove_child(menu)
	menu.queue_free()
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(60)
	var hud = main.hud
	hud._pause_options_open = false
	hud._show_pause_menu()
	await frames(10)
	await _shot("5_pause")
	hud._open_pause_settings()
	await frames(10)
	await _shot("6_pause_settings")
	hud._clear_overlay()
	get_tree().paused = false
	await frames(5)
	var castle: Node = null
	for b in get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_PLAYER)):
		if b is Castle and (b as Castle).is_stronghold():
			castle = b
	if castle == null:
		var at := Vector3(-120, 0, 60)
		main._clear_trees(at, 30.0)
		castle = Castle.new()
		castle.faction = Constants.FACTION_PLAYER
		main.world_add(castle)
		castle.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
		await frames(10)
	main.selection_manager.select_units([castle])
	GameManager.on_selection_changed(main.selection_manager.selected_units, true)
	main.camera_jump_to(castle.global_position) if main.has_method("camera_jump_to") else null
	for k in range(60):
		await frames(1)
	await _shot("7_castle_panel")
	get_tree().quit()
