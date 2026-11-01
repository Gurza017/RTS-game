extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД «ПОСЛЕ ПОБЕДЫ ОТРЯД НЕ ОТХОДИТ» (ТЗ 29.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: отряд, добив врага, сбрасывает цель и уходит назад / «отматывает»
## путь — ярче всего в Attack-Move, а также когда враг напал сам (при прямом
## ПКМ по цели — почти нормально). Каждый блок ставит отряд копейщиков
## игрока ПКМ-приказом (настоящая разметка и посты), пускает две волны орды
## одну за другой по оси +X и меряет:
##   • ОТКАТ — насколько центр отряда вернулся назад по оси наступления от
##     самой дальней достигнутой точки (считается с первого контакта);
##   • «ИДЁТ ОТ ВРАГА» — боец в MOVING, чья точка приказа дальше от ближайшего
##     живого врага, чем он сам, дольше AWAY_SEC подряд (с разбором: кто
##     прислал приказ — perf_config.cmd_meter по источникам, флаги бойца);
##   • ПАУЗА МЕЖДУ ВОЛНАМИ — через сколько после гибели первой волны отряд
##     взял в бой вторую, и добил ли её.
## Блоки:
##   A — [A] Attack-Move через обе волны (стоят на пути, вторая в GAP м за первой)
##   B — [S] Защита: отряд стоит, волны нападают сами
##   C — стойка атаки, вольное стояние: волны нападают сами
##   D — то же, что A/B/C, но через секунду после первого контакта игрок
##       кликает ПКМ по бойцу первой волны (замок цели, как SelectionManager)
## Запуск: godot --headless --path . res://qa_no_retreat/Test.tscn
##         [-- only=abcd gap=N hp=0.5 diag=1]

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

## Расстояние до первой волны и зазор до второй (м по оси +X)
const D1 := 16.0
var _gap: float = 10.0
## Запас жизни волн (доля): бой короткий, но настоящий
var _hp_frac: float = 0.5
## Допустимый откат центра отряда назад по оси наступления
const RETREAT_TOL := 2.5
## «Идёт от врага» столько подряд — событие
const AWAY_SEC := 1.5
## Вторая волна обязана быть взята в бой не позже стольких секунд после первой
const ENGAGE_SEC := 8.0
## Потолок блока (игровых секунд)
const BLOCK_SEC := 100.0
const SAMPLE := 6

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcd"
var _done := false
var _diag := false
var _deep := false
var _row := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
		elif s.begins_with("gap="):
			_gap = float(s.substr(4))
		elif s.begins_with("hp="):
			_hp_frac = float(s.substr(3))
		elif s == "diag=1":
			_diag = true
		elif s == "deep=1":
			_deep = true
	call_deferred("_run")
	get_tree().create_timer(1500.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_no_retreat: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3, fac: int = F) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int = F, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k / cols) * 0.8, 0, float(k % cols) * 0.8), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _clear(at: Vector3, r: float) -> void:
	main._clear_trees(at, r)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
			u.queue_free()
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and (b as Node3D).global_position.distance_to(at) < r \
				and not (b as Building).is_stronghold():
			b.queue_free()

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for m in men:
		c += (m as Node3D).global_position
		n += 1
	if n == 0:
		return Vector3.INF
	return c / float(n)

## Сражающиеся враги: живые и не в панике. Бегущих в панике отряд не
## преследует (ТЗ 29.10.2026, п. 4) — волна, от которой остались только
## беглецы, сломлена, и «идти от бегущего» — не откат
func _fighters(men: Array) -> Array:
	var out: Array = []
	for m in _alive(men):
		if not (m as Unit).is_panicked():
			out.append(m)
	return out

func _nearest(from: Vector3, foes: Array) -> Unit:
	var best: Unit = null
	var bd := INF
	for f in foes:
		var d: float = (f as Node3D).global_position.distance_to(from)
		if d < bd:
			bd = d
			best = f
	return best

## Отряд ПКМ-приказом в точку at (разметка + посты), ждём, пока встанет
func _form(kind: String, at: Vector3, n: int) -> Array:
	var men: Array = _squad(kind, at + Vector3(-8, 0, 0), n, F, 10)
	await pframes(5)
	var sm = main.selection_manager
	sm.select_units(men)
	sm.order_at_world(at, false)
	sm.clear_selection()
	var t := 0
	while t < 900:
		await pframes(15)
		t += 15
		var home := 0
		for m in _alive(men):
			var u := m as Unit
			if u.global_position.distance_to(u.post_pos) < 2.0 and u.state == Unit.State.IDLE:
				home += 1
		if home >= int(0.9 * float(men.size())):
			break
	return men

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	_Opt.cmd_meter = true
	_Opt.squad_probes = true
	print("  зазор между волнами %.1f м, запас жизни волн %.2f; поводок отряда %.1f, погони %.1f, агро %.1f" % [
		_gap, _hp_frac, Unit.CHASE_LEASH, Unit.PURSUIT_LIMIT, Unit.AGGRO_RADIUS])
	if "a" in _only: await _case("A", "am", false)
	if "b" in _only: await _case("B", "defense", false)
	if "c" in _only: await _case("C", "idle", false)
	if "d" in _only:
		await _case("D1", "am", true)
		await _case("D2", "defense", true)
		await _case("D3", "idle", true)
	if "e" in _only: await _case("E", "am_arrived", false)
	if "f" in _only: await _case("F", "am_arrived", true)
	_finish()

func _src_rows(sid: int) -> Dictionary:
	var out: Dictionary = {}
	for r in _Opt.cmd_sid_report():
		if int(r[1]) == sid:
			out[String(r[0])] = int(r[2])
	return out

func _diff(a: Dictionary, b: Dictionary) -> String:
	var parts: Array = []
	for k in b:
		var d: int = int(b[k]) - int(a.get(k, 0))
		if d > 0:
			parts.append("%s %d" % [k, d])
	return ", ".join(parts) if not parts.is_empty() else "—"

func _flags(u: Unit, at: Vector3, foe: Unit) -> String:
	var tg: String = "-"
	if u.attack_target != null and is_instance_valid(u.attack_target):
		tg = "y"
	var lf: Vector3 = u._leash_from
	var lfs: String = "INF" if lf.x == INF else "%.1f" % (lf.x - at.x)
	return "st=%d x=%.1f mt=%.1f post=%.1f foe=%.1f tgt=%s lock=%s forced=%s leash_from=%s anch=%s march_pend=%s atk_pend=%s dis=%s ret=%s panic=%s" % [
		u.state, u.global_position.x - at.x, u.move_target.x - at.x, u.post_pos.x - at.x,
		(foe.global_position.x - at.x) if foe != null else -99.0, tg, u.target_lock, u._attack_is_forced,
		lfs, u._pursuit_anchored, u._march_pending, u._atk_pending, u._disengaging, u.retreating, u._panicked]

func _case(tag: String, mode: String, click: bool) -> void:
	var title: String = {"am": "[A] Attack-Move через две волны", "defense": "[S] Защита, волны нападают сами",
		"idle": "вольное стояние, волны нападают сами",
		"am_arrived": "[A] отряд ПРИБЫЛ в точку и ждёт группу, волны нападают сами"}[mode]
	if click:
		title += " + ПКМ игрока по бойцу первой волны"
	print("\n═════ %s. %s ═════" % [tag, title])
	var at := Vector3(-60, 0, -40 + float(_row) * 9.0)
	_row += 1
	_clear(at, 80.0)
	await pframes(5)
	var men: Array = await _form("spearman", at, 30)
	var sid: int = (men[0] as Unit).squad_id
	var sm = main.selection_manager
	var sc = sm._squad_commander
	if mode == "defense":
		sm.select_units(men)
		sm.set_selection_stance("defense")
		sm.clear_selection()
		await pframes(40)
	if mode == "am_arrived":
		# Два отряда одного клика [A]: второй стоит далеко и «не дойдёт» —
		# первый прибывает и ждёт группу в режиме [A] (как в партии)
		var buddy: Array = _squad("spearman", at + Vector3(-30, 0, 30), 10, F, 5)
		await pframes(5)
		var dest1: Vector3 = at + Vector3(14, 0, 0)
		sm.select_units(men + buddy)
		sm.order_at_world(dest1, true)
		sm.clear_selection()
		for b in buddy:
			(b as Unit).set_tick(false)
		var tw := 0
		while tw < 1800:
			await pframes(15)
			tw += 15
			var c0: Vector3 = _centre(_alive(men))
			if c0.x != INF and c0.distance_to(dest1) <= 3.0:
				break
		await pframes(120)
		print("    отряд прибыл в точку [A] (в режиме [A]: %s, прибыл: %s); дальше координаты — от точки прибытия" % [
			sc.is_attack_moving(sid), bool((sc._am.get(sid, {}) as Dictionary).get("arrived", false))])
		at = dest1
		_free(buddy)
	# Волна: deep=0 — 12 гоблинов 3×4 (мелкая стычка); deep=1 — 36 гоблинов
	# колонной 4 в ширину × 9 в глубину (7 м по ходу: отряд прорубается сквозь
	# толпу и уходит от места первого контакта дальше поводка CHASE_LEASH)
	var wn: int = 36 if _deep else 12
	var wc: int = 4
	var w1: Array = _squad("goblin_spearman", at + Vector3(D1, 0, -1.5), wn, G, wc)
	var w2: Array = _squad("goblin_spearman", at + Vector3(D1 + _gap + (8.0 if _deep else 0.0), 0, -1.5), wn, G, wc)
	for g in w1 + w2:
		(g as Unit).current_health = (g as Unit).max_health * _hp_frac
	await pframes(5)
	_Opt.cmd_reset()
	var cb0: int = Unit.chase_breaks
	var lb0: int = sc.leash_breaks
	var rs0: int = sc.resumes
	var ovr0: int = GameManager.probes.override_reports
	var dest: Vector3 = at + Vector3(D1 + _gap + 16.0, 0, 0)
	if mode == "am":
		sm.select_units(men)
		sm.order_at_world(dest, true)
		sm.clear_selection()
	else:
		var k := 0
		for g in w1:
			(g as Unit).command_attack(men[k % men.size()], true)
			k += 1
	var trace_t := 0
	var t := 0
	var t_contact := -1
	var t_w1_dead := -1
	var t_w2_eng := -1
	var t_w2_dead := -1
	var t_click := -1
	var w2_sent := false
	var maxp := -INF
	var worst_ret := 0.0
	var worst_ret_t := 0.0
	var worst_ret_phase := ""
	var streak: Dictionary = {}
	var away_events := 0
	var away_lines: Array = []
	var away_units: Dictionary = {}
	var prev_src: Dictionary = _src_rows(sid)
	var last_src_line := "—"
	var cur_src: Dictionary = {}
	var limit: int = int(BLOCK_SEC * 60.0)
	while t < limit:
		await pframes(SAMPLE)
		t += SAMPLE
		var alive: Array = _alive(men)
		if alive.is_empty():
			break
		var a1: Array = _fighters(w1)
		var a2: Array = _fighters(w2)
		var foes: Array = a1 + a2
		var c: Vector3 = _centre(alive)
		var p: float = c.x - at.x
		var fighting := false
		var eng2 := false
		for m in alive:
			var u := m as Unit
			var tg = u.attack_target
			if tg != null and is_instance_valid(tg):
				fighting = true
				if tg in w2:
					eng2 = true
		for g in a2:
			if (g as Unit).current_health < (g as Unit).max_health * _hp_frac - 0.5:
				eng2 = true
		if t_contact < 0 and fighting:
			t_contact = t
			maxp = p
		# Вторая волна нападает сама с первого контакта (подходит ~5 с) —
		# бой идёт сплошным потоком, как при подходе орды
		if mode != "am" and not w2_sent and t_contact >= 0:
			w2_sent = true
			var k2 := 0
			for g in a2:
				(g as Unit).command_attack(alive[k2 % alive.size()], true)
				k2 += 1
		# ПКМ игрока по живому бойцу первой волны (как SelectionManager)
		if click and t_click < 0 and t_contact >= 0 and t - t_contact >= 60 and not a1.is_empty():
			t_click = t
			if mode == "am":
				sc.cancel_squad(sid)
			for m in alive:
				(m as Unit).command_attack(a1[0], true, true, true)
			print("    t=%.1f ПКМ по бойцу первой волны (живых в ней %d)" % [float(t) / 60.0, a1.size()])
		if t_w1_dead < 0 and a1.is_empty() and t > 60:
			t_w1_dead = t
			print("    t=%.1f первая волна выбита; центр отряда x=%.1f" % [float(t) / 60.0, p])
		if t_w2_eng < 0 and eng2:
			t_w2_eng = t
			print("    t=%.1f вторая волна взята в бой; центр x=%.1f" % [float(t) / 60.0, p])
		if t_w2_dead < 0 and a2.is_empty() and t_w1_dead >= 0:
			t_w2_dead = t
			print("    t=%.1f вторая волна выбита; центр x=%.1f" % [float(t) / 60.0, p])
		# Источники приказов за окно
		cur_src = _src_rows(sid)
		var dl: String = _diff(prev_src, cur_src)
		if dl != "—":
			last_src_line = "t=%.1f: %s" % [float(t) / 60.0, dl]
			if _diag:
				print("    ПРИКАЗЫ %s" % last_src_line)
		prev_src = cur_src
		# Откат центра
		if t_contact >= 0:
			maxp = maxf(maxp, p)
			var ret: float = maxp - p
			if ret > worst_ret:
				worst_ret = ret
				worst_ret_t = float(t) / 60.0
				worst_ret_phase = "волна 1 жива" if not a1.is_empty() else ("волна 2 жива" if not a2.is_empty() else "врагов нет")
		# Трасса раз в секунду: центр, состояния, шаги назад по оси с источником
		if _diag and t - trace_t >= 60:
			trace_t = t
			var n_atk := 0
			var n_fwd := 0
			var n_back := 0
			var n_idle := 0
			var back_ex: Array = []
			for m in alive:
				var u := m as Unit
				if u.state == Unit.State.ATTACKING:
					n_atk += 1
				elif u.state == Unit.State.MOVING:
					var ddx: float = u.move_target.x - u.global_position.x
					if ddx < -1.5:
						n_back += 1
						if back_ex.size() < 2:
							back_ex.append(_flags(u, at, _nearest(u.global_position, foes) if not foes.is_empty() else null))
					else:
						n_fwd += 1
				else:
					n_idle += 1
			print("    ТРАССА t=%.0f центр x=%.1f | бьют %d, идут вперёд %d, НАЗАД %d, стоят %d | врагов %d+%d | приказы: %s" % [
				float(t) / 60.0, p, n_atk, n_fwd, n_back, n_idle, a1.size(), a2.size(), last_src_line])
			for ex in back_ex:
				print("      НАЗАД: %s" % ex)
		# Кто идёт от врага
		for m in alive:
			var u := m as Unit
			var id: int = u.get_instance_id()
			var away := false
			if u.state == Unit.State.MOVING and not foes.is_empty():
				var foe := _nearest(u.global_position, foes)
				var mv := Vector2(u.move_target.x - u.global_position.x, u.move_target.z - u.global_position.z)
				var tf := Vector2(foe.global_position.x - u.global_position.x, foe.global_position.z - u.global_position.z)
				# Уход = шаг ПРОТИВ направления на ближайшего врага (а не марш мимо него)
				away = mv.length() > 1.5 and tf.length() > 0.5 and mv.normalized().dot(tf.normalized()) < -0.3
			if away:
				var s: int = int(streak.get(id, 0)) + SAMPLE
				streak[id] = s
				if s >= int(AWAY_SEC * 60.0) and not away_units.has(id):
					away_units[id] = true
					away_events += 1
					if away_lines.size() < 8:
						away_lines.append("t=%.1f %s | приказы за окно: %s" % [float(t) / 60.0, _flags(u, at, _nearest(u.global_position, foes)), last_src_line])
			else:
				streak[id] = 0
				away_units.erase(id)
		if mode == "am":
			if t_w2_dead >= 0 and (c.distance_to(dest) <= 5.0 or t - t_w2_dead >= 1500):
				break
		elif t_w2_dead >= 0 and t - t_w2_dead >= 240:
			break
	var alive_end: Array = _alive(men)
	var c_end: Vector3 = _centre(alive_end)
	print("  %s: контакт %.1f с, волна1 выбита %.1f, волна2 в бою %.1f, выбита %.1f; откат макс %.2f м (t=%.1f, %s); " % [
		tag, float(t_contact) / 60.0, float(t_w1_dead) / 60.0, float(t_w2_eng) / 60.0, float(t_w2_dead) / 60.0,
		worst_ret, worst_ret_t, worst_ret_phase]
		+ "идущих от врага ≥ %.1f с: %d; живых %d из %d; центр x=%.1f (цель [A] x=%.1f)" % [
		AWAY_SEC, away_events, alive_end.size(), men.size(), (c_end.x - at.x) if c_end.x != INF else -99.0, dest.x - at.x])
	print("  %s: приказы по источникам: %s" % [tag, str(cur_src)])
	GameManager.probes.flush_now()
	print("  %s: обрывов поводка отряда %d, поводка [A] %d, возобновлений марша [A] %d, зондов сброса замка %d" % [
		tag, Unit.chase_breaks - cb0, sc.leash_breaks - lb0, sc.resumes - rs0, GameManager.probes.override_reports - ovr0])
	for l in away_lines:
		print("    ОТ ВРАГА: %s" % l)
	verdict("%s откат центра ≤ %.1f м после первого контакта" % [tag, RETREAT_TOL], worst_ret <= RETREAT_TOL,
		"%.2f м в t=%.1f (%s)" % [worst_ret, worst_ret_t, worst_ret_phase])
	verdict("%s никто не идёт от врага дольше %.1f с" % [tag, AWAY_SEC], away_events == 0, "событий %d" % away_events)
	var gap_s: float = -1.0
	if t_w1_dead >= 0 and t_w2_eng >= 0:
		gap_s = maxf(0.0, float(t_w2_eng - t_w1_dead) / 60.0)
	verdict("%s вторая волна взята в бой ≤ %.0f с после первой" % [tag, ENGAGE_SEC], t_w2_eng >= 0 and gap_s <= ENGAGE_SEC,
		"пауза %.1f с" % gap_s)
	verdict("%s обе волны сломлены (сражающихся не осталось)" % tag, t_w2_dead >= 0)
	# ПКМ игрока по врагу снимает [A] (правило 25.10.2026, SquadCommander
	# cancel_squad): точка [A] больше не приказ, и дойти до неё отряд не
	# обязан — с кликом проверяется только бой без отката (замок переходит
	# на соседний отряд, Unit._lock_next_victim)
	if mode == "am" and not click:
		verdict("%s [A] отряд дошёл до точки приказа" % tag, c_end.x != INF and c_end.distance_to(dest) <= 6.0,
			"до точки %.1f м" % (c_end.distance_to(dest) if c_end.x != INF else -1.0))
	_free(men)
	_free(w1)
	_free(w2)
	await pframes(10)
