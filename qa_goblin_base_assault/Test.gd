extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ШТУРМ БАЗЫ ИГРОКА ОТ ГЛАВНОЙ ХАТЫ ОРДЫ (ТЗ 13.10.2026, два письма)
## scripts/goblin/GoblinFortressAssaultEvent.gd
## ═══════════════════════════════════════════════════════════════════════════
## Часы эвента сдвигаются стендом (set_clock) — ждать 30 минут нельзя; всё
## остальное — живая партия (вожак орды жив, его очередь приказов и раздаёт
## приказы волны). Красный ИИ, тролли и гноллы сняты — не переменная замера.
## A — сроки: до 30:00 тишина; 30:00 срабатывает ровно раз.
## B — волна 30:00: 8 отрядов (3/3/2) по одному с шагом ~1.1 с, пик рождений
##     за кадр в бюджете, кадр в спавне не хуже фона; СБОР: до выхода
##     последнего отряда никто не уходит с площадки, марш — после всех.
## C — марш кулаком (брод свободен): компактность (поперечник кулака вне
##     боя), реку — бродом, пень огибают, в базу — нижним проходом, без
##     спама вызволений; две крепости игрока: первая снесена — переключение.
## D — 45:00: 14 отрядов (5/5/4); брод ЗАНЯТ игроком — групповое агро
##     (доля волны в бою за 12 с после первого контакта), заслон пробит,
##     перегруппировка, волна идёт дальше.
## E — 60:00: 20 отрядов (7/7/6); хата снесена — срок отменяется.
## Запуск: godot --headless --path . res://qa_goblin_base_assault/Test.tscn
##         [-- only=abcde]
## Провалы искать по «НЕ ПРОШЛО» / «провалов:» (и SCRIPT ERROR в логе).

const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN
const _Spawn := preload("res://scripts/spawn_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var ev = null
var ai = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abcde"

func _ready() -> void:
	# Стенд судит МЕХАНИКУ штурма по табличному составу; поздняя орда
	# (ТЗ 23.10.2026, второе письмо: штурмы 45:00/60:00 крупнее) — своя ручка,
	# её стережёт qa_tz1023 R
	_Opt.goblin_late_surge = false
	call_deferred("_run")
	get_tree().create_timer(2700.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_goblin_base_assault: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

# ─────────────────────────────────────────────────────────────────────────────
func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _centre(sid: int) -> Vector3:
	var c: Vector2 = GameManager.squad_centre_xz(sid)
	return Vector3(c.x, 0.0, c.y) if c.x != INF else Vector3.INF

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

func _comp_ok(cnt: Dictionary, rid: int, spear: int, big: int) -> bool:
	return int(cnt.get("goblin_rider", 0)) == rid and int(cnt.get("goblin_spearman", 0)) == spear \
		and int(cnt.get("big_goblin", 0)) == big

func _kill_sids(sids: Array) -> void:
	for s in sids:
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int, gap: float = 0.65) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var u := _unit(uid, f, at + Vector3(float(i / cols) * gap, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * gap))
		GameManager.add_to_squad(sid, u)
	return sid

func _castles() -> Array:
	var o: Array = []
	for b in get_tree().get_nodes_in_group(Constants.building_group(F)):
		if is_instance_valid(b) and b is Building and not (b as Building).is_dead() \
				and b.has_method("is_stronghold") and bool(b.call("is_stronghold")):
			o.append(b)
	return o

func _ev_set(sec: float) -> void:
	ev.set_clock(sec)
	await pframes(2)

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
	return float(s[mini(int(s.size() * q), s.size() - 1)])

## Поперечник кулака: наибольшее расстояние между центрами отрядов волны
func _span(sids: Array) -> float:
	var cs: Array = []
	for s in sids:
		if _members(int(s)).size() > 0:
			var c: Vector3 = _centre(int(s))
			if c.x != INF:
				cs.append(c)
	var w := 0.0
	for i in range(cs.size()):
		for j in range(i + 1, cs.size()):
			w = maxf(w, Vector2((cs[i] as Vector3).x - (cs[j] as Vector3).x, (cs[i] as Vector3).z - (cs[j] as Vector3).z).length())
	return w

## Ждать выхода всей волны: spawned ≥ n, затем launched; возвращает
## {"spawn_ft", "gaps", "span", "moved_before"}
func _watch_spawn(wave: int, n: int, max_s: float) -> Dictionary:
	var ft := PackedFloat32Array()
	var last: int = Time.get_ticks_usec()
	var f := 0
	var first_pos: Dictionary = {}
	var moved_before := 0
	var launched_at := -1.0
	while f < int(max_s * 60.0):
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		ft.append(float(now - last) / 1000.0)
		last = now
		f += 1
		if f % 30 != 0:
			continue
		var sids: Array = _wave_sids(wave)
		var lw: Array = ev.launched
		var launched: bool = not lw.is_empty() and int((lw[lw.size() - 1] as Dictionary)["wave"]) == wave
		if not launched:
			# До марша ни один отряд не ушёл со своего места площадки
			for s in sids:
				var c: Vector3 = _centre(int(s))
				if c.x == INF:
					continue
				if not first_pos.has(s):
					first_pos[s] = c
				elif Vector2(c.x - (first_pos[s] as Vector3).x, c.z - (first_pos[s] as Vector3).z).length() > 8.0:
					moved_before += 1
					first_pos[s] = c
		else:
			launched_at = float((lw[lw.size() - 1] as Dictionary)["t"])
			break
	var rows: Array = []
	for r in ev.spawned:
		if int((r as Dictionary)["wave"]) == wave:
			rows.append(r)
	var gaps: Array = []
	for i in range(1, rows.size()):
		gaps.append(float((rows[i] as Dictionary)["t"]) - float((rows[i - 1] as Dictionary)["t"]))
	var last_spawn: float = float((rows[rows.size() - 1] as Dictionary)["t"]) if not rows.is_empty() else -1.0
	return {"ft": ft, "gaps": gaps, "rows": rows.size(), "moved_before": moved_before,
		"launched_at": launched_at, "last_spawn": last_spawn, "span": _span(_wave_sids(wave))}

# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	# Площадку сбора/спавн у пня стенд проверяет на точке: вход орды из-за
	# кромки (ТЗ 31.10.2026, стережёт qa_tz1031c) увёл бы отряды к краю карты
	preload("res://scripts/perf_config.gd").horde_edge_entry = false
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	ev = main.get("assault_event")
	ai = main.get("goblin_ai")
	_Opt.tick_meter = true
	if ev == null:
		verdict("A0 модуль штурма подключён к Main", false)
		_finish()
		return
	# Стенд судит ЦЕЛЫЙ кулак 30:00/45:00/60:00: регулярные рейды 10-15 мин и
	# сдвоенные волны (ТЗ 14.10.2026) здесь выключены — их проверяет qa_tz1014
	ev.set_raids(false)
	ev.set_pair(false)
	for k in ["enemy_ai", "gnoll_ai", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
			n.set_physics_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit:
			var u := n0 as Unit
			if u.stat_id == "troll" or u.stat_id == "gnoll" or u.faction == E:
				u.take_damage(1.0e12)
	await pframes(4)
	print("    орда на старте: %d (потолок HORDE_CAP %d)" % [int(main.horde_alive()), _Spawn.HORDE_CAP])
	await _block_abc()
	if _only.contains("d"):
		await _block_d()
	if _only.contains("e"):
		await _block_e()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A + B + C: 30:00 — СРАБАТЫВАНИЕ, СПАВН И СБОР, МАРШ КУЛАКОМ, ШТУРМ
# ═════════════════════════════════════════════════════════════════════════════
func _block_abc() -> void:
	print("\n═════ A. СРОКИ ═════")
	var t_list: Array = _Spawn.ASSAULT_EVENT_TIMES
	verdict("A1 сроки — 30:00, 45:00, 60:00 (%s)" % str(t_list),
		t_list.size() == 3 and is_equal_approx(float(t_list[0]), 1800.0) and is_equal_approx(float(t_list[1]), 2700.0)
		and is_equal_approx(float(t_list[2]), 3600.0))
	# Часы эвента идут сами: окно фона кадра обязано кончиться ДО 30:00,
	# иначе срок срабатывает внутри него, а следующий set_clock отматывает
	# часы назад (ловушка первого прогона: «шаг выхода −1.04 с»)
	await _ev_set(1788.0)
	await pframes(60 * 3)
	verdict("A2 до 30:00 штурма нет (сработало %d)" % ev.fired.size(), ev.fired.is_empty())
	var base_ft: PackedFloat32Array = await _frames_wall(60 * 4)
	main.horde_spawn_peak = 0
	verdict("A2б фон снят до срока (часы %.1f < 1800, сработало %d)" % [ev.clock, ev.fired.size()], ev.clock < 1800.0 and ev.fired.is_empty())
	await _ev_set(1799.9)
	await pframes(60)
	var fired_n: int = ev.fired.size()
	var at: float = float((ev.fired[0] as Dictionary)["at"]) if fired_n > 0 else -1.0
	verdict("A3 30:00 сработал ровно раз (сработало %d, в %.1f с)" % [fired_n, at], fired_n == 1 and at >= 1800.0 and at < 1801.0)
	if fired_n == 0:
		return
	print("\n═════ B. СПАВН ПО ОДНОМУ И СБОР В КУЛАК ═════")
	var w: Dictionary = await _watch_spawn(1, 8, 60.0)
	var cnt: Dictionary = _wave_comp(1)
	verdict("B1 волна 30:00 — 8 отрядов: конница 3, пехота 3, туши 2 (%s)" % str(cnt), int(w["rows"]) == 8 and _comp_ok(cnt, 3, 3, 2))
	var gmin := INF
	var gmax := 0.0
	for g in w["gaps"]:
		gmin = minf(gmin, float(g))
		gmax = maxf(gmax, float(g))
	var step: float = _Spawn.ASSAULT_EVENT_SPAWN_STEP
	var peak: int = int(main.horde_spawn_peak)
	var sft: PackedFloat32Array = w["ft"]
	print("    выход: шаг %.2f…%.2f с (заказ %.2f); рождений за кадр пик %d (бюджет %d); кадр: фон p99 %.1f / худший %.1f мс, спавн+сбор p99 %.1f / худший %.1f мс" % [
		gmin, gmax, step, peak, _Opt.horde_spawn_budget, _pct(base_ft, 0.99), _pct(base_ft, 1.0), _pct(sft, 0.99), _pct(sft, 1.0)])
	verdict("B2 по одному отряду с шагом ~%.1f с (%.2f…%.2f)" % [step, gmin, gmax], gmin > step - 0.15 and gmax < step + 0.15)
	verdict("B3 рождений за кадр в бюджете (пик %d ≤ %d + 4)" % [peak, _Opt.horde_spawn_budget], peak <= _Opt.horde_spawn_budget + 4)
	var lim: float = maxf(_pct(base_ft, 0.99) * 2.0, _pct(base_ft, 0.99) + 8.0)
	verdict("B4 кадр в спавне не хуже фона: p99 %.1f ≤ %.1f мс" % [_pct(sft, 0.99), lim], _pct(sft, 0.99) <= lim)
	var la: float = float(w["launched_at"])
	var ls: float = float(w["last_spawn"])
	print("    сбор: последний отряд вышел в %.1f с, марш отдан в %.1f с (пауза %.1f); сдвинулись с площадки до марша: %d; поперечник кулака на старте %.0f м" % [
		ls, la, la - ls, int(w["moved_before"]), float(w["span"])])
	verdict("B5 никто не уходит гуськом: до марша с площадки не сдвинулся ни один отряд (%d)" % int(w["moved_before"]), int(w["moved_before"]) == 0)
	verdict("B6 марш отдан после выхода всей волны (пауза после последнего %.1f с ≥ %.1f)" % [la - ls, _Spawn.ASSAULT_EVENT_STAGE_SETTLE],
		la >= 0.0 and la - ls >= _Spawn.ASSAULT_EVENT_STAGE_SETTLE - 0.6)
	var sids: Array = _wave_sids(1)
	if _only.contains("c"):
		await _block_c(sids)
	else:
		_kill_sids(sids)

func _block_c(sids: Array) -> void:
	print("\n═════ C. МАРШ КУЛАКОМ: БРОД → ОБХОД ПНЯ → НИЖНИЙ ПРОХОД → ШТУРМ ═════")
	var route: Array = ev.route()
	var rs := ""
	for p in route:
		rs += "(%.0f, %.0f) " % [(p as Vector3).x, (p as Vector3).z]
	print("    маршрут: %s" % rs)
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	var gx: float = base.x + main.WALL_GAP_DOWN_AT
	var wz: float = main._wall_bottom_z(gx)
	var home_side: int = main.river_side(base)
	var lair := Vector3.INF
	var bd := INF
	for l in GameManager.troll_lairs:
		if is_instance_valid(l) and main.river_side((l as Node3D).global_position) == home_side:
			var d: float = (l as Node3D).global_position.distance_to((main.PLAYER_BASE_ANCHOR + main.ENEMY_BASE_ANCHOR) * 0.5)
			if d < bd:
				bd = d
				lair = (l as Node3D).global_position
	# Вторая крепость игрока — проверка переключения цели
	var c2p: Vector3 = base + Vector3(32.0, 0.0, 26.0)
	main._clear_area_of_resources(c2p, 10.0)
	main._clear_trees(c2p, 10.0)
	var c2: Building = load("res://scripts/Castle.gd").new()
	c2.faction = F
	main.world_add(c2)
	c2.global_position = Vector3(c2p.x, GameManager.get_terrain_height(c2p.x, c2p.z), c2p.z)
	await pframes(4)
	var castles: Array = _castles()
	print("    крепостей игрока %d" % castles.size())
	var side_prev: Dictionary = {}
	var bad_cross := 0
	var good_cross := 0
	var lair_min := INF
	var in_gate := 0
	var in_wall := 0
	var crossed_in: Dictionary = {}
	var siege_t := -1
	var first_razed_t := -1
	var second_hit := false
	var hp0: Dictionary = {}
	for c in castles:
		hp0[c] = (c as Building).current_health
	var span_worst := 0.0
	var span_sum := 0.0
	var span_n := 0
	var f := 0
	var limit: int = 60 * 660
	var ft := PackedFloat32Array()
	var last: int = Time.get_ticks_usec()
	while f < limit:
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		ft.append(float(now - last) / 1000.0)
		last = now
		f += 1
		if f % 30 != 0:
			continue
		var alive: Array = []
		for s in sids:
			if _members(int(s)).size() > 0:
				alive.append(int(s))
		if alive.is_empty():
			break
		# Компактность кулака — на марше, вне боя (и до штурма)
		var fighting := 0
		for sa in alive:
			if ev.squad_mode(sa) == "fight":
				fighting += 1
		if fighting == 0 and ev.wave_wp() < route.size() and ev.wave_stage() == "march":
			var sp: float = _span(alive)
			span_worst = maxf(span_worst, sp)
			span_sum += sp
			span_n += 1
		for s2 in alive:
			var c: Vector3 = _centre(s2)
			if c.x == INF:
				continue
			var sd: int = main.river_side(c)
			var pv: Variant = side_prev.get(s2)
			if sd != 0:
				if pv != null and int(pv) != 0 and int(pv) != sd:
					if absf(c.z - main.FORD_Z) <= main.FORD_HALF + 8.0:
						good_cross += 1
					else:
						bad_cross += 1
						print("      переход реки ВНЕ брода: отряд %d в (%.0f, %.0f)" % [s2, c.x, c.z])
				side_prev[s2] = sd
			if lair.x != INF and sd == home_side:
				lair_min = minf(lair_min, Vector2(c.x - lair.x, c.z - lair.z).length())
			var wzc: float = main._wall_bottom_z(c.x)
			var inside: bool = (c.z - wzc) * signf(base.z - wz) > 0.0 and c.x < main._wall_right_x(c.z)
			if inside and not crossed_in.has(s2):
				crossed_in[s2] = true
				if absf(c.x - gx) <= main.WALL_GAP_W * 0.5 + 8.0:
					in_gate += 1
				else:
					in_wall += 1
					print("      вход на базу НЕ через нижний проход: отряд %d в (%.0f, %.0f)" % [s2, c.x, c.z])
		var siege := 0
		for s3 in alive:
			if ev.squad_mode(s3) == "siege":
				siege += 1
		if siege_t < 0 and siege >= int(ceil(float(alive.size()) * 0.5)):
			siege_t = f
			print("    штурм начался на %d с (отрядов на штурме %d из %d)" % [f / 60, siege, alive.size()])
		var alive_c := 0
		for c4 in castles:
			if is_instance_valid(c4) and not (c4 as Building).is_dead():
				alive_c += 1
		if first_razed_t < 0 and alive_c < castles.size():
			first_razed_t = f
			print("    первая крепость снесена на %d с" % (f / 60))
		if first_razed_t >= 0 and alive_c > 0:
			for c5 in castles:
				if is_instance_valid(c5) and not (c5 as Building).is_dead() and (c5 as Building).current_health < float(hp0[c5]) - 1.0:
					second_hit = true
		if f % 1800 == 0:
			var st := ""
			for s4 in alive:
				var cc: Vector3 = _centre(s4)
				st += "%d:%s@(%.0f,%.0f) " % [s4, ev.squad_mode(s4), cc.x, cc.z]
			print("    t=%3d с: волна %s/wp%d, поперечник %.0f м | %s | точки %s, бой %d, подходов %d, перегруппировок %d, застрявшим %d" % [
				f / 60, ev.wave_stage(), ev.wave_wp(), _span(alive), st, str(ev.wp_reached), ev.engages, ev.assists, ev.regroups, ev.stuck_reissues])
		if alive_c == 0 or (second_hit and first_razed_t >= 0 and f - first_razed_t > 60 * 15):
			break
	var uns := 0
	var uns_max := 0
	var men := 0
	var uns_by: Dictionary = {}
	for s5 in sids:
		var sq: Variant = GameManager.squads.get(int(s5))
		if sq == null:
			continue
		var tp: String = GameManager.squad_type(int(s5))
		for m in ((sq as Dictionary)["members"] as Array):
			if m != null and is_instance_valid(m):
				men += 1
				uns += int((m as Unit).unstuck_count)
				uns_max = maxi(uns_max, int((m as Unit).unstuck_count))
				if int((m as Unit).unstuck_count) > 0:
					uns_by[tp] = int(uns_by.get(tp, 0)) + int((m as Unit).unstuck_count)
	print("    вызволения по родам: %s" % str(uns_by))
	var span_avg: float = span_sum / float(maxi(span_n, 1))
	print("    переходы реки: в броду %d, вне брода %d; ближе всего к пню %.1f м; вход на базу: проходом %d, мимо %d; поперечник кулака на марше средний %.0f м, худший %.0f м; вызволений у живых бойцов волны %d (макс %d, бойцов %d); кадр p99 %.1f, худший %.1f мс" % [
		good_cross, bad_cross, lair_min, in_gate, in_wall, span_avg, span_worst, uns, uns_max, men, _pct(ft, 0.99), _pct(ft, 1.0)])
	verdict("C1 все точки маршрута взяты кулаком (%s)" % str(ev.wp_reached), ev.wp_reached.size() >= route.size())
	verdict("C2 реку переходят только бродом (вне брода %d, бродом %d)" % [bad_cross, good_cross], bad_cross == 0 and good_cross >= 6)
	verdict("C3 центральный пень огибают (ближе всего %.1f м ≥ 10)" % lair_min, lair.x == INF or lair_min >= 10.0)
	verdict("C4 на базу — через нижний проход (проходом %d, мимо %d)" % [in_gate, in_wall], in_gate >= 5 and in_wall == 0)
	verdict("C5 не в ниточку: поперечник кулака из 8 отрядов на марше ≤ 90 м в среднем (%.0f), ≤ 140 м худший (%.0f)" % [span_avg, span_worst],
		span_n > 0 and span_avg <= 90.0 and span_worst <= 140.0)
	verdict("C6 штурм начат (%s)" % (("на %d с" % (siege_t / 60)) if siege_t >= 0 else "нет"), siege_t >= 0)
	verdict("C7 крепость снесена, волна переключилась на следующую (первая на %s, вторая под ударом: %s)" % [
		("%d с" % (first_razed_t / 60)) if first_razed_t >= 0 else "—", str(second_hit)], first_razed_t >= 0 and (second_hit or _castles().is_empty()))
	# Спам — это сотни (прежняя орда: ~21 000 за партию); 460 бойцов через
	# лесную стену, брод и застройку базы за 200 с дают единицы-десятки
	verdict("C8 без спама вызволений (всего %d на %d бойцов, на бойца до %d; порог ≤ 10 %% и ≤ 3 на бойца)" % [uns, men, uns_max],
		float(uns) <= 0.10 * float(maxi(men, 1)) and uns_max <= 3)
	_kill_sids(sids)
	await pframes(30)

# ═════════════════════════════════════════════════════════════════════════════
# D. 45:00 — 14 ОТРЯДОВ, БРОД ЗАНЯТ: ГРУППОВОЕ АГРО
# ═════════════════════════════════════════════════════════════════════════════
func _block_d() -> void:
	print("\n═════ D. 45:00: 14 ОТРЯДОВ, БРОД ЗАНЯТ ИГРОКОМ — АГРО ВСЕЙ КУЧЕЙ ═════")
	var rx: float = main.river_x(main.FORD_Z)
	var home_side: int = main.river_side(main.PLAYER_BASE_ANCHOR)
	# Заслон — на дальнем от базы берегу, у первой точки волны
	var hold := Vector3(rx - float(home_side) * 14.0, 0.0, main.FORD_Z)
	main._clear_trees(hold, 24.0)
	var block: Array = []
	var cfg: Dictionary = _UCfg.train_cfg("barracks", "spearman")
	for k in range(4):
		block.append(_squad("spearman", F, hold + Vector3(0.0, 0.0, -18.0 + 12.0 * float(k)), int(cfg.get("squad", 30)), int(cfg.get("cols", 6))))
	await pframes(10)
	var men0 := 0
	for s in block:
		men0 += _members(int(s)).size()
	var eng0: int = ev.engages
	await _ev_set(2699.9)
	await pframes(60)
	var fired_n: int = ev.fired.size()
	verdict("D1 45:00 сработал (всего срабатываний %d)" % fired_n, fired_n == 2)
	var w: Dictionary = await _watch_spawn(2, 14, 80.0)
	var cnt: Dictionary = _wave_comp(2)
	verdict("D2 волна 45:00 — 14 отрядов: конница 5, пехота 5, туши 4 (%s)" % str(cnt), int(w["rows"]) == 14 and _comp_ok(cnt, 5, 5, 4))
	verdict("D3 сбор в кулак: с площадки до марша не ушёл никто (%d), марш после всех (%s)" % [int(w["moved_before"]), str(float(w["launched_at"]) >= 0.0)],
		int(w["moved_before"]) == 0 and float(w["launched_at"]) >= 0.0)
	var sids: Array = _wave_sids(2)
	var f := 0
	var contact_t := -1
	var fight_12 := 0
	var fight_peak := 0
	var passed_t := -1
	var regroup0: int = ev.regroups
	while f < 60 * 480:
		await pframes(30)
		f += 30
		var alive: Array = []
		for s2 in sids:
			if _members(int(s2)).size() > 0:
				alive.append(int(s2))
		if alive.is_empty():
			break
		var fighting := 0
		for s3 in alive:
			if ev.squad_mode(s3) == "fight":
				fighting += 1
		fight_peak = maxi(fight_peak, fighting)
		if contact_t < 0 and fighting > 0:
			contact_t = f
			print("    первый контакт у брода на %d с (в бою %d из %d)" % [f / 60, fighting, alive.size()])
		if contact_t >= 0 and f == contact_t + 60 * 12:
			fight_12 = fighting
			print("    через 12 с после контакта в бою %d из %d (приказов боя %d, подходов %d)" % [fighting, alive.size(), ev.engages - eng0, ev.assists])
		var men := 0
		for s4 in block:
			men += _members(int(s4)).size()
		if passed_t < 0 and contact_t >= 0 and ev.regroups > regroup0 and ev.wave_wp() >= 2:
			passed_t = f
			print("    волна перегруппировалась и пошла дальше брода на %d с; заслон: осталось %d из %d; поперечник %.0f м" % [f / 60, men, men0, _span(alive)])
			break
		if f % 1800 == 0:
			print("    t=%3d с: волна %s/wp%d, в бою %d из %d, заслон %d из %d, перегруппировок %d" % [f / 60, ev.wave_stage(), ev.wave_wp(), fighting, alive.size(), men, men0, ev.regroups])
	var n_live: int = sids.size()
	verdict("D4 брод занят — волна вступает в бой (%s)" % (("на %d с" % (contact_t / 60)) if contact_t >= 0 else "нет"), contact_t >= 0)
	verdict("D5 агро всей кучей: через 12 с после контакта в бою ≥ 70 %% волны (%d из %d, пик %d)" % [fight_12, n_live, fight_peak],
		contact_t >= 0 and float(maxi(fight_12, fight_peak)) >= 0.7 * float(n_live))
	verdict("D6 заслон пробит, перегруппировка и марш дальше (%s)" % (("на %d с" % (passed_t / 60)) if passed_t >= 0 else "нет"), passed_t >= 0)
	_kill_sids(sids)
	_kill_sids(block)
	await pframes(30)

# ═════════════════════════════════════════════════════════════════════════════
# E. 60:00 — 20 ОТРЯДОВ; ХАТА СНЕСЕНА — ОТМЕНА
# ═════════════════════════════════════════════════════════════════════════════
func _block_e() -> void:
	print("\n═════ E. 60:00: 20 ОТРЯДОВ; ОТМЕНА ПРИ СНЕСЁННОЙ ХАТЕ ═════")
	var n0: int = ev.fired.size()
	print("    орда в поле перед 60:00: %d (потолок %d)" % [int(main.horde_alive()), _Spawn.HORDE_CAP])
	await _ev_set(3599.9)
	await pframes(60)
	var n1: int = ev.fired.size()
	verdict("E1 60:00 сработал (срабатываний %d → %d)" % [n0, n1], n1 == n0 + 1)
	var w: Dictionary = await _watch_spawn(3, 20, 100.0)
	var cnt: Dictionary = _wave_comp(3)
	var men := 0
	for s in _wave_sids(3):
		men += _members(int(s)).size()
	print("    волна 60:00: отрядов %d, бойцов %d, состав %s; сдвинулись до марша %d" % [int(w["rows"]), men, str(cnt), int(w["moved_before"])])
	verdict("E2 волна 60:00 — 20 отрядов: конница 7, пехота 7, туши 6 (%s)" % str(cnt), int(w["rows"]) == 20 and _comp_ok(cnt, 7, 7, 6))
	verdict("E3 сбор 20 отрядов в кулак без ухода гуськом (%d) и с маршем после всех (%s)" % [int(w["moved_before"]), str(float(w["launched_at"]) >= 0.0)],
		int(w["moved_before"]) == 0 and float(w["launched_at"]) >= 0.0)
	_kill_sids(_wave_sids(3))
	var chief = ai.get("chief")
	if chief != null and is_instance_valid(chief):
		(chief as Building).take_damage(1.0e12)
	await pframes(10)
	var ev2: Node = load("res://scripts/goblin/GoblinFortressAssaultEvent.gd").new()
	main.add_child(ev2)
	ev2.setup(main)
	ev2.set_raids(false)
	ev2.set_pair(false)
	ev2.set_clock(1799.9)
	await pframes(60 * 2)
	print("    хата жива: %s; второй эвент: сработал %d, отменено %s" % [str(ai.chief_alive()), ev2.fired.size(), str(ev2.cancelled)])
	verdict("E4 хата снесена — штурм отменён (сработал %d, отменено %s)" % [ev2.fired.size(), str(ev2.cancelled)],
		not ai.chief_alive() and ev2.fired.is_empty() and ev2.cancelled.size() == 1)
	ev2.queue_free()
