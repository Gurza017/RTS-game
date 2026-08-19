extends Node

## ЯДРО АРМИИ (SoA): СТРОКА ОБЯЗАНА СОВПАДАТЬ С БОЙЦОМ.
##
## Строка пишется сквозным способом из тех же мест, где боец и так менял
## величину. Такая схема ломается ровно одним способом — про какое-то место
## забыли, и строка тихо разошлась с объектом. Здесь это и проверяется:
## сначала сходимость номеров битов (числа продублированы в Unit ради скорости),
## потом совпадение координат/состояния/здоровья на живой армии, потом
## переиспользование строк после гибели.
##
## Запуск: godot --headless --path . res://qa_army/SelfTest.tscn

const _Army := preload("res://scripts/army/ArmySoA.gd")

var _fail := 0
var _checks := 0

func _ready() -> void:
	call_deferred("_run")

func ok(name: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fail += 1
	print("  [%s] %s%s" % ["OK " if cond else "НЕ ПРОШЛО", name,
		("  — " + detail) if detail != "" else ""])

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(4)
	var world: Node3D = main.world_root()

	print("\n───── A. БИТЫ ПРИЗНАКОВ НЕ РАЗЪЕХАЛИСЬ ─────")
	# Unit складывает слово признаков литеральными сдвигами (обращение к
	# константам чужого скрипта в горячем месте стоит слишком дорого), поэтому
	# сходимость с ArmySoA.F_* обязана проверяться стендом
	ok("A1 номера битов совпадают с ArmySoA.F_*",
		_Army.F_POS_VALID == 1 << 0 and _Army.F_RETREATING == 1 << 1
		and _Army.F_SPRINTING == 1 << 2 and _Army.F_SETTLED == 1 << 3
		and _Army.F_DISENGAGE == 1 << 4 and _Army.F_LOCKED == 1 << 5
		and _Army.F_GARRISONED == 1 << 6 and _Army.F_CLEAR_TRUNK == 1 << 7
		and _Army.F_CLEAR_ENEMY == 1 << 8 and _Army.F_SELECTED == 1 << 9
		and _Army.F_WORKING == 1 << 10 and _Army.F_STEP_PENDING == 1 << 11
		and _Army.F_TRUNK_IGNORE == 1 << 12)

	print("\n───── B. СТРОКА ВЫДАЁТСЯ И ЗАПОЛНЯЕТСЯ ─────")
	var Spear := load("res://scenes/units/Spearman.tscn") as PackedScene
	var used0: int = GameManager.army.used()
	var units: Array = []
	for i in range(60):
		var u: Unit = Spear.instantiate()
		u.faction = Constants.FACTION_PLAYER
		world.add_child(u)
		u.global_position = Vector3(float(i % 10) * 1.2 - 6.0, 0.0,
			float(i / 10) * 1.2 + 30.0)
		units.append(u)
	await _frames(1)
	ok("B1 строк стало ровно на армию больше",
		GameManager.army.used() == used0 + 60,
		"было %d, стало %d" % [used0, GameManager.army.used()])
	var idxs: Dictionary = {}
	var dup := 0
	for u in units:
		if idxs.has(u._soa):
			dup += 1
		idxs[u._soa] = true
	ok("B2 номера строк уникальны", dup == 0, "повторов %d" % dup)

	print("\n───── C. КООРДИНАТА, СОСТОЯНИЕ И ЗДОРОВЬЕ СХОДЯТСЯ ─────")
	# КООРДИНАТЫ ПОПАДАЮТ В СТРОКИ НЕ САМИ. Боец их не пишет — в его покадровый
	# цикл нельзя добавить ничего (замер: любая проверка на бойца стоит +2.2 мс
	# на пятнадцати тысячах). Их снимает разом на отряд ArmySoA.harvest_squad,
	# и зовётся он из пересчёта коридоров. Поэтому бойцов надо ОФОРМИТЬ ОТРЯДОМ
	# и дать пройти сроку жизни коридора
	var march_sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for u in units:
		GameManager.add_to_squad(march_sid, u)
		u.command_move(u.global_position + Vector3(14.0, 0.0, 0.0))
	# CORRIDOR_TTL_MS = 200 мс — это 12 физкадров; берём с запасом
	await _frames(30)
	var A = GameManager.army
	var apx: PackedFloat32Array = A.px
	var apz: PackedFloat32Array = A.pz
	var ast: PackedInt32Array = A.st
	var ahp: PackedFloat32Array = A.hp
	var worst := 0.0
	var bad_state := 0
	var bad_hp := 0
	var invalid := 0
	for u in units:
		var i: int = u._soa
		if not A.pos_ready(i):
			invalid += 1
			continue
		var d: float = Vector2(apx[i] - u.global_position.x,
			apz[i] - u.global_position.z).length()
		if d > worst:
			worst = d
		if ast[i] != u.state:
			bad_state += 1
		if not is_equal_approx(ahp[i], u.current_health):
			bad_hp += 1
	ok("C1 у всех идущих координата в строке настоящая", invalid == 0,
		"без координаты %d" % invalid)
	# Допуск — срок жизни коридора: строки обновляются раз в 200 мс, а отряд за
	# это время проходит меньше метра
	ok("C2 координата отстаёт не больше срока пересчёта", worst < 1.2,
		"худшее расхождение %.3f м при пороге записи 0.20 м" % worst)
	ok("C3 состояние совпадает у всех", bad_state == 0, "расхождений %d" % bad_state)
	ok("C4 здоровье совпадает у всех", bad_hp == 0, "расхождений %d" % bad_hp)

	print("\n───── D. УРОН И СМЕРТЬ ПОПАДАЮТ В СТРОКУ ─────")
	var victim: Unit = units[0]
	var vi: int = victim._soa
	var hp_before: float = victim.current_health
	victim.take_damage(7.0, null)
	ok("D1 урон записан сразу, не дожидаясь тика",
		is_equal_approx(A.hp[vi], victim.current_health)
		and victim.current_health < hp_before,
		"было %.1f, в строке %.1f" % [hp_before, A.hp[vi]])
	victim.take_damage(99999.0, null)
	ok("D2 смерть отмечена в строке сразу",
		A.st[vi] == Unit.State.DEAD, "состояние в строке %d" % A.st[vi])

	print("\n───── E. СТРОКИ ВОЗВРАЩАЮТСЯ И ПЕРЕИСПОЛЬЗУЮТСЯ ─────")
	# Убитый в блоке D тоже освобождает строку — но не сразу, а когда узел
	# действительно снимут с дерева. Ждём этого ДО замера, иначе арифметика
	# стенда разъедется на одну строку (так и вышло в первом прогоне)
	await _frames(3)
	var used_before: int = A.used()
	var freed: Array = []
	for i in range(20):
		freed.append(units[i + 1]._soa)
		units[i + 1].free()
	await _frames(1)
	ok("E1 строки освобождены", A.used() == used_before - 20,
		"было %d, стало %d" % [used_before, A.used()])
	var still_valid := 0
	for i in freed:
		if A.pos_ready(i):
			still_valid += 1
	ok("E2 освобождённая строка не отвечает «координата настоящая»",
		still_valid == 0, "осталось помеченных %d" % still_valid)
	# Новый набор обязан занять именно освобождённые строки
	var reused := 0
	var fresh: Array = []
	for i in range(20):
		var u: Unit = Spear.instantiate()
		u.faction = Constants.FACTION_PLAYER
		world.add_child(u)
		u.global_position = Vector3(40.0 + float(i), 0.0, 40.0)
		fresh.append(u)
		if freed.has(u._soa):
			reused += 1
	ok("E3 новые бойцы заняли освобождённые строки", reused == 20,
		"переиспользовано %d из 20" % reused)
	await _frames(2)
	var leaked := 0
	for u in fresh:
		if not is_equal_approx(A.hp[u._soa], u.current_health):
			leaked += 1
	ok("E4 в переиспользованной строке нет чисел прошлого жильца",
		leaked == 0, "расхождений %d" % leaked)

	print("\n───── F. ОТРЯД ПИШЕТСЯ В СТРОКУ ─────")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	GameManager.add_to_squad(sid, fresh[0])
	ok("F1 номер отряда в строке", A.sq[fresh[0]._soa] == sid,
		"в строке %d, отряд %d" % [A.sq[fresh[0]._soa], sid])
	GameManager.remove_from_squad(fresh[0])
	ok("F2 при выбытии номер снят", A.sq[fresh[0]._soa] == 0)

	print("\n───── G. РАБОЧИЙ НЕ ТЕРЯЕТ СТРОКУ НА ДОБЫЧЕ ─────")
	# РЕГРЕСС, КОТОРЫЙ ЭТО ЛОВИТ. Worker переопределяет tick_physics и в ветках
	# GATHERING/BUILDING/RETURNING до super() не доходит — там стоял вызов
	# unit_grid.update(), ставший заглушкой после перехода на плоскую сетку.
	# Строка переставала обновляться, и когда из неё стал браться кадр
	# отрисовки, спрайт рабочего замирал на месте последней записи (у замка),
	# махал молотком по воздуху и «телепортировался» в конце работы
	var Wrk := load("res://scenes/units/Worker.tscn") as PackedScene
	var w: Unit = Wrk.instantiate()
	w.faction = Constants.FACTION_PLAYER
	world.add_child(w)
	w.global_position = Vector3(-20.0, 0.0, 60.0)
	await _frames(3)
	var trees: Array = []
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn != null and rn.resource_type == Constants.RESOURCE_WOOD:
			trees.append(rn)
			if trees.size() >= 40:
				break
	# Ближайшее дерево к рабочему, чтобы он дошёл за разумное число кадров
	var best: ResourceNode = null
	var best_d := INF
	for rn in trees:
		var d: float = rn.global_position.distance_to(w.global_position)
		if d < best_d:
			best_d = d
			best = rn
	ok("G1 дерево для добычи нашлось", best != null)
	if best != null:
		# Ставим рабочего вплотную: стенд проверяет СИНХРОННОСТЬ СТРОКИ во время
		# работы, а не то, за сколько кадров он дойдёт через лес
		w.global_position = best.global_position + Vector3(2.0, 0.0, 0.0)
		w.sync_row()
		await _frames(2)
		w.command_gather(best)
		# Ждём, пока рабочий действительно возьмётся за работу
		var got := false
		for _i in range(900):
			await get_tree().physics_frame
			if w.state == Unit.State.GATHERING or w.state == Unit.State.RETURNING:
				got = true
				break
		ok("G2 рабочий дошёл и взялся за дело", got, "состояние %d" % w.state)
		var worst_w := 0.0
		for _i in range(120):
			await get_tree().physics_frame
			var i2: int = w._soa
			if i2 < 0:
				continue
			var d: float = Vector2(A.px[i2] - w.global_position.x,
				A.pz[i2] - w.global_position.z).length()
			if d > worst_w:
				worst_w = d
		ok("G3 строка идёт за узлом во время работы", worst_w < 0.5,
			"худшее расхождение %.3f м" % worst_w)

	print("\n=== ЯДРО АРМИИ: провалов: %d из %d ===" % [_fail, _checks])
	get_tree().quit(1 if _fail > 0 else 0)
