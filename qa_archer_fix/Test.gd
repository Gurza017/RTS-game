extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: РЕМОНТ ЛУЧНИКОВ (ТЗ 17.09.2026), headless
## ═══════════════════════════════════════════════════════════════════════════
##   A КУЗНИЦА  — два отряда лучников стоят строем, в 23 м чужие; узлы ветки
##                лучника изучаются один за другим: отряды НЕ рассыпаются —
##                реестр отрядов тот же, все бойцы в своих отрядах, никто не
##                ушёл дальше метра и никто не идёт
##   B ПРИКАЗ   — то же под приказом атаки на чужих у края дальности:
##                после каждого исследования отряд остаётся отрядом
##   C ТРУПЫ    — лучники стреляют по гоблинам; стенд убивает всех разом:
##                после гибели цели новых выстрелов по павшим нет, цели у
##                стрелков сняты в такт, отрядная цель снята
##   D ТРОЛЛЬ   — то же с тушей: убит — стрелы по нему не летят, хитбокс
##                мёртвого в скане целей не возникает
## Числа — из конфигов (правило 10), время — физкадрами (правило 11).

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

var main = null
var _seen_move: Dictionary = {}
var _seen_post: Dictionary = {}
var _dumped: bool = false
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(480.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 480 с")
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
	print("\n═════ ИТОГ qa_archer_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6, face: Vector3 = Vector3.RIGHT) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x - float(i / cols) * 0.8, 0.0,
			at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	for u in men:
		(u as Unit).command_move((u as Unit).global_position, false, face)
	GameManager.squad_close_ranks(sid, true)
	return [sid, men]

func _kill_all(men: Array) -> void:
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _positions(men: Array) -> Dictionary:
	var d: Dictionary = {}
	for u in _alive(men):
		d[u] = (u as Unit).global_position
	return d

## Сколько бойцов сдвинулось дальше lim от снимка, худший сдвиг, идущих
func _drift(men: Array, snap: Dictionary, lim: float) -> Array:
	var moved := 0
	var worst := 0.0
	var walking := 0
	for u in _alive(men):
		if not snap.has(u):
			continue
		var d: float = _xz((u as Unit).global_position, snap[u])
		worst = maxf(worst, d)
		if d > lim:
			moved += 1
		if (u as Unit).state == Unit.State.MOVING:
			walking += 1
	return [moved, worst, walking]

func _in_squad(men: Array, sid: int) -> int:
	var n := 0
	for u in _alive(men):
		if (u as Unit).squad_id == sid:
			n += 1
	return n

## Отряды своей стороны в реестре (чужие ИИ/орда заводят свои по ходу партии)
func _own_squads() -> int:
	var n := 0
	for key in GameManager.squads:
		if int((GameManager.squads[key] as Dictionary).get("faction", -1)) == F:
			n += 1
	return n

func _archer_cells() -> Array:
	var out: Array = []
	for c in _Forge.cells():
		var cell: String = String(c)
		if _UCfg.get_upgrade_slot(_Forge.node_id("archer", cell)).is_empty():
			continue
		out.append(cell)
	return out

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(14.0, 0.0, 0.0), Vector3(-14.0, 0.0, 0.0), Vector3(0.0, 0.0, 8.0), Vector3(0.0, 0.0, -8.0), Vector3(25.0, 0.0, 0.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
			if GameManager.is_water(p.x, p.z) or GameManager.is_water(p.x + 25.0, p.z):
				h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if main.fog != null:
		main.fog.enabled = false
	GameManager.pop_limit_enabled = false
	await frames(3)
	# Дикие (стражи пней, гноллы, патрули) на площадку не заходят: их тик снят
	for n in get_tree().get_nodes_in_group("all_units"):
		var wu := n as Unit
		if wu != null and wu.faction != F:
			wu.set_tick(false)
	var base: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 30.0))
	main._clear_area_of_resources(base, 70.0)
	await _a_forge(base, false)
	await _a_forge(base + Vector3(0.0, 0.0, 60.0), true)
	await _c_corpses(base + Vector3(-60.0, 0.0, 0.0))
	await _d_troll(base + Vector3(60.0, 0.0, 0.0))
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A / B. ПРОКАЧКИ КУЗНИЦЫ НЕ РАССЫПАЮТ ОТРЯД
# ═════════════════════════════════════════════════════════════════════════════
func _a_forge(base: Vector3, attack: bool) -> void:
	var tag: String = "B" if attack else "A"
	print("\n═════ %s. ПРОКАЧКИ КУЗНИЦЫ %s ═════" % [tag, "ПОД ПРИКАЗОМ АТАКИ" if attack else "В ПОКОЕ"])
	GameManager.researched.erase(F)
	var s1: Array = _squad("archer", F, base, 24)
	var s2: Array = _squad("archer", F, base + Vector3(0.0, 0.0, 8.0), 24)
	# В покое чужие — за дальностью, но внутри обнаружения радара после
	# роста дальности (23 м: база 15 + радар 5 = 20 → с «Длинной тетивой»
	# 17.5-25); под приказом — в дальности лука (14 м), чтобы штатный подход
	# по приказу не читался как рассыпание
	var foe_x: float = 14.0 if attack else 23.0
	var foes: Array = _squad("goblin_spearman", G, base + Vector3(foe_x, 0.0, 4.0), 12)
	for u in foes[1]:
		(u as Unit).set_tick(false)
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
		(u as Unit)._soa_push_stats()
	await pframes(60 * 2)
	if attack:
		for s in [s1, s2]:
			for u in s[1]:
				(u as Unit).command_attack(foes[1][0], true, false, true)
		# Снимок — ПОСЛЕ прихода: ждём, пока никто не идёт
		for _w in range(60 * 15):
			await get_tree().physics_frame
			var walking := 0
			for s in [s1, s2]:
				for u in _alive(s[1]):
					if (u as Unit).state == Unit.State.MOVING:
						walking += 1
			if walking == 0 and _w > 60:
				break
		await pframes(60)
	var squads0: int = _own_squads()
	_seen_move.clear()
	_seen_post.clear()
	_Opt.cmd_meter = true
	_Opt.cmd_reset()
	var snap1: Dictionary = _positions(s1[1])
	var snap2: Dictionary = _positions(s2[1])
	var cells: Array = _archer_cells()
	var worst_moved := 0
	var worst_drift := 0.0
	var worst_walk := 0
	var bad_squads := 0
	var bad_members := 0
	var bad_cell := ""
	for c in cells:
		var cell: String = String(c)
		GameManager.finish_research(F, _Forge.node_id("archer", cell))
		for _f in range(60 * 3):
			await get_tree().physics_frame
			for s in [s1, s2]:
				var snap: Dictionary = snap1 if s == s1 else snap2
				for u in _alive(s[1]):
					var uu := u as Unit
					var pd: float = _xz(uu.global_position, uu.post_pos)
					if pd > 0.7 and not _seen_post.has(uu) and uu.state != Unit.State.MOVING:
						_seen_post[uu] = true
						var tn3: String = "-"
						if uu.attack_target != null and is_instance_valid(uu.attack_target) and uu.attack_target is Unit:
							tn3 = "%s @%.1f" % [(uu.attack_target as Unit).stat_id, _xz(uu.global_position, uu.attack_target.global_position)]
						print("      ДРЕЙФ ОТ ПОСТА %s (узел %s, кадр %d): %.2f м, state %d, target %s, post %s, pos %s, сдвиг от снимка %.2f" % [
							uu.name, cell, _f, pd, uu.state, tn3, str(uu.post_pos), str(uu.global_position),
							_xz(uu.global_position, snap[uu]) if snap.has(uu) else -1.0])
					if snap.has(uu) and not _seen_move.has(uu) and _xz(uu.global_position, snap[uu]) > 0.5:
						_seen_move[uu] = true
						var tn2: String = "-"
						if uu.attack_target != null and is_instance_valid(uu.attack_target) and uu.attack_target is Unit:
							tn2 = "%s @%.1f" % [(uu.attack_target as Unit).stat_id, _xz(uu.global_position, uu.attack_target.global_position)]
						print("      СТАРТ СДВИГА %s (узел %s, кадр %d): state %d, target %s, reform_permit %s, move_target %s, post %.1f м" % [
							uu.name, cell, _f, uu.state, tn2, str(uu.get("_reform_permit")), str(uu.get("move_target")),
							_xz(uu.global_position, uu.post_pos)])
						if not _dumped:
							_dumped = true
							var sqd: Dictionary = GameManager.squads[int(s[0])]
							print("      отряд %d: reform_at %s, fails %s, next %s, now %d, slots %d" % [int(s[0]), str(sqd.get("reform_at")),
								str(sqd.get("reform_fails")), str(sqd.get("reform_next_ms")), Time.get_ticks_msec(), (sqd.get("slots", []) as Array).size()])
							for u2 in _alive(s[1]):
								var v := u2 as Unit
								print("        %s st %d pd %.2f post_valid %s snapdrift %.2f" % [v.name, v.state, _xz(v.global_position, v.post_pos),
									str(v.get("_post_valid")), _xz(v.global_position, snap[v]) if snap.has(v) else -1.0])
		var d1: Array = _drift(s1[1], snap1, 1.0)
		var d2: Array = _drift(s2[1], snap2, 1.0)
		var moved: int = int(d1[0]) + int(d2[0])
		var walk: int = int(d1[2]) + int(d2[2])
		var hp_sum := 0.0
		for s in [s1, s2]:
			for u in _alive(s[1]):
				hp_sum += (u as Unit).current_health
		var sq1: Dictionary = GameManager.squads[int(s1[0])]
		print("    узел %s: ушедших %d, худший %.2f, идущих %d, живых %d, HP %.0f, reform_pending %s, in_combat %s, last_hit %s" % [cell, moved,
			maxf(float(d1[1]), float(d2[1])), walk, _alive(s1[1]).size() + _alive(s2[1]).size(), hp_sum,
			str(sq1.get("reform_check_pending")), str(GameManager.squad_in_combat(int(s1[0]))), str(sq1.get("last_hit_ms"))])
		if moved > worst_moved:
			for s in [s1, s2]:
				for u in _alive(s[1]):
					var uu := u as Unit
					var snap: Dictionary = snap1 if s == s1 else snap2
					if snap.has(uu) and _xz(uu.global_position, snap[uu]) > 1.0:
						var tn: String = "-"
						if uu.attack_target != null and is_instance_valid(uu.attack_target) and uu.attack_target is Unit:
							tn = "%s f%d @%.1f м" % [(uu.attack_target as Unit).stat_id, (uu.attack_target as Unit).faction, _xz(uu.global_position, uu.attack_target.global_position)]
						print("      ушёл %s: state %d, target %s, forced %s, sniper %s, сдвиг %.2f" % [uu.name, uu.state,
							tn, str(uu.get("_attack_is_forced")), str(uu.get("_sniper")), _xz(uu.global_position, snap[uu])])
		if moved > worst_moved or walk > worst_walk:
			bad_cell = cell
		worst_moved = maxi(worst_moved, moved)
		worst_drift = maxf(worst_drift, maxf(float(d1[1]), float(d2[1])))
		worst_walk = maxi(worst_walk, walk)
		if _own_squads() != squads0:
			bad_squads += 1
		if _in_squad(s1[1], int(s1[0])) != _alive(s1[1]).size() or _in_squad(s2[1], int(s2[0])) != _alive(s2[1]).size():
			bad_members += 1
	for row in _Opt.cmd_report():
		print("    приказы: %s %s state %d → %d" % [row[0], row[1], int(row[2]), int(row[3])])
	_Opt.cmd_meter = false
	verdict("%s1 изучено узлов ветки лучника: все" % tag, cells.size() >= 15, "%d узлов" % cells.size())
	verdict("%s2 реестр отрядов не менялся ни на одном узле (одиночных отрядов не появилось)" % tag,
		bad_squads == 0, "нарушений %d, своих отрядов %d" % [bad_squads, _own_squads()])
	verdict("%s3 все бойцы остались в своих отрядах" % tag, bad_members == 0, "нарушений %d" % bad_members)
	verdict("%s4 никто не ушёл дальше метра от своего места после исследования" % tag,
		worst_moved == 0, "ушедших %d, худший сдвиг %.2f м (узел %s)" % [worst_moved, worst_drift, bad_cell])
	verdict("%s5 через 3 с после исследования никто не идёт" % tag, worst_walk == 0,
		"идущих %d (узел %s)" % [worst_walk, bad_cell])
	var alive1: int = _alive(s1[1]).size() + _alive(s2[1]).size()
	for s in [s1, s2]:
		for u in s[1]:
			if is_instance_valid(u) and (u as Unit).is_dead():
				print("      погиб %s: убил %s" % [(u as Unit).name, str((u as Unit).get("_slain_by"))])
	verdict("%s6 потерь среди лучников нет (чужие заморожены)" % tag, alive1 == 48, "живых %d" % alive1)
	_kill_all(s1[1]); _kill_all(s2[1]); _kill_all(foes[1])
	GameManager.researched.erase(F)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ПОСЛЕ ГИБЕЛИ ЦЕЛИ — НИ ОДНОЙ СТРЕЛЫ ПО ТРУПУ
# ═════════════════════════════════════════════════════════════════════════════
func _c_corpses(base: Vector3) -> void:
	print("\n═════ C. СТРЕЛЫ ПО ТРУПАМ ПЕХОТЫ ═════")
	var s1: Array = _squad("archer", F, base, 24)
	var foes: Array = _squad("goblin_spearman", G, base + Vector3(16.0, 0.0, 0.0), 12)
	for u in foes[1]:
		(u as Unit).set_tick(false)
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
		(u as Unit)._soa_push_stats()
	await pframes(30)
	for u in s1[1]:
		(u as Unit).command_attack(foes[1][0], true, false, true)
	# Пусть постреляют
	var fired0: int = GameManager.arrows_fired
	await pframes(60 * 6)
	var fired1: int = GameManager.arrows_fired
	verdict("C1 лучники стреляют по живым", fired1 > fired0 + 10, "выстрелов %d" % (fired1 - fired0))
	# Все чужие гибнут разом
	for u in foes[1]:
		(u as Unit).max_health = 100.0
		(u as Unit).current_health = 100.0
		(u as Unit)._soa_push_stats()
	_kill_all(foes[1])
	await pframes(2)
	var fired_dead0: int = GameManager.arrows_fired
	# Цели у стрелков — сняты в такт?
	var stale_targets := 0
	var stale_worst := 0
	for _f in range(60 * 3):
		await get_tree().physics_frame
		var st := 0
		for u in _alive(s1[1]):
			var t = (u as Unit).attack_target
			if t != null and is_instance_valid(t) and (t as Unit).is_dead():
				st += 1
		stale_worst = maxi(stale_worst, st)
		if _f == 30:
			stale_targets = st
	var fired_dead1: int = GameManager.arrows_fired
	verdict("C2 после гибели всех целей новых выстрелов нет (за 3 с ≤ 2)", fired_dead1 - fired_dead0 <= 2,
		"выстрелов после гибели %d" % (fired_dead1 - fired_dead0))
	verdict("C3 через полсекунды ни у одного стрелка нет мёртвой цели", stale_targets == 0,
		"с мёртвой целью %d (пик %d)" % [stale_targets, stale_worst])
	_kill_all(s1[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. МЁРТВЫЙ ТРОЛЛЬ — НЕ ЦЕЛЬ
# ═════════════════════════════════════════════════════════════════════════════
func _d_troll(base: Vector3) -> void:
	print("\n═════ D. СТРЕЛЫ ПО ТУШЕ ТРОЛЛЯ ═════")
	var s1: Array = _squad("archer", F, base, 24)
	var troll: Unit = _spawn("troll", G, base + Vector3(15.0, 0.0, 0.0))
	troll.set_tick(false)
	await pframes(30)
	for u in s1[1]:
		(u as Unit).command_attack(troll, true, false, true)
	var fired0: int = GameManager.arrows_fired
	await pframes(60 * 5)
	var fired1: int = GameManager.arrows_fired
	verdict("D1 лучники стреляют по троллю", fired1 > fired0 + 10, "выстрелов %d" % (fired1 - fired0))
	var tpos: Vector3 = troll.global_position
	troll.take_damage(1e12)
	await pframes(2)
	var fired_dead0: int = GameManager.arrows_fired
	var stale := 0
	for _f in range(60 * 3):
		await get_tree().physics_frame
		if _f == 30:
			for u in _alive(s1[1]):
				var t = (u as Unit).attack_target
				if t != null and is_instance_valid(t) and (t as Unit).is_dead():
					stale += 1
	var fired_dead1: int = GameManager.arrows_fired
	verdict("D2 после гибели тролля новых выстрелов нет (за 3 с ≤ 2)", fired_dead1 - fired_dead0 <= 2,
		"выстрелов после гибели %d" % (fired_dead1 - fired_dead0))
	verdict("D3 мёртвый тролль не остаётся целью ни у кого", stale == 0, "с мёртвой целью %d" % stale)
	# Хитбокс мёртвого: скан целей у точки туши ничего не находит
	var found = GameManager.army.nearest_of_side(tpos.x, tpos.z, G, 6.0)
	verdict("D4 скан целей в точке туши мёртвого не находит", found == null or not is_instance_valid(found) \
		or (found is Unit and not (found as Unit).is_dead()), "нашёл: %s" % str(found))
	_kill_all(s1[1])
	await pframes(3)
