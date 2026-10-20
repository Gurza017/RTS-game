extends Node
## Оконный зонд нижней панели армии (ТЗ 12.10.2026, второе письмо, блок 5):
## n1 — один отряд (приёмы видны); n12 — развёрнутый род из 12 отрядов;
## n30 — 30 отрядов (три ряда по десять); n3 — три отряда.
## Запуск: godot --windowed --position -5000,-5000 --path . res://qa_tz1012/ArmyShot.tscn -- --out=<путь> bg=1
const P := Constants.FACTION_PLAYER
var main = null
var _out := ""

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(150.0).timeout.connect(func(): get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _spawn(kind: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = P
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	u.set_tick(false)
	return u

func _crop(suffix: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var c: Image = img.get_region(Rect2i(0, img.get_height() - 360, img.get_width(), 360))
	c.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

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
	main.set_process(false)
	# Кузница: залп лучников изучен, чтобы приём был виден у одного отряда
	for nid in ["archer_1d"]:
		if GameManager.has_method("finish_research"):
			GameManager.finish_research(P, nid)
	var sids: Array = []
	var base := Vector3(-90, 0, 40)
	for i in range(30):
		var kind: String = "archer" if i < 30 else "spearman"
		var sid: int = GameManager.new_squad(P, kind)
		for k in range(3):
			GameManager.add_to_squad(sid, _spawn(kind, base + Vector3(float(i % 10) * 3.0, 0, float(i / 10) * 3.0 + float(k) * 0.5)))
		sids.append(sid)
	var spear: Array = []
	for i in range(4):
		var sid2: int = GameManager.new_squad(P, "spearman")
		for k in range(3):
			GameManager.add_to_squad(sid2, _spawn("spearman", base + Vector3(float(i) * 3.0, 0, 12.0 + float(k) * 0.5)))
		spear.append(sid2)
	# Ранги у части отрядов — значок «★N» в углу карточки
	for i in range(0, 30, 4):
		(GameManager.squads[sids[i]] as Dictionary)["level"] = 1 + (i / 4) % 7
	var sm = main.selection_manager
	var hud = main.hud
	for pair in [["n1", sids.slice(0, 1)], ["n3", sids.slice(0, 3)], ["n12", sids.slice(0, 12)], ["n30", sids]]:
		var list: Array = []
		for sid in (pair[1] as Array):
			list.append_array(GameManager.squads[sid]["members"])
		for sid in spear:
			list.append_array(GameManager.squads[sid]["members"])
		sm.select_units(list)
		await frames(3)
		hud._parent_sids = (pair[1] as Array) + spear
		hud._expand_type_from_parent("archer")
		await frames(5)
		await _crop(String(pair[0]))
	# Один отряд без разворота — приёмы на месте
	sm.select_units((GameManager.squads[sids[0]]["members"] as Array).duplicate())
	await frames(5)
	await _crop("single")
	get_tree().quit()
