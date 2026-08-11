extends Node

## QA п.1.1 / 1.2 — производительность и утечки, расширенная статистика.
## Отличие от qa_arrow/Perf.tscn: считается полное распределение, отдельно
## учитывается, что Performance.TIME_* обновляется РАЗ В СЕКУНДУ и содержит
## МАКСИМУМ кадра за эту секунду (см. Main::iteration в движке), поэтому
## наивный p95 по покадровым выборкам врёт.

const N_PER_SIDE := 300

var main: Node = null

func _ready() -> void:
	call_deferred("_run")

func _mode() -> String:
	for a in OS.get_cmdline_user_args():
		var s: String = a
		if s.begins_with("mode="):
			return s.substr(5)
	return "melee"

func _pct(arr: Array[float], q: float) -> float:
	if arr.is_empty():
		return 0.0
	var i: int = clampi(int(float(arr.size() - 1) * q), 0, arr.size() - 1)
	return arr[i]

func _stats(tag: String, arr: Array[float]) -> void:
	if arr.is_empty():
		print("  %s: нет выборок" % tag)
		return
	var a: Array[float] = arr.duplicate()
	a.sort()
	print("  %-22s N=%4d  min=%6.2f  p50=%6.2f  p75=%6.2f  p90=%6.2f  p95=%6.2f  p99=%6.2f  max=%7.2f"
		% [tag, a.size(), a[0], _pct(a, 0.50), _pct(a, 0.75), _pct(a, 0.90),
		   _pct(a, 0.95), _pct(a, 0.99), a[a.size() - 1]])

func _arrows() -> int:
	var n := 0
	for c in main.get_children():
		if c is Arrow:
			n += 1
	for c in main.get_node("World").get_children():
		if c is Arrow:
			n += 1
	return n

func _run() -> void:
	print("Engine.max_fps=%d  physics_ticks_per_second=%d  headless=%s"
		% [Engine.max_fps, Engine.physics_ticks_per_second, str(DisplayServer.get_name() == "headless")])
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(3):
		await get_tree().process_frame

	# Даём карте отстояться: рабочих ещё нет, здания уснули
	for _i in range(120):
		await get_tree().process_frame
	var base_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var base_orph  := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var mode := _mode()
	print("режим: %s | узлов до боя: %d | orphan до боя: %d" % [mode, base_nodes, base_orph])

	# ── СПАВН ────────────────────────────────────────────────────────────────
	var Spear := load("res://scenes/units/Spearman.tscn") as PackedScene
	var Arch  := load("res://scenes/units/Archer.tscn") as PackedScene
	var spawned: Array = []
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
			spawned.append(u)
	await get_tree().process_frame
	var spawn_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("заспавнено %d юнитов, узлов: %d (на юнита ~%.1f)"
		% [N_PER_SIDE * 2, spawn_nodes, float(spawn_nodes - base_nodes) / float(N_PER_SIDE * 2)])

	for u in get_tree().get_nodes_in_group("player_units"):
		u.command_move(Vector3(2.0, 0, u.global_position.z))
	for u in get_tree().get_nodes_in_group("enemy_units"):
		u.command_move(Vector3(-2.0, 0, u.global_position.z))

	# ── ЗАМЕР ────────────────────────────────────────────────────────────────
	var phys_raw: Array[float] = []
	var proc_raw: Array[float] = []
	var phys_uni: Array[float] = []   # только НОВЫЕ значения (раз в секунду)
	var proc_uni: Array[float] = []
	var last_p := -1.0
	var last_q := -1.0
	var peak_nodes := 0
	var t_start := Time.get_ticks_usec()
	var frames := 0
	for frame in range(900):
		await get_tree().process_frame
		frames += 1
		var p: float = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		var q: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		if frame > 60:
			phys_raw.append(p)
			proc_raw.append(q)
			if p != last_p:
				phys_uni.append(p)
				last_p = p
			if q != last_q:
				proc_uni.append(q)
				last_q = q
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		if frame % 300 == 0:
			print("  кадр %4d: юнитов=%d, узлов=%d, стрел=%d, TIME_FPS=%d"
				% [frame, get_tree().get_nodes_in_group("all_units").size(),
				   int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), _arrows(),
				   int(Performance.get_monitor(Performance.TIME_FPS))])
	var elapsed_ms := float(Time.get_ticks_usec() - t_start) / 1000.0

	print("\n--- РАСПРЕДЕЛЕНИЯ, мс ---")
	print("  ВНИМАНИЕ: Performance.TIME_PHYSICS_PROCESS/TIME_PROCESS движок обновляет")
	print("  РАЗ В СЕКУНДУ и кладёт туда МАКСИМУМ кадра за эту секунду. Покадровая")
	print("  выборка = одно и то же число, повторённое ~fps раз -> её p95 бессмысленен.")
	_stats("physics (покадрово)", phys_raw)
	_stats("process (покадрово)", proc_raw)
	_stats("physics (пик/сек)",   phys_uni)
	_stats("process (пик/сек)",   proc_uni)
	print("  реальный средний кадр по стенным часам: %.2f мс (%.1f FPS), кадров %d за %.1f с"
		% [elapsed_ms / float(frames), 1000.0 / (elapsed_ms / float(frames)), frames, elapsed_ms / 1000.0])
	print("  бюджет кадра 60 FPS = 16.67 мс")

	# ── УТЕЧКИ ───────────────────────────────────────────────────────────────
	print("\n--- УТЕЧКИ ---")
	# 1. Ждём, пока бой утихнет (число юнитов перестало меняться)
	var prev := -1
	var stable := 0
	var w := 0
	while w < 4000 and stable < 180:
		await get_tree().process_frame
		w += 1
		var cur := get_tree().get_nodes_in_group("all_units").size()
		if cur == prev:
			stable += 1
		else:
			stable = 0
			prev = cur
	print("  бой затих за %d кадров, живых юнитов: %d" % [w, prev])
	print("  узлов: пик=%d, сейчас=%d (до боя %d), стрел на карте: %d"
		% [peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), base_nodes, _arrows()])
	print("  orphan-узлов: %d (было до боя %d)"
		% [int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), base_orph])

	# 2. Ждём > STUCK_LIFETIME (20 c) после последнего выстрела
	var last_arrow_ms := Time.get_ticks_msec()
	var arrows_peak := _arrows()
	while Time.get_ticks_msec() - last_arrow_ms < 26000:
		await get_tree().process_frame
		if _arrows() > 0:
			last_arrow_ms = Time.get_ticks_msec()
			arrows_peak = maxi(arrows_peak, _arrows())
	print("  спустя >26 с после последней стрелы: стрел на карте = %d (пик был %d) -> %s"
		% [_arrows(), arrows_peak, "OK" if _arrows() == 0 else "УТЕЧКА"])

	# 3. Убираем всех выживших — узлы обязаны вернуться к досражённому уровню
	var alive := 0
	for u in spawned:
		if is_instance_valid(u):
			alive += 1
			u.queue_free()
	for _i in range(120):
		await get_tree().process_frame
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orph  := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("  снято выживших: %d" % alive)
	print("  узлов после полной зачистки: %d, было до боя: %d, разница: %+d"
		% [after, base_nodes, after - base_nodes])
	print("  orphan-узлов в конце: %d (ждём 0)" % orph)
	print("  ВЕРДИКТ утечек: %s" % ("PASS" if orph == 0 and absi(after - base_nodes) <= 5 else "СМОТРИ ЦИФРЫ"))

	print("\n=== PERFSTATS DONE (%s) ===" % mode)
	get_tree().quit()
