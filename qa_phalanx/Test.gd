extends Node

## Проверка пакета: динамическая фаланга, ребаланс толчков, ×3 к руде.

var main: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_test_ore_amounts()
	await _test_phalanx_ranks()
	await _test_push()
	print("\n=== PHALANX TEST DONE ===")
	get_tree().quit()

# ── 3. Запас золота и камня ─────────────────────────────────────────────────
func _test_ore_amounts() -> void:
	print("\n───── ЗАПАС РУДЫ ─────")
	var by_type := {}
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null:
			continue
		var t: int = rn.resource_type
		if not by_type.has(t):
			by_type[t] = {"n": 0, "sum": 0.0, "min": INF, "max": 0.0}
		var d: Dictionary = by_type[t]
		d["n"] = int(d["n"]) + 1
		d["sum"] = float(d["sum"]) + rn.remaining
		d["min"] = minf(float(d["min"]), rn.remaining)
		d["max"] = maxf(float(d["max"]), rn.remaining)
	for t in [Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_WOOD]:
		if not by_type.has(t):
			continue
		var d: Dictionary = by_type[t]
		var label := "золото" if t == Constants.RESOURCE_GOLD else ("камень" if t == Constants.RESOURCE_STONE else "дерево")
		print("  %-7s узлов=%4d  всего=%9.0f  на узел: мин=%.0f макс=%.0f сред=%.0f"
			% [label, int(d["n"]), float(d["sum"]), float(d["min"]), float(d["max"]),
			   float(d["sum"]) / float(d["n"])])
	print("  прежние значения кусков были 420/250/130 → ожидаем 1260/750/390")

# ── 1. Фаланга: ряды, смыкание, переключение поз ────────────────────────────
func _test_phalanx_ranks() -> void:
	print("\n───── ФАЛАНГА: РЯДЫ И СМЫКАНИЕ ─────")
	var Spear := load("res://scenes/units/Spearman.tscn") as PackedScene
	# Строй 6 колонн × 5 рядов, фронтом на +X, враг справа
	var squad: Array = []
	for row in range(5):
		for col in range(6):
			var u: Unit = Spear.instantiate()
			u.faction = Constants.FACTION_PLAYER
			main.add_child(u)
			u.global_position = Vector3(-float(row) * 0.55, 0.0, float(col) * 0.55)
			u.set_meta("start_x", -float(row) * 0.55)
			u.set_meta("row", row)
			squad.append(u)
	# Враг — стенка справа, чтобы фаланга видела направление
	var foes: Array = []
	for col in range(6):
		var e: Unit = Spear.instantiate()
		e.faction = Constants.FACTION_ENEMY
		main.add_child(e)
		e.global_position = Vector3(2.0, 0.0, float(col) * 0.55)
		foes.append(e)
	await get_tree().process_frame

	for u in squad:
		u.set_stance("defense")
	for e in foes:
		e.set_stance("defense")
	# Дать пересчитаться рядам (RANK_RECHECK = 0.25 c)
	for _i in range(40):
		await get_tree().physics_frame
	_print_ranks("после включения ЗАЩИТЫ", squad)

	# Убиваем ВЕСЬ первый ряд (row 0 — те, у кого x ≈ 0)
	var killed := 0
	for u in squad:
		if is_instance_valid(u) and absf(u.global_position.x) < 0.2:
			u._die()
			killed += 1
	print("  убито бойцов первой шеренги: %d" % killed)
	for _i in range(60):
		await get_tree().physics_frame
	_print_ranks("после гибели первой шеренги", squad)

	# Смыкание: сместились ли выжившие вперёд (к врагу, +X).
	# Стартовая позиция была записана в _start_x при создании
	var advanced := 0
	var sum_adv := 0.0
	var max_adv := -99.0
	for u in squad:
		if not is_instance_valid(u) or u.is_dead():
			continue
		var adv: float = u.global_position.x - float(u.get_meta("start_x"))
		if adv > 0.05:
			advanced += 1
		sum_adv += adv
		max_adv = maxf(max_adv, u.global_position.x)
	print("  шагнули вперёд: %d из %d, средний сдвиг=%.2f м, передний край x=%.2f"
		% [advanced, 24, sum_adv / 24.0, max_adv])
	print("  (первая шеренга стояла на x=0.00, враг на x=2.00, копьё достаёт 2.0 м)")

	for u in squad + foes:
		if is_instance_valid(u):
			u.queue_free()
	await get_tree().process_frame

func _print_ranks(label: String, squad: Array) -> void:
	var hist := {}
	var leveled := 0
	var alive := 0
	# Сверка: сколько бойцов КАЖДОЙ исходной шеренги считают себя передовыми
	var by_row := {}
	for u in squad:
		if not is_instance_valid(u) or u.is_dead():
			continue
		alive += 1
		var r: int = u._live_rank
		hist[r] = int(hist.get(r, 0)) + 1
		var src: int = int(u.get_meta("row"))
		if not by_row.has(src):
			by_row[src] = [0, 0]
		var e: Array = by_row[src]
		e[0] = int(e[0]) + 1
		if u.call("_spear_leveled"):
			leveled += 1
			e[1] = int(e[1]) + 1
	print("  %s: живых=%d, копья горизонтально=%d, живые ряды %s"
		% [label, alive, leveled, str(hist)])
	var keys: Array = by_row.keys()
	keys.sort()
	for k in keys:
		var e: Array = by_row[k]
		print("     исходная шеренга %d: живых=%d, из них с горизонтальным копьём=%d"
			% [int(k), int(e[0]), int(e[1])])

# ── 2. Толчки ───────────────────────────────────────────────────────────────
func _test_push() -> void:
	print("\n───── ТОЛЧКИ ─────")
	var Spear := load("res://scenes/units/Spearman.tscn") as PackedScene
	var UCfg := load("res://scripts/unit_stats_config.gd")
	print("  PUSH_GLOBAL_SCALE = %.2f (ожидается 0.35)" % UCfg.PUSH_GLOBAL_SCALE)
	print("  push_resist: атака=%.2f, защита=%.2f"
		% [UCfg.stance_stat("attack", "push_resist", 1.0),
		   UCfg.stance_stat("defense", "push_resist", 1.0)])
	print("  push_mult:   атака=%.2f, защита=%.2f"
		% [UCfg.stance_stat("attack", "push_mult", 1.0),
		   UCfg.stance_stat("defense", "push_mult", 1.0)])

	for case in ["атакующий → атакующего", "атакующий → фалангу", "фаланга → атакующего"]:
		var a: Unit = Spear.instantiate()
		var b: Unit = Spear.instantiate()
		a.faction = Constants.FACTION_PLAYER
		b.faction = Constants.FACTION_ENEMY
		main.add_child(a)
		main.add_child(b)
		a.global_position = Vector3(40.0, 0, 40.0)
		b.global_position = Vector3(41.0, 0, 40.0)
		await get_tree().process_frame
		# Толкающему даём перевес: у двух одинаковых бойцов разница нулевая
		# и толчка нет вовсе (равные шеренги стоят намертво — так и задумано)
		a.push_force += 4.0
		match case:
			"атакующий → фалангу":
				b.set_stance("defense")
			"фаланга → атакующего":
				a.set_stance("defense")
		var before_b: float = b.global_position.x
		var before_a: float = a.global_position.x
		a._apply_push(b, Vector3(1, 0, 0))
		var db: float = b.global_position.x - before_b
		var da: float = a.global_position.x - before_a
		print("  %-24s: цель отброшена на %.4f м, толкающий подался на %.4f м"
			% [case, db, da])
		a.queue_free()
		b.queue_free()
		await get_tree().process_frame
	print("  толкающему добавлено +4.0 push_force, иначе равные бойцы не двигают друг друга")
	print("  ожидание: по фаланге сдвиг заметно МЕНЬШЕ, чем по атакующему;")
	print("  фаланга сама не толкает вовсе (0.0000)")

	# Отдельно: равные бойцы друг друга не сдвигают, и упор фаланги выше
	var x: Unit = Spear.instantiate()
	var y: Unit = Spear.instantiate()
	x.faction = Constants.FACTION_PLAYER
	y.faction = Constants.FACTION_ENEMY
	main.add_child(x)
	main.add_child(y)
	x.global_position = Vector3(44, 0, 44)
	y.global_position = Vector3(45, 0, 44)
	await get_tree().process_frame
	print("  упор копейщика: в атаке=%.2f, в защите=%.2f (выше = труднее сдвинуть)"
		% [x.call("_stand_power"), _stand_in_defense(y)])
	print("  свой пуш копейщика: в атаке=%.2f, в защите=%.2f"
		% [x.call("_push_power"), _push_in_defense(y)])
	x.queue_free()
	y.queue_free()
	await get_tree().process_frame

func _stand_in_defense(u: Unit) -> float:
	u.set_stance("defense")
	return u.call("_stand_power")

func _push_in_defense(u: Unit) -> float:
	u.set_stance("defense")
	return u.call("_push_power")
