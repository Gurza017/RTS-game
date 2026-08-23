extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЦЕНА ПОДСИСТЕМ В МИЛЛИСЕКУНДАХ КАДРА
## ═══════════════════════════════════════════════════════════════════════════
## qa_march_perf меряет ЧИСТУЮ армию: без ИИ, без тумана, без гоблинов, в окне
## 1280x720. Он показывает 180+ FPS там, где игрок видит 41 — то есть меряет
## не ту сцену. Здесь сцена собирается КАК В ПАРТИИ: ИИ, туман, деревня
## гоблинов, HUD, растительность, экономика — всё на месте.
##
## ЗАМЕР A/B, А НЕ ЛЕСТНИЦА. Первая версия гасила подсистемы по одной и
## сравнивала соседние строки — и намеряла, что выключение тумана ОТНИМАЕТ 17
## кадров. Причина в том, что мир между ступенями живёт: ИИ водит войска,
## гоблины просыпаются, экономика строит. Разность соседних строк меряла эту
## жизнь, а не подсистему. Теперь каждая подсистема гасится и ВОЗВРАЩАЕТСЯ, а
## её цена считается против СРЕДНЕГО двух базовых замеров вокруг неё.
##
## СЧИТАЕМ МИЛЛИСЕКУНДЫ, А НЕ КАДРЫ. Кадры не складываются: «минус 10 FPS» на
## 120 и на 45 — совершенно разные затраты. Миллисекунды складываются.
##
## Запуск (окно обязательно: в headless FPS — это темп главного цикла, а
## отрисовки нет вовсе):
##   godot --path . res://qa_fps/Test.tscn -- units=2000 res=1920x1080
##
## Аргументы: units=N (столько же у красного), res=WxH

const _Opt = preload("res://scripts/perf_config.gd")

var main = null
var _rows: Array = []
var _units: Array = []
var _foes: Array = []

var UNITS := 2000
var RES := Vector2i(1920, 1080)

const SQUAD_SIZE := 50
const COLS := 10
const GAP := 0.9

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

## Один замер. Прогрев обязателен: смена настройки почти всегда стоит одного
## тяжёлого кадра, а TIME_FPS усредняется по последней секунде и тянет этот
## кадр за собой ещё много замеров подряд
func _sample(warm: int = 40, n: int = 45) -> Dictionary:
	await frames(warm)
	var fps := 0.0
	var ph := 0.0
	var pr := 0.0
	var draws := 0
	for _i in range(n):
		await get_tree().process_frame
		fps += Performance.get_monitor(Performance.TIME_FPS)
		ph  += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		pr  += Performance.get_monitor(Performance.TIME_PROCESS)
		draws = maxi(draws, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var f: float = fps / float(n)
	return {
		"fps": f,
		"ms": 1000.0 / maxf(f, 0.001),
		"phys": ph / float(n) * 1000.0,
		"proc": pr / float(n) * 1000.0,
		"draws": draws,
	}

## Цена подсистемы: гасим — меряем — возвращаем — меряем базу снова.
## Положительное число в колонке «цена» означает «столько миллисекунд кадра
## она стоит». Возвращает свежую базу для следующего замера
func _cost(label: String, off: Callable, on: Callable,
		base_before: Dictionary) -> Dictionary:
	off.call()
	var without: Dictionary = await _sample()
	on.call()
	var base_after: Dictionary = await _sample()
	var base_ms: float = (float(base_before["ms"]) + float(base_after["ms"])) * 0.5
	_rows.append([label, base_ms - float(without["ms"]),
		float(without["fps"]), int(base_before["draws"]) - int(without["draws"])])
	return base_after

func _spawn_side(fac: int, at: Vector3, unit_scene: String) -> Array:
	var out: Array = []
	var squads: int = maxi(UNITS / SQUAD_SIZE, 1)
	var per_row: int = int(ceil(sqrt(float(squads))))
	for s in range(squads):
		var sid: int = GameManager.new_squad(fac, "spearman")
		var bx: float = at.x + float(s % per_row) * 12.0
		var bz: float = at.z + float(s / per_row) * 10.0
		var slots: Array = []
		for i in range(SQUAD_SIZE):
			var u: Unit = load(unit_scene).instantiate()
			u.faction = fac
			main.world_add(u)
			u.global_position = Vector3(
				bx + float(i % COLS) * GAP, 0.0, bz + float(i / COLS) * GAP)
			u.sync_row()
			GameManager.add_to_squad(sid, u)
			out.append(u)
			slots.append(u.global_position)
		# ── РАЗМЕТКА СТРОЯ ОБЯЗАТЕЛЬНА ─────────────────────────────────────
		# Без неё у отряда нет КУРСА, а без курса пакетный пересчёт рядов
		# (GameManager._push_squad_ranks) отказывается работать и каждый боец
		# считает ряд сам. В партии курс есть у любого отряда, получившего ПКМ,
		# и стенд без разметки мерил бы путь, которым игра почти не ходит
		GameManager.squad_set_formation(sid, slots, Vector3(0, 0, 1), false)
	return out

## Раздвинуть ортокамеру так, чтобы армия помещалась целиком: иначе стенд
## меряет отсечение пирамидой видимости, а не отрисовку войск
func _fit_camera(on: Array) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or on.is_empty():
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var mid := Vector3.ZERO
	for u in on:
		if not is_instance_valid(u):
			continue
		var p: Vector3 = (u as Node3D).global_position
		mid += p
		lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.z)
	mid /= float(on.size())
	main.focus_camera_on(Vector3(mid.x, 0.0, mid.z))
	await frames(2)
	if main._camera != null:
		(main._camera as Node).set_process(false)
	(cam as Camera3D).size = maxf(maxf((hi.x - lo.x) * 1.15,
		(hi.y - lo.y) * 1.7) + 10.0, 24.0)
	# РАДИУС LOD ЗАДАЁМ САМИ, как это делает камера в игре: её _process здесь
	# выключен, а без радиуса стенд мерил бы девяностометровый LOD на кадре,
	# показывающем полторы сотни метров (см. GameManager.update_view_point)
	var half: Vector2 = Vector2((hi.x - lo.x) * 0.5, (hi.y - lo.y) * 0.5)
	GameManager.update_view_point(Vector3(mid.x, 0.0, mid.z), half.length() + 4.0)

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("units="):
			UNITS = maxi(int(s.substr(6)), 50)
		elif s.begins_with("res="):
			var p := s.substr(4).split("x")
			if p.size() == 2:
				RES = Vector2i(int(p[0]), int(p[1]))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(RES)
	get_tree().root.content_scale_size = RES
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)

	_units = _spawn_side(Constants.FACTION_PLAYER, Vector3(-60.0, 0.0, -30.0),
		"res://scenes/units/Spearman.tscn")
	# Красный — ДАЛЕКО: стенд меряет «стоят», а не бой. Бой мерит qa_hotspot
	_foes = _spawn_side(Constants.FACTION_ENEMY, Vector3(60.0, 0.0, 40.0),
		"res://scenes/units/Spearman.tscn")
	await pframes(30)
	await _fit_camera(_units)
	# ── ДЛИННЫЙ ПРОГРЕВ ПОСЛЕ СПАВНА ───────────────────────────────────────
	# Спавн четырёх тысяч бойцов стоит секунд десять ОДНОГО кадра, а TIME_FPS
	# усредняется по последней секунде: без прогрева первые замеры показывали
	# семь кадров там, где сцена уже давно шла на шестидесяти
	await frames(180)

	# ── ЧЕСТНЫЕ СЧЁТЧИКИ ДВУХ БЛОКОВ КАДРА ─────────────────────────────────
	# Одна пара Time.get_ticks_usec на кадр вокруг ВСЕГО _physics_process и
	# ВСЕГО _process. Мониторы Performance для этого не годятся: при снятом
	# ограничении кадров они усредняются по кадрам отрисовки и дают то 10, то
	# 20 мс на одной и той же неподвижной сцене
	_Opt.tick_meter = true
	_Opt.vis_meter = true
	_Opt.tick_reset()
	_Opt.vis_reset()
	var base: Dictionary = await _sample()
	var tick_ms: float = _Opt.tick_ms()
	var vis_ms: float = _Opt.vis_ms()
	_Opt.tick_meter = false
	_Opt.vis_meter = false
	var base0: Dictionary = base.duplicate()

	base = await _cost("туман войны",
		func():
			if GameManager.fog != null:
				GameManager.fog.enabled = false
				(GameManager.fog as Node3D).visible = false,
		func():
			if GameManager.fog != null:
				GameManager.fog.enabled = true
				(GameManager.fog as Node3D).visible = true,
		base)

	base = await _cost("HUD",
		func():
			if main.hud != null:
				(main.hud as CanvasLayer).visible = false
				(main.hud as Node).set_process(false),
		func():
			if main.hud != null:
				(main.hud as CanvasLayer).visible = true
				(main.hud as Node).set_process(true),
		base)

	base = await _cost("мышление ИИ (красный + гоблины)",
		func(): _ai_process(false),
		func(): _ai_process(true),
		base)

	base = await _cost("растительность (отрисовка)",
		func(): _veg_visible(false),
		func(): _veg_visible(true),
		base)

	base = await _cost("деревня гоблинов (отрисовка)",
		func(): _group_visible("goblin_buildings", false),
		func(): _group_visible("goblin_buildings", true),
		base)

	base = await _cost("спрайты армии (отрисовка)",
		func(): _army_visible(false),
		func(): _army_visible(true),
		base)

	base = await _cost("ФИЗИЧЕСКИЙ ТИК АРМИИ",
		func(): _army_ticking(false),
		func(): _army_ticking(true),
		base)

	base = await _cost("визуальный тик армии",
		func(): _army_drawing(false),
		func(): _army_drawing(true),
		base)

	# ── РАЗБИВКА ФИЗИЧЕСКОГО ТИКА ПО ВЕТКАМ ────────────────────────────────
	# Профиль носит на себе свой же замер (две пары Time.get_ticks_usec на
	# ветку на бойца) и завышает сумму примерно вдвое — сравнивать его строки
	# можно только ДРУГ С ДРУГОМ, а не с базой выше
	_Opt.profile_physics = true
	_Opt.prof_reset()
	# ФИЗИЧЕСКИХ кадров, но ветки хвоста живут в кадре отрисовки: ждём ОБА,
	# иначе доли считались бы от разного числа проходов
	await pframes(120)
	await frames(1)
	var prof: Array = _Opt.prof_report()
	_Opt.profile_physics = false

	# ── ЦЕНА ВЫДЕЛЕНИЯ ─────────────────────────────────────────────────────
	# Разбор клика меряется ОТДЕЛЬНО от кадра: SelectionManager._select_one
	# ищет узел линейным перебором по массиву выделения, то есть весь разбор
	# квадратичен по числу бойцов. Это цена ОДНОГО клика, а не кадра, и путать
	# их нельзя — первая версия стенда именно так и намеряла «7 FPS»
	var sm = main.selection_manager
	var t_sel: int = Time.get_ticks_msec()
	sm._clear_selection()
	for u in _units:
		if is_instance_valid(u):
			sm._select(u)
	GameManager.on_selection_changed(sm.selected_units)
	var sel_ms: int = Time.get_ticks_msec() - t_sel
	await frames(180)
	var with_sel: Dictionary = await _sample()

	# ── МЕТКА ПОД НОГАМИ ДОЛЖНА СОВПАДАТЬ СО СПРАЙТОМ ──────────────────────
	for u in _units:
		if is_instance_valid(u):
			(u as Unit).command_move((u as Node3D).global_position
				+ Vector3(25.0, 0.0, 25.0))
	await frames(90)
	var gap := 0.0
	var lag := 0.0
	var checked := 0
	for u in _units:
		if not is_instance_valid(u):
			continue
		var unit: Unit = u
		var slot = GameManager.far_units._slot.get(unit, null)
		var ring: Vector3 = GameManager.sel_decals._last_pos.get(unit, Vector3.INF)
		if slot == null or ring.x == INF:
			continue
		checked += 1
		gap = maxf(gap, Vector2(slot.pos.x - ring.x, slot.pos.z - ring.z).length())
		lag = maxf(lag, Vector2(unit.draw_position().x - unit.global_position.x,
			unit.draw_position().z - unit.global_position.z).length())
	var marching: Dictionary = await _sample()

	print("\n═════ ЦЕНА ПОДСИСТЕМ В КАДРЕ ═════")
	print("  окно %dx%d | бойцов у игрока %d | всего юнитов %d" % [
		RES.x, RES.y, _units.size(), GameManager.active_units()])
	print("  шардов физики %d, визуальных %d, такт позы %d кадров" % [
		_Opt.shards_for(GameManager.active_units()),
		_Opt.vis_shards_for(GameManager.active_units()),
		_Opt.anim_every_for(GameManager.active_units())])
	print("  база: %.1f FPS (%.2f мс на кадр) | вызовов отрисовки %d" % [
		float(base0["fps"]), float(base0["ms"]), int(base0["draws"])])
	# Физика идёт фиксированные 60 Гц: при FPS ниже шестидесяти на один кадр
	# приходится больше одного физического тика, и цена тика на КАДР выше
	# самого тика. Без этой поправки разбор кадра не сходится
	var per_frame: float = tick_ms * (60.0 / maxf(float(base0["fps"]), 1.0))
	print("  физтик %.2f мс x %.2f тика на кадр = %.2f мс | весь кадр логики %.2f мс"
		% [tick_ms, 60.0 / maxf(float(base0["fps"]), 1.0), per_frame, vis_ms])
	print("  итого логика %.2f мс из %.2f мс кадра; остальное — движок и рендер"
		% [per_frame + vis_ms, float(base0["ms"])])
	print("\n  подсистема                          цена, мс   без неё, FPS   вызовов")
	print("  ──────────────────────────────────+──────────+─────────────+─────────")
	for r in _rows:
		var row: Array = r
		print("  %-34s %8.2f %13.1f %9d" % [String(row[0]), float(row[1]),
			float(row[2]), int(row[3])])

	print("\n─── РАЗБИВКА ФИЗ. ТИКА (профиль завышает сумму ~вдвое) ───")
	var sum_us := 0
	for row in prof:
		if not String(row[0]).begins_with("!"):
			sum_us += int(row[1])
	for row in prof:
		var bucket: String = String(row[0])
		var total_us: int = int(row[1])
		var calls: int = int(row[2])
		if bucket.begins_with("!"):
			print("  %-18s %8.2f мс/кадр НА ВСЮ АРМИЮ"
				% [bucket, float(total_us) / 1000.0 / float(maxi(calls, 1))])
			continue
		print("  %-18s %7.2f мс/кадр (%5.1f%%) | %8d вызовов | %6.2f мкс"
			% [bucket, float(total_us) / 1000.0 / 120.0,
			   100.0 * float(total_us) / float(maxi(sum_us, 1)),
			   calls, float(row[3])])

	print("\n  выделена вся армия: %.1f FPS (%.2f мс); сам разбор клика %d мс" % [
		float(with_sel["fps"]), float(with_sel["ms"]), sel_ms])
	print("  та же армия на марше: %.1f FPS (%.2f мс)" % [
		float(marching["fps"]), float(marching["ms"])])
	print("\n  метка под ногами: проверено %d, расхождение кольца со спрайтом %.3f м" % [
		checked, gap])
	print("  отставание картинки от логики %.3f м" % lag)
	print("\n=== QA_FPS DONE ===")
	get_tree().quit()

func _ai_process(on: bool) -> void:
	for f in ["enemy_ai", "goblin_ai"]:
		var n = main.get(f)
		if n == null:
			continue
		var un := n as Unit
		if un != null:
			un.set_draw(on)
			un.set_tick(on)
		else:
			(n as Node).set_process(on)
			(n as Node).set_physics_process(on)

func _group_visible(g: String, on: bool) -> void:
	for n in get_tree().get_nodes_in_group(g):
		var n3 := n as Node3D
		if n3 != null:
			n3.visible = on

## Спрятать САМИ СПРАЙТЫ армии, не трогая логику: разница показывает, сколько
## стоит отрисовка бойцов отдельно от их тика
func _army_visible(on: bool) -> void:
	var far = GameManager.far_units
	if far == null or not ("_buckets" in far):
		return
	for b in (far.get("_buckets") as Dictionary).values():
		if b != null and ("mmi" in b) and b.mmi != null:
			(b.mmi as Node3D).visible = on

## Снять с армии физический тик, оставив её на экране
func _army_ticking(on: bool) -> void:
	for u in GameManager._live_units:
		if is_instance_valid(u):
			(u as Unit).set_tick(on)

## Снять с армии ВИЗУАЛЬНЫЙ тик (поза, ракурс, LOD, перенос слота)
func _army_drawing(on: bool) -> void:
	for u in GameManager._live_units:
		if is_instance_valid(u):
			(u as Unit).set_draw(on)

func _veg_visible(on: bool) -> void:
	var v = GameManager.veg
	if v == null:
		return
	for f in ["_buckets", "_layers"]:
		if not (f in v):
			continue
		var d = v.get(f)
		if d is Dictionary:
			for b in d.values():
				if b != null and ("mmi" in b) and b.mmi != null:
					(b.mmi as Node3D).visible = on
