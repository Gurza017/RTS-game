extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ЭКОНОМИЧЕСКАЯ МОДЕЛЬ ПАРТИИ НА 90 МИНУТ (ТЗ 24.09.2026, «партия перед сном»)
## ═══════════════════════════════════════════════════════════════════════════
## ЗДЕСЬ НЕТ НИ ОДНОЙ ЦЕНЫ И НИ ОДНОГО ТЕМПА ДОБЫЧИ. Цены берутся из
## unit_stats_config (TRAINING, BUILDINGS) и forge_config (древо с множителем
## ряда), темп — из статов рабочего. Модель хранит только ЦЕЛИ ЗАКАЗА (сколько
## длится партия, сколько отрядов на поле, доля кузницы) и допущения о ходе
## партии (как быстро растёт бригада, армия, дома). Правка цены здания или
## отряда доезжает до матрицы сама — стенд qa_economy90 её и печатает.
##
## ФОРМУЛА ЗАКАЗА:
##   нужно_в_минуту(р) = бюджет(р) / 90 мин
##   бюджет(р) = отряды(80) + постройки + наём рабочих + содержание
##               + доля кузницы (65 %) − стартовый банк − пассивный приход
##   рабочих(р) = ⌈ бюджет(р) / (темп(р) × КПД × прирост_кузницы × рабоче-минуты) ⌉
## КПД (WORKER_EFFICIENCY) — потери на толчею, дальние жилы и переходы между
## деревьями; прирост кузницы — средний за партию выигрыш ветки рабочего,
## он СЧИТАЕТСЯ из самих узлов древа (econ_gain), а не задан числом.

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

# ── ЦЕЛИ ЗАКАЗА ─────────────────────────────────────────────────────────────
const SESSION_MIN := 90.0
## Отрядов на поле одновременно и сколько раз армия «переворачивается» потерями
const ARMY_SQUADS_ON_FIELD := 40
const LOSS_FACTOR := 2.0
## Состав армии (доли отрядов): пехота строя, стрелки, мечники
const ARMY_MIX := {"spearman": 0.50, "archer": 0.30, "warrior": 0.20}
## Где нанимается род (для цены)
const ARMY_BUILDING := {"spearman": "barracks", "archer": "archery", "warrior": "barracks"}
## Доля кузницы, которую партия ОБЯЗАНА успевать (по стоимости), и потолок,
## выше которого бригада, кормящая эту партию, НЕ дотягивается
const FORGE_TARGET_SHARE := 0.65
const FORGE_UNREACHABLE_MARGIN := 1.15   # 100 % дороже возможного хотя бы в 1.15 раза

# ── ХОД ПАРТИИ (допущения модели) ───────────────────────────────────────────
## Бригада растёт от стартовой до целевой за RAMP_MIN минут
const START_WORKERS := 5
const RAMP_MIN := 15.0
## Армия: первые отряды с ARMY_START_MIN, полный состав к ARMY_FULL_MIN
const ARMY_START_MIN := 8.0
const ARMY_FULL_MIN := 45.0
## Постройки партии (сверх стартового замка). Бараки и стрелковая дорожают
## линейно, загон — своим законом: цена считается building_cost_scaled
const BUILD_PLAN := {"house": 40, "barracks": 3, "archery": 2, "tower": 6,
	"sheep_pen": 3, "smithy": 1}
## Дома растут вместе с армией (лимит бойцов): от стартовых до плана к ARMY_FULL_MIN
const START_HOUSES := 3
## Рабочих за партию гибнет и нанимается заново (доля бригады)
const WORKER_LOSS_SHARE := 0.25
## Плечо «жила ↔ склад» — то же, что у приточной подписи HUD (Worker.INCOME_NOMINAL_ARM)
const NOMINAL_ARM := 12.0
## КПД бригады: толчея у склада, дальние жилы, переходы между деревьями
const WORKER_EFFICIENCY := 0.85
## Ветка рабочего: к какой минуте изучены ряды 1..ECON_ROWS (и с этой минуты
## действует её прирост)
const ECON_ROWS := 3
const ECON_READY_MIN := 20.0

# ── ТЕМП «ЗНАЧИМОГО ДЕЙСТВИЯ» ───────────────────────────────────────────────
## Раз в сколько минут игрок обязан быть в состоянии что-то купить
const ACTION_EVERY_MIN_MAX := 3.0
## Ряд кузницы → к какой минуте ОДИН его узел доступен по золоту
const FORGE_ROW_BY_MIN := {1: 5.0, 2: 15.0}
## Доля золотого притока, которую игрок отдаёт кузнице (остальное — войска)
const FORGE_GOLD_SHARE := 0.5
## «Элитный» ряд стоит не меньше стольких отрядов копейщиков за узел
const ELITE_ROW := 4
const ELITE_MIN_SQUADS := 3.0
## Потолок «закрыть нужду в камне»: самый дорогой по камню узел или постройка
const STONE_CLOSE_MIN_MAX := 4.0

# ── РУДНИК: ВОЛНЫ ПОСЛЕ ЗАХВАТА ─────────────────────────────────────────────
const MINE_WAVE_INTERVAL_SEC := 240.0
const MINE_WAVE_SQUADS_START := 0.5
const MINE_WAVE_SQUADS_LATE := 2.0
const MINE_WAVE_LATE_MIN := 45.0

## Размер волны на захваченный рудник в ОТРЯДАХ (дробный: 0.5 — полотряда)
static func mine_wave_squads(clock_sec: float) -> float:
	var t: float = clampf(clock_sec / (MINE_WAVE_LATE_MIN * 60.0), 0.0, 1.0)
	return lerpf(MINE_WAVE_SQUADS_START, MINE_WAVE_SQUADS_LATE, t)

const RES := [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
	Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]

static func res_name(r: int) -> String:
	match r:
		Constants.RESOURCE_WOOD: return "Wood"
		Constants.RESOURCE_GOLD: return "Gold"
		Constants.RESOURCE_STONE: return "Stone"
		Constants.RESOURCE_FOOD: return "Food"
	return "?"

static func _zero() -> Dictionary:
	var d := {}
	for r in RES:
		d[r] = 0.0
	return d

static func _add(acc: Dictionary, cost: Dictionary, k: float = 1.0) -> void:
	for r in cost.keys():
		acc[r] = float(acc.get(r, 0.0)) + float(cost[r]) * k

## ── БЮДЖЕТ ПО СТАТЬЯМ ──────────────────────────────────────────────────────
static func army_squads_total() -> float:
	return float(ARMY_SQUADS_ON_FIELD) * LOSS_FACTOR

static func squad_cost(unit_id: String) -> Dictionary:
	return _UCfg.train_cost(String(ARMY_BUILDING.get(unit_id, "barracks")), unit_id)

## Средняя цена отряда по составу армии
static func mean_squad_cost() -> Dictionary:
	var acc := _zero()
	for u in ARMY_MIX.keys():
		_add(acc, squad_cost(String(u)), float(ARMY_MIX[u]))
	return acc

static func army_cost() -> Dictionary:
	var acc := _zero()
	_add(acc, mean_squad_cost(), army_squads_total())
	return acc

static func buildings_cost() -> Dictionary:
	var acc := _zero()
	for b in BUILD_PLAN.keys():
		var n: int = int(BUILD_PLAN[b])
		var existing0: int = START_HOUSES if String(b) == "house" else 0
		for i in range(n - (existing0 if String(b) == "house" else 0)):
			_add(acc, _UCfg.building_cost_scaled(String(b), existing0 + i))
	return acc

static func forge_cost_full() -> Dictionary:
	var acc := _zero()
	for n in _Forge.all_nodes():
		var d: Dictionary = n
		_add(acc, {Constants.RESOURCE_WOOD: float(d.get("cost_wood", 0.0)),
			Constants.RESOURCE_GOLD: float(d.get("cost_gold", 0.0)),
			Constants.RESOURCE_STONE: float(d.get("cost_stone", 0.0)),
			Constants.RESOURCE_FOOD: float(d.get("cost_food", 0.0))})
	return acc

static func forge_cost(share: float) -> Dictionary:
	var acc := _zero()
	_add(acc, forge_cost_full(), share)
	return acc

static func target_workers() -> Dictionary:
	return recommended_workers()

## Средняя бригада за партию при целевом составе N: рост 5 → N за RAMP_MIN
static func worker_minutes(n: float) -> float:
	var ramp: float = RAMP_MIN * (float(START_WORKERS) + n) * 0.5
	return ramp + (SESSION_MIN - RAMP_MIN) * n

## Средняя армия (отрядов) за партию
static func army_squad_minutes() -> float:
	var s: float = float(ARMY_SQUADS_ON_FIELD)
	return (ARMY_FULL_MIN - ARMY_START_MIN) * s * 0.5 + (SESSION_MIN - ARMY_FULL_MIN) * s

static func house_minutes() -> float:
	var h1: float = float(BUILD_PLAN["house"])
	var h0: float = float(START_HOUSES)
	return ARMY_FULL_MIN * (h0 + h1) * 0.5 + (SESSION_MIN - ARMY_FULL_MIN) * h1

## Наём рабочих и содержание (еда) при бригаде в total_workers человек
static func upkeep_cost(total_workers: float) -> Dictionary:
	var acc := _zero()
	var hire: Dictionary = _UCfg.train_cost("castle", "worker")
	var hires: float = maxf(total_workers - float(START_WORKERS), 0.0) \
		+ total_workers * WORKER_LOSS_SHARE
	_add(acc, hire, hires)
	acc[Constants.RESOURCE_FOOD] = float(acc[Constants.RESOURCE_FOOD]) \
		+ army_squad_minutes() * 60.0 * _UCfg.FOOD_UPKEEP_SQUAD_PER_SEC \
		+ worker_minutes(total_workers) * 60.0 * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC
	return acc

## Полный бюджет партии при доле кузницы share и бригаде total_workers
static func session_budget(share: float, total_workers: float) -> Dictionary:
	var acc := _zero()
	_add(acc, army_cost())
	_add(acc, buildings_cost())
	_add(acc, forge_cost(share))
	_add(acc, upkeep_cost(total_workers))
	return acc

## Пассивный приход: дома (еда)
static func passive_income() -> Dictionary:
	var acc := _zero()
	acc[Constants.RESOURCE_FOOD] = house_minutes() * 60.0 \
		* _UCfg.HOUSE_FOOD_INCOME / _UCfg.HOUSE_FOOD_INTERVAL
	return acc

## ── ТЕМП ОДНОГО РАБОЧЕГО ───────────────────────────────────────────────────
## Единиц в секунду на плече NOMINAL_ARM. Бонусы — доли, как в Worker:
## gather (доля долой с цикла), carry (доля к грузу), walk_loaded (к ходу с ношей)
static func worker_rate(res: int, gather_pct: float = 0.0, carry_pct: float = 0.0,
		walk_loaded_pct: float = 0.0) -> float:
	if res == Constants.RESOURCE_FOOD:
		return _UCfg.MEAT_PER_SEC_TARGET
	var cyc: float = _UCfg.stat("worker", "gather_time", 5.0) * _UCfg.gather_time_mult(res)
	cyc *= 1.0 - minf(gather_pct, _UCfg.GATHER_PCT_CAP)
	var ve: float = _UCfg.stat("worker", "walk_speed_empty", 3.2)
	var vl: float = _UCfg.stat("worker", "walk_speed_loaded", 2.2) * (1.0 + walk_loaded_pct)
	var trip: float = NOMINAL_ARM / ve + NOMINAL_ARM / vl
	var carry: float = _UCfg.stat("worker", "gather_amount", 10.0) * (1.0 + carry_pct)
	return carry / maxf(cyc + trip, 0.5)

## Сумма бонусов ветки рабочего по рядам 1..rows
static func econ_bonuses(rows: int) -> Dictionary:
	var out := {}
	for n in _Forge.tree("worker"):
		var d: Dictionary = n
		if int(d["row"]) > rows:
			continue
		for k in d.keys():
			var key: String = String(k)
			if key.begins_with("bonus_"):
				out[key] = float(out.get(key, 0.0)) + float(d[k])
	return out

## Прирост темпа от рядов 1..ECON_ROWS ветки рабочего (множитель, ≥ 1)
static func econ_gain(res: int) -> float:
	if res == Constants.RESOURCE_FOOD:
		return 1.0
	var b: Dictionary = econ_bonuses(ECON_ROWS)
	var gk: String = String(_UCfg.GATHER_BONUS_KEY.get(res, ""))
	var with: float = worker_rate(res, float(b.get(gk, 0.0)), float(b.get("bonus_carry_pct", 0.0)),
		float(b.get("bonus_walk_loaded_pct", 0.0)))
	return with / maxf(worker_rate(res), 0.0001)

## Средний за партию множитель: прирост действует с ECON_READY_MIN
static func econ_gain_avg(res: int) -> float:
	var g: float = econ_gain(res)
	return 1.0 + (g - 1.0) * (SESSION_MIN - ECON_READY_MIN) / SESSION_MIN

## Единиц в минуту с одного рабочего «на деле» (КПД и средний прирост кузницы)
static func worker_per_min_effective(res: int) -> float:
	return worker_rate(res) * 60.0 * WORKER_EFFICIENCY * econ_gain_avg(res)

## ── РЕКОМЕНДУЕМАЯ БРИГАДА ─────────────────────────────────────────────────
## Сколько рабочих на каждом ресурсе закрывают бюджет партии с долей кузницы
## share. Еда зависит от размера бригады (содержание), поэтому считается
## последовательными приближениями — три прохода сходятся с запасом
static func workers_for(share: float) -> Dictionary:
	var out := {}
	var total: float = 40.0
	for _pass in range(4):
		var bud: Dictionary = session_budget(share, total)
		var start: Dictionary = _UCfg.starting_resources(Constants.FACTION_PLAYER)
		var pas: Dictionary = passive_income()
		total = 0.0
		for r in RES:
			var need: float = float(bud[r]) - float(start.get(r, 0.0)) - float(pas.get(r, 0.0))
			# Рабоче-минуты одного места бригады: место набирается за RAMP_MIN
			var per_slot: float = worker_per_min_effective(r) * (SESSION_MIN - RAMP_MIN * 0.5)
			var n: int = int(ceil(maxf(need, 0.0) / maxf(per_slot, 0.001)))
			out[r] = n
			total += float(n)
	return out

static func recommended_workers() -> Dictionary:
	return workers_for(FORGE_TARGET_SHARE)

static func workers_total(w: Dictionary) -> int:
	var n := 0
	for r in w.keys():
		n += int(w[r])
	return n

## Сколько ресурса за партию приносит бригада w (без стартового банка)
static func session_income(w: Dictionary) -> Dictionary:
	var acc := _zero()
	for r in RES:
		acc[r] = float(w.get(r, 0)) * worker_per_min_effective(r) * (SESSION_MIN - RAMP_MIN * 0.5)
	_add(acc, passive_income())
	_add(acc, _UCfg.starting_resources(Constants.FACTION_PLAYER))
	return acc

## ── ТЕМП ДЕЙСТВИЙ ─────────────────────────────────────────────────────────
## Минута, к которой ОДИН узел ряда row доступен по золоту: золотые рабочие
## растут вместе с бригадой, кузнице идёт FORGE_GOLD_SHARE их притока
static func forge_row_minute(row: int, w: Dictionary) -> float:
	var node_gold: float = 0.0
	for n in _Forge.tree("spearman"):
		var d: Dictionary = n
		if int(d["row"]) == row:
			node_gold = maxf(node_gold, float(d.get("cost_gold", 0.0)))
	var g_full: float = float(w.get(Constants.RESOURCE_GOLD, 0)) \
		* worker_rate(Constants.RESOURCE_GOLD) * 60.0 * WORKER_EFFICIENCY * FORGE_GOLD_SHARE
	var g0: float = g_full * float(START_WORKERS) / maxf(float(workers_total(w)), 1.0)
	# Накопленное к минуте t при линейном росте от g0 до g_full за RAMP_MIN
	var t := 0.0
	var acc := 0.0
	while acc < node_gold and t < SESSION_MIN:
		var k: float = clampf(t / RAMP_MIN, 0.0, 1.0)
		acc += lerpf(g0, g_full, k) * 0.1
		t += 0.1
	return t
