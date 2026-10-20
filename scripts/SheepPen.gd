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
## ── ЗАГОН — «КОЛОДЕЦ РЕСУРСОВ» (ТЗ 23.09.2026, третье письмо) ────────────
## ТРЕБОВАНИЕ РАЗВЁРНУТО. Прежде здесь было записано: «овцы привязаны к
## загону, а не заперты в нём — заходят и выходят, как и просили». Новый
## заказ просит обратного и по пунктам:
##   • ровно SHEEP_PEN_CAPACITY (10, ТЗ 12.10.2026) мест;
##   • на одну овцу один рабочий, то есть не больше пяти на загон;
##   • овцы НЕ выходят за ограду;
##   • забитую заменяет новая через SHEEP_PEN_RESPAWN_SEC — и только пока
##     мест меньше пяти.
## Ограда по-прежнему не коллизия (физтел в проекте нет): «не выходят»
## делается радиусом выпаса, а не стеной.
##
## РЕГЕНЕРАЦИЯ СЧИТАЕТСЯ ОТ ЧИСЛА ЖИВЫХ, А НЕ ПО СОБЫТИЮ «ОВЦА УМЕРЛА».
## Событие пришлось бы ловить на всех путях гибели (разделка, тролль, снос
## загона, загрузка партии), и любой забытый оставил бы загон навсегда
## пустым. Проверка состояния раз в такт не может забыть ничего.
##
## Файл без class_name: подключается через preload (как Tower/Archery).

const _UCfgP := preload("res://scripts/unit_stats_config.gd")
const _SheepP := preload("res://scripts/goblin/Sheep.gd")

## Сетка меша ограды: 4 × 3 при пропорции картинки 256×192 — по одной ячейке
## на «тайл» рисунка, этого хватает, чтобы лечь на любой здешний склон
const MESH_CELLS_X := 6
const MESH_CELLS_Z := 5
## Подъём над грунтом: меньше — мерцание с землёй, больше — ограда парит
const MESH_LIFT := 0.05

const FENCE_TEX := "res://assets/environment/resources/Wooden/Wooden Fence_64x64 tile.png"

## Насколько овцам разрешено отходить от центра (доля полуширины загона).
## ── БЫЛО 1.35 «ОВЦА ОБЯЗАНА ЗАХОДИТЬ И ВЫХОДИТЬ», СТАЛО 0.72 ────────────
## Заказ 23.09.2026: «овцы не убегают и находятся только внутри загона».
## Не единица, а чуть меньше: ровно по кромке овца вставала бы НА ограду, и
## половина спрайта оказывалась бы снаружи рисунка
const ROAM_FACTOR := 0.72

## Ограда без стен: овцы пасутся внутри, рабочий заносит овцу в загон
func blocks_movement() -> bool:
	return false

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
	# ── ЗАГОН СРАЗУ С ПЯТЬЮ ОВЦАМИ (ТЗ 24.09.2026, п. 1) ─────────────────
	# Флаг ставит ТОЛЬКО стройка (ConstructionSite._complete и мгновенная
	# постройка в GameManager): стенды, заводящие загон через .new(), ставят
	# СВОИХ овец и шестой-седьмой лишней получить не должны. Отложенно — в
	# _ready точка узла ещё нулевая (см. _build_visual)
	if stock_on_ready:
		call_deferred("_stock_initial")

## Заполнить загон до вместимости сразу (новая постройка)
var stock_on_ready: bool = false

func _stock_initial() -> void:
	if not is_inside_tree() or _dead:
		return
	var guard: int = capacity()
	while live_count() < capacity() and guard > 0:
		guard -= 1
		var before: int = live_count()
		_spawn_one_sheep()
		if live_count() <= before:
			break    # потолок стада игрока — дальше не посадить
	_respawn_t = _roll_respawn()

## ── СНОС ЗАГОНА УБИВАЕТ СТАДО (ТЗ 24.09.2026, п. 3) ──────────────────────
## Было «овцы снесённого загона разбегаются» (ТЗ 19.09.2026, блок 3).
## ТРЕБОВАНИЕ РАЗВЁРНУТО: живые овцы гибнут на месте и ложатся красными
## тушами — мясо с них по-прежнему можно вынести (туша хозяйская,
## Worker._next_owned_sheep берёт мёртвых по owner_faction). Делается в _die,
## а не в _exit_tree: из дерева загон уходит и при смене сцены, и в стендах —
## там убивать стадо незачем
func _die() -> void:
	if not _dead:
		for s in get_tree().get_nodes_in_group("sheep"):
			if s == null or not is_instance_valid(s) or s.get("pen") != self:
				continue
			if bool(s.get("dead")) or bool(s.get("eaten")):
				continue
			if s.has_method("release_from") and s.get("captor") != null:
				s.call("release_from", s.get("captor"))
			if s.has_method("kill_by"):
				s.call("kill_by", null)
	super._die()

## ── ПЕПЕЛИЩЕ ЗАГОНА ЛЕЖИТ ПЛАШМЯ И РОВНО ПО ЦЕНТРУ (ТЗ 24.09.2026, п. 3) ──
## Общая руина — ВЕРТИКАЛЬНЫЙ квад, поднятый на половину высоты: на экране
## он уезжает вверх от центра ограды, а его глубина берётся у точки на земле
## под ним — туши, лежащие в загоне ЗА этой точкой, уходили под картинку.
## Ограда нарисована сверху, и пепелище ложится так же — сеткой по рельефу
## (тот же приём, что у самой ограды). Тогда центр рисунка стоит в центре
## загона, а любой спрайт, стоящий на нём, рисуется поверх по глубине сам:
## его точка на земле ближе к камере, чем пол под его верхней частью.
## Высота плоскости выводится из пропорции картинки с поправкой на наклон
## камеры (V_STRETCH) — иначе рисунок на экране сплющился бы
func spawn_ruin() -> Node3D:
	var ruin: Node3D = super.spawn_ruin()
	if ruin == null:
		return null
	var old: MeshInstance3D = ruin.get_node_or_null("RuinSprite") as MeshInstance3D
	if old == null:
		return ruin
	var q: QuadMesh = old.mesh as QuadMesh
	var smat: ShaderMaterial = q.material as ShaderMaterial if q != null else null
	var tex: Texture2D = smat.get_shader_parameter("albedo_tex") as Texture2D if smat != null else null
	if q == null or tex == null:
		return ruin
	var w: float = q.size.x
	var d: float = q.size.y * _BBUtil.V_STRETCH
	# Не шире самой ограды. По глубине НЕ ужимаем: плоскость под камерой в 45°
	# и так укорачивается в 0.71 раза — ровно как рисунок стоящего квада
	var k: float = minf(1.0, build_size.x * 1.1 / maxf(w, 0.01))
	w *= k
	d *= k
	var org: Vector3 = ruin.global_position
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for iz in range(MESH_CELLS_Z + 1):
		for ix in range(MESH_CELLS_X + 1):
			var u: float = float(ix) / float(MESH_CELLS_X)
			var v: float = float(iz) / float(MESH_CELLS_Z)
			var lx: float = -w * 0.5 + u * w
			var lz: float = -d * 0.5 + v * d
			var h: float = GameManager.get_terrain_height(org.x + lx, org.z + lz) - org.y
			verts.append(Vector3(lx, h + MESH_LIFT, lz))
			uvs.append(Vector2(u, v))
	for iz2 in range(MESH_CELLS_Z):
		for ix2 in range(MESH_CELLS_X):
			var a: int = iz2 * (MESH_CELLS_X + 1) + ix2
			var b: int = a + 1
			var c: int = a + MESH_CELLS_X + 1
			idx.append_array([a, c, b, b, c, c + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = smat.get_shader_parameter("modulate") if smat.get_shader_parameter("modulate") is Color else Color.WHITE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	# ПРАВИЛО 6: remove_child перед queue_free — имя «RuinSprite» занимает новый
	ruin.remove_child(old)
	old.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "RuinSprite"
	mi.mesh = mesh
	ruin.add_child(mi)
	return ruin

func _exit_tree() -> void:
	# ОВЦЫ ПЕРЕЖИВАЮТ ЗАГОН: снесённая ограда не убивает стадо, но привязка
	# гаснет — иначе овцы вечно паслись бы вокруг несуществующего узла и не
	# размножались бы вовсе (потолок спрашивается у привязки)
	# ТЗ 19.09.2026: овцы снесённого загона РАЗБЕГАЮТСЯ (Sheep.on_pen_lost —
	# привязка гаснет, хозяин остаётся, дом переносится в точку овцы) и
	# становятся блуждающими: их собирает рабочий по ПКМ (Worker, пастух)
	for s in get_tree().get_nodes_in_group("sheep"):
		if s != null and is_instance_valid(s) and s.get("pen") == self:
			if s.has_method("on_pen_lost"):
				s.call("on_pen_lost")
			else:
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

## ── ВНУТРИ ОГРАДЫ — НЕ БОЛЬШЕ INSIDE_CAP (письмо 10, спринт 19) ──────────
## Заказ: до десяти овец пасутся ВНУТРИ загона у центра, лишние — вокруг в
## OVERFLOW_RADIUS. Кто внутри, решает ПОРЯДОК ПРИВЯЗКИ (Sheep.bind_seq):
## первые десять по счётчику — внутри, остальные снаружи; выбыла внутренняя
## — следующая по порядку занимает её место сама, при первой же перебежке
## ── ВНУТРИ ВСЕ, КТО ЕСТЬ (ТЗ 23.09.2026) ─────────────────────────────────
## Было «первые десять внутри, остальные вокруг в OVERFLOW_RADIUS»: при
## тридцати местах иначе и не расставишь. Пять овец помещаются внутрь все,
## и потолок выведен из вместимости — двумя числами они разошлись бы
const INSIDE_CAP := _UCfgP.SHEEP_PEN_CAPACITY
## Оставлен для тех, кто пасётся ВНЕ загона (у замка, дикие): к самому загону
## он больше не относится
const OVERFLOW_RADIUS := 20.0
const INSIDE_FRAC := 0.62
var _bind_counter: int = 0

func next_seq() -> int:
	_bind_counter += 1
	return _bind_counter

func inside_radius() -> float:
	return minf(build_size.x, build_size.z) * 0.5 * INSIDE_FRAC

## Овца — из первых INSIDE_CAP по порядку привязки среди живых этого загона
func inside_slot(s: Node) -> bool:
	if s == null:
		return false
	var my: int = int(s.get("bind_seq"))
	var ahead := 0
	for o in get_tree().get_nodes_in_group("sheep"):
		if o == s or o == null or not is_instance_valid(o):
			continue
		if o.get("pen") != self or bool(o.get("eaten")) or bool(o.get("dead")):
			continue
		if int(o.get("bind_seq")) < my:
			ahead += 1
	return ahead < INSIDE_CAP

func graze_radius_for(s: Node) -> float:
	return inside_radius() if inside_slot(s) else OVERFLOW_RADIUS

## Сколько сейчас внутри (по правилу порядка)
func inside_count() -> int:
	return mini(sheep_count(), INSIDE_CAP)

## Где пасутся привязанные и как далеко разрешено отходить
func graze_center() -> Vector3:
	return global_position

func graze_radius() -> float:
	return maxf(build_size.x, build_size.z) * 0.5 * ROAM_FACTOR

## Сколько ЖИВЫХ овец в загоне (туши место не держат — ТЗ 24.09.2026)
func live_count() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s):
			continue
		if s.get("pen") == self and not bool(s.get("eaten")) and not bool(s.get("dead")):
			n += 1
	return n

## Сколько овец уже привязано к ЭТОМУ загону (с тушами)
func sheep_count() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s):
			continue
		if s.get("pen") == self and not bool(s.get("eaten")):
			n += 1
	return n

## Место есть, когда не полон ЗАГОН и не полон ПОТОЛОК ИГРОКА
## (Sheep.owned_cap_ok, SHEEP_PLAYER_MAX — ТЗ 19.09.2026)
func has_room() -> bool:
	if live_count() >= capacity():
		return false
	return bool(_SheepP.owned_cap_ok(faction))

## Принять принесённую овцу. Утиный контракт: Worker._sheep_dest ищет по
## группе `sheep_pens` любой узел с этим методом
func accept_sheep(s: Node3D) -> bool:
	if s == null or not is_instance_valid(s) or not s.has_method("bind_to_pen"):
		return false
	if not has_room():
		return false
	s.call("bind_to_pen", self, faction)
	return true

# ─────────────────────────────────────────────────────────────────────────────
# РЕГЕНЕРАЦИЯ СТАДА: ЗАГОН САМ ВОСПОЛНЯЕТ ПУСТЫЕ МЕСТА
# ─────────────────────────────────────────────────────────────────────────────
# (ТЗ 23.09.2026, третье письмо.) Загон — «колодец»: пока в нём меньше пяти
# овец, через SHEEP_PEN_RESPAWN_SEC появляется одна новая. Таймер общий на
# загон, а не свой у каждого пустого места: пять пустых мест не должны
# заполниться разом через двенадцать секунд — стадо восстанавливается по
# одной овце, и это видно глазом.
#
# ТАКТ РЕДКИЙ И СВОЙ. Загон — здание, его _process идёт и так; заводить ради
# одной проверки Timer значило бы завести узел на каждый загон

## Сколько ждать до следующей овцы (взводится, как только место освободилось).
## ── НАЧАЛЬНОЕ ЗНАЧЕНИЕ — ПОЛНАЯ ПАУЗА, А НЕ НОЛЬ ────────────────────────
## С нулём первый же кадр после постройки давал `_respawn_t <= 0`, и загон
## рождал овцу МГНОВЕННО, ещё до того, как игрок увидел ограду. В стенде это
## выглядело как «в загоне шесть овец из пяти»: стенд ставил свои пять, а
## одну загон уже успел добавить сам
var _respawn_t: float = _UCfgP.SHEEP_PEN_RESPAWN_SEC

## Пауза до следующей овцы — жребий в [MIN, MAX] (ТЗ 24.09.2026: «20-30 с»).
## Свой генератор, а не общий randf(): новый потребитель общего потока
## сдвинул бы все сеяные жребии партии (правило проекта)
var _rng := RandomNumberGenerator.new()
func _roll_respawn() -> float:
	return _rng.randf_range(_UCfgP.SHEEP_PEN_RESPAWN_MIN_SEC, _UCfgP.SHEEP_PEN_RESPAWN_SEC)
## Стендам: сколько овец загон восполнил за партию
var sheep_respawned: int = 0

## SUPER ОБЯЗАТЕЛЕН: у Building свой _process (очередь найма, полоса
## готовности, ремонт). Перекрой его молча — и загон перестал бы делать всё,
## что умеет обычное здание, а заметили бы это далеко не сразу
## ЗАГОН ТИКАЕТ ВСЕГДА (ТЗ 24.09.2026, второе письмо). Базовое здание
## включает _process только тем, кому он нужен (_needs_tick), — у загона флага
## не было, и таймер респауна не шёл НИ РАЗУ: овцы появлялись только в
## стендах, звавших _tick_restock руками. Это и был «пустой загон с пятью
## рабочими» со скриншота
func _needs_tick() -> bool:
	return true

func _process(delta: float) -> void:
	super._process(delta)
	_tick_restock(delta)

## Один шаг восполнения. Вызывается и стендом напрямую — ему незачем ждать
## реального такта в двенадцать секунд
## Стендам, которые сажают своих овец руками: false — загон не досаживает
var auto_restock: bool = true

func _tick_restock(delta: float) -> void:
	if not auto_restock and delta < 1.0:
		return
	if _dead or faction == Constants.FACTION_NEUTRAL:
		return
	var n: int = live_count()
	if n >= capacity():
		# Загон полон — часы сбрасываются: пауза отсчитывается ОТ ТОГО МИГА,
		# когда место освободилось, а не с постройки загона
		_respawn_t = _roll_respawn()
		return
	_respawn_t -= delta
	if _respawn_t > 0.0:
		return
	_respawn_t = _roll_respawn()
	_spawn_one_sheep()

## Новая овца в случайной точке внутри ограды.
## ИМЯ СО СУФФИКСОМ, потому что `_spawn_one` ЗАНЯТО РОДИТЕЛЕМ: у Building так
## зовётся выпуск нанятого юнита, и переопределение с другой сигнатурой —
## ошибка разбора («The function signature doesn't match the parent»)
func _spawn_one_sheep() -> void:
	if not is_inside_tree():
		return
	# Потолок стада игрока — тот же, что у переноски (Sheep.owned_cap_ok)
	if not bool(_SheepP.owned_cap_ok(faction)):
		return
	var sh = _SheepP.new()
	get_parent().add_child(sh)
	var a: float = _rng.randf() * TAU
	var r: float = sqrt(_rng.randf()) * inside_radius()
	var px: float = global_position.x + cos(a) * r
	var pz: float = global_position.z + sin(a) * r
	sh.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
	if sh.has_method("bind_to_pen"):
		sh.call("bind_to_pen", self, faction)
	sheep_respawned += 1

# ─────────────────────────────────────────────────────────────────────────────
# РАБОЧИЕ: ОДИН НА ОВЦУ
# ─────────────────────────────────────────────────────────────────────────────

## Сколько рабочих сейчас занято овцами ЭТОГО загона
func workers_here() -> int:
	var n := 0
	for w in get_tree().get_nodes_in_group(Constants.unit_group(faction)):
		if w == null or not is_instance_valid(w):
			continue
		if not (w is Worker) or (w as Unit).is_dead():
			continue
		if (w as Worker).farm_pen() == self:
			n += 1
			continue
		var tgt = (w as Worker).sheep_target()
		if tgt != null and is_instance_valid(tgt) and tgt.get("pen") == self:
			n += 1
	return n

## ── КАКУЮ ОВЦУ ДАТЬ ФЕРМЕРУ ЗАГОНА (ТЗ 24.09.2026, п. 1) ──────────────────
## Сперва ТУША с мясом и свободным местом у ножа (доработать начатое), потом
## живая свободная овца. Овцы, на которых уже нацелен другой рабочий, в
## выбор не идут — иначе двое шли бы к одной, и второй разворачивался бы на
## полпути. null — работы сейчас нет, фермер ждёт у ограды
func pick_sheep_for(worker: Node) -> Node3D:
	var taken: Dictionary = {}
	for w in get_tree().get_nodes_in_group(Constants.unit_group(faction)):
		if w == worker or w == null or not is_instance_valid(w) or not (w is Worker):
			continue
		var t = (w as Worker).sheep_target()
		if t != null:
			taken[t] = true
	var from: Vector3 = (worker as Node3D).global_position if worker is Node3D else global_position
	var best_body: Node3D = null
	var bd_body := INF
	var best_live: Node3D = null
	var bd_live := INF
	for sh in get_tree().get_nodes_in_group("sheep"):
		if sh == null or not is_instance_valid(sh) or sh.get("pen") != self or taken.has(sh):
			continue
		if bool(sh.get("eaten")):
			continue
		var d: float = from.distance_squared_to((sh as Node3D).global_position)
		if bool(sh.get("dead")):
			if int(sh.get("meat_left")) <= 0 or not bool(sh.call("butcher_has_room")):
				continue
			if d < bd_body:
				bd_body = d
				best_body = sh
		elif bool(sh.call("is_free")) and d < bd_live:
			bd_live = d
			best_live = sh
	return best_body if best_body != null else best_live

## Где фермер ждёт новую овцу: у проёма ограды (нижняя кромка), а не в центре
func farm_wait_point(worker: Node) -> Vector3:
	# ── КОЛЬЦО ВНУТРИ ОГРАДЫ (ТЗ 14.10.2026, п. 3) ───────────────────────
	# Прежде ждали на одной линии у нижней кромки — вместе с подходом к тушам
	# «с одной стороны» это и была толпа в точке. Теперь у каждого фермера
	# свой угол (farmer_slot), а радиус — чуть меньше полуразмера загона
	var a: float = farmer_angle(worker)
	var r: float = minf(build_size.x, build_size.z) * 0.5 * FARM_RING_FRAC
	var p: Vector3 = global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	p.y = GameManager.get_terrain_height(p.x, p.z)
	return p

## ── МЕСТА ФЕРМЕРОВ (ТЗ 14.10.2026, п. 3) ────────────────────────────────────
## «Рабочие у загона толкаются в одной точке»: все подходили к туше с той
## стороны, откуда шли (от склада), и вставали в SHEEP_GRAB_DIST от неё —
## одной дугой. Теперь каждому фермеру загона выдан свой номер места, номер —
## угол на круге: у туши он встаёт на этом углу в FARM_AROUND_R от неё, в
## ожидании — на кольце внутри ограды. Номера раздаются наименьшим свободным,
## ушедшие с загона их освобождают
const FARM_RING_FRAC := 0.80
const FARM_AROUND_R := 1.0
var _farm_slots: Dictionary = {}

func farmer_slot(worker: Node) -> int:
	if worker == null or not is_instance_valid(worker):
		return 0
	var id: int = worker.get_instance_id()
	var cur: Variant = _farm_slots.get(id)
	if cur != null:
		return int(cur)
	# Чистка ушедших: не наш фермер или освобождён
	for k in _farm_slots.keys():
		var o: Object = instance_from_id(int(k))
		if o == null or not is_instance_valid(o) or not (o is Worker) or (o as Worker).is_dead() or (o as Worker).farm_pen() != self:
			_farm_slots.erase(k)
	var used: Dictionary = {}
	for v in _farm_slots.values():
		used[int(v)] = true
	var slot: int = 0
	while used.has(slot):
		slot += 1
	_farm_slots[id] = slot
	return slot

func farmer_angle(worker: Node) -> float:
	var n: int = maxi(_UCfgP.SHEEP_PEN_WORKERS, 1)
	# Сдвиг на полшага: первый фермер не стоит строго на оси ограды
	return (float(farmer_slot(worker)) + 0.5) * TAU / float(n)

## Где фермеру стоять у овцы/туши в точке around
func farm_stand_point(worker: Node, around: Vector3) -> Vector3:
	var a: float = farmer_angle(worker)
	var p: Vector3 = around + Vector3(cos(a), 0.0, sin(a)) * FARM_AROUND_R
	p.y = GameManager.get_terrain_height(p.x, p.z)
	return p

## Можно ли поставить сюда ещё одного рабочего.
## ПРАВИЛО «ОДИН РАБОЧИЙ НА ОДНУ ОВЦУ» ВЫРАЖЕНО ДВУМЯ УСЛОВИЯМИ СРАЗУ, и оба
## нужны: потолок по загону (SHEEP_PEN_WORKERS) отсекает шестого, даже если
## овец пять, а занятость конкретной овцы (Sheep.butcher_count) — второго
## желающего на ту же тушу
func worker_slot_free() -> bool:
	return workers_here() < _UCfgP.SHEEP_PEN_WORKERS

## Подпись для панели интерфейса
func capacity_text() -> String:
	var n: int = sheep_count()
	var w: int = workers_here()
	return "Овец: %d / %d · рабочих: %d / %d" % [
		n, capacity(), w, _UCfgP.SHEEP_PEN_WORKERS]
