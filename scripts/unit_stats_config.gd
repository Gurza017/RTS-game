extends RefCounted
## ХАРАКТЕРИСТИКИ ЮНИТОВ, СТОЙКИ, ВЕТЕРАНСТВО, ЦЕНЫ, ПОСТРОЙКИ, ЭКОНОМИКА — только параметры.
## Подключение: const _UStats := preload("res://scripts/unit_stats_config.gd")
## История чисел и разворотов — docs/config_notes/unit_stats_config.md; расчёт — docs/BALANCE_MATH.md

const _Forge := preload("res://scripts/forge_config.gd")
const _PerfU := preload("res://scripts/perf_config.gd")   # ручка food_big_army

# ── ХАРАКТЕРИСТИКИ РОДОВ ВОЙСК (STATS) ──
const STATS := {
	# ── МЕЧНИК (Warrior) — тяжёлая пехота, элитный танк ──
	"warrior": {
		"health": 340.0,                     # запас жизни, HP
		"name_genitive_plural": "мечников",
		"movement_speed": 1.9,               # скорость ходьбы, м/с (тяжёлый доспех)
		"attack_1": 20.0,                     # обычный удар (три подряд)
		"attack_2": 28.0,                     # мощный удар (ротация 3+1)
		"attack_range": 1.6,                 # длина руки, м: ближе — бьёт
		"attack_cooldown": 1.6,                     # пауза между ударами, с
		"defense": 0.0,                      # защита: вычитается из входящего урона
		"armor": 10.0,                    # броня: доля снижения, см. ARMOR_SOFTNESS
		"morale": 85.0,                     # мораль 0..100
		"push_force": 3.4,                   # напор: продавливает строй
		"squad_slots": 2.0,  # слотов лимита отрядов на один отряд
		"squad_weight": 2.0,  # вес бойца в счёте силы и морали отряда
		"description": "Heavy melee fighter. Hits hardest in a straight duel and shoves enemy ranks back on contact.",
	},

	# ── КОПЕЙЩИК (Spearman) — основная пехота ──
	"spearman": {
		"health": 180.0,                     # запас жизни, HP — основа шкалы TTK
		"name_genitive_plural": "копейщиков",
		"movement_speed": 2.0,               # скорость ходьбы, м/с
		"attack_1": 14.0,                     # урон тычка копьём
		"attack_2": 16.0,                     # мощного удара у копья нет — число про запас
		"attack_range": 2.5,                 # длина копья, м — больше, чем у меча
		"attack_cooldown": 2.0,                     # пауза между ударами, с
		"defense": 0.0,                      # защита (стойка «оборона» даёт +5)
		"armor": 3.0,                     # броня: доля снижения, см. ARMOR_SOFTNESS
		"morale": 75.0,                     # мораль 0..100
		"push_force": 1.0,                   # напор в свалке
		"description": "Backbone infantry. Holds the line shoulder to shoulder — spears level automatically when the enemy closes in.",
	},

	# ── ЛУЧНИК (Archer) — стрелок, слаб в ближнем бою ──
	"archer": {
		"health": 110.0,                     # запас жизни, HP
		"name_genitive_plural": "лучников",
		"movement_speed": 2.1,               # скорость ходьбы, м/с
		"attack_1": 22.0,                     # урон выстрела
		"attack_2": 30.0,                     # мощный выстрел (числом пока не пользуется)
		"attack_range": 15.0,                # базовая дальность, м (кузница поднимает до потолка)
		"attack_range_cap": 25.0,  # жёсткий потолок дальности, м (база + кузница)
		"attack_cooldown": 3.0,                     # пауза между выстрелами, с
		"defense": 0.0,                      # защита
		"armor": 1.0,                     # броня почти нулевая
		"morale": 45.0,                     # мораль 0..100 — стрелок паникует первым
		"push_force": 0.0,                   # напора нет: стрелок никого не давит
		"arrow_speed": 20.0,                 # скорость стрелы, м/с: видно дугу
		"arrow_arc": 0.20,                   # высота дуги как доля дальности
		"description": "Ranged skirmisher. Long reach and a fast squad, but folds quickly if caught in melee.",
	},

	# ── МОНАХ (Monk) — лекарь, не боец ──
	"monk": {
		"health": 220.0,                      # запас жизни одной модели, HP
		"name_genitive_plural": "монахов",
		"movement_speed": 2.0,               # скорость ходьбы, м/с
		# урон 0 выключает авто-агро, ответ на удар и тыловой напор
		"attack_1": 0.0,
		"attack_2": 0.0,
		"attack_range": 1.4,                 # длина руки, м
		"attack_cooldown": 1.6,              # пауза между ударами, с
		"defense": 0.0,                      # защита
		"armor": 1.0,                        # броня
		"morale": 60.0,                      # мораль 0..100
		"push_force": 0.3,                   # напор в свалке — почти нулевой
		"description": "Support unit. Weak in a fight — keep it behind the line.",
	},

	# ── ГОБЛИН-КОПЕЙЩИК — орда, третья сторона (Constants.FACTION_GOBLIN) ──
	"goblin_spearman": {
		"health": 165.0,                     # запас жизни, HP
		"name_genitive_plural": "гоблинов",
		"movement_speed": 2.2,               # скорость, м/с: орда идёт быстрее людей
		"attack_1": 12.0,                     # «Attack Fast» — три быстрых тычка...
		"attack_2": 18.0,                    # ...затем «Attack Strong» (ротация 3+1)
		"attack_range": 2.2,                 # длина копья, м
		"attack_cooldown": 2.5,              # пауза между ударами, с
		"defense": 0.0,                      # защита
		"armor": 1.0,                        # брони нет вовсе
		"morale": 75.0,                     # мораль 0..100
		"push_force": 0.8,                   # напор ниже людского: берут числом
		"description": "Goblin spear mob. Weak one on one, dangerous in a hundred.",
	},
	# ── БОЛЬШОЙ ГОБЛИН — медленная туша, стена мяса ──
	"big_goblin": {
		"health": 1850.0,                    # запас жизни, HP (число, не ссылка)
		"name_genitive_plural": "больших гоблинов",
		"movement_speed": 1.54,              # скорость, м/с
		"attack_1": 55.0,                    # удар
		"attack_range": 3.5,  # длинный выпад, м
		"attack_cooldown": 2.7,  # пауза между ударами, с
		"defense": 2.0,
		"armor": 6.0,
		"morale": 90.0,  # мораль: туша не бежит
		"push_force": 10.0,
		"squad_weight": 3.0,  # вес бойца в счёте силы и морали отряда
		"description": "Big Goblin. Slow meat wall with a wide sweep.",
	},

	# ── ГНОЛЛ — быстрый хрупкий метатель ──
	"gnoll": {
		"health": 55.0,  # запас жизни, HP
		"name_genitive_plural": "гноллов",
		"movement_speed": 1.85,  # м/с — чуть медленнее копейщика (2.0): пехота его нагоняет
		"attack_1": 15.0,  # урон броска
		"attack_range": 13.5,  # дальность броска, м
		"attack_cooldown": 1.77,             # пауза между бросками, с
		"defense": 0.0,
		"armor": 0.0,
		"morale": 75.0,  # мораль 0..100
		"push_force": 0.0,
		"description": "Gnoll bone-thrower. Fast, fragile, never fights in melee.",
	},
	# ── НАЕЗДНИК НА КАБАНЕ — ударная конница орды ──
	"goblin_rider": {
		"health": 300.0,  # запас жизни, HP
		"name_genitive_plural": "наездников",
		"movement_speed": 4.6,  # скорость, м/с: рассекает поле
		"attack_1": 25.0,                    # урон обычного удара седока
		"attack_2": 35.0,                    # урон мощного удара (ротация 3+1)
		"attack_range": 2.5,                 # длина руки с седла, м
		"attack_cooldown": 2.1,              # пауза между ударами, с — вдвое чаще пехоты
		"defense": 0.0,                      # защита
		"armor": 4.0,                        # броня: шкура кабана
		"morale": 110.0,                     # мораль выше сотни: конница не дрогнет
		"push_force": 18.0,                  # напор: кабан давит строй сильнее рыцаря
		"charge_push_mult": 2.5,  # множитель толчка; >1 — ударная конница (таран и отбрасывание)
		"push_every": 1,  # толчок на каждый N-й удар (1 — каждый)
		"charge_range": 14.0,   # за сколько метров до цели начинается разгон
		"charge_min_runup": 10.0,            # таран только после стольких метров бега по прямой
		"charge_speed_mult": 1.8,            # во сколько раз быстрее на разгоне
		"charge_impact_frac": 0.5,           # доля МАКС. запаса ЖЕРТВЫ, снимаемая тараном
		"squad_weight": 2.0,  # один всадник = два пехотинца в счёте силы отряда
		"charge_splash": 2.0,                # радиус первого ряда контакта, м
		"charge_knockback": 1.3,             # на сколько метров отлетают накрытые
		"charge_breakthrough": 2.0,  # метров проезда сквозь строй сразу после удара
		"charge_row_kill": 1,  # первый ряд затоптан насмерть (1 — да)
		"charge_row2_frac": 0.3,  # второй ряд теряет эту долю запаса
		"charge_row2_knock": 2.8,  # отлёт второго ряда, м
		"charge_row_depth": 1.1,  # глубина одного ряда при ударе по рядам, м
		"charge_counter_frac": 0.35,         # доля СВОЕГО запаса за навал на копья
		"description": "Pig rider. Fast shock cavalry — hits hard, dies fast.",
	},

	# ── ТРОЛЛЬ — босс логова ──
	"troll": {
		"health": 8160.0,                   # запас жизни, HP
		"name_genitive_plural": "троллей",
		"movement_speed": 2.88,              # скорость, м/с
		"attack_1": 70.0,                    # удар дубиной по цели
		"attack_2": 100.0,
		"attack_range": 4.5,                 # длина дубины, м
		"attack_cooldown": 1.7,            # пауза между ударами, с
		"defense": 0.0,
		"armor": 12.0,                       # толстая шкура
		"morale": 300.0,                     # не паникует никогда
		"push_force": 30.0,                  # сминает шеренгу напором
		"push_every": 1,
		"charge_push_mult": 4.6,
		"charge_range": 10.0,                # за сколько метров до цели начинается разгон
		"charge_min_runup": 6.0,
		"charge_speed_mult": 1.8,
		"charge_impact_frac": 0.6,           # доля МАКС. запаса жертвы за таран
		"charge_splash": 2.5,                # кого накрывает удар с разгона, м
		"charge_knockback": 3.0,             # на сколько отлетают, м
		"charge_breakthrough": 2.5,          # вклинивается в строй, м
		"charge_counter_frac": 0.02,         # копья царапают, а не валят
		"squad_weight": 60.0,                # один тролль = отряд пехоты в морали
		"description": "Lair boss. Club sweeps the line, charges like a boar, tires after a flurry.",
	},

	# ── Свинобосс — полководец орды на кабане (PigBoss.gd, ТЗ 28.10.2026) ──
	"pig_boss": {
		"health": 7500.0,                   # запас жизни, HP — уровня тролля
		"name_genitive_plural": "свинобоссов",
		"movement_speed": 4.2,               # скорость, м/с: чуть медленнее наездника
		"attack_1": 90.0,                    # тяжёлый удар седока (свип по сектору)
		"attack_2": 130.0,
		"attack_range": 3.0,                 # длина оружия с седла, м
		"attack_cooldown": 1.6,              # пауза между ударами, с
		"defense": 0.0,
		"armor": 14.0,                       # доспех: плоское снижение урона
		"morale": 300.0,                     # не паникует никогда
		"push_force": 30.0,                  # напор кабана-гиганта
		"push_every": 1,
		"charge_push_mult": 4.0,             # ударная конница: таран и отбрасывание
		"charge_range": 14.0,                # за сколько метров до цели начинается разгон
		"charge_min_runup": 8.0,
		"charge_speed_mult": 1.7,
		"charge_impact_frac": 0.55,          # доля МАКС. запаса жертвы за таран
		"charge_splash": 2.5,                # радиус первого ряда контакта, м
		"charge_knockback": 2.5,             # на сколько отлетают накрытые, м
		"charge_breakthrough": 2.5,          # метров проезда сквозь строй
		"charge_row_kill": 1,
		"charge_row2_frac": 0.3,
		"charge_row2_knock": 2.5,
		"charge_row_depth": 1.1,
		"charge_counter_frac": 0.05,         # копья царапают, а не валят
		"squad_weight": 50.0,                # один босс = отряд пехоты в морали
		"description": "Warchief on a giant boar. Suppression aura, war screech, leads the horde.",
	},

	# ── РАБОЧИЙ (Worker) — не боец ──
	"worker": {
		"health": 70.0,  # запас жизни, HP
		"attack_1": 4.0,  # урон топора
		"attack_range": 1.3,  # длина руки, м
		"attack_cooldown": 1.6,  # пауза между ударами, с
		"walk_speed_empty": 3.2,             # скорость БЕЗ груза, м/с
		"walk_speed_loaded": 2.2,            # скорость С грузом, м/с
		"defense": 0.0,                      # защита
		"armor": 0.0,                        # броня
		"morale": 40.0,                      # мораль 0..100
		"push_force": 0.5,                   # напор: рабочего сдвигает любой боец
		"gather_time": 2.5,                  # базовый цикл добычи, с (на ресурсе × GATHER_TIME_MULT)
		"gather_amount": 20.0,               # сколько ресурса приносит за ходку
		"description": "Gathers resources and builds structures. Fights back with an axe when cornered.",
	},
}

## ── ДОБЫЧА: ЦИКЛ ПО РЕСУРСАМ ──
## Доля базового gather_time на каждом ресурсе
const GATHER_TIME_MULT := {
	Constants.RESOURCE_WOOD:  0.80,   # дерево — ходовее всего, добывается быстрее
	Constants.RESOURCE_STONE: 1.10,   # камень
	Constants.RESOURCE_GOLD:  1.30,   # золото — самое медленное
	Constants.RESOURCE_FOOD:  1.00,   # разделка туши — базовый цикл
}

## Какой ключ бонуса кузницы ускоряет добычу ИМЕННО этого ресурса
const GATHER_BONUS_KEY := {
	Constants.RESOURCE_WOOD:  "bonus_gather_wood",
	Constants.RESOURCE_STONE: "bonus_gather_stone",
	Constants.RESOURCE_GOLD:  "bonus_gather_gold",
}

## Доля цикла на данном ресурсе (незнакомый — базовый)
static func gather_time_mult(res_type: int) -> float:
	return float(GATHER_TIME_MULT.get(res_type, 1.0))

## Потолок ускорения добычи раздельной веткой кузницы — доля цикла долой
const GATHER_PCT_CAP := 0.60

## Потолок удешевления найма: самый дешёвый рабочий всё равно стоит еды
const HIRE_DISCOUNT_CAP := 0.60
## Потолок ускорения найма и стройки (доля долой от времени)
const TRAIN_SPEED_CAP := 0.70

## Размеры гоблинских отрядов лежат в их собственном конфиге (см. squad_size)
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

## ── СТОЙКИ ОТРЯДА (STANCES) — кнопки [АТАКА] / [ЗАЩИТА] ──
const STANCE_ATTACK  := "attack"
const STANCE_DEFENSE := "defense"

## Общий множитель силы толчка (knockback) для всех юнитов
## Прибавка к напору и упору за каждого своего в ряду за спиной (ТЗ 31.10.2026, ручка rank_push)
const PUSH_RANK_SUPPORT := 0.5
const PUSH_GLOBAL_SCALE := 0.35
## Долгий бой: запас жизни родов из TTK_UNITS × TTK_HEALTH_MULT, пехотный толчок × INFANTRY_PRESS_MULT
## (ручка perf_config.ttk_press)
const TTK_HEALTH_MULT := 1.5
const TTK_UNITS := ["spearman", "archer", "warrior", "goblin_spearman",
	"goblin_rider", "big_goblin"]
const INFANTRY_PRESS_MULT := 1.8

const STANCES := {
	"attack": {
		"name":              "Attack",
		"push_mult":         1.0,
		"push_resist":       1.0,
		"attack_speed_mult": 1.0,
		"move_speed_mult":   1.0,
		"morale_mult":       1.0,
		"defense_bonus":     0.0,
		"holds_ground":      false,
		"lock_position":     false,
	},
	"defense": {
		"name":              "Defend",
		"push_mult":         0.0,    # своего пуша у фаланги нет вовсе
		"push_resist":       0.5,    # входящий толчок срезан вдвое (упор щитами)
		"attack_speed_mult": 1.25,   # +25% скорости атаки
		"move_speed_mult":   1.0,    # шаг в [S] не замедлен; ⚠ менять только по явному ТЗ (разворотов: 2)
		"morale_mult":       1.30,   # +30% морали
		"defense_bonus":     5.0,    # +5 защиты
		"holds_ground":      true,   # с места не сходят (кроме смыкания рядов)
		"lock_position":     false,  # глухой замок позиции снят; ⚠ не включать без явного ТЗ
	},
}

## ── ШАГ ПЕХОТЫ = БЕГ − 15 % ──
## Шаг копейщиков, лучников, мечников и монахов = прежний бег × WALK_FROM_RUN; бег как абсолют не меняется
const RUN_SPEED_FACTOR := 1.35          ## бег к прежнему шагу (Unit.SPRINT_SPEED_FACTOR)
const WALK_FROM_RUN := 0.85             ## новый шаг = бег × 0.85
const WALK_BOOST_UNITS := ["spearman", "archer", "warrior", "monk"]
const RETREAT_RUN_MULT := 1.30          ## отход в замок: бег +30 %

## Множитель шага рода войск к его movement_speed (1.0 — без изменений)
static func walk_boost(unit_id: String) -> float:
	if unit_id in WALK_BOOST_UNITS:
		return RUN_SPEED_FACTOR * WALK_FROM_RUN
	return 1.0

## Словарь стойки по id; неизвестная стойка → «атака» (стандартные параметры)
static func get_stance(stance_id: String) -> Dictionary:
	return STANCES.get(stance_id, STANCES["attack"])

## ── ОТСТУП ОТ СКАЛ ПРИ ОБХОДЕ, м от кромки (Unit.nav_clearance по роду войск) ──
const NAV_CLEARANCE_INFANTRY := 1.5
const NAV_CLEARANCE_CAVALRY := 2.2
const NAV_CLEARANCE_GIANT := 3.5
const NAV_CLEARANCE_TROLL := 4.0

## ── БРОНЯ ──
## Мягкость брони: урон × SOFTNESS / (SOFTNESS + защита)
const ARMOR_SOFTNESS := 25.0
## Нижний предел суммарной защиты (минус — уязвимость)
const ARMOR_MIN_TOTAL := -12.0

static func damage_after_armor(amount: float, total_defense: float) -> float:
	var d: float = maxf(total_defense, ARMOR_MIN_TOTAL)
	if d == 0.0:
		return amount
	return amount * ARMOR_SOFTNESS / (ARMOR_SOFTNESS + d)

## ── МОРАЛЬ И ПАНИКА ──
const MORALE_MAX := 100.0  # потолок морали отряда
## Потеря морали за гибель бойца: число / полный штат отряда
const MORALE_LOSS_PER_DEATH := 40.0
const MORALE_LOSS_PER_HIT := 0.02  # потеря за полученный удар
const MORALE_GAIN_PER_KILL := 2.0  # прибавка за убийство
const MORALE_REGEN_PER_SEC := 3.0  # восстановление, в секунду

## Пороги паники: доля морали (абсолютный) и доля от базовой морали рода (относительный)
const PANIC_THRESHOLD := 0.30  # справочно: код не читает
const PANIC_RATIO := 0.5  # справочно: код не читает

## «Нас почти не осталось»: паника по счёту живых (не больше LAST_MEN при штате от MIN_ROSTER)
const PANIC_LAST_MEN := 6  # справочно: код не читает

## Предохранитель: паника возможна только при живых не больше этой доли полного штата
const PANIC_ALIVE_FRAC := 0.30
## Шанс паники на каждую новую потерю ниже порога (аура своей легенды делит, чужой — умножает)
const PANIC_CHANCE := 0.5
## Ступор (потеря управления), с
const PANIC_STUN_SEC := 14.0
## Полуугол конуса разбега, град
const PANIC_CONE_DEG := 30.0
## Отступ от края карты при выборе точки бегства, м
const PANIC_EDGE_MARGIN := 18.0
## Дальность разбега, м (врассыпную)
const PANIC_FLEE_DIST := 12.0
## Радиус, в котором паника ищет угрозу для вектора бегства, м
const PANIC_THREAT_R := 30.0
## Паника — один раз: отбежал → в замок лечиться; места нет — ждёт у кольца замка
const PANIC_MAX_RUNS := 1  # бегств на отряд
const PANIC_HEAL_RETRY_SEC := 10.0  # переспрос места в замке, с
const PANIC_HEAL_WAIT_R := 3.0  # где ждать у кольца замка, м
## Разброс паникующих у точки бегства, м (× √штата); сбор — в SPREAD × REGROUP_MULT
const PANIC_SPREAD := 4.0
const PANIC_REGROUP_MULT := 1.6
## Во сколько раз режется защита паникующего (−30 %)
const PANIC_ARMOR_MULT := 0.70
const PANIC_RECOVER_MORALE := 0.55  # мораль после восстановления, доля MORALE_MAX

## ── ПОСЛЕДНИЙ ВЫЖИВШИЙ (узел кузницы LAST_STAND_CELL у пехоты, ТЗ 28.10.2026, блок 3) ──
## Шанс, что последний боец выбитого отряда уцелеет призраком (жребий — AudioManager.rng)
const LAST_STAND_CHANCE := 0.4
## Доля запаса, с которой уцелевший уходит в крепость
const LAST_STAND_HP_FRAC := 0.10
## Срок призрака, с: чужие его не видят, пока идёт лечиться; истёк или вошёл в гарнизон — снова как все
const LAST_STAND_GHOST_SEC := 90.0
## Период красного мигания призрака, с (вспышка в instance-цвете, как у удара)
const LAST_STAND_BLINK_SEC := 0.5
## Ячейка древа пехоты (spearman/warrior), дающая механику
const LAST_STAND_CELL := "3c"

## ── АУРА ЛЕГЕНДАРНОГО ОТРЯДА ──
const LEGEND_AURA_RADIUS := 28.0  # радиус, м
const LEGEND_AURA_ALLY_MULT := 1.50  # множитель морали своих отрядов рядом
const LEGEND_AURA_FOE_MULT := 0.75  # множитель морали вражеских новобранцев рядом
## Ранг, с которого отряд считается легендарным (золотой вымпел): 9 ступеней + легенда
const LEGEND_TIER := 10

## ── ЧИСЛА ЛЕГЕНДАРНЫХ ПЕРКОВ ──
const LEGEND_PIERCE_FRAC := 0.30      ## «Пробитие брони»: игнорирует 30 % защиты
const LEGEND_HEAL_FRAC := 0.15        ## «Кровь за кровь»: доля запаса за убийство
const LEGEND_PUSH_MULT := 2.0         ## «Таран»: во сколько раз крепче упор и напор

## Одно поле стойки с дефолтом
static func stance_stat(stance_id: String, key: String, default: float = 0.0) -> float:
	var d: Dictionary = get_stance(stance_id)
	return d.get(key, default)

## Вернуть словарь характеристик юнита ("warrior"/"spearman"/"archer"/"worker")
static func get_stats(unit_id: String) -> Dictionary:
	return STATS.get(unit_id, {})

## Одно значение с дефолтом: stat("warrior", "push_force", 1.0)
static func stat(unit_id: String, key: String, default: float = 0.0) -> float:
	var d: Dictionary = STATS.get(unit_id, {})
	return d.get(key, default)

## ── ПОСТРОЙКИ (BUILDINGS) ──
## Папка иконок кузницы (smith_icon_path)
const SMITH_ICONS_DIR := "res://assets/factions/humans/icons/buildings/icons_for_smith/"

## ── ЁМКОСТЬ КУЧИ РУДНИКА (золото / камень), единиц ──
const DEFAULT_CLUSTER_GOLD  := 25000.0
const DEFAULT_CLUSTER_STONE := 30000.0

## Ёмкость кучи по виду ресурса ("gold" / "stone")
static func cluster_stock(kind: String) -> float:
	match kind:
		"gold":  return DEFAULT_CLUSTER_GOLD
		"stone": return DEFAULT_CLUSTER_STONE
	return DEFAULT_CLUSTER_STONE

## Полный путь к иконке кузницы по имени файла
static func smith_icon_path(icon_name: String) -> String:
	if icon_name.is_empty():
		return ""
	if icon_name.begins_with("res://") or icon_name.begins_with("user://"):
		return icon_name
	var f := icon_name
	if f.get_extension().is_empty():
		f += ".png"
	return SMITH_ICONS_DIR + f

static func smith_icon(icon_name: String) -> Texture2D:
	var path := smith_icon_path(icon_name)
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("Иконка кузницы не найдена: %s (искали по имени «%s»)"
			% [path, icon_name])
		return null
	var tex := ResourceLoader.load(path) as Texture2D
	if tex == null:
		push_warning("Иконка кузницы не читается как текстура: %s" % path)
	return tex

## ── СТАРТОВЫЙ ЗАПАС ──
## Игрок: сумма стартовой инфраструктуры (крепость, 3 дома, бараки, кузница, 2 узла экономики,
## 5 рабочих, отряд копейщиков) + 2-3 % запаса; сложность — множителем player_resource_mult
## ⚠ Менять только по явному ТЗ владельца (разворотов: 1)
const PLAYER_STARTING_RESOURCES := {
	Constants.RESOURCE_WOOD:  3600.0,   # дерево: замок, дома, бараки, кузница
	Constants.RESOURCE_GOLD:  1500.0,   # золото: кузница, исследования, найм
	Constants.RESOURCE_STONE: 2100.0,   # камень: только постройки
	Constants.RESOURCE_FOOD:   400.0,   # еда: рабочие и первый отряд
}

## ИИ: старт равный игроку (правило партии); стороны расходятся множителями сложности (ai_resource_mult)
const AI_STARTING_RESOURCES := {
	Constants.RESOURCE_WOOD:  3600.0,     # дерево
	Constants.RESOURCE_GOLD:  1500.0,     # золото
	Constants.RESOURCE_STONE: 2100.0,     # камень
	Constants.RESOURCE_FOOD:   400.0,     # еда
}

## Стартовый запас фракции — всегда полный набор из четырёх ресурсов
static func starting_resources(faction: int) -> Dictionary:
	var src: Dictionary = AI_STARTING_RESOURCES if faction == Constants.FACTION_ENEMY \
		else PLAYER_STARTING_RESOURCES
	return {
		Constants.RESOURCE_WOOD:  float(src.get(Constants.RESOURCE_WOOD,  0.0)),
		Constants.RESOURCE_GOLD:  float(src.get(Constants.RESOURCE_GOLD,  0.0)),
		Constants.RESOURCE_STONE: float(src.get(Constants.RESOURCE_STONE, 0.0)),
		Constants.RESOURCE_FOOD:  float(src.get(Constants.RESOURCE_FOOD,  0.0)),
	}

## Постройки: подпись, запас жизни, время стройки одного рабочего (с), габарит (м), цена, доступна ли рабочему, иконка
const BUILDINGS := {
	"castle": {
		"name": "Замок",                          # подпись в интерфейсе
		"max_hp": 15000.0,                         # запас жизни постройки
		"build_time": 15.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(8.0, 6.0, 8.0),           # габарит коллизии и спрайта, м
		"cost_wood": 1200.0,                       # цена: дерево
		"cost_gold": 400.0,                       # цена: золото
		"cost_stone": 800.0,                      # цена: камень
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/Castle.png",
	},
	"goblin_hut": {
		"name": "Хижина гоблинов",                # подпись в интерфейсе
		"max_hp": 1000.0,                         # запас жизни хижины
		"build_time": 10.0,                       # секунд отстройки (орда строит сама)
		"size": Vector3(4.0, 3.5, 4.0),           # габарит, м: шаг деревни от него
		"cost_wood": 0.0,                         # орда ресурсов людей не тратит
		"cost_gold": 0.0,
		"cost_stone": 0.0,
		"worker_buildable": false,                # игроку не строится
		"icon": "",
	},
	# ── Кузница гоблинов (ТЗ 28.10.2026): цена и время для ИИ орды и будущей ручной стройки ──
	"goblin_forge": {
		"name": "Кузница гоблинов",
		"max_hp": 2400.0,                         # запас жизни
		"build_time": 30.0,                       # секунд отстройки (орда строит сама, GoblinForgeAI)
		"size": Vector3(4.0, 3.5, 4.0),           # базовый габарит хижины; ×goblin_config.GOBLIN_FORGE_SIZE_MULT
		"cost_wood": 300.0,
		"cost_gold": 120.0,
		"cost_stone": 0.0,
		"cost_food": 150.0,
		"worker_buildable": false,                # игроку (людям) не строится
		"icon": "res://assets/ui/goblin_forge/pikes.png",
	},
	"barracks": {
		"name": "Бараки",                         # подпись в интерфейсе
		"max_hp": 7000.0,                         # запас жизни постройки
		"build_time": 20.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(3.5, 2.2, 3.5),           # габарит, м
		"cost_wood": 500.0,                       # цена: дерево
		"cost_gold": 300.0,                       # цена: золото
		"cost_stone": 400.0,                      # цена: камень
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/Barracks.png",
	},
	"archery": {
		"name": "Стрелковая",                     # подпись в интерфейсе
		"max_hp": 3800.0,                         # запас жизни постройки
		"build_time": 20.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(3.5, 2.2, 3.5),           # габарит, м (как у бараков)
		"cost_wood": 450.0,                       # цена: дерево
		"cost_gold": 250.0,                       # цена: золото
		"cost_stone": 350.0,                      # цена: камень
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/Archery.png",
	},
	"tower": {
		"name": "Башня",                          # подпись в интерфейсе
		"max_hp": 8000.0,                         # запас жизни постройки
		"build_time": 30.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(3.4, 3.0, 3.4),           # габарит, м
		"cost_wood": 400.0,                       # цена: дерево
		"cost_gold": 100.0,                       # цена: золото
		"cost_stone": 500.0,                      # цена: камень (башня каменная)
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/Tower.png",
		"construction_scale": 1.0,                # своя картинка стройки
		"ruin_scale": 1.0,                        # своё пепелище
	},
	"smithy": {
		"name": "Кузница",                        # подпись в интерфейсе
		"max_hp": 4000.0,                         # запас жизни постройки
		"build_time": 40.0,                       # секунд работы одного рабочего (вдвое дольше обычных)
		"size": Vector3(4.0, 3.0, 4.0),           # габарит, м
		"cost_wood": 600.0,                       # цена: дерево
		"cost_gold": 300.0,                       # цена: золото
		"cost_stone": 500.0,                      # цена: камень
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/Monastery.png",
		"marker_top_uv": 0.40,  # верх рамки выделения: доля кадра сверху (UV.y), 0 — по рисунку
	},
	"mine": {
		"name": "Золотой рудник",                 # подпись в интерфейсе
		"max_hp": 1250.0,                          # запас жизни постройки
		"build_time": 10.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(3.0, 2.0, 3.0),           # габарит, м
		"cost_wood": .0,                          # рудник бесплатен: ставится на жилу
		"cost_gold": 0.0,
		"cost_stone": 0.0,
		"worker_buildable": false,                # кнопки на панели рабочего нет
		"icon": "res://assets/environment/resources/Gold_mine/GoldMine_Active.png",  # иконка — сама шахта
	},
	"house": {
		"name": "Дом",                            # подпись в интерфейсе
		"max_hp": 380.0,                          # запас жизни постройки
		"build_time": 10.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(2.6, 2.2, 2.6),           # габарит, м
		"cost_wood": 150.0,                        # цена: дерево (дом дешёвый)
		"cost_gold": 0.0,
		"cost_stone": 100.0,
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/House1.png",
	},
	"house2": {
		"name": "Дом", "max_hp": 380.0, "build_time": 10.0,
		"size": Vector3(2.6, 2.2, 2.6),
		"cost_wood": 150.0, "cost_gold": 0.0, "cost_stone": 100.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/House2.png",
	},
	"house3": {
		"name": "Дом", "max_hp": 180.0, "build_time": 10.0,
		"size": Vector3(2.6, 2.2, 2.6),
		"cost_wood": 150.0, "cost_gold": 0.0, "cost_stone": 100.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/House3.png",
	},
	# ── РЫНОК — обменник ресурсов (курс — MARKET), габарит бараков ──
	"market": {
		"name": "Рынок",
		"max_hp": 3000.0,
		"build_time": 25.0,
		"size": Vector3(3.5, 2.2, 3.5),
		"cost_wood": 400.0,
		"cost_gold": 200.0,
		"cost_stone": 150.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/Market.png",
	},
	# ── СКЛАД — точка сдачи ресурсов у делянки, габарит дома ──
	"storehouse": {
		"name": "Склад",
		"max_hp": 1200.0,
		"build_time": 12.0,
		"size": Vector3(2.6, 2.2, 2.6),
		"cost_wood": 200.0,
		"cost_gold": 0.0,
		"cost_stone": 50.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/Storehouse.png",
	},
	# ── ЗАГОН ДЛЯ ОВЕЦ — ставится сразу, без стройки ──
	"sheep_pen": {
		"name": "Овцеферма",
		"max_hp": 400.0,
		"build_time": 18.0,                       # стройка рабочими (ТЗ 30.10.2026); ИИ ставит сразу
		"instant_build": true,
		"size": Vector3(5.0, 1.4, 5.3),
		"cost_wood": 120.0,
		"cost_gold": 0.0,
		"cost_stone": 0.0,
		"worker_buildable": true,
		"icon": "res://assets/environment/resources/Wooden/Wooden Fence_64x64 tile.png",
		"construction_scale": 0.9,
		"ruin_scale": 0.9,
	},
	"troll_lair": {
		"name": "Логово тролля", "max_hp": 8000.0, "build_time": 0.0,
		"size": Vector3(12.0, 8.0, 12.0),
		"cost_wood": 0.0, "cost_gold": 0.0, "cost_stone": 0.0,
		"worker_buildable": false, "icon": "",
	},
	# Служебные: не строятся рабочими, но запас жизни настраивается так же
	"town_center": {
		"name": "Городской центр", "max_hp": 500.0, "build_time": 0.0,
		"size": Vector3(4.0, 2.5, 4.0),
		"cost_wood": 0.0, "cost_gold": 0.0, "cost_stone": 0.0,
		"worker_buildable": false, "icon": "",
	},
	"construction_site": {
		"name": "Стройка", "max_hp": 120.0, "build_time": 0.0,
		"size": Vector3(3.0, 2.0, 3.0),
		"cost_wood": 0.0, "cost_gold": 0.0, "cost_stone": 0.0,
		"worker_buildable": false, "icon": "",
	},
}

## ── ЕДА: ДОМА ──
## Дом даёт мало намеренно: 40 домов ≈ 5 еды/с — две трети расхода полной армии, остальное — загоны
const HOUSE_FOOD_INCOME   := 1.0   # сколько еды даёт один дом за начисление
const HOUSE_FOOD_INTERVAL := 8.0   # как часто начисляет, секунд

## ── ЕДА: ФЕРМА — ЦЕЛЕВЫЕ ЧИСЛА РАСЧЁТА ──
## MEAT_PER_SEC_TARGET — цель для сверки, а не действующий темп (его дают Worker.MEAT_PER_TRIP, удары, ходка)
const MEAT_PER_SEC_TARGET := 0.44      # еды в секунду с ОДНОГО фермера
const FARM_WORKERS_REFERENCE := 15     # столько фермеров держит расчёт (справочно: код не читает)
const FARM_SQUADS_SUPPORTED := 15      # столько отрядов они кормят с домами (справочно: код не читает)

## ── СОДЕРЖАНИЕ АРМИИ ЕДОЙ ──
## Едят головы: с бойца в секунду × множитель рода (рыцарь — вдвое)
const FOOD_UPKEEP_SOLDIER_PER_SEC := 0.005
const FOOD_UPKEEP_UNIT_MULT := {"warrior": 2.0}
## Отрядное число — для модели экономики (economy_model.upkeep_cost): средний отряд 45 голов
const FOOD_UPKEEP_SQUAD_PER_SEC  := FOOD_UPKEEP_SOLDIER_PER_SEC * 45.0
const FOOD_UPKEEP_WORKER_PER_SEC := 1.0 / 30.0  # с рабочего в секунду
const FOOD_UPKEEP_TICK := 1.0  # период списания, с
const FOOD_UPKEEP_FACTIONS := [Constants.FACTION_PLAYER]  # кто платит содержание
## Большая армия ест дороже (ТЗ 28.10.2026, блок 2; ручка perf_config.food_big_army): сверх стольких голов ставка растёт
const FOOD_UPKEEP_BIG_ARMY_HEADS := 900.0
## Прибавка к ставке за каждые FOOD_UPKEEP_BIG_ARMY_HEADS голов сверх порога (0.5: 1800 голов — ×1.5)
const FOOD_UPKEEP_BIG_ARMY_K := 0.5

## Множитель ставки содержания при heads живых бойцов (без рабочих); 1.0 до порога и при выключенной ручке
static func food_upkeep_mult(heads: float) -> float:
	if not _PerfU.food_big_army:
		return 1.0
	return 1.0 + FOOD_UPKEEP_BIG_ARMY_K * maxf(heads - FOOD_UPKEEP_BIG_ARMY_HEADS, 0.0) / FOOD_UPKEEP_BIG_ARMY_HEADS

## ── ЗАГОН — «КОЛОДЕЦ РЕСУРСОВ» ──
## Мест (овец) в загоне; на овцу — один рабочий; живая овца держит место, туша — нет
const SHEEP_PEN_CAPACITY  := 10
## Пауза до новой овцы — жребий в [MIN, MAX], с
const SHEEP_PEN_RESPAWN_MIN_SEC := 5.0
const SHEEP_PEN_RESPAWN_SEC := 5.0
## Рабочих на загон = числу мест (одно число, а не второй потолок)
const SHEEP_PEN_WORKERS := SHEEP_PEN_CAPACITY
## Загонов у игрока — не больше
const SHEEP_PEN_MAX_COUNT := 3
## Потолок стада игрока выводится из загонов; выпас у замка (CASTLE_GRAZE_*) — отдельный потолок
const SHEEP_PLAYER_MAX    := SHEEP_PEN_MAX_COUNT * SHEEP_PEN_CAPACITY
const CASTLE_GRAZE_LIMIT  := 5  # овец пасётся у замка
const CASTLE_GRAZE_RADIUS := 20.0  # радиус выпаса у замка, м
const STARVE_MORALE_PER_SEC := 1.5  # голод: потеря морали в секунду
const STARVE_MORALE_FLOOR := 0.40  # голод: ниже этой доли мораль не падает

## Какие записи BUILDINGS — дома (три картинки, один баланс)
const HOUSE_IDS := ["house", "house2", "house3"]

static func is_house(building_id: String) -> bool:
	return building_id in HOUSE_IDS

## ── ЛИМИТ НАСЕЛЕНИЯ: РАБОЧИЕ ──
const POP_LIMIT_ENABLED   := true
const POP_BASE_WORKERS    := 10     # рабочих без крепости и домов (стартовая бригада)
const CASTLE_WORKER_SLOTS := 10    # +рабочих за каждую крепость
const HOUSE_WORKER_SLOTS  := 3     # +рабочих за каждый дом

## ── ЛИМИТ АРМИИ — В БОЙЦАХ, НЕ В ОТРЯДАХ ──
## Рабочие в счёт не входят (свой лимит POP_*)
const ARMY_BASE_UNITS   := 120   # бойцов без крепости и домов
const ARMY_CASTLE_UNITS := 120   # +бойцов за каждую крепость
const ARMY_HOUSE_UNITS  := 90    # +бойцов за каждый дом
const ARMY_HARD_CAP     := 2500  # потолок, выше которого не поднимает ничто

## Сколько РАБОЧИХ помещается при таком числе домов и крепостей
static func pop_worker_cap(houses: int, castles: int = 0) -> int:
	return POP_BASE_WORKERS + HOUSE_WORKER_SLOTS * maxi(houses, 0) \
		+ CASTLE_WORKER_SLOTS * maxi(castles, 0)

## Сколько БОЙЦОВ помещается при таком числе домов и крепостей
static func pop_army_cap(houses: int, castles: int = 0) -> int:
	return mini(ARMY_BASE_UNITS + ARMY_HOUSE_UNITS * maxi(houses, 0)
		+ ARMY_CASTLE_UNITS * maxi(castles, 0), ARMY_HARD_CAP)

## Сколько домов нужно до полного капа (показывает интерфейс)
static func houses_for_full_army(castles: int = 1) -> int:
	var need: int = ARMY_HARD_CAP - ARMY_BASE_UNITS - ARMY_CASTLE_UNITS * maxi(castles, 0)
	if need <= 0:
		return 0
	return int(ceil(float(need) / float(ARMY_HOUSE_UNITS)))

## ── БАШНЯ (TOWER) ──
const TOWER_VISION           := 35.0  # обзор башни, м
## Укрепление башни — ступени списком (длина = число ступеней): hp_add — доля БАЗОВОГО max_hp,
## dmg_mult — множитель входящего урона (ступени не складываются, берётся текущая)
const TOWER_FORT_LEVELS := [
	{"name": "Каменная облицовка", "cost_wood": 220.0, "cost_stone": 320.0,
		"time": 20.0, "hp_add": 1.0 / 3.0, "dmg_mult": 0.90},
	{"name": "Крепостные зубцы",   "cost_wood": 220.0, "cost_stone": 320.0,
		"time": 20.0, "hp_add": 1.0 / 3.0, "dmg_mult": 0.80},
	{"name": "Окованные ворота",   "cost_wood": 220.0, "cost_stone": 320.0,
		"time": 20.0, "hp_add": 1.0 / 3.0, "dmg_mult": 0.70},
]
## Оттенок рисунка башни по ступени укрепления (0 — без укрепления)
const TOWER_FORT_TINT := [Color(1, 1, 1), Color(0.90, 0.90, 0.93), Color(0.82, 0.83, 0.88),
	Color(0.74, 0.75, 0.82)]
## Сколько отрядов помещается в башню и каких родов войск
const TOWER_GARRISON_LIMIT   := 1
const TOWER_GARRISON_TYPES   := ["archer"]
## Сколько лучников видно на площадке (запасное число; действует ROOF_VISIBLE)
const TOWER_VISIBLE_ARCHERS  := 10
## Период перевыбора цели гарнизоном, с
const TOWER_RETARGET_SEC     := 0.25

## ── ГАРНИЗОН НА КРЫШЕ (башня, бараки, крепость) ──
## Бафф высоты любому укрытому стрелку: дальность и урон
const GARRISON_RANGE_MULT    := 1.30
const GARRISON_DAMAGE_MULT   := 1.30
## Доля урона стрелы, достающаяся защитнику на крыше (стены — полный урон параллельно)
const GARRISON_COVER_FRAC    := 0.5
## Сколько стрелковых отрядов помещается на крышу и сколько стрелков видно
const ROOF_SQUADS := {"tower": 1, "barracks": 1, "castle": 2}
## Сколько стрелков видно на крыше (остальные в резерве, сменяют павших)
const ROOF_VISIBLE := {"tower": 10, "barracks": 15, "castle": 40}
## На какой доле высоты рисунка стоят ноги
const ROOF_FOOT_FRAC := {"tower": 0.52, "barracks": 0.44, "castle": 0.50}
## Фланговые полубашни крепости выше настила (ступеньки): ноги на 0.60 рисунка
const CASTLE_FLANK_FOOT_FRAC := 0.60
## Крепостей на игрока — не больше трёх, каждая следующая дороже в CASTLE_COST_MULT раз
const CASTLE_MAX_COUNT := 3
const CASTLE_COST_MULT := 4.0

## ── УДОРОЖАНИЕ ЗДАНИЙ ──
## Производственные — линейно ×1, ×2, ×3 по счёту; башни — ступенька после TOWER_FREE_COUNT;
## крепость — степень CASTLE_COST_MULT; загон и дома — свои законы ниже
const PROGRESSIVE_BUILDINGS := ["barracks", "archery"]

## Рынок: отдать N ресурса A → N · value[A] / value[B] · (1 − fee) ресурса B (Market.gd);
## ключи — Constants.RESOURCE_* (0 дерево, 1 золото, 2 камень, 3 еда); steps — сетка кнопок «−/+»
## и колеса в окне обмена, lot_min/lot_max — пределы количества (ТЗ 29.10.2026)
const MARKET := {
	"value": {0: 1.0, 1: 2.0, 2: 1.3, 3: 0.9},
	"fee": 0.20,
	"steps": [100, 200, 300, 500, 1000, 2000, 5000, 10000, 20000],
	"lot_min": 100,
	"lot_max": 20000,
}
## Загон: каждый следующий +50 % базовой цены
const SHEEP_PEN_COST_STEP := 0.50
## Башни: сколько стоят по базовой цене и на сколько дорожает каждая сверх
const TOWER_FREE_COUNT := 10
const TOWER_COST_STEP  := 0.75    # 11-я = ×1.75, 12-я = ×2.5, 13-я = ×3.25 …
const TOWER_COST_MAX   := 8.0     # потолок множителя: цена не уходит в бесконечность
## Дома: первые HOUSE_FREE_COUNT по базовой цене, дальше × HOUSE_COST_GROWTH за каждый
## (считаются все три картинки и заложенные площадки)
## ⚠ Менять только по явному ТЗ владельца (разворотов: 1)
const HOUSE_FREE_COUNT  := 9
const HOUSE_COST_GROWTH := 1.12
## Роскошь: рост от ЛИМИТА В ОТРЯДАХ после дома — × GROWTH за каждый отряд сверх LUXURY_FROM,
## сверх STEEP_FROM — ещё × STEEP
const HOUSE_LUXURY_FROM := 35.0
const HOUSE_LUXURY_GROWTH := 2.0
const HOUSE_LUXURY_STEEP_FROM := 40.0
const HOUSE_LUXURY_STEEP := 4.0

## Добавка роскоши к цене следующего дома; 1.0 — лимит после дома не выше HOUSE_LUXURY_FROM
static func house_luxury_mult(existing: int, castles: int) -> float:
	var per: float = float(maxi(squad_size("spearman"), 1))
	var after: float = float(pop_army_cap(existing + 1, castles)) / per
	var over: float = after - HOUSE_LUXURY_FROM
	if over <= 0.0:
		return 1.0
	var steep: float = maxf(after - HOUSE_LUXURY_STEEP_FROM, 0.0)
	return pow(HOUSE_LUXURY_GROWTH, over - steep) * pow(HOUSE_LUXURY_GROWTH * HOUSE_LUXURY_STEEP, steep)

## Множитель цены следующего здания типа при existing стоящих (одна функция на все законы)
static func building_cost_mult(building_id: String, existing: int) -> float:
	var n: int = maxi(existing, 0)
	if n <= 0:
		return 1.0
	if building_id == "castle":
		return pow(CASTLE_COST_MULT, float(n))
	if building_id == "tower":
		var over: int = n - TOWER_FREE_COUNT + 1
		if over <= 0:
			return 1.0
		return minf(1.0 + TOWER_COST_STEP * float(over), TOWER_COST_MAX)
	if building_id in PROGRESSIVE_BUILDINGS:
		return float(n + 1)
	if building_id == "sheep_pen":
		return 1.0 + SHEEP_PEN_COST_STEP * float(n)
	if is_house(building_id):
		var over_h: int = n - HOUSE_FREE_COUNT + 1
		if over_h <= 0:
			return 1.0
		return pow(HOUSE_COST_GROWTH, float(over_h))
	return 1.0

## Цена постройки с учётом стоящих; castles >= 0 — у дома добавка роскоши, −1 — прежний закон
static func building_cost_scaled(building_id: String, existing: int, castles: int = -1) -> Dictionary:
	var cost: Dictionary = building_cost(building_id)
	var k: float = building_cost_mult(building_id, existing)
	if castles >= 0 and is_house(building_id):
		k *= house_luxury_mult(existing, castles)
	if k == 1.0:
		return cost
	for key in cost.keys():
		cost[key] = float(cost[key]) * k
	return cost

## ── РАЗМЕР ОТРЯДА — МОДЕЛЕЙ В ОДНОМ ОТРЯДЕ ──
const SQUAD_SIZE_SPEARMEN  := 60   # копейщики
const SQUAD_SIZE_ARCHERS   := 30   # лучники
const SQUAD_SIZE_SWORDSMEN := 30   # мечники (рыцари)
const SQUAD_SIZE_MONKS     := 1  # монахи

## Числа большого гоблина (справочно; справочно: код не читает)
const BIG_GOBLIN_HORDE_SQUAD := 100   # = goblin_config.SQUAD_SIZE.goblin_spearman
const BIG_GOBLIN_HP_SQUADS := 0.5     # сколько отрядов орды весит туша по запасу жизни

## ── МОНАХ ──
const MONK_LIMIT           := 3  # монахов на игрока
## Лечение: радиус ауры, точка стойки и такты
const MONK_HEAL_RADIUS     := 20.0   # радиус ауры лечения, м
## Прежняя дальность каста в упор, м (справочно: код не читает — каст идёт из любой точки ауры)
const MONK_CAST_RANGE      := 3.0
const MONK_STAND_FRAC      := 0.7    # где встать: доля радиуса ауры от центра отряда
const MONK_MOVE_SLACK      := 3.0    # новый приказ подхода — только если точка ушла дальше
const MONK_HEAL_LEASH      := 14.0  # удержание начатого пациента, м (не меньше дальности каста)
const MONK_STEP_SEC        := 0.6  # пауза между приказами идти к раненому, с
const MONK_HEAL_TICK       := 0.5  # такт лечения, с
## Одиночное лечение: секунд на полный запас одного бойца
const MONK_HEAL_SEC_PER_MAN := 10.0
## Массовое лечение: не быстрее этого числа секунд с нуля до полного на каждого
const MONK_MASS_FULL_SEC := 24.0
## Дистанция между монахами, м
const MONK_SPACING := 5.0
## Воскрешение (ветка кузницы monk_3d)
const MONK_RES_SEC := 5.0            # канал воскрешения, с
const MONK_RES_COOLDOWN := 5.0       # откат между каналами, с
const MONK_RES_COOLDOWN_4D := 4.0  # откат с улучшением 4d, с
const MONK_RES_COOLDOWN_5D := 2.0  # откат с улучшением 5d, с
## Радиус поиска павших, м (шире радиуса лечения)
const MONK_RES_SEARCH_RADIUS := 30.0
const MONK_RES_HP := 1.0  # запас жизни воскрешённого, HP
const MONK_RES_PARALLEL_MULT := 0.7  # множитель времени канала при параллельном канале
## Опыт монаха — за лечение, а не за убийства
const MONK_XP_HP_PER_KILL := 150.0  # вылеченных HP за один «зачёт убийства»
const MONK_RES_XP_KILLS := 3  # зачётов за одно воскрешение
## Ауры поддержки (награды ветеранства монаха)
const MONK_AURA_BASE_R := 4.0  # базовый радиус ауры, м (+ «Аура радиуса»)
const MONK_AURA_TICK := 1.0  # раздача раз в, с
const MONK_AURA_HOLD_MS := 1700  # срок действия выданных чисел, мс (больше такта скана)
const MONK_AOE_RATE        := 0.5  # доля запаса за такт массового лечения (справочно: код не читает)
## Автономный монах: скан раз в SCAN_SEC, выбирает самый побитый отряд; нет раненых — к ближайшему
## своему на FRONT_DIST; под ударом — отход на RETREAT_DIST к своим
const MONK_SCAN_SEC        := 1.2  # период скана, с
const MONK_AURA_R          := 20.0  # радиус ауры по умолчанию, м (справочно: код не читает, см. MONK_HEAL_RADIUS)
const MONK_FRONT_DIST      := 10.0  # м до фронта своего отряда (справочно: код не читает)
const MONK_RETREAT_DIST    := 10.0  # м отхода под ударом
## Сколько квадов VFX лечения на одного монаха (массовый каст: на самых раненых)
const MONK_VFX_MAX         := 8

## Жёсткий потолок размера одного заказа найма (Building.MAX_SQUAD_SIZE)
const SQUAD_SIZE_HARD_CAP := 100

## ── ВЕТЕРАНСТВО: ШАБЛОНЫ НАГРАД ──
## Монах: ауры — три карточки на ступень, семь ступеней
const _VET_MONK_TEMPLATE := [
	[
		{"id": "aura_armor", "name": "Аура морали", "icon": "icon_shield.png", "bonus_aura_armor": 1.0},
		{"id": "aura_attack", "name": "Боевой клич", "icon": "icon_sword.png", "bonus_aura_attack": 1.0},
		{"id": "aura_rate", "name": "Аура скорострельности", "icon": "icon_might.png", "bonus_aura_rate": 0.08},
	],
	[
		{"id": "aura_attack", "name": "Боевой клич", "icon": "icon_sword.png", "bonus_aura_attack": 1.0},
		{"id": "aura_rate", "name": "Аура скорострельности", "icon": "icon_might.png", "bonus_aura_rate": 0.08},
		{"id": "aura_radius", "name": "Аура радиуса", "icon": "icon_trader.png", "bonus_aura_radius": 1.0},
	],
	[
		{"id": "aura_armor", "name": "Аура морали", "icon": "icon_shield.png", "bonus_aura_armor": 1.0},
		{"id": "aura_radius", "name": "Аура радиуса", "icon": "icon_trader.png", "bonus_aura_radius": 1.0},
		{"id": "aura_rate", "name": "Аура скорострельности", "icon": "icon_might.png", "bonus_aura_rate": 0.08},
	],
	[
		{"id": "aura_armor", "name": "Аура стойкости", "icon": "icon_shield.png", "bonus_aura_armor": 2.0},
		{"id": "aura_attack", "name": "Громовой клич", "icon": "icon_sword.png", "bonus_aura_attack": 2.0},
		{"id": "aura_rate", "name": "Аура беглого огня", "icon": "icon_might.png", "bonus_aura_rate": 0.12},
	],
	[
		{"id": "aura_attack", "name": "Громовой клич", "icon": "icon_sword.png", "bonus_aura_attack": 2.0},
		{"id": "aura_radius", "name": "Широкая аура", "icon": "icon_trader.png", "bonus_aura_radius": 1.5},
		{"id": "aura_rate", "name": "Аура беглого огня", "icon": "icon_might.png", "bonus_aura_rate": 0.12},
	],
	[
		{"id": "aura_armor", "name": "Аура стойкости", "icon": "icon_shield.png", "bonus_aura_armor": 2.0},
		{"id": "aura_radius", "name": "Широкая аура", "icon": "icon_trader.png", "bonus_aura_radius": 1.5},
		{"id": "aura_attack", "name": "Громовой клич", "icon": "icon_sword.png", "bonus_aura_attack": 2.0},
	],
	[
		{"id": "aura_armor", "name": "Святой оплот", "icon": "icon_shield.png", "bonus_aura_armor": 2.0, "bonus_aura_attack": 2.0},
		{"id": "aura_rate", "name": "Ливень стрел", "icon": "icon_might.png", "bonus_aura_rate": 0.15, "bonus_aura_radius": 1.0},
		{"id": "aura_radius", "name": "Свет над войском", "icon": "icon_trader.png", "bonus_aura_radius": 2.0, "bonus_aura_armor": 1.0},
	],
]

## Бойцы: три карточки на ступень из тройки урон/броня/запас; 1-3 лычки, 4-6 флаги, 7 — легендарные перки
const _VET_BONUS_TEMPLATE := [
	# ── ЭТАП 1 — ЛЫЧКИ (ступени 1-3) ──
	# ── ЛЫЧКА I ──
	[
		{"id": "attack", "name": "Заточка", "icon": "icon_sword.png",
			"bonus_attack": 3.0, "bonus_armor": -1.0, "bonus_defense": 0.0,
			"bonus_health": 8.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "Щит", "icon": "icon_shield.png",
			"bonus_attack": -1.0, "bonus_armor": 3.0, "bonus_defense": 0.0,
			"bonus_health": 8.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "Выносливость", "icon": "icon_heart.png",
			"bonus_attack": -1.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
			"bonus_health": 21.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── ЛЫЧКА II ──
	[
		{"id": "attack", "name": "Крепкая рука", "icon": "icon_sword.png",
			"bonus_attack": 3.0, "bonus_armor": -1.0, "bonus_defense": 0.0,
			"bonus_health": 8.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "Наручи", "icon": "icon_shield.png",
			"bonus_attack": -1.0, "bonus_armor": 3.0, "bonus_defense": 0.0,
			"bonus_health": 8.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "Второе дыхание", "icon": "icon_heart.png",
			"bonus_attack": -1.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
			"bonus_health": 21.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── ЛЫЧКА III ──
	[
		{"id": "attack", "name": "Отточенный удар", "icon": "icon_sword.png",
			"bonus_attack": 3.0, "bonus_armor": -1.0, "bonus_defense": 0.0,
			"bonus_health": 8.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "Кольчуга", "icon": "icon_shield.png",
			"bonus_attack": -1.0, "bonus_armor": 3.0, "bonus_defense": 0.0,
			"bonus_health": 8.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "Закалка", "icon": "icon_heart.png",
			"bonus_attack": -1.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
			"bonus_health": 21.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── ЭТАП 2 — ФЛАГИ (ступени 4-6) ──
	# ── ФЛАГ I ──
	[
		{"id": "attack", "name": "Клинок ветерана", "icon": "icon_sword.png",
			"bonus_attack": 4.0, "bonus_armor": -2.0, "bonus_defense": 0.0,
			"bonus_health": 10.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "Латы", "icon": "icon_shield.png",
			"bonus_attack": -2.0, "bonus_armor": 4.0, "bonus_defense": 0.0,
			"bonus_health": 10.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "Стойкость", "icon": "icon_heart.png",
			"bonus_attack": -2.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
			"bonus_health": 30.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── ФЛАГ II ──
	[
		{"id": "attack", "name": "Сокрушающий удар", "icon": "icon_sword.png",
			"bonus_attack": 4.0, "bonus_armor": -2.0, "bonus_defense": 0.0,
			"bonus_health": 10.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "Пластины", "icon": "icon_shield.png",
			"bonus_attack": -2.0, "bonus_armor": 4.0, "bonus_defense": 0.0,
			"bonus_health": 10.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "Железное здоровье", "icon": "icon_heart.png",
			"bonus_attack": -2.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
			"bonus_health": 30.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── ФЛАГ III ──
	[
		{"id": "attack", "name": "Разящий", "icon": "icon_sword.png",
			"bonus_attack": 4.0, "bonus_armor": -2.0, "bonus_defense": 0.0,
			"bonus_health": 10.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "Полный доспех", "icon": "icon_shield.png",
			"bonus_attack": -2.0, "bonus_armor": 4.0, "bonus_defense": 0.0,
			"bonus_health": 10.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "Несгибаемые", "icon": "icon_heart.png",
			"bonus_attack": -2.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
			"bonus_health": 30.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── ЭТАП 3 — ЛЕГЕНДА (ступень 7): пять перков ──
	[
		{"id": "legend_steadfast", "name": "Непреклонные", "icon": "icon_hand.png",
			"bonus_attack": 0.0, "bonus_armor": 3.0, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 1.0,
			"bonus_morale": 30.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "legend_pierce", "name": "Пробитие брони", "icon": "icon_sword.png",
			"bonus_attack": 4.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.20, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 5.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "legend_shieldwall", "name": "Стена щитов", "icon": "icon_shield.png",
			"bonus_attack": 0.0, "bonus_armor": 4.0, "bonus_defense": 0.0,
			"bonus_health": 20.0, "bonus_speed": -0.10, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "legend_juggernaut", "name": "Таран", "icon": "icon_might.png",
			"bonus_attack": 3.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 20.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 2.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "legend_bloodthirst", "name": "Кровь за кровь", "icon": "icon_dual_sword.png",
			"bonus_attack": 4.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 15.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 5.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
]

## ── АВТОМАТИЧЕСКОЕ ВЕТЕРАНСТВО ──
## Прибавки по ступеням: [белые 1-3, красные 4-6, золотые 7-9] — упор на мораль и напор,
## атака и запас растут умеренно (ТЗ 30.10.2026). Ключа bonus_speed быть не должно
const VET_AUTO_STEPS := {
	# мечник: таран рубки — напор и мораль, броня
	"warrior": [
		{"bonus_health": 8.0, "bonus_armor": 0.4, "bonus_attack": 0.8, "bonus_morale": 3.0, "bonus_push": 0.10, "bonus_rage_cd": 0.02},
		{"bonus_health": 10.0, "bonus_armor": 0.5, "bonus_attack": 1.0, "bonus_morale": 4.0, "bonus_push": 0.15, "bonus_rage_cd": 0.02},
		{"bonus_health": 12.0, "bonus_armor": 0.6, "bonus_attack": 1.2, "bonus_morale": 5.0, "bonus_push": 0.20, "bonus_rage_cd": 0.03},
	],
	# копейщик: стена — напор и защита
	"spearman": [
		{"bonus_health": 6.0, "bonus_defense": 0.4, "bonus_attack": 0.6, "bonus_morale": 3.0, "bonus_push": 0.15},
		{"bonus_health": 8.0, "bonus_defense": 0.6, "bonus_attack": 0.8, "bonus_morale": 4.0, "bonus_push": 0.25, "bonus_cooldown": 0.03},
		{"bonus_health": 10.0, "bonus_defense": 0.8, "bonus_attack": 1.0, "bonus_morale": 5.0, "bonus_push": 0.35, "bonus_cooldown": 0.04},
	],
	# лучник: темп и выдержка; дальность осторожно — у неё потолок attack_range_cap
	"archer": [
		{"bonus_health": 4.0, "bonus_attack": 0.6, "bonus_cooldown": 0.06, "bonus_morale": 4.0},
		{"bonus_health": 5.0, "bonus_attack": 0.8, "bonus_cooldown": 0.08, "bonus_range": 0.3, "bonus_morale": 5.0},
		{"bonus_health": 6.0, "bonus_attack": 1.0, "bonus_cooldown": 0.10, "bonus_range": 0.4, "bonus_morale": 6.0},
	],
	# монах: растёт лечением
	"monk": [
		{"bonus_health": 6.0, "bonus_heal_rate": 0.03, "bonus_heal_amount": 0.03, "bonus_morale": 3.0},
		{"bonus_health": 7.0, "bonus_heal_rate": 0.04, "bonus_heal_amount": 0.03, "bonus_morale": 4.0},
		{"bonus_health": 8.0, "bonus_heal_rate": 0.05, "bonus_heal_amount": 0.04, "bonus_morale": 5.0},
	],
}

## Лестница рода, которого нет в таблице (гоблины, конница, туши)
const VET_AUTO_DEFAULT := [
	{"bonus_health": 6.0, "bonus_armor": 0.3, "bonus_attack": 0.6, "bonus_morale": 3.0, "bonus_push": 0.08},
	{"bonus_health": 7.0, "bonus_armor": 0.35, "bonus_attack": 0.7, "bonus_morale": 4.0, "bonus_push": 0.12},
	{"bonus_health": 8.0, "bonus_armor": 0.4, "bonus_attack": 0.8, "bonus_morale": 5.0, "bonus_push": 0.15},
]

## Ступеней одного цвета лычек (белые / красные / золотые)
const VET_TIER_STEPS := 3

## Прибавки ступени lvl (1..9; легенда и престиж — как золотая) для этого рода войск
static func vet_auto_step(unit_type: String, lvl: int = 1) -> Dictionary:
	var d: Variant = VET_AUTO_STEPS.get(unit_type)
	var lst: Array = VET_AUTO_DEFAULT if d == null else d
	var t: int = clampi((maxi(lvl, 1) - 1) / VET_TIER_STEPS, 0, lst.size() - 1)
	return (lst[t] as Dictionary).duplicate()

## Стойкость к панике по рангу: жребий паники × (1 − доля); 0 — новобранцы, 10 — легенда
## Отход легенды (ручка legend_retreat): доля живых от штата и откат повтора, с
const LEGEND_RETREAT_FRAC := 0.5
const LEGEND_RETREAT_CD_SEC := 90.0

const VET_PANIC_RESIST := [0.0, 0.05, 0.10, 0.15, 0.22, 0.29, 0.36, 0.45, 0.54, 0.63, 0.75]

static func vet_panic_resist(lvl: int) -> float:
	return float(VET_PANIC_RESIST[clampi(lvl, 0, VET_PANIC_RESIST.size() - 1)])

## Легендарный перк (ступень LEGEND_TIER) — один на род, выдаётся сам
const VET_AUTO_LEGEND := {
	"warrior":  "legend_bloodthirst",   # мечник лечится убийством: он в гуще
	"spearman": "legend_steadfast",     # копейщик держит линию
	"archer":   "legend_pierce",        # лучник пробивает броню
	"monk":     "legend_shieldwall",    # монах усиливает тех, кого лечит
}

static func vet_auto_legend(unit_type: String) -> String:
	return String(VET_AUTO_LEGEND.get(unit_type, ""))

const LEGEND_PERK_IDS := [
	"legend_steadfast",
	"legend_pierce",
	"legend_shieldwall",
	"legend_juggernaut",
	"legend_bloodthirst",
]

## Бит перка по id (0 — нет в реестре)
static var _perk_bits: Dictionary = {}

static func perk_bit(id: String) -> int:
	if _perk_bits.is_empty():
		for i in range(LEGEND_PERK_IDS.size()):
			_perk_bits[String(LEGEND_PERK_IDS[i])] = 1 << i
	return int(_perk_bits.get(id, 0))

## Слово перков по списку выбранных наград (незнакомые id пропускаются)
static func perk_mask_of(chosen: Array) -> int:
	var m := 0
	for c in chosen:
		m |= perk_bit(String(c))
	return m

## ── КРИВАЯ ОПЫТА (ТЗ 30.10.2026, знамёна) ──
## Интервал k-й ступени = первый интервал рода × П(1 + рост); ступени 1-9 и легенда (10-я)
const VET_XP_GROWTH := [0.0, 0.05, 0.07, 0.10, 0.15, 0.20, 0.24, 0.27, 0.30, 0.30]

## Пороги убийств по первому интервалу (кратны 5)
static func vet_curve(first: float) -> Array:
	var out: Array = []
	var acc := 0.0
	var k := 1.0
	for g in VET_XP_GROWTH:
		k *= 1.0 + float(g)
		acc += first * k
		out.append(int(round(acc / 5.0)) * 5)
	return out

## Пороги убийств и наградные таблицы по роду войск (9 ступеней + легенда)
static var VET_CONFIG: Dictionary = {
	"spearman": {"thresholds": vet_curve(50.0), "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"warrior":  {"thresholds": vet_curve(130.0), "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"archer":   {"thresholds": vet_curve(130.0), "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	# монах: ауры, опыт — за лечение
	"monk":     {"thresholds": vet_curve(50.0), "bonuses": _VET_MONK_TEMPLATE.duplicate(true)},
	# орда: своя лестница порогов
	"goblin_spearman": {"thresholds": vet_curve(130.0), "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"gnoll":           {"thresholds": vet_curve(80.0), "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"goblin_rider":    {"thresholds": vet_curve(180.0), "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
}

## ── ЗНАМЁНА ВЕТЕРАНСТВА ──
## Формы полотнища
const BANNER_PENNANT  := 0    ## вымпел: сужается к острию
const BANNER_GUIDON   := 1    ## «ласточкин хвост»: клин вырезан из свободного края
const BANNER_STANDARD := 2    ## прямоугольный штандарт с бахромой и гербом

const BANNER_CHEVRON := Color(0.97, 0.97, 0.95)  # цвет лычек на полотнище
const BANNER_TIP_COLOR := Color(0.97, 0.97, 0.95)  # белый конец вымпела
const BANNER_GOLD := Color(0.93, 0.76, 0.24)  # золото значка легенды в панели

const VET_BADGE_OUTLINE := Color(0.08, 0.08, 0.10, 0.9)  # обводка значка ранга в панели

## Красный штандарт элиты (BannerArt.vexillum_texture) у отряда с индивидуальным званием
## (GameManager.squad_elite); true — и у дошедшего до высшего ранга
const ELITE_BANNER_AT_TOP_RANK := true  # справочно: код не читает

## Ступени знамени (ТЗ 31.10.2026): вымпел цвета стороны (игрок — синий, красный ИИ —
## красный, орда — зелёные язычки), лычки 1-3 — белые «Опытные», красные «Ветераны»,
## жёлто-оранжевые «Элита»; 10 — «Легендарные»: синее поле в фиолетовой рамке,
## оранжевые лычки 1 + престиж (жёлтого флага больше нет)
## ⚠ Менять только по явному ТЗ владельца (разворотов: 4)
const BANNER_BLUE := Color(0.16, 0.34, 0.70)  # базовое полотнище отряда игрока
const CHEV_WHITE := Color(0.97, 0.97, 0.95)
const CHEV_RED := Color(0.80, 0.12, 0.14)
const CHEV_GOLD := Color(1.00, 0.84, 0.16)  # справочно: прежняя золотая лычка (до 31.10)
const CHEV_ORANGE := Color(1.00, 0.56, 0.08)  # жёлто-оранжевая лычка старших ступеней и легенды
## Фиолетовая рамка легендарного вымпела
const BANNER_PURPLE := Color(0.46, 0.20, 0.66)
## Полотнище красного ИИ (вместо синего у тех же ступеней)
const BANNER_RED := Color(0.66, 0.09, 0.11)
## Золото легендарного флага и его кайма
const LEGEND_GOLD := Color(0.96, 0.79, 0.20)
const LEGEND_GOLD_DARK := Color(0.62, 0.42, 0.06)
const VET_BANNER_TIERS := [
	{"rank": "опытных", "title": "Опытные", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE, "chevrons": 1, "chevron_col": CHEV_WHITE},
	{"rank": "опытных", "title": "Опытные", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE, "chevrons": 2, "chevron_col": CHEV_WHITE},
	{"rank": "опытных", "title": "Опытные", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE, "chevrons": 3, "chevron_col": CHEV_WHITE},
	{"rank": "ветеранов", "title": "Ветераны", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE, "chevrons": 1, "chevron_col": CHEV_RED},
	{"rank": "ветеранов", "title": "Ветераны", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE, "chevrons": 2, "chevron_col": CHEV_RED},
	{"rank": "ветеранов", "title": "Ветераны", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE, "chevrons": 3, "chevron_col": CHEV_RED},
	{"rank": "элитных", "title": "Элита", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE, "chevrons": 1, "chevron_col": CHEV_ORANGE},
	{"rank": "элитных", "title": "Элита", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE, "chevrons": 2, "chevron_col": CHEV_ORANGE},
	{"rank": "элитных", "title": "Элита", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE, "chevrons": 3, "chevron_col": CHEV_ORANGE},
	# легенда — синее поле в фиолетовой рамке; лычки 1 + престиж — BannerArt.legend_texture
	{"rank": "легендарных", "title": "Легендарные", "shape": BANNER_PENNANT, "cloth": BANNER_BLUE,
		"edge": BANNER_PURPLE, "chevrons": 1, "chevron_col": CHEV_ORANGE, "legend": true},
]


## ── ПРЕСТИЖ ЛЕГЕНДЫ (лычки сверх легенды) ──
## k-я ступень стоит последний интервал шкалы × GAP[k-1]; прибавки рода (и уровень штандарта у элиты) —
## за первые BONUS_MAX, остальные — знак на знамени: красный хвост 1-3 → синий 1-3 (BannerArt.legend_tail_spec)
const LEGEND_EXTRA_MAX := 3  # ступеней престижа: 1-3 красные лычки на золоте (ТЗ 30.10.2026)
const LEGEND_EXTRA_GAP := [1.3, 1.4, 1.5]  # множители последнего интервала по ступеням
const LEGEND_EXTRA_BONUS_MAX := 3  # за сколько первых — прибавки

## Порог убийств k-й ступени престижа (k = 1..LEGEND_EXTRA_MAX); −1 — нет
static func legend_extra_threshold(unit_type: String, k: int) -> int:
	if k < 1 or k > LEGEND_EXTRA_MAX:
		return -1
	var th: Array = _vet_thresholds(unit_type)
	if th.size() < 2:
		return -1
	var last: int = int(th[th.size() - 1])
	var gap: float = float(last - int(th[th.size() - 2]))
	var need: float = float(last)
	for i in range(k):
		need += gap * float(LEGEND_EXTRA_GAP[i])
	return int(round(need))

## Сколько ступеней престижа даёт счёт kills (0..LEGEND_EXTRA_MAX)
static func legend_extra_for_kills(unit_type: String, kills: int) -> int:
	var n := 0
	for k in range(1, LEGEND_EXTRA_MAX + 1):
		var t: int = legend_extra_threshold(unit_type, k)
		if t < 0 or kills < t:
			break
		n = k
	return n

## Звание отряда одним словом: «Новобранцы» / «Опытные» / «Ветераны» / «Легендарные»
static func rank_title(lvl: int) -> String:
	if lvl <= 0:
		return "Новобранцы"
	return String(veteran_banner_tier(lvl).get("title", "Опытные"))

static func veteran_banner_tier(lvl: int) -> Dictionary:
	if lvl <= 0 or VET_BANNER_TIERS.is_empty():
		return {}
	var idx: int = clampi(lvl, 1, VET_BANNER_TIERS.size()) - 1
	var d: Dictionary = (VET_BANNER_TIERS[idx] as Dictionary).duplicate()
	d["key"] = idx + 1
	return d

## Полное название отряда: «Отряд ветеранов копейщиков»
static func veteran_rank_name(unit_id: String, lvl: int) -> String:
	var tier: Dictionary = veteran_banner_tier(lvl)
	if tier.is_empty():
		return ""
	var noun: String = String(stat_str(unit_id, "name_genitive_plural", ""))
	if noun == "":
		return "Отряд %s" % String(tier.get("rank", ""))
	return "Отряд %s %s" % [String(tier.get("rank", "")), noun]

## Значок ранга в панели
static func veteran_badge_text(lvl: int) -> String:
	var t: Dictionary = veteran_banner_tier(lvl)
	if t.is_empty():
		return ""
	if bool(t.get("legend", false)):
		return "✪"
	return "❯".repeat(maxi(int(t.get("chevrons", 1)), 1))

static func veteran_badge_color(lvl: int) -> Color:
	var t: Dictionary = veteran_banner_tier(lvl)
	if t.is_empty():
		return Color.WHITE
	if bool(t.get("legend", false)):
		return BANNER_GOLD
	return t.get("chevron_col", Color.WHITE) as Color

## Строковое поле характеристик с дефолтом (числовой брат — stat() выше)
static func stat_str(unit_id: String, key: String, default: String = "") -> String:
	var d: Dictionary = STATS.get(unit_id, {})
	return String(d.get(key, default))

## Множитель опыта поверх порогов VET_CONFIG по роду (округление до целого);
## лычки сверх легенды дорожают вместе с порогами
const VET_XP_MULT := {"monk": 1.2}
static var _vet_th_cache: Dictionary = {}

static func _vet_thresholds(unit_type: String) -> Array:
	var raw: Array = (VET_CONFIG.get(unit_type, {}) as Dictionary).get("thresholds", [])
	var k: Variant = VET_XP_MULT.get(unit_type)
	if k == null:
		return raw
	var c: Variant = _vet_th_cache.get(unit_type)
	if c != null:
		return c
	var out: Array = []
	for t in raw:
		out.append(int(round(float(t) * float(k))))
	_vet_th_cache[unit_type] = out
	return out

static func _vet_bonuses(unit_type: String) -> Array:
	return (VET_CONFIG.get(unit_type, {}) as Dictionary).get("bonuses", [])

## Максимальный уровень ветеранства (= число порогов) у данного типа юнита
static func max_veteran_level(unit_type: String) -> int:
	return _vet_thresholds(unit_type).size()

## Сколько убийств нужно, чтобы получить уровень level (1..max)
static func veteran_threshold(unit_type: String, level: int) -> int:
	var th: Array = _vet_thresholds(unit_type)
	if level < 1 or level > th.size():
		return 0
	return int(th[level - 1])

## Какой уровень заслужен при данном числе убийств (0 — ещё не ветеран)
static func veteran_level_for_kills(unit_type: String, kills: int) -> int:
	var th: Array = _vet_thresholds(unit_type)
	var lvl := 0
	for i in range(mini(th.size(), max_veteran_level(unit_type))):
		if kills >= int(th[i]):
			lvl = i + 1
	return lvl

## Короткие имена характеристик по ключу модификатора
const _MOD_TO_STAT := {
	"bonus_attack": "attack", "bonus_armor": "armor", "bonus_defense": "defense",
	"bonus_health": "health", "bonus_speed": "speed", "bonus_range": "range",
	"bonus_cooldown": "cooldown", "bonus_spread": "spread", "bonus_push": "push",
	"bonus_morale": "morale", "bonus_carry": "carry", "bonus_gather": "gather",
	"bonus_train": "train",
	"bonus_aura_armor": "aura_armor", "bonus_aura_attack": "aura_attack",
	"bonus_aura_rate": "aura_rate", "bonus_aura_radius": "aura_radius",
}

## Короткое имя характеристики по ключу модификатора ("bonus_attack" → "attack")
static func modifier_stat_name(key: String) -> String:
	return String(_MOD_TO_STAT.get(key, key))

## Только НЕНУЛЕВЫЕ модификаторы записи — то, что она реально даёт
static func nonzero_modifiers(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in BONUS_KEYS:
		var key: String = String(k)
		var v: float = float(src.get(key, 0.0))
		if v != 0.0:
			out[key] = v
	return out

## Карточки наград уровня level (1..max) с полями stat/value
static func veteran_choices(unit_type: String, level: int) -> Array:
	var b: Array = _vet_bonuses(unit_type)
	if level < 1 or level > b.size():
		return []
	var lst: Array = b[level - 1]
	for e in lst:
		var d: Dictionary = e
		if d.has("stat"):
			continue
		var nz: Dictionary = nonzero_modifiers(d)
		var first: String = ""
		for k in nz:
			first = String(k)
			break
		d["stat"]  = modifier_stat_name(first) if first != "" else ""
		d["value"] = float(nz.get(first, 0.0)) if first != "" else 0.0
	return lst

static func veteran_choice_at(unit_type: String, level: int, choice_id: String) -> Dictionary:
	for c in veteran_choices(unit_type, level):
		var d: Dictionary = c
		if String(d.get("id", "")) == choice_id:
			return d
	return {}

static func veteran_choice_info(unit_type: String, choice_id: String) -> Dictionary:
	for lvl_list in _vet_bonuses(unit_type):
		for c in (lvl_list as Array):
			var d: Dictionary = c
			if String(d.get("id", "")) == choice_id:
				return d
	return {}

## ── ГАРНИЗОН ЗАМКА: ПОПОЛНЕНИЕ И ЛЕЧЕНИЕ ──
const GARRISON_SQUAD_LIMIT   := 8    # отрядов в одном замке
## Лечение в замке: HP в секунду каждой раненой модели, у всех одновременно
const GARRISON_HEAL_PER_SEC  := 1.0 / 0.7
const GARRISON_REVIVE_SECONDS := 5.0 * 0.7  # секунд на одну восстановленную модель
## Дистанция до замка, с которой отряд «входит внутрь», м
const GARRISON_ENTER_RADIUS  := 5.0
const GARRISON_AUTO_RELEASE  := true  # здоровый отряд выпускается сам

## ── СТРОЙКА И РУИНЫ ──
const CONSTRUCTION_MIN_SEC := 6.0  # минимум времени стройки, с
## Замок ставится бесплатно и строится сам, с
const CASTLE_BUILD_SEC     := 8.0
## Сколько лежат руины, с (0 — вечно); последние RUIN_FADE_SEC растворяются дизером
const RUIN_LIFETIME_SEC    := 600.0
const RUIN_FADE_SEC        := 20.0

## Вес бойца рода в счёте силы и морали отряда (поле squad_weight, по умолчанию 1)
static func squad_weight(unit_id: String) -> float:
	return maxf(float(stat(unit_id, "squad_weight", 1.0)), 0.01)

## Сколько слотов лимита отрядов занимает отряд рода (поле squad_slots; рыцари — 2)
static func squad_slots(unit_id: String) -> int:
	return maxi(int(round(float(stat(unit_id, "squad_slots", 1.0)))), 1)

## Размер отряда по роду; гоблины — из goblin_config.SQUAD_SIZE; рабочий и прочие — 1
static func squad_size(unit_id: String) -> int:
	match unit_id:
		"spearman": return SQUAD_SIZE_SPEARMEN
		"archer":   return SQUAD_SIZE_ARCHERS
		"warrior":  return SQUAD_SIZE_SWORDSMEN
		"monk":     return SQUAD_SIZE_MONKS
	# гоблины отвечают своим конфигом
	var gs: Variant = _GobCfg.SQUAD_SIZE.get(unit_id)
	if gs != null:
		return int(gs)
	return 1

## ── НАЙМ: где, за сколько, какого размера отряд (cols — справочно: код не читает) ──
const TRAINING := {
	"castle": {
		# рабочий покупается мясом — связь бригады с домами и стадом
		"worker":   {"cost_food":  50.0, "cost_wood":  0.0, "cost_gold":  0.0, "time":  11.0, "squad": 1, "cols": 4},
		# мечники крепости выходят с лычками — дороже и дольше барачных
		"warrior":  {"cost_wood": 520.0, "cost_gold": 640.0, "cost_food": 75.0, "time": 84.0, "squad": SQUAD_SIZE_SWORDSMEN, "cols": 5},
		"monk":     {"cost_wood":  60.0, "cost_gold": 120.0, "cost_food": 20.0, "time": 20.0, "squad": SQUAD_SIZE_MONKS, "cols": 5},
		# для ИИ: он нанимает копейщиков и лучников прямо в замке
		"spearman": {"cost_wood": 150.0, "cost_gold": 45.0, "cost_food": 35.0, "time": 26.0, "squad": SQUAD_SIZE_SPEARMEN, "cols": 5},
		"archer":   {"cost_wood": 350.0, "cost_gold": 250.0, "cost_food": 45.0, "time": 32.0, "squad": SQUAD_SIZE_ARCHERS, "cols": 5},
	},
	# Цена — за ОТРЯД (60 копейщиков, по 30 лучников и мечников); еда в цене связывает армию с домами и стадом
	"barracks": {
		"spearman": {"cost_wood": 150.0, "cost_gold": 45.0, "cost_food": 35.0, "time": 26.0, "squad": SQUAD_SIZE_SPEARMEN, "cols": 5},
		"warrior":  {"cost_wood": 380.0, "cost_gold": 420.0, "cost_food": 55.0, "time": 66.0, "squad": SQUAD_SIZE_SWORDSMEN, "cols": 5},
	},
	"archery": {
		"archer":   {"cost_wood": 350.0, "cost_gold": 250.0, "cost_food": 45.0, "time": 32.0, "squad": SQUAD_SIZE_ARCHERS, "cols": 5},
	},
	"town_center": {
		"worker":   {"cost_food":  30.0, "cost_wood":  0.0, "cost_gold":  0.0, "time":  8.0, "squad": 1, "cols": 4},
	},
}

## Настройки одного заказа найма (пустой словарь — здание такого не умеет)
static func train_cfg(building_id: String, unit_id: String) -> Dictionary:
	var per_building: Dictionary = TRAINING.get(building_id, {})
	return per_building.get(unit_id, {})

## Цена заказа найма в формате ResourceManager.spend(); еда равноправна остальным
static func train_cost(building_id: String, unit_id: String) -> Dictionary:
	var d: Dictionary = train_cfg(building_id, unit_id)
	var cost: Dictionary = {}
	var w: float = d.get("cost_wood",  0.0)
	var g: float = d.get("cost_gold",  0.0)
	var s: float = d.get("cost_stone", 0.0)
	var f: float = d.get("cost_food",  0.0)
	if w > 0.0: cost[Constants.RESOURCE_WOOD]  = w
	if g > 0.0: cost[Constants.RESOURCE_GOLD]  = g
	if s > 0.0: cost[Constants.RESOURCE_STONE] = s
	if f > 0.0: cost[Constants.RESOURCE_FOOD]  = f
	return cost

## Цена найма с учётом кузницы: bonus_hire_cost (хранится у «worker») снимает долю со всех строк цены
static func train_cost_discounted(building_id: String, unit_id: String,
		discount: float) -> Dictionary:
	var cost: Dictionary = train_cost(building_id, unit_id)
	if unit_id != "worker" or discount <= 0.0:
		return cost
	var k: float = 1.0 - clampf(discount, 0.0, HIRE_DISCOUNT_CAP)
	for key in cost.keys():
		cost[key] = maxf(1.0, float(cost[key]) * k)
	return cost

## Настройки одной постройки (пустой словарь, если id незнаком)
static func building_cfg(building_id: String) -> Dictionary:
	return BUILDINGS.get(building_id, {})

## Одно числовое поле постройки с дефолтом
static func building_stat(building_id: String, key: String, default: float = 0.0) -> float:
	var d: Dictionary = BUILDINGS.get(building_id, {})
	return d.get(key, default)

## Габарит постройки
static func building_size(building_id: String, default: Vector3 = Vector3(3.0, 2.0, 3.0)) -> Vector3:
	var d: Dictionary = BUILDINGS.get(building_id, {})
	return d.get("size", default)

## Цена постройки в формате ResourceManager.spend(): {тип_ресурса: количество}
static func building_cost(building_id: String) -> Dictionary:
	var d: Dictionary = BUILDINGS.get(building_id, {})
	var cost: Dictionary = {}
	var w: float = d.get("cost_wood",  0.0)
	var g: float = d.get("cost_gold",  0.0)
	var s: float = d.get("cost_stone", 0.0)
	var f: float = d.get("cost_food",  0.0)
	if w > 0.0: cost[Constants.RESOURCE_WOOD]  = w
	if g > 0.0: cost[Constants.RESOURCE_GOLD]  = g
	if s > 0.0: cost[Constants.RESOURCE_STONE] = s
	if f > 0.0: cost[Constants.RESOURCE_FOOD]  = f
	return cost

## Что рабочий может строить: id в порядке объявления BUILDINGS
static func worker_buildable_ids() -> Array:
	var out: Array = []
	for key in BUILDINGS:
		var bid: String = String(key)
		var d: Dictionary = BUILDINGS[bid]
		if bool(d.get("worker_buildable", false)):
			out.append(bid)
	return out

## Время исследования слота по умолчанию, с (если нет своего research_time)
const DEFAULT_RESEARCH_TIME := 10.0

## ── СЛОТЫ УЛУЧШЕНИЙ КУЗНИЦЫ (applies_to — роды, requires — id предшественника) ──
const UPGRADE_SLOTS := [
	{
		"id": "spears", "name": "Копья", "desc": "+3 урон копейщикам",
		"applies_to": ["spearman"], "requires": "Bla bla bla",
		"cost_gold": 120.0, "cost_wood": 300.0, "cost_stone": 50.0,
		"research_time": 120.0, "icon": "icon_trap_spears.png",
		"bonus_attack": 3.0, "bonus_push": 0.5,
	},
	{
		"id": "shields", "name": "Щиты", "desc": "+2 броня пехоте",
		"applies_to": ["spearman", "warrior"], "requires": "",
		"cost_gold": 300.0, "cost_wood": 500.0, "cost_stone": 80.0,
		"research_time": 12.0, "icon": "icon_shield.png",
		"bonus_armor": 2.0, "bonus_speed": -0.1,
	},
	{
		"id": "helmets", "name": "Шлемы", "desc": "+15 HP всем",
		"applies_to": ["all"], "requires": "",
		"cost_gold": 380.0, "cost_wood": 400.0, "cost_stone": 260.0,
		"research_time": 10.0, "icon": "icon_heart.png",
		"bonus_health": 10.0, "bonus_morale": 10.0,
	},
	{
		"id": "armor", "name": "Броня", "desc": "+3 броня, чуть медленнее",
		"applies_to": ["all"], "requires": "shields",
		"cost_gold": 1150.0, "cost_wood": 1000.0, "cost_stone": 1200.0,
		"research_time": 20.0, "icon": "icon_broken_sword.png",
		"bonus_armor": 3.0, "bonus_speed": -0.2, "bonus_health": 10.0,
	},
	{
		"id": "swords", "name": "Мечи", "desc": "+5 урон мечникам",
		"applies_to": ["warrior"], "requires": "",
		"cost_gold": 1200.0, "cost_wood": 340.0, "cost_stone": 200.0,
		"research_time": 18.0, "icon": "icon_dual_sword.png",
		"bonus_attack": 5.0, "bonus_push": 1.0, "bonus_morale": 15.0,
	},
	{
		"id": "arrows", "name": "Стрелы", "desc": "+4 урон лучникам",
		"applies_to": ["archer"], "requires": "",
		"cost_gold": 590.0, "cost_wood": 1000.0, "cost_stone": 0.0,
		"research_time": 14.0, "icon": "icon_rain_of_arrows.png",
		"bonus_attack": 4.0,
	},
	{
		"id": "boots", "name": "Сапоги", "desc": "+0.4 скорость всем",
		"applies_to": ["all"], "requires": "",
		"cost_gold": 600.0, "cost_wood": 80.0, "cost_stone": 0.0,
		"research_time": 10.0, "icon": "icon_luck_horseshoe.png",
		"bonus_speed": 0.4,
	},
	{
		"id": "banner", "name": "Знамя", "desc": "+10 мораль, +2 напор",
		"applies_to": ["all"], "requires": "helmets",
		"cost_gold": 1800.0, "cost_wood": 360.0, "cost_stone": 300.0,
		"research_time": 220.0, "icon": "icon_might.png",
		"bonus_morale": 10.0, "bonus_push": 2.0,
	},
]

## Сколько секунд исследуется слот (поле research_time или DEFAULT_RESEARCH_TIME)
static func upgrade_research_time(slot: Dictionary) -> float:
	return maxf(float(slot.get("research_time", DEFAULT_RESEARCH_TIME)), 0.0)

## ── МОДИФИКАТОРЫ ──
## Шаблон числовых бонусов с нулями (zero_modifiers / with_all_modifiers)
const MODIFIERS := {
	"bonus_attack":   0.0,
	"bonus_armor":    0.0,
	"bonus_defense":  0.0,
	"bonus_health":   0.0,
	"bonus_speed":    0.0,
	"bonus_range":    0.0,
	"bonus_cooldown": 0.0,
	"bonus_spread":   0.0,
	"bonus_push":     0.0,
	"bonus_morale":   0.0,
	"bonus_carry":    0.0,
	"bonus_gather":   0.0,
	"bonus_cooldown_pct": 0.0,
	"bonus_armor_pen":    0.0,
	"bonus_giant":        0.0,
	"bonus_snipers":      0.0,
	"bonus_snipe_cd":     0.0,
}

## Нижний предел перезарядки: bonus_cooldown не может ускорить удар до нуля
const MIN_COOLDOWN := 0.25

## ── БАЛЛИСТИКА ЛУЧНИКА ──
## Упреждение: точка = позиция + скорость × время полёта (1.0 — полный вынос); потолок выноса, м
const ARCHER_LEAD_FACTOR := 1.0
const ARCHER_LEAD_MAX := 14.0

## Кучность (множитель разброса) и темп по уровню отряда 0..7
const ARCHER_DRILL := [
	{"spread": 1.35, "fire": 0.85},   # 0 — новобранцы: шире и медленнее
	{"spread": 1.20, "fire": 0.92},
	{"spread": 1.08, "fire": 0.97},
	{"spread": 1.00, "fire": 1.00},   # 3 — уставная норма
	{"spread": 0.90, "fire": 1.06},
	{"spread": 0.82, "fire": 1.12},
	{"spread": 0.74, "fire": 1.18},
	{"spread": 0.66, "fire": 1.25},   # 7 — высший грейд (штандарт)
]

## Один ряд лестницы выучки по уровню отряда
static func archer_drill(level: int) -> Dictionary:
	if ARCHER_DRILL.is_empty():
		return {"spread": 1.0, "fire": 1.0}
	return ARCHER_DRILL[clampi(level, 0, ARCHER_DRILL.size() - 1)]

## Нижняя граница радиуса тучи залпа, м
const VOLLEY_MIN_SPREAD := 1.10

## Снайперский выстрел (archer_2d): снайперов в отряде (+bonus_snipers), дальность прямого выстрела (м),
## скорость стрелы к обычной, задержка между снайперами (с), срок заявки на цель (мс), потолок доли брони
const SNIPE_SQUAD_BASE := 3
const SNIPE_RANGE := 25.0
const SNIPE_SPEED_MULT := 1.56
const SNIPE_STAGGER_SEC := 0.14
const SNIPE_CLAIM_MS := 1500
const ARMOR_PEN_MAX := 0.9
## Стрела в голове павшего: точка вдоль тела от его центра, доля высоты квада
const SNIPE_HEAD_ALONG := 0.30

## ── СПЛОЧЁННОСТЬ ОТРЯДА ──
const SQUAD_COHESION_DIST := 14.0  # зона отряда, м: дальше — отставший
## Как часто отряду разрешено подзывать отставших, мс
const SQUAD_COHESION_COOLDOWN_MS := 2500
## Суровая сплочённость (ручка perf_config.cohesion_strict): дерущийся по инициативе дальше FIGHT_ZONES зон
## от медианы отозван; приказ ИИ/[A] на бойца — дальше FORCED_ZONES; цель-здание и замок игрока не трогаются
const COHESION_FIGHT_ZONES := 1.25
const COHESION_FORCED_ZONES := 2.0
const COHESION_STRICT_CD_MS := 1200  # период проверки, мс

## Все ключи бонусов — по ним GameManager копит суммы, а панель рисует строки
const BONUS_KEYS := ["bonus_attack", "bonus_armor", "bonus_defense",
					 "bonus_health", "bonus_speed", "bonus_range",
					 "bonus_cooldown", "bonus_spread",
					 "bonus_push", "bonus_morale",
					 "bonus_carry", "bonus_gather", "bonus_build",
					 # лечение монаха: доля темпа, доля объёма за такт, метры к радиусу
					 "bonus_heal_rate", "bonus_heal_amount", "bonus_heal_radius",
					 # обучение рабочего: доля к темпу найма
					 "bonus_train",
					 # ауры монаха: броня, удар, темп стрельбы союзникам; метры к радиусу
					 "bonus_aura_armor", "bonus_aura_attack", "bonus_aura_rate",
					 "bonus_aura_radius",
					 # ветка лучника: доля к перезарядке, доля игнорируемой брони, прибавка к множителю
					 # урона по крупным (0.5 = ×1.5), снайперов в отряде, доля к перезарядке снайпера
					 "bonus_cooldown_pct", "bonus_armor_pen", "bonus_giant",
					 "bonus_snipers", "bonus_snipe_cd",
					 # древо мечника: удары сверх серии «Яростной атаки», задетых соседей и доля урона им
					 # («Рассечение»), доля силы удара ниже половины запаса
					 "bonus_rage_hits", "bonus_cleave", "bonus_cleave_dmg",
					 "bonus_berserk",
					 # экономика: раздельная добыча — ДОЛЯ цикла (0.15 = на 15 % быстрее)
					 "bonus_gather_wood", "bonus_gather_stone", "bonus_gather_gold",
					 # мясо (темп разделки), груз и ходьба рабочего — тоже доли
					 "bonus_gather_food", "bonus_carry_pct", "bonus_walk_pct",
					 # ход с грузом
					 "bonus_walk_loaded_pct",
					 # доля долой от цены найма рабочего; доля к темпу обучения БОЕВЫХ отрядов
					 # (bonus_train — только рабочие)
					 "bonus_hire_cost", "bonus_train_army",
					 # доля долой с отката «Яростной атаки» мечника
					 "bonus_rage_cd",
					 # «Приём копья»: прибавка к множителю рукопашного урона по крупным
					 "bonus_giant_melee",
					 # экономика (ТЗ 28.10.2026): доля к выходу мяса с туши (кусок за ходку), доля к темпу
					 # исследований Кузницы (все вкладки)
					 "bonus_meat_pct", "bonus_research_pct"]

## Шаблон с нулями — КОПИЯ, а не сам словарь: вызывающий волен его править
static func zero_modifiers() -> Dictionary:
	return MODIFIERS.duplicate()

## Дополнить запись недостающими ключами шаблона (значения не трогаются).
static func with_all_modifiers(src: Dictionary) -> Dictionary:
	var out: Dictionary = src.duplicate()
	for k in MODIFIERS:
		if not out.has(k):
			out[k] = 0.0
	return out

## ── ОБЗОР (ТУМАН ВОЙНЫ) ──
const VISION_MULT := 1.6  # обзор бойца = дальность атаки × это
const VISION_MIN  := 15.0  # нижний предел обзора бойца, м
const BUILDING_VISION := 34.0  # обзор здания, м
## Крепость видит дальше любого дома, м
const CASTLE_VISION := 62.0

## Радиус обзора по дальности атаки
static func vision_radius(attack_range: float) -> float:
	return maxf(attack_range * VISION_MULT, VISION_MIN)

## Найти слот улучшения по id (пустой словарь, если нет).
static func get_upgrade_slot(upgrade_id: String) -> Dictionary:
	for slot in UPGRADE_SLOTS:
		var d: Dictionary = slot
		if String(d.get("id", "")) == upgrade_id:
			return d
	# ── Кузница гоблинов (ТЗ 28.10.2026): узлы «gforge_*» из своего конфига; load, а не preload —
	# иначе цикл подключения (тот же приём, что forge_config._UCfgRef)
	if upgrade_id.begins_with("gforge_"):
		return load("res://scripts/economy/goblin_forge/goblin_forge_config.gd").get_node(upgrade_id)
	return _Forge.get_node(upgrade_id)

## Стоимость слота в формате ResourceManager.spend(): {тип_ресурса: количество}
static func upgrade_cost(slot: Dictionary) -> Dictionary:
	var cost: Dictionary = {}
	var g: float = slot.get("cost_gold",  0.0)
	var w: float = slot.get("cost_wood",  0.0)
	var s: float = slot.get("cost_stone", 0.0)
	var f: float = slot.get("cost_food", 0.0)
	if g > 0.0: cost[Constants.RESOURCE_GOLD]  = g
	if w > 0.0: cost[Constants.RESOURCE_WOOD]  = w
	if s > 0.0: cost[Constants.RESOURCE_STONE] = s
	if f > 0.0: cost[Constants.RESOURCE_FOOD]  = f
	return cost

## Действует ли слот на юнита данного типа
static func slot_applies_to(slot: Dictionary, unit_id: String) -> bool:
	var lst: Array = slot.get("applies_to", [])
	for e in lst:
		var s: String = String(e)
		if s == "all" or s == unit_id:
			return true
	return false

## ── ЭЛИТА КРЕПОСТИ: МЕЧНИКИ С ЛЫЧКАМИ ──
const KEEP_WARRIOR_VET := 1          # с чего начинает Крепость без улучшений
const KEEP_WARRIOR_VET_MAX := 4      # потолок ранга: I..IV
const KEEP_WARRIOR_PICKS_PER_VET := 1  # наград за каждую лычку

## Исследование ранга рыцарей: золото и время по ступеням
const KNIGHT_UPGRADE_COST := 7000.0  # золота за вторую ступень
const KNIGHT_UPGRADE_COST_MULT := 2.0  # × за каждую следующую
## Секунд исследования на ступень
const KNIGHT_UPGRADE_TIME := 60.0
const KNIGHT_UPGRADE_TIME_STEP := 30.0   # +30 с на каждую следующую ступень

const KEEP_VET_UPGRADES := {
	2: {"id": "keep_vet_2", "cost_gold": KNIGHT_UPGRADE_COST,
		"time": KNIGHT_UPGRADE_TIME},
	3: {"id": "keep_vet_3", "cost_gold": KNIGHT_UPGRADE_COST * KNIGHT_UPGRADE_COST_MULT,
		"time": KNIGHT_UPGRADE_TIME + KNIGHT_UPGRADE_TIME_STEP},
	4: {"id": "keep_vet_4",
		"cost_gold": KNIGHT_UPGRADE_COST * KNIGHT_UPGRADE_COST_MULT * KNIGHT_UPGRADE_COST_MULT,
		"time": KNIGHT_UPGRADE_TIME + KNIGHT_UPGRADE_TIME_STEP * 2.0},
}

## Римская запись ранга для интерфейса («Мечники [ I ]»)
const ROMAN := ["", "I", "II", "III", "IV", "V", "VI", "VII"]

static func roman(n: int) -> String:
	if n <= 0 or n >= ROMAN.size():
		return str(n)
	return String(ROMAN[n])

## Содержание элиты: еда и золото по рангу
const KEEP_UPKEEP_FOOD_PER_VET := 0.25   # +25 % еды за каждую лычку
const KEEP_UPKEEP_GOLD_PER_VET := 0.05   # золота в секунду за лычку, на отряд

## Во сколько раз дороже ест отряд ранга `vet` по сравнению с новобранцем
static func keep_food_mult(vet: int) -> float:
	return 1.0 + KEEP_UPKEEP_FOOD_PER_VET * float(maxi(vet, 0))

## Сколько золота в секунду ест отряд ранга `vet` (0 у новобранцев)
static func keep_gold_rate(vet: int) -> float:
	return KEEP_UPKEEP_GOLD_PER_VET * float(maxi(vet, 0))
