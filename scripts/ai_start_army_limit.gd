extends RefCounted
## КРАСНЫЙ ИИ: лимиты, тактики, отход, рейды, башни, кузница. Только параметры.
## Спавн и тайминги — scripts/spawn_config.gd (сюда они приходят ссылками
## const X := _Spawn.AI_X). Подключение: const _AICfg := preload(...).
## История и обоснования чисел — docs/config_notes/ai_start_army_limit.md

const _UCfgRef := preload("res://scripts/unit_stats_config.gd")
const _Spawn := preload("res://scripts/spawn_config.gd")

# ── ЛИМИТЫ: до чего ИИ копит силы ──
## Сколько ОТРЯДОВ каждого рода ИИ доводит до строя (ключи — id из STATS)
const SQUAD_LIMIT := _Spawn.AI_SQUAD_LIMIT

## Потолок рабочих на экономике
const WORKER_LIMIT := _Spawn.AI_WORKER_LIMIT

## Сколько рабочих выходит на карту в первую секунду партии
const START_WORKERS := _Spawn.AI_START_WORKERS

# ── СТАРТОВЫЕ ОТРЯДЫ: СОСТАВ И РАНГ ПРИ РОЖДЕНИИ ──
## Строки {"unit", "count" (0 = уставной), "vet", "picks"}; пусто — старт равный
const START_SQUADS := _Spawn.AI_START_SQUADS

## Порядок предпочтений при авто-выборе наград СТАРТОВЫМ отрядам (ключи —
## модификаторы unit_stats_config.MODIFIERS)
const START_VETERAN_PREFERENCE := ["bonus_attack", "bonus_health",
	"bonus_defense", "bonus_armor", "bonus_speed"]

## Стартовый состав, нормализованный: count = 0 развёрнут в уставной размер
static func start_squads() -> Array:
	var out: Array = []
	for row in START_SQUADS:
		var d: Dictionary = row
		var uid: String = String(d.get("unit", ""))
		if uid.is_empty() or not _UCfgRef.STATS.has(uid):
			continue
		var n: int = int(d.get("count", 0))
		if n <= 0:
			n = _UCfgRef.squad_size(uid)
		out.append({
			"unit":  uid,
			"count": maxi(n, 1),
			"vet":   maxi(int(d.get("vet", 0)), 0),
			"picks": maxi(int(d.get("picks", 0)), 0),
		})
	return out

# ── ГАРНИЗОН И ИЗЛИШКИ ──
## Сколько отрядов КАЖДОГО рода остаётся в стойке «защита» у замка (крепость и без
## них стерегут спящая охрана HomeGuard и гарнизоны башен); 7 при лимите 10/5/6
## оставляли дома 18 из 21 — ТЗ 27.10.2026 (аудит, разд. 2)
const HOME_GUARD_PER_TYPE := 2
## С какой доли СУММАРНОГО лимита отрядов идёт штурм (ручка ai_assault_fraction)
const ASSAULT_READY_FRACTION := 0.8
## Отряд волны, ушедший вперёд её центра дальше, м, ждёт остальных (ручка ai_wave_hold)
const WAVE_LEAD_MAX := 25.0
## Огрызок меньше половины штата вливается в неполную группу своего рода не дальше, м (ручка ai_regroup_whole)
const REGROUP_JOIN_R := 30.0

## Всё сверх гарнизона идёт к точке сбора в поле, не дожидаясь полного лимита
const SEND_SURPLUS_TO_LAKE := true

## Точка сбора «в поле»: true — Main.ai_rally_point (центр карты), иначе OVERRIDE
const USE_LAKE_AS_RALLY := true
const RALLY_POINT_OVERRIDE := Vector3(0.0, 0.0, 0.0)

## Радиус вокруг точки сбора, в котором ИИ считает, что «бой у центра идёт», м
const LAKE_CONTEST_RADIUS := 26.0

## У центра нет боевых игрока, а свои там есть — идти на базу игрока
## (в оборонительном режиме не действует)
const PUSH_BASE_AFTER_LAKE_WIN := true

## Волна выходит целиком: атака начинается, когда MUSTER_FRACTION боевых
## отрядов стоят в MUSTER_RADIUS, м, от точки сбора
const AI_MUSTER_BEFORE_ATTACK := true
const MUSTER_FRACTION := 0.75
const MUSTER_RADIUS := 26.0

# ── ОБОРОНИТЕЛЬНЫЙ РЕЖИМ ──
## ИИ не идёт в лоб на базу: держит свою половину карты и рубеж; false — штурм базы
const DEFENSIVE_MODE := true

## Какую долю пути от своего замка к базе игрока ИИ считает своей (рубеж обороны)
const MAP_CONTROL_FRACTION := 0.5

## Ширина рубежа обороны, м: по ней раскладываются отряды-заслоны
const DEFENSE_LINE_WIDTH := 44.0

## Радиус вокруг рубежа, м: противник внутри — вторжение, контратака без погони дальше
const DEFENSE_ENGAGE_RADIUS := 30.0

## Патрули: отрядов, ходящих по рубежу; радиус патрульного круга, м; стоянка на точке, с
const PATROL_SQUADS := 5
const PATROL_RADIUS := 16.0
const PATROL_DWELL := 12.0

## Контратака в обороне: противник в DEFENSE_ENGAGE_RADIUS снимает секцию с поста
const AI_COUNTER_ATTACK := true

## ── ОТВОЕВАТЬ ЦЕНТР (ROLE_RECAP) ──
## Центр под игроком и армия набрана — вся армия выходит единым фронтом
const AI_RECAP_CENTER := true

## С какой доли полного лимита армии (в бойцах, total_army_cap) ИИ идёт отбивать центр
const RECAP_ARMY_FRACTION := 0.8

## Ниже какой доли наступление сворачивается обратно в оборону (гистерезис)
const RECAP_ABORT_FRACTION := 0.45

## Сколько отрядов каждого рода остаётся дома, пока армия отбивает центр
const RECAP_HOME_GUARD := 1

## Авто-выбор ветеранских наград по ходу партии и порядок предпочтений
## (короткие имена статов)
const AI_AUTO_VETERAN := true
const AI_VETERAN_PREFERENCE := ["attack", "armor", "health", "defense", "speed"]

# ── ТЕМП ──
## Мирная фаза: столько секунд ИИ не воюет и строит экономику (0 — с первой секунды)
const PEACE_SECONDS := 600.0

## Такт размышления ИИ, с (меньше — резвее, дороже по процессору)
const THINK_INTERVAL := 2.0

# ── ГЛАВНЫЙ ЦИКЛ ИИ ЛЮДЕЙ ──
## Час генерального штурма базы игрока и перемирие (не рейдит экономику), с
const AI_ASSAULT_AT_SEC := _Spawn.AI_ASSAULT_AT_SEC
const AI_TRUCE_SEC := _Spawn.AI_TRUCE_SEC
## Экспансия на ничейные рудники и отрядов на захват
const AI_CAPTURE_MINES := true
## Башни на границе: сколько; дома после стрелковой; резерв еды; пол рабочих
const AI_BUILD_TOWERS := true
const AI_TOWERS := _Spawn.AI_TOWERS
const AI_HOUSES := _Spawn.AI_HOUSES
const AI_FOOD_RESERVE := _Spawn.AI_FOOD_RESERVE
const AI_WORKER_FLOOR := _Spawn.AI_WORKER_FLOOR
## Восстановление после потерь — числа в spawn_config
const AI_WORKER_REBUILD_MIN := _Spawn.AI_WORKER_REBUILD_MIN
const AI_REBUILD_SITES := _Spawn.AI_REBUILD_SITES
const AI_REBUILD_CREW := _Spawn.AI_REBUILD_CREW
const AI_REBUILD_CASTLE_FREE := _Spawn.AI_REBUILD_CASTLE_FREE
const AI_REBUILD_REFUGEE_WAVES := _Spawn.AI_REBUILD_REFUGEE_WAVES
const RETALIATION_LEND_MIN_LEVEL := _Spawn.AI_RETALIATION_LEND_MIN_LEVEL
## Точка башни: на этой доле пути от замка к базе игрока, по очереди слева и
## справа от оси на TOWER_SIDE, м
const TOWER_BORDER_FRACTION := 0.3
const TOWER_SIDE := 14.0
# ── СТАРТОВАЯ ОБОРОНА КРЕПОСТИ (числа — spawn_config) ──
const HOME_DEFENSE_ENABLED := _Spawn.AI_HOME_DEFENSE_ENABLED
const HOME_TOWERS := _Spawn.AI_HOME_TOWERS
const HOME_TOWER_ARCHERS := _Spawn.AI_HOME_TOWER_ARCHERS
const HOME_CASTLE_ARCHERS := _Spawn.AI_HOME_CASTLE_ARCHERS
const HOME_GUARD_SQUADS := _Spawn.AI_HOME_GUARD_SQUADS
const HOME_GUARD_ZONE := _Spawn.AI_HOME_GUARD_ZONE
const HOME_GUARD_WAKE_FOES := _Spawn.AI_HOME_GUARD_WAKE_FOES
const HOME_GUARD_HIT_SEC := _Spawn.AI_HOME_GUARD_HIT_SEC
const HOME_GUARD_CALM_SEC := _Spawn.AI_HOME_GUARD_CALM_SEC
const HOME_GUARD_TICK_SEC := _Spawn.AI_HOME_GUARD_TICK_SEC
const HOME_GUARD_HOME_R := _Spawn.AI_HOME_GUARD_HOME_R
const HOME_GUARD_HOME_RETRY_SEC := _Spawn.AI_HOME_GUARD_HOME_RETRY_SEC
const HOME_GUARD_GATHER_R := _Spawn.AI_HOME_GUARD_GATHER_R
const HOME_GUARD_GATHER_SEC := _Spawn.AI_HOME_GUARD_GATHER_SEC
const HOME_GUARD_HEAL_FRAC := _Spawn.AI_HOME_GUARD_HEAL_FRAC
const HOME_GUARD_WAVE_SQUADS := _Spawn.AI_HOME_GUARD_WAVE_SQUADS
const HOME_GUARD_WAVE_GAP_SEC := _Spawn.AI_HOME_GUARD_WAVE_GAP_SEC
# ── ОБОРОНА БАЗЫ В ТРИ УРОВНЯ (числа — spawn_config) ──
const HOME_RING_DIST := _Spawn.AI_HOME_RING_DIST
const HOME_RING_CLEAR := _Spawn.AI_HOME_RING_CLEAR
const HOME_LINE_DIST := _Spawn.AI_HOME_LINE_DIST
const HOME_LINE_SQUADS := _Spawn.AI_HOME_LINE_SQUADS
const HOME_LINE_ROWS := _Spawn.AI_HOME_LINE_ROWS
const HOME_LINE_GAP := _Spawn.AI_HOME_LINE_GAP
const HOME_LINE_ROW_GAP := _Spawn.AI_HOME_LINE_ROW_GAP
const HOME_TOWER_POST_DIST := _Spawn.AI_HOME_TOWER_POST_DIST
const HOME_GUARD_POST_ZONE := _Spawn.AI_HOME_GUARD_POST_ZONE
# ── ОТВЕТНЫЙ УДАР И ПОДКРЕПЛЕНИЕ (числа — spawn_config) ──
const RETALIATION_LOSSES := _Spawn.AI_RETALIATION_LOSSES
const RETALIATION_SEC := _Spawn.AI_RETALIATION_SEC
const RETALIATION_COOLDOWN_SEC := _Spawn.AI_RETALIATION_COOLDOWN_SEC
const RETALIATION_MIN_SQUADS := _Spawn.AI_RETALIATION_MIN_SQUADS
const RETALIATION_ADVANTAGE := _Spawn.AI_RETALIATION_ADVANTAGE
const RETALIATION_SCAN_R := _Spawn.AI_RETALIATION_SCAN_R
const RETALIATION_HOME_R := _Spawn.AI_RETALIATION_HOME_R
const RETALIATION_RECHECK_SEC := _Spawn.AI_RETALIATION_RECHECK_SEC
const REINFORCE_AT_SEC := _Spawn.AI_REINFORCE_AT_SEC
const REINFORCE_SQUADS := _Spawn.AI_REINFORCE_SQUADS
const REINFORCE_UNIT := _Spawn.AI_REINFORCE_UNIT
const REINFORCE_VET := _Spawn.AI_REINFORCE_VET

## Строки охраны крепости, нормализованные как start_squads()
static func home_guard_squads() -> Array:
	var out: Array = []
	for row in HOME_GUARD_SQUADS:
		var d: Dictionary = row
		var uid: String = String(d.get("unit", ""))
		if uid.is_empty() or not _UCfgRef.STATS.has(uid):
			continue
		var n: int = int(d.get("count", 0))
		if n <= 0:
			n = _UCfgRef.squad_size(uid)
		out.append({
			"unit":  uid,
			"count": maxi(n, 1),
			"vet":   maxi(int(d.get("vet", 0)), 0),
			"picks": maxi(int(d.get("picks", 0)), 0),
		})
	return out
## Рейды по экономике игрока: раз в RAID_INTERVAL_SEC один отряд бьёт рабочих и
## одиночные постройки; идёт, если свободных отрядов не меньше MIN_FIELD, а всего
## не меньше MIN_ARMY; отход в замок по сроку MAX_SEC, с, или при FLEE_FOES боевых
## игрока в FLEE_RADIUS, м; добычу ищет в HUNT_RADIUS, м
const AI_RAIDS := true
const RAID_INTERVAL_SEC := _Spawn.AI_RAID_INTERVAL_SEC
const RAID_MIN_FIELD := 1
const RAID_MIN_ARMY := 3
const RAID_MAX_SEC := 60.0
const RAID_FLEE_FOES := 12
const RAID_FLEE_RADIUS := 18.0
const RAID_HUNT_RADIUS := 60.0

## Сколько заказов найма ИИ держит в очереди здания одновременно (1 — чередой)
const MAX_QUEUED_ORDERS := 1

## Армия выбита — барак отстраивается в приоритете и бесплатно
const REBUILD_BARRACKS_FREE := true
## Ниже какого числа боевых бойцов ИИ считает армию потерянной
const ARMY_LOST_THRESHOLD := 10

# ── ТАКТИКИ ПОСТРОЕНИЯ АТАКУЮЩЕЙ ВОЛНЫ ──
## Порядок «копья — луки — фланги» во всех один; различаются глубиной и шириной:
## depth — вдоль курса (+ к игроку), flank — доля FLANK_SPREAD по обоим краям
const TACTICS := [
	{
		"id": "shield_wall", "name": "Стена щитов",
		"layout": {
			"spearman": {"depth":  0.0, "flank": 0.0},
			"archer":   {"depth": -7.0, "flank": 0.0},
			"warrior":  {"depth": -2.0, "flank": 1.0},
		},
	},
	{
		"id": "wide_front", "name": "Широкий фронт",
		"layout": {
			"spearman": {"depth":  0.0, "flank": 0.0},
			"archer":   {"depth": -9.0, "flank": 0.0},
			"warrior":  {"depth":  0.0, "flank": 1.4},
		},
	},
	{
		"id": "deep_column", "name": "Глубокая колонна",
		"layout": {
			"spearman": {"depth":  0.0, "flank": 0.0},
			"archer":   {"depth": -5.0, "flank": 0.0},
			"warrior":  {"depth": -4.0, "flank": 0.6},
		},
	},
]

## Разнос фланговых отрядов от центра волны, м (для "flank": 1.0)
const FLANK_SPREAD := 14.0

## Строй волны разворачивается к армии игрока, а не к его замку; армию ИИ
## замечает в ARMY_AIM_RADIUS, м, от волны
const AI_FACE_PLAYER_ARMY := true
const ARMY_AIM_RADIUS := 100.0

## true — тактики по кругу, false — случайно
const TACTICS_IN_ORDER := true

# ── ТАКТИКА НА УРОВНЕ ОТРЯДА (считается раз в THINK_INTERVAL, раз на отряд) ──

## ── ИССЛЕДОВАНИЯ В КУЗНИЦЕ ──
## ИИ качает древо кузницы (forge_config)
const AI_RESEARCH_FORGE := true

## Что ИИ ценит в узле древа: узел = сумма бонусов с этими весами, берётся лучший
const AI_FORGE_WEIGHTS := {
	"bonus_attack": 3.0,
	"bonus_armor":  2.5,
	"bonus_health": 1.6,
	"bonus_speed":  1.2,
	"bonus_push":   0.6,
	"bonus_morale": 0.4,
	"bonus_carry":  2.0,
	"bonus_gather": 25.0,
	"bonus_build":  6.0,
	# доли промыслов и груза рабочего (вес — за 0.10 узла)
	"bonus_gather_wood": 25.0, "bonus_gather_stone": 22.0,
	"bonus_gather_gold": 22.0, "bonus_gather_food": 18.0,
	"bonus_carry_pct": 20.0, "bonus_walk_pct": 20.0,
	"bonus_walk_loaded_pct": 18.0,
	# выход мяса с туши и темп самой кузницы (ТЗ 28.10.2026, блок 2)
	"bonus_meat_pct": 12.0, "bonus_research_pct": 16.0,
}

## Ветки, которые ИИ качает сверх нанимаемых родов (combat_types)
const AI_FORGE_EXTRA_BRANCHES := ["worker"]

## Золото, которое ИИ держит нетронутым на найм, прежде чем платить за науку
const AI_RESEARCH_GOLD_RESERVE := 300.0
## Резерв дерева под найм: после мира исследования ждут, пока на складе не
## наберётся столько дерева (в мир — не ждут)
const AI_RESEARCH_WOOD_RESERVE := 500.0

## ── СПОСОБНОСТИ-РЕЖИМЫ ОТРЯДОВ (колонка D древа) ──
## Докупать способности каждому отряду; резерв золота под докупку (отдельный)
const AI_BUY_SQUAD_ABILITIES := true
const AI_ABILITY_GOLD_RESERVE := 500.0

## ── ФЛАНГОВЫЙ ОБХОД МЕЧНИКОВ ──
## Мечники обходят чужой строй по дуге к стрелкам в тылу
const AI_WARRIOR_FLANK := true
## Насколько широко мечники обходят чужой строй, м (вбок от курса)
const FLANK_ARC_RADIUS := 24.0
## С какой дистанции до цели начинается обход, м (ближе — поздно)
const FLANK_TRIGGER_DIST := 22.0
## В каком радиусе от цели волны ищутся стрелки игрока, м
const FLANK_REACH := 55.0
## Дальность оружия, выше которой боец считается СТРЕЛКОМ, м
const RANGED_ATTACK_RANGE := 6.0

## ── КАЙТ ЛУЧНИКОВ ──
## Подошла пехота — лучники отходят за спину своих копейщиков и стреляют оттуда
const AI_ARCHER_KITE := true
## Ближе этого чужая пехота считается угрозой лучникам, м
const KITE_TRIGGER_DIST := 13.0
## На сколько м ЗА спину прикрывающего отряда отходят лучники
const KITE_BACK_DIST := 8.0

## ── ОТСТУПЛЕНИЕ ОТРЯДА В КРЕПОСТЬ ──
## Выбитый отряд уходит в замок лечиться и пополняться
const AI_SQUAD_RETREAT := true
## Доля силы отряда (живые × здоровье от полного), ниже которой он уходит
const RETREAT_STRENGTH := 0.35
## Тот же порог у опытного отряда (ранг от RETREAT_VETERAN_LEVEL)
const RETREAT_STRENGTH_VETERAN := 0.30
## Ниже этой доли силы отряд БЕЗ противника рядом идёт в замок лечиться и пополняться (ручка ai_refill_home)
const RETREAT_REFILL_STRENGTH := 0.5
## С какого уровня ветеранства отряд считается «опытным» (лычки — это 1-3)
const RETREAT_VETERAN_LEVEL := 1
## Радиус поиска угрозы, м: без противника рядом отряд не отступает
const RETREAT_THREAT_RADIUS := 26.0
## Завязался в рукопашной — дерётся до конца (отход только до и после контакта)
const AI_NO_RETREAT_IN_MELEE := true

## Запрет отхода ближе стольких м к противнику; 0 — правила нет (выключено намеренно)
const AI_NO_RETREAT_RANGE := 0.0

## ── ФАЛАНГА ──
## Сколько шеренг держит отряд копейщиков (колонки выводятся: ceil(людей / шеренг))
const PHALANX_RANKS := 4
## Копейщики держат стойку ЗАЩИТА и на марше, пока противника нет рядом
const AI_SPEAR_PHALANX_ON_MARCH := true
## Ближе этого противник — «контакт», м: копейщики в АТАКУ, лучники в кайт
const CONTACT_RADIUS := 24.0

## Решение об отходе держится столько секунд (= Unit.RETREAT_LOCK_SEC)
const RETREAT_MIN_SEC := 12.0

## ── ЗАСЛОН У БАЗЫ ──
## Гарнизон стоит строем лицом к противнику: копья впереди, стрелки за ними, мечи по краям
const AI_BASE_SCREEN := true
## Дистанции от замка по родам войск, м; разнос фланговых мечников вбок, м
const SCREEN_SPEAR_DIST := 13.0
const SCREEN_BOW_DIST   := 7.0
const SCREEN_FLANK_DIST := 10.0
const SCREEN_FLANK_SIDE := 12.0
## Просвет между соседними отрядами заслона, м (ширина фронта выводится)
const SCREEN_SQUAD_GAP := 2.2
## Сколько м фронта под одну линию заслона; не поместившиеся — во второй эшелон
const SCREEN_MAX_WIDTH := 64.0
## Насколько второй эшелон стоит позади первого, м
const SCREEN_ROW_DEPTH := 7.0

# ── ХЕЛПЕРЫ ──

## Сколько отрядов данного рода нужно ИИ (0 — род не нанимается вовсе)
static func squad_limit(unit_id: String) -> int:
	return int(SQUAD_LIMIT.get(unit_id, 0))

## Боевые рода в порядке приоритета найма
static func combat_types() -> Array:
	var out: Array = []
	for key in SQUAD_LIMIT:
		var uid: String = String(key)
		if squad_limit(uid) > 0:
			out.append(uid)
	return out

## Всего отрядов в полной армии — по этому числу ИИ решает, что пора в атаку
static func total_squad_limit() -> int:
	var n := 0
	for key in SQUAD_LIMIT:
		n += squad_limit(String(key))
	return n

## Полный лимит армии В БОЙЦАХ (для доли RECAP_ARMY_FRACTION)
static func total_army_cap() -> int:
	var n := 0
	for key in SQUAD_LIMIT:
		var uid: String = String(key)
		n += squad_limit(uid) * _UCfgRef.squad_size(uid)
	return n

## Тактика по индексу волны
static func tactic_for_wave(wave_index: int) -> Dictionary:
	if TACTICS.is_empty():
		return {}
	if TACTICS_IN_ORDER:
		return TACTICS[wave_index % TACTICS.size()]
	return TACTICS[randi() % TACTICS.size()]

## Смещение рода внутри тактики: course — единичный курс атаки в XZ, side — ±1 край фланга
static func tactic_offset(tactic: Dictionary, unit_id: String, course: Vector3, side: float) -> Vector3:
	var layout: Dictionary = tactic.get("layout", {})
	var d: Dictionary = layout.get(unit_id, {})
	var depth: float = d.get("depth", 0.0)
	var flank: float = d.get("flank", 0.0)
	var right := Vector3(-course.z, 0.0, course.x)
	return course * depth + right * (flank * FLANK_SPREAD * side)

# ── СЦЕНАРИЙ ГЛОБАЛЬНОГО ИИ КАРТЫ (RedAI.gd) ──
## Доля армии на стычки вне баз (вылазка + рейд) в мирную фазу
const SORTIE_ARMY_FRACTION := 0.30
## Периметр базы: пары копейщики/лучники у башен — копья впереди на SPEAR_AHEAD,
## луки позади на BOW_BEHIND, пары разнесены вдоль фронта башни на SIDE, м
const AI_TOWER_PERIMETER := true
const PERIMETER_SPEAR_AHEAD := 6.0
const PERIMETER_BOW_BEHIND := 4.0
const PERIMETER_SIDE := 7.0
## Борьба за брод: рудник у брода — первая цель; группа SPEAR + ARCHER отрядов,
## формируется при армии не меньше FORD_MIN_SQUADS тактических отрядов
const AI_FORD_FIRST := true
const FORD_SPEAR_SQUADS := 3
const FORD_ARCHER_SQUADS := 1
const FORD_MIN_SQUADS := 6
## Копейщики группы на марше — широко (столько шеренг), ближе DEEP_RANGE, м, к броду — PHALANX_RANKS
const PHALANX_RANKS_MARCH := 2
const FORD_DEEP_RANGE := 45.0
## Вылазки на троллей ради опыта: раз в INTERVAL, не раньше FIRST_SEC, не дольше
## MAX_SEC; запас ниже RETREAT_STRENGTH — в замок лечиться
const AI_TROLL_HUNT := true
const HUNT_INTERVAL_SEC := 120.0
const HUNT_FIRST_SEC := 240.0
const HUNT_MAX_SEC := 90.0
const HUNT_RETREAT_STRENGTH := 0.5
## Разведка боем 2 : 1: каждый RECON_EVERY-й рейд — чистая разведка на RECON_DEPTH м
## от базы игрока; «дошёл» — ближе RECON_ARRIVE, м
const RECON_EVERY := 3
const RECON_DEPTH := 30.0
const RECON_ARRIVE := 14.0

# ── ЭКОНОМИКА КРАСНОГО v2 (ТЗ 30.10.2026, ручка ai_eco_v2, scripts/ai/RedEconomy.gd) ──
## Потолок рабочих: множитель к AI_WORKER_LIMIT; до ECO_WORKER_TARGET — найм в приоритете
const ECO_WORKER_LIMIT_MULT := 1.5
const ECO_WORKER_TARGET := 28
## Загоны у базы и фермеров на загон (мясо — второй источник еды после домов)
const ECO_PENS := 2
const ECO_FARMERS_PER_PEN := 3
## Склады у дальних делянок: рабочий дальше ECO_STORE_FAR_M от точки сдачи — повод для склада
const ECO_STOREHOUSES := 2
const ECO_STORE_FAR_M := 28.0
const ECO_STORE_MIN_WORKERS := 3
## Рынок: держать еду не ниже FOOD_TARGET, платить излишком сверх KEEP (дерево/золото/камень)
const ECO_FOOD_TARGET := 700.0
const ECO_TRADE_KEEP := {0: 1500.0, 1: 900.0, 2: 600.0}
const ECO_TRADE_EVERY_SEC := 6.0
## Камень сверх этого уходит в золото (кузница и рыцари платят золотом)
const ECO_STONE_SURPLUS := 4000.0

# ── ТАКТИКА КРАСНОГО (ТЗ 30.10.2026, scripts/ai/RedTactics.gd) ──
## Перегруппировка: отряды в RG_CLUSTER_R, м, — одна группа; бой был за RG_RECENT_SEC, тихо RG_QUIET_SEC
## и врагов нет в RG_SCAN_R, м, — сбор строем-кирпичом у медианы; не дольше RG_MAX_SEC
const RG_CLUSTER_R := 40.0
const RG_RECENT_SEC := 30.0
const RG_QUIET_SEC := 4.0
const RG_SCAN_R := 26.0
const RG_MAX_SEC := 22.0
## Отряд встал: центр в RG_ARRIVE_M от места и в покое не меньше RG_IDLE_FRAC бойцов
const RG_ARRIVE_M := 3.5
const RG_IDLE_FRAC := 0.7
## Зазор между рядами кирпичей корпуса, м
const RG_ROW_GAP := 3.0
## Корпус: стычка дальше CORPS_MIN_DIST, м, от рубежа и ближе CORPS_REACH — заслон встаёт
## кирпичами 2×N в CORPS_STANDOFF, м, перед ней на CORPS_HOLD_SEC; с поста срывается на врага ближе CORPS_ENGAGE_R
const CORPS_MIN_DIST := 25.0
const CORPS_REACH := 90.0
const CORPS_STANDOFF := 12.0
const CORPS_HOLD_SEC := 30.0
const CORPS_ENGAGE_R := 16.0
## Клещи штурма: волна от PINCER_MIN отрядов — по PINCER_SHARE на каждое крыло; крыло бежит
## на PINCER_WIDE, м, вбок от середины чужого фронта (на PINCER_BACK позади него), затем в тыл на PINCER_DEEP
const PINCER_MIN := 6
const PINCER_SHARE := 0.2
const PINCER_WIDE := 30.0
const PINCER_BACK := 10.0
const PINCER_DEEP := 12.0
const PINCER_STAGE_M := 12.0
const PINCER_WING_GAP := 12.0   ## разнос крыльев одной стороны, м
## Опорная точка: группа брода/рудника простояла у цели SP_HOLD_SEC — вышка в SP_BEHIND, м, за линией
## и лучники на неё; вышек опорных точек не больше SP_TOWERS
const SP_HOLD_SEC := 20.0
const SP_NEAR_M := 16.0
const SP_BEHIND := 9.0
const SP_TOWERS := 2
