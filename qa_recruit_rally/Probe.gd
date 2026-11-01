extends Node
## ЗОНД (вердиктов нет): новобранцы из барака на точку сбора с флажком.
## Вопрос владельца 29.10.2026: «только что построенные отряды добегают до
## точки сбора и бегут на месте, гаснут по таймерам». Сценарии:
##   S1 — один заказ на пустой флажок;
##   S2 — три заказа подряд (один кадр между ними) на один флажок;
##   S3 — на флажок, где уже стоят три прежних заказа (вторая волна найма);
##   S4 — флажок внутри строя, пришедшего приказом игрока (slots).
## Печатает по каждому отряду: когда встал, сколько в MOVING по секундам,
## сработал ли валидатор, и по каждому бегущему на 8-й секунде — расстояние
## до ячейки, ход, соседи. Аргументы: ladders=0 — лестницы застревания
## (stall_arrive, run_in_place_cure, unstick) выключены; only=1234; size=N.
const _Opt := preload("res://scripts/perf_config.gd")
const SPEARMAN := preload("res://scenes/units/Spearman.tscn")
var main: Node
var _ladders: bool = true
var _only: String = "1234"
var _size: int = 20
var _defense: bool = false
var _foe_off: float = 0.0     # чужой блок сдвинут от флажка к бараку на N м
var _dmg: bool = false        # новобранцы бьют по-настоящему (враг безвреден)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("ladders="):
			_ladders = s.substr(8) != "0"
		elif s.begins_with("only="):
			_only = s.substr(5)
		elif s.begins_with("size="):
			_size = int(s.substr(5))
		elif s == "defense=1":
			_defense = true
		elif s.begins_with("foeoff="):
			_foe_off = float(s.substr(7))
		elif s == "dmg=1":
			_dmg = true
	call_deferred("_run")

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _moving(men: Array) -> int:
	var n := 0
	for m in _alive(men):
		if (m as Unit).state == Unit.State.MOVING:
			n += 1
	return n

func _flat(c: Vector3, r: float) -> void:
	main._clear_trees(c, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(c) < r:
				u.queue_free()

func _barracks(at: Vector3) -> Building:
	var b: Building = Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return b

## Заказать k отрядов подряд; вернуть массив [sid → бойцы]
func _order(b: Building, k: int) -> Dictionary:
	var before: Array = get_tree().get_nodes_in_group("player_units").duplicate()
	b.squad_size = _size
	for _i in range(k):
		b.queue_unit("spearman", {}, 0.01)
	for j in b.production_queue:
		(j as Dictionary)["time"] = 0.01
	var want: int = before.size() + k * _size
	for _f in range(600):
		await get_tree().physics_frame
		if get_tree().get_nodes_in_group("player_units").size() >= want:
			break
	await pframes(2)
	var out: Dictionary = {}
	for n in get_tree().get_nodes_in_group("player_units"):
		if n in before:
			continue
		var sid: int = (n as Unit).squad_id
		if not out.has(sid):
			out[sid] = []
		(out[sid] as Array).append(n)
	return out

func _post_centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for m in _alive(men):
		c += (m as Unit).post_pos
		n += 1
	return c / maxf(float(n), 1.0)

func _extent(men: Array) -> Vector2:
	var minx := INF; var maxx := -INF; var minz := INF; var maxz := -INF
	for m in _alive(men):
		var p: Vector3 = (m as Unit).post_pos
		minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
		minz = minf(minz, p.z); maxz = maxf(maxz, p.z)
	return Vector2(maxx - minx, maxz - minz)

func _nearest_other(u: Unit, r: float) -> Array:
	var best: float = INF
	var who: Unit = null
	for n in GameManager.unit_grid.query_radius(u.global_position, r):
		var o := n as Unit
		if o == null or o == u or o.is_dead():
			continue
		var d: float = o.global_position.distance_to(u.global_position)
		if d < best:
			best = d
			who = o
	return [best, who]

func _watch(label: String, groups: Dictionary, flag: Vector3, secs: float) -> void:
	var t0: int = Unit.game_ms()
	var st0: int = Unit.stall_arrivals
	var z0: int = Unit.zone_arrivals
	var h0: int = Unit.rip_halts
	var rp0: int = Unit.rip_repaths
	var un0: int = Unit.unstuck_total
	var set0: int = GameManager.squad_arrive_settled
	var done: Dictionary = {}
	var moving_log: Dictionary = {}
	var dumped := false
	for sid in groups.keys():
		moving_log[sid] = []
	while Unit.game_ms() - t0 < int(secs * 1000.0):
		await pframes(30)
		var el: float = float(Unit.game_ms() - t0) / 1000.0
		for sid in groups.keys():
			var mv: int = _moving(groups[sid])
			(moving_log[sid] as Array).append("%.1f:%d" % [el, mv])
			if mv == 0 and not done.has(sid):
				done[sid] = el
		if el >= 8.0 and not dumped:
			dumped = true
			for sid in groups.keys():
				for m in _alive(groups[sid]):
					var u := m as Unit
					if u.state != Unit.State.MOVING:
						continue
					var p: Vector3 = u.global_position
					var dt: float = Vector2(u.move_target.x - p.x, u.move_target.z - p.z).length()
					var dp: float = Vector2(u.post_pos.x - p.x, u.post_pos.z - p.z).length()
					var nb: Array = _nearest_other(u, 2.0)
					var o: Unit = nb[1]
					var o_s: String = "—"
					if o != null:
						o_s = "sid %d st %d settled %s" % [o.squad_id, int(o.state), str(o._settled)]
					print("      sid %d боец %d: до цели %.2f, до ячейки %.2f, ход %.2f/%.2f м/с, бег %s, told %s, arrived %s, jammed %s, маршрут %d/%d, streak %d, сосед %.2f м [%s]" % [
						sid, u.get_instance_id() % 1000, dt, dp, u._mv_speed, u._effective_speed(), str(u.sprinting), str(u._zone_told), str(u._squad_arrived), str(u._arrive_jammed()), u._route_i, u._route.size(), u._stuck_streak, float(nb[0]), o_s])
	print("  [%s] за %.0f с: stall %d, zone %d, settled(валид.) %d, cure-halt %d, cure-repath %d, unstick %d" % [label, secs,
		Unit.stall_arrivals - st0, Unit.zone_arrivals - z0, GameManager.squad_arrive_settled - set0, Unit.rip_halts - h0, Unit.rip_repaths - rp0, Unit.unstuck_total - un0])
	var src_rows: Array = []
	for r in _Opt.cmd_sid_report():
		if groups.has(int(r[1])):
			src_rows.append("%s→sid %d: %d" % [String(r[0]), int(r[1]), int(r[2])])
	print("    источники command_move по отрядам: %s" % ", ".join(src_rows))
	_Opt.cmd_reset()
	for sid in groups.keys():
		var men: Array = groups[sid]
		var told := 0
		var arr := 0
		for m in _alive(men):
			if (m as Unit)._zone_told: told += 1
			if (m as Unit)._squad_arrived: arr += 1
		var pc: Vector3 = _post_centre(men)
		var ex: Vector2 = _extent(men)
		var worst := 0.0
		for m in _alive(men):
			var u := m as Unit
			worst = maxf(worst, Vector2(u.post_pos.x - u.global_position.x, u.post_pos.z - u.global_position.z).length())
		print("    sid %d (%d): встали через %s с; MOVING по секундам %s; валидатор %d раз, told %d, arrived-флаг %d; центр ячеек от флажка %.2f м, блок %.1f×%.1f, худший от ячейки %.2f" % [
			sid, _alive(men).size(), str(done.get(sid, "НЕ ВСТАЛИ")), " ".join(moving_log[sid]), int(GameManager.squad_arrive_by_sid.get(sid, 0)), told, arr,
			Vector2(pc.x - flag.x, pc.z - flag.z).length(), ex.x, ex.y, worst])

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for nm in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager"]:
		var nd = main.get(nm)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	_Opt.squad_probes = true
	_Opt.cmd_meter = true
	_Opt.stall_arrive = _ladders
	_Opt.run_in_place_cure = _ladders
	_Opt.unstick = _ladders
	print("зонд новобранцев: size=%d, лестницы=%s, валидатор=%s, SPAWN spacing=%.2f, SQUAD_SPOT_SPACING=%.2f, want_r(size)=%.2f" % [
		_size, str(_ladders), str(_Opt.squad_arrive_validate), Building.spawn_spacing(0.35), GameManager.SQUAD_SPOT_SPACING,
		sqrt(float(_size)) * 0.5 * GameManager.SQUAD_SPOT_SPACING + 0.4])
	var ford: Vector3 = main.ford_point()
	var base := Vector3(ford.x - 90.0, 0, ford.z + 40.0)
	_flat(base, 45.0)
	await pframes(5)
	var b: Building = _barracks(base)
	await pframes(5)
	var flag: Vector3 = base + Vector3(0, 0, 22.0)
	flag.y = GameManager.get_terrain_height(flag.x, flag.z)

	if "1" in _only:
		print("\n── S1: один заказ на пустой флажок ──")
		b.set_rally_point(flag)
		var g1: Dictionary = await _order(b, 1)
		await _watch("S1", g1, flag, 30.0)
		for sid in g1.keys():
			for m in g1[sid]:
				if is_instance_valid(m): m.queue_free()
		await pframes(10)

	if "2" in _only:
		print("\n── S2: три заказа подряд на один флажок ──")
		b.set_rally_point(flag)
		var g2: Dictionary = await _order(b, 3)
		await _watch("S2", g2, flag, 40.0)
		if "3" in _only:
			print("\n── S3: вторая волна (три заказа) на флажок, где стоят первые три ──")
			var g3: Dictionary = await _order(b, 3)
			await _watch("S3", g3, flag, 40.0)
			print("    и прежние три после второй волны:")
			await _watch("S3-старые", g2, flag, 5.0)
			for sid in g3.keys():
				for m in g3[sid]:
					if is_instance_valid(m): m.queue_free()
		for sid in g2.keys():
			for m in g2[sid]:
				if is_instance_valid(m): m.queue_free()
		await pframes(10)

	if "4" in _only:
		print("\n── S4: флажок внутри строя, стоящего по приказу игрока ──")
		var sid_a: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		var army: Array = []
		for k in range(60):
			var u: Unit = SPEARMAN.instantiate()
			u.faction = Constants.FACTION_PLAYER
			main.world_add(u)
			var p: Vector3 = flag + Vector3(float(k % 10) * 0.55 - 2.5, 0, float(k / 10) * 0.55 - 1.4)
			u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
			u.sync_row()
			GameManager.add_to_squad(sid_a, u)
			army.append(u)
		await pframes(5)
		var slots: Array = []
		for u in army:
			slots.append((u as Unit).global_position)
			(u as Unit).command_move((u as Unit).global_position, false, Vector3.BACK, false, true)
		GameManager.squad_set_formation(sid_a, slots, Vector3.BACK, false)
		if _defense:
			for u in army:
				(u as Unit).set_stance("defense")
		await pframes(60)
		print("    строй игрока: sid %d, MOVING %d, центр ячеек от флажка %.2f м" % [sid_a, _moving(army), Vector2(_post_centre(army).x - flag.x, _post_centre(army).z - flag.z).length()])
		b.set_rally_point(flag)
		var g4: Dictionary = await _order(b, 2)
		await _watch("S4", g4, flag, 40.0)
	if "5" in _only or "6" in _only:
		var live: bool = "6" in _only
		print("\n── S%s: у флажка чужой отряд (24 копейщика красных), %s ──" % ["6" if live else "5", "ЖИВОЙ, урон 0 с обеих сторон" if live else "ЗАМОРОЖЕННЫЙ (set_tick false)"])
		var sid_e: int = GameManager.new_squad(Constants.FACTION_ENEMY, "spearman")
		var foes: Array = []
		for k in range(24):
			var u: Unit = SPEARMAN.instantiate()
			u.faction = Constants.FACTION_ENEMY
			main.world_add(u)
			var p: Vector3 = flag + Vector3(float(k % 6) * 0.7 - 1.75, 0, float(k / 6) * 0.7 - 1.05 - _foe_off)
			u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
			u.sync_row()
			u.post_pos = u.global_position
			GameManager.add_to_squad(sid_e, u)
			foes.append(u)
		await pframes(10)
		for u in foes:
			if live:
				(u as Unit).attack_damage = 0.0
			else:
				(u as Unit).set_tick(false)
		b.set_rally_point(flag)
		var g5: Dictionary = await _order(b, 2)
		if live and not _dmg:
			for sid in g5.keys():
				for m in g5[sid]:
					(m as Unit).attack_damage = 0.0
		await _watch("S%s" % ("6" if live else "5"), g5, flag, 40.0)
		for sid in g5.keys():
			var st: Dictionary = {}
			for m in _alive(g5[sid]):
				var k: int = int((m as Unit).state)
				st[k] = int(st.get(k, 0)) + 1
			print("    sid %d состояния к концу %s (0 IDLE, 1 MOVING, 2 ATTACKING)" % [sid, str(st)])
	print("\n=== RECRUIT RALLY PROBE DONE ===")
	get_tree().quit()
