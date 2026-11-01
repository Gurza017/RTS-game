extends RefCounted
## Поведение орды: деревня, расписание, тролли и пни, гноллы, овцы, туши, резерв. Без class_name — через preload().
## Сила и запас бойцов — unit_stats_config.STATS; спавн и тайминги — spawn_config.gd (здесь переэкспорт через _Spawn).
## Заметки, история чисел и разворотов — docs/config_notes/goblin_config.md
const _Spawn := preload("res://scripts/spawn_config.gd")

# ── СОСТАВ И СТРОЙ ОТРЯДА ──
## Уставной размер отряда по роду (из spawn_config)
const SQUAD_SIZE := _Spawn.GOBLIN_SQUAD_SIZE
## Колонок в строю при выходе из хижины, по роду
const SQUAD_COLS := {
	"goblin_spearman": 10,
	"goblin_rider":    8,
	"gnoll":           4,
	"big_goblin":      3,
}
## Шаг строя при выходе из хижины, м (растянут вместе с SIZE_SCALE)
const SQUAD_SPACING := 0.65

## Состав полной орды (по нему вожак донанимает до штата) — выводится из START_SQUADS, второго списка нет
static func army_composition() -> Array:
	var out: Array = []
	for row in START_SQUADS:
		out.append(String((row as Dictionary).get("unit", "")))
	return out

## Полная численность орды в отрядах = длина START_SQUADS
static func army_squads() -> int:
	return START_SQUADS.size()

# ── ЦЕНА И ВРЕМЯ НАЙМА ──

# ── ДЕРЕВНЯ ──
## Хижин в деревне
const HUTS := 10
## Еды в минуту с одной хижины и такт начисления, с
const HUT_FOOD_PER_MIN := 100.0
const HUT_TICK_SEC := 10.0
## Сетка хижин: шаг, м; хижин по рядам; сдвиг чётных рядов в долях шага («шахматка»)
const HUT_STEP := 6.0
const HUT_ROWS := [4, 3, 3]
const HUT_ROW_OFFSET := 0.5
## Радиус, в который укладывается вся деревня, м (обороне и стенду)
const VILLAGE_RADIUS := 16.0
## Дым из трубы: кадров в секунду (лента Goblin Hut.png — 12 кадров)
const HUT_SMOKE_FPS := 7.0
## Центр деревни: доли полукарты по X/Z (правый верхний угол = +X / −Z)
const VILLAGE_ANCHOR := Vector2(0.72, -0.72)

# ── ВНЕШНИЙ ВИД ──
## Размер пикселя спрайта гоблина, м (= 0.0085 × SIZE_SCALE); менять только вместе с SIZE_SCALE
const PIXEL_SIZE := 0.012282
## Во сколько раз гоблин крупнее наброска: от него выведены PIXEL_SIZE, HORDE_SPOT, SQUAD_SPACING и радиус расталкивания
const SIZE_SCALE := 1.445

# ── ТРОЛЛЬ: РАЗМЕР И ДУБИНА ──
## Размер пикселя спрайта тролля, м
const TROLL_PIXEL_SIZE := 0.0261
## Порог альфы для поиска ступней в кадре (Unit._anim_bottom_px): отсекает тень, впечатанную в арт
const TROLL_FOOT_ALPHA := 0.5
## Во сколько раз шире пехотинца личный круг тролля (Unit.sep_radius)
const TROLL_SIZE_SCALE := 3.4
## Ударов дубиной в серии до одышки и длительность одышки, с (лента Recovery)
const TROLL_SWINGS := 3
const TROLL_REST_SEC := 2.75
const TROLL_SPLASH_FRAC := 0.6

# ── ГНОЛЛ: СПРАЙТ И БРОСОК КОСТИ ──
## Размер пикселя гнолла, м (кадр 192×192, как у людей)
const GNOLL_PIXEL_SIZE := 0.0125
## Высота вылета кости над землёй, м (от плеча, не от ступней)
const GNOLL_THROW_Y := 1.05
## Скорость кости, м/с
const GNOLL_BONE_SPEED := 7.0
## Подъём дуги в долях дальности (бросок от руки — почти прямой)
const GNOLL_BONE_ARC := 0.18
## Длина упакованной оси = признак «кручусь» для mm_arrow.gdshader (летит — крутится, воткнулась — нет)
const GNOLL_BONE_AXIS_K := 0.4
## Оборотов в секунду у летящей кости
const GNOLL_BONE_SPIN := 2.2
## Кадр ленты Gnoll_Throw (8 кадров), на котором кость вылетает
const GNOLL_THROW_FRAME := 4
## Разброс обычного броска, м; доля явных промахов и их разброс, м (кость в землю рядом)
const GNOLL_SCATTER := 1.5
const GNOLL_MISS_CHANCE := 0.3
const GNOLL_MISS_SPREAD := 3.2

# ── ГНОЛЛ: КАЙТ ──
## Пехота ближе KITE_IN м — отбежать на KITE_OUT м, не чаще раза в KITE_SEC с
const GNOLL_KITE_IN := 6.0
const GNOLL_KITE_OUT := 9.0
const GNOLL_KITE_SEC := 1.1
## Враг с attack_range не больше этого, м, считается ближним боем (от стрелков не кайтим)
const GNOLL_MELEE_RANGE_MAX := 5.0
## Кайт глушится, если за GIVEUP с не сдвинулся дальше MIN_GAIN м: BLOCK_SEC с гнолл стоит и метает
const GNOLL_KITE_GIVEUP := 1.0
const GNOLL_KITE_MIN_GAIN := 0.8
const GNOLL_KITE_BLOCK_SEC := 4.0

# ── ГНОЛЛ: ПАТРУЛЬ, ПОВОДОК, ОБОРОНА ПНЯ ──
## Радиус патруля вокруг пня, м, и период смены точки, с
const GNOLL_PATROL_RADIUS := 26.0
const GNOLL_PATROL_SEC := 7.0
## Поводок инициативы (Unit.aggro_leash), м: ближе — берёт цель сам
const GNOLL_AGGRO_LEASH := 10.0
## Дальность броска, м (attack_range гнолла срезается до неё ради видимой дуги)
const GNOLL_THROW_RANGE := 8.5
## Оборона пня: враг ближе этого, м — гнолл встаёт сбоку от линии «пень → враг»
const GNOLL_DEFEND_RANGE := 34.0
const GNOLL_FLANK_SIDE := 13.0           # в сторону от линии, м
const GNOLL_FLANK_BACK := 8.0            # назад от врага, м
const GNOLL_FLANK_SEC := 4.0             # не чаще раза в столько с
## Повтор скана после промаха (никого не найдено), с: фланг и кайт; фазы бойцов разнесены по номеру узла
const GNOLL_FLANK_MISS_SEC := 2.0
const GNOLL_KITE_MISS_SEC := 0.3
const GNOLL_SCAN_PHASES := 17

# ── ГНОЛЛ: ПОД УРОНОМ И СПАВН ──
## Метнул — отходит на столько м к пню
const GNOLL_RUN_BACK := 5.0
## Ниже этой доли запаса бежит прятаться в пень (как гарнизон): вход с этого расстояния, м; лечение, доля запаса в секунду
const GNOLL_HIDE_HP := 0.45
const GNOLL_HIDE_RANGE := 4.5
const GNOLL_HIDE_HEAL_FRAC := 0.12
## Стартовая стая на пень (из spawn_config)
const GNOLL_START_SQUADS := _Spawn.GNOLL_START_SQUADS
## Спавн по часам: период, с; отрядов за раз (мин/макс); перепроверка места, с; потолок отрядов от всех пней (из spawn_config)
const GNOLL_SPAWN_SEC := _Spawn.GNOLL_SPAWN_SEC
const GNOLL_SPAWN_MIN := _Spawn.GNOLL_SPAWN_MIN
const GNOLL_SPAWN_MAX := _Spawn.GNOLL_SPAWN_MAX
const GNOLL_SPAWN_RECHECK_SEC := _Spawn.GNOLL_SPAWN_RECHECK_SEC
const MAX_STUMP_GNOLLS := _Spawn.MAX_STUMP_GNOLLS
## Прежние волны по удару по пню — ручки отката (из spawn_config)
const GNOLL_WAVE_SQUADS := _Spawn.GNOLL_WAVE_SQUADS
const GNOLL_WAVE_SEC := _Spawn.GNOLL_WAVE_SEC
const GNOLL_WAVES_MAX := _Spawn.GNOLL_WAVES_MAX
const GNOLL_COOLDOWN_SEC := _Spawn.GNOLL_COOLDOWN_SEC
## Потолок живых гноллов на пень (из spawn_config)
const GNOLL_MAX_ALIVE := _Spawn.GNOLL_MAX_ALIVE

# ── ТРОЛЛЬ: ПАТРУЛЬ, ТАРАН И ДУБИНА ──
## Патруль: радиус кольца вокруг логова, м, и период смены точки, с
const TROLL_PATROL_RADIUS := 23.4
const TROLL_PATROL_SEC := 9.0
## Топтание с разгона: сколько бойцов перед троллем гибнет на месте
const TROLL_TRAMPLE_COUNT := 3
## Дубина бьёт дугой перед спрайтом: не больше стольких бойцов за удар
const TROLL_SWEEP_COUNT := 6
const TROLL_SWEEP_ARC_COS := 0.5         # косинус полуугла сектора (±60°)
const TROLL_SWEEP_REACH_PAD := 0.8       # не дальше attack_range + столько м
## Накрытые отлетают на столько м и лежат сбитыми столько с
const TROLL_SWEEP_KNOCKBACK := 2.6
const TROLL_KNOCKDOWN_SEC := 2.5
## Сила вспышки попадания (общая Unit.HIT_FLASH_PEAK 0.85 держала бы тушу засвеченной)
const TROLL_FLASH_PEAK := 0.07
## Процедурные пятна крови (mm_unit_sprite.blood_spots); 0 — выключены, остаётся подкраска по доле запаса
const TROLL_BLOOD_SPOTS := 0.0
## Доля запаса, на которой логово выпускает подмогу, и её численность (из spawn_config)
const TROLL_REINFORCE_AT := 0.35
const TROLL_REINFORCE_COUNT := _Spawn.TROLL_REINFORCE_COUNT
## Агро-цепочка логова: помощников по первому удару и бонусная группа после их гибели (0 — снято; из spawn_config)
const TROLL_AGGRO_HELPERS := _Spawn.TROLL_AGGRO_HELPERS
const TROLL_AGGRO_BONUS := _Spawn.TROLL_AGGRO_BONUS
## Окно солидарности, с: второй страж задет в окне — все тролли логова идут на обидчика
const TROLL_SOLIDARITY_SEC := 10.0
## Радиус агро, м; погоня без удара дольше этого, с — цель брошена; множитель скорости в бою
const TROLL_AGGRO_RADIUS := 12.0
const TROLL_CHASE_SEC := 10.0
const TROLL_COMBAT_SPEED_MULT := 1.2
## Вероятность клича за убийство (жребий из AudioManager.rng)
const TROLL_VICTORY_CHANCE := 0.34

# ── ТРОЛЛЬ: КЛИК, КОЛЬЦО, ПРИЦЕЛ ──
## Зона клика: половина высоты рисунка, м, и круг у ног, м
const TROLL_PICK_BODY_H := 2.55
const TROLL_PICK_RADIUS := 1.45
## Кольцо выделения и тень — во столько раз крупнее пехотного (Unit.ring_scale)
const TROLL_RING_SCALE := 3.57
## Овал кольца: растяжение по осям поверх TROLL_RING_SCALE (тени под троллем нет)
const TROLL_RING_OVAL := Vector2(1.45, 0.9)
## Радиус тонкого красного обвода, м (64-сегментный меш, как у здания; мимо RING_SCALE)
const TROLL_FINE_RING_R := 1.32
## Куда целится стрелок: центр массы туши над землёй, м
const TROLL_AIM_HEIGHT := 2.3
## Доля стрел, намеренно уходящих в землю рядом с тушей, и их разброс, м
const TROLL_AIM_MISS_CHANCE := 0.22
const TROLL_AIM_MISS_SPREAD := 2.4
## Окружение: столько чужих в пределах дубины — кольцо; раз в SHOVE_SEC с расталкивает всех на SHOVE_PUSH м
const TROLL_SURROUND_FOES := 4
const TROLL_SHOVE_SEC := 0.6
const TROLL_SHOVE_PUSH := 0.55
## Разброс угла падения туши, градусы (в обе стороны от вертикали)
const TROLL_DEATH_TILT := 34.0
## Цена смерти тролля нападавшим, в убийствах (три полных отряда копейщиков)
const TROLL_KILL_WORTH := 180

## Касание дубины — доля длины ленты удара (урон и разлёт списываются отложенно)
const TROLL_SWING_HIT_SEC := 0.3
## Множитель урона дубины по всем накрытым (и цели, и дуге)
const TROLL_SWEEP_DMG_MULT := 1.2
## Продвижение к цели на каждый удар серии, м
const TROLL_SWING_STEP := 0.6
## Подкраска туши на смерти (краснеет)
const TROLL_DEATH_TINT := Color(1.0, 0.55, 0.55)

# ── ЛОГОВО (ПЕНЬ): СТРАЖИ, РИСУНОК, ГЛУШЬ ──
## Стражи восполняются раз в столько секунд до потолка, пока пень жив (из spawn_config)
const TROLL_RESPAWN_SEC := _Spawn.TROLL_RESPAWN_SEC
const TROLL_GUARDS_MAX := _Spawn.TROLL_GUARDS_MAX
## Волна защиты пня: троллей сверх охраны и её откат, с (из spawn_config)
const TROLL_DEFENSE_WAVE := _Spawn.TROLL_DEFENSE_WAVE
const TROLL_DEFENSE_WAVE_CD := _Spawn.TROLL_DEFENSE_WAVE_CD
## Прицел стрелка по пню: центр пня над землёй, м
const TROLL_LAIR_AIM_HEIGHT := 1.8
## Стрела, долетевшая до здания, не торчит, а растворяется за столько секунд
const ARROW_BUILDING_FADE := 0.6
## Цвет вспышки удара у тролля (общая вспышка — белая)
const TROLL_FLASH_COLOR := Color(1.0, 0.22, 0.18)
## Овал кольца пня: растяжение по осям и сдвиг центра в долях радиуса (+ к камере, − от неё; TrollLair.ring_center)
## ⚠ Менять только по явному ТЗ владельца (разворотов: 3)
const TROLL_LAIR_RING_OVAL := Vector2(1.35, 0.80)
const TROLL_LAIR_RING_SHIFT := -0.30
## Стартовых стражей у пня (из spawn_config)
const LAIR_START_TROLLS := _Spawn.LAIR_START_TROLLS
## Декор логова: колья с черепами; кости; кольцо кольев от края коробки дерева, м
const LAIR_SPIKES := 6
const LAIR_BONES := 8
const LAIR_DECOR_RING := 4.0
## Подкраска руины пня (тот же рисунок, «заглохший»)
const LAIR_RUIN_TINT := Color(0.42, 0.40, 0.46)
## Глушь вокруг пня: кольцо R0…R1 м — грибы, камни, кости, кусты; рощицы дальше TREES_R м, кластеров и деревьев в каждом
const LAIR_GLADE_R0 := 9.0
const LAIR_GLADE_R1 := 22.0
const LAIR_GLADE_MUSHROOMS := 10
const LAIR_GLADE_STONES := 8
const LAIR_GLADE_BONES := 12
const LAIR_GLADE_BUSHES := 6
const LAIR_GLADE_TREES_R := 26.0
const LAIR_GLADE_TREE_CLUSTERS := 3
const LAIR_GLADE_TREES_PER := 5
## Снесённый пень восстанавливается не раньше чем через столько секунд (из spawn_config)
const LAIR_REGEN_SEC := _Spawn.LAIR_REGEN_SEC
## Заморозка пня за рекой: ничего не рождает, пока игрок не перешёл брод; потом разморозка порциями (из spawn_config)
const LAIR_FREEZE_ENABLED := _Spawn.LAIR_FREEZE_ENABLED
const LAIR_THAW_STEP_SEC := _Spawn.LAIR_THAW_STEP_SEC        # одна порция в столько с
const LAIR_THAW_CHECK_SEC := _Spawn.LAIR_THAW_CHECK_SEC      # поиск игрока на том берегу, с
const LAIR_THAW_BANK_MARGIN := _Spawn.LAIR_THAW_BANK_MARGIN  # м за сухой кромкой русла = «перешёл»
## Высота кола, м; сторона квада костей, м
const LAIR_SPIKE_H := 3.2
const LAIR_BONES_M := 2.0
## Расчищенная площадка под логово, м (лес и руда не сажаются)
const LAIR_CLEAR := 36.0

# ── РАСКЛАДКА ПНЕЙ ──
## Первый пень — абсолютная точка на правом берегу, м
const LAIR_SPOT := Vector2(105.0, 85.0)
## Прежнее смещение пня от якоря базы игрока — история, не читается
const LAIR_OFFSET := Vector2(28.0, 104.0)
## «Красный пень»: смещение от середины между якорями игрока и ИИ, м (X — от кромки к реке, Z 0 — напротив брода)
const LAIR_AI_SPOT := Vector2(30.0, 0.0)
## ТЗ 31.10.2026 (lair_layout_v2): пень в секции у левой кромки — смещение от середины якорей, м
const LAIR_AI_SPOT_V2 := Vector2(-15.0, 0.0)
## Зеркальный пень на правом берегу — абсолютная точка, м
const LAIR_MIRROR_SPOT := Vector2(196.0, 0.0)
## Площадка пня в секции — уже прежней: лесные стены секции не вырубаются, м
const LAIR_CLEAR_V2 := 16.0
## Гора за левым пнём: золото и камень — смещения от пня к кромке, м
const LAIR_PILE_GOLD := Vector2(-15.0, -9.0)
const LAIR_PILE_STONE := Vector2(-15.0, 9.0)
## Центр горы от якоря базы игрока, м
const HILL_OFFSET := Vector2(24.0, 52.0)

# ── МЕСТЬ ГОБЛИНОВ ──
## Пень зачищен — раз в интервал, с, из деревни выходят столько отрядов этого рода окружать дерево (из spawn_config)
const REVENGE_INTERVAL_SEC := _Spawn.REVENGE_INTERVAL_SEC
const REVENGE_SQUADS := _Spawn.REVENGE_SQUADS
const REVENGE_UNIT := _Spawn.REVENGE_UNIT
## Радиус кольца, которым отряды мести встают вокруг дерева, м
const REVENGE_RING := 22.0

# ── СТРОЙ ОРДЫ: ТОЛПА, А НЕ КАРЕ ──
## Шаг толпы — корень из площади на бойца, м (0.85 × SIZE_SCALE); разброс места в долях шага
const HORDE_SPOT := 1.23
const HORDE_JITTER := 0.45

# ── СТАРТОВАЯ ОРДА ──
## Что стоит у деревни в первую секунду: строки {unit, count (0 — уставной), vet, picks} (из spawn_config)
const START_SQUADS := _Spawn.GOBLIN_START_SQUADS
## Потолок живых бойцов орды на карту (живое значение по часам — spawn_config.horde_cap())
const HORDE_CAP := _Spawn.HORDE_CAP

## Порядок предпочтений при авто-выборе наград ветеранства (чего нет на уровне — пропускается)
const VETERAN_PREFERENCE := ["bonus_attack", "bonus_health", "bonus_defense",
	"bonus_armor", "bonus_speed"]

## Строки START_SQUADS с подставленными умолчаниями — одна точка чтения для спавна и стендов
static func start_squads() -> Array:
	var out: Array = []
	for row in START_SQUADS:
		var d: Dictionary = row
		var uid: String = String(d.get("unit", ""))
		if uid.is_empty():
			continue
		var n: int = int(d.get("count", 0))
		if n <= 0:
			n = int(SQUAD_SIZE.get(uid, 20))
		out.append({
			"unit":  uid,
			"count": n,
			"vet":   maxi(int(d.get("vet", 0)), 0),
			"picks": maxi(int(d.get("picks", 0)), 0),
		})
	return out

## Сколько стартовых отрядов выходит ветеранами (нужно стенду и балансу)
static func veteran_start_squads() -> int:
	var n := 0
	for row in start_squads():
		if int((row as Dictionary)["vet"]) > 0:
			n += 1
	return n

# ── РАСПИСАНИЕ ──
## До этой секунды орда спит (0 — спячки нет; механизм сна оставлен под стенды и сложность)
## ⚠ Менять только по явному ТЗ владельца (разворотов: 1)
const DORMANT_UNTIL_SEC := 0.0
## Такт мышления вожака орды, с
const THINK_INTERVAL := 2.0

# ── ГЛАВНЫЙ ЦИКЛ ОРДЫ: ГАРНИЗОН, РУДНИК, РАЗВЕДКА, РЕЙДЫ ──
## Элитный гарнизон деревни: столько первых ветеранских отрядов из деревни не выходят (из spawn_config)
const GARRISON_SQUADS := _Spawn.GOBLIN_GARRISON_SQUADS
## Рудник орды: м от деревни к центру карты; его охрана — список отрядов (из spawn_config)
const MINE_OFFSET := 25.0
const MINE_GUARD := _Spawn.GOBLIN_MINE_GUARD
## Отрядов резервом на захваченном руднике холма
const EXPAND_MINE_SQUADS := 1
## Рейды по экономике: интервал, с (из spawn_config); отрядов в малом и крупном рейде (чередуются)
const RAID_INTERVAL_SEC := _Spawn.GOBLIN_RAID_INTERVAL_SEC
const RAID_SQUADS_SMALL := 1
const RAID_SQUADS_BIG := 3
## Рейд: поиск целей вокруг известной базы, м; отход по доле запаса; потолок рейда, с
const RAID_HUNT_RADIUS := 70.0
const RAID_RETREAT_HP := 0.55
const RAID_FLEE_FOES := 12               # столько боевых чужих в FLEE_RADIUS — «сильное сопротивление», уходим
const RAID_FLEE_RADIUS := 18.0
const RAID_MAX_SEC := 70.0
## Рейд без добычи у известной базы дольше этого, с — домой
const RAID_IDLE_SEC := 12.0
## Фаза беспокойства (рейды и разведка): не короче MIN с; после MAX с — наступление тем, что есть (из spawn_config)
const HARASS_MIN_SEC := 90.0
const HARASS_MAX_SEC := _Spawn.GOBLIN_HARASS_MAX_SEC
const ASSAULT_MIN_SQUADS := _Spawn.GOBLIN_ASSAULT_MIN_SQUADS   # но не меньше стольких отрядов
## Мирная фаза, с (из spawn_config): отстройка и патруль границы; ответ на нападение и тревога рудника действуют и в мире
const PEACE_SEC := _Spawn.GOBLIN_PEACE_SEC
## Перемирие партии (красный ИИ и орда не нападают) — одно число с мирной фазой
const TRUCE_SEC := PEACE_SEC
## Орда не трогает красного ИИ раньше этого, с, и пока у него нет крепости
const AI_PROTECT_SEC := 1800.0
## Патруль границы деревни: радиус кольца, м; точек на кольце; смена точки, с
const PATROL_BORDER_R := 26.0
## Генеральный штурм базы — не раньше этой секунды (из spawn_config)
const ASSAULT_EARLIEST_SEC := _Spawn.GOBLIN_ASSAULT_EARLIEST_SEC
## Конные налётчики — веер вокруг базы, охота на рабочих и одинокие стрелковые отряды, налёт и отход (из spawn_config)
const SCOUT_UNITS := _Spawn.SCOUT_UNITS                      # бойцов в отряде, 0 — полный конный
const SCOUT_HARASS_SEC := _Spawn.SCOUT_HARASS_SEC            # налёт на добычу, с
const SCOUT_SORTIE_SEC := _Spawn.SCOUT_SORTIE_SEC            # передышка дома между вылазками, с
const SCOUT_MAX_SQUADS := _Spawn.SCOUT_MAX_SQUADS            # потолок пула отрядов
const SCOUT_SORTIE_WEIGHTS := _Spawn.SCOUT_SORTIE_WEIGHTS    # веса вылазки 1 / 2 / 3 отрядами
const SCOUT_RUN_SEC := _Spawn.SCOUT_RUN_SEC                  # отход после налёта, с
const SCOUT_SORTIE_MAX_SEC := _Spawn.SCOUT_SORTIE_MAX_SEC    # потолок одной вылазки, с
const SCOUT_ORBIT_R := _Spawn.SCOUT_ORBIT_R                  # радиус орбиты вокруг базы, м
const SCOUT_ORBIT_POINTS := _Spawn.SCOUT_ORBIT_POINTS        # точек орбиты
const SCOUT_HUNT_R := _Spawn.SCOUT_HUNT_R                    # поиск добычи от центра отряда, м
const SCOUT_LONE_R := _Spawn.SCOUT_LONE_R                    # «одинокий» стрелковый отряд: без пехоты в стольких м
## Уставной размер разведотряда: SCOUT_UNITS, а 0 — полный конный отряд
static func scout_units() -> int:
	return SCOUT_UNITS if SCOUT_UNITS > 0 else int(SQUAD_SIZE.get("goblin_rider", 50))

# ── ТАКТИКА ШТУРМА БАЗЫ (GoblinAttackCommander) ──
## Линия сбора: м от ближайшей чужой постройки (вне полёта стрелы и башни, внутри обзора построек)
const ASSAULT_STANDOFF := 30.0
## Постройки дальше этого от точки базы к «этой базе» не относятся, м
const ASSAULT_BASE_RADIUS := 90.0
## Шаг между отрядами на линии сбора, м
const ASSAULT_LINE_STEP := 9.0
## Сбор состоялся: доля отрядов не дальше радиуса, м, от своих мест; иначе — по таймауту, с
const ASSAULT_ASSEMBLE_RADIUS := 12.0
const ASSAULT_ASSEMBLE_FRAC := 0.7
const ASSAULT_ASSEMBLE_TIMEOUT := 45.0
## Паттерн А «провокатор»
const PROBE_FLANK_OFFSET := 22.0         # точка фланга: сдвиг поперёк оси от края базы, м
const PROBE_INFANTRY_SEC := 8.0          # пехота щупает, с
const PROBE_CAVALRY_SEC := 5.0           # конница колет, с
const PROBE_RECOVER_SEC := 5.0           # пауза на линии между уколами, с
const PROBE_CYCLES := 2                  # векторов прощупать до общего навала
## Паттерн Б «откатные волны»
const HR_CAVALRY_SEC := 6.0              # конница бьёт в лоб, с
const HR_CAVALRY_BACK_SEC := 6.0         # откат к линии, с (пехота заходит в брешь)
const HR_BRAWL_SEC := 20.0               # замес дольше этого, с…
const HR_LOSING_DROP := 0.25             # …с потерей этой доли запаса — отход всей армии
## Паттерн В «веер»: сдвиг фланговых групп от центра, м; каскад между группами, с
const FAN_OFFSET := 24.0
const FAN_CASCADE_SEC := 1.5
## Отход и лечение: запас армии ниже RETREAT_HP — все в лагерь; восстановились до REARM_HP — новая волна другим паттерном
const ASSAULT_RETREAT_HP := 0.5
const ASSAULT_REARM_HP := 0.9
## Лагерь — деревня, если она ближе CAMP_FAR м от базы, иначе точка на оси отхода в CAMP_DIST м от края базы (вне башен)
const ASSAULT_CAMP_FAR := 120.0
const ASSAULT_CAMP_DIST := 70.0
## Лечение у костров: радиус, м, и запаса в секунду
const CAMP_HEAL_RADIUS := 30.0
const CAMP_HEAL_PER_SEC := 2.0
## Марш в центр с дозором: конница впереди тела, замечает чужих и отходит к телу — тело переходит в штурм
const VANGUARD_LEAD := 25.0              # дозор впереди тела, м
const VANGUARD_SIGHT := 30.0             # обзор дозора, м
const VANGUARD_REISSUE_DIST := 8.0       # цель дозора переиздаётся, уехав дальше, м
## Оборона деревни: пехота держит рубеж у костров, конница колет с фланга (сторона чередуется)
const DEFEND_ALERT_PAD := 20.0           # угроза замечается в DEFEND_RADIUS + столько м
const DEFEND_LINE_DIST := 18.0           # рубеж пехоты от центра деревни к угрозе, м
const DEFEND_ENGAGE := 16.0              # пехота бьёт не дальше этого от своего места, м
const DEFEND_CAV_FLANK := 20.0           # заход конницы поперёк угрозы, м
const DEFEND_CAV_STRIKE_SEC := 6.0       # конница колет, с
const DEFEND_CAV_BACK_SEC := 5.0         # и отходит к деревне, с

# ── ОВЦЫ У ЛОГОВА И ГОЛОД ТРОЛЛЯ ──
## Стартовое стадо; прирост — штук раз в BREED_SEC с (из spawn_config); потолок стада логова
const SHEEP_START := _Spawn.SHEEP_START
const SHEEP_BREED_SEC := _Spawn.SHEEP_BREED_SEC
const SHEEP_BREED_COUNT := _Spawn.SHEEP_BREED_COUNT
const SHEEP_MAX := 10
## Выпас: дальше этого от логова овца не уходит, м
const SHEEP_GRAZE_RADIUS := 26.0
## Личный период размножения спокойной овцы, с: у замка и в загоне (стадо удваивается за период до потолка привязки)
const SHEEP_BREED_CASTLE_SEC := 300.0
const SHEEP_BREED_PEN_SEC    := 150.0

## Овца логова, которую CALM_SEC с никто не трогал, раз в SELF_BREED_SEC с приводит ещё одну (в пределах SHEEP_MAX)
const SHEEP_SELF_BREED_SEC := 150.0
const SHEEP_CALM_SEC := 25.0
## Перебежка раз в HOP_SEC с на HOP_MIN…HOP_MAX м; скорость перехода, м/с
const SHEEP_HOP_SEC := 10.0
const SHEEP_HOP_MIN := 5.0
const SHEEP_HOP_MAX := 10.0
const SHEEP_SPEED := 1.1
## Пиксель овцы, м: рисунок 38 px в кадре 128 → ~0.9 м ростом
const SHEEP_PIXEL_SIZE := 0.0192
## Тролль голодает раз в столько секунд (±20 %) или когда стадо больше TROLL_HUNGRY_FLOCK
const TROLL_HUNGER_SEC := 150.0
## Голос тролля: окно между попытками рыкнуть на марше, с, и шанс попытки; вероятность рыка на удар в бою
const TROLL_GROWL_MIN_SEC := 12.0
const TROLL_GROWL_MAX_SEC := 20.0
const TROLL_GROWL_MARCH_P := 0.35
const TROLL_GROWL_FIGHT_P := 0.12
## Смех орды над выбитым отрядом: последний чужой погиб не дальше этого от какого-нибудь гоблина, м
const LAUGH_SIGHT := 18.0
## Смех при убийствах выключен (заказ владельца)
const LAUGH_ENABLED := false
## Хор смеха только в малой стычке: отрядов орды в LAUGH_SIGHT не больше
const LAUGH_MAX_SQUADS := 3
## Стадо больше этого — тролль голоден вне очереди
const TROLL_HUNGRY_FLOCK := 5
## Отара заново: стадо вырезано или съедено целиком — пень ждёт RESPAWN_SEC с и выпускает RESPAWN_COUNT овец (из spawn_config)
const SHEEP_RESPAWN_SEC := _Spawn.SHEEP_RESPAWN_SEC
const SHEEP_RESPAWN_COUNT := _Spawn.SHEEP_RESPAWN_COUNT
## Рейд тролля за овцами: у стороны (игрок или красный ИИ) больше стольких овец — свободный тролль идёт к стаду
const TROLL_RAID_SHEEP := 30
const TROLL_RAID_EAT := 3                # съедает
const TROLL_RAID_HERD := 5               # уводит к своему пню
## По дороге ломает постройки (крепость — никогда): радиус, м; наевшись, ищет хотя бы одну в стольких м от стада; на снос не дольше, с
const TROLL_RAID_SMASH_R := 14.0
const TROLL_RAID_SMASH_SEEK := 45.0
const TROLL_RAID_SMASH_SEC := 60.0
## Откат рейда на тролля, с; период проверки, с; радиус «дома» у пня, м
const TROLL_RAID_COOLDOWN_SEC := 300.0
const TROLL_RAID_CHECK_SEC := 6.0
const TROLL_RAID_HOME_R := 10.0
## Второй («красный») пень у базы красного ИИ (из spawn_config)
const LAIR_AI_ENABLED := _Spawn.LAIR_AI_ENABLED
## Овцы — возобновляемый ресурс: снесённый пень восстаёт и выпускает столько троллей-воров; удачный рейд — ещё столько (из spawn_config)
const TROLL_RAID_SPAWN := _Spawn.TROLL_RAID_SPAWN
const TROLL_RAID_REWARD := _Spawn.TROLL_RAID_REWARD
## Период проверки «у стороны много овец», с
const SHEEP_PRESSURE_CHECK_SEC := 6.0
## Тролль ест с этого расстояния, м; съеденная овца лечит долю полного запаса
const TROLL_EAT_RANGE := 2.8
const TROLL_EAT_HEAL := 0.2
## Дальше этого от деревни отряды в обороне не отходят, м
const DEFEND_RADIUS := 40.0

# ── ОТХОД В ХИЖИНУ ──
## Разбитый отряд уходит лечиться: порог — доля от ПИКОВОЙ численности отряда (не от уставной)
const RETREAT_STRENGTH := 0.15

# ── СПЯЧКА ──

# ── МЕСТО БОЙЦА В ТОЛПЕ ──
## Россыпью, а не кучей: места толпы раздвинуты на эту долю (шаг шире, отряды идут реже)
const HORDE_SPREAD := 1.2
## Плотная толпа (ручка horde_dense): шаг 1.23 × 0.9 = 1.1 м — вдвое шире
## личного круга гоблина (0.60 м), и разброс места меньше
const HORDE_DENSE_SPREAD := 0.9
const HORDE_DENSE_JITTER := 0.3
## Туши шире своей прежней толпы (ручка horde_dense): множитель к шагу
const BIG_WIDE_MULT := 1.5
const _OptGC := preload("res://scripts/perf_config.gd")

static func horde_spread() -> float:
	return HORDE_DENSE_SPREAD if _OptGC.horde_dense else HORDE_SPREAD

static func horde_jitter() -> float:
	return HORDE_DENSE_JITTER if _OptGC.horde_dense else HORDE_JITTER

## Шаг толпы туш поверх общего (ручка horde_dense)
static func big_wide() -> float:
	return BIG_WIDE_MULT if _OptGC.horde_dense else 1.0

## Место бойца idx из total в отряде seed_id: спираль золотого угла по диску плюс детерминированный сдвиг
static func horde_offset(idx: int, total: int, seed_id: int) -> Vector2:
	var n: int = maxi(total, 1)
	# Радиус диска — из площади на бойца: pi*R^2 = n * SPOT^2
	var r_max: float = sqrt(float(n) / PI) * HORDE_SPOT * horde_spread()
	var ang: float = float(idx) * 2.39996323                      # золотой угол
	var r: float = sqrt((float(idx) + 0.5) / float(n)) * r_max
	var h1: float = fposmod(sin(float(idx) * 12.9898 + float(seed_id) * 4.1414) * 43758.5453, 1.0)
	var h2: float = fposmod(sin(float(idx) * 78.2330 + float(seed_id) * 7.7373) * 24634.6345, 1.0)
	var j: float = HORDE_SPOT * horde_jitter()
	return Vector2(cos(ang) * r + (h1 - 0.5) * 2.0 * j,
		sin(ang) * r + (h2 - 0.5) * 2.0 * j)

## Габарит толпы отряда, м (нужен обороне и стенду)
static func horde_radius(total: int) -> float:
	return sqrt(float(maxi(total, 1)) / PI) * HORDE_SPOT * horde_spread() + HORDE_SPOT * horde_jitter()

# ── МЕСТА ХИЖИН ──
## Сетка в шахматку вокруг центра: смещения хижин от центра деревни
static func hut_offsets() -> Array:
	var out: Array = []
	var rows: int = HUT_ROWS.size()
	for r in range(rows):
		var cnt: int = int(HUT_ROWS[r])
		var z: float = (float(r) - float(rows - 1) * 0.5) * HUT_STEP
		var shift: float = (float(r % 2) - 0.5) * HUT_ROW_OFFSET * HUT_STEP
		for c in range(cnt):
			var x: float = (float(c) - float(cnt - 1) * 0.5) * HUT_STEP + shift
			out.append(Vector2(x, z))
	return out

# ── БОЛЬШОЙ ГОБЛИН (ТУША) ──
## Во сколько раз туша крупнее людского наброска («клетка» в заказах = метр); пиксель спрайта, м
const BIG_SIZE_SCALE := 2.4
const BIG_PIXEL_SIZE := 0.0108 * BIG_SIZE_SCALE
## Свип дубины: косинус полуугла сектора перед взглядом (±60°); полуширина полосы, м («3 клетки»)
const BIG_SWEEP_ARC_COS := 0.5
const BIG_SWEEP_HALF_W := 1.5
## Скольких накрывает один взмах; отброс накрытых, м («1-2 клетки»)
const BIG_SWEEP_MAX := 6
const BIG_KNOCKBACK := 1.5
## Каждый N-й взмах — двойной; пауза внутри двойного удара, с
const BIG_COMBO_EVERY := 3
const BIG_COMBO_GAP := 0.45
## За столько секунд до готовности удара будится замороженный скан целей (развернуть спрайт, начать замах)
const BIG_SCAN_LEAD := 0.6
## Множитель удара по зданию (отдельная запись BigGoblin._hit_building, в т. ч. второй удар двойного взмаха; свип бьёт только бойцов)
const BIG_BUILDING_DMG_MULT := 1.5
## Личный радиус расталкивания: множитель к ширине туши
const BIG_SEP_MULT := 2.2
## Тонкий обвод туши: радиус по ступням, м; овал — растяжение по осям (как у тролля)
const BIG_FINE_RING_R := 0.75
const BIG_RING_OVAL := Vector2(1.35, 0.9)
## Вспышка удара — лёгкая красная, как у тролля, а не белая
const BIG_FLASH_PEAK := 0.35
const BIG_FLASH_COLOR := Color(1.0, 0.22, 0.18)
## Строй отряда туш: колонок и шаг, м (их надо разводить)
const BIG_SQUAD_COLS := 3
const BIG_SQUAD_SPACING := 2.2
## Отрядов туш: в волне пня, на базе орды, в защите пня (из spawn_config)
const BIG_WAVE_SQUADS := _Spawn.BIG_WAVE_SQUADS
const BIG_BASE_SQUADS := _Spawn.BIG_BASE_SQUADS
const BIG_DEFENSE_SQUADS := _Spawn.BIG_DEFENSE_SQUADS
## Тяжёлый шаг: период звука шага, с (своя категория звука, редкий и низкий)
const BIG_STEP_SEC := 1.45
## Перехват на марше: урон или чужой рядом — погоня и добивание отряда, поле чисто — возврат на точку марша
const BIG_AGGRO_RADIUS := 18.0           # чужой ближе — бросает точку марша, м
const BIG_HUNT_RADIUS := 28.0            # пока здесь есть чужие — ищет следующего, м
const BIG_PURSUIT_LIMIT := 60.0          # поводок погони, м
const BIG_HUNT_TICK := 0.5               # такт скана, с
## Связка с пехотой орды: без цели берёт цель соседнего отряда гоблинов, м; отстав от своей пехоты дальше, м — идёт к ней
const BIG_ESCORT_RADIUS := 30.0
const BIG_ESCORT_FOLLOW := 22.0
## Порог ленты ходьбы туши — доля её шага (общий порог 1.0 м/с срезал ленту при замедлении в толпе)
const BIG_WALK_ANIM_FRAC := 0.4
## Гоблин с целью бежит: множитель к ходьбе, пока держит цель
const GOBLIN_RUN_MULT := 1.3
## Охота свино-всадника (веса целей: лучник 2.2, мечник 1.6, рабочий 1.4, копейщик в строю 0.4): скан, м и с; поводок, м; авто-агро, м
const RIDER_HUNT_RADIUS := 30.0
const RIDER_HUNT_TICK := 0.5
const RIDER_PURSUIT_LIMIT := 40.0
const RIDER_AGGRO_RADIUS := 20.0
## Вес туши как цели у стрелков
const BIG_TARGET_PRIO := 2.0

# ── ДРЕМЛЮЩИЙ РЕЗЕРВ ОРДЫ (DormantReserve.gd) ──
## Одноразовый спящий резерв за лагерем и его состав (из spawn_config); будит только штурм лагеря
const RESERVE_ENABLED := _Spawn.GOBLIN_RESERVE_ENABLED
const RESERVE_SQUADS := _Spawn.GOBLIN_RESERVE_SQUADS
## Где стоит: за деревней (от центра карты), м от её края; колонн и шаг между отрядами, м
const RESERVE_BACK := 22.0
const RESERVE_COLS := 5
const RESERVE_STEP := 12.0
## Такт проверки угрозы по сетке ядра, с
const RESERVE_TICK_SEC := 0.75
## Штурм лагеря: столько чужих боевых в радиусе, м, от центра деревни (меньше — разведчик)
const RESERVE_WAKE_RADIUS := 44.0
const RESERVE_WAKE_FOES := 6
## Ушли чужие — возврат на посты и сон
const RESERVE_CALM_SEC := 8.0            # без угрозы столько с — домой
const RESERVE_HOME_RETRY_SEC := 20.0     # переиздать приказ домой, если не дошёл, с
const RESERVE_HOME_RADIUS := 6.0         # на посту в этом радиусе, м — снова спит
## Лечение на постах, доля запаса в секунду (конница после вылазки лечится здесь, не в хижине)
const RESERVE_HEAL_FRAC := 0.03
## Конных отрядов взаймы вожаку на одну вылазку, не больше; не даёт, когда в резерве меньше LEND_FLOOR отрядов (из spawn_config)
const RESERVE_LEND_MAX := 2
const RESERVE_LEND_FLOOR := _Spawn.GOBLIN_RESERVE_LEND_FLOOR
## Пробуждение волнами: отрядов в волне и пауза между волнами, с (из spawn_config)
const RESERVE_WAVE_SQUADS := _Spawn.RESERVE_WAVE_SQUADS
const RESERVE_WAVE_GAP_SEC := _Spawn.RESERVE_WAVE_GAP_SEC

# ── Свинобосс — полководец орды (PigBoss.gd, PigBossCommander.gd; ТЗ 28.10.2026) ──
## Модель ×3 наездника: размер пикселя и личные габариты
## Знамя за спиной босса: назад от взгляда (доля ширины кадра), вверх (доля
## высоты тела), вглубь кадра, м — чтобы рисовалось за телом
const BOSS_BANNER_BACK := 0.11
const BOSS_BANNER_UP := 0.20
const BOSS_BANNER_DEPTH := 0.5
const BOSS_SIZE_SCALE := 2.1             # ТЗ 29.10.2026: −30 % (было 3.0)
const BOSS_PIXEL_SIZE := PIXEL_SIZE * BOSS_SIZE_SCALE
const BOSS_SEP_MULT := 0.6               # sep_radius = SEP_MIN_DIST × SIZE_SCALE × BOSS_SIZE_SCALE × это
const BOSS_FINE_RING_R := 0.9            # тонкий обвод у ног, м (> 0 — тело в ядре)
const BOSS_RING_OVAL := Vector2(1.4, 0.9)
const BOSS_PICK_BODY_H := 1.7            # высота кликбокса, м
const BOSS_PICK_R := 1.1                 # радиус кликбокса у ног, м
const BOSS_AIM_H := 1.55                 # куда целится стрелок, м
const BOSS_FLASH_PEAK := 0.35
const BOSS_FLASH_COLOR := Color(1.0, 0.45, 0.35)
const BOSS_TARGET_PRIO := 2.5            # вес как цели стрелков
const BOSS_AGGRO_RADIUS := 18.0          # авто-агро в покое, м
const BOSS_PURSUIT_LIMIT := 40.0         # поводок погони, м
## Доспех: подтон перекраски листов и доля смешения (0 — лист наездника как есть)
const BOSS_ARMOR_TINT := Color(0.66, 0.74, 0.90)
const BOSS_TINT_MIX := 0.55
## Свип удара: сектор ±60° (cos), ширина за дальность оружия, накрытых за взмах, отброс, м
const BOSS_SWEEP_ARC_COS := 0.5
const BOSS_SWEEP_HALF_W := 1.5
const BOSS_SWEEP_MAX := 6
const BOSS_KNOCKBACK := 2.0
const BOSS_BUILDING_DMG_MULT := 3.0      # удар по постройке-цели × это
## Аура подавления: радиус, м; такт раздачи, с; срок метки, мс (> такта)
const BOSS_AURA_R := 40.0
const BOSS_AURA_TICK := 0.5
const BOSS_AURA_HOLD_MS := 1200
## Варварский клич: откат по игровым часам, с; срок, с; множители урона чужих/своих; замешательство, с; чужих в ауре для решения
const BOSS_SCREECH_CD_SEC := 300.0
const BOSS_SCREECH_SEC := 20.0
const BOSS_SCREECH_FOE_MULT := 0.85
const BOSS_SCREECH_ALLY_MULT := 1.15
const BOSS_HESITATE_SEC := 1.5
const BOSS_SCREECH_MIN_FOES := 12
## Кольцо ауры: цвет, цвет и срок вспышки клича, мс
const BOSS_RING_COLOR := Color(0.55, 0.20, 0.75, 0.55)
const BOSS_RING_FLASH_COLOR := Color(1.0, 0.35, 0.25, 0.95)
const BOSS_RING_FLASH_MS := 900
## Мозг: такт, с; повтор приказа отряду не чаще, с; радиус оси фронта, м; точки плотности — вперёд/вбок, м, радиус счёта, м
const BOSS_TICK_SEC := 1.0
const BOSS_REISSUE_SEC := 8.0
const BOSS_FRONT_SCAN_R := 60.0
const BOSS_PROBE_AHEAD := 18.0
const BOSS_PROBE_SIDE := 22.0
const BOSS_PROBE_R := 14.0
const BOSS_FLANK_ARRIVE := 8.0           # конница уже на фланге ближе этого, м
const BOSS_FINISH_STRENGTH := 0.4        # чужой отряд слабее этой доли штата — добить
const BOSS_FINISH_R := 55.0              # искать такие не дальше, м от центра волны
## Самосохранение: отход при доле hp, возврат при доле hp, укрытие за центром волны, м; сектор выхода из окружения, м; лечение в волне, доля запаса в с
const BOSS_WITHDRAW_HP := 0.25
const BOSS_RETURN_HP := 0.60
const BOSS_SHELTER_DIST := 30.0
const BOSS_ESCAPE_R := 12.0
const BOSS_REGEN_PER_SEC := 0.004
## Отряд босса: ранг свиты (VET_BANNER_TIERS), наград свите; покупка не раньше, с партии; номер на знамени
const BOSS_ESCORT_VET := 4
const BOSS_ESCORT_PICKS := 2
const BOSS_FROM_SEC := 1800.0
const BOSS_BANNER_NUMBER := 1
## «Гоблинский горн» (ТЗ 29.10.2026; откат и срок — BOSS_SCREECH_CD_SEC / BOSS_SCREECH_SEC):
## своим в ауре атака ×, входящий урон × (−20 % стойкости = ×1/0.8), чужим атака ×; рык отрядов — не больше стольких
const BOSS_HORN_ALLY_ATK_MULT := 1.30
const BOSS_HORN_ALLY_FRAIL_MULT := 1.25
const BOSS_HORN_FOE_ATK_MULT := 0.85
const BOSS_HORN_ROAR_SQUADS := 6
## «Удар Свинобосса» — таран строя (ТЗ 29.10.2026): откат, с; поиск строя копейщиков, м; живых в нём не меньше
const BOSS_RAM_CD_SEC := 600.0
const BOSS_RAM_SCAN_R := 40.0
const BOSS_RAM_MIN_MEN := 10
## Подготовка (свита встаёт за спиной), с; скорость тарана × move_speed; дальше этого — таран выдохся, м
const BOSS_RAM_PREP_SEC := 2.5
const BOSS_RAM_SPEED_MULT := 1.9
const BOSS_RAM_MAX_DIST := 45.0
## Ряды строя: полоса поиска поперёк хода, м; разрыв по ходу, с которого начинается новый ряд, м
const BOSS_RAM_ROW_LANE := 3.0
const BOSS_RAM_ROW_GAP := 0.32
## Пробиваемых рядов (третий — застревает), встаёт перед ним за, м
const BOSS_RAM_PIERCE_ROWS := 2
const BOSS_RAM_STOP_GAP := 0.9
## Накрытие: радиус у тела, м; полоса гибели поперёк хода, м; погибших за таран не больше
const BOSS_RAM_HIT_R := 2.4
const BOSS_RAM_KILL_LANE := 1.6
const BOSS_RAM_KILL_MAX := 12
## Раскиданные в стороны: доля макс. запаса, отлёт вбок, м, лежат, с
const BOSS_RAM_SIDE_FRAC := 0.45
const BOSS_RAM_SIDE_KNOCK := 3.2
const BOSS_RAM_KNOCKDOWN_SEC := 2.0
## Свита: искать не дальше, м; своя свита в деле, если живых не меньше; подкрепление — всадников
const BOSS_RAM_ESCORT_R := 50.0
const BOSS_RAM_ESCORT_MIN := 5
const BOSS_RAM_REINF_N := 12
## Свита в прорыв: точка за спиной босса, м; ждать сбора не дольше, с
const BOSS_RAM_BREACH_BACK := 2.5
const BOSS_RAM_RUSH_SEC := 3.0
## После тарана — бой как у тролля (сбивает с ног, раздвигает кольцо), с
const BOSS_BRAWL_SEC := 30.0
## Зонд босса: сводка состояния раз в, с
const BOSS_PROBE_STATUS_SEC := 15.0
## Ярость (ТЗ 29.10.2026, 2В): порог доли hp; скорость ×; перезарядка удара и откаты способностей ×; рык раз в, с
const BOSS_RAGE_HP := 0.20
const BOSS_RAGE_SPEED := 1.25
const BOSS_RAGE_CD_MULT := 0.70
const BOSS_RAGE_GROWL_SEC := 5.0
## Исступление: порог доли hp; скорость ×; перезарядка ×; урон взмаха ×; красный накал — вспышка раз в, с, яркость
const BOSS_FRENZY_HP := 0.05
const BOSS_FRENZY_SPEED := 1.50
const BOSS_FRENZY_CD_MULT := 0.45
const BOSS_FRENZY_DMG_MULT := 1.5
const BOSS_FRENZY_GLOW_SEC := 0.3
const BOSS_FRENZY_GLOW_PEAK := 0.75
## Бегство на базу: порог доли hp (и сразу после тарана при hp <= BOSS_RAGE_HP); скорость бегства ×;
## точка — от главной хаты на столько м к краю лагеря; прибыл — ближе, м
const BOSS_FLEE_HP := 0.12
const BOSS_FLEE_SPEED_MULT := 1.3
const BOSS_BASE_BACK := 18.0
const BOSS_BASE_ARRIVE_R := 10.0
## На базе: лечение, доля запаса в с; готов выйти при доле hp
const BOSS_BASE_REGEN_PER_SEC := 0.02
const BOSS_BASE_READY_HP := 0.95
## Таран (ТЗ 30.10.2026): доля растоптанных в полосе гибели, что выживает; их запас — доля max_health; потолок бега, с
const BOSS_RAM_SURVIVE_SHARE := 0.5
const BOSS_RAM_SURVIVE_HP := 0.5
const BOSS_RAM_RUN_MAX_SEC := 5.0
## Рывки после тарана: первый через, с; дальше раз в, с — если у морды >= TROLL_SURROUND_FOES; длина рывка, м;
## рывков на таран; выход насквозь в конце боя, м; урон накрытому рывком — доля запаса
const BOSS_SURGE_FIRST_SEC := 4.0
const BOSS_SURGE_EVERY_SEC := 6.0
const BOSS_SURGE_DIST := 5.0
const BOSS_SURGE_MAX := 3
const BOSS_SURGE_EXIT_DIST := 10.0
const BOSS_SURGE_FRAC := 0.25
## Прорыв в бегстве (ТЗ 31.10.2026): проба чужих впереди на столько м, радиус пробы, м; длина рывка, м;
## не чаще раза в, с; урон накрытому — доля запаса (только расталкивает)
const BOSS_FLEE_PROBE_AHEAD := 3.0
const BOSS_FLEE_PROBE_R := 3.0
const BOSS_FLEE_DASH_DIST := 9.0
const BOSS_FLEE_DASH_CD_SEC := 0.6
const BOSS_FLEE_DASH_FRAC := 0.05
## Без волны дольше, с — вылазка сам (ТЗ 30.10.2026); готовые планы орды идут с ним
const BOSS_IDLE_SORTIE_SEC := 90.0

# ── ГНОЛЛЫ: ЗОНА ОТВЕТСТВЕННОСТИ И ОХОТА НА РАБОЧИХ (GnollAI.gd) ──
## Зона гноллов — лес вокруг пня; цель вне зоны бросается, боец возвращается
const GNOLL_ZONE_RADIUS := 48.0          # круг вокруг пня, м
const GNOLL_ZONE_TOWARD_BASE := 8.0      # полуплоскость «к базе людей своей стороны» дальше этого закрыта, м
const GNOLL_FORD_PAD := 14.0             # брод закрыт всегда: полоса FORD_HALF + столько м
## Круговой патруль: шаг угла за отрезок, градусы (направление — по номеру узла); точка притягивается к дереву в стольких м
const GNOLL_PATROL_STEP_DEG := 40.0
const GNOLL_PATROL_TREE_SNAP := 9.0
## Гнолл без пня (снесён, загрузка партии) подхватывает ближайший не дальше этого, м; иначе остаётся у home_pos
const GNOLL_HOME_ADOPT_R := 60.0
## Поводок погони тролля: дальше этого от точки начала погони, м — цель брошена, домой
const TROLL_CHASE_RADIUS := 45.0
## Охота на чужих рабочих: такт скана, с; радиус от пня (внутри зоны), м; свободных гноллов на одну жертву
const GNOLL_HUNT_TICK := 0.75
const GNOLL_HUNT_RADIUS := 45.0
const GNOLL_HUNTERS_PER_PREY := 2

# ── Кузница гоблинов (ТЗ 28.10.2026; древо и экономика — scripts/economy/goblin_forge/) ──
## Размер кузницы относительно хижины (квад от build_size, коробка и фундамент растут вместе)
const GOBLIN_FORGE_SIZE_MULT := 1.6
## Ворота кузницы — тот же HUT_GATE × размер (как у главной хаты)
const GOBLIN_FORGE_GATE_MULT := GOBLIN_FORGE_SIZE_MULT
