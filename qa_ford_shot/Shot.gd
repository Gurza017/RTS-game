extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СНИМОК БРОДА: ЦВЕТ МЕЛКОВОДЬЯ И ТЕЛА В ВОДЕ (ТЗ 29.09.2026, блок 8)
## ═══════════════════════════════════════════════════════════════════════════
## Ставит на броде два отряда (люди и орда) лицом друг к другу, убивает часть
## бойцов в воде во всех ориентациях тела и сохраняет кадр: глазом проверяется,
## что вода светлая и мелкая, а у тел под водой НИЖНЯЯ по экрану половина, голова
## сухая. Вердикт один — тела в воде есть и они в мокром бакете. Запуск:
##   godot --windowed --position -5000,-5000 --path . res://qa_ford_shot/Shot.tscn -- bg=1 --out=<путь без .png>

var main = null
var _out: String = ""
var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 120 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_ford_shot: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _spawn(path: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1600, 900)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(10)
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n.has_method("set_process"):
			n.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	GameManager.world_bounds_enabled = true
	GameManager.refresh_map_bounds()
	var fz: float = main.FORD_Z
	var fx: float = main.river_x(fz)
	var centre := Vector3(fx, 0.0, fz)
	# Чужих партии у брода — прочь
	for u in GameManager._live_units.duplicate():
		if u != null and is_instance_valid(u) and (u as Node3D).global_position.distance_to(centre) < 60.0:
			(u as Unit).set_tick(false)
			(u as Node).queue_free()
	await pframes(4)
	main.focus_camera_on(centre)
	await frames(4)
	(main._camera as Node).set_process(false)
	var cam: Camera3D = get_viewport().get_camera_3d() as Camera3D
	cam.size = 14.0
	main.set_process(false)
	# Тела в воде: 16 бойцов обеих сторон по броду, все ориентации
	var men: Array = []
	for i in range(16):
		var fac: int = Constants.FACTION_PLAYER if i % 2 == 0 else Constants.FACTION_GOBLIN
		var path: String = "res://scenes/units/Spearman.tscn" if i % 2 == 0 else "res://scenes/units/GoblinSpearman.tscn"
		var p := centre + Vector3(-4.5 + float(i % 4) * 3.0, 0.0, -4.5 + float(i / 4) * 3.0)
		men.append(_spawn(path, fac, p))
	# И живые на берегах — для масштаба цвета
	for i in range(10):
		_spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER, centre + Vector3(-main.RIVER_HALF_W - main.RIVER_BANK - 3.0, 0.0, -6.0 + float(i) * 1.3))
		_spawn("res://scenes/units/GoblinSpearman.tscn", Constants.FACTION_GOBLIN, centre + Vector3(main.RIVER_HALF_W + main.RIVER_BANK + 3.0, 0.0, -6.0 + float(i) * 1.3))
	await pframes(20)
	var wet_before: int = GameManager.corpses.count()
	for u in men:
		if is_instance_valid(u):
			(u as Unit).take_damage((u as Unit).max_health * 10.0 + 1000.0, null)
	await pframes(10)
	var wet := 0
	for u in men:
		if u == null or not is_instance_valid(u):
			continue
	var bodies: int = GameManager.corpses.count() - wet_before
	verdict("A1 тела на броде легли (%d)" % bodies, bodies >= 12, "тел %d" % bodies)
	var wet_buckets := 0
	for key in GameManager.corpses._buckets:
		if String(key).find("|wet") >= 0:
			wet_buckets += 1
	verdict("A2 тела в воде — в мокрых бакетах", wet_buckets > 0, "мокрых бакетов %d" % wet_buckets)
	if _out != "":
		await frames(3)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out + ".png")
		print("  снимок: %s.png" % _out)
	_finish()
