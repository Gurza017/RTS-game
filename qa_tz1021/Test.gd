extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 21.10.2026: аудит лога партии 21.10 и снятие замка строя копейщиков
## ═══════════════════════════════════════════════════════════════════════════
##   A — строй копейщиков: «Фаланга» изучена, стойка [S], НАСТОЯЩАЯ протяжка
##       (тот же путь, что отпускание ПКМ) — где бойцы ФАКТИЧЕСКИ встали;
##       принудительного смыкания в три шеренги в коде нет вовсе
##   B — «дошёл, упёрся в соседа»: всадники орды в точки, занятые чужим
##       отрядом, — прибытие, а не вызволение и сдача (A/B по ручке)
##   C — вызволение «cliff» только при стене ПО ХОДУ (стена за спиной — нет)
##   D — поход в замок держит отход всю дорогу: внутренние приказы не
##       отменяют, приказ игрока отменяет сразу (A/B по ручке)
##   E — перезакладка крепости ИИ: не под носом у врага и не чаще паузы
##   F — телеметрия: падение хижины орды — hut_fell, у вызволения есть «d»
## Запуск: godot --headless --path . res://qa_tz1021/Test.tscn [-- only=abcdef]

const _Opt := preload("res://scripts/perf_config.gd")
const _Hut := preload("res://scripts/goblin/GoblinHut.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcdef"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
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
	print("\n═════ ИТОГ qa_tz1021: прошло %d, провалов: %d ═════" % [_pass, _fail])
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
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _place(b: Building, at: Vector3, fac: int = F) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _clear(at: Vector3, r: float) -> void:
	main._clear_trees(at, r)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
			u.queue_free()

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
	_Opt.telemetry = true
	if "a" in _only: await _a_spear_drag()
	if "b" in _only: await _b_stall_arrive()
	if "c" in _only: await _c_cliff_ahead()
	if "d" in _only: await _d_garrison_trip()
	if "e" in _only: await _e_castle_rebuild()
	if "f" in _only: await _f_telemetry()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
# A. СТРОЙ КОПЕЙЩИКОВ: ФАКТ, А НЕ ПЛАН
# ─────────────────────────────────────────────────────────────────────────────
func _measure(men: Array, a: Vector3, b: Vector3) -> Vector3:
	var dir := (b - a).normalized()
	var facing := Vector3(dir.z, 0.0, -dir.x)
	var lat: Array = []
	var dep: Array = []
	for m in men:
		var p: Vector3 = (m as Node3D).global_position - a
		p.y = 0.0
		lat.append(p.dot(dir))
		dep.append(p.dot(-facing))
	lat.sort()
	dep.sort()
	var rows := 1
	for i in range(1, dep.size()):
		if float(dep[i]) - float(dep[i - 1]) > 0.3:
			rows += 1
	return Vector3(float(lat[-1]) - float(lat[0]), float(dep[-1]) - float(dep[0]), float(rows))

func _drag_case(at: Vector3, squads: int, deep: bool, line: float) -> Vector3:
	_clear(at, 40.0)
	await pframes(3)
	var men: Array = []
	for q in range(squads):
		men.append_array(_squad("spearman", at + Vector3(float(q) * 6.0, 0, 0), 60))
	await pframes(10)
	var sm = main.selection_manager
	sm.select_units(men)
	sm.formation_mode = sm.FORM_DEEP if deep else sm.FORM_WIDE
	sm._squad_cmd().stand_ground(sm)
	await pframes(10)
	var a := at + Vector3(-line * 0.5, 0, 10)
	var b := at + Vector3(line * 0.5, 0, 10)
	sm._execute_line_formation(a, b)
	var waited := 0
	while waited < 1500:
		await pframes(10)
		waited += 10
		var moving := 0
		for m in men:
			if is_instance_valid(m) and (m as Unit).state == Unit.State.MOVING:
				moving += 1
		if moving == 0 and waited > 60:
			break
	await pframes(60)
	var res := _measure(men, a, b)
	var ready := GameManager.spear_wall_ready((men[0] as Unit).squad_id)
	sm.clear_selection()
	sm.formation_mode = sm.FORM_WIDE
	_free(men)
	await pframes(5)
	return Vector3(res.x, res.z, 1.0 if ready else 0.0)

func _a_spear_drag() -> void:
	print("\n═════ A. СТРОЙ КОПЕЙЩИКОВ С «ФАЛАНГОЙ» В [S]: ФАКТИЧЕСКАЯ ШИРИНА ═════")
	for nid in ["spearman_1a", "spearman_1b", "spearman_1c", "spearman_1d", "spearman_2d", "spearman_3d"]:
		GameManager.finish_research(F, nid)
	verdict("A0 принудительного смыкания в три шеренги в коде нет",
		not GameManager.has_method("spear_wall_form") and not ("SPEAR_WALL_ROWS" in GameManager)
			and not ("DEEP_ROWS" in main.selection_manager))
	var r1: Vector3 = await _drag_case(Vector3(-80, 0, -10), 1, false, 30.0)
	print("  1 отряд [1], линия 30 м: ширина %.1f м, шеренг %d, фаланга=%s" % [r1.x, int(r1.y), r1.z > 0.5])
	verdict("A1 1 отряд, [1]: фронт во всю протяжку (≥ 90 %), не три шеренги",
		r1.z > 0.5 and r1.x >= 27.0 and r1.y < 3.0, "ширина %.1f, шеренг %d" % [r1.x, int(r1.y)])
	var r2: Vector3 = await _drag_case(Vector3(-80, 0, 30), 1, true, 30.0)
	print("  1 отряд [2], линия 30 м: ширина %.1f м, шеренг %d" % [r2.x, int(r2.y)])
	verdict("A2 1 отряд, [2]: тоже во всю протяжку", r2.x >= 27.0 and r2.y < 3.0,
		"ширина %.1f, шеренг %d" % [r2.x, int(r2.y)])
	var r3: Vector3 = await _drag_case(Vector3(-30, 0, -10), 3, false, 30.0)
	print("  3 отряда [1], линия 30 м: ширина %.1f м, шеренг %d" % [r3.x, int(r3.y)])
	verdict("A3 3 отряда, [1]: фронт во всю протяжку", r3.x >= 27.0 and r3.y <= 5.0,
		"ширина %.1f, шеренг %d" % [r3.x, int(r3.y)])
	var r4: Vector3 = await _drag_case(Vector3(-30, 0, 30), 1, false, 6.0)
	print("  1 отряд [1], линия 6 м: ширина %.1f м, шеренг %d" % [r4.x, int(r4.y)])
	var want_rows: int = int(ceil(60.0 / float(maxi(1, int(floor(6.0 / main.selection_manager.UNIT_SPACING))))))
	verdict("A4 короткая протяжка — глубину задаёт игрок (шеренг ≈ 60 / мест в ряду)",
		absi(int(r4.y) - want_rows) <= 1 and r4.x <= 7.0, "шеренг %d, ждали %d" % [int(r4.y), want_rows])

# ─────────────────────────────────────────────────────────────────────────────
# B. «ДОШЁЛ, УПЁРСЯ В СОСЕДА»
# ─────────────────────────────────────────────────────────────────────────────
## Синтетика «два отряда в одни точки» и «точка занята стоящим своим» лог НЕ
## воспроизводит: свои стоящие и спящие раздвигаются, боец доходит (зонд
## qa_spear_drag/Rider). Поэтому блок судит СВОЙСТВО правила, а эффект на
## партии меряет A/B зондом qa_ai_loop/Smoke (строка «ЗАСТРЕВАНИЯ»)
func _b_stall_arrive() -> void:
	print("\n═════ B. «ДОШЁЛ, УПЁРСЯ В СОСЕДА» — ПРИБЫТИЕ, А НЕ ВЫЗВОЛЕНИЕ ═════")
	var at := Vector3(-80, 0, -10)
	_clear(at, 20.0)
	await pframes(3)
	var man := _spawn("spearman", at)
	var rider := _spawn("goblin_rider", at + Vector3(0, 0, 6), G)
	var troll_r: float = clampf(2.0 * Unit.SEP_MIN_DIST * 3.4 * Unit.SEP_CROSS_SQUAD, Unit.STALL_ARRIVE_MIN, Unit.STALL_ARRIVE_MAX)
	print("  допуск: человек %.2f м, всадник %.2f м (тролль по формуле %.2f м); общий ARRIVE %.2f м" % [
		man._stall_arrive_r(), rider._stall_arrive_r(), troll_r, Unit.ARRIVE_RADIUS])
	verdict("B0 допуск шире общего ARRIVE и растёт с личным кругом",
		man._stall_arrive_r() > Unit.ARRIVE_RADIUS and rider._stall_arrive_r() > man._stall_arrive_r())
	await pframes(5)
	for u in [man, rider]:
		var uu := u as Unit
		uu.command_move(uu.global_position + Vector3(1.0, 0, 0))
		uu._stuck_streak = Unit.STALL_ARRIVE_STREAK
	var near_ok: bool = man._stall_arrived(1.0) and rider._stall_arrived(1.0)
	var far_no: bool = not man._stall_arrived(man._stall_arrive_r() + 0.2)
	man._stuck_streak = 1
	var early_no: bool = not man._stall_arrived(1.0)
	man._stuck_streak = Unit.STALL_ARRIVE_STREAK
	_Opt.stall_arrive = false
	var off_no: bool = not man._stall_arrived(1.0)
	_Opt.stall_arrive = true
	verdict("B1 секунда без продвижения в 1 м от точки — прибытие (человек и всадник)", near_ok)
	verdict("B2 дальше допуска и раньше секунды — не прибытие", far_no and early_no)
	verdict("B3 ручка выключена — прежнее поведение", off_no)
	# Детектор не вызволяет бойца у самой точки: два такта без продвижения
	var u0: int = Unit.unstuck_total
	man._stuck_streak = Unit.UNSTICK_STREAK * 2
	man._stuck_ref_dist = 1.0
	man._stuck_timer = Unit.STUCK_CHECK_SEC
	man._tick_stuck(0.0, 1.0)
	verdict("B4 детектор у самой точки не вызволяет", Unit.unstuck_total == u0)
	# Ход доделывает прибытие: боец встаёт, приказ исполнен
	man._stuck_streak = Unit.STALL_ARRIVE_STREAK
	man._stuck_timer = 0.0
	var s0: int = Unit.stall_arrivals
	for _i in range(6):
		if man.state != Unit.State.MOVING:
			break
		man._stuck_streak = Unit.STALL_ARRIVE_STREAK
		await pframes(1)
	verdict("B5 боец встал (IDLE) и прибытие засчитано", man.state == Unit.State.IDLE and Unit.stall_arrivals > s0,
		"состояние %d" % int(man.state))
	man.queue_free()
	rider.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
# C. «СКАЛА РЯДОМ» — ТОЛЬКО ПО ХОДУ
# ─────────────────────────────────────────────────────────────────────────────
func _c_cliff_ahead() -> void:
	print("\n═════ C. ВЫЗВОЛЕНИЕ У СТЕНЫ — ТОЛЬКО ПО ХОДУ ═════")
	var at := Vector3(-80, 0, -10)
	_clear(at, 20.0)
	await pframes(3)
	# Стена из деревьев-стены в 3 м по +X от бойца
	for k in range(-4, 5):
		GameManager.forest_wall_add(at + Vector3(3.0, 0, float(k) * 1.5), 1.2)
	await pframes(5)
	verdict("C0 стена стоит в маске скал (по +X), за спиной чисто",
		GameManager.is_cliff(at.x + 3.0, at.z) and not GameManager.is_cliff(at.x - 4.0, at.z))
	var u := _spawn("spearman", at)
	await pframes(5)
	u._stuck_streak = Unit.UNSTICK_STREAK
	u.state = Unit.State.MOVING
	# Идёт ОТ стены
	u.velocity = Vector3(-2.0, 0, 0)
	u.move_target = at + Vector3(-20, 0, 0)
	var away: bool = u._may_unstick()
	# Идёт НА стену
	u.velocity = Vector3(2.0, 0, 0)
	u.move_target = at + Vector3(20, 0, 0)
	var into: bool = u._may_unstick()
	_Opt.unstick_cliff_ahead = false
	u.velocity = Vector3(-2.0, 0, 0)
	u.move_target = at + Vector3(-20, 0, 0)
	var away_old: bool = u._may_unstick()
	_Opt.unstick_cliff_ahead = true
	verdict("C1 стена за спиной — не застревание", not away)
	verdict("C2 стена по ходу — застревание у стены (cliff)", into and u._unstick_why == "cliff")
	verdict("C3 без ручки стена за спиной вызволяла (прежнее поведение)", away_old)
	u._stuck_streak = 0
	u.state = Unit.State.IDLE
	u.velocity = Vector3.ZERO
	u.queue_free()
	for k in range(-4, 5):
		GameManager.forest_wall_remove(at + Vector3(3.0, 0, float(k) * 1.5))

# ─────────────────────────────────────────────────────────────────────────────
# D. ПОХОД В ЗАМОК ДЕРЖИТ ОТХОД ВСЮ ДОРОГУ
# ─────────────────────────────────────────────────────────────────────────────
var _castle: Building = null

func _trip(on: bool, player_cancel: bool, at: Vector3) -> Dictionary:
	_Opt.garrison_trip_lock = on
	var c: Castle = _castle as Castle
	var men: Array = _squad("spearman", at, 30)
	var sid: int = (men[0] as Unit).squad_id
	await pframes(10)
	c.request_garrison(sid, false)
	var t := 0
	var cancelled := false
	var inside := false
	while t < 60 * 90:
		await pframes(30)
		t += 30
		if c._slot_of(sid) >= 0:
			inside = true
			break
		if not c._incoming.has(sid):
			cancelled = true
			break
		# Внутренний приказ (как у смыкания/сплочённости) раз в 3 с после 13-й
		# секунды пути — без keep_retreat и без признака игрока
		if not player_cancel and t >= 60 * 13 and t % 180 == 0:
			for m in men:
				if is_instance_valid(m) and not (m as Unit).garrisoned:
					(m as Unit).command_move((m as Node3D).global_position + Vector3(4.0, 0, 0))
		if player_cancel and t == 60 * 5:
			for m in men:
				if is_instance_valid(m) and not (m as Unit).garrisoned:
					(m as Unit).command_move(at + Vector3(0, 0, 8), false, Vector3.ZERO, false, true)
	var res := {"cancelled": cancelled, "inside": inside, "secs": float(t) / 60.0}
	print("  ручка %s, %s: внутри=%s, отменён=%s за %.1f с" % ["вкл" if on else "выкл",
		"отмена игроком на 5-й с" if player_cancel else "внутренние приказы с 13-й с",
		inside, cancelled, res["secs"]])
	if inside:
		c.release_garrison(sid)
	await pframes(30)
	_free(GameManager.squad_members(sid))
	await pframes(5)
	_Opt.garrison_trip_lock = true
	return res

func _d_garrison_trip() -> void:
	print("\n═════ D. ПОХОД В ЗАМОК: ОТХОД ДЕРЖИТСЯ ВСЮ ДОРОГУ ═════")
	var cpos := Vector3(-80, 0, -45)
	_clear(cpos, 30.0)
	_clear(Vector3(-80, 0, 0), 45.0)
	var c: Building = Castle.new()
	_place(c, cpos)
	_castle = c
	await pframes(30)
	var far := Vector3(-80, 0, 30)
	var off: Dictionary = await _trip(false, false, far)
	var on: Dictionary = await _trip(true, false, far)
	var pl: Dictionary = await _trip(true, true, far)
	verdict("D0 без ручки внутренний приказ после 12 с отменял поход (стенд воспроизводит лог)",
		bool(off["cancelled"]))
	verdict("D1 с ручкой отряд дошёл и вошёл, несмотря на внутренние приказы",
		bool(on["inside"]) and not bool(on["cancelled"]), "за %.1f с" % float(on["secs"]))
	verdict("D2 приказ игрока отменяет поход сразу (≤ 2 с после приказа)",
		bool(pl["cancelled"]) and float(pl["secs"]) <= 7.0, "отмена на %.1f с" % float(pl["secs"]))

# ─────────────────────────────────────────────────────────────────────────────
# E. ПЕРЕЗАКЛАДКА КРЕПОСТИ ИИ
# ─────────────────────────────────────────────────────────────────────────────
func _e_castle_rebuild() -> void:
	print("\n═════ E. ПЕРЕЗАКЛАДКА КРЕПОСТИ ИИ ═════")
	var ai = main.get("enemy_ai")
	if ai == null:
		verdict("E0 узел ИИ красного есть", false)
		return
	var anchor := Vector3(-30, 0, -10)
	_clear(anchor, 60.0)
	await pframes(3)
	var free_spot: Vector3 = ai._safe_castle_spot(anchor)
	verdict("E1 вокруг руин пусто — площадка находится", free_spot != Vector3.INF)
	var army: Array = _squad("spearman", anchor + Vector3(-3, 0, -3), 12)
	await pframes(5)
	var busy: Vector3 = ai._safe_castle_spot(anchor)
	verdict("E2 армия игрока у руин — закладки нет (ждём)", busy == Vector3.INF)
	_free(army)
	await pframes(5)
	var side: Array = _squad("spearman", anchor + Vector3(-30, 0, 0), 12)
	await pframes(5)
	var away: Vector3 = ai._safe_castle_spot(anchor)
	var far_ok: bool = away != Vector3.INF
	for m in side:
		if far_ok and (m as Node3D).global_position.distance_to(away) < ai.CASTLE_REBUILD_SAFE_R:
			far_ok = false
	verdict("E3 враг с одной стороны — площадка с другой, вне радиуса", far_ok,
		"площадка %s" % str(away))
	_free(side)
	ai._castle_site_ms = Unit.game_ms()
	var cool: bool = ai._rebuild_cooldown_ok()
	ai._castle_site_ms = -1000000
	verdict("E4 сразу после закладки — пауза (вторая не закладывается)",
		not cool and ai._rebuild_cooldown_ok())

# ─────────────────────────────────────────────────────────────────────────────
# F. ТЕЛЕМЕТРИЯ
# ─────────────────────────────────────────────────────────────────────────────
func _f_telemetry() -> void:
	print("\n═════ F. ТЕЛЕМЕТРИЯ ═════")
	var at := Vector3(-30, 0, 30)
	_clear(at, 25.0)
	await pframes(3)
	var n0: int = GameManager.tm_events.size()
	var hut: Building = _Hut.new()
	_place(hut, at, G)
	await pframes(10)
	hut._die()
	await pframes(5)
	var kinds: Array = []
	for i in range(n0, GameManager.tm_events.size()):
		kinds.append(String((GameManager.tm_events[i] as Array)[1]))
	verdict("F1 снос хижины орды — hut_fell, не castle_fell",
		kinds.has("hut_fell") and not kinds.has("castle_fell"), str(kinds))
	# Вызволение пишет дистанцию до своей точки
	var u := _spawn("spearman", at + Vector3(10, 0, 0))
	await pframes(5)
	u.move_target = u.global_position + Vector3(0.7, 0, 0)
	var n1: int = GameManager.tm_events.size()
	u._unstick_last_ms = -1000000
	u._unstick_why = "no_progress"
	u._unstick()
	var d_ok := false
	for i in range(n1, GameManager.tm_events.size()):
		var e: Array = GameManager.tm_events[i]
		if String(e[1]) == "unstuck" and (e[2] as Dictionary).has("d"):
			d_ok = true
	verdict("F2 в событии вызволения есть дистанция до точки «d»", d_ok)
	u.queue_free()
