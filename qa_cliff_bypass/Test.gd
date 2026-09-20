extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_cliff_bypass (QA_CliffBypassGate) — ТЗ 19.09.2026
## «ГЛОБАЛЬНЫЙ ФИКС ОБХОДА ГОР И УГЛОВ ПРЕПЯТСТВИЙ»
## ═══════════════════════════════════════════════════════════════════════════
## Скриншоты владельца: тролли зависли у угла скалы (агро на лучников на
## возвышенности), гоблины идут гуськом и затор у выступа.
##   A ГАБАРИТ   — отступ от стены СВОЙСТВО рода войск (пехота 1.5, конница
##                 2.2, туша 3.5, тролль 4.0); прямая в 2.5 м от кромки для
##                 гоблина свободна, для тролля «упирается».
##   B ТРОЛЛИ    — поочерёдно два тролля: (1) агро на лучников над обрывом —
##                 в стену не идёт, стоит; (2) приказ атаки на лучников на
##                 плато — идёт в обход через спуск и доходит до удара;
##                 Stuck Units Count = 0.
##   C ГОБЛИНЫ   — пять отрядов огибают плато (цель за ним): Stuck = 0,
##                 Formation Width Retention ≥ 70 %, маршруты без спама.
##   D КОННИЦА   — три отряда всадников, то же.
## Метрики ТЗ: Stuck Units Count (боец на ходу без продвижения > 1.5 с у
## стены), Path Recalculations/sec (nav_routes_built за окно), Formation
## Width Retention (ширина строя поперёк хода при огибании / исходная).
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_cliff_bypass/Test.tscn

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN
const _UStats := preload("res://scripts/unit_stats_config.gd")

## Порог «застрял»: без продвижения дольше STUCK_SEC (ТЗ: 1.5 с)
const STUCK_SEC := 1.5
const STUCK_MOVE := 0.25          # м за такт 0.5 с (0.5 м/с при шаге 2.2+)
const STUCK_WALL_R := 3.5         # «у стены» — скала в этом радиусе
const WIDTH_MIN_FRAC := 0.70      # ТЗ: удержание ширины ≥ 70 %

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_cliff_bypass: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = _g(at)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Отряд блоком cols колонок с шагом sp, разметка закреплена на месте
func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int, sp: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(
			at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0,
			at.z + float(i / cols) * sp))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in _alive(men):
		c += (u as Unit).global_position
		n += 1
	return c / maxf(float(n), 1.0)

func _free_all(men: Array) -> void:
	for u in men:
		if u != null and is_instance_valid(u):
			(u as Node).queue_free()

func _clear_trees(at: Vector3, r: float) -> void:
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn0 := n0 as ResourceNode
		if rn0 != null and is_instance_valid(rn0) and _xz(rn0.global_position, at) < r:
			rn0.queue_free()

## Есть ли скала в радиусе r от точки (восемь проб плюс сама точка)
func _near_wall(p: Vector3, r: float) -> bool:
	if GameManager.is_cliff(p.x, p.z) or not GameManager.nav_free(p):
		return true
	for k in range(8):
		var a: float = float(k) * TAU / 8.0
		var q := Vector3(p.x + cos(a) * r, 0.0, p.z + sin(a) * r)
		if not GameManager.nav_free(q):
			return true
	return false

## ── МЕТРИКА «ЗАСТРЯЛ»: такт 0.5 с, без продвижения STUCK_SEC подряд ────────
## Считаются только те, кому ЕСТЬ куда идти: MOVING дальше 4 м от точки либо
## ATTACKING с целью дальше досягаемости. Раз застрявший — считается один раз
var _stk_last: Dictionary = {}     # unit → позиция прошлого такта
var _stk_still: Dictionary = {}    # unit → секунд без хода
var _stk_flag: Dictionary = {}     # unit → застревал
var _stk_where: Array = []

func _stuck_reset() -> void:
	_stk_last.clear(); _stk_still.clear(); _stk_flag.clear(); _stk_where.clear()

func _stuck_tick(men: Array) -> void:
	for u in _alive(men):
		var un := u as Unit
		var p: Vector3 = un.global_position
		var want_move := false
		if un.state == Unit.State.MOVING:
			want_move = _xz(p, un.move_target) > 4.0
		elif un.state == Unit.State.ATTACKING:
			var t = un.attack_target
			if t != null and is_instance_valid(t):
				want_move = _xz(p, (t as Node3D).global_position) > un.reach() + 2.0
		var last: Variant = _stk_last.get(u)
		if last != null and want_move and _xz(p, last) < STUCK_MOVE:
			_stk_still[u] = float(_stk_still.get(u, 0.0)) + 0.5
		else:
			_stk_still[u] = 0.0
		_stk_last[u] = p
		if float(_stk_still[u]) >= STUCK_SEC and not _stk_flag.has(u) and _near_wall(p, STUCK_WALL_R):
			_stk_flag[u] = true
			_stk_where.append("%s в (%.0f, %.0f) %s" % [un.stat_id, p.x, p.z, "MOVING" if un.state == Unit.State.MOVING else "ATTACKING"])

func _stuck_count() -> int:
	return _stk_flag.size()

## Ширина отряда поперёк хода: центр сдвинулся с прошлого такта — ось хода,
## ширина — размах проекций на перпендикуляр
func _width_across(men: Array, dir: Vector2) -> float:
	var al: Array = _alive(men)
	if al.size() < 2 or dir.length_squared() < 1e-6:
		return -1.0
	var n: Vector2 = Vector2(-dir.y, dir.x).normalized()
	var lo := INF
	var hi := -INF
	for u in al:
		var p: Vector3 = (u as Unit).global_position
		var s: float = p.x * n.x + p.z * n.y
		lo = minf(lo, s)
		hi = maxf(hi, s)
	return hi - lo

## Габариты блока по СВОИМ осям (ковариация XZ, как у фронта ИИ): [большой,
## малый]. Retention считается по МАЛОМУ: строй, ставший ниткой, теряет его
## (0.6 м личного круга против 2.6-3 м глубины блока), а блок, повернувший за
## угол вместе со своей осью, — нет. Ширина «поперёк хода» при повороте
## меняется местами с глубиной и мерила бы разворот, а не гуськом
func _extents(men: Array) -> Array:
	var al: Array = _alive(men)
	if al.size() < 3:
		return [-1.0, -1.0]
	var c := Vector2.ZERO
	for u in al:
		var p: Vector3 = (u as Unit).global_position
		c += Vector2(p.x, p.z)
	c /= float(al.size())
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	for u in al:
		var p: Vector3 = (u as Unit).global_position
		var dx: float = p.x - c.x
		var dz: float = p.z - c.y
		sxx += dx * dx; szz += dz * dz; sxz += dx * dz
	var ang: float = 0.5 * atan2(2.0 * sxz, sxx - szz)
	var a1 := Vector2(cos(ang), sin(ang))
	var a2 := Vector2(-a1.y, a1.x)
	var lo1 := INF; var hi1 := -INF; var lo2 := INF; var hi2 := -INF
	for u in al:
		var p: Vector3 = (u as Unit).global_position
		var q := Vector2(p.x - c.x, p.z - c.y)
		var s1: float = q.dot(a1); var s2: float = q.dot(a2)
		lo1 = minf(lo1, s1); hi1 = maxf(hi1, s1); lo2 = minf(lo2, s2); hi2 = maxf(hi2, s2)
	var e1: float = hi1 - lo1
	var e2: float = hi2 - lo2
	return [maxf(e1, e2), minf(e1, e2)]

## Плато из PLATEAU_SPECS[0]: центр, радиус вершины, угол спуска
var _pc: Vector3 = Vector3.ZERO
var _pr: float = 0.0
var _ramp: float = 0.0
var _pt: Vector3 = Vector3.ZERO      # площадка старта (глухая сторона)

func _foot(extra: float = 8.0) -> Vector3:
	var opp: float = _ramp + PI
	var d: float = _pr + main.PLATEAU_RAMP_STEEP + extra
	return Vector3(_pc.x + cos(opp) * d, 0.0, _pc.z + sin(opp) * d)

func _at_angle(a: float, d: float) -> Vector3:
	return Vector3(_pc.x + cos(a) * d, 0.0, _pc.z + sin(a) * d)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = true
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	# Дикие партии замораживаются: площадка своя, чужие тела в замере не нужны
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction != F:
			(n as Unit).set_tick(false)
	for l in GameManager.get("troll_lairs"):
		if l == null or not is_instance_valid(l):
			continue
		for t in l.get("trolls"):
			if is_instance_valid(t):
				(t as Unit).set_tick(false)
		for g in l.get("gnolls"):
			if g != null and is_instance_valid(g):
				(g as Node).queue_free()
	# Тролль без логова его УСЫНОВЛЯЕТ лениво (Troll.tick_physics) и уходит в
	# патруль/обед за сотню метров — стенду нужен тролль на площадке
	GameManager.troll_lair = null
	var spec: Array = main.PLATEAU_SPECS[0]
	_pc = Vector3(float(spec[0]), 0.0, float(spec[1]))
	_pr = float(spec[2])
	_ramp = atan2(-_pc.z, -_pc.x)
	print("  плато: центр (%.0f, %.0f), радиус %.0f, спуск под %.2f рад; сетка: непроходимых %d" % [
		_pc.x, _pc.z, _pr, _ramp, GameManager.nav_cells_blocked])
	# Лес расчищается ТОЛЬКО на площадках старта и цели: угол скалы остаётся
	# в живом лесу — ровно как на скриншоте
	_clear_trees(_foot(18.0), 12.0)
	_clear_trees(_at_angle(_ramp, _pr + main.PLATEAU_RAMP_STEEP + 18.0), 12.0)
	for a in OS.get_cmdline_user_args():
		if String(a) == "notrees":
			_clear_trees(_pc, _pr + 50.0)
	await pframes(6)

	var only: String = ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			only = String(a).substr(5)
	if only == "" or only.contains("a"):
		await _a_clearance()
	if only == "" or only.contains("b"):
		await _b_trolls()
	if only == "" or only.contains("c"):
		await _c_goblins()
	if only == "" or only.contains("d"):
		await _d_cavalry()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_clearance() -> void:
	print("\n═════ A. ОТСТУП ОТ СТЕНЫ ПО ГАБАРИТУ ═════")
	var far: Vector3 = _foot(60.0)
	var gob: Unit = _spawn("goblin_spearman", GF, far)
	var rid: Unit = _spawn("goblin_rider", GF, far + Vector3(3.0, 0.0, 0.0))
	var big: Unit = _spawn("big_goblin", GF, far + Vector3(6.0, 0.0, 0.0))
	var tro: Unit = _spawn("troll", GF, far + Vector3(10.0, 0.0, 0.0))
	var sp: Unit = _spawn("spearman", F, far + Vector3(-3.0, 0.0, 0.0))
	await pframes(2)
	verdict("A1 пехота и гоблин — отступ %.1f м (конфиг %.1f)" % [gob.nav_clearance(), _UStats.NAV_CLEARANCE_INFANTRY],
		gob.nav_clearance() == _UStats.NAV_CLEARANCE_INFANTRY and sp.nav_clearance() == _UStats.NAV_CLEARANCE_INFANTRY)
	verdict("A2 конница — отступ %.1f м (конфиг %.1f)" % [rid.nav_clearance(), _UStats.NAV_CLEARANCE_CAVALRY],
		rid.nav_clearance() == _UStats.NAV_CLEARANCE_CAVALRY)
	verdict("A3 туша — %.1f м, тролль — %.1f м" % [big.nav_clearance(), tro.nav_clearance()],
		big.nav_clearance() == _UStats.NAV_CLEARANCE_GIANT and tro.nav_clearance() == _UStats.NAV_CLEARANCE_TROLL)
	verdict("A4 порядок отступов: пехота < конница < туша < тролль",
		gob.nav_clearance() < rid.nav_clearance() and rid.nav_clearance() < big.nav_clearance()
			and big.nav_clearance() < tro.nav_clearance())
	# Прямая вдоль стены в 2.5 м от кромки: гоблину свободна, троллю упирается
	var opp: float = _ramp + PI
	var d: float = _pr + main.PLATEAU_RAMP_STEEP + 2.5
	var a0: Vector3 = _at_angle(opp - 0.35, d)
	var a1: Vector3 = _at_angle(opp + 0.35, d)
	var g_blk: bool = GameManager.nav_blocked(a0, a1, gob.nav_clearance())
	var t_blk: bool = GameManager.nav_blocked(a0, a1, tro.nav_clearance())
	verdict("A5 хорда вдоль кромки в 2.5 м: гоблину свободна (%s), троллю упирается (%s)" % [str(not g_blk), str(t_blk)],
		not g_blk and t_blk)
	# Обход тролля лежит дальше от стены, чем обход гоблина
	var foot: Vector3 = _foot(8.0)
	var goal: Vector3 = _at_angle(_ramp, _pr + main.PLATEAU_RAMP_STEEP + 14.0)
	var rg: PackedVector3Array = GameManager.nav_route(foot, goal, gob.nav_clearance())
	var rt: PackedVector3Array = GameManager.nav_route(foot, goal, tro.nav_clearance())
	var min_g := INF
	var min_t := INF
	for p in rg:
		min_g = minf(min_g, _xz(p, _pc))
	for p in rt:
		min_t = minf(min_t, _xz(p, _pc))
	verdict("A6 углы обхода тролля дальше от плато, чем у гоблина (%.1f против %.1f м от центра, точек %d / %d)" % [min_t, min_g, rt.size(), rg.size()],
		rt.size() > 0 and rg.size() > 0 and min_t >= min_g + 1.0)
	for u in [gob, rid, big, tro, sp]:
		(u as Node).queue_free()
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _archers_on_edge(n: int) -> Array:
	var opp: float = _ramp + PI
	var edge: Vector3 = _at_angle(opp, _pr - 2.5)
	var men: Array = []
	var sid: int = GameManager.new_squad(F, "archer")
	for i in range(n):
		var u: Unit = _spawn("archer", F, edge + Vector3(float(i % 3) * 0.8 - 0.8, 0.0, float(i / 3) * 0.8))
		u.max_health = 1e9
		u.current_health = 1e9
		u._soa_push_stats()
		GameManager.add_to_squad(sid, u)
		u.set_tick(false)
		men.append(u)
	return men

func _b_trolls() -> void:
	print("\n═════ B. ТРОЛЛИ У ОБРЫВА ═════")
	var arc: Array = _archers_on_edge(6)
	await pframes(3)
	# ── (1) агро на лучников над обрывом: в стену не идём ─────────────────
	var t1: Unit = _spawn("troll", GF, _foot(3.0))
	t1.max_health = 1e9
	t1.current_health = 1e9
	await pframes(3)
	var d0: float = _xz(t1.global_position, (arc[0] as Unit).global_position)
	print("  тролль-1 у подножия, лучники на кромке в %.1f м (агро %.0f м)" % [d0, t1.aggro_radius()])
	var start: Vector3 = t1.global_position
	_stuck_reset()
	var chased := 0
	var worst_off := 0.0
	for f in range(60 * 12):
		await get_tree().physics_frame
		if f % 120 == 0:
			print("    t=%3.0f тролль-1 в (%.0f, %.0f), state %d, target %s, сдвиг %.1f" % [float(f) / 60.0,
				t1.global_position.x, t1.global_position.z, t1.state, str(t1.attack_target), _xz(t1.global_position, start)])
		if f % 30 == 0:
			_stuck_tick([t1])
		worst_off = maxf(worst_off, _xz(t1.global_position, start))
		if t1.attack_target != null and t1.state == Unit.State.ATTACKING:
			chased = maxi(chased, 1)
	verdict("B1 тролль видит лучников над обрывом, в стену не идёт: сдвиг %.1f м < 3, на скале — нет" % worst_off,
		worst_off < 3.0 and not GameManager.is_cliff(t1.global_position.x, t1.global_position.z))
	verdict("B2 Stuck Units Count (тролль-1) = %d" % _stuck_count(), _stuck_count() == 0)
	t1.take_damage(1e12)
	await pframes(4)
	# ── (2) приказ атаки на лучников на плато: обход через спуск ─────────
	var t2: Unit = _spawn("troll", GF, _foot(6.0))
	t2.max_health = 1e9
	t2.current_health = 1e9
	await pframes(3)
	var tgt: Unit = arc[0]
	t2.command_attack(tgt, true, true)
	var routes0: int = GameManager.nav_routes_built
	var straight: float = _xz(t2.global_position, tgt.global_position)
	_stuck_reset()
	var reached := -1
	var via_ramp := false
	var path_len := 0.0
	var prev: Vector3 = t2.global_position
	var cliff_hits := 0
	for f in range(60 * 90):
		await get_tree().physics_frame
		# Поводок погони тролля (TROLL_CHASE_SEC, правило игры — qa_troll_aggro)
		# на время замера снят: обход плато длиннее десяти секунд. Цель —
		# та, что выбрал squad_pick_member, а не tgt
		t2._chase_target = t2.attack_target
		t2._chase_t = -1e6
		t2._chase_from = Vector3(INF, 0.0, 0.0)
		if f % 30 == 0:
			_stuck_tick([t2])
			var p: Vector3 = t2.global_position
			path_len += _xz(p, prev)
			prev = p
			if GameManager.is_cliff(p.x, p.z):
				cliff_hits += 1
			var a: float = absf(wrapf(atan2(p.z - _pc.z, p.x - _pc.x) - _ramp, -PI, PI))
			if a < main.PLATEAU_RAMP_CONE + 0.4 and _xz(p, _pc) < _pr + main.PLATEAU_RAMP_GENTLE + 4.0:
				via_ramp = true
		if f % 300 == 0:
			print("    t=%3.0f тролль-2 в (%.0f, %.0f), до цели %.1f, до плато %.1f, state %d, target %s, маршрут %d/%d" % [
				float(f) / 60.0, t2.global_position.x, t2.global_position.z, _xz(t2.global_position, tgt.global_position),
				_xz(t2.global_position, _pc), t2.state, str(t2.attack_target), t2._atk_route_i, t2._atk_route.size()])
		if _xz(t2.global_position, tgt.global_position) <= t2.reach() + 1.0:
			reached = f
			break
	var secs: float = float(reached if reached >= 0 else 60 * 90) / 60.0
	var routes: int = GameManager.nav_routes_built - routes0
	print("  тролль-2: прямая %.1f м, прошёл %.1f м за %.1f с, маршрутов построено %d (%.2f/с), застреваний %d" % [
		straight, path_len, secs, routes, float(routes) / maxf(secs, 1.0), _stuck_count()])
	for w in _stk_where:
		print("    застрял: %s" % w)
	verdict("B3 тролль-2 дошёл до удара по лучникам на плато за %.1f с" % secs, reached >= 0)
	verdict("B4 шёл через спуск, на скале не стоял (%d проб)" % cliff_hits, via_ramp and cliff_hits == 0)
	verdict("B5 Stuck Units Count (тролль-2) = %d" % _stuck_count(), _stuck_count() == 0)
	verdict("B6 Path Recalculations/sec у одного тролля %.2f — не спам (< 3/с)" % (float(routes) / maxf(secs, 1.0)),
		float(routes) / maxf(secs, 1.0) < 3.0)
	t2.take_damage(1e12)
	for u in arc:
		if is_instance_valid(u):
			(u as Unit).set_tick(true)
			(u as Unit).take_damage(1e12)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
## Отряды с глухой стороны плато посылаются за него (цель напротив, за
## спуском): прямая идёт через плато, дорога — вокруг стены. Каждый боец
## получает СВОЮ точку (перенос формы блока), как у приказа группой
func _bypass_block(title: String, kind: String, n_squads: int, per: int, cols: int, sp: float, budget_sec: float) -> void:
	print("\n═════ %s ═════" % title)
	var start: Vector3 = _foot(18.0)
	var goal: Vector3 = _at_angle(_ramp, _pr + main.PLATEAU_RAMP_STEEP + 18.0)
	var squads: Array = []
	var all: Array = []
	var block_w: float = float(cols - 1) * sp + 4.0
	for i in range(n_squads):
		var off := Vector3((float(i) - float(n_squads - 1) * 0.5) * block_w, 0.0, 0.0)
		# Раскладка вдоль оси хода: блоки рядом друг с другом поперёк неё
		var ax: Vector2 = Vector2(cos(_ramp), sin(_ramp))
		var nx: Vector2 = Vector2(-ax.y, ax.x)
		var at: Vector3 = start + Vector3(nx.x * off.x, 0.0, nx.y * off.x)
		var sq: Array = _squad(kind, GF, at, per, cols, sp)
		squads.append(sq)
		all += sq[1]
	await pframes(30)
	# Исходная ширина поперёк оси «старт → цель»
	var axis: Vector2 = Vector2(goal.x - start.x, goal.z - start.z).normalized()
	var w0: Array = []
	for sq in squads:
		w0.append(float(_extents(sq[1])[1]))
	var straight: float = _xz(start, goal)
	for sq in squads:
		var c: Vector3 = _centre(sq[1])
		for u in sq[1]:
			var un := u as Unit
			var rel: Vector3 = un.global_position - c
			un.command_move(goal + Vector3(rel.x, 0.0, rel.z), false, Vector3.ZERO, false, true)
	var routed := 0
	for u in all:
		if (u as Unit).route_size() > 0:
			routed += 1
	verdict("%s1 приказ получил маршрут у всех (%d из %d)" % [title[0], routed, all.size()], routed == all.size())
	var routes0: int = GameManager.nav_routes_built
	_stuck_reset()
	var arrived := -1
	var min_frac := INF
	var min_frac_sq := -1
	var last_c: Array = []
	for sq in squads:
		last_c.append(_centre(sq[1]))
	var cliff_hits := 0
	var frames_n: int = int(budget_sec * 60.0)
	for f in range(frames_n):
		await get_tree().physics_frame
		if f % 30 != 0:
			continue
		_stuck_tick(all)
		var n_in := 0
		for u in _alive(all):
			var p: Vector3 = (u as Unit).global_position
			if GameManager.is_cliff(p.x, p.z):
				cliff_hits += 1
			if _xz(p, goal) < block_w * float(n_squads) * 0.5 + 8.0:
				n_in += 1
		# Ширина при огибании: пока центр отряда в поясе плато (±ширина
		# склона) и отряд идёт (центр сдвинулся за такт)
		for i in range(squads.size()):
			var c: Vector3 = _centre(squads[i][1])
			var mv := Vector2(c.x - last_c[i].x, c.z - last_c[i].z)
			last_c[i] = c
			var dc: float = _xz(c, _pc)
			if mv.length() > 0.4 and dc < _pr + main.PLATEAU_RAMP_GENTLE + 12.0 and float(w0[i]) > 0.0:
				var w: float = float(_extents(squads[i][1])[1])
				if w > 0.0:
					var fr: float = w / float(w0[i])
					if fr < min_frac:
						min_frac = fr
						min_frac_sq = i
		if f % 300 == 0:
			for i in range(squads.size()):
				var c: Vector3 = _centre(squads[i][1])
				var st: Dictionary = {}
				for u in _alive(squads[i][1]):
					var k: String = str((u as Unit).state) + ("t" if (u as Unit).attack_target != null else "")
					st[k] = int(st.get(k, 0)) + 1
				var ex: Array = _extents(squads[i][1])
				print("    t=%3.0f отряд %d: центр (%.0f, %.0f) до цели %.0f м, до плато %.0f м, блок %.1f × %.1f, поперёк оси %.1f, состояния %s" % [
					float(f) / 60.0, i, c.x, c.z, _xz(c, goal), _xz(c, _pc), float(ex[0]), float(ex[1]), _width_across(squads[i][1], axis), str(st)])
		if n_in >= int(float(all.size()) * 0.9):
			arrived = f
			break
	var secs: float = float(arrived if arrived >= 0 else frames_n) / 60.0
	var routes: int = GameManager.nav_routes_built - routes0
	var rps: float = float(routes) / maxf(secs, 1.0)
	print("  %s: прямая %.0f м, дошли за %.1f с, маршрутов %d (%.1f/с на %d бойцов), застреваний %d, малый габарит блока мин %.0f %% (отряд %d, исходный %.1f м)" % [
		kind, straight, secs, routes, rps, all.size(), _stuck_count(), min_frac * 100.0 if min_frac < INF else -1.0, min_frac_sq,
		float(w0[min_frac_sq]) if min_frac_sq >= 0 else -1.0])
	for w in _stk_where:
		print("    застрял: %s" % w)
	verdict("%s2 отряды обошли плато и дошли (за %.1f с)" % [title[0], secs], arrived >= 0)
	verdict("%s3 Stuck Units Count = %d (ТЗ: 0)" % [title[0], _stuck_count()], _stuck_count() == 0)
	verdict("%s4 на скале никто не стоял (%d проб)" % [title[0], cliff_hits], cliff_hits == 0)
	verdict("%s5 Formation Width Retention (малый габарит блока) %.0f %% ≥ %.0f %%" % [title[0], min_frac * 100.0 if min_frac < INF else -1.0, WIDTH_MIN_FRAC * 100.0],
		min_frac < INF and min_frac >= WIDTH_MIN_FRAC)
	verdict("%s6 Path Recalculations/sec %.1f < %d (по одному на бойца в секунду, без ежекадрового спама)" % [title[0], rps, all.size()],
		rps < float(all.size()))
	for u in all:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)
	await pframes(6)

func _c_goblins() -> void:
	await _bypass_block("C. ПЯТЬ ОТРЯДОВ ГОБЛИНОВ ОГИБАЮТ ПЛАТО", "goblin_spearman", 5, 20, 5, 1.0, 120.0)

func _d_cavalry() -> void:
	await _bypass_block("D. ТРИ ОТРЯДА КОННИЦЫ ОГИБАЮТ ПЛАТО", "goblin_rider", 3, 12, 4, 1.3, 90.0)
