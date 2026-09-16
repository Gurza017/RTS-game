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
const GOBLIN_RAID_INTERVAL_SEC := 40.0
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
## Гноллы: стартовая стая и волны по удару в пень
const GNOLL_START_SQUADS := 3
const GNOLL_WAVE_SQUADS := 3
const GNOLL_WAVE_SEC := 180.0
const GNOLL_WAVES_MAX := 3
const GNOLL_COOLDOWN_SEC := 600.0
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
const AI_HOME_GUARD_HEAL_FRAC := 0.02
## Условия и триггеры: перемирие, час генерального штурма, рейды, башни
const AI_TRUCE_SEC := 600.0
const AI_ASSAULT_AT_SEC := 1800.0
const AI_RAID_INTERVAL_SEC := 60.0
const AI_TOWERS := 2
const AI_MINE_SQUADS := 1
