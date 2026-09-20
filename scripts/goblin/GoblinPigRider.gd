extends Unit

## ═══════════════════════════════════════════════════════════════════════════
## ГОБЛИН НА КАБАНЕ
## ═══════════════════════════════════════════════════════════════════════════
## Быстрая ударная конница орды: догоняет, продавливает строй напором кабана
## (push_force вдвое выше рыцарского) и быстро гибнет под копьями. Механики —
## все базовые, как и у пешего гоблина.

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _GobCfgV  := preload("res://scripts/goblin/goblin_config.gd")

const SHEET_DIR := "res://assets/factions/Goblin/"
const SHEETS := {
	"idle":   "Pig Rider_Idle.png",
	"walk":   "Pig Rider_Run.png",
	"attack": "Pig Rider_Attack.png",
}

func _ready() -> void:
	_apply_config_stats("goblin_rider")
	display_name = "Наездник на кабане"
	super._ready()
	_setup_visual()

func _strike_damage() -> float:
	_play_attack_anim("attack", 420)
	return attack_damage

# ─────────────────────────────────────────────────────────────────────────────
# ОХОТА КОННИЦЫ (ТЗ 18.09.2026, п. 4)
# ─────────────────────────────────────────────────────────────────────────────
## Жалоба: всадники сбрасывают агро перед врагом и спрессовываются в кучу.
## Прежде цель давало только общее авто-агро в покое (радиус обзора, ближайший
## кем бы он ни был) и поводок погони 7 м, как у пехоты: кайтящий лучник
## уходил за поводок, всадник бросал цель и вставал. Теперь:
##   • раз в RIDER_HUNT_TICK — скан в RIDER_HUNT_RADIUS (30 м) с ВЕСОМ ЦЕЛИ
##     ДЛЯ КОННИЦЫ (BestEnemyPrio, колонка _tgtWc): лучник, мечник, рабочий
##     тянут к себе, копейщик в «Защите» отталкивает (×0.4) — в лоб на копья
##     всадник идёт только когда иного рядом нет;
##   • цель ДЕРЖИТСЯ: пока жива и в RIDER_PURSUIT_LIMIT (pursuit_limit), скан
##     её не меняет; сменилась — только по гибели/уходу;
##   • разгон и таран — штатные (charge_range из STATS), новая цель после
##     прежней получает свой заход;
##   • марш орды (command_move) не бросается навсегда: точка запоминается и
##     возвращается, когда чужих в радиусе не осталось (как у туши)
var hunting: bool = false
var hunts_started: int = 0
var hunt_swaps: int = 0
var marches_resumed: int = 0
var _hunt_t: float = 0.0
var _resume_to: Vector3 = Vector3.INF

## Тик идёт всегда (часы охоты): по физике конница не спит
func may_sleep_physics() -> bool:
	return false

func target_prio_mode() -> int:
	return 2

func aggro_radius() -> float:
	return _GobCfgV.RIDER_AGGRO_RADIUS

func pursuit_limit() -> float:
	return _GobCfgV.RIDER_PURSUIT_LIMIT if hunting else PURSUIT_LIMIT

func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	_tick_hunt(delta)
	super.tick_physics(delta, prof, bm, bonus_ver)

func _target_alive() -> bool:
	var t := attack_target
	return t != null and is_instance_valid(t) \
		and not (t is Unit and ((t as Unit).is_dead() or (t as Unit).garrisoned))

## Лучшая цель по весу конницы в радиусе (тот же скан, что у авто-агро, с
## prio 2: см. SpatialGrid.best_enemy → target_prio_mode)
func _hunt_scan(r: float) -> Node3D:
	return _find_nearest_enemy_in_range(r, "rider_hunt")

func _engage(foe: Node3D) -> void:
	if foe == null or not is_instance_valid(foe) or _panicked or retreating:
		return
	var fu := foe as Unit
	if fu != null and (fu.is_dead() or int(fu.faction) == int(faction)):
		return
	if not hunting:
		hunting = true
		hunts_started += 1
		_resume_to = move_target if state == State.MOVING else Vector3.INF
	# Разгон взводится сам (charge_range > 0): «удар с разгона» — штатный путь
	command_attack(foe, true)

func _tick_hunt(delta: float) -> void:
	_hunt_t -= delta
	if _hunt_t > 0.0:
		return
	_hunt_t = _GobCfgV.RIDER_HUNT_TICK
	if _panicked or retreating or garrisoned or player_order_active() or target_lock:
		return
	var alive: bool = _target_alive()
	if alive:
		# УДЕРЖАНИЕ: цель не меняется, пока жива и в поводке. Одно исключение —
		# всадник упёрся в копья строя (цель — копейщик в «Защите»), а рядом
		# есть слабая цель: сменить, не гася заход
		if not hunting:
			return
		var tu := attack_target as Unit
		if tu == null or tu.cav_target_weight() >= 1.0:
			return
		var better: Node3D = _hunt_scan(_GobCfgV.RIDER_HUNT_RADIUS)
		if better != null and better != attack_target and better is Unit \
				and (better as Unit).cav_target_weight() > tu.cav_target_weight():
			hunt_swaps += 1
			command_attack(better, true)
		return
	# Цели нет: на марше, в покое или после гибели прежней — скан
	var foe: Node3D = _hunt_scan(_GobCfgV.RIDER_HUNT_RADIUS)
	if foe != null:
		_engage(foe)
		return
	if hunting:
		hunting = false
		if _resume_to.x != INF:
			marches_resumed += 1
			var to: Vector3 = _resume_to
			_resume_to = Vector3.INF
			command_move(to)

## Удар — повод взять обидчика (стрела, кость), если своей цели нет
func take_damage(amount: float, attacker: Node3D = null) -> void:
	super.take_damage(amount, attacker)
	if state == State.DEAD or attacker == null or not is_instance_valid(attacker):
		return
	if not (attacker is Unit) or _target_alive():
		return
	_engage(attacker)

## Личный габарит: кабан с седоком шире пешего гоблина, но радиус берётся тот
## же — общий множитель размера орды (см. Unit.sep_radius и goblin_config)
func sep_radius() -> float:
	return SEP_MIN_DIST * _GobCfgV.SIZE_SCALE

func _sfx_swing() -> String:
	return "sword_attack"

## Грюнты пака (ТЗ 19.09.2026): визги и хрюканье — на удар, урон и марш
func _sfx_grunt() -> String:
	return "goblin_grunt"

func _sfx_hurt() -> String:
	return "goblin_grunt"

func _sfx_move_grunt() -> String:
	return "goblin_grunt"


## ГОЛОСА ОРДЫ (спринт 18): крики атаки вперемешку с расстройкой высоты и
## громкости (см. AudioManager.SFX_LIMITS goblin_attack), смерть — свой сэмпл
## с ±0.08 к высоте. Шанс на удар — общий (Unit.SHOUT_CHANCE): жребий идёт из
## того же потока, что и у людей, и число вызовов не меняется — иначе
## сеяные стенды орды (qa_gnoll_fix) поехали бы от одной смены порога
const GOBLIN_SHOUT_CHANCE := SHOUT_CHANCE

func _sfx_shout() -> String:
	return "goblin_attack"

func _shout_chance() -> float:
	return GOBLIN_SHOUT_CHANCE

func _sfx_death() -> String:
	return "goblin_death"

func _sfx_hit() -> String:
	return "sword_hit"

func _setup_visual() -> void:
	var asp: AnimatedSprite3D = _SSParser.build_sprite_from_map(
		SHEET_DIR, SHEETS, ["attack"])
	if asp == null:
		push_warning("GoblinPigRider: ленты не найдены в %s" % SHEET_DIR)
		return
	for child in get_children():
		if child is MeshInstance3D and child != selection_ring:
			child.visible = false
	_apply_goblin_scale(asp)
	add_child(asp)
	_active_sprite = asp

## ── СВОЙ МАСШТАБ И ЧЕСТНАЯ ПРИВЯЗКА К ЗЕМЛЕ ────────────────────────────────
## Общий размер пикселя (0.0108) подобран под кадры людей; у гоблина кадр
## крупнее (256 против 192-320), а рисунок в нём другой пропорции — при общем
## числе гоблин выходил ШИРЕ человека, будучи ниже его. Разбор и вывод числа —
## в goblin_config.PIXEL_SIZE.
##
## Высота центра спрайта пересчитывается ПО САМОЙ ЛЕНТЕ, а не берётся
## константой: константа 0.42 подобрана под старый размер пикселя, и с новым
## гоблин ушёл бы ногами под землю. Формула та же, по которой стенд qa_ring
## проверяет привязку: центр = (полкадра - прозрачный низ) x размер пикселя
func _apply_goblin_scale(asp: AnimatedSprite3D) -> void:
	asp.pixel_size = _GobCfgV.PIXEL_SIZE
	var frames: SpriteFrames = asp.sprite_frames
	if frames == null or not frames.has_animation("idle"):
		return
	var first: Texture2D = frames.get_frame_texture("idle", 0)
	if first == null:
		return
	var at := first as AtlasTexture
	var fh: float = at.region.size.y if at != null else first.get_size().y
	if fh <= 0.0:
		return
	var pad: int = _anim_bottom_px(first)
	asp.position.y = (fh * 0.5 - float(pad)) * asp.pixel_size
