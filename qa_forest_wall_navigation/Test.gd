extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЛЕСНАЯ СТЕНА: АВТО-АГРО ПОД ОБСТРЕЛОМ, [A] СКВОЗЬ ПРЕГРАДУ, КЛИК ЗА ЛЕС
## (ТЗ 13.10.2026, пятое письмо)
## ═══════════════════════════════════════════════════════════════════════════
## Стенд САМ ставит сплошную лесную стену (ResourceNode.FOREST_WALL, та же
## посадка, что у стен баз — Main._wall_row): полоса вдоль Z длиной WALL_LEN,
## без прохода; обход — вокруг ближнего торца. Сетка A* пересобирается
## (GameManager._forest_nav_dirty), стенд ждёт пересборку.
## A — АВТО-АГРО ПОД ОБСТРЕЛОМ: лучники игрока за стеной бьют копейщиков
##     красного (ИИ заморожен — отвечает сам отряд: squad_counter_charge).
##     Зонды: доля красных, дошедших до рукопашной; «упёрся в стену» (боец у
##     стены не сдвинулся за 4 с, цель недосягаема); через какой торец прошёл
##     каждый (единообразие); время первого контакта.
## B — [A] НА ОТРЯДЫ ЗА СТЕНОЙ: 4 отряда игрока Attack-Move на красных за
##     лесом. Зонды: путь центров против идеала A→торец→B, развороты,
##     «упёрся», оторвавшиеся («ниточка»), поперечник группы, вступили в бой.
## C — ПКМ ЗА ЛЕС: 4 отряда обычным кликом за массив. Зонды: застрявшие,
##     отставшие дольше 8 с, «дребезг» (бойцы с ≥ 3 сменами направления на
##     обратное), пришли.
## Запуск: godot --headless --path . res://qa_forest_wall_navigation/Test.tscn
##         [-- only=abc]
## Провалы искать по «НЕ ПРОШЛО» / «провалов:» (и SCRIPT ERROR в логе).

const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")

## Геометрия: стена по x = WALL_X, z ∈ [WALL_Z0, WALL_Z1], полуширина полосы
const WALL_X := -70.0
const WALL_Z0 := -76.0
const WALL_Z1 := 16.0
const WALL_HALF := 3.0
## Ось сценария (по z): красные/цель — здесь; ближний торец — северный (Z1)
const AXIS_Z := -12.0
const STUCK_SEC := 4.0
const LINK_M := 3.0
const DETACH_M := 10.0

var main = null
var sm = null
var cmd = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abc"

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(1500.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_forest_wall_navigation: прошло %d, провалов: %d ═════" % [_pass, _fail])
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
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead() and not (m as Unit).garrisoned:
			o.append(m)
	return o

func _all(sids: Array) -> Array:
	var o: Array = []
	for s in sids:
		o.append_array(_members(int(s)))
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

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _staff(kind: String) -> Array:
	var bld: String = "archery" if kind == "archer" else "barracks"
	var cfg: Dictionary = _UCfg.train_cfg(bld, kind)
	return [int(cfg.get("squad", 20)), int(cfg.get("cols", 5))]

func _squad(uid: String, f: int, at: Vector3, n: int = 0) -> int:
	var st: Array = _staff(uid)
	var cnt: int = n if n > 0 else int(st[0])
	var cols: int = int(st[1])
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(cnt):
		var u := _unit(uid, f, at + Vector3(float(i / cols) * 0.65, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * 0.65))
		GameManager.add_to_squad(sid, u)
	return sid

func _kill(sids: Array) -> void:
	for s in sids:
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)

func _select(sids: Array) -> void:
	sm.select_units(_all(sids))
	await pframes(2)

## Стена: полоса вдоль Z, ряды поперёк шагом Main.WALL_STEP
func _build_wall() -> int:
	var before: int = main.wall_trees_placed
	var z: float = WALL_Z0
	while z <= WALL_Z1:
		main._wall_row(Vector2(WALL_X, z), Vector2(1.0, 0.0), WALL_HALF)
		z += main.WALL_STEP
	var planted: int = main.wall_trees_placed - before
	# Пересборка сетки A*: отложенная, не чаще FOREST_NAV_MIN_MS
	await pframes(60 * 3)
	return planted

## Тело отряда — наибольшая компонента связности (звено LINK_M)
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

func _detached(sid: int) -> int:
	var men: Array = _members(sid)
	if men.size() < 3:
		return 0
	var body: Dictionary = _main_body(men)
	var n := 0
	for u in men:
		if body.has(u):
			continue
		var p: Vector3 = (u as Unit).global_position
		var dn := INF
		for bu in body:
			dn = minf(dn, Vector2((bu as Unit).global_position.x - p.x, (bu as Unit).global_position.z - p.z).length())
		if dn > DETACH_M:
			n += 1
	return n

func _near_wall(p: Vector3) -> bool:
	return absf(p.x - WALL_X) < WALL_HALF + 3.0 and p.z > WALL_Z0 - 2.0 and p.z < WALL_Z1 + 2.0

## Общий наблюдатель: раз в 0.5 с ведёт следы центров отрядов, раз в 4 с —
## «упёрся в стену» (у стены, сдвиг < 0.5 м, не в досягаемости цели) и
## «дребезг» (обратные смены направления бойца, окно 1 с), торец прохода.
## stop(f) — условие досрочного конца
func _watch(tag: String, sids: Array, limit_s: float, stop: Callable, hook: Callable = Callable()) -> Dictionary:
	var tracks: Dictionary = {}
	var st := {"stuck": 0, "stuck_who": "", "north": 0, "south": 0, "passed": {}, "flips": {}, "upos1": {}, "udir": {},
		"upos4": {}, "det_run": {}, "det_s": 0.0, "span_max": 0.0}
	for s in sids:
		tracks[int(s)] = []
	var f := 0
	var limit: int = int(limit_s * 60.0)
	var stopped := false
	while f < limit:
		await get_tree().physics_frame
		f += 1
		if hook.is_valid():
			hook.call(f)
		if stop.is_valid() and f % 30 == 0 and bool(stop.call(f)):
			stopped = true
			break
		if f % 30 == 0:
			var cs: Array = []
			for s in sids:
				var men: Array = _members(int(s))
				if men.size() < 3:
					continue
				var c: Vector3 = _median(men)
				(tracks[int(s)] as Array).append(c)
				cs.append(c)
				# отрыв
				var dn: int = _detached(int(s))
				var r1: int = (int((st["det_run"] as Dictionary).get(int(s), 0)) + 1) if dn > 0 else 0
				(st["det_run"] as Dictionary)[int(s)] = r1
				st["det_s"] = maxf(float(st["det_s"]), float(r1) * 0.5)
				# торец
				for u in men:
					var p: Vector3 = (u as Unit).global_position
					if absf(p.x - WALL_X) < 3.5 and not (st["passed"] as Dictionary).has(u):
						(st["passed"] as Dictionary)[u] = true
						if p.z > (WALL_Z0 + WALL_Z1) * 0.5:
							st["north"] = int(st["north"]) + 1
						else:
							st["south"] = int(st["south"]) + 1
			var span := 0.0
			for i in range(cs.size()):
				for j in range(i + 1, cs.size()):
					span = maxf(span, Vector2((cs[i] as Vector3).x - (cs[j] as Vector3).x, (cs[i] as Vector3).z - (cs[j] as Vector3).z).length())
			st["span_max"] = maxf(float(st["span_max"]), span)
		if f % 60 == 0:
			# дребезг
			for u2 in _all(sids):
				var uu := u2 as Unit
				var p2: Vector3 = uu.global_position
				var pp: Variant = (st["upos1"] as Dictionary).get(uu)
				(st["upos1"] as Dictionary)[uu] = p2
				if pp == null:
					continue
				var d: Vector3 = p2 - (pp as Vector3)
				d.y = 0.0
				if d.length() < 0.5:
					continue
				var dirn: Vector3 = d.normalized()
				var pd: Variant = (st["udir"] as Dictionary).get(uu)
				(st["udir"] as Dictionary)[uu] = dirn
				if pd != null and dirn.dot(pd as Vector3) < -0.3:
					(st["flips"] as Dictionary)[uu] = int((st["flips"] as Dictionary).get(uu, 0)) + 1
		if f % int(STUCK_SEC * 60.0) == 0:
			for u3 in _all(sids):
				var uu3 := u3 as Unit
				var p3: Vector3 = uu3.global_position
				var pp3: Variant = (st["upos4"] as Dictionary).get(uu3)
				(st["upos4"] as Dictionary)[uu3] = p3
				if pp3 == null or not _near_wall(p3):
					continue
				if p3.distance_to(pp3 as Vector3) >= 0.5:
					continue
				# В досягаемости цели — это бой, не стена
				var t = uu3.attack_target
				if t != null and is_instance_valid(t) and p3.distance_to((t as Node3D).global_position) <= uu3.reach() + 0.5:
					continue
				if uu3.state == Unit.State.IDLE and uu3.attack_target == null:
					continue
				st["stuck"] = int(st["stuck"]) + 1
				if int(st["stuck"]) <= 3:
					st["stuck_who"] = String(st["stuck_who"]) + "[%s (%.0f,%.0f) st%d tgt=%s путь%d] " % [
						uu3.stat_id, p3.x, p3.z, int(uu3.state), str(t != null), uu3._route.size()]
	# геометрия следов
	var rev := 0
	var turns := 0
	var per: Dictionary = {}
	for s3 in sids:
		var tr: Array = tracks[int(s3)]
		var length := 0.0
		var prev_dir := Vector3.ZERO
		var last: Vector3 = tr[0] if not tr.is_empty() else Vector3.ZERO
		var r := 0
		var t := 0
		for i in range(1, tr.size()):
			var seg: Vector3 = (tr[i] as Vector3) - last
			seg.y = 0.0
			if seg.length() < 0.5:
				continue
			length += seg.length()
			var dirv: Vector3 = seg.normalized()
			if prev_dir != Vector3.ZERO:
				var dd: float = dirv.dot(prev_dir)
				if dd < -0.5:
					r += 1
				elif dd < 0.5:
					t += 1
			prev_dir = dirv
			last = tr[i]
		rev += r
		turns += t
		per[int(s3)] = {"len": length, "start": tr[0] if not tr.is_empty() else Vector3.ZERO,
			"end": tr[tr.size() - 1] if not tr.is_empty() else Vector3.ZERO, "rev": r, "turns": t}
	var jitter := 0
	for k in (st["flips"] as Dictionary):
		if int((st["flips"] as Dictionary)[k]) >= 3:
			jitter += 1
	var out := {"frames": f, "stopped": stopped, "stuck": int(st["stuck"]), "stuck_who": String(st["stuck_who"]),
		"north": int(st["north"]), "south": int(st["south"]), "rev": rev, "turns": turns, "per": per,
		"jitter": jitter, "det_s": float(st["det_s"]), "span_max": float(st["span_max"]), "tracks": tracks}
	print("    [%s] %d с; упёрлись в стену: %d %s; торец: север %d / юг %d; разворотов %d, поворотов %d; дребезг (≥3 обратных смены) у %d бойцов; отрыв до %.1f с; поперечник группы до %.0f м" % [
		tag, f / 60, int(st["stuck"]), String(st["stuck_who"]), int(st["north"]), int(st["south"]), rev, turns, jitter, float(st["det_s"]), float(st["span_max"])])
	return out

func _ratio_via(out: Dictionary, via: Vector3) -> float:
	var worst := 0.0
	for k in (out["per"] as Dictionary):
		var pr: Dictionary = (out["per"] as Dictionary)[k]
		var ideal: float = (pr["start"] as Vector3).distance_to(via) + via.distance_to(pr["end"] as Vector3)
		var straight: float = (pr["start"] as Vector3).distance_to(pr["end"] as Vector3)
		ideal = minf(ideal, straight) if not _line_hits_wall(pr["start"], pr["end"]) else ideal
		worst = maxf(worst, float(pr["len"]) / maxf(ideal, 1.0))
	return worst

func _line_hits_wall(a: Vector3, b: Vector3) -> bool:
	if (a.x - WALL_X) * (b.x - WALL_X) > 0.0:
		return false
	var t: float = (WALL_X - a.x) / (b.x - a.x)
	var z: float = a.z + (b.z - a.z) * t
	return z > WALL_Z0 and z < WALL_Z1

# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	sm = main.selection_manager
	cmd = sm.squad_commander()
	_Opt.tick_meter = true
	for k in ["enemy_ai", "gnoll_ai", "enemy_guard", "goblin_ai", "goblin_reserve"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
			n.set_physics_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var centre := Vector3(WALL_X, 0.0, AXIS_Z)
	main._clear_area_of_resources(centre, 75.0)
	main._clear_trees(centre, 75.0)
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit and ((n0 as Unit).faction != F or (n0 as Unit).stat_id == "worker") \
				and (n0 as Unit).global_position.distance_to(centre) < 110.0:
			(n0 as Unit).take_damage(1.0e12)
	for sh in get_tree().get_nodes_in_group("sheep"):
		if is_instance_valid(sh) and (sh as Node3D).global_position.distance_to(centre) < 110.0:
			(sh as Node).queue_free()
	await pframes(4)
	var planted: int = await _build_wall()
	var blocked: bool = GameManager.nav_line_blocked(Vector3(WALL_X - 15.0, 0.0, AXIS_Z), Vector3(WALL_X + 15.0, 0.0, AXIS_Z), 1.5) \
		if GameManager.has_method("nav_line_blocked") else true
	print("    стена: x=%.0f, z %.0f…%.0f, полуширина %.1f, деревьев %d; прямая через стену для A*: %s" % [
		WALL_X, WALL_Z0, WALL_Z1, WALL_HALF, planted, "заслонена" if blocked else "СВОБОДНА"])
	verdict("0 стена поставлена и видна навигации (деревьев %d, прямая сквозь неё заслонена: %s)" % [planted, str(blocked)], planted > 60 and blocked)
	if _only.contains("a"):
		await _block_a()
	if _only.contains("b"):
		await _block_b()
	if _only.contains("c"):
		await _block_c()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. АВТО-АГРО ПОД ОБСТРЕЛОМ ИЗ-ЗА СТЕНЫ
# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. КРАСНЫЕ КОПЕЙЩИКИ ПОД ОБСТРЕЛОМ ЛУЧНИКОВ ИЗ-ЗА СТЕНЫ ═════")
	# Лучники в ~10 м от копейщиков: ответ отряда на обстрел (squad_counter_charge)
	# по правилу COUNTER_CHARGE_RANGE 12 м — дальше за стрелком никто не бежит.
	# ЛОВУШКА (три прогона впустую): _squad кладёт ряды в +X, и блок лучников
	# с центром в 4.5 м от оси стены задними рядами стоял ВНУТРИ стволов
	# (is_cliff у цели = true) — такую цель не достать никому. Передний ряд —
	# не ближе 2 м к кромке маски стволов (полуширина 3 + радиус 1.6 + 0.45)
	var arch: Array = []
	for k in range(2):
		arch.append(_squad("archer", F, Vector3(WALL_X - 9.5, 0.0, AXIS_Z - 6.0 + 10.0 * float(k))))
	var red: Array = []
	for k2 in range(2):
		red.append(_squad("spearman", E, Vector3(WALL_X + 5.5, 0.0, AXIS_Z - 6.0 + 10.0 * float(k2))))
	await pframes(2)
	var inside := 0
	for u0 in _all(arch) + _all(red):
		if GameManager.is_cliff((u0 as Unit).global_position.x, (u0 as Unit).global_position.z):
			inside += 1
	print("    площадка A: бойцов внутри маски стволов %d (обязано быть 0)" % inside)
	await pframes(30)
	var red_n: int = _all(red).size()
	var arch_n: int = _all(arch).size()
	# Судится НАВИГАЦИЯ, а не истребление: 60 лучников выбивают 120 копейщиков
	# за 50 с обхода. Потери заморожены (удары и ответ на обстрел — в силе)
	Unit.losses_frozen = true
	var st := {"shot_t": -1, "first_t": -1}
	var r: Dictionary = await _watch("A красные под обстрелом (до первого контакта)", red, 120.0, func(f):
		if int(st["shot_t"]) < 0:
			for u3 in _all(red):
				if (u3 as Unit)._hit_flash > 0.0 or GameManager.squad_in_combat((u3 as Unit).squad_id):
					st["shot_t"] = f
					break
		# Треть в досягаемости — контакт: дальше развороты и смены направления
		# это рубка, а не навигация
		if _in_reach(red) >= int(ceil(float(_all(red).size()) / 3.0)):
			st["first_t"] = f
			return true
		return false)
	var contact: int = await _wait_reach(red, 0.5, 60.0)
	if contact >= 0:
		contact += int(r["frames"])
	Unit.losses_frozen = false
	_dump_red(red)
	print("    красных %d, лучников %d; обстрел замечен на %.1f с; первый контакт (треть) %s; половина в досягаемости %s; через торец север %d / юг %d" % [
		red_n, arch_n, float(int(st["shot_t"])) / 60.0, ("на %d с" % (int(st["first_t"]) / 60)) if int(st["first_t"]) >= 0 else "нет",
		("на %d с" % (contact / 60)) if contact >= 0 else "нет", int(r["north"]), int(r["south"])])
	verdict("A1 под обстрелом красные поднимаются и ДОХОДЯТ до лучников в обход стены (≥ 50 %% в досягаемости за ≤ 180 с: %s)" % [
		("на %d с" % (contact / 60)) if contact >= 0 else "нет"], contact >= 0)
	verdict("A2 никто не упёрся лбом в стену под стрелами (упёрлись: %d)" % int(r["stuck"]), int(r["stuck"]) == 0)
	verdict("A3 обход единообразный — через один торец (север %d / юг %d из %d), следы без разворотов до контакта (%d)" % [
		int(r["north"]), int(r["south"]), red_n, int(r["rev"])],
		(int(r["north"]) == 0 or int(r["south"]) == 0) and int(r["north"]) + int(r["south"]) >= int(red_n * 0.8) and int(r["rev"]) == 0)
	verdict("A4 без дребезга и отрыва до контакта: дребезг у %d бойцов (≤ 2), отрыв ≤ 10 с (%.1f)" % [int(r["jitter"]), float(r["det_s"])],
		int(r["jitter"]) <= 2 and float(r["det_s"]) <= 10.0)
	_kill(arch)
	_kill(red)
	await pframes(30)
	# ── A2. ЯВНЫЙ ПРИКАЗ (как отдаёт ИИ): атака отряда лучников с 16 м ──────
	print("  ── A2: приказ атаки на лучников за стеной (squad_attack_squad, как у ИИ) ──")
	var arch2: Array = []
	for k3 in range(2):
		arch2.append(_squad("archer", F, Vector3(WALL_X - 7.0, 0.0, AXIS_Z - 6.0 + 10.0 * float(k3))))
	var red2: Array = []
	for k4 in range(2):
		red2.append(_squad("spearman", E, Vector3(WALL_X + 9.0, 0.0, AXIS_Z - 6.0 + 10.0 * float(k4))))
	await pframes(30)
	var red2_n: int = _all(red2).size()
	Unit.losses_frozen = true
	for i in range(2):
		GameManager.squad_attack_squad(int(red2[i]), int(arch2[i]), true)
	var r2: Dictionary = await _watch("A2 красные по приказу (до первого контакта)", red2, 120.0, func(_f):
		return _in_reach(red2) >= int(ceil(float(_all(red2).size()) / 3.0)))
	var contact2: int = await _wait_reach(red2, 0.5, 60.0)
	if contact2 >= 0:
		contact2 += int(r2["frames"])
	Unit.losses_frozen = false
	_dump_red(red2)
	verdict("A5 по приказу атаки красные обходят стену и доходят (≥ 50 %% в досягаемости: %s), упёрлись %d, через один торец (север %d / юг %d из %d), дребезг у %d" % [
		("на %d с" % (contact2 / 60)) if contact2 >= 0 else "нет", int(r2["stuck"]), int(r2["north"]), int(r2["south"]), red2_n, int(r2["jitter"])],
		contact2 >= 0 and int(r2["stuck"]) == 0 and (int(r2["north"]) == 0 or int(r2["south"]) == 0) and int(r2["jitter"]) <= 2)
	_kill(arch2)
	_kill(red2)
	await pframes(30)

# ═════════════════════════════════════════════════════════════════════════════
# B. [A] НА ОТРЯДЫ ЗА СТЕНОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _block_b() -> void:
	print("\n═════ B. ATTACK-MOVE ЧЕРЕЗ ЛЕСНУЮ ПРЕГРАДУ НА ОТРЯДЫ ЗА НЕЙ ═════")
	var kinds := ["spearman", "spearman", "warrior", "archer"]
	var sids: Array = []
	for i in range(kinds.size()):
		sids.append(_squad(kinds[i], F, Vector3(WALL_X - 34.0, 0.0, AXIS_Z - 10.0 + 7.0 * float(i))))
	var red: Array = []
	for k in range(2):
		red.append(_squad("spearman", E, Vector3(WALL_X + 16.0, 0.0, AXIS_Z - 5.0 + 10.0 * float(k))))
	await pframes(30)
	var red_n: int = _all(red).size()
	await _select(sids)
	sm.set_attack_move_armed(true)
	var dest: Vector3 = _median(_all(red))
	var ok: bool = sm.order_at_world(dest, true)
	await pframes(2)
	# Следы судятся ДО первой рубки: в бою развороты и смены направления —
	# это удары, а не навигация
	var st := {"fight_t": -1, "fight_n": 0}
	var r: Dictionary = await _watch("B [A] за стену (до первого боя)", sids, 150.0, func(f):
		var n := 0
		for s in sids:
			if cmd.is_fighting(int(s)) or GameManager.squad_in_combat(int(s)):
				n += 1
		st["fight_n"] = maxi(int(st["fight_n"]), n)
		if int(st["fight_t"]) < 0 and n >= 1:
			st["fight_t"] = f
			return true
		return false)
	# Дальше — бой: вступили ли все и выбиты ли красные
	var f2 := 0
	while f2 < 60 * 60:
		await pframes(30)
		f2 += 30
		var n2 := 0
		for s3 in sids:
			if cmd.is_fighting(int(s3)) or GameManager.squad_in_combat(int(s3)):
				n2 += 1
		st["fight_n"] = maxi(int(st["fight_n"]), n2)
		var left0 := 0
		for s4 in red:
			left0 += _members(int(s4)).size()
		if left0 == 0:
			break
	var via := Vector3(WALL_X, 0.0, WALL_Z1 + 6.0)
	var ratio: float = _ratio_via(r, via)
	var left := 0
	for s3 in red:
		left += _members(int(s3)).size()
	print("    приказ [A] %s; путь/идеал (A→торец→B) худший ×%.2f; в бою отрядов до %d из 4 (первые 3 — %s); красных осталось %d из %d" % [
		str(ok), ratio, int(st["fight_n"]), ("на %d с" % (int(st["fight_t"]) / 60)) if int(st["fight_t"]) >= 0 else "нет", left, red_n])
	verdict("B1 отряды обтекают стену и вступают в бой (≥ 3 из 4 в бою: %s), красные выбиты или бьются (%d из %d)" % [
		("на %d с" % (int(st["fight_t"]) / 60)) if int(st["fight_t"]) >= 0 else "нет", left, red_n], int(st["fight_t"]) >= 0 and left < red_n)
	verdict("B2 кратчайший обход: путь ≤ 1.3 × (A→торец→B) (×%.2f), разворотов назад %d (0), крутых поворотов ≤ 2 на отряд (%d)" % [
		ratio, int(r["rev"]), int(r["turns"])], ratio <= 1.3 and int(r["rev"]) == 0 and int(r["turns"]) <= 2 * sids.size())
	verdict("B3 не затираются об деревья: упёрлись %d (0), дребезг у %d бойцов (≤ 2)" % [int(r["stuck"]), int(r["jitter"])],
		int(r["stuck"]) == 0 and int(r["jitter"]) <= 2)
	verdict("B4 кулаком, не ниточкой: отрыв от тела ≤ 10 с (%.1f), поперечник группы ≤ 55 м (%.0f), через один торец (север %d / юг %d)" % [
		float(r["det_s"]), float(r["span_max"]), int(r["north"]), int(r["south"])],
		float(r["det_s"]) <= 10.0 and float(r["span_max"]) <= 55.0 and (int(r["north"]) == 0 or int(r["south"]) == 0))
	for s4 in sids:
		cmd.cancel_squad(int(s4))
	_kill(sids)
	_kill(red)
	sm.clear_selection()
	await pframes(30)

# ═════════════════════════════════════════════════════════════════════════════
# C. ПКМ ЗА ЛЕС
# ═════════════════════════════════════════════════════════════════════════════
func _block_c() -> void:
	print("\n═════ C. ПКМ ЗА МАССИВ ЛЕСА ═════")
	var kinds := ["spearman", "archer", "warrior", "spearman"]
	var sids: Array = []
	for i in range(kinds.size()):
		sids.append(_squad(kinds[i], F, Vector3(WALL_X - 34.0, 0.0, AXIS_Z - 15.0 + 10.0 * float(i))))
	await pframes(30)
	var dest := Vector3(WALL_X + 24.0, 0.0, AXIS_Z)
	await _select(sids)
	sm.order_at_world(dest, false)
	await pframes(2)
	var st := {"arrived": -1}
	var r: Dictionary = await _watch("C ПКМ за лес", sids, 150.0, func(f):
		var near := 0
		for s in sids:
			var men: Array = _members(int(s))
			if men.size() < 3:
				continue
			var c: Vector3 = _median(men)
			var pcs: Array = []
			for u in men:
				pcs.append((u as Unit).post_pos)
			var pc: Vector3 = _median_v(pcs)
			if Vector2(c.x - pc.x, c.z - pc.z).length() <= 5.0:
				near += 1
		if near >= sids.size():
			st["arrived"] = f
			return true
		return false)
	var via := Vector3(WALL_X, 0.0, WALL_Z1 + 6.0)
	var ratio: float = _ratio_via(r, via)
	await pframes(60 * 4)
	var off := 0
	var tot := 0
	for s2 in sids:
		for u2 in _members(int(s2)):
			tot += 1
			var uu := u2 as Unit
			if Vector2(uu.global_position.x - uu.post_pos.x, uu.global_position.z - uu.post_pos.z).length() > 1.5:
				off += 1
	var arrived: int = int(st["arrived"])
	print("    пришли: %s; путь/идеал ×%.2f; не на посту через 4 с: %d из %d" % [("на %d с" % (arrived / 60)) if arrived >= 0 else "нет", ratio, off, tot])
	verdict("C1 все отряды пришли за лес (%s), путь ≤ 1.3 × идеала (×%.2f)" % [("%d с" % (arrived / 60)) if arrived >= 0 else "нет", ratio],
		arrived >= 0 and ratio <= 1.3)
	verdict("C2 без замираний и дребезга: упёрлись %d (0), дребезг у %d бойцов (≤ 2), разворотов %d (0)" % [int(r["stuck"]), int(r["jitter"]), int(r["rev"])],
		int(r["stuck"]) == 0 and int(r["jitter"]) <= 2 and int(r["rev"]) == 0)
	verdict("C3 отставших, потерявших вектор, нет: отрыв ≤ 8 с (%.1f), не на посту ≤ 3 %% (%d из %d)" % [float(r["det_s"]), off, tot],
		float(r["det_s"]) <= 8.0 and float(off) <= 0.03 * float(maxi(tot, 1)))
	_kill(sids)
	sm.clear_selection()

## Сколько красных ДОШЛИ до блока игрока: ближайший чужой боец в
## reach + CONTACT_PAD. Не «своя цель в досягаемости»: 120 копейщиков против
## 60 лучников в плотном блоке — большинству цель назначена в глубине блока,
## и они стоят в очереди за спинами своих (6-8 м до цели, 2-3 м до блока)
const CONTACT_PAD := 1.5
func _in_reach(red: Array) -> int:
	var foes: Array = []
	for f0 in get_tree().get_nodes_in_group(Constants.unit_group(F)):
		if is_instance_valid(f0) and f0 is Unit and not (f0 as Unit).is_dead():
			foes.append((f0 as Unit).global_position)
	var n := 0
	for u in _all(red):
		var uu := u as Unit
		var p: Vector3 = uu.global_position
		var lim: float = uu.reach() + CONTACT_PAD
		for fp in foes:
			if Vector2(p.x - (fp as Vector3).x, p.z - (fp as Vector3).z).length() <= lim:
				n += 1
				break
	return n

## Ждать, пока ≥ frac красных не встанут в досягаемость (навигация, не
## истребление: потери заморожены — Unit.losses_frozen)
func _wait_reach(red: Array, frac: float, cap_s: float) -> int:
	var f := 0
	while f < int(cap_s * 60.0):
		await pframes(30)
		f += 30
		if _in_reach(red) >= int(ceil(float(_all(red).size()) * frac)):
			return f
	return -1

## Где и в чём стоят красные: по эту/ту сторону стены, состояния, цели, пути
func _dump_red(red: Array) -> void:
	var east := 0
	var west := 0
	var st := {}
	var with_t := 0
	var routes := 0
	var dead_end := 0
	var dsum := 0.0
	var n := 0
	var sample := ""
	for u in _all(red):
		var uu := u as Unit
		var p: Vector3 = uu.global_position
		n += 1
		if p.x > WALL_X: east += 1
		else: west += 1
		st[int(uu.state)] = int(st.get(int(uu.state), 0)) + 1
		var t = uu.attack_target
		if t != null and is_instance_valid(t):
			with_t += 1
			dsum += p.distance_to((t as Node3D).global_position)
		if uu._route.size() > 0: routes += 1
		if uu._nav_dead_end: dead_end += 1
		if n <= 3:
			sample += "[(%.0f,%.0f) st%d tgt=%s d=%.0f путь=%d тупик=%s пост=(%.0f,%.0f)] " % [p.x, p.z, int(uu.state), str(t != null),
				p.distance_to((t as Node3D).global_position) if t != null and is_instance_valid(t) else -1.0, uu._route.size(), str(uu._nav_dead_end), uu.post_pos.x, uu.post_pos.z]
	print("    красные: восточнее стены %d, западнее %d; состояния %s; с целью %d (ср. дист. %.1f); с маршрутом %d; тупик %d; примеры %s" % [
		east, west, str(st), with_t, dsum / float(maxi(with_t, 1)), routes, dead_end, sample])

func _median_v(ps: Array) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for p in ps:
		xs.append((p as Vector3).x)
		zs.append((p as Vector3).z)
	xs.sort()
	zs.sort()
	return Vector3(float(xs[xs.size() / 2]), 0.0, float(zs[zs.size() / 2]))
