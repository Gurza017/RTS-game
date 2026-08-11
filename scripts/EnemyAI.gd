extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ИИ ПРОТИВНИКА
## ═══════════════════════════════════════════════════════════════════════════
## Все НАСТРОЙКИ живут в scripts/ai_start_army_limit.gd — здесь только логика.
##
## Схема партии:
##   1. Старт как у игрока: замок + START_WORKERS рабочих, войск нет вовсе.
##   2. Экономика: рабочие добываются до WORKER_LIMIT, ставится барак, кузница.
##   3. Найм отрядов до SQUAD_LIMIT по каждому типу.
##   4. Пока лимит не набран: HOME_GUARD_PER_TYPE отрядов каждого типа стоят
##      у замка в стойке ЗАЩИТА, все излишки уходят драться к озеру.
##   5. Лимит набран → общая атака выбранной тактикой на базу игрока.
##   6. Победил у озера → двигается на базу. Потерял армию → снова с пункта 2.
##
## Файл намеренно без class_name: подключается через preload, поэтому не
## зависит от global_script_class_cache.cfg.

const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _UCfg  := preload("res://scripts/unit_stats_config.gd")

## Роли отряда
const ROLE_GUARD   := "guard"     # стоит у замка в обороне
const ROLE_FIELD   := "field"     # отправлен драться к озеру
const ROLE_ASSAULT := "assault"   # идёт на базу игрока
const ROLE_LINE    := "line"      # держит рубеж обороны (DEFENSIVE_MODE)
const ROLE_PATROL  := "patrol"    # ходит по своей территории (DEFENSIVE_MODE)

# Строй отряда при выдаче приказа
const SQUAD_COLS    := 6
const SQUAD_SPACING := 0.5
## Разнос отрядов ОДНОГО типа по фронту волны, метры
const SQUAD_LATERAL_STEP := 5.0
## Насколько далеко от замка встаёт гарнизон
const GUARD_RING := 12.0

var main: Node3D = null

## Отряды ИИ: [{"type": String, "members": Array, "role": String,
##              "target": Vector3, "issued": bool}]
var squads: Array = []

var _think_timer:  float = 0.0
var _peace_timer:  float = 0.0
var _peace_over:   bool  = false
var _wave_index:   int   = 0
var _tactic: Dictionary  = {}
var _lake_taken: bool    = false
## Была ли у ИИ настоящая армия. Нужно для аварийного барака: на старте армия
## тоже равна нулю, и без этого флага ПЕРВЫЙ барак доставался бы бесплатно
var _had_army: bool      = false
## Диагностика для стенда QA — что ИИ сделал за последний тик
var last_action: String  = ""

func setup(p_main: Node3D) -> void:
	main = p_main
	reset()

func reset() -> void:
	squads.clear()
	_think_timer = 0.0
	_peace_timer = 0.0
	_peace_over  = _AICfg.PEACE_SECONDS <= 0.0
	_wave_index  = 0
	_tactic      = _AICfg.tactic_for_wave(0)
	_lake_taken  = false
	_had_army    = false
	_patrol_phase = 0
	_patrol_timer = 0.0
	last_stand   = false
	last_action  = ""

func _process(delta: float) -> void:
	if main == null:
		return
	if not _peace_over:
		_peace_timer += delta
		if _peace_timer >= _AICfg.PEACE_SECONDS:
			_peace_over = true
	# Смена патрульной точки идёт по СВОЕМУ таймеру, а не по такту размышления:
	# иначе патруль перескакивал бы на новую дугу каждые THINK_INTERVAL секунд
	# и никуда не доходил
	_patrol_timer += delta
	if _patrol_timer >= _AICfg.PATROL_DWELL:
		_patrol_timer = 0.0
		_patrol_phase += 1
	_think_timer += delta
	if _think_timer < _AICfg.THINK_INTERVAL:
		return
	_think_timer = 0.0
	tick()

# ─────────────────────────────────────────────────────────────────────────────
# ОДИН ТАКТ РАЗМЫШЛЕНИЯ
# ─────────────────────────────────────────────────────────────────────────────
func tick() -> void:
	last_action = ""
	var castle: Castle = _find_castle()
	_regroup()                    # разложить новых бойцов по отрядам
	if army_size() >= _AICfg.ARMY_LOST_THRESHOLD:
		_had_army = true           # с этого момента аварийный барак разрешён
	_auto_veteran()               # звёздочки отрядов раздаются сами
	_economy(castle)              # рабочие: добыча и найм
	if castle == null:
		return
	_construction(castle)         # барак, кузница, улучшения
	if not _peace_over:
		_hold_everyone_home(castle)
		return
	_train_army(castle)
	if _AICfg.DEFENSIVE_MODE:
		_command_squads_defensive(castle)
	else:
		_command_squads(castle)

# ─────────────────────────────────────────────────────────────────────────────
# ВЕТЕРАНСКИЕ НАГРАДЫ ИИ
# Отряд игрока получает окно выбора в интерфейсе; у ИИ интерфейса нет, и без
# этого его звёздочки копились неиспользованными — при равных числах в конфиге
# игрок получал преимущество просто потому, что ему есть куда нажать.
# Выбор идёт по списку предпочтений из конфига, а не случайно: поведение
# воспроизводимо и его видно в отчёте стенда.
# ─────────────────────────────────────────────────────────────────────────────
func _auto_veteran() -> void:
	if not _AICfg.AI_AUTO_VETERAN:
		return
	# squads_of_faction возвращает ЗАПИСИ отряда, а не идентификаторы —
	# номер лежит в поле "id"
	for s in GameManager.squads_of_faction(Constants.FACTION_ENEMY):
		var rec: Dictionary = s
		var sid: int = int(rec.get("id", 0))
		if sid <= 0:
			continue
		var unit_type: String = String(rec.get("type", ""))
		# Пока есть неразобранные уровни — берём по одному за такт-проход
		while GameManager.squad_pending(sid) > 0:
			var lvl: int = GameManager.squad_choosing_level(sid)
			var choices: Array = _UCfg.veteran_choices(unit_type, lvl)
			if choices.is_empty():
				break
			var pick := 0
			for want in _AICfg.AI_VETERAN_PREFERENCE:
				var found := -1
				for i in range(choices.size()):
					if String((choices[i] as Dictionary).get("stat", "")) == String(want):
						found = i
						break
				if found >= 0:
					pick = found
					break
			if not GameManager.apply_veteran_choice(sid, pick):
				break
			last_action += "|звезда отряду %d (%s)" % [sid,
				String((choices[pick] as Dictionary).get("stat", "?"))]

# ─────────────────────────────────────────────────────────────────────────────
# ОТРЯДЫ: сборка из свежих бойцов, чистка выбитых
# ─────────────────────────────────────────────────────────────────────────────

## Живые боевые юниты ИИ, ещё не попавшие ни в один отряд, распределяются
## по неполным отрядам своего типа; не хватило места — заводится новый отряд.
## Бойцы выходят из ворот по порядку, поэтому отряд собирается связным.
func _regroup() -> void:
	# 1) выбитых — вон, пустые отряды — расформировать
	var kept: Array = []
	for s in squads:
		var sq: Dictionary = s
		var alive: Array = []
		for m in sq["members"]:
			if is_instance_valid(m) and not m.is_dead():
				alive.append(m)
		if alive.is_empty():
			continue
		sq["members"] = alive
		kept.append(sq)
	squads = kept

	# 2) кто уже в отряде
	var assigned: Dictionary = {}
	for s in squads:
		var sq: Dictionary = s
		for m in sq["members"]:
			assigned[(m as Node).get_instance_id()] = true

	# 3) новобранцев — в неполные отряды своего типа
	for n in main.get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u is Worker or u.is_dead():
			continue
		if assigned.has(u.get_instance_id()):
			continue
		var uid: String = u.stat_id
		var want: int = _UCfg.squad_size(uid)
		var placed := false
		for s in squads:
			var sq: Dictionary = s
			if String(sq["type"]) != uid:
				continue
			if (sq["members"] as Array).size() >= want:
				continue
			(sq["members"] as Array).append(u)
			sq["issued"] = false     # состав изменился — приказ переиздать
			placed = true
			break
		if not placed:
			squads.append({
				"type": uid, "members": [u], "role": ROLE_GUARD,
				"target": u.global_position, "issued": false,
			})

## Сколько отрядов данного типа существует
func squad_count(unit_id: String) -> int:
	var n := 0
	for s in squads:
		if String((s as Dictionary)["type"]) == unit_id:
			n += 1
	return n

## Все боевые юниты ИИ в отрядах
func army_size() -> int:
	var n := 0
	for s in squads:
		n += ((s as Dictionary)["members"] as Array).size()
	return n

## Лимит набран по ВСЕМ типам — можно идти в общую атаку
func army_ready() -> bool:
	for t in _AICfg.combat_types():
		var uid: String = String(t)
		if squad_count(uid) < _AICfg.squad_limit(uid):
			return false
	return not squads.is_empty()

# ─────────────────────────────────────────────────────────────────────────────
# ЭКОНОМИКА
# ─────────────────────────────────────────────────────────────────────────────
func _economy(castle: Castle) -> void:
	var workers: Array = []
	for n in main.get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(n) and n is Worker and not (n as Worker).is_dead():
			workers.append(n)
	# простаивающий рабочий сразу идёт на ресурс
	for w in workers:
		var wk := w as Worker
		if wk.state == Unit.State.IDLE:
			_assign_worker(wk)
	if castle == null:
		return
	var queued := _queued_count(castle, "worker")
	if workers.size() + queued >= _AICfg.WORKER_LIMIT:
		return
	# Замок занят армией — рабочие ждут, КРОМЕ полного вымирания экономики
	if not castle.production_queue.is_empty() and workers.size() > 0:
		return
	if castle.train_worker():
		last_action += "|найм рабочего"
		return
	# Не хватило дерева, а добывать уже некому — один «беженец» бесплатно,
	# иначе ИИ навсегда залипает без экономики
	if workers.size() + queued == 0:
		castle.queue_unit("worker", {}, 8.0)
		last_action += "|бесплатный рабочий (экономика вымерла)"

func _assign_worker(w: Worker) -> void:
	var order := [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
				  Constants.RESOURCE_WOOD, Constants.RESOURCE_STONE]
	var start: int = w.get_instance_id() % order.size()
	for i in range(order.size()):
		var res_type: int = order[(start + i) % order.size()]
		# Тип указан явно: main объявлен как Node3D, поэтому := тут ничего не выводит
		var target: ResourceNode = main.find_nearest_resource(w.global_position, res_type)
		if target != null:
			w.command_gather(target)
			return

# ─────────────────────────────────────────────────────────────────────────────
# СТРОЙКА И ИССЛЕДОВАНИЯ
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# ИИ СТРОИТ ЧЕРЕЗ ФУНДАМЕНТ, КАК И ИГРОК
#
# Раньше здание ИИ появлялось ГОТОВЫМ прямо из вызова Barracks.new(): ни лесов,
# ни прогресса, ни рабочих — постройка возникала из воздуха за один кадр.
# Теперь ставится ConstructionSite (тот же класс, что у игрока), на него
# отправляется артель, и здание проходит все фазы стройки с растущим срубом
# внутри лесов. Побочно это выравнивает баланс: у ИИ постройка тоже занимает
# время и отвлекает рабочих от добычи.
# ─────────────────────────────────────────────────────────────────────────────
const _CSite := preload("res://scripts/ConstructionSite.gd")

## Сколько рабочих ИИ снимает с добычи на одну стройку
const BUILD_CREW := 3

## Идёт ли уже стройка этого здания (или любого, если id пуст)
func _site_in_progress(build_id: String = "") -> bool:
	for s in main.get_tree().get_nodes_in_group("construction_sites"):
		if not is_instance_valid(s):
			continue
		if (s as Building).faction != Constants.FACTION_ENEMY:
			continue
		if build_id.is_empty() or String(s.target_id) == build_id:
			return true
	return false

## Заложить фундамент и послать на него артель.
## free_build = true — ресурсы уже не списываются (аварийное восстановление)
func _start_site(build_id: String, at: Vector3, free_build: bool = false) -> bool:
	if not free_build:
		if not ResourceManager.spend(Constants.FACTION_ENEMY, _UCfg.building_cost(build_id)):
			return false
	var cfg: Dictionary = _UCfg.building_cfg(build_id)
	var site: Building = _CSite.new()
	site.faction     = Constants.FACTION_ENEMY
	site.target_id   = build_id
	site.target_name = String(cfg.get("name", build_id))
	site.build_time  = _UCfg.building_stat(build_id, "build_time", 12.0)
	site.build_size  = _UCfg.building_size(build_id)
	main.world_add(site)
	site.global_position = Vector3(at.x, main.get_terrain_height(at.x, at.z), at.z)
	# Артель: ближайшие к площадке рабочие
	var crew: Array = []
	for n in main.get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(n) and n is Worker and not (n as Worker).is_dead():
			crew.append(n)
	crew.sort_custom(func(a, b):
		return (a as Node3D).global_position.distance_squared_to(site.global_position) \
			< (b as Node3D).global_position.distance_squared_to(site.global_position))
	for i in range(mini(BUILD_CREW, crew.size())):
		(crew[i] as Worker).command_build(site)
	return true

func _construction(castle: Castle) -> void:
	var barracks: Building = null
	var smithy: Smithy = null
	for b in main.get_tree().get_nodes_in_group("enemy_buildings"):
		if not is_instance_valid(b):
			continue
		if b is Barracks:
			barracks = b as Building
		elif b is Smithy:
			smithy = b as Smithy

	# Одна стройка за раз: иначе ИИ закладывает фундаменты пачкой и снимает
	# с добычи всю экономику разом
	if _site_in_progress():
		return

	if barracks == null:
		# АВАРИЙНЫЙ БАРАК: без него ИИ не может нанимать пехоту вообще, поэтому
		# при потере армии он ставится в приоритете (и бесплатно, если разрешено)
		# «Армия потеряна» = она БЫЛА и её выбили. Первый барак партии всегда
		# покупается за ресурсы, как у игрока
		var broke: bool = _had_army and army_size() < _AICfg.ARMY_LOST_THRESHOLD
		var free_ok: bool = _AICfg.REBUILD_BARRACKS_FREE and broke
		# Барак — СО СТОРОНЫ ФРОНТА: отряды выходят из него лицом к противнику,
		# а не в тыловой угол карты
		var fdir := castle.front_dir()
		var side := Vector3(-fdir.z, 0.0, fdir.x)
		var spot: Vector3 = castle.global_position + fdir * 2.0 + side * 8.0
		if _start_site("barracks", spot, free_ok):
			last_action += "|заложен барак%s" % (" (бесплатно)" if free_ok else "")
		return

	if smithy == null:
		var fdir2 := castle.front_dir()
		var side2 := Vector3(-fdir2.z, 0.0, fdir2.x)
		var spot2: Vector3 = castle.global_position + fdir2 * 2.0 - side2 * 8.0
		if _start_site("smithy", spot2):
			last_action += "|заложена кузница"
		return

	for slot in _UCfg.UPGRADE_SLOTS:
		var d: Dictionary = slot
		var uid: String = String(d.get("id", ""))
		if GameManager.can_research(Constants.FACTION_ENEMY, uid):
			if smithy.research(uid):
				last_action += "|исследование %s" % uid
				return

# ─────────────────────────────────────────────────────────────────────────────
# НАЙМ ВОЙСК ДО ЛИМИТОВ
# ─────────────────────────────────────────────────────────────────────────────
## Сколько заказов этого типа ИИ уже оформил и ещё не получил на руки.
## Считает и очередь производства, и отряд, который ПРЯМО СЕЙЧАС выходит из
## ворот шеренгами (см. Building.in_progress_count): без второго слагаемого ИИ
## в этом окне видел заказ пропавшим и набирал лишние отряды сверх лимита
func _queued_count(bld: Building, unit_id: String) -> int:
	return bld.in_progress_count(unit_id)

## Сколько заказов у здания «в работе». НЕ длина очереди: между окончанием
## производства и выходом отряда из ворот очередь уже пуста, а отряда на карте
## ещё нет (выход идёт шеренгами, см. Building.ROW_RELEASE_SEC). В это окно ИИ
## считал себя свободным и ставил дубль — замер qa_ai показывал семь отрядов
## копейщиков при лимите в три
func _queued_orders(bld: Building) -> int:
	return bld.orders_in_progress()

func _train_army(castle: Castle) -> void:
	var barracks: Building = null
	for b in main.get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is Barracks:
			barracks = b as Building
			break

	# Пехота идёт из барака, рыцари — из замка: две очереди работают параллельно
	if barracks != null and _queued_orders(barracks) < _AICfg.MAX_QUEUED_ORDERS:
		var need := _most_needed(["spearman", "archer"], barracks)
		if need != "" and barracks.train_from_config(need):
			last_action += "|заказ отряда %s (барак)" % need

	if _queued_orders(castle) < _AICfg.MAX_QUEUED_ORDERS:
		var wneed := _most_needed(["warrior"], castle)
		if wneed != "" and castle.train_from_config(wneed):
			last_action += "|заказ отряда %s (замок)" % wneed

## Какой тип нужнее: у кого больше не хватает отрядов до лимита.
## Уже заказанные отряды учитываются, иначе ИИ ставит их пачкой.
func _most_needed(types: Array, bld: Building) -> String:
	var best := ""
	var best_gap := 0
	for t in types:
		var uid: String = String(t)
		var limit: int = _AICfg.squad_limit(uid)
		if limit <= 0:
			continue
		var have: int = squad_count(uid) + _queued_count(bld, uid)
		var gap: int = limit - have
		if gap > best_gap:
			best_gap = gap
			best = uid
	return best

# ─────────────────────────────────────────────────────────────────────────────
# ПРИКАЗЫ ОТРЯДАМ
# ─────────────────────────────────────────────────────────────────────────────

## Мирная фаза: всё стоит дома и никого не трогает
func _hold_everyone_home(castle: Castle) -> void:
	for i in range(squads.size()):
		_set_role(squads[i] as Dictionary, ROLE_GUARD,
			_guard_post(castle, i, squads.size()))
	_apply_orders()

func _command_squads(castle: Castle) -> void:
	var rally := _rally_point()
	var ready := army_ready()
	if ready and not _lake_taken:
		# Лимит набран — волна пошла. Тактика выбирается на волну
		_tactic = _AICfg.tactic_for_wave(_wave_index)

	# Проверка «центр карты взят»: своих у озера есть, боевых игрока — нет
	if _AICfg.PUSH_BASE_AFTER_LAKE_WIN:
		_lake_taken = _own_near(rally) > 0 and _player_combat_near(rally) == 0

	# Гарнизон: первые HOME_GUARD_PER_TYPE отрядов каждого типа
	var per_type: Dictionary = {}
	var home: Array = []
	var field: Array = []
	for s in squads:
		var sq: Dictionary = s
		var uid: String = String(sq["type"])
		var seen: int = int(per_type.get(uid, 0))
		per_type[uid] = seen + 1
		if seen < _AICfg.HOME_GUARD_PER_TYPE:
			home.append(sq)
		else:
			field.append(sq)

	# Куда идут излишки/волна
	var target_pos := rally
	var role := ROLE_FIELD
	if ready or _lake_taken:
		var base := _player_base_pos()
		if base != Vector3.ZERO:
			target_pos = base
			role = ROLE_ASSAULT
	elif not _AICfg.SEND_SURPLUS_TO_LAKE:
		# Излишки велено копить дома — они тоже встают на кольцо обороны
		for s in field:
			home.append(s)
		field = []

	# Посты раздаются, когда итоговое число домашних отрядов уже известно:
	# иначе индекс заворачивался по кругу и два отряда получали одну точку
	for i in range(home.size()):
		_set_role(home[i] as Dictionary, ROLE_GUARD,
			_guard_post(castle, i, home.size()))

	if field.is_empty():
		_apply_orders()
		return

	# Курс волны и раскладка по тактике
	var course := target_pos - castle.global_position
	course.y = 0.0
	if course.length() < 0.01:
		course = Vector3.FORWARD
	course = course.normalized()
	var right := Vector3(-course.z, 0.0, course.x)

	# Сколько отрядов каждого типа идёт в волне — нужно, чтобы развести их
	# в ЛИНИЮ, а не свалить все в одну точку (раньше 4 отряда копейщиков
	# получали одну и ту же цель и лезли друг на друга)
	var per_type_total: Dictionary = {}
	for s in field:
		var uid: String = String((s as Dictionary)["type"])
		per_type_total[uid] = int(per_type_total.get(uid, 0)) + 1

	var per_type_idx: Dictionary = {}
	for s in field:
		var sq: Dictionary = s
		var uid: String = String(sq["type"])
		var i: int = int(per_type_idx.get(uid, 0))
		per_type_idx[uid] = i + 1
		var n: int = int(per_type_total[uid])
		# Фланговые отряды одного типа делятся между левым и правым краем
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var off := _AICfg.tactic_offset(_tactic, uid, course, side)
		# Разнос по фронту внутри своего типа: центрируем ряд отрядов
		var centered: float = float(i) - float(n - 1) * 0.5
		off += right * (centered * SQUAD_LATERAL_STEP)
		_set_role(sq, role, target_pos + off)
	_apply_orders()

# ═════════════════════════════════════════════════════════════════════════════
# ОБОРОНИТЕЛЬНЫЙ РЕЖИМ (DEFENSIVE_MODE)
# ═════════════════════════════════════════════════════════════════════════════
# ИИ не ходит на базу игрока вовсе. Его задача — держать СВОЮ ПОЛОВИНУ КАРТЫ:
#   • HOME_GUARD_PER_TYPE отрядов каждого типа стоят кольцом у замка;
#   • PATROL_SQUADS отрядов ходят по кругу вдоль рубежа;
#   • всё остальное выстраивается ЗАСЛОНОМ поперёк направления на базу игрока,
#     на MAP_CONTROL_FRACTION пути от своего замка (при 0.5 — ровно центр карты,
#     то есть озеро).
# Контратака ограничена радиусом DEFENSE_ENGAGE_RADIUS вокруг рубежа: враг,
# зашедший в зону, получает бой, ушедший — не преследуется.
# ═════════════════════════════════════════════════════════════════════════════

## Точка рубежа обороны — на доле пути от своего замка к базе игрока
func _defense_center(castle: Castle) -> Vector3:
	if castle == null:
		return _rally_point()
	var base := _player_base_pos()
	if base == Vector3.ZERO:
		return _rally_point()
	var c := castle.global_position
	var p: Vector3 = c.lerp(base, clampf(_AICfg.MAP_CONTROL_FRACTION, 0.05, 0.95))
	p.y = 0.0
	# Рубеж не должен лечь в озеро: точка в воде недостижима
	return GameManager.land_target(p)

## Направление «на противника» от замка — вдоль него строится глубина заслона
func _defense_course(castle: Castle) -> Vector3:
	var base := _player_base_pos()
	if castle == null or base == Vector3.ZERO:
		return Vector3.FORWARD
	var course := base - castle.global_position
	course.y = 0.0
	if course.length() < 0.01:
		return Vector3.FORWARD
	return course.normalized()

# ═════════════════════════════════════════════════════════════════════════════
# ТАКТИЧЕСКИЙ СЦЕНАРИЙ 2: ПОСЛЕДНИЙ РУБЕЖ У ЗАМКА
# ═════════════════════════════════════════════════════════════════════════════
# Когда центр карты потерян и у игрока перевес, держать растянутый заслон
# посреди поля бессмысленно: его обходят и перемалывают по частям. ИИ отводит
# войска и собирает КОМПАКТНЫЙ порядок прямо перед своим замком:
#
#            ← фронт (на противника)
#     [рыцари]                          [рыцари]      ← фланги, манёвр
#          ██████ копейщики, стойка ЗАЩИТА ██████     ← щиты и фаланга
#                 ▒▒▒ лучники ▒▒▒                     ← за спиной пехоты
#                     [ЗАМОК]
#
# Копейщики в обороне держат фалангу и принимают удар, лучники стоят ЗА ними
# и стреляют из-за строя, рыцари стоят на флангах и оттуда же контратакуют.
# Как только противник входит в радиус контратаки, флангам разрешается бить —
# это и есть «плотная контратака» из задания.
# ═════════════════════════════════════════════════════════════════════════════

## Насколько силы игрока должны превосходить силы ИИ у рубежа, чтобы тот
## отступил к замку. 1.35 — «заметный перевес», а не случайный разведчик
const LAST_STAND_RATIO := 1.35
## Глубина построения перед замком, метры
const STAND_LINE_DIST  := 14.0   # шеренга копейщиков
const STAND_BOW_DIST   := 8.0    # лучники — ближе к замку, за спиной пехоты
const STAND_FLANK_DIST := 11.0   # рыцари — по краям
const STAND_FLANK_SIDE := 13.0   # разнос флангов от оси
## Ширина шеренги копейщиков, метры
const STAND_LINE_WIDTH := 20.0

## Идёт ли последний рубеж прямо сейчас (для отчёта стенда)
var last_stand: bool = false

## Центр потерян и у игрока перевес — пора отходить к замку.
## Гистерезис: выйти из режима труднее, чем войти, иначе ИИ метался бы между
## рубежом и замком на каждом такте размышления
func _should_last_stand(castle: Castle) -> bool:
	if castle == null:
		return false
	var center := _defense_center(castle)
	var mine: int = _own_near(center)
	var theirs: int = _player_combat_near(center)
	if last_stand:
		# Возвращаемся на рубеж, только когда противника там уже нет
		return theirs > 0
	if theirs <= 0:
		return false
	# Своих у рубежа не осталось вовсе — центр потерян
	if mine == 0:
		return true
	return float(theirs) >= float(mine) * LAST_STAND_RATIO

## Построение у замка: копейщики стеной, лучники за ними, рыцари по флангам
func _command_last_stand(castle: Castle) -> void:
	var course := _defense_course(castle)
	var right := Vector3(-course.z, 0.0, course.x)
	var home := castle.global_position

	# Раскладка по родам войск: у каждого своя линия и свой порядковый номер
	var idx: Dictionary = {}
	var total: Dictionary = {}
	for s in squads:
		var uid: String = String((s as Dictionary)["type"])
		total[uid] = int(total.get(uid, 0)) + 1

	for s in squads:
		var sq: Dictionary = s
		var uid: String = String(sq["type"])
		var i: int = int(idx.get(uid, 0))
		idx[uid] = i + 1
		var n: int = maxi(int(total.get(uid, 1)), 1)
		var centered: float = float(i) - float(n - 1) * 0.5
		var spot: Vector3
		match uid:
			"archer":
				# ЗА СПИНОЙ ПЕХОТЫ: стреляют из-за строя, сами под удар не идут
				spot = home + course * STAND_BOW_DIST \
					+ right * (centered * (STAND_LINE_WIDTH / float(n + 1)))
			"warrior":
				# ФЛАНГИ: рыцари чередуют левый и правый край
				var side: float = -1.0 if i % 2 == 0 else 1.0
				spot = home + course * STAND_FLANK_DIST \
					+ right * (side * STAND_FLANK_SIDE + centered * 2.0)
			_:
				# КОПЕЙЩИКИ — СТЕНА ЩИТОВ И ФАЛАНГА поперёк направления удара
				spot = home + course * STAND_LINE_DIST \
					+ right * (centered * (STAND_LINE_WIDTH / float(n)))
		_set_role(sq, ROLE_LINE, GameManager.land_target(spot))
	_apply_orders()

func _command_squads_defensive(castle: Castle) -> void:
	# СНАЧАЛА ПРОВЕРЯЕМ, НЕ ПОРА ЛИ ОТСТУПАТЬ. Потерянный центр и перевес
	# противника отменяют обычную раскладку по рубежу целиком
	last_stand = _should_last_stand(castle)
	if last_stand:
		_command_last_stand(castle)
		return
	var center := _defense_center(castle)
	var course := _defense_course(castle)
	var right := Vector3(-course.z, 0.0, course.x)

	# Раздача ролей: сначала домашний гарнизон, затем патрули, остальное — заслон
	var per_type: Dictionary = {}
	var home: Array = []
	var rest: Array = []
	for s in squads:
		var sq: Dictionary = s
		var uid: String = String(sq["type"])
		var seen: int = int(per_type.get(uid, 0))
		per_type[uid] = seen + 1
		if seen < _AICfg.HOME_GUARD_PER_TYPE:
			home.append(sq)
		else:
			rest.append(sq)

	for i in range(home.size()):
		_set_role(home[i] as Dictionary, ROLE_GUARD, _guard_post(castle, i, home.size()))

	# ЗАСЛОН ВАЖНЕЕ ПАТРУЛЕЙ: в патруль уходит не больше половины излишков.
	# Без этой доли при четырёх свободных отрядах трое уходили гулять и рубеж
	# держал один-единственный отряд
	var patrols: int = mini(_AICfg.PATROL_SQUADS, rest.size() / 2)
	# Заслон строится по ширине рубежа, патрули ходят по кругу вокруг него
	var line_count: int = rest.size() - patrols
	for i in range(rest.size()):
		var sq: Dictionary = rest[i]
		if i < line_count:
			# ЗАСЛОН: отряды растянуты поперёк курса, с шагом по ширине рубежа
			var centered: float = float(i) - float(maxi(line_count - 1, 1)) * 0.5
			var step: float = _AICfg.DEFENSE_LINE_WIDTH / float(maxi(line_count, 1))
			var off := right * (centered * step)
			# Глубина по типу войск — та же раскладка, что и у тактик атаки
			off += _AICfg.tactic_offset(_tactic, String(sq["type"]), course, 0.0)
			_set_role(sq, ROLE_LINE, GameManager.land_target(center + off))
		else:
			# ПАТРУЛЬ: точка на дуге ПЕРЕД рубежом, смена по таймеру
			var pi: int = i - line_count
			_set_role(sq, ROLE_PATROL, _patrol_point(center, pi, patrols, course))
	_apply_orders()

## ── ПАТРУЛЬ ХОДИТ ТОЛЬКО ПО ФРОНТОВОЙ ЗОНЕ ──────────────────────────────────
## Раньше патрульные точки лежали на ПОЛНОМ круге вокруг рубежа. Половина
## этого круга — собственный тыл ИИ, то есть угол карты с густым лесным
## массивом за крепостью: отряды исправно уходили туда, вставали среди
## деревьев и возвращались только через PATROL_DWELL. Со стороны это и есть
## «войска ИИ уходят и застревают в лесу за крепостью».
##
## Теперь патруль ходит по ДУГЕ ПЕРЕД рубежом — в секторе ±PATROL_ARC_DEG
## вокруг направления на противника. Тыл не патрулируется вовсе: там некого
## встречать, а лес только ломает строй.
##
## course — единичное направление «на противника».
const PATROL_ARC_DEG := 65.0

func _patrol_point(center: Vector3, idx: int, total: int, course: Vector3) -> Vector3:
	var steps := 4                      # четыре точки на дугу
	var slot: int = int(_patrol_phase) % steps
	# Базовый угол сектора: разводим отряды по ширине фронта
	var arc := deg_to_rad(PATROL_ARC_DEG)
	var span: float = arc * 2.0
	var t_idx: float = (float(idx) + 0.5) / float(maxi(total, 1))
	var t_slot: float = float(slot) / float(steps)
	# Смещение по времени вдвое мельче, чем разнос между отрядами: каждый
	# ходит вдоль СВОЕГО участка фронта, а не пересекает чужие
	var off: float = -arc + span * t_idx + (span / float(maxi(total, 1))) * (t_slot - 0.5)
	var dir := course.rotated(Vector3.UP, off)
	var p := center + dir * _AICfg.PATROL_RADIUS
	p.y = 0.0
	return GameManager.land_target(p)

## Фаза патрулирования: растёт раз в PATROL_DWELL секунд
var _patrol_phase: int   = 0
var _patrol_timer: float = 0.0

## Есть ли противник в зоне ответственности рубежа
func _intruder_near(center: Vector3) -> bool:
	var r: float = _AICfg.DEFENSE_ENGAGE_RADIUS
	for u in main.get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		if (u as Node3D).global_position.distance_to(center) <= r:
			return true
	return false

## Позиция гарнизонного отряда: кольцо вокруг замка.
## Кольцо делится по ФАКТИЧЕСКОМУ числу отрядов, стоящих дома (guard_count),
## а не по лимиту из конфига: при SEND_SURPLUS_TO_LAKE=false домой садятся ВСЕ
## отряды, и индекс поста заворачивался по кругу — два отряда получали одну и
## ту же точку и лезли друг на друга.
## guard_count <= 0 — запасной путь: делим по числу из конфига.
func _guard_post(castle: Castle, idx: int, guard_count: int = 0) -> Vector3:
	if castle == null:
		return Vector3.ZERO
	var total: int = guard_count
	if total <= 0:
		total = _AICfg.combat_types().size() * _AICfg.HOME_GUARD_PER_TYPE
	total = maxi(total, 3)
	var ang: float = TAU * float(idx) / float(total) - TAU * 0.25
	var c := castle.global_position
	return Vector3(c.x + cos(ang) * GUARD_RING, 0.0, c.z + sin(ang) * GUARD_RING)

## Смена роли/цели помечает отряд как «надо переиздать приказ».
## Без этого приказ уходил бы каждый такт и сбивал бойцов с пути.
func _set_role(sq: Dictionary, role: String, target: Vector3) -> void:
	var moved: bool = (sq["target"] as Vector3).distance_to(target) > 2.0
	if String(sq["role"]) != role or moved:
		sq["role"]   = role
		sq["target"] = target
		sq["issued"] = false

## Разрешено ли ЭТОМУ отряду срываться с поста ради контратаки.
## В обычной обороне — всем. На последнем рубеже у замка — только рыцарям:
## иначе построение, ради которого войска и отводились, рассыпается сразу же
func _may_counter_attack(sq: Dictionary) -> bool:
	if not last_stand:
		return true
	return String(sq["type"]) == "warrior"

func _apply_orders() -> void:
	for s in squads:
		var sq: Dictionary = s
		var members: Array = sq["members"]
		if members.is_empty():
			continue
		var role: String = String(sq["role"])
		# Стойка: гарнизон и заслон держат строй, патруль/поле/штурм — в атаке.
		# Заслону приказ «атаковать» НЕ выдаётся сознательно: прямой приказ
		# переводит бойца в стойку АТАКА (см. Unit.command_attack), и рубеж
		# расползся бы вслед за первым же забредшим разведчиком. Стойка ЗАЩИТА
		# сама бьёт всё, до чего дотягивается, оставаясь на месте
		var holds: bool = (role == ROLE_GUARD or role == ROLE_LINE)
		# ─── КОНТРАТАКА ──────────────────────────────────────────────────────
		# ИИ больше не изображает статую. Заслон и патруль ДЕРЖАТ рубеж, пока
		# вокруг тихо, но стоит противнику войти в зону — вся секция снимается
		# с поста и дерётся, а не ждёт, пока её обойдут и перебьют по одному.
		# Раньше «оборона» означала «никогда не атаковать», и отряды стояли
		# столбами, пока рядом шла резня.
		#
		# НА ПОСЛЕДНЕМ РУБЕЖЕ КОНТРАТАКУЮТ НЕ ВСЕ. Если бы вся армия срывалась
		# с мест при появлении противника, построение у замка (стена копейщиков,
		# лучники за ней, рыцари по флангам) рассыпалось бы в ту же секунду,
		# ради чего его и строили. Поэтому с поста снимаются ТОЛЬКО рыцари —
		# это и есть манёвр флангами; копейщики держат стену, лучники бьют
		# из-за неё, не сходя с места
		var threat: Node3D = null
		if _AICfg.AI_COUNTER_ATTACK and _may_counter_attack(sq):
			var anchor: Vector3 = _squad_centroid(members)
			threat = _nearest_player_target(anchor, _AICfg.DEFENSE_ENGAGE_RADIUS)
		if threat != null:
			holds = false
		var stance: String = _UCfg.STANCE_DEFENSE if holds else _UCfg.STANCE_ATTACK
		var need_issue: bool = not bool(sq["issued"])
		if not need_issue:
			# Приказ уже отдан: подтолкнуть только тех, кто встал без дела
			var idle := 0
			for m in members:
				if (m as Unit).state == Unit.State.IDLE:
					idle += 1
			if idle * 2 < members.size():
				continue
		sq["issued"] = true
		var center: Vector3 = sq["target"]
		var course := _order_course(members, center)
		for i in range(members.size()):
			var u := members[i] as Unit
			if not is_instance_valid(u) or u.is_dead():
				continue
			if u.stance != stance:
				u.set_stance(stance)
			var col: int = i % SQUAD_COLS
			var row: int = i / SQUAD_COLS
			var off_x: float = (float(col) - float(SQUAD_COLS - 1) * 0.5) * SQUAD_SPACING
			var off_z: float = float(row) * SQUAD_SPACING
			u.formation_row = row
			if threat != null:
				# ПРОТИВНИК В ЗОНЕ — ДЕРЁМСЯ ВСЕЙ СЕКЦИЕЙ. Цель берётся своя для
				# каждого бойца (см. Unit.command_attack: приказ разворачивается
				# по вражескому отряду), поэтому секция не сваливается на одного
				var own := _nearest_player_target(u.global_position,
					_AICfg.DEFENSE_ENGAGE_RADIUS * 1.5)
				u.command_attack(own if own != null else threat, true, true)
			elif holds:
				# Вокруг тихо: гарнизон и заслон встают на пост и держат его
				u.command_move(center + Vector3(off_x, 0.0, off_z), false, course)
			elif role == ROLE_PATROL:
				# Патруль обходит свою дугу; в бой втягивается авто-агро
				u.command_move(center + Vector3(off_x, 0.0, off_z), true, course)
			else:
				var foe := _nearest_player_target(u.global_position, 24.0)
				if foe != null:
					u.command_attack(foe, true, true)
				else:
					u.command_move(center + Vector3(off_x, 0.0, off_z), false, course)

## Середина секции — от неё и считается «есть ли враг в зоне»
func _squad_centroid(members: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for m in members:
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		c += u.global_position
		n += 1
	return c / float(n) if n > 0 else Vector3.ZERO

func _order_course(members: Array, center: Vector3) -> Vector3:
	var centroid := Vector3.ZERO
	for m in members:
		centroid += (m as Node3D).global_position
	centroid /= float(members.size())
	var course := center - centroid
	course.y = 0.0
	if course.length() < 0.01:
		return Vector3.ZERO
	return course.normalized()

# ─────────────────────────────────────────────────────────────────────────────
# ЦЕЛИ И ЗАМЕРЫ ОБСТАНОВКИ
# ─────────────────────────────────────────────────────────────────────────────
func _find_castle() -> Castle:
	for b in main.get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is Castle:
			return b as Castle
	return null

## Точка сбора «в поле». Берётся у Main методом, а не через константу класса:
## EnemyAI подключается в Main через preload, и обратная ссылка на класс Main
## замкнула бы зависимость файлов друг на друга
func _rally_point() -> Vector3:
	if _AICfg.USE_LAKE_AS_RALLY and main.has_method("ai_rally_point"):
		var p: Vector3 = main.ai_rally_point()
		return p
	return _AICfg.RALLY_POINT_OVERRIDE

func _player_base_pos() -> Vector3:
	for b in main.get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b is Castle:
			return (b as Node3D).global_position
	for b in main.get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b):
			return (b as Node3D).global_position
	for u in main.get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(u):
			return (u as Node3D).global_position
	return Vector3.ZERO

func _own_near(pos: Vector3) -> int:
	var r: float = _AICfg.LAKE_CONTEST_RADIUS
	var n := 0
	for s in squads:
		for m in (s as Dictionary)["members"]:
			if is_instance_valid(m) and (m as Node3D).global_position.distance_to(pos) <= r:
				n += 1
	return n

func _player_combat_near(pos: Vector3) -> int:
	var r: float = _AICfg.LAKE_CONTEST_RADIUS
	var n := 0
	for u in main.get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(u) or u is Worker:
			continue
		if (u as Unit).is_dead():
			continue
		if (u as Node3D).global_position.distance_to(pos) <= r:
			n += 1
	return n

func _nearest_player_target(from: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for grp in ["player_units", "player_buildings"]:
		for n in main.get_tree().get_nodes_in_group(String(grp)):
			if not is_instance_valid(n):
				continue
			if n.has_method("is_dead") and n.is_dead():
				continue
			var d: float = from.distance_to((n as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = n as Node3D
	return best

# ─────────────────────────────────────────────────────────────────────────────
# ДИАГНОСТИКА (используется стендом QA)
# ─────────────────────────────────────────────────────────────────────────────
func report() -> String:
	var parts: Array = []
	for t in _AICfg.combat_types():
		var uid: String = String(t)
		parts.append("%s %d/%d" % [uid, squad_count(uid), _AICfg.squad_limit(uid)])
	var roles: Dictionary = {}
	for s in squads:
		var r: String = String((s as Dictionary)["role"])
		roles[r] = int(roles.get(r, 0)) + 1
	return "режим=%s | отряды: %s | бойцов=%d | роли=%s | лимит набран=%s | тактика=%s | озеро взято=%s | последний рубеж=%s" % [
		"оборона" if _AICfg.DEFENSIVE_MODE else "атака",
		", ".join(parts), army_size(), str(roles), str(army_ready()),
		String(_tactic.get("id", "-")), str(_lake_taken), str(last_stand)]
