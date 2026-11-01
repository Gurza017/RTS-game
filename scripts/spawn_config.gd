extends RefCounted
## ЕДИНЫЙ КОНФИГ СПАВНА: кто, сколько и когда появляется, по всем сущностям и
## фракциям. Только параметры; поведение — goblin_config / ai_start_army_limit,
## они читают числа ОТСЮДА (const X := _Spawn.X). Подключение: preload.
## Формат отрядного списка: {"unit", "count" (0 = уставной размер), "vet", "picks"}
## История и обоснования чисел — docs/config_notes/spawn_config.md

# ── ГОБЛИНЫ (орда) ──
## Уставной размер отряда по роду, бойцов
const GOBLIN_SQUAD_SIZE := {
	"goblin_spearman": 100,
	"goblin_rider":    50,
	"gnoll":           12,
	"big_goblin":      7,   # ТЗ 31.10.2026: семь туш в отряде (было 5)
	"pig_boss":        31,   # свинобосс + свита наездников (goblin_config.BOSS_*)
}
## Стартовая орда у деревни (старая система, см. заметки)
const GOBLIN_START_SQUADS := [
	{"unit": "goblin_spearman", "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_spearman", "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_spearman", "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_spearman", "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_rider",    "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_spearman", "count": 0, "vet": 0, "picks": 0},
	{"unit": "goblin_spearman", "count": 0, "vet": 0, "picks": 0},
	{"unit": "goblin_rider",    "count": 0, "vet": 0, "picks": 0},
	{"unit": "goblin_spearman", "count": 0, "vet": 0, "picks": 0},
	{"unit": "goblin_rider",    "count": 0, "vet": 0, "picks": 0},
	{"unit": "big_goblin",      "count": 0, "vet": 0, "picks": 0},
]
## Гарнизон деревни в мирную фазу: отрядов ветеранских копейщиков
const GOBLIN_GARRISON_SQUADS := 3
## Найм в хижинах: цена одного отряда в еде и время найма, с
const GOBLIN_SQUAD_FOOD_COST := 90.0
const GOBLIN_SQUAD_BUILD_SEC := 90.0
## Охрана рудника орды (старая система)
const GOBLIN_MINE_GUARD := [
	{"unit": "goblin_rider",    "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_spearman", "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_spearman", "count": 0, "vet": 3, "picks": 3},
]
## Спящий резерв за лагерем (будит только штурм лагеря) и его состав
const GOBLIN_RESERVE_ENABLED := true
const GOBLIN_RESERVE_SQUADS := [
	{"unit": "goblin_rider",    "count": 0, "vet": 1, "picks": 1},
	{"unit": "goblin_rider",    "count": 0, "vet": 1, "picks": 1},
	{"unit": "goblin_rider",    "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_rider",    "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_rider",    "count": 0, "vet": 4, "picks": 4},
	{"unit": "goblin_rider",    "count": 0, "vet": 4, "picks": 4},
	{"unit": "big_goblin",      "count": 0, "vet": 0, "picks": 0},
	{"unit": "goblin_spearman", "count": 0, "vet": 0, "picks": 0},
	{"unit": "goblin_spearman", "count": 0, "vet": 0, "picks": 0},
	{"unit": "goblin_spearman", "count": 0, "vet": 0, "picks": 0},
	{"unit": "goblin_spearman", "count": 0, "vet": 0, "picks": 0},
	{"unit": "goblin_spearman", "count": 0, "vet": 0, "picks": 0},
]
## Большие гоблины (туши): отрядов в волне пня, на базе, в защите пня
const BIG_WAVE_SQUADS := 1
const BIG_BASE_SQUADS := 1
const BIG_DEFENSE_SQUADS := 1
## Расписание орды: мирная фаза (= перемирие), с; не раньше какой секунды штурм
const GOBLIN_PEACE_SEC := 900.0
const GOBLIN_ASSAULT_EARLIEST_SEC := 1800.0
## Потолок беспокойства: дольше HARASS_MAX_SEC в harass — наступление тем, что
## есть, но не меньше ASSAULT_MIN_SQUADS отрядов
const GOBLIN_HARASS_MAX_SEC := 480.0
const GOBLIN_ASSAULT_MIN_SQUADS := 6
## Резерв не даёт конницу взаймы, когда отрядов в нём меньше
const GOBLIN_RESERVE_LEND_FLOOR := 8
## Пауза между набегами орды (старая система), с
const GOBLIN_RAID_INTERVAL_SEC := 40.0
## Разведка всадников: вылазки 1-3 конных отрядов веером вокруг базы игрока
const SCOUT_UNITS := 0                    # бойцов в отряде; 0 — уставной (GOBLIN_SQUAD_SIZE)
const SCOUT_MAX_SQUADS := 3               # потолок пула разведчиков, отрядов
const SCOUT_SORTIE_WEIGHTS := [0.4, 0.4, 0.2]   # веса жребия: 1 / 2 / 3 отряда в вылазку
const SCOUT_SORTIE_SEC := 22.0            # передышка дома между вылазками, с
const SCOUT_HARASS_SEC := 12.0            # длительность налёта на добычу, с
const SCOUT_RUN_SEC := 8.0                # отход после налёта (hit-and-run), с
const SCOUT_SORTIE_MAX_SEC := 150.0       # потолок одной вылазки — потом домой, с
const SCOUT_ORBIT_R := 42.0               # радиус орбиты вокруг базы игрока, м
const SCOUT_ORBIT_POINTS := 6             # точек на орбите
const SCOUT_HUNT_R := 38.0                # поиск добычи от центра отряда, м
const SCOUT_LONE_R := 18.0                # «одинокий» стрелковый отряд: без пехоты ближе, м
## Месть за зачищенный пень: раз в интервал — столько отрядов пехоты
const REVENGE_INTERVAL_SEC := 600.0
const REVENGE_SQUADS := 10
const REVENGE_UNIT := "goblin_spearman"

# ── НОВАЯ ОРДА (лагерь, еда, волны; логика — scripts/goblin/GoblinAI.gd) ──
## Потолок живых бойцов орды НА ВСЮ КАРТУ (охрана, волны, пни); отряд урезается
## до остатка, ноль — не родится (Main.spawn_goblin_squad)
const HORDE_CAP := 1800
## Потолок бойцов в волнах и на площадке сбора (охрана рудников не в счёт)
const HORDE_FIELD_CAP := 900
## ── ЛАГЕРЬ ──
## Главная хата: запас жизни, размер относительно хижины, самопочинка в секунду
## и пауза после удара, прежде чем она начнётся, с
const CHIEF_HUT_HP := 20000.0
const CHIEF_HUT_SIZE_MULT := 2.0
const CHIEF_HUT_REGEN_PER_SEC := 40.0
const CHIEF_HUT_REGEN_DELAY_SEC := 15.0
## Хижины — серпом выше главной хаты (к -Z): число, радиус дуги, м, и размах
## дуги в градусах (симметрично от вертикали)
const CAMP_HUTS := 10
const CAMP_ARC_R := 19.0
const CAMP_ARC_DEG := 150.0
## ── ЭКОНОМИКА ЕДЫ ──
## Доход еды в минуту с хижины и с главной хаты
const HUT_FOOD_MIN := 12.0
const CHIEF_FOOD_MIN := 100.0
## Рост дохода: +RAMP_PER_HOUR долей за час партии, потолок множителя RAMP_MAX
const FOOD_RAMP_PER_HOUR := 1.0
const FOOD_RAMP_MAX := 2.5
## Содержание: еды в минуту за каждого живого бойца волн и площадки сбора
const FOOD_UPKEEP_PER_UNIT_MIN := 0.06
## Потолок копилки еды (перемирие не копит гигантскую первую волну)
const FOOD_BANK_MAX := 1600.0
## Цены отрядов в еде (отряд — уставной размер GOBLIN_SQUAD_SIZE)
const SQUAD_PRICE := {
	"goblin_spearman": 300.0,
	"goblin_rider":    360.0,
	"big_goblin":      280.0,
	"pig_boss":        900.0,   # отряд свинобосса (свита — ветераны)
}
## Между рождениями двух отрядов волны не меньше, с
const SQUAD_SPAWN_GAP_SEC := 4.0
## Площадка сбора: смещения слотов от центра лагеря (x, z), м; шаг шире
## диаметра толпы из 100 (≈15 м), в стороне от рудника лагеря и его охраны
const MUSTER_SLOTS := [
	Vector2(-2.0, 22.0), Vector2(16.0, 22.0), Vector2(34.0, 22.0),
	Vector2(5.0, 39.0), Vector2(23.0, 39.0), Vector2(41.0, 39.0),
	Vector2(-2.0, 56.0), Vector2(16.0, 56.0), Vector2(34.0, 56.0),
	Vector2(59.0, 22.0), Vector2(59.0, 39.0), Vector2(59.0, 56.0),
]
## Стартовый резерв волн: оплаченные отряды спят на площадке сбора, первые
## планы волн берут их даром (GoblinAI._production_tick)
const START_RESERVE := [
	"goblin_spearman", "goblin_spearman", "goblin_spearman", "goblin_spearman",
	"goblin_rider", "goblin_rider", "goblin_rider",
	"big_goblin", "big_goblin", "big_goblin",
]
## Темп волн: между выходами не меньше GAP_MIN; дольше GAP_MAX без выхода —
## уходит то, что набрано, с
const WAVE_GAP_MIN_SEC := 420.0
const WAVE_GAP_MAX_SEC := 600.0
## ── ВОЛНЫ ──
## Шаблоны состава волн и порядок их чередования по кругу
const WAVE_TEMPLATES := {
	"scout": ["goblin_rider", "goblin_rider"],
	"small_a": ["goblin_spearman", "goblin_spearman", "big_goblin"],
	"small_b": ["goblin_spearman", "goblin_rider"],
	"small_c": ["goblin_spearman", "goblin_spearman", "goblin_rider"],
	"big_a": ["goblin_spearman", "goblin_spearman", "goblin_spearman", "big_goblin", "goblin_rider"],
	"big_b": ["goblin_spearman", "goblin_spearman", "big_goblin", "goblin_rider", "goblin_rider"],
	# Волна полководца: план берётся после goblin_config.BOSS_FROM_SEC, пока босс не жив (GoblinAI._new_plan)
	"boss": ["goblin_spearman", "goblin_spearman", "goblin_rider", "big_goblin", "pig_boss"],
}
const WAVE_PATTERN := ["scout", "small_a", "big_a", "small_b", "small_c", "big_b"]
## Волна, не набравшая состав за столько секунд (упёрлась в потолок), уходит тем, что есть
const WAVE_ASSEMBLE_MAX_SEC := 240.0
## Сколько волн одновременно в поле
const WAVES_MAX_ACTIVE := 2
## Срок волны, с: дольше — домой на площадку сбора (бойцы вливаются в следующую)
const WAVE_MAX_SEC := 420.0
## Точка развёртывания — за столько м до цели по линии подхода
const WAVE_STAGE_DIST := 32.0
## Точка захода кавалерии во фланг/тыл — в стольких м сбоку/сзади от цели
const WAVE_FLANK_DIST := 30.0
## Ложный отход (один раз): через столько с рубки или при такой доле потерь —
## отход на FEINT_BACK м, перегруппировка FEINT_REGROUP_SEC и второй удар
const WAVE_FEINT_SEC := 14.0
const WAVE_FEINT_LOSS := 0.25
const WAVE_FEINT_BACK := 24.0
const WAVE_FEINT_REGROUP_SEC := 8.0
## Брод: волна держит брод столько с; брод «отобран» чужими, если у его середины
## их больше FORD_TAKEN_FOES (тогда штурм брода — первым)
const WAVE_FORD_HOLD_SEC := 150.0
const FORD_TAKEN_FOES := 12
## ── ОХРАНА РУДНИКОВ (стационарная, спит в F_DORMANT) ──
## Состав охраны рудника лагеря и ничейных рудников сторон
const CAMP_MINE_GUARD := [
	{"unit": "goblin_spearman", "count": 0, "vet": 2, "picks": 2},
	{"unit": "goblin_spearman", "count": 0, "vet": 2, "picks": 2},
	{"unit": "big_goblin",      "count": 0, "vet": 2, "picks": 2},
	{"unit": "big_goblin",      "count": 0, "vet": 2, "picks": 2},
	{"unit": "big_goblin",      "count": 0, "vet": 2, "picks": 2},
	{"unit": "goblin_rider",    "count": 0, "vet": 4, "picks": 4},
	{"unit": "goblin_rider",    "count": 0, "vet": 4, "picks": 4},
	{"unit": "goblin_rider",    "count": 0, "vet": 4, "picks": 4},
]
const TERRITORY_MINE_GUARD := [
	{"unit": "goblin_spearman", "count": 0, "vet": 2, "picks": 2},
	{"unit": "goblin_spearman", "count": 0, "vet": 2, "picks": 2},
	{"unit": "goblin_rider",    "count": 0, "vet": 2, "picks": 2},
	{"unit": "goblin_rider",    "count": 0, "vet": 2, "picks": 2},
]
## Охрана просыпается на удар по руднику или чужого ближе WAKE_R, м; тихо
## CALM_SEC — одним приказом на пост; «дома» — ближе HOME_R к посту, м, или
## через HOME_TIMEOUT_SEC, тогда засыпает
const GUARD_WAKE_R := 22.0
const GUARD_CALM_SEC := 12.0
const GUARD_HOME_R := 7.0
const GUARD_HOME_TIMEOUT_SEC := 30.0
## Ближний край толпы охраны не ближе стольких м к руднику (радиус захвата
## Mine.CAPTURE_RADIUS 8 — иначе охрана захватила бы ничейный рудник себе)
const GUARD_MINE_CLEAR := 10.0
## Тревога лагеря: чужой ближе стольких м к главной хате или хижине — будятся
## отряды площадки сбора; тихо GUARD_CALM_SEC — назад в слоты и спать
const CAMP_ALARM_R := 45.0

# ── ПНИ (логова): тролли, гноллы, овцы ──
const LAIR_AI_ENABLED := true             # второй («красный») пень
const LAIR_START_TROLLS := 1              # стражей при появлении пня
const TROLL_GUARDS_MAX := 2               # потолок постоянной охраны
const TROLL_RESPAWN_SEC := 300.0          # +1 страж раз в столько секунд
const TROLL_DEFENSE_WAVE := 3             # волна защиты: троллей сверх охраны
const TROLL_DEFENSE_WAVE_CD := 600.0      # откат волны защиты, с
const TROLL_REINFORCE_COUNT := 1          # подмога на трети запаса (бонусная пара)
const TROLL_AGGRO_HELPERS := 0            # помощников по первому удару (снято)
const TROLL_AGGRO_BONUS := 0              # бонусных стражей по первому удару (снято)
const TROLL_RAID_SPAWN := 1               # троллей за удачный рейд за овцами
const TROLL_RAID_REWARD := 3              # стражей в награду за рейд
const LAIR_REGEN_SEC := 600.0             # не раньше чего пень восстанавливается после падения
## Заморозка пня за рекой: пень на чужом берегу считает «всухую»; игрок перешёл
## брод — порционная разморозка
const LAIR_FREEZE_ENABLED := true
const LAIR_THAW_STEP_SEC := 3.0           # одна порция (тролль / отряд) в столько секунд
const LAIR_THAW_CHECK_SEC := 2.0          # как часто ищем игрока на том берегу, с
const LAIR_THAW_BANK_MARGIN := 2.0        # метров за сухой кромкой русла = «перешёл»
## Гноллы у пней — по часам, с общим потолком: каждый пень раз в SPAWN_SEC
## выпускает SPAWN_MIN..MAX отрядов (чередуя), пока живых отрядов от всех пней
## меньше MAX_STUMP_GNOLLS; у потолка место проверяется раз в RECHECK_SEC
const GNOLL_START_SQUADS := 2             # стартовая стая на пень, отрядов (в потолок входит)
const GNOLL_SPAWN_SEC := 120.0
const GNOLL_SPAWN_MIN := 1
const GNOLL_SPAWN_MAX := 2
const GNOLL_SPAWN_RECHECK_SEC := 10.0
const MAX_STUMP_GNOLLS := 6               # живых отрядов гноллов от всех пней разом
## Прежние волны по удару в пень (ручки отката и старые стенды)
const GNOLL_WAVE_SQUADS := 3              # отрядов в волне
const GNOLL_WAVE_SEC := 180.0             # пауза между волнами, с
const GNOLL_WAVES_MAX := 3                # волн на пень
const GNOLL_COOLDOWN_SEC := 600.0         # откат серии волн, с
const GNOLL_MAX_ALIVE := 72
# ── ПНИ (ТЗ 31.10.2026, LairDirector) ──
## Множитель охраны пня при lair_guard_x3
const LAIR_GUARD_MULT := 3
## Поход к броду: троллей и отрядов гноллов за раз; период ближнего (первого) и дальнего пня, с
const LAIR_SORTIE_TROLLS := 3
const LAIR_SORTIE_GNOLLS := 3
const LAIR_SORTIE_NEAR_SEC := 600.0
const LAIR_SORTIE_FAR_SEC := 420.0
## Пятак: за выходом из брода на левом берегу, м; потолок живых на пятаке (троллей / отрядов гноллов)
const LAIR_PATCH_OUT := 14.0
const LAIR_PATCH_TROLLS_MAX := 9
const LAIR_PATCH_GNOLLS_MAX := 9
## Награда за снесённый игроком пень, золото; подъём слитка, м; срок, с
const LAIR_REWARD_GOLD := 5000
const LAIR_REWARD_RISE := 3.0
const LAIR_REWARD_SEC := 1.6
## Оживление: через сколько после сноса; кто внутри; шаг вываливания, с
const LAIR_REVIVE_SEC := 1800.0
const LAIR_REVIVE_TROLLS := 7
const LAIR_REVIVE_GNOLLS := 20
const LAIR_REVIVE_STEP_SEC := 1.0               # живых гноллов на пень, потолок (волна сверх — не выходит)
## Овцы у пня: стартовое стадо, приплод (раз в BREED_SEC по BREED_COUNT) и
## пополнение после потерь (через RESPAWN_SEC по RESPAWN_COUNT)
const SHEEP_START := 5
const SHEEP_BREED_SEC := 300.0
const SHEEP_BREED_COUNT := 2
const SHEEP_RESPAWN_SEC := 20.0
const SHEEP_RESPAWN_COUNT := 5

# ── КРАСНЫЙ ИИ (люди) ──
## Лимит отрядов по роду войск (сколько ИИ доводит до строя); 29 отрядов —
## ТЗ 27.10.2026 (аудит, разд. 2: «25-30 отрядов, эндгейм-давление»), прежде 10/5/6
const AI_SQUAD_LIMIT := {
	"spearman": 14,
	"archer":   7,
	"warrior":  8,
}
## Потолок рабочих и сколько их выходит на карту в первую секунду
const AI_WORKER_LIMIT := 40
const AI_START_WORKERS := 5
## Стартовые отряды В ПОЛЕ (пусто = без полевой армии на старте)
const AI_START_SQUADS := []
## ── СТАРТОВАЯ ОБОРОНА КРЕПОСТИ ──
## Башни на кольце вокруг крепости: дистанция от центра замка, м, и угол от оси
## «замок → центр карты» (плюс — вправо от фасада); в каждой сразу гарнизон
const AI_HOME_DEFENSE_ENABLED := true
const AI_HOME_TOWERS := [
	{"dist": 20.0, "angle_deg": -35.0},
	{"dist": 15.0, "angle_deg":  60.0},
	{"dist": 10.0, "angle_deg": -115.0},
]
const AI_HOME_TOWER_ARCHERS := 1        # отрядов лучников в каждой башне
const AI_HOME_CASTLE_ARCHERS := 1       # отрядов лучников на крыше крепости
## Охрана крепости (спит до штурма); "vet" — уровень по VET_BANNER_TIERS
const AI_HOME_GUARD_SQUADS := [
	{"unit": "warrior",  "count": 0, "vet": 4, "picks": 4},
	{"unit": "warrior",  "count": 0, "vet": 4, "picks": 4},
	{"unit": "spearman", "count": 0, "vet": 2, "picks": 2},
	{"unit": "spearman", "count": 0, "vet": 2, "picks": 2},
	{"unit": "spearman", "count": 0, "vet": 2, "picks": 2},
]
## ── ОБОРОНА БАЗЫ В ТРИ УРОВНЯ ──
## 1 — охрана кольцом вокруг крепости; 2 — гарнизон линиями поперёк курса
## на базу игрока; 3 — остальные постами у передних башен (RedAI.perimeter_post)
const AI_HOME_RING_DIST := 13.0         # уровень 1: радиус кольца охраны, м
const AI_HOME_RING_CLEAR := 4.5         # пост кольца не ближе стольких м к башне/жиле
const AI_HOME_LINE_DIST := 34.0         # уровень 2: первая линия гарнизона от замка, м
const AI_HOME_LINE_SQUADS := 3          # отрядов в линии
const AI_HOME_LINE_ROWS := 2            # линий
const AI_HOME_LINE_GAP := 3.0           # просвет между блоками линии, м
const AI_HOME_LINE_ROW_GAP := 4.0       # просвет между линиями, м
const AI_HOME_TOWER_POST_DIST := 5.0    # уровень 3: пост перед башней, м от неё
## Чужой боевой ближе стольких м к ЛЮБОМУ посту гарнизона — тревога базы
const AI_HOME_GUARD_POST_ZONE := 12.0
## ── ОТВЕТНЫЙ УДАР (TOTAL_RETALIATION) ──
## Потеряно LOSSES моделей (счёт от прошлого удара) — вся полевая армия на
## RETALIATION_SEC идёт Attack-Move к источнику потерь; следующий не раньше COOLDOWN
const AI_RETALIATION_LOSSES := 60
const AI_RETALIATION_SEC := 120.0
const AI_RETALIATION_COOLDOWN_SEC := 180.0
## Условия удара по силе: полевых отрядов не меньше MIN_SQUADS; своих в поле не
## меньше ADVANTAGE × чужих в SCAN_R от источника потерь; потери у своей крепости
## (HOME_R) — без проверки силы; отказ переспрашивается через RECHECK_SEC
const AI_RETALIATION_MIN_SQUADS := 8
const AI_RETALIATION_ADVANTAGE := 1.0
const AI_RETALIATION_SCAN_R := 45.0
const AI_RETALIATION_HOME_R := 45.0
const AI_RETALIATION_RECHECK_SEC := 30.0
## Одноразовое подкрепление: на REINFORCE_AT_SEC часов ИИ у замка появляются
## REINFORCE_SQUADS отрядов REINFORCE_UNIT ранга REINFORCE_VET и уходят в охрану
const AI_REINFORCE_AT_SEC := 120.0
const AI_REINFORCE_SQUADS := 8
const AI_REINFORCE_UNIT := "spearman"
const AI_REINFORCE_VET := 0
## Пробуждение охраны: удар по замку (память HIT_SEC), чужой боевой в ZONE от
## замка (WAKE_FOES и больше) или удар по самой охране; тихо CALM_SEC — на посты
## и спать; «дома» — ближе HOME_R, м; на постах лечатся HEAL_FRAC запаса в сек
const AI_HOME_GUARD_ZONE := 26.0
const AI_HOME_GUARD_WAKE_FOES := 1
const AI_HOME_GUARD_HIT_SEC := 6.0
const AI_HOME_GUARD_CALM_SEC := 12.0
const AI_HOME_GUARD_TICK_SEC := 0.75    # такт HomeGuard, с
const AI_HOME_GUARD_HOME_R := 6.0
const AI_HOME_GUARD_HOME_RETRY_SEC := 20.0  # переиздать приказ домой, если отряд не дошёл
const AI_HOME_GUARD_GATHER_R := 3.0      # отряд собран, когда каждый боец ближе этого к своему месту поста, м
const AI_HOME_GUARD_GATHER_SEC := 60.0   # не собрались за столько с после прихода центра — спать как есть
const AI_HOME_GUARD_HEAL_FRAC := 0.02
## Пробуждение дозами: отрядов в волне тревоги (0 — ВЕСЬ гарнизон разом) и
## пауза до следующей дозы, с
## ⚠ Менять только по явному ТЗ владельца (разворотов: 1)
const AI_HOME_GUARD_WAVE_SQUADS := 0
const AI_HOME_GUARD_WAVE_GAP_SEC := 180.0
## То же у резерва орды за лагерем (DormantReserve)
const RESERVE_WAVE_SQUADS := 4
const RESERVE_WAVE_GAP_SEC := 180.0
## Перемирие (ИИ не рейдит экономику игрока), с; час генерального штурма, с;
## пауза между рейдами, с; башен на границе
const AI_TRUCE_SEC := 900.0
const AI_ASSAULT_AT_SEC := 1800.0
const AI_RAID_INTERVAL_SEC := 60.0
const AI_TOWERS := 2
## ── ЕДА КРАСНОГО ──
## Домов после стрелковой (дом — 1 еда / 8 с); рабочий не нанимается, если после
## покупки еды останется меньше FOOD_RESERVE, пока рабочих не меньше WORKER_FLOOR
const AI_HOUSES := 14
const AI_FOOD_RESERVE := 160.0
const AI_WORKER_FLOOR := 8
## Ответный удар одалживает спящую охрану уровней от этого и выше (кольцо —
## уровень 1 — не трогается), ровно до MIN_SQUADS
const AI_RETALIATION_LEND_MIN_LEVEL := 2
## ── ВОССТАНОВЛЕНИЕ ПОСЛЕ ПОТЕРЬ ──
## Рабочие: ИИ помнит пик бригады и нанимает до него в приоритете; цель не меньше
const AI_WORKER_REBUILD_MIN := 12
## Добыча красного: множитель цикла сбора (меньше — быстрее) и груза
const AI_GATHER_CYCLE_MULT := 0.75
const AI_GATHER_CARRY_MULT := 1.30
## Перестройка утраченной ключевой постройки: строек параллельно, размер артели,
## крепость без единого склада закладывается бесплатно
const AI_REBUILD_SITES := 2
const AI_REBUILD_CREW := 5
const AI_REBUILD_CASTLE_FREE := true
## Бесплатная закладка без единого живого рабочего приводит артель REBUILD_CREW
## бесплатных рабочих — не больше стольких раз за партию
const AI_REBUILD_REFUGEE_WAVES := 3

# ── ШТУРМ БАЗЫ ИГРОКА ОТ ГЛАВНОЙ ХАТЫ ОРДЫ (scripts/goblin/GoblinFortressAssaultEvent.gd) ──
## В заданные минуты, пока главная хата жива, у неё рождается волна, собирается
## в кулак и маршем с боем идёт через брод на крепости игрока
const ASSAULT_EVENT_ENABLED := true
## Сроки штурмов, с игрового времени (30:00, 45:00, 60:00)
const ASSAULT_EVENT_TIMES := [1800.0, 2700.0, 3600.0]
## Состав по волнам: отрядов конницы / пехоты / туш
const ASSAULT_EVENT_WAVES := [
	{"goblin_rider": 3, "goblin_spearman": 3, "big_goblin": 2},
	{"goblin_rider": 5, "goblin_spearman": 5, "big_goblin": 4},
	{"goblin_rider": 7, "goblin_spearman": 7, "big_goblin": 6},
]
## Шаг выхода отрядов, с (внутри отряда бойцы — очередью Main.spawn_goblin_squad)
const ASSAULT_EVENT_SPAWN_STEP := 1.1
## Прибавка к HORDE_CAP для отрядов штурма (Main.spawn_goblin_squad(..., cap_bonus))
const ASSAULT_EVENT_CAP_EXTRA := 1200
## Отказ потолка — повтор на следующем шаге, не больше стольких раз на волну
const ASSAULT_EVENT_SPAWN_RETRY_MAX := 10
## Площадка сбора: от хаты к броду, м; шаг сетки мест, м; пауза после
## последнего выхода, с
const ASSAULT_EVENT_STAGE_DIST := 30.0
const ASSAULT_EVENT_STAGE_STEP := 14.0
const ASSAULT_EVENT_STAGE_SETTLE := 3.0
## Кулак на марше: шаг сетки мест поперёк хода, м; радиус путевой точки, м;
## доля живых отрядов у точки для перехода к следующей; потолок ожидания, с
const ASSAULT_EVENT_BLOCK_STEP := 13.0
const ASSAULT_EVENT_WP_R := 16.0
const ASSAULT_EVENT_WP_GATE := 0.75
const ASSAULT_EVENT_WP_WAIT_MAX := 30.0
## Марш с боем: чужие ближе AM_R (здания — AM_BLD_R), м — бой; групповое агро
## поднимает отряды волны в ASSIST_R от угрозы; тихо CALM_SEC — марш дальше
const ASSAULT_EVENT_AM_R := 18.0
const ASSAULT_EVENT_AM_BLD_R := 14.0
const ASSAULT_EVENT_ASSIST_R := 110.0
const ASSAULT_EVENT_CALM_SEC := 4.0
## Обход центрального пня — на таком расстоянии от него, м, со стороны базы
const ASSAULT_EVENT_LAIR_BYPASS_R := 36.0
## Ноги маршрута длиннее этого, м, режутся промежуточными точками (конница ждёт туш)
const ASSAULT_EVENT_LEG_MAX := 45.0
## У прохода базы блок сужается до стольких колонн
const ASSAULT_EVENT_GATE_COLS := 2
## Нижний проход базы: точка перед проходом и за ним, м по Z от стены
const ASSAULT_EVENT_GATE_OUT := 12.0
const ASSAULT_EVENT_GATE_IN := 14.0
## Застрял: центр отряда не сдвинулся на STUCK_M за STUCK_SEC — тот же приказ
## ещё раз, не больше STUCK_MAX раз на точку
const ASSAULT_EVENT_STUCK_SEC := 25.0
const ASSAULT_EVENT_STUCK_M := 3.0
const ASSAULT_EVENT_STUCK_MAX := 3

# ── РЕГУЛЯРНЫЕ РЕЙДЫ ОРДЫ ПО ЧАСАМ (scripts/goblin/RaidManager.gd) ──
## Тот же движок волн, что у штурма; цели рейда по приоритету: рабочие → башни
## → бараки → дома и прочее; крепости — последними
const RAID_ENABLED := true
## Расписание ранних рейдов: секунда партии → состав
const RAID_SCHEDULE := [
	{"t": 600.0,  "comp": {"goblin_rider": 3}},
	{"t": 720.0,  "comp": {"goblin_rider": 3}},
	{"t": 900.0,  "comp": {"goblin_rider": 3, "big_goblin": 3, "goblin_spearman": 3}},
]
## Сдвоенные волны крупных сроков: состав делится пополам, вторая половина —
## через PAIR_GAP_SEC той же дорогой (выключатель — для стендов кулака)
const ASSAULT_EVENT_PAIR := true
const ASSAULT_EVENT_PAIR_GAP_SEC := 120.0
## Рабочего-цель рейд ищет в стольких м от отряда (прочие цели — ближайшие без радиуса)
const RAID_WORKER_R := 80.0

## ── ПОЗДНЯЯ ОРДА ПЛОТНЕЕ (ручка A/B — perf_config.goblin_late_surge) ──
## С LATE_SURGE_FROM_SEC: доход еды × FOOD_MULT, паузы волн × GAP_MULT, потолок
## поля × FIELD_CAP_MULT, потолок орды + HORDE_CAP_EXTRA, штурмы 45:00 и 60:00
## × ASSAULT_MULT отрядов каждого рода
const LATE_SURGE_FROM_SEC := 1800.0
const LATE_FOOD_MULT := 1.6
const LATE_GAP_MULT := 0.65
const LATE_FIELD_CAP_MULT := 1.6
const LATE_HORDE_CAP_EXTRA := 900
const LATE_ASSAULT_MULT := 1.4
const _OptSp := preload("res://scripts/perf_config.gd")

static func late_surge(clock_sec: float) -> bool:
	return _OptSp.goblin_late_surge and clock_sec >= LATE_SURGE_FROM_SEC

## ── ЭНДГЕЙМ: ПОСЛЕ ЧАСА ДАВЛЕНИЕ ЕЩЁ ВЫШЕ (ручка A/B — perf_config.goblin_late_raids) ──
## С HOUR_SURGE_FROM_SEC: паузы волн × HOUR_GAP_MULT (вместо LATE), планы волн
## × PLAN_MULT отрядов от шаблона, потолки поля и орды — свои
const HOUR_SURGE_FROM_SEC := 3600.0
const HOUR_GAP_MULT := 0.45
const HOUR_PLAN_MULT := 1.6
const HOUR_FIELD_CAP_MULT := 2.2
const HOUR_HORDE_CAP_EXTRA := 1600

static func hour_surge(clock_sec: float) -> bool:
	return late_surge(clock_sec) and _OptSp.goblin_late_raids and clock_sec >= HOUR_SURGE_FROM_SEC

## Множитель пауз волн вожака по часам партии
static func late_gap_k(clock_sec: float) -> float:
	if hour_surge(clock_sec):
		return HOUR_GAP_MULT
	return LATE_GAP_MULT if late_surge(clock_sec) else 1.0

## Потолок бойцов в поле по часам партии
static func field_cap(clock_sec: float) -> int:
	if hour_surge(clock_sec):
		return int(float(HORDE_FIELD_CAP) * HOUR_FIELD_CAP_MULT)
	return int(float(HORDE_FIELD_CAP) * LATE_FIELD_CAP_MULT) if late_surge(clock_sec) else HORDE_FIELD_CAP

## Потолок орды на карту по часам партии
static func horde_cap(clock_sec: float) -> int:
	if hour_surge(clock_sec):
		return HORDE_CAP + HOUR_HORDE_CAP_EXTRA
	return HORDE_CAP + LATE_HORDE_CAP_EXTRA if late_surge(clock_sec) else HORDE_CAP

## ── ПОЗДНИЕ РЕЙДЫ ПО ЧАСАМ ──
## С LATE_RAID_FROM_SEC рейд каждые LATE_RAID_EVERY_SEC (после часа —
## HOUR_RAID_EVERY_SEC) до LATE_RAID_UNTIL_SEC; состав LATE_RAID_COMP растёт на
## LATE_RAID_GROW за срок, после часа × HOUR_RAID_MULT; срок ближе
## LATE_RAID_CLEAR_SEC к штурму не ставится. Штурмы после 60:00 — каждые
## HOUR_ASSAULT_EVERY_SEC до HOUR_ASSAULT_UNTIL_SEC, состав последнего штурма
## × (1 + HOUR_ASSAULT_GROW·k)
const LATE_RAID_FROM_SEC := 1800.0
const LATE_RAID_EVERY_SEC := 300.0
const HOUR_RAID_EVERY_SEC := 240.0
const LATE_RAID_UNTIL_SEC := 10800.0
const LATE_RAID_CLEAR_SEC := 100.0
const LATE_RAID_COMP := {"goblin_rider": 2, "goblin_spearman": 2, "big_goblin": 1}
const LATE_RAID_GROW := 0.08
const HOUR_RAID_MULT := 1.75
const HOUR_ASSAULT_EVERY_SEC := 900.0
const HOUR_ASSAULT_UNTIL_SEC := 10800.0
const HOUR_ASSAULT_GROW := 0.3

# ── ВХОД ОРДЫ ИЗ-ЗА КРОМКИ КАРТЫ (ТЗ 31.10.2026, ручка horde_edge_entry) ──
## Шаг перебора точек вдоль кромки, м
const HORDE_ENTRY_STEP := 8.0
## Запас от кромки сверх габарита толпы, м
const HORDE_ENTRY_PAD := 2.0
## Ни одного чужого бойца ближе, м
const HORDE_ENTRY_CLEAR_R := 45.0
## Радиус проверки обзора игрока вокруг точки входа, м
const HORDE_ENTRY_LOOK_R := 14.0
## Дошёл: медиана отряда у точки заказа в габарите толпы плюс, м
const HORDE_ENTRY_ARRIVE_R := 3.0
## Такт сторожа входящих, физкадров
const HORDE_ENTRY_TICK := 20
## Срок входа, с: дольше — признак снят (страховка от глухой стены)
const HORDE_ENTRY_MAX_SEC := 240.0

# ── МАРШ ВОЛНЫ ПРИВАЛАМИ (ТЗ 31.10.2026, scripts/goblin/WaveMarch.gd) ──────
## Привал «выход с базы» — от центра волны к цели, м
const HALT_EXIT_DIST := 45.0
## Привал «подступ» — до входа в брод на своём берегу, м
const HALT_FORD_APPROACH := 30.0
## Привал «за бродом» — после выхода из брода, м
const HALT_FORD_EXIT := 28.0
## Привалы ближе друг к другу (и к развёртыванию) снимаются, м
const HALT_MIN_GAP := 35.0
## Блок волны: отрядов в ряду; шаг — диаметр крупнейшей толпы + зазор, не меньше минимума, м
const HALT_COLS := 4
const HALT_SQUAD_PAD := 4.0
const HALT_GAP_MIN := 14.0
## Отряд на привале: центр ближе, м; доля вставших бойцов
const HALT_ARRIVE_R := 9.0
const HALT_SETTLE_SHARE := 0.8
## Центр отряда у точки дольше — собран, как бы ни доталкивалась толпа, с
const HALT_SETTLE_GRACE_SEC := 8.0
## Нет хода HALT_STUCK_M за HALT_STUCK_SEC — лог и переприказ
const HALT_STUCK_M := 3.0
const HALT_STUCK_SEC := 20.0
## Разброс бойцов отряда больше — «порвался», м
const HALT_TORN_M := 25.0
## Стоянка: не меньше HALT_MIN_SEC после сбора всех; ждать отставших не дольше HALT_WAIT_MAX_SEC от первого пришедшего
const HALT_MIN_SEC := 6.0
const HALT_WAIT_MAX_SEC := 35.0
## Срок этапа: HALT_LEG_BASE_SEC + длина / HALT_LEG_SPEED
const HALT_LEG_BASE_SEC := 40.0
const HALT_LEG_SPEED := 1.0
## Скан передовых: раз в SCAN_SEC, после находки — SCAN_HOT_SEC; точка на SCAN_AHEAD вперёд, радиус SCAN_R
const SCAN_SEC := 8.0
const SCAN_HOT_SEC := 2.0
const SCAN_AHEAD := 15.0
const SCAN_R := 35.0
## Враг ближе к голове — развёртывание на месте, м; передовых отрядов не больше
const CONTACT_R := 40.0
const SCAN_HEADS := 5

# ── ПОДАЧА ВОЛНЫ ДОЗАМИ (ТЗ 31.10.2026, scripts/goblin/WaveFeed.gd) ────────
## Скан чужих отрядов от центра волны, м
const FEED_SCAN_R := 50.0
## По два своих на чужой, когда своих пехотных не меньше RATIO × чужих
const FEED_PAIR_RATIO := 2
## Новых отрядов в бой за такт не больше
const FEED_DOSE_MAX := 3
## Заход во фланг: вбок от крайнего чужого, м; срок захода, с
const FEED_FLANK_OFF := 22.0
const FEED_FLANK_SEC := 25.0
## Свой ниже доли штата — замена свежим; чужой ниже — конница в брешь (до CAV_MAX отрядов)
const FEED_REPLACE_FRAC := 0.3
const FEED_BREACH_FRAC := 0.5
const FEED_CAV_MAX := 2
