extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД: БЕГ НА МЕСТЕ ПОСЛЕ ВЫХОДА ИЗ КРЕПОСТИ (ТЗ 30.10.2026, п. 3)
## ═══════════════════════════════════════════════════════════════════════════
## Отряд игрока: паника → бегство → очередь лечения → замок → лазарет →
## авто-выход. После выхода 30 с окнами по 1 с: MOVING и сдвиг < 0.25 м —
## «бег на месте»; по застрявшим печатаются флаги бойца. Вердиктов нет.
##   -- only=pmr   p — после паники, m — «в замок» без паники, r — с флажком сбора

const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER

var main = null
var castle: Castle = null
var _only: String = "pmr"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился за 900 с")
		get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = F
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, cols: int) -> Array:
	var sid: int = GameManager.new_squad(F, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k / cols) * 0.7, 0, float(k % cols) * 0.7))
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(25.0, 0.0, 0.0), Vector3(-25.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 25.0), Vector3(0.0, 0.0, -25.0)]:
				var q: Vector3 = p + (d as Vector3)
				h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
				if GameManager.is_water(q.x, q.z):
					h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager", "boss_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if main.fog != null:
		main.fog.enabled = false
	GameManager.pop_limit_enabled = false
	var anchor: Vector3 = main.PLAYER_BASE_ANCHOR * 0.7
	anchor.y = 0.0
	var p: Vector3 = _flat_spot(anchor)
	main._clear_trees(p, 70.0)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(p) < 70.0:
				u.queue_free()
	castle = Castle.new()
	castle.faction = F
	main.world_add(castle)
	castle.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
	await pframes(10)
	print("  замок (%.0f, %.0f), ворота %s" % [p.x, p.z, str(castle._gate_position())])
	if _only.contains("p"):
		await _case("P после паники", p + Vector3(28, 0, 6), "panic", false)
	if _only.contains("m"):
		await _case("M «в замок»", p + Vector3(28, 0, -10), "castle", false)
	if _only.contains("r"):
		await _case("R паника + флажок", p + Vector3(-28, 0, 8), "panic", true)
	if _only.contains("d"):
		await _case("D «Защита», паника, потом приказ игрока", p + Vector3(28, 0, 6), "panic", false, false, "defense")
	if _only.contains("e"):
		await _case("E «Защита» + флажок на занятом", p + Vector3(-28, 0, 8), "panic", true, true, "defense")
	if _only.contains("f"):
		await _case("F враг на пути к флажку (стоит)", p + Vector3(28, 0, 6), "panic", true, false, "", 1)
	if _only.contains("g"):
		await _case("G враг на пути к флажку (живой)", p + Vector3(28, 0, 6), "panic", true, false, "", 2)
	if _only.contains("v"):
		await _case("V паника, потери: замок доукомплектует 12", p + Vector3(28, 0, 6), "panic", true, false, "", 0, 48)
	if _only.contains("o"):
		await _case("O выход на занятое место", p + Vector3(28, 0, 6), "panic", false, true)
	if _only.contains("q"):
		await _case("Q флажок на занятом месте", p + Vector3(-28, 0, 8), "panic", true, true)
	print("\n═════ ЗОНД qa_castle_exit завершён ═════")
	get_tree().quit()

var _blockers: Array = []

func _case(tag: String, at: Vector3, how: String, rally: bool, occupied: bool = false, stance: String = "", foes: int = 0, n_men: int = 60) -> void:
	print("\n═════ %s ═════" % tag)
	castle.has_rally = rally
	if rally:
		castle.rally_point = castle.global_position + Vector3(-18, 0, 14)
	# Стоящий свой отряд (прошлый выпуск) на точке выхода
	if occupied:
		var ex: Vector3 = castle.spawn_offset
		ex.y = 0.0
		ex = ex.normalized() if ex.length() > 0.01 else Vector3.BACK
		var dest: Vector3 = castle._gate_position() + ex * castle.SQUAD_EXIT_DISTANCE
		if rally:
			dest = castle.rally_point
		_blockers = _squad("spearman", dest - Vector3(3.0, 0, 3.0), 60, 10)
		print("  на точке выхода (%.1f, %.1f) стоит свой отряд из 60" % [dest.x, dest.z])
	var men: Array = _squad("spearman", at, n_men, 10)
	if n_men < 60:
		GameManager.squads[(men[0] as Unit).squad_id]["full"] = 60
	var sid: int = (men[0] as Unit).squad_id
	if stance != "":
		for m in men:
			(m as Unit).set_stance(stance)
	await pframes(20)
	for m in men:
		(m as Unit).current_health = (m as Unit).max_health * 0.6
		(m as Unit)._soa_push_stats()
	if how == "panic":
		GameManager._start_panic(sid)
		GameManager._drain_panic_queue(true)
	else:
		GameManager.squad_to_castle(sid)
	# До входа внутрь (все garrisoned) — до 120 с
	var t := 0
	while t < 7200:
		await pframes(30)
		t += 30
		var inside := 0
		for m in men:
			if is_instance_valid(m) and (m as Unit).garrisoned:
				inside += 1
		if inside == men.size():
			break
		if t % 600 == 0:
			print("  t=%.0f с: внутри %d/%d, паника %s, очередь %s, no_control %s" % [float(t) / 60.0,
				inside, men.size(), str(GameManager.squad_panicked(sid)),
				str(GameManager.squad_in_heal_queue(sid)), str(GameManager.squad_no_control(sid))])
	print("  внутри через %.1f с" % (float(t) / 60.0))
	var gobs: Array = []
	if foes > 0:
		var ex2: Vector3 = castle.spawn_offset
		ex2.y = 0.0
		ex2 = ex2.normalized() if ex2.length() > 0.01 else Vector3.BACK
		var side2 := Vector3(-ex2.z, 0.0, ex2.x)
		var gp: Vector3 = castle._gate_position() + ex2 * (castle.SQUAD_EXIT_DISTANCE + 3.0)
		if rally:
			gp = castle._gate_position().lerp(castle.rally_point, 0.55)
			ex2 = (castle.rally_point - castle._gate_position()).normalized()
			side2 = Vector3(-ex2.z, 0.0, ex2.x)
		var gsid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_spearman")
		for k in range(30):
			var off: Vector3 = side2 * (float(k % 10) - 4.5) * 1.0 + ex2 * float(k / 10) * 1.0
			var g: Unit = Building.PRELOAD_SCENES["goblin_spearman"].instantiate()
			g.faction = Constants.FACTION_GOBLIN
			main.world_add(g)
			var at2: Vector3 = gp + off
			g.global_position = Vector3(at2.x, GameManager.get_terrain_height(at2.x, at2.z), at2.z)
			g.sync_row()
			g.post_pos = g.global_position
			GameManager.add_to_squad(gsid, g)
			if foes == 1:
				g.set_tick(false)
			gobs.append(g)
		print("  у выхода (%.1f, %.1f) враг: 30 гоблинов, %s" % [gp.x, gp.z, "заморожены" if foes == 1 else "живые"])
	# Лечение ускоряем: внутри — до полного запаса сразу
	for m in men:
		if is_instance_valid(m):
			(m as Unit).current_health = (m as Unit).max_health
	var t2 := 0
	while t2 < 36000 and castle._slot_of(sid) >= 0:
		await pframes(30)
		t2 += 30
		for m in GameManager.squads[sid]["members"]:
			if is_instance_valid(m) and (m as Unit).garrisoned:
				(m as Unit).current_health = (m as Unit).max_health
	print("  в лазарете %.0f с" % (float(t2) / 60.0))
	print("  выпущен: %s, no_control %s" % [str(castle._slot_of(sid) < 0), str(GameManager.squad_no_control(sid))])
	men = (GameManager.squads[sid]["members"] as Array).duplicate()
	if stance != "":
		print("  стойка после выхода: %s" % String((men[0] as Unit).stance))
	await _watch(men, 12.0)
	if stance != "":
		# Приказ игрока: 25 м в сторону, как ПКМ по земле
		var c: Vector3 = (men[0] as Unit).global_position
		var to: Vector3 = GameManager.land_target(c + Vector3(-22, 0, 14))
		var sm = main.get("selection_manager")
		sm.selected_units = men.duplicate()
		sm.call("_issue_formation_move", to)
		if false:
			for m in men:
				(m as Unit).command_move(to + ((m as Unit).global_position - c), false, Vector3.ZERO, false, true)
		print("  приказ игрока → (%.0f, %.0f)" % [to.x, to.z])
		await _watch(men, 25.0)
	for m in _blockers + gobs:
		if is_instance_valid(m):
			m.queue_free()
	_blockers = []
	for m in men:
		if is_instance_valid(m):
			m.queue_free()
	await pframes(10)

func _watch(men: Array, sec: float) -> void:
	var last: Dictionary = {}
	var run: Dictionary = {}
	var worst := 0
	var told: Dictionary = {}
	var t := 0.0
	while t < sec:
		await pframes(60)
		t += 1.0
		var rip := 0
		var moving := 0
		var legs := 0
		var anims: Dictionary = {}
		for m in men:
			if m == null or not is_instance_valid(m) or (m as Unit).is_dead():
				continue
			var u := m as Unit
			var pp: Vector3 = u.global_position
			var k: int = u.get_instance_id()
			if u.state == Unit.State.MOVING:
				moving += 1
			if u.sprinting:
				legs += 1000
			if u.retreating:
				legs += 1000000
			if last.has(k):
				var lp: Vector3 = last[k]
				if u.state == Unit.State.MOVING and Vector2(pp.x - lp.x, pp.z - lp.z).length() < 0.25:
					run[k] = int(run.get(k, 0)) + 1
					rip += 1
					worst = maxi(worst, int(run[k]))
					if int(run[k]) == 3 and told.size() < 6 and not told.has(k):
						told[k] = true
						_dump(u)
				else:
					run[k] = 0
			if last.has(k) and Vector2(pp.x - (last[k] as Vector3).x, pp.z - (last[k] as Vector3).z).length() < 0.25:
				var an: String = String(u._anim_name)
				var key: String = "%s/%s" % [an, Unit.State.keys()[u.state]]
				anims[key] = int(anims.get(key, 0)) + 1
				if an.contains("walk") or an.contains("run"):
					legs += 1
			last[k] = pp
		print("  +%2.0f с: MOVING %d, бег на месте %d, ноги без хода %d %s" % [t, moving, rip, legs, str(anims)])
	print("  ИТОГ: худшая серия окон бега на месте %d" % worst)

func _dump(u: Unit) -> void:
	var mt: Vector3 = u.move_target
	var pp: Vector3 = u.global_position
	var keys := ["sprinting", "retreating", "_panicked", "_player_run", "_move_lock", "_squad_arrived",
		"_zone_told", "_mv_speed", "_stuck_streak", "_clear_enemy", "_order_pass", "dormant",
		"_phys_asleep", "garrisoned", "_fling_left", "stance", "_march_pending", "is_charging"]
	var s := ""
	for k in keys:
		var v = u.get(k)
		if v != null:
			s += "%s=%s " % [k, str(v)]
	print("    застрял %d: у (%.1f, %.1f) → цель (%.1f, %.1f) %.1f м; %s; ядро: st=%d" % [
		u.get_instance_id() % 10000, pp.x, pp.z, mt.x, mt.z,
		Vector2(mt.x - pp.x, mt.z - pp.z).length(), s,
		int(GameManager.army.get_state(u._soa)) if u._soa >= 0 and GameManager.army.has_method("get_state") else -1])
