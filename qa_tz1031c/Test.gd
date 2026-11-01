extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tz1031c — ВХОД ОРДЫ ИЗ-ЗА КРОМКИ, ПЛАШКА ЛАГЕРЯ (ТЗ 31.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ВХОД — отряд орды, заказанный посреди карты, рождается у кромки: на
##          проходимой сухой земле, вне обзора игрока, на том же берегу, без
##          чужих рядом; маршем доходит до своей точки; усыплённый в пути
##          засыпает по прибытии; охрана рудника (enter=false) — на месте;
##          ручка horde_edge_entry=false — прежний спавн на точке (A0).
##   C ПРИВАЛЫ — волна к базе игрока идёт этапами: выход с базы, подступ к
##          броду, за бродом; на привале отряды собираются блоком (центры
##          врозь, конница сзади) и спят; ручка wave_stages=false — без
##          привалов (C0).
##   D ДОЗЫ — на развёртывании в бой идёт по отряду на каждый чужой (туши
##          на копейщиков), остальные в резерве; лишний — во фланг; просевший
##          заменяется свежим; ослабший чужой — конница в брешь; ручка
##          wave_feed=false — все разом (D0).
##   B ПЛАШКА — разгром лагеря орды не показывает «Лагерь орды уничтожен»
##          (ручка horde_defeat_notice=true возвращает её — B0).
## Запуск: godot --headless --path . res://qa_tz1031c/Test.tscn [-- only=ab]

const _Opt := preload("res://scripts/perf_config.gd")
const _Spawn := preload("res://scripts/spawn_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const G := Constants.FACTION_GOBLIN

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only: String = "acdb"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 900 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_tz1031c: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	# Чужие на пути — цели (замороженный остаётся в сетке, ловушка стендов):
	# отряд ввязался бы в бой и честно снял бы вход. Площадку чистим
	for n in get_tree().get_nodes_in_group("all_units"):
		var wu := n as Unit
		if wu != null and wu.faction != Constants.FACTION_PLAYER and not wu.is_dead():
			wu.take_damage(1e12)
	await pframes(4)
	if "a" in _only: await _block_a()
	if "c" in _only: await _block_c()
	if "d" in _only: await _block_d()
	if "b" in _only: await _block_b()
	_finish()

func _alive(sid: int) -> Array:
	var out: Array = []
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return out
	for m in (raw as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _kill(sid: int) -> void:
	for m in _alive(sid):
		(m as Unit).take_damage(1e12)

func _edge_gap(p: Vector3) -> float:
	return minf(GameManager.map_lim_x - absf(p.x), GameManager.map_lim_z - absf(p.z))

func _centre(us: Array) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for u in us:
		xs.append((u as Unit).global_position.x)
		zs.append((u as Unit).global_position.z)
	if xs.is_empty():
		return Vector3.INF
	xs.sort()
	zs.sort()
	return Vector3(xs[xs.size() / 2], 0.0, zs[zs.size() / 2])

## Посреди карты, на сухой проходимой земле: здесь орде рождаться нельзя
func _mid_spot() -> Vector3:
	for r in [0.0, 10.0, 20.0, 30.0]:
		for a in range(8):
			var p := Vector3(cos(a * 0.785) * r + 20.0, 0.0, sin(a * 0.785) * r)
			if GameManager.is_passable(p.x, p.z) and not GameManager.is_water(p.x, p.z):
				return GameManager.land_target(p)
	return GameManager.land_target(Vector3(20.0, 0.0, 0.0))

# ═════════════════════════════════════════════════════════════════════════════
# A. ВХОД ИЗ-ЗА КРОМКИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. ВХОД ОРДЫ ИЗ-ЗА КРОМКИ ═════")
	var fog = main.fog
	if fog != null:
		fog.enabled = true
		fog.refresh()
	await pframes(4)
	var goal: Vector3 = _mid_spot()
	var n: int = 12
	var pad: float = _GobCfg.horde_radius(n) + _Spawn.HORDE_ENTRY_PAD
	var sid: int = int(main.spawn_goblin_squad("goblin_spearman", n, goal))
	var men: Array = _alive(sid)
	var entry: Vector3 = (GameManager.squads[sid] as Dictionary).get("entry", Vector3.INF)
	var c0: Vector3 = _centre(men)
	var lit := 0
	var dry := 0
	var on_edge := 0
	var going := 0
	for m in men:
		var u := m as Unit
		var p: Vector3 = u.global_position
		if fog != null and fog.is_lit(p.x, p.z):
			lit += 1
		if GameManager.is_passable(p.x, p.z) and not GameManager.is_water(p.x, p.z):
			dry += 1
		if _edge_gap(p) <= pad * 2.0 + 2.0:
			on_edge += 1
		if u.horde_entering and u.state == Unit.State.MOVING and u.horde_goal.distance_to(goal) < pad + 2.0:
			going += 1
	print("  точка заказа (%.0f, %.0f), вход (%.0f, %.0f), до цели %.0f м" % [goal.x, goal.z, entry.x, entry.z,
		Vector2(c0.x - goal.x, c0.z - goal.z).length()])
	verdict("A1 отряд родился у кромки, а не на точке заказа посреди карты (%d из %d у кромки)" % [on_edge, men.size()],
		entry.is_finite() and on_edge == men.size() and Vector2(c0.x - goal.x, c0.z - goal.z).length() > 30.0)
	verdict("A2 на проходимой сухой земле (%d из %d), вне обзора игрока (освещено %d)" % [dry, men.size(), lit],
		dry == men.size() and lit == 0)
	verdict("A3 тот же берег, что у точки заказа",
		main.river_side(entry) == 0 or main.river_side(goal) == 0 or main.river_side(entry) == main.river_side(goal))
	verdict("A4 все идут маршем к своей точке (%d из %d)" % [going, men.size()], going == men.size())
	# Марш и сон по прибытии
	main.goblin_ai._sleep_squad(sid)
	var awake := 0
	for m in men:
		if not (m as Unit).dormant:
			awake += 1
	verdict("A6 усыплённый в пути не засыпает у кромки (бодрствуют %d из %d)" % [awake, men.size()],
		awake == men.size())
	var g := 0
	var arrived := false
	while g < 60 * 120:
		await get_tree().physics_frame
		g += 1
		if g % 600 == 0:
			var st: Dictionary = {}
			for m in _alive(sid):
				var k: String = "%d%s" % [(m as Unit).state, "z" if (m as Unit).dormant else ""]
				st[k] = int(st.get(k, 0)) + 1
			var cc: Vector3 = _centre(_alive(sid))
			print("    t=%d: состояния %s, центр (%.0f, %.0f)" % [g / 60, str(st), cc.x, cc.z])
		if g % 30 == 0:
			var c: Vector3 = _centre(_alive(sid))
			if c.is_finite() and Vector2(c.x - goal.x, c.z - goal.z).length() < pad + 3.0:
				var still := 0
				for m in _alive(sid):
					if (m as Unit).horde_entering:
						still += 1
				if still == 0:
					arrived = true
					break
	await pframes(_Spawn.HORDE_ENTRY_TICK + 2)
	var c1: Vector3 = _centre(_alive(sid))
	var slept := 0
	for m in _alive(sid):
		if (m as Unit).dormant:
			slept += 1
	verdict("A7 отряд дошёл до точки заказа (центр в %.1f м, %d физкадров)" % [
		Vector2(c1.x - goal.x, c1.z - goal.z).length(), g], arrived)
	verdict("A8 дошедший усыплённый спит (%d из %d)" % [slept, _alive(sid).size()],
		slept == _alive(sid).size() and slept > 0)
	_kill(sid)
	await pframes(3)
	# Чужие у кромки отталкивают вход: ставим своих бойцов на прежнюю точку входа
	var pl: Array = []
	var ps: PackedScene = Building.PRELOAD_SCENES.get("spearman")
	var psid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for k in range(6):
		var u: Unit = ps.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main._world.add_child(u)
		u.global_position = entry + Vector3(float(k) * 0.8, 0.0, 0.0)
		u.sync_row()
		GameManager.add_to_squad(psid, u)
		u.set_tick(false)
		pl.append(u)
	await pframes(4)
	var e2: Vector3 = main.horde_entry_point(goal, n)
	verdict("A5 вход не рядом с чужими: новый в %.0f м от бойцов на прежнем" % e2.distance_to(entry),
		e2.is_finite() and Vector2(e2.x - entry.x, e2.z - entry.z).length() >= _Spawn.HORDE_ENTRY_CLEAR_R - 1.0)
	for u in pl:
		(u as Unit).take_damage(1e12)
	# Охрана рудника и стартовый резерв — на месте
	var sid2: int = int(main.spawn_goblin_squad("gnoll", n, goal, false, 0, false))
	var c2: Vector3 = _centre(_alive(sid2))
	verdict("A9 enter=false (охрана рудника) рождается на своей точке (%.1f м)" % Vector2(c2.x - goal.x, c2.z - goal.z).length(),
		Vector2(c2.x - goal.x, c2.z - goal.z).length() < pad + 1.0)
	_kill(sid2)
	await pframes(3)
	# Настоящий пень: гноллы входят из-за кромки, пост — у пня, а не у кромки
	var lair = GameManager.nearest_lair(goal)
	if lair != null and is_instance_valid(lair):
		var fr0: bool = bool(lair.get("frozen"))
		lair.set("frozen", false)
		# Гноллы пня выходят из самого пня (ТЗ 31.10.2026, lair_spawn_at_lair) —
		# вход из-за кромки проверяется с ручкой снятой
		var sal0: bool = _Opt.lair_spawn_at_lair
		_Opt.lair_spawn_at_lair = false
		var before: int = (lair.get("gnoll_squads") as Array).size()
		lair.call("spawn_gnoll_squads", 1)
		var gs: Array = lair.get("gnoll_squads")
		var ok_l := false
		var info := "отряд не родился"
		if gs.size() > before:
			var gsid: int = int(gs[gs.size() - 1])
			var gm: Array = _alive(gsid)
			var lp: Vector3 = (lair as Node3D).global_position
			var far := 0
			var post_ok := 0
			for m in gm:
				var u := m as Unit
				if _edge_gap(u.global_position) <= pad * 2.0 + 2.0:
					far += 1
				if Vector2(u.post_pos.x - lp.x, u.post_pos.z - lp.z).length() < _GobCfg.GNOLL_PATROL_RADIUS:
					post_ok += 1
			ok_l = not gm.is_empty() and far == gm.size() and post_ok == gm.size()
			var en: Vector3 = (GameManager.squads[gsid] as Dictionary).get("entry", Vector3.INF)
			info = "у кромки %d из %d, пост у пня %d; пень (%.0f, %.0f), вход (%.0f, %.0f)" % [far, gm.size(), post_ok,
				lp.x, lp.z, en.x, en.z]
			_kill(gsid)
		verdict("A10 гноллы пня входят из-за кромки, пост — у пня (%s)" % info, ok_l)
		lair.set("frozen", fr0)
		_Opt.lair_spawn_at_lair = sal0
		await pframes(3)
	# Ручка выключена — прежний спавн
	_Opt.horde_edge_entry = false
	var sid3: int = int(main.spawn_goblin_squad("gnoll", n, goal))
	var c3: Vector3 = _centre(_alive(sid3))
	verdict("A0 horde_edge_entry=false — отряд на точке заказа (%.1f м) — прежний спавн" % Vector2(c3.x - goal.x, c3.z - goal.z).length(),
		Vector2(c3.x - goal.x, c3.z - goal.z).length() < pad + 1.0)
	_Opt.horde_edge_entry = true
	_kill(sid3)
	await pframes(3)
	if fog != null:
		fog.enabled = false

# ═════════════════════════════════════════════════════════════════════════════
# B. ПЛАШКА «ЛАГЕРЬ ОРДЫ УНИЧТОЖЕН»
# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# C. МАРШ ВОЛНЫ ПРИВАЛАМИ (WaveMarch, ручка wave_stages)
# ═════════════════════════════════════════════════════════════════════════════
const _WM := preload("res://scripts/goblin/WaveMarch.gd")

## Волна из своих отрядов к базе игрока: состав — у площадки сбора лагеря
func _make_wave(ga) -> Dictionary:
	var kinds: Array = ["goblin_spearman", "goblin_spearman", "goblin_spearman",
		"big_goblin", "big_goblin", "goblin_rider"]
	var sids: Array = []
	for i in range(kinds.size()):
		var base: Vector3 = ga._slot_pos(i)
		var n: int = int(_GobCfg.SQUAD_SIZE.get(kinds[i], 30))
		var sid: int = int(main.spawn_goblin_squad(kinds[i], n, base, false, 0, false))
		if sid > 0:
			ga._set_horde_formation(sid, base, n, Vector3.FORWARD)
			sids.append(sid)
	await pframes(90)
	var n0: int = ga.waves.size()
	ga._launch("big_a", sids)
	if ga.waves.size() <= n0:
		return {}
	var w: Dictionary = ga.waves[ga.waves.size() - 1]
	# Цель — база игрока за бродом (жребий сценария стенду не нужен)
	var pb: Vector3 = main.PLAYER_BASE_ANCHOR
	w["pos"] = pb
	w["name"] = "player_base"
	w["node"] = null
	ga._assign_points(w)
	if _Opt.wave_stages:
		_WM.build_legs(ga, w)
	else:
		w.erase("legs")
		for sid in sids:
			ga._order_move(int(sid), (w["pts"] as Dictionary)[sid]["stage"], false)
	return w

func _block_c() -> void:
	print("\n═════ C. МАРШ ВОЛНЫ ПРИВАЛАМИ ═════")
	var ga = main.goblin_ai
	ga._reserve_done = true
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	# Игроков в походе нет: стоящие на базе у цели — уже развёртывание
	var w: Dictionary = await _make_wave(ga)
	if w.is_empty():
		verdict("C1 волна вышла", false)
		return
	var legs: Array = w.get("legs", [])
	print("  привалов %d, цель %s" % [legs.size(), str(w["pos"])])
	verdict("C1 путь через брод разбит на привалы: выход, подступ, за бродом (%d)" % legs.size(), legs.size() >= 3)
	ga.set_process(true)
	Engine.time_scale = 3.0
	var shots: Dictionary = {}     # привал → [спят, всего, мин. разнос, конница сзади]
	var t_ms: int = Time.get_ticks_msec()
	var g := 0
	while g < 60 * 400 and not bool(w.get("legs_done", false)) and ga.waves.has(w):
		await pframes(20)
		g += 20
		var li: int = int(w.get("leg", -1))
		if li < 0 or li >= legs.size() or shots.has(li) or float(w.get("gather_t", -1.0)) < 0.0:
			continue
		var hp: Dictionary = w.get("hpts", {})
		var all_in := true
		var asleep := 0
		var total := 0
		var cs: Array = []
		for sid in (w["sids"] as Array):
			var men: Array = _alive(int(sid))
			var c: Vector3 = _centre(men)
			if c.x == INF or not hp.has(sid):
				continue
			if Vector2(c.x - (hp[sid] as Vector3).x, c.z - (hp[sid] as Vector3).z).length() >= _Spawn.HALT_ARRIVE_R:
				all_in = false
			cs.append([int(sid), c])
			for m in men:
				total += 1
				if (m as Unit).dormant:
					asleep += 1
		if not all_in or float(asleep) < float(total) * 0.8:
			continue
		var dmin := INF
		for i in range(cs.size()):
			for j in range(i + 1, cs.size()):
				var a: Vector3 = cs[i][1]
				var b: Vector3 = cs[j][1]
				dmin = minf(dmin, Vector2(a.x - b.x, a.z - b.z).length())
		var dir: Vector3 = w.get("leg_dir", Vector3.FORWARD)
		var inf_p := 0.0
		var inf_n := 0
		var cav_p := INF
		for e in cs:
			var p: float = (e[1] as Vector3).x * dir.x + (e[1] as Vector3).z * dir.z
			if ga._type(int(e[0])) == "goblin_rider":
				cav_p = minf(cav_p, p)
			else:
				inf_p += p
				inf_n += 1
		var behind: bool = cav_p == INF or cav_p < inf_p / maxf(inf_n, 1) - 3.0
		shots[li] = [asleep, total, dmin, behind]
		print("  привал %d собран через %.0f с игры: спят %d/%d, разнос центров ≥ %.1f м, конница сзади %s" % [
			li + 1, ga.clock - float(w["t0"]), asleep, total, dmin, behind])
	Engine.time_scale = 1.0
	print("  этапы: приказов %d, пройдено %d, застреваний %d, опозданий %d, сканов %d, стена %.0f с" % [
		ga.halts_ordered, ga.halts_done, ga.halt_stuck, ga.halt_late, ga.scans_done,
		float(Time.get_ticks_msec() - t_ms) / 1000.0])
	verdict("C2 волна прошла все привалы (%d/%d, legs_done=%s)" % [ga.halts_done, legs.size(), bool(w.get("legs_done", false))],
		bool(w.get("legs_done", false)) and ga.halts_done >= legs.size())
	var slept_ok := shots.size() >= 2
	var gap_ok := shots.size() >= 2
	var cav_ok := shots.size() >= 2
	for k in shots:
		var s: Array = shots[k]
		slept_ok = slept_ok and float(s[0]) >= float(s[1]) * 0.8
		gap_ok = gap_ok and float(s[2]) >= _Spawn.HALT_GAP_MIN * 0.6
		cav_ok = cav_ok and bool(s[3])
	verdict("C3 на привалах собрались и спят (снимков %d)" % shots.size(), slept_ok)
	verdict("C4 отряды стоят блоком, а не кучей (центры ≥ %.1f м)" % (_Spawn.HALT_GAP_MIN * 0.6), gap_ok)
	verdict("C5 конница в заднем ряду блока", cav_ok)
	ga.set_process(false)
	for sid2 in (w["sids"] as Array):
		_kill(int(sid2))
	ga.waves.erase(w)
	await pframes(10)
	# C0: ручка выключена — прежний прямой марш без привалов
	_Opt.wave_stages = false
	var w0: Dictionary = await _make_wave(ga)
	verdict("C0 wave_stages=false — привалов нет", not w0.is_empty() and not w0.has("legs"))
	_Opt.wave_stages = true
	for sid3 in (w0.get("sids", []) as Array):
		_kill(int(sid3))
	ga.waves.erase(w0)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# D. ПОДАЧА В БОЙ ДОЗАМИ (WaveFeed, ручка wave_feed)
# ═════════════════════════════════════════════════════════════════════════════
func _player_squad(at: Vector3) -> int:
	var scene: PackedScene = Building.PRELOAD_SCENES.get("spearman")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(30):
		var p: Vector3 = at + Vector3(float(i % 10) * 0.6 - 2.7, 0.0, float(i / 10) * 0.6)
		var u: Unit = scene.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
	return sid

func _kill_frac(sid: int, frac: float) -> void:
	var men: Array = _alive(sid)
	var k: int = int(ceil(float(men.size()) * frac))
	for i in range(mini(k, men.size())):
		(men[i] as Unit).take_damage(1e12)

func _queued_sids(ga) -> Dictionary:
	var out: Dictionary = {}
	for o in ga._oq:
		out[int((o as Dictionary)["sid"])] = true
	return out

func _feed_wave(ga, c: Vector3) -> Dictionary:
	var kinds: Array = ["goblin_spearman", "goblin_spearman", "goblin_spearman",
		"big_goblin", "big_goblin", "goblin_rider"]
	var sids: Array = []
	for i in range(kinds.size()):
		var base: Vector3 = GameManager.land_target(c + Vector3((float(i) - 2.5) * 16.0, 0.0, -32.0))
		var n: int = int(_GobCfg.SQUAD_SIZE.get(kinds[i], 30))
		var sid: int = int(main.spawn_goblin_squad(kinds[i], n, base, false, 0, false))
		if sid > 0:
			ga._set_horde_formation(sid, base, n, Vector3(0.0, 0.0, 1.0))
			sids.append(sid)
	await pframes(120)
	var n0: int = ga.waves.size()
	_Opt.wave_stages = false
	ga._launch("big_a", sids)
	_Opt.wave_stages = true
	if ga.waves.size() <= n0:
		return {}
	var w: Dictionary = ga.waves[ga.waves.size() - 1]
	w["pos"] = c
	w["name"] = "player_base"
	w["node"] = null
	w["tactic"] = "front"
	ga._assign_points(w)
	ga._oq.clear()
	return w

func _block_d() -> void:
	print("\n═════ D. ПОДАЧА В БОЙ ДОЗАМИ ═════")
	var ga = main.goblin_ai
	ga.set_process(false)
	var c: Vector3 = GameManager.land_target(main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, 30.0))
	main._clear_area_of_resources(c, 60.0)
	var foes: Array = []
	for k in range(3):
		foes.append(_player_squad(c + Vector3((float(k) - 1.0) * 12.0, 0.0, 0.0)))
	var w: Dictionary = await _feed_wave(ga, c)
	if w.is_empty():
		verdict("D1 волна вышла", false)
		return
	ga._deploy(w)
	var fd: Dictionary = w.get("feed", {})
	var on: Dictionary = fd.get("on", {})
	var q: Dictionary = _queued_sids(ga)
	var bigs := 0
	for sid in on:
		if ga._type(int(sid)) == "big_goblin":
			bigs += 1
	print("  первая доза: в бою %d из %d, приказов %d, туш в дозе %d" % [on.size(), (w["sids"] as Array).size(), q.size(), bigs])
	verdict("D1 первая доза — по отряду на каждый из 3 чужих, остальные в резерве (в бою %d, приказов %d)" % [on.size(), q.size()],
		on.size() == 3 and q.size() == 3)
	verdict("D2 против копейщиков первыми идут туши (%d из 2)" % bigs, bigs == 2)
	ga._oq.clear()
	ga._wave_engage(w, 1.0)
	var fl: Dictionary = fd.get("flank", {})
	verdict("D3 лишний резерв заходит во фланг (%d)" % fl.size(), fl.size() == 1)
	# Замена: свой в бою просел до четверти — на его противника свежий
	var weak: int = int(on.keys()[0])
	var weak_foe: int = int(on[weak])
	_kill_frac(weak, 0.8)
	await pframes(4)
	var r0: int = ga.feed_replaced
	ga._oq.clear()
	ga._wave_engage(w, 1.0)
	var fresh := 0
	for sid2 in on:
		if int(on[sid2]) == weak_foe and int(sid2) != weak:
			fresh += 1
	verdict("D4 просевший отряд заменён свежим на том же противнике (замен +%d, свежих %d)" % [ga.feed_replaced - r0, fresh],
		ga.feed_replaced > r0 and fresh >= 1)
	# Брешь: чужой отряд в бою ослаб — конница в него
	_kill_frac(int(foes[1]), 0.6)
	await pframes(4)
	ga._oq.clear()
	ga._wave_engage(w, 1.0)
	var cav: Dictionary = fd.get("cav", {})
	verdict("D5 ослабший чужой отряд — конница бьёт в брешь (%d)" % cav.size(), cav.size() >= 1)
	print("  счётчики: доз %d, замен %d, фланг %d, брешей %d" % [ga.feed_doses, ga.feed_replaced, ga.feed_flanks, ga.feed_breaches])
	for sid3 in (w["sids"] as Array):
		_kill(int(sid3))
	ga.waves.erase(w)
	ga._oq.clear()
	await pframes(10)
	# D0: ручка выключена — все отряды получают приказ разом
	_Opt.wave_feed = false
	var w0: Dictionary = await _feed_wave(ga, c)
	ga._deploy(w0)
	var q0: Dictionary = _queued_sids(ga)
	verdict("D0 wave_feed=false — приказы всем отрядам разом (%d из %d)" % [q0.size(), (w0.get("sids", []) as Array).size()],
		q0.size() == (w0.get("sids", []) as Array).size() and not w0.has("feed"))
	_Opt.wave_feed = true
	for sid4 in (w0.get("sids", []) as Array):
		_kill(int(sid4))
	for f in foes:
		_kill(int(f))
	ga.waves.erase(w0)
	ga._oq.clear()
	await pframes(10)

func _notice_text() -> String:
	var hud = main.get("hud")
	if hud == null:
		return ""
	var nt = hud.get("_notice")
	if nt == null or not is_instance_valid(nt):
		return ""
	return String((nt as Label).text)

func _block_b() -> void:
	print("\n═════ B. ПЛАШКА ЛАГЕРЯ ═════")
	var ga = main.goblin_ai
	var hud = main.get("hud")
	if hud != null and hud.get("_notice") != null and is_instance_valid(hud.get("_notice")):
		(hud.get("_notice") as Node).queue_free()
	await pframes(2)
	ga._defeat()
	await pframes(2)
	var t: String = _notice_text()
	verdict("B1 разгром лагеря не показывает плашку («%s»), производство встало" % t,
		not t.contains("Лагерь орды") and String(ga.phase) == String(ga.PHASE_DEFEATED))
	_Opt.horde_defeat_notice = true
	ga._defeat()
	await pframes(2)
	t = _notice_text()
	verdict("B0 horde_defeat_notice=true — прежняя плашка («%s»)" % t, t.contains("Лагерь орды"))
	_Opt.horde_defeat_notice = false
