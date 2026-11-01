extends Node
## ═══════════════════════════════════════════════════════════════════════════
## РАЗБОР ПАРТИИ 26.10.2026 (godot.log + performance_log_2026-10-26_1423.json)
## ═══════════════════════════════════════════════════════════════════════════
## A — ВЫТЕСНЕНИЕ ТЕЛ У ПОТОЛКА. Догоревшее (index < 0) до уплотнения очереди
##     пускалось гаснуть повторно: hide_slot(-1) гасил последний слот бакета,
##     в свободный список уходил −1. Свойства: ни одного −1 в свободных
##     списках, ни одного «живого» тела с index < 0, живых ровно потолок.
## B — ПОВОДОК ПОГОНИ ОТРЯДНЫЙ. Сорвал поводок один — погоня кончена для всего
##     отряда в том же кадре (в партии отряд 86 срывался поштучно 20 с и
##     рвался надвое). Свойства: через секунду после первого срыва не гонится
##     никто; через RETURN_SEC никто не дальше SPLIT_R от медианы отряда.
## C — ЗОНД «БЕГ НА МЕСТЕ» НЕ СЧИТАЕТ ГАРНИЗОН. Строка вне карты хранит ленту,
##     с которой её сняли; зонд ловил лучников на крыше 30 минут подряд.
##     Свойство: отряд, вошедший в замок на бегу, в ответе ядра не появляется.
## Запуск: godot --headless --path . res://qa_log_1026/Test.tscn [-- only=abc]
## Провалы — «НЕ ПРОШЛО» / «провалов:».

const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const _CorpseR := preload("res://scripts/CorpseRenderer.gd")
const _Opt := preload("res://scripts/perf_config.gd")
## Отряд цел: никто дальше этого от медианы (24 мечника строем ~6×4 м)
const SPLIT_R := 12.0
const RETURN_SEC := 15.0

var main: Node = null
var _pass := 0
var _fail := 0
var _only := "abc"
var _done := false
var _diag := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		if String(a) == "diag=1":
			_diag = true
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
	print("\n═════ ИТОГ qa_log_1026: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3, fac: int) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _clear(at: Vector3, r: float) -> void:
	main._clear_trees(at, r)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
			u.queue_free()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "enemy_guard", "goblin_reserve"]:
		var nd = main.get(n)
		if nd != null and is_instance_valid(nd):
			nd.set_process(false)
			nd.set_physics_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	if "a" in _only: await _block_a()
	if "b" in _only: await _block_b()
	if "c" in _only: await _block_c()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
func _block_a() -> void:
	print("\n═════ A. ВЫТЕСНЕНИЕ ТЕЛ У ПОТОЛКА ═════")
	var cr = _CorpseR.new()
	var root := Node3D.new()
	main.add_child(root)
	var img := Image.create(32, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var sheet := ImageTexture.create_from_image(img)
	var cap: int = _CorpseR.MAX_CORPSES
	for i in range(cap):
		cr.spawn_prop(sheet, 4, 0.02, Vector3(float(i % 70), 0.0, float(i / 70)), i, root, 0.0)
	# 20 старейших догорают штатно (срок жизни + растворение) — меньше
	# COMPACT_MIN, очередь не уплотняется: снятые места лежат в голове
	var dead_n := 20
	for i in range(dead_n):
		cr._begin_fade(cr._list[i], 0.1)
	cr.update(0.2)
	print("    после догорания: в очереди %d, гаснут %d, снятых мест %d" % [cr._list.size(), cr.fading_count(), cr._dead_slots])
	# Новые тела сверх потолка — вытеснение
	var extra := 40
	for i in range(extra):
		cr.spawn_prop(sheet, 4, 0.02, Vector3(float(i), 0.0, -5.0), cap + i, root, 0.0)
	for _k in range(5):
		cr.update(1.0)
	var neg_free := 0
	for b in cr._buckets.values():
		for s in b.free:
			if int(s) < 0:
				neg_free += 1
	# Ещё тела поверх: со старым кодом они брали из свободного списка −1
	# (запись в последний слот бакета, тело с index < 0 — «никто»)
	var more := 30
	for i in range(more):
		cr.spawn_prop(sheet, 4, 0.02, Vector3(float(i), 0.0, -8.0), cap + extra + i, root, 0.0)
	for _k in range(5):
		cr.update(1.0)
	var neg_idx := 0
	for c in cr._list.slice(cr._list.size() - more):
		if c.index < 0:
			neg_idx += 1
	var live := 0
	var bad := 0
	var slots: Dictionary = {}
	var dup := 0
	for c in cr._list:
		if c.index >= 0 and c.fade_left < 0.0:
			live += 1
			var key := "%d|%d" % [c.bucket.get_instance_id(), c.index]
			if slots.has(key):
				dup += 1
			slots[key] = true
		elif c.index < 0 and c.fade_left < 0.0 and cr._fading.has(c):
			bad += 1
	print("    живых %d (потолок %d), отрицательных в свободных %d, общих слотов %d" % [live, cap, neg_free, dup])
	verdict("A1 в свободных списках нет −1", neg_free == 0, "%d" % neg_free)
	verdict("A2 у живых тел нет общих слотов", dup == 0, "%d" % dup)
	verdict("A3 живых ровно потолок (снятые места не считаются телами)", live == cap,
		"%d из %d" % [live, cap])
	verdict("A4 снятые места не гаснут повторно", bad == 0, "%d" % bad)
	verdict("A5 новые тела получают настоящий слот (не −1)", neg_idx == 0, "%d из %d" % [neg_idx, more])
	cr.clear()
	root.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _block_b() -> void:
	print("\n═════ B. ПОВОДОК ПОГОНИ — ОДНО РЕШЕНИЕ НА ОТРЯД ═════")
	# Разворот ТЗ 31.10.2026 (lock_chase): под замком игрока поводок 7 м
	# погоню больше не снимает — блок мерит сам поводок, ручку выключает
	var lc0: bool = _Opt.lock_chase
	_Opt.lock_chase = false
	var at := Vector3(-40, 0, -30)
	_clear(at, 60.0)
	await pframes(5)
	var men: Array = _squad("warrior", at, 24, F, 8)
	var foes: Array = _squad("spearman", at + Vector3(4.0, 0, 0), 6, E, 3)
	for f in foes:
		(f as Unit).max_health *= 50.0
		(f as Unit).current_health = (f as Unit).max_health
	await pframes(10)
	for m in men:
		(m as Unit).command_attack(foes[0], true, true, true)
	# Контакт: хотя бы один боец дотянулся (якорь погони поставлен)
	var t := 0
	while t < 60 * 15:
		await pframes(10)
		t += 10
		var touched := false
		for m in _alive(men):
			if (m as Unit)._pursuit_anchored:
				touched = true
		if touched:
			break
	await pframes(60 * 2)
	var locked0 := 0
	for m in _alive(men):
		if (m as Unit).target_lock:
			locked0 += 1
	print("    контакт через %.1f с, под замком %d из %d" % [float(t) / 60.0, locked0, men.size()])
	# Беглецы уходят бегом на 70 м. Из рубки бегом не выйти (сквозь тела и
	# сцепку) — отрыв на 6 м переносом, дальше честный бег
	for f in _alive(foes):
		var fu := f as Unit
		fu.set_attack_target(null)
		fu.global_position += Vector3(6.0, 0.0, 0.0)
		fu.sync_row()
	for f in _alive(foes):
		(f as Unit).command_move(GameManager.land_target((f as Node3D).global_position + Vector3(70, 0, 8)),
			false, Vector3.ZERO, false, true, true)
	# Срыв поводка — первый боец, у которого замок снят веткой поводка
	# (якорь и «дотянулся» сброшены вместе с замком)
	var leash_t := -1
	t = 0
	while t < 60 * 20 and leash_t < 0:
		await get_tree().physics_frame
		t += 1
		for m in _alive(men):
			var u := m as Unit
			if not u.target_lock and not u._pursuit_anchored and not u._engaged_once 					and u.state != Unit.State.IDLE:
				leash_t = t
				break
	await pframes(60)
	var chasing := 0
	for m in _alive(men):
		var u := m as Unit
		var tg = u.attack_target
		if u.state == Unit.State.ATTACKING and tg != null and is_instance_valid(tg) and tg in foes 				and (tg as Node3D).global_position.distance_to(u.global_position) > 3.0:
			chasing += 1
	if leash_t >= 0:
		print("    срыв поводка через %.1f с бега; через 1 с после него гонятся %d из %d" % [
			float(leash_t) / 60.0, chasing, _alive(men).size()])
	else:
		print("    срыва поводка за 20 с не было (беглецов догнали); гонятся %d из %d" % [chasing, _alive(men).size()])
	verdict("B1 погоня кончена у всего отряда (через 1 с после срыва не гонится никто)",
		chasing == 0, "гонятся %d" % chasing)
	await pframes(int(RETURN_SEC * 60.0))
	var alive: Array = _alive(men)
	var xs: Array = []
	var zs: Array = []
	for m in alive:
		xs.append((m as Unit).global_position.x)
		zs.append((m as Unit).global_position.z)
	xs.sort()
	zs.sort()
	var med := Vector2(float(xs[xs.size() / 2]), float(zs[zs.size() / 2]))
	var far := 0
	var worst := 0.0
	for m in alive:
		var dd: float = Vector2((m as Unit).global_position.x, (m as Unit).global_position.z).distance_to(med)
		worst = maxf(worst, dd)
		if dd > SPLIT_R:
			far += 1
	print("    через %.0f с: худший отрыв от медианы отряда %.1f м, дальше %.0f м — %d" % [RETURN_SEC, worst, SPLIT_R, far])
	verdict("B2 отряд не порван погоней (никто дальше %.0f м от медианы)" % SPLIT_R, far == 0,
		"%d бойцов, худший %.1f м" % [far, worst])
	_Opt.lock_chase = lc0
	for m in men:
		if is_instance_valid(m): m.queue_free()
	for f in foes:
		if is_instance_valid(f): f.queue_free()
	await pframes(10)

# ─────────────────────────────────────────────────────────────────────────────
func _block_c() -> void:
	print("\n═════ C. ЗОНД «БЕГ НА МЕСТЕ» И ГАРНИЗОН ═════")
	# При прямой загрузке Main крепостей нет ни у кого — снятие с карты делается
	# теми же вызовами, что в Castle.absorb_unit (отрисовка, тик, признак карты)
	var at := Vector3(-30, 0, 20)
	_clear(at, 20.0)
	await pframes(5)
	var men: Array = _squad("spearman", at, 12, F, 4)
	await pframes(30)
	# Бегом, как в партии: признак бега и лента ходьбы у входящих
	for m in men:
		(m as Unit).command_move(at + Vector3(20, 0, 0), false, Vector3.ZERO, false, true, true)
	await pframes(40)
	for m in men:
		var u := m as Unit
		u.visible = false
		u.leave_render()
		u.set_draw(false)
		u.set_tick(false)
		# MOVING, а не IDLE, как у замка: в headless у строки нет ленты, и
		# зонд судит «бег» по состоянию хода — так блок ловит прежний дефект
		# и без окна (строка вне карты не должна попадать в ответ НИКАК)
		u.state = Unit.State.MOVING
		u.set_off_map(true)
	var rows: Dictionary = {}
	for m in men:
		rows[(m as Unit)._soa] = true
	var r0: int = (men[0] as Unit)._soa
	print("    строка %d: состояние в ядре %d (MOVING=%d), лента привязана %s, флаги %d" % [r0,
		GameManager.army.state_of(r0), Unit.State.MOVING, GameManager.army.row_look_bound(r0),
		GameManager.army.flags_of(r0)])
	# Окно замера у ядра одно на всех: зонд партии (SquadProbes, раз в 250 мс)
	# забирал бы его раньше стенда — на время блока он выключен
	var probes_was: bool = _Opt.squad_probes
	_Opt.squad_probes = false
	var hit := 0
	for k in range(16):
		await pframes(15)
		var got: PackedInt32Array = GameManager.army.probe_stuck_rows(Unit.game_ms(), 0.15, 500, 2, Unit.State.MOVING)
		for r in got:
			if rows.has(r):
				hit += 1
	_Opt.squad_probes = probes_was
	print("    в гарнизоне %d, попаданий их строк в ответ зонда %d" % [men.size(), hit])
	verdict("C1 гарнизон не «бежит на месте»", hit == 0, "%d" % hit)
