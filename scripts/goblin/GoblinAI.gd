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
const _OptGA := preload("res://scripts/perf_config.gd")
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
# ── РОЛИ ГЛАВНОГО ЦИКЛА (спринт 17) ─────────────────────────────────────────
const ROLE_GARRISON   := "garrison"   # элитный гарнизон деревни, не выходит никогда
const ROLE_MINE_GUARD := "mine_guard" # охрана рудника орды, патруль кольцом
const ROLE_MINE_ALARM := "mine_alarm" # тревога: вся орда идёт к своему руднику
const ROLE_MINE_HOLD  := "mine_hold"  # резерв на захваченном руднике холма
const ROLE_SCOUT      := "scout"      # разведчик, обходит точки интереса
const ROLE_RAID       := "raid"       # рейд по экономике противника

# ── ФАЗА ОРДЫ ───────────────────────────────────────────────────────────────
const PHASE_DORMANT := "dormant"
const PHASE_CENTER  := "center"
const PHASE_HUNT    := "hunt"
const PHASE_DEFEND  := "defend"
## Разведка и рейды между экспансией и генеральным наступлением (спринт 17)
const PHASE_HARASS  := "harass"
## Мирная фаза: отстройка и патруль границ деревни (0 — PEACE_SEC)
const PHASE_PEACE   := "peace"
const ROLE_BORDER   := "border"     # патруль границ деревни в мире

var main: Node3D = null
var village: Vector3 = Vector3.ZERO
## Отряды орды: [{ "id", "type", "members", "role", "target", "peak" }]
var squads: Array = []
var phase: String = PHASE_DORMANT
var clock: float = 0.0            # игровое время партии, сек
var last_action: String = ""      # диагностика для стенда

var _think: float = 0.0
var _awake: bool = false

# ── СОСТОЯНИЕ ГЛАВНОГО ЦИКЛА (спринт 17) ────────────────────────────────────
var garrison_sids: Dictionary = {}
var mine_guard_sids: Dictionary = {}
var mine: Node = null                 # рудник орды у деревни
var mine_alarm_until: float = -1.0e9  # часы вожака; пока не истекли — тревога
var mine_alarms: int = 0
var scout_sid: int = 0
var _scout_wp: int = 0
var _scout_at: float = -1.0e9
## Состояние разведчика: "out" — обход, "harass" — точечный укол у найденной
## базы, "home" — отход в деревню и передышка
var scout_state: String = "out"
var _scout_state_at: float = -1.0e9
var scout_sorties: int = 0
var scout_harasses: int = 0
var known_bases: Dictionary = {}      # фракция → точка чужой базы, что нашла разведка
var raid_sids: Dictionary = {}        # sid → часы начала рейда
var _raid_last: float = -1.0e9
var raids_launched: int = 0
var raid_retreats: int = 0
var raid_returns: int = 0             # рейдов, вернувшихся без добычи (спринт 20)
var _harass_since: float = 0.0
## ── ГОРН ОРДЫ (спринт 18) ────────────────────────────────────────────────
## Триггер 1 — первый контакт сторон: игрок впервые видит отряд или деревню
## орды (точка освещена его туманом) ЛИБО орда впервые видит войска игрока
## (боец игрока в обзоре какого-нибудь отряда). Один раз за партию.
## Триггер 2 — начало общего наступления: выход всей армии к центру или на
## базу (переходы фаз → CENTER / → HUNT)
var first_contact: bool = false
var horn_blows: int = 0
var hill_mine_sid: int = 0

## Регистрация из Main: гарнизон и охрана рудника
func register_garrison(sid: int) -> void:
	garrison_sids[sid] = true

func register_mine_guard(sid: int) -> void:
	mine_guard_sids[sid] = true

## ── ДРЕМЛЮЩИЙ РЕЗЕРВ (13.09.2026, DormantReserve.gd) ────────────────────────
## Отряды резерва — особые: вне волн, вне планов командира, вне пробуждения
## орды. Спят и просыпаются своим контроллером; вожак берёт у него конницу
## на вылазку (borrow_cavalry) и ведёт её обычным рейдом
var reserve = null
var reserve_sids: Dictionary = {}
var reserve_raids: int = 0

func register_reserve(sid: int) -> void:
	reserve_sids[sid] = true

func attach_reserve(r) -> void:
	reserve = r

func attach_mine(m: Node) -> void:
	mine = m
	if m != null and m.has_signal("attacked"):
		m.connect("attacked", _on_mine_attacked)

## Тревога рудника: продлевается каждым ударом
func _on_mine_attacked(_by: int, _at: Vector3) -> void:
	mine_alarm_until = clock + _GobCfg.MINE_ALARM_SEC
	mine_alarms += 1

func mine_alarm_active() -> bool:
	return clock < mine_alarm_until and mine != null and is_instance_valid(mine) \
		and not bool(mine.call("is_dead"))

## Отряды ВОЛНЫ — без гарнизона, охраны рудника и мести: по ним считается
## «армия набрана» (найм и переход в наступление)
func _wave_squads() -> int:
	var n := 0
	for s in squads:
		if not _is_special(int((s as Dictionary)["id"])):
			n += 1
	return n

## Особые роли не входят ни в волны, ни в планы командира
func _is_special(sid: int) -> bool:
	return garrison_sids.has(sid) or mine_guard_sids.has(sid) \
		or _revenge_sids.has(sid) or (sid > 0 and sid == scout_sid) \
		or reserve_sids.has(sid)

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
	garrison_sids.clear()
	mine_guard_sids.clear()
	mine_alarm_until = -1.0e9
	scout_sid = 0
	scout_state = "out"
	_scout_state_at = -1.0e9
	scout_sorties = 0
	scout_harasses = 0
	known_bases.clear()
	raid_sids.clear()
	_raid_last = -1.0e9
	_harass_since = 0.0
	hill_mine_sid = 0

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
	_sweep_heal()
	_tick_raids()
	if not first_contact:
		_check_first_contact()
	var was: String = phase
	_decide_phase()
	if phase != was and (phase == PHASE_CENTER or phase == PHASE_HUNT):
		_blow_horn("наступление: " + phase)
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
	# Само тело — Unit.set_dormant (15.09.2026): тем же путём спит охрана
	# крепости красного ИИ, здесь остался только гоблинский выключатель
	# и разбор ниже — почему гасится ровно то, что гасится
	u.set_dormant(on)
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
	# вся та экономия, ради которой спячка и заводилась.
	# И ПАКЕТНЫЕ ПРОХОДЫ ТОЖЕ. Тик бойца можно отключить снаружи, а вот
	# расталкивание союзников идёт по КОЛОНКАМ и о выключенном тике не знает:
	# семьсот спящих продолжали разводиться каждый кадр. Замер (qa_mass_battle,
	# 3000 бойцов + деревня): свалка 16.5 -> 11.5 мс на одном этом бите

## Длина мирной фазы: по сложности, а при выключенном чекбоксе «Перемирие»
## (game_settings.armistice, ТЗ 14.09.2026 п. 2) — ноль: орда сразу в поле
func _peace_sec() -> float:
	if not GameManager.truce_enabled():
		return 0.0
	return _Diff.goblin_peace_sec()

func _wake_horde() -> void:
	_awake = true
	# Проснулись — сначала мирная фаза (патруль границ), если она ещё идёт
	phase = PHASE_PEACE if clock < _peace_sec() else PHASE_CENTER
	for s in squads:
		# Резерв спит своим сном — его будит только штурм лагеря
		if reserve_sids.has(int((s as Dictionary)["id"])):
			continue
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
	if _wave_squads() >= _GobCfg.army_squads():
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

## ОТРЯД, НЕ ДОШЕДШИЙ ДО ХИЖИНЫ, ВОЗВРАЩАЕТСЯ В ПОЛЕ (спринт 17). Роль HEAL
## ставится по request_garrison, а поход к воротам сторож хижины ОТМЕНЯЕТ,
## если боец дерётся без режима отхода (Castle._process_garrison). Отряд
## оставался в HEAL навсегда: приказов ему не раздают, в поле он не считается
## — зонд длинной партии показал орду из 18 отрядов с пустым полем, которая
## 16 минут переключала «центр»/«оборона», не сделав ни шагу. Отряд, которого
## нет ни в очереди, ни внутри ни одной хижины, снова полевой; если он всё ещё
## разбит, _retreat_broken пошлёт его лечиться заново
func _sweep_heal() -> void:
	var huts: Array = _huts()
	for s in squads:
		var sq: Dictionary = s
		if String(sq["role"]) != ROLE_HEAL:
			continue
		var sid: int = int(sq["id"])
		var pending := false
		for h in huts:
			var c := h as Castle
			if c != null and (c._slot_of(sid) >= 0 or c._incoming.has(sid)):
				pending = true
				break
		if pending:
			continue
		sq["role"] = ROLE_DEFEND
		sq["issued"] = false
		last_action += "|отряд %d не дошёл до хижины, снова в поле" % sid

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
		PHASE_PEACE:
			if clock >= _peace_sec():
				phase = PHASE_CENTER
				last_action += "|мир кончился, экспансия к центру"
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
				# никого не было, и штурм отменялся, не начавшись.
				# ── СПРИНТ 17: после центра — разведка и рейды, а не сразу
				# штурм: генеральное наступление ждёт полной армии
				phase = PHASE_HARASS
				_harass_since = clock
				last_action += "|центр взят, разведка и рейды"
		PHASE_HARASS:
			if _field_squads() == 0:
				phase = PHASE_DEFEND
				last_action += "|поле пусто, оборона деревни"
			elif _village_threatened():
				phase = PHASE_DEFEND
				last_action += "|деревню атакуют, все домой"
			elif _assault_ready():
				phase = PHASE_HUNT
				last_action += "|кулак собран, генеральное наступление"
		PHASE_HUNT:
			if _field_squads() == 0:
				phase = PHASE_DEFEND
				last_action += "|волна выбита, оборона деревни"
		PHASE_DEFEND:
			if _wave_squads() >= _GobCfg.army_squads() and not _village_threatened():
				phase = PHASE_CENTER
				last_action += "|орда собрана, новая волна в центр"

func _blow_horn(why: String) -> void:
	horn_blows += 1
	last_action += "|горн (%s)" % why
	AudioManager.play_horn()

## Первый контакт: точка орды на свету у игрока или боец игрока в обзоре орды
func _check_first_contact() -> void:
	if first_contact:
		return
	var fog = GameManager.fog
	var lit_ok: bool = fog != null and is_instance_valid(fog) and bool(fog.enabled)
	var sight: float = _UCfg.vision_radius(float(_UCfg.STATS["goblin_spearman"]["attack_range"]))
	var pts: Array = [village]
	if mine != null and is_instance_valid(mine):
		pts.append((mine as Node3D).global_position)
	for s in squads:
		var sq: Dictionary = s
		if (sq["members"] as Array).is_empty():
			continue
		pts.append(_squad_center(sq))
	for p in pts:
		var c: Vector3 = p
		if lit_ok and fog.is_lit(c.x, c.z):
			first_contact = true
			_blow_horn("первый контакт: орду увидели")
			return
		var seen = GameManager.army.nearest_of_side(c.x, c.z, Constants.FACTION_PLAYER, sight)
		if seen != null:
			first_contact = true
			_blow_horn("первый контакт: орда увидела игрока")
			return

## Генеральное наступление: армия набрана, поле не пустое, рейды шли не меньше
## HARASS_MIN_SEC, и есть куда идти (база найдена разведкой либо известна по
## постройкам)
func _assault_ready() -> bool:
	if _wave_squads() < _GobCfg.army_squads():
		return false
	if clock - _harass_since < _GobCfg.HARASS_MIN_SEC:
		return false
	# Не раньше 35-й минуты (уточнение владельца): до того — центр, рудники,
	# точечные рейды
	if clock < _GobCfg.ASSAULT_EARLIEST_SEC:
		return false
	return _assault_target() != Vector3.ZERO

## Чужие у деревни (тот же радиус, что у обороны командира)
func _village_threatened() -> bool:
	var r: float = _GobCfg.DEFEND_RADIUS + _GobCfg.DEFEND_ALERT_PAD
	return _nearest_foe(village, r) != null

## Сколько отрядов реально в поле (не лечатся)
func _field_squads() -> int:
	var n := 0
	for s in squads:
		var sq: Dictionary = s
		if String(sq["role"]) == ROLE_HEAL or _is_special(int(sq["id"])):
			continue
		n += 1
	return n

## Орда уже дошла до центра? Считаем по центру масс всех полевых отрядов
func _horde_at_center() -> bool:
	var acc := Vector3.ZERO
	var n := 0
	for s in squads:
		var sq: Dictionary = s
		if String(sq["role"]) == ROLE_HEAL or _is_special(int(sq["id"])):
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

## Куда идёт генеральное наступление (спринт 17: «скрипт 30-й минуты» с
## охотой на слабейшего снят). База, которую НАШЛА РАЗВЕДКА, ближайшая к
## деревне; разведка ничего не нашла — ближайшая по постройкам. ZERO — идти
## некуда
func _assault_target() -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for f in known_bases:
		if not _target_faction_allowed(int(f)):
			continue
		var p: Vector3 = known_bases[f]
		var d: float = village.distance_squared_to(p)
		if d < bd:
			bd = d
			best = p
	if best != Vector3.ZERO:
		return best
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		if not _target_faction_allowed(f):
			continue
		var anchor := Vector3.ZERO
		var n := 0
		for b in main.get_tree().get_nodes_in_group(Constants.building_group(f)):
			if not is_instance_valid(b) or (b as Building).is_dead():
				continue
			anchor += (b as Node3D).global_position
			n += 1
		if n == 0:
			continue
		anchor /= float(n)
		var d2: float = village.distance_squared_to(anchor)
		if d2 < bd:
			bd = d2
			best = anchor
	return best

## Рудники, не принадлежащие орде (ничьи и чужие)
func _foreign_mines() -> Array:
	var out: Array = []
	for grp in ["neutral_buildings", Constants.building_group(Constants.FACTION_PLAYER),
			Constants.building_group(Constants.FACTION_ENEMY)]:
		for b in main.get_tree().get_nodes_in_group(grp):
			if b == null or not is_instance_valid(b):
				continue
			if b is Mine and not (b as Building).is_dead():
				out.append(b)
	return out

## Рудник на холме — ближайший к центру карты рудник, КРОМЕ рудника деревни.
## Захваченный ордой рудник холма остаётся «холмом» (14.09.2026): прежде
## брались только чужие, и резерв, захватив рудник, тут же уходил к
## следующему чужому за полкарты — «держит его» не выполнялось никогда
func _hill_mine() -> Node3D:
	var best: Node3D = null
	var bd := INF
	var mines: Array = _foreign_mines()
	for b in main.get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_GOBLIN)):
		if b != null and is_instance_valid(b) and b is Mine and not (b as Building).is_dead() and b != GameManager.goblin_mine:
			mines.append(b)
	for m in mines:
		var d: float = Vector2((m as Node3D).global_position.x,
			(m as Node3D).global_position.z).length_squared()
		if d < bd:
			bd = d
			best = m
	return best

# ═════════════════════════════════════════════════════════════════════════════
# РАЗВЕДКА И РЕЙДЫ (спринт 17)
# ═════════════════════════════════════════════════════════════════════════════
## Точки интереса разведчика: центр, рудники, углы противников
func _scout_waypoints() -> Array:
	var pts: Array = [Vector3.ZERO]
	for m in _foreign_mines():
		pts.append((m as Node3D).global_position)
	if main.has_method("gold_mine_spots"):
		for p in main.gold_mine_spots():
			pts.append(p)
	pts.append(main.PLAYER_BASE_ANCHOR)
	pts.append(main.ENEMY_BASE_ANCHOR)
	return pts

## Разведчик увидел чужую постройку — база этой стороны известна
func _scout_look(sq: Dictionary) -> void:
	var c: Vector3 = _squad_center(sq)
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		for b in main.get_tree().get_nodes_in_group(Constants.building_group(f)):
			if b == null or not is_instance_valid(b) or (b as Building).is_dead():
				continue
			if c.distance_to((b as Node3D).global_position) <= _GobCfg.SCOUT_SIGHT:
				if not known_bases.has(f):
					last_action += "|разведка нашла базу стороны %d" % f
				known_bases[f] = (b as Node3D).global_position
				break

## Разведка — МАЛЫЙ ОТРЯД (SCOUT_UNITS конных), свой и вне волны. Автомат:
## out — обход точек; harass — у найденной базы бьёт ближайшего рабочего
## SCOUT_HARASS_SEC; home — отход в деревню и передышка SCOUT_SORTIE_SEC.
## Возвращает план или пустой словарь
func _scout_plan(_field: Array) -> Dictionary:
	var sq: Dictionary = {}
	for s in squads:
		if int((s as Dictionary)["id"]) == scout_sid:
			sq = s
			break
	if sq.is_empty():
		# Разведчика нет — выпустить из деревни малый конный отряд
		scout_sid = 0
		if main == null or not main.has_method("spawn_goblin_squad"):
			return {}
		var nsid: int = main.spawn_goblin_squad("goblin_rider", _GobCfg.SCOUT_UNITS, village)
		if nsid <= 0:
			return {}
		scout_sid = nsid
		scout_state = "out"
		_scout_state_at = clock
		_scout_wp = 0
		_scout_at = -1.0e9
		scout_sorties += 1
		last_action += "|вышла разведка (%d конных)" % _GobCfg.SCOUT_UNITS
		_regroup()
		for s2 in squads:
			if int((s2 as Dictionary)["id"]) == scout_sid:
				sq = s2
		if sq.is_empty():
			return {}
	sq["role"] = ROLE_SCOUT
	var c: Vector3 = _squad_center(sq)
	_scout_look(sq)
	match scout_state:
		"harass":
			if clock - _scout_state_at >= _GobCfg.SCOUT_HARASS_SEC:
				scout_state = "home"
				_scout_state_at = clock
				last_action += "|разведка уколола и отходит"
				sq["target"] = village
				return {"sq": sq, "goal": village, "center": c, "retreat": true}
			var prey: Node3D = _raid_prey(c)
			if prey != null:
				sq["target"] = prey.global_position
				return {"sq": sq, "foe": prey, "wake": true}
			scout_state = "home"
			_scout_state_at = clock
			return {"sq": sq, "goal": village, "center": c, "retreat": true}
		"home":
			if c.distance_to(village) > _GobCfg.SCOUT_ARRIVE + 4.0:
				return {}                       # ещё идёт домой
			if clock - _scout_state_at < _GobCfg.SCOUT_SORTIE_SEC:
				return {}                       # передышка
			scout_state = "out"
			_scout_state_at = clock
			_scout_wp = 0
			_scout_at = -1.0e9
			scout_sorties += 1
	# out: обход точек интереса; у найденной базы — короткий укол
	for f in known_bases:
		if c.distance_to(known_bases[f]) <= _GobCfg.SCOUT_SIGHT:
			scout_state = "harass"
			_scout_state_at = clock
			scout_harasses += 1
			last_action += "|разведка нашла базу, точечный укол"
			var prey2: Node3D = _raid_prey(c)
			if prey2 != null:
				sq["target"] = prey2.global_position
				return {"sq": sq, "foe": prey2, "wake": true}
			break
	var pts: Array = _scout_waypoints()
	if pts.is_empty():
		return {}
	_scout_wp = _scout_wp % pts.size()
	var goal: Vector3 = pts[_scout_wp]
	if c.distance_to(goal) <= _GobCfg.SCOUT_ARRIVE:
		if _scout_at < 0.0:
			_scout_at = clock
		elif clock - _scout_at >= _GobCfg.SCOUT_DWELL_SEC:
			_scout_wp = (_scout_wp + 1) % pts.size()
			_scout_at = -1.0e9
			goal = pts[_scout_wp]
	sq["target"] = goal
	return {"sq": sq, "goal": goal, "center": c, "wake": true}

## Рейды: раз в RAID_INTERVAL_SEC отправить малую или крупную группу на
## экономику известной базы. Ведётся в такте (см. tick): цель уточняется
## каждый такт, отход — по запасу, сопротивлению или сроку
func _tick_raids() -> void:
	if phase != PHASE_HARASS or known_bases.is_empty() or mine_alarm_active():
		return
	# Действующие рейды: снять выбывших
	var gone: Array = []
	for sid in raid_sids:
		var found := false
		for s in squads:
			if int((s as Dictionary)["id"]) == int(sid) \
					and String((s as Dictionary)["role"]) != ROLE_HEAL:
				found = true
		if not found:
			gone.append(sid)
	for sid in gone:
		raid_sids.erase(sid)
	if not raid_sids.is_empty():
		return
	if clock - _raid_last < _GobCfg.RAID_INTERVAL_SEC:
		return
	var want: int = _GobCfg.RAID_SQUADS_BIG if (raids_launched % 2 == 1) else _GobCfg.RAID_SQUADS_SMALL
	var picked := 0
	# ── КОННИЦА РЕЗЕРВА — ПЕРВОЙ (13.09.2026) ──────────────────────────────
	# Вылазка hit & run через брод: 1-2 конных отряда из дремлющего резерва,
	# режут одиночек и рабочих, при угрозе отходят НА ПОСТ лечиться
	if reserve != null and is_instance_valid(reserve):
		for sid_r in reserve.borrow_cavalry(mini(want, _GobCfg.RESERVE_LEND_MAX)):
			raid_sids[int(sid_r)] = clock
			picked += 1
			reserve_raids += 1
	# Конные — первыми: рейд это скорость
	for pass_i in range(2):
		for s in squads:
			var sq: Dictionary = s
			var sid: int = int(sq["id"])
			if picked >= want:
				break
			if String(sq["role"]) == ROLE_HEAL or _is_special(sid) or sid == scout_sid \
					or sid == hill_mine_sid or raid_sids.has(sid):
				continue
			var cav: bool = String(sq["type"]) == "goblin_rider"
			if pass_i == 0 and not cav:
				continue
			raid_sids[sid] = clock
			picked += 1
	if picked > 0:
		_raid_last = clock
		raids_launched += 1
		last_action += "|рейд №%d, отрядов %d" % [raids_launched, picked]

## ── ЗАЩИТА КРАСНОГО ИИ (спринт 20) ──────────────────────────────────────
## По базе ИИ-человека орда работает не раньше AI_PROTECT_SEC и только когда
## у него стоит крепость: иначе диверсанты вырезали бы пять рабочих на старте
var ai_protect_refusals: int = 0

func _target_faction_allowed(f: int) -> bool:
	if f != Constants.FACTION_ENEMY:
		return true
	if clock < _GobCfg.AI_PROTECT_SEC:
		ai_protect_refusals += 1
		return false
	for b in main.get_tree().get_nodes_in_group(Constants.building_group(f)):
		if b == null or not is_instance_valid(b):
			continue
		var bld := b as Building
		if bld != null and not bld.is_dead() and bld.has_method("is_stronghold") \
				and bool(bld.call("is_stronghold")):
			return true
	ai_protect_refusals += 1
	return false

## Цель рейда у известной базы: рабочий → одиночная постройка (не крепость).
## null — целей нет, идём к базе
func _raid_prey(base: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		if not _target_faction_allowed(f):
			continue
		for n in main.get_tree().get_nodes_in_group(Constants.unit_group(f)):
			if n == null or not is_instance_valid(n):
				continue
			var u := n as Unit
			if u == null or u.is_dead() or u.garrisoned or not (u is Worker):
				continue
			var d: float = base.distance_squared_to(u.global_position)
			if d < bd and d <= _GobCfg.RAID_HUNT_RADIUS * _GobCfg.RAID_HUNT_RADIUS:
				bd = d
				best = u
	if best != null:
		return best
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		if not _target_faction_allowed(f):
			continue
		for b in main.get_tree().get_nodes_in_group(Constants.building_group(f)):
			if b == null or not is_instance_valid(b):
				continue
			var bld := b as Building
			if bld == null or bld.is_dead():
				continue
			if bld.has_method("is_stronghold") and bool(bld.call("is_stronghold")):
				continue
			var d2: float = base.distance_squared_to(bld.global_position)
			if d2 < bd and d2 <= _GobCfg.RAID_HUNT_RADIUS * _GobCfg.RAID_HUNT_RADIUS:
				bd = d2
				best = bld
	return best

## Сколько боевых чужих рядом с точкой (сопротивление рейду)
func _foes_near(p: Vector3, r: float) -> int:
	var n := 0
	for m in GameManager.unit_grid.query_radius(p, r):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead() or u is Worker or int(u.faction) == Constants.FACTION_GOBLIN:
			continue
		n += 1
	return n

## План одного рейд-отряда: атака добычи или отход домой лечиться
func _raid_plan(sq: Dictionary) -> Dictionary:
	var sid: int = int(sq["id"])
	var c: Vector3 = _squad_center(sq)
	var peak: int = maxi(int(sq.get("peak", 1)), 1)
	var alive: int = (sq["members"] as Array).size()
	var weak: bool = float(alive) < float(peak) * _GobCfg.RAID_RETREAT_HP
	var resisted: bool = _foes_near(c, _GobCfg.RAID_FLEE_RADIUS) >= _GobCfg.RAID_FLEE_FOES
	var expired: bool = clock - float(raid_sids.get(sid, clock)) > _GobCfg.RAID_MAX_SEC
	if weak or resisted or expired:
		raid_sids.erase(sid)
		raid_retreats += 1
		last_action += "|рейд %d отходит (%s)" % [sid,
			"мало запаса" if weak else ("сопротивление" if resisted else "срок")]
		# Конница резерва возвращается на СВОЙ пост и лечится там, а не в хижине
		if reserve_sids.has(sid) and reserve != null and is_instance_valid(reserve):
			sq["role"] = ROLE_DEFEND
			var post: Vector3 = reserve.return_squad(sid)
			return {"sq": sq, "goal": post, "center": c, "retreat": true}
		sq["role"] = ROLE_HEAL
		var hut := _nearest_hut(c)
		if hut != null and hut.request_garrison(sid):
			return {}
		# Хижина полна — отход к деревне в режиме отхода
		return {"sq": sq, "goal": village, "center": c, "retreat": true}
	var base := Vector3.ZERO
	var bd := INF
	for f in known_bases:
		if not _target_faction_allowed(int(f)):
			continue
		var d: float = c.distance_squared_to(known_bases[f])
		if d < bd:
			bd = d
			base = known_bases[f]
	sq["role"] = ROLE_RAID
	var prey: Node3D = _raid_prey(base if base != Vector3.ZERO else c)
	if prey != null:
		sq["target"] = prey.global_position
		return {"sq": sq, "foe": prey, "wake": true}
	# ── ДОБЫЧИ НЕТ — ДИВЕРСАНТЫ НЕ ПАСУТСЯ В УГЛУ ЧУЖОЙ БАЗЫ (спринт 20) ──
	# Прежде отряд шёл к базе и стоял там до срока рейда. Теперь рейд, у
	# которого некого бить (или база ещё не найдена), кончается сразу: отряд
	# возвращается в поле — к центру/деревне общим порядком
	if base == Vector3.ZERO or clock - float(raid_sids.get(sid, clock)) > _GobCfg.RAID_IDLE_SEC:
		raid_sids.erase(sid)
		raid_returns += 1
		if reserve_sids.has(sid) and reserve != null and is_instance_valid(reserve):
			sq["role"] = ROLE_DEFEND
			var post2: Vector3 = reserve.return_squad(sid)
			return {"sq": sq, "goal": post2, "center": c, "wake": true}
		sq["role"] = ROLE_CENTER
		last_action += "|рейд %d без добычи — домой" % sid
		return {"sq": sq, "goal": village if phase == PHASE_DEFEND else Vector3.ZERO,
			"center": c, "wake": true}
	sq["target"] = base
	return {"sq": sq, "goal": base, "center": c, "wake": true}

## Охрана рудника: патруль кольцом, на тревоге — бой у рудника
func _mine_guard_plan(sq: Dictionary, idx: int) -> Dictionary:
	if mine == null or not is_instance_valid(mine):
		return {}
	var mp: Vector3 = (mine as Node3D).global_position
	var c: Vector3 = _squad_center(sq)
	sq["role"] = ROLE_MINE_GUARD
	var foe: Node3D = _nearest_foe(mp, _GobCfg.CENTER_RADIUS)
	if foe != null:
		if GameManager.squad_in_combat(int(sq["id"])):
			return {}
		return {"sq": sq, "foe": foe}
	var slot: int = int(floor(clock / _GobCfg.MINE_GUARD_PATROL_SEC)) + idx
	var ang: float = TAU * float(slot % 6) / 6.0
	var goal := Vector3(mp.x + cos(ang) * _GobCfg.MINE_GUARD_PATROL_R, 0.0,
		mp.z + sin(ang) * _GobCfg.MINE_GUARD_PATROL_R)
	sq["target"] = goal
	var prev_goal: Vector3 = sq.get("ordered_goal", Vector3.INF)
	if prev_goal.distance_to(goal) < 0.5:
		return {}
	return {"sq": sq, "goal": goal, "center": c}

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
		PHASE_HARASS: aim = Vector3.ZERO           # поле держится у центра
		PHASE_HUNT:
			aim = _assault_target() if hunt_target_override == Vector3.INF else hunt_target_override
		PHASE_DEFEND: aim = village
	# Недоразобранный план прошлого такта выбрасывается целиком: обстановка
	# пересчитана, и выдавать поверх неё вчерашние приказы хуже, чем не выдать
	_order_queue.clear()
	_order_at = 0
	var alarm: bool = mine_alarm_active()
	var mine_pos: Vector3 = (mine as Node3D).global_position if alarm else Vector3.ZERO
	# ── ОСОБЫЕ РОЛИ (спринт 17): гарнизон, охрана рудника, разведка, рейды ──
	var handled: Dictionary = {}
	var guard_idx := 0
	var field: Array = []
	for s0 in squads:
		var sq0: Dictionary = s0
		var sid0: int = int(sq0["id"])
		if String(sq0["role"]) == ROLE_HEAL or (sq0["members"] as Array).is_empty():
			continue
		if only_revenge:
			continue
		if garrison_sids.has(sid0):
			sq0["role"] = ROLE_GARRISON
			handled[sid0] = true
			# Гарнизон стоит толпой за околицей и бьёт то, что подошло
			var gspread: float = 6.0 * float(garrison_idx_of(sid0))
			var ggoal := Vector3(village.x + gspread, 0.0, village.z)
			var gfoe: Node3D = _nearest_foe(_squad_center(sq0), _GobCfg.CENTER_RADIUS)
			if gfoe != null:
				if not GameManager.squad_in_combat(sid0):
					_order_queue.append({"sq": sq0, "foe": gfoe})
			elif (sq0.get("ordered_goal", Vector3.INF) as Vector3).distance_to(ggoal) > 0.5 \
					or clock - float(sq0.get("ordered_at", -1.0e9)) >= REISSUE_KEEPALIVE_SEC:
				sq0["target"] = ggoal
				_order_queue.append({"sq": sq0, "goal": ggoal, "center": _squad_center(sq0)})
			continue
		if mine_guard_sids.has(sid0):
			handled[sid0] = true
			var gp: Dictionary = _mine_guard_plan(sq0, guard_idx)
			guard_idx += 1
			if not gp.is_empty():
				_order_queue.append(gp)
			continue
		if _revenge_sids.has(sid0):
			continue                       # ниже, общим путём
		if sid0 == scout_sid:
			continue                       # разведчик ведётся своим автоматом ниже
		# Резерв ведёт DormantReserve; в поле попадает только конница, взятая
		# на вылазку (она в raid_sids)
		if reserve_sids.has(sid0) and not raid_sids.has(sid0):
			continue
		field.append(sq0)
	# ── ТРЕВОГА РУДНИКА: вся орда к нему ─────────────────────────────────────
	if alarm and not only_revenge:
		for s1 in field:
			var sq1: Dictionary = s1
			var sid1: int = int(sq1["id"])
			if reserve_sids.has(sid1):
				continue
			handled[sid1] = true
			sq1["role"] = ROLE_MINE_ALARM
			raid_sids.erase(sid1)
			var c1: Vector3 = _squad_center(sq1)
			var foe1: Node3D = _nearest_foe(mine_pos, _GobCfg.CENTER_RADIUS)
			if foe1 == null:
				foe1 = _nearest_foe(c1, _GobCfg.CENTER_RADIUS)
			if foe1 != null:
				if not GameManager.squad_in_combat(sid1):
					_order_queue.append({"sq": sq1, "foe": foe1, "wake": true})
				continue
			var goal1 := Vector3(mine_pos.x + 6.0 * float(field.find(s1) - field.size() / 2), 0.0, mine_pos.z)
			sq1["target"] = goal1
			if (sq1.get("ordered_goal", Vector3.INF) as Vector3).distance_to(goal1) < 0.5 \
					and clock - float(sq1.get("ordered_at", -1.0e9)) < REISSUE_KEEPALIVE_SEC:
				continue
			_order_queue.append({"sq": sq1, "goal": goal1, "center": c1, "wake": true})
		last_action += "|ТРЕВОГА: орда идёт к руднику"
		field = []
	# ── МИРНАЯ ФАЗА: ПАТРУЛЬ ГРАНИЦ ДЕРЕВНИ (уточнение владельца) ───────────
	if not only_revenge and not alarm and phase == PHASE_PEACE:
		if _village_threatened():
			# Пришли бить — оборона деревни командиром, как в фазе обороны
			var dplans: Array = commander.plan_defense(field, village, clock)
			for s5 in field:
				(s5 as Dictionary)["role"] = ROLE_DEFEND
				handled[int((s5 as Dictionary)["id"])] = true
			for plan5 in dplans:
				_order_queue.append(plan5)
		else:
			var bi := 0
			for s5 in field:
				var sq5: Dictionary = s5
				handled[int(sq5["id"])] = true
				sq5["role"] = ROLE_BORDER
				var slot: int = int(floor(clock / _GobCfg.PATROL_BORDER_SEC)) + bi
				var ang: float = TAU * float(slot % _GobCfg.PATROL_BORDER_POINTS) / float(_GobCfg.PATROL_BORDER_POINTS)
				var r: float = _GobCfg.VILLAGE_RADIUS + _GobCfg.PATROL_BORDER_R
				var goal5 := Vector3(village.x + cos(ang) * r, 0.0, village.z + sin(ang) * r)
				bi += 1
				sq5["target"] = goal5
				var c5: Vector3 = _squad_center(sq5)
				var foe5: Node3D = _nearest_foe(c5, _GobCfg.CENTER_RADIUS)
				if foe5 != null:
					if not GameManager.squad_in_combat(int(sq5["id"])):
						_order_queue.append({"sq": sq5, "foe": foe5})
					continue
				if (sq5.get("ordered_goal", Vector3.INF) as Vector3).distance_to(goal5) < 0.5:
					continue
				_order_queue.append({"sq": sq5, "goal": goal5, "center": c5})
		field = []
	# ── РАЗВЕДКА, РЕЙДЫ, РЕЗЕРВ НА РУДНИКЕ ХОЛМА (фазы экспансии и рейдов) ───
	if not only_revenge and (phase == PHASE_HARASS or phase == PHASE_CENTER):
		var rest: Array = []
		# Резерв на руднике холма: EXPAND_MINE_SQUADS отрядов стоят на нём
		var hill: Node3D = _hill_mine()
		var hold_left: int = _GobCfg.EXPAND_MINE_SQUADS if hill != null else 0
		for s2 in field:
			var sq2: Dictionary = s2
			var sid2: int = int(sq2["id"])
			if phase == PHASE_HARASS and raid_sids.has(sid2):
				handled[sid2] = true
				var rp: Dictionary = _raid_plan(sq2)
				if not rp.is_empty():
					_order_queue.append(rp)
				continue
			if hold_left > 0 and (hill_mine_sid == sid2 or hill_mine_sid == 0) \
					and sid2 != scout_sid:
				hill_mine_sid = sid2
				hold_left -= 1
				handled[sid2] = true
				sq2["role"] = ROLE_MINE_HOLD
				var hp3: Vector3 = hill.global_position
				var hfoe: Node3D = _nearest_foe(hp3, _GobCfg.CENTER_RADIUS)
				if hfoe != null:
					if not GameManager.squad_in_combat(sid2):
						_order_queue.append({"sq": sq2, "foe": hfoe})
					continue
				sq2["target"] = hp3
				if (sq2.get("ordered_goal", Vector3.INF) as Vector3).distance_to(hp3) < 0.5 \
						and clock - float(sq2.get("ordered_at", -1.0e9)) < REISSUE_KEEPALIVE_SEC:
					continue
				_order_queue.append({"sq": sq2, "goal": hp3, "center": _squad_center(sq2)})
				continue
			rest.append(sq2)
		if hill == null:
			hill_mine_sid = 0
		if phase == PHASE_HARASS:
			var sp: Dictionary = _scout_plan(rest)
			if not sp.is_empty():
				var ssq: Dictionary = sp["sq"]
				handled[int(ssq["id"])] = true
				if sp.has("foe") or bool(sp.get("retreat", false)):
					_order_queue.append(sp)
				else:
					var prev_g: Vector3 = ssq.get("ordered_goal", Vector3.INF)
					if prev_g.distance_to(sp["goal"]) > 0.5 \
							or clock - float(ssq.get("ordered_at", -1.0e9)) >= REISSUE_KEEPALIVE_SEC:
						_order_queue.append(sp)
		field = rest
	# ── ШТУРМ БАЗЫ ВЕДЁТ КОМАНДИР (заказ 10.09.2026) ─────────────────────────
	# В фазе охоты полевые отряды (не месть, не лечащиеся) получают план от
	# GoblinAttackCommander: сбор на дистанции, паттерн, отход и лечение.
	# Режимов три (уточнение владельца): охота — штурм базы, центр — марш с
	# дозором, оборона деревни — рубеж у костров и фланговые уколы конницы.
	# Фаза рейдов держит поле у центра тем же маршем с дозором
	var tactical: Dictionary = {}
	if _GobCfg.ASSAULT_TACTICS and not only_revenge and not alarm \
			and (phase == PHASE_HUNT or phase == PHASE_CENTER or phase == PHASE_DEFEND \
			or phase == PHASE_HARASS):
		var role: String = ROLE_HUNT if phase == PHASE_HUNT else \
			(ROLE_CENTER if (phase == PHASE_CENTER or phase == PHASE_HARASS) else ROLE_DEFEND)
		for s4 in field:
			var sq4: Dictionary = s4
			sq4["role"] = role
			sq4["target"] = aim
			tactical[int(sq4["id"])] = true
		var plans: Array = []
		match phase:
			PHASE_HUNT:   plans = commander.plan(field, aim, village, clock)
			PHASE_DEFEND: plans = commander.plan_defense(field, village, clock)
			_:            plans = commander.plan_advance(field, aim, village, clock)
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
		if tactical.has(sid) or handled.has(sid):
			continue                       # приказы этого отряда уже в плане
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

## Порядковый номер гарнизонного отряда (для разноса по околице)
func garrison_idx_of(sid: int) -> int:
	var i := 0
	for k in garrison_sids:
		if int(k) == sid:
			return i
		i += 1
	return 0

## Исполнить одну запись плана (обход состава — дорогая часть).
## Возвращает число бойцов, которым выдан приказ, — им и меряется бюджет кадра
func _issue_squad(plan: Dictionary) -> int:
	var sq: Dictionary = plan["sq"]
	var members: Array = sq["members"]
	var issued := 0
	# Зонд BigStand: источник приказов — вожак орды (метку снимает физтик)
	if _OptGA.cmd_meter: _OptGA.cmd_src = "horde_ai"
	# Живость — на СЫРОЙ ссылке, до приведения типа (правило 5): цель могла
	# пасть, пока запись ждала своего кадра, а типизированное присваивание
	# освобождённого объекта не даёт null — оно бросает исключение
	# Ветка выбирается ПО КЛЮЧУ, а не по «цель не null»: павшая цель в
	# словаре сравнивается с null как равная, и запись атаки проваливалась
	# в ветку марша без «goal» (SCRIPT ERROR в зонде длинной партии, 34-я мин)
	if plan.has("foe"):
		var foe_raw: Variant = plan.get("foe")
		if foe_raw == null or not is_instance_valid(foe_raw):
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
	# Снимок — ПАРА [узлы, xz] (спринт 14): обход самой пары молча давал
	# ноль построек, и орда не выбирала здания целью вовсе
	for b in (GameManager.enemy_buildings_snapshot(Constants.FACTION_GOBLIN)[0] as Array):
		if b == null or not is_instance_valid(b):
			continue
		var bld := b as Building
		if bld == null or bld.is_dead() or not GameManager.goblin_may_raze(bld):
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
