extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_red_tactics — ЭКОНОМИКА И ТАКТИКА КРАСНОГО ИИ (ТЗ 30.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A — экономика на живой карте (RedEconomy, ручка ai_eco_v2): красному дают
##       барак/кузницу/стрелковую, золото и дерево, еды 40 — за ~3 игровые
##       минуты он ставит загон с фермерами, закладывает рынок, покупает на нём
##       еду, нанимает рабочих сверх старого пола и учится в кузнице, пока
##       идёт стройка. `eco=0` — тот же прогон с ручкой выключенной (A0).
##   B — перегруппировка после боя (ai_regroup): четыре отряда поля
##       рассыпаны, бой кончился — сбор кирпичами у медианы, лучники позади,
##       по окончании сбора приказ снимается; враг рядом — сбора нет;
##       ручка выключена — отряды идут к целям плана россыпью.
##   C — корпус по сигналу (ai_corps): патруль дерётся с игроком в 50 м от
##       рубежа — заслон встаёт кирпичами перед стычкой, радиус контратаки
##       сужен до CORPS_ENGAGE_R.
##   D — клещи штурма (ai_pincer): волна из 8 отрядов — крылья с обеих
##       сторон, за краем чужого фронта, обходят бегом, потом в тыл.
##   E — опорная точка (ai_strongpoint): рудничная группа стоит у цели — вышка
##       за линией, лучники группы на неё.
## Запуск: godot --headless --path . res://qa_red_tactics/Test.tscn [-- only=abcde eco=0]

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")
const R := Constants.FACTION_ENEMY
const P := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

var main = null
var ai = null
var castle: Castle = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abcde"
var _eco_on := true
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		if String(a) == "eco=0":
			_eco_on = false
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 900 с")
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
	Engine.time_scale = 1.0
	print("\n═════ ИТОГ qa_red_tactics: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

var _mine: Array = []
func _unit(uid: String, at: Vector3, fac: int = R) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	_mine.append(u)
	return u

## Отряд реестра; spread > 0 — бойцы разбросаны в круге этого радиуса
func _squad(uid: String, at: Vector3, n: int, fac: int = R, spread: float = 0.0) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	var cols := 6
	for i in range(n):
		var p: Vector3 = at + Vector3((float(i % cols) - float(cols - 1) * 0.5) * 0.65, 0.0, float(i / cols) * 0.65)
		if spread > 0.0:
			var a: float = float(i) * 2.399
			var r: float = spread * sqrt(float(i + 1) / float(n))
			p = at + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var u: Unit = _unit(uid, p, fac)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _group(uid: String, men: Array, role: String, target: Vector3) -> Dictionary:
	var sq := {
		"type": uid, "members": men.duplicate(), "role": role,
		"target": target, "issued": false,
		"flank_side": 0, "flank_close": false, "peak": men.size(),
	}
	ai.squads.append(sq)
	return sq

func _kill_all() -> void:
	for u in _mine:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e12)
	_mine.clear()
	ai.squads.clear()

func _spread(men: Array) -> float:
	var live: Array = []
	for m in men:
		if is_instance_valid(m) and not (m as Unit).is_dead():
			live.append(m)
	if live.is_empty():
		return 0.0
	var c: Vector3 = GameManager._centroid_of(live)
	var worst := 0.0
	for m2 in live:
		worst = maxf(worst, Vector2((m2 as Node3D).global_position.x - c.x, (m2 as Node3D).global_position.z - c.z).length())
	return worst

## Ровная сухая площадка в поле, подальше от баз
func _field_spot(near: Vector3) -> Vector3:
	for r in [0.0, 20.0, 40.0, 60.0]:
		for k in range(8):
			var a: float = float(k) * TAU / 8.0
			var p: Vector3 = near + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var ok := true
			for dx in [-25.0, 0.0, 25.0]:
				for dz in [-25.0, 0.0, 25.0]:
					if GameManager.is_water(p.x + dx, p.z + dz) or not GameManager.is_passable(p.x + dx, p.z + dz):
						ok = false
			if ok:
				return GameManager.land_target(p)
	return GameManager.land_target(near)

func _clear(c: Vector3, r: float) -> void:
	main._clear_trees(c, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(c) < r and not (u is Worker):
				u.queue_free()

func _run() -> void:
	seed(3010)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd"]:
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
	if castle == null:
		verdict("0 крепость красного есть", false)
		_finish()
		return
	if "a" in _only:
		await _a_economy()
	main.enemy_ai.set_process(false)
	if "b" in _only: await _b_regroup()
	if "c" in _only: await _c_corps()
	if "d" in _only: _d_pincer()
	if "e" in _only: await _e_strongpoint()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ЭКОНОМИКА
# ═════════════════════════════════════════════════════════════════════════════
func _count_bld(id: String) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and (b as Building).building_id == id and not (b as Building).is_dead():
			n += 1
	for s in get_tree().get_nodes_in_group("construction_sites"):
		if is_instance_valid(s) and (s as Building).faction == R and String(s.target_id) == id:
			n += 1
	return n

func _workers() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(n) and n is Worker and not (n as Worker).is_dead():
			out.append(n)
	return out

func _place(id: String, off: Vector2) -> void:
	if _count_bld(id) > 0:
		return
	var f: Vector3 = castle.front_dir()
	var sd := Vector3(-f.z, 0.0, f.x)
	var b: Building = _CSite.make_building(id)
	b.faction = R
	main.world_add(b)
	b.global_position = GameManager.land_target(castle.global_position + f * off.x + sd * off.y)

func _a_economy() -> void:
	var tag: String = "A" if _eco_on else "A0"
	print("\n═════ %s. Экономика красного (ai_eco_v2=%s) ═════" % [tag, str(_eco_on)])
	_Opt.ai_eco_v2 = _eco_on
	_place("barracks", Vector2(2.0, 8.0))
	_place("smithy", Vector2(2.0, -8.0))
	_place("archery", Vector2(2.0, 16.0))
	await pframes(5)
	ResourceManager.set_amount(R, Constants.RESOURCE_WOOD, 6000.0)
	ResourceManager.set_amount(R, Constants.RESOURCE_GOLD, 6000.0)
	ResourceManager.set_amount(R, Constants.RESOURCE_STONE, 2500.0)
	ResourceManager.set_amount(R, Constants.RESOURCE_FOOD, 40.0)
	ai._peace_over = true
	var w0: int = _workers().size()
	var floor_n: int = _AICfg.AI_WORKER_FLOOR
	print("  рабочих на старте %d (пол старого найма %d)" % [w0, floor_n])
	Engine.time_scale = 3.0
	var t0: float = ai.clock
	var site_seen := false
	var forge_during_site := false
	var food_min := 1.0e9
	var wmax := w0
	while ai.clock - t0 < 200.0:
		await pframes(30)
		if ai._sites_count() > 0:
			site_seen = true
			if ai.eco.forge_starts > 0:
				forge_during_site = true
		wmax = maxi(wmax, _workers().size())
		food_min = minf(food_min, ResourceManager.get_amount(R, Constants.RESOURCE_FOOD))
	Engine.time_scale = 1.0
	var farmers := 0
	for w in _workers():
		if (w as Worker).farm_pen() != null:
			farmers += 1
	var pens: int = ai.eco.pens().size()
	var mk: int = _count_bld("market")
	var food: float = ResourceManager.get_amount(R, Constants.RESOURCE_FOOD)
	print("  %s: за %.0f с — загонов %d, фермеров %d, рынок %d, сделок %d (еды куплено %.0f), еда сейчас %.0f; рабочих %d → %d (пик %d); складов %d; кузница стартов %d (во время стройки: %s); последнее: %s" % [
		tag, ai.clock - t0, pens, farmers, mk, ai.eco.trades, ai.eco.food_bought, food, w0, _workers().size(), wmax,
		_count_bld("storehouse"), ai.eco.forge_starts, str(forge_during_site), ai.last_action])
	if _eco_on:
		verdict("A1 поставлен загон и на нём фермеры: загонов %d, фермеров %d" % [pens, farmers], pens >= 1 and farmers >= 2)
		verdict("A2 заложен рынок: %d" % mk, mk >= 1)
		verdict("A3 рынок покупает еду: сделок %d, еды %.0f" % [ai.eco.trades, ai.eco.food_bought], ai.eco.food_bought > 0.0)
		verdict("A4 рабочих нанято сверх пола старого найма: пик %d > %d" % [wmax, floor_n], wmax > floor_n)
		verdict("A5 кузница учится, не дожидаясь конца строек: стартов %d, во время стройки %s" % [ai.eco.forge_starts, str(forge_during_site)],
			ai.eco.forge_starts > 0 and (forge_during_site or not site_seen))
	else:
		verdict("A0 ручка ai_eco_v2=false: ни загона, ни рынка, ни сделок (загонов %d, рынок %d, сделок %d)" % [pens, mk, ai.eco.trades],
			pens == 0 and mk == 0 and ai.eco.trades == 0)
	_Opt.ai_eco_v2 = true

# ═════════════════════════════════════════════════════════════════════════════
# B. ПЕРЕГРУППИРОВКА ПОСЛЕ БОЯ
# ═════════════════════════════════════════════════════════════════════════════
## Такт ИИ без экономики и стройки: отметки боя, роли не трогаем, раздача
func _ai_tick() -> void:
	ai.tac.tick()
	ai._apply_orders()

func _run_ai(sec: float, until: Callable = Callable()) -> float:
	var t := 0.0
	var acc := 0.0
	while t < sec:
		await pframes(1)
		var d: float = 1.0 / float(Engine.physics_ticks_per_second)
		t += d
		acc += d
		ai.clock += d
		ai._drain_orders()
		if acc >= _AICfg.THINK_INTERVAL:
			acc = 0.0
			_ai_tick()
			if until.is_valid() and bool(until.call()):
				break
	return t

func _b_regroup() -> void:
	print("\n═════ B. Перегруппировка после боя ═════")
	var spot: Vector3 = _field_spot((castle.global_position + ai._player_base_pos()) * 0.5)
	_clear(spot, 60.0)
	await pframes(3)
	ai._peace_over = true
	for knob in [true, false]:
		_Opt.ai_regroup = knob
		_kill_all()
		await pframes(3)
		var base: Vector3 = ai._player_base_pos()
		var face := Vector3(base.x - spot.x, 0.0, base.z - spot.z).normalized()
		var right := Vector3(-face.z, 0.0, face.x)
		var kinds := ["spearman", "spearman", "archer", "warrior"]
		var offs := [right * -14.0 + face * 6.0, right * 12.0 + face * 9.0, right * 3.0 - face * 4.0, right * -4.0 + face * 14.0]
		var groups: Array = []
		var all: Array = []
		for i in range(kinds.size()):
			var s: Array = _squad(kinds[i], spot + offs[i], 20, R, 7.0)
			# Цель плана — далеко вперёд: без сбора отряды пошли бы туда россыпью
			var g: Dictionary = _group(kinds[i], s[1], "field", GameManager.land_target(spot + face * 60.0 + right * (float(i) - 1.5) * 8.0))
			groups.append(g)
			all.append_array(s[1])
		await pframes(5)
		var now: float = ai.clock
		for g2 in groups:
			(g2 as Dictionary)["fight_t"] = now - _AICfg.RG_QUIET_SEC - 1.0
			(g2 as Dictionary)["fight_p"] = spot + face * 10.0
		var sp0: Array = []
		for g3 in groups:
			sp0.append(snappedf(_spread(g3["members"]), 0.1))
		var rg0: int = ai.tac.regroups
		var done0: int = ai.tac.regroups_done
		var c_start: Vector3 = GameManager._centroid_of(all)
		var posts: Array = []
		var had_id: Array = [0]
		var waited: float = await _run_ai(_AICfg.RG_MAX_SEC + 6.0, func():
			if posts.is_empty() and int(groups[0].get("rg_id", 0)) > 0:
				for g4 in groups:
					posts.append(g4["rg_post"])
					had_id[0] += 1 if int(g4.get("rg_id", 0)) > 0 else 0
			return ai.tac.regroups_done > done0)
		var sp1: Array = []
		var post_err := 0.0
		for gi in range(groups.size()):
			sp1.append(snappedf(_spread(groups[gi]["members"]), 0.1))
			if not posts.is_empty():
				var c: Vector3 = ai._squad_centroid(groups[gi]["members"])
				post_err = maxf(post_err, Vector2(c.x - (posts[gi] as Vector3).x, c.z - (posts[gi] as Vector3).z).length())
		var c_end: Vector3 = GameManager._centroid_of(all)
		var moved: float = (c_end - c_start).dot(face)
		print("  [%s] сборов %d (отрядов с местом %d), завершено %d за %.1f с; разброс отрядов %s → %s м; дальше всех от места %.1f м; центр войска ушёл вперёд на %.1f м" % [
			"вкл" if knob else "выкл", ai.tac.regroups - rg0, int(had_id[0]), ai.tac.regroups_done - done0, waited, str(sp0), str(sp1), post_err, moved])
		if knob:
			verdict("B1 конец боя объявлен: сбор всем четырём отрядам", ai.tac.regroups - rg0 == 1 and int(had_id[0]) == 4, "отрядов %d" % int(had_id[0]))
			var bow_back := false
			if posts.size() == 4:
				var proj: Array = []
				for p4 in posts:
					proj.append(((p4 as Vector3) - spot).dot(face))
				bow_back = float(proj[2]) < minf(minf(float(proj[0]), float(proj[1])), float(proj[3])) - 1.0
			verdict("B2 лучники в кирпиче позади пехоты", bow_back)
			var tight := true
			for v in sp1:
				tight = tight and float(v) <= 4.5
			verdict("B3 отряды собрались кирпичами у мест: разброс ≤ 4.5 м (%s), до места ≤ %.1f м (%.1f)" % [str(sp1), _AICfg.RG_ARRIVE_M, post_err],
				tight and post_err <= _AICfg.RG_ARRIVE_M)
			var cleared := true
			for g5 in groups:
				cleared = cleared and not (g5 as Dictionary).has("rg_id")
			verdict("B4 сбор завершён построением, приказ снят (новый анализ целей)", ai.tac.regroups_done > done0 and cleared)
			verdict("B5 во время сбора войско не ушло к целям плана: %.1f м вперёд" % moved, absf(moved) < 8.0)
		else:
			verdict("B0 ручка ai_regroup=false: сбора нет, отряды идут к целям плана (%.1f м вперёд)" % moved,
				ai.tac.regroups == rg0 and moved > 10.0)
	_Opt.ai_regroup = true
	# B6: враг рядом — бой не кончился, сбора нет
	_kill_all()
	await pframes(3)
	var s6: Array = _squad("spearman", spot, 20, R, 7.0)
	var g6: Dictionary = _group("spearman", s6[1], "field", spot)
	var foe: Array = _squad("goblin_spearman", spot + Vector3(14.0, 0, 0), 10, G)
	for f in foe[1]:
		(f as Unit).set_tick(false)
	await pframes(5)
	g6["fight_t"] = ai.clock - _AICfg.RG_QUIET_SEC - 1.0
	g6["fight_p"] = spot
	var rg6: int = ai.tac.regroups
	ai.tac.tick()
	verdict("B6 враг в %.0f м — сбора нет (бой не кончился)" % _AICfg.RG_SCAN_R, ai.tac.regroups == rg6)
	_kill_all()
	await pframes(5)

# ═════════════════════════════════════════════════════════════════════════════
# C. КОРПУС ПО СИГНАЛУ
# ═════════════════════════════════════════════════════════════════════════════
func _c_corps() -> void:
	print("\n═════ C. Корпус по сигналу ═════")
	_kill_all()
	await pframes(3)
	var center: Vector3 = ai._defense_center(castle)
	var course: Vector3 = ai._defense_course(castle)
	var right := Vector3(-course.z, 0.0, course.x)
	var line: Array = []
	for i in range(4):
		var uid: String = "archer" if i == 3 else "spearman"
		var s: Array = _squad(uid, GameManager.land_target(center + right * (float(i) - 1.5) * 9.0), 20)
		line.append(_group(uid, s[1], ai.ROLE_LINE, (s[1][0] as Node3D).global_position))
	var pp: Vector3 = GameManager.land_target(center + course * 22.0 + right * 45.0)
	var dist: float = Vector2(pp.x - center.x, pp.z - center.z).length()
	var ps: Array = _squad("spearman", pp, 12)
	var patrol: Dictionary = _group("spearman", ps[1], ai.ROLE_PATROL, pp)
	var foe: Array = _squad("spearman", pp + right * 2.5, 12, P)
	await pframes(90)
	var sig0: int = ai.tac.corps_signals
	ai.tac.tick()
	ai.tac.assign_corps(line, center)
	var ok_sig: bool = ai.tac.corps_signals > sig0 and ai.tac.corps_active()
	var near := 0
	var radius_ok := true
	for sq in line:
		var t: Vector3 = sq["target"]
		if Vector2(t.x - pp.x, t.z - pp.z).length() < _AICfg.CORPS_STANDOFF + 14.0:
			near += 1
		radius_ok = radius_ok and is_equal_approx(ai.tac.engage_radius(sq), _AICfg.CORPS_ENGAGE_R)
	var bow_t: Vector3 = line[3]["target"]
	var bow_d: float = Vector2(bow_t.x - pp.x, bow_t.z - pp.z).length()
	var sp_d := INF
	for k in range(3):
		var t2: Vector3 = line[k]["target"]
		sp_d = minf(sp_d, Vector2(t2.x - pp.x, t2.z - pp.z).length())
	print("  стычка патруля в %.0f м от рубежа: сигналов %d, заслона у стычки %d из 4, лучники %.1f м / пехота %.1f м от стычки" % [
		dist, ai.tac.corps_signals - sig0, near, bow_d, sp_d])
	verdict("C1 стычка патруля — сигнал корпусу", ok_sig, "дистанция %.0f м" % dist)
	verdict("C2 заслон встал перед стычкой: %d из 4" % near, near == 4)
	verdict("C3 лучники позади пехоты (%.1f > %.1f м)" % [bow_d, sp_d], bow_d > sp_d + 1.0)
	verdict("C4 корпус держит место: радиус контратаки %.0f м" % _AICfg.CORPS_ENGAGE_R, radius_ok)
	_Opt.ai_corps = false
	ai.tac.reset()
	ai.tac.tick()
	ai.tac.assign_corps(line, center)
	verdict("C0 ручка ai_corps=false: сигнала нет", ai.tac.corps_signals == 0 and not ai.tac.corps_active())
	_Opt.ai_corps = true
	ai.tac.reset()
	for u in foe[1]:
		_mine.append(u)
	_kill_all()
	await pframes(5)

# ═════════════════════════════════════════════════════════════════════════════
# D. КЛЕЩИ ШТУРМА
# ═════════════════════════════════════════════════════════════════════════════
func _d_pincer() -> void:
	print("\n═════ D. Клещи штурма ═════")
	var target := Vector3(0, 0, 0)
	var course := Vector3(0, 0, 1)
	var right := Vector3(-course.z, 0.0, course.x)
	for knob in [true, false]:
		_Opt.ai_pincer = knob
		var plan: Array = []
		var kinds := ["spearman", "spearman", "warrior", "spearman", "archer", "spearman", "warrior", "archer"]
		for i in range(kinds.size()):
			var sq := {"type": kinds[i], "members": [], "role": "assault", "target": Vector3.ZERO, "issued": false}
			var off: float = (float(i) - 3.5) * 7.0
			plan.append([sq, target + right * off, kinds[i]])
		ai.tac.pincer(plan, target, course, target - course * 60.0)
		var wings_l := 0
		var wings_r := 0
		var bows_wing := 0
		var far_ok := true
		var half := 0.0
		for p in plan:
			if not (p[0] as Dictionary).has("wing"):
				half = maxf(half, absf((p[1] as Vector3).dot(right)))
		for p2 in plan:
			var sq2: Dictionary = p2[0]
			if not sq2.has("wing"):
				continue
			if float(sq2["wing"]) < 0.0: wings_l += 1
			else: wings_r += 1
			if String(sq2["type"]) == "archer":
				bows_wing += 1
			var lat: float = (p2[1] as Vector3).dot(right) * float(sq2["wing"])
			far_ok = far_ok and lat > half + 10.0 and ai.tac.wing_role(sq2, "assault") == ai.ROLE_FLANK
		print("  [%s] крыльев слева %d, справа %d (лучников в крыльях %d), полуфронт центра %.1f м" % [
			"вкл" if knob else "выкл", wings_l, wings_r, bows_wing, half])
		if knob:
			verdict("D1 крылья с обеих сторон, лучники в центре", wings_l >= 1 and wings_r >= 1 and bows_wing == 0)
			verdict("D2 крыло бежит за край чужого фронта (обход, ROLE_FLANK)", far_ok)
			# Крыло дошло до внешней точки — следующий такт ведёт его в тыл
			var w: Array = []
			for p3 in plan:
				if (p3[0] as Dictionary).has("wing"):
					w = p3
					break
			var sqw: Dictionary = w[0]
			var outer: Vector3 = w[1]
			var men: Array = _squad("warrior", GameManager.land_target(outer), 6)[1]
			sqw["members"] = men
			ai.tac.pincer(plan, target, course, target - course * 60.0)
			var rear: Vector3 = w[1]
			verdict("D3 дошедшее крыло идёт в тыл: %.1f м за фронтом, роль штурма" % rear.dot(course),
				rear.dot(course) > _AICfg.PINCER_DEEP * 0.5 and ai.tac.wing_role(sqw, "assault") == "assault")
			for u in men:
				if is_instance_valid(u): (u as Unit).take_damage(1.0e12)
		else:
			verdict("D0 ручка ai_pincer=false: крыльев нет", wings_l + wings_r == 0)
	_Opt.ai_pincer = true

# ═════════════════════════════════════════════════════════════════════════════
# E. ОПОРНАЯ ТОЧКА
# ═════════════════════════════════════════════════════════════════════════════
func _e_strongpoint() -> void:
	print("\n═════ E. Опорная точка: вышка и лучники ═════")
	ResourceManager.set_amount(R, Constants.RESOURCE_WOOD, 6000.0)
	ResourceManager.set_amount(R, Constants.RESOURCE_GOLD, 6000.0)
	ResourceManager.set_amount(R, Constants.RESOURCE_STONE, 3000.0)
	for knob in [false, true]:
		_Opt.ai_strongpoint = knob
		_kill_all()
		ai.tac.reset()
		await pframes(3)
		var t: Vector3 = _field_spot(castle.global_position + castle.front_dir() * 55.0)
		_clear(t, 25.0)
		var sp: Array = _squad("spearman", t, 20)
		_group("spearman", sp[1], ai.ROLE_MINE, t)
		var bw: Array = _squad("archer", t - castle.front_dir() * 5.0, 12)
		var gb: Dictionary = _group("archer", bw[1], ai.ROLE_MINE, (bw[1][0] as Node3D).global_position)
		await pframes(5)
		var sites0: int = ai._sites_count("tower")
		ai.tac.build_step(castle, 3)
		var early: int = ai._sites_count("tower") - sites0
		ai.clock += _AICfg.SP_HOLD_SEC + 1.0
		ai.tac.build_step(castle, 3)
		var laid: int = ai._sites_count("tower") - sites0
		var site: Node3D = null
		for s in get_tree().get_nodes_in_group("construction_sites"):
			if is_instance_valid(s) and (s as Building).faction == R and String(s.target_id) == "tower" \
					and (s as Node3D).global_position.distance_to(t) < 25.0:
				site = s
		print("  [%s] до срока вышек %d, после срока %d%s" % ["вкл" if knob else "выкл", early, laid,
			(", вышка в %.1f м от точки" % site.global_position.distance_to(t)) if site != null else ""])
		if not knob:
			verdict("E0 ручка ai_strongpoint=false: вышки нет", laid == 0)
			continue
		verdict("E1 группа простояла срок — вышка заложена у точки", early == 0 and laid == 1 and site != null)
		if site == null:
			continue
		# Достроить сразу и посадить лучников
		var pos: Vector3 = site.global_position
		site.queue_free()
		var tw: Building = _CSite.make_building("tower")
		tw.faction = R
		main.world_add(tw)
		tw.global_position = pos
		await pframes(5)
		ai.tac.build_step(castle, 3)
		var bsid: int = ai._sid_of(gb)
		var going: bool = tw._incoming.has(bsid) or tw.call("has_garrison")
		verdict("E2 лучники группы идут на вышку", going and ai.tac.sp_garrisons >= 1)
		tw.take_damage(1.0e12)
	_Opt.ai_strongpoint = true
	_kill_all()
	await pframes(5)
