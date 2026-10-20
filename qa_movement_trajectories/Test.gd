extends Node

## ═══════════════════════════════════════════════════════════════════════════
## АУДИТ ТРАЕКТОРИЙ ДВИЖЕНИЯ АРМИИ (ТЗ 13.10.2026, четвёртое письмо)
## ═══════════════════════════════════════════════════════════════════════════
## Группа из 6 отрядов (3 копейщиков, 2 лучников, 1 мечников, штат из конфига
## найма) ходит ОБЫЧНЫМ ПКМ (SelectionManager.order_at_world — та же сетка
## блоков и перенос строя, что у клика). След центра каждого отряда (медиана,
## раз в 0.5 с) даёт метрики:
##   • длина пути / идеал (прямая или A → узел → B у препятствия);
##   • развороты назад (ход против предыдущего, cos < −0.5) и крутые
##     повороты (cos < 0.5) на отрезках длиннее 0.5 м;
##   • откаты (дистанция до цели выросла > 1 м между замерами);
##   • боковой увод от прямой A→B (прямой марш);
##   • ПЕРЕКРЁСТЫ: пересечения следов центров разных отрядов и смена
##     бокового порядка отрядов (левый остался левым);
##   • по бойцам: «бег против хода отряда» ≥ 2 окна по 3 с, «бег на месте»
##     (MOVING, а за 3 с < 0.3 м), отставшие от своего поста на приходе.
## A — прямой марш 70 м по сухой равнине (группа и одиночный отряд).
## B — порядок и строй: построение по линии протяжкой, марш 70 м, второй
##     марш под 90° — следы не перекрещиваются, фланги не меняются местами.
## C — препятствия: проход в лесной стене базы (прямая упирается в стену в
##     8 м от прохода) и река (прямая через глубокую воду — дорога через брод).
## D — переприказ на ходу: на 6-й секунде марша — новая точка под 90°;
##     разворот за ≤ 2 с, без стояния, без бега на месте, строй на приходе.
## Запуск: godot --headless --path . res://qa_movement_trajectories/Test.tscn
##         [-- only=abcd]
## Провалы искать по «НЕ ПРОШЛО» / «провалов:» (и SCRIPT ERROR в логе).

const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")

const SAMPLE_FR := 30          # след центра — раз в 0.5 с
const MIN_SEG := 0.5           # отрезок следа короче — не судится по углу
const KINDS := ["spearman", "archer", "spearman", "warrior", "spearman", "archer"]

var main = null
var sm = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abcd"

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
	print("\n═════ ИТОГ qa_movement_trajectories: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

# ─────────────────────────────────────────────────────────────────────────────
# СЛУЖЕБНОЕ
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

func _median(men: Array) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for u in men:
		xs.append((u as Unit).global_position.x)
		zs.append((u as Unit).global_position.z)
	xs.sort()
	zs.sort()
	return Vector3(float(xs[xs.size() / 2]), 0.0, float(zs[zs.size() / 2]))

func _posts_centre(sid: int) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for u in _members(sid):
		xs.append((u as Unit).post_pos.x)
		zs.append((u as Unit).post_pos.z)
	if xs.is_empty():
		return Vector3.INF
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

func _squad(uid: String, at: Vector3) -> int:
	var st: Array = _staff(uid)
	var n: int = int(st[0])
	var cols: int = int(st[1])
	var sid: int = GameManager.new_squad(F, uid)
	for i in range(n):
		var u := _unit(uid, F, at + Vector3(float(i / cols) * 0.65, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * 0.65))
		GameManager.add_to_squad(sid, u)
	return sid

## Группа из 6 отрядов в ряд поперёк оси X (фланги по Z)
func _group(at: Vector3) -> Array:
	var sids: Array = []
	for i in range(KINDS.size()):
		sids.append(_squad(KINDS[i], at + Vector3(0.0, 0.0, -25.0 + 10.0 * float(i))))
	return sids

func _kill(sids: Array) -> void:
	for s in sids:
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)

func _clear(at: Vector3, r: float) -> void:
	main._clear_area_of_resources(at, r)
	main._clear_trees(at, r)
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit and (n0 as Unit).faction != F \
				and (n0 as Unit).global_position.distance_to(at) < r + 20.0:
			(n0 as Unit).take_damage(1.0e12)
	for sh in get_tree().get_nodes_in_group("sheep"):
		if is_instance_valid(sh) and (sh as Node3D).global_position.distance_to(at) < r + 20.0:
			(sh as Node).queue_free()

func _select(sids: Array) -> void:
	var all: Array = []
	for s in sids:
		all.append_array(_members(int(s)))
	sm.select_units(all)
	await pframes(2)

func _order(sids: Array, dest: Vector3) -> void:
	await _select(sids)
	sm.order_at_world(dest, false)
	await pframes(2)

## Сухая ровная точка рядом с желаемой
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

# ─────────────────────────────────────────────────────────────────────────────
# СЛЕД И МЕТРИКИ
# ─────────────────────────────────────────────────────────────────────────────
## Ведёт группу до прихода (центры постов и центры отрядов сошлись ≤ arrive_r
## у ≥ 80 % отрядов) или до limit_s; в hook(f) можно вмешаться (переприказ).
## Возвращает словарь метрик и следы
func _track(tag: String, sids: Array, limit_s: float, arrive_r: float, hook: Callable = Callable()) -> Dictionary:
	var tracks: Dictionary = {}      # sid → Array[Vector3]
	var dist_prev: Dictionary = {}
	var regress: Dictionary = {}
	var upos: Dictionary = {}
	var ucen: Dictionary = {}
	var back_run: Dictionary = {}
	var back_n := 0
	var inplace_n := 0
	var arrived := -1
	var f := 0
	var limit: int = int(limit_s * 60.0)
	for s in sids:
		tracks[int(s)] = []
		regress[int(s)] = 0
	while f < limit:
		await get_tree().physics_frame
		f += 1
		if hook.is_valid():
			hook.call(f)
		if f % SAMPLE_FR != 0:
			continue
		var near := 0
		var alive := 0
		for s in sids:
			var men: Array = _members(int(s))
			if men.size() < 3:
				continue
			alive += 1
			var c: Vector3 = _median(men)
			(tracks[int(s)] as Array).append(c)
			var pc: Vector3 = _posts_centre(int(s))
			if pc.x != INF:
				var d: float = Vector2(c.x - pc.x, c.z - pc.z).length()
				var dp: Variant = dist_prev.get(int(s))
				# Откат: до своих постов стало дальше > 1 м (за 0.5 с)
				if dp != null and d > float(dp) + 1.0 and d > arrive_r:
					regress[int(s)] = int(regress[int(s)]) + 1
				dist_prev[int(s)] = d
				if d <= arrive_r:
					near += 1
		# ── по бойцам, окно 3 с ────────────────────────────────────────────
		if f % 180 == 0:
			for s2 in sids:
				var men2: Array = _members(int(s2))
				if men2.is_empty():
					continue
				var c2: Vector3 = _median(men2)
				var cp: Variant = ucen.get(int(s2))
				ucen[int(s2)] = c2
				var D: Vector3 = (c2 - (cp as Vector3)) if cp != null else Vector3.ZERO
				var squad_moves: bool = D.length() > 3.0
				for u in men2:
					var uu := u as Unit
					var p: Vector3 = uu.global_position
					var pp: Variant = upos.get(uu)
					upos[uu] = p
					if pp == null:
						continue
					var d3: Vector3 = p - (pp as Vector3)
					d3.y = 0.0
					# Бег на месте: идёт по автомату, а не сдвинулся
					if uu.state == Unit.State.MOVING and d3.length() < 0.3 and squad_moves:
						inplace_n += 1
					var back := false
					if squad_moves and d3.length() > 1.5 \
							and d3.normalized().dot(Vector3(D.x, 0.0, D.z).normalized()) < -0.3:
						back = true
					var br: int = (int(back_run.get(uu, 0)) + 1) if back else 0
					back_run[uu] = br
					if br == 2:
						back_n += 1
		if arrived < 0 and alive > 0 and near >= int(ceil(float(alive) * 0.8)):
			arrived = f
			break
	# ── геометрия следов ───────────────────────────────────────────────────
	var out := {"arrived": arrived, "frames": f, "back_n": back_n, "inplace_n": inplace_n,
		"tracks": tracks, "regress": regress, "per": {}}
	var rev_tot := 0
	var turn_tot := 0
	for s3 in sids:
		var tr: Array = tracks[int(s3)]
		var length := 0.0
		var rev := 0
		var turns := 0
		var prev_dir := Vector3.ZERO
		var last: Vector3 = tr[0] if not tr.is_empty() else Vector3.ZERO
		for i in range(1, tr.size()):
			var seg: Vector3 = (tr[i] as Vector3) - last
			seg.y = 0.0
			if seg.length() < MIN_SEG:
				continue
			length += seg.length()
			var dir: Vector3 = seg.normalized()
			if prev_dir != Vector3.ZERO:
				var dd: float = dir.dot(prev_dir)
				if dd < -0.5:
					rev += 1
				elif dd < 0.5:
					turns += 1
			prev_dir = dir
			last = tr[i]
		rev_tot += rev
		turn_tot += turns
		var straight: float = (tr[tr.size() - 1] as Vector3).distance_to(tr[0] as Vector3) if tr.size() > 1 else 0.0
		(out["per"] as Dictionary)[int(s3)] = {"len": length, "straight": straight, "rev": rev, "turns": turns,
			"regress": int(regress[int(s3)]), "type": GameManager.squad_type(int(s3))}
	out["rev"] = rev_tot
	out["turns"] = turn_tot
	# Отставшие от поста на приходе: ждём, пока дойдут ВСЕ отряды (приход
	# судился по 80 %), потолок 25 с, затем 3 с на смыкание
	var fw := 0
	while fw < 60 * 25:
		await pframes(30)
		fw += 30
		var all_in := true
		for s6 in sids:
			var men6: Array = _members(int(s6))
			if men6.size() < 3:
				continue
			var pc6: Vector3 = _posts_centre(int(s6))
			if pc6.x != INF and Vector2(_median(men6).x - pc6.x, _median(men6).z - pc6.z).length() > arrive_r:
				all_in = false
		if all_in:
			break
	await pframes(60 * 3)
	var off := 0
	var tot := 0
	for s4 in sids:
		for u4 in _members(int(s4)):
			tot += 1
			var uu4 := u4 as Unit
			if Vector2(uu4.global_position.x - uu4.post_pos.x, uu4.global_position.z - uu4.post_pos.z).length() > 1.5:
				off += 1
	out["off_post"] = off
	out["men"] = tot
	print("    [%s] %s за %d с; разворотов назад %d, крутых поворотов %d; назад ≥6 с: %d бойцов; бег на месте: %d; не на посту через 3 с: %d из %d" % [
		tag, "пришли" if arrived >= 0 else "НЕ пришли", f / 60, rev_tot, turn_tot, back_n, inplace_n, off, tot])
	for s5 in sids:
		var pr: Dictionary = (out["per"] as Dictionary)[int(s5)]
		print("      отряд %d %-8s: путь %.1f м, по прямой %.1f м (×%.2f), разворотов %d, поворотов %d, откатов %d" % [
			int(s5), String(pr["type"]), float(pr["len"]), float(pr["straight"]),
			float(pr["len"]) / maxf(float(pr["straight"]), 0.1), int(pr["rev"]), int(pr["turns"]), int(pr["regress"])])
	return out

## Пересечения следов центров разных отрядов (отрезки по замерам)
func _crossings(tracks: Dictionary) -> int:
	var keys: Array = tracks.keys()
	var n := 0
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Array = tracks[keys[i]]
			var b: Array = tracks[keys[j]]
			for p in range(1, a.size()):
				for q in range(1, b.size()):
					if _seg_cross(a[p - 1], a[p], b[q - 1], b[q]):
						n += 1
	return n

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

## Боковой порядок отрядов относительно оси хода: число пар, поменявшихся
## местами между началом и концом следа
func _order_swaps(tracks: Dictionary, axis: Vector3) -> int:
	var side := Vector3(-axis.z, 0.0, axis.x).normalized()
	var keys: Array = tracks.keys()
	var swaps := 0
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Array = tracks[keys[i]]
			var b: Array = tracks[keys[j]]
			if a.size() < 2 or b.size() < 2:
				continue
			var d0: float = (a[0] as Vector3 - b[0] as Vector3).dot(side)
			var d1: float = (a[a.size() - 1] as Vector3 - b[b.size() - 1] as Vector3).dot(side)
			if d0 * d1 < 0.0 and absf(d0) > 2.0 and absf(d1) > 2.0:
				swaps += 1
	return swaps

## Наибольший боковой увод следа от СОБСТВЕННОЙ хорды отряда (старт → финиш):
## сетка блоков перестраивает группу на приходе (6 в ряд → 3×2), и увод от
## общей прямой A→B — это раскладка, а не «дуга»; дуга — отход от своей хорды
func _lateral_max(tracks: Dictionary, _a: Vector3, _b: Vector3) -> float:
	var worst := 0.0
	for k in tracks:
		var tr: Array = tracks[k]
		if tr.size() < 2:
			continue
		var a: Vector3 = tr[0]
		var axis: Vector3 = (tr[tr.size() - 1] as Vector3) - a
		axis.y = 0.0
		if axis.length() < 1.0:
			continue
		axis = axis.normalized()
		var side := Vector3(-axis.z, 0.0, axis.x)
		for p in tr:
			worst = maxf(worst, absf((p as Vector3 - a).dot(side)))
	return worst

func _path_ratio(out: Dictionary, ideal_of: Callable) -> float:
	var worst := 0.0
	for k in (out["tracks"] as Dictionary):
		var tr: Array = (out["tracks"] as Dictionary)[k]
		if tr.size() < 2:
			continue
		var ideal: float = float(ideal_of.call(tr[0] as Vector3, tr[tr.size() - 1] as Vector3))
		var pr: Dictionary = (out["per"] as Dictionary)[k]
		worst = maxf(worst, float(pr["len"]) / maxf(ideal, 1.0))
	return worst

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
	_Opt.tick_meter = true
	for k in ["enemy_ai", "gnoll_ai", "enemy_guard", "goblin_ai", "goblin_reserve"]:
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
	if _only.contains("a"):
		await _block_a()
	if _only.contains("b"):
		await _block_b()
	if _only.contains("c"):
		await _block_c()
	if _only.contains("d"):
		await _block_d()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ПРЯМОЙ МАРШ ПО РАВНИНЕ
# ═════════════════════════════════════════════════════════════════════════════
const FIELD := Vector3(-110.0, 0.0, -22.0)

func _block_a() -> void:
	print("\n═════ A. ПРЯМОЙ МАРШ А → Б ═════")
	_clear(FIELD + Vector3(35.0, 0.0, 0.0), 75.0)
	await pframes(4)
	var sids: Array = _group(FIELD)
	await pframes(30)
	var a0: Vector3 = FIELD
	var b0: Vector3 = FIELD + Vector3(70.0, 0.0, 0.0)
	await _order(sids, b0)
	var r: Dictionary = await _track("A группа 6 → 70 м", sids, 120.0, 6.0)
	var ratio: float = _path_ratio(r, func(a, b): return (a as Vector3).distance_to(b as Vector3))
	var lat: float = _lateral_max(r["tracks"], a0, b0)
	var cross: int = _crossings(r["tracks"])
	print("    путь/прямая худший ×%.2f, боковой увод до %.1f м, перекрёстов следов %d" % [ratio, lat, cross])
	verdict("A1 группа дошла (%s)" % (("%d с" % (int(r["arrived"]) / 60)) if int(r["arrived"]) >= 0 else "нет"), int(r["arrived"]) >= 0)
	verdict("A2 ни один отряд не делает петель: путь ≤ 1.15 × прямой (худший ×%.2f), разворотов назад 0 (%d)" % [ratio, int(r["rev"])],
		ratio <= 1.15 and int(r["rev"]) == 0)
	verdict("A3 без «кучерявых дуг»: крутых поворотов 0 (%d), боковой увод ≤ 4 м (%.1f), откатов 0 (%s)" % [
		int(r["turns"]), lat, str(r["regress"])], int(r["turns"]) == 0 and lat <= 4.0 and _sum(r["regress"]) == 0)
	verdict("A4 бойцы не бегут назад (%d) и не бегут на месте (%d)" % [int(r["back_n"]), int(r["inplace_n"])],
		int(r["back_n"]) == 0 and int(r["inplace_n"]) <= 2)
	verdict("A5 строй на приходе: не на посту ≤ 3 %% (%d из %d)" % [int(r["off_post"]), int(r["men"])],
		float(r["off_post"]) <= 0.03 * float(maxi(int(r["men"]), 1)))
	# Одиночный отряд — тот же марш назад
	var one: Array = [sids[2]]
	await _order(one, a0 + Vector3(0.0, 0.0, -25.0 + 20.0))
	var r1: Dictionary = await _track("A одиночный отряд ← 70 м", one, 90.0, 5.0)
	var ratio1: float = _path_ratio(r1, func(a, b): return (a as Vector3).distance_to(b as Vector3))
	verdict("A6 одиночный отряд: прямая (×%.2f ≤ 1.1), разворотов %d, поворотов %d, откатов %s" % [
		ratio1, int(r1["rev"]), int(r1["turns"]), str(r1["regress"])],
		int(r1["arrived"]) >= 0 and ratio1 <= 1.1 and int(r1["rev"]) == 0 and int(r1["turns"]) == 0)
	_kill(sids)
	sm.clear_selection()
	await pframes(20)

func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n

# ═════════════════════════════════════════════════════════════════════════════
# B. ПОРЯДОК И СТРОЙ: ЛИНИЯ ПРОТЯЖКОЙ, МАРШ, МАРШ ПОД 90°
# ═════════════════════════════════════════════════════════════════════════════
func _block_b() -> void:
	print("\n═════ B. ПОРЯДОК ФЛАНГОВ И ПЕРЕКРЁСТЫ ═════")
	_clear(FIELD + Vector3(35.0, 0.0, 20.0), 80.0)
	await pframes(4)
	var sids: Array = _group(FIELD)
	await pframes(30)
	await _select(sids)
	sm._execute_line_formation(FIELD + Vector3(6.0, 0.0, -30.0), FIELD + Vector3(6.0, 0.0, 30.0))
	await pframes(2)
	var r0: Dictionary = await _track("B линия протяжкой", sids, 60.0, 4.0)
	var c0: int = _crossings(r0["tracks"])
	verdict("B1 построение по линии: встали (%s), следов-перекрёстов ≤ 2 (%d), разворотов %d" % [
		("%d с" % (int(r0["arrived"]) / 60)) if int(r0["arrived"]) >= 0 else "нет", c0, int(r0["rev"])],
		int(r0["arrived"]) >= 0 and c0 <= 2 and int(r0["rev"]) == 0)
	# Марш вперёд 70 м
	var b1: Vector3 = FIELD + Vector3(76.0, 0.0, 0.0)
	await _order(sids, b1)
	var r1: Dictionary = await _track("B марш линией 70 м", sids, 120.0, 6.0)
	var c1: int = _crossings(r1["tracks"])
	var sw1: int = _order_swaps(r1["tracks"], Vector3(1.0, 0.0, 0.0))
	verdict("B2 на марше фланги не меняются местами (пар %d) и следы не перекрещиваются (%d)" % [sw1, c1],
		int(r1["arrived"]) >= 0 and sw1 == 0 and c1 == 0)
	verdict("B2б бойцы: назад %d, на месте %d, не на посту %d из %d" % [int(r1["back_n"]), int(r1["inplace_n"]), int(r1["off_post"]), int(r1["men"])],
		int(r1["back_n"]) == 0 and int(r1["inplace_n"]) <= 2 and float(r1["off_post"]) <= 0.03 * float(maxi(int(r1["men"]), 1)))
	# Марш под 90°: группа разворачивается — перестроение неизбежно, но
	# без петель и без бега назад
	var b2: Vector3 = b1 + Vector3(0.0, 0.0, 60.0)
	await _order(sids, b2)
	var r2: Dictionary = await _track("B марш под 90° 60 м", sids, 120.0, 6.0)
	var ratio2: float = _path_ratio(r2, func(a, b): return (a as Vector3).distance_to(b as Vector3))
	verdict("B3 поворот группы на 90°: без петель (путь ×%.2f ≤ 1.3, разворотов %d), назад %d, на месте %d" % [
		ratio2, int(r2["rev"]), int(r2["back_n"]), int(r2["inplace_n"])],
		int(r2["arrived"]) >= 0 and ratio2 <= 1.3 and int(r2["rev"]) == 0 and int(r2["back_n"]) == 0)
	_kill(sids)
	sm.clear_selection()
	await pframes(20)

# ═════════════════════════════════════════════════════════════════════════════
# C. ПРЕПЯТСТВИЯ: ПРОХОД В ЛЕСНОЙ СТЕНЕ, РЕКА ЧЕРЕЗ БРОД
# ═════════════════════════════════════════════════════════════════════════════
func _block_c() -> void:
	print("\n═════ C. ПРЕПЯТСТВИЯ ═════")
	# ── C1. Проход в лесной стене базы игрока (правая стена) ───────────────
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	var gap_z: float = base.z + main.WALL_GAP_RIGHT_AT
	var wall_x: float = main._wall_right_x(gap_z)
	var gap := Vector3(wall_x, 0.0, gap_z)
	# Прямая A→B упирается в стену в 8 м от кромки прохода
	var a1 := Vector3(wall_x - 34.0, 0.0, gap_z - 10.0)
	var b1 := Vector3(wall_x + 34.0, 0.0, gap_z + main.WALL_GAP_W * 0.5 + 8.0 + 24.0)
	for p in [a1, b1]:
		main._clear_area_of_resources(p, 22.0)
		for n0 in get_tree().get_nodes_in_group("all_units"):
			if is_instance_valid(n0) and n0 is Unit and (n0 as Unit).faction != F and (n0 as Unit).global_position.distance_to(p) < 40.0:
				(n0 as Unit).take_damage(1.0e12)
	await pframes(4)
	var sids: Array = _group(a1)
	await pframes(30)
	print("    стена x=%.0f, проход z=%.0f±%.0f; A (%.0f, %.0f) → B (%.0f, %.0f)" % [wall_x, gap_z, main.WALL_GAP_W * 0.5, a1.x, a1.z, b1.x, b1.z])
	await _order(sids, b1)
	var r1: Dictionary = await _track("C проход в лесной стене", sids, 150.0, 7.0)
	var ratio1: float = _path_ratio(r1, func(a, b): return (a as Vector3).distance_to(gap) + gap.distance_to(b as Vector3))
	var through := 0
	for k in (r1["tracks"] as Dictionary):
		for p in ((r1["tracks"] as Dictionary)[k] as Array):
			if absf((p as Vector3).x - wall_x) < 3.0 and absf((p as Vector3).z - gap_z) <= main.WALL_GAP_W * 0.5 + 2.0:
				through += 1
				break
	verdict("C1 лесная стена: дошли (%s) через проход (отрядов %d из %d), дуга минимальна — путь ≤ 1.25 × (A→проход→B) (×%.2f), разворотов %d" % [
		("%d с" % (int(r1["arrived"]) / 60)) if int(r1["arrived"]) >= 0 else "нет", through, sids.size(), ratio1, int(r1["rev"])],
		int(r1["arrived"]) >= 0 and through >= sids.size() - 1 and ratio1 <= 1.25 and int(r1["rev"]) == 0)
	verdict("C1б у стены без метаний: крутых поворотов ≤ 1 на отряд (%d), откатов ≤ 1 на отряд (%d), назад %d, на месте %d" % [
		int(r1["turns"]), _sum(r1["regress"]), int(r1["back_n"]), int(r1["inplace_n"])],
		int(r1["turns"]) <= sids.size() and _sum(r1["regress"]) <= sids.size() and int(r1["back_n"]) == 0)
	_kill(sids)
	sm.clear_selection()
	await pframes(20)
	# ── C2. Река: прямая через глубокую воду, дорога — через брод ───────────
	var rx: float = main.river_x(main.FORD_Z)
	var ford := Vector3(rx, 0.0, main.FORD_Z)
	var a2: Vector3 = _dry(Vector3(rx - 60.0, 0.0, main.FORD_Z - 55.0))
	var b2: Vector3 = _dry(Vector3(rx + 60.0, 0.0, main.FORD_Z - 55.0))
	for p2 in [a2, b2, ford]:
		main._clear_trees(p2, 24.0)
		for n1 in get_tree().get_nodes_in_group("all_units"):
			if is_instance_valid(n1) and n1 is Unit and (n1 as Unit).faction != F and (n1 as Unit).global_position.distance_to(p2) < 45.0:
				(n1 as Unit).take_damage(1.0e12)
	await pframes(4)
	var sids2: Array = _group(a2)
	await pframes(30)
	print("    река x=%.0f, брод z=%.0f; A (%.0f, %.0f) → B (%.0f, %.0f), прямая через воду" % [rx, main.FORD_Z, a2.x, a2.z, b2.x, b2.z])
	await _order(sids2, b2)
	# Лямбда GDScript захватывает int ПО ЗНАЧЕНИЮ — счётчик держим в словаре
	var st := {"water": 0}
	var r2: Dictionary = await _track("C река через брод", sids2, 220.0, 8.0, func(f):
		if f % 30 == 0:
			for s in sids2:
				for u in _members(int(s)):
					var p3: Vector3 = (u as Unit).global_position
					if main.is_water(p3.x, p3.z) and not main.in_ford(p3.z):
						st["water"] = int(st["water"]) + 1)
	var water: int = int(st["water"])
	var ratio2: float = _path_ratio(r2, func(a, b): return (a as Vector3).distance_to(ford) + ford.distance_to(b as Vector3))
	verdict("C2 река: дошли (%s), в глубокой воде 0 (%d), путь ≤ 1.2 × (A→брод→B) (×%.2f), разворотов назад %d" % [
		("%d с" % (int(r2["arrived"]) / 60)) if int(r2["arrived"]) >= 0 else "нет", water, ratio2, int(r2["rev"])],
		int(r2["arrived"]) >= 0 and water == 0 and ratio2 <= 1.2 and int(r2["rev"]) == 0)
	verdict("C2б у брода без метаний: крутых поворотов ≤ 2 на отряд (%d), откатов ≤ 2 на отряд (%d), назад %d" % [
		int(r2["turns"]), _sum(r2["regress"]), int(r2["back_n"])],
		int(r2["turns"]) <= 2 * sids2.size() and _sum(r2["regress"]) <= 2 * sids2.size() and int(r2["back_n"]) == 0)
	_kill(sids2)
	sm.clear_selection()
	await pframes(20)

# ═════════════════════════════════════════════════════════════════════════════
# D. ПЕРЕПРИКАЗ НА ХОДУ
# ═════════════════════════════════════════════════════════════════════════════
func _block_d() -> void:
	print("\n═════ D. ПЕРЕПРИКАЗ НА ХОДУ ═════")
	_clear(FIELD + Vector3(35.0, 0.0, 20.0), 80.0)
	await pframes(4)
	var sids: Array = _group(FIELD)
	await pframes(30)
	var p1: Vector3 = FIELD + Vector3(80.0, 0.0, 0.0)
	await _order(sids, p1)
	# Лямбда захватывает int/Vector3 по значению — состояние в словаре
	var st := {"cen": [], "reorder_f": -1, "p2": Vector3.INF, "posts_changed": 0}
	var men_n := 0
	var pre_posts: Dictionary = {}
	for s in sids:
		for u in _members(int(s)):
			pre_posts[u] = (u as Unit).post_pos
			men_n += 1
	var r: Dictionary = await _track("D марш с переприказом", sids, 150.0, 6.0, func(f):
		var rf: int = int(st["reorder_f"])
		if f == 60 * 6:
			# Новая точка — под 90° от текущего хода, 50 м
			var all: Array = []
			for s in sids:
				all.append_array(_members(int(s)))
			var c: Vector3 = _median(all)
			st["p2"] = c + Vector3(0.0, 0.0, 50.0)
			sm.select_units(all)
			sm.order_at_world(st["p2"], false)
			st["reorder_f"] = f
		elif rf > 0 and f == rf + 60:
			var n := 0
			for s in sids:
				for u in _members(int(s)):
					if pre_posts.has(u) and (u as Unit).post_pos.distance_to(pre_posts[u] as Vector3) > 0.5:
						n += 1
			st["posts_changed"] = n
		elif rf > 0 and f > rf and f % 15 == 0 and f <= rf + 60 * 6:
			var all2: Array = []
			for s in sids:
				all2.append_array(_members(int(s)))
			(st["cen"] as Array).append(_median(all2)))
	var cen: Array = st["cen"]
	var p2: Vector3 = st["p2"]
	var posts_changed: int = int(st["posts_changed"])
	# Разворот: ход центра группы в окне 2-4 с после переприказа — к новой точке
	var aligned := false
	var moved_15 := 0.0
	if cen.size() >= 16 and p2.x != INF:
		var c2: Vector3 = cen[7]      # ~2 с
		var c4: Vector3 = cen[15]     # ~4 с
		var v: Vector3 = c4 - c2
		v.y = 0.0
		var want: Vector3 = p2 - c2
		want.y = 0.0
		aligned = v.length() > 1.0 and v.normalized().dot(want.normalized()) > 0.7
		var c15: Vector3 = cen[5]     # ~1.5 с
		var c0: Vector3 = cen[0]
		moved_15 = (c15 - c0).length()
		print("    после переприказа: за 1.5 с центр сдвинулся на %.1f м; ход в окне 2-4 с %s к новой точке (cos %.2f)" % [
			moved_15, "идёт" if aligned else "НЕ идёт", v.normalized().dot(want.normalized()) if v.length() > 0.01 else 0.0])
	verdict("D1 переприказ принят всеми: посты сменились у %d из %d бойцов за 1 с" % [posts_changed, men_n],
		posts_changed >= int(float(men_n) * 0.95))
	verdict("D2 вектор сменился плавно и сразу: через 2-4 с группа идёт к новой точке (%s), без зависания" % str(aligned), aligned)
	verdict("D3 дошли до новой точки (%s), разворотов назад по следам ≤ 1 на отряд (%d), бега на месте ≤ 2 (%d)" % [
		("%d с" % (int(r["arrived"]) / 60)) if int(r["arrived"]) >= 0 else "нет", int(r["rev"]), int(r["inplace_n"])],
		int(r["arrived"]) >= 0 and int(r["rev"]) <= sids.size() and int(r["inplace_n"]) <= 2)
	verdict("D4 строй не сброшен: на приходе не на посту ≤ 3 %% (%d из %d)" % [int(r["off_post"]), int(r["men"])],
		float(r["off_post"]) <= 0.03 * float(maxi(int(r["men"]), 1)))
	_kill(sids)
	sm.clear_selection()
	await pframes(20)
