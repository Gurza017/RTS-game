extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: БЕГСТВО В ПАНИКЕ — ПРОЧЬ ОТ ВРАГА (ТЗ 29.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: отряды орды в панике бегут «вперёд» сквозь войска игрока, все в одну
## сторону. Причина: курс бегства брался из кэша _squad_face, который пишут
## только копейщики в «Защите»; у орды он пуст, и срабатывал запасной «от
## центра карты» — у базы игрока это ровно на строй игрока. Ручка
## perf_config.panic_away_enemy.
##   A НАПРАВЛЕНИЕ — волна орды между центром карты и строем игрока: срыв
##                   настоящим _start_panic, отряд уходит ОТ строя; ручка снята —
##                   прежний бег на строй (доказательство ручки)
##   B ТЕЛА       — сзади тонкая шеренга игрока, спереди большой блок: бегут
##                   от блока и проходят шеренгу насквозь (F_CLEAR_ENEMY)
##   C ЛЕС        — враг с одной стороны, лес с другой: бегут от врага, у леса
##                   поворачивают (_panic_turn), бега на месте нет, в лесу никого
## Враги заморожены (тела в ядре есть, ударов нет); время — физкадрами.

const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_panic_flee: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, at: Vector3, fac: int) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int, cols: int, step: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k / cols) * step, 0, float(k % cols) * step), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

## Заморожённая шеренга поперёк оси: n бойцов по перпендикуляру к out
func _line(at: Vector3, out: Vector3, n: int, step: float, fac: int) -> Array:
	var sid: int = GameManager.new_squad(fac, "spearman")
	var perp := Vector3(-out.z, 0.0, out.x)
	var res: Array = []
	for k in range(n):
		var u := _spawn("spearman", at + perp * (float(k) - float(n - 1) * 0.5) * step, fac)
		GameManager.add_to_squad(sid, u)
		u.set_tick(false)
		res.append(u)
	return res

func _clear(at: Vector3, r: float, trees: bool = true) -> void:
	if trees:
		main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _centre(men: Array) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			s += (m as Unit).global_position
			n += 1
	return s / float(maxi(n, 1))

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 20.0), Vector3(0.0, 0.0, -20.0)]:
				var q: Vector3 = p + (d as Vector3)
				h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
				if GameManager.is_water(q.x, q.z):
					h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

## Окна по 1 с: в MOVING и сместился меньше RIP_STEP — «бег на месте»;
## наибольшая серия окон подряд по отряду
const RIP_STEP := 0.25
func _watch(men: Array, sec: float) -> int:
	var last: Dictionary = {}
	var run: Dictionary = {}
	var worst := 0
	var t := 0.0
	while t < sec:
		await pframes(60)
		t += 1.0
		for m in men:
			if m == null or not is_instance_valid(m) or (m as Unit).is_dead():
				continue
			var u := m as Unit
			var p: Vector3 = u.global_position
			var k: int = u.get_instance_id()
			if last.has(k):
				var lp: Vector3 = last[k]
				if u.state == Unit.State.MOVING and Vector2(p.x - lp.x, p.z - lp.z).length() < RIP_STEP:
					run[k] = int(run.get(k, 0)) + 1
					worst = maxi(worst, int(run[k]))
				else:
					run[k] = 0
			last[k] = p
	return worst

func _panic(men: Array) -> void:
	var sid: int = (men[0] as Unit).squad_id
	GameManager._start_panic(sid)
	GameManager._drain_panic_queue(true)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager", "boss_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if main.fog != null:
		main.fog.enabled = false
	GameManager.pop_limit_enabled = false
	# Площадка между центром карты и базой игрока: «от центра» здесь = на базу
	var anchor: Vector3 = main.PLAYER_BASE_ANCHOR * 0.55
	anchor.y = 0.0
	var p: Vector3 = _flat_spot(anchor)
	var out: Vector3 = Vector3(p.x, 0.0, p.z).normalized()
	print("  площадка (%.0f, %.0f), «от центра» (%.2f, %.2f)" % [p.x, p.z, out.x, out.z])
	_clear(p, 60.0)
	await pframes(5)
	await _a_dir("A1", p, out, true)
	await _a_dir("A0", p, out, false)
	await _b_bodies(p, out)
	await _c_forest()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. НАПРАВЛЕНИЕ: строй игрока там, куда «от центра карты»
# ═════════════════════════════════════════════════════════════════════════════
func _a_dir(tag: String, p: Vector3, out: Vector3, knob: bool) -> void:
	print("\n═════ %s. ПАНИКА ОРДЫ У СТРОЯ ИГРОКА (panic_away_enemy=%s) ═════" % [tag, str(knob)])
	_Opt.panic_away_enemy = knob
	var gobs: Array = _squad("goblin_spearman", p - Vector3(1.6, 0, 1.6), 16, G, 4, 0.9)
	var foes: Array = []
	for r in range(3):
		foes.append_array(_line(p + out * (7.0 + float(r) * 0.8), out, 10, 0.7, F))
	await pframes(10)
	var fc: Vector3 = _centre(foes)
	var c0: Vector3 = _centre(gobs)
	var d0: float = Vector2(c0.x - fc.x, c0.z - fc.z).length()
	var p0: Dictionary = {}
	for g in gobs:
		p0[(g as Unit).get_instance_id()] = (g as Unit).global_position
	_panic(gobs)
	await pframes(60 * 5)
	var c1: Vector3 = _centre(gobs)
	var d1: float = Vector2(c1.x - fc.x, c1.z - fc.z).length()
	var away := 0
	var toward := 0
	for g in gobs:
		var u := g as Unit
		var mv: Vector3 = u.global_position - p0[u.get_instance_id()]
		mv.y = 0.0
		var dir: Vector3 = (Vector3(p0[u.get_instance_id()]) - fc)
		dir.y = 0.0
		if mv.length() > 1.0:
			if mv.dot(dir) > 0.0:
				away += 1
			else:
				toward += 1
	var info := "до строя %.1f → %.1f м, прочь %d, к врагу %d из %d" % [d0, d1, away, toward, gobs.size()]
	if knob:
		verdict("A1a отряд ушёл прочь от строя игрока (+6 м)", d1 >= d0 + 6.0, info)
		verdict("A1b каждый бежит прочь (≥ 90 %), к врагу — никто", away * 10 >= gobs.size() * 9 and toward == 0, info)
	else:
		verdict("A0 ручка снята: прежний бег на строй игрока (воспроизведение жалобы)", toward > away, info)
	_Opt.panic_away_enemy = true
	_free(gobs)
	_free(foes)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# B. ТЕЛА: бегут от блока и проходят сквозь тонкую шеренгу сзади
# ═════════════════════════════════════════════════════════════════════════════
func _b_bodies(p: Vector3, out: Vector3) -> void:
	print("\n═════ B. СКВОЗЬ ЧУЖУЮ ШЕРЕНГУ ЗА СПИНОЙ ═════")
	var gobs: Array = _squad("goblin_spearman", p - Vector3(1.4, 0, 1.4), 12, G, 4, 0.9)
	var block: Array = []
	for r in range(4):
		block.append_array(_line(p + out * (5.0 + float(r) * 0.8), out, 12, 0.7, F))
	var line_c: Vector3 = p - out * 3.5
	var line: Array = _line(line_c, out, 14, 0.55, F)
	await pframes(10)
	var turns0: int = Unit.panic_turns
	_panic(gobs)
	var worst: int = await _watch(gobs, 7.0)
	var beyond := 0
	for g in gobs:
		var q: Vector3 = (g as Unit).global_position - line_c
		if q.dot(-out) > 1.0:
			beyond += 1
	verdict("B1 бегут от блока и прошли шеренгу за спиной (≥ 80 %)", beyond * 10 >= gobs.size() * 8,
		"%d из %d за шеренгой" % [beyond, gobs.size()])
	verdict("B2 нет бега на месте у чужих тел (серия окон ≤ 1)", worst <= 1,
		"худшая серия %d, поворотов %d" % [worst, Unit.panic_turns - turns0])
	_free(gobs)
	_free(block)
	_free(line)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# C. ЛЕС: за спиной — глухое препятствие
# ═════════════════════════════════════════════════════════════════════════════
## Клетка леса (непроходимая), от которой в 4 м есть чистая площадка: точка
## бегства (PANIC_FLEE_DIST) ложится за опушку, и бег упирается в лес
func _forest_spot() -> Array:
	var lx: float = GameManager.map_lim_x - 40.0
	var lz: float = GameManager.map_lim_z - 40.0
	var x := -lx
	while x < lx:
		var z := -lz
		while z < lz:
			if not GameManager.is_passable(x, z) and not GameManager.is_water(x, z):
				for d in [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]:
					var s: Vector3 = Vector3(x, 0, z) - d * 4.0
					var ok := true
					for r in range(25):
						var q: Vector3 = s - d * float(r / 5) * 2.5 + Vector3(-d.z, 0, d.x) * float(r % 5 - 2) * 2.0
						if not GameManager.is_passable(q.x, q.z) or GameManager.is_water(q.x, q.z):
							ok = false
					if ok:
						return [Vector3(x, 0, z), s, d]
			z += 6.0
		x += 6.0
	return []

func _c_forest() -> void:
	print("\n═════ C. ЗА СПИНОЙ ЛЕС ═════")
	var spot: Array = _forest_spot()
	if spot.is_empty():
		verdict("C0 нашлась клетка леса", false)
		return
	var wall: Vector3 = spot[0]
	var s: Vector3 = spot[1]
	var d: Vector3 = spot[2]
	print("  лес (%.0f, %.0f), старт (%.0f, %.0f), лес в стороне (%.0f, %.0f)" % [wall.x, wall.z, s.x, s.z, d.x, d.z])
	_clear(s - d * 5.0, 6.0, false)
	await pframes(5)
	var gobs: Array = _squad("goblin_spearman", s - Vector3(1.0, 0, 1.0), 8, G, 3, 0.9)
	var foes: Array = _line(s - d * 7.0, -d, 10, 0.7, F)
	foes.append_array(_line(s - d * 7.8, -d, 10, 0.7, F))
	await pframes(10)
	var fc: Vector3 = _centre(foes)
	var d0: Dictionary = {}
	for g in gobs:
		var u := g as Unit
		d0[u.get_instance_id()] = Vector2(u.global_position.x - fc.x, u.global_position.z - fc.z).length()
	var turns0: int = Unit.panic_turns
	_panic(gobs)
	var worst: int = await _watch(gobs, 8.0)
	var farther := 0
	var in_wood := 0
	for g in gobs:
		var u := g as Unit
		var q: Vector3 = u.global_position
		if Vector2(q.x - fc.x, q.z - fc.z).length() > float(d0[u.get_instance_id()]) + 3.0:
			farther += 1
		if not GameManager.is_passable(q.x, q.z):
			in_wood += 1
	var turns: int = Unit.panic_turns - turns0
	var blocked: bool = GameManager.nav_blocked(s, s + d * 12.0, 0.75)
	verdict("C0 прямая бегства от врага упирается в лес (сцена осмысленна)", blocked)
	verdict("C1 бегут от врага, а не на него (≥ 80 % дальше на 3 м)", farther * 10 >= gobs.size() * 8,
		"%d из %d" % [farther, gobs.size()])
	verdict("C2 у леса нет бега на месте (серия окон ≤ 1)", worst <= 1, "худшая серия %d, поворотов %d" % [worst, turns])
	verdict("C3 в непроходимой клетке никого", in_wood == 0, "%d в лесу" % in_wood)
	_free(gobs)
	_free(foes)
	await pframes(5)
