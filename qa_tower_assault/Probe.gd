extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД ТЗ 25.10.2026 (третье письмо, п. 5): ПРОСАДКА КАДРА, КОГДА АРМИЯ
## ДОБИВАЕТ ВЫШКИ. Измеритель, вердиктов нет.
## ═══════════════════════════════════════════════════════════════════════════
## Сцена: 20 отрядов игрока (копейщики, мечники, лучники) в 45 м от двух
## вражеских башен; выделение целиком, ПКМ по первой башне тем же путём, что
## мышь (_handle_right_click). Первая башня ослаблена — падает быстро, и замок
## переходит на соседнюю (BUILDING_CHAIN_RANGE): ровно «добить оставшиеся».
## Печать каждые 30 физкадров: тик армии (tick_meter), худший кадр по стене,
## маршруты A*, промахи кэша дороги, худший A*, кто заказал.
## Запуск: godot --headless --path . res://qa_tower_assault/Probe.tscn

const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const _Opt := preload("res://scripts/perf_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main: Node = null

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: зонд завис")
		get_tree().quit(2))

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _wipe(at: Vector3, r: float) -> void:
	main._clear_area_of_resources(at, r)
	main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()

func _squad(uid: String, at: Vector3, n: int, cols: int) -> Array:
	var sid: int = GameManager.new_squad(F, uid)
	var men: Array = []
	var slots: Array = []
	for i in range(n):
		var p: Vector3 = at + Vector3(float(i % cols) * 0.6, 0.0, float(i / cols) * 0.6)
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = F
		main.world_add(u)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		slots.append(u.global_position)
		men.append(u)
	GameManager.squad_set_formation(sid, slots, Vector3(0, 0, -1), false)
	return men

func _run() -> void:
	seed(251025)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR.lerp(Vector3.ZERO, 0.45)
	spot.y = 0.0
	_wipe(spot, 90.0)
	await pframes(10)
	var towers: Array = []
	for k in range(2):
		var t: Building = load("res://scripts/Tower.gd").new()
		t.faction = R
		main.world_add(t)
		var tp: Vector3 = spot + Vector3(float(k) * 18.0 - 9.0, 0.0, -22.0)
		t.global_position = Vector3(tp.x, GameManager.get_terrain_height(tp.x, tp.z), tp.z)
		towers.append(t)
	await pframes(10)
	(towers[0] as Building).current_health = (towers[0] as Building).max_health * 0.15
	var all: Array = []
	var kinds := ["spearman", "spearman", "warrior", "archer", "spearman"]
	for q in range(20):
		var uid: String = kinds[q % kinds.size()]
		var at: Vector3 = spot + Vector3(float(q % 5) * 9.0 - 18.0, 0.0, 22.0 + float(q / 5) * 7.0)
		all.append_array(_squad(uid, at, 30, 10))
	await pframes(30)
	var sel = main.selection_manager
	main.set_process(false)
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	if cam != null:
		cam.set_process(false)
		cam.global_position = (towers[0] as Node3D).global_position + Vector3(0.0, 50.0, 40.0)
		cam.look_at((towers[0] as Node3D).global_position, Vector3.UP)
	await pframes(3)
	sel._clear_selection()
	for u in all:
		sel._select(u)
	_Opt.tick_meter = true
	_Opt.tick_reset()
	var prof := false
	for a in OS.get_cmdline_user_args():
		if String(a) == "prof=1":
			prof = true
	if prof:
		_Opt.profile_physics = true
		_Opt.prof_reset()
	var t0 := towers[0] as Building
	var line := ""
	var a0: Vector3 = (all[0] as Unit).global_position
	for k in range(12):
		var p: Vector3 = a0.lerp(t0.global_position, float(k) / 11.0)
		line += "%s" % ("." if GameManager.is_passable(p.x, p.z) else "#")
	print("[зонд] проходимость боец0 → башня: %s; ring_radius %.2f; башня %s" % [line, t0.ring_radius(), str(t0.global_position)])
	var scr: Vector2 = cam.unproject_position(t0.global_position + Vector3(0.0, 2.0, 0.0))
	# Сравнение: тот же подход, но цель — замороженный чужой отряд у башни
	if "target=unit" in OS.get_cmdline_user_args():
		var esid: int = GameManager.new_squad(R, "spearman")
		var foe: Unit = null
		for i in range(20):
			var u: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
			u.faction = R
			main.world_add(u)
			var ep: Vector3 = t0.global_position + Vector3(float(i % 5) * 0.6, 0.0, 6.0 + float(i / 5) * 0.6)
			u.global_position = Vector3(ep.x, GameManager.get_terrain_height(ep.x, ep.z), ep.z)
			u.sync_row()
			GameManager.add_to_squad(esid, u)
			u.set_tick(false)
			foe = u
		await pframes(3)
		scr = cam.unproject_position(foe.global_position + Vector3(0.0, 0.8, 0.0))
	print("[зонд] бойцов %d, клик в %s, цель под курсором: %s" % [all.size(), str(scr),
		str(sel._pick_at(scr, sel.order_pick_mask()).get("target"))])
	var us0: int = Time.get_ticks_usec()
	sel._handle_right_click(scr, false)
	print("[зонд] сам клик: %.2f мс" % (float(Time.get_ticks_usec() - us0) / 1000.0))
	var r0: int = GameManager.nav_routes_built
	var mk0: int = GameManager.nav_miss_key
	var mr0: int = GameManager.nav_miss_reuse
	GameManager.nav_worst_usec = 0
	var worst_ms := 0.0
	var last := Time.get_ticks_usec()
	var windows: int = 50
	for w in range(windows):
		worst_ms = 0.0
		for _f in range(30):
			await get_tree().physics_frame
			var nowu := Time.get_ticks_usec()
			worst_ms = maxf(worst_ms, float(nowu - last) / 1000.0)
			last = nowu
		var tick_ms: float = float(_Opt._tick_usec) / 1000.0 / float(maxi(_Opt._tick_frames, 1))
		_Opt.tick_reset()
		var alive_t := 0
		for t in towers:
			if is_instance_valid(t) and not (t as Building).is_dead():
				alive_t += 1
		print("  [%2d] тик армии %.2f мс | худший кадр %.1f мс | A* +%d (мимо ключа %d, мимо нити %d) худший A* %.2f мс | башен %d | кто %s" % [
			w, tick_ms, worst_ms, GameManager.nav_routes_built - r0, GameManager.nav_miss_key - mk0,
			GameManager.nav_miss_reuse - mr0, float(GameManager.nav_worst_usec) / 1000.0, alive_t,
			str(GameManager.nav_req_class)])
		r0 = GameManager.nav_routes_built
		mk0 = GameManager.nav_miss_key
		mr0 = GameManager.nav_miss_reuse
		GameManager.nav_worst_usec = 0
		GameManager.nav_req_class = {}
		# Кто чем занят: цель — башня, в досягаемости, ударов за окно
		var st_cnt: Dictionary = {}
		var on_t := 0
		var in_reach := 0
		var hits := 0
		for u in all:
			if not is_instance_valid(u) or (u as Unit).is_dead():
				continue
			var uu := u as Unit
			var sn: String = String(Unit.State.keys()[uu.state])
			st_cnt[sn] = int(st_cnt.get(sn, 0)) + 1
			if uu.attack_target != null and is_instance_valid(uu.attack_target) and uu.attack_target is Building:
				on_t += 1
				if not uu._target_out_of_reach():
					in_reach += 1
			hits += int(uu.get("_strike_count")) if uu.get("_strike_count") != null else 0
		var hp_s := ""
		for t in towers:
			hp_s += "%.0f " % ((t as Building).current_health if is_instance_valid(t) else -1.0)
		var ds: Array = []
		for u2 in all:
			if is_instance_valid(u2) and not (u2 as Unit).is_dead():
				ds.append((u2 as Unit).global_position.distance_to(t0.global_position) if is_instance_valid(t0) else -1.0)
		ds.sort()
		var s0: Unit = all[0]
		if is_instance_valid(s0):
			print("       дистанции до башни: мин %.1f мед %.1f; боец0 поз %s цель %s пад %.2f досяг %.2f путь %s" % [
				float(ds[0]), float(ds[ds.size() / 2]), str(s0.global_position), str(s0.attack_target),
				s0._target_pad, s0.reach(), str(s0.get("_atk_waypoint"))])
		var per_kind: Dictionary = {}
		for u3 in all:
			if not is_instance_valid(u3) or (u3 as Unit).is_dead():
				continue
			var k3: String = (u3 as Unit).stat_id
			var d3: float = (u3 as Unit).global_position.distance_to(t0.global_position) if is_instance_valid(t0) else -1.0
			per_kind[k3] = minf(float(per_kind.get(k3, 1e9)), d3)
		var sp0: Unit = all[0]
		var sid0: int = sp0.squad_id
		print("       мин. по родам %s | копейщик0: ring_done %s hold %s якорь %s auto %s" % [str(per_kind),
			str(sp0.get("_ring_done")), str(GameManager.squad_attack_hold(sid0)),
			str(GameManager.squad_attack_anchor(sid0)), str(sp0._auto_pilot)])
		print("       состояния %s | по башне %d, достают %d | ударов всего %d | HP башен %s" % [
			str(st_cnt), on_t, in_reach, hits, hp_s])
		if prof and w % 10 == 9:
			var rows: Array = _Opt.prof_report()
			for i in range(rows.size()):
				var r: Array = rows[i]
				if i >= 14 and not String(r[0]).begins_with("DBG"):
					continue
				print("      %-26s %8.1f мс  вызовов %7d  ср %.1f мкс  макс %d" % [String(r[0]),
					float(r[1]) / 1000.0, int(r[2]), float(r[3]), int(r[4])])
			_Opt.prof_reset()
		if alive_t == 0:
			break
	get_tree().quit(0)
