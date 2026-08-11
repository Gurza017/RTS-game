extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СНИМКИ РАКУРСА — qa_world3
## ═══════════════════════════════════════════════════════════════════════════
## Запускать БЕЗ --headless: headless вообще ничего не рисует, а «задран ли нос
## камеры» — вопрос картинки, а не числа. qa_shot снимает 5 кадров у базы;
## здесь добавлены ракурсы, которых там нет: оба края ПРЯМОУГОЛЬНОЙ карты
## по отдельности (длинная ось X и короткая Z ведут себя по-разному),
## угол ИИ, лесная подкова базы и потолок зума с облаками.
##
## Каждый кадр сопровождается ЧИСЛАМИ в консоли (высота, фокус, фактический
## наклон по basis, доля экрана, занятая картой) — чтобы картинку можно было
## сверить с геометрией, а не только «на глаз».

const SHOT_DIR := "user://shots3"

var main = null
var cam: RTSCamera = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

## Фактический наклон взгляда в градусах НИЖЕ ГОРИЗОНТА, посчитанный по
## мировой матрице камеры (а не по переменной _orbit_pitch)
func real_pitch() -> float:
	var fwd: Vector3 = -cam.global_transform.basis.z
	return rad_to_deg(asin(clampf(-fwd.y, -1.0, 1.0)))

## Доля центральной вертикали экрана, под которой лежит игровое поле.
## Остальное — бортик и чернота за краем мира
func map_share() -> float:
	var vp: Vector2 = Vector2(get_tree().root.size)
	var hits := 0
	var total := 0
	for i in range(101):
		var sy: float = vp.y * float(i) / 100.0
		var sc := Vector2(vp.x * 0.5, sy)
		var from: Vector3 = cam.project_ray_origin(sc)
		var dirn: Vector3 = cam.project_ray_normal(sc)
		total += 1
		if dirn.y >= -1e-5:
			continue                      # луч выше горизонта — земли не встретит
		var t: float = -from.y / dirn.y
		var p: Vector3 = from + dirn * t
		if absf(p.x) <= main.MAP_HALF_X and absf(p.z) <= main.MAP_HALF_Z:
			hits += 1
	return float(hits) / float(total)

func shot(nm: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = SHOT_DIR + "/" + nm + ".png"
	img.save_png(path)
	print("  [%s] %s" % [nm, note])
	print("      зум %.1f, фокус (%.1f, %.1f), наклон по матрице %.2f°, камера в (%.1f, %.1f, %.1f)" % [
		cam._height, cam._focus.x, cam._focus.z, real_pitch(),
		cam.global_position.x, cam.global_position.y, cam.global_position.z])
	print("      поле занимает %.0f%% центральной вертикали кадра → %s" % [
		map_share() * 100.0, ProjectSettings.globalize_path(path)])

## Ракурс задаётся ДОЛЕЙ диапазона зума (0 — вплотную, 1 — предельное
## отдаление), а не метрами: смысл величины _height зависит от проекции
## (высота подвеса в перспективе, охват кадра в ортографии) и уже менялся
func look(focus: Vector3, t: float) -> void:
	var h: float = lerpf(cam.min_height, cam.max_height, clampf(t, 0.0, 1.0))
	cam._focus = Vector3(
		clampf(focus.x, cam.bounds_min.x, cam.bounds_max.x), 0.0,
		clampf(focus.z, cam.bounds_min.y, cam.bounds_max.y))
	cam._target_height = h
	cam._height = h
	cam._update_position()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	cam = main._camera
	# Курсор стенда стоит в углу окна, и скролл краем экрана уводит фокус между
	# постановкой ракурса и снимком. Панораму глушим — снимаем ровно то, что задали
	cam.pan_speed = 0.0
	cam.edge_pan_margin = 0.0

	var pa: Vector3 = main.PLAYER_BASE_ANCHOR
	var ea: Vector3 = main.ENEMY_BASE_ANCHOR
	print("карта %.1f × %.1f, потолок зума %.1f м, пол зума %.1f м" % [
		main.MAP_HALF_X * 2.0, main.MAP_HALF_Z * 2.0, cam.max_height, cam.min_height])

	# База игрока: замок, барак и строй — чтобы в кадре были фасады и объём
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = pa
	var barracks := Barracks.new()
	barracks.faction = Constants.FACTION_PLAYER
	main.world_add(barracks)
	barracks.global_position = pa + Vector3(12.0, 0.0, 1.0)
	for i in range(40):
		var s := Spearman.new()
		s.faction = Constants.FACTION_PLAYER
		main.world_add(s)
		s.global_position = pa + Vector3(-6.0 + float(i % 10) * 1.2, 0.0,
			9.0 + float(i / 10) * 1.2)
	await frames(60)

	look(pa + Vector3(3.0, 0.0, 6.0), 0.30)
	await frames(8)
	await shot("01_baza_igroka",
		"база игрока с рабочего зума: видны ли ФАСАДЫ замка и стволы деревьев")

	look(pa + Vector3(3.0, 0.0, 6.0), 0.0)
	await frames(8)
	await shot("02_blizhniy_zum",
		"пол зума: не провалилась ли камера под землю, не перевернулась ли")

	look(Vector3.ZERO, 1.0)
	await frames(8)
	await shot("03_potolok_zuma_centr",
		"потолок зума над центром: читается ли карта, много ли черноты")

	look(Vector3(ea.x, 0.0, ea.z), 0.35)
	await frames(8)
	await shot("04_ugol_ii", "верхний правый угол: база ИИ, лес и кучи руды в углу")

	look(Vector3(main.CAM_BOUND_X, 0.0, 0.0), 0.55)
	await frames(8)
	await shot("05_kray_dlinnoy_osi_x", "восточный край ДЛИННОЙ оси X")

	look(Vector3(0.0, 0.0, -main.CAM_BOUND_Z), 0.55)
	await frames(8)
	await shot("06_kray_korotkoy_osi_z",
		"северный край КОРОТКОЙ оси Z: камера смотрит прямо на ближнюю кромку")

	look(pa + Vector3(0.0, 0.0, 2.0), 0.12)
	await frames(8)
	await shot("07_lesnaya_podkova_bazy",
		"лесной карман вокруг базы игрока: есть ли подкова деревьев вообще")

	look(Vector3(-40.0, 0.0, 30.0), 0.75)
	await frames(8)
	await shot("08_obshchiy_plan", "общий план над полем: объём леса и построек")

	print("=== SHOT3 DONE ===")
	get_tree().quit()
