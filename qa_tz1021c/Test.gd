extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 21.10.2026 (четвёртое письмо): агро на урон, стрелы по хижинам,
## знамёна, раскладка смешанного строя, курсор-топор
## ═══════════════════════════════════════════════════════════════════════════
##   A — обстрел лучниками: тролль (с логовом и без), туша, гнолл, пехота орды
##       не стоят под стрелами — берут стрелка целью и сближаются
##   B — копейщики в [S] после стычки: подошедшая туша бьёт — отвечают сами
##   C — стрелы по хижине и главной хате орды снимают запас
##   D — знамёна: у отрядов с рангом только треугольные вымпелы, коронок нет
##   E — смешанный строй глубокой протяжкой: пехота ровными шеренгами, тыл
##       (лучники, рыцари малым числом) — компактный прямоугольник за ней
##   F — курсор-топор: лезвие вниз (пиксели лезвия в нижней половине)
## Отход из боя — отдельные стенды qa_forced_retreat_in_combat и
## qa_attack_move_override.
## Запуск: godot --headless --path . res://qa_tz1021c/Test.tscn [-- only=abcdef]

const _Opt := preload("res://scripts/perf_config.gd")
const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _Hut := preload("res://scripts/goblin/GoblinHut.gd")
const _Chief := preload("res://scripts/goblin/GoblinChiefHut.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcdef"
var _done := false

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

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz1021c: прошло %d, провалов: %d ═════" % [_pass, _fail])
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
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _place(b: Building, at: Vector3, fac: int = F) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

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

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "a" in _only: await _a_fire_aggro()
	if "b" in _only: await _b_hold_vs_big()
	if "c" in _only: await _c_hut_arrows()
	if "d" in _only: _d_banners()
	if "e" in _only: await _e_mixed_formation()
	if "f" in _only: _f_axe()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
# A. ОБСТРЕЛ: КРУПНЫЕ И ДИКИЕ НЕ СТОЯТ ПОД СТРЕЛАМИ
# ─────────────────────────────────────────────────────────────────────────────
## Лучники (12) в 17 м бьют одиночку (или отряд) приказом; через secs секунд:
## стала ли целью стреляющая сторона и сократилась ли дистанция
func _fire_case(kind: String, at: Vector3, n: int, lair_node: Node = null,
		pre_target: bool = false) -> Dictionary:
	_clear(at, 45.0)
	await pframes(3)
	var foes: Array = _squad(kind, at, n, G, 3) if n > 1 else [_spawn(kind, at, G)]
	# Запас ×6: замер — РЕАКЦИЯ, а не кто кого перестреляет (гнолл иначе
	# падает от двенадцати луков раньше, чем добежит)
	for f in foes:
		(f as Unit).max_health *= 6.0
		(f as Unit).current_health = (f as Unit).max_health
		if lair_node != null:
			f.set("lair", lair_node)
		# Стоит на месте (патруль гнолла иначе уводит его из-под огня — замер
		# тогда о промахах по бегущему, а не об ответе)
		(f as Unit).command_move((f as Node3D).global_position)
	# Занятая цель: стоит, «видя» далёкую овцу/пост — тролль у пня в патруле
	if pre_target:
		# Цель — за спиной у лучников, в 45 м: путь к ней ведёт мимо стрелков
		var bait := _spawn("worker", at + Vector3(-45.0, 0, -2.0), F)
		bait.set_tick(false)
		for f in foes:
			(f as Unit).command_attack(bait, false)
	# Дистанция — ОТ ДАЛЬНОСТИ ЛУКА ИЗ КОНФИГА (ТЗ 22.10.2026): было 17 м при
	# базовой дальности 15 — патрулирующий гнолл стоял за досягаемостью,
	# лучник по правилу за целью не идёт, и «не отвечал» нетронутый гнолл (A6)
	var arc_r: float = float(_UCfgT.stat("archer", "attack_range", 15.0))
	var archers: Array = _squad("archer", at + Vector3(-minf(17.0, arc_r - 3.0), 0, -2.0), 12, F, 4)
	await pframes(10)
	var d0: float = 1e9
	for a in archers:
		d0 = minf(d0, (a as Node3D).global_position.distance_to((foes[0] as Node3D).global_position))
		(a as Unit).command_attack(foes[0], true)
	var hp0: float = (foes[0] as Unit).current_health
	var answered := 0
	var closed := 0
	var t := 0
	while t < 600:
		await pframes(10)
		t += 10
		answered = 0
		closed = 0
		for f in _alive(foes):
			var tg = (f as Unit).attack_target
			if tg != null and is_instance_valid(tg) and tg is Unit and (tg as Unit).stat_id == "archer":
				answered += 1
			var dm: float = 1e9
			for a in _alive(archers):
				dm = minf(dm, (a as Node3D).global_position.distance_to((f as Node3D).global_position))
			# Сблизился — или уже бьёт со своей дальности (гнолл мечет кости)
			if dm < d0 - 4.0 or ((f as Unit).state == Unit.State.ATTACKING 					and dm <= (f as Unit).attack_range + 1.0):
				closed += 1
		# «Под огнём» — тоже условие выхода: занятый гнолл сближается раньше,
		# чем долетает первая стрела (стрелки в 12 м, ТЗ 22.10.2026)
		if closed > 0 and answered > 0 and is_instance_valid(foes[0]) \
				and (foes[0] as Unit).current_health < hp0:
			break
	var hp1: float = (foes[0] as Unit).current_health if is_instance_valid(foes[0]) else 0.0
	var res := {"answered": answered, "closed": closed, "n": _alive(foes).size(),
		"sec": float(t) / 60.0, "hit": hp1 < hp0}
	_free(foes)
	_free(archers)
	await pframes(5)
	return res

func _a_fire_aggro() -> void:
	print("\n═════ A. ОБСТРЕЛ ЛУЧНИКАМИ: ОТВЕТ СТРЕЛКУ ═════")
	var lair: Node = null
	for l in GameManager.troll_lairs:
		if l != null and is_instance_valid(l):
			lair = l
			break
	var cases := [
		["A1", "тролль без логова", "troll", 1, null, false],
		["A2", "тролль у логова", "troll", 1, lair, false],
		["A3", "тролль, занятый далёкой целью", "troll", 1, null, true],
		["A4", "туша (отряд 3)", "big_goblin", 3, null, false],
		["A5", "туша, занятая далёкой целью", "big_goblin", 1, null, true],
		["A6", "гнолл", "gnoll", 1, null, false],
		["A7", "гнолл, занятый далёкой целью", "gnoll", 1, null, true],
		["A8", "пехота орды (отряд 9)", "goblin_spearman", 9, null, false],
	]
	var z := -40.0
	for c in cases:
		var r: Dictionary = await _fire_case(String(c[2]), Vector3(-60, 0, z), int(c[3]), c[4], bool(c[5]))
		print("  %s %s: под огнём=%s, стрелка целью %d из %d, сблизились %d за %.1f с" % [
			c[0], c[1], r.hit, r.answered, r.n, r.closed, r.sec])
		verdict("%s %s отвечает стрелку" % [c[0], c[1]],
			bool(r.hit) and int(r.answered) > 0 and int(r.closed) > 0,
			"целью %d, сблизились %d" % [r.answered, r.closed])
		z += 22.0

# ─────────────────────────────────────────────────────────────────────────────
# B. КОПЕЙЩИКИ В [S] ПОСЛЕ СТЫЧКИ: ТУША БЬЁТ — ОТВЕЧАЮТ
# ─────────────────────────────────────────────────────────────────────────────
func _b_hold_vs_big() -> void:
	print("\n═════ B. КОПЕЙЩИКИ ПОСЛЕ СТЫЧКИ ОТВЕЧАЮТ ПОДОШЕДШЕЙ ТУШЕ ═════")
	for stance_s in [true, false]:
		var at := Vector3(-20, 0, -30) if stance_s else Vector3(-20, 0, 20)
		_clear(at, 40.0)
		await pframes(3)
		var men: Array = _squad("spearman", at, 24, F, 8)
		await pframes(5)
		var sm = main.selection_manager
		if stance_s:
			sm.select_units(men)
			sm._squad_cmd().stand_ground(sm)
			sm.clear_selection()
		await pframes(10)
		# Первая фаза: мелкая стычка с гоблинами, выбиты до последнего
		var gobs: Array = _squad("goblin_spearman", at + Vector3(2, 0, 5), 6, G, 3)
		var t := 0
		while t < 1200 and not _alive(gobs).is_empty():
			await pframes(10)
			t += 10
		_free(gobs)
		await pframes(120)          # тишина — отряд «остыл», стоит в покое
		var idle0 := 0
		for m in _alive(men):
			if (m as Unit).state == Unit.State.IDLE:
				idle0 += 1
		# Вторая фаза: туша подходит сбоку и бьёт крайнего
		var big := _spawn("big_goblin", at + Vector3(-9, 0, 1.4), G)
		var victim: Unit = null
		var best := 1e9
		for m in _alive(men):
			var d: float = (m as Node3D).global_position.distance_to(big.global_position)
			if d < best:
				best = d
				victim = m
		big.command_attack(victim, true)
		var hp0: float = big.current_health
		var answer := 0
		t = 0
		while t < 900 and is_instance_valid(big) and not big.is_dead():
			await pframes(10)
			t += 10
			answer = 0
			for m in _alive(men):
				if (m as Unit).attack_target == big:
					answer += 1
			if big.current_health < hp0 * 0.9 and answer > 0:
				break
		var dealt: float = hp0 - (big.current_health if is_instance_valid(big) else 0.0)
		print("  %s: в покое перед тушей %d, бьют тушу %d, сняли %.0f из %.0f за %.1f с" % [
			"[S]" if stance_s else "[C]", idle0, answer, dealt, hp0, float(t) / 60.0])
		verdict("B%d копейщики %s отвечают туше сами" % [1 if stance_s else 2, "[S]" if stance_s else "[C]"],
			answer * 3 >= _alive(men).size() and dealt >= hp0 * 0.08,
			"бьют %d из %d, урон %.0f (порог трети отряда и 8 %% запаса)" % [answer, _alive(men).size(), dealt])
		if is_instance_valid(big):
			big.queue_free()
		_free(men)
		await pframes(5)

# ─────────────────────────────────────────────────────────────────────────────
# C. СТРЕЛЫ ПО ХИЖИНАМ ОРДЫ
# ─────────────────────────────────────────────────────────────────────────────
func _c_hut_arrows() -> void:
	print("\n═════ C. СТРЕЛЫ ПО ХИЖИНЕ И ГЛАВНОЙ ХАТЕ ОРДЫ ═════")
	var i := 0
	for chief in [false, true]:
		for volley in [false, true]:
			i += 1
			var at := Vector3(30, 0, -40 + 25 * (i - 1))
			_clear(at, 40.0)
			await pframes(3)
			var hut: Building = (_Chief.new() if chief else _Hut.new()) as Building
			_place(hut, at, G)
			await pframes(10)
			var archers: Array = _squad("archer", at + Vector3(-18.0, 0, -2), 12, F, 4)
			if volley:
				for nid in ["archer_1a", "archer_1b", "archer_1c", "archer_1d"]:
					GameManager.finish_research(F, nid)
				GameManager.squad_set_volley_mode((archers[0] as Unit).squad_id, true) \
					if GameManager.has_method("squad_set_volley_mode") else null
			await pframes(5)
			for a in archers:
				(a as Unit).command_attack(hut, true)
			var hp0: float = hut.current_health
			var fired0: int = GameManager.arrows_fired
			await pframes(600)
			var refused := 0
			var st := {}
			for a in (_alive(archers) if is_instance_valid(hut) else []):
				refused += int(a.get("shots_refused_range"))
				var k: String = "%d/%s/%.1f" % [(a as Unit).state, str((a as Unit).attack_target == hut), (a as Node3D).global_position.distance_to(hut.global_position)]
				st[k] = int(st.get(k, 0)) + 1
			print("    выпущено %d, отказ по дальности %d, лучники %s" % [GameManager.arrows_fired - fired0, refused, str(st)])
			var hp1: float = hut.current_health if is_instance_valid(hut) else 0.0
			var fired: int = GameManager.arrows_fired
			print("  %s, %s: запас %.0f → %.0f" % ["главная хата" if chief else "хижина",
				"залп" if volley else "по готовности", hp0, hp1])
			verdict("C%d стрелы снимают запас: %s, %s" % [i, "хата" if chief else "хижина",
				"залп" if volley else "по готовности"], hp1 < hp0 - 50.0,
				"%.0f → %.0f" % [hp0, hp1])
			_free(archers)
			if is_instance_valid(hut):
				hut.queue_free()
			await pframes(5)

# ─────────────────────────────────────────────────────────────────────────────
# D. ЗНАМЁНА: ТОЛЬКО ТРЕУГОЛЬНЫЕ ВЫМПЕЛЫ
# ─────────────────────────────────────────────────────────────────────────────
func _gold_px(tex: Texture2D) -> int:
	if tex == null:
		return -1
	var img: Image = tex.get_image()
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			# Золото шкалы (BANNER_GOLD 0.93/0.76/0.24) и любые жёлтые
			if c.a > 0.5 and c.r > 0.75 and c.g > 0.55 and c.b < 0.45:
				n += 1
	return n

func _d_banners() -> void:
	print("
═════ D. ЗНАМЁНА: ВЫМПЕЛЫ, У ЛЕГЕНДЫ — ЗОЛОТО ═════")
	var UC = load("res://scripts/unit_stats_config.gd")
	var BA = load("res://scripts/BannerArt.gd")
	# РАЗВОРОТ ТЗ 25.10.2026 (блок 3): легендарный ранг (последняя ступень) —
	# ЗОЛОТОЙ квадратный штандарт. Правило 21.10 «без жёлтого, только
	# вымпелы» держится для всех ступеней НИЖЕ легенды
	var top: int = UC.VET_BANNER_TIERS.size()
	var shapes_ok := true
	for i in range(top - 1):
		if int((UC.VET_BANNER_TIERS[i] as Dictionary).get("shape", -1)) != UC.BANNER_PENNANT:
			shapes_ok = false
	verdict("D1 все ступени ниже легенды — треугольные вымпелы", shapes_ok)
	var gold := 0
	for lvl in range(1, top):
		gold += maxi(_gold_px(BA.texture_for(lvl)), 0)
		# vexillum_texture рисует ЗНАМЯ ЛЕГЕНДЫ (ступень top) при любом
		# аргументе — с 25.10 оно золотое, проверяется в D3
	verdict("D2 ни на одном знамени ниже легенды нет жёлтого", gold == 0,
		"жёлтых пикселей %d" % gold)
	var leg: Dictionary = UC.veteran_banner_tier(top)
	var c: Color = leg.get("cloth", Color.BLACK)
	verdict("D3 знамя легендарных — золотое (разворот ТЗ 25.10)", c.r > 0.8 and c.g > 0.6 and c.b < 0.35, str(c))
	verdict("D4 знамя элиты отличается от общего (свой ключ, × ELITE_SCALE)",
		BA.vexillum_texture(7) != BA.texture_for(7))

# ─────────────────────────────────────────────────────────────────────────────
# E. СМЕШАННЫЙ СТРОЙ ГЛУБОКОЙ ПРОТЯЖКОЙ
# ─────────────────────────────────────────────────────────────────────────────
## Протяжка смешанного выделения: 3 отряда копейщиков по 60 + лучники 24 +
## мечники 12. Возвращает ширину фронта копейщиков, шеренги по отрядам,
## шеренги и смещение центра тыловых
func _mixed_case(at: Vector3, line: float) -> Dictionary:
	_clear(at, 60.0)
	await pframes(3)
	var men: Array = []
	var spear_sids: Array = []
	for q in range(3):
		var sq: Array = _squad("spearman", at + Vector3(float(q) * 7.0 - 7.0, 0, 0), 60, F, 10)
		spear_sids.append((sq[0] as Unit).squad_id)
		men.append_array(sq)
	var arch: Array = _squad("archer", at + Vector3(0, 0, -8), 24, F, 8)
	var war: Array = _squad("warrior", at + Vector3(8, 0, -8), 12, F, 6)
	men.append_array(arch)
	men.append_array(war)
	await pframes(10)
	var sm = main.selection_manager
	sm.select_units(men)
	sm.formation_mode = sm.FORM_WIDE
	var a := at + Vector3(-line * 0.5, 0, 12)
	var b := at + Vector3(line * 0.5, 0, 12)
	sm._execute_line_formation(a, b)
	sm.clear_selection()
	var dir := (b - a).normalized()
	var mid := (a + b) * 0.5
	var lat_min := INF
	var lat_max := -INF
	var rows_by: Dictionary = {}
	for m in men:
		var u := m as Unit
		var l: float = (u.post_pos - a).dot(dir)
		if u.stat_id == "spearman":
			lat_min = minf(lat_min, l)
			lat_max = maxf(lat_max, l)
		var k: int = u.squad_id
		rows_by[k] = maxi(int(rows_by.get(k, 0)), u.formation_row + 1)
	var spear_rows: Array = []
	for sid in spear_sids:
		spear_rows.append(int(rows_by.get(sid, 0)))
	var off := func(list: Array) -> float:
		var cc := Vector3.ZERO
		for m2 in list:
			cc += (m2 as Unit).post_pos
		cc /= float(list.size())
		return absf((cc - mid).dot(dir))
	var res := {"front": lat_max - lat_min, "spear_rows": spear_rows,
		"arch_rows": int(rows_by.get((arch[0] as Unit).squad_id, 0)),
		"war_rows": int(rows_by.get((war[0] as Unit).squad_id, 0)),
		"arch_off": off.call(arch), "war_off": off.call(war)}
	_free(men)
	await pframes(5)
	return res

func _e_mixed_formation() -> void:
	print("
═════ E. СМЕШАННЫЙ СТРОЙ ПРОТЯЖКОЙ ═════")
	for case in [[12.0, "короткая (глубокая) 12 м"], [40.0, "длинная 40 м"]]:
		var line: float = float(case[0])
		var r: Dictionary = await _mixed_case(Vector3(-40, 0, -20 if line < 20.0 else 40), line)
		print("  %s: фронт копейщиков %.1f м, шеренги отрядов %s, лучники %d шер. (центр %.1f м), мечники %d шер. (центр %.1f м)" % [
			case[1], r.front, str(r.spear_rows), r.arch_rows, r.arch_off, r.war_rows, r.war_off])
		var tag: String = "E%s" % ("1" if line < 20.0 else "2")
		verdict("%sа %s: фронт первой линии ≥ 90 %% протяжки" % [tag, case[1]],
			float(r.front) >= line * 0.9 - 0.6, "%.1f из %.1f" % [r.front, line])
		var rs: Array = r.spear_rows
		verdict("%sб %s: отряды пехоты одной глубины" % [tag, case[1]],
			int(rs.max()) - int(rs.min()) <= 0, str(rs))
		verdict("%sв %s: лучники — 2-3 шеренги по центру" % [tag, case[1]],
			int(r.arch_rows) >= 2 and int(r.arch_rows) <= 3 and float(r.arch_off) < 2.0,
			"%d шер., центр %.1f" % [r.arch_rows, r.arch_off])
		verdict("%sг %s: мечники — 2-3 шеренги по центру" % [tag, case[1]],
			int(r.war_rows) >= 2 and int(r.war_rows) <= 3 and float(r.war_off) < 2.0,
			"%d шер., центр %.1f" % [r.war_rows, r.war_off])

# ─────────────────────────────────────────────────────────────────────────────
# F. КУРСОР-ТОПОР
# ─────────────────────────────────────────────────────────────────────────────
func _f_axe() -> void:
	print("
═════ F. КУРСОР-ТОПОР: ЛЕЗВИЕ ВНИЗ ═════")
	var CA = load("res://scripts/CursorArt.gd")
	var tex: ImageTexture = CA.texture(CA.AXE)
	verdict("F0 рисунок топора есть", tex != null)
	if tex == null:
		return
	var img: Image = tex.get_image()
	var head: Vector2 = CA.AXE_HEAD
	var below := 0
	var above := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			# Металл: светлый серо-голубой (дерево рукояти — тёплое)
			if c.a > 0.5 and c.b > 0.45 and c.b >= c.r:
				if float(y) > head.y + 1.0:
					below += 1
				elif float(y) < head.y - 1.0:
					above += 1
	verdict("F1 металла головки ниже проуха больше, чем выше (лезвие вниз)",
		below > above * 2, "ниже %d, выше %d" % [below, above])
	var hs: Vector2 = CA.hotspot(CA.AXE)
	verdict("F2 горячая точка — ниже проуха, у кромки", hs.y > head.y and hs.x < head.x, str(hs))
	var hit := false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var px := int(hs.x) + dx
			var py := int(hs.y) + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height() 					and img.get_pixel(px, py).a > 0.5:
				hit = true
	verdict("F3 горячая точка лежит на рисунке лезвия", hit)
