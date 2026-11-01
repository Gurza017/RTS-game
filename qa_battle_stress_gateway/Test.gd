extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ШЛЮЗ БАГОВ УПРАВЛЕНИЯ И БОЕВОЙ ЛОГИКИ (ТЗ 13.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## A — смешанная армия (копейщики, мечники, лучники — штат из конфига найма):
##     строй по линии протяжкой ПКМ, затем шесть ног Attack-Move, каждая —
##     клавишей [A] (настоящий ввод) и кликом по миру:
##       1 база → свой рудник (спящая охрана орды)
##       2 → рудник красного, по пути ЗАСАДА В ТУМАНЕ (красная пехота)
##       3 → база красного (проход в его лесной стене)
##       4 → брод, на дальний берег
##       5 → к дальнему пню; на 15-й секунде ПЕРЕНАПРАВЛЕНИЕ обычным ПКМ
##           (режим [A] обязан слететь), затем снова [A]
##       6 → лагерь орды, бой 30 с
##     Зонды каждой ноги: оторвавшиеся от тела отряда (длительность), «бегут
##     назад» (против хода своего отряда), застрявшие, глубокая вода,
##     «прошёл мимо врага» (живой враг в 10 м от центра отряда, а отряд не в
##     бою дольше 4 с), физкадр p50/p99.
##     База красного на НАШЕМ берегу — поэтому брод идёт после неё.
## B — моно-армии (только копейщики / только лучники / только мечники, по 4
##     отряда): клавиши [S] [C] [A] [F1] настоящим вводом, рамка HUD, строй
##     при стойке, Attack-Move сквозь заслон, строй по прибытии, отход в замок.
## C — туши (big_goblin): урон свипа сверяется с формулой брони жертвы,
##     комбо, ширина свипа, лента удара и возврат из неё, марш отрядов туш с
##     эскортом (застрявшие, вода, наложение тел), бой под нагрузкой.
## Запуск: godot --headless --path . res://qa_battle_stress_gateway/Test.tscn
##         [-- only=abc]
## Провалы искать по «НЕ ПРОШЛО» / «провалов:» (и SCRIPT ERROR в логе).

const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

## Разрыв строя — по компонентам связности (как qa_campaign)
const LINK_M := 3.0
const DETACH_M := 10.0
## «Прошёл мимо врага»: живой враг ближе этого к центру отряда на марше
const IGNORE_R := 10.0
const IGNORE_SEC := 4.0

var main = null
var sm = null
var cmd = null
var hud = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abc"

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(3000.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_battle_stress_gateway: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

# ─────────────────────────────────────────────────────────────────────────────
# СЛУЖЕБНОЕ
# ─────────────────────────────────────────────────────────────────────────────
## Состав для чтения — напрямую из squads[sid]["members"] (squad_members()
## распускает опустевший отряд прямо в геттере)
func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead() and not (m as Unit).garrisoned:
			o.append(m)
	return o

func _alive_sids(sids: Array) -> Array:
	var o: Array = []
	for s in sids:
		if _members(int(s)).size() >= 3:
			o.append(int(s))
	return o

func _median(men: Array) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for u in men:
		xs.append((u as Unit).global_position.x)
		zs.append((u as Unit).global_position.z)
	xs.sort()
	zs.sort()
	return Vector3(float(xs[xs.size() / 2]), 0.0, float(zs[zs.size() / 2]))

func _army_median(sids: Array) -> Vector3:
	var all: Array = []
	for s in sids:
		all.append_array(_members(int(s)))
	return _median(all) if not all.is_empty() else Vector3.ZERO

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

## Штат и ширина отряда — из конфига найма (стенд не хардкодит численность)
func _staff(kind: String) -> Array:
	var bld: String = "archery" if kind == "archer" else "barracks"
	var cfg: Dictionary = _UCfg.train_cfg(bld, kind)
	return [int(cfg.get("squad", 20)), int(cfg.get("cols", 5))]

func _kill_units_near(fac: int, at: Vector3, r: float) -> void:
	for n0 in get_tree().get_nodes_in_group(Constants.unit_group(fac)):
		if is_instance_valid(n0) and n0 is Unit and (n0 as Unit).global_position.distance_to(at) < r:
			(n0 as Unit).take_damage(1.0e12)

func _kill_faction(fac: int) -> void:
	for n0 in get_tree().get_nodes_in_group(Constants.unit_group(fac)):
		if is_instance_valid(n0) and n0 is Unit:
			(n0 as Unit).take_damage(1.0e12)

func _clear_spot(at: Vector3, r: float) -> void:
	main._clear_area_of_resources(at, r)
	main._clear_trees(at, r)

## Сухая точка рядом с желаемой (по кольцам)
func _dry(p: Vector3) -> Vector3:
	if not main.is_water(p.x, p.z):
		return p
	for ring in range(1, 8):
		for k in range(12):
			var a: float = TAU * float(k) / 12.0
			var q := p + Vector3(cos(a), 0.0, sin(a)) * float(ring) * 5.0
			if not main.is_water(q.x, q.z):
				return q
	return p

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		get_tree().root.push_input(e, true)
		await get_tree().process_frame
	await get_tree().process_frame

func _select_sids(sids: Array) -> void:
	var all: Array = []
	for s in sids:
		all.append_array(_members(int(s)))
	sm.select_units(all)
	await pframes(2)

## Attack-Move так, как его отдаёт игрок: [A] с клавиатуры, затем клик
## (order_at_world — тот же вход, что ЛКМ во взведённом режиме и мини-карта)
func _am_order(dest: Vector3) -> Dictionary:
	await _key(KEY_A)
	var armed: bool = sm.attack_move_armed
	var ok: bool = sm.order_at_world(dest, false)
	await pframes(2)
	var n := 0
	var sids: Array = sm.selected_squad_ids()
	for s in sids:
		if cmd.is_attack_moving(int(s)):
			n += 1
	return {"armed": armed, "ok": ok, "am": n, "of": sids.size(), "disarmed": not sm.attack_move_armed}

# ── физкадр ─────────────────────────────────────────────────────────────────
var _ft: PackedFloat32Array = PackedFloat32Array()
var _ft_last: int = 0
func _ft_tick() -> void:
	var now: int = Time.get_ticks_usec()
	if _ft_last > 0:
		_ft.append(float(now - _ft_last) / 1000.0)
	_ft_last = now

func _ft_reset() -> void:
	_ft = PackedFloat32Array()
	_ft_last = 0
	_Opt.tick_reset()

func _ft_report(label: String) -> Dictionary:
	if _ft.is_empty():
		return {"p50": 0.0, "p99": 0.0, "max": 0.0}
	var a: Array = Array(_ft)
	a.sort()
	var r := {"p50": float(a[a.size() / 2]), "p99": float(a[int(a.size() * 0.99)]), "max": float(a[a.size() - 1])}
	print("    %s: физкадр p50 %.1f мс, p99 %.1f мс, худший %.1f мс (кадров %d); tick_meter %.2f мс" % [
		label, r["p50"], r["p99"], r["max"], a.size(), _Opt.tick_ms()])
	return r

# ── тело отряда: самая большая компонента связности по звену LINK_M ─────────
func _main_body(men: Array) -> Dictionary:
	var n: int = men.size()
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var px := PackedFloat32Array()
	var pz := PackedFloat32Array()
	px.resize(n); pz.resize(n)
	for i in range(n):
		var p: Vector3 = (men[i] as Unit).global_position
		px[i] = p.x
		pz[i] = p.z
	var best_c := -1
	var best_n := 0
	var cid := 0
	var l2: float = LINK_M * LINK_M
	for i0 in range(n):
		if comp[i0] >= 0:
			continue
		var stack: Array = [i0]
		comp[i0] = cid
		var cnt := 0
		while not stack.is_empty():
			var i: int = stack.pop_back()
			cnt += 1
			for j in range(n):
				if comp[j] >= 0:
					continue
				var dx: float = px[i] - px[j]
				var dz: float = pz[i] - pz[j]
				if dx * dx + dz * dz <= l2:
					comp[j] = cid
					stack.append(j)
		if cnt > best_n:
			best_n = cnt
			best_c = cid
		cid += 1
	var out: Dictionary = {}
	for k in range(n):
		if comp[k] == best_c:
			out[men[k]] = true
	return out

func _fighting(sid: int) -> bool:
	return cmd.is_fighting(sid) or GameManager.squad_in_combat(sid)

## Оторвавшиеся по отряду: вне тела дальше DETACH_M от ближайшего бойца тела,
## не в бою, не в панике и не в отходе
func _detached(sid: int) -> int:
	var men: Array = _members(sid)
	if men.size() < 3 or _fighting(sid):
		return 0
	var body: Dictionary = _main_body(men)
	var n := 0
	for u in men:
		var uu := u as Unit
		if body.has(uu) or uu._panicked or uu.retreating or uu.state == Unit.State.ATTACKING:
			continue
		var p: Vector3 = uu.global_position
		var dn := INF
		for bu in body:
			dn = minf(dn, Vector2((bu as Unit).global_position.x - p.x, (bu as Unit).global_position.z - p.z).length())
		if dn > DETACH_M:
			n += 1
	return n

## Живые враги игрока в радиусе
func _foes_near(c: Vector3, r: float) -> int:
	var n := 0
	for nd in GameManager.unit_grid.query_radius(c, r):
		if nd == null or not is_instance_valid(nd):
			continue
		var u := nd as Unit
		if u == null or u.is_dead() or u.faction == F:
			continue
		n += 1
	return n

# ─────────────────────────────────────────────────────────────────────────────
# НОГА МАРША С ЗОНДАМИ
# ─────────────────────────────────────────────────────────────────────────────
## Возвращает: arrived (с, −1 — нет), det_s / det_ford_s (дольше всего
## держался отрыв), back_s (дольше всего боец шёл против хода отряда), back_n
## (бойцов, шедших назад ≥ 2 окон подряд), stuck, water, ignore_s (дольше
## всего отряд стоял рядом с живым врагом не в бою), fights (отрядов, бывших
## в бою), ft
func _leg(tag: String, sids: Array, dest: Vector3, limit_s: float, arrive_r: float,
		stop_on_arrival: bool = true) -> Dictionary:
	_ft_reset()
	var det_run: Dictionary = {}
	var det_s := 0.0
	var det_ford_s := 0.0
	var ign_run: Dictionary = {}
	var ign_s := 0.0
	var ign_who := ""
	var fought: Dictionary = {}
	var water := 0
	var stuck := 0
	var back_run: Dictionary = {}
	var back_s := 0.0
	var back_n := 0
	var back_who := ""
	var w_pos: Dictionary = {}
	var w_cen: Dictionary = {}
	var st_pos: Dictionary = {}
	var st_cen: Dictionary = {}
	var arrived := -1
	var f := 0
	var limit: int = int(limit_s * 60.0)
	var rx: float = main.river_x(0.0)
	var men0 := 0
	for s0 in sids:
		men0 += _members(int(s0)).size()
	while f < limit:
		await get_tree().physics_frame
		_ft_tick()
		f += 1
		if f % 30 != 0:
			continue
		var alive: Array = _alive_sids(sids)
		if alive.is_empty():
			break
		var near := 0
		for s in alive:
			var men: Array = _members(s)
			var c: Vector3 = _median(men)
			var at_ford: bool = absf(c.z - main.FORD_Z) < 30.0 and absf(c.x - rx) < 30.0
			if Vector2(c.x - dest.x, c.z - dest.z).length() < arrive_r:
				near += 1
			var fighting: bool = _fighting(s)
			if fighting:
				fought[s] = true
			# ── отрыв ────────────────────────────────────────────────────────
			var dn: int = _detached(s)
			var r1: int = (int(det_run.get(s, 0)) + 1) if dn > 0 else 0
			det_run[s] = r1
			if at_ford:
				det_ford_s = maxf(det_ford_s, float(r1) * 0.5)
			else:
				det_s = maxf(det_s, float(r1) * 0.5)
			# ── прошёл мимо врага ────────────────────────────────────────────
			var foes: int = _foes_near(c, IGNORE_R)
			var r2: int = (int(ign_run.get(s, 0)) + 1) if (foes > 0 and not fighting) else 0
			ign_run[s] = r2
			if float(r2) * 0.5 > ign_s:
				ign_s = float(r2) * 0.5
				ign_who = "отряд %d (%s) в (%.0f, %.0f), врагов в %d м: %d, AM=%s" % [s, GameManager.squad_type(s), c.x, c.z,
					int(IGNORE_R), foes, str(cmd.is_attack_moving(s))]
			# ── вода ─────────────────────────────────────────────────────────
			for u in men:
				var p: Vector3 = (u as Unit).global_position
				if main.is_water(p.x, p.z) and not main.in_ford(p.z):
					water += 1
		# ── НАЗАД: окно 3 с; боец сдвинулся > 1.5 м против хода отряда ──────
		if f % 180 == 0:
			for s in alive:
				var men2: Array = _members(s)
				var c2: Vector3 = _median(men2)
				var cp: Variant = w_cen.get(s)
				w_cen[s] = c2
				var D: Vector3 = (c2 - (cp as Vector3)) if cp != null else Vector3.ZERO
				var squad_moves: bool = D.length() > 3.0 and not _fighting(s)
				for u2 in men2:
					var uu := u2 as Unit
					var p2: Vector3 = uu.global_position
					var pp: Variant = w_pos.get(uu)
					w_pos[uu] = p2
					var back := false
					if squad_moves and pp != null and uu.state != Unit.State.ATTACKING \
							and not uu.retreating and not uu._panicked:
						var d: Vector3 = p2 - (pp as Vector3)
						d.y = 0.0
						if d.length() > 1.5 and d.normalized().dot(Vector3(D.x, 0.0, D.z).normalized()) < -0.3:
							back = true
					var br: int = (int(back_run.get(uu, 0)) + 1) if back else 0
					back_run[uu] = br
					if br == 2:
						back_n += 1
						if back_n <= 3:
							print("      назад: отряд %d (%s) боец (%.1f, %.1f), отряд идёт (%.1f, %.1f)/3с, состояние %d, пост (%.0f, %.0f), путь %d" % [
								s, uu.stat_id, p2.x, p2.z, D.x, D.z, int(uu.state), uu.post_pos.x, uu.post_pos.z, uu._route.size()])
					if float(br) * 3.0 > back_s:
						back_s = float(br) * 3.0
						back_who = "отряд %d (%s)" % [s, uu.stat_id]
		# ── ЗАСТРЯЛ: окно 6 с; отряд ушёл > 6 м, боец < 0.4 м, позади тела ──
		if f % 360 == 0:
			var stk := 0
			for s3 in alive:
				var men3: Array = _members(s3)
				var c3: Vector3 = _median(men3)
				var cprev: Variant = st_cen.get(s3)
				st_cen[s3] = c3
				var moved: bool = cprev != null and c3.distance_to(cprev as Vector3) > 6.0
				# Отряд в бою не «застревает»: стоящий в свалке в 8 м от медианы —
				# это бой, а не затор в пути (нога 2 краснела у рудника красного)
				if _fighting(s3):
					continue
				for u3 in men3:
					var p3: Vector3 = (u3 as Unit).global_position
					var prev: Variant = st_pos.get(u3)
					st_pos[u3] = p3
					if moved and prev != null and p3.distance_to(prev as Vector3) < 0.4 \
							and (u3 as Unit).state != Unit.State.ATTACKING \
							and Vector2(p3.x - c3.x, p3.z - c3.z).length() > 8.0:
						stk += 1
			stuck = maxi(stuck, stk)
			var ac: Vector3 = _army_median(alive)
			var men_n := 0
			for s5 in alive:
				men_n += _members(s5).size()
			print("    [%s] t=%3d с: армия (%.0f, %.0f) до цели %.0f м, отрядов %d, бойцов %d, у цели %d, в бою %d, застрявших %d" % [
				tag, f / 60, ac.x, ac.z, Vector2(ac.x - dest.x, ac.z - dest.z).length(), alive.size(), men_n, near,
				_count_fighting(alive), stk])
		if arrived < 0 and near >= int(ceil(float(alive.size()) * 0.8)):
			arrived = f
			if stop_on_arrival:
				break
	var men1 := 0
	for s6 in sids:
		men1 += _members(int(s6)).size()
	var ft: Dictionary = _ft_report(tag)
	print("    [%s] итог: %s; отрыв вне брода до %.1f с, у брода до %.1f с; назад ≥6 с: %d бойцов (дольше всего %.0f с %s); застрявших до %d; в воде %d; рядом с врагом не в бою до %.1f с %s; в бою побывало отрядов %d; потери %d из %d" % [
		tag, ("дошли за %d с" % (arrived / 60)) if arrived >= 0 else "НЕ дошли", det_s, det_ford_s, back_n, back_s, back_who,
		stuck, water, ign_s, ign_who, fought.size(), men0 - men1, men0])
	return {"arrived": arrived, "det_s": det_s, "det_ford_s": det_ford_s, "back_n": back_n, "back_s": back_s,
		"stuck": stuck, "water": water, "ign_s": ign_s, "fought": fought.size(), "ft": ft, "frames": f,
		"lost": men0 - men1}

func _count_fighting(sids: Array) -> int:
	var n := 0
	for s in sids:
		if _fighting(int(s)):
			n += 1
	return n

## Общие вердикты ноги
func _leg_verdicts(id: String, r: Dictionary, need_arrive: bool = true) -> void:
	if need_arrive:
		verdict("%s дошли до цели (%s)" % [id, ("%d с" % (int(r["arrived"]) / 60)) if int(r["arrived"]) >= 0 else "нет"],
			int(r["arrived"]) >= 0)
	verdict("%s разрыв не держится: отрыв > 10 м от тела ≤ 12 с вне брода (%.1f с), ≤ 15 с у брода (%.1f с)" % [
		id, float(r["det_s"]), float(r["det_ford_s"])], float(r["det_s"]) <= 12.0 and float(r["det_ford_s"]) <= 15.0)
	verdict("%s никто не бежит против хода отряда ≥ 6 с вне боя (%d бойцов)" % [id, int(r["back_n"])], int(r["back_n"]) == 0)
	verdict("%s застрявших нет (%d), в глубокую воду не зашли (%d)" % [id, int(r["stuck"]), int(r["water"])],
		int(r["stuck"]) == 0 and int(r["water"]) == 0)
	verdict("%s угрозу не игнорируют: живой враг в %d м, отряд не в бою ≤ %.0f с (%.1f с)" % [
		id, int(IGNORE_R), IGNORE_SEC, float(r["ign_s"])], float(r["ign_s"]) <= IGNORE_SEC)

# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	# Зеркальный пень (ТЗ 31.10.2026) стоит на пути армии к лагерю орды — окружение,
	# а не марш: стенд меряет марш на прежней расстановке
	preload("res://scripts/perf_config.gd").lair_layout_v2 = false
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
	sm = main.selection_manager
	cmd = sm.squad_commander()
	hud = main.hud
	_Opt.tick_meter = true
	# Красный ИИ и дикие — не переменная замера: ИИ заморожен, его войско
	# снято (постройки остаются — их и обходит/штурмует марш), тролли и
	# гноллы сняты, пни заморожены. Орда ЖИВАЯ (охрана рудников, лагерь)
	for k in ["enemy_ai", "gnoll_ai", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
			n.set_physics_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit and ((n0 as Unit).stat_id == "troll" or (n0 as Unit).stat_id == "gnoll"):
			(n0 as Unit).take_damage(1.0e12)
	_kill_faction(E)
	await pframes(4)
	if _only.contains("a"):
		await _block_a()
	if _only.contains("b"):
		await _block_b()
	if _only.contains("c"):
		await _block_c()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. СМЕШАННАЯ АРМИЯ: СТРОЙ ПО ЛИНИИ + ШЕСТЬ НОГ ATTACK-MOVE
# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. СМЕШАННАЯ АРМИЯ: СТРОЙ ПО ЛИНИИ И МАРШ [A] ЧЕРЕЗ ВСЮ КАРТУ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	var spot: Vector3 = base + Vector3(30.0, 0.0, 10.0)
	_clear_spot(spot, 30.0)
	var kinds := ["spearman", "spearman", "spearman", "spearman", "spearman", "spearman", "spearman",
		"warrior", "warrior", "warrior", "archer", "archer", "archer", "archer"]
	var sids: Array = []
	for i in range(kinds.size()):
		var st: Array = _staff(kinds[i])
		var at: Vector3 = spot + Vector3(-16.0 + float(i % 5) * 8.0, 0.0, -10.0 + float(i / 5) * 9.0)
		sids.append(_squad(kinds[i], F, at, int(st[0]), int(st[1])))
	await pframes(30)
	var men_n := 0
	for s in sids:
		men_n += _members(int(s)).size()
	print("    армия: %d отрядов, %d бойцов (штат из конфига найма)" % [sids.size(), men_n])
	await _select_sids(sids)
	# ── A1. СТРОЙ ПО ЛИНИИ (протяжка ПКМ) С ПЕРВОГО РАЗА ────────────────────
	var la := Vector3(spot.x - 22.0, 0.0, spot.z + 14.0)
	var lb := Vector3(spot.x + 22.0, 0.0, spot.z + 14.0)
	var all: Array = []
	for s in sids:
		all.append_array(_members(int(s)))
	var start: Dictionary = {}
	for u in all:
		start[u] = (u as Unit).global_position
	sm._execute_line_formation(la, lb)
	await pframes(3)
	var posts: Dictionary = {}
	var no_order := 0
	for u in all:
		posts[u] = (u as Unit).post_pos
		if Vector2((posts[u] as Vector3).x - (start[u] as Vector3).x, (posts[u] as Vector3).z - (start[u] as Vector3).z).length() < 0.3:
			no_order += 1
	# Посты разных отрядов не накладываются
	var overlap := 0
	for i in range(all.size()):
		var ui := all[i] as Unit
		for j in range(i + 1, all.size()):
			var uj := all[j] as Unit
			if ui.squad_id == uj.squad_id:
				continue
			var pi: Vector3 = posts[ui]
			var pj: Vector3 = posts[uj]
			if Vector2(pi.x - pj.x, pi.z - pj.z).length() < 0.3:
				overlap += 1
	await pframes(60 * 40)
	var inn := 0
	for u in all:
		var uu := u as Unit
		if not is_instance_valid(uu) or uu.is_dead():
			continue
		var pp: Vector3 = posts[uu]
		if Vector2(uu.global_position.x - pp.x, uu.global_position.z - pp.z).length() <= 1.5:
			inn += 1
	print("    строй по линии: на местах %d/%d, без приказа %d, наложений постов %d" % [inn, all.size(), no_order, overlap])
	verdict("A1 строй по линии с первого раза: приказ получили все (без приказа %d), посты не накладываются (%d)" % [no_order, overlap],
		no_order == 0 and overlap == 0)
	verdict("A1б через 40 с на своих местах ≥ 95 %% (%d/%d)" % [inn, all.size()], float(inn) >= 0.95 * float(all.size()))
	# ── НОГИ ────────────────────────────────────────────────────────────────
	var mines: Array = main.territory_mine_spots()
	var my_mine: Vector3 = mines[0] if (mines[0] as Vector3).z < 0.0 else mines[1]
	var red_mine: Vector3 = mines[1] if (mines[0] as Vector3).z < 0.0 else mines[0]
	var red_base: Vector3 = main.ENEMY_BASE_ANCHOR
	var rx: float = main.river_x(main.FORD_Z)
	var far_bank: Vector3 = _dry(Vector3(rx + 28.0, 0.0, main.FORD_Z))
	var far_lair := Vector3.INF
	for l in GameManager.troll_lairs:
		if is_instance_valid(l) and (l as Node3D).global_position.x > rx:
			far_lair = (l as Node3D).global_position
	if far_lair == Vector3.INF:
		far_lair = Vector3(rx + 100.0, 0.0, 80.0)
	var village: Vector3 = main.goblin_village_center()
	village.y = 0.0
	# 1. база → свой рудник
	var o1: Dictionary = await _am_order(_dry(my_mine + Vector3(-12.0, 0.0, 6.0)))
	verdict("A2 [A] с клавиатуры взводит режим, клик отдаёт Attack-Move всем (%d из %d) и снимает взвод" % [int(o1["am"]), int(o1["of"])],
		bool(o1["armed"]) and bool(o1["ok"]) and int(o1["am"]) == int(o1["of"]) and bool(o1["disarmed"]))
	var r1: Dictionary = await _leg("1 база→свой рудник", sids, my_mine, 200.0, 26.0)
	_leg_verdicts("A3 нога 1:", r1)
	# 2. → рудник красного; ЗАСАДА В ТУМАНЕ на полпути
	var amb_at: Vector3 = _dry((_army_median(_alive_sids(sids)) + red_mine) * 0.5)
	_clear_spot(amb_at, 12.0)
	var amb: Array = []
	for k in range(2):
		var st2: Array = _staff("spearman")
		amb.append(_squad("spearman", E, amb_at + Vector3(-5.0 + 10.0 * float(k), 0.0, 0.0), mini(int(st2[0]), 24), 6))
	await pframes(2)
	var fog = main.get("fog")
	var lit: bool = fog != null and fog.is_lit(amb_at.x, amb_at.z)
	print("    засада: 2 отряда красной пехоты в (%.0f, %.0f), в тумане: %s" % [amb_at.x, amb_at.z, str(not lit)])
	var o2: Dictionary = await _am_order(_dry(red_mine + Vector3(-12.0, 0.0, -6.0)))
	var amb_t0: int = Time.get_ticks_msec()
	var r2: Dictionary = await _leg("2 → рудник красного (засада)", sids, red_mine, 260.0, 26.0)
	var amb_left := 0
	for s in amb:
		amb_left += _members(int(s)).size()
	print("    засада: осталось %d бойцов" % amb_left)
	verdict("A4 засада в тумане (в тумане при приказе: %s) замечена и выбита на марше (осталось %d)" % [str(not lit), amb_left],
		amb_left == 0 and int(o2["am"]) == int(o2["of"]))
	_leg_verdicts("A5 нога 2:", r2)
	# 3. → база красного (проход в его лесной стене)
	await _select_sids(_alive_sids(sids))
	await _am_order(_dry(red_base + Vector3(26.0, 0.0, -6.0)))
	var r3: Dictionary = await _leg("3 → база красного", sids, red_base + Vector3(26.0, 0.0, -6.0), 220.0, 30.0)
	_leg_verdicts("A6 нога 3:", r3)
	# 4. → брод, дальний берег
	await _select_sids(_alive_sids(sids))
	await _am_order(far_bank)
	var r4: Dictionary = await _leg("4 → брод", sids, far_bank, 320.0, 26.0)
	_leg_verdicts("A7 нога 4:", r4)
	# 5. → дальний пень с ПЕРЕНАПРАВЛЕНИЕМ на лету
	var lair_pt: Vector3 = _dry(far_lair + Vector3(0.0, 0.0, -16.0))
	await _select_sids(_alive_sids(sids))
	await _am_order(lair_pt)
	await _leg("5а → пень (марш [A])", sids, lair_pt, 15.0, 26.0, false)
	var alive5: Array = _alive_sids(sids)
	var c5: Vector3 = _army_median(alive5)
	var redir: Vector3 = _dry(c5 + Vector3(0.0, 0.0, -35.0))
	var d0: Dictionary = {}
	for s in alive5:
		var m: Vector3 = _median(_members(s))
		d0[s] = Vector2(m.x - redir.x, m.z - redir.z).length()
	await _select_sids(alive5)
	sm.order_at_world(redir, false)
	await pframes(2)
	var still_am := 0
	for s in alive5:
		if cmd.is_attack_moving(s):
			still_am += 1
	await pframes(60 * 12)
	var closer := 0
	for s in alive5:
		var men5: Array = _members(s)
		if men5.is_empty():
			continue
		var m2: Vector3 = _median(men5)
		if float(d0[s]) - Vector2(m2.x - redir.x, m2.z - redir.z).length() > 8.0:
			closer += 1
	print("    перенаправление ПКМ: в [A] осталось %d из %d, за 12 с приблизились к новой точке %d" % [still_am, alive5.size(), closer])
	verdict("A8 перенаправление ПКМ на марше снимает [A] у всех (осталось %d)" % still_am, still_am == 0 and not sm.attack_move_armed)
	verdict("A8б армия разворачивается на новую точку (%d из %d приблизились > 8 м за 12 с)" % [closer, alive5.size()],
		float(closer) >= 0.9 * float(alive5.size()))
	# [A] дважды — второе нажатие снимает взвод (не залипает)
	await _key(KEY_A)
	var arm1: bool = sm.attack_move_armed
	await _key(KEY_A)
	var arm2: bool = sm.attack_move_armed
	verdict("A8в [A] переключается: первое нажатие взводит (%s), второе снимает (%s)" % [str(arm1), str(arm2)], arm1 and not arm2)
	await _am_order(lair_pt)
	var r5: Dictionary = await _leg("5б → пень после перенаправления", sids, lair_pt, 200.0, 26.0)
	_leg_verdicts("A9 нога 5:", r5)
	# 6. → лагерь орды
	await _select_sids(_alive_sids(sids))
	await _am_order(village)
	var r6: Dictionary = await _leg("6 → лагерь орды", sids, village, 300.0, 90.0)
	_leg_verdicts("A10 нога 6:", r6)
	var watch: Array = []
	for gn in get_tree().get_nodes_in_group(Constants.unit_group(G)):
		if is_instance_valid(gn) and not (gn as Unit).is_dead() and (gn as Unit).global_position.distance_to(village) < 120.0:
			watch.append(gn)
	_ft_reset()
	for _k in range(60 * 30):
		await get_tree().physics_frame
		_ft_tick()
	var g_dead := 0
	for gw in watch:
		if not is_instance_valid(gw) or (gw as Unit).is_dead():
			g_dead += 1
	_ft_report("бой у лагеря")
	verdict("A11 у лагеря идёт бой: орда несёт потери (пало %d из %d за 30 с)" % [g_dead, watch.size()], g_dead > 0)
	for s in sids:
		cmd.cancel_squad(int(s))
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)
	sm.clear_selection()
	await pframes(30)

# ═════════════════════════════════════════════════════════════════════════════
# B. МОНО-АРМИИ: КЛАВИШИ [S] [C] [A] [F1] И СТРОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _player_castle() -> Node:
	for b in get_tree().get_nodes_in_group(Constants.building_group(F)):
		if is_instance_valid(b) and b is Castle and String((b as Node).get_script().resource_path).ends_with("/Castle.gd"):
			return b
	return null

func _freeze_horde() -> void:
	for k in ["goblin_ai", "goblin_reserve"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
			n.set_physics_process(false)

func _in_place(sids: Array, r: float) -> Array:
	var inn := 0
	var tot := 0
	for s in sids:
		for u in _members(int(s)):
			var uu := u as Unit
			tot += 1
			if Vector2(uu.global_position.x - uu.post_pos.x, uu.global_position.z - uu.post_pos.z).length() <= r:
				inn += 1
	return [inn, tot]

func _block_b() -> void:
	print("\n═════ B. МОНО-АРМИИ: [S] [C] [A] [F1] И СТРОЙ ═════")
	_freeze_horde()
	# ЗАМОК ИГРОКА СТЕНД СТАВИТ САМ: при прямой загрузке Main.tscn у игрока
	# нет ни одной постройки (крепость ставит игрок первым кликом зоны
	# старта), а [F1] без крепости законно молчит (_on_send_to_castle)
	var castle: Node = _player_castle()
	if castle == null:
		var cp: Vector3 = main.PLAYER_BASE_ANCHOR
		main._clear_area_of_resources(cp, 12.0)
		main._clear_trees(cp, 12.0)
		var cb: Building = load("res://scripts/Castle.gd").new()
		cb.faction = F
		main.world_add(cb)
		cb.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
		await pframes(4)
		castle = cb
	for kind in ["spearman", "archer", "warrior"]:
		var p := Vector3(-110.0, 0.0, -22.0)
		var dest := Vector3(-55.0, 0.0, -22.0)
		_clear_spot((p + dest) * 0.5, 50.0)
		_kill_units_near(G, (p + dest) * 0.5, 70.0)
		await pframes(4)
		var st: Array = _staff(kind)
		var sids: Array = []
		for i in range(4):
			sids.append(_squad(kind, F, p + Vector3(0.0, 0.0, -18.0 + 12.0 * float(i)), int(st[0]), int(st[1])))
		await pframes(20)
		await _select_sids(sids)
		var tag: String = "B[%s]" % kind
		print("\n  ── %s: 4 отряда по %d ──" % [tag, int(st[0])])
		# [S]
		await _key(KEY_S)
		var st_s: String = String(sm.selection_stance())
		var hud_s: String = String(hud.active_squad_cmd())
		verdict("%s1 [S]: стойка «защита» (%s), рамка HUD «%s»" % [tag, st_s, hud_s],
			st_s == _UCfg.STANCE_DEFENSE and hud_s == "S")
		# Строй по линии в [S]: держится, никто не выбегает
		sm._execute_line_formation(p + Vector3(8.0, 0.0, -24.0), p + Vector3(8.0, 0.0, 24.0))
		await pframes(60 * 30)
		var ip: Array = _in_place(sids, 1.5)
		verdict("%s2 строй по линии в [S]: на местах ≥ 90 %% (%d/%d)" % [tag, int(ip[0]), int(ip[1])],
			float(ip[0]) >= 0.9 * float(ip[1]))
		# [C]
		await _key(KEY_C)
		var st_c: String = String(sm.selection_stance())
		var hud_c: String = String(hud.active_squad_cmd())
		verdict("%s3 [C]: стойка «атака» (%s), рамка «%s»" % [tag, st_c, hud_c], st_c == _UCfg.STANCE_ATTACK and hud_c == "C")
		# [A] сквозь заслон: два отряда красной пехоты на пути
		var block_at: Vector3 = (p + dest) * 0.5
		var foes: Array = []
		for k in range(2):
			foes.append(_squad("spearman", E, block_at + Vector3(0.0, 0.0, -8.0 + 16.0 * float(k)), 15, 5))
		await pframes(2)
		var o: Dictionary = await _am_order(dest)
		var hud_a: String = String(hud.active_squad_cmd())
		verdict("%s4 [A]+клик: Attack-Move у всех (%d из %d), взвод снят, рамка «%s»" % [tag, int(o["am"]), int(o["of"]), hud_a],
			bool(o["armed"]) and int(o["am"]) == int(o["of"]) and bool(o["disarmed"]) and hud_a == "A")
		var r: Dictionary = await _leg(tag + " [A]", sids, dest, 150.0, 18.0)
		var foe_left := 0
		for fs in foes:
			foe_left += _members(int(fs)).size()
		verdict("%s5 заслон выбит на марше (осталось %d), дошли (%s)" % [tag, foe_left,
			("%d с" % (int(r["arrived"]) / 60)) if int(r["arrived"]) >= 0 else "нет"], foe_left == 0 and int(r["arrived"]) >= 0)
		verdict("%s6 марш без разрывов/застрявших/бегущих назад (отрыв %.1f с, назад %d, застрявших %d)" % [
			tag, float(r["det_s"]), int(r["back_n"]), int(r["stuck"])],
			float(r["det_s"]) <= 12.0 and int(r["back_n"]) == 0 and int(r["stuck"]) == 0)
		await pframes(60 * 8)
		var ip2: Array = _in_place(sids, 2.0)
		verdict("%s7 строй по прибытии сохранён: на местах ≥ 85 %% (%d/%d)" % [tag, int(ip2[0]), int(ip2[1])],
			float(ip2[0]) >= 0.85 * float(ip2[1]))
		# [F1] — в замок
		await _select_sids(_alive_sids(sids))
		await _key(KEY_F1)
		await pframes(4)
		var tc := 0
		for s in sids:
			if GameManager.squad_is_to_castle(int(s)):
				tc += 1
		var hud_f: String = String(hud.active_squad_cmd())
		verdict("%s8 [F1]: отряды идут в замок (%d из %d), рамка «%s»" % [tag, tc, sids.size(), hud_f], tc == sids.size() and hud_f == "F1")
		# Крепость в ~140 м от площадки: шаг отхода ~1.5 м/с — 95 с дороги плюс
		# очередь у ворот (DOOR_PATIENCE); потолок 240 с. ЗДОРОВЫЙ ПОЛНЫЙ ОТРЯД
		# ЗАМОК ВЫПУСКАЕТ СРАЗУ (GARRISON_AUTO_RELEASE: лечить и пополнять
		# нечего) — «вошли» судится по ПИКУ доли бойцов внутри (замер раз в
		# 0.5 с), а не по одновременному присутствию всех четырёх
		var f := 0
		var peak: Dictionary = {}
		for s in sids:
			peak[int(s)] = 0.0
		while f < 60 * 240:
			await pframes(30)
			f += 30
			var all_in := true
			for s in sids:
				var sq: Variant = GameManager.squads.get(int(s))
				if sq == null:
					continue
				var tot := 0
				var gar := 0
				for m in ((sq as Dictionary)["members"] as Array):
					if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
						tot += 1
						if (m as Unit).garrisoned:
							gar += 1
				var fr: float = float(gar) / float(maxi(tot, 1))
				peak[int(s)] = maxf(float(peak[int(s)]), fr)
				if float(peak[int(s)]) < 0.9:
					all_in = false
			if all_in:
				break
		var ok_n := 0
		var pk := ""
		for s2 in sids:
			if float(peak[int(s2)]) >= 0.9:
				ok_n += 1
			pk += "%.0f%% " % (float(peak[int(s2)]) * 100.0)
			# Кто не вошёл: отставшие снаружи
			var sq2: Variant = GameManager.squads.get(int(s2))
			if sq2 != null and castle != null and is_instance_valid(castle):
				for m2 in ((sq2 as Dictionary)["members"] as Array):
					if m2 != null and is_instance_valid(m2) and not (m2 as Unit).is_dead() and not (m2 as Unit).garrisoned 							and (m2 as Unit).global_position.distance_to(castle._gate_position()) > 8.0:
						var uu2 := m2 as Unit
						print("      снаружи: отряд %d боец (%.0f, %.0f), до ворот %.0f м, состояние %d, цель %s, отход %s, путь %d" % [
							int(s2), uu2.global_position.x, uu2.global_position.z, uu2.global_position.distance_to(castle._gate_position()),
							int(uu2.state), str(uu2.attack_target), str(uu2.retreating), uu2._route.size()])
		print("    %s: пик доли внутри по отрядам: %s(за %d с)" % [tag, pk, f / 60])
		verdict("%s9 [F1]: отряды дошли и приняты замком — пик ≥ 90 %% бойцов внутри у %d из %d за ≤ 240 с" % [tag, ok_n, sids.size()], ok_n == sids.size())
		if castle != null and is_instance_valid(castle):
			for s in sids:
				castle.release_garrison(int(s))
		await pframes(10)
		for s in sids:
			cmd.cancel_squad(int(s))
			for u in _members(int(s)):
				(u as Unit).take_damage(1.0e12)
		for fs in foes:
			for u in _members(int(fs)):
				(u as Unit).take_damage(1.0e12)
		sm.clear_selection()
		await pframes(20)

# ═════════════════════════════════════════════════════════════════════════════
# C. ТУШИ
# ═════════════════════════════════════════════════════════════════════════════
func _expected_hit(victim: Unit, amount: float) -> float:
	var td: float = victim.defense + victim.armor \
		+ GameManager.get_upgrade(victim.faction, "defense") \
		+ GameManager.unit_bonus(victim.faction, victim.stat_id, "bonus_armor") \
		+ GameManager.unit_bonus(victim.faction, victim.stat_id, "bonus_defense") \
		+ victim.vet_armor + victim.vet_defense \
		+ _UCfg.stance_stat(victim.stance, "defense_bonus", 0.0)
	return maxf(amount * Unit.MIN_DAMAGE_FRACTION, _UCfg.damage_after_armor(amount, td))

func _block_c() -> void:
	print("\n═════ C. ТУШИ: УРОН, АНИМАЦИЯ, МАРШ, БОЙ ПОД НАГРУЗКОЙ ═════")
	_freeze_horde()
	# Площадка — подальше от пня (−151, 0): его овцы в 60 м уводили
	# стоящую тушу на охоту с лентой удара (ложное «залипание» C5)
	var p := Vector3(-70.0, 0.0, 30.0)
	_clear_spot(p, 60.0)
	_kill_units_near(G, p, 80.0)
	for sh in get_tree().get_nodes_in_group("sheep"):
		if is_instance_valid(sh) and (sh as Node3D).global_position.distance_to(p) < 140.0:
			(sh as Node).queue_free()
	await pframes(4)
	# ── C1. УРОН СВИПА ПО ФОРМУЛЕ ───────────────────────────────────────────
	var big: Unit = _unit("big_goblin", G, p)
	var vs: Array = []
	for k in range(5):
		var a: float = deg_to_rad(-40.0 + 20.0 * float(k))
		var v: Unit = _unit("spearman", F, p + Vector3(cos(a), 0.0, sin(a)) * 2.6)
		v.set_tick(false)
		vs.append(v)
	await pframes(4)
	big.command_attack(vs[2], true, false, true)
	var hp: Dictionary = {}
	for v in vs:
		hp[v] = (v as Unit).current_health
	var hits: Array = []       # [кадр, жертва, урон]
	var anim_attack_frames := 0
	var f := 0
	var sw0: int = big.sweeps
	while f < 60 * 14:
		await get_tree().physics_frame
		f += 1
		if is_instance_valid(big) and String(big.anim_shown()).begins_with("attack"):
			anim_attack_frames += 1
		for v in vs:
			if not is_instance_valid(v):
				continue
			var h: float = (v as Unit).current_health
			if h < float(hp[v]) - 0.01:
				# Ожидание — в момент удара, пока жертва жива (правило 5: позже
				# узел может быть освобождён); добивающий удар режется остатком
				hits.append([f, _expected_hit(v as Unit, big.attack_damage + big._upgrade_damage_bonus()),
					float(hp[v]) - h, h <= 0.0 or (v as Unit).is_dead()])
			hp[v] = h
	var dmg_cfg: float = big.attack_damage + big._upgrade_damage_bonus()
	var bad := 0
	var worst := 0.0
	var exp0 := 0.0
	var frames_multi: Dictionary = {}
	for h in hits:
		var expv: float = float(h[1])
		exp0 = expv
		# Добивающий удар режется остатком здоровья — его не сверяем
		if bool(h[3]) and float(h[2]) < expv - 0.01:
			continue
		worst = maxf(worst, absf(float(h[2]) - expv))
		if absf(float(h[2]) - expv) > 0.01 * expv:
			bad += 1
		frames_multi[int(h[0])] = int(frames_multi.get(int(h[0]), 0)) + 1
	var multi := 0
	for k2 in frames_multi:
		multi = maxi(multi, int(frames_multi[k2]))
	# Комбо: два удара с паузой ~BIG_COMBO_GAP
	var hit_frames: Array = frames_multi.keys()
	hit_frames.sort()
	var combo := 0
	for i in range(1, hit_frames.size()):
		var gap: float = float(int(hit_frames[i]) - int(hit_frames[i - 1])) / 60.0
		if absf(gap - _GobCfg.BIG_COMBO_GAP) < 0.2:
			combo += 1
	print("    туша: удар %.1f, свипов %d, попаданий %d, ожидаемый урон по копейщику %.2f, худшее расхождение %.3f; накрыто за взмах до %d; комбо-пар %d; кадров с лентой удара %d" % [
		dmg_cfg, big.sweeps - sw0, hits.size(), exp0, worst, multi, combo, anim_attack_frames])
	verdict("C1 урон свипа совпадает с формулой брони жертвы (расхождений %d из %d, худшее %.3f)" % [bad, hits.size(), worst],
		hits.size() > 0 and bad == 0)
	verdict("C2 свип — сектор: накрывает нескольких за взмах (до %d, потолок %d)" % [multi, _GobCfg.BIG_SWEEP_MAX],
		multi >= 2 and multi <= _GobCfg.BIG_SWEEP_MAX)
	verdict("C3 комбо: двойной удар с паузой %.2f с встречается (%d)" % [_GobCfg.BIG_COMBO_GAP, combo], combo >= 1)
	verdict("C4 лента удара играет (кадров %d)" % anim_attack_frames, anim_attack_frames > 0)
	# Жертв нет — лента удара отпускается
	for v in vs:
		if is_instance_valid(v):
			(v as Unit).take_damage(1.0e12)
	# Последняя жертва пала — вокруг туши нет глаз игрока, туман прячет её
	# и усыпляет по картинке (fog_sleep) с той лентой, что была; это штатно:
	# на свет её выводит wake_for_lod с пересчётом позы. Здесь — тот самый
	# «игрок вернулся»: будим и смотрим, что лента отпущена
	var stuck_attack := 0
	for _k in range(60 * 4):
		await get_tree().physics_frame
	var hidden_asleep: bool = is_instance_valid(big) and big._proc_sleeping and big._hp_fog_hidden
	# Глаза игрока: замороженный лучник в 14 м светит туман (обзор 24 м);
	# туша пойдёт на него (агро 18 м), но до удара ей ~7 с хода — окно 1 с
	# после выхода на свет чистое
	var eye: Unit = _unit("archer", F, p + Vector3(0.0, 0.0, 14.0))
	eye.set_tick(false)
	await pframes(20)
	for _k2 in range(60):
		await get_tree().physics_frame
		if is_instance_valid(big) and String(big.anim_shown()).begins_with("attack"):
			stuck_attack += 1
	verdict("C5 без целей лента удара отпущена, когда тушу снова видно (спала под туманом: %s; кадров удара за 1 с на свету: %d, лента «%s»)" % [
		str(hidden_asleep), stuck_attack, String(big.anim_shown()) if is_instance_valid(big) else "-"], stuck_attack == 0)
	if is_instance_valid(eye):
		eye.take_damage(1.0e12)
	big.take_damage(1.0e12)
	await pframes(10)
	# ── C6. МАРШ ТУШ С ЭСКОРТОМ ─────────────────────────────────────────────
	var gsids: Array = []
	var bsids: Array = []
	for k3 in range(4):
		var at: Vector3 = p + Vector3(-20.0, 0.0, -24.0 + 14.0 * float(k3))
		bsids.append(_squad("big_goblin", G, at, 5, _GobCfg.BIG_SQUAD_COLS, _GobCfg.BIG_SQUAD_SPACING))
		gsids.append(_squad("goblin_spearman", G, at + Vector3(-8.0, 0.0, 0.0), 30, 6, 0.9))
	await pframes(20)
	var mdest: Vector3 = p + Vector3(60.0, 0.0, 0.0)
	_clear_spot(mdest, 40.0)
	var all_sids: Array = bsids + gsids
	var shift: Vector3 = mdest - _army_median(all_sids)
	for s in all_sids:
		for u in _members(int(s)):
			(u as Unit).command_move((u as Unit).global_position + shift, false)
	var min_gap := INF
	var overlap_run := 0
	var overlap_worst := 0
	var r: Dictionary = {}
	_ft_reset()
	var f2 := 0
	var stuck := 0
	var water := 0
	var prevp: Dictionary = {}
	while f2 < 60 * 90:
		await get_tree().physics_frame
		_ft_tick()
		f2 += 1
		if f2 % 30 != 0:
			continue
		var bigs: Array = []
		for s in bsids:
			bigs.append_array(_members(int(s)))
		var ov := false
		for i in range(bigs.size()):
			for j in range(i + 1, bigs.size()):
				var d: float = Vector2((bigs[i] as Unit).global_position.x - (bigs[j] as Unit).global_position.x,
					(bigs[i] as Unit).global_position.z - (bigs[j] as Unit).global_position.z).length()
				min_gap = minf(min_gap, d)
				if d < 0.5:
					ov = true
		overlap_run = overlap_run + 1 if ov else 0
		overlap_worst = maxi(overlap_worst, overlap_run)
		for b in bigs:
			var bp: Vector3 = (b as Unit).global_position
			if main.is_water(bp.x, bp.z) and not main.in_ford(bp.z):
				water += 1
		if f2 % 360 == 0:
			var stk := 0
			for b2 in bigs:
				var bp2: Vector3 = (b2 as Unit).global_position
				var pv: Variant = prevp.get(b2)
				prevp[b2] = bp2
				if pv != null and bp2.distance_to(pv as Vector3) < 0.3 \
						and Vector2(bp2.x - ((b2 as Unit).post_pos.x), bp2.z - ((b2 as Unit).post_pos.z)).length() > 4.0:
					stk += 1
			stuck = maxi(stuck, stk)
		var arrived := 0
		for b3 in bigs:
			if Vector2((b3 as Unit).global_position.x - (b3 as Unit).post_pos.x, (b3 as Unit).global_position.z - (b3 as Unit).post_pos.z).length() < 4.0:
				arrived += 1
		if arrived == bigs.size() and f2 > 120:
			r["arrived"] = f2
			break
	_ft_report("марш туш")
	var bigs_n := 0
	for s in bsids:
		bigs_n += _members(int(s)).size()
	print("    марш туш: дошли %s, мин. расстояние между тушами %.2f м, наложение (< 0.5 м) подряд до %.1f с, застрявших %d, в воде %d" % [
		("за %d с" % (int(r["arrived"]) / 60)) if r.has("arrived") else "НЕТ", min_gap, float(overlap_worst) * 0.5, stuck, water])
	verdict("C6 туши с эскортом дошли строем (все %d в 4 м от поста)" % bigs_n, r.has("arrived"))
	verdict("C7 туши не стоят друг в друге (наложение < 0.5 м держится ≤ 1 с: %.1f с), не застревают (%d), не в воде (%d)" % [
		float(overlap_worst) * 0.5, stuck, water], overlap_worst <= 2 and stuck == 0 and water == 0)
	# ── C8. БОЙ ПОД НАГРУЗКОЙ: туши + эскорт против смешанной армии ─────────
	var army: Array = []
	var front: Vector3 = mdest + Vector3(30.0, 0.0, 0.0)
	var ak := ["spearman", "spearman", "spearman", "spearman", "warrior", "warrior", "archer", "archer"]
	for i in range(ak.size()):
		var st: Array = _staff(ak[i])
		army.append(_squad(ak[i], F, front + Vector3(float(i / 4) * 10.0, 0.0, -24.0 + 12.0 * float(i % 4)), int(st[0]), int(st[1])))
	await pframes(10)
	var hp0 := 0.0
	var men0: Array = []
	for s in army:
		for u in _members(int(s)):
			men0.append(u)
			hp0 += (u as Unit).current_health
	var big0: Array = []
	var bhp0 := 0.0
	var swept0 := 0
	for s in bsids:
		for b in _members(int(s)):
			big0.append(b)
			bhp0 += (b as Unit).current_health
			swept0 += int(b.swept_total)
	var foe_mid: Vector3 = _army_median(army)
	for s in all_sids:
		var tgt: Array = _members(int(army[0]))
		for u in _members(int(s)):
			var near_t: Unit = null
			var bd := INF
			for s2 in army:
				for t in _members(int(s2)):
					var d2: float = (t as Unit).global_position.distance_squared_to((u as Unit).global_position)
					if d2 < bd:
						bd = d2
						near_t = t
			if near_t != null:
				(u as Unit).command_attack(near_t, true, false, true)
	_ft_reset()
	var anim_bad := 0
	for k4 in range(60 * 60):
		await get_tree().physics_frame
		_ft_tick()
		# Лента туши — только из её набора (не «пусто»)
		if k4 % 60 == 0:
			for b in big0:
				if is_instance_valid(b) and not (b as Unit).is_dead() and String((b as Unit).anim_shown()) == "":
					anim_bad += 1
	var ft: Dictionary = _ft_report("бой туш под нагрузкой")
	var hp1 := 0.0
	for u in men0:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			hp1 += (u as Unit).current_health
	var bhp1 := 0.0
	var swept1 := 0
	for b in big0:
		if is_instance_valid(b) and not (b as Unit).is_dead():
			bhp1 += (b as Unit).current_health
			swept1 += int(b.swept_total)
	print("    бой: урон армии %.0f, урон тушам %.0f, накрытий свипом %d (живыми тушами), лент без имени %d" % [
		hp0 - hp1, bhp0 - bhp1, swept1, anim_bad])
	verdict("C8 бой туш под нагрузкой идёт в обе стороны (армии %.0f, тушам %.0f)" % [hp0 - hp1, bhp0 - bhp1],
		hp0 - hp1 > 0.0 and bhp0 - bhp1 > 0.0)
	verdict("C9 лента туши всегда из набора (пустых %d)" % anim_bad, anim_bad == 0)
	print("    (справочно) физкадр боя p99 %.1f мс, худший %.1f мс" % [float(ft["p99"]), float(ft["max"])])
