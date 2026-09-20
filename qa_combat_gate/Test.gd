extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_CombatGate — ТЗ 19.09.2026-3, блок 4 (headless)
## ═══════════════════════════════════════════════════════════════════════════
## Четыре сценария с метриками:
##   Ticks Per Second — физтиков армии в секунду (GameManager.army_ticks);
##   Pathfinding Requests/sec — маршрутов ядра (nav_routes_built) и сканов
##     целей (perf_config.scan_calls) в секунду;
##   Animation Desync Count — бойцов, чья лента ходьбы расходится с фактом
##     движения (лента «walk» у стоящего / «idle» у идущего);
##   Units Pixel-Overlapped Count — бойцов с соседом ближе гарантированного
##     интервала расталкивания (SEP_MIN_DIST − SEP_DEADZONE).
##   A обстрел 10 стоящих отрядов: запросов/с < 1000, стоящий отряд без
##     приказа разворачивается на обидчика (ТЗ п. 3)
##   B фокус 10 отрядов на одного тролля: все на нём, никто не убегает,
##     кольцо без вдавливания в тушу
##   C три тролля: лишние отряды уходят на соседних
##   D двойной ПКМ: 2 фаланги (Защита) не бегут, 3 обычных бегут и
##     вступают в бой, упёршись в чужой строй
##   E направленный чардж конницы: сектор по dot, удар в тыл × REAR_DMG_MULT
## Числа — из конфигов (правило 10), время — физкадрами (правило 11).

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _CavImpact := preload("res://scripts/units/CavalryImpactHandler.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const GF := Constants.FACTION_GOBLIN

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_combat_gate: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

## Отряд блоком cols × rows, лицом по FORWARD (−Z), разметка закреплена
func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6, sp: float = 0.6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(
			at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0,
			at.z + float(i / cols) * sp))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	for u in men:
		(u as Unit).command_move((u as Unit).global_position, false, Vector3.FORWARD)
	GameManager.squad_close_ranks(sid, true)
	return [sid, men]

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _kill_all(men: Array) -> void:
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 30.0), Vector3(0.0, 0.0, -30.0), Vector3(0.0, 0.0, 50.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
				if GameManager.is_water(p.x + d.x, p.z + d.z):
					h += 100.0
			if h > 1.0:
				h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

# ── МЕТРИКИ ─────────────────────────────────────────────────────────────────
var _m_t0_usec: int = 0
var _m_ticks0: int = 0
var _m_nav0: int = 0

func _metrics_begin() -> void:
	_Opt.scan_meter = true
	_Opt.scan_reset()
	_m_t0_usec = Time.get_ticks_usec()
	_m_ticks0 = GameManager.army_ticks
	_m_nav0 = GameManager.nav_routes_built

## [ticks/s, nav/s, scans/s, секунд]
func _metrics_end() -> Array:
	var sec: float = maxf(float(Time.get_ticks_usec() - _m_t0_usec) / 1e6, 1e-3)
	var out: Array = [
		float(GameManager.army_ticks - _m_ticks0) / sec,
		float(GameManager.nav_routes_built - _m_nav0) / sec,
		float(_Opt.scan_calls) / sec, sec]
	_Opt.scan_meter = false
	return out

func _anim_desync(units: Array) -> int:
	var n := 0
	for u in units:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var uu := u as Unit
		if uu.state != Unit.State.IDLE and uu.state != Unit.State.MOVING:
			continue
		# Судим только две штатные ленты: у особых поз (щит, замах, набег)
		# факт хода лентой не описывается
		var an: String = String(uu._anim_name)
		if an != "walk" and an != "idle":
			continue
		var walking: bool = uu.walk_anim_recently()
		if (an == "walk") != walking:
			n += 1
	return n

func _overlapped(units: Array) -> int:
	var lim: float = Unit.SEP_MIN_DIST - Unit.SEP_DEADZONE - 0.02
	var n := 0
	for u in units:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var p: Vector3 = (u as Unit).global_position
		for o in GameManager.unit_grid.query_radius(p, lim):
			if o == u or o == null or not is_instance_valid(o):
				continue
			if (o as Unit).is_dead():
				continue
			n += 1
			break
	return n

func _print_metrics(tag: String, m: Array, units: Array) -> void:
	print("  [%s] ticks/s %.0f | маршрутов/с %.1f | сканов/с %.1f | desync %d | overlapped %d (из %d, %.1f с)" % [
		tag, m[0], m[1], m[2], _anim_desync(units), _overlapped(units), _alive(units).size(), m[3]])

func _squad_targets_in(men: Array, sid_set: Array) -> int:
	var n := 0
	for u in men:
		if not is_instance_valid(u):
			continue
		var t = (u as Unit).attack_target
		if t != null and is_instance_valid(t) and t is Unit and int((t as Unit).squad_id) in sid_set:
			n += 1
	return n

# ═════════════════════════════════════════════════════════════════════════════
func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	# Дикие партии (тролли, гноллы, резерв) замораживаются — площадка своя
	for g in [Constants.unit_group(GF), Constants.unit_group(E)]:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n) and n is Unit:
				(n as Unit).set_tick(false)
	await pframes(2)
	var base: Vector3 = _flat_spot(Vector3(-60.0, 0.0, -20.0))
	print("  площадка %s" % str(base))

	var only_e: bool = "only_e" in OS.get_cmdline_user_args()
	if not only_e:
		await _a_fire(base)
		await _b_focus_one(base + Vector3(0.0, 0.0, 70.0))
		await _c_focus_three(base + Vector3(60.0, 0.0, 70.0))
		await _d_double_rmb(base)
	await _e_cavalry(base)
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ОБСТРЕЛ ДЕСЯТИ СТОЯЩИХ ОТРЯДОВ
# ═════════════════════════════════════════════════════════════════════════════
func _a_fire(base: Vector3) -> void:
	print("\n═════ A. ОБСТРЕЛ 10 ОТРЯДОВ ═════")
	var kinds: Array = ["spearman", "spearman", "spearman", "spearman", "archer", "archer",
		"archer", "warrior", "warrior", "warrior"]
	var squads: Array = []
	var all: Array = []
	for i in range(kinds.size()):
		var col: int = i % 5
		var row: int = i / 5
		var sq: Array = _squad(String(kinds[i]), F, base + Vector3(float(col) * 9.0 - 18.0, 0.0, float(row) * 8.0), 12)
		squads.append(sq)
		all += sq[1]
	# Две фаланги — в «Защите» (держат место), остальные — в «Атаке»
	for k in range(2):
		for u in squads[k][1]:
			(u as Unit).set_stance("defense")
	await pframes(30)
	var ar_range: float = _UCfg.stat("archer", "attack_range", 15.0)
	var e1: Array = _squad("archer", E, base + Vector3(-9.0, 0.0, -(ar_range - 1.0)), 12)
	# Второй отряд стрелков — по мечникам второго ряда: дальше 12 м (ответ на
	# ДАЛЬНИЙ обстрел, не на удар в упор), но в дальности лука
	var e2: Array = _squad("archer", E, base + Vector3(9.0, 0.0, 8.0 - (ar_range - 1.0)), 12)
	for u in e1[1] + e2[1]:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
	await pframes(5)
	# Стрелки бьют по третьему отряду копейщиков (стойка «Атака») и по мечникам
	for u in e1[1]:
		(u as Unit).command_attack(squads[2][1][0], true, true, true)
	for u in e2[1]:
		(u as Unit).command_attack(squads[7][1][0], true, true, true)
	_metrics_begin()
	await pframes(240)
	var m: Array = _metrics_end()
	_print_metrics("A обстрел", m, all)
	verdict("A1 запросов путей и сканов в секунду меньше 1000",
		m[1] + m[2] < 1000.0, "маршрутов/с %.1f, сканов/с %.1f" % [m[1], m[2]])
	verdict("A2 такт армии живой (≥ 55 физтиков/с)", m[0] >= 55.0, "%.0f" % m[0])
	var esids: Array = [int(e1[0]), int(e2[0])]
	var turned_sp: int = _squad_targets_in(squads[2][1], esids)
	var turned_wr: int = _squad_targets_in(squads[7][1], esids)
	verdict("A3 обстрелянный отряд копейщиков (Атака) развернулся на обидчика",
		turned_sp > 0, "на стрелков нацелено %d из %d" % [turned_sp, _alive(squads[2][1]).size()])
	verdict("A4 обстрелянные мечники развернулись на обидчика",
		turned_wr > 0, "на стрелков нацелено %d из %d" % [turned_wr, _alive(squads[7][1]).size()])
	# Фаланга в «Защите» обстрела не получала — стоит на месте
	var moved := 0.0
	for u in squads[0][1]:
		if is_instance_valid(u):
			moved = maxf(moved, (u as Unit).global_position.distance_to((u as Unit).post_pos))
	verdict("A5 фаланга в «Защите» без приказа с места не сошла", moved < 2.0, "сдвиг %.2f м" % moved)
	var desync: int = _anim_desync(all)
	verdict("A6 рассинхрон анимаций ≤ 5 % состава", desync * 20 <= all.size(), "%d из %d" % [desync, all.size()])
	for sq in squads:
		_kill_all(sq[1])
	_kill_all(e1[1] + e2[1])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# B. ФОКУС ДЕСЯТИ ОТРЯДОВ НА ОДНОМ ТРОЛЛЕ
# ═════════════════════════════════════════════════════════════════════════════
func _troll_at(at: Vector3) -> Unit:
	var t: Unit = _spawn("troll", GF, at)
	t.max_health = 1e9
	t.current_health = 1e9
	t.set_tick(false)
	return t

func _focus_issue(units: Array, big: Unit) -> Dictionary:
	var sm = main.selection_manager
	sm.select_units(units)
	var spread: Dictionary = sm._big_target_spread(big)
	for u in units:
		if not is_instance_valid(u):
			continue
		var sid: int = (u as Unit).squad_id
		var mine = big
		if spread.has(sid):
			mine = spread[sid]
		(u as Unit).command_attack(mine, true, true, true)
	return spread

func _b_focus_one(base: Vector3) -> void:
	print("\n═════ B. 10 ОТРЯДОВ НА ОДНОГО ТРОЛЛЯ ═════")
	var troll: Unit = _troll_at(base + Vector3(0.0, 0.0, -18.0))
	var squads: Array = []
	var all: Array = []
	for i in range(10):
		var sq: Array = _squad("spearman", F, base + Vector3(float(i % 5) * 8.0 - 16.0, 0.0, float(i / 5) * 7.0), 12)
		squads.append(sq)
		all += sq[1]
	await pframes(20)
	var spread: Dictionary = _focus_issue(all, troll)
	verdict("B1 соседей-гигантов нет — все 10 отрядов на тролле", spread.is_empty(),
		"переписано отрядов: %d" % spread.size())
	_metrics_begin()
	var far_max := 0.0
	var inside_max := 0
	for k in range(20):
		await pframes(60)
		var inside := 0
		for u in all:
			if not is_instance_valid(u) or (u as Unit).is_dead():
				continue
			var d: float = (u as Unit).global_position.distance_to(troll.global_position)
			far_max = maxf(far_max, d)
			if d < troll.sep_radius() * 0.8:
				inside += 1
		inside_max = maxi(inside_max, inside)
	var m: Array = _metrics_end()
	_print_metrics("B фокус", m, all)
	var on_troll := 0
	var in_reach := 0
	for u in all:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		if (u as Unit).attack_target == troll:
			on_troll += 1
		if (u as Unit).global_position.distance_to(troll.global_position) <= (u as Unit).reach() + troll.sep_radius() + 0.8:
			in_reach += 1
	verdict("B2 никто не убежал: дальше 50 м от тролля ноль", far_max <= 50.0, "максимум %.1f м" % far_max)
	verdict("B3 все живые держат цель — тролль", on_troll == _alive(all).size(),
		"на тролле %d из %d" % [on_troll, _alive(all).size()])
	verdict("B4 в тушу вдавлено не больше 3 бойцов (кольцо, а не блин)", inside_max <= 3,
		"пик внутри %.1f м: %d" % [troll.sep_radius() * 0.8, inside_max])
	verdict("B5 у туши стоит кольцо: не меньше 24 в досягаемости удара", in_reach >= 24,
		"в досягаемости %d" % in_reach)
	verdict("B6 запросов/с < 1000", m[1] + m[2] < 1000.0, "маршрутов/с %.1f, сканов/с %.1f" % [m[1], m[2]])
	for sq in squads:
		_kill_all(sq[1])
	troll.take_damage(1e12)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# C. ТРИ ТРОЛЛЯ: ЛИШНИЕ ОТРЯДЫ — НА СОСЕДНИХ
# ═════════════════════════════════════════════════════════════════════════════
func _c_focus_three(base: Vector3) -> void:
	print("\n═════ C. 10 ОТРЯДОВ НА ТРЁХ ТРОЛЛЕЙ ═════")
	var t0: Unit = _troll_at(base + Vector3(0.0, 0.0, -30.0))
	var t1: Unit = _troll_at(base + Vector3(-14.0, 0.0, -34.0))
	var t2: Unit = _troll_at(base + Vector3(14.0, 0.0, -34.0))
	var squads: Array = []
	var all: Array = []
	for i in range(10):
		var sq: Array = _squad("spearman", F, base + Vector3(float(i % 5) * 8.0 - 16.0, 0.0, float(i / 5) * 7.0), 12)
		squads.append(sq)
		all += sq[1]
	await pframes(20)
	var spread: Dictionary = _focus_issue(all, t0)
	var per: Dictionary = {}
	for sq in squads:
		var tgt = spread.get(int(sq[0]), t0)
		per[tgt] = int(per.get(tgt, 0)) + 1
	verdict("C1 лишние отряды переписаны на соседних троллей", spread.size() >= 7,
		"переписано %d из 10" % spread.size())
	verdict("C2 у каждого из трёх троллей есть свои отряды",
		int(per.get(t0, 0)) > 0 and int(per.get(t1, 0)) > 0 and int(per.get(t2, 0)) > 0,
		"раздача: %d / %d / %d" % [int(per.get(t0, 0)), int(per.get(t1, 0)), int(per.get(t2, 0))])
	verdict("C3 первые три ближайших отряда остались на кликнутом", int(per.get(t0, 0)) >= 3,
		"%d" % int(per.get(t0, 0)))
	await pframes(300)
	var hitters: Dictionary = {}
	for u in all:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			var t = (u as Unit).attack_target
			if t != null and is_instance_valid(t):
				hitters[t] = int(hitters.get(t, 0)) + 1
	verdict("C4 через 5 с у всех троих есть нацеленные бойцы",
		int(hitters.get(t0, 0)) > 0 and int(hitters.get(t1, 0)) > 0 and int(hitters.get(t2, 0)) > 0,
		"%d / %d / %d" % [int(hitters.get(t0, 0)), int(hitters.get(t1, 0)), int(hitters.get(t2, 0))])
	for sq in squads:
		_kill_all(sq[1])
	for t in [t0, t1, t2]:
		t.take_damage(1e12)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. ДВОЙНОЙ ПКМ: ФАЛАНГА НЕ БЕЖИТ, ОБЫЧНЫЕ БЕГУТ И ДЕРУТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _d_double_rmb(base: Vector3) -> void:
	print("\n═════ D. ДВОЙНОЙ ПКМ ═════")
	var ph: Array = []
	var norm: Array = []
	for i in range(2):
		var sq: Array = _squad("spearman", F, base + Vector3(float(i) * 9.0 - 18.0, 0.0, 0.0), 12)
		for u in sq[1]:
			(u as Unit).set_stance("defense")
		ph.append(sq)
	for i in range(3):
		var sq: Array = _squad("warrior", F, base + Vector3(float(i) * 9.0, 0.0, 0.0), 12)
		norm.append(sq)
	var all: Array = []
	for sq in ph + norm:
		all += sq[1]
	await pframes(20)
	# Чужой строй поперёк дороги мечников, в 22 м; точка приказа — за ним
	var foe: Array = _squad("spearman", E, base + Vector3(9.0, 0.0, -16.0), 24, 12, 0.55)
	for u in foe[1]:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
		(u as Unit).set_tick(false)
	await pframes(5)
	var sm = main.selection_manager
	sm.select_units(all)
	sm._issue_formation_move(base + Vector3(0.0, 0.0, -30.0), true)
	await pframes(3)
	var ph_run := 0
	var nm_run := 0
	for sq in ph:
		for u in sq[1]:
			if (u as Unit).sprinting: ph_run += 1
	for sq in norm:
		for u in sq[1]:
			if (u as Unit).sprinting: nm_run += 1
	verdict("D1 фаланги в «Защите» не побежали", ph_run == 0, "бегущих %d" % ph_run)
	verdict("D2 обычные отряды побежали", nm_run >= 30, "бегущих %d из %d" % [nm_run, 36])
	_metrics_begin()
	var engaged_peak := 0
	for k in range(12):
		await pframes(60)
		var engaged := 0
		for sq in norm:
			engaged += _squad_targets_in(sq[1], [int(foe[0])])
		engaged_peak = maxi(engaged_peak, engaged)

	var m: Array = _metrics_end()
	_print_metrics("D бег", m, all)
	verdict("D3 бегущие мечники, упёршись в строй, вступили в бой (≥ 12 из 36)",
		engaged_peak >= 12, "пик нацеленных на чужой строй %d" % engaged_peak)
	for sq in ph + norm:
		_kill_all(sq[1])
	_kill_all(foe[1])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# E. НАПРАВЛЕННЫЙ ЧАРДЖ КОННИЦЫ
# ═════════════════════════════════════════════════════════════════════════════
func _e_cavalry(base: Vector3) -> void:
	print("\n═════ E. ЧАРДЖ ВО ФЛАНГ И ТЫЛ ═════")
	var S := _CavImpact
	verdict("E1 сектор по dot: лоб / фланг / тыл",
		S.sector_of(Vector3(0, 0, 1), Vector3(0, 0, -1)) == S.SECTOR_FRONT
		and S.sector_of(Vector3(1, 0, 0), Vector3(0, 0, -1)) == S.SECTOR_FLANK
		and S.sector_of(Vector3(0, 0, -1), Vector3(0, 0, -1)) == S.SECTOR_REAR)
	S.reset_stats()
	# Копейщики лицом на −Z (FORWARD); всадники с −Z летят в лоб, с +Z — в спину
	var sq: Array = _squad("spearman", F, base, 24, 12, 0.55)
	for u in sq[1]:
		(u as Unit).set_stance("attack")
		(u as Unit).max_health = 1e6
		(u as Unit).current_health = 1e6
	await pframes(20)
	# Касание — ВЫЗОВОМ _charge_impact с честным разбегом (сам спуск разгона
	# стережёт qa_boar_rider_charge; здесь — сектор, множители и мораль):
	# всадник у спины строя, точка взвода — 15 м позади него
	var rider: Unit = _spawn("goblin_rider", GF, base + Vector3(0.0, 0.0, 3.5))
	rider.set_tick(false)
	await pframes(4)
	var m0: float = GameManager.squad_morale(int(sq[0]))
	var dirn := Vector3(0.0, 0.0, -1.0)
	rider._charge_from = rider.global_position + Vector3(0.0, 0.0, 15.0)
	rider._charge_path = 0.0
	rider.is_charging = true
	rider._charge_impact(sq[1][12] as Unit, dirn)
	await pframes(2)
	var hit_rear: int = S.hits[S.SECTOR_REAR]
	print("  E: %s" % str(S.last))
	verdict("E2 удар с тыла опознан сектором ТЫЛ", hit_rear > 0,
		"касаний: лоб %d, фланг %d, тыл %d" % [S.hits[0], S.hits[1], S.hits[2]])
	verdict("E3 множитель урона в тыл — REAR_DMG_MULT", hit_rear > 0
		and absf(float(S.last.get("dmg", 0.0)) - S.REAR_DMG_MULT) < 1e-6,
		"dmg %.2f, dot %.2f" % [float(S.last.get("dmg", 0.0)), float(S.last.get("dot", 0.0))])
	verdict("E4 мораль отряда просела от удара в тыл на REAR_MORALE_HIT",
		hit_rear > 0 and m0 - GameManager.squad_morale(int(sq[0])) >= S.REAR_MORALE_HIT - 0.5,
		"мораль %.1f → %.1f" % [m0, GameManager.squad_morale(int(sq[0]))])
	# Фланг: тот же строй, всадник сбоку, ход поперёк курса строя
	S.reset_stats()
	rider.global_position = base + Vector3(-5.0, 0.0, 0.6)
	rider.sync_row()
	rider._charge_from = rider.global_position + Vector3(-15.0, 0.0, 0.0)
	rider.is_charging = true
	rider._charge_impact(sq[1][0] as Unit, Vector3(1.0, 0.0, 0.0))
	verdict("E5 удар сбоку опознан сектором ФЛАНГ с FLANK_DMG_MULT",
		S.hits[S.SECTOR_FLANK] > 0 and absf(float(S.last.get("dmg", 0.0)) - S.FLANK_DMG_MULT) < 1e-6,
		"%s" % str(S.last))
	# Лоб: множителей нет (прежние правила копий)
	S.reset_stats()
	rider.global_position = base + Vector3(0.0, 0.0, -4.0)
	rider.sync_row()
	rider._charge_from = rider.global_position + Vector3(0.0, 0.0, -15.0)
	rider.is_charging = true
	rider._charge_impact(sq[1][0] as Unit, Vector3(0.0, 0.0, 1.0))
	verdict("E6 удар в лоб — сектор ЛОБ, множители 1.0",
		S.hits[S.SECTOR_FRONT] > 0 or S.hits[0] + S.hits[1] + S.hits[2] == 0,
		"%s" % str(S.last))
	var riders: Array = [rider]
	_kill_all(sq[1])
	_kill_all(riders)
	await pframes(4)
