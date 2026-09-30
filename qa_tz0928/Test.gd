extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tz0928 — ТЗ 25.09.2026: отряды у кромки карты, оборона базы ИИ в
## три уровня, пробуждение гарнизона, стрелы за картой
## ═══════════════════════════════════════════════════════════════════════════
##   A  squad_inside: центр отрядного приказа держится от кромки на полуразмер
##      строя + SQUAD_EDGE_PAD; внутри поля точка не трогается; границы сняты —
##      не трогается вовсе
##   B  EnemyAI._apply_orders: отряд, посланный планировщиком В КРОМКУ, встаёт
##      прямоугольником внутри поля, а не ниткой вдоль борта (скриншоты 25.09)
##   C  Подкрепление базы ИИ (spawn_ai_reinforcements): уровни 2 и 3 — линии
##      поперёк курса обороны и посты у передних башен; все посты внутри карты,
##      отряды не накладываются, ни один не сплющен в линию
##   D  Пробуждение: удар по ЛЮБОМУ отряду гарнизона поднимает ВЕСЬ гарнизон;
##      чужой у поста линии (вне зоны замка) — тоже тревога
##   E  Стрелы: прицел за кромкой зажимается к полю (_clamp_aim), узел из пула
##      втыкается внутри карты, прицел внутри поля не трогается
## Запуск: <godot> --headless --path . res://qa_tz0928/Test.tscn [-- only=abcde]

const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _TowerS := preload("res://scripts/Tower.gd")

var main = null
var ai = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _only: String = "abcde"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5).to_lower()
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
	print("\n═════ ИТОГ qa_tz0928: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit(1 if _fail > 0 else 0)

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
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

func _members(sid: int) -> Array:
	var rec: Variant = GameManager.squads.get(sid)
	if rec == null:
		return []
	var out: Array = []
	for m in (rec as Dictionary).get("members", []):
		if is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _kill(men: Array) -> void:
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _enemy_castle() -> Castle:
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is Castle and (b as Castle).is_stronghold():
			return b as Castle
	return null

## Габарит точек по осям: [ширина по X, глубина по Z]
func _bbox(pts: Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var x0 := INF; var x1 := -INF; var z0 := INF; var z1 := -INF
	for p in pts:
		var v: Vector3 = p
		x0 = minf(x0, v.x); x1 = maxf(x1, v.x)
		z0 = minf(z0, v.z); z1 = maxf(z1, v.z)
	return Vector2(x1 - x0, z1 - z0)

func _run() -> void:
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(10):
		await get_tree().process_frame
	ai = main.enemy_ai
	if ai != null:
		ai.set_process(false)
		ai._peace_over = true
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.pop_limit_enabled = false
	await pframes(4)
	print("\n═════ qa_tz0928 (границы %s, map_lim %.1f × %.1f) ═════" % [
		str(GameManager.world_bounds_enabled), GameManager.map_lim_x, GameManager.map_lim_z])
	if "a" in _only: await _a_inside()
	if "b" in _only: await _b_ai_edge()
	if "c" in _only: await _c_reinforcements()
	if "d" in _only: await _d_wake_all()
	if "e" in _only: await _e_arrows()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. squad_inside
# ═════════════════════════════════════════════════════════════════════════════
func _a_inside() -> void:
	print("\n═════ A. squad_inside ═════")
	var lz: float = GameManager.map_lim_z
	var lx: float = GameManager.map_lim_x
	var pad: float = GameManager.SQUAD_EDGE_PAD
	var p := Vector3(-150.0, 0.0, lz + 30.0)
	var q: Vector3 = GameManager.squad_inside(p, 2.75, 1.65)
	verdict("A1 центр за нижней кромкой → внутрь на полуширину + %.0f м" % pad,
		absf(q.z - (lz - 2.75 - pad)) < 0.01 and q.x == p.x, "z %.2f, ждали %.2f" % [q.z, lz - 2.75 - pad])
	var p2 := Vector3(-lx - 5.0, 0.0, lz + 5.0)
	var q2: Vector3 = GameManager.squad_inside(p2, 4.0)
	verdict("A2 угол карты: обе оси", absf(q2.x + (lx - 4.0 - pad)) < 0.01 and absf(q2.z - (lz - 4.0 - pad)) < 0.01,
		"%.1f, %.1f" % [q2.x, q2.z])
	var p3 := Vector3(10.0, 0.0, -20.0)
	verdict("A3 точка в поле не трогается", GameManager.squad_inside(p3, 5.0) == p3)
	GameManager.world_bounds_enabled = false
	verdict("A4 границы сняты — точка как есть", GameManager.squad_inside(p, 5.0) == p)
	GameManager.world_bounds_enabled = true

# ═════════════════════════════════════════════════════════════════════════════
# B. EnemyAI: приказ в кромку
# ═════════════════════════════════════════════════════════════════════════════
func _b_ai_edge() -> void:
	print("\n═════ B. ОТРЯД ИИ, ПОСЛАННЫЙ В КРОМКУ ═════")
	if ai == null:
		verdict("B0 enemy_ai есть", false)
		return
	var lz: float = GameManager.map_lim_z
	var n: int = _UCfg.squad_size("spearman")
	var base := Vector3(-120.0, 0.0, lz - 40.0)
	var sq_r: Array = _squad("spearman", Constants.FACTION_ENEMY, base, n, 10, 0.55)
	var men: Array = sq_r[1]
	await pframes(3)
	ai._regroup()
	var sq: Dictionary = {}
	for s in ai.squads:
		if (s as Dictionary)["members"].has(men[0]):
			sq = s
			break
	verdict("B0 отряд подобран EnemyAI", not sq.is_empty())
	if sq.is_empty():
		_kill(men)
		return
	# Чужие у кромки (охрана рудника стороны красного, ТЗ 29.09.2026 третье
	# письмо: до 100 гоблинов в 60 м, патруль плавает) — не наш сюжет: ИИ
	# честно шлёт линию в атаку, и посты ложатся по врагу, а не по разметке
	for fu in get_tree().get_nodes_in_group("all_units"):
		if fu is Unit and not (fu as Unit).is_dead() and (fu as Unit).faction != Constants.FACTION_ENEMY \
				and (fu as Unit).global_position.distance_to(Vector3(-120.0, 0.0, lz)) < 80.0:
			(fu as Unit).take_damage(1.0e12)
	await pframes(3)
	# Планировщик шлёт ЛИНИЮ ровно на кромку, курсом на север (шеренги вглубь — к югу, за край)
	var course := Vector3(0.0, 0.0, -1.0)
	sq["role"] = ai.ROLE_LINE
	sq["target"] = Vector3(-120.0, 0.0, lz)
	sq["face"] = course
	sq["issued"] = false
	ai._apply_orders()
	# Раздача идёт очередью — ждём, пока у всех появится пост
	for _w in range(120):
		await pframes(1)
		var got := 0
		for u in men:
			if (u as Unit).state == Unit.State.MOVING:
				got += 1
		if got >= n - 2:
			break
	var pad: float = GameManager.SQUAD_EDGE_PAD
	var posts: Array = []
	var worst: float = -INF
	for u in men:
		var pp: Vector3 = (u as Unit).post_pos
		posts.append(pp)
		worst = maxf(worst, pp.z)
	var bb: Vector2 = _bbox(posts)
	verdict("B1 ни один пост не ближе %.0f м к кромке (худший z %.1f при кромке %.1f)" % [pad, worst, lz],
		worst <= lz - pad + 0.6)
	verdict("B2 разметка — прямоугольник, а не нитка: глубина %.1f м (≥ 1.5), ширина %.1f м" % [bb.y, bb.x],
		bb.y >= 1.5 and bb.x >= 3.0)
	# Дошли и встали — центр отряда внутри поля
	for _w in range(40):
		await pframes(30)
		var idle := 0
		for u in men:
			if (u as Unit).state == Unit.State.IDLE:
				idle += 1
		if idle >= n - 3:
			break
	var live: Array = []
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			live.append((u as Unit).global_position)
	var bb2: Vector2 = _bbox(live)
	var zmax := -INF
	for p in live:
		zmax = maxf(zmax, (p as Vector3).z)
	verdict("B3 на месте: строй глубиной %.1f м, самый южный z %.1f (кромка %.1f)" % [bb2.y, zmax, lz],
		bb2.y >= 1.2 and zmax < lz - 1.0)
	# Строй по местам — _posts_intact не переиздаёт приказ каждый такт
	sq["issued"] = true
	var before: Array = []
	for u in men:
		before.append((u as Unit).state)
	ai._apply_orders()
	await pframes(3)
	var re := 0
	for i in range(men.size()):
		if (men[i] as Unit).state == Unit.State.MOVING and before[i] == Unit.State.IDLE:
			re += 1
	verdict("B4 стоящий у кромки строй не переиздаётся (_posts_intact против зажатых слотов)", re <= 2,
		"сдвинуто с места %d" % re)
	_kill(men)
	ai.squads = []
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# C. ПОДКРЕПЛЕНИЕ БАЗЫ ИИ — УРОВНИ 2 И 3
# ═════════════════════════════════════════════════════════════════════════════
var _line_posts: Array = []

func _c_reinforcements() -> void:
	print("\n═════ C. ПОДКРЕПЛЕНИЕ: ЛИНИИ И БАШНИ ═════")
	var keep: Castle = _enemy_castle()
	verdict("C0 крепость ИИ стоит", keep != null)
	if keep == null:
		return
	var guard = main.enemy_guard
	var before: int = guard.squads.size() if guard != null else 0
	var placed: int = main.spawn_ai_reinforcements()
	guard = main.enemy_guard
	verdict("C1 поставлено %d отрядов подкрепления" % _AICfg.REINFORCE_SQUADS, placed == _AICfg.REINFORCE_SQUADS,
		"поставлено %d" % placed)
	await pframes(3)
	var recs: Array = guard.squads.slice(before)
	var cpos: Vector3 = keep.global_position
	var course: Vector3 = main._home_course(cpos)
	var side := Vector3(-course.z, 0.0, course.x)
	var pad: float = GameManager.SQUAD_EDGE_PAD
	var inside := true
	var no_line := true
	var depths := ""
	var lines := 0
	var at_tower := 0
	var towers: Array = []
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is _TowerS:
			towers.append((b as Node3D).global_position)
	for s in recs:
		var post: Vector3 = s["post"]
		_line_posts.append(post)
		if absf(post.x) > GameManager.map_lim_x - pad + 0.1 or absf(post.z) > GameManager.map_lim_z - pad + 0.1:
			inside = false
		var pts: Array = []
		for m in _members(int(s["sid"])):
			pts.append((m as Unit).global_position)
		var bb: Vector2 = _bbox(pts)
		depths += "%.1fx%.1f " % [bb.x, bb.y]
		if minf(bb.x, bb.y) < 1.5:
			no_line = false
		var off: Vector3 = post - cpos
		var along: float = off.x * course.x + off.z * course.z
		var lvl: int = int(s.get("level", 0))
		# Линии: пост в полосе [LINE_DIST − глубина блока − просвет; LINE_DIST]
		if lvl == 2 and along >= _AICfg.HOME_LINE_DIST - 12.0 and along <= _AICfg.HOME_LINE_DIST + 1.0:
			lines += 1
		# Периметр: у башни впереди линий либо на фланге первой линии
		if lvl == 3:
			var near_tower := false
			for tp in towers:
				if _xz(post, tp) <= _AICfg.HOME_TOWER_POST_DIST + 6.0:
					near_tower = true
			var lateral: float = absf(off.x * side.x + off.z * side.z)
			if near_tower or (absf(along - _AICfg.HOME_LINE_DIST) < 1.5 and lateral > 8.0):
				at_tower += 1
	verdict("C2 все посты внутри карты с отступом %.0f м" % pad, inside)
	verdict("C3 ни один отряд не сплющен в линию (габариты %s)" % depths, no_line)
	var want_lines: int = mini(_AICfg.REINFORCE_SQUADS, _AICfg.HOME_LINE_SQUADS * _AICfg.HOME_LINE_ROWS)
	verdict("C4 уровень 2: %d отрядов в линиях на %.0f м по курсу обороны" % [want_lines, _AICfg.HOME_LINE_DIST],
		lines == want_lines, "в линиях %d" % lines)
	var want_tower: int = _AICfg.REINFORCE_SQUADS - want_lines
	verdict("C5 уровень 3: %d отрядов на периметре (башни впереди линий или фланги)" % want_tower,
		at_tower == want_tower, "на периметре %d" % at_tower)
	# Отряды не накладываются: центры разнесены не меньше чем на ширину блока
	var min_d := INF
	for i in range(recs.size()):
		for j in range(i + 1, recs.size()):
			min_d = minf(min_d, _xz(recs[i]["post"], recs[j]["post"]))
	verdict("C6 посты разнесены (ближайшая пара %.1f м ≥ 5.5)" % min_d, min_d >= 5.5)
	# Ни один пост не на кольце охраны и не в фундаменте замка
	var off_ring := true
	for s in recs:
		if _xz(s["post"], cpos) < _AICfg.HOME_RING_DIST + 4.0:
			off_ring = false
	verdict("C7 посты гарнизона дальше кольца охраны от замка", off_ring)
	verdict("C8 все спят под охраной", guard.asleep_count() == guard.squads.size(),
		"спит %d из %d" % [guard.asleep_count(), guard.squads.size()])

# ═════════════════════════════════════════════════════════════════════════════
# D. ПРОБУЖДЕНИЕ ВСЕМ ГАРНИЗОНОМ
# ═════════════════════════════════════════════════════════════════════════════
func _d_wake_all() -> void:
	print("\n═════ D. ТРЕВОГА ПОДНИМАЕТ ВЕСЬ ГАРНИЗОН ═════")
	var guard = main.enemy_guard
	var keep: Castle = _enemy_castle()
	if guard == null or keep == null or _line_posts.is_empty():
		verdict("D0 гарнизон и линии на месте", false)
		return
	var total: int = guard.squads.size()
	verdict("D0 до тревоги спят все (%d)" % total, guard.asleep_count() == total and not guard.alarm)
	# Обидчик — далеко от замка (вне HOME_GUARD_ZONE), бьёт отряд ЛИНИИ
	var far_post: Vector3 = _line_posts[0]
	for p in _line_posts:
		if _xz(p, keep.global_position) > _xz(far_post, keep.global_position):
			far_post = p
	var course: Vector3 = main._home_course(keep.global_position)
	var at: Vector3 = far_post + course * (_AICfg.HOME_GUARD_POST_ZONE + 8.0)
	var hitter: Unit = _spawn("archer", Constants.FACTION_PLAYER, at)
	hitter.max_health = 1e9; hitter.current_health = 1e9; hitter._soa_push_stats()
	await pframes(int(_AICfg.HOME_GUARD_TICK_SEC * 60.0) * 2 + 4)
	verdict("D1 чужой в %.0f м от поста (вне зоны замка) тревоги не даёт" % (_AICfg.HOME_GUARD_POST_ZONE + 8.0),
		not guard.alarm and _xz(at, keep.global_position) > _AICfg.HOME_GUARD_ZONE,
		"тревога %s, до замка %.0f" % [str(guard.alarm), _xz(at, keep.global_position)])
	# Обстрел: удар по бойцу линии
	var victim_sid: int = 0
	for s in guard.squads:
		if (s["post"] as Vector3) == far_post:
			victim_sid = int(s["sid"])
	var victim: Unit = _members(victim_sid)[0] if victim_sid > 0 else null
	if victim != null:
		victim.take_damage(5.0, hitter)
	await pframes(int(_AICfg.HOME_GUARD_TICK_SEC * 60.0) * 2 + 6)
	verdict("D2 удар по отряду линии — тревога, встал ВЕСЬ гарнизон (%d)" % total,
		guard.alarm and guard.asleep_count() == 0, "тревога %s, спит %d" % [str(guard.alarm), guard.asleep_count()])
	var with_target := 0
	for s in guard.squads:
		for m in _members(int(s["sid"])):
			var u := m as Unit
			if u.attack_target != null or u.state == Unit.State.ATTACKING:
				with_target += 1
				break
	verdict("D3 проснувшиеся отряды получили цель (%d из %d)" % [with_target, total], with_target >= total / 2)
	# Снять: обидчик убит, тревога спадает, все идут домой (не ждём прихода)
	hitter.take_damage(1e12)
	await pframes(int(_AICfg.HOME_GUARD_CALM_SEC * 60.0) + 90)
	verdict("D4 угрозы нет — тревога снята", not guard.alarm)
	# Чужой У ПОСТА (POST_ZONE - 2), вне зоны замка — тревога без единого удара
	var near: Vector3 = far_post + course * (_AICfg.HOME_GUARD_POST_ZONE - 2.0)
	var sq_r: Array = _squad("spearman", Constants.FACTION_PLAYER, near, 6, 3, 0.7)
	for u in sq_r[1]:
		(u as Unit).set_stance("defense")
	await pframes(int(_AICfg.HOME_GUARD_TICK_SEC * 60.0) * 3 + 6)
	verdict("D5 чужой в %.0f м от поста линии будит гарнизон (вне зоны замка %.0f м)" % [
			_AICfg.HOME_GUARD_POST_ZONE - 2.0, _AICfg.HOME_GUARD_ZONE],
		guard.alarm and _xz(near, keep.global_position) > _AICfg.HOME_GUARD_ZONE,
		"тревога %s" % str(guard.alarm))
	_kill(sq_r[1])
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# E. СТРЕЛЫ ЗА КАРТОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _e_arrows() -> void:
	print("\n═════ E. СТРЕЛЫ ЗА КРОМКОЙ ═════")
	var lz: float = GameManager.map_lim_z
	var start := Vector3(-100.0, 1.2, lz - 15.0)
	var aim := Vector3(-100.0, 0.0, lz + 12.0)
	var n0: int = GameManager.arrows_clamped
	var q: Vector3 = GameManager._clamp_aim(start, aim)
	verdict("E1 прицел за кромкой зажат к полю (z %.1f ≤ %.1f)" % [q.z, lz - GameManager.ARROW_EDGE_PAD],
		q.z <= lz - GameManager.ARROW_EDGE_PAD + 0.01 and GameManager.arrows_clamped == n0 + 1)
	var inside := Vector3(-100.0, 0.0, lz - 30.0)
	verdict("E2 прицел внутри поля не трогается", GameManager._clamp_aim(start, inside) == inside)
	# Узел из пула (projectile_core = false): втыкается внутри карты
	var was: bool = _Opt.projectile_core
	_Opt.projectile_core = false
	var world: Node = main.get("_world")
	var shooter: Unit = _spawn("archer", Constants.FACTION_PLAYER, Vector3(start.x, 0.0, start.z))
	var a: Node3D = GameManager.spawn_arrow(world, start, aim, start.distance_to(aim), 30.0, 0.2, 1.0,
		shooter, Constants.FACTION_PLAYER)
	var landed := false
	for _w in range(240):
		await pframes(1)
		if a != null and is_instance_valid(a) and bool(a.get("_spent")):
			landed = true
			break
	var az: float = a.global_position.z if a != null and is_instance_valid(a) else INF
	verdict("E3 стрела-узел приземлилась внутри карты (z %.1f < кромка %.1f)" % [az, lz], landed and az < lz)
	_Opt.projectile_core = was
	# Ядро: выстрел за кромку не даёт ни одной висящей за краем — прицел зажат до записи
	var n1: int = GameManager.arrows_clamped
	GameManager.fire_projectile(world, start, aim, start.distance_to(aim), 30.0, 0.2, 1.0,
		shooter, Constants.FACTION_PLAYER)
	verdict("E4 путь ядра тоже зажимает прицел (счётчик +1)", GameManager.arrows_clamped == n1 + 1)
	shooter.take_damage(1e12)
	await pframes(4)
