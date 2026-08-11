extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: АГРО-ЛОГИКА И ПРОДОЛЖЕНИЕ МАРША
## ═══════════════════════════════════════════════════════════════════════════
##   A ОТВЕТ НА ОБСТРЕЛ — отряд, по которому бьют лучники, идёт на них ВЕСЬ
##   B СКВОЗЬ БОЙ       — марширующий отряд не проходит мимо вражеской пехоты
##   C МАРШ ПОСЛЕ БОЯ   — снеся заслон, отряд продолжает путь, а не стоит
##   D ФАЛАНГА СТОИТ    — стойка ЗАЩИТА обстрелом с места не срывается
##
## Запуск: godot --headless --path . res://qa_aggro/Test.tscn

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

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	return u

## Отряд из count бойцов вокруг центра
func _squad(kind: String, fac: int, center: Vector3, count: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(count):
		var p := center + Vector3(float(i % 5) * 0.6 - 1.2, 0.0, float(i / 5) * 0.6)
		var u := _new(kind, fac, p)
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _alive(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _run() -> void:
	seed(777)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	GameManager.world_bounds_enabled = false
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  АГРО-ЛОГИКА: ОТВЕТ НА ОБСТРЕЛ, БОЙ НА МАРШЕ, ПРОДОЛЖЕНИЕ ПУТИ   ║")
	print("╚══════════════════════════════════════════════════════════════════╝")
	await _a_counter_fire()
	await _b_no_walkthrough()
	await _c_march_resumes()
	await _d_defense_holds()

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %s%s" % [_pad(String(row[0]), 58), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== AGGRO TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ОТРЯД ПОД ОБСТРЕЛОМ ИДЁТ НА СТРЕЛКОВ
# Главный баг: ответ был только на удар В УПОР. Пехота, которую расстреливали
# с десяти метров, стояла и умирала — «до меня не дотягиваются, значит, всё в
# порядке».
# ═════════════════════════════════════════════════════════════════════════════
func _a_counter_fire() -> void:
	print("\n═════ A. ОТВЕТ НА ОБСТРЕЛ ═════")
	var foot := _squad("spearman", Constants.FACTION_PLAYER, Vector3(0, 0, -300), 10)
	var bows := _squad("archer", Constants.FACTION_ENEMY, Vector3(0, 0, -292), 5)
	# Стрелков не убить: меряем реакцию пехоты, а не исход перестрелки
	for a in bows:
		(a as Unit).max_health = 1e9
		(a as Unit).current_health = 1e9
	await frames(30)
	var start_z: float = (foot[0] as Node3D).global_position.z

	var t0: int = Time.get_ticks_msec()
	var charging := 0
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		charging = 0
		for u in foot:
			if not is_instance_valid(u):
				continue
			if (u as Unit).attack_target != null:
				charging += 1
		if charging >= foot.size() - 1:
			break
	print("  пошли в атаку: %d из %d" % [charging, foot.size()])
	verdict("A1 под обстрелом поднялся ВЕСЬ отряд", charging >= foot.size() - 2,
		"взяли цель %d из %d" % [charging, foot.size()])

	# И действительно сблизились со стрелками. Замер идёт ПОСЛЕ паузы: цикл
	# выше обрывается в тот момент, когда отряд только взял цель, а сблизиться
	# он к этому мгновению физически ещё не успел
	var t_close: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_close < 3500:
		await get_tree().process_frame
	var closed := 0
	for u in foot:
		if is_instance_valid(u) and (u as Node3D).global_position.z > start_z + 2.0:
			closed += 1
	verdict("A2 отряд сблизился со стрелками", closed >= foot.size() / 2,
		"сблизились %d из %d" % [closed, foot.size()])

	for u in foot + bows:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. МАРШИРУЮЩИЙ ОТРЯД НЕ ПРОСАЧИВАЕТСЯ СКВОЗЬ ВРАЖЕСКУЮ ПЕХОТУ
# ═════════════════════════════════════════════════════════════════════════════
func _b_no_walkthrough() -> void:
	print("\n═════ B. НЕ ПРОЙТИ СКВОЗЬ БОЙ ═════")
	var wall := _squad("spearman", Constants.FACTION_ENEMY, Vector3(0, 0, -350), 15)
	for u in wall:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
	var col := _squad("warrior", Constants.FACTION_PLAYER, Vector3(0, 0, -362), 10)
	await frames(30)
	# Приказ идти НАСКВОЗЬ: точка за спиной вражеского строя
	for u in col:
		(u as Unit).command_move(Vector3(0, 0, -338))

	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	var slipped := 0
	var fighting := 0
	for u in col:
		if not is_instance_valid(u):
			continue
		if (u as Node3D).global_position.z > -344.0:
			slipped += 1
		if (u as Unit).attack_target != null:
			fighting += 1
	print("  просочилось за строй: %d, дерётся: %d (из %d)"
		% [slipped, fighting, col.size()])
	verdict("B1 никто не прошёл сквозь чужой строй", slipped == 0,
		"просочилось %d" % slipped)
	verdict("B2 колонна вступила в ближний бой", fighting >= col.size() / 2,
		"дерётся %d из %d" % [fighting, col.size()])

	for u in wall + col:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ПОСЛЕ БОЯ МАРШ ПРОДОЛЖАЕТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _c_march_resumes() -> void:
	print("\n═════ C. МАРШ ПОСЛЕ БОЯ ═════")
	# Слабый заслон: его снесут, и марш обязан продолжиться
	var picket := _squad("spearman", Constants.FACTION_ENEMY, Vector3(0, 0, -400), 2)
	for u in picket:
		(u as Unit).max_health = 6.0
		(u as Unit).current_health = 6.0
	var col := _squad("warrior", Constants.FACTION_PLAYER, Vector3(0, 0, -412), 8)
	await frames(30)
	var goal := Vector3(0, 0, -380)
	for u in col:
		(u as Unit).command_move(goal)

	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		if _alive(picket) == 0:
			break
	verdict("C1 заслон снесён", _alive(picket) == 0,
		"живых в заслоне %d" % _alive(picket))

	var t1: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 12000:
		await get_tree().process_frame
	var arrived := 0
	for u in col:
		if not is_instance_valid(u):
			continue
		if (u as Node3D).global_position.distance_to(goal) < 4.5:
			arrived += 1
	print("  дошли до точки приказа: %d из %d" % [arrived, col.size()])
	verdict("C2 отряд продолжил марш после боя", arrived >= col.size() / 2,
		"дошло %d из %d" % [arrived, col.size()])

	for u in picket + col:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. ФАЛАНГА В ОБОРОНЕ ОБСТРЕЛОМ С МЕСТА НЕ СРЫВАЕТСЯ
# Контратака на обстрел не должна ломать главное свойство стойки ЗАЩИТА
# ═════════════════════════════════════════════════════════════════════════════
func _d_defense_holds() -> void:
	print("\n═════ D. ОБОРОНА ДЕРЖИТ РУБЕЖ ═════")
	var foot := _squad("spearman", Constants.FACTION_PLAYER, Vector3(0, 0, -450), 10)
	for u in foot:
		(u as Unit).set_stance("defense")
	var bows := _squad("archer", Constants.FACTION_ENEMY, Vector3(0, 0, -442), 5)
	for a in bows:
		(a as Unit).max_health = 1e9
		(a as Unit).current_health = 1e9
	await frames(30)
	var home: Array = []
	for u in foot:
		home.append((u as Node3D).global_position)

	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	var drift := 0.0
	for i in range(foot.size()):
		if not is_instance_valid(foot[i]):
			continue
		var p: Vector3 = (foot[i] as Node3D).global_position
		drift = maxf(drift, Vector2(p.x - home[i].x, p.z - home[i].z).length())
	print("  наибольший сход с рубежа под обстрелом: %.2f м" % drift)
	verdict("D1 оборона не срывается на стрелков", drift < 3.0,
		"сход %.2f м" % drift)

	for u in foot + bows:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)
