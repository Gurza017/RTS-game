extends StaticBody3D
class_name Building

const _BBUtil := preload("res://scripts/BillboardUtil.gd")
const _UCfgB  := preload("res://scripts/unit_stats_config.gd")
const _Diff := preload("res://scripts/game_difficulty_config.gd")
const _Vis    := preload("res://scripts/units/UnitVisuals.gd")

# ПРЕДЗАГРУЗКА СЦЕН ЮНИТОВ. preload() резолвится на этапе компиляции, поэтому
# PackedScene'ы лежат в памяти ещё до старта игры: найм отряда из 20 бойцов
# не читает диск и не даёт микро-фриза кадра. Спавн — только .instantiate().
## МОНАХ ЗДЕСЬ ОТСУТСТВОВАЛ, хотя Monk.gd написан целиком, в конфиге он есть и
## Замок предлагает его нанять (HUD._train_cmd). Заказ доходил до _spawn_one,
## сцены не находилось — push_error, и игрок оставался без бойца, ЗАПЛАТИВ за
## него (деньги списываются в момент заказа). Не хватало ровно .tscn и строчки
## здесь. Корень сцены — Node3D: Unit давно наследует именно его, а не
## CharacterBody3D, как в трёх соседних сценах (там это наследие, тела спят и
## кадру не стоят — проверено стендом qa_soa_floor/Bodies)
const PRELOAD_SCENES := {
	"worker":   preload("res://scenes/units/Worker.tscn"),
	"spearman": preload("res://scenes/units/Spearman.tscn"),
	"archer":   preload("res://scenes/units/Archer.tscn"),
	"warrior":  preload("res://scenes/units/Warrior.tscn"),
	"monk":     preload("res://scenes/units/Monk.tscn"),
	# ГОБЛИНЫ. Регистрация нужна не ради кнопок найма (у орды нет панели), а
	# ради Castle._revive_one: доукомплектование отряда в хижине берёт сцену
	# отсюда, и без записи разбитый отряд выходил бы из хижины прежним
	"goblin_spearman": preload("res://scenes/units/GoblinSpearman.tscn"),
	"goblin_rider":    preload("res://scenes/units/GoblinPigRider.tscn"),
	"troll":           preload("res://scenes/units/Troll.tscn"),
	"gnoll":           preload("res://scenes/units/Gnoll.tscn"),
}

## Есть ли чем исполнить заказ на такого бойца. Спрашивают и очередь найма, и
## интерфейс: предлагать кнопку найма того, кого нельзя создать, — это отдать
## деньги в никуда
static func can_spawn(unit_name: String) -> bool:
	return PRELOAD_SCENES.has(unit_name)

## О каких типах уже пожаловались (см. _spawn_one): жалоба одна на тип, а не
## на каждого бойца из заказа
static var _missing_warned: Dictionary = {}

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
## ── ИНТЕРВАЛ ВЫХОДЯЩЕГО ИЗ ЗДАНИЯ ОТРЯДА ───────────────────────────────────
## Было 0.35 — «максимально плотный строй, плечом к плечу». На экране это
## оказалось теснее самого спрайта: фигура занимает около полуметра в ширину,
## соседи налезали друг на друга силуэтами, и свежий отряд читался слипшимся
## комком с мерцающими краями (жалоба владельца по свежесозданным мечникам).
## 0.55 — это по-прежнему плотная шеренга (радиус расталкивания 0.29 м, то
## есть до толкотни ещё далеко), но силуэты уже не перекрываются
var squad_spacing: float = 0.55

func _ready() -> void:
	current_health = max_health
	collision_layer = Constants.LAYER_BUILDINGS
	collision_mask = 0
	# ── ВОРОТА ЗАВОДЯТСЯ ЗДЕСЬ, А НЕ ЛЕНИВО ─────────────────────────────────
	# _gate_position() зовут в том числе из _physics_process (сторожевой обход
	# гарнизона в Castle), а add_child в момент, когда движок обходит дерево,
	# отбивается — узел не добавляется, его global_position равен ЛОКАЛЬНОЙ
	# точке, и ворота оказываются у начала координат карты. Ровно так и вышло:
	# qa_garrison показал отряд, вечно идущий к точке (0, 0, 6.5) вместо замка
	_ensure_spawn_point()
	_build_visual()
	_maybe_load_building_sprite()
	add_to_group("all_buildings")
	add_to_group(Constants.building_group(faction))
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

## Форма, по которой ЛУЧ МЫШИ попадает в постройку. Держим ссылку: пока
## спрайта нет, это коробка из конфига, а как только рисунок загружен —
## она подгоняется под НЕГО (см. _fit_pick_to_sprite)
var _pick_shape: CollisionShape3D = null

## ── ФОРМА ПОПАДАНИЯ ЗАВОДИТСЯ ОДНИМ МЕСТОМ ─────────────────────────────────
## _build_visual переопределяют и Замок, и Хижина, и Стройплощадка, и каждый
## заводил свой CollisionShape3D. Пока форма была просто коробкой из конфига,
## это сходило с рук; теперь её подгоняют под рисунок (_fit_pick_to_sprite), и
## подгонять надо ТУ САМУЮ форму, по которой стреляет луч мыши. Забыть здесь
## ссылку — значит молча оставить наследнику старое поведение, что и вышло с
## хижиной: кольцо у неё встало по рисунку, а клик по-прежнему промахивался
func _add_pick_shape() -> CollisionShape3D:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = build_size
	collider.shape = shape
	collider.position.y = build_size.y / 2.0
	add_child(collider)
	_pick_shape = collider
	return collider

func _build_visual() -> void:
	_add_pick_shape()

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

## ── АНИМИРОВАННАЯ ПОСТРОЙКА ────────────────────────────────────────────────
## Ноль — статичная картинка (все здания людей). Больше нуля — лента листается
## с этой частотой: так у хижины гоблинов идёт дым из трубы. Здание при этом
## остаётся неподвижным, к камере не доворачивается и от билборда не зависит
func sprite_fps() -> float:
	return 0.0

## Сдвиг фазы ленты. Берётся от номера узла, а не случайно: два прогона стенда
## обязаны давать одну картинку, а десять соседних хижин — разный такт дыма
func sprite_frame_phase() -> float:
	if sprite_fps() <= 0.0:
		return 0.0
	return float(get_instance_id() % 97) * 0.13

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
	quad.material = _BBUtil.make_static_material(tex, Color.WHITE, 0.5,
		sprite_fps(), sprite_frame_phase())
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
	# И ФОРМА ПОПАДАНИЯ ЛУЧА — ТУДА ЖЕ (см. _fit_pick_to_sprite)
	_fit_pick_to_sprite(tex, quad)

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
	# Те же три числа нужны кольцу на земле (см. ring_center / ring_radius).
	# Считаются здесь и один раз: обмер текстуры не бесплатен, а меняться ему
	# не с чего — рисунок у постройки один на всю её жизнь
	_draw_half_w = w * 0.5
	_draw_cx     = cx
	_draw_base_y = bottom * _BBUtil.V_STRETCH

# ═════════════════════════════════════════════════════════════════════════════
# ПО ЧЕМУ КЛИКАЕТ ИГРОК — ПО КАРТИНКЕ, А НЕ ПО КОРОБКЕ ИЗ КОНФИГА
#
# ЖАЛОБА ВЛАДЕЛЬЦА: «из-за смещения хитбоксов зданий мечники не доходят до
# дистанции удара, сбиваются в кучу и дёргаются».
#
# ЗАМЕР (стенд qa_pivot) объясняет всё. Постройка — ВЕРТИКАЛЬНЫЙ билборд, и
# рисуется он ВЫШЕ своей коробки в разы: у хижины гоблинов коробка 4×3.5×4, а
# нарисована она на 5.2 м вверх, да ещё домноженных на компенсацию наклона
# камеры (V_STRETCH ≈ 1.41), — то есть верхушка картинки стоит на 7.4 м, вдвое
# выше коробки. У замка та же история.
#
# Луч мыши идёт под 45°. Кликнув в ВЕРХНЮЮ половину картинки, игрок пускал луч
# НАД коробкой: тот пролетал мимо здания и втыкался в ЗЕМЛЮ перед ним, метрах в
# пяти. Приказ читался как «идти в точку», а не «атаковать здание»: отряд шёл
# в одну общую точку у стены, там сбивался в кучу и топтался, потому что все
# лезли на одно место. Ровно то, что видно на скриншоте.
#
# ЛЕЧИТСЯ ГЕОМЕТРИЕЙ, А НЕ ДОПУСКАМИ. Форма попадания подгоняется под ТУ ЖЕ
# непрозрачную часть рисунка, по которой уже строится рамка выделения
# (_fit_marker_to_sprite): что игрок видит — по тому и кликает.
#
# ПОЧЕМУ ПЛАСТИНА, А НЕ ВЫСОКАЯ КОРОБКА. Коробку пришлось бы тянуть и вверх, и
# в глубину; при камере в 45° луч, нацеленный в ЗЕМЛЮ ПЕРЕД зданием, проходил
# бы сквозь её нижнюю переднюю часть — и клик по пустой траве читался бы как
# клик по дому. Пластина стоит в плоскости самого спрайта, поэтому попадание в
# неё и попадание в рисунок — это одно и то же событие.
#
# КОЛЛИЗИЙ У ЗДАНИЯ БОЛЬШЕ НЕТ НИКАКИХ: у юнитов collision_mask = 0, размещение
# построек считается по build_size напрямую. Эта форма обслуживает РОВНО луч
# мыши (Constants.LAYER_BUILDINGS, см. SelectionManager._pick_at)
# ═════════════════════════════════════════════════════════════════════════════

## Толщина пластины попадания, метры. Не ноль: у бесконечно тонкой коробки луч
## под скользящим углом промахивается на численной погрешности
const PICK_SLAB_DEPTH := 0.5

func _fit_pick_to_sprite(tex: Texture2D, sprite_quad: QuadMesh) -> void:
	if _pick_shape == null or not is_instance_valid(_pick_shape):
		return
	var box := _pick_shape.shape as BoxShape3D
	if box == null or tex == null or sprite_quad == null:
		return
	var r: Rect2 = _BBUtil.opaque_rect(tex)
	# Доли кадра → метры. По вертикали UV растёт ВНИЗ (низ рисунка — 1 - r.end.y)
	var w: float = sprite_quad.size.x * r.size.x
	var bottom: float = sprite_quad.size.y * (1.0 - r.end.y)
	var top: float    = sprite_quad.size.y * (1.0 - r.position.y)
	var cx: float = sprite_quad.size.x * (r.position.x + r.size.x * 0.5 - 0.5)
	# ВЫСОТА БЕРЁТСЯ УЖЕ РАСТЯНУТОЙ. Компенсацию наклона камеры делает ШЕЙДЕР
	# (cyl_billboard, uniform v_stretch), и делает он это в МИРОВЫХ координатах,
	# от нижней кромки квада вверх. Значит нарисованное здание физически стоит
	# от bottom*V_STRETCH до top*V_STRETCH, и форма попадания обязана считаться
	# там же — иначе она снова окажется ниже картинки, только меньше
	var vs: float = _BBUtil.V_STRETCH
	box.size = Vector3(w, maxf((top - bottom) * vs, 0.2), PICK_SLAB_DEPTH)
	_pick_shape.position = Vector3(cx, (bottom + top) * 0.5 * vs, 0.0)
	_pick_shape.rotation = Vector3.ZERO

# ═════════════════════════════════════════════════════════════════════════════
# ГДЕ У ПОСТРОЙКИ «ОСНОВАНИЕ РИСУНКА»
#
# Кольцо приказа и кольцо наведения лежат ПЛАШМЯ на земле (см.
# SelectionDecalRenderer.building_ring_scale), и обе их величины брались из
# коробки конфига. У хижины гоблинов это давало круг радиусом 2.35 м под
# рисунком шириной 3.28 м, то есть кольцо было в полтора раза шире дома и
# наполовину торчало перед ним — «кольцо рисуется под спрайтом здания».
#
# Обе величины теперь считаются ОДИН РАЗ, при загрузке рисунка, и берутся из
# него же: центр — середина непрозрачной части, радиус — её полуширина.
# Постройка без спрайта (процедурная коробка) отвечает по-старому: там есть
# настоящий объём, и коробка для него правильна
# ═════════════════════════════════════════════════════════════════════════════

## Полуширина НАРИСОВАННОЙ постройки, метры. −1 — рисунка нет, спрашивать нечего
var _draw_half_w: float = -1.0
## Сдвиг середины рисунка от начала координат по X, метры
var _draw_cx: float = 0.0
## Высота нарисованного основания над грунтом, метры (уже с V_STRETCH)
var _draw_base_y: float = 0.0

## Куда класть кольцо на земле: середина основания рисунка
func ring_center() -> Vector3:
	if _draw_half_w < 0.0:
		return global_position
	return global_position + Vector3(_draw_cx, _draw_base_y, 0.0)

## Радиус кольца на земле, метры
func ring_radius() -> float:
	if _draw_half_w < 0.0:
		return maxf(build_size.x, build_size.z) * 0.5
	return _draw_half_w

func set_selected(value: bool) -> void:
	if selection_ring:
		selection_ring.visible = value
	# Флажок точки сбора показываем только у выделенного здания: иначе карта
	# зарастает флажками всех бараков сразу
	_rally_visible = value
	_refresh_rally_marker()
	_refresh_zone_marker()

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

## Обзор постройки в тумане (читает FogOfWar._collect_building_sources).
## Башня отвечает своим числом (TOWER_VISION), остальные — общим
func vision_radius() -> float:
	return _UCfgB.BUILDING_VISION

## Доля общей картинки пепелища (см. spawn_ruin): у башни рисунок узкий, и
## «домовые» руины в полный размер лежали бы шире самой башни
func ruin_scale() -> float:
	return _UCfgB.building_stat(building_id, "ruin_scale", 1.0)

## Своя картинка руины ("" — общая по расе) и «руину может отстроить любая
## сторона, и достаётся она отстроившему» (золотой рудник) — переопределяют
## наследники; читает spawn_ruin / GameManager.rebuild_ruin
func ruin_sprite_override() -> String:
	return ""

func ruin_any_faction() -> bool:
	return false

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
	# ДЕНЬГИ НЕ СПИСЫВАЮТСЯ ЗА ТОГО, КОГО НЕЧЕМ СОЗДАТЬ. Проверка стоит ПЕРЕД
	# spend(): раньше заказ принимался, оплачивался, доходил до _spawn_one и
	# там валился с «unknown unit» — игрок терял ресурсы и не получал бойца
	if not can_spawn(unit_name):
		if not _missing_warned.has(unit_name):
			_missing_warned[unit_name] = true
			push_warning("Building: найм '%s' отклонён — нет сцены юнита" % unit_name)
		return false
	# ── ЛИМИТ НАСЕЛЕНИЯ (дома, заказ 09.09.2026) ──────────────────────────
	# Проверка стоит ДО списания по той же причине, что и can_spawn: за
	# отклонённый заказ платить нельзя. Считает GameManager.pop_allows —
	# живые плюс заказанные, только у игрока, только в партии
	if not GameManager.pop_allows(faction, unit_name):
		return false
	if not ResourceManager.spend(faction, cost):
		return false
	var sz := clampi(squad_size, 1, MAX_SQUAD_SIZE)
	# ТЕМП НАЙМА ЗАВИСИТ ОТ СЛОЖНОСТИ, И ТОЛЬКО У ПРОТИВНИКА. Множитель
	# применяется ЗДЕСЬ, в момент постановки в очередь, а не при выходе отряда:
	# заказ обязан знать своё время сразу — по нему рисуется полоса готовности,
	# и пересчёт задним числом дёргал бы её у игрока на глазах
	var wait: float = _Diff.train_time(faction, build_time)
	# Цена едет ВМЕСТЕ с заказом: только так отмена по ПКМ может вернуть ровно
	# столько, сколько было списано, не пересчитывая её задним числом
	production_queue.append({"name": unit_name, "time": wait, "size": sz,
		"cols": squad_cols, "spacing": squad_spacing, "cost": cost.duplicate()})
	set_process(true)   # заказ есть — здание просыпается (см. _process)
	# ЗВУК ЗАКАЗА — ОДИН НА ВСЕ ЗДАНИЯ И ВСЕ РОДА ВОЙСК. Точка выбрана здесь, а
	# не на кнопках панели, ровно по той же причине, по какой здесь же стоит
	# списание ресурсов: заказ приходит не только с кнопки (ИИ, стенды,
	# горячие клавиши), а прозвучать он должен тогда и только тогда, когда
	# действительно принят и оплачен. Чужие заказы молчат — интерфейс наш
	if faction == Constants.FACTION_PLAYER:
		AudioManager.play_ui("order_unit")
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
			# ── ПОЛОСУ ВЫБИРАЕТ ЗАНЯТОСТЬ, А НЕ СЛЕПОЙ СЧЁТЧИК ──────────────
			# Разбор и замер — в _free_exit_lane. Коротко: счётчик уводил ОДИН
			# заказ в пустом поле на полторы-две полосы вбок от ворот
			# Колонны берём УЖЕ ВЫРОВНЕННЫМИ в квадрат: ровно с такими
			# _spawn_one посчитает шаг полосы (см. square_cols там же)
			var lane: int = _free_exit_lane(sid, sz, square_cols(sz, cols), sp)
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
			# ── МЕСТО У ФЛАЖКА — ТОЖЕ ОДНО НА ЗАКАЗ ─────────────────
			# Жалоба владельца со скриншотом: «при выходе из бараков на
			# точку сбора отряд разделяется на два оторванных куска».
			# Точка флажка (r_pos) снималась сюда уже давно и по той же
			# причине — но СВОБОДНОЕ МЕСТО возле флажка считалось ВНУТРИ
			# _spawn_one, то есть НА КАЖДОГО БОЙЦА ОТДЕЛЬНО. А отряд выходит
			# шеренга за шеренгой, растягиваясь на секунды: между первой и
			# последней шеренгой мир успевает поменяться (чужой отряд пришёл
			# или ушёл), и free_squad_spot честно отвечал ДРУГОЕ место. Одна
			# половина отряда шла к первому ответу, вторая ко второму — вот
			# и «два оторванных куска». Один заказ — один отряд — ОДНО место
			var r_spot: Vector3 = r_pos
			if r_has:
				var want_r: float = sqrt(float(maxi(sz, 1))) * 0.5 * GameManager.SQUAD_SPOT_SPACING + 0.4
				r_spot = GameManager.free_squad_spot(sid, r_pos, {}, want_r)
			for i in range(sz):
				_pending_spawns.append({
					"name": unit_name, "idx": i, "cols": cols, "spacing": sp,
					"squad": sid, "total": sz, "lane": lane,
					"has_rally": r_has, "rally": r_pos, "spot": r_spot,
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
			int(job.get("total", 1)), bool(job.get("has_rally", false)), r_pos,
			job.get("spot", r_pos))
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
const GATE_CLEARANCE := 0.5    # 0.9 → 0.5: площадка вплотную к стене (заказ 10.09.2026)

## Сколько колонн даёт КВАДРАТНЫЙ строй на `total` бойцов.
## Общая для всех точка: тем же расчётом пользуются пополнение гарнизона и
## перестроение, иначе отряд менял бы пропорции после каждой потери.
## `fallback` берётся, когда размер неизвестен (одиночный найм)
static func square_cols(total: int, fallback: int = 4) -> int:
	if total <= 1:
		return maxi(fallback, 1)
	return maxi(int(ceil(sqrt(float(total)))), 1)

## Единичный вектор «на фронт» — от постройки к середине карты.
## ЭТО НЕ НАПРАВЛЕНИЕ ВОРОТ (см. facade_dir): им пользуется ИИ, чтобы понять,
## куда обращена база, а ворота теперь привязаны к рисунку, а не к карте
func front_dir() -> Vector3:
	var d := -global_position
	d.y = 0.0
	if d.length() < 1.0:
		return Vector3.BACK
	return d.normalized()

# ═════════════════════════════════════════════════════════════════════════════
# ТОЧКА ВЫХОДА — УЗЕЛ SpawnPoint У НАРИСОВАННЫХ ДВЕРЕЙ
# ═════════════════════════════════════════════════════════════════════════════
# ПОЧЕМУ БОЙЦЫ ВЫХОДИЛИ СБОКУ. Причина не в пивоте: пивот здания как раз в
# порядке — спрайт стоит нижней кромкой на грунте ровно в своей точке
# (см. _maybe_load_building_sprite). Дело было в РАССОГЛАСОВАНИИ ДВУХ ФАСАДОВ:
#
#   • картинка здания прибита фасадом строго на мировой +Z и с камерой не
#     связана вовсе (make_static_material, поворот узла нулевой) — то есть
#     нарисованная дверь ВСЕГДА обращена к нижнему краю экрана;
#   • а ворота считались как front_dir() — «от постройки к середине карты», то
#     есть в произвольную сторону, зависящую от того, где здание построено.
#
# База игрока стоит в углу, значит front_dir смотрит по диагонали — и отряд
# выходил из угла/боковой стены, ровно как на скриншоте с копейщиками.
# Разъехались две стороны, каждая из которых по отдельности «правильная»;
# найти это можно было только сопоставив их между собой.
#
# ТЕПЕРЬ ворота — это НАСТОЯЩИЙ УЗЕЛ Marker3D с именем SpawnPoint, стоящий у
# нарисованных дверей, и весь спавн идёт строго через его global_position.
# (В задании был Marker2D — но игра трёхмерная, и двумерный маркер тут просто
# не имеет мировой точки, которую можно отдать бойцу.)
#
# Здания в этом проекте собираются кодом, а не сценами (руками написаны только
# MainMenu.tscn и Main.tscn), поэтому узел создаётся в _ready. Смысл требования
# от этого не меняется: точка выхода стала ОДНИМ ЯВНЫМ МЕСТОМ, которое видно в
# дереве сцены, можно подвинуть одной строкой и увидеть в отладчике — вместо
# формулы, размазанной по трём файлам.
const SPAWN_POINT_NAME := "SpawnPoint"

## Узел ворот. Создаётся в _ready, живёт под зданием, ездит вместе с ним
var spawn_point: Marker3D = null

## КУДА СМОТРИТ НАРИСОВАННЫЙ ФАСАД. Мировой +Z и ничего больше: спрайт
## постройки зафиксирован именно так (см. _maybe_load_building_sprite), а
## процедурная коробка симметрична и своего «переда» не имеет вовсе
func facade_dir() -> Vector3:
	return Vector3.BACK

## Насколько точка выхода вынесена вперёд от центра здания.
## По умолчанию — до передней стены плюс зазор; замок переопределяет (у него
## ворота в надвратной башне, см. Castle.GATE_DISTANCE)
## ── ВОРОТА ЛЕЖАТ НА ПЕРИМЕТРЕ РИСУНКА, А НЕ ЗА НИМ ─────────────────────────
## Жалоба владельца: «спаун рабочих происходит не у стен здания, а в воздухе
## ЗА кругом». Так и было: вынос считался от КОРОБКИ ИЗ КОНФИГА, а кольцо на
## земле — от НАРИСОВАННОГО основания (см. ring_radius), и коробка почти всегда
## крупнее рисунка. Боец честно вставал по коробке, то есть снаружи кольца, на
## пустой траве.
##
## Берём МЕНЬШЕЕ из двух: дальше периметра рисунка ворота не уезжают никогда, а
## ближе к центру, чем сама коробка, — тем более (иначе боец появлялся бы
## внутри постройки). Постройка без рисунка отвечает по-старому: у неё есть
## настоящий объём, и коробка для неё правильна
func gate_depth() -> float:
	var by_box: float = build_size.z * 0.5
	if _draw_half_w >= 0.0:
		return minf(by_box, _draw_half_w) + GATE_CLEARANCE
	return by_box + GATE_CLEARANCE

func _ensure_spawn_point() -> void:
	if spawn_point != null and is_instance_valid(spawn_point):
		return
	spawn_point = Marker3D.new()
	spawn_point.name = SPAWN_POINT_NAME
	add_child(spawn_point)
	# Стенд может собрать здание вне дерева — тогда add_child промолчит, а
	# _gate_position() уйдёт на запасной путь (см. там же)
	if spawn_point.get_parent() != self:
		spawn_point = null

## Обновить положение ворот. Дёшево и идемпотентно, поэтому зовётся из
## _gate_position каждый раз: build_size может быть выставлен наследником уже
## после _ready, а здание — переехать (стройплощадка → готовое здание)
func _face_front() -> void:
	spawn_offset = facade_dir() * gate_depth()
	# ── ВОРОТА ПРОТИВ СЕРЕДИНЫ РИСУНКА, А НЕ ПРОТИВ НАЧАЛА КООРДИНАТ ────────
	# Непрозрачная часть кадра нередко смещена внутри самого кадра, и середина
	# постройки на экране не совпадает с её узлом. Поправка та же самая, по
	# которой кладётся кольцо на земле (ring_center) — иначе ворота и кольцо
	# описывают разные «середины» одного и того же дома, а рабочий выходит
	# сбоку от нарисованных дверей
	if _draw_half_w >= 0.0:
		spawn_offset.x += _draw_cx
	if spawn_point != null and is_instance_valid(spawn_point):
		spawn_point.position = spawn_offset

func _gate_position() -> Vector3:
	_face_front()
	# ЧИТАЕМ У УЗЛА, а не складываем позицию с офсетом: если маркер кто-то
	# подвинет (в редакторе, в стенде, в будущей сцене здания), спавн обязан
	# поехать за ним — иначе «точка выхода — это узел» остаётся на словах.
	# Запасной путь — на случай здания, собранного вне дерева сцены: у такого
	# маркера нет мировой точки, и читать её значило бы получить локальную
	if spawn_point != null and is_instance_valid(spawn_point) \
			and spawn_point.is_inside_tree():
		return spawn_point.global_position
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
## ── ПЛОЩАДКА ВПЛОТНУЮ К ЗДАНИЮ (заказ 10.09.2026 по скриншотам) ────────────
## Было 4.0 — отряд отходил от ворот на четыре метра, и между стеной и первой
## шеренгой лежала пустая трава. Теперь первая шеренга встаёт в метре от
## ворот; проём при этом свободен (rally_zone начинается за полшага до неё)
const SQUAD_EXIT_DISTANCE := 1.0
## Глубина площадки сбора, м: все ряды полос выхода укладываются в неё
## (exit_lanes / _lane_depth_step), у здания она ОДНА и та же при любом отряде
const ZONE_DEPTH := 18.0

## ── ОДИНОЧКА ВЫХОДИТ У САМИХ ВОРОТ ─────────────────────────────────────────
## Жалоба владельца со скриншотом: «точка спавна выходящих юнитов у Крепости и
## Бараков находится далеко внизу здания, а не у ворот».
##
## Четыре метра выше — это отход ОТРЯДА, и он там нужен: пятьдесят человек
## строятся шеренгами и обязаны освободить дверной проём следующему заказу.
## Рабочий же выходит ПООДИНОЧКЕ и никакого прохода не занимает — а четыре
## метра ему доставались те же самые. Вместе с выносом самих ворот
## (gate_depth, у замка это ещё пять метров) рабочий возникал метрах в девяти
## ниже здания, посреди пустой травы: ровно то, что на скриншоте.
##
## Число выведено из шага россыпи, а не подобрано: одиночки расходятся
## спиралью с шагом SINGLE_AGENT_SPREAD, и полтора шага — это ровно «встал за
## порогом, не мешая следующему»
## 1.5 → 0.8 шага (10.09.2026): рабочий выходит у самой стены замка
const SINGLE_AGENT_EXIT_DISTANCE := SINGLE_AGENT_SPREAD * 0.8
## Запас между рядами площадки соседних отрядов, метры (сверх глубины строя).
## 4.0 → 1.0 (10.09.2026): ряды идут вплотную, площадка укладывается в ZONE_DEPTH
const EXIT_LANE_GAP := 1.0

## СКОЛЬКО ПОЛОС ВЫХОДА СУЩЕСТВУЕТ ВСЕГО — и почему их число обязано быть
## конечным. Полосы разводят отряды, выходящие из ОДНИХ ворот ОДНОВРЕМЕННО,
## чтобы они не толкались в дверях; дальше этого их работа не идёт.
## Счётчик же рос без предела и никогда не сбрасывался, а полоса N уводит точку
## сбора на (N+1)/2 × lane_step (~8.5 м) вбок. Пятнадцатый заказ из одного
## барака собирался метрах в шестидесяти от ворот, тридцатый — за краем карты,
## у леса: игрок видел, как часть найма выходит из дверей, а часть возникает на
## отшибе и бежит оттуда к строю.
## Ровно этот же счётчик уже ловили на НАЗНАЧЕННОЙ точке сбора (qa_rally2 F8) и
## обезвредили только там — на пути «без флажка» он остался жив.
## Пять полос дают разброс ±2 × lane_step (~±14 м у отряда в 20 человек) —
## этого хватает, чтобы одновременный найм не встал друг в друга, и мало, чтобы
## уйти с карты.
##
## ОБНУЛЯТЬ СЧЁТЧИК НА ПРОСТОЕ ЗДАНИЯ НЕЛЬЗЯ, и это проверено: такая версия
## возвращала следующий заказ на полосу 0, а предыдущий отряд всё ещё стоял
## там, где собрался, — qa_rally2 E7/E8 сразу показали наложение (центры в
## 0.71 м, 17 бойцов вплотную к чужим). Цикл сам по себе делает всё, что от
## полос требуется: пять подряд идущих заказов гарантированно расходятся, а
## шестой встаёт на место первого, который к тому времени давно уведён.
const EXIT_LANES := 5

## Счётчик полос выхода: последний рубеж, когда ВСЕ полосы заняты.
## Крутится по кругу внутри EXIT_LANES и потому ограничен сверху
var _exit_lane: int = 0

## ── ПОЛОСУ ВЫБИРАЕТ ЗАНЯТОСТЬ, А НЕ СЛЕПОЙ СЧЁТЧИК ─────────────────────────
## Жалоба владельца со скриншотом: «точка спауна находится не у ворот, а сильно
## ниже И ПРАВЕЕ — прямо в чистом поле». Правее её уводили именно полосы.
##
## Счётчик увеличивался НА КАЖДЫЙ ЗАКАЗ и не смотрел по сторонам вовсе. Второй
## наём из замка уходил на полосу 1, третий на 2 — а шаг полосы у отряда в
## шестьдесят копейщиков ≈ 9.4 м, то есть третий отряд собирался в ДЕВЯТНАДЦАТИ
## метрах вбок от ворот, посреди пустого поля, даже когда рядом не было ни души.
## Полосы заведены против ОДНОВРЕМЕННОГО найма («не толкаться в дверях»), и
## только этот случай они и должны обслуживать.
##
## СБРАСЫВАТЬ СЧЁТЧИК НА ПРОСТОЕ ЗДАНИЯ УЖЕ ПРОБОВАЛИ И ОТКАТИЛИ (qa_rally2
## E7/E8): «здание простаивает» не значит «место у ворот свободно» — прошлый
## отряд мог всё ещё стоять там, где собрался. Поэтому спрашиваем не время, а
## СВОЙСТВО: стоит ли кто-нибудь на этой полосе. Ровно тот же приём и та же
## причина, что у GameManager.free_squad_spot.
##
## ЗАНЯТОСТЬ СЧИТАЕТСЯ ПО ДВУМ ИСТОЧНИКАМ, и второй легко упустить. Заказ
## выходит из дверей по два бойца за кадр: пока он не вышел, на его полосе
## физически НИКОГО НЕТ, и второй заказ, отданный в тот же кадр, честно нашёл бы
## её свободной — то самое наложение, ради которого полосы и придуманы. Поэтому
## полоса считается занятой и тогда, когда её держит ещё не вышедшая заявка
func _free_exit_lane(squad_id: int, total: int, cols: int, spacing: float) -> int:
	var want: float = sqrt(float(maxi(total, 1))) * 0.5 * spacing + 1.0
	var n_l: int = exit_lanes(total, cols, spacing)
	for lane in range(n_l):
		if not _lane_busy(lane, total, cols, spacing, want):
			_lane_owner[lane] = squad_id
			return lane
	# Все полосы заняты — крутим счётчик по кругу, как и раньше
	var fallback: int = _exit_lane % n_l
	_exit_lane = (_exit_lane + 1) % n_l
	_lane_owner[fallback] = squad_id
	return fallback

## ── ЗАНЯТОСТЬ ПОЛОСЫ СЧИТАЕТСЯ ПО ТРЁМ ПРИЗНАКАМ, И НИ ОДИН НЕ ЛИШНИЙ ───────
## 1. ЗАЯВКА, КОТОРАЯ ЕЩЁ НЕ ВЫШЛА. Отряд заводится в реестре ПУСТЫМ, а бойцов
##    ему доставляют следующими кадрами (см. _drain_pending_spawns): второй
##    заказ того же кадра не нашёл бы на полосе ни души.
## 2. ПРОШЛЫЙ ХОЗЯИН, ЕЩЁ НЕ УШЁДШИЙ ОТ ДВЕРЕЙ. ГЕОМЕТРИЕЙ ЭТО НЕ УЗНАТЬ, и
##    первая версия правки на этом и споткнулась: отряд ВЫХОДИТ У ВОРОТ и лишь
##    потом идёт на своё место, а ворота у всех полос общие — по точке сбора
##    полоса выглядела свободной, пока свежий отряд ещё топтался в дверях.
##    Стенд поймал это немедленно (qa_spawnlane B1: разрыв между соседними
##    заказами 0.00 м). Чья полоса — знает только сам заказ, поэтому хозяин
##    ЗАПОМИНАЕТСЯ.
## 3. ПОСТОРОННИЙ НА МЕСТЕ СБОРА. Хозяина у полосы может не быть вовсе, а место
##    занимать чужой отряд, которого игрок туда привёл сам
func _lane_busy(lane: int, total: int, cols: int, spacing: float,
		want: float) -> bool:
	if _lane_claimed(lane):
		return true
	if _lane_held(lane, total, cols, spacing):
		return true
	return _lane_occupied(_lane_centre(lane, total, cols, spacing), want)

## Полоса → id отряда, который её занял последним
var _lane_owner: Dictionary = {}

## Топчется ли хозяин полосы всё ещё у дверей.
## СОСТАВ ЧИТАЕТСЯ НАПРЯМУЮ, а не через squad_members(): тот не читатель, он
## РАСПУСКАЕТ опустевший отряд прямо в геттере — а сюда мы приходим ровно тогда,
## когда отряд только заведён и ещё пуст (см. CLAUDE.md, раздел про марш)
func _lane_held(lane: int, total: int, cols: int, spacing: float) -> bool:
	var sid_v: Variant = _lane_owner.get(lane)
	if sid_v == null:
		return false
	var sq: Variant = GameManager.squads.get(int(sid_v))
	if sq == null:
		_lane_owner.erase(lane)
		return false
	var gate := _gate_position()
	# «Ушёл от дверей» — это дальше собственного места сбора и дальше шага
	# полосы: ближе он всё ещё мешает следующему заказу выйти
	var clear: float = SQUAD_EXIT_DISTANCE + _lane_step(total, cols, spacing)
	for m in ((sq as Dictionary)["members"] as Array):
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		if u.global_position.distance_to(gate) <= clear:
			return true
	_lane_owner.erase(lane)
	return false

## Держит ли полосу заявка, которая ещё не вышла из дверей
func _lane_claimed(lane: int) -> bool:
	for job in _pending_spawns:
		var j: Dictionary = job
		# Заказ с назначенной точкой сбора полосу не занимает: он к ней и не
		# идёт (см. _spawn_one, ветка r_has)
		if bool(j.get("has_rally", false)):
			continue
		if int(j.get("lane", 0)) == lane:
			return true
	return false

## Стоит ли кто-то из своих на этом месте
func _lane_occupied(centre: Vector3, radius: float) -> bool:
	for n in GameManager.unit_grid.query_radius(centre, radius):
		var u := n as Unit
		if u != null and not u.is_dead() and u.faction == faction:
			return true
	return false

## Шаг между полосами. Считается по РЕАЛЬНОМУ пятну отряда, а не по ширине
## строя: 50 бойцов в 5 колонн формально занимают 1.75 м, но пока отряд идёт к
## точке сбора, он расплывается в пятно примерно √n × 0.7 м
func _lane_step(total: int, cols: int, spacing: float) -> float:
	var blob: float = sqrt(float(maxi(total, 1))) * 0.7
	return maxf(float(cols) * spacing, blob) + EXIT_LANE_GAP

## Точка на оси полосы, вынесенная от ворот вперёд на `forward` метров.
## forward = 0 — вход в полосу прямо в дверях, forward = SQUAD_EXIT_DISTANCE —
## куда встанет середина вышедшего отряда
func _lane_point(lane: int, forward: float, total: int, cols: int,
		spacing: float) -> Vector3:
	var exit_dir := spawn_offset
	exit_dir.y = 0.0
	if exit_dir.length() < 0.01:
		exit_dir = Vector3.BACK
	exit_dir = exit_dir.normalized()
	var side := Vector3(-exit_dir.z, 0.0, exit_dir.x)
	var sh: Vector2 = _lane_shift(lane, total, cols, spacing)
	return _gate_position() + exit_dir * (forward + sh.x) + side * sh.y

## ── ПОЛОСА УХОДИТ ВПЕРЁД РОВНО НАСТОЛЬКО ЖЕ, НАСКОЛЬКО ВБОК ────────────
## Смещение полосы от точки ворот: x — вперёд по фасаду, y — вбок. Считается
## ОДИН раз здесь и читается обоими концами: раскладкой заказа (_spawn_one) и
## проверкой занятости (_lane_centre). Разъехаться они не могут — та же
## причина, по которой одной функцией считается сам шаг полосы (_lane_step).
##
## ЖАЛОБА ВЛАДЕЛЬЦА (скриншот со стрелками): «юниты спавнятся далеко внизу
## справа по диагонали, а не прямо перед дверью». Воспроизведено числом
## (зонд qa_gate, блок «четыре заказа из барака»): четвёртый заказ вставал
## в 13.89 м ВБОК при 4.47 м вперёд, то есть под 72° к фасаду.
##
## ПРИЧИНА НЕ В ЗАНЯТОСТИ ПОЛОС — все четыре отряда стояли на своих местах
## честно. Веер РОС ТОЛЬКО ВБОК: вперёд у каждой полосы было одно и то же
## SQUAD_EXIT_DISTANCE = 4 м, а вбок прибавлялось по _lane_step (7.13 м у
## барака) — уже ПЕРВАЯ боковая полоса уходила вбок вдвое дальше, чем вперёд.
##
## Теперь полосы лежат КЛИНОМ В 45°: тот же шаг прибавляется и по фасаду, и
## ни одна полоса не оказывается сбоку дальше, чем впереди. «Перед воротами»
## выполняется ПО ПОСТРОЕНИЮ, а не подбором числа. Боковой разнос полос не
## тронут вовсе (его стережёт qa_spawnlane A1/A2/B1), а соседние заказы
## расходятся теперь ещё и по глубине.
## ── ПОЛОСЫ РАСХОДЯТСЯ ВГЛУБЬ, А НЕ ВБОК (заказ владельца, 31.08.2026) ────
## ЭТО РАЗВОРОТ, И ОН ТРЕТИЙ ПО СЧЁТУ У ОДНОЙ И ТОЙ ЖЕ ЖАЛОБЫ. История:
##   1. полосы расходились ЧИСТО ВБОК — четвёртый заказ вставал в 13.89 м
##      вбок при 4.47 м вперёд, под 72° к фасаду;
##   2. добавили тот же шаг вперёд — вышел клин в 45°, замер 37°;
##   3. владелец снова: «спавн со смещением по диагонали вправо-вниз, а не
##      ровно перед воротами». И он прав: даже под 37° второй заказ уходит
##      на СЕМЬ метров вбок (замер qa_gate), а четвёртый на четырнадцать —
##      это уже не «у дверей», это соседний двор.
##
## ПОЧЕМУ ВБОК ВООБЩЕ РАСХОДИЛИСЬ. Полосы заведены против ОДНОВРЕМЕННОГО
## найма: два заказа не должны встать друг на друга. Разносить их вбок надо
## было на ШИРИНУ отряда (у барака 7.13 м) — оттого и семь метров.
##
## ВГЛУБЬ ДЕШЕВЛЕ, И ЭТО АРИФМЕТИКА, А НЕ ВКУС. Разносить в глубину надо на
## ГЛУБИНУ отряда, а она у строя в пять колонн ВТРОЕ МЕНЬШЕ ширины: двадцать
## бойцов это 5 колонн по 4 шеренги. То есть очередь перед воротами и
## компактнее веера, и целиком укладывается в ту самую полосу перед дверью.
## Боковой составляющей нет вовсе — «перед воротами» выполняется по
## построению, а не подбором угла.
func _lane_shift(lane: int, total: int, cols: int, spacing: float) -> Vector2:
	return Vector2(float(lane) * _lane_depth_step(total, cols, spacing), 0.0)

## Шаг полос В ГЛУБИНУ: глубина строя плюс тот же просвет, что был у бокового
## шага. Считается ОДНОЙ функцией с тем местом, где полоса выбирается, — иначе
## проверка занятости судила бы об одних полосах, а отряд выходил на другие
## (та же причина, что у _lane_step)
## ── РЯДЫ ПЛОЩАДКИ УКЛАДЫВАЮТСЯ В ZONE_DEPTH (10.09.2026) ───────────────────
## Прежний шаг «не теснее бокового 7.13 м» уводил пятый заказ на тридцать
## метров от ворот; владелец попросил площадку в 18 м вплотную к зданию.
## Сколько рядов помещается — считается от глубины СТРОЯ: сколько отрядов
## этого размера встанут друг за другом с просветом EXIT_LANE_GAP. Потолок —
## EXIT_LANES (его читают стенды), пол — два ряда, чтобы одновременные заказы
## всё ещё расходились. Ряды растягиваются на всю глубину площадки: у мелкого
## отряда шаг больше просвета, у крупного — ровно просвет
func exit_lanes(total: int, cols: int, spacing: float) -> int:
	var rows: int = int(ceil(float(maxi(total, 1)) / float(maxi(cols, 1))))
	var own: float = float(rows) * spacing
	var fit: int = int(floor((ZONE_DEPTH - SQUAD_EXIT_DISTANCE - own) / (own + EXIT_LANE_GAP))) + 1
	return clampi(fit, 2, EXIT_LANES)

func _lane_depth_step(total: int, cols: int, spacing: float) -> float:
	var rows: int = int(ceil(float(maxi(total, 1)) / float(maxi(cols, 1))))
	var own: float = float(rows) * spacing
	var n_l: int = exit_lanes(total, cols, spacing)
	var span: float = ZONE_DEPTH - SQUAD_EXIT_DISTANCE - own
	return maxf(own + EXIT_LANE_GAP, span / float(maxi(n_l - 1, 1)))

## Куда встанет середина отряда, вышедшего на этой полосе
func _lane_centre(lane: int, total: int, cols: int, spacing: float) -> Vector3:
	return _lane_point(lane, SQUAD_EXIT_DISTANCE, total, cols, spacing)

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

# ── РАЗМЕРЫ МАРКЕРА ТОЧКИ СБОРА ──────────────────────────────────────────────
# Заказ владельца: флаг вдвое меньше, тёмно-красный, с раздвоенным язычком;
# кольцо — тонкое и аккуратное. Все числа ниже — ровно половина прежних, так что
# «на 50%» здесь буквально: древко 2.6 → 1.3, полотнище 1.1×0.7 → 0.55×0.35.
const RALLY_POLE_H    := 1.30
const RALLY_POLE_R    := 0.0275
const RALLY_FLAG_W    := 0.55
## Шаг россыпи одиночных агентов (рабочих) при выходе из здания, метры.
## Выведен из строевого интервала: плотнее — слипнутся, шире — расползутся
const SINGLE_AGENT_SPREAD := 0.7    # 0.9 → 0.7 (10.09.2026): россыпь теснее, у стены

const RALLY_FLAG_H    := 0.35
## Глубина выреза «ласточкина хвоста» в долях ширины полотнища
const RALLY_FLAG_NOTCH := 0.38
## Кольцо: радиус тоже вдвое меньше прежнего (было 0.9-1.15), а ЛИНИЯ намеренно
## тонкая — 4 см против прежних 25. Толстый обод на земле читался как блин
const RALLY_RING_R    := 0.54
const RALLY_RING_W    := 0.04
const RALLY_DARK_RED  := Color(0.52, 0.07, 0.09)
## Кольцо чуть светлее полотнища: тем же тоном тонкая линия по траве не читается
const RALLY_RING_COLOR := Color(0.74, 0.15, 0.15, 0.85)

## ВЫМПЕЛ С РАЗДВОЕННЫМ ЯЗЫЧКОМ (swallowtail). QuadMesh такую форму не даёт в
## принципе, поэтому полотнище собирается вручную из трёх треугольников:
## прямоугольник, у которого со стороны развевания вырезан клин.
##
##   (0,+h)┌──────────────┐(w,+h)
##         │           ╱
##         │      (w-n,0)      ← вершина выреза
##         │           ╲
##   (0,-h)└──────────────┘(w,-h)
##
## Начало координат — НА ДРЕВКЕ (x = 0), полотнище уходит в +X. Смещение вбок
## вшито прямо в вершины, а не задано center_offset, как было у квада: у
## произвольного ArrayMesh такого поля нет, зато локальные координаты
## разворачиваются билбордом точно так же — полотнище остаётся у древка с любого
## ракурса камеры и не разрезается непрозрачным цилиндром пополам
func _build_rally_flag_mesh() -> ArrayMesh:
	var w: float = RALLY_FLAG_W
	var h: float = RALLY_FLAG_H * 0.5
	var n: float = RALLY_FLAG_W * RALLY_FLAG_NOTCH
	var v := PackedVector3Array([
		# верхняя половина: древко-верх, вершина выреза, край-верх
		Vector3(0.0, h, 0.0), Vector3(w - n, 0.0, 0.0), Vector3(w, h, 0.0),
		# нижняя половина
		Vector3(0.0, -h, 0.0), Vector3(w, -h, 0.0), Vector3(w - n, 0.0, 0.0),
		# перемычка у древка
		Vector3(0.0, h, 0.0), Vector3(0.0, -h, 0.0), Vector3(w - n, 0.0, 0.0),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Построить маркер: древко + вымпел + кольцо на земле. Всё процедурно —
## отдельной картинки под это в паке нет
func _build_rally_marker() -> Node3D:
	var root := Node3D.new()
	root.name = "RallyMarker"
	# Кольцо на земле: видно, даже если флажок заслонён деревом
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = RALLY_RING_R - RALLY_RING_W * 0.5
	tor.outer_radius = RALLY_RING_R + RALLY_RING_W * 0.5
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.albedo_color   = RALLY_RING_COLOR
	rm.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.position.y = 0.06
	root.add_child(ring)
	# Древко
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RALLY_POLE_R
	cyl.bottom_radius = RALLY_POLE_R
	cyl.height = RALLY_POLE_H
	pole.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.36, 0.26, 0.14)
	pole.material_override = pm
	pole.position.y = RALLY_POLE_H * 0.5
	root.add_child(pole)
	# Полотнище: билборд, чтобы вымпел был виден с любого ракурса
	var flag := MeshInstance3D.new()
	flag.mesh = _build_rally_flag_mesh()
	var fm := StandardMaterial3D.new()
	fm.albedo_color    = RALLY_DARK_RED
	fm.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode  = BaseMaterial3D.BILLBOARD_FIXED_Y
	fm.cull_mode       = BaseMaterial3D.CULL_DISABLED
	flag.material_override = fm
	# Полотнище висит у верхушки древка: его центр по высоте на пол-полотнища
	# ниже среза, иначе верхний угол торчит над палкой
	flag.position = Vector3(0.0, RALLY_POLE_H - RALLY_FLAG_H * 0.5, 0.0)
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
		r_has: bool = false, r_pos: Vector3 = Vector3.ZERO,
		r_spot: Vector3 = Vector3.INF) -> void:
	# Сцена уже в памяти (см. PRELOAD_SCENES) — instantiate() без чтения диска.
	# Спрайт-шиты юнита тоже кэшированы (SpriteSheetParser._frames_cache),
	# поэтому _ready() второго и последующих бойцов диск не трогает.
	var scene: PackedScene = PRELOAD_SCENES.get(unit_name)
	if scene == null:
		# МЯГКИЙ ПРОПУСК, А НЕ ОШИБКА. Заказ уже оплачен и снят с очереди, так
		# что валиться здесь бессмысленно — бойца всё равно не будет. Жалуемся
		# ОДИН РАЗ на тип: заказ выходит по бойцу за раз, и push_error на
		# каждого забивал консоль десятками одинаковых строк.
		# Чтобы сюда вообще не попадать, найм такого бойца не предлагается —
		# см. can_spawn() и его проверку в очереди заказов
		if not _missing_warned.has(unit_name):
			_missing_warned[unit_name] = true
			push_warning("Building: нет сцены для юнита '%s' — заказ пропущен"
				% unit_name)
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
	# ── ОДИНОЧКИ НЕ СТРОЯТСЯ ШЕРЕНГОЙ ──────────────────────────────────────
	# Вопрос владельца: «почему рабочие вообще имеют логику отрядного
	# построения?». Отряд у рабочего — УЧЁТНАЯ единица (иначе его не выделить и
	# не посчитать в панели), а вот боевая раскладка ему досталась просто
	# потому, что здесь спрашивали squad_id и никогда — что это за отряд.
	# Отсюда и «рабочие выстраиваются в боевую шеренгу через полкарты».
	#
	# Одиночкам раскладку заменяем россыпью по спирали золотого угла вокруг
	# точки сбора: плотно, без шеренг и без полос выхода
	var single: bool = squad_id > 0 and GameManager.squad_is_single_agent(squad_id)
	var col      := idx % cols
	var row      := idx / cols
	if single:
		col = 0
		row = 0
	# Ряд в строю: копейщики первых двух шеренг выходят с копьями наперевес
	unit.formation_row = row
	var offset_x := (col - (cols - 1) * 0.5) * spacing
	if single:
		# Спираль золотого угла: равномерное заполнение диска при любом числе
		var ang: float = TAU * 0.381966 * float(idx)
		var rr: float = SINGLE_AGENT_SPREAD * sqrt(float(idx))
		offset_x = cos(ang) * rr
	# ── ГЛУБИНА СЧИТАЕТСЯ ОТ ДАЛЬНЕЙ ШЕРЕНГИ, А НЕ ОТ ВОРОТ ─────────────────
	# Отряд выходит шеренга за шеренгой (см. _drain_pending_spawns), и раньше
	# шеренга, вышедшая ПЕРВОЙ, вставала БЛИЖЕ всех к воротам. Каждая следующая
	# была обязана пройти сквозь уже стоящих, чтобы попасть глубже в поле, —
	# отряд буквально выворачивался наизнанку, а последняя вышедшая шеренга
	# оказывалась впереди строя. Это и есть жалоба «первая шеренга проходит
	# сквозь весь отряд и становится последней».
	#
	# Теперь наоборот: первым вышедшим достаётся САМОЕ ДАЛЬНЕЕ место, и они
	# идут туда по пустой земле. Каждая следующая шеренга останавливается ближе
	# предыдущей, никого не пересекая. Порядок шеренг в строю при этом прежний
	# (formation_row не меняется): первым вышел — первым и стоит
	var rows_total: int = int(ceil(float(maxi(total, 1)) / float(cols)))
	var offset_z: float = float(rows_total - 1 - row) * spacing
	if single:
		# Вторая координата той же спирали (см. offset_x выше)
		var ang2: float = TAU * 0.381966 * float(idx)
		offset_z = sin(ang2) * SINGLE_AGENT_SPREAD * sqrt(float(idx))
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
	# Шаг полосы — ОДНОЙ ФУНКЦИЕЙ с тем местом, где полоса ВЫБИРАЕТСЯ
	# (см. _lane_step): считай его здесь по-своему, и проверка занятости судила
	# бы об одних полосах, а отряд выходил бы на другие
	var lane_sh: Vector2 = _lane_shift(lane, total, cols, spacing)
	# Точка сбора отряда: ОТ ворот на SQUAD_EXIT_DISTANCE, строй сохраняется
	# Полосы выхода разводят ОТРЯДЫ, чтобы они не толкались в дверях. Одиночкам
	# полоса не нужна: они и так расходятся спиралью
	if single:
		lane_sh = Vector2.ZERO
	var out_dist: float = SINGLE_AGENT_EXIT_DISTANCE if single else SQUAD_EXIT_DISTANCE
	var rally: Vector3 = gate + exit_dir * (out_dist + lane_sh.x + offset_z) \
		+ side * (offset_x + lane_sh.y)
	# Место на ПЛОЩАДКЕ — по рядам полос, независимо от флажка (хак №3)
	var zone_pos: Vector3 = rally
	var zxz: Vector2 = GameManager.clamp_to_map(zone_pos.x, zone_pos.z)
	zone_pos.x = zxz.x
	zone_pos.z = zxz.y
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
		# (замер qa_rally2, F8). К флажку идут все — строем, но в одну точку.
		#
		# ── НО НЕ НА ГОЛОВЫ ТЕМ, КТО УЖЕ ТАМ СТОИТ ─────────────────────────
		# Жалоба владельца: новобранцы идут на точку сбора, где уже стоят
		# войска, и отряды накладываются. Флажок один, а отрядов к нему приходит
		# сколько угодно — сдвигать надо не флажок, а МЕСТО отряда возле него
		# (см. GameManager.free_squad_spot). Габарит передаём заказанный, а не
		# наличный: отряд ещё выходит по одному, и по наличному составу каждый
		# следующий боец получал бы своё место
		# МЕСТО УЖЕ ПОСЧИТАНО — ОДИН РАЗ НА ЗАКАЗ, в queue-ветке _process.
		# Здесь его только ЧИТАЮТ: считать свободное место на КАЖДОГО бойца
		# значит получить разные ответы для разных шеренг одного и того же
		# отряда — точно та же беда, что уже ловилась на самой точке флажка
		# (qa_rally2 F4). Запасной ответ — сама точка: так зовёт стенд,
		# собравший _spawn_one напрямую
		var want_c: Vector3 = r_spot if r_spot.x != INF else r_pos
		rally = want_c + exit_dir * offset_z + side * offset_x
	# СТРАХОВКА ОТ ТОЧКИ СБОРА ЗА КРАЕМ МИРА. Полосы теперь ограничены, но барак
	# может стоять вплотную к краю карты, а игрок — поставить флажок куда угодно.
	# Приказ за границу боец всё равно не выполнит (шаг упирается в map_lim), и
	# отряд остался бы вечно «идущим» в стену вместо того, чтобы встать строем
	var rally_xz := GameManager.clamp_to_map(rally.x, rally.z)
	rally.x = rally_xz.x
	rally.z = rally_xz.y
	# Вход в дерево — отложенно (вне текущего кадра), позиция и приказ следом:
	# отложенные вызовы выполняются в порядке постановки, так что к моменту
	# _place_spawned юнит уже в дереве и global_position корректен
	parent.call_deferred("add_child", unit)
	call_deferred("_place_spawned", unit, gate, rally, squad_id, exit_dir, zone_pos)

## ── ПЛОЩАДКА СБОРА (хак №3, 09.09.2026) ──────────────────────────────────
## Боец появляется СРАЗУ НА СВОЁМ МЕСТЕ в прямоугольнике перед воротами, а не
## в самих воротах с последующим маршем к месту: очередь в проёме, разбор
## наложения у дверей и толчея двух заказов исчезают по построению. Полосы
## выхода остались РЯДАМИ площадки (см. _free_exit_lane): каждому заказу —
## свой свободный ряд, ближний к воротам. С назначенной точкой сбора отряд
## тоже собирается на площадке и оттуда идёт к флажку строем.
## Разворот прежнего заказа «бойцы появляются у ворот и выходят шеренгами»
## (qa_spawnlane C1 переписан на «появляются на площадке»)
const SPAWN_ON_ZONE := true

func _place_spawned(unit: Unit, gate: Vector3, rally: Vector3,
		squad_id: int = 0, exit_dir: Vector3 = Vector3.ZERO,
		zone_pos: Vector3 = Vector3.INF) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
		return
	if SPAWN_ON_ZONE and zone_pos.x != INF:
		unit.global_position = Vector3(zone_pos.x,
			GameManager.get_terrain_height(zone_pos.x, zone_pos.z), zone_pos.z)
		unit.sync_row()
	else:
		unit.global_position = gate
	if squad_id > 0:
		GameManager.add_to_squad(squad_id, unit)
	unit.command_move(rally, false, exit_dir)

## Прямоугольник площадки: центр, ось вперёд, ось вбок, полуширина, полуглубина.
## Считается по уставному отряду здания и покрывает все EXIT_LANES рядов
func rally_zone() -> Dictionary:
	var total: int = maxi(squad_size, 1)
	var cols: int = square_cols(total, squad_cols)
	var spacing: float = squad_spacing
	# ВОРОТА — ПЕРВЫМИ: _gate_position() лениво ставит фасад (_face_front) и
	# переписывает spawn_offset; читать его ДО этого значит взять начальное
	# (3, 0, 0) и развернуть площадку вбок (поймал qa_rally_zone A4)
	var gate: Vector3 = _gate_position()
	var dir: Vector3 = spawn_offset
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var side := Vector3(-dir.z, 0.0, dir.x)
	var rows: int = int(ceil(float(total) / float(cols)))
	var own: float = float(rows) * spacing
	var step: float = _lane_depth_step(total, cols, spacing)
	var near: float = SQUAD_EXIT_DISTANCE - spacing * 0.5
	var far: float = SQUAD_EXIT_DISTANCE + float(exit_lanes(total, cols, spacing) - 1) * step + own + spacing * 0.5
	var half_w: float = maxf(float(cols) * spacing * 0.5, _lane_step(total, cols, spacing) * 0.5) + spacing * 0.5
	return {
		"centre": gate + dir * ((near + far) * 0.5),
		"dir": dir, "side": side,
		"half_w": half_w, "half_d": (far - near) * 0.5,
	}

## Лежит ли точка на площадке (в плане)
func in_rally_zone(p: Vector3, slack: float = 0.3) -> bool:
	var z: Dictionary = rally_zone()
	var c: Vector3 = z["centre"]
	var d: Vector3 = p - c
	var along: float = d.x * (z["dir"] as Vector3).x + d.z * (z["dir"] as Vector3).z
	var across: float = d.x * (z["side"] as Vector3).x + d.z * (z["side"] as Vector3).z
	return absf(along) <= float(z["half_d"]) + slack and absf(across) <= float(z["half_w"]) + slack

## Рисунок площадки на земле — только у выделенного здания (как флажок)
var _zone_marker: MeshInstance3D = null
const ZONE_COLOR := Color(0.93, 0.80, 0.30, 1.0)
const ZONE_LINE_W := 0.12
## РАМКА СКРЫТА (заказ 10.09.2026 по скриншоту: «жёлтую зону убрать совсем»).
## Геометрия площадки и спавн на ней остались, рисунок на земле — нет.
## Ручка оставлена: механизм рамки по рельефу проверен и может понадобиться
const ZONE_MARKER_SHOWN := false

func _refresh_zone_marker() -> void:
	if not ZONE_MARKER_SHOWN or not _rally_visible or squad_size <= 1 or not SPAWN_ON_ZONE:
		if _zone_marker != null and is_instance_valid(_zone_marker):
			_zone_marker.visible = false
		return
	var z: Dictionary = rally_zone()
	if _zone_marker == null or not is_instance_valid(_zone_marker):
		_zone_marker = MeshInstance3D.new()
		_zone_marker.name = "RallyZone"
		var m := StandardMaterial3D.new()
		m.albedo_color = ZONE_COLOR
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_zone_marker.material_override = m
		var host: Node = get_parent()
		if host == null:
			host = self
		host.add_child(_zone_marker)
	# ── РАМКА, А НЕ ЗАЛИВКА ────────────────────────────────────────────────
	# Прозрачная заливка в GL Compatibility гасила под собой спрайты бойцов
	# (снимок qa_rally_zone/Shot: два отряда пропали целиком), а плоский квад
	# на волнистом рельефе тонул в грунте. Четыре НЕПРОЗРАЧНЫЕ полосы по
	# краям, вершины — по рельефу: под ногами бойцов рамки нет вовсе
	var c: Vector3 = z["centre"]
	var dir: Vector3 = z["dir"]
	var side: Vector3 = z["side"]
	var hw: float = float(z["half_w"])
	var hd: float = float(z["half_d"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# полоса: от a до b вдоль оси u, ширина ZONE_LINE_W поперёк оси v
	var strips: Array = [
		[dir, side, -hd, hd, -hw], [dir, side, -hd, hd, hw],
		[side, dir, -hw, hw, -hd], [side, dir, -hw, hw, hd]]
	for sdef in strips:
		var u: Vector3 = sdef[0]
		var v: Vector3 = sdef[1]
		var t0: float = float(sdef[2])
		var t1: float = float(sdef[3])
		var off: float = float(sdef[4])
		var n: int = maxi(int(ceil((t1 - t0) / 2.0)), 1)
		for k in range(n):
			var a0: float = t0 + (t1 - t0) * float(k) / float(n)
			var a1: float = t0 + (t1 - t0) * float(k + 1) / float(n)
			var pts: Array = [
				c + u * a0 + v * (off - ZONE_LINE_W), c + u * a1 + v * (off - ZONE_LINE_W),
				c + u * a1 + v * (off + ZONE_LINE_W), c + u * a0 + v * (off + ZONE_LINE_W)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var q: Vector3 = pts[idx]
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(q.x, GameManager.get_terrain_height(q.x, q.z) + 0.05, q.z))
	_zone_marker.mesh = st.commit()
	_zone_marker.global_transform = Transform3D.IDENTITY
	_zone_marker.visible = true

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
	var path: String = ruin_sprite_override()
	if path.is_empty():
		path = GameManager.ruin_sprite_path(faction, building_id)
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
	ruin.set_meta("ruin_any_faction", ruin_any_faction())
	var quad := QuadMesh.new()
	quad.size = sprite_quad_size(tex, build_size) * ruin_scale()
	var rmat: ShaderMaterial = _BBUtil.make_static_material(tex)
	# ── БОЕЦ РИСУЕТСЯ ПОВЕРХ ПЕПЕЛИЩА (заказ владельца 10.09.2026) ────────
	# Точка сортировки руины уходит от камеры на половину её нарисованной
	# высоты (см. depth_push в cyl_billboard): пепелище — мусор на земле, и
	# спрайт тролля (живого или мёртвого) обязан быть выше него
	rmat.set_shader_parameter("depth_push", quad.size.y * 0.5)
	quad.material = rmat
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
