extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_building_block — ФУНДАМЕНТЫ НЕПРОХОДИМЫ, КРЫША СОРТИРУЕТСЯ ПО
## ПОДНОЖИЮ (ТЗ 19.09.2026 «коллизии зданий и Y-sort тролля»)
## ═══════════════════════════════════════════════════════════════════════════
##   A. реестр: крепость, башня, хижина, пень — в реестре; загон — нет; круги
##      лежат внутри рисунка, ворота / строитель / кольцо подхода — снаружи;
##   B. отряд, посланный сквозь крепость, обходит её: ни одного тела внутри
##      фундамента за весь ход, отряд доходит;
##   C. боец, поставленный внутрь, выходит сам;
##   D. сетка навигации: ячейки построек, прямая через крепость упирается,
##      маршрут ядра идёт в обход;
##   E. гарнизон башни и стройка живы (ворота и точка строителя снаружи);
##   F. Y-sort: спрайт крыши сортируется по подножию башни — тролль перед
##      башней ближе к камере, чем крыша, позади — дальше;
##   G. снесённая постройка снимает фундамент, руина не держит.
## Запуск: godot --headless --path . res://qa_building_block/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _TowerS := preload("res://scripts/Tower.gd")
const _HutS := preload("res://scripts/goblin/GoblinHut.gd")
const _PenS := preload("res://scripts/SheepPen.gd")
const _LairS := preload("res://scripts/goblin/TrollLair.gd")
const _SiteS := preload("res://scripts/ConstructionSite.gd")
const F := Constants.FACTION_PLAYER
## = mm_unit_sprite depth_lift: боец приподнят к камере на столько
const UNIT_DEPTH_LIFT := 0.35

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
	print("\n═════ ИТОГ qa_building_block: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x + float(i % cols) * 0.7 - float(cols - 1) * 0.35, 0.0,
			at.z + float(i / cols) * 0.9))
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

## Ровная сухая площадка без скал в поле карты
func _flat_spot(base: Vector3, span: float) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-4, 5):
		for iz in range(-4, 5):
			var p := Vector3(base.x + float(ix) * span, 0.0, base.z + float(iz) * span)
			var bad := false
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(14.0, 0.0, 0.0), Vector3(-14.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 22.0), Vector3(0.0, 0.0, -22.0)]:
				var q: Vector3 = p + d
				if GameManager.is_water(q.x, q.z) or GameManager.is_cliff(q.x, q.z):
					bad = true
				h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
			if bad:
				continue
			if h < best_h:
				best_h = h
				best = p
	print("  площадка стенда: %s (перепад %.2f м)" % [str(best), best_h])
	return best

## Глубина точки по камере партии: чем больше, тем дальше от объектива
func _depth(cam: Camera3D, p: Vector3) -> float:
	return (p - cam.global_position).dot(-cam.global_transform.basis.z)

func _inside(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and (u as Unit).garrisoned:
			n += 1
	return n

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

## Глубже ли точка внутри фундамента (тело 0 — сама точка)
func _in_bld(p: Vector3) -> bool:
	return GameManager.bld_depth(p.x, p.z, 0.0) > 0.0

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
	# Стартовые бойцы всех сторон — вон (тролль у пня, гноллы, орда)
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	# Границы мира ВКЛЮЧЕНЫ намеренно: фундаменты — правило партии, как вода
	var base: Vector3 = _flat_spot(Vector3(-120.0, 0.0, -50.0), 9.0)
	_clear_trees(base, 40.0)
	await pframes(2)
	var n_before: int = GameManager.obstacle_count()

	print("\n═════ A. РЕЕСТР ФУНДАМЕНТОВ ═════")
	var keep: Castle = Castle.new()
	_place(keep, base)
	var tower: Building = _TowerS.new()
	_place(tower, base + Vector3(16.0, 0.0, 0.0))
	var hut: Building = _HutS.new()
	_place(hut, base + Vector3(-16.0, 0.0, 0.0), Constants.FACTION_GOBLIN)
	var pen: Building = _PenS.new()
	_place(pen, base + Vector3(0.0, 0.0, -20.0))
	var lair: Building = _LairS.new()
	_place(lair, base + Vector3(-16.0, 0.0, -22.0), Constants.FACTION_GOBLIN)
	await pframes(6)
	# Пень выпускает стражу с рождения — вон
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction == Constants.FACTION_GOBLIN:
			(n as Unit).take_damage(1.0e12)
	await pframes(2)
	var n_now: int = GameManager.obstacle_count() - n_before
	verdict("A1 в реестре четыре постройки (крепость, башня, хижина, пень), загон — нет",
		n_now == 4 and not pen._obstacle_on and keep._obstacle_on and tower._obstacle_on
		and hut._obstacle_on and lair._obstacle_on, "добавилось %d, загон %s" % [n_now, str(pen._obstacle_on)])
	var cc: PackedFloat32Array = keep.block_circles()
	var n_c: int = cc.size() / 3
	var front_ok := true
	var width_ok := true
	var r_min := 1e9
	for k in range(n_c):
		var x: float = cc[k * 3] - keep.global_position.x - keep._draw_cx
		var z: float = cc[k * 3 + 1] - keep.global_position.z
		var r: float = cc[k * 3 + 2]
		r_min = minf(r_min, r)
		if z + r > keep.BLOCK_FRONT + 0.01:
			front_ok = false
		if absf(x) + r > keep.ring_radius() + 0.01:
			width_ok = false
	verdict("A2 круги крепости: %d шт., передняя грань не дальше BLOCK_FRONT, ширина в пределах рисунка" % n_c,
		n_c >= 2 and front_ok and width_ok and r_min >= 0.4, "r_min %.2f" % r_min)
	var gate: Vector3 = keep._gate_position()
	verdict("A3 ворота крепости снаружи фундамента (с зазором тела)",
		GameManager.bld_depth(gate.x, gate.z, keep.BLOCK_FRONT) <= 0.0,
		"ворота z %.2f от центра" % (gate.z - keep.global_position.z))
	var wp: Vector3 = keep.work_position(keep.global_position + Vector3(1.0, 0.0, 8.0))
	verdict("A4 точка строителя перед стеной снаружи фундамента",
		GameManager.bld_depth(wp.x, wp.z, Unit.BLD_CLEAR) <= 0.0,
		"z %.2f" % (wp.z - keep.global_position.z))
	# Кольцо подхода атакующих: ring_radius + длина руки — снаружи по всему кругу
	var ring_ok := true
	for a in range(12):
		var ang: float = TAU * float(a) / 12.0
		var q: Vector3 = keep.ring_center() + Vector3(cos(ang), 0.0, sin(ang)) * (keep.ring_radius() + 1.2)
		if GameManager.bld_depth(q.x, q.z, 0.25) > 0.0:
			ring_ok = false
	verdict("A5 кольцо подхода атакующих (ring_radius + рука) снаружи фундамента", ring_ok)
	var lc: PackedFloat32Array = lair.block_circles()
	verdict("A6 пень — один ствол радиусом меньше GNOLL_HIDE_RANGE", lc.size() == 3
		and lc[2] + 0.25 < 4.5, "r %.2f" % (lc[2] if lc.size() == 3 else -1.0))
	verdict("A7 хижина орды в реестре с рисунком (круг у стены, не коробка)", hut._obstacle_on and hut._draw_half_w > 0.0)

	print("\n═════ B. ОТРЯД СКВОЗЬ КРЕПОСТЬ — ОБХОД ═════")
	var start: Vector3 = base + Vector3(0.0, 0.0, 14.0)
	var goal: Vector3 = base + Vector3(0.0, 0.0, -14.0)
	var s1: Array = _squad("spearman", F, start, 24)
	await pframes(10)
	for u in s1[1]:
		(u as Unit).command_move(goal, false, Vector3.ZERO, false, true)
	var worst_pen := 0.0
	var worst_frames := 0
	var arrived := 0
	var w := 0
	while w < 60 * 45:
		await get_tree().physics_frame
		w += 1
		var pen_now := 0.0
		for u in _alive(s1[1]):
			pen_now = maxf(pen_now, GameManager.bld_depth((u as Unit).global_position.x, (u as Unit).global_position.z, 0.0))
		if pen_now > 0.0:
			worst_frames += 1
		worst_pen = maxf(worst_pen, pen_now)
		arrived = 0
		for u in _alive(s1[1]):
			if _xz((u as Unit).global_position, goal) < 6.0:
				arrived += 1
		if arrived >= 22:
			break
	verdict("B1 ни одно тело не входило в фундамент крепости за весь ход",
		worst_pen <= 0.0, "худшая глубина %.2f м, кадров с телом внутри %d" % [worst_pen, worst_frames])
	verdict("B2 отряд дошёл за крепость (обход, не сквозь)", arrived >= 22,
		"дошли %d из 24 за %d физкадров" % [arrived, w])

	print("\n═════ C. СТОЯЩИЙ ВНУТРИ ВЫХОДИТ ═════")
	var inside_u: Unit = _spawn("spearman", F, keep.global_position + Vector3(0.0, 0.0, -1.5))
	await pframes(2)
	var was_in: bool = _in_bld(inside_u.global_position)
	inside_u.command_move(keep.global_position + Vector3(0.0, 0.0, -12.0), false, Vector3.ZERO, false, true)
	var out_at := -1
	for i in range(60 * 8):
		await get_tree().physics_frame
		if not _in_bld(inside_u.global_position):
			out_at = i
			break
	verdict("C1 боец, поставленный внутрь фундамента, выходит наружу", was_in and out_at >= 0,
		"внутри был %s, вышел за %d физкадров" % [str(was_in), out_at])

	print("\n═════ D. СЕТКА НАВИГАЦИИ ═════")
	verdict("D1 ячейки построек в сетке навигации есть", GameManager.army.nav_bld_cells() > 0,
		"ячеек %d" % GameManager.army.nav_bld_cells())
	var blocked: bool = GameManager.army.nav_line_blocked(start.x, start.z, goal.x, goal.z, 0.7)
	verdict("D2 прямая сквозь крепость упирается", blocked)
	var route: PackedVector3Array = GameManager.nav_route(start, goal, 1.5)
	var route_clear := true
	for p in route:
		if _in_bld(p):
			route_clear = false
	verdict("D3 маршрут ядра идёт в обход крепости", route.size() >= 1 and route_clear,
		"точек %d" % route.size())

	print("\n═════ E. ГАРНИЗОН И СТРОЙКА ЖИВЫ ═════")
	var s2: Array = _squad("archer", F, base + Vector3(16.0, 0.0, 12.0), 30)
	await pframes(10)
	tower.request_garrison(int(s2[0]))
	w = 0
	while w < 60 * 40:
		await get_tree().physics_frame
		w += 1
		if _inside(s2[1]) == 30:
			break
	verdict("E1 отряд лучников зашёл в башню через ворота (фундамент не мешает)",
		_inside(s2[1]) == 30, "внутри %d за %d физкадров" % [_inside(s2[1]), w])
	var site: Building = _SiteS.new()
	site.target_id = "house"
	site.target_name = "Дом"
	site.build_size = _UCfg.building_size("house")
	site.build_time = 600.0
	_place(site, base + Vector3(16.0, 0.0, -18.0))
	await pframes(4)
	var wk: Unit = _spawn("worker", F, base + Vector3(16.0, 0.0, -8.0))
	await pframes(2)
	wk.command_build(site)
	var settled := false
	for i in range(60 * 20):
		await get_tree().physics_frame
		if bool(wk.get("_build_settled")):
			settled = true
			break
	verdict("E2 рабочий дошёл до площадки и встал на стройку (площадка в реестре: %s)" % str(site._obstacle_on),
		settled and not _in_bld(wk.global_position),
		"встал %s, внутри %s" % [str(settled), str(_in_bld(wk.global_position))])

	print("\n═════ F. Y-SORT: КРЫША ПО ПОДНОЖИЮ, ТРОЛЛЬ ПЕРЕД БАШНЕЙ ПОВЕРХ ═════")
	await frames(3)
	var cam: Camera3D = main.selection_manager.camera
	main._camera.pan_to(tower.global_position)
	main._camera._update_position()
	await frames(2)
	var spr: MeshInstance3D = tower._roof.first_sprite()
	var mat: ShaderMaterial = null
	if spr != null and spr.mesh is QuadMesh:
		mat = (spr.mesh as QuadMesh).material as ShaderMaterial
	var anchored: bool = mat != null and float(mat.get_shader_parameter("depth_anchor_on")) > 0.5
	var anchor: Vector3 = Vector3.ZERO
	var push: float = 0.0
	if mat != null:
		anchor = mat.get_shader_parameter("depth_anchor")
		push = float(mat.get_shader_parameter("depth_push"))
	verdict("F1 спрайт крыши сортируется по подножию башни (якорь = точка постройки, сдвиг к камере)",
		anchored and _xz(anchor, tower.global_position + Vector3(tower._draw_cx, 0.0, 0.0)) < 0.01
		and push < 0.0 and push >= -0.5, "якорь %s, сдвиг %.2f" % [str(anchor), push])
	# Глубина крыши: якорь минус сдвиг к камере; тролль: ноги минус depth_lift
	var d_roof: float = _depth(cam, anchor) + push
	var t_front: Unit = _spawn("troll", Constants.FACTION_GOBLIN, tower.global_position + Vector3(0.0, 0.0, 3.0))
	var t_back: Unit = _spawn("troll", Constants.FACTION_GOBLIN, tower.global_position + Vector3(0.0, 0.0, -3.0))
	t_front.set_tick(false)
	t_back.set_tick(false)
	await pframes(2)
	var d_front: float = _depth(cam, t_front.global_position) - UNIT_DEPTH_LIFT
	var d_back: float = _depth(cam, t_back.global_position) - UNIT_DEPTH_LIFT
	verdict("F2 тролль в 3 м перед башней ближе к камере, чем спрайты крыши — рисуется поверх",
		d_front < d_roof - 0.05, "тролль %.2f, крыша %.2f" % [d_front, d_roof])
	verdict("F3 тролль в 3 м позади башни дальше крыши — крыша поверх него",
		d_back > d_roof + 0.05, "тролль %.2f, крыша %.2f" % [d_back, d_roof])
	# Прежняя точка (ноги на крыше) — была БЛИЖЕ тролля впереди: ловушка ушла
	var feet_w: Vector3 = tower.to_global(tower._roof.slot_local(0))
	var d_old: float = _depth(cam, feet_w)
	verdict("F4 прежняя точка сортировки (ноги на крыше) лежала ближе тролля впереди — ошибка была геометрической",
		d_old < d_front, "старая %.2f, тролль %.2f" % [d_old, d_front])
	# Ряды крыши между собой: задний ряд не ближе переднего
	var spr_n: int = tower._roof._sprites.size()
	var order_ok := true
	if spr_n >= 2:
		var m0 := ((tower._roof._sprites[0] as MeshInstance3D).mesh as QuadMesh).material as ShaderMaterial
		var p0: float = float(m0.get_shader_parameter("depth_push"))
		for i in range(1, spr_n):
			var mi := ((tower._roof._sprites[i] as MeshInstance3D).mesh as QuadMesh).material as ShaderMaterial
			if float(mi.get_shader_parameter("depth_push")) > 0.0:
				order_ok = false
		verdict("F5 у всех %d спрайтов крыши сдвиг к камере (крыша поверх стены), передний %.2f" % [spr_n, p0], order_ok)
	t_front.take_damage(1.0e12)
	t_back.take_damage(1.0e12)

	print("\n═════ G. СНОС ═════")
	var cnt_before: int = GameManager.obstacle_count()
	hut.take_damage(1.0e12)
	await pframes(4)
	verdict("G1 снесённая хижина снята с реестра, руина не держит",
		GameManager.obstacle_count() == cnt_before - 1 and not _in_bld(hut.global_position if is_instance_valid(hut) else base + Vector3(-16.0, 0.0, 0.0)),
		"было %d, стало %d" % [cnt_before, GameManager.obstacle_count()])
	_finish()
