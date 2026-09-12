extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД СПРИНТА 19 (письмо 9): фантом-спрайт постройки, бригада ждёт крепость,
## строители у нарисованного фундамента, ворота ~3 м, точка сбора приоритетом
## и маркером, выход прямоугольником. Клавиши 1/2/3 — qa_formation_keys.
## ═══════════════════════════════════════════════════════════════════════════
##   A — фантом постройки с картинкой (замок, бараки) — полупрозрачный спрайт
##       самого здания; без картинки (рудник) — прежняя коробка;
##   B — партия без крепости: рабочие стоят, а не идут на ресурсы; после
##       достройки крепости — расходятся по ресурсам;
##   C — строители у стройплощадки стоят у НИЗА РИСУНКА (со стороны камеры),
##       а не у стены коробки габарита;
##   D — вынос ворот не дальше GATE_MAX_DEPTH + зазор у любой постройки;
##   E — при выделенном здании ПКМ ставит точку сбора даже поверх бойца;
##       маркер точки сбора виден у выделенного здания и без назначения;
##   F — отряд с диагональной точкой сбора выходит прямоугольником по осям
##       фасада, а не ромбом, повёрнутым на курс.
## Запуск: godot --headless --path . res://qa_sprint19/Test.tscn

const _CSite := preload("res://scripts/ConstructionSite.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_sprint19: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _workers() -> Array:
	var out: Array = []
	for u in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_PLAYER)):
		if is_instance_valid(u) and u is Worker and not (u as Unit).is_dead():
			out.append(u)
	return out

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(3)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	# Настоящий старт партии: пять рабочих, крепости нет
	main.start_game()
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(30)

	print("\n═════ B. БРИГАДА ЖДЁТ КРЕПОСТЬ ═════")
	var ws: Array = _workers()
	var idle := 0
	for w in ws:
		if (w as Unit).state == Unit.State.IDLE and (w as Worker).gather_target == null:
			idle += 1
	verdict("B1 без крепости рабочие стоят на месте (%d из %d в покое, без цели добычи)" % [idle, ws.size()],
		ws.size() > 0 and idle == ws.size())
	var origin: Vector3 = (ws[0] as Node3D).global_position if not ws.is_empty() else Vector3.ZERO
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 500000.0)

	print("\n═════ A. ФАНТОМ — СПРАЙТ ПОСТРОЙКИ ═════")
	main.enter_building_placement({}, _UCfg.building_size("castle"), func(_p): pass, "Замок", "castle")
	await frames(2)
	var g = main.get("_ghost")
	verdict("A1 фантом замка — картинка самого замка (узел GhostSprite)",
		g != null and is_instance_valid(g) and g.has_node("GhostSprite"))
	var sp = g.get_node_or_null("GhostSprite") if g != null and is_instance_valid(g) else null
	var qm: QuadMesh = (sp as MeshInstance3D).mesh if sp != null else null
	verdict("A2 квад фантома в размер настоящей постройки (%.1f м ширины)" % (qm.size.x if qm != null else -1.0),
		qm != null and qm.size.x > 4.0)
	var mats: Array = main.get("_ghost_mats")
	verdict("A3 материалы фантома перекрашиваемы (красный на запрете)", mats != null and mats.size() >= 2)
	main._cancel_placement()
	await frames(2)
	main.enter_building_placement({}, _UCfg.building_size("mine"), func(_p): pass, "Рудник", "mine")
	await frames(2)
	g = main.get("_ghost")
	var has_sprite: bool = g != null and is_instance_valid(g) and g.has_node("GhostSprite")
	verdict("A4 у постройки без картинки (рудник) — прежняя коробка", g != null and not has_sprite)
	main._cancel_placement()
	await frames(2)

	print("\n═════ C. СТРОИТЕЛИ У НАРИСОВАННОГО ФУНДАМЕНТА ═════")
	var spos: Vector3 = origin + Vector3(0.0, 0.0, -16.0)
	spos.y = GameManager.get_terrain_height(spos.x, spos.z)
	var site: Building = _CSite.new()
	site.faction = Constants.FACTION_PLAYER
	site.target_id = "castle"
	site.target_name = "Замок"
	site.build_time = 9999.0
	site.build_size = _UCfg.building_size("castle")
	main.world_add(site)
	site.global_position = spos
	for w in ws:
		(w as Worker).command_build(site)
	await pframes(60 * 20)
	var front := 0
	var worst := 0.0
	var settled := 0
	for w in ws:
		var p: Vector3 = (w as Node3D).global_position
		if bool(w.get("_build_settled")):
			settled += 1
		if p.z - spos.z > 0.0:
			front += 1
			worst = maxf(worst, p.z - spos.z)
	var lim: float = _CSite.FRONT_EDGE + Worker.BUILD_STAND_PAD + Worker.BUILD_ARRIVE_PAD + 0.3
	print("  строителей у стены %d/%d, со стороны камеры %d, худший вынос вперёд %.2f м (коробка %.2f)" % [
		settled, ws.size(), front, worst, site.build_size.z * 0.5])
	verdict("C1 все строители встали на работу", settled == ws.size(), "%d из %d" % [settled, ws.size()])
	verdict("C2 со стороны камеры строитель стоит у низа рисунка (≤ %.2f м), а не у стены коробки (%.2f м)" % [lim, site.build_size.z * 0.5],
		front > 0 and worst <= lim, "худший %.2f м" % worst)
	verdict("C3 стена по рисунку уже коробки: edge_distance(+Z) < габарит/2",
		site.edge_distance(Vector3(0, 0, 1)) < site.build_size.z * 0.5 - 0.5,
		"%.2f против %.2f" % [site.edge_distance(Vector3(0, 0, 1)), site.build_size.z * 0.5])
	site.queue_free()
	await pframes(2)

	print("\n═════ D. ВОРОТА НЕ ДАЛЬШЕ ~3 м ═════")
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = origin + Vector3(30.0, 0.0, 0.0)
	await frames(2)
	var bar: Building = Barracks.new()
	bar.faction = Constants.FACTION_PLAYER
	main.world_add(bar)
	bar.global_position = origin + Vector3(30.0, 0.0, 30.0)
	await frames(2)
	var gd_c: float = castle.gate_depth()
	var gd_b: float = bar.gate_depth()
	verdict("D1 ворота крепости в %.2f м от центра (≤ %.2f)" % [gd_c, Building.GATE_MAX_DEPTH + Building.GATE_CLEARANCE + 0.01],
		gd_c <= Building.GATE_MAX_DEPTH + Building.GATE_CLEARANCE + 0.01)
	verdict("D2 ворота бараков не дальше того же потолка (%.2f м)" % gd_b,
		gd_b <= Building.GATE_MAX_DEPTH + Building.GATE_CLEARANCE + 0.01)
	# Крепость достроена «по-настоящему» — бригада расходится по ресурсам
	main._on_castle_built(castle)
	await pframes(30)
	var busy := 0
	for w in ws:
		if (w as Unit).state != Unit.State.IDLE or (w as Worker).gather_target != null:
			busy += 1
	verdict("B2 после достройки крепости бригада расходится по ресурсам (%d из %d заняты)" % [busy, ws.size()],
		busy >= 3)

	print("\n═════ E. ТОЧКА СБОРА: ПРИОРИТЕТ ПКМ И МАРКЕР ═════")
	var sm = main.selection_manager
	sm.select_units([bar])
	await frames(2)
	var mk = bar.get("_rally_marker")
	verdict("E1 у выделенных бараков маркер точки сбора виден и без назначения",
		mk != null and is_instance_valid(mk) and (mk as Node3D).visible and not bar.has_rally)
	var def_pt: Vector3 = bar.effective_rally_point()
	verdict("E2 маркер стоит на площадке перед воротами (%.1f м от центра)" % _xz(def_pt, bar.global_position),
		mk != null and _xz((mk as Node3D).global_position, def_pt) < 0.05 and _xz(def_pt, bar.global_position) > 1.0)
	# Клик «по бойцу»: точка земли под курсором — ровно там, где стоит свой рабочий
	var blocker: Vector3 = (ws[0] as Node3D).global_position
	var ok_click: bool = sm._rally_click(Vector3(blocker.x, 0.0, blocker.z))
	verdict("E3 при выделенном здании ПКМ поверх бойца всё равно ставит точку сбора",
		ok_click and bar.has_rally and _xz(bar.rally_point, blocker) < 0.05,
		"has_rally=%s, точка %s" % [str(bar.has_rally), str(bar.rally_point)])
	mk = bar.get("_rally_marker")
	verdict("E4 маркер переехал в назначенную точку",
		mk != null and is_instance_valid(mk) and _xz((mk as Node3D).global_position, bar.rally_point) < 0.05)
	sm.select_units([castle, bar])
	var ok2: bool = sm._rally_click(origin + Vector3(5.0, 0.0, 5.0))
	verdict("E5 два выделенных здания получают точку сбора разом", ok2 and castle.has_rally and bar.has_rally)
	sm.select_units([ws[0]])
	verdict("E6 с бойцом в выделении ПКМ — не точка сбора", not sm._rally_click(origin))
	sm.select_units([])

	print("\n═════ F. ВЫХОД — ПРЯМОУГОЛЬНИК ПО ОСЯМ ФАСАДА ═════")
	var ar: Building = load("res://scripts/Archery.gd").new()
	ar.faction = Constants.FACTION_PLAYER
	main.world_add(ar)
	ar.global_position = origin + Vector3(-30.0, 0.0, 30.0)
	await frames(2)
	GameManager.world_bounds_enabled = false
	# Точка сбора по диагонали от ворот
	ar.set_rally_point(ar.global_position + Vector3(28.0, 0.0, 28.0))
	var before: Dictionary = GameManager.squads.duplicate()
	ar.train_from_config("archer")
	var guard := 0
	while guard < 3000 and not (ar.production_queue.is_empty() and ar._pending_spawns.is_empty()):
		ar._production_timer = 99999.0
		await get_tree().physics_frame
		guard += 1
	await pframes(3)
	var sid := -1
	for k in GameManager.squads:
		if not before.has(k) and String(GameManager.squads[k].get("type")) == "archer":
			sid = k
	var men: Array = GameManager.squad_members(sid) if sid > 0 else []
	var exit_dir: Vector3 = ar.spawn_offset
	exit_dir.y = 0.0
	exit_dir = exit_dir.normalized()
	var side := Vector3(-exit_dir.z, 0.0, exit_dir.x)
	# Точки приказа — по осям фасада: столбцов не больше, чем колонн в строю
	var cols_x: Array = []
	var rows_z: Array = []
	for m in men:
		var mt: Vector3 = (m as Unit).move_target
		var cx: float = mt.dot(side)
		var cz: float = mt.dot(exit_dir)
		var fx := false
		for v in cols_x:
			if absf(float(v) - cx) < 0.08: fx = true
		if not fx: cols_x.append(cx)
		var fz := false
		for v in rows_z:
			if absf(float(v) - cz) < 0.08: fz = true
		if not fz: rows_z.append(cz)
	print("  лучников %d, различных колонн по фасаду %d, шеренг %d" % [men.size(), cols_x.size(), rows_z.size()])
	verdict("F1 отряд вышел (30 лучников)", men.size() == 30)
	verdict("F2 места отряда — прямоугольник по осям фасада: колонн %d (≤ 6), шеренг %d (≤ 5)" % [cols_x.size(), rows_z.size()],
		cols_x.size() <= 6 and rows_z.size() <= 5 and cols_x.size() * rows_z.size() >= 30)
	_finish()
