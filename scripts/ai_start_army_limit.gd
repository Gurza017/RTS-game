extends RefCounted
## КРАСНЫЙ ИИ: лимиты, тактики, отход, рейды, башни, кузница.
## Только параметры. Спавн и тайминги — scripts/spawn_config.gd; снятые пояснения — docs/CONFIG_NOTES_2026-09-14.md

const _UCfgRef := preload("res://scripts/unit_stats_config.gd")
const _Spawn := preload("res://scripts/spawn_config.gd")
## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

## Сколько ОТРЯДОВ каждого типа ИИ доводит до строя.
const SQUAD_LIMIT := _Spawn.AI_SQUAD_LIMIT

## Сколько рабочих ИИ держит на экономике (потолок).
const WORKER_LIMIT := _Spawn.AI_WORKER_LIMIT

## Сколько рабочих ИИ выводит на карту в первую секунду партии.
const START_WORKERS := _Spawn.AI_START_WORKERS

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# 1а. СТАРТОВЫЕ ОТРЯДЫ ИИ: СОСТАВ И РАНГ ПРИ РОЖДЕНИИ
const START_SQUADS := _Spawn.AI_START_SQUADS

const START_VETERAN_PREFERENCE := ["bonus_attack", "bonus_health",
	"bonus_defense", "bonus_armor", "bonus_speed"]

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

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

## Сколько отрядов КАЖДОГО типа остаётся в боевой позиции у замка.
const HOME_GUARD_PER_TYPE := 7

const SEND_SURPLUS_TO_LAKE := true

## Точка сбора «в поле». Vector3.INF-подобного значения нет, поэтому
const USE_LAKE_AS_RALLY := true
const RALLY_POINT_OVERRIDE := Vector3(0.0, 0.0, 0.0)

## Радиус вокруг точки сбора, внутри которого ИИ считает, что «бой у озера идёт».
const LAKE_CONTEST_RADIUS := 26.0

## Если у озера не осталось боевых юнитов игрока, а свои там есть —
const PUSH_BASE_AFTER_LAKE_WIN := true

## ── ВОЛНА ВЫХОДИТ ЦЕЛИКОМ, А НЕ ПО ОДНОМУ ──────────────────────────────────
const AI_MUSTER_BEFORE_ATTACK := true
## Какая доля отрядов волны должна дойти до точки сбора
const MUSTER_FRACTION := 0.75
## Радиус точки сбора, м
const MUSTER_RADIUS := 26.0

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

const DEFENSIVE_MODE := true

## Какую долю карты ИИ считает своей: 0.5 — ровно половина, до центра (озера).
const MAP_CONTROL_FRACTION := 0.5

## Ширина рубежа обороны, метры: по ней раскладываются отряды-заслоны
const DEFENSE_LINE_WIDTH := 44.0

const DEFENSE_ENGAGE_RADIUS := 30.0

## ПАТРУЛИ: сколько отрядов ходит по своей территории вместо стояния на месте
const PATROL_SQUADS := 5
## Радиус патрульного круга вокруг рубежа, метры
const PATROL_RADIUS := 16.0
## Сколько секунд отряд стоит на патрульной точке, прежде чем идти к следующей
const PATROL_DWELL := 12.0

const AI_COUNTER_ATTACK := true

## ── ОТВОЕВАТЬ ЦЕНТР (RECAP CENTER) ──────────────────────────────────────────
const AI_RECAP_CENTER := true

## С какой доли полного лимита армии ИИ считает, что накопил на наступление.
const RECAP_ARMY_FRACTION := 0.8

const RECAP_ABORT_FRACTION := 0.45

## Сколько отрядов каждого рода остаётся дома, пока армия отбивает центр
const RECAP_HOME_GUARD := 1

const AI_AUTO_VETERAN := true
const AI_VETERAN_PREFERENCE := ["attack", "armor", "health", "defense", "speed"]

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

## Мирная фаза: сколько секунд ИИ вообще не воюет и только строит экономику.
const PEACE_SECONDS := 600.0

## Как часто думает ИИ (сек). Меньше — резвее реакция, дороже по процессору.
const THINK_INTERVAL := 2.0

# ── ГЛАВНЫЙ ЦИКЛ ИИ ЛЮДЕЙ (спринт 17) ───────────────────────────────────────
const AI_ASSAULT_AT_SEC := _Spawn.AI_ASSAULT_AT_SEC
const AI_TRUCE_SEC := _Spawn.AI_TRUCE_SEC
const AI_CAPTURE_MINES := true
const MINE_SQUADS := _Spawn.AI_MINE_SQUADS
const AI_BUILD_TOWERS := true
const AI_TOWERS := _Spawn.AI_TOWERS
const TOWER_BORDER_FRACTION := 0.3
const TOWER_SIDE := 14.0
# ── СТАРТОВАЯ ОБОРОНА КРЕПОСТИ (15.09.2026, см. spawn_config) ──────────────
const HOME_DEFENSE_ENABLED := _Spawn.AI_HOME_DEFENSE_ENABLED
const HOME_TOWERS := _Spawn.AI_HOME_TOWERS
const HOME_TOWER_ARCHERS := _Spawn.AI_HOME_TOWER_ARCHERS
const HOME_CASTLE_ARCHERS := _Spawn.AI_HOME_CASTLE_ARCHERS
const HOME_GUARD_SQUADS := _Spawn.AI_HOME_GUARD_SQUADS
const HOME_GUARD_DEPTH := _Spawn.AI_HOME_GUARD_DEPTH
const HOME_GUARD_GAP := _Spawn.AI_HOME_GUARD_GAP
const HOME_GUARD_ZONE := _Spawn.AI_HOME_GUARD_ZONE
const HOME_GUARD_WAKE_FOES := _Spawn.AI_HOME_GUARD_WAKE_FOES
const HOME_GUARD_HIT_SEC := _Spawn.AI_HOME_GUARD_HIT_SEC
const HOME_GUARD_CALM_SEC := _Spawn.AI_HOME_GUARD_CALM_SEC
const HOME_GUARD_TICK_SEC := _Spawn.AI_HOME_GUARD_TICK_SEC
const HOME_GUARD_HOME_R := _Spawn.AI_HOME_GUARD_HOME_R
const HOME_GUARD_HEAL_FRAC := _Spawn.AI_HOME_GUARD_HEAL_FRAC

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
const AI_RAIDS := true
const RAID_INTERVAL_SEC := _Spawn.AI_RAID_INTERVAL_SEC
const RAID_MIN_FIELD := 1
const RAID_MIN_ARMY := 3
const RAID_MAX_SEC := 60.0
const RAID_FLEE_FOES := 12
const RAID_FLEE_RADIUS := 18.0
const RAID_HUNT_RADIUS := 60.0

## Сколько заказов найма ИИ держит в очереди здания одновременно.
const MAX_QUEUED_ORDERS := 1

const REBUILD_BARRACKS_FREE := true
## Ниже какого числа боевых юнитов ИИ считает армию потерянной
const ARMY_LOST_THRESHOLD := 10

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
## ── БОЕВОЙ ПОРЯДОК ОДИН ДЛЯ ВСЕХ ТАКТИК (заказ владельца, авг. 2026) ────────
# 4. ТАКТИКИ ПОСТРОЕНИЯ АТАКУЮЩЕЙ ВОЛНЫ
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

## Разнос фланговых отрядов от центра волны, метры (для "flank": 1.0)
const FLANK_SPREAD := 14.0

## ── ФРОНТОМ К АРМИИ, А НЕ К ЗДАНИЮ ──────────────────────────────────────────
const AI_FACE_PLAYER_ARMY := true
## На каком расстоянии от волны ИИ вообще замечает армию игрока, метры
const ARMY_AIM_RADIUS := 100.0

const TACTICS_IN_ORDER := true

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

## ── ИССЛЕДОВАНИЯ В КУЗНИЦЕ ──────────────────────────────────────────────────
const AI_RESEARCH_FORGE := true

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
}

const AI_FORGE_EXTRA_BRANCHES := ["worker"]

const AI_RESEARCH_GOLD_RESERVE := 300.0

## ── СПОСОБНОСТИ-РЕЖИМЫ ОТРЯДОВ (колонка D древа) ────────────────────────────
const AI_BUY_SQUAD_ABILITIES := true
const AI_ABILITY_GOLD_RESERVE := 500.0

## ── ФЛАНГОВЫЙ ОБХОД МЕЧНИКОВ ────────────────────────────────────────────────
## Мечник в лоб на строй копейщиков — это размен, который ИИ всегда проигрывает.
const AI_WARRIOR_FLANK := true
## Насколько широко мечники обходят чужой строй, метры (вбок от курса)
const FLANK_ARC_RADIUS := 24.0
## С какой дистанции до цели начинается обход. Ближе — уже поздно обходить
const FLANK_TRIGGER_DIST := 22.0
## В каком радиусе от цели волны ищутся стрелки игрока
const FLANK_REACH := 55.0
const RANGED_ATTACK_RANGE := 6.0

## ── КАЙТ ЛУЧНИКОВ ───────────────────────────────────────────────────────────
const AI_ARCHER_KITE := true
## Ближе этого чужая пехота считается угрозой лучникам, метры
const KITE_TRIGGER_DIST := 13.0
## На сколько метров ЗА спину прикрывающего отряда отходят лучники
const KITE_BACK_DIST := 8.0

## ── ОТСТУПЛЕНИЕ ОТРЯДА В КРЕПОСТЬ ───────────────────────────────────────────
const AI_SQUAD_RETREAT := true
const RETREAT_STRENGTH := 0.35
## ── ВЕТЕРАНОВ ИИ БЕРЕЖЁТ РАНЬШЕ, ЧЕМ НОВОБРАНЦЕВ ────────────────────────────
const RETREAT_STRENGTH_VETERAN := 0.30
## С какого уровня ветеранства отряд считается «опытным» (лычки — это 1-3)
const RETREAT_VETERAN_LEVEL := 1
const RETREAT_THREAT_RADIUS := 26.0
const AI_NO_RETREAT_IN_MELEE := true

## ── РЕШЕНИЕ ОБ АТАКЕ НЕ ОТМЕНЯЕТСЯ У САМОГО ПРОТИВНИКА ─────────────────────
## ── ПРАВИЛО ЗАВЕДЕНО, НО ВЫКЛЮЧЕНО, И ЭТО НЕ ЛЕНЬ ──────────────────────────
const AI_NO_RETREAT_RANGE := 0.0

## ── ФАЛАНГА ─────────────────────────────────────────────────────────────────
const PHALANX_RANKS := 4
## Копейщики держат стойку ЗАЩИТА и на марше, пока противника нет рядом:
const AI_SPEAR_PHALANX_ON_MARCH := true
const CONTACT_RADIUS := 24.0

## ── ОТСТУПЛЕНИЕ ФИКСИРУЕТСЯ ПО ВРЕМЕНИ ─────────────────────────────────────
const RETREAT_MIN_SEC := 12.0

## ── ЗАСЛОН У БАЗЫ ───────────────────────────────────────────────────────────
## Гарнизон встаёт не кольцом вокруг замка, а строем ЛИЦОМ к противнику:
const AI_BASE_SCREEN := true
## Дистанции от замка по родам войск, метры
const SCREEN_SPEAR_DIST := 13.0
const SCREEN_BOW_DIST   := 7.0
const SCREEN_FLANK_DIST := 10.0
const SCREEN_FLANK_SIDE := 12.0
## ── ШИРИНА ЗАСЛОНА ЗАДАЁТСЯ НЕ ЧИСЛОМ, А ШАГОМ МЕЖДУ ОТРЯДАМИ ─────────────
const SCREEN_SQUAD_GAP := 2.2
const SCREEN_MAX_WIDTH := 64.0
## Насколько второй эшелон стоит позади первого, метры
const SCREEN_ROW_DEPTH := 7.0

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

## Сколько отрядов данного типа нужно ИИ (0 — тип не нанимается вовсе)
static func squad_limit(unit_id: String) -> int:
	return int(SQUAD_LIMIT.get(unit_id, 0))

## Боевые типы в порядке приоритета найма
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

## Смещение типа юнита внутри выбранной тактики.
static func tactic_offset(tactic: Dictionary, unit_id: String, course: Vector3, side: float) -> Vector3:
	var layout: Dictionary = tactic.get("layout", {})
	var d: Dictionary = layout.get(unit_id, {})
	var depth: float = d.get("depth", 0.0)
	var flank: float = d.get("flank", 0.0)
	var right := Vector3(-course.z, 0.0, course.x)
	return course * depth + right * (flank * FLANK_SPREAD * side)

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# СЦЕНАРИЙ ГЛОБАЛЬНОГО ИИ КАРТЫ (заказ владельца, 13.09.2026) — RedAI.gd
const SORTIE_ARMY_FRACTION := 0.30
const AI_TOWER_PERIMETER := true
const PERIMETER_SPEAR_AHEAD := 6.0
const PERIMETER_BOW_BEHIND := 4.0
const PERIMETER_SIDE := 7.0
const AI_FORD_FIRST := true
const FORD_SPEAR_SQUADS := 3
const FORD_ARCHER_SQUADS := 1
const FORD_MIN_SQUADS := 6
const PHALANX_RANKS_MARCH := 2
const FORD_DEEP_RANGE := 45.0
const AI_TROLL_HUNT := true
const HUNT_INTERVAL_SEC := 120.0
## Первая вылазка не раньше этой секунды: сперва экономика и башни
const HUNT_FIRST_SEC := 240.0
const HUNT_MAX_SEC := 90.0
const HUNT_RETREAT_STRENGTH := 0.5
const RECON_EVERY := 3
const RECON_DEPTH := 30.0
const RECON_ARRIVE := 14.0
