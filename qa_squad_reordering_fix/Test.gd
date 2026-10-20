extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ПЕРЕСТРОЕНИЯ ПЕРЕД МАРШЕМ: СТРОЙ ОБЯЗАН ТРОНУТЬСЯ КАК СТОЯЛ
## (ТЗ 13.10.2026, шестое письмо, qa_squad_reordering_fix)
## ═══════════════════════════════════════════════════════════════════════════
## 12 отрядов встают строем по линии (протяжка ПКМ), стоят, затем получают
## новый приказ. В момент приказа судится РАЗДАЧА МЕСТ (кто куда послан):
##   • инверсии бокового порядка внутри отряда (пара бойцов, стоящих «левый —
##     правый», получила места «правый — левый») — это и есть «вывернулись»;
##   • инверсии глубины (передний послан назад за заднего);
##   • перекрёсты отрезков «боец → его место» внутри отряда;
##   • лишний путь: средняя длина «боец → место» против сдвига центра.
## В первые 3 с — кто пошёл НАЗАД или ВБОК раньше, чем вперёд; задержка
## старта; на приходе — прямизна пути каждого бойца (путь / хорда).
## Случаи: A широкий фронт [1], 12 копейщиков; B коробочка [2]; C смешанное
## выделение (эшелоны: копейщики/лучники/мечники); D обычный ПКМ-клик
## группой; E протяжка в режиме [A] (марш с боем); F справочно — протяжка
## линии в обратную сторону (фронт разворачивается на 180°: перестроение
## ожидаемо, печатаются числа).
## Запуск: godot --headless --path . res://qa_squad_reordering_fix/Test.tscn
##         [-- only=abcdef]
## Провалы искать по «НЕ ПРОШЛО» / «провалов:» (и SCRIPT ERROR в логе).

const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")

const FIELD := Vector3(-110.0, 0.0, -20.0)
const SHIFT := 40.0
const TIE := 0.25

var main = null
var sm = null
var cmd = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abcdef"

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(1800.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_squad_reordering_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _unit(uid: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = F
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _staff(kind: String) -> Array:
	var bld: String = "archery" if kind == "archer" else "barracks"
	var cfg: Dictionary = _UCfg.train_cfg(bld, kind)
	return [int(cfg.get("squad", 20)), int(cfg.get("cols", 5))]

func _squad(uid: String, at: Vector3) -> int:
	var st: Array = _staff(uid)
	var sid: int = GameManager.new_squad(F, uid)
	var cols: int = int(st[1])
	for i in range(int(st[0])):
		var u := _unit(uid, at + Vector3(float(i / cols) * 0.65, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * 0.65))
		GameManager.add_to_squad(sid, u)
	return sid

func _army(kinds: Array) -> Array:
	var sids: Array = []
	for i in range(kinds.size()):
		var col: int = i % 6
		var row: int = i / 6
		sids.append(_squad(kinds[i], FIELD + Vector3(-float(row) * 12.0, 0.0, -32.0 + 12.0 * float(col))))
	return sids

func _kill(sids: Array) -> void:
	for s in sids:
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)

func _select(sids: Array) -> void:
	sm.select_units(_all(sids))
	await pframes(2)

## Ждать, пока ≥ 97 % бойцов встанут на свои места (≤ 0.6 м), потолок cap_s
func _settle(sids: Array, cap_s: float) -> float:
	var f := 0
	var frac := 0.0
	while f < int(cap_s * 60.0):
		await pframes(30)
		f += 30
		var tot := 0
		var inn := 0
		for u in _all(sids):
			tot += 1
			var uu := u as Unit
			if Vector2(uu.global_position.x - uu.post_pos.x, uu.global_position.z - uu.post_pos.z).length() <= 0.6:
				inn += 1
		frac = float(inn) / float(maxi(tot, 1))
		if frac >= 0.97:
			break
	await pframes(60 * 2)
	return frac

func _seg_cross(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	var r := Vector2(b.x - a.x, b.z - a.z)
	var s := Vector2(d.x - c.x, d.z - c.z)
	var den: float = r.cross(s)
	if absf(den) < 1e-6:
		return false
	var qp := Vector2(c.x - a.x, c.z - a.z)
	var t: float = qp.cross(s) / den
	var u: float = qp.cross(r) / den
	return t > 0.0 and t < 1.0 and u > 0.0 and u < 1.0

## РАЗДАЧА МЕСТ В МОМЕНТ ПРИКАЗА: инверсии бокового порядка и глубины,
## перекрёсты «боец → место», лишний путь. axis — направление хода (к цели),
## side — поперёк (ось фронта)
func _assignment(sids: Array, axis: Vector3, side: Vector3) -> Dictionary:
	var inv_lat := 0
	var inv_dep := 0
	var pairs := 0
	var cross := 0
	var excess_sum := 0.0
	var worst_sq := ""
	var worst_inv := 0.0
	for s in sids:
		var men: Array = _members(int(s))
		var n: int = men.size()
		if n < 3:
			continue
		var pl := PackedFloat32Array(); pl.resize(n)
		var pd := PackedFloat32Array(); pd.resize(n)
		var sl := PackedFloat32Array(); sl.resize(n)
		var sd := PackedFloat32Array(); sd.resize(n)
		var dsum := 0.0
		for i in range(n):
			var u := men[i] as Unit
			var p: Vector3 = u.global_position
			var q: Vector3 = u.post_pos
			pl[i] = p.dot(side); pd[i] = p.dot(axis)
			sl[i] = q.dot(side); sd[i] = q.dot(axis)
			dsum += Vector2(q.x - p.x, q.z - p.z).length()
		var c0: Vector3 = _median(men)
		var pcs: Array = []
		for u2 in men:
			pcs.append((u2 as Unit).post_pos)
		var c1: Vector3 = _median_v(pcs)
		var shift: float = Vector2(c1.x - c0.x, c1.z - c0.z).length()
		excess_sum += dsum / float(n) - shift
		var il := 0
		var idp := 0
		var cr := 0
		var pr := 0
		for i in range(n):
			for j in range(i + 1, n):
				pr += 1
				var a: float = pl[i] - pl[j]
				var b: float = sl[i] - sl[j]
				if absf(a) > TIE and absf(b) > TIE and a * b < 0.0:
					il += 1
				var a2: float = pd[i] - pd[j]
				var b2: float = sd[i] - sd[j]
				if absf(a2) > TIE and absf(b2) > TIE and a2 * b2 < 0.0:
					idp += 1
				# Перекрёст — только при настоящей смене бокового порядка (> TIE):
				# два бойца разных шеренг со сдвигом в 0.1 м дают пересечение
				# 40-метровых отрезков, не пересекаясь телами
				if absf(a) > TIE and absf(b) > TIE and _seg_cross((men[i] as Unit).global_position, (men[i] as Unit).post_pos,
						(men[j] as Unit).global_position, (men[j] as Unit).post_pos):
					cr += 1
		inv_lat += il
		inv_dep += idp
		cross += cr
		pairs += pr
		var fr: float = float(il + idp) / float(maxi(pr, 1))
		if fr > worst_inv:
			worst_inv = fr
			worst_sq = "%d (%s): бок %d, глубина %d, перекрёстов %d из %d пар" % [int(s), GameManager.squad_type(int(s)), il, idp, cr, pr]
	return {"inv_lat": inv_lat, "inv_dep": inv_dep, "cross": cross, "pairs": pairs,
		"inv_frac": float(inv_lat + inv_dep) / float(maxi(pairs, 1)), "cross_frac": float(cross) / float(maxi(pairs, 1)),
		"excess": excess_sum / float(maxi(sids.size(), 1)), "worst": worst_sq}

func _median_v(ps: Array) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for p in ps:
		xs.append((p as Vector3).x)
		zs.append((p as Vector3).z)
	xs.sort()
	zs.sort()
	return Vector3(float(xs[xs.size() / 2]), 0.0, float(zs[zs.size() / 2]))

## Первые 3 с после приказа и дорога до прихода: назад / вбок-раньше-вперёд,
## задержка старта, прямизна пути бойцов
func _march(tag: String, sids: Array, axis: Vector3, limit_s: float) -> Dictionary:
	var start: Dictionary = {}
	var path: Dictionary = {}
	var last: Dictionary = {}
	for u in _all(sids):
		start[u] = (u as Unit).global_position
		path[u] = 0.0
		last[u] = (u as Unit).global_position
	var c0: Vector3 = _median(_all(sids))
	var back := 0
	var side_first := 0
	var start_f := -1
	var f := 0
	var limit: int = int(limit_s * 60.0)
	var arrived := -1
	while f < limit:
		await get_tree().physics_frame
		f += 1
		if start_f < 0 and f % 5 == 0:
			var c: Vector3 = _median(_all(sids))
			if Vector2(c.x - c0.x, c.z - c0.z).length() >= 0.5:
				start_f = f
		if f == 90:
			for u in _all(sids):
				var d: Vector3 = (u as Unit).global_position - (start[u] as Vector3)
				d.y = 0.0
				if d.length() < 0.5:
					continue
				var fwd: float = d.dot(axis)
				if fwd < -0.3 * d.length():
					back += 1
				elif absf(d.length() * d.length() - fwd * fwd) > fwd * fwd and d.length() > 1.0:
					side_first += 1
		if f % 30 == 0:
			var tot := 0
			var inn := 0
			for u in _all(sids):
				var uu := u as Unit
				var p: Vector3 = uu.global_position
				path[uu] = float(path[uu]) + Vector2(p.x - (last[uu] as Vector3).x, p.z - (last[uu] as Vector3).z).length()
				last[uu] = p
				tot += 1
				if Vector2(p.x - uu.post_pos.x, p.z - uu.post_pos.z).length() <= 0.8:
					inn += 1
			if f > 120 and float(inn) >= 0.95 * float(maxi(tot, 1)):
				arrived = f
				break
	var worst := 0.0
	var sum := 0.0
	var n := 0
	var over := 0
	for u in _all(sids):
		var chord: float = Vector2((u as Unit).global_position.x - (start[u] as Vector3).x, (u as Unit).global_position.z - (start[u] as Vector3).z).length()
		if chord < 3.0:
			continue
		var ratio: float = float(path[u]) / chord
		worst = maxf(worst, ratio)
		sum += ratio
		n += 1
		if ratio > 1.15:
			over += 1
	var out := {"back": back, "side_first": side_first, "start_f": start_f, "arrived": arrived,
		"ratio_worst": worst, "ratio_mean": sum / float(maxi(n, 1)), "over": over, "men": n}
	print("    [%s] старт через %.2f с; за 1.5 с назад %d, вбок раньше вперёд %d; %s; прямизна пути бойца: средняя ×%.3f, худшая ×%.2f, кривых (> 1.15) %d из %d" % [
		tag, float(start_f) / 60.0 if start_f >= 0 else -1.0, back, side_first,
		("дошли за %d с" % (arrived / 60)) if arrived >= 0 else "НЕ дошли", float(out["ratio_mean"]), worst, over, n])
	return out

func _print_assign(tag: String, a: Dictionary) -> void:
	print("    [%s] раздача мест: инверсий бока %d, глубины %d из %d пар (%.1f %%), перекрёстов %d (%.1f %%), лишний путь %.2f м; худший отряд %s" % [
		tag, int(a["inv_lat"]), int(a["inv_dep"]), int(a["pairs"]), float(a["inv_frac"]) * 100.0, int(a["cross"]),
		float(a["cross_frac"]) * 100.0, float(a["excess"]), String(a["worst"])])

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
	var centre: Vector3 = FIELD + Vector3(30.0, 0.0, 0.0)
	main._clear_area_of_resources(centre, 95.0)
	main._clear_trees(centre, 95.0)
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit and ((n0 as Unit).faction != F or (n0 as Unit).stat_id == "worker") \
				and (n0 as Unit).global_position.distance_to(centre) < 130.0:
			(n0 as Unit).take_damage(1.0e12)
	for sh in get_tree().get_nodes_in_group("sheep"):
		if is_instance_valid(sh) and (sh as Node3D).global_position.distance_to(centre) < 130.0:
			(sh as Node).queue_free()
	await pframes(4)
	var mono: Array = []
	for i in range(12):
		mono.append("spearman")
	var mixed: Array = ["spearman", "spearman", "archer", "warrior", "spearman", "spearman",
		"archer", "warrior", "spearman", "spearman", "archer", "warrior"]
	if _only.contains("a"):
		await _case("A широкий фронт [1], 12×копейщики", mono, sm.FORM_WIDE, "line")
	if _only.contains("b"):
		await _case("B коробочка [2], 12×копейщики", mono, sm.FORM_DEEP, "line")
	if _only.contains("c"):
		await _case("C смешанное выделение (эшелоны), [1]", mixed, sm.FORM_WIDE, "line")
	if _only.contains("d"):
		await _case("D обычный ПКМ-клик группой", mixed, sm.FORM_WIDE, "click")
	if _only.contains("e"):
		await _case("E протяжка в режиме [A]", mixed, sm.FORM_WIDE, "am")
	if _only.contains("f"):
		await _case("F протяжка в обратную сторону (справочно)", mono, sm.FORM_WIDE, "reverse", false)
	_finish()

## Один случай: строй по линии → стоим → новый приказ (+SHIFT вперёд)
func _case(tag: String, kinds: Array, mode: int, how: String, judge: bool = true) -> void:
	print("\n═════ %s ═════" % tag)
	sm.formation_mode = mode
	var sids: Array = _army(kinds)
	await pframes(30)
	# Линия вдоль Z (фронт смотрит в +X: facing = (dir.z, 0, −dir.x) при dir = (0,0,1) → (1,0,0))
	var la: Vector3 = FIELD + Vector3(8.0, 0.0, -42.0)
	var lb: Vector3 = FIELD + Vector3(8.0, 0.0, 42.0)
	await _select(sids)
	sm._execute_line_formation(la, lb)
	var settled: float = await _settle(sids, 70.0)
	var axis := Vector3(1.0, 0.0, 0.0)
	var side := Vector3(0.0, 0.0, 1.0)
	print("    исходный строй: на местах %.0f %%" % (settled * 100.0))
	# ── НОВЫЙ ПРИКАЗ ─────────────────────────────────────────────────────
	await _select(sids)
	var la2: Vector3 = la + axis * SHIFT
	var lb2: Vector3 = lb + axis * SHIFT
	match how:
		"line":
			sm._execute_line_formation(la2, lb2)
		"reverse":
			sm._execute_line_formation(lb2, la2)
		"click":
			sm.order_at_world((la2 + lb2) * 0.5 + axis * 6.0, false)
		"am":
			sm.set_attack_move_armed(true)
			sm.attack_move_line(la2, lb2)
	await pframes(2)
	var a: Dictionary = _assignment(sids, axis, side)
	_print_assign(tag, a)
	var m: Dictionary = await _march(tag, sids, axis, 120.0)
	if judge:
		var key: String = tag.substr(0, 1)
		# Порог 0.2 % пар: соседи по шеренге в 0.3 м друг от друга (порог TIE
		# 0.25) могут поменяться местами одной парой на 13 тысяч
		verdict("%s1 не выворачиваются: инверсий порядка в раздаче мест ≤ 0.2 %% (%d бок + %d глубина из %d пар = %.2f %%)" % [
			key, int(a["inv_lat"]), int(a["inv_dep"]), int(a["pairs"]), float(a["inv_frac"]) * 100.0], float(a["inv_frac"]) <= 0.002)
		verdict("%s2 пути «боец → место» внутри отряда не перекрещиваются (≤ 0.2 %%: %d), лишний путь ≤ 1 м (%.2f)" % [
			key, int(a["cross"]), float(a["excess"])], float(a["cross_frac"]) <= 0.002 and float(a["excess"]) <= 1.0)
		verdict("%s3 тронулись как стояли: старт ≤ 1 с (%.2f), назад 0 (%d), вбок раньше вперёд ≤ 2 %% (%d)" % [
			key, float(m["start_f"]) / 60.0, int(m["back"]), int(m["side_first"])],
			int(m["start_f"]) >= 0 and int(m["start_f"]) <= 60 and int(m["back"]) == 0 and float(m["side_first"]) <= 0.02 * float(maxi(int(m["men"]), 1)))
		verdict("%s4 траектории прямые: дошли (%s), путь бойца ≤ 1.15 × хорды у ≥ 98 %% (кривых %d из %d), средняя ×%.3f" % [
			key, ("%d с" % (int(m["arrived"]) / 60)) if int(m["arrived"]) >= 0 else "нет", int(m["over"]), int(m["men"]), float(m["ratio_mean"])],
			int(m["arrived"]) >= 0 and float(m["over"]) <= 0.02 * float(maxi(int(m["men"]), 1)) and float(m["ratio_mean"]) <= 1.05)
	for s in sids:
		cmd.cancel_squad(int(s))
	_kill(sids)
	sm.clear_selection()
	sm.formation_mode = sm.FORM_WIDE
	await pframes(30)
