extends Building
class_name Smithy

const _UCfg := preload("res://scripts/unit_stats_config.gd")

## Слоты улучшений живут в unit_stats_config.gd (UPGRADE_SLOTS) — добавляйте
## новые там. Здесь оставлен алиас: HUD и старый код обращаются к Smithy.UPGRADES.
static var UPGRADES: Array = _UCfg.UPGRADE_SLOTS

## ТЕКУЩЕЕ ИССЛЕДОВАНИЕ. Кузница качает по одной технологии за раз; время
## каждой задаётся в конфиге (UPGRADE_SLOTS[*].research_time).
var research_id: String      = ""
var research_time: float     = 0.0
var research_timer: float    = 0.0

## ОЧЕРЕДЬ ИССЛЕДОВАНИЙ. Элемент — {"id": String, "time": float}.
## Ресурсы за очередной заказ списываются СРАЗУ при постановке в очередь (как и
## при найме отряда): иначе игрок бронирует пять технологий бесплатно, а к
## моменту их начала денег уже нет. Время хранится в элементе, а не читается из
## конфига при старте, — так снятый из очереди слот нельзя стартовать дважды
var research_queue: Array = []
## Сколько заказов можно поставить сверх текущего
const QUEUE_MAX := 5

func _ready() -> void:
	building_id  = "smithy"
	sprite_path  = "res://assets/sprites/buildings/smithy.png"
	# Запас жизни и габарит — из единого конфига (BUILDINGS["smithy"])
	max_health   = _UCfg.building_stat("smithy", "max_hp", 250.0)
	build_size   = _UCfg.building_size("smithy", Vector3(4.0, 3.0, 4.0))
	display_name = String(_UCfg.building_cfg("smithy").get("name", "Кузница"))
	# Точку выхода держит узел SpawnPoint (см. Building), офсет считается по нему
	super._ready()

func _build_visual() -> void:
	var col := CollisionShape3D.new()
	var sh  := BoxShape3D.new()
	sh.size = build_size; col.shape = sh
	col.position.y = build_size.y / 2.0
	add_child(col)

	var body := MeshInstance3D.new()
	var box  := BoxMesh.new(); box.size = build_size
	var mat  := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.36, 0.32)
	mat.roughness    = 0.88
	box.material = mat; body.mesh = box
	body.position.y = build_size.y / 2.0
	add_child(body)

	var chimney := MeshInstance3D.new()
	var ch_box := BoxMesh.new(); ch_box.size = Vector3(0.5, 1.5, 0.5)
	var ch_mat := StandardMaterial3D.new(); ch_mat.albedo_color = Color(0.28, 0.24, 0.20); ch_box.material = ch_mat
	chimney.mesh = ch_box; chimney.position = Vector3(1.2, build_size.y + 0.75, 0.8)
	add_child(chimney)

	# Единый для всех построек маркер выделения (Cursor_04.png плашмя на земле)
	selection_ring = make_selection_marker()
	add_child(selection_ring)

## Заказать исследование. Ресурсы списываются СРАЗУ (как и при найме отряда),
## бонус применяется по истечении research_time. Кузница качает строго по одной
## технологии, но заказы КОПЯТСЯ: занятой кузнице повторный клик по другому
## слоту ставит его в очередь (если хватает ресурсов).
## false — очередь полна, не хватило ресурсов или слот недоступен/уже заказан
## (GameManager.can_research отсекает и купленное, и уже стоящее в очереди —
## пометку «в работе» ставит start_research в момент постановки).
func research(upgrade_id: String) -> bool:
	if not research_id.is_empty() and research_queue.size() >= QUEUE_MAX:
		return false
	var t: float = GameManager.start_research(faction, upgrade_id)
	if t < 0.0:
		return false
	if t <= 0.0:
		# research_time = 0 в конфиге — прежнее мгновенное поведение
		GameManager.finish_research(faction, upgrade_id)
		_click_sfx()
		return true
	if research_id.is_empty():
		_begin(upgrade_id, t)
	else:
		research_queue.append({"id": upgrade_id, "time": t})
	_click_sfx()
	return true

## ЩЕЛЧОК ПО ИССЛЕДОВАНИЮ. Звучит на ПРИНЯТЫЙ заказ, а не на нажатие кнопки:
## отказ (не хватило ресурсов, узел заперт, очередь полна) обязан отличаться от
## успеха хотя бы тишиной. Чужая кузница молчит — интерфейс наш
func _click_sfx() -> void:
	if faction == Constants.FACTION_PLAYER:
		AudioManager.play_ui("smith_pick")

## ОТМЕНИТЬ заказ — текущий или стоящий в очереди. Ресурсы возвращаются
## полностью (GameManager.cancel_research). Отменённое текущее исследование
## сразу уступает место следующему из очереди.
## false — такого заказа в кузнице нет.
func cancel_research(upgrade_id: String) -> bool:
	if upgrade_id == research_id:
		if not GameManager.cancel_research(faction, upgrade_id):
			return false
		research_id    = ""
		research_time  = 0.0
		research_timer = 0.0
		_start_next()
		return true
	for i in range(research_queue.size()):
		var item: Dictionary = research_queue[i]
		if String(item.get("id", "")) != upgrade_id:
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

## Все заказанные слоты по порядку, начиная с текущего
func queued_ids() -> Array:
	var ids: Array = []
	if not research_id.is_empty():
		ids.append(research_id)
	for item in research_queue:
		ids.append(String((item as Dictionary).get("id", "")))
	return ids

func _begin(upgrade_id: String, t: float) -> void:
	research_id    = upgrade_id
	research_time  = t
	research_timer = 0.0
	set_process(true)   # пошёл отсчёт — здание просыпается

func _start_next() -> void:
	while not research_queue.is_empty():
		var item: Dictionary = research_queue.pop_front()
		var next_id: String  = String(item.get("id", ""))
		if next_id.is_empty():
			continue
		_begin(next_id, float(item.get("time", 0.0)))
		return

## Доля готовности текущего исследования 0..1 (0, если кузница свободна)
func research_progress() -> float:
	if research_id.is_empty() or research_time <= 0.0:
		return 0.0
	return clampf(research_timer / research_time, 0.0, 1.0)

# Пока идёт исследование, зданию нужен покадровый тик (см. Building._needs_tick)
func _needs_tick() -> bool:
	return not research_id.is_empty()

func _process(delta: float) -> void:
	super._process(delta)
	if research_id.is_empty():
		return
	research_timer += delta
	if research_timer < research_time:
		return
	var done_id := research_id
	research_id    = ""
	research_timer = 0.0
	research_time  = 0.0
	GameManager.finish_research(faction, done_id)
	_start_next()
