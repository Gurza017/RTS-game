extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД qa_am_defense — [A] ИЗ «ЗАЩИТЫ» ПРОТИВ [A] ИЗ «ВОЛЬНО» (скриншоты 30.10 22:46)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: отряды в [S], посланные [A] на пень с троллями, расходятся в стороны,
## пятятся и растягиваются; в «вольно» тот же приказ идёт ровно. Сцена одна и
## та же, меняется только стойка отрядов до клика:
##   6 отрядов копейщиков по 24 в ряд, впереди на LINE_Z два тролля и три
##   отряда орды (живые, дерутся), [A] на MARCH вперёд.
## Раз в 0.5 с: разброс отряда (p90 расстояния до медианы), доля бойцов,
## сдвинувшихся НАЗАД по оси марша больше BACK_M, боковой увод центров,
## стойка отрядов и режим [A]. Вердиктов нет — числа для сравнения.
## Запуск: godot --headless --path . res://qa_am_defense/Probe.tscn [-- only=ad trace=1 knob=…]

const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN
const N_SQ := 6
const SQ_GAP := 11.0
const LINE_Z := 35.0
const MARCH := 60.0
const BACK_M := 0.4
var RUN_SEC := 70.0
var _dest_z := MARCH
var _rmb := false

var main: Node = null
var _only := "ad"
var _trace := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
		if s == "trace=1":
			_trace = true
		if s == "rmb=1":
			_rmb = true
		if s == "dest=line":
			_dest_z = LINE_Z
		if s.begins_with("sec="):
			RUN_SEC = float(s.substr(4))
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился")
		get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3, fac: int) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int, cols: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3((float(k % cols) - float(cols - 1) * 0.5) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _spot() -> Vector3:
	for x in [-80.0, -110.0, -50.0, 40.0, 70.0, -140.0, 0.0]:
		for z in [-90.0, -60.0, -30.0, 0.0]:
			var ok := true
			var dx := -45.0
			while ok and dx <= 45.0:
				var dz := -10.0
				while dz <= MARCH + 15.0:
					if GameManager.is_water(x + dx, z + dz) or GameManager.is_cliff(x + dx, z + dz):
						ok = false
						break
					dz += 5.0
				dx += 5.0
			if ok:
				return Vector3(x, 0, z)
	return Vector3(-80, 0, -60)

func _clear(c: Vector3, r: float) -> void:
	main._clear_trees(c, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(c) < r:
				u.queue_free()
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and (b as Node3D).global_position.distance_to(c) < r \
				and not (b as Building).is_stronghold():
			b.queue_free()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.troll_lair = null
	GameManager.pop_limit_enabled = false
	if "a" in _only:
		await _case(false)
	if "d" in _only:
		await _case(true)
	print("=== QA_AM_DEFENSE PROBE DONE ===")
	get_tree().quit()

func _p90_radius(men: Array) -> float:
	var a: Array = _alive(men)
	if a.size() < 3:
		return 0.0
	var c: Vector3 = GameManager._centroid_of(a)
	var ds: Array = []
	for m in a:
		ds.append(Vector2((m as Unit).global_position.x - c.x, (m as Unit).global_position.z - c.z).length())
	ds.sort()
	return float(ds[int(float(ds.size() - 1) * 0.9)])

func _case(defense: bool) -> void:
	var tag: String = "ЗАЩИТА" if defense else "ВОЛЬНО"
	print("\n═════ [A] из стойки %s ═════" % tag)
	var start: Vector3 = _spot()
	_clear(start + Vector3(0, 0, MARCH * 0.5), 90.0)
	await pframes(5)
	var squads: Array = []
	var sids: Array = []
	for k in range(N_SQ):
		var x: float = (float(k) - float(N_SQ - 1) * 0.5) * SQ_GAP
		var men: Array = _squad("spearman", start + Vector3(x, 0, 0), 24, F, 8)
		squads.append(men)
		sids.append(int((men[0] as Unit).squad_id))
	var foes: Array = []
	for j in range(3):
		foes.append_array(_squad("goblin_spearman", start + Vector3((float(j) - 1.0) * 14.0, 0, LINE_Z), 16, G, 8))
	for j2 in range(2):
		var tr := _spawn("troll", start + Vector3((float(j2) - 0.5) * 20.0, 0, LINE_Z + 6.0), G)
		foes.append(tr)
	await pframes(10)
	var sm = main.selection_manager
	var cmd = sm._squad_cmd()
	var all: Array = []
	for s in squads:
		all.append_array(s)
	sm.select_units(all)
	await pframes(2)
	if defense:
		sm.set_selection_stance("defense")
		await pframes(5)
	var st_before: String = String((squads[0][0] as Unit).stance)
	var restores0: int = int(cmd.stance_restores)
	if _rmb:
		# ПКМ по троллю — путь _handle_right_click: раскладка по фронту и
		# разлив у крупной цели, затем command_attack с замком
		var victim: Unit = foes[foes.size() - 1]
		var front: Dictionary = sm.frontline_targets(victim)
		if victim.fine_ring_radius() > 0.0:
			var bs: Dictionary = sm._big_target_spread(victim)
			for k2 in bs:
				front[k2] = bs[k2]
		for u in all:
			var t3: Node3D = front.get((u as Unit).squad_id, victim)
			(u as Unit).command_attack(t3, true, true, true)
	else:
		cmd.attack_move(sm, GameManager.land_target(start + Vector3(0, 0, _dest_z)))
	sm.clear_selection()
	var x0: Array = []
	for s0 in squads:
		x0.append(GameManager._centroid_of(_alive(s0)).x)
	var prev: Dictionary = {}
	var max_r: Array = []
	var lat: Array = []
	var back_peak := 0.0
	var back_sum := 0.0
	var samples := 0
	var r_sum := 0.0
	var am_off_t: Array = []
	var def_back_t: Array = []
	for _k in range(N_SQ):
		max_r.append(0.0)
		lat.append(0.0)
		am_off_t.append(-1.0)
		def_back_t.append(-1.0)
	var t := 0.0
	while t < RUN_SEC:
		await pframes(30)
		t += 0.5
		var back := 0
		var tot := 0
		var row := ""
		for i in range(N_SQ):
			var a: Array = _alive(squads[i])
			if a.is_empty():
				continue
			var r: float = _p90_radius(squads[i])
			max_r[i] = maxf(float(max_r[i]), r)
			r_sum += r
			var c: Vector3 = GameManager._centroid_of(a)
			lat[i] = maxf(float(lat[i]), absf(c.x - float(x0[i])))
			if float(am_off_t[i]) < 0.0 and not cmd.is_attack_moving(int(sids[i])):
				am_off_t[i] = t
			if float(def_back_t[i]) < 0.0 and defense and String((a[0] as Unit).stance) == "defense":
				def_back_t[i] = t
			for m in a:
				var id: int = (m as Unit).get_instance_id()
				var p: Vector3 = (m as Unit).global_position
				var pv: Variant = prev.get(id)
				prev[id] = p
				if pv == null:
					continue
				tot += 1
				if p.z - (pv as Vector3).z < -BACK_M:
					back += 1
			row += " [%.0f,%.0f r%.1f %s%s]" % [c.x - start.x, c.z - start.z, r,
				"A" if cmd.is_attack_moving(int(sids[i])) else "-",
				"S" if String((a[0] as Unit).stance) == "defense" else "c"]
		samples += 1
		var bf: float = float(back) / float(maxi(tot, 1))
		back_peak = maxf(back_peak, bf)
		back_sum += bf
		if _trace and int(t * 2.0) % 20 == 0 and t >= 40.0:
			_diag(squads, foes)
		if _trace and int(t * 2.0) % 4 == 0:
			print("    t=%4.1f назад %3.0f%% врагов %d |%s" % [t, bf * 100.0, _alive(foes).size(), row])
		if _alive(foes).is_empty() and t > 20.0 and _all_idle(squads):
			break
	var rr: Array = []
	for v in max_r:
		rr.append(snappedf(float(v), 0.1))
	var ll: Array = []
	for v2 in lat:
		ll.append(snappedf(float(v2), 0.1))
	print("  %s: стойка до клика %s; врагов осталось %d из %d за %.1f с" % [tag, st_before, _alive(foes).size(), foes.size(), t])
	print("  %s: разброс p90 по отрядам макс %s, средний %.2f м" % [tag, str(rr), r_sum / float(maxi(samples * N_SQ, 1))])
	print("  %s: боковой увод центров %s" % [tag, str(ll)])
	print("  %s: пятятся (сдвиг назад > %.1f м за 0.5 с) — пик %.0f%%, среднее %.1f%%" % [tag, BACK_M, back_peak * 100.0, back_sum / float(maxi(samples, 1)) * 100.0])
	print("  %s: [A] снят на секунде %s; стойка «Защита» вернулась на %s; возвратов %d" % [tag, str(am_off_t), str(def_back_t), int(cmd.stance_restores) - restores0])
	for s2 in squads:
		for m2 in s2:
			if is_instance_valid(m2):
				(m2 as Unit).queue_free()
	for f2 in foes:
		if is_instance_valid(f2):
			(f2 as Node).queue_free()
	await pframes(10)

func _all_idle(squads: Array) -> bool:
	for s in squads:
		for m in _alive(s):
			if (m as Unit).state != Unit.State.IDLE:
				return false
	return true

## Разбор: кто из врагов жив, состояния бойцов, цели, сброс отбрасыванием
func _diag(squads: Array, foes: Array) -> void:
	var fk: Dictionary = {}
	for f in _alive(foes):
		var k: String = (f as Unit).stat_id
		fk[k] = int(fk.get(k, 0)) + 1
	print("      живы враги: %s" % str(fk))
	for i in range(squads.size()):
		var a: Array = _alive(squads[i])
		if a.is_empty():
			continue
		var st: Dictionary = {}
		var tg := 0
		var lock := 0
		var fl := 0
		var far := 0.0
		var c: Vector3 = GameManager._centroid_of(a)
		var nearest_foe := 1e9
		for m in a:
			var u := m as Unit
			var sn: String = Unit.State.keys()[u.state]
			st[sn] = int(st.get(sn, 0)) + 1
			if u.attack_target != null and is_instance_valid(u.attack_target):
				tg += 1
			if u.target_lock:
				lock += 1
			if u._fling_left > 0.0:
				fl += 1
			far = maxf(far, Vector2(u.global_position.x - c.x, u.global_position.z - c.z).length())
		for f2 in _alive(foes):
			nearest_foe = minf(nearest_foe, c.distance_to((f2 as Node3D).global_position))
		print("      отряд %d: %s цель %d замок %d летят %d дальний %.1f м, ближ. враг %.1f м, в бою %s, стойка %s" % [
			i, str(st), tg, lock, fl, far, nearest_foe,
			str(GameManager.squad_in_combat((a[0] as Unit).squad_id)), String((a[0] as Unit).stance)])
