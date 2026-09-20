extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ВСЕ СТРЕЛЫ — ОДНИМ MultiMesh (этап D3), СЛОТЫ РАЗДАЁТ ЯДРО (BigStand-5, 3)
## ═══════════════════════════════════════════════════════════════════════════
## Раньше каждая стрела была узлом со СВОИМ мешем и материалом — то есть своим
## вызовом отрисовки (замер qa_shotcorpse: 36 торчащих = +36 вызовов, в свалке
## с лучниками их 100-150). Сюда переехала КАРТИНКА: один MultiMeshInstance3D,
## буфер — в ядре (ArmyCore.Rb, та же инфраструктура, что у армии), подача —
## общим RbFlush раз в кадр.
##
## С этапа 3 BigStand-5 у рядового снаряда нет узла вовсе: выстрел — запись
## полёта в ядре (ArmyCore.ProjectileFire), слот слоя ядро берёт из своего
## списка свободных (RbAcquire), промах втыкается в грунт там же, торчащие
## живут массивом ядра (StuckTick). Слой здесь владеет только ЖИЗНЕННЫМ ЦИКЛОМ:
## узел MultiMesh, материал, текстура, рост ёмкости (instance_count — ресурс
## сцены, ядро его не трогает). Узел Arrow остался legacy-путём под ручкой
## perf_config.projectile_core = false (A/B на одной сборке) и стендам.
##
## Ось и растворение едут в instance-цвете (см. mm_arrow.gdshader): у стрел
## каналы урона свободны, и COLOR ровно вмещает ax.xyz + fade.
##
## Владелец — GameManager (авто-загрузка живёт дольше сцены, поэтому ensure()
## проверяет, что узел ещё в ДЕРЕВЕ ЭТОЙ сцены, и при смене сцены строит слой
## заново; прежняя запись в списке бакетов ядра при этом просто пустеет — Rb
## на смену сцены не пересоздаётся, и это осознанная мелкая утечка записи).

const _SHADER := preload("res://shaders/mm_arrow.gdshader")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const GROW := 64

## Длина квада в метрах. Задаётся ЯВНО, а не из пикселей: сама картинка
## 64x64 почти пустая (полезная область 43x12), и вывод длины из размера листа
## давал квадрат 0.69x0.69 с крошечной стрелой посередине. 0.65 вместо прежних
## 0.75 — заказ владельца «убавить на 10-15%». Кость короче: она метательная
const ARROW_LENGTH := 0.65
const BONE_LENGTH := 0.42
const BONE_SHEET := "res://assets/factions/orc/Troll/Gnoll/Gnoll_Bone.png"
const _ARROW_PATHS := [
	"res://assets/factions/humans/units/archer/Arrow-Sheet.png",
	"res://assets/sprites/units/Arrow.png",
]

## Слой костей гноллов (своя картинка, свой кувырок)
var is_bone: bool = false

var mmi: MultiMeshInstance3D = null
var mm: MultiMesh = null
var mat: ShaderMaterial = null
var core_id: int = -1
var capacity: int = 0
## Поколение слоя. Растёт на каждой пересборке (смена сцены): слот, взятый у
## прошлого поколения, возвращать в список свободных нельзя — его номер может
## оказаться за ёмкостью нового буфера, и первый же acquire отдал бы номер, по
## которому ядро пишет за край массива
var gen: int = 0

## Длина квада этого слоя (метры) — её же ядро берёт для точки втыкания
func quad_length() -> float:
	return BONE_LENGTH if is_bone else ARROW_LENGTH

## Модуль оси у ЛЕТЯЩЕГО снаряда слоя: признак кувырка (см. mm_arrow.gdshader)
func flight_axis_k() -> float:
	return _GobCfg.GNOLL_BONE_AXIS_K if is_bone else 1.0

## Слой готов для выстрела без узла: текстуру и размеры берёт сам
func ensure_layer(world: Node3D) -> bool:
	if mmi != null and is_instance_valid(mmi) and mmi.is_inside_tree():
		return true
	var tex: Texture2D = load_bone_texture() if is_bone else load_arrow_texture()
	var aspect: float = 43.0 / 12.0
	if tex != null:
		var sz := tex.get_size()
		if sz.y > 0.0:
			aspect = sz.x / sz.y
	else:
		aspect = 6.0
	if not ensure(world, tex, quad_length(), aspect):
		return false
	if is_bone:
		set_spin(_GobCfg.GNOLL_BONE_SPIN)
	return true

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
	return true

## Нарастить слой: буфер и свободные — в ядре, instance_count — у ресурса
## сцены (его ядро не трогает). РОСТ ГЕОМЕТРИЧЕСКИЙ: смена instance_count —
## это перевыделение буфера в сервере отрисовки, и шаг в 64 на залпе 2000
## стрел стоил 31 перевыделение (зонд LaunchProbe: 18.5 против 8 мкс на выстрел)
func grow() -> void:
	if core_id < 0:
		return
	var new_cap: int = maxi(capacity * 2, GROW)
	GameManager.army.rb_grow(core_id, new_cap)
	mm.instance_count = new_cap
	capacity = new_cap

## Слот под legacy-узел (Arrow) или декор стенда. Свободные ведёт ядро
func acquire() -> int:
	if core_id < 0:
		return -1
	var i: int = GameManager.army.rb_acquire(core_id)
	if i < 0:
		grow()
		i = GameManager.army.rb_acquire(core_id)
	return i

## Сколько слотов свободно (стенды)
func free_count() -> int:
	if core_id < 0:
		return 0
	return GameManager.army.rb_free_count(core_id)

## Вернуть слот. Зовёт Arrow при освобождении УЗЛА (не при уходе в пул: там
## слот остаётся за узлом и переписывается следующим выстрелом)
func release(idx: int, slot_gen: int = -1) -> void:
	if idx < 0 or core_id < 0 or idx >= capacity:
		return
	if slot_gen >= 0 and slot_gen != gen:
		return
	GameManager.army.rb_release(core_id, idx)

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

## ── КУВЫРОК — СВОЙСТВО СЛОЯ, А НЕ СНАРЯДА ─────────────────────────────────
## Оборотов в секунду у ЛЕТЯЩИХ снарядов этого слоя (ноль — не крутятся).
## Материал у бакета один на всех, поэтому и ручка одна; кто именно сейчас
## летит, шейдер узнаёт по длине упакованной оси (см. mm_arrow.gdshader)
func set_spin(turns: float) -> void:
	if mat != null:
		mat.set_shader_parameter("spin_turns", turns)

func hide(idx: int) -> void:
	if idx >= 0 and core_id >= 0:
		GameManager.army.rb_hide_slot(core_id, idx)

## ── ТЕКСТУРЫ СЛОЯ ─────────────────────────────────────────────────────────
## Картинка обрезается по непрозрачной области: в исходных 64x64 стрела
## занимает 43x12 в середине, и без обрезки квад был бы почти пустым
static var _tex_cache: Dictionary = {}

## Кость: первый кадр четырёхкадровой ленты, обрезанный по рисунку. Крутиться
## в полёте ей нечем: слой кладёт квад на ВЕКТОР СКОРОСТИ (mm_arrow), листания
## кадров у него нет вовсе. Кадр режется тем же способом, что часовой башни —
## Image.get_region: AtlasTexture в sampler2D уезжает целиком
static func load_bone_texture() -> Texture2D:
	if _tex_cache.has(BONE_SHEET):
		return _tex_cache[BONE_SHEET]
	if not ResourceLoader.exists(BONE_SHEET):
		_tex_cache[BONE_SHEET] = null
		return null
	var tex := load(BONE_SHEET) as Texture2D
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		_tex_cache[BONE_SHEET] = null
		return null
	var fh: int = img.get_height()
	var frames: int = maxi(img.get_width() / maxi(fh, 1), 1)
	var frame: Image = img.get_region(Rect2i(0, 0, maxi(img.get_width() / frames, 1), fh))
	var r: Rect2i = frame.get_used_rect()
	if r.size.x > 0 and r.size.y > 0:
		frame = frame.get_region(r)
	var out: Texture2D = ImageTexture.create_from_image(frame)
	_tex_cache[BONE_SHEET] = out
	return out

static func load_arrow_texture() -> Texture2D:
	for p in _ARROW_PATHS:
		var path: String = p
		if _tex_cache.has(path):
			return _tex_cache[path]
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		if img.is_compressed() and img.decompress() != OK:
			continue
		var rect := img.get_used_rect()
		var out: Texture2D = tex
		if rect.size.x > 0 and rect.size.y > 0:
			out = ImageTexture.create_from_image(img.get_region(rect))
		_tex_cache[path] = out
		return out
	return null

## ── РЕЕСТР ПОЛЁТОВ LEGACY-УЗЛОВ (perf_config.arrow_core, projectile_core off)
## id полёта → узел стрелы: события от BatchArrows приходят по id
var _flights: Dictionary = {}

func register_flight(id: int, arrow: Node3D) -> void:
	_flights[id] = arrow
	_flight_since[id] = Engine.get_physics_frames()

## Когда полёт зарегистрирован (для срока полёта под ядром)
var _flight_since: Dictionary = {}
var flights_expired: int = 0     # стендам: сколько полётов погашено сроком

## ── ЖЁСТКИЙ СРОК ПОЛЁТА ПОД ЯДРОМ (спринт 18) ──────────────────────────────
## Пока летит ядро, у узла выключен _process, а с ним и MAX_FLIGHT_SEC: полёт,
## чьё событие потерялось, висел бы вечно (кость крутится на месте — жалоба
## владельца). Раз в секунду: старше MAX_FLIGHT_SEC — гасим принудительно.
## Снаряды БЕЗ узла срок полёта считают в самом ядре (_afMaxAge)
func sweep_flights(max_sec: float) -> void:
	if _flights.is_empty():
		return
	# ИГРОВОЕ время (физкадры), не стенные часы: под нагрузкой шлюза физика
	# отстаёт от стены, и честный полёт в 3 с длится 10+ с стены — стенные
	# часы гасили бы живые стрелы (qa_full_game_4k A1 под шлюзом)
	var now: int = Engine.get_physics_frames()
	var lim: int = int(max_sec * float(Engine.physics_ticks_per_second))
	var dead: Array = []
	for id in _flights:
		if now - int(_flight_since.get(id, now)) > lim:
			dead.append(id)
	for id2 in dead:
		var a = _flights.get(id2)
		_flights.erase(id2)
		_flight_since.erase(id2)
		flights_expired += 1
		if a != null and is_instance_valid(a) and a.has_method("_despawn"):
			a.call("_despawn")

func unregister_flight(id: int) -> void:
	_flights.erase(id)
	_flight_since.erase(id)

## Полётов этого слоя: узлы legacy плюс записи ядра
func flight_count() -> int:
	var n: int = _flights.size()
	if core_id >= 0:
		n += GameManager.army.flights_on(core_id)
	return n

## Только legacy-узлы в полёте (GameManager решает, звать ли забор событий)
func legacy_flight_count() -> int:
	return _flights.size()

## Разобрать события ядра за кадр: касание чужого или приземление.
## ── СОБЫТИЯ — ОДИН СПИСОК НА ВСЕ СЛОИ (спринт 18, «зависшие кости») ──────
## take_arrow_events отдаёт события ВСЕХ полётов и очищает список. Пока
## каждый слой брал его сам, слой стрел (первый) забирал и события костей —
## и терял их: кость никогда не получала core_event, узел висел «в полёте» с
## выключенным _process, а слот крутился на месте вечно. Теперь события
## берёт GameManager один раз и раздаёт по слоям (dispatch_events)
static func dispatch_events(ev: Array, layers: Array) -> int:
	var n: int = ev.size()
	var k := 0
	var routed := 0
	while k + 3 < n:
		var id: int = int(ev[k])
		for l in layers:
			if l == null or not is_instance_valid(l):
				continue
			var a = l._flights.get(id)
			if a == null:
				continue
			l._flights.erase(id)
			l._flight_since.erase(id)
			if is_instance_valid(a):
				a.core_event(ev[k + 1], ev[k + 2], ev[k + 3])
			routed += 1
			break
		k += 4
	return routed

## Совместимость: слой в одиночку (стенды) — забирает и раздаёт сам себе
func drain_events() -> void:
	if _flights.is_empty():
		return
	dispatch_events(GameManager.army.take_arrow_events(), [self])

func set_layer_visible(v: bool) -> void:
	if mmi != null and is_instance_valid(mmi):
		mmi.visible = v
