extends Building
class_name Mine

## ═══════════════════════════════════════════════════════════════════════════
## ЗОЛОТОЙ РУДНИК: ЗАХВАТ ПЕХОТОЙ, РАБОЧИЕ ВНУТРИ, ФЛАГ ВЛАДЕЛЬЦА (10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Три состояния — три картинки из assets/environment/resources/Gold_mine:
##   Inactive  — пустой: ничей или без рабочих внутри;
##   Active    — светится: внутри рабочие владельца;
##   Destroyed — руина (spawn_ruin); её восстанавливает рабочий кликом, руина
##               рудника ОБЩАЯ — отстроить может любая сторона, и рудник
##               достаётся тому, кто отстроил (meta ruin_any_faction).
## ЗАХВАТ: пехота ОДНОЙ стороны в CAPTURE_RADIUS без чужих бойцов CAPTURE_SEC
## подряд — рудник переходит к ней, над ним встаёт флажок цвета стороны
## (вымпел без лычек, BannerArt.faction_flag_texture). Пока рядом чужие
## защитники (в том числе гоблины и тролли) — не захватить. Рабочие в захват
## не идут (они добывают, а не воюют), гарнизон внутри тоже.
## ДОХОД: владельцу INCOME_BASE золота в секунду плюс INCOME_PER_WORKER за
## каждого рабочего внутри (не больше WORKER_CAP). Ничейный не платит никому.
## РАБОЧИЙ ЗАХОДИТ ВНУТРЬ тем же путём, что на стройку (ПКМ по руднику →
## Worker.command_build: work_position/add_builder — утиный контракт
## ConstructionSite), внутри скрыт как гарнизон замка (absorb), выходит ПКМ
## по руднику пустым выделением (release_all) или при гибели рудника.
## СМЕНА ВЛАДЕЛЬЦА НЕ ВЫГОНЯЕТ РАБОЧИХ — они переходят новому хозяину:
## сторона, строка ядра, отряд и ленты цветовой папки перекрашиваются
## (_recolor_worker).
## Фракция NEUTRAL (Constants.FACTION_NEUTRAL) — своя группа зданий, в
## «чужие» она никому не входит: ИИ и орда её не штурмуют, условие победы её
## не считает.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _BannerArtM := preload("res://scripts/BannerArt.gd")
const _SquadBannerM := preload("res://scripts/SquadBanner.gd")
const _GSM := preload("res://scripts/game_settings.gd")

const ART_DIR := "res://assets/environment/resources/Gold_mine/"
const SPRITE_INACTIVE  := ART_DIR + "GoldMine_Inactive.png"
const SPRITE_ACTIVE    := ART_DIR + "GoldMine_Active.png"
const SPRITE_DESTROYED := ART_DIR + "GoldMine_Destroyed.png"

## Радиус захвата вокруг рудника, м, и сколько секунд подряд пехота одной
## стороны должна стоять в нём без чужих
const CAPTURE_RADIUS := 8.0
const CAPTURE_SEC := 3.0
const CAPTURE_TICK := 0.25
## Доход владельцу: золота в секунду за сам рудник и за каждого рабочего
const INCOME_BASE := 10.0
const INCOME_PER_WORKER := 1.0
const WORKER_CAP := 5
## Флажок владельца: смещение от центра рудника (по земле) и высота древка
const FLAG_OFFSET := Vector3(-1.7, 0.0, 0.8)
const FLAG_Y := 1.55

signal captured(new_faction)

## Рабочие внутри (скрыты, как гарнизон)
var workers: Array = []
## Счётчики для стендов
var captures: int = 0
var income_total: float = 0.0

var _capture_by: int = -1
var _capture_t: float = 0.0
var _tick_t: float = 0.0
var _income_acc: float = 0.0
var _flag: MeshInstance3D = null
var _state_sprite: String = ""
var _base_name: String = "Золотой рудник"

func _ready() -> void:
	building_id  = "mine"
	sprite_path  = SPRITE_INACTIVE
	max_health   = _UCfg.building_stat("mine", "max_hp", 250.0)
	build_size   = _UCfg.building_size("mine", Vector3(3.0, 2.0, 3.0))
	_base_name   = String(_UCfg.building_cfg("mine").get("name", "Золотой рудник"))
	display_name = _base_name
	is_dropoff   = false
	super._ready()
	_refresh_flag()
	_refresh_sprite()
	_refresh_name()
	set_process(true)

## Картинка заменяет процедурный вид целиком: здесь только форма клика и маркер
func _build_visual() -> void:
	_add_pick_shape()
	selection_ring = make_selection_marker()
	add_child(selection_ring)

func is_neutral() -> bool:
	return faction == Constants.FACTION_NEUTRAL

func is_active() -> bool:
	return not workers.is_empty()

func has_room() -> bool:
	return workers.size() < WORKER_CAP

func income_per_sec() -> float:
	if is_neutral():
		return 0.0
	return INCOME_BASE + INCOME_PER_WORKER * float(workers.size())

func _needs_tick() -> bool:
	return true

func _process(delta: float) -> void:
	super._process(delta)
	if _dead:
		return
	_tick_t += delta
	if _tick_t >= CAPTURE_TICK:
		_tick_capture(_tick_t)
		_tick_t = 0.0
	if faction == Constants.FACTION_PLAYER or faction == Constants.FACTION_ENEMY:
		_income_acc += delta * income_per_sec()
		if _income_acc >= 1.0:
			var whole: float = floor(_income_acc)
			_income_acc -= whole
			income_total += whole
			ResourceManager.gather_resource(faction, Constants.RESOURCE_GOLD, whole)

## ── ЗАХВАТ ─────────────────────────────────────────────────────────────────
## Кто стоит рядом: пехота сторон-претендентов (игрок, ИИ) считается, рабочие
## и гарнизон — нет; гоблины и тролли захватывать не умеют, но ЗАЩИЩАЮТ —
## при них захват невозможен
func _tick_capture(dt: float) -> void:
	var present: Dictionary = {}
	var contested := false
	for n in GameManager.unit_grid.query_radius(global_position, CAPTURE_RADIUS):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.garrisoned:
			continue
		if u is Worker:
			continue
		var f: int = int(u.faction)
		if f == Constants.FACTION_PLAYER or f == Constants.FACTION_ENEMY:
			present[f] = int(present.get(f, 0)) + 1
		else:
			contested = true
	if contested or present.size() != 1:
		_capture_by = -1
		_capture_t = 0.0
		return
	var f2: int = int(present.keys()[0])
	if f2 == faction:
		_capture_by = -1
		_capture_t = 0.0
		return
	if _capture_by != f2:
		_capture_by = f2
		_capture_t = 0.0
	_capture_t += dt
	if _capture_t >= CAPTURE_SEC:
		_capture(f2)

## Доля захвата (стенды и интерфейс): 0 — никто не захватывает
func capture_progress() -> float:
	if _capture_by < 0:
		return 0.0
	return clampf(_capture_t / CAPTURE_SEC, 0.0, 1.0)

func capturing_faction() -> int:
	return _capture_by

func _capture(f: int) -> void:
	var old: int = faction
	remove_from_group(Constants.building_group(old))
	faction = f
	add_to_group(Constants.building_group(f))
	_capture_by = -1
	_capture_t = 0.0
	captures += 1
	for w in workers:
		if w != null and is_instance_valid(w):
			_recolor_worker(w as Unit, f)
	_refresh_flag()
	_refresh_sprite()
	_refresh_name()
	if f != Constants.FACTION_PLAYER and _rally_visible:
		set_selected(false)
	captured.emit(f)

## ── ФЛАЖОК ВЛАДЕЛЬЦА ───────────────────────────────────────────────────────
## Тот же узел, что у знамени отряда (ветровой материал, картинка BannerArt),
## только полотнище — цвет стороны, без лычек. Ставится ЛОКАЛЬНО: рудник
## получает свою точку уже после add_child, и глобальная установка отстала бы
func _refresh_flag() -> void:
	if is_neutral():
		if _flag != null and is_instance_valid(_flag):
			_flag.visible = false
		return
	var cloth: Color = _GSM.color_tint(GameManager.color_of(faction))
	var tex: Texture2D = _BannerArtM.faction_flag_texture(cloth)
	if _flag == null or not is_instance_valid(_flag):
		_flag = _SquadBannerM.create(1)
		_flag.name = "MineFlag"
		add_child(_flag)
	_flag.call("build_texture", tex)
	_flag.position = Vector3(FLAG_OFFSET.x + float(_SquadBannerM.POLE_OFFSET_X), FLAG_Y, FLAG_OFFSET.z)
	_flag.visible = true

func flag_visible() -> bool:
	return _flag != null and is_instance_valid(_flag) and _flag.visible

## ── КАРТИНКА ПО СОСТОЯНИЮ ──────────────────────────────────────────────────
func _refresh_sprite() -> void:
	var want: String = SPRITE_ACTIVE if is_active() else SPRITE_INACTIVE
	if want == _state_sprite:
		return
	var spr := get_node_or_null("BuildingSprite") as MeshInstance3D
	if spr == null:
		return
	var q := spr.mesh as QuadMesh
	if q == null:
		return
	var mat := q.material as ShaderMaterial
	if mat == null or not ResourceLoader.exists(want):
		return
	mat.set_shader_parameter("albedo_tex", load(want))
	_state_sprite = want

func state_sprite() -> String:
	return _state_sprite

func _refresh_name() -> void:
	if is_neutral():
		display_name = "%s (ничей)" % _base_name
	else:
		display_name = "%s — рабочих %d/%d" % [_base_name, workers.size(), WORKER_CAP]

## ── РАБОЧИЕ ВНУТРИ: УТИНЫЙ КОНТРАКТ СТРОЙКИ ────────────────────────────────
## Worker.command_build(рудник) ведёт рабочего к work_position и у стены зовёт
## add_builder — здесь это и есть вход внутрь
func work_position(from: Vector3) -> Vector3:
	var d: Vector3 = from - global_position
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3.BACK
	d = d.normalized()
	return global_position + d * (edge_distance(d) + 0.6)

func edge_distance(_dir: Vector3) -> float:
	return maxf(build_size.x, build_size.z) * 0.5

func add_builder(w: Node) -> void:
	var u := w as Worker
	if u == null or not is_instance_valid(u) or u.garrisoned or _dead:
		return
	if int(u.faction) != faction or not has_room():
		return
	_absorb(u)

func remove_builder(_w: Node) -> void:
	pass

func builder_count() -> int:
	return workers.size()

## Вход: тот же приём, что Castle.absorb_unit — боец снят с карты целиком
## (слот отрисовки, кольцо, сетка, группы, строка ядра — off-map)
func _absorb(u: Unit) -> void:
	u.garrisoned = true
	u.end_retreat(true)
	u.visible = false
	u.leave_render()
	u.set_draw(false)
	u.set_tick(false)
	GameManager.forget_on_map(u)
	GameManager.unit_grid.remove(u)
	for g in Constants.UNIT_GROUPS.values():
		u.remove_from_group(String(g))
	u.state = Unit.State.IDLE
	u.global_position = global_position
	u.garrison_host = self
	u.set_off_map(true)
	if u is Worker:
		(u as Worker).build_target = null
	workers.append(u)
	_refresh_sprite()
	_refresh_name()

## Выпустить всех (ПКМ по руднику пустым выделением, гибель рудника)
func release_all() -> bool:
	if workers.is_empty():
		return false
	var list: Array = workers.duplicate()
	workers.clear()
	var k := 0
	for w in list:
		if w == null or not is_instance_valid(w):
			continue
		var ang: float = TAU * 0.381966 * float(k) + 0.7
		var r: float = edge_distance(Vector3.BACK) + 1.2 + 0.5 * sqrt(float(k))
		_release(w as Unit, global_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r))
		k += 1
	_refresh_sprite()
	_refresh_name()
	return true

func _release(u: Unit, at: Vector3) -> void:
	if u == null or not is_instance_valid(u) or not u.garrisoned:
		return
	u.garrisoned = false
	u.garrison_host = null
	u.visible = true
	var spot: Vector3 = GameManager.land_target(Vector3(at.x, 0.0, at.z))
	u.global_position = Vector3(spot.x, GameManager.get_terrain_height(spot.x, spot.z), spot.z)
	u.add_to_group(Constants.unit_group(int(u.faction)))
	u.set_draw(true)
	u.set_tick(true)
	u.enter_render()
	u.set_off_map(false)
	if u.has_method("on_construction_finished"):
		u.call("on_construction_finished")

## Урон по укрытому внутри получает рудник (см. Unit.take_damage)
func absorb_damage_for(_u: Unit, amount: float, attacker: Node3D = null) -> void:
	take_damage(amount, attacker)

## Смена хозяина: рабочий переходит новой стороне — сторона, строка ядра,
## отряд-из-одного и ленты ЦВЕТОВОЙ ПАПКИ новой стороны
func _recolor_worker(u: Unit, f: int) -> void:
	u.faction = f
	if u._soa >= 0:
		GameManager.army.set_faction(u._soa, f)
	GameManager.remove_from_squad(u)
	var sid: int = GameManager.new_squad(f, "worker")
	GameManager.add_to_squad(sid, u)
	if u is Worker:
		var w := u as Worker
		if w._pawn_sprite != null and is_instance_valid(w._pawn_sprite):
			w._pawn_sprite.queue_free()
			w._pawn_sprite = null
		w._active_sprite = null
		w._setup_worker_visual()
		w._look_ok = false

## ── ГИБЕЛЬ: РАБОЧИЕ ВЫБЕГАЮТ, ОСТАЁТСЯ ОБЩАЯ РУИНА ─────────────────────────
func _die() -> void:
	if _dead:
		return
	release_all()
	super._die()

func ruin_sprite_override() -> String:
	return SPRITE_DESTROYED

func ruin_any_faction() -> bool:
	return true
