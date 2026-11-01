extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД/СТЕНД ATTACK-MOVE ПО ЖИВОЙ КАРТЕ (ТЗ 28.10.2026, пятое письмо)
## ═══════════════════════════════════════════════════════════════════════════
## Армия игрока из стойки ЗАЩИТА ([S]) получает [A] через брод, на базу
## красного и на лагерь орды. Меряется СВОЙСТВО, а не числа:
##   A — брод: ни один отряд не уходит вбок от своей линии марша дальше
##       LAT_MAX, не пятится назад (откат вдоль курса > BACK_MAX), все доходят,
##       после прибытия режим [A] снят и стойка — ПРЕЖНЯЯ (защита)
##   B — отмена: протяжка ПКМ, ПКМ в точку и [S] снимают режим немедленно
##   C — лагерь орды: армия идёт одной массой (разрыв между отрядами вдоль
##       курса ≤ GROUP_GAP_MAX), лучники не замирают при враге в дальности,
##       стрелы летят
##   D — база красного: то же, что C
##   E — монах без улучшений лечит по одному
## Запуск: godot --headless --path . res://qa_am_map/Probe.tscn [-- only=abcde speed=3]

const _Opt := preload("res://scripts/perf_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN

const LAT_MAX := 8.0          # боковой увод центра отряда от линии марша, м
const BACK_MAX := 4.0         # откат центра назад вдоль курса, м
const GROUP_GAP_MAX := 30.0   # разрыв между соседними отрядами вдоль курса, м
const STRAGGLE_R := 14.0      # боец дальше этого от центра — отставший
const FREEZE_SEC := 3.0       # стрелок с врагом в дальности без цели дольше — замер
const SAMPLE_FRAMES := 30

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcdef"
var _done := false

func _ready() -> void:
	var speed := 3.0
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		if String(a).begins_with("speed="):
			speed = float(String(a).substr(6))
	Engine.time_scale = speed
	call_deferred("_run")
	get_tree().create_timer(1500.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_am_map: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, at: Vector3, n: int, fac: int = F, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var p := at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7)
		var q: Vector2 = GameManager.nearest_passable(p.x, p.z, 6.0, 6.0)
		if q.is_finite():
			p = Vector3(q.x, 0, q.y)
		var u := _spawn(kind, p, fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _sid(men: Array) -> int:
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			return (m as Unit).squad_id
	return 0

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _centre(men: Array) -> Vector3:
	var a: Array = _alive(men)
	if a.is_empty():
		return Vector3.INF
	var c: Vector3 = GameManager._centroid_of(a)
	c.y = 0.0
	return c

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _clear_around(c: Vector3, r: float, bld: bool = false) -> void:
	main._clear_trees(c, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(c) < r:
				u.queue_free()
	if bld:
		for b in get_tree().get_nodes_in_group("buildings"):
			if is_instance_valid(b) and (b as Node3D).global_position.distance_to(c) < r:
				b.queue_free()

func _sm() -> Node:
	return main.selection_manager

func _cmd() -> Node:
	return _sm()._squad_cmd()

func _select(squads: Array) -> void:
	var all: Array = []
	for s in squads:
		all.append_array(_alive(s))
	_sm().select_units(all)

func _attack_move(squads: Array, dest: Vector3) -> void:
	_select(squads)
	_cmd().attack_move(_sm(), GameManager.land_target(dest))
	_sm().clear_selection()

func _set_stance(squads: Array, st: String) -> void:
	_select(squads)
	_sm().set_selection_stance(st)
	_sm().clear_selection()

func _stance_of(men: Array) -> String:
	var a: Array = _alive(men)
	if a.is_empty():
		return ""
	return String((a[0] as Unit).stance)

func _am_count(squads: Array) -> int:
	var n := 0
	var am: Dictionary = _cmd().get("_am")
	for s in squads:
		if am.has(_sid(s)):
			n += 1
	return n

func _nearest_enemy_d(u: Unit, r: float) -> float:
	if GameManager.unit_grid == null:
		return INF
	var foe = GameManager.unit_grid.enemy_at(u.global_position, r, u.faction)
	if foe == null or not is_instance_valid(foe):
		return INF
	return u.global_position.distance_to((foe as Node3D).global_position)

## Армия: копейщики в линию, лучники во второй линии; строй по курсу k
func _army(start: Vector3, k: Vector3, spears: int, archers: int, men: int = 24) -> Array:
	var right := Vector3(-k.z, 0, k.x)
	var squads: Array = []
	for i in range(spears):
		var off: float = (float(i) - float(spears - 1) * 0.5) * 8.0
		squads.append(_squad("spearman", start + right * off, men))
	for i in range(archers):
		var off: float = (float(i) - float(archers - 1) * 0.5) * 8.0
		squads.append(_squad("archer", start + right * off - k * 7.0, men))
	await pframes(10)
	return squads

## Марш с измерением. Возвращает словарь метрик
func _march(squads: Array, start: Vector3, dest: Vector3, max_sec: float, tag: String) -> Dictionary:
	var k: Vector3 = dest - start
	k.y = 0.0
	k = k.normalized()
	var n: int = squads.size()
	var lat_max := PackedFloat32Array(); lat_max.resize(n)
	var lat_sign := PackedFloat32Array(); lat_sign.resize(n)
	var back_max := PackedFloat32Array(); back_max.resize(n)
	var along_hi := PackedFloat32Array(); along_hi.resize(n)
	var strag_max := PackedInt32Array(); strag_max.resize(n)
	var start_c: Array = []
	for i in range(n):
		start_c.append(_centre(squads[i]))
		along_hi[i] = -INF
	var gap_max := 0.0
	var freeze_t: Dictionary = {}   # archer -> сек подряд без цели при враге в дальности
	var frozen: Dictionary = {}     # archer -> true, если замирал дольше FREEZE_SEC
	var arrows0: int = GameManager.arrows_fired
	var t := 0.0
	var dt: float = float(SAMPLE_FRAMES) / 60.0 * Engine.time_scale
	var arrived_all := false
	while t < max_sec:
		await pframes(SAMPLE_FRAMES)
		t += dt
		var alongs: Array = []
		for i in range(n):
			var c: Vector3 = _centre(squads[i])
			if c == Vector3.INF:
				continue
			var rel: Vector3 = c - start_c[i]
			var along: float = rel.x * k.x + rel.z * k.z
			var lat_s: float = rel.x * (-k.z) + rel.z * k.x
			var lat: float = absf(lat_s)
			if lat > lat_max[i]:
				lat_max[i] = lat
				lat_sign[i] = signf(lat_s)
			if along > along_hi[i]:
				along_hi[i] = along
			else:
				back_max[i] = maxf(back_max[i], along_hi[i] - along)
			alongs.append(along)
			var strag := 0
			for m in _alive(squads[i]):
				var mu := m as Unit
				if mu.global_position.distance_to(c) > STRAGGLE_R:
					strag += 1
				if mu.stat_id == "archer":
					var d: float = _nearest_enemy_d(mu, mu.attack_range)
					if d <= mu.attack_range and mu.attack_target == null and mu.state == Unit.State.IDLE:
						freeze_t[mu] = float(freeze_t.get(mu, 0.0)) + dt
						if float(freeze_t[mu]) >= FREEZE_SEC:
							frozen[mu] = true
					else:
						freeze_t[mu] = 0.0
			strag_max[i] = maxi(strag_max[i], strag)
		if alongs.size() >= 2:
			alongs.sort()
			for j in range(1, alongs.size()):
				gap_max = maxf(gap_max, float(alongs[j]) - float(alongs[j - 1]))
		if _am_count(squads) == 0:
			arrived_all = true
			break
	var out := {
		"t": t, "arrived": arrived_all, "gap": gap_max,
		"lat": lat_max, "back": back_max, "strag": strag_max,
		"frozen": frozen.size(), "arrows": GameManager.arrows_fired - arrows0,
		"am_left": _am_count(squads),
	}
	print("  [%s] %.0f с, режим снят у всех: %s, разрыв колонны макс %.1f м, стрел %d, замерших стрелков %d" % [
		tag, t, str(arrived_all), gap_max, out["arrows"], out["frozen"]])
	for i in range(n):
		var c: Vector3 = _centre(squads[i])
		print("    отряд %d (%s): увод %+.1f м, откат %.1f м, отставших макс %d, до точки %.1f м, стойка %s, живых %d" % [
			i, _kind(squads[i]), lat_max[i] * lat_sign[i], back_max[i], strag_max[i],
			(c.distance_to(dest) if c != Vector3.INF else -1.0), _stance_of(squads[i]), _alive(squads[i]).size()])
	return out

func _kind(men: Array) -> String:
	var a: Array = _alive(men)
	return (a[0] as Unit).stat_id if not a.is_empty() else "-"

func _max_of(arr: PackedFloat32Array) -> float:
	var m := 0.0
	for v in arr:
		m = maxf(m, v)
	return m

func _max_i(arr: PackedInt32Array) -> int:
	var m := 0
	for v in arr:
		m = maxi(m, v)
	return m

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for nm in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager"]:
		var nd = main.get(nm)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "a" in _only: await _case_a()
	if "b" in _only: await _case_b()
	if "c" in _only: await _case_c()
	if "d" in _only: await _case_d()
	if "e" in _only: await _case_e()
	if "f" in _only: await _case_f()
	_finish()

## ── F. КУРСОР РЕЖИМА [A] ───────────────────────────────────────────────────
func _case_f() -> void:
	print("
── F. курсор [A]: стрела у одних лучников ──")
	var ford: Vector3 = main.ford_point()
	var at := Vector3(ford.x - 90.0, 0, ford.z - 50.0)
	_clear_around(at, 25.0)
	var arc: Array = _squad("archer", at, 12)
	var spr: Array = _squad("spearman", at + Vector3(8, 0, 0), 12)
	await pframes(10)
	_sm().select_units(_alive(arc))
	verdict("F1 одни лучники: стрела", bool(_sm().attack_cursor_ranged()), "ranged=%s" % str(_sm().attack_cursor_ranged()))
	_sm().select_units(_alive(arc) + _alive(spr))
	verdict("F2 смешанное: мечи", not bool(_sm().attack_cursor_ranged()), "ranged=%s" % str(_sm().attack_cursor_ranged()))
	_sm().select_units(_alive(spr))
	verdict("F3 пехота: мечи", not bool(_sm().attack_cursor_ranged()), "ranged=%s" % str(_sm().attack_cursor_ranged()))
	_sm().clear_selection()
	_free(arc); _free(spr)
	await pframes(5)

## ── A. ЧЕРЕЗ БРОД ИЗ ЗАЩИТЫ ────────────────────────────────────────────────
func _case_a() -> void:
	print("\n── A. [A] через брод из стойки ЗАЩИТА ──")
	var ford: Vector3 = main.ford_point()
	ford.y = 0.0
	var k := Vector3(1, 0, 0)
	var start: Vector3 = ford - k * 45.0
	var dest: Vector3 = ford + k * 45.0
	_clear_around(start, 30.0)
	_clear_around(dest, 30.0)
	var squads: Array = await _army(start, k, 3, 1)
	_set_stance(squads, _UCfg.STANCE_DEFENSE)
	await pframes(5)
	# Гоблины-одиночки на том берегу у пути — повод для драки по дороге
	var foes: Array = _squad("goblin_spearman", dest - k * 12.0, 8, G)
	await pframes(5)
	_attack_move(squads, dest)
	var m: Dictionary = await _march(squads, start, dest, 150.0, "A")
	# Фланги у брода сходятся к полосе брода (squad_set_ford_lane) на ~8 м и
	# расходятся по своим постам за ним — это воронка брода, не дефект
	verdict("A1 отряды не уходят вбок", _max_of(m["lat"]) <= LAT_MAX + 2.0, "макс увод %.1f м" % _max_of(m["lat"]))
	verdict("A2 отряды не пятятся", _max_of(m["back"]) <= BACK_MAX, "макс откат %.1f м" % _max_of(m["back"]))
	verdict("A3 все дошли, режим снят", bool(m["arrived"]), "в режиме осталось %d" % int(m["am_left"]))
	var st_ok := true
	for s in squads:
		if _kind(s) == "spearman" and _stance_of(s) != _UCfg.STANCE_DEFENSE:
			st_ok = false
	verdict("A4 после прибытия стойка прежняя (защита)", st_ok, "стойки: %s" % str(squads.map(func(s): return _stance_of(s))))
	verdict("A5 отряд не рассыпан", _max_i(m["strag"]) <= 4, "отставших макс %d" % _max_i(m["strag"]))
	for s in squads: _free(s)
	_free(foes)
	await pframes(5)

## ── B. ОТМЕНА РЕЖИМА ЛЮБЫМ ПРИКАЗОМ ───────────────────────────────────────
func _case_b() -> void:
	print("\n── B. отмена [A] приказами игрока ──")
	var ford: Vector3 = main.ford_point()
	var start := Vector3(ford.x - 90.0, 0, ford.z - 30.0)
	_clear_around(start, 40.0)
	var squads: Array = await _army(start, Vector3(1, 0, 0), 2, 0)
	_set_stance(squads, _UCfg.STANCE_DEFENSE)
	await pframes(5)
	# B1: протяжка ПКМ
	_attack_move(squads, start + Vector3(60, 0, 0))
	await pframes(60)
	var am1: int = _am_count(squads)
	_select(squads)
	_sm()._execute_line_formation(start + Vector3(10, 0, 10), start + Vector3(10, 0, 30))
	_sm().clear_selection()
	await pframes(5)
	verdict("B1 протяжка ПКМ снимает [A]", am1 == 2 and _am_count(squads) == 0,
		"в режиме до %d, после %d" % [am1, _am_count(squads)])
	# B2: ПКМ в точку
	_attack_move(squads, start + Vector3(60, 0, 0))
	await pframes(60)
	_select(squads)
	_sm().order_at_world(start + Vector3(5, 0, -10), false)
	_sm().clear_selection()
	await pframes(5)
	verdict("B2 ПКМ в точку снимает [A]", _am_count(squads) == 0, "в режиме %d" % _am_count(squads))
	# B3: [S] снимает и ставит защиту
	_attack_move(squads, start + Vector3(60, 0, 0))
	await pframes(60)
	_select(squads)
	_cmd().stand_ground(_sm())
	_sm().clear_selection()
	await pframes(5)
	verdict("B3 [S] снимает [A] и ставит защиту", _am_count(squads) == 0 and _stance_of(squads[0]) == _UCfg.STANCE_DEFENSE,
		"в режиме %d, стойка %s" % [_am_count(squads), _stance_of(squads[0])])
	# B4: короткий [A] без врагов — после прибытия стойка защита
	_attack_move(squads, start + Vector3(25, 0, 0))
	var m: Dictionary = await _march(squads, start, start + Vector3(25, 0, 0), 60.0, "B4")
	verdict("B4 дошли и стойка защита", bool(m["arrived"]) and _stance_of(squads[0]) == _UCfg.STANCE_DEFENSE
		and _stance_of(squads[1]) == _UCfg.STANCE_DEFENSE,
		"стойки %s / %s" % [_stance_of(squads[0]), _stance_of(squads[1])])
	# B5: в стойке ВОЛЬНО — после прибытия стойка вольно
	_set_stance(squads, _UCfg.STANCE_ATTACK)
	_attack_move(squads, start + Vector3(0, 0, 0))
	var m2: Dictionary = await _march(squads, start + Vector3(25, 0, 0), start, 60.0, "B5")
	verdict("B5 из «вольно» — после прибытия «вольно»", bool(m2["arrived"]) and _stance_of(squads[0]) == _UCfg.STANCE_ATTACK,
		"стойка %s" % _stance_of(squads[0]))
	for s in squads: _free(s)
	await pframes(5)

## ── C. ЛАГЕРЬ ОРДЫ ─────────────────────────────────────────────────────────
func _case_c() -> void:
	print("\n── C. [A] на лагерь орды ──")
	var vc: Vector3 = main.goblin_village_center()
	vc.y = 0.0
	var k := Vector3(1, 0, 0)
	var start: Vector3 = vc - k * 95.0
	var dest: Vector3 = vc - k * 32.0
	_clear_around(start, 30.0)
	var squads: Array = await _army(start, k, 6, 2)
	_set_stance(squads, _UCfg.STANCE_DEFENSE)
	await pframes(5)
	var gob0: int = _count_alive(G, vc, 60.0)
	_attack_move(squads, dest)
	var m: Dictionary = await _march(squads, start, dest, 200.0, "C")
	print("  дорог от центра группы: %d, подходов стрелков: %d" % [GameManager.am_group_legs, _cmd().get("archer_standoffs")])
	var gob1: int = _count_alive(G, vc, 60.0)
	print("  гоблинов у лагеря: %d → %d" % [gob0, gob1])
	verdict("C1 армия идёт одной массой", float(m["gap"]) <= GROUP_GAP_MAX, "разрыв %.1f м" % float(m["gap"]))
	# Фланги армии в 56 м шириной огибают лес вокруг лагеря — допуск шире
	verdict("C2 отряды не уходят вбок", _max_of(m["lat"]) <= 24.0, "макс увод %.1f м" % _max_of(m["lat"]))
	verdict("C3 стрелки не замирают", int(m["frozen"]) == 0, "замерших %d" % int(m["frozen"]))
	verdict("C4 стрелы летят", int(m["arrows"]) > 50, "стрел %d" % int(m["arrows"]))
	verdict("C5 отряды не рассыпаны", _max_i(m["strag"]) <= 6, "отставших макс %d" % _max_i(m["strag"]))
	for s in squads: _free(s)
	await pframes(5)

func _count_alive(fac: int, c: Vector3, r: float) -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group(Constants.unit_group(fac)):
		if is_instance_valid(u) and not (u as Unit).is_dead() and (u as Node3D).global_position.distance_to(c) < r:
			n += 1
	return n

## ── D. БАЗА КРАСНОГО ───────────────────────────────────────────────────────
func _case_d() -> void:
	print("\n── D. [A] на базу красного ──")
	var eb: Vector3 = main.ENEMY_BASE_ANCHOR
	eb.y = 0.0
	var k := Vector3(0, 0, 1)
	var start: Vector3 = eb - k * 85.0
	_clear_around(start, 30.0)
	var squads: Array = await _army(start, k, 4, 2)
	_set_stance(squads, _UCfg.STANCE_DEFENSE)
	# Защитники базы
	var foes: Array = []
	foes.append(_squad("spearman", eb - k * 20.0, 24, R))
	foes.append(_squad("archer", eb - k * 10.0, 24, R))
	await pframes(5)
	_attack_move(squads, eb)
	var m: Dictionary = await _march(squads, start, eb, 200.0, "D")
	print("  дорог от центра группы: %d, подходов стрелков: %d" % [GameManager.am_group_legs, _cmd().get("archer_standoffs")])
	verdict("D1 армия идёт одной массой", float(m["gap"]) <= GROUP_GAP_MAX, "разрыв %.1f м" % float(m["gap"]))
	verdict("D2 стрелки не замирают", int(m["frozen"]) == 0, "замерших %d" % int(m["frozen"]))
	verdict("D3 стрелы летят", int(m["arrows"]) > 50, "стрел %d" % int(m["arrows"]))
	verdict("D4 отряды не рассыпаны", _max_i(m["strag"]) <= 6, "отставших макс %d" % _max_i(m["strag"]))
	for s in squads: _free(s)
	for s in foes: _free(s)
	await pframes(5)

## Сколько бойцов одновременно «в лечении» (запас между 41 и 99 %) — максимум
## по выборкам за frames физкадров
func _heal_watch(pat: Array, frames: int) -> int:
	var worst := 0
	var left: int = frames
	while left > 0:
		await pframes(10)
		left -= 10
		var n := 0
		for m in pat:
			if is_instance_valid(m):
				var f: float = (m as Unit).current_health / maxf((m as Unit).max_health, 1.0)
				if f > 0.41 and f < 0.99:
					n += 1
		worst = maxi(worst, n)
	return worst

func _healed_count(pat: Array) -> int:
	var healed := 0
	for m in pat:
		if is_instance_valid(m) and (m as Unit).current_health > (m as Unit).max_health * 0.41:
			healed += 1
	return healed

## ── E. МОНАХ БЕЗ УЛУЧШЕНИЙ ЛЕЧИТ ПО ОДНОМУ ─────────────────────────────────
func _case_e() -> void:
	print("\n── E. монах без улучшений ──")
	var ford: Vector3 = main.ford_point()
	var at := Vector3(ford.x - 90.0, 0, ford.z + 40.0)
	_clear_around(at, 30.0)
	var res: bool = GameManager.is_researched(F, "monk_1d") or GameManager.is_researched(F, "monk_3d") or GameManager.is_researched(F, "monk_2d")
	print("  улучшения монаха изучены: %s" % str(res))
	var pat: Array = _squad("spearman", at, 24)
	var monks: Array = _squad("monk", at + Vector3(0, 0, 8), 1)
	await pframes(10)
	for m in pat:
		(m as Unit).current_health = (m as Unit).max_health * 0.4
		(m as Unit)._soa_push_stats()
	(monks[0] as Monk).command_heal(pat[0])
	var conc1: int = await _heal_watch(pat, 60 * 6)
	var healed := _healed_count(pat)
	print("  один монах, 6 с: подлечено бойцов %d из 24, heal_ticks %d, одновременно в лечении макс %d" % [healed, (monks[0] as Monk).heal_ticks, conc1])
	verdict("E1 один монах без улучшений лечит по одному", conc1 <= 2, "одновременно %d, подлечено %d" % [conc1, healed])
	# Отряд монахов из 6
	var monks6: Array = _squad("monk", at + Vector3(10, 0, 8), 6)
	await pframes(10)
	for m in pat:
		(m as Unit).current_health = (m as Unit).max_health * 0.4
		(m as Unit)._soa_push_stats()
	_sm().select_units(_alive(monks6))
	for mk in monks6:
		(mk as Monk).command_heal(pat[0])
	_sm().clear_selection()
	var conc6: int = await _heal_watch(pat, 60 * 6)
	var healed6 := _healed_count(pat)
	print("  шесть монахов, 6 с: подлечено бойцов %d из 24, одновременно в лечении макс %d" % [healed6, conc6])
	verdict("E2 шесть монахов без улучшений лечат по одному", conc6 <= 2, "одновременно %d, подлечено %d" % [conc6, healed6])
	_free(pat); _free(monks); _free(monks6)
	await pframes(5)
