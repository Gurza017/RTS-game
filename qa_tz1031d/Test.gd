extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tz1031d — ПНИ (ТЗ 31.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A РАССТАНОВКА — левый пень в секции у кромки, за ним золото и камень,
##          зеркальный пень на правом берегу (lair_layout_v2; A0 — прежняя точка).
##   B ОХРАНА ×3 — стражи и стартовая стая каждого пня втрое, стая своя у
##          каждого пня, общий потолок втрое (lair_guard_x3; B0).
##   C ВЫХОД ИЗ ПНЯ — гноллы пня рождаются у пня, без входа из-за кромки
##          (lair_spawn_at_lair; C0).
##   E БЕЗ ОТСТУПЛЕНИЯ — раненый гнолл не бежит в пень (gnoll_no_retreat; E0).
##   D ПОХОДЫ — правобережные пни шлют 3 тролля и 3 отряда гноллов на пятак за
##          бродом, сроки 10 / 7 мин, левый не ходит (lair_ford_sorties; D0).
##   H ПРИВАЛ ПОХОДА — вышедшие сперва собираются у подступа к броду, собрались
##          и простояли — на пятак (lair_sortie_march; H0 — сразу на пятак).
##   F НАГРАДА — снесённый игроком пень даёт +5000 и слиток (lair_reward; F0).
##   G ОЖИВЛЕНИЕ — через 30 мин пень встаёт запечатанным: 7 троллей и 20
##          отрядов внутри, переход игрока не будит, удар выпускает по одному
##          в секунду (lair_revive; G0).
## Запуск: godot --headless --path . res://qa_tz1031d/Test.tscn [-- only=abcedfg]

const _Opt := preload("res://scripts/perf_config.gd")
const _Spawn := preload("res://scripts/spawn_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _DiffL := preload("res://scripts/game_difficulty_config.gd")
const _Lair := preload("res://scripts/goblin/TrollLair.gd")
const P := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only: String = "abcedhfg"

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
	print("\n═════ ИТОГ qa_tz1031d: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd",
			"raid_manager", "lair_director"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "a" in _only: await _block_a()
	if "b" in _only: await _block_b()
	# Дальше — на чистой карте: чужие мешали бы походу и счёту гноллов
	for n in get_tree().get_nodes_in_group("all_units"):
		var wu := n as Unit
		if wu != null and wu.faction != P and not wu.is_dead():
			wu.take_damage(1e12)
	await pframes(4)
	if "c" in _only: await _block_c()
	if "e" in _only: await _block_e()
	if "d" in _only: await _block_d()
	if "h" in _only: await _block_h()
	if "f" in _only: await _block_f()
	if "g" in _only: await _block_g()
	_finish()

func _lair_of(f: int) -> Node:
	return GameManager.lair_for(f)

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

func _kill_gnolls() -> void:
	for n in get_tree().get_nodes_in_group("all_units"):
		var wu := n as Unit
		if wu != null and wu.faction == G and not wu.is_dead():
			wu.take_damage(1e12)
	await pframes(4)

## Часы партии при прямой загрузке Main стоят (не is_playing), а такт
## директора пней снят стендом: сроки привала похода двигаем сами
## Часы партии догоняют игровые часы бойцов (не обгоняют: если Main ведёт
## их сам, второй шаг не добавляется)
var _clk_from: Vector2 = Vector2.INF
func _tick_clock(_sec: float) -> void:
	if not _clk_from.is_finite():
		_clk_from = Vector2(Unit.game_sec, float(main.game_clock()))
	main.set_game_clock(maxf(float(main.game_clock()), _clk_from.y + (Unit.game_sec - _clk_from.x)))
	var dir: Node = main.lair_director
	dir._next_tick = -1.0
	dir._process(0.0)

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _player_unit() -> Unit:
	for n in get_tree().get_nodes_in_group(Constants.unit_group(P)):
		var u := n as Unit
		if u != null and not u.is_dead():
			return u
	return null

# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. РАССТАНОВКА ═════")
	var left: Node = _lair_of(E)
	var mir: Node = _lair_of(G)
	var near: Node = _lair_of(P)
	var lp: Vector3 = (left as Node3D).global_position if left != null else Vector3.INF
	verdict("A1 левый пень в секции у кромки (x %.0f, z %.0f)" % [lp.x, lp.z],
		left != null and lp.x < -185.0 and absf(lp.z) < 6.0)
	var mp: Vector3 = (mir as Node3D).global_position if mir != null else Vector3.INF
	verdict("A2 зеркальный пень на правом берегу (x %.0f, z %.0f)" % [mp.x, mp.z],
		mir != null and int(main.river_side(mp)) > 0 and _xz(mp, main.lair_mirror_center()) < 1.0)
	verdict("A3 пень игрока на месте", near != null
		and _xz((near as Node3D).global_position, main.troll_lair_center()) < 1.0)
	# Гора за левым пнём: куски золота и камня у точек кучи
	var gold := 0
	var stone := 0
	if left != null:
		for n in get_tree().get_nodes_in_group("resource_nodes"):
			var r := n as Node3D
			if r == null or not is_instance_valid(r):
				continue
			var t: int = int(r.get("resource_type"))
			var dg: float = _xz(r.global_position, lp + Vector3(_GobCfg.LAIR_PILE_GOLD.x, 0, _GobCfg.LAIR_PILE_GOLD.y))
			var ds: float = _xz(r.global_position, lp + Vector3(_GobCfg.LAIR_PILE_STONE.x, 0, _GobCfg.LAIR_PILE_STONE.y))
			if t == Constants.RESOURCE_GOLD and dg < 6.0:
				gold += 1
			if t == Constants.RESOURCE_STONE and ds < 6.0:
				stone += 1
	verdict("A4 за левым пнём золото и камень (кусков %d / %d, куч %d)" % [gold, stone, main.lair_piles],
		gold > 0 and stone > 0 and main.lair_piles == 2)
	_Opt.lair_layout_v2 = false
	var old: Vector3 = main.troll_lair_center_ai()
	var piles0: int = main.lair_piles
	main._spawn_lair_piles()
	verdict("A0 без ручки — прежняя точка (x %.0f) и без горы" % old.x,
		old.x > -160.0 and main.lair_piles == piles0)
	_Opt.lair_layout_v2 = true

# ═════════════════════════════════════════════════════════════════════════════
func _block_b() -> void:
	print("\n═════ B. ОХРАНА ×3 ═════")
	var m: int = _Spawn.LAIR_GUARD_MULT
	var want_t: int = _GobCfg.LAIR_START_TROLLS * m
	var want_g: int = _DiffL.mob_count(_GobCfg.GNOLL_START_SQUADS) * m
	var info := ""
	var ok_t := true
	var ok_g := true
	for f in [P, E, G]:
		var l: Node = _lair_of(f)
		if l == null:
			ok_t = false
			continue
		var nt: int = int(l.call("trolls_alive")) + int(l.get("virt_trolls"))
		var ng: int = int(l.call("gnoll_squads_alive"))
		info += " [%d: троллей %d, стай %d]" % [f, nt, ng]
		ok_t = ok_t and nt >= want_t
		ok_g = ok_g and ng == want_g
	verdict("B1 стражей у каждого пня ≥ %d%s" % [want_t, info], ok_t)
	verdict("B2 стартовая стая у каждого пня — %d отрядов" % want_g, ok_g)
	verdict("B3 общий потолок стай ×%d (%d)" % [m, GameManager.gnoll_squads_room() + GameManager.gnoll_squads_alive_all()],
		GameManager.gnoll_squads_room() + GameManager.gnoll_squads_alive_all() == _Spawn.MAX_STUMP_GNOLLS * m)
	_Opt.lair_guard_x3 = false
	verdict("B0 без ручки — множитель 1, потолок прежний",
		_Lair.guard_mult() == 1 and GameManager.gnoll_squads_room() + mini(GameManager.gnoll_squads_alive_all(),
			_Spawn.MAX_STUMP_GNOLLS) <= _Spawn.MAX_STUMP_GNOLLS)
	_Opt.lair_guard_x3 = true

# ═════════════════════════════════════════════════════════════════════════════
func _gnoll_spawn_probe(l: Node) -> Array:
	var fr0: bool = bool(l.get("frozen"))
	l.set("frozen", false)
	# Счётчик, а не размер списка: подсчёт потолка чистит список от выбитых
	var before: int = int(l.get("gnoll_squads_total"))
	l.call("spawn_gnoll_squads", 1)
	l.set("frozen", fr0)
	var gs: Array = l.get("gnoll_squads")
	if int(l.get("gnoll_squads_total")) <= before or gs.is_empty():
		return []
	var sid: int = int(gs[gs.size() - 1])
	return [sid, _alive(sid)]

func _block_c() -> void:
	print("\n═════ C. ГНОЛЛЫ ВЫХОДЯТ ИЗ ПНЯ ═════")
	var l: Node = _lair_of(P)
	var lp: Vector3 = (l as Node3D).global_position
	var r: Array = _gnoll_spawn_probe(l)
	var near := 0
	var has_entry := true
	if not r.is_empty():
		has_entry = (GameManager.squads[int(r[0])] as Dictionary).has("entry")
		for u in r[1]:
			if _xz((u as Unit).global_position, lp) < _GobCfg.GNOLL_PATROL_RADIUS * 1.3:
				near += 1
	verdict("C1 гноллы у пня (%d из %d), входа из-за кромки нет" % [near, (r[1] as Array).size() if not r.is_empty() else 0],
		not r.is_empty() and near == (r[1] as Array).size() and not has_entry)
	if not r.is_empty():
		_kill(int(r[0]))
	await pframes(4)
	_Opt.lair_spawn_at_lair = false
	var r0: Array = _gnoll_spawn_probe(l)
	if not r0.is_empty():
		print("    C0: вход ", (GameManager.squads[int(r0[0])] as Dictionary).get("entry"), " боец ",
			((r0[1] as Array)[0] as Unit).global_position if not (r0[1] as Array).is_empty() else "-",
			" ручка ", _Opt.horde_edge_entry)
	else:
		print("    C0: отряд не родился, capped ", l.get("gnoll_capped"), " отказов ", main.horde_cap_refusals)
	verdict("C0 без ручки — вход из-за кромки", not r0.is_empty()
		and (GameManager.squads[int(r0[0])] as Dictionary).has("entry"))
	if not r0.is_empty():
		_kill(int(r0[0]))
	_Opt.lair_spawn_at_lair = true
	await _kill_gnolls()

# ═════════════════════════════════════════════════════════════════════════════
func _block_e() -> void:
	print("\n═════ E. ГНОЛЛЫ НЕ ОТСТУПАЮТ ═════")
	var l: Node = _lair_of(P)
	var res: Array = []
	for knob in [true, false]:
		_Opt.gnoll_no_retreat = knob
		var r: Array = _gnoll_spawn_probe(l)
		if r.is_empty():
			print("    E: отряд не родился, capped ", l.get("gnoll_capped"), " отказов ", main.horde_cap_refusals,
				" места ", GameManager.gnoll_squads_room())
			res.append(null)
			continue
		var u: Unit = (r[1] as Array)[0]
		u.take_damage(u.max_health * 0.7, _player_unit())
		await pframes(3)
		res.append(bool(u.get("hiding_to_lair")))
		_kill(int(r[0]))
		await pframes(3)
	_Opt.gnoll_no_retreat = true
	verdict("E1 раненый гнолл не бежит в пень (бежит: %s)" % str(res[0]), res[0] == false)
	verdict("E0 без ручки — бежит (%s)" % str(res[1]), res[1] == true)
	await _kill_gnolls()

# ═════════════════════════════════════════════════════════════════════════════
func _block_d() -> void:
	print("\n═════ D. ПОХОДЫ К БРОДУ ═════")
	var dir: Node = main.lair_director
	var near: Node = _lair_of(P)
	var mir: Node = _lair_of(G)
	var left: Node = _lair_of(E)
	verdict("D1 сроки: ближний %.0f, дальний %.0f, левый %.0f" % [dir.sortie_period(near),
		dir.sortie_period(mir), dir.sortie_period(left)],
		is_equal_approx(dir.sortie_period(near), _Spawn.LAIR_SORTIE_NEAR_SEC)
		and is_equal_approx(dir.sortie_period(mir), _Spawn.LAIR_SORTIE_FAR_SEC)
		and dir.sortie_period(left) < 0.0)
	var patch: Vector3 = dir.patch_point()
	verdict("D2 пятак на левом берегу за бродом (%.0f, %.0f)" % [patch.x, patch.z],
		int(main.river_side(patch)) < 0 and absf(patch.z - main.FORD_Z) < main.FORD_HALF)
	# Срок пришёл — поход выходит сам, по часам
	var key: int = near.get_instance_id()
	dir._sortie_at[key] = -1.0
	dir._next_tick = -1.0
	dir._process(0.0)
	var tr: Array = (dir.patch_trolls as Array).duplicate()
	var gs: Array = (dir.patch_gnoll_squads as Array).duplicate()
	var ok_own := true
	for t in tr:
		ok_own = ok_own and (t as Unit).get("lair") == null and Vector3((t as Unit).get("ford_hold")).is_finite()
	for sid in gs:
		for g in _alive(int(sid)):
			ok_own = ok_own and (g as Unit).get("lair") == null
	verdict("D3 поход по сроку: троллей %d, отрядов %d, пню не принадлежат" % [tr.size(), gs.size()],
		tr.size() == _Spawn.LAIR_SORTIE_TROLLS and gs.size() == _Spawn.LAIR_SORTIE_GNOLLS and ok_own)
	# Дошли до пятака
	var t_at := 0
	var g_at := 0
	for i in range(60):
		await pframes(120)
		_tick_clock(2.0)
		t_at = 0
		for t in tr:
			if is_instance_valid(t) and _xz((t as Unit).global_position, patch) < 22.0:
				t_at += 1
		g_at = 0
		for sid in gs:
			var c: Vector2 = GameManager.squad_centre_xz(int(sid))
			if c.is_finite() and c.distance_to(Vector2(patch.x, patch.z)) < 25.0:
				g_at += 1
		if t_at == tr.size() and g_at == gs.size():
			break
	verdict("D4 на пятаке троллей %d из %d, отрядов %d из %d" % [t_at, tr.size(), g_at, gs.size()],
		t_at >= tr.size() - 1 and g_at >= gs.size() - 1 and tr.size() > 0)
	# Потолок пятака: повторные походы не накапливают сверх него
	for i in range(4):
		dir.launch_sortie(mir)
	verdict("D5 потолок пятака: троллей %d ≤ %d, отрядов %d ≤ %d" % [dir._alive_patch_trolls(),
		_Spawn.LAIR_PATCH_TROLLS_MAX, dir._alive_patch_gnolls(), _Spawn.LAIR_PATCH_GNOLLS_MAX],
		dir._alive_patch_trolls() <= _Spawn.LAIR_PATCH_TROLLS_MAX
		and dir._alive_patch_gnolls() <= _Spawn.LAIR_PATCH_GNOLLS_MAX)
	for t in dir.patch_trolls:
		(t as Unit).take_damage(1e12)
	await _kill_gnolls()
	_Opt.lair_ford_sorties = false
	var s0: int = dir.sorties
	dir._sortie_at[key] = -1.0
	dir._next_tick = -1.0
	dir._process(0.0)
	verdict("D0 без ручки — походов нет", dir.sorties == s0)
	_Opt.lair_ford_sorties = true

# ═════════════════════════════════════════════════════════════════════════════
func _block_h() -> void:
	print("
═════ H. ПРИВАЛ ПОХОДА ═════")
	var dir: Node = main.lair_director
	var near: Node = _lair_of(P)
	var patch: Vector3 = dir.patch_point()
	var halt: Vector3 = dir.halt_point((near as Node3D).global_position)
	verdict("H1 привал у подступа к броду на берегу пня (%.0f, %.0f)" % [halt.x, halt.z],
		halt.is_finite() and int(main.river_side(halt)) > 0)
	var m0: int = (dir.marches as Array).size()
	var h0: int = dir.march_halts + dir.march_timeouts
	var r: Array = dir.launch_sortie(near)
	var tr: Array = (dir.patch_trolls as Array).slice(-int(r[0])) if int(r[0]) > 0 else []
	var at_halt := true
	for t in tr:
		at_halt = at_halt and _xz(Vector3((t as Unit).get("ford_hold")), halt) < 10.0
	verdict("H2 вышедшие идут на привал, а не на пятак (троллей %d, поход в очереди %d → %d)" % [tr.size(), m0,
		(dir.marches as Array).size()], tr.size() > 0 and at_halt and (dir.marches as Array).size() == m0 + 1)
	for i in range(80):
		await pframes(120)
		_tick_clock(2.0)
		if i % 5 == 0 and (dir.marches as Array).size() > m0:
			var mm: Dictionary = dir.marches[m0]
			var ds: Array = []
			for e in mm["trolls"]:
				if is_instance_valid(e[0]):
					ds.append("т%.1f" % _xz((e[0] as Unit).global_position, e[2]))
			for e2 in mm["gnolls"]:
				var c2: Vector2 = GameManager.squad_centre_xz(int(e2[0]))
				if c2.is_finite():
					ds.append("г%.1f" % c2.distance_to(Vector2((e2[2] as Vector3).x, (e2[2] as Vector3).z)))
			print("    привал: на месте %s из %s, до точек %s" % [str(mm.get("there", "?")), str(mm.get("alive", "?")), str(ds)])
		if (dir.marches as Array).size() == m0:
			break
	var on_patch := true
	for t2 in tr:
		if is_instance_valid(t2):
			on_patch = on_patch and _xz(Vector3((t2 as Unit).get("ford_hold")), patch) < 10.0
	verdict("H3 собрались — привал снят, дальше на пятак (собраний %d, по сроку %d, контактов %d)" % [
		dir.march_halts, dir.march_timeouts, dir.march_contacts],
		(dir.marches as Array).size() == m0 and dir.march_halts + dir.march_timeouts > h0
		and dir.march_halts > 0 and on_patch)
	for t3 in dir.patch_trolls:
		if is_instance_valid(t3):
			(t3 as Unit).take_damage(1e12)
	await _kill_gnolls()
	await pframes(10)
	_Opt.lair_sortie_march = false
	var r0: Array = dir.launch_sortie(near)
	var tr0: Array = (dir.patch_trolls as Array).slice(-int(r0[0])) if int(r0[0]) > 0 else []
	var direct := tr0.size() > 0
	for t4 in tr0:
		direct = direct and _xz(Vector3((t4 as Unit).get("ford_hold")), patch) < 10.0
	verdict("H0 без ручки — сразу на пятак, привала нет", direct and (dir.marches as Array).size() == m0)
	_Opt.lair_sortie_march = true
	for t5 in dir.patch_trolls:
		if is_instance_valid(t5):
			(t5 as Unit).take_damage(1e12)
	await _kill_gnolls()
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
func _block_f() -> void:
	print("\n═════ F. НАГРАДА ЗА ПЕНЬ ═════")
	var pu: Unit = _player_unit()
	var l: Node = _lair_of(G)
	var g0: float = ResourceManager.get_amount(P, Constants.RESOURCE_GOLD)
	(l as Building).take_damage(1e12, pu)
	await pframes(2)
	var g1: float = ResourceManager.get_amount(P, Constants.RESOURCE_GOLD)
	var fx := false
	for c in (l as Node).get_parent().get_children() if is_instance_valid(l) and l.get_parent() != null \
			else main._world.get_children():
		if String(c.name).begins_with("LairReward"):
			fx = true
	verdict("F1 снесён игроком: золота +%.0f, слиток над пнём %s" % [g1 - g0, str(fx)],
		is_equal_approx(g1 - g0, float(_Spawn.LAIR_REWARD_GOLD)) and fx)
	_Opt.lair_reward = false
	var l2: Node = _lair_of(P)
	var g2: float = ResourceManager.get_amount(P, Constants.RESOURCE_GOLD)
	(l2 as Building).take_damage(1e12, pu)
	await pframes(2)
	verdict("F0 без ручки — без награды (+%.0f)" % (ResourceManager.get_amount(P, Constants.RESOURCE_GOLD) - g2),
		is_equal_approx(ResourceManager.get_amount(P, Constants.RESOURCE_GOLD), g2))
	_Opt.lair_reward = true
	await _kill_gnolls()

# ═════════════════════════════════════════════════════════════════════════════
func _block_g() -> void:
	print("\n═════ G. ОЖИВЛЕНИЕ ═════")
	var dir: Node = main.lair_director
	if _lair_of(G) != null:
		(_lair_of(G) as Building).take_damage(1e12, null)
		await pframes(2)
	await _kill_gnolls()
	var now: float = main.game_clock()
	# 29 минут — ещё рано
	GameManager.lair_fell_at[G] = now - _Spawn.LAIR_REVIVE_SEC + 60.0
	dir._next_tick = -1.0
	dir._process(0.0)
	verdict("G1 до 30 минут пень не встаёт", _lair_of(G) == null)
	GameManager.lair_fell_at[G] = now - _Spawn.LAIR_REVIVE_SEC - 1.0
	dir._next_tick = -1.0
	dir._process(0.0)
	await pframes(6)
	var l: Node = _lair_of(G)
	var ok := l != null
	if ok:
		ok = bool(l.get("sealed")) and bool(l.get("frozen")) \
			and int(l.get("virt_trolls")) == _Spawn.LAIR_REVIVE_TROLLS \
			and int(l.get("virt_gnoll_squads")) == _Spawn.LAIR_REVIVE_GNOLLS \
			and int(l.call("trolls_alive")) == 0
	verdict("G2 через 30 минут — запечатан: %s троллей, %s отрядов внутри, снаружи никого" % [
		str(l.get("virt_trolls")) if l != null else "-", str(l.get("virt_gnoll_squads")) if l != null else "-"], ok)
	if l == null:
		return
	# Переход игрока на берег его не будит
	var pu: Unit = _player_unit()
	var keep: Vector3 = pu.global_position
	pu.global_position = (l as Node3D).global_position + Vector3(-30.0, 0.0, 0.0)
	GameManager._lair_thaw_check()
	verdict("G3 переход игрока не будит запечатанный", not bool(l.get("thawing")))
	pu.global_position = keep
	# Удар — по одному в секунду
	(l as Building).take_damage(10.0, pu)
	await get_tree().create_timer(3.5).timeout
	var out3: int = int(l.call("trolls_alive"))
	await get_tree().create_timer(8.0).timeout
	var out11: int = int(l.call("trolls_alive"))
	var vg: int = int(l.get("virt_gnoll_squads"))
	verdict("G4 удар выпускает по одному: через 3.5 с троллей %d, через 11.5 с %d, стай внутри %d" % [
		out3, out11, vg], out3 >= 3 and out3 <= 5 and out11 == _Spawn.LAIR_REVIVE_TROLLS
		and vg < _Spawn.LAIR_REVIVE_GNOLLS and vg > 0)
	# Ручка снята — не встаёт
	(l as Building).take_damage(1e12, null)
	await pframes(2)
	_Opt.lair_revive = false
	GameManager.lair_fell_at[G] = main.game_clock() - _Spawn.LAIR_REVIVE_SEC - 1.0
	var r0: int = dir.revives
	dir._next_tick = -1.0
	dir._process(0.0)
	verdict("G0 без ручки — не встаёт", dir.revives == r0 and _lair_of(G) == null)
	_Opt.lair_revive = true
