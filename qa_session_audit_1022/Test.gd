extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД АУДИТА ПАРТИИ 22.10.2026 (performance_log_2026-10-22_1451.json)
## ═══════════════════════════════════════════════════════════════════════════
##   A — пауза не двигает игровые часы (Unit.game_ms): после паузы сроки
##       боя и очередь у ворот замка не истекают разом (лог: пауза ~3.5 мин
##       после падения крепости красных, «вход в замок за 258.7 с» при 45 с)
##   B — точка приказа в ПРОСВЕТЕ лесной стены (маска стволов свободна,
##       клетка навигации закрыта) выносится наружу: land_target и
##       squad_inside; живой отряд, посланный в такую точку, доходит без
##       вызволений. Справочно — то же с выключенной ручкой nav_pocket_out
##       (лог: посты красных у своей базы x≈−192, z≈26-28 в полосе стены,
##       49-55 вызволений на отряд)
##   C — отказ «нет места» в телеметрию — не чаще раза в 15 с на отряд
##       (лог: 107 одинаковых отказов за две минуты)
##   D — игровые часы инвариантны к Engine.time_scale и к просадке FPS
##       (max_physics_steps_per_frame = 1): Unit.game_ms — сумма delta физики,
##       часы партии Main и ИИ идут от того же источника без расхождения
##   E — проходимость точки — один предикат (is_passable) в ядре: совпадает
##       с четырьмя предикатами по одному на сетке точек (лес, река,
##       фундамент), поиск ближайшей — один переход и признак неудачи INF с
##       записью в телеметрию; _sweep_trapped не оставляет пост в просвете
## Запуск: godot --headless --path . res://qa_session_audit_1022/Test.tscn [-- only=abcde]

const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcde"
## Блок D: стенд нагружает кадр отрисовки (просадка FPS) и считает физкадры
var _slow_ms: int = 0
var _phys_n: int = 0
var _done := false
var _core_pick: Vector3 = Vector3.INF

func _ready() -> void:
	# Стенд обязан жить на паузе дерева (блок A)
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(900.0, true).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_session_audit_1022: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

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
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _place(b: Building, at: Vector3, fac: int = F) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _clear_units(at: Vector3, r: float) -> void:
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and (b as Node3D).global_position.distance_to(at) < r:
			b.queue_free()

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "a" in _only: await _a_pause_clock()
	if "b" in _only: await _b_forest_pocket()
	if "c" in _only: await _c_refused_spam()
	if "d" in _only: await _d_clock_invariance()
	if "e" in _only: await _e_passable()
	_finish()

func _process(_delta: float) -> void:
	if _slow_ms > 0:
		OS.delay_msec(_slow_ms)

func _physics_process(_delta: float) -> void:
	_phys_n += 1

# ─────────────────────────────────────────────────────────────────────────────
# A. ПАУЗА НЕ ДВИГАЕТ ИГРОВЫЕ ЧАСЫ
# ─────────────────────────────────────────────────────────────────────────────
func _a_pause_clock() -> void:
	print("\n═════ A. ПАУЗА И ИГРОВЫЕ ЧАСЫ ═════")
	var base := Vector3(-60, 0, -40)
	_clear_units(base, 70.0)
	main._clear_trees(base, 70.0)
	await pframes(3)
	var c := Castle.new()
	_place(c, base)
	await pframes(10)
	# Отряд в 45 м от замка просится внутрь — идёт, терпение у дверей не вышло
	var men: Array = _squad("spearman", base + Vector3(45, 0, 0), 12)
	var sid: int = (men[0] as Unit).squad_id
	await pframes(5)
	var ok_req: bool = c.request_garrison(sid)
	await pframes(30)
	var q0: float = c._queue_secs(sid)
	var g0: int = Unit.game_ms()
	var w0: int = Time.get_ticks_msec()
	get_tree().paused = true
	await frames(2)
	var g_mid0: int = Unit.game_ms()
	OS.delay_msec(3000)
	await frames(2)
	var g_mid1: int = Unit.game_ms()
	get_tree().paused = false
	await pframes(2)
	var w1: int = Time.get_ticks_msec()
	var g1: int = Unit.game_ms()
	var q1: float = c._queue_secs(sid)
	print("  A: стенные %d мс, игровые %d мс; очередь у ворот %.1f → %.1f с" % [w1 - w0, g1 - g0, q0, q1])
	verdict("A1 на паузе игровые часы стоят", g_mid1 == g_mid0, "%d → %d" % [g_mid0, g_mid1])
	verdict("A2 после паузы в 3 с игровые часы ушли меньше чем на 0.5 с", w1 - w0 >= 3000 and g1 - g0 < 500,
		"стенные %d, игровые %d" % [w1 - w0, g1 - g0])
	verdict("A3 срок очереди у ворот замка не съеден паузой (< 1.5 с прибавки)", ok_req and q1 - q0 < 1.5,
		"%.1f → %.1f" % [q0, q1])
	_free(men)
	c.queue_free()
	await pframes(10)

# ─────────────────────────────────────────────────────────────────────────────
# B. ПРОСВЕТ В ЛЕСНОЙ СТЕНЕ
# ─────────────────────────────────────────────────────────────────────────────
## Точки полосы стены базы красных, где маска стволов свободна, а клетка
## навигации закрыта (ровно то, что ловили посты красных в логе)
func _pockets() -> Array:
	var out: Array = []
	var specs: Array = main._wall_specs()
	if specs.is_empty():
		return out
	var sp: Dictionary = specs[0]
	var x := -205.0
	while x < -135.0:
		var zc: float = main._wall_z_of(sp, x)
		var dz := -3.0
		while dz <= 3.0:
			var z: float = zc + dz
			if not GameManager.is_cliff(x, z) and not GameManager.army.nav_free(x, z) \
					and not GameManager.in_building(x, z):
				out.append(Vector3(x, 0.0, z))
			dz += 0.5
		x += 1.3
	return out

## Середина полосы стены: точки В СТВОЛАХ (is_cliff) — так ложились посты
## красных из лога; старый поиск уводил их в ближайший просвет внутри леса
func _band_core() -> Array:
	var out: Array = []
	var specs: Array = main._wall_specs()
	if specs.is_empty():
		return out
	var sp: Dictionary = specs[0]
	var x := -205.0
	while x < -135.0:
		var zc: float = main._wall_z_of(sp, x)
		for dz in [-1.0, 0.0, 1.0]:
			var z: float = zc + float(dz)
			if GameManager.is_cliff(x, z):
				out.append(Vector3(x, 0.0, z))
		x += 1.7
	return out

func _b_forest_pocket() -> void:
	var core: Array = _band_core()
	var stuck_old := 0
	var stuck_new := 0
	for p0 in core:
		_Opt.nav_pocket_out = false
		var a: Vector3 = GameManager.land_target(p0)
		_Opt.nav_pocket_out = true
		var b: Vector3 = GameManager.land_target(p0)
		if not GameManager.army.nav_free(a.x, a.z):
			stuck_old += 1
		if not GameManager.army.nav_free(b.x, b.z):
			stuck_new += 1
	print("  B: точек в стволах середины полосы %d; land_target в закрытую клетку: без ручки %d, с ручкой %d" % [
		core.size(), stuck_old, stuck_new])
	# Сплошная лес-стена (ТЗ 23.10.2026, третье письмо): просвет — тоже стена в
	# едином предикате, и наружу выносит уже БЕЗ nav_pocket (stuck_old 0)
	verdict("B5 точка в стволах середины стены: без ручки уходила в просвет внутри леса, с ручкой — наружу",
		core.size() >= 5 and stuck_new == 0 and (stuck_old > 0 or _Opt.forest_nav_solid),
		"без ручки %d из %d в лесу, с ручкой %d" % [stuck_old, core.size(), stuck_new])
	if stuck_old > 0:
		for p1 in core:
			_Opt.nav_pocket_out = false
			var a1: Vector3 = GameManager.land_target(p1)
			_Opt.nav_pocket_out = true
			if not GameManager.army.nav_free(a1.x, a1.z):
				_core_pick = p1
				break

	print("\n═════ B. ТОЧКА ПРИКАЗА В ПРОСВЕТЕ ЛЕСНОЙ СТЕНЫ ═════")
	var pk: Array = _pockets()
	if _Opt.forest_nav_solid:
		# Первопричина снята: просветов «маска свободна, клетка закрыта» нет
		verdict("B0 у стены базы красных НЕТ просветов «маска свободна, клетка закрыта» (стена сплошная)",
			pk.is_empty(), "%d точек" % pk.size())
		return
	verdict("B0 у стены базы красных есть просветы «маска свободна, клетка закрыта» (условие замера)",
		pk.size() >= 5, "%d точек" % pk.size())
	if pk.size() < 5:
		return
	var out_ok := 0
	var worst := 0.0
	var inside_ok := 0
	for p in pk:
		var q: Vector3 = GameManager.land_target(p)
		if GameManager.army.nav_free(q.x, q.z) and not GameManager.is_cliff(q.x, q.z):
			out_ok += 1
		worst = maxf(worst, Vector2(q.x - p.x, q.z - p.z).length())
		var s: Vector3 = GameManager.squad_inside(p, 3.0)
		if GameManager.army.nav_free(s.x, s.z):
			inside_ok += 1
	verdict("B1 land_target выносит каждую такую точку на свободную клетку (сдвиг ≤ 12 м)",
		out_ok == pk.size() and worst <= 12.0, "%d из %d, худший сдвиг %.1f м" % [out_ok, pk.size(), worst])
	verdict("B2 squad_inside (центр отрядного приказа ИИ) — тоже наружу", inside_ok == pk.size(),
		"%d из %d" % [inside_ok, pk.size()])
	# Живой отряд красных: стоит к югу от стены, послан в просвет
	var res_on: Dictionary = await _b_live(pk, true)
	var res_off: Dictionary = await _b_live(pk, false)
	print("  B: с ручкой — дошли %d из %d, вызволений %d; без ручки — дошли %d из %d, вызволений %d" % [
		res_on["arrived"], res_on["n"], res_on["unstuck"], res_off["arrived"], res_off["n"], res_off["unstuck"]])
	verdict("B3 отряд, посланный в просвет стены, доходит (≥ 90 %) без вызволений (≤ 2)",
		res_on["arrived"] >= int(res_on["n"] * 0.9) and res_on["unstuck"] <= 2,
		"дошли %d из %d, вызволений %d" % [res_on["arrived"], res_on["n"], res_on["unstuck"]])
	# Справка, не вердикт: без ручки исход зависит от того, у какого края
	# полосы лёг просвет (у ближнего — дойти можно)
	print("  B4 справочно: без ручки nav_pocket_out дошли %d из %d, вызволений %d" % [
		res_off["arrived"], res_off["n"], res_off["unstuck"]])

func _b_live(pk: Array, knob: bool) -> Dictionary:
	_Opt.nav_pocket_out = knob
	_Opt.telemetry = true
	# Самый глубокий просвет — дальше всех от свободной клетки (как посты
	# красных в логе у середины полосы)
	var tgt: Vector3 = pk[0]
	var deep := -1.0
	var was: bool = _Opt.nav_pocket_out
	_Opt.nav_pocket_out = true
	for p in pk:
		var q: Vector3 = GameManager.land_target(p)
		var dd: float = Vector2(q.x - p.x, q.z - p.z).length()
		if dd > deep:
			deep = dd
			tgt = p
	_Opt.nav_pocket_out = was
	# Предпочтительно — точка в стволах, которую старый поиск увёл в лес
	if _core_pick != Vector3.INF:
		tgt = _core_pick
	print("  B: цель %s, ручка %s" % [str(tgt), str(knob)])
	var start := Vector3(tgt.x, 0.0, tgt.z - 16.0)
	# Чужие у площадки (охрана базы красных, отряды орды) уводили отряд в бой
	for u0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u0) and (u0 as Node3D).global_position.distance_to(start) < 90.0:
			u0.queue_free()
	await pframes(3)
	var men: Array = _squad("spearman", start + Vector3(-2, 0, -2), 12, E, 4)
	await pframes(10)
	var ev0: int = GameManager.tm_events.size()
	# Как приказ ИИ (EnemyAI._apply_orders): центр отряда — через
	# squad_inside, места бойцов — вокруг него
	var centre: Vector3 = GameManager.squad_inside(tgt, 1.5)
	for i in range(men.size()):
		var u: Unit = men[i]
		var off := Vector3(float(i % 4) * 0.7 - 1.0, 0, float(i / 4) * 0.7 - 0.7)
		u.command_move(centre + off)
	# Ждём СВОЙСТВО с потолком: ближайшая свободная клетка бывает за стеной,
	# и отряд обходит её проходом (под нагрузкой шлюза 25 с не хватало)
	var t := 0
	var arrived := 0
	while t < 60 * 70:
		await pframes(30)
		t += 30
		arrived = _arrived_count(men)
		if arrived == men.size():
			break
	print("  B: ждали %.1f с" % (float(t) / 60.0))
	print("  B: центр %s (клетка свободна %s), старт %s" % [str(centre), str(GameManager.army.nav_free(centre.x, centre.z)), str(start)])
	for m3 in men.slice(0, 4):
		if is_instance_valid(m3):
			var u3: Unit = m3
			print("    боец %s → %s, сост %d" % [str(u3.global_position.snapped(Vector3.ONE * 0.1)), str(u3.move_target.snapped(Vector3.ONE * 0.1)), int(u3.state)])
	var uns := 0
	var evs: Array = GameManager.tm_events
	for k in range(ev0, evs.size()):
		var e: Array = evs[k]
		if String(e[1]) in ["unstuck", "unstuck_giveup"]:
			uns += 1
	_free(men)
	await pframes(10)
	_Opt.nav_pocket_out = true
	return {"arrived": arrived, "n": men.size(), "unstuck": uns}

func _arrived_count(men: Array) -> int:
	var n := 0
	for m in men:
		if not is_instance_valid(m):
			continue
		var u2: Unit = m
		var mt: Vector3 = u2.move_target
		var p: Vector3 = u2.global_position
		if u2.state != Unit.State.MOVING and Vector2(p.x - mt.x, p.z - mt.z).length() < 2.5:
			n += 1
	return n

# ─────────────────────────────────────────────────────────────────────────────
# C. ОТКАЗ «НЕТ МЕСТА» В ТЕЛЕМЕТРИЮ — НЕ ЧАЩЕ РАЗА В 15 С
# ─────────────────────────────────────────────────────────────────────────────
func _c_refused_spam() -> void:
	print("\n═════ C. ТЕЛЕМЕТРИЯ ОТКАЗОВ ГАРНИЗОНА ═════")
	_Opt.telemetry = true
	var base := Vector3(-60, 0, 30)
	_clear_units(base, 60.0)
	main._clear_trees(base, 60.0)
	await pframes(3)
	var c := Castle.new()
	_place(c, base)
	await pframes(10)
	var all: Array = []
	var sids: Array = []
	var lim: int = c.garrison_limit()
	for k in range(lim + 1):
		var men: Array = _squad("spearman", base + Vector3(-30.0 + float(k % 5) * 6.0, 0, 20.0 + float(k / 5) * 6.0), 4)
		all.append_array(men)
		sids.append((men[0] as Unit).squad_id)
	await pframes(5)
	for k2 in range(lim):
		c.request_garrison(int(sids[k2]))
	var last: int = int(sids[lim])
	var ev0: int = GameManager.tm_events.size()
	# Отказанный переспрашивает раз в 2 с, как очередь «в замок» — 6 раз
	for _r in range(6):
		c.request_garrison(last)
		await pframes(120)
	var n_ref := 0
	var evs: Array = GameManager.tm_events
	for k3 in range(ev0, evs.size()):
		var e: Array = evs[k3]
		if String(e[1]) == "garrison_refused" and int((e[2] as Dictionary).get("sid", -1)) == last:
			n_ref += 1
	verdict("C1 шесть отказов за ~12 с — одна запись в телеметрии", n_ref == 1, "%d записей" % n_ref)
	_free(all)
	c.queue_free()
	await pframes(10)

# ─────────────────────────────────────────────────────────────────────────────
# D. ИГРОВЫЕ ЧАСЫ ИНВАРИАНТНЫ К time_scale И К ПРОСАДКЕ FPS
# ─────────────────────────────────────────────────────────────────────────────
## Свойство, а не числа: за N физических тактов игровые часы уходят ровно на
## сумму их delta (= N × time_scale / ticks_per_second), что бы ни делали
## стенные часы; часы партии Main и ИИ людей уходят на то же самое
func _d_clock_invariance() -> void:
	print("\n═════ D. ИГРОВЫЕ ЧАСЫ: time_scale И ПРОСАДКА FPS ═════")
	var eai = main.get("enemy_ai")
	if eai != null:
		eai.set_process(true)
	var tps: float = float(Engine.physics_ticks_per_second)
	# ── D1/D2: time_scale ×4 (как зонд Smoke; ходов физики в секунду столько же)
	Engine.time_scale = 4.0
	await pframes(4)
	await frames(2)
	var g0: int = Unit.game_ms()
	var m0: float = main.game_clock()
	var e0: float = float(eai.clock) if eai != null else 0.0
	var n0: int = _phys_n
	var w0: int = Time.get_ticks_msec()
	await pframes(90)
	await frames(1)
	var dn: int = _phys_n - n0
	var dg: float = float(Unit.game_ms() - g0) * 0.001
	var dm: float = main.game_clock() - m0
	var de: float = (float(eai.clock) - e0) if eai != null else dg
	var dw: float = float(Time.get_ticks_msec() - w0) * 0.001
	Engine.time_scale = 1.0
	var want: float = float(dn) * 4.0 / tps
	print("  D: ×4 — физкадров %d, игровые %.3f с (ждали %.3f), Main %.3f, ИИ %.3f, стенные %.3f" % [
		dn, dg, want, dm, de, dw])
	verdict("D1 при time_scale ×4 игровые часы = сумма delta физики (±1 такт)",
		absf(dg - want) <= 4.0 / tps + 0.002, "%.3f против %.3f с" % [dg, want])
	verdict("D2 часы партии Main и ИИ людей идут от того же источника (расхождение ≤ 1 такт)",
		absf(dm - dg) <= 4.0 / tps * 1.5 + 0.002 and absf(de - dg) <= 4.0 / tps * 1.5 + 0.002,
		"игровые %.3f, Main %.3f, ИИ %.3f" % [dg, dm, de])
	# ── D3/D4: просадка FPS — кадр отрисовки тянется 50 мс, физика один шаг
	# на кадр (max_physics_steps_per_frame = 1): мир замедляется, часы с ним
	var steps0: int = Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 1
	await pframes(4)
	_slow_ms = 50
	await frames(3)
	g0 = Unit.game_ms()
	m0 = main.game_clock()
	n0 = _phys_n
	w0 = Time.get_ticks_msec()
	await pframes(40)
	await frames(1)
	_slow_ms = 0
	dn = _phys_n - n0
	dg = float(Unit.game_ms() - g0) * 0.001
	dm = main.game_clock() - m0
	dw = float(Time.get_ticks_msec() - w0) * 0.001
	Engine.max_physics_steps_per_frame = steps0
	want = float(dn) / tps
	print("  D: просадка — физкадров %d, игровые %.3f с (ждали %.3f), Main %.3f, стенные %.3f" % [
		dn, dg, want, dm, dw])
	verdict("D3 при просадке FPS игровые часы = сумма delta физики, а не стенные",
		dw > want * 1.8 and absf(dg - want) <= 1.0 / tps + 0.002,
		"игровые %.3f, ждали %.3f, стенные %.3f" % [dg, want, dw])
	verdict("D4 часы партии Main при просадке идут вместе с миром (≤ 1 такт)",
		absf(dm - dg) <= 1.5 / tps + 0.002, "игровые %.3f, Main %.3f" % [dg, dm])
	if eai != null:
		eai.set_process(false)
	# ── D5: стенных часов в игровой логике нет (сторож правила) ──────────────
	var hits: Array = _wall_clock_hits("res://scripts")
	for h in hits.slice(0, 5):
		print("    стенные часы в игре: %s" % h)
	verdict("D5 Time.get_ticks_msec в игровых скриптах — только интерфейс, звук, автосохранение, телеметрия",
		hits.is_empty(), "%d мест" % hits.size())

## Скрипты, которым стенные часы положены: интерфейс, звук, запись на диск,
## телеметрия (кадр в мс по стене — её смысл). Игровой срок — Unit.game_ms()
const WALL_CLOCK_OK := ["AudioManager.gd", "Autosave.gd", "HUD.gd", "SelectionManager.gd",
	"TelemetryLogger.gd", "LoadingScreen.gd"]
func _wall_clock_hits(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append_array(_wall_clock_hits(dir + "/" + sub))
	for fn in d.get_files():
		if not fn.ends_with(".gd") or fn in WALL_CLOCK_OK:
			continue
		var txt: String = FileAccess.get_file_as_string(dir + "/" + fn)
		var ln := 0
		for line in txt.split("\n"):
			ln += 1
			var code: String = line.strip_edges()
			if code.begins_with("#"):
				continue
			var cut: int = code.find("#")
			if cut >= 0:
				code = code.substr(0, cut)
			if code.find("Time.get_ticks_msec") >= 0:
				out.append("%s/%s:%d" % [dir, fn, ln])
	return out

# ─────────────────────────────────────────────────────────────────────────────
# E. ПРОХОДИМОСТЬ: ОДИН ПРЕДИКАТ В ЯДРЕ, ПРИЗНАК НЕУДАЧИ, ВЫНОС ИЗ СТВОЛОВ
# ─────────────────────────────────────────────────────────────────────────────
func _composite(x: float, z: float) -> bool:
	return not (GameManager.is_cliff(x, z) or GameManager.is_water(x, z)
		or GameManager.in_building(x, z) or GameManager.nav_pocket(x, z))

## Прежний поиск (GDScript-кольца, четыре предиката по одному) — эталон для E3
func _old_nearest(x: float, z: float) -> Vector2:
	if not GameManager.is_cliff(x, z) and not GameManager.in_building(x, z) and not GameManager.nav_pocket(x, z):
		return Vector2(x, z)
	var r: float = GameManager.CLIFF_SEARCH_STEP
	while r <= GameManager.CLIFF_SEARCH_R:
		var n: int = maxi(8, int(TAU * r / GameManager.CLIFF_SEARCH_STEP))
		for i in range(n):
			var a: float = TAU * float(i) / float(n)
			var px: float = x + cos(a) * r
			var pz: float = z + sin(a) * r
			if _composite(px, pz):
				return Vector2(px, pz)
		r += GameManager.CLIFF_SEARCH_STEP
	return Vector2(x, z)

func _e_passable() -> void:
	print("\n═════ E. ПРОХОДИМОСТЬ — ОДИН ПРЕДИКАТ, ОДИН ПЕРЕХОД ═════")
	_Opt.telemetry = true
	# Своя постройка у реки — фундамент в замере. Фундаменты в игре сняты по
	# заказу владельца (building_obstacles = false, проход сквозь здания):
	# на время блока ручка включается, чтобы сверка охватила и этот источник
	var bld_was: bool = _Opt.building_obstacles
	_Opt.building_obstacles = true
	var bpos := Vector3(-30, 0, 30)
	_clear_units(bpos, 30.0)
	main._clear_trees(bpos, 30.0)
	await pframes(3)
	var c := Castle.new()
	_place(c, bpos)
	await pframes(20)
	# Сетка точек: полоса лесной стены красных, русло, крепость
	var pts: Array = []
	var specs: Array = main._wall_specs()
	if not specs.is_empty():
		var sp: Dictionary = specs[0]
		var x := -205.0
		while x < -135.0:
			var zc: float = main._wall_z_of(sp, x)
			var dz := -6.0
			while dz <= 6.0:
				pts.append(Vector2(x, zc + dz))
				dz += 0.5
			x += 0.9
	var rx := -60.0
	while rx <= 60.0:
		var rz := -24.0
		while rz <= 24.0:
			pts.append(Vector2(rx, rz))
			rz += 1.5
		rx += 3.0
	var bx := -12.0
	while bx <= 12.0:
		var bz := -12.0
		while bz <= 12.0:
			pts.append(Vector2(bpos.x + bx, bpos.z + bz))
			bz += 0.75
		bx += 0.75
	var mism := 0
	var n_cliff := 0
	var n_water := 0
	var n_bld := 0
	var n_pocket := 0
	for p in pts:
		var a: bool = _composite(p.x, p.y)
		var b: bool = GameManager.is_passable(p.x, p.y)
		if a != b:
			mism += 1
			if mism <= 3:
				print("    расхождение в %s: по одному %s, ядро %s" % [str(p), str(a), str(b)])
		if GameManager.is_cliff(p.x, p.y): n_cliff += 1
		if GameManager.is_water(p.x, p.y): n_water += 1
		if GameManager.in_building(p.x, p.y): n_bld += 1
		if GameManager.nav_pocket(p.x, p.y): n_pocket += 1
	print("  E: точек %d — стволы %d, вода %d, фундамент %d, просвет %d; расхождений %d" % [
		pts.size(), n_cliff, n_water, n_bld, n_pocket, mism])
	verdict("E1 is_passable (ядро) совпадает с четырьмя предикатами по одному на всех точках",
		mism == 0 and n_cliff > 0 and n_water > 0 and n_bld > 0 and n_pocket > 0,
		"расхождений %d из %d (стволы %d, вода %d, фундамент %d, просвет %d)" % [
			mism, pts.size(), n_cliff, n_water, n_bld, n_pocket])
	# E2/E3: найденная точка проходима по всем четырём; совпадает с прежним
	# поиском (у непроходимых не в воде — тот же порядок проб)
	var bad := 0
	var same := 0
	var cmp := 0
	var hard: Array = []
	for p2 in pts:
		if GameManager.is_passable(p2.x, p2.y):
			continue
		hard.append(p2)
		var f: Vector2 = GameManager.nearest_passable(p2.x, p2.y)
		if not f.is_finite() or not _composite(f.x, f.y):
			bad += 1
		if not GameManager.is_water(p2.x, p2.y):
			cmp += 1
			var o: Vector2 = _old_nearest(p2.x, p2.y)
			if o.distance_to(f) < 0.01:
				same += 1
	verdict("E2 найденная ближайшая точка проходима по всем четырём предикатам",
		hard.size() > 0 and bad == 0, "непроходимых %d, плохих ответов %d" % [hard.size(), bad])
	verdict("E3 поиск в ядре даёт ту же точку, что прежний GDScript-обход (≥ 98 %)",
		cmp > 0 and float(same) >= float(cmp) * 0.98, "совпало %d из %d" % [same, cmp])
	# E4: цена — один переход на вызов против переходов на каждую пробу
	var t0: int = Time.get_ticks_usec()
	for p3 in hard:
		GameManager.nearest_passable(p3.x, p3.y)
	var t_new: float = float(Time.get_ticks_usec() - t0) / maxf(float(hard.size()), 1.0)
	t0 = Time.get_ticks_usec()
	for p4 in hard:
		_old_nearest(p4.x, p4.y)
	var t_old: float = float(Time.get_ticks_usec() - t0) / maxf(float(hard.size()), 1.0)
	print("  E: цена поиска на непроходимую точку — ядро %.1f мкс, прежний обход %.1f мкс" % [t_new, t_old])
	verdict("E4 поиск в ядре дешевле прежнего GDScript-обхода хотя бы вчетверо",
		t_new * 4.0 <= t_old, "%.1f против %.1f мкс" % [t_new, t_old])
	# E5/E6: неудача — INF, промах в счётчике и в телеметрии (раз в окно)
	var core: Array = _band_core()
	if core.is_empty():
		verdict("E5 есть точка в стволах для замера неудачи", false)
	else:
		var q: Vector3 = core[0]
		var lim: float = absf(q.x) - GameManager.CLIFF_SEARCH_R - 2.0
		var miss0: int = GameManager.passable_misses
		var ev0: int = GameManager.tm_events.size()
		GameManager._np_miss_tell_ms = -1000000
		var r1: Vector2 = GameManager.nearest_passable(q.x, q.z, lim, INF)
		var r2: Vector2 = GameManager.nearest_passable(q.x, q.z, lim, INF)
		var n_ev := 0
		var evs: Array = GameManager.tm_events
		for k in range(ev0, evs.size()):
			if String((evs[k] as Array)[1]) == "passable_miss":
				n_ev += 1
		verdict("E5 не нашлось — Vector2.INF, а не исходная точка",
			not r1.is_finite() and not r2.is_finite(), "%s / %s" % [str(r1), str(r2)])
		verdict("E6 промахи посчитаны (+2) и записаны в телеметрию одним событием за окно",
			GameManager.passable_misses - miss0 == 2 and n_ev == 1,
			"счётчик +%d, событий %d" % [GameManager.passable_misses - miss0, n_ev])
	# E7: вынос из стволов — пост в просвете стены переносится к бойцу
	var pk: Array = _pockets()
	# Сплошная стена: просветов нет — пост ставится в стволы у кромки
	if pk.is_empty() and _Opt.forest_nav_solid and core.size() > 2:
		pk = [core[core.size() / 3]]
	if core.is_empty() or pk.is_empty():
		verdict("E7 есть точки в стволах и в просвете для замера выноса", false)
	else:
		var at: Vector3 = core[core.size() / 2]
		for u0 in get_tree().get_nodes_in_group("all_units"):
			if is_instance_valid(u0) and (u0 as Node3D).global_position.distance_to(at) < 40.0:
				u0.queue_free()
		await pframes(3)
		var u: Unit = _spawn("spearman", at, E)
		u.post_pos = pk[0]
		u._post_valid = true
		var t := 0
		while t < 600 and GameManager.is_cliff(u.global_position.x, u.global_position.z):
			await pframes(5)
			t += 5
		await pframes(3)
		var up: Vector3 = u.global_position
		var pp: Vector3 = u.post_pos
		print("  E: боец %s → %s за %d кадров, пост %s" % [str(at), str(up.snapped(Vector3.ONE * 0.1)), t, str(pp.snapped(Vector3.ONE * 0.1))])
		verdict("E7 _sweep_trapped выносит бойца на проходимое и не оставляет пост в просвете стены",
			GameManager.is_passable(up.x, up.z) and GameManager.is_passable(pp.x, pp.z),
			"боец проходим %s, пост проходим %s" % [str(GameManager.is_passable(up.x, up.z)),
				str(GameManager.is_passable(pp.x, pp.z))])
		_free([u])
	c.queue_free()
	await pframes(10)
	_Opt.building_obstacles = bld_was
