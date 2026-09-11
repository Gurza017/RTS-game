extends Building

## ═══════════════════════════════════════════════════════════════════════════
## ЗАГОН ДЛЯ ОВЕЦ (заказ владельца, спринт 13)
## ═══════════════════════════════════════════════════════════════════════════
## Постройка рабочего, которая ДЕРЖИТ СТАДО. Смысл её в двух числах: она
## поднимает потолок выпаса (у замка их всего CASTLE_GRAZE_LIMIT) и вдвое
## ускоряет размножение (SHEEP_BREED_PEN_SEC против SHEEP_BREED_CASTLE_SEC).
##
## ── КАРТИНКА ЛЕЖИТ ПЛАШМЯ, А НЕ СТОИТ БИЛБОРДОМ ───────────────────────────
## Арт `Wooden Fence_64x64 tile.png` — это ГОТОВАЯ ОГРАДА СВЕРХУ: замкнутый
## прямоугольник 256×192 с проёмом снизу и уже впечатанной тенью. Поставь его
## вертикальным квадом (общий путь Building._maybe_load_building_sprite) — и
## на экране будет стена с нарисованным полом, сквозь которую видно небо.
## Поэтому здесь СВОЙ `_build_visual`, а общий загрузчик спрайта отключён.
##
## ── МЕШ СЛЕДУЕТ РЕЛЬЕФУ, А НЕ ПОДНЯТ НАД НИМ ──────────────────────────────
## Плоский квад в десять метров на волнистой земле (гармоники дают до ±0.85 м)
## наполовину уходит в грунт, а поднятый над ней висит в воздухе. Та же
## задача, что у травы: сетка MESH_CELLS_X × MESH_CELLS_Z, высота каждой
## вершины берётся у `GameManager.get_terrain_height`, сверху крохотный
## подъём MESH_LIFT против z-fighting с землёй.
##
## ── ОВЦЫ ПРИВЯЗАНЫ К ЗАГОНУ, А НЕ ЗАПЕРТЫ В НЁМ ───────────────────────────
## `accept_sheep` ставит овце `pen = self` (Sheep.bind_to), и дальше она
## пасётся сама в радиусе `graze_radius()` — то есть ЗАХОДИТ И ВЫХОДИТ, как
## и просили. Ограда — не коллизия: физтел в проекте нет вовсе.
##
## Файл без class_name: подключается через preload (как Tower/Archery).

const _UCfgP := preload("res://scripts/unit_stats_config.gd")

## Сетка меша ограды: 4 × 3 при пропорции картинки 256×192 — по одной ячейке
## на «тайл» рисунка, этого хватает, чтобы лечь на любой здешний склон
const MESH_CELLS_X := 6
const MESH_CELLS_Z := 5
## Подъём над грунтом: меньше — мерцание с землёй, больше — ограда парит
const MESH_LIFT := 0.05

const FENCE_TEX := "res://assets/environment/resources/Wooden/Wooden Fence_64x64 tile.png"

## Насколько овцам разрешено выходить за ограду (доля полуширины загона).
## Единица означала бы «строго внутри», а овца обязана заходить и выходить
const ROAM_FACTOR := 1.35

func _ready() -> void:
	# ПОЛЯ СТАВЯТСЯ ДО super._ready(): базовый _ready сразу строит картинку и
	# форму попадания по build_size (тот же порядок, что у Archery и Tower)
	building_id  = "sheep_pen"
	sprite_path  = FENCE_TEX
	max_health   = _UCfgP.building_stat("sheep_pen", "max_hp", 400.0)
	build_size   = _UCfgP.building_size("sheep_pen", Vector3(10.0, 1.4, 7.5))
	display_name = String(_UCfgP.building_cfg("sheep_pen").get("name", "Загон для овец"))
	super._ready()
	add_to_group("sheep_pens")

func _exit_tree() -> void:
	# ОВЦЫ ПЕРЕЖИВАЮТ ЗАГОН: снесённая ограда не убивает стадо, но привязка
	# гаснет — иначе овцы вечно паслись бы вокруг несуществующего узла и не
	# размножались бы вовсе (потолок спрашивается у привязки)
	for s in get_tree().get_nodes_in_group("sheep"):
		if s != null and is_instance_valid(s) and s.get("pen") == self:
			s.set("pen", null)
	super._exit_tree()

# ─────────────────────────────────────────────────────────────────────────────
# КАРТИНКА
# ─────────────────────────────────────────────────────────────────────────────

## Общий загрузчик спрайта здания отключён намеренно: он ставит ВЕРТИКАЛЬНЫЙ
## квад, а ограда нарисована сверху (см. шапку файла)
func _maybe_load_building_sprite() -> void:
	pass

var _fence_mi: MeshInstance3D = null

func _build_visual() -> void:
	_add_pick_shape()
	_build_fence_mesh()
	selection_ring = make_selection_marker()
	add_child(selection_ring)
	# ── ВЫСОТЫ ПЕРЕСЧИТЫВАЮТСЯ ОТЛОЖЕННО ───────────────────────────────────
	# В _ready точка узла ещё НУЛЕВАЯ: и стройплощадка, и загрузка партии
	# ставят global_position уже ПОСЛЕ add_child (та же грабля, что у ворот
	# замка и у ствола дерева). Собранный здесь меш лёг бы по рельефу в
	# начале координат карты
	call_deferred("_reshape_fence")

func _build_fence_mesh() -> void:
	if not ResourceLoader.exists(FENCE_TEX):
		push_warning("SheepPen: нет картинки ограды %s" % FENCE_TEX)
		return
	var tex := load(FENCE_TEX) as Texture2D
	if tex == null:
		return
	var hx: float = build_size.x * 0.5
	var hz: float = build_size.z * 0.5
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var org: Vector3 = global_position
	for iz in range(MESH_CELLS_Z + 1):
		for ix in range(MESH_CELLS_X + 1):
			var u: float = float(ix) / float(MESH_CELLS_X)
			var v: float = float(iz) / float(MESH_CELLS_Z)
			var lx: float = -hx + u * build_size.x
			var lz: float = -hz + v * build_size.z
			var h: float = GameManager.get_terrain_height(org.x + lx, org.z + lz) - org.y
			verts.append(Vector3(lx, h + MESH_LIFT, lz))
			uvs.append(Vector2(u, v))
	for iz2 in range(MESH_CELLS_Z):
		for ix2 in range(MESH_CELLS_X):
			var a: int = iz2 * (MESH_CELLS_X + 1) + ix2
			var b: int = a + 1
			var c: int = a + MESH_CELLS_X + 1
			var d: int = c + 1
			idx.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "PenFence"
	mi.mesh = mesh
	add_child(mi)
	_fence_mi = mi

## Пересобрать ограду по рельефу в её НАСТОЯЩЕЙ точке (см. _build_visual)
func _reshape_fence() -> void:
	if _fence_mi == null or not is_instance_valid(_fence_mi):
		return
	var old: ArrayMesh = _fence_mi.mesh as ArrayMesh
	var mat: Material = null
	if old != null and old.get_surface_count() > 0:
		mat = old.surface_get_material(0)
	# ПРАВИЛО 6: remove_child ПЕРЕД queue_free. Освобождение отложено, и
	# старый узел до конца кадра остаётся ребёнком — вместе со своим ИМЕНЕМ.
	# Новый «PenFence» получал бы от движка суффикс, и всякий, кто ищет
	# ограду по имени, находил бы старую (уже приговорённую) или ничего
	remove_child(_fence_mi)
	_fence_mi.queue_free()
	_fence_mi = null
	_build_fence_mesh()
	if _fence_mi != null and mat != null:
		var m: ArrayMesh = _fence_mi.mesh as ArrayMesh
		if m != null and m.get_surface_count() > 0:
			m.surface_set_material(0, mat)

# ─────────────────────────────────────────────────────────────────────────────
# СТАДО
# ─────────────────────────────────────────────────────────────────────────────

## Потолок загона (unit_stats_config — правит владелец)
func capacity() -> int:
	return _UCfgP.SHEEP_PEN_CAPACITY

## Где пасутся привязанные и как далеко разрешено отходить
func graze_center() -> Vector3:
	return global_position

func graze_radius() -> float:
	return maxf(build_size.x, build_size.z) * 0.5 * ROAM_FACTOR

## Сколько овец уже привязано к ЭТОМУ загону
func sheep_count() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s):
			continue
		if s.get("pen") == self and not bool(s.get("eaten")):
			n += 1
	return n

func has_room() -> bool:
	return sheep_count() < capacity()

## Принять принесённую овцу. Утиный контракт: Worker._sheep_dest ищет по
## группе `sheep_pens` любой узел с этим методом
func accept_sheep(s: Node3D) -> bool:
	if s == null or not is_instance_valid(s) or not s.has_method("bind_to_pen"):
		return false
	if not has_room():
		return false
	s.call("bind_to_pen", self, faction)
	return true

## Подпись для панели интерфейса (заказ: «Вместимость: X / 20 овец»)
func capacity_text() -> String:
	return "Вместимость: %d / %d овец" % [sheep_count(), capacity()]
