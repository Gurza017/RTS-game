extends Unit

## ═══════════════════════════════════════════════════════════════════════════
## ГНОЛЛ — БЫСТРЫЙ СЛАБЫЙ МЕТАТЕЛЬ У ПНЯ (заказ владельца, спринт 13)
## ═══════════════════════════════════════════════════════════════════════════
## Обычный `Unit` третьей стороны. Как и у гоблинов, почти всё достаётся от
## базы: бой, движение, туман, ветеранство, общая отрисовка, тело на поле.
## Своего здесь четыре вещи, и каждая — переопределение, а не развилка в Unit:
##
##   • КОСТЬ ВМЕСТО СТРЕЛЫ (`_on_attack_fired`). Тот же снаряд по всей логике
##     полёта и попадания, но со своим слоем отрисовки и своей картинкой —
##     см. `Arrow.bone` и `GameManager.bones_mm`. Дуга КРУТАЯ и дальность
##     КОРОТКАЯ (GNOLL_BONE_ARC, attack_range в конфиге): гнолл не стрелок, он
##     метатель. Разброс большой и с ПРОМАХАМИ — доля `GNOLL_MISS_CHANCE`
##     выстрелов уходит в землю рядом с целью намеренно.
##
##   • КАЙТ (`_tick_kite`). Подошла пехота ближе `GNOLL_KITE_IN` — гнолл
##     отбегает на `GNOLL_KITE_OUT`, продолжая метать. Это ПРИКАЗ на шаг, а не
##     сила и не своя ветка движения: тем же `command_move`, каким ходят все.
##     В рукопашную он не идёт вовсе (`pursues_target` = false), и потому его
##     единственная защита — расстояние.
##
##   • ПАТРУЛЬ И АГРО ПО РАССТОЯНИЮ (`_tick_patrol`). У пня он не толпится:
##     ходит по кольцу вокруг него. И на далёкий бой НЕ СБЕГАЕТСЯ ВЕСЬ —
##     инициативу берёт только тот, у кого враг ближе `GNOLL_AGGRO_LEASH` от
##     ЕГО СОБСТВЕННОГО поста. Это не новое правило, а личный поводок из базы
##     (`AGGRO_LEASH`), суженный конфигом: «не все агрятся, когда бой далеко».
##
##   • ФЛАНГ ПРИ ОБОРОНЕ ПНЯ (`_tick_flank`). Пока логово живо и по нему бьют,
##     гнолл встаёт не перед атакующими, а СБОКУ от линии «пень → враг»: он
##     отвлекает и щиплет с крыла, а держат удар тролли. Точка считается один
##     раз на подход и обновляется не чаще `GNOLL_FLANK_SEC`.
##
## Файл без class_name: подключается через preload/load (как Troll и Sheep).

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _GobCfgG  := preload("res://scripts/goblin/goblin_config.gd")

const SHEET_DIR := "res://assets/factions/orc/Troll/Gnoll/"
## Ключи те же, что знает базовый автомат внешности; hit — лента получения
## урона, она короткая (2 кадра) и в автомате не участвует
const SHEETS := {
	"idle":   "Gnoll_Idle.png",
	"walk":   "Gnoll_Walk.png",
	"attack": "Gnoll_Throw.png",
	"hit":    "Gnoll_Hit.png",
}

## Логово (пень), которое гнолл охраняет. Null — вольный гнолл
var lair: Node3D = null

var _patrol_t: float = 0.0
var _kite_t: float = 0.0
var _flank_t: float = 0.0
## ── КАЙТ ПО ФАКТУ, А НЕ ПО ТАЙМЕРУ ────────────────────────────────────────
## Точка, из которой начат последний отход, и срок, к которому он обязан дать
## заметное смещение. Не дал — отбегать некуда (свои тела), кайт глушится и
## гнолл стоит и метает. Без этого он вечно оставался в MOVING и «бежал на
## месте» с непрерывным лупом шагов (жалоба спринта 14)
var _kite_from: Vector3 = Vector3.INF
var _kite_check_t: float = 0.0
var _kite_block_t: float = 0.0
## Стенды: сколько раз кайт признан невозможным
var kite_blocked: int = 0
## Стенды: сколько раз отбегал от подошедшей пехоты и сколько костей метнул
var kites: int = 0
var bones_thrown: int = 0
var bones_missed: int = 0

func _ready() -> void:
	_apply_config_stats("gnoll")
	display_name = "Гнолл"
	super._ready()
	_setup_visual()

func _setup_visual() -> void:
	# Лента броска НЕ зациклена: бросок проигрывается один раз и возвращает
	# бойца в idle/walk (третий аргумент build_sprite_from_map)
	var asp: AnimatedSprite3D = _SSParser.build_sprite_from_map(
		SHEET_DIR, SHEETS, ["attack", "hit"])
	if asp == null:
		# Правило проекта: отсутствующий ассет не роняет игру — остаётся
		# процедурный примитив базы
		push_warning("Gnoll: ленты не найдены в %s" % SHEET_DIR)
		return
	for child in get_children():
		if child is MeshInstance3D and child != selection_ring:
			child.visible = false
	_apply_gnoll_scale(asp)
	add_child(asp)
	_active_sprite = asp

## Габарит и привязка к земле — по САМОЙ ЛЕНТЕ, тем же способом, что у
## гоблина-копейщика: центр = (полкадра − прозрачный низ) × размер пикселя
func _apply_gnoll_scale(asp: AnimatedSprite3D) -> void:
	asp.pixel_size = _GobCfgG.GNOLL_PIXEL_SIZE
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

func sep_radius() -> float:
	return SEP_MIN_DIST * _GobCfgG.SIZE_SCALE

## ── В РУКОПАШНУЮ НЕ ИДЁТ ВОВСЕ ─────────────────────────────────────────────
## Тот же ответ, что у лучника: назначенную цель, до которой не дострелить,
## база подменит на достижимую (Unit._prefer_in_range), а сходить с места за
## ней он не станет
func pursues_target() -> bool:
	return false

## Поводок инициативы уже своего рода войск: гнолл не сбегается на далёкий бой
func aggro_leash() -> float:
	return _GobCfgG.GNOLL_AGGRO_LEASH

func _sfx_swing() -> String:
	return ""

func _sfx_hit() -> String:
	return ""

# ─────────────────────────────────────────────────────────────────────────────
# БРОСОК КОСТИ
# ─────────────────────────────────────────────────────────────────────────────
func _on_attack_fired(target: Node3D, damage: float) -> void:
	_play_attack_anim("attack", 520)
	var parent := get_parent()
	if parent == null or target == null or not is_instance_valid(target):
		return
	var from_pos: Vector3 = global_position + Vector3(0.0, _GobCfgG.GNOLL_THROW_Y, 0.0)
	var tw := target as Unit
	if tw != null:
		tw.notify_incoming_fire(global_position)
	var aim_h: float = tw.aim_height() if tw != null else 0.8
	var aim: Vector3 = target.global_position + Vector3(0.0, aim_h, 0.0)
	# ── ПРОМАХ — ЭТО ТОЧКА, А НЕ ВЕРОЯТНОСТЬ УРОНА ────────────────────────
	# Урон гнолла и так мал; «иногда промахивается» сделано ГЕОМЕТРИЕЙ: кость
	# летит в землю рядом с целью и втыкается там. Так это видно на экране, а
	# заодно не требует ни одной новой ветки в расчёте урона
	var miss: bool = randf() < _GobCfgG.GNOLL_MISS_CHANCE
	var spread: float = _GobCfgG.GNOLL_MISS_SPREAD if miss else _GobCfgG.GNOLL_SCATTER
	var ang: float = randf() * TAU
	var off: float = sqrt(randf()) * spread
	aim += Vector3(cos(ang) * off, 0.0, sin(ang) * off)
	if miss:
		aim.y = 0.0
		bones_missed += 1
	bones_thrown += 1
	var dist: float = from_pos.distance_to(aim)
	GameManager.spawn_arrow(parent, from_pos, aim, dist,
		_GobCfgG.GNOLL_BONE_SPEED, _GobCfgG.GNOLL_BONE_ARC, damage, self,
		faction, true)

# ─────────────────────────────────────────────────────────────────────────────
# ХОД: КАЙТ, ФЛАНГ, ПАТРУЛЬ
# ─────────────────────────────────────────────────────────────────────────────
func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	super.tick_physics(delta, prof, bm, bonus_ver)
	if state == State.DEAD:
		return
	# Гнолл из сохранённой партии рождается без логова — подхватываем логово
	# партии, чтобы патруль и оборона пня работали и после загрузки
	if lair == null and GameManager.troll_lair != null \
			and is_instance_valid(GameManager.troll_lair):
		lair = GameManager.troll_lair as Node3D
	# ПОРЯДОК ВОРОТ ЗНАЧИМ: кайт важнее и фланга, и патруля. Подошедшая пехота
	# убивает гнолла за пару ударов, а «отойти» — единственная его защита
	if _tick_kite(delta):
		return
	if _tick_flank(delta):
		return
	_tick_patrol(delta)

## Отбежать от подошедшей вплотную пехоты. true — шаг выдан, дальше не идём
func _tick_kite(delta: float) -> bool:
	# ── ПРОВЕРКА ПРЕДЫДУЩЕГО ОТХОДА ────────────────────────────────────────
	# Отход выдан — смотрим, дал ли он смещение. Не дал — бежать некуда
	if _kite_check_t > 0.0:
		_kite_check_t -= delta
		if _kite_check_t <= 0.0 and _kite_from.x != INF:
			var gain: float = Vector2(global_position.x - _kite_from.x,
				global_position.z - _kite_from.z).length()
			if gain < _GobCfgG.GNOLL_KITE_MIN_GAIN:
				# Отбегать некуда: глушим кайт и ВСТАЁМ — стоящий метатель
				# полезнее бегущего на месте, и лупа шагов он не держит
				_kite_block_t = _GobCfgG.GNOLL_KITE_BLOCK_SEC
				kite_blocked += 1
				velocity = Vector3.ZERO
				if state == State.MOVING:
					state = State.IDLE
			_kite_from = Vector3.INF
	if _kite_block_t > 0.0:
		_kite_block_t -= delta
		return false
	_kite_t -= delta
	if _kite_t > 0.0:
		return false
	var foe: Node3D = _nearest_melee_foe(_GobCfgG.GNOLL_KITE_IN)
	if foe == null:
		return false
	_kite_t = _GobCfgG.GNOLL_KITE_SEC
	var away: Vector3 = global_position - foe.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(1.0, 0.0, 0.0)
	away = away.normalized()
	var p: Vector3 = global_position + away * _GobCfgG.GNOLL_KITE_OUT
	# ОТБЕГАЕМ, НО НЕ УБЕГАЕМ С КАРТЫ: точка зажимается кольцом вокруг пня,
	# иначе стая по одному разошлась бы по всей карте от первой же стычки
	if lair != null and is_instance_valid(lair):
		var from_lair: Vector3 = p - lair.global_position
		from_lair.y = 0.0
		var lim: float = _GobCfgG.GNOLL_PATROL_RADIUS * 1.6
		if from_lair.length() > lim:
			p = lair.global_position + from_lair.normalized() * lim
	command_move(GameManager.land_target(p))
	# Точка отсчёта смещения: по ней и решается, удался ли отход
	_kite_from = global_position
	_kite_check_t = _GobCfgG.GNOLL_KITE_GIVEUP
	kites += 1
	return true

## Ближайший чужой в радиусе r ОТ ТОЧКИ — по сетке ядра, по всем чужим
## сторонам. Тот же приём и тот же вызов, что у гарнизона башни
## (Tower._pick_target): своего «найди врага рядом» в GameManager нет, и
## заводить второе такое место незачем
func _nearest_foe_at(p: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var best_d2: float = INF
	for f in Constants.other_factions(faction):
		var cand = GameManager.army.nearest_of_side(p.x, p.z, int(f), r)
		if cand == null or not is_instance_valid(cand):
			continue
		var u := cand as Unit
		if u == null or u.is_dead():
			continue
		var q: Vector3 = u.global_position
		var d2: float = Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = u
	return best

## Ближайший чужой БЛИЖНЕГО БОЯ рядом со мной. Стрелок кайтом не пугает: от
## него отбегать бессмысленно, он достанет и так
func _nearest_melee_foe(r: float) -> Node3D:
	var u: Node3D = _nearest_foe_at(global_position, r)
	if u == null:
		return null
	if (u as Unit).attack_range > _GobCfgG.GNOLL_MELEE_RANGE_MAX:
		return null
	return u

## Оборона пня: встать СБОКУ от линии «пень → враг». true — шаг выдан
func _tick_flank(delta: float) -> bool:
	_flank_t -= delta
	if _flank_t > 0.0:
		return false
	if lair == null or not is_instance_valid(lair):
		return false
	if lair.has_method("is_dead") and bool(lair.call("is_dead")):
		return false
	# Оборона нужна, только когда враг УЖЕ У ПНЯ
	var foe: Node3D = _nearest_foe_at((lair as Node3D).global_position,
		_GobCfgG.GNOLL_DEFEND_RANGE)
	if foe == null:
		return false
	_flank_t = _GobCfgG.GNOLL_FLANK_SEC
	var line: Vector3 = foe.global_position - lair.global_position
	line.y = 0.0
	if line.length() < 0.5:
		return false
	line = line.normalized()
	var side: Vector3 = Vector3(-line.z, 0.0, line.x)
	# Сторона крыла — от номера узла, а не случайно: стая обязана делиться на
	# два крыла, а не метаться туда-сюда каждым тактом
	if (get_instance_id() % 2) == 1:
		side = -side
	var p: Vector3 = foe.global_position + side * _GobCfgG.GNOLL_FLANK_SIDE \
		- line * _GobCfgG.GNOLL_FLANK_BACK
	command_move(GameManager.land_target(p))
	return true

## Патруль кольца пня: только в покое и без цели
func _tick_patrol(delta: float) -> void:
	if state != State.IDLE or attack_target != null:
		return
	if lair == null or not is_instance_valid(lair):
		return
	_patrol_t -= delta
	if _patrol_t > 0.0:
		return
	_patrol_t = _GobCfgG.GNOLL_PATROL_SEC * randf_range(0.7, 1.3)
	var a: float = randf() * TAU
	var r: float = _GobCfgG.GNOLL_PATROL_RADIUS * randf_range(0.35, 1.0)
	var p: Vector3 = lair.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	command_move(GameManager.land_target(p))

## Удар по гноллу поднимает волну у пня — тем же путём, что у тролля
func take_damage(amount: float, attacker: Node3D = null) -> void:
	if state == State.DEAD:
		return
	super.take_damage(amount, attacker)
	if state == State.DEAD:
		return
	if lair != null and is_instance_valid(lair) and lair.has_method("on_gnoll_hit"):
		lair.call("on_gnoll_hit", self, attacker)
