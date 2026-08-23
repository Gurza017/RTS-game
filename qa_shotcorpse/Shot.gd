extends Node

## ВРЕМЕННЫЙ СТЕНД: СНИМКИ ПОЛЯ ПОСЛЕ БОЯ И СЧЁТ ВЫЗОВОВ ОТРИСОВКИ.
##
## Зачем окно. headless не рисует ничего: ни тени, ни трупа, ни стрелы там нет,
## и счётчик вызовов отрисовки в нём всегда ноль. Всё, что проверяется здесь,
## существует только на экране — поэтому стенд оконный, как qa_shotvis.
##
## Запуск:
##   godot --path . res://qa_shotcorpse/Shot.tscn -- --out=<абс.путь без .png>
##
## Пишет три снимка:
##   _living — живые бойцы вблизи: тень под ступнями обязана быть мягкой серой,
##             а не плотной чёрной лужей (порок правился в mm_unit_sprite);
##   _pile   — завал тел: ни одного чёрного пятна сбоку от головы, под каждым
##             телом одно тугое пятно (mm_corpse + CorpseRenderer.SHADOW_FRAC);
##   _arrows — стрелы: воткнувшиеся стоят круто, в теле их по одной.
##
## И печатает то, ради чего всё затевалось: сколько вызовов отрисовки стоит
## поле боя с завалом и стрелами.

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

## Убить бойца СТРЕЛОЙ — то есть настоящим путём, с попаданием и втыканием.
## Подделывать тут нечего: именно этот путь и решает, останется ли стрела в теле
func _shoot(victim: Unit) -> void:
	var tp: Vector3 = victim.global_position
	var a := Arrow.new()
	a.faction = Constants.FACTION_PLAYER
	a.damage  = victim.max_health * 10.0 + 1000.0
	a._start_pos = tp + Vector3(-5.0, 2.2, -1.0)
	a._end_pos   = tp
	a._dist      = 5.5
	a._speed     = 40.0
	main.world_add(a)
	a.global_position = a._start_pos

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
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	main.set_process(false)
	var cam = main.get("_camera")
	if cam != null:
		cam.set_process(false)
		cam.min_height = 6.0

	# Площадки ищем ЧИСТЫЕ и внутри карты: за краем поля (|z| > MAP_HALF_Z)
	# рисуется чёрная плоскость, и снимок выходит чёрным, а в роще бойца
	# закрывает крона — оба раза судить по картинке нельзя
	var base: Vector3 = _clear_spot(-70.0)
	var pile: Vector3 = _clear_spot(-10.0)
	var lane: Vector3 = _clear_spot(50.0)
	print("вызовов отрисовки на пустом поле: %d"
		% int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	# ── 1. ЖИВЫЕ ВБЛИЗИ ────────────────────────────────────────────────────
	var alive: Array = []
	for i in range(6):
		alive.append(_spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER,
			base + Vector3(float(i % 3) * 1.6, 0.0, float(i / 3) * 1.6)))
	await pframes(6)
	cam.jump_to(base + Vector3(1.6, 0.0, 0.8), 8.0)
	await _shot("living")

	# ── 2. ЗАВАЛ ТЕЛ ───────────────────────────────────────────────────────
	var mob: Array = []
	for i in range(60):
		mob.append(_spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_ENEMY,
			pile + Vector3(float(i % 10) * 0.7 - 3.2, 0.0, float(i / 10) * 0.7 - 2.0)))
	await pframes(6)
	for u in mob:
		if is_instance_valid(u):
			u.take_damage(u.max_health * 10.0 + 1000.0, null)
	await pframes(4)
	cam.jump_to(pile, 11.0)
	await _shot("pile")

	# ── 3. СТРЕЛЫ: В ТЕЛАХ И В ГРУНТЕ ──────────────────────────────────────
	var shot_mob: Array = []
	for i in range(24):
		shot_mob.append(_spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_ENEMY,
			lane + Vector3(float(i % 6) * 1.1 - 2.8, 0.0, float(i / 6) * 1.1 - 1.6)))
	await pframes(6)
	for u in shot_mob:
		_shoot(u)
	# Промахи рядом: стрелы должны воткнуться в грунт круто, а не лечь плашмя
	for i in range(20):
		var miss := Arrow.new()
		miss.faction = Constants.FACTION_PLAYER
		miss.damage  = 0.0
		miss._start_pos  = lane + Vector3(-6.0, 2.4, float(i) * 0.35 - 3.5)
		miss._end_pos    = lane + Vector3(4.5, 0.0, float(i) * 0.35 - 3.5)
		miss._dist       = 10.5
		miss._speed      = 40.0
		miss._arc_factor = 0.12
		main.world_add(miss)
		miss.global_position = miss._start_pos
	await pframes(40)
	cam.jump_to(lane, 10.0)
	await _shot("arrows")

	# ── 4. ОДИНОЧНЫЕ ТЕЛА: ВИДНО ЛИ ПЯТНО ТЕНИ ─────────────────────────────
	# На завале тени перекрыты соседями, и судить по нему нельзя. Здесь тела
	# стоят порознь: под каждым обязан читаться мягкий ободок
	var solo := _clear_spot(90.0)
	var lone: Array = []
	for i in range(4):
		lone.append(_spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_ENEMY, solo + Vector3(float(i) * 2.6 - 3.9, 0.0, 0.0)))
	await pframes(6)
	for u in lone:
		if is_instance_valid(u):
			u.take_damage(u.max_health * 10.0 + 1000.0, null)
	await pframes(4)
	cam.jump_to(solo, 7.0)
	await _shot("solo")

	# ── 5. ЗВЁЗДЫ ВЕТЕРАНОВ: КАНТ И ПАЛИТРА ────────────────────────────────
	# Все три грейда рядом, над бойцами и над травой: кант обязан читаться на
	# любом фоне, а цвета — отличаться друг от друга с одного взгляда
	var vet := _clear_spot(-115.0)
	var lvls: Array = [1, 4, 7]
	for k in range(lvls.size()):
		var at: Vector3 = vet + Vector3(float(k) * 3.0 - 3.0, 0.0, 0.0)
		var u := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER, at)
		await pframes(2)
		var star = load("res://scripts/VeterancyStar.gd").create(int(lvls[k]))
		main.world_add(star)
		# Высоту над грунтом звезда ставит себе сама (VeterancyStar.STAR_HEIGHT),
		# и присваивание global_position её затирает — прибавляем обратно
		star.global_position = Vector3(at.x,
			GameManager.get_terrain_height(at.x, at.z) + star.position.y, at.z)
	await pframes(6)
	cam.jump_to(vet, 7.0)
	await _shot("stars")

	print("тел на поле: %d, торчащих стрел: %d"
		% [GameManager.corpses.count(), GameManager.stuck_arrow_count()])
	print("=== SHOTCORPSE DONE ===")
	get_tree().quit(0)

## Чистая площадка около заданного x: без деревьев, руды и воды в радиусе 13 м.
## Ищем по кольцам вокруг точки, а не «первое попавшееся»: карта заросшая
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
