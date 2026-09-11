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
##                еду и нанимает армию заново до полного штата орды
##                (goblin_config.army_squads()).
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
const _Diff := preload("res://scripts/game_difficulty_config.gd")
const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _Commander := preload("res://scripts/goblin/GoblinAttackCommander.gd")

## Командир штурма базы (заказ 10.09.2026): сбор на дистанции, паттерны,
## отход и лечение. Ведёт полевые отряды в фазе охоты, см. _issue_orders
var commander = _Commander.new()
## Стенд: цель охоты вместо _weakest_target (INF — не задана)
var hunt_target_override: Vector3 = Vector3.INF

# ── РОЛИ ОТРЯДА ─────────────────────────────────────────────────────────────
const ROLE_DORMANT := "dormant"   # спит в деревне
const ROLE_CENTER  := "center"    # штурмует центр карты
const ROLE_HUNT    := "hunt"      # добивает самого слабого игрока
const ROLE_DEFEND  := "defend"    # держит деревню
const ROLE_HEAL    := "heal"      # разбит, уходит в хижину лечиться
const ROLE_REVENGE := "revenge"   # месть: держит дерево тролля

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
	commander.reset()
	hunt_target_override = Vector3.INF
	phase = PHASE_DORMANT
	clock = 0.0
	_think = 0.0
	_awake = false
	last_action = ""
	_order_queue.clear()
	_order_at = 0
	_revenge_sids.clear()
	_revenge_last = -1.0e9
	revenge_waves = 0

# ═════════════════════════════════════════════════════════════════════════════
# МЕСТЬ ГОБЛИНОВ (заказ владельца, 09.09.2026)
# ═════════════════════════════════════════════════════════════════════════════
# Логово тролля зачищено → раз в REVENGE_INTERVAL_SEC из деревни выходят
# REVENGE_SQUADS отрядов пехоты и маршируют через всю карту окружать и держать
# дерево тролля. Идут НЕЗАВИСИМО от спячки и волн орды: это не волна, а
# отдельное расписание, и роль у них своя (ROLE_REVENGE) — раздача целей по
# фазе их не трогает. Спящими они не засыпают (см. _regroup)
var _revenge_sids: Dictionary = {}
var _revenge_last: float = -1.0e9
## Сколько волн мести вышло (диагностика стенда)
var revenge_waves: int = 0

func _tick_revenge() -> void:
	if not GameManager.troll_lair_cleared():
		return
	if clock - _revenge_last < _GobCfg.REVENGE_INTERVAL_SEC:
		return
	_revenge_last = clock
	revenge_waves += 1
	var lair: Node3D = GameManager.troll_lair as Node3D
	var n_per: int = int(_GobCfg.SQUAD_SIZE.get(_GobCfg.REVENGE_UNIT, 20))
	for i in range(_GobCfg.REVENGE_SQUADS):
		var a: float = TAU * float(i) / float(_GobCfg.REVENGE_SQUADS)
		var r: float = _GobCfg.VILLAGE_RADIUS + _GobCfg.horde_radius(n_per) + 4.0
		var base := Vector3(village.x + cos(a) * r, 0.0, village.z + sin(a) * r)
		var sid: int = int(main.call("spawn_goblin_squad", _GobCfg.REVENGE_UNIT, n_per, base))
		if sid <= 0:
			continue
		_revenge_sids[sid] = i
	last_action += "|месть: %d отрядов идут к дереву тролля" % _GobCfg.REVENGE_SQUADS
	if lair == null:
		return
	# Реестр подхватит их в следующем _regroup; роль ставится там же

## Точка отряда мести на кольце вокруг дерева
func _revenge_goal(sid: int) -> Vector3:
	var lair: Node3D = GameManager.troll_lair as Node3D
	if lair == null or not is_instance_valid(lair):
		return village
	var idx: int = int(_revenge_sids.get(sid, 0))
	var a: float = TAU * float(idx) / float(maxi(_GobCfg.REVENGE_SQUADS, 1))
	return lair.global_position + Vector3(cos(a) * _GobCfg.REVENGE_RING, 0.0,
		sin(a) * _GobCfg.REVENGE_RING)

func _process(delta: float) -> void:
	if main == null:
		return
	clock += delta
	# Недоразданные приказы прошлого такта — по порции за кадр (см. _drain_orders)
	_drain_orders()
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
	# Месть идёт по своим часам, спячка орды ей не указ
	_tick_revenge()
	if not _awake:
		# ── СПЯЧКА ──────────────────────────────────────────────────────────
		# Просыпаемся по часам ИЛИ раньше, если орду пришли бить: спящий боец
		# не отвечает на удар вовсе, и без этой оговорки разведчик игрока
		# вырезал бы деревню бесплатно за полчаса до её пробуждения
		# Срок спячки крутит сложность: на Hard орда просыпается раньше
		var wake_at: float = _Diff.goblin_dormant_sec()
		if clock < wake_at and not _attacked():
			last_action = "спит (%.0f с до подъёма)" % (wake_at - clock)
			# Месть не спит: её отрядам приказы раздаются и в спячке орды
			if not _revenge_sids.is_empty():
				_issue_orders(true)
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
	u.set_tick(not on)
	# ── ВИЗУАЛЬНЫЙ ТИК СПЯЩЕМУ НЕ ГАСИМ ────────────────────────────────────
	# Здесь стояло set_draw(not on), и это была дыра в тумане войны. Гоблин
	# прячется от чужих глаз САМ, веткой внутри tick_visual (Unit._hide_in_fog):
	# погасив ему визуальный тик, мы отняли у него единственный способ это
	# сделать — и семьсот спящих в деревне продолжали рисоваться игроку сквозь
	# неразведанную черноту. Ровно это владелец и увидел: «отряды орков в
	# тумане продолжают рендериться».
	#
	# Платы за это почти нет: стоящий боец гасит свой визуальный тик сам, через
	# пару кадров (Unit._proc_sleeping), а будит его редкий общий обход
	# GameManager._wake_returned_far_units — раз в пятнадцать физкадров и ровно
	# на один кадр. Тот же путь, которым живут все прочие стоящие войска.
	# Выключенным остаётся ФИЗИЧЕСКИЙ тик и бит F_DORMANT в солвере — то есть
	# вся та экономия, ради которой спячка и заводилась
	if not on:
		u.set_draw(true)
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
		# ТРОЛЛИ — СТРАЖИ ЛОГОВА, А НЕ ВОЛНА: вожак их не водит и не усыпляет
		if u.stat_id == "troll":
			continue
		var rec: Variant = known.get(u.squad_id)
		if rec == null:
			var role: String = ROLE_REVENGE if _revenge_sids.has(u.squad_id) else ROLE_DEFEND
			rec = {"id": u.squad_id, "type": u.stat_id, "members": [],
				"role": role, "target": village, "peak": 0}
			known[u.squad_id] = rec
			squads.append(rec)
		var arr: Array = (rec as Dictionary)["members"]
		if not arr.has(u):
			arr.append(u)
			# Спящему бойцу сон ставится в момент зачисления: свежий выходит
			# из хижины уже проснувшимся, стартовый — спящим. Отряд мести
			# не спит никогда — он вышел по своим часам
			if not _awake and not _revenge_sids.has(u.squad_id):
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
## Ранга новобранцам не полагается (заказ владельца): знамя есть только у тех
## стартовых отрядов, которым его выдала goblin_config.START_SQUADS
func _economy() -> void:
	if squads.size() >= _GobCfg.army_squads():
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
	for t in _GobCfg.army_composition():
		want[String(t)] = int(want.get(String(t), 0)) + 1
	for t in want:
		if int(have.get(String(t), 0)) < int(want[t]):
			return String(t)
	return String(_GobCfg.army_composition()[0])

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
			if squads.size() >= _GobCfg.army_squads():
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
# ─────────────────────────────────────────────────────────────────────────────
# РАЗДАЧА ПРИКАЗОВ: РЕШЕНИЕ СРАЗУ, ИСПОЛНЕНИЕ ПОРЦИЯМИ И ТОЛЬКО ПО ДЕЛУ
# ─────────────────────────────────────────────────────────────────────────────
# Зонд qa_mass3k/AIProbe (сент. 2026) поймал здесь горб 46-72 мс КАЖДЫЙ такт:
# _issue_orders выдавал command_attack/command_move КАЖДОМУ из тысячи гоблинов
# в один кадр и КАЖДЫЕ две секунды, даже когда ни фаза, ни цель, ни точка не
# менялись. На кадре свалки это читалось как стабильные ~2.4 мс «мышления ИИ»
# (замер qa_mass3k) — рывок, размазанный усреднением по секунде.
#
# Лечение — ДВА приёма красного ИИ, перенесённые сюда дословно:
#  1) НЕИЗМЕНИВШИЙСЯ ПРИКАЗ НЕ ПЕРЕИЗДАЁТСЯ (правило stagnant target,
#     EnemyAI._posts_intact). Отряд, уже втянутый в бой, новых приказов не
#     получает вовсе — бойцов ведут сцепка, авто-агро и подтягивание фланга;
#     переиздание только дёргало их (command_attack будит, метит позу грязной
#     и переставляет стену — см. «цена костыля была не там, где её мерили»).
#     Марш к той же точке переиздаётся не чаще REISSUE_KEEPALIVE_SEC —
#     страховка от застрявших остаётся, но вчетверо реже.
#  2) РАЗДАЧА НАРЕЗАНА ПО КАДРАМ (EnemyAI._drain_orders): решение по всем
#     отрядам принимается одним тактом (картина мира согласована), а дорогие
#     обходы состава складываются в очередь и разбираются по
#     ORDER_BUDGET_MEMBERS бойцов за кадр.
var _order_queue: Array = []
var _order_at: int = 0
const ORDER_BUDGET_MEMBERS := 150
## Как часто повторять марш В ТУ ЖЕ точку отряду вне боя (страховка от
## застрявших). Прежние две секунды (каждый такт) были не страховкой, а
## основной статьёй расхода кадра
const REISSUE_KEEPALIVE_SEC := 8.0

func _drain_orders() -> void:
	if _order_at >= _order_queue.size():
		return
	var left: int = ORDER_BUDGET_MEMBERS
	while _order_at < _order_queue.size() and left > 0:
		var plan: Dictionary = _order_queue[_order_at]
		_order_at += 1
		left -= _issue_squad(plan)
	if _order_at >= _order_queue.size():
		_order_queue.clear()
		_order_at = 0

func _issue_orders(only_revenge: bool = false) -> void:
	var aim := village
	match phase:
		PHASE_CENTER: aim = Vector3.ZERO           # центр карты
		PHASE_HUNT:
			aim = _weakest_target() if hunt_target_override == Vector3.INF else hunt_target_override
			if aim == Vector3.ZERO:
				aim = Vector3.ZERO
		PHASE_DEFEND: aim = village
	# Недоразобранный план прошлого такта выбрасывается целиком: обстановка
	# пересчитана, и выдавать поверх неё вчерашние приказы хуже, чем не выдать
	_order_queue.clear()
	_order_at = 0
	# ── ШТУРМ БАЗЫ ВЕДЁТ КОМАНДИР (заказ 10.09.2026) ─────────────────────────
	# В фазе охоты полевые отряды (не месть, не лечащиеся) получают план от
	# GoblinAttackCommander: сбор на дистанции, паттерн, отход и лечение.
	# Прежняя лавина остаётся для центра карты и обороны деревни
	# Режимов три (уточнение владельца): охота — штурм базы, центр — марш с
	# дозором, оборона деревни — рубеж у костров и фланговые уколы конницы
	var tactical: Dictionary = {}
	if _GobCfg.ASSAULT_TACTICS and not only_revenge \
			and (phase == PHASE_HUNT or phase == PHASE_CENTER or phase == PHASE_DEFEND):
		var field: Array = []
		var role: String = ROLE_HUNT if phase == PHASE_HUNT else \
			(ROLE_CENTER if phase == PHASE_CENTER else ROLE_DEFEND)
		for s0 in squads:
			var sq0: Dictionary = s0
			if String(sq0["role"]) == ROLE_HEAL or (sq0["members"] as Array).is_empty():
				continue
			if String(sq0["role"]) == ROLE_REVENGE or _revenge_sids.has(int(sq0["id"])):
				continue
			sq0["role"] = role
			sq0["target"] = aim
			field.append(sq0)
			tactical[int(sq0["id"])] = true
		var plans: Array = []
		match phase:
			PHASE_HUNT:   plans = commander.plan(field, aim, village, clock)
			PHASE_CENTER: plans = commander.plan_advance(field, aim, village, clock)
			_:            plans = commander.plan_defense(field, village, clock)
		for plan in plans:
			_order_queue.append(plan)
		if commander.last_action != "":
			last_action += "|" + commander.last_action
	elif commander.is_active():
		commander.reset()
	var i := 0
	for s in squads:
		var sq: Dictionary = s
		if String(sq["role"]) == ROLE_HEAL:
			continue                       # отход ведёт хижина, свой приказ его отменит
		var members: Array = sq["members"]
		if members.is_empty():
			continue
		var sid: int = int(sq["id"])
		if tactical.has(sid):
			continue                       # приказы этого отряда уже в плане командира
		if only_revenge and not (String(sq["role"]) == ROLE_REVENGE or _revenge_sids.has(sid)):
			continue
		# Отряды расходятся по фронту, а не лезут в одну точку
		var spread: float = 8.0 * float(i - squads.size() / 2)
		var goal := Vector3(aim.x + spread, 0.0, aim.z)
		i += 1
		# ОТРЯД МЕСТИ ДЕРЖИТ ДЕРЕВО ТРОЛЛЯ, фазы орды его не касаются
		if String(sq["role"]) == ROLE_REVENGE or _revenge_sids.has(sid):
			sq["role"] = ROLE_REVENGE
			goal = _revenge_goal(sid)
		else:
			sq["role"] = ROLE_CENTER if phase == PHASE_CENTER else \
				(ROLE_HUNT if phase == PHASE_HUNT else ROLE_DEFEND)
		sq["target"] = goal
		var center := _squad_center(sq)
		# Цель поблизости — атакуем её; нет — идём к точке
		var foe: Node3D = _nearest_foe(center, _GobCfg.CENTER_RADIUS)
		# ── ПОСТРОЙКИ ТОЖЕ ЦЕЛЬ (заказ 10.09.2026) ──────────────────────
		# Орда доходила до чужой базы и вставала «у стены»: приказ атаки
		# раздавался только по бойцам, а дома вокруг были не при чём. Нет
		# бойца в радиусе — ближайший чужой дом в BUILDING_HUNT_RADIUS
		# получает тот же command_attack (охрана деревни и месть — нет:
		# у них своя цель)
		if foe == null and String(sq["role"]) != ROLE_REVENGE and phase != PHASE_DEFEND:
			foe = _nearest_enemy_building(center, _GobCfg.BUILDING_HUNT_RADIUS)
		if foe != null:
			# ОТРЯД УЖЕ ДЕРЁТСЯ — НЕ ТРОГАТЬ. Приказ нужен один раз, на входе
			# в бой; дальше цели раздают сцепка и авто-агро, а переиздание
			# каждые две секунды только будило и передёргивало всю орду
			if GameManager.squad_in_combat(sid):
				continue
			_order_queue.append({"sq": sq, "foe": foe})
			continue
		# Марш в ту же точку не переиздаётся чаще страховочного срока
		var prev_goal: Vector3 = sq.get("ordered_goal", Vector3.INF)
		var prev_at: float = float(sq.get("ordered_at", -1.0e9))
		if prev_goal.distance_to(goal) < 0.5 \
				and clock - prev_at < REISSUE_KEEPALIVE_SEC:
			continue
		_order_queue.append({"sq": sq, "goal": goal, "center": center})

## Исполнить одну запись плана (обход состава — дорогая часть).
## Возвращает число бойцов, которым выдан приказ, — им и меряется бюджет кадра
func _issue_squad(plan: Dictionary) -> int:
	var sq: Dictionary = plan["sq"]
	var members: Array = sq["members"]
	var issued := 0
	# Живость — на СЫРОЙ ссылке, до приведения типа (правило 5): цель могла
	# пасть, пока запись ждала своего кадра, а типизированное присваивание
	# освобождённого объекта не даёт null — оно бросает исключение
	var foe_raw: Variant = plan.get("foe")
	if foe_raw != null:
		if not is_instance_valid(foe_raw):
			return 0
		var foe := foe_raw as Node3D
		# Приказ командира штурма снимает режим отхода (щуп вернулся к линии
		# и снова идёт в бой): в отходе боец не берёт целей вовсе
		var wake: bool = bool(plan.get("wake", false))
		for m in members:
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u != null and not u.is_dead():
				if wake and u.retreating:
					u.end_retreat(true)
				u.command_attack(foe, true, true)
				issued += 1
		return issued
	var goal: Vector3 = plan["goal"]
	var center: Vector3 = plan["center"]
	sq["ordered_goal"] = goal
	sq["ordered_at"] = clock
	# ── ОТХОД (командир штурма): режим отхода — сквозь тела, без агро и
	# ответного удара, разметка снята; в лагере отряд стоит толпой у костров
	if bool(plan.get("retreat", false)):
		# Разметка НЕ снимается, а ставится на лагерь: дойдя, отряд стоит у
		# костров толпой, и смыкание собирает его там же (хижина снимает
		# разметку потому, что её отряд уходит в ворота — здесь он остаётся)
		var nr: int = members.size()
		var rslots: Array = []
		for kr in range(nr):
			var hr: Vector2 = _GobCfg.horde_offset(kr, nr, int(sq["id"]))
			rslots.append(Vector3(goal.x + hr.x, 0.0, goal.z + hr.y))
		GameManager.squad_set_formation(int(sq["id"]), rslots,
			(goal - center).normalized() if goal.distance_to(center) > 0.1 else Vector3.FORWARD,
			false)
		for kr2 in range(nr):
			if not is_instance_valid(members[kr2]):
				continue
			var ur := members[kr2] as Unit
			if ur == null or ur.is_dead():
				continue
			ur.begin_retreat()
			ur.command_move(GameManager.land_target(rslots[kr2]), false, Vector3.ZERO, true)
			issued += 1
		return issued
	# ── ТОЛПОЙ, А НЕ В ОДНУ ТОЧКУ ───────────────────────────────────────────
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
	var wake2: bool = bool(plan.get("wake", false))
	for k2 in range(n):
		if not is_instance_valid(members[k2]):
			continue
		var u2 := members[k2] as Unit
		if u2 == null or u2.is_dead():
			continue
		if wake2 and u2.retreating:
			u2.end_retreat(true)
		u2.command_move(GameManager.land_target(slots[k2]))
		issued += 1
	return issued

## Ближайший чужой ЛЮБОЙ стороны. Гоблины враждебны всем, поэтому спрашиваем
## обе фракции и берём ближайшего
## Ближайшая живая чужая постройка (игрока или красного ИИ) не дальше radius
func _nearest_enemy_building(from: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var bd: float = radius * radius
	for b in GameManager.enemy_buildings_snapshot(Constants.FACTION_GOBLIN):
		if b == null or not is_instance_valid(b):
			continue
		var bld := b as Building
		if bld == null or bld.is_dead():
			continue
		var d: float = from.distance_squared_to(bld.global_position)
		if d < bd:
			bd = d
			best = bld
	return best

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
