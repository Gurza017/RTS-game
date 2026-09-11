extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ВСЕ СТРЕЛЫ — ОДНИМ MultiMesh (этап D3)
## ═══════════════════════════════════════════════════════════════════════════
## Раньше каждая стрела была узлом со СВОИМ мешем и материалом — то есть своим
## вызовом отрисовки (замер qa_shotcorpse: 36 торчащих = +36 вызовов, в свалке
## с лучниками их 100-150). Логика стрелы (полёт, попадание, сроки, пул)
## остаётся в узле Arrow как была; сюда переехала только КАРТИНКА: один
## MultiMeshInstance3D, буфер — в ядре (ArmyCore.Rb, та же инфраструктура, что
## у армии), подача — общим RbFlush раз в кадр.
##
## Ось и растворение едут в instance-цвете (см. mm_arrow.gdshader): у стрел
## каналы урона свободны, и COLOR ровно вмещает ax.xyz + fade.
##
## Владелец — GameManager (авто-загрузка живёт дольше сцены, поэтому ensure()
## проверяет, что узел ещё в ДЕРЕВЕ ЭТОЙ сцены, и при смене сцены строит слой
## заново; прежняя запись в списке бакетов ядра при этом просто пустеет — Rb
## на смену сцены не пересоздаётся, и это осознанная мелкая утечка записи).

const _SHADER := preload("res://shaders/mm_arrow.gdshader")
const GROW := 64

var mmi: MultiMeshInstance3D = null
var mm: MultiMesh = null
var mat: ShaderMaterial = null
var core_id: int = -1
var capacity: int = 0
var free: Array = []
## Поколение слоя. Растёт на каждой пересборке (смена сцены): слот, взятый у
## прошлого поколения, возвращать в список свободных нельзя — его номер может
## оказаться за ёмкостью нового буфера, и первый же acquire отдал бы номер, по
## которому ядро пишет за край массива
var gen: int = 0

func ensure(world: Node3D, tex: Texture2D, length: float, aspect: float) -> bool:
	if mmi != null and is_instance_valid(mmi) and mmi.is_inside_tree():
		return true
	gen += 1
	if world == null:
		return false
	var quad := QuadMesh.new()
	quad.size = Vector2(length, length / maxf(aspect, 0.01))
	mat = ShaderMaterial.new()
	mat.shader = _SHADER
	if tex != null:
		mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("modulate", Color.WHITE)
	else:
		mat.set_shader_parameter("modulate", Color(0.85, 0.70, 0.20))
	mat.set_shader_parameter("alpha_scissor", 0.2)
	# Поверх наземной декорации — как у спрайтов армии (см. FarUnitRenderer)
	mat.render_priority = 1
	quad.material = mat
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 0
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Стрелы разбросаны по всей карте, а пирамиду видимости считает один узел
	mmi.extra_cull_margin = 16384.0
	world.add_child(mmi)
	core_id = GameManager.army.rb_create(mm.get_rid())
	capacity = 0
	free = []
	return true

func acquire() -> int:
	if core_id < 0:
		return -1
	if free.is_empty():
		var new_cap: int = capacity + GROW
		GameManager.army.rb_ensure(core_id, new_cap)
		for i in range(capacity, new_cap):
			free.append(i)
		mm.instance_count = new_cap
		capacity = new_cap
	return free.pop_back()

## Вернуть слот. Зовёт Arrow при освобождении УЗЛА (не при уходе в пул: там
## слот остаётся за узлом и переписывается следующим выстрелом)
func release(idx: int, slot_gen: int = -1) -> void:
	if idx < 0 or core_id < 0 or idx >= capacity:
		return
	if slot_gen >= 0 and slot_gen != gen:
		return
	GameManager.army.rb_hide_slot(core_id, idx)
	free.append(idx)

## Полная запись слота: позиция + ось + доля покрытия. Базис пишется единичным
## (ориентацию целиком строит шейдер из оси в цвете)
func write(idx: int, pos: Vector3, axis: Vector3, fade: float) -> void:
	if idx < 0 or core_id < 0:
		return
	GameManager.army.rb_write_full(core_id, idx, pos, 0, false, 0.0, 1.0)
	GameManager.army.rb_write_color(core_id, idx,
		axis.x * 0.5 + 0.5, axis.y * 0.5 + 0.5, axis.z * 0.5 + 0.5, fade)

## Быстрый путь полёта: только позиция и ось (гашение в полёте не меняется)
func write_flight(idx: int, pos: Vector3, axis: Vector3, fade: float) -> void:
	if idx < 0 or core_id < 0:
		return
	GameManager.army.rb_write_pos(core_id, idx, pos)
	GameManager.army.rb_write_color(core_id, idx,
		axis.x * 0.5 + 0.5, axis.y * 0.5 + 0.5, axis.z * 0.5 + 0.5, fade)

func hide(idx: int) -> void:
	if idx >= 0 and core_id >= 0:
		GameManager.army.rb_hide_slot(core_id, idx)

## ── РЕЕСТР ПОЛЁТОВ, КОТОРЫЕ ВЕДЁТ ЯДРО (perf_config.arrow_core) ───────────
## id полёта → узел стрелы: события от BatchArrows приходят по id
var _flights: Dictionary = {}

func register_flight(id: int, arrow: Node3D) -> void:
	_flights[id] = arrow

func unregister_flight(id: int) -> void:
	_flights.erase(id)

func flight_count() -> int:
	return _flights.size()

## Разобрать события ядра за кадр: касание чужого или приземление
func drain_events() -> void:
	if _flights.is_empty():
		return
	var ev: Array = GameManager.army.take_arrow_events()
	var n: int = ev.size()
	var k := 0
	while k + 3 < n:
		var id: int = int(ev[k])
		var a = _flights.get(id)
		_flights.erase(id)
		if a != null and is_instance_valid(a):
			a.core_event(ev[k + 1], ev[k + 2], ev[k + 3])
		k += 4

func set_layer_visible(v: bool) -> void:
	if mmi != null and is_instance_valid(mmi):
		mmi.visible = v
