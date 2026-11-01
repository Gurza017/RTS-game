extends Node
## ЗОНД qa_am_defense/Live — тот же приказ на автосейве владельца (30.10 22:44,
## за минуту до скриншотов «отряды разъезжаются у пня»). Сцена поднимается
## заново на каждый прогон; меняется только стойка отрядов перед приказом.
## Отряды — все рукопашные отряды игрока в R_PICK от пня (логова троллей).
## Приказ: [A] в точку пня (mode=am) или ПКМ по ближайшему троллю (mode=rmb).
## Раз в 0.5 с: разброс p90, доля пятящихся (сдвиг ОТ пня > BACK_M за 0.5 с),
## боковой увод центров поперёк оси «центр группы → пень».
## Вердиктов нет. Запуск:
##   godot --headless --path . res://qa_am_defense/Live.tscn -- [mode=am|rmb sec=60 cases=sad]
##   cases: s — стойки как в сейве, a — все «вольно», d — все «Защита»,
##   D — [A], через 1 с «Защита» на ходу
const _Opt := preload("res://scripts/perf_config.gd")
const R_PICK := 500.0
const BACK_M := 0.4
var main: Node = null
var _mode := "am"
var _sec := 60.0
var _cases := "ad"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("mode="):
			_mode = s.substr(5)
		elif s.begins_with("sec="):
			_sec = float(s.substr(4))
		elif s.begins_with("cases="):
			_cases = s.substr(6)
	call_deferred("_run")
	get_tree().create_timer(1500.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился")
		get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.get_32()
	f.get_32()
	f.get_32()
	var d: Variant = f.get_var(false)
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _run() -> void:
	var st: Dictionary = _read("user://autosave.tts")
	if st.is_empty():
		print("  автосейва нет — зонд не запущен")
		get_tree().quit()
		return
	for c in _cases:
		await _case(st.duplicate(true), String(c))
	print("=== QA_AM_DEFENSE LIVE DONE ===")
	get_tree().quit()

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead() and not (m as Unit).garrisoned:
			out.append(m)
	return out

func _members(sid: int) -> Array:
	var sq: Variant = GameManager.squads.get(sid)
	return ((sq as Dictionary)["members"] as Array).duplicate() if sq != null else []

func _case(st: Dictionary, c: String) -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
		await pframes(10)
	GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(90)
	var pc: Array = []
	for u0 in GameManager._live_units:
		if u0 != null and is_instance_valid(u0) and (u0 as Unit).faction == Constants.FACTION_PLAYER and (u0 as Unit).squad_id > 0 and not (u0 as Unit).garrisoned:
			pc.append(u0)
	var army_c: Vector3 = GameManager._centroid_of(pc) if not pc.is_empty() else Vector3.ZERO
	print("  [%s] логов %d, troll_lair %s, руин %d, игрока бойцов %d в %s" % [c, GameManager.troll_lairs.size(),
		str(GameManager.troll_lair), get_tree().get_nodes_in_group("ruins").size(), pc.size(), str(army_c)])
	var lair = GameManager.nearest_lair(army_c)
	var lp: Vector3 = Vector3.INF
	if lair != null and is_instance_valid(lair):
		lp = (lair as Node3D).global_position
	else:
		for r in get_tree().get_nodes_in_group("ruins"):
			if String(r.get_meta("ruin_building_id", "")) == "troll_lair":
				var rp: Vector3 = (r as Node3D).global_position
				if not lp.is_finite() or rp.distance_to(army_c) < lp.distance_to(army_c):
					lp = rp
	if not lp.is_finite():
		print("  [%s] ни логова, ни руины пня" % c)
		return
	print("  [%s] пень в %s, до армии %.0f м" % [c, str(lp), lp.distance_to(army_c)])
	var sids: Array = []
	var stances: Dictionary = {}
	for sid in GameManager.squads:
		var sq: Dictionary = GameManager.squads[sid]
		if int(sq.get("faction", -1)) != Constants.FACTION_PLAYER:
			continue
		var tp: String = String(sq.get("type", ""))
		if not (tp in ["spearman", "warrior"]):
			continue
		var a: Array = _alive(sq["members"])
		if a.size() < 5:
			continue
		var cc: Vector3 = GameManager._centroid_of(a)
		if Vector2(cc.x - army_c.x, cc.z - army_c.z).length() > R_PICK:
			continue
		sids.append(int(sid))
		var s0: String = String((a[0] as Unit).stance)
		stances[s0] = int(stances.get(s0, 0)) + 1
	var trolls: Array = []
	for u in GameManager._live_units:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead() and (u as Unit).stat_id == "troll":
			trolls.append(u)
	var men: Array = []
	for s1 in sids:
		men.append_array(_alive(_members(int(s1))))
	print("\n═════ [%s] режим %s: отрядов у пня %d (бойцов %d), стойки в сейве %s, троллей %d ═════" % [
		c, _mode, sids.size(), men.size(), str(stances), trolls.size()])
	if sids.is_empty():
		return
	var sm = main.selection_manager
	sm.select_units(men)
	await pframes(2)
	if c == "a":
		sm.set_selection_stance("attack")
	elif c == "d":
		sm.set_selection_stance("defense")
	await pframes(5)
	var gc: Vector3 = GameManager._centroid_of(men)
	if _mode == "rmb" and not trolls.is_empty():
		var victim: Unit = trolls[0]
		for t in trolls:
			if (t as Node3D).global_position.distance_to(gc) < victim.global_position.distance_to(gc):
				victim = t
		var front: Dictionary = sm.frontline_targets(victim)
		if victim.fine_ring_radius() > 0.0:
			var bs: Dictionary = sm._big_target_spread(victim)
			for k in bs:
				front[k] = bs[k]
		for u in men:
			(u as Unit).command_attack(front.get((u as Unit).squad_id, victim), true, true, true)
	else:
		sm._squad_cmd().attack_move(sm, GameManager.land_target(lp))
	if c == "D":
		# Порядок владельца, вариант 2: сначала [A], потом «Защита» на ходу
		await pframes(60)
		sm.set_selection_stance("defense")
	sm.clear_selection()
	var ax := Vector2(lp.x - gc.x, lp.z - gc.z).normalized()
	var side := Vector2(-ax.y, ax.x)
	var c0: Dictionary = {}
	for s2 in sids:
		var a2: Array = _alive(_members(int(s2)))
		if not a2.is_empty():
			c0[s2] = GameManager._centroid_of(a2)
	var prev: Dictionary = {}
	var t := 0.0
	var back_sum := 0.0
	var back_peak := 0.0
	var r_sum := 0.0
	var r_n := 0
	var r_max: Dictionary = {}
	var lat_max: Dictionary = {}
	var samples := 0
	while t < _sec:
		await pframes(30)
		t += 0.5
		var back := 0
		var tot := 0
		for s3 in sids:
			var a3: Array = _alive(_members(int(s3)))
			if a3.size() < 3:
				continue
			var cc3: Vector3 = GameManager._centroid_of(a3)
			var ds: Array = []
			for m in a3:
				var p: Vector3 = (m as Unit).global_position
				ds.append(Vector2(p.x - cc3.x, p.z - cc3.z).length())
				var id: int = (m as Unit).get_instance_id()
				var pv: Variant = prev.get(id)
				prev[id] = p
				if pv == null:
					continue
				tot += 1
				var d0: float = Vector2((pv as Vector3).x - lp.x, (pv as Vector3).z - lp.z).length()
				var d1: float = Vector2(p.x - lp.x, p.z - lp.z).length()
				if d1 - d0 > BACK_M:
					back += 1
			ds.sort()
			var r: float = float(ds[int(float(ds.size() - 1) * 0.9)])
			r_sum += r
			r_n += 1
			r_max[s3] = maxf(float(r_max.get(s3, 0.0)), r)
			if c0.has(s3):
				var dv := Vector2(cc3.x - (c0[s3] as Vector3).x, cc3.z - (c0[s3] as Vector3).z)
				lat_max[s3] = maxf(float(lat_max.get(s3, 0.0)), absf(dv.dot(side)))
		var bf: float = float(back) / float(maxi(tot, 1))
		back_sum += bf
		back_peak = maxf(back_peak, bf)
		samples += 1
		if int(t * 2.0) % 10 == 0:
			print("    t=%4.1f назад %3.0f%% разброс ср. %.1f м" % [t, bf * 100.0, r_sum / float(maxi(r_n, 1))])
	var rm: Array = []
	for k2 in r_max:
		rm.append(snappedf(float(r_max[k2]), 0.1))
	rm.sort()
	var lm: Array = []
	for k3 in lat_max:
		lm.append(snappedf(float(lat_max[k3]), 0.1))
	lm.sort()
	print("  [%s] разброс p90: средний %.2f м, макс по отрядам %s" % [c, r_sum / float(maxi(r_n, 1)), str(rm)])
	print("  [%s] боковой увод: %s" % [c, str(lm)])
	print("  [%s] пятятся от пня: пик %.0f%%, среднее %.1f%%" % [c, back_peak * 100.0, back_sum / float(maxi(samples, 1)) * 100.0])
