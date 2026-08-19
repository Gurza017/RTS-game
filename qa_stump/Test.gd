extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПЕНЬКИ — ЧИСТО ДЕКОРАЦИЯ
## ═══════════════════════════════════════════════════════════════════════════
##   A СНЯТИЕ — сруб снимает с пенька всё, чем он мог мешать
##   B ПРОХОД — рабочий идёт СКВОЗЬ поле пеньков по прямой и доходит
##   C ОТРЯД  — то же для строя: пеньки не рвут марш
##
## Проверяется НЕ «поле сброшено», а «шаг не отклонился»: обстакл мог бы
## остаться в реестре обхода (GameManager.register_trunk) даже при нулевом
## слое столкновений — это разные механизмы, и жалоба была именно про движение.

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

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

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(2)

	await _a_strip()
	await _b_worker()
	await _c_squad()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 62), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_STUMP DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

## ЧИСТЫЙ КОРИДОР. На карте почти две тысячи настоящих стволов, и полоса
## пеньков, положенная «куда-нибудь», почти наверняка ляжет в лесу: боец
## обойдёт ЖИВОЕ дерево, а стенд запишет это на пеньки. Ищем прямую полосу,
## вдоль которой на MARGIN метров нет ни одного ресурса
func _clear_lane(length: float) -> Vector3:
	const MARGIN := 4.0
	var nodes := get_tree().get_nodes_in_group("resource_nodes")
	for r in range(10, 64, 3):
		for a in range(0, 16):
			var ang: float = TAU * float(a) / 16.0
			var base := Vector3(cos(ang) * float(r), 0.0, sin(ang) * float(r))
			if main.is_water(base.x, base.z):
				continue
			var ok := true
			var steps := int(length) + 2
			# Полоса, а не линия: строй идёт шириной в несколько метров, и
			# дерево в стороне остановит фланговый ряд — стенд записал бы это
			# на пеньки (проверено: 6 бойцов из 9 «не дошли» именно так)
			for i in range(steps * 3):
				var p := Vector3(base.x + float(i % 3 - 1) * 5.0,
					0.0, base.z + float(i / 3))
				if main.is_water(p.x, p.z):
					ok = false
					break
				for n in nodes:
					var rn := n as ResourceNode
					if rn == null or not is_instance_valid(rn):
						continue
					var d: float = Vector2(rn.global_position.x - p.x,
						rn.global_position.z - p.z).length()
					if d < MARGIN:
						ok = false
						break
				if not ok:
					break
			if ok:
				return base
	return Vector3(0.0, 0.0, 0.0)

## ОСВОБОДИТЬ КОРИДОР. Поиска чистого места мало: лес на карте случайный,
## и при неудачном посеве живое дерево всё равно оказывалось в полосе движения
## строя — стенд падал «дошло 6 из 9» через прогон, обвиняя пеньки в том, что
## делало настоящее дерево. Поэтому всё живое из коробки теста просто убирается:
## проверяем пеньки, а не везение генератора карты
func _clear_box(centre: Vector3, half_x: float, half_z: float) -> void:
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var r := n as ResourceNode
		if r == null or not is_instance_valid(r):
			continue
		var dx: float = absf(r.global_position.x - centre.x)
		var dz: float = absf(r.global_position.z - centre.z)
		if dx < half_x and dz < half_z:
			r.queue_free()

## Посадить дерево и тут же срубить его в пень
func _stump_at(p: Vector3) -> ResourceNode:
	var t := ResourceNode.new()
	t.resource_type = Constants.RESOURCE_WOOD
	t.remaining = 40.0
	main.world_add(t)
	t.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
	return t

# ═════════════════════════════════════════════════════════════════════════════
# A. ЧТО СНИМАЕТСЯ ПРИ СРУБЕ
# ═════════════════════════════════════════════════════════════════════════════
func _a_strip() -> void:
	print("\n═════ A. СНЯТИЕ ═════")
	var t := _stump_at(Vector3(0.0, 0.0, 40.0))
	await pframes(6)          # регистрация ствола отложена (см. _register_trunk)
	var before: int = GameManager.trunk_count()
	var blocked_live: Vector3 = GameManager.trunk_block(
		t.global_position.x, t.global_position.z, 0.3)
	verdict("A1 живое дерево — препятствие (иначе проверка ниже пуста)",
		before > 0 and blocked_live != Vector3.ZERO,
		"стволов на учёте %d" % before)

	t.extract(1e9)            # срубили
	await pframes(4)
	verdict("A2 пень снят с реестра обхода",
		GameManager.trunk_count() == before - 1,
		"стволов было %d, стало %d" % [before, GameManager.trunk_count()])
	verdict("A3 через пень шаг не блокируется вовсе",
		GameManager.trunk_block(t.global_position.x, t.global_position.z, 0.5)
			== Vector3.ZERO)
	verdict("A4 пень не ловится лучом (слой столкновений снят)",
		t.collision_layer == 0, "слой %d" % t.collision_layer)
	verdict("A5 пень больше не ресурс (вне группы поиска)",
		not t.is_in_group("resource_nodes"))
	verdict("A6 пень остался на карте, как и просили",
		is_instance_valid(t) and not t.is_queued_for_deletion())

# ═════════════════════════════════════════════════════════════════════════════
# B. РАБОЧИЙ ИДЁТ СКВОЗЬ ПОЛЕ ПЕНЬКОВ
# ═════════════════════════════════════════════════════════════════════════════
func _b_worker() -> void:
	print("\n═════ B. РАБОЧИЙ ═════")
	# Стена пеньков поперёк дороги: восемь штук вплотную друг к другу
	var lane := _clear_lane(14.0)
	_clear_box(Vector3(lane.x, 0.0, lane.z + 7.0), 12.0, 12.0)
	await pframes(3)
	var stumps: Array = []
	for i in range(8):
		var s := _stump_at(Vector3(lane.x - 3.0 + float(i) * 0.85, 0.0, lane.z + 7.0))
		stumps.append(s)
	await pframes(6)
	for s in stumps:
		(s as ResourceNode).extract(1e9)
	await pframes(4)

	var w := Worker.new()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = Vector3(lane.x,
		GameManager.get_terrain_height(lane.x, lane.z + 1.0), lane.z + 1.0)
	w.sync_row()
	await pframes(4)
	var goal := Vector3(lane.x, 0.0, lane.z + 13.0)
	w.command_move(goal)
	# Отклонение от прямой линии — то самое «обходит и залипает»
	var drift := 0.0
	var stalled := 0
	var prev: Vector3 = w.global_position
	for _i in range(240):
		await get_tree().physics_frame
		drift = maxf(drift, absf(w.global_position.x - lane.x))
		if w.state == Unit.State.MOVING and w.global_position.distance_to(prev) < 0.001:
			stalled += 1
		prev = w.global_position
		if w.global_position.distance_to(goal) < 1.0:
			break
	var left: float = w.global_position.distance_to(goal)
	verdict("B1 рабочий дошёл сквозь стену пеньков",
		left < 1.5, "не дошёл %.2f м" % left)
	verdict("B2 шёл по прямой, а не в обход",
		drift < 0.5, "отклонение вбок %.2f м" % drift)
	verdict("B3 ни одного кадра «идёт и стоит на месте»",
		stalled == 0, "таких кадров %d" % stalled)
	w.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. СТРОЙ ЧЕРЕЗ ПЕНЬКИ
# ═════════════════════════════════════════════════════════════════════════════
func _c_squad() -> void:
	print("\n═════ C. ОТРЯД ═════")
	var lane := _clear_lane(20.0)
	_clear_box(Vector3(lane.x, 0.0, lane.z + 9.0), 14.0, 16.0)
	await pframes(3)
	var stumps: Array = []
	for i in range(10):
		var s := _stump_at(Vector3(lane.x - 4.0 + float(i) * 0.9, 0.0, lane.z + 8.0))
		stumps.append(s)
	await pframes(6)
	for s in stumps:
		(s as ResourceNode).extract(1e9)
	await pframes(4)

	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(9):
		var u := Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var x: float = lane.x - 2.0 + float(i % 3) * 1.0
		var z: float = lane.z + 1.0 + float(i / 3) * 1.0
		u.global_position = Vector3(x, GameManager.get_terrain_height(x, z), z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(4)
	for u in men:
		(u as Unit).command_move(Vector3((u as Unit).global_position.x, 0.0, lane.z + 17.0))
	# Копейщик идёт около 2 м/с, а идти ему шестнадцать метров: 420 кадров (7 с)
	# впритык, и задние ряды не успевали — стенд мерил не пеньки, а терпение
	for _i in range(900):
		await get_tree().physics_frame
	var arrived := 0
	for u in men:
		if (u as Unit).global_position.z > lane.z + 15.0:
			arrived += 1
	verdict("C1 весь строй прошёл полосу пеньков насквозь",
		arrived == men.size(), "дошло %d из %d" % [arrived, men.size()])
