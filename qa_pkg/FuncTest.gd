extends Node

## QA п.1.3 (сон зданий), п.1.4 (пни), п.4 (здания не крутятся за камерой)

var main: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	# Ставим замок игрока ровно так, как это делает игрок кликом мыши
	var vp := get_viewport().get_visible_rect().size
	main._try_place_castle(vp * 0.5)
	for _i in range(10):
		await get_tree().process_frame
	# Достраиваем игроку весь набор типов зданий — иначе на карте только два
	# замка и проверять сон/спрайты почти не на чем
	_add_building(Barracks.new(), Vector3(-30, 0, -30))
	_add_building(Smithy.new(),   Vector3(-34, 0, -30))
	_add_building(Mine.new(),     Vector3(-38, 0, -30))
	var CS0 := load("res://scripts/ConstructionSite.gd")
	var s0: Building = CS0.new()
	s0.faction = Constants.FACTION_PLAYER
	s0.target_id = "mine"
	s0.target_name = "Рудник"
	s0.build_time = 999.0
	s0.build_size = Vector3(3, 2, 3)
	_add_building(s0, Vector3(-42, 0, -30))
	for _i in range(10):
		await get_tree().process_frame
	await _t13()
	await _t14()
	await _t41()
	_t42()
	await _t43()
	print("\n=== FUNC DONE ===")
	get_tree().quit()

func _add_building(b: Building, pos: Vector3) -> void:
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = pos

func _cls(b: Node) -> String:
	if b is Castle:   return "Castle"
	if b is Barracks: return "Barracks"
	if b is Smithy:   return "Smithy"
	if b is Mine:     return "Mine"
	if b.is_in_group("construction_sites"): return "ConstructionSite"
	return "Building"

# ── 1.3 здания без заказов спят ──────────────────────────────────────────────
func _t13() -> void:
	print("\n===== 1.3 СОН _process У ЗДАНИЙ =====")
	var sleeping := 0
	var awake := 0
	var fails: Array = []
	var idle_target: Building = null
	for n in get_tree().get_nodes_in_group("all_buildings"):
		var b := n as Building
		var proc := b.is_processing()
		print("  %-22s фракц=%d класс=%-10s очередь=%d  is_processing=%s"
			% [b.display_name, b.faction, _cls(b), b.production_queue.size(), str(proc)])
		if proc: awake += 1
		else:    sleeping += 1
		# Правило: заказов нет и _needs_tick() = false -> обязан спать
		var need: bool = b.call("_needs_tick")
		var must_tick: bool = need or not b.production_queue.is_empty()
		if proc != must_tick:
			fails.append("%s(фракц %d): is_processing=%s, а ожидалось %s"
				% [b.display_name, b.faction, str(proc), str(must_tick)])
		if not must_tick and idle_target == null and b.faction == Constants.FACTION_ENEMY:
			idle_target = b
	print("спит: %d, тикает: %d" % [sleeping, awake])

	# Отдельно: замок ИГРОКА тикает всегда, замок ИИ без заказов спит
	var pc: Building = null
	var ec: Building = null
	for n in get_tree().get_nodes_in_group("all_buildings"):
		if n is Castle:
			if n.faction == Constants.FACTION_PLAYER: pc = n
			else: ec = n
	print("замок ИГРОКА: is_processing=%s (ждём true — пассивное золото)"
		% (str(pc.is_processing()) if pc else "НЕТ ЗАМКА"))
	print("замок ИИ:     is_processing=%s (ждём false — заказов нет)"
		% (str(ec.is_processing()) if ec else "НЕТ ЗАМКА"))

	# Пробуждение по заказу + реальный выход отряда
	if idle_target != null:
		var before := get_tree().get_nodes_in_group("all_units").size()
		ResourceManager.add_resource(idle_target.faction, Constants.RESOURCE_WOOD, 1000.0)
		ResourceManager.add_resource(idle_target.faction, Constants.RESOURCE_GOLD, 1000.0)
		idle_target.squad_size = 5
		idle_target.squad_cols = 5
		var ok: bool = idle_target.queue_unit("spearman", {Constants.RESOURCE_WOOD: 10.0}, 1.0)
		print("заказ у «%s»: spend=%s, is_processing сразу после queue_unit=%s (ждём true)"
			% [idle_target.display_name, str(ok), str(idle_target.is_processing())])
		for _i in range(240):
			await get_tree().process_frame
		var after := get_tree().get_nodes_in_group("all_units").size()
		print("юнитов было %d, стало %d (+%d, заказывали 5) — отряд реально вышел: %s"
			% [before, after, after - before, "ДА" if after - before >= 5 else "НЕТ"])
		print("после выхода отряда is_processing=%s (ждём false — снова уснул)"
			% str(idle_target.is_processing()))
	if fails.is_empty():
		print("ВЕРДИКТ 1.3: PASS")
	else:
		print("ВЕРДИКТ 1.3: FAIL -> %s" % str(fails))

# ── 1.4 пни ──────────────────────────────────────────────────────────────────
func _t14() -> void:
	print("\n===== 1.4 ПЕНЬ ПОСЛЕ РУБКИ =====")
	var tree_node: ResourceNode = null
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn.resource_type == Constants.RESOURCE_WOOD:
			tree_node = rn
			break
	if tree_node == null:
		print("деревьев на карте нет — тест невозможен, FAIL")
		return
	var before_cnt := get_tree().get_nodes_in_group("resource_nodes").size()
	var pos := tree_node.global_position
	print("рубим дерево в (%.1f, %.1f), ресурсных узлов до рубки: %d" % [pos.x, pos.z, before_cnt])
	tree_node.extract(tree_node.remaining)
	await get_tree().process_frame

	var alive: bool = is_instance_valid(tree_node)
	var stump: MeshInstance3D = null
	if alive:
		stump = tree_node.get("_stump_node") as MeshInstance3D
	print("  узел жив:                 %s (ждём true)"  % str(alive))
	print("  визуал пня есть:          %s (ждём true)"  % str(stump != null and is_instance_valid(stump)))
	print("  is_in_group(resource_nodes): %s (ждём false)" % str(tree_node.is_in_group("resource_nodes")))
	print("  is_processing():          %s (ждём false)" % str(tree_node.is_processing()))
	print("  is_physics_processing():  %s (ждём false)" % str(tree_node.is_physics_processing()))
	print("  collision_layer:          %d (ждём 0)"     % tree_node.collision_layer)
	print("  remaining:                %.1f"            % tree_node.remaining)
	print("  ресурсных узлов после:    %d (было %d)"    % [get_tree().get_nodes_in_group("resource_nodes").size(), before_cnt])
	# find_nearest_resource от самой точки пня не должен вернуть пень
	var found := GameManager.find_nearest_resource(pos, Constants.RESOURCE_WOOD)
	var same: bool = (found == tree_node)
	print("  find_nearest_resource из точки пня вернул: %s -> это пень? %s (ждём НЕТ)"
		% [("null" if found == null else "дерево в (%.1f,%.1f) на расстоянии %.2f м"
			% [found.global_position.x, found.global_position.z, pos.distance_to(found.global_position)]),
		   "ДА" if same else "НЕТ"])
	var ok: bool = alive and stump != null and not tree_node.is_in_group("resource_nodes") \
		and not tree_node.is_processing() and tree_node.collision_layer == 0 and not same
	print("ВЕРДИКТ 1.4: %s" % ("PASS" if ok else "FAIL"))

# ── 4.1 у всех построек world_fixed = 1, rotation = 0 ────────────────────────
func _t41() -> void:
	print("\n===== 4.1 BUILDINGSPRITE У ВСЕХ ПОСТРОЕК =====")
	await _check_all_buildings("на карте")
	# Здание, построенное через ConstructionSite
	var CS := load("res://scripts/ConstructionSite.gd")
	var site: Building = CS.new()
	site.faction     = Constants.FACTION_PLAYER
	site.target_id   = "barracks"
	site.target_name = "Бараки"
	site.build_time  = 0.5
	site.build_size  = Vector3(3.5, 2.2, 3.5)
	main.world_add(site)
	site.global_position = Vector3(40, 0, 40)
	await get_tree().process_frame
	var fake := Node3D.new()
	main.add_child(fake)
	site.add_builder(fake)
	var guard := 0
	while is_instance_valid(site) and guard < 300:
		await get_tree().process_frame
		guard += 1
	await get_tree().process_frame
	print("  фундамент достроен за %d кадров, теперь проверяем полученное здание:" % guard)
	await _check_all_buildings("после ConstructionSite")
	fake.queue_free()

func _check_all_buildings(tag: String) -> void:
	var bad: Array = []
	var n_ok := 0
	var n_nosprite := 0
	for n in get_tree().get_nodes_in_group("all_buildings"):
		var b := n as Building
		var spr := b.get_node_or_null("BuildingSprite") as MeshInstance3D
		if spr == null:
			n_nosprite += 1
			print("  %-22s [%s] BuildingSprite ОТСУТСТВУЕТ" % [b.display_name, _cls(b)])
			continue
		var m := (spr.mesh as QuadMesh).material as ShaderMaterial
		var wf_v = m.get_shader_parameter("world_fixed")
		var wf: float = 0.0 if wf_v == null else float(wf_v)
		var rot := spr.rotation
		var ok: bool = absf(wf - 1.0) < 0.001 and rot.length() < 1e-6
		if ok: n_ok += 1
		else:  bad.append("%s: world_fixed=%.2f rotation=%s" % [b.display_name, wf, str(rot)])
		print("  %-22s [%-16s] world_fixed=%.1f rotation=(%.3f,%.3f,%.3f) %s"
			% [b.display_name, _cls(b), wf, rot.x, rot.y, rot.z, "OK" if ok else "FAIL"])
	print("  итог (%s): со спрайтом и OK: %d, без BuildingSprite: %d, плохих: %d %s"
		% [tag, n_ok, n_nosprite, bad.size(), str(bad) if not bad.is_empty() else ""])

# ── 4.2 контроль регрессии: деревья и кусты доворачиваются ───────────────────
func _t42() -> void:
	print("\n===== 4.2 КОНТРОЛЬ: ДЕРЕВЬЯ И КУСТЫ =====")
	var tree_stats: Dictionary = {}
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn.resource_type != Constants.RESOURCE_WOOD:
			continue
		var m := _find_shader_mat(rn)
		if m == null:
			continue
		var v = m.get_shader_parameter("world_fixed")
		var wf: float = 0.0 if v == null else float(v)
		tree_stats[wf] = int(tree_stats.get(wf, 0)) + 1
	print("  деревья: распределение world_fixed = %s (ждём {0.0: N})" % str(tree_stats))

	# Кусты — декорации в World, не в группах. Ищем по имени узла
	var bush_stats: Dictionary = {}
	var bushes := 0
	_scan_bushes(main, bush_stats)
	for k in bush_stats:
		bushes += int(bush_stats[k])
	print("  кусты/декор (cyl_billboard, не здания): найдено %d, распределение world_fixed = %s"
		% [bushes, str(bush_stats)])
	var ok: bool = (tree_stats.size() == 1 and tree_stats.has(0.0)) \
		and (bush_stats.is_empty() or (bush_stats.size() == 1 and bush_stats.has(0.0)))
	print("ВЕРДИКТ 4.2: %s" % ("PASS" if ok else "FAIL"))

func _scan_bushes(root: Node, acc: Dictionary) -> void:
	for c in root.get_children():
		if c is Building:
			continue          # здания считаем в 4.1
		var mi := c as MeshInstance3D
		if mi != null and mi.name != "BuildingSprite" and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var m := mi.mesh.surface_get_material(0) as ShaderMaterial
			if m != null and m.shader != null and String(m.shader.resource_path).ends_with("cyl_billboard.gdshader"):
				var v = m.get_shader_parameter("world_fixed")
				var wf: float = 0.0 if v == null else float(v)
				acc[wf] = int(acc.get(wf, 0)) + 1
		_scan_bushes(c, acc)

func _find_shader_mat(root: Node) -> ShaderMaterial:
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var m := mi.mesh.surface_get_material(0) as ShaderMaterial
			if m != null:
				return m
		var deep := _find_shader_mat(c)
		if deep != null:
			return deep
	return null

# ── 4.3 поворот камеры не меняет ориентацию спрайта здания ───────────────────
func _t43() -> void:
	print("\n===== 4.3 ОРБИТА КАМЕРЫ =====")
	var cam: RTSCamera = null
	for c in main.get_children():
		if c.name == "CameraPivot":
			for cc in c.get_children():
				if cc is RTSCamera:
					cam = cc
	if cam == null:
		print("камера не найдена — FAIL")
		return
	var spr: MeshInstance3D = null
	var owner_b: Building = null
	for n in get_tree().get_nodes_in_group("all_buildings"):
		var b := n as Building
		var s := b.get_node_or_null("BuildingSprite") as MeshInstance3D
		if s != null:
			spr = s; owner_b = b
			break
	if spr == null:
		print("построек со спрайтом нет — FAIL")
		return
	print("контрольная постройка: %s в (%.1f, %.1f)"
		% [owner_b.display_name, owner_b.global_position.x, owner_b.global_position.z])

	var base_basis := spr.global_transform.basis
	var yaws: Array[float] = [0.0, 45.0, 90.0, 180.0, 270.0]
	var pitches: Array[float] = [25.0, 55.0, 80.0]
	var max_dev := 0.0
	var normal := Vector3(0, 0, 1)   # QuadMesh смотрит в +Z; узел не повёрнут
	print("  yaw   pitch | базис спрайта совпал с исходным | |cos| между взглядом камеры и нормалью спрайта")
	for p in pitches:
		cam._orbit_pitch = p
		for y in yaws:
			cam._orbit_yaw = y
			cam._update_position()
			await get_tree().process_frame
			var b2 := spr.global_transform.basis
			var dev: float = (b2.x - base_basis.x).length() + (b2.y - base_basis.y).length() + (b2.z - base_basis.z).length()
			max_dev = maxf(max_dev, dev)
			var fwd := -cam.global_transform.basis.z
			var facing: float = absf(fwd.dot(normal))
			var edge := "  <-- ПОЧТИ С РЕБРА" if facing < 0.25 else ""
			print("  %5.0f %5.0f | откл=%.9f | |cos|=%.3f (видимая ширина %.0f%% от полной)%s"
				% [y, p, dev, facing, facing * 100.0, edge])
	print("максимальное отклонение базиса BuildingSprite за всю орбиту: %.9f (ждём 0)" % max_dev)
	print("ВЕРДИКТ 4.3: %s" % ("PASS" if max_dev < 1e-6 else "FAIL"))
