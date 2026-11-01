extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 29.10.2026 (пакет «победа, курсоры, паника, [S]+[A], фаланга»)
## ═══════════════════════════════════════════════════════════════════════════
## P — ПАНИКА (п. 3):
##   P1 беглец упёрся в чужой строй — просачивается сквозь него, бег не гаснет;
##   P2 беглец у глухого препятствия (лес) — меняет вектор, не бежит на месте;
##   P3 отряд, завершивший бегство, неуправляем: выпадает из выделения и
##      групп Ctrl+N, не выделяется; после выхода из лазарета — снова свой.
## Запуск: godot --headless --path . res://qa_tz1029/Test.tscn [-- only=p]

const F := Constants.FACTION_PLAYER
const _Opt := preload("res://scripts/perf_config.gd")
const G := Constants.FACTION_GOBLIN

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "p"
var _done := false
## Блок S: изучена «Фаланга», расстояние до волны, отрядов, волна напала до [A]
var _s_ph := false
var _s_near := 22.0
var _s_nsq := 2
var _s_eng := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
		elif s == "ph=1":
			_s_ph = true
		elif s.begins_with("near="):
			_s_near = float(s.substr(5))
		elif s.begins_with("nsq="):
			_s_nsq = int(s.substr(4))
		elif s == "eng=1":
			_s_eng = true
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_tz1029: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, at: Vector3, n: int, fac: int = F, cols: int = 6, step: float = 0.8) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k / cols) * step, 0, float(k % cols) * step), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _clear(at: Vector3, r: float, trees: bool = true) -> void:
	if trees:
		main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and (b as Node3D).global_position.distance_to(at) < r and not (b as Building).is_stronghold():
			b.queue_free()

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager", "boss_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "p" in _only:
		await _p1_bodies()
		await _p2_obstacle()
		await _p3_control()
	if "s" in _only:
		await _s_defense_am()
	if "f" in _only:
		await _f_shove("F1", true)
		await _f_shove("F2", false)
	_finish()

## Окна по 1 с: боец в MOVING, сместившийся меньше RIP_STEP, — «бег на месте»;
## возвращает наибольшую серию окон подряд по отряду
const RIP_STEP := 0.25
func _watch(men: Array, sec: float) -> Dictionary:
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
				var mv: float = Vector2(p.x - lp.x, p.z - lp.z).length()
				if u.state == Unit.State.MOVING and mv < RIP_STEP:
					run[k] = int(run.get(k, 0)) + 1
					worst = maxi(worst, int(run[k]))
				else:
					run[k] = 0
			last[k] = p
	return {"worst": worst}

func _p1_bodies() -> void:
	print("\n═════ P1. Паникующий упёрся в чужой строй ═════")
	var at := Vector3(-60, 0, -40)
	_clear(at, 60.0)
	await pframes(5)
	var men: Array = _squad("spearman", at, 12, F, 6)
	# Чужой строй поперёк пути: три шеренги гоблинов, замороженных
	# (тела в ядре есть, ударов нет)
	var wall_x: float = at.x + 6.0
	var foes: Array = _squad("goblin_spearman", Vector3(wall_x, 0, at.z - 4.0), 36, G, 12, 0.75)
	for f in foes:
		(f as Unit).set_tick(false)
	await pframes(10)
	var far_x: float = wall_x + 3.0
	for k in range(men.size()):
		var u := men[k] as Unit
		u.panic_flee(Vector3(at.x + 24.0, 0, at.z + float(k % 6) * 0.8))
	var w: Dictionary = await _watch(men, 10.0)
	var crossed := 0
	var running := 0
	for m in men:
		var u2 := m as Unit
		if u2.global_position.x > far_x:
			crossed += 1
		if u2.sprinting or u2.state != Unit.State.MOVING:
			running += 1
	verdict("P1a беглецы прошли сквозь чужой строй", crossed == men.size(), "%d из %d за строем" % [crossed, men.size()])
	verdict("P1b бег не гаснет у чужих тел (бежит или дошёл)", running == men.size(), "%d из %d" % [running, men.size()])
	verdict("P1c нет бега на месте (серия окон по 1 с не больше 1)", int(w["worst"]) <= 1, "худшая серия %d" % int(w["worst"]))
	_free(men)
	_free(foes)
	await pframes(5)

## Клетка леса (непроходимая), от которой в 10 м есть чистая проходимая площадка
func _forest_spot() -> Array:
	var lx: float = GameManager.map_lim_x - 30.0
	var lz: float = GameManager.map_lim_z - 30.0
	var x := -lx
	while x < lx:
		var z := -lz
		while z < lz:
			if not GameManager.is_passable(x, z):
				for d in [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]:
					var s: Vector3 = Vector3(x, 0, z) - d * 10.0
					var ok := true
					for r in range(9):
						var q: Vector3 = s + Vector3(float(r % 3 - 1) * 2.0, 0, float(r / 3 - 1) * 2.0)
						if not GameManager.is_passable(q.x, q.z):
							ok = false
					if ok:
						return [Vector3(x, 0, z), s, d]
			z += 6.0
		x += 6.0
	return []

func _p2_obstacle() -> void:
	print("\n═════ P2. Паникующий у глухого препятствия ═════")
	var spot: Array = _forest_spot()
	if spot.is_empty():
		verdict("P2 нашлась клетка леса", false)
		return
	var wall: Vector3 = spot[0]
	var s: Vector3 = spot[1]
	var d: Vector3 = spot[2]
	print("  лес (%.0f, %.0f), старт (%.0f, %.0f)" % [wall.x, wall.z, s.x, s.z])
	_clear(s, 6.0, false)
	await pframes(5)
	var men: Array = _squad("spearman", s - Vector3(1.0, 0, 1.0), 8, F, 4)
	await pframes(10)
	var turns0: int = Unit.panic_turns
	for k in range(men.size()):
		(men[k] as Unit).panic_flee(wall + d * 4.0)
	var w: Dictionary = await _watch(men, 8.0)
	var moved := 0
	for m in men:
		if (m as Unit).global_position.distance_to(s) > 2.0:
			moved += 1
	print("  поворотов бегства %d" % (Unit.panic_turns - turns0))
	verdict("P2a нет бега на месте у леса (серия окон по 1 с не больше 1)", int(w["worst"]) <= 1, "худшая серия %d" % int(w["worst"]))
	verdict("P2b беглецы ушли со старта", moved >= men.size() - 1, "%d из %d дальше 2 м" % [moved, men.size()])
	_free(men)
	await pframes(5)

func _p3_control() -> void:
	print("\n═════ P3. Отступивший после паники неуправляем ═════")
	var base := Vector3(-110, 0, 40)
	_clear(base, 50.0)
	await pframes(3)
	var c: Building = Castle.new()
	c.faction = F
	main.world_add(c)
	c.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z)
	await pframes(10)
	var men: Array = _squad("spearman", base + Vector3(24, 0, 0), 10, F, 5)
	var sid: int = (men[0] as Unit).squad_id
	await pframes(5)
	var sm = main.selection_manager
	sm.select_units(men)
	sm._save_group(0)
	var sel0: int = sm.selected_units.size()
	GameManager._start_panic(sid)
	await pframes(30)
	GameManager._end_panic(sid)
	await pframes(3)
	var in_sel := 0
	var in_grp := 0
	for m in men:
		if m in sm.selected_units:
			in_sel += 1
		if m in sm._groups[0]:
			in_grp += 1
	verdict("P3a отряд вне управления", GameManager.squad_no_control(sid))
	verdict("P3b выпал из выделения", sel0 == men.size() and in_sel == 0, "было %d, осталось %d" % [sel0, in_sel])
	verdict("P3c выпал из группы Ctrl+1", in_grp == 0, "в группе %d" % in_grp)
	sm.select_units(men)
	verdict("P3d клик не выделяет", sm.selected_units.size() == 0, "выделено %d" % sm.selected_units.size())
	var t := 0
	var inside := false
	while t < 60 * 60:
		await pframes(30)
		t += 30
		if (c as Castle)._slot_of(sid) >= 0:
			inside = true
			break
	verdict("P3e дошёл в замок сам", inside, "через %.1f с" % (float(t) / 60.0))
	if inside:
		(c as Castle).release_garrison(sid)
		await pframes(10)
		sm.select_units(men)
		verdict("P3f после лазарета снова выделяется", sm.selected_units.size() > 0 and not GameManager.squad_no_control(sid), "выделено %d" % sm.selected_units.size())
	sm.clear_selection()
	_free(men)
	await pframes(5)

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	for m in men:
		c += (m as Node3D).global_position
	return c / float(maxi(men.size(), 1))

## Строй отряда по ПКМ (настоящая разметка): ждём, пока 90 % встанут
func _form(kind: String, at: Vector3, n: int) -> Array:
	var men: Array = _squad(kind, at + Vector3(-8, 0, 0), n, F, 10)
	await pframes(5)
	var sm = main.selection_manager
	sm.select_units(men)
	sm.order_at_world(at, false)
	sm.clear_selection()
	var t := 0
	while t < 900:
		await pframes(15)
		t += 15
		var home := 0
		for m in _alive(men):
			var u := m as Unit
			if u.global_position.distance_to(u.post_pos) < 2.0 and u.state == Unit.State.IDLE:
				home += 1
		if home >= int(0.9 * float(men.size())):
			break
	return men

## Ширина отряда поперёк хода (ось Z) по 10-90 перцентилям
func _width(men: Array) -> float:
	var zs: Array = []
	for m in men:
		zs.append((m as Node3D).global_position.z)
	if zs.size() < 3:
		return 0.0
	zs.sort()
	return float(zs[int(zs.size() * 0.9)]) - float(zs[int(zs.size() * 0.1)])

## S — [S] Защита, затем [A] через волну орды (п. 4)
func _s_defense_am() -> void:
	print("
═════ S. Копейщики в [S], затем [A] через волну ═════")
	var at := Vector3(-60, 0, 20)
	_clear(at, 70.0)
	await pframes(5)
	if _s_ph:
		GameManager.finish_research(F, "spearman_1d")
	print("  фаланга %s, волна в %.0f м, отрядов %d, волна напала до [A] %s" % [_s_ph, _s_near, _s_nsq, _s_eng])
	var a: Array = await _form("spearman", at, 30)
	var b: Array = await _form("spearman", at + Vector3(0, 0, 12), 30)
	var extra: Array = []
	for q in range(2, _s_nsq):
		extra += await _form("spearman", at + Vector3(0, 0, 12.0 * float(q)), 30)
	var sids: Array = [(a[0] as Unit).squad_id, (b[0] as Unit).squad_id]
	var sm = main.selection_manager
	sm.select_units(a + b + extra)
	sm.set_selection_stance("defense")
	sm.clear_selection()
	await pframes(60)
	var w0: Array = [_width(a), _width(b)]
	var gap0: float = absf(_centre(b).z - _centre(a).z)
	var wave: Array = _squad("goblin_spearman", at + Vector3(_s_near, 0, 0), 30, G, 6)
	for g in wave:
		(g as Unit).current_health = (g as Unit).max_health * 0.5
	await pframes(5)
	if _s_eng:
		var kk := 0
		for g in wave:
			(g as Unit).command_attack((a + b)[kk % 60], true)
			kk += 1
		await pframes(180)
	var dest: Vector3 = at + Vector3(_s_near + 18.0, 0, 6)
	sm.select_units(a + b + extra)
	sm.order_at_world(dest, true)
	sm.clear_selection()
	var sc = sm._squad_commander
	_Opt.cmd_meter = true
	_Opt.cmd_reset()
	var maxx: Array = [-INF, -INF]
	var worst_back: Array = [0.0, 0.0]
	var worst_w: Array = [0.0, 0.0]
	var back_men := 0
	var last: Dictionary = {}
	var t := 0
	var t_dead := -1
	var stances: String = ""
	while t < 60 * 60:
		await pframes(30)
		t += 30
		var aw: Array = _alive(wave)
		# Волна сломлена: не осталось ни одного сражающегося (бегущих в
		# панике отряд не преследует — ТЗ 29.10.2026, п. 4)
		var fighters := 0
		for g3 in aw:
			if not (g3 as Unit).is_panicked():
				fighters += 1
		if fighters == 0 and t_dead < 0:
			t_dead = t
		var groups: Array = [_alive(a), _alive(b)]
		for k in range(2):
			var g: Array = groups[k]
			if g.is_empty():
				continue
			var c: Vector3 = _centre(g)
			var x: float = c.x - at.x
			maxx[k] = maxf(maxx[k], x)
			if t_dead < 0:
				worst_back[k] = maxf(worst_back[k], maxx[k] - x)
			var wdt: float = _width(g)
			worst_w[k] = maxf(worst_w[k], wdt)
		# Боец, отступивший назад больше 0.8 м за полсекунды без врага за спиной
		for m in _alive(a + b):
			var u := m as Unit
			var key: int = u.get_instance_id()
			var px: float = u.global_position.x
			if last.has(key) and float(last[key]) - px > 0.8 and t_dead < 0:
				back_men += 1
			last[key] = px
		if t % 120 == 0:
			var st: Dictionary = {}
			for m in _alive(a + b):
				var s2: String = "%s/%d" % [String((m as Unit).stance), int((m as Unit).state)]
				st[s2] = int(st.get(s2, 0)) + 1
			print("    t=%.0f c1=%.1f c2=%.1f w=%.1f/%.1f волна %d am=%s/%s %s" % [float(t) / 60.0,
				_centre(groups[0]).x - at.x, _centre(groups[1]).x - at.x, _width(groups[0]), _width(groups[1]),
				aw.size(), sc.is_attack_moving(sids[0]), sc.is_attack_moving(sids[1]), str(st)])
			if aw.size() <= 4 and aw.size() > 0:
				var fx: Array = []
				for g2 in aw:
					var gp: Vector3 = (g2 as Node3D).global_position - at
					fx.append("(%.1f,%.1f st%d)" % [gp.x, gp.z, int((g2 as Unit).state)])
				var u0 := groups[0][0] as Unit
				var mt: Vector3 = u0.move_target - at
				print("      враги %s; боец0 mt=(%.1f,%.1f) tgt=%s; приказы: %s" % [" ".join(fx), mt.x, mt.z,
					str(u0.attack_target != null), str(_Opt.cmd_sid_report().filter(func(r): return int(r[1]) == int(sids[0])))])
		if t_dead > 0 and t > t_dead + 900:
			break
	var gap1: float = absf(_centre(_alive(b)).z - _centre(_alive(a)).z)
	print("  ширина до [A] %.1f/%.1f, худшая %.1f/%.1f; зазор отрядов %.1f → %.1f" % [w0[0], w0[1], worst_w[0], worst_w[1], gap0, gap1])
	verdict("S1 волна сломлена (сражающихся не осталось)", t_dead > 0, "за %.1f с" % (float(t_dead) / 60.0))
	verdict("S2 нет отката центра назад (до 2 м)", maxf(worst_back[0], worst_back[1]) <= 2.0, "%.1f / %.1f м" % [worst_back[0], worst_back[1]])
	verdict("S3 строй не разъезжается (ширина не больше 1.6 исходной)", worst_w[0] <= w0[0] * 1.6 + 1.0 and worst_w[1] <= w0[1] * 1.6 + 1.0, "%.1f/%.1f при %.1f/%.1f" % [worst_w[0], worst_w[1], w0[0], w0[1]])
	verdict("S4 отряды не разъехались (зазор ±50 %)", gap1 <= gap0 * 1.5 + 2.0 and gap1 >= gap0 * 0.5 - 2.0, "%.1f → %.1f" % [gap0, gap1])
	verdict("S5 бойцов, пятившихся назад до конца волны, мало", back_men <= 3, "%d окон" % back_men)
	var cx: float = minf(_centre(_alive(a)).x, _centre(_alive(b)).x) - at.x
	verdict("S6 отряды прошли за волну", cx > _s_near + 2.0, "центр %.1f м (волна на %.0f)" % [cx, _s_near])
	_free(extra)
	_free(a)
	_free(b)
	_free(wave)
	await pframes(5)

## F — НАТИСК ФАЛАНГИ (п. 5): отряд копейщиков рубится с отрядом орды, игрок
## даёт двойной ПКМ по врагу (приказ атаки + приём). F1 — новый натиск,
## F2 — прежнее поведение (ручка phalanx_shove выключена: смыкание рядов
## после приказа атаки) как контроль
var _f_ctrl: Dictionary = {}
func _f_shove(tag: String, on: bool) -> void:
	print("
═════ %s. Натиск фаланги в замесе (%s) ═════" % [tag, "новый" if on else "прежний, контроль"])
	_Opt.phalanx_shove = on
	GameManager.finish_research(F, "spearman_4d")
	var at := Vector3(-60, 0, 60)
	_clear(at, 50.0)
	await pframes(5)
	var men: Array = await _form("spearman", at, 30)
	var foes: Array = _squad("goblin_spearman", at + Vector3(3.5, 0, -1.0), 30, G, 6, 0.9)
	await pframes(5)
	var sm = main.selection_manager
	for k in range(men.size()):
		(men[k] as Unit).command_attack(foes[k % foes.size()], true, false, true)
	for g in foes:
		(g as Unit).command_attack(men[0], true)
	await pframes(150)
	var c0: Vector3 = _centre(_alive(foes))
	var m0: Vector3 = _centre(_alive(men))
	var p0: int = GameManager.shove_pulses
	sm.select_units(men)
	sm._trigger_double_rmb_abilities()
	sm.clear_selection()
	var moving_back := 0
	for _w in range(8):
		await pframes(60)
		for m in _alive(men):
			var u := m as Unit
			if u.state == Unit.State.MOVING and u.attack_target == null:
				moving_back += 1
	var c1: Vector3 = _centre(_alive(foes))
	var m1: Vector3 = _centre(_alive(men))
	var pushed: float = c1.x - c0.x
	var adv: float = m1.x - m0.x
	var pulses: int = GameManager.shove_pulses - p0
	print("  рывков %d, враг отброшен на %.2f м, свой строй %+.2f м, идущих без цели (окна) %d" % [pulses, pushed, adv, moving_back])
	if on:
		_f_ctrl = {}
		verdict("F1a натиск сработал в замесе (рывков не меньше 4)", pulses >= 4, "%d" % pulses)
		verdict("F1b вражеский отряд отброшен назад (не меньше 2 м)", pushed >= 2.0, "%.2f м" % pushed)
		verdict("F1c свой строй не ушёл назад", adv >= -0.3, "%+.2f м" % adv)
		verdict("F1d отряд не бросает бой ради смыкания (идущих без цели мало)", moving_back <= 8, "%d окон" % moving_back)
		_f_ctrl["pushed"] = pushed
	else:
		print("  контроль: прежнее поведение — смыкание после приказа атаки")
	_free(men)
	_free(foes)
	_Opt.phalanx_shove = true
	await pframes(5)
