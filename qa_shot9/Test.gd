extends Node

## РЕНДЕР-ТЕСТ: снимок экрана с реальным HUD.
##
## Запускать БЕЗ --headless: в headless нечего снимать, кадр не рисуется.
## Ставит замок, выделяет артель рабочих (тот же случай, что на скриншотах
## заказчика) и сохраняет PNG рядом с проектом.
##
##   <godot> --path . res://qa_shot9/Test.tscn -- --out=C:/tmp/shot.png
##
## Разрешение окна берётся из --size=ШхВ (по умолчанию 1280x720).

var main: Node = null

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

func _run() -> void:
	var out: String = _arg("--out=", "user://hud_shot.png")
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
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 700.0)

	# Замок рядом с точкой старта игрока — чтобы в кадре был не голый луг
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(0.0, 0.0, 0.0)
	await frames(3)

	# Артель рабочих: у неё в панели показываются кнопки построек
	var workers: Array = []
	for i in range(5):
		var wk := Worker.new()
		wk.faction = Constants.FACTION_PLAYER
		main.world_add(wk)
		wk.global_position = Vector3(-4.0 + float(i) * 1.2, 0.0, 7.0)
		workers.append(wk)
	await frames(3)
	if main._camera != null:
		main._camera.jump_to(Vector3.ZERO, main._camera.max_height * 0.45)
	# Прокручиваем окно измерения притока целиком, порциями «как рейс рабочего»,
	# иначе на снимке будет либо пусто, либо всплеск от одной большой сдачи
	for i in range(140):
		if i % 20 == 0:
			ResourceManager.gather_resource(Constants.FACTION_PLAYER,
				Constants.RESOURCE_WOOD, 10.0)
			ResourceManager.gather_resource(Constants.FACTION_PLAYER,
				Constants.RESOURCE_GOLD, 6.0)
		main.hud._update_resource_income(0.1)
	main.hud.show_selection(workers)
	await frames(30)

	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(out)
	print("SHOT %s -> %s (%dx%d), err=%d" % [
		size_s, out, img.get_width(), img.get_height(), err])
	print("=== QA_SHOT9 DONE ===")
	get_tree().quit()
