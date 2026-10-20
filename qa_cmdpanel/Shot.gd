extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ ЗОНД: ПАНЕЛЬ КОМАНД И МУЛЬТИ-ВЫБОР (ТЗ 10.10.2026, блок 4)
## ═══════════════════════════════════════════════════════════════════════════
## Снимки: one — один отряд (четыре кнопки A/C/S/F1); multi — смешанное
## выделение (сводные иконки родов + кнопки); detail — развёрнутый род
## (карточки отрядов: флаг, HP, опыт, число); hover — подсказка над кнопкой.
## Запуск: godot --windowed --position -5000,-5000 --path . res://qa_cmdpanel/Shot.tscn -- --out=<путь> bg=1

var main = null
var hud = null
var sm = null
var _out := ""
var _size := Vector2i(1280, 720)

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

func _squad(utype: String, n: int, at: Vector3, lvl: int = 0) -> int:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, utype)
	var scn: String = {"spearman": "Spearman", "archer": "Archer",
		"warrior": "Warrior", "monk": "Monk"}[utype]
	for i in range(n):
		var u: Unit = load("res://scenes/units/%s.tscn" % scn).instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var p := at + Vector3(float(i % 6) * 0.8, 0.0, float(i / 6) * 0.8)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
	if lvl > 0:
		GameManager.squads[sid]["level"] = lvl
	return sid

## Разбор раскладки панели: кто сколько требует (печать в лог зонда)
func _dump(n: Node, depth: int) -> void:
	if depth > 6 or not (n is Control):
		return
	var c := n as Control
	if not c.visible:
		return
	var ms: Vector2 = c.get_combined_minimum_size()
	print("  %s%s [%s] min=%s size=%s pos=%s" % ["  ".repeat(depth), c.name, c.get_class(), ms, c.size, c.position])
	for ch in c.get_children():
		_dump(ch, depth + 1)

func _select(sids: Array) -> void:
	sm._clear_selection()
	for sid in sids:
		for m in GameManager.squad_members(int(sid)):
			sm._select(m)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(6)

func _run() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	if _out == "":
		push_error("нужен --out=<путь без расширения>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(_size)
	get_tree().root.content_scale_size = _size
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	hud = main.hud
	sm  = main.selection_manager
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	await frames(6)
	var at := Vector3(-30.0, 0.0, 15.0)
	var all: Array = []
	for i in range(5):
		all.append(_squad("spearman", 12 + i, at + Vector3(i * 6.0, 0, 0), i % 3))
	for i in range(3):
		all.append(_squad("archer", 10, at + Vector3(i * 6.0, 0, 6), 1))
	for i in range(2):
		all.append(_squad("warrior", 8, at + Vector3(i * 6.0, 0, 12)))
	all.append(_squad("monk", 4, at + Vector3(0, 0, 18)))
	await frames(4)
	var cam = main.get("_camera")
	if cam != null:
		cam.jump_to(at + Vector3(10, 0, 8), 30.0)
		cam.set_process(false)
	await _select([all[0]])
	await _shot("one")
	var btn = hud._squad_cmd_btns.get("C")
	if btn != null:
		(btn as Control).mouse_entered.emit()
		await frames(3)
		await _shot("hover")
		(btn as Control).mouse_exited.emit()
	await _select(all)
	await _shot("multi")
	hud._on_type_filter_pressed("spearman")
	await frames(6)
	await _shot("detail")
	# ТЗ 11.10.2026 (второе письмо): размер плашки при разных родах и Tab
	hud._on_type_filter_pressed("archer")
	await frames(6)
	await _shot("detail_archer")
	_dump(hud._bottom_panel, 0)
	hud._on_type_filter_pressed("warrior")
	await frames(6)
	await _shot("detail_warrior")
	await _select([all[10]])
	await _shot("one_monk")
	# Панель рабочих (ТЗ 11.10.2026, ч. 1 п. 5): артель и одиночка
	var ws: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Worker:
			ws.append(u)
	sm._clear_selection()
	for w in ws:
		sm._select(w)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(6)
	await _shot("workers")
	sm._clear_selection()
	if not ws.is_empty():
		sm._select(ws[0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(6)
	await _shot("worker_one")
	print("=== CMDPANEL SHOT DONE ===")
	get_tree().quit()
