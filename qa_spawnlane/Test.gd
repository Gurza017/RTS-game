extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_spawnlane — ПОЛОСЫ ВЫХОДА ИЗ ВОРОТ НЕ УЕЗЖАЮТ ЗА КАРТУ
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: при найме нескольких отрядов подряд часть выходит из дверей барака,
## а часть собирается где-то на отшибе (внизу у леса) и бежит оттуда.
##
## Причина — счётчик полос выхода Building._exit_lane. Полосы разводят отряды,
## выходящие из одних ворот, чтобы они не толкались в дверях, но счётчик рос
## БЕЗ ПРЕДЕЛА и никогда не сбрасывался: полоса N уводит точку сбора на
## (N+1)/2 × lane_step (~6-8 м) вбок. Пятнадцатый заказ собирался в шести
## десятках метров от ворот, тридцатый — за краем карты.
##
## Тот же счётчик уже ловили на НАЗНАЧЕННОЙ точке сбора (qa_rally2 F8) и
## обезвредили только там; путь «без флажка» остался.
##
## Проверяется СВОЙСТВО, а не число: отступ вбок ограничен и НЕ РАСТЁТ с
## номером заказа. Границу стенд считает из тех же констант, что и код.
##
## Запуск: godot --headless --path . res://qa_spawnlane/Test.tscn

const ORDERS := 20        ## сколько заказов подряд даём одному бараку
const SQUAD  := 3         ## бойцов в заказе (мелкий — чтобы стенд был быстрым)

var main = null
var _pass: int = 0
var _fail: int = 0
var _trash: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _new_barracks(at: Vector3) -> Building:
	var b: Building = Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(at.x, 0.0, at.z)
	_trash.append(b)
	return b

## Один заказ; ждём, пока все бойцы войдут в дерево. Пауза между шеренгами
## (ROW_RELEASE_SEC) стенду не нужна — гасим её, как это делают другие стенды
func _train(b: Building, size: int) -> Array:
	var before: Array = get_tree().get_nodes_in_group("player_units").duplicate()
	b.squad_size = size
	b.queue_unit("spearman", {}, 0.01)
	if not b.production_queue.is_empty():
		(b.production_queue[0] as Dictionary)["time"] = 0.01
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000:
		b._row_gate = 0.0
		await get_tree().process_frame
		if get_tree().get_nodes_in_group("player_units").size() >= before.size() + size:
			break
	var fresh: Array = []
	for n in get_tree().get_nodes_in_group("player_units"):
		if not (n in before):
			fresh.append(n)
			_trash.append(n)
	return fresh

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	var b := _new_barracks(Vector3(-40.0, 0.0, -40.0))
	await frames(3)
	var gate: Vector3 = b._gate_position()
	var exit_dir: Vector3 = b.spawn_offset
	exit_dir.y = 0.0
	exit_dir = exit_dir.normalized()
	var side := Vector3(-exit_dir.z, 0.0, exit_dir.x)

	# ГРАНИЦА СЧИТАЕТСЯ ИЗ КОНСТАНТ КОДА, а не вписывается числом
	var cols: int = Building.square_cols(SQUAD, b.squad_cols)
	var blob: float = sqrt(float(SQUAD)) * 0.7
	var lane_step: float = maxf(float(cols) * b.squad_spacing, blob) \
		+ Building.EXIT_LANE_GAP
	var max_lane: float = float(Building.EXIT_LANES / 2) * lane_step
	var half_w: float = float(cols - 1) * 0.5 * b.squad_spacing
	var limit: float = max_lane + half_w + 0.5

	print("\n───── ИСХОДНЫЕ ─────")
	print("  барак в (%.0f, %.0f), ворота (%.1f, %.1f), полос %d, шаг полосы %.2f м"
		% [b.global_position.x, b.global_position.z, gate.x, gate.z,
		Building.EXIT_LANES, lane_step])
	print("  предел бокового отступа: %.2f м" % limit)

	print("\n───── A. %d ЗАКАЗОВ ПОДРЯД ИЗ ОДНОГО БАРАКА ─────" % ORDERS)
	var lat_by_order: Array = []
	var worst := 0.0
	var off_map := 0
	for k in range(ORDERS):
		var fresh: Array = await _train(b, SQUAD)
		# Отступ берётся ЗНАКОВЫЙ и по центру отряда: полосы 1 и 2 отходят на
		# одну и ту же величину в РАЗНЫЕ стороны, и по модулю они неразличимы
		var lat_sum := 0.0
		var cnt := 0
		for n in fresh:
			var u := n as Unit
			if u == null:
				continue
			var d: Vector3 = u.move_target - gate
			d.y = 0.0
			lat_sum += d.dot(side)
			cnt += 1
			if absf(u.move_target.x) > GameManager.map_lim_x + 0.01 \
					or absf(u.move_target.z) > GameManager.map_lim_z + 0.01:
				off_map += 1
		var lat: float = lat_sum / maxf(float(cnt), 1.0)
		lat_by_order.append(lat)
		worst = maxf(worst, absf(lat))
		if k < 3 or k >= ORDERS - 3:
			print("    заказ %2d: отступ вбок %+.2f м" % [k + 1, lat])

	verdict("A1 боковой отступ ограничен", worst <= limit,
		"худший %.2f м при пределе %.2f м" % [worst, limit])

	# ГЛАВНОЕ СВОЙСТВО: полосы ходят ПО КРУГУ, а не растут. Проверяем именно
	# периодичность с шагом EXIT_LANES — она и означает «роста нет».
	# Сравнивать «последние против первых» тут нельзя: внутри цикла значение
	# законно скачет (полоса 0 даёт 0 м, полоса 4 — два шага вбок)
	var per_err := 0.0
	var per_n := 0
	for k in range(ORDERS - Building.EXIT_LANES):
		var a: float = float(lat_by_order[k])
		var c: float = float(lat_by_order[k + Building.EXIT_LANES])
		per_err = maxf(per_err, absf(a - c))
		per_n += 1
	verdict("A2 полосы ходят по кругу, отступ не растёт",
		per_n > 0 and per_err < 0.01,
		"сравнений %d, худшее расхождение периода %.4f м" % [per_n, per_err])

	verdict("A3 ни одна точка сбора не ушла за карту", off_map == 0,
		"за картой точек: %d" % off_map)

	print("\n───── B. СОСЕДНИЕ ЗАКАЗЫ ВСЁ ЕЩЁ РАСХОДЯТСЯ ─────")
	# Ради ограничения полос нельзя потерять то, ради чего полосы заводились:
	# два заказа подряд обязаны собираться в РАЗНЫХ местах. Именно это ломала
	# первая версия фикса, обнулявшая счётчик на простое здания (qa_rally2
	# E7/E8: центры отрядов в 0.71 м, 17 бойцов вплотную к чужим)
	var min_gap := INF
	for k in range(ORDERS - 1):
		var a: float = float(lat_by_order[k])
		var c: float = float(lat_by_order[k + 1])
		min_gap = minf(min_gap, absf(a - c))
	verdict("B1 соседние заказы не садятся в одну точку", min_gap > 0.5,
		"худший разрыв между соседними заказами %.2f м" % min_gap)
	verdict("B2 счётчик полос ограничен сверху", b._exit_lane < Building.EXIT_LANES,
		"счётчик = %d при пределе %d" % [b._exit_lane, Building.EXIT_LANES])

	print("\n───── C. БОЙЦЫ ПОЯВЛЯЮТСЯ У ВОРОТ, А НЕ В ПОЛЕ ─────")
	# Позиция появления задана в _place_spawned жёстко воротами; проверяем, что
	# свежий боец физически стоит у здания, а не возникает за десятки метров
	var b2 := _new_barracks(Vector3(40.0, 0.0, 40.0))
	await frames(3)
	var gate2: Vector3 = b2._gate_position()
	var before2: Array = get_tree().get_nodes_in_group("player_units").duplicate()
	b2.squad_size = SQUAD
	b2.queue_unit("spearman", {}, 0.01)
	if not b2.production_queue.is_empty():
		(b2.production_queue[0] as Dictionary)["time"] = 0.01
	var far_spawn := 0
	var seen := 0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and seen < SQUAD:
		b2._row_gate = 0.0
		await get_tree().process_frame
		for n in get_tree().get_nodes_in_group("player_units"):
			if n in before2:
				continue
			before2.append(n)
			_trash.append(n)
			seen += 1
			var p: Vector3 = (n as Node3D).global_position
			var dist: float = Vector2(p.x - gate2.x, p.z - gate2.z).length()
			if dist > 3.0:
				far_spawn += 1
	verdict("C1 все появились вплотную к воротам", far_spawn == 0,
		"далеко от ворот: %d из %d" % [far_spawn, seen])

	print("\n───── D. ШЕСТЬ БАРАКОВ: КАЖДЫЙ ВЫПУСКАЕТ У СВОИХ ВОРОТ ─────")
	# Жалоба пришла именно с несколькими бараками. Здания ставим В РАЗНЫХ
	# четвертях карты: правило ворот — «фасад к середине карты», так что у
	# каждого барака своё направление выхода, и ошибка в осях (мировые вместо
	# собственных) вылезла бы сразу
	var spots := [
		Vector3(-70.0, 0.0, -50.0), Vector3(70.0, 0.0, -50.0),
		Vector3(-70.0, 0.0, 50.0),  Vector3(70.0, 0.0, 50.0),
		Vector3(0.0, 0.0, -60.0),   Vector3(0.0, 0.0, 60.0),
	]
	var yards: Array = []
	for s in spots:
		yards.append(_new_barracks(s))
	await frames(4)

	var worst_gate := 0.0        # как далеко от СВОИХ ворот появился боец
	var worst_front := 0.0       # насколько выход ушёл вбок от фасада
	var wrong_yard := 0          # появился ближе к ЧУЖОМУ бараку
	var spawned := 0
	for bb in yards:
		var yard := bb as Building
		var g: Vector3 = yard._gate_position()
		# Ворота обязаны лежать РОВНО перед НАРИСОВАННЫМ фасадом.
		#
		# Здесь стоял front_dir() — «от постройки к середине карты». Ровно это
		# рассогласование и оказалось причиной жалобы «бойцы выходят сбоку»:
		# картинка здания прибита фасадом к мировому +Z и от положения на карте
		# не зависит вовсе, а ворота считались по карте. Проверка честно мерила
		# снос относительно НЕВЕРНОЙ оси и потому была зелёной, пока баг был жив.
		# Сверяемся с тем же, с чем сверяется игрок глазами, — с фасадом
		var fd: Vector3 = yard.facade_dir()
		var to_gate: Vector3 = g - yard.global_position
		to_gate.y = 0.0
		var sidew: float = absf(to_gate.dot(Vector3(-fd.z, 0.0, fd.x)))
		worst_front = maxf(worst_front, sidew)
		# …и лежать СНАРУЖИ передней стены, а не внутри коробки здания
		if to_gate.dot(fd) < yard.build_size.z * 0.5:
			worst_front = maxf(worst_front, 99.0)

		var seen_before: Array = get_tree().get_nodes_in_group("player_units").duplicate()
		yard.squad_size = SQUAD
		yard.queue_unit("spearman", {}, 0.01)
		if not yard.production_queue.is_empty():
			(yard.production_queue[0] as Dictionary)["time"] = 0.01
		var got := 0
		var tt: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - tt < 15000 and got < SQUAD:
			yard._row_gate = 0.0
			await get_tree().process_frame
			for n in get_tree().get_nodes_in_group("player_units"):
				if n in seen_before:
					continue
				seen_before.append(n)
				_trash.append(n)
				got += 1
				spawned += 1
				var p: Vector3 = (n as Node3D).global_position
				var dg: float = Vector2(p.x - g.x, p.z - g.z).length()
				worst_gate = maxf(worst_gate, dg)
				# Ближе ли он к чужому бараку, чем к своему
				for other in yards:
					if other == yard:
						continue
					var og: Vector3 = (other as Building)._gate_position()
					if Vector2(p.x - og.x, p.z - og.z).length() < dg:
						wrong_yard += 1
						break

	verdict("D1 ворота стоят прямо перед фасадом, не сбоку", worst_front < 0.01,
		"худший боковой снос ворот %.4f м" % worst_front)
	verdict("D2 каждый боец появился у ворот СВОЕГО барака", worst_gate < 3.0,
		"бойцов %d, худшее удаление от своих ворот %.2f м" % [spawned, worst_gate])
	verdict("D3 никто не появился у чужого барака", wrong_yard == 0,
		"чужих появлений: %d" % wrong_yard)

	print("\n═══ qa_spawnlane: прошло %d, провалов: %d ═══" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
