extends Unit
class_name Warrior

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")

# Ротация атак: 3 обычных удара (attack_1), затем 1 мощный (attack_2)
var _attack_2_damage: float = 24.0
var _combo_step: int = 0

func _ready() -> void:
	_apply_config_stats("warrior")   # характеристики — из unit_stats_config.gd
	_attack_2_damage = _UStats.stat("warrior", "attack_2", attack_damage * 2.4)
	display_name    = "Мечник"
	super._ready()
	_setup_warrior_visual()

# Мечник рубит сталью: замах — свист меча, попадание — лязг по броне
## ── АГРО МЕЧНИКА — 5 м (ТЗ 18.09.2026, п. 4) ─────────────────────────────
const WARRIOR_AGGRO_RADIUS := 5.0

func aggro_radius() -> float:
	return WARRIOR_AGGRO_RADIUS

## Мечник — желанная цель конницы (ТЗ 18.09.2026, п. 4)
func cav_target_weight() -> float:
	return 1.6

func _sfx_swing() -> String:
	return "sword_attack"

# ═════════════════════════════════════════════════════════════════════════════
# ЯРОСТНЫЙ НАБЕГ (способность отряда warrior_1d, двойной ПКМ)
# ═════════════════════════════════════════════════════════════════════════════
# ЧТО ЭТО. Рывок к точке приказа с ЗАФИКСИРОВАННЫМИ ЩИТАМИ и серия из
# RAGE_HITS ударов подряд с ротацией «обычный → мощный → обычный → мощный →
# обычный». Серия ФИКСИРОВАННАЯ, а не «каждый четвёртый»: заказ описывает её
# по шагам, и она обязана быть одинаковой каждый раз.
#
# ПОЧЕМУ ЭТО НЕ НОВОЕ СОСТОЯНИЕ. Ровно та же причина, что у щита абзацем ниже:
# набег не отвечает на вопрос «какой приказ выполняет боец» — приказ у него
# обычный марш, — он меняет скорость, кулдаун, ротацию и щит. Признак поверх
# состояния, а не внутри него.
#
# ПОТОЛОК ПО ВРЕМЕНИ ОБЯЗАТЕЛЕН. Серия тратится только в бою, а до врага можно
# и не добежать (его убили, приказ сменили): без RAGE_SEC мечник ходил бы
# ускоренным под щитом до конца партии.
const RAGE_HITS := 5
const RAGE_SPEED_MULT := 1.45
## ── АГРО ПОСЛЕ РЫВКА (ТЗ-B 19.09.2026) ────────────────────────────────────
## «Сразу по окончании рывка юниты должны автоматически входить в состояние
## агро». Рывок — марш по двойному ПКМ; по прибытии боец вставал в IDLE и
## ждал лотерею такта агро (0.5-2 с) с радиусом мечника 5 м — а точка приказа
## лежит перед строем, и в 5 м никого: мечники «замирали». Теперь конец
## рывка (прибытие, истечение серии или её срока) — СОБЫТИЕ: ближайший чужой
## в RUSH_AGGRO_R берётся целью тем же тиком (command_attack с forced, без
## замка — авто-агро дальше ведёт бой как обычно)
const RUSH_AGGRO_R := 14.0
## ── СТЕНА ЩИТОВ НА ПОСЛЕДНИХ МЕТРАХ РАЗГОНА (заказ владельца, спринт 15) ────
## «Юнит бежит, а за 5-10 метров до цели включает "Стену щитов" (+30 % к
## скорости) и влетает во врага». В набеге щит поднят с первого шага (см.
## _update_guard), а вот РЫВОК — это отдельная фаза: пока до цели дальше
## SHIELD_WALL_RANGE, мечник бежит набегом; ближе — стена щитов, скорость ещё
## на SHIELD_WALL_SPEED_MULT выше, и в строй он входит на ней. Множитель
## ставится ПОВЕРХ набега (после ветки щита — та же причина, что у
## RAGE_SPEED_MULT: штраф щита не должен съесть рывок)
const SHIELD_WALL_RANGE := 8.0
const SHIELD_WALL_SPEED_MULT := 1.3
## Удары в серии БЫСТРЫЕ: доля обычной перезарядки
const RAGE_COOLDOWN_MULT := 0.45
const RAGE_SEC := 9.0
## ── ТОЛЧОК В НАБЕГЕ (заказ спринта 14: «увеличить силу отталкивания») ─────
## Множитель идёт ПОСЛЕ потолка шага, как charge_push_mult у конницы: сам
## `push_force` потолком съедается (разбор — Unit._apply_push), и поднимать
## надо именно множитель. Толчок и так идёт НА КАЖДЫЙ удар (Unit.PUSH_EVERY
## = 1), поэтому пять быстрых ударов серии дают пять толчков подряд — на
## экране это читается одним длинным навалом, ради которого приём и заведён
const RAGE_PUSH_MULT := 2.6
## Шаг ротации: true — мощный удар. Пять шагов, как в заказе
const RAGE_STRONG := [false, true, false, true, false]

var _rage_left: int = 0
var _rage_until_ms: int = 0
var _rage_step: int = 0
## Стенды: сколько ударов серии уже нанесено и сколько из них мощных
var rage_hits_done: int = 0
var rage_strong_done: int = 0
## Рывок начат и его конец ещё не разобран (агро после рывка — один раз)
var _rush_pending: bool = false
## Выкрик «Яростной атаки» (ТЗ 19.09.2026 «Audio System Update»): взводится
## рывком, звучит на ПЕРВОМ состоявшемся ударе мечом, один на отряд в
## AudioManager.KNIGHT_ANGRY_GAP
var _angry_pending: bool = false
var angry_shouts: int = 0
## Стенды: сколько раз агро после рывка выдало цель
var rush_aggro_count: int = 0

## ── БОНУСЫ КУЗНИЦЫ МЕЧНИКА, КЭШ ПО ВЕРСИИ ТАБЛИЦЫ ─────────────────────────
## Читаются на удар и на рывок; словарный поиск на каждый удар в свалке —
## лишнее, версия таблицы меняется считанные разы за партию
var _forge_ver: int = -1
var _rage_bonus_hits: int = 0
var _cleave_n: int = 0
var _cleave_frac: float = 0.0
var _berserk: float = 0.0

func _refresh_forge() -> void:
	if _forge_ver == GameManager.bonus_version:
		return
	_forge_ver = GameManager.bonus_version
	_rage_bonus_hits = int(round(GameManager.unit_bonus(faction, "warrior", "bonus_rage_hits")))
	_cleave_n = int(round(GameManager.unit_bonus(faction, "warrior", "bonus_cleave")))
	_cleave_frac = clampf(GameManager.unit_bonus(faction, "warrior", "bonus_cleave_dmg"), 0.0, 1.0)
	_berserk = GameManager.unit_bonus(faction, "warrior", "bonus_berserk")

## Сколько ударов в серии «Яростной Атаки» с учётом кузницы (5 → 7 с
## «Неистовством»)
func rage_hits_total() -> int:
	_refresh_forge()
	return RAGE_HITS + _rage_bonus_hits

## Сколько соседей задевает удар («Рассечение» 2, «Стальной вихрь» +1)
func cleave_targets() -> int:
	_refresh_forge()
	return _cleave_n

func cleave_frac() -> float:
	_refresh_forge()
	return _cleave_frac

## Включить набег. Зовёт SelectionManager по двойному ПКМ, один раз на бойца
func start_rage_dash() -> void:
	GameManager.tm_ability("rage_dash", faction)
	if state == State.DEAD:
		return
	_rage_left = rage_hits_total()
	_rage_step = 0
	_rage_until_ms = Time.get_ticks_msec() + int(RAGE_SEC * 1000.0)
	_rush_pending = true
	_angry_pending = true
	# Щит фиксируется НЕ флагом _guard_active напрямую: его каждый кадр
	# переписывает _update_guard, и прямая запись погасла бы в тот же тик
	mark_pose_dirty()

func rage_active() -> bool:
	return _rage_left > 0 and Time.get_ticks_msec() < _rage_until_ms

## ── КОНЕЦ РЫВКА — В БОЙ С БЛИЖАЙШИМ ───────────────────────────────────────
## Зовётся по прибытию (бег кончился), по истечении серии или её срока.
## Боец, уже дерущийся, ничего не меняет; стоящий или идущий берёт ближайшего
## чужого в RUSH_AGGRO_R. Никого нет — такт агро обнуляется, чтобы штатное
## авто-агро посмотрело на своём первом же тике
func _rush_aggro() -> void:
	if not _rush_pending:
		return
	_rush_pending = false
	if state == State.DEAD or _panicked or retreating:
		return
	if state == State.ATTACKING and attack_target != null and is_instance_valid(attack_target):
		return
	var foe: Node3D = GameManager.unit_grid.best_enemy(self, RUSH_AGGRO_R, CROWD_PENALTY)
	if foe != null and is_instance_valid(foe) and foe is Unit and not (foe as Unit).is_dead():
		rush_aggro_count += 1
		command_attack(foe, true)
	else:
		_aggro_timer = 0.0
		_wake_process()

## Прибежали — бег выключается сам (Unit._process_move), и это конец рывка
func _set_sprinting(on: bool) -> void:
	var was: bool = sprinting
	super._set_sprinting(on)
	if was and not on and _rush_pending:
		_rush_aggro()

func rage_left() -> int:
	return _rage_left if rage_active() else 0

## Стена щитов: набег идёт И до цели осталось не больше SHIELD_WALL_RANGE.
## Цель читается сырой ссылкой (правило 5): в разгаре набега она гибнет чаще,
## чем меняется
func shield_wall_active() -> bool:
	if not rage_active():
		return false
	var t = attack_target
	if t == null or not is_instance_valid(t):
		return false
	var tp: Vector3 = (t as Node3D).global_position
	var me: Vector3 = position if _local_xform else global_position
	return Vector2(tp.x - me.x, tp.z - me.z).length() <= SHIELD_WALL_RANGE

# Каждый 4-й удар — мощный: другой урон и другая анимация.
# В НАБЕГЕ ротация другая — фиксированная пятёрка (см. RAGE_STRONG)
func _strike_damage() -> float:
	# ── КРОВЬ БЕРСЕРКА: ниже половины запаса удар сильнее ─────────────────
	_refresh_forge()
	var mult: float = 1.0
	if _berserk > 0.0 and current_health < max_health * 0.5:
		mult += _berserk
	if rage_active():
		# Чередование «обычный → мощный → …» на любую длину серии: с
		# «Неистовством» их семь, и таблица из пяти шагов дала бы сбой ритма
		var strong: bool = (_rage_step % 2) == 1
		_rage_step += 1
		_rage_left -= 1
		rage_hits_done += 1
		if strong:
			rage_strong_done += 1
			_play_attack_anim("attack2", 380)
			return _attack_2_damage * mult
		_play_attack_anim("attack1", 300)
		return attack_damage * mult
	_combo_step += 1
	if _combo_step >= 4:
		_combo_step = 0
		_play_attack_anim("attack2", 600)
		return _attack_2_damage * mult
	_play_attack_anim("attack1", 450)
	return attack_damage * mult

## Стенды: сколько ударов серии ещё осталось (без учёта срока)
func rage_hits_left() -> int:
	return _rage_left

## ── РАССЕЧЕНИЕ — УДАР ПО ПЛОЩАДИ (узел warrior_2d, прокачка warrior_4d) ──
## После касания по цели тот же взмах задевает до cleave_targets() ЖИВЫХ
## чужих в досягаемости (attack_range + CLEAVE_PAD) в переднем секторе
## CLEAVE_ARC_COS от направления удара, ближайших первыми, на cleave_frac()
## урона. Один скан сетки на удар — событие, не покадровый путь
const CLEAVE_PAD := 0.8
const CLEAVE_ARC_COS := 0.15
## Стенды: сколько соседей задето всего и последним ударом
var cleave_hits: int = 0
var cleave_last: int = 0

func _after_melee_hit(tgt: Node3D, dmg: float, dir: Vector3) -> void:
	if _angry_pending:
		_angry_pending = false
		angry_shouts += 1
		AudioManager.squad_voice("knight_angry", _voice_key(), global_position, 1.0, AudioManager.KNIGHT_ANGRY_GAP)
	cleave_last = 0
	var n: int = cleave_targets()
	if n <= 0:
		return
	var frac: float = cleave_frac()
	if frac <= 0.0:
		return
	var mp: Vector3 = position if _local_xform else global_position
	var look: Vector3 = dir
	if look.length_squared() < 1e-6:
		look = _facing
	var reach: float = attack_range + CLEAVE_PAD
	var cand: Array = []      # [dist, Unit]
	for node in GameManager.unit_grid.query_radius(mp, reach):
		if node == null or not is_instance_valid(node) or node == tgt:
			continue
		var v := node as Unit
		if v == null or v.is_dead() or v.faction == faction or v.garrisoned:
			continue
		var off: Vector3 = v.global_position - mp
		off.y = 0.0
		var d: float = off.length()
		if d > reach:
			continue
		if d > 0.2 and (off.x * look.x + off.z * look.z) / d < CLEAVE_ARC_COS:
			continue
		cand.append([d, v])
	if cand.is_empty():
		return
	cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var k: int = mini(cand.size(), n)
	for i in range(k):
		var v: Unit = cand[i][1]
		if is_instance_valid(v) and not v.is_dead():
			v.take_damage(dmg * frac, self)
			cleave_hits += 1
			cleave_last += 1

## Удары серии быстрые: доля обычной перезарядки
func _effective_cooldown() -> float:
	var c: float = super._effective_cooldown()
	if rage_active():
		c *= RAGE_COOLDOWN_MULT
	return c

## ── НАПОР В НАБЕГЕ ────────────────────────────────────────────────────────
## Напор решает, СДВИНЕТСЯ ли жертва вообще (_apply_push выходит на
## неположительной разнице): в набеге мечник продавливает и тех, кто упёрся
func _push_power() -> float:
	var p: float = super._push_power()
	if rage_active():
		p *= RAGE_PUSH_MULT
	return p

## ── А ВОТ НАСКОЛЬКО СДВИНЕТСЯ — РЕШАЕТ МНОЖИТЕЛЬ ПОСЛЕ ПОТОЛКА ────────────
## И ЭТО НЕ ПРИДИРКА, А ЗАМЕР. Первая версия приёма поднимала ТОЛЬКО напор —
## и жертву отодвигало ровно на столько же, сколько без набега (стенд
## qa_knights_push D4: 0.70 против 0.68 м). Причина записана в шапке
## _apply_push: шаг зажат потолком 0.4 м, а потолок срабатывает уже при
## разнице напора в три единицы, то есть весь избыток напора в него и упёрся.
## Работает ровно то же, что у конницы, — множитель ПОСЛЕ clampf. Побочно это
## включает жертве плавный канал (push_smooth), то есть отлёт виден движением,
## а не телепортом: заказ дословно просил, чтобы «врагов заметно раскидывало»
func _push_after_cap() -> float:
	var m: float = super._push_after_cap()
	if rage_active():
		m *= RAGE_PUSH_MULT
	return m

# ─────────────────────────────────────────────────────────────────────────────
# ЗАЩИТА ЩИТОМ (AUTO-GUARD)
#
# ПОЧЕМУ ЭТО НЕ НОВОЕ ЗНАЧЕНИЕ В enum State, А НАДСТРОЙКА НАД ним.
# Стейт-машина Unit (IDLE/MOVING/ATTACKING/…) отвечает на вопрос «какой приказ
# юнит выполняет». Щит на этот вопрос не отвечает: мечник закрывается И стоя,
# И на марше, И между замахами в рубке — приказ при этом не меняется. Отдельное
# State.DEFENDING пришлось бы разбирать в каждом match по стейту (движение,
# поиск цели, строй, ИИ, HUD), и любая пропущенная ветка означала бы застрявшего
# бойца. Поэтому щит — независимый признак `_guard_active` поверх обычного
# стейта: он меняет анимацию, скорость и входящий урон, но не трогает приказ.
#
# Файл листа — Warrior_Guard.png (лежит в каждом цветном наборе). Направлений у
# него нет, в отличие от копейщика с его Lancer_*_Defence.png: разворот
# влево/вправо делает горизонтальный флип билборда в Unit._update_sprite_flip.
# ─────────────────────────────────────────────────────────────────────────────
const GUARD_ANIM  := "guard"
const GUARD_SHEET := "Warrior_Guard.png"

## Сколько щит остаётся поднятым после последней угрозы (выстрел, попадание)
const GUARD_HOLD_MS := 1600
## Доля урона, которую съедает щит: ближний бой и стрелы режутся по-разному
const GUARD_CUT_MELEE  := 0.50
const GUARD_CUT_RANGED := 0.70
## Косинус границы фронтального сектора. 0.0 — ровно передняя полусфера:
## всё, что прилетело сзади, щит не видит (backstab бьёт в полную силу)
const GUARD_FRONT_COS := 0.0
## Скорость под щитом: −35% (просили 30–40%). Мечник не останавливается,
## а идёт под обстрелом медленнее, прикрываясь на ходу
const GUARD_SPEED_FACTOR := 0.65

## Переключатель с панели юнита. Выключен — мечник игнорирует стрелы,
## щит сам не поднимает и ходит на полной скорости
var auto_guard: bool = true
## Щит поднят прямо сейчас (пересчитывается каждый кадр в _process)
var _guard_active: bool = false
## До какого момента (ticks_msec) действует «в меня стреляют / меня бьют»
var _threat_until_ms: int = 0

## Угроза свежая — есть повод держать щит
func _threatened() -> bool:
	return Time.get_ticks_msec() < _threat_until_ms

## Щит поднят по угрозе — картинку разбудить, когда угроза истечёт (этап 5);
## в рывке — на его срок (конец рывка разбирает визуальный тик)
func _vis_extra_wake_ms() -> int:
	if _rush_pending and _rage_until_ms > 0:
		return _rage_until_ms
	if _guard_active and _threat_until_ms > 0:
		return _threat_until_ms
	return 0

func _mark_threat() -> void:
	_threat_until_ms = Time.get_ticks_msec() + GUARD_HOLD_MS

## Щит поднят? Читает HUD для подсветки и стенды QA
func is_guarding() -> bool:
	return _guard_active

func set_auto_guard(on: bool) -> void:
	if auto_guard == on:
		return
	auto_guard = on
	if not on:
		_guard_active = false
		_threat_until_ms = 0
	_wake_process()

# Лучник зовёт это В МОМЕНТ ВЫСТРЕЛА (см. Archer._on_attack_fired), поэтому щит
# успевает встать до прилёта стрелы
func notify_incoming_fire(from: Vector3) -> void:
	if not auto_guard or state == State.DEAD:
		return
	_mark_threat()
	# Стоящий разворачивается ЛИЦОМ к стрелку: иначе щит окажется не с той
	# стороны и фронтальная проверка честно откажет в защите. Идущего не
	# доворачиваем — это сбило бы приказ на движение
	if state == State.IDLE:
		var d := from - global_position
		d.y = 0.0
		if d.length_squared() > 1e-4:
			_facing = d.normalized()
			_flip_dirty = true
	_wake_process()

# Поймал стрелу — держим щит поднятым ещё пару секунд.
#
# ТОЛЬКО ОБСТРЕЛ. «Стена щитов» — пассивка ПРОТИВ СТРЕЛЬБЫ: в ближнем бою щит
# остаётся ручным (переключатель игрока), иначе мечник закрывался бы сам в любой
# рубке и −50% превращались бы в постоянную прибавку к броне.
#
# Отметка ставится ПОСЛЕ super: множитель урона считается по тому щиту, который
# уже стоял, а не по поднятому этим же попаданием
func take_damage(amount: float, attacker: Node3D = null) -> void:
	super.take_damage(amount, attacker)
	if state == State.DEAD or not auto_guard:
		return
	if attacker is Archer:
		_mark_threat()

## Долевое снижение входящего урона щитом
func _incoming_damage_factor(attacker: Node3D) -> float:
	# ── БАЗА СЧИТАЕТСЯ ВСЕГДА ──────────────────────────────────────────────
	# В базе живёт легендарная «Стена щитов» (−40 % от стрел), и она положена
	# мечнику ровно так же, как всем. Раньше здесь стоял безусловный выход при
	# опущенном щите — то есть перк отряда мечников не работал бы вовсе, и
	# заметить это можно было бы только по числам
	var base: float = super._incoming_damage_factor(attacker)
	if not _guard_active:
		return base
	# УДАР В СПИНУ ЩИТ ИГНОРИРУЕТ полностью — но базовое снижение остаётся
	if attacker != null and not _is_front_attack(attacker):
		return base
	# Стрелы щит держит лучше, чем сталь в упор. Множители ПЕРЕМНОЖАЮТСЯ, а не
	# заменяют друг друга: щит и легендарный перк — разные вещи, и оба должны
	# работать. Ноля при этом не выходит ни при каких числах
	var cut: float = GUARD_CUT_RANGED if attacker is Archer else GUARD_CUT_MELEE
	return base * (1.0 - cut)

## Атакующий во фронтальном секторе?
func _is_front_attack(attacker: Node3D) -> bool:
	if _facing.length_squared() < 1e-6:
		return true          # направление неизвестно — считаем удар лобовым
	var to_atk := attacker.global_position - global_position
	to_atk.y = 0.0
	if to_atk.length_squared() < 1e-6:
		return true          # бьют вплотную сверху — сторону не определить
	return _facing.normalized().dot(to_atk.normalized()) > GUARD_FRONT_COS

func tick_visual(delta: float, frame: int = -1, anim_every: int = ANIM_EVERY,
		view_x: float = 0.0, view_z: float = 0.0, view_r2: float = INF,
		lerp_k: float = 1.0, mm_all: bool = true, prof: bool = false,
		fog_on: bool = true, cam_epoch: int = 0) -> void:
	_update_guard()
	super.tick_visual(delta, frame, anim_every, view_x, view_z, view_r2,
		lerp_k, mm_all, prof, fog_on, cam_epoch)

## Пересчёт признака «щит поднят». Поводов закрыться ДВА:
##   1) в юнита летит стрела или его только что ударили (_threatened);
##   2) отряду ВКЛЮЧЕН режим обороны игроком (стойка «Защита»).
## Во время самого замаха (_anim_lock_until_ms) щит опущен: одновременно бить
## и закрываться нельзя, да и анимация удара всё равно перекрыла бы guard.
##
## ── ПОКОЙ ЩИТА БОЛЬШЕ НЕ ПОДНИМАЕТ ─────────────────────────────────────────
## Здесь стояло `or state == State.IDLE`, и мечник стоял под щитом ВСЕГДА:
## любой боец без дела — это IDLE, то есть вся армия на марше между приказами
## и весь гарнизон жили в оборонительной позе. Заказ владельца прямой: в покое
## щит опущен, поднимается на включённый режим или на первый же прилёт.
## Реакция на угрозу при этом не изменилась ни на кадр — она в _threatened()
func _update_guard() -> void:
	# Конец рывка по СЕРИИ или СРОКУ (прибытие ловит _set_sprinting): рывок
	# начат, а ярости уже нет — в бой с ближайшим, один раз
	if _rush_pending and not sprinting and not rage_active():
		_rush_aggro()
	var want := false
	if auto_guard and state != State.DEAD and Time.get_ticks_msec() >= _anim_lock_until_ms:
		# ЩИТ В НАБЕГЕ ПОДНЯТ БЕЗУСЛОВНО (заказ: «рывок с зафиксированными
		# щитами»), и требование auto_guard тут не при чём — режим включил сам
		# игрок двойным ПКМ
		want = _threatened() or _stance_holds_ground() or rage_active()
	if want != _guard_active:
		# Щит поднялся или опустился — поза обязана смениться В ЭТОМ ЖЕ КАДРЕ.
		# Обычный пересчёт идёт раз в ANIM_EVERY кадров, и стрела вполне
		# успевает долететь за эту паузу: со стороны щит «не срабатывает»
		mark_pose_dirty()
	_guard_active = want

# Анимация щита важнее walk/idle, но НЕ важнее анимации удара: пока идёт замах,
# базовая проверка _anim_lock_until_ms не пускает сюда никого
func _update_sprite_anim() -> void:
	if Time.get_ticks_msec() < _anim_lock_until_ms:
		return
	if _guard_active and _has_anim(GUARD_ANIM):
		if _anim_name != GUARD_ANIM:
			_set_anim(GUARD_ANIM)
		return
	super._update_sprite_anim()

# МАРШ ПОД ЩИТОМ: мечник не встаёт под обстрелом, а идёт медленнее.
#
# ШТРАФЫ НЕ ПЕРЕМНОЖАЮТСЯ. Штраф стойки «Защита» (STANCES.move_speed_mult, те же
# −35%) и штраф поднятого щита — это ОДНО И ТО ЖЕ замедление, названное дважды:
# боец идёт шагом, прикрываясь. Перемножение давало 0.65 × 0.65 = 0.42, то есть
# мечник в обороне под обстрелом полз вдвое медленнее заказанного. Берём
# наибольший штраф из двух, а не их произведение.
func _effective_speed() -> float:
	var s: float = super._effective_speed()
	# РЫВОК БЫСТРЕЕ ОБЫЧНОГО ХОДА, И ШТРАФ ЩИТА ЕГО НЕ СЪЕДАЕТ: множитель
	# ставится ПОСЛЕ ветки щита (ниже), иначе 1.45 × 0.65 дало бы 0.94 — то
	# есть «рывок» медленнее обычного марша
	if rage_active():
		var m: float = RAGE_SPEED_MULT
		if shield_wall_active():
			m *= SHIELD_WALL_SPEED_MULT
		return s * m
	if _guard_active:
		var stance_mult: float = _UStats.stance_stat(stance, "move_speed_mult", 1.0)
		if stance_mult > GUARD_SPEED_FACTOR:
			s *= GUARD_SPEED_FACTOR / maxf(stance_mult, 0.01)
	return s

# Сон _process. Базовая версия отказывается спать при любой анимации, кроме
# "idle", — со щитом наизготовку стоящая армия мечников не заснула бы никогда
# и съела бы кадр. Под угрозой не спим — щит должен опуститься вовремя.
# ЗДЕСЬ СТОЯЛО «AnimatedSprite3D крутит цикл сам, без нашего _process» — это
# было верно до общей отрисовки: теперь узел на паузе (_look_detach_node), и
# ленту листает ТОЛЬКО визуальный тик. Уснувший мечник замирал на случайном
# кадре idle/guard («еле дышит»), поэтому многокадровую ленту не усыпляем —
# то же правило, что у базы и у копейщика
func _process_can_sleep() -> bool:
	if Time.get_ticks_msec() < _anim_lock_until_ms:
		return false
	if _threatened() or rage_active():
		return false
	if _anim_name != &"" and _anim_name != &"idle" and _anim_name != GUARD_ANIM:
		return false
	return not (_look_loop and _look_frames > 1)

func _setup_warrior_visual() -> void:
	var fname := GameManager.race_of(faction)
	# Набор ЦВЕТА СВОЕЙ ФРАКЦИИ, запасной — общий soldier_pack
	var pack_path := GameManager.unit_sprite_folder(faction, "warrior")
	# Проба ПО ФАЙЛУ, а не по каталогу (см. SpriteSheetParser.folder_has)
	var colored := _SSParser.folder_has(pack_path, "Warrior_Idle.png")
	if not colored:
		pack_path = "res://assets/factions/%s/units/soldier_pack" % fname
	var tint := Color.WHITE
	if not colored:
		tint = Color(1.0, 0.55, 0.55) if faction == Constants.FACTION_ENEMY else Color(0.82, 0.92, 1.0)

	# 1. Явная карта листов: idle/walk + раздельные анимации ударов + щит.
	# GUARD_SHEET зациклен намеренно (в no_loop его нет): щит держат, пока есть
	# угроза, а не проигрывают один раз
	var mapped: AnimatedSprite3D = _SSParser.build_sprite_from_map(pack_path, {
		"idle":    "Warrior_Idle.png",
		"walk":    "Warrior_Run.png",
		"attack1": "Warrior_Attack1.png",
		"attack2": "Warrior_Attack2.png",
		GUARD_ANIM: GUARD_SHEET,
	}, ["attack1", "attack2"])
	if mapped:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		mapped.modulate = tint
		add_child(mapped)
		_active_sprite = mapped
		return

	# 2. Автосканирование папки (общая анимация attack)
	var asp: AnimatedSprite3D = _SSParser.build_animated_sprite(pack_path)
	if asp:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		asp.modulate = tint
		add_child(asp)
		_active_sprite = asp
		return

	# 3. Один PNG из soldier_pack
	var idle_path := "res://assets/factions/%s/units/soldier_pack/Warrior_Idle.png" % fname
	if ResourceLoader.exists(idle_path):
		var tex := load(idle_path) as Texture2D
		if tex:
			set_sprite_texture(tex)
			return

	# 4. Цветовой оттенок на базовом billboard-спрайте.
	# Квад заводится ТОЛЬКО здесь: у мечника со спрайт-листом его нет
	_ensure_body_quad()
	if _sprite_node:
		var mat := _sprite_node.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.75, 0.30, 0.90) if faction == Constants.FACTION_PLAYER else Color(0.90, 0.30, 0.30)
