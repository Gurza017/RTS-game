extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СТЕНД: КАК ВЫГЛЯДИТ ПАНЕЛЬ ВЕТЕРАНСТВА ПОСЛЕ РЕДИЗАЙНА
## ═══════════════════════════════════════════════════════════════════════════
## Headless судит СВОЙСТВА (см. Test.gd), а вид панели судят глазом: ровна ли
## левая ось, не жмётся ли колонка наград, читаются ли флажки ранга в строке.
## Снимки:
##   panel  — отряд ждёт награду: флажки ранга, крупные квадратные кнопки,
##            таблица статов с иконкой уже взятой награды справа
##   hover  — курсор на награде: плашка справа и зелёный предпросмотр в таблице
##   alert  — значок заслуженного ранга в углу (лычки, одна из них мигает)
##
## Запуск: godot --path . res://qa_vetui/Shot.tscn --out=<путь без расширения>

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var hud = null
var sm = null
var _out := ""
var _size := Vector2i(1280, 800)

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(suffix: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

func _run() -> void:
	for a in OS.get_cmdline_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	if _out == "":
		push_error("нужен --out=<путь без расширения>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_size)
	get_tree().root.content_scale_size = _size

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	hud = main.hud
	sm  = main.selection_manager
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	await frames(6)

	# Отряд-ветеран: второй ранг заслужен, награда не выбрана, одна награда уже
	# взята раньше — чтобы в таблице статов было что показать справа
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var at := Vector3(-30.0, 0.0, 15.0)
	for i in range(12):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var p := at + Vector3(float(i % 6) * 0.8, 0.0, float(i / 6) * 0.8)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
	var sq: Dictionary = GameManager.squads[sid]
	sq["level"] = 2
	sq["pending"] = 1
	sq["chosen"] = ["armor"]
	sq["kills"] = _UCfg.veteran_threshold("spearman", 2)
	await frames(4)
	var cam = main.get("_camera")
	if cam != null:
		cam.jump_to(at, 26.0)
		cam.set_process(false)
	sm._clear_selection()
	for m in GameManager.squad_members(sid):
		sm._select(m)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(6)
	await _shot("panel")

	# Наведение на награду: плашка справа + предпросмотр статов
	var btns: Array = hud.button_container.get_children()
	if not btns.is_empty():
		(btns[btns.size() - 1] as Button).mouse_entered.emit()
		await frames(3)
		await _shot("hover")
		(btns[btns.size() - 1] as Button).mouse_exited.emit()
		await frames(2)

	# Значок ранга в углу: лычки вместо звезды
	hud._alert_sig = ""
	hud._refresh_alert_stack()
	await frames(4)
	await _shot("alert")

	print("=== VETUI SHOT DONE ===")
	get_tree().quit()
