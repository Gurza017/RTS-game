extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ПРОФИЛЬ: МАССОВЫЙ МАРШ БЕЗ БОЯ (жалоба игрока — 900+ копейщиков лагают
## именно при ВЫДЕЛЕНИИ И ОТПРАВКЕ через карту, не в бою)
## ═══════════════════════════════════════════════════════════════════════════
## qa_perf меряет БОЙ (все ищут цель, дерутся). Здесь — противоположный
## случай: 3 отряда по 300 копейщиков, ни одного врага рядом, один общий
## приказ «идти в точку через всю карту» — ровно тот сценарий из отчёта.

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

func _measure(label: String, warm: int, window: int) -> Dictionary:
	await frames(warm)
	var phys: float = await _avg(Performance.TIME_PHYSICS_PROCESS, window)
	var proc: float = await _avg(Performance.TIME_PROCESS, window)
	var total: float = (phys + proc) * 1000.0
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	print("  %-40s физика %6.2f | кадр %6.2f | сумма %6.2f мс | FPS %.0f" % [
		label, phys * 1000.0, proc * 1000.0, total, fps])
	return {"phys": phys, "proc": proc, "total": total}

const SQUADS := 3
const SQUAD_N := 300

## --utype=spearman|worker|unit — какой класс спавнить (бисекция Стадии 0:
## это ли специфика Spearman/направленных спрайтов, или это цена ЛЮБОГО Unit)
func _utype_from_args() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--utype="):
			return a.substr(8)
	return "spearman"

func _new_unit(utype: String) -> Unit:
	match utype:
		"worker": return Worker.new()
		"unit":   return Unit.new()
	return Spearman.new()

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
	await frames(3)

	var utype := _utype_from_args()
	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  ПРОФИЛЬ: МАРШ %d × %d ЮНИТОВ (%s) БЕЗ БОЯ                      ║" % [SQUADS, SQUAD_N, utype])
	print("╚══════════════════════════════════════════════════════════════════╝")

	await _measure("фон (пустая карта)", 10, 60)

	var sids: Array = []
	for s in range(SQUADS):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		sids.append(sid)
		var lane := -40.0 + float(s) * 4.0
		for i in range(SQUAD_N):
			var u: Unit = _new_unit(utype)
			u.faction = Constants.FACTION_PLAYER
			main.world_add(u)
			u.global_position = Vector3(-50.0 + float(i % 20) * 1.0, 0.0, lane + float(i / 20) * 1.0)
			GameManager.add_to_squad(sid, u)
			_units.append(u)
	print("  поставлено юнитов: %d" % _units.size())
	# ПРОГРЕВ ЩЕДРЫЙ: первые кадры после спавна ловят разбор спрайтлистов и
	# первичный расчёт позы/ракурса у каждого юнита (см. qa_perf.gd) — это
	# одноразовые издержки СОЗДАНИЯ, а не установившаяся цена простоя
	await _measure("стоят на месте (idle, должны уснуть)", 180, 60)

	# ОДИН ПРИКАЗ НА ВСЁ: имитирует выделение всех отрядов и один клик через
	# карту — ровно то действие, которое в отчёте вызывает фриз
	var t_issue := Time.get_ticks_usec()
	for u in _units:
		(u as Unit).command_move(Vector3(60.0, 0.0, 40.0), false, Vector3.FORWARD)
	var issue_ms := float(Time.get_ticks_usec() - t_issue) / 1000.0
	print("  время на РАЗДАЧУ приказа %d юнитам: %.2f мс (один вызов из потока ввода)" % [_units.size(), issue_ms])

	print("\n─── МАРШ (первые кадры сразу после приказа) ───")
	await _measure("марш, кадры 0-60",    0,  60)
	await _measure("марш, кадры 60-180",  0, 120)

	var arrived := 0
	for u in _units:
		if is_instance_valid(u) and (u as Unit).state == Unit.State.IDLE:
			arrived += 1
	print("  дошло и встало (в окне замера): %d из %d" % [arrived, _units.size()])

	print("\n=== MASS MOVE TEST DONE ===")
	get_tree().quit()
