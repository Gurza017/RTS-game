extends RefCounted
## ХАРАКТЕРИСТИКИ ЮНИТОВ, СТОЙКИ, ВЕТЕРАНСТВО, ЦЕНЫ, ЗДАНИЯ, ЭКОНОМИКА.
## Только параметры. Подключение: const _UStats := preload("res://scripts/unit_stats_config.gd")
## Разбор чисел — docs/BALANCE_MATH.md; снятые пояснения — docs/CONFIG_NOTES_2026-09-14.md

const _Forge := preload("res://scripts/forge_config.gd")

const STATS := {
	# ── МЕЧНИК (Warrior) — тяжёлый боец, сильно толкается ────────────────────
	# ── ЭЛИТНЫЙ ТАНК (ребаланс по заказу владельца 10.09.2026) ──────────────
	"warrior": {
		"health": 340.0,                     # почти вдвое живучее копейщика (180)
		"name_genitive_plural": "мечников",
		"movement_speed": 1.9,               # НА 0.1 НИЖЕ КОПЕЙЩИКА (2.0): тяжёлый доспех
		"attack_1": 20.0,                     # обычный удар (три подряд)
		"attack_2": 28.0,                     # мощный удар (ротация 3+1)
		"attack_range": 1.6,                 # длина руки, м: ближе — бьёт
		"attack_cooldown": 1.6,                     # пауза между ударами, с
		"defense": 0.0,                      # защита: вычитается из входящего урона
		"armor": 10.0,                    # броня: доля снижения, см. ARMOR_SOFTNESS
		"morale": 85.0,                     # мораль 0..100 — тяжёлая пехота держится
		"push_force": 3.4,                   # напор: рыцарь продавливает строй
		"squad_slots": 2.0,
		"squad_weight": 2.0,
		"description": "Heavy melee fighter. Hits hardest in a straight duel and shoves enemy ranks back on contact.",
	},

	# ── КОПЕЙЩИК (Spearman) — основная пехота ────────────────────────────────
	"spearman": {
		"health": 180.0,                     # 130 HP — основа шкалы TTK, см. docs/BALANCE_MATH.md
		"name_genitive_plural": "копейщиков",
		"movement_speed": 2.0,               # скорость ходьбы, м/с
		"attack_1": 14.0,                     # урон тычка копьём
		"attack_2": 16.0,                     # мощного удара у копья нет — число про запас
		"attack_range": 2.0,                 # длина копья, м — больше, чем у меча
		"attack_cooldown": 2.0,                     # пауза между ударами, с
		"defense": 0.0,                      # защита (стойка «оборона» даёт +5)
		"armor": 3.0,                     # броня: доля снижения, см. ARMOR_SOFTNESS
		"morale": 75.0,                     # мораль 0..100
		"push_force": 1.0,                   # напор в свалке
		"description": "Backbone infantry. Holds the line shoulder to shoulder — spears level automatically when the enemy closes in.",
	},

	# ── ЛУЧНИК (Archer) — стрелок, слаб в ближнем бою ────────────────────────
	"archer": {
		"health": 110.0,                     # 80 HP: стрелок хрупок, но не бумажный
		"name_genitive_plural": "лучников",
		"movement_speed": 2.1,               # скорость ходьбы, м/с
		"attack_1": 22.0,                     # урон выстрела
		"attack_2": 30.0,                     # мощный выстрел (числом пока не пользуется)
		"attack_range": 15.0,                # БАЗА 15 м; кузница доводит до 25 (ТЗ 14.09.2026)
		# ── ЖЁСТКИЙ ПОТОЛОК ДАЛЬНОСТИ (заказ владельца, авг. 2026) ─────────
		"attack_range_cap": 25.0,
		"attack_cooldown": 3.0,                     # ДОЛГИЙ откат: залп раз в три с половиной секунды
		"defense": 0.0,                      # защита
		"armor": 1.0,                     # броня почти нулевая
		"morale": 45.0,                     # мораль 0..100 — стрелок паникует первым
		"push_force": 0.0,                   # напора нет: стрелок никого не давит
		"arrow_speed": 20.0,                 # скорость стрелы, м/с: видно дугу
		"arrow_arc": 0.20,                   # высота дуги как доля дальности
		"description": "Ranged skirmisher. Long reach and a fast squad, but folds quickly if caught in melee.",
	},

	# ── МОНАХ (Monk) — вспомогательный юнит, слаб в бою ──────────────────────
	"monk": {
		"health": 220.0,                      # запас жизни одной модели, HP
		"name_genitive_plural": "монахов",
		"movement_speed": 2.0,               # скорость ходьбы, м/с
		# ── МОНАХ НЕ ДЕРЁТСЯ (спринт 19, письмо 12) ────────────────────────
		# Ноль урона выключает и авто-агро, и ответ на удар, и тыловой напор:
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

	# ═════════════════════════════════════════════════════════════════════════
	# ═════════════════════════════════════════════════════════════════════════
	# ГОБЛИНЫ — ТРЕТЬЯ СТОРОНА (Constants.FACTION_GOBLIN)
	"goblin_spearman": {
		"health": 165.0,                     # чуть ниже людского копейщика
		"name_genitive_plural": "гоблинов",
		"movement_speed": 2.2,               # скорость, м/с: орда идёт быстрее людей
		"attack_1": 12.0,                     # «Attack Fast» — три быстрых тычка...
		"attack_2": 18.0,                    # ...затем «Attack Strong» (ротация 3+1)
		"attack_range": 2.2,                 # длина копья, м
		"attack_cooldown": 2.5,              # пауза между ударами, с
		"defense": 0.0,                      # защита
		"armor": 1.0,                        # брони нет вовсе
		"morale": 75.0,                     # орда дрогнет раньше людей
		"push_force": 0.8,                   # напор ниже людского: берут числом
		"description": "Goblin spear mob. Weak one on one, dangerous in a hundred.",
	},
	# ── ГНОЛЛ: БЫСТРЫЙ СЛАБЫЙ МЕТАТЕЛЬ (заказ спринта 13) ──────────────────
	## ── БОЛЬШОЙ ГОБЛИН: ТУША-МЯСО (заказ 13.09.2026) ──────────────────────
	# Смысл рода войск целиком в трёх числах: ЖИВУЧЕСТИ у него нет (55 против
	"big_goblin": {
		"health": 1850.0,                    # = 100 × 165 × BIG_GOBLIN_HP_SQUADS (ТЗ 14.09.2026: число, не ссылка)
		"name_genitive_plural": "больших гоблинов",
		"movement_speed": 1.54,              # 2.2 × 0.7 (−30 % от гоблина)
		"attack_1": 55.0,                    # ×3 от гоблина
		# Длинный выпад: заказ просит 4-5 «клеток», а клетка сетки ядра — метр
		"attack_range": 3.5,
		"attack_cooldown": 2.7,
		"defense": 2.0,
		"armor": 6.0,
		# Мораль высокая: туша не бежит — она затем и нужна, чтобы стоять
		"morale": 90.0,
		"push_force": 10.0,
		# Крупный боец считается за нескольких при подсчёте морали и силы
		"squad_weight": 3.0,
		"description": "Big Goblin. Slow meat wall with a wide sweep.",
	},

	"gnoll": {
		"health": 55.0,
		"name_genitive_plural": "гноллов",
		# ── ШАГ СРЕЗАН ДО 2.5 (заказ спринта 15) ──────────────────────────
		# Было 3.6 — быстрее пехоты игрока в полтора раза, и стая «мелькала»
		"movement_speed": 2.2,
		"attack_1": 15.0,
		"attack_range": 13.5,
		"attack_cooldown": 1.77,             # спринт 20: −15 % (было 2.08)
		"defense": 0.0,
		"armor": 0.0,
		# ── МОРАЛЬ ПОДНЯТА (заказ 13.09.2026: «не должны быть в вечном ужасе») ──
		"morale": 75.0,
		"push_force": 0.0,
		"description": "Gnoll bone-thrower. Fast, fragile, never fights in melee.",
	},
	"goblin_rider": {
		"health": 350.0,
		"name_genitive_plural": "наездников",
		# ── СКОРОСТЬ КАБАНА: ЗАКАЗ ВЛАДЕЛЬЦА «РАССЕКАТЬ ПОЛЕ» ─────────────
		"movement_speed": 4.6,
		"attack_1": 25.0,                    # урон обычного удара седока
		"attack_2": 35.0,                    # урон мощного удара (ротация 3+1)
		"attack_range": 2.5,                 # длина руки с седла, м
		"attack_cooldown": 2.1,              # пауза между ударами, с — вдвое чаще пехоты
		"defense": 0.0,                      # защита
		"armor": 4.0,                        # броня: шкура кабана
		"morale": 110.0,                     # мораль выше сотни: конница не дрогнет
		"push_force": 18.0,                  # напор: кабан давит строй сильнее рыцаря
		# ── УДАРНАЯ КОННИЦА: ТОЛЧОК ВДВОЕ И ПОЧТИ НА КАЖДЫЙ УДАР ───────────
		"charge_push_mult": 3.5,
		"push_every": 1,
		# ── НАТИСК С РАЗГОНА (заказ владельца, авг. 2026) ──────────────────
		"charge_range": 14.0,   # спринт 15: разгон длиннее — иначе 10 м пробега не набрать (было 10.0),                # за сколько метров до цели начинается разгон
		# ── БЕЗ РАЗГОНА НЕТ И ТАРАНА ───────────────────────────────────────
		"charge_min_runup": 10.0,            # спринт 15: ТОЛЬКО после 10 м бега по прямой
		"charge_speed_mult": 1.8,            # во сколько раз быстрее на разгоне
		"charge_impact_frac": 0.5,           # доля МАКС. запаса ЖЕРТВЫ, снимаемая тараном
		# ── ОДИН ВСАДНИК = ДВА ПЕХОТИНЦА ПРИ СЧЁТЕ СИЛЫ ОТРЯДА ────────
		"squad_weight": 2.0,
		"charge_splash": 2.0,                # радиус первого ряда контакта, м
		"charge_knockback": 2.2,             # на сколько метров отлетают накрытые
		# Сколько метров кабан проезжает СКВОЗЬ строй сразу после удара.
		"charge_breakthrough": 2.0,
		# ── ЦЕНА ЛОБОВОГО НАВАЛА НА КОПЬЯ ──────────────────────────────────
		# ── УДАР ПО РЯДАМ (заказ спринта 15) ──────────────────────────────
		"charge_row_kill": 2,
		"charge_row2_frac": 0.3,
		"charge_row_depth": 1.1,
		"charge_counter_frac": 0.35,         # доля СВОЕГО запаса за навал на копья
		"description": "Pig rider. Fast shock cavalry — hits hard, dies fast.",
	},

	# ── ТРОЛЛЬ — БОСС ЛОГОВА (заказ владельца, 09.09.2026) ───────────────────
	# Запас жизни — «три полных отряда копейщиков / 180 юнитов»: 180 × 180 HP.
	"troll": {
		# 32400 (180 копейщиков) −30 % (10.09.2026) −20 % (спринт 14)
		"health": 8160.0,                   # спринт 20: −20 % (было 12700)
		"name_genitive_plural": "троллей",
		"movement_speed": 2.88,              # тяжёлый шаг; +20 % к прежним 2.4 (заказ 09.09.2026)
		"attack_1": 70.0,                    # удар дубиной по цели
		"attack_2": 100.0,
		"attack_range": 4.5,                 # длина дубины, м
		"attack_cooldown": 1.7,            # 1.4 / 1.2: темп ударов +20 % (заказ 10.09.2026)
		"defense": 0.0,
		"armor": 12.0,                       # толстая шкура
		"morale": 300.0,                     # не паникует никогда
		"push_force": 30.0,                  # сминает шеренгу напором
		"push_every": 1,
		"charge_push_mult": 4.6,
		"charge_range": 10.0,                # разгон с шестнадцати метров
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

	# ── РАБОЧИЙ (Worker / Pawn) — не боец ────────────────────────────────────
	"worker": {
		# ── РАБОЧИЙ ВООРУЖЁН (спринт 19, письмо 10) ────────────────────────
		"health": 55.0,
		"attack_1": 4.0,
		"attack_range": 1.3,
		"attack_cooldown": 1.6,
		# ── МЕДЛЕННЫЙ СТАРТ (письмо 12): без кузницы рабочий идёт, рубит и
		"walk_speed_empty": 2.5,             # скорость БЕЗ груза, м/с
		# ── ГРУЖЁНЫЙ ИДЁТ ЗАМЕТНО МЕДЛЕННЕЕ (баланс темпа, см. BALANCE_MATH) ─
		"walk_speed_loaded": 1.6,            # скорость С грузом, м/с
		"defense": 0.0,                      # защита
		"armor": 0.0,                        # броня
		"morale": 40.0,                      # мораль 0..100
		"push_force": 0.5,                   # напор: рабочего сдвигает любой боец
		# ── БАЗОВАЯ ДОБЫЧА НАМЕРЕННО СКРОМНАЯ ──────────────────────────────
		"gather_time": 6.0,                  # секунд на один цикл добычи
		"gather_amount": 15.0,                # сколько ресурса приносит за ходку
		"description": "Gathers resources and builds structures. Fights back with an axe when cornered.",
	},
}

## Размеры гоблинских отрядов лежат в их собственном конфиге (см. squad_size)
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## СТОЙКИ ОТРЯДА (STANCES) — кнопки [АТАКА] / [ЗАЩИТА] на панели отряда
const STANCE_ATTACK  := "attack"
const STANCE_DEFENSE := "defense"

## ОБЩИЙ МНОЖИТЕЛЬ СИЛЫ ТОЛЧКА (knockback) для всех юнитов.
const PUSH_GLOBAL_SCALE := 0.35

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
		"move_speed_mult":   0.65,   # −35% скорости ходьбы (щит/опущенные копья)
		"morale_mult":       1.30,   # +30% морали
		"defense_bonus":     5.0,    # +5 защиты
		"holds_ground":      true,   # с места не сходят (кроме смыкания рядов)
		# ── ЗАМОК ПОЗИЦИИ СНЯТ ОБРАТНО (заказ владельца, авг. 2026) ────────
		# Короткая история этой ручки, чтобы её не завели в третий раз.
		"lock_position":     false,
	},
}

## Словарь стойки по id; неизвестная стойка → «атака» (стандартные параметры)
static func get_stance(stance_id: String) -> Dictionary:
	return STANCES.get(stance_id, STANCES["attack"])

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## ОТСТУП ОТ СКАЛ ПРИ ОБХОДЕ — ПО ГАБАРИТУ (ТЗ 19.09.2026, обход гор и углов)
## Читает Unit.nav_clearance(): пехота и гоблины, конница (charge_range > 0),
## гиганты (fine_ring_radius > 0), тролль — своё. Метры от кромки скалы
const NAV_CLEARANCE_INFANTRY := 1.5
const NAV_CLEARANCE_CAVALRY := 2.2
const NAV_CLEARANCE_GIANT := 3.5
const NAV_CLEARANCE_TROLL := 4.0

## БОЕВАЯ МАТЕМАТИКА: КАК БРОНЯ СНИЖАЕТ УРОН
const ARMOR_SOFTNESS := 25.0

const ARMOR_MIN_TOTAL := -12.0

static func damage_after_armor(amount: float, total_defense: float) -> float:
	var d: float = maxf(total_defense, ARMOR_MIN_TOTAL)
	if d == 0.0:
		return amount
	return amount * ARMOR_SOFTNESS / (ARMOR_SOFTNESS + d)

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## МОРАЛЬ И ПАНИКА (WHITE FLAG)
const MORALE_MAX := 100.0
## ── ЧИСЛО ОПУЩЕНО С 90 ДО 40 ПО ЗАКАЗУ ВЛАДЕЛЬЦА ──────────────────────────
## Доля полного штата, гибель которой снимает столько же морали. Читается так:
const MORALE_LOSS_PER_DEATH := 40.0
const MORALE_LOSS_PER_HIT := 0.02
const MORALE_GAIN_PER_KILL := 2.0
const MORALE_REGEN_PER_SEC := 3.0

## ── ПОРОГ ПАНИКИ ───────────────────────────────────────────────────────────
## Срабатывает по ЛЮБОМУ из двух условий (заказ владельца):
const PANIC_THRESHOLD := 0.30
const PANIC_RATIO := 0.5

## ── «НАС ПОЧТИ НЕ ОСТАЛОСЬ» — ТРЕТИЙ ПОРОГ, ПО СЧЁТУ ЖИВЫХ ─────────────────
const PANIC_LAST_MEN := 6

const PANIC_LAST_MEN_MIN_ROSTER := PANIC_LAST_MEN * 2
## ── ПРЕДОХРАНИТЕЛЬ ПАНИКИ (срочный багфикс 19.09.2026) ─────────────────────
## Паника возможна ТОЛЬКО при критических потерях: живых не больше этой доли
## полного штата (0.30 — из 30 лучников осталось 9). Отряд в бою без потерь,
## отряд без урона за окно RECENT_HIT_WINDOW_MS и отряд вне боя не срываются
## НИКОГДА — ни абсолютным, ни относительным порогом
const PANIC_ALIVE_FRAC := 0.30
## …и даже тогда не гарантированно: каждая НОВАЯ потеря ниже порога — жребий
## с этим шансом (аура своей легенды делит шанс, чужой — умножает)
const PANIC_CHANCE := 0.5
## ── ДЛИТЕЛЬНОСТЬ СТУПОРА СОКРАЩЕНА НА 30 % (заказ 13.09.2026) ──────────────
const PANIC_STUN_SEC := 14.0
## ── КОНУС РАЗБЕГА (заказ 13.09.2026) ───────────────────────────────────────
const PANIC_CONE_DEG := 30.0
## ── ОТ КРАЯ КАРТЫ ОТТАЛКИВАЕМСЯ (заказ 13.09.2026) ─────────────────────────
const PANIC_EDGE_MARGIN := 18.0
## На сколько метров паникующие разбегаются. РАЗБЕГАЮТСЯ ВРАССЫПНУЮ, А НЕ
const PANIC_FLEE_DIST := 12.0
## Паника — строго один раз (ТЗ 19.09.2026): отбежал → в замок лечиться;
## места нет — ждёт у кольца замка, переспрашивая раз в PANIC_HEAL_RETRY_SEC
const PANIC_MAX_RUNS := 1
const PANIC_HEAL_RETRY_SEC := 10.0
const PANIC_HEAL_WAIT_R := 3.0
## ── НАСКОЛЬКО ШИРОКО ОТРЯД ПРИ ЭТОМ РАССЫПАЕТСЯ ────────────────────────────
const PANIC_SPREAD := 4.0
const PANIC_REGROUP_MULT := 1.6
## Во сколько раз режется защита паникующего (−30 %)
const PANIC_ARMOR_MULT := 0.70
const PANIC_RECOVER_MORALE := 0.55

## ── ЛЕГЕНДАРНЫЙ ОТРЯД ПОДНИМАЕТ СВОИХ И ДАВИТ ЧУЖИХ ────────────────────────
const LEGEND_AURA_RADIUS := 28.0
const LEGEND_AURA_ALLY_MULT := 1.50
const LEGEND_AURA_FOE_MULT := 0.75
## Ранг, с которого отряд считается легендарным (золотой штандарт)
const LEGEND_TIER := 7

## ── ЧИСЛА ЛЕГЕНДАРНЫХ ПЕРКОВ ───────────────────────────────────────────────
const LEGEND_PIERCE_FRAC := 0.30      ## «Пробитие брони»: игнорирует 30 % защиты
const LEGEND_ARROW_GUARD := 0.40      ## «Стена щитов»: −40 % урона от стрел
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

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
## ПОСТРОЙКИ (BUILDINGS) — ЕДИНАЯ ТАБЛИЦА ПАРАМЕТРОВ
const SMITH_ICONS_DIR := "res://assets/factions/humans/icons/buildings/icons_for_smith/"

## ═════════════════════════════════════════════════════════════════════════════
## ═════════════════════════════════════════════════════════════════════════════
## ЁМКОСТЬ РУДНИКА (ОДНОЙ КУЧИ ЗОЛОТА ИЛИ КАМНЯ)
const DEFAULT_CLUSTER_GOLD  := 10000.0
const DEFAULT_CLUSTER_STONE := 10000.0

## Ёмкость кучи по виду ресурса ("gold"/"stone"). Строкой, а не числом
static func cluster_stock(kind: String) -> float:
	match kind:
		"gold":  return DEFAULT_CLUSTER_GOLD
		"stone": return DEFAULT_CLUSTER_STONE
	return DEFAULT_CLUSTER_STONE

## Полный путь к иконке кузницы по ИМЕНИ ФАЙЛА.
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

# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
## ── СТАРТОВЫЙ ЗАПАС УРЕЗАН ДО ИГРОВОГО ─────────────────────────────────────
## ══ ЗАФИКСИРОВАНО ВЛАДЕЛЬЦЕМ 10.09.2026 — НЕ МЕНЯТЬ ═════════════════════
const PLAYER_STARTING_RESOURCES := {
	Constants.RESOURCE_WOOD:  65600.0,   # дерево: замок, рабочие, дома
	Constants.RESOURCE_GOLD:  55600.0,   # золото: найм, исследования, способности
	Constants.RESOURCE_STONE: 57600.0,   # камень: только постройки
	Constants.RESOURCE_FOOD:  15600.0,   # еда: капает с домов, тратится на найм
}

## ЗАПАС ИИ ПРАВИТСЯ ОТДЕЛЬНО ОТ ИГРОЦКОГО — и ровно ради этого блоки разные:
const AI_STARTING_RESOURCES := {
	Constants.RESOURCE_WOOD:  15450.0,     # дерево
	Constants.RESOURCE_GOLD:  15350.0,     # золото
	Constants.RESOURCE_STONE: 15300.0,     # камень
	Constants.RESOURCE_FOOD:  15300.0,     # еда
}

## Стартовый запас фракции. ВСЕГДА возвращает полный набор из четырёх ресурсов:
static func starting_resources(faction: int) -> Dictionary:
	var src: Dictionary = AI_STARTING_RESOURCES if faction == Constants.FACTION_ENEMY \
		else PLAYER_STARTING_RESOURCES
	return {
		Constants.RESOURCE_WOOD:  float(src.get(Constants.RESOURCE_WOOD,  0.0)),
		Constants.RESOURCE_GOLD:  float(src.get(Constants.RESOURCE_GOLD,  0.0)),
		Constants.RESOURCE_STONE: float(src.get(Constants.RESOURCE_STONE, 0.0)),
		Constants.RESOURCE_FOOD:  float(src.get(Constants.RESOURCE_FOOD,  0.0)),
	}

const BUILDINGS := {
	"castle": {
		"name": "Замок",                          # подпись в интерфейсе
		"max_hp": 15000.0,                         # запас жизни постройки
		"build_time": 15.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(8.0, 6.0, 8.0),           # габарит коллизии и спрайта, м
		"cost_wood": 3300.0,                       # цена: дерево
		"cost_gold": 1300.0,                       # цена: золото
		"cost_stone": 2300.0,                      # цена: камень
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
	"barracks": {
		"name": "Бараки",                         # подпись в интерфейсе
		"max_hp": 7000.0,                         # запас жизни постройки
		"build_time": 20.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(3.5, 2.2, 3.5),           # габарит, м
		# ── ЦЕНА ПОД НОВЫЙ ТЕМП ЭКОНОМИКИ ──────────────────────────────────
		"cost_wood": 1320.0,                       # цена: дерево
		"cost_gold": 1150.0,                       # цена: золото
		"cost_stone": 1220.0,                      # цена: камень
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/Barracks.png",
	},
	"archery": {
		"name": "Стрелковая",                     # подпись в интерфейсе
		"max_hp": 3800.0,                         # запас жизни постройки
		"build_time": 20.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(3.5, 2.2, 3.5),           # габарит, м (как у бараков)
		"cost_wood": 280.0,                       # цена: дерево
		"cost_gold": 120.0,                       # цена: золото
		"cost_stone": 1160.0,                      # цена: камень
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/Archery.png",
	},
	"tower": {
		"name": "Башня",                          # подпись в интерфейсе
		# ── ОЧЕНЬ ПРОЧНАЯ И ДОРОГАЯ (заказ владельца 10.09.2026) ──────────
		"max_hp": 8000.0,                         # запас жизни постройки
		"build_time": 30.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(3.4, 3.0, 3.4),           # габарит, м (см. выше)
		"cost_wood": 1300.0,                       # цена: дерево
		"cost_gold": 200.0,                       # цена: золото
		"cost_stone": 1600.0,                      # цена: камень (башня каменная)
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/Tower.png",
		# ── СВОИ КАРТИНКИ СТРОЙКИ И РУИН, ПОЭТОМУ ДОЛЯ РАВНА ЕДИНИЦЕ ──────
		"construction_scale": 1.0,                # своя картинка стройки
		"ruin_scale": 1.0,                        # своё пепелище
	},
	"smithy": {
		"name": "Кузница",                        # подпись в интерфейсе
		"max_hp": 4000.0,                         # запас жизни постройки
		"build_time": 40.0,                       # вдвое дольше обычных зданий (заказ 10.09.2026)
		"size": Vector3(4.0, 3.0, 4.0),           # габарит, м
		# КУЗНИЦА ДОРОЖЕ БАРАКОВ, но обе в пределах первых двух минут:
		"cost_wood": 1450.0,                       # цена: дерево
		"cost_gold": 300.0,                       # цена: золото
		"cost_stone": 1580.0,                      # цена: камень
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/Monastery.png",
	},
	"mine": {
		"name": "Золотой рудник",                 # подпись в интерфейсе
		"max_hp": 1250.0,                          # запас жизни постройки
		"build_time": 10.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(3.0, 2.0, 3.0),           # габарит, м
		"cost_wood": .0,                          # рудник бесплатен: ставится на жилу
		"cost_gold": 0.0,
		"cost_stone": 0.0,
		# ── РУДНИК УБРАН ИЗ МЕНЮ РАБОЧЕГО (заказ спринта 13) ───────────────
		"worker_buildable": false,                # кнопки на панели рабочего нет
		# ЗДЕСЬ СТОЯЛА Tower.png, А СПРАЙТ БЫЛ House1 — это и была жалоба
		"icon": "res://assets/factions/humans/icons/hud/Gold_Resource.png",
	},
	"house": {
		"name": "Дом",                            # подпись в интерфейсе
		"max_hp": 380.0,                          # запас жизни постройки
		"build_time": 10.0,                       # секунд работы ОДНОГО рабочего
		"size": Vector3(2.6, 2.2, 2.6),           # габарит, м
		"cost_wood": 360.0,                        # цена: дерево (дом дешёвый)
		"cost_gold": 0.0,
		"cost_stone": 300.0,
		"worker_buildable": true,                 # кнопка есть на панели рабочего
		"icon": "res://assets/factions/humans/icons/buildings/House1.png",
	},
	"house2": {
		"name": "Дом", "max_hp": 380.0, "build_time": 10.0,
		"size": Vector3(2.6, 2.2, 2.6),
		"cost_wood": 360.0, "cost_gold": 0.0, "cost_stone": 300.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/House2.png",
	},
	"house3": {
		"name": "Дом", "max_hp": 180.0, "build_time": 10.0,
		"size": Vector3(2.6, 2.2, 2.6),
		"cost_wood": 360.0, "cost_gold": 0.0, "cost_stone": 300.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/House3.png",
	},
	# ── ЗАГОН ДЛЯ ОВЕЦ (спринт 13, размеры пересчитаны в спринте 14) ───────
	# ── ПРОПОРЦИЯ СЧИТАЕТСЯ ПО ЭКРАНУ, А НЕ ПО ЗЕМЛЕ ──────────────────────
	# ── СТАВИТСЯ СРАЗУ, БЕЗ СТРОЙКИ (заказ спринта 14) ────────────────────
	# Заменил в меню рабочего золотой рудник.
	"sheep_pen": {
		"name": "Загон для овец",
		"max_hp": 400.0,
		"build_time": 0.0,
		"instant_build": true,
		"size": Vector3(5.0, 1.4, 5.3),
		"cost_wood": 180.0,
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

const HOUSE_FOOD_INCOME   := 2.0   # сколько еды даёт один дом за начисление (4 → 2, 10.09.2026)
const HOUSE_FOOD_INTERVAL := 8.0   # как часто начисляет, секунд

## ── СОДЕРЖАНИЕ АРМИИ ЕДОЙ (заказ владельца, 10.09.2026) ──────────────────────
## Расчёт: десять домов дают 10 × HOUSE_FOOD_INCOME / HOUSE_FOOD_INTERVAL =
const FOOD_UPKEEP_SQUAD_PER_SEC  := 0.1
const FOOD_UPKEEP_WORKER_PER_SEC := 1.0 / 30.0
const FOOD_UPKEEP_TICK := 1.0
const FOOD_UPKEEP_FACTIONS := [Constants.FACTION_PLAYER]

## ── СТАДО ИГРОКА: ПОТОЛКИ ВЫПАСА (заказ спринта 13) ───────────────────────
## У ЗАМКА пасётся мало и медленно: CASTLE_GRAZE_LIMIT овец в радиусе
const SHEEP_PEN_CAPACITY  := 30
## Загонов у игрока — не больше SHEEP_PEN_MAX_COUNT (как крепости, отказ с
## подсказкой), овец у игрока всего — не больше SHEEP_PLAYER_MAX (ТЗ 19.09.2026)
const SHEEP_PEN_MAX_COUNT := 3
const SHEEP_PLAYER_MAX    := 90
const CASTLE_GRAZE_LIMIT  := 5
const CASTLE_GRAZE_RADIUS := 20.0
const STARVE_MORALE_PER_SEC := 1.5
const STARVE_MORALE_FLOOR := 0.40

## Какие записи BUILDINGS — дома (три картинки, один баланс)
const HOUSE_IDS := ["house", "house2", "house3"]

static func is_house(building_id: String) -> bool:
	return building_id in HOUSE_IDS

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## ── КРЕПОСТЬ ТОЖЕ ДАЁТ ЛИМИТ (заказ владельца 10.09.2026) ─────────────────
## ЛИМИТ НАСЕЛЕНИЯ ИГРОКА (заказ 09.09.2026)
const POP_LIMIT_ENABLED   := true
const POP_BASE_WORKERS    := 10     # рабочих без крепости и домов (стартовая бригада)
const POP_BASE_SQUADS     := 3     # боевых отрядов без крепости
const CASTLE_WORKER_SLOTS := 10    # +рабочих за каждую крепость
const CASTLE_SQUAD_SLOTS  := 5     # +отрядов за каждую крепость
const HOUSE_WORKER_SLOTS  := 3     # +рабочих за каждый дом
const HOUSE_SQUAD_SLOTS   := 3     # +отрядов за каждый дом

static func pop_worker_cap(houses: int, castles: int = 0) -> int:
	return POP_BASE_WORKERS + HOUSE_WORKER_SLOTS * maxi(houses, 0) \
		+ CASTLE_WORKER_SLOTS * maxi(castles, 0)

static func pop_squad_cap(houses: int, castles: int = 0) -> int:
	return POP_BASE_SQUADS + HOUSE_SQUAD_SLOTS * maxi(houses, 0) \
		+ CASTLE_SQUAD_SLOTS * maxi(castles, 0)

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## БАШНЯ (TOWER)
const TOWER_VISION           := 35.0
## Сколько отрядов помещается в башню и каких родов войск
const TOWER_GARRISON_LIMIT   := 1
const TOWER_GARRISON_TYPES   := ["archer"]
## ── СКОЛЬКО ЛУЧНИКОВ ВИДНО НА ПЛОЩАДКЕ (заказ владельца 10.09.2026) ───────
const TOWER_VISIBLE_ARCHERS  := 10
## ГАРНИЗОН СТРЕЛЯЕТ С ПЛОЩАДКИ (09.09.2026) НА СВОЮ ШТАТНУЮ ДАЛЬНОСТЬ:
const TOWER_RETARGET_SEC     := 0.25

## ── ГАРНИЗОН НА КРЫШЕ (ТЗ 14.09.2026, Garrison System Overhaul) ────────────
## Бафф высоты — любому укрытому стрелку (башня, бараки, крепость)
const GARRISON_RANGE_MULT    := 1.30
const GARRISON_DAMAGE_MULT   := 1.30
## Срез укрытия (ТЗ 19.09.2026): защитник на крыше получает эту долю урона
## стрелы, стены — полный урон параллельно (Castle.take_damage)
const GARRISON_COVER_FRAC    := 0.5
## Сколько стрелковых отрядов помещается на крышу и сколько стрелков видно
const ROOF_SQUADS := {"tower": 1, "barracks": 1, "castle": 2}
## ТЗ 19.09.2026 (п. 4): бараки — 15 на крыше из 30 (остальные в резерве),
## крепость — 40 из 60 (9 на левой башне + 22 на настиле двумя половинками
## по 11 + 9 на правой башне); павшего на крыше сменяет резервист
const ROOF_VISIBLE := {"tower": 10, "barracks": 15, "castle": 40}
## На какой доле высоты рисунка стоят ноги (крепость: настил и фланговые башни)
## 15.09.2026: опущены — бойцы «летали» над зубцами (башня 0.60 → 0.52,
## бараки 0.56 → 0.44, крепость 0.66 → 0.50, фланги 0.78 → 0.54)
const ROOF_FOOT_FRAC := {"tower": 0.52, "barracks": 0.44, "castle": 0.50}
## Фланговые полубашни крепости выше настила (ступеньки): ноги на 0.60 рисунка
const CASTLE_FLANK_FOOT_FRAC := 0.60
## Крепостей на игрока — не больше трёх, каждая следующая дороже в CASTLE_COST_MULT раз
const CASTLE_MAX_COUNT := 3
const CASTLE_COST_MULT := 4.0

## Цена постройки с учётом уже стоящих (для крепости — прогрессивная)
static func building_cost_scaled(building_id: String, existing: int) -> Dictionary:
	var cost: Dictionary = building_cost(building_id)
	if building_id != "castle" or existing <= 0:
		return cost
	var k: float = pow(CASTLE_COST_MULT, float(existing))
	for key in cost.keys():
		cost[key] = float(cost[key]) * k
	return cost

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## РАЗМЕР ОТРЯДА (SQUAD SIZE) — СКОЛЬКО МОДЕЛЕЙ В ОДНОМ ОТРЯДЕ
const SQUAD_SIZE_SPEARMEN  := 60   # копейщики
const SQUAD_SIZE_ARCHERS   := 30   # лучники
const SQUAD_SIZE_SWORDSMEN := 30   # мечники (рыцари)
const SQUAD_SIZE_MONKS     := 1

## ── ЧИСЛА БОЛЬШОГО ГОБЛИНА ВЫВОДЯТСЯ ИЗ ГОБЛИНСКИХ ────────────────────────
const BIG_GOBLIN_HORDE_SQUAD := 100   # = goblin_config.SQUAD_SIZE.goblin_spearman
## Сколько СТАНДАРТНЫХ ОТРЯДОВ орды весит одна туша по запасу жизни.
const BIG_GOBLIN_HP_SQUADS := 0.5     # 13.09.2026: запас порезан вдвое (было 1.0)
## Удар ×3 от гоблинского attack_1
## Отряд туш — ровно пять (заказ)
const SQUAD_SIZE_BIG_GOBLIN := 5
const MONK_LIMIT           := 3
## Лечение: радиус ауры, такт и «секунд на полный запас одного бойца»
const MONK_HEAL_RADIUS     := 20.0   # ТЗ 16.09.2026: аура 20 м по умолчанию (было 10)
## ИСТОРИЯ (до 17.09.2026 каст был «в упор», 3 м): теперь каст — из любой
## точки ауры (Monk.cast_range() = heal_radius()), а монах встаёт на
## MONK_STAND_FRAC радиуса от центра отряда-пациента — снаружи строя.
## Константу читают стенды как помощник расстановки
const MONK_CAST_RANGE      := 3.0
const MONK_STAND_FRAC      := 0.7    # где встать: доля радиуса ауры от центра отряда
const MONK_MOVE_SLACK      := 3.0    # новый приказ подхода — только если точка ушла дальше
const MONK_HEAL_LEASH      := 14.0
const MONK_STEP_SEC        := 0.6
const MONK_HEAL_TICK       := 0.5
## Одиночное лечение МЕДЛЕННОЕ (письмо 12, tier 1): полный запас за 14 с;
const MONK_HEAL_SEC_PER_MAN := 10.0
## ── ДИСТАНЦИЯ МЕЖДУ МОНАХАМИ (письмо 12) ───────────────────────────────────
const MONK_SPACING := 5.0
## ── ВОСКРЕШЕНИЕ (письмо 12, tier 3, forge monk_3d) ─────────────────────────
const MONK_RES_SEC := 5.0            # канал воскрешения (ТЗ 17.09.2026: 15 → 5)
const MONK_RES_COOLDOWN := 5.0       # откат между каналами; 4d / 5d — короче
const MONK_RES_COOLDOWN_4D := 4.0
const MONK_RES_COOLDOWN_5D := 2.0
## 13.09.2026: павшие ищутся в MONK_RES_SEARCH_RADIUS (шире радиуса лечения:
const MONK_RES_SEARCH_RADIUS := 30.0
const MONK_RES_YIELD_FRAC := 0.4
const MONK_RES_HP := 1.0
const MONK_RES_PARALLEL_MULT := 0.7
## ── ОПЫТ ЗА ЛЕЧЕНИЕ, А НЕ ЗА УБИЙСТВА (письмо 12) ──────────────────────────
const MONK_XP_HP_PER_KILL := 150.0
const MONK_RES_XP_KILLS := 3
## ── АУРЫ ПОДДЕРЖКИ (награды ветеранства монаха) ────────────────────────────
## Базовый радиус MONK_AURA_BASE_R плюс «Аура радиуса»; раздача раз в
const MONK_AURA_BASE_R := 4.0
const MONK_AURA_TICK := 1.0
const MONK_AURA_HOLD_MS := 1700
const MONK_AOE_RATE        := 0.5
## ── АВТОНОМНЫЙ МОНАХ (ТЗ 16.09.2026) ───────────────────────────────────────
## Скан раз в MONK_SCAN_SEC (или по событию), радиус ауры по умолчанию
## MONK_AURA_R; свободный монах выбирает самый побитый ОТРЯД; нет раненых —
## один скан по карте и марш к ближайшему своему отряду на MONK_FRONT_DIST;
## никого — сон по физике. Под ударом — отход на MONK_RETREAT_DIST к своим
const MONK_SCAN_SEC        := 1.2
const MONK_AURA_R          := 20.0
const MONK_FRONT_DIST      := 10.0
const MONK_RETREAT_DIST    := 10.0
## Сколько квадов VFX лечения на одного монаха (массовый каст: на самых раненых)
const MONK_VFX_MAX         := 8

const SQUAD_SIZE_HARD_CAP := 100

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## ── ШАБЛОН НАГРАД МОНАХА: АУРЫ (письмо 12) ────────────────────────────────
## ОПЫТ ОТРЯДА (VETERANCY) — ЗВАНИЯ ЗА УБИЙСТВА, ОТДЕЛЬНО ПО ТИПАМ ЮНИТОВ
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

const _VET_BONUS_TEMPLATE := [
	# ═══════════════════════════════════════════════════════════════════════
	# ═══════════════════════════════════════════════════════════════════════
	# ── ТРИ КАРТОЧКИ НА КАЖДОЙ СТУПЕНИ, И ВСЕ ТРИ ИЗ ОДНОЙ ТРОЙКИ СТАТОВ ───
	# ── РАЗМЕН СОХРАНЁН, И ЭТО ГЛАВНОЕ ─────────────────────────────────────
	# ── ЛЫЧКА I ────────────────────────────────────────────────────────────
	# ЭТАП 1 — СЕРЕБРЯНЫЕ ЛЫЧКИ (грейды 1-3, красный вымпел)
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
	# ── ЛЫЧКА II ───────────────────────────────────────────────────────────
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
	# ── ЛЫЧКА III ──────────────────────────────────────────────────────────
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
	# ═══════════════════════════════════════════════════════════════════════
	# ═══════════════════════════════════════════════════════════════════════
	# ── ФЛАГ I ─────────────────────────────────────────────────────────────
	# ЭТАП 2 — СИНИЕ ФЛАГИ (грейды 4-6, «ласточкин хвост»)
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
	# ── ФЛАГ II ────────────────────────────────────────────────────────────
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
	# ── ФЛАГ III ───────────────────────────────────────────────────────────
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
	# ═══════════════════════════════════════════════════════════════════════
	# ═══════════════════════════════════════════════════════════════════════
	# ЭТАП 3 — ЗОЛОТОЙ ШТАНДАРТ (грейд 7): ПЯТЬ ЛЕГЕНДАРНЫХ ПЕРКОВ
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

## ═════════════════════════════════════════════════════════════════════════════
## ═════════════════════════════════════════════════════════════════════════════
const LEGEND_PERK_IDS := [
	"legend_steadfast",
	"legend_pierce",
	"legend_shieldwall",
	"legend_juggernaut",
	"legend_bloodthirst",
]

## Бит этого перка либо 0, если id в реестре нет.
static var _perk_bits: Dictionary = {}

static func perk_bit(id: String) -> int:
	if _perk_bits.is_empty():
		for i in range(LEGEND_PERK_IDS.size()):
			_perk_bits[String(LEGEND_PERK_IDS[i])] = 1 << i
	return int(_perk_bits.get(id, 0))

## Слово перков по списку выбранных наград. Незнакомые id молча пропускаются:
static func perk_mask_of(chosen: Array) -> int:
	var m := 0
	for c in chosen:
		m |= perk_bit(String(c))
	return m

## Копейщики / Рыцари (мечники) / Лучники / Монахи — четыре НЕЗАВИСИМЫХ блока.
static var VET_CONFIG: Dictionary = {
	"spearman": {"thresholds": [50, 105, 155, 235, 310, 390, 455], "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"warrior":  {"thresholds": [130, 260, 520, 780, 940, 1100, 1500], "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"archer":   {"thresholds": [130, 260, 520, 780, 940, 1100, 1500], "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	# ── МОНАХ: НАГРАДЫ — АУРЫ ПОДДЕРЖКИ (письмо 12), опыт — за лечение ─────
	"monk":     {"thresholds": [50, 130, 260, 390, 520, 650, 780], "bonuses": _VET_MONK_TEMPLATE.duplicate(true)},
	# ── ГОБЛИНЫ: ШКАЛА ЛЮДЕЙ ЦЕЛИКОМ (заказ владельца) ──────────────────────
	# Тот же шаблон наград и та же лестница порогов. Записи отдельные, а не
	"goblin_spearman": {"thresholds": [130, 260, 520, 780, 1040, 1300, 1690],
		"bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"gnoll":           {"thresholds": [80, 155, 310, 520, 730, 935, 1170],
		"bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"goblin_rider":    {"thresholds": [180, 310, 520, 780, 1040, 1300, 2080],
		"bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
}

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## ЗНАМЁНА ВЕТЕРАНСТВА — СЕМЬ ГРЕЙДОВ (заказ владельца, авг. 2026)
const BANNER_PENNANT  := 0    ## вымпел: сужается к острию
const BANNER_GUIDON   := 1    ## «ласточкин хвост»: клин вырезан из свободного края
const BANNER_STANDARD := 2    ## прямоугольный штандарт с бахромой и гербом

const BANNER_CHEVRON := Color(0.97, 0.97, 0.95)
const BANNER_TIP_COLOR := Color(0.97, 0.97, 0.95)
const BANNER_GOLD := Color(0.93, 0.76, 0.24)

const VET_BADGE_OUTLINE := Color(0.08, 0.08, 0.10, 0.9)

const VET_BANNER_TIERS := [
	{"rank": "опытных",       "shape": BANNER_PENNANT,  "cloth": Color(0.72, 0.11, 0.13),
		"chevrons": 1, "chevron_dir":  1, "white_tip": false},
	{"rank": "закалённых",    "shape": BANNER_PENNANT,  "cloth": Color(0.72, 0.11, 0.13),
		"chevrons": 2, "chevron_dir":  1, "white_tip": false},
	{"rank": "ветеранов",     "shape": BANNER_PENNANT,  "cloth": Color(0.72, 0.11, 0.13),
		"chevrons": 2, "chevron_dir":  1, "white_tip": true},
	{"rank": "элитных",       "shape": BANNER_GUIDON,   "cloth": Color(0.16, 0.34, 0.70),
		"chevrons": 1, "chevron_dir": -1, "white_tip": false},
	{"rank": "знаменитых",    "shape": BANNER_GUIDON,   "cloth": Color(0.16, 0.34, 0.70),
		"chevrons": 2, "chevron_dir": -1, "white_tip": false},
	{"rank": "прославленных", "shape": BANNER_GUIDON,   "cloth": Color(0.16, 0.34, 0.70),
		"chevrons": 2, "chevron_dir": -1, "white_tip": true},
	{"rank": "легендарных",   "shape": BANNER_STANDARD, "cloth": Color(0.55, 0.09, 0.12),
		"chevrons": 0, "chevron_dir":  1, "white_tip": false},
]

static func veteran_banner_tier(lvl: int) -> Dictionary:
	if lvl <= 0 or VET_BANNER_TIERS.is_empty():
		return {}
	var idx: int = clampi(lvl, 1, VET_BANNER_TIERS.size()) - 1
	var d: Dictionary = (VET_BANNER_TIERS[idx] as Dictionary).duplicate()
	d["key"] = idx + 1
	return d

## ПОЛНОЕ НАЗВАНИЕ ОТРЯДА: «Отряд ветеранов копейщиков».
static func veteran_rank_name(unit_id: String, lvl: int) -> String:
	var tier: Dictionary = veteran_banner_tier(lvl)
	if tier.is_empty():
		return ""
	var noun: String = String(stat_str(unit_id, "name_genitive_plural", ""))
	if noun == "":
		return "Отряд %s" % String(tier.get("rank", ""))
	return "Отряд %s %s" % [String(tier.get("rank", "")), noun]

## ── ЗНАЧОК РАНГА В ПАНЕЛИ ──────────────────────────────────────────────────
static func veteran_badge_text(lvl: int) -> String:
	var t: Dictionary = veteran_banner_tier(lvl)
	if t.is_empty():
		return ""
	if int(t.get("shape", BANNER_PENNANT)) == BANNER_STANDARD:
		return "✪"
	var g: String = "❯" if int(t.get("chevron_dir", 1)) > 0 else "❮"
	var out: String = g.repeat(maxi(int(t.get("chevrons", 1)), 1))
	if bool(t.get("white_tip", false)):
		out += "❙"
	return out

static func veteran_badge_color(lvl: int) -> Color:
	var t: Dictionary = veteran_banner_tier(lvl)
	if t.is_empty():
		return Color.WHITE
	if int(t.get("shape", BANNER_PENNANT)) == BANNER_STANDARD:
		return BANNER_GOLD
	return (t.get("cloth", Color.WHITE) as Color).lightened(0.25)

## Строковое поле характеристик с дефолтом (числовой брат — stat() выше)
static func stat_str(unit_id: String, key: String, default: String = "") -> String:
	var d: Dictionary = STATS.get(unit_id, {})
	return String(d.get(key, default))

static func _vet_thresholds(unit_type: String) -> Array:
	return (VET_CONFIG.get(unit_type, {}) as Dictionary).get("thresholds", [])

static func _vet_bonuses(unit_type: String) -> Array:
	return (VET_CONFIG.get(unit_type, {}) as Dictionary).get("bonuses", [])

## Максимальный уровень ветеранства (= число порогов) у данного типа юнита
static func max_veteran_level(unit_type: String) -> int:
	return mini(_vet_thresholds(unit_type).size(), _vet_bonuses(unit_type).size())

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

## ── СОКРАЩЁННАЯ ФОРМА НАГРАДЫ: stat/value ────────────────────────────────────
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

## Пять вариантов улучшения на уровне level (1..max) у данного типа юнита.
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

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## ГАРНИЗОН ЗАМКА (CASTLE REFILL & HEAL)
const GARRISON_SQUAD_LIMIT   := 7    # сколько отрядов помещается в один Замок
## HP в секунду каждой раненой модели, ОДНОВРЕМЕННО у всех моделей отряда
const GARRISON_HEAL_PER_SEC  := 1.0
const GARRISON_REVIVE_SECONDS := 5.0  # секунд на одну восстановленную модель
## Дистанция до Замка, с которой отряд «входит внутрь»
const GARRISON_ENTER_RADIUS  := 5.0
const GARRISON_AUTO_RELEASE  := true

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## СТРОЙКА И РУИНЫ
const CONSTRUCTION_MIN_SEC := 6.0
## Замок ставится БЕСПЛАТНО и сразу начинает строиться (заказ владельца).
const CASTLE_BUILD_SEC     := 8.0
## Сколько секунд лежат руины снесённой постройки. 0 — лежат вечно
const RUIN_LIFETIME_SEC    := 0.0

## Размер отряда по типу юнита; рабочий — всегда «отряд из одного»
static func squad_weight(unit_id: String) -> float:
	return maxf(float(stat(unit_id, "squad_weight", 1.0)), 0.01)

## ── СКОЛЬКО СЛОТОВ ЛИМИТА ЗАНИМАЕТ ОТРЯД ЭТОГО РОДА ──────────────────────
## Заказ владельца (10.09.2026): «1 отряд Рыцарей занимает 2 слота отряда».
static func squad_slots(unit_id: String) -> int:
	return maxi(int(round(float(stat(unit_id, "squad_slots", 1.0)))), 1)

static func squad_size(unit_id: String) -> int:
	match unit_id:
		"spearman": return SQUAD_SIZE_SPEARMEN
		"archer":   return SQUAD_SIZE_ARCHERS
		"warrior":  return SQUAD_SIZE_SWORDSMEN
		"monk":     return SQUAD_SIZE_MONKS
	# ГОБЛИНЫ ОТВЕЧАЮТ СВОИМ КОНФИГОМ. Спрашивают отсюда все, кто считает
	var gs: Variant = _GobCfg.SQUAD_SIZE.get(unit_id)
	if gs != null:
		return int(gs)
	return 1

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## НАЙМ ЮНИТОВ: где, за сколько и какого размера отряд
const TRAINING := {
	"castle": {
		# Рабочий обучается ДОЛГО (письмо 12): 16 с против прежних 10; линию
		"worker":   {"cost_wood":  50.0, "cost_gold":  0.0, "time":  16.0, "squad": 1, "cols": 4},
		# ── МЕЧНИКИ КРЕПОСТИ — ГОТОВАЯ ЭЛИТА (заказ 13.09.2026) ───────────
		"warrior":  {"cost_wood":  600.0, "cost_gold": 1500.0, "time": 75.0, "squad": SQUAD_SIZE_SWORDSMEN, "cols": 5},
		"monk":     {"cost_wood":  20.0, "cost_gold": 30.0, "time": 14.0, "squad": SQUAD_SIZE_MONKS, "cols": 5},
		# Оставлено для ИИ: он нанимает копейщиков и лучников прямо в замке
		"spearman": {"cost_wood": 100.0, "cost_gold": 60.0, "time": 30.0, "squad": SQUAD_SIZE_SPEARMEN, "cols": 5},
		"archer":   {"cost_wood":  200.0, "cost_gold": 300.0, "time": 30.0, "squad": SQUAD_SIZE_ARCHERS, "cols": 5},
	},
	# БАРАКИ — ТОЛЬКО ПЕХОТА (заказ 09.09.2026): лучники уехали в стрелковую
	"barracks": {
		"spearman": {"cost_wood": 100.0, "cost_gold": 60.0, "time": 30.0, "squad": SQUAD_SIZE_SPEARMEN, "cols": 5},
		"warrior":  {"cost_wood": 250.0, "cost_gold": 600.0, "time": 60.0, "squad": SQUAD_SIZE_SWORDSMEN, "cols": 5},
	},
	"archery": {
		"archer":   {"cost_wood":  200.0, "cost_gold":300.0, "time": 30.0, "squad": SQUAD_SIZE_ARCHERS, "cols": 5},
	},
	"town_center": {
		"worker":   {"cost_wood":  10.0, "cost_gold":  0.0, "time":  8.0, "squad": 1, "cols": 4},
	},
}

## Настройки одного заказа найма (пустой словарь — здание такого не умеет)
static func train_cfg(building_id: String, unit_id: String) -> Dictionary:
	var per_building: Dictionary = TRAINING.get(building_id, {})
	return per_building.get(unit_id, {})

## Цена заказа найма в формате ResourceManager.spend()
static func train_cost(building_id: String, unit_id: String) -> Dictionary:
	var d: Dictionary = train_cfg(building_id, unit_id)
	var cost: Dictionary = {}
	var w: float = d.get("cost_wood",  0.0)
	var g: float = d.get("cost_gold",  0.0)
	var s: float = d.get("cost_stone", 0.0)
	if w > 0.0: cost[Constants.RESOURCE_WOOD]  = w
	if g > 0.0: cost[Constants.RESOURCE_GOLD]  = g
	if s > 0.0: cost[Constants.RESOURCE_STONE] = s
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
	if w > 0.0: cost[Constants.RESOURCE_WOOD]  = w
	if g > 0.0: cost[Constants.RESOURCE_GOLD]  = g
	if s > 0.0: cost[Constants.RESOURCE_STONE] = s
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

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## КУЗНИЦА (BLACKSMITH)
const SMITHY := {
	"name":       "Кузница",
	"health":     500.0,
	"cost_wood":  500.0,
	"cost_stone": 500.0,
	"cost_gold":  500.0,
}

## Время исследования по умолчанию, если у слота не задан свой research_time.
const DEFAULT_RESEARCH_TIME := 10.0

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## СЛОТЫ УЛУЧШЕНИЙ КУЗНИЦЫ (UPGRADE SLOTS)
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

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## Все ключи бонусов — по ним GameManager накапливает суммы.
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

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## БАЛЛИСТИКА ЛУЧНИКА — ВСЕ ЧИСЛА ЗДЕСЬ, В КОДЕ ТОЛЬКО ФОРМУЛА
## Упреждение (ТЗ 15.09.2026): точка = позиция + скорость × время полёта,
## два прохода; 1.0 — полный вынос, потолок — страховка от стрельбы в поле
const ARCHER_LEAD_FACTOR := 1.0
const ARCHER_LEAD_MAX := 14.0

## ── КУЧНОСТЬ И ТЕМП ПО ВЫУЧКЕ ОТРЯДА ───────────────────────────────────────
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

## ── ЗАЛП: МИНИМАЛЬНОЕ НАКРЫТИЕ ─────────────────────────────────────────────
const VOLLEY_MIN_SPREAD := 1.10

## ── СНАЙПЕРСКИЙ ВЫСТРЕЛ (ТЗ 14.09.2026, Snipe Shot) ─────────────────────────
## Число снайперов в отряде при купленном archer_2d (Snipe Mastery прибавляет
## bonus_snipers), дальность прямого выстрела, множитель скорости стрелы к
## обычной, задержка между снайперами в одном залпе («раз-два-три»), срок, на
## который снайпер «забирает» цель у остальных снайперов отряда, и потолок
## доли игнорируемой брони
const SNIPE_SQUAD_BASE := 3
const SNIPE_RANGE := 25.0
const SNIPE_SPEED_MULT := 1.56
const SNIPE_STAGGER_SEC := 0.14
const SNIPE_CLAIM_MS := 1500
const ARMOR_PEN_MAX := 0.9
## Стрела в голове павшего: точка вдоль тела от его центра, доля высоты квада
const SNIPE_HEAD_ALONG := 0.30

## ── СПЛОЧЁННОСТЬ ОТРЯДА ────────────────────────────────────────────────────
const SQUAD_COHESION_DIST := 14.0
## Как часто отряду разрешено подзывать отставших, мс
const SQUAD_COHESION_COOLDOWN_MS := 2500

## Все ключи бонусов — по ним GameManager накапливает суммы, а всплывающие окна
const BONUS_KEYS := ["bonus_attack", "bonus_armor", "bonus_defense",
					 "bonus_health", "bonus_speed", "bonus_range",
					 "bonus_cooldown", "bonus_spread",
					 "bonus_push", "bonus_morale",
					 "bonus_carry", "bonus_gather", "bonus_build",
					 # ── ЛЕЧЕНИЕ МОНАХА (спринт 16): доля темпа, доля объёма за такт,
					 "bonus_heal_rate", "bonus_heal_amount", "bonus_heal_radius",
					 # ── ОБУЧЕНИЕ РАБОЧЕГО (письмо 12): доля к темпу найма ─────
					 "bonus_train",
					 # ── АУРЫ МОНАХА (письмо 12): броня, удар, темп стрельбы
					 # союзникам в радиусе; последняя — метры к самому радиусу
					 "bonus_aura_armor", "bonus_aura_attack", "bonus_aura_rate",
					 "bonus_aura_radius",
					 # ── ВЕТКА ЛУЧНИКА (ТЗ 14.09.2026): доля к перезарядке (0.1 =
					 # −10 %), доля игнорируемой брони цели, прибавка к множителю
					 # урона по крупным (0.5 = ×1.5), число снайперов в отряде,
					 # доля к перезарядке снайперского выстрела
					 "bonus_cooldown_pct", "bonus_armor_pen", "bonus_giant",
					 "bonus_snipers", "bonus_snipe_cd",
					 # ── ДРЕВО МЕЧНИКА (ТЗ-B 19.09.2026): удары сверх серии
					 # «Яростной Атаки», число задетых соседей и доля урона
					 # им («Рассечение»), доля силы удара ниже половины запаса
					 "bonus_rage_hits", "bonus_cleave", "bonus_cleave_dmg",
					 "bonus_berserk"]

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

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## ── ЧИСЛА СОКРАЩЕНЫ ПО ЗАКАЗУ ВЛАДЕЛЬЦА (авг. 2026) ────────────────────────
## ОБЗОР (ТУМАН ВОЙНЫ)
const VISION_MULT := 1.6
const VISION_MIN  := 15.0
const BUILDING_VISION := 34.0
## ── КРЕПОСТЬ ВИДИТ ДАЛЬШЕ ЛЮБОГО ДОМА (заказ владельца 10.09.2026) ────────
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

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
## ЭЛИТА КРЕПОСТИ: МЕЧНИКИ С ЛЫЧКАМИ (заказ владельца, 13.09.2026)
const KEEP_WARRIOR_VET := 1          # с чего начинает Крепость без улучшений
const KEEP_WARRIOR_VET_MAX := 4      # потолок: заказ просит I..IV
const KEEP_WARRIOR_PICKS_PER_VET := 1

## ── ИССЛЕДОВАНИЕ РАНГА РЫЦАРЕЙ: ДОРОГО, ЗОЛОТОМ И ПО ВРЕМЕНИ (13.09.2026) ─
const KNIGHT_UPGRADE_COST := 7000.0
const KNIGHT_UPGRADE_COST_MULT := 2.0
## Секунд исследования на ступень (Смитня меряет тем же — секундами _process)
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

## Римская запись ранга для интерфейса (заказ: «Мечники [ I ]»)
const ROMAN := ["", "I", "II", "III", "IV", "V", "VI", "VII"]

static func roman(n: int) -> String:
	if n <= 0 or n >= ROMAN.size():
		return str(n)
	return String(ROMAN[n])

## ── СОДЕРЖАНИЕ ЭЛИТЫ: ЕДА И ЗОЛОТО, ПО РАНГУ ──────────────────────────────
const KEEP_UPKEEP_FOOD_PER_VET := 0.25   # +25 % еды за каждую лычку
const KEEP_UPKEEP_GOLD_PER_VET := 0.05   # золота в секунду за лычку, на отряд

## Во сколько раз дороже ест отряд ранга `vet` по сравнению с новобранцем
static func keep_food_mult(vet: int) -> float:
	return 1.0 + KEEP_UPKEEP_FOOD_PER_VET * float(maxi(vet, 0))

## Сколько золота в секунду ест отряд ранга `vet` (0 у новобранцев)
static func keep_gold_rate(vet: int) -> float:
	return KEEP_UPKEEP_GOLD_PER_VET * float(maxi(vet, 0))
