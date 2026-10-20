extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 14.10.2026: РЕЙДЫ ПО ЧАСАМ, ЭКОНОМИКА КРАСНОГО, ГНОЛЛЫ У ПНЕЙ
## ═══════════════════════════════════════════════════════════════════════════
##   A — расписание (10:00 / 12:00 / 15:00 / сдвоенные 30:00+2), состав волн,
##       несколько волн в поле разом, приоритет целей рейда (рабочие → башни →
##       бараки → дома → крепость) функцией и живым отрядом, кадр при выходе
##       комбинированной волны;
##   B — красный ИИ: рабочие после потерь в голову очереди, темп добычи,
##       параллельная перестройка снесённых построек, крепость без склада,
##       найм армии не останавливается;
##   C — гноллы: часы от рождения пня, 1-2 отряда чередуясь, общий потолок
##       MAX_STUMP_GNOLLS, часы стоят у потолка и заводятся заново.
## Запуск: godot --headless --path . res://qa_tz1014/Test.tscn [-- only=abc]

const _Spawn := preload("res://scripts/spawn_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Raid := preload("res://scripts/goblin/RaidManager.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _Diff := preload("res://scripts/game_difficulty_config.gd")

const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN

var main: Node = null
var ev: Node = null
var ai: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abc"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz1014: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _members(sid: int) -> Array:
	var out: Array = []
	if not GameManager.squads.has(sid):
		return out
	for m in GameManager.squads[sid]["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _kill_sids(sids: Array) -> void:
	for s in sids:
		for m in _members(int(s)):
			(m as Unit).take_damage(1.0e12)

func _wave_sids(wave: int) -> Array:
	var o: Array = []
	for r in ev.spawned:
		if int((r as Dictionary)["wave"]) == wave:
			o.append(int((r as Dictionary)["sid"]))
	return o

func _wave_comp(wave: int) -> Dictionary:
	var cnt := {}
	for r in ev.spawned:
		if int((r as Dictionary)["wave"]) == wave:
			var t: String = String((r as Dictionary)["type"])
			cnt[t] = int(cnt.get(t, 0)) + 1
	return cnt

func _comp_eq(a: Dictionary, b: Dictionary) -> bool:
	for k in b:
		if int(a.get(k, 0)) != int(b[k]):
			return false
	for k2 in a:
		if int(b.get(k2, 0)) != int(a[k2]):
			return false
	return true

## Ждать, пока у волны не выйдут все n отрядов (потолок кадров)
func _wait_wave(wave: int, n: int, cap_s: float) -> bool:
	var f := 0
	while f < int(cap_s * 60.0):
		await pframes(10)
		f += 10
		if _wave_sids(wave).size() >= n:
			return true
	return false

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _bld(script_path: String, f: int, at: Vector3, variant: String = "") -> Building:
	var b: Building = load(script_path).new()
	b.faction = f
	if variant != "":
		b.variant_id = variant
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return b

func _frames_wall(n_phys: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var last: int = Time.get_ticks_usec()
	for _i in range(n_phys):
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		out.append(float(now - last) / 1000.0)
		last = now
	return out

func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s: Array = Array(a)
	s.sort()
	return float(s[clampi(int(float(s.size() - 1) * q), 0, s.size() - 1)])

func _red_workers() -> Array:
	var o: Array = []
	for n in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(n) and n is Worker and not (n as Worker).is_dead():
			o.append(n)
	return o

func _red_bld(kind: String) -> Building:
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if not is_instance_valid(b) or (b as Building).is_dead():
			continue
		if String((b as Building).building_id) == kind:
			return b
	return null

func _red_sites(kind: String = "") -> Array:
	var o: Array = []
	for s in get_tree().get_nodes_in_group("construction_sites"):
		if is_instance_valid(s) and (s as Building).faction == E and (kind == "" or String(s.target_id) == kind):
			o.append(s)
	return o

func _give(f: int, amount: float) -> void:
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(f, int(t), amount)

# ═════════════════════════════════════════════════════════════════════════════
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	ev = main.get("assault_event")
	ai = main.get("goblin_ai")
	_Opt.tick_meter = true
	# Замок игрока: при прямой загрузке Main.tscn его нет (ловушка 13.10)
	var cp: Vector3 = main.PLAYER_BASE_ANCHOR
	main._clear_area_of_resources(cp, 12.0)
	main._clear_trees(cp, 12.0)
	var castle: Building = _bld("res://scripts/Castle.gd", F, cp)
	main._phase = main.Phase.PLAYING
	await pframes(4)
	verdict("0 движок волн и вожак орды подключены", ev != null and ai != null and castle != null)
	if ev == null or ai == null:
		_finish()
		return
	if "a" in _only:
		await _block_a(castle)
	if "b" in _only:
		await _block_b()
	if "c" in _only:
		await _block_c()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. РЕЙДЫ ПО ЧАСАМ
# ═════════════════════════════════════════════════════════════════════════════
func _block_a(castle: Building) -> void:
	print("\n═════ A. РАСПИСАНИЕ РЕЙДОВ И ПРИОРИТЕТ ЦЕЛЕЙ ═════")
	var sched: Array = ev.schedule()
	var times: Array = []
	for e in sched:
		times.append(int(float(e["t"])))
	print("    расписание: %s" % str(times))
	var want: Array = [600, 720, 900, 1800, 1920, 2700, 2820, 3600, 3720]
	verdict("A1 расписание: 10:00, 12:00, 15:00, затем сдвоенные 30/45/60 (+%d с)" % int(_Spawn.ASSAULT_EVENT_PAIR_GAP_SEC),
		times == want, str(times))
	var c0: Dictionary = sched[0]["comp"]
	var c2: Dictionary = sched[2]["comp"]
	verdict("A2 состав: 10:00 и 12:00 — по 3 конницы, 15:00 — 3 конницы + 3 туши + 3 пехоты",
		_comp_eq(c0, {"goblin_rider": 3}) and _comp_eq(sched[1]["comp"], {"goblin_rider": 3})
		and _comp_eq(c2, {"goblin_rider": 3, "big_goblin": 3, "goblin_spearman": 3}))
	# Сдвоенная волна 30:00: половины дают исходный состав 3/3/2
	var h1: Dictionary = sched[3]["comp"]
	var h2: Dictionary = sched[4]["comp"]
	var sum: Dictionary = {}
	for k in h1: sum[k] = int(sum.get(k, 0)) + int(h1[k])
	for k2 in h2: sum[k2] = int(sum.get(k2, 0)) + int(h2[k2])
	verdict("A3 сдвоенная волна 30:00: %s + %s = состав срока %s" % [str(h1), str(h2), str(_Spawn.ASSAULT_EVENT_WAVES[0])],
		_comp_eq(sum, _Spawn.ASSAULT_EVENT_WAVES[0]) and String(sched[3]["kind"]) == "assault"
		and not h1.is_empty() and not h2.is_empty())
	# ── Живые срабатывания: 10:00 ────────────────────────────────────────────
	ev.set_clock(599.9)
	await pframes(60)
	var ok1: bool = await _wait_wave(1, 3, 20.0)
	var f0: Dictionary = ev.fired[0] if not ev.fired.is_empty() else {}
	verdict("A4 10:00 — рейд: 3 отряда конницы вышли на площадку (%s, срок %d)" % [str(_wave_comp(1)), int(f0.get("sched", -1))],
		ok1 and _comp_eq(_wave_comp(1), {"goblin_rider": 3}) and int(f0.get("sched", -1)) == 600 and String(f0.get("kind", "")) == "raid")
	# Волна 1 собралась и пошла — следующая не сбивает её учёт
	await pframes(60 * 6)
	var st1: String = ev.wave_stage(1)
	ev.set_clock(719.9)
	await pframes(60)
	var ok2: bool = await _wait_wave(2, 3, 20.0)
	verdict("A5 12:00 — ещё 3 конницы вслед (%s); первая волна в поле не сбита (%s → %s, точка %d)" % [
		str(_wave_comp(2)), st1, ev.wave_stage(1), ev.wave_wp(1)],
		ok2 and _comp_eq(_wave_comp(2), {"goblin_rider": 3}) and ev.wave_stage(1) == "march" and ev.wave_wp(1) >= 0
		and ev.wave_ids().size() >= 2)
	# ── 15:00 — комбинированная группа и кадр ───────────────────────────────
	var base_w: PackedFloat32Array = await _frames_wall(120)
	ev.set_clock(899.9)
	var raid_w: PackedFloat32Array = await _frames_wall(60 * 25)
	var ok3: bool = _wave_sids(3).size() >= 9
	print("    кадр физики: фон p50 %.1f p99 %.1f max %.1f; выход+сбор+марш 15:00 p50 %.1f p99 %.1f max %.1f мс; орда в поле %d" % [
		_pct(base_w, 0.5), _pct(base_w, 0.99), _pct(base_w, 1.0), _pct(raid_w, 0.5), _pct(raid_w, 0.99), _pct(raid_w, 1.0), int(main.horde_alive())])
	verdict("A6 15:00 — штурмовая группа 3/3/3 (%s)" % str(_wave_comp(3)),
		ok3 and _comp_eq(_wave_comp(3), {"goblin_rider": 3, "big_goblin": 3, "goblin_spearman": 3}))
	verdict("A7 кадр при выходе и сборе 9 отрядов: p99 %.1f ≤ фон %.1f × 2 + 10, худший %.1f ≤ 60 мс" % [
		_pct(raid_w, 0.99), _pct(base_w, 0.99), _pct(raid_w, 1.0)],
		_pct(raid_w, 0.99) <= _pct(base_w, 0.99) * 2.0 + 10.0 and _pct(raid_w, 1.0) <= 60.0)
	verdict("A8 три волны живут своим учётом (волн %d), отказов потолка 0 (%d)" % [ev.wave_ids().size(), ev.spawn_refusals],
		ev.wave_ids().size() >= 3 and ev.spawn_refusals == 0)
	# ── Сдвоенные 30:00 ─────────────────────────────────────────────────────
	for w in [1, 2, 3]:
		_kill_sids(_wave_sids(w))
	await pframes(30)
	ev.set_clock(1799.9)
	await pframes(60)
	var ok4: bool = await _wait_wave(4, 5, 20.0)
	ev.set_clock(1919.9)
	await pframes(60)
	var ok5: bool = await _wait_wave(5, 3, 20.0)
	var f4: Dictionary = ev.fired[3] if ev.fired.size() > 3 else {}
	var f5: Dictionary = ev.fired[4] if ev.fired.size() > 4 else {}
	verdict("A9 30:00 — первый отряд %s в срок %d, второй %s через %d с (срок %d)" % [
		str(_wave_comp(4)), int(f4.get("sched", -1)), str(_wave_comp(5)), int(float(f5.get("sched", -1)) - float(f4.get("sched", 0))), int(f5.get("sched", -1))],
		ok4 and ok5 and int(f4.get("sched", -1)) == 1800 and int(f5.get("sched", -1)) == 1920
		and _comp_eq(_wave_comp(4), h1) and _comp_eq(_wave_comp(5), h2))
	for w2 in [4, 5]:
		_kill_sids(_wave_sids(w2))
	await pframes(30)
	# ── Приоритет целей: функция ─────────────────────────────────────────────
	# Стартовые рабочие игрока стоят у крепости и законно были бы первой
	# целью — для проверки лестницы приоритетов их снимаем
	for n in get_tree().get_nodes_in_group(Constants.unit_group(F)):
		if is_instance_valid(n) and n is Worker:
			(n as Unit).take_damage(1.0e12)
	await pframes(4)
	var cp: Vector3 = castle.global_position
	var spot: Vector3 = cp + Vector3(-30.0, 0.0, 0.0)
	main._clear_trees(spot, 30.0)
	main._clear_area_of_resources(spot, 30.0)
	var wk: Unit = _unit("worker", F, spot + Vector3(0, 0, -10.0))
	var tw: Building = _bld("res://scripts/Tower.gd", F, spot + Vector3(-8.0, 0, 6.0))
	var br: Building = _bld("res://scripts/Barracks.gd", F, spot + Vector3(8.0, 0, 10.0))
	var hs: Building = _bld("res://scripts/House.gd", F, spot + Vector3(0.0, 0, 16.0), "house")
	await pframes(4)
	var from: Vector3 = spot + Vector3(0, 0, -20.0)
	var ranks: Array = []
	var tick := 1000
	var t: Node3D = _Raid.raid_target(get_tree(), tick, from); ranks.append(_Raid.target_rank(t))
	wk.take_damage(1.0e12); await pframes(2); tick += 1
	t = _Raid.raid_target(get_tree(), tick, from); ranks.append(_Raid.target_rank(t))
	tw.take_damage(1.0e12); await pframes(2); tick += 1
	t = _Raid.raid_target(get_tree(), tick, from); ranks.append(_Raid.target_rank(t))
	br.take_damage(1.0e12); await pframes(2); tick += 1
	t = _Raid.raid_target(get_tree(), tick, from); ranks.append(_Raid.target_rank(t))
	hs.take_damage(1.0e12); await pframes(2); tick += 1
	t = _Raid.raid_target(get_tree(), tick, from); ranks.append(_Raid.target_rank(t))
	verdict("A10 приоритет целей рейда: рабочий → башня → бараки → дом → крепость (%s)" % str(ranks), ranks == [1, 2, 3, 4, 5])
	# ── Приоритет целей: живой отряд рейда у базы ───────────────────────────
	var wk2: Unit = _unit("worker", F, spot + Vector3(0, 0, -10.0))
	var tw2: Building = _bld("res://scripts/Tower.gd", F, spot + Vector3(-8.0, 0, 6.0))
	await pframes(4)
	var wid: int = ev.launch_wave({"t": ev.clock, "kind": "raid", "comp": {"goblin_rider": 1}, "label": "стенд-рейд"})
	var okw: bool = await _wait_wave(wid, 1, 10.0)
	var rsid: int = int(_wave_sids(wid)[0]) if okw else 0
	# Отряд переносится к базе и ставится в режим «цели по приоритету» —
	# марш через всю карту судит qa_goblin_base_assault
	if rsid > 0:
		var k := 0
		for m in _members(rsid):
			var u := m as Unit
			u.global_position = from + Vector3(float(k % 10) * 0.9 - 4.5, 0.0, float(k / 10) * 0.9)
			u.sync_row()
			k += 1
		ev._sq[rsid]["mode"] = "siege"
		ev._waves[wid]["stage"] = "march"
		ev._waves[wid]["wp"] = ev.route().size()
		ev._waves[wid]["spawned_t"] = ev.clock - 100.0
	await pframes(40)
	var tg1 = ev.squad_target(rsid)
	var r1: int = _Raid.target_rank(tg1)
	wk2.take_damage(1.0e12)
	# Тихо CALM_SEC → перегруппировка → цель по приоритету
	var tg2 = null
	for _i in range(20):
		await pframes(30)
		tg2 = ev.squad_target(rsid)
		if tg2 != null and is_instance_valid(tg2) and _Raid.target_rank(tg2) == 2:
			break
	var r2: int = _Raid.target_rank(tg2)
	print("    отряд рейда: цель 1 — %s (ранг %d), после гибели рабочего — %s (ранг %d); записей целей %d" % [
		str(tg1), r1, str(tg2), r2, ev.raid_targets.size()])
	verdict("A11 живой отряд рейда у базы берёт рабочего первым (ранг %d), после него — башню (ранг %d)" % [r1, r2],
		rsid > 0 and r1 == 1 and r2 == 2)
	tw2.take_damage(1.0e12)
	_kill_sids([rsid])
	await pframes(20)

# ═════════════════════════════════════════════════════════════════════════════
# B. КРАСНЫЙ ИИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_b() -> void:
	print("\n═════ B. КРАСНЫЙ ИИ: РАБОЧИЕ, ДОБЫЧА, ПЕРЕСТРОЙКА ═════")
	var red: Node = main.get("enemy_ai")
	var castle: Building = _red_bld("castle")
	verdict("B0 у красного есть крепость и рабочие (%d)" % _red_workers().size(), castle != null and _red_workers().size() > 0)
	if castle == null:
		return
	_give(E, 50000.0)
	# ── Темп добычи ──────────────────────────────────────────────────────────
	var wp: Worker = _unit("worker", F, Vector3(-100.0, 0.0, 120.0)) as Worker
	var we: Worker = _unit("worker", E, Vector3(-100.0, 0.0, 122.0)) as Worker
	await pframes(2)
	var cp_t: float = wp._cycle_time()
	var ce_t: float = we._cycle_time()
	var cp_c: float = wp.carry_capacity()
	var ce_c: float = we.carry_capacity()
	verdict("B1 рабочий красного собирает быстрее (цикл %.2f против %.2f = ×%.2f) и носит больше (%.0f против %.0f = ×%.2f)" % [
		ce_t, cp_t, ce_t / maxf(cp_t, 0.01), ce_c, cp_c, ce_c / maxf(cp_c, 0.01)],
		absf(ce_t / cp_t - _Spawn.AI_GATHER_CYCLE_MULT) < 0.02 and absf(ce_c / cp_c - _Spawn.AI_GATHER_CARRY_MULT) < 0.02)
	wp.take_damage(1.0e12); we.take_damage(1.0e12)
	# ── Рабочие после потерь — в голову очереди ──────────────────────────────
	await pframes(60 * 4)
	var n0: int = _red_workers().size()
	var peak0: int = int(red._peak_workers)
	# Замок занят заказом рыцарей — рабочий всё равно встаёт первым
	(castle as Castle).train_from_config("warrior")
	var victims: Array = _red_workers()
	for i in range(mini(4, victims.size())):
		(victims[i] as Unit).take_damage(1.0e12)
	var hires0: int = int(red.worker_priority_hires)
	await pframes(60 * 5)
	var q0: String = String((castle.production_queue[0] as Dictionary).get("name", "")) if not castle.production_queue.is_empty() else "-"
	print("    рабочих %d → %d (пик %d), очередь замка: %s, приоритетных наймов +%d, бригада ниже цели: %s" % [
		n0, _red_workers().size(), peak0, q0, int(red.worker_priority_hires) - hires0, str(red.workers_short)])
	verdict("B2 после гибели рабочих ИИ нанимает их в приоритете: заказ рабочего в голове очереди замка (%s), наймов +%d" % [
		q0, int(red.worker_priority_hires) - hires0],
		q0 == "worker" and int(red.worker_priority_hires) - hires0 >= 1 and bool(red.workers_short))
	# ── Перестройка: снесены бараки и кузница ────────────────────────────────
	var f := 0
	while (_red_bld("barracks") == null or _red_bld("smithy") == null) and f < 60 * 240:
		await pframes(30)
		f += 30
	var br: Building = _red_bld("barracks")
	var sm: Building = _red_bld("smithy")
	verdict("B3 база красного отстроилась (бараки и кузница за %d с)" % (f / 60), br != null and sm != null)
	if br != null and sm != null:
		# Такт ИИ 2 с: постройка, снесённая раньше первого такта с ней, в «пик»
		# базы не попала бы — в партии такого окна нет
		await pframes(60 * 3)
		br.take_damage(1.0e12)
		sm.take_damage(1.0e12)
		for _k in range(6):
			await pframes(60)
			var ids: Array = []
			for s0 in _red_sites():
				ids.append(String(s0.target_id))
			print("    +%d с: площадки %s; бараки %s, кузница %s; действие: %s" % [_k + 1, str(ids),
				str(_red_bld("barracks") != null), str(_red_bld("smithy") != null), String(red.last_action)])
		var sb: Array = _red_sites("barracks")
		var ss: Array = _red_sites("smithy")
		# Артель — НАЗНАЧЕННЫЕ на площадку (build_target), а не дошедшие: за
		# шесть секунд рабочий с дальней делянки до площадки не доходит
		var per_site: Dictionary = {}
		for w in _red_workers():
			var bt = (w as Worker).build_target
			if bt != null and is_instance_valid(bt):
				per_site[bt] = int(per_site.get(bt, 0)) + 1
		var crew_b: int = int(per_site.get(sb[0], 0)) if not sb.is_empty() else 0
		var crew_s: int = int(per_site.get(ss[0], 0)) if not ss.is_empty() else 0
		var starved := 0
		for st in _red_sites():
			if int(per_site.get(st, 0)) == 0:
				starved += 1
		var nw: int = _red_workers().size()
		var want_crew: int = mini(_Spawn.AI_REBUILD_CREW, nw / maxi(_red_sites().size(), 1))
		print("    площадок: бараки %d (артель %d), кузница %d (артель %d); площадок всего %d, без строителей %d, рабочих %d" % [
			sb.size(), crew_b, ss.size(), crew_s, _red_sites().size(), starved, nw])
		verdict("B4 снесённые бараки и кузница закладываются заново ПАРАЛЛЕЛЬНО (бараки %d, кузница %d), артель ≥ %d у каждой, без строителей 0 (%d)" % [
			sb.size(), ss.size(), want_crew, starved],
			not sb.is_empty() and not ss.is_empty() and crew_b >= want_crew and crew_s >= want_crew and starved == 0)
		# Дождаться бараков заново и проверить, что найм армии идёт
		f = 0
		while _red_bld("barracks") == null and f < 60 * 120:
			await pframes(30)
			f += 30
		red._peace_over = true
		await pframes(60 * 5)
		var br2: Building = _red_bld("barracks")
		var q: int = int(br2.orders_in_progress()) if br2 != null else -1
		verdict("B5 после перестройки бараки снова нанимают отряды (заказов в работе %d)" % q, br2 != null and q >= 1)
	# ── Крепость снесена, склада нет, ресурсов нет — закладывается бесплатно ──
	_give(E, 0.0)
	castle.take_damage(1.0e12)
	for _k2 in range(4):
		await pframes(60 * 2)
		print("    крепость: жива %s, находится %s, склад %s, действие: %s" % [str(is_instance_valid(castle) and not castle.is_dead()), str(red._find_castle()),
			str(GameManager.get_nearest_dropoff(E, Vector3.ZERO)), String(red.last_action)])
	var cs: Array = _red_sites("castle")
	var fresh = red._find_castle()
	var rebuilt: bool = fresh != null and is_instance_valid(fresh) and fresh != castle
	print("    после сноса крепости: площадок крепости %d, новая крепость %s, рабочих %d" % [cs.size(), str(rebuilt), _red_workers().size()])
	verdict("B6 крепость без единого склада закладывается заново бесплатно (площадка %d / достроена %s)" % [cs.size(), str(rebuilt)],
		not cs.is_empty() or rebuilt)

# ═════════════════════════════════════════════════════════════════════════════
# C. ГНОЛЛЫ У ПНЕЙ
# ═════════════════════════════════════════════════════════════════════════════
func _block_c() -> void:
	print("\n═════ C. ГНОЛЛЫ: ЧАСЫ, ЧЕРЕДОВАНИЕ 1-2, ОБЩИЙ ПОТОЛОК %d ═════" % _Spawn.MAX_STUMP_GNOLLS)
	var lairs: Array = []
	for l in GameManager.troll_lairs:
		if l != null and is_instance_valid(l) and not (l as Building).is_dead():
			lairs.append(l)
	var armed := 0
	var alive0: int = GameManager.gnoll_squads_alive_all()
	for l in lairs:
		var left: float = float(l.gnoll_wave_left())
		if left < INF and left <= _Diff.mob_gap(_GobCfg.GNOLL_SPAWN_SEC) + 1.0:
			armed += 1
	print("    пней %d, часы заведены у %d, отрядов гноллов живых %d (старт по %d на пень)" % [lairs.size(), armed, alive0, _GobCfg.GNOLL_START_SQUADS])
	verdict("C1 часы спавна идут с рождения пня у всех пней (%d/%d), интервал %d с" % [armed, lairs.size(), int(_GobCfg.GNOLL_SPAWN_SEC)],
		not lairs.is_empty() and armed == lairs.size() and absf(_GobCfg.GNOLL_SPAWN_SEC - 120.0) < 0.01)
	verdict("C2 стартовые стаи не превышают общий потолок (%d ≤ %d)" % [alive0, _Spawn.MAX_STUMP_GNOLLS], alive0 <= _Spawn.MAX_STUMP_GNOLLS)
	# Незамороженный пень для живого выхода
	var lair = null
	for l2 in lairs:
		if not bool(l2.frozen):
			lair = l2
			break
	if lair == null:
		verdict("C3 есть незамороженный пень", false)
		return
	# Освободить место: снести все отряды гноллов
	for l3 in lairs:
		_kill_sids((l3.gnoll_squads as Array).duplicate())
	await pframes(10)
	var room0: int = GameManager.gnoll_squads_room()
	var virt := 0
	for l4 in lairs:
		virt += int(l4.virt_gnoll_squads)
	var t0: int = int(lair.gnoll_squads_total)
	lair._on_gnoll_wave()
	await pframes(5)
	var d1: int = int(lair.gnoll_squads_total) - t0
	lair._on_gnoll_wave()
	await pframes(5)
	var d2: int = int(lair.gnoll_squads_total) - t0 - d1
	verdict("C3 выходы чередуются: %d, затем %d отряда (место было %d, за рекой ждут разморозки %d)" % [d1, d2, room0, virt],
		d1 == _GobCfg.GNOLL_SPAWN_MIN and d2 == _GobCfg.GNOLL_SPAWN_MAX and room0 == _Spawn.MAX_STUMP_GNOLLS - virt)
	# До потолка и за него
	var guard := 0
	while GameManager.gnoll_squads_room() > 0 and guard < 10:
		lair._on_gnoll_wave()
		await pframes(5)
		guard += 1
	var at_cap: int = GameManager.gnoll_squads_alive_all()
	var t1: int = int(lair.gnoll_squads_total)
	lair._on_gnoll_wave()
	await pframes(5)
	var left_cap: float = float(lair.gnoll_wave_left())
	verdict("C4 у потолка (%d живых) выход не идёт (+%d), часы стоят: проверка места через %.0f с" % [
		at_cap, int(lair.gnoll_squads_total) - t1, left_cap],
		at_cap == _Spawn.MAX_STUMP_GNOLLS and int(lair.gnoll_squads_total) == t1 and bool(lair.gnoll_clock_paused)
		and absf(left_cap - _GobCfg.GNOLL_SPAWN_RECHECK_SEC) < 1.0)
	# Часть отрядов выбита — часы заводятся на полный интервал, выход идёт
	var sids: Array = (lair.gnoll_squads as Array).duplicate()
	_kill_sids([sids[0], sids[1]])
	await pframes(10)
	lair._on_gnoll_wave()
	await pframes(5)
	var left2: float = float(lair.gnoll_wave_left())
	var t2: int = int(lair.gnoll_squads_total)
	lair._on_gnoll_wave()
	await pframes(5)
	verdict("C5 после гибели части отрядов часы заводятся на полный интервал (%.0f с) и выход возобновляется (+%d)" % [
		left2, int(lair.gnoll_squads_total) - t2],
		not bool(lair.gnoll_clock_paused) and absf(left2 - _Diff.mob_gap(_GobCfg.GNOLL_SPAWN_SEC)) < 1.0
		and int(lair.gnoll_squads_total) - t2 >= 1 and GameManager.gnoll_squads_alive_all() <= _Spawn.MAX_STUMP_GNOLLS)
	verdict("C6 удар по пню часы не ускоряет (было %.0f с)" % float(lair.gnoll_wave_left()), (func():
		var before: float = float(lair.gnoll_wave_left())
		lair.on_lair_attacked()
		return absf(float(lair.gnoll_wave_left()) - before) < 1.0).call())
