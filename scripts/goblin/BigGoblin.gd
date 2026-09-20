extends Unit

## ═══════════════════════════════════════════════════════════════════════════
## БОЛЬШОЙ ГОБЛИН — ТУША-МЯСО С ШИРОКИМ СВИПОМ (заказ владельца, 13.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Обычный `Unit` третьей стороны на ЛЕНТАХ ГОБЛИНА-КОПЕЙЩИКА, увеличенных
## втрое. Не свинокабан и не тролль: и бой, и строй, и туман, и общая
## отрисовка достаются от базы. Своего здесь ровно четыре вещи:
##
##   • ГАБАРИТ. Свой `pixel_size` (BIG_PIXEL_SIZE), свой радиус расталкивания,
##     свой кликбокс и своё кольцо. Кликбокс — НЕ Area2D: физтел у бойцов в
##     этом проекте нет вовсе (`collision_mask` = 0), и попадание мыши считает
##     `SelectionManager._pick_at` по `pick_body_h` / `pick_radius` — тем же
##     способом, каким кликается тролль. Лучник целится в `aim_height`.
##
##   • СВИП. Удар накрывает не одну цель, а СЕКТОР перед взглядом: ±60° и вся
##     дальность оружия, до BIG_SWEEP_MAX ближайших. Каждый накрытый получает
##     урон и отброс на BIG_KNOCKBACK (тот же канал скорости, что у конницы и
##     дубины тролля, — своей механики отбрасывания не заводится).
##
##   • РИТМ. Перезарядка четыре секунды — это очень долго, и между ударами
##     туша выглядела бы замершей. Поэтому каждый BIG_COMBO_EVERY-й взмах
##     ДВОЙНОЙ: второй удар вылетает через BIG_COMBO_GAP секунд.
##
##   • УЯЗВИМОСТЬ К СТРЕЛАМ. `ranged_damage_mult` = 2.0 — множитель живёт на
##     ЦЕЛИ и применяется в `Arrow._strike`, то есть в пути СТРЕЛЫ, а не в
##     горячем пути рукопашной: пехота за него не платит ничего.
##
## СКАН ЦЕЛЕЙ ЗАМОРОЖЕН НА ВРЕМЯ ПЕРЕЗАРЯДКИ (заказ, часть 2). Пока идёт КД,
## туша не ищет никого: она проверяет ПРЕЖНЮЮ цель (жива, в дальности) и на
## этом успокаивается. Скан округи запускается один раз, за BIG_SCAN_LEAD до
## готовности удара. Разбор и замер — в docs/ENGINEERING_LOG.md.
##
## Файл без class_name: подключается через preload (как Troll, Gnoll и Sheep).

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _GobCfgB  := preload("res://scripts/goblin/goblin_config.gd")

## Ленты — ГОБЛИНСКИЕ, просто крупнее. Отдельного арта у туши нет и не нужно
const SHEET_DIR := "res://assets/factions/Goblin/"
const SHEETS := {
	"idle":    "Spear Goblin_Idle.png",
	"walk":    "Spear Goblin_Run.png",
	"attack1": "Spear Goblin_Attack Strong.png",
	"attack2": "Spear Goblin_Attack Fast.png",
}

## Счётчик взмахов для комбо и отложенный второй удар двойного взмаха
var _swings: int = 0
var _combo_left: float = 0.0
## Скан заморожен до этого момента (мс по часам армии). Пока now_ms < него,
## округу не щупаем вовсе — см. `_may_scan_now`
var _scan_frozen_until: int = 0
## Стенды: сколько раз свип накрыл кого-то и сколько сканов пропущено
var sweeps: int = 0
var swept_total: int = 0
var scans_skipped: int = 0
var scans_done: int = 0
## Тяжёлый шаг
var _step_t: float = 0.0
## ── ОХОТА ВМЕСТО МАРША (ТЗ 14.09.2026, п. 6) ──────────────────────────────
## Куда шла туша до перехвата (INF — не шла); пока hunting, поводок погони
## BIG_PURSUIT_LIMIT, а поле чисто — возврат на _resume_to
var _resume_to: Vector3 = Vector3.INF
var hunting: bool = false
var _hunt_t: float = 0.0
## Стенды: сколько раз марш прерван боем и сколько раз возобновлён
var hunts_started: int = 0
var marches_resumed: int = 0

func _ready() -> void:
	_apply_config_stats("big_goblin")
	display_name = "Большой гоблин"
	super._ready()
	_setup_visual()
	# Лента ходьбы — по доле СВОЕГО шага (ТЗ 19.09.2026, блок 4)
	var wmin: float = move_speed * _GobCfgB.BIG_WALK_ANIM_FRAC
	_walk_min2 = wmin * wmin

## Стендам: подхваты чужой цели у пехоты орды и подходы к своей пехоте
var escorts_taken: int = 0
var follows_issued: int = 0

func _setup_visual() -> void:
	var asp: AnimatedSprite3D = _SSParser.build_sprite_from_map(
		SHEET_DIR, SHEETS, ["attack1", "attack2"])
	if asp == null:
		push_warning("BigGoblin: ленты не найдены в %s" % SHEET_DIR)
		return
	for child in get_children():
		if child is MeshInstance3D and child != selection_ring:
			child.visible = false
	_apply_big_scale(asp)
	add_child(asp)
	_active_sprite = asp

## Габарит и привязка к земле — ПО САМОЙ ЛЕНТЕ, тем же способом, что у гоблина
## и гнолла: центр = (полкадра − прозрачный низ) × размер пикселя. Константой
## это задавать нельзя — ноги уедут от земли при первой же смене листа
func _apply_big_scale(asp: AnimatedSprite3D) -> void:
	asp.pixel_size = _GobCfgB.BIG_PIXEL_SIZE
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

# ─────────────────────────────────────────────────────────────────────────────
# ГАБАРИТ: РАСТАЛКИВАНИЕ, КЛИК, ПРИЦЕЛ, КОЛЬЦО
# ─────────────────────────────────────────────────────────────────────────────
func sep_radius() -> float:
	return SEP_MIN_DIST * _GobCfgB.BIG_SIZE_SCALE * _GobCfgB.BIG_SEP_MULT / 3.0

## Радар охоты — часы в тике: туша по физике не спит (BigStand, этап 3)
func may_sleep_physics() -> bool:
	return false

## Кликбокс: высота тела и радиус круга у ног. По ним `_pick_at` сдвигает
## якорь под середину рисунка и расширяет круг — иначе клик по груди туши
## пролетает над её точкой на земле (та же правка, что делалась троллю)
func pick_body_h() -> float:
	return 1.6

func pick_radius() -> float:
	return 1.0

func ring_scale() -> float:
	return _GobCfgB.BIG_SIZE_SCALE

## Тонкий обвод вместо растянутого кольца бойца (13.09.2026, как у тролля)
func fine_ring_radius() -> float:
	return _GobCfgB.BIG_FINE_RING_R

func ring_oval() -> Vector2:
	return _GobCfgB.BIG_RING_OVAL

## Лёгкое красное мигание при уроне вместо белого
func hit_flash_peak() -> float:
	return _GobCfgB.BIG_FLASH_PEAK

func hit_flash_color() -> Color:
	return _GobCfgB.BIG_FLASH_COLOR

## Стрелок целится в корпус, а не в ступни
func aim_height() -> float:
	return 1.4

## ── ×2 УРОНА ОТ СТРЕЛ (заказ) ──────────────────────────────────────────────
## Множитель живёт на ЦЕЛИ и применяется в пути стрелы (`Arrow._strike`):
## рукопашная за него не платит ни одного сравнения
## Приоритетная цель стрелков: множитель ×2 (ТЗ 14.09.2026, п. 10)
func target_weight() -> float:
	return _GobCfgB.BIG_TARGET_PRIO

## Снайпер тушу не убивает с одной стрелы (ТЗ 14.09.2026): обычный урон с
## бронепробитием и «Грозой великанов»; добивающий выстрел — стрела в голове
func snipe_one_shot() -> bool:
	return false

func giant_class() -> bool:
	return true

func ranged_damage_mult() -> float:
	return 2.0

func _sfx_shout() -> String:
	return "big_grunt"

## Грюнты пака (ТЗ 19.09.2026): средние рыки — на свип и на урон
func _sfx_grunt() -> String:
	return "big_grunt"

func _sfx_hurt() -> String:
	return "big_grunt"

func _sfx_death() -> String:
	return "goblin_death"

func _sfx_hit() -> String:
	return "sword_hit"

func _sfx_swing() -> String:
	return "spear_hit"

# ─────────────────────────────────────────────────────────────────────────────
# СКАН ТОЛЬКО ПОД КОНЕЦ ПЕРЕЗАРЯДКИ (часть 2 заказа)
# ─────────────────────────────────────────────────────────────────────────────
## Можно ли СЕЙЧАС щупать округу. Пока идёт КД — нельзя: у туши уже есть
## цель, а если её не стало, новую она возьмёт за BIG_SCAN_LEAD до готовности.
## Счётчики ведутся всегда: по ним стенд и меряет экономию
func _may_scan_now() -> bool:
	if now_ms < _scan_frozen_until:
		scans_skipped += 1
		return false
	scans_done += 1
	return true

## Цель по-прежнему годится? Тогда скан не нужен вовсе — это и есть
## «кэш предыдущей цели» из заказа. Проверка стоит две дистанции и одну
## валидность, скан — обход сетки
func _target_still_good() -> bool:
	var t := attack_target
	if t == null or not is_instance_valid(t):
		return false
	var tu := t as Unit
	if tu != null and tu.is_dead():
		return false
	var mp: Vector3 = position if _local_xform else global_position
	var tp: Vector3 = tu.position if (tu != null and tu._local_xform) \
		else t.global_position
	var d: float = Vector2(tp.x - mp.x, tp.z - mp.z).length()
	return d <= attack_range + _pad_of(t)

# ─────────────────────────────────────────────────────────────────────────────
# ТИК: КОМБО И ТЯЖЁЛЫЙ ШАГ
# ─────────────────────────────────────────────────────────────────────────────
func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	super.tick_physics(delta, prof, bm, bonus_ver)
	if state == State.DEAD:
		_combo_left = 0.0
		return
	# ── ВТОРОЙ УДАР ДВОЙНОГО ВЗМАХА ───────────────────────────────────────
	# Стоит ПЕРВЫМ и до всех ворот: комбо обязано дойти до конца независимо
	# от того, что решил автомат боя в этом кадре
	if _combo_left > 0.0:
		_combo_left -= delta
		if _combo_left <= 0.0:
			_combo_left = 0.0
			_sweep_now(false)
	# ── ТЯЖЁЛЫЙ ШАГ ───────────────────────────────────────────────────────
	# Редкий глухой удар ноги, пока туша ИДЁТ ПО ЛЕНТЕ (и на марше, и на
	# подходе к цели). Своего узла звука не заводим — это обычный 3D-голос
	# в общем пуле, с отсечкой по расстоянию и туману; сэмпл — свой thud
	# (ТЗ 19.09.2026, блок 1: прежний Sword_hit_armor с питчем 0.55 — «ведро»)
	if walk_anim_recently():
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = _GobCfgB.BIG_STEP_SEC
			AudioManager.play_3d("big_step", global_position)
	_tick_hunt(delta)

# ─────────────────────────────────────────────────────────────────────────────
# ПЕРЕХВАТ НА МАРШЕ: ЧУЖОЙ РЯДОМ ИЛИ УДАР — БРОСИТЬ ТОЧКУ, ДОБИТЬ, ВЕРНУТЬСЯ
# ─────────────────────────────────────────────────────────────────────────────
## Жалоба (ТЗ 14.09.2026, п. 6): туши по вейпоинтам орды шли сквозь отряды
## игрока, получая урон, — к точке. Марш орды идёт command_move, а базовый
## ответ на удар у идущего гасится (`_may_answer_blow`: «иду прочь»), и
## контратака отряда (squad_counter_charge) — с откатом и поводком 7 м: за
## кайтящим стрелком туша не шла. Теперь:
##   • удар (take_damage) или чужой в BIG_AGGRO_RADIUS на марше → цель, марш
##     запомнен в _resume_to;
##   • на охоте поводок BIG_PURSUIT_LIMIT (pursuit_limit), кайт не спасает;
##   • цель кончилась — ближайший чужой в BIG_HUNT_RADIUS; никого —
##     возврат на прерванную точку (command_move), охота снята
func _engage(foe: Node3D) -> void:
	if foe == null or not is_instance_valid(foe) or _panicked or retreating:
		return
	var fu := foe as Unit
	if fu == null or fu.is_dead() or int(fu.faction) == int(faction):
		return
	if not hunting:
		hunting = true
		hunts_started += 1
		_resume_to = move_target if state == State.MOVING else Vector3.INF
	command_attack(foe, true)

## Ближайший чужой в r — ПЕХОТА В ПРИОРИТЕТЕ (ТЗ 19.09.2026, блок 2):
## ближайший боевой; нет боевых — ближайший вообще (рабочий, монах). Скан —
## один обход сетки раз в BIG_HUNT_TICK, туш на карте единицы
func _hunt_scan(r: float, combat_only: bool = false) -> Node3D:
	# Это ТОЖЕ скан сетки — считается тем же счётчиком, что и авто-агро
	# (qa_big_goblin D: экономию Scan-on-Cooldown стенд меряет по нему)
	scans_done += 1
	var mp: Vector3 = position if _local_xform else global_position
	var best: Node3D = null
	var bd := INF
	var best_any: Node3D = null
	var bd_any := INF
	for n in GameManager.unit_grid.query_radius(mp, r):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.garrisoned or int(u.faction) == int(faction):
			continue
		var q: Vector3 = u.position if u._local_xform else u.global_position
		var d2: float = Vector2(q.x - mp.x, q.z - mp.z).length_squared()
		if u.is_combatant():
			if d2 < bd:
				bd = d2
				best = u
		elif d2 < bd_any:
			bd_any = d2
			best_any = u
	if combat_only:
		return best
	return best if best != null else best_any

## ── СВЯЗКА С ПЕХОТОЙ ОРДЫ (блок 3) ────────────────────────────────────────
## Цель соседнего отряда обычных гоблинов (живой враг у любого своего
## боевого не-гиганта в BIG_ESCORT_RADIUS) — подхватить. Свой боевой сосед,
## ушедший дальше BIG_ESCORT_FOLLOW, — идти к нему (только в покое, без
## приказа и охоты: марш орды и приказ командира важнее)
func _escort_target() -> Node3D:
	var mp: Vector3 = position if _local_xform else global_position
	var best: Node3D = null
	var bd := INF
	for n in GameManager.unit_grid.query_radius(mp, _GobCfgB.BIG_ESCORT_RADIUS):
		if n == null or not is_instance_valid(n):
			continue
		var a := n as Unit
		if a == null or a == self or a.is_dead() or int(a.faction) != int(faction):
			continue
		if a.giant_class() or not a.is_combatant():
			continue
		var t = a.attack_target
		if t == null or not is_instance_valid(t) or not (t is Unit):
			continue
		var tu := t as Unit
		if tu.is_dead() or tu.garrisoned or int(tu.faction) == int(faction):
			continue
		var q: Vector3 = tu.position if tu._local_xform else tu.global_position
		var d2: float = Vector2(q.x - mp.x, q.z - mp.z).length_squared()
		if d2 < bd:
			bd = d2
			best = tu
	return best

func _escort_follow() -> bool:
	if state != State.IDLE or hunting or _resume_to.x != INF or target_lock or _move_lock > 0.0:
		return false
	var mp: Vector3 = position if _local_xform else global_position
	var best: Unit = null
	var bd := INF
	for n in GameManager.unit_grid.query_radius(mp, _GobCfgB.BIG_ESCORT_RADIUS * 2.0):
		if n == null or not is_instance_valid(n):
			continue
		var a := n as Unit
		if a == null or a == self or a.is_dead() or int(a.faction) != int(faction):
			continue
		if a.giant_class() or not a.is_combatant() or a.squad_id <= 0:
			continue
		if not (a.state == State.MOVING or a.state == State.ATTACKING):
			continue
		var q: Vector3 = a.position if a._local_xform else a.global_position
		var d2: float = Vector2(q.x - mp.x, q.z - mp.z).length_squared()
		if d2 < bd:
			bd = d2
			best = a
	if best == null or bd < _GobCfgB.BIG_ESCORT_FOLLOW * _GobCfgB.BIG_ESCORT_FOLLOW:
		return false
	var c: Vector2 = GameManager.squad_centre_xz(best.squad_id)
	var to: Vector3 = Vector3(c.x, 0.0, c.y) if c.x != INF else best.global_position
	follows_issued += 1
	command_move(GameManager.land_target(to))
	return true

func _tick_hunt(delta: float) -> void:
	_hunt_t -= delta
	if _hunt_t > 0.0:
		return
	_hunt_t = _GobCfgB.BIG_HUNT_TICK
	if _panicked or retreating or garrisoned:
		return
	var t := attack_target
	var alive: bool = t != null and is_instance_valid(t) \
		and not (t is Unit and (t as Unit).is_dead())
	# ПЕХОТА ВАЖНЕЕ РАБОЧЕГО (блок 2): цель без оружия (рабочий, монах) —
	# это авто-агро базы, взявшее ближайшего; боевой чужой в радиусе агро
	# перебивает её тем же тактом. Под замком приказа — нет
	if alive and not target_lock and t is Unit and not (t as Unit).is_combatant():
		var better: Node3D = _hunt_scan(_GobCfgB.BIG_AGGRO_RADIUS, true)
		if better != null:
			_engage(better)
			return
	if not hunting:
		# На марше И В ПОКОЕ (ТЗ 19.09.2026, блок 2): чужой в радиусе агро —
		# перехват тем же тактом, без ожидания такта агро и заморозки скана
		if (state == State.MOVING or state == State.IDLE) and not alive and not target_lock:
			var foe: Node3D = _hunt_scan(_GobCfgB.BIG_AGGRO_RADIUS)
			if foe == null:
				# Своя пехота рядом уже дерётся — подхватить её цель (блок 3)
				foe = _escort_target()
				if foe != null:
					escorts_taken += 1
			if foe != null:
				_engage(foe)
			elif state == State.IDLE:
				_escort_follow()
		return
	if alive:
		return
	# Цель кончилась: следующий чужой рядом, потом цель своей пехоты,
	# иначе — обратно на марш
	var nxt: Node3D = _hunt_scan(_GobCfgB.BIG_HUNT_RADIUS)
	if nxt == null:
		nxt = _escort_target()
		if nxt != null:
			escorts_taken += 1
	if nxt != null:
		command_attack(nxt, true)
		return
	hunting = false
	if _resume_to.x != INF:
		marches_resumed += 1
		var to: Vector3 = _resume_to
		_resume_to = Vector3.INF
		command_move(to)

func pursuit_limit() -> float:
	return _GobCfgB.BIG_PURSUIT_LIMIT if hunting else PURSUIT_LIMIT

## Удар — повод бросить вейпоинт, с любой дистанции (стрела, кость)
func take_damage(amount: float, attacker: Node3D = null) -> void:
	super.take_damage(amount, attacker)
	if state == State.DEAD or attacker == null or not is_instance_valid(attacker):
		return
	if not (attacker is Unit):
		return
	var t := attack_target
	var alive: bool = t != null and is_instance_valid(t) \
		and not (t is Unit and (t as Unit).is_dead())
	if alive and hunting:
		return
	_engage(attacker)

# ─────────────────────────────────────────────────────────────────────────────
# УДАР: СЕКТОР, ОТБРОС, КОМБО
# ─────────────────────────────────────────────────────────────────────────────
## Базовый автомат зовёт `_strike_damage` в момент удара. Урон по одной цели
## мы не наносим вовсе — его несёт свип (`_damage_on_strike` = false), ровно
## как у лучника урон несёт стрела
func _strike_damage() -> float:
	_swings += 1
	# Замок скана: следующий раз щупаем округу за BIG_SCAN_LEAD до готовности
	var cd: float = _effective_cooldown()
	_scan_frozen_until = now_ms + int(
		maxf(cd - _GobCfgB.BIG_SCAN_LEAD, 0.0) * 1000.0)
	var combo: bool = (_swings % _GobCfgB.BIG_COMBO_EVERY) == 0
	_play_attack_anim("attack1" if not combo else "attack2", 520)
	_sweep_now(true)
	if combo:
		# Двойной взмах: второй удар — отложенный, его выпустит тик
		_combo_left = _GobCfgB.BIG_COMBO_GAP
	return attack_damage

func _damage_on_strike() -> bool:
	return false          # урон несёт свип, а не одиночный удар

## Взмах: сектор перед взглядом. `loud` — первый удар пары (со звуком)
func _sweep_now(loud: bool) -> void:
	var dir: Vector3 = _facing
	if dir.length_squared() < 1e-6:
		dir = Vector3(0.0, 0.0, -1.0)
	dir = dir.normalized()
	var mp: Vector3 = position if _local_xform else global_position
	var reach: float = attack_range + _GobCfgB.BIG_SWEEP_HALF_W
	# ── КОГО НАКРЫЛО ──────────────────────────────────────────────────────
	# Один скан сетки на ВЕСЬ взмах (а не по цели на каждого накрытого): тот
	# же приём, что у дуги дубины тролля
	var hits: Array = GameManager.unit_grid.query_radius(mp, reach)
	var picked: Array = []
	for n in hits:
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.faction == faction:
			continue
		var dp: Vector3 = u.position if u._local_xform else u.global_position
		var to := Vector3(dp.x - mp.x, 0.0, dp.z - mp.z)
		var d: float = to.length()
		if d < 0.01:
			picked.append([0.0, u])
			continue
		# СЕКТОР, А НЕ КРУГ: бьём вперёд, а не вокруг себя
		if to.normalized().dot(dir) < _GobCfgB.BIG_SWEEP_ARC_COS:
			continue
		picked.append([d, u])
	if picked.is_empty():
		return
	picked.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var dmg: float = attack_damage + _upgrade_damage_bonus()
	var n_hit := 0
	for row in picked:
		if n_hit >= _GobCfgB.BIG_SWEEP_MAX:
			break
		var u := (row[1]) as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		n_hit += 1
		u.take_damage(dmg, self)
		# ── ОТБРОС: ТОТ ЖЕ КАНАЛ, ЧТО У КОННИЦЫ ───────────────────────────
		# Своей механики отбрасывания не заводится: apply_knockback уже умеет
		# и затухающую скорость, и метку для картинки, и проверку чужих тел
		if is_instance_valid(u) and not u.is_dead():
			var away := Vector3(u.global_position.x - mp.x, 0.0,
				u.global_position.z - mp.z)
			if away.length_squared() < 1e-4:
				away = dir
			u.apply_knockback(away.normalized(), _GobCfgB.BIG_KNOCKBACK, mp)
	if n_hit > 0:
		sweeps += 1
		swept_total += n_hit
		if loud:
			AudioManager.play_3d("big_sweep", mp)
		_grunt_attack()

# ─────────────────────────────────────────────────────────────────────────────
# СКАН-ПО-ПЕРЕЗАРЯДКЕ: ГЕЙТ НАД БАЗОВЫМ АВТО-АГРО
# ─────────────────────────────────────────────────────────────────────────────
## Базовый `_check_auto_aggro` — единственное место, откуда стоящая туша
## щупает округу. Перекрываем его ДВУМЯ воротами, ровно как просит заказ:
##
##   1. цель жива и в дальности — бьём её, скан пропускаем целиком;
##   2. идёт перезарядка — не щупаем вовсе до BIG_SCAN_LEAD перед готовностью.
##
## Ворота стоят ЗДЕСЬ, а не в базе: у пехоты свой ритм (0.5-2.0 с) и свои
## причины смотреть по сторонам, и общий гейт по кулдауну сломал бы им
## подтягивание фланга и ответ на удар
func _check_auto_aggro() -> void:
	# Приказ игрока сильнее любой экономии: замок цели разбирает база
	if target_lock:
		super._check_auto_aggro()
		return
	# 1. КЭШ ПРЕЖНЕЙ ЦЕЛИ
	if _target_still_good():
		scans_skipped += 1
		_aggro_timer = AGGRO_INTERVAL_HOT
		return
	# 2. ЗАМОРОЗКА НА ВРЕМЯ КД
	if not _may_scan_now():
		# Просыпаемся ровно к окну скана, а не через полный интервал агро
		_aggro_timer = maxf(float(_scan_frozen_until - now_ms) * 0.001, 0.05)
		return
	super._check_auto_aggro()
