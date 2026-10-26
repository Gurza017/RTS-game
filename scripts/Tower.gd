extends Castle
## ═══════════════════════════════════════════════════════════════════════════
## ОБОРОНИТЕЛЬНАЯ БАШНЯ (заказ владельца, 09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## НАСЛЕДУЕТ ЗАМОК ради гарнизона — тем же порядком и по той же причине, что
## хижина гоблинов: принять отряд, спрятать с карты, лечить, доукомплектовать,
## выпустить через ворота у нарисованной двери. Писать это заново значило бы
## завести вторую реализацию гарнизона со своими болезнями.
##
## От замка отличается ровно четырьмя вещами, и все они выражены
## ПЕРЕОПРЕДЕЛЕНИЯМИ, а не развилками внутри Castle:
##   • принимает ТОЛЬКО ЛУЧНИКОВ и ровно один отряд
##     (unit_stats_config.TOWER_GARRISON_*, см. garrison_accepts / garrison_limit);
##   • отряд НЕ ВЫХОДИТ САМ, когда вылечен: башня — это пост, а не лазарет
##     (_auto_release). Наружу — по ПКМ по башне или кнопкой в панели;
##   • обзор в тумане TOWER_VISION вместо BUILDING_VISION (vision_radius);
##   • на площадке стоит ЧАСОВОЙ, пока внутри есть лучники (_sync_sentinel).
##
## И ЭТО НЕ КРЕПОСТЬ: is_stronghold() = false. Все места, где «замок» значит
## «столица» — зона застройки, кнопка «в замок», условие поражения, точка
## базы для ИИ, — спрашивают именно это, а не `is Castle`.
##
## Файл НАМЕРЕННО без class_name: подключается через preload/load, поэтому не
## зависит от global_script_class_cache.cfg (тот же приём, что у House).

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _BBUtilT := preload("res://scripts/BillboardUtil.gd")
## Модуль крыши — общий _Roof из Castle

## Ворота у подножия: башня узкая, замковые 6.5 м увели бы точку выхода на
## пустую траву далеко перед рисунком
const TOWER_GATE := 2.6

## ── ЧАСОВОЙ НА ПЛОЩАДКЕ ─────────────────────────────────────────────────────
## Где у Tower.png площадка: деревянный настил лежит на 0.60 высоты рисунка
## (обмер: настил на 100-110 px из 256 снизу). Подбирается глазом в окне
const SENTINEL_FOOT_FRAC := 0.60
## Сторона квада часового, метры. Кадр Archer_Idle 192 px при пикселе бойца
## ~0.0108 м даёт 2.07; чуть меньше — часовой стоит дальше от камеры, чем
## подножие, и не должен читаться крупнее прохожего
const SENTINEL_SIZE_M := 1.9
## Пустое поле под ступнями в кадре Archer_Idle: 56 px из 192 (обмер PIL).
## Низ квада опускается на эту долю ниже настила, чтобы ноги стояли на нём
const SENTINEL_FOOT_PAD := 56.0 / 192.0

## ── МЕСТА НА НАСТИЛЕ: КРУГ, А НЕ ШЕРЕНГА (заказ спринта 14) ───────────────
## Было: все спрайты расходились от середины ВДОЛЬ ОДНОЙ ЛИНИИ, и десять
## лучников вытягивались в длинную полосу шире самой башни — на скриншоте это
## читалось как строй, вставший на карниз.
##
## Стало: один в ЦЕНТРЕ площадки, остальные равномерно по ЭЛЛИПСУ вокруг него.
## Эллипс, а не круг, потому что настил виден под наклоном камеры: круг на
## горизонтальной площадке проецируется в эллипс, сплюснутый по вертикали
## экрана ровно в sin(наклона) раз — это и есть SENTINEL_RING_SQUASH.
##
## ГЛУБИНА БЕРЁТСЯ ИЗ ТОГО ЖЕ СИНУСА: стоящий «за» центром обязан рисоваться
## позади, а спрайты лежат в одной плоскости билборда, и порядок задаёт только
## сдвиг по Z. Поэтому места считаются ОДНОЙ формулой — иначе картинка и
## порядок перекрытия разъехались бы.
const SENTINEL_RING_FRAC := 0.30      # радиус круга, доля ширины постройки
const SENTINEL_RING_SQUASH := 0.42    # сплющивание по экрану (наклон камеры)
const SENTINEL_RING_DEPTH := 0.16     # разнос по глубине, м

## Место idx на настиле: (вбок, вверх, вглубь) от середины площадки.
## Нулевой — в центре, остальные по кругу. Всего мест — сколько видимых
## лучников держит башня (unit_stats_config.TOWER_VISIBLE_ARCHERS)
## Место idx на настиле — считает RoofGarrison._ring_spot тем же правилом
static func sentinel_spot(idx: int, total: int, width: float) -> Vector3:
	if idx <= 0 or total <= 1:
		return Vector3.ZERO
	var r: float = width * SENTINEL_RING_FRAC
	var on_ring: int = maxi(total - 1, 1)
	var a: float = TAU * (float(idx - 1) + 0.5) / float(on_ring)
	return Vector3(cos(a) * r, sin(a) * r * SENTINEL_RING_SQUASH, -sin(a) * SENTINEL_RING_DEPTH)

## ── ВСЯ ПЛОЩАДКА ЖИВЁТ В ОБЩЕМ МОДУЛЕ RoofGarrison (ТЗ 14.09.2026) ─────────
## Спрайты на настиле, огонь за укрытых, урон дальнего боя по лучнику на
## площадке, тела у подножия и выпуск — один код на башню, бараки и крепость
## (см. scripts/RoofGarrison.gd). Здесь остались только раскладка (кольцо) и
## прежние имена, по которым башню спрашивают панель и стенды
func _roof_setup():
	var r = _Roof.new()
	r.setup(self, _Roof.LAYOUT_RING, int(_UCfgT.ROOF_VISIBLE.get("tower", _UCfgT.TOWER_VISIBLE_ARCHERS)),
		float(_UCfgT.ROOF_FOOT_FRAC.get("tower", SENTINEL_FOOT_FRAC)))
	return r

## Сколько выстрелов сделано с площадки (стенды)
var shots_fired: int:
	get:
		return int(_roof.shots_fired) if _roof != null else 0

func _configure() -> void:
	building_id  = "tower"
	sprite_path  = ""
	max_health   = _UCfgT.building_stat("tower", "max_hp", 1200.0)
	build_size   = _UCfgT.building_size("tower", Vector3(3.4, 3.0, 3.4))
	display_name = String(_UCfgT.building_cfg("tower").get("name", "Башня"))
	# СКЛАДА НЕТ: башня — не столица, рабочим сдавать сюда нечего
	is_dropoff   = false
	squad_size   = 1
	squad_cols   = 4
	squad_spacing = 0.55
	spawn_offset = Vector3(0.0, 0.0, TOWER_GATE)

## Не дальше периметра рисунка — см. Building.gate_depth
func gate_depth() -> float:
	if _draw_half_w >= 0.0:
		return minf(TOWER_GATE, _draw_half_w + GATE_CLEARANCE)
	return TOWER_GATE

## Башня — не крепость (см. шапку)
func is_stronghold() -> bool:
	return false

func garrison_limit() -> int:
	return _UCfgT.TOWER_GARRISON_LIMIT

func garrison_accepts(unit_type: String) -> bool:
	return unit_type in _UCfgT.TOWER_GARRISON_TYPES

## Вылеченный отряд остаётся на посту
func _auto_release() -> bool:
	return false

## Обзор выше стрелка (см. unit_stats_config.TOWER_VISION)
func vision_radius() -> float:
	return _UCfgT.TOWER_VISION

## Тик нужен только с гарнизоном (или очередью ко входу) и на время работ по
## укреплению; золота башня не даёт
func _needs_tick() -> bool:
	return not garrison.is_empty() or not _incoming.is_empty() or _fort_left > 0.0

# ═════════════════════════════════════════════════════════════════════════════
# УКРЕПЛЕНИЕ БАШНИ (ТЗ 20.10.2026, блок 4)
# ═════════════════════════════════════════════════════════════════════════════
## Ступени — unit_stats_config.TOWER_FORT_LEVELS. Работы идут таймером здания
## (башня продолжает стоять и стрелять, гарнизон не выходит); по окончании —
## прибавка к запасу жизни, снижение входящего урона и «каменный» рисунок.
## Сохраняется (SaveLoadManager: поле "fort")
signal fortified(level: int)
var fort_level: int = 0
var _fort_left: float = 0.0
var _fort_total: float = 0.0

func fort_max() -> int:
	return _UCfgT.TOWER_FORT_LEVELS.size()

## Описание СЛЕДУЮЩЕЙ ступени; пусто — предел
func fort_next() -> Dictionary:
	if fort_level >= fort_max():
		return {}
	return _UCfgT.TOWER_FORT_LEVELS[fort_level]

func fort_cost() -> Dictionary:
	var n: Dictionary = fort_next()
	if n.is_empty():
		return {}
	var c := {}
	if float(n.get("cost_wood", 0.0)) > 0.0:
		c[Constants.RESOURCE_WOOD] = int(n["cost_wood"])
	if float(n.get("cost_stone", 0.0)) > 0.0:
		c[Constants.RESOURCE_STONE] = int(n["cost_stone"])
	return c

func fort_busy() -> bool:
	return _fort_left > 0.0

func fort_progress() -> float:
	if _fort_total <= 0.0:
		return 0.0
	return clampf(1.0 - _fort_left / _fort_total, 0.0, 1.0)

## Заказать следующую ступень. false — предел, идут работы или не хватает
func fort_start() -> bool:
	if fort_busy() or is_dead():
		return false
	var n: Dictionary = fort_next()
	if n.is_empty():
		return false
	var c: Dictionary = fort_cost()
	if not ResourceManager.can_afford(faction, c):
		return false
	ResourceManager.spend(faction, c)
	_fort_total = maxf(float(n.get("time", 0.0)), 0.01)
	_fort_left = _fort_total
	set_process(true)
	return true

## Отменить идущие работы с возвратом цены
func fort_cancel() -> bool:
	if not fort_busy():
		return false
	var c: Dictionary = fort_cost()
	for k in c:
		ResourceManager.add_resource(faction, int(k), float(c[k]))
	_fort_left = 0.0
	_fort_total = 0.0
	return true

## Множитель входящего урона текущей ступени
func fort_damage_mult() -> float:
	if fort_level <= 0:
		return 1.0
	var d: Dictionary = _UCfgT.TOWER_FORT_LEVELS[mini(fort_level, fort_max()) - 1]
	return float(d.get("dmg_mult", 1.0))

## Поставить ступень сразу (завершение работ, загрузка сохранения, стенды)
func fort_apply(level: int) -> void:
	level = clampi(level, 0, fort_max())
	var base_hp: float = _UCfgT.building_stat("tower", "max_hp", 1200.0)
	while fort_level < level:
		var d: Dictionary = _UCfgT.TOWER_FORT_LEVELS[fort_level]
		var add: float = base_hp * float(d.get("hp_add", 0.0))
		max_health += add
		current_health += add
		fort_level += 1
	_fort_look()
	_update_hp_bar()

func _fort_look() -> void:
	if _sprite_mat == null:
		return
	var tints: Array = _UCfgT.TOWER_FORT_TINT
	var c: Color = tints[clampi(fort_level, 0, tints.size() - 1)]
	_sprite_mat.set_shader_parameter("modulate", c)

func _process(delta: float) -> void:
	super._process(delta)
	if _fort_left > 0.0:
		_fort_left -= delta
		if _fort_left <= 0.0:
			_fort_left = 0.0
			fort_apply(fort_level + 1)
			flash_accept()
			fortified.emit(fort_level)

## Облицовка режет ВХОДЯЩИЙ урон (стрелы, удары, туши) — до базового расчёта
func take_damage(amount: float, attacker: Node = null) -> void:
	super.take_damage(amount * fort_damage_mult(), attacker)

## ЗАМКОВОЙ МОДЕЛИ У БАШНИ НЕТ. База Castle грузит castle.glb; здесь нужен
## только коллайдер и запасной примитив — картинку положит поверх
## Building._maybe_load_building_sprite
func _build_visual() -> void:
	_add_pick_shape()
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = build_size.x * 0.32
	cyl.bottom_radius = build_size.x * 0.4
	cyl.height = build_size.y * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.48, 0.44)
	mat.roughness = 0.9
	cyl.material = mat
	body.mesh = cyl
	body.position.y = build_size.y
	add_child(body)
	selection_ring = make_selection_marker()
	add_child(selection_ring)

## Дальность огня с площадки — штатная дальность лучников внутри с баффом
## высоты (GARRISON_RANGE_MULT), а не обзор башни. Гарнизон пуст — ноль
func fire_range() -> float:
	return float(_roof.fire_range()) if _roof != null else 0.0

## Точка, откуда летят стрелы: середина настила
func platform_point() -> Vector3:
	return _roof.platform_point() if _roof != null else global_position

## Куда падает труп: у ПОДНОЖИЯ башни, чуть в сторону от ворот
func corpse_spot(idx: int = 0) -> Vector3:
	return _roof.corpse_spot(idx) if _roof != null else global_position

func has_garrison() -> bool:
	return not garrison.is_empty()

## Отряд внутри (первый; у башни он один). 0 — пусто
func garrison_squad_id() -> int:
	if garrison.is_empty():
		return 0
	return int((garrison[0] as Dictionary).get("sid", 0))

## Спрайтов на настиле ровно столько, сколько живых (не больше cap)
func _sync_sentinel() -> void:
	if _roof != null:
		_roof.sync()

## Сколько ЖИВЫХ бойцов сидит внутри
func garrison_men() -> int:
	return int(_roof.men()) if _roof != null else 0

func sentinel_visible() -> bool:
	return _roof != null and int(_roof.shown()) > 0

## Сколько спрайтов лучников видно на настиле (стенды)
func archers_shown() -> int:
	return int(_roof.shown()) if _roof != null else 0

## Выпустить всех (ПКМ по башне или кнопка панели). false — внутри пусто
func release_all() -> bool:
	if garrison.is_empty():
		return false
	var ids: Array = []
	for rec in garrison:
		ids.append(int((rec as Dictionary).get("sid", 0)))
	for sid in ids:
		release_garrison(int(sid))
	_sync_sentinel()
	return true

## Пепелище общее «домовое», на башне — в долю (см. Building.spawn_ruin)
func ruin_scale() -> float:
	return _UCfgT.building_stat("tower", "ruin_scale", 1.0)
