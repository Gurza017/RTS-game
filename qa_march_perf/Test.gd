extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ПРОФИЛЬ МАРША: 15 ОТРЯДОВ ПО 54 БОЙЦА ИДУТ В ТОЧКУ
## ═══════════════════════════════════════════════════════════════════════════
## Воспроизводит ТОЧНЫЙ симптом из отчёта игрока:
##   стоят после выхода из барака — 70-75 FPS;
##   выделил все 15 отрядов, отправил маршем — 4-7 FPS и не поднимается.
##
## qa_perf меряет БОЙ, а не МАРШ, и потому этот случай не ловит.
## Здесь врагов нет вовсе: если провал воспроизводится, он в пути движения,
## а не в поиске цели.
##
## Замеры: (1) стоят, (2) идут. В каждом — разбивка физ. тика по веткам.

const _OptCfg = preload("res://scripts/perf_config.gd")

## ЧИСЛА ОТРЯДА ПЕРЕОПРЕДЕЛЯЮТСЯ АРГУМЕНТОМ, а не правкой файла: тот же стенд
## нужен и на 810 бойцах (случай из отчёта), и на 2000-5000 (заказ владельца на
## 80 FPS). Запуск: `... res://qa_march_perf/Test.tscn -- squads=40 size=54`
static var SQUADS := 15
static var SIZE   := 54
static var COLS   := 9

## Разбор аргументов. Отдельным методом, чтобы стенд читал их РАНЬШЕ спавна и
## печатал в шапке уже настоящие числа
func _read_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("squads="):
			SQUADS = maxi(int(s.substr(7)), 1)
		elif s.begins_with("size="):
			SIZE = maxi(int(s.substr(5)), 1)
		elif s.begins_with("cols="):
			COLS = maxi(int(s.substr(5)), 1)

var main = null
var _units: Array = []
var _squads: Array = []

func _ready() -> void:
	call_deferred("_run")

## ФИЗИЧЕСКИЕ кадры: при Engine.max_fps = 0 рендер тикает быстрее физики,
## и ожидание process_frame не соответствует симулированному времени
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _avg(mon: int, n: int) -> float:
	var acc := 0.0
	for _i in range(n):
		await get_tree().process_frame
		acc += Performance.get_monitor(mon)
	return acc / float(n)

## КАМЕРА ОБЯЗАНА СМОТРЕТЬ НА ВОЙСКА. Без этого спрайты отсекаются пирамидой
## видимости, вызовов отрисовки остаётся 234 на 810 бойцов, и стенд меряет
## что угодно, кроме симптома игрока
## КАМЕРУ НАДО ПРИБИТЬ. Её _process крутит краевую прокрутку по позиции курсора,
## а курсор в запущенном стендом окне стоит в углу — за первые же секунды замера
## камера уезжала в угол карты, все 810 бойцов оказывались вне near_view и вне
## пирамиды видимости, и стенд мерил пустой экран (вызовов ~230 на 810 моделей).
## Здесь камера один раз наводится в (0,0) и её _process выключается; точку
## обзора для LOD с этого момента держит сам стенд
func _freeze_camera() -> void:
	if main == null:
		return
	main.focus_camera_on(Vector3.ZERO)
	await get_tree().process_frame
	if main._camera != null:
		(main._camera as Node).set_process(false)
	GameManager.update_view_point(Vector3.ZERO)

func _look_at_troops() -> void:
	GameManager.update_view_point(Vector3.ZERO)

## ПОЧЕМУ В КАДРЕ НЕТ СПРАЙТОВ. Отвечает на вопрос прямо: сколько бойцов
## отдано в дальний MultiMesh, у скольких видим свой узел, где стоит камера
func _visibility_note() -> String:
	var far := 0
	var vis := 0
	var near := 0
	for u in _units:
		if not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu._far_registered:
			far += 1
		if GameManager.near_view(uu.global_position):
			near += 1
		var spr = uu._active_sprite
		if spr != null and is_instance_valid(spr) and (spr as Node3D).visible:
			vis += 1
	# СКОЛЬКО ФИЗИЧЕСКИХ ТЕЛ ЗНАЕТ ДВИЖОК. Ради этого числа и затевался уход от
	# CharacterBody3D: qa_node_cost намерил 5.7 мкс на тело в кадр ЗА ОДИН ФАКТ
	# его существования (900 тел с пустым тиком — 5.72 мс/кадр против 0.66 мс у
	# Node3D). Этой статьи нет в «!ВЕСЬ ТИК ЮНИТОВ»: её платит PhysicsServer3D
	# вне нашего цикла, поэтому проверяется она так — счётчиком тел
	var bodies: int = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var cam := get_viewport().get_camera_3d()
	var cpos := Vector3.ZERO
	var csize := 0.0
	if cam != null:
		cpos = cam.global_position
		csize = (cam as Camera3D).size
	return "далеко(MultiMesh) %d | near_view %d | видимых спрайтов %d | ФИЗ.ТЕЛ %d | камера %.0f,%.0f,%.0f size %.0f" % [
		far, near, vis, bodies, cpos.x, cpos.y, cpos.z, csize]

## Снимок кадра в файл: единственный способ проверить, что армия, переехавшая
## в общий MultiMesh, выглядит как раньше
func _shot(nm: String) -> void:
	var dir: String = "res://qa_march_perf/shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [dir, nm]
	img.save_png(path)
	print("  снимок: %s" % ProjectSettings.globalize_path(path))

## Пара снимков крупным планом: новая общая отрисовка и прежняя, узлами.
## Между ними обязана быть НЕОТЛИЧИМАЯ картинка
func _shot_pair(nm: String) -> void:
	var cam := get_viewport().get_camera_3d()
	var old_size: float = 48.0
	if cam != null:
		old_size = (cam as Camera3D).size
		(cam as Camera3D).size = 10.0
	await frames(3)
	await _shot("%s_mm" % nm)
	_OptCfg.mm_render_all = false
	# Двух кадров хватает, чтобы бойцы вернули себе свои узлы-спрайты
	await frames(6)
	await _shot("%s_nodes" % nm)
	_OptCfg.mm_render_all = true
	await frames(6)
	if cam != null:
		(cam as Camera3D).size = old_size
	await frames(2)

func _measure(label: String) -> Dictionary:
	_look_at_troops()
	await frames(30)
	_look_at_troops()
	var phys: float = await _avg(Performance.TIME_PHYSICS_PROCESS, 120)
	var proc: float = await _avg(Performance.TIME_PROCESS, 120)
	var draws: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs: float  = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var fps: float   = Performance.get_monitor(Performance.TIME_FPS)
	var total: float = (phys + proc) * 1000.0
	var moving := 0
	for u in _units:
		if is_instance_valid(u) and (u as Unit).state == Unit.State.MOVING:
			moving += 1
	print("  %-26s физика %7.2f | кадр %7.2f | сумма %7.2f мс | FPS %5.1f | вызовов %5d | объектов %5d | в движении %d" % [
		label, phys * 1000.0, proc * 1000.0, total, fps, int(draws), int(objs), moving])
	print("     %s" % _visibility_note())
	return {"phys": phys, "proc": proc, "total": total, "fps": fps}

func _breakdown(label: String) -> void:
	_OptCfg.profile_physics = true
	_OptCfg.prof_reset()
	await frames(120)
	var rows: Array = _OptCfg.prof_report()
	_OptCfg.profile_physics = false
	print("\n─── РАЗБИВКА ФИЗ. ТИКА: %s (120 физ. кадров) ───" % label)
	# Бакеты с «!» — это итог по всему тику, а не отдельная ветка: в сумму долей
	# они не входят, иначе каждая ветка была бы посчитана дважды
	var sum_us := 0
	for row in rows:
		if String(row[0]).begins_with("!"):
			continue
		sum_us += int(row[1])
	for row in rows:
		if String(row[0]).begins_with("!"):
			var t_us: int = int(row[1])
			var t_frames: int = maxi(int(row[2]), 1)
			print("  %-18s %9.2f мс всего | %6d физ. кадров | %6.2f мс/кадр НА ВСЕХ БОЙЦОВ"
				% [String(row[0]), float(t_us) / 1000.0, t_frames,
				   float(t_us) / 1000.0 / float(t_frames)])
			continue
		var bucket: String = String(row[0])
		var total_us: int  = int(row[1])
		var calls: int     = int(row[2])
		var avg_us: float  = float(row[3])
		var share: float   = 100.0 * float(total_us) / float(maxi(sum_us, 1))
		print("  %-18s %9.2f мс всего (%5.1f%%) | %8d вызовов | %6.2f мкс/вызов"
			% [bucket, float(total_us) / 1000.0, share, calls, avg_us])
	print("  сумма веток: %.2f мс за 120 кадров = %.2f мс/кадр"
		% [float(sum_us) / 1000.0, float(sum_us) / 1000.0 / 120.0])

## Отряды стоят кирпичами бок о бок, как после выхода из барака
func _spawn() -> void:
	for s in range(SQUADS):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		_squads.append(sid)
		# ВОЙСКА СТАВЯТСЯ В КАДР. Ортокамера смотрит в (0,0) с size 48, поэтому
		# блок 5×3 отрядов с шагом 10×8 м умещается целиком; иначе пирамида
		# видимости отсекает спрайты и стенд меряет пустой экран
		# Сетка отрядов КВАДРАТНАЯ по числу отрядов, а не «пять в ряд»: на
		# сорока отрядах ряд из пяти уходил бы вглубь на шестьдесят метров,
		# пирамида видимости срезала бы половину армии, и стенд мерил бы
		# половину нагрузки под видом целой
		var per_row: int = int(ceil(sqrt(float(SQUADS))))
		var span_x: float = float(per_row - 1) * 10.0
		var span_z: float = float((SQUADS - 1) / per_row) * 8.0
		var base_x: float = -span_x * 0.5 + float(s % per_row) * 10.0
		var base_z: float = -span_z * 0.5 + float(s / per_row) * 8.0
		for i in range(SIZE):
			var u: Unit = Spearman.new()
			u.faction = Constants.FACTION_PLAYER
			main.world_add(u)
			u.global_position = Vector3(
				base_x + float(i % COLS) * 0.9,
				0.0,
				base_z + float(i / COLS) * 0.9)
			u.max_health = 1e9
			u.current_health = 1e9
			GameManager.add_to_squad(sid, u)
			_units.append(u)

## СМЕЩЕНИЕ ОТ ТЕКУЩЕГО ПОЛОЖЕНИЯ, а не точка на карте. Абсолютная цель годится
## только для первой фазы: к третьему замеру отряды уже стояли почти на ней, и
## «марш» превращался в 15 идущих из 810 — стенд мерил стоячую сцену под видом
## марша. Здесь каждая фаза отсчитывается от того места, где строй сейчас
## КАЖДЫЙ ОТРЯД ИДЁТ В СВОЮ ТОЧКУ, сохраняя место в общем построении. Общая
## точка на всех — грубая ошибка замера: пятнадцать отрядов сходились в один
## квадрат, 810 моделей вставали друг на друга, и стенд мерил не марш, а
## предельную плотность (цена скана рядов и чужого строя растёт с ней
## квадратично). Игрок так войска не водит
func _march_by(offset: Vector3) -> void:
	for sid in _squads:
		var members: Array = GameManager.squad_members(int(sid))
		if members.is_empty():
			continue
		var centroid := Vector3.ZERO
		for u in members:
			centroid += (u as Node3D).global_position
		centroid /= float(members.size())
		centroid.y = 0.0
		var target: Vector3 = centroid + offset
		var course: Vector3 = offset.normalized()
		var slots: Array = []
		for u in members:
			var slot: Vector3 = target + ((u as Node3D).global_position - centroid)
			slot.y = 0.0
			slots.append(slot)
			(u as Unit).command_move(slot, false, course)
		GameManager.squad_set_formation(int(sid), slots, course, false)

## Марш ровно тем же путём, каким его выдаёт ПКМ: строй переносится как есть
func _march(center: Vector3) -> void:
	for sid in _squads:
		var members: Array = GameManager.squad_members(int(sid))
		if members.is_empty():
			continue
		var centroid := Vector3.ZERO
		for u in members:
			centroid += (u as Node3D).global_position
		centroid /= float(members.size())
		centroid.y = 0.0
		var course: Vector3 = center - centroid
		course.y = 0.0
		course = course.normalized()
		var slots: Array = []
		for u in members:
			var offset: Vector3 = (u as Node3D).global_position - centroid
			offset.y = 0.0
			var slot: Vector3 = center + offset
			slots.append(slot)
			(u as Unit).command_move(slot, false, course)
		GameManager.squad_set_formation(int(sid), slots, course, false)

func _run() -> void:
	_read_args()
	get_tree().root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(3)
	await _freeze_camera()

	print("\n╔═══════════════════════════════════════════════════════════════════════╗")
	print("║  ПРОФИЛЬ МАРША: %2d отрядов × %d = %d бойцов, врагов нет              ║" % [SQUADS, SIZE, SQUADS * SIZE])
	print("╚═══════════════════════════════════════════════════════════════════════╝")

	await _measure("фон (пустая карта)")
	_spawn()
	print("  поставлено бойцов: %d" % _units.size())
	# ВСЯ АРМИЯ ОБЯЗАНА БЫТЬ В КАДРЕ. Иначе стенд меряет отсечение пирамидой
	# видимости, а не отрисовку войск (см. _visibility_note)
	_fit_camera()
	# Прогрев: первый спавн разбирает спрайтлисты
	await frames(180)

	# СНИМОК ЭКРАНА: перевод армии в общий MultiMesh меняет КАРТИНКУ, а её
	# никакими числами не проверить — только глазами (headless не рисует вовсе)
	await _shot("stand")
	# КРУПНЫЙ ПЛАН В ОБОИХ РЕЖИМАХ. Мелкий общий план не покажет, съехал ли
	# спрайт по высоте, потерялось ли зеркало и тот ли кадр показан: сравнивать
	# надо вблизи и с прежней отрисовкой узлами
	await _shot_pair("idle")
	_march_by(Vector3(6.0, 0.0, 0.0))
	await frames(45)
	await _shot_pair("walk")

	print("\n─── ФАЗА 1: СТОЯТ ───")
	await _measure("стоят")
	await _measure("стоят (повтор)")
	await _breakdown("СТОЯТ")

	# ЦЕЛЬ ДАЛЕКО, НО ВНУТРИ КАРТЫ. Близкая цель отряды успевали пройти прямо
	# посреди окна (доля идущих скакала 281..810), а цель за краем карты не
	# лучше: строй упирался в границу через clamp_to_map и вставал совсем.
	# 45 м при маршевой скорости — это больше двадцати секунд ходу, то есть
	# заведомо дольше любого окна замера, и всё это время в пределах карты
	print("\n─── ФАЗА 2: ИДУТ МАРШЕМ ───")
	_march_by(Vector3(0.0, 0.0, 45.0))
	await frames(60)
	await _measure("идут")
	await _measure("идут (повтор)")
	_march_by(Vector3(0.0, 0.0, -45.0))
	await _breakdown("ИДУТ")

	# ИГРОК ОТПРАВЛЯЕТ ВОЙСКА ВЫДЕЛЕННЫМИ. Каждое выделение вешает на бойца ЕЩЁ
	# ДВА узла — кольцо и тень (см. Unit.set_selected), то есть на 810 моделях
	# это +1620 объектов отрисовки поверх самих спрайтов. В стенде этого не было,
	# и именно поэтому он показывал 26-30 FPS там, где игрок видит 4-7
	print("\n─── ФАЗА 2b: ИДУТ И ВЫДЕЛЕНЫ (как у игрока) ───")
	for u in _units:
		if is_instance_valid(u):
			(u as Unit).set_selected(true)
	_march_by(Vector3(0.0, 0.0, 45.0))
	await _measure("идут, выделены")
	_march_by(Vector3(0.0, 0.0, -45.0))
	await _measure("идут, выделены (2)")
	for u in _units:
		if is_instance_valid(u):
			(u as Unit).set_selected(false)
	_march_by(Vector3(0.0, 0.0, 45.0))
	await _measure("идут, выделение снято")

	print("\n─── ФАЗА 3: ИДУТ, sprite_lod ВЫКЛ ───")
	_OptCfg.sprite_lod = false
	_march_by(Vector3(0.0, 0.0, 45.0))
	await _measure("идут, без LOD спрайтов")
	_OptCfg.sprite_lod = true

	print("\n─── ФАЗА 4: ИДУТ, _process у юнитов ВЫКЛ (чистая логика) ───")
	for u in _units:
		if is_instance_valid(u):
			(u as Node).set_process(false)
	_march_by(Vector3(0.0, 0.0, -45.0))
	await _measure("идут, без _process")

	print("\n=== MARCH PERF DONE ===")
	get_tree().quit()

## Раздвинуть ортокамеру так, чтобы блок отрядов помещался целиком
func _fit_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for u in _units:
		if not is_instance_valid(u):
			continue
		var p: Vector3 = (u as Node3D).global_position
		lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.z)
	if lo.x > hi.x:
		return
	# Наклон камеры сплющивает глубину — по оси Z запас больше
	var want: float = maxf((hi.x - lo.x) * 1.15, (hi.y - lo.y) * 1.7) + 8.0
	(cam as Camera3D).size = maxf(want, 24.0)
