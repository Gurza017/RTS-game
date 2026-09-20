extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_garrison_archers_test — ГРАД СТРЕЛ ПО УКРЕПЛЕНИЯМ (ТЗ 19.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ФОКУС      — 10 отрядов лучников игрока по ПКМ на башню с гарнизоном
##                  (бараки и крепость рядом, чтобы прежний «разлив по
##                  соседним домам» имел куда увести): все 10 держат замок на
##                  башне, мимо идущая пехота и трупы цель не подменяют,
##                  стрелы летят в башню.
##   B УРОН       — параллельный урон: стены получают 100 %, защитник на
##                  крыше — 0.5× той же стрелы (до брони); башня, бараки,
##                  крепость — одно правило.
##   C ТРУПЫ      — павшие защитники лежат НА ПЛОЩАДКЕ (высота крыши), у
##                  подножия — никого; место павшего занимает резервист.
##   D УПРАВЛЕНИЕ — выделена башня игрока, ПКМ по ДАЛЬНЕМУ чужому отряду:
##                  гарнизон переносит огонь на него, ближний не трогает;
##                  цель выбита — гарнизон сам возвращается к ближнему.
##   E ПО ЗДАНИЮ  — ПКМ выделенной башней по чужим баракам: гарнизон бьёт
##                  постройку (дальность — до края рисунка).
## Числа — из конфига (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_garrison_archers_test/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")

const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const GF := Constants.FACTION_GOBLIN

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(600.0)
	t.timeout.connect(func():
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_garrison_archers_test: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var px: float = at.x - float(i / cols) * 0.9
		var pz: float = at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35
		var u: Unit = _spawn(kind, fac, Vector3(px, 0.0, pz))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _kill_all(arr: Array) -> void:
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e12)

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _hp_sum(arr: Array) -> float:
	var s := 0.0
	for u in _alive(arr):
		s += (u as Unit).current_health
	return s

func _place(b: Building, fac: int, at: Vector3) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

## Экранная точка узла (камера партии наведена на него)
func _screen_of(p: Vector3) -> Vector2:
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	return cam.unproject_position(p)

func _look_at(p: Vector3) -> void:
	if main.has_method("focus_camera_on"):
		main.focus_camera_on(p)
	await frames(12)

func _freeze_ai() -> void:
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for k in ["goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	_freeze_ai()
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	# Дикие партии (стартовые войска, стражи, гноллы) — вон: они лезут в замер
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	# Камера — замораживаем (правило стендов по экрану: точка считается в том
	# же кадре, что и разбор клика)
	main.set_process(false)
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	if cam != null:
		cam.set_process(false)
	await _a_focus()
	await _b_damage()
	await _c_corpses()
	await _d_manual()
	await _e_building()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ФОКУС: 10 ОТРЯДОВ ЛУЧНИКОВ ПО БАШНЕ С ГАРНИЗОНОМ
# ═════════════════════════════════════════════════════════════════════════════
var _a_tower: Building = null
var _a_barracks: Building = null
var _a_castle: Building = null

func _a_focus() -> void:
	print("\n═════ A. ФОКУС ДЕСЯТИ ОТРЯДОВ НА БАШНЕ ═════")
	var tp := Vector3(40.0, 0.0, -40.0)
	main._clear_area_of_resources(tp, 70.0)
	var tower: Building = load("res://scripts/Tower.gd").new()
	_place(tower, E, tp)
	# Соседи ТОГО ЖЕ лагеря в BUILDING_CHAIN_RANGE (26 м): прежний разлив
	# уводил лишние отряды сюда
	var barracks: Building = Barracks.new()
	_place(barracks, E, tp + Vector3(-18.0, 0.0, 6.0))
	var castle: Building = Castle.new()
	_place(castle, E, tp + Vector3(16.0, 0.0, 14.0))
	await pframes(6)
	_a_tower = tower
	_a_barracks = barracks
	_a_castle = castle
	# Гарнизон: вражеские лучники в каждом укреплении
	var g_t: Array = _squad("archer", E, tp + Vector3(0, 0, 6), 12)
	var g_b: Array = _squad("archer", E, barracks.global_position + Vector3(0, 0, 6), 12)
	var g_c: Array = _squad("archer", E, castle.global_position + Vector3(0, 0, 8), 12)
	await pframes(4)
	var sat: bool = (tower as Castle).garrison_now(int(g_t[0])) \
		and (barracks as Castle).garrison_now(int(g_b[0])) \
		and (castle as Castle).garrison_now(int(g_c[0]))
	await pframes(4)
	verdict("A0 башня, бараки и крепость — с гарнизоном лучников на крыше",
		sat and (tower as Castle).has_roof_garrison() and (barracks as Castle).has_roof_garrison()
		and (castle as Castle).has_roof_garrison(),
		"сели: %s" % str(sat))
	# 10 отрядов лучников игрока в 22 м к югу от башни (лук 15 + подход)
	var squads: Array = []
	var all_men: Array = []
	for k in range(10):
		var at: Vector3 = tp + Vector3(-13.5 + 3.0 * float(k), 0.0, 24.0 + float(k % 2) * 4.0)
		var s: Array = _squad("archer", F, at, 12)
		squads.append(s)
		all_men.append_array(s[1])
	await pframes(6)
	# Мимоходящая пехота гоблинов — в 6 м от строя лучников, идёт поперёк
	var passers: Array = _squad("goblin_spearman", GF, tp + Vector3(-30.0, 0.0, 14.0), 10, 5)
	for g in passers[1]:
		(g as Unit).set_tick(false)
		# Бессмертны: их расстреливают гарнизоны крыш (вражеские для орды), а
		# нам нужен факт «стрелки игрока их целью не берут», не их гибель
		(g as Unit).max_health = 1.0e7
		(g as Unit).current_health = 1.0e7
		(g as Unit)._soa_push_stats()
	# Трупы под ногами: павший чужой рядом со стрелками
	var dead_one: Unit = _spawn("goblin_spearman", GF, tp + Vector3(0.0, 0.0, 18.0))
	await pframes(2)
	dead_one.take_damage(1.0e12)
	await pframes(4)
	var sm = main.selection_manager
	sm._clear_selection()
	for s in squads:
		for u in s[1]:
			sm._select(u)
	GameManager.on_selection_changed(sm.selected_units, true)
	await _look_at(tp)
	var scr: Vector2 = _screen_of(tower.global_position + Vector3(0.0, tower.build_size.y * 0.5, 0.0))
	var pick: Dictionary = sm._pick_at(scr, sm.order_pick_mask())
	verdict("A1 клик по башне находит башню", pick.get("target", null) == tower,
		"нашли %s" % str(pick.get("target", null)))
	sm._handle_right_click(scr, false)
	await pframes(3)
	# Сразу после приказа: у КАЖДОГО отряда замок на башне, не на соседях
	var on_tower := 0
	var on_other := 0
	for s in squads:
		var t = (s[1][0] as Unit)._lock_target
		if t == tower:
			on_tower += 1
		else:
			on_other += 1
	verdict("A2 все 10 отрядов получили замок на башню (разлива по соседним домам нет)",
		on_tower == 10 and on_other == 0, "на башне %d, на прочем %d" % [on_tower, on_other])
	# Стрелы, выпущенные ДО клика (авто-агро по гоблину до его гибели), долетают
	# и в замер не идут: судим только выстрелы после приказа
	await pframes(90)
	# Пехота идёт поперёк мимо стрелков; 8 с обстрела
	for g in passers[1]:
		(g as Unit).set_tick(true)
		(g as Unit).command_move(tp + Vector3(30.0, 0.0, 14.0))
	var hp_t0: float = tower.current_health
	var hp_b0: float = barracks.current_health
	var hp_c0: float = castle.current_health
	var pass_hp0: float = _hp_sum(passers[1])
	var lost_lock := 0
	var retargeted := 0
	var shots_at_tower := 0
	var shots_other := 0
	var seen_ids: Dictionary = {}
	for f in range(60 * 8):
		await get_tree().physics_frame
		if f % 10 == 0:
			for u in all_men:
				if u == null or not is_instance_valid(u):
					continue
				var uu := u as Unit
				if uu == null or uu.is_dead():
					continue
				if not uu.target_lock or uu._lock_target != tower:
					lost_lock += 1
				var at = uu.attack_target
				if at != null and is_instance_valid(at) and at != tower:
					retargeted += 1
		for rec in GameManager.flight_records():
			var id: int = int(rec["id"])
			if seen_ids.has(id):
				continue
			seen_ids[id] = true
			var sh = rec["shooter"]
			if sh == null or not is_instance_valid(sh) or not (sh is Unit) or (sh as Unit).faction != F:
				continue
			var en: Vector3 = rec["end"]
			if Vector2(en.x - tower.global_position.x, en.z - tower.global_position.z).length() \
					<= tower.ring_radius() + 3.0:
				shots_at_tower += 1
			else:
				shots_other += 1
	verdict("A3 за 8 с ни один стрелок не потерял замок на башне и не взял другую цель",
		lost_lock == 0 and retargeted == 0, "потерь замка %d, чужих целей %d" % [lost_lock, retargeted])
	verdict("A4 стрелы игрока летят в башню (≥ 90 %), не в соседей и не в прохожих",
		shots_at_tower > 0 and float(shots_at_tower) >= 0.9 * float(shots_at_tower + shots_other),
		"в башню %d, мимо %d" % [shots_at_tower, shots_other])
	verdict("A5 башня несёт урон, бараки и крепость — нет",
		tower.current_health < hp_t0 and is_equal_approx(barracks.current_health, hp_b0)
		and is_equal_approx(castle.current_health, hp_c0),
		"башня %.0f → %.0f, бараки %.0f → %.0f, крепость %.0f → %.0f" % [
			hp_t0, tower.current_health, hp_b0, barracks.current_health, hp_c0, castle.current_health])
	# Прохожие: стрелы по ним не назначались (урон только случайным пролётом,
	# и то не больше пары стрел — судим по замку выше). Здесь — что прохожие
	# живы и дошли: их никто не расстреливал строем
	verdict("A6 мимоходящая пехота целью стрелков игрока не стала (см. A3), вся жива",
		_alive(passers[1]).size() == 10, "живых %d, запас %.0f → %.0f (стрелы над головой — свойство полёта)" % [
			_alive(passers[1]).size(), pass_hp0, _hp_sum(passers[1])])
	sm._clear_selection()
	_kill_all(all_men)
	_kill_all(passers[1])
	await pframes(4)
	# Гарнизоны остаются для блоков B/C. ЛОВУШКА: take_damage по укрытому
	# уходит в ЗДАНИЕ (absorb_damage_for) — «убить» гарнизон 1e12 снесло бы
	# постройку целиком. Стрелы в полёте обязаны долететь до замера урона
	await pframes(150)

# ═════════════════════════════════════════════════════════════════════════════
# B. ПАРАЛЛЕЛЬНЫЙ УРОН
# ═════════════════════════════════════════════════════════════════════════════
func _b_damage() -> void:
	print("\n═════ B. ПАРАЛЛЕЛЬНЫЙ УРОН: СТЕНЫ 100 %, ЗАЩИТНИК 50 % ═════")
	var frac: float = _UCfg.GARRISON_COVER_FRAC
	verdict("B0 срез укрытия из конфига = 0.5", is_equal_approx(frac, 0.5), "%.2f" % frac)
	var shooter: Unit = _spawn("archer", F, _a_tower.global_position + Vector3(0, 0, 40))
	shooter.set_tick(false)
	await pframes(2)
	for b in [_a_tower, _a_barracks, _a_castle]:
		var bb: Castle = b as Castle
		var name_b: String = bb.building_id
		# Свежий гарнизон, если его выбили в A
		if not bb.has_roof_garrison():
			var g: Array = _squad("archer", E, bb.global_position + Vector3(0, 0, 6), 12)
			await pframes(3)
			bb.garrison_now(int(g[0]))
			await pframes(3)
		var roof = bb._roof
		var units: Array = roof.roof_units()
		var hp_units0: float = 0.0
		for u in units:
			hp_units0 += (u as Unit).current_health
		var hp_b0: float = bb.current_health
		var hits0: int = bb.roof_hits
		var dmg := 100.0
		bb.take_damage(dmg, shooter)
		await pframes(1)
		var hp_units1: float = 0.0
		for u in roof.roof_units():
			hp_units1 += (u as Unit).current_health
		var wall_loss: float = hp_b0 - bb.current_health
		var men_loss: float = hp_units0 - hp_units1
		# Защитник получил 0.5× до брони: по формуле брони ожидаем ровно это
		var def_u: Unit = units[0]
		var expect_men: float = _UCfg.damage_after_armor(dmg * frac, def_u.defense + def_u.armor)
		verdict("B1 %s: стены −%.0f (100 %%), защитник −%.1f = броня(%.0f × 0.5)" % [name_b, dmg, expect_men, dmg],
			absf(wall_loss - dmg) < 0.05 and absf(men_loss - expect_men) < 0.5 and bb.roof_hits == hits0 + 1,
			"стены −%.1f, гарнизон −%.1f, попаданий в крышу +%d" % [wall_loss, men_loss, bb.roof_hits - hits0])
	# Ближний бой — только в стены
	var sp: Unit = _spawn("spearman", F, _a_tower.global_position + Vector3(0, 0, 6))
	sp.set_tick(false)
	var hpu0: float = 0.0
	for u in (_a_tower as Castle)._roof.roof_units():
		hpu0 += (u as Unit).current_health
	var hpt0: float = _a_tower.current_health
	_a_tower.take_damage(50.0, sp)
	await pframes(1)
	var hpu1: float = 0.0
	for u in (_a_tower as Castle)._roof.roof_units():
		hpu1 += (u as Unit).current_health
	verdict("B2 удар копьём — стены −50, гарнизон цел",
		absf(hpt0 - _a_tower.current_health - 50.0) < 0.05 and absf(hpu0 - hpu1) < 0.5,
		"стены −%.1f, гарнизон −%.1f" % [hpt0 - _a_tower.current_health, hpu0 - hpu1])
	sp.take_damage(1.0e12)
	shooter.take_damage(1.0e12)
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. ТРУПЫ ЗАЩИТНИКОВ — НА ПЛОЩАДКЕ
# ═════════════════════════════════════════════════════════════════════════════
func _c_corpses() -> void:
	print("\n═════ C. ТРУПЫ ЗАЩИТНИКОВ НА КРЫШЕ ═════")
	var bb: Castle = _a_castle as Castle
	var shooter: Unit = _spawn("archer", F, bb.global_position + Vector3(0, 0, 40))
	shooter.set_tick(false)
	var roof = bb._roof
	var men0: int = roof.men()
	var shown0: int = int(roof.shown())
	var corpses0: int = GameManager.corpses._list.size()
	var ground: float = GameManager.get_terrain_height(bb.global_position.x, bb.global_position.z)
	var roof_y: float = roof.platform_point().y
	# Бьём, пока не погибнут четверо (0.5× среза — значит вдвое больше залпов)
	var dead := 0
	for i in range(400):
		if roof.men() <= men0 - 4:
			break
		bb.take_damage(60.0, shooter)
		await pframes(1)
	dead = men0 - roof.men()
	await pframes(3)
	var on_roof := 0
	var at_base := 0
	for c in GameManager.corpses._list.slice(corpses0):
		var p: Vector3 = c.pos
		if Vector2(p.x - bb.global_position.x, p.z - bb.global_position.z).length() > bb.ring_radius() * 1.6:
			continue
		if p.y > ground + (roof_y - ground) * 0.5:
			on_roof += 1
		else:
			at_base += 1
	verdict("C1 гарнизон несёт потери (защитники гибнут медленнее — срез 0.5)", dead >= 4,
		"погибло %d" % dead)
	verdict("C2 все тела павших лежат НА ПЛОЩАДКЕ (высота крыши), у подножия — никого",
		on_roof == dead and at_base == 0,
		"на крыше %d, у подножия %d, погибло %d (крыша y=%.2f, грунт %.2f)" % [on_roof, at_base, dead, roof_y, ground])
	verdict("C3 место павшего занял резервист (спрайтов не меньше)",
		int(roof.shown()) == mini(shown0, roof.men()),
		"было %d, стало %d при живых %d" % [shown0, int(roof.shown()), roof.men()])
	shooter.take_damage(1.0e12)
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# D. ПРЯМОЙ ПРИКАЗ ГАРНИЗОНУ: ВЫДЕЛЕНА БАШНЯ, ПКМ ПО ДАЛЬНЕМУ ОТРЯДУ
# ═════════════════════════════════════════════════════════════════════════════
var _d_tower: Building = null

func _d_manual() -> void:
	print("\n═════ D. РУЧНОЙ ПРИКАЗ ГАРНИЗОНУ ═════")
	var tp := Vector3(-60.0, 0.0, 60.0)
	main._clear_area_of_resources(tp, 60.0)
	var tower: Building = load("res://scripts/Tower.gd").new()
	_place(tower, F, tp)
	_d_tower = tower
	await pframes(4)
	var g: Array = _squad("archer", F, tp + Vector3(0, 0, 6), 20)
	await pframes(3)
	var sat: bool = (tower as Castle).garrison_now(int(g[0]))
	await pframes(3)
	var roof = (tower as Castle)._roof
	var base_r: float = (g[1][0] as Unit).attack_range
	var reach: float = base_r * _UCfg.GARRISON_RANGE_MULT
	# Ближний отряд — 9 м, дальний — 0.9 × дальности с баффом, оба бессмертны
	var near: Array = _squad("goblin_spearman", GF, tp + Vector3(9.0, 0, 0), 10, 5)
	var far: Array = _squad("goblin_spearman", GF, tp + Vector3(0, 0, -reach * 0.9), 10, 5)
	for u in near[1] + far[1]:
		(u as Unit).set_tick(false)
	await pframes(3)
	verdict("D0 гарнизон сел, ближний и дальний отряды поставлены", sat and roof.men() == 20,
		"внутри %d, лук %.1f, дальность крыши %.1f" % [roof.men(), base_r, reach])
	# Авто-агро: без приказа бьёт ближнего
	await pframes(90)
	var near_hp0: float = _hp_sum(near[1])
	var far_hp0: float = _hp_sum(far[1])
	verdict("D1 без приказа гарнизон бьёт ближайшего", roof._fire_target != null
		and is_instance_valid(roof._fire_target) and (roof._fire_target as Unit).squad_id == int(near[0]),
		"цель %s" % str(roof._fire_target))
	# Выделяем башню, ПКМ по дальнему отряду
	var sm = main.selection_manager
	sm._clear_selection()
	sm._select(tower)
	GameManager.on_selection_changed(sm.selected_units, true)
	await _look_at(tp)
	var far_u: Unit = far[1][0]
	var scr: Vector2 = _screen_of(far_u.global_position + Vector3(0, 0.6, 0))
	var pick: Dictionary = sm._pick_at(scr, sm.order_pick_mask())
	var picked = pick.get("target", null)
	var pick_ok: bool = picked != null and picked is Unit and (picked as Unit).squad_id == int(far[0])
	verdict("D2 клик находит бойца дальнего отряда", pick_ok, "нашли %s" % str(picked))
	var orders0: int = int(sm.garrison_fire_orders)
	sm._handle_right_click(scr, false)
	await pframes(2)
	var mt = (tower as Castle).roof_manual_target()
	verdict("D3 ПКМ выделенной башней = приказ гарнизону (ручная цель в дальнем отряде)",
		sm.garrison_fire_orders == orders0 + 1 and mt != null and (mt as Unit).squad_id == int(far[0]),
		"приказов %d, цель %s" % [sm.garrison_fire_orders - orders0, str(mt)])
	near_hp0 = _hp_sum(near[1])
	far_hp0 = _hp_sum(far[1])
	var wrong := 0
	for f in range(60 * 5):
		await get_tree().physics_frame
		var t = roof._fire_target
		if t != null and is_instance_valid(t) and (t as Unit).squad_id != int(far[0]):
			wrong += 1
	verdict("D4 весь огонь 5 с — по указанному дальнему отряду, ближний не тронут",
		wrong == 0 and _hp_sum(far[1]) < far_hp0 and is_equal_approx(_hp_sum(near[1]), near_hp0),
		"кадров с чужой целью %d, дальний %.0f → %.0f, ближний %.0f → %.0f" % [
			wrong, far_hp0, _hp_sum(far[1]), near_hp0, _hp_sum(near[1])])
	# Цель выбита — обратно к авто-агро (ближний)
	_kill_all(far[1])
	await pframes(90)
	near_hp0 = _hp_sum(near[1])
	var shots5: int = int(roof.shots_fired)
	# Залп синхронный (перезарядка 3 с): окно — не короче двух перезарядок
	await pframes(60 * 7)
	var mt5 = (tower as Castle).roof_manual_target()
	verdict("D5 цель выбита — гарнизон вернулся к авто-агро по ближнему",
		mt5 == null and _hp_sum(near[1]) < near_hp0,
		"ручная цель %s, ближний %.0f → %.0f, живых %d, выстрелов +%d, цель %s" % [str(mt5), near_hp0,
			_hp_sum(near[1]), _alive(near[1]).size(), int(roof.shots_fired) - shots5, str(roof._fire_target)])
	sm._clear_selection()
	_kill_all(near[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. ГАРНИЗОН ПО ЧУЖОМУ ЗДАНИЮ
# ═════════════════════════════════════════════════════════════════════════════
func _e_building() -> void:
	print("\n═════ E. ПРИКАЗ ГАРНИЗОНУ ПО ЧУЖОЙ ПОСТРОЙКЕ ═════")
	var tower: Castle = _d_tower as Castle
	var roof = tower._roof
	var reach: float = float(roof.fire_range())
	# Чужие бараки: центр за дальностью, стена — внутри
	var eb: Building = Barracks.new()
	_place(eb, E, tower.global_position + Vector3(0, 0, reach + 1.5))
	await pframes(6)
	var sm = main.selection_manager
	sm._clear_selection()
	sm._select(tower)
	GameManager.on_selection_changed(sm.selected_units, true)
	await _look_at(tower.global_position)
	var scr: Vector2 = _screen_of(eb.global_position + Vector3(0, eb.build_size.y * 0.5, 0))
	var pick: Dictionary = sm._pick_at(scr, sm.order_pick_mask())
	verdict("E0 клик находит чужие бараки", pick.get("target", null) == eb, "нашли %s" % str(pick.get("target", null)))
	var hp0: float = eb.current_health
	sm._handle_right_click(scr, false)
	await pframes(2)
	verdict("E1 ручная цель гарнизона — постройка", tower.roof_manual_target() == eb,
		"цель %s, стена в %.1f м при дальности %.1f" % [str(tower.roof_manual_target()),
			Vector2(eb.global_position.x - tower.global_position.x, eb.global_position.z - tower.global_position.z).length() - eb.ring_radius(), reach])
	await pframes(60 * 5)
	verdict("E2 гарнизон бьёт постройку: запас стен убыл", eb.current_health < hp0,
		"%.0f → %.0f" % [hp0, eb.current_health])
	sm._clear_selection()
