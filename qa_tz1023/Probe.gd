extends Node
## ЗОНД ТЗ 23.10.2026 (вердиктов нет): воспроизвести жалобы числами.
##   a — отклик лучников и пехоты на ПКМ по врагу (время до первой стрелы /
##       до трогания), из покоя, с марша, из чужого боя
##   l — протяжка ПКМ из «каши» после боя: доля на постах по секундам и доля
##       ЧУЖИХ среди ближайших соседей (мера «слились в кучу»)
##   m — армия против армии: доля чужих соседей своих отрядов в свалке
## Запуск: godot --headless --path . res://qa_tz1023/Probe.tscn -- only=alm

const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const _UCfg := preload("res://scripts/unit_stats_config.gd")
var main: Node = null
var sm = null
var _only := "alm"
var _diag := false
var _diag2 := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		if String(a) == "diag=2":
			_diag2 = true
		if String(a) == "diag=1":
			_diag = true
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ")
		get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _staff(kind: String) -> Array:
	var bld: String = "archery" if kind == "archer" else "barracks"
	var cfg: Dictionary = _UCfg.train_cfg(bld, kind)
	return [int(cfg.get("squad", 20)), int(cfg.get("cols", 5))]

func _squad(uid: String, f: int, at: Vector3, n: int = -1, cols: int = -1, jitter: float = 0.0) -> int:
	var st: Array = _staff(uid)
	if n < 0: n = int(st[0])
	if cols < 0: cols = int(st[1])
	var sid: int = GameManager.new_squad(f, uid)
	var gap := 0.65
	for i in range(n):
		var p: Vector3 = at + Vector3(float(i / cols) * gap, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * gap)
		if jitter > 0.0:
			p += Vector3(randf_range(-jitter, jitter), 0.0, randf_range(-jitter, jitter))
		GameManager.add_to_squad(sid, _unit(uid, f, p))
	return sid

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _all(sids: Array) -> Array:
	var o: Array = []
	for s in sids:
		o.append_array(_members(int(s)))
	return o

func _wipe(at: Vector3, r: float) -> void:
	main._clear_area_of_resources(at, r)
	main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()

func _kill(sids: Array) -> void:
	for u in _all(sids):
		(u as Unit).take_damage(1.0e12)

func _run() -> void:
	seed(12345)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	sm = main.selection_manager
	if "a" in _only: await _a_response()
	if "l" in _only: await _l_line()
	if "m" in _only: await _m_melee()
	if "g" in _only: await _g_group_click()
	print("ЗОНД ГОТОВ")
	get_tree().quit()

# ─────────────────────────────────────────────────────────────────────────────
func _order_attack(men: Array, target: Unit) -> void:
	sm.select_units(men)
	for u in men:
		(u as Unit).command_attack(target, true, true, true)

func _a_case(label: String, kind: String, dist: float, pre: String) -> void:
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 10.0)
	_wipe(spot, 45.0)
	await pframes(5)
	var mine: int = _squad(kind, F, spot)
	var foe: int = _squad("spearman", R, spot + Vector3(dist, 0.0, 0.0))
	var other: int = -1
	await pframes(20)
	for u in _members(foe):
		(u as Unit).set_tick(false)
	if pre == "march":
		for u in _members(mine):
			(u as Unit).command_move((u as Unit).global_position + Vector3(0, 0, 12), false, Vector3.ZERO, false, true)
		await pframes(40)
	elif pre == "fight":
		other = _squad("spearman", R, spot + Vector3(-12.0, 0.0, 0.0))
		await pframes(5)
		for u in _members(other):
			(u as Unit).set_tick(false)
		var t0: Unit = _members(other)[0]
		_order_attack(_members(mine), t0)
		await pframes(240)
	elif pre == "retreat":
		other = _squad("spearman", R, spot + Vector3(-3.0, 0.0, 0.0))
		await pframes(5)
		_order_attack(_members(mine), _members(other)[0])
		await pframes(120)
		for u in _members(mine):
			(u as Unit).command_move((u as Unit).global_position + Vector3(8, 0, -14), false, Vector3.ZERO, false, true)
		await pframes(30)
	var men: Array = _members(mine)
	var tgt: Unit = _members(foe)[0]
	var a0: int = GameManager.arrows_fired
	var start: Dictionary = {}
	for u in men:
		start[u] = (u as Unit).global_position
	_order_attack(men, tgt)
	var t_first := -1.0
	var t_half := -1.0
	var t_move := -1.0
	var hits0: Dictionary = {}
	for f in range(60 * 12):
		await get_tree().physics_frame
		var t: float = float(f + 1) / 60.0
		if (_diag or (_diag2 and kind == "archer" and f < 240)) and f % 15 == 0 and men.size() > 0 and is_instance_valid(men[0]):
			var u0: Unit = men[0]
			var tt = u0.attack_target
			var dd: float = u0.global_position.distance_to((tt as Node3D).global_position) if (tt != null and is_instance_valid(tt)) else -1.0
			print("    t=%.2f st=%d tgt=%s d=%.1f rng=%.1f timer=%.2f snooze=%s vel=%.2f march=%s lock=%.2f dis=%s forced=%s" % [t, u0.state, tt != null, dd, u0.attack_range, u0._attack_timer, u0._atk_snooze, u0.velocity.length(), u0._march_pending, u0._move_lock, u0._disengaging, u0._attack_is_forced])
		if kind == "archer":
			var fired: int = GameManager.arrows_fired - a0
			if fired > 0 and t_first < 0.0: t_first = t
			if fired >= men.size() / 2 and t_half < 0.0: t_half = t
		else:
			var moved := 0
			var atk := 0
			for u in men:
				if not is_instance_valid(u): continue
				if (u as Unit).global_position.distance_to(start[u]) > 0.5: moved += 1
				if (u as Unit).state == Unit.State.ATTACKING: atk += 1
			if moved >= men.size() / 2 and t_move < 0.0: t_move = t
		if (t_first > 0 and t_half > 0) or t_move > 0:
			break
	var st: Dictionary = {}
	for u in men:
		if is_instance_valid(u):
			var k: String = str((u as Unit).state)
			st[k] = int(st.get(k, 0)) + 1
	print("  %-8s %-8s d=%4.0f м: первая стрела %5.2f с, половина %5.2f с, тронулись %5.2f с | состояния %s" % [
		kind, pre, dist, t_first, t_half, t_move, str(st)])
	_kill([mine, foe] + ([other] if other > 0 else []))
	await pframes(30)

func _a_response() -> void:
	print("\n═════ A. ОТКЛИК НА ПКМ ПО ВРАГУ ═════")
	if _diag:
		await _a_case("", "archer", 12.0, "march")
		await _a_case("", "warrior", 20.0, "retreat")
		return
	for pre in ["idle", "march", "fight", "retreat"]:
		for d in [12.0, 30.0]:
			await _a_case("", "archer", d, pre)
	for pre in ["idle", "march", "fight", "retreat"]:
		await _a_case("", "spearman", 20.0, pre)
		await _a_case("", "warrior", 20.0, pre)

# ─────────────────────────────────────────────────────────────────────────────
## Доля чужих среди k ближайших соседей своих бойцов (0 — каждый в своей
## коробке, ~1 — полная каша); считается по выборке
func _foreign_share(men: Array, k: int = 4, sample: int = 200) -> float:
	var n: int = men.size()
	if n < k + 1:
		return 0.0
	var step: int = maxi(1, n / sample)
	var tot := 0
	var foreign := 0
	var i := 0
	while i < n:
		var u := men[i] as Unit
		var p: Vector3 = u.global_position
		var best: Array = []   # [d2, sid]
		for j in range(n):
			if j == i: continue
			var v := men[j] as Unit
			var d2: float = (v.global_position - p).length_squared()
			if best.size() < k:
				best.append([d2, v.squad_id])
				best.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			elif d2 < float(best[k - 1][0]):
				best[k - 1] = [d2, v.squad_id]
				best.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		for b in best:
			tot += 1
			if int(b[1]) != u.squad_id:
				foreign += 1
		i += step
	return float(foreign) / float(maxi(tot, 1))

func _at_post(men: Array, tol: float = 1.2) -> float:
	var ok := 0
	for u in men:
		var p: Vector3 = (u as Unit).global_position
		var q: Vector3 = (u as Unit).post_pos
		if Vector2(p.x - q.x, p.z - q.z).length() < tol:
			ok += 1
	return float(ok) / float(maxi(men.size(), 1))

func _l_line() -> void:
	print("\n═════ L. ПРОТЯЖКА ПКМ ИЗ КАШИ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(45.0, 0.0, 15.0)
	_wipe(spot, 60.0)
	await pframes(5)
	var kinds := ["spearman", "spearman", "archer", "warrior", "spearman", "archer",
		"spearman", "warrior", "archer", "spearman", "spearman", "archer",
		"warrior", "spearman", "archer", "spearman", "spearman", "warrior"]
	var sids: Array = []
	for i in range(kinds.size()):
		var at: Vector3 = spot + Vector3(randf_range(-14, 14), 0.0, randf_range(-12, 12))
		sids.append(_squad(kinds[i], F, at, -1, -1, 3.0))
	await pframes(30)
	var men: Array = _all(sids)
	print("  армия %d отрядов, %d бойцов; чужих соседей в каше %.2f" % [sids.size(), men.size(), _foreign_share(men)])
	for rep in range(3):
		sm.select_units(men)
		var z: float = spot.z + (25.0 if rep % 2 == 0 else -25.0)
		sm._execute_line_formation(Vector3(spot.x - 35.0, 0, z), Vector3(spot.x + 35.0, 0, z))
		var line := "  приказ %d:" % (rep + 1)
		for sec in range(1, 41):
			await pframes(60)
			if sec in [2, 5, 10, 15, 20, 30, 40]:
				line += "  %dс пост %.0f%% чуж %.2f" % [sec, _at_post(men) * 100.0, _foreign_share(men)]
		print(line)

# ─────────────────────────────────────────────────────────────────────────────
func _m_melee() -> void:
	print("\n═════ M. АРМИЯ НА АРМИЮ: КОРОБКИ ИЛИ КАША ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(45.0, 0.0, 15.0)
	_wipe(spot, 70.0)
	await pframes(5)
	var mine: Array = []
	var foes: Array = []
	for i in range(8):
		var z: float = spot.z - 28.0 + float(i) * 8.0
		mine.append(_squad("spearman" if i % 3 != 2 else "warrior", F, Vector3(spot.x - 25.0, 0, z)))
		foes.append(_squad("spearman" if i % 3 != 1 else "warrior", R, Vector3(spot.x + 25.0, 0, z)))
	await pframes(30)
	# Крест-накрест: i-й наш на (i+3)-й чужой — пути отрядов пересекаются,
	# как в свалке партии
	for i in range(8):
		var tf: Array = _members(int(foes[(i + 3) % 8]))
		var tm: Array = _members(int(mine[(i + 5) % 8]))
		for u in _members(int(mine[i])):
			(u as Unit).command_attack(tf[0], true, true, true)
		for u2 in _members(int(foes[i])):
			(u2 as Unit).command_attack(tm[0], true, true, false)
	var line := "  "
	for sec in range(1, 91):
		await pframes(60)
		if sec % 10 == 0:
			var a: Array = _all(mine)
			var b: Array = _all(foes)
			line += " %dс %d/%.2f, %d/%.2f, разд %d |" % [sec, a.size(), _foreign_share(a), b.size(), _foreign_share(b), GameManager.reform_unboxed]
	print(line)

# ─────────────────────────────────────────────────────────────────────────────
## Каша после боя (центры отрядов в 3-8 м друг от друга) → ПКМ-клик по земле:
## переносится ли каша как есть
func _g_group_click() -> void:
	print("\n═════ G. ПКМ-КЛИК ГРУППОЙ ИЗ КАШИ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(45.0, 0.0, 15.0)
	_wipe(spot, 60.0)
	await pframes(5)
	var kinds := ["spearman", "spearman", "archer", "warrior", "spearman", "archer",
		"spearman", "warrior", "archer", "spearman", "spearman", "archer"]
	var sids: Array = []
	for i in range(kinds.size()):
		var a: float = TAU * float(i) / float(kinds.size())
		var at: Vector3 = spot + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 7.0)
		sids.append(_squad(kinds[i], F, at, -1, -1, 2.5))
	await pframes(30)
	var men: Array = _all(sids)
	print("  армия %d отрядов, %d бойцов; чужих соседей в каше %.2f" % [sids.size(), men.size(), _foreign_share(men)])
	for rep in range(3):
		sm.select_units(men)
		var dest: Vector3 = spot + Vector3(0.0, 0.0, 28.0 if rep % 2 == 0 else -28.0)
		sm._issue_formation_move(dest, false)
		var line := "  клик %d:" % (rep + 1)
		for sec in range(1, 31):
			await pframes(60)
			if sec in [5, 10, 20, 30]:
				line += "  %dс пост %.0f%% чуж %.2f" % [sec, _at_post(men) * 100.0, _foreign_share(men)]
		print(line)
