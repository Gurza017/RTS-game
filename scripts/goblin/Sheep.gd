extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## ОВЦА — МИРНАЯ ЖИВНОСТЬ У ЛОГОВА ТРОЛЛЕЙ (заказ владельца, 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## НЕ Unit и не ResourceNode: в ядро армии не входит, в сетке соседей не
## состоит, целью ни для кого не является, тел и коллизий у неё нет. Это
## декорация с поведением, как дерево с ветром, — только ходит. Поэтому
## стоимость стада — десять узлов с лёгким _process, и ни одной строки в
## покадровых проходах армии.
##
## ПОВЕДЕНИЕ: пасётся вокруг логова (home) в радиусе SHEEP_GRAZE_RADIUS. Раз в
## SHEEP_HOP_SEC выбирает точку в SHEEP_HOP_MIN…SHEEP_HOP_MAX от себя и не
## спеша переходит туда (лента Bouncing), стоя — щиплет траву (лента Idle).
## Воду обходит тем же land_target, что и бойцы. Спрайт смотрит по ходу:
## зеркальные ленты пересобраны ОДИН РАЗ (статический кэш) — билборд
## cyl_billboard нормирует масштаб и отрицательный scale.x не переворачивает.
## В тумане прячется, как боец (is_lit по своей точке).
##
## СЪЕДЕНИЕ: тролль (Troll._eat) зовёт eat() — овца исчезает мгновенно, логово
## узнаёт об этом (TrollLair.on_sheep_eaten) и считает стадо заново.
## Файл без class_name: подключается через preload (как Troll/TrollLair).

const _GobCfgS := preload("res://scripts/goblin/goblin_config.gd")
const _BBUtilS := preload("res://scripts/BillboardUtil.gd")
## Потолок выпаса у замка — в конфиге владельца, как и всё остальное
const _UCfgS := preload("res://scripts/unit_stats_config.gd")

const DIR := "res://assets/environment/resources/Sheep/"
const SHEET_IDLE := DIR + "HappySheep_Idle.png"       # 8 кадров 128×128
const SHEET_WALK := DIR + "HappySheep_Bouncing.png"   # 6 кадров 128×128
const IDLE_FPS := 6.0
const WALK_FPS := 9.0

## Пересобранные ленты: ключ "idle"/"walk" + "_m" для зеркала → Texture2D,
## плюс "rows" → [top, bottom, frame_w] — общий срез по строкам рисунка
static var _cache: Dictionary = {}

## ── ЧАСЫ СТАДА (стенд qa_sheep_performance_test) ──────────────────────────
## Одна пара get_ticks_usec вокруг _process КАЖДОЙ овцы, только пока prof_on:
## в выключенном виде — одно сравнение bool. prof_calls — сколько овце-кадров
## накоплено (мкс / calls = цена одной овцы за кадр)
static var prof_on: bool = false
static var prof_usec: int = 0
static var prof_calls: int = 0

static func prof_reset() -> void:
	prof_usec = 0
	prof_calls = 0

## ── ПОТОЛОК СТАДА ИГРОКА (ТЗ 19.09.2026, блок 1): SHEEP_PLAYER_MAX ─────────
## Считаются ВСЕ живые овцы стороны — в загонах, у замка и блуждающие.
## Спрашивают: SheepPen.has_room, Worker._keep_accepts и breed_one — то есть
## каждое место, где у игрока появляется овца. Овцы логова (owner_faction −1)
## сюда не входят — их потолок держит TrollLair
static func owned_count(fac: int) -> int:
	var n := 0
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	for s in tree.get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s):
			continue
		if int(s.get("owner_faction")) != fac:
			continue
		if bool(s.get("eaten")) or bool(s.get("dead")):
			continue
		n += 1
	return n

static func owned_cap_ok(fac: int) -> bool:
	if fac < 0:
		return true
	return owned_count(fac) < _UCfgS.SHEEP_PLAYER_MAX

var lair: Node3D = null
var home: Vector3 = Vector3.ZERO
var eaten: bool = false
## ── СТАДО ИГРОКА (заказ спринта 13) ───────────────────────────────────────
## Принесённая рабочим овца ПРИВЯЗЫВАЕТСЯ: `pen` — загон, `keep` — зона замка,
## когда загона нет или он полон. Привязка задаёт три вещи разом: где пасётся
## (graze_home / graze_radius), с каким периодом плодится (breed_sec) и какой
## у стада потолок (flock_limit). Считать потолок КРУГОМ НА КАРТЕ нельзя:
## круги двух соседних загонов пересекаются, и одна овца шла бы в зачёт обоим
var pen: Node3D = null
var keep: Node3D = null
var owner_faction: int = -1
## ── ТУША (заказ спринта 13: «5 ударов ножом → смерть») ────────────────────
## Мёртвая овца НЕ ИСЧЕЗАЕТ: она лежит на боку, пока рабочий не вынесет с неё
## всё мясо (Worker.SHEEP_MEAT_TRIPS ходок). Поэтому смерть и исчезновение —
## два разных события: kill_flip() и consume()
var dead: bool = false
## ── КРАЖА (Worker.command_steal_sheep, 10.09.2026) ─────────────────────────
## captor — рабочий, который несёт или режет; _carried — едет над головой
## (свой ход и привязка к земле выключены), _pinned — опущена у склада и не
## разбегается, пока её режут. Луч мыши ловит тело на слое ресурсов
## (StaticBody3D) — рабочему с выделением этот слой открыт (order_pick_mask)
var captor: Node3D = null
var _carried: bool = false
var _pinned: bool = false
## Стенды: сколько перебежек сделано
var hops: int = 0

var _mi: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _target: Vector3 = Vector3.INF
var _hop_t: float = 0.0
var _walking: bool = false
var _mirror: bool = false
var _fog_t: float = 0.0
var _quad_h: float = 1.0
## ── ПАССИВНОЕ РАЗМНОЖЕНИЕ (заказ владельца 10.09.2026) ────────────────────
## «При отсутствии урона 1 овца со временем порождает 2-ю». Таймер личный, а
## не общий у логова: стадо растёт от КАЖДОЙ спокойной овцы, и вырезанное
## стадо восстанавливается медленнее, чем целое. Потолок стада (SHEEP_MAX)
## держит логово — спрашиваем его же spawn_sheep
var _breed_t: float = 0.0
## Сколько секунд овцу никто не трогал (надрез/укус сбрасывают)
var _calm_t: float = 0.0
## Сколько овец породила эта (стенды)
var bred: int = 0

static func sheets_ok() -> bool:
	return ResourceLoader.exists(SHEET_IDLE) and ResourceLoader.exists(SHEET_WALK)

## Число кадров горизонтальной ленты с квадратным кадром
static func frames_in(path: String) -> int:
	if not ResourceLoader.exists(path):
		return 0
	var tex := load(path) as Texture2D
	if tex == null:
		return 0
	var sz: Vector2 = tex.get_size()
	return maxi(int(round(sz.x / maxf(sz.y, 1.0))), 1)

## Срез по строкам: общий для обеих лент, чтобы ноги были на одной высоте
static func _rows() -> Array:
	if _cache.has("rows"):
		return _cache["rows"]
	var top := 1000000
	var bot := 0
	var fw := 0
	for p in [SHEET_IDLE, SHEET_WALK]:
		var tex := load(p) as Texture2D
		var img: Image = tex.get_image() if tex != null else null
		if img == null:
			continue
		var r: Rect2i = img.get_used_rect()
		if r.size.y <= 0:
			continue
		top = mini(top, r.position.y)
		bot = maxi(bot, r.end.y)
		fw = img.get_height()
	if bot <= top:
		top = 0
		bot = fw
	_cache["rows"] = [top, bot, fw]
	return _cache["rows"]

static func _texture(kind: String, mirror: bool) -> Texture2D:
	var key: String = kind + ("_m" if mirror else "")
	if _cache.has(key):
		return _cache[key]
	var path: String = SHEET_IDLE if kind == "idle" else SHEET_WALK
	var tex := load(path) as Texture2D
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		return null
	var rows: Array = _rows()
	var top: int = int(rows[0])
	var ch: int = int(rows[1]) - top
	var fw: int = int(rows[2])
	var frames: int = maxi(img.get_width() / maxi(fw, 1), 1)
	# «rest» — ОДИН кадр, последний из прыжка: овца лежит (спринт 19)
	var first: int = 0
	if kind == "rest":
		first = frames - 1
		frames = 1
	var strip := Image.create(fw * frames, ch, false, img.get_format())
	for f in range(frames):
		var fr: Image = img.get_region(Rect2i((first + f) * fw, top, fw, ch))
		if mirror:
			fr.flip_x()
		strip.blit_rect(fr, Rect2i(0, 0, fw, ch), Vector2i(f * fw, 0))
	var out := ImageTexture.create_from_image(strip)
	_cache[key] = out
	return out

## Взвести таймер размножения (зовёт логово при рождении; фаза у каждой своя,
## иначе всё стадо плодилось бы в один такт)
func arm_breeding(first_delay: float) -> void:
	_breed_t = maxf(first_delay, 1.0)

# ─────────────────────────────────────────────────────────────────────────────
# ПРИВЯЗКА К СТАДУ ИГРОКА
# ─────────────────────────────────────────────────────────────────────────────

## Овца хозяйская (принесена в загон или в зону замка), а не дикая у логова
func is_owned() -> bool:
	return owner_faction >= 0 and (pen != null or keep != null)

## ── БЛУЖДАЮЩАЯ (ТЗ 19.09.2026, блок 3) ────────────────────────────────────
## Овца ИГРОКА без привязки: из снесённого загона или не поместившаяся в
## полный. Хозяин у неё остался (owner_faction), а места нет — пасётся вокруг
## точки `home` в SHEEP_GRAZE_RADIUS и не плодится (flock_limit 0). Рабочий по
## ПКМ её НЕ режет, а несёт в незаполненный загон (Worker, режим пастуха)
func is_stray() -> bool:
	return owner_faction >= 0 and pen == null and keep == null and not dead and not eaten

## Загон снесён: привязка гаснет, овца остаётся хозяйской и РАЗБЕГАЕТСЯ от
## места ограды — дом переносится в её же точку, перебежка взводится сразу
func on_pen_lost() -> void:
	pen = null
	keep = null
	home = global_position
	_pinned = false
	if not dead and not eaten and not _carried:
		_mood = 0
		force_hop()

# ─────────────────────────────────────────────────────────────────────────────
# ВЫДЕЛЕНИЕ И УТИЛИЗАЦИЯ (ТЗ 19.09.2026, блок 2)
# ─────────────────────────────────────────────────────────────────────────────
## Овца — не боец: в selected_units не входит (панели и приказы её не видят),
## SelectionManager держит её в СВОЁМ списке selected_sheep. Подсветка — то же
## общее кольцо, что у бойца (UnitVisuals.ring_mesh, один меш на всех),
## заводится лениво при первом выделении и растянуто под ширину овцы
const _VisS := preload("res://scripts/units/UnitVisuals.gd")
const SEL_RING_SCALE := 2.4
## Двойной клик по овце без загона — все хозяйские овцы в этом радиусе
const FLOCK_PICK_RADIUS := 20.0
var _sel_ring: MeshInstance3D = null
var _selected: bool = false

func set_selected(on: bool) -> void:
	_selected = on
	if on and _sel_ring == null:
		var mi := MeshInstance3D.new()
		mi.name = "SheepRing"
		mi.mesh = _VisS.ring_mesh()
		mi.scale = Vector3(SEL_RING_SCALE, 1.0, SEL_RING_SCALE)
		mi.position.y = _VisS.RING_Y
		add_child(mi)
		_sel_ring = mi
	if _sel_ring != null:
		_sel_ring.visible = on

func is_selected() -> bool:
	return _selected

## Стадо этой овцы для двойного клика: тот же загон, та же зона замка, а у
## блуждающей — хозяйские без привязки в FLOCK_PICK_RADIUS от неё
func flock_mates() -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s) or bool(s.get("eaten")):
			continue
		if int(s.get("owner_faction")) != owner_faction:
			continue
		if pen != null and is_instance_valid(pen):
			if s.get("pen") == pen:
				out.append(s)
		elif keep != null and is_instance_valid(keep):
			if s.get("keep") == keep:
				out.append(s)
		elif s.get("pen") == null and s.get("keep") == null:
			var d: Vector3 = (s as Node3D).global_position - global_position
			d.y = 0.0
			if d.length() <= FLOCK_PICK_RADIUS:
				out.append(s)
	return out

## Delete по выделенной овце: исчезает мгновенно. Тот же путь, что у съедения
## троллем (eat): привязки и реестры снимаются им, рабочий, нёсший её, увидит
## `eaten` в своём тике и возьмётся за следующую
func dispose() -> void:
	set_selected(false)
	eat()

## Утиный контракт SheepPen.accept_sheep
func bind_to_pen(p: Node3D, f: int) -> void:
	pen = p
	keep = null
	owner_faction = f
	lair = null
	home = (p as Node3D).global_position
	if p.has_method("next_seq"):
		bind_seq = int(p.call("next_seq"))
	_breed_t = breed_sec() * (0.5 + 0.5 * fposmod(float(get_instance_id()) * 0.37, 1.0))
	_hop_t = 1.0

## Загона нет или он полон — пасётся у замка (свой потолок и свой период)
func bind_to_keep(c: Node3D, f: int) -> void:
	keep = c
	pen = null
	owner_faction = f
	lair = null
	home = (c as Node3D).global_position
	_breed_t = breed_sec() * (0.5 + 0.5 * fposmod(float(get_instance_id()) * 0.37, 1.0))
	_hop_t = 1.0

## Где центр выпаса и как далеко разрешено отходить. У ЗАГОНА радиус берётся у
## самой ограды и ЧУТЬ БОЛЬШЕ её (SheepPen.ROAM_FACTOR): овца обязана заходить
## и выходить, а не сидеть внутри как в клетке
func graze_home() -> Vector3:
	if pen != null and is_instance_valid(pen):
		return (pen as Node3D).global_position
	if keep != null and is_instance_valid(keep):
		return (keep as Node3D).global_position
	return home

func graze_radius() -> float:
	# ЗАГОН: первые INSIDE_CAP по порядку привязки — ВНУТРИ ограды, у центра;
	# лишние пасутся вокруг в OVERFLOW_RADIUS (письмо 10, спринт 19)
	if pen != null and is_instance_valid(pen) and pen.has_method("graze_radius_for"):
		return float(pen.call("graze_radius_for", self))
	if pen != null and is_instance_valid(pen) and pen.has_method("graze_radius"):
		return float(pen.call("graze_radius"))
	if keep != null and is_instance_valid(keep):
		# ЧИСЛО ОДНО И ЛЕЖИТ У ВЛАДЕЛЬЦА: CASTLE_GRAZE_RADIUS стоит рядом с
		# CASTLE_GRAZE_LIMIT, потому что это ОДНО правило — «пять овец в
		# радиусе двадцати метров». Вторая копия в goblin_config неминуемо
		# разошлась бы с первой при правке баланса
		return _UCfgS.CASTLE_GRAZE_RADIUS
	return _GobCfgS.SHEEP_GRAZE_RADIUS

## Период удвоения стада: загон вдвое быстрее замка (заказ спринта 13)
func breed_sec() -> float:
	if pen != null and is_instance_valid(pen):
		return _GobCfgS.SHEEP_BREED_PEN_SEC
	if keep != null and is_instance_valid(keep):
		return _GobCfgS.SHEEP_BREED_CASTLE_SEC
	return _GobCfgS.SHEEP_SELF_BREED_SEC

## Потолок стада по ПРИВЯЗКЕ (см. шапку полей)
func flock_limit() -> int:
	if pen != null and is_instance_valid(pen) and pen.has_method("capacity"):
		return int(pen.call("capacity"))
	if keep != null and is_instance_valid(keep):
		return _UCfgS.CASTLE_GRAZE_LIMIT
	return 0

## Сколько овец уже привязано к тому же загону/замку, что и эта
func flock_count() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s) or bool(s.get("eaten")):
			continue
		if bool(s.get("dead")):
			continue
		if pen != null and s.get("pen") == pen:
			n += 1
		elif pen == null and keep != null and s.get("keep") == keep:
			n += 1
	return n

## Приплод хозяйской овцы: копия рядом, с той же привязкой. Инстанс делается
## СВОИМ ЖЕ скриптом (get_script().new()), а не через preload — иначе файл
## пришлось бы предзагружать сам в себя
func breed_one() -> int:
	if flock_count() >= flock_limit():
		return 0
	# Глобальный потолок стада игрока (ТЗ 19.09.2026): 90 на сторону
	if not owned_cap_ok(owner_faction):
		return 0
	var par: Node = get_parent()
	if par == null:
		return 0
	var s: Node3D = (get_script() as GDScript).new()
	s.owner_faction = owner_faction
	s.pen = pen
	s.keep = keep
	s.home = graze_home()
	if pen != null and is_instance_valid(pen) and pen.has_method("next_seq"):
		s.bind_seq = int(pen.call("next_seq"))
	par.add_child(s)
	var ang: float = randf() * TAU
	var p: Vector3 = global_position + Vector3(cos(ang), 0.0, sin(ang)) * 1.6
	s.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
	return 1

func _ready() -> void:
	_breed_t = breed_sec() * (0.6 + 0.5 * fposmod(float(get_instance_id()) * 0.37, 1.0))
	add_to_group("sheep")
	_build_visual()
	_build_pick_body()
	_hop_t = randf_range(1.5, _GobCfgS.SHEEP_HOP_SEC)
	_snap_to_ground()
	set_process(true)

func _build_visual() -> void:
	var tex: Texture2D = _texture("idle", false)
	if tex == null:
		push_warning("Sheep: ленты не найдены в %s" % DIR)
		return
	var rows: Array = _rows()
	var fw: int = int(rows[2])
	var ch: int = int(rows[1]) - int(rows[0])
	var px: float = _GobCfgS.SHEEP_PIXEL_SIZE
	var q := QuadMesh.new()
	q.size = Vector2(float(fw) * px, float(ch) * px)
	_quad_h = q.size.y
	_mat = _BBUtilS.make_material(tex, Color.WHITE, 0.5, IDLE_FPS)
	_mat.set_shader_parameter("frame_count", float(frames_in(SHEET_IDLE)))
	_mat.set_shader_parameter("frame_fps", IDLE_FPS)
	_mat.set_shader_parameter("frame_phase", randf() * 8.0)
	q.material = _mat
	_mi = MeshInstance3D.new()
	_mi.name = "SheepSprite"
	_mi.mesh = q
	_mi.position.y = _quad_h * 0.5
	add_child(_mi)

func _set_anim(walking: bool, mirror: bool) -> void:
	if _mat == null:
		return
	if walking == _walking and mirror == _mirror and _mat.get_shader_parameter("frame_count") != null:
		pass
	_walking = walking
	_mirror = mirror
	var kind: String = "walk" if walking else "idle"
	var tex: Texture2D = _texture(kind, mirror)
	if tex == null:
		return
	_mat.set_shader_parameter("albedo_tex", tex)
	_mat.set_shader_parameter("frame_count", float(frames_in(SHEET_WALK if walking else SHEET_IDLE)))
	_mat.set_shader_parameter("frame_fps", WALK_FPS if walking else IDLE_FPS)

## Лента настроения: покой медленнее/быстрее или лежащий кадр (спринт 19)
func _set_mood_anim(kind: String, fps: float) -> void:
	if _mat == null:
		return
	var tex: Texture2D = _texture(kind, _mirror)
	if tex == null:
		return
	_walking = false
	_mat.set_shader_parameter("albedo_tex", tex)
	_mat.set_shader_parameter("frame_count", float(1 if kind == "rest" else frames_in(SHEET_IDLE)))
	_mat.set_shader_parameter("frame_fps", fps)

func mood() -> int:
	return _mood

## ── НАСТРОЕНИЯ НА ВЫПАСЕ (письмо 10: «пакет анимаций») ────────────────────
## Своего арта под «щиплет / оглядывается / лежит» у овцы нет — есть покой
## (8 кадров, движение головы) и прыжок (6 кадров, последний — лежит). Из
## них и собран выпас: перебежка (как прежде), прыжок на месте, лежание,
## медленное щипание. Жребий — из AudioManager.rng: общий поток посеян зерном
## партии, и лишний randf() сдвинул бы все жребии мира
func _pick_mood() -> void:
	var r: float = AudioManager.rng.randf()
	moods_seen += 1
	if r < 0.55:
		force_hop()
		return
	if r < 0.70:
		_mood = 1
		_mood_t = 0.75
		_set_anim(true, _mirror)
	elif r < 0.85:
		_mood = 2
		_mood_t = AudioManager.rng.randf_range(6.0, 12.0)
		_set_mood_anim("rest", 0.0)
	else:
		_mood = 3
		_mood_t = AudioManager.rng.randf_range(5.0, 9.0)
		_set_mood_anim("idle", IDLE_FPS * 0.5)

func is_walking() -> bool:
	return _walking

func is_mirrored() -> bool:
	return _mirror

func current_target() -> Vector3:
	return _target

func sprite_texture() -> Texture2D:
	if _mat == null:
		return null
	return _mat.get_shader_parameter("albedo_tex") as Texture2D

func _snap_to_ground() -> void:
	var p: Vector3 = global_position
	global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

## ── ПЕРЕБЕЖКА ──────────────────────────────────────────────────────────────
## Точка — в SHEEP_HOP_MIN…MAX от себя, но не дальше SHEEP_GRAZE_RADIUS от
## логова (иначе стадо за полчаса разбредается по карте); вода обходится
func force_hop() -> void:
	if dead:
		return
	var ang: float = randf() * TAU
	var dist: float = randf_range(_GobCfgS.SHEEP_HOP_MIN, _GobCfgS.SHEEP_HOP_MAX)
	var p: Vector3 = global_position + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
	# ЦЕНТР И РАДИУС — У ПРИВЯЗКИ: у дикой это логово, у хозяйской загон или
	# зона замка (graze_home / graze_radius). Радиус загона чуть больше самой
	# ограды, поэтому овца сама заходит внутрь и выходит наружу
	var gh: Vector3 = graze_home()
	var gr: float = graze_radius()
	var from_home: Vector3 = p - gh
	from_home.y = 0.0
	if from_home.length() > gr:
		# ── ТОЧКА ВНУТРИ КРУГА, А НЕ НА ЕГО КРОМКЕ (спринт 19) ──────────
		# Прежний зажим на 0.85 радиуса сажал стадо КОЛЬЦОМ по границе
		# выпаса: у загона это ограда, и внутри не стоял никто (скриншот
		# владельца). Теперь точка выбирается равномерно по кругу выпаса
		var ang2: float = AudioManager.rng.randf() * TAU
		var rr: float = gr * sqrt(AudioManager.rng.randf()) * 0.92
		p = gh + Vector3(cos(ang2) * rr, 0.0, sin(ang2) * rr)
	var xz: Vector2 = GameManager.clamp_to_map(p.x, p.z)
	p = GameManager.land_target(Vector3(xz.x, 0.0, xz.y))
	_target = Vector3(p.x, 0.0, p.z)
	hops += 1
	_set_anim(true, _target.x < global_position.x)

## Дошла (или стенд «телепортирует»): стоим и щиплем траву
func arrive_now() -> void:
	if _target.x != INF:
		global_position = Vector3(_target.x, GameManager.get_terrain_height(_target.x, _target.z), _target.z)
	_target = Vector3.INF
	_hop_t = _GobCfgS.SHEEP_HOP_SEC
	_set_anim(false, _mirror)

func _build_pick_body() -> void:
	var body := StaticBody3D.new()
	body.name = "SheepPick"
	body.collision_layer = Constants.LAYER_RESOURCES
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.3, 1.0)
	cs.shape = box
	cs.position.y = 0.65
	body.add_child(cs)
	add_child(body)

func is_free() -> bool:
	return not eaten and captor == null

func captured_by(w: Node3D) -> void:
	captor = w
	_carried = true
	_pinned = true
	_target = Vector3.INF
	_mood = 0
	# Перехват у тролля (письмо 10): рабочий отбил овцу из угоняемой отары
	herder = null
	_set_anim(false, _mirror)

func carry_to(p: Vector3) -> void:
	global_position = p

func drop_at(p: Vector3) -> void:
	_carried = false
	global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func release_from(w: Node3D) -> void:
	if captor != w:
		return
	captor = null
	_carried = false
	_pinned = false
	_snap_to_ground()
	_hop_t = 2.0
	# Блуждающую опустили не там, где взяли: пасётся отсюда (ТЗ 19.09.2026)
	if is_stray():
		home = global_position

func is_carried() -> bool:
	return _carried

## ── УВОДИТ ТРОЛЛЬ (спринт 18) ─────────────────────────────────────────────
## Овца в стаде рейда идёт за пастухом: прыжок раз в HERD_HOP_SEC к точке
## возле него; привязка к загону/замку снята сразу (хозяин её лишился)
const HERD_HOP_SEC := 1.2
const HERD_GAP := 2.2
var herder: Node3D = null

## ── ТУША (спринт 19, письмо 10) ───────────────────────────────────────────
## Мясо лежит У ТУШИ: MEAT_TRIPS кусков, их выносит АРТЕЛЬ (butcher_join, не
## больше MAX_BUTCHERS). Никто не режет CORPSE_DESPAWN_SEC подряд — туша
## истлевает (consume). Свежая туша окровавлена (BLOOD_TINT в modulate)
const MEAT_TRIPS := 20
const MAX_BUTCHERS := 4
const CORPSE_DESPAWN_SEC := 120.0
const BLOOD_TINT := Color(0.78, 0.40, 0.40, 1.0)
var meat_left: int = 0
var butchers: Array = []
var _corpse_t: float = 0.0
var killed_by: Node3D = null
## Порядок привязки к загону: первые SheepPen.INSIDE_CAP пасутся ВНУТРИ ограды
var bind_seq: int = 0
## Настроение на выпасе (см. _pick_mood): 0 покой, 1 прыжок на месте,
## 2 лежит, 3 щиплет медленно
var _mood: int = 0
var _mood_t: float = 0.0
var moods_seen: int = 0

func herd_by(t: Node3D) -> void:
	herder = t
	pen = null
	keep = null
	owner_faction = -1
	_pinned = false
	_hop_t = 0.2

func release_herd() -> void:
	herder = null
	_hop_t = 1.0

## ── КРАСНОГО МИГАНИЯ БОЛЬШЕ НЕТ ВОВСЕ (заказ спринта 13) ──────────────────
## История ручки короткая и однонаправленная: (1.7, 0.45, 0.45) → мягкое
## (1.35, 0.85, 0.85) → снято. Причина та же, по которой его и убавляли:
## ударов на тушу двадцать с лишним, и любая подкраска читается как ошибка
## отрисовки, а не как удар. Смысловая половина функции ОСТАЛАСЬ и она
## главная — удар СБРАСЫВАЕТ ПОКОЙ, а тревожная овца не плодится
func wound_flash() -> void:
	_calm_t = 0.0
	_breed_t = maxf(_breed_t, _GobCfgS.SHEEP_CALM_SEC)

## ── СМЕРТЬ И ИСЧЕЗНОВЕНИЕ — ДВА РАЗНЫХ СОБЫТИЯ ────────────────────────────
## «5 ударов ножом → смерть», а мясо выносится ходками ещё две-три минуты.
## Значит, туша обязана ЛЕЖАТЬ НА ЭКРАНЕ всё это время. kill_flip() кладёт её
## на бок, consume() убирает, когда мясо кончилось.
##
## НА БОК КЛАДЁТСЯ УЗЕЛ, А НЕ ЛЕНТА: своего «мёртвого» арта у овцы нет, а
## билборд cyl_billboard разворачивает квад к камере сам и любой поворот
## съедает. Тот же приём, что у тела тролля, — world_fixed = 1 снимает
## билборд, после чего поворот вокруг Z доезжает до экрана
func kill_flip() -> void:
	if dead or eaten:
		return
	dead = true
	meat_left = MEAT_TRIPS
	_corpse_t = 0.0
	_mood = 0
	herder = null
	# Логово узнаёт о потере: последняя овца — таймер новой отары (спринт 18)
	if lair != null and is_instance_valid(lair) and lair.has_method("on_sheep_eaten"):
		lair.call("on_sheep_eaten", self)
	_target = Vector3.INF
	_pinned = true
	# ── ТУША НЕ ДЫШИТ (ТЗ 19.09.2026, блок 4) ──────────────────────────────
	# Прежний kill_flip ставил ленту ПОКОЯ (8 кадров, 6 к/с), и мёртвая овца
	# продолжала листать дыхание. Кадр ФИКСИРУЕТСЯ: один кадр (лежащий, из
	# «rest» — последний кадр прыжка), frame_fps 0 — шейдер при нуле показывает
	# кадр 0 и часов TIME не читает. Спрайт ТОТ ЖЕ, овечий — никакой иконки
	# мяса на земле нет и быть не должно (уточнение владельца)
	_walking = false
	if _mat != null:
		var tex: Texture2D = _texture("rest", _mirror)
		if tex == null:
			tex = _texture("idle", _mirror)
		if tex != null:
			_mat.set_shader_parameter("albedo_tex", tex)
		_mat.set_shader_parameter("frame_count", 1.0)
		_mat.set_shader_parameter("frame_fps", 0.0)
		_mat.set_shader_parameter("world_fixed", 1.0)
		# Окровавленная туша (письмо 10): подкраска, а не мигание
		_mat.set_shader_parameter("modulate", BLOOD_TINT)
	if _mi != null:
		# НОГАМИ ВВЕРХ: квад в мировой ориентации (world_fixed — ракурс камеры
		# в игре зафиксирован) перевёрнут на 180° вокруг оси взгляда. Прежнее
		# «на бок» (±90°) развёрнуто ТЗ 19.09.2026. Высота — та же, что у
		# живой: квад той же высоты, центр на половине, ноги (теперь сверху)
		# на высоте бывшей головы, спина на земле
		_mi.rotation_degrees = Vector3(0.0, 0.0, 180.0)
		_mi.position.y = _quad_h * 0.5

func is_dead_body() -> bool:
	return dead

## ── ТУША: КТО РЕЖЕТ И СКОЛЬКО ОСТАЛОСЬ (спринт 19) ────────────────────────
## Убить может любой боец одним ударом (Unit._hunt_arrival) или рабочий
## пятью надрезами; и там и там — сюда
func kill_by(who: Node3D) -> void:
	if dead or eaten:
		return
	# Овца, взятая рабочим (captured_by), числится «на руках» и до
	# смерти: нож режет её на месте, и признак переноски снимается здесь —
	# иначе туша оставалась живой, и рабочий резал её по кругу
	_carried = false
	killed_by = who
	kill_flip()

func _prune_butchers() -> void:
	var i: int = butchers.size() - 1
	while i >= 0:
		var b = butchers[i]
		if b == null or not is_instance_valid(b) or bool(b.call("is_dead")):
			butchers.remove_at(i)
		i -= 1

func butcher_has_room() -> bool:
	_prune_butchers()
	return butchers.size() < MAX_BUTCHERS

func butcher_join(w: Node3D) -> bool:
	if not dead or eaten or w == null:
		return false
	_prune_butchers()
	if butchers.has(w):
		return true
	if butchers.size() >= MAX_BUTCHERS:
		return false
	butchers.append(w)
	return true

func butcher_leave(w: Node3D) -> void:
	butchers.erase(w)

func butcher_count() -> int:
	_prune_butchers()
	return butchers.size()

## Отрезать кусок: false — мясо кончилось
func take_meat() -> bool:
	if meat_left <= 0:
		return false
	meat_left -= 1
	return true

## Мясо кончилось — туша исчезает
func consume() -> void:
	eat()

## Совместимость: прежний путь «разделана и исчезла» одним движением
func butchered() -> void:
	consume()

func _process(delta: float) -> void:
	# Часы стада включает только стенд (prof_on); в партии — одно сравнение
	if prof_on:
		var t0: int = Time.get_ticks_usec()
		_step(delta)
		prof_usec += Time.get_ticks_usec() - t0
		prof_calls += 1
		return
	_step(delta)

func _step(delta: float) -> void:
	if eaten or _carried:
		return
	# ── ТУША ЛЕЖИТ: НИ ХОДЬБЫ, НИ ПРИПЛОДА ────────────────────────────────
	# Никто не режет — истлевает за CORPSE_DESPAWN_SEC (письмо 10); часы
	# идут только пока у туши нет ни одного рабочего
	if dead:
		if butchers.is_empty() or butcher_count() == 0:
			_corpse_t += delta
			if _corpse_t >= CORPSE_DESPAWN_SEC:
				consume()
		return
	# ── НАСТРОЕНИЕ НА ВЫПАСЕ (спринт 19): лежит, прыгает, щиплет ───────────
	if _mood != 0:
		_mood_t -= delta
		if _mood_t <= 0.0:
			_mood = 0
			_set_anim(false, _mirror)
			_hop_t = AudioManager.rng.randf_range(1.0, 3.0)
	# ── РАЗМНОЖЕНИЕ: ТОЛЬКО ЦЕЛАЯ И СПОКОЙНАЯ ОВЦА ─────────────────────────
	# Приплод раздаёт ПРИВЯЗКА: у дикой — логово (у него свой потолок стада),
	# у хозяйской — она сама (breed_one, потолок загона или зоны замка)
	_calm_t += delta
	_breed_t -= delta
	if _breed_t <= 0.0:
		_breed_t = breed_sec()
		if _calm_t >= _GobCfgS.SHEEP_CALM_SEC and captor == null:
			if is_owned():
				bred += breed_one()
			elif lair != null and is_instance_valid(lair) \
					and lair.has_method("spawn_sheep"):
				bred += int(lair.call("spawn_sheep", 1))
	# За пастухом (рейд тролля): цель — точка у него, по своему такту
	if herder != null:
		if not is_instance_valid(herder) or bool(herder.get("is_dead_flag")):
			herder = null
		else:
			_hop_t -= delta
			if _hop_t <= 0.0:
				_hop_t = HERD_HOP_SEC
				var hp: Vector3 = (herder as Node3D).global_position
				var k: float = float(get_instance_id() % 7) * 0.9
				var off := Vector3(cos(k) * HERD_GAP, 0.0, sin(k) * HERD_GAP)
				var tp: Vector3 = GameManager.land_target(hp + off)
				_target = Vector3(tp.x, 0.0, tp.z)
				_set_anim(true, _target.x < global_position.x)
	if _target.x == INF:
		if not _pinned and _mood == 0:
			_hop_t -= delta
		if _hop_t <= 0.0 and _mood == 0:
			if herder != null or captor != null:
				force_hop()
			else:
				_pick_mood()
	else:
		var d: Vector3 = _target - global_position
		d.y = 0.0
		var dist: float = d.length()
		var step: float = _GobCfgS.SHEEP_SPEED * delta
		if dist <= maxf(step, 0.12):
			arrive_now()
		else:
			var np: Vector3 = global_position + d / dist * step
			global_position = Vector3(np.x, GameManager.get_terrain_height(np.x, np.z), np.z)
	# Туман — по своей точке, не чаще двух раз в секунду
	_fog_t -= delta
	if _fog_t <= 0.0:
		_fog_t = 0.5
		var fog = GameManager.fog
		var lit: bool = fog == null or not fog.enabled or fog.is_lit(global_position.x, global_position.z)
		if _mi != null:
			_mi.visible = lit

## Тролль съел: исчезает мгновенно, логово узнаёт
func eat() -> void:
	if eaten:
		return
	eaten = true
	if lair != null and is_instance_valid(lair) and lair.has_method("on_sheep_eaten"):
		lair.call("on_sheep_eaten", self)
	queue_free()
