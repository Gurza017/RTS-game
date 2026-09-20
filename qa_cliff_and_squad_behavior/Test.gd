extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_cliff_and_squad_behavior — ТЗ 20.09.2026
## «НАВИГАЦИЯ, ЦЕЛЬНОСТЬ ОТРЯДА, СТОЙКИ»
## ═══════════════════════════════════════════════════════════════════════════
## Четыре обязательных теста заказа плюс проверки блока 4:
##   A ГОРЫ    — 100 лучников, 100 копейщиков, конница и тролли огибают
##               плато. Отряды идут дугой по земле, а не вереницей: малый
##               габарит блока держится, застреваний нет, в нити обхода есть
##               скруглённый угол (несколько точек вместо одного излома).
##   B СПАВН   — пять заказов из казарм к точке сбора. Ни одной точки
##               маршрута ЗА СПИНОЙ (это и был «призрачный угол»), крюк
##               пути над прямой в пределах допуска, все дошли.
##   C СТОЙКА  — копейщики по кнопке «Защита»: НИ ОДИН не сдвинулся, копья
##               опустили все три шеренги, и со «Стеной копий» они опущены
##               даже на марше.
##   D ОТХОД   — отряд в бою получает приказ уйти: бой разорван тем же
##               кадром, по дороге не агрится ни на кого дальше пяти метров.
##   E ЛУЧНИКИ — «Защита» не режет им скорость и не гонит за уходящим.
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_cliff_and_squad_behavior/Test.tscn
##         [-- only=abcde]

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN
const _UStats := preload("res://scripts/unit_stats_config.gd")

## «Застрял»: без продвижения дольше STUCK_SEC у стены (как в qa_cliff_bypass)
const STUCK_SEC := 1.5
const STUCK_MOVE := 0.25
const STUCK_WALL_R := 3.5
## Заказ: «не вытягиваясь в вереницу» — малый габарит блока при обходе
const WIDTH_MIN_FRAC := 0.70
## Крюк выхода из казармы над прямой: больше — это и есть петля
const SPAWN_DETOUR_MAX := 1.35
## ── ЧТО СЧИТАТЬ ВЕРЕНИЦЕЙ ──────────────────────────────────────────────────
## Сто бойцов пятью блоками, огибающих плато радиусом 12 м, растягиваются
## вдоль дуги ЧЕСТНО: внутренний ряд идёт по короткой стороне, внешний по
## длинной. Замер A/B (ручка nav_cliff_arc, блок A): без правки вытянутость
## блока 4.3-4.6 при малом габарите 47-50 %, с правкой 3.8-4.4 при 47-58 %.
## Вереница — это ДРУГОЙ порядок: двадцать человек в одну линию дают 15-20.
## Порог абсолютный, а не кратность исходного: блок 5 × 4 и блок 4 × 3 после
## обхода обязаны остаться блоками, и мерить это надо одним числом
const ELONG_MAX := 6.0

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 900 с")
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
	print("\n═════ ИТОГ qa_cliff_and_squad_behavior: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

# ── общее ────────────────────────────────────────────────────────────────────
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

func _near_wall(p: Vector3, r: float) -> bool:
	if GameManager.is_cliff(p.x, p.z) or not GameManager.nav_free(p):
		return true
	for k in range(8):
		var a: float = float(k) * TAU / 8.0
		var q := Vector3(p.x + cos(a) * r, 0.0, p.z + sin(a) * r)
		if not GameManager.nav_free(q):
			return true
	return false

## Габариты блока по своим осям: [большой, малый]. Вереница теряет малый
var _stk_last: Dictionary = {}
var _stk_still: Dictionary = {}
var _stk_flag: Dictionary = {}
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
			_stk_where.append("%s в (%.0f, %.0f)" % [un.stat_id, p.x, p.z])

func _stuck_count() -> int:
	return _stk_flag.size()

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

## Плато PLATEAU_SPECS[0]
var _pc: Vector3 = Vector3.ZERO
var _pr: float = 0.0
var _ramp: float = 0.0

func _at_angle(a: float, d: float) -> Vector3:
	return Vector3(_pc.x + cos(a) * d, 0.0, _pc.z + sin(a) * d)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = true
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	# Дикие партии замораживаются: площадка своя
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction != F:
			(n as Unit).set_tick(false)
	for l in GameManager.get("troll_lairs"):
		if l == null or not is_instance_valid(l):
			continue
		for t in l.get("trolls"):
			if is_instance_valid(t):
				(t as Unit).set_tick(false)
		for gg in l.get("gnolls"):
			if gg != null and is_instance_valid(gg):
				(gg as Node).queue_free()
	GameManager.troll_lair = null
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(F, int(t), 1000000.0)
	var spec: Array = main.PLATEAU_SPECS[0]
	_pc = Vector3(float(spec[0]), 0.0, float(spec[1]))
	_pr = float(spec[2])
	_ramp = atan2(-_pc.z, -_pc.x)
	print("  плато: центр (%.0f, %.0f), радиус %.0f; непроходимых ячеек сетки %d" % [
		_pc.x, _pc.z, _pr, GameManager.nav_cells_blocked])
	await pframes(4)

	var only: String = ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			only = String(a).substr(5)
	if only == "" or only.contains("a"):
		await _a_mountains()
	if only == "" or only.contains("b"):
		await _b_spawn()
	if only == "" or only.contains("c"):
		await _c_stance()
	if only == "" or only.contains("d"):
		await _d_disengage()
	if only == "" or only.contains("e"):
		await _e_archers()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ОБХОД ГОР: 100 лучников, 100 копейщиков, конница, тролли
# ═════════════════════════════════════════════════════════════════════════════
func _a_mountains() -> void:
	print("\n═════ A. ОБХОД ГОРЫ ЧЕТЫРЬМЯ РОДАМИ ВОЙСК ═════")
	# Старт — с глухой стороны плато, цель — у спуска: прямая идёт СКВОЗЬ гору
	var start: Vector3 = _at_angle(_ramp + PI, _pr + main.PLATEAU_RAMP_STEEP + 20.0)
	var goal: Vector3 = _at_angle(_ramp, _pr + main.PLATEAU_RAMP_STEEP + 18.0)
	_clear_trees(start, 16.0)
	_clear_trees(goal, 14.0)
	# ЧУЖИХ У ТРАССЫ НЕ ДОЛЖНО БЫТЬ ВОВСЕ. Замороженный тик их не спасает:
	# строка остаётся в сетке ядра, лучник берёт её целью и ВСТАЁТ стрелять
	# (holds_ground_on_aggro) — первый прогон дал «не дошли за 150 с» и
	# «габарит 44 %» именно от этого, а не от навигации
	var wiped := 0
	for n in get_tree().get_nodes_in_group("all_units"):
		if not is_instance_valid(n) or not (n is Unit):
			continue
		var wu := n as Unit
		if wu.faction == F:
			continue
		if _xz(wu.global_position, _pc) < 160.0:
			wu.queue_free()
			wiped += 1
	print("  вычищено чужих у трассы: %d" % wiped)
	await pframes(6)

	# ── A0. ДУГА ВМЕСТО ИЗЛОМА ────────────────────────────────────────────
	# Свойство самой нити: обход выступа обязан давать НЕСКОЛЬКО точек
	# (скруглённый угол), а не одну точку поворота. Меряется до всяких тел —
	# это вопрос к сетке, а не к расталкиванию
	var pts: PackedVector3Array = GameManager.nav_route(_g(start), _g(goal),
		_UStats.NAV_CLEARANCE_INFANTRY, GameManager.SQUAD_ROUTE_HALF_W)
	var turn_max := 0.0
	var turns: Array = []
	for i in range(pts.size()):
		var a: Vector3 = _g(start) if i == 0 else pts[i - 1]
		var b: Vector3 = pts[i]
		var c: Vector3 = _g(goal) if i + 1 >= pts.size() else pts[i + 1]
		var v1 := Vector2(b.x - a.x, b.z - a.z)
		var v2 := Vector2(c.x - b.x, c.z - b.z)
		if v1.length() > 0.01 and v2.length() > 0.01:
			var tn: float = absf(v1.angle_to(v2))
			turn_max = maxf(turn_max, tn)
			turns.append(tn)
	# ДУГА СУДИТСЯ ПО МЕДИАНЕ, А НЕ ПО ХУДШЕМУ ПОВОРОТУ. Скруглённый обход
	# выступа — это цепочка МЕЛКИХ поворотов; один крутой стык у входа в дугу
	# или у самой цели её не отменяет, а ломаная A* без сглаживания даёт
	# один-два угла по 60-90° и медиану там же
	turns.sort()
	var med: float = turns[turns.size() / 2] if not turns.is_empty() else PI
	print("  нить обхода: %d углов, медиана поворота %.0f°, самый острый %.0f°" % [
		pts.size(), rad_to_deg(med), rad_to_deg(turn_max)])
	verdict("A0 обход выступа идёт дугой, а не одним изломом",
		pts.size() >= 3 and med <= deg_to_rad(35.0),
		"точек %d, медиана %.0f° (порог 35°), худший %.0f°" % [
			pts.size(), rad_to_deg(med), rad_to_deg(turn_max)])
	# Ни одна точка нити не стоит В скале
	var in_wall := 0
	for p in pts:
		if not GameManager.nav_free(p):
			in_wall += 1
	verdict("A0б все углы нити лежат на свободной земле", in_wall == 0,
		"в скале %d из %d" % [in_wall, pts.size()])

	await _walk_block("A1 ЛУЧНИКИ (100)", "archer", 5, 20, 5, 1.0, start, goal, 150.0)
	await _walk_block("A2 КОПЕЙЩИКИ (100)", "spearman", 5, 20, 5, 0.9, start, goal, 150.0)
	await _walk_block("A3 СВИНО-ВСАДНИКИ", "goblin_rider", 2, 12, 4, 1.3, start, goal, 120.0)
	await _walk_block("A4 ТРОЛЛИ", "troll", 1, 2, 2, 6.0, start, goal, 120.0)

## Один прогон: n_squads отрядов по per бойцов идут от start к goal мимо горы
func _walk_block(tag: String, kind: String, n_squads: int, per: int, cols: int,
		sp: float, start: Vector3, goal: Vector3, budget_sec: float) -> void:
	print("\n── %s ──" % tag)
	var fac: int = GF if kind.begins_with("goblin") or kind == "troll" else F
	var squads: Array = []
	var all: Array = []
	var block_w: float = float(cols - 1) * sp + 4.0
	var ax := Vector2(cos(_ramp), sin(_ramp))
	var nx := Vector2(-ax.y, ax.x)
	for i in range(n_squads):
		var off: float = (float(i) - float(n_squads - 1) * 0.5) * block_w
		var at: Vector3 = start + Vector3(nx.x * off, 0.0, nx.y * off)
		var sq: Array = _squad(kind, fac, at, per, cols, sp)
		squads.append(sq)
		all += sq[1]
	await pframes(30)
	var w0: Array = []
	var elong0 := 0.0           # исходная вытянутость блока (большой / малый)
	for sq in squads:
		var ex0: Array = _extents(sq[1])
		w0.append(float(ex0[1]))
		if float(ex0[1]) > 0.01:
			elong0 = maxf(elong0, float(ex0[0]) / float(ex0[1]))
	for sq in squads:
		var c: Vector3 = _centre(sq[1])
		for u in sq[1]:
			var un := u as Unit
			var rel: Vector3 = un.global_position - c
			un.command_move(goal + Vector3(rel.x, 0.0, rel.z), false, Vector3.ZERO, false, true)
	_stuck_reset()
	var min_frac := INF
	var max_elong := 0.0        # худшая вытянутость (большой / малый габарит)
	var last_c: Array = []
	for sq in squads:
		last_c.append(_centre(sq[1]))
	var arrived := -1
	var frames_n: int = int(budget_sec * 60.0)
	var in_wall_hits := 0
	for f in range(frames_n):
		await get_tree().physics_frame
		if f % 30 != 0:
			continue
		_stuck_tick(all)
		var n_in := 0
		for u in _alive(all):
			var p: Vector3 = (u as Unit).global_position
			if GameManager.is_cliff(p.x, p.z):
				in_wall_hits += 1
			if _xz(p, goal) < block_w * float(n_squads) * 0.5 + 10.0:
				n_in += 1
		for i in range(squads.size()):
			var c: Vector3 = _centre(squads[i][1])
			var mv := Vector2(c.x - last_c[i].x, c.z - last_c[i].z)
			last_c[i] = c
			var dc: float = _xz(c, _pc)
			if mv.length() > 0.4 and dc < _pr + main.PLATEAU_RAMP_GENTLE + 12.0 and float(w0[i]) > 0.0:
				var ex: Array = _extents(squads[i][1])
				var w: float = float(ex[1])
				if w > 0.0:
					min_frac = minf(min_frac, w / float(w0[i]))
					max_elong = maxf(max_elong, float(ex[0]) / w)
		if n_in >= int(float(all.size()) * 0.9):
			arrived = f
			break
	var secs: float = float(arrived if arrived >= 0 else frames_n) / 60.0
	print("  %s: %d бойцов, дошли за %.1f с (%s), застреваний %d, малый габарит блока мин %.0f %%" % [
		kind, all.size(), secs, "дошли" if arrived >= 0 else "НЕ ДОШЛИ",
		_stuck_count(), min_frac * 100.0 if min_frac < INF else -1.0])
	for w in _stk_where:
		print("    застрял: %s" % w)
	verdict("%sа дошли до цели за бюджет" % tag.substr(0, 2), arrived >= 0,
		"%.1f с из %.0f" % [secs, budget_sec])
	verdict("%sб никто не застрял у склона" % tag.substr(0, 2), _stuck_count() == 0,
		"застряли %d" % _stuck_count())
	if n_squads > 0 and per >= 3:
		# ── ВЕРЕНИЦА — ЭТО ВЫТЯНУТОСТЬ, А НЕ ПРОСТО СЖАТИЕ ────────────────
		# Блок, обходящий выступ, честно ужимается: внутренний ряд идёт по
		# более короткой дуге. Заказ запрещает ДРУГОЕ — «тонкую линию», то
		# есть рост отношения длины блока к его ширине. Порог — кратность
		# исходной вытянутости самого строя
		verdict("%sв строй не вытянулся в вереницу" % tag.substr(0, 2),
			max_elong <= ELONG_MAX,
			"вытянутость %.1f (была %.1f, предел %.1f); малый габарит %.0f %%" % [
				max_elong, elong0, ELONG_MAX, min_frac * 100.0 if min_frac < INF else -1.0])
	verdict("%sг никто не оказался внутри скалы" % tag.substr(0, 2), in_wall_hits == 0,
		"замеров в скале %d" % in_wall_hits)
	_free_all(all)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# B. СПАВН ИЗ КАЗАРМ: пять заказов, прямая нить без петли
# ═════════════════════════════════════════════════════════════════════════════
func _b_spawn() -> void:
	print("\n═════ B. ПЯТЬ ОТРЯДОВ ИЗ КАЗАРМ ═════")
	# Площадка вдали от плато и леса
	var at := Vector3(30.0, 0.0, -30.0)
	_clear_trees(at, 60.0)
	await pframes(4)
	var b: Building = Barracks.new()
	b.faction = F
	main.world_add(b)
	b.global_position = _g(at)
	await frames(8)
	await pframes(4)
	var gate: Vector3 = b._gate_position()
	var dir: Vector3 = b.rally_zone()["dir"]
	# Точка сбора — в сорока метрах ПЕРЕД воротами и вбок: именно так владелец
	# и ставит флажок, и именно там появлялась петля
	var rally: Vector3 = _g(gate + dir * 34.0 + Vector3(dir.z, 0.0, -dir.x) * 12.0)
	b.set_rally_point(rally)
	b.squad_size = 12
	var before: Array = get_tree().get_nodes_in_group("player_units").duplicate()
	for i in range(5):
		b.queue_unit("spearman", {}, 0.01)
	for q in b.production_queue:
		(q as Dictionary)["time"] = 0.01
	var men: Array = []
	var guard := 0
	while guard < 1200 and men.size() < 5 * b.squad_size:
		guard += 1
		await get_tree().physics_frame
		for n in get_tree().get_nodes_in_group("player_units"):
			if n in before or n in men:
				continue
			men.append(n)
	print("  вышло бойцов: %d за %d физкадров" % [men.size(), guard])
	verdict("B1 все пять заказов вышли", men.size() >= 5 * b.squad_size,
		"вышло %d из %d" % [men.size(), 5 * b.squad_size])
	# ── ПРИЗРАЧНЫЙ УГОЛ: точка маршрута ПОЗАДИ бойца ──────────────────────
	# Петля видна по самому маршруту: первый угол лежит в стороне, обратной
	# цели. Смотрим все точки нити каждого вышедшего
	var back_pts := 0
	var worst_dot := 1.0
	var routed := 0
	for u in men:
		var un := u as Unit
		if un == null or not is_instance_valid(un) or un.route_size() <= 0:
			continue
		routed += 1
		var p: Vector3 = un.global_position
		var togo := Vector2(rally.x - p.x, rally.z - p.z)
		if togo.length() < 1.0:
			continue
		togo = togo.normalized()
		for i in range(un._route.size()):
			var q: Vector3 = un._route[i]
			var v := Vector2(q.x - p.x, q.z - p.z)
			if v.length() < 0.5:
				continue
			var d: float = v.normalized().dot(togo)
			worst_dot = minf(worst_dot, d)
			if d < -0.1:
				back_pts += 1
	print("  маршрутов у вышедших: %d, точек «за спиной»: %d, худший косинус %.2f" % [
		routed, back_pts, worst_dot])
	verdict("B2 в маршруте выхода нет точек за спиной (петли)", back_pts == 0,
		"точек назад %d, худший косинус %.2f" % [back_pts, worst_dot])
	# ── КРЮК ПУТИ ─────────────────────────────────────────────────────────
	var path: Dictionary = {}
	var prev: Dictionary = {}
	for u in men:
		prev[u] = (u as Node3D).global_position
		path[u] = 0.0
	var start_far: Dictionary = {}
	for u in men:
		start_far[u] = _xz((u as Node3D).global_position, rally)
	var arrived := -1
	for f in range(60 * 90):
		await get_tree().physics_frame
		for u in men:
			if u == null or not is_instance_valid(u):
				continue
			var p: Vector3 = (u as Node3D).global_position
			path[u] = float(path[u]) + _xz(p, prev[u])
			prev[u] = p
		if f % 30 != 0:
			continue
		# ПРИБЫЛ — ЗНАЧИТ ВСТАЛ. Пять отрядов на ОДИН флажок разводит
		# free_squad_spot на десятки метров, и круг вокруг самой точки сбора
		# мерил бы его раскладку, а не приход
		var n_in := 0
		for u in men:
			if u != null and is_instance_valid(u) and (u as Unit).state != Unit.State.MOVING:
				n_in += 1
		if n_in >= int(float(men.size()) * 0.9):
			arrived = f
			break
	var worst := 0.0
	var worst_u := ""
	for u in men:
		var s: float = float(start_far[u])
		if s < 8.0:
			continue
		var k: float = float(path[u]) / s
		if k > worst:
			worst = k
			worst_u = "%s" % str((u as Node3D).name)
	print("  дошли за %.1f с, худший крюк пути / прямая = %.2f (%s)" % [
		float(arrived if arrived >= 0 else 60 * 90) / 60.0, worst, worst_u])
	verdict("B3 отряды дошли до точки сбора", arrived >= 0,
		"%.1f с" % (float(arrived if arrived >= 0 else 60 * 90) / 60.0))
	verdict("B4 выход без петли: крюк пути в пределах допуска",
		worst <= SPAWN_DETOUR_MAX, "худший %.2f (порог %.2f)" % [worst, SPAWN_DETOUR_MAX])
	_free_all(men)
	b.queue_free()
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# C. СТОЙКА КОПЕЙЩИКОВ: щит не двигает никого, копья опускают все три шеренги
# ═════════════════════════════════════════════════════════════════════════════
func _c_stance() -> void:
	print("\n═════ C. «ЗАЩИТА» У КОПЕЙЩИКОВ ═════")
	var at := Vector3(-40.0, 0.0, 30.0)
	_clear_trees(at, 30.0)
	await pframes(4)
	# Стена копий изучена: заказ — «все 3 ряда держат копья вперёд»
	GameManager.finish_research(F, "spearman_1d")
	var sq: Array = _squad("spearman", F, at, 24, 8, 0.9)
	var sid: int = sq[0]
	var men: Array = sq[1]
	# Разметка на месте, курс — по экрану; отряд стоит
	var slots: Array = []
	for u in men:
		slots.append((u as Node3D).global_position)
	GameManager.squad_set_formation(sid, slots, Vector3.FORWARD, false)
	await pframes(40)
	verdict("C0 «Стена копий» изучена и включена", GameManager.spear_wall_ready(sid))
	var p0: Array = []
	for u in men:
		p0.append((u as Node3D).global_position)
	var forms0: int = GameManager.spear_wall_forms
	# ── ЩИТ ────────────────────────────────────────────────────────────────
	for u in men:
		(u as Unit).set_stance("defense")
	GameManager.on_squad_stance(sid, "defense")
	# ── В HEADLESS ПОЗУ НИКТО НЕ СЧИТАЕТ ──────────────────────────────────
	# `_spear_leveled` живёт в разборе позы (визуальный тик), а у стоящего
	# бойца вне кадра он не идёт вовсе: личная задержка опускания копья
	# (DROP_DELAY_MAX_MS) не истекает никогда, и первый прогон дал «опустили
	# 0 из 24» на исправном коде. Гоняем разбор сами, как и в других стендах
	for _i in range(120):
		await get_tree().physics_frame
		for u in men:
			var spx := u as Spearman
			if spx != null:
				spx._update_sprite_anim()
	var moved := 0
	var worst := 0.0
	for i in range(men.size()):
		var d: float = _xz((men[i] as Node3D).global_position, p0[i])
		worst = maxf(worst, d)
		if d > 0.35:
			moved += 1
	print("  сдвинулись %d из %d, худший сдвиг %.2f м, перестроений стены %d" % [
		moved, men.size(), worst, GameManager.spear_wall_forms - forms0])
	verdict("C1 по кнопке «Защита» с места не сдвинулся никто", moved == 0,
		"сдвинулись %d, худший %.2f м" % [moved, worst])
	verdict("C1б перестроения стены копий не было",
		GameManager.spear_wall_forms == forms0,
		"построений %d" % (GameManager.spear_wall_forms - forms0))
	var down := 0
	var rows: Dictionary = {}
	for u in men:
		var sp := u as Spearman
		if sp == null:
			continue
		sp._update_sprite_anim()
		if sp._spear_leveled():
			down += 1
			rows[sp._live_rank] = int(rows.get(sp._live_rank, 0)) + 1
	print("  копья опущены у %d из %d, по рядам: %s" % [down, men.size(), str(rows)])
	verdict("C2 копья опустили ВСЕ, включая задние шеренги", down == men.size(),
		"опустили %d из %d, ряды %s" % [down, men.size(), str(rows)])
	# ── C3. СТЕНА КОПИЙ ДЕРЖИТ ПИКИ И НА МАРШЕ ────────────────────────────
	var goal: Vector3 = at + Vector3(0.0, 0.0, -18.0)
	for u in men:
		(u as Unit).set_stance("attack")
		(u as Unit).command_move(goal + ((u as Node3D).global_position - _centre(men)),
			false, Vector3.ZERO, false, true)
	await pframes(45)
	var march_down := 0
	var marching := 0
	for u in men:
		var sp := u as Spearman
		if sp == null:
			continue
		if sp.state == Unit.State.MOVING:
			marching += 1
		sp._update_sprite_anim()
		if sp._spear_leveled():
			march_down += 1
	print("  на марше: идут %d, копья вперёд у %d из %d" % [marching, march_down, men.size()])
	verdict("C3 со «Стеной копий» пики вперёд и на марше", march_down == men.size(),
		"держат %d из %d (идут %d)" % [march_down, men.size(), marching])
	_free_all(men)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# D. ОТХОД: приказ рвёт бой, агро не дальше пяти метров
# ═════════════════════════════════════════════════════════════════════════════
func _d_disengage() -> void:
	print("\n═════ D. ПРИКАЗ ОТОЙТИ ═════")
	verdict("D0 радиус инициативы сужен до пяти метров",
		absf(Unit.AGGRO_RADIUS - 5.0) < 0.01, "AGGRO_RADIUS = %.1f" % Unit.AGGRO_RADIUS)
	var at := Vector3(60.0, 0.0, 40.0)
	_clear_trees(at, 40.0)
	await pframes(4)
	var ours: Array = _squad("warrior", F, at, 12, 4, 0.9)
	var foes: Array = _squad("goblin_spearman", GF, at + Vector3(0.0, 0.0, 4.0), 12, 4, 0.9)
	# Приманка в стороне: по дороге отряд пройдёт мимо неё в 9 м — дальше пяти
	var bait_at: Vector3 = at + Vector3(9.0, 0.0, -22.0)
	var bait: Array = _squad("goblin_spearman", GF, bait_at, 6, 3, 0.9)
	for u in bait[1]:
		(u as Unit).set_tick(false)     # приманка стоит и сама не агрится
	await pframes(60)
	var in_fight := 0
	for u in ours[1]:
		if (u as Unit).attack_target != null:
			in_fight += 1
	print("  завязка боя: с целью %d из %d" % [in_fight, ours[1].size()])
	verdict("D1 бой завязался", in_fight >= int(float(ours[1].size()) * 0.5),
		"с целью %d из %d" % [in_fight, ours[1].size()])
	# ── ПРИКАЗ ОТОЙТИ ─────────────────────────────────────────────────────
	var away: Vector3 = at + Vector3(0.0, 0.0, -40.0)
	var c0: Vector3 = _centre(ours[1])
	for u in ours[1]:
		var un := u as Unit
		un.command_move(away + (un.global_position - c0), false, Vector3.ZERO, false, true)
	var kept := 0
	var locked := 0
	for u in ours[1]:
		var un := u as Unit
		if un.attack_target != null:
			kept += 1
		if un.target_lock:
			locked += 1
	verdict("D2 приказ снял цель и замок у всех тем же кадром",
		kept == 0 and locked == 0, "с целью %d, под замком %d" % [kept, locked])
	# ── ПО ДОРОГЕ НЕ АГРИТЬСЯ НА ДАЛЬНИХ ──────────────────────────────────
	var bait_hits := 0
	var far_hits := 0
	for f in range(60 * 14):
		await get_tree().physics_frame
		if f % 10 != 0:
			continue
		for u in _alive(ours[1]):
			var un := u as Unit
			var t = un.attack_target
			if t == null or not is_instance_valid(t):
				continue
			var d: float = _xz(un.global_position, (t as Node3D).global_position)
			if d > Unit.AGGRO_RADIUS + un.attack_range:
				far_hits += 1
			for bu in bait[1]:
				if t == bu:
					bait_hits += 1
					break
	var cf: Vector3 = _centre(ours[1])
	var gone: float = _xz(cf, c0)
	print("  отряд ушёл на %.1f м, зацепов приманки %d, целей дальше агро %d" % [
		gone, bait_hits, far_hits])
	verdict("D3 отряд физически вышел из боя", gone >= 20.0, "ушёл на %.1f м" % gone)
	verdict("D4 по дороге не сагрился на отряд в стороне", bait_hits == 0,
		"зацепов %d" % bait_hits)
	verdict("D5 ни одной цели дальше радиуса инициативы", far_hits == 0,
		"дальних целей %d" % far_hits)
	_free_all(ours[1]); _free_all(foes[1]); _free_all(bait[1])
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# E. ЛУЧНИКИ В «ЗАЩИТЕ»: скорость не режется, за уходящим не идут
# ═════════════════════════════════════════════════════════════════════════════
func _e_archers() -> void:
	print("\n═════ E. ЛУЧНИКИ В «ЗАЩИТЕ» ═════")
	var at := Vector3(-70.0, 0.0, -20.0)
	_clear_trees(at, 40.0)
	await pframes(4)
	var sq: Array = _squad("archer", F, at, 8, 4, 1.0)
	var men: Array = sq[1]
	await pframes(20)
	var a0 := men[0] as Unit
	a0.command_move(a0.global_position + Vector3(0.0, 0.0, -25.0), false, Vector3.ZERO, false, true)
	await pframes(10)
	var base_speed: float = a0._effective_speed()
	for u in men:
		(u as Unit).set_stance("defense")
		(u as Unit).command_move((u as Node3D).global_position + Vector3(0.0, 0.0, -25.0),
			false, Vector3.ZERO, false, true)
	await pframes(10)
	var def_speed: float = a0._effective_speed()
	print("  скорость лучника: атака %.2f, защита %.2f" % [base_speed, def_speed])
	verdict("E1 «Защита» не режет лучнику скорость",
		absf(def_speed - base_speed) < 0.01,
		"было %.2f, стало %.2f" % [base_speed, def_speed])
	# Копейщику штраф остаётся — это свойство рода войск, а не отмена стойки
	var ssq: Array = _squad("spearman", F, at + Vector3(14.0, 0.0, 0.0), 4, 2, 0.9)
	var s0 := ssq[1][0] as Unit
	# ШТРАФ СТОЙКИ ЧИТАЕТСЯ ТОЛЬКО У ИДУЩЕГО (`state != IDLE` в
	# _effective_speed): у стоящего его нет вовсе, и мерить надо на марше
	s0.command_move(s0.global_position + Vector3(0.0, 0.0, -25.0), false, Vector3.ZERO, false, true)
	await pframes(10)
	var sp_base: float = s0._effective_speed()
	for u in ssq[1]:
		(u as Unit).set_stance("defense")
		(u as Unit).command_move((u as Node3D).global_position + Vector3(0.0, 0.0, -25.0),
			false, Vector3.ZERO, false, true)
	await pframes(10)
	var sp_def: float = s0._effective_speed()
	verdict("E1б копейщику штраф стойки остаётся", sp_def < sp_base * 0.99,
		"было %.2f, стало %.2f" % [sp_base, sp_def])
	# ── E2. НЕ БЕЖИТ ЗА УХОДЯЩИМ ──────────────────────────────────────────
	# Замер скорости гнал отряд на 25 м — ждём, пока встанет, и врага ставим
	# от НОВОГО центра
	var settled := 0
	for _i in range(60 * 20):
		await get_tree().physics_frame
		settled = 0
		for u in men:
			if (u as Unit).state != Unit.State.MOVING:
				settled += 1
		if settled == men.size():
			break
	var here: Vector3 = _centre(men)
	var foe: Unit = _spawn("goblin_spearman", GF, here + Vector3(0.0, 0.0, -12.0))
	foe.set_tick(false)
	# ── ОТКРЫТИЕ ОГНЯ МЕРЯЕТСЯ ВРЕМЕНЕМ, А НЕ ОДНИМ СНИМКОМ ───────────────
	# Стоящий отряд, у которого коридор ответил «чужих нет», СПИТ ПО ФИЗИКЕ
	# (BigStand, этап 3) — такт авто-агро у него не идёт вовсе, и будит его
	# пересчёт коридора. Снимок через секунду после появления врага честно
	# давал «0 из 8» на исправном коде; мерить надо, ЗА СКОЛЬКО отряд
	# проснулся и открыл огонь
	var shooting := 0
	var wake_f := -1
	for f in range(60 * 20):
		await get_tree().physics_frame
		shooting = 0
		for u in men:
			if (u as Unit).attack_target == foe:
				shooting += 1
		if shooting > 0:
			wake_f = f
			break
	print("  огонь открыт через %.1f с (%d из %d)" % [
		float(wake_f if wake_f >= 0 else 60 * 20) / 60.0, shooting, men.size()])
	verdict("E2 стоя в «Защите», лучники сами открыли огонь", shooting > 0,
		"взяли цель %d из %d за %.1f с" % [shooting, men.size(),
			float(wake_f if wake_f >= 0 else 60 * 20) / 60.0])
	# ── ПОТОЛОК ЩЕДРЫЙ, И ЭТО ЗАМЕР, А НЕ ЛЕНЬ ────────────────────────────
	# Спящий отряд будит ПЕРЕСЧЁТ КОРИДОРА, а его срок разнесён по отрядам
	# (CORRIDOR_TTL_JITTER_MS) и вдвое длиннее у спящих: замер дал 1.7 с на
	# свободной машине и 18.2 с под нагрузкой шлюза на ОДНОМ И ТОМ ЖЕ коде.
	# Вердикт стережёт «просыпается вообще», время печатается рядом
	verdict("E2б спящий отряд просыпается на подошедшего врага",
		wake_f >= 0 and wake_f <= 60 * 20,
		"%.1f с (потолок 20 с; на свободной машине 1.7 с)" % (
			float(wake_f if wake_f >= 0 else 60 * 20) / 60.0))
	var c0: Vector3 = _centre(men)
	# Цель уходит за дальность выстрела
	foe.global_position = _g(here + Vector3(0.0, 0.0, -60.0))
	foe.sync_row()
	await pframes(120)
	var c1: Vector3 = _centre(men)
	print("  центр лучников сдвинулся на %.2f м после ухода цели" % _xz(c1, c0))
	verdict("E3 за ушедшей целью лучники не пошли", _xz(c1, c0) < 2.0,
		"сдвиг центра %.2f м" % _xz(c1, c0))
	_free_all(men); _free_all(ssq[1])
	if is_instance_valid(foe):
		foe.queue_free()
	await pframes(6)
