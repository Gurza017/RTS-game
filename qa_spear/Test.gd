extends Node

## СТЕНД: НОВЫЕ МЕХАНИКИ КОПЕЙЩИКОВ (части 1, 2 задания)
##
## Разделы:
##   A — спавн у ворот: точка выхода у фасада, квадратный строй, выход рядами
##   B — подтягивание хвоста: +15% отставшим, когда первые ряды встали
##   C — отступление в замок: сброс режимов, отказ от боя, лечение, возврат
##   D — агро-радиус: обстрел ближе 12 поднимает отряд, дальше — нет
##   E — смыкание строя после боя и приоритет первых рядов
##   F — темп фаланги: атака из Defense медленнее обычного хода

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main: Node = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

## Ждать по НАСТЕННЫМ часам: часть механик завязана на Time.get_ticks_msec(),
## а headless крутит кадры быстрее реального времени
func wait_ms(ms: int) -> void:
	var end: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _mk_squad(kind: String, n: int, at: Vector3, cols: int = 0) -> Dictionary:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var c: int = cols if cols > 0 else Building.square_cols(n)
	var men: Array = []
	for i in range(n):
		var u: Unit = load("res://scenes/units/%s.tscn" % kind.capitalize()).instantiate()
		u.faction = Constants.FACTION_PLAYER
		get_tree().root.add_child(u)
		u.global_position = at + Vector3(
			float(i % c) * 0.7, 0.0, float(i / c) * 0.7)
		u.post_pos = u.global_position
		u.set("_post_valid", true)
		u.formation_row = i / c
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return {"sid": sid, "men": men}

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	# ОТСЕЧЕНИЕ ДАЛЬНИХ СПРАЙТОВ СНИМАЕМ. Площадки стенда вынесены за сотни
	# метров от точки обзора камеры, то есть заведомо за lod_radius: поза там
	# не пересчитывается вовсе, а вместе с ней не выполняется и решение об
	# опускании копья (оно принимается внутри Spearman._spear_leveled, которую
	# зовёт именно обновление позы)
	preload("res://scripts/perf_config.gd").sprite_lod = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 500000.0)
	await frames(1)

	await _test_gate_spawn()
	await _test_catch_up()
	await _test_retreat()
	await _test_aggro_band()
	await _test_reform()
	await _test_phalanx_pace()

	print("\n=== ИТОГ qa_spear: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. СПАВН У ВОРОТ КВАДРАТНЫМ СТРОЕМ
# ═════════════════════════════════════════════════════════════════════════════
## Свои копейщики, вышедшие из этого здания (в радиусе r от него)
func _spawned_near(b: Building, r: float) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("player_units"):
		var u := n as Spearman
		if u == null or u.is_dead():
			continue
		if u.global_position.distance_to(b.global_position) <= r:
			out.append(u)
	return out

func _test_gate_spawn() -> void:
	print("\n═════ A. СПАВН У ВОРОТ ═════")
	# Квадрат считается по составу, а не по прибитым в конфиге пяти колоннам
	verdict("A1 квадрат для 20 бойцов = 5 колонн",
		Building.square_cols(20) == 5, "получили %d" % Building.square_cols(20))
	verdict("A2 квадрат для 10 бойцов = 4 колонны (а не полоса 5×2)",
		Building.square_cols(10) == 4, "получили %d" % Building.square_cols(10))
	verdict("A3 квадрат для 9 = 3 колонны",
		Building.square_cols(9) == 3, "получили %d" % Building.square_cols(9))

	# Барак в стороне от центра: ворота обязаны смотреть НА ЦЕНТР карты,
	# а не в прибитый мировой +X
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(-40, 0, -40)
	await frames(3)
	var gate: Vector3 = b._gate_position()
	var to_centre := (Vector3.ZERO - b.global_position)
	to_centre.y = 0.0
	to_centre = to_centre.normalized()
	var gate_dir := gate - b.global_position
	gate_dir.y = 0.0
	var align: float = gate_dir.normalized().dot(to_centre)
	print("  барак на %s, ворота на %s" % [str(b.global_position), str(gate)])
	verdict("A4 ворота смотрят на середину карты", align > 0.99,
		"совпадение направлений %.3f" % align)
	var wall: float = maxf(b.build_size.x, b.build_size.z) * 0.5
	var reach: float = gate_dir.length()
	verdict("A5 точка выхода у стены фасада, а не в поле",
		reach > wall and reach < wall + 2.0,
		"вынос %.2f м при полугабарите %.2f" % [reach, wall])

	# Выход рядами: заказ уходит не сплошной ниткой, а шеренгами с паузой
	b.squad_size = 12
	b.squad_cols = 4
	# Считаем ВЫШЕДШИХ НАПРЯМУЮ, а не через номер отряда: номер, снятый заранее,
	# успевает достаться чужому заказу (базу противника Main достраивает
	# отложенно и заводит свои отряды), а перебор «последнего непустого отряда»
	# пропускает запись, пока бойцы ещё стоят в очереди на вход в дерево
	var ok: bool = b.queue_unit("spearman", {}, 0.05)
	verdict("A6 заказ принят", ok)
	# Ждём ПОЯВЛЕНИЯ первого бойца, а не фиксированное число кадров: заказ
	# отрабатывает по таймеру производства, а вход в дерево идёт отложенно
	var t_wait: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_wait < 2000:
		await get_tree().process_frame
		if _spawned_near(b, 30.0).size() > 0:
			break
	await frames(1)
	var first_batch: int = _spawned_near(b, 30.0).size()
	await wait_ms(140)
	var mid_batch: int = _spawned_near(b, 30.0).size()
	await wait_ms(1200)
	var full: int = _spawned_near(b, 30.0).size()
	print("  вышло: сразу %d, через 0.14 с %d, через 1.4 с %d" % [
		first_batch, mid_batch, full])
	verdict("A7 первая шеренга выходит целиком, а не по два бойца",
		first_batch >= 3, "в первой партии %d" % first_batch)
	verdict("A8 между шеренгами есть пауза",
		mid_batch < 12, "через 0.14 с уже %d из 12" % mid_batch)
	verdict("A9 отряд вышел полностью", full == 12, "вышло %d" % full)

	# И построился квадратом: ширина примерно равна глубине
	var men := _spawned_near(b, 30.0)
	await wait_ms(600)
	var minx := INF; var maxx := -INF; var minz := INF; var maxz := -INF
	for m in men:
		var p: Vector3 = (m as Node3D).global_position
		minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
		minz = minf(minz, p.z); maxz = maxf(maxz, p.z)
	var w: float = maxx - minx
	var d: float = maxz - minz
	var ratio: float = maxf(w, d) / maxf(minf(w, d), 0.01)
	print("  пятно отряда: %.2f × %.2f м, соотношение сторон %.2f" % [w, d, ratio])
	verdict("A10 пятно отряда близко к квадрату", ratio < 2.2,
		"соотношение %.2f" % ratio)

	for m in men:
		(m as Node).queue_free()
	b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. ПОДТЯГИВАНИЕ ХВОСТА
# ═════════════════════════════════════════════════════════════════════════════
func _test_catch_up() -> void:
	print("\n═════ B. ПОДТЯГИВАНИЕ ХВОСТА (+15%) ═════")
	verdict("B1 прибавка ровно +15%",
		absf(Unit.CATCH_UP_FACTOR - 1.15) < 0.001,
		"CATCH_UP_FACTOR=%.3f" % Unit.CATCH_UP_FACTOR)

	var sq := _mk_squad("spearman", 12, Vector3(100, 0, 100))
	var sid: int = sq["sid"]
	var men: Array = sq["men"]
	await frames(2)
	# Разметка строя обнуляет счётчик дошедших
	GameManager.squad_set_formation(sid, [Vector3(100, 0, 100)], Vector3.FORWARD, false)
	verdict("B2 новый приказ снимает прибавку",
		not GameManager.squad_catching_up(sid))

	# Пока дошло меньше порога — прибавки нет
	for i in range(3):
		GameManager.squad_note_arrival(sid)
	verdict("B3 при 3 дошедших из 12 прибавки ещё нет",
		not GameManager.squad_catching_up(sid),
		"порог %.0f%%" % (GameManager.CATCH_UP_TRIGGER * 100.0))
	GameManager.squad_note_arrival(sid)
	GameManager.squad_note_arrival(sid)
	verdict("B4 перевалило за порог — прибавка включилась",
		GameManager.squad_catching_up(sid))

	# И она реально попадает в скорость отстающего
	var u: Unit = men[0]
	u.state = Unit.State.MOVING
	u.march_slow = false
	var fast: float = u._effective_speed()
	# ЧЕРЕЗ API, А НЕ ПРЯМОЙ ЗАПИСЬЮ В СЛОВАРЬ: прибавку отряд теперь РАЗДАЁТ
	# бойцам в момент переключения (GameManager.squad_set_catch_up), а не
	# опрашивается каждым идущим в каждом кадре
	GameManager.squad_set_catch_up(sid, false)
	var slow: float = u._effective_speed()
	print("  скорость отставшего: без прибавки %.3f, с прибавкой %.3f" % [slow, fast])
	verdict("B5 отстающий едет ровно на 15% быстрее",
		absf(fast / maxf(slow, 0.001) - 1.15) < 0.01,
		"отношение %.4f" % (fast / maxf(slow, 0.001)))

	# Дошедший (IDLE) прибавку НЕ получает — иначе строй разъезжался бы
	GameManager.squad_set_catch_up(sid, true)
	u.state = Unit.State.IDLE
	var idle_spd: float = u._effective_speed()
	u.state = Unit.State.MOVING
	verdict("B6 уже вставший на место прибавки не получает",
		absf(idle_spd - slow) < 0.001,
		"стоящий %.3f, базовая %.3f" % [idle_spd, slow])

	for m in men:
		(m as Node).queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. ОТСТУПЛЕНИЕ В ЗАМОК
# ═════════════════════════════════════════════════════════════════════════════
func _test_retreat() -> void:
	print("\n═════ C. ОТСТУПЛЕНИЕ В ЗАМОК ═════")
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-60, 0, -60)
	await frames(3)

	var sq := _mk_squad("spearman", 6, Vector3(-40, 0, -40))
	var sid: int = sq["sid"]
	var men: Array = sq["men"]
	# Отряд в бою: стойка обороны, назначенная цель, разметка строя
	var foe: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	foe.faction = Constants.FACTION_ENEMY
	get_tree().root.add_child(foe)
	foe.global_position = Vector3(-39, 0, -40)
	foe.max_health = 1e9; foe.current_health = 1e9
	await frames(3)
	for m in men:
		var u := m as Unit
		u.set_stance("defense")
		u.command_attack(foe, true, true)
	GameManager.squad_set_formation(sid, [Vector3(-40, 0, -40)], Vector3.FORWARD, false)
	await frames(3)
	var in_fight := 0
	for m in men:
		if (m as Unit).attack_target != null:
			in_fight += 1
	verdict("C1 отряд действительно в бою", in_fight > 0,
		"с целью %d из %d" % [in_fight, men.size()])

	# Кнопка «в замок»
	var accepted: bool = castle.request_garrison(sid)
	await frames(2)
	verdict("C2 замок принял заявку на отступление", accepted)
	var retreating := 0
	var cleared_stance := 0
	var cleared_target := 0
	for m in men:
		var u := m as Unit
		if u.retreating: retreating += 1
		if not u._stance_holds_ground(): cleared_stance += 1
		if u.attack_target == null: cleared_target += 1
	verdict("C3 все перешли в режим отхода", retreating == men.size(),
		"%d из %d" % [retreating, men.size()])
	verdict("C4 стойка обороны сброшена", cleared_stance == men.size(),
		"%d из %d" % [cleared_stance, men.size()])
	verdict("C5 боевая цель сброшена", cleared_target == men.size(),
		"%d из %d" % [cleared_target, men.size()])
	verdict("C6 разметка строя снята",
		not GameManager.squad_has_formation(sid))

	# Урон по дороге НЕ разворачивает отряд обратно в бой
	for m in men:
		(m as Unit).take_damage(5.0, foe)
	await frames(3)
	var still_going := 0
	for m in men:
		var u := m as Unit
		if u.attack_target == null and u.retreating:
			still_going += 1
	verdict("C7 входящий урон не втягивает отступающих в бой",
		still_going == men.size(), "%d из %d" % [still_going, men.size()])
	verdict("C8 урон при этом проходит (отряд не бессмертен)",
		(men[0] as Unit).current_health < (men[0] as Unit).max_health)

	# Доходят до ворот и всасываются внутрь
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
		var inside := 0
		for m in men:
			if is_instance_valid(m) and (m as Unit).garrisoned:
				inside += 1
		if inside == men.size():
			break
	var inside_now := 0
	for m in men:
		if is_instance_valid(m) and (m as Unit).garrisoned:
			inside_now += 1
	verdict("C9 отряд дошёл до замка и зашёл внутрь",
		inside_now == men.size(), "внутри %d из %d" % [inside_now, men.size()])
	if inside_now == men.size():
		verdict("C10 режим отхода снят на входе",
			not (men[0] as Unit).retreating)

	# Лечение внутри
	var hp_before: float = (men[0] as Unit).current_health
	await wait_ms(1500)
	var hp_after: float = (men[0] as Unit).current_health
	verdict("C11 внутри замка раненых лечат", hp_after > hp_before,
		"было %.1f, стало %.1f" % [hp_before, hp_after])

	# ПРОТИВНИКА УБИРАЕМ ДО ВЫПУСКА. Проверяем «вылеченный отряд сам уходит на
	# точку сбора», а вышедший из ворот отряд — уже обычный, без режима отхода:
	# заметив рядом врага, он совершенно правильно бросается на него, и марш
	# на флажок при этом прерывается. С живым врагом рядом проверять марш
	# бессмысленно — мерили бы авто-агро, а не возврат
	foe.queue_free()
	await frames(2)

	# Выпуск наружу — на точку сбора, строем
	castle.rally_point = Vector3(-20, 0, -20)
	castle.has_rally = true
	var released: bool = castle.release_garrison(sid)
	# Выпуск идёт через release_unit + command_move на каждого; даём кадрам
	# отработать, иначе последний из шестерых ловится ещё внутри стен
	await wait_ms(250)
	verdict("C12 отряд выпущен наружу", released)
	var outside := 0
	for m in men:
		if not (m as Unit).garrisoned:
			outside += 1
	verdict("C12b все шестеро оказались снаружи", outside == men.size(),
		"снаружи %d из %d" % [outside, men.size()])
	# «Идёт ИЛИ уже пришёл»: ближний к флажку боец успевает дойти за те же
	# кадры, что мы ждём, и честно переходит в IDLE — это не провал марша
	var out_ok := 0
	for m in men:
		var u := m as Unit
		if u.garrisoned:
			continue
		if u.state == Unit.State.MOVING \
				or u.global_position.distance_to(u.move_target) < 1.0:
			out_ok += 1
	verdict("C13 вышедшие идут на точку сбора (или уже дошли)",
		out_ok == men.size(), "%d из %d" % [out_ok, men.size()])
	var toward := 0
	for m in men:
		if (m as Unit).move_target.distance_to(Vector3(-20, 0, -20)) < 6.0:
			toward += 1
	verdict("C14 цель марша — именно точка сбора", toward == men.size(),
		"%d из %d" % [toward, men.size()])

	for m in men:
		if is_instance_valid(m): (m as Node).queue_free()
	castle.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. АГРО-РАДИУС ПО СТРЕЛКАМ
# ═════════════════════════════════════════════════════════════════════════════
func _test_aggro_band() -> void:
	print("\n═════ D. АГРО НА ЛУЧНИКОВ (10–12) ═════")
	verdict("D1 порог ответной атаки лежит в диапазоне 10–12",
		Unit.COUNTER_CHARGE_RANGE >= 10.0 and Unit.COUNTER_CHARGE_RANGE <= 12.0,
		"COUNTER_CHARGE_RANGE=%.1f" % Unit.COUNTER_CHARGE_RANGE)
	verdict("D2 радиус собственного обзора не меньше 10",
		Unit.AGGRO_RADIUS >= 10.0, "AGGRO_RADIUS=%.1f" % Unit.AGGRO_RADIUS)

	# Стрелок ВНУТРИ полосы: отряд обязан подняться
	var near_sq := _mk_squad("spearman", 6, Vector3(200, 0, 200))
	var shooter: Unit = load("res://scenes/units/Archer.tscn").instantiate()
	shooter.faction = Constants.FACTION_ENEMY
	get_tree().root.add_child(shooter)
	shooter.global_position = Vector3(200, 0, 211)      # ~11 м
	shooter.max_health = 1e9; shooter.current_health = 1e9
	await frames(3)
	var dist_near: float = (near_sq["men"][0] as Node3D).global_position \
		.distance_to(shooter.global_position)
	for m in near_sq["men"]:
		(m as Unit).take_damage(3.0, shooter)
	await frames(4)
	var roused := 0
	for m in near_sq["men"]:
		var u := m as Unit
		if u.attack_target != null or u.state == Unit.State.ATTACKING:
			roused += 1
	print("  стрелок в %.1f м: поднялось %d из 6" % [dist_near, roused])
	verdict("D3 обстрел ближе 12 м поднимает отряд",
		roused >= 4, "поднялось %d из 6 (дистанция %.1f)" % [roused, dist_near])

	# Стрелок ЗА полосой: отряд стоит
	var far_sq := _mk_squad("spearman", 6, Vector3(300, 0, 300))
	var sniper: Unit = load("res://scenes/units/Archer.tscn").instantiate()
	sniper.faction = Constants.FACTION_ENEMY
	get_tree().root.add_child(sniper)
	sniper.global_position = Vector3(300, 0, 318)       # ~18 м
	sniper.max_health = 1e9; sniper.current_health = 1e9
	await frames(3)
	var dist_far: float = (far_sq["men"][0] as Node3D).global_position \
		.distance_to(sniper.global_position)
	var home: Array = []
	for m in far_sq["men"]:
		home.append((m as Node3D).global_position)
	for m in far_sq["men"]:
		(m as Unit).take_damage(3.0, sniper)
	await frames(6)
	var charged := 0
	for i in range(far_sq["men"].size()):
		var u: Unit = far_sq["men"][i]
		if (u as Node3D).global_position.distance_to(home[i] as Vector3) > 2.0:
			charged += 1
	print("  стрелок в %.1f м: сорвалось с места %d из 6" % [dist_far, charged])
	verdict("D4 обстрел дальше 12 м отряд с места не срывает",
		charged == 0, "ушло %d из 6 (дистанция %.1f)" % [charged, dist_far])

	for m in near_sq["men"] + far_sq["men"]:
		(m as Node).queue_free()
	shooter.queue_free(); sniper.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# E. СМЫКАНИЕ СТРОЯ ПОСЛЕ ПОТЕРЬ И ПОСЛЕ БОЯ
# ═════════════════════════════════════════════════════════════════════════════
func _test_reform() -> void:
	print("\n═════ E. СМЫКАНИЕ СТРОЯ ═════")
	var sq := _mk_squad("spearman", 12, Vector3(400, 0, 400), 4)
	var sid: int = sq["sid"]
	var men: Array = sq["men"]
	# Разметка: 3 шеренги по 4, фронт на +Z
	var slots: Array = []
	for row in range(3):
		for col in range(4):
			slots.append(Vector3(400.0 + float(col) * 0.7, 0.0,
				402.0 - float(row) * 0.7))
	GameManager.squad_set_formation(sid, slots, Vector3.BACK, false)
	await frames(2)

	# Выбиваем ВСЮ первую шеренгу
	for i in range(4):
		(men[i] as Unit)._die()
	await frames(3)
	GameManager.squads[sid]["reshuffled"] = 0
	var moved: bool = GameManager.squad_close_ranks(sid)
	await frames(2)
	verdict("E1 после потерь отряд смыкает ряды", moved)

	# ПРИОРИТЕТ ПЕРВЫХ РЯДОВ: восемь выживших обязаны занять первые восемь мест
	var alive := GameManager.squad_members(sid)
	# Сверяемся с move_target, а не с фактической позицией: приказ уже отдан,
	# а дойти боец ещё не успел. Допуск щедрый — command_move прогоняет точку
	# через land_target (перенос из воды на берег и зажим границ карты)
	print("  цели выживших:")
	for m in alive:
		print("    %s" % str((m as Unit).move_target))
	var front_taken := 0
	for si in range(mini(8, slots.size())):
		var slot: Vector3 = slots[si]
		for m in alive:
			if (m as Unit).move_target.distance_to(slot) < 0.4:
				front_taken += 1
				break
	print("  выживших %d, занято первых мест разметки: %d" % [alive.size(), front_taken])
	verdict("E2 выжившие идут на ПЕРВЫЕ места разметки, дыры уезжают в хвост",
		front_taken >= 7, "занято %d из 8" % front_taken)
	var last_slots_used := 0
	for si in range(8, slots.size()):
		for m in alive:
			if (m as Unit).move_target.distance_to(slots[si] as Vector3) < 0.4:
				last_slots_used += 1
				break
	verdict("E3 хвост разметки остаётся пустым", last_slots_used == 0,
		"занято хвостовых мест: %d" % last_slots_used)

	# ВЫХОД ИЗ БОЯ тоже собирает строй, даже без новых потерь
	GameManager.squads[sid]["reshuffled"] = 0
	var forced: bool = GameManager.squad_close_ranks(sid, true)
	verdict("E4 вышедший из боя отряд перестраивается и без потерь", forced)
	# «Потерь нет» надо ещё и обозначить: порог считается от состава НА МОМЕНТ
	# ПРИКАЗА, а он до сих пор помнит двенадцать человек из начала раздела
	GameManager.squads[sid]["at_order"] = GameManager.squad_members(sid).size()
	GameManager.squads[sid]["reshuffled"] = 0
	var not_forced: bool = GameManager.squad_close_ranks(sid, false)
	verdict("E5 без потерь и без флага строй не переступает", not not_forced)

	for m in alive:
		(m as Node).queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# F. ТЕМП ФАЛАНГИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_phalanx_pace() -> void:
	print("\n═════ F. ТЕМП АТАКИ ИЗ СТОЙКИ ЗАЩИТЫ ═════")
	verdict("F1 замедление ровно −25%",
		absf(Unit.PHALANX_ATTACK_FACTOR - 0.75) < 0.001,
		"PHALANX_ATTACK_FACTOR=%.3f" % Unit.PHALANX_ATTACK_FACTOR)

	var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u.faction = Constants.FACTION_PLAYER
	get_tree().root.add_child(u)
	u.global_position = Vector3(500, 0, 500)
	await frames(2)
	u.state = Unit.State.MOVING
	u.march_slow = false
	u.set_stance("attack")
	var plain: float = u._effective_speed()
	u.set_stance("defense")
	var phalanx: float = u._effective_speed()
	print("  ход обычный %.3f, фалангой %.3f" % [plain, phalanx])
	verdict("F2 фаланга идёт на четверть медленнее",
		absf(phalanx / maxf(plain, 0.001) - 0.75) < 0.01,
		"отношение %.4f" % (phalanx / maxf(plain, 0.001)))
	u.state = Unit.State.IDLE
	var standing: float = u._effective_speed()
	verdict("F3 стоящую фалангу замедление не трогает",
		absf(standing - plain) < 0.001,
		"стоя %.3f, базовая %.3f" % [standing, plain])

	# Копья: на простом марше вверх, в атаке по приказу — наперевес
	u.set_stance("attack")
	u.command_move(Vector3(510, 0, 500))
	await frames(2)
	verdict("F4 на обычном марше копьё поднято",
		not bool(u.call("_spear_leveled")))
	var foe: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	foe.faction = Constants.FACTION_ENEMY
	get_tree().root.add_child(foe)
	foe.global_position = Vector3(508, 0, 500)
	foe.max_health = 1e9; foe.current_health = 1e9
	await frames(2)
	u.command_attack(foe, true, true)
	await wait_ms(Spearman.DROP_DELAY_MAX_MS + 400)
	verdict("F5 в атаке ПО ПРИКАЗУ копьё опускается на марше",
		bool(u.call("_spear_leveled")),
		"ряд %d, цель %s" % [u._live_rank, str(u.attack_target != null)])
	# А подобранная самим цель копьё не опускает
	u.command_move(Vector3(520, 0, 500))
	await frames(2)
	u.command_attack(foe, false)
	await frames(2)
	verdict("F6 самостоятельно подобранная цель копьё не опускает",
		not bool(u.call("_spear_leveled")))

	u.queue_free(); foe.queue_free()
	await frames(2)
