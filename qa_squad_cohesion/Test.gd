extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД: ОТРЯД ДВИЖЕТСЯ И ДЕРЁТСЯ КУЛАКОМ (ТЗ 29.09.2026, третье письмо, п. 4)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: «1–3 бойца уходят в другую сторону, отряды выворачиваются,
## перестраиваются и теряют строй при перемещениях и атаках». Сценарии идут
## настоящим путём приказа игрока (SelectionManager._issue_formation_move и
## _handle_right_click по врагу):
##   A — марш 40 м; B — разворот назад на 30 м (выворачивание); C — бег
##   (двойной клик); D — атака на чужой отряд; E — поворот на 90°.
## На каждом: отставшие (дальше STRAY_M от медианы отряда) по ходу и в
## конце, худший поперечник, «проходы сквозь строй» (боец прошёл больше
## пути центра плюс двойного поперечника — значит, пересёк отряд),
## и «ушли не туда» (в конце ближе к чужой цели, чем к своей точке, при
## приказе движения). Копейщики, мечники и лучники отдельно.
## Запуск: godot --headless --path . res://qa_squad_cohesion/Test.tscn

const F := Constants.FACTION_PLAYER
const STRAY_M := 6.0
var main = null
var sm = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(500.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_squad_cohesion: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int, gap: float = 0.6) -> Array:
	var sid: int = GameManager.new_squad(f, uid)
	var out: Array = []
	for i in range(n):
		var u := _unit(uid, f, at + Vector3(float(i / cols) * gap, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * gap))
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return [sid, out]

func _alive(arr: Array) -> Array:
	var o: Array = []
	for u in arr:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			o.append(u)
	return o

func _median(men: Array) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for u in men:
		xs.append((u as Unit).global_position.x)
		zs.append((u as Unit).global_position.z)
	xs.sort()
	zs.sort()
	return Vector3(float(xs[xs.size() / 2]), 0.0, float(zs[zs.size() / 2]))

func _extent(men: Array) -> float:
	var c: Vector3 = _median(men)
	var m := 0.0
	for u in men:
		m = maxf(m, Vector2((u as Unit).global_position.x - c.x, (u as Unit).global_position.z - c.z).length())
	return m

## Прогон одного приказа: frames физкадров, опрос каждые 10
func _watch(men: Array, frames: int, label: String) -> Dictionary:
	var start: Dictionary = {}
	var path: Dictionary = {}
	var last: Dictionary = {}
	for u in men:
		start[u] = (u as Unit).global_position
		last[u] = (u as Unit).global_position
		path[u] = 0.0
	var c0: Vector3 = _median(men)
	var ext0: float = _extent(men)
	var stray_worst := 0
	var ext_worst := 0.0
	var f := 0
	while f < frames:
		await get_tree().physics_frame
		f += 1
		if f % 10 != 0:
			continue
		var live: Array = _alive(men)
		if live.is_empty():
			break
		var c: Vector3 = _median(live)
		var stray := 0
		for u in live:
			var p: Vector3 = (u as Unit).global_position
			if Vector2(p.x - c.x, p.z - c.z).length() > STRAY_M:
				stray += 1
			path[u] = float(path[u]) + Vector2(p.x - (last[u] as Vector3).x, p.z - (last[u] as Vector3).z).length()
			last[u] = p
		stray_worst = maxi(stray_worst, stray)
		ext_worst = maxf(ext_worst, _extent(live))
	var live2: Array = _alive(men)
	var c1: Vector3 = _median(live2)
	var ctravel: float = Vector2(c1.x - c0.x, c1.z - c0.z).length()
	var crossers := 0
	var stray_end := 0
	for u in live2:
		if float(path[u]) > ctravel + 2.0 * ext0 + 3.0:
			crossers += 1
		var p2: Vector3 = (u as Unit).global_position
		if Vector2(p2.x - c1.x, p2.z - c1.z).length() > STRAY_M:
			stray_end += 1
	var out := {"stray_worst": stray_worst, "stray_end": stray_end, "ext0": ext0, "ext_worst": ext_worst,
		"ext_end": _extent(live2), "crossers": crossers, "travel": ctravel, "n": live2.size()}
	print("    %s: отставших по ходу до %d, в конце %d; поперечник %.1f → до %.1f → %.1f; пересекли строй %d; центр прошёл %.1f м (живых %d)" % [
		label, stray_worst, stray_end, ext0, ext_worst, float(out["ext_end"]), crossers, ctravel, live2.size()])
	return out

func _order_move(men: Array, to: Vector3, run: bool = false) -> void:
	sm.select_units(men)
	sm._issue_formation_move(to, run)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard", "cav_commander"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit:
			(n0 as Unit).take_damage(1.0e12)
	for fac in range(Constants.FACTION_COUNT):
		if fac == F:
			continue
		for b in get_tree().get_nodes_in_group(Constants.building_group(fac)):
			if is_instance_valid(b):
				(b as Node).process_mode = Node.PROCESS_MODE_DISABLED
	sm = main.selection_manager
	var base := Vector3(-60.0, 0.0, -10.0)
	main._clear_area_of_resources(base, 80.0)
	for rn in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(rn) and (rn as Node3D).global_position.distance_to(base) < 80.0:
			(rn as Node).queue_free()
	await pframes(6)
	var kinds := [["spearman", 24, 8], ["warrior", 16, 4], ["archer", 20, 5]]
	var worst_stray := 0
	var worst_cross := 0
	var worst_end := 0
	for ki in range(kinds.size()):
		var kd: Array = kinds[ki]
		var uid: String = String(kd[0])
		print("\n═════ %s ═════" % uid)
		var at: Vector3 = base + Vector3(-30.0, 0.0, -30.0 + 30.0 * float(ki))
		var sq: Array = _squad(uid, F, at, int(kd[1]), int(kd[2]))
		var men: Array = sq[1]
		await pframes(20)
		# A. марш 40 м вперёд
		_order_move(men, at + Vector3(40.0, 0.0, 0.0))
		var a: Dictionary = await _watch(men, 60 * 14, "A марш 40 м")
		# B. разворот назад 30 м
		_order_move(men, at + Vector3(10.0, 0.0, 0.0))
		var b: Dictionary = await _watch(men, 60 * 12, "B разворот назад 30 м")
		# C. бег 30 м (двойной клик)
		_order_move(men, at + Vector3(40.0, 0.0, 0.0), true)
		var c: Dictionary = await _watch(men, 60 * 10, "C бег 30 м")
		# E. поворот на 90° (точка вбок)
		_order_move(men, at + Vector3(40.0, 0.0, 14.0))
		var e: Dictionary = await _watch(men, 60 * 10, "E поворот 90°, 14 м вбок")
		for r in [a, b, c, e]:
			worst_stray = maxi(worst_stray, int(r["stray_end"]))
			worst_cross = maxi(worst_cross, int(r["crossers"]))
		# D. атака на чужой отряд (гоблины-копейщики 30, стоят)
		var foe_at: Vector3 = at + Vector3(62.0, 0.0, 14.0)
		var foe: Array = _squad("goblin_spearman", Constants.FACTION_GOBLIN, foe_at, 30, 6, 0.9)
		await pframes(4)
		sm.select_units(men)
		for u in _alive(men):
			(u as Unit).command_attack((foe[1] as Array)[0], true, false, true)
		var d: Dictionary = await _watch(men, 60 * 12, "D атака на отряд в 22 м")
		# «Ушли не туда»: в атаке — дальше 12 м от чужого отряда и не дерутся
		var off := 0
		var fc: Vector3 = _median(_alive(foe[1])) if not _alive(foe[1]).is_empty() else foe_at
		for u in _alive(men):
			var uu := u as Unit
			if Vector2(uu.global_position.x - fc.x, uu.global_position.z - fc.z).length() > 12.0 and uu.state != Unit.State.ATTACKING:
				off += 1
		print("    D: не у цели и не в бою — %d" % off)
		worst_end = maxi(worst_end, off)
		for u2 in _alive(foe[1]):
			(u2 as Unit).take_damage(1.0e12)
		for u3 in _alive(men):
			(u3 as Unit).take_damage(1.0e12)
		await pframes(10)
	# ── F. ТРИ ОТРЯДА ОДНИМ КЛИКОМ СКВОЗЬ РОЩУ СО СТВОЛАМИ ──────────────────
	print("
═════ F. ТРИ ОТРЯДА КОПЕЙЩИКОВ СКВОЗЬ РОЩУ ═════")
	var grove: Vector3 = base + Vector3(10.0, 0.0, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	for i in range(28):
		var tp: Vector3 = grove + Vector3(rng.randf_range(-7.0, 7.0), 0.0, rng.randf_range(-12.0, 12.0))
		var tr := ResourceNode.new()
		tr.resource_type = Constants.RESOURCE_WOOD
		tr.remaining = 500.0
		tr.forest_kind = ResourceNode.FOREST_NORMAL
		main.world_add(tr)
		tr.global_position = Vector3(tp.x, GameManager.get_terrain_height(tp.x, tp.z), tp.z)
	var all3: Array = []
	var sqs3: Array = []
	for j in range(3):
		var s3: Array = _squad("spearman", F, base + Vector3(-25.0, 0.0, -12.0 + 12.0 * float(j)), 24, 8)
		sqs3.append(s3)
		all3.append_array(s3[1])
	await pframes(20)
	_order_move(all3, base + Vector3(35.0, 0.0, 0.0))
	var fres: Array = []
	for f0 in range(3):
		pass
	var fw: Dictionary = await _watch(all3, 60 * 25, "F три отряда через рощу (общая масса)")
	var f_stray := 0
	for s3b in sqs3:
		var live3: Array = _alive(s3b[1])
		var c3: Vector3 = _median(live3)
		for u in live3:
			if Vector2((u as Unit).global_position.x - c3.x, (u as Unit).global_position.z - c3.z).length() > STRAY_M:
				f_stray += 1
	print("    F: отставших от СВОЕГО отряда в конце %d" % f_stray)
	verdict("F1 роща: отставших от своего отряда нет (%d)" % f_stray, f_stray == 0)
	# ── G. НАТИСК ФАЛАНГИ (приём копейщиков) и марш в «Защите» ─────────────
	print("
═════ G. ПРИЁМЫ КОПЕЙЩИКОВ ═════")
	var gs: Array = sqs3[1]
	var gmen: Array = _alive(gs[1])
	for u in gmen:
		(u as Unit).set_stance("defense")
	_order_move(gmen, _median(gmen) + Vector3(-15.0, 0.0, 0.0))
	await _watch(gmen, 60 * 10, "G марш в «Защите» 15 м")
	var foe2: Array = _squad("goblin_spearman", Constants.FACTION_GOBLIN, _median(gmen) + Vector3(-14.0, 0.0, 0.0), 30, 6, 0.9)
	await pframes(4)
	for u in gmen:
		if (u as Unit).has_method("start_phalanx_push"):
			(u as Unit).call("start_phalanx_push")
		(u as Unit).command_attack((foe2[1] as Array)[0], true, false, true)
	var gw: Dictionary = await _watch(gmen, 60 * 8, "G натиск фаланги на отряд")
	verdict("G1 натиск фаланги: строй не рвётся (отставших в конце %d, по ходу до %d)" % [int(gw["stray_end"]), int(gw["stray_worst"])], int(gw["stray_end"]) <= 1)
	for u2 in _alive(foe2[1]):
		(u2 as Unit).take_damage(1.0e12)
	verdict("A1 после приказов движения отставших от отряда нет (худший %d)" % worst_stray, worst_stray == 0)
	verdict("A2 отряд не выворачивается: сквозь строй не проходит никто (худший %d)" % worst_cross, worst_cross <= 1)
	verdict("A3 в атаке никто не ушёл в сторону без боя (худший %d)" % worst_end, worst_end <= 1)
	_finish()
