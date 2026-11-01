extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_am_front_guard — [A] НЕ УХОДИТ К ВОЛНЕ СБОКУ (ТЗ 30.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Скриншот 01:29 (партия 30.10, 27:23): армия в [A] бьёт линию орды, а часть
## отрядов срывается к волне, проходящей сбоку. Причина — раскладка фронта
## (GameManager.front_pairs): ВСЕ чужие отряды в радиусе «габарит группы +
## досягаемость + 6 м» раздаются нашим по порядку вдоль оси фронта, и
## крайний отряд получал крайнего врага, не проверяя ни сектора, ни дальности.
##   A — 8 отрядов копейщиков идут [A] на +Z; линия орды (3 отряда) на пути
##       средних отрядов; волна (2 отряда) справа, вне сектора ±60° крайнего
##       отряда, но в радиусе раскладки. Ни один отряд не уходит к волне
##       (увод центра вправо ≤ LAT_MAX), волна не тронута, раскладка
##       отклонила пару (front_rejects > 0)
##   A0 — то же с ручкой am_front_guard выключенной: жалоба воспроизводится
## Все враги стоят (тик снят) — замер про выбор цели, а не про встречный бой.
## Запуск: godot --headless --path . res://qa_am_front_guard/Test.tscn [-- only=a0 trace=1]

const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

const LAT_MAX := 8.0
const MARCH := 70.0
const N_SQ := 8
const SQ_GAP := 10.0
const LINE_Z := 30.0
## Волна сбоку: от правого отряда (dx, dz) — вне сектора, в радиусе раскладки
const BAND_DX := 9.0
const BAND_DZ := LINE_Z - 2.0

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "a0"
var _trace := false
var _done := false
var _log: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		if String(a) == "trace=1":
			_trace = true
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_am_front_guard: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3, fac: int = F) -> Unit:
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

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _centre(men: Array) -> Vector3:
	var a: Array = _alive(men)
	if a.is_empty():
		return Vector3.INF
	return GameManager._centroid_of(a)

## Сухая ровная площадка под армию, линию и волну
func _spot() -> Vector3:
	for x in [-80.0, -110.0, -50.0, 40.0, 70.0, -140.0, 0.0]:
		for z in [-90.0, -60.0, -30.0, 0.0]:
			var ok := true
			var dx := -40.0
			while ok and dx <= 70.0:
				var dz := -10.0
				while dz <= MARCH + 15.0:
					var px: float = x + dx
					var pz: float = z + dz
					if GameManager.is_water(px, pz) or GameManager.is_cliff(px, pz):
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
		await _case(true)
	if "0" in _only:
		_Opt.am_front_guard = false
		await _case(false)
		_Opt.am_front_guard = true
	_finish()

func _case(guard: bool) -> void:
	var tag: String = "A" if guard else "A0"
	print("\n═════ %s. [A] армией мимо волны сбоку (am_front_guard=%s) ═════" % [tag, str(guard)])
	var start: Vector3 = _spot()
	_clear(start + Vector3(15.0, 0, MARCH * 0.5), 95.0)
	await pframes(5)
	# Армия: N_SQ отрядов в ряд по X, центр ряда — start
	var squads: Array = []
	for k in range(N_SQ):
		var x: float = (float(k) - float(N_SQ - 1) * 0.5) * SQ_GAP
		squads.append(_squad("spearman", start + Vector3(x, 0, 0), 24, F, 8))
	var right_x: float = (float(N_SQ - 1) * 0.5) * SQ_GAP
	# Линия орды на пути средних отрядов, волна справа
	var foes: Array = []
	var line: Array = []
	for j in range(3):
		var lx: float = (float(j) - 1.0) * SQ_GAP
		var sq: Array = _squad("goblin_spearman", start + Vector3(lx, 0, LINE_Z), 12, G, 6)
		line.append_array(sq)
	var band: Array = []
	for j2 in range(2):
		var sq2: Array = _squad("goblin_spearman", start + Vector3(right_x + BAND_DX, 0, BAND_DZ + float(j2) * 5.0), 12, G, 4)
		band.append_array(sq2)
	foes.append_array(line)
	foes.append_array(band)
	for g in foes:
		(g as Unit).max_health *= 3.0
		(g as Unit).current_health = (g as Unit).max_health
		(g as Unit).set_tick(false)
	await pframes(10)
	var sm = main.selection_manager
	var cmd = sm._squad_cmd()
	var rej0: int = int(cmd.front_rejects)
	var all: Array = []
	for s in squads:
		all.append_array(s)
	sm.select_units(all)
	cmd.attack_move(sm, GameManager.land_target(start + Vector3(0, 0, MARCH)))
	sm.clear_selection()
	var x0: Array = []
	for s0 in squads:
		x0.append(_centre(s0).x)
	var worst: Array = []
	for _i in range(N_SQ):
		worst.append(0.0)
	var aimed: Array = []
	for _k in range(N_SQ):
		aimed.append(false)
	var t := 0
	while t < 60 * 60:
		await pframes(15)
		t += 15
		var arrived := 0
		for i in range(N_SQ):
			var c: Vector3 = _centre(squads[i])
			if c.x == INF:
				continue
			worst[i] = maxf(float(worst[i]), c.x - float(x0[i]))
			for m in _alive(squads[i]):
				var at = (m as Unit).attack_target
				if at != null and is_instance_valid(at) and band.has(at):
					aimed[i] = true
					break
			if c.z >= start.z + MARCH - 8.0:
				arrived += 1
		if _trace and t % 60 == 0:
			var row := ""
			for i2 in range(N_SQ):
				var c2: Vector3 = _centre(squads[i2])
				row += " (%.0f,%.0f)" % [c2.x - start.x, c2.z - start.z]
			print("    t=%.0f%s" % [float(t) / 60.0, row])
		if arrived == N_SQ or _alive(line).is_empty() and t > 60 * 30:
			break
	var band_hit := 0
	for b in band:
		if not is_instance_valid(b) or (b as Unit).is_dead() or (b as Unit).current_health < (b as Unit).max_health:
			band_hit += 1
	# Судится правая половина армии — к волне. Левая законно сходится к
	# линии на помощь средним (угроза группы)
	var mx := 0.0
	for wi in range(N_SQ / 2, N_SQ):
		mx = maxf(mx, float(worst[wi]))
	var n_aimed := 0
	for a2 in aimed:
		n_aimed += 1 if bool(a2) else 0
	var lst: Array = []
	for w2 in worst:
		lst.append(snappedf(float(w2), 0.1))
	print("  %s: увод центров вправо по отрядам %s; отрядов с целью в волне %d; волна задета %d из %d; линия жива %d из %d; пар отклонено %d, за %.0f с" % [
		tag, str(lst), n_aimed, band_hit, band.size(), _alive(line).size(), line.size(), int(cmd.front_rejects) - rej0, float(t) / 60.0])
	if guard:
		verdict("A1 ни один отряд не ушёл к волне сбоку: увод вправо до %.1f м (≤ %.0f)" % [mx, LAT_MAX], mx <= LAT_MAX)
		verdict("A2 волна сбоку не взята целью и не тронута: отрядов с целью в волне %d, задето %d из %d" % [
			n_aimed, band_hit, band.size()], n_aimed == 0 and band_hit == 0)
		verdict("A3 раскладка фронта отклонила пары вне сектора: %d" % (int(cmd.front_rejects) - rej0),
			int(cmd.front_rejects) > rej0)
		verdict("A4 линия на пути разбита: живых %d из %d" % [_alive(line).size(), line.size()],
			_alive(line).size() * 4 <= line.size())
	else:
		verdict("A0 ручка am_front_guard=false: жалоба воспроизводится: отрядов с целью в волне сбоку %d, увод вправо %.1f м" % [n_aimed, mx],
			n_aimed > 0)
	for s2 in squads:
		_free(s2)
	_free(foes)
	await pframes(20)
