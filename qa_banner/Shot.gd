extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СТЕНД: СЕМЬ ЗНАМЁН ВЕТЕРАНСТВА И УПАВШЕЕ ЗНАМЯ
## ═══════════════════════════════════════════════════════════════════════════
## Зачем окно. Знамя — это КАРТИНКА, и судить её можно только глазом. Вдобавок
## headless не собирает ни одного шейдера (правило проекта), а знамя рисуется
## тем же cyl_billboard, что и растительность: если он не соберётся, узнать об
## этом можно ровно здесь.
##
## Что проверяется ЧИСЛАМИ (печатается в консоль):
##   • сколько вызовов отрисовки стоит строй со знаменем — знамя обязано быть
##     ОДНИМ квадом на отряд, а не поверхностью на каждую фигуру;
##   • упавшее знамя обязано лечь В ТОТ ЖЕ MultiMesh, что и тела, то есть НЕ
##     добавить ни одного вызова сверх уже имеющихся бакетов.
##
## Что судится ГЛАЗОМ (снимки):
##   _ladder — все семь грейдов в ряд: вымпел с лычками, «ласточкин хвост»,
##             штандарт с бахромой и гербом;
##   _squad  — знамя на копье бойца в живом строю: древко обязано читаться
##             продолжением копья, а не палкой рядом со строем;
##   _fallen — упавшее знамя на земле рядом с телами.
##
## Запуск:
##   godot --path . res://qa_banner/Shot.tscn -- --out=<абс.путь без .png>

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _Banner := preload("res://scripts/SquadBanner.gd")
const _Art    := preload("res://scripts/BannerArt.gd")

var _out := ""
var _size := Vector2i(1280, 720)
var main = null

func _ready() -> void:
	call_deferred("_run")

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

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
	print("  снимок %-8s вызовов отрисовки: %d" % [suffix,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])

func _spawn(path: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--size="):
			var p := s.substr(7).split("x")
			if p.size() == 2:
				_size = Vector2i(int(p[0]), int(p[1]))
	if _out == "":
		push_error("нужен --out=<путь без расширения>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_size)
	get_tree().root.content_scale_size = _size

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
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
	if cam != null:
		cam.set_process(false)
		cam.min_height = 6.0
	await pframes(4)

	print("вызовов отрисовки на пустом поле: %d"
		% int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	await _ladder(cam)
	await _in_squad(cam)
	await _fallen(cam)

	print("=== QA_BANNER DONE ===")
	get_tree().quit()

## ── ЛЕСЕНКА: ВСЕ СЕМЬ ГРЕЙДОВ В РЯД ────────────────────────────────────────
## Узлы ставятся напрямую, минуя отряды: здесь судится КАРТИНКА, а не логика
## знаменосца (её проверяет headless-стенд qa_vet)
func _ladder(cam) -> void:
	var base: Vector3 = _clear_spot(-70.0)
	var n: int = _UCfg.VET_BANNER_TIERS.size()
	for i in range(n):
		var b: MeshInstance3D = _Banner.create(i + 1)
		main.world_add(b)
		var at := base + Vector3(float(i) * 2.2 - float(n - 1) * 1.1, 0.0, 0.0)
		b.place_at(at, GameManager.get_terrain_height(at.x, at.z))
		print("  грейд %d: %s" % [i + 1, _UCfg.veteran_rank_name("spearman", i + 1)])
	await pframes(4)
	cam.jump_to(base, 12.0)
	await _shot("ladder")

## ── ЗНАМЯ В ЖИВОМ СТРОЮ ────────────────────────────────────────────────────
## Главный вопрос картинки: читается ли древко продолжением копья знаменосца.
## Отряд поднимается настоящим путём, через GameManager, чтобы знаменосца
## выбрала та же машинерия, что и в партии
func _in_squad(cam) -> void:
	var base: Vector3 = _clear_spot(-10.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(16):
		var at := base + Vector3(float(i % 8) * 0.75 - 2.6, 0.0, float(i / 8) * 0.7)
		var u := _spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER, at)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	# Курс отряда: по нему выбирается «первый ряд, крайний левый»
	GameManager.squad_set_formation(sid, [], Vector3(0, 0, -1), false)
	(GameManager.squads[sid] as Dictionary)["level"] = 3
	GameManager.refresh_squad_banner(sid)
	await pframes(8)
	var bearer = GameManager.squad_bearer(sid)
	print("  знаменосец: %s, знамя=%s" % [
		str(bearer != null),
		str((GameManager.squads[sid] as Dictionary).get("banner") != null)])
	cam.jump_to(base, 9.0)
	await _shot("squad")
	# Убиваем знаменосца — знамя обязано переехать, а не пропасть
	if bearer != null:
		(bearer as Unit).take_damage(1e9, null)
	await pframes(6)
	print("  после гибели знаменосца: новый=%s" %
		str(GameManager.squad_bearer(sid) != null))
	await _shot("squad_after")
	for u in men:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await pframes(4)

## ── УПАВШЕЕ ЗНАМЯ ──────────────────────────────────────────────────────────
## Отряд выбивается ЦЕЛИКОМ, и знамя обязано лечь на поле слотом слоя тел.
## Считаем вызовы отрисовки до и после: лишних быть не должно, кроме одного
## бакета на саму ленту знамени
func _fallen(cam) -> void:
	var base: Vector3 = _clear_spot(55.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(12):
		var at := base + Vector3(float(i % 6) * 0.8 - 2.0, 0.0, float(i / 6) * 0.8)
		var u := _spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER, at)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	(GameManager.squads[sid] as Dictionary)["level"] = 7
	GameManager.refresh_squad_banner(sid)
	await pframes(6)
	var before: int = GameManager.corpses.count()
	var buckets0: int = GameManager.corpses.bucket_count()
	for u in men:
		if is_instance_valid(u):
			(u as Unit).take_damage(1e9, null)
	await pframes(8)
	var after: int = GameManager.corpses.count()
	print("  тел было %d, стало %d (12 бойцов + знамя = %d)"
		% [before, after, after - before])
	print("  бакетов лент: было %d, стало %d (+1 на ленту знамени)"
		% [buckets0, GameManager.corpses.bucket_count()])
	cam.jump_to(base, 9.0)
	await _shot("fallen")

## Чистая площадка около заданного x: без деревьев, руды и воды в радиусе 13 м.
##
## СНИМАТЬ НАДО ВНУТРИ КАРТЫ, и это не мелочь: за её краем (|z| > MAP_HALF_Z)
## рисуется чёрная плоскость, и снимок выходит целиком чёрным. Первый прогон
## этого стенда так и вышел — знамёна стояли на z = -220. Заодно ищем место без
## леса: в роще знамя закрывает крона, и судить по картинке нельзя
func _clear_spot(x0: float) -> Vector3:
	for r in range(0, 60, 3):
		for a in range(0, 12):
			var ang: float = TAU * float(a) / 12.0
			var p := Vector3(x0 + cos(ang) * float(r), 0.0, sin(ang) * float(r))
			if absf(p.x) > 110.0 or absf(p.z) > 55.0:
				continue
			if main.is_water(p.x, p.z):
				continue
			var ok := true
			for n in get_tree().get_nodes_in_group("resource_nodes"):
				var rn := n as ResourceNode
				if rn != null and rn.global_position.distance_to(p) < 13.0:
					ok = false
					break
			if ok:
				return p
	return Vector3(x0, 0.0, 0.0)
