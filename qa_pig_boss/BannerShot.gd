extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД (ОКОННЫЙ): ЗНАМЯ СВИНОБОССА ЗА СПИНОЙ (ТЗ 30.10.2026, скриншот 01:46)
## ═══════════════════════════════════════════════════════════════════════════
## Знамя стояло древком у земли в точке босса, полотнище закрывало морду.
## Снимки: босс идёт вправо по экрану и влево — древко обязано торчать из-за
## спины (с противоположной взгляду стороны) и над головой. Вердиктов нет,
## кроме знака сдвига: древко сзади по взгляду.
##   godot --audio-driver Dummy --windowed --path . res://qa_pig_boss/BannerShot.tscn -- --out=<путь без .png>

const _Opt := preload("res://scripts/perf_config.gd")

var _out := ""
var _size := Vector2i(1280, 720)
var main = null

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился за 240 с")
		get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _shot(suffix: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

func _run() -> void:
	for a in OS.get_cmdline_user_args():
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
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	main.set_process(false)
	var cam = main.get("_camera")
	cam.set_process(false)
	cam.min_height = 6.0
	await pframes(4)
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, 40.0)
	main._clear_area_of_resources(base, 40.0)
	var sid: int = main.spawn_boss_squad(base)
	if sid <= 0:
		print("  босс не заведён")
		get_tree().quit()
		return
	var boss: Unit = null
	for m in GameManager.squads[sid]["members"]:
		if m != null and is_instance_valid(m) and (m as Unit).is_pig_boss():
			boss = m
	# Свиту — подальше, кадр только для босса
	for m in GameManager.squads[sid]["members"]:
		if m != boss and is_instance_valid(m):
			(m as Unit).command_move(base + Vector3(0.0, 0.0, 25.0))
	await pframes(30)
	var cr: Vector3 = GameManager.camera_right()
	for side in [1.0, -1.0]:
		var p: Vector3 = boss.global_position
		boss.command_move(p + cr * side * 30.0)
		await pframes(40)
		cam.jump_to(boss.global_position, 14.0)
		await pframes(4)
		var off: Vector3 = boss.banner_offset()
		var bn = GameManager.squads[sid].get("banner")
		var br = GameManager.squad_bearer(sid)
		print("  знаменосец %s (босс %s), знамя %s видно=%s в %s, босс в %s" % [
			str(br), str(boss), str(bn), str(bn.visible) if bn != null else "-",
			str(bn.global_position) if bn != null else "-", str(boss.global_position)])
		print("  взгляд %s: сдвиг знамени %s (по камере %.2f м, вверх %.2f м)" % [
			"вправо" if side > 0.0 else "влево", str(off), cr.dot(off), off.y])
		print("  ВЕРДИКТ знамя сзади по взгляду (%s): %s" % ["вправо" if side > 0.0 else "влево",
			"ПРОШЛО" if cr.dot(off) * side < 0.0 and off.y > 0.0 else "НЕ ПРОШЛО"])
		await _shot("right" if side > 0.0 else "left")
	print("=== QA_PIG_BOSS BANNER DONE ===")
	get_tree().quit()
