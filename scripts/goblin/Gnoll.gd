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
const _OptG     := preload("res://scripts/perf_config.gd")

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
## ДОМАШНЯЯ ТОЧКА (ТЗ 14.09.2026, п. 5): пишется вместе с пнём при рождении.
## Пень снесён или гнолл из слепка — патруль идёт вокруг неё, а не вокруг
## чужого пня за тысячу метров (прежний фолбэк GameManager.troll_lair и
## был «хаотичной миграцией» стай через всю карту)
var home_pos: Vector3 = Vector3.INF
## Угол кругового патруля и направление обхода (±1, по номеру узла)
var _patrol_ang: float = NAN
var _patrol_dir: float = 1.0

## ── БРОСОК ВЫЛЕТАЕТ С КАДРА ЗАМАХА, А НЕ С НАЧАЛА ЛЕНТЫ ───────────────────
## Боевая петля зовёт `_on_attack_fired` в момент УДАРА, а лента броска
## (Gnoll_Throw, восемь кадров) в этот миг только начинается: кость вылетала
## из опущенной руки. Теперь бросок ПЛАНИРУЕТСЯ — цель и урон запоминаются,
## а сам снаряд рождается через `_throw_delay()` секунд, то есть ровно на том
## кадре, где рука распрямилась.
## ЦЕЛЬ ЗАПОМИНАЕТСЯ ТОЧКОЙ, А НЕ ССЫЛКОЙ: за полкадра замаха жертва может
## погибнуть, и бросок обязан уйти туда, куда гнолл целился, — иначе рука
## провожает пустоту (и правило 5: ссылка на освобождённый узел бросает)
var _throw_left: float = 0.0
var _throw_aim: Vector3 = Vector3.ZERO
var _throw_dmg: float = 0.0
## Задуманный промах едет вместе с броском: считать его в момент ПРИЦЕЛИВАНИЯ
## нельзя — замах, перебитый следующим приказом, до кости не доходит вовсе, и
## доля промахов считалась бы от несостоявшихся бросков
var _throw_miss: bool = false

var _patrol_t: float = 0.0
var _kite_t: float = 0.0
var _flank_t: float = 0.0
## Своя доля интервала: скан после промаха взводится не у всех разом
var _scan_phase: float = 0.0
## ── КАЙТ ПО ФАКТУ, А НЕ ПО ТАЙМЕРУ ────────────────────────────────────────
## Точка, из которой начат последний отход, и срок, к которому он обязан дать
## заметное смещение. Не дал — отбегать некуда (свои тела), кайт глушится и
## гнолл стоит и метает. Без этого он вечно оставался в MOVING и «бежал на
## месте» с непрерывным лупом шагов (жалоба спринта 14)
var _kite_from: Vector3 = Vector3.INF
var _kite_check_t: float = 0.0
var _kite_block_t: float = 0.0
## ── СЕРИЯ КАЙТОВ (14.09.2026) ──────────────────────────────────────────────
## Гнолл в кольце тел: каждый отдельный отход «удаётся» на метр (внутри
## кольца есть где качнуться), а суммарно он топчется на месте — отходы
## меняют направление вслед за ближайшим врагом. Серия: якорь первого кайта
## и счётчик; GNOLL_KITE_SERIES кайтов подряд без ухода от якоря дальше
## GNOLL_KITE_MIN_GAIN × 1.5 — отходить некуда, тот же блок
var _kite_series_from: Vector3 = Vector3.INF
var _kite_series_n: int = 0
var _kite_series_t: float = 0.0
const GNOLL_KITE_SERIES := 2
const GNOLL_KITE_SERIES_GAP := 3.0
## Стенды: сколько раз кайт признан невозможным
var kite_blocked: int = 0
## Бежит прятаться в пень (см. GNOLL_HIDE_HP); внутри — `hidden`
var hiding_to_lair: bool = false
var hidden: bool = false
## Стенды: сколько раз ужаленный гнолл взял обидчика целью и сколько отходов
var aggro_answers: int = 0
var run_backs: int = 0
## Пока > 0 — гнолл отходит после броска: фланг и патруль его не перебивают
var _run_back_t: float = 0.0
## Стенды: сколько раз отбегал от подошедшей пехоты и сколько костей метнул
var kites: int = 0
var bones_thrown: int = 0
var bones_missed: int = 0

## ── ЗОНА ОТВЕТСТВЕННОСТИ И ОХОТА (13.09.2026, GnollAI.gd) ──────────────────
## Все точки патруля / кайта / фланга зажимаются в зону пня (лес слева,
## справа и ниже, без полуплоскости «к базе людей» и без брода); ушедший из
## зоны бросает цель и возвращается. На охоте (hunt) гнолл ПРЕСЛЕДУЕТ
## рабочего, не кайтит от него и после броска не отходит — закидывает и
## добивает. Контроллер берётся у Main лениво
var hunting: bool = false
var zone_returns: int = 0
var _zone_t: float = 0.0
var _zone_ai = null
var _zone_from: Vector3 = Vector3.INF   # откуда отдан последний возврат в зону
const ZONE_CHECK_SEC := 0.5
const ZONE_SLACK := 4.0

func _zone():
	if _zone_ai == null or not is_instance_valid(_zone_ai):
		var m = GameManager.main
		_zone_ai = m.get("gnoll_ai") if m != null and is_instance_valid(m) else null
	return _zone_ai

func _in_zone_pt(p: Vector3) -> Vector3:
	var z = _zone()
	if z == null or lair == null or not is_instance_valid(lair):
		return p
	return z.clamp_to_zone(lair, p)

## Охота на рабочего: цель приказом, преследование включено
func hunt(prey: Node3D) -> void:
	if prey == null or not is_instance_valid(prey) or hidden or hiding_to_lair:
		return
	hunting = true
	command_attack(prey, true)

## Раз в ZONE_CHECK_SEC: вышел из зоны — цель долой, назад в зону.
## true — приказ отдан, остальная логика такта пропускается
func _tick_zone(delta: float) -> bool:
	_zone_t -= delta
	if _zone_t > 0.0:
		return false
	_zone_t = ZONE_CHECK_SEC
	var z = _zone()
	if z == null or lair == null or not is_instance_valid(lair):
		return false
	if _kite_block_t > 0.0:
		return false               # стоим: отходить некуда (см. ниже)
	if hunting and (attack_target == null or not is_instance_valid(attack_target) \
			or (attack_target as Unit).is_dead()):
		hunting = false
	if attack_target != null and is_instance_valid(attack_target) \
			and not z.in_zone(lair, attack_target.global_position, ZONE_SLACK * 2.0):
		set_attack_target(null)
		hunting = false
	if not z.in_zone(lair, global_position, ZONE_SLACK):
		# «ОТОЙТИ НЕКУДА — НЕ БЕЖАТЬ НА МЕСТЕ» (то же правило, что у кайта):
		# возврат, не давший хода с прошлой проверки, глушится на
		# GNOLL_KITE_BLOCK_SEC, боец стоит. Иначе зажатый чужими телами гнолл
		# получал бы command_move каждые полсекунды (qa_gnoll_fix B4/B5)
		if _zone_from.x != INF and Vector2(global_position.x - _zone_from.x,
				global_position.z - _zone_from.z).length() < _GobCfgG.GNOLL_KITE_MIN_GAIN:
			_zone_from = Vector3.INF
			_kite_block_t = _GobCfgG.GNOLL_KITE_BLOCK_SEC
			kite_blocked += 1
			velocity = Vector3.ZERO
			if state == State.MOVING:
				state = State.IDLE
			return false
		set_attack_target(null)
		hunting = false
		zone_returns += 1
		_zone_from = global_position
		if _OptG.cmd_meter: _OptG.cmd_src = "gnoll_zone"
		command_move(GameManager.land_target(z.clamp_to_zone(lair, global_position)))
		if _OptG.cmd_meter: _OptG.cmd_src = ""
		return true
	_zone_from = Vector3.INF
	return false

func _ready() -> void:
	_apply_config_stats("gnoll")
	display_name = "Гнолл"
	super._ready()
	_setup_visual()
	# Фаза скана — от номера узла, а не от randf(): два прогона одного боя
	# обязаны дать одно поле (то же правило, что у угла втыкания стрелы)
	_scan_phase = float(get_instance_id() % _GobCfgG.GNOLL_SCAN_PHASES) \
		/ float(_GobCfgG.GNOLL_SCAN_PHASES)

## Взвести интервал после ПРОМАХА скана: врага в радиусе не нашлось.
## Без ручки возвращает ноль — то есть прежнее «сканируем каждый тик»
func _miss_gate(sec: float) -> float:
	if not _OptG.gnoll_scan_gate:
		return 0.0
	return sec * (0.75 + 0.5 * _scan_phase)

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
	return hunting

## Поводок инициативы уже своего рода войск: гнолл не сбегается на далёкий бой
func aggro_leash() -> float:
	return _GobCfgG.GNOLL_AGGRO_LEASH

func _sfx_swing() -> String:
	return ""

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
	return ""

# ─────────────────────────────────────────────────────────────────────────────
# БРОСОК КОСТИ
# ─────────────────────────────────────────────────────────────────────────────
func _on_attack_fired(target: Node3D, damage: float) -> void:
	# ── ЗАМАХ УЖЕ ИДЁТ — СНАЧАЛА ВЫПУСТИТЬ ТУ КОСТЬ (спринт 16) ─────────
	# Новый удар до вылета прежней кости ПЕРЕЗАПУСКАЛ отсчёт замаха, и кость
	# терялась: у гнолла, получившего цель от авто-агро посреди чужого замаха,
	# первый бросок пропадал вовсе (qa_gnoll_fix C6/E6 — «в воздухе 0»)
	if _throw_left > 0.0:
		_throw_left = 0.0
		_release_bone()
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
	# ── ЦЕЛИТСЯ СЕЙЧАС, БРОСАЕТ НА КАДРЕ ЗАМАХА ───────────────────────────
	_throw_aim = aim
	_throw_dmg = damage
	_throw_miss = miss
	_throw_left = _throw_delay()

## Сколько ждать от начала ленты до вылета кости. Считается ИЗ САМОЙ ЛЕНТЫ
## (номер кадра на её темп): перерисуют бросок другим числом кадров или fps —
## задержка доедет сама, без правки кода
func _throw_delay() -> float:
	var fps := 10.0
	var asp := _active_sprite as AnimatedSprite3D
	if asp != null and asp.sprite_frames != null \
			and asp.sprite_frames.has_animation("attack"):
		fps = maxf(asp.sprite_frames.get_animation_speed("attack"), 1.0)
	return float(_GobCfgG.GNOLL_THROW_FRAME) / fps

## Выпустить запланированную кость. Зовётся из тика по истечении задержки
func _release_bone() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var from_pos: Vector3 = global_position + Vector3(0.0, _GobCfgG.GNOLL_THROW_Y, 0.0)
	# Звук — ровно в кадре, когда кость покидает руку (не в _on_attack_fired,
	# где только считается прицел и взводится задержка _throw_delay)
	AudioManager.play_3d("gnoll_throw", global_position)
	bones_thrown += 1
	if _throw_miss:
		bones_missed += 1
	var dist: float = from_pos.distance_to(_throw_aim)
	GameManager.spawn_arrow(parent, from_pos, _throw_aim, dist,
		_GobCfgG.GNOLL_BONE_SPEED, _GobCfgG.GNOLL_BONE_ARC, _throw_dmg, self,
		faction, true)
	# ── МЕТНУЛ — ОТОШЁЛ (спринт 16: «подбегают, метают кость и отступают») ──
	# Отход к пню на GNOLL_RUN_BACK обычным приказом: он снимает цель, гнолл
	# уходит в покой, и следующий наскок ему даёт либо авто-агро, либо новый
	# укол обидчика (см. take_damage). Без пня — просто прочь от цели
	# Отход — только у НАСТОЯЩЕГО броска по цели: у стенда, дёргающего
	# _on_attack_fired напрямую без цели, гнолл остаётся на месте
	if attack_target == null:
		return
	# Отойти некуда (кайт это уже выяснил — _kite_block_t): не бежать на месте
	if _kite_block_t > 0.0 or hunting:
		return
	var back: Vector3 = global_position - _throw_aim
	back.y = 0.0
	if lair != null and is_instance_valid(lair):
		back = lair.global_position - global_position
		back.y = 0.0
	if back.length_squared() > 1e-4:
		run_backs += 1
		if _OptG.cmd_meter: _OptG.cmd_src = "gnoll_runback"
		command_move(GameManager.land_target(
			global_position + back.normalized() * _GobCfgG.GNOLL_RUN_BACK))
		if _OptG.cmd_meter: _OptG.cmd_src = ""
		# Срок отхода — дорога плюс запас: фланговый приказ (_tick_flank) и
		# патруль иначе перебивали отход в следующий же такт, и гнолл бежал
		# ОБРАТНО к стрелку (qa_gnoll_behavior B3: «было 7.1, стало 6.9»)
		_run_back_t = _GobCfgG.GNOLL_RUN_BACK / maxf(move_speed, 0.5) + 0.4
		# Тот же надзор, что у кайта: не сдвинулся за GNOLL_KITE_GIVEUP —
		# отход признаётся невозможным, гнолл встаёт (см. _tick_kite)
		_kite_from = global_position
		_kite_check_t = _GobCfgG.GNOLL_KITE_GIVEUP

# ─────────────────────────────────────────────────────────────────────────────
# ХОД: КАЙТ, ФЛАНГ, ПАТРУЛЬ
# ─────────────────────────────────────────────────────────────────────────────
func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	super.tick_physics(delta, prof, bm, bonus_ver)
	if state == State.DEAD:
		# Замах, оборванный смертью, броска не даёт
		_throw_left = 0.0
		return
	# ── ОТЛОЖЕННЫЙ БРОСОК ─────────────────────────────────────────────────
	# Стоит ПЕРВЫМ и до всех ворот хода: кость обязана вылететь на своём кадре
	# независимо от того, кайтит гнолл, обходит с фланга или патрулирует
	if _throw_left > 0.0:
		_throw_left -= delta
		if _throw_left <= 0.0:
			_throw_left = 0.0
			_release_bone()
	# ── ПЕНЬ ПОТЕРЯН — ПОДХВАТЫВАЕМ ТОЛЬКО БЛИЖНИЙ (ТЗ 14.09.2026, п. 5) ─
	# Гнолл из слепка или с оставшимся снесённым пнём брал ПЕРВОЕ логово
	# партии и бежал к нему через всю карту. Теперь: ближайший пень не дальше
	# GNOLL_HOME_ADOPT_R от дома, иначе — дом (home_pos), патруль вокруг него
	if lair == null or not is_instance_valid(lair):
		lair = null
		if home_pos.x == INF:
			home_pos = global_position
		var nl: Node = GameManager.nearest_lair(home_pos)
		if nl != null and is_instance_valid(nl) and Vector2(
				(nl as Node3D).global_position.x - home_pos.x,
				(nl as Node3D).global_position.z - home_pos.z).length() <= _GobCfgG.GNOLL_HOME_ADOPT_R:
			lair = nl as Node3D
			home_pos = lair.global_position
	# ПОРЯДОК ВОРОТ ЗНАЧИМ: кайт важнее и фланга, и патруля. Подошедшая пехота
	# убивает гнолла за пару ударов, а «отойти» — единственная его защита
	# ── БЕЖИТ В ПЕНЬ: ничего другого не делает, у ворот прячется ──────────
	if hiding_to_lair:
		if lair == null or not is_instance_valid(lair) or bool(lair.call("is_dead")):
			hiding_to_lair = false
		else:
			var d_l: float = Vector2(global_position.x - lair.global_position.x,
				global_position.z - lair.global_position.z).length()
			if d_l <= _GobCfgG.GNOLL_HIDE_RANGE:
				lair.call("hide_gnoll", self)
				return
			if state != State.MOVING:
				command_move(GameManager.land_target(lair.global_position))
			return
	if _tick_zone(delta):
		return
	if _tick_kite(delta):
		return
	if _run_back_t > 0.0:
		_run_back_t -= delta
		if state == State.MOVING:
			return
		_run_back_t = 0.0
	if _tick_flank(delta):
		return
	_tick_patrol(delta)

## Отбежать от подошедшей вплотную пехоты. true — шаг выдан, дальше не идём
func _tick_kite(delta: float) -> bool:
	# ── ПРОВЕРКА ПРЕДЫДУЩЕГО ОТХОДА ────────────────────────────────────────
	# Отход выдан — смотрим, дал ли он смещение. Не дал — бежать некуда
	if _kite_series_n > 0:
		_kite_series_t -= delta
		if _kite_series_t <= 0.0:
			_kite_series_n = 0
			_kite_series_from = Vector3.INF
	if _kite_check_t > 0.0:
		_kite_check_t -= delta
		if _kite_check_t <= 0.0 and _kite_from.x != INF:
			var gain: float = Vector2(global_position.x - _kite_from.x,
				global_position.z - _kite_from.z).length()
			# Серия отходов без ухода от якоря — тоже «некуда» (кольцо тел)
			if _kite_series_n >= GNOLL_KITE_SERIES and _kite_series_from.x != INF \
					and Vector2(global_position.x - _kite_series_from.x,
					global_position.z - _kite_series_from.z).length() < _GobCfgG.GNOLL_KITE_MIN_GAIN * 1.5:
				gain = 0.0
			if gain < _GobCfgG.GNOLL_KITE_MIN_GAIN:
				# Отбегать некуда: глушим кайт и ВСТАЁМ — стоящий метатель
				# полезнее бегущего на месте, и лупа шагов он не держит
				_kite_block_t = _GobCfgG.GNOLL_KITE_BLOCK_SEC
				kite_blocked += 1
				velocity = Vector3.ZERO
				if state == State.MOVING:
					state = State.IDLE
				_kite_series_n = 0
				_kite_series_from = Vector3.INF
			_kite_from = Vector3.INF
	if _kite_block_t > 0.0:
		_kite_block_t -= delta
		return false
	_kite_t -= delta
	if _kite_t > 0.0:
		return false
	var foe: Node3D = _nearest_melee_foe(_GobCfgG.GNOLL_KITE_IN)
	if foe == null:
		# ПРОМАХ ТОЖЕ ВЗВОДИТ ЧАСЫ: иначе скан идёт каждый физтик (см. _miss_gate)
		_kite_t = _miss_gate(_GobCfgG.GNOLL_KITE_MISS_SEC)
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
	if _OptG.cmd_meter: _OptG.cmd_src = "gnoll_kite"
	command_move(GameManager.land_target(_in_zone_pt(p)))
	if _OptG.cmd_meter: _OptG.cmd_src = ""
	# Точка отсчёта смещения: по ней и решается, удался ли отход
	_kite_from = global_position
	_kite_check_t = _GobCfgG.GNOLL_KITE_GIVEUP
	if _kite_series_n == 0:
		_kite_series_from = global_position
	_kite_series_n += 1
	_kite_series_t = GNOLL_KITE_SERIES_GAP
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
	# От рабочего не кайтим: он добыча, а не угроза (охота в лесу)
	if u is Worker:
		return null
	return u

## Оборона пня: встать СБОКУ от линии «пень → враг». true — шаг выдан
func _tick_flank(delta: float) -> bool:
	_flank_t -= delta
	if _flank_t > 0.0:
		return false
	# ── ОТВЕТ ОБИДЧИКУ ВАЖНЕЕ ФЛАНГА (спринт 16) ──────────────────────────
	# Фланговый приказ — command_move, и он снимает цель: ужаленный гнолл
	# брал стрелка целью и через такт уезжал на фланг, так и не бросив
	# (qa_gnoll_behavior B2: «брошено 0»). Пока цель есть — фланг подождёт
	if attack_target != null:
		return false
	if lair == null or not is_instance_valid(lair):
		return false
	if lair.has_method("is_dead") and bool(lair.call("is_dead")):
		return false
	# Оборона нужна, только когда враг УЖЕ У ПНЯ
	var foe: Node3D = _nearest_foe_at((lair as Node3D).global_position,
		_GobCfgG.GNOLL_DEFEND_RANGE)
	if foe == null:
		# Самый дорогой скан в классе (r = 34 м): без взвода часов он идёт
		# КАЖДЫЙ физтик у каждого гнолла всю партию — см. _miss_gate
		_flank_t = _miss_gate(_GobCfgG.GNOLL_FLANK_MISS_SEC)
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
	if _OptG.cmd_meter: _OptG.cmd_src = "gnoll_flank"
	command_move(GameManager.land_target(_in_zone_pt(p)))
	if _OptG.cmd_meter: _OptG.cmd_src = ""
	return true

## Центр патруля: пень, а без него — домашняя точка
func _home() -> Vector3:
	if lair != null and is_instance_valid(lair):
		return lair.global_position
	return home_pos

## ── ПАТРУЛЬ — КРУГОВОЙ МАРШ ВОКРУГ ПНЯ (ТЗ 14.09.2026, п. 5) ───────────────
## Прежде каждая точка бралась случайным углом — прямые векторы через всю
## поляну. Теперь угол ШАГАЕТ на GNOLL_PATROL_STEP_DEG в своём направлении
## обхода, радиус держится у GNOLL_PATROL_RADIUS: стая кружит вокруг
## контрольной точки. Точка отрезка притягивается к ближайшему дереву
## (GnollAI.forest_spots) — патруль идёт лесом. Только в покое и без цели
func _tick_patrol(delta: float) -> void:
	if state != State.IDLE or attack_target != null:
		return
	# Отходить некуда (кайт заглушен) — и патрулировать некуда: стоим
	if _kite_block_t > 0.0:
		return
	var home: Vector3 = _home()
	if home.x == INF:
		return
	_patrol_t -= delta
	if _patrol_t > 0.0:
		return
	_patrol_t = _GobCfgG.GNOLL_PATROL_SEC * randf_range(0.7, 1.3)
	if is_nan(_patrol_ang):
		var here: Vector3 = global_position - home
		_patrol_ang = atan2(here.z, here.x) if here.length() > 0.5 else randf() * TAU
		_patrol_dir = 1.0 if (get_instance_id() % 2) == 0 else -1.0
	_patrol_ang += deg_to_rad(_GobCfgG.GNOLL_PATROL_STEP_DEG) * _patrol_dir * randf_range(0.8, 1.2)
	var r: float = _GobCfgG.GNOLL_PATROL_RADIUS * randf_range(0.7, 1.0)
	var p: Vector3 = home + Vector3(cos(_patrol_ang) * r, 0.0, sin(_patrol_ang) * r)
	p = _in_zone_pt(p)
	var z = _zone()
	if z != null and lair != null and is_instance_valid(lair):
		var tree: Vector3 = z.nearest_forest_spot(lair, p, _GobCfgG.GNOLL_PATROL_TREE_SNAP)
		if tree.x != INF:
			# К стволу вплотную не идём — рядом с ним, чтобы не упереться
			var off: Vector3 = p - tree
			off.y = 0.0
			if off.length() < 0.5:
				off = Vector3(cos(_patrol_ang), 0.0, sin(_patrol_ang))
			p = tree + off.normalized() * 1.6
	if _OptG.cmd_meter: _OptG.cmd_src = "gnoll_patrol"
	command_move(GameManager.land_target(p))
	if _OptG.cmd_meter: _OptG.cmd_src = ""

## Ответ на обстрел у гнолла свой (ниже, в take_damage), общий не нужен
func answers_far_fire() -> bool:
	return false

## Удар по гноллу поднимает волну у пня — тем же путём, что у тролля
func take_damage(amount: float, attacker: Node3D = null) -> void:
	if state == State.DEAD:
		return
	super.take_damage(amount, attacker)
	if state == State.DEAD:
		return
	if lair != null and is_instance_valid(lair) and lair.has_method("on_gnoll_hit"):
		lair.call("on_gnoll_hit", self, attacker)
	if hidden:
		return
	# ── МАЛО ЗАПАСА — В ПЕНЬ ───────────────────────────────────────────────
	if not hiding_to_lair and lair != null and is_instance_valid(lair) \
			and not bool(lair.call("is_dead")) \
			and current_health < max_health * _GobCfgG.GNOLL_HIDE_HP:
		hiding_to_lair = true
		_throw_left = 0.0
		command_move(GameManager.land_target(lair.global_position))
		return
	# ── УЖАЛИЛИ — ОТВЕТИТЬ ОБИДЧИКУ ───────────────────────────────────────
	# Базовый ответ на удар работает только вплотную (COUNTER_CHARGE_RANGE), а
	# гнолла бьют стрелой с двадцати метров: он продолжал патрулировать под
	# обстрелом. Обидчик, кем бы он ни был, становится целью — гнолл подбегает
	# на бросок (Unit.pursues_target у него «да») и метает
	if attack_target == null and attacker != null and is_instance_valid(attacker) \
			and attacker is Unit and (attacker as Unit).faction != faction \
			and not (attacker as Unit).is_dead():
		aggro_answers += 1
		command_attack(attacker, true)
