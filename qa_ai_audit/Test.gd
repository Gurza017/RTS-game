extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_ai_audit — ФИКСЫ ИИ ПО АУДИТУ ПАРТИЙ И ТЕЛЕМЕТРИЯ (ТЗ 19.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A. резерв орды: конница, возвращённая с рейда под обстрелом, деревню не
##      будит; удар по спящему у деревни — будит; пол займа;
##   B. красный ИИ: ответный удар не по откату — отказ при малой армии, отказ
##      при перевесе противника у цели, удар у своей крепости без проверки;
##   C. орда: потолок беспокойства — HUNT после HARASS_MAX_SEC с ≥ MIN
##      отрядами, не раньше и не меньше;
##   D. телеметрия: goblin_squads ≥ 0, сброс накопителей на старте, урон
##      по сторонам и родам, способности, экономика, события.
## Запуск: godot --headless --path . res://qa_ai_audit/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_ai_audit: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x + float(i % cols) * 0.7, 0.0, at.z + float(i / cols) * 0.9))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _kill_all_but_goblins() -> void:
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction != Constants.FACTION_GOBLIN:
			(n as Unit).take_damage(1.0e12)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	main.enemy_ai.set_process(false)
	main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	var reserve = main.goblin_reserve
	var gai = main.goblin_ai
	var eai = main.enemy_ai

	print("\n═════ A. РЕЗЕРВ ОРДЫ: ЛОЖНАЯ ТРЕВОГА ═════")
	verdict("A0 резерв заведён и спит", reserve != null and (reserve.squads as Array).size() >= 10
		and int(reserve.asleep_count()) == (reserve.squads as Array).size(),
		"отрядов %d" % ((reserve.squads as Array).size() if reserve != null else -1))
	var lent_sids: Array = reserve.borrow_cavalry(1)
	verdict("A1 вожак занял один конный отряд (резерв выше пола %d)" % _GobCfg.RESERVE_LEND_FLOOR, lent_sids.size() == 1)
	var lsid: int = int(lent_sids[0]) if not lent_sids.is_empty() else 0
	# Рейд ушёл за сотню метров и попал под обстрел
	var far: Vector3 = reserve.village + Vector3(-120.0, 0.0, 0.0)
	if far.x < -200.0:
		far = reserve.village + Vector3(120.0, 0.0, 0.0)
	for m in reserve._members(lsid):
		(m as Unit).global_position = Vector3(far.x, GameManager.get_terrain_height(far.x, far.z), far.z)
		(m as Unit).sync_row()
	await pframes(2)
	var hitter: Unit = _spawn("archer", F, far + Vector3(0.0, 0.0, 30.0))
	hitter.set_tick(false)
	var victim: Unit = reserve._members(lsid)[0]
	victim.take_damage(3.0, hitter)
	var hit_seen: bool = GameManager.squad_hit_recently(lsid)
	reserve.return_squad(lsid)
	var threat_after_return: bool = reserve._threatened()
	verdict("A2 удар по отряду, только что возвращённому с рейда (100+ м от деревни), деревню НЕ будит",
		hit_seen and not reserve.lent.has(lsid) and not threat_after_return,
		"удар %s, lent %s, тревога %s" % [str(hit_seen), str(reserve.lent.has(lsid)), str(threat_after_return)])
	# А удар по спящему на посту — будит
	var home_sid := 0
	for s in reserve.squads:
		var sid: int = int(s["sid"])
		if sid != lsid and reserve._asleep.has(sid):
			home_sid = sid
			break
	var home_v: Unit = reserve._members(home_sid)[0]
	var hitter2: Unit = _spawn("archer", F, home_v.global_position + Vector3(0.0, 0.0, 25.0))
	hitter2.set_tick(false)
	home_v.take_damage(3.0, hitter2)
	verdict("A3 удар по спящему отряду у деревни — тревога", reserve._threatened())
	hitter.take_damage(1.0e12)
	hitter2.take_damage(1.0e12)
	await pframes(60 * 4)
	# Пол займа: ниже RESERVE_LEND_FLOOR отрядов конница не выдаётся
	var saved: Array = reserve.squads
	reserve.squads = saved.slice(0, _GobCfg.RESERVE_LEND_FLOOR)
	var none: Array = reserve.borrow_cavalry(1)
	reserve.squads = saved
	verdict("A4 при %d отрядах резерв конницу взаймы не даёт" % _GobCfg.RESERVE_LEND_FLOOR, none.is_empty())

	print("\n═════ B. КРАСНЫЙ ИИ: ОТВЕТНЫЙ УДАР ПО СИЛЕ ═════")
	eai._regroup()
	var home: Vector3 = eai._home_pos if eai._home_pos != Vector3.ZERO else main.ENEMY_BASE_ANCHOR
	if eai._home_pos == Vector3.ZERO:
		eai._home_pos = home
	var target: Vector3 = home + Vector3(60.0, 0.0, 0.0)
	var why0: String = eai._retaliation_refusal(target)
	verdict("B1 без полевой армии (охрана — не армия) удар отложен", why0 != "" and why0.begins_with("полевых"), why0)
	# Восемь полевых отрядов копейщиков красных — УСТАВНЫХ: записи ИИ
	# собираются по роду до полного штата, и неполные сливаются (ловушка
	# qa_ai_scenarios)
	var red: Array = []
	var full: int = _UCfg.squad_size("spearman")
	for i in range(_AICfg.RETALIATION_MIN_SQUADS):
		red.append(_squad("spearman", E, home + Vector3(-28.0 + float(i) * 7.0, 0.0, 20.0), full, 6))
	await pframes(4)
	eai._regroup()
	var why1: String = eai._retaliation_refusal(target)
	verdict("B2 армия набрана, у цели никого — удар идёт", why1 == "", why1)
	# Перевес противника у цели: больше бойцов игрока, чем красных в поле
	var wall: Array = []
	var need: int = int(ceil(float(full * _AICfg.RETALIATION_MIN_SQUADS) * _AICfg.RETALIATION_ADVANTAGE / 50.0)) + 2
	for i in range(need):
		wall.append(_squad("spearman", F, target + Vector3(-20.0 + float(i) * 4.0, 0.0, -6.0), 50, 5))
	for s in wall:
		for u in s[1]:
			(u as Unit).set_tick(false)
	await pframes(4)
	var why2: String = eai._retaliation_refusal(target)
	verdict("B3 у цели перевес противника — удар отложен", why2 != "" and why2.begins_with("в поле"), why2)
	verdict("B4 те же потери у своей крепости — удар без проверки силы",
		eai._retaliation_refusal(home + Vector3(10.0, 0.0, 0.0)) == "")
	# Полный путь: потери набраны, отказ не сбрасывает счёт
	GameManager.faction_losses[E] = int(GameManager.faction_losses.get(E, 0)) + _AICfg.RETALIATION_LOSSES + 5
	GameManager.last_loss_from[E] = target
	eai._peace_over = true
	eai._retal_mark = 0
	eai._retal_next_ok = 0.0
	eai.retaliation_until = -1.0
	var ref0: int = eai.retaliation_refusals
	eai._update_retaliation()
	verdict("B5 _update_retaliation при перевесе противника: отказ, счёт потерь цел, переспрос через RECHECK",
		eai.retaliation_refusals == ref0 + 1 and not eai.retaliation_active()
		and eai._retal_mark == 0 and eai._retal_next_ok > eai.clock,
		"отказов %d, активен %s" % [eai.retaliation_refusals, str(eai.retaliation_active())])
	for s in wall:
		for u in s[1]:
			(u as Unit).take_damage(1.0e12)
	await pframes(4)
	eai._retal_next_ok = 0.0
	eai._update_retaliation()
	verdict("B6 противник ушёл — тот же счёт потерь даёт удар", eai.retaliation_active())
	var ev_ret := false
	for e in GameManager.tm_events:
		if String(e[1]) == "red_retaliation":
			ev_ret = true
	verdict("B7 событие удара записано в телеметрию", ev_ret)
	eai.retaliation_until = -1.0
	for s in red:
		for u in s[1]:
			(u as Unit).take_damage(1.0e12)

	print("\n═════ C. ОРДА: ПОТОЛОК БЕСПОКОЙСТВА ═════")
	var saved_g: Array = gai.squads
	var field_recs: Array = []
	for s in saved_g:
		if not gai._is_special(int((s as Dictionary)["id"])):
			field_recs.append(s)
	verdict("C0 у стартовой орды полевых отрядов не меньше уставных %d" % _GobCfg.army_squads(),
		field_recs.size() >= _GobCfg.army_squads(), "полевых %d" % field_recs.size())
	gai.phase = gai.PHASE_HARASS
	gai.clock = _GobCfg.ASSAULT_EARLIEST_SEC + 10.0
	gai.squads = field_recs.slice(0, _GobCfg.ASSAULT_MIN_SQUADS + 1)
	gai._harass_since = gai.clock - _GobCfg.HARASS_MIN_SEC - 10.0
	verdict("C1 неполная армия, беспокойство меньше HARASS_MAX_SEC — наступления нет", not gai._assault_ready())
	gai._harass_since = gai.clock - _GobCfg.HARASS_MAX_SEC - 1.0
	verdict("C2 та же армия после HARASS_MAX_SEC — наступление тем, что есть", gai._assault_ready())
	gai.squads = field_recs.slice(0, _GobCfg.ASSAULT_MIN_SQUADS - 1)
	verdict("C3 меньше ASSAULT_MIN_SQUADS отрядов — наступления нет и после потолка", not gai._assault_ready())
	gai.clock = _GobCfg.ASSAULT_EARLIEST_SEC - 100.0
	gai.squads = field_recs
	gai._harass_since = 0.0
	verdict("C4 полная армия до часа X — наступления нет", not gai._assault_ready())
	gai.squads = saved_g
	var gate: Dictionary = gai.assault_gate()
	verdict("C5 ворота наступления читаются телеметрией", gate.has("wave") and gate.has("harass_sec") and gate.has("clock_ok"))
	gai.phase = gai.PHASE_PEACE
	gai.clock = 0.0

	print("\n═════ D. ТЕЛЕМЕТРИЯ ═════")
	var tm = main.telemetry
	verdict("D0 зонд партии на месте", tm != null)
	GameManager.nav_req_class["spearman"] = 777
	GameManager.tm_reset()
	verdict("D1 сброс накопителей: счётчики навигации и потерь пусты",
		GameManager.nav_req_class.is_empty() and GameManager.faction_losses.is_empty() and GameManager.tm_events.is_empty())
	var pl: Unit = _spawn("spearman", F, Vector3(-60.0, 0.0, -60.0))
	var en: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, Vector3(-60.0, 0.0, -58.0))
	pl.set_tick(false)
	en.set_tick(false)
	await pframes(2)
	var hp0: float = pl.current_health
	pl.take_damage(10.0, en)
	var dealt: float = hp0 - pl.current_health
	var d_in: float = float((GameManager.tm_damage_in.get(F, {}) as Dictionary).get("spearman", 0.0))
	var d_out: float = float((GameManager.tm_damage_out.get(Constants.FACTION_GOBLIN, {}) as Dictionary).get("goblin_spearman", 0.0))
	verdict("D2 урон учтён: принят копейщиком игрока и нанесён гоблином — сумма после брони",
		dealt > 0.0 and absf(d_in - dealt) < 0.01 and absf(d_out - dealt) < 0.01,
		"прошло %.2f, принято %.2f, нанесено %.2f" % [dealt, d_in, d_out])
	var w: Unit = _spawn("warrior", F, Vector3(-60.0, 0.0, -64.0))
	await pframes(2)
	(w as Warrior).start_rage_dash()
	verdict("D3 способность учтена (rage_dash игрока)", int(GameManager.tm_abilities.get("%d:rage_dash" % F, 0)) >= 1)
	ResourceManager.add_resource(F, Constants.RESOURCE_GOLD, 123.0)
	ResourceManager.spend(F, {Constants.RESOURCE_GOLD: 23.0})
	tm._sample()
	var eco: Dictionary = tm.last_sample.get("economy", {})
	var pe: Dictionary = eco.get(str(F), {})
	verdict("D4 экономика в образце: приток 123 и расход 23 золота у игрока",
		absf(float((pe.get("income", {}) as Dictionary).get(str(Constants.RESOURCE_GOLD), 0.0)) - 123.0) < 0.01
		and absf(float((pe.get("spent", {}) as Dictionary).get(str(Constants.RESOURCE_GOLD), 0.0)) - 23.0) < 0.01,
		str(pe))
	var ai: Dictionary = tm.last_sample.get("ai", {})
	verdict("D5 goblin_squads в образце ≥ 0 (не −1), фаза и ворота есть",
		int(ai.get("goblin_squads", -1)) >= 0 and ai.has("goblin_phase") and ai.has("goblin_gate"), str(ai))
	verdict("D6 урон и способности в образце разностью", (tm.last_sample.get("damage_in", {}) as Dictionary).has(str(F))
		and (tm.last_sample.get("abilities", {}) as Dictionary).has("%d:rage_dash" % F))
	# Событие смены фазы орды
	gai.phase = gai.PHASE_PEACE
	gai.clock = _GobCfg.PEACE_SEC + 10.0
	gai._decide_phase()
	gai.phase = gai.PHASE_PEACE
	gai.clock = 1e6
	var before_ev: int = GameManager.tm_events.size()
	gai.tick()
	var got := false
	for e in GameManager.tm_events:
		if String(e[1]) == "goblin_phase":
			got = true
	verdict("D7 смена фазы орды — событие с таймкодом", got, "событий %d → %d" % [before_ev, GameManager.tm_events.size()])
	gai.phase = gai.PHASE_PEACE
	gai.clock = 0.0
	_finish()
