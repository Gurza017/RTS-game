extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ВОЖАК ОРДЫ И КУЗНИЦА (ТЗ 28.10.2026, п. 4) — помощник GoblinAI
## ═══════════════════════════════════════════════════════════════════════════
## Зовётся из GoblinAI._process раз в такт (THINK_SEC) после _economy_tick:
##   1) ДЕРЕВО И ЗОЛОТО лагеря — пассивный приток по доле живых хижин (у орды
##      нет рабочих; еда идёт своим тактом в GoblinAI._economy_tick);
##   2) ЗАКЛАДКА кузницы — одна на лагерь, после FORGE_LAY_AFTER_SEC, если
##      хватает дерева/золота/еды и после оплаты остаётся еда на отряды;
##      орда строит сама: цена списывается сразу, здание встаёт через
##      build_time (ConstructionSite и рабочих у орды нет);
##   3) ИССЛЕДОВАНИЕ — по одному, лучший узел по весам FORGE_AI_WEIGHTS на
##      единицу цены (тот же приём, что EnemyAI._research_forge у красного);
##      заготовки (stub) не берутся.
## Ручка perf_config.goblin_forge выключает все три шага; само здание и древо
## при этом работают (стенд, ручная игра за гоблинов).

const _GF := preload("res://scripts/economy/goblin_forge/goblin_forge_config.gd")
const _GFB := preload("res://scripts/economy/goblin_forge/GoblinForgeBonus.gd")
const _GForgeS := preload("res://scripts/economy/goblin_forge/GoblinForge.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

## Срок закладки — поле, а не константа: стенд ставит ноль
var lay_after_sec: float = _GF.FORGE_LAY_AFTER_SEC
## Закладка оплачена, здание встанет в этот момент часов вожака (-1 — нет)
var _lay_done_at: float = -1.0
var _lay_spot: Vector3 = Vector3.INF
var _last_research_at: float = -1.0e9
## Счётчики стендам и телеметрии
var forges_laid: int = 0
var researches_ordered: int = 0
var wood_income_min: float = 0.0
var gold_income_min: float = 0.0
var last_action: String = ""

func tick(gai: Node, dt: float) -> void:
	if not _Opt.goblin_forge or gai == null or gai.phase == gai.PHASE_DEFEATED:
		return
	_income(gai, dt)
	_lay_tick(gai)
	_research_tick(gai)

# ─────────────────────────────────────────────────────────────────────────────
# ДЕРЕВО И ЗОЛОТО ЛАГЕРЯ
# ─────────────────────────────────────────────────────────────────────────────
func _income(gai: Node, dt: float) -> void:
	var huts: Array = gai._huts_alive()
	var small: int = 0
	for h in huts:
		if String((h as Building).building_id) == "goblin_hut":
			small += 1
	# Доля лагеря: хижины — половина притока, хата — вторая половина
	var k: float = 0.5 * float(small) / maxf(float(_GobCfg.HUTS), 1.0) + (0.5 if gai.chief_alive() else 0.0)
	wood_income_min = _GF.HORDE_WOOD_PER_MIN * k
	gold_income_min = _GF.HORDE_GOLD_PER_MIN * k
	_bank_add(Constants.RESOURCE_WOOD, wood_income_min / 60.0 * dt, _GF.HORDE_WOOD_BANK_MAX)
	_bank_add(Constants.RESOURCE_GOLD, gold_income_min / 60.0 * dt, _GF.HORDE_GOLD_BANK_MAX)

func _bank_add(type: int, amount: float, cap: float) -> void:
	if amount <= 0.0:
		return
	var f: int = Constants.FACTION_GOBLIN
	var have: float = ResourceManager.get_amount(f, type)
	if have >= cap:
		return
	ResourceManager.set_amount(f, type, minf(have + amount, cap))

# ─────────────────────────────────────────────────────────────────────────────
# ЗАКЛАДКА
# ─────────────────────────────────────────────────────────────────────────────
func forge(gai: Node) -> Node:
	return _GFB.forge_of(gai.get_tree(), Constants.FACTION_GOBLIN)

func _lay_tick(gai: Node) -> void:
	var f: int = Constants.FACTION_GOBLIN
	if _lay_done_at >= 0.0:
		if gai.clock < _lay_done_at:
			return
		_lay_done_at = -1.0
		_place(gai, _lay_spot)
		return
	if forge(gai) != null or gai.clock < lay_after_sec:
		return
	var cost: Dictionary = _UCfg.building_cost("goblin_forge")
	if not ResourceManager.can_afford(f, cost):
		return
	var food_after: float = ResourceManager.get_amount(f, Constants.RESOURCE_FOOD) \
		- float(cost.get(Constants.RESOURCE_FOOD, 0.0))
	if food_after < _GF.FORGE_LAY_FOOD_RESERVE:
		return
	var spot: Vector3 = camp_spot(gai)
	if not is_finite(spot.x):
		last_action = "кузница: места в лагере нет"
		return
	if not ResourceManager.spend(f, cost):
		return
	_lay_spot = spot
	_lay_done_at = gai.clock + _UCfg.building_stat("goblin_forge", "build_time", 30.0)
	last_action = "кузница заложена"

## Место кузницы: смещение от центра лагеря, свободное от других построек и
## проходимое; INF — не нашлось
func camp_spot(gai: Node) -> Vector3:
	var offs: Array = [_GF.CAMP_OFFSET]
	offs.append_array(_GF.CAMP_OFFSET_ALT)
	for o in offs:
		var off: Vector2 = o
		var p: Vector3 = Vector3(gai.village.x + off.x, 0.0, gai.village.z + off.y)
		if not GameManager.is_passable(p.x, p.z):
			continue
		if _spot_busy(gai, p):
			continue
		return p
	return Vector3.INF

func _spot_busy(gai: Node, p: Vector3) -> bool:
	var r2: float = _GF.SPOT_BUSY_R * _GF.SPOT_BUSY_R
	for b in gai.get_tree().get_nodes_in_group("all_buildings"):
		if b == null or not is_instance_valid(b) or not (b is Node3D):
			continue
		var q: Vector3 = (b as Node3D).global_position
		if Vector2(q.x - p.x, q.z - p.z).length_squared() < r2:
			return true
	return false

func _place(gai: Node, spot: Vector3) -> Node:
	if gai.main == null or not is_finite(spot.x):
		return null
	var b = _GForgeS.new()
	b.faction = Constants.FACTION_GOBLIN
	gai.main.world_add(b)
	b.global_position = Vector3(spot.x, GameManager.get_terrain_height(spot.x, spot.z), spot.z)
	forges_laid += 1
	last_action = "кузница построена"
	return b

# ─────────────────────────────────────────────────────────────────────────────
# ИССЛЕДОВАНИЕ
# ─────────────────────────────────────────────────────────────────────────────
func _research_tick(gai: Node) -> void:
	var fg = forge(gai)
	if fg == null or not String(fg.research_id).is_empty():
		return
	if gai.clock - _last_research_at < _GF.FORGE_RESEARCH_GAP_SEC:
		return
	var best_id: String = pick_research(Constants.FACTION_GOBLIN)
	if best_id.is_empty():
		return
	_last_research_at = gai.clock
	if fg.research(best_id):
		researches_ordered += 1
		last_action = "исследование %s" % best_id

## Лучший доступный узел древа по весам на единицу цены ("" — нечего или не по карману)
func pick_research(f: int) -> String:
	var best_id: String = ""
	var best_score: float = 0.0
	var food: float = ResourceManager.get_amount(f, Constants.RESOURCE_FOOD)
	for n in _GF.all_nodes():
		var node: Dictionary = n
		var nid: String = String(node.get("id", ""))
		if bool(node.get("stub", false)):
			continue
		if not GameManager.can_research(f, nid):
			continue
		var cost: Dictionary = _UCfg.upgrade_cost(node)
		if not ResourceManager.can_afford(f, cost):
			continue
		if food - float(cost.get(Constants.RESOURCE_FOOD, 0.0)) < _GF.FORGE_RESEARCH_FOOD_RESERVE:
			continue
		var score: float = 0.0
		for key in _GF.FORGE_AI_WEIGHTS:
			score += float(node.get(String(key), 0.0)) * float(_GF.FORGE_AI_WEIGHTS[key])
		if score <= 0.0:
			continue
		score /= maxf(float(node.get("cost_wood", 0.0)) + float(node.get("cost_gold", 0.0)), 1.0)
		if score > best_score:
			best_score = score
			best_id = nid
	return best_id

## Сводка стендам и телеметрии
func summary() -> Dictionary:
	return {"laid": forges_laid, "ordered": researches_ordered,
		"wood_min": snappedf(wood_income_min, 0.1), "gold_min": snappedf(gold_income_min, 0.1),
		"pending": _lay_done_at >= 0.0, "last": last_action}
