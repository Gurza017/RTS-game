extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_rally2 — ДЫРЫ ДВУХ ПАКЕТОВ (спавн/точка сбора, перехват/поводок)
## ═══════════════════════════════════════════════════════════════════════════
## qa_rally уже закрыл «спокойные» случаи. Здесь — то, что он не трогает:
##   A ПЕРЕХВАТ В ЖИВОМ БОЮ — стена из 20 врагов, приказ в точку ЗА их спиной.
##                            Считаем поштучно, сколько прошло насквозь.
##   B ОБХОД С ФЛАНГА       — та же стена, точка сбоку: перехват не должен
##                            превращаться в залипание на любой цели.
##   C ПОВОДОК              — пост, дальний враг, ближний враг, прямой приказ.
##   D ФЛАЖОК ЧЕРЕЗ ВВОД    — _handle_right_click с настоящей камерой, два
##                            здания с разными точками.
##   E СПАВН 50             — габарит пятна, вход в здание, следующий заказ.
##   F ГРАНИЧНЫЕ            — за краем карты, на здании, смена точки в найме,
##                            снос здания с флажком, два заказа подряд.

const SPEARMAN := preload("res://scenes/units/Spearman.tscn")
const ARCHER   := preload("res://scenes/units/Archer.tscn")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _trash: Array = []      # всё, что стенд создал и должен убрать за собой

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n: out += " "
	return out

# ── ПРИМИТИВЫ СТЕНДА ─────────────────────────────────────────────────────────

## Боец на позиции. Фракция ставится ДО входа в дерево (общая конвенция проекта)
func _mk_unit(scene: PackedScene, fac: int, pos: Vector3, sid: int = 0) -> Unit:
	var u: Unit = scene.instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(pos.x, GameManager.get_terrain_height(pos.x, pos.z), pos.z)
	if sid > 0:
		GameManager.add_to_squad(sid, u)
	_trash.append(u)
	return u

## Прямоугольный строй: cols колонн, шаг spacing, центр по X в center
func _mk_block(scene: PackedScene, fac: int, center: Vector3, n: int,
		cols: int, spacing: float, unit_id: String) -> Array:
	var sid: int = GameManager.new_squad(fac, unit_id)
	var out: Array = []
	for i in range(n):
		var col: int = i % cols
		var row: int = i / cols
		var p := center + Vector3((col - (cols - 1) * 0.5) * spacing, 0.0, row * spacing)
		out.append(_mk_unit(scene, fac, p, sid))
	return out

## Шеренга вдоль оси Z в точке x
func _mk_wall(fac: int, at_x: float, at_z: float, n: int, step: float) -> Array:
	var sid: int = GameManager.new_squad(fac, "spearman")
	var out: Array = []
	for i in range(n):
		var z: float = at_z + (float(i) - (n - 1) * 0.5) * step
		out.append(_mk_unit(SPEARMAN, fac, Vector3(at_x, 0.0, z), sid))
	return out

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _centroid(arr: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in arr:
		if not is_instance_valid(u): continue
		c += (u as Node3D).global_position
		n += 1
	return c / float(maxi(n, 1))

func _min_dist_to(arr: Array, p: Vector3) -> float:
	var d := INF
	for u in arr:
		if not is_instance_valid(u): continue
		var q: Vector3 = (u as Node3D).global_position
		d = minf(d, Vector2(q.x - p.x, q.z - p.z).length())
	return d

func _max_dist_to(arr: Array, p: Vector3) -> float:
	var d := 0.0
	for u in arr:
		if not is_instance_valid(u): continue
		var q: Vector3 = (u as Node3D).global_position
		d = maxf(d, Vector2(q.x - p.x, q.z - p.z).length())
	return d

## Габарит пятна отряда в плане: [ширина по X, глубина по Z]
func _extent(arr: Array) -> Array:
	var x0 := INF; var x1 := -INF; var z0 := INF; var z1 := -INF
	for u in arr:
		if not is_instance_valid(u): continue
		var p: Vector3 = (u as Node3D).global_position
		x0 = minf(x0, p.x); x1 = maxf(x1, p.x)
		z0 = minf(z0, p.z); z1 = maxf(z1, p.z)
	if x0 == INF:
		return [0.0, 0.0]
	return [x1 - x0, z1 - z0]

func _with_target(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and (u as Unit).attack_target != null:
			n += 1
	return n

## Ждать, пока все встанут (никто не MOVING), вернуть затраченные секунды
func _settle(units: Array, limit_ms: int) -> float:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < limit_ms:
		await get_tree().process_frame
		var moving := 0
		for u in units:
			if is_instance_valid(u) and (u as Unit).state == Unit.State.MOVING:
				moving += 1
		if moving == 0:
			break
	return float(Time.get_ticks_msec() - t0) / 1000.0

## Здание с мгновенным наймом
func _new_building(kind: String, at: Vector3) -> Building:
	var b: Building = Barracks.new() if kind == "barracks" else Castle.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(at.x, 0.0, at.z)
	_trash.append(b)
	return b

## Заказать отряд; дождаться, пока все size бойцов войдут в дерево
func _train(b: Building, unit_id: String, size: int, wait_ms: int = 20000) -> Array:
	var before: Array = get_tree().get_nodes_in_group("player_units").duplicate()
	b.squad_size = size
	b.queue_unit(unit_id, {}, 0.01)
	if not b.production_queue.is_empty():
		(b.production_queue[0] as Dictionary)["time"] = 0.01
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < wait_ms:
		await get_tree().process_frame
		if get_tree().get_nodes_in_group("player_units").size() >= before.size() + size:
			break
	var fresh: Array = []
	for n in get_tree().get_nodes_in_group("player_units"):
		if not (n in before):
			fresh.append(n)
			_trash.append(n)
	return fresh

func _sweep() -> void:
	for n in _trash:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_trash.clear()
	await frames(6)

# ═════════════════════════════════════════════════════════════════════════════

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	# ИИ спит: его отряды портят замеры расстояний и лезут в чужой бой
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	var probe: Unit = SPEARMAN.instantiate()
	main.world_add(probe)
	await frames(2)
	print("  копейщик: скорость %.2f м/с, дальность удара %.2f м, перехват до %.2f м" % [
		probe.move_speed, probe.attack_range, probe.attack_range + Unit.INTERCEPT_MARGIN])
	print("  поводок AGGRO_LEASH = %.1f м, радиус агро %.1f м" % [
		Unit.AGGRO_LEASH, Unit.AGGRO_RADIUS])
	probe.queue_free()
	await frames(2)

	await _a_intercept()
	await _b_flank()
	await _c_leash()
	await _d_flag_real_input()
	await _e_big_squad()
	await _f_edges()

	print("\n═════ ИТОГ qa_rally2 ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 64), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== RALLY2 TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ПЕРЕХВАТ В ЖИВОМ БОЮ
# ═════════════════════════════════════════════════════════════════════════════
# Стена из 20 вражеских копейщиков поперёк пути. Свой отряд из 20 получает
# приказ в точку ЗА их спиной. Считаем ПОШТУЧНО, сколько своих оказалось по ту
# сторону линии — это и есть «прошли призраками».
func _a_intercept() -> void:
	print("\n═════ A. ПЕРЕХВАТ В ЖИВОМ БОЮ ═════")
	var wall_x := 0.0
	var wall_z := -20.0
	var foes: Array = _mk_wall(Constants.FACTION_ENEMY, wall_x, wall_z, 20, 1.2)
	await frames(3)
	# Врагам назначаем ПОСТ на их же месте: так стоит любой отряд в игре
	for f in foes:
		(f as Unit).command_move((f as Node3D).global_position)

	var start := Vector3(wall_x - 11.0, 0.0, wall_z)
	var mine: Array = _mk_block(SPEARMAN, Constants.FACTION_PLAYER, start, 20, 5, 1.0, "spearman")
	await frames(3)

	var sm: SelectionManager = main.selection_manager
	sm._clear_selection()
	for u in mine:
		sm._select_one(u)
	var goal := Vector3(wall_x + 14.0, 0.0, wall_z)
	print("  стена x=%.1f (20 бойцов, ширина %.1f м), свой отряд x=%.1f, приказ в x=%.1f" % [
		wall_x, 19.0 * 1.2, start.x, goal.x])
	# Настоящий путь приказа движения по земле
	sm._issue_formation_move(goal)
	sm._clear_selection()

	var t0: int = Time.get_ticks_msec()
	var t_contact: float = -1.0
	var max_through := 0
	var max_through_span := 0
	var peak_engaged := 0
	while Time.get_ticks_msec() - t0 < 26000:
		await get_tree().process_frame
		var eng: int = _with_target(mine)
		if eng > 0 and t_contact < 0.0:
			t_contact = float(Time.get_ticks_msec() - t0) / 1000.0
		peak_engaged = maxi(peak_engaged, eng)
		# СЧИТАЕМ, ТОЛЬКО ПОКА СТЕНА ЖИВА.
		# Проверка ловит «прошли призраками» — то есть просочились СКВОЗЬ строй,
		# не вступив в бой. Пройти по трупам после того, как стену перебили, —
		# это не тот баг, а требуемое поведение: снеся заслон, отряд обязан
		# продолжить марш (см. Unit._resume_march). Пока условие звучало как
		# «за 26 секунд никто не оказался за линией», оно перестало их различать:
		# отряд честно выигрывал бой и шёл дальше, а стенд считал это провалом
		if _alive(foes).size() > 10:
			var thr := 0
			var thr_span := 0
			for u in mine:
				if not is_instance_valid(u) or (u as Unit).is_dead(): continue
				var p: Vector3 = (u as Node3D).global_position
				if p.x > wall_x + 1.5:
					thr += 1
					if absf(p.z - wall_z) <= 12.0:
						thr_span += 1
			max_through = maxi(max_through, thr)
			max_through_span = maxi(max_through_span, thr_span)

	var mine_alive: int = _alive(mine).size()
	var foes_alive: int = _alive(foes).size()
	print("  ИТОГИ БОЯ за 26 с:")
	print("    прошло за линию врага (x > %.1f): %d из 20" % [wall_x + 1.5, max_through])
	print("      из них внутри ширины строя врага: %d" % max_through_span)
	print("    бой завязался через %.2f с" % t_contact)
	print("    пик бойцов с целью: %d из 20" % peak_engaged)
	print("    живых: своих %d, врагов %d" % [mine_alive, foes_alive])

	verdict("A1 сквозь ЖИВУЮ вражескую шеренгу не прошёл никто",
		max_through == 0, "прошло %d (пока стена держалась)" % max_through)
	verdict("A2 бой действительно завязался", peak_engaged > 0,
		"с целью было %d" % peak_engaged)
	verdict("A3 контакт наступил быстро (<12 с)",
		t_contact >= 0.0 and t_contact < 12.0, "%.2f с" % t_contact)
	verdict("A4 в бой втянулась большая часть отряда (>=10)",
		peak_engaged >= 10, "пик %d" % peak_engaged)
	await _sweep()

# ═════════════════════════════════════════════════════════════════════════════
# B. ОБХОД С ФЛАНГА
# ═════════════════════════════════════════════════════════════════════════════
# Точка приказа сбоку от чужой линии. Отряд имеет полное право пройти по
# свободной земле — перехват не должен цепляться за врага «через полкарты».
func _b_flank() -> void:
	print("\n═════ B. ОБХОД С ФЛАНГА ═════")
	for pair in [[19.0, "широкий"], [12.0, "близкий"]]:
		var clearance: float = float((pair as Array)[0])
		var tag: String = String((pair as Array)[1])
		var wall_x := 0.0
		var wall_z := 30.0
		var foes: Array = _mk_wall(Constants.FACTION_ENEMY, wall_x, wall_z, 20, 1.2)
		await frames(3)
		for f in foes:
			(f as Unit).command_move((f as Node3D).global_position)
		# Идём ВДОЛЬ линии, отступив на clearance по X от её плоскости
		var start := Vector3(wall_x - clearance, 0.0, wall_z - 22.0)
		var goal  := Vector3(wall_x - clearance, 0.0, wall_z + 22.0)
		var mine: Array = _mk_block(SPEARMAN, Constants.FACTION_PLAYER, start, 20, 5, 1.0, "spearman")
		await frames(3)
		var sm: SelectionManager = main.selection_manager
		sm._clear_selection()
		for u in mine:
			sm._select_one(u)
		sm._issue_formation_move(goal)
		sm._clear_selection()

		var secs: float = await _settle(mine, 70000)
		var eng: int = _with_target(mine)
		var near_goal: float = _min_dist_to(mine, goal)
		var far_goal: float  = _max_dist_to(mine, goal)
		# Насколько близко отряд реально подходил к чужой шеренге
		var closest := INF
		for u in mine:
			if not is_instance_valid(u): continue
			closest = minf(closest, _min_dist_to(foes, (u as Node3D).global_position))
		print("  %s обход (зазор %.0f м): дошли за %.1f с, ближний %.1f м от точки, дальний %.1f м" % [
			tag, clearance, secs, near_goal, far_goal])
		print("    с целью залипло %d из 20, ближайшее сближение с врагом %.1f м" % [eng, closest])
		verdict("B%s отряд дошёл до точки в обход линии" % tag.substr(0, 1),
			near_goal <= 3.0, "ближний %.1f м" % near_goal)
		verdict("B%s перехват не залип на дальнем враге" % tag.substr(0, 1),
			eng == 0, "с целью %d" % eng)
		await _sweep()

# ═════════════════════════════════════════════════════════════════════════════
# C. ПОВОДОК
# ═════════════════════════════════════════════════════════════════════════════
func _c_leash() -> void:
	print("\n═════ C. ПОВОДОК ═════")
	var post := Vector3(-40.0, 0.0, 40.0)

	# ── C1: враг проходит в 20 м мимо. Сорваться нельзя ──────────────────────
	var guard: Unit = _mk_unit(SPEARMAN, Constants.FACTION_PLAYER, post)
	await frames(3)
	guard.command_move(post)              # ПОСТ = куда поставили
	await _settle([guard], 4000)
	var p_post: Vector3 = guard.global_position

	var walker: Unit = _mk_unit(SPEARMAN, Constants.FACTION_ENEMY,
		post + Vector3(20.0, 0.0, -18.0))
	await frames(3)
	walker.command_move(post + Vector3(20.0, 0.0, 18.0))
	var t0: int = Time.get_ticks_msec()
	var drift := 0.0
	var hooked := false
	while Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
		drift = maxf(drift, p_post.distance_to(guard.global_position))
		if guard.attack_target != null:
			hooked = true
	print("  враг прошёл в 20 м: цель взята=%s, сдвиг с поста %.2f м" % [str(hooked), drift])
	verdict("C1 боец не срывается на врага в 20 м от поста",
		not hooked and drift < 1.5, "цель=%s, сдвиг %.2f м" % [str(hooked), drift])
	walker.queue_free()
	await frames(4)

	# ── C2: враг подошёл на 5 м. Ответить, но не убегать ─────────────────────
	var close_foe: Unit = _mk_unit(SPEARMAN, Constants.FACTION_ENEMY,
		p_post + Vector3(5.0, 0.0, 0.0))
	close_foe.max_health = 100000.0     # мешок для битья: бой не должен кончиться
	close_foe.current_health = 100000.0
	await frames(3)
	close_foe.command_move(close_foe.global_position)
	var t1: int = Time.get_ticks_msec()
	var answered := false
	var drift2 := 0.0
	while Time.get_ticks_msec() - t1 < 10000:
		await get_tree().process_frame
		if guard.attack_target != null:
			answered = true
		drift2 = maxf(drift2, p_post.distance_to(guard.global_position))
	print("  враг в 5 м: ответил=%s, максимальный отход от поста %.2f м" % [str(answered), drift2])
	verdict("C2 боец отвечает на врага в 5 м от поста", answered)
	verdict("C3 отвечая, боец не сходит далеко с поста (<8 м)",
		drift2 < 8.0, "отход %.2f м" % drift2)
	close_foe.queue_free()
	guard.queue_free()
	await frames(5)

	# ── C4: НАСТОЯЩИЙ ПОВОДОК. У копейщика радиус обзора (10 м) меньше поводка
	# (14 м), поэтому AGGRO_LEASH на нём не срабатывает НИКОГДА. Проверяем на
	# лучнике: у него дальность 20 м, обзор тоже 20 м — вот там поводок и живёт
	var arch: Unit = _mk_unit(ARCHER, Constants.FACTION_PLAYER, post)
	await frames(3)
	print("  лучник: дальность %.1f м, обзор max(%.1f, %.1f) = %.1f м" % [
		arch.attack_range, Unit.AGGRO_RADIUS, arch.attack_range,
		maxf(Unit.AGGRO_RADIUS, arch.attack_range)])
	arch.command_move(post)
	await _settle([arch], 4000)
	var a_post: Vector3 = arch.global_position
	var far_foe: Unit = _mk_unit(SPEARMAN, Constants.FACTION_ENEMY,
		a_post + Vector3(0.0, 0.0, 18.0))
	far_foe.max_health = 100000.0
	far_foe.current_health = 100000.0
	await frames(3)
	far_foe.command_move(far_foe.global_position)
	var t2: int = Time.get_ticks_msec()
	var a_drift := 0.0
	while Time.get_ticks_msec() - t2 < 10000:
		await get_tree().process_frame
		a_drift = maxf(a_drift, a_post.distance_to(arch.global_position))
	print("  враг в 18 м (дальше поводка 14 м): лучник сдвинулся на %.2f м, цель=%s" % [
		a_drift, str(arch.attack_target != null)])
	verdict("C4 поводок держит лучника: за врагом в 18 м он не идёт",
		a_drift < 3.0, "сдвиг %.2f м" % a_drift)
	far_foe.queue_free()
	arch.queue_free()
	await frames(5)

	# ── C5: ПРЯМОЙ ПРИКАЗ через полкарты мимо врагов поводок не ограничивает ──
	var camp_z := 0.0
	var camp: Array = _mk_wall(Constants.FACTION_ENEMY, 0.0, camp_z, 12, 1.2)
	await frames(3)
	for f in camp:
		(f as Unit).command_move((f as Node3D).global_position)
	var from_p := Vector3(-35.0, 0.0, camp_z - 26.0)
	var to_p   := Vector3( 35.0, 0.0, camp_z - 26.0)
	var march: Array = _mk_block(SPEARMAN, Constants.FACTION_PLAYER, from_p, 10, 5, 1.0, "spearman")
	await frames(3)
	for u in march:
		(u as Unit).command_move(to_p + ((u as Node3D).global_position - from_p))
	var run_s: float = await _settle(march, 90000)
	var near_end: float = _min_dist_to(march, to_p)
	print("  марш %.0f м мимо лагеря врага (в %.0f м сбоку): дошли за %.1f с, ближний %.1f м" % [
		from_p.distance_to(to_p), 26.0, run_s, near_end])
	verdict("C5 прямой приказ через карту выполняется (поводок его не режет)",
		near_end <= 4.0, "ближний %.1f м" % near_end)
	await _sweep()

# ═════════════════════════════════════════════════════════════════════════════
# D. ФЛАЖОК ЧЕРЕЗ НАСТОЯЩИЙ ВВОД
# ═════════════════════════════════════════════════════════════════════════════
# Не _try_set_rally напрямую, а весь путь: камера → экранная точка →
# _handle_right_click → разбор клика → set_rally_point → маркер.
func _d_flag_real_input() -> void:
	print("\n═════ D. ФЛАЖОК ЧЕРЕЗ НАСТОЯЩИЙ ВВОД ═════")
	var sm: SelectionManager = main.selection_manager
	var cam: RTSCamera = main._camera
	var b1: Building = _new_building("barracks", Vector3(10.0, 0.0, 10.0))
	var b2: Building = _new_building("barracks", Vector3(30.0, 0.0, 10.0))
	await frames(3)

	# Чистим пятачок от деревьев и жил: разбор клика выбирает объект по близости
	# его основания к точке земли, и куст у самой точки честно перебьёт грунт
	var spot1 := Vector3(4.0, 0.0, 24.0)
	var spot2 := Vector3(36.0, 0.0, 24.0)
	var cleared := 0
	for r in get_tree().get_nodes_in_group("resource_nodes"):
		var p: Vector3 = (r as Node3D).global_position
		if Vector2(p.x - spot1.x, p.z - spot1.z).length() < 7.0 \
				or Vector2(p.x - spot2.x, p.z - spot2.z).length() < 7.0:
			(r as Node).queue_free()
			cleared += 1
	await frames(4)
	print("  убрано декораций у точек клика: %d" % cleared)

	cam._focus = Vector3(20.0, 0.0, 16.0)
	cam._target_height = 40.0
	cam._height = 40.0
	cam._update_position()
	await frames(6)
	print("  камера в (%.1f, %.1f, %.1f), кадр %s" % [
		cam.global_position.x, cam.global_position.y, cam.global_position.z,
		str(get_tree().root.size)])

	# ── ПКМ по земле при выделенном b1 ──────────────────────────────────────
	sm._clear_selection()
	sm._select_one(b1)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	var scr1: Vector2 = cam.unproject_position(spot1)
	var pick1: Dictionary = sm._pick_at(scr1,
		Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS | Constants.LAYER_RESOURCES | Constants.LAYER_GROUND)
	print("  клик 1: мир (%.1f, %.1f) → экран (%.0f, %.0f); разбор дал цель %s, землю (%.1f, %.1f)" % [
		spot1.x, spot1.z, scr1.x, scr1.y,
		"нет" if pick1["target"] == null else str(pick1["target"]),
		(pick1["position"] as Vector3).x, (pick1["position"] as Vector3).z])
	sm._handle_right_click(scr1)
	await frames(3)
	var err1: float = Vector2(b1.rally_point.x - spot1.x, b1.rally_point.z - spot1.z).length()
	print("  b1: has_rally=%s, точка (%.2f, %.2f), промах %.2f м" % [
		str(b1.has_rally), b1.rally_point.x, b1.rally_point.z, err1])
	verdict("D1 ПКМ настоящей мышью ставит точку сбора", b1.has_rally)
	verdict("D2 точка легла туда, куда целился клик (<1.5 м)",
		b1.has_rally and err1 < 1.5, "промах %.2f м" % err1)
	verdict("D3 флажок появился и стоит в точке",
		b1._rally_marker != null and is_instance_valid(b1._rally_marker)
		and Vector2(b1._rally_marker.global_position.x - b1.rally_point.x,
			b1._rally_marker.global_position.z - b1.rally_point.z).length() < 0.1)

	# ── Второе здание, вторая точка ─────────────────────────────────────────
	sm._clear_selection()
	sm._select_one(b2)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	var scr2: Vector2 = cam.unproject_position(spot2)
	sm._handle_right_click(scr2)
	await frames(3)
	var err2: float = Vector2(b2.rally_point.x - spot2.x, b2.rally_point.z - spot2.z).length()
	print("  b2: has_rally=%s, точка (%.2f, %.2f), промах %.2f м" % [
		str(b2.has_rally), b2.rally_point.x, b2.rally_point.z, err2])
	verdict("D4 второе здание получило СВОЮ точку, не перебив первую",
		b2.has_rally and err2 < 1.5
		and Vector2(b1.rally_point.x - spot1.x, b1.rally_point.z - spot1.z).length() < 1.5,
		"промах b2 %.2f м" % err2)

	# Выделен b2 → виден только его флажок
	var m1: Node3D = b1._rally_marker
	var m2: Node3D = b2._rally_marker
	print("  выделено b2: флажок b1 виден=%s, флажок b2 виден=%s" % [
		str(m1.visible) if m1 != null else "нет маркера",
		str(m2.visible) if m2 != null else "нет маркера"])
	verdict("D5 при выделенном b2 виден только его флажок",
		m1 != null and m2 != null and not m1.visible and m2.visible)

	# Переключаемся обратно на b1
	sm._clear_selection()
	sm._select_one(b1)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)
	print("  переключились на b1: флажок b1 виден=%s, флажок b2 виден=%s" % [
		str(m1.visible), str(m2.visible)])
	verdict("D6 переключение выделения переключает и флажки",
		m1.visible and not m2.visible)

	sm._clear_selection()
	# Маркеры живут в мире отдельно от зданий — убираем вручную
	if m1 != null and is_instance_valid(m1): m1.queue_free()
	if m2 != null and is_instance_valid(m2): m2.queue_free()
	await _sweep()

# ═════════════════════════════════════════════════════════════════════════════
# E. СПАВН БОЛЬШОГО ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _e_big_squad() -> void:
	print("\n═════ E. 50 КОПЕЙЩИКОВ ИЗ КРЕПОСТИ БЕЗ ТОЧКИ СБОРА ═════")
	var at := Vector3(-60.0, 0.0, 55.0)
	var b: Building = _new_building("castle", at)
	await frames(4)
	var gate: Vector3 = b._gate_position()
	print("  крепость в (%.0f, %.0f), габарит %.1f×%.1f, ворота (%.1f, %.1f)" % [
		at.x, at.z, b.build_size.x, b.build_size.z, gate.x, gate.z])

	var men: Array = await _train(b, "spearman", 50, 30000)
	print("  вышло бойцов: %d" % men.size())
	var secs: float = await _settle(men, 40000)
	var near_gate: float = _min_dist_to(men, gate)
	var far_gate: float  = _max_dist_to(men, gate)
	var ext: Array = _extent(men)
	print("  встали за %.1f с: первая шеренга %.2f м от ворот, последняя %.2f м" % [
		secs, near_gate, far_gate])
	print("  пятно отряда: %.1f м по X × %.1f м по Z" % [float(ext[0]), float(ext[1])])

	# Внутри габарита здания
	var inside := 0
	var hx: float = b.build_size.x * 0.5
	var hz: float = b.build_size.z * 0.5
	for u in men:
		if not is_instance_valid(u): continue
		var p: Vector3 = (u as Node3D).global_position
		if absf(p.x - at.x) <= hx and absf(p.z - at.z) <= hz:
			inside += 1
	print("  внутри коробки здания стоит: %d" % inside)

	verdict("E1 из крепости вышли все 50", men.size() == 50, "вышло %d" % men.size())
	verdict("E2 первая шеренга в 3–5 м от ворот",
		near_gate >= 3.0 and near_gate <= 5.0, "%.2f м" % near_gate)
	verdict("E3 отряд растёт ОТ здания наружу, а не уходит в поле (<20 м)",
		far_gate < 20.0, "последняя шеренга %.2f м" % far_gate)
	verdict("E4 никто не встал внутри габарита здания", inside == 0,
		"внутри %d" % inside)
	verdict("E5 сами ворота свободны (никого ближе 2 м)",
		near_gate >= 2.0, "ближайший %.2f м" % near_gate)

	# Следующий заказ: не должен упереться в предыдущий отряд
	var men2: Array = await _train(b, "spearman", 20, 20000)
	var secs2: float = await _settle(men2, 30000)
	var c1: Vector3 = _centroid(men)
	var c2: Vector3 = _centroid(men2)
	var gap: float = Vector2(c1.x - c2.x, c1.z - c2.z).length()
	# Сколько бойцов второго заказа стоит вплотную к чужому
	var jam := 0
	for u in men2:
		if not is_instance_valid(u): continue
		if _min_dist_to(men, (u as Node3D).global_position) < 0.45:
			jam += 1
	var near_gate2: float = _min_dist_to(men2, gate)
	print("  второй заказ (20): встал за %.1f с, ближний %.2f м от ворот" % [secs2, near_gate2])
	print("  расстояние между центрами отрядов %.2f м, вплотную к чужим %d из %d" % [
		gap, jam, men2.size()])
	verdict("E6 второй заказ вышел целиком", men2.size() == 20, "вышло %d" % men2.size())
	verdict("E7 отряды не наложились друг на друга (центры > 5 м)",
		gap > 5.0, "%.2f м" % gap)
	verdict("E8 второй отряд не застрял в первом (<3 вплотную)",
		jam < 3, "вплотную %d" % jam)
	await _sweep()

# ═════════════════════════════════════════════════════════════════════════════
# F. ГРАНИЧНЫЕ
# ═════════════════════════════════════════════════════════════════════════════
func _f_edges() -> void:
	print("\n═════ F. ГРАНИЧНЫЕ СЛУЧАИ ═════")

	# ── F1: точка сбора ЗА краем карты ──────────────────────────────────────
	var b: Building = _new_building("barracks", Vector3(100.0, 0.0, -45.0))
	await frames(3)
	b.set_rally_point(Vector3(900.0, 0.0, -45.0))
	var lim: Vector2 = GameManager.clamp_to_map(900.0, -45.0)
	print("  точка сбора за краем (900, −45) → зажата в (%.1f, %.1f), предел карты %.1f" % [
		b.rally_point.x, b.rally_point.z, lim.x])
	verdict("F1 точка сбора за краем карты зажата внутрь поля",
		absf(b.rally_point.x - lim.x) < 0.01 and absf(b.rally_point.x) < 130.0,
		"x=%.2f" % b.rally_point.x)
	var men: Array = await _train(b, "spearman", 10, 20000)
	var s1: float = await _settle(men, 40000)
	var d1: float = _min_dist_to(men, b.rally_point)
	print("  отряд дошёл за %.1f с, ближний %.2f м от зажатой точки" % [s1, d1])
	verdict("F2 отряд доходит до зажатой точки, а не виснет у стены",
		d1 <= 3.0, "ближний %.2f м" % d1)
	await _sweep()

	# ── F3: точка сбора НА САМОМ ЗДАНИИ ─────────────────────────────────────
	var b3: Building = _new_building("barracks", Vector3(-20.0, 0.0, -55.0))
	await frames(3)
	b3.set_rally_point(b3.global_position)
	var men3: Array = await _train(b3, "spearman", 10, 20000)
	var s3: float = await _settle(men3, 30000)
	var inside3 := 0
	for u in men3:
		if not is_instance_valid(u): continue
		var p: Vector3 = (u as Node3D).global_position
		if absf(p.x - b3.global_position.x) <= b3.build_size.x * 0.5 \
				and absf(p.z - b3.global_position.z) <= b3.build_size.z * 0.5:
			inside3 += 1
	# Не топчется ли отряд бесконечно
	var pos_a: Array = []
	for u in men3:
		pos_a.append((u as Node3D).global_position)
	await frames(120)
	var jitter := 0.0
	for i in range(men3.size()):
		if not is_instance_valid(men3[i]): continue
		jitter = maxf(jitter, (pos_a[i] as Vector3).distance_to((men3[i] as Node3D).global_position))
	print("  точка сбора на здании: встали за %.1f с, внутри коробки %d из %d, дрожь за 2 с %.2f м" % [
		s3, inside3, men3.size(), jitter])
	verdict("F3 точка сбора на здании не подвешивает отряд (нет вечной ходьбы)",
		s3 < 25.0 and jitter < 1.0, "встали за %.1f с, дрожь %.2f м" % [s3, jitter])
	await _sweep()

	# ── F4: СМЕНА ТОЧКИ ВО ВРЕМЯ НАЙМА ──────────────────────────────────────
	var b4: Building = _new_building("barracks", Vector3(-20.0, 0.0, 20.0))
	await frames(3)
	var r_old := Vector3(-2.0, 0.0, 20.0)
	var r_new := Vector3(-20.0, 0.0, 42.0)
	b4.set_rally_point(r_old)
	var before4: Array = get_tree().get_nodes_in_group("player_units").duplicate()
	b4.squad_size = 20
	b4.queue_unit("spearman", {}, 0.01)
	(b4.production_queue[0] as Dictionary)["time"] = 0.01
	# Ждём, пока выйдет примерно половина, и на ходу переставляем точку
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
		if get_tree().get_nodes_in_group("player_units").size() >= before4.size() + 8:
			break
	b4.set_rally_point(r_new)
	print("  точка переставлена, когда вышло %d из 20" % [
		get_tree().get_nodes_in_group("player_units").size() - before4.size()])
	var t1: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 15000:
		await get_tree().process_frame
		if get_tree().get_nodes_in_group("player_units").size() >= before4.size() + 20:
			break
	var men4: Array = []
	for n in get_tree().get_nodes_in_group("player_units"):
		if not (n in before4):
			men4.append(n)
			_trash.append(n)
	var s4: float = await _settle(men4, 40000)
	var to_old := 0
	var to_new := 0
	for u in men4:
		if not is_instance_valid(u): continue
		var p: Vector3 = (u as Node3D).global_position
		var do_: float = Vector2(p.x - r_old.x, p.z - r_old.z).length()
		var dn: float = Vector2(p.x - r_new.x, p.z - r_new.z).length()
		if do_ < dn: to_old += 1
		else:        to_new += 1
	print("  вышло %d за %.1f с: у СТАРОЙ точки %d, у НОВОЙ %d" % [
		men4.size(), s4, to_old, to_new])
	verdict("F4 смена точки во время найма не рвёт отряд надвое",
		to_old == 0 or to_new == 0, "старая %d / новая %d" % [to_old, to_new])
	await _sweep()

	# ── F5: СНОС ЗДАНИЯ С АКТИВНЫМ ФЛАЖКОМ ──────────────────────────────────
	var b5: Building = _new_building("barracks", Vector3(60.0, 0.0, -20.0))
	await frames(3)
	b5.set_rally_point(Vector3(70.0, 0.0, -10.0))
	b5.set_selected(true)
	await frames(2)
	var mk: Node3D = b5._rally_marker
	var host: Node = mk.get_parent()
	var orphans_before: int = _count_markers()
	print("  флажок создан, родитель: %s (здание: %s); маркеров в дереве: %d" % [
		str(host.name), str(b5.name), orphans_before])
	verdict("F5 флажок вообще есть до сноса", mk != null and mk.visible)
	b5.take_damage(1e9, null)
	await frames(10)
	var alive_marker: bool = is_instance_valid(mk)
	var orphans_after: int = _count_markers()
	print("  после сноса: маркер жив=%s, маркеров в дереве было %d, стало %d" % [
		str(alive_marker), orphans_before, orphans_after])
	verdict("F6 снос здания убирает флажок (нет осиротевшего узла)",
		not alive_marker and orphans_after < orphans_before,
		"маркер жив=%s, маркеров %d→%d" % [str(alive_marker), orphans_before, orphans_after])
	if alive_marker:
		mk.queue_free()
	await _sweep()

	# ── F7: ДВА ЗАКАЗА ПОДРЯД С РАЗНЫМИ ТОЧКАМИ ─────────────────────────────
	var b7: Building = _new_building("barracks", Vector3(-70.0, 0.0, -20.0))
	await frames(3)
	var p1 := Vector3(-52.0, 0.0, -20.0)
	var p2 := Vector3(-70.0, 0.0, -2.0)
	b7.set_rally_point(p1)
	var sq1: Array = await _train(b7, "spearman", 10, 20000)
	b7.set_rally_point(p2)
	var sq2: Array = await _train(b7, "spearman", 10, 20000)
	await _settle(sq1 + sq2, 40000)
	var d_1: float = _min_dist_to(sq1, p1)
	var d_2: float = _min_dist_to(sq2, p2)
	var wrong1 := 0
	for u in sq1:
		if not is_instance_valid(u): continue
		var p: Vector3 = (u as Node3D).global_position
		if Vector2(p.x - p2.x, p.z - p2.z).length() < Vector2(p.x - p1.x, p.z - p1.z).length():
			wrong1 += 1
	print("  заказ 1 → точка 1: ближний %.2f м, ушедших к чужой точке %d" % [d_1, wrong1])
	print("  заказ 2 → точка 2: ближний %.2f м" % d_2)
	verdict("F7 первый заказ остался у своей точки", d_1 <= 3.0 and wrong1 == 0,
		"ближний %.2f м, чужих %d" % [d_1, wrong1])
	# ВНИМАНИЕ: _exit_lane у здания только РАСТЁТ и не сбрасывается, а полоса
	# выхода прибавляется и к назначенной точке сбора. Поэтому второй заказ
	# встаёт не НА флажок, а в стороне от него на шаг полосы (~6 м), третий —
	# ещё дальше. Проверяем именно это число
	verdict("F8 второй заказ приходит В СВОЮ точку, а не в стороне от флажка",
		d_2 <= 3.0, "ближний %.2f м" % d_2)
	await _sweep()

## Сколько узлов флажка живёт в дереве прямо сейчас. Godot переименовывает
## одноимённых соседей (RallyMarker2, RallyMarker3…), поэтому сверяем префикс
func _count_markers() -> int:
	var n := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if String(node.name).begins_with("RallyMarker"):
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n
