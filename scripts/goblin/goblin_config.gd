extends RefCounted
## ПОВЕДЕНИЕ ОРДЫ: деревня, фазы, волны, тролли, гноллы, овцы, резерв.
## Только параметры (сила и запас — в unit_stats_config.STATS). Без class_name — через preload.
## Спавн и тайминги — scripts/spawn_config.gd; снятые пояснения — docs/CONFIG_NOTES_2026-09-14.md
const _Spawn := preload("res://scripts/spawn_config.gd")

const SQUAD_SIZE := _Spawn.GOBLIN_SQUAD_SIZE
## Ширина строя при выходе из хижины
const SQUAD_COLS := {
	"goblin_spearman": 10,
	"goblin_rider":    8,
	"gnoll":           4,
	"big_goblin":      3,
}
const SQUAD_SPACING := 0.65

## ЧЕГО И СКОЛЬКО В ПОЛНОЙ ОРДЕ — ВЫВОДИТСЯ ИЗ СТАРТОВОГО СОСТАВА (см.
static func army_composition() -> Array:
	var out: Array = []
	for row in START_SQUADS:
		out.append(String((row as Dictionary).get("unit", "")))
	return out

static func army_squads() -> int:
	return START_SQUADS.size()

# ── ЦЕНА И ВРЕМЯ НАЙМА ──────────────────────────────────────────────────────
## Отряд стоит 90 еды и делается полторы минуты — заказ владельца
const SQUAD_FOOD_COST := _Spawn.GOBLIN_SQUAD_FOOD_COST
const SQUAD_BUILD_SEC := _Spawn.GOBLIN_SQUAD_BUILD_SEC

# ── ДЕРЕВНЯ ─────────────────────────────────────────────────────────────────
## Сколько хижин ставится в деревне
const HUTS := 10
## Еды в минуту с ОДНОЙ хижины (заказ владельца: +100 в минуту)
const HUT_FOOD_PER_MIN := 100.0
const HUT_TICK_SEC := 10.0
## ── ПЛОТНАЯ ЗАСТРОЙКА ───────────────────────────────────────────────────────
const HUT_STEP := 6.0
const HUT_ROWS := [4, 3, 3]
## Смещение каждого следующего ряда вбок, доля шага: ряды идут «в шахматку»
const HUT_ROW_OFFSET := 0.5
const VILLAGE_RADIUS := 16.0
const HUT_MIN_GAP := 5.0
## Частота дыма из трубы, кадров в секунду (лента Goblin Hut.png — 12 кадров)
const HUT_SMOKE_FPS := 7.0
## Доля от полукарты, на которой стоит центр деревни В ПРАВОМ ВЕРХНЕМ УГЛУ.
const VILLAGE_ANCHOR := Vector2(0.72, -0.72)

# ── ВНЕШНИЙ ВИД ─────────────────────────────────────────────────────────────
## РАЗМЕР ПИКСЕЛЯ У ГОБЛИНОВ СВОЙ, и это не косметика.
const PIXEL_SIZE := 0.012282

const SIZE_SCALE := 1.445

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## ТРОЛЛЬ И ЛОГОВО (заказ владельца, 09.09.2026)
const TROLL_PIXEL_SIZE := 0.0261   # спринт 15: −15 % (было 0.0307)
## Порог альфы, по которому ищутся СТУПНИ тролля в кадре (Unit._anim_bottom_px):
const TROLL_FOOT_ALPHA := 0.5
## Во сколько раз шире пехотинца личный круг тролля (Unit.sep_radius)
const TROLL_SIZE_SCALE := 3.4       # спринт 15: −15 % вслед за спрайтом
## Серия ударов дубиной до одышки и её длительность (лента Recovery)
const TROLL_SWINGS := 3             # спринт 15: серия из ТРЁХ ударов
const TROLL_REST_SEC := 2.75        # спринт 16: одышка 2.5-3 с после трёх ударов
## Брызги дубины: радиус вокруг цели, м, и доля урона соседям
const TROLL_SPLASH_RADIUS := 3.0
const TROLL_SPLASH_FRAC := 0.6
# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════

## Габарит: кадр гнолла 192×192, как у людей, но сам он поджарее гоблина
const GNOLL_PIXEL_SIZE := 0.0125
## Кость вылетает от плеча, а не от ступней
const GNOLL_THROW_Y := 1.05
## ── ПОЛЁТ КОСТИ: ЧЕСТНЫЙ НАВЕС НА КОРОТКОЙ ДИСТАНЦИИ (спринт 14) ─────────
const GNOLL_BONE_SPEED := 7.0
## ── БРОСОК ОТ РУКИ, А НЕ НАВЕС (заказ спринта 15) ─────────────────────────
const GNOLL_BONE_ARC := 0.18
## ── КУВЫРОК В ПОЛЁТЕ ──────────────────────────────────────────────────────
## Кость крутится через голову, пока летит, и ПЕРЕСТАЁТ, как только воткнулась.
const GNOLL_BONE_AXIS_K := 0.4
## Оборотов в секунду у летящей кости
const GNOLL_BONE_SPIN := 2.2
## ── ВЫЛЕТ ПРИВЯЗАН К КАДРУ ЗАМАХА ─────────────────────────────────────────
## Лента Gnoll_Throw — восемь кадров; рука распрямляется примерно на пятом.
const GNOLL_THROW_FRAME := 4
## Разброс обычного броска и доля явных ПРОМАХОВ (кость в землю рядом)
const GNOLL_SCATTER := 1.5
const GNOLL_MISS_CHANCE := 0.3
const GNOLL_MISS_SPREAD := 3.2

## ── КАЙТ ──────────────────────────────────────────────────────────────────
const GNOLL_KITE_IN := 6.0
const GNOLL_KITE_OUT := 9.0
const GNOLL_KITE_SEC := 1.1
const GNOLL_MELEE_RANGE_MAX := 5.0
## ── КАЙТ ОТМЕНЯЕТСЯ, КОГДА ОТБЕГАТЬ НЕКУДА (заказ спринта 14) ────────────
## Жалоба: «гноллы бежали на месте с зацикленным звуком шагов». Так и было:
const GNOLL_KITE_GIVEUP := 1.0
const GNOLL_KITE_MIN_GAIN := 0.8
const GNOLL_KITE_BLOCK_SEC := 4.0

## ── ПАТРУЛЬ И ПОВОДОК ─────────────────────────────────────────────────────
const GNOLL_PATROL_RADIUS := 26.0
const GNOLL_PATROL_SEC := 7.0
## ── АГРЕССИЯ С ДЕСЯТИ МЕТРОВ (заказ спринта 14) ─────────────────────────
const GNOLL_AGGRO_LEASH := 10.0
## Дальность броска. Короче прежних 11 м намеренно: см. разбор дуги выше
const GNOLL_THROW_RANGE := 8.5

## ── ОБОРОНА ПНЯ: ФЛАНГ И ОТВЛЕЧЕНИЕ ───────────────────────────────────────
## Враг ближе GNOLL_DEFEND_RANGE от пня — гнолл встаёт СБОКУ от линии
const GNOLL_DEFEND_RANGE := 34.0
const GNOLL_FLANK_SIDE := 13.0
const GNOLL_FLANK_BACK := 8.0
const GNOLL_FLANK_SEC := 4.0

## ── ИНТЕРВАЛ ПОСЛЕ ПРОМАХА СКАНА (аудит класса, сент. 2026) ───────────────
const GNOLL_FLANK_MISS_SEC := 1.0
const GNOLL_KITE_MISS_SEC := 0.3
const GNOLL_SCAN_PHASES := 17

## ── ВОЛНЫ (прямой заказ спринта 13) ───────────────────────────────────────
## ── ПОВЕДЕНИЕ ПОД УРОНОМ (заказ спринта 16) ─────────────────────────────────
## «3 отряда на старте; если по пню бьют — ещё 3 через 3 минуты и ещё 3 через
const GNOLL_RUN_BACK := 5.0
const GNOLL_HIDE_HP := 0.45
const GNOLL_HIDE_RANGE := 4.5
const GNOLL_HIDE_HEAL_FRAC := 0.12
const GNOLL_START_SQUADS := _Spawn.GNOLL_START_SQUADS
const GNOLL_WAVE_SQUADS := _Spawn.GNOLL_WAVE_SQUADS
const GNOLL_WAVE_SEC := _Spawn.GNOLL_WAVE_SEC
const GNOLL_WAVES_MAX := _Spawn.GNOLL_WAVES_MAX
const GNOLL_COOLDOWN_SEC := _Spawn.GNOLL_COOLDOWN_SEC

const TROLL_PATROL_RADIUS := 23.4
const TROLL_PATROL_SEC := 9.0
## ── ТАРАН И ДУБИНА (заказ 09.09.2026) ────────────────────────────────────
const TROLL_TRAMPLE_COUNT := 3
## Дубина бьёт ДУГОЙ ПЕРЕД спрайтом: не больше стольких бойцов за удар…
const TROLL_SWEEP_COUNT := 6
const TROLL_SWEEP_ARC_COS := 0.5
const TROLL_SWEEP_REACH_PAD := 0.8
## Накрытые дубиной ОТЛЕТАЮТ (как от тяжёлой конницы), м…
const TROLL_SWEEP_KNOCKBACK := 2.6
## …и ЛЕЖАТ сбитыми с ног столько секунд, потом встают и снова дерутся
const TROLL_KNOCKDOWN_SEC := 2.5
const TROLL_FLASH_PEAK := 0.07
## Пятна и брызги крови поверх подкраски (mm_unit_sprite.blood_spots).
const TROLL_BLOOD_SPOTS := 0.0
## Доля запаса, на которой логово выпускает подмогу, и её численность.
const TROLL_REINFORCE_AT := 0.35
const TROLL_REINFORCE_COUNT := _Spawn.TROLL_REINFORCE_COUNT
## ── АГРО-ЦЕПОЧКА ЛОГОВА (заказ 10.09.2026) ─────────────────────────────────
## Первый же удар по стражу у логова: он агрится на обидчика, и из логова
const TROLL_AGGRO_HELPERS := _Spawn.TROLL_AGGRO_HELPERS
const TROLL_AGGRO_BONUS := _Spawn.TROLL_AGGRO_BONUS
## Задели двоих троллей за это окно — все тролли логова идут на обидчика
const TROLL_SOLIDARITY_SEC := 10.0
const TROLL_AGGRO_RADIUS := 12.0
const TROLL_CHASE_SEC := 10.0
const TROLL_COMBAT_SPEED_MULT := 1.2
## ── КЛИК И КОЛЬЦО (заказ 10.09.2026) ─────────────────────────────────────
const TROLL_PICK_BODY_H := 2.55     # спринт 15: −15 %
const TROLL_PICK_RADIUS := 1.45     # спринт 15: −15 %
const TROLL_RING_SCALE := 3.57      # спринт 15: −15 % вслед за спрайтом
## ── МЕТКА ПОД НОГАМИ ТРОЛЛЯ (заказ владельца 10.09.2026) ──────────────────
const TROLL_RING_OVAL := Vector2(1.45, 0.9)
## ── ТОНКИЙ ОВАЛ ВМЕСТО ТОЛСТЫХ ДУГ (заказ спринта 14) ─────────────────────
const TROLL_FINE_RING_R := 1.32     # спринт 15: −15 % вслед за спрайтом
const TROLL_AIM_HEIGHT := 2.3       # спринт 15: −15 % вслед за спрайтом
## ── ДИСПЕРСИЯ ПО КРУПНОЙ ЦЕЛИ (заказ спринта 14) ──────────────────────────
## Доля выстрелов, которая намеренно уходит В ЗЕМЛЮ рядом с тушей. Без неё
const TROLL_AIM_MISS_CHANCE := 0.22
const TROLL_AIM_MISS_SPREAD := 2.4
## ── ОКРУЖЕНИЕ ─────────────────────────────────────────────────────────────
const TROLL_SURROUND_FOES := 4
const TROLL_SHOVE_SEC := 0.6
const TROLL_SHOVE_PUSH := 0.55
## Разброс угла падения туши, градусы (в обе стороны от вертикали)
const TROLL_DEATH_TILT := 34.0
## Цена смерти тролля нападавшим, в убийствах (три полных отряда копейщиков)
const TROLL_KILL_WORTH := 180

## ── СЕРИЯ ДУБИНЫ СИНХРОНИЗИРОВАНА С КАСАНИЕМ (заказ спринта 15) ─────────────
const TROLL_SWING_HIT_SEC := 0.3
## Урон дубины по всем накрытым (и цели, и дуге) — +20 % (заказ спринта 16)
const TROLL_SWEEP_DMG_MULT := 1.2
const TROLL_SWING_STEP := 0.6
## Тон тела на смерти: «усилить красный оттенок при смерти» — туша краснеет
const TROLL_DEATH_TINT := Color(1.0, 0.55, 0.55)
## ── СТРАЖИ ЛОГОВА ВОСПОЛНЯЮТСЯ ПО ТАЙМЕРУ, ПОКА ПЕНЬ ЖИВ (спринт 15) ────────
const TROLL_RESPAWN_SEC := _Spawn.TROLL_RESPAWN_SEC
const TROLL_GUARDS_MAX := _Spawn.TROLL_GUARDS_MAX
## ── ВОЛНА ЗАЩИТЫ ПНЯ (13.09.2026) ───────────────────────────────────────────
const TROLL_DEFENSE_WAVE := _Spawn.TROLL_DEFENSE_WAVE
const TROLL_DEFENSE_WAVE_CD := _Spawn.TROLL_DEFENSE_WAVE_CD
const TROLL_LAIR_AIM_HEIGHT := 1.8
## Стрела, долетевшая до здания, не торчит, а растворяется за столько секунд
const ARROW_BUILDING_FADE := 0.6
const TROLL_FLASH_COLOR := Color(1.0, 0.22, 0.18)
## ── ОВАЛ ПНЯ (заказ спринта 15) ─────────────────────────────────────────────
const TROLL_LAIR_RING_OVAL := Vector2(1.5, 1.0)
const TROLL_LAIR_RING_SHIFT := 0.45
## Стартовых стражей у дерева
const LAIR_START_TROLLS := _Spawn.LAIR_START_TROLLS
## Декор логова: колья с черепами и кости
const LAIR_SPIKES := 6
const LAIR_BONES := 8
const LAIR_DECOR_RING := 4.0      # м от края коробки дерева до кольца кольев
## Подкраска руины пня (спринт 20): тот же рисунок, «заглохший»
const LAIR_RUIN_TINT := Color(0.42, 0.40, 0.46)
const LAIR_GLADE_R0 := 9.0
const LAIR_GLADE_R1 := 22.0
const LAIR_GLADE_MUSHROOMS := 10
const LAIR_GLADE_STONES := 8
const LAIR_GLADE_BONES := 12
const LAIR_GLADE_BUSHES := 6
const LAIR_GLADE_TREES_R := 26.0
const LAIR_GLADE_TREE_CLUSTERS := 3
const LAIR_GLADE_TREES_PER := 5
## Снесённый пень восстанавливается не раньше чем через столько секунд
const LAIR_REGEN_SEC := _Spawn.LAIR_REGEN_SEC
const LAIR_SPIKE_H := 3.2         # высота кола, м
const LAIR_BONES_M := 2.0         # сторона квада костей, м
## Расчищенная площадка под логово (лес и руда не сажаются)
const LAIR_CLEAR := 36.0
## ── РАСКЛАДКА ПНЕЙ (ТЗ 14.09.2026, п. 3) ──────────────────────────────────
const LAIR_SPOT := Vector2(105.0, 85.0)
const LAIR_OFFSET := Vector2(28.0, 104.0)   # история, не читается
## ВТОРОЙ ПЕНЬ — У КРАСНОГО ИИ (спринт 18): смещение от якоря базы ИИ, метры.
const LAIR_AI_OFFSET := Vector2(-104.0, -10.0)   # история, не читается
## «КРАСНЫЙ ПЕНЬ» — смещение от СЕРЕДИНЫ между якорями игрока и ИИ (ТЗ
const LAIR_AI_SPOT := Vector2(30.0, 0.0)
const HILL_OFFSET := Vector2(24.0, 52.0)

## ── МЕСТЬ ГОБЛИНОВ ────────────────────────────────────────────────────────
## Логово зачищено → раз в REVENGE_INTERVAL_SEC из деревни выходят
const REVENGE_INTERVAL_SEC := _Spawn.REVENGE_INTERVAL_SEC
const REVENGE_SQUADS := _Spawn.REVENGE_SQUADS
const REVENGE_UNIT := _Spawn.REVENGE_UNIT
## Радиус кольца, которым отряды мести встают вокруг дерева, м
const REVENGE_RING := 22.0

## ── СТРОЙ ОРДЫ: КРУГ, А НЕ ПРЯМОУГОЛЬНИК ───────────────────────────────────
const HORDE_SPOT := 1.23
const HORDE_JITTER := 0.45

# ── СТАРТОВАЯ ОРДА: ЯВНЫЙ СПИСОК ОТРЯДОВ ────────────────────────────────────
## ЗДЕСЬ ЗАДАЁТСЯ, ЧТО ИМЕННО СТОИТ У ДЕРЕВНИ В ПЕРВУЮ СЕКУНДУ ПАРТИИ.
const START_SQUADS := _Spawn.GOBLIN_START_SQUADS

const VETERAN_PREFERENCE := ["bonus_attack", "bonus_health", "bonus_defense",
	"bonus_armor", "bonus_speed"]

## ── ЧТЕНИЕ ТАБЛИЦЫ: ОДНА ТОЧКА ВХОДА ────────────────────────────────────────
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

# ── РАСПИСАНИЕ ──────────────────────────────────────────────────────────────
## До этой минуты орда СПИТ: не ищет цели, не считает путь, не тикает мозгами.
const DORMANT_UNTIL_SEC := 0.0
## Как часто думает вожак орды, сек
const THINK_INTERVAL := 2.0

# ── ГЛАВНЫЙ ЦИКЛ ОРДЫ (спринт 17) ───────────────────────────────────────────
const GARRISON_SQUADS := _Spawn.GOBLIN_GARRISON_SQUADS
const MINE_OFFSET := 25.0
const MINE_GUARD := _Spawn.GOBLIN_MINE_GUARD
## Охрана патрулирует кольцом такого радиуса вокруг рудника, смена точки раз в
const MINE_GUARD_PATROL_R := 9.0
const MINE_GUARD_PATROL_SEC := 10.0
## Тревога рудника: на столько секунд ВСЯ орда (кроме гарнизона и лечащихся)
const MINE_ALARM_SEC := 45.0
## Сколько отрядов держат захваченный рудник на холме резервом
const EXPAND_MINE_SQUADS := 1
## Разведка: один отряд (конный, если есть) обходит точки интереса
const SCOUT_SQUADS := 1
const SCOUT_SIGHT := 30.0
const SCOUT_ARRIVE := 10.0
const SCOUT_DWELL_SEC := 6.0
const RAID_INTERVAL_SEC := _Spawn.GOBLIN_RAID_INTERVAL_SEC
const RAID_SQUADS_SMALL := 1
const RAID_SQUADS_BIG := 3           # спринт 20: диверсии по 1-3 отряда
const RAID_HUNT_RADIUS := 70.0
const RAID_RETREAT_HP := 0.55
const RAID_FLEE_FOES := 12
const RAID_FLEE_RADIUS := 18.0
const RAID_MAX_SEC := 70.0
## Рейд без единой добычи у известной базы дольше этого — домой (спринт 20)
const RAID_IDLE_SEC := 12.0
const HARASS_MIN_SEC := 90.0
## ── ТАЙМИНГИ (уточнение владельца 11.09.2026) ──────────────────────────────
const PEACE_SEC := _Spawn.GOBLIN_PEACE_SEC
## Перемирие партии (спринт 20): красный ИИ и орда не нападают первые минуты.
const TRUCE_SEC := PEACE_SEC
## ── ЗАЩИТА КРАСНОГО ИИ (спринт 20, модуль 6.2) ──────────────────────────
const AI_PROTECT_SEC := 1800.0
const PATROL_BORDER_R := 26.0
const PATROL_BORDER_POINTS := 8
const PATROL_BORDER_SEC := 14.0
## ГЕНЕРАЛЬНЫЙ ШТУРМ — не раньше 35-й минуты; до того — центр, рудники, рейды
const ASSAULT_EARLIEST_SEC := _Spawn.GOBLIN_ASSAULT_EARLIEST_SEC
const SCOUT_UNITS := 2
const SCOUT_HARASS_SEC := 8.0
const SCOUT_SORTIE_SEC := 45.0
## Радиус, в котором «центр карты» считается взятым
const CENTER_RADIUS := 30.0
const BUILDING_HUNT_RADIUS := 70.0

# ── ТАКТИКА ШТУРМА БАЗЫ (заказ владельца, 10.09.2026) ───────────────────────
const ASSAULT_TACTICS := true
const ASSAULT_STANDOFF := 30.0
## Постройки дальше этого от точки базы к «этой базе» не относятся
const ASSAULT_BASE_RADIUS := 90.0
## Шаг между отрядами на линии сбора, м
const ASSAULT_LINE_STEP := 9.0
const ASSAULT_ASSEMBLE_RADIUS := 12.0
const ASSAULT_ASSEMBLE_FRAC := 0.7
const ASSAULT_ASSEMBLE_TIMEOUT := 45.0
const PROBE_FLANK_OFFSET := 22.0
const PROBE_INFANTRY_SEC := 8.0
const PROBE_CAVALRY_SEC := 5.0
const PROBE_RECOVER_SEC := 5.0
const PROBE_CYCLES := 2
const HR_CAVALRY_SEC := 6.0
const HR_CAVALRY_BACK_SEC := 6.0
const HR_BRAWL_SEC := 20.0
const HR_LOSING_DROP := 0.25
## Паттерн В «веер»: сдвиг фланговых групп от центра, каскад между группами
const FAN_OFFSET := 24.0
const FAN_CASCADE_SEC := 1.5
const ASSAULT_RETREAT_HP := 0.5
const ASSAULT_REARM_HP := 0.9
const ASSAULT_CAMP_FAR := 120.0
const ASSAULT_CAMP_DIST := 70.0
const CAMP_HEAL_RADIUS := 30.0
const CAMP_HEAL_PER_SEC := 2.0
const VANGUARD_LEAD := 25.0
const VANGUARD_SIGHT := 30.0
const VANGUARD_REISSUE_DIST := 8.0
## Оборона деревни (уточнение владельца): угроза замечается в DEFEND_RADIUS +
const DEFEND_ALERT_PAD := 20.0
const DEFEND_LINE_DIST := 18.0
const DEFEND_ENGAGE := 16.0
const DEFEND_CAV_FLANK := 20.0
const DEFEND_CAV_STRIKE_SEC := 6.0
const DEFEND_CAV_BACK_SEC := 5.0

# ── ОВЦЫ У ЛОГОВА И ГОЛОД ТРОЛЛЯ (заказ владельца, 10.09.2026) ─────────────
## Стартовое стадо, прирост по таймеру (штук раз в SHEEP_BREED_SEC) и потолок
const SHEEP_START := _Spawn.SHEEP_START
const SHEEP_BREED_SEC := _Spawn.SHEEP_BREED_SEC
const SHEEP_BREED_COUNT := _Spawn.SHEEP_BREED_COUNT
const SHEEP_MAX := 10
## Выпас: дальше этого от логова овца не уходит
const SHEEP_GRAZE_RADIUS := 26.0
## ── ПАССИВНОЕ РАЗМНОЖЕНИЕ ОВЦЫ (заказ владельца 10.09.2026) ───────────────
## ── РАЗМНОЖЕНИЕ СТАДА ИГРОКА (заказ спринта 13) ───────────────────────────
## Перебежка раз в SHEEP_HOP_SEC на 5–10 м, скорость перехода
const SHEEP_BREED_CASTLE_SEC := 300.0
const SHEEP_BREED_PEN_SEC    := 150.0

const SHEEP_SELF_BREED_SEC := 150.0
const SHEEP_CALM_SEC := 25.0
const SHEEP_HOP_SEC := 10.0
const SHEEP_HOP_MIN := 5.0
const SHEEP_HOP_MAX := 10.0
const SHEEP_SPEED := 1.1
## Пиксель овцы: рисунок 38 px в кадре 128 → ~0.9 м ростом
const SHEEP_PIXEL_SIZE := 0.0192
## Тролль голодает раз в TROLL_HUNGER_SEC (±20 %) или когда стадо больше
const TROLL_HUNGER_SEC := 150.0
## ── ГОЛОС ТРОЛЛЯ (спринт 18) ─────────────────────────────────────────────
const TROLL_GROWL_MIN_SEC := 12.0
const TROLL_GROWL_MAX_SEC := 20.0
const TROLL_GROWL_MARCH_P := 0.35
const TROLL_GROWL_FIGHT_P := 0.12
const LAUGH_SIGHT := 18.0
## Хор смеха — только в малой стычке: отрядов орды в LAUGH_SIGHT не больше
const LAUGH_MAX_SQUADS := 3
const TROLL_HUNGRY_FLOCK := 5
## ── ОТАРА ЗАНОВО (спринт 18): стадо логова вырезано или съедено целиком —
## пень ждёт SHEEP_RESPAWN_SEC и выпускает новую отару из SHEEP_RESPAWN_COUNT
const SHEEP_RESPAWN_SEC := _Spawn.SHEEP_RESPAWN_SEC
const SHEEP_RESPAWN_COUNT := _Spawn.SHEEP_RESPAWN_COUNT
## ── РЕЙД ТРОЛЛЯ ЗА ОВЦАМИ (спринт 18): у стороны (игрок или красный ИИ)
const TROLL_RAID_SHEEP := 30
const TROLL_RAID_EAT := 3
const TROLL_RAID_HERD := 5
const TROLL_RAID_SMASH_R := 14.0
const TROLL_RAID_SMASH_SEEK := 45.0
const TROLL_RAID_SMASH_SEC := 60.0
const TROLL_RAID_COOLDOWN_SEC := 300.0
const TROLL_RAID_CHECK_SEC := 6.0
const TROLL_RAID_HOME_R := 10.0
## Второе логово — у базы красного ИИ (зеркально по X: перед рекой, внизу)
const LAIR_AI_ENABLED := _Spawn.LAIR_AI_ENABLED
## ── САМОВОЗОБНОВЛЯЕМЫЙ РЕСУРС (уточнение владельца): у стороны 30+ овец —
const TROLL_RAID_SPAWN := _Spawn.TROLL_RAID_SPAWN
const TROLL_RAID_REWARD := _Spawn.TROLL_RAID_REWARD
const SHEEP_PRESSURE_CHECK_SEC := 6.0
const TROLL_EAT_RANGE := 2.8
const TROLL_EAT_HEAL := 0.2
## Дальше этого от деревни отряды в обороне не отходят
const DEFEND_RADIUS := 40.0

# ── ОТХОД В ХИЖИНУ ──────────────────────────────────────────────────────────
const RETREAT_STRENGTH := 0.15
const NO_RETREAT_IN_MELEE := true

# ── СПЯЧКА ──────────────────────────────────────────────────────────────────
const DORMANT_SLEEP_PHYSICS := true

## ── МЕСТО БОЙЦА В ТОЛПЕ ─────────────────────────────────────────────────────
static func horde_offset(idx: int, total: int, seed_id: int) -> Vector2:
	var n: int = maxi(total, 1)
	# Радиус диска — из площади на бойца: pi*R^2 = n * SPOT^2
	var r_max: float = sqrt(float(n) / PI) * HORDE_SPOT
	var ang: float = float(idx) * 2.39996323                      # золотой угол
	var r: float = sqrt((float(idx) + 0.5) / float(n)) * r_max
	var h1: float = fposmod(sin(float(idx) * 12.9898 + float(seed_id) * 4.1414) * 43758.5453, 1.0)
	var h2: float = fposmod(sin(float(idx) * 78.2330 + float(seed_id) * 7.7373) * 24634.6345, 1.0)
	var j: float = HORDE_SPOT * HORDE_JITTER
	return Vector2(cos(ang) * r + (h1 - 0.5) * 2.0 * j,
		sin(ang) * r + (h2 - 0.5) * 2.0 * j)

## Габарит толпы отряда, м (нужен обороне и стенду)
static func horde_radius(total: int) -> float:
	return sqrt(float(maxi(total, 1)) / PI) * HORDE_SPOT + HORDE_SPOT * HORDE_JITTER

## ── МЕСТА ХИЖИН ─────────────────────────────────────────────────────────────
## Сетка в шахматку вокруг центра. Возвращает смещения от центра деревни
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

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## БОЛЬШОЙ ГОБЛИН (заказ владельца, 13.09.2026)
const BIG_SIZE_SCALE := 2.4             # 13.09.2026: −20 % (было 3.0 — втрое крупнее людского)
const BIG_PIXEL_SIZE := 0.0108 * BIG_SIZE_SCALE
const BIG_SWEEP_ARC_COS := 0.5          # cos(60°): половина сектора 60°
const BIG_SWEEP_HALF_W := 1.5           # «3 клетки» в ширину, полуширина
const BIG_SWEEP_MAX := 6                # скольких накрывает один взмах
const BIG_KNOCKBACK := 1.5              # отброс, м («1-2 клетки»)
const BIG_COMBO_EVERY := 3
const BIG_COMBO_GAP := 0.45             # пауза внутри двойного удара, с
const BIG_SCAN_LEAD := 0.6
## Личный радиус расталкивания: туша шире гоблина и не должна тереться
const BIG_SEP_MULT := 2.2
const BIG_FINE_RING_R := 0.75
const BIG_RING_OVAL := Vector2(1.35, 0.9)
## Вспышка удара — лёгкая красная, как у тролля, а не белая
const BIG_FLASH_PEAK := 0.35
const BIG_FLASH_COLOR := Color(1.0, 0.22, 0.18)
## Отряд туш — пять (заказ). Ширина строя и шаг: они большие, их надо разводить
const BIG_SQUAD_COLS := 3
const BIG_SQUAD_SPACING := 2.2
## Сколько отрядов туш где стоит (заказ):
const BIG_WAVE_SQUADS := _Spawn.BIG_WAVE_SQUADS
const BIG_BASE_SQUADS := _Spawn.BIG_BASE_SQUADS
const BIG_DEFENSE_SQUADS := _Spawn.BIG_DEFENSE_SQUADS
## Тяжёлый шаг: своя категория звука, редкий и низкий
const BIG_STEP_SEC := 1.1
## ── ПЕРЕХВАТ НА МАРШЕ (ТЗ 14.09.2026, п. 6) ───────────────────────────────
## Туша, идущая по вейпоинту, получила урон или заметила чужого в
const BIG_AGGRO_RADIUS := 18.0
const BIG_HUNT_RADIUS := 28.0
const BIG_PURSUIT_LIMIT := 60.0
const BIG_HUNT_TICK := 0.5
## Вес туши как цели у стрелков (ТЗ 14.09.2026, п. 10: приоритет ×2)
const BIG_TARGET_PRIO := 2.0

# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# ── ДРЕМЛЮЩИЙ РЕЗЕРВ ОРДЫ (DormantReserve.gd) ────────────────────────────────
# СЦЕНАРИЙ ГЛОБАЛЬНОГО ИИ КАРТЫ (заказ владельца, 13.09.2026)
const RESERVE_ENABLED := _Spawn.GOBLIN_RESERVE_ENABLED
const RESERVE_SQUADS := _Spawn.GOBLIN_RESERVE_SQUADS
const RESERVE_BACK := 22.0
const RESERVE_COLS := 5
const RESERVE_STEP := 12.0
## Такт проверки резерва (не покадрово): угроза деревне ищется по сетке ядра
const RESERVE_TICK_SEC := 0.75
const RESERVE_WAKE_RADIUS := 44.0     # от центра деревни
const RESERVE_WAKE_FOES := 6          # столько чужих боевых — «штурм», а не разведчик
## Ушли чужие — через столько секунд без угрозы резерв идёт на посты
const RESERVE_CALM_SEC := 8.0
## Отряд считается вернувшимся на пост в этом радиусе — и снова засыпает
const RESERVE_HOME_RADIUS := 6.0
const RESERVE_HEAL_FRAC := 0.03
## Сколько конных отрядов вожак вправе взять на одну вылазку
const RESERVE_LEND_MAX := 2

# ── ГНОЛЛЫ: ЗОНА ОТВЕТСТВЕННОСТИ И ОХОТА НА РАБОЧИХ (GnollAI.gd) ────────────
## ── ЗОНА СЖАТА ДО ЛЕСА У ПНЯ (ТЗ 14.09.2026, п. 5) ────────────────────────
const GNOLL_ZONE_RADIUS := 48.0
const GNOLL_ZONE_TOWARD_BASE := 8.0
const GNOLL_FORD_PAD := 14.0
## Патруль — КРУГОВОЙ МАРШ вокруг пня (ТЗ 14.09.2026, п. 5): угол шагает на
const GNOLL_PATROL_STEP_DEG := 40.0
const GNOLL_PATROL_TREE_SNAP := 9.0
## Гнолл, потерявший пень (снесён, загрузка партии), подхватывает ближайший
const GNOLL_HOME_ADOPT_R := 60.0
const TROLL_CHASE_RADIUS := 45.0
## Охота: раз в GNOLL_HUNT_TICK контроллер ищет рабочих чужой стороны в
const GNOLL_HUNT_TICK := 0.75
const GNOLL_HUNT_RADIUS := 45.0   # 14.09.2026: не дальше зоны леса
const GNOLL_HUNTERS_PER_PREY := 2
