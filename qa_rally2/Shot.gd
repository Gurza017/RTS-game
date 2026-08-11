extends Node

## СНИМКИ ФЛАЖКА ТОЧКИ СБОРА. Запускается БЕЗ --headless: headless ничего не
## рисует, а вопрос «видно ли флажок и там ли он стоит» — вопрос картинки.
## PNG кладутся туда же, куда их кладёт qa_shot (user://shots).
##
## ВАЖНО: у RTSCamera есть панорамирование мышью у края окна (edge_pan_margin).
## В обычном окне курсор ОС лежит где попало, и за 20 секунд камера уезжает
## сама. Поэтому её _process глушится, а ракурс ставится вручную перед каждым
## кадром. Заодно снимается отсечение дальних спрайтов (оно тоже завязано на
## _process камеры).

const _Opt = preload("res://scripts/perf_config.gd")

var main = null
var cam: RTSCamera = null

const SHOT_DIR := "user://shots"

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _aim(focus: Vector3, height: float) -> void:
	cam._focus = focus
	cam._target_height = height
	cam._height = height
	cam._update_position()
	GameManager.update_view_point(focus)

func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = SHOT_DIR + "/" + nm + ".png"
	img.save_png(path)
	print("  снимок: %s → %s" % [nm, ProjectSettings.globalize_path(path)])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	get_tree().root.size = Vector2i(1280, 720)
	_Opt.sprite_lod = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	cam = main._camera
	cam.set_process(false)          # никакого самохода камеры от курсора у края

	var at: Vector3 = main.PLAYER_BASE_ANCHOR
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = at
	var b2 := Barracks.new()
	b2.faction = Constants.FACTION_PLAYER
	main.world_add(b2)
	b2.global_position = at + Vector3(16.0, 0.0, 0.0)
	await frames(10)

	var spot: Vector3  = at + Vector3(-2.0, 0.0, 16.0)
	var spot2: Vector3 = at + Vector3(20.0, 0.0, 14.0)
	# Расчищаем пятачки под флажками: иначе древко тонет в кроне ёлки и по
	# снимку не понять, есть флажок или его загородило
	var cleared := 0
	for r in get_tree().get_nodes_in_group("resource_nodes"):
		var p: Vector3 = (r as Node3D).global_position
		if Vector2(p.x - spot.x, p.z - spot.z).length() < 7.0 \
				or Vector2(p.x - spot2.x, p.z - spot2.z).length() < 7.0:
			(r as Node).queue_free()
			cleared += 1
	await frames(5)
	print("  расчищено декораций у флажков: %d" % cleared)

	b.set_rally_point(spot)
	b2.set_rally_point(spot2)
	await frames(5)
	print("  барак 1 (%.0f, %.0f) → флажок (%.0f, %.0f)" % [
		b.global_position.x, b.global_position.z, spot.x, spot.z])
	print("  барак 2 (%.0f, %.0f) → флажок (%.0f, %.0f)" % [
		b2.global_position.x, b2.global_position.z, spot2.x, spot2.z])

	var wide := at + Vector3(7.0, 0.0, 8.0)

	# 1. Ничего не выделено — флажков быть не должно
	_aim(wide, 32.0)
	await frames(4)
	await _shot("r2_01_nichego_ne_vydeleno")

	# 2. Выделен барак 1 — только его флажок
	b.set_selected(true)
	await frames(4)
	await _shot("r2_02_vydelen_barak1")

	# 2б. Он же вблизи: видно древко, полотнище и кольцо на земле
	_aim(spot + Vector3(0.0, 0.0, -3.0), cam.min_height)
	await frames(4)
	await _shot("r2_02b_flazhok_vblizi")

	# 3. Переключились на барак 2
	_aim(wide, 32.0)
	b.set_selected(false)
	b2.set_selected(true)
	await frames(4)
	await _shot("r2_03_vydelen_barak2")

	# 4. Сняли выделение — флажки снова спрятаны
	b2.set_selected(false)
	await frames(4)
	await _shot("r2_04_snyali_vydelenie")

	# 5. Отряд идёт к флажку и встаёт ровно на нём
	b.set_selected(true)
	b.squad_size = 20
	b.queue_unit("spearman", {}, 0.01)
	(b.production_queue[0] as Dictionary)["time"] = 0.01
	for _i in range(60 * 25):
		await get_tree().process_frame
		_aim(wide, 32.0)          # камеру держим силой каждый кадр
	await _shot("r2_05_otryad_u_flazhka")

	# 6. Сброс точки — флажок обязан исчезнуть, отряд остаётся стоять
	b.clear_rally_point()
	await frames(10)
	_aim(wide, 32.0)
	await frames(2)
	await _shot("r2_06_tochka_sbrosena")

	print("=== RALLY2 SHOT DONE ===")
	get_tree().quit()
