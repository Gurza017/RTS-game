extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СТОЙКА «ЗАЩИТА» И ЗАПРЕТ ПОГОНИ У СТРЕЛКОВ
## ═══════════════════════════════════════════════════════════════════════════
##   A ЗАБОР   — копейщики в обороне не сходят с места ни за кем
##   B СМЫКАНИЕ — но брешь в СВОЁМ строю закрывают
##   C ЛУЧНИК  — не преследует никогда: ни сам, ни по прямому приказу
##   D ПОДХОД  — но приказ исполняет: доходит до дистанции выстрела и стреляет
##
## Всё меряется СМЕЩЕНИЕМ, а не флагами: «преследование выключено» — это про
## то, что боец остался стоять, а не про то, что где-то стоит false.

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
	GameManager.world_bounds_enabled = false
	await pframes(2)

	await _a_wall()
	await _b_close_ranks()
	await _c_archer_no_chase()
	await _d_archer_approach()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 64), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_HOLD DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

func _spawn(kind: String, faction: int, pos: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		_:          u = Warrior.new()
	u.faction = faction
	main.world_add(u)
	u.global_position = Vector3(pos.x, GameManager.get_terrain_height(pos.x, pos.z), pos.z)
	u.sync_row()
	return u

# ═════════════════════════════════════════════════════════════════════════════
# A. ФАЛАНГА КАК ЗАБОР
# ═════════════════════════════════════════════════════════════════════════════
func _a_wall() -> void:
	print("\n═════ A. ЗАБОР ═════")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(6):
		var u := _spawn("spearman", Constants.FACTION_PLAYER,
			Vector3(-200.0 + float(i % 3) * 0.7, 0.0, -200.0 + float(i / 3) * 0.7))
		GameManager.add_to_squad(sid, u)
		u.set_stance(_UStancesRef().STANCE_DEFENSE)
		men.append(u)
	# Враг СТОИТ рядом, но вне дистанции копья
	var foe := _spawn("warrior", Constants.FACTION_ENEMY, Vector3(-200.0, 0.0, -196.5))
	foe.set_physics_process(false)          # неподвижная мишень
	await pframes(6)
	var start: Array = []
	for u in men:
		start.append((u as Unit).global_position)
	await pframes(180)
	var creep := 0.0
	for i in range(men.size()):
		creep = maxf(creep, (men[i] as Unit).global_position.distance_to(start[i]))
	verdict("A1 враг в трёх метрах — строй не подался вперёд ни на шаг",
		creep < 0.25, "макс. сдвиг %.2f м" % creep)

	# ── ТРЕБОВАНИЕ РАЗВЕРНУЛОСЬ (заказ владельца, авг. 2026) ────────────────
	# Раньше здесь проверялось «стойка держит позицию ДАЖЕ по прямому приказу»
	# (сдвиг < 0.6 м). Теперь правило другое и делится надвое: в покое строй стоит
	# намертво (это проверяет A1 выше), а ПО ПРИКАЗУ фаланга идёт вперёд единым
	# забором — но идёт В ТОЧКУ ПРИКАЗА, а не за убегающим (Unit._phalanx_march).
	#
	# Поэтому проверяется СВОЙСТВО, а не прежнее число: строй закрыл расстояние
	# до того места, где враг стоял в момент клика (3.5 м), и там остановился —
	# при том, что сам враг успел отбежать на двадцать метров. Если бы работала
	# погоня, сдвиг был бы порядка двадцати метров, а не трёх с половиной
	var order_gap: float = 3.5
	for u in men:
		(u as Unit).command_attack(foe, true, true, true)
	await pframes(20)
	foe.global_position = Vector3(-200.0, GameManager.get_terrain_height(-200.0, -180.0), -180.0)
	foe.sync_row()
	await pframes(180)
	var chase := 0.0
	for i in range(men.size()):
		chase = maxf(chase, (men[i] as Unit).global_position.distance_to(start[i]))
	verdict("A2 стена дошла до точки приказа, а за убежавшим не пошла",
		chase <= order_gap + 0.6, "макс. сдвиг %.2f м при разрыве приказа %.1f м, враг убежал на 20 м" % [chase, order_gap])
	# И отдельно — что она действительно ПОШЛА, а не осталась стоять: без этого
	# первая половина проверки была бы зелёной и на полностью неподвижном строю
	verdict("A2б и она действительно двинулась вперёд, а не осталась стоять",
		chase > 1.0, "макс. сдвиг %.2f м" % chase)
	for u in men:
		(u as Node).queue_free()
	foe.queue_free()
	await pframes(3)

func _UStancesRef():
	return preload("res://scripts/unit_stats_config.gd")

# ═════════════════════════════════════════════════════════════════════════════
# B. БРЕШЬ В СВОЁМ СТРОЮ ЗАКРЫВАЕТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _b_close_ranks() -> void:
	print("\n═════ B. СМЫКАНИЕ ═════")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	# Колонна по одному вдоль +Z, с ДЫРОЙ на месте второго бойца
	for i in range(4):
		var z: float = -100.0 + float(i) * 0.75
		if i == 1:
			continue                      # вот она, брешь
		var u := _spawn("spearman", Constants.FACTION_PLAYER, Vector3(-100.0, 0.0, z))
		GameManager.add_to_squad(sid, u)
		u.set_stance(_UStancesRef().STANCE_DEFENSE)
		men.append(u)
	# Враг ВПЕРЕДИ по курсу, чтобы фаланга вообще работала (без врага она спит)
	var foe := _spawn("warrior", Constants.FACTION_ENEMY, Vector3(-100.0, 0.0, -104.0))
	foe.set_physics_process(false)
	await pframes(10)
	# Задний боец (последний в списке) стоит дальше всех от врага
	var back: Unit = men[men.size() - 1]
	var z0: float = back.global_position.z
	await pframes(240)
	var moved: float = z0 - back.global_position.z    # к врагу — это уменьшение z
	verdict("B1 задний ряд подтянулся, закрывая брешь",
		moved > 0.15, "подтянулся на %.2f м" % moved)
	# Но НЕ прошёл сквозь строй и не докатился до врага
	verdict("B2 смыкание не превратилось в наступление",
		back.global_position.z > -103.0,
		"дошёл до z=%.2f (враг на -104)" % back.global_position.z)
	for u in men:
		(u as Node).queue_free()
	foe.queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ЛУЧНИК НЕ ПРЕСЛЕДУЕТ
# ═════════════════════════════════════════════════════════════════════════════
func _c_archer_no_chase() -> void:
	print("\n═════ C. ЛУЧНИК НЕ ГОНИТСЯ ═════")
	verdict("C0 у лучника преследование выключено, у пехоты — нет",
		not Archer.new().pursues_target() and Warrior.new().pursues_target())

	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var men: Array = []
	for i in range(4):
		var u := _spawn("archer", Constants.FACTION_PLAYER,
			Vector3(0.0 + float(i) * 0.8, 0.0, -300.0))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	var foe := _spawn("warrior", Constants.FACTION_ENEMY, Vector3(0.0, 0.0, -292.0))
	foe.set_physics_process(false)
	await pframes(10)
	# Приказ игрока по цели В ЗОНЕ ВЫСТРЕЛА — лучники стреляют с места
	for u in men:
		(u as Unit).command_attack(foe, true, true, true)
	await pframes(90)
	var start: Array = []
	for u in men:
		start.append((u as Unit).global_position)
	# Цель убегает далеко за дальность стрельбы (у лучника ~20 м)
	foe.global_position = Vector3(0.0, GameManager.get_terrain_height(0.0, -250.0), -250.0)
	foe.sync_row()
	await pframes(300)
	var chase := 0.0
	for i in range(men.size()):
		chase = maxf(chase, (men[i] as Unit).global_position.distance_to(start[i]))
	verdict("C1 цель убежала — лучники остались стоять",
		chase < 1.0, "макс. сдвиг %.2f м" % chase)
	verdict("C2 и бросили недостижимую цель, а не замерли с ней в руках",
		(men[0] as Unit).attack_target == null)

	# Появился новый враг В РАДИУСЕ — по нему открывают огонь, не сходя с места
	var foe2 := _spawn("warrior", Constants.FACTION_ENEMY, Vector3(3.0, 0.0, -288.0))
	foe2.set_physics_process(false)
	await pframes(150)
	var got := 0
	for u in men:
		if (u as Unit).attack_target != null:
			got += 1
	verdict("C3 новую цель в радиусе нашли сами",
		got > 0, "взяли цель %d из %d" % [got, men.size()])
	var chase2 := 0.0
	for i in range(men.size()):
		chase2 = maxf(chase2, (men[i] as Unit).global_position.distance_to(start[i]))
	verdict("C4 и всё так же не сдвинулись с позиции",
		chase2 < 1.5, "макс. сдвиг %.2f м" % chase2)
	for u in men:
		(u as Node).queue_free()
	foe.queue_free()
	foe2.queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. НО ПРИКАЗ ОН ИСПОЛНЯЕТ
# ═════════════════════════════════════════════════════════════════════════════
func _d_archer_approach() -> void:
	print("\n═════ D. ПОДХОД НА ВЫСТРЕЛ ═════")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var men: Array = []
	for i in range(3):
		var u := _spawn("archer", Constants.FACTION_PLAYER,
			Vector3(float(i) * 0.8, 0.0, -400.0))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	# Цель ДАЛЕКО за дальностью стрельбы — до неё надо дойти
	var foe := _spawn("warrior", Constants.FACTION_ENEMY, Vector3(0.0, 0.0, -360.0))
	foe.set_physics_process(false)
	await pframes(10)
	var d0: float = (men[0] as Unit).global_position.distance_to(foe.global_position)
	for u in men:
		(u as Unit).command_attack(foe, true, true, true)
	# Лучник идёт около 2 м/с, а идти ему двадцать метров: 420 кадров (7 с)
	# физически не хватало, и стенд мерил не остановку, а нехватку времени
	await pframes(900)
	var a0: Unit = men[0]
	var d1: float = a0.global_position.distance_to(foe.global_position)
	verdict("D1 по приказу лучник подошёл к далёкой цели",
		d1 < d0 - 5.0, "было %.1f м, стало %.1f м" % [d0, d1])
	verdict("D2 подошёл ИМЕННО на дистанцию выстрела, а не вплотную",
		d1 <= a0.attack_range + 1.5 and d1 > 2.0,
		"дистанция %.1f м при дальности %.1f м" % [d1, a0.attack_range])
	verdict("D3 и открыл огонь",
		a0.attack_target != null and a0.state == Unit.State.ATTACKING)
	for u in men:
		(u as Node).queue_free()
	foe.queue_free()
	await pframes(3)
