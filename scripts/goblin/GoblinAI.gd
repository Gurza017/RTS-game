extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ВОЖАК ОРДЫ ГОБЛИНОВ
## ═══════════════════════════════════════════════════════════════════════════
## Третья сторона, враждебная ВСЕМ. Живёт по расписанию, а не по разведке:
##
##   00:00-30:00  СПЯЧКА. Орда стоит в деревне и не тикает вовсе — ни движения,
##                ни поиска целей, ни пересчёта поз. Её можно убить, она
##                блокирует шаг, но кадра не ест.
##   30:00        ВОЛНА В ЦЕНТР. Все отряды идут в середину карты и дерутся
##                там со всеми, кто попался: синими, красными, друг с другом их
##                никто не разводит.
##   волна выбита ОБОРОНА ДЕРЕВНИ. Уцелевшие и свежие держат хижины, орда копит
##                еду и нанимает армию заново до ARMY_SQUADS отрядов.
##   набрали      СНОВА В ЦЕНТР. Зачистили центр — идём на САМОГО СЛАБОГО
##                игрока (по здоровью зданий и числу бойцов) и добиваем его.
##   и по кругу.
##
## ── ЧТО ЗДЕСЬ НАМЕРЕННО НЕ НАПИСАНО ────────────────────────────────────────
## Ни своей боёвки, ни своего движения, ни своей блокировки строем. Гоблин —
## обычный Unit, и всё это он получает от базы; вожак только раздаёт приказы
## РАЗ В THINK_INTERVAL И ПО ОТРЯДУ, а не по бойцу (правило проекта: решение
## отряда, принятое на каждого из сотни, стоит в сто раз дороже и не меняет
## ничего — отряд наступает, отходит и лечится как тело).

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _UCfg   := preload("res://scripts/unit_stats_config.gd")

# ── РОЛИ ОТРЯДА ─────────────────────────────────────────────────────────────
const ROLE_DORMANT := "dormant"   # спит в деревне
const ROLE_CENTER  := "center"    # штурмует центр карты
const ROLE_HUNT    := "hunt"      # добивает самого слабого игрока
const ROLE_DEFEND  := "defend"    # держит деревню
const ROLE_HEAL    := "heal"      # разбит, уходит в хижину лечиться

# ── ФАЗА ОРДЫ ───────────────────────────────────────────────────────────────
const PHASE_DORMANT := "dormant"
const PHASE_CENTER  := "center"
const PHASE_HUNT    := "hunt"
const PHASE_DEFEND  := "defend"

var main: Node3D = null
var village: Vector3 = Vector3.ZERO
## Отряды орды: [{ "id", "type", "members", "role", "target", "peak" }]
var squads: Array = []
var phase: String = PHASE_DORMANT
var clock: float = 0.0            # игровое время партии, сек
var last_action: String = ""      # диагностика для стенда

var _think: float = 0.0
var _awake: bool = false

func setup(p_main: Node3D, p_village: Vector3) -> void:
	main = p_main
	village = p_village
	reset()

func reset() -> void:
	squads.clear()
	phase = PHASE_DORMANT
	clock = 0.0
	_think = 0.0
	_awake = false
	last_action = ""

func _process(delta: float) -> void:
	if main == null:
		return
	clock += delta
	_think -= delta
	if _think > 0.0:
		return
	_think = _GobCfg.THINK_INTERVAL
	tick()

# ═════════════════════════════════════════════════════════════════════════════
# ОДИН ТАКТ
# ═════════════════════════════════════════════════════════════════════════════
func tick() -> void:
	last_action = ""
	_regroup()
	if not _awake:
		# ── СПЯЧКА ──────────────────────────────────────────────────────────
		# Просыпаемся по часам ИЛИ раньше, если орду пришли бить: спящий боец
		# не отвечает на удар вовсе, и без этой оговорки разведчик игрока
		# вырезал бы деревню бесплатно за полчаса до её пробуждения
		if clock < _GobCfg.DORMANT_UNTIL_SEC and not _attacked():
			last_action = "спит (%.0f с до подъёма)" % (_GobCfg.DORMANT_UNTIL_SEC - clock)
			return
		_wake_horde()
	_economy()
	_retreat_broken()
	_decide_phase()
	_issue_orders()

# ── ПРОБУЖДЕНИЕ ─────────────────────────────────────────────────────────────
## Спящий боец выключен ровно в двух местах: физический тик и визуальный.
## GameManager перед вызовом обоих спрашивает is_physics_processing()/
## is_processing(), поэтому «сон» — это отсутствие вызова, а не отдельная ветка
## в каждом автомате. Картинка при этом не пропадает: слот общей отрисовки
## хранит последнюю записанную позу, а стоящий боец её и не меняет
func _set_dormant(u: Unit, on: bool) -> void:
	if not _GobCfg.DORMANT_SLEEP_PHYSICS:
		return
	if u.dormant != on:
		# Состояние ДЕЙСТВИТЕЛЬНО меняется — только тогда двигаем счётчик
		u.dormant = on
		GameManager.note_dormant(on)
	u.set_physics_process(not on)
	u.set_process(not on)
	# И ПАКЕТНЫЕ ПРОХОДЫ ТОЖЕ. Тик бойца можно отключить снаружи, а вот
	# расталкивание союзников идёт по КОЛОНКАМ и о выключенном тике не знает:
	# семьсот спящих продолжали разводиться каждый кадр. Замер (qa_mass_battle,
	# 3000 бойцов + деревня): свалка 16.5 -> 11.5 мс на одном этом бите
	if u._soa >= 0:
		GameManager.army.set_dormant(u._soa, on)

func _wake_horde() -> void:
	_awake = true
	phase = PHASE_CENTER
	for s in squads:
		for m in (s as Dictionary)["members"]:
			var u := m as Unit
			if u != null and is_instance_valid(u):
				_set_dormant(u, false)
				u.wake_for_lod()
	last_action = "ОРДА ПРОСНУЛАСЬ"

## Кого-то из орды бьют прямо сейчас? Спрашиваем бухгалтерию боя, а не
## обходим бойцов: она и так ведёт отметку удара по отряду
func _attacked() -> bool:
	for s in squads:
		var sid: int = int((s as Dictionary)["id"])
		if sid > 0 and GameManager.squad_in_combat(sid):
			return true
	return false

# ═════════════════════════════════════════════════════════════════════════════
# СОСТАВ
# ═════════════════════════════════════════════════════════════════════════════
## Выбитых — вон, пустые отряды — расформировать, новых бойцов — в свои отряды.
## Гарнизонные выбывают из состава наравне с павшими: они живы, но с карты сняты
## (Castle.absorb_unit), и оставь их в списке — вожак вечно числил бы роль
## «лечится» и не набирал бы замену. Та же ошибка была допущена и исправлена
## в EnemyAI._regroup
func _regroup() -> void:
	var kept: Array = []
	for s in squads:
		var sq: Dictionary = s
		var alive: Array = []
		for m in sq["members"]:
			if is_instance_valid(m) and not (m as Unit).is_dead() \
					and not (m as Unit).garrisoned:
				alive.append(m)
		if alive.is_empty():
			continue
		sq["members"] = alive
		kept.append(sq)
	squads = kept

	# Свежие бойцы орды, ещё не попавшие ни в один отряд. Отряд у них уже есть
	# (его завёл барак-хижина при найме) — просто заносим его в реестр вожака
	var known: Dictionary = {}
	for s in squads:
		known[int((s as Dictionary)["id"])] = s
	for n in main.get_tree().get_nodes_in_group("goblin_units"):
		if not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.garrisoned or u.squad_id <= 0:
			continue
		var rec: Variant = known.get(u.squad_id)
		if rec == null:
			rec = {"id": u.squad_id, "type": u.stat_id, "members": [],
				"role": ROLE_DEFEND, "target": village, "peak": 0}
			known[u.squad_id] = rec
			squads.append(rec)
		var arr: Array = (rec as Dictionary)["members"]
		if not arr.has(u):
			arr.append(u)
			# Спящему бойцу сон ставится в момент зачисления: свежий выходит
			# из хижины уже проснувшимся, стартовый — спящим
			if not _awake:
				_set_dormant(u, true)

	# ПИК СЧИТАЕТСЯ ЧЕТВЁРТЫМ ПРОХОДОМ, после пополнения. Отряд, собранный в
	# этот такт, до пополнения не существовал, и записанный раньше пик остался
	# бы единицей — разбитым такой отряд считался бы никогда
	for s in squads:
		var sq2: Dictionary = s
		var n2: int = (sq2["members"] as Array).size()
		if n2 > int(sq2.get("peak", 0)):
			sq2["peak"] = n2

func army_squads() -> int:
	return squads.size()

func army_size() -> int:
	var n := 0
	for s in squads:
		n += ((s as Dictionary)["members"] as Array).size()
	return n

# ═════════════════════════════════════════════════════════════════════════════
# ЭКОНОМИКА: ЕДА КОПИТСЯ ХИЖИНАМИ, ОРДА НАНИМАЕТ
# ═════════════════════════════════════════════════════════════════════════════
## Найм идёт ПО ОДНОМУ заказу за такт и только пока армия не полна. Заказ
## ставится в хижину как обычный заказ найма — со всей штатной механикой:
## списание в момент заказа, выход шеренга за шеренгой, свой squad_id.
## Звёзд новобранцам не полагается (заказ владельца): серебро есть только у
## стартовых отрядов
func _economy() -> void:
	if squads.size() >= _GobCfg.ARMY_SQUADS:
		return
	var huts := _huts()
	if huts.is_empty():
		return
	# Уже строится — второй заказ не ставим: орда должна накопить, а не
	# заморозить всю еду в очереди
	for h in huts:
		if not (h as Building).production_queue.is_empty():
			return
	var cost: Dictionary = {Constants.RESOURCE_FOOD: _GobCfg.SQUAD_FOOD_COST}
	if not ResourceManager.can_afford(Constants.FACTION_GOBLIN, cost):
		return
	# Чего не хватает по составу — того и нанимаем
	var want: String = _missing_type()
	var hut: Building = huts[randi() % huts.size()]
	hut.squad_size   = int(_GobCfg.SQUAD_SIZE.get(want, 20))
	hut.squad_cols   = int(_GobCfg.SQUAD_COLS.get(want, 5))
	hut.squad_spacing = _GobCfg.SQUAD_SPACING
	if hut.queue_unit(want, cost, _GobCfg.SQUAD_BUILD_SEC):
		last_action += "|найм %s" % want

## Какого рода войск не хватает против эталонного состава орды
func _missing_type() -> String:
	var have: Dictionary = {}
	for s in squads:
		var t: String = String((s as Dictionary)["type"])
		have[t] = int(have.get(t, 0)) + 1
	var want: Dictionary = {}
	for t in _GobCfg.ARMY_COMPOSITION:
		want[String(t)] = int(want.get(String(t), 0)) + 1
	for t in want:
		if int(have.get(String(t), 0)) < int(want[t]):
			return String(t)
	return String(_GobCfg.ARMY_COMPOSITION[0])

func _huts() -> Array:
	var out: Array = []
	for b in main.get_tree().get_nodes_in_group("goblin_buildings"):
		if is_instance_valid(b) and not (b as Building).is_dead():
			out.append(b)
	return out

# ═════════════════════════════════════════════════════════════════════════════
# ОТХОД РАЗБИТЫХ В ХИЖИНУ
# ═════════════════════════════════════════════════════════════════════════════
## Порог — доля от ПИКА отряда, а не от уставного размера. Орда пополняется
## постепенно, и по уставному числу свежий отряд из десяти бойцов вечно
## читался бы как «разбит» и разворачивался бы у ворот обратно внутрь.
##
## Отход выполняет сама хижина (request_garrison): она уже умеет снять
## разметку строя, перевести отряд в режим отхода, довести до ворот, спрятать,
## лечить и доукомплектовать. Своего «идти домой» здесь нет намеренно — оно
## было бы худшей копией.
func _retreat_broken() -> void:
	for s in squads:
		var sq: Dictionary = s
		if String(sq["role"]) == ROLE_HEAL:
			continue
		var peak: int = maxi(int(sq.get("peak", 1)), 1)
		var alive: int = (sq["members"] as Array).size()
		if float(alive) > float(peak) * _GobCfg.RETREAT_STRENGTH:
			continue
		# ИЗ РУКОПАШНОЙ НЕ ОТХОДЯТ. Отряд, повернувший спину в контакте, не
		# отступает, а гибнет: режим отхода глушит и авто-агро, и ответный удар
		if _GobCfg.NO_RETREAT_IN_MELEE and GameManager.squad_engaged(int(sq["id"])) > 0:
			continue
		var hut := _nearest_hut(_squad_center(sq))
		if hut == null:
			continue
		if hut.request_garrison(int(sq["id"])):
			sq["role"] = ROLE_HEAL
			sq["issued"] = true
			last_action += "|отряд %d уходит в хижину" % int(sq["id"])

func _nearest_hut(from: Vector3) -> Castle:
	var best: Castle = null
	var bd := INF
	for h in _huts():
		var c := h as Castle
		if c == null:
			continue
		var d: float = from.distance_squared_to(c.global_position)
		if d < bd:
			bd = d
			best = c
	return best

# ═════════════════════════════════════════════════════════════════════════════
# ФАЗА ОРДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _decide_phase() -> void:
	match phase:
		PHASE_CENTER:
			# Волна кончилась, когда орда в поле выбита; уцелевшие возвращаются
			# держать деревню и копить на новую армию
			if _field_squads() == 0:
				phase = PHASE_DEFEND
				last_action += "|волна выбита, оборона деревни"
			elif _horde_at_center() and _center_clear():
				# ЦЕНТР СЧИТАЕТСЯ ВЗЯТЫМ, ТОЛЬКО КОГДА ОРДА ДО НЕГО ДОШЛА.
				# Без первой половины условия волна «брала» центр в тот же
				# такт, в который выходила из деревни: в середине карты просто
				# никого не было, и штурм отменялся, не начавшись
				phase = PHASE_HUNT
				last_action += "|центр взят, идём на слабейшего"
		PHASE_HUNT:
			if _field_squads() == 0:
				phase = PHASE_DEFEND
				last_action += "|волна выбита, оборона деревни"
		PHASE_DEFEND:
			if squads.size() >= _GobCfg.ARMY_SQUADS:
				phase = PHASE_CENTER
				last_action += "|орда собрана, новая волна в центр"

## Сколько отрядов реально в поле (не лечатся)
func _field_squads() -> int:
	var n := 0
	for s in squads:
		if String((s as Dictionary)["role"]) != ROLE_HEAL:
			n += 1
	return n

## Орда уже дошла до центра? Считаем по центру масс всех полевых отрядов
func _horde_at_center() -> bool:
	var acc := Vector3.ZERO
	var n := 0
	for s in squads:
		var sq: Dictionary = s
		if String(sq["role"]) == ROLE_HEAL:
			continue
		# Пустой отряд пропускаем ЯВНО, а не по «центр равен нулю»: ноль — это
		# законная точка на карте (ровно её середина), и как признак «не знаю»
		# он однажды уже соврал бы именно здесь
		if (sq["members"] as Array).is_empty():
			continue
		acc += _squad_center(sq)
		n += 1
	if n == 0:
		return false
	acc /= float(n)
	return Vector2(acc.x, acc.z).length() <= _GobCfg.CENTER_RADIUS

## Центр карты свободен от чужих? Спрашиваем сетку соседей одним запросом,
## а не обходим группы: это тот же скан, которым пользуется красный ИИ
func _center_clear() -> bool:
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		var seen = GameManager.army.nearest_of_side(0.0, 0.0, f, _GobCfg.CENTER_RADIUS)
		if seen != null:
			return false
	return true

## Самый слабый из живых игроков: сумма здоровья зданий плюс число бойцов.
## Возвращает точку, куда идти (его база), или ZERO
func _weakest_target() -> Vector3:
	var best_score := INF
	var best := Vector3.ZERO
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		var hp := 0.0
		var anchor := Vector3.ZERO
		var n := 0
		for b in main.get_tree().get_nodes_in_group(Constants.building_group(f)):
			if not is_instance_valid(b) or (b as Building).is_dead():
				continue
			hp += (b as Building).current_health
			anchor += (b as Node3D).global_position
			n += 1
		var men: int = main.get_tree().get_nodes_in_group(Constants.unit_group(f)).size()
		if n == 0 and men == 0:
			continue                      # этой стороны уже нет
		var score: float = hp + float(men) * 10.0
		if score < best_score:
			best_score = score
			best = (anchor / float(maxi(n, 1))) if n > 0 else Vector3.ZERO
	return best

# ═════════════════════════════════════════════════════════════════════════════
# ПРИКАЗЫ
# ═════════════════════════════════════════════════════════════════════════════
## Одна цель на ОТРЯД, а не на бойца. Раздача по бойцу — это ровно тот способ,
## которым отряд разваливается: каждый получает своего ближайшего врага и
## растекается по округе. command_attack сам разложит отряд по моделям чужого
## отряда (GameManager.squad_pick_member)
func _issue_orders() -> void:
	var aim := village
	match phase:
		PHASE_CENTER: aim = Vector3.ZERO           # центр карты
		PHASE_HUNT:
			aim = _weakest_target()
			if aim == Vector3.ZERO:
				aim = Vector3.ZERO
		PHASE_DEFEND: aim = village
	var i := 0
	for s in squads:
		var sq: Dictionary = s
		if String(sq["role"]) == ROLE_HEAL:
			continue                       # отход ведёт хижина, свой приказ его отменит
		var members: Array = sq["members"]
		if members.is_empty():
			continue
		# Отряды расходятся по фронту, а не лезут в одну точку
		var spread: float = 8.0 * float(i - squads.size() / 2)
		var goal := Vector3(aim.x + spread, 0.0, aim.z)
		i += 1
		sq["role"] = ROLE_CENTER if phase == PHASE_CENTER else \
			(ROLE_HUNT if phase == PHASE_HUNT else ROLE_DEFEND)
		sq["target"] = goal
		var center := _squad_center(sq)
		# Цель поблизости — атакуем её; нет — идём к точке
		var foe: Node3D = _nearest_foe(center, _GobCfg.CENTER_RADIUS)
		if foe != null:
			for m in members:
				if not is_instance_valid(m):
					continue
				var u := m as Unit
				if u != null and not u.is_dead():
					u.command_attack(foe, true, true)
			continue
		# ── ТОЛПОЙ, А НЕ В ОДНУ ТОЧКУ ───────────────────────────────────────
		# Раньше всем бойцам отряда выдавалась ОДНА цель: сотня гоблинов шла в
		# один пятачок, упиралась друг в друга и разбиралась расталкиванием уже
		# на месте. Теперь у каждого своё место в толпе (диск со сдвигом,
		# goblin_config.horde_offset), и оно же кладётся в разметку отряда —
		# чтобы смыкание после боя собирало ТОЛПУ, а не квадрат фаланги
		var slots: Array = []
		var n: int = members.size()
		for k in range(n):
			var ho: Vector2 = _GobCfg.horde_offset(k, n, int(sq["id"]))
			slots.append(Vector3(goal.x + ho.x, 0.0, goal.z + ho.y))
		GameManager.squad_set_formation(int(sq["id"]), slots,
			(goal - center).normalized() if goal.distance_to(center) > 0.1 else Vector3.FORWARD,
			false)
		for k2 in range(n):
			if not is_instance_valid(members[k2]):
				continue
			var u2 := members[k2] as Unit
			if u2 == null or u2.is_dead():
				continue
			u2.command_move(GameManager.land_target(slots[k2]))

## Ближайший чужой ЛЮБОЙ стороны. Гоблины враждебны всем, поэтому спрашиваем
## обе фракции и берём ближайшего
func _nearest_foe(from: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius * radius
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		var seen = GameManager.army.nearest_of_side(from.x, from.z, f, radius)
		if seen == null:
			continue
		var nd := seen as Node3D
		var d: float = from.distance_squared_to(nd.global_position)
		if d < bd:
			bd = d
			best = nd
	return best

func _squad_center(sq: Dictionary) -> Vector3:
	var live: Array = []
	for m in (sq["members"] as Array):
		if is_instance_valid(m) and not (m as Unit).is_dead():
			live.append(m)
	if live.is_empty():
		return village
	return GameManager._centroid_of(live)
