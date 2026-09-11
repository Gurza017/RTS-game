extends Building

## ═══════════════════════════════════════════════════════════════════════════
## ЛОГОВО ТРОЛЛЯ — МЁРТВОЕ ДЕРЕВО (заказ владельца, 09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Постройка третьей стороны: картинка Dead Tree в масштабе тролля, вокруг —
## декор из черепов на кольях и костей (Root Troll/*). Выпускает стражей:
## стартовых при закладке и подмогу, когда тролль просел до половины
## (Troll.take_damage → call_guards). Знает, сколько троллей живо: по нулю
## GoblinAI заводит «месть гоблинов» (см. goblin_config.REVENGE_*).
##
## В группе goblin_buildings, но НЕ Castle: гарнизона, найма и склада у дерева
## нет, а вожак орды хижины ищет по классу GoblinHut (см. GoblinAI._huts —
## там по группе, поэтому «разбитый отряд идёт лечиться» в дерево не пойдёт:
## request_garrison у него нет, is_instance_valid + has_method стерегут).
##
## Файл без class_name: подключается через preload/load.

const _UCfgL  := preload("res://scripts/unit_stats_config.gd")
const _GobCfgL := preload("res://scripts/goblin/goblin_config.gd")
const _BBUtilL := preload("res://scripts/BillboardUtil.gd")
const _TrollScene := preload("res://scenes/units/Troll.tscn")
const _SheepScript := preload("res://scripts/goblin/Sheep.gd")
const _GnollScene := preload("res://scenes/units/Gnoll.tscn")

const ART_DIR := "res://assets/factions/orc/Troll/Root Troll/"
const TREE_SPRITE := ART_DIR + "Dead Tree.png"
const SPIKES := ["Skull Spike_01.png", "Skull Spike_02.png"]
const BONES  := ["Bones_01.png", "Bones_02.png", "Bones_03.png"]

## Живые тролли логова (сырые ссылки; чистятся по правилу 5)
var trolls: Array = []
var _spawned_total: int = 0
## ── АГРО-ЦЕПОЧКА (заказ 10.09.2026) ────────────────────────────────────────
## 0 — тихо; 1 — по первому удару вышли TROLL_AGGRO_HELPERS, группа дерётся;
## 2 — группа выбита, вышла бонусная пара (один раз), дальше стандартно.
## aggro_enabled — ручка для стендов, которым нужен предсказуемый один тролль
var aggro_wave: int = 0
var aggro_enabled: bool = true
var aggro_spawns: int = 0
var _last_attacker: Node3D = null
## Стадо овец вокруг логова (Sheep.gd): узлы-декорации, не бойцы
## ── СТАЯ ГНОЛЛОВ (заказ спринта 13) ───────────────────────────────────────
## «3 отряда на старте; если по пню бьют — ещё 3 через 3 минуты и ещё 3 через
## 3 минуты (три волны); после третьей — откат 10 минут, если пень жив».
##
## ЧАСЫ ВОЛН ЛИЧНЫЕ И ВЗВОДЯТСЯ УДАРОМ, А НЕ НАЧАЛОМ ПАРТИИ. Иначе стая
## приходила бы к игроку, который логова вообще не касался, — а заказ прямо
## говорит «если по пню бьют». Взводит их `on_lair_attacked`, и зовут её оба
## пути: удар по самому пню (take_damage) и удар по любому его стражу
## (Troll.take_damage → on_guard_hit, Gnoll.take_damage → on_gnoll_hit).
var gnolls: Array = []
var gnoll_squads: Array = []
## Сколько волн уже вышло (0 — только стартовые отряды)
var gnoll_wave: int = 0
var _gnoll_alarmed: bool = false
## Стенды: сколько отрядов стаи выпущено всего
var gnoll_squads_total: int = 0

var sheep: Array = []
var sheep_born: int = 0
var _flock_timer: Timer = null

func _ready() -> void:
	building_id  = "troll_lair"
	sprite_path  = TREE_SPRITE
	max_health   = _UCfgL.building_stat("troll_lair", "max_hp", 8000.0)
	build_size   = _UCfgL.building_size("troll_lair", Vector3(12.0, 8.0, 12.0))
	display_name = String(_UCfgL.building_cfg("troll_lair").get("name", "Логово тролля"))
	is_dropoff   = false
	super._ready()
	call_deferred("_build_decor")
	call_deferred("_start_flock")
	call_deferred("_start_gnoll_pack")
	# Реестр партии: при загрузке слепка логово встаёт из фабрики зданий, и
	# Main его не регистрирует — регистрируется само. Тролли из слепка
	# подхватывают его лениво (Troll.tick_physics)
	GameManager.troll_lair = self

## Принять тролля, рождённого не здесь (загрузка партии)
# ═════════════════════════════════════════════════════════════════════════════
# СТАДО ОВЕЦ (заказ владельца, 10.09.2026)
# ═════════════════════════════════════════════════════════════════════════════
## При появлении логова — SHEEP_START овец, дальше раз в SHEEP_BREED_SEC ещё
## SHEEP_BREED_COUNT до потолка SHEEP_MAX. Таймер — узел под логовом: у
## логова нет своего тика (_needs_tick = false), и заводить его ради стада
## незачем. Тролль ест овец сам (Troll._tick_hunger)
# ═════════════════════════════════════════════════════════════════════════════
# СТАЯ ГНОЛЛОВ
# ═════════════════════════════════════════════════════════════════════════════
## Выпустить n ОТРЯДОВ гноллов у пня. Размер отряда — уставной
## (goblin_config.SQUAD_SIZE), раскладка — толпой, тем же путём, каким выходят
## все отряды орды: Main.spawn_goblin_squad. Второго кода спавна орды в
## проекте быть не должно
func spawn_gnoll_squads(n: int) -> int:
	if n <= 0 or is_dead():
		return 0
	var main = GameManager.main
	if main == null or not is_instance_valid(main) \
			or not main.has_method("spawn_goblin_squad"):
		return 0
	var size: int = int(_GobCfgL.SQUAD_SIZE.get("gnoll", 12))
	var made := 0
	for i in range(n):
		# Отряды разводятся по кольцу вокруг пня: три отряда, вышедшие в одну
		# точку, расталкивались бы полминуты (та же причина, что у полос
		# выхода из зданий)
		var a: float = TAU * float(gnoll_squads_total) * 0.618 + 0.9
		var r: float = _GobCfgL.GNOLL_PATROL_RADIUS * 0.55
		var px: float = global_position.x + cos(a) * r
		var pz: float = global_position.z + sin(a) * r
		var base: Vector3 = GameManager.land_target(
			Vector3(px, 0.0, pz))
		var sid: int = int(main.call("spawn_goblin_squad", "gnoll", size, base))
		if sid <= 0:
			continue
		gnoll_squads.append(sid)
		gnoll_squads_total += 1
		made += 1
		# Каждый гнолл узнаёт свой пень: по нему считаются патруль и фланг
		for u in GameManager.squad_members(sid):
			if u == null or not is_instance_valid(u):
				continue
			u.set("lair", self)
			(u as Unit).post_pos = (u as Unit).global_position
			gnolls.append(u)
	return made

## Стартовая стая: GNOLL_START_SQUADS отрядов при появлении пня.
## Отложенно, как и стадо: в _ready точка узла ещё нулевая
func _start_gnoll_pack() -> void:
	if is_dead():
		return
	spawn_gnoll_squads(_GobCfgL.GNOLL_START_SQUADS)

## ── ЧАСЫ ВОЛН — УЗЕЛ-ТАЙМЕР, А НЕ СВОЙ ТИК ────────────────────────────────
## У логова нет _process вовсе (_needs_tick = false), и заводить его ради
## одного сложения раз в три минуты незачем — ровно тот же выбор и та же
## причина, что у таймера стада
var _gnoll_timer: Timer = null

## Первый удар по пню или по любому его стражу взводит часы волн
func on_lair_attacked() -> void:
	if _gnoll_alarmed or is_dead():
		return
	_gnoll_alarmed = true
	if _gnoll_timer == null:
		_gnoll_timer = Timer.new()
		_gnoll_timer.one_shot = true
		add_child(_gnoll_timer)
		_gnoll_timer.timeout.connect(_on_gnoll_wave)
	_gnoll_timer.wait_time = _GobCfgL.GNOLL_WAVE_SEC
	_gnoll_timer.start()

## Удар по гноллу — тот же сигнал тревоги, что и удар по троллю
func on_gnoll_hit(_g: Node, _attacker: Node3D) -> void:
	on_lair_attacked()

## Живых гноллов (стенды)
func gnolls_alive() -> int:
	var alive: Array = []
	for g in gnolls:
		if g != null and is_instance_valid(g) and not (g as Unit).is_dead():
			alive.append(g)
	gnolls = alive
	return gnolls.size()

## Сколько секунд до следующей волны (стенды); INF — часы не взведены
func gnoll_wave_left() -> float:
	if not _gnoll_alarmed or _gnoll_timer == null:
		return INF
	return _gnoll_timer.time_left

## Волна пришла. Стенды зовут это напрямую, не дожидаясь трёх минут
func _on_gnoll_wave() -> void:
	if is_dead():
		return
	if gnoll_wave < _GobCfgL.GNOLL_WAVES_MAX:
		gnoll_wave += 1
		spawn_gnoll_squads(_GobCfgL.GNOLL_WAVE_SQUADS)
		# ПОСЛЕ ТРЕТЬЕЙ ВОЛНЫ — ДЛИННЫЙ ОТКАТ, а не остановка: пень жив,
		# значит стая когда-нибудь восстановится (прямой заказ)
		if _gnoll_timer != null:
			_gnoll_timer.wait_time = _GobCfgL.GNOLL_WAVE_SEC 				if gnoll_wave < _GobCfgL.GNOLL_WAVES_MAX 				else _GobCfgL.GNOLL_COOLDOWN_SEC
			_gnoll_timer.start()
		return
	# Откат истёк — счёт волн начинается заново
	gnoll_wave = 0
	if _gnoll_timer != null:
		_gnoll_timer.wait_time = _GobCfgL.GNOLL_WAVE_SEC
		_gnoll_timer.start()

func _start_flock() -> void:
	if not _SheepScript.sheets_ok() or is_dead():
		return
	spawn_sheep(_GobCfgL.SHEEP_START)
	_flock_timer = Timer.new()
	_flock_timer.wait_time = _GobCfgL.SHEEP_BREED_SEC
	_flock_timer.one_shot = false
	add_child(_flock_timer)
	_flock_timer.timeout.connect(breed_sheep)
	_flock_timer.start()

## Прирост по таймеру; возвращает, сколько родилось (0 на потолке)
func breed_sheep() -> int:
	var room: int = _GobCfgL.SHEEP_MAX - sheep_alive()
	return spawn_sheep(mini(_GobCfgL.SHEEP_BREED_COUNT, maxi(room, 0)))

func spawn_sheep(n: int) -> int:
	var parent := get_parent()
	if parent == null or is_dead():
		return 0
	var made := 0
	for _i in range(n):
		if sheep_alive() >= _GobCfgL.SHEEP_MAX:
			break
		var a: float = TAU * float(sheep_born) * 0.618 + 1.3
		var r: float = maxf(build_size.x, build_size.z) * 0.5 + _GobCfgL.LAIR_DECOR_RING + 3.0 + 4.0 * fposmod(float(sheep_born) * 0.37, 1.0)
		var p: Vector3 = GameManager.land_target(Vector3(global_position.x + cos(a) * r, 0.0, global_position.z + sin(a) * r))
		var s: Node3D = _SheepScript.new()
		s.set("lair", self)
		s.set("home", global_position)
		parent.add_child(s)
		s.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		sheep.append(s)
		sheep_born += 1
		made += 1
	return made

func sheep_alive() -> int:
	var live: Array = []
	for s in sheep:
		if s != null and is_instance_valid(s) and not bool(s.get("eaten")):
			live.append(s)
	sheep = live
	return sheep.size()

func nearest_sheep(from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	sheep_alive()
	for s in sheep:
		var d: float = from.distance_squared_to((s as Node3D).global_position)
		if d < bd:
			bd = d
			best = s
	return best

func on_sheep_eaten(s: Node) -> void:
	sheep.erase(s)

func adopt(u: Unit) -> void:
	if u == null or not is_instance_valid(u) or trolls.has(u):
		return
	trolls.append(u)
	_spawned_total += 1

## Здание не тикает: ни очереди, ни дохода
func _needs_tick() -> bool:
	return false

## Обзор чужой постройке не нужен, но метод общий — оставляем базовый

## ── ДЕКОР: КОЛЬЯ С ЧЕРЕПАМИ И КОСТИ ────────────────────────────────────────
## Колья — вертикальные билборды тем же материалом, что здания (мировая
## ориентация, компенсация наклона); кости — квады ПЛАШМЯ на земле, как
## маркер выделения. Точки детерминированы от номера узла: два прогона
## стенда дают одно логово
func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id() % 100003)
	var ring: float = maxf(build_size.x, build_size.z) * 0.5 + _GobCfgL.LAIR_DECOR_RING
	var n_sp: int = _GobCfgL.LAIR_SPIKES
	for i in range(n_sp):
		var a: float = TAU * float(i) / float(n_sp) + rng.randf_range(-0.25, 0.25)
		var r: float = ring + rng.randf_range(-1.0, 1.5)
		_add_spike(SPIKES[i % SPIKES.size()], Vector3(cos(a) * r, 0.0, sin(a) * r), rng, i)
	var n_b: int = _GobCfgL.LAIR_BONES
	for j in range(n_b):
		var a2: float = rng.randf() * TAU
		var r2: float = rng.randf_range(build_size.x * 0.45, ring + 3.0)
		_add_bones(BONES[j % BONES.size()], Vector3(cos(a2) * r2, 0.0, sin(a2) * r2), rng, j)

func _add_spike(file: String, at: Vector3, rng: RandomNumberGenerator, idx: int) -> void:
	var path: String = ART_DIR + file
	if not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var quad := QuadMesh.new()
	var h: float = _GobCfgL.LAIR_SPIKE_H * rng.randf_range(0.9, 1.1)
	var aspect: float = _BBUtilL.frame_aspect(tex)
	quad.size = Vector2(h * maxf(aspect, 0.1), h)
	quad.material = _BBUtilL.make_static_material(tex, Color.WHITE, 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "Spike%d" % idx
	mi.mesh = quad
	var gy: float = GameManager.get_terrain_height(global_position.x + at.x,
		global_position.z + at.z) - global_position.y
	mi.position = Vector3(at.x, gy + quad.size.y * 0.5, at.z)
	add_child(mi)

func _add_bones(file: String, at: Vector3, rng: RandomNumberGenerator, idx: int) -> void:
	var path: String = ART_DIR + file
	if not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var quad := QuadMesh.new()
	var s: float = _GobCfgL.LAIR_BONES_M * rng.randf_range(0.8, 1.2)
	quad.size = Vector2(s, s)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Bones%d" % idx
	mi.mesh = quad
	var gy: float = GameManager.get_terrain_height(global_position.x + at.x,
		global_position.z + at.z) - global_position.y
	mi.position = Vector3(at.x, gy + 0.04, at.z)
	mi.rotation_degrees = Vector3(-90.0, rng.randf() * 360.0, 0.0)
	add_child(mi)

# ═════════════════════════════════════════════════════════════════════════════
# СТРАЖИ
# ═════════════════════════════════════════════════════════════════════════════
## Выпустить n троллей у дверей. Каждый — свой отряд из одного (для морали,
## опыта и панели). Возвращает список выпущенных
func spawn_guards(n: int) -> Array:
	var out: Array = []
	var parent := get_parent()
	if parent == null:
		return out
	for i in range(n):
		var u: Unit = _TrollScene.instantiate()
		u.faction = Constants.FACTION_GOBLIN
		u.set("lair", self)
		parent.add_child(u)
		var a: float = TAU * float(_spawned_total) * 0.618 + 0.4
		var r: float = maxf(build_size.x, build_size.z) * 0.5 + 3.0
		var px: float = global_position.x + cos(a) * r
		var pz: float = global_position.z + sin(a) * r
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		var sid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "troll")
		GameManager.add_to_squad(sid, u)
		u.post_pos = u.global_position
		trolls.append(u)
		_spawned_total += 1
		out.append(u)
	return out

## Подмога на половине запаса: выходят ещё n троллей и идут к обидчику
func call_guards(n: int, wounded: Node3D) -> void:
	if is_dead():
		return
	var fresh: Array = spawn_guards(n)
	# Мстят тому, кто бьёт раненого: его цель — и их цель
	var foe: Node3D = null
	if wounded != null and is_instance_valid(wounded):
		var t = wounded.get("attack_target")
		if t != null and is_instance_valid(t):
			foe = t as Node3D
	for u in fresh:
		if foe != null:
			(u as Unit).command_attack(foe, true, true)

## Удар по стражу: тролль агрится на обидчика, первый удар по группе поднимает
## помощников из логова — сразу, без таймеров и порогов запаса
func on_guard_hit(troll: Node, attacker: Node3D) -> void:
	# ЧАСЫ ВОЛН ГНОЛЛОВ ВЗВОДИТ ЛЮБОЙ УДАР ПО ЛОГОВУ ИЛИ ЕГО СТРАЖЕ: заказ
	# говорит «если по пню бьют», а бьют по нему в трёх местах — по самому
	# пню, по троллю и по гноллу. Все три ведут в on_lair_attacked
	on_lair_attacked()
	if attacker != null and is_instance_valid(attacker):
		_last_attacker = attacker
		var t := troll as Unit
		if t != null and is_instance_valid(t) and not t.is_dead() and t.attack_target == null:
			t.command_attack(attacker, true, true)
	if not aggro_enabled or aggro_wave != 0 or is_dead():
		return
	aggro_wave = 1
	var fresh: Array = spawn_guards(_GobCfgL.TROLL_AGGRO_HELPERS)
	aggro_spawns += fresh.size()
	for u in fresh:
		if attacker != null and is_instance_valid(attacker):
			(u as Unit).command_attack(attacker, true, true)

func on_troll_died(u: Node) -> void:
	_prune()
	# Гибнущий ещё не помечен мёртвым (зовут до super._die) — считаем без него
	var left := 0
	for t in trolls:
		if t != u and t != null and is_instance_valid(t) and not (t as Unit).is_dead():
			left += 1
	if aggro_enabled and aggro_wave == 1 and left == 0 and not is_dead():
		# ГРУППА ВЫБИТА — МГНОВЕННО ЕЩЁ ПАРА, вне всяких таймеров; у неё
		# уже стандартная подмога на трети запаса, повторного вызова нет
		aggro_wave = 2
		var bonus: Array = spawn_guards(_GobCfgL.TROLL_AGGRO_BONUS)
		aggro_spawns += bonus.size()
		for b in bonus:
			b.set("standard_reinforce", true)
			if _last_attacker != null and is_instance_valid(_last_attacker):
				(b as Unit).command_attack(_last_attacker, true, true)

func _prune() -> void:
	var alive: Array = []
	for t in trolls:
		if t != null and is_instance_valid(t) and not (t as Unit).is_dead():
			alive.append(t)
	trolls = alive

## Сколько троллей живо
func trolls_alive() -> int:
	_prune()
	return trolls.size()

## Удар по самому пню: тот же сигнал тревоги, что и удар по страже
func take_damage(amount: float, attacker: Node = null) -> void:
	super.take_damage(amount, attacker)
	if not is_dead():
		on_lair_attacked()

## Логово зачищено: хоть один тролль когда-то был, и живых нет
func is_cleared() -> bool:
	return _spawned_total > 0 and trolls_alive() == 0
