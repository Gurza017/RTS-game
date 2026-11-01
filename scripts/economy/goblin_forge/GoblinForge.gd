extends "res://scripts/goblin/GoblinHut.gd"

## ═══════════════════════════════════════════════════════════════════════════
## КУЗНИЦА ГОБЛИНОВ (ТЗ 28.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Здание орды, где исследуется древо goblin_forge_config. Наследует хижину
## ради готового обвеса: рисунок хаты с дымом из трубы (Building.sprite_fps),
## рисунок к камере (_draw_z / draw_anchor), фундамент в ядре (block_circles →
## register_building_obstacle), руины, туман. Крупнее хижины в
## goblin_config.GOBLIN_FORGE_SIZE_MULT раз — квад растёт от build_size, с ним
## коробка размещения, пластина клика и ряд кругов фундамента.
##
## Очередь исследований — тот же контур, что у Smithy (GameManager.start_research
## списывает ресурсы и ставит пометку «в работе», finish_research копит бонусы
## по фракции здания): банк и бонусы в GameManager уже разделены по фракциям,
## и у орды они свои. Сам Smithy не наследуется: он процедурная коробка людей,
## а HUD ветвится по `is Smithy`; у кузницы орды своё окно (GoblinForgePanel).
## Без class_name — подключается preload/load (кэш классов не трогаем).

const _GF := preload("res://scripts/economy/goblin_forge/goblin_forge_config.gd")
const _GobCfgF := preload("res://scripts/goblin/goblin_config.gd")

var research_id: String = ""
var research_time: float = 0.0
var research_timer: float = 0.0
## Элемент — {"id": String, "time": float}; ресурсы списаны при постановке
var research_queue: Array = []
const QUEUE_MAX := 3
## Сколько исследований доехало в этой кузнице (стендам и телеметрии)
var finished_count: int = 0

func _configure() -> void:
	super._configure()
	building_id  = "goblin_forge"
	max_health   = _UCfgH.building_stat("goblin_forge", "max_hp", 2400.0)
	build_size   = _UCfgH.building_size("goblin_forge", Vector3(4.0, 3.5, 4.0)) * _GobCfgF.GOBLIN_FORGE_SIZE_MULT
	display_name = String(_UCfgH.building_cfg("goblin_forge").get("name", "Кузница гоблинов"))
	spawn_offset = Vector3(0.0, 0.0, HUT_GATE * _GobCfgF.GOBLIN_FORGE_GATE_MULT)

## Кузница — не столица: с её сносом орда не держится, как и без хижин она не живёт
func is_stronghold() -> bool:
	return false

## Заказать исследование. false — очередь полна, узел недоступен, не хватило ресурсов
func research(upgrade_id: String) -> bool:
	if not _GF.is_forge_id(upgrade_id):
		return false
	if not research_id.is_empty() and research_queue.size() >= QUEUE_MAX:
		return false
	var t: float = GameManager.start_research(faction, upgrade_id)
	if t < 0.0:
		return false
	if t <= 0.0:
		GameManager.finish_research(faction, upgrade_id)
		finished_count += 1
		return true
	if research_id.is_empty():
		_begin(upgrade_id, t)
	else:
		research_queue.append({"id": upgrade_id, "time": t})
	if faction == Constants.FACTION_PLAYER:
		AudioManager.play_ui("smith_pick")
	return true

## Отменить заказ с полным возвратом цены (GameManager.cancel_research)
func cancel_research(upgrade_id: String) -> bool:
	if upgrade_id == research_id:
		if not GameManager.cancel_research(faction, upgrade_id):
			return false
		research_id = ""
		research_time = 0.0
		research_timer = 0.0
		_start_next()
		return true
	for i in range(research_queue.size()):
		if String((research_queue[i] as Dictionary).get("id", "")) != upgrade_id:
			continue
		if not GameManager.cancel_research(faction, upgrade_id):
			return false
		research_queue.remove_at(i)
		return true
	return false

## Место слота в очереди: 0 — исследуется сейчас, 1.. — ждёт, -1 — не заказан
func queue_position(upgrade_id: String) -> int:
	if upgrade_id == research_id:
		return 0
	for i in range(research_queue.size()):
		if String((research_queue[i] as Dictionary).get("id", "")) == upgrade_id:
			return i + 1
	return -1

func queued_ids() -> Array:
	var ids: Array = []
	if not research_id.is_empty():
		ids.append(research_id)
	for item in research_queue:
		ids.append(String((item as Dictionary).get("id", "")))
	return ids

func research_progress() -> float:
	if research_id.is_empty() or research_time <= 0.0:
		return 0.0
	return clampf(research_timer / research_time, 0.0, 1.0)

func _begin(upgrade_id: String, t: float) -> void:
	research_id = upgrade_id
	research_time = t
	research_timer = 0.0
	set_process(true)

func _start_next() -> void:
	while not research_queue.is_empty():
		var item: Dictionary = research_queue.pop_front()
		var next_id: String = String(item.get("id", ""))
		if next_id.is_empty():
			continue
		_begin(next_id, float(item.get("time", 0.0)))
		return

## Снесли посреди исследования — заказы снимаются с возвратом, иначе пометка
## «в работе» переживает здание (тот же разбор, что у Smithy._die)
func _die() -> void:
	if not _dead:
		for id in queued_ids():
			GameManager.cancel_research(faction, String(id))
		research_queue.clear()
		research_id = ""
		research_time = 0.0
		research_timer = 0.0
	super._die()

func _needs_tick() -> bool:
	return not research_id.is_empty()

func _process(delta: float) -> void:
	super._process(delta)
	if research_id.is_empty():
		return
	research_timer += delta
	if research_timer < research_time:
		return
	var done_id: String = research_id
	research_id = ""
	research_timer = 0.0
	research_time = 0.0
	finished_count += 1
	GameManager.finish_research(faction, done_id)
	_start_next()
