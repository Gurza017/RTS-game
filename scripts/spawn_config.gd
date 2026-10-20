extends RefCounted
## ЕДИНЫЙ КОНФИГ СПАВНА (ТЗ 14.09.2026, п. 1): кто, сколько и когда появляется,
## по всем сущностям и фракциям. Только параметры. Без class_name — через preload.
## Поведение (фазы, приказы) — goblin_config / ai_start_army_limit; они читают
## числа ОТСЮДА (const X := _Spawn.X), второй копии не заводить.
## Формат отрядного списка: {"unit", "count" (0 = уставной размер), "vet", "picks"}

# ═══ ГОБЛИНЫ (орда) ═══════════════════════════════════════════════════════════
## Размер отряда по роду (уставной)
const GOBLIN_SQUAD_SIZE := {
	"goblin_spearman": 100,
	"goblin_rider":    50,
	"gnoll":           12,
	"big_goblin":      5,
}
## Стартовая орда у деревни
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
## Гарнизон деревни (ветеранские копейщики, мирная фаза)
const GOBLIN_GARRISON_SQUADS := 3
## Найм: цена еды и время на отряд
const GOBLIN_SQUAD_FOOD_COST := 90.0
const GOBLIN_SQUAD_BUILD_SEC := 90.0
## Охрана рудника орды
const GOBLIN_MINE_GUARD := [
	{"unit": "goblin_rider",    "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_spearman", "count": 0, "vet": 3, "picks": 3},
	{"unit": "goblin_spearman", "count": 0, "vet": 3, "picks": 3},
]
## Спящий резерв за лагерем (будит только штурм лагеря)
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
## Большие гоблины: отрядов туш в волне пня, на базе, в защите пня
const BIG_WAVE_SQUADS := 1
const BIG_BASE_SQUADS := 1
const BIG_DEFENSE_SQUADS := 1
## Расписание орды: мирная фаза (= перемирие), не раньше какой секунды штурм
## ТЗ 24.09.2026 (второе письмо): «на десятой минуте у врага ничего не должно
## быть» — первый набег орды по расписанию на 15-й минуте (GoblinRaids)
const GOBLIN_PEACE_SEC := 900.0
const GOBLIN_ASSAULT_EARLIEST_SEC := 1800.0
## ── ПОТОЛОК БЕСПОКОЙСТВА (аудит партий 19.09.2026) ─────────────────────────
## Партия A: орда 27 минут в harass и ни разу не перешла в HUNT — полевых
## отрядов не набиралось до уставных 11 (рейды таяли, раненые сидели в
## хижинах). После часа X и HARASS_MAX_SEC беспокойства орда идёт в
## наступление тем, что есть, но не меньше ASSAULT_MIN_SQUADS отрядов
const GOBLIN_HARASS_MAX_SEC := 480.0
const GOBLIN_ASSAULT_MIN_SQUADS := 6
## Резерв не даёт конницу взаймы, когда отрядов в нём меньше (12 → 2 за партию)
const GOBLIN_RESERVE_LEND_FLOOR := 8
const GOBLIN_RAID_INTERVAL_SEC := 40.0
## ── РАЗВЕДКА ВСАДНИКОВ (ТЗ 19.09.2026, блок 3.4) ──────────────────────────
## Полноценные конные отряды (0 = уставной размер), в вылазку 1-3 разом
## (веса), пул не больше SCOUT_MAX_SQUADS; веер вокруг базы игрока по орбите,
## охота на рабочих и одинокие стрелковые отряды, налёт и отход
const SCOUT_UNITS := 0                    # 0 — полный отряд (GOBLIN_SQUAD_SIZE)
const SCOUT_MAX_SQUADS := 3
const SCOUT_SORTIE_WEIGHTS := [0.4, 0.4, 0.2]   # 1 / 2 / 3 отряда
const SCOUT_SORTIE_SEC := 22.0            # передышка дома (была 45)
const SCOUT_HARASS_SEC := 12.0            # налёт на добычу
const SCOUT_RUN_SEC := 8.0                # отход после налёта (hit-and-run)
const SCOUT_SORTIE_MAX_SEC := 150.0       # потолок одной вылазки — потом домой
const SCOUT_ORBIT_R := 42.0               # радиус орбиты вокруг базы
const SCOUT_ORBIT_POINTS := 6
const SCOUT_HUNT_R := 38.0                # ищем добычу от центра отряда
const SCOUT_LONE_R := 18.0                # «одинокий» стрелковый отряд: без пехоты рядом
## Месть за зачищенный пень: раз в интервал — столько отрядов пехоты
const REVENGE_INTERVAL_SEC := 600.0
const REVENGE_SQUADS := 10
const REVENGE_UNIT := "goblin_spearman"

# ═══ НОВАЯ ОРДА (ТЗ 11.10.2026, часть 2) ═════════════════════════════════════
## Старая система спавна снесена (стартовая орда, резерв, набеги по часам,
## волны на рудник, месть, бесплатная разведка, бесплатное доукомплектование в
## хижинах — всё это рождало бойцов без потолка). Единственный источник войск —
## ГЛАВНАЯ ХАТА лагеря; хижины дают ЕДУ, еда идёт на содержание и на покупку
## отрядов; отряды копятся на площадке сбора ВОЛНОЙ (спят), волна уходит
## целиком по сценарию. Логика — scripts/goblin/GoblinAI.gd.
## Потолок живых бойцов фракции орды НА ВСЮ КАРТУ (охрана, волны, пни):
## Main.spawn_goblin_squad урезает отряд до остатка, ноль — отряд не родится
const HORDE_CAP := 1800
## Потолок бойцов в волнах и на площадке сбора (охрана рудников не в счёт)
const HORDE_FIELD_CAP := 900
## ── ЛАГЕРЬ ──────────────────────────────────────────────────────────────────
## Главная хата: вдвое больше хижины, запас 20 000, сама чинится, если по ней
## не бьют REGEN_DELAY_SEC
const CHIEF_HUT_HP := 20000.0
const CHIEF_HUT_SIZE_MULT := 2.0
const CHIEF_HUT_REGEN_PER_SEC := 40.0
const CHIEF_HUT_REGEN_DELAY_SEC := 15.0
## Хижины — серпом ВЫШЕ главной хаты (к -Z, вверх по экрану): радиус дуги и
## размах дуги в градусах (симметрично от вертикали)
const CAMP_HUTS := 10
const CAMP_ARC_R := 19.0
const CAMP_ARC_DEG := 150.0
## ── ЭКОНОМИКА ЕДЫ ───────────────────────────────────────────────────────────
## Доход: еды в минуту с хижины и с главной хаты; рост дохода со временем —
## +RAMP_PER_HOUR долей за час партии (потолок RAMP_MAX). Содержание —
## еды в минуту за каждого живого бойца волн и площадки сбора. Копилка не
## больше BANK_MAX: перемирие не копит гигантскую первую волну
## ТЗ 12.10.2026 (второе письмо): 8/80 → 12/100 — крупная волна (4-5
## отрядов, ~1500 еды) окупается за 7 минут (220 еды/мин на старте, рост ×ramp)
const HUT_FOOD_MIN := 12.0
const CHIEF_FOOD_MIN := 100.0
const FOOD_RAMP_PER_HOUR := 1.0
const FOOD_RAMP_MAX := 2.5
const FOOD_UPKEEP_PER_UNIT_MIN := 0.06
const FOOD_BANK_MAX := 1600.0
## Цены отрядов в еде (отряд — уставной размер GOBLIN_SQUAD_SIZE)
const SQUAD_PRICE := {
	"goblin_spearman": 300.0,
	"goblin_rider":    360.0,
	"big_goblin":      280.0,
}
## Между рождениями двух отрядов волны не меньше, с
const SQUAD_SPAWN_GAP_SEC := 4.0
## Площадка сбора: смещения слотов от центра лагеря (x, z), м. Шаг между
## слотами больше диаметра толпы из 100 (≈15 м) — диски не накладываются.
## Слоты лежат в стороне от рудника лагеря и его охраны
## ТЗ 12.10.2026 (второе письмо): двенадцать слотов — десять под стартовый
## резерв и ещё два под текущую закупку
const MUSTER_SLOTS := [
	Vector2(-2.0, 22.0), Vector2(16.0, 22.0), Vector2(34.0, 22.0),
	Vector2(5.0, 39.0), Vector2(23.0, 39.0), Vector2(41.0, 39.0),
	Vector2(-2.0, 56.0), Vector2(16.0, 56.0), Vector2(34.0, 56.0),
	Vector2(59.0, 22.0), Vector2(59.0, 39.0), Vector2(59.0, 56.0),
]
## ── СТАРТОВЫЙ РЕЗЕРВ ВОЛН (ТЗ 12.10.2026, второе письмо) ────────────────────
## «Волны практически исчезли»: первая волна ждала, пока экономика еды
## накопит отряды, и в поле выходила поздно и мелко. На старте лагерь получает
## готовый резерв — отряды спят на площадке сбора и считаются оплаченными:
## первые планы волн берут их даром (GoblinAI._production_tick), пока экономика
## раскочегаривается. 565 бойцов — в пределах HORDE_FIELD_CAP
const START_RESERVE := [
	"goblin_spearman", "goblin_spearman", "goblin_spearman", "goblin_spearman",
	"goblin_rider", "goblin_rider", "goblin_rider",
	"big_goblin", "big_goblin", "big_goblin",
]
## ── ТЕМП ВОЛН: КАЖДЫЕ 7-10 МИНУТ ────────────────────────────────────────────
## Между выходами волн не меньше WAVE_GAP_MIN_SEC; дольше WAVE_GAP_MAX_SEC без
## выхода — уходит то, что набрано (план не ждёт до конца сборки)
const WAVE_GAP_MIN_SEC := 420.0
const WAVE_GAP_MAX_SEC := 600.0
## ── ВОЛНЫ ───────────────────────────────────────────────────────────────────
## Состав волн по шаблонам. Порядок волн — WAVE_PATTERN по кругу: разведка,
## мелкая, крупная… Мелкая — 2-3 отряда, крупная — 4-5
const WAVE_TEMPLATES := {
	"scout": ["goblin_rider", "goblin_rider"],
	"small_a": ["goblin_spearman", "goblin_spearman", "big_goblin"],
	"small_b": ["goblin_spearman", "goblin_rider"],
	"small_c": ["goblin_spearman", "goblin_spearman", "goblin_rider"],
	"big_a": ["goblin_spearman", "goblin_spearman", "goblin_spearman", "big_goblin", "goblin_rider"],
	"big_b": ["goblin_spearman", "goblin_spearman", "big_goblin", "goblin_rider", "goblin_rider"],
}
const WAVE_PATTERN := ["scout", "small_a", "big_a", "small_b", "small_c", "big_b"]
## Волна, не набравшая состав за столько секунд (упёрлась в потолок), уходит
## тем, что есть
const WAVE_ASSEMBLE_MAX_SEC := 240.0
## Сколько волн одновременно в поле
const WAVES_MAX_ACTIVE := 2
## Срок волны: дольше — домой, на площадку сбора (бойцы вливаются в следующую)
const WAVE_MAX_SEC := 420.0
## Точка развёртывания — за столько м до цели по линии подхода
const WAVE_STAGE_DIST := 32.0
## Флаг/тыл: точка захода кавалерии — в стольких м сбоку/сзади от цели
const WAVE_FLANK_DIST := 30.0
## Ложный отход: через столько с рубки или при такой доле потерь — отход на
## FEINT_BACK м, перегруппировка FEINT_REGROUP_SEC и второй удар (один раз)
const WAVE_FEINT_SEC := 14.0
const WAVE_FEINT_LOSS := 0.25
const WAVE_FEINT_BACK := 24.0
const WAVE_FEINT_REGROUP_SEC := 8.0
## Брод: волна держит брод столько секунд; брод «отобран» чужими, если у его
## середины их больше FORD_TAKEN_FOES (тогда штурм брода — первым)
const WAVE_FORD_HOLD_SEC := 150.0
const FORD_TAKEN_FOES := 12
## ── ОХРАНА РУДНИКОВ (стационарная, глубокий покой) ─────────────────────────
## Рудник лагеря: 2 пехоты (2 лычки), 3 туши (2 лычки), 3 конницы (4 лычки —
## синие флаги). Ничейные рудники сторон: 2 пехоты + 2 конницы каждый.
## Охрана СПИТ (F_DORMANT: ни тика, ни расталкивания), просыпается только
## на удар по руднику или чужого ближе GUARD_WAKE_R; отбилась — через
## GUARD_CALM_SEC идёт на пост ОДНИМ приказом и засыпает там
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
const GUARD_WAKE_R := 22.0
const GUARD_CALM_SEC := 12.0
const GUARD_HOME_R := 7.0
const GUARD_HOME_TIMEOUT_SEC := 30.0
## Ближний край толпы охраны не ближе стольких м к руднику: в радиусе захвата
## (Mine.CAPTURE_RADIUS 8) охрана захватила бы ничейный рудник себе
const GUARD_MINE_CLEAR := 10.0
## Тревога лагеря: чужой ближе стольких м к главной хате или хижине — будятся
## отряды площадки сбора; тихо GUARD_CALM_SEC — назад в слоты и спать
const CAMP_ALARM_R := 45.0

# ═══ ПНИ (логова): тролли, гноллы, овцы ══════════════════════════════════════
const LAIR_AI_ENABLED := true             # второй («красный») пень
const LAIR_START_TROLLS := 1              # стражей при появлении пня
const TROLL_GUARDS_MAX := 2               # потолок постоянной охраны
const TROLL_RESPAWN_SEC := 300.0          # +1 страж раз в столько секунд
const TROLL_DEFENSE_WAVE := 3             # волна защиты: троллей сверх охраны
const TROLL_DEFENSE_WAVE_CD := 600.0
const TROLL_REINFORCE_COUNT := 1          # подмога на трети запаса (бонусная пара)
const TROLL_AGGRO_HELPERS := 0            # помощники по первому удару (снято)
const TROLL_AGGRO_BONUS := 0
const TROLL_RAID_SPAWN := 1               # троллей за удачный рейд за овцами
const TROLL_RAID_REWARD := 3
const LAIR_REGEN_SEC := 600.0             # не раньше чего пень восстанавливается
## Заморозка пня за рекой (ТЗ 19.09.2026, блок 3): пень на чужом берегу ничего
## не рождает, а считает «всухую»; игрок перешёл брод — порционная разморозка
const LAIR_FREEZE_ENABLED := true
const LAIR_THAW_STEP_SEC := 3.0           # одна порция (тролль / отряд) в столько секунд
const LAIR_THAW_CHECK_SEC := 2.0          # как часто ищем игрока на том берегу
const LAIR_THAW_BANK_MARGIN := 2.0        # метров за сухой кромкой русла = «перешёл»
## Гноллы: стартовая стая и волны по удару в пень
## ── СПАВН ГНОЛЛОВ У ПНЕЙ — ПО ЧАСАМ, С ОБЩИМ ПОТОЛКОМ (ТЗ 14.10.2026, п. 3)
## Прежде: 3 отряда на старте и три волны по удару в пень. Теперь каждый пень
## раз в GNOLL_SPAWN_SEC выпускает GNOLL_SPAWN_MIN..MAX отрядов (чередуя 1 и
## 2), пока живых отрядов гноллов ОТ ВСЕХ ПНЕЙ меньше MAX_STUMP_GNOLLS; у
## потолка часы стоят (пень проверяет место раз в GNOLL_SPAWN_RECHECK_SEC и
## заводит полный интервал заново, когда место появилось). Стартовая стая —
## GNOLL_START_SQUADS на пень, в потолок входит (три пня × 2 = 6)
const GNOLL_START_SQUADS := 2
const GNOLL_SPAWN_SEC := 120.0
const GNOLL_SPAWN_MIN := 1
const GNOLL_SPAWN_MAX := 2
const GNOLL_SPAWN_RECHECK_SEC := 10.0
const MAX_STUMP_GNOLLS := 6               # живых отрядов гноллов от всех пней разом
## Прежние волны по удару (оставлены для старых стендов и как ручки отката)
const GNOLL_WAVE_SQUADS := 3
const GNOLL_WAVE_SEC := 180.0
const GNOLL_WAVES_MAX := 3
const GNOLL_COOLDOWN_SEC := 600.0
const GNOLL_MAX_ALIVE := 72               # живых гноллов на пень, потолок (волна сверх — не выходит)
## Овцы у пня
const SHEEP_START := 5
const SHEEP_BREED_SEC := 300.0
const SHEEP_BREED_COUNT := 2
const SHEEP_RESPAWN_SEC := 20.0
const SHEEP_RESPAWN_COUNT := 5

# ═══ КРАСНЫЙ ИИ (люди) ═══════════════════════════════════════════════════════
## Лимиты отрядов по роду и рабочих
const AI_SQUAD_LIMIT := {
	"spearman": 10,
	"archer":   5,
	"warrior":  6,
}
const AI_WORKER_LIMIT := 40
const AI_START_WORKERS := 5
## Стартовые отряды В ПОЛЕ (пусто = без полевой армии на старте)
const AI_START_SQUADS := []
## ── СТАРТОВАЯ ОБОРОНА КРЕПОСТИ (15.09.2026) ─────────────────────────────────
## Ставится вместе с замком в _spawn_enemy_base. Башни — на кольце вокруг
## крепости: угол от оси «замок → центр карты» (положительный — вправо от
## фасада), дистанция от центра замка; в КАЖДОЙ башне сразу сидит отряд лучников
## (garrison_now). Углы разведены так, чтобы башни не легли ни на бараки/кузню/
## стрелковую ИИ (фронт +2, вбок ±8/±16), ни на его же жилы за замком (±35°)
const AI_HOME_DEFENSE_ENABLED := true
const AI_HOME_TOWERS := [
	{"dist": 20.0, "angle_deg": -35.0},
	{"dist": 15.0, "angle_deg":  60.0},
	{"dist": 10.0, "angle_deg": -115.0},
]
const AI_HOME_TOWER_ARCHERS := 1        # отрядов лучников в каждой башне
const AI_HOME_CASTLE_ARCHERS := 1       # отрядов лучников на крыше крепости
## Охрана крепости: стоит В ГЛУБИНЕ базы (колонной за замком, по оси от центра
## карты), спит до штурма. Ранг — по VET_BANNER_TIERS: 2 — красный вымпел с
## двумя лычками, 4 — первый синий «ласточкин хвост»
const AI_HOME_GUARD_SQUADS := [
	{"unit": "warrior",  "count": 0, "vet": 4, "picks": 4},
	{"unit": "warrior",  "count": 0, "vet": 4, "picks": 4},
	{"unit": "spearman", "count": 0, "vet": 2, "picks": 2},
	{"unit": "spearman", "count": 0, "vet": 2, "picks": 2},
	{"unit": "spearman", "count": 0, "vet": 2, "picks": 2},
]
const AI_HOME_GUARD_DEPTH := 9.0        # первый отряд охраны — за замком, м (прежняя колонна; не используется с 25.09)
## ── ОБОРОНА БАЗЫ В ТРИ УРОВНЯ (ТЗ 25.09.2026, п. 1) ───────────────────────
## Прежняя расстановка ставила охрану колонной, а подкрепление — блоками «в
## углу за замком», по оси ОТ центра карты; база стоит в углу, и посты уходили
## за кромку — отряды ложились одной ниткой вдоль края (скриншоты 25.09).
## Уровень 1 — охрана (AI_HOME_GUARD_SQUADS) КОЛЬЦОМ вокруг крепости на
## RING_DIST, лицом наружу, посты обходят башни и жилы базы.
## Уровень 2 — гарнизон (подкрепление) ЛИНИЯМИ поперёк курса обороны (на базу
## игрока), LINE_ROWS шеренг по LINE_SQUADS отрядов, первая на LINE_DIST от
## замка (за постами заслона полевой армии EnemyAI._screen_post: 13-27 м).
## Уровень 3 — всё, что не влезло в линии, встаёт постами у ПЕРЕДНИХ башен
## (RedAI.perimeter_post — та же логика, что у полевой армии).
## Центр каждого поста держится от кромки на полуразмер строя плюс
## GameManager.SQUAD_EDGE_PAD (см. squad_inside)
const AI_HOME_RING_DIST := 13.0         # уровень 1: радиус кольца охраны, м
const AI_HOME_RING_CLEAR := 4.5         # пост кольца не ближе стольких м к башне/жиле
const AI_HOME_LINE_DIST := 34.0         # уровень 2: первая линия гарнизона от замка, м
const AI_HOME_LINE_SQUADS := 3          # отрядов в линии
const AI_HOME_LINE_ROWS := 2            # линий
const AI_HOME_LINE_GAP := 3.0           # просвет между блоками линии, м
const AI_HOME_LINE_ROW_GAP := 4.0       # просвет между линиями, м
const AI_HOME_TOWER_POST_DIST := 5.0    # уровень 3: пост перед башней, м от неё
## Чужой боевой ближе стольких м к ЛЮБОМУ посту гарнизона — тревога
## («враг подбирается к базе», ТЗ 25.09.2026)
const AI_HOME_GUARD_POST_ZONE := 12.0
## ── ОТВЕТНЫЙ УДАР И ПОДКРЕПЛЕНИЕ (ТЗ 19.09.2026-3, п. 2) ─────────────────
## TOTAL_RETALIATION: потеряно AI_RETALIATION_LOSSES моделей (счёт от
## прошлого удара) → ВСЯ полевая армия на AI_RETALIATION_SEC идёт ATTACK-MOVE
## к источнику потерь (точка последнего убийцы) или к базе игрока; охрана
## крепости остаётся дома (DEFEND_BASE). Следующий — не раньше COOLDOWN
const AI_RETALIATION_LOSSES := 60
const AI_RETALIATION_SEC := 120.0
const AI_RETALIATION_COOLDOWN_SEC := 180.0
## ── ОТВЕТНЫЙ УДАР — ПО СИЛЕ, А НЕ ПО ОТКАТУ (аудит партий 19.09.2026) ─────
## Партия A: удар шёл ровно каждые 5 минут (5 из 5) и сжёг армию 32 → 0.
## Условия: полевых отрядов не меньше MIN_SQUADS; своих бойцов в поле не
## меньше ADVANTAGE × чужих в SCAN_R от источника потерь; потери у своей
## крепости (HOME_R) — удар без проверки силы. Отказ переспрашивается
## через RECHECK_SEC, счёт потерь при отказе не сбрасывается
const AI_RETALIATION_MIN_SQUADS := 8
const AI_RETALIATION_ADVANTAGE := 1.0
const AI_RETALIATION_SCAN_R := 45.0
const AI_RETALIATION_HOME_R := 45.0
const AI_RETALIATION_RECHECK_SEC := 30.0
## Одноразовое подкрепление: на AI_REINFORCE_AT_SEC часов ИИ в углу за
## замком появляются AI_REINFORCE_SQUADS отрядов AI_REINFORCE_UNIT и уходят
## под охрану крепости (HomeGuard: спят, просыпаются только на штурм)
const AI_REINFORCE_AT_SEC := 120.0
const AI_REINFORCE_SQUADS := 8
const AI_REINFORCE_UNIT := "spearman"
const AI_REINFORCE_VET := 0
const AI_REINFORCE_COLS := 2            # колонн блоков в углу
const AI_HOME_GUARD_GAP := 2.0          # просвет между отрядами колонны, м
## Пробуждение: удар по замку (память HIT_SEC), чужой боевой в ZONE от замка
## (WAKE_FOES и больше) или удар по самой охране. Отбились — через CALM_SEC
## возвращаются на посты и засыпают; на постах лечатся HEAL_FRAC запаса в сек
const AI_HOME_GUARD_ZONE := 26.0
const AI_HOME_GUARD_WAKE_FOES := 1
const AI_HOME_GUARD_HIT_SEC := 6.0
const AI_HOME_GUARD_CALM_SEC := 12.0
const AI_HOME_GUARD_TICK_SEC := 0.75
const AI_HOME_GUARD_HOME_R := 6.0
const AI_HOME_GUARD_HOME_RETRY_SEC := 20.0  # переиздать приказ домой, если отряд не дошёл
const AI_HOME_GUARD_HEAL_FRAC := 0.02
## Пробуждение ДОЗАМИ (ТЗ 19.09.2026, блок 3.3): по тревоге просыпается не вся
## охрана, а волна из стольких отрядов; следующая — через столько секунд
## тревоги. Отряд, по которому бьют, просыпается вне очереди.
## РАЗВОРОТ (ТЗ 25.09.2026, п. 1): по тревоге встаёт ВЕСЬ гарнизон базы —
## ноль означает «все разом». Положительное число возвращает дозы
const AI_HOME_GUARD_WAVE_SQUADS := 0
const AI_HOME_GUARD_WAVE_GAP_SEC := 180.0
## То же у резерва орды за лагерем (DormantReserve)
const RESERVE_WAVE_SQUADS := 4
const RESERVE_WAVE_GAP_SEC := 180.0
## Условия и триггеры: перемирие, час генерального штурма, рейды, башни
## ТЗ 24.09.2026 (второе письмо): перемирие 15 минут — то же, что у орды
const AI_TRUCE_SEC := 900.0
const AI_ASSAULT_AT_SEC := 1800.0
const AI_RAID_INTERVAL_SEC := 60.0
const AI_TOWERS := 2
## ── ЕДА КРАСНОГО (ТЗ 29.09.2026, второе письмо, п. 1) ──────────────────
## С ТЗ 23.09 отряд и рабочий стоят еду, а ИИ не имел НИ ОДНОГО её
## источника: 400 стартовой еды уходили на рабочих к 140-й секунде, и дальше
## ни один заказ отряда не проходил ResourceManager.spend — 0-3 полевых
## отряда до падения замка (performance_log 29.09 16:06, 28.09 23:39).
## Теперь: AI_HOUSES домов после стрелковой (дом — 1 еда / 8 с), и рабочий
## не нанимается, если после покупки еды останется меньше AI_FOOD_RESERVE,
## пока рабочих не меньше AI_WORKER_FLOOR
const AI_HOUSES := 10
const AI_FOOD_RESERVE := 160.0
const AI_WORKER_FLOOR := 8
## Ответный удар одалживает спящую охрану уровней 2-3 (подкрепление линий и
## периметра) — ровно столько, сколько не хватает до MIN_SQUADS. Кольцо
## (уровень 1) не трогается никогда. Удар кончился — одолженные идут на посты
const AI_RETALIATION_LEND_MIN_LEVEL := 2
const AI_MINE_SQUADS := 1
## ── КРАСНЫЙ НЕ ВЫКЛЮЧАЕТСЯ ПОСЛЕ ПОТЕРЬ (ТЗ 14.10.2026, п. 2) ─────────────
## Рабочие: ИИ помнит ПИК своей бригады и после потерь нанимает до него в
## ПРИОРИТЕТЕ — заказ рабочего встаёт в голову очереди замка, а заказы
## отрядов из замка ждут, пока бригада ниже цели. Цель — не меньше
## AI_WORKER_REBUILD_MIN
const AI_WORKER_REBUILD_MIN := 12
## Добыча: рабочие красного собирают быстрее (цикл × CYCLE_MULT) и носят
## больше (груз × CARRY_MULT) — «агрессивный сбор» без второй таблицы темпов
const AI_GATHER_CYCLE_MULT := 0.75
const AI_GATHER_CARRY_MULT := 1.30
## Перестройка: пока не хватает ключевой постройки, которая у базы БЫЛА
## (барак, кузница, стрелковая, дом, башня, крепость), стройки идут
## параллельно (до AI_REBUILD_SITES) и артель больше (AI_REBUILD_CREW);
## крепость без единого склада закладывается БЕСПЛАТНО (иначе рабочим некуда
## нести, и экономика мертва навсегда) — тот же приём, что REBUILD_BARRACKS_FREE
const AI_REBUILD_SITES := 2
const AI_REBUILD_CREW := 5
const AI_REBUILD_CASTLE_FREE := true

## ═══════════════════════════════════════════════════════════════════════════
## ШТУРМ БАЗЫ ИГРОКА ОТ ГЛАВНОЙ ХАТЫ ОРДЫ (ТЗ 13.10.2026, два письма,
## scripts/goblin/GoblinFortressAssaultEvent.gd)
## ═══════════════════════════════════════════════════════════════════════════
## Отдельно от волн вожака: в заданные минуты партии, ТОЛЬКО пока главная хата
## жива, у неё по одному отряду рождается волна, СОБИРАЕТСЯ В КУЛАК на
## площадке и единым блоком идёт маршем с боем через центральный брод, обходит
## пень на нашем берегу и входит на базу игрока нижним проходом — сносить
## крепости (первую, затем следующую), всё прочее — по ходу
const ASSAULT_EVENT_ENABLED := true
## Минуты партии (секунды игрового времени) — 30:00, 45:00, 60:00
const ASSAULT_EVENT_TIMES := [1800.0, 2700.0, 3600.0]
## ПРОГРЕССИЯ СОСТАВА: конница / пехота / туши по волнам —
## 3/3/2 (8) → 5/5/4 (14) → 7/7/6 (20)
const ASSAULT_EVENT_WAVES := [
	{"goblin_rider": 3, "goblin_spearman": 3, "big_goblin": 2},
	{"goblin_rider": 5, "goblin_spearman": 5, "big_goblin": 4},
	{"goblin_rider": 7, "goblin_spearman": 7, "big_goblin": 6},
]
## Шаг выхода отрядов, с (по одному отряду; внутри отряда бойцы растянуты
## очередью Main.spawn_goblin_squad(staggered))
const ASSAULT_EVENT_SPAWN_STEP := 1.1
## Прибавка к HORDE_CAP для отрядов эвента: третья волна — 7×50 + 7×100 +
## 6×5 = 1080 бойцов, а резерв площадки, охрана и волны вожака к 30-й минуте
## держат ~1700 из 1800 (Main.spawn_goblin_squad(..., cap_bonus))
const ASSAULT_EVENT_CAP_EXTRA := 1200
## Отказ потолка (орда выше HORDE_CAP + EXTRA) — попытка повторяется на
## следующем шаге, не больше RETRY_MAX раз на волну; дальше волна идёт тем,
## что вышло
const ASSAULT_EVENT_SPAWN_RETRY_MAX := 10
## ПЛОЩАДКА СБОРА: от хаты в сторону брода, сетка мест шагом STAGE_STEP
## (шире диаметра толпы отряда — отряды не трутся). Отряд рождается на своём
## месте и стоит, пока не выйдет вся волна; затем — марш кулаком.
## STAGE_SETTLE — пауза после последнего выхода (хвост очереди бойцов)
const ASSAULT_EVENT_STAGE_DIST := 30.0
const ASSAULT_EVENT_STAGE_STEP := 14.0
const ASSAULT_EVENT_STAGE_SETTLE := 3.0
## КУЛАК НА МАРШЕ: у каждого отряда своё место в блоке вокруг путевой точки
## (сетка поперёк хода шагом BLOCK_STEP); следующая точка — когда до неё дошла
## доля WP_GATE живых отрядов (или ждали WP_WAIT_MAX); отставший дальше
## REJOIN_R от центра кулака получает приказ заново
const ASSAULT_EVENT_BLOCK_STEP := 13.0
const ASSAULT_EVENT_WP_R := 16.0
const ASSAULT_EVENT_WP_GATE := 0.75
const ASSAULT_EVENT_WP_WAIT_MAX := 30.0
## Марш с боем: чужие (люди обеих сторон) ближе AM_R к отряду — бой;
## ГРУППОВОЕ АГРО: бой любого отряда волны поднимает ВСЕ отряды волны в
## ASSIST_R от угрозы (раскладка фронта, нет пары — подход к угрозе);
## тихо CALM_SEC — перегруппировка и марш дальше
const ASSAULT_EVENT_AM_R := 18.0
const ASSAULT_EVENT_AM_BLD_R := 14.0
const ASSAULT_EVENT_ASSIST_R := 110.0
const ASSAULT_EVENT_CALM_SEC := 4.0
## Обход центрального пня — на таком расстоянии от него, со стороны базы
const ASSAULT_EVENT_LAIR_BYPASS_R := 36.0
## Ноги маршрута длиннее этого режутся промежуточными точками: ворота точки
## держат конницу (4.6 м/с) до подхода туш (1.54 м/с), и кулак не растягивается
## больше чем на ногу
const ASSAULT_EVENT_LEG_MAX := 45.0
## У прохода базы блок сужается до стольких колонн (проход WALL_GAP_W 26 м,
## пень в 21 м от прохода)
const ASSAULT_EVENT_GATE_COLS := 2
## Нижний проход базы: точка перед проходом и за ним (по Z от стены)
const ASSAULT_EVENT_GATE_OUT := 12.0
const ASSAULT_EVENT_GATE_IN := 14.0
## Застрял: центр отряда не сдвинулся на STUCK_M за STUCK_SEC — тот же
## приказ ещё раз, не больше STUCK_MAX раз на точку
const ASSAULT_EVENT_STUCK_SEC := 25.0
const ASSAULT_EVENT_STUCK_M := 3.0
const ASSAULT_EVENT_STUCK_MAX := 3

## ═══════════════════════════════════════════════════════════════════════════
## РЕГУЛЯРНЫЕ РЕЙДЫ ОРДЫ ПО ЧАСАМ (ТЗ 14.10.2026, п. 1; scripts/goblin/RaidManager.gd)
## ═══════════════════════════════════════════════════════════════════════════
## Тот же движок волн, что у штурма (GoblinFortressAssaultEvent: площадка
## сбора, кулак, маршрут бродом в нижний проход базы, групповое агро), но
## ЦЕЛИ РЕЙДА — по приоритету: рабочие → башни → бараки → дома и прочие
## постройки; крепости — последними. Состав — конница орды (свиновсадники),
## туши, пехота
const RAID_ENABLED := true
## Расписание: секунда партии → состав. 10:00 три конницы, 12:00 ещё три
## вслед, 15:00 комбинированная штурмовая группа 3/3/3
const RAID_SCHEDULE := [
	{"t": 600.0,  "comp": {"goblin_rider": 3}},
	{"t": 720.0,  "comp": {"goblin_rider": 3}},
	{"t": 900.0,  "comp": {"goblin_rider": 3, "big_goblin": 3, "goblin_spearman": 3}},
]
## СДВОЕННЫЕ ВОЛНЫ КРУПНЫХ СРОКОВ (30:00, 45:00, 60:00): состав срока делится
## пополам — первый отряд (половина) выходит в срок, второй — через
## PAIR_GAP_SEC вслед той же дорогой. Выключатель — для стендов кулака
const ASSAULT_EVENT_PAIR := true
const ASSAULT_EVENT_PAIR_GAP_SEC := 120.0
## Цели рейда: рабочего ищем в RAID_WORKER_R от отряда (по всей базе), прочие
## постройки — ближайшие без радиуса. Список целей кэшируется на такт
const RAID_WORKER_R := 80.0
