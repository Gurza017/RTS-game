extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_TZ1027D — ТЗ 27.10.2026 (аудит): красный ИИ — лимиты и распад армии.
## ═══════════════════════════════════════════════════════════════════════════
## A — конфиг: лимит 25-30 отрядов, в поле уходит большинство армии,
##     домов хватает на еду для полной армии
## B — _regroup не рвёт отряд реестра: партия из бараков — одна группа ИИ,
##     огрызок рядом вливается в группу (одно знамя), далёкий — своя группа
##     (ручка ai_regroup_whole)
## C — докомплектация в тишине: отряд ниже половины силы без врага рядом
##     уходит в замок (ручка ai_refill_home)
## D — штурм по доле армии (ручка ai_assault_fraction)
## E — волна держится вместе: ушедший вперёд отряд ждёт (ручка ai_wave_hold)
## F — отряд реестра, в котором ещё никого не было, геттер не распускает
##     (ручка squad_keep_unborn): партия из бараков выходит ОДНИМ отрядом
## G — охрана крепости засыпает, когда каждый боец у своего места поста,
##     отставшим — приказ на место; срок сбора (ручка guard_sleep_gathered)
## Каждая ручка проверяется и выключением. Ручки: only=abcdefg
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _Spawn := preload("res://scripts/spawn_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const R := Constants.FACTION_ENEMY

var main = null
var ai = null
var castle: Castle = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abcdefg"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz1027d: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _unit(uid: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = R
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	_mine.append(u)
	return u

## Отряд реестра красного; ответ — [sid, members]
func _squad(uid: String, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(R, uid)
	var men: Array = []
	for i in range(n):
		var p: Vector3 = at + Vector3((float(i % cols) - float(cols - 1) * 0.5) * 0.65, 0.0, float(i / cols) * 0.65)
		var u: Unit = _unit(uid, p)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

## Группа ИИ поверх готового отряда реестра
func _group(uid: String, men: Array, role: String = "guard") -> Dictionary:
	var sq := {
		"type": uid, "members": men.duplicate(), "role": role,
		"target": (men[0] as Node3D).global_position, "issued": false,
		"flank_side": 0, "flank_close": false, "peak": men.size(),
	}
	ai.squads.append(sq)
	return sq

## Убиваем ТОЛЬКО своих спавненных: смерть всей охраны и гарнизонов красного
## роняет его постройки (крепость исчезала между блоками)
var _mine: Array = []
func _kill_all() -> void:
	for u in _mine:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e12)
	_mine.clear()
	ai.squads.clear()

## Сколько групп ИИ держат бойцов отряда реестра sid и сколько их всего в группах
func _groups_of(sid: int) -> Array:
	var groups := 0
	var men := 0
	for s in ai.squads:
		var k := 0
		for m in (s as Dictionary)["members"]:
			if is_instance_valid(m) and (m as Unit).squad_id == sid:
				k += 1
		if k > 0:
			groups += 1
			men += k
	return [groups, men]

func _alive_sq(sq: Dictionary) -> int:
	var n := 0
	for m in sq["members"]:
		if is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n

func _run() -> void:
	seed(2710)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	_Opt.squad_probes = false
	ai = main.enemy_ai
	if ai.red.ai == null:
		ai.red.ai = ai
	castle = ai._find_castle()
	print("  крепость красного: %s" % (str(castle.global_position) if castle != null else "нет"))
	if "a" in _only: _a_config()
	if "b" in _only: await _b_regroup()
	if "c" in _only: await _c_refill()
	if "d" in _only: _d_ready()
	if "e" in _only: await _e_wave()
	if "f" in _only: await _f_unborn()
	if "g" in _only: await _g_guard_gather()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_config() -> void:
	print("\n═════ A. КОНФИГ КРАСНОГО ═════")
	var total: int = _AICfg.total_squad_limit()
	var men: int = _AICfg.total_army_cap()
	print("  лимит: %d отрядов, %d бойцов; дома у замка %d на род; домов %d" % [
		total, men, _AICfg.HOME_GUARD_PER_TYPE, _Spawn.AI_HOUSES])
	verdict("A1 лимит отрядов красного 25-30 (ТЗ: эндгейм-давление)", total >= 25 and total <= 30, "%d" % total)
	var home: int = 0
	for key in _AICfg.SQUAD_LIMIT:
		home += mini(_AICfg.HOME_GUARD_PER_TYPE, _AICfg.squad_limit(String(key)))
	verdict("A2 в поле уходит не меньше 70 %% армии (дома %d из %d)" % [home, total],
		float(total - home) >= 0.7 * float(total))
	# Еда: доход домов за время до срока штурма покрывает найм полной боевой армии
	# (рабочие — отдельно, их кормит стартовый запас и первые дома)
	var income: float = float(_Spawn.AI_HOUSES) * _UCfg.HOUSE_FOOD_INCOME / _UCfg.HOUSE_FOOD_INTERVAL
	var need := 0.0
	for key in _AICfg.SQUAD_LIMIT:
		var uid: String = String(key)
		var c: Dictionary = _UCfg.train_cfg("barracks" if uid != "archer" else "archery", uid)
		if c.is_empty():
			c = _UCfg.train_cfg("castle", uid)
		need += float(_AICfg.squad_limit(uid)) * float(c.get("cost_food", 0.0))
	var horizon: float = _Spawn.AI_ASSAULT_AT_SEC
	print("  еда: доход %.2f/с, нужно %.0f на боевую армию, за %.0f с до срока штурма накопится %.0f" % [
		income, need, horizon, income * horizon])
	verdict("A3 домов хватает: еда до срока штурма покрывает найм полной боевой армии", income * horizon >= need)
	verdict("A4 доля штурма в (0.5, 1.0]", _AICfg.ASSAULT_READY_FRACTION > 0.5 and _AICfg.ASSAULT_READY_FRACTION <= 1.0)

# ═════════════════════════════════════════════════════════════════════════════
func _b_regroup() -> void:
	print("\n═════ B. _regroup НЕ РВЁТ ОТРЯД РЕЕСТРА ═════")
	if castle == null:
		verdict("B0 крепость красного есть", false)
		return
	var base: Vector3 = castle.global_position
	var dir: Vector3 = (main.ai_rally_point() - base)
	dir.y = 0.0
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	_diag_castle("начало B")
	for knob in [true, false]:
		_Opt.ai_regroup_whole = knob
		_kill_all()
		await pframes(3)
		_diag_castle("после _kill_all")
		# Огрызок в поле (20 из 60) в своей группе, далеко от ворот
		var far_at: Vector3 = GameManager.land_target(base + dir * 90.0)
		var rem: Array = _squad("spearman", far_at, 20)
		_group("spearman", rem[1], "line")
		# Свежая партия из бараков у ворот — 60, ни в одной группе
		var fresh: Array = _squad("spearman", GameManager.land_target(base + dir * 12.0), 60, 10)
		await pframes(2)
		_diag_castle("после спавна")
		ai._regroup()
		_diag_castle("после _regroup")
		var gf: Array = _groups_of(int(fresh[0]))
		var gr: Array = _groups_of(int(rem[0]))
		print("  [%s] партия 60: групп %d, бойцов в группах %d; огрызок: групп %d, бойцов %d; групп всего %d" % [
			"ручка вкл" if knob else "ручка выкл", gf[0], gf[1], gr[0], gr[1], ai.squads.size()])
		if knob:
			verdict("B1 партия из бараков — одна группа ИИ целиком", gf[0] == 1 and gf[1] == 60, "%d групп, %d бойцов" % [gf[0], gf[1]])
			verdict("B2 далёкий огрызок не трогается (своя группа, 20 бойцов)", gr[0] == 1 and gr[1] == 20)
			# Огрызок рядом с другим огрызком — вливается (одно знамя)
			var near_at: Vector3 = GameManager.land_target(far_at + side * 12.0)
			var small: Array = _squad("spearman", near_at, 15)
			var merges0: int = ai.regroup_merges
			await pframes(2)
			ai._regroup()
			var same := 0
			for u in small[1]:
				if is_instance_valid(u) and (u as Unit).squad_id == int(rem[0]):
					same += 1
			var grp_sz := -1
			for s in ai.squads:
				for m in (s as Dictionary)["members"]:
					if is_instance_valid(m) and (m as Unit).squad_id == int(rem[0]):
						grp_sz = ((s as Dictionary)["members"] as Array).size()
						break
				if grp_sz >= 0:
					break
			verdict("B3 огрызок рядом влился в отряд реестра соседа (одно знамя)", same == 15 and ai.regroup_merges == merges0 + 1,
				"перешло %d из 15, слияний %d" % [same, ai.regroup_merges - merges0])
			verdict("B4 группа соседа выросла до 35", grp_sz == 35, "%d" % grp_sz)
			# Далёкий огрызок (80 м от всех) — своя группа, отряд реестра не меняется
			var lone_at: Vector3 = GameManager.land_target(base - side * 80.0)
			var lone: Array = _squad("spearman", lone_at, 15)
			await pframes(2)
			ai._regroup()
			var gl: Array = _groups_of(int(lone[0]))
			var kept := 0
			for u in lone[1]:
				if is_instance_valid(u) and (u as Unit).squad_id == int(lone[0]):
					kept += 1
			verdict("B5 далёкий огрызок — своя группа, знамя своё", gl[0] == 1 and gl[1] == 15 and kept == 15)
		else:
			verdict("B6 ручка выключена — партия рвётся по группам (старое поведение)", gf[0] >= 2, "%d групп" % gf[0])
	_Opt.ai_regroup_whole = true
	_kill_all()
	await pframes(3)
	_diag_castle("после B")

func _diag_castle(tag: String) -> void:
	var nb := 0
	for b in main.get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b):
			nb += 1
	print("  [диаг %s] крепость жива=%s, фаза=%s, зданий красного %d, часы %.1f" % [
		tag, str(is_instance_valid(castle)), str(main._phase), nb, main._match_clock])
	if not is_instance_valid(castle):
		castle = ai._find_castle()
		print("  [диаг %s] новая крепость: %s" % [tag, str(castle.global_position) if castle != null else "нет"])

# ═════════════════════════════════════════════════════════════════════════════
func _c_refill() -> void:
	print("\n═════ C. ДОКОМПЛЕКТАЦИЯ В ТИШИНЕ ═════")
	if castle == null:
		verdict("C0 крепость красного есть", false)
		return
	var base: Vector3 = castle.global_position
	var dir: Vector3 = (main.ai_rally_point() - base)
	dir.y = 0.0
	dir = dir.normalized()
	for knob in [true, false]:
		_Opt.ai_refill_home = knob
		_kill_all()
		await pframes(3)
		var sqd: Array = _squad("spearman", GameManager.land_target(base + dir * 40.0), 30)
		var sq: Dictionary = _group("spearman", sqd[1], "line")
		sq["peak"] = 30
		for u in sqd[1]:
			(u as Unit).current_health = (u as Unit).max_health * 0.4
		await pframes(2)
		var trips0: int = ai.refill_trips
		var strength: float = ai._squad_strength(sq)
		var went: bool = ai._try_retreat(sq, castle)
		print("  [%s] сила %.2f, порог отхода %.2f, порог докомплектации %.2f → отход %s, роль %s" % [
			"ручка вкл" if knob else "ручка выкл", strength, _AICfg.RETREAT_STRENGTH,
			_AICfg.RETREAT_REFILL_STRENGTH, str(went), String(sq["role"])])
		if knob:
			verdict("C1 отряд на 40 %% силы в тишине уходит в замок", went and String(sq["role"]) == ai.ROLE_RETREAT
				and ai.refill_trips == trips0 + 1)
			# Здоровый отряд не уходит
			_kill_all()
			await pframes(3)
			var ok_sq: Array = _squad("spearman", GameManager.land_target(base + dir * 40.0), 30)
			var sq2: Dictionary = _group("spearman", ok_sq[1], "line")
			sq2["peak"] = 30
			await pframes(2)
			verdict("C2 здоровый отряд в тишине остаётся", not ai._try_retreat(sq2, castle))
		else:
			verdict("C3 ручка выключена — 40 %% без угрозы рядом не уходит (прежнее правило)", not went)
	_Opt.ai_refill_home = true
	_kill_all()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _d_ready() -> void:
	print("\n═════ D. ШТУРМ ПО ДОЛЕ АРМИИ ═════")
	var total := 0
	for t in _AICfg.combat_types():
		total += ai._Diff.ai_squad_limit(String(t)) if false else 0
	total = _AICfg.total_squad_limit()
	var need: int = int(ceil(float(total) * _AICfg.ASSAULT_READY_FRACTION))
	var dummy := _unit("spearman", GameManager.land_target(castle.global_position + Vector3(5, 0, 5)))
	ai.squads.clear()
	_Opt.ai_assault_fraction = true
	for i in range(need - 1):
		ai.squads.append({"type": "spearman", "members": [dummy], "role": "guard", "target": Vector3.ZERO,
			"issued": true, "flank_side": 0, "flank_close": false, "peak": 1})
	var before: bool = ai.army_ready()
	ai.squads.append({"type": "spearman", "members": [dummy], "role": "guard", "target": Vector3.ZERO,
		"issued": true, "flank_side": 0, "flank_close": false, "peak": 1})
	var after: bool = ai.army_ready()
	print("  лимит %d, нужно %d групп: при %d → %s, при %d → %s" % [total, need, need - 1, str(before), need, str(after)])
	verdict("D1 ниже доли штурма нет", not before)
	verdict("D2 с долей — штурм готов (без единого лучника и рыцаря)", after)
	_Opt.ai_assault_fraction = false
	verdict("D3 ручка выключена — прежнее правило «все рода до лимита»: не готов", not ai.army_ready())
	_Opt.ai_assault_fraction = true
	ai.squads.clear()
	dummy.take_damage(1.0e12)

# ═════════════════════════════════════════════════════════════════════════════
func _e_wave() -> void:
	print("\n═════ E. ВОЛНА ДЕРЖИТСЯ ВМЕСТЕ ═════")
	if castle == null:
		verdict("E0 крепость красного есть", false)
		return
	var base: Vector3 = castle.global_position
	var rally: Vector3 = main.ai_rally_point()
	var dir: Vector3 = rally - base
	dir.y = 0.0
	dir = dir.normalized()
	var per_home: int = _AICfg.HOME_GUARD_PER_TYPE
	# Привалы волны (ai_wave_stages, ТЗ 31.10.2026) держат волну сами и на
	# привале wave_hold не зовут — блок меряет wave_hold один
	_Opt.ai_wave_stages = false
	for knob in [true, false]:
		_Opt.ai_wave_hold = knob
		_kill_all()
		await pframes(3)
		# Домашние — первые HOME_GUARD_PER_TYPE копейщиков; дальше два полевых:
		# A — в 80 м от озера (тыл), B — в 10 м от точки сбора (у озера свои есть →
		# центр взят, волна «вышла»; B впереди центра волны на 35 м)
		for i in range(per_home):
			var h: Array = _squad("spearman", GameManager.land_target(base + dir * (14.0 + 4.0 * float(i))), 12, 6)
			_group("spearman", h[1])
		# Курс волны — от её центра к цели (база игрока, иначе озеро)
		var tgt: Vector3 = ai._player_base_pos()
		if tgt == Vector3.ZERO:
			tgt = rally
		var toward: Vector3 = tgt - rally
		toward.y = 0.0
		toward = toward.normalized() if toward.length() > 0.01 else dir
		var a: Array = _squad("spearman", GameManager.land_target(rally - toward * 55.0), 24, 6)
		var ga: Dictionary = _group("spearman", a[1], "field")
		var b: Array = _squad("spearman", GameManager.land_target(rally + toward * 15.0), 24, 6)
		var gb: Dictionary = _group("spearman", b[1], "field")
		await pframes(2)
		ai._peace_over = true
		ai._wave_out = true
		ai._lake_taken = true
		var holds0: int = ai.wave_holds
		ai._command_squads(castle)
		var cb: Vector3 = ai._squad_centroid(gb["members"])
		var ca: Vector3 = ai._squad_centroid(ga["members"])
		var db: float = (gb["target"] as Vector3).distance_to(cb)
		var da: float = (ga["target"] as Vector3).distance_to(ca)
		print("  [%s] цель B от его центра %.1f м, цель A от его центра %.1f м, удержаний %d, роли %s/%s" % [
			"ручка вкл" if knob else "ручка выкл", db, da, ai.wave_holds - holds0, String(ga["role"]), String(gb["role"])])
		if knob:
			verdict("E1 ушедший вперёд отряд B ждёт: его цель — где стоит", db < 3.0 and ai.wave_holds > holds0, "%.1f м" % db)
			verdict("E2 отряд A идёт к цели волны (не удержан)", da > 10.0, "%.1f м" % da)
		else:
			verdict("E3 ручка выключена — B идёт вперёд к цели волны", db > 10.0, "%.1f м" % db)
	_Opt.ai_wave_hold = true
	_Opt.ai_wave_stages = true
	ai._wave_out = false
	ai._lake_taken = false
	_kill_all()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _f_unborn() -> void:
	print("\n═════ F. ПУСТАЯ ЗАПИСЬ ОТРЯДА ДО ПЕРВОГО БОЙЦА ═════")
	# F1-F2: прямой сценарий бараков — запись заведена, бойцов ещё нет, такт ИИ
	# спросил состав всех отрядов стороны
	for knob in [true, false]:
		_Opt.squad_keep_unborn = knob
		var sid: int = GameManager.new_squad(R, "spearman")
		GameManager.squads_of_faction(R)
		var kept: bool = GameManager.squads.has(sid)
		var u: Unit = _unit("spearman", GameManager.land_target(castle.global_position + Vector3(20, 0, 0)))
		GameManager.add_to_squad(sid, u)
		if knob:
			verdict("F1 ручка вкл: пустая запись пережила squads_of_faction, боец вошёл в отряд",
				kept and u.squad_id == sid, "запись %s, squad_id %d (ждали %d)" % [str(kept), u.squad_id, sid])
		else:
			verdict("F2 ручка выкл: запись распущена, боец остался без отряда (прежнее поведение)",
				not kept and u.squad_id == 0, "запись %s, squad_id %d" % [str(kept), u.squad_id])
		if GameManager.squads.has(sid):
			GameManager._disband_squad(sid)
	_Opt.squad_keep_unborn = true
	# F3: опустевший ПО ПОТЕРЯМ отряд распускается по-прежнему
	var r: Array = _squad("spearman", GameManager.land_target(castle.global_position + Vector3(24, 0, 0)), 2, 2)
	var sid3: int = r[0]
	for m in r[1]:
		(m as Unit).take_damage(1.0e12)
	await pframes(2)
	GameManager.squad_members(sid3)
	verdict("F3 отряд, потерявший всех, геттер распускает как раньше", not GameManager.squads.has(sid3))
	# F4: сквозной сценарий — заказ в крепости красного, такт ИИ каждый кадр
	for knob in [true, false]:
		_Opt.squad_keep_unborn = knob
		var before: Dictionary = {}
		for n in main.get_tree().get_nodes_in_group("enemy_units"):
			before[n.get_instance_id()] = true
		var ok_q: bool = castle.queue_unit("spearman", {}, 0.05)
		castle.set_process(true)
		var fresh: Array = []
		for _w in range(900):
			await pframes(1)
			GameManager.squads_of_faction(R)     # то, что делает такт ИИ
			fresh.clear()
			for n in main.get_tree().get_nodes_in_group("enemy_units"):
				if is_instance_valid(n) and not before.has(n.get_instance_id()) and n is Unit \
						and (n as Unit).stat_id == "spearman":
					fresh.append(n)
			if fresh.size() >= _UCfg.squad_size("spearman"):
				break
		await pframes(5)
		var sids: Dictionary = {}
		for n in fresh:
			sids[(n as Unit).squad_id] = int(sids.get((n as Unit).squad_id, 0)) + 1
			_mine.append(n)
		print("  [%s] заказ %s, вышло %d, по отрядам %s" % ["ручка вкл" if knob else "ручка выкл", str(ok_q), fresh.size(), str(sids)])
		if knob:
			verdict("F4 ручка вкл: партия из крепости вышла ОДНИМ отрядом реестра, без squad_id 0",
				fresh.size() > 0 and sids.size() == 1 and not sids.has(0), str(sids))
		else:
			verdict("F5 ручка выкл: такт ИИ между заказом и спавном оставляет партию без отряда",
				fresh.size() > 0 and sids.has(0), str(sids))
	_Opt.squad_keep_unborn = true
	_kill_all()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
const _HG := preload("res://scripts/ai/HomeGuard.gd")
func _g_guard_gather() -> void:
	print("\n═════ G. ОХРАНА СПИТ, КОГДА СОБРАЛАСЬ ═════")
	if castle == null:
		verdict("G0 крепость красного есть", false)
		return
	var guard = main.get("enemy_guard")
	if guard == null or not is_instance_valid(guard):
		guard = _HG.new()
		guard.name = "EnemyHomeGuard"
		main.add_child(guard)
		guard.setup(main, castle)
		main.enemy_guard = guard
	var front: Vector3 = castle.front_dir()
	var post: Vector3 = GameManager.land_target(castle.global_position + front * 18.0)
	# Сетка _squad: колонки по +X с шагом 0.65, ряды по +Z — те же оси отдаём
	# посту (side = RIGHT, front = FORWARD: post_spot кладёт ряды в -front = +Z)
	var r: Array = _squad("spearman", post, 24, 6)
	var sid: int = r[0]
	var men: Array = r[1]
	await pframes(2)
	guard.adopt(sid, post, 6, 0.65, Vector3.FORWARD, Vector3.RIGHT)
	verdict("G0 усыновлённый на посту отряд спит сразу", guard.is_asleep(sid))
	var rec: Dictionary = {}
	for s in guard.squads:
		if int((s as Dictionary)["sid"]) == sid:
			rec = s
	var far_dist := 14.0
	var scatter := func() -> void:
		guard._set_sleep(sid, false)
		for i in range(8):
			var u: Unit = men[i]
			var p: Vector3 = post + Vector3.RIGHT * far_dist + Vector3(0.0, 0.0, 0.65 * float(i))
			u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
			u.sync_row()
			u.post_pos = u.global_position
			u.state = Unit.State.IDLE
		rec["gather_ms"] = 0
		rec["home_ms"] = 0
	var max_off := func() -> float:
		var worst := 0.0
		for k in range(men.size()):
			var u: Unit = men[k]
			var p: Vector3 = guard.post_spot(rec, k)
			worst = maxf(worst, Vector2(u.global_position.x - p.x, u.global_position.z - p.z).length())
		return worst
	var tick_frames: int = int(_AICfg.HOME_GUARD_TICK_SEC * 60.0) + 5
	# G1: ручка выключена — центр «дома», отряд засыпает с восемью бойцами в 14 м
	_Opt.guard_sleep_gathered = false
	scatter.call()
	guard.set_process(true)
	await pframes(tick_frames * 3)
	verdict("G1 ручка выкл: отряд уснул по центру, хотя 8 бойцов стоят в %.0f м от мест (прежнее поведение)" % far_dist,
		guard.is_asleep(sid) and max_off.call() > far_dist - 2.0, "спит %s, дальний от места %.1f м" % [str(guard.is_asleep(sid)), max_off.call()])
	# G2-G3: ручка включена — отставшие получают приказ на место, сон после сбора
	_Opt.guard_sleep_gathered = true
	scatter.call()
	await pframes(tick_frames * 3)
	var moving := 0
	for i in range(8):
		var u: Unit = men[i]
		if u.state == Unit.State.MOVING or absf(u.global_position.x - post.x) < far_dist - 3.0:
			moving += 1
	verdict("G2 ручка вкл: через три такта отряд не спит, отставшие идут на места",
		not guard.is_asleep(sid) and moving >= 6, "спит %s, идут/пришли %d из 8" % [str(guard.is_asleep(sid)), moving])
	var slept := false
	for _w in range(900):
		await pframes(1)
		if guard.is_asleep(sid):
			slept = true
			break
	verdict("G3 собрались у мест (каждый ближе %.1f м) — отряд уснул" % _AICfg.HOME_GUARD_GATHER_R,
		slept and max_off.call() <= _AICfg.HOME_GUARD_GATHER_R + 0.5, "спит %s, дальний от места %.1f м" % [str(slept), max_off.call()])
	# G4: не собрались за HOME_GUARD_GATHER_SEC — спят как есть (отставшие заморожены)
	scatter.call()
	for i in range(8):
		(men[i] as Unit).set_tick(false)
	rec["gather_ms"] = Unit.game_ms() - int(_AICfg.HOME_GUARD_GATHER_SEC * 1000.0) - 1000
	await pframes(tick_frames * 3)
	verdict("G4 срок сбора вышел — отряд спит и с отставшими (охрана не бодрствует вечно)",
		guard.is_asleep(sid), "спит %s, дальний от места %.1f м" % [str(guard.is_asleep(sid)), max_off.call()])
	for i in range(8):
		(men[i] as Unit).set_tick(true)
	guard._set_sleep(sid, false)
	guard.squads.erase(rec)
	GameManager.squad_set_home_guard(sid, false)
	_kill_all()
	await pframes(3)
