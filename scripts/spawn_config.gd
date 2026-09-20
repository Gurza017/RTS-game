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
const GOBLIN_PEACE_SEC := 600.0
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
const GNOLL_START_SQUADS := 3
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
const AI_HOME_GUARD_DEPTH := 9.0        # первый отряд охраны — за замком, м
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
## тревоги. Отряд, по которому бьют, просыпается вне очереди
const AI_HOME_GUARD_WAVE_SQUADS := 3
const AI_HOME_GUARD_WAVE_GAP_SEC := 180.0
## То же у резерва орды за лагерем (DormantReserve)
const RESERVE_WAVE_SQUADS := 4
const RESERVE_WAVE_GAP_SEC := 180.0
## Условия и триггеры: перемирие, час генерального штурма, рейды, башни
const AI_TRUCE_SEC := 600.0
const AI_ASSAULT_AT_SEC := 1800.0
const AI_RAID_INTERVAL_SEC := 60.0
const AI_TOWERS := 2
const AI_MINE_SQUADS := 1
