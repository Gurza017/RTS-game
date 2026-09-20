extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_building_navigation — ОБТЕКАНИЕ ЗДАНИЙ, ВХОДЫ, СДАЧА РЕСУРСОВ
## (ТЗ 19.09.2026 «Фикс обтекания зданий и навигации»)
## ═══════════════════════════════════════════════════════════════════════════
## Застройка на ровной площадке: крепость, два барака, четыре башни, золотая
## жила и два массива деревьев. 10 рабочих, 2 отряда лучников, 6 отрядов
## копейщиков (3 по ТЗ + 3 для массового марша).
##   A. РАБОЧИЕ — 120 с добычи с сдачей в крепость: ходки идут, ни один не
##      стоит у дверей дольше STALL_MAX_SEC, ни один не «мечется»;
##   B. ГАРНИЗОН — лучники заходят в башню и крепость и выходят по приказу в
##      срок (дважды), фундамент не держит ни на входе, ни на выходе;
##   C. МАССОВЫЙ МАРШ — 8 отрядов вправо сквозь застройку и обратно: доходят
##      в срок, тел внутри фундаментов ноль, отряд НЕ расщепляется (нет
##      двух групп по разные стороны), поперечный габарит после прохода
##      восстанавливается, крюк центра отряда не длиннее DETOUR_MAX.
## Запуск: godot --headless --path . res://qa_building_navigation/Test.tscn
##   ключи: -- fast (короткий марш), skip=abc (пропустить блоки)

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _TowerS := preload("res://scripts/Tower.gd")
const F := Constants.FACTION_PLAYER

## Рабочий в RETURNING без сдвига дольше этого — застрял
const STALL_MAX_SEC := 6.0
## Крюк центра отряда: длина пути центра / прямая
const DETOUR_MAX := 1.35
## Расщепление: щель по поперечной оси между двумя группами (≥ 3 бойца в каждой)
const SPLIT_GAP := 5.0
const SPLIT_MIN_MEN := 3
## «Вплотную»: отряд, чья прямая шла сквозь крепость, проходит не дальше
## HUG_MAX от края фундамента (мерится ближайший боец по точным кругам)
const HUG_MAX := 2.0
const HUG_PROBE := 4.0

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _skip := ""
var _fast := false
var _trace := -1
var base := Vector3.ZERO
var keep: Castle = null
var towers: Array = []
var barracks: Array = []
var gold_nodes: Array = []
var workers: Array = []
## Пробы рабочих (блок A): собираются каждые SAMPLE_FRAMES физкадров
const SAMPLE_FRAMES := 30
var _w_last: Dictionary = {}       # uid → последняя точка
var _w_streak: Dictionary = {}     # uid → подряд проб без сдвига в RETURNING
var _w_worst: Dictionary = {}      # uid → худшая серия (пробы)
var _w_flips: Dictionary = {}      # uid → развороты по X подряд (метания)
var _w_last_dx: Dictionary = {}
var _w_samples := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s == "fast":
			_fast = true
		elif s.begins_with("skip="):
			_skip = s.substr(5)
		elif s.begins_with("trace="):
			_trace = int(s.substr(6))
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_building_navigation: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 8) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var sp: float = 0.6
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x + float(i / cols) * sp - float((n - 1) / cols) * sp * 0.5, 0.0,
			at.z + float(i % cols) * sp - float(cols - 1) * sp * 0.5))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _place(b: Building, at: Vector3, fac: int = F) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _clear_trees(at: Vector3, r: float) -> void:
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn0 := n0 as ResourceNode
		if rn0 != null and is_instance_valid(rn0) and _xz(rn0.global_position, at) < r:
			rn0.queue_free()

func _node(rtype: int, at: Vector3, scale_v: float = 1.0) -> ResourceNode:
	var r := ResourceNode.new()
	r.resource_type = rtype
	r.size_scale = scale_v
	r.remaining = 100000.0
	main.world_add(r)
	r.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return r

## Ровная сухая площадка 110 × 56 м без скал и воды в поле карты
func _flat_spot(seed_p: Vector3, span: float) -> Vector3:
	var best: Vector3 = seed_p
	var best_h: float = 1e9
	for ix in range(-6, 7):
		for iz in range(-5, 6):
			var p := Vector3(seed_p.x + float(ix) * span, 0.0, seed_p.z + float(iz) * span)
			var bad := false
			var h := 0.0
			for dx in [-54.0, -27.0, 0.0, 27.0, 54.0]:
				for dz in [-26.0, -13.0, 0.0, 13.0, 26.0]:
					var q: Vector3 = p + Vector3(dx, 0.0, dz)
					if GameManager.is_water(q.x, q.z) or GameManager.is_cliff(q.x, q.z) \
							or absf(q.x) > GameManager.map_lim_x - 4.0 or absf(q.z) > GameManager.map_lim_z - 4.0:
						bad = true
					h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
			if bad:
				continue
			if h < best_h:
				best_h = h
				best = p
	print("  площадка стенда: %s (перепад %.2f м)" % [str(best), best_h])
	return best

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _inside(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and (u as Unit).garrisoned:
			n += 1
	return n

func _in_bld(p: Vector3) -> bool:
	return GameManager.bld_depth(p.x, p.z, 0.0) > 0.0

func _deposit_point() -> Vector3:
	if keep.has_method("deposit_point"):
		return keep.call("deposit_point")
	return keep._gate_position()

func _centre(men: Array) -> Vector3:
	var c: Vector3 = GameManager._centroid_of(_alive(men))
	c.y = 0.0
	return c

## Расщепление отряда: сортируем поперечную координату, ищем щель ≥ SPLIT_GAP
## с не меньше SPLIT_MIN_MEN бойцов по обе стороны
func _split(men: Array, axis_x: bool) -> bool:
	var vals: Array = []
	for u in _alive(men):
		var p: Vector3 = (u as Unit).global_position
		vals.append(p.z if axis_x else p.x)
	if vals.size() < SPLIT_MIN_MEN * 2:
		return false
	vals.sort()
	for i in range(1, vals.size()):
		if float(vals[i]) - float(vals[i - 1]) >= SPLIT_GAP and i >= SPLIT_MIN_MEN and vals.size() - i >= SPLIT_MIN_MEN:
			return true
	return false

func _extent(men: Array, axis_x: bool) -> float:
	var lo := 1e9
	var hi := -1e9
	for u in _alive(men):
		var p: Vector3 = (u as Unit).global_position
		var v: float = p.z if axis_x else p.x
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return maxf(hi - lo, 0.0)

## Проба рабочих: застревание и метания на обратной дороге
func _sample_workers() -> void:
	_w_samples += 1
	var dep: Vector3 = _deposit_point()
	for w in _alive(workers):
		var u := w as Unit
		var id: int = u.get_instance_id()
		var p: Vector3 = u.global_position
		var last: Vector3 = _w_last.get(id, p)
		var moved: float = _xz(p, last)
		_w_last[id] = p
		if u.state == Unit.State.RETURNING and _xz(p, dep) > 3.0:
			if moved < 0.12:
				_w_streak[id] = int(_w_streak.get(id, 0)) + 1
				_w_worst[id] = maxi(int(_w_worst.get(id, 0)), int(_w_streak[id]))
			else:
				_w_streak[id] = 0
			var dx: float = p.x - last.x
			var ldx: float = float(_w_last_dx.get(id, 0.0))
			if absf(dx) > 0.15 and absf(ldx) > 0.15 and signf(dx) != signf(ldx):
				_w_flips[id] = int(_w_flips.get(id, 0)) + 1
			_w_last_dx[id] = dx
		else:
			_w_streak[id] = 0
			_w_last_dx[id] = 0.0

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.troll_lair = null
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	base = _flat_spot(Vector3(-100.0, 0.0, -40.0), 10.0)
	_clear_trees(base, 70.0)
	await pframes(2)

	# ── ЗАСТРОЙКА ────────────────────────────────────────────────────────────
	keep = Castle.new()
	_place(keep, base)
	for bx in [-22.0, 22.0]:
		var b: Building = Barracks.new()
		_place(b, base + Vector3(bx, 0.0, 0.0))
		barracks.append(b)
	for tp in [Vector3(-11.0, 0.0, -14.0), Vector3(11.0, 0.0, -14.0), Vector3(-11.0, 0.0, 12.0), Vector3(11.0, 0.0, 12.0)]:
		var t: Building = _TowerS.new()
		_place(t, base + tp)
		towers.append(t)
	# Золотая жила слева-снизу, лес между жилой и крепостью и на полосе марша
	# Жила слева-СЗАДИ крепости: прямая от неё к воротам идёт через фундамент
	for gp in [Vector3(-40.0, 0.0, -16.0), Vector3(-43.0, 0.0, -13.0), Vector3(-37.0, 0.0, -13.5)]:
		gold_nodes.append(_node(Constants.RESOURCE_GOLD, base + gp, 1.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for tc in [Vector3(-27.0, 0.0, -10.0), Vector3(27.0, 0.0, -5.0)]:
		for i in range(9):
			var a: float = rng.randf() * TAU
			var r: float = 1.5 + rng.randf() * 4.0
			_node(Constants.RESOURCE_WOOD, base + tc + Vector3(cos(a) * r, 0.0, sin(a) * r), 1.0)
	await pframes(6)
	print("  построек в реестре фундаментов: %d" % GameManager.obstacle_count())
	var dep: Vector3 = _deposit_point()
	verdict("A0 точка сдачи ресурсов снаружи фундамента крепости",
		GameManager.bld_depth(dep.x, dep.z, Unit.BLD_CLEAR + 0.3) <= 0.0,
		"точка %s, центр %s" % [str(dep), str(keep.global_position)])

	# ── РАБОЧИЕ: ДОБЫЧА НА ВСЁ ВРЕМЯ СТЕНДА ─────────────────────────────────
	for i in range(10):
		var w: Unit = _spawn("worker", F, base + Vector3(-34.0 + float(i % 5) * 1.2, 0.0, -22.0 + float(i / 5) * 1.2))
		workers.append(w)
	await pframes(2)
	for i in range(workers.size()):
		(workers[i] as Worker).command_gather(gold_nodes[i % gold_nodes.size()])
	var gold0: float = ResourceManager.gathered_total(F, Constants.RESOURCE_GOLD)

	# ── ГАРНИЗОН ─────────────────────────────────────────────────────────────
	var arch1: Array = _squad("archer", F, base + Vector3(11.0, 0.0, 24.0), 20)
	var arch2: Array = _squad("archer", F, base + Vector3(-8.0, 0.0, 26.0), 20)
	await pframes(10)
	if not "b" in _skip:
		print("\n═════ B. ГАРНИЗОН: ВХОД И ВЫХОД ═════")
		var tw: Building = towers[3]
		for round_i in range(2):
			var t_in: int = await _garrison_in(tw, arch1, "башню", round_i)
			var t_out: int = await _garrison_out(tw, arch1, "башни", round_i, true)
			var k_in: int = await _garrison_in(keep, arch2, "крепость (крыша)", round_i)
			var k_out: int = await _garrison_out(keep, arch2, "крепости", round_i, false)
			print("    раунд %d: башня вход %d / выход %d, крепость вход %d / выход %d физкадров" % [round_i + 1, t_in, t_out, k_in, k_out])
	# Отряды лучников — на линию марша
	await pframes(30)

	# ── МАССОВЫЙ МАРШ ────────────────────────────────────────────────────────
	var squads: Array = []
	var zs: Array = [-20.0, -10.0, 0.0, 10.0, 20.0, -5.0, 5.0, 15.0]
	for i in range(6):
		squads.append(_squad("spearman", F, base + Vector3(-40.0, 0.0, float(zs[i])), 24))
	# Лучники встают на свои полосы
	squads.append(arch1)
	squads.append(arch2)
	await pframes(4)
	for i in range(6, 8):
		var sq: Array = squads[i]
		var c0: Vector3 = _centre(sq[1])
		for u in _alive(sq[1]):
			var off: Vector3 = (u as Unit).global_position - c0
			off.y = 0.0
			(u as Unit).command_move(base + Vector3(-40.0, 0.0, float(zs[i])) + off, false, Vector3.ZERO, false, true)
	await pframes(60 * 25)
	if not "c" in _skip:
		print("\n═════ C. МАССОВЫЙ МАРШ СКВОЗЬ ЗАСТРОЙКУ ═════")
		await _march(squads, base + Vector3(40.0, 0.0, 0.0), "вправо")
		await pframes(60 * 4)
		await _march(squads, base + Vector3(-40.0, 0.0, 0.0), "влево")

	# ── ИТОГ РАБОЧИХ ────────────────────────────────────────────────────────
	if not "a" in _skip:
		print("\n═════ A. РАБОЧИЕ: ДОБЫЧА И СДАЧА В КРЕПОСТЬ ═════")
		# Догоняем до 120 с наблюдения, если марш был короче
		var need: int = 60 * 120 - _w_samples * SAMPLE_FRAMES
		var f := 0
		while f < need:
			await pframes(SAMPLE_FRAMES)
			f += SAMPLE_FRAMES
			_sample_workers()
		var delivered: float = ResourceManager.gathered_total(F, Constants.RESOURCE_GOLD) - gold0
		var worst := 0
		var worst_id := 0
		var flips_max := 0
		for id in _w_worst.keys():
			if int(_w_worst[id]) > worst:
				worst = int(_w_worst[id])
				worst_id = id
		for id in _w_flips.keys():
			flips_max = maxi(flips_max, int(_w_flips[id]))
		var worst_sec: float = float(worst * SAMPLE_FRAMES) / 60.0
		var secs: float = float(_w_samples * SAMPLE_FRAMES) / 60.0
		var cap: float = 0.0
		if not workers.is_empty():
			cap = (workers[0] as Worker).carry_capacity()
		print("    наблюдение %.0f с, сдано золота %.0f (ходок ≈ %.1f), худший простой на обратной дороге %.1f с (боец %d), разворотов по X макс %d"
			% [secs, delivered, delivered / maxf(cap, 1.0), worst_sec, worst_id, flips_max])
		verdict("A1 рабочие носят золото в крепость: не меньше 10 ходок за наблюдение",
			delivered >= cap * 10.0, "сдано %.0f = %.1f ходок" % [delivered, delivered / maxf(cap, 1.0)])
		verdict("A2 ни один рабочий не стоял на обратной дороге дольше %.0f с" % STALL_MAX_SEC,
			worst_sec < STALL_MAX_SEC, "худший %.1f с" % worst_sec)
		verdict("A3 рабочие не мечутся у дверей (разворотов по X подряд ≤ 6)", flips_max <= 6, "макс %d" % flips_max)
		var inside_w := 0
		for w in _alive(workers):
			if _in_bld((w as Unit).global_position):
				inside_w += 1
		verdict("A4 в конце ни один рабочий не внутри фундамента", inside_w == 0, "внутри %d" % inside_w)
	_finish()

func _garrison_in(b: Building, sq: Array, what: String, round_i: int) -> int:
	var men: Array = _alive(sq[1])
	var far := 0.0
	var gate: Vector3 = b._gate_position()
	for u in men:
		far = maxf(far, _xz((u as Unit).global_position, gate))
	var speed: float = maxf((men[0] as Unit).move_speed, 1.0)
	var bound: int = int((far / speed + 12.0) * 60.0)
	var ok: bool = b.request_garrison(int(sq[0]))
	var w := 0
	while w < bound:
		await get_tree().physics_frame
		w += 1
		if w % SAMPLE_FRAMES == 0:
			_sample_workers()
		if _inside(men) == men.size():
			break
	var n_in: int = _inside(men)
	verdict("B%d.%d лучники вошли в %s в срок (%d из %d, %.1f с при бюджете %.1f)" % [round_i + 1, 1 if what.begins_with("баш") else 3, what, n_in, men.size(), float(w) / 60.0, float(bound) / 60.0],
		ok and n_in == men.size())
	return w

func _garrison_out(b: Building, sq: Array, what: String, round_i: int, tower: bool) -> int:
	var men: Array = _alive(sq[1])
	var gate: Vector3 = b._gate_position()
	if tower:
		b.release_all()
	else:
		b.release_roof()
	var bound: int = 60 * 12
	var w := 0
	var clear_n := 0
	while w < bound:
		await get_tree().physics_frame
		w += 1
		if w % SAMPLE_FRAMES == 0:
			_sample_workers()
		clear_n = 0
		for u in men:
			var uu := u as Unit
			# Вышел, встал на свою точку выхода, не в фундаменте
			if not uu.garrisoned and not _in_bld(uu.global_position) and uu.state == Unit.State.IDLE:
				clear_n += 1
		if clear_n == men.size():
			break
	var n_gar := 0
	var n_bld := 0
	var n_mov := 0
	var far_gate := 0.0
	for u in men:
		var uu := u as Unit
		if uu.garrisoned: n_gar += 1
		elif _in_bld(uu.global_position): n_bld += 1
		elif uu.state != Unit.State.IDLE: n_mov += 1
		if not uu.garrisoned:
			far_gate = maxf(far_gate, _xz(uu.global_position, gate))
	verdict("B%d.%d лучники вышли из %s и встали у ворот (%d из %d, %.1f с)" % [round_i + 1, 2 if tower else 4, what, clear_n, men.size(), float(w) / 60.0],
		clear_n == men.size(), "внутри %d, в фундаменте %d, ещё идут %d, дальний от ворот %.1f м" % [n_gar, n_bld, n_mov, far_gate])
	# Дать отряду встать на точку выхода
	await pframes(60 * 3)
	return w

func _march(squads: Array, click: Vector3, tag: String) -> void:
	var sm = main.selection_manager
	var all_men: Array = []
	var ext0: Array = []
	var starts: Array = []
	for sq in squads:
		var men: Array = _alive(sq[1])
		all_men.append_array(men)
		ext0.append(_extent(men, true))
		starts.append(_centre(men))
	sm.select_units(all_men)
	await pframes(2)
	var _Opt := preload("res://scripts/perf_config.gd")
	if _trace >= 0:
		_Opt.cmd_meter = true
		_Opt.cmd_reset()
	sm._issue_formation_move(click, false)
	await pframes(2)
	var n_sq: int = squads.size()
	var path_len: Array = []
	var last_c: Array = []
	var ext_max: Array = []
	var split_n: Array = []
	var goals: Array = []
	for i in range(n_sq):
		path_len.append(0.0)
		last_c.append(starts[i])
		ext_max.append(0.0)
		split_n.append(0)
		# Цель отряда — его конечная разметка (посты бойцов)
		var g := Vector3.ZERO
		var k := 0
		for u in _alive(squads[i][1]):
			g += (u as Unit).post_pos
			k += 1
		goals.append(g / maxf(float(k), 1.0))
	var inside_frames := 0
	var inside_worst := 0
	var hug: Array = []
	for i in range(n_sq):
		hug.append(HUG_PROBE)
	var arrived_all := false
	var w := 0
	# Бюджет: прямая по самому медленному роду плюс 20 с на обход и построение
	var slowest: float = 1e9
	for u in all_men:
		slowest = minf(slowest, maxf((u as Unit).move_speed, 0.5))
	var bound: int = int((80.0 / slowest + 20.0) * 60.0)
	var arrive_frame: Array = []
	for i in range(n_sq):
		arrive_frame.append(-1)
	while w < bound:
		await get_tree().physics_frame
		w += 1
		if w % SAMPLE_FRAMES == 0:
			_sample_workers()
		if w % 15 != 0:
			continue
		var inside := 0
		var done := 0
		for i in range(n_sq):
			var men: Array = _alive(squads[i][1])
			var c: Vector3 = _centre(men)
			if i == _trace and w % 60 == 0 and not men.is_empty():
				var u0 := men[0] as Unit
				print("    [trace %ds] центр %s ext %.1f; боец0 %s st=%d mt=%s route=%d/%d atk_route=%d/%d goal=%s" % [w / 60, str(c), _extent(men, true),
					str(u0.global_position), u0.state, str(u0.move_target), u0._route_i, u0._route.size(), u0._atk_route_i, u0._atk_route.size(), str(u0._route_goal)])
				if w == 60:
					print("    [trace] маршрут бойца0: %s" % str(u0._route))
				if w % 300 == 0:
					var rows: Array = []
					for uu in men:
						var ux := uu as Unit
						rows.append("%.0f/%.0f st%d r%d/%d mt%.0f" % [ux.global_position.x, ux.global_position.z, ux.state, ux._route_i, ux._route.size(), ux.move_target.x])
					print("    [trace] бойцы: %s" % ", ".join(rows))
			path_len[i] = float(path_len[i]) + _xz(c, last_c[i])
			last_c[i] = c
			ext_max[i] = maxf(float(ext_max[i]), _extent(men, true))
			if _split(men, true):
				split_n[i] = int(split_n[i]) + 1
			for u in men:
				var up: Vector3 = (u as Unit).global_position
				if _in_bld(up):
					inside += 1
				# Ближайший подход к фундаменту: HUG_PROBE − глубина с зазором HUG_PROBE
				var dp: float = GameManager.bld_depth(up.x, up.z, HUG_PROBE)
				if dp > 0.0:
					hug[i] = minf(float(hug[i]), HUG_PROBE - dp)
			# Прибытие: центр у цели и все бойцы не дальше 7 м от центра
			var near := true
			for u in men:
				if _xz((u as Unit).global_position, c) > 7.0:
					near = false
			if _xz(c, goals[i]) < 4.0 and near:
				done += 1
				if int(arrive_frame[i]) < 0:
					arrive_frame[i] = w
		if inside > 0:
			inside_frames += 1
			inside_worst = maxi(inside_worst, inside)
		if done == n_sq:
			arrived_all = true
			break
	if _trace >= 0:
		_Opt.cmd_meter = false
		print("    [trace] источники command_move по отрядам: %s" % str(_Opt.cmd_sid_report()))
		print("    [trace] источники command_move: %s" % str(_Opt.cmd_report()))
	# Итог по отрядам
	var worst_detour := 0.0
	var worst_ext := 0.0
	var splits := 0
	var stragglers := 0
	var final_ext_bad := 0
	for i in range(n_sq):
		var men: Array = _alive(squads[i][1])
		var straight: float = _xz(goals[i], starts[i])
		var ratio: float = float(path_len[i]) / maxf(straight, 1.0)
		worst_detour = maxf(worst_detour, ratio)
		worst_ext = maxf(worst_ext, float(ext_max[i]) - float(ext0[i]))
		splits += int(split_n[i])
		var c: Vector3 = _centre(men)
		for u in men:
			if _xz((u as Unit).global_position, c) > 7.0:
				stragglers += 1
		var ext_now: float = _extent(men, true)
		if ext_now > float(ext0[i]) + 2.5:
			final_ext_bad += 1
		print("    отряд %d (%s): крюк ×%.2f, поперечник %.1f → макс %.1f → в конце %.1f, проб с расщеплением %d, ближе всего к стене %.1f м, пришёл на %.1f с"
			% [i + 1, String(squads[i][1][0].stat_id), ratio, float(ext0[i]), float(ext_max[i]), ext_now, int(split_n[i]),
			float(hug[i]), float(int(arrive_frame[i])) / 60.0 if int(arrive_frame[i]) >= 0 else -1.0])
	verdict("C-%s все 8 отрядов дошли за %.0f с (за %.1f с)" % [tag, float(bound) / 60.0, float(w) / 60.0], arrived_all)
	verdict("C-%s отставших (дальше 7 м от центра отряда) нет" % tag, stragglers == 0, "отставших %d" % stragglers)
	verdict("C-%s ни одно тело не входило в фундамент" % tag, inside_frames == 0,
		"проб с телом внутри %d, худшая %d тел" % [inside_frames, inside_worst])
	verdict("C-%s ни один отряд не расщепился на две группы по разные стороны здания" % tag, splits == 0,
		"проб с расщеплением %d" % splits)
	verdict("C-%s поперечник отряда после прохода восстанавливается (в конце не шире исходного + 2.5 м)" % tag,
		final_ext_bad == 0, "отрядов шире %d" % final_ext_bad)
	verdict("C-%s крюк центра отряда не длиннее ×%.2f прямой" % [tag, DETOUR_MAX], worst_detour <= DETOUR_MAX,
		"худший ×%.2f" % worst_detour)
	# Отряд 3 идёт по оси крепости: обходит её ВПЛОТНУЮ, а не крюком
	verdict("C-%s отряд по оси крепости огибает её по краю фундамента (ближе %.1f м)" % [tag, HUG_MAX],
		float(hug[2]) <= HUG_MAX, "ближайший подход %.1f м" % float(hug[2]))
