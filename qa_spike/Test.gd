extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СПАЙК: МАССОВЫЙ МАРШ 15×60 (900 КОПЕЙЩИКОВ), ОДИН ПРИКАЗ ЧЕРЕЗ ВСЮ КАРТУ
## ═══════════════════════════════════════════════════════════════════════════
## Заказ игрока: 75 fps в простое → 4 fps на марше. Сначала МЕРЯЕМ (базовый
## fps в простое, fps на марше, разбивку physика-бюджета по веткам
## Unit.tick_physics через perf_config.profile_physics — см. qa_perf), и
## ТОЛЬКО ПОТОМ разбираемся, где узкое место. Код архитектуры (leader-only
## pathfinding, отключение физики в State.MOVING и т.п.) здесь НЕ пишем —
## это отдельное решение после анализа цифр.

const _OptCfg = preload("res://scripts/perf_config.gd")

var main = null
var _units: Array = []

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _avg(mon: int, n: int) -> float:
	var acc := 0.0
	for _i in range(n):
		await get_tree().physics_frame
		acc += Performance.get_monitor(mon)
	return acc / float(n)

func _measure(label: String, warm: int, window: int) -> Dictionary:
	await frames(warm)
	var phys: float = await _avg(Performance.TIME_PHYSICS_PROCESS, window)
	var proc: float = await _avg(Performance.TIME_PROCESS, window)
	var draws: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs: float = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var total: float = (phys + proc) * 1000.0
	print("  %-32s физика %6.2f | кадр %6.2f | сумма %6.2f мс | вызовов %5d | объектов %5d | FPS %.0f" % [
		label, phys * 1000.0, proc * 1000.0, total, int(draws), int(objs), fps])
	return {"phys": phys, "proc": proc, "total": total, "fps": fps}

func _profile_breakdown(label: String, window: int) -> void:
	_OptCfg.profile_physics = true
	_OptCfg.prof_reset()
	await frames(window)
	var rows: Array = _OptCfg.prof_report()
	_OptCfg.profile_physics = false
	print("\n  ─── РАЗБИВКА ФИЗ. ТИКА ПО ВЕТКАМ: %s (%d кадров) ───" % [label, window])
	var sum_us := 0
	for row in rows:
		sum_us += int(row[1])
	for row in rows:
		var bucket: String = String(row[0])
		var total_us: int = int(row[1])
		var calls: int = int(row[2])
		var avg_us: float = float(row[3])
		var share: float = 100.0 * float(total_us) / float(maxi(sum_us, 1))
		print("    %-18s %8.2f мс всего (%5.1f%%) | %7d вызовов | %6.2f мкс/вызов"
			% [bucket, float(total_us) / 1000.0, share, calls, avg_us])
	print("    сумма веток: %.2f мс / %d кадров = %.3f мс/кадр"
		% [float(sum_us) / 1000.0, window, float(sum_us) / 1000.0 / float(window)])

const SQUADS := 15
const SQUAD_N := 60

func _run() -> void:
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
	GameManager.world_bounds_enabled = false
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  СПАЙК: %d ОТРЯДОВ × %d = %d КОПЕЙЩИКОВ, МАРШ ЧЕРЕЗ КАРТУ         ║" % [SQUADS, SQUAD_N, SQUADS * SQUAD_N])
	print("╚══════════════════════════════════════════════════════════════════╝")

	await _measure("фон (пустая карта)", 10, 60)

	# Диагональные "коробки" отрядов, как на скриншоте игрока — 12×5 в отряде
	var cols := 12
	var sid_list: Array = []
	for s in range(SQUADS):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		sid_list.append(sid)
		var lane := float(s / 3) * 8.0
		var col_off := float(s % 3) * 14.0
		for i in range(SQUAD_N):
			var u: Unit = Spearman.new()
			u.faction = Constants.FACTION_PLAYER
			main.world_add(u)
			u.global_position = Vector3(
				-70.0 + col_off + float(i % cols) * 1.0,
				0.0,
				-40.0 + lane + float(i / cols) * 1.0)
			GameManager.add_to_squad(sid, u)
			_units.append(u)
	print("  поставлено юнитов: %d" % _units.size())

	# ПРОГРЕВ ЩЕДРЫЙ: первые кадры после спавна ловят разбор спрайтлистов
	await _measure("стоят на месте (idle, должны уснуть)", 180, 60)
	await _profile_breakdown("IDLE", 120)

	# ОДИН ПРИКАЗ НА ВСЁ: имитирует выделение всех 15 отрядов и один клик
	# через карту — ровно сценарий из отчёта
	var t_issue := Time.get_ticks_usec()
	for u in _units:
		(u as Unit).command_move(Vector3(90.0, 0.0, 60.0), false, Vector3.FORWARD)
	var issue_ms := float(Time.get_ticks_usec() - t_issue) / 1000.0
	print("  время на РАЗДАЧУ приказа %d юнитам: %.2f мс" % [_units.size(), issue_ms])

	print("\n─── МАРШ ───")
	await _measure("марш, кадры 0-60",    0,  60)
	var march := await _measure("марш, кадры 60-180", 0, 120)
	await _profile_breakdown("МАРШ", 180)

	var arrived := 0
	for u in _units:
		if is_instance_valid(u) and (u as Unit).state == Unit.State.IDLE:
			arrived += 1
	print("\n  дошло и встало (в окне замера): %d из %d" % [arrived, _units.size()])
	print("  ВЕРДИКТ: марш держит %.0f fps (цель — 60)" % (march.get("fps", 0.0) as float))

	print("\n=== SPIKE TEST DONE ===")
	get_tree().quit()
