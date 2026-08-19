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
const _FCfg  := preload("res://scripts/forge_config.gd")

## Роли отряда
const ROLE_GUARD   := "guard"     # стоит у замка в обороне
const ROLE_FIELD   := "field"     # отправлен драться к озеру
const ROLE_ASSAULT := "assault"   # идёт на базу игрока
const ROLE_LINE    := "line"      # держит рубеж обороны (DEFENSIVE_MODE)
const ROLE_PATROL  := "patrol"    # ходит по своей территории (DEFENSIVE_MODE)
## ── ТАКТИЧЕСКИЕ РОЛИ, ПЕРЕБИВАЮЩИЕ ОПЕРАТИВНЫЕ ──────────────────────────────
## Роли выше отвечают на вопрос «где этому отряду быть по плану кампании».
## Три роли ниже отвечают на «что делать прямо сейчас» и назначаются ПОВЕРХ
## плана каждый такт (см. _tactical_overrides): обстановка меняется быстрее,
## чем план, и отряд, который вот-вот вырежут, не должен упрямо идти в свою
## точку на рубеже
const ROLE_FLANK   := "flank"     # мечники обходят строй и идут в тыл, к стрелкам
const ROLE_KITE    := "kite"      # лучники отходят за спину своей пехоты
const ROLE_RETREAT := "retreat"   # отряд выбит и уходит на восстановление в замок

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
## Волна уже вышла (собралась на точке сбора и получила приказ на атаку)
var _wave_out: bool      = false

## Собралась ли волна на точке сбора. Считается по центрам отрядов, а не по
## каждому бойцу: отряд приходит целиком, и его центр — честный ответ
func _mustered(field: Array, rally: Vector3) -> bool:
	if field.is_empty():
		return false
	var r2: float = _AICfg.MUSTER_RADIUS * _AICfg.MUSTER_RADIUS
	var at := 0
	for s in field:
		var c := _squad_centroid((s as Dictionary)["members"])
		if c == Vector3.ZERO:
			continue
		var dx: float = c.x - rally.x
		var dz: float = c.z - rally.z
		if dx * dx + dz * dz <= r2:
			at += 1
	return float(at) >= float(field.size()) * _AICfg.MUSTER_FRACTION

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
	_wave_out    = false
	_home_pos    = Vector3.ZERO
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
	# Недоразданные приказы прошлого такта — по порции за кадр (см. _drain_orders)
	_drain_orders()
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
	# Снимок зданий игрока на весь такт: дальше его читает _nearest_player_target
	# вместо копирования группы на каждый запрос
	_refresh_target_cache()
	var castle: Castle = _find_castle()
	_regroup()                    # разложить новых бойцов по отрядам
	if army_size() >= _AICfg.ARMY_LOST_THRESHOLD:
		_had_army = true           # с этого момента аварийный барак разрешён
	_auto_veteran()               # звёздочки отрядов раздаются сами
	_economy(castle)              # рабочие: добыча и найм
	if castle == null:
		# ── ЗАМОК ПАЛ ────────────────────────────────────────────────────────
		# Раньше такт просто заканчивался здесь: ИИ переставал отдавать приказы
		# ВООБЩЕ. Отряды замирали там, где их застало падение крепости, а те,
		# кого уже отправили в гарнизон, шли к воротам, которых больше нет.
		_no_castle()
		return
	_home_pos = castle.global_position
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
			# ГАРНИЗОННЫЕ ВЫБЫВАЮТ ИЗ СОСТАВА НАРАВНЕ С УБИТЫМИ. Отряд, ушедший
			# в замок на восстановление, физически ещё жив, но с карты снят
			# (Castle.absorb_unit гасит его и выводит из отрисовки) — оставь его
			# в составе, и ИИ вечно числил бы роль «отход», раздавал бы посты
			# невидимкам и не набирал бы замену. Вернувшихся из замка подберёт
			# шаг 3 этой же функции, как обычное пополнение
			if is_instance_valid(m) and not m.is_dead() and not (m as Unit).garrisoned:
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
		if u == null or u is Worker or u.is_dead() or u.garrisoned:
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
				# Сторона обхода закрепляется за отрядом ОДИН РАЗ, при рождении.
				# Считай её каждый такт — два отряда мечников менялись бы краями
				# и топтались бы на месте вместо обхода (см. _try_flank)
				"flank_side": squad_count(uid) % 2,
				"flank_close": false,
				"peak": 0,
			})

	# 4) ПИК ЧИСЛЕННОСТИ — ЗНАМЕНАТЕЛЬ БОЕСПОСОБНОСТИ (см. _squad_strength).
	# Считается ПОСЛЕ добора новобранцев, а не в первом проходе: отряд, собранный
	# только что, в первом проходе ещё не существовал, и его пик остался бы
	# единицей до следующего такта. Практическая цена такой задержки — не
	# косметика: возьми отряд потери в это самое окно, и пик записался бы уже
	# УМЕНЬШЕННЫМ, то есть разгромленный отряд навсегда считался бы целым и
	# никогда не ушёл бы на восстановление. Стенд поймал это как «боеспособность
	# 60.00» у только что собранных шестидесяти копейщиков.
	# Пик только растёт: отряд обязан помнить, каким он был
	for s in squads:
		var sq2: Dictionary = s
		sq2["peak"] = maxi(int(sq2.get("peak", 0)), (sq2["members"] as Array).size())

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

# ═════════════════════════════════════════════════════════════════════════════
# ЗАМОК ПАЛ: ОТСТРАИВАЕМСЯ И ДЕРЁМСЯ НА РУИНАХ
# ═════════════════════════════════════════════════════════════════════════════
# Два требования владельца, и оба про один момент — потерю крепости:
#   • рабочие пытаются заложить НОВУЮ неподалёку, если есть на что;
#   • защитники держатся у руин и дерутся до последнего, а не разбредаются.
#
# Второе делается НЕ новым кодом, а тем, который уже есть: _command_last_stand
# строит последний рубеж вокруг точки — стена копий фронтом, лучники за спиной,
# рыцари по флангам. Единственное, чего ему не хватало, — замка как якоря;
# теперь якорем служит запомненное место базы (_home_pos).
#
# Отход при этом запрещён в принципе: уходить некуда, а режим отхода глушит и
# авто-агро, и ответный удар — отряд просто шёл бы умирать молча (см.
# _try_retreat).

## Место своей базы. Пишется каждый такт, пока замок жив, и переживает его
var _home_pos: Vector3 = Vector3.ZERO

func _no_castle() -> void:
	last_action += "|ЗАМОК ПОТЕРЯН"
	var anchor: Vector3 = _home_pos if _home_pos != Vector3.ZERO else _rally_point()
	# ── 1. НОВАЯ КРЕПОСТЬ, ЕСЛИ ЕСТЬ НА ЧТО ────────────────────────────────
	# Одна стройка за раз — общее правило ИИ. Площадка берётся чуть в стороне от
	# руин: на самих руинах стоит коллайдер обломков
	if not _site_in_progress():
		var cost: Dictionary = _UCfg.building_cost("castle")
		if ResourceManager.can_afford(Constants.FACTION_ENEMY, cost):
			var spot: Vector3 = GameManager.land_target(
				anchor + Vector3(CASTLE_REBUILD_OFFSET, 0.0, CASTLE_REBUILD_OFFSET))
			if _start_site("castle", spot):
				last_action += "|закладывается новая крепость"
	# ── 2. ПОСЛЕДНИЙ РУБЕЖ У РУИН ──────────────────────────────────────────
	last_stand = true
	_command_last_stand_at(anchor)

## Насколько в сторону от руин закладывается новая крепость, м
const CASTLE_REBUILD_OFFSET := 9.0

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

	_research_forge(smithy)
	_buy_squad_abilities()

# ═════════════════════════════════════════════════════════════════════════════
# СПОСОБНОСТИ-РЕЖИМЫ: ДОКУПИТЬ И ВКЛЮЧИТЬ
# ═════════════════════════════════════════════════════════════════════════════
# Двухступенчатая схема (исследование фракции + покупка отрядом) у игрока
# замыкается кликом по панели. У ИИ панели нет, и без этого прохода он честно
# исследовал бы «Залповый огонь» и не применил его ни разу.
#
# Включаем СРАЗУ после покупки: выбор «залпом или вразнобой» — это тактика на
# уровне, до которого ИИ не поднимался ни в одной другой механике, а залп по
# плотному строю выгоден почти всегда. Если понадобится разбор «когда выгодно» —
# это будет отдельное решение с отдельным замером, а не догадка здесь
func _buy_squad_abilities() -> void:
	if not _AICfg.AI_BUY_SQUAD_ABILITIES:
		return
	for sq in GameManager.squads_of_faction(Constants.FACTION_ENEMY):
		var d: Dictionary = sq
		var sid: int = int(d.get("id", 0))
		var uid: String = String(d.get("type", ""))
		if sid <= 0 or uid.is_empty():
			continue
		var node: Dictionary = _FCfg.toggle_ability_of(uid)
		if node.is_empty():
			continue
		var nid: String = String(node.get("id", ""))
		if not GameManager.is_researched(Constants.FACTION_ENEMY, nid):
			continue
		if not GameManager.squad_has_ability(sid, nid):
			# Резерв: прокачанный режим у трёх отрядов хуже, чем пополнение
			var gold: float = ResourceManager.get_amount(
				Constants.FACTION_ENEMY, Constants.RESOURCE_GOLD)
			var cost: float = _FCfg.squad_unlock_cost(node)
			if gold - cost <= _AICfg.AI_ABILITY_GOLD_RESERVE:
				continue
			if not GameManager.squad_buy_ability(sid, nid):
				continue
			last_action += "|куплен режим %s отряду %d" % [nid, sid]
		if not GameManager.squad_ability_on(sid, nid):
			GameManager.squad_set_ability(sid, nid, true)

# ═════════════════════════════════════════════════════════════════════════════
# ДРЕВО КУЗНИЦЫ: ИИ ТОЖЕ УЧИТСЯ
# ═════════════════════════════════════════════════════════════════════════════
# Здесь была дыра, а не недоработка баланса. Цикл выше перебирает ПЛОСКИЕ слоты
# (_UCfg.UPGRADE_SLOTS) — наследство от старой кузницы, там всего несколько
# позиций, причём первая из них навсегда закрыта заглушкой "requires" (см.
# CLAUDE.md, «Never index UPGRADE_SLOTS[0]»). Вся настоящая наука переехала в
# древо (forge_config: 4 рода войск × 20 узлов), и ИИ не покупал из неё НИЧЕГО.
# На длинной партии это означало прокачанного игрока против ИИ с базовыми
# характеристиками — и списывалось на «ИИ слабый», хотя механика просто не была
# ему подключена.
#
# Узел древа И ЕСТЬ слот улучшения: _UCfg.get_upgrade_slot() падает в
# forge_config.get_node(), поэтому ни Smithy.research, ни GameManager.can_research
# менять не пришлось — доступность, цена, очередь и накопление бонусов работают
# ровно так же, как у игрока.
func _research_forge(smithy: Smithy) -> void:
	if not _AICfg.AI_RESEARCH_FORGE or smithy == null:
		return
	# Резерв на найм: прокачанная армия из трёх человек проигрывает
	# необученной из тридцати
	if ResourceManager.get_amount(Constants.FACTION_ENEMY, Constants.RESOURCE_GOLD) \
			<= _AICfg.AI_RESEARCH_GOLD_RESERVE:
		return
	var best_id := ""
	var best_score := 0.0
	# Только те рода войск, которые ИИ реально нанимает: качать ветку монаха,
	# которого нет в SQUAD_LIMIT, — это выкинутое золото. Плюс экономические
	# ветки из AI_FORGE_EXTRA_BRANCHES: рабочий в combat_types() не значится, но
	# он есть у ИИ всегда и с первой минуты
	var branches: Array = _AICfg.combat_types().duplicate()
	branches.append_array(_AICfg.AI_FORGE_EXTRA_BRANCHES)
	for t in branches:
		var uid: String = String(t)
		for n in _FCfg.tree(uid):
			var node: Dictionary = n
			var nid: String = String(node.get("id", ""))
			if nid.is_empty():
				continue
			# can_research сам проверит и предпосылки, и «весь ряд» у колонки D,
			# и то, что узел не куплен и не в очереди
			if not GameManager.can_research(Constants.FACTION_ENEMY, nid):
				continue
			var score := 0.0
			for key in _AICfg.AI_FORGE_WEIGHTS:
				score += float(node.get(String(key), 0.0)) * float(_AICfg.AI_FORGE_WEIGHTS[key])
			if score <= 0.0:
				continue
			# Дешёвое при равной пользе предпочтительнее: делим на цену золота,
			# чтобы ИИ шёл по древу снизу вверх, а не упирался в дорогой узел
			var gold: float = maxf(float(node.get("cost_gold", 0.0)), 1.0)
			score /= gold
			if score > best_score:
				best_score = score
				best_id    = nid
	if best_id.is_empty():
		return
	if smithy.research(best_id):
		last_action += "|исследование древа %s" % best_id

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
	_assign_home_posts(castle, squads)
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

	# ── СБОР ПЕРЕД АТАКОЙ ───────────────────────────────────────────────────
	# Лимит набран — это ещё не волна: отряды в этот момент могут быть
	# размазаны от барака до озера. Пока на точке сбора не собралась
	# MUSTER_FRACTION волны, все идут К НЕЙ, а не на базу игрока.
	# Защёлка _wave_out нужна, чтобы уже вышедшая волна не разворачивалась
	# обратно, когда доля просядет из-за потерь
	if _AICfg.AI_MUSTER_BEFORE_ATTACK and not _wave_out:
		if (ready or _lake_taken) and _mustered(field, rally):
			_wave_out = true
			last_action += "|волна собрана, общий выход"
	if field.is_empty():
		_wave_out = false          # волны нет — сбор начинается заново
	var attacking: bool = (ready or _lake_taken) 		and (_wave_out or not _AICfg.AI_MUSTER_BEFORE_ATTACK)

	# Куда идут излишки/волна
	var target_pos := rally
	var role := ROLE_FIELD
	if attacking:
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
	_assign_home_posts(castle, home)

	if field.is_empty():
		_apply_orders()
		return

	# ── ФРОНТОМ К АРМИИ ИГРОКА, А НЕ К ЕГО ЗДАНИЮ ───────────────────────────
	# Курс задаёт ориентацию ВСЕГО боевого порядка: по нему считаются и глубина
	# эшелонов, и разнос флангов, и направление взгляда каждого отряда. Пока он
	# брался от замка к замку, стена копий могла встретить армию боком — лучники
	# оказывались не за спинами своих, а сбоку. Точка прицеливания ищется от
	# ЦЕНТРА МАСС ВОЛНЫ и по уже собранной за этот кадр сетке, то есть стоит
	# один скан на такт, а не обход групп
	var wave_c := _field_centroid(field)
	if attacking and _AICfg.AI_FACE_PLAYER_ARMY and wave_c != Vector3.ZERO:
		var seen = GameManager.army.nearest_of_side(wave_c.x, wave_c.z,
			Constants.FACTION_PLAYER, _AICfg.ARMY_AIM_RADIUS)
		if seen != null:
			target_pos = (seen as Node3D).global_position
			last_action += "|строй фронтом к армии игрока"
	# Курс волны и раскладка по тактике
	var course := target_pos - (wave_c if wave_c != Vector3.ZERO else castle.global_position)
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
## Курс «на противника» от произвольной точки. Замка может не быть вовсе
func _course_from(home: Vector3) -> Vector3:
	var base := _player_base_pos()
	var c := base - home
	c.y = 0.0
	if c.length() < 0.01:
		return Vector3.FORWARD
	return c.normalized()

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
	_command_last_stand_at(castle.global_position)

## Тот же последний рубеж, но вокруг ПРОИЗВОЛЬНОЙ точки: замка может уже не
## быть (см. _no_castle), а рубеж всё равно нужен
func _command_last_stand_at(home: Vector3) -> void:
	var course := _course_from(home)
	var right := Vector3(-course.z, 0.0, course.x)

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

	_assign_home_posts(castle, home)

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
# ═════════════════════════════════════════════════════════════════════════════
# ЗАСЛОН У БАЗЫ: ГАРНИЗОН СТОИТ СТРОЕМ, А НЕ КОЛЬЦОМ
# ═════════════════════════════════════════════════════════════════════════════
# _guard_post раздавал точки по ОКРУЖНОСТИ вокруг замка, одинаково всем родам
# войск. Половина гарнизона при этом стояла в тылу, спиной к противнику, а
# лучники с равной вероятностью оказывались перед копейщиками — то есть первыми
# под удар шли те, кому в ближнем бою нечем ответить.
#
# Теперь домашний гарнизон строится ЛИЦОМ к базе игрока:
#
#            ← фронт (на противника)
#     [мечники]                        [мечники]     ← фланги, манёвр
#         ██████ копейщики, ЗАЩИТА ██████            ← щиты и фаланга
#                ▒▒▒ лучники ▒▒▒                     ← за спинами пехоты
#                    [ЗАМОК]
#
# Это та же раскладка, что у последнего рубежа (_command_last_stand), и это
# намеренно: построение у своих стен не должно зависеть от того, каким путём ИИ
# в него пришёл — плановым гарнизоном или отходом под давлением.
#
# Номер отряда здесь ПО СВОЕМУ РОДУ ВОЙСК, а не сквозной: сквозной разносил бы
# три копейщика и одного лучника по одной шкале, и лучник вставал бы на край
# копейной шеренги
func _assign_home_posts(castle: Castle, home: Array) -> void:
	if castle == null:
		return
	if not _AICfg.AI_BASE_SCREEN:
		for i in range(home.size()):
			_set_role(home[i] as Dictionary, ROLE_GUARD,
				_guard_post(castle, i, home.size()))
		return
	var total: Dictionary = {}
	for s in home:
		var uid: String = String((s as Dictionary)["type"])
		total[uid] = int(total.get(uid, 0)) + 1
	var idx: Dictionary = {}
	for s in home:
		var sq: Dictionary = s
		var uid2: String = String(sq["type"])
		var i2: int = int(idx.get(uid2, 0))
		idx[uid2] = i2 + 1
		_set_role(sq, ROLE_GUARD,
			_screen_post(castle, uid2, i2, int(total.get(uid2, 1))))

## Точка заслона для отряда рода `uid`, номер `idx` из `count` отрядов этого рода
func _screen_post(castle: Castle, uid: String, idx: int, count: int) -> Vector3:
	var course := _defense_course(castle)
	var right := Vector3(-course.z, 0.0, course.x)
	var home := castle.global_position
	var n: int = maxi(count, 1)
	var centered: float = float(idx) - float(n - 1) * 0.5
	var spot: Vector3
	match uid:
		"archer":
			spot = home + course * _AICfg.SCREEN_BOW_DIST \
				+ right * (centered * (_AICfg.SCREEN_WIDTH / float(n + 1)))
		"warrior":
			var side: float = -1.0 if idx % 2 == 0 else 1.0
			spot = home + course * _AICfg.SCREEN_FLANK_DIST \
				+ right * (side * _AICfg.SCREEN_FLANK_SIDE + centered * 2.0)
		_:
			# Копейщики и всё прочее ближнего боя — стена перед зданиями
			spot = home + course * _AICfg.SCREEN_SPEAR_DIST \
				+ right * (centered * (_AICfg.SCREEN_WIDTH / float(n)))
	return GameManager.land_target(spot)

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

# ═════════════════════════════════════════════════════════════════════════════
# ТАКТИЧЕСКИЙ СЛОЙ: ЧТО ДЕЛАТЬ ПРЯМО СЕЙЧАС
# ═════════════════════════════════════════════════════════════════════════════
# Считается РАЗ В ТАКТ (THINK_INTERVAL = 2 с) и РАЗ НА ОТРЯД — не на бойца.
# Армия ИИ это десяток отрядов; те же решения, посчитанные поимённо, стоили бы
# в двадцать раз дороже и не изменили бы ни одного из них: отступает, обходит и
# прячется отряд целиком, а не отдельный человек.
#
# Вызывается из _apply_orders, а не из каждой ветки команд, НАМЕРЕННО:
# _apply_orders — единственное место, где приказы вообще уходят к бойцам, и
# тактика, привязанная к нему, не может быть забыта в новой ветке планирования.
#
# ПОРЯДОК ПРОВЕРОК = ПОРЯДОК ПРИОРИТЕТОВ. Выбитый отряд уходит, что бы ему ни
# планировали; уцелевшие лучники прячутся; мечники идут в обход. Каждый отряд
# получает не больше одной тактической роли за такт
func _tactical_overrides(castle: Castle) -> void:
	if not _peace_over:
		return
	for s in squads:
		var sq: Dictionary = s
		if (sq["members"] as Array).is_empty():
			continue
		if _try_retreat(sq, castle):
			continue
		match String(sq["type"]):
			"archer":
				_try_kite(sq)
			"warrior":
				_try_flank(sq)

## Боеспособность отряда: живое здоровье против здоровья того же отряда В ЕГО
## ЛУЧШЕМ СОСТАВЕ (sq["peak"] — наибольшая численность, которой он достигал).
##
## ЗДЕСЬ БЫЛА ЛОВУШКА, И ОНА СТОИЛА БЫ ИИ ВСЕЙ АРМИИ. Сначала знаменателем
## стояла ШТАТНАЯ численность (_UCfg.squad_size) — «доля от полного отряда».
## Звучит правильно, но отряды ИИ собираются пополнением: барак выпускает
## бойцов шеренгами, и _regroup заводит отряд с ОДНОГО человека, доливая
## остальных следующими тактами. По штатной мерке такой отряд боеспособен на
## 5%, то есть свежее пополнение, едва выйдя из ворот, разворачивалось и
## уходило обратно в замок — навсегда, потому что там оно снова становилось
## пополнением. Стенд поймал это на ровном месте: у шести мечников роль вышла
## «отход» вместо «обход».
##
## Отсчёт от собственного пика лишён этого порока и вдобавок точнее отвечает
## заказу («при КРИТИЧЕСКОМ УРОНЕ»): целый отряд любого размера боеспособен на
## единицу, а падает эта величина ровно от потерь и ран — от того, что и
## называется уроном
func _squad_strength(sq: Dictionary) -> float:
	var members: Array = sq["members"]
	if members.is_empty():
		return 0.0
	var sample: Unit = null
	var hp := 0.0
	for m in members:
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		if sample == null:
			sample = u
		hp += u.current_health
	if sample == null:
		return 0.0
	var peak: int = maxi(int(sq.get("peak", members.size())), 1)
	var full_hp: float = float(peak) * maxf(sample.max_health, 1.0)
	return hp / full_hp

## ── ОТСТУПЛЕНИЕ В КРЕПОСТЬ ──────────────────────────────────────────────────
## Выбитый отряд, оставленный в поле, доедают бесплатно. Отправленный в замок —
## лечится и пополняется до штатной численности и возвращается в строй.
##
## Отправка идёт ШТАТНЫМ механизмом гарнизона (Castle.request_garrison), а не
## своим приказом «идти к замку»: тот сам снимает разметку строя, переводит
## бойцов в режим отхода (без перехвата, без авто-агро, сквозь чужие строи) и
## впускает их внутрь. Своя реализация повторила бы всё это хуже.
##
## Номер отряда берётся У БОЙЦОВ, а не у записи ИИ: гарнизон оперирует отрядами
## GameManager, а запись ИИ — своя группировка, и в неё после потерь могут
## попасть остатки нескольких разных отрядов найма
## Есть ли у записи ИИ хоть один боец, до которого прямо сейчас достают оружием.
## Номера отрядов берутся У БОЙЦОВ, а не у записи ИИ: одна запись ИИ может
## содержать остатки нескольких отрядов найма (см. _try_retreat ниже)
func _in_melee(sq: Dictionary) -> bool:
	var seen: Dictionary = {}
	for m in sq["members"]:
		if not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		var sid: int = u.squad_id
		if sid <= 0 or seen.has(sid):
			continue
		seen[sid] = true
		if GameManager.squad_engaged(sid) > 0:
			return true
	return false

func _try_retreat(sq: Dictionary, castle: Castle) -> bool:
	if not _AICfg.AI_SQUAD_RETREAT or castle == null:
		return false
	# Уже отступает: приказ отдан замком, переиздавать нечего. Роль спадёт сама,
	# когда бойцы уйдут внутрь (_regroup выкидывает их из состава)
	if String(sq["role"]) == ROLE_RETREAT:
		return true
	if _squad_strength(sq) > _AICfg.RETREAT_STRENGTH:
		return false
	# ── ЗАВЯЗАЛСЯ В РУКОПАШНОЙ — ДЕРЁТСЯ ДО КОНЦА ───────────────────────────
	# Отряд, развернувшийся спиной посреди схватки, не отступает, а гибнет: он
	# идёт к воротам сквозь тех, кто до него достаёт, не отвечает (режим отхода
	# глушит и авто-агро, и ответный удар) и получает весь урон бесплатно. Это и
	# есть «трусость ИИ» из отчёта — механика отхода сама по себе верна, неверен
	# был момент её применения.
	#
	# Правило: отходить можно ДО контакта и ПОСЛЕ него, но не ИЗ него. Пока
	# оружие достаёт хотя бы до одного бойца отряда, решение об отходе просто не
	# принимается, и отряд дерётся обычным порядком. Уцелевшие уйдут в замок
	# следующим тактом, когда контакт разорвётся; полноценная система морали и
	# паники — отдельная работа, здесь её нет намеренно.
	#
	# «Контакт» берётся из бухгалтерии боя (GameManager.squad_engaged): она уже
	# считает это раз в 0.4 с на отряд, своего обхода бойцов не добавляется
	if _AICfg.AI_NO_RETREAT_IN_MELEE and _in_melee(sq):
		return false
	# Отступают ОТ КОГО-ТО. Уводить отряд с поста из-за старых ран, когда вокруг
	# тихо, значит оголить рубеж без всякой причины
	var anchor := _squad_centroid(sq["members"])
	if _nearest_player_target(anchor, _AICfg.RETREAT_THREAT_RADIUS) == null:
		return false
	var sent := false
	var seen: Dictionary = {}
	for m in sq["members"]:
		var u := m as Unit
		if u == null or not is_instance_valid(u):
			continue
		var sid: int = u.squad_id
		if sid <= 0 or seen.has(sid):
			continue
		seen[sid] = true
		if castle.request_garrison(sid):
			sent = true
	if not sent:
		return false          # гарнизон полон — деремся там, где стоим
	_set_role(sq, ROLE_RETREAT, castle.global_position)
	sq["issued"] = true       # приказ уже отдан замком, свой поверх не нужен
	last_action += "|отход отряда %s в замок" % String(sq["type"])
	return true

## ── КАЙТ ЛУЧНИКОВ ───────────────────────────────────────────────────────────
## Лучник в ближнем бою бесполезен и умирает первым. Подошла пехота — отряд
## отходит ЗА СПИНУ ближайшей своей пехоты и стреляет оттуда.
## Если прикрывать некем, отходит просто от угрозы: даже голое отступление
## лучше, чем стоять и получать по зубам оружием, которым не ответишь
func _try_kite(sq: Dictionary) -> bool:
	if not _AICfg.AI_ARCHER_KITE:
		return false
	var anchor := _squad_centroid(sq["members"])
	var foe := _nearest_player_melee(anchor, _AICfg.KITE_TRIGGER_DIST)
	if foe == null:
		return false
	var fpos: Vector3 = foe.global_position
	var cover := _nearest_own_melee_centroid(anchor)
	var spot: Vector3
	if cover != Vector3.INF:
		# «За спиной» считается ОТ УГРОЗЫ, а не от лучников: прикрытие имеет
		# смысл только тогда, когда пехота оказывается МЕЖДУ ними
		var away := cover - fpos
		away.y = 0.0
		if away.length() < 0.01:
			away = anchor - fpos
			away.y = 0.0
		if away.length() < 0.01:
			away = Vector3.FORWARD
		spot = cover + away.normalized() * _AICfg.KITE_BACK_DIST
	else:
		var back := anchor - fpos
		back.y = 0.0
		if back.length() < 0.01:
			back = Vector3.FORWARD
		spot = anchor + back.normalized() * _AICfg.KITE_BACK_DIST
	_set_role(sq, ROLE_KITE, GameManager.land_target(spot))
	return true

## ── ФЛАНГОВЫЙ ОБХОД МЕЧНИКОВ ────────────────────────────────────────────────
## Мечник, пущенный в лоб на строй копейщиков, — это размен, который ИИ всегда
## проигрывает: у копья и досягаемость больше, и фаланга держит строй. Его дело
## — обойти стену по дуге и добраться до стрелков, у которых в ближнем бою нет
## ничего.
##
## Обход двухшаговый: пока далеко, отряд идёт в точку СБОКУ от стрелков (мимо
## лобового строя), и только вблизи переходит в атаку. Первый шаг отдаётся
## БЕГОМ (см. _apply_orders): бегущий отряд не перехватывается чужой линией и
## не втягивается в авто-бой — то есть действительно обходит, а не застревает в
## первой же стычке. Плата за это честная: на бегу мечники уязвимы
func _try_flank(sq: Dictionary) -> bool:
	if not _AICfg.AI_WARRIOR_FLANK:
		return false
	var anchor := _squad_centroid(sq["members"])
	# Стрелки ищутся рядом с ЦЕЛЬЮ ВОЛНЫ, а не рядом с самим отрядом: обход
	# затевается заранее, когда до чужого строя ещё далеко
	var prey := _nearest_player_ranged(sq["target"] as Vector3, _AICfg.FLANK_REACH)
	if prey == null:
		return false
	var ppos: Vector3 = prey.global_position
	var course := ppos - anchor
	course.y = 0.0
	var dist := course.length()
	if dist < 0.01:
		return false
	course = course.normalized()
	var right := Vector3(-course.z, 0.0, course.x)
	# Сторона обхода закреплена за отрядом навсегда (по номеру первого бойца):
	# иначе два отряда мечников каждый такт менялись бы краями и топтались
	var side: float = 1.0 if (int(sq.get("flank_side", 0)) == 0) else -1.0
	if dist > _AICfg.FLANK_TRIGGER_DIST:
		sq["flank_close"] = false
		var wp := ppos + right * (side * _AICfg.FLANK_ARC_RADIUS) - course * 4.0
		_set_role(sq, ROLE_FLANK, GameManager.land_target(wp))
	else:
		sq["flank_close"] = true
		_set_role(sq, ROLE_FLANK, ppos)
	return true

## Ближайший боец игрока БЛИЖНЕГО боя (порог дальности — из конфига, чтобы
## новый род войск подхватился сам)
func _nearest_player_melee(from: Vector3, radius: float) -> Node3D:
	return _nearest_player_unit(from, radius, false)

## Ближайший СТРЕЛОК игрока
func _nearest_player_ranged(from: Vector3, radius: float) -> Node3D:
	return _nearest_player_unit(from, radius, true)

## Обход группы здесь ОСТАВЛЕН СОЗНАТЕЛЬНО: нужен ближайший боец С ЗАДАННЫМ
## РОДОМ (стрелок или рукопашник), а сетка про род ничего не знает — она
## различает только стороны. Зато и зовут это редко: один раз на отряд в роли
## обхода, а не на бойца (см. _apply_orders). Радиус проверяется ПЕРВЫМ, до
## чтения свойств узла, — это отсекает подавляющее большинство кандидатов
func _nearest_player_unit(from: Vector3, radius: float, ranged: bool) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	var fx: float = from.x
	var fz: float = from.z
	var rr: float = radius * radius
	for n in main.get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(n):
			continue
		var p: Vector3 = (n as Node3D).global_position
		var dx: float = fx - p.x
		var dz: float = fz - p.z
		var d2: float = dx * dx + dz * dz
		if d2 >= rr:
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u is Worker:
			continue
		var is_ranged: bool = u.attack_range >= _AICfg.RANGED_ATTACK_RANGE
		if is_ranged != ranged:
			continue
		var d: float = sqrt(d2)
		if d < best_d:
			best_d = d
			best = u
	return best

## Середина ближайшего СВОЕГО отряда ближнего боя — за его спину и прячутся
## лучники. Vector3.INF — прикрывать некем
func _nearest_own_melee_centroid(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for s in squads:
		var sq: Dictionary = s
		var uid: String = String(sq["type"])
		if uid == "archer":
			continue
		var members: Array = sq["members"]
		if members.is_empty():
			continue
		var c := _squad_centroid(members)
		var d: float = from.distance_to(c)
		if d < best_d:
			best_d = d
			best = c
	return best

# ─────────────────────────────────────────────────────────────────────────────
# ВЫДАЧА ПРИКАЗОВ РАЗМАЗАНА ПО КАДРАМ
#
# Такт размышления идёт раз в THINK_INTERVAL (2 с), и ВСЯ его работа падала в
# ОДИН кадр: решение по отряду плюс обход всех его бойцов с command_move/
# command_attack на каждого. На шести сотнях бойцов ИИ это заметный горб раз в
# две секунды — тот самый «синхронный пульс», который видно как рывок всей
# армии разом.
#
# Решение (дешёвая часть) по-прежнему принимается сразу и на все отряды —
# обстановка обязана быть согласованной, иначе половина отрядов планировала бы
# по одной картине мира, половина по другой. А вот РАЗДАЧА (дорогая часть)
# складывается в очередь и разбирается по ORDER_BUDGET_MEMBERS бойцов за кадр.
# При шести сотнях бойцов это три-четыре кадра, то есть 50-70 мс — на фоне
# двухсекундного такта задержка неощутима, а горб исчезает.
#
# Тот же приём, что и с фазами коридоров отрядов (GameManager._sweep_corridors):
# кадр держит работа В ОДНОМ КАДРЕ, а не за секунду.
# ─────────────────────────────────────────────────────────────────────────────

## План выдачи: по записи на отряд, каждая — уже принятое решение
var _order_queue: Array = []
var _order_at: int = 0

const ORDER_BUDGET_MEMBERS := 200

## Разобрать очередь приказов. Зовётся КАЖДЫЙ кадр из _process
func _drain_orders() -> void:
	if _order_at >= _order_queue.size():
		return
	var left: int = ORDER_BUDGET_MEMBERS
	while _order_at < _order_queue.size() and left > 0:
		var plan: Dictionary = _order_queue[_order_at]
		_order_at += 1
		left -= _issue_plan(plan)
	if _order_at >= _order_queue.size():
		_order_queue.clear()
		_order_at = 0

func _apply_orders() -> void:
	_tactical_overrides(_find_castle())
	# Недоразобранный план прошлого такта выбрасывается целиком: обстановка
	# пересчитана, и выдавать поверх неё вчерашние приказы было бы хуже, чем
	# не выдать вовсе
	_order_queue.clear()
	_order_at = 0
	for s in squads:
		var sq: Dictionary = s
		var members: Array = sq["members"]
		if members.is_empty():
			continue
		var role: String = String(sq["role"])
		# ── ОТСТУПАЮЩИЙ ОТРЯД НИКАКИХ ПРИКАЗОВ ОТ ИИ НЕ ПОЛУЧАЕТ ────────────
		# Его ведёт замок (Castle.request_garrison): бойцы уже в режиме отхода и
		# идут к воротам. Любой приказ отсюда снял бы этот режим — command_move
		# без keep_retreat гасит retreating (см. Unit) — и отряд посреди дороги
		# снова полез бы драться, ради чего его и уводили
		if role == ROLE_RETREAT:
			continue
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
		var uid: String = String(sq["type"])
		var stance: String = _UCfg.STANCE_DEFENSE if holds else _UCfg.STANCE_ATTACK
		# ── ФАЛАНГА НА МАРШЕ ────────────────────────────────────────────────
		# Копья опускает СТОЙКА ЗАЩИТА (Spearman._spear_leveled: holds =
		# _stance_holds_ground() or _charging()), а марширующий отряд получал
		# стойку АТАКА и шёл щетиной вверх — копья опускались только в момент
		# приказа атаки, то есть уже в контакте. Пока противника нет рядом,
		# копейщики держат ЗАЩИТУ и идут блоком с опущенными копьями; при
		# контакте стойка возвращается к АТАКЕ, и отряд бьёт как обычно.
		# «Контакт» ищется один раз на отряд, не на бойца
		var contact: bool = threat != null
		if _AICfg.AI_SPEAR_PHALANX_ON_MARCH and uid == "spearman" and not holds:
			if not contact:
				contact = _nearest_player_target(_squad_centroid(members),
					_AICfg.CONTACT_RADIUS) != null
			if not contact:
				stance = _UCfg.STANCE_DEFENSE
		# Обходящие мечники бегут, а на бегу фаланги и стойки нет вовсе —
		# им стойка АТАКА нужна, чтобы по прибытии сразу вступить в бой
		if role == ROLE_FLANK:
			stance = _UCfg.STANCE_ATTACK
		var need_issue: bool = not bool(sq["issued"])
		if not need_issue:
			# Приказ уже отдан: подтолкнуть только тех, кто встал без дела.
			#
			# ── НО НЕ ПОСРЕДИ СХВАТКИ ────────────────────────────────────────
			# Это второй источник «разворота спиной», и он тоньше первого.
			# В свалке отряд, который многочисленнее своего противника, наполовину
			# состоит из бойцов БЕЗ ЦЕЛИ: до врага дотягивается только передняя
			# шеренга, остальные честно стоят в State.IDLE. Условие «бездельников
			# больше половины» на такой картине срабатывает всегда, и отряд
			# получал command_move поверх идущего боя — а command_move у бойца с
			# живой целью эту цель СНИМАЕТ (см. Unit._disengaging). То есть
			# подталкивание тыла разворачивало и передний ряд тоже.
			#
			# Пока отряд в контакте, никаких подталкиваний: тыл подтянется сам
			# смыканием рядов, а передний ряд не бросит начатое
			if _in_melee(sq):
				continue
			var idle := 0
			for m in members:
				if (m as Unit).state == Unit.State.IDLE:
					idle += 1
			if idle * 2 < members.size():
				continue
		sq["issued"] = true
		var center: Vector3 = sq["target"]
		var course := _order_course(members, center)
		# ── РОВНЫЕ ШЕРЕНГИ: КОЛОНКИ ВЫВОДЯТСЯ ИЗ ЧИСЛА ШЕРЕНГ ───────────────
		# Здесь была жёсткая шестёрка колонок на всех. Отряд копейщиков в 20
		# человек ложился в неё как 6+6+6+2 — три полных ряда и огрызок, то есть
		# ни «ровных шеренг», ни предсказуемой глубины фаланги. Теперь у
		# копейщиков задано ЧИСЛО ШЕРЕНГ (PHALANX_RANKS), а колонки считаются от
		# него: 20 человек на 4 шеренги — ровно 5×4, при любых потерях ряды
		# остаются одинаковой длины. Остальным родам шестёрка и подходит
		var cols: int = SQUAD_COLS
		if uid == "spearman" and _AICfg.PHALANX_RANKS > 0:
			cols = maxi(1, int(ceil(float(members.size()) / float(_AICfg.PHALANX_RANKS))))
		var flank_close: bool = bool(sq.get("flank_close", false))
		# ── ЦЕЛЬ ИЩЕТСЯ РАЗ НА ОТРЯД, А НЕ НА БОЙЦА ─────────────────────────
		# Здесь стояли три вызова _nearest_player_target/_ranged ВНУТРИ цикла по
		# бойцам. Это было плохо дважды.
		#
		# По ЦЕНЕ: каждый вызов обходил обе группы игрока целиком (см. шапку
		# _nearest_player_target), и весь такт размышления укладывался в один
		# кадр — отсюда «пульс раз в две секунды» и просадка до 6 FPS в момент
		# первой стычки, когда отрядов становится много.
		#
		# По СМЫСЛУ: своя цель каждому бойцу — это ровно тот механизм, который
		# уже однажды разваливал отряд игрока (см. в CLAUDE.md разбор
		# SelectionManager: «каждому выделенному своя ближайшая цель» и есть
		# главный источник расползания). Один приказ на отряд разворачивается по
		# составу противника сам — этим занимается GameManager.squad_pick_member
		# внутри command_attack, и делает он это равномерно, а не «кто ближе».
		var anchor: Vector3 = _squad_centroid(members)
		var squad_prey: Node3D = null
		if role == ROLE_FLANK and flank_close:
			squad_prey = _nearest_player_ranged(anchor, _AICfg.FLANK_TRIGGER_DIST * 1.5)
			if squad_prey == null:
				squad_prey = _nearest_player_target(anchor, _AICfg.CONTACT_RADIUS)
		elif threat != null:
			squad_prey = _nearest_player_target(anchor,
				_AICfg.DEFENSE_ENGAGE_RADIUS * 1.5)
			if squad_prey == null:
				squad_prey = threat
		elif not holds and role != ROLE_KITE and role != ROLE_PATROL:
			squad_prey = _nearest_player_target(anchor, 24.0)
		# Решение принято — раздача уходит в очередь (см. _drain_orders)
		_order_queue.append({
			"members": members, "role": role, "stance": stance,
			"center": center, "course": course, "cols": cols,
			"prey": squad_prey, "threat": threat, "holds": holds,
			"flank_close": flank_close,
		})
	# Первую порцию выдаём сразу, в этом же кадре: отряды, попавшие в начало
	# очереди, не должны ждать следующего кадра без причины
	_drain_orders()

## Разослать один готовый план бойцам. Возвращает, скольким выдано (бюджет
## считается в бойцах, а не в отрядах: отряды бывают и по одному человеку, и по
## полсотни)
func _issue_plan(plan: Dictionary) -> int:
	var members: Array = plan["members"]
	var role: String = plan["role"]
	var stance: String = plan["stance"]
	var center: Vector3 = plan["center"]
	var course: Vector3 = plan["course"]
	var cols: int = plan["cols"]
	var prey = plan["prey"]
	var threat = plan["threat"]
	var holds: bool = plan["holds"]
	var flank_close: bool = plan["flank_close"]
	# Цель могли убить, пока план ждал своей очереди
	if prey != null and not is_instance_valid(prey):
		prey = null
	if threat != null and not is_instance_valid(threat):
		threat = null
	var done := 0
	for i in range(members.size()):
		# ПРОВЕРКА ДО ПРИВЕДЕНИЯ ТИПА, А НЕ ПОСЛЕ. `x as Unit` на освобождённом
		# объекте не возвращает null — он БРОСАЕТ «Trying to cast a freed
		# object», то есть страховка ниже физически не могла сработать. Здесь
		# это не теория: план ждёт своей очереди несколько кадров (см.
		# _drain_orders), и бойца за это время вполне могут добить — рядом
		# стоящая проверка prey/threat поставлена ровно по этой причине
		if not is_instance_valid(members[i]):
			continue
		var u := members[i] as Unit
		if u == null or u.is_dead():
			continue
		done += 1
		if u.stance != stance:
			u.set_stance(stance)
		var col: int = i % cols
		var row: int = i / cols
		var off_x: float = (float(col) - float(cols - 1) * 0.5) * SQUAD_SPACING
		var off_z: float = float(row) * SQUAD_SPACING
		u.formation_row = row
		if role == ROLE_FLANK:
			# ОБХОД. Пока далеко — БЕГОМ мимо чужого строя: бегущий отряд не
			# перехватывается вражеской линией и не втягивается в авто-бой
			# (см. Unit.sprinting), то есть действительно обходит, а не
			# застревает в первой стычке. Флаг спадает сам по прибытии
			if flank_close:
				u.command_attack(prey, true, true)
			else:
				u.command_move(center + Vector3(off_x, 0.0, off_z), false,
					course, false, false, true)
		elif role == ROLE_KITE:
			# ОТХОД ЗА СПИНУ СВОИХ. Не режим отхода (retreating): лучники
			# обязаны продолжать стрелять, а тот режим глушит авто-агро
			u.command_move(center + Vector3(off_x, 0.0, off_z), false, course)
		elif threat != null:
			# ПРОТИВНИК В ЗОНЕ — ДЕРЁМСЯ ВСЕЙ СЕКЦИЕЙ, ОДНОЙ ЦЕЛЬЮ НА ОТРЯД
			u.command_attack(prey if prey != null else threat, true, true)
		elif holds:
			# Вокруг тихо: гарнизон и заслон встают на пост и держат его
			u.command_move(center + Vector3(off_x, 0.0, off_z), false, course)
		elif role == ROLE_PATROL:
			# Патруль обходит свою дугу; в бой втягивается авто-агро
			u.command_move(center + Vector3(off_x, 0.0, off_z), true, course)
		elif prey != null:
			u.command_attack(prey, true, true)
		else:
			u.command_move(center + Vector3(off_x, 0.0, off_z), false, course)
	return maxi(done, 1)

## Центр масс всей полевой волны — от него считается курс боевого порядка
func _field_centroid(field: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for s in field:
		for m in (s as Dictionary)["members"]:
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u == null or u.is_dead():
				continue
			c += u.global_position
			n += 1
	return c / float(n) if n > 0 else Vector3.ZERO

## Середина секции — от неё и считается «есть ли враг в зоне»
## ЦЕНТР ОТРЯДА — МЕДИАНА (тот же разбор, что в GameManager._centroid_of):
## у растянутого или расколотого надвое отряда среднее садится в пустое поле
## между группами, и туда же уезжает вся тактика ИИ — отход, кайт, обход
func _squad_centroid(members: Array) -> Vector3:
	var live: Array = []
	for m in members:
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		live.append(u)
	if live.is_empty():
		return Vector3.ZERO
	return GameManager._centroid_of(live)

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

# ─────────────────────────────────────────────────────────────────────────────
# ПОИСК ЦЕЛИ: СЕТКА ДЛЯ БОЙЦОВ, СНИМОК ЗА ТАКТ ДЛЯ ЗДАНИЙ
#
# Здесь стоял двойной обход групп `player_units` + `player_buildings`. Обе беды
# этого обхода видны только на большой армии:
#   • get_nodes_in_group КОПИРУЕТ внутренний массив на каждое обращение — при
#     1900 бойцах игрока это 1900 ссылок в новый Array;
#   • расстояние мерилось до КАЖДОГО, включая тех, кто на другом конце карты,
#     хотя радиус запроса — 24-40 м.
# А звали это из ПОШТУЧНОГО цикла по бойцам ИИ (см. _apply_orders), то есть один
# такт размышления при 600 бойцах ИИ стоил ~1.1 млн проверок расстояния и 1200
# копий массива — и всё это в ОДНОМ кадре. Это и был «пульс раз в две секунды».
#
# Бойцы теперь берутся из плоской сетки армии (ArmySoA.nearest_of_side): она уже
# собрана в этом кадре, и обходятся только непустые ячейки нужного радиуса.
# Здания в сетке не лежат — их мало, и их список снимается РАЗ ЗА ТАКТ
# (_refresh_target_cache), а не на каждый запрос.
# ─────────────────────────────────────────────────────────────────────────────

## Снимок зданий игрока на текущий такт: [Node3D, x, z] тройками в плоском виде
var _pb_nodes: Array = []
var _pb_x := PackedFloat32Array()
var _pb_z := PackedFloat32Array()

func _refresh_target_cache() -> void:
	_pb_nodes.clear()
	_pb_x.clear()
	_pb_z.clear()
	if main == null:
		return
	for b in main.get_tree().get_nodes_in_group("player_buildings"):
		if not is_instance_valid(b):
			continue
		if b.has_method("is_dead") and b.is_dead():
			continue
		var p: Vector3 = (b as Node3D).global_position
		_pb_nodes.append(b)
		_pb_x.append(p.x)
		_pb_z.append(p.z)

func _nearest_player_target(from: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = radius
	var u = GameManager.army.nearest_of_side(from.x, from.z,
		Constants.FACTION_PLAYER, radius)
	if u != null:
		best = u as Node3D
		best_d = from.distance_to(best.global_position)
	# Здания — коротким проходом по снимку такта. Их единицы, сетка тут не нужна
	for i in range(_pb_nodes.size()):
		var dx: float = from.x - _pb_x[i]
		var dz: float = from.z - _pb_z[i]
		var d: float = sqrt(dx * dx + dz * dz)
		if d < best_d:
			var b = _pb_nodes[i]
			if is_instance_valid(b):
				best_d = d
				best = b as Node3D
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
