extends Node3D
class_name Main

enum Phase { MAIN_MENU, PLACING_CASTLE, PLACING_BUILDING, PLAYING, VICTORY, DEFEAT }

const _BBUtil   := preload("res://scripts/BillboardUtil.gd")
const _UIAssets := preload("res://scripts/UIAssets.gd")
const _UCfg     := preload("res://scripts/unit_stats_config.gd")
const _CSite    := preload("res://scripts/ConstructionSite.gd")
# ИИ вынесен в отдельный файл: логика в EnemyAI.gd, ЧИСЛА — в ai_start_army_limit.gd
const _EnemyAI  := preload("res://scripts/EnemyAI.gd")
const _AICfg    := preload("res://scripts/ai_start_army_limit.gd")

const VICTORY_CHECK_INTERVAL := 3.0

# ─────────────────────────────────────────────────────────────────────────────
# РАЗМЕР МИРА
# Одно число управляет ВСЕМ: жёсткой границей, зоной генерации, привязками баз,
# пределами камеры и оформлением края. Раньше половина карты (75 м) была
# рассыпана литералами по десятку мест — трогать размер было нельзя.
# ─────────────────────────────────────────────────────────────────────────────
const MAP_HALF_LEGACY := 75.0          # как было (квадрат 150×150)
const MAP_GROWTH      := 1.30          # +30% по ширине и длине
## Половина стороны РАВНОВЕЛИКОГО КВАДРАТА. Прямая ссылка на прежний размер:
## прямоугольник ниже подобран так, чтобы площадь осталась ровно такой же
const MAP_HALF_EQUIV := MAP_HALF_LEGACY * MAP_GROWTH   # 97.5 → квадрат 195×195

# ── ФОРМА КАРТЫ: ПРЯМОУГОЛЬНИК 16:9 ──────────────────────────────────────────
# Поле вытянуто по горизонтали, как экран. ПЛОЩАДЬ СОХРАНЕНА от квадратной
# карты: 260 × 146.25 = 38 025 м² = 195². Значит ни плотность леса, ни число
# ресурсов, ни нагрузка на кадр от смены формы не поехали.
# Обе полуоси считаются из одного числа: MAP_HALF_EQUIV × √(16/9) и ÷ √(16/9).
const MAP_ASPECT := 16.0 / 9.0
## Половина ШИРИНЫ поля (ось X, длинная сторона)
const MAP_HALF_X := 130.0        # MAP_HALF_EQUIV * sqrt(MAP_ASPECT)
## Половина ВЫСОТЫ поля (ось Z, короткая сторона)
const MAP_HALF_Z := 73.125       # MAP_HALF_EQUIV / sqrt(MAP_ASPECT)

## Полоса у самой границы, в которую юнит уже не заходит (упор в стену)
const MAP_EDGE_MARGIN := 1.5
## Зона общей генерации (лес, кусты, кучи ресурсов)
const GEN_HALF_X := MAP_HALF_X - 9.0
const GEN_HALF_Z := MAP_HALF_Z - 9.0
## Зона разброса куч ресурсов
const RES_HALF_X := MAP_HALF_X - 13.0
const RES_HALF_Z := MAP_HALF_Z - 13.0
## Куда вообще можно ткнуть мышью на земле
const MAP_CLAMP_X := MAP_HALF_X - 5.0
const MAP_CLAMP_Z := MAP_HALF_Z - 5.0
## Полуразмер площадки, внутри которой игрок ставит свой замок.
## Отсчитывается ОТ ЯКОРЯ ЕГО БАЗЫ — то есть от нижнего левого угла карты
const PLAYER_PLACE_HALF := 30.0

# ── ОФОРМЛЕНИЕ КРАЯ МИРА ─────────────────────────────────────────────────────
## Ширина зелёного бортика (фаски) за игровым полем
const MAP_BEVEL := 3.5
## На сколько метров фаска опускается в черноту
const MAP_BEVEL_DROP := 2.5

# ЕДИНСТВЕННОЕ озеро карты. ВРЕМЕННО ОТКЛЮЧЕНО (LAKE_ENABLED = false):
# центр карты сделан сушей. Код озера НЕ удалён — вся геометрия, обход берега
# и поиск суши остаются на месте и включаются одним флагом.
const LAKE_ENABLED := false
const LAKE_CENTER := Vector3(-22.0, 0.0, -12.0)
const LAKE_RADIUS := 11.0    # средний радиус по X
const LAKE_SQUASH := 0.72    # сжатие по Z (озеро вытянутое, не круглое)
# Доля радиуса берега, на которой стоит кольцо камней — внутри воды, у кромки
const LAKE_ROCK_RING := 0.88
# Запас вокруг берега, куда юнит уже не заходит (камни у кромки + кромка сама)
const LAKE_MARGIN := 0.6

var hud: HUD
var selection_manager: SelectionManager
var enemy_ai: Node             = null     # см. scripts/EnemyAI.gd
var _victory_timer     := 0.0
var _phase: int        = Phase.MAIN_MENU
var _ghost: MeshInstance3D    = null
var _camera: RTSCamera        = null

# ── БЕЗОПАСНЫЕ ЗОНЫ БАЗ ──────────────────────────────────────────────────────
# Пятачок вокруг каждой базы, куда генератор НЕ сажает ни деревьев, ни руды.
# Раньше замок вставал прямо в кучу камней: кластеры разбрасывались по карте,
# ничего не зная про базы. Теперь зоны резервируются ДО генерации, и все
# спавнеры их обходят.
const BASE_CLEAR_RADIUS := 11.0
# ── СТАРТОВЫЕ УГЛЫ: ИГРОК И ИИ ПО ДИАГОНАЛИ ──────────────────────────────────
# Игрок — НИЖНИЙ ЛЕВЫЙ угол (−X, −Z), ИИ — ВЕРХНИЙ ПРАВЫЙ (+X, +Z).
# Якоря отсчитываются ОТ УГЛОВ ПОЛЯ, а не литералами: изменится форма карты —
# базы сами останутся в своих углах. Отступ подобран так, чтобы расчищенная
# зона базы (BASE_CLEAR_RADIUS = 11) и кольцо своих ресурсов (15 м) целиком
# помещались внутрь поля и не упирались в бортик.
const BASE_CORNER_INSET := 24.0
const PLAYER_BASE_ANCHOR := Vector3(
	-MAP_HALF_X + BASE_CORNER_INSET, 0.0, -MAP_HALF_Z + BASE_CORNER_INSET)
const ENEMY_BASE_ANCHOR  := Vector3(
	 MAP_HALF_X - BASE_CORNER_INSET, 0.0,  MAP_HALF_Z - BASE_CORNER_INSET)
# Кольцо, на котором у базы стоят своя жила золота и своя каменоломня
const BASE_RESOURCE_DIST := 15.0

# Занятые круги: [{"c": Vector3, "r": float}, ...]
var _reserved: Array = []

var _castle_placed: bool       = false
var _placing_build_fn: Callable
var _placing_refund: Dictionary = {}
var _duck_node: Node3D         = null
# Контейнер всего контента карты; transform ВСЕГДА identity — не трогать
var _world: Node3D             = null

func _ready() -> void:
	randomize()
	GameManager.main = self
	_apply_custom_cursor()
	# АРХИТЕКТУРНОЕ ПРАВИЛО RTS: весь контент карты живёт под узлом World
	# с НУЛЕВОЙ и НИКОГДА не меняющейся трансформацией. Вращается только
	# CameraPivot (см. _setup_camera) — мир неподвижен.
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	# Пределы карты снимаются ОДИН РАЗ и дальше живут числами в GameManager:
	# зажим границ стоит на самом горячем пути (шаг каждого бойца)
	GameManager.refresh_map_bounds()
	_setup_environment()
	_setup_terrain()
	_setup_fog()
	_camera = _setup_camera()
	hud = HUD.new()
	add_child(hud)
	selection_manager = SelectionManager.new()
	add_child(selection_manager)
	selection_manager.setup(_camera, hud.get_drag_rect())
	enemy_ai = _EnemyAI.new()
	enemy_ai.name = "EnemyAI"
	add_child(enemy_ai)
	start_game()

func start_game() -> void:
	# Реестр стволов переживает узлы (он не в дереве сцены), поэтому при новом
	# бое его надо обнулить руками — иначе на карте останутся невидимые
	# препятствия от прошлого леса
	GameManager.clear_trunks()
	_setup_reserved_zones()
	ResourceManager.reset_resources()
	GameManager.reset_squads()
	_victory_timer       = 0.0
	_castle_placed       = false
	_spawn_resource_nodes()
	# Своя жила и своя каменоломня рядом с каждой базой — на расчищенной
	# площадке, вне коллизии замка и не пересекаясь друг с другом
	_add_base_resource_clusters(PLAYER_BASE_ANCHOR)
	_add_base_resource_clusters(ENEMY_BASE_ANCHOR)
	_spawn_enemy_base()
	# ── СТАРТ ВПЛОТНУЮ К ЗЕМЛЕ, В СВОЁМ УГЛУ ────────────────────────────────
	# Матч открывается на ПРЕДЕЛЕ ПРИБЛИЖЕНИЯ (min_height), в углу игрока.
	# Это разворот прежнего решения: раньше здесь стоял max_height («общий план
	# стартовой зоны») ровно потому, что при полном приближении игрок не видел
	# карты вокруг. Теперь ту же задачу решает туман войны — дальше пятачка
	# всё равно ничего не видно, а стартовая площадка под замок раскрыта
	# заранее (см. _setup_fog), поэтому выбирать место есть где и вслепую
	# игрок не остаётся. Дальше зум крутится колесом
	if _camera != null:
		_camera.jump_to(PLAYER_BASE_ANCHOR, _camera.min_height)
	_reveal_start_area()
	_phase = Phase.PLAYING
	# Лес заводится на весь бой; основная тема будет подмешиваться раз в 10 минут
	AudioManager.start_game_audio()
	hud.show_hud()
	# СТАРТОВЫЙ ЗАМОК СТАВИТ ИГРОК, А НЕ ГЕНЕРАТОР. Сразу после старта под
	# курсором появляется синий фантом крепости: ЛКМ — поставить, ПКМ или
	# Escape — отменить. Место ограничено нижним левым углом (см.
	# clamp_to_player_start), поэтому «замок посреди карты» невозможен
	if not _castle_placed:
		enter_castle_placement(true)
	if enemy_ai != null:
		enemy_ai.setup(self)

## ТОЧКА СБОРА ИИ «В ПОЛЕ» — середина карты.
## Спрашивается из EnemyAI: тот не знает ни про озеро, ни про класс Main
func ai_rally_point() -> Vector3:
	if LAKE_ENABLED:
		var away := Vector3(1.0, 0.0, 1.0).normalized()
		var p := LAKE_CENTER + away * (LAKE_RADIUS + 6.0)
		return Vector3(p.x, 0.0, p.z)
	# Озера нет — центр карты это ровно середина между базами
	var mid := (PLAYER_BASE_ANCHOR + ENEMY_BASE_ANCHOR) * 0.5
	return Vector3(mid.x, 0.0, mid.z)

# ─────────────────────────────────────────────────────────────────────────────
# ГРАНИЦЫ МИРА
# Маски столкновений в проекте намеренно нулевые (см. README: включённые маски
# давали дрожание на грунте), поэтому физическая стена сама по себе никого не
# остановит. Настоящий упор — вот этот зажим: через него проходит КАЖДОЕ
# перемещение юнита (шаг, расталкивание, толчок чужой шеренги) и каждый приказ.
# Стены-коллайдеры ставятся отдельно (_build_world_edge) и работают как
# ограничитель для лучей выбора, чтобы клик мимо карты не давал точку в пустоте.
# ─────────────────────────────────────────────────────────────────────────────

## Точка, зажатая в границы мира. Пределы РАЗНЫЕ по осям: карта прямоугольная
func clamp_to_map(x: float, z: float) -> Vector2:
	var lx: float = MAP_HALF_X - MAP_EDGE_MARGIN
	var lz: float = MAP_HALF_Z - MAP_EDGE_MARGIN
	return Vector2(clampf(x, -lx, lx), clampf(z, -lz, lz))

## Точка вне игрового поля?
func is_outside_map(x: float, z: float) -> bool:
	return absf(x) > MAP_HALF_X - MAP_EDGE_MARGIN \
		or absf(z) > MAP_HALF_Z - MAP_EDGE_MARGIN

## СТАРТОВАЯ ПЛОЩАДКА ИГРОКА — НИЖНИЙ ЛЕВЫЙ УГОЛ КАРТЫ.
## Замок ставится кликом, но только внутри квадрата вокруг якоря своей базы:
## иначе игрок мог основать столицу хоть под носом у ИИ, и вся диагональная
## расстановка теряла смысл. Заодно точка не вылезает за границу поля
func clamp_to_player_start(x: float, z: float) -> Vector2:
	var a: Vector3 = PLAYER_BASE_ANCHOR
	var cx: float = clampf(x, a.x - PLAYER_PLACE_HALF, a.x + PLAYER_PLACE_HALF)
	var cz: float = clampf(z, a.z - PLAYER_PLACE_HALF, a.z + PLAYER_PLACE_HALF)
	return Vector2(clampf(cx, -MAP_CLAMP_X, MAP_CLAMP_X),
		clampf(cz, -MAP_CLAMP_Z, MAP_CLAMP_Z))

## Помещается ли декорация/ресурс в поле с запасом. Угловые лесные массивы
## разбрасывают деревья от центра рощи со случайным разлётом и легко
## выплёскиваются за границу — такое дерево оказалось бы в черноте
func _fits_in_map(x: float, z: float, margin: float = 2.0) -> bool:
	return absf(x) <= MAP_HALF_X - margin and absf(z) <= MAP_HALF_Z - margin

# ─────────────────────────────────────────────────────────────────────────────
# РЕЗЕРВНЫЕ ЗОНЫ
# Вызывается ДО любой генерации: и рельеф с лесом (_setup_terrain), и ресурсы
# (start_game) спрашивают _is_reserved() перед тем, как что-то поставить.
# ─────────────────────────────────────────────────────────────────────────────
func _setup_reserved_zones() -> void:
	_reserved.clear()
	_reserve(PLAYER_BASE_ANCHOR, BASE_CLEAR_RADIUS)
	_reserve(ENEMY_BASE_ANCHOR,  BASE_CLEAR_RADIUS)
	# Пятачки под СВОИ кучи руды резервируются ЗДЕСЬ, а не после их спавна.
	# Порядок вызовов: _ready() → _setup_terrain() сажает лес подковы, и только
	# потом start_game() ставит кучи. Резерв, выставленный вместе с кучей,
	# опаздывал — лес успевал вырасти прямо в жиле (замер QA: до 15 стволов
	# внутри кучи). Точки детерминированы, поэтому их можно занять заранее.
	for anchor in [PLAYER_BASE_ANCHOR, ENEMY_BASE_ANCHOR]:
		for spot in _base_resource_spots(anchor):
			_reserve(spot, BASE_ORE_CLEAR)

func _reserve(center: Vector3, radius: float) -> void:
	_reserved.append({"c": center, "r": radius})

## true — точка попадает в чью-то безопасную зону (с запасом margin)
func _is_reserved(x: float, z: float, margin: float = 0.0) -> bool:
	for e in _reserved:
		var d: Dictionary = e
		var c: Vector3 = d["c"]
		var r: float   = d["r"]
		if Vector2(x - c.x, z - c.z).length() < r + margin:
			return true
	return false

## Убрать ресурсы, оказавшиеся под зданием. Страховка для замка игрока:
## его точку выбирает игрок, и она может не совпасть с якорем базы
func _clear_area_of_resources(center: Vector3, radius: float) -> void:
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null or not is_instance_valid(rn):
			continue
		var d := Vector2(rn.global_position.x - center.x, rn.global_position.z - center.z).length()
		if d < radius:
			rn.queue_free()

func on_selection_changed(units: Array) -> void:
	hud.show_selection(units)

# Единственная точка добавления контента карты: всё — под World (identity transform)
func world_add(node: Node) -> void:
	_world.add_child(node)

# GameManager.far_units держит MultiMeshInstance3D дальних юнитов — этим узлам
# тоже нужен World как родитель (identity transform, как и всему остальному)
func world_root() -> Node3D:
	return _world

# ─────────────────────────────────────────────────────────────────────────────
# ТУМАН ВОЙНЫ И СТАРТОВАЯ ПЛОЩАДКА
# ─────────────────────────────────────────────────────────────────────────────

## Насколько раскрытая заранее площадка шире зоны, в которой разрешено ставить
## замок (PLAYER_PLACE_HALF). Запас нужен, чтобы у самой границы зоны игрок
## видел не кромку тумана, а землю за ней — иначе крайние точки выбираются
## вслепую. Радиус берётся по ПОЛУДИАГОНАЛИ квадрата зоны, а не по его
## полуширине: круг, вписанный в квадрат, оставил бы углы зоны в темноте
const START_REVEAL_PAD := 8.0

var fog: FogOfWar = null
## Зелёная подсветка «здесь можно поставить замок». Живёт только на время
## выбора места
var _start_zone: MeshInstance3D = null

func _setup_fog() -> void:
	fog = FogOfWar.new()
	fog.name = "FogOfWar"
	_world.add_child(fog)
	fog.setup(MAP_HALF_X, MAP_HALF_Z)
	GameManager.fog = fog

## Раскрыть стартовую площадку НАВСЕГДА — ещё до того, как поставлен замок и
## появились свои юниты. Без этого игрок в первые секунды выбирает место под
## крепость в сплошной серой пелене
func _reveal_start_area() -> void:
	if fog == null:
		return
	fog.reset()
	var r: float = PLAYER_PLACE_HALF * sqrt(2.0) + START_REVEAL_PAD
	fog.add_permanent_reveal(PLAYER_BASE_ANCHOR, r)

## Зелёная плашка на земле: внутри неё можно ставить стартовый замок.
## Ровно тот же квадрат, что зажимает clamp_to_player_start, — подсказка не
## должна расходиться с правилом, которое она показывает
func _show_start_zone() -> void:
	_hide_start_zone()
	var quad := QuadMesh.new()
	quad.size = Vector2(PLAYER_PLACE_HALF * 2.0, PLAYER_PLACE_HALF * 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# СВЕЧЕНИЕ, А НЕ ЗАЛИВКА, И ОЧЕНЬ СЛАБОЕ.
	# Первый заход красил плашку обычной альфой 0.16 — зелёное по зелёной
	# траве, подсветку было буквально не найти. Второй ушёл в другую крайность:
	# аддитивное свечение в полную силу, а партия открывается НА ПРЕДЕЛЕ
	# ПРИБЛИЖЕНИЯ, где вся видимая земля лежит внутри зоны — экран заливало
	# кислотно-зелёным целиком. Нужен именно лёгкий подмес: он читается как
	# «здесь можно», не споря с травой и не мешая разглядеть место
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode   = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.035, 0.11, 0.045, 1.0)
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	# Плашка лежит НА земле и обязана рисоваться поверх травы, но ПОД туманом
	# (иначе подсветка светилась бы сквозь пелену за пределами раскрытой зоны)
	mat.no_depth_test = true
	mat.render_priority = 4
	quad.material = mat
	_start_zone = MeshInstance3D.new()
	_start_zone.name = "StartZone"
	_start_zone.mesh = quad
	_start_zone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_start_zone.position = Vector3(PLAYER_BASE_ANCHOR.x, 0.04, PLAYER_BASE_ANCHOR.z)
	_start_zone.extra_cull_margin = 4096.0
	_world.add_child(_start_zone)

func _hide_start_zone() -> void:
	if _start_zone != null and is_instance_valid(_start_zone):
		_start_zone.queue_free()
	_start_zone = null

# ─────────────────────────────────────────────────────────────────────────────
# CASTLE PLACEMENT  — использует _input(), чтобы клик не съедался UI
# ─────────────────────────────────────────────────────────────────────────────

## Начать выбор места под замок.
## free = true — СТАРТОВЫЙ замок: он не стоит ресурсов и ставится в начале
## партии, поэтому списывать за него нечего и возвращать при отмене тоже
func enter_castle_placement(free: bool = false) -> void:
	if _phase != Phase.PLAYING:
		return
	# ЗАМОК СТАВИТСЯ БЕСПЛАТНО — и стартовый, и любой следующий (заказ владельца).
	# Здесь списывалось 300 дерева и 200 золота, причём числами прямо в коде, мимо
	# балансной таблицы. Возвращать при отмене тоже нечего, поэтому _placing_refund
	# пуст в обоих случаях. Аргумент free оставлен: на него завязаны вызовы
	_placing_refund = {}
	_phase = Phase.PLACING_CASTLE
	_create_ghost()
	# Зелёная подсветка разрешённой площадки — только у СТАРТОВОГО замка:
	# он один зажат в угол игрока (clamp_to_player_start), последующие ставятся
	# где угодно, и рисовать им квадрат было бы прямой ложью
	if not _castle_placed:
		_show_start_zone()
	hud.show_placement_hint()

## СИНИЙ ФАНТОМ ЗАМКА. Сначала пробуем настоящий спрайт крепости, залитый
## синим и полупрозрачный, — игрок видит именно то здание, которое ставит.
## Если спрайта нет, остаётся прежний каркас из коробки и четырёх башен
func _create_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.name = "CastleGhost"

	var sprite_path: String = GameManager.building_sprite_path(
		Constants.FACTION_PLAYER, "castle")
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		var tex := load(sprite_path) as Texture2D
		if tex != null:
			var size: Vector3 = _UCfg.building_size("castle")
			var quad := QuadMesh.new()
			# Пропорции — по самой картинке, как и у настоящей постройки
			# (см. Building.sprite_quad_size): фантом обязан выглядеть ровно
			# тем, что встанет на его место
			quad.size = Building.sprite_quad_size(tex, size)
			var gm := StandardMaterial3D.new()
			gm.albedo_texture   = tex
			# Синева и прозрачность: фантом читается как чертёж, а не как
			# готовая постройка, и не спорит с настоящими зданиями за внимание
			gm.albedo_color     = Color(0.35, 0.65, 1.0, 0.55)
			gm.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.cull_mode        = BaseMaterial3D.CULL_DISABLED
			gm.depth_draw_mode  = BaseMaterial3D.DEPTH_DRAW_DISABLED
			quad.material = gm
			var sp := MeshInstance3D.new()
			sp.name = "GhostSprite"
			sp.mesh = quad
			# Та же компенсация наклона камеры, что и у настоящей постройки
			# (BillboardUtil.V_STRETCH). У фантома обычный StandardMaterial3D,
			# а не cyl_billboard, поэтому тянем сам узел: фантом обязан
			# выглядеть ровно тем, что встанет на его место
			sp.scale.y = _BBUtil.V_STRETCH
			sp.position.y = quad.size.y * 0.5 * _BBUtil.V_STRETCH
			_ghost.add_child(sp)
			# Кольцо на земле: точно видно, КУДА встанет здание
			var foot := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = maxf(size.x, size.z) * 0.5
			tor.outer_radius = maxf(size.x, size.z) * 0.5 + 0.35
			foot.mesh = tor
			var fm := StandardMaterial3D.new()
			fm.albedo_color   = Color(0.40, 0.75, 1.0, 0.75)
			fm.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
			foot.material_override = fm
			foot.position.y = 0.08
			_ghost.add_child(foot)
			_ghost.position.y = 0.0
			add_child(_ghost)
			return

	# Видимый полупрозрачный замок-призрак: большой box + 4 башни
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(8.0, 6.0, 8.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(0.35, 0.65, 1.0, 0.55)
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	box_mesh.material = mat
	var keep_mi := MeshInstance3D.new()
	keep_mi.mesh = box_mesh; keep_mi.position.y = 3.0
	_ghost.add_child(keep_mi)

	for corner in [Vector3(-4,0,-4), Vector3(4,0,-4), Vector3(-4,0,4), Vector3(4,0,4)]:
		var t := MeshInstance3D.new()
		var tc := CylinderMesh.new(); tc.top_radius = 1.0; tc.bottom_radius = 1.0; tc.height = 7.5
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.30, 0.60, 1.0, 0.50)
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tc.material = tm; t.mesh = tc
		t.position  = corner + Vector3(0, 3.75, 0)
		_ghost.add_child(t)

	_ghost.position.y = 0.0
	add_child(_ghost)

func _input(event: InputEvent) -> void:
	# ── ALT: ТУМБЛЕР ПОЛОСОК ЗДОРОВЬЯ ───────────────────────────────────────
	# Ловим в _input, а не в _unhandled_input: над полем висит HUD, и клавиша,
	# нажатая пока курсор на панели, до необработанного ввода не доходила бы.
	# echo отсекаем обязательно — зажатый Alt сыплет повторами, и полоски
	# мигали бы с частотой автоповтора вместо одного переключения.
	# keycode ИЛИ physical_keycode: на не-латинских раскладках keycode едет,
	# physical привязан к самой клавише и покрывает и левый, и правый Alt
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ALT or k.physical_keycode == KEY_ALT:
			GameManager.toggle_hp_bars()
			get_viewport().set_input_as_handled()
			return
		# ── F3: ТУМБЛЕР СЧЁТЧИКА FPS ────────────────────────────────────────
		if (k.keycode == KEY_F3 or k.physical_keycode == KEY_F3) and hud:
			hud.toggle_fps_counter()
			get_viewport().set_input_as_handled()
			return
		# ── F11 / Alt+Enter: ТУМБЛЕР FULLSCREEN / WINDOWED ─────────────────
		var alt_enter: bool = (k.keycode == KEY_ENTER or k.physical_keycode == KEY_ENTER) \
			and (k.alt_pressed or Input.is_key_pressed(KEY_ALT))
		if k.keycode == KEY_F11 or k.physical_keycode == KEY_F11 or alt_enter:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
	if _phase != Phase.PLACING_CASTLE and _phase != Phase.PLACING_BUILDING:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _phase == Phase.PLACING_CASTLE:
				_try_place_castle(event.position)
			else:
				_try_place_building(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_or_keep_placing()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_or_keep_placing()
		get_viewport().set_input_as_handled()

## ОТМЕНА РАЗМЕЩЕНИЯ — НО НЕ ДЛЯ ПЕРВОГО ЗАМКА.
## Пока стартовая крепость не поставлена, отменять нечего: без неё партия
## нежизнеспособна (нет ни производства рабочих, ни точки сдачи ресурсов), а
## обратно в режим постройки игрока никто не вернёт — случайный ПКМ в первую
## секунду матча оставлял его в тупике с пустой картой. Поэтому здесь ПКМ и
## Escape просто игнорируются, и фантом остаётся под курсором до успешной
## установки. Все ОСТАЛЬНЫЕ постройки (и замки после первого) отменяются как
## прежде, с возвратом ресурсов
func _cancel_or_keep_placing() -> void:
	if _phase == Phase.PLACING_CASTLE and not _castle_placed:
		return
	_refund_and_cancel()

func _cancel_placement() -> void:
	if _ghost:
		_ghost.queue_free(); _ghost = null
	_phase = Phase.PLAYING
	hud.hide_placement_hint()
	_hide_start_zone()

func _refund_and_cancel() -> void:
	for res_type in _placing_refund:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, res_type as int, _placing_refund[res_type] as float)
	_placing_refund = {}
	_cancel_placement()

# Called by GameManager when player clicks a build button for Smithy/Barracks/Mine
func enter_building_placement(cost: Dictionary, ghost_size: Vector3, build_fn: Callable, building_name: String = "Здание") -> void:
	if _phase != Phase.PLAYING:
		return
	_placing_build_fn = build_fn
	_placing_refund   = cost
	_phase = Phase.PLACING_BUILDING
	_create_building_ghost(ghost_size)
	hud.show_placement_hint(building_name)

# ─────────────────────────────────────────────────────────────────────────────
# ЗОНА ЗАСТРОЙКИ
# Строить можно только рядом со своим замком: база растёт вокруг столицы, а не
# расползается кляксами по всей карте. Фантом сам показывает, можно ли здесь
# ставить — красный значит нельзя, и клик в этом месте не сработает.
# ─────────────────────────────────────────────────────────────────────────────
## Радиус застройки вокруг замка, метры
const BUILD_RADIUS := 50.0
## Цвета фантома: разрешено / запрещено
const GHOST_OK   := Color(0.35, 0.65, 1.0, 0.55)
const GHOST_BAD  := Color(1.0, 0.25, 0.20, 0.55)

## Материалы фантома, которым надо перекрашиваться при движении курсора
var _ghost_mats: Array = []
## Разрешено ли строить в текущей точке под курсором
var _ghost_ok: bool = true

## Точка в зоне застройки хоть одного своего замка?
func in_build_radius(x: float, z: float) -> bool:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		var c := b as Castle
		if c == null or c.is_dead():
			continue
		if Vector2(x - c.global_position.x, z - c.global_position.z).length() <= BUILD_RADIUS:
			return true
	return false

## Перекрасить фантом под текущее место: синий — можно, красный — нельзя
func _tint_ghost(ok: bool) -> void:
	if ok == _ghost_ok:
		return
	_ghost_ok = ok
	var col: Color = GHOST_OK if ok else GHOST_BAD
	for m in _ghost_mats:
		var mat := m as StandardMaterial3D
		if mat != null:
			mat.albedo_color = col

func _create_building_ghost(ghost_size: Vector3) -> void:
	if _ghost:
		_ghost.queue_free()
	_ghost_mats.clear()
	_ghost_ok = true
	_ghost = MeshInstance3D.new()
	_ghost.name = "BuildingGhost"
	var box := BoxMesh.new()
	box.size = ghost_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GHOST_OK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = mat
	_ghost_mats.append(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position.y = ghost_size.y * 0.5
	_ghost.add_child(mi)
	# Кольцо радиуса застройки под фантомом: видно, докуда вообще можно ставить
	var foot := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = maxf(ghost_size.x, ghost_size.z) * 0.5
	tor.outer_radius = maxf(ghost_size.x, ghost_size.z) * 0.5 + 0.3
	foot.mesh = tor
	var fm := StandardMaterial3D.new()
	fm.albedo_color = GHOST_OK
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foot.material_override = fm
	_ghost_mats.append(fm)
	foot.position.y = 0.08
	_ghost.add_child(foot)
	add_child(_ghost)

func _try_place_building(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	if world_pos == Vector3.ZERO:
		return
	# ВНЕ ЗОНЫ СТРОИТЬ НЕЛЬЗЯ. Режим постройки при этом НЕ сбрасывается: игрок
	# просто промахнулся мимо зоны, и отбирать у него фантом за это незачем —
	# пусть подведёт курсор ближе к замку и кликнет ещё раз
	if not in_build_radius(world_pos.x, world_pos.z):
		hud.show_placement_hint("Слишком далеко от Замка!")
		return
	if _ghost:
		_ghost.queue_free(); _ghost = null
	_ghost_mats.clear()
	_phase = Phase.PLAYING
	hud.hide_placement_hint()
	_placing_build_fn.call(world_pos)

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var from := _camera.project_ray_origin(screen_pos)
	var dir  := _camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return Vector3.ZERO
	var t  := -from.y / dir.y
	var wp := from + dir * t
	wp.x = clampf(wp.x, -MAP_CLAMP_X, MAP_CLAMP_X)
	wp.z = clampf(wp.z, -MAP_CLAMP_Z, MAP_CLAMP_Z)
	wp.y = get_terrain_height(wp.x, wp.z)
	return wp

func _try_place_castle(screen_pos: Vector2) -> void:
	if _camera == null:
		return
	var from := _camera.project_ray_origin(screen_pos)
	var dir  := _camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return
	var t         := -from.y / dir.y
	var world_pos := from + dir * t
	var ps: Vector2 = clamp_to_player_start(world_pos.x, world_pos.z)
	world_pos.x   = ps.x
	world_pos.z   = ps.y
	world_pos.y   = get_terrain_height(world_pos.x, world_pos.z)

	if _ghost:
		_ghost.queue_free(); _ghost = null

	_castle_placed = true
	_placing_refund = {}
	# Точку замка выбирает игрок и может ткнуть прямо в рощу или в кучу камней.
	# Расчищаем пятно под здание: генератор про этот клик ничего не знал
	_clear_area_of_resources(world_pos, 7.5)
	_reserve(world_pos, BASE_CLEAR_RADIUS)
	# ЗАМОК СНАЧАЛА СТРОИТСЯ. Вместо готовой крепости на карту встаёт
	# стройплощадка с картинкой Castle_Construction, и уже она через
	# CASTLE_BUILD_SEC подменяет себя настоящим Замком (см. ConstructionSite).
	# Бригада ей не нужна (self_building): рабочих на карте ещё нет, их спавнит
	# сам старт партии, и требуй стройка людей — партия не началась бы вовсе
	var site = _CSite.new()
	site.faction     = Constants.FACTION_PLAYER
	site.target_id   = "castle"
	site.target_name = "Замок"
	site.build_size  = _UCfg.building_size("castle")
	site.build_time  = maxf(_UCfg.building_stat("castle", "build_time", 0.0),
		_UCfg.CASTLE_BUILD_SEC)
	site.self_building = true
	_world.add_child(site)
	site.global_position = world_pos
	site.built.connect(_on_castle_built)

	_phase = Phase.PLAYING
	hud.hide_placement_hint()
	_hide_start_zone()

	# Переместить камеру к стройке, чтобы игрок видел, что происходит
	focus_camera_on(world_pos)

	if selection_manager:
		selection_manager._clear_selection()
		selection_manager._select(site)
		GameManager.on_selection_changed(selection_manager.selected_units)

	_spawn_starting_workers(world_pos, site)

## Замок достроился: выделяем его вместо исчезнувшей площадки, иначе игрок
## остаётся с пустой панелью команд и без кнопок найма.
## И ТОЛЬКО ТЕПЕРЬ бригада расходится по ресурсам — до этого она строила
func _on_castle_built(made) -> void:
	if made == null or not is_instance_valid(made):
		return
	if selection_manager:
		selection_manager._clear_selection()
		selection_manager._select(made)
		GameManager.on_selection_changed(selection_manager.selected_units)
	_send_starting_workers_to_resources(made.global_position)

# ─────────────────────────────────────────────────────────────────────────────
# СТАРТОВАЯ БРИГАДА
#
# Рабочие появляются вместе с ФУНДАМЕНТОМ замка и первым делом СТРОЯТ ЕГО, а не
# разбегаются по жилам. Раньше стройка была self_building (сама себя копила,
# рабочие сразу уходили добывать) — со стороны это выглядело так, будто замок
# растёт сам по себе, пока бригада занимается чем-то другим.
#
# self_building у площадки ОСТАВЛЕН как страховка: если бригаду перебьют или
# игрок уведёт её приказом, стройка всё равно доползёт до конца и партия не
# встанет намертво. Пока рабочие на месте, ветка self_building не работает
# вовсе — ConstructionSite использует её только при builder_count() == 0.
# ─────────────────────────────────────────────────────────────────────────────

## Сколько рабочих даётся на старте и в каком порядке они потом расходятся по
## ресурсам. Длина массива И ЕСТЬ число рабочих — менять здесь, а не в range()
const START_WORKER_RESOURCES := [
	Constants.RESOURCE_WOOD,
	Constants.RESOURCE_WOOD,
	Constants.RESOURCE_STONE,
	Constants.RESOURCE_GOLD,
]

## Стартовая бригада, пока строит замок. Список нужен, чтобы по готовности
## разослать ИМЕННО ЕЁ, а не всех рабочих на карте: к тому моменту замок мог
## успеть нанять ещё людей, и у них свои дела
var _start_crew: Array = []

func _spawn_starting_workers(origin: Vector3, site: Node3D = null) -> void:
	_start_crew.clear()
	var n: int = START_WORKER_RESOURCES.size()
	for i in range(n):
		var angle  := TAU * float(i) / float(n)
		var offset := Vector3(cos(angle) * 3.5, 0.0, sin(angle) * 3.5)
		var w      := Worker.new()
		w.faction  = Constants.FACTION_PLAYER
		_world.add_child(w)
		w.global_position = origin + offset
		# ОДИН РАБОЧИЙ = ОДИН ОТРЯД. Правило «игра оперирует только отрядами»
		# распространяется и на рабочих: иначе их нельзя было бы ни выделить,
		# ни посчитать в панели типов
		GameManager.add_to_squad(GameManager.new_squad(w.faction, "worker"), w)
		_start_crew.append(w)
		if site != null and is_instance_valid(site):
			w.command_build(site)
		else:
			# Площадки нет (замок поставлен готовым — так делают стенды):
			# прежнее поведение, сразу на ресурсы
			_send_worker_to_resource(w, int(START_WORKER_RESOURCES[i]))

## Замок готов — бригада возвращается к обычной работе. Порядок ресурсов тот
## же, что и раньше: двое на лес, один на камень, один на золото
func _send_starting_workers_to_resources(origin: Vector3) -> void:
	for i in range(_start_crew.size()):
		var w = _start_crew[i]
		if w == null or not is_instance_valid(w) or w.is_dead():
			continue
		_send_worker_to_resource(w, int(START_WORKER_RESOURCES[i % START_WORKER_RESOURCES.size()]))
	_start_crew.clear()

func _send_worker_to_resource(w, res_type: int) -> void:
	if w == null or not is_instance_valid(w):
		return
	var target := find_nearest_resource(w.global_position, res_type)
	if target == null:
		target = find_nearest_resource(w.global_position, Constants.RESOURCE_WOOD)
	if target:
		w.command_gather(target)

# ─────────────────────────────────────────────────────────────────────────────
# PROCESS / AI
# ─────────────────────────────────────────────────────────────────────────────

## Под курсором ресурс? Тогда показываем курсор №2 (рука/добыча).
## Опрос идёт РАЗ В CURSOR_POLL секунд, а не каждый кадр: разбор клика гоняет
## лучи по физике, и делать это 60 раз в секунду ради вида курсора незачем
const CURSOR_POLL := 0.08
var _cursor_timer: float = 0.0
var _cursor_on_res: bool = false

func _update_hover_cursor(delta: float) -> void:
	_cursor_timer -= delta
	if _cursor_timer > 0.0:
		return
	_cursor_timer = CURSOR_POLL
	if selection_manager == null or _camera == null:
		return
	# КУРСОР СБОРА — ТОЛЬКО КОГДА КЛИК ДЕЙСТВИТЕЛЬНО СОБЕРЁТ РЕСУРС.
	# Дерево является целью лишь для рабочего (см. SelectionManager.selection_has_worker):
	# у отряда солдат ПКМ по лесу проходит сквозь него на землю, и обещать рукой
	# «здесь можно рубить» там нельзя — курсор врал бы про то, что произойдёт
	if not selection_manager.selection_has_worker():
		if _cursor_on_res:
			_cursor_on_res = false
			var arrow := _UIAssets.cursor(1)
			if arrow != null:
				Input.set_custom_mouse_cursor(arrow, Input.CURSOR_ARROW,
					_UIAssets.cursor_hotspot(1))
		return
	var mask: int = Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS \
		| Constants.LAYER_RESOURCES | Constants.LAYER_GROUND
	var hit: Dictionary = selection_manager._pick_at(
		get_viewport().get_mouse_position(), mask)
	var on_res: bool = hit["target"] is ResourceNode
	if on_res == _cursor_on_res:
		return
	_cursor_on_res = on_res
	# Меняем ИМЕННО стрелку: у Godot нет «текущего» курсора, форма выбирается
	# по состоянию, и подменять надо ту же роль, что стоит по умолчанию
	var idx: int = 2 if on_res else 1
	var tex := _UIAssets.cursor(idx)
	if tex != null:
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW,
			_UIAssets.cursor_hotspot(idx))

func _process(delta: float) -> void:
	_update_hover_cursor(delta)
	if _duck_node and is_instance_valid(_duck_node):
		_duck_node.position.y = 0.45 + sin(Time.get_ticks_msec() * 0.001 * PI) * 0.08
	if _phase == Phase.PLACING_CASTLE or _phase == Phase.PLACING_BUILDING:
		_update_ghost(delta)
	if _phase == Phase.PLAYING:
		# ИИ тикает сам (EnemyAI._process по THINK_INTERVAL из конфига);
		# «волн усиления из воздуха» больше нет — армия только через найм
		_victory_timer += delta
		if _victory_timer >= VICTORY_CHECK_INTERVAL:
			_victory_timer = 0.0
			_check_victory()

func _update_ghost(_delta: float) -> void:
	if _ghost == null or _camera == null:
		return
	var mouse   := get_viewport().get_mouse_position()
	var from    := _camera.project_ray_origin(mouse)
	var dir     := _camera.project_ray_normal(mouse)
	if abs(dir.y) > 0.001:
		var t := -from.y / dir.y
		var wp := from + dir * t
		# СТАРТОВЫЙ ЗАМОК зажимается в угол игрока, ОБЫЧНОЕ здание — только в
		# границы карты: его зону ограничивает не зажим, а радиус от замка,
		# и игрок должен видеть красный фантом там, куда ставить нельзя
		var gs: Vector2
		if _phase == Phase.PLACING_CASTLE:
			gs = clamp_to_player_start(wp.x, wp.z)
		else:
			gs = clamp_to_map(wp.x, wp.z)
		wp.x   = gs.x
		wp.z   = gs.y
		_ghost.global_position = Vector3(wp.x, get_terrain_height(wp.x, wp.z), wp.z)
		# Цвет фантома обычного здания — по зоне застройки. Стартовый замок
		# ставится ДО появления замков вообще, поэтому его не красим
		if _phase == Phase.PLACING_BUILDING:
			_tint_ghost(in_build_radius(wp.x, wp.z))

# Системный курсор заменяется ассетом Cursor_01 из menu UI.
# HOTSPOT — НАСТОЯЩЕЕ ОСТРИЁ, а не угол кадра: точку считает
# UIAssets.cursor_hotspot() по альфе (самый левый непрозрачный пиксель верхней
# непрозрачной строки). С Vector2.ZERO курсор целился углом картинки, и клик
# уходил мимо на несколько пикселей — по краю юнита или мелкой жилы промах был
# стабильным.
## Навести объектив на точку карты. Единая точка входа для всех, кому нужно
## «показать вот это»: постановка замка, плашка простаивающих рабочих в HUD.
## Пределы карты зажимает сама камера (RTSCamera.pan_to)
func focus_camera_on(world_pos: Vector3) -> void:
	if _camera:
		_camera.pan_to(world_pos)

func _apply_custom_cursor() -> void:
	var tex := _UIAssets.cursor(1)
	if tex == null:
		return
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, _UIAssets.cursor_hotspot(1))
	# Рука при наведении на кликабельное — второй вариант курсора
	var hand := _UIAssets.cursor(2)
	if hand != null:
		Input.set_custom_mouse_cursor(hand, Input.CURSOR_POINTING_HAND,
			_UIAssets.cursor_hotspot(2))

# ─────────────────────────────────────────────────────────────────────────────
# КУРСОР НЕ ДОЛЖЕН УБЕГАТЬ НА ВТОРОЙ МОНИТОР
#
# БАГ: скролл краем экрана (RTSCamera._process) читает позицию курсора во
# вьюпорте. На двухмониторной системе курсор спокойно уезжает за правую границу
# окна на соседний экран — координата во вьюпорте при этом остаётся прижатой к
# краю, и камера УЕЗЖАЕТ САМА, пока игрок работает на другом мониторе.
#
# ЛЕЧЕНИЕ: пока окно игры в фокусе, курсор заперт в его пределах
# (MOUSE_MODE_CONFINED — видимый, но не покидающий окно). При потере фокуса
# ограничение СНИМАЕТСЯ, иначе Alt+Tab и переход на второй монитор стали бы
# невозможны, а окно превратилось бы в ловушку.
#
# Режим CONFINED, а не CONFINED_HIDDEN: свой курсор мы рисуем сами
# (см. _apply_custom_cursor), прятать его нельзя.
# ─────────────────────────────────────────────────────────────────────────────

## В headless-прогонах (стенды qa_*) окна нет вовсе — трогать DisplayServer там
## бессмысленно, а на некоторых сборках ещё и роняет прогон
func _has_window() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("headless")

## F11/Alt+Enter: переключение Fullscreen (exclusive) / Windowed. В headless
## прогонах DisplayServer недоступен — выходим сразу
func _toggle_fullscreen() -> void:
	if not _has_window():
		return
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

## КУРСОР НЕ ЗАПИРАЕТСЯ В ОКНЕ. Здесь стоял _confine_mouse(), ставивший
## Input.MOUSE_MODE_CONFINED по фокусу окна — он лечил «скролл краем экрана
## срабатывает, когда курсор на втором мониторе», но заодно не выпускал курсор
## к полосе заголовка Windows: кнопки свернуть/развернуть/закрыть становились
## недоступны, окно ощущалось зависшим. Скролл краем и без того обесточен,
## когда курсор над любым Control (RTSCamera._process проверяет
## gui_get_hovered_control), так что запирать курсор незачем.

# ─────────────────────────────────────────────────────────────────────────────
# ИИ ПРОТИВНИКА ЖИВЁТ В scripts/EnemyAI.gd, а все его числа — в
# scripts/ai_start_army_limit.gd. Здесь остался только узел-контроллер
# (см. enemy_ai) и точка сбора ai_rally_point().
#
# Прежняя реализация лежала прямо в Main: пофазный найм («5 отрядов копейщиков,
# потом 2 лучников»), патрульные точки и БЕСПЛАТНЫЕ волны усиления из воздуха.
# Всё это убрано: армия ИИ теперь строится только за ресурсы и только до
# лимитов из конфига.
# ─────────────────────────────────────────────────────────────────────────────

func _check_victory() -> void:
	if get_tree().get_nodes_in_group("enemy_buildings").is_empty() and \
	   get_tree().get_nodes_in_group("enemy_units").is_empty():
		_phase = Phase.VICTORY
		hud.show_victory()
	elif _castle_placed and \
		 get_tree().get_nodes_in_group("player_buildings").is_empty() and \
		 get_tree().get_nodes_in_group("player_units").is_empty():
		_phase = Phase.DEFEAT
		hud.show_defeat()

func restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

# ─────────────────────────────────────────────────────────────────────────────
# RESOURCE HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func find_nearest_resource(from_pos: Vector3, res_type: int) -> ResourceNode:
	var nearest: ResourceNode = null
	var best_dist := INF
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(n):
			continue
		if n.resource_type != res_type or n.remaining <= 0.0:
			continue
		var d := from_pos.distance_to(n.global_position)
		if d < best_dist:
			best_dist = d; nearest = n
	return nearest

# ─────────────────────────────────────────────────────────────────────────────
# SPAWNING
# ─────────────────────────────────────────────────────────────────────────────

func _spawn_resource_nodes() -> void:
	_spawn_gold_nodes()
	_spawn_stone_nodes()
	# Колодцы больше не ставятся: вода удалена из игры как ресурс

# Ресурсы по карте раскиданы КУЧАМИ, а не поштучно по заранее забитым точкам.
# Прежние списки координат давали ровные цепочки одинаковых камней — «заборы»;
# теперь центры куч выбираются случайно, а состав каждой кучи берётся из
# пресетов (см. CLUSTER_PRESETS)
const GOLD_CLUSTERS  := 5
const STONE_CLUSTERS := 7

func _spawn_gold_nodes() -> void:
	_scatter_clusters(Constants.RESOURCE_GOLD, GOLD_CLUSTERS)

func _spawn_stone_nodes() -> void:
	_scatter_clusters(Constants.RESOURCE_STONE, STONE_CLUSTERS)
	_add_corner_resource_clusters()

# Разбрасывает count куч по карте, обходя озеро, базу ИИ и уже занятые места
func _scatter_clusters(res_type: int, count: int) -> void:
	var centers: Array = []
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 400:
		attempts += 1
		var cx := randf_range(-RES_HALF_X, RES_HALF_X)
		var cz := randf_range(-RES_HALF_Z, RES_HALF_Z)
		if LAKE_ENABLED and Vector2(cx - LAKE_CENTER.x, cz - LAKE_CENTER.z).length() \
				< LAKE_RADIUS * 1.4 + 5.0:
			continue
		if _is_reserved(cx, cz, 8.0):
			continue                      # пятачок базы — не занимать
		var too_close := false
		for q in centers:
			if Vector2(cx, cz).distance_to(q) < 16.0:
				too_close = true
				break
		if too_close:
			continue
		centers.append(Vector2(cx, cz))
		_spawn_resource_cluster(Vector3(cx, 0.0, cz), res_type)
		placed += 1

# ── ЖИВОПИСНЫЕ КЛАСТЕРЫ КАМНЯ И ЗОЛОТА В УГЛАХ КАРТЫ ─────────────────────────
# По одному кластеру каждого типа возле каждого угла (то есть рядом с базой
# игрока и базой ИИ). Кластер — не россыпь одинаковых кочек, а композиция:
# один КРУПНЫЙ самородок/валун, один средний и два-три мелких осколка вокруг.
# Варианты спрайтов (Gold Stone 1..6 / Rock1..4) разные внутри кластера.
# Центры отсчитываются ОТ УГЛОВ ПОЛЯ по каждой оси: карта прямоугольная,
# и общий множитель здесь дал бы кучи посреди поля по короткой оси
const CORNER_RES_INSET := 22.0
const CORNER_RES_CENTERS := [
	Vector3(-MAP_HALF_X + CORNER_RES_INSET, 0.0, -MAP_HALF_Z + CORNER_RES_INSET),
	Vector3( MAP_HALF_X - CORNER_RES_INSET, 0.0, -MAP_HALF_Z + CORNER_RES_INSET),
	Vector3(-MAP_HALF_X + CORNER_RES_INSET, 0.0,  MAP_HALF_Z - CORNER_RES_INSET),
	Vector3( MAP_HALF_X - CORNER_RES_INSET, 0.0,  MAP_HALF_Z - CORNER_RES_INSET),
]
# ── СОСТАВ КУЧИ: СЛУЧАЙНЫЙ ПРЕСЕТ ───────────────────────────────────────────
# Куча — не решётка и не цепочка, а СНОП: крупные куски в середине, мелочь
# осыпью вокруг, всё с плотным перекрытием. Три разных набора дают кучам
# заметно разную форму и «вес».
## КУЧИ СТАЛИ ЖИРНЕЕ И БОГАЧЕ. Прежние наборы (1-3 крупных куска и горстка
## мелочи) выглядели как случайно оброненные камешки. Теперь в каждой куче
## заметное ядро из крупных самородков и щедрая осыпь вокруг — жила читается
## как месторождение, к которому есть смысл вести бригаду
const CLUSTER_PRESETS := [
	{"big": 3, "mid": 4, "small": 8},
	{"big": 5, "mid": 4, "small": 5},
	{"big": 4, "mid": 2, "small": 10},
]

# Размер и запас по классу куска. Разброс масштаба добавляется сверху,
# поэтому двух одинаковых камней в куче не бывает
# ЗАПАС ×3 к прежнему: жилы золота и каменоломни выдыхались слишком быстро,
# рабочие успевали срыть базовую кучу за пару минут. Значения ниже — уже
# итоговые (было 420 / 250 / 130). Множитель применяется только к КУЧАМ
# (золото и камень) — деревья считают свой запас отдельно, в _spawn_tree_cluster
const PIECE_CLASSES := {
	"big":   {"scale": 1.60, "amount": 1260.0, "jitter": 0.22, "spread": 0.9},
	"mid":   {"scale": 1.05, "amount":  750.0, "jitter": 0.20, "spread": 1.7},
	"small": {"scale": 0.62, "amount":  390.0, "jitter": 0.26, "spread": 2.6},
}

# Минимальный просвет между центрами кусков: намеренно МЕНЬШЕ их радиусов,
# чтобы спрайты перекрывались и куча читалась как единый навал, а не как
# аккуратно расставленные по кругу отдельные камни
const PIECE_MIN_GAP := 0.42

## НАСКОЛЬКО КУЧА ЗОЛОТА ТЕСНЕЕ КАМЕННОЙ — ДВА ОТДЕЛЬНЫХ МНОЖИТЕЛЯ.
##
## Раньше был один общий GOLD_CLUSTER_TIGHTEN = 0.55, применённый и к spread
## (радиус разброса), и к min_gap (просвет между центрами) СРАЗУ. Причина
## была верной — самородки мельче нарисованы, чем глыбы камня, и на радиусе
## камня расползались в редкую россыпь искр — но лекарство задело не то:
## сжатие РАДИУСА у пары десятков кусков "big"/"mid" в куче схлопывало их
## почти в одну точку, и billboard-квады (каждый ~2.5×size_scale м, у "big"
## все 4 м) укладывались друг на друга не вширь, а стопкой — с камеры кажется
## не куча, а «высокий узкий столб». ResourceNode._maybe_load_sprite теперь
## САМ раздувает квад так, чтобы нарисованный кусок был стабильного видимого
## размера независимо от того, сколько пустого поля вокруг него на холсте —
## лекарство от «искр» больше не нужно радиусу, только просвету между
## центрами (перекрытие спрайтов по-прежнему нужно для читаемости навала)
const GOLD_SPREAD_TIGHTEN := 0.85   # было 0.55 — тесный радиус и давал столб
const GOLD_GAP_TIGHTEN    := 0.55   # просвет между кусками — держим плотным

# ── РЕСУРСЫ БАЗЫ ─────────────────────────────────────────────────────────────
# Золото и камень стоят РЯДОМ с замком, но на расчищенном кольце: достаточно
# близко, чтобы рабочие не бегали через полкарты, и достаточно далеко, чтобы
# ни одна куча не пересекалась ни с замком, ни с соседней кучей.
# Ставятся с ТЫЛЬНОЙ стороны базы (от центра карты), чтобы не загораживать
# плац перед замком, откуда выходят войска.
# Радиус чистой земли вокруг СВОЕЙ кучи руды: жила не должна зарастать лесом
const BASE_ORE_CLEAR := 4.5

## Детерминированные точки двух базовых куч: [золото, камень].
## Вынесено в отдельную функцию, чтобы _setup_reserved_zones() могла занять их
## ДО посадки леса, а _add_base_resource_clusters() поставила туда же кучи.
func _base_resource_spots(anchor: Vector3) -> Array:
	# «Наружу» = от центра карты: у игрока это к своему углу, у ИИ — к своему
	var outward := anchor - Vector3.ZERO
	outward.y = 0.0
	if outward.length() < 0.01:
		outward = Vector3.FORWARD
	outward = outward.normalized()
	var base_ang := atan2(outward.z, outward.x)
	var out: Array = []
	# Две кучи разведены на 70° по кольцу: между ними остаётся проход
	for delta_deg in [-35.0, 35.0]:
		var ang: float = base_ang + deg_to_rad(delta_deg)
		var px: float = clampf(anchor.x + cos(ang) * BASE_RESOURCE_DIST, -MAP_CLAMP_X, MAP_CLAMP_X)
		var pz: float = clampf(anchor.z + sin(ang) * BASE_RESOURCE_DIST, -MAP_CLAMP_Z, MAP_CLAMP_Z)
		out.append(Vector3(px, 0.0, pz))
	return out

func _add_base_resource_clusters(anchor: Vector3) -> void:
	var spots := _base_resource_spots(anchor)
	var types := [Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE]
	for i in range(spots.size()):
		var p: Vector3 = spots[i]
		if is_water(p.x, p.z):
			continue
		# Пятачок уже зарезервирован (см. _setup_reserved_zones), но чужие
		# спавнеры могли поставить сюда что-то ДО резерва — подчищаем
		_clear_area_of_resources(p, BASE_ORE_CLEAR)
		_spawn_resource_cluster(p, int(types[i]), true)

# ── ЛЕСНОЙ КАРМАН ВОКРУГ БАЗЫ (ПОДКОВА) ──────────────────────────────────────
# Замок прикрыт густым лесом с ТРЁХ сторон, а перед ним остаётся открытый плац
# под выход войск и стройплощадки. Открытая сторона смотрит в центр карты —
# туда, откуда придёт противник и куда пойдут свои отряды.
# Общая генерация леса при этом не трогается: это ДОПОЛНИТЕЛЬНАЯ полоса.
const POCKET_INNER   := 13.0   # ближе этого к замку деревьев нет (плац + стройка)
const POCKET_OUTER   := 23.0   # внешний край полосы
const POCKET_OPEN_DEG := 120.0 # ширина открытого сектора перед замком
const POCKET_TREES   := 74     # попыток посадки на одну базу

func _add_base_forest_pocket(anchor: Vector3) -> void:
	# Открытая сторона — в центр карты
	var to_center := Vector3.ZERO - anchor
	to_center.y = 0.0
	if to_center.length() < 0.01:
		to_center = Vector3.FORWARD
	var open_ang := atan2(to_center.z, to_center.x)
	var half_open := deg_to_rad(POCKET_OPEN_DEG * 0.5)

	var placed: Array = []
	for _i in range(POCKET_TREES):
		# Угол В ПОДКОВЕ: равномерно по закрытым 240°, мимо открытого сектора
		var t := randf() * (TAU - half_open * 2.0)
		var ang := open_ang + half_open + t
		# Радиус со случайным разбросом — край полосы рваный, не циркульный
		var r := randf_range(POCKET_INNER, POCKET_OUTER)
		var px: float = anchor.x + cos(ang) * r
		var pz: float = anchor.z + sin(ang) * r
		# ГРАНИЦА — ЧЕРЕЗ _fits_in_map, ПО КАЖДОЙ ОСИ СВОЕЙ ПОЛУОСЬЮ.
		# Здесь стоял общий литерал 76.0 — остаток квадратной карты 75 м.
		# После перехода на прямоугольник 260×146.25 базы уехали в углы
		# (|x| якоря = 106), и условие |px| > 76 отбраковывало КАЖДОЕ дерево
		# подковы у обеих баз: все 74 попытки на базу давали ноль
		# посадок, замок стоял в чистом поле (замер qa_world3: в закрытых
		# секторах кольца оставались только деревья углового массива).
		# Заодно 76.0 было БОЛЬШЕ полуоси Z (73.125) — по короткой оси тот же
		# литерал, наоборот, выпускал бы деревья за край поля
		if not _fits_in_map(px, pz):
			continue
		if is_water(px, pz):
			continue
		if _is_reserved(px, pz):
			continue
		# Плотно, но без совпадений стволов
		var cand := Vector2(px, pz)
		var ok := true
		for q in placed:
			if cand.distance_to(q) < 1.25:
				ok = false
				break
		if not ok:
			continue
		placed.append(cand)
		var tree := ResourceNode.new()
		tree.resource_type = Constants.RESOURCE_WOOD
		tree.remaining     = randf_range(480.0, 720.0)
		tree.tree_variant  = randi_range(1, 4)
		_world.add_child(tree)
		tree.global_position = Vector3(px, get_terrain_height(px, pz), pz)

func _add_corner_resource_clusters() -> void:
	for c in CORNER_RES_CENTERS:
		var center: Vector3 = c
		# Угол вражеской базы: отодвигаем кластеры, чтобы не зарасти плац,
		# откуда выходят отряды (замок ИИ стоит в 55,55)
		if center.x > 0.0 and center.z > 0.0:
			center += Vector3(10.0, 0.0, -4.0)
		# Центр кластера отодвигаем от базы ЦЕЛИКОМ, а не режем по куску:
		# иначе угловая куча вставала вплотную к границе safe zone «откушенным»
		# краем и держалась только на пер-кусочной отсечке
		var gold_c := center + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		if not _is_reserved(gold_c.x, gold_c.z, 8.0):
			_spawn_resource_cluster(gold_c, Constants.RESOURCE_GOLD)
		# Камень — поодаль от золота, чтобы кучи читались раздельно
		var away: float = -1.0 if center.x > 0.0 else 1.0
		var stone_c := center + Vector3(randf_range(9, 14) * away, 0, randf_range(-5, 5))
		if not _is_reserved(stone_c.x, stone_c.z, 8.0):
			_spawn_resource_cluster(stone_c, Constants.RESOURCE_STONE)

# Одна КУЧА: снопом, с плотным перекрытием и случайным составом.
# Крупные куски садятся у самого центра, средние чуть шире, мелочь — осыпью
# по краю. Куча слегка сплюснута в случайную сторону (эллипс), поэтому две
# соседние кучи никогда не выглядят одинаково.
# ignore_reserved = true — куча ставится В зарезервированный пятачок. Так
# спавнятся СВОИ базовые жилы: их пятачок занят специально под них (лес туда
# не лезет), и общая проверка _is_reserved отвергла бы каждый кусок.
func _spawn_resource_cluster(center: Vector3, res_type: int, ignore_reserved: bool = false) -> void:
	var preset: Dictionary = CLUSTER_PRESETS[randi() % CLUSTER_PRESETS.size()]
	# Ориентация и сплюснутость кучи — свои у каждой
	var ell_ang   := randf() * TAU
	var squash    := randf_range(0.62, 1.0)
	var placed_pts: Array = []
	# Золото собираем теснее камня — см. GOLD_SPREAD_TIGHTEN/GOLD_GAP_TIGHTEN
	var spread_tighten: float = GOLD_SPREAD_TIGHTEN \
		if res_type == Constants.RESOURCE_GOLD else 1.0
	var gap_tighten: float = GOLD_GAP_TIGHTEN \
		if res_type == Constants.RESOURCE_GOLD else 1.0

	for cls in ["big", "mid", "small"]:
		var cls_id: String = cls
		var n: int = int(preset.get(cls_id, 0))
		if n <= 0:
			continue
		var pc: Dictionary = PIECE_CLASSES[cls_id]
		var base_scale: float = pc.get("scale", 1.0)
		var amount: float     = pc.get("amount", 200.0)
		var jitter: float     = pc.get("jitter", 0.2)
		var spread: float     = float(pc.get("spread", 1.5)) * spread_tighten

		for i in range(n):
			var pt := Vector2.ZERO
			# Несколько попыток найти точку, не совпадающую с уже занятой.
			# Порог маленький (PIECE_MIN_GAP) — перекрытие спрайтов ЖЕЛАТЕЛЬНО.
			# Просвет ужимается СВОИМ множителем (gap_tighten), НЕЗАВИСИМО от
			# радиуса разброса: иначе на тесном круге золота ни одна точка не
			# проходит проверку, цикл отваливается по числу попыток и валит
			# все куски в Vector2.ZERO — то есть стопкой
			var min_gap: float = PIECE_MIN_GAP * gap_tighten
			for _try in range(14):
				var ang := randf() * TAU
				# r = R·√u даёт равномерное заполнение диска, а не сгусток в центре
				var r   := sqrt(randf()) * spread
				var cand := Vector2(cos(ang) * r, sin(ang) * r * squash).rotated(ell_ang)
				var ok := true
				for q in placed_pts:
					if cand.distance_to(q) < min_gap:
						ok = false
						break
				if ok:
					pt = cand
					break
			placed_pts.append(pt)

			var px: float = center.x + pt.x
			var pz: float = center.z + pt.y
			if is_water(px, pz):
				continue
			# Куски, попавшие на пятачок базы, не ставим — замок не должен
			# торчать из кучи камней
			if not ignore_reserved and _is_reserved(px, pz):
				continue
			var node := ResourceNode.new()
			node.resource_type = res_type
			# Разброс масштаба: одинаковых кусков в куче не бывает
			var sc: float = base_scale * randf_range(1.0 - jitter, 1.0 + jitter)
			node.size_scale  = sc
			# Запас пропорционален размеру — крупный самородок и даёт больше
			node.remaining   = amount * (sc / base_scale)
			node.res_variant = 0     # 0 = вариант спрайта выберется случайно
			_world.add_child(node)
			node.global_position = Vector3(px, get_terrain_height(px, pz), pz)

func _spawn_enemy_base() -> void:
	var castle := Castle.new()
	castle.faction = Constants.FACTION_ENEMY
	_world.add_child(castle)
	# ЗАМОК СТАВИТСЯ РОВНО В СВОЙ ЯКОРЬ. Здесь стояли литералы (55, 55) — они
	# остались от карты 75 м и НЕ разъехались вместе с ENEMY_BASE_ANCHOR
	# (55 × MAP_GROWTH = 71.5). В итоге расчищенная зона базы, своя жила золота
	# и своя каменоломня (_setup_reserved_zones / _add_base_resource_clusters
	# считают всё от якоря) оказывались в 16 м от замка, а сам замок вырастал
	# посреди леса и камней, которые генератор спокойно сажал в незарезервированной
	# точке (55, 55)
	var anchor: Vector3 = ENEMY_BASE_ANCHOR
	castle.global_position = Vector3(anchor.x, get_terrain_height(anchor.x, anchor.z), anchor.z)

	# Стартовые рабочие — СТОЛЬКО ЖЕ, сколько у игрока (AICfg.START_WORKERS).
	# Типы ресурсов чередуются по кругу, чтобы никто не дублировал соседа
	var res_types := [
		Constants.RESOURCE_WOOD,
		Constants.RESOURCE_WOOD,
		Constants.RESOURCE_GOLD,
		Constants.RESOURCE_STONE,
	]
	for i in range(_AICfg.START_WORKERS):
		var w := Worker.new()
		w.faction = Constants.FACTION_ENEMY
		_world.add_child(w)
		# Смещения отсчитываются ОТ ЯКОРЯ базы, а не от прежних литералов:
		# рабочие обязаны появляться у своего замка, куда бы тот ни уехал
		var wx: float = anchor.x - 3.0 + float(i % 2) * 3.0
		var wz: float = anchor.z - 5.0 + float(i / 2) * 2.0
		w.global_position = Vector3(wx, get_terrain_height(wx, wz), wz)
		# Стартовые рабочие ИИ — тоже отряды из одного (см. _spawn_starting_workers)
		GameManager.add_to_squad(GameManager.new_squad(w.faction, "worker"), w)
		var res_type: int = res_types[i % res_types.size()]
		var target := find_nearest_resource(w.global_position, res_type)
		if target == null:  # запасной вариант — дерево
			target = find_nearest_resource(w.global_position, Constants.RESOURCE_WOOD)
		if target:
			w.command_gather(target)

	# СТАРТОВЫХ ВОЙСК У ИИ НЕТ ВООБЩЕ: замок и рабочие, как у игрока.
	# Армия появляется только через очередь найма и только за ресурсы —
	# бесплатные «волны усиления» из прежней версии удалены.

# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT / TERRAIN
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# СВЕТ: ОДНО СОЛНЦЕ И РОВНАЯ ЗАЛИВКА
#
# БЫЛО ДВА ВСТРЕЧНЫХ ИСТОЧНИКА: тёплое солнце с юго-запада и холодная синяя
# подсветка почти с противоположной стороны. На пологих волнах рельефа их
# вклады складывались в чередующиеся тёплые и холодные полосы вдоль гребней —
# то самое «полосатое/тигровое» поле из отчёта. Второй направленный свет
# делал ровно то, для чего в 3D обычно служит АМБИЕНТ, только неравномерно.
#
# СТАЛО КАК В «КАЗАКАХ 3»: ОДИН направленный источник под пологим углом с
# юго-запада плюс ровная полусферическая заливка неба. Тени от рельефа мягкие
# и однонаправленные, полос нет по построению — их нечему создавать.
#
# Вторая половина той же проблемы — нормали земли; они чинятся в
# _build_flat_terrain() (см. terrain_normal).
# ─────────────────────────────────────────────────────────────────────────────
## Угол солнца: наклон к горизонту и поворот. 48° — свет, при котором у
## построек читаются и фасад, и скат крыши, а спрайты не выглядят плоскими
const SUN_PITCH := -48.0
const SUN_YAW   := -40.0

func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(SUN_PITCH, SUN_YAW, 0.0)
	# Энергия чуть ниже прежней (было 1.4): вместе с поднятым амбиентом это даёт
	# ту же общую яркость, но без пересвета склонов, обращённых к солнцу
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.86)
	# Тени от направленного света ВЫКЛЮЧЕНЫ СОЗНАТЕЛЬНО. Юниты, деревья и
	# постройки здесь — плоские билборды; они отбросили бы прямоугольные тени
	# от квадов, а не силуэты фигур. Плюс в GL Compatibility карта теней на
	# пологом рельефе даёт ступенчатую рябь — ровно тот эффект, от которого
	# мы тут избавляемся. Мягкая тень под ногами рисуется отдельно
	sun.shadow_enabled = false
	add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	# BG_SKY is not supported in GL Compatibility — use BG_COLOR instead
	env.background_mode  = Environment.BG_COLOR
	env.background_color = Color(0.38, 0.58, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Заливка холодная и РОВНАЯ — она заменила прежний встречный синий прожектор.
	# Ровная по определению: у амбиента нет направления, а значит нет и полос
	env.ambient_light_color  = Color(0.70, 0.77, 0.92)
	env.ambient_light_energy = 0.72
	env_node.environment = env
	add_child(env_node)

func _setup_terrain() -> void:
	var ground_body := StaticBody3D.new()
	ground_body.name = "Ground"
	ground_body.collision_layer = Constants.LAYER_GROUND
	ground_body.collision_mask  = 0
	var col   := CollisionShape3D.new()
	# Коллайдер земли ровно по игровому полю: клик за краем карты больше не
	# даёт точку на грунте и не превращается в приказ идти в черноту
	var shape := BoxShape3D.new()
	shape.size = Vector3(MAP_HALF_X * 2.0, 0.2, MAP_HALF_Z * 2.0)
	col.shape = shape; col.position.y = -0.1
	ground_body.add_child(col); _world.add_child(ground_body)
	_build_flat_terrain()
	_build_world_edge()
	# ЗОНЫ РЕЗЕРВИРУЮТСЯ ЗДЕСЬ, а не только в start_game(): лес сажается из
	# _ready() ДО start_game(), и раньше на момент посадки список зон был пуст —
	# роща спокойно вырастала прямо на пятачке базы игрока
	_setup_reserved_zones()
	_add_forest_clusters()
	_spawn_water_body()
	_spawn_bushes()
	_spawn_clouds()

func _add_forest_clusters() -> void:
	# Естественные рощи: случайные центры по карте, деревья рассыпаны в диске,
	# размер и плотность рощи случайные — никаких прямых линий
	# ×2 к прежним 14 — карта заметно более лесистая
	# Плотность леса сохранена: площадь выросла на 69% (1.3² по двум осям),
	# столько же добавлено рощ — иначе расширенная карта вышла бы голой степью
	# ГУСТОЙ ЛЕС ПО ВСЕЙ КАРТЕ, А НЕ ТОЛЬКО У БАЗ. Раньше плотные массивы
	# росли только вокруг замков и в углах, а середина карты оставалась
	# редколесьем — «густые кластеры, как у замка» и просили распространить
	# на всё поле. Рощ стало в полтора раза больше, каждая — заметно плотнее
	var target_clusters := int(42.0 * MAP_GROWTH * MAP_GROWTH)
	var placed   := 0
	var attempts := 0
	while placed < target_clusters and attempts < 1400:
		attempts += 1
		var cx := randf_range(-GEN_HALF_X, GEN_HALF_X)
		var cz := randf_range(-GEN_HALF_Z, GEN_HALF_Z)
		# Не заслонять озеро (радиус берега + запас на разброс рощи)
		if LAKE_ENABLED and Vector2(cx - LAKE_CENTER.x, cz - LAKE_CENTER.z).length() \
				< LAKE_RADIUS * 1.35 + 4.0:
			continue
		# Не застраивать базу врага
		if cx > ENEMY_BASE_ANCHOR.x - 17.0 and cz > ENEMY_BASE_ANCHOR.z - 17.0:
			continue
		# Не сажать рощу на базу
		if _is_reserved(cx, cz, 6.0):
			continue
		# Деревьев в роще вдвое больше, а просвет между стволами вдвое меньше
		# (0.85 вместо 1.7): роща читается как чаща, а не как редкие кустики
		_spawn_tree_cluster(Vector3(cx, 0.0, cz), randi_range(11, 24),
			randf_range(3.5, 8.0), 0.85)
		placed += 1
	_add_corner_forests()
	# Подкова густого леса вокруг каждой базы — ПОВЕРХ общей генерации,
	# ничего из неё не отменяя
	_add_base_forest_pocket(PLAYER_BASE_ANCHOR)
	_add_base_forest_pocket(ENEMY_BASE_ANCHOR)

# ── ГУСТЫЕ ЛЕСНЫЕ МАССИВЫ В 4 УГЛАХ КАРТЫ ────────────────────────────────────
# Относительно обычной рощи: ПЛОЩАДЬ ×3 (радиус ×√3) и ПЛОТНОСТЬ ×2,
# то есть деревьев ×6. Минимальный просвет между стволами тоже вдвое меньше —
# без этого частокол упёрся бы в дистанцию 1.7 и плотность не выросла бы.
const CORNER_AREA_MULT    := 3.0
const CORNER_DENSITY_MULT := 2.0
# Центры массивов: чуть внутрь от границы карты (±80)
const CORNER_FOREST_INSET := 17.0
const CORNER_CENTERS := [
	Vector3(-MAP_HALF_X + CORNER_FOREST_INSET, 0.0, -MAP_HALF_Z + CORNER_FOREST_INSET),
	Vector3( MAP_HALF_X - CORNER_FOREST_INSET, 0.0, -MAP_HALF_Z + CORNER_FOREST_INSET),
	Vector3(-MAP_HALF_X + CORNER_FOREST_INSET, 0.0,  MAP_HALF_Z - CORNER_FOREST_INSET),
	Vector3( MAP_HALF_X - CORNER_FOREST_INSET, 0.0,  MAP_HALF_Z - CORNER_FOREST_INSET),
]

func _add_corner_forests() -> void:
	var radius_mult: float = sqrt(CORNER_AREA_MULT)          # площадь ×3
	var count_mult:  float = CORNER_AREA_MULT * CORNER_DENSITY_MULT   # ×6 деревьев
	for c in CORNER_CENTERS:
		var center: Vector3 = c
		# Угол вражеской базы (+X,+Z): массив сдвинут наружу, чтобы не зарасти
		# по замку и плацу, откуда выходят отряды
		if center.x > 0.0 and center.z > 0.0:
			center += Vector3(8.0, 0.0, 8.0)
		# Три перекрывающихся пятна вместо одного круга — край леса рваный,
		# без «циркульной» границы
		for i in range(3):
			var jitter := Vector3(randf_range(-7.0, 7.0), 0.0, randf_range(-7.0, 7.0))
			var radius: float = randf_range(5.0, 8.0) * radius_mult
			var count:  int   = int(randf_range(7.0, 11.0) * count_mult)
			_spawn_tree_cluster(center + jitter, count, radius, 0.85)

# Овальная роща: деревья рассыпаны по эллипсу со случайной ориентацией,
# с минимальной дистанцией между стволами — никаких рядов/«заборов».
# Каждое дерево — отдельный StaticBody3D (ResourceNode), зафиксированный
# в мировых координатах; billboard только на его собственном спрайте.
# min_gap — минимальный просвет между стволами: чем он меньше, тем гуще лес
func _spawn_tree_cluster(center: Vector3, count: int, radius: float = 5.5, min_gap: float = 1.7) -> void:
	var ell_ang   := randf() * TAU                 # ориентация эллипса рощи
	var rz_factor := randf_range(0.6, 1.0)         # сжатие: 1.0 = круг, 0.6 = овал
	var placed_pts: Array = []
	for i in range(count):
		var pt := Vector2.ZERO
		var ok := false
		for _attempt in range(10):
			# Равномерная точка в диске (r = R·√u) → эллипс → поворот
			var ang  := randf() * TAU
			var r    := sqrt(randf())
			var cand := Vector2(cos(ang) * r * radius, sin(ang) * r * radius * rz_factor).rotated(ell_ang)
			ok = true
			for q in placed_pts:
				if cand.distance_to(q) < min_gap:
					ok = false
					break
			if ok:
				pt = cand
				break
		if not ok:
			continue
		placed_pts.append(pt)
		# Дерево, попавшее на безопасную зону базы, просто не сажаем —
		# так роща обтекает базу, а не срезается ровным краем
		if _is_reserved(center.x + pt.x, center.z + pt.y):
			continue
		# И не сажаем за краем мира: угловые массивы с их разлётом легко
		# выплёскивались наружу, и стволы висели в черноте
		if not _fits_in_map(center.x + pt.x, center.z + pt.y):
			continue
		var tree := ResourceNode.new()
		tree.resource_type = Constants.RESOURCE_WOOD
		tree.remaining     = randf_range(480.0, 720.0)   # 3x ёмкость
		tree.tree_variant  = randi_range(1, 4)
		_world.add_child(tree)
		var px := center.x + pt.x
		var pz := center.z + pt.y
		tree.global_position = Vector3(px, get_terrain_height(px, pz), pz)

func _setup_camera() -> RTSCamera:
	# Иерархия: Main → CameraPivot (Node3D, ЕДИНСТВЕННЫЙ вращающийся узел)
	#                    └── Camera3D (смотрит на пивот под углом)
	# Мир (World) при этом никогда не трансформируется.
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	add_child(pivot)
	var camera := RTSCamera.new()
	pivot.add_child(camera)
	# Отдаём камере СЫРУЮ половину карты — сам отступ под текущий зум и
	# соотношение сторон экрана она теперь считает внутри (RTSCamera._clamp_focus)
	camera.set_bounds(MAP_HALF_X - MAP_EDGE_MARGIN, MAP_HALF_Z - MAP_EDGE_MARGIN)
	camera.make_current()
	# ТОЧКА СЛУХА — НА ЗЕМЛЕ В ФОКУСЕ, А НЕ НА КАМЕРЕ. В ортографии камера
	# унесена на 400 м назад (RTSCamera.ORTHO_DISTANCE), и как слушатель она
	# бесполезна: любой 3D-звук оказался бы дальше max_distance. Слушатель —
	# ребёнок пивота, то есть всегда стоит там, куда игрок смотрит. Отсюда и
	# нужное поведение: подвёл камеру к рабочим — слышно топоры, увёл — тишина
	var listener := AudioListener3D.new()
	listener.name = "Listener"
	listener.position = Vector3(0.0, 2.0, 0.0)
	pivot.add_child(listener)
	listener.make_current()
	return camera

# ─────────────────────────────────────────────────────────────────────────────
# РЕЛЬЕФ
#
# Поле было ОДНИМ квадратом сплошного цвета. В ортографии, где нет ни схождения
# перспективы, ни изменения размера с расстоянием, такая земля читается ровно
# как «плоская школьная доска»: ни одной опорной точки для глаза.
#
# Здесь земля становится настоящей поверхностью: сетка вершин с плавными
# пологими волнами. Свет падает на склоны под разными углами — и появляется
# светотень, то есть ОБЪЁМ. Никаких текстур для этого не нужно.
#
# ВЫСОТА СЧИТАЕТСЯ АНАЛИТИЧЕСКИ (сумма синусов), а не хранится в карте высот.
# Это принципиально: get_terrain_height() обязан возвращать РОВНО ту же высоту,
# что и вершина меша, иначе бойцы поедут под землю или повиснут в воздухе.
# Одна функция — один источник правды и для картинки, и для игры.
#
# АМПЛИТУДА НАМЕРЕННО МАЛА (RELIEF_AMP). Волны дают светотень, но не мешают
# игре: движение остаётся плоским по XZ, дистанции и формации не плывут,
# разбор клика по плоскости y=0 ошибается меньше чем на метр.
# ─────────────────────────────────────────────────────────────────────────────
## Выключатель рельефа. false — прежняя идеально плоская доска
const TERRAIN_RELIEF := true
## Высота волн, метры (от впадины до гребня — вдвое больше)
const RELIEF_AMP := 0.85
## Шаг сетки вершин, метры. Мельче — плавнее свет, но больше треугольников
const RELIEF_STEP := 2.5

## ЕДИНСТВЕННЫЙ ИСТОЧНИК ВЫСОТЫ: и для меша земли, и для всего, что на ней стоит
func get_terrain_height(x: float, z: float) -> float:
	if not TERRAIN_RELIEF:
		return 0.0
	# Три несоизмеримые гармоники: узор не повторяется на глаз и не даёт
	# «стиральной доски» — ни одной прямой линии гребней
	return RELIEF_AMP * (
		  0.55 * sin(x * 0.031 + z * 0.017)
		+ 0.30 * sin(x * 0.013 - z * 0.041 + 1.7)
		+ 0.15 * sin(x * 0.077 + z * 0.059 + 3.1))

# ─────────────────────────────────────────────────────────────────────────────
# НОРМАЛЬ ЗЕМЛИ — АНАЛИТИЧЕСКАЯ, А НЕ ПО ТРЕУГОЛЬНИКАМ
#
# ПОЧЕМУ ПОЛЕ БЫЛО «ПОЛОСАТЫМ». Меш земли собирается через SurfaceTool БЕЗ
# индексации: на каждый квад кладутся шесть отдельных вершин. У такой геометрии
# generate_normals() физически не может усреднить нормаль между соседями —
# он даёт ОДНУ нормаль на треугольник. В результате пологая волнистая земля
# разбивалась на 4 тысячи плоских граней со скачком освещённости на каждом
# стыке: глаз читал это как чешую или тигровые полосы по всему полю. Второй
# встречный источник света (см. _setup_environment) только усиливал рисунок.
#
# Высота задана формулой, значит и наклон можно взять ТОЧНО — производной по
# x и z, а не приближением по соседним вершинам. Нормаль получается идеально
# гладкой, свет ложится непрерывно, гранёности нет вовсе. И это ровно тот же
# «единственный источник правды», что и у get_terrain_height().
# ─────────────────────────────────────────────────────────────────────────────
func terrain_normal(x: float, z: float) -> Vector3:
	if not TERRAIN_RELIEF:
		return Vector3.UP
	# Производные тех же трёх гармоник, что и в get_terrain_height
	var a := x * 0.031 + z * 0.017
	var b := x * 0.013 - z * 0.041 + 1.7
	var c := x * 0.077 + z * 0.059 + 3.1
	var dhdx: float = RELIEF_AMP * (
		  0.55 * 0.031 * cos(a)
		+ 0.30 * 0.013 * cos(b)
		+ 0.15 * 0.077 * cos(c))
	var dhdz: float = RELIEF_AMP * (
		  0.55 *  0.017 * cos(a)
		+ 0.30 * -0.041 * cos(b)
		+ 0.15 *  0.059 * cos(c))
	return Vector3(-dhdx, 1.0, -dhdz).normalized()

func _build_flat_terrain() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Playfield"
	var mat := StandardMaterial3D.new()
	mat.albedo_color   = Color(0.26, 0.50, 0.20)
	mat.roughness      = 0.90
	# Цвет вершин подмешивает лёгкую пятнистость луга поверх светотени
	mat.vertex_color_use_as_albedo = true

	if not TERRAIN_RELIEF:
		var plane := PlaneMesh.new()
		plane.size     = Vector2(MAP_HALF_X * 2.0, MAP_HALF_Z * 2.0)
		plane.material = mat
		mi.mesh        = plane
		mi.position.y  = 0.001
		add_child(mi)
		return

	var nx: int = int(ceil(MAP_HALF_X * 2.0 / RELIEF_STEP))
	var nz: int = int(ceil(MAP_HALF_Z * 2.0 / RELIEF_STEP))
	var dx: float = MAP_HALF_X * 2.0 / float(nx)
	var dz: float = MAP_HALF_Z * 2.0 / float(nz)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(nz):
		for ix in range(nx):
			var x0: float = -MAP_HALF_X + float(ix) * dx
			var x1: float = x0 + dx
			var z0: float = -MAP_HALF_Z + float(iz) * dz
			var z1: float = z0 + dz
			var a := Vector3(x0, get_terrain_height(x0, z0), z0)
			var b := Vector3(x1, get_terrain_height(x1, z0), z0)
			var c := Vector3(x1, get_terrain_height(x1, z1), z1)
			var d := Vector3(x0, get_terrain_height(x0, z1), z1)
			for v in [a, b, c, a, c, d]:
				var p: Vector3 = v
				# Пятнистость привязана к координатам, а не к randf(): узор
				# одинаков при каждом запуске и не мерцает между кадрами
				var tint: float = 0.94 + 0.06 * sin(p.x * 0.21 + p.z * 0.33)
				st.set_color(Color(tint, tint, tint))
				# НОРМАЛЬ СТАВИТСЯ ЯВНО, ПО ФОРМУЛЕ РЕЛЬЕФА. generate_normals()
				# на неиндексированной сетке даёт по одной нормали на треугольник,
				# и поле распадалось на тысячи плоских граней — см. terrain_normal
				st.set_normal(terrain_normal(p.x, p.z))
				st.add_vertex(p)
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

# ─────────────────────────────────────────────────────────────────────────────
# КРАЙ МИРА: ЗЕЛЁНЫЙ БОРТИК + ЧЕРНОТА (как в «Казаках»)
# Порядок по высоте: зелёное поле (y=0) → фаска, уходящая вниз и наружу →
# сплошная чёрная плоскость под ней и до горизонта.
# ─────────────────────────────────────────────────────────────────────────────
func _build_world_edge() -> void:
	# 1. ЧЕРНОТА. Заведомо больше поля, чтобы её край не попал в кадр даже на
	# максимальном отдалении камеры.
	# ЗАПАС СЧИТАН ПОД ЗАДРАННЫЙ НОС: при наклоне 45° и угле обзора 75° верхний
	# луч пирамиды идёт всего в 7.5° ниже горизонта и с высоты 40 м достаёт до
	# земли за ~300 м от камеры. Плюс сама камера уходит к краю (CAM_BOUND по
	# диагонали ~133 м) — итого до ~440 м от центра. Берём с большим запасом от
	# ДЛИННОЙ стороны: чернота обязана уходить за горизонт по всем направлениям
	var void_mi := MeshInstance3D.new()
	void_mi.name = "WorldVoid"
	var void_pl := PlaneMesh.new()
	var void_side: float = MAP_HALF_X * 12.0
	void_pl.size = Vector2(void_side, void_side)
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.02, 0.02, 0.03)
	vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_pl.material  = vmat
	void_mi.mesh      = void_pl
	void_mi.position.y = -MAP_BEVEL_DROP
	add_child(void_mi)

	# 2. БОРТИК: рамка между внутренним прямоугольником (край поля, y=0) и
	# внешним (край фаски, опущенный в черноту). Четыре трапеции со скошенными
	# углами. Полуоси РАЗНЫЕ — карта прямоугольная, общий множитель дал бы
	# бортик, вылезающий за поле по длинной оси и режущий его по короткой
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: Array = []
	var outer: Array = []
	for c in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var s: Vector2 = c
		inner.append(Vector3(s.x * MAP_HALF_X, 0.0, s.y * MAP_HALF_Z))
		outer.append(Vector3(s.x * (MAP_HALF_X + MAP_BEVEL), -MAP_BEVEL_DROP,
			s.y * (MAP_HALF_Z + MAP_BEVEL)))
	# ── ШОВ С ПОЛЕМ ЗАШИТ ────────────────────────────────────────────────────
	# Внутренняя кромка бортика лежала на y = 0 ровной линией, а край самого
	# поля идёт ПО РЕЛЬЕФУ (get_terrain_height даёт до ±0.85 м). Между ними
	# оставалась щель переменной высоты: сквозь неё по всему периметру
	# просвечивала чернота — рваными полосами, тем шире, чем выше волна.
	# Теперь внутренняя кромка сажается ровно на рельеф и шов исчезает.
	#
	# Дробим каждую сторону на сегменты: одной трапеции на сторону мало —
	# кромка обязана повторять волну, а не срезать её хордой
	const EDGE_SEGMENTS := 24
	for i in range(4):
		var j: int = (i + 1) % 4
		for s2 in range(EDGE_SEGMENTS):
			var t0: float = float(s2) / float(EDGE_SEGMENTS)
			var t1: float = float(s2 + 1) / float(EDGE_SEGMENTS)
			var a: Vector3 = (inner[i] as Vector3).lerp(inner[j], t0)
			var b: Vector3 = (inner[i] as Vector3).lerp(inner[j], t1)
			a.y = get_terrain_height(a.x, a.z)
			b.y = get_terrain_height(b.x, b.z)
			var c2: Vector3 = (outer[i] as Vector3).lerp(outer[j], t1)
			var d: Vector3 = (outer[i] as Vector3).lerp(outer[j], t0)
			# Две стороны рамки смотрят наружу, две внутрь — cull отключён
			# у материала, поэтому порядок обхода на вид не влияет
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(c2)
			st.add_vertex(a); st.add_vertex(c2); st.add_vertex(d)
	st.generate_normals()
	var bevel := MeshInstance3D.new()
	bevel.name = "WorldBevel"
	bevel.mesh = st.commit()
	var bmat := StandardMaterial3D.new()
	# Темнее поля: край читается как срез дёрна, а не как продолжение луга
	bmat.albedo_color = Color(0.17, 0.33, 0.13)
	bmat.roughness    = 0.95
	bmat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	bevel.material_override = bmat
	add_child(bevel)

	# 3. ФИЗИЧЕСКИЕ СТЕНЫ по периметру. Настоящий упор юнитов — зажим в
	# clamp_to_map() (маски в проекте нулевые, стена сама никого не держит).
	#
	# СЛОЙ ВЫБОРА У НИХ СНЯТ (было LAYER_GROUND). Стена высотой 12 м стоит
	# СНАРУЖИ поля, а камера на максимальном отдалении физически оказывается
	# ЗА ней (фокус до CAM_BOUND + вынос 60/tan60 ≈ 35 м, стена на MAP_HALF+0.5).
	# Луч к южной кромке карты шёл из-за стены и протыкал её на высоте ~6 м:
	# правый клик по полосе z ≳ 92 возвращал точку НА СТЕНЕ (ошибка до 5.6 м),
	# а разбор попаданий обрывался на ней — врага, жилу или своего бойца у
	# южного края нельзя было назначить целью вовсе (замер qa_world2, B6).
	# Ловить клик в черноту стена и не должна: точка земли считается
	# аналитически по плоскости y=0, а приказ всё равно зажимается
	# land_target()/clamp_to_map(). Тела оставлены как разметка периметра.
	var walls := StaticBody3D.new()
	walls.name = "WorldWalls"
	walls.collision_layer = 0
	walls.collision_mask  = 0
	var th: float = 1.0
	var h: float  = 12.0
	for side in range(4):
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var horiz: bool = side < 2
		bs.size = Vector3(MAP_HALF_X * 2.0 + th * 2.0, h, th) if horiz \
			else Vector3(th, h, MAP_HALF_Z * 2.0 + th * 2.0)
		cs.shape = bs
		var sign: float = 1.0 if (side % 2) == 0 else -1.0
		cs.position = Vector3(0.0, h * 0.5, sign * (MAP_HALF_Z + th * 0.5)) if horiz \
			else Vector3(sign * (MAP_HALF_X + th * 0.5), h * 0.5, 0.0)
		walls.add_child(cs)
	_world.add_child(walls)

# ─────────────────────────────────────────────────────────────────────────────
# ЛАНДШАФТ: ПРУД, КУСТЫ, ОБЛАКА
# ─────────────────────────────────────────────────────────────────────────────

# Форма берега озера: радиус в зависимости от угла — сумма гармоник,
# поэтому контур плавный, замкнутый и заведомо не круглый/не квадратный
func _lake_radius_at(angle: float) -> float:
	return LAKE_RADIUS * (1.0
		+ 0.17 * sin(angle * 2.0 + 0.7)
		+ 0.11 * sin(angle * 3.0 - 1.9)
		+ 0.06 * sin(angle * 5.0 + 2.6))

func _lake_point(angle: float) -> Vector2:
	var r := _lake_radius_at(angle)
	return Vector2(cos(angle) * r, sin(angle) * r * LAKE_SQUASH)

# Точка (x, z) внутри озера? Юниты по воде и камням в ней не ходят —
# движение проверяет это через GameManager.is_water().
#
# Аналитический тест вместо коллайдера: физические маски в проекте намеренно
# нулевые (см. README — включённые маски давали дрожание на грунте), а форма
# берега и так задана функцией, поэтому проверка точная и без узлов физики.
func is_water(x: float, z: float) -> bool:
	# ОЗЕРО ВРЕМЕННО ОТКЛЮЧЕНО: воды на карте нет вовсе, центр — суша.
	# Одна проверка на самом верху отключает и обход берега, и поиск суши,
	# и все оговорки про воду в приказах — они просто перестают срабатывать
	if not LAKE_ENABLED:
		return false
	var dx := x - LAKE_CENTER.x
	var dz := z - LAKE_CENTER.z
	# Дешёвая отбраковка: подавляющее большинство юнитов далеко от озера
	var max_r := LAKE_RADIUS * 1.35 + LAKE_MARGIN
	if absf(dx) > max_r or absf(dz) > max_r:
		return false
	# Разжимаем по Z обратно — контур становится «радиусом от угла»
	var uz := dz / LAKE_SQUASH
	var dist := sqrt(dx * dx + uz * uz)
	if dist < 0.001:
		return true
	return dist <= _lake_radius_at(atan2(uz, dx)) + LAKE_MARGIN

# Обход озера: вернуть РАЗРЕШЁННЫЙ шаг из точки from. Если прямой шаг ведёт
# в воду — юнит идёт ВДОЛЬ берега по касательной в ту сторону, которая ближе
# к его цели. Покомпонентного скольжения по осям недостаточно: при движении
# строго вдоль X (step.z == 0) обе покомпонентные попытки отбраковывались
# и юнит намертво упирался в берег вместо обхода.
func slide_around_water(from: Vector3, step: Vector3) -> Vector3:
	# ЮНИТ УЖЕ СТОИТ В ВОДЕ — ВЫВОДИМ ЕГО НА БЕРЕГ.
	# Ходьбой в озеро не попасть: каждый шаг проверяется. Но юнита можно
	# ПОСТАВИТЬ туда напрямую — выходом отряда из гарнизона (Castle.release_unit
	# раскладывает бойцов по строю от ворот), спавном из ворот у самой кромки,
	# отладочной телепортацией. Обычный обход по касательной в этом случае
	# бесполезен: вокруг тоже вода, все шесть проб отбраковываются, функция
	# возвращала Vector3.ZERO — и боец оставался в озере НАВСЕГДА, не реагируя
	# ни на один приказ. Поэтому первым делом идём кратчайшим путём на сушу.
	if is_water(from.x, from.z):
		var shore := nearest_land(from.x, from.z)
		var out_dir := Vector3(shore.x - from.x, 0.0, shore.y - from.z)
		if out_dir.length() > 1e-4:
			return out_dir.normalized() * step.length()
		return step
	var to := from + step
	if not is_water(to.x, to.z):
		return step
	# Наружу от центра озера (для вытянутого контура радиали достаточно)
	var outward := Vector3(from.x - LAKE_CENTER.x, 0.0, from.z - LAKE_CENTER.z)
	if outward.length_squared() < 1e-6:
		return Vector3.ZERO
	outward = outward.normalized()
	var tangent := Vector3(-outward.z, 0.0, outward.x)
	if tangent.dot(step) < 0.0:
		tangent = -tangent
	var len := step.length()
	# Пробуем чистую касательную, затем с подмешанным «отходом от воды».
	# Тип элемента задан явно: `for b in [...]` даёт Variant и ломает вывод типов
	var blends: Array[float] = [0.0, 0.35, 0.7]
	for blend in blends:
		var dir: Vector3  = (tangent + outward * blend).normalized()
		var cand: Vector3 = from + dir * len
		if not is_water(cand.x, cand.z):
			return dir * len
	# ОБРАТНАЯ КАСАТЕЛЬНАЯ. Первый набор ведёт в ту сторону берега, которая
	# ближе к цели, но в вогнутом кармане контура (озеро не круглое —
	# см. _lake_radius_at) все три попытки упираются в воду, и юнит вставал
	# намертво прямо у кромки: приказ есть, шаг нулевой, отряд «висит».
	# Пробуем обойти карман в другую сторону и, в самом крайнем случае, просто
	# отойти от воды — движение продолжается всегда.
	for blend in blends:
		var dir: Vector3  = (-tangent + outward * blend).normalized()
		var cand: Vector3 = from + dir * len
		if not is_water(cand.x, cand.z):
			return dir * len
	var back: Vector3 = from + outward * len
	if not is_water(back.x, back.z):
		return outward * len
	return Vector3.ZERO

# Ближайшая СУША к точке (x, z). Нужна, когда приказ пришёл в воду: цель
# переносится на берег, иначе юнит бесконечно упирается в кромку и не может
# «дойти» — дистанция до точки в озере никогда не станет меньше порога прибытия.
# Ищем по радиали от центра озера: контур задан радиусом от угла, поэтому
# достаточно вынести точку наружу вдоль того же луча.
const SHORE_STEP := 0.5      # шаг поиска берега, м
const SHORE_TRIES := 60      # максимум шагов (30 м — заведомо больше озера)

func nearest_land(x: float, z: float) -> Vector2:
	if not is_water(x, z):
		return Vector2(x, z)
	var out := Vector2(x - LAKE_CENTER.x, z - LAKE_CENTER.z)
	if out.length_squared() < 1e-6:
		out = Vector2(1.0, 0.0)      # ровно в центре — уходим куда угодно
	out = out.normalized()
	for i in range(1, SHORE_TRIES + 1):
		var p := Vector2(x, z) + out * (float(i) * SHORE_STEP)
		if not is_water(p.x, p.y):
			# Ещё полшага наружу: точно за кромкой, а не впритык к ней
			return p + out * SHORE_STEP
	return Vector2(x, z)

func _spawn_water_body() -> void:
	# ОЗЕРО И УТКА ВРЕМЕННО ОТКЛЮЧЕНЫ (LAKE_ENABLED). Вместе с водой не
	# создаются ни кольцо камней у кромки, ни резиновая утка — центр карты
	# остаётся чистой сушей. Вернуть всё обратно = поставить флаг в true
	if not LAKE_ENABLED:
		return
	# ЕДИНСТВЕННОЕ озеро на карте. Раньше собиралось из 4 перекрывающихся
	# QuadMesh — прямоугольники давали угловатые «ступеньки» по берегу.
	# Теперь это цельный полигон-веер с органическим контуром.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 96
	for i in range(segments):
		var a0 := TAU * float(i)       / float(segments)
		var a1 := TAU * float(i + 1)   / float(segments)
		var p0 := _lake_point(a0)
		var p1 := _lake_point(a1)
		# Обход по часовой в плоскости XZ — нормаль вверх
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p1.x, p1.y) / (LAKE_RADIUS * 2.0) + Vector2(0.5, 0.5))
		st.add_vertex(Vector3(p1.x, 0.0, p1.y))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p0.x, p0.y) / (LAKE_RADIUS * 2.0) + Vector2(0.5, 0.5))
		st.add_vertex(Vector3(p0.x, 0.0, p0.y))

	var water_tex: Texture2D = null
	var water_path := "res://assets/environment/terrain/Water Background color.png"
	if ResourceLoader.exists(water_path):
		water_tex = load(water_path) as Texture2D
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.24, 0.58, 0.86, 0.92)
	if water_tex:
		pmat.albedo_texture = water_tex
		pmat.uv1_scale      = Vector3(3.0, 3.0, 1.0)
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	st.set_material(pmat)

	var lake := MeshInstance3D.new()
	lake.name = "Lake"
	lake.mesh = st.commit()
	lake.position = Vector3(LAKE_CENTER.x, 0.005, LAKE_CENTER.z)
	_world.add_child(lake)

	# Камни стоят ВНУТРИ воды, по внутреннему кольцу у самой кромки
	# (LAKE_ROCK_RING = доля от радиуса берега), а не на суше снаружи.
	var rock_paths := [
		"res://assets/environment/terrain/Water Rocks_01.png",
		"res://assets/environment/terrain/Water Rocks_02.png",
		"res://assets/environment/terrain/Water Rocks_03.png",
		"res://assets/environment/terrain/Water Rocks_04.png",
	]
	var rock_count := 18
	for i in range(rock_count):
		var rp: String = rock_paths[i % rock_paths.size()]
		if not ResourceLoader.exists(rp):
			continue
		var rtex := load(rp) as Texture2D
		if rtex == null:
			continue
		var rmi := MeshInstance3D.new()
		var rq  := QuadMesh.new()
		# Water Rocks_*.png — шит из 16 кадров: размер по одному кадру
		var rw := randf_range(1.2, 1.8)
		rq.size = Vector2(rw, rw / _BBUtil.frame_aspect(rtex))
		# Кадры ПРОИГРЫВАЮТСЯ (fps > 0): это анимация омывания камня водой,
		# ради которой шит и нарисован. Фаза у каждого камня своя (см.
		# make_material), поэтому кольцо не «пульсирует» синхронно.
		rq.material = _BBUtil.make_material(rtex, Color.WHITE, 0.5, 7.0)
		rmi.mesh    = rq
		var ra := TAU * float(i) / float(rock_count) + randf_range(-0.06, 0.06)
		var rpt := _lake_point(ra) * randf_range(LAKE_ROCK_RING - 0.05, LAKE_ROCK_RING + 0.03)
		rmi.position = Vector3(
			LAKE_CENTER.x + rpt.x,
			rq.size.y * 0.5 - 0.05,
			LAKE_CENTER.z + rpt.y)
		_world.add_child(rmi)

	# Резиновая утка в центре озера с покачиванием
	var duck_path := "res://assets/environment/terrain/Rubber duck.png"
	if ResourceLoader.exists(duck_path):
		var duck_tex := load(duck_path) as Texture2D
		if duck_tex:
			var duck_mi := MeshInstance3D.new()
			var duck_q  := QuadMesh.new()
			# Rubber duck.png — шит: размер по ОДНОМУ кадру
			duck_q.size = Vector2(1.0, 1.0 / _BBUtil.frame_aspect(duck_tex))
			duck_q.material = _BBUtil.make_material(duck_tex, Color.WHITE, 0.5, 0.0)
			duck_mi.mesh    = duck_q
			duck_mi.position = Vector3(LAKE_CENTER.x + 1.0, 0.45, LAKE_CENTER.z)
			_world.add_child(duck_mi)
			_duck_node = duck_mi

func _spawn_bushes() -> void:
	var bush_paths := [
		"res://assets/environment/terrain/Bushe1.png",
		"res://assets/environment/terrain/Bushe2.png",
		"res://assets/environment/terrain/Bushe3.png",
		"res://assets/environment/terrain/Bushe4.png",
	]
	var bush_textures := []   # нетипизированный массив — совместим со всеми версиями Godot 4
	for p in bush_paths:
		if ResourceLoader.exists(p):
			var t := load(p) as Texture2D
			if t:
				bush_textures.append(t)
	if bush_textures.is_empty():
		return

	# Кусты растут ОКРУГЛЫМИ/овальными группами (как рощи), а не поодиночке
	var target_clusters := int(12.0 * MAP_GROWTH * MAP_GROWTH)
	var placed   := 0
	var attempts := 0
	while placed < target_clusters and attempts < 400:
		attempts += 1
		var cx := randf_range(-GEN_HALF_X, GEN_HALF_X)
		var cz := randf_range(-GEN_HALF_Z, GEN_HALF_Z)
		if Vector2(cx, cz).length() < 15.0:          # середина карты
			continue
		if cx > ENEMY_BASE_ANCHOR.x - 15.0 and cz > ENEMY_BASE_ANCHOR.z - 15.0:
			continue                                 # угол врага
		if LAKE_ENABLED and Vector2(cx - LAKE_CENTER.x, cz - LAKE_CENTER.z).length() \
				< LAKE_RADIUS * 1.35 + 2.0:
			continue                                     # озеро
		_spawn_bush_cluster(bush_textures, Vector3(cx, 0.0, cz), randi_range(3, 7))
		placed += 1

# Овальное пятно кустов; каждый куст — отдельный объект, зафиксированный
# в мировых координатах, billboard только на его собственном спрайте
func _spawn_bush_cluster(textures: Array, center: Vector3, count: int) -> void:
	var ell_ang := randf() * TAU
	var rx := randf_range(2.5, 5.0)
	var rz := rx * randf_range(0.55, 1.0)
	var placed_pts: Array = []
	for i in range(count):
		var pt := Vector2.ZERO
		var ok := false
		for _attempt in range(8):
			var ang  := randf() * TAU
			var r    := sqrt(randf())
			var cand := Vector2(cos(ang) * r * rx, sin(ang) * r * rz).rotated(ell_ang)
			ok = true
			for q in placed_pts:
				if cand.distance_to(q) < 1.6:
					ok = false
					break
			if ok:
				pt = cand
				break
		if not ok:
			continue
		placed_pts.append(pt)
		if not _fits_in_map(center.x + pt.x, center.z + pt.y):
			continue

		var tex: Texture2D = textures[randi() % textures.size()]
		var bmi := MeshInstance3D.new()
		var bq  := QuadMesh.new()
		# Крупные пышные кусты. ВАЖНО: Bushe*.png — шит из 8 кадров,
		# пропорции берём у ОДНОГО кадра (кадр выбирает шейдер) — иначе
		# куст рисовался плоской полосой из 8 кустов («заборчик»)
		var sc  := randf_range(2.2, 3.6)
		var b_fa: float = _BBUtil.frame_aspect(tex)
		bq.size = Vector2(sc, sc / b_fa)
		# Цилиндрический билборд: каждый куст поворачивается к позиции камеры
		# вокруг своей собственной оси (не «стенкой» вместе с соседями)
		# КОЛЫХАНИЕ НА ВЕТРУ: у Bushe*.png в шите те же 8 кадров качания.
		# Фаза и темп у каждого куста свои (см. BillboardUtil.make_wind_material),
		# поэтому заросли шевелятся вразнобой, а не одной волной
		bq.material = _BBUtil.make_wind_material(tex)
		bmi.mesh    = bq
		bmi.position = Vector3(center.x + pt.x, bq.size.y * 0.5, center.z + pt.y)
		_world.add_child(bmi)

## ОБЛАКА ОТКЛЮЧЕНЫ ВМЕСТЕ С ПЕРЕХОДОМ НА ОРТОГРАФИЮ.
## В перспективе они висели высоко и уменьшались с расстоянием, читаясь как
## небо. В ортографии размер от расстояния не зависит вообще: облако на высоте
## 50 м рисуется того же размера, что дерево под ним, и выглядит белым пятном,
## лежащим прямо на поле. Код оставлен — вернётся, если появится настоящий
## слой неба (отдельный вьюпорт или перспективная камера заднего плана)
const CLOUDS_ENABLED := false

func _spawn_clouds() -> void:
	if not CLOUDS_ENABLED:
		return
	var cloud_paths := []   # нетипизированный массив — совместим со всеми версиями Godot 4
	for n in range(1, 9):
		var p := "res://assets/environment/terrain/Clouds_%02d.png" % n
		if ResourceLoader.exists(p):
			cloud_paths.append(p)
	if cloud_paths.is_empty():
		return

	var count := int(20.0 * MAP_GROWTH * MAP_GROWTH)
	for i in range(count):
		var p: String = cloud_paths[i % cloud_paths.size()]
		var tex := load(p) as Texture2D
		if tex == null:
			continue
		var cmi := MeshInstance3D.new()
		var cq  := QuadMesh.new()
		var sw  := randf_range(12.0, 28.0)
		cq.size = Vector2(sw, sw * 0.45)
		var cmat := StandardMaterial3D.new()
		cmat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		cmat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_texture = tex
		cmat.albedo_color   = Color(1.0, 1.0, 1.0, 0.90)
		cmat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.cull_mode      = BaseMaterial3D.CULL_DISABLED
		cq.material = cmat
		cmi.mesh    = cq
		var cx := randf_range(-MAP_HALF_X, MAP_HALF_X)
		var cy := randf_range(40.0, 65.0)
		var cz := randf_range(-MAP_HALF_Z, MAP_HALF_Z)
		cmi.position = Vector3(cx, cy, cz)
		_world.add_child(cmi)
