extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ATTACK-MOVE ДЕРЖИТ ВЕКТОР МАРША (ТЗ 22.10.2026, скриншот 15:54)
## ═══════════════════════════════════════════════════════════════════════════
## Армия из 4 отрядов (2 копейщиков, лучники, мечники) получает [A] строго
## на юг (+Z) настоящим SquadCommander.attack_move. Судится свойство:
##   A — одиночки орды стоят восточнее пути в 12-15 м: армия идёт вниз,
##       ни один отряд не сворачивает на восток (боковой увод центра ≤
##       LAT_MAX), все доходят до точки
##   B — гоблин ПРЯМО НА ПУТИ: армия его бьёт (сектор по ходу) и идёт дальше
##   C — постройка орды у пути (хижина): армия её сносит и идёт дальше
## Справочно печатается то же с ручкой am_march_cone выключенной (-- ab=1).
## Запуск: godot --headless --path . res://qa_attack_move_vector_test/Test.tscn [-- only=abc ab=1]

const _Hut := preload("res://scripts/goblin/GoblinHut.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

## Допустимый боковой увод центра отряда от его линии марша, м
const LAT_MAX := 6.0
## Длина марша, м
const MARCH := 64.0

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abc"
var _ab := false
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		if String(a) == "ab=1":
			_ab = true
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_attack_move_vector_test: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, at: Vector3, n: int, fac: int = F, cols: int = 8) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _clear_box(x0: float, z0: float, x1: float, z1: float) -> void:
	var c := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	var r: float = Vector2(x1 - x0, z1 - z0).length() * 0.5 + 10.0
	main._clear_trees(c, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(c) < r:
				u.queue_free()
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and (b as Node3D).global_position.distance_to(c) < r \
				and not (b as Building).is_stronghold():
			b.queue_free()

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "a" in _only:
		await _case_a(true)
		await _case_a(true, true)
		if _ab:
			_Opt.am_march_cone = false
			await _case_a(false, true)
			_Opt.am_march_cone = true
	if "b" in _only: await _case_b()
	if "c" in _only: await _case_c()
	_finish()

## Сухая полоса марша: от (x, z0) на юг на MARCH м без воды
func _lane() -> Vector3:
	for x in [-80.0, -100.0, -60.0, -120.0, 60.0, 80.0]:
		var ok := true
		var z := -60.0
		while z <= -60.0 + MARCH + 10.0:
			for dx in [-12.0, 0.0, 18.0]:
				if GameManager.is_water(x + dx, z) or GameManager.is_cliff(x + dx, z):
					ok = false
			z += 3.0
		if ok:
			return Vector3(x, 0, -60.0)
	return Vector3(-80, 0, -60)

## Армия: 2 копейщиков, лучники, мечники рядом в линию; [A] на юг
func _army(start: Vector3) -> Array:
	var squads: Array = []
	var kinds := ["spearman", "archer", "spearman", "warrior"]
	for k in range(4):
		squads.append(_squad(kinds[k], start + Vector3(-12.0 + float(k) * 7.0, 0, 0), 24))
	await pframes(10)
	return squads

func _attack_move(squads: Array, dest: Vector3) -> void:
	var sm = main.selection_manager
	var all: Array = []
	for s in squads:
		all.append_array(s)
	sm.select_units(all)
	sm._squad_cmd().attack_move(sm, GameManager.land_target(dest))
	sm.clear_selection()

func _centre(men: Array) -> Vector3:
	var a: Array = _alive(men)
	if a.is_empty():
		return Vector3.INF
	return GameManager._centroid_of(a)

func _case_a(cone_on: bool, shooters: bool = false) -> void:
	var tag: String = ("A3" if shooters else "A") if cone_on else ("A3-0 (справочно, без сектора)" if shooters else "A0 (справочно, без сектора)")
	print("\n═════ %s. %s ═════" % [tag, "красные лучники бьют с фланга в 14 м" if shooters else "одиночки на фланге в 12-15 м"])
	var start: Vector3 = _lane()
	_clear_box(start.x - 30, start.z - 10, start.x + 40, start.z + MARCH + 15)
	await pframes(5)
	var squads: Array = await _army(start)
	var x0: Array = []
	for s in squads:
		x0.append(_centre(s).x)
	# Одиночки к востоку от правого отряда: 12-15 м от его линии
	var lone: Array = []
	var east_x: float = start.x + 9.0
	if shooters:
		# Отряд красных лучников в 14 м восточнее правого отряда: начинают
		# бить, когда армия уже почти поравнялась (угол > 60° от хода)
		var arch: Array = _squad("archer", Vector3(east_x + 14.0, 0, start.z + 30.0), 8, Constants.FACTION_ENEMY, 4)
		for a0 in arch:
			(a0 as Unit).max_health *= 4.0
			(a0 as Unit).current_health = (a0 as Unit).max_health
		lone.append_array(arch)
	for k in range(0 if shooters else 4):
		var g := _spawn("goblin_spearman", Vector3(east_x + 12.0 + float(k % 2) * 3.0, 0, start.z + 12.0 + float(k) * 12.0), G)
		g.max_health *= 3.0
		g.current_health = g.max_health
		# Стоят смирно (тик снят): иначе подстреленный лучниками гоблин сам
		# прибегает в контакт, а рубка в контакте ТЗ разрешена — замер тогда
		# не про срыв марша на фланг
		g.set_tick(false)
		lone.append(g)
	var cmd = main.selection_manager._squad_cmd()
	var skips0: int = int(cmd.cone_skips)
	await _attack_move(squads, start + Vector3(0, 0, MARCH))
	# След центров; своя линия марша отряда — от центра на старте к точке, где
	# он встал (строй [A] раскладывает армию эшелонами — сдвиг к своему месту
	# законен, судится уход С ЭТОЙ ЛИНИИ по дороге)
	var tracks: Array = []
	for s0 in squads:
		tracks.append([_centre(s0)])
	var arrived := 0
	var t := 0
	while t < 60 * 70:
		await pframes(15)
		t += 15
		arrived = 0
		for i in range(squads.size()):
			var c: Vector3 = _centre(squads[i])
			if c.x == INF:
				continue
			(tracks[i] as Array).append(c)
			if i == 3 and t % 60 == 0 and OS.get_cmdline_user_args().has("trace=1"):
				var nd := INF
				var gpos := Vector3.ZERO
				for g3 in _alive(lone):
					var dd: float = c.distance_to((g3 as Node3D).global_position)
					if dd < nd:
						nd = dd
						gpos = (g3 as Node3D).global_position
				var lu3 := _alive(squads[3])[0] as Unit
				print("    TRACE3 t=%.0f c=(%.1f,%.1f) гоблин ближе всех %.1f м в (%.1f,%.1f) бой=%s цель=%s" % [float(t) / 60.0, c.x, c.z, nd, gpos.x, gpos.z, str(main.selection_manager._squad_cmd().is_fighting(lu3.squad_id)), str(lu3.attack_target)])
			if c.z >= start.z + MARCH - 6.0:
				arrived += 1
		if arrived == squads.size():
			break
	await pframes(120)
	var worst_lat := 0.0
	var lat_by: Array = []
	for i2 in range(squads.size()):
		var tr: Array = tracks[i2]
		var la: Vector3 = tr[0]
		var lb: Vector3 = _centre(squads[i2])
		var seg := Vector2(lb.x - la.x, lb.z - la.z)
		var w := 0.0
		for pnt in tr:
			var rel := Vector2((pnt as Vector3).x - la.x, (pnt as Vector3).z - la.z)
			# Только к ВОСТОКУ (к одиночкам): «сваливание вправо» из ТЗ.
			# При ходе на юг (+Z) восток даёт отрицательное cross
			var lat: float = maxf(0.0, -seg.normalized().cross(rel)) if seg.length() > 0.5 else maxf(0.0, rel.x)
			w = maxf(w, lat)
		lat_by.append(w)
		worst_lat = maxf(worst_lat, w)
	print("  %s: увод по отрядам (копейщики, лучники, копейщики, мечники) %s" % [tag, str(lat_by)])
	var east_hits := 0
	for g2 in lone:
		if not is_instance_valid(g2) or (g2 as Unit).is_dead() \
				or (g2 as Unit).current_health < (g2 as Unit).max_health:
			east_hits += 1
	print("  %s: боковой увод центров до %.1f м, дошли %d из %d за %.0f с, задето одиночек %d из %d, отсечено сектором %d" % [
		tag, worst_lat, arrived, squads.size(), float(t) / 60.0, east_hits, lone.size(), int(cmd.cone_skips) - skips0])
	if cone_on:
		var pre: String = "A3" if shooters else "A1"
		verdict("%s армия не сворачивает на восток (увод ≤ %.0f м)" % [pre, LAT_MAX], worst_lat <= LAT_MAX,
			"%.1f м" % worst_lat)
		verdict("%s все отряды дошли до точки на юге" % ("A4" if shooters else "A2"), arrived == squads.size(),
			"%d из %d" % [arrived, squads.size()])
	for s2 in squads:
		_free(s2)
	_free(lone)
	await pframes(10)

func _case_b() -> void:
	print("\n═════ B. гоблин прямо на пути ═════")
	var start: Vector3 = _lane()
	_clear_box(start.x - 30, start.z - 10, start.x + 40, start.z + MARCH + 15)
	await pframes(5)
	var squads: Array = await _army(start)
	var g := _spawn("goblin_spearman", start + Vector3(0, 0, 26), G)
	g.command_move(g.global_position)
	await _attack_move(squads, start + Vector3(0, 0, MARCH))
	var t := 0
	var arrived := 0
	while t < 60 * 70:
		await pframes(15)
		t += 15
		arrived = 0
		for s in squads:
			var c: Vector3 = _centre(s)
			if c.x != INF and c.z >= start.z + MARCH - 6.0:
				arrived += 1
		if arrived == squads.size() and (not is_instance_valid(g) or g.is_dead()):
			break
	var dead: bool = not is_instance_valid(g) or g.is_dead()
	print("  B: гоблин на пути убит %s, дошли %d из %d за %.0f с" % [dead, arrived, squads.size(), float(t) / 60.0])
	verdict("B1 цель по ходу марша атакована и уничтожена", dead)
	verdict("B2 после стычки армия дошла до точки", arrived == squads.size(), "%d из %d" % [arrived, squads.size()])
	for s2 in squads:
		_free(s2)
	if is_instance_valid(g):
		g.queue_free()
	await pframes(10)

func _case_c() -> void:
	print("\n═════ C. хижина орды у пути ═════")
	var start: Vector3 = _lane()
	_clear_box(start.x - 30, start.z - 10, start.x + 40, start.z + MARCH + 15)
	await pframes(5)
	var hut: Building = _Hut.new()
	hut.faction = G
	main.world_add(hut)
	var hp := start + Vector3(4.0, 0, 30.0)
	hut.global_position = Vector3(hp.x, GameManager.get_terrain_height(hp.x, hp.z), hp.z)
	await pframes(5)
	hut.max_health = 600.0
	hut.current_health = 600.0
	var squads: Array = await _army(start)
	var cmd = main.selection_manager._squad_cmd()
	var be0: int = int(cmd.bld_engages)
	await _attack_move(squads, start + Vector3(0, 0, MARCH))
	var t := 0
	var arrived := 0
	while t < 60 * 90:
		await pframes(15)
		t += 15
		arrived = 0
		for s in squads:
			var c: Vector3 = _centre(s)
			if c.x != INF and c.z >= start.z + MARCH - 6.0:
				arrived += 1
		if arrived == squads.size():
			break
	var razed: bool = not is_instance_valid(hut) or hut.is_dead()
	print("  C: хижина снесена %s, вступлений по зданию %d, дошли %d из %d за %.0f с" % [
		razed, int(cmd.bld_engages) - be0, arrived, squads.size(), float(t) / 60.0])
	verdict("C1 Attack-Move сносит постройку врага по ходу", razed)
	verdict("C2 после сноса армия дошла до точки", arrived == squads.size(), "%d из %d" % [arrived, squads.size()])
	for s2 in squads:
		_free(s2)
	await pframes(10)
