extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД «30 ОТРЯДОВ НА 30 ОТРЯДОВ»
## ═══════════════════════════════════════════════════════════════════════════
## Цель задания: стабильные 60 FPS в сражении 30×30 отрядов (600+ моделей
## на карте с пассивной коллизией и ИИ). Стенд ставит ровно такую нагрузку
## и снимает цену кадра БЕЗ vsync — иначе TIME_PROCESS показывает ожидание
## развёртки, а не работу.
##
## Замер идёт в ДВУХ режимах:
##   • «строи стоят» — отряды на позициях, авто-агро молчит (марш/ожидание);
##   • «свалка» — все дерутся, бессмертные (нагрузка не тает по ходу замера).
##
## ЗАПУСК:
##   godot --headless --path . res://qa_30x30/Test.tscn
## Ключ --headless честен для ЛОГИКИ (физика и скрипты считаются полностью),
## но не выполняет отрисовку: колонка «вызовов» в headless всегда 0.

const _OptCfg = preload("res://scripts/perf_config.gd")

## 30 отрядов на сторону. Состав отражает боевой ростер игры: копейщики —
## костяк, лучники — поддержка, мечники — ударный кулак
const SQUADS_PER_SIDE := 30
const SQUAD_MIX := ["spearman", "spearman", "archer", "warrior"]
## Моделей в отряде стенда. 20 × 30 × 2 = 1200 юнитов на карте
const SQUAD_MODELS := 20

var main = null
var _units: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _avg(mon: int, n: int) -> float:
	var acc := 0.0
	for _i in range(n):
		await get_tree().process_frame
		acc += Performance.get_monitor(mon)
	return acc / float(n)

## ЧЕСТНЫЙ ЗАМЕР: СЧИТАЕМ КАДРЫ ПО ЧАСАМ.
##
## Мониторы Performance.TIME_PHYSICS_PROCESS / TIME_PROCESS для этой задачи
## непригодны: они дают время ОДНОГО шага соответствующего цикла, а при
## отключённой вертикальной синхронизации кадров рисуется больше, чем шагов
## физики (или меньше). Сумма двух мониторов расходилась с наблюдаемым FPS в
## разы — на одном и том же прогоне «32 мс» соседствовали со «139 FPS».
##
## Здесь меряется ровно то, что видит игрок: сколько кадров прошло за
## измеренный отрезок стенных часов. Ошибиться в этом нельзя.
const WARMUP_SEC  := 1.5
const MEASURE_SEC := 4.0

func _measure(label: String) -> float:
	# Прогрев: первые кадры после спавна ловят разбор спрайт-листов
	var warm_end: int = Time.get_ticks_msec() + int(WARMUP_SEC * 1000.0)
	while Time.get_ticks_msec() < warm_end:
		await get_tree().process_frame
	var t0: int = Time.get_ticks_msec()
	var end: int = t0 + int(MEASURE_SEC * 1000.0)
	var count := 0
	var draws := 0
	var objs := 0
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		count += 1
		draws += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objs  += int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var elapsed: float = float(Time.get_ticks_msec() - t0) * 0.001
	var fps: float = float(count) / maxf(elapsed, 0.001)
	var ms: float  = 1000.0 / maxf(fps, 0.001)
	var alive := 0
	for u in _units:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			alive += 1
	print("  %-24s %6.2f мс/кадр | %5.1f FPS | вызовов %5d | объектов %5d | живых %d" % [
		label, ms, fps, draws / maxi(count, 1), objs / maxi(count, 1), alive])
	return ms

func _new_unit(kind: String) -> Unit:
	match kind:
		"spearman": return Spearman.new()
		"archer":   return Archer.new()
		"warrior":  return Warrior.new()
	return Worker.new()

func _make_battle() -> int:
	for side_i in range(2):
		var fac: int = Constants.FACTION_PLAYER if side_i == 0 else Constants.FACTION_ENEMY
		var side: float = -1.0 if side_i == 0 else 1.0
		for s in range(SQUADS_PER_SIDE):
			var kind: String = SQUAD_MIX[s % SQUAD_MIX.size()]
			var sid: int = GameManager.new_squad(fac, kind)
			# Отряды стоят фронтом друг к другу: 6 рядов по 5 колонн,
			# отряды разведены по фронту на 5 м
			# Фронт шириной ~90 м: при максимальном отдалении камеры (110 м
			# видимой высоты) вся свалка попадает в кадр — именно так игрок и
			# смотрит на большое сражение, и именно так считаются вызовы отрисовки
			var lane: float = -45.0 + float(s) * 3.1
			for i in range(SQUAD_MODELS):
				var u: Unit = _new_unit(kind)
				u.faction = fac
				main.world_add(u)
				u.global_position = Vector3(
					side * (12.0 + float(i % 5) * 0.9),
					0.0, lane + float(i / 5) * 0.9)
				u.max_health     = 1e9
				u.current_health = 1e9
				GameManager.add_to_squad(sid, u)
				_units.append(u)
	return _units.size()

func _run() -> void:
	# ЗЕРНО ГЕНЕРАТОРА ФИКСИРОВАНО. Лес, кусты и жилы ресурсов расставляются
	# случайно, а это сотни отдельных мешей — от запуска к запуску число
	# вызовов отрисовки гуляло на треть, и сравнивать замеры было невозможно
	seed(20260801)
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

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  30 ОТРЯДОВ ПРОТИВ 30 ОТРЯДОВ                                    ║")
	print("╚══════════════════════════════════════════════════════════════════╝")
	# КАМЕРА НА МАКСИМАЛЬНОМ ОТДАЛЕНИИ НАД ЦЕНТРОМ БОЯ: так на неё разом
	# приходится вся свалка, и стенд меряет худший, а не удобный случай
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.has_method("pan_to"):
		cam.pan_to(Vector3.ZERO)
		cam.set("_target_height", cam.get("max_height"))
		cam.set("_height", cam.get("max_height"))
		cam.call("_update_position")
		# КАМЕРУ ГЛУШИМ. Её _process гонит скролл краем экрана по фактическому
		# положению курсора мыши — а он в автоматическом прогоне где угодно.
		# Из-за этого камера уезжала с поля боя посреди замера, юниты выпадали
		# из отсечения, и один и тот же стенд давал то 64, то 154 FPS
		cam.set_process(false)
		# Точку обзора для LOD обновляет тот же _process — ставим её вручную
		GameManager.update_view_point(Vector3.ZERO)
	var idle: float = await _measure("фон (пустая карта)")
	var total_units: int = _make_battle()
	print("  поставлено юнитов: %d (по %d отрядов на сторону)" % [
		total_units, SQUADS_PER_SIDE])
	await frames(120)

	print("\n─── РЕЖИМ 1: СТРОИ СТОЯТ (ожидание/марш) ───")
	var standing: float = await _measure("30x30 стоят")

	print("\n─── РЕЖИМ 2: ОБЩАЯ СВАЛКА ───")
	for u in _units:
		(u as Unit).command_attack(null, false)
	await frames(180)
	var melee: float = await _measure("30x30 дерутся")

	# ─── РАЗБОР: СКОЛЬКО СТОИТ ОТРИСОВКА, А СКОЛЬКО СКРИПТЫ ──────────────────
	# Прячем сами узлы бойцов: логика (_process/_physics_process) продолжает
	# работать полностью, рендер про них забывает. Разница двух замеров и есть
	# цена отрисовки — по ней видно, куда вкладываться дальше
	print("\n─── РАЗБОР НАГРУЗКИ ───")
	for u in _units:
		(u as Node3D).visible = false
	var logic_only: float = await _measure("только логика")
	for u in _units:
		(u as Node3D).visible = true

	print("\n─── ИТОГ ───")
	print("  из них логика:        %6.2f мс/кадр, отрисовка: %6.2f мс/кадр" % [
		logic_only - idle, melee - logic_only])
	print("  фон карты:            %6.2f мс/кадр (%.0f FPS)" % [idle, 1000.0 / maxf(idle, 0.01)])
	print("  %4d моделей, стоят:  %6.2f мс/кадр (%.0f FPS)" % [
		total_units, standing, 1000.0 / maxf(standing, 0.01)])
	print("  %4d моделей, свалка: %6.2f мс/кадр (%.0f FPS)" % [
		total_units, melee, 1000.0 / maxf(melee, 0.01)])
	var worst: float = maxf(standing, melee)
	print("\n  ВЕРДИКТ: %s (бюджет кадра 60 fps = 16.6 мс)" % (
		"60 FPS ДЕРЖИТСЯ" if worst < 16.6 else "БЮДЖЕТ ПРЕВЫШЕН"))
	print("\n=== 30x30 TEST DONE ===")
	get_tree().quit()
