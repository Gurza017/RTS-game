extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ВОЖАК ОРДЫ — ЭКОНОМИКА, ВОЛНЫ, ОХРАНА (ТЗ 11.10.2026, часть 2: снос и новая)
## ═══════════════════════════════════════════════════════════════════════════
## ЧТО СНЕСЕНО. Прежний вожак (2000 строк) и его спутники рождали бойцов из
## шести источников без общего потолка: стартовая орда в 11 отрядов, спящий
## резерв, набеги по часам (GoblinRaids, без конца), волны на каждый рудник
## игрока раз в 240 с, «месть» по 1000 копейщиков раз в 10 минут, бесплатная
## разведка и бесплатное доукомплектование в хижинах. Выжившие не
## распускались — к 40-й минуте партии владельца на карте было ~5800
## гоблинов. Охрана рудников патрулировала кольцо 9 м вокруг самого рудника,
## куда толпа не помещалась, — вызволение (unstuck) крутилось вечно (4000
## событий за первые 4 минуты), а переприказ «держать точку» раз в 8 с будил
## всех стоящих.
##
## ЧТО ТЕПЕРЬ. Один источник войск — ГЛАВНАЯ ХАТА лагеря:
##   1) ЭКОНОМИКА (_economy_tick): хижины и хата дают еду, бойцы волн её
##      едят (содержание), копилка с потолком; рост дохода со временем;
##   2) ПРОИЗВОДСТВО (_production_tick): план следующей волны по шаблону
##      (spawn_config.WAVE_PATTERN), отряды покупаются за еду по одному и
##      рождаются в СВОБОДНОМ слоте площадки сбора (шаг больше диаметра
##      толпы), сразу засыпают (F_DORMANT: ни тика, ни расталкивания);
##      потолки HORDE_CAP (вся фракция) и HORDE_FIELD_CAP (волны);
##   3) ВОЛНА (_launch / _wave_tick): набранная волна просыпается и уходит
##      по СЦЕНАРИЮ (разведка, рудник игрока / красного, база игрока /
##      красного, патруль и штурм брода) с ТАКТИКОЙ (в лоб, фланг, тыл,
##      ложный отход и повторный удар). Приказ отряду — ОДИН на этап, а не
##      раз в 8 с; переприказ только отряду, который стоит без дела или
##      застрял (25 с без продвижения, не больше трёх раз). Кончилась волна
##      — выжившие возвращаются на площадку сбора и засыпают, вливаясь в
##      следующую волну (покупать их заново не нужно);
##   4) ОХРАНА РУДНИКОВ (_guards_tick): стационарная, спит; будит удар по
##      руднику или чужой ближе GUARD_WAKE_R; отбилась — домой одним приказом
##      и снова спать;
##   5) ТРЕВОГА ЛАГЕРЯ (_camp_tick): чужой у хижин — будится площадка сбора.
## Последняя хижина снесена — производство встаёт навсегда (орда разбита).
##
## Все приказы идут ОЧЕРЕДЬЮ с бюджетом ORDER_BUDGET бойцов на кадр
## (_drain_orders): раздача пятисот приказов одним кадром давала пики 30-60 мс.
## Числа — scripts/spawn_config.gd (блок «НОВАЯ ОРДА»).

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Spawn  := preload("res://scripts/spawn_config.gd")
const _Diff   := preload("res://scripts/game_difficulty_config.gd")
const _OptGA  := preload("res://scripts/perf_config.gd")
const _UCfgA  := preload("res://scripts/unit_stats_config.gd")

const THINK_SEC := 1.0
## Бойцов, получающих приказ за кадр (очередь _drain_orders)
const ORDER_BUDGET := 40
## Отряд «застрял на марше»: центр сдвинулся меньше STUCK_M за STUCK_SEC
const STUCK_SEC := 25.0
const STUCK_M := 3.0
const STUCK_REISSUE_MAX := 3
## Отряд дошёл до своей точки этапа
const ARRIVE_M := 12.0
## Радиус поиска чужого отряда у цели волны
const ENGAGE_R := 45.0
## Поводок охраны: дальше от рудника — домой, даже если враг рядом
const GUARD_LEASH := 45.0

const PHASE_PEACE := "peace"
const PHASE_WAR := "war"
const PHASE_DEFEATED := "defeated"

const ROLE_GUARD := "mine_guard"
const ROLE_MUSTER := "muster"
const ROLE_WAVE := "wave"

var main: Node3D = null
var village: Vector3 = Vector3.ZERO
var chief: Node = null
var phase: String = PHASE_PEACE
var clock: float = 0.0
## Отражение для телеметрии и стендов: [{id, type, role}] — логика его не читает
var squads: Array = []

## sid → {mine, post, st ("sleep" / "fight" / "home"), calm, t}
var guards: Dictionary = {}
## Рудник → время последнего удара по нему (сигнал Mine.attacked)
var _mine_hit: Dictionary = {}
## Слот площадки сбора → sid; и обратно
var muster: Dictionary = {}
var _muster_slot: Dictionary = {}
## Отряды площадки, разбуженные тревогой лагеря
var _camp_awake: bool = false
var _camp_calm: float = 0.0
## План следующей волны: {tpl, comp: [род…], have: [sid…], t0}
var _plan: Dictionary = {}
var _pattern_i: int = 0
var _last_spawn: float = -1.0e9
## Волны в поле
var waves: Array = []
var _wave_seq: int = 0
## Очередь приказов
var _oq: Array = []
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()

## ── СЧЁТЧИКИ (стенды, телеметрия, зонд длинной партии) ─────────────────────
var waves_launched: int = 0
var waves_returned: int = 0
var squads_bought: int = 0
var food_spent: float = 0.0
var income_min: float = 0.0
var upkeep_min: float = 0.0
var field_units: int = 0
var orders_issued: int = 0
var stuck_reissues: int = 0
var guard_wakes: int = 0
var scenario_counts: Dictionary = {}
var tactic_counts: Dictionary = {}
var last_action: String = ""
## Совместимость с зондом qa_ai_loop/Smoke (поля прежнего вожака)
var raids_launched: int = 0
var raid_retreats: int = 0
var scout_sorties: int = 0
var scout_harasses: int = 0
var known_bases: Array = []
## ПЕРВЫЙ КОНТАКТ (горн орды, qa_audio18): орда увидела войска игрока или
## игрок открыл туман над лагерем, рудником или отрядом орды — один раз за
## партию. Горн трубит и на выходе каждой волны (horn_blows — стендам)
var first_contact: bool = false
var horn_blows: int = 0

# ═════════════════════════════════════════════════════════════════════════════
# ПОДКЛЮЧЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func setup(main_node: Node3D, center: Vector3, chief_hut: Node = null) -> void:
	main = main_node
	village = center
	chief = chief_hut
	# Свой генератор: общий сеяный поток партии не сдвигается (ловушка
	# «новый потребитель randi() сдвигает лотереи»), а партия с тем же зерном
	# выбирает те же сценарии
	var ws: Variant = main.get("world_seed") if main != null else null
	_rng.seed = int(ws) if ws != null else 1

## Прежний вожак держал гарнизон деревни и спящий резерв — их больше нет
func register_garrison(_sid: int) -> void:
	pass

func attach_reserve(_r: Node) -> void:
	pass

## Отряд охраны рудника: пост — где стоит сейчас (или заданная точка); сразу
## засыпает. Рудник по умолчанию — рудник лагеря
func register_mine_guard(sid: int, mine: Node = null, post: Vector3 = Vector3.INF) -> void:
	var m: Node = mine
	if m == null:
		m = GameManager.goblin_mine
	var p: Vector3 = post
	if p.x == INF:
		var c: Vector2 = GameManager.squad_centre_xz(sid)
		p = Vector3(c.x, 0.0, c.y) if c.x != INF else village
	guards[sid] = {"mine": m, "post": p, "st": "sleep", "calm": 0.0, "t": clock}
	if m != null and is_instance_valid(m):
		attach_mine(m)
	_sleep_squad(sid)

## Удар по руднику будит его охрану (сигнал Mine.attacked)
func attach_mine(m: Node) -> void:
	if m == null or not is_instance_valid(m) or not m.has_signal("attacked"):
		return
	var cb := Callable(self, "_on_mine_attacked").bind(m)
	if not m.is_connected("attacked", cb):
		m.connect("attacked", cb)

func _on_mine_attacked(_by_faction, _at, m: Node) -> void:
	_mine_hit[m] = clock

## Отряд на особой роли (охрана, площадка сбора): командир конницы его не
## берёт — спящих и стоящих на посту нельзя уводить в набег
func is_special_squad(sid: int) -> bool:
	if guards.has(sid) or _muster_slot.has(sid):
		return true
	# Отряды штурма по часам ведёт свой маршрут (GoblinFortressAssaultEvent)
	var ev = main.get("assault_event") if main != null else null
	return ev != null and is_instance_valid(ev) and bool(ev.call("owns", sid))

## Сводка для телеметрии (TelemetryLogger.goblin_gate)
func assault_gate() -> Dictionary:
	return {"food": int(ResourceManager.get_amount(Constants.FACTION_GOBLIN, Constants.RESOURCE_FOOD)),
		"income": snappedf(income_min, 0.1), "upkeep": snappedf(upkeep_min, 0.1),
		"plan": String(_plan.get("tpl", "")), "have": (_plan.get("have", []) as Array).size(),
		"need": (_plan.get("comp", []) as Array).size(), "ready": _ready_q.size(), "waves": waves.size(),
		"field": field_units, "guards": guards.size(), "launched": waves_launched}

# ═════════════════════════════════════════════════════════════════════════════
# ТАКТ
# ═════════════════════════════════════════════════════════════════════════════
## Шаг игровых часов (scripts/GameClockStep.gd, аудит 22.10.2026): часы и
## таймеры этого узла идут от Unit.game_ms(), а не от delta отрисовки —
## при просадке FPS мир замедляется, и сроки этого узла вместе с ним
var _gclk = preload("res://scripts/GameClockStep.gd").new()

func _process(delta: float) -> void:
	delta = _gclk.step()   # игровое время вместо delta отрисовки (GameClockStep)
	if main == null:
		return
	_drain_orders()
	_t += delta
	if _t < THINK_SEC:
		return
	var dt: float = _t
	_t = 0.0
	clock += dt
	_prune()
	if not _reserve_done:
		_spawn_start_reserve()
	_economy_tick(dt)
	_production_tick()
	_guards_tick(dt)
	_camp_tick(dt)
	_waves_tick(dt)
	_maybe_launch()
	_check_first_contact()
	_reflect()

## ── СТАРТОВЫЙ РЕЗЕРВ (spawn_config.START_RESERVE) ─────────────────────────
## Один раз, на первом такте вожака (лагерь и охрана уже стоят): по отряду в
## свободный слот площадки, разметка толпой, сразу сон — как купленный, но
## даром. Первые планы волн забирают их через «вернувшихся с прошлой волны»
var _reserve_done: bool = false
var reserve_spawned: int = 0
var _last_launch_clock: float = -1.0

func _spawn_start_reserve() -> void:
	_reserve_done = true
	if main == null or phase == PHASE_DEFEATED:
		return
	for t in _Spawn.START_RESERVE:
		var want: String = String(t)
		var n: int = int(_GobCfg.SQUAD_SIZE.get(want, 50))
		if field_units + n > _Spawn.field_cap(clock) or horde_alive() + n > _Spawn.horde_cap(clock):
			break
		var slot: int = _free_slot()
		if slot < 0:
			break
		var base: Vector3 = _slot_pos(slot)
		if main.has_method("_clear_trees"):
			main.call("_clear_trees", base, 9.0)
		var sid: int = int(main.call("spawn_goblin_squad", want, n, base, false))
		if sid <= 0:
			continue
		field_units += n
		muster[slot] = sid
		_muster_slot[sid] = slot
		_set_horde_formation(sid, base, n, Vector3.FORWARD)
		_sleep_squad(sid)
		reserve_spawned += 1
	last_action = "стартовый резерв: %d отрядов" % reserve_spawned

func _blow_horn(why: String) -> void:
	horn_blows += 1
	last_action = why
	if AudioManager.has_method("play_horn"):
		AudioManager.play_horn()

## Точки, по которым судится первый контакт: лагерь, рудник лагеря, центры
## отрядов охраны, площадки и волн. Свет тумана игрока над точкой или боец
## игрока в обзоре гоблина — горн, один раз за партию
func _check_first_contact() -> void:
	if first_contact:
		return
	var fog = GameManager.fog
	var lit_ok: bool = fog != null and is_instance_valid(fog) and bool(fog.enabled)
	var sight: float = _UCfgA.vision_radius(float(_UCfgA.STATS["goblin_spearman"]["attack_range"]))
	var pts: Array = [village]
	if GameManager.goblin_mine != null and is_instance_valid(GameManager.goblin_mine):
		pts.append((GameManager.goblin_mine as Node3D).global_position)
	for sid in guards:
		pts.append(_centre(int(sid)))
	for sid2 in _muster_slot:
		pts.append(_centre(int(sid2)))
	for w in waves:
		for sid3 in (w["sids"] as Array):
			pts.append(_centre(int(sid3)))
	for p in pts:
		var c: Vector3 = p
		if c.x == INF:
			continue
		if lit_ok and fog.is_lit(c.x, c.z):
			first_contact = true
			_blow_horn("первый контакт: орду увидели")
			return
		if GameManager.army.nearest_of_side(c.x, c.z, Constants.FACTION_PLAYER, sight) != null:
			first_contact = true
			_blow_horn("первый контакт: орда увидела игрока")
			return

func _peace_sec() -> float:
	if not GameManager.truce_enabled():
		return 0.0
	return _Diff.goblin_peace_sec()

## Живые бойцы отряда (состав читается напрямую: squad_members — не читатель)
func _alive(sid: int) -> Array:
	var out: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return out
	for m in (sq as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _alive_n(sid: int) -> int:
	var n := 0
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return 0
	for m in (sq as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n

func _centre(sid: int) -> Vector3:
	var c: Vector2 = GameManager.squad_centre_xz(sid)
	return Vector3(c.x, 0.0, c.y) if c.x != INF else Vector3.INF

func _type(sid: int) -> String:
	return GameManager.squad_type(sid)

## Выбитые отряды снимаются отовсюду
func _prune() -> void:
	for sid in guards.keys():
		if _alive_n(int(sid)) == 0:
			guards.erase(sid)
	for sid in _muster_slot.keys():
		if _alive_n(int(sid)) == 0:
			muster.erase(_muster_slot[sid])
			_muster_slot.erase(sid)
	for pl in ([_plan] + _ready_q):
		if (pl as Dictionary).is_empty():
			continue
		var keep: Array = []
		for sid in ((pl as Dictionary)["have"] as Array):
			if _alive_n(int(sid)) > 0:
				keep.append(sid)
		(pl as Dictionary)["have"] = keep

func _reflect() -> void:
	squads.clear()
	field_units = 0
	for sid in guards:
		squads.append({"id": int(sid), "type": _type(int(sid)), "role": ROLE_GUARD})
	for sid in _muster_slot:
		squads.append({"id": int(sid), "type": _type(int(sid)), "role": ROLE_MUSTER})
		field_units += _alive_n(int(sid))
	for w in waves:
		for sid in (w["sids"] as Array):
			if _muster_slot.has(sid):
				continue
			squads.append({"id": int(sid), "type": _type(int(sid)), "role": ROLE_WAVE})
			field_units += _alive_n(int(sid))

# ═════════════════════════════════════════════════════════════════════════════
# ЭКОНОМИКА ЕДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _huts_alive() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_GOBLIN)):
		if b == null or not is_instance_valid(b) or not (b is Building) or (b as Building).is_dead():
			continue
		var bid: String = String((b as Building).building_id)
		if bid == "goblin_hut" or bid == "goblin_chief_hut":
			out.append(b)
	return out

func chief_alive() -> bool:
	if chief == null or not is_instance_valid(chief):
		# Загрузка партии сносит и ставит постройки заново: хата — та, что
		# стоит в лагере сейчас (поиск только при потере ссылки)
		chief = null
		for b in get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_GOBLIN)):
			if is_instance_valid(b) and b is Building and String((b as Building).building_id) == "goblin_chief_hut":
				chief = b
				break
	return chief != null and is_instance_valid(chief) and not (chief as Building).is_dead()

## Спячка одного бойца (прежний помощник вожака; стенд тумана qa_fog D7 зовёт
## его напрямую): тело — Unit.set_dormant, визуальный тик не гасится
func _set_dormant(u: Unit, on: bool) -> void:
	if u != null and is_instance_valid(u):
		u.set_dormant(on)

## ── ПОСЛЕ ЗАГРУЗКИ ПАРТИИ (SaveLoadManager.apply) ─────────────────────────
## Отряды орды восстанавливаются из слепка заново и с новыми номерами, а
## вожак о них не знает: отряд у рудника (ближе GUARD_LEASH) становится его
## охраной (пост — где стоит), прочие — площадкой сбора (идут в слот и спят).
## Гноллы, тролли и туши пней — дикие, их не трогаем
func adopt_after_load() -> void:
	# Резерв уже лежит в сохранённых отрядах — второй раз его не рожать
	_reserve_done = true
	guards.clear()
	muster.clear()
	_muster_slot.clear()
	_homing.clear()
	waves.clear()
	_ready_q.clear()
	_plan = {}
	var mines: Array = []
	for grp in ["neutral_buildings", "enemy_buildings", "goblin_buildings", "player_buildings"]:
		for b in get_tree().get_nodes_in_group(grp):
			if b is Mine and is_instance_valid(b) and not mines.has(b):
				mines.append(b)
	for sid in GameManager.squads.keys():
		var sq: Dictionary = GameManager.squads[sid]
		if int(sq.get("faction", -1)) != Constants.FACTION_GOBLIN:
			continue
		var t: String = String(sq.get("type", ""))
		if t != "goblin_spearman" and t != "goblin_rider" and t != "big_goblin":
			continue
		if _alive_n(int(sid)) == 0:
			continue
		var c: Vector3 = _centre(int(sid))
		var near: Node = null
		var bd: float = GUARD_LEASH
		for m in mines:
			var d: float = Vector2(c.x - (m as Node3D).global_position.x, c.z - (m as Node3D).global_position.z).length()
			if d < bd:
				bd = d
				near = m
		if near != null:
			register_mine_guard(int(sid), near, c)
		else:
			_to_muster(int(sid))


func _economy_tick(dt: float) -> void:
	if phase == PHASE_DEFEATED:
		return
	var huts: Array = _huts_alive()
	if huts.is_empty():
		_defeat()
		return
	var small := 0
	for h in huts:
		if String((h as Building).building_id) == "goblin_hut":
			small += 1
	var ramp: float = minf(1.0 + _Spawn.FOOD_RAMP_PER_HOUR * clock / 3600.0, _Spawn.FOOD_RAMP_MAX)
	var diff_k: float = _Diff.goblin_hut_food_per_min() / maxf(_GobCfg.HUT_FOOD_PER_MIN, 0.001)
	income_min = (float(small) * _Spawn.HUT_FOOD_MIN \
		+ (_Spawn.CHIEF_FOOD_MIN if chief_alive() else 0.0)) * ramp * diff_k
	# Поздняя орда (ТЗ 23.10.2026, второе письмо, п. 4): после 30-й минуты
	# доход × LATE_FOOD_MULT — больше покупок, крупнее волны
	if _Spawn.late_surge(clock):
		income_min *= _Spawn.LATE_FOOD_MULT
	upkeep_min = float(field_units) * _Spawn.FOOD_UPKEEP_PER_UNIT_MIN
	var f: float = ResourceManager.get_amount(Constants.FACTION_GOBLIN, Constants.RESOURCE_FOOD)
	f = clampf(f + (income_min - upkeep_min) / 60.0 * dt, 0.0, _Spawn.FOOD_BANK_MAX)
	ResourceManager.set_amount(Constants.FACTION_GOBLIN, Constants.RESOURCE_FOOD, f)

## ПОСЛЕДНЯЯ ХИЖИНА СНЕСЕНА — орда разбита: производство встаёт навсегда.
## Живые отряды доживают своё (охрана спит, волны дерутся)
func _defeat() -> void:
	phase = PHASE_DEFEATED
	_plan = {}
	_ready_q.clear()
	last_action = "лагерь уничтожен — производство остановлено"
	var hud = main.get("hud") if main != null else null
	if hud != null and is_instance_valid(hud) and hud.has_method("show_placement_hint"):
		hud.show_placement_hint("Лагерь орды уничтожен — новых волн не будет")

# ═════════════════════════════════════════════════════════════════════════════
# ПРОИЗВОДСТВО: ПЛАН ВОЛНЫ → ПОКУПКА ПО ОТРЯДУ → СЛОТ ПЛОЩАДКИ СБОРА
# ═════════════════════════════════════════════════════════════════════════════
func horde_alive() -> int:
	if main != null and main.has_method("horde_alive"):
		return int(main.call("horde_alive"))
	return 0

func _new_plan() -> void:
	var pat: Array = _Spawn.WAVE_PATTERN
	var tpl: String = String(pat[_pattern_i % pat.size()])
	_pattern_i += 1
	_plan = {"tpl": tpl, "comp": (_Spawn.WAVE_TEMPLATES[tpl] as Array).duplicate(), "have": [], "t0": clock}

## Какого рода не хватает плану (первый неукомплектованный)
func _plan_missing() -> String:
	var need: Dictionary = {}
	for t in (_plan["comp"] as Array):
		need[String(t)] = int(need.get(String(t), 0)) + 1
	for sid in (_plan["have"] as Array):
		var t2: String = _type(int(sid))
		need[t2] = int(need.get(t2, 0)) - 1
	for t3 in (_plan["comp"] as Array):
		if int(need.get(String(t3), 0)) > 0:
			return String(t3)
	return ""

func _in_ready(sid: int) -> bool:
	for rp in _ready_q:
		if ((rp as Dictionary)["have"] as Array).has(sid):
			return true
	return false

func _free_slot() -> int:
	for i in range((_Spawn.MUSTER_SLOTS as Array).size()):
		if not muster.has(i):
			return i
	return -1

func _slot_pos(i: int) -> Vector3:
	var o: Vector2 = _Spawn.MUSTER_SLOTS[i]
	return GameManager.land_target(Vector3(village.x + o.x, 0.0, village.z + o.y))

func _production_tick() -> void:
	if phase == PHASE_DEFEATED:
		return
	if _plan.is_empty():
		_new_plan()
	var want: String = _plan_missing()
	if want == "":
		return
	# Сначала — вернувшиеся с прошлой волны (стоят на площадке, уже оплачены)
	for sid in _muster_slot.keys():
		if (_plan["have"] as Array).has(sid) or _type(int(sid)) != want or _in_ready(int(sid)):
			continue
		(_plan["have"] as Array).append(sid)
		return
	if clock - _last_spawn < _Spawn.SQUAD_SPAWN_GAP_SEC:
		return
	var price: float = float((_Spawn.SQUAD_PRICE as Dictionary).get(want, 300.0))
	if ResourceManager.get_amount(Constants.FACTION_GOBLIN, Constants.RESOURCE_FOOD) < price:
		return
	var n: int = int(_GobCfg.SQUAD_SIZE.get(want, 50))
	if field_units + n > _Spawn.field_cap(clock) or horde_alive() + n > _Spawn.horde_cap(clock):
		last_action = "потолок орды: %s ждёт" % want
		return
	var slot: int = _free_slot()
	if slot < 0:
		return
	var base: Vector3 = _slot_pos(slot)
	var sid: int = int(main.call("spawn_goblin_squad", want, n, base, true))
	if sid <= 0:
		return
	ResourceManager.set_amount(Constants.FACTION_GOBLIN, Constants.RESOURCE_FOOD,
		ResourceManager.get_amount(Constants.FACTION_GOBLIN, Constants.RESOURCE_FOOD) - price)
	food_spent += price
	squads_bought += 1
	_last_spawn = clock
	field_units += n
	muster[slot] = sid
	_muster_slot[sid] = slot
	(_plan["have"] as Array).append(sid)
	# Разметка — толпа на слоте: смыкание собирает отряд там же, где он стоит
	_set_horde_formation(sid, base, n, Vector3.FORWARD)
	# Спать сразу: опоздавшие (растяжка спавна) перенимают спячку у старшего
	_sleep_squad(sid)
	last_action = "куплен %s (слот %d)" % [want, slot]

# ═════════════════════════════════════════════════════════════════════════════
# ВЫПУСК ВОЛНЫ: СЦЕНАРИЙ, ЦЕЛЬ, ТАКТИКА
# ═════════════════════════════════════════════════════════════════════════════
## ── ГОТОВЫЕ ВОЛНЫ ЖДУТ ВЫХОДА ОЧЕРЕДЬЮ ────────────────────────────────────
## Набранная волна, которой выходить рано (перемирие) или некуда (в поле уже
## WAVES_MAX_ACTIVE), встаёт в очередь _ready_q, а производство берётся за
## следующий план — иначе копилка упиралась в потолок, пока волна ждала
var _ready_q: Array = []

func _maybe_launch() -> void:
	if phase == PHASE_DEFEATED:
		return
	# Укомплектованный план — в очередь готовых, если на площадке есть место
	# под следующий (иначе он остаётся планом и просто ждёт)
	if not _plan.is_empty() and _plan_missing() == "" and _ready_q.size() < 3 \
			and _free_slots_n() >= 2:
		_ready_q.append(_plan)
		_plan = {}
	if clock < _peace_sec():
		return
	phase = PHASE_WAR
	if waves.size() >= _Spawn.WAVES_MAX_ACTIVE:
		return
	# ── ТЕМП: ВОЛНА КАЖДЫЕ 7-10 МИНУТ (ТЗ 12.10.2026, второе письмо) ──────
	# Не чаще WAVE_GAP_MIN_SEC; дольше WAVE_GAP_MAX_SEC без выхода — план
	# уходит тем, что набрано (ветка «не набрал состав» ниже)
	var since: float = clock - _last_launch_clock if _last_launch_clock >= 0.0 else 1.0e9
	# После 30-й минуты паузы × LATE_GAP_MULT (ТЗ 23.10.2026, второе письмо)
	var gap_k: float = _Spawn.LATE_GAP_MULT if _Spawn.late_surge(clock) else 1.0
	if since < _Spawn.WAVE_GAP_MIN_SEC * gap_k:
		return
	var overdue: bool = since >= _Spawn.WAVE_GAP_MAX_SEC * gap_k and _last_launch_clock >= 0.0
	if not _ready_q.is_empty():
		# ── ОДИН ВЫХОД — ВСЁ НАБРАННОЕ (ТЗ 12.10.2026, второе письмо) ───────
		# Волны выходят раз в 7-10 минут, а не парами по готовности: за паузу
		# набирается два-три плана, и уходят они ОДНОЙ ощутимой волной, а не
		# цепочкой мелких набегов (зонд GobProbe: 12 волн по 2-3 отряда за 40
		# минут — «волны почти исчезли»). Состав плана в работе тоже идёт,
		# если он полон
		var rp: Dictionary = _ready_q.pop_front()
		var merged: Array = (rp["have"] as Array).duplicate()
		var tpl0: String = String(rp["tpl"])
		while not _ready_q.is_empty():
			var more: Dictionary = _ready_q.pop_front()
			merged.append_array(more["have"])
			tpl0 = String(more["tpl"]) if tpl0 == "scout" else tpl0
		if not _plan.is_empty() and _plan_missing() == "":
			merged.append_array(_plan["have"])
			_plan = {}
		_launch(tpl0, merged)
		return
	if _plan.is_empty():
		return
	var have: Array = _plan["have"]
	if have.is_empty():
		return
	var full: bool = _plan_missing() == ""
	if not full and not overdue and clock - float(_plan["t0"]) < _Spawn.WAVE_ASSEMBLE_MAX_SEC:
		return
	_launch(String(_plan["tpl"]), have.duplicate())
	_plan = {}

func _free_slots_n() -> int:
	return (_Spawn.MUSTER_SLOTS as Array).size() - muster.size()

func _launch(tpl: String, sids: Array) -> void:
	var live: Array = []
	for s in sids:
		if _alive_n(int(s)) > 0:
			live.append(int(s))
	if live.is_empty():
		return
	for sid in live:
		if _muster_slot.has(sid):
			muster.erase(_muster_slot[sid])
			_muster_slot.erase(sid)
		_homing.erase(sid)
		_wake_squad(sid)
	var sc: Dictionary = _pick_scenario(tpl, live)
	if sc.is_empty():
		# Целей нет вовсе — отряды обратно на площадку
		for sid2 in live:
			_to_muster(sid2)
		return
	_wave_seq += 1
	var has_cav := false
	for sid3 in live:
		if _type(sid3) == "goblin_rider":
			has_cav = true
	var tactic: String = "raid" if String(sc["name"]) == "scout" else _pick_tactic(has_cav)
	var w := {"id": _wave_seq, "tpl": tpl, "sids": live, "name": sc["name"],
		"pos": sc["pos"], "node": sc.get("node"), "tactic": tactic, "stage": "march",
		"t0": clock, "st_t": clock, "men0": 0, "feint_done": false, "calm": 0.0,
		"pts": {}, "roles": {}, "track": {}}
	var men0 := 0
	for sid4 in live:
		men0 += _alive_n(sid4)
	w["men0"] = men0
	waves.append(w)
	waves_launched += 1
	_last_launch_clock = clock
	raids_launched += 1
	if String(sc["name"]) == "scout":
		scout_sorties += 1
	scenario_counts[sc["name"]] = int(scenario_counts.get(sc["name"], 0)) + 1
	tactic_counts[tactic] = int(tactic_counts.get(tactic, 0)) + 1
	last_action = "волна %d (%s): %s, тактика %s, отрядов %d" % [_wave_seq, tpl, sc["name"], tactic, live.size()]
	_assign_points(w)
	for sid5 in live:
		_order_move(sid5, (w["pts"] as Dictionary)[sid5]["stage"], false)
		(w["track"] as Dictionary)[sid5] = {"c": _centre(sid5), "t": clock, "n": 0}
	_blow_horn("волна %d вышла" % _wave_seq)

## Сценарий волны: {name, pos, node}. Разведка — к базе игрока (ловить
## рабочих и одиночек); прочие — взвешенный жребий по обстановке
func _pick_scenario(tpl: String, sids: Array) -> Dictionary:
	var player_base: Node3D = _base_of(Constants.FACTION_PLAYER)
	var red_base: Node3D = _base_of(Constants.FACTION_ENEMY)
	if tpl == "scout":
		var tgt: Node3D = player_base if player_base != null else red_base
		if tgt == null:
			return {}
		return {"name": "scout", "pos": tgt.global_position, "node": null}
	var cand: Array = []
	if main != null and main.has_method("ford_point"):
		var fp: Vector3 = main.call("ford_point")
		var foes: int = _foes_count(fp, 35.0)
		if foes >= _Spawn.FORD_TAKEN_FOES:
			cand.append({"name": "ford_assault", "pos": fp, "node": null, "w": 4.0})
		else:
			cand.append({"name": "ford_patrol", "pos": fp, "node": null, "w": 1.0})
	var pm: Node3D = _mine_of(Constants.FACTION_PLAYER)
	if pm != null:
		cand.append({"name": "player_mine", "pos": pm.global_position, "node": pm, "w": 2.5})
	var rm: Node3D = _mine_of(Constants.FACTION_ENEMY)
	if rm != null:
		cand.append({"name": "red_mine", "pos": rm.global_position, "node": rm, "w": 1.5})
	if player_base != null:
		cand.append({"name": "player_base", "pos": player_base.global_position, "node": player_base,
			"w": 1.5 + (1.0 if clock > 1500.0 else 0.0)})
	if red_base != null:
		cand.append({"name": "red_base", "pos": red_base.global_position, "node": red_base, "w": 1.0})
	if cand.is_empty():
		return {}
	var total := 0.0
	for c in cand:
		total += float(c["w"])
	var r: float = _rng.randf() * total
	for c2 in cand:
		r -= float(c2["w"])
		if r <= 0.0:
			return c2
	return cand[cand.size() - 1]

func _pick_tactic(has_cav: bool) -> String:
	var opts: Array = [["front", 0.3], ["flank", 0.3], ["rear", 0.2], ["feint", 0.2]] if has_cav \
		else [["front", 0.5], ["feint", 0.3], ["flank", 0.2]]
	var r: float = _rng.randf()
	for o in opts:
		r -= float(o[1])
		if r <= 0.0:
			return String(o[0])
	return "front"

## Точки этапов каждому отряду: развёртывание за WAVE_STAGE_DIST до цели,
## отряды рядом поперёк подхода с шагом больше диаметра толпы; фланг/тыл —
## у конницы (или у последнего отряда пехоты, если конницы нет)
func _assign_points(w: Dictionary) -> void:
	var sids: Array = w["sids"]
	var t: Vector3 = w["pos"]
	var c := Vector3.ZERO
	var k := 0
	for sid in sids:
		var cc: Vector3 = _centre(int(sid))
		if cc.x != INF:
			c += cc
			k += 1
	c = c / float(maxi(k, 1)) if k > 0 else village
	var dir: Vector3 = t - c
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	w["dir"] = dir
	var tactic: String = w["tactic"]
	var flankers: Array = []
	if tactic == "flank" or tactic == "rear":
		for sid2 in sids:
			if _type(int(sid2)) == "goblin_rider":
				flankers.append(int(sid2))
		if flankers.is_empty() and sids.size() >= 2:
			flankers.append(int(sids[sids.size() - 1]))
	var front: Array = []
	for sid3 in sids:
		if not flankers.has(int(sid3)):
			front.append(int(sid3))
	var stage_c: Vector3 = t - dir * _Spawn.WAVE_STAGE_DIST
	var pts: Dictionary = {}
	var roles: Dictionary = {}
	for i in range(front.size()):
		var off: float = (float(i) - float(front.size() - 1) * 0.5) * 17.0
		var sp: Vector3 = GameManager.land_target(stage_c + side * off)
		pts[front[i]] = {"stage": sp, "strike": t + side * off * 0.5}
		roles[front[i]] = "front"
	var sgn: float = 1.0 if _rng.randf() < 0.5 else -1.0
	for j in range(flankers.size()):
		var fp: Vector3
		if tactic == "rear":
			fp = t + dir * _Spawn.WAVE_FLANK_DIST + side * (float(j) - float(flankers.size() - 1) * 0.5) * 17.0
		else:
			fp = t + side * sgn * (_Spawn.WAVE_FLANK_DIST + float(j) * 17.0) - dir * 6.0
		var lim: Vector2 = GameManager.clamp_to_map(fp.x, fp.z)
		var fpp: Vector3 = GameManager.land_target(Vector3(lim.x, 0.0, lim.y))
		pts[flankers[j]] = {"stage": GameManager.land_target(stage_c + side * sgn * 26.0), "flank": fpp, "strike": t}
		roles[flankers[j]] = "flank"
	w["pts"] = pts
	w["roles"] = roles

# ═════════════════════════════════════════════════════════════════════════════
# ВОЛНА В ПОЛЕ
# ═════════════════════════════════════════════════════════════════════════════
func _waves_tick(dt: float) -> void:
	var done: Array = []
	for w in waves:
		var live: Array = []
		for sid in (w["sids"] as Array):
			if _alive_n(int(sid)) > 0:
				live.append(int(sid))
		w["sids"] = live
		if live.is_empty():
			done.append(w)
			continue
		if clock - float(w["t0"]) > _Spawn.WAVE_MAX_SEC and String(w["stage"]) != "home":
			_wave_home(w)
			continue
		match String(w["stage"]):
			"march":
				_wave_march(w)
			"flank":
				_wave_flank(w)
			"engage":
				_wave_engage(w, dt)
			"feint":
				if clock - float(w["st_t"]) >= _Spawn.WAVE_FEINT_REGROUP_SEC:
					w["feint_done"] = true
					_set_stage(w, "engage")
					for sid2 in live:
						_engage_squad(int(sid2), w)
			"home":
				if _wave_home_tick(w):
					done.append(w)
	for w2 in done:
		waves.erase(w2)

func _set_stage(w: Dictionary, st: String) -> void:
	w["stage"] = st
	w["st_t"] = clock

## Марш к точкам развёртывания: дошли 3/4 отрядов или вышел срок —
## развёртывание. Застрявшему (центр не сдвинулся) — тот же приказ ещё раз,
## не чаще STUCK_SEC и не больше STUCK_REISSUE_MAX раз
func _wave_march(w: Dictionary) -> void:
	var live: Array = w["sids"]
	var pts: Dictionary = w["pts"]
	var arrived := 0
	var far := 0.0
	for sid in live:
		var c: Vector3 = _centre(sid)
		if c.x == INF or not pts.has(sid):
			continue
		var sp: Vector3 = pts[sid]["stage"]
		var d: float = Vector2(c.x - sp.x, c.z - sp.z).length()
		far = maxf(far, d)
		if d < ARRIVE_M:
			arrived += 1
		else:
			_stuck_check(w, sid, c, sp)
	var timeout: float = 60.0 + float(w.get("dist0", 0.0))
	if not w.has("dist0"):
		w["dist0"] = far / 2.0
	if float(arrived) >= ceilf(float(live.size()) * 0.75) or clock - float(w["st_t"]) > timeout \
			or _foes_count(_wave_centre(w), 18.0) > 0:
		_deploy(w)

func _stuck_check(w: Dictionary, sid: int, c: Vector3, goal: Vector3) -> void:
	var tr: Dictionary = (w["track"] as Dictionary).get(sid, {"c": c, "t": clock, "n": 0})
	var pc: Vector3 = tr["c"]
	if pc.x == INF or Vector2(c.x - pc.x, c.z - pc.z).length() > STUCK_M:
		tr["c"] = c
		tr["t"] = clock
	elif clock - float(tr["t"]) > STUCK_SEC and int(tr["n"]) < STUCK_REISSUE_MAX:
		tr["n"] = int(tr["n"]) + 1
		tr["t"] = clock
		stuck_reissues += 1
		_order_move(sid, goal, false)
	(w["track"] as Dictionary)[sid] = tr

func _wave_centre(w: Dictionary) -> Vector3:
	var acc := Vector3.ZERO
	var k := 0
	for sid in (w["sids"] as Array):
		var c: Vector3 = _centre(int(sid))
		if c.x != INF:
			acc += c
			k += 1
	return acc / float(k) if k > 0 else village

## Развёртывание: фронт бьёт сразу, фланг/тыл сначала заходит на свою точку
func _deploy(w: Dictionary) -> void:
	var roles: Dictionary = w["roles"]
	var pts: Dictionary = w["pts"]
	var any_flank := false
	for sid in (w["sids"] as Array):
		if String(roles.get(sid, "front")) == "flank" and pts.has(sid) and (pts[sid] as Dictionary).has("flank"):
			any_flank = true
			_order_move(int(sid), pts[sid]["flank"], true)
	if String(w["name"]) == "ford_patrol" or String(w["name"]) == "ford_assault":
		w["hold_t"] = clock
	if any_flank:
		_set_stage(w, "flank")
		for sid2 in (w["sids"] as Array):
			if String(roles.get(sid2, "front")) == "front":
				_engage_squad(int(sid2), w)
		return
	_set_stage(w, "engage")
	w["engage_t"] = clock
	for sid3 in (w["sids"] as Array):
		_engage_squad(int(sid3), w)

## Фланг/тыл: дошёл до точки захода (или 25 с) — удар
func _wave_flank(w: Dictionary) -> void:
	var roles: Dictionary = w["roles"]
	var pts: Dictionary = w["pts"]
	var ready := true
	for sid in (w["sids"] as Array):
		if String(roles.get(sid, "front")) != "flank" or not pts.has(sid):
			continue
		var c: Vector3 = _centre(int(sid))
		var fp: Vector3 = pts[sid].get("flank", c)
		if c.x != INF and Vector2(c.x - fp.x, c.z - fp.z).length() > ARRIVE_M:
			ready = false
	if ready or clock - float(w["st_t"]) > 25.0:
		_set_stage(w, "engage")
		w["engage_t"] = clock
		for sid2 in (w["sids"] as Array):
			if String(roles.get(sid2, "front")) == "flank":
				_engage_squad(int(sid2), w)

## Бой: переприказ ТОЛЬКО отряду, который стоит без дела; ложный отход по
## тактике; цель выполнена или чисто — дальше по сценарию
func _wave_engage(w: Dictionary, dt: float) -> void:
	var live: Array = w["sids"]
	var nm: String = w["name"]
	# Ложный отход: один раз за волну
	if String(w["tactic"]) == "feint" and not bool(w["feint_done"]):
		var men := 0
		for sid in live:
			men += _alive_n(sid)
		var lost: float = 1.0 - float(men) / float(maxi(int(w["men0"]), 1))
		if clock - float(w.get("engage_t", w["st_t"])) > _Spawn.WAVE_FEINT_SEC or lost >= _Spawn.WAVE_FEINT_LOSS:
			var back: Vector3 = -(w.get("dir", Vector3.FORWARD) as Vector3)
			for sid2 in live:
				var c: Vector3 = _centre(sid2)
				if c.x == INF:
					continue
				_order_move(sid2, GameManager.land_target(c + back * _Spawn.WAVE_FEINT_BACK), false, true)
			_set_stage(w, "feint")
			return
	var idle := 0
	for sid3 in live:
		if _squad_idle(sid3):
			idle += 1
			_engage_squad(sid3, w)
	# Цель и окрестности чисты?
	var foes: int = _foes_count(w["pos"], ENGAGE_R)
	var node = w.get("node")
	var node_ok: bool = node != null and is_instance_valid(node) and not (node as Building).is_dead() \
		and _hostile_building(node)
	if foes == 0 and not node_ok:
		w["calm"] = float(w["calm"]) + dt
	else:
		w["calm"] = 0.0
	if nm == "ford_patrol" or nm == "ford_assault":
		# Брод держим срок, потом домой (брод снова чей-то — следующая волна туда)
		if clock - float(w.get("hold_t", w["st_t"])) > _Spawn.WAVE_FORD_HOLD_SEC and foes == 0:
			_wave_home(w)
		return
	if float(w["calm"]) < 12.0:
		return
	# Штурм базы: следующая постройка той же стороны рядом — продолжаем
	if nm == "player_base" or nm == "red_base":
		var fac: int = Constants.FACTION_PLAYER if nm == "player_base" else Constants.FACTION_ENEMY
		var nb: Node3D = _nearest_building_of(fac, w["pos"], 60.0)
		if nb != null:
			w["node"] = nb
			w["pos"] = nb.global_position
			w["calm"] = 0.0
			for sid4 in live:
				_engage_squad(sid4, w)
			return
	_wave_home(w)

func _squad_idle(sid: int) -> bool:
	for m in _alive(sid):
		var u := m as Unit
		if u.state != Unit.State.IDLE:
			return false
	return true

## Приказ отряду волны по цели: чужой отряд у цели (раскладка фронта), иначе
## постройка-цель, иначе — встать на цель
func _engage_squad(sid: int, w: Dictionary) -> void:
	var c: Vector3 = _centre(sid)
	if c.x == INF:
		return
	var t: Vector3 = w["pos"]
	var probe: Vector3 = c if c.distance_to(t) < ENGAGE_R else t
	var pairs: Dictionary = GameManager.front_pairs([sid], probe, ENGAGE_R, Constants.FACTION_GOBLIN)
	if pairs.has(sid):
		_order_attack_squad(sid, int(pairs[sid]))
		return
	var node = w.get("node")
	if node != null and is_instance_valid(node) and not (node as Building).is_dead() and _hostile_building(node):
		_order_attack_node(sid, node)
		return
	var pts: Dictionary = w["pts"]
	var goal: Vector3 = pts[sid].get("strike", t) if pts.has(sid) else t
	if c.distance_to(goal) > ARRIVE_M:
		_order_move(sid, goal, false)

func _hostile_building(b) -> bool:
	if not (b is Building):
		return false
	var bb := b as Building
	if bb.faction == Constants.FACTION_GOBLIN or bb.faction == Constants.FACTION_NEUTRAL:
		return false
	return GameManager.goblin_may_raze(bb)

## Волна домой: на площадку сбора (свободные слоты; нет — к хате), там спать
func _wave_home(w: Dictionary) -> void:
	_set_stage(w, "home")
	waves_returned += 1
	raid_retreats += 1
	for sid in (w["sids"] as Array):
		_to_muster(int(sid))

func _wave_home_tick(w: Dictionary) -> bool:
	# Все отряды волны уже числятся на площадке — волна закрыта
	for sid in (w["sids"] as Array):
		if not _muster_slot.has(int(sid)):
			return false
	return true

## Отряд — на площадку сбора: слот, приказ одним разом, по приходу спать
## (_muster_home_tick). Свободного слота нет — к хате, и спать там же
var _homing: Dictionary = {}    # sid → время приказа

func _to_muster(sid: int) -> void:
	var slot: int = _free_slot()
	var goal: Vector3
	if slot >= 0:
		muster[slot] = sid
		_muster_slot[sid] = slot
		goal = _slot_pos(slot)
	else:
		_muster_slot[sid] = -1
		goal = GameManager.land_target(village + Vector3(_rng.randf_range(-20.0, 20.0), 0.0, 30.0))
	_wake_squad(sid)
	_order_move(sid, goal, false, true)
	_homing[sid] = {"t": clock, "goal": goal}

# ═════════════════════════════════════════════════════════════════════════════
# ОХРАНА РУДНИКОВ — СПИТ, ПОКА НЕ ТРОНУЛИ
# ═════════════════════════════════════════════════════════════════════════════
func _guards_tick(dt: float) -> void:
	# Дошедшие домой (площадка сбора) засыпают здесь же, в одном такте
	for sid in _homing.keys():
		var h: Dictionary = _homing[sid]
		var c: Vector3 = _centre(int(sid))
		var goal: Vector3 = h["goal"]
		if c.x == INF or Vector2(c.x - goal.x, c.z - goal.z).length() < _Spawn.GUARD_HOME_R \
				or clock - float(h["t"]) > 60.0:
			_homing.erase(sid)
			if not _camp_awake:
				_sleep_squad(int(sid))
	# По руднику — одна проверка на такт, а не по отряду
	var by_mine: Dictionary = {}
	for sid in guards:
		var g: Dictionary = guards[sid]
		var m = g["mine"]
		if m == null or not is_instance_valid(m):
			continue
		if not by_mine.has(m):
			by_mine[m] = []
		(by_mine[m] as Array).append(int(sid))
	var now_ms: int = Unit.game_ms()
	for m2 in by_mine:
		var mp: Vector3 = (m2 as Node3D).global_position
		var foe: Node3D = _nearest_foe(mp, _Spawn.GUARD_WAKE_R)
		var hit: bool = clock - float(_mine_hit.get(m2, -1.0e9)) < 6.0
		var threat: bool = foe != null or hit
		# ── УДАР ПО ЛЮБОМУ ОТРЯДУ ОХРАНЫ — ТРЕВОГА ВСЕЙ ОХРАНЫ РУДНИКА ─────
		# (ТЗ 22.10.2026). Прежде тревогу поднимали только чужой у самого
		# рудника и удар по руднику: лучников с 20+ м от поста и копейщиков у
		# крайнего поста кольца (дальше GUARD_WAKE_R от центра) охрана не
		# замечала и стояла под ударами. Обидчик — цель (last_hit_by)
		var striker: Node3D = null
		for sid_h in (by_mine[m2] as Array):
			var sqh: Variant = GameManager.squads.get(int(sid_h))
			if sqh == null:
				continue
			if now_ms - int((sqh as Dictionary).get("last_hit_ms", -1000000)) < 6000:
				threat = true
				var hb: Variant = (sqh as Dictionary).get("last_hit_by")
				if hb != null and is_instance_valid(hb) and hb is Unit and not (hb as Unit).is_dead():
					striker = hb
			# Чужой у самого отряда (не только у рудника) — тоже тревога
			if foe == null:
				var cg: Vector3 = _centre(int(sid_h))
				if cg.x != INF:
					var fg: Node3D = _nearest_foe(cg, _Spawn.GUARD_WAKE_R)
					if fg != null:
						foe = fg
						threat = true
		if foe == null and striker != null:
			foe = striker
		for sid2 in (by_mine[m2] as Array):
			var g2: Dictionary = guards[sid2]
			var st: String = g2["st"]
			var c2: Vector3 = _centre(sid2)
			var leash: bool = c2.x != INF and Vector2(c2.x - mp.x, c2.z - mp.z).length() > GUARD_LEASH
			if threat and not leash:
				g2["calm"] = 0.0
				if st != "fight":
					guard_wakes += 1
					_wake_squad(sid2)
					g2["st"] = "fight"
				if _squad_idle(sid2):
					var probe: Vector3 = foe.global_position if foe != null else mp
					var pairs: Dictionary = GameManager.front_pairs([sid2], probe, _Spawn.GUARD_WAKE_R + 15.0, Constants.FACTION_GOBLIN)
					if pairs.has(sid2):
						_order_attack_squad(sid2, int(pairs[sid2]))
					elif foe != null and (foe as Unit).squad_id > 0:
						# Стрелок дальше скана — бьём его отряд напрямую
						_order_attack_squad(sid2, (foe as Unit).squad_id)
					elif foe != null:
						_order_attack_node(sid2, foe)
				continue
			if st == "fight":
				g2["calm"] = float(g2["calm"]) + dt
				if float(g2["calm"]) >= _Spawn.GUARD_CALM_SEC or leash:
					g2["st"] = "home"
					g2["t"] = clock
					_order_move(sid2, g2["post"], false, true)
			elif st == "home":
				var post: Vector3 = g2["post"]
				if c2.x == INF or Vector2(c2.x - post.x, c2.z - post.z).length() < _Spawn.GUARD_HOME_R \
						or clock - float(g2["t"]) > _Spawn.GUARD_HOME_TIMEOUT_SEC:
					g2["st"] = "sleep"
					_sleep_squad(sid2)

# ═════════════════════════════════════════════════════════════════════════════
# ТРЕВОГА ЛАГЕРЯ
# ═════════════════════════════════════════════════════════════════════════════
func _camp_tick(dt: float) -> void:
	var p: Vector3 = (chief as Node3D).global_position if chief_alive() else village
	var foe: Node3D = _nearest_foe(p, _Spawn.CAMP_ALARM_R)
	if foe != null:
		_camp_calm = 0.0
		if not _camp_awake:
			_camp_awake = true
			last_action = "тревога лагеря"
		for sid in _muster_slot.keys():
			_homing.erase(sid)
			_wake_squad(int(sid))
			if _squad_idle(int(sid)):
				var pairs: Dictionary = GameManager.front_pairs([int(sid)], foe.global_position, 40.0, Constants.FACTION_GOBLIN)
				if pairs.has(int(sid)):
					_order_attack_squad(int(sid), int(pairs[int(sid)]))
		return
	if not _camp_awake:
		return
	_camp_calm += dt
	if _camp_calm < _Spawn.GUARD_CALM_SEC:
		return
	_camp_awake = false
	for sid2 in _muster_slot.keys():
		var slot: int = int(_muster_slot[sid2])
		var goal: Vector3 = _slot_pos(slot) if slot >= 0 else village + Vector3(0.0, 0.0, 30.0)
		_order_move(int(sid2), goal, false, true)
		_homing[sid2] = {"t": clock, "goal": goal}

# ═════════════════════════════════════════════════════════════════════════════
# ЦЕЛИ
# ═════════════════════════════════════════════════════════════════════════════
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

## Чужих бойцов (люди обеих сторон) в радиусе — зовётся на выпуске волны и
## раз в такт на волну, не покадрово
func _foes_count(p: Vector3, r: float) -> int:
	var n := 0
	for e in GameManager.unit_grid.query_radius(p, r):
		var u := e as Unit
		if u == null or u.is_dead() or u.garrisoned:
			continue
		if u.faction == Constants.FACTION_PLAYER or u.faction == Constants.FACTION_ENEMY:
			n += 1
	return n

## Главная постройка стороны: крепость, иначе любая постройка (кроме рудников)
func _base_of(fac: int) -> Node3D:
	var any: Node3D = null
	for b in get_tree().get_nodes_in_group(Constants.building_group(fac)):
		if b == null or not is_instance_valid(b) or not (b is Building) or (b as Building).is_dead():
			continue
		if b is Mine:
			continue
		if b.has_method("is_stronghold") and bool(b.call("is_stronghold")):
			if GameManager.goblin_may_raze(b):
				return b
			continue
		if any == null and GameManager.goblin_may_raze(b):
			any = b
	return any

func _mine_of(fac: int) -> Node3D:
	for b in get_tree().get_nodes_in_group(Constants.building_group(fac)):
		if b is Mine and is_instance_valid(b) and not (b as Building).is_dead():
			return b
	return null

func _nearest_building_of(fac: int, from: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var bd: float = r * r
	for b in get_tree().get_nodes_in_group(Constants.building_group(fac)):
		if b == null or not is_instance_valid(b) or not (b is Building) or (b as Building).is_dead():
			continue
		if not GameManager.goblin_may_raze(b):
			continue
		var d: float = from.distance_squared_to((b as Node3D).global_position)
		if d < bd:
			bd = d
			best = b
	return best

# ═════════════════════════════════════════════════════════════════════════════
# СОН И ПРИКАЗЫ
# ═════════════════════════════════════════════════════════════════════════════
func _sleep_squad(sid: int) -> void:
	for m in _alive(sid):
		var u := m as Unit
		if u.retreating:
			u.end_retreat(true)
		u.set_attack_target(null)
		if not u.dormant:
			u.set_dormant(true)

func _wake_squad(sid: int) -> void:
	for m in _alive(sid):
		var u := m as Unit
		if u.dormant:
			u.set_dormant(false)

## Разметка отряда — толпа вокруг точки (goblin_config.horde_offset)
func _set_horde_formation(sid: int, goal: Vector3, n: int, course: Vector3) -> Array:
	var slots: Array = []
	# ШАГ ТОЛПЫ ПО ТЕЛУ (ТЗ 12.10.2026): туша вдвое с лишним крупнее гоблина,
	# а места ей раздавались шагом гоблина — пять туш шли комом и толкались.
	# Тот же множитель, что у разметки GameManager (_block_slot_step)
	var hk: float = 1.0
	var sq: Variant = GameManager.squads.get(sid)
	if sq != null:
		hk = maxf(1.0, GameManager._block_slot_step((sq as Dictionary)["members"]) / _GobCfg.HORDE_SPOT)
	for k in range(n):
		var ho: Vector2 = _GobCfg.horde_offset(k, n, sid) * hk
		slots.append(Vector3(goal.x + ho.x, 0.0, goal.z + ho.y))
	GameManager.squad_set_formation(sid, slots, course, false)
	return slots

func _order_move(sid: int, goal: Vector3, run: bool, retreat: bool = false) -> void:
	_drop_orders(sid)
	_oq.append({"k": "move", "sid": sid, "goal": goal, "run": run, "retreat": retreat, "i": 0})

func _order_attack_squad(sid: int, foe_sid: int) -> void:
	var sink: Array = []
	GameManager.squad_attack_squad(sid, foe_sid, true, sink)
	if sink.is_empty():
		return
	_drop_orders(sid)
	_oq.append({"k": "pairs", "sid": sid, "pairs": sink, "i": 0})

func _order_attack_node(sid: int, node: Node3D) -> void:
	_drop_orders(sid)
	_oq.append({"k": "node", "sid": sid, "node": node, "i": 0})

## Новый приказ отряду заменяет недоданный старый
func _drop_orders(sid: int) -> void:
	for i in range(_oq.size() - 1, -1, -1):
		if int((_oq[i] as Dictionary)["sid"]) == sid:
			_oq.remove_at(i)

func _drain_orders() -> void:
	if _oq.is_empty():
		return
	if _OptGA.cmd_meter: _OptGA.cmd_src = "horde_ai"
	var budget: int = ORDER_BUDGET
	while budget > 0 and not _oq.is_empty():
		var o: Dictionary = _oq[0]
		var used: int = _issue(o, budget)
		budget -= maxi(used, 1)
		if bool(o.get("_done", false)):
			_oq.pop_front()

func _issue(o: Dictionary, budget: int) -> int:
	var sid: int = int(o["sid"])
	var k: String = o["k"]
	var used := 0
	if k == "pairs":
		var pairs: Array = o["pairs"]
		var i: int = int(o["i"])
		while i + 1 < pairs.size() and used < budget:
			var u_raw = pairs[i]
			var t_raw = pairs[i + 1]
			i += 2
			if not is_instance_valid(u_raw) or not is_instance_valid(t_raw):
				continue
			var u := u_raw as Unit
			if u.is_dead() or (t_raw as Unit).is_dead():
				continue
			if u.dormant:
				u.set_dormant(false)
			if u.retreating:
				u.end_retreat(true)
			u.command_attack(t_raw as Node3D, true, true)
			used += 1
		o["i"] = i
		o["_done"] = i + 1 >= pairs.size()
		orders_issued += used
		return used
	var men: Array = o.get("_men", [])
	if int(o["i"]) == 0:
		men = _alive(sid)
		o["_men"] = men
		if k == "move":
			var goal: Vector3 = o["goal"]
			var c: Vector3 = _centre(sid)
			var course: Vector3 = (goal - c).normalized() if c.x != INF and goal.distance_to(c) > 0.1 else Vector3.FORWARD
			course.y = 0.0
			o["_slots"] = _set_horde_formation(sid, goal, men.size(), course)
	var node_raw = o.get("node")
	if k == "node" and not is_instance_valid(node_raw):
		o["_done"] = true
		return 0
	var j: int = int(o["i"])
	while j < men.size() and used < budget:
		var m = men[j]
		j += 1
		if not is_instance_valid(m) or (m as Unit).is_dead():
			continue
		var u2 := m as Unit
		if u2.dormant:
			u2.set_dormant(false)
		if k == "move":
			var slots: Array = o["_slots"]
			var p: Vector3 = GameManager.land_target(slots[mini(j - 1, slots.size() - 1)])
			if bool(o["retreat"]):
				u2.begin_retreat()
				u2.command_move(p, false, Vector3.ZERO, true)
			else:
				if u2.retreating:
					u2.end_retreat(true)
				u2.command_move(p, false, Vector3.ZERO, false, false, bool(o["run"]))
		else:
			if u2.retreating:
				u2.end_retreat(true)
			u2.command_attack(node_raw as Node3D, true, false)
		used += 1
	o["i"] = j
	o["_done"] = j >= men.size()
	orders_issued += used
	return used
