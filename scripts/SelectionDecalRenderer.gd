extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## КОЛЬЦА И ТЕНИ ВЫДЕЛЕНИЯ: ДВА MultiMesh НА ВСЮ АРМИЮ
## ═══════════════════════════════════════════════════════════════════════════
## Было: Unit.set_selected() вешал на КАЖДОГО выделенного бойца ДВА новых узла
## MeshInstance3D — кольцо и мини-тень. На выделенных 15 отрядах (810 моделей)
## это 1620 дополнительных объектов отрисовки поверх самих спрайтов; замер
## qa_march_perf показал рост вызовов отрисовки с 1124 до 2744 ровно в момент
## выделения. Игрок отправляет войска именно выделенными — отсюда и разрыв
## между «стоят 70 FPS» и «пошли — 4 FPS».
##
## Стало: два MultiMeshInstance3D на всю партию (кольца и тени), боец занимает
## в них по слоту. Меши и материалы у колец с тенями и раньше были ОБЩИЕ
## (UnitVisuals.ring_mesh/shadow_mesh — статические синглтоны), так что
## изображение не меняется ни на пиксель, меняется только способ подачи.
##
## Ограничения те же, что у FarUnitRenderer: БЕЗ custom_data (открытый баг
## GL Compatibility godot/godot#96503), только transform. Тон здесь не нужен
## вовсе — цвет вшит в общий материал меша.
##
## ПОДАЧА — ТОЖЕ ОДНИМ set_buffer НА СЛОЙ ЗА КАДР (см. шапку FarUnitRenderer):
## поштучный set_instance_transform на каждого выделенного бойца — это два
## обращения в RenderingServer на модель в кадр, а выделенный отряд как раз и
## идёт маршем. Слой держит теневую копию буфера, flush() отдаёт её целиком.
## Раскладка: 12 float на экземпляр (TRANSFORM_3D, use_colors здесь не нужен).
##
## Владелец — GameManager (по аналогии с far_units/unit_grid): RefCounted не
## может сам быть узлом дерева, MultiMeshInstance3D добавляется в мир через
## переданный world_root.

const _Vis := preload("res://scripts/units/UnitVisuals.gd")

const GROW_STEP := 128

class Layer:
	## Только трансформ, без цвета: 3×4 матрица построчно
	const STRIDE := 12

	var mmi: MultiMeshInstance3D
	var mm: MultiMesh
	var free: Array = []
	var capacity: int = 0
	var buf: PackedFloat32Array = PackedFloat32Array()
	var dirty: bool = false

	## Все записи в буфер — внутри класса-владельца: снаружи `l.buf[i] = x`
	## копировал бы весь массив на каждый float (Packed-массивы — значения
	## с копированием при записи). См. ту же оговорку в FarUnitRenderer
	func grow(step: int) -> void:
		var new_cap: int = capacity + step
		buf.resize(new_cap * STRIDE)   # нули = спрятанный слот
		mm.instance_count = new_cap
		capacity = new_cap
		dirty = true

	## basis задаётся построчно: b0/b1/b2 — строки матрицы 3×3
	func write(idx: int, b0: Vector3, b1: Vector3, b2: Vector3, pos: Vector3) -> void:
		var o: int = idx * STRIDE
		buf[o]      = b0.x
		buf[o + 1]  = b0.y
		buf[o + 2]  = b0.z
		buf[o + 3]  = pos.x
		buf[o + 4]  = b1.x
		buf[o + 5]  = b1.y
		buf[o + 6]  = b1.z
		buf[o + 7]  = pos.y
		buf[o + 8]  = b2.x
		buf[o + 9]  = b2.y
		buf[o + 10] = b2.z
		buf[o + 11] = pos.z
		dirty = true

	## Спрятать слот — нулевая матрица (вырожденный треугольник растеризатор
	## отбрасывает сразу; MultiMesh не умеет «скрыть экземпляр»)
	func hide_slot(idx: int) -> void:
		var o: int = idx * STRIDE
		for i in range(STRIDE):
			buf[o + i] = 0.0
		dirty = true

	func hide_all() -> void:
		for i in range(buf.size()):
			buf[i] = 0.0
		dirty = true

	func flush() -> void:
		if not dirty:
			return
		dirty = false
		if capacity > 0:
			mm.set_buffer(buf)

var _rings: Layer = null
var _shadows: Layer = null
var _slot: Dictionary = {}      # Unit -> int (индекс слота, общий для обоих слоёв)
var _last_pos: Dictionary = {}  # Unit -> Vector3 (чтобы не переписывать неподвижных)

## ── ТРЕТИЙ СЛОЙ: КРАСНЫЕ КОЛЬЦА ПРИЦЕЛИВАНИЯ ────────────────────────────────
## Когда курсор наведён на чужой отряд, под ним загораются красные кольца — та
## же обратная связь, что жёлтые кольца у своих. Отдельный слой, а не второй
## смысл у существующего: цвет вшит в материал МЕША (см. UnitVisuals), поэтому
## «то же кольцо другим цветом» технически означает другой меш, а значит и
## другой MultiMesh. Тени этому слою не полагаются — тень под ногами это признак
## своего выделения, а не прицела.
##
## Слой ДЕШЁВЫЙ по построению: под курсором всегда не больше одного отряда, то
## есть десятки экземпляров против сотен у выделения
var _hover: Layer = null
## ── ЗДАНИЯМ СВОЙ СЛОЙ, А НЕ ЧУЖОЙ МЕШ В МАСШТАБЕ ──────────────────────────
## Разные меши в одном MultiMesh не живут: буфер хранит трансформы, а меш у
## слоя один на всех. Кольцо бойца и контур здания — РАЗНЫЕ меши (см. разбор у
## _Vis.building_ring_mesh), значит и слоя должно быть два.
##
## Заводится ЛЕНИВО, как и все остальные: пока игрок не навёлся ни на одну
## постройку, узла нет вовсе и вызовов отрисовки он не стоит. Наведён — это
## ОДИН вызов на все подсвеченные постройки разом, сколько бы их ни было
var _hover_b: Layer = null
## Кто из подсвеченных живёт в слое зданий (иначе снять слот не с того слоя)
var _hover_in_b: Dictionary = {}
var _hover_slot: Dictionary = {}
var _hover_last: Dictionary = {}

func _make_layer(mesh: Mesh, world_root: Node3D) -> Layer:
	var l := Layer.new()
	l.mm = MultiMesh.new()
	l.mm.transform_format = MultiMesh.TRANSFORM_3D
	l.mm.mesh = mesh
	l.mm.instance_count = 0
	l.mmi = MultiMeshInstance3D.new()
	l.mmi.multimesh = l.mm
	# Метки лежат на земле и не должны исчезать, когда центр строя уехал за
	# край экрана: пирамиду видимости считает один общий узел на всю армию
	l.mmi.extra_cull_margin = 16384.0
	world_root.add_child(l.mmi)
	return l

func _ensure(world_root: Node3D) -> void:
	if _rings == null:
		_rings = _make_layer(_Vis.ring_mesh(), world_root)
	if _shadows == null:
		_shadows = _make_layer(_Vis.shadow_mesh(), world_root)

func _grow() -> void:
	var new_cap: int = _rings.capacity + GROW_STEP
	_rings.grow(GROW_STEP)
	_shadows.grow(GROW_STEP)
	# Реестр свободных слотов ведётся ОДИН на оба слоя: индекс у кольца и у тени
	# одного бойца всегда совпадает
	for i in range(new_cap - GROW_STEP, new_cap):
		_rings.free.append(i)

## Показать метки под бойцом. Идемпотентно: повторный вызов ничего не ломает
func register(unit: Unit, world_root: Node3D) -> void:
	if _slot.has(unit):
		return
	_ensure(world_root)
	if _rings.free.is_empty():
		_grow()
	var idx: int = _rings.free.pop_back()
	_slot[unit] = idx
	# ТОЧКА — НАРИСОВАННАЯ, А НЕ ЛОГИЧЕСКАЯ (см. Unit.draw_position): метка лежит
	# под ногами спрайта, а спрайт сглаживается между физическими шагами
	var dp: Vector3 = unit.draw_position()
	_write(idx, dp)
	_last_pos[unit] = dp

## Убрать метки. Идемпотентно
func unregister(unit: Unit) -> void:
	_drop_slot(unit)

## ── СНЯТИЕ СЛОТА БЕЗ ОБРАЩЕНИЯ К ОБЪЕКТУ ────────────────────────────────────
## Принимает Variant, а не Unit, и это не небрежность: ключом словаря может
## оказаться УЖЕ ОСВОБОЖДЁННЫЙ объект (см. update_all), а typed-параметр
## `unit: Unit` на таком аргументе бросает «Trying to assign invalid previously
## freed instance» ровно в момент вызова — то есть уборщик падал бы на том же
## самом мусоре, который пришёл убирать. Тело функции объект не трогает вовсе:
## всё, что ей нужно, — это номер слота из словаря
func _drop_slot(unit) -> void:
	if not _slot.has(unit):
		return
	var idx: int = _slot[unit]
	_rings.hide_slot(idx)
	_shadows.hide_slot(idx)
	_rings.free.append(idx)
	_slot.erase(unit)
	_last_pos.erase(unit)

func is_registered(unit: Unit) -> bool:
	return _slot.has(unit)

func registered_count() -> int:
	return _slot.size()

## Строки матрицы поворота, разложенные ОДИН раз: у кольца — единичная, у тени
## — поворот на -90° по X (тень лежит плашмя). Раскладывать Basis на строки в
## каждой записи незачем, они постоянны
const _ID0 := Vector3(1.0, 0.0, 0.0)
const _ID1 := Vector3(0.0, 1.0, 0.0)
const _ID2 := Vector3(0.0, 0.0, 1.0)
const _SH0 := Vector3(1.0, 0.0, 0.0)
const _SH1 := Vector3(0.0, 0.0, 1.0)
const _SH2 := Vector3(0.0, -1.0, 0.0)

## Смещения по высоте те же, что были у отдельных узлов (UnitVisuals.RING_Y /
## SHADOW_Y), и тень так же положена плашмя поворотом на -90° по X
func _write(idx: int, pos: Vector3) -> void:
	_rings.write(idx, _ID0, _ID1, _ID2,
		Vector3(pos.x, pos.y + _Vis.RING_Y, pos.z))
	_shadows.write(idx, _SH0, _SH1, _SH2,
		Vector3(pos.x, pos.y + _Vis.SHADOW_Y, pos.z))

# ═════════════════════════════════════════════════════════════════════════════
# КОЛЬЦА ПРИЦЕЛИВАНИЯ
# ═════════════════════════════════════════════════════════════════════════════

## Задать НАБОР подсвеченных врагов целиком. Именно набором, а не по одному:
## наведение опрашивается по таймеру и каждый раз отвечает «вот этот отряд», а
## разницу с прошлым разом считать удобнее здесь, чем в четырёх местах вызова.
## Повторный вызов с тем же составом не трогает буфер вовсе
func set_hover_units(units: Array, world_root: Node3D) -> void:
	# Кого гасим: был подсвечен, в новом наборе его нет
	var keep: Dictionary = {}
	for u in units:
		if is_instance_valid(u) and (u is Unit or u is Building):
			keep[u] = true
	var drop: Array = []
	for u in _hover_slot:
		# Мёртвых гасим тоже — набор приходит с опроса курсора, а между двумя
		# опросами подсвеченный отряд успевают вырезать наполовину
		if not keep.has(u) or not is_instance_valid(u):
			drop.append(u)
	for u in drop:
		_hover_drop(u)
	if keep.is_empty():
		return
	for u in keep:
		if _hover_slot.has(u):
			continue
		var is_b: bool = u is Building
		var lay: Layer = _hover_b if is_b else _hover
		if lay == null:
			lay = _make_layer(_Vis.building_ring_mesh() if is_b
				else _Vis.hover_ring_mesh(), world_root)
			if is_b:
				_hover_b = lay
			else:
				_hover = lay
		if lay.free.is_empty():
			var new_cap: int = lay.capacity + GROW_STEP
			lay.grow(GROW_STEP)
			for i in range(new_cap - GROW_STEP, new_cap):
				lay.free.append(i)
		var idx: int = lay.free.pop_back()
		_hover_slot[u] = idx
		_hover_in_b[u] = is_b
		var hp3: Vector3 = (u as Node3D).global_position
		_hover_write(idx, hp3,
			building_ring_scale(u) if is_b else 1.0, is_b)
		_hover_last[u] = hp3

# ═════════════════════════════════════════════════════════════════════════════
# УКАЗАТЕЛИ ОТДАННОГО ПРИКАЗА
# ═════════════════════════════════════════════════════════════════════════════
## Два слоя, оба поверх той же машинерии, что и кольца выделения.
##
## ЗАЧЕМ. Игрок отдал приказ и через полминуты не помнит, кому и куда. Кольца
## прицеливания (_hover) отвечают на вопрос «на кого я НАВЁЛСЯ», а эти — на
## вопрос «что этому отряду УЖЕ приказано». Поэтому они не гаснут по уходу
## курсора и появляются заново при повторном выделении отряда.
##
## Метка точки движения СНИМАЕТСЯ САМА, когда отряд дошёл: за этим следит
## владелец приказов (GameManager.squad_orders), сюда приходит уже готовый
## список того, что показывать в этом кадре.
var _order_ring: Layer = null            # красные кольца на приказанной цели
## Контур приказанного ЗДАНИЯ — свой слой по той же причине, что у наведения:
## меш у здания другой (см. _Vis.building_ring_mesh)
var _order_ring_b: Layer = null
var _order_slot: Dictionary = {}
var _order_in_b: Dictionary = {}
var _dest: Layer = null                  # метки точек, куда послан отряд
var _dest_n: int = 0

## КОЛЬЦА НА ЦЕЛИ ПРИКАЗА. Набором целиком, как и у прицеливания: разницу с
## прошлым кадром считать удобнее здесь, чем в местах вызова
func set_order_targets(units: Array, world_root: Node3D) -> void:
	var keep: Dictionary = {}
	for u in units:
		if is_instance_valid(u) and (u is Unit or u is Building):
			keep[u] = true
	var drop: Array = []
	for u in _order_slot:
		if not keep.has(u) or not is_instance_valid(u):
			drop.append(u)
	for u in drop:
		_order_drop(u)
	if keep.is_empty():
		return
	for u in keep:
		var pos: Vector3 = (u as Node3D).global_position
		var is_b: bool = u is Building
		var k: float = building_ring_scale(u) if is_b else 1.0
		var lay: Layer = _order_ring_b if is_b else _order_ring
		if lay == null:
			lay = _make_layer(_Vis.building_ring_mesh() if is_b
				else _Vis.hover_ring_mesh(), world_root)
			if is_b:
				_order_ring_b = lay
			else:
				_order_ring = lay
		if _order_slot.has(u):
			# Цель ЖИВАЯ и ходит: кольцо обязано ехать за ней, иначе оно
			# остаётся лежать там, где враг был в момент приказа
			lay.write(int(_order_slot[u]), Vector3(k, 0.0, 0.0), _ID1,
				Vector3(0.0, 0.0, k), Vector3(pos.x, pos.y + _Vis.RING_Y, pos.z))
			continue
		if lay.free.is_empty():
			var new_cap: int = lay.capacity + GROW_STEP
			lay.grow(GROW_STEP)
			for i in range(new_cap - GROW_STEP, new_cap):
				lay.free.append(i)
		var idx: int = lay.free.pop_back()
		_order_slot[u] = idx
		_order_in_b[u] = is_b
		lay.write(idx, Vector3(k, 0.0, 0.0), _ID1,
			Vector3(0.0, 0.0, k), Vector3(pos.x, pos.y + _Vis.RING_Y, pos.z))

func drop_order_target(u) -> void:
	_order_drop(u)

func _order_drop(u) -> void:
	if not _order_slot.has(u):
		return
	var lay: Layer = _order_ring_b if bool(_order_in_b.get(u, false)) else _order_ring
	if lay == null:
		return
	lay.hide_slot(int(_order_slot[u]))
	lay.free.append(int(_order_slot[u]))
	_order_slot.erase(u)
	_order_in_b.erase(u)

## МЕТКИ ТОЧЕК НАЗНАЧЕНИЯ. Не по объектам, а списком точек: их единицы (по
## одной на выделенный отряд), и держать под них словарь незачем — слой просто
## переписывается целиком каждый кадр.
##
## `phase` — время в секундах: от него метка мягко пульсирует. Пульсация здесь
## масштабом, а не прозрачностью: у кольца материал общий на весь слой, и
## менять в нём альфу означало бы мигать всеми метками разом
## Масштаб метки. Заказ владельца — вдвое меньше прежнего (было 5.0): метка
## обязана читаться как ТОЧКА, куда отряд идёт, а не как площадь, которую он
## займёт. Толщина линии при этом задана не здесь, а в самом меше
## (UnitVisuals.dest_ring_mesh) — масштаб тянул бы её вместе с радиусом
const DEST_SCALE := 2.5
const DEST_PULSE := 0.18

func set_move_marks(points: Array, world_root: Node3D, phase: float) -> void:
	if points.is_empty():
		if _dest != null and _dest_n > 0:
			for i in range(_dest_n):
				_dest.hide_slot(i)
			_dest_n = 0
		return
	if _dest == null:
		_dest = _make_layer(_Vis.dest_ring_mesh(), world_root)
	while _dest.capacity < points.size():
		_dest.grow(GROW_STEP)
	var k: float = DEST_SCALE * (1.0 + DEST_PULSE * sin(phase * 3.0))
	for i in range(points.size()):
		var p: Vector3 = points[i]
		_dest.write(i, Vector3(k, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
			Vector3(0.0, 0.0, k), Vector3(p.x, p.y + _Vis.RING_Y, p.z))
	# Лишние места прошлого кадра гасим: отряд сняли с выделения — метка ушла
	for i in range(points.size(), _dest_n):
		_dest.hide_slot(i)
	_dest_n = points.size()

func flush_orders() -> void:
	if _order_ring != null:
		_order_ring.flush()
	if _order_ring_b != null:
		_order_ring_b.flush()
	if _dest != null:
		_dest.flush()

## Снять бойца с прицельной подсветки. Идемпотентно и БЕЗ обращения к объекту —
## зовётся в том числе из Unit._exit_tree, то есть на уже умирающем бойце
func drop_hover(u) -> void:
	_hover_drop(u)

func _hover_drop(u) -> void:
	if not _hover_slot.has(u):
		return
	var lay: Layer = _hover_b if bool(_hover_in_b.get(u, false)) else _hover
	if lay == null:
		return
	lay.hide_slot(_hover_slot[u])
	lay.free.append(_hover_slot[u])
	_hover_slot.erase(u)
	_hover_in_b.erase(u)
	_hover_last.erase(u)

func _hover_write(idx: int, pos: Vector3, k: float = 1.0,
		in_b: bool = false) -> void:
	var lay: Layer = _hover_b if in_b else _hover
	if lay == null:
		return
	lay.write(idx, Vector3(k, 0.0, 0.0), _ID1, Vector3(0.0, 0.0, k),
		Vector3(pos.x, pos.y + _Vis.RING_Y, pos.z))

## ── КОНТУР ПОД ЗДАНИЕМ: РАДИУС ПО ЕГО ОСНОВАНИЮ ───────────────────────────
## Чужой боец и чужая постройка — одинаково законные цели приказа (см.
## SelectionManager.enemy_target_under_cursor), и обратная связь у них обязана
## быть одна: красный контур под тем, что накроет клик.
##
## ЗДАНИЕ ОБВОДИТСЯ СВОИМ МЕШЕМ (_Vis.building_ring_mesh), а не увеличенным
## кольцом бойца. Кольцо бойца — тор в 35 см о двенадцати сегментах; растянутое
## до замка оно давало толстый угловатый многоугольник (разбор — там же, у
## меша). Здешний тор единичного радиуса и тонкий, поэтому масштаб равен просто
## ПОЛОВИНЕ ГАБАРИТА постройки в метрах.
##
## Масштабируются ТОЛЬКО оси X и Z: тор лежит в горизонтальной плоскости, и
## общий масштаб поднял бы его над землёй колесом
static func building_ring_scale(n) -> float:
	var b := n as Building
	if b == null:
		return 1.0
	# Чуть шире самой коробки: контур обязан лежать ВОКРУГ основания, а не
	# резать его угол
	return maxf(b.build_size.x, b.build_size.z) * 0.5 + BUILD_RING_MARGIN

## Запас контура наружу от габарита постройки, метры
const BUILD_RING_MARGIN := 0.35

func clear_hover() -> void:
	for u in _hover_slot.keys():
		var lay: Layer = _hover_b if bool(_hover_in_b.get(u, false)) else _hover
		if lay == null:
			continue
		lay.hide_slot(_hover_slot[u])
		lay.free.append(_hover_slot[u])
	_hover_slot.clear()
	_hover_in_b.clear()
	_hover_last.clear()

func hover_count() -> int:
	return _hover_slot.size()

func is_hovered(unit: Unit) -> bool:
	return _hover_slot.has(unit)

## Подтянуть метки за сдвинувшимися бойцами. Зовётся раз в кадр из GameManager;
## неподвижных пропускаем — выделенный строй чаще стоит, чем идёт
##
## ── ПРОВЕРКА ЖИВОСТИ ИДЁТ ДО ПРИВЕДЕНИЯ К ТИПУ, И ЭТО НЕ ПРИДИРКА ────────────
## Здесь стояло `var u: Unit = unit` и лишь ПОСЛЕ него is_instance_valid(u).
## Порядок был обратный тому, что нужно: присваивание освобождённого объекта в
## типизированную переменную само по себе бросает «Trying to assign invalid
## previously freed instance» — то есть проверка, ради которой строка писалась,
## не успевала выполниться никогда. В редакторе это выбивает точку останова, а
## в бою на 2500+ юнитов ошибка печатается каждый кадр на каждого выбывшего:
## поток отладчика захлёбывается, картинка продолжает тикать, а физика и звук
## встают — тот самый «дедлок» из отчёта.
##
## Ключи словаря чистятся тут же: боец мог быть освобождён мимо _exit_tree
## (снос сцены, queue_free из стенда), и без уборки слот залипал бы навсегда
func update_all() -> void:
	_update_hover_positions()
	if _slot.is_empty():
		return
	var stale: Array = []
	for unit in _slot:
		if not is_instance_valid(unit):
			stale.append(unit)
			continue
		var u: Unit = unit
		var p: Vector3 = u.draw_position()
		var was: Vector3 = _last_pos.get(u, Vector3.INF)
		var dx: float = p.x - was.x
		var dz: float = p.z - was.z
		if dx * dx + dz * dz < 0.0004:      # сдвиг меньше 2 см — метка и так на месте
			continue
		_write(_slot[u], p)
		_last_pos[u] = p
	# Словарь правится ПОСЛЕ обхода: Dictionary в GDScript не допускает удаления
	# ключей во время итерации по себе
	for k in stale:
		_drop_slot(k)

## Красные кольца ездят за подсвеченным отрядом ровно так же, как жёлтые за
## своим: враг под курсором чаще всего именно идёт.
##
## Именно ЗДЕСЬ и падал отчётный стек (SelectionDecalRenderer.gd:280): наведение
## опрашивается по таймеру курсора, а подсвеченный вражеский отряд в это время
## режут — между двумя опросами половина набора успевает освободиться. Порядок
## «проверить, потом привести» — тот же, что и в update_all выше
func _update_hover_positions() -> void:
	if _hover_slot.is_empty():
		return
	var stale: Array = []
	for unit in _hover_slot:
		if not is_instance_valid(unit):
			stale.append(unit)
			continue
		# ЗДАНИЕ НЕ ХОДИТ И draw_position() У НЕГО НЕТ. Приводить к Unit
		# заранее нельзя (типизированное присваивание на постройке — ошибка),
		# поэтому тип разбирается здесь, один раз на подсвеченную цель
		var uu := unit as Unit
		if uu == null:
			continue
		var p: Vector3 = uu.draw_position()
		var was: Vector3 = _hover_last.get(uu, Vector3.INF)
		var dx: float = p.x - was.x
		var dz: float = p.z - was.z
		if dx * dx + dz * dz < 0.0004:
			continue
		_hover_write(_hover_slot[uu], p)
		_hover_last[uu] = p
	for k in stale:
		_hover_drop(k)

## ОТДАТЬ НАКОПЛЕННОЕ В РЕНДЕР — один set_buffer на слой за кадр.
## Зовётся из GameManager._process после всех юнитов (см. process_priority)
func flush() -> void:
	if _rings != null:
		_rings.flush()
	if _shadows != null:
		_shadows.flush()
	if _hover != null:
		_hover.flush()
	if _hover_b != null:
		_hover_b.flush()

## Полная очистка (смена сцены/сброс партии) — только бухгалтерия слотов
func clear_bookkeeping() -> void:
	_hover_slot.clear()
	_hover_in_b.clear()
	_hover_last.clear()
	if _hover != null:
		_hover.hide_all()
		_hover.flush()
	if _hover_b != null:
		_hover_b.hide_all()
		_hover_b.flush()
		_hover.free = range(_hover.capacity)
	for l in [_rings, _shadows]:
		if l == null:
			continue
		var lay: Layer = l
		lay.hide_all()
		lay.flush()
	if _rings != null:
		_rings.free = range(_rings.capacity)
	_slot.clear()
	_last_pos.clear()
