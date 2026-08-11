extends Node

## Собственная проверка пакета: баллистика стрел, ориентация зданий,
## единый фронт формации, групповая стройка, сон _process у зданий.

var main: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_arrow()
	_test_building_orientation()
	_test_building_sleep()
	await _test_formation_facing()
	await _test_group_build()
	print("\n=== SELFTEST DONE ===")
	get_tree().quit()

# ── 1. Стрела: наклон по вектору скорости и втыкание остриём ────────────────
func _test_arrow() -> void:
	print("\n───── СТРЕЛА: НАКЛОН ПО ТРАЕКТОРИИ ─────")
	var ArrowS := load("res://scripts/Arrow.gd")
	var a: Node3D = ArrowS.new()
	var from_pos := Vector3(0, 1.2, 0)
	var aim      := Vector3(12, 0.8, 0)
	a.set("_start_pos", from_pos)
	a.set("_end_pos",   aim)
	a.set("_dist",      from_pos.distance_to(aim))
	a.set("_speed",     7.0)
	a.set("_arc_factor", 0.3)
	a.set("damage", 10.0)
	a.set("faction", Constants.FACTION_PLAYER)
	main.add_child(a)
	a.global_position = from_pos
	await get_tree().process_frame

	var mat: ShaderMaterial = (a.get_node("ArrowSprite") as MeshInstance3D).mesh.material
	var quad: QuadMesh = (a.get_node("ArrowSprite") as MeshInstance3D).mesh
	print("квад стрелы: длина=%.3f м, толщина=%.3f м (длина по локальному X)"
		% [quad.size.x, quad.size.y])

	var samples := [0.0, 0.25, 0.5, 0.75, 1.0]
	for s in samples:
		var t: float = s
		var dir: Vector3 = a.call("_velocity_dir", t)
		print("  t=%.2f: ось=(%.2f, %+.2f, %.2f)  наклон=%+6.1f°"
			% [t, dir.x, dir.y, dir.z, rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))])
	var d0: Vector3 = a.call("_velocity_dir", 0.0)
	var d5: Vector3 = a.call("_velocity_dir", 0.5)
	var d1: Vector3 = a.call("_velocity_dir", 1.0)
	print("взлёт вверх: %s | вершина горизонт: %s | падение вниз: %s"
		% ["ДА" if d0.y > 0.1 else "НЕТ",
		   "ДА" if absf(d5.y) < 0.02 else "НЕТ",
		   "ДА" if d1.y < -0.1 else "НЕТ"])

	# Летим до конца и смотрим воткнувшуюся стрелу
	var guard := 0
	while not bool(a.get("_spent")) and guard < 2000 and is_instance_valid(a):
		await get_tree().process_frame
		guard += 1
	if not is_instance_valid(a):
		print("стрела удалена до втыкания — ОШИБКА")
		return
	var axis: Vector3 = mat.get_shader_parameter("axis")
	var half: float   = quad.size.x * 0.5
	var tip: Vector3  = a.global_position + axis * half
	var tail: Vector3 = a.global_position - axis * half
	print("воткнулась за %d кадров. ось=(%.2f, %+.2f, %.2f)" % [guard, axis.x, axis.y, axis.z])
	print("  остриё y=%+.3f (должно быть НИЖЕ земли 0)" % tip.y)
	print("  оперение y=%+.3f (должно быть ВЫШЕ земли)" % tail.y)
	print("  вердикт: %s" % ("остриём в землю — ОК" if tip.y < 0.0 and tail.y > 0.0 else "ПЛОХО"))
	print("  _process выключен: %s, Area3D снята: %s"
		% [str(not a.is_processing()), str(a.get("_area") == null)])

# ── 2. Здания не крутятся за камерой ────────────────────────────────────────
func _test_building_orientation() -> void:
	print("\n───── ЗДАНИЯ: МИРОВАЯ ОРИЕНТАЦИЯ ─────")
	var checked := 0
	for b in get_tree().get_nodes_in_group("all_buildings"):
		var spr := b.get_node_or_null("BuildingSprite") as MeshInstance3D
		if spr == null:
			continue
		var m := (spr.mesh as QuadMesh).material as ShaderMaterial
		var wf: float = m.get_shader_parameter("world_fixed")
		print("  %-16s world_fixed=%.1f  rotation=%s" % [b.display_name, wf, str(spr.rotation)])
		checked += 1
	print("зданий со спрайтом: %d (world_fixed=1 => к камере не доворачиваются)" % checked)
	# Контроль: деревья ДОЛЖНЫ остаться доворачивающимися
	var tree_wf := -1.0
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if n.resource_type != Constants.RESOURCE_WOOD:
			continue
		var m := _find_shader_mat(n)
		if m != null:
			var v = m.get_shader_parameter("world_fixed")
			tree_wf = 0.0 if v == null else float(v)
			break
	print("контроль: у дерева world_fixed=%.1f (должен остаться 0 — лес доворачивается)" % tree_wf)

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

# ── 3. Здания без заказов не тикают ─────────────────────────────────────────
func _test_building_sleep() -> void:
	print("\n───── ЗДАНИЯ: СОН _process ─────")
	for b in get_tree().get_nodes_in_group("all_buildings"):
		print("  %-16s фракция=%d  is_processing=%s  очередь=%d"
			% [b.display_name, b.faction, str(b.is_processing()), b.production_queue.size()])

# ── 4. Единый фронт формации ────────────────────────────────────────────────
func _test_formation_facing() -> void:
	print("\n───── ФОРМАЦИЯ: ЕДИНОЕ НАПРАВЛЕНИЕ ─────")
	var SpearS := load("res://scenes/units/Spearman.tscn") as PackedScene
	var squad: Array = []
	for i in range(30):
		var u: Unit = SpearS.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.add_child(u)
		u.global_position = Vector3(-10.0 + float(i % 6) * 0.5, 0.0, -10.0 + float(i / 6) * 0.5)
		squad.append(u)
	await get_tree().process_frame

	# Линия фронта: тянем слева направо по X, значит фронт смотрит на -Z
	var line_start := Vector3(0.0, 0.0, 5.0)
	var line_end   := Vector3(9.0, 0.0, 5.0)
	var sm = main.selection_manager
	sm._clear_selection()
	for u in squad:
		sm._select(u)
	sm._execute_line_formation(line_start, line_end)

	var line_dir := (line_end - line_start).normalized()
	var expect := Vector3(line_dir.z, 0.0, -line_dir.x)
	print("вектор линии=(%.2f,%.2f), ожидаемый взгляд=(%.2f, %.2f)"
		% [line_dir.x, line_dir.z, expect.x, expect.z])
	# Ждём прихода
	var guard := 0
	while guard < 1200:
		await get_tree().process_frame
		guard += 1
		var moving := 0
		for u in squad:
			if is_instance_valid(u) and u.state == Unit.State.MOVING:
				moving += 1
		if moving == 0:
			break
	var same := 0
	var worst := 999.0
	var flips := {}
	for u in squad:
		if not is_instance_valid(u):
			continue
		var f: Vector3 = u._facing
		var dot: float = f.normalized().dot(expect)
		worst = minf(worst, dot)
		if dot > 0.999:
			same += 1
		var fh: bool = u._flip_h_state
		flips[fh] = int(flips.get(fh, 0)) + 1
	print("пришли за %d кадров. смотрят строго по фронту: %d из %d, худший dot=%.4f"
		% [guard, same, squad.size(), worst])
	print("зеркало спрайта flip_h: %s  (одно значение на всех = смотрят одинаково)" % str(flips))
	# Стойка: копья подняты, пока не нажата ЗАЩИТА
	var lev_attack := 0
	for u in squad:
		if is_instance_valid(u) and u.call("_spear_leveled"):
			lev_attack += 1
	sm.set_selection_stance("defense")
	await get_tree().process_frame
	var lev_def := 0
	for u in squad:
		if is_instance_valid(u) and u.call("_spear_leveled"):
			lev_def += 1
	print("копья горизонтально: в стойке АТАКА %d/30, в стойке ЗАЩИТА %d/30"
		% [lev_attack, lev_def])
	# Ряд пересчитывается раз в RANK_RECHECK = 0.25 c, поэтому сразу после смены
	# стойки часть бойцов ещё держит прошлый ряд. Даём строю устояться и смотрим,
	# сколько бойцов реально стоят во втором ряду и глубже
	for _i in range(40):
		await get_tree().physics_frame
	var lev_def2 := 0
	var ranks := {}
	for u in squad:
		if not is_instance_valid(u):
			continue
		if u.call("_spear_leveled"):
			lev_def2 += 1
		var r: int = u._live_rank
		ranks[r] = int(ranks.get(r, 0)) + 1
	print("через 40 физкадров: горизонтально %d/30, распределение по рядам %s"
		% [lev_def2, str(ranks)])
	for u in squad:
		if is_instance_valid(u):
			u.queue_free()
	await get_tree().process_frame

# ── 5. Артель ускоряет стройку ──────────────────────────────────────────────
func _test_group_build() -> void:
	print("\n───── АРТЕЛЬ: УСКОРЕНИЕ СТРОЙКИ ─────")
	var CS := load("res://scripts/ConstructionSite.gd")
	for n in [1, 2, 3, 5]:
		var site: Building = CS.new()
		site.faction     = Constants.FACTION_PLAYER
		site.target_id   = "mine"
		site.target_name = "Рудник"
		site.build_time  = 12.0
		site.build_size  = Vector3(3, 2, 3)
		main.add_child(site)
		site.global_position = Vector3(30, 0, 30)
		var fakes: Array = []
		for i in range(n):
			var f := Node3D.new()
			main.add_child(f)
			site.add_builder(f)
			fakes.append(f)
		var before: float = site.progress
		site._process(1.0)
		var rate: float = site.progress - before
		print("  рабочих=%d → прогресс за 1 сек=%.2f (×%.2f к одиночке), стройка за %.1f сек"
			% [n, rate, rate, site.build_time / maxf(rate, 0.01)])
		site.queue_free()
		for f in fakes:
			f.queue_free()
		await get_tree().process_frame

	# UI: панель построек у выделения из нескольких рабочих
	var WorkerS := load("res://scenes/units/Worker.tscn") as PackedScene
	var crew: Array = []
	for i in range(4):
		var w: Unit = WorkerS.instantiate()
		w.faction = Constants.FACTION_PLAYER
		main.add_child(w)
		w.global_position = Vector3(20.0 + float(i), 0, 20.0)
		crew.append(w)
	await get_tree().process_frame
	var hud = main.hud
	hud.show_selection(crew)
	await get_tree().process_frame
	var names: Array = []
	for b in hud.button_container.get_children():
		if b is Button:
			names.append(String((b as Button).text).replace("\n", " / "))
	print("панель при выделении 4 рабочих: %d кнопок -> %s" % [names.size(), str(names)])
	print("подпись: %s" % hud.info_label.text)
	for w in crew:
		w.queue_free()
