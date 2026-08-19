extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ПОЛОСКИ ЗДОРОВЬЯ: ОДИН MultiMesh НА ВСЮ АРМИЮ
## ═══════════════════════════════════════════════════════════════════════════
## Было: Unit._build_hp_bar() вешал на бойца ДВА узла (корень + заливка) со
## СВОИМ QuadMesh, у которого при каждом уроне переписывались size и
## center_offset. Замер (qa_hotspot, 600 бойцов, тумблер Alt поднят):
## **+2.8 мс кадра и +720 вызовов отрисовки** — самая дорогая мелочь в
## интерфейсе, и включается она одной клавишей посреди боя.
##
## Стало: один MultiMeshInstance3D на всю партию. Устройство и все оговорки —
## те же, что у SelectionDecalRenderer и FarUnitRenderer:
##   • теневой PackedFloat32Array, одна подача set_buffer за кадр;
##   • ВСЕ записи в буфер живут внутри класса-владельца (Packed-массивы
##     копируются при записи через чужую ссылку);
##   • extra_cull_margin, иначе слой пропадает целиком, когда его условный
##     центр уходит за край кадра.
##
## ОТЛИЧИЕ ОТ КОЛЕЦ ВЫДЕЛЕНИЯ: у полоски есть переменная величина — доля
## здоровья. Масштабом экземпляра её не передать (билборд теряет масштаб, см.
## шапку mm_hp_bar.gdshader), поэтому слой включает use_colors и доля едет в
## канале r, а обрезку делает шейдер. Отсюда STRIDE = 16, а не 12.

const _SHADER := preload("res://shaders/mm_hp_bar.gdshader")

const GROW_STEP := 256

class Layer:
	## 12 float трансформа + 4 float цвета (TRANSFORM_3D + use_colors)
	const STRIDE := 16

	var mmi: MultiMeshInstance3D
	var mm: MultiMesh
	var free: Array = []
	var capacity: int = 0
	var buf: PackedFloat32Array = PackedFloat32Array()
	var dirty: bool = false

	func grow(step: int) -> void:
		var new_cap: int = capacity + step
		buf.resize(new_cap * STRIDE)      # нули = спрятанный слот
		for i in range(capacity, new_cap):
			free.append(i)
		mm.instance_count = new_cap
		capacity = new_cap
		dirty = true

	## Полоска не поворачивается: базис единичный, разворот к камере делает
	## шейдер. Пишем положение и долю жизни
	func write(idx: int, pos: Vector3, w: float, h: float, frac: float) -> void:
		var o: int = idx * STRIDE
		buf[o]      = w
		buf[o + 1]  = 0.0
		buf[o + 2]  = 0.0
		buf[o + 3]  = pos.x
		buf[o + 4]  = 0.0
		buf[o + 5]  = h
		buf[o + 6]  = 0.0
		buf[o + 7]  = pos.y
		buf[o + 8]  = 0.0
		buf[o + 9]  = 0.0
		buf[o + 10] = 1.0
		buf[o + 11] = pos.z
		buf[o + 12] = frac
		buf[o + 13] = 0.0
		buf[o + 14] = 0.0
		buf[o + 15] = 1.0
		dirty = true

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

var _layer: Layer = null
var _slot: Dictionary = {}       # Unit -> индекс слота
## Что уже лежит в буфере: повторную такую же запись делать незачем
var _last: Dictionary = {}       # Unit -> Vector3(x, z, frac)

func _ensure(world_root: Node3D) -> void:
	if _layer != null:
		return
	var l := Layer.new()
	# Квад ЕДИНИЧНЫЙ: настоящие ширина и толщина приходят масштабом экземпляра,
	# а UV.x от 0 до 1 нужен шейдеру для отсечки по доле жизни
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("bar_color", Color(0.86, 0.12, 0.12))
	# Тот же приоритет, что был у одиночной полоски (UnitVisuals.hp_bar_material):
	# она не должна тонуть в спрайте бойца
	mat.render_priority = 4
	quad.material = mat
	l.mm = MultiMesh.new()
	l.mm.transform_format = MultiMesh.TRANSFORM_3D
	l.mm.use_colors = true
	l.mm.mesh = quad
	l.mm.instance_count = 0
	l.mmi = MultiMeshInstance3D.new()
	l.mmi.name = "HpBars"
	l.mmi.multimesh = l.mm
	l.mmi.extra_cull_margin = 16384.0
	world_root.add_child(l.mmi)
	_layer = l

## Показать полоску над бойцом. Идемпотентно
func register(unit: Unit, world_root: Node3D) -> void:
	if _slot.has(unit):
		return
	_ensure(world_root)
	if _layer.free.is_empty():
		_layer.grow(GROW_STEP)
	_slot[unit] = _layer.free.pop_back()
	_write(unit)

## Убрать полоску. Идемпотентно
func unregister(unit: Unit) -> void:
	_drop_slot(unit)

## Variant, а не Unit, по той же причине, что и в SelectionDecalRenderer:
## ключом может оказаться уже освобождённый объект, и typed-параметр бросил бы
## «Trying to assign invalid previously freed instance» прямо на вызове
func _drop_slot(unit) -> void:
	if not _slot.has(unit) or _layer == null:
		return
	var idx: int = _slot[unit]
	_layer.hide_slot(idx)
	_layer.free.append(idx)
	_slot.erase(unit)
	_last.erase(unit)

func is_registered(unit: Unit) -> bool:
	return _slot.has(unit)

func registered_count() -> int:
	return _slot.size()

func _write(unit: Unit) -> void:
	var idx: int = _slot[unit]
	# Та же оговорка, что у колец выделения: полоска висит над НАРИСОВАННЫМ
	# бойцом, а картинка сглаживается между физическими шагами
	var p: Vector3 = unit.draw_position()
	var frac: float = 0.0
	if unit.max_health > 0.0:
		frac = clampf(unit.current_health / unit.max_health, 0.0, 1.0)
	_layer.write(idx,
		Vector3(p.x, p.y + Unit.HP_BAR_HEIGHT, p.z),
		Unit.HP_BAR_WIDTH, Unit.HP_BAR_THICKNESS, frac)
	_last[unit] = Vector3(p.x, p.z, frac)

## Подтянуть полоски за бойцами и за их здоровьем. Зовётся раз в кадр из
## GameManager рядом с метками выделения; неподвижных и нераненых пропускаем
## ПРОВЕРКА ЖИВОСТИ — ДО ПРИВЕДЕНИЯ К ТИПУ. Разбор см. в
## SelectionDecalRenderer.update_all: `var u: Unit = <освобождённый>` падает сам,
## не дав is_instance_valid ни одного шанса сработать
func update_all() -> void:
	if _slot.is_empty():
		return
	var stale: Array = []
	for unit in _slot:
		if not is_instance_valid(unit):
			stale.append(unit)
			continue
		var u: Unit = unit
		var p: Vector3 = u.draw_position()
		var frac: float = 0.0
		if u.max_health > 0.0:
			frac = clampf(u.current_health / u.max_health, 0.0, 1.0)
		var was: Vector3 = _last.get(u, Vector3.INF)
		var dx: float = p.x - was.x
		var dz: float = p.z - was.y
		# Порог тот же по смыслу, что у меток выделения: 2 см по земле или
		# заметное изменение доли жизни
		if dx * dx + dz * dz < 0.0004 and absf(frac - was.z) < 0.002:
			continue
		_write(u)
	for k in stale:
		_drop_slot(k)

func flush() -> void:
	if _layer != null:
		_layer.flush()

## Полная очистка (смена сцены/сброс партии)
func clear_bookkeeping() -> void:
	if _layer != null:
		_layer.hide_all()
		_layer.flush()
		_layer.free = range(_layer.capacity)
	_slot.clear()
	_last.clear()
