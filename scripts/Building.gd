extends StaticBody3D
class_name Building

const _BBUtil := preload("res://scripts/BillboardUtil.gd")
const _UCfgB  := preload("res://scripts/unit_stats_config.gd")
const _Vis    := preload("res://scripts/units/UnitVisuals.gd")

# ПРЕДЗАГРУЗКА СЦЕН ЮНИТОВ. preload() резолвится на этапе компиляции, поэтому
# PackedScene'ы лежат в памяти ещё до старта игры: найм отряда из 20 бойцов
# не читает диск и не даёт микро-фриза кадра. Спавн — только .instantiate().
const PRELOAD_SCENES := {
	"worker":   preload("res://scenes/units/Worker.tscn"),
	"spearman": preload("res://scenes/units/Spearman.tscn"),
	"archer":   preload("res://scenes/units/Archer.tscn"),
	"warrior":  preload("res://scenes/units/Warrior.tscn"),
}

signal died(building)

@export var faction: int = Constants.FACTION_PLAYER
@export var max_health: float = 300.0
@export var build_size: Vector3 = Vector3(3.0, 2.0, 3.0)
@export var is_dropoff: bool = false

var display_name: String = "Building"
var current_health: float
var production_queue: Array = []
var spawn_offset: Vector3 = Vector3(3.0, 0, 0)
var selection_ring: MeshInstance3D
var sprite_path: String = ""
var _production_timer: float = 0.0
var squad_size: int = 1
var squad_cols: int = 4
var squad_spacing: float = 0.35   # максимально плотный строй: плечом к плечу (было 0.7)

func _ready() -> void:
	current_health = max_health
	collision_layer = Constants.LAYER_BUILDINGS
	collision_mask = 0
	_build_visual()
	_maybe_load_building_sprite()
	add_to_group("all_buildings")
	if faction == Constants.FACTION_PLAYER:
		add_to_group("player_buildings")
	else:
		add_to_group("enemy_buildings")
	if is_dropoff:
		GameManager.register_dropoff(faction, self)
	# Постройка, возведённая при поднятом тумблере Alt, сразу получает полоску
	if GameManager.hp_bars_forced:
		_update_hp_bar()
	# ЧУЖОЕ ЗДАНИЕ ПРЯЧЕТСЯ СРАЗУ, а не со следующим пересчётом тумана.
	# Маска обновляется раз в UPDATE_INTERVAL, и без этой строки вражеская база
	# успевала мигнуть на экране в кадре своего появления — в начале партии это
	# ровно та подсказка о её местоположении, которую туман и должен скрывать.
	# ОТЛОЖЕННО: позицию зданию задают уже ПОСЛЕ add_child, в _ready она ещё
	# нулевая (та же грабля, что у ResourceNode._register_trunk)
	if faction != Constants.FACTION_PLAYER:
		call_deferred("_fog_hide_if_unscouted")

func _fog_hide_if_unscouted() -> void:
	if not is_inside_tree() or GameManager.fog == null:
		return
	set_fog_hidden(not (GameManager.fog as FogOfWar).is_seen(
		global_position.x, global_position.z))

# ─────────────────────────────────────────────────────────────────────────────
# СКРЫТИЕ В ТУМАНЕ ВОЙНЫ
#
# Чужая постройка не видна, пока разведка до неё не дошла. В отличие от бойцов
# (те прячутся по «видно СЕЙЧАС», Unit.tick_visual) здание прячется по
# «РАЗВЕДАНО ЛИ»: строение неподвижно, и однажды найденная база обязана
# оставаться на карте как последнее известное положение — под серой дымкой,
# но на месте. Именно это и разводит два требования владельца: база видна
# после разведки, а перемещения и найм войск под дымкой — нет.
#
# Гасится не только картинка, но и слой столкновений: невидимое здание не
# должно ловить клики выделения (луч выбора ходит по слоям, а не по видимости),
# иначе игрок «находил» вражескую базу, тыкая мышью в чёрное поле.
# ─────────────────────────────────────────────────────────────────────────────
var _fog_hidden: bool = false

func set_fog_hidden(hide_it: bool) -> void:
	if _fog_hidden == hide_it:
		return
	_fog_hidden = hide_it
	visible = not hide_it
	collision_layer = 0 if hide_it else Constants.LAYER_BUILDINGS

func _exit_tree() -> void:
	if is_dropoff:
		GameManager.unregister_dropoff(faction, self)
	# ФЛАЖОК ТОЧКИ СБОРА ЖИВЁТ В МИРЕ, А НЕ ПОД ЗДАНИЕМ (см. _refresh_rally_marker),
	# поэтому queue_free() постройки его с собой НЕ забирает. Снесённый барак
	# оставлял на карте вечный зелёный флажок: узел-сироту, который уже некому
	# ни спрятать, ни удалить (замер qa_rally2, F6)
	if _rally_marker != null and is_instance_valid(_rally_marker):
		_rally_marker.queue_free()
	_rally_marker = null

func _build_visual() -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = build_size
	collider.shape = shape
	collider.position.y = build_size.y / 2.0
	add_child(collider)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = build_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.35, 0.85) if faction == Constants.FACTION_PLAYER else Color(0.75, 0.2, 0.2)
	box.material = mat
	mesh_instance.mesh = box
	mesh_instance.position.y = build_size.y / 2.0
	add_child(mesh_instance)

	selection_ring = make_selection_marker()
	add_child(selection_ring)

# ─────────────────────────────────────────────────────────────────────────────
# МАРКЕР ВЫДЕЛЕНИЯ ЗДАНИЯ
# Вместо жирного жёлтого тора — спрайт Cursor_04.png из menu ui, положенный
# ПЛАШМЯ на землю под зданием: он подчёркивает постройку, а не обхватывает её
# кольцом. Общий для Building, Castle и ConstructionSite — рисунок выделения
# должен быть один на все здания.
# ─────────────────────────────────────────────────────────────────────────────
const SELECT_CURSOR_PATH := "res://assets/environment/menu ui/Cursor_04.png"

func make_selection_marker() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "SelectionMarker"
	var tex: Texture2D = null
	if ResourceLoader.exists(SELECT_CURSOR_PATH):
		tex = load(SELECT_CURSOR_PATH) as Texture2D

	if tex != null:
		var quad := QuadMesh.new()
		# МАРКЕР ОБЛЕГАЕТ ФУНДАМЕНТ, А НЕ ОБВОДИТ ПОЛЯНУ ВОКРУГ.
		# Было: сторона = max(x, z) × 1.45, то есть у замка 8×8 скобки
		# расходились на 11.6 м — на скриншоте игрока они висели далеко за
		# стенами и цеплялись за соседние объекты.
		# Стало: РАЗМЕР ПО КАЖДОЙ ОСИ СВОЙ (прямоугольные постройки получают
		# прямоугольный маркер) и всего +8% на то, чтобы уголки не сливались
		# со стеной вплотную
		quad.size = Vector2(build_size.x * 1.08, build_size.z * 1.08)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture  = tex
		mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
		# Лежит на земле — глубину не пишет, иначе спорит с травой за z-fight
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.render_priority = 2
		quad.material = mat
		mi.mesh = quad
		# QuadMesh смотрит в +Z; поворот на -90° по X кладёт его на грунт
		mi.rotation_degrees.x = -90.0
		mi.position.y = 0.06
	else:
		# Запасной вариант, если ассета нет: прежнее кольцо
		var torus := TorusMesh.new()
		torus.inner_radius = build_size.x * 0.7
		torus.outer_radius = build_size.x * 0.85
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(1, 1, 0)
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		torus.material = ring_mat
		mi.mesh = torus
		mi.position.y = 0.25

	mi.visible = false
	return mi

# Ключ здания в раскладке цветных спрайтов (game_settings.BUILDING_SPRITES).
# Подклассы задают его в _ready() ДО super._ready()
var building_id: String = ""

# ─────────────────────────────────────────────────────────────────────────────
# РАЗМЕР СПРАЙТА ПОСТРОЙКИ — ПО ПРОПОРЦИЯМ КАРТИНКИ, А НЕ ПО КОРОБКЕ КОЛЛИЗИИ
#
# БЫЛО: Vector2(build_size.x * 1.1, build_size.y * 1.2). Обе стороны квада
# брались из ГАБАРИТА постройки, то есть из коробки, которая описывает её
# ПЛАН и высоту для расчётов, а не пропорции рисунка. Совпадало это только у
# замка, у которого коробка (8 × 6) случайно близка к его текстуре 320×256.
# Остальным доставалось:
#   • Бараки — картинка 192×256 (соотношение 0.75), коробка давала 3.85 × 2.64
#     (1.46). Рисунок растягивался вширь ВДВОЕ — ровно та «приплюснутость»;
#   • Домики — 128×192 (0.67) против 2.86 × 2.64 (1.08): сплющены в 1.6 раза;
#   • Башня — 128×256 (0.5) против коробки 3.3 × 2.4: сплющена в 2.7 раза.
#
# СТАЛО: ширина по-прежнему привязана к плану постройки (пятно на земле должно
# совпадать с коллизией и маркером выделения), а ВЫСОТА выводится из
# соотношения сторон самой текстуры. Пропорции картинки сохраняются точно,
# каким бы ни был габарит в конфиге.
# ─────────────────────────────────────────────────────────────────────────────

## Ширина спрайта относительно плана постройки: небольшой запас, чтобы стены
## рисунка не обрезались ровно по коробке коллизии
const SPRITE_WIDTH_FACTOR := 1.1

## Размер квада под текстуру постройки с СОХРАНЕНИЕМ пропорций картинки
static func sprite_quad_size(tex: Texture2D, box: Vector3) -> Vector2:
	var w: float = box.x * SPRITE_WIDTH_FACTOR
	var aspect: float = _BBUtil.frame_aspect(tex)
	if aspect <= 0.01:
		aspect = 1.0
	return Vector2(w, w / aspect)

func _maybe_load_building_sprite() -> void:
	# ЦВЕТ ФРАКЦИИ в приоритете: Castle.png из «{Цвет} Buildings».
	# sprite_path остаётся запасным путём, если цветного набора нет
	var path := ""
	if not building_id.is_empty():
		path = GameManager.building_sprite_path(faction, building_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		path = sprite_path
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	for child in get_children():
		if child == selection_ring:
			continue
		if child is CollisionShape3D:
			continue
		child.visible = false
	var quad := QuadMesh.new()
	quad.size = sprite_quad_size(tex, build_size)
	# ЗДАНИЕ СТОИТ НАМЕРТВО. Раньше здесь был цилиндрический билборд, и при
	# орбите камеры замок/бараки доворачивались к зрителю — читалось как
	# вращение постройки на месте вокруг своей оси. Теперь ориентация мировая:
	# спрайт зафиксирован фасадом на +Z (исходное направление взгляда камеры,
	# _orbit_yaw = 0) и с камерой не связан вообще.
	quad.material = _BBUtil.make_static_material(tex)
	var billboard := MeshInstance3D.new()
	billboard.name = "BuildingSprite"
	billboard.mesh = quad
	# Низ спрайта ложится ровно на грунт: квад центрируется в своём начале
	# координат, поэтому подъём равен ПОЛОВИНЕ его высоты
	billboard.position.y = quad.size.y * 0.5
	# Явно нулевой поворот: узел здания никем не вращается, но пусть это
	# будет видно из кода — фасад смотрит строго по мировому +Z
	billboard.rotation = Vector3.ZERO
	add_child(billboard)
	# Рамка выделения переезжает НА РИСУНОК: пока её строили в _build_visual,
	# обмерять было нечего (см. _fit_marker_to_sprite)
	_fit_marker_to_sprite(tex, quad)

# ─────────────────────────────────────────────────────────────────────────────
# РАМКА ВЫДЕЛЕНИЯ ПО РИСУНКУ, А НЕ ПО КОРОБКЕ
#
# БЫЛО: маркер — квад Cursor_04.png, положенный ПЛАШМЯ на землю размером
# build_size.x × build_size.z. Коробка из конфига описывает пятно для коллизии
# и размещения, а постройка — БИЛБОРД, у которого никакой глубины нет вовсе.
# Замер (qa_bounds): у замка коробка 8×8 м, а нарисован он 8.6 м в ширину и
# 5.7 м в высоту. Положенный на землю квадрат 8.6×8.6 проецируется под 45° в
# ромб высотой 92 px: его ближний угол висел на 46 px НИЖЕ подошвы стены —
# 43% высоты здания пустой травы перед ним, — а дальний на столько же врезался
# внутрь замка. Это и читалось как «рамка улетает далеко от здания».
#
# СТАЛО: маркер — вертикальный квад В ТОЙ ЖЕ ПЛОСКОСТИ, что и спрайт здания, и
# ровно по непрозрачной части картинки (BillboardUtil.opaque_rect) плюс
# небольшой запас. Он обводит именно то, что видит игрок, при любой коробке в
# конфиге. Наклон камеры компенсируется тем же V_STRETCH, что и у самого
# здания, — рамка не может разъехаться со стеной.
#
# Запасной путь (постройка без спрайта, рисуется процедурно) остался прежним:
# там есть настоящий объём, и пятно на земле для него правильно.
# ─────────────────────────────────────────────────────────────────────────────

## Запас рамки вокруг рисунка, доля его размера
const MARKER_MARGIN := 0.06
## Насколько рамка вынесена к камере от плоскости спрайта. Материал и так не
## пишет глубину, но лишние полсантиметра снимают любой спор за z
const MARKER_Z_LIFT := 0.05

func _fit_marker_to_sprite(tex: Texture2D, sprite_quad: QuadMesh) -> void:
	if selection_ring == null or tex == null or sprite_quad == null:
		return
	var mq := selection_ring.mesh as QuadMesh
	if mq == null:
		return      # запасное кольцо-тор: обмерять нечего, оставляем как есть
	var r: Rect2 = _BBUtil.opaque_rect(tex)
	# Доли кадра → метры. По вертикали UV растёт ВНИЗ, поэтому низ рисунка — это
	# (1 - r.end.y), а верх — (1 - r.position.y)
	var w: float = sprite_quad.size.x * r.size.x
	var bottom: float = sprite_quad.size.y * (1.0 - r.end.y)
	var top: float    = sprite_quad.size.y * (1.0 - r.position.y)
	var mw: float = w * MARKER_MARGIN
	var mh: float = (top - bottom) * MARKER_MARGIN
	mq.size = Vector2(w + mw * 2.0, (top - bottom) + mh * 2.0)
	# Рисунок может стоять в кадре не по центру — держим рамку на нём
	var cx: float = sprite_quad.size.x * (r.position.x + r.size.x * 0.5 - 0.5)
	# Тот же множитель, что тянет само здание (BillboardUtil.V_STRETCH): узел
	# растягивается вокруг своего центра, поэтому и центр поднимается на него же
	selection_ring.scale = Vector3(1.0, _BBUtil.V_STRETCH, 1.0)
	selection_ring.position = Vector3(cx,
		((bottom - mh) + (top + mh)) * 0.5 * _BBUtil.V_STRETCH, MARKER_Z_LIFT)
	selection_ring.rotation = Vector3.ZERO

func set_selected(value: bool) -> void:
	if selection_ring:
		selection_ring.visible = value
	# Флажок точки сбора показываем только у выделенного здания: иначе карта
	# зарастает флажками всех бараков сразу
	_rally_visible = value
	_refresh_rally_marker()

var _dead := false

func take_damage(amount: float, attacker: Node = null) -> void:
	if _dead:
		return
	current_health -= amount
	_update_hp_bar()
	if current_health <= 0.0:
		# Снесённая постройка тоже идёт в счёт опыта отряда-разрушителя
		GameManager.credit_kill(attacker, self)
		_die()

# ─────────────────────────────────────────────────────────────────────────────
# ПОЛОСКА ЗДОРОВЬЯ НАД ПОСТРОЙКОЙ
# Устроена ровно так же, как у бойца (см. Unit._apply_hp_bar_fraction): ширина
# самого КВАДА = доля здоровья, потому что билборд затирает масштаб узла.
# Отличия: полоска шире и висит на высоте крыши — иначе она тонет в стене.
# Создаётся ЛЕНИВО: при первом уроне либо когда игрок поднял тумблер Alt.
# ─────────────────────────────────────────────────────────────────────────────
const HP_BAR_WIDTH     := 2.4
const HP_BAR_THICKNESS := 0.16
## Запас над крышей, чтобы полоска не влипала в скат
const HP_BAR_CLEARANCE := 0.9

var _hp_bar_root: Node3D         = null
var _hp_bar_fill: MeshInstance3D = null

## Пересобрать под текущее состояние тумблера Alt (зовёт GameManager)
func refresh_hp_bar() -> void:
	if _dead:
		return
	_update_hp_bar()

func _update_hp_bar() -> void:
	var frac: float = 0.0
	if max_health > 0.0:
		frac = clampf(current_health / max_health, 0.0, 1.0)
	# Тумблер Alt имеет АБСОЛЮТНЫЙ приоритет — см. Unit._update_hp_bar()
	var forced: bool = GameManager.hp_bars_forced
	if _hp_bar_fill == null:
		if not forced:
			return
		_build_hp_bar()
		if _hp_bar_fill == null:
			return
	if _hp_bar_root:
		_hp_bar_root.visible = forced
	var q := _hp_bar_fill.mesh as QuadMesh
	if q == null:
		return
	var w: float = maxf(HP_BAR_WIDTH * frac, 0.001)
	q.size = Vector2(w, HP_BAR_THICKNESS)
	q.center_offset = Vector3(-(HP_BAR_WIDTH - w) * 0.5, 0.0, 0.0)

func _build_hp_bar() -> void:
	_hp_bar_root = Node3D.new()
	_hp_bar_root.name = "HPBar"
	_hp_bar_root.position.y = build_size.y + HP_BAR_CLEARANCE
	add_child(_hp_bar_root)

	_hp_bar_fill = MeshInstance3D.new()
	_hp_bar_fill.name = "HPFill"
	var fill_q := QuadMesh.new()
	fill_q.size = Vector2(HP_BAR_WIDTH, HP_BAR_THICKNESS)
	# Материал общий на весь мир (см. UnitVisuals) — на пачке построек это
	# один и тот же ресурс, а не копия на каждую стену
	fill_q.material = _Vis.hp_bar_material()
	_hp_bar_fill.mesh = fill_q
	_hp_bar_root.add_child(_hp_bar_fill)

func is_dead() -> bool:
	return _dead

# Жёсткий лимит на один заказ. Берётся из конфига (SQUAD_SIZE_HARD_CAP):
# размер отряда крутится в SQUAD_SIZE_*, а это только предохранитель
const MAX_SQUAD_SIZE := _UCfgB.SQUAD_SIZE_HARD_CAP

## ЗАКАЗ НАЙМА ПО КОНФИГУ (unit_stats_config.TRAINING[building_id][unit_id]).
## Цена, время и размер отряда лежат в одном месте, а не разбросаны по
## train_* методам — HUD показывает в карточке ровно те же числа.
func train_from_config(unit_id: String) -> bool:
	var c: Dictionary = _UCfgB.train_cfg(building_id, unit_id)
	if c.is_empty():
		return false
	var old_size := squad_size
	var old_cols := squad_cols
	squad_size = int(c.get("squad", 1))
	squad_cols = int(c.get("cols", 4))
	var ok := queue_unit(unit_id, _UCfgB.train_cost(building_id, unit_id),
		float(c.get("time", 10.0)))
	squad_size = old_size
	squad_cols = old_cols
	return ok

## ОТМЕНА ЗАКАЗА (ПКМ по иконке найма). Снимается ПОСЛЕДНИЙ заказ этого типа,
## а деньги за него возвращаются полностью. Активный (нулевой) заказ отменяется
## тоже — прогресс по нему просто пропадает.
## Возвращает true, если что-то отменили.
func cancel_order(unit_name: String) -> bool:
	for i in range(production_queue.size() - 1, -1, -1):
		var order: Dictionary = production_queue[i]
		if String(order.get("name", "")) != unit_name:
			continue
		return cancel_order_at(i)
	return false

## ОТМЕНА ЗАКАЗА ПО МЕСТУ В ОЧЕРЕДИ (ПКМ по конкретной иконке визуальной
## очереди — HUD._order_slot). В отличие от cancel_order(), снимает РОВНО ТУ
## заявку, по которой кликнули, даже если рядом стоят заявки того же типа.
func cancel_order_at(index: int) -> bool:
	if index < 0 or index >= production_queue.size():
		return false
	var order: Dictionary = production_queue[index]
	var refund: Dictionary = order.get("cost", {})
	for key in refund:
		ResourceManager.add_resource(faction, int(key), float(refund[key]))
	production_queue.remove_at(index)
	if index == 0:
		_production_timer = 0.0     # отменили тот, что уже строился
	return true

## Сколько заказов этого типа сейчас в очереди (для цифры на иконке)
func queued_count(unit_name: String) -> int:
	var n := 0
	for order in production_queue:
		if String((order as Dictionary).get("name", "")) == unit_name:
			n += 1
	return n

## Есть ли ЗАКАЗ, который уже отсчитал своё время, но ещё выходит из ворот.
##
## Между «производство закончилось» и «отряд стоит на карте» лежит выход
## шеренгами (см. ROW_RELEASE_SEC): у отряда в 50 человек это почти две
## секунды, и всё это время очередь производства уже ПУСТА. Кто считает свои
## силы по очереди — а так делает ИИ, решая, не заказать ли ещё отряд, —
## в этом окне видит заказ пропавшим и оформляет дубль. Замер qa_ai (раздел 4):
## шесть отрядов копейщиков при лимите в три.
func spawning_count(unit_name: String) -> int:
	var n := 0
	for job in _pending_spawns:
		if String((job as Dictionary).get("name", "")) == unit_name:
			n += 1
	return n

## Заказ этого типа ещё «в работе»: либо в очереди, либо выходит из ворот
func in_progress_count(unit_name: String) -> int:
	# Выходящий отряд — это ОДИН заказ, сколько бы бойцов в нём ни осталось
	return queued_count(unit_name) + (1 if spawning_count(unit_name) > 0 else 0)

## ВСЕГО заказов «в работе» у здания — очередь плюс тот, что сейчас выходит.
## Именно это, а не длину очереди, должен спрашивать тот, кто решает,
## не пора ли заказать ещё
func orders_in_progress() -> int:
	return production_queue.size() + (1 if not _pending_spawns.is_empty() else 0)

func queue_unit(unit_name: String, cost: Dictionary, build_time: float) -> bool:
	if not ResourceManager.spend(faction, cost):
		return false
	var sz := clampi(squad_size, 1, MAX_SQUAD_SIZE)
	# Цена едет ВМЕСТЕ с заказом: только так отмена по ПКМ может вернуть ровно
	# столько, сколько было списано, не пересчитывая её задним числом
	production_queue.append({"name": unit_name, "time": build_time, "size": sz,
		"cols": squad_cols, "spacing": squad_spacing, "cost": cost.duplicate()})
	set_process(true)   # заказ есть — здание просыпается (см. _process)
	return true

# ── ПОКАДРОВЫЙ ВЫХОД ОТРЯДА (борьба с фризом) ────────────────────────────────
# Раньше все 20 бойцов инстанцировались и добавлялись в дерево В ОДНОМ кадре —
# 20 × (_ready + сборка визуала + вход в дерево) давали видимую паузу.
# Теперь заказ кладётся в _pending_spawns и разбирается по SPAWN_PER_FRAME
# юнитов за кадр, причём add_child идёт через call_deferred: узел входит в
# дерево вне физического шага, не тормозя текущий кадр.
const SPAWN_PER_FRAME := 2

# ── ВЫХОД ШЕРЕНГА ЗА ШЕРЕНГОЙ ────────────────────────────────────────────────
# Покадровая выдача по два бойца разбивала фриз, но выглядела как струйка:
# отряд вытекал из ворот сплошной ниткой и собирался в строй уже в поле.
#
# Теперь выпускаем ЦЕЛЫМИ ШЕРЕНГАМИ и с паузой между ними. Ряд уходит от ворот,
# следующий выступает через ROW_RELEASE_SEC — получается тот самый поэтапный
# выход строем, а нагрузка на кадр даже ниже прежней: шеренга это 4–5 бойцов,
# но раз в четверть секунды, а не два каждый кадр.
#
# Ограничитель SPAWN_PER_FRAME остаётся страховкой на случай гигантской шеренги:
# больше него за один кадр не выйдет никто.
const ROW_RELEASE_SEC := 0.25

var _pending_spawns: Array = []   # элементы: {"name","idx","cols","spacing"}
## Сколько ждать до выпуска следующей шеренги
var _row_gate: float = 0.0

## Нужен ли зданию покадровый тик, когда очередь производства пуста.
## По умолчанию НЕТ: достроенное здание без заказов ничего не считает и
## снимается с _process целиком. Переопределяют те, у кого есть свой таймер
## (Castle — пассивное золото, Mine — добыча, ConstructionSite — прогресс).
func _needs_tick() -> bool:
	return false

func _process(delta: float) -> void:
	_drain_pending_spawns(delta)
	if production_queue.is_empty():
		# СТАТИЧНОЕ ЗДАНИЕ НЕ ТИКАЕТ. Десятки построек, каждая из которых
		# каждый кадр проверяет пустую очередь, — бесплатный, но лишний
		# обход дерева. Просыпаемся в queue_unit()
		if _pending_spawns.is_empty() and not _needs_tick():
			set_process(false)
	if not production_queue.is_empty():
		_production_timer += delta
		var current = production_queue[0]
		if _production_timer >= current["time"]:
			_production_timer = 0.0
			production_queue.pop_front()
			var sz: int = clampi(current.get("size", squad_size), 1, MAX_SQUAD_SIZE)
			var cols: int   = current.get("cols", squad_cols)
			var sp: float   = current.get("spacing", squad_spacing)
			# ОДИН ЗАКАЗ = ОДИН ОТРЯД. Запись в реестре заводится здесь, до
			# спавна: все бойцы заявки получат один и тот же squad_id и дальше
			# живут как единое целое — выделяются и получают приказы вместе
			var unit_name: String = String(current["name"])
			var sid: int = GameManager.new_squad(faction, unit_name)
			# СВОЯ ПОЛОСА ВЫХОДА У КАЖДОГО ОТРЯДА. Раньше все заказы здания шли
			# в одну точку сбора, и два отряда из одного барака вставали друг в
			# друга (замер QA: центры масс в 1.86 м, 13 бойцов из 50 вплотную к
			# чужим). Теперь каждый следующий отряд отходит в свою полосу
			var lane: int = _exit_lane
			_exit_lane += 1
			# Строй отряда снимается СЕЙЧАС и едет вместе с каждой заявкой:
			# пока отряд выходит по кадрам, squad_cols здания может смениться
			# ТОЧКА СБОРА СНИМАЕТСЯ ТАМ ЖЕ И ПО ТОЙ ЖЕ ПРИЧИНЕ. Отряд выходит по
			# два бойца за кадр, а игрок может переставить флажок прямо во время
			# найма — раньше _spawn_one читал rally_point ЖИВЬЁМ, и ОДИН заказ
			# разрывался надвое: часть уходила к старой точке, часть к новой
			# (замер qa_rally2, F4: 8 бойцов у старой точки, 12 у новой).
			# Один заказ — один отряд — одна точка; переставленный флажок
			# действует со СЛЕДУЮЩЕГО заказа
			var r_has: bool = has_rally
			var r_pos: Vector3 = rally_point
			for i in range(sz):
				_pending_spawns.append({
					"name": unit_name, "idx": i, "cols": cols, "spacing": sp,
					"squad": sid, "total": sz, "lane": lane,
					"has_rally": r_has, "rally": r_pos,
				})

func _drain_pending_spawns(delta: float = 0.0) -> void:
	if _pending_spawns.is_empty():
		_row_gate = 0.0
		return
	_row_gate -= delta
	if _row_gate > 0.0:
		return
	# Выпускаем РОВНО ОДНУ шеренгу: подряд идущие заявки с одинаковым номером
	# ряда (idx / cols). Дальше ждём ROW_RELEASE_SEC — так следующий ряд
	# выступает из ворот вслед за предыдущим, а не вперемешку с ним
	var first: Dictionary = _pending_spawns[0]
	var cols0: int = maxi(int(first.get("cols", 1)), 1)
	var row0:  int = int(first.get("idx", 0)) / cols0
	var n := 0
	while n < _pending_spawns.size() and n < SPAWN_PER_FRAME * 4:
		var j: Dictionary = _pending_spawns[n]
		var c: int = maxi(int(j.get("cols", 1)), 1)
		if int(j.get("idx", 0)) / c != row0:
			break
		n += 1
	for _i in range(n):
		var job: Dictionary = _pending_spawns.pop_front()
		var r_pos: Vector3 = job.get("rally", Vector3.ZERO)
		_spawn_one(String(job["name"]), int(job["idx"]), int(job["cols"]),
			float(job["spacing"]), int(job.get("squad", 0)), int(job.get("lane", 0)),
			int(job.get("total", 1)), bool(job.get("has_rally", false)), r_pos)
	_row_gate = ROW_RELEASE_SEC

# ─────────────────────────────────────────────────────────────────────────────
# ВОРОТА — У СТЕНЫ ФАСАДА, А НЕ «ГДЕ-ТО СБОКУ»
#
# spawn_offset у базовой постройки был прибит к (+3, 0, 0) — жёстко на восток
# в МИРОВЫХ осях. Барак, стоящий западнее замка, выпускал отряд себе за спину;
# барак у восточного края — в стену карты. Игрок видел, как бойцы возникают
# сбоку от здания и оттуда разбредаются.
#
# Теперь правило общее для всех построек (Замок его уже применял у себя):
# фасад смотрит к СЕРЕДИНЕ КАРТЫ, то есть к противнику, а точка выхода лежит
# ровно у стены фасада — половина габарита плюс небольшой зазор на пороге.
# Считается ЛЕНИВО: позиция здания задаётся уже ПОСЛЕ add_child(), в _ready()
# её ещё нет.
# ─────────────────────────────────────────────────────────────────────────────

## Зазор от стены до точки появления: боец не должен возникать внутри текстуры
const GATE_CLEARANCE := 0.9

## Сколько колонн даёт КВАДРАТНЫЙ строй на `total` бойцов.
## Общая для всех точка: тем же расчётом пользуются пополнение гарнизона и
## перестроение, иначе отряд менял бы пропорции после каждой потери.
## `fallback` берётся, когда размер неизвестен (одиночный найм)
static func square_cols(total: int, fallback: int = 4) -> int:
	if total <= 1:
		return maxi(fallback, 1)
	return maxi(int(ceil(sqrt(float(total)))), 1)

## Единичный вектор «на фронт» — от постройки к середине карты
func front_dir() -> Vector3:
	var d := -global_position
	d.y = 0.0
	if d.length() < 1.0:
		return Vector3.BACK
	return d.normalized()

## Обновить направление ворот по фактическому положению постройки
func _face_front() -> void:
	spawn_offset = front_dir() * (maxf(build_size.x, build_size.z) * 0.5 + GATE_CLEARANCE)

func _gate_position() -> Vector3:
	_face_front()
	return global_position + spawn_offset

# ОТХОД ОТ ВОРОТ. Отряд появляется вплотную к зданию (иначе бойцы «телепортом»
# возникают в поле), а затем сам отходит на это расстояние и освобождает проход:
# без этого следующий отряд упирался в предыдущий прямо в дверях.
#
# БЫЛО 14 м. Вместе с глубиной строя (у отряда в 50 человек это ещё десяток
# рядов) первая шеренга вставала метрах в двадцати от здания, и выглядело это
# так, будто отряд самовольно ушёл в поле. Теперь ПЕРВАЯ ШЕРЕНГА встаёт в
# четырёх метрах от ворот — ровно «у стены», как и просили. Глубину строя
# убрать нельзя: пятьдесят человек физически занимают место, но растёт она
# ОТ здания наружу и начинается вплотную к нему.
const SQUAD_EXIT_DISTANCE := 4.0
## Запас между полосами выхода соседних отрядов, метры (сверх ширины строя)
const EXIT_LANE_GAP := 4.0

## Счётчик полос выхода: каждый следующий заказ уходит в свою сторону от ворот
var _exit_lane: int = 0

# ── ТОЧКА СБОРА ──────────────────────────────────────────────────────────────
# Игрок выделяет постройку и ПКМ по карте назначает, куда идут новые отряды
# (см. SelectionManager._try_set_rally). Пока точка не задана, отряд, как и
# раньше, отходит от ворот на SQUAD_EXIT_DISTANCE и встаёт у дверей.
# Строй при этом СОХРАНЯЕТСЯ: к точке сбора едет то же смещение бойца в строю,
# что и к воротам, — иначе отряд приходил бы на точку кучей.
var rally_point: Vector3 = Vector3.ZERO
var has_rally: bool = false

## Флажок точки сбора на земле. Видно, только пока здание выделено
var _rally_marker: Node3D = null

## Построить маркер: древко + флажок + кольцо на земле. Всё процедурно —
## отдельной картинки под это в паке нет
func _build_rally_marker() -> Node3D:
	var root := Node3D.new()
	root.name = "RallyMarker"
	# Кольцо на земле: видно, даже если флажок заслонён деревом
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.9
	tor.outer_radius = 1.15
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.albedo_color   = Color(0.30, 0.95, 0.35, 0.85)
	rm.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.position.y = 0.06
	root.add_child(ring)
	# Древко
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.055
	cyl.bottom_radius = 0.055
	cyl.height = 2.6
	pole.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.36, 0.26, 0.14)
	pole.material_override = pm
	pole.position.y = 1.3
	root.add_child(pole)
	# Полотнище: билборд, чтобы флажок был виден с любого ракурса
	var flag := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 0.7)
	# ПОЛОТНИЩЕ ВИСИТ СБОКУ ОТ ДРЕВКА, А НЕ НАСАЖЕНО НА НЕГО. Раньше квад стоял
	# ровно по оси древка, непрозрачный цилиндр рассекал его пополам, и вблизи
	# флажок читался как «палка с двумя зелёными квадратиками» (снимок qa_rally2
	# r2_02b). Сдвиг задан через center_offset САМОГО МЕША: в отличие от смещения
	# узла, он живёт в локальных координатах и поворачивается вместе с билбордом,
	# поэтому полотнище остаётся у древка с любого ракурса камеры
	quad.center_offset = Vector3(0.56, 0.0, 0.0)
	flag.mesh = quad
	var fm := StandardMaterial3D.new()
	fm.albedo_color    = Color(0.25, 0.90, 0.35)
	fm.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode  = BaseMaterial3D.BILLBOARD_FIXED_Y
	fm.cull_mode       = BaseMaterial3D.CULL_DISABLED
	flag.material_override = fm
	flag.position = Vector3(0.0, 2.25, 0.0)
	root.add_child(flag)
	return root

## Показать/спрятать флажок. Зовётся из set_selected: маркер нужен игроку
## ровно тогда, когда он смотрит на это здание
func _refresh_rally_marker() -> void:
	if not has_rally:
		if _rally_marker != null and is_instance_valid(_rally_marker):
			_rally_marker.queue_free()
		_rally_marker = null
		return
	if _rally_marker == null or not is_instance_valid(_rally_marker):
		_rally_marker = _build_rally_marker()
		# Маркер живёт в МИРЕ, а не под зданием: иначе он ездил бы вместе с
		# ним и наследовал его масштаб
		var host: Node = get_parent()
		if host == null:
			host = self
		host.add_child(_rally_marker)
	_rally_marker.global_position = rally_point
	_rally_marker.visible = _rally_visible

## Выделено ли здание прямо сейчас
var _rally_visible: bool = false

## Назначить точку сбора. Y берётся с рельефа
func set_rally_point(pos: Vector3) -> void:
	# ТОЧКА СБОРА ЗАЖИМАЕТСЯ В ГРАНИЦЫ МИРА. Сюда приходит СЫРАЯ точка земли из
	# SelectionManager._handle_right_click: клик мимо карты даёт пересечение
	# луча с плоскостью y=0 за краем поля (сотни метров в черноте). Слоты строя
	# считаются ОТ этой точки, и весь выходящий отряд схлопывался в один угол
	# карты — приказ каждого бойца зажимался в одно и то же место
	var c: Vector2 = GameManager.clamp_to_map(pos.x, pos.z)
	rally_point = Vector3(c.x, GameManager.get_terrain_height(c.x, c.y), c.y)
	has_rally = true
	_refresh_rally_marker()

## Снять точку сбора — отряды снова остаются у дверей
func clear_rally_point() -> void:
	has_rally = false
	rally_point = Vector3.ZERO
	_refresh_rally_marker()

## r_has/r_pos — ТОЧКА СБОРА, СНЯТАЯ НА МОМЕНТ ЗАПУСКА ЗАКАЗА (см. _process).
## Живые поля has_rally/rally_point здесь читать нельзя: заказ выходит несколько
## кадров, и перестановка флажка посреди найма рвала отряд на две половины
func _spawn_one(unit_name: String, idx: int, cols: int = -1, spacing: float = -1.0,
		squad_id: int = 0, lane: int = 0, total: int = 1,
		r_has: bool = false, r_pos: Vector3 = Vector3.ZERO) -> void:
	# Сцена уже в памяти (см. PRELOAD_SCENES) — instantiate() без чтения диска.
	# Спрайт-шиты юнита тоже кэшированы (SpriteSheetParser._frames_cache),
	# поэтому _ready() второго и последующих бойцов диск не трогает.
	var scene: PackedScene = PRELOAD_SCENES.get(unit_name)
	if scene == null:
		push_error("Building._spawn_one: unknown unit '%s'" % unit_name)
		return
	var unit: Unit = scene.instantiate()

	if unit == null:
		push_error("Building._spawn_one: %s.new() returned null!" % unit_name)
		return

	unit.faction = faction
	var parent := get_parent()
	if parent == null:
		push_error("Building._spawn_one: get_parent() is null — building not in scene tree?")
		unit.queue_free()
		return
	if cols <= 0:
		cols = squad_cols
	if spacing < 0.0:
		spacing = squad_spacing
	# КВАДРАТ, А НЕ ПОЛОСА. Число колонн из конфига прибито к 5 независимо от
	# размера заказа: отряд в 10 лучников выходил строем 5×2 — широкой лентой,
	# а не «кирпичом». Ровный квадрат читается как строй с любого ракурса и
	# ведёт себя предсказуемо при смыкании рядов
	cols = square_cols(total, cols)
	var gate := _gate_position()
	var col      := idx % cols
	var row      := idx / cols
	# Ряд в строю: копейщики первых двух шеренг выходят с копьями наперевес
	unit.formation_row = row
	var offset_x := (col - (cols - 1) * 0.5) * spacing
	var offset_z := row * spacing
	# Направление выхода задаётся spawn_offset здания (ворота), нормируется
	var exit_dir := spawn_offset
	exit_dir.y = 0.0
	if exit_dir.length() < 0.01:
		exit_dir = Vector3.BACK
	exit_dir = exit_dir.normalized()
	var side := Vector3(-exit_dir.z, 0.0, exit_dir.x)
	# ПОЛОСА ЭТОГО ОТРЯДА. Чередуем стороны от оси ворот: 0, +1, −1, +2, −2 …
	# так соседние отряды расходятся веером, а не встают друг другу в спину.
	#
	# Шаг полосы считается по РЕАЛЬНОМУ пятну отряда, а не по ширине строя:
	# 50 бойцов в 5 колонн формально занимают 1.75 м, но пока отряд идёт к точке
	# сбора, он расплывается в пятно примерно √n × 0.7 м. По ширине строя полосы
	# получались вдвое уже нужного, и соседние отряды перемешивались
	var blob: float = sqrt(float(maxi(total, 1))) * 0.7
	var lane_step: float = maxf(float(cols) * spacing, blob) + EXIT_LANE_GAP
	var lane_dir: float  = 1.0 if lane % 2 == 1 else -1.0
	var lane_mag: float  = float((lane + 1) / 2)
	# Точка сбора отряда: ОТ ворот на SQUAD_EXIT_DISTANCE, строй сохраняется
	var rally: Vector3 = gate + exit_dir * (SQUAD_EXIT_DISTANCE + offset_z) \
		+ side * (offset_x + lane_dir * lane_mag * lane_step)
	# НАЗНАЧЕННАЯ ИГРОКОМ ТОЧКА СБОРА перебивает место у дверей. Смещение бойца
	# в строю переносится как есть, а направление взгляда считается от ворот
	# к точке — отряд приходит туда единым фронтом, а не толпой
	if r_has:
		var course := r_pos - gate
		course.y = 0.0
		if course.length() > 0.01:
			exit_dir = course.normalized()
			side = Vector3(-exit_dir.z, 0.0, exit_dir.x)
		# ПОЛОСА ВЫХОДА К НАЗНАЧЕННОЙ ТОЧКЕ НЕ ПРИБАВЛЯЕТСЯ. Полосы разводят
		# отряды, выходящие из ОДНИХ ворот, чтобы они не толкались в дверях —
		# у ворот это нужно. Но игрок указал КОНКРЕТНОЕ место, и сдвигать
		# отряд от флажка нельзя: счётчик полос только растёт, поэтому второй
		# заказ приходил в 5.4 м сбоку, третий ещё дальше, и так без предела
		# (замер qa_rally2, F8). К флажку идут все — строем, но в одну точку
		rally = r_pos + exit_dir * offset_z + side * offset_x
	# Вход в дерево — отложенно (вне текущего кадра), позиция и приказ следом:
	# отложенные вызовы выполняются в порядке постановки, так что к моменту
	# _place_spawned юнит уже в дереве и global_position корректен
	parent.call_deferred("add_child", unit)
	call_deferred("_place_spawned", unit, gate, rally, squad_id, exit_dir)

func _place_spawned(unit: Unit, gate: Vector3, rally: Vector3,
		squad_id: int = 0, exit_dir: Vector3 = Vector3.ZERO) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
		return
	unit.global_position = gate
	if squad_id > 0:
		GameManager.add_to_squad(squad_id, unit)
	# Весь отряд смотрит в сторону выхода — иначе бойцы разворачиваются
	# кто куда, пока разбредаются по своим слотам
	unit.command_move(rally, false, exit_dir)

func _die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	spawn_ruin()
	queue_free()

# ─────────────────────────────────────────────────────────────────────────────
# РУИНЫ НА МЕСТЕ СНЕСЁННОЙ ПОСТРОЙКИ
#
# Замок оставляет Castle_Destroyed, всё остальное — House_Destroyed
# (game_settings.PROCESS_SPRITES). Руина — ЧИСТО ДЕКОРАЦИЯ: обычный Node3D со
# спрайтом, без коллизии, без групп зданий и без здоровья. Это принципиально:
# попади она хоть в одну группу, её начали бы считать и проверка победы, и ИИ,
# и клик мышью — «неубиваемое здание» на пустом месте.
#
# Ставится в момент смерти, до queue_free(): дети умирающего узла уходят вместе
# с ним, поэтому руина цепляется к РОДИТЕЛЮ, а не к себе.
# ─────────────────────────────────────────────────────────────────────────────
func spawn_ruin() -> void:
	var parent := get_parent()
	if parent == null or building_id.is_empty():
		return
	var path: String = GameManager.ruin_sprite_path(faction, building_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	# РУИНА — ТЕЛО ТОЛЬКО РАДИ ПКМ, И НА ОТДЕЛЬНОМ СЛОЕ.
	# Группы зданий и здоровье ей по-прежнему не положены (см. шапку): для
	# проверки победы, ИИ и левого клика её не существует. Но по ней должен
	# работать приказ «отстроить заново», а приказы в проекте адресуются лучом,
	# поэтому нужен коллайдер. Слой LAYER_RUINS в маску левого клика не входит,
	# так что выделить руину нельзя и луч, ищущий постройки, её не замечает.
	# collision_mask = 0 — общее правило проекта, ни с чем она не сталкивается
	var ruin := StaticBody3D.new()
	ruin.name = "Ruin_" + building_id
	ruin.collision_layer = Constants.LAYER_RUINS
	ruin.collision_mask  = 0
	ruin.add_to_group("ruins")
	# Что и чьё тут стояло — чтобы стройплощадка встала ровно та же
	ruin.set_meta("ruin_building_id", building_id)
	ruin.set_meta("ruin_faction", faction)
	ruin.set_meta("ruin_size", build_size)
	var quad := QuadMesh.new()
	quad.size = sprite_quad_size(tex, build_size)
	quad.material = _BBUtil.make_static_material(tex)
	var mi := MeshInstance3D.new()
	mi.name = "RuinSprite"
	mi.mesh = quad
	mi.position.y = quad.size.y * 0.5
	ruin.add_child(mi)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = build_size
	col.shape = box
	col.position.y = build_size.y * 0.5
	ruin.add_child(col)
	parent.add_child(ruin)
	ruin.global_position = global_position
	# Срок жизни руин — в конфиге владельца; 0 означает «лежат вечно»
	var life: float = _UCfgB.RUIN_LIFETIME_SEC
	if life > 0.0:
		var t := ruin.get_tree().create_timer(life)
		t.timeout.connect(ruin.queue_free)
