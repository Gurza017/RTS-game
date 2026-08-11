extends Node

## СНИМОК КАДРА ИГРЫ. Запускается БЕЗ --headless: headless ничего не рисует,
## а ракурс — вопрос картинки, а не чисел. Ставит камеру в несколько
## характерных положений и сохраняет PNG в пользовательскую папку.

var main = null

const SHOT_DIR := "user://shots"

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(nm: String) -> void:
	# Ждём конца кадра: без этого в текстуре может лежать ещё не отрисованное
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = SHOT_DIR + "/" + nm + ".png"
	img.save_png(path)
	print("  снимок: %s (%d×%d) → %s" % [nm, img.get_width(), img.get_height(),
		ProjectSettings.globalize_path(path)])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)

	var cam: RTSCamera = main._camera
	print("  наклон камеры %.1f°, поворот %.1f°" % [cam._orbit_pitch, cam._orbit_yaw])

	# Ставим замок игрока В ЕГО УГЛУ, чтобы в кадре были постройки
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = a
	var barracks := Barracks.new()
	barracks.faction = Constants.FACTION_PLAYER
	main.world_add(barracks)
	barracks.global_position = a + Vector3(10.0, 0.0, 2.0)
	# Строй копейщиков перед замком — видно ли объём и фасады
	for i in range(40):
		var s := Spearman.new()
		s.faction = Constants.FACTION_PLAYER
		main.world_add(s)
		s.global_position = a + Vector3(-6.0 + float(i % 10) * 1.2, 0.0,
			8.0 + float(i / 10) * 1.2)
	await frames(60)

	# 1. База игрока со средней высоты
	cam._focus = a + Vector3(2.0, 0.0, 4.0)
	cam._target_height = 24.0
	cam._height = 24.0
	cam._update_position()
	await frames(10)
	print("  камера в (%.1f, %.1f, %.1f), фокус (%.1f, %.1f)" % [
		cam.global_position.x, cam.global_position.y, cam.global_position.z,
		cam._focus.x, cam._focus.z])
	await _shot("01_baza_srednyaya_vysota")

	# 2. Максимальное приближение — объём построек и деревьев
	cam._target_height = cam.min_height
	cam._height = cam.min_height
	cam._update_position()
	await frames(10)
	await _shot("02_blizko")

	# 3. Отдаление: проверяем потолок зума на прямоугольной карте
	for h in [70.0, 110.0]:
		cam._focus = Vector3(0.0, 0.0, 0.0)
		cam._target_height = h
		cam._height = h
		cam._update_position()
		await frames(10)
		await _shot("03_daleko_h%02d" % int(h))

	# 4. Юго-восточный край карты — бортик и чернота в кадре
	cam._focus = Vector3(main.CAM_BOUND_X, 0.0, main.CAM_BOUND_Z)
	cam._target_height = 30.0
	cam._height = 30.0
	cam._update_position()
	await frames(10)
	await _shot("04_kray_karty")

	print("=== SHOT DONE ===")
	get_tree().quit()
