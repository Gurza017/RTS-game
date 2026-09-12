extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_nav — ПИСЬМО 11: НАВИГАЦИЯ ВОКРУГ СКАЛ И ВОДЫ
## ═══════════════════════════════════════════════════════════════════════════
## Скриншот владельца: отряд, заагрившийся на гноллов на плато, бежит лбом в
## обрыв, сгружается у стены и дёргается; вторая половина отряда рвётся.
##   A СЕТКА    — у карты есть сетка проходимости ядра; прямая через плато
##                упирается, чистое поле — нет; обход существует, все его точки
##                проходимы и видны друг из друга, длина разумная.
##   B ПРИКАЗ   — отряд с «глухой» стороны плато посылается на его вершину:
##                с навигацией доходит (через спуск), без неё (A/B) стоит у
##                стены. Отряд не рвётся: разброс по приходу в пределах строя.
##   C АГРО     — враг на плато над стеной, отряд внизу в радиусе агро: никто
##                не бежит в обрыв (инициатива за обрыв запрещена), но стрелок,
##                до которого дострелить, стреляет.
##   D АТАКА    — приказ атаки на врага на плато: отряд идёт в обход по
##                спуску и вступает в бой.
##   E БРОД     — приказ на другой берег вдали от брода: маршрут ведёт
##                через брод, бойцы не встают ниткой в одну точку (полосы).
##   F ЦЕНА     — тысяча приказов через плато строятся за миллисекунды.
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_nav/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(600.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_nav: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func _squad(uid: String, fac: int, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	for i in range(n):
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = fac
		main.world_add(u)
		var p := at + Vector3(float(i % 5) * 0.6 - 1.2, 0.0, float(i / 5) * 0.6 - 1.2)
		u.global_position = _g(p)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			c += (u as Unit).global_position
			n += 1
	return c / maxf(float(n), 1.0)

func _spread(men: Array) -> float:
	var c: Vector3 = _centre(men)
	var worst := 0.0
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			worst = maxf(worst, _xz((u as Unit).global_position, c))
	return worst

func _clear_trees(at: Vector3, r: float) -> void:
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn0 := n0 as ResourceNode
		if rn0 != null and is_instance_valid(rn0) and _xz(rn0.global_position, at) < r:
			rn0.queue_free()

func _free_all(men: Array) -> void:
	for u in men:
		if is_instance_valid(u):
			(u as Node).queue_free()

## Плато из PLATEAU_SPECS (первое): центр, радиус вершины, угол спуска
var _pc: Vector3 = Vector3.ZERO
var _pr: float = 0.0
var _ramp: float = 0.0

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	# Скалы, вода и маршрут — правило партии: границы мира ВКЛЮЧЕНЫ
	GameManager.world_bounds_enabled = true
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	# Логово: стражи и стая замораживаются — чужие тела в замере не нужны
	for l in GameManager.get("troll_lairs"):
		if l == null or not is_instance_valid(l):
			continue
		for t in l.get("trolls"):
			if is_instance_valid(t):
				(t as Unit).set_tick(false)
		for g in l.get("gnolls"):
			if g != null and is_instance_valid(g):
				(g as Node).queue_free()
	var spec: Array = main.PLATEAU_SPECS[0]
	_pc = Vector3(float(spec[0]), 0.0, float(spec[1]))
	_pr = float(spec[2])
	_ramp = atan2(-_pc.z, -_pc.x)
	print("  плато: центр (%.0f, %.0f), радиус %.0f, спуск под %.2f рад" % [_pc.x, _pc.z, _pr, _ramp])
	_clear_trees(_pc, _pr + 40.0)
	await pframes(6)

	await _a_grid()
	await _b_order()
	await _c_aggro()
	await _d_attack()
	await _e_ford()
	await _f_cost()
	_finish()

## Точка у подножия с ГЛУХОЙ стороны плато (напротив спуска)
func _foot(extra: float = 8.0) -> Vector3:
	var opp: float = _ramp + PI
	var d: float = _pr + main.PLATEAU_RAMP_STEEP + extra
	return Vector3(_pc.x + cos(opp) * d, 0.0, _pc.z + sin(opp) * d)

# ═════════════════════════════════════════════════════════════════════════════
func _a_grid() -> void:
	print("\n═════ A. СЕТКА ПРОХОДИМОСТИ ═════")
	verdict("A1 сетка построена, непроходимых ячеек %d" % GameManager.nav_cells_blocked,
		GameManager.nav_on() and GameManager.nav_cells_blocked > 0)
	var foot: Vector3 = _foot()
	var top: Vector3 = _pc
	verdict("A2 вершина плато и подножие проходимы, обрыв между ними — нет",
		GameManager.nav_free(top) and GameManager.nav_free(foot)
			and not GameManager.nav_free(Vector3(_pc.x + cos(_ramp + PI) * (_pr + 2.0), 0.0, _pc.z + sin(_ramp + PI) * (_pr + 2.0))))
	verdict("A3 прямая с глухой стороны на вершину упирается в скалу", GameManager.nav_blocked(foot, top))
	var open_a: Vector3 = _pc + Vector3(-60.0, 0.0, 0.0)
	var open_b: Vector3 = _pc + Vector3(-60.0, 0.0, 30.0)
	verdict("A4 прямая в чистом поле свободна", not GameManager.nav_blocked(open_a, open_b)
		and GameManager.nav_route(open_a, open_b).is_empty())
	var route: PackedVector3Array = GameManager.nav_route(foot, top)
	verdict("A5 обход найден: %d точек" % route.size(), route.size() >= 1)
	var all_free := true
	var all_seen := true
	var prev: Vector3 = foot
	var length := 0.0
	for p in route:
		if not GameManager.nav_free(p):
			all_free = false
		if GameManager.nav_blocked(prev, p):
			all_seen = false
		length += _xz(prev, p)
		prev = p
	if GameManager.nav_blocked(prev, top):
		all_seen = false
	length += _xz(prev, top)
	verdict("A6 все точки обхода проходимы и видны друг из друга", all_free and all_seen)
	verdict("A7 обход не длиннее четырёх прямых (%.0f м при прямой %.0f м)" % [length, _xz(foot, top)],
		length < _xz(foot, top) * 4.0 + 10.0)
	# Обход проходит через сектор спуска
	var via_ramp := false
	for p in route:
		var a: float = atan2(p.z - _pc.z, p.x - _pc.x)
		if absf(wrapf(a - _ramp, -PI, PI)) < main.PLATEAU_RAMP_CONE + 0.5 and _xz(p, _pc) < _pr + main.PLATEAU_RAMP_GENTLE + 6.0:
			via_ramp = true
	verdict("A8 обход идёт через спуск плато", via_ramp)
	verdict("A9 цель за обрывом для инициативы недостижима при поводке %.0f м, при поводке 200 м — достижима" % Unit.AGGRO_LEASH,
		GameManager.nav_unreachable(foot, top, Unit.AGGRO_LEASH) and not GameManager.nav_unreachable(foot, top, 200.0))

# ═════════════════════════════════════════════════════════════════════════════
func _b_order() -> void:
	print("\n═════ B. ПРИКАЗ НА ВЕРШИНУ: С НАВИГАЦИЕЙ И БЕЗ ═════")
	var foot: Vector3 = _foot(10.0)
	var top: Vector3 = _pc
	# ── A/B: без навигации — стоят у стены ──────────────────────────────
	var saved: int = GameManager.nav_cells_blocked
	GameManager.nav_cells_blocked = 0
	var ctl: Array = _squad("warrior", Constants.FACTION_PLAYER, foot, 10)
	await pframes(3)
	for u in ctl:
		(u as Unit).command_move(top, false, Vector3.ZERO, false, true)
	var best_ctl := INF
	for _i in range(60 * 35):
		await get_tree().physics_frame
		best_ctl = minf(best_ctl, _xz(_centre(ctl), top))
	print("  без навигации: центр отряда за 35 с подошёл к вершине не ближе %.1f м" % best_ctl)
	verdict("B0 (A/B) без навигации отряд к вершине не доходит (лучшее %.1f м)" % best_ctl, best_ctl > 8.0)
	_free_all(ctl)
	GameManager.nav_cells_blocked = saved
	await pframes(4)
	# ── С навигацией — доходят через спуск ──────────────────────────────
	var men: Array = _squad("warrior", Constants.FACTION_PLAYER, foot, 10)
	await pframes(3)
	for u in men:
		(u as Unit).command_move(top, false, Vector3.ZERO, false, true)
	var routed := 0
	for u in men:
		if (u as Unit).route_size() > 0:
			routed += 1
	verdict("B1 приказ получил маршрут у всех (%d из %d)" % [routed, men.size()], routed == men.size())
	var arrived := -1
	var worst_spread := 0.0
	for f in range(60 * 120):
		await get_tree().physics_frame
		if f % 30 == 0:
			worst_spread = maxf(worst_spread, _spread(men))
		var n_in := 0
		for u in men:
			if _xz((u as Unit).global_position, top) < 6.0:
				n_in += 1
		if n_in >= 9:
			arrived = f
			break
	verdict("B2 с навигацией отряд дошёл на вершину (за %.1f с)" % (float(arrived) / 60.0), arrived >= 0,
		"центр в %.1f м от вершины" % _xz(_centre(men), top))
	verdict("B3 отряд не рвался по дороге: худший разброс от центра %.1f м < 14" % worst_spread, worst_spread < 14.0)
	var cliff_hits := 0
	for u in men:
		if GameManager.is_cliff((u as Unit).global_position.x, (u as Unit).global_position.z):
			cliff_hits += 1
	verdict("B4 никто не стоит на скале", cliff_hits == 0)
	_free_all(men)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _c_aggro() -> void:
	print("\n═════ C. АГРО ЧЕРЕЗ ОБРЫВ ═════")
	var foot: Vector3 = _foot(3.0)
	# Враг на кромке вершины над стеной, в радиусе агро от подножия
	var opp: float = _ramp + PI
	var edge: Vector3 = Vector3(_pc.x + cos(opp) * (_pr - 2.0), 0.0, _pc.z + sin(opp) * (_pr - 2.0))
	var foe: Unit = Building.PRELOAD_SCENES["goblin_spearman"].instantiate()
	foe.faction = Constants.FACTION_GOBLIN
	main.world_add(foe)
	foe.global_position = _g(edge)
	foe.sync_row()
	foe.set_tick(false)
	var men: Array = _squad("warrior", Constants.FACTION_PLAYER, foot, 10)
	await pframes(3)
	var d0: float = _xz(foot, edge)
	print("  враг на кромке в %.1f м от отряда (агро %.0f м)" % [d0, (men[0] as Unit).aggro_radius()])
	var start: Vector3 = _centre(men)
	var chased := 0
	for _i in range(60 * 12):
		await get_tree().physics_frame
	for u in men:
		if (u as Unit).attack_target == foe and (u as Unit).state == Unit.State.ATTACKING:
			chased += 1
	var moved: float = _xz(_centre(men), start)
	verdict("C1 враг над обрывом виден (%.1f м), но за него никто не пошёл: гонятся %d, центр сдвинулся на %.1f м" % [d0, chased, moved],
		chased == 0 and moved < 3.0)
	var cliff_hits := 0
	for u in men:
		if GameManager.is_cliff((u as Unit).global_position.x, (u as Unit).global_position.z):
			cliff_hits += 1
	verdict("C2 никто не упёрся в стену (на скале 0)", cliff_hits == 0)
	# Стрелок снизу — стреляет, если дострелить
	var arc: Array = _squad("archer", Constants.FACTION_PLAYER, foot + Vector3(0.0, 0.0, 3.0), 5)
	await pframes(3)
	var hp0: float = foe.current_health
	var shot := false
	for _i in range(60 * 12):
		await get_tree().physics_frame
		if foe.current_health < hp0:
			shot = true
			break
	verdict("C3 лучник у подножия стреляет по врагу на плато, не лезет на гору", shot)
	var arc_cliff := 0
	for u in arc:
		if GameManager.is_cliff((u as Unit).global_position.x, (u as Unit).global_position.z):
			arc_cliff += 1
	verdict("C3б лучники остались внизу (на скале 0)", arc_cliff == 0)
	_free_all(men)
	_free_all(arc)
	foe.queue_free()
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _d_attack() -> void:
	print("\n═════ D. ПРИКАЗ АТАКИ НА ВРАГА НА ПЛАТО ═════")
	var foot: Vector3 = _foot(6.0)
	var foe: Unit = Building.PRELOAD_SCENES["goblin_spearman"].instantiate()
	foe.faction = Constants.FACTION_GOBLIN
	main.world_add(foe)
	foe.global_position = _g(_pc)
	foe.sync_row()
	foe.set_tick(false)
	foe.max_health = 1.0e6
	foe.current_health = 1.0e6
	var men: Array = _squad("warrior", Constants.FACTION_PLAYER, foot, 10)
	await pframes(3)
	for u in men:
		(u as Unit).command_attack(foe, true, false, true)
	var hp0: float = foe.current_health
	var hit_at := -1
	for f in range(60 * 150):
		await get_tree().physics_frame
		if foe.current_health < hp0:
			hit_at = f
			break
	verdict("D1 отряд обошёл обрыв и вступил в бой (первый удар через %.1f с)" % (float(hit_at) / 60.0), hit_at >= 0,
		"центр в %.1f м от цели" % _xz(_centre(men), _pc))
	var near := 0
	for u in men:
		if _xz((u as Unit).global_position, _pc) < 8.0:
			near += 1
	verdict("D2 у цели наверху — большинство отряда (%d из 10)" % near, near >= 7)
	_free_all(men)
	foe.queue_free()
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _e_ford() -> void:
	print("\n═════ E. ЧЕРЕЗ РЕКУ ВДАЛИ ОТ БРОДА ═════")
	if not bool(main.RIVER_ENABLED):
		verdict("E0 реки нет — блок пропущен", true)
		return
	var zf: float = float(main.FORD_Z)
	var z: float = zf + 60.0 if zf < 0.0 else zf - 60.0
	var west := Vector3(main.river_x(z) - 30.0, 0.0, z)
	var east := Vector3(main.river_x(z) + 30.0, 0.0, z)
	_clear_trees(west, 14.0)
	_clear_trees(east, 14.0)
	await pframes(4)
	var men: Array = _squad("spearman", Constants.FACTION_PLAYER, west, 10)
	await pframes(3)
	for u in men:
		(u as Unit).command_move(east, false, Vector3.ZERO, false, true)
	var lanes: Dictionary = {}
	var with_ford := 0
	for u in men:
		var un := u as Unit
		if un.route_size() >= 2:
			with_ford += 1
			lanes[snappedf(un.get("_route")[un.route_size() - 2].z, 0.5)] = true
	# Полос столько, сколько ШЕРЕНГ у блока (полоса — смещение от центра
	# отряда вдоль русла): блок стенда 5×2 даёт две
	verdict("E1 маршрут каждого ведёт через брод (%d из 10), полосы разные (%d)" % [with_ford, lanes.size()],
		with_ford == 10 and lanes.size() >= 2)
	var crossed := 0
	var wet_frames := 0
	for _f in range(60 * 150):
		await get_tree().physics_frame
		crossed = 0
		for u in men:
			var p: Vector3 = (u as Unit).global_position
			if main.is_water(p.x, p.z):
				wet_frames += 1
			if _xz(p, east) < 6.0:
				crossed += 1
		if crossed >= 9:
			break
	verdict("E2 отряд перешёл реку по броду (%d из 10 у цели), в воде кадров: %d" % [crossed, wet_frames],
		crossed >= 9 and wet_frames == 0)
	_free_all(men)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _f_cost() -> void:
	print("\n═════ F. ЦЕНА МАРШРУТА ═════")
	var foot: Vector3 = _foot(10.0)
	var t0: int = Time.get_ticks_usec()
	var n := 0
	for i in range(1000):
		var a: Vector3 = foot + Vector3(float(i % 10) * 0.7, 0.0, float(i / 10) * 0.3)
		var r: PackedFloat32Array = GameManager.army.nav_path(a.x, a.z, _pc.x, _pc.z)
		n += r.size()
	var us: int = Time.get_ticks_usec() - t0
	print("  1000 маршрутов через плато (без кэша): %.1f мс, %.1f мкс на маршрут" % [float(us) * 0.001, float(us) / 1000.0])
	verdict("F1 маршрут через плато стоит меньше 2 мс (%.0f мкс)" % (float(us) / 1000.0), us < 2000 * 1000)
	t0 = Time.get_ticks_usec()
	var b := 0
	for i in range(10000):
		if GameManager.nav_blocked(foot + Vector3(float(i % 100) * 0.1, 0.0, 0.0), _pc):
			b += 1
	us = Time.get_ticks_usec() - t0
	print("  10000 проверок прямой: %.1f мс (%.2f мкс каждая)" % [float(us) * 0.001, float(us) / 10000.0])
	verdict("F2 проверка прямой дешевле 20 мкс", us < 20 * 10000)
