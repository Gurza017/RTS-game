extends Node

## БЛОК 3 — ЗАПАС ЗОЛОТА И КАМНЯ ×3 (пункты 3.1 … 3.3)

var main: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_t31_stats()
	await _t32_spread()
	await _t33_practice()
	print("\n=== T3 DONE ===")
	get_tree().quit()

func _label(t: int) -> String:
	match t:
		Constants.RESOURCE_GOLD:  return "золото"
		Constants.RESOURCE_STONE: return "камень"
		Constants.RESOURCE_WOOD:  return "дерево"
		Constants.RESOURCE_FOOD:  return "еда"
		_: return "вода"

func _collect() -> Dictionary:
	var by: Dictionary = {}
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null:
			continue
		var t: int = rn.resource_type
		if not by.has(t):
			by[t] = {"n": 0, "sum": 0.0, "min": INF, "max": 0.0}
		var d: Dictionary = by[t]
		d["n"] = int(d["n"]) + 1
		d["sum"] = float(d["sum"]) + rn.remaining
		d["min"] = minf(float(d["min"]), rn.remaining)
		d["max"] = maxf(float(d["max"]), rn.remaining)
	return by

# ── 3.1 ─────────────────────────────────────────────────────────────────────
func _t31_stats() -> void:
	print("\n══════ 3.1 ЗАПАС ПО ТИПАМ РЕСУРСА ══════")
	var MainS = load("res://scripts/Main.gd")
	var pc: Dictionary = MainS.PIECE_CLASSES
	print("  PIECE_CLASSES (только руда):")
	for k in ["big", "mid", "small"]:
		var d: Dictionary = pc[k]
		var am: float = float(d["amount"])
		var j: float = float(d["jitter"])
		print("    %-5s amount=%7.1f jitter=%.2f → фактический диапазон %.1f … %.1f"
			% [k, am, j, am * (1.0 - j), am * (1.0 + j)])
	print("    дерево (_spawn_tree_cluster): фиксированный диапазон 480 … 720")
	var by := _collect()
	print("   тип     | узлов |   всего    |   мин   |   макс  |  средний")
	for t in [Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_WOOD,
			  Constants.RESOURCE_FOOD, Constants.RESOURCE_WATER]:
		if not by.has(t):
			continue
		var d: Dictionary = by[t]
		print("  %-8s |  %4d | %10.0f | %7.1f | %7.1f | %8.1f"
			% [_label(t), int(d["n"]), float(d["sum"]), float(d["min"]),
			   float(d["max"]), float(d["sum"]) / float(d["n"])])
	var ok := true
	for t in [Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE]:
		if not by.has(t):
			continue
		var d: Dictionary = by[t]
		if float(d["min"]) < 390.0 * 0.74 - 0.5 or float(d["max"]) > 1260.0 * 1.22 + 0.5:
			ok = false
	if by.has(Constants.RESOURCE_WOOD):
		var w: Dictionary = by[Constants.RESOURCE_WOOD]
		if float(w["min"]) < 479.9 or float(w["max"]) > 720.1:
			ok = false
	print("  руда: ожидаемые границы 288.6 (small×0.74) … 1537.2 (big×1.22)")
	print("  дерево: ожидаемые границы 480.0 … 720.0 (НЕ менялось)")
	print("  ИТОГ 3.1: %s" % ["PASS" if ok else "FAIL"])

# ── 3.2 ─────────────────────────────────────────────────────────────────────
func _t32_spread() -> void:
	print("\n══════ 3.2 РАЗБРОС ПО 5 ГЕНЕРАЦИЯМ ══════")
	print("   № |  золото узлов/сумма  |  камень узлов/сумма  |  дерево узлов/сумма")
	var golds: Array[float] = []
	var stones: Array[float] = []
	# первая генерация — уже загруженная карта
	var runs: Array = [_collect()]
	for i in range(4):
		var m2: Node = load("res://scenes/Main.tscn").instantiate()
		get_tree().root.add_child(m2)
		await get_tree().process_frame
		await get_tree().process_frame
		# считаем ТОЛЬКО узлы новой карты
		var by: Dictionary = {}
		for n in get_tree().get_nodes_in_group("resource_nodes"):
			var rn := n as ResourceNode
			if rn == null or not m2.is_ancestor_of(rn):
				continue
			var t: int = rn.resource_type
			if not by.has(t):
				by[t] = {"n": 0, "sum": 0.0, "min": INF, "max": 0.0}
			var d: Dictionary = by[t]
			d["n"] = int(d["n"]) + 1
			d["sum"] = float(d["sum"]) + rn.remaining
			d["min"] = minf(float(d["min"]), rn.remaining)
			d["max"] = maxf(float(d["max"]), rn.remaining)
		runs.append(by)
		m2.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	for i in range(runs.size()):
		var by: Dictionary = runs[i]
		var g: Dictionary = by.get(Constants.RESOURCE_GOLD, {"n": 0, "sum": 0.0})
		var s: Dictionary = by.get(Constants.RESOURCE_STONE, {"n": 0, "sum": 0.0})
		var w: Dictionary = by.get(Constants.RESOURCE_WOOD, {"n": 0, "sum": 0.0})
		golds.append(float(g["sum"]))
		stones.append(float(s["sum"]))
		print("   %d  |  %4d / %9.0f   |  %4d / %9.0f   |  %4d / %9.0f"
			% [i + 1, int(g["n"]), float(g["sum"]), int(s["n"]), float(s["sum"]),
			   int(w["n"]), float(w["sum"])])
	_spread("золото", golds)
	_spread("камень", stones)

func _spread(name: String, arr: Array[float]) -> void:
	var mn := INF
	var mx := 0.0
	var s := 0.0
	for v in arr:
		mn = minf(mn, v); mx = maxf(mx, v); s += v
	var avg: float = s / float(arr.size())
	print("  %s: мин=%.0f макс=%.0f сред=%.0f, размах=%.0f (%.1f%% от среднего)"
		% [name, mn, mx, avg, mx - mn, (mx - mn) / avg * 100.0])

# ── 3.3 ─────────────────────────────────────────────────────────────────────
func _t33_practice() -> void:
	print("\n══════ 3.3 ПРАКТИКА: ВЫРАБОТКА ОДНОГО КУСКА ЗОЛОТА ══════")
	var Worker := load("res://scenes/units/Worker.tscn") as PackedScene
	var CastleS = load("res://scripts/Castle.gd")
	var base := Vector3(160.0, 0.0, 160.0)
	var castle: Building = CastleS.new()
	castle.faction = Constants.FACTION_PLAYER
	main.add_child(castle)
	castle.global_position = base
	await get_tree().process_frame

	var ore := ResourceNode.new()
	ore.resource_type = Constants.RESOURCE_GOLD
	ore.remaining = 1260.0     # «большой» кусок ровно по PIECE_CLASSES
	main.add_child(ore)
	ore.global_position = base + Vector3(4.0, 0.0, 0.0)
	await get_tree().process_frame

	var w: Unit = Worker.instantiate()
	w.faction = Constants.FACTION_PLAYER
	main.add_child(w)
	w.global_position = base + Vector3(3.0, 0.0, 0.0)
	await get_tree().process_frame
	print("  gather_time=%.1f с, gather_amount=%.1f, запас куска=%.0f (прежний был 420)"
		% [w.gather_time, w.gather_amount, ore.remaining])
	print("  замок-склад в %.1f м от жилы (полный цикл = рубка + бег туда-обратно)"
		% base.distance_to(ore.global_position))
	w.command_gather(ore)

	Engine.time_scale = 10.0
	var game_time := 0.0
	var frames := 0
	var start_amount: float = ore.remaining
	var t_half := -1.0
	while is_instance_valid(ore) and ore.remaining > 0.0 and frames < 60 * 400:
		await get_tree().physics_frame
		game_time += get_physics_process_delta_time()
		frames += 1
		if t_half < 0.0 and ore.remaining <= start_amount * 0.5:
			t_half = game_time
	Engine.time_scale = 1.0
	var left: float = ore.remaining if is_instance_valid(ore) else 0.0
	var mined: float = start_amount - left
	print("  выработано %.0f из %.0f за %.1f с игрового времени (%d физ. кадров)"
		% [mined, start_amount, game_time, frames])
	if t_half > 0.0:
		print("  половина куска (630 ед.) выработана за %.1f с" % t_half)
	if mined > 0.0:
		var rate: float = mined / game_time
		print("  темп добычи: %.3f ед/с → полный кусок 1260 ед = %.1f с (%.1f мин)"
			% [rate, 1260.0 / rate, 1260.0 / rate / 60.0])
		print("  прежний кусок 420 ед = %.1f с (%.1f мин) — ровно втрое меньше"
			% [420.0 / rate, 420.0 / rate / 60.0])
		print("  теоретический минимум (только рубка, без беготни): %.0f с"
			% (1260.0 / 10.0 * 3.0))
	if is_instance_valid(ore):
		ore.queue_free()
	w.queue_free()
	castle.queue_free()
	await get_tree().process_frame
