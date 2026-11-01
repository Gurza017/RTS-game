extends RefCounted
## Ручки производительности и измерители стендов: выключатели оптимизаций
## массового боя, лестница шардов тика, счётчики замеров. Поля СТАТИЧЕСКИЕ —
## их читает горячий путь десятки тысяч раз в секунду, автозагрузка тут не нужна.
## Подключение: const _Opt := preload("res://scripts/perf_config.gd")
## Любая ручка читается из командной строки стенда: `-- knob=имя:значение`.
## История замеров, A/B и разворотов — docs/config_notes/perf_config.md

# ── ПОИСК ЦЕЛИ И СОСТОЯНИЕ ОТРЯДА ──
## Скан врага делает первый спросивший боец отряда, остальные берут кэш отряда на squad_target_ttl
static var squad_target_cache: bool = true

## Ответ squad_in_combat кэшируется на физкадр (иначе квадрат по составу отряда); false — только для A/B
static var squad_combat_cache: bool = true

# ── ОТРИСОВКА: LOD И ОБЩИЙ MultiMesh ──
## Направленная поза и кадры анимации считаются только в lod_radius от фокуса камеры
static var sprite_lod: bool = true

## Нижняя граница LOD-радиуса от фокуса камеры, м (реальный радиус растёт с зумом)
static var lod_radius: float = 90.0

## Срок жизни общего результата поиска цели у отряда, с
static var squad_target_ttl: float = 0.4

## Вся армия (и ближние) рисуется общим MultiMesh; false — режим замеров, бойцы у камеры узлами и сплющены
static var mm_render_all: bool = true

# ── ИЗМЕРИТЕЛИ (вердиктов нет, включают стенды) ──
## Разбивка физтика по веткам парой часов на ветку бойца; завышает тик на 25-35 %, только для ранжирования
static var profile_physics: bool = false
## Трёхточечный радар отряда на марше: заслон щупают три точки фронта, личный blocker_reach молчит, пока пусто
static var march_radar: bool = true

## Таймерный скан заслона на марше (blocker_reach); false — измеритель потолка: только упор телом (`wall`)
static var march_blocker_scan: bool = true

## Скан целей у стрелков — один на отряд, 2 Гц, с фазой прицеливания; false — личный опрос + кэш с TTL
static var squad_radar: bool = true

## Счётчик сканов сетки (Unit._find_nearest_enemy_in_range): вызовы по меткам места вызова, без часов
static var scan_meter: bool = false
static var scan_calls: int = 0
## Метка места вызова → число сканов
static var scan_sites: Dictionary = {}

static func scan_reset() -> void:
	scan_calls = 0
	scan_sites = {}

static func scan_hit(site: String) -> void:
	scan_calls += 1
	scan_sites[site] = int(scan_sites.get(site, 0)) + 1

## [[метка, вызовов], …] по убыванию
static func scan_report() -> Array:
	var rows: Array = []
	for k in scan_sites:
		rows.append([String(k), int(scan_sites[k])])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	return rows

## Промах скана гнолла (кайт, оборона пня) взводит короткий интервал, фазы разведены по узлу; false — скан каждый физтик
static var gnoll_scan_gate: bool = true

## Часы тика по родам войск (stat_id) и по состояниям; дорого (две пары часов на бойца), включает стенд
static var class_meter: bool = false
static var _class_usec: Dictionary = {}
static var _class_ticks: Dictionary = {}
static var _class_frames: int = 0
## Время и число вызовов NavPath (меряется отдельно от классов)
static var nav_usec: int = 0
static var nav_calls: int = 0

static func class_reset() -> void:
	_class_usec = {}
	_class_ticks = {}
	_class_max = {}
	_class_frames = 0
	_state_usec = {}
	_state_ticks = {}
	nav_usec = 0
	nav_calls = 0

## Худший одиночный тик по классу [мкс, состояние бойца] — пики, а не средние
static var _class_max: Dictionary = {}

static func class_add(id: String, usec: int, state: int = -1) -> void:
	_class_usec[id] = int(_class_usec.get(id, 0)) + usec
	_class_ticks[id] = int(_class_ticks.get(id, 0)) + 1
	var m: Variant = _class_max.get(id)
	if m == null or usec > int((m as Array)[0]):
		_class_max[id] = [usec, state]
	# те же часы — раскладка по состояниям IDLE / MOVING / ATTACKING
	_state_usec[state] = int(_state_usec.get(state, 0)) + usec
	_state_ticks[state] = int(_state_ticks.get(state, 0)) + 1

# ── ЗОНДЫ BIGSTAND: состояния, приказы, расталкивание (одно сравнение bool на событие) ──
static var _state_usec: Dictionary = {}
static var _state_ticks: Dictionary = {}

## [[state, мс на кадр, мкс на тик, тиков], …] — считается от _class_frames
static func state_report() -> Array:
	var rows: Array = []
	var fr: float = float(maxi(_class_frames, 1))
	for st in _state_usec:
		var total: int = int(_state_usec[st])
		var ticks: int = int(_state_ticks.get(st, 1))
		rows.append([int(st), float(total) / 1000.0 / fr, float(total) / float(maxi(ticks, 1)), ticks])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return rows

## Счётчик Unit.command_move: класс бойца, состояние до приказа, источник (метка cmd_src ставится вызывающим; без метки — «other»)
static var cmd_meter: bool = false
static var cmd_src: String = ""
static var _cmd_counts: Dictionary = {}
static var cmd_total: int = 0

## Те же события по отрядам (src|sid → вызовов): виден отряд, которого дёргают каждую секунду
static var _cmd_sids: Dictionary = {}

static func cmd_reset() -> void:
	_cmd_counts.clear()
	_cmd_sids.clear()
	cmd_total = 0

static func cmd_hit(cls: String, st: int, sid: int = -1) -> void:
	cmd_total += 1
	var src: String = cmd_src if cmd_src != "" else "other"
	var key: String = "%s|%s|%d" % [src, cls, st]
	_cmd_counts[key] = int(_cmd_counts.get(key, 0)) + 1
	var k2: String = "%s|%d" % [src, sid]
	_cmd_sids[k2] = int(_cmd_sids.get(k2, 0)) + 1

## [[src, sid, calls], …] по убыванию
static func cmd_sid_report() -> Array:
	var rows: Array = []
	for k in _cmd_sids:
		var p: PackedStringArray = String(k).split("|")
		rows.append([p[0], int(p[1]), int(_cmd_sids[k])])
	rows.sort_custom(func(a, b): return int(a[2]) > int(b[2]))
	return rows

## [[src, cls, state, calls], …] по убыванию
static func cmd_report() -> Array:
	var rows: Array = []
	for k in _cmd_counts:
		var p: PackedStringArray = String(k).split("|")
		rows.append([p[0], p[1], int(p[2]), int(_cmd_counts[k])])
	rows.sort_custom(func(a, b): return int(a[3]) > int(b[3]))
	return rows

## Сколько строк сдвинуло расталкивание (ArmyCore.BatchSeparation) за окно замера — «сколько тел трётся»
static var sep_meter: bool = false
static var sep_moved: int = 0
static var sep_frames: int = 0

static func sep_reset() -> void:
	sep_moved = 0
	sep_frames = 0

static func sep_add(n: int) -> void:
	sep_moved += n
	sep_frames += 1

static func class_max(id: String) -> Array:
	var m: Variant = _class_max.get(id)
	return (m as Array) if m != null else [0, -1]

static func class_frame() -> void:
	_class_frames += 1

## [[id, мс на кадр, мкс на тик, тиков], …] по убыванию мс на кадр
static func class_report() -> Array:
	var rows: Array = []
	var fr: float = float(maxi(_class_frames, 1))
	for id in _class_usec:
		var total: int = int(_class_usec[id])
		var ticks: int = int(_class_ticks.get(id, 1))
		rows.append([String(id), float(total) / 1000.0 / fr, float(total) / float(maxi(ticks, 1)), ticks])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return rows
## Копилки profile_physics: мкс и вызовы по веткам
static var _prof_usec: Dictionary = {}
static var _prof_calls: Dictionary = {}

## Лёгкий счётчик целого физтика армии: одна пара часов НА КАДР — единственное честное время тика
static var tick_meter: bool = false
static var _tick_usec: int = 0
static var _tick_frames: int = 0

static func tick_reset() -> void:
	_tick_usec = 0
	_tick_frames = 0

static func tick_add(usec: int) -> void:
	_tick_usec += usec
	_tick_frames += 1

## Средняя цена одного физического тика армии, мс. -1, если замеров не было
static func tick_ms() -> float:
	if _tick_frames <= 0:
		return -1.0
	return float(_tick_usec) / 1000.0 / float(_tick_frames)

static func tick_frames() -> int:
	return _tick_frames

## Тот же счётчик для КАДРОВОГО (визуального) обхода армии — отдельный бюджет, с физикой не складывать
static var vis_meter: bool = false
static var _vis_usec: int = 0
static var _vis_frames: int = 0

static func vis_reset() -> void:
	_vis_usec = 0
	_vis_frames = 0

static func vis_add(usec: int) -> void:
	_vis_usec += usec
	_vis_frames += 1

static func vis_ms() -> float:
	if _vis_frames <= 0:
		return -1.0
	return float(_vis_usec) / 1000.0 / float(_vis_frames)

# ── ШАРДЫ ТИКА АРМИИ ──
## Делитель частоты тика армии (движок остаётся на 60 Гц); 1 — полная частота. Половинный тик построен и выключен по замеру (пейсинг кадра)
static var army_tick_div: int = 1

static func army_hz() -> float:
	return float(Engine.physics_ticks_per_second) / float(maxi(army_tick_div, 1))

## Автоматическая лестница шардов по численности; false — всегда один шард
static var tick_shards_auto: bool = true
## Границы лестницы (бойцов): до 1-й — 1 шард (60 Гц на бойца), до 2-й — 2, до 3-й — 3, выше — tick_shards_max
static var tick_shard_1_max: int = 800
static var tick_shard_2_max: int = 1200
static var tick_shard_3_max: int = 2200
## Потолок дробления; 4 — 15 опросов в секунду на бойца (5 проверен и не взят: рывок виден)
static var tick_shards_max: int = 4
## Ручное число шардов (0 — считать по армии); стендам для сравнения с дроблением и без
static var tick_shards_force: int = 0

static func shards_for(unit_count: int) -> int:
	if tick_shards_force > 0:
		return tick_shards_force
	if not tick_shards_auto:
		return 1
	var s: int
	if unit_count <= tick_shard_1_max:
		s = 1
	elif unit_count <= tick_shard_2_max:
		s = mini(2, maxi(1, tick_shards_max))
	elif unit_count <= tick_shard_3_max:
		s = mini(3, maxi(1, tick_shards_max))
	else:
		s = maxi(1, tick_shards_max)
	# лестница настроена под 60 Гц: личная частота бойца (15 Гц) и его дельта
	# не зависят от частоты движка — при army_tick_div шарды пересчитываются
	var hz: float = army_hz()
	if hz < 59.0 and s > 1:
		s = maxi(1, int(round(float(s) * hz / 60.0)))
	return s

# ── ТАКТ ПОЗЫ ──
## Такт полного пересчёта позы (Unit.ANIM_EVERY) растягивается с anim_every_base до anim_every_max кадров по численности
static var anim_adaptive: bool = true
static var anim_every_base: int = 3
static var anim_every_max: int = 5
## С какого размера армии такт начинает растягиваться и где достигает предела
static var anim_stretch_from: int = 700
static var anim_stretch_full: int = 2000

static func anim_every_for(unit_count: int) -> int:
	if not anim_adaptive:
		return anim_every_base
	if unit_count <= anim_stretch_from:
		return anim_every_base
	if unit_count >= anim_stretch_full:
		return anim_every_max
	# Плавно между базовым и предельным, чтобы такт не прыгал на границе
	var t: float = float(unit_count - anim_stretch_from) \
		/ float(maxi(anim_stretch_full - anim_stretch_from, 1))
	return anim_every_base + int(round(t * float(anim_every_max - anim_every_base)))

# ── ДВИЖЕНИЕ: МАТРИЦА, ПАКЕТНЫЙ ШАГ, ВИЗУАЛЬНЫЕ ШАРДЫ ──
## Марш отряда одним якорем (боец = якорь + своё смещение); построено и ВЫКЛЮЧЕНО по замеру — условие «коридор чист» почти не выполняется
static var squad_matrix: bool = false
## Отряды меньше этого идут поштучно даже при включённой матрице
static var squad_matrix_min: int = 6

## Геометрия шага (вода, стволы, чужой строй, край, рельеф) — одним проходом ArmySoA.batch_move; false — поштучно, для A/B
static var batch_move: bool = true

## Лишние шарды визуального прохода сверх физических от vis_extra_from бойцов (1 → 2 → 4 утверждены владельцем по A/B)
static var vis_shards_extra: int = 4
## С какого размера армии визуальный проход получает лишние шарды
static var vis_extra_from: int = 2000

## Сколько шардов у ВИЗУАЛЬНОГО прохода при данной армии
static func vis_shards_for(unit_count: int) -> int:
	var s: int = shards_for(unit_count)
	if unit_count >= vis_extra_from:
		s += vis_shards_extra
	return maxi(1, s)

# ── БОЙ В ЯДРЕ ──
## Пакетный проход боя (ArmyCore.BatchCombat); построен и ВЫКЛЮЧЕН по замеру дважды — в рубке дороже, чем экономит
static var batch_combat: bool = false

## Дрёма перезарядки в ядре (Unit._atk_snooze + ArmyCore.TickSnooze); ручка снимает только ВЗВОД, для A/B
static var atk_snooze: bool = true

## Обход скал у хода без маршрута (Unit._nav_dir поверх _atk_waypoint), проверка прямой раз в NAV_RECHECK_SEC
static var nav_detour_move: bool = true
## Фундаменты построек непроходимы (круги в ядре + ячейки сетки); гасит ОБЕ половины правила разом
## ⚠ Выключено по заказу владельца (ТЗ 23.09.2026): проход сквозь здания; qa_building_navigation/qa_building_block красные ожидаемо
static var building_obstacles: bool = false
## Отступ у скал и воды шире, чем у домов (NavCliffExtra), угол нити — дугой (NavSmooth)
static var nav_cliff_arc: bool = true
## Урон наносится на кадре касания ленты удара, а не на замахе
static var melee_hit_delay: bool = true

## Стоящий отряд без чужих в коридоре снимает физтик с бойцов (Unit.sleep_physics)
static var squad_phys_sleep: bool = true
## Чужой под пеленой и не в бою тикает раз в N своих тактов с дельтой × N (ArmyCore.TickRows); 0 — выключено
static var fog_slow_div: int = 6
## Телеметрия партии (TelemetryLogger → user://performance_log_<дата>.json): период, с, и порог FPS для среза по родам войск
static var telemetry: bool = true
static var telemetry_sec: float = 10.0
static var telemetry_spike_fps: float = 30.0
## Стоящий, скрытый туманом, спит по картинке; будит GameManager._wake_returned_far_units
static var fog_sleep: bool = true

# ── КАРТИНКА В ЯДРЕ (BatchVisual, этапы C.1 / E1-E3) ──
## Сглаживание и запись позиций привязанных строк ведёт C#-проход; false — GDScript в tick_visual
static var vis_core_path: bool = true
## Кадр ленты листает ядро (параметры ленты уходят в строку по событию из Unit._set_anim)
static var anim_core: bool = true
## Кольца, тени и полоски здоровья в буферах Rb ядра; GDScript-обход — запасная дорога для бойца без слота
static var decal_core: bool = true
## Полный разбор позы взводят события (состояние, ряд, поворот, камера, цель); расписание — страховка в pose_safety_mult раз реже
static var pose_events: bool = true
static var pose_safety_mult: int = 6
## Полёт стрелы — запись в ядре (ArrowLaunch/BatchArrows), узел только для втыкания и пула; переключается на живой сцене
static var arrow_core: bool = true
## Радиус касания стрелы растёт с личным радиусом тела цели (потолок ×2, ArmyCore.HitBodyMax); у людей 0.35 м
static var arrow_body_hit: bool = true
## Упреждение стрелка по фактической скорости цели (Unit.real_velocity), а не по намерению velocity
static var lead_real_velocity: bool = true
## Память недостижимой точки после сдачи вызволения (Unit.GIVEUP_MEMORY_MS)
static var giveup_memory: bool = true

# ── ПАКЕТНЫЕ ПРОХОДЫ ЯДРА (этапы D1-D3, BigStand-5) ──
## Потоков Parallel.For у расчёта разведения и BatchVisual (результат от числа потоков не зависит); 1 — однопоточно
static var core_threads: int = 3

## Попиксельная часть маски тумана (штампы, «разведано», RGBA) — в C# (ArmyCore.FogRefresh)
static var fog_core: bool = true

## Тыловой напор: пехотинец ранга >= 2 в дерущемся отряде давит к свалке шагом ядра (RearPressPass), без GDScript-тика
static var rear_press: bool = true

## Автопилот подхода к цели в ядре (ArmyCore.AutopilotPass), GDScript-автомат — по расписанию AGGRO_INTERVAL_HOT
static var approach_autopilot: bool = true

## Диспетчер тика идёт по списку строк от ядра (ArmyCore.TickRows); ведомые ядром в GDScript-тик не входят
static var core_tick_list: bool = true

## Коридор отряда и бухгалтерия боя считаются ядром одним вызовом (SquadCorridor / SquadMelee)
static var squad_core_recalc: bool = true
## Стрелковые отряды не участвуют в кольце осады: цель — ровно кликнутое здание
static var ring_skip_ranged: bool = true

## Снаряд без узла: полёт, втыкание и прилёты пачкой — в ядре (ArmyCore.ProjectileFire)
static var projectile_core: bool = true

## GCSettings.LatencyMode = SustainedLowLatency (gen2 только фоном); ставится раз в GameManager._ready
static var gc_low_latency: bool = true
## Тихие строки: привязанная к отрисовке строка не входит в визуальный проход, пока ядро или боец её не разбудят (ArmyCore.VisQuiet)
static var vis_quiet_rows: bool = true
## GDScript-поле Unit._vis_quiet сбрасывается вместе с флагом ядра (иначе тишина утекала)
static var vis_quiet_sync: bool = true
## Удар и смена цели не будят картинку (вспышку и долю жизни пишет ядро); позу метит только зависящая от цели лента
static var vis_wake_lite: bool = true
## Боец вне LOD вправе быть тихим с отложенной позой; поза считается на входе в LOD (seen_now)
static var vis_lod_quiet: bool = true
## Таймер разлёта от тарана — колонка ядра (FlingSet), BatchVisual догоняет без порога телепорта
static var fling_core: bool = true
## Копейщик с направленными листами снимает _flip_dirty в _update_sprite_flip (ворота тишины открыты)
static var vis_dir_flip_clear: bool = true
## Выбор ленты (walk/idle, замок удара, принуждение подкласса, зеркало) и переезд между бакетами ведёт ArmyCore.LookPass
static var look_core: bool = true
## Сроки отрядных проходов — от прошлого срока + TTL, а не от now (после провала кадра не срабатывают одним кадром)
static var phase_keep: bool = true
## Хвост коридора отряда (состав, габариты, стволы, чужие, ряды, предотбор сна) — один вызов ArmyCore.SquadRecalc
static var squad_index_core: bool = true
## Боец в контакте, но вне досягаемости (Unit.ATK_HALF_ZONE), получает GDScript-автомат через тик (7.5 Гц вместо 15)
static var atk_half_contact: bool = true
## Аудит по родам, пакет 1: редкие сканы у туши (BIG_ESCORT_BACKOFF), всадника (RIDER_SWAP_EVERY) и копейщика (PHALANX_ADVANCE_SCAN_MS)
static var audit_pack: bool = true
## Пакет 2: конница в автопилоте до рубежа разгона; построено и ВЫКЛЮЧЕНО по замеру (в шуме — дорог контакт, не подход)
static var rider_autopilot: bool = false
## Причины пробуждений строки / отказов объявить тишину (только при vis_meter); печатает qa_bigstand/VisAb
const VIS_WHY_NAMES := ["прочее", "pose_dirty", "flip_dirty", "_wake_process", "ход↔стоп (_mv_tick)",
	"разворот хода", "смена цели", "удар (анимация)", "смена ряда", "смена состояния",
	"take_damage", "command_move", "command_attack", "wake_for_lod", "стойка/бег", "приказ поста",
	"разворот взгляда (физтик)", "face_towards", "копейщик: ракурс/копьё", "мечник: щит/ярость", "рабочий"]
const VIS_NOQ_NAMES := ["нет core_dmg", "anim_core/mm_all/soa", "мёртв/летит", "pose_dirty",
	"flip_dirty", "dmg_dirty", "нет слота", "уже тихий", "туман без ядра", "не виден и pose_dirty"]
static var vis_why: PackedInt32Array = PackedInt32Array()
static var vis_noq: PackedInt32Array = PackedInt32Array()
## Почему тик бойца в досягаемости цели не ушёл в дрёму (только при tick_meter)
const ATK_WHY_NAMES := ["взвёл дрёму", "остаток ≤ запаса", "разгон", "нет строки", "ждёт залпа"]
static var atk_why: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])

static func vis_why_reset() -> void:
	vis_why.resize(VIS_WHY_NAMES.size()); vis_why.fill(0)
	vis_noq.resize(VIS_NOQ_NAMES.size()); vis_noq.fill(0)
	atk_why.fill(0)


# ── ОТРЯДНЫЕ ТАКТЫ ──
## Сроки коридора и связки боя растягиваются от числа ХОДЯЩИХ бойцов; потолок двойной — тройной задерживал смыкание на 1.5 с
static var squad_ttl_from: int = 2500     ## с какой численности начинается растяжение
static var squad_ttl_max: float = 2.0     ## во сколько раз максимум растягивать

## Множитель отрядных сроков при данном числе ходящих бойцов
static func squad_ttl_scale(active: int) -> float:
	if active <= squad_ttl_from:
		return 1.0
	return clampf(float(active) / float(maxi(squad_ttl_from, 1)), 1.0, squad_ttl_max)

## Линия соприкосновения: тыл подпирает фронт дешёвым шагом без сканов; построено и ВЫКЛЮЧЕНО по замеру (доля дерущихся падает втрое)
static var battle_lines: bool = false

## Нарисованная точка догоняет логическую (Unit._smoothed); false — рисовать по логике, рывками
static var visual_smoothing: bool = true

## Догон картинки отдельным проходом каждый кадр (Unit.tick_draw); построено и ВЫКЛЮЧЕНО по замеру (+6 мс кадра за 7 % рывка)
static var draw_catchup: bool = false

## Бухгалтерия боя на уровне отряда (с кем дерёмся, кто достаёт, подсказка цели); замок игрока выше подсказки
static var squad_melee: bool = true

## Деревня гоблинов в партии; выключают ТОЛЬКО массовые стенды (её угол растягивает сетку соседей)
static var goblin_village: bool = true
## Бойцы набега орды рождаются очередью по horde_spawn_budget в физкадр, а не одним кадром
static var horde_spawn_stagger: bool = true
static var horde_spawn_budget: int = 40
## Удар с разгона у конницы — только первой линией; счётчик Unit.cav_double_hits считает в любом положении
static var cav_front_only: bool = true
## Отрядом конницы решает CavalryCommander (один скан на отряд); false — личная охота каждого всадника каждый кадр
static var cav_commander: bool = true

# ── СВИНОБОСС (ТЗ 28.10.2026; PigBoss.gd, PigBossCommander.gd) ──
## Свинобосс-полководец: покупка отряда после BOSS_FROM_SEC (GoblinAI._new_plan), мозг PigBossCommander; false — не рождается и не командует
static var pig_boss: bool = true
## Аура подавления: чужие в BOSS_AURA_R не получают бонусов штандарта и аур монаха (Unit._suppressed_until_ms)
static var boss_aura: bool = true
## «Варварский клич»: замешательство раз на клич и ×BOSS_SCREECH_FOE_MULT чужим, ×ALLY_MULT своим на BOSS_SCREECH_SEC (PigBoss.screech)
static var boss_screech: bool = true
## Самосохранение: отход при BOSS_WITHDRAW_HP, возврат при BOSS_RETURN_HP с регенерацией в волне (PigBossCommander)
static var boss_withdraw: bool = true
## ТЗ 29.10.2026: клич стал «Гоблинским горном» — своим ×BOSS_HORN_ALLY_ATK_MULT атаки и ×FRAIL входящего урона, чужим ×FOE_ATK, горн и рык отрядов; false — прежний клич (×1.15 / ×0.85)
static var boss_horn: bool = true
## ТЗ 29.10.2026: «Удар Свинобосса» — таран строя копейщиков раз в BOSS_RAM_CD_SEC со свитой в прорыв (PigBoss.ram_*, PigBossCommander._tick_ram); копья и Стена копий его не держат
static var boss_ram: bool = true
## ТЗ 29.10.2026: оружие босса — длина, урон и сектор взмаха туши (STATS["big_goblin"], BIG_SWEEP_*); false — своё (STATS["pig_boss"], BOSS_SWEEP_*)
static var boss_big_weapon: bool = true
## ТЗ 29.10.2026: зонд босса (приказы, горн, таран, отход, сводка hp/свиты) — строки «[ЗОНД boss_…]» и события телеметрии
static var boss_probe: bool = true
## ТЗ 29.10.2026, 2В: ярость при hp <= BOSS_RAGE_HP и исступление при <= BOSS_FRENZY_HP — скорость, темп ударов, рыки, красный накал (PigBoss._tick_rage)
static var boss_rage: bool = true
## ТЗ 29.10.2026, 2В: при hp <= BOSS_FLEE_HP (или после тарана в ярости) босс бросает свиту и бежит на базу, лечится, набирает новую свиту и возвращается (PigBossCommander._tick_flee); false — прежний отход к волне (BOSS_WITHDRAW_HP)
static var boss_flee_base: bool = true
## ТЗ 30.10.2026: отряд босса не усыпляется орой (_sleep_squad), сидящий без волны босс сам ведёт вылазку/встаёт в идущую волну, цели вылазок — брод и золотой рудник (GoblinAI._boss_*, PigBossCommander._tick_idle)
static var boss_sortie: bool = true
## ТЗ 30.10.2026: таран — половина растоптанных выживает с BOSS_RAM_SURVIVE_HP запаса; в беге босс в ядре MOVING (свита его не выталкивает), срок бега BOSS_RAM_RUN_MAX_SEC
static var boss_ram_survive: bool = true
## ТЗ 30.10.2026: после тарана рывки сквозь строй (BOSS_SURGE_*) и выход насквозь — не застревает в копейщиках (PigBoss._tick_surge)
static var boss_surge: bool = true
## ТЗ 29.10.2026: расширенные зонды для .exe — передача знамени и штандарта, отходы отрядов, сводка навигации и зондов раз в минуту
static var probes_ext: bool = true

# ── ATTACK-MOVE И ПРИКАЗЫ ──
## Скан командира [A] по расписанию состояния (бой ~0.9 с, марш ~1.75 с, покой ~3 с, ×0.8-1.2); false — каждые 0.3 с
static var am_adaptive: bool = true

## Приказы командира [A] бойцам — очередью с бюджетом времени на кадр (SquadCommander.ORDER_BUDGET_USEC)
static var am_order_queue: bool = true
## Вызволение застрявшего сбрасывает путь и цель; false — детектор только снимает стволы
static var unstick: bool = true
## Второе вызволение за Unit.UNSTICK_REPEAT_SEC = «цель недостижима», боец встаёт
static var unstick_giveup: bool = true
## Выход из непроходимого на EXIT_PAD за кромку с разносом соседей по касательной (GameManager.passable_exit)
static var unstick_exit_pad: bool = true
## Секунду не продвигается и ближе личного допуска (Unit._stall_arrive_r) к точке — прибыл, а не застрял
static var stall_arrive: bool = true
## Приказ движения отряду в бою ставит выход из боя (Unit._disengaging) каждому бойцу до точки приказа
static var retreat_squad_lock: bool = true
## В стойке «держать» боец отвечает оружию длиннее своего шагом навстречу не дальше Unit.HOLD_OUTREACH_STEP
static var hold_answer_outreach: bool = true
## Несколько отрядов на линии протяжки стоят одной глубины, малый тыл — 2-3 шеренги по середине
static var formation_balanced: bool = true
## Ветка вызволения «cliff» засчитывает стену только в секторе ±60° по ходу (Unit.UNSTICK_AHEAD_COS)
static var unstick_cliff_ahead: bool = true
## Замок продлевает отход отряду в своей очереди (Castle._incoming) всю дорогу; приказ игрока снимает всегда
static var garrison_trip_lock: bool = true
## Перезакладка крепости ИИ не чаще CASTLE_REBUILD_COOLDOWN_SEC и без чужих боевых в CASTLE_REBUILD_SAFE_R
static var castle_rebuild_safe: bool = true

## Худший одиночный вызов ветки profile_physics (среднее прячет пики)
static var _prof_max: Dictionary = {}

static func prof_reset() -> void:
	_prof_usec.clear()
	_prof_calls.clear()
	_prof_max.clear()

static func prof_add(bucket: String, usec: int) -> void:
	_prof_usec[bucket]  = int(_prof_usec.get(bucket, 0)) + usec
	_prof_calls[bucket] = int(_prof_calls.get(bucket, 0)) + 1
	if usec > int(_prof_max.get(bucket, 0)):
		_prof_max[bucket] = usec

## Часы _process подсистем (ИИ, туман, HUD, выделение, Main, GameManager._process); одна проверка bool, когда выключено
static var sys_meter: bool = false
static var _sys_usec: Dictionary = {}
static var _sys_max: Dictionary = {}
static var _sys_n: Dictionary = {}

static func sys_reset() -> void:
	_sys_usec.clear()
	_sys_max.clear()
	_sys_n.clear()

static func sys_add(bucket: String, usec: int) -> void:
	_sys_usec[bucket] = int(_sys_usec.get(bucket, 0)) + usec
	_sys_n[bucket] = int(_sys_n.get(bucket, 0)) + 1
	if usec > int(_sys_max.get(bucket, 0)):
		_sys_max[bucket] = usec

## [[bucket, total_usec, max_usec, calls], ...] по убыванию
static func sys_report() -> Array:
	var rows: Array = []
	for b in _sys_usec:
		rows.append([b, int(_sys_usec[b]), int(_sys_max.get(b, 0)), int(_sys_n.get(b, 0))])
	rows.sort_custom(func(a, c): return int(a[1]) > int(c[1]))
	return rows

## [[bucket, total_usec, calls, avg_usec, max_usec], ...] по убыванию total_usec
static func prof_report() -> Array:
	var rows: Array = []
	for bucket in _prof_usec:
		var total: int = int(_prof_usec[bucket])
		var calls: int = int(_prof_calls.get(bucket, 1))
		rows.append([bucket, total, calls, float(total) / float(maxi(calls, 1)),
			int(_prof_max.get(bucket, 0))])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	return rows

# ── ТЗ ОКТЯБРЯ 2026: ПОВЕДЕНИЕ ОТРЯДОВ И ИНТЕРФЕЙС (все — ручки A/B, false = прежнее поведение) ──
## Силуэт бойца сквозь постройку вторым проходом бакета (mm_unit_ghost); ставится при создании бакета, до старта партии
static var unit_ghost: bool = true

## Дорога атаки строится к центру отряда цели (Unit._atk_leg_goal) — отряд огибает рощу одним боком
static var atk_leg_shared: bool = true
## Поводок бойца игрока без ПКМ-замка: за целью не дальше Unit.CHASE_LEASH от точки старта (из строя — от поста)
static var squad_leash: bool = true
## Отряд в [A] сворачивает только на врага в секторе ±60° по ходу (AM_CONE_COS) или в контакте (AM_SIDE_CONTACT)
static var am_march_cone: bool = true
## Attack-Move сносит чужие постройки по ходу (SquadCommander._scan_building)
static var am_buildings: bool = true
## Монахи в [A] не идут на угрозу: встают за спинами, к пациенту подходят с тыльной стороны
static var monk_rear: bool = true
## Бойцы (не рабочие) в клетке леса-стены или скалы выводятся на проходимое порцией ArmyCore.TrappedRows за кадр
static var trap_sweep: bool = true

## Точка приказа в просвете лесной стены (клетка закрыта, маска стволов свободна) выносится, как со скалы (GameManager.nav_pocket)
static var nav_pocket_out: bool = true

## Перевод огня по приказу: стрелок стреляет не позже QUICK_RETARGET_SEC, остаток перезарядки уходит долгом
static var quick_retarget: bool = true
## Приказ группе: каждый отряд в своей строевой разметке, коробки раздвигаются без наложения (_issue_box_move)
static var squad_boxes: bool = true
## Ctrl+N запоминает взаимное расположение отрядов группы (_group_saved_layout)
static var group_layout: bool = true
## «Яростная атака»: откат на отряд и самозапуск на первом ударе в ближнем бою (GameManager.squad_start_rage)
static var rage_cooldown: bool = true
static var rage_auto: bool = true
## «Фаланга» копейщиков встаёт сама, пока отряд в бою (Spearman._phalanx_auto_threat), без [S]
static var phalanx_auto: bool = true
## Тела светлее и с подтоном своей стороны (CorpseRenderer._set_faction_tint); false — серо-бурый ковёр
static var corpse_faction_tint: bool = true
## Палитра кучи тел (CorpseRenderer.CORPSE_PALETTES): 0 обычная, 1 мох (гибрид), 2 степь (итог); в партии — F7
static var corpse_palette: int = 2
## Тень под кучей тел (CorpseRenderer.CORPSE_SHADOWS): 0 нет … 4 плотная; в партии — F8
static var corpse_shadow: int = 2
## Сочность кучи тел −2…3 (0 — как в палитре); в партии — F9
static var corpse_vivid: int = 0
## Охрана базы красного просыпается от удара по любой постройке в HomeGuard.BASE_ALARM_R от крепости
static var home_guard_buildings: bool = true
## Attack-Move кликом: у каждого отряда своя точка — середина его постов (SquadCommander.attack_move)
static var am_own_dest: bool = true
## Группа Ctrl+N в [A]: центр упёрся — остальные держат фронт строем, а не бегут к угрозе
## ⚠ Менять только по явному ТЗ владельца (разворотов: 1) — выключено 25.10.2026, код оставлен
static var group_line_hold: bool = false
## Глубокий фронт [2]: 2-3 равных эшелона, передний не меньше задних (SelectionManager.deep_row_counts)
## ⚠ Менять только по явному ТЗ владельца (разворотов: 8)
static var deep_even_rows: bool = true
## Воскрешённый встаёт только в рамке живого строя своего отряда, на проходимом (GameManager.raise_spot)
static var raise_in_frame: bool = true
## Запас жизни основных родов войск обеих сторон × TTK_HEALTH_MULT (unit_stats_config.TTK_UNITS)
static var ttk_press: bool = true
## Поздняя орда (после 30-й минуты) плотнее и чаще (spawn_config.LATE_*)
static var goblin_late_surge: bool = true
## Клетка навигации (2 м), закрытая лесом, непроходима целиком для шага, разведения, толчка и предиката (ArmyCore.ForestAt)
static var forest_nav_solid: bool = true
## Свободная клетка, с трёх сторон закрытая лесом, при сборке сетки становится лесом (NavFillForestPockets); читается при сборке
static var forest_pocket_fill: bool = true
## Пехотный толчок × INFANTRY_PRESS_MULT (конницы не касается)
static var infantry_press: bool = true
## Коробка отряда в бою (scripts/army/SquadBox): прямоугольник держит место каждого, бьют два передних ряда
## ⚠ Менять только по явному ТЗ владельца (разворотов: 1) — выключено 25.10.2026; qa_box_front включает сам
static var box_front: bool = false
## Натиск коробки: перевес напора по рядам теснит врагов полосы (SquadBox._press)
static var box_press: bool = true
## Зонды отрядов stuck_running / squad_split / order_override_bug (scripts/army/SquadProbes.gd): строки «[ЗОНД …]» и tm_event
static var squad_probes: bool = true
## Подход к постройке — автопилотом ядра «к точке» (Unit._arm_autopilot_building), а не GDScript-автоматом каждый кадр
static var bld_autopilot: bool = true
## Ручная цель гарнизона крыши держится, пока жива и в RoofGarrison.MANUAL_HOLD_K дальностей; вне — башня ждёт
static var tower_strict_target: bool = true
## ПКМ по земле с выделенными башнями — огонь по ближайшему врагу у точки (TOWER_POINT_PICK_R), а не точка сбора
static var tower_point_fire: bool = true
## ПКМ по врагу во взведённом [A] — прицельная атака этой цели (снимает Attack-Move)
static var am_click_target: bool = true
## Марш по приказу игрока не прерывается ударом сзади (Unit._march_ignores_blow)
static var player_march_hold: bool = true
## Группа Ctrl+N хранит место каждого бойца и ставит на него без раздвижки коробок (_shape_of / _group_saved_shapes)
static var group_shape_lock: bool = true
## Поводок погони — одно решение на отряд (Unit._end_squad_pursuit): сорвал один — отбой всем, кто гонит тот же отряд
static var leash_whole_squad: bool = true
## Подобранная реликвия сливается со знаменем отряда — один флагшток (GameManager.refresh_squad_banner)
static var relic_merge_banner: bool = true
## Пол сближения своих в бою (ArmyCore.SetAllyFloor): не теснее ALLY_FLOOR_OWN к своему отряду / ALLY_FLOOR_CROSS к чужому
static var ally_floor: bool = true
## Рукопашник у тролля/туши идёт к своему месту на кольце (Unit._ring_note), а не по прямой в спины своих
static var giant_ring: bool = true
## Курсор над интерфейсом — палец, боевой вид только над полем (Main._update_hover_cursor)
static var ui_finger_cursor: bool = true
## Оперение курсора-стрелы по досягаемости: зелёное — выделенные стрелки/башни достают до цели, красное — нет (SelectionManager.selection_reaches)
static var arrow_reach_tint: bool = true
## Двойной клик по казарме/стрелковой выделяет все свои постройки того же типа в кадре, как у башен (SelectionManager._select_buildings_on_screen)
static var bld_double_click: bool = true
## Открытое окно кузницы перерисовывается по сигналу GameManager.research_finished: изученный узел зеленеет и следующий из очереди показывает полосу без перезахода (HUD._on_research_finished)
static var forge_live_refresh: bool = true
## Численность выделения тикает вживую по сигналу GameManager.squad_members_changed: бейдж портрета, карточки отрядов, полоса родов, строка «Отрядов» (HUD._refresh_live_counts)
static var hud_live_counts: bool = true
## Засыпающий боец пишет своё состояние в строку ядра (Unit.set_dormant): спящая охрана не числится «бегущей на месте» 40 минут
static var dormant_state_sync: bool = true
## После сдачи вызволения авто-агро GIVEUP_MEMORY_MS не берёт цель, к которой надо идти (Unit._check_auto_aggro): без этого цикл «лес → сдача → новая цель за лесом»
static var giveup_aggro_hold: bool = true
## Переполненный буфер событий телеметрии сначала режет старейшую половину самого частого вида, а не всё подряд (GameManager.tm_event)
static var tm_trim_by_kind: bool = true
## Массовое лечение монаха не включается узлом 2d и не быстрее MONK_MASS_FULL_SEC на отряд (Monk.aoe_active / _care_squad)
static var monk_mass_gate: bool = true

## Засыпающий на ходу сперва встаёт (Unit.set_dormant), иначе застывал в MOVING с лентой ходьбы
static var dormant_halt: bool = true
## Сон стоящего отряда проверяет ЖИВОЕ состояние бойца, а не копию ядра (GameManager._squad_sleep_decide_rows)
static var sleep_live_state: bool = true
## Сплочённость не считает «на посту» бойца, чей пост сам дальше зоны от медианы отряда (GameManager._cohesion_guard)
static var cohesion_post_zone: bool = true
## Смыкание стоящего строя видит разъехавшиеся посты (GameManager._posts_scattered)
static var reform_post_scatter: bool = true
## Боец дальше NAV_LAT_MAX от центра отряда обходит препятствие своей дорогой, а не отрядной (GameManager.squad_leg)
static var straggler_own_leg: bool = true

## Поздние рейды орды каждые 4-5 мин после 30:00 и ступень «после часа» (spawn_config.LATE_RAID_* / HOUR_*)
static var goblin_late_raids: bool = true
## Бездельный отряд волны у базы игрока сносит постройку в GOBLIN_BASE_RAZE_R и не уходит домой, пока есть что сносить (GoblinAI._raze_near_base)
static var goblin_base_raze: bool = true
## Туша бьёт постройку: удар × BIG_BUILDING_DMG_MULT (свип накрывает только бойцов)
static var big_bld_damage: bool = true
## Рейд/штурм бьёт чужого без отряда (монах, одиночка) сам, а не стоит (GoblinFortressAssaultEvent._engage)
static var raid_lone_foe: bool = true
## У башни одна кнопка гарнизона («Выпустить»), кнопки одного размера (HUD.TOWER_BTN_SIZE)
static var tower_one_garrison_btn: bool = true

## Значки «+» и круг ауры каждый кадр идут за НАРИСОВАННОЙ точкой якоря (RelicManager._follow_aura_view); false — логический центр раз в 0.15 с
static var aura_follow_draw: bool = true
## Круги ауры и башни без теста глубины — холм их не режет
static var aura_ring_no_depth: bool = true
## Неполная последняя шеренга строя встаёт по центру (SquadFormation.centred_tail, GameManager._default_block_slots)
static var formation_centred_tail: bool = true
## «Бег на месте» дольше RIP_CURE_MS лечится: новый путь, стоп у цели или пересчёт позы (Unit.cure_run_in_place)
static var run_in_place_cure: bool = true
## Суровая сплочённость: дерущийся дальше COHESION_FIGHT_ZONES зон от отряда бросает бой и возвращается (_cohesion_guard)
static var cohesion_strict: bool = true

## Красный ИИ (ТЗ 27.10.2026, разд. 2 и 4): новобранцы распределяются ЦЕЛЫМИ отрядами реестра, огрызок меньше половины штата вливается в неполную группу рядом (EnemyAI._regroup)
static var ai_regroup_whole: bool = true
## Отряд ниже RETREAT_REFILL_STRENGTH без противника рядом идёт в замок лечиться и пополняться (EnemyAI._try_retreat)
static var ai_refill_home: bool = true
## Штурм красного — с ASSAULT_READY_FRACTION суммарного лимита отрядов, а не «все рода до последнего» (EnemyAI.army_ready)
static var ai_assault_fraction: bool = true
## Отряд волны, ушедший вперёд центра дальше WAVE_LEAD_MAX и не в бою, ждёт остальных (EnemyAI._command_squads)
static var ai_wave_hold: bool = true
## Места отрядов одного рода в волне красного разводятся по фронту не теснее шага ряда — при 6-8 отрядах рода фланговый сдвиг тактики клал соседей друг на друга (EnemyAI._despread_plan)
static var ai_wave_despread: bool = true
## Охрана крепости засыпает, только когда КАЖДЫЙ боец у своего места поста (HOME_GUARD_GATHER_R), отставшим — приказ на место; иначе по центру и спящие кучи в 15 м (HomeGuard._process_timed)
static var guard_sleep_gathered: bool = true
## Отряд реестра, в котором ещё никого не было (full == 0), геттер squad_members не распускает: бараки заводят запись до спавна, и такт ИИ между ними оставлял всю партию без отряда (GameManager.squad_members)
static var squad_keep_unborn: bool = true
## Разбор партии 29.10.2026: монах не поднимает павшего в отряд, у которого живых уже штат (squad_has_room) — крепость пополняла до 60, монахи добавляли тела с поля, отряд выходил 67-72 из 60
static var raise_squad_cap: bool = true
## ТЗ 29.10.2026: вектор бегства в панике — прочь от врагов вокруг отряда (скан сетки), без врагов — к своей крепости/хижине; false — прежний кэш курса копейщиков и «от центра карты» (гоблины у базы игрока бежали вперёд сквозь строй)
static var panic_away_enemy: bool = true

## Кузница гоблинов (ТЗ 28.10.2026): вожак орды копит дерево/золото, закладывает кузницу и заказывает исследования (GoblinForgeAI); false — орда кузницу не строит (само здание и древо работают)
static var goblin_forge: bool = true

## [A] из стойки ЗАЩИТА (ТЗ 28.10.2026, пятое письмо): прежняя стойка отряда хранится в записи режима и возвращается при снятии [A] — прибытие или любой приказ игрока (SquadCommander._register_am / cancel_squad); false — отряд остаётся в «атаке», как прежде
static var am_stance_restore: bool = true

## Группа [A] идёт одной дорогой: нить A* строится от центра ГРУППЫ клика к точке, у отряда своя только последняя точка (GameManager.squad_leg, am_group_of/am_group_centre); false — дорога на каждый отряд от его центра (фланги уходили в разные проходы стены)
static var am_group_route: bool = true

## Стрелки под [A] не получают приказ атаки по цели за дальностью: отряд подходит на 0.8 дальности строем (SquadCommander._tick_squad, ветка прямого скана); false — приказ атаки сразу, цель за дальностью стрелок бросал и замирал
static var am_archer_standoff: bool = true

## Курсор режима [A]: стрела, когда выделены одни стрелки (SelectionManager._apply_attack_cursor); false — всегда скрещённые мечи
static var am_ranged_cursor: bool = true

## Валидатор прибытия отряда (ТЗ 28.10.2026, вечер): доля отряда в 1 м от своих ячеек → отряд прибыл, упёршийся в тела в допуске встаёт в покой одним проходом, без таймеров (GameManager.squad_note_zone, Unit.settle_in_zone)
static var squad_arrive_validate: bool = true
## ТЗ 29.10.2026, п. 3: паникующий проходит сквозь тела и не перехватывается
static var panic_pass: bool = true
## ТЗ 29.10.2026, п. 5: натиск фаланги — отрядные синхронные рывки в замесе
static var phalanx_shove: bool = true
## ТЗ 29.10.2026, п. 4: [A] — запомненный враг проходит сектор марша, бегущий
## в панике не разворачивает отряд (откат за остатком волны)
static var am_cone_memory: bool = true
## ТЗ 30.10.2026 (скриншот 01:29): пара раскладки фронта (front_pairs) берётся, только если она рядом с найденным врагом или не дальше его и в секторе марша; иначе — отряд самого врага (крайние отряды уходили к дальней волне сбоку)
static var am_front_guard: bool = true
## Опыт держит строй: жребий паники × (1 − vet_panic_resist(ранг)) (ТЗ 30.10.2026)
static var vet_panic_resist: bool = true
## Легенда при половине штата уходит в крепость восстановиться (ТЗ 30.10.2026)
static var legend_retreat: bool = true
## Знамя Свинобосса за спиной, а не в точке тела (ТЗ 30.10.2026)
static var boss_banner_back: bool = true
## Окно «Красный игрок разбит» с «Продолжить», пока орда жива (ТЗ 30.10.2026)
static var red_defeat_modal: bool = true
## ── ТЗ 30.10.2026, интерфейс и карта ──
## Мягкая тень у основания построек
static var building_shadow: bool = true
## Плотная куча золота (GOLD_LAYOUTS) вместо общих шаблонов куч
static var gold_dense_heap: bool = true
## Ступенчатая разблокировка построек рабочего: крепость → овцеферма → дом/склад → всё
static var build_unlock: bool = true
## Овцеферма игрока строится рабочими (площадка), а не встаёт сразу
static var pen_construct: bool = true
## Панель рабочего сеткой в три колонки, без подписи
static var worker_grid_panel: bool = true
## Панель армии: без строки «Отрядов: N — M», на портрете число отрядов
static var army_count_badge: bool = true
## Рабочие в смешанном выделении — своя группа в полосе родов
static var mixed_worker_group: bool = true
## Экономика красного v2: рынок, загоны, склады, кузница вне очереди строек (ТЗ 30.10.2026)
static var ai_eco_v2: bool = true
## Красный ИИ: перегруппировка после боя, корпус по сигналу, клещи штурма, опорные точки (ТЗ 30.10.2026)
static var ai_regroup: bool = true
static var ai_corps: bool = true
static var ai_pincer: bool = true
static var ai_strongpoint: bool = true
## ТЗ 29.10.2026: замок цели игрока после истребления отряда-цели переходит на соседний вражеский отряд
static var lock_chain_squad: bool = true
## ТЗ 29.10.2026, знамёна: штандарт за общий опыт — свойство отряда (ранг не поднимает, один на отряд,
## дальше улучшение до STANDARD_MAX_LEVEL, носитель передаёт соседу), бордовый поверх золота легенды
static var standard_squad: bool = true
## ТЗ 29.10.2026: у орды престиж легенды — шевроны на рваном штандарте (знак без прибавок)
static var goblin_legend_marks: bool = true
## Шаг на последнем отрезке не длиннее остатка пути до точки приказа (перелёт при редком такте, 29.10.2026)
static var step_clamp: bool = true

## Монахи одного отряда без узлов массового лечения делят ОДНОГО пациента (Monk._care_squad): отряд монахов лечит по одному, а не по бойцу на монаха; false — каждый монах ведёт своего
static var monk_squad_focus: bool = true

## Большая армия ест дороже (ТЗ 28.10.2026, блок 2): сверх unit_stats_config.FOOD_UPKEEP_BIG_ARMY_HEADS голов ставка на голову растёт (food_upkeep_mult, GameManager._sweep_food, economy_model); false — линейно, как прежде
static var food_big_army: bool = true
## Ветка «выход мяса» кузницы (bonus_meat_pct) растит кусок за ходку фермера (Worker.meat_yield_mult); false — узлы изучаются, но кусок базовый
static var meat_yield_bonus: bool = true
## Узлы «темп исследований» (bonus_research_pct) ускоряют таймер Кузницы на всех вкладках (Smithy.research_speed_mult); false — секунда за секунду
static var forge_research_speed: bool = true

## «Последний выживший» (узел 3c пехоты, ТЗ 28.10.2026): последний боец выбитого отряда с шансом LAST_STAND_CHANCE уцелевает призраком — чужие его не видят, он уходит в крепость лечиться и выходит с отрядом, пополненным до штата (Unit._try_last_stand, ArmyCore.FGhost); false — последний гибнет всегда
static var last_stand: bool = true

## Сток эндгейма кузницы (ТЗ 28.10.2026, п. 2): ряды 3-5 дороже в forge_config.ROW_SINK_MULT раз по весам SINK_RES_WEIGHT; false — прежние цены рядов
static var forge_endgame_sink: bool = true

## ТЗ 31.10.2026: под ручным замком игрока поводок погони меряется от точки ПРИКАЗА (Unit.LOCK_CHASE_MAX), а «цель ушла из виду» замок не снимает, пока цель в этом радиусе; false — прежние 7 м от касания и порог _lock_sight_range
static var lock_chase: bool = true
## ТЗ 31.10.2026: Свинобосс в бегстве пробивает строй — чужие на пути к базе → рывок насквозь курсом бегства (PigBoss._tick_flee_break), между рывками тело идёт сквозь тела; false — бегство обычным ходом
static var boss_flee_break: bool = true
## ТЗ 31.10.2026 (армия в [A] идёт назад): пока отряд в [A] не дошёл, смыкание рядов (squad_close_ranks из выхода из боя, потерь и обхода _sweep_reform) его не трогает — строй собирает марш командира к местам у точки (_march_to_slots); иначе смыкание центрировало разметку по месту стычки и передние шли назад; false — прежнее
static var am_no_reform: bool = true
## ТЗ 31.10.2026: монахи одного отряда не расходятся друг от друга (Monk._tick_spacing) — их держит строй отряда; расстановка спорила со смыканием, монахи ходили туда-обратно; false — прежнее
static var monk_spacing_own_squad: bool = true
## ТЗ 31.10.2026: [A] — надстройка над стойкой: отряд в «Защите» идёт с боем, НЕ переходя в «Атаку» (SquadCommander._drop_defense), бьёт встреченного фалангой — прямым приказом с переносом стены (как клик по ближнему отряду), по прибытии стоит в «Защите»; false — на марш [A] «Защита» снимается и возвращается по прибытии (28.10)
static var am_keep_defense: bool = true
## ТЗ 31.10.2026: места строя раздаются ПО РЯДАМ (SquadFormation.rank_pairs: передние по курсу — в передние шеренги, в шеренге по порядку поперёк курса) — в смыкании и в марше [A] к местам у точки; false — жадно «место по порядку → ближайший» (крест-накрест, бойцы шли назад сквозь своих)
static var rank_match: bool = true
## ТЗ 31.10.2026: смыкание после боя ставит переднюю шеренгу у передних бойцов по курсу (GameManager._slots_recentered, REFORM_FRONT_Q), хвост подтягивается вперёд; false — разметка по центру масс, передние идут назад
static var reform_front_anchor: bool = true
## ТЗ 31.10.2026: обрыв поводка погони отряда игрока (Unit._leash_check) — к своему отряду: пост рядом с центром отряда — на пост, гнался весь отряд — встать на месте, строй собирает смыкание по месту; false — возврат к якорю/посту (ход назад через поле)
static var leash_hold_here: bool = true
## ТЗ 31.10.2026 (вечер, «догнал, уничтожил — собрался в строй»): пост, поставленный концом боя «где стою» (Unit._hold_loose: цель выбита/ушла, поводок, тупик), — «не в строю»; обход _sweep_reform смыкает такой отряд по месту, отряд без разметки получает её; false — пост «где стою» считался строем, разбросанные стояли
static var idle_form_up: bool = true
## ТЗ 31.10.2026 (знамёна по сторонам): знамя красного ИИ — красное поле с теми же лычками (BannerArt.side_of), знамя Свинобосса — зелёные язычки орды; false — все люди под синим, босс под синей шкалой
static var faction_banners: bool = true
## ТЗ 31.10.2026: клик по знамени над отрядом выбирает отряд (SelectionManager._banner_squad_at) — свой выделяется, чужой открывает разведку; false — знамя не кликается
static var banner_click: bool = true
## ТЗ 31.10.2026: овцеферма — клик по своей овце открывает её ферму, без выделения наведение на построенную ферму даёт палец и мягкую подсветку (Building.set_hover_glow); false — клик по овце выделяет овцу, наведения нет
static var pen_hover: bool = true
## ТЗ 31.10.2026: рабочие по своему золотому руднику — курсор кирка, рудник мигает (flash_accept), реплика «Go/Come on» (AudioManager «worker_gold»); false — палец и без отклика
static var mine_confirm: bool = true
## ТЗ 31.10.2026: орда входит на карту из-за кромки вне обзора игрока и маршем идёт к точке спавна
static var horde_edge_entry: bool = true
## ТЗ 31.10.2026: задний ряд без врага в длине оружия не обтекает своего впереди ближе ALLY_QUEUE_GAP — ждёт очереди
static var ally_queue: bool = true
## ТЗ 31.10.2026: ряды за спиной бойца прибавляют напор толчка (и упор у толкаемого)
static var rank_push: bool = false
## ТЗ 31.10.2026: пол сближения атакующих со своими 0.48 м (почти строевой шаг) вместо 0.333 — армии не сжимаются в кисель на подходе
static var ally_floor_wide: bool = true
## ТЗ 31.10.2026: волна орды идёт привалами (выход с базы, подступ к броду, за бродом) — сбор, строй, скан передовых (WaveMarch)
static var wave_stages: bool = true
## ТЗ 31.10.2026: собравшийся на привале отряд спит до следующего этапа (удар будит)
static var wave_halt_sleep: bool = true
## ТЗ 31.10.2026: застрявшие и не собравшиеся на привале — строкой «[ВОЛНА …]» в лог и tm_event
static var wave_march_log: bool = true
## ТЗ 31.10.2026: волна вступает в бой дозами — 1-2 отряда на чужой отряд от центра, резерв, фланг, замена просевших, конница в брешь (WaveFeed)
static var wave_feed: bool = true
## ── ПНИ (ТЗ 31.10.2026, scripts/goblin/LairDirector.gd) ──
## Левобережный пень — в секцию у кромки, за ним золото и камень; зеркальный пень на правом берегу
static var lair_layout_v2: bool = true
## Охрана пня ×3: стражи, стартовая стая, потолки гноллов
static var lair_guard_x3: bool = true
## Гноллы и тролли пня выходят из самого пня, а не из-за кромки
static var lair_spawn_at_lair: bool = true
## Правобережные пни шлют к броду 3 тролля и 3 отряда гноллов (раз в 7 / 10 мин) держать пятак
static var lair_ford_sorties: bool = true
## Снесённый игроком пень: «дзынь», слиток «+5000» над пнём, камера к пню, золото на счёт
static var lair_reward: bool = true
## Пень оживает через 30 мин: внутри 7 троллей и 20 отрядов гноллов, вываливаются по одному в секунду при ударе
static var lair_revive: bool = true
## Гноллы не отступают: ни отхода после броска, ни кайта, ни бегства в пень
static var gnoll_no_retreat: bool = true
## ── МЕЧНИКИ И «ВОЛЬНО» (ТЗ 31.10.2026, второе письмо) ──
## Щит мечника не поднят постоянно: только под обстрелом (стрелы и кости гноллов −70 %),
## в стойке «Защита» и на последних метрах рывка
static var warrior_shield_dynamic: bool = true
## В рукопашной мечник между ударами под щитом (−50 %), после серии ударов открыт
static var warrior_melee_guard: bool = true
## «Стена щитов» в «Защите»: −80 % и стрел, и стали, удары втрое реже
static var warrior_shield_wall: bool = true
## «Стена щитов» смыкает ряды: разметка мечников в «Защите» сжимается к передней
## шеренге до WALL_SPACING/WALL_DEPTH, выход из «Защиты» разжимает обратно
static var warrior_wall_tight: bool = true
## ── ТОЛЧОК МАССОЙ (ТЗ 31.10.2026, «главная мысль») ──
## Толчок по отряду × соотношение сил вокруг него (отряды чужой стороны против
## своих в MASS_R, каждый с весом живые/штат): кулак сносит одиночку, 1 на 1 —
## паритет, строй в три отряда вглубь конница не сдвинет
static var mass_push: bool = true
## Первые MASS_IMPACT_SEC контакта отряда толчок сильнее (удар с разгона)
static var mass_impact: bool = true
## ── ПЛОТНОСТЬ ОРДЫ (ТЗ 31.10.2026, «главная мысль») ──
## Толпа орды плотнее (HORDE_DENSE_SPREAD вместо HORDE_SPREAD), туши — шире
## (BIG_WIDE_MULT к шагу их толпы)
static var horde_dense: bool = true
## Волна штурма красного ИИ идёт привалами (выход, подступ к броду, за бродом)
## всем боевым порядком и ждёт отставших (scripts/ai/RedMarch.gd)
static var ai_wave_stages: bool = true
## Свинобосс синхронно с дозами: вскрывает оборону — бьёт центральный чужой
## отряд (до BOSS_OPEN_MAX подряд), дозы идут туда же; пока идёт подача, его
## мозг не перехватывает отряды волны
static var boss_wave_sync: bool = true
## Поход пня к броду идёт привалом: тролли и гноллы сперва собираются у
## подступа к броду (LairDirector, числа HALT_* общие с ордой), ждут всех, затем
## на пятак; чужие ближе CONTACT_R — привал снят
static var lair_sortie_march: bool = true
## Подтягивание задних рядов в бою ведёт ядро арендой (Unit._arm_pullup):
## без стража «чужой рядом», с поводком по бойцу, до выхода цели из окна
static var pullup_core: bool = true
## Пробег разгона конницы копит ядро на время аренды подтягивания: всадник в
## разгоне и с потраченным натиском не входит в автомат каждый такт
static var charge_core: bool = true
## Страж «чужой рядом» у автопилота подхода — раз в 20 физтактов (3 Гц)
## вместо 12 (5 Гц); подтягивание (pullup_core) стража не имеет вовсе
static var guard_3hz: bool = true
## Марш идущих (MOVING) ведёт ядро арендой (Unit._arm_march): GDScript-автомат
## входит у угла маршрута, у конца пути, по упору, стражу и ближайшему таймеру
static var march_core: bool = true
## Смыкание рядов (squad_close_ranks) не трогает СПЯЩИЙ отряд: command_move спящему ставил MOVING при снятом тике — бег на месте до пробуждения (зонд qa_crash1101/Dorm: 220-1094 бойцов)
static var reform_skip_dormant: bool = true
## «Вольно» ([C]): копейщики и мечники агрятся ОТРЯДОМ на отряд, а не поодиночке
static var ease_squad_engage: bool = true
## Рывок перед столкновением: за EASE_RUSH_DIST до цели шаг ×EASE_RUSH_MULT
static var ease_rush: bool = true
## Столкновение рывком на 1.5 с ускоряет звуки боя (pitch)
static var clash_audio_boost: bool = true
## ТЗ 31.10.2026: уведомления «Лагерь орды уничтожен» нет
static var horde_defeat_notice: bool = false
