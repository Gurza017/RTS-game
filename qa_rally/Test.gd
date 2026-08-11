extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СПАВН У ЗДАНИЯ И ТОЧКА СБОРА
## ═══════════════════════════════════════════════════════════════════════════
##   A БЕЗ ТОЧКИ СБОРА — отряд встаёт вплотную к зданию и НЕ уходит
##   B С ТОЧКОЙ СБОРА  — отряд идёт ровно в указанную точку и там встаёт
##   C ПКМ ПО КАРТЕ     — цепочка «выделил здание → клик» реально ставит точку
##   D МАРКЕР           — флажок есть, стоит в точке, виден только у выделенного

const _UCfg = preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

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

## Здание с мгновенным наймом: ждать реальные 12 секунд в стенде незачем
func _new_building(kind: String, at: Vector3) -> Building:
	var b: Building = Barracks.new() if kind == "barracks" else Castle.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = at
	return b

## Заказать отряд и дождаться выхода
func _train(b: Building, unit_id: String, size: int) -> Array:
	var before: Array = []
	for n in get_tree().get_nodes_in_group("player_units"):
		before.append(n)
	# Размер отряда задаётся полем здания, а не аргументом заказа
	b.squad_size = size
	b.queue_unit(unit_id, {}, 0.01)
	if not b.production_queue.is_empty():
		(b.production_queue[0] as Dictionary)["time"] = 0.01
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		var now: Array = get_tree().get_nodes_in_group("player_units")
		if now.size() >= before.size() + size:
			break
	var fresh: Array = []
	for n in get_tree().get_nodes_in_group("player_units"):
		if not (n in before):
			fresh.append(n)
	return fresh

## Дождаться, пока отряд встанет (все в IDLE) или выйдет время
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

func _spread(units: Array, from: Vector3) -> Array:
	var near_d := INF
	var far_d := 0.0
	for u in units:
		if not is_instance_valid(u): continue
		var p: Vector3 = (u as Node3D).global_position
		var d: float = Vector2(p.x - from.x, p.z - from.z).length()
		near_d = minf(near_d, d)
		far_d  = maxf(far_d, d)
	return [near_d, far_d]

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	# ИИ усыпляем: его отряды не должны мешать замерам расстояний
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	await _a_no_rally()
	await _b_with_rally()
	await _c_click_chain()
	await _d_marker()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 60), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== RALLY TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. БЕЗ ТОЧКИ СБОРА: ВСТАЛИ У ЗДАНИЯ И СТОЯТ
# ═════════════════════════════════════════════════════════════════════════════
func _a_no_rally() -> void:
	print("\n═════ A. БЕЗ ТОЧКИ СБОРА ═════")
	for kind in ["barracks", "castle"]:
		var k: String = kind
		var at := Vector3(-60.0 if k == "barracks" else -30.0, 0.0, -55.0)
		var b: Building = _new_building(k, at)
		await frames(3)
		var men: Array = await _train(b, "spearman", 10)
		print("  %s: вышло %d бойцов" % [k, men.size()])
		var secs: float = await _settle(men, 15000)
		var gate: Vector3 = b._gate_position()
		var sp: Array = _spread(men, gate)
		print("    встали за %.1f с: ближний %.1f м от ворот, дальний %.1f м" % [
			secs, float(sp[0]), float(sp[1])])
		verdict("A%s первая шеренга встаёт вплотную к зданию (<5 м)" % k.substr(0, 1),
			float(sp[0]) <= 5.0, "ближний %.1f м" % float(sp[0]))
		verdict("A%s отряд не уходит вглубь карты (<14 м)" % k.substr(0, 1),
			float(sp[1]) <= 14.0, "дальний %.1f м" % float(sp[1]))
		# И СТОИТ: через 3 секунды никто не убежал
		var p0: Array = []
		for u in men:
			p0.append((u as Node3D).global_position)
		await frames(180)
		var drift := 0.0
		for i in range(men.size()):
			if not is_instance_valid(men[i]): continue
			drift = maxf(drift, (p0[i] as Vector3).distance_to(
				(men[i] as Node3D).global_position))
		print("    за 3 с самый непоседливый сдвинулся на %.2f м" % drift)
		verdict("A%s после выхода отряд стоит на месте" % k.substr(0, 1),
			drift < 1.5, "сдвиг %.2f м" % drift)
		for u in men:
			(u as Node).queue_free()
		b.queue_free()
		await frames(5)

# ═════════════════════════════════════════════════════════════════════════════
# B. С ТОЧКОЙ СБОРА: ПРИШЛИ РОВНО ТУДА
# ═════════════════════════════════════════════════════════════════════════════
func _b_with_rally() -> void:
	print("\n═════ B. С ТОЧКОЙ СБОРА ═════")
	for kind in ["barracks", "castle"]:
		var k: String = kind
		var at := Vector3(-60.0 if k == "barracks" else -30.0, 0.0, -20.0)
		var b: Building = _new_building(k, at)
		await frames(3)
		var rally := at + Vector3(26.0, 0.0, 14.0)
		b.set_rally_point(rally)
		print("  %s в (%.0f, %.0f), точка сбора (%.0f, %.0f)" % [
			k, at.x, at.z, rally.x, rally.z])
		var men: Array = await _train(b, "spearman", 10)
		var secs: float = await _settle(men, 25000)
		var sp: Array = _spread(men, rally)
		print("    дошли за %.1f с: ближний %.1f м от точки, дальний %.1f м" % [
			secs, float(sp[0]), float(sp[1])])
		verdict("B%s отряд пришёл в назначенную точку" % k.substr(0, 1),
			float(sp[0]) <= 3.0, "ближний %.1f м" % float(sp[0]))
		verdict("B%s отряд встал КОМПАКТНО у точки, а не растянулся" % k.substr(0, 1),
			float(sp[1]) <= 16.0, "дальний %.1f м" % float(sp[1]))
		# Точка сбора ближе к зданию, чем к воротам? Значит приказ отработал
		var gate: Vector3 = b._gate_position()
		var to_gate: Array = _spread(men, gate)
		print("    от ворот при этом: ближний %.1f м" % float(to_gate[0]))
		verdict("B%s отряд ушёл от ворот к точке, а не остался у дверей" % k.substr(0, 1),
			float(to_gate[0]) > 8.0, "от ворот %.1f м" % float(to_gate[0]))
		for u in men:
			(u as Node).queue_free()
		b.queue_free()
		await frames(5)

# ═════════════════════════════════════════════════════════════════════════════
# C. ЦЕПОЧКА «ВЫДЕЛИЛ ЗДАНИЕ → ПКМ ПО КАРТЕ»
# ═════════════════════════════════════════════════════════════════════════════
func _c_click_chain() -> void:
	print("\n═════ C. ПКМ ПО КАРТЕ ПРИ ВЫДЕЛЕННОМ ЗДАНИИ ═════")
	var sm = main.selection_manager
	var b: Building = _new_building("barracks", Vector3(10.0, 0.0, -40.0))
	await frames(3)
	# Выделяем здание так же, как это делает клик мышью
	sm._clear_selection()
	sm._select_one(b)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	print("  выделено объектов: %d, из них зданий: %d" % [
		sm.selected_units.size(), 1 if b in sm.selected_units else 0])
	verdict("C1 здание попадает в выделение", b in sm.selected_units)

	# ПКМ по пустой земле — ровно тем путём, каким идёт настоящий клик
	var spot := Vector3(34.0, 0.0, -16.0)
	var ok: bool = sm._try_set_rally(spot, null)
	print("  _try_set_rally вернул %s; has_rally=%s, точка (%.1f, %.1f)" % [
		str(ok), str(b.has_rally), b.rally_point.x, b.rally_point.z])
	verdict("C2 ПКМ по земле ставит точку сбора", ok and b.has_rally)
	verdict("C3 точка сбора совпадает с местом клика",
		Vector2(b.rally_point.x - spot.x, b.rally_point.z - spot.z).length() < 0.5,
		"расхождение %.2f м" % Vector2(b.rally_point.x - spot.x,
			b.rally_point.z - spot.z).length())

	# ПКМ по вражескому бойцу точку сбора ставить НЕ должен: это приказ атаки
	var foe := Spearman.new()
	foe.faction = Constants.FACTION_ENEMY
	main.world_add(foe)
	foe.global_position = Vector3(20.0, 0.0, -30.0)
	await frames(3)
	var prev: Vector3 = b.rally_point
	var ok2: bool = sm._try_set_rally(foe.global_position, foe)
	print("  ПКМ по врагу: вернул %s, точка осталась (%.1f, %.1f)" % [
		str(ok2), b.rally_point.x, b.rally_point.z])
	verdict("C4 клик по юниту не подменяет точку сбора",
		not ok2 and b.rally_point.distance_to(prev) < 0.01)

	# Смешанное выделение (здание + боец) точку сбора не ставит
	var mine := Spearman.new()
	mine.faction = Constants.FACTION_PLAYER
	main.world_add(mine)
	mine.global_position = Vector3(12.0, 0.0, -38.0)
	await frames(3)
	sm._select_one(mine)
	var ok3: bool = sm._try_set_rally(Vector3(50.0, 0.0, 0.0), null)
	print("  смешанное выделение (здание + боец): вернул %s" % str(ok3))
	verdict("C5 при смешанном выделении точка сбора не ставится", not ok3)

	foe.queue_free(); mine.queue_free(); b.queue_free()
	sm._clear_selection()
	await frames(5)

# ═════════════════════════════════════════════════════════════════════════════
# D. МАРКЕР
# ═════════════════════════════════════════════════════════════════════════════
func _d_marker() -> void:
	print("\n═════ D. ФЛАЖОК ТОЧКИ СБОРА ═════")
	var b: Building = _new_building("barracks", Vector3(50.0, 0.0, -50.0))
	await frames(3)
	verdict("D1 без точки сбора флажка нет", b._rally_marker == null)

	var spot := Vector3(66.0, 0.0, -40.0)
	b.set_rally_point(spot)
	await frames(2)
	var m: Node3D = b._rally_marker
	print("  флажок создан: %s, позиция (%.1f, %.1f), видим=%s" % [
		str(m != null), m.global_position.x if m != null else 0.0,
		m.global_position.z if m != null else 0.0,
		str(m.visible) if m != null else "—"])
	verdict("D2 флажок создан и стоит в точке сбора",
		m != null and Vector2(m.global_position.x - spot.x,
			m.global_position.z - spot.z).length() < 0.1)
	verdict("D3 у невыделенного здания флажок скрыт", m != null and not m.visible)

	b.set_selected(true)
	await frames(2)
	verdict("D4 у выделенного здания флажок виден", m != null and m.visible)
	b.set_selected(false)
	await frames(2)
	verdict("D5 снятие выделения прячет флажок", m != null and not m.visible)

	b.set_selected(true)
	b.clear_rally_point()
	await frames(2)
	verdict("D6 сброс точки сбора убирает флажок",
		b._rally_marker == null or not is_instance_valid(b._rally_marker))
	b.queue_free()
	await frames(3)
