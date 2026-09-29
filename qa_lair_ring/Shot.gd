extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СНИМОК: КОЛЬЦО ПНЯ (ТЗ 29.09.2026, скриншот 3)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: «красный круг отрисовывается отдельно и ниже самого пня». Заказ:
## круг шире, пень визуально по центру круга. Стенд наводит на пень курсорное
## кольцо и кольцо приказа, печатает геометрию (центр, радиус, овал, сдвиг) и
## сохраняет кадр. Вердикт один — центр кольца лежит ВЫШЕ основания рисунка
## по экрану (сдвиг от камеры), и кольцо шире основания. Запуск:
##   godot --windowed --position -5000,-5000 --path . res://qa_lair_ring/Shot.tscn -- bg=1 --out=<путь без .png>

var main = null
var _out: String = ""
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	call_deferred("_run")
	get_tree().create_timer(90.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 90 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_lair_ring: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1600, 900)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.call_deferred("thaw_lairs_now")
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	var lair = GameManager.troll_lair
	if lair == null or not is_instance_valid(lair):
		verdict("A0 пень на карте есть", false)
		_finish()
		return
	# Стражей и овец — прочь, чтобы не лезли в кадр
	for u in GameManager._live_units.duplicate():
		if u != null and is_instance_valid(u) and (u as Node3D).global_position.distance_to(lair.global_position) < 40.0:
			(u as Unit).set_tick(false)
			(u as Node).queue_free()
	await pframes(4)
	var lp: Vector3 = lair.global_position
	main.focus_camera_on(lp)
	await frames(4)
	(main._camera as Node).set_process(false)
	var cam: Camera3D = get_viewport().get_camera_3d() as Camera3D
	cam.size = 40.0
	main.set_process(false)
	GameManager.sel_decals.set_hover_units([lair], main.world_root())
	GameManager.sel_decals.set_order_targets([lair], main.world_root())
	await frames(3)
	var rc: Vector3 = lair.ring_center()
	var rb: Vector3 = lair.global_position + Vector3(lair._draw_cx, lair._draw_base_y, 0.0)
	var rr: float = lair.ring_radius()
	var ov: Vector2 = lair.ring_oval()
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var along: float = (rc - rb).dot(fwd)   # >0 — вдоль взгляда, ОТ камеры (вверх по экрану, под рисунок)
	print("  пень: центр рисунка %s, основание %s, центр кольца %s, радиус %.1f м, овал %s, сдвиг вдоль взгляда %.2f м" % [
		str(lp), str(rb), str(rc), rr, str(ov), along])
	verdict("A1 центр кольца сдвинут ОТ камеры (под рисунок), а не под основание",
		along > 0.5, "сдвиг %.2f м (плюс — от камеры, под рисунок)" % along)
	verdict("A2 кольцо шире основания рисунка (овал по X > 1)", ov.x > 1.05, "овал %s" % str(ov))
	if _out != "":
		await frames(2)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out + ".png")
		print("  снимок: %s.png" % _out)
	_finish()
