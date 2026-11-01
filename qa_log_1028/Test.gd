extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_LOG_1028 — разбор партии .exe 27-28.10.2026 (лог logs/exe + телеметрия).
## ═══════════════════════════════════════════════════════════════════════════
## A — засыпающий боец подаёт состояние в строку ядра: стоящий в GDScript, но
##     MOVING в ядре (тик погашен между шардами) после set_dormant(true) в ядре
##     IDLE (ручка dormant_state_sync; выкл — MOVING остаётся: «бег на месте»
##     спящей охраны 42 минуты, 724 строки зонда).
## B — зонд order_override_bug читает метку источника GameManager.probes.ctx:
##     «attack_move» глушит запись (в экспорте get_stack() пуст).
## C — после сдачи вызволения авто-агро не берёт цель, к которой надо идти
##     (giveup_aggro_hold; выкл — берёт): цикл «лес → сдача → новая цель».
## D — panic_capped пишется один раз на отряд (красный отряд ниже порога,
##     жребий 100 %, потери одна за другой — одно событие, не одно на смерть).
## E — переполненный буфер телеметрии режет самый частый вид, редкие события
##     переживают спам (tm_trim_by_kind; выкл — срез подряд теряет редкие).
## Запуск: godot --headless --path . res://qa_log_1028/Test.tscn [-- only=abcde]
const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const _Opt := preload("res://scripts/perf_config.gd")

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcde"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_log_1028: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _spot(dx: float, dz: float) -> Vector3:
	return main.PLAYER_BASE_ANCHOR + Vector3(dx, 0.0, dz)

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var p: Vector3 = at + Vector3(float(i / 5) * 0.7, 0.0, (float(i % 5) - 2.0) * 0.7)
		GameManager.add_to_squad(sid, _unit(uid, f, p))
	return sid

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _boot() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	await pframes(3)

func _run() -> void:
	await _boot()
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
	_finish()

# ── A. СОСТОЯНИЕ СПЯЩЕГО В ЯДРЕ ──────────────────────────────────────────────
func _block_a() -> void:
	print("\n── A. Засыпающий подаёт состояние в ядро ──")
	var sid: int = _squad("spearman", R, _spot(40.0, 30.0), 4)
	await pframes(6)
	var u: Unit = _members(sid)[0]
	verdict("A1 строка подана (первый тик прошёл)", u._sent_st >= 0 and u._soa >= 0,
		"_sent_st=%d soa=%d" % [u._sent_st, u._soa])
	# Гонка шардов: в GDScript боец уже стоит, в ядре ещё идёт
	GameManager.army.set_state(u._soa, Unit.State.MOVING)
	u.state = Unit.State.IDLE
	u.set_dormant(true)
	verdict("A2 после set_dormant(true) в ядре IDLE", GameManager.army.state_of(u._soa) == Unit.State.IDLE,
		"ядро=%d" % GameManager.army.state_of(u._soa))
	u.set_dormant(false)
	await pframes(2)
	_Opt.dormant_state_sync = false
	GameManager.army.set_state(u._soa, Unit.State.MOVING)
	u.state = Unit.State.IDLE
	u.set_dormant(true)
	verdict("A3 ручка выкл: ядро остаётся MOVING (старое поведение)",
		GameManager.army.state_of(u._soa) == Unit.State.MOVING, "ядро=%d" % GameManager.army.state_of(u._soa))
	_Opt.dormant_state_sync = true
	u.set_dormant(false)
	await pframes(2)
	for m in _members(sid):
		(m as Unit).take_damage(1e12)
	await pframes(2)

# ── B. МЕТКА ИСТОЧНИКА ЗОНДА ─────────────────────────────────────────────────
func _block_b() -> void:
	print("\n── B. Зонд order_override_bug: метка источника вместо стека ──")
	var sid: int = _squad("spearman", F, _spot(30.0, 30.0), 3)
	await pframes(2)
	var u: Unit = _members(sid)[0]
	var p: Variant = GameManager.probes
	var was: bool = _Opt.squad_probes
	_Opt.squad_probes = true
	var n0: int = int(p.override_notes)
	p.ctx = "attack_move"
	u._probe_override("test_am")
	verdict("B1 метка «attack_move» глушит запись зонда", int(p.override_notes) == n0, "notes %d → %d" % [n0, int(p.override_notes)])
	p.ctx = ""
	u._probe_override("test_plain")
	verdict("B2 без метки запись идёт", int(p.override_notes) == n0 + 1, "notes %d → %d" % [n0, int(p.override_notes)])
	verdict("B3 ctx у зонда есть и пуст по умолчанию", "ctx" in p and String(p.ctx) == "")
	p.flush_now()
	_Opt.squad_probes = was
	for m in _members(sid):
		(m as Unit).take_damage(1e12)
	await pframes(2)

# ── C. ПОСЛЕ СДАЧИ — ТОЛЬКО ЦЕЛЬ ПОД РУКОЙ ───────────────────────────────────
func _block_c() -> void:
	print("\n── C. Сдача вызволения держит авто-агро ──")
	var at: Vector3 = _spot(30.0, -30.0)
	var sid: int = _squad("spearman", F, at, 1)
	var e: Unit = _unit("spearman", R, at + Vector3(4.2, 0.0, 0.0))
	e.set_tick(false)
	await pframes(4)
	var u: Unit = _members(sid)[0]
	u.set_attack_target(null)
	u.state = Unit.State.IDLE
	u._giveup_hold_until_ms = Unit.game_ms() + 30000
	var held0: int = Unit.giveup_aggro_held
	u._check_auto_aggro()
	verdict("C1 с памятью сдачи далёкая цель не взята", u.attack_target == null and Unit.giveup_aggro_held == held0 + 1,
		"цель=%s held %d → %d" % [str(u.attack_target), held0, Unit.giveup_aggro_held])
	_Opt.giveup_aggro_hold = false
	u._check_auto_aggro()
	verdict("C2 ручка выкл: цель взята (старое поведение)", u.attack_target == e,
		"цель=%s" % str(u.attack_target))
	_Opt.giveup_aggro_hold = true
	u.set_attack_target(null)
	u._giveup_hold_until_ms = 0
	u._check_auto_aggro()
	verdict("C3 память истекла — цель снова берётся", u.attack_target == e, "цель=%s" % str(u.attack_target))
	u.take_damage(1e12)
	e.take_damage(1e12)
	await pframes(2)

# ── D. PANIC_CAPPED ОДИН РАЗ НА ОТРЯД ────────────────────────────────────────
func _block_d() -> void:
	print("\n── D. panic_capped — одно событие на отряд ──")
	var sid: int = _squad("spearman", R, _spot(45.0, -40.0), 20)
	await pframes(3)
	var sq: Dictionary = GameManager.squads[sid]
	sq["panic_runs"] = 1          # уже отбегал — дальше только «предел держит»
	GameManager.panic_chance_override = 1.0
	var was_tm: bool = _Opt.telemetry
	_Opt.telemetry = true
	var n0: int = _count_events("panic_capped", sid)
	# Ниже порога (30 % штата): 20 → 5, по одному, с обходом морали после каждой
	var ms: Array = _members(sid)
	for i in range(15):
		(ms[i] as Unit).take_damage(1e12)
		for _k in range(4):
			GameManager._sweep_morale(GameManager.MORALE_SWEEP_SEC + 0.01)
	var n1: int = _count_events("panic_capped", sid)
	verdict("D1 пять смертей ниже порога — одно событие panic_capped", n1 - n0 == 1, "событий %d" % (n1 - n0))
	verdict("D2 жребии бросались (panic_rolls растёт)", int(sq.get("panic_rolls", 0)) >= 2, str(sq.get("panic_rolls", 0)))
	GameManager.panic_chance_override = -1.0
	_Opt.telemetry = was_tm
	for m in _members(sid):
		(m as Unit).take_damage(1e12)
	await pframes(2)

func _count_events(kind: String, sid: int) -> int:
	var n := 0
	for e in GameManager.tm_events:
		var a: Array = e
		if String(a[1]) == kind and int((a[2] as Dictionary).get("sid", -1)) == sid:
			n += 1
	return n

# ── E. БУФЕР ТЕЛЕМЕТРИИ ──────────────────────────────────────────────────────
func _block_e() -> void:
	print("\n── E. Переполнение буфера событий ──")
	var was_tm: bool = _Opt.telemetry
	_Opt.telemetry = true
	var saved: Array = GameManager.tm_events
	var saved_drop: int = GameManager.tm_events_dropped
	var cap: int = GameManager.TM_EVENTS_MAX
	# 10 редких в начале, остальное — спам до потолка минус один
	var ev: Array = []
	for i in range(10):
		ev.append([0.1 * i, "castle_fell", {"i": i}])
	while ev.size() < cap - 1:
		ev.append([1.0, "unstuck", {}])
	GameManager.tm_events = ev
	GameManager.tm_event("unstuck", {})       # ровно потолок → срез при следующем
	GameManager.tm_event("unstuck", {})
	var rare: int = _kind_count("castle_fell")
	var spam: int = _kind_count("unstuck")
	verdict("E1 редкие события пережили срез", rare == 10, "castle_fell=%d" % rare)
	verdict("E2 срезана половина спама", spam >= (cap - 10) / 2 - 2 and spam <= (cap - 10) / 2 + 3,
		"unstuck=%d при потолке %d" % [spam, cap])
	verdict("E3 размер ниже потолка", GameManager.tm_events.size() < cap, str(GameManager.tm_events.size()))
	# Ручка выкл: срез подряд сносит старейшую восьмую — вместе с редкими
	_Opt.tm_trim_by_kind = false
	GameManager.tm_events = ev.duplicate()
	GameManager.tm_event("unstuck", {})
	GameManager.tm_event("unstuck", {})
	verdict("E4 ручка выкл: редкие события потеряны (старое поведение)", _kind_count("castle_fell") == 0,
		"castle_fell=%d" % _kind_count("castle_fell"))
	_Opt.tm_trim_by_kind = true
	GameManager.tm_events = saved
	GameManager.tm_events_dropped = saved_drop
	_Opt.telemetry = was_tm

func _kind_count(kind: String) -> int:
	var n := 0
	for e in GameManager.tm_events:
		if String((e as Array)[1]) == kind:
			n += 1
	return n
