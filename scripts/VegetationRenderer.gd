extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ОБЩИЙ MultiMesh ДЛЯ РАСТИТЕЛЬНОСТИ (деревья и кусты)
## ═══════════════════════════════════════════════════════════════════════════
## ПОЧЕМУ. Каждое растение несло СВОЙ ShaderMaterial — иначе не раздать
## индивидуальную фазу и длительность колыхания (см. BillboardUtil.make_wind_material),
## а без разброса лес машет одним куском. Материал у каждого свой ⇒ батчинга нет
## ⇒ вызов отрисовки на каждое растение.
##
## ЗАМЕР, ради которого всё это (qa_veg, вся карта в кадре, АРМИИ НЕТ,
## RTX 4070): 1762 вызова отрисовки, 75 кадров в секунду. То есть декорация
## одна упирала игру в 75 к/с ещё до появления первого бойца — при цели в
## 100-120. В обычном приближённом кадре этого не видно (qa_march_perf даёт 131
## вызов на 810 бойцах), потому что лес туда просто не попадает; но армией в
## пятнадцать тысяч командуют именно с отдалённой камеры.
##
## КАК. Разброс переехал в instance-цвет (use_colors), как это уже сделано у
## бойцов в FarUnitRenderer, и весь лес одного сорта рисуется одним вызовом.
## Вид при этом не меняется ни на кадр: те же ленты, та же фаза, тот же цикл.
##
## УСТРОЙСТВО ТО ЖЕ, ЧТО У БОЙЦОВ, и по тем же причинам:
##   • бакет на ленту кадров, ключ — текстура + пропорции квада;
##   • теневой PackedFloat32Array, одна подача set_buffer на бакет за кадр;
##   • ВСЕ записи в буфер живут ВНУТРИ класса Bucket. Packed-массивы в GDScript
##     копируются при записи снаружи (см. FarUnitRenderer).
##
## ЧЕМ ОТЛИЧАЕТСЯ ОТ БОЙЦОВ. Растение не ходит: запись в буфер идёт ОДИН РАЗ
## при посадке и дальше не трогается вовсе. flush() поэтому зовётся не каждый
## кадр, а только когда что-то поменялось (посадка, рубка, пень) — за это и
## отвечает флаг dirty.
##
## РАЗМЕР — МАСШТАБОМ ЭКЗЕМПЛЯРА, А НЕ СВОИМ МЕШЕМ. У куста размер случайный,
## у дерева — свой на сорт; меш у бакета один, поэтому в бакете лежит квад
## ЕДИНИЧНОЙ ширины с пропорциями кадра, а настоящий размер задаётся
## равномерным масштабом в трансформе.

const _SHADER := preload("res://shaders/veg_multimesh.gdshader")
const _BB     := preload("res://scripts/BillboardUtil.gd")

const GROW_STEP := 256

class Bucket:
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
		buf.resize(new_cap * STRIDE)
		for i in range(capacity, new_cap):
			free.append(i)
		mm.instance_count = new_cap
		capacity = new_cap
		dirty = true

	## Полная запись: положение, равномерный масштаб, фаза и цикл колыхания.
	## Поворота нет вовсе — квад доворачивает к камере шейдер
	func write(idx: int, pos: Vector3, scale: float, phase01: float,
			cycle01: float) -> void:
		var o: int = idx * STRIDE
		buf[o]      = scale
		buf[o + 1]  = 0.0
		buf[o + 2]  = 0.0
		buf[o + 3]  = pos.x
		buf[o + 4]  = 0.0
		buf[o + 5]  = scale
		buf[o + 6]  = 0.0
		buf[o + 7]  = pos.y
		buf[o + 8]  = 0.0
		buf[o + 9]  = 0.0
		buf[o + 10] = scale
		buf[o + 11] = pos.z
		buf[o + 12] = phase01
		buf[o + 13] = cycle01
		buf[o + 14] = 0.0
		buf[o + 15] = 1.0
		dirty = true

	## Только положение: дрожание ствола при рубке. Масштаб и цвет на месте
	func write_pos(idx: int, pos: Vector3) -> void:
		var o: int = idx * STRIDE
		buf[o + 3]  = pos.x
		buf[o + 7]  = pos.y
		buf[o + 11] = pos.z
		dirty = true

	## Спрятать экземпляр: нулевая матрица — вырожденный треугольник, который
	## растеризатор отбрасывает сразу (скрыть экземпляр MultiMesh нельзя)
	func hide_slot(idx: int) -> void:
		var o: int = idx * STRIDE
		for i in range(STRIDE):
			buf[o + i] = 0.0
		dirty = true

	func flush() -> void:
		if not dirty:
			return
		dirty = false
		if capacity > 0:
			mm.set_buffer(buf)

## Место одного растения в общей отрисовке. Класс, а не словарь: ResourceNode
## держит прямую ссылку и двигает себя сам
class Slot:
	var bucket: Bucket
	var index: int
	var scale: float = 1.0
	var phase01: float = 0.0
	var cycle01: float = 0.0
	var pos: Vector3 = Vector3.ZERO

	## Порог «сдвинулось» — АБСОЛЮТНЫЙ квадрат расстояния (0.01 мм), а не
	## Vector3.is_equal_approx. У того допуск растёт вместе с величиной
	## координаты: на дереве в ста метрах от центра карты он достигает
	## миллиметра, и затухающее дрожание рубки не доводило ствол до исходной
	## точки — он замирал сдвинутым (стенд qa_veg D2 поймал 0.0008 м). Ровно
	## тот же приём и то же обоснование, что у бойцов в FarUnitRenderer.Slot
	const MOVE_EPS_SQ := 1e-10

	func move_to(p: Vector3) -> void:
		var dx: float = p.x - pos.x
		var dy: float = p.y - pos.y
		var dz: float = p.z - pos.z
		# Неподвижное растение не переписываем: стоящий лес не помечает бакет
		# грязным вовсе, и flush() для него не делает ничего
		if dx * dx + dy * dy + dz * dz < MOVE_EPS_SQ:
			return
		pos = p
		bucket.write_pos(index, p)

var _buckets: Dictionary = {}     # ключ -> Bucket
var _dirty_any: bool = false

## Ключ бакета: лента плюс пропорции квада. Размер в ключ НЕ входит — он живёт
## в масштабе экземпляра, иначе каждый куст со своим случайным размером
## заводил бы отдельный бакет и смысл затеи пропал бы
static func _key(tex: Texture2D, frames: int, aspect: float) -> String:
	return "%d|%d|%.4f" % [tex.get_rid().get_id(), frames, aspect]

func _get_or_make(tex: Texture2D, frames: int, aspect: float,
		world_root: Node3D) -> Bucket:
	var k := _key(tex, frames, aspect)
	if _buckets.has(k):
		return _buckets[k]
	var b := Bucket.new()

	var quad := QuadMesh.new()
	# Квад ЕДИНИЧНОЙ ВЫСОТЫ: настоящий размер приходит масштабом экземпляра
	quad.size = Vector2(aspect, 1.0)

	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("modulate", Color.WHITE)
	mat.set_shader_parameter("alpha_scissor", 0.5)
	mat.set_shader_parameter("frame_count", float(maxi(frames, 1)))
	mat.set_shader_parameter("cycle_min", _BB.WIND_CYCLE_MIN)
	mat.set_shader_parameter("cycle_max", _BB.WIND_CYCLE_MAX)
	mat.set_shader_parameter("v_stretch", _BB.V_STRETCH)
	# Тот же приоритет, что у прежних материалов растительности: боец рисуется
	# приоритетом 1 и не должен казаться утопленным в куст (см. BillboardUtil)
	mat.render_priority = 0
	quad.material = mat

	b.mm = MultiMesh.new()
	b.mm.transform_format = MultiMesh.TRANSFORM_3D
	b.mm.use_colors = true
	b.mm.mesh = quad
	b.mm.instance_count = 0

	b.mmi = MultiMeshInstance3D.new()
	b.mmi.name = "Veg_%d" % _buckets.size()
	b.mmi.multimesh = b.mm
	# Пирамиду видимости считает один узел на весь бакет, а растения разбросаны
	# по всей карте: без запаса бакет пропадал бы целиком (см. FarUnitRenderer)
	b.mmi.extra_cull_margin = 16384.0
	world_root.add_child(b.mmi)

	_buckets[k] = b
	return b

## ПОСАДИТЬ РАСТЕНИЕ. `base` — точка на грунте, `height` — высота квада в метрах.
## Квад центрируется на половине высоты сам. Возвращает слот (или null, если
## рисовать нечего)
func plant(tex: Texture2D, base: Vector3, height: float, world_root: Node3D,
		phase01: float = -1.0, cycle01: float = -1.0) -> Slot:
	if tex == null or world_root == null or height <= 0.0:
		return null
	var frames: int = _BB.frame_count(tex)
	var aspect: float = _BB.frame_aspect(tex)
	if aspect <= 0.0:
		aspect = 1.0
	var b := _get_or_make(tex, frames, aspect, world_root)
	if b.free.is_empty():
		b.grow(GROW_STEP)
	var s := Slot.new()
	s.bucket = b
	s.index  = b.free.pop_back()
	s.scale  = height
	# Разброс тот же, что раздавал make_wind_material каждому своему материалу
	s.phase01 = randf() if phase01 < 0.0 else phase01
	s.cycle01 = randf() if cycle01 < 0.0 else cycle01
	s.pos = Vector3(base.x, base.y + height * 0.5, base.z)
	b.write(s.index, s.pos, s.scale, s.phase01, s.cycle01)
	_dirty_any = true
	return s

## Убрать растение (срублено, снесено вместе с картой)
func remove(s: Slot) -> void:
	if s == null or s.bucket == null:
		return
	s.bucket.hide_slot(s.index)
	s.bucket.free.append(s.index)
	s.bucket = null
	_dirty_any = true

## Сдвинуть растение (дрожание ствола при рубке)
func move(s: Slot, base: Vector3) -> void:
	if s == null or s.bucket == null:
		return
	s.move_to(Vector3(base.x, base.y + s.scale * 0.5, base.z))
	_dirty_any = true

## Отдать накопленное в RenderingServer. В отличие от бойцов зовётся не каждый
## кадр, а только когда что-то изменилось: растение не ходит
func flush() -> void:
	if not _dirty_any:
		return
	_dirty_any = false
	for k in _buckets:
		(_buckets[k] as Bucket).flush()

## Сколько узлов MultiMeshInstance3D заведено (столько же вызовов отрисовки)
func bucket_count() -> int:
	return _buckets.size()

## Сколько мест занято (стенды)
func planted_count() -> int:
	var n := 0
	for k in _buckets:
		var b: Bucket = _buckets[k]
		n += b.capacity - b.free.size()
	return n

## Новая карта: узлы прошлой сцены уже освобождены вместе с миром
func clear_bookkeeping() -> void:
	_buckets.clear()
	_dirty_any = false
