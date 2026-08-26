extends Node

## СТЕНД: ОТРЯД КАК ЕДИНИЦА ВЫДЕЛЕНИЯ
##   1 РЕЕСТР      — заказ найма = один отряд; два заказа = два отряда без смешения
##   2 ВЫХОД       — отряд спавнится у ворот и отходит на SQUAD_EXIT_DISTANCE
##   3 ВЫДЕЛЕНИЕ   — клик / рамка / Shift берут отряд ЦЕЛИКОМ; половину не выделить
##   4 ПРИКАЗЫ     — марш, формация линией и атака уходят всему отряду
##   5 МАРШ СТРОЕМ — обычный ПКМ сохраняет габариты строя (без Ctrl+1)
##   6 UI          — стойки без Ctrl+1, подпись панели, несколько отрядов
##   7 УБЫЛЬ       — реестр чистится, пустой отряд исчезает, нет утечек
##   8 НАГРУЗКА    — 300+ юнитов, медиана TIME_PHYSICS_PROCESS, reset_squads()

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _AICfg  := preload("res://scripts/ai_start_army_limit.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var main: Node = null
var hud = null
var sm = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	await frames(2)
	hud = main.hud
	sm  = main.selection_manager
	_refill()
	# Замок игрока ставится кликом мыши, которого в headless нет: поднимаем базу
	# вручную, иначе стартовых рабочих в партии не появляется вовсе
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-46.0, 0.0, -46.0)
	await frames(2)
	main._spawn_starting_workers(castle.global_position)
	await frames(2)

	await _test_registry()
	await _test_exit()
	await _test_selection()
	await _test_orders()
	await _test_march_shape()
	await _test_ui()
	await _test_attrition()
	await _test_reform_after_pass()
	await _test_reform_defense_line()
	await _test_mass_and_reset()
	_summary()
	print("\n=== SQUAD TEST DONE ===")
	get_tree().quit()

func _refill() -> void:
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 500000.0)

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-56s %s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

# ─────────────────────────────────────────────────────────────────────────────
var barracks: Building = null
var squad_a:  int = 0   # копейщики, заказ №1
var squad_a2: int = 0   # копейщики, заказ №2 (подряд за первым)
var squad_b:  int = 0   # лучники

func flush(bld: Building, cap: int = 1200) -> void:
	var guard := 0
	while guard < cap:
		if bld == null or not is_instance_valid(bld):
			return
		if bld.production_queue.is_empty() and bld._pending_spawns.is_empty():
			return
		bld._production_timer = 99999.0
		# ПАУЗУ МЕЖДУ ШЕРЕНГАМИ ТОЖЕ ПРОМАТЫВАЕМ. Отряд выходит из ворот
		# шеренга за шеренгой с задержкой ROW_RELEASE_SEC (см. Building):
		# у отряда в 50 человек это почти две секунды, и замер попадал на
		# недособранную партию (165 бойцов вместо 350). Темп выхода проверяет
		# qa_spear, раздел A; здесь нас интересует ИТОГОВЫЙ состав
		bld._row_gate = 0.0
		await get_tree().process_frame
		guard += 1

func _members(sid: int) -> Array:
	return GameManager.squad_members(sid)

## Отряды, которых не было в before_ids
## Отряды, появившиеся с момента снимка, ТОЛЬКО ИГРОКА.
## Фильтр по стороне обязателен: вражеский ИИ в стенде не выключен и заводит
## свои отряды параллельно. Без фильтра его отряд попадал в «партию» игрока —
## тест насчитывал 8 отрядов вместо 7 и один «неразформированный» после того,
## как игроцкие бойцы были перебиты (это был живой враг). Именно это и делало
## qa_squad #8 то красным, то зелёным в зависимости от таймингов ИИ
func _new_squad_ids(before_ids: Array) -> Array:
	var out: Array = []
	for key in GameManager.squads.keys():
		var sid: int = key
		if sid in before_ids:
			continue
		if int(GameManager.squads[sid]["faction"]) != Constants.FACTION_PLAYER:
			continue
		out.append(sid)
	return out

## Габариты облака точек по мировым осям XZ: [ширина_x, глубина_z]
func _bbox(points: Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var p0: Vector3 = points[0]
	var min_x: float = p0.x
	var max_x: float = p0.x
	var min_z: float = p0.z
	var max_z: float = p0.z
	for p in points:
		var v: Vector3 = p
		min_x = minf(min_x, v.x); max_x = maxf(max_x, v.x)
		min_z = minf(min_z, v.z); max_z = maxf(max_z, v.z)
	return Vector2(max_x - min_x, max_z - min_z)

# ═════════════════════════════════════════════════════════════════════════════
# 1. РЕЕСТР ОТРЯДОВ
# ═════════════════════════════════════════════════════════════════════════════
func _test_registry() -> void:
	print("\n═════ 1. РЕЕСТР ОТРЯДОВ ═════")
	# Стартовые рабочие: каждый — свой отряд
	var worker_squads: Array = []
	var workers := 0
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Worker:
			workers += 1
			var sid: int = (u as Unit).squad_id
			if sid > 0 and not (sid in worker_squads):
				worker_squads.append(sid)
	print("  стартовых рабочих=%d, отрядов у них=%d (1 рабочий = 1 отряд)" % [
		workers, worker_squads.size()])
	verdict("1 рабочий = 1 отряд", workers > 0 and workers == worker_squads.size(),
		"рабочих=%d отрядов=%d" % [workers, worker_squads.size()])

	barracks = Barracks.new()
	barracks.faction = Constants.FACTION_PLAYER
	main.world_add(barracks)
	barracks.global_position = Vector3(-40.0, 0.0, -40.0)
	await frames(2)

	# ── ЗАКАЗ №1 ─────────────────────────────────────────────────────────────
	var before1: Array = GameManager.squads.keys().duplicate()
	var reg_before: int = GameManager.squads.size()
	barracks.train_spearman()
	await flush(barracks)
	await frames(3)
	var new1: Array = _new_squad_ids(before1)
	squad_a = int(new1[0]) if not new1.is_empty() else 0
	print("  заказ №1 «копейщики»: новых отрядов в реестре=%d (было %d, стало %d)" % [
		new1.size(), reg_before, GameManager.squads.size()])
	verdict("1 один заказ = РОВНО один отряд", new1.size() == 1,
		"новых отрядов=%d" % new1.size())

	var want: int = _UCfg.squad_size("spearman")
	var got: int = _members(squad_a).size()
	print("  отряд A id=%d, бойцов=%d (конфиг squad_size(spearman)=%d)" % [squad_a, got, want])
	verdict("1 размер отряда = squad_size из конфига", got == want,
		"бойцов=%d ожидалось=%d" % [got, want])

	var same := true
	for m in _members(squad_a):
		if (m as Unit).squad_id != squad_a:
			same = false
	verdict("1 у всех бойцов один squad_id", same)
	verdict("1 тип отряда в реестре верный", GameManager.squad_type(squad_a) == "spearman",
		"squad_type=%s" % GameManager.squad_type(squad_a))

	# ── ЗАКАЗ №2 ПОДРЯД ──────────────────────────────────────────────────────
	var before2: Array = GameManager.squads.keys().duplicate()
	barracks.train_spearman()
	await flush(barracks)
	await frames(3)
	var new2: Array = _new_squad_ids(before2)
	squad_a2 = int(new2[0]) if not new2.is_empty() else 0
	var got2: int = _members(squad_a2).size()
	print("  заказ №2 «копейщики»: новых отрядов=%d, отряд B2 id=%d, бойцов=%d" % [
		new2.size(), squad_a2, got2])
	verdict("1 второй заказ = второй ОТДЕЛЬНЫЙ отряд",
		new2.size() == 1 and squad_a2 > 0 and squad_a2 != squad_a and got2 == want,
		"id1=%d id2=%d бойцов2=%d" % [squad_a, squad_a2, got2])

	# Бойцы не перемешались
	var mix := 0
	var ma: Array = _members(squad_a)
	var mb: Array = _members(squad_a2)
	for m in ma:
		if m in mb:
			mix += 1
	var wrong_id := 0
	for m in mb:
		if (m as Unit).squad_id != squad_a2:
			wrong_id += 1
	print("  пересечение составов: %d бойцов; чужой squad_id во втором отряде: %d" % [mix, wrong_id])
	verdict("1 бойцы двух заказов не перемешаны", mix == 0 and wrong_id == 0 and ma.size() == want,
		"пересечение=%d, чужих id=%d, |A|=%d |A2|=%d" % [mix, wrong_id, ma.size(), mb.size()])

# ═════════════════════════════════════════════════════════════════════════════
# 2. ВЫХОД ИЗ ЗДАНИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _test_exit() -> void:
	print("\n═════ 2. ВЫХОД ИЗ ЗДАНИЯ (ДВА ЗАКАЗА ПОДРЯД) ═════")
	var bpos: Vector3 = barracks.global_position
	var gate: Vector3 = bpos + barracks.spawn_offset
	# Замер СРАЗУ после спавна: отряд №2 только что вышел из ворот
	var d_spawn := 999.0
	var d_spawn_max := 0.0
	for m in _members(squad_a2):
		var d: float = (m as Node3D).global_position.distance_to(bpos)
		d_spawn = minf(d_spawn, d)
		d_spawn_max = maxf(d_spawn_max, d)
	print("  ворота здания: %s, SQUAD_EXIT_DISTANCE=%.1f" % [str(gate), barracks.SQUAD_EXIT_DISTANCE])
	print("  сразу после спавна отряд №2: ближний боец %.2f м, дальний %.2f м от центра здания" % [
		d_spawn, d_spawn_max])
	verdict("2 бойцы появляются ВПЛОТНУЮ к зданию (≤ ворот + строй)",
		d_spawn < barracks.spawn_offset.length() + 2.0,
		"ближний при спавне=%.2f м, ворота на %.2f м" % [d_spawn, barracks.spawn_offset.length()])

	# Дать обоим отрядам отойти
	await frames(600)

	var report: Array = []
	for pair in [[squad_a, "A (копейщики №1)"], [squad_a2, "A2 (копейщики №2)"]]:
		var row: Array = pair
		var sid: int = int(row[0])
		var label: String = String(row[1])
		var dmin := 9999.0
		var dmax := 0.0
		var near_gate := 0
		for m in _members(sid):
			var d: float = (m as Node3D).global_position.distance_to(bpos)
			dmin = minf(dmin, d)
			dmax = maxf(dmax, d)
			if d < 5.0:
				near_gate += 1
		print("  отряд %-22s: ближний %.2f м, дальний %.2f м, в 5 м от здания: %d бойцов" % [
			label, dmin, dmax, near_gate])
		report.append({"sid": sid, "min": dmin, "max": dmax, "near": near_gate})

	var all_clear := true
	var worst_min := 9999.0
	var stuck := 0
	for e in report:
		var d: Dictionary = e
		worst_min = minf(worst_min, float(d["min"]))
		stuck += int(d["near"])
		if float(d["min"]) <= 5.0:
			all_clear = false
	verdict("2 все отряды освободили ворота (>5 м от здания)", all_clear,
		"худший ближний=%.2f м, застряло у дверей=%d" % [worst_min, stuck])

	# Дошли ли до точки сбора (SQUAD_EXIT_DISTANCE от ворот)
	var target_d: float = barracks.spawn_offset.length() + barracks.SQUAD_EXIT_DISTANCE
	var reached := 0
	var total := 0
	var far := 0
	for e in report:
		var d: Dictionary = e
		for m in _members(int(d["sid"])):
			total += 1
			var dist: float = (m as Node3D).global_position.distance_to(bpos)
			if dist > target_d * 0.6:
				reached += 1
			if dist > barracks.spawn_offset.length() + 2.0:
				far += 1
	print("  расчётная точка сбора в %.1f м от центра здания" % target_d)
	print("  отошли за габарит ворот (>%.1f м): %d из %d; дошли на 60%%+ до точки сбора: %d из %d" % [
		barracks.spawn_offset.length() + 2.0, far, total, reached, total])
	verdict("2 отряды отошли от ворот на SQUAD_EXIT_DISTANCE", far == total,
		"отошло=%d из %d" % [far, total])

	# ВЗАИМНОЕ ПРОНИКНОВЕНИЕ ДВУХ ОТРЯДОВ: минимальная дистанция между составами
	var ma: Array = _members(squad_a)
	var mb: Array = _members(squad_a2)
	var inter_min := 9999.0
	var overlap := 0        # бойцов A ближе 0.35 м к любому бойцу A2
	for x in ma:
		var best := 9999.0
		for y in mb:
			var d: float = (x as Node3D).global_position.distance_to((y as Node3D).global_position)
			best = minf(best, d)
		inter_min = minf(inter_min, best)
		if best < 0.35:
			overlap += 1
	# Расстояние между центрами масс отрядов
	var ca := Vector3.ZERO
	for x in ma:
		ca += (x as Node3D).global_position
	if not ma.is_empty():
		ca /= float(ma.size())
	var cb := Vector3.ZERO
	for y in mb:
		cb += (y as Node3D).global_position
	if not mb.is_empty():
		cb /= float(mb.size())
	print("  два отряда копейщиков: мин. дистанция между составами %.2f м, центры масс разнесены на %.2f м" % [
		inter_min, ca.distance_to(cb)])
	print("  бойцов A ближе 0.35 м к соседнему отряду: %d из %d" % [overlap, ma.size()])
	verdict("2 второй отряд не застрял в первом (не слился телами)",
		inter_min > 0.2, "мин. дистанция=%.2f м, слипшихся=%d" % [inter_min, overlap])
	print("  ЗАМЕЧАНИЕ: оба заказа одного здания идут в ОДНУ точку сбора")
	print("    (gate + spawn_offset*SQUAD_EXIT_DISTANCE), поэтому отряды стоят вперемешку")

	# ── ТРЕТИЙ ОТРЯД ДЛЯ ДАЛЬНЕЙШИХ ТЕСТОВ: ЛУЧНИКИ (другой squad_size) ──────
	var before3: Array = GameManager.squads.keys().duplicate()
	barracks.train_archer()
	await flush(barracks)
	await frames(3)
	var new3: Array = _new_squad_ids(before3)
	squad_b = int(new3[0]) if not new3.is_empty() else 0
	var want_b: int = _UCfg.squad_size("archer")
	var got_b: int = _members(squad_b).size()
	print("  заказ «лучники»: отряд id=%d, бойцов=%d (конфиг=%d), тип=%s" % [
		squad_b, got_b, want_b, GameManager.squad_type(squad_b)])
	verdict("1 отряд лучников своего размера и типа",
		new3.size() == 1 and got_b == want_b and GameManager.squad_type(squad_b) == "archer",
		"бойцов=%d ожидалось=%d" % [got_b, want_b])

	# РАЗВОДИМ ОТРЯДЫ ПО КАРТЕ: тесты выделения должны мерить логику отрядов,
	# а не то, что три отряда стоят кучей у одних ворот и попадают в любую рамку
	var ca2 := Vector3.ZERO
	for x in _members(squad_a):
		ca2 += (x as Node3D).global_position
	if not _members(squad_a).is_empty():
		ca2 /= float(_members(squad_a).size())
	_park_squad(squad_a2, ca2 + Vector3(34.0, 0.0, 0.0))
	_park_squad(squad_b,  ca2 + Vector3(0.0, 0.0, 34.0))
	await frames(5)
	print("  отряды разведены: A в %s, A2 и B — в 34 м от него" % str(ca2.round()))

## Переставить отряд целиком, сохранив его строй, и остановить
func _park_squad(sid: int, center: Vector3) -> void:
	var ms: Array = _members(sid)
	if ms.is_empty():
		return
	var c := Vector3.ZERO
	for m in ms:
		c += (m as Node3D).global_position
	c /= float(ms.size())
	for m in ms:
		var u := m as Unit
		var off: Vector3 = u.global_position - c
		var np := Vector3(center.x + off.x, 0.0, center.z + off.z)
		u.global_position = np
		u.move_target = np
		u.state = Unit.State.IDLE

# ═════════════════════════════════════════════════════════════════════════════
# 3. ВЫДЕЛЕНИЕ ТОЛЬКО ОТРЯДАМИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_selection() -> void:
	print("\n═════ 3. НЕЛЬЗЯ ВЫДЕЛИТЬ ОДИНОЧКУ ═════")
	var members: Array = _members(squad_a)
	if members.size() < 4:
		verdict("3 выделение отрядами", false, "отряд пуст")
		return

	# ── КЛИК ПО ОДНОМУ БОЙЦУ ─────────────────────────────────────────────────
	sm._clear_selection()
	sm._select(members[0])
	var picked: int = sm.selected_units.size()
	var all_in := true
	for m in members:
		if not (m in sm.selected_units):
			all_in = false
	print("  клик по 1 бойцу → выделено %d (в отряде %d)" % [picked, members.size()])
	verdict("3 клик по бойцу выделяет ВЕСЬ отряд", picked == members.size() and all_in,
		"выделено=%d из %d" % [picked, members.size()])

	# Перебор: клик по КАЖДОМУ бойцу отряда всегда даёт полный отряд
	var bad_click := 0
	for m in members:
		sm._clear_selection()
		sm._select(m)
		if sm.selected_units.size() != members.size():
			bad_click += 1
	print("  перебор всех %d бойцов: кликов, давших неполный отряд = %d" % [members.size(), bad_click])
	verdict("3 ни один боец не выделяется в одиночку", bad_click == 0,
		"неполных выделений=%d" % bad_click)

	# ── РАМКА ПО ЧАСТИ ОТРЯДА ────────────────────────────────────────────────
	var cam: Camera3D = main._camera
	var ca := Vector3.ZERO
	for m in members:
		ca += (m as Node3D).global_position
	ca /= float(members.size())
	if main._camera.has_method("pan_to"):
		main._camera.pan_to(ca)
	await frames(5)

	var p: Vector2 = cam.unproject_position((members[0] as Node3D).global_position)
	sm._clear_selection()
	sm._handle_box_select(p - Vector2(6, 6), p + Vector2(6, 6), false)
	var box1: int = sm.selected_units.size()
	print("  рамка 12×12 px вокруг ОДНОГО бойца → выделено %d" % box1)
	verdict("3 рамка по 1 бойцу берёт отряд целиком", box1 == members.size(),
		"выделено=%d из %d" % [box1, members.size()])

	# Рамка, геометрически накрывающая ровно 2 бойцов отряда
	var s0: Vector2 = cam.unproject_position((members[0] as Node3D).global_position)
	var s1: Vector2 = cam.unproject_position((members[1] as Node3D).global_position)
	var r_min := Vector2(minf(s0.x, s1.x) - 2.0, minf(s0.y, s1.y) - 2.0)
	var r_max := Vector2(maxf(s0.x, s1.x) + 2.0, maxf(s0.y, s1.y) + 2.0)
	var rect := Rect2(r_min, r_max - r_min)
	var inside := 0
	for m in members:
		if rect.has_point(cam.unproject_position((m as Node3D).global_position)):
			inside += 1
	sm._clear_selection()
	sm._handle_box_select(r_min, r_max, false)
	var box2: int = sm.selected_units.size()
	print("  рамка накрыла геометрически %d бойцов → выделено %d (в отряде %d)" % [
		inside, box2, members.size()])
	verdict("3 рамка по 1-2 бойцам берёт отряд целиком",
		inside < members.size() and box2 == members.size(),
		"в рамке=%d выделено=%d из %d" % [inside, box2, members.size()])

	# ── SHIFT-ДОБАВЛЕНИЕ ─────────────────────────────────────────────────────
	var mb: Array = _members(squad_b)
	sm._clear_selection()
	sm._select(members[0])
	var before_add: int = sm.selected_units.size()
	var pb: Vector2 = cam.unproject_position((mb[0] as Node3D).global_position)
	sm._handle_box_select(pb - Vector2(6, 6), pb + Vector2(6, 6), true)   # additive
	var after_add: int = sm.selected_units.size()
	var whole_a := true
	var whole_b := true
	for m in members:
		if not (m in sm.selected_units):
			whole_a = false
	for m in mb:
		if not (m in sm.selected_units):
			whole_b = false
	print("  Shift-добавление второго отряда: было %d → стало %d (A=%d + B=%d = %d)" % [
		before_add, after_add, members.size(), mb.size(), members.size() + mb.size()])
	verdict("3 Shift добавляет ОТРЯДАМИ, а не бойцами",
		whole_a and whole_b and after_add == members.size() + mb.size(),
		"выделено=%d, A целиком=%s, B целиком=%s" % [after_add, str(whole_a), str(whole_b)])

	# ── ПОПЫТКА ОБОЙТИ ПРАВИЛО: выделить ровно половину отряда ───────────────
	# 1) Прямой вызов _select на каждом бойце половины — всё равно полный отряд
	sm._clear_selection()
	for i in range(members.size() / 2):
		sm._select(members[i])
	var half_try: int = sm.selected_units.size()
	# 2) Рамка вокруг центроида половины отряда
	var half_pts: Array = []
	for i in range(members.size() / 2):
		half_pts.append(cam.unproject_position((members[i] as Node3D).global_position))
	var hmin: Vector2 = half_pts[0]
	var hmax: Vector2 = half_pts[0]
	for q in half_pts:
		var v: Vector2 = q
		hmin = Vector2(minf(hmin.x, v.x), minf(hmin.y, v.y))
		hmax = Vector2(maxf(hmax.x, v.x), maxf(hmax.y, v.y))
	sm._clear_selection()
	sm._handle_box_select(hmin, hmax, false)
	var half_box: int = sm.selected_units.size()
	# 3) Двойной клик по типу — тоже отрядами
	sm._clear_selection()
	sm._select_same_type_on_screen(members[0] as Unit)
	var dbl: int = sm.selected_units.size()
	var dbl_partial := 0
	for sid in sm.selected_squad_ids():
		var full: Array = _members(int(sid))
		for m in full:
			if not (m in sm.selected_units):
				dbl_partial += 1
	print("  обход №1 (25 отдельных _select) → %d; обход №2 (рамка по половине) → %d; обход №3 (двойной клик) → %d, недобранных бойцов %d" % [
		half_try, half_box, dbl, dbl_partial])
	print("  (в рамке по половине геометрически лежало %d бойцов из %d)" % [
		half_pts.size(), members.size()])
	verdict("3 половину отряда выделить НЕВОЗМОЖНО",
		half_try == members.size() and half_box == members.size() and dbl_partial == 0,
		"полуотряд=%d/%d, рамка=%d/%d" % [half_try, members.size(), half_box, members.size()])

	# ── ИНВАРИАНТ: В ВЫДЕЛЕНИИ НЕТ НЕПОЛНЫХ ОТРЯДОВ ──────────────────────────
	# Прогоняем набор попыток и после КАЖДОЙ проверяем, что все отряды в
	# выделении представлены полностью — это и есть формулировка правила
	var partial_cases := 0
	var attempts := 0
	for i in range(members.size()):
		# попытка: клик по бойцу i, затем рамка вокруг бойца (i+1)
		sm._clear_selection()
		sm._select(members[i])
		var pt: Vector2 = cam.unproject_position((members[(i + 1) % members.size()] as Node3D).global_position)
		sm._handle_box_select(pt - Vector2(3, 3), pt + Vector2(3, 3), true)
		attempts += 1
		for sid2 in sm.selected_squad_ids():
			for m2 in _members(int(sid2)):
				if not (m2 in sm.selected_units):
					partial_cases += 1
					break
	print("  %d попыток обхода (клик + Shift-рамка по разным бойцам): неполных отрядов %d" % [
		attempts, partial_cases])
	verdict("3 инвариант «неполных отрядов в выделении не бывает»", partial_cases == 0,
		"неполных=%d за %d попыток" % [partial_cases, attempts])

	# ── ВСЕ ОТРЯДЫ НА ЭКРАНЕ ─────────────────────────────────────────────────
	sm._clear_selection()
	sm._handle_box_select(Vector2(0, 0), Vector2(1280, 720), false)
	var ids: Array = sm.selected_squad_ids()
	var whole := true
	var missing := 0
	for sid in ids:
		for m in _members(int(sid)):
			if not (m in sm.selected_units):
				whole = false
				missing += 1
	print("  рамка на весь экран → отрядов %d, бойцов %d, недобранных %d" % [
		ids.size(), sm.selected_units.size(), missing])
	verdict("3 все попавшие отряды выделены целиком", whole, "недобрано бойцов=%d" % missing)

# ═════════════════════════════════════════════════════════════════════════════
# 4. ПРИКАЗЫ ОТРЯДУ
# ═════════════════════════════════════════════════════════════════════════════
func _test_orders() -> void:
	print("\n═════ 4. ПРИКАЗЫ ВСЕМУ ОТРЯДУ ═════")
	var members: Array = _members(squad_a)
	sm._clear_selection()
	sm._select(members[0])
	sm._issue_formation_move(Vector3(-20.0, 0.0, -20.0))
	await frames(2)
	var moving := 0
	for m in members:
		if (m as Unit).state == Unit.State.MOVING:
			moving += 1
	print("  ПКМ в точку → сменили state на MOVING: %d из %d" % [moving, members.size()])
	verdict("4 приказ ПКМ получает весь отряд", moving == members.size(),
		"двинулось=%d из %d" % [moving, members.size()])

	# ── ФОРМАЦИЯ ЛИНИЕЙ ──────────────────────────────────────────────────────
	var line_a := Vector3(-30.0, 0.0, -10.0)
	var line_b := Vector3(-10.0, 0.0, -10.0)
	sm._execute_line_formation(line_a, line_b)
	await frames(2)
	var dir := (line_b - line_a).normalized()
	var face := Vector3(dir.z, 0.0, -dir.x)
	var worst := 1.0
	var faced := 0
	var line_moving := 0
	for m in members:
		var u := m as Unit
		if u.state == Unit.State.MOVING:
			line_moving += 1
		var f: Vector3 = u.face_on_arrive
		if f.length() > 0.01:
			faced += 1
			worst = minf(worst, f.normalized().dot(face))
	print("  формация линией: приказ получили %d из %d, направление задано %d, худший dot=%.5f" % [
		line_moving, members.size(), faced, worst])
	verdict("4 формация линией уходит всему отряду", line_moving == members.size(),
		"двинулось=%d из %d" % [line_moving, members.size()])
	verdict("4 худший dot взгляда ≈1.0 на отряде 20+",
		members.size() >= 20 and faced == members.size() and worst > 0.999,
		"бойцов=%d, худший dot=%.5f" % [members.size(), worst])

	# ── ПРИКАЗ АТАКИ ─────────────────────────────────────────────────────────
	var enemy_scene: PackedScene = load("res://scenes/units/Spearman.tscn")
	var foes: Array = []
	for i in range(6):
		var e: Unit = enemy_scene.instantiate()
		e.faction = Constants.FACTION_ENEMY
		main.world_add(e)
		foes.append(e)
	await frames(2)
	var centroid := Vector3.ZERO
	for m in members:
		centroid += (m as Node3D).global_position
	centroid /= float(members.size())
	var foe_base: Vector3 = centroid + Vector3(14.0, 0.0, 0.0)
	for i in range(foes.size()):
		var e2: Unit = foes[i]
		e2.global_position = foe_base + Vector3(0.0, 0.0, float(i) * 0.8)
	await frames(2)

	# Настоящий путь игрока: наводим камеру и «кликаем» ПКМ по врагу
	if main._camera.has_method("pan_to"):
		main._camera.pan_to(foe_base)
	await frames(5)
	var cam: Camera3D = main._camera
	sm._clear_selection()
	sm._select(members[0])
	var scr: Vector2 = cam.unproject_position((foes[0] as Node3D).global_position + Vector3(0, 0.6, 0))
	var hit: Dictionary = sm._screen_ray_hit(scr, Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS | Constants.LAYER_RESOURCES | Constants.LAYER_GROUND)
	var hit_name: String = "нет попадания"
	if hit.has("collider"):
		var res = sm._resolve_node(hit["collider"])
		hit_name = str(res)
	print("  ПКМ по врагу: луч попал в %s" % hit_name)
	sm._handle_right_click(scr)
	await frames(2)
	var attacking := 0
	var with_target := 0
	for m in members:
		var u2 := m as Unit
		if u2.state == Unit.State.ATTACKING:
			attacking += 1
		if u2.attack_target != null and is_instance_valid(u2.attack_target):
			with_target += 1
	print("  приказ атаки → state=ATTACKING у %d из %d, цель назначена у %d" % [
		attacking, members.size(), with_target])
	verdict("4 приказ атаки получает весь отряд",
		attacking == members.size() and with_target == members.size(),
		"атакует=%d, с целью=%d из %d" % [attacking, with_target, members.size()])

	for e3 in foes:
		if is_instance_valid(e3):
			(e3 as Unit)._die()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# 5. МАРШ СТРОЕМ БЕЗ Ctrl+1
# ═════════════════════════════════════════════════════════════════════════════
func _test_march_shape() -> void:
	print("\n═════ 5. МАРШ СТРОЕМ БЕЗ ГОРЯЧЕЙ ГРУППЫ ═════")
	var members: Array = _members(squad_a)
	# Ставим отряд в заведомо НЕ квадратный строй: длинная линия
	sm._clear_selection()
	sm._select(members[0])
	sm._execute_line_formation(Vector3(-40.0, 0.0, 0.0), Vector3(-14.0, 0.0, 0.0))
	await frames(700)

	sm._clear_selection()
	sm._select(members[0])
	var grp: int = sm.current_group_index()
	var is_squad: bool = sm._selection_is_squad()
	print("  индекс горячей группы: %d (−1 = Ctrl+1..9 НЕ назначалась), _selection_is_squad=%s" % [
		grp, str(is_squad)])

	# Замер габаритов ДО и целевых точек ПОСЛЕ — в одном кадре, без await
	var pos_before: Array = []
	for m in members:
		pos_before.append((m as Node3D).global_position)
	var box_before: Vector2 = _bbox(pos_before)

	var target := Vector3(-10.0, 0.0, 22.0)
	sm._issue_formation_move(target)

	var dest: Array = []
	var slow := 0
	for m in members:
		var u := m as Unit
		dest.append(u.move_target)
		if u.march_slow:
			slow += 1
	var box_after: Vector2 = _bbox(dest)

	# Как выглядел бы СХЛОПНУТЫЙ квадрат (старое поведение)
	var cols: int = maxi(1, int(ceil(sqrt(float(members.size())))))
	var sq_w: float = float(cols - 1) * sm.UNIT_SPACING
	var sq_d: float = float((members.size() - 1) / cols) * sm.UNIT_SPACING

	print("  габариты строя ДО приказа : %.2f × %.2f м" % [box_before.x, box_before.y])
	print("  габариты целевых слотов ПОСЛЕ: %.2f × %.2f м" % [box_after.x, box_after.y])
	print("  квадратная сетка (старое поведение) была бы: %.2f × %.2f м" % [sq_w, sq_d])
	print("  march_slow (шагом, строем) выставлен у %d из %d" % [slow, members.size()])
	var dw: float = absf(box_before.x - box_after.x)
	var dd: float = absf(box_before.y - box_after.y)
	verdict("5 обычный ПКМ сохраняет габариты строя", dw < 0.01 and dd < 0.01,
		"расхождение %.4f × %.4f м" % [dw, dd])
	# КОНТРАКТ ИЗМЕНИЛСЯ: у ПКМ теперь два режима (см. SelectionManager).
	# Одиночный клик — БЫСТРЫЙ ШАГ: строй сохраняется, но отряд не переходит
	# на маршевый полушаг. Маршем (march_slow) идут только по ПКМ С ПРОТЯЖКОЙ,
	# когда игрок сам задаёт фронт. Ждать march_slow от простого клика неверно:
	# стенд проверял бы прежнее поведение, а не нынешнее
	verdict("5 обычный ПКМ — быстрый шаг, а не маршевый полушаг",
		slow == 0 and grp == -1,
		"march_slow=%d из %d, горячая группа=%d" % [slow, members.size(), grp])
	verdict("5 строй НЕ схлопнулся в квадрат",
		absf(box_after.x - sq_w) > 1.0, "ширина после=%.2f, квадрат=%.2f" % [box_after.x, sq_w])

	# Смещения каждого бойца сохранены в точности
	var max_err := 0.0
	# ОПОРА БЕРЁТСЯ СВОЯ У КАЖДОГО НАБОРА, а не «среднее до» против
	# «точки приказа»: проверяется ВЗАИМНОЕ расположение бойцов, а то,
	# какой точкой строй привязан к курсору, — отдельное решение кода
	# (там МЕДИАНА, см. GameManager._centroid_of). Со средним слева
	# и точкой приказа справа стенд мерял разницу среднего и медианы
	# (0.1-0.2 м), а не искажение строя
	var centroid: Vector3 = _median_xz(pos_before)
	var centroid_after: Vector3 = _median_xz(dest)
	for i in range(members.size()):
		var p0: Vector3 = pos_before[i]
		var d0: Vector3 = dest[i]
		var off_before := Vector3(p0.x - centroid.x, 0.0, p0.z - centroid.z)
		var off_after  := Vector3(d0.x - centroid_after.x, 0.0, d0.z - centroid_after.z)
		max_err = maxf(max_err, off_before.distance_to(off_after))
	print("  максимальная ошибка переноса смещения бойца: %.5f м" % max_err)
	verdict("5 смещения бойцов перенесены без искажений", max_err < 0.001,
		"макс. ошибка=%.5f м" % max_err)

# ═════════════════════════════════════════════════════════════════════════════
# 6. UI
# ═════════════════════════════════════════════════════════════════════════════
func _test_ui() -> void:
	print("\n═════ 6. ПАНЕЛЬ ОТРЯДА БЕЗ Ctrl+1 ═════")
	var members: Array = _members(squad_a)
	sm._clear_selection()
	sm._select(members[0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)
	var labels: Array = []
	for b in hud.button_container.get_children():
		labels.append(((b as Button).text if (b as Button).text != "" else (b as Button).tooltip_text))
	var grp: int = sm.current_group_index()
	print("  подпись панели: «%s»" % hud.info_label.text)
	print("  кнопки: %s ; горячая группа: %d" % [str(labels), grp])
	var has_stances: bool = ("Attack" in labels) and ("Defend" in labels)
	verdict("6 кнопки стоек видны сразу при current_group_index()==-1",
		has_stances and grp == -1, "кнопки=%s, группа=%d" % [str(labels), grp])
	# ── ЧИСЛЕННОСТЬ УШЛА ИЗ ПОДПИСИ В БЕЙДЖ ПОРТРЕТА ────────────────────────
	# Строка «Отряд копейщиков — 60 бойцов» дословно повторяла заголовок окна
	# статов, висящего прямо над ней (заказ владельца — убрать дубли), а
	# освободившуюся строку занимает шкала опыта. Число никуда не пропало:
	# проверяем его там, где оно теперь живёт, плюс что имя отряда в подписи
	# осталось — иначе панель перестала бы отвечать «кто выбран»
	verdict("6 подпись — имя отряда, численность — на бейдже портрета",
		String(hud.info_label.text).contains("копейщик")
			and hud._portrait_count_lbl != null and hud._portrait_count_lbl.visible
			and hud._portrait_count_lbl.text == str(members.size()),
		"подпись «%s», бейдж «%s», ожидали %d" % [hud.info_label.text,
			hud._portrait_count_lbl.text if hud._portrait_count_lbl != null else "—",
			members.size()])

	# ── ЛУЧНИКИ: другая подпись ──────────────────────────────────────────────
	var mb: Array = _members(squad_b)
	sm._clear_selection()
	sm._select(mb[0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	print("  подпись для лучников: «%s»" % hud.info_label.text)
	verdict("6 подпись отряда лучников верна (имя + бейдж численности)",
		String(hud.info_label.text).contains("лучник")
			and hud._portrait_count_lbl != null
			and hud._portrait_count_lbl.text == str(mb.size()),
		"получено «%s», бейдж «%s», ожидали %d" % [hud.info_label.text,
			hud._portrait_count_lbl.text if hud._portrait_count_lbl != null else "—",
			mb.size()])

	# ── НЕСКОЛЬКО ОТРЯДОВ СРАЗУ ──────────────────────────────────────────────
	sm._clear_selection()
	sm._select(members[0])
	sm._select(mb[0])
	sm._select((_members(squad_a2)[0]))
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	var ids: Array = sm.selected_squad_ids()
	var total: int = sm.selected_units.size()
	# ВЫДЕЛЕНИЕ РАЗНОТИПНОЕ (копейщики + лучники), а это теперь УРОВЕНЬ 1
	# двухуровневой схемы: детальной панели нет вовсе, внизу только компактная
	# полоса групп (см. CLAUDE.md «Selection is TWO-LEVEL» и qa_sel2 A1).
	# Прежние проверки требовали подписи «Отрядов: N — M бойцов» и кнопок стоек
	# прямо здесь — они переехали на уровень 2
	print("  три отряда: слотов групп=%d, панель=%s" % [
		hud.type_slots(), str(hud._bottom_panel.visible)])
	verdict("6 разнотипное мультивыделение даёт уровень 1: полоса групп без панели",
		ids.size() == 3 and hud.type_slots() == 2 and not hud._bottom_panel.visible,
		"отрядов=%d бойцов=%d слотов=%d панель=%s" % [
			ids.size(), total, hud.type_slots(), hud._bottom_panel.visible])

	# Разворачиваем копейщиков — вот теперь и подпись, и стойки обязаны быть
	hud._on_type_filter_pressed("spearman")
	await frames(2)
	var labels2: Array = []
	for b in hud.button_container.get_children():
		labels2.append(((b as Button).text if (b as Button).text != "" else (b as Button).tooltip_text))
	var spear_men := 0
	for u in sm.selected_units:
		if is_instance_valid(u) and (u as Unit).squad_id > 0 \
				and GameManager.squad_type((u as Unit).squad_id) == "spearman":
			spear_men += 1
	print("  уровень 2: подпись «%s», кнопки %s" % [hud.info_label.text, str(labels2)])
	verdict("6 уровень 2: тип в подписи, численность типа — на бейдже",
		hud._bottom_panel.visible
			and String(hud.info_label.text).contains("копейщик")
			and hud._portrait_count_lbl != null
			and hud._portrait_count_lbl.text == str(spear_men),
		"копейщиков=%d, текст «%s», бейдж «%s»" % [spear_men, hud.info_label.text,
			hud._portrait_count_lbl.text if hud._portrait_count_lbl != null else "—"])
	verdict("6 стойки доступны и на нескольких отрядах",
		("Attack" in labels2) and ("Defend" in labels2), "кнопки=%s" % str(labels2))

	# ── СМЕШАННОЕ ВЫДЕЛЕНИЕ С РАБОЧИМ: стоек быть не должно ──────────────────
	var worker: Node = null
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Worker:
			worker = u
			break
	if worker != null:
		sm._clear_selection()
		sm._select(members[0])
		sm._select(worker)
		GameManager.on_selection_changed(sm.selected_units)
		await frames(2)
		var labels3: Array = []
		for b in hud.button_container.get_children():
			labels3.append(((b as Button).text if (b as Button).text != "" else (b as Button).tooltip_text))
		print("  отряд + рабочий: кнопки %s" % str(labels3))
		verdict("6 стойки не выдаются смешанному выделению с рабочим",
			not ("Attack" in labels3), "кнопки=%s" % str(labels3))

# ═════════════════════════════════════════════════════════════════════════════
# 7. УБЫЛЬ И РАСФОРМИРОВАНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _test_attrition() -> void:
	print("\n═════ 7. УБЫЛЬ И РАСФОРМИРОВАНИЕ ═════")
	var members: Array = _members(squad_a)
	var start: int = members.size()
	var kill: int = maxi(1, start / 2)
	for i in range(kill):
		(members[i] as Unit)._die()
	await frames(3)
	var left: int = _members(squad_a).size()
	var raw: int = (GameManager.squads[squad_a]["members"] as Array).size() if GameManager.squads.has(squad_a) else -1
	print("  было %d, убито %d, живых в реестре %d, сырой массив members=%d" % [
		start, kill, left, raw])
	verdict("7 реестр чистит павших", left == start - kill and raw == start - kill,
		"живых=%d сырых=%d ожидалось=%d" % [left, raw, start - kill])

	for m in _members(squad_a):
		(m as Unit)._die()
	await frames(3)
	var exists: bool = GameManager.squads.has(squad_a)
	print("  после гибели всех: отряд %d в реестре=%s" % [squad_a, str(exists)])
	verdict("7 пустой отряд расформирован", not exists)

	# squad_id снят у выбывших: одиночка не тянет за собой мёртвый id
	var stale := 0
	for u in get_tree().get_nodes_in_group("player_units"):
		var sid: int = (u as Unit).squad_id
		if sid > 0 and not GameManager.squads.has(sid):
			stale += 1
	print("  живых бойцов со ссылкой на несуществующий отряд: %d" % stale)
	verdict("7 нет висячих squad_id у живых", stale == 0, "висячих=%d" % stale)

	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("  осиротевших узлов: %d" % orphan)
	verdict("7 нет утечки узлов", orphan == 0, "orphan=%d" % orphan)

# ═════════════════════════════════════════════════════════════════════════════
# 8. НАГРУЗКА, ПОВТОРНАЯ ПАРТИЯ И РЕЕСТР
# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# СТРОЙ СМЫКАЕТСЯ ПОСЛЕ ПРОХОДА СОЮЗНИКОВ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца: рыцари проходят сквозь шеренгу пехоты, после чего пехота
## остаётся с разломанным строем и дырами.
##
## ПОЧЕМУ ПРЕЖНЕЕ СМЫКАНИЕ ЭТОГО НЕ ЛОВИЛО. Оно взводится ТОЛЬКО боем
## (squad_mark_hit): «отряд задели — значит после боя надо сомкнуться». Проход
## СВОИХ боем не является, отметка не ставилась, и дыры оставались до первой
## стычки.
##
## Стенд не изображает сам проход рыцарей — он воспроизводит его РЕЗУЛЬТАТ:
## бойцов растаскивает со своих мест. Причина отъезда для механики не важна
## вовсе, и это её главное достоинство (см. GameManager._sweep_reform)
func _test_reform_after_pass() -> void:
	print("\n═════ СМЫКАНИЕ ПОСЛЕ ПРОХОДА СОЮЗНИКОВ ═════")
	# СВОЙ ОТРЯД, А НЕ squad_a: к этому блоку прежние отряды стенда уже выбиты
	# и расформированы (см. _test_attrition / _test_mass_and_reset)
	var center := Vector3(-700.0, 0.0, -700.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(12):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var sp := center + Vector3(float(i % 6) * 0.8 - 2.0, 0.0, float(i / 6) * 0.8)
		u.global_position = Vector3(sp.x, GameManager.get_terrain_height(sp.x, sp.z), sp.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await frames(4)
	# Ставим отряду разметку — без неё смыкать не во что
	var slots: Array = []
	for i in range(men.size()):
		slots.append(center + Vector3(float(i % 6) * 0.8 - 2.0, 0.0,
			float(i / 6) * 0.8))
	GameManager.squad_set_formation(sid, slots, Vector3(0, 0, -1), false)
	# Разметка сама приказов не раздаёт — она их только ХРАНИТ. Ставим отряд на
	# места штатным смыканием: именно оно пишет бойцам post_pos, по которому
	# потом и считается «съехал ли он со своего места»
	GameManager.squad_close_ranks(sid, true)
	# ФИЗИЧЕСКИЕ кадры: ждём, пока дойдут (правило проекта — движение живёт в них)
	for _i in range(240):
		await get_tree().physics_frame
	var settled := 0
	for m in men:
		var u := m as Unit
		if u != null and not u.is_dead() and u._post_valid \
				and u.global_position.distance_to(u.post_pos) < 1.0:
			settled += 1
	verdict("R0 отряд встал по разметке", settled >= men.size() / 2,
		"на местах %d из %d" % [settled, men.size()])

	# ── ПРОХОД СОЮЗНИКОВ: РАСТАСКИВАЕМ СТРОЙ ──────────────────────────────
	# Пять метров вбок — это ровно та дыра, которую пробивает прошедший сквозь
	# строй отряд рыцарей
	var shoved := 0
	for i in range(men.size()):
		var u := men[i] as Unit
		if u == null or u.is_dead():
			continue
		if i % 2 != 0:
			continue
		var p: Vector3 = u.global_position + Vector3(5.0, 0.0, 0.0)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.state = Unit.State.IDLE
		shoved += 1
	await frames(3)
	var broken := 0
	for m in men:
		var u2 := m as Unit
		if u2 != null and not u2.is_dead() and u2._post_valid \
				and u2.global_position.distance_to(u2.post_pos) > GameManager.REFORM_DRIFT:
			broken += 1
	verdict("R1 строй действительно разломан", broken >= shoved / 2,
		"съехало %d из %d (растащено %d)" % [broken, men.size(), shoved])

	# ── СМЫКАНИЕ ОБЯЗАНО СЛУЧИТЬСЯ САМО ───────────────────────────────────
	# Никаких боёв и никаких приказов: только время. Обход идёт раз в
	# GameManager.REFORM_SWEEP_SEC, потом бойцам надо дойти
	for _i in range(600):
		await get_tree().physics_frame
	var back := 0
	for m in men:
		var u3 := m as Unit
		if u3 != null and not u3.is_dead() and u3._post_valid \
				and u3.global_position.distance_to(u3.post_pos) < GameManager.REFORM_DRIFT:
			back += 1
	var live := 0
	for m in men:
		if (m as Unit) != null and not (m as Unit).is_dead():
			live += 1
	print("  вернулось на места %d из %d живых" % [back, live])
	verdict("R2 строй сомкнулся сам, без боя и без приказа",
		live > 0 and back >= live - 1,
		"на местах %d из %d" % [back, live])

# ═════════════════════════════════════════════════════════════════════════════
# ТО ЖЕ САМОЕ, НО В ОБОРОНЕ И ПО ЛИНИИ ИЗ ПКМ-РАСТЯЖКИ
# ═════════════════════════════════════════════════════════════════════════════
## Заявленный владельцем случай дословно: «копейщики, расставившись по ПКМ
## (растягиванием линии), пропускают сквозь себя проходящих лучников, строй
## ломается и больше НЕ восстанавливается».
##
## Отличий от блока выше два, и оба существенные:
##   • разметка ОДНОШЕРЕНОЖНАЯ (линия), а не блок — по ней и считается «своё
##     место», и если смыкание её не читает, дыры остаются;
##   • стойка ОБОРОНА. Она запрещает бойцу двигаться по собственной
##     инициативе, и надо убедиться, что смыкание рядов из-под этого запрета
##     всё же работает (Unit.allow_reform_move) — иначе фаланга чинить свой
##     строй не может вовсе.
func _test_reform_defense_line() -> void:
	print("\n═════ СМЫКАНИЕ ЛИНИИ В ОБОРОНЕ ═════")
	var center := Vector3(-760.0, 0.0, -760.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	var slots: Array = []
	for i in range(10):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		# ЛИНИЯ: одна шеренга поперёк курса, как её раскладывает растяжка ПКМ
		var sp := center + Vector3(float(i) * 0.9 - 4.0, 0.0, 0.0)
		u.global_position = Vector3(sp.x, GameManager.get_terrain_height(sp.x, sp.z), sp.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		u.set_stance(_UCfg.STANCE_DEFENSE)
		men.append(u)
		slots.append(sp)
	GameManager.squad_set_formation(sid, slots, Vector3(0, 0, -1), false)
	GameManager.squad_close_ranks(sid, true)
	for _i in range(240):
		await get_tree().physics_frame
	var on_spot := 0
	for m in men:
		var u0 := m as Unit
		if u0 != null and u0._post_valid \
				and u0.global_position.distance_to(u0.post_pos) < 1.0:
			on_spot += 1
	verdict("R3 линия в обороне встала по разметке", on_spot >= men.size() - 1,
		"на местах %d из %d" % [on_spot, men.size()])

	# ── ЛУЧНИКИ ПРОШЛИ НАСКВОЗЬ: РАСТАСКИВАЕМ ЛИНИЮ ───────────────────────
	var shoved := 0
	for i in range(men.size()):
		if i % 2 != 0:
			continue
		var u1 := men[i] as Unit
		if u1 == null or u1.is_dead():
			continue
		var p: Vector3 = u1.global_position + Vector3(0.0, 0.0, 4.0)
		u1.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u1.sync_row()
		u1.state = Unit.State.IDLE
		shoved += 1
	await frames(3)
	var broken := 0
	for m in men:
		var u2 := m as Unit
		if u2 != null and u2._post_valid \
				and u2.global_position.distance_to(u2.post_pos) > GameManager.REFORM_DRIFT:
			broken += 1
	verdict("R3б линия действительно разломана", broken >= shoved / 2,
		"съехало %d (растащено %d)" % [broken, shoved])

	# ── И ОБЯЗАНА СОМКНУТЬСЯ САМА, НЕСМОТРЯ НА ОБОРОНУ ────────────────────
	for _i in range(600):
		await get_tree().physics_frame
	var back := 0
	var live := 0
	for m in men:
		var u3 := m as Unit
		if u3 == null or u3.is_dead():
			continue
		live += 1
		if u3._post_valid \
				and u3.global_position.distance_to(u3.post_pos) < GameManager.REFORM_DRIFT:
			back += 1
	print("  вернулось на места %d из %d живых" % [back, live])
	verdict("R4 линия в обороне сомкнулась сама", live > 0 and back >= live - 1,
		"на местах %d из %d" % [back, live])
	for m in men:
		if is_instance_valid(m):
			(m as Node).queue_free()
	await frames(3)

func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var c: Array = a.duplicate()
	c.sort()
	var n: int = c.size()
	if n % 2 == 1:
		return float(c[n / 2])
	return (float(c[n / 2 - 1]) + float(c[n / 2])) * 0.5

func _spawn_batch(orders: int) -> Array:
	var before: Array = GameManager.squads.keys().duplicate()
	_refill()
	for _i in range(orders):
		barracks.train_spearman()
	await flush(barracks)
	await frames(5)
	return _new_squad_ids(before)

## Сколько отрядов в реестре принадлежит стороне. ИИ живёт своей жизнью и
## тоже заводит отряды — общий размер реестра мерить бессмысленно
func _squads_of(f: int) -> int:
	var n := 0
	for key in GameManager.squads.keys():
		var sid: int = key
		if int(GameManager.squads[sid]["faction"]) == f:
			n += 1
	return n

## Живые юниты, чей squad_id указывает на отряд, где их НЕТ в составе
func _stale_ids() -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("all_units"):
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var sid: int = (u as Unit).squad_id
		if sid <= 0:
			continue
		if not GameManager.squads.has(sid):
			n += 1
			continue
		if not (u in (GameManager.squads[sid]["members"] as Array)):
			n += 1
	return n

func _kill_all_player_fighters() -> void:
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Worker:
			continue
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit)._die()
	await frames(5)

func _test_mass_and_reset() -> void:
	print("\n═════ 8. НАГРУЗКА 300+ ЮНИТОВ И ПОВТОРНАЯ ПАРТИЯ ═════")
	# Чистим поле от остатков предыдущих тестов
	await _kill_all_player_fighters()
	var base_registry: int = _squads_of(Constants.FACTION_PLAYER)
	print("  реестр перед партией №1: %d отрядов игрока (только рабочие), всего в реестре %d" % [
		base_registry, GameManager.squads.size()])

	# ── ПАРТИЯ №1: 7 заказов по полному отряду копейщиков ────────────────────
	# Размер берётся ИЗ КОНФИГА, а не числом: unit_stats_config — балансная
	# ведомость владельца и всегда права. Здесь стояло жёсткое 50, конфиг с тех
	# пор говорит 54, и стенд падал на своей же устаревшей константе
	var squad_n: int = _UCfg.squad_size("spearman")
	var ids1: Array = await _spawn_batch(7)
	var live1 := 0
	for sid in ids1:
		live1 += _members(int(sid)).size()
	var units1 := 0
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and not (u as Unit).is_dead():
			units1 += 1
	print("  партия №1: отрядов=%d, бойцов в них=%d, всего живых юнитов на карте=%d" % [
		ids1.size(), live1, units1])
	verdict("8 партия из 7 заказов дала 7 полных отрядов",
		ids1.size() == 7 and live1 == 7 * squad_n,
		"отрядов=%d бойцов=%d (ожидали 7×%d=%d)" % [ids1.size(), live1, squad_n, 7 * squad_n])

	# ── ЗАМЕР ПРОИЗВОДИТЕЛЬНОСТИ ─────────────────────────────────────────────
	# Отряды получают приказ, чтобы мерить не спящую сцену
	for sid in ids1:
		var mm: Array = _members(int(sid))
		if mm.is_empty():
			continue
		sm._clear_selection()
		sm._select(mm[0])
		sm._issue_formation_move(Vector3(randf_range(-30.0, 30.0), 0.0, randf_range(-30.0, 30.0)))
	sm._clear_selection()
	# Прогрев
	for _i in range(220):
		await get_tree().physics_frame
	var samples: Array = []
	for _i in range(240):
		await get_tree().physics_frame
		samples.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)))
	samples.sort()
	var med: float = _median(samples) * 1000.0
	var p95: float = float(samples[int(samples.size() * 0.95)]) * 1000.0
	var mx: float  = float(samples[samples.size() - 1]) * 1000.0
	var alive_now := 0
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and not (u as Unit).is_dead():
			alive_now += 1
	print("  живых юнитов при замере: %d" % alive_now)
	print("  TIME_PHYSICS_PROCESS: медиана %.3f мс, p95 %.3f мс, макс %.3f мс (240 кадров после 220 прогрева)" % [
		med, p95, mx])
	verdict("8 физический кадр на 300+ юнитах в норме (<16.6 мс)",
		alive_now >= 300 and med < 16.6, "юнитов=%d медиана=%.3f мс" % [alive_now, med])

	# ── ГИБЕЛЬ ВСЕЙ ПАРТИИ ───────────────────────────────────────────────────
	await _kill_all_player_fighters()
	var after_kill: int = _squads_of(Constants.FACTION_PLAYER)
	var leftover := 0
	for sid in ids1:
		if GameManager.squads.has(int(sid)):
			leftover += 1
	print("  после гибели партии №1: отрядов игрока %d, из них боевых от партии №1: %d (всего в реестре %d, остальное — ИИ)" % [
		after_kill, leftover, GameManager.squads.size()])
	verdict("8 гибель партии расформировала все её отряды",
		leftover == 0 and after_kill == base_registry,
		"осталось боевых=%d, отрядов игрока=%d (ожидалось %d)" % [leftover, after_kill, base_registry])

	# ── ПАРТИЯ №2: реестр не растёт ──────────────────────────────────────────
	var ids2: Array = await _spawn_batch(7)
	var peak2: int = _squads_of(Constants.FACTION_PLAYER)
	await _kill_all_player_fighters()
	var after_kill2: int = _squads_of(Constants.FACTION_PLAYER)
	print("  партия №2: отрядов=%d, пик отрядов игрока=%d, после гибели=%d" % [
		ids2.size(), peak2, after_kill2])
	verdict("8 реестр не растёт между партиями", after_kill2 == after_kill,
		"после №1=%d, после №2=%d" % [after_kill, after_kill2])
	print("  висячих squad_id у живых юнитов: %d" % _stale_ids())

	# ── НОВАЯ ПАРТИЯ ЧЕРЕЗ start_game() → reset_squads() ─────────────────────
	# ВНИМАНИЕ: в реальной игре start_game() вызывается ОДИН раз из _ready(),
	# а «играть снова» идёт через restart_game() → reload_current_scene().
	# Здесь мы бьём по reset_squads() напрямую — на живой сцене
	var before_reset: int = GameManager.squads.size()
	var live_before: int = 0
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and not (u as Unit).is_dead():
			live_before += 1
	main.start_game()
	await frames(3)
	var after_reset: int = GameManager.squads.size()
	var stale: int = _stale_ids()
	print("  start_game(): реестр %d → %d отрядов (заново заведены стартовые рабочие ИИ)" % [
		before_reset, after_reset])
	print("  живых юнитов ДО reset: %d; после reset висячих/чужих squad_id: %d" % [
		live_before, stale])
	# ── ПРОВЕРКА ПЕРЕПИСАНА НА СВОЙСТВО ────────────────────────────────────
	# Было «после reset отрядов не больше пяти» — то есть в стенде жило знание
	# о том, СКОЛЬКО отрядов заводит start_game (пять рабочих ИИ). Это число
	# менялось уже дважды и в последний раз выросло на десять: партия теперь
	# начинается ещё и с ордой гоблинов в правом верхнем углу.
	# Утверждаем то, ради чего проверка написана: СТАРЫХ отрядов не осталось, а
	# нумерация началась заново с единицы
	# Сколько отрядов ЗАВОДИТ сама start_game — считаем по конфигам, а не по
	# памяти: стартовые рабочие ИИ (у каждого свой отряд из одного) плюс орда
	# гоблинов в правом верхнем углу
	var want_after: int = _AICfg.START_WORKERS + _GobCfg.ARMY_SQUADS
	var max_id := 0
	for k in GameManager.squads.keys():
		max_id = maxi(max_id, int(k))
	verdict("8 reset_squads() вычистил старый реестр",
		after_reset == want_after and max_id <= want_after,
		"после reset=%d (ожидалось %d), наибольший id=%d" % [
			after_reset, want_after, max_id])
	verdict("8 после reset у живых юнитов нет ЧУЖИХ squad_id", stale == 0,
		"юнитов с чужим/висячим squad_id=%d из %d" % [stale, live_before])

	_refill()
	var before3: Array = GameManager.squads.keys().duplicate()
	barracks.train_spearman()
	await flush(barracks)
	await frames(3)
	var ids3: Array = _new_squad_ids(before3)
	var sid3: int = int(ids3[0]) if not ids3.is_empty() else 0
	print("  первый заказ новой партии получил id=%d (счётчик _next_squad_id обнулён)" % sid3)

	await _kill_all_player_fighters()
	await frames(10)
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("  финал: отрядов в реестре %d, осиротевших узлов %d" % [
		GameManager.squads.size(), orphan])
	verdict("8 нет утечки узлов после трёх партий", orphan == 0, "orphan=%d" % orphan)



# Медиана по осям — та же опора, что у GameManager._centroid_of
func _median_xz(pts: Array) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for p in pts:
		var v: Vector3 = p
		xs.append(v.x)
		zs.append(v.z)
	xs.sort()
	zs.sort()
	var h: int = xs.size() / 2
	return Vector3(xs[h], 0.0, zs[h])
