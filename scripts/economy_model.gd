extends RefCounted
## МОДЕЛЬ ПАРТИИ НА 90 МИНУТ: цели заказа и допущения о ходе партии. Цен и темпов здесь нет —
## они берутся из unit_stats_config и forge_config. Заметки — docs/config_notes/economy_model.md

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

# ── ЦЕЛИ ЗАКАЗА ──
## Длительность партии, мин
const SESSION_MIN := 90.0
## Отрядов на поле одновременно и во сколько раз потери «переворачивают» армию за партию
const ARMY_SQUADS_ON_FIELD := 40
const LOSS_FACTOR := 2.0
## Состав армии (доли отрядов): пехота строя, стрелки, мечники
const ARMY_MIX := {"spearman": 0.50, "archer": 0.30, "warrior": 0.20}
## Где нанимается род (для цены)
const ARMY_BUILDING := {"spearman": "barracks", "archer": "archery", "warrior": "barracks"}
## Доля древа кузницы (по дереву/золоту/камню), которую партия обязана успевать; еда — узкое место по замыслу
const FORGE_TARGET_SHARE := 0.5
const FORGE_UNREACHABLE_MARGIN := 1.15   # полное древо дороже возможного не меньше чем во столько раз

# ── ХОД ПАРТИИ (допущения) ──
## Бригада растёт от стартовой до целевой за RAMP_MIN минут
const START_WORKERS := 5
const RAMP_MIN := 15.0
## Армия: первые отряды с ARMY_START_MIN, полный состав к ARMY_FULL_MIN
const ARMY_START_MIN := 8.0
const ARMY_FULL_MIN := 45.0
## Постройки партии сверх стартового замка, штук (цена — building_cost_scaled; домов 14 — с 10-го дом дорожает)
const BUILD_PLAN := {"house": 18, "barracks": 3, "archery": 2, "tower": 6,
	"sheep_pen": 3, "smithy": 1}
## Дома растут вместе с армией (лимит бойцов): от стартовых до плана к ARMY_FULL_MIN
const START_HOUSES := 3
## Рабочих за партию гибнет и нанимается заново (доля бригады)
const WORKER_LOSS_SHARE := 0.25
## Плечо «жила ↔ склад», м — то же, что Worker.INCOME_NOMINAL_ARM
const NOMINAL_ARM := 12.0
## КПД бригады: толчея у склада, дальние жилы, переходы между деревьями
const WORKER_EFFICIENCY := 0.85
## Ветка рабочего: сколько рядов изучено и к какой минуте (с неё действует прирост)
const ECON_ROWS := 3
const ECON_READY_MIN := 20.0

# ── ЕДА: ТАБЛИЦА «ПРИХОД / СОДЕРЖАНИЕ» ПО РАЗМЕРУ АРМИИ (ТЗ 28.10.2026, блок 2) ──
## Размеры армии (отрядов на поле), для которых печатается таблица
const FOOD_TABLE_SQUADS := [10, 20, 40]
## Бригада при такой армии: базовых рабочих плюс столько на каждый отряд (фермеры — внутри)
const FOOD_WORKERS_BASE := 20
const FOOD_WORKERS_PER_SQUAD := 2.0

# ── ТЕМП «ЗНАЧИМОГО ДЕЙСТВИЯ» ──
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

# ── РУДНИК: ВОЛНЫ ОРДЫ ПОСЛЕ ЗАХВАТА ──
## Период волн, с; размер волны в отрядах на старте и к MINE_WAVE_LATE_MIN минуте
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

## ── БЮДЖЕТ ПО СТАТЬЯМ ──
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

## Цена узла по ресурсам: with_sink — как в игре, иначе ядро (без стока эндгейма)
static func forge_node_cost(d: Dictionary, with_sink: bool = true) -> Dictionary:
	var src: Dictionary = d if with_sink else (d.get("core_cost", d) as Dictionary)
	return {Constants.RESOURCE_WOOD: float(src.get("cost_wood", 0.0)),
		Constants.RESOURCE_GOLD: float(src.get("cost_gold", 0.0)),
		Constants.RESOURCE_STONE: float(src.get("cost_stone", 0.0)),
		Constants.RESOURCE_FOOD: float(src.get("cost_food", 0.0))}

## Полное древо всех вкладок; max_row — только ряды 1..max_row
static func forge_cost_full(with_sink: bool = true, max_row: int = 99) -> Dictionary:
	var acc := _zero()
	for n in _Forge.all_nodes():
		var d: Dictionary = n
		if int(d.get("row", 0)) <= max_row:
			_add(acc, forge_node_cost(d, with_sink))
	return acc

## Доля древа в бюджете партии — по ЯДРУ цены: бригада считается под развитие, сток
## эндгейма (forge_config.ROW_SINK_MULT) съедает излишек богатой партии (surplus_at)
static func forge_cost(share: float) -> Dictionary:
	var acc := _zero()
	_add(acc, forge_cost_full(false), share)
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
		+ army_food_total() \
		+ worker_minutes(total_workers) * 60.0 * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC
	return acc

## ── ЕДА АРМИИ: ГОЛОВЫ, СТАВКА, НАДБАВКА БОЛЬШОЙ АРМИИ ──
## Голов в среднем отряде по составу ARMY_MIX (уставные размеры из unit_stats_config)
static func squad_heads() -> float:
	var h := 0.0
	for u in ARMY_MIX.keys():
		h += float(ARMY_MIX[u]) * float(_UCfg.squad_size(String(u)))
	return h

## Средний множитель рода (FOOD_UPKEEP_UNIT_MULT) на голову того же состава
static func squad_food_mult() -> float:
	var h := 0.0
	var m := 0.0
	for u in ARMY_MIX.keys():
		var n: float = float(ARMY_MIX[u]) * float(_UCfg.squad_size(String(u)))
		h += n
		m += n * float(_UCfg.FOOD_UPKEEP_UNIT_MULT.get(String(u), 1.0))
	return m / maxf(h, 0.001)

## Еды в секунду на содержание squads отрядов и workers рабочих — та же формула,
## что у GameManager._sweep_food (ставка на голову × род × надбавка большой армии)
static func food_upkeep_per_sec(squads: float, workers: float) -> float:
	var heads: float = squads * squad_heads()
	return heads * squad_food_mult() * _UCfg.FOOD_UPKEEP_SOLDIER_PER_SEC * _UCfg.food_upkeep_mult(heads) \
		+ workers * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC

## Отрядов на поле в минуту t партии: рост с ARMY_START_MIN до ARMY_FULL_MIN
static func squads_at(t_min: float) -> float:
	var k: float = clampf((t_min - ARMY_START_MIN) / maxf(ARMY_FULL_MIN - ARMY_START_MIN, 0.1), 0.0, 1.0)
	return k * float(ARMY_SQUADS_ON_FIELD)

## Еда на содержание армии за партию — интеграл по минутам (надбавка нелинейна по головам)
static func army_food_total() -> float:
	var acc := 0.0
	var t := 0.0
	while t < SESSION_MIN:
		acc += 60.0 * food_upkeep_per_sec(squads_at(t + 0.5), 0.0)
		t += 1.0
	return acc

## Домов под армию в n отрядов (лимит бойцов pop_army_cap с одной крепостью), не меньше стартовых
static func houses_for_squads(n: int) -> int:
	var heads: float = float(n) * squad_heads()
	var need: float = heads - float(_UCfg.ARMY_BASE_UNITS) - float(_UCfg.ARMY_CASTLE_UNITS)
	return maxi(START_HOUSES, int(ceil(maxf(need, 0.0) / float(_UCfg.ARMY_HOUSE_UNITS))))

## Фермеров при армии в n отрядов: по фермеру на отряд, но не больше мест в загонах
static func farmers_for_squads(n: int) -> int:
	return mini(n, int(_UCfg.SHEEP_PLAYER_MAX))

## Еды в секунду с одного фермера при долях ветки: темп ножа (bonus_gather_food) и выход с туши
## (bonus_meat_pct) — та же формула, что Worker.farmer_meat_per_sec × meat_yield_mult
static func meat_rate(cut_pct: float = 0.0, meat_pct: float = 0.0) -> float:
	return _UCfg.MEAT_PER_SEC_TARGET / maxf(1.0 - clampf(cut_pct, 0.0, _UCfg.GATHER_PCT_CAP), 0.1) \
		* (1.0 + maxf(meat_pct, 0.0))

## Строка таблицы «приход / содержание» при n отрядах и изученных рядах 1..rows ветки рабочего
static func food_balance_row(n: int, rows: int) -> Dictionary:
	var b: Dictionary = econ_bonuses(rows) if rows > 0 else {}
	var workers: float = float(FOOD_WORKERS_BASE) + FOOD_WORKERS_PER_SQUAD * float(n)
	var houses: int = houses_for_squads(n)
	var farmers: int = farmers_for_squads(n)
	var heads: float = float(n) * squad_heads()
	var up_army: float = food_upkeep_per_sec(float(n), 0.0)
	var up_work: float = workers * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC
	var inc_h: float = float(houses) * _UCfg.HOUSE_FOOD_INCOME / _UCfg.HOUSE_FOOD_INTERVAL
	var inc_f: float = float(farmers) * meat_rate(float(b.get("bonus_gather_food", 0.0)),
		float(b.get("bonus_meat_pct", 0.0)))
	return {"squads": n, "heads": heads, "mult": _UCfg.food_upkeep_mult(heads), "houses": houses,
		"farmers": farmers, "workers": workers, "upkeep_army": up_army, "upkeep_workers": up_work,
		"upkeep": up_army + up_work, "income_houses": inc_h, "income_farms": inc_f,
		"income": inc_h + inc_f, "balance": inc_h + inc_f - up_army - up_work}

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

## ── ТЕМП ОДНОГО РАБОЧЕГО ──
## Единиц в секунду на плече NOMINAL_ARM. Бонусы — доли, как в Worker:
## gather (доля долой с цикла; у еды — темп ножа), carry (доля к грузу), walk_loaded (к ходу с ношей),
## meat (выход мяса с туши — только еда)
static func worker_rate(res: int, gather_pct: float = 0.0, carry_pct: float = 0.0,
		walk_loaded_pct: float = 0.0, meat_pct: float = 0.0) -> float:
	if res == Constants.RESOURCE_FOOD:
		return meat_rate(gather_pct, meat_pct)
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
	var b: Dictionary = econ_bonuses(ECON_ROWS)
	if res == Constants.RESOURCE_FOOD:
		return meat_rate(float(b.get("bonus_gather_food", 0.0)), float(b.get("bonus_meat_pct", 0.0))) \
			/ maxf(meat_rate(), 0.0001)
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

## ── РЕКОМЕНДУЕМАЯ БРИГАДА ──
## Рабочих на каждом ресурсе под бюджет партии с долей кузницы share;
## еда зависит от размера бригады, поэтому — последовательными приближениями
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
			# Фермеров не больше мест в загонах: остаток нужды в еде — недостача
			# партии (last_food_shortfall), её закрывают ветка «выход мяса» и отказ
			# от части древа, а не сотня фермеров, которым негде резать
			if r == Constants.RESOURCE_FOOD:
				var cap: int = int(_UCfg.SHEEP_PLAYER_MAX)
				last_food_shortfall = maxf(float(n - cap), 0.0) * per_slot if n > cap else 0.0
				n = mini(n, cap)
			out[r] = n
			total += float(n)
	return out

## Еды, которую бригада последнего workers_for не закрывает из-за потолка загонов (0 — закрывает)
static var last_food_shortfall: float = 0.0

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

## ── ТЕМП ДЕЙСТВИЙ ──
## Минута, к которой один узел ряда row доступен по золоту (кузнице идёт FORGE_GOLD_SHARE притока)
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

## ── ИЗЛИШЕК БОГАТОЙ ПАРТИИ (ТЗ 28.10.2026, п. 2: сток кузницы) ──
## Бригада богатой партии по телеметрии 27-28.10: 5-7 k дерева, ~2 k золота, ~1 k камня в минуту к 50-60-й мин
const RICH_WORKERS := {Constants.RESOURCE_WOOD: 45, Constants.RESOURCE_GOLD: 20,
	Constants.RESOURCE_STONE: 8, Constants.RESOURCE_FOOD: 30}
## Ряды древа, которые партия покупает целиком (все вкладки), и к какой минуте
const FORGE_CORE_ROWS := 2
const FORGE_CORE_BY_MIN := 20.0
## Минуты, на которых печатается излишек
const SURPLUS_MINUTES := [30.0, 45.0, 60.0, 90.0]

## Рабоче-минуты одного места бригады к минуте t: место набирается за RAMP_MIN
static func worked_minutes(t: float) -> float:
	if t <= RAMP_MIN:
		return t * t / (2.0 * RAMP_MIN)
	return t - RAMP_MIN * 0.5

## Домов к минуте t: от стартовых до плана к ARMY_FULL_MIN
static func houses_at(t: float) -> float:
	return lerpf(float(START_HOUSES), float(BUILD_PLAN["house"]), clampf(t / ARMY_FULL_MIN, 0.0, 1.0))

## Приход к минуте t: банк + дома + бригада w
static func income_to(t: float, w: Dictionary) -> Dictionary:
	var acc := _zero()
	_add(acc, _UCfg.starting_resources(Constants.FACTION_PLAYER))
	var hm := 0.0
	var m := 0.0
	while m < t:
		hm += houses_at(m + 0.5) * minf(1.0, t - m)
		m += 1.0
	acc[Constants.RESOURCE_FOOD] = float(acc[Constants.RESOURCE_FOOD]) \
		+ hm * 60.0 * _UCfg.HOUSE_FOOD_INCOME / _UCfg.HOUSE_FOOD_INTERVAL
	for r in RES:
		acc[r] = float(acc[r]) + float(w.get(r, 0)) * worker_per_min_effective(r) * worked_minutes(t)
	return acc

## Расход к минуте t без стока: армия (наём равномерно с ARMY_START_MIN), постройки (к ARMY_FULL_MIN),
## наём рабочих, еда содержания армии и бригады, ряды 1..forge_rows древа всех вкладок (к FORGE_CORE_BY_MIN)
static func spend_to(t: float, w: Dictionary, forge_rows: int = FORGE_CORE_ROWS) -> Dictionary:
	var acc := _zero()
	var nw: float = float(workers_total(w))
	_add(acc, army_cost(), clampf((t - ARMY_START_MIN) / (SESSION_MIN - ARMY_START_MIN), 0.0, 1.0))
	_add(acc, buildings_cost(), clampf(t / ARMY_FULL_MIN, 0.0, 1.0))
	var hire: Dictionary = _UCfg.train_cost("castle", "worker")
	_add(acc, hire, (maxf(nw - float(START_WORKERS), 0.0) + nw * WORKER_LOSS_SHARE) * clampf(t / SESSION_MIN, 0.0, 1.0))
	var food := 0.0
	var m := 0.0
	while m < t:
		food += 60.0 * food_upkeep_per_sec(squads_at(m + 0.5), 0.0) * minf(1.0, t - m)
		m += 1.0
	food += nw * worked_minutes(t) * 60.0 * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC
	acc[Constants.RESOURCE_FOOD] = float(acc[Constants.RESOURCE_FOOD]) + food
	if forge_rows > 0:
		_add(acc, forge_cost_full(true, forge_rows), clampf(t / FORGE_CORE_BY_MIN, 0.0, 1.0))
	return acc

## Излишек к минуте t: приход − расход (по ресурсам; минус — недостача)
static func surplus_at(t: float, w: Dictionary = RICH_WORKERS, forge_rows: int = FORGE_CORE_ROWS) -> Dictionary:
	var inc: Dictionary = income_to(t, w)
	var sp: Dictionary = spend_to(t, w, forge_rows)
	var out := _zero()
	for r in RES:
		out[r] = float(inc[r]) - float(sp[r])
	return out

## Сумма положительных статей излишка (недостача одного ресурса не гасит излишек другого)
static func surplus_total(s: Dictionary) -> float:
	var acc := 0.0
	for r in RES:
		acc += maxf(float(s.get(r, 0.0)), 0.0)
	return acc
