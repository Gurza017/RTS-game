extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД qa_army_front — ВСЯ АРМИЯ ИДЁТ ТОЛЬКО ВПЕРЁД (ТЗ 31.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба (скриншоты 30.10 22:46-22:48): армия целиком (копейщики, мечники,
## лучники, монахи) глубоким строем [2], [A] или ПКМ на пень/тролля — отряды
## разъезжаются вбок, разворачиваются и идут назад, растягиваются, после боя
## собираются криво.
## Сцена: 30 отрядов (12 копейщиков, 8 мечников, 7 лучников, 3 монаха по 20)
## протяжкой ПКМ в глубокий строй, враг впереди. Сценарии (cases=…):
##   f — [A]/ПКМ в точку в тумане за отрядами орды;   g — в точку на земле;
##   s — на пень (логово) с троллями;  n — на отряд гноллов;  t — на тролля.
## Приказ (orders=…): a — [A], r — ПКМ. Стойка (stances=…): d — «Защита», c — «вольно».
## ЗОНД «ПОШЁЛ НАЗАД»: раз в 0.5 с у каждого бойца смещение за 1 с вдоль оси
## «центр армии → цель»; назад > BACK_M, не сбит с ног и не в разлёте — отметка
## (род, состояние, стойка, [A], цель и точка хода позади/впереди, кто отдал
## приказ — Unit.dbg_order_src). Отряд «пошёл назад» — его центр за 2 с
## отошёл назад > SQ_BACK_M.
## Строй после боя (врагов в 45 м нет 10 с): боец «не на месте» — дальше
## OFF_SLOT_M от ближайшего места разметки; отряд кривой — таких > OFF_SHARE.
## Запуск: godot --headless --path . res://qa_army_front/Probe.tscn
##   [-- cases=fgsnt orders=ar stances=dc sec=90 trace=1 knob=…]

const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN
const KINDS := [["spearman", 12], ["warrior", 8], ["archer", 7], ["monk", 3]]
const MEN := 20
const AHEAD := 55.0
const BACK_M := 0.6
const SQ_BACK_M := 1.5
const OFF_SLOT_M := 0.9
const OFF_SHARE := 0.25
var main: Node = null
var _cases := "gsnt"
var _orders := "ar"
var _stances := "dc"
var _sec := 90.0
var _trace := false
var _track := false
var _start: Vector3
var results: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("cases="): _cases = s.substr(6)
		elif s.begins_with("orders="): _orders = s.substr(7)
		elif s.begins_with("stances="): _stances = s.substr(8)
		elif s.begins_with("sec="): _sec = float(s.substr(4))
		elif s == "trace=1": _trace = true
		elif s == "track=1": _track = true
	call_deferred("_run")
	get_tree().create_timer(5400.0).timeout.connect(func():
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
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead() and not (m as Unit).garrisoned:
			out.append(m)
	return out

func _spot() -> Vector3:
	for x in [-60.0, -90.0, -30.0, 30.0, 60.0, 0.0, -120.0]:
		for z in [-80.0, -50.0, -20.0, 10.0]:
			var ok := true
			var dx := -60.0
			while ok and dx <= 60.0:
				var dz := -25.0
				while dz <= AHEAD + 35.0:
					if GameManager.is_water(x + dx, z + dz) or GameManager.is_cliff(x + dx, z + dz):
						ok = false
						break
					dz += 5.0
				dx += 5.0
			if ok:
				return Vector3(x, 0, z)
	return Vector3(-60, 0, -50)

func _clear(c: Vector3, r: float) -> void:
	main._clear_trees(c, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(c) < r:
				if u is Unit and not (u as Unit).is_dead():
					(u as Unit).take_damage(1e12)
				else:
					u.queue_free()
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and (b as Node3D).global_position.distance_to(c) < r and not (b as Building).is_stronghold():
			b.queue_free()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	GameManager.pop_limit_enabled = false
	Unit.dbg_order_src = true
	for n2 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n2) and n2 is Unit and (n2 as Unit).faction != F:
			(n2 as Unit).set_tick(false)
	_start = _spot()
	print("  площадка (%.0f, %.0f)" % [_start.x, _start.z])
	for c in _cases:
		for o in _orders:
			for st in _stances:
				await _case(String(c), String(o), String(st))
	print("\n═════ СВОДКА qa_army_front ═════")
	for r in results:
		print("  " + String(r))
	print("=== QA_ARMY_FRONT DONE ===")
	get_tree().quit()

## Армия: протяжка ПКМ в глубокий строй [2] поперёк оси +Z, ждём, пока встанет
func _army() -> Array:
	var squads: Array = []
	var i := 0
	for kd in KINDS:
		for _k in range(int(kd[1])):
			var x: float = -50.0 + float(i % 10) * 11.0
			var z: float = -20.0 - float(i / 10) * 8.0
			squads.append(_squad(String(kd[0]), _start + Vector3(x, 0, z), MEN, F, 5))
			i += 1
	await pframes(5)
	var sm = main.selection_manager
	var all: Array = []
	for s in squads:
		all.append_array(s)
	sm.select_units(all)
	await pframes(2)
	sm.formation_mode = sm.FORM_DEEP
	sm._execute_line_formation(_start + Vector3(25, 0, 0), _start + Vector3(-25, 0, 0))
	for _w in range(40):
		await pframes(30)
		var moving := 0
		for u in all:
			if is_instance_valid(u) and (u as Unit).state == Unit.State.MOVING:
				moving += 1
		if moving == 0:
			break
	return squads

## Враг по сценарию. Ответ: [цель-узел или null, точка приказа, враги]
func _enemy(c: String) -> Array:
	var foes: Array = []
	var p0: Vector3 = _start + Vector3(0, 0, AHEAD)
	var tgt: Node3D = null
	match c:
		"f", "g":
			for j in range(4):
				foes.append_array(_squad("goblin_spearman", _start + Vector3((float(j) - 1.5) * 14.0, 0, AHEAD - 12.0), 16, G, 8))
			p0 = _start + Vector3(0, 0, AHEAD + 15.0)
		"s":
			var lair: Building = load("res://scripts/goblin/TrollLair.gd").new()
			lair.faction = G
			main.world_add(lair)
			lair.global_position = Vector3(p0.x, GameManager.get_terrain_height(p0.x, p0.z), p0.z)
			GameManager.register_lair(lair)
			tgt = lair
			for j2 in range(2):
				foes.append(_spawn("troll", p0 + Vector3((float(j2) - 0.5) * 14.0, 0, -7.0), G))
			for j3 in range(2):
				foes.append_array(_squad("gnoll", p0 + Vector3((float(j3) - 0.5) * 26.0, 0, -10.0), 10, G, 5))
			foes.append(lair)
		"n":
			for j4 in range(3):
				foes.append_array(_squad("gnoll", p0 + Vector3((float(j4) - 1.0) * 16.0, 0, 0), 12, G, 6))
			tgt = foes[int(foes.size() / 2)]
		"t":
			for j5 in range(2):
				foes.append(_spawn("troll", p0 + Vector3((float(j5) - 0.5) * 18.0, 0, 0), G))
			foes.append_array(_squad("goblin_spearman", p0 + Vector3(0, 0, 6.0), 16, G, 8))
			tgt = foes[0]
	return [tgt, p0, foes]

## Приказ ПКМ по врагу — тот же путь, что SelectionManager._handle_right_click
## (раскладка фронта, разлив у крупной цели, кольцо у постройки, стрелки — в
## указанную цель, замок)
func _rmb_attack(sm, target: Node3D) -> void:
	sm._squad_cmd()._cancel_for_selection(sm)
	var front: Dictionary = sm.frontline_targets(target)
	if target is Unit and (target as Unit).fine_ring_radius() > 0.0:
		var bs: Dictionary = sm._big_target_spread(target as Unit)
		for k in bs:
			front[k] = bs[k]
	if target is Building:
		var sp: Dictionary = sm._ring_squads_around(target as Building)
		for k2 in sp:
			front[k2] = sp[k2]
	for u in sm.selected_units:
		if not is_instance_valid(u) or not u.has_method("command_attack"):
			continue
		var sid: int = (u as Unit).squad_id
		var t = target
		if sid > 0 and front.has(sid):
			t = front[sid]
		if sid > 0 and GameManager.squad_type(sid) == "archer":
			t = target
		(u as Unit).command_attack(t, true, true, true)

func _case(c: String, o: String, st: String) -> void:
	var tag := "%s/%s/%s" % [{"f": "туман", "g": "земля", "s": "пень", "n": "гнолл", "t": "тролль"}[c], "[A]" if o == "a" else "ПКМ", "Защита" if st == "d" else "вольно"]
	print("\n═════ %s ═════" % tag)
	_clear(_start + Vector3(0, 0, AHEAD * 0.4), 110.0)
	GameManager.troll_lair = null
	await pframes(10)
	if GameManager.fog != null:
		GameManager.fog.enabled = c == "f"
	var squads: Array = await _army()
	var en: Array = _enemy(c)
	var tgt: Node3D = en[0]
	var dest: Vector3 = en[1]
	var foes: Array = en[2]
	await pframes(5)
	var sm = main.selection_manager
	var cmd = sm._squad_cmd()
	var all: Array = []
	for s in squads:
		all.append_array(s)
	sm.select_units(all)
	await pframes(2)
	sm.set_selection_stance("defense" if st == "d" else "attack")
	await pframes(3)
	if tgt != null:
		# ПКМ по врагу и [A] + клик по врагу (am_click_target) — одна ветка
		_rmb_attack(sm, tgt)
	elif o == "a":
		cmd.attack_move(sm, GameManager.land_target(dest))
	else:
		cmd._cancel_for_selection(sm)
		sm.march_selection_to(GameManager.land_target(dest))
	sm.clear_selection()
	# Ось марша: центр армии → точка приказа
	var c0: Vector3 = GameManager._centroid_of(_alive(all))
	var tp0: Vector3 = tgt.global_position if tgt != null else dest
	var ax := Vector2(tp0.x - c0.x, tp0.z - c0.z).normalized()
	var hist: Dictionary = {}
	var prev_p: Dictionary = {}
	var sq_hist: Array = []
	var spread_max: Array = []
	for _q in squads:
		sq_hist.append([])
		spread_max.append(0.0)
	var back_ids: Dictionary = {}
	var back_ev := 0
	var back_why: Dictionary = {}
	var sq_back: Dictionary = {}
	var quiet_t := 0.0
	var regroup: Array = []
	var t := 0.0
	while t < _sec:
		await pframes(30)
		t += 0.5
		var near_foes := 0
		var alive_foes: Array = _alive_foes(foes)
		var ac: Vector3 = GameManager._centroid_of(_alive(all))
		for f in alive_foes:
			if (f as Node3D).global_position.distance_to(ac) < 45.0:
				near_foes += 1
		for i in range(squads.size()):
			var a: Array = _alive(squads[i])
			if a.size() < 3:
				continue
			var cc: Vector3 = GameManager._centroid_of(a)
			var h: Array = sq_hist[i]
			h.append(cc)
			if h.size() > 4:
				h.pop_front()
				var d_back: float = Vector2(cc.x - (h[0] as Vector3).x, cc.z - (h[0] as Vector3).z).dot(ax)
				if d_back < -SQ_BACK_M:
					sq_back[i] = int(sq_back.get(i, 0)) + 1
			var ds: Array = []
			for m in a:
				var u := m as Unit
				var p: Vector3 = u.global_position
				ds.append(Vector2(p.x - cc.x, p.z - cc.z).length())
				var id: int = u.get_instance_id()
				var pv: Variant = prev_p.get(id)
				var p1s: Variant = hist.get(id)
				hist[id] = pv
				prev_p[id] = p
				if p1s == null:
					continue
				var mv := Vector2(p.x - (p1s as Vector3).x, p.z - (p1s as Vector3).z)
				if mv.dot(ax) < -BACK_M and not u.is_down() and u._fling_left <= 0.0:
					back_ev += 1
					back_ids[id] = true
					var why: String = _why(u, ax, cmd)
					back_why[why] = int(back_why.get(why, 0)) + 1
			ds.sort()
			spread_max[i] = maxf(float(spread_max[i]), float(ds[int(float(ds.size() - 1) * 0.9)]))
		if _track and int(t * 2.0) % 4 == 0:
			for ti in [0, 5, 13]:
				var ta: Array = _alive(squads[ti])
				if ta.is_empty():
					continue
				var tsid: int = (ta[0] as Unit).squad_id
				var tcc: Vector3 = GameManager._centroid_of(ta)
				var tsq: Dictionary = GameManager.squads.get(tsid, {})
				var tsl: Array = tsq.get("slots", [])
				var tsc := Vector3.ZERO
				for q in tsl.slice(0, ta.size()):
					tsc += q as Vector3
				tsc /= float(maxi(mini(tsl.size(), ta.size()), 1))
				var tcr: Vector3 = tsq.get("course", Vector3.ZERO)
				var tst: Dictionary = {}
				for m in ta:
					var k: String = Unit.State.keys()[(m as Unit).state]
					tst[k] = int(tst.get(k, 0)) + 1
				var tp1: Vector3 = tgt.global_position if tgt != null and is_instance_valid(tgt) else dest
				print("      [%d %s] t=%.0f центр→цель %.1f м, разметка→цель %.1f м, курс·ось %.2f, %s, замок %d" % [ti, GameManager.squad_type(tsid), t, Vector2(tp1.x - tcc.x, tp1.z - tcc.z).dot(ax), Vector2(tp1.x - tsc.x, tp1.z - tsc.z).dot(ax), Vector2(tcr.x, tcr.z).normalized().dot(ax) if tcr.length_squared() > 1e-4 else 0.0, str(tst), ta.filter(func(x): return (x as Unit).target_lock).size()])
		if _trace and int(t * 2.0) % 10 == 0:
			print("    t=%4.1f врагов %d (рядом %d), назад событий %d бойцов %d" % [t, alive_foes.size(), near_foes, back_ev, back_ids.size()])
		if near_foes == 0 and t > 10.0:
			quiet_t += 0.5
			if quiet_t >= 10.0 and regroup.is_empty():
				regroup = _regroup_quality(squads)
				if alive_foes.is_empty():
					break
		else:
			quiet_t = 0.0
	if regroup.is_empty():
		regroup = _regroup_quality(squads)
	var sb: Array = []
	for k3 in sq_back:
		var a3: Array = _alive(squads[int(k3)])
		sb.append("%s:%d" % [GameManager.squad_type((a3[0] as Unit).squad_id) if not a3.is_empty() else "?", int(sq_back[k3])])
	var ssum := 0.0
	for v in spread_max:
		ssum += float(v)
	var why_s: Array = []
	for k4 in back_why:
		why_s.append([int(back_why[k4]), k4])
	why_s.sort()
	why_s.reverse()
	var line := "%-22s назад: бойцов %3d, событий %4d, отрядов %2d | разброс p90 ср %.1f | после боя: кривых %d из %d | врагов %d за %.0f с" % [tag, back_ids.size(), back_ev, sq_back.size(), ssum / float(maxi(spread_max.size(), 1)), int(regroup[0]), (regroup[1] as Array).size(), _alive_foes(foes).size(), t]
	print("  " + line)
	print("    доли не на месте по отрядам: %s" % str(regroup[1]))
	print("    отряды назад: %s" % str(sb))
	for w in why_s.slice(0, 12):
		print("    назад ×%d: %s" % [int(w[0]), String(w[1])])
	results.append(line)
	for s2 in squads:
		for m2 in s2:
			if is_instance_valid(m2) and not (m2 as Unit).is_dead():
				(m2 as Unit).take_damage(1e12)
	for f2 in foes:
		if is_instance_valid(f2):
			if f2 is Unit and not (f2 as Unit).is_dead():
				(f2 as Unit).take_damage(1e12)
			elif f2 is Building:
				(f2 as Node).queue_free()
	await pframes(20)

func _alive_foes(foes: Array) -> Array:
	var out: Array = []
	for f in foes:
		if f == null or not is_instance_valid(f):
			continue
		if f is Unit and (f as Unit).is_dead():
			continue
		if f is Building and (f as Building).is_dead():
			continue
		out.append(f)
	return out

## Почему идёт назад: род, состояние, стойка, [A], цель и точка хода, источник
func _why(u: Unit, ax: Vector2, cmd) -> String:
	var sn: String = Unit.State.keys()[u.state]
	var tg := "нет"
	var t = u.attack_target
	if t != null and is_instance_valid(t):
		var tp: Vector3 = (t as Node3D).global_position
		var rel := Vector2(tp.x - u.global_position.x, tp.z - u.global_position.z)
		tg = "позади" if rel.dot(ax) < 0.0 else "впереди"
	var am: String = "A" if cmd.is_attack_moving(u.squad_id) else "-"
	var gl := ""
	if u.dbg_goal.x != INF:
		var rg := Vector2(u.dbg_goal.x - u.global_position.x, u.dbg_goal.z - u.global_position.z)
		gl = " ход:%s" % ("позади" if rg.dot(ax) < 0.0 else "впереди")
	return "%s %s %s %s цель:%s%s%s ← %s" % [u.stat_id, sn, u.stance, am, tg, " замок" if u.target_lock else "", gl, u.dbg_src]

## Строй после боя: [кривых отрядов, доли «не на месте» по отрядам]
func _regroup_quality(squads: Array) -> Array:
	var bad := 0
	var rat: Array = []
	for s in squads:
		var a: Array = _alive(s)
		if a.size() < 4:
			continue
		var sq: Variant = GameManager.squads.get((a[0] as Unit).squad_id)
		var slots: Array = (sq as Dictionary).get("slots", []) if sq != null else []
		if slots.is_empty():
			bad += 1
			rat.append(1.0)
			continue
		var off := 0
		for m in a:
			var p: Vector3 = (m as Unit).global_position
			var best := INF
			for sl in slots:
				best = minf(best, Vector2(p.x - (sl as Vector3).x, p.z - (sl as Vector3).z).length())
			if best > OFF_SLOT_M:
				off += 1
		var k: float = float(off) / float(a.size())
		rat.append(snappedf(k, 0.05))
		if k > OFF_SHARE:
			bad += 1
	rat.sort()
	return [bad, rat]
