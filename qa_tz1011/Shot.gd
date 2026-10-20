extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ ЗОНД ТЗ 11.10.2026: лагерь орды, ресурсы стартовой зоны, туман у
## верхней кромки, панели (вердиктов нет — снимки для глаза)
## ═══════════════════════════════════════════════════════════════════════════
## Снимки: camp — лагерь сверху (главная хата, серп хижин, площадка, рудник
## с охраной); zone — стартовая зона игрока без тумана (2 золота + 2 камня);
## fogedge — правый верх зоны игрока в тумане (макушки деревьев у кромки);
## start — старт партии как у владельца (туман, панели, окошко строя).
## Запуск: godot --windowed --position -5000,-5000 --path . res://qa_tz1011/Shot.tscn -- --out=<путь> bg=1

var main = null
var _out := ""

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(suffix: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, suffix])
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
	var cam = main.get("_camera")
	main.set_process(false)
	await _shot("start")
	# Туман у верхней кромки: правый верх зоны игрока
	# Как на скриншоте владельца: разведанный круг у верхней кромки, справа —
	# туман; смотрим на стык кромки карты и тумана
	GameManager.fog.add_permanent_reveal(Vector3(-160.0, 0.0, -100.0), 40.0)
	var fogp := Vector3(-120.0, 0.0, -105.0)
	cam.jump_to(fogp, 80.0)
	await frames(30)
	await _shot("fogedge")
	# Без тумана: зона игрока и лагерь
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	cam.jump_to(Vector3(-170.0, 0.0, -80.0), 110.0)
	await frames(30)
	await _shot("zone")
	var gc: Vector3 = main.goblin_village_center()
	# Лагерь — ЧЕСТНЫМ раскрытием тумана (как при подходе разведки), а не
	# выключением: так видно, что спящая охрана появляется на свету
	if GameManager.fog != null:
		GameManager.fog.enabled = true
		(GameManager.fog as Node3D).visible = true
		GameManager.fog.add_permanent_reveal(gc, 90.0)
	cam.jump_to(gc + Vector3(0, 0, 10), 75.0)
	await frames(30)
	await _shot("camp")
	var gm: Node3D = GameManager.goblin_mine
	if gm != null:
		print("  рудник лагеря %s, центр лагеря %s" % [gm.global_position, gc])
		var gai = main.goblin_ai
		for sid in gai.guards:
			var c: Vector2 = GameManager.squad_centre_xz(int(sid))
			print("   охрана %d %s: центр (%.0f, %.0f), пост %s, спит=%s" % [int(sid), GameManager.squad_type(int(sid)),
				c.x, c.y, gai.guards[sid]["post"], str(gai.guards[sid]["st"])])
		cam.jump_to(gm.global_position, 70.0)
		await frames(20)
		cam.set_process(false)     # иначе край окна за экраном катит камеру
		await frames(400)
		await _shot("campmine")
	print("=== TZ1011 SHOT DONE ===")
	get_tree().quit()
