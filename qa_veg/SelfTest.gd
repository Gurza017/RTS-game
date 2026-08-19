extends Node

## РАСТИТЕЛЬНОСТЬ В ОБЩЕМ MultiMesh: КАРТИНКА ОБЯЗАНА ОСТАТЬСЯ ПРЕЖНЕЙ.
##
## Снимок глазами тут не помощник: карта генерируется случайно, и два прогона
## несравнимы попиксельно. Поэтому сверяются ЧИСЛА — ровно те, что раньше
## задавал узел-спрайт дерева:
##     quad.size = (5.0 * frame_aspect, 5.0);  position.y = 2.5
## В MultiMesh то же самое выражено мешем единичной высоты с пропорциями кадра
## плюс равномерный масштаб 5.0 в трансформе экземпляра. Если обе записи дают
## одну и ту же нарисованную ширину/высоту и одну и ту же мировую точку —
## картинка не изменилась.
##
## Запуск: godot --headless --path . res://qa_veg/SelfTest.tscn

const _BBUtil := preload("res://scripts/BillboardUtil.gd")
const STRIDE := 16

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
		await get_tree().process_frame

## Прочитать трансформ экземпляра прямо из теневого буфера бакета
func _inst(slot) -> Dictionary:
	var b = slot.bucket
	var o: int = slot.index * STRIDE
	return {
		"sx":  b.buf[o], "sy": b.buf[o + 5], "sz": b.buf[o + 10],
		"pos": Vector3(b.buf[o + 3], b.buf[o + 7], b.buf[o + 11]),
		"phase": b.buf[o + 12], "cycle": b.buf[o + 13],
	}

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(5)
	# ── ТУМАН ВЫКЛЮЧЕН НАМЕРЕННО ────────────────────────────────────────────
	# Пространственный звук и дрожание ствола теперь ГЛУШАТСЯ вне освещённой
	# зоны (защита от «нахожу базу врага на слух», см. AudioManager._audible_at
	# и ResourceNode.shake). Этот стенд проверяет не туман, а сам звук/дрожь, и
	# ставит свои объекты там, где своих юнитов нет, — то есть в темноте.
	# enabled = false заставляет is_lit отвечать «видно везде» (штатный
	# выключатель FogOfWar), и стенд снова меряет то, ради чего написан.
	# Саму отсечку по туману стережёт qa_fog
	if GameManager.fog != null:
		GameManager.fog.enabled = false

	var trees: Array = []
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn != null and rn.resource_type == Constants.RESOURCE_WOOD:
			trees.append(rn)

	print("\n───── A. ДЕРЕВЬЯ ПЕРЕЕХАЛИ В ОБЩУЮ ОТРИСОВКУ ─────")
	ok("A1 деревья на карте есть", trees.size() > 100,
		"деревьев %d" % trees.size())
	var with_slot := 0
	var with_node := 0
	for rn in trees:
		if rn._veg_slot != null:
			with_slot += 1
		for ch in rn._visual_root.get_children():
			if ch is MeshInstance3D:
				with_node += 1
	ok("A2 у каждого дерева есть место в MultiMesh",
		with_slot == trees.size(), "%d из %d" % [with_slot, trees.size()])
	ok("A3 своих узлов-спрайтов у деревьев не осталось", with_node == 0,
		"узлов %d" % with_node)
	var buckets: int = GameManager.veg.bucket_count()
	ok("A4 бакетов единицы, а не тысячи", buckets > 0 and buckets <= 16,
		"бакетов %d на %d растений" % [buckets, GameManager.veg.planted_count()])

	print("\n───── B. ГЕОМЕТРИЯ СОВПАДАЕТ С ПРЕЖНИМ УЗЛОМ ─────")
	var t: ResourceNode = trees[0]
	var inf := _inst(t._veg_slot)
	# Прежний узел: quad.size.y = 5.0, mesh_instance.position.y = 2.5
	ok("B1 масштаб экземпляра = высоте дерева",
		is_equal_approx(inf["sx"], ResourceNode.TREE_HEIGHT)
		and is_equal_approx(inf["sy"], ResourceNode.TREE_HEIGHT)
		and is_equal_approx(inf["sz"], ResourceNode.TREE_HEIGHT),
		"%.3f/%.3f/%.3f при TREE_HEIGHT=%.1f" % [inf["sx"], inf["sy"], inf["sz"],
			ResourceNode.TREE_HEIGHT])
	var want_pos: Vector3 = t.global_position + Vector3(0.0, ResourceNode.TREE_HEIGHT * 0.5, 0.0)
	ok("B2 центр квада там же, где был у узла (+2.5 м над основанием)",
		(inf["pos"] as Vector3).distance_to(want_pos) < 0.001,
		"%s против %s" % [str(inf["pos"]), str(want_pos)])
	# Нарисованная ширина: меш бакета — (aspect, 1.0), масштаб — TREE_HEIGHT
	var tex: Texture2D = t._veg_tex
	var aspect: float = _BBUtil.frame_aspect(tex)
	var quad: QuadMesh = t._veg_slot.bucket.mm.mesh
	ok("B3 меш бакета — квад единичной высоты с пропорциями КАДРА",
		is_equal_approx(quad.size.y, 1.0) and is_equal_approx(quad.size.x, aspect),
		"меш %s, пропорции кадра %.4f" % [str(quad.size), aspect])
	var drawn_w: float = quad.size.x * ResourceNode.TREE_HEIGHT
	var drawn_h: float = quad.size.y * ResourceNode.TREE_HEIGHT
	ok("B4 нарисованный размер = прежнему (5.0*aspect на 5.0)",
		is_equal_approx(drawn_w, ResourceNode.TREE_HEIGHT * aspect)
		and is_equal_approx(drawn_h, ResourceNode.TREE_HEIGHT),
		"%.3f x %.3f" % [drawn_w, drawn_h])
	ok("B5 у бакета один материал на всех", quad.material != null)

	print("\n───── C. РАЗБРОС ВЕТРА СОХРАНЁН ─────")
	var phases: Dictionary = {}
	var cycles: Dictionary = {}
	var n_check: int = mini(trees.size(), 200)
	# Округление ТОНКОЕ: при шаге 0.01 всего сто возможных значений, и на двухстах
	# деревьях совпадения неизбежны по принципу Дирихле — стенд ловил бы не
	# отсутствие разброса, а собственную сетку округления (было 86 из 200)
	for i in range(n_check):
		var f := _inst(trees[i]._veg_slot)
		phases[snappedf(f["phase"], 0.0001)] = true
		cycles[snappedf(f["cycle"], 0.0001)] = true
	ok("C1 фаза колыхания у каждого своя", phases.size() > n_check * 9 / 10,
		"разных фаз %d на %d деревьев" % [phases.size(), n_check])
	ok("C2 длительность цикла тоже своя", cycles.size() > n_check * 9 / 10,
		"разных циклов %d" % cycles.size())

	print("\n───── D. РУБКА: ДРОЖАНИЕ И ПЕНЬ ─────")
	var t2: ResourceNode = trees[1]
	var base: Vector3 = (_inst(t2._veg_slot)["pos"] as Vector3)
	t2.shake()
	await _frames(3)
	var shaken: Vector3 = (_inst(t2._veg_slot)["pos"] as Vector3)
	ok("D1 ствол дрожит при рубке", shaken.distance_to(base) > 0.001,
		"сдвиг %.4f м" % shaken.distance_to(base))
	# Дожидаемся затухания
	await _frames(120)
	var settled: Vector3 = (_inst(t2._veg_slot)["pos"] as Vector3)
	ok("D2 после рубки возвращается ТОЧНО на место",
		settled.distance_to(base) < 0.0001,
		"остаточный сдвиг %.6f м" % settled.distance_to(base))

	var t3: ResourceNode = trees[2]
	var b3 = t3._veg_slot.bucket
	var idx3: int = t3._veg_slot.index
	var free_before: int = b3.free.size()
	t3.extract(t3.remaining + 10.0)     # выбираем дерево целиком → пень
	await _frames(3)
	ok("D3 срубленное дерево снято с отрисовки", t3._veg_slot == null)
	ok("D4 место освобождено под следующее растение",
		b3.free.size() == free_before + 1,
		"свободных мест %d → %d" % [free_before, b3.free.size()])
	var zeroed := true
	for k in range(STRIDE):
		if not is_equal_approx(b3.buf[idx3 * STRIDE + k], 0.0):
			zeroed = false
			break
	ok("D5 экземпляр погашен нулевой матрицей", zeroed)
	ok("D6 пень на месте появился", t3._stump_node != null)

	print("\n=== РАСТИТЕЛЬНОСТЬ: провалов: %d из %d ===" % [_fail, _checks])
	get_tree().quit(1 if _fail > 0 else 0)
