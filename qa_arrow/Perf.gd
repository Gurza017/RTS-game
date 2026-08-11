extends Node

## Нагрузочный замер: бой двух линий + обстрел лучниками.
## Смотрим время физики/процесса и число живых узлов (утечки).

const N_PER_SIDE := 300

var main: Node = null
var _t := 0
var _samples: Array[float] = []
var _proc_samples: Array[float] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var base_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("узлов после генерации карты: %d" % base_nodes)

	# Режим: "melee" — две враждебные линии сходятся; "march" — все свои,
	# просто марш. Разница показывает цену боевой логики отдельно от базовой
	var mode := "melee"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mode="):
			mode = a.substr(5)
	print("режим: %s" % mode)

	var Spear := load("res://scenes/units/Spearman.tscn") as PackedScene
	var Arch  := load("res://scenes/units/Archer.tscn") as PackedScene
	for i in range(N_PER_SIDE):
		var factions: Array = [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]
		if mode == "march":
			factions = [Constants.FACTION_PLAYER, Constants.FACTION_PLAYER]
		for f in factions:
			var scene: PackedScene = Arch if (i % 4 == 0) else Spear
			var u: Unit = scene.instantiate()
			u.faction = f
			main.add_child(u)
			var side: float = -6.0 if (mode == "melee" and f == Constants.FACTION_PLAYER) else 6.0
			if mode == "march":
				side = -6.0 if (i % 2 == 0) else 6.0
			u.global_position = Vector3(
				side + float(i % 10) * 0.4 * signf(side),
				0.0,
				-12.0 + float(i / 10) * 0.5)
	await get_tree().process_frame
	print("заспавнено %d юнитов, узлов: %d"
		% [N_PER_SIDE * 2, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])

	# Сводим линии в бой
	for u in get_tree().get_nodes_in_group("player_units"):
		u.command_move(Vector3(2.0, 0, u.global_position.z))
	for u in get_tree().get_nodes_in_group("enemy_units"):
		u.command_move(Vector3(-2.0, 0, u.global_position.z))

	var peak_nodes := 0
	# Пары (кадр, мс) — чтобы понять, КОГДА случались спайки, а не только их размер
	var worst: Array = []
	for frame in range(900):
		await get_tree().process_frame
		# Прогрев 200 кадров: показатель TIME_PHYSICS_PROCESS ещё десятки кадров
		# отдаёт залипшее значение тяжёлого кадра спавна (~340 мс), и оно портит p95
		if frame > 200:
			var ph: float = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
			_samples.append(ph)
			worst.append([frame, ph])
			_proc_samples.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		if frame % 300 == 0:
			print("  кадр %4d: юнитов=%d, узлов=%d, физика=%.2f мс, процесс=%.2f мс"
				% [frame,
				   get_tree().get_nodes_in_group("all_units").size(),
				   int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				   float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
				   float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0])

	_samples.sort()
	_proc_samples.sort()
	var med: float = _samples[_samples.size() / 2]
	var p95: float = _samples[int(float(_samples.size()) * 0.95)]
	var pmed: float = _proc_samples[_proc_samples.size() / 2]
	var p99: float = _samples[int(float(_samples.size()) * 0.99)]
	print("\nфизика: медиана %.2f мс, p95 %.2f мс, p99 %.2f мс   | _process: медиана %.2f мс"
		% [med, p95, p99, pmed])
	print("бюджет кадра 60 FPS = 16.67 мс, замеров=%d" % _samples.size())
	# Сколько замеров выше бюджета и где именно они были по времени
	var over := 0
	var over_frames: Array = []
	for pair in worst:
		var v: float = float(pair[1])
		if v > 16.67:
			over += 1
			if over_frames.size() < 12:
				over_frames.append("к%d:%.0f" % [int(pair[0]), v])
	print("замеров выше 16.67 мс: %d из %d, первые из них: %s"
		% [over, _samples.size(), str(over_frames)])
	worst.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var top: Array = []
	for i in range(mini(5, worst.size())):
		var pair: Array = worst[i]
		top.append("кадр %d = %.1f мс" % [int(pair[0]), float(pair[1])])
	print("худшие 5 замеров: %s" % str(top))

	# Утечки: ждём, пока трупы и стрелы уберутся
	for _i in range(240):
		await get_tree().process_frame
	print("\nживых юнитов в конце: %d" % get_tree().get_nodes_in_group("all_units").size())
	print("узлов: пик=%d, сейчас=%d, было до боя=%d"
		% [peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), base_nodes])
	print("orphan-узлов (утечка вне дерева): %d"
		% int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
	var arrows := 0
	for n in main.get_children():
		if n is Arrow:
			arrows += 1
	print("стрел на карте: %d (живут по 20 сек, потом queue_free)" % arrows)
	print("\n=== PERF DONE ===")
	get_tree().quit()
