extends Node

## ═══════════════════════════════════════════════════════════════════════════
## БОЛЬШОЙ СТЕНД ТЗ 24.09.2026 (второе письмо)
## ═══════════════════════════════════════════════════════════════════════════
##   A — ОВЦЫ: 5 фермеров, новая овца каждые 5 с, цикл без простоя
##   B — DELETE И РУИНЫ: снос выделенного здания, руина живёт 10 мин и
##       растворяется (растворение проверяется ускоренно)
##   C — ПОДВЫБОР: 10 отрядов в выделении → клик по иконке рода → приказ
##       получает только он
##   D — КОННИЦА ПРОТИВ КОПИЙ: лоб (каждый второй всадник гибнет), фланг
##   E — МАРШ И ФРОНТ: 3 отряда через полкарты без разрывов и «выворачивания»,
##       бой фронт на фронт без стягивания в точку, тон тел и сбитых с ног
##   F — ЭКОНОМИКА И ОРДА: груз 20 и цикл вдвое, копейщики дешевле, набеги по
##       расписанию, древо рабочего в одну вкладку
## Запуск: godot --headless --path . res://qa_tz0924b/Test.tscn [-- only=abcdef]

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _ForgeT := preload("res://scripts/forge_config.gd")
const _CSiteT := preload("res://scripts/ConstructionSite.gd")
const _CavT := preload("res://scripts/units/CavalryImpactHandler.gd")
const _RaidsT := preload("res://scripts/goblin/GoblinRaids.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var only: String = "abcdef"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else: _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz0924b: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int = 6, gap: float = 0.7) -> Array:
	var sid: int = GameManager.new_squad(f, uid)
	var out: Array = []
	for i in range(n):
		var u := _unit(uid, f, at + Vector3(float(i % cols) * gap, 0.0, float(i / cols) * gap))
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _kill(arr: Array) -> void:
	for u in arr:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e9)

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _centre(arr: Array) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			acc += (u as Node3D).global_position
			n += 1
	return acc / float(n) if n > 0 else Vector3.INF

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	if GameManager.fog != null: GameManager.fog.enabled = false
	for w in get_tree().get_nodes_in_group("all_units"):
		if w is Unit and (w as Unit).faction != Constants.FACTION_PLAYER:
			(w as Unit).set_tick(false)
	await pframes(4)
	if "a" in only: await _a_sheep()
	if "b" in only: await _b_delete()
	if "c" in only: await _c_subselect()
	if "d" in only: await _d_cavalry()
	if "e" in only: await _e_march_front()
	if "f" in only: _f_economy()
	_finish()

func _spot(dx: float, dz: float) -> Vector3:
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	return Vector3(a.x + dx, 0.0, a.z + dz)

# ═════════════════════════════════════════════════════════════════════════════
var _dbg_last: String = ""
func _a_sheep() -> void:
	print("\n═════ A. ОВЦЫ ═════")
	# Склад для мяса: в партии замок ставит игрок, в стенде — сам стенд
	if GameManager.get_nearest_dropoff(Constants.FACTION_PLAYER, _spot(0.0, 0.0)) == null:
		var cas: Building = _CSiteT.make_building("castle")
		cas.faction = Constants.FACTION_PLAYER
		main.world_add(cas)
		var cp := _spot(0.0, 0.0)
		cas.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
		await pframes(3)
	var at := _spot(30.0, 24.0)
	var pen: Building = _CSiteT.make_building("sheep_pen")
	pen.faction = Constants.FACTION_PLAYER
	pen.set("stock_on_ready", true)
	main.world_add(pen)
	pen.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	await pframes(4)
	var workers: Array = []
	for i in range(5):
		var w := _unit("worker", Constants.FACTION_PLAYER, at + Vector3(-6.0 + float(i) * 1.5, 0.0, 8.0))
		GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "worker"), w)
		workers.append(w)
	await pframes(2)
	var sm = main.selection_manager
	sm.selected_units = workers.duplicate()
	var n: int = int(sm._assign_pen_farmers(pen))
	verdict("A1 пять рабочих поставлены на загон", n == 5, "поставлено %d" % n)
	var r0: int = int(pen.get("sheep_respawned"))
	var food0: float = ResourceManager.gathered_total(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD)
	var idle_frames := 0
	var worst_wait := 0
	var cur_wait: Dictionary = {}
	for f in range(60 * 60):
		await get_tree().physics_frame
		if f % 300 == 0 and OS.get_cmdline_user_args().has("dbg"):
			for w9 in workers:
				var ww9 := w9 as Worker
				var tg = ww9.sheep_target()
				print("    dbg f%d фаза=%d сост=%d cut_t=%.2f cuts=%d тик=%s поз=(%.1f,%.1f) цель=%s мясо=%.0f" % [f, ww9.sheep_phase(), ww9.state, float(ww9._sheep_cut_t), int(ww9._sheep_cuts), str(ww9.tick_on),
					ww9.global_position.x, ww9.global_position.z,
					("(%.1f,%.1f) dead=%s" % [tg.global_position.x, tg.global_position.z, str(tg.get("dead"))]) if tg != null else "нет",
					ww9.meat_delivered])
		if OS.get_cmdline_user_args().has("dbg2"):
			var wd := workers[2] as Worker
			var key: String = "%d/%d/%d" % [wd.sheep_phase(), wd.state, int(wd._sheep_cuts)]
			if key != _dbg_last:
				_dbg_last = key
				print("    trace f%d фаза=%d сост=%d cuts=%d dest=%s carry=%.0f" % [f, wd.sheep_phase(), wd.state, int(wd._sheep_cuts), str(wd._sheep_dest_node), wd.carrying_amount])
		for w2 in workers:
			var ww := w2 as Worker
			if ww.sheep_phase() == Worker.SheepPhase.WAIT or ww.farm_pen() == null:
				cur_wait[ww] = int(cur_wait.get(ww, 0)) + 1
				worst_wait = maxi(worst_wait, int(cur_wait[ww]))
				idle_frames += 1
			else:
				cur_wait[ww] = 0
	var r1: int = int(pen.get("sheep_respawned"))
	var got: float = ResourceManager.gathered_total(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD) - food0
	verdict("A2 загон рождает овец (пауза %.0f с)" % _UCfgT.SHEEP_PEN_RESPAWN_SEC,
		is_equal_approx(_UCfgT.SHEEP_PEN_RESPAWN_SEC, 5.0) and r1 > r0, "родилось %d за минуту" % (r1 - r0))
	verdict("A3 цикл фермы без простоя: ни один фермер не ждал дольше 8 с", worst_wait <= 60 * 8,
		"худшее ожидание %.1f с" % (float(worst_wait) / 60.0))
	verdict("A4 мясо идёт на склад", got > 0.0, "за минуту +%.0f еды" % got)
	for w3 in workers:
		if is_instance_valid(w3):
			(w3 as Unit).take_damage(1e9)
	pen.call("_die")
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _b_delete() -> void:
	print("\n═════ B. DELETE И РУИНЫ ═════")
	var at := _spot(50.0, 5.0)
	var b: Building = _CSiteT.make_building("house")
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	await pframes(4)
	var sm = main.selection_manager
	sm._clear_selection()
	sm.selected_units = [b]
	var n: int = int(sm.disband_selected())
	await pframes(3)
	verdict("B1 Delete сносит выделенное здание", n == 1 and (not is_instance_valid(b) or b.is_dead()))
	var ruin: Node3D = null
	for r in get_tree().get_nodes_in_group("ruins"):
		if r is Node3D and (r as Node3D).global_position.distance_to(b.global_position if is_instance_valid(b) else at) < 3.0:
			ruin = r
	verdict("B2 на месте здания руина", ruin != null)
	verdict("B3 руина живёт 10 минут и растворяется последние секунды",
		is_equal_approx(_UCfgT.RUIN_LIFETIME_SEC, 600.0) and _UCfgT.RUIN_FADE_SEC > 0.0)
	if ruin != null:
		Building.ruin_dissolve(ruin, 0.5)
		var mi: MeshInstance3D = ruin.get_node_or_null("RuinSprite") as MeshInstance3D
		await get_tree().create_timer(0.25).timeout
		var mid: float = -1.0
		if is_instance_valid(ruin) and mi != null:
			var m = (mi.mesh as PrimitiveMesh).material if mi.mesh is PrimitiveMesh else mi.mesh.surface_get_material(0)
			if m is ShaderMaterial:
				mid = float((m as ShaderMaterial).get_shader_parameter("dissolve"))
		await get_tree().create_timer(0.5).timeout
		verdict("B4 растворение идёт плавно и руина исчезает", mid > 0.1 and mid < 0.95 and not is_instance_valid(ruin),
			"в середине dissolve=%.2f, руина %s" % [mid, "жива" if is_instance_valid(ruin) else "исчезла"])
	# Рамка вокруг армии со зданием: казнит армию, здание не трогает
	var men: Array = _squad("spearman", Constants.FACTION_PLAYER, _spot(55.0, 15.0), 3)
	var b2: Building = _CSiteT.make_building("house")
	b2.faction = Constants.FACTION_PLAYER
	main.world_add(b2)
	b2.global_position = Vector3(at.x + 10.0, GameManager.get_terrain_height(at.x + 10.0, at.z), at.z)
	await pframes(3)
	sm.selected_units = men + [b2]
	sm.disband_selected()
	await pframes(3)
	verdict("B5 рамка с бойцами и зданием здание не сносит", is_instance_valid(b2) and not b2.is_dead())
	b2.call("_die")

# ═════════════════════════════════════════════════════════════════════════════
func _c_subselect() -> void:
	print("\n═════ C. ПОДВЫБОР ═════")
	var all: Array = []
	var sq_sets: Array = []
	for k in range(9):
		var s: Array = _squad("spearman", Constants.FACTION_PLAYER, _spot(20.0 + float(k % 3) * 8.0, 40.0 + float(k / 3) * 8.0), 6, 3)
		sq_sets.append(s)
		all += s
	var monk: Array = _squad("monk", Constants.FACTION_PLAYER, _spot(10.0, 44.0), 1, 1)
	all += monk
	await pframes(3)
	var sm = main.selection_manager
	sm._clear_selection()
	for u in all:
		sm._select_one(u)
	GameManager.on_selection_changed(sm.selected_units)
	await pframes(2)
	main.hud._on_type_filter_pressed("monk")
	await pframes(2)
	var only_monk: bool = sm.selected_units.size() == 1 and sm.selected_units[0] == monk[0]
	verdict("C1 клик по иконке монаха оставляет в выделении ТОЛЬКО монаха", only_monk,
		"в выделении %d" % sm.selected_units.size())
	var pos0: Dictionary = {}
	for u2 in all:
		pos0[u2] = (u2 as Node3D).global_position
	sm._issue_formation_move(_spot(10.0, 70.0))
	await pframes(90)
	var moved_other := 0
	for u3 in all:
		if u3 == monk[0]:
			continue
		if (u3 as Node3D).global_position.distance_to(pos0[u3]) > 1.0:
			moved_other += 1
	var monk_moved: float = (monk[0] as Node3D).global_position.distance_to(pos0[monk[0]])
	verdict("C2 приказ получил только монах, армия стоит", moved_other == 0 and monk_moved > 1.0,
		"монах прошёл %.1f м, сдвинулись посторонние %d" % [monk_moved, moved_other])
	_kill(all)
	sm._clear_selection()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _d_cavalry() -> void:
	print("\n═════ D. КОННИЦА ПРОТИВ КОПИЙ ═════")
	_CavT.reset_stats()
	var at := _spot(60.0, 40.0)
	var wall: Array = _squad("spearman", Constants.FACTION_PLAYER, at, 10, 10, 0.7)
	for u in wall:
		(u as Unit)._facing = Vector3(0.0, 0.0, -1.0)
		(u as Unit).set_tick(false)
	await pframes(2)
	var riders: Array = []
	for i in range(6):
		var r := _unit("goblin_rider", Constants.FACTION_GOBLIN, at + Vector3(float(i) * 1.2, 0.0, -1.2))
		r.set_tick(false)
		r._charge_from = r.global_position - Vector3(0.0, 0.0, -30.0)
		r._charge_path = 30.0
		riders.append(r)
	for i2 in range(riders.size()):
		(riders[i2] as Unit)._charge_impact(wall[i2], Vector3(0.0, 0.0, 1.0))
	var dead := 0
	var halved := 0
	for r2 in riders:
		if not is_instance_valid(r2) or (r2 as Unit).is_dead():
			dead += 1
		elif absf((r2 as Unit).current_health / (r2 as Unit).max_health - 0.5) < 0.02:
			halved += 1
	verdict("D1 лоб на копья: каждый второй всадник первой волны гибнет, остальные теряют 50 %",
		dead == 3 and halved == 3, "погибло %d, на половине %d из 6" % [dead, halved])
	_kill(riders + wall)
	await pframes(2)
	# Фланг: копейщики получают высокий урон и рассеиваются, летят не все
	var line: Array = _squad("spearman", Constants.FACTION_PLAYER, at + Vector3(20.0, 0.0, 0.0), 24, 6, 0.7)
	for u2 in line:
		(u2 as Unit)._facing = Vector3(0.0, 0.0, -1.0)
		(u2 as Unit).set_tick(false)
	await pframes(3)
	var home: Dictionary = {}
	for u3 in line:
		home[u3] = (u3 as Node3D).global_position
	var fr := _unit("goblin_rider", Constants.FACTION_GOBLIN, at + Vector3(18.6, 0.0, 1.7))
	fr.set_tick(false)
	fr._charge_from = fr.global_position - Vector3(30.0, 0.0, 0.0)
	fr._charge_path = 30.0
	fr._charge_impact(line[6], Vector3(1.0, 0.0, 0.0))
	# Отлёт — скорость, её ведёт тик бойца: размораживаем накрытых
	for u5 in line:
		if is_instance_valid(u5) and not (u5 as Unit).is_dead():
			(u5 as Unit).set_tick(true)
	await pframes(45)
	var hurt := 0
	var flown := 0
	for u4 in line:
		if not is_instance_valid(u4) or (u4 as Unit).is_dead():
			hurt += 1
			continue
		if (u4 as Unit).current_health < (u4 as Unit).max_health - 0.1:
			hurt += 1
		if (u4 as Node3D).global_position.distance_to(home[u4]) > 0.8:
			flown += 1
	verdict("D2 удар во фланг: накрытые копейщики ранены (сектор фланг/тыл)",
		int(_CavT.last.get("sector", -1)) != _CavT.SECTOR_FRONT and hurt >= 3, "ранено %d" % hurt)
	verdict("D3 отлетают только первые ряды, а не весь строй", flown >= 1 and flown <= hurt and flown < line.size() / 2,
		"отлетело %d из %d" % [flown, line.size()])
	_kill(line + [fr])
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
func _e_march_front() -> void:
	print("\n═════ E. МАРШ, ФРОНТ, ТЕЛА ═════")
	# Полоса марша — между зоной игрока и базой красного ИИ, подальше от его
	# охраны (замороженные чужие остаются целями в сетке ядра)
	# Внутри зоны игрока: у середины между базами стоит пень с троллями
	var start := Vector3(-205.0, 0.0, -55.0)
	var goal := Vector3(-135.0, 0.0, -55.0)
	# Коридор марша чистится от деревьев: меряем строй, а не обход рощ
	var xx: float = start.x - 10.0
	while xx <= goal.x + 10.0:
		main._clear_area_of_resources(Vector3(xx, 0.0, start.z), 16.0)
		xx += 10.0
	await pframes(3)
	var squads: Array = []
	var all: Array = []
	for k in range(3):
		var s: Array = _squad("spearman", Constants.FACTION_PLAYER, start + Vector3(0.0, 0.0, float(k - 1) * 9.0), 40, 8, 0.66)
		squads.append(s)
		all += s
	await pframes(4)
	var sm = main.selection_manager
	sm._clear_selection()
	for u in all:
		sm._select_one(u)
	GameManager.on_selection_changed(sm.selected_units)
	sm._issue_formation_move(goal)
	if OS.get_cmdline_user_args().has("dbg3"):
		await pframes(2)
		for k8 in range(squads.size()):
			var u8 := (squads[k8] as Array)[0] as Unit
			print("    dbg3 отряд %d: сост=%d цель=(%.1f,%.1f) sel=%s" % [k8, u8.state, u8.move_target.x, u8.move_target.z, str(sm.selected_units.has(u8))])
	var worst_spread := 0.0
	var backtrack := 0
	var prev: Array = []
	for s0 in squads:
		prev.append(_centre(s0).x)
	var arrived := false
	var g := 0
	while g < 60 * 70:
		await pframes(30)
		g += 30
		var all_near := true
		for k2 in range(squads.size()):
			var s1: Array = squads[k2]
			var c: Vector3 = _centre(s1)
			for u2 in s1:
				if not is_instance_valid(u2):
					continue
				worst_spread = maxf(worst_spread, Vector2((u2 as Node3D).global_position.x - c.x, (u2 as Node3D).global_position.z - c.z).length())
			# «Выворачивание» — центр отряда пошёл НАЗАД по ходу марша
			if c.x < float(prev[k2]) - 0.8 and c.x < goal.x - 8.0:
				backtrack += 1
			prev[k2] = c.x
			if absf(c.x - goal.x) > 8.0:
				all_near = false
		if all_near:
			arrived = true
			break
	var cs: Array = []
	for s9 in squads:
		var c9: Vector3 = _centre(s9)
		cs.append("(%.0f,%.0f)" % [c9.x, c9.z])
	verdict("E1 три отряда дошли через полкарты", arrived, "за %.0f с, центры %s" % [float(g) / 60.0, str(cs)])
	verdict("E2 без разрывов: ни один боец не дальше 14 м от центра своего отряда", worst_spread <= 14.0,
		"худший разнос %.1f м" % worst_spread)
	verdict("E3 без «выворачивания»: центр отряда не ходит назад", backtrack == 0, "откатов %d" % backtrack)
	# Взгляд: стоящий строй смотрит в одну сторону
	await pframes(120)
	var faces: Dictionary = {}
	for u3 in squads[0]:
		var fv: Vector3 = (u3 as Unit)._facing
		faces[Vector2i(int(round(fv.x * 2.0)), int(round(fv.z * 2.0)))] = true
	verdict("E4 стоящий отряд смотрит в одну сторону", faces.size() <= 1, "направлений %d" % faces.size())
	# ── Бой фронт на фронт ────────────────────────────────────────────────
	var mine: Array = squads[1]
	var foe_at: Vector3 = _centre(mine) + Vector3(8.0, 0.0, 0.0)
	var foes: Array = _squad("goblin_spearman", Constants.FACTION_GOBLIN, foe_at - Vector3(0.0, 0.0, 3.0), 30, 3, 0.9)
	var z0: Array = _lateral(mine)
	for u4 in mine:
		(u4 as Unit).command_attack(foes[0], true)
	await pframes(60 * 6)
	var z1: Array = _lateral(_alive(mine))
	var w0: float = float(z0[1]) - float(z0[0])
	var w1: float = float(z1[1]) - float(z1[0])
	verdict("E5 в бою отряд держит фронт, а не стягивается в точку", w1 >= w0 * 0.5,
		"ширина фронта %.1f → %.1f м" % [w0, w1])
	# ── Тела: темнеют только убитые, куча слоями ──────────────────────────
	_kill(foes)
	await pframes(4)
	var tints: Array = []
	for c2 in GameManager.corpses._list:
		if c2 != null and int(c2.index) >= 0:
			tints.append(float(c2.tint))
	var tmin := 1.0
	var tmax := 0.0
	for t in tints:
		tmin = minf(tmin, float(t))
		tmax = maxf(tmax, float(t))
	verdict("E6 тела притемнены мягко: верх ≤ %.2f, низ ≥ %.2f" % [GameManager.corpses.PILE_TOP_TINT, GameManager.corpses.PILE_FLOOR_TINT],
		not tints.is_empty() and tmax <= GameManager.corpses.PILE_TOP_TINT + 0.001 and tmin >= GameManager.corpses.PILE_FLOOR_TINT - 0.001,
		"тонов %d, от %.2f до %.2f" % [tints.size(), tmin, tmax])
	var live := _unit("spearman", Constants.FACTION_PLAYER, _spot(40.0, 60.0))
	await pframes(2)
	live.knock_down(1.0)
	var prop = live.get("_down_prop")
	verdict("E7 сбитый с ног живой не темнеет", prop != null and is_equal_approx(float(prop.tint), 1.0),
		"тон %.2f" % (float(prop.tint) if prop != null else -1.0))
	_kill(all + [live])
	await pframes(3)

func _lateral(arr: Array) -> Array:
	var lo := INF
	var hi := -INF
	for u in arr:
		if is_instance_valid(u):
			var z: float = (u as Node3D).global_position.z
			lo = minf(lo, z)
			hi = maxf(hi, z)
	return [lo, hi]

# ═════════════════════════════════════════════════════════════════════════════
func _f_economy() -> void:
	print("\n═════ F. ЭКОНОМИКА И ОРДА ═════")
	var ws: Dictionary = _UCfgT.STATS["worker"]
	verdict("F1 рабочий: груз 20, цикл вдвое быстрее", is_equal_approx(float(ws["gather_amount"]), 20.0)
		and float(ws["gather_time"]) <= 2.5 + 0.001)
	var c: Dictionary = _UCfgT.train_cost("barracks", "spearman")
	verdict("F2 копейщики дешевле прежних 300/150/60", float(c.get(Constants.RESOURCE_WOOD, 999.0)) < 300.0
		and float(c.get(Constants.RESOURCE_GOLD, 999.0)) < 150.0, str(c))
	verdict("F3 одно древо рабочего, вкладки «Экономика» нет", not _ForgeT.UNIT_TABS.has("economy"))
	var sched: Array = _RaidsT.SCHEDULE
	verdict("F4 первый набег орды — не раньше 15-й минуты", float(sched[0]["t"]) >= 900.0
		and float(preload("res://scripts/spawn_config.gd").GOBLIN_PEACE_SEC) >= 900.0)
	# Набег строится строем: пехота в центре, туши за ней
	var gr = _RaidsT.new()
	gr.setup(main, main.goblin_ai.village if main.goblin_ai != null else Vector3(150.0, 0.0, -80.0))
	var r: Dictionary = gr.launch({"goblin_spearman": 3, "big_goblin": 2}, 0.0, main.PLAYER_BASE_ANCHOR, false)
	var kinds: Dictionary = r["kinds"]
	var slots: Dictionary = r["slots"]
	var inf_d := 0.0
	var heavy_d := 0.0
	var ni := 0
	var nh := 0
	for sid in slots.keys():
		var d: float = (slots[sid] as Vector3).distance_to(main.PLAYER_BASE_ANCHOR)
		if String(kinds[sid]) == "big_goblin":
			heavy_d += d; nh += 1
		else:
			inf_d += d; ni += 1
	# РАЗВОРОТ ТЗ 25.09.2026, п. 5: туши позади — только в схеме Б; в схеме А
	# они живой щит ПЕРЕД пехотой (стенд qa_tz0925, блок H)
	var heavy_behind: bool = heavy_d / float(nh) > inf_d / float(ni)
	var by_tactic: bool = heavy_behind if String(r.get("tactic", "B")) == _RaidsT.TACTIC_B else not heavy_behind
	verdict("F5 набег строем: 3 отряда пехоты фронтом, туши по тактике (А — щит впереди, Б — позади)",
		ni == 3 and nh == 1 and by_tactic, "пехота %d, туши %d, схема %s" % [ni, nh, String(r.get("tactic", "?"))])
	for sid2 in (r["sids"] as Array):
		var raw: Variant = GameManager.squads.get(int(sid2))
		if raw != null:
			_kill((raw as Dictionary)["members"])
