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
	var strip := Image.create(fw * frames, ch, false, img.get_format())
	for f in range(frames):
		var fr: Image = img.get_region(Rect2i(f * fw, top, fw, ch))
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

## Утиный контракт SheepPen.accept_sheep
func bind_to_pen(p: Node3D, f: int) -> void:
	pen = p
	keep = null
	owner_faction = f
	lair = null
	home = (p as Node3D).global_position
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
	var par: Node = get_parent()
	if par == null:
		return 0
	var s: Node3D = (get_script() as GDScript).new()
	s.owner_faction = owner_faction
	s.pen = pen
	s.keep = keep
	s.home = graze_home()
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
		p = gh + from_home.normalized() * gr * 0.85
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

func is_carried() -> bool:
	return _carried

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
	_target = Vector3.INF
	_pinned = true
	_set_anim(false, _mirror)
	if _mat != null:
		_mat.set_shader_parameter("world_fixed", 1.0)
	if _mi != null:
		# Овца ложится на бок: голова влево или вправо — от номера узла, а не
		# случайно (два прогона стенда обязаны дать одну картинку)
		var side: float = 1.0 if (get_instance_id() % 2) == 0 else -1.0
		_mi.rotation_degrees = Vector3(0.0, 0.0, 90.0 * side)
		# Лёжа квад «высок» ровно на свою ШИРИНУ: подъём считается по ней,
		# иначе туша висит в воздухе или тонет в грунте
		_mi.position.y = _quad_h * 0.28

func is_dead_body() -> bool:
	return dead

## Мясо кончилось — туша исчезает
func consume() -> void:
	eat()

## Совместимость: прежний путь «разделана и исчезла» одним движением
func butchered() -> void:
	consume()

func _process(delta: float) -> void:
	if eaten or _carried:
		return
	# ── ТУША ЛЕЖИТ: НИ ХОДЬБЫ, НИ ПРИПЛОДА ────────────────────────────────
	if dead:
		return
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
	if _target.x == INF:
		if not _pinned:
			_hop_t -= delta
		if _hop_t <= 0.0:
			force_hop()
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
