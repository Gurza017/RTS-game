extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ВАЛИДАТОР ПРИБЫТИЯ ОТРЯДА (ТЗ 28.10.2026, вечер, «бег на месте»)
## ═══════════════════════════════════════════════════════════════════════════
## Порог прибытия 0.48 м, а чужой отряд ядро держит на 0.67 м: место, занятое
## или прижатое другим отрядом, недостижимо — боец упирается в тела в 0.6-0.9 м
## от ячейки и бежит на месте. Лечение — на уровне отряда, без таймеров:
## доля отряда в 1 м от ячеек → отряд прибыл → один проход ставит в покой
## упёршихся в допуске (GameManager.squad_note_zone / Unit.settle_in_zone),
## опоздавший применяет то же правило сам по флагу отряда.
## Лестницы-таймеры (stall_arrive, run_in_place_cure) на стенде ВЫКЛЮЧЕНЫ:
## валидатор обязан справляться один.
##   A — места заняты стоящим чужим отрядом: все 24 в покое, строки ядра в
##       покое, один проход на приказ, зонд застревания молчит; без ручки
##       бегут на месте дальше
##   B — точность не потеряна: сдвиг на 0.8 м у прибывшего отряда исполняется
##   C — свободный марш: никого не остановили раньше порога
## Запуск: godot --headless --path . res://qa_squad_arrival/Test.tscn [-- only=abc]

const _Opt := preload("res://scripts/perf_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const F := Constants.FACTION_PLAYER

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abc"
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
	print("\n═════ ИТОГ qa_squad_arrival: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, at: Vector3, n: int, cols: int = 6, fac: int = F) -> Array:
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

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _flat(c: Vector3, r: float) -> void:
	main._clear_trees(c, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(c) < r:
				u.queue_free()

func _moving(men: Array) -> int:
	var n := 0
	for m in _alive(men):
		if (m as Unit).state == Unit.State.MOVING:
			n += 1
	return n

func _snap(men: Array) -> Dictionary:
	var d: Dictionary = {}
	for m in _alive(men):
		d[(m as Unit).get_instance_id()] = (m as Unit).global_position
	return d

## Бегущие на месте: MOVING и смещение за окно меньше 0.5 м
func _rip_count(men: Array, before: Dictionary) -> int:
	var n := 0
	for m in _alive(men):
		var u := m as Unit
		var p0: Variant = before.get(u.get_instance_id())
		if p0 == null or u.state != Unit.State.MOVING:
			continue
		if u.global_position.distance_to(p0 as Vector3) < 0.5:
			n += 1
	return n

func _rows_of(men: Array) -> Dictionary:
	var d: Dictionary = {}
	for m in _alive(men):
		d[(m as Unit)._soa] = true
	return d

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for nm in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager"]:
		var nd = main.get(nm)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	# Лестницы-таймеры выключены: валидатор обязан справляться один
	_Opt.stall_arrive = false
	_Opt.run_in_place_cure = false
	_Opt.unstick = false
	if "a" in _only:
		await _case_a(true)
		await _case_a(false)
		await _case_a_deep()
	if "b" in _only:
		await _case_b()
	if "c" in _only:
		await _case_c()
	_finish()

## ── A. МЕСТА ПРИКАЗА — В ЧУЖИХ ТЕЛАХ ───────────────────────────────────────
## Союзные тела шаг не блокируют (разведение только разводит, и боец доходит
## до 0.48 сквозь стоящих своих — проверено этим же стендом), а ЧУЖИЕ тела
## блокируют шаг в BLOCK_RADIUS 0.55: место приказа в 0.2 м за чужим бойцом
## недостижимо, и боец упирается в 0.6-0.9 м от него — та самая мёртвая зона.
## Красный отряд заморожен (set_tick false — тело в сетке остаётся), у наших
## attack_damage 0, чтобы марш не перехватывал заслон и остался MOVING
func _case_a(knob: bool) -> void:
	print("
── A. места приказа в чужих телах (ручка squad_arrive_validate = %s) ──" % str(knob))
	_Opt.squad_arrive_validate = knob
	var ford: Vector3 = main.ford_point()
	var at := Vector3(ford.x - 90.0, 0, ford.z + 40.0)
	_flat(at, 30.0)
	var a: Array = _squad("spearman", at, 24, 24, Constants.FACTION_ENEMY)
	var b: Array = _squad("spearman", at + Vector3(0, 0, -12.0), 24, 24)
	await pframes(10)
	for m in a:
		(m as Unit).set_tick(false)        # чужие тела стоят, не бьют
	for m in b:
		(m as Unit).attack_damage = 0.0    # марш без перехвата заслона
	await pframes(30)
	var sid_a: int = (a[0] as Unit).squad_id
	var sid_b: int = (b[0] as Unit).squad_id
	var v0: int = GameManager.squad_arrive_validations
	var s0: int = GameManager.squad_arrive_settled
	var z0: int = Unit.zone_arrivals
	# Каждому из B — место в 0.2 м за чужим бойцом (приказ игрока)
	for i in range(24):
		var tgt: Vector3 = (a[i] as Unit).global_position + Vector3(0, 0, 0.2)
		(b[i] as Unit).command_move(tgt, false, Vector3.ZERO, false, true)
	await pframes(2)
	var t0: int = Unit.game_ms()
	var settled_ms: int = -1
	var frames := 0
	var idle_at: Dictionary = {}       # id → [мс, dist до поста в миг покоя]
	while Unit.game_ms() - t0 < 10000:
		await get_tree().physics_frame
		frames += 1
		for m in _alive(b):
			var u := m as Unit
			if u.state != Unit.State.MOVING and not idle_at.has(u.get_instance_id()):
				idle_at[u.get_instance_id()] = [Unit.game_ms() - t0, snappedf(Vector2(u.post_pos.x - u.global_position.x, u.post_pos.z - u.global_position.z).length(), 0.01), int(u.state), u._settled]
		if frames % 6 == 0 and settled_ms < 0 and _moving(b) == 0:
			settled_ms = Unit.game_ms() - t0
	for m in _alive(b):
		var u := m as Unit
		var dn: float = Vector2(u.post_pos.x - u.global_position.x, u.post_pos.z - u.global_position.z).length()
		if dn > Unit.ARRIVE_RADIUS:
			print("    боец %d: сейчас %.2f м от поста, state %d, settled %s, в покое с %s, stall %d" % [u.get_instance_id() % 1000, dn, int(u.state), str(u._settled), str(idle_at.get(u.get_instance_id())), int(Unit.stall_by_unit.get(u.get_instance_id(), 0))])
	var mv: int = _moving(b)
	var near := 0
	var worst := 0.0
	for m in _alive(b):
		var u := m as Unit
		var d: float = Vector2(u.post_pos.x - u.global_position.x, u.post_pos.z - u.global_position.z).length()
		worst = maxf(worst, d)
		if d < Unit.SQUAD_ARRIVE_TOL:
			near += 1
	var vb: int = int(GameManager.squad_arrive_by_sid.get(sid_b, 0))
	print("  через 10 с: MOVING %d из 24, все встали через %d мс; в 1 м от ячейки %d, худший %.2f м; проходов: всего %d, у B %d, у A %d; остановлено проходом %d, по флагу в тике %d; вызволений %d" % [
		mv, settled_ms, near, worst, GameManager.squad_arrive_validations - v0, vb, int(GameManager.squad_arrive_by_sid.get(sid_a, 0)),
		GameManager.squad_arrive_settled - s0, Unit.zone_arrivals - z0 - (GameManager.squad_arrive_settled - s0), Unit.unstuck_total])
	if knob:
		verdict("A1 все 24 в покое не позже 8 с после приказа (путь 12 м ≈ 5 с)",
			mv == 0 and settled_ms > 0 and settled_ms <= 8000, "MOVING %d, встали через %d мс" % [mv, settled_ms])
		var core_bad := 0
		var vel_bad := 0
		for m in _alive(b):
			var u := m as Unit
			if u._soa >= 0 and GameManager.army.state_of(u._soa) != Unit.State.IDLE:
				core_bad += 1
			if u.velocity.length_squared() > 1e-6:
				vel_bad += 1
		verdict("A2 строки ядра в IDLE и скорость обнулена", core_bad == 0 and vel_bad == 0,
			"ядро не IDLE %d, скорость не ноль %d" % [core_bad, vel_bad])
		verdict("A3 один проход валидатора на приказ у отряда B", vb == 1, "проходов у B %d" % vb)
		verdict("A4 все в допуске 1 м от своих ячеек", near == _alive(b).size(), "в допуске %d, худший %.2f м" % [near, worst])
		var snap_on: Dictionary = _snap(b)
		await pframes(60 * 2)
		verdict("A5 через 2 с никто не бежит на месте", _rip_count(b, snap_on) == 0, "бегут на месте %d" % _rip_count(b, snap_on))
	else:
		var snap: Dictionary = _snap(b)
		await pframes(60 * 2)
		var rip: int = _rip_count(b, snap)
		verdict("A6 без ручки (и без лестниц-таймеров) бегут на месте дальше — ручка нужна",
			rip > 0, "бегут на месте %d, MOVING %d" % [rip, _moving(b)])
	_free(a); _free(b)
	await pframes(5)

## ── A-deep. ГЛУБОКИЙ СТРОЙ ЗА ЗАБЛОКИРОВАННЫМ ФРОНТОМ (справочно, без вердикта)
## Места 6×4 внутри чужого блока: в допуске 1 м только передний ряд, задние
## стоят в 1.45-2.8 м от своих ячеек. Валидатор по ТЗ (допуск 1 м) ставит
## передний ряд; задние — лестница stall_arrive (1.2-3 м, 1 с) на штатном
## месте. Печать — владельцу для решения о допуске глубокого строя
func _case_a_deep() -> void:
	print("
── A-deep. места 6×4 внутри чужого блока (справочно; stall_arrive = %s) ──" % str(_Opt.stall_arrive))
	var stall_was: bool = _Opt.stall_arrive
	_Opt.stall_arrive = true
	_Opt.squad_arrive_validate = true
	var ford: Vector3 = main.ford_point()
	var at := Vector3(ford.x - 90.0, 0, ford.z + 40.0)
	_flat(at, 30.0)
	var a: Array = _squad("spearman", at, 24, 6, Constants.FACTION_ENEMY)
	var b: Array = _squad("spearman", at + Vector3(0, 0, -12.0), 24, 6)
	await pframes(10)
	for m in a:
		(m as Unit).set_tick(false)
	for m in b:
		(m as Unit).attack_damage = 0.0
	await pframes(30)
	var sid_b: int = (b[0] as Unit).squad_id
	var z0: int = Unit.zone_arrivals
	var st0: int = Unit.stall_arrivals
	for i in range(24):
		var tgt: Vector3 = (a[i] as Unit).global_position + Vector3(0, 0, 0.2)
		(b[i] as Unit).command_move(tgt, false, Vector3.ZERO, false, true)
	await pframes(60 * 10)
	var near := 0
	for m in _alive(b):
		var u := m as Unit
		if Vector2(u.post_pos.x - u.global_position.x, u.post_pos.z - u.global_position.z).length() < Unit.SQUAD_ARRIVE_TOL:
			near += 1
	print("  через 10 с: MOVING %d из 24; в 1 м от ячейки %d; проходов у отряда %d; встали зоной %d, лестницей stall_arrive %d" % [
		_moving(b), near, int(GameManager.squad_arrive_by_sid.get(sid_b, 0)), Unit.zone_arrivals - z0, Unit.stall_arrivals - st0])
	_Opt.stall_arrive = stall_was
	_free(a); _free(b)
	await pframes(5)

## ── B. ТОЧНОСТЬ: СДВИГ НА 0.8 М У ПРИБЫВШЕГО ОТРЯДА ИСПОЛНЯЕТСЯ ─────────────
func _case_b() -> void:
	print("\n── B. сдвиг на 0.8 м после прибытия (смыкание рядов не замирает) ──")
	_Opt.squad_arrive_validate = true
	var ford: Vector3 = main.ford_point()
	var at := Vector3(ford.x - 90.0, 0, ford.z - 40.0)
	_flat(at, 30.0)
	var c: Array = _squad("spearman", at, 24)
	await pframes(10)
	for m in c:
		var u := m as Unit
		u.command_move(u.global_position + Vector3(20, 0, 0), false, Vector3.ZERO, false, true)
	var t0: int = Unit.game_ms()
	while Unit.game_ms() - t0 < 14000 and _moving(c) > 0:
		await get_tree().physics_frame
	var armed := 0
	for m in _alive(c):
		if (m as Unit)._squad_arrived:
			armed += 1
	print("  марш 20 м: MOVING %d, флаг прибытия у %d из %d" % [_moving(c), armed, _alive(c).size()])
	verdict("B1 отряд прибыл и флаг роздан всем", _moving(c) == 0 and armed == _alive(c).size(),
		"MOVING %d, флаг у %d" % [_moving(c), armed])
	var snap: Dictionary = _snap(c)
	for m in _alive(c):
		var u := m as Unit
		u.command_move(u.global_position + Vector3(0, 0, 0.8), false, Vector3.ZERO, false, true)
	await pframes(60 * 3)
	var moved := 0
	var short := 0
	for m in _alive(c):
		var u := m as Unit
		var p0: Vector3 = snap[u.get_instance_id()]
		var d: float = u.global_position.distance_to(p0)
		if d >= 0.25:
			moved += 1
		else:
			short += 1
	print("  сдвиг 0.8 м (до порога 0.48 — ход ≥ 0.32): прошли ≥ 0.25 м — %d, замерли — %d, MOVING %d" % [moved, short, _moving(c)])
	verdict("B2 сдвиг исполнен всеми (правило зоны не замораживает короткий ход)",
		short == 0 and _moving(c) == 0, "замерли %d, MOVING %d" % [short, _moving(c)])
	_free(c)
	await pframes(5)

## ── C. СВОБОДНЫЙ МАРШ: НИКОГО НЕ ОСТАНОВИЛИ РАНЬШЕ ПОРОГА ─────────────────
func _case_c() -> void:
	print("\n── C. свободный марш без помех ──")
	_Opt.squad_arrive_validate = true
	var ford: Vector3 = main.ford_point()
	var at := Vector3(ford.x - 60.0, 0, ford.z + 70.0)
	_flat(at, 30.0)
	var d: Array = _squad("spearman", at, 24)
	await pframes(10)
	var s0: int = GameManager.squad_arrive_settled
	var z0: int = Unit.zone_arrivals
	for m in d:
		var u := m as Unit
		u.command_move(u.global_position + Vector3(0, 0, 15), false, Vector3.ZERO, false, true)
	var t0: int = Unit.game_ms()
	while Unit.game_ms() - t0 < 12000 and _moving(d) > 0:
		await get_tree().physics_frame
	var far := 0
	var worst := 0.0
	for m in _alive(d):
		var u := m as Unit
		var dd: float = Vector2(u.post_pos.x - u.global_position.x, u.post_pos.z - u.global_position.z).length()
		worst = maxf(worst, dd)
		if dd > Unit.ARRIVE_RADIUS + 0.05:
			far += 1
	print("  свободный марш 15 м: MOVING %d, дальше порога прибытия %d, худший %.2f м; остановлено зоной %d" % [
		_moving(d), far, worst, Unit.zone_arrivals - z0])
	verdict("C1 все дошли до порога, зона никого не остановила раньше",
		_moving(d) == 0 and far == 0 and Unit.zone_arrivals - z0 == 0 and GameManager.squad_arrive_settled - s0 == 0,
		"MOVING %d, дальше порога %d, зоной %d" % [_moving(d), far, Unit.zone_arrivals - z0])
	_free(d)
	await pframes(5)
