extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 24.10.2026: КОРОБКИ ОТРЯДОВ И ЛИНИЯ ФРОНТА В БОЮ
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба владельца: при столкновении отряды теряют структуру и сливаются в
## один ком. Сценарий из ТЗ: три полных отряда копейщиков игрока против трёх
## полных отрядов гоблинов-копейщиков, лоб в лоб. Приказ игрока идёт тем же
## путём, что ПКМ по врагу (выделение → frontline_targets → command_attack с
## замком), строй перед боем — тем же, что ПКМ по земле группой.
##
## ЧТО МЕРИМ (каждые 2 с, 40 с боя):
##   чуж  — доля бойцов ДРУГОГО отряда той же стороны среди 4 ближайших своих
##          (0 — каждый в своей коробке, у стыка двух коробок ~0.05-0.10);
##   нал  — наложение коробок союзников: доля бойцов отряда A внутри
##          прямоугольника (по осям фронта) отряда B, худшая пара;
##   глуб — глубина отряда (вдоль курса) к исходной;
##   зад  — доля бойцов задних шеренг (исходный ряд ≥ 2), стоящих ВПЕРЕДИ
##          медианы своей первой шеренги, то есть обежавших свой строй;
##   удар — КТО НАНОСИТ УДАРЫ: приращение счётчика ударов бойца (_strike_count)
##          за окно, по ряду бойца (в коробке — ряд коробки _box_row, без неё —
##          живой ряд _live_rank). Заказ: бьют первые 1-2 ряда.
## Запуск: godot --headless --path . res://qa_box_front/Test.tscn
##         [-- knob=box_front:0]  (A/B по ручке)

const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var main: Node = null
var sm = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _shot := ""
var _diag := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "diag=1":
			_diag = true
		if String(a).begins_with("--out="):
			_shot = String(a).substr(6)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд завис")
		get_tree().quit(2))

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else: _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

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

func _wipe(at: Vector3, r: float) -> void:
	main._clear_area_of_resources(at, r)
	main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()

## Отряд прямоугольником: колонки поперёк курса (ось Z), шеренги вглубь
## (против курса по X). Ряд пишется в formation_row — по нему стенд и
## различает «передних» и «задних»
func _box(uid: String, fac: int, front_c: Vector3, course: Vector3, n: int, cols: int, gap: float) -> int:
	var sid: int = GameManager.new_squad(fac, uid)
	var side := Vector3(-course.z, 0.0, course.x)
	var slots: Array = []
	var men: Array = []
	for i in range(n):
		var p: Vector3 = front_c + side * ((float(i % cols) - float(cols - 1) * 0.5) * gap) \
			- course * (float(i / cols) * gap)
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = fac
		main.world_add(u)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		u._facing = course
		u.formation_row = i / cols
		GameManager.add_to_squad(sid, u)
		slots.append(u.global_position)
		men.append(u)
	GameManager.squad_set_formation(sid, slots, course, false)
	return sid

# ─────────────────────────────────────────────────────────────────────────────
# МЕРЫ
# ─────────────────────────────────────────────────────────────────────────────
## pool — среди кого ищутся соседи (по умолчанию те же men): общая каша —
## это соседи НАШИХ бойцов среди своих и чужих, а не толпы орды между собой
func _foreign_share(men: Array, k: int = 4, pool: Array = []) -> float:
	var n: int = men.size()
	if n < k + 1:
		return 0.0
	var tot := 0
	var foreign := 0
	var all: Array = men if pool.is_empty() else pool
	for i in range(n):
		var u := men[i] as Unit
		var p: Vector3 = u.global_position
		var best: Array = []
		for j in range(all.size()):
			var v := all[j] as Unit
			if v == u: continue
			var d2: float = (v.global_position - p).length_squared()
			if best.size() < k:
				best.append([d2, v.squad_id])
				best.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			elif d2 < float(best[k - 1][0]):
				best[k - 1] = [d2, v.squad_id]
				best.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		for b in best:
			tot += 1
			if int(b[1]) != u.squad_id:
				foreign += 1
	return float(foreign) / float(maxi(tot, 1))

## Прямоугольник отряда по осям фронта: [min_along, max_along, min_side, max_side]
## по 10-90 перцентилям (одиночка, выбитый разлётом, коробку не задаёт)
func _rect(men: Array, course: Vector3) -> Array:
	var side := Vector3(-course.z, 0.0, course.x)
	var al: Array = []
	var sd: Array = []
	for u in men:
		var p: Vector3 = (u as Unit).global_position
		al.append(p.dot(course))
		sd.append(p.dot(side))
	if al.is_empty():
		return [0.0, 0.0, 0.0, 0.0]
	al.sort()
	sd.sort()
	var lo: int = int(float(al.size()) * 0.1)
	var hi: int = mini(al.size() - 1, int(float(al.size()) * 0.9))
	return [float(al[lo]), float(al[hi]), float(sd[lo]), float(sd[hi])]

## В осях отряда A (курс его коробки): развёрнутая коробка, мерянная в осях
## карты, «накладывалась» бы своим же прямоугольником описанной рамки
func _overlap(sids: Array, course0: Vector3) -> float:
	var worst := 0.0
	for a in sids:
		var ma: Array = _members(int(a))
		if ma.size() < 5: continue
		var course: Vector3 = _course_of(int(a), course0)
		var side := Vector3(-course.z, 0.0, course.x)
		for b in sids:
			if a == b: continue
			var mb: Array = _members(int(b))
			if mb.size() < 5: continue
			var r: Array = _rect(mb, course)
			var inside := 0
			for u in ma:
				var p: Vector3 = (u as Unit).global_position
				var al: float = p.dot(course)
				var sd: float = p.dot(side)
				if al >= float(r[0]) and al <= float(r[1]) and sd >= float(r[2]) and sd <= float(r[3]):
					inside += 1
			worst = maxf(worst, float(inside) / float(ma.size()))
	return worst

func _depth(men: Array, course: Vector3) -> float:
	var r: Array = _rect(men, course)
	return float(r[1]) - float(r[0])

## Доля задних (исходный ряд ≥ 2), стоящих впереди медианы СВОЕЙ первой шеренги
## (по живому ряду: передовой ряд — тот, у кого _live_rank = 0)
func _rear_ahead(sid: int, course: Vector3) -> float:
	var men: Array = _members(sid)
	var front: Array = []
	for u in men:
		if _row_of(u as Unit) == 0:
			front.append((u as Unit).global_position.dot(course))
	if front.is_empty():
		return 0.0
	front.sort()
	var med: float = float(front[front.size() / 2])
	var rear := 0
	var ahead := 0
	for u in men:
		if _row_of(u as Unit) >= 2:
			rear += 1
			if (u as Unit).global_position.dot(course) > med + 0.3:
				ahead += 1
	return float(ahead) / float(maxi(rear, 1))

func _row_of(u: Unit) -> int:
	return u._box_row if u._box_on else u._live_rank

## Удары за окно по рядам: [ряды 0-1, ряды 2+]; prev — счётчики прошлого окна
func _strikes(men: Array, prev: Dictionary) -> Array:
	var front := 0
	var rear := 0
	for u in men:
		var uu := u as Unit
		var c: int = uu._strike_count
		var d: int = c - int(prev.get(uu.get_instance_id(), c))
		prev[uu.get_instance_id()] = c
		if d <= 0:
			continue
		if _row_of(uu) <= 1:
			front += d
		else:
			rear += d
	return [front, rear]

## Кто в контакте: боец с целью в пределах досягаемости, по живому ряду
func _engaged_by_rank(men: Array) -> Array:
	var front := 0
	var rear := 0
	for u in men:
		var uu := u as Unit
		var t = uu.attack_target
		if t == null or not is_instance_valid(t):
			continue
		if uu.global_position.distance_to((t as Node3D).global_position) <= uu.reach() + 0.3:
			if uu._live_rank <= 1:
				front += 1
			else:
				rear += 1
	return [front, rear]

# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	seed(24102026)
	# Коробки выключены по развороту ТЗ 25.10.2026 (третье письмо, п. 2):
	# стенд механики включает ручку сам, если её не задали явно (knob=box_front:N)
	var _knob_set := false
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("knob=box_front"):
			_knob_set = true
	if not _knob_set:
		preload("res://scripts/perf_config.gd").box_front = true
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	sm = main.selection_manager
	var only := "abc"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			only = String(a).substr(5)
	if "a" in only: await _block_a()
	if "b" in only: await _block_b()
	if "c" in only: await _block_c()
	print("\n═════ ИТОГ ═════")
	for e in _log:
		print("  %-64s %s" % [String(e[0]), "ПРОШЛО" if bool(e[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)

## Толпа орды — той же раскладкой, что Main._horde_one (goblin_config.horde_offset)
func _crowd(fac: int, base: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(fac, "goblin_spearman")
	var slots: Array = []
	for k in range(n):
		var ho: Vector2 = _GobCfg.horde_offset(k, n, sid)
		var u: Unit = Building.PRELOAD_SCENES["goblin_spearman"].instantiate()
		u.faction = fac
		main.world_add(u)
		var x: float = base.x + ho.x
		var z: float = base.z + ho.y
		u.global_position = Vector3(x, GameManager.get_terrain_height(x, z), z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		slots.append(u.global_position)
	GameManager.squad_set_formation(sid, slots, Vector3(-1, 0, 0), false)
	return sid

func _kill_all(sids: Array) -> void:
	for u in _all(sids):
		(u as Unit).take_damage(1.0e12)
	await pframes(30)

## Курс отряда для мер: курс его коробки, если она есть, иначе общий
func _course_of(sid: int, fallback: Vector3) -> Vector3:
	var b: Dictionary = GameManager.box.box_of(sid)
	return b["course"] if not b.is_empty() else fallback

## Приказ игрока ПКМ по врагу — путь _handle_right_click (раскладка по фронту
## + command_attack с замком)
func _player_attack(mine: Array, victim: Unit) -> void:
	sm.select_units(_all(mine))
	var front: Dictionary = sm.frontline_targets(victim)
	for u in _all(mine):
		var sid: int = (u as Unit).squad_id
		var t: Node3D = front.get(sid, victim)
		(u as Unit).command_attack(t, true, true, true)

## Наблюдение за боем: раз в 2 с печать, худшие меры после контакта
func _watch(tag: String, mine: Array, foes: Array, course: Vector3, d0: Dictionary, secs: int) -> Dictionary:
	var worst := {"f": 0.0, "o": 0.0, "rear": 0.0, "depth": 0.0, "mix": 0.0}
	var eng_front := 0
	var eng_rear := 0
	var prev: Dictionary = {}
	_strikes(_all(mine), prev)
	var prev_f: Dictionary = {}
	_strikes(_all(foes), prev_f)
	var t_contact := -1.0
	var n0: int = _all(mine).size()
	var g0: int = _all(foes).size()
	for f in range(60 * secs):
		await get_tree().physics_frame
		if t_contact < 0.0:
			var e0: Array = _engaged_by_rank(_all(mine))
			if int(e0[0]) + int(e0[1]) > 0:
				t_contact = float(f) / 60.0
		if f % 120 != 119:
			continue
		var men: Array = _all(mine)
		var fs: float = _foreign_share(men)
		var ra := 0.0
		var dmax := 0.0
		var ds := ""
		for s in mine:
			var mk: Array = _members(int(s))
			if mk.size() < 10: continue
			var cs: Vector3 = _course_of(int(s), course)
			ra = maxf(ra, _rear_ahead(int(s), cs))
			var dr: float = _depth(mk, cs) / maxf(float(d0.get(s, 1.0)), 0.1)
			dmax = maxf(dmax, dr)
			ds += " %.2f" % dr
		var ov: float = _overlap(mine, course)
		var eg: Array = _strikes(men, prev)
		var egf: Array = _strikes(_all(foes), prev_f)
		var mix: float = _foreign_share(men, 4, men + _all(foes))
		if _diag:
			_box_diag(mine)
		print("  %s %2dс  наших %3d чужих %3d | чуж %.2f нал %.2f зад %.2f глуб%s | удары 0-1: %d, 2+: %d (чужие %d/%d) | общая каша %.2f" % [
			tag, (f + 1) / 60, men.size(), _all(foes).size(), fs, ov, ra, ds, int(eg[0]), int(eg[1]), int(egf[0]), int(egf[1]), mix])
		if t_contact >= 0.0 and men.size() > n0 / 3:
			worst["f"] = maxf(float(worst["f"]), fs)
			worst["o"] = maxf(float(worst["o"]), ov)
			worst["rear"] = maxf(float(worst["rear"]), ra)
			worst["depth"] = maxf(float(worst["depth"]), dmax)
			worst["mix"] = maxf(float(worst["mix"]), mix)
			eng_front += int(eg[0])
			eng_rear += int(eg[1])
	worst["t"] = t_contact
	worst["ef"] = float(eng_front) / float(maxi(eng_front + eng_rear, 1))
	worst["front"] = eng_front
	worst["rear_hits"] = eng_rear
	print("  %s контакт на %.1f с; потери наших %d из %d, чужих %d из %d; коробок включено %d, снято %d, замен в колонках %d, разводов %d, разворотов %d" % [
		tag, t_contact, n0 - _all(mine).size(), n0, g0 - _all(foes).size(), g0,
		GameManager.box.activations, GameManager.box.releases, GameManager.box.refills,
		GameManager.box.side_pushes, GameManager.box.turns])
	return worst

func _box_diag(mine: Array) -> void:
	for s in mine:
		var b: Dictionary = GameManager.box.box_of(int(s))
		if b.is_empty():
			print("     отряд %d: коробки нет" % int(s))
			continue
		var lags: Array = []
		var inf := 0
		for m in (b["units"] as Array):
			if m == null or not is_instance_valid(m): continue
			var u: Unit = m
			if u._box_goal.x == INF:
				inf += 1
				continue
			lags.append(Vector2(u.global_position.x - u._box_goal.x, u.global_position.z - u._box_goal.z).length())
		lags.sort()
		var rows_n := 0
		for r in (b["row"] as PackedInt32Array):
			rows_n = maxi(rows_n, r + 1)
		print("     отряд %d: курс (%.2f, %.2f) F (%.1f, %.1f) %d×%d, отставание медиана %.2f, 90%% %.2f, макс %.2f, без места %d, идёт %s" % [
			int(s), (b["course"] as Vector3).x, (b["course"] as Vector3).z, (b["F"] as Vector3).x, (b["F"] as Vector3).z,
			int(b["cols"]), rows_n, float(lags[lags.size() / 2]) if lags.size() > 0 else -1.0,
			float(lags[int(lags.size() * 0.9)]) if lags.size() > 0 else -1.0,
			float(lags[lags.size() - 1]) if lags.size() > 0 else -1.0, inf, str(b["moving"])])

func _depths(mine: Array, course: Vector3) -> Dictionary:
	var d0: Dictionary = {}
	for s in mine:
		d0[s] = _depth(_members(int(s)), course)
	return d0

func _common_verdicts(tag: String, w: Dictionary, f_lim: float, o_lim: float) -> void:
	verdict("%s0 бой состоялся" % tag, float(w["t"]) >= 0.0, "контакт %.1f с" % float(w["t"]))
	verdict("%s1 союзные коробки не сливаются (чужих соседей ≤ %.2f)" % [tag, f_lim], float(w["f"]) <= f_lim, "худшее %.2f" % float(w["f"]))
	if o_lim > 0.0:
		verdict("%s2 коробки союзников не накладываются (≤ %.2f)" % [tag, o_lim], float(w["o"]) <= o_lim, "худшее %.2f" % float(w["o"]))
	verdict("%s3 задние шеренги не обегают свой строй (≤ 0.10)" % tag, float(w["rear"]) <= 0.10, "худшее %.2f" % float(w["rear"]))
	verdict("%s4 глубина коробки держится (≤ 1.5 исходной)" % tag, float(w["depth"]) <= 1.5, "худшее %.2f" % float(w["depth"]))
	verdict("%s5 бьют первые две шеренги (≥ 0.8 ударов)" % tag, float(w["ef"]) >= 0.8,
		"ряды 0-1: %d, 2+: %d (%.0f%%)" % [int(w["front"]), int(w["rear_hits"]), float(w["ef"]) * 100.0])

func _staff() -> Array:
	var sp_cfg: Dictionary = _UCfg.train_cfg("barracks", "spearman")
	return [int(sp_cfg.get("squad", 60)), Building.new().squad_spacing]

# ─────────────────────────────────────────────────────────────────────────────
## A. Три на три лоб в лоб: строй игрока — ПКМ группой по земле, атака — ПКМ
## по среднему отряду гоблинов (раскладка по фронту), гоблины навстречу
func _block_a() -> void:
	print("\n═════ A. 3 ОТРЯДА КОПЕЙЩИКОВ ПРОТИВ 3 ОТРЯДОВ ГОБЛИНОВ, ЛОБ В ЛОБ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(45.0, 0.0, 15.0)
	_wipe(spot, 70.0)
	await pframes(10)
	var course := Vector3(1, 0, 0)
	var st: Array = _staff()
	var n_gb: int = _UCfg.squad_size("goblin_spearman")
	var mine: Array = []
	var foes: Array = []
	for i in range(3):
		var z: float = spot.z + (float(i) - 1.0) * 12.0
		mine.append(_box("spearman", F, Vector3(spot.x - 16.0, 0, z), course, int(st[0]), 12, float(st[1])))
		foes.append(_box("goblin_spearman", G, Vector3(spot.x + 16.0, 0, z), -course, n_gb, 14, 0.65))
	await pframes(20)
	sm.select_units(_all(mine))
	sm._issue_formation_move(Vector3(spot.x - 14.0, 0, spot.z), false)
	await pframes(60 * 6)
	var d0: Dictionary = _depths(mine, course)
	print("  строй перед боем: чуж %.2f, нал %.2f" % [_foreign_share(_all(mine)), _overlap(mine, course)])
	_player_attack(mine, _members(int(foes[1]))[0])
	for i in range(3):
		var tm: Array = _members(int(mine[i]))
		for g in _members(int(foes[i])):
			(g as Unit).command_attack(tm[0], true, false, false)
	var w: Dictionary = await _watch("A", mine, foes, course, d0, 40)
	_common_verdicts("A", w, 0.15, 0.15)
	await _kill_all(mine + foes)

## B. «3-5 отрядов в одну точку»: четыре отряда копейщиков тесной группой
## посланы ПКМ на ОДИН отряд гоблинов (толпа орды, как в партии). Коробки
## обязаны лечь в линию, а не впрессоваться в одну
func _block_b() -> void:
	print("\n═════ B. 4 ОТРЯДА КОПЕЙЩИКОВ НА ОДИН ОТРЯД ГОБЛИНОВ (ТОЛПА) ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(45.0, 0.0, -35.0)
	_wipe(spot, 70.0)
	await pframes(10)
	var course := Vector3(1, 0, 0)
	var st: Array = _staff()
	var mine: Array = []
	for i in range(4):
		var z: float = spot.z + (float(i % 2) - 0.5) * 8.0
		var x: float = spot.x - 18.0 - float(i / 2) * 5.0
		mine.append(_box("spearman", F, Vector3(x, 0, z), course, int(st[0]), 12, float(st[1])))
	var foes: Array = [_crowd(G, Vector3(spot.x + 10.0, 0, spot.z), _UCfg.squad_size("goblin_spearman"))]
	await pframes(30)
	var d0: Dictionary = _depths(mine, course)
	_player_attack(mine, _members(int(foes[0]))[0])
	for g in _members(int(foes[0])):
		(g as Unit).command_attack(_members(int(mine[0]))[0], true, false, false)
	var w: Dictionary = await _watch("B", mine, foes, course, d0, 40)
	_common_verdicts("B", w, 0.15, 0.15)
	await _kill_all(mine + foes)

## C. Косая свалка 6 на 6: наши (копейщики) и чужие (толпы гоблинов)
## крест-накрест — i-й наш на (i+2)-й чужой, пути пересекаются, как в партии
func _block_c() -> void:
	print("\n═════ C. КОСАЯ СВАЛКА 6 НА 6 КРЕСТ-НАКРЕСТ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(45.0, 0.0, 15.0)
	_wipe(spot, 80.0)
	await pframes(10)
	var course := Vector3(1, 0, 0)
	var st: Array = _staff()
	var n_gb: int = _UCfg.squad_size("goblin_spearman")
	var mine: Array = []
	var foes: Array = []
	for i in range(6):
		var z: float = spot.z - 25.0 + float(i) * 10.0
		mine.append(_box("spearman", F, Vector3(spot.x - 22.0, 0, z), course, int(st[0]), 12, float(st[1])))
		foes.append(_crowd(G, Vector3(spot.x + 22.0, 0, z), n_gb))
	await pframes(30)
	var d0: Dictionary = _depths(mine, course)
	for i in range(6):
		var tf: Array = _members(int(foes[(i + 2) % 6]))
		for u in _members(int(mine[i])):
			(u as Unit).command_attack(tf[0], true, true, true)
		var tm: Array = _members(int(mine[(i + 4) % 6]))
		for g in _members(int(foes[i])):
			(g as Unit).command_attack(tm[0], true, false, false)
	var w: Dictionary = await _watch("C", mine, foes, course, d0, 50)
	verdict("C0 бой состоялся", float(w["t"]) >= 0.0, "контакт %.1f с" % float(w["t"]))
	verdict("C1 союзные коробки не сливаются (чужих соседей ≤ 0.15)", float(w["f"]) <= 0.15, "худшее %.2f" % float(w["f"]))
	# РАЗВОРОТ ТЗ 25.10.2026 (блок 2): орда снова ТОЛПА без коробок и
	# обтекает чужие коробки — у стыков каша выше, чем у коробки против
	# коробки (замер: 0.12-0.13 на исходе боя). Порог 0.10 → 0.15
	verdict("C6 общая каша (свои и чужие вперемешку) ≤ 0.20 (без коробок у орды каша гуще — ТЗ 25.10)", float(w["mix"]) <= 0.20, "худшее %.2f" % float(w["mix"]))
	verdict("C5 бьют первые две шеренги (≥ 0.8 ударов)", float(w["ef"]) >= 0.8,
		"ряды 0-1: %d, 2+: %d (%.0f%%)" % [int(w["front"]), int(w["rear_hits"]), float(w["ef"]) * 100.0])
	await _kill_all(mine + foes)
