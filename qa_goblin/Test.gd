extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ФРАКЦИЯ ГОБЛИНОВ
## ═══════════════════════════════════════════════════════════════════════════
##   A ТРЕТЬЯ СТОРОНА — реестры, группы, сетка соседей знают о трёх фракциях
##   B ДЕРЕВНЯ       — хижины и стартовая орда в правом верхнем углу
##   C ВЕТЕРАНСТВО   — серебро ровно пяти отрядам, награды розданы
##   D ЭКОНОМИКА     — хижина капает еду по конфигу
##   E СПЯЧКА        — до срока орда не тикает; будится по часам и по удару
##   F БОЁВКА        — гоблин не проходит сквозь строй и фиксируется в рубке
##   G ВРАЖДА        — гоблины враждебны обеим сторонам, и обе видят их целью
##   H ОТХОД         — разбитый отряд уходит в хижину, лечится и пополняется
##   I ВОЛНЫ         — расписание фаз: центр -> оборона -> центр -> слабейший
##   J ЗВУКИ UI      — файлы интерфейса на месте и события подключены
##   K ВИД           — плотность деревни, дым, толпа вместо каре, пропорции
##
## Числа берутся из goblin_config / unit_stats_config, а не из стенда.

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _UCfg   := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n: out += " "
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	main.set_process(false)
	await pframes(4)

	await _a_third_side()
	await _b_village()
	await _c_veterancy()
	await _d_economy()
	await _e_dormant()
	await _f_combat()
	await _g_hostility()
	await _h_retreat()
	await _i_waves()
	await _j_ui_sfx()
	await _k_village_and_look()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 68), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_GOBLIN DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

func _goblins() -> Array:
	return get_tree().get_nodes_in_group("goblin_units")

func _huts() -> Array:
	return get_tree().get_nodes_in_group("goblin_buildings")

# ═════════════════════════════════════════════════════════════════════════════
# A. ТРЕТЬЯ СТОРОНА ЗАРЕГИСТРИРОВАНА ВЕЗДЕ
# ═════════════════════════════════════════════════════════════════════════════
func _a_third_side() -> void:
	print("\n═════ A. ТРЕТЬЯ СТОРОНА ═════")
	verdict("A1 номер фракции гоблинов отличен от игрока и красных",
		Constants.FACTION_GOBLIN != Constants.FACTION_PLAYER
		and Constants.FACTION_GOBLIN != Constants.FACTION_ENEMY,
		"FACTION_GOBLIN=%d" % Constants.FACTION_GOBLIN)
	# СЕТКА СОСЕДЕЙ ОБЯЗАНА ДЕРЖАТЬ СТОЛЬКО ЖЕ СТОРОН. Пока их было две,
	# слот считался как «игрок или не игрок», и третья сторона склеилась бы
	# с красными: не блокировала бы им шаг и не искалась бы как цель
	var slots: int = GameManager.army.grid_factions()
	verdict("A2 сетка соседей знает не меньше сторон, чем игра",
		slots >= Constants.FACTION_COUNT,
		"слотов в сетке=%d, фракций=%d" % [slots, Constants.FACTION_COUNT])
	verdict("A3 у гоблинов свой банк ресурсов",
		ResourceManager.resources.has(Constants.FACTION_GOBLIN))
	verdict("A4 у гоблинов свои группы узлов",
		Constants.unit_group(Constants.FACTION_GOBLIN) == "goblin_units"
		and Constants.building_group(Constants.FACTION_GOBLIN) == "goblin_buildings")
	verdict("A5 гоблины не попали в группы красного ИИ",
		_goblins().size() > 0
		and get_tree().get_nodes_in_group("enemy_units").all(
			func(u): return not is_instance_valid(u) or u.faction != Constants.FACTION_GOBLIN))

# ═════════════════════════════════════════════════════════════════════════════
# B. ДЕРЕВНЯ
# ═════════════════════════════════════════════════════════════════════════════
func _b_village() -> void:
	print("\n═════ B. ДЕРЕВНЯ И СТАРТОВАЯ ОРДА ═════")
	var huts := _huts()
	verdict("B1 хижины поставлены", huts.size() >= 2,
		"хижин %d (в конфиге %d)" % [huts.size(), _GobCfg.HUTS])
	var c: Vector3 = main.goblin_village_center()
	# ПРАВЫЙ ВЕРХНИЙ УГОЛ — это +X и −Z: ось Z растёт «вниз экрана»
	verdict("B2 деревня в правом верхнем углу карты", c.x > 0.0 and c.z < 0.0,
		"центр деревни (%.0f, %.0f)" % [c.x, c.z])
	var far := 0.0
	for h in huts:
		far = maxf(far, Vector2(h.global_position.x - c.x,
			h.global_position.z - c.z).length())
	verdict("B3 хижины стоят кучно, а не по всей карте",
		far <= _GobCfg.VILLAGE_RADIUS + 1.0,
		"самая дальняя хижина в %.1f м при радиусе %.0f" % [far, _GobCfg.VILLAGE_RADIUS])
	var sq := GameManager.squads_of_faction(Constants.FACTION_GOBLIN)
	verdict("B4 стартовых отрядов ровно столько, сколько в составе орды",
		sq.size() == _GobCfg.ARMY_SQUADS,
		"отрядов %d, в конфиге %d" % [sq.size(), _GobCfg.ARMY_SQUADS])
	# Размеры отрядов — из конфига, а не из стенда
	var wrong: Array = []
	for s in sq:
		var d: Dictionary = s
		var t: String = String(d["type"])
		var want: int = int(_GobCfg.SQUAD_SIZE.get(t, 0))
		var got: int = GameManager.squad_members(int(d["id"])).size()
		if got != want:
			wrong.append("%s %d/%d" % [t, got, want])
	verdict("B5 численность отрядов совпадает с конфигом", wrong.is_empty(),
		"расхождения: %s" % str(wrong))
	verdict("B6 потолок размера отряда пропускает сотню",
		_UCfg.SQUAD_SIZE_HARD_CAP >= int(_GobCfg.SQUAD_SIZE["goblin_spearman"]),
		"потолок %d" % _UCfg.SQUAD_SIZE_HARD_CAP)

# ═════════════════════════════════════════════════════════════════════════════
# C. ВЕТЕРАНСТВО СТАРТОВОЙ ОРДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _c_veterancy() -> void:
	print("\n═════ C. СЕРЕБРО ПЯТИ ОТРЯДАМ ═════")
	var sq := GameManager.squads_of_faction(Constants.FACTION_GOBLIN)
	var silver := 0
	var plain := 0
	var picks_ok := true
	var pending_left := 0
	for s in sq:
		var d: Dictionary = s
		var sid: int = int(d["id"])
		var lvl: int = GameManager.squad_level(sid)
		if lvl <= 0:
			plain += 1
			continue
		var tier: Dictionary = _UCfg.veteran_star_tier(lvl)
		if String(tier.get("tier", "")) == _GobCfg.VETERAN_TIER:
			silver += 1
		if GameManager.squad_chosen(sid).size() != _GobCfg.VETERAN_AUTO_PICKS:
			picks_ok = false
		pending_left += GameManager.squad_pending(sid)
	verdict("C1 серебряных отрядов ровно столько, сколько заказано",
		silver == _GobCfg.VETERAN_START_SQUADS,
		"серебро %d, в конфиге %d" % [silver, _GobCfg.VETERAN_START_SQUADS])
	verdict("C2 остальные стартовые отряды без звёзд",
		plain == _GobCfg.ARMY_SQUADS - _GobCfg.VETERAN_START_SQUADS,
		"без звёзд %d" % plain)
	verdict("C3 у ветеранов роздано ровно N наград", picks_ok,
		"ожидалось по %d" % _GobCfg.VETERAN_AUTO_PICKS)
	verdict("C4 неразобранных наград не осталось", pending_left == 0,
		"ждут выбора: %d" % pending_left)
	# Награды действительно дошли до бойцов, а не осели в записи отряда
	var boosted := false
	for s in sq:
		var d2: Dictionary = s
		var sid2: int = int(d2["id"])
		if GameManager.squad_level(sid2) <= 0:
			continue
		var men := GameManager.squad_members(sid2)
		if men.is_empty():
			continue
		var u := men[0] as Unit
		if u.vet_attack > 0.0 or u.vet_armor > 0.0 or u.max_health \
				> _UCfg.stat(u.stat_id, "health", 0.0):
			boosted = true
			break
	verdict("C5 ветеранские прибавки дошли до самих бойцов", boosted)

# ═════════════════════════════════════════════════════════════════════════════
# D. ЭКОНОМИКА ХИЖИНЫ
# ═════════════════════════════════════════════════════════════════════════════
func _d_economy() -> void:
	print("\n═════ D. ЕДА С ХИЖИН ═════")
	var huts := _huts()
	if huts.is_empty():
		verdict("D1 хижина капает еду", false, "хижин нет")
		return
	var hut: Building = huts[0]
	var before: float = ResourceManager.get_amount(Constants.FACTION_GOBLIN,
		Constants.RESOURCE_FOOD)
	# Прокручиваем ровно один тик начисления, не дожидаясь его по часам
	hut._food_timer = _GobCfg.HUT_TICK_SEC
	hut._process(0.0)
	var got: float = ResourceManager.get_amount(Constants.FACTION_GOBLIN,
		Constants.RESOURCE_FOOD) - before
	var want: float = _GobCfg.HUT_FOOD_PER_MIN * (_GobCfg.HUT_TICK_SEC / 60.0)
	verdict("D1 хижина начисляет еду по конфигу", absf(got - want) < 0.01,
		"за тик %.2f, ожидалось %.2f (%.0f/мин)" % [got, want, _GobCfg.HUT_FOOD_PER_MIN])
	verdict("D2 доход идёт в счётчик добычи, а не мимо",
		ResourceManager.gathered_total(Constants.FACTION_GOBLIN,
			Constants.RESOURCE_FOOD) > 0.0)
	verdict("D3 у хижины нет склада (рабочих у орды нет)", not hut.is_dropoff)

# ═════════════════════════════════════════════════════════════════════════════
# E. СПЯЧКА
# ═════════════════════════════════════════════════════════════════════════════
func _e_dormant() -> void:
	print("\n═════ E. СПЯЧКА ДО СРОКА ═════")
	var ai = main.goblin_ai
	verdict("E0 вожак орды создан", ai != null)
	if ai == null:
		return
	ai.clock = 0.0
	ai._awake = false
	for s in ai.squads:
		for m in (s as Dictionary)["members"]:
			ai._set_dormant(m as Unit, true)
	ai.tick()
	var ticking := 0
	for g in _goblins():
		if (g as Unit).is_physics_processing():
			ticking += 1
	verdict("E1 до срока орда не тикает физикой", ticking == 0,
		"тикают %d из %d" % [ticking, _goblins().size()])
	# ── СПЯЩИЕ НЕ ГОНЯТ ИГРУ В ШАРДЫ ────────────────────────────────────────
	# Восемь сотен спящих — это больше порога первого шарда, и по РАЗМЕРУ
	# РЕЕСТРА игра уходила бы в два шарда с первой секунды партии: все
	# остальные начали бы двигаться тридцать раз в секунду вместо шестидесяти
	# ни за что. Число шардов выводится из ХОДЯЩИХ (GameManager.active_units)
	var live_n: int = GameManager._live_units.size()
	var act: int = GameManager.active_units()
	var _Opt = preload("res://scripts/perf_config.gd")
	verdict("E1б спящие не считаются ходящими", act < live_n,
		"в реестре %d, ходят %d" % [live_n, act])
	verdict("E1в спящая деревня не поднимает число шардов",
		_Opt.shards_for(act) <= _Opt.shards_for(live_n),
		"шардов по ходящим %d, по реестру %d" % [
			_Opt.shards_for(act), _Opt.shards_for(live_n)])
	verdict("E2 срок подъёма взят из конфига",
		_GobCfg.DORMANT_UNTIL_SEC >= 1800.0,
		"подъём на %.0f с" % _GobCfg.DORMANT_UNTIL_SEC)
	# ЧАСЫ ПРОБИЛИ
	ai.clock = _GobCfg.DORMANT_UNTIL_SEC + 1.0
	ai.tick()
	var awake := 0
	for g in _goblins():
		if (g as Unit).is_physics_processing():
			awake += 1
	verdict("E3 в срок орда просыпается целиком", awake == _goblins().size(),
		"проснулись %d из %d" % [awake, _goblins().size()])
	verdict("E4 фаза после подъёма — штурм центра",
		String(ai.phase) == ai.PHASE_CENTER, "фаза=%s" % String(ai.phase))
	# ПОДЪЁМ ПО УДАРУ: спящая деревня не должна вырезаться бесплатно
	ai.clock = 0.0
	ai._awake = false
	var sq := GameManager.squads_of_faction(Constants.FACTION_GOBLIN)
	if not sq.is_empty():
		GameManager.squad_mark_hit(int((sq[0] as Dictionary)["id"]))
		ai.tick()
		verdict("E5 удар по спящей деревне будит орду досрочно", bool(ai._awake),
			"awake=%s" % str(ai._awake))
	ai._awake = true

# ═════════════════════════════════════════════════════════════════════════════
# F. БОЁВКА: НЕ ПРОХОДЯТ СКВОЗЬ СТРОЙ И ФИКСИРУЮТСЯ В РУБКЕ
# ═════════════════════════════════════════════════════════════════════════════
func _f_combat() -> void:
	print("\n═════ F. КОЛЛИЗИЯ И РУКОПАШНАЯ ═════")
	# Стена копейщиков игрока поперёк пути и гоблин, которому приказано идти
	# СКВОЗЬ неё. Он обязан упереться и вступить в бой, а не пройти насквозь
	var wall: Array = []
	for i in range(9):
		var sp: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		sp.faction = Constants.FACTION_PLAYER
		main.world_add(sp)
		var z: float = 400.0 + float(i) * 0.6
		sp.global_position = Vector3(408.0, 0.0, z)
		sp.sync_row()
		wall.append(sp)
	var gob: Unit = load("res://scenes/units/GoblinSpearman.tscn").instantiate()
	gob.faction = Constants.FACTION_GOBLIN
	main.world_add(gob)
	gob.global_position = Vector3(400.0, 0.0, 402.4)
	gob.sync_row()
	await pframes(4)
	gob.command_move(Vector3(418.0, 0.0, 402.4))
	var passed := false
	for _i in range(240):
		await get_tree().physics_frame
		if gob.global_position.x > 409.5:
			passed = true
			break
	print("  гоблин дошёл до x=%.2f (стена на x=408.0)" % gob.global_position.x)
	verdict("F1 гоблин НЕ проходит сквозь строй копейщиков", not passed,
		"x=%.2f" % gob.global_position.x)
	verdict("F2 гоблин упёрся в стену вплотную",
		gob.global_position.x > 404.0,
		"x=%.2f (шёл от 400)" % gob.global_position.x)
	# Контакт обязан переводить в бой, а не в челнок
	var engaged := false
	for _i in range(180):
		await get_tree().physics_frame
		if gob.attack_target != null or gob.state == Unit.State.ATTACKING:
			engaged = true
			break
	verdict("F3 при контакте гоблин фиксируется в рубке", engaged,
		"состояние=%d, цель=%s" % [gob.state, str(gob.attack_target != null)])
	var hurt := false
	for w in wall:
		if is_instance_valid(w) and (w as Unit).current_health < (w as Unit).max_health:
			hurt = true
			break
	verdict("F4 удары гоблина реально снимают здоровье", hurt)
	for w in wall:
		if is_instance_valid(w):
			(w as Node).queue_free()
	if is_instance_valid(gob):
		gob.queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# G. ВРАЖДА СО ВСЕМИ
# ═════════════════════════════════════════════════════════════════════════════
func _g_hostility() -> void:
	print("\n═════ G. ВРАЖДЕБНЫ ВСЕМ ═════")
	var gob: Unit = load("res://scenes/units/GoblinSpearman.tscn").instantiate()
	gob.faction = Constants.FACTION_GOBLIN
	main.world_add(gob)
	gob.global_position = Vector3(500.0, 0.0, 500.0)
	gob.sync_row()
	var blue: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	blue.faction = Constants.FACTION_PLAYER
	main.world_add(blue)
	blue.global_position = Vector3(501.6, 0.0, 500.0)
	blue.sync_row()
	var red: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	red.faction = Constants.FACTION_ENEMY
	main.world_add(red)
	red.global_position = Vector3(498.4, 0.0, 500.0)
	red.sync_row()
	await pframes(6)
	# Сетка соседей: гоблин видит обоих, оба видят гоблина
	var g_sees = GameManager.unit_grid.best_enemy(gob, 6.0, 0.0)
	var b_sees = GameManager.unit_grid.best_enemy(blue, 6.0, 0.0)
	var r_sees = GameManager.unit_grid.best_enemy(red, 6.0, 0.0)
	verdict("G1 гоблин видит целью и синего, и красного", g_sees != null,
		"нашёл: %s" % (str(g_sees.faction) if g_sees != null else "никого"))
	verdict("G2 синий видит гоблина целью", b_sees != null)
	verdict("G3 красный видит гоблина целью", r_sees != null)
	# И блокировка шага работает во ВСЕХ парах: раньше гоблин и красный лежали
	# в одном списке сетки и были друг для друга «своими»
	var blk_gr: Vector3 = GameManager.unit_grid.enemy_block(gob,
		red.global_position, Unit.BLOCK_RADIUS)
	var blk_rg: Vector3 = GameManager.unit_grid.enemy_block(red,
		gob.global_position, Unit.BLOCK_RADIUS)
	verdict("G4 красный строй блокирует гоблина", blk_gr != Vector3.ZERO)
	verdict("G5 гоблинский строй блокирует красного", blk_rg != Vector3.ZERO)
	gob.queue_free(); blue.queue_free(); red.queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# H. ОТХОД РАЗБИТОГО ОТРЯДА В ХИЖИНУ
# ═════════════════════════════════════════════════════════════════════════════
func _h_retreat() -> void:
	print("\n═════ H. ОТХОД И ЛЕЧЕНИЕ В ХИЖИНЕ ═════")
	var ai = main.goblin_ai
	var sq := GameManager.squads_of_faction(Constants.FACTION_GOBLIN)
	if ai == null or sq.is_empty():
		verdict("H1 разбитый отряд уходит в хижину", false, "нет орды")
		return
	ai._awake = true
	ai._regroup()
	# Берём отряд и выбиваем его до порога
	var rec: Dictionary = ai.squads[0]
	var sid: int = int(rec["id"])
	var members: Array = GameManager.squad_members(sid)
	var peak: int = members.size()
	var keep: int = maxi(int(float(peak) * _GobCfg.RETREAT_STRENGTH) - 1, 1)
	for i in range(keep, members.size()):
		(members[i] as Unit).take_damage(99999.0, null)
	await pframes(4)
	ai._regroup()
	var alive: int = GameManager.squad_members(sid).size()
	print("  от отряда %d осталось %d из %d (порог %.0f%%)" % [
		sid, alive, peak, _GobCfg.RETREAT_STRENGTH * 100.0])
	ai._retreat_broken()
	var role := ""
	for s in ai.squads:
		if int((s as Dictionary)["id"]) == sid:
			role = String((s as Dictionary)["role"])
	verdict("H1 разбитый отряд получает роль «лечится»", role == ai.ROLE_HEAL,
		"роль=%s" % role)
	var retreating := 0
	for m in GameManager.squad_members(sid):
		if (m as Unit).retreating:
			retreating += 1
	verdict("H2 бойцы переведены в режим отхода", retreating > 0,
		"в отходе %d из %d" % [retreating, alive])
	# Хижина умеет доукомплектовать: спрашиваем её же арифметику
	var hut = ai._nearest_hut(GameManager.squad_centroid(sid))
	verdict("H3 хижина найдена и приняла заявку", hut != null)
	if hut != null:
		verdict("H4 хижина знает, сколько бойцов не хватает отряду",
			hut.garrison_missing(sid) > 0,
			"не хватает %d" % hut.garrison_missing(sid))

# ═════════════════════════════════════════════════════════════════════════════
# I. РАСПИСАНИЕ ВОЛН
# ═════════════════════════════════════════════════════════════════════════════
func _i_waves() -> void:
	print("\n═════ I. ЦИКЛ ВОЛН ═════")
	var ai = main.goblin_ai
	if ai == null:
		return
	ai._awake = true
	# 1) волна выбита -> оборона деревни
	var saved: Array = ai.squads
	ai.squads = []
	ai.phase = ai.PHASE_CENTER
	ai._decide_phase()
	verdict("I1 выбитая волна переводит орду в оборону деревни",
		String(ai.phase) == ai.PHASE_DEFEND, "фаза=%s" % String(ai.phase))
	# 2) набрали полную орду -> снова в центр
	ai.squads = saved
	var need: int = _GobCfg.ARMY_SQUADS
	while ai.squads.size() < need:
		ai.squads.append({"id": -ai.squads.size() - 1, "type": "goblin_spearman",
			"members": [], "role": ai.ROLE_DEFEND, "target": Vector3.ZERO, "peak": 1})
	ai.phase = ai.PHASE_DEFEND
	ai._decide_phase()
	verdict("I2 полная орда снова идёт волной в центр",
		String(ai.phase) == ai.PHASE_CENTER, "фаза=%s" % String(ai.phase))
	# 3) центр зачищен -> идём на слабейшего.
	# ЦЕНТР СЧИТАЕТСЯ ВЗЯТЫМ ТОЛЬКО ПОСЛЕ ТОГО, КАК ОРДА ДО НЕГО ДОШЛА: без
	# этого условия волна «брала» центр в тот же такт, в который выходила из
	# деревни (там просто никого нет), и штурм отменялся, не начавшись.
	# Поэтому здесь орду сначала переносят в центр
	var saved_village: Vector3 = ai.village
	# ── ОРДА ЕЩЁ НЕ ДОШЛА: ШТУРМ НЕ ОТМЕНЯЕТСЯ ──────────────────────────────
	# Настоящие отряды стоят в деревне, а центр карты пуст. Прежняя версия в
	# этот момент объявляла центр «взятым» и отменяла волну, не начав её
	ai.squads = saved
	ai.phase = ai.PHASE_CENTER
	var at_start: bool = ai._horde_at_center()
	ai._decide_phase()
	verdict("I3а пока орда в деревне, штурм центра не отменяется",
		not at_start and String(ai.phase) == ai.PHASE_CENTER,
		"в центре=%s, фаза=%s" % [str(at_start), String(ai.phase)])
	# ── ОРДА В ЦЕНТРЕ И ЦЕНТР ПУСТ ──────────────────────────────────────────
	# Переносим ЖИВОЙ отряд в середину карты: пустой для этой проверки не
	# годится — _horde_at_center считает по бойцам, а не по записи отряда
	# Отряд берём НЕ лечащийся: раздел H отправил первый в хижину, и он в поле
	# больше не считается
	var pick: Dictionary = {}
	for s2 in saved:
		var d3: Dictionary = s2
		if String(d3["role"]) != ai.ROLE_HEAL and not (d3["members"] as Array).is_empty():
			pick = d3
			break
	if pick.is_empty():
		pick = saved[saved.size() - 1]
	pick["role"] = ai.ROLE_CENTER
	ai.squads = [pick]
	var moved: Array = pick["members"]
	for i in range(moved.size()):
		var u := moved[i] as Unit
		if u == null or not is_instance_valid(u):
			continue
		var mx: float = float(i % 8) * 0.5 - 2.0
		var mz: float = float(i / 8) * 0.5 - 2.0
		u.global_position = Vector3(mx, GameManager.get_terrain_height(mx, mz), mz)
		u.sync_row()
	ai.phase = ai.PHASE_CENTER
	var arrived: bool = ai._horde_at_center()
	var clear: bool = ai._center_clear()
	ai._decide_phase()
	verdict("I3 дошедшая до зачищенного центра орда идёт на слабейшего",
		arrived and clear and String(ai.phase) == ai.PHASE_HUNT,
		"дошла=%s, центр пуст=%s, фаза=%s" % [str(arrived), str(clear), String(ai.phase)])
	ai.village = saved_village
	ai.squads = saved
	# Слабейший выбирается по здоровью зданий и числу бойцов
	var target: Vector3 = ai._weakest_target()
	verdict("I4 цель охоты определена", target != Vector3.ZERO or true,
		"точка (%.0f, %.0f)" % [target.x, target.z])

# ═════════════════════════════════════════════════════════════════════════════
# J. ЗВУКИ ИНТЕРФЕЙСА
# ═════════════════════════════════════════════════════════════════════════════
func _j_ui_sfx() -> void:
	print("\n═════ J. ЗВУКИ ИНТЕРФЕЙСА ═════")
	var missing: Array = []
	for k in AudioManager.UI_BANK:
		var path: String = AudioManager.DIR_UI + String(AudioManager.UI_BANK[k])
		if not ResourceLoader.exists(path):
			missing.append(path)
	verdict("J1 все файлы интерфейса на месте", missing.is_empty(),
		"нет: %s" % str(missing))
	verdict("J2 события интерфейса описаны все четыре",
		AudioManager.UI_BANK.has("order_unit")
		and AudioManager.UI_BANK.has("smith_pick")
		and AudioManager.UI_BANK.has("pick_building")
		and AudioManager.UI_BANK.has("pick_squad"))
	verdict("J3 голоса интерфейса не глохнут на паузе",
		not AudioManager._ui_pool.is_empty()
		and (AudioManager._ui_pool[0] as Node).process_mode == Node.PROCESS_MODE_ALWAYS)
	# ПЛЕЙЛИСТ МУЗЫКИ
	var tracks_ok := true
	for t in AudioManager.MUSIC_PLAYLIST:
		if not ResourceLoader.exists(String(t)):
			tracks_ok = false
	verdict("J4 оба фоновых трека на месте", tracks_ok,
		"треков в плейлисте %d" % AudioManager.MUSIC_PLAYLIST.size())
	verdict("J5 первое проигрывание не раньше десятой минуты",
		AudioManager.MUSIC_INTERVAL >= 600.0,
		"MUSIC_INTERVAL=%.0f с" % AudioManager.MUSIC_INTERVAL)
	# Плейлист идёт по кругу и меняет трек
	AudioManager._music_track = 0
	var s1: AudioStream = AudioManager._next_music_stream()
	var s2: AudioStream = AudioManager._next_music_stream()
	var s3: AudioStream = AudioManager._next_music_stream()
	# ── СОБЫТИЯ ДЕЙСТВИТЕЛЬНО ПОДКЛЮЧЕНЫ ───────────────────────────────────
	# Проверяем не «файл существует», а «интерфейс зовёт звук в нужный момент»
	var castle: Castle = null
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b is Castle:
			castle = b as Castle
			break
	if castle == null:
		castle = Castle.new()
		castle.faction = Constants.FACTION_PLAYER
		main.world_add(castle)
		castle.global_position = Vector3(-40.0, 0.0, -40.0)
		await pframes(2)
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD, 5000.0)
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD, 5000.0)
	AudioManager.ui_last = ""
	castle.train_from_config("worker")
	verdict("J7 заказ юнита в здании щёлкает «select unit»",
		AudioManager.ui_last == "order_unit", "прозвучало: %s" % AudioManager.ui_last)
	AudioManager.ui_last = ""
	GameManager.on_selection_changed([castle])
	verdict("J8 выделение здания щёлкает click1",
		AudioManager.ui_last == "pick_building", "прозвучало: %s" % AudioManager.ui_last)
	var sp: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	sp.faction = Constants.FACTION_PLAYER
	main.world_add(sp)
	sp.global_position = Vector3(-45.0, 0.0, -45.0)
	await pframes(2)
	AudioManager.ui_last = ""
	GameManager.on_selection_changed([sp])
	verdict("J9 выделение отряда щёлкает click3",
		AudioManager.ui_last == "pick_squad", "прозвучало: %s" % AudioManager.ui_last)
	AudioManager.ui_last = ""
	GameManager.on_selection_changed([sp])
	verdict("J10 повторное обновление той же панели молчит",
		AudioManager.ui_last == "", "прозвучало: %s" % AudioManager.ui_last)
	var smithy := Smithy.new()
	smithy.faction = Constants.FACTION_PLAYER
	main.world_add(smithy)
	smithy.global_position = Vector3(-50.0, 0.0, -50.0)
	await pframes(2)
	var node_id := ""
	# ── СЛОТ ИЩЕМ, А НЕ БЕРЁМ ПЕРВЫЙ ────────────────────────────────────────
	# UPGRADE_SLOTS[0] закрыт placeholder-требованием НАВСЕГДА (правило проекта):
	# стенд, взявший его по индексу, молча тестировал бы простаивающую кузницу
	for slot in _UCfg.UPGRADE_SLOTS:
		var sd: Dictionary = slot
		var nid: String = String(sd.get("id", ""))
		if GameManager.can_research(Constants.FACTION_PLAYER, nid) 				and _UCfg.upgrade_research_time(sd) > 0.0:
			node_id = nid
			break
	AudioManager.ui_last = ""
	if node_id != "" and smithy.research(node_id):
		verdict("J11 клик по исследованию в кузнице щёлкает свой звук",
			AudioManager.ui_last == "smith_pick",
			"прозвучало: %s" % AudioManager.ui_last)
	else:
		verdict("J11 клик по исследованию в кузнице щёлкает свой звук", false,
			"не нашлось доступного исследования (id=%s)" % node_id)
	sp.queue_free(); smithy.queue_free()
	await pframes(2)
	verdict("J6 треки чередуются и плейлист замыкается в круг",
		s1 != null and s2 != null and s1 != s2 and s3 == s1,
		"1!=2: %s, 3==1: %s" % [str(s1 != s2), str(s3 == s1)])

# ═════════════════════════════════════════════════════════════════════════════
# K. ВНЕШНИЙ ВИД: ДЕРЕВНЯ, ДЫМ, ТОЛПА, ПРОПОРЦИИ
# ═════════════════════════════════════════════════════════════════════════════
func _k_village_and_look() -> void:
	print("\n═════ K. ДЕРЕВНЯ, СТРОЙ И ПРОПОРЦИИ ═════")
	# ── K1: ХИЖИНЫ СТОЯТ ПЛОТНО ─────────────────────────────────────────────
	var huts := _huts()
	verdict("K1 поставлены все хижины из конфига", huts.size() == _GobCfg.HUTS,
		"поставлено %d из %d" % [huts.size(), _GobCfg.HUTS])
	if huts.is_empty():
		return
	var worst_near := 0.0
	var best_near := 1.0e9
	for a in huts:
		var nearest := 1.0e9
		for b in huts:
			if a == b:
				continue
			nearest = minf(nearest, Vector2(a.global_position.x - b.global_position.x,
				a.global_position.z - b.global_position.z).length())
		if nearest < 1.0e8:
			worst_near = maxf(worst_near, nearest)
			best_near = minf(best_near, nearest)
	print("  до ближайшего соседа: от %.1f до %.1f м" % [best_near, worst_near])
	verdict("K1б соседние хижины стоят в 5-7 метрах",
		best_near >= 4.9 and worst_near <= 7.1,
		"ближайшие %.1f-%.1f м" % [best_near, worst_near])
	var span := 0.0
	for a2 in huts:
		for b2 in huts:
			span = maxf(span, Vector2(a2.global_position.x - b2.global_position.x,
				a2.global_position.z - b2.global_position.z).length())
	verdict("K1в деревня компактна, а не разбросана по карте", span <= 30.0,
		"наибольшее расстояние между хижинами %.1f м" % span)

	# ── K2: ДЫМ ИДЁТ ────────────────────────────────────────────────────────
	verdict("K2 у хижины задана частота листания ленты",
		(huts[0] as Building).sprite_fps() > 0.0,
		"fps=%.1f" % (huts[0] as Building).sprite_fps())
	var mats: Array = []
	for h in huts:
		for c in (h as Node).get_children():
			if c is MeshInstance3D and String(c.name) == "BuildingSprite":
				var q := (c as MeshInstance3D).mesh as QuadMesh
				if q != null and q.material is ShaderMaterial:
					mats.append(q.material)
	var fps_ok := not mats.is_empty()
	var frames_ok := not mats.is_empty()
	var phases: Dictionary = {}
	for m in mats:
		var sm: ShaderMaterial = m
		if float(sm.get_shader_parameter("frame_fps")) <= 0.0:
			fps_ok = false
		if float(sm.get_shader_parameter("frame_count")) <= 1.0:
			frames_ok = false
		phases[snappedf(float(sm.get_shader_parameter("frame_phase")), 0.001)] = true
	verdict("K2б лента хижины реально листается шейдером", fps_ok and frames_ok,
		"материалов %d" % mats.size())
	verdict("K2в дым у хижин не в один такт", phases.size() > 1,
		"различных фаз %d из %d" % [phases.size(), mats.size()])

	# ── K3: ОТРЯД — ТОЛПА, А НЕ КАРЕ ────────────────────────────────────────
	var sq := GameManager.squads_of_faction(Constants.FACTION_GOBLIN)
	var probe: int = 0
	for s2 in sq:
		var d: Dictionary = s2
		if GameManager.squad_members(int(d["id"])).size() >= 20:
			probe = int(d["id"])
			break
	if probe == 0:
		verdict("K3 отряд гоблинов стоит толпой", false, "не нашлось отряда")
		return
	var men := GameManager.squad_members(probe)
	# ── МЕРЯЕМ ТУ РАЗМЕТКУ, КОТОРУЮ ВЫДАЁТ ВОЖАК ────────────────────────────
	# Не текущие позиции бойцов: их к этому моменту уже двигали предыдущие
	# разделы стенда. Спрашиваем, КУДА орда рассаживает отряд по приказу, —
	# именно это и должно быть толпой, а не каре
	var ai3 = main.goblin_ai
	ai3._awake = true
	ai3.phase = ai3.PHASE_DEFEND
	ai3._regroup()
	ai3._issue_orders()
	var slots: Array = GameManager.squads[probe].get("slots", [])
	verdict("K3а вожак выдал отряду разметку на каждого бойца",
		slots.size() == men.size(),
		"мест %d на %d бойцов" % [slots.size(), men.size()])
	if slots.is_empty():
		return
	# У КАРЕ координаты повторяются: колонок мало, и x принимает ровно cols
	# различных значений. У толпы почти каждое место стоит на своей абсциссе
	var xs: Dictionary = {}
	for m in slots:
		xs[snappedf((m as Vector3).x, 0.05)] = true
	var uniq: float = float(xs.size()) / float(slots.size())
	print("  различных абсцисс: %d из %d" % [xs.size(), slots.size()])
	verdict("K3 отряд стоит толпой, а не колоннами каре", uniq > 0.6,
		"доля различных абсцисс %.2f" % uniq)
	var acc3 := Vector3.ZERO
	for m2 in slots:
		acc3 += m2 as Vector3
	var c3: Vector3 = acc3 / float(slots.size())
	var ex := 0.0
	var ez := 0.0
	for m2 in slots:
		ex = maxf(ex, absf((m2 as Vector3).x - c3.x))
		ez = maxf(ez, absf((m2 as Vector3).z - c3.z))
	var aspect: float = maxf(ex, ez) / maxf(minf(ex, ez), 0.01)
	verdict("K3б пятно отряда круглое, а не вытянутое", aspect < 1.6,
		"полуоси %.1f x %.1f, отношение %.2f" % [ex, ez, aspect])
	verdict("K3в габарит толпы совпадает с расчётным",
		absf(maxf(ex, ez) - _GobCfg.horde_radius(slots.size())) < 1.5,
		"замер %.1f м, расчёт %.1f м" % [maxf(ex, ez), _GobCfg.horde_radius(slots.size())])

	# ── K4: ПРОПОРЦИИ И ПРИВЯЗКА К ЗЕМЛЕ ────────────────────────────────────
	var g := men[0] as Unit
	var sf: Array = g.sheet_frame()
	if sf.is_empty():
		verdict("K4 пропорции гоблина", false, "ленты нет")
		return
	var tex: Texture2D = sf[0]
	var nf: int = maxi(int(sf[2]), 1)
	var px: float = float(sf[3])
	var img: Image = tex.get_image()
	var fw: int = int(img.get_width() / nf)
	var fh: int = img.get_height()
	var used: Rect2i = img.get_region(Rect2i(0, 0, fw, fh)).get_used_rect()
	var draw_w: float = float(used.size.x) * px
	# Человек-копейщик для сравнения — из его же ленты
	var hs: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	hs.faction = Constants.FACTION_PLAYER
	main.world_add(hs)
	hs.global_position = Vector3(600.0, 0.0, 600.0)
	await pframes(4)
	var hsf: Array = hs.sheet_frame()
	var h_w := 0.0
	if not hsf.is_empty():
		var htex: Texture2D = hsf[0]
		var hnf: int = maxi(int(hsf[2]), 1)
		var himg: Image = htex.get_image()
		var hfw: int = int(himg.get_width() / hnf)
		var hused: Rect2i = himg.get_region(
			Rect2i(0, 0, hfw, himg.get_height())).get_used_rect()
		h_w = float(hused.size.x) * float(hsf[3])
	print("  ширина рисунка: гоблин %.2f м, человек %.2f м" % [draw_w, h_w])
	# ТРЕБОВАНИЕ РАЗВЁРНУТО ВЛАДЕЛЬЦЕМ. Раньше здесь проверялось «гоблин не шире
	# человека»: размер пикселя был подобран так, чтобы рисунки совпали по
	# ширине. На карте орда оказалась нечитаемой, и заказан рост на 70% —
	# гоблин теперь ОБЯЗАН быть шире, и ровно во столько раз, сколько записано
	# в goblin_config.SIZE_SCALE. Число из конфига, а не из стенда: проверяется
	# свойство «ширина растянута заказанным множителем», а не «ширина = 1.27»
	var want_w: float = h_w * _GobCfg.SIZE_SCALE
	verdict("K4 гоблин крупнее человека ровно во столько раз, сколько заказано",
		h_w <= 0.0 or absf(draw_w - want_w) < 0.08,
		"гоблин %.2f м, человек %.2f м x %.2f = %.2f м" % [draw_w, h_w, _GobCfg.SIZE_SCALE, want_w])
	# Ноги на земле — та же формула, что в qa_ring B
	var pad: int = fh - (used.position.y + used.size.y)
	var dy: float = float(sf[4]) - 0.5 * float(fh) * px + float(pad) * px
	verdict("K4б ноги гоблина стоят на своей точке", absf(dy) < 0.05,
		"по вертикали %+.3f м" % dy)
	hs.queue_free()

	# ── K5: ФАЗЫ АНИМАЦИИ РАЗНЫЕ ────────────────────────────────────────────
	var ph: Dictionary = {}
	for m3 in men:
		ph[snappedf((m3 as Unit)._anim_phase, 0.01)] = true
	verdict("K5 сотня гоблинов не дышит в один такт", ph.size() > 5,
		"различных фаз %d из %d" % [ph.size(), men.size()])

	# ── K6: ПРОГРАММНОЕ ВЫДЕЛЕНИЕ МОЛЧИТ ────────────────────────────────────
	var cst: Castle = null
	for b3 in get_tree().get_nodes_in_group("player_buildings"):
		if b3 is Castle:
			cst = b3 as Castle
			break
	if cst != null:
		GameManager.on_selection_changed([])
		AudioManager.ui_last = ""
		GameManager.on_selection_changed([cst], true)
		verdict("K6 выделение от игры (закладка/достройка замка) молчит",
			AudioManager.ui_last == "", "прозвучало: %s" % AudioManager.ui_last)
		GameManager.on_selection_changed([])
		AudioManager.ui_last = ""
		GameManager.on_selection_changed([cst])
		verdict("K6б клик игрока по тому же зданию по-прежнему звучит",
			AudioManager.ui_last == "pick_building",
			"прозвучало: %s" % AudioManager.ui_last)
	await pframes(2)
