extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ВОСКРЕШЕНИЕ НЕ РАЗДУВАЕТ ОТРЯД СВЕРХ ШТАТА (разбор партии 29.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## В партии крепость доукомплектовала отряд копейщиков до штата (60), а монахи
## тем временем поднимали в него павших с поля: отряд выходил из ворот с 67-72
## бойцами, пик «full» уезжал за ним. Ручка perf_config.raise_squad_cap.
##   A ПРЯМО   — raise_fallen в полный отряд отказывает, тело лежит; поиск тел
##               полного отряда пуст; неполный — поднимается ровно до штата;
##               ручка снята — прежний перебор (доказательство ручки)
##   B МОНАХ   — живой монах (2d) у тел отряда, пополненного до штата
##               «крепостью»: за 25 с ни одного подъёма; трое пали — поднял,
##               но не сверх штата
## Штат — из unit_stats_config.squad_size (правило 10), время — физкадрами.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_raise_cap: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 10) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x + float(i % cols) * 0.7, 0.0, at.z + float(i / cols) * 0.7))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

## Живые отряда — прямо из записи (squad_members — не читатель)
func _alive(sid: int) -> int:
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return 0
	var n := 0
	for m in (raw as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n

func _first_alive(sid: int) -> Unit:
	for m in (GameManager.squads[sid]["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			return m
	return null

## Тела отряда, годные к подъёму (в обход фильтра поиска)
func _corpses_of(sid: int) -> Array:
	var out: Array = []
	for c in GameManager.corpses._raisable_list(F):
		if int(c.squad_id) == sid:
			out.append(c)
	return out

## «Крепость»: добрать отряд новобранцами до штата
func _refill(sid: int, at: Vector3) -> void:
	var t: String = GameManager.squad_type(sid)
	var full: int = _UCfg.squad_size(t)
	var k := 0
	while _alive(sid) < full:
		var u: Unit = _spawn(t, F, at + Vector3(float(k) * 0.7, 0.0, -3.0))
		GameManager.add_to_squad(sid, u)
		k += 1

func _kill_squad(sid: int) -> void:
	for m in (GameManager.squads[sid]["members"] as Array).duplicate():
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			(m as Unit).take_damage(1e12)

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(14.0, 0.0, 0.0), Vector3(-14.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 14.0), Vector3(0.0, 0.0, -14.0)]:
				var q: Vector3 = p + (d as Vector3)
				h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
				if GameManager.is_water(q.x, q.z) or not GameManager.is_passable(q.x, q.z):
					h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if main.fog != null:
		main.fog.enabled = false
	GameManager.pop_limit_enabled = false
	await frames(3)
	for n in get_tree().get_nodes_in_group("all_units"):
		var wu := n as Unit
		if wu != null and wu.faction != F:
			wu.set_tick(false)
	var base: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 30.0))
	main._clear_area_of_resources(base, 60.0)
	await _a_direct(base)
	await _b_monk(base + Vector3(0.0, 0.0, 30.0))
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ПОДЪЁМ НАПРЯМУЮ
# ═════════════════════════════════════════════════════════════════════════════
func _a_direct(base: Vector3) -> void:
	print("\n═════ A. ПОДЪЁМ В ПОЛНЫЙ ОТРЯД ═════")
	var full: int = _UCfg.squad_size("spearman")
	var sq: Array = _squad("spearman", F, base, full)
	var sid: int = int(sq[0])
	for i in range(5):
		(sq[1][i] as Unit).take_damage(1e12)
	await pframes(4)
	var bodies: Array = _corpses_of(sid)
	verdict("A0 пятеро пали, тела годны к подъёму (%d)" % bodies.size(), bodies.size() >= 5)
	if bodies.is_empty():
		return
	_refill(sid, base)
	await pframes(2)
	var r0: int = GameManager.raise_refused_full
	var u: Unit = GameManager.raise_fallen(bodies[0], null)
	verdict("A1 отряд в штате (%d/%d): подъём отклонён, тело лежит, отказов +%d" % [
		_alive(sid), full, GameManager.raise_refused_full - r0],
		u == null and _alive(sid) == full and GameManager.raise_refused_full == r0 + 1
		and int(bodies[0].index) >= 0 and _corpses_of(sid).size() == bodies.size())
	var c_sq = GameManager.corpses.find_raisable_of_squad(F, sid, base, 80.0)
	var c_any = GameManager.corpses.find_raisable_priority(F, base, 80.0, "monk")
	var c_near = GameManager.corpses.find_raisable(F, base, 80.0)
	verdict("A2 поиск тел не отдаёт павших полного отряда (по отряду, приоритетный, ближайший)",
		c_sq == null and (c_any == null or int(c_any.squad_id) != sid)
		and (c_near == null or int(c_near.squad_id) != sid))
	# Один пал — место есть: поднимается ровно до штата
	_first_alive(sid).take_damage(1e12)
	await pframes(3)
	var c1 = GameManager.corpses.find_raisable_of_squad(F, sid, base, 80.0)
	var u1: Unit = GameManager.raise_fallen(c1, null) if c1 != null else null
	var c2 = GameManager.corpses.find_raisable_of_squad(F, sid, base, 80.0)
	var left: Array = _corpses_of(sid)
	var u2: Unit = GameManager.raise_fallen(left[0], null) if not left.is_empty() else null
	verdict("A3 один пал: поднят в отряд (%s), отряд %d/%d, второго тела поиск не отдаёт и подъём отклонён" % [
		str(u1 != null), _alive(sid), full],
		u1 != null and u1.squad_id == sid and _alive(sid) == full and c2 == null and u2 == null)
	# Ручка снята — прежний перебор (доказательство, что запрет держит она)
	_Opt.raise_squad_cap = false
	left = _corpses_of(sid)
	var u3: Unit = GameManager.raise_fallen(left[0], null) if not left.is_empty() else null
	verdict("A4 ручка raise_squad_cap=false: подъём в полный отряд проходит (%d/%d) — прежний перебор" % [
		_alive(sid), full], u3 != null and _alive(sid) == full + 1)
	_Opt.raise_squad_cap = true
	_kill_squad(sid)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. ЖИВОЙ МОНАХ У ТЕЛ ДОУКОМПЛЕКТОВАННОГО ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _b_monk(base: Vector3) -> void:
	print("\n═════ B. МОНАХ И ПОЛНЫЙ ОТРЯД ═════")
	GameManager.researched.erase(F)
	for cell in ["1a", "1b", "1c", "1d", "2a", "2b", "2c", "2d"]:
		GameManager.finish_research(F, "monk_" + cell)
	var full: int = _UCfg.squad_size("spearman")
	var sq: Array = _squad("spearman", F, base, full)
	var sid: int = int(sq[0])
	for i in range(8):
		(sq[1][i] as Unit).take_damage(1e12)
	await pframes(4)
	_refill(sid, base)
	var monk: Unit = _spawn("monk", F, base + Vector3(2.0, 0.0, -2.0))
	await pframes(4)
	verdict("B0 монах умеет поднимать, тел отряда %d, отряд %d/%d" % [_corpses_of(sid).size(), _alive(sid), full],
		bool(monk.call("can_resurrect")) and _corpses_of(sid).size() >= 8 and _alive(sid) == full)
	var peak: int = _alive(sid)
	for _i in range(60 * 25):
		await get_tree().physics_frame
		peak = maxi(peak, _alive(sid))
	verdict("B1 за 25 с монах не поднял никого в полный отряд: пик %d/%d, поднято %d" % [
		peak, full, int(monk.get("resurrected_total"))],
		peak == full and int(monk.get("resurrected_total")) == 0)
	for _k in range(3):
		_first_alive(sid).take_damage(1e12)
	await pframes(4)
	peak = 0
	for _i in range(60 * 40):
		await get_tree().physics_frame
		peak = maxi(peak, _alive(sid))
		if _alive(sid) >= full and int(monk.get("resurrected_total")) > 0:
			break
	for _i in range(60 * 5):
		await get_tree().physics_frame
		peak = maxi(peak, _alive(sid))
	verdict("B2 трое пали — монах поднимает (%d), но не сверх штата: пик %d/%d" % [
		int(monk.get("resurrected_total")), peak, full],
		int(monk.get("resurrected_total")) >= 1 and peak <= full)
	monk.take_damage(1e12)
	GameManager.researched.erase(F)
