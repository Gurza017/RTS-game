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
	_write(idx, unit.global_position)
	_last_pos[unit] = unit.global_position

## Убрать метки. Идемпотентно
func unregister(unit: Unit) -> void:
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

## Подтянуть метки за сдвинувшимися бойцами. Зовётся раз в кадр из GameManager;
## неподвижных пропускаем — выделенный строй чаще стоит, чем идёт
func update_all() -> void:
	if _slot.is_empty():
		return
	for unit in _slot:
		var u: Unit = unit
		if not is_instance_valid(u):
			continue
		var p: Vector3 = u.global_position
		var was: Vector3 = _last_pos.get(u, Vector3.INF)
		var dx: float = p.x - was.x
		var dz: float = p.z - was.z
		if dx * dx + dz * dz < 0.0004:      # сдвиг меньше 2 см — метка и так на месте
			continue
		_write(_slot[u], p)
		_last_pos[u] = p

## ОТДАТЬ НАКОПЛЕННОЕ В РЕНДЕР — один set_buffer на слой за кадр.
## Зовётся из GameManager._process после всех юнитов (см. process_priority)
func flush() -> void:
	if _rings != null:
		_rings.flush()
	if _shadows != null:
		_shadows.flush()

## Полная очистка (смена сцены/сброс партии) — только бухгалтерия слотов
func clear_bookkeeping() -> void:
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
