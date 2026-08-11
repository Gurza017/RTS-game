extends Node

## РЕНДЕР-ТЕСТ ДВУХУРОВНЕВОГО ВЫДЕЛЕНИЯ.
##
## Запускать БЕЗ --headless (как и qa_shot9): в headless кадр не рисуется.
## Сохраняет ДВА снимка — уровень 1 (только компактные групповые иконки) и
## уровень 2 (карточки отрядов развёрнутого типа):
##
##   <godot> --path . res://qa_shot10/Test.tscn -- --out=C:/tmp/sel --size=1280x720
##
## получится <out>_lvl1.png и <out>_lvl2.png

var main: Node = null
var hud       = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _arg(name_eq: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s: String = a
		if s.begins_with(name_eq):
			return s.substr(name_eq.length())
	return def

func _shot(path: String, tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(path)
	print("SHOT %s -> %s (%dx%d), err=%d" % [
		tag, path, img.get_width(), img.get_height(), err])

func _run() -> void:
	var out: String = _arg("--out=", "user://sel")
	var size_s: String = _arg("--size=", "1280x720")
	var parts: PackedStringArray = size_s.split("x")
	var w: int = int(parts[0]) if parts.size() > 0 else 1280
	var h: int = int(parts[1]) if parts.size() > 1 else 720
	DisplayServer.window_set_size(Vector2i(w, h))
	get_tree().root.size = Vector2i(w, h)
	await frames(2)

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(4)
	hud = main.hud
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 900.0)

	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(0.0, 0.0, 0.0)
	await frames(3)

	# 4 отряда копейщиков и 3 отряда лучников — случай из задания
	var all: Array = []
	var sids: Array = []
	for i in range(4):
		sids.append(_squad("spearman", 8, Vector3(-12.0 + float(i) * 8.0, 0.0, 12.0), all))
	for i in range(3):
		sids.append(_squad("archer", 6 + i * 2, Vector3(-8.0 + float(i) * 8.0, 0.0, 20.0), all))
	await frames(4)
	# Пара званий, чтобы на карточках были звёзды
	GameManager.squads[int(sids[4])]["level"] = 2
	GameManager.refresh_star(int(sids[4]))
	GameManager.squads[int(sids[6])]["level"] = 5
	GameManager.refresh_star(int(sids[6]))
	# Одному отряду потреплем состав — шкала должна укоротиться
	var hurt: Array = GameManager.squad_members(int(sids[5]))
	for m in hurt:
		(m as Unit).current_health = (m as Unit).max_health * 0.4

	if main._camera != null:
		main._camera.jump_to(Vector3(0.0, 0.0, 14.0), main._camera.max_height * 0.42)
	# Прокрутить окно измерения притока, иначе цифры дохода будут пустыми
	for i in range(140):
		if i % 20 == 0:
			ResourceManager.gather_resource(Constants.FACTION_PLAYER,
				Constants.RESOURCE_WOOD, 10.0)
			ResourceManager.gather_resource(Constants.FACTION_PLAYER,
				Constants.RESOURCE_GOLD, 6.0)
		hud._update_resource_income(0.1)

	# ── УРОВЕНЬ 1 ────────────────────────────────────────────────────────────
	hud.show_selection(all)
	await frames(20)
	print("  уровень 1: слотов=%d, панель видна=%s" % [
		hud.type_slots(), str(hud._bottom_panel.visible)])
	_shot(out + "_lvl1.png", "уровень 1")

	# ── УРОВЕНЬ 2 (лучники) ──────────────────────────────────────────────────
	hud._on_type_filter_pressed("archer")
	await frames(20)
	print("  уровень 2: карточек=%d, подпись «%s»" % [
		hud._squad_strip.get_child_count(), hud.info_label.text])
	_shot(out + "_lvl2.png", "уровень 2")

	print("=== QA_SHOT10 DONE ===")
	get_tree().quit()

func _squad(kind: String, n: int, at: Vector3, out_all: Array) -> int:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	for i in range(n):
		var u: Unit = Archer.new() if kind == "archer" else Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = at + Vector3(float(i % 4) * 1.1, 0.0, float(i / 4) * 1.1)
		GameManager.add_to_squad(sid, u)
		out_all.append(u)
	return sid
