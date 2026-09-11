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
const _Opt := preload("res://scripts/perf_config.gd")

const GROW_STEP := 256

## ── БУФЕР ПОЛОСОК ЖИВЁТ В ЯДРЕ (этап E2, 09.09.2026) ──────────────────────
## Тот же Rb, что у бакетов бойцов и колец: запись по событию отсюда, позиция
## и доля жизни — BatchVisual из строки, подача — RbFlush
class Layer:
	const STRIDE := 16
	var mmi: MultiMeshInstance3D
	var mm: MultiMesh
	var free: Array = []
	var capacity: int = 0
	var core_id: int = -1
	func grow(step: int) -> void:
		var new_cap: int = capacity + step
		GameManager.army.rb_ensure(core_id, new_cap)
		for i in range(capacity, new_cap):
			free.append(i)
		mm.instance_count = new_cap
		capacity = new_cap
	func write(idx: int, pos: Vector3, w: float, h: float, frac: float) -> void:
		GameManager.army.rb_write_xform(core_id, idx, Vector3(w, 0.0, 0.0),
			Vector3(0.0, h, 0.0), Vector3(0.0, 0.0, 1.0), pos)
		GameManager.army.rb_write_color(core_id, idx, frac, 0.0, 0.0, 1.0)
	func hide_slot(idx: int) -> void:
		GameManager.army.rb_hide_slot(core_id, idx)
	func hide_all() -> void:
		GameManager.army.rb_hide_all(core_id)
	## Подаёт ядро (RbFlush)
	func flush() -> void:
		pass

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
	l.core_id = GameManager.army.rb_create(l.mm.get_rid())
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
	# Строка ведёт полоску сама (этап E2); без строки — GDScript-обход
	if unit._soa >= 0:
		GameManager.army.hp_bind(unit._soa, _layer.core_id, _slot[unit])

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
	if is_instance_valid(unit) and unit._soa >= 0:
		GameManager.army.hp_unbind(unit._soa)
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
	var core: bool = _Opt.decal_core
	for unit in _slot:
		if not is_instance_valid(unit):
			stale.append(unit)
			continue
		var u: Unit = unit
		if core and u._rb_bound:
			continue
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
