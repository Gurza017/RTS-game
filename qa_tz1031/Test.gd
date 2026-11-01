extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tz1031 — ПОГОНЯ ПОД ЗАМКОМ, [A] В «ЗАЩИТЕ», СМЫКАНИЕ ПО РЯДАМ
## (ТЗ 31.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ПОГОНЯ   — прямой приказ игрока (замок) дожимает уходящую цель дальше
##                поводка PURSUIT_LIMIT, пока она в LOCK_CHASE_MAX от точки
##                приказа; дальше приказ исчерпан; ручка lock_chase.
##   B [A]+ЗАЩИТА — отряд в «Защите» идёт [A], не переходя в «Атаку», по
##                прибытии стоит в «Защите», встречного бьёт; ручка am_keep_defense.
##   C ПО РЯДАМ — смыкание рассыпанного отряда: передний по курсу — в
##                передние шеренги (нет «инверсий»: шедший впереди не уходит
##                за шедшего позади); ручка rank_match.
##   D [A] НЕ СМЫКАЕТСЯ — смыкание отряда на марше [A] отклонено; ручка am_no_reform.
##   E МОНАХИ   — монахи одного отряда не расходятся друг от друга; ручка
##                monk_spacing_own_squad.
##   F СТРОЙ ПО МЕСТУ — смыкание растянутого отряда ставит переднюю шеренгу у
##                передних (назад идут единицы), смыкание по потерям у ушедшего
##                от разметки отряда строит его там, где он стоит, а не на
##                исходной линии; ручка reform_front_anchor.
##   G ПОВОДОК  — обрыв погони по авто-агро: боец встаёт, к якорю назад не
##                идёт; ручка leash_hold_here.
##   H СТРОЙ ПОСЛЕ БОЯ — «догнал, уничтожил — собрался»: отряд добил
##                рассыпанного врага по ПКМ и стоит строем, а не россыпью;
##                гнался один — он возвращается в свою ячейку, соседи стоят;
##                ручка idle_form_up.
## Числа — из конфигов и кода (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_tz1031/Test.tscn [-- only=abcdefg]

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN
const _Opt := preload("res://scripts/perf_config.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _base: Vector3 = Vector3.ZERO
var _only: String = "abcdefgh"
var _trace := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		elif String(a) == "trace=1":
			_trace = true
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 900 с")
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
	print("\n═════ ИТОГ qa_tz1031: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Строй: колонки по X, ряды по −Z от точки at (фронт смотрит в +Z)
func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int, sp: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0, at.z - float(i / cols) * sp))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _kill(men: Array) -> void:
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _immortal(u: Unit) -> void:
	u.max_health = 1e9
	u.current_health = 1e9
	u._soa_push_stats()

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h := 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for dz in [-30.0, 0.0, 30.0, 60.0, 80.0]:
				for dx in [-30.0, 0.0, 30.0]:
					var q: Vector3 = p + Vector3(dx, 0.0, dz)
					h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
					if GameManager.is_water(q.x, q.z) or GameManager.is_cliff(q.x, q.z) or not GameManager.is_passable(q.x, q.z):
						h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

func _clean() -> void:
	main._clear_area_of_resources(_base + Vector3(0, 0, 25), 90.0)
	main._clear_trees(_base + Vector3(0, 0, 25), 90.0)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead() and (u as Node3D).global_position.distance_to(_base + Vector3(0, 0, 25)) < 95.0:
			(u as Unit).take_damage(1e12)
	await pframes(20)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	for n2 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n2) and n2 is Unit and (n2 as Unit).faction != F:
			(n2 as Unit).set_tick(false)
	GameManager.troll_lair = null
	GameManager.pop_limit_enabled = false
	_base = _flat_spot(Vector3(-40.0, 0.0, -50.0))
	print("  площадка (%.0f, %.0f)" % [_base.x, _base.z])
	if "a" in _only:
		await _block_a()
	if "b" in _only:
		await _block_b()
	if "c" in _only:
		await _block_c()
	if "d" in _only:
		await _block_d()
	if "e" in _only:
		await _block_e()
	if "f" in _only:
		await _block_f()
	if "g" in _only:
		await _block_g()
	if "h" in _only:
		await _block_h()
	_finish()

# ── A. Погоня под замком ────────────────────────────────────────────────────
## Ответ: [доля под замком, дистанция центр-центр] в момент, когда цель ушла
## на far м от старта, и доля под замком после ухода за LOCK_CHASE_MAX
func _chase(knob: bool) -> Array:
	await _clean()
	_Opt.lock_chase = knob
	var ours: Array = _squad("warrior", F, _base, 10, 5, 0.7)
	var foes: Array = _squad("goblin_spearman", GF, _base + Vector3(0, 0, 5.0), 10, 5, 0.7)
	var men: Array = ours[1]
	var gs: Array = foes[1]
	for g in gs:
		_immortal(g as Unit)
		(g as Unit).set_tick(false)
	await pframes(5)
	for i in range(men.size()):
		(men[i] as Unit).command_attack(gs[i % gs.size()], true, false, true)
	var v: float = (men[0] as Unit).move_speed * 1.3
	var c_start: Vector3 = GameManager._centroid_of(men)
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var moved := 0.0
	var at25: Array = []
	var chase_end: float = Unit.LOCK_CHASE_MAX + 5.0
	var t := 0.0
	var adv := 0.0
	while adv < chase_end and t < 90.0:
		await get_tree().physics_frame
		t += dt
		if t < 3.0:
			continue
		moved += v * dt
		for g2 in gs:
			var gp: Vector3 = (g2 as Unit).global_position
			gp.z += v * dt
			gp.y = GameManager.get_terrain_height(gp.x, gp.z)
			(g2 as Unit).global_position = gp
			(g2 as Unit).sync_row()
		if _trace and int(t * 60.0) % 30 == 0:
			var u0: Unit = men[0]
			var tg = u0.attack_target
			print("      t=%.1f %s замок %s цель %s до цели %.1f от приказа %.1f atk_pending %s forced %s" % [t, Unit.State.keys()[u0.state], str(u0.target_lock), str(tg != null and is_instance_valid(tg)), u0.global_position.distance_to((gs[0] as Unit).global_position), Vector2(u0.global_position.x - u0._lock_from.x, u0.global_position.z - u0._lock_from.z).length() if u0._lock_from.x != INF else -1.0, str(u0._atk_pending), str(u0._attack_is_forced)])
		if int(t * 60.0) % 15 == 0:
			var al: Array = _alive(men)
			if al.is_empty() or _lock_share(men) == 0.0:
				break
			adv = GameManager._centroid_of(al).z - c_start.z
		if at25.is_empty() and moved >= 25.0:
			at25 = [_lock_share(men), GameManager._centroid_of(_alive(men)).z - c_start.z]
	var end_share: float = _lock_share(men)
	_kill(men)
	_kill(gs)
	_Opt.lock_chase = true
	return [at25[0] if not at25.is_empty() else 0.0, at25[1] if not at25.is_empty() else 0.0, end_share]

func _lock_share(men: Array) -> float:
	var a: Array = _alive(men)
	var k := 0
	for m in a:
		if (m as Unit).target_lock:
			k += 1
	return float(k) / float(maxi(a.size(), 1))

func _block_a() -> void:
	print("\n── A. Погоня под замком игрока ──")
	var on: Array = await _chase(true)
	var off: Array = await _chase(false)
	print("    ручка вкл: под замком %.2f, отряд прошёл %.1f м, после %.0f м — %.2f" % [on[0], on[1], Unit.LOCK_CHASE_MAX, on[2]])
	print("    ручка выкл: под замком %.2f, отряд прошёл %.1f м" % [off[0], off[1]])
	verdict("A1 цель ушла на 25 м (поводок %.0f м) — отряд гонит под замком" % Unit.PURSUIT_LIMIT, float(on[0]) >= 0.6 and float(on[1]) >= 12.0, "замок %.2f, прошёл %.1f м" % [on[0], on[1]])
	verdict("A2 за LOCK_CHASE_MAX от точки приказа замок снят", float(on[2]) <= 0.3, "под замком %.2f" % on[2])
	verdict("A0 без ручки — погоня обрывается у поводка", float(off[1]) < 10.0, "замок %.2f, прошёл %.1f м" % [off[0], off[1]])

# ── B. [A] в «Защите» ───────────────────────────────────────────────────────
func _am_def(knob: bool, with_foe: bool) -> Dictionary:
	await _clean()
	_Opt.am_keep_defense = knob
	var ours: Array = _squad("spearman", F, _base, 20, 5, 0.7)
	var men: Array = ours[1]
	var sid: int = int(ours[0])
	var gs: Array = []
	if with_foe:
		gs = _squad("goblin_spearman", GF, _base + Vector3(0, 0, 22.0), 12, 6, 0.7)[1]
		for g in gs:
			(g as Unit).set_tick(false)
	await pframes(5)
	var sm = main.selection_manager
	var cmd = sm._squad_cmd()
	sm.select_units(men)
	await pframes(2)
	sm.set_selection_stance("defense")
	await pframes(3)
	cmd.attack_move(sm, GameManager.land_target(_base + Vector3(0, 0, 45.0)))
	sm.clear_selection()
	var res := {"march_def": true, "arrived": false, "arr_def": false, "fought": false}
	var t := 0.0
	while t < 40.0:
		await pframes(30)
		t += 0.5
		var a: Array = _alive(men)
		if a.is_empty():
			break
		for m in a:
			if (m as Unit).state == Unit.State.ATTACKING:
				res["fought"] = true
		if cmd.is_attack_moving(sid):
			for m2 in a:
				if String((m2 as Unit).stance) != "defense":
					res["march_def"] = false
		elif t > 2.0:
			res["arrived"] = true
			var all_def := true
			for m3 in a:
				if String((m3 as Unit).stance) != "defense":
					all_def = false
			res["arr_def"] = all_def
			break
	if with_foe:
		var hurt := 0
		for g2 in gs:
			if not is_instance_valid(g2) or (g2 as Unit).is_dead() or (g2 as Unit).current_health < (g2 as Unit).max_health:
				hurt += 1
		res["foe_hurt"] = hurt
	_kill(men)
	_kill(gs)
	_Opt.am_keep_defense = true
	return res

func _block_b() -> void:
	print("\n── B. [A] в «Защите» ──")
	var on: Dictionary = await _am_def(true, false)
	var off: Dictionary = await _am_def(false, false)
	var fo: Dictionary = await _am_def(true, true)
	print("    вкл: %s; выкл: %s; со встречным: %s" % [str(on), str(off), str(fo)])
	verdict("B1 на марше [A] стойка «Защита» не снимается", bool(on["march_def"]))
	verdict("B2 по прибытии отряд стоит в «Защите»", bool(on["arrived"]) and bool(on["arr_def"]))
	verdict("B3 встречного отряд в «Защите» бьёт", bool(fo["fought"]) and int(fo.get("foe_hurt", 0)) > 0, "задето врагов %d" % int(fo.get("foe_hurt", 0)))
	verdict("B0 без ручки — на марш «Защита» снимается (прежнее)", not bool(off["march_def"]))

# ── C. Смыкание по рядам ────────────────────────────────────────────────────
## Отряд 5×4 с разметкой курсом +Z рассыпан в пятно; смыкание с force.
## Инверсия — пара, где шедший впереди (> 0.6 м по курсу) встал позади (> 0.3 м)
func _ranks(knob: bool) -> Array:
	await _clean()
	_Opt.rank_match = knob
	var ours: Array = _squad("spearman", F, _base, 20, 5, 0.7)
	var sid: int = int(ours[0])
	var men: Array = ours[1]
	var course := Vector3(0, 0, 1)
	var slots: Array = []
	for i in range(20):
		var sx: float = (float(i % 5) - 2.0) * 0.7
		var sz: float = 10.0 - float(i / 5) * 0.7
		slots.append(Vector3(_base.x + sx, GameManager.get_terrain_height(_base.x + sx, _base.z + sz), _base.z + sz))
	GameManager.squad_set_formation(sid, slots, course, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31102026
	for m in men:
		var p := Vector3(_base.x + rng.randf_range(-3.0, 3.0), 0, _base.z + 8.0 + rng.randf_range(-2.5, 2.5))
		p.y = GameManager.get_terrain_height(p.x, p.z)
		(m as Unit).global_position = p
		(m as Unit).sync_row()
		(m as Unit).post_pos = p
	await pframes(10)
	var p0: Array = []
	for m2 in men:
		p0.append((m2 as Unit).global_position)
	GameManager.squad_close_ranks(sid, true)
	await pframes(60 * 8)
	var inv := 0
	for i in range(men.size()):
		for j in range(men.size()):
			if i == j:
				continue
			var a0: float = (p0[i] as Vector3).dot(course) - (p0[j] as Vector3).dot(course)
			var a1: float = (men[i] as Unit).global_position.dot(course) - (men[j] as Unit).global_position.dot(course)
			if a0 > 0.6 and a1 < -0.3:
				inv += 1
	var sl: Array = (GameManager.squads[sid] as Dictionary).get("slots", [])
	var on_slot := 0
	for m3 in men:
		var best := INF
		for s in sl:
			best = minf(best, Vector2((m3 as Unit).global_position.x - (s as Vector3).x, (m3 as Unit).global_position.z - (s as Vector3).z).length())
		if best < 0.9:
			on_slot += 1
	_kill(men)
	_Opt.rank_match = true
	return [inv, float(on_slot) / float(men.size())]

func _block_c() -> void:
	print("\n── C. Смыкание по рядам ──")
	var on: Array = await _ranks(true)
	var off: Array = await _ranks(false)
	print("    вкл: инверсий %d, на местах %.2f; выкл: инверсий %d, на местах %.2f" % [on[0], on[1], off[0], off[1]])
	verdict("C1 смыкание по рядам — шедший впереди не уходит за шедшего позади", int(on[0]) == 0, "инверсий %d" % on[0])
	verdict("C2 отряд собран на местах разметки", float(on[1]) >= 0.85, "доля %.2f" % on[1])
	verdict("C0 без ручки — жадная раздача даёт инверсии", int(off[0]) > 0, "инверсий %d" % off[0])

# ── D. [A] на марше не смыкается ────────────────────────────────────────────
func _am_reform(knob: bool) -> Array:
	await _clean()
	_Opt.am_no_reform = knob
	var ours: Array = _squad("spearman", F, _base, 20, 5, 0.7)
	var sid: int = int(ours[0])
	var men: Array = ours[1]
	await pframes(5)
	var sm = main.selection_manager
	var cmd = sm._squad_cmd()
	sm.select_units(men)
	await pframes(2)
	cmd.attack_move(sm, GameManager.land_target(_base + Vector3(0, 0, 60.0)))
	sm.clear_selection()
	await pframes(60 * 4)
	var ok: bool = GameManager.squad_close_ranks(sid, true)
	var p0: Array = []
	for m in men:
		p0.append((m as Unit).global_position)
	await pframes(60)
	var back := 0
	for i in range(men.size()):
		if (men[i] as Unit).global_position.z - (p0[i] as Vector3).z < -0.3:
			back += 1
	_kill(men)
	_Opt.am_no_reform = true
	return [ok, back]

func _block_d() -> void:
	print("\n── D. [A] на марше не смыкается ──")
	var on: Array = await _am_reform(true)
	var off: Array = await _am_reform(false)
	print("    вкл: смыкание %s, назад %d; выкл: смыкание %s, назад %d" % [str(on[0]), on[1], str(off[0]), off[1]])
	verdict("D1 смыкание отряда на марше [A] отклонено", not bool(on[0]))
	verdict("D2 после попытки смыкания никто не идёт назад", int(on[1]) == 0, "назад %d" % on[1])
	verdict("D0 без ручки — смыкание на марше проходит", bool(off[0]))

# ── E. Монахи одного отряда ─────────────────────────────────────────────────
func _monks(knob: bool) -> float:
	await _clean()
	_Opt.monk_spacing_own_squad = knob
	var ours: Array = _squad("monk", F, _base, 8, 4, 0.7)
	var men: Array = ours[1]
	await pframes(10)
	var p0: Array = []
	for m in men:
		p0.append((m as Unit).global_position)
	await pframes(60 * 8)
	var mx := 0.0
	for i in range(men.size()):
		mx = maxf(mx, (men[i] as Unit).global_position.distance_to(p0[i]))
	_kill(men)
	_Opt.monk_spacing_own_squad = true
	return mx

func _block_e() -> void:
	print("\n── E. Монахи одного отряда ──")
	var on: float = await _monks(true)
	var off: float = await _monks(false)
	print("    макс. смещение монаха: вкл %.2f м, выкл %.2f м" % [on, off])
	verdict("E1 монахи отряда стоят в строю, не расходятся", on < 0.5, "%.2f м" % on)
	verdict("E0 без ручки — расстановка разводит монахов отряда", off > 1.0, "%.2f м" % off)

# ── F. Строй по месту ───────────────────────────────────────────────────────
## Разметка 5×4 курсом +Z на исходной линии; отряд стоит колонкой на 20 м
## впереди (растянут на 9 м по курсу). force — смыкание после боя; иначе —
## по потерям (выбит каждый четвёртый). Ответ: [ушли назад > 1 м, центр
## разметки после смыкания − центр людей до него по курсу]
func _front(knob: bool, force: bool) -> Array:
	await _clean()
	_Opt.reform_front_anchor = knob
	var ours: Array = _squad("spearman", F, _base, 20, 5, 0.7)
	var sid: int = int(ours[0])
	var men: Array = ours[1]
	var course := Vector3(0, 0, 1)
	var slots: Array = []
	for i in range(20):
		var sx: float = (float(i % 5) - 2.0) * 0.7
		var sz: float = -float(i / 5) * 0.7
		slots.append(Vector3(_base.x + sx, GameManager.get_terrain_height(_base.x + sx, _base.z + sz), _base.z + sz))
	GameManager.squad_set_formation(sid, slots, course, false)
	(GameManager.squads[sid] as Dictionary)["at_order"] = 20
	for i2 in range(men.size()):
		var p := Vector3(_base.x + (float(i2 % 3) - 1.0) * 0.8, 0, _base.z + 20.0 + float(i2) * 0.45)
		p.y = GameManager.get_terrain_height(p.x, p.z)
		(men[i2] as Unit).global_position = p
		(men[i2] as Unit).sync_row()
		(men[i2] as Unit).post_pos = p
	await pframes(10)
	if not force:
		for k in range(0, men.size(), 4):
			(men[k] as Unit).take_damage(1e12)
		await pframes(4)
	var live: Array = _alive(men)
	var z0: Dictionary = {}
	var zc := 0.0
	for m in live:
		z0[m] = (m as Unit).global_position.z
		zc += (m as Unit).global_position.z
	zc /= float(maxi(live.size(), 1))
	if force:
		GameManager.squad_close_ranks(sid, true)
	await pframes(60 * 8)
	var back := 0
	for m2 in live:
		if is_instance_valid(m2) and (m2 as Unit).global_position.z < float(z0[m2]) - 1.0:
			back += 1
	var sl: Array = (GameManager.squads[sid] as Dictionary).get("slots", [])
	var sc := 0.0
	for s0 in sl.slice(0, live.size()):
		sc += (s0 as Vector3).z
	sc /= float(maxi(mini(sl.size(), live.size()), 1))
	_kill(men)
	_Opt.reform_front_anchor = true
	return [back, sc - zc, live.size()]

func _block_f() -> void:
	print("
── F. Строй после боя — по месту, передней кромкой ──")
	var on: Array = await _front(true, true)
	var off: Array = await _front(false, true)
	var lon: Array = await _front(true, false)
	var loff: Array = await _front(false, false)
	print("    после боя: вкл назад %d из %d, сдвиг строя %.1f м; выкл назад %d, сдвиг %.1f м" % [on[0], on[2], on[1], off[0], off[1]])
	print("    по потерям: вкл назад %d из %d, сдвиг %.1f м; выкл назад %d, сдвиг %.1f м" % [lon[0], lon[2], lon[1], loff[0], loff[1]])
	verdict("F1 смыкание растянутого отряда — назад идут единицы", int(on[0]) <= int(ceil(float(on[2]) * 0.15)), "назад %d из %d" % [on[0], on[2]])
	verdict("F2 строй встаёт не позади центра людей", float(on[1]) >= -0.5, "сдвиг %.1f м" % on[1])
	verdict("F0 без ручки — строй по центру масс, передние идут назад", int(off[0]) > int(on[0]), "назад %d против %d" % [off[0], on[0]])
	verdict("F3 смыкание по потерям у ушедшего отряда — по месту, не на исходной линии", float(lon[1]) > -3.0 and int(lon[0]) <= int(ceil(float(lon[2]) * 0.2)), "сдвиг %.1f м, назад %d" % [lon[1], lon[0]])
	verdict("F4 без ручки — после потерь передние идут назад", int(loff[0]) > int(lon[0]), "назад %d против %d" % [loff[0], lon[0]])

# ── G. Обрыв поводка без возврата ───────────────────────────────────────────
## Отряд «вольно» берёт по авто-агро одиночку в 4 м; тот уходит бегом дальше
## поводка. Ответ: насколько отряд отошёл назад от самой дальней точки погони
func _leash(knob: bool) -> Array:
	await _clean()
	_Opt.leash_hold_here = knob
	var ours: Array = _squad("warrior", F, _base, 8, 4, 0.7)
	var men: Array = ours[1]
	var sm = main.selection_manager
	sm.select_units(men)
	await pframes(2)
	sm.set_selection_stance("attack")
	sm.clear_selection()
	var g: Unit = _spawn("goblin_spearman", GF, _base + Vector3(0, 0, 4.5))
	GameManager.add_to_squad(GameManager.new_squad(GF, "goblin_spearman"), g)
	_immortal(g)
	g.set_tick(false)
	var v: float = (men[0] as Unit).move_speed * 1.3
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var zmax := -INF
	var t := 0.0
	var breaks0: int = Unit.chase_breaks
	while t < 14.0:
		await get_tree().physics_frame
		t += dt
		if t > 3.0 and t < 9.0:
			var gp: Vector3 = g.global_position
			gp.z += v * dt
			gp.y = GameManager.get_terrain_height(gp.x, gp.z)
			g.global_position = gp
			g.sync_row()
		var a: Array = _alive(men)
		if not a.is_empty():
			zmax = maxf(zmax, GameManager._centroid_of(a).z)
	var zf: float = GameManager._centroid_of(_alive(men)).z
	var brk: int = Unit.chase_breaks - breaks0
	_kill(men)
	_kill([g])
	_Opt.leash_hold_here = true
	return [zmax - zf, zmax - _base.z, brk]

func _block_g() -> void:
	print("
── G. Обрыв поводка погони ──")
	var on: Array = await _leash(true)
	var off: Array = await _leash(false)
	print("    вкл: погоня %.1f м, назад %.1f м, обрывов %d; выкл: погоня %.1f м, назад %.1f м, обрывов %d" % [on[1], on[0], on[2], off[1], off[0], off[2]])
	verdict("G1 поводок оборвал погоню", int(on[2]) > 0, "обрывов %d" % on[2])
	verdict("G2 после обрыва отряд не уходит назад к якорю", float(on[0]) < 2.0, "назад %.1f м" % on[0])
	verdict("G0 без ручки — возврат к якорю", float(off[0]) > 4.0, "назад %.1f м" % off[0])

# ── H. Строй после боя ──────────────────────────────────────────────────────
## Доля живых в 0.9 м от ячейки своей разметки и худший отрыв от медианы
func _on_slots(sid: int, men: Array) -> Array:
	var sl: Array = (GameManager.squads[sid] as Dictionary).get("slots", [])
	var a: Array = _alive(men)
	var ok := 0
	var c: Vector3 = GameManager._centroid_of(a)
	var worst := 0.0
	for m in a:
		var p: Vector3 = (m as Unit).global_position
		worst = maxf(worst, Vector2(p.x - c.x, p.z - c.z).length())
		var best := INF
		for s0 in sl:
			best = minf(best, Vector2(p.x - (s0 as Vector3).x, p.z - (s0 as Vector3).z).length())
		if best <= 0.9:
			ok += 1
	return [float(ok) / float(maxi(a.size(), 1)), worst, a.size()]

## Отряд 12 мечников в разметке 4×3 курсом +Z; whole — ПКМ всем отрядом по
## рассыпанным на 12 м слабым гоблинам; иначе один боец гонит одиночку.
## Ответ: [доля на ячейках, худший отрыв, живых, сдвинулось соседей > 1 м]
func _form_up(knob: bool, whole: bool, flee: bool = false) -> Array:
	await _clean()
	_Opt.idle_form_up = knob
	var ours: Array = _squad("warrior", F, _base, 12, 4, 0.7)
	var sid: int = int(ours[0])
	var men: Array = ours[1]
	var slots: Array = []
	for u0 in men:
		slots.append((u0 as Unit).global_position)
	GameManager.squad_set_formation(sid, slots, Vector3(0, 0, 1), false)
	(GameManager.squads[sid] as Dictionary)["at_order"] = men.size()
	await pframes(30)
	var gsid: int = GameManager.new_squad(GF, "goblin_spearman")
	var gs: Array = []
	var spots: Array = [Vector3(-6, 0, 6), Vector3(5, 0, 9), Vector3(-2, 0, 12), Vector3(7, 0, 4), Vector3(-8, 0, 11), Vector3(1, 0, 15)]
	if not whole:
		spots = [Vector3(-0.35, 0, 6.5)]
	if flee:
		spots = [Vector3(-3, 0, 4.0), Vector3(-1, 0, 4.5), Vector3(1, 0, 4.0), Vector3(3, 0, 4.5)]
	for o in spots:
		var g: Unit = _spawn("goblin_spearman", GF, _base + (o as Vector3))
		GameManager.add_to_squad(gsid, g)
		g.set_tick(false)
		g.current_health = 1.0
		g._soa_push_stats()
		gs.append(g)
	await pframes(4)
	var p0: Dictionary = {}
	for m in men:
		p0[m] = (m as Unit).global_position
	var chaser: Unit = men[1]
	if flee:
		# «Вольно»: авто-агро берёт уходящих, поводок обрывает погоню без контакта
		var sm = main.selection_manager
		sm.select_units(men)
		await pframes(2)
		sm.set_selection_stance("attack")
		sm.clear_selection()
		for g2 in gs:
			_immortal(g2 as Unit)
		var v: float = (men[0] as Unit).move_speed * 1.3
		var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
		var tt := 0.0
		while tt < 9.0:
			await get_tree().physics_frame
			tt += dt
			if tt > 1.0:
				for k in range(gs.size()):
					var gg: Unit = gs[k]
					var gp: Vector3 = gg.global_position
					gp.z += v * dt
					gp.x += (float(k) - 1.5) * 0.25 * v * dt
					gp.y = GameManager.get_terrain_height(gp.x, gp.z)
					gg.global_position = gp
					gg.sync_row()
		_kill(gs)
	elif whole:
		for i in range(men.size()):
			(men[i] as Unit).command_attack(gs[i % gs.size()], true, false, true)
	else:
		chaser.command_attack(gs[0], true, false, true)
	var t := 0
	while t < 60 * 12 and not _alive(gs).is_empty():
		await get_tree().physics_frame
		t += 1
	var killed: bool = _alive(gs).is_empty()
	await pframes(60 * 10)
	var r: Array = _on_slots(sid, men)
	var moved := 0
	if not whole:
		for m2 in _alive(men):
			if m2 != chaser and (m2 as Unit).global_position.distance_to(p0[m2]) > 1.0:
				moved += 1
	r.append(moved)
	r.append(killed)
	_kill(men)
	_kill(gs)
	_Opt.idle_form_up = true
	return r

## Состояние «бой кончился, разовое смыкание отказало»: отряд рассыпан в
## пределах своего габарита, у каждого пост «где стою» (_hold_loose). Ответ — _on_slots
func _loose_idle(knob: bool) -> Array:
	await _clean()
	_Opt.idle_form_up = knob
	var ours: Array = _squad("warrior", F, _base, 12, 4, 0.7)
	var sid: int = int(ours[0])
	var men: Array = ours[1]
	var slots: Array = []
	for u0 in men:
		slots.append((u0 as Unit).global_position)
	GameManager.squad_set_formation(sid, slots, Vector3(0, 0, 1), false)
	await pframes(30)
	for i in range(men.size()):
		var u: Unit = men[i]
		var p := Vector3(_base.x + sin(float(i) * 2.4) * 2.2, 0.0, _base.z - 0.7 + cos(float(i) * 1.7) * 1.8)
		p.y = GameManager.get_terrain_height(p.x, p.z)
		u.global_position = p
		u.sync_row()
		u.velocity = Vector3.ZERO
		u.state = Unit.State.IDLE
		u._hold_loose()
	await pframes(60 * 8)
	var r: Array = _on_slots(sid, men)
	_kill(men)
	_Opt.idle_form_up = true
	return r

func _block_h() -> void:
	print("
── H. Строй после боя: догнал, уничтожил — собрался ──")
	var on: Array = await _form_up(true, true)
	var off: Array = await _form_up(false, true)
	var one: Array = await _form_up(true, false)
	var one_off: Array = await _form_up(false, false)
	var li: Array = await _loose_idle(true)
	var li_off: Array = await _loose_idle(false)
	print("    покой с постами «где стою»: вкл на ячейках %.0f %%, выкл %.0f %%" % [li[0] * 100.0, li_off[0] * 100.0])
	verdict("H6 покой после боя с постами «где стою» — отряд собирается в строй", float(li[0]) >= 0.99, "на ячейках %.0f %%" % (li[0] * 100.0))
	verdict("H0 без ручки — россыпь так и стоит", float(li_off[0]) < 0.9, "на ячейках %.0f %%" % (li_off[0] * 100.0))
	var fl: Array = await _form_up(true, true, true)
	var fl_off: Array = await _form_up(false, true, true)
	print("    погоня без контакта: вкл на ячейках %.0f %%, отрыв %.1f м; выкл %.0f %%, отрыв %.1f м" % [fl[0] * 100.0, fl[1], fl_off[0] * 100.0, fl_off[1]])
	verdict("H5 оборванная погоня «вольно» — отряд собрался в строй", float(fl[0]) >= 0.99 and float(fl[1]) <= 3.0, "на ячейках %.0f %%, отрыв %.1f м" % [fl[0] * 100.0, fl[1]])
	print("    весь отряд: вкл на ячейках %.0f %%, отрыв %.1f м (враг выбит %s); выкл %.0f %%, отрыв %.1f м" % [on[0] * 100.0, on[1], on[4], off[0] * 100.0, off[1]])
	print("    один боец: вкл на ячейках %.0f %%, отрыв %.1f м (враг выбит %s; в бой вступил отряд — сдвинулось %d); выкл %.0f %%" % [one[0] * 100.0, one[1], one[4], one[3], one_off[0] * 100.0])
	verdict("H1 весь отряд после боя стоит строем — каждый на ячейке", bool(on[4]) and float(on[0]) >= 0.99, "на ячейках %.0f %%" % (on[0] * 100.0))
	verdict("H2 строй цельный — нет оторвавшихся", float(on[1]) <= 3.0, "отрыв %.1f м" % on[1])
	verdict("H3 гнался один — вернулся в свою ячейку", bool(one[4]) and float(one[0]) >= 0.99, "на ячейках %.0f %%" % (one[0] * 100.0))
	verdict("H4 гнался один — после боя строй цельный", float(one[1]) <= 3.0, "отрыв %.1f м" % one[1])
