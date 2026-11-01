extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ЭКОНОМИКА КРАСНОГО ИИ v2 (ТЗ 30.10.2026, ручка perf_config.ai_eco_v2)
## ═══════════════════════════════════════════════════════════════════════════
## Телеметрия партии 30.10: у красных еда 9-62 всю партию при 7-14 тыс.
## золота и 3-9 тыс. дерева. Еду давали только дома (1 еда за 8 с), рабочие
## еду не добывали, рынка не было — и всё, что стоит еды (рабочий, отряд, узел
## кузницы), стояло. Резерв еды AI_FOOD_RESERVE запирал найм рабочих на полу
## AI_WORKER_FLOOR, а кузница ждала окна между стройками (исследования шли
## только в конце _construction, после ранних выходов по занятой площадке).
##
## Модуль закрывает это четырьмя вещами, каждая — тем же путём, что у игрока:
##   • ЗАГОНЫ (ECO_PENS) и фермеры на них — Worker.command_farm_pen: мясо;
##   • РЫНОК — Market.trade по курсу MARKET: излишек золота/дерева/камня
##     сверх ECO_TRADE_KEEP в еду до ECO_FOOD_TARGET, лишний камень в золото;
##   • СКЛАДЫ (ECO_STOREHOUSES) у делянок, где рабочие ходят дальше
##     ECO_STORE_FAR_M до точки сдачи;
##   • КУЗНИЦА каждый такт, когда она свободна, — а не только в окно без строек.
## Плюс потолок рабочих ×ECO_WORKER_LIMIT_MULT и найм в приоритете до
## ECO_WORKER_TARGET (EnemyAI._economy спрашивает worker_limit/worker_target).
## Модуль ничего не считает покадрово: всё — в такте ИИ раз в 2 с.

const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Diff := preload("res://scripts/game_difficulty_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _Market := preload("res://scripts/Market.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")

const F := Constants.FACTION_ENEMY

var ai = null                      # EnemyAI

## Стенды и телеметрия
var trades: int = 0
var food_bought: float = 0.0
var pens_built: int = 0
var farmers_sent: int = 0
var stores_started: int = 0
var markets_started: int = 0
var forge_starts: int = 0
var _trade_t: float = -1.0e9

func reset() -> void:
	trades = 0
	food_bought = 0.0
	pens_built = 0
	farmers_sent = 0
	stores_started = 0
	markets_started = 0
	forge_starts = 0
	_trade_t = -1.0e9

func on() -> bool:
	return _Opt.ai_eco_v2

## Потолок рабочих
func worker_limit() -> int:
	return int(round(float(_Diff.ai_worker_limit()) * _AICfg.ECO_WORKER_LIMIT_MULT))

## До скольких рабочих найм идёт в голову очереди замка
func worker_target() -> int:
	return mini(_AICfg.ECO_WORKER_TARGET, worker_limit())

## Рынок закрывает еду — резерв еды под армию найм рабочих не запирает
func feeds_workers() -> bool:
	return market() != null

# ─────────────────────────────────────────────────────────────────────────────
# ПОСТРОЙКИ
# ─────────────────────────────────────────────────────────────────────────────
func _tree() -> SceneTree:
	return ai.main.get_tree()

func market() -> Building:
	for b in _tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is Building and (b as Building).building_id == "market" \
				and not (b as Building).is_dead():
			return b as Building
	return null

func pens() -> Array:
	var out: Array = []
	for p in _tree().get_nodes_in_group("sheep_pens"):
		if is_instance_valid(p) and int(p.get("faction")) == F and not (p as Building).is_dead():
			out.append(p)
	return out

func storehouses() -> int:
	var n := 0
	for b in _tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is Building and (b as Building).building_id == "storehouse" \
				and not (b as Building).is_dead():
			n += 1
	return n + ai._sites_count("storehouse")

## Свободна ли точка: ни одной своей постройки и стройки ближе r
func _spot_free(p: Vector3, r: float) -> bool:
	for grp in ["enemy_buildings", "construction_sites", "sheep_pens"]:
		for b in _tree().get_nodes_in_group(grp):
			if not is_instance_valid(b):
				continue
			var q: Vector3 = (b as Node3D).global_position
			if Vector2(q.x - p.x, q.z - p.z).length() < r:
				return false
	return GameManager.is_passable(p.x, p.z)

## Первое свободное место из списка смещений (вперёд по фронту, вбок) от замка
func _base_spot(castle: Castle, offs: Array, r: float) -> Vector3:
	var f: Vector3 = castle.front_dir()
	var sd := Vector3(-f.z, 0.0, f.x)
	for o in offs:
		var v: Vector2 = o
		var p: Vector3 = castle.global_position + f * v.x + sd * v.y
		p.x = clampf(p.x, -ai.main.GEN_HALF_X + 6.0, ai.main.GEN_HALF_X - 6.0)
		p.z = clampf(p.z, -ai.main.GEN_HALF_Z + 6.0, ai.main.GEN_HALF_Z - 6.0)
		p = GameManager.land_target(p)
		if _spot_free(p, r):
			return p
	return Vector3.INF

## Места у замка: загоны и рынок — по бокам, вне рядов домов (±7.5 м за
## замком) и вне линии барак/кузница/стрелковая (+2 м вперёд, ±8/16 вбок)
const PEN_OFFS := [Vector2(-12.0, 16.0), Vector2(-12.0, -16.0), Vector2(-19.0, 17.0),
	Vector2(-19.0, -17.0), Vector2(-26.0, 16.0), Vector2(-26.0, -16.0)]
const MARKET_OFFS := [Vector2(2.0, -16.0), Vector2(-5.0, -17.0), Vector2(-5.0, 17.0),
	Vector2(9.0, -14.0), Vector2(9.0, 14.0)]

## Один шаг стройки экономики; true — действие сделано (площадка заложена
## или загон поставлен), такт стройки на этом заканчивается
func build_step(castle: Castle, crew: int) -> bool:
	var np: int = pens().size()
	var mk: Building = market()
	var mk_site: bool = ai._site_in_progress("market")
	# Первый загон — сразу (мясо нужно раньше рынка), второй — после рынка
	if np < 1 or (np < _AICfg.ECO_PENS and (mk != null or mk_site)):
		if _place_pen(castle):
			return true
	if mk == null and not mk_site:
		var p: Vector3 = _base_spot(castle, MARKET_OFFS, 5.0)
		if p.x != INF and ai._start_site("market", p, false, crew):
			markets_started += 1
			ai.last_action += "|заложен рынок"
			return true
	if storehouses() < _AICfg.ECO_STOREHOUSES:
		var sp: Vector3 = _store_spot()
		if sp.x != INF and ai._start_site("storehouse", sp, false, crew):
			stores_started += 1
			ai.last_action += "|заложен склад"
			return true
	return false

## Загон ставится сразу (instant_build), цену берёт общий build_cost_for
func _place_pen(castle: Castle) -> bool:
	var p: Vector3 = _base_spot(castle, PEN_OFFS, 6.0)
	if p.x == INF:
		return false
	if not ResourceManager.spend(F, GameManager.build_cost_for(F, "sheep_pen")):
		return false
	var made: Building = _CSite.make_building("sheep_pen")
	if made == null:
		return false
	made.faction = F
	if "stock_on_ready" in made:
		made.set("stock_on_ready", true)
	ai.main.world_add(made)
	made.global_position = p
	pens_built += 1
	ai.last_action += "|поставлен загон"
	return true

## Склад — у делянки, куда ECO_STORE_MIN_WORKERS и больше рабочих ходят
## дальше ECO_STORE_FAR_M от ближайшей точки сдачи: медиана их целей,
## сдвинутая на 5 м к замку (не на ствол и не в рудную жилу)
func _store_spot() -> Vector3:
	var xs: Array = []
	var zs: Array = []
	var far2: float = _AICfg.ECO_STORE_FAR_M * _AICfg.ECO_STORE_FAR_M
	for n in _tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(n) or not (n is Worker) or (n as Worker).is_dead():
			continue
		var w := n as Worker
		var gt = w.gather_target
		if gt == null or not is_instance_valid(gt):
			continue
		var gp: Vector3 = (gt as Node3D).global_position
		var dp = GameManager.get_nearest_dropoff(F, gp)
		if dp == null or not is_instance_valid(dp):
			continue
		if (dp as Node3D).global_position.distance_squared_to(gp) < far2:
			continue
		xs.append(gp.x)
		zs.append(gp.z)
	if xs.size() < _AICfg.ECO_STORE_MIN_WORKERS:
		return Vector3.INF
	xs.sort()
	zs.sort()
	var c := Vector3(float(xs[xs.size() / 2]), 0.0, float(zs[zs.size() / 2]))
	var home: Vector3 = ai._home_pos
	var to_home := Vector3(home.x - c.x, 0.0, home.z - c.z)
	if to_home.length() > 0.1:
		c += to_home.normalized() * 5.0
	var q: Vector2 = GameManager.nearest_passable(c.x, c.z)
	if not q.is_finite():
		return Vector3.INF
	var p: Vector3 = GameManager.land_target(Vector3(q.x, 0.0, q.y))
	return p if _spot_free(p, 6.0) else Vector3.INF

# ─────────────────────────────────────────────────────────────────────────────
# ТАКТ: ФЕРМЕРЫ, РЫНОК, КУЗНИЦА
# ─────────────────────────────────────────────────────────────────────────────
func tick(castle: Castle) -> void:
	_farmers()
	_trade()
	_forge()

## Рабочий на загоне в покое ждёт овцу — общий проход «бездельника на ресурс»
## его не трогает (EnemyAI._economy спрашивает это)
static func is_farmer(w: Worker) -> bool:
	return w.farm_pen() != null

func _farmers() -> void:
	var ps: Array = pens()
	if ps.is_empty():
		return
	var count: Dictionary = {}
	var free: Array = []
	for n in _tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(n) or not (n is Worker) or (n as Worker).is_dead():
			continue
		var w := n as Worker
		var fp: Node3D = w.farm_pen()
		if fp != null:
			count[fp] = int(count.get(fp, 0)) + 1
			continue
		# Строитель и сдающий груз — не трогаем; собирающий — можно
		if w.build_target != null and is_instance_valid(w.build_target):
			continue
		free.append(w)
	var sent := 0
	for p in ps:
		var need: int = _AICfg.ECO_FARMERS_PER_PEN - int(count.get(p, 0))
		while need > 0 and not free.is_empty() and sent < 2:
			var best: int = 0
			var bd: float = INF
			for i in range(free.size()):
				var d: float = (free[i] as Node3D).global_position.distance_squared_to((p as Node3D).global_position)
				if d < bd:
					bd = d
					best = i
			var w2: Worker = free[best]
			free.remove_at(best)
			w2.command_farm_pen(p as Node3D)
			farmers_sent += 1
			sent += 1
			need -= 1

func _amount(r: int) -> float:
	return ResourceManager.get_amount(F, r)

func _trade() -> void:
	var mk: Building = market()
	if mk == null or not mk.has_method("trade"):
		return
	if ai.clock - _trade_t < _AICfg.ECO_TRADE_EVERY_SEC:
		return
	_trade_t = ai.clock
	var lot_min: float = float(_UCfg.MARKET["lot_min"])
	var lot_max: float = float(_UCfg.MARKET["lot_max"])
	# Лишний камень — в золото
	var stone: float = _amount(Constants.RESOURCE_STONE)
	if stone > _AICfg.ECO_STONE_SURPLUS:
		var lot: float = clampf(floorf(stone - _AICfg.ECO_STONE_SURPLUS), lot_min, lot_max)
		if mk.trade(F, Constants.RESOURCE_STONE, Constants.RESOURCE_GOLD, lot):
			trades += 1
	var food: float = _amount(Constants.RESOURCE_FOOD)
	if food >= _AICfg.ECO_FOOD_TARGET:
		return
	var need: float = _AICfg.ECO_FOOD_TARGET - food
	# Платим тем, чего сверх запаса больше всего (в единицах курса)
	var val: Dictionary = _UCfg.MARKET["value"]
	var best_r: int = -1
	var best_v: float = 0.0
	for r in _AICfg.ECO_TRADE_KEEP:
		var spare: float = _amount(int(r)) - float(_AICfg.ECO_TRADE_KEEP[r])
		var v: float = spare * float(val.get(int(r), 1.0))
		if spare >= lot_min and v > best_v:
			best_v = v
			best_r = int(r)
	if best_r < 0:
		return
	var va: float = float(val.get(best_r, 1.0))
	var vf: float = float(val.get(Constants.RESOURCE_FOOD, 1.0))
	var fee: float = float(_UCfg.MARKET["fee"])
	var pay: float = ceilf(need * vf / va / maxf(1.0 - fee, 0.01))
	var spare2: float = _amount(best_r) - float(_AICfg.ECO_TRADE_KEEP[best_r])
	pay = clampf(pay, lot_min, minf(lot_max, floorf(spare2)))
	if pay < lot_min:
		return
	var got: float = _Market.quote(best_r, Constants.RESOURCE_FOOD, pay)
	if mk.trade(F, best_r, Constants.RESOURCE_FOOD, pay):
		trades += 1
		food_bought += got
		ai.last_action += "|рынок: %d → еда %d" % [int(pay), int(got)]

## Кузница работает всегда, когда свободна (раньше — только в окно без строек)
func _forge() -> void:
	if not ai._peace_over:
		return
	var smithy: Smithy = null
	for b in _tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is Smithy and not (b as Building).is_dead():
			smithy = b as Smithy
			break
	if smithy == null:
		return
	if not smithy.research_id.is_empty() or not smithy.research_queue.is_empty():
		return
	var before: String = smithy.research_id
	ai._research_forge(smithy)
	if smithy.research_id != before:
		forge_starts += 1
