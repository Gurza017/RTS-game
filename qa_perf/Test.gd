extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ПРОФИЛЬ КАДРА: 15 ОТРЯДОВ В БОЮ
## ═══════════════════════════════════════════════════════════════════════════
## Сначала МЕРЯЕМ, потом режем. Стенд ставит боевую нагрузку из задания
## (15 отрядов, ~300 моделей) и снимает цену кадра, поочерёдно отключая
## подсистемы. Разница между замерами и есть цена подсистемы.
##
## ПРОГРЕВ ОБЯЗАТЕЛЕН: первое окно после спавна ловит разбор спрайтлистов
## (для 300 копейщиков это ~250 мс на кадр) и завышает всё в сто раз.

const _OptCfg = preload("res://scripts/perf_config.gd")

var main = null
var _units: Array = []
var _log: Array = []

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

## Одно измерение: прогрев вхолостую, затем зачётное окно
func _measure(label: String) -> Dictionary:
	var _warm_p: float = await _avg(Performance.TIME_PHYSICS_PROCESS, 60)
	await frames(20)
	var phys: float = await _avg(Performance.TIME_PHYSICS_PROCESS, 120)
	var proc: float = await _avg(Performance.TIME_PROCESS, 120)
	var alive := 0
	for u in _units:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			alive += 1
	var total: float = (phys + proc) * 1000.0
	# РЕНДЕР МЕРЯЕМ ОТДЕЛЬНО: headless его не выполняет вовсе, и логика там
	# выглядит бодро при том, что в окне игра стоит. Вызовы отрисовки — главный
	# подозреваемый: каждый боец, дерево и куст здесь отдельный MeshInstance3D
	var draws: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs: float = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	print("  %-34s физика %6.2f | кадр %6.2f | сумма %6.2f мс | вызовов %5d | объектов %5d | FPS %.0f | живых %d" % [
		label, phys * 1000.0, proc * 1000.0, total, int(draws), int(objs), fps, alive])
	_log.append([label, total])
	return {"phys": phys, "proc": proc, "total": total}

## РАЗБИВКА physика-БЮДЖЕТА ПО ВЕТКАМ Unit.tick_physics (см. perf_config.
## profile_physics). Общее число "физика NN мс" из _measure() не говорит, ГДЕ
## внутри тика деньги — этот блок это показывает
func _profile_breakdown() -> void:
	_OptCfg.profile_physics = true
	_OptCfg.prof_reset()
	await frames(120)
	var rows: Array = _OptCfg.prof_report()
	_OptCfg.profile_physics = false
	print("\n─── РАЗБИВКА ФИЗ. ТИКА ПО ВЕТКАМ (120 кадров) ───")
	var sum_us := 0
	for row in rows:
		sum_us += int(row[1])
	for row in rows:
		var bucket: String = String(row[0])
		var total_us: int = int(row[1])
		var calls: int = int(row[2])
		var avg_us: float = float(row[3])
		var share: float = 100.0 * float(total_us) / float(maxi(sum_us, 1))
		print("  %-18s %8.2f мс всего (%5.1f%%) | %7d вызовов | %6.2f мкс/вызов"
			% [bucket, float(total_us) / 1000.0, share, calls, avg_us])
	print("  сумма веток: %.2f мс за 120 кадров (%.3f мс/кадр)"
		% [float(sum_us) / 1000.0, float(sum_us) / 1000.0 / 120.0])

## РЕАЛЬНЫЙ СОСТАВ БОЯ ИЗ ОТЧЁТА ИГРОКА. Считать «отряды» без учёта их размера
## нельзя: отряд копейщиков это 50 моделей, лучников 25, мечников 20. Десять
## отрядов пикинеров — это 500 бойцов, а не 200
const ROSTER := [
	# [фракция, тип, отрядов, размер отряда]
	[Constants.FACTION_PLAYER, "spearman", 10, 50],
	[Constants.FACTION_PLAYER, "archer",   10, 25],
	[Constants.FACTION_PLAYER, "warrior",   5, 20],
	[Constants.FACTION_ENEMY,  "spearman",  3, 50],
	[Constants.FACTION_ENEMY,  "archer",    2, 25],
	[Constants.FACTION_ENEMY,  "warrior",   2, 20],
]
## Рабочие обеих сторон: тоже юниты, тоже тикают каждый кадр
const WORKERS_PLAYER := 40
const WORKERS_ENEMY  := 20

func _new_unit(kind: String) -> Unit:
	match kind:
		"spearman": return Spearman.new()
		"archer":   return Archer.new()
		"warrior":  return Warrior.new()
	return Worker.new()

## Бессмертный бой: юниты не гибнут, нагрузка не тает по ходу замера
func _make_battle() -> int:
	var lane_p := -26.0
	var lane_e := -26.0
	for entry in ROSTER:
		var e: Array = entry
		var fac: int = int(e[0])
		var kind: String = String(e[1])
		var count: int = int(e[2])
		var size: int = int(e[3])
		for s in range(count):
			var sid: int = GameManager.new_squad(fac, kind)
			var side: float = -14.0 if fac == Constants.FACTION_PLAYER else 14.0
			var lane: float = lane_p if fac == Constants.FACTION_PLAYER else lane_e
			if fac == Constants.FACTION_PLAYER:
				lane_p += 5.0
			else:
				lane_e += 5.0
			for i in range(size):
				var u: Unit = _new_unit(kind)
				u.faction = fac
				main.world_add(u)
				u.global_position = Vector3(
					side + float(i % 10) * 0.9 * signf(side),
					0.0, lane + float(i / 10) * 0.9)
				u.max_health = 1e9
				u.current_health = 1e9
				GameManager.add_to_squad(sid, u)
				_units.append(u)
	# Рабочие: стоят своим лагерем в стороне и не воюют
	for w in range(WORKERS_PLAYER + WORKERS_ENEMY):
		var fac2: int = Constants.FACTION_PLAYER if w < WORKERS_PLAYER else Constants.FACTION_ENEMY
		var u2: Unit = Worker.new()
		u2.faction = fac2
		main.world_add(u2)
		u2.global_position = Vector3(-60.0 + float(w % 10) * 1.2, 0.0,
			-50.0 + float(w / 10) * 1.2)
		_units.append(u2)
	return _units.size()

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	# ВЕРТИКАЛЬНУЮ СИНХРОНИЗАЦИЮ СНИМАЕМ. С ней кадр всегда ровно 13.3 мс (75 Гц),
	# и TIME_PROCESS показывает не работу, а ожидание развёртки: пустая карта и
	# бой на 300 моделей давали одинаковые 13.3 мс. Без vsync видно настоящую цену
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	# Убираем ИИ и стартовых рабочих: меряем ровно заказанную нагрузку
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════════════╗")
	print("║  ПРОФИЛЬ: РЕАЛЬНЫЙ СОСТАВ БОЯ ИЗ ОТЧЁТА ИГРОКА                           ║")
	print("╚══════════════════════════════════════════════════════════════════════════╝")

	var idle: Dictionary = await _measure("фон (пустая карта)")
	var total_units: int = _make_battle()
	print("  поставлено юнитов: %d" % total_units)
	await frames(90)
	# Сводим строи: каждый ищет ближайшего врага сам
	for u in _units:
		(u as Unit).command_attack(null, false)
	await frames(120)

	print("\n─── ВСЁ ВКЛЮЧЕНО ───")
	var full: Dictionary = await _measure("все оптимизации ВКЛ")
	await _profile_breakdown()

	print("\n─── ПООЧЕРЁДНОЕ ОТКЛЮЧЕНИЕ (разница = цена подсистемы) ───")
	_OptCfg.squad_target_cache = false
	var no_cache: Dictionary = await _measure("без общего поиска цели")
	_OptCfg.squad_target_cache = true

	# ЗАМЕРА РАСТАЛКИВАНИЯ БОЛЬШЕ НЕТ. Подсистему не «оптимизировали флагом», а
	# удалили целиком: союзники не толкают друг друга вовсе (см. шапку Unit.gd).
	# Её цена теперь равна нулю по построению, мерить нечего

	_OptCfg.sprite_lod = false
	var no_lod: Dictionary = await _measure("без отсечения дальних спрайтов")
	_OptCfg.sprite_lod = true

	var after: Dictionary = await _measure("контроль: снова всё ВКЛ")

	print("\n─── ИТОГ ───")
	print("  фон карты:                    %6.2f мс" % (idle["total"] as float))
	print("  %d моделей, оптимизации ВКЛ: %6.2f мс  (~%.0f fps)" % [
		total_units, full["total"] as float, 1000.0 / maxf(full["total"] as float, 0.01)])
	print("  контрольный повтор:           %6.2f мс" % (after["total"] as float))
	var base_ms: float = ((full["total"] as float) + (after["total"] as float)) * 0.5
	print("  цена общего поиска цели:      %+6.2f мс" % ((no_cache["total"] as float) - base_ms))
	print("  цена дальних спрайтов:        %+6.2f мс" % ((no_lod["total"] as float) - base_ms))
	print("\n  ВЕРДИКТ: %s" % ("60+ fps держится" if base_ms < 16.6 else "бюджет кадра превышен"))
	print("\n=== PERF TEST DONE ===")
	get_tree().quit()
