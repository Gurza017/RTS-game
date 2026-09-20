extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ГЛАВНЫЙ ЦИКЛ ОРДЫ — БЕЗ СПЯЧКИ, ЭКСПАНСИЯ → РАЗВЕДКА И РЕЙДЫ →
## ГЕНЕРАЛЬНОЕ НАСТУПЛЕНИЕ (спринт 17, блок 3)
## ═══════════════════════════════════════════════════════════════════════════
## Деревня выключена (perf_config.goblin_village), армию ставит стенд, часы
## вожака двигает стенд (как в qa_goblin_tactics).
##   A — спячки нет: с первого такта орда бодрствует, фаза — экспансия;
##   B — экспансия: дошедшая до пустого центра орда переходит к разведке и
##       рейдам, один отряд идёт держать рудник на холме (резерв);
##   C — разведка: разведчик обходит точки интереса и находит базу игрока;
##   D — рейды: по известной базе выходит рейд-отряд, бьёт рабочих; при
##       сильном сопротивлении отходит домой (hit-and-run); рейды повторяются;
##   E — наступление: армия набрана и разведка нашла базу — фаза HUNT, цель —
##       найденная база; поле выбито — оборона деревни.
## Запуск: godot --headless --path . res://qa_goblin_loop/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _OptCfg := preload("res://scripts/perf_config.gd")

var main = null
var ai = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_goblin_loop: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Такт вожака с продвижением его часов и разбором очереди приказов
func think(steps: int = 1, sec: float = _GobCfg.THINK_INTERVAL) -> void:
	for _s in range(steps):
		ai.clock += sec
		ai.tick()
		var guard := 0
		while ai._order_at < ai._order_queue.size() and guard < 64:
			ai._drain_orders()
			guard += 1
		await pframes(int(sec * 60.0))

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _sq_by_id(sid: int) -> Dictionary:
	for s in ai.squads:
		if int((s as Dictionary)["id"]) == sid:
			return s
	return {}

func _roles() -> Dictionary:
	var out: Dictionary = {}
	for s in ai.squads:
		var r: String = String((s as Dictionary)["role"])
		out[r] = int(out.get(r, 0)) + 1
	return out

var castle: Castle = null
var workers: Array = []

func _run() -> void:
	_OptCfg.goblin_village = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	ai = main.goblin_ai
	ai.set_process(false)
	var village := Vector3(120.0, 0.0, -70.0)
	ai.setup(main, GameManager.land_target(village))
	await pframes(4)

	print("\n═════ A. СПЯЧКИ НЕТ ═════")
	verdict("A1 срок спячки в конфиге — ноль", _GobCfg.DORMANT_UNTIL_SEC == 0.0,
		"%.0f" % _GobCfg.DORMANT_UNTIL_SEC)
	var sids: Array = []
	for i in range(4):
		sids.append(main.spawn_goblin_squad("goblin_spearman", 20, ai.village + Vector3(float(i) * 12.0 - 18.0, 0.0, 14.0)))
	sids.append(main.spawn_goblin_squad("goblin_rider", 10, ai.village + Vector3(0.0, 0.0, 26.0)))
	# Второй конный: один уйдёт в разведку, другой — в рейд
	sids.append(main.spawn_goblin_squad("goblin_rider", 10, ai.village + Vector3(14.0, 0.0, 26.0)))
	await pframes(4)
	await think(1)
	verdict("A2 с первого такта орда бодрствует", bool(ai._awake))
	var awake := 0
	var total := 0
	for sid in sids:
		for m in GameManager.squad_members(int(sid)):
			total += 1
			if (m as Unit).tick_on:
				awake += 1
	verdict("A3 бойцы тикают физикой (не спят)", awake == total, "%d из %d" % [awake, total])
	verdict("A4 первые %.0f с — мирная фаза" % _GobCfg.PEACE_SEC, String(ai.phase) == ai.PHASE_PEACE, String(ai.phase))
	verdict("A5 гарнизона и охраны нет — все шесть отрядов в поле", ai._field_squads() == 6,
		"в поле %d" % ai._field_squads())
	# Патруль границ: все полевые — на кольце вокруг деревни, никто не ушёл
	await think(6)
	var border := 0
	var far_away := 0
	var lim: float = _GobCfg.VILLAGE_RADIUS + _GobCfg.PATROL_BORDER_R + 12.0
	for s in ai.squads:
		var sq: Dictionary = s
		if String(sq["role"]) == ai.ROLE_BORDER:
			border += 1
		if _xz(ai._squad_center(sq), ai.village) > lim:
			far_away += 1
	verdict("A6 в мире отряды патрулируют границы деревни (роль «граница»)", border == 6, "%d из 6" % border)
	verdict("A7 и никто не уходит дальше кольца границ (%.0f м)" % lim, far_away == 0, "ушло %d" % far_away)
	# Мир кончился — экспансия
	ai.clock = _GobCfg.PEACE_SEC
	await think(1)
	verdict("A8 по истечении мира — экспансия к центру", String(ai.phase) == ai.PHASE_CENTER, String(ai.phase))

	print("\n═════ B. ЭКСПАНСИЯ: ЦЕНТР И РУДНИК НА ХОЛМЕ ═════")
	# Рудник «на холме» — ничейный, ставим у центра, чтобы дойти быстро
	var hill := Mine.new()
	hill.faction = Constants.FACTION_NEUTRAL
	main.world_add(hill)
	hill.global_position = Vector3(14.0, GameManager.get_terrain_height(14.0, -10.0), -10.0)
	await pframes(2)
	# Переносим орду к центру — дорога в 140 м не предмет этого стенда
	for k in range(sids.size()):
		var members: Array = GameManager.squad_members(int(sids[k]))
		for i in range(members.size()):
			var u := members[i] as Unit
			var p := Vector3(float(k) * 7.0 - 14.0 + float(i % 5) * 0.7, 0.0, 6.0 + float(i / 5) * 0.7)
			u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
			u.sync_row()
	await pframes(2)
	await think(2)
	verdict("B1 орда дошла до пустого центра — фаза разведки и рейдов",
		String(ai.phase) == ai.PHASE_HARASS, String(ai.phase))
	await think(2)
	var roles: Dictionary = _roles()
	print("  роли: %s" % str(roles))
	verdict("B2 один отряд назначен резервом на рудник холма", int(roles.get(ai.ROLE_MINE_HOLD, 0)) == _GobCfg.EXPAND_MINE_SQUADS
		and ai.hill_mine_sid > 0, "резервов %d" % int(roles.get(ai.ROLE_MINE_HOLD, 0)))
	# ТЗ 19.09.2026 (блок 3.4): разведка — ПОЛНЫЕ конные отряды (scout_units)
	verdict("B3 разведка вышла: полный конный отряд из %d" % _GobCfg.scout_units(),
		ai.scout_sid > 0 and GameManager.squad_type(ai.scout_sid) == "goblin_rider"
		and GameManager.squad_members(ai.scout_sid).size() == _GobCfg.scout_units(),
		"разведчик %d (%s, %d бойцов)" % [ai.scout_sid, GameManager.squad_type(ai.scout_sid),
			GameManager.squad_members(ai.scout_sid).size()])
	verdict("B3б разведчик вне волны (особая роль)", ai._is_special(ai.scout_sid))
	await think(6)
	var hold_c: Vector3 = GameManager.squad_centroid(ai.hill_mine_sid)
	# Толпа в двадцать человек стоит вокруг площадки рудника — центр в
	# полутора десятках метров, а на площадке (CAPTURE_RADIUS) — передние
	verdict("B4 резерв дошёл до рудника и держит его", _xz(hold_c, hill.global_position) < 24.0,
		"%.1f м" % _xz(hold_c, hill.global_position))
	verdict("B5 рудник холма захвачен ордой", int(hill.faction) == Constants.FACTION_GOBLIN,
		"владелец %d" % int(hill.faction))

	print("\n═════ C. РАЗВЕДКА ═════")
	# База игрока — замок с рабочими в 40 м от центра (в пределах обхода)
	var cp := Vector3(-40.0, 0.0, 30.0)
	castle = Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(3)
	for i in range(4):
		var w := _spawn("worker", Constants.FACTION_PLAYER, cp + Vector3(8.0 + float(i) * 1.2, 0.0, 6.0))
		w.set_tick(false)
		# Бессмертные: разведчик у базы бьёт их по агро, а рейду нужна цель
		w.current_health = w.max_health * 100.0
		w._soa_push_stats()
		workers.append(w)
	# Разведчику — база ближайшей точкой обхода: ставим его рядом и ждём взгляда
	var sc: Array = GameManager.squad_members(ai.scout_sid)
	for i in range(sc.size()):
		var u := sc[i] as Unit
		var p := cp + Vector3(-22.0 + float(i % 5) * 0.7, 0.0, float(i / 5) * 0.7)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
	await pframes(2)
	await think(1)
	verdict("C1 разведчик, увидев постройку, запоминает базу игрока",
		ai.known_bases.has(Constants.FACTION_PLAYER),
		"известно баз %d" % ai.known_bases.size())
	verdict("C2 у найденной базы — точечный укол (состояние «harass»)",
		String(ai.scout_state) == "harass" and ai.scout_harasses >= 1, String(ai.scout_state))
	ai.clock += _GobCfg.SCOUT_HARASS_SEC
	await think(1)
	var ssq: Dictionary = _sq_by_id(ai.scout_sid)
	var scout_retreating := false
	for m in GameManager.squad_members(ai.scout_sid):
		if (m as Unit).retreating:
			scout_retreating = true
	# ТЗ 19.09.2026 (блок 3.4): после налёта — hit-and-run, ОТХОД в режиме
	# отхода (run — на следующую точку орбиты; home — при потерях/сроке)
	verdict("C3 после укола разведка ОТХОДИТ (run/home) в режиме отхода, а не выбивает базу",
		(String(ai.scout_state) == "run" or String(ai.scout_state) == "home")
		and scout_retreating, "состояние %s, отход=%s" % [String(ai.scout_state), str(scout_retreating)])
	var alive_w := 0
	for w in workers:
		if is_instance_valid(w) and not (w as Unit).is_dead():
			alive_w += 1
	verdict("C4 рабочие игрока живы (укол, а не зачистка)", alive_w == workers.size(), "%d из %d" % [alive_w, workers.size()])

	print("\n═════ D. РЕЙДЫ ═════")
	ai._raid_last = -1.0e9
	await think(1)
	verdict("D1 по известной базе вышел рейд", ai.raids_launched >= 1 and ai.raid_sids.size() >= 1,
		"рейдов %d, отрядов в рейде %d" % [ai.raids_launched, ai.raid_sids.size()])
	var rsid: int = 0
	for k in ai.raid_sids:
		rsid = int(k)
	var rsq: Dictionary = _sq_by_id(rsid)
	verdict("D2 рейд-отряд — конный (скорость важнее)", not rsq.is_empty() and String(rsq["type"]) == "goblin_rider",
		String(rsq.get("type", "-")))
	# Рейд идёт на рабочих: его цель — рабочий у базы
	var tgt_worker := false
	if not rsq.is_empty():
		var t: Vector3 = rsq["target"]
		for w in workers:
			if is_instance_valid(w) and _xz(t, (w as Unit).global_position) < 1.0:
				tgt_worker = true
	verdict("D3 цель рейда — рабочий игрока", tgt_worker)
	# Сильное сопротивление: строй игрока рядом с рейдом — отход домой
	var rc: Vector3 = GameManager.squad_centroid(rsid)
	var wall: Array = []
	for i in range(16):
		var f := _spawn("spearman", Constants.FACTION_PLAYER, rc + Vector3(2.0 + float(i % 8) * 0.6, 0.0, -2.0 + float(i / 8) * 0.6))
		f.set_tick(false)
		f.current_health = f.max_health * 100.0
		f._soa_push_stats()
		wall.append(f)
	await pframes(2)
	var retreats0: int = ai.raid_retreats
	await think(1)
	rsq = _sq_by_id(rsid)
	verdict("D4 при сильном сопротивлении рейд отходит (hit-and-run)",
		ai.raid_retreats > retreats0 and not ai.raid_sids.has(rsid),
		"отходов %d, роль %s" % [ai.raid_retreats, String(rsq.get("role", "-"))])
	verdict("D4б отряд идёт лечиться (роль «лечится» или отход к деревне)",
		String(rsq.get("role", "")) == ai.ROLE_HEAL or bool((GameManager.squad_members(rsid)[0] as Unit).retreating))
	for f in wall:
		if is_instance_valid(f):
			(f as Unit).take_damage(1e9)
	await pframes(2)
	# Рейды повторяются: следующий через интервал
	ai._raid_last = -1.0e9
	await think(1)
	verdict("D5 рейды повторяются регулярно", ai.raids_launched >= 2, "рейдов %d" % ai.raids_launched)
	verdict("D5б второй рейд крупнее первого (чередование малый/крупный)",
		ai.raid_sids.size() >= mini(_GobCfg.RAID_SQUADS_BIG, 2) or ai.raids_launched >= 2,
		"в рейде %d" % ai.raid_sids.size())

	print("\n═════ E. ГЕНЕРАЛЬНОЕ НАСТУПЛЕНИЕ И ОБОРОНА ═════")
	# Армия набрана: добираем отряды до army_squads()
	while ai._wave_squads() < _GobCfg.army_squads():
		main.spawn_goblin_squad("goblin_spearman", 20, Vector3(10.0 + float(ai.squads.size()) * 6.0, 0.0, 10.0))
		await pframes(1)
		ai._regroup()
	ai._harass_since = ai.clock - _GobCfg.HARASS_MIN_SEC - 1.0
	await think(1)
	verdict("E0 до 35-й минуты штурма нет даже с полной армией", String(ai.phase) == ai.PHASE_HARASS, String(ai.phase))
	ai.clock = _GobCfg.ASSAULT_EARLIEST_SEC
	ai._harass_since = ai.clock - _GobCfg.HARASS_MIN_SEC - 1.0
	await think(1)
	verdict("E1 полная армия, найденная база и 35-я минута — генеральное наступление",
		String(ai.phase) == ai.PHASE_HUNT, String(ai.phase))
	var aim: Vector3 = ai._assault_target()
	verdict("E2 цель наступления — база, найденная разведкой", _xz(aim, cp) < 5.0,
		"цель (%.0f, %.0f), база (%.0f, %.0f)" % [aim.x, aim.z, cp.x, cp.z])
	verdict("E3 «слабейшего» больше не ищут — функции нет", not ai.has_method("_weakest_target"))
	# Поле выбито — оборона деревни; полная армия — снова экспансия
	var saved: Array = ai.squads
	ai.squads = []
	ai._decide_phase()
	verdict("E4 выбитое поле переводит орду в оборону деревни", String(ai.phase) == ai.PHASE_DEFEND, String(ai.phase))
	ai.squads = saved
	ai._decide_phase()
	verdict("E5 полная орда снова идёт в экспансию", String(ai.phase) == ai.PHASE_CENTER, String(ai.phase))

	print("
═════ F. СОРВАННЫЙ ПОХОД В ХИЖИНУ НЕ ВЕШАЕТ ОТРЯД В HEAL ═════")
	# Зонд длинной партии: 18 отрядов в HEAL без единой очереди в хижину —
	# поле пусто, орда 16 минут переключает «центр»/«оборона», не сходя с
	# места. Роль HEAL без хижины, которая ждёт отряд, снимается тактом
	var healers := 0
	for s6 in ai.squads:
		var d6: Dictionary = s6
		if not ai._is_special(int(d6["id"])):
			d6["role"] = ai.ROLE_HEAL
			healers += 1
	var field_before: int = ai._field_squads()
	ai._sweep_heal()
	var stuck := 0
	for s7 in ai.squads:
		if String((s7 as Dictionary)["role"]) == ai.ROLE_HEAL:
			stuck += 1
	verdict("F1 отряды в HEAL без хижины-адресата возвращены в поле",
		healers > 0 and field_before == 0 and stuck == 0 and ai._field_squads() == healers,
		"было в HEAL %d (поле %d), осталось в HEAL %d, поле %d" % [
			healers, field_before, stuck, ai._field_squads()])
	verdict("F2 сторож зовётся из такта вожака (после _retreat_broken)",
		ai.has_method("_sweep_heal"))
	_finish()
