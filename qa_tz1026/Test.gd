extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_TZ1026 — ТЗ 26.10.2026 (знамёна, плотность, окружение тролля, курсор,
## массовое лечение монаха). Headless.
## ═══════════════════════════════════════════════════════════════════════════
## Числа — из конфигов (правило 10), время — физкадрами (правило 11).
## Ручки: diag=1 — подробная печать; block=X — только блок X.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const GF := Constants.FACTION_GOBLIN

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _diag := false
var _only := ""
var _live_troll := true
var _c_squads := 1
var _c_kind := "big_goblin"
var _e_research: Array = []
var _last_pos: Dictionary = {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "diag=1":
			_diag = true
		elif a.begins_with("csq="):
			_c_squads = int(a.substr(4))
		elif a.begins_with("res="):
			_e_research = Array(a.substr(4).split(","))
		elif a.begins_with("ckind="):
			_c_kind = a.substr(6)
		elif a == "live=0":
			_live_troll = false
		elif a.begins_with("block="):
			_only = a.substr(6)
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 900 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_tz1026: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _want(b: String) -> bool:
	return _only == "" or _only.find(b) >= 0

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Отряд блоком cols × rows, лицом по FORWARD (−Z), разметка закреплена
func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6, sp: float = 0.6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(
			at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0,
			at.z + float(i / cols) * sp))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	for u in men:
		(u as Unit).command_move((u as Unit).global_position, false, Vector3.FORWARD)
	GameManager.squad_close_ranks(sid, true)
	return [sid, men]

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _kill_all(men: Array) -> void:
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

## Вычистить всех чужих и диких в радиусе (ловушка «стенд на случайной карте»)
func _clear_area(c: Vector3, r: float) -> void:
	for u in GameManager._live_units.duplicate():
		if not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu == null or uu.is_dead():
			continue
		if uu.global_position.distance_to(c) < r:
			uu.take_damage(1e12)

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 30.0), Vector3(0.0, 0.0, -30.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
				if GameManager.is_water(p.x + d.x, p.z + d.z):
					h += 100.0
				if not GameManager.is_passable(p.x + d.x, p.z + d.z):
					h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	main = get_tree().current_scene
	if main == null or not main.has_method("world_add"):
		var sc: PackedScene = load("res://scenes/Main.tscn")
		main = sc.instantiate()
		get_tree().root.add_child(main)
	await frames(30)
	_Opt.squad_probes = false
	var base: Vector3 = _flat_spot(Vector3(0.0, 0.0, 40.0))
	_clear_area(base, 70.0)
	await pframes(10)
	if _want("A"):
		await _a_banner(base)
	if _want("B"):
		await _b_density(base)
	if _want("C"):
		await _c_troll_ring(base)
	if _want("D"):
		await _d_cursor()
	if _want("E"):
		await _e_monk(base)
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# E. МОНАХ: МАССОВОЕ ЛЕЧЕНИЕ БЕЗ ИССЛЕДОВАНИЯ И ЕГО ТЕМП
# ═════════════════════════════════════════════════════════════════════════════
func _squad_hp(men: Array) -> Array:
	var hp := 0.0
	var mx := 0.0
	var full := 0
	for u in _alive(men):
		var uu := u as Unit
		hp += uu.current_health
		mx += uu.max_health
		if uu.current_health >= uu.max_health - 0.01:
			full += 1
	return [hp / maxf(mx, 1.0), full]

func _e_monk(base: Vector3) -> void:
	print("
═════ E. МОНАХ: ЛЕЧЕНИЕ ОТРЯДА ИЗ 50 ═════")
	var r0: Array = await _e_case(base, [])
	verdict("E1 без исследований монах лечит одного за такт", int(r0[1]) == 1,
		"целей за такт %d" % int(r0[1]))
	var r1: Array = await _e_case(base, ["1d", "2d"])
	verdict("E2 «Первое Чудо» (2d, воскрешение) лечения всего отряда не даёт",
		int(r1[1]) <= 3 and not bool(r1[2]), "целей за такт %d, aoe %s" % [int(r1[1]), r1[2]])
	var r2: Array = await _e_case(base, ["1b", "2b", "3b", "4b", "5b", "1d", "2d", "3d"])
	verdict("E3 вся ветка лечения: отряд с 30 % до полного не быстрее 15 с",
		float(r2[0]) >= 15.0, "полностью за %.1f с" % float(r2[0]))
	verdict("E4 и всё же лечит: к 30 с отряд целиком здоров",
		float(r2[0]) > 0.0 and float(r2[0]) <= 30.0, "полностью за %.1f с" % float(r2[0]))

## [секунд до полного (−1 — не успел за 30 с), целей за такт, aoe_active]
func _e_case(base: Vector3, research: Array) -> Array:
	GameManager.reset_research()
	for cell in research:
		GameManager.finish_research(F, "monk_" + String(cell))
	var sq: Array = _squad("spearman", F, base + Vector3(0.0, 0.0, -6.0), 50, 10, 0.6)
	var men: Array = sq[1]
	var msq: Array = _squad("monk", F, base + Vector3(0.0, 0.0, 2.0), 1, 1, 0.6)
	var monk: Unit = msq[1][0]
	await pframes(20)
	for u in men:
		var uu := u as Unit
		uu.current_health = uu.max_health * 0.3
		uu._soa_push_stats()
	var cap: int = int(monk.call("max_heal_targets"))
	var aoe: bool = bool(monk.call("aoe_active"))
	# Двойной ПКМ по своему отряду: дважды через путь SelectionManager
	var sm = main.selection_manager
	sm.select_units([monk])
	sm._try_monk_heal_order(men[0])
	await pframes(6)
	sm._try_monk_heal_order(men[0])
	var h0: Array = _squad_hp(men)
	var t_full := -1.0
	for k in range(60):
		await pframes(30)
		var h: Array = _squad_hp(men)
		var t: float = float(k + 1) * 0.5
		if _diag and k % 4 == 3:
			print("  t=%.1f с: запас отряда %.0f %%, целых %d" % [t, float(h[0]) * 100.0, int(h[1])])
		if int(h[1]) >= _alive(men).size():
			t_full = t
			break
	print("  изучено %s: целей за такт %d, aoe %s, старт %.0f %%, полностью за %s" % [
		research, cap, aoe, float(h0[0]) * 100.0, ("%.1f с" % t_full) if t_full > 0 else "> 30 с"])
	sm.select_units([])
	_kill_all(men)
	_kill_all(msq[1])
	await pframes(4)
	return [t_full, cap, aoe]

# ═════════════════════════════════════════════════════════════════════════════
# C. ОТРЯД РЫЦАРЕЙ НА КРУПНУЮ ЦЕЛЬ: ОПОЯСЫВАНИЕ
# ═════════════════════════════════════════════════════════════════════════════
## Туша жива и бьёт (отброшенные ударом на секунды выбывают), но с места не
## сходит (ловушка «дикий без логова уходит к логову партии»). Ручки:
## ckind= (big_goblin/troll), live=0 — неподвижная, csq=N — отрядов по 30
func _c_troll_ring(base: Vector3) -> void:
	print("\n═════ C. РЫЦАРИ НА КРУПНУЮ ЦЕЛЬ (%s) ═════" % _c_kind)
	var troll: Unit = _spawn(_c_kind, GF, base + Vector3(0.0, 0.0, -14.0))
	troll.max_health = 1e9
	troll.current_health = 1e9
	if not _live_troll:
		troll.set_tick(false)
	var men: Array = []
	for qi in range(_c_squads):
		var sq: Array = _squad("warrior", F, base + Vector3(float(qi - (_c_squads - 1) * 0.5) * 6.0, 0.0, 0.0), 30, 6, 0.6)
		men += sq[1]
	await pframes(20)
	for u in men:
		(u as Unit).command_attack(troll, true, true, true)
	var best := 0
	var last := 0
	var hp0: float = troll.current_health
	var pin: Vector3 = troll.global_position
	for k in range(15):
		for _f in range(60):
			await get_tree().physics_frame
			if _live_troll and is_instance_valid(troll):
				troll.global_position = pin
				troll.sync_row()
		var inr := 0
		for u in _alive(men):
			if (u as Unit).target_in_range():
				inr += 1
		best = maxi(best, inr)
		last = inr
		if _diag:
			print("  t=%d с: в досягаемости %d из %d, урон %.0f" % [k + 1, inr,
				_alive(men).size(), hp0 - troll.current_health])
	var dmg: float = hp0 - troll.current_health
	# Сектора по 45° вокруг цели, где стоит хоть один дотянувшийся
	var sect: Dictionary = {}
	for u in _alive(men):
		var uu := u as Unit
		if not uu.target_in_range():
			continue
		var dv: Vector3 = uu.global_position - troll.global_position
		sect[int(floor((atan2(dv.z, dv.x) + PI) / (PI / 4.0))) % 8] = true
	print("  итог: в досягаемости %d (пик %d), урон %.0f, секторов %d/8, R цели %.2f, reach %.2f" % [
		last, best, dmg, sect.size(), troll.sep_radius(), (men[0] as Unit).reach()])
	# СВОЙСТВО, А НЕ РАЗНИЦА С ПРЕЖНИМ КОДОМ: без мест на кольце отряд в этой
	# синтетике тоже держит полукольцо (замер 26.10, по 3 прогона: 24.3 против
	# 25.7 в досягаемости, 4 сектора у обоих) — стенд стережёт, что пол
	# сближения своих (ally_floor) не отгоняет рыцарей от туши (с полом и без
	# поблажки по цели-гиганту было 11 из 30)
	verdict("C1 крупную цель бьют: в досягаемости ≥ 20 из 30 под её ударами",
		last >= 20, "%d из %d" % [last, _alive(men).size()])
	verdict("C2 полукольцо: дотянувшиеся стоят не меньше чем в 4 секторах из 8",
		sect.size() >= 4, "%d из 8" % sect.size())
	_kill_all(men)
	troll.take_damage(1e12)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# A. РЕЛИКВИЯ СРАСТАЕТСЯ СО ЗНАМЕНЕМ, ДРЕВКО ЛЕГЕНДЫ ЗА ПОЛОТНИЩЕМ
# ═════════════════════════════════════════════════════════════════════════════
func _a_level(sid: int, lvl: int) -> void:
	var sq: Dictionary = GameManager.squads[sid]
	var cur: int = int(sq["level"])
	if lvl > cur:
		GameManager._grant_auto_veterancy(sid, cur, lvl)
	GameManager.refresh_squad_banner(sid)

func _a_banner(base: Vector3) -> void:
	print("\n═════ A. РЕЛИКВИЯ И ЗНАМЯ ОТРЯДА ═════")
	var rm = GameManager.relic_mgr()
	var sq: Array = _squad("spearman", F, base + Vector3(-10.0, 0.0, 0.0), 12, 6, 0.6)
	var sid: int = sq[0]
	var men: Array = sq[1]
	_a_level(sid, 2)
	await pframes(4)
	var banner = GameManager.squads[sid].get("banner")
	verdict("A0 у ветерана висит вымпел", banner != null and is_instance_valid(banner)
		and not bool(banner.shown_elite), "")
	# Реликвия павшего носителя лежит у ног бойца — подбор первым наступившим
	var r: Dictionary = rm.place_on_ground(2, (men[3] as Unit).global_position)
	var picked := false
	for _i in range(60):
		await get_tree().physics_frame
		var c = r["carrier"]
		if typeof(c) == TYPE_OBJECT and is_instance_valid(c) and (c as Unit).squad_id == sid:
			picked = true
			break
	await frames(3)
	banner = GameManager.squads[sid].get("banner")
	var node = r["node"]
	verdict("A1 боец отряда подобрал реликвию", picked, "")
	var a2: bool = banner != null and bool(banner.shown_elite) and int(banner.shown_elite_lvl) == 2
	verdict("A2 знамя отряда стало штандартом с уровнем реликвии (лычки на полотнище)", a2,
		("elite=%s lvl=%d" % [banner.shown_elite, int(banner.shown_elite_lvl)]) if banner != null else "знамени нет")
	verdict("A3 второго флагштока нет: узел реликвии не рисуется",
		node == null or not is_instance_valid(node) or not node.visible, "")
	# Легенда с реликвией: золотой флаг с бордовым мини-флажком
	var carrier: Unit = r["carrier"] if picked else null
	_a_level(sid, _UCfg.max_veteran_level("spearman"))
	await frames(3)
	banner = GameManager.squads[sid].get("banner")
	verdict("A4 легенда с реликвией: один флагшток, мини-флажок штандарта на золотом",
		banner != null and bool(banner.shown_elite) and (node == null or not node.visible), "")
	# Носитель пал — реликвию подбирает сосед: флагшток по-прежнему один
	if carrier != null:
		carrier.take_damage(1e12)
	for _i in range(40):
		await get_tree().physics_frame
	await frames(3)
	banner = GameManager.squads[sid].get("banner")
	node = r["node"]
	var c2 = r["carrier"]
	var mate: bool = typeof(c2) == TYPE_OBJECT and is_instance_valid(c2) and (c2 as Unit).squad_id == sid
	verdict("A5 носитель пал — реликвию поднял сосед, флагшток всё ещё один",
		mate and banner != null and bool(banner.shown_elite)
		and (node == null or not is_instance_valid(node) or not node.visible), "сосед: %s" % mate)
	# Реликвия ушла из отряда (унесли далеко) — знамя снова без штандарта
	rm._drop(r)
	r["pos"] = base + Vector3(60.0, 0.0, 60.0)
	await frames(3)
	banner = GameManager.squads[sid].get("banner")
	verdict("A5b реликвия ушла из отряда — знамя снова без штандарта",
		banner != null and is_instance_valid(banner) and not bool(banner.shown_elite), "")
	# Древко легенды — ЗА полотнищем: на строках полотнища столбец тени древка
	# закрыт каймой (до правки — серая тень древка поверх флага)
	var BA = load("res://scripts/BannerArt.gd")
	BA.clear_cache()
	var img: Image = BA.legend_texture(0).get_image()
	var col: int = BA.POLE_X + BA.POLE_W - 1
	var over := 0
	for y in range(BA.STD_TOP + 3, BA.STD_TOP + BA.STD_H - 3):
		if img.get_pixel(col, y).is_equal_approx(BA.POLE_SHADE):
			over += 1
	verdict("A6 древко легендарного флага за полотнищем", over == 0,
		"строк с древком поверх ткани: %d" % over)
	_kill_all(men)
	for rr in rm.relics.duplicate():
		var nd = (rr as Dictionary)["node"]
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	rm.relics.clear()
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# B. ПЛОТНОСТЬ: ЗАДНИЕ РЯДЫ НЕ ПРОВАЛИВАЮТСЯ СКВОЗЬ ПЕРЕДНИХ
# ═════════════════════════════════════════════════════════════════════════════
## Два отряда мечников по 30 давят на неподвижную стену врага (неуязвимую):
## считаем пары союзников ближе 0.9 · 4r/3 (круги зашли друг в друга заметно
## больше чем на треть)
func _b_density(base: Vector3) -> void:
	print("\n═════ B. ПЛОТНОСТЬ В СВАЛКЕ ═════")
	var wall: Array = _squad("spearman", E, base + Vector3(0.0, 0.0, -12.0), 36, 12, 0.6)
	var foes: Array = wall[1]
	for u in foes:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
		(u as Unit)._soa_push_stats()
		(u as Unit).set_tick(false)
	var mine: Array = []
	for qi in range(2):
		var sq: Array = _squad("warrior", F, base + Vector3(float(qi) * 4.0 - 2.0, 0.0, 0.0), 30, 6, 0.6)
		mine += sq[1]
	await pframes(20)
	for i in range(mine.size()):
		(mine[i] as Unit).command_attack(foes[i % foes.size()], true, true, true)
	var floor_d: float = Unit.PERSONAL_RADIUS * 4.0 / 3.0
	var worst := 0
	var sum := 0
	var n := 0
	for k in range(12):
		await pframes(60)
		if k < 4:
			continue
		var al: Array = _alive(mine)
		var pairs := 0
		for i in range(al.size()):
			var pa: Vector3 = (al[i] as Unit).global_position
			for j in range(i + 1, al.size()):
				var pb: Vector3 = (al[j] as Unit).global_position
				if Vector2(pa.x - pb.x, pa.z - pb.z).length() < floor_d * 0.9:
					pairs += 1
		worst = maxi(worst, pairs)
		sum += pairs
		n += 1
		if _diag:
			print("  t=%d с: пар теснее 0.9·4r/3: %d" % [k + 1, pairs])
	var avg: float = float(sum) / maxf(float(n), 1.0)
	print("  пар теснее %.2f м: в среднем %.1f, пик %d (из %d бойцов), срезано шагов полом: %d" % [
		floor_d * 0.9, avg, worst, _alive(mine).size(), GameManager.army.ally_floor_blocked()])
	verdict("B1 союзники в свалке не сминаются: пар теснее 0.9·4r/3 в среднем ≤ 3",
		avg <= 3.0, "в среднем %.1f, пик %d" % [avg, worst])
	_kill_all(mine)
	_kill_all(foes)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. КУРСОР НАД ИНТЕРФЕЙСОМ
# ═════════════════════════════════════════════════════════════════════════════
func _hud_control() -> Control:
	var best: Control = null
	var stack: Array = [main.hud]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for ch in nd.get_children():
			stack.append(ch)
		var c := nd as Control
		if c == null or not c.is_visible_in_tree() or c.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size.x < 60.0 or r.size.y < 40.0:
			continue
		if best == null or r.get_area() > best.get_global_rect().get_area():
			best = c
	return best

func _hover(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	get_tree().root.push_input(e, true)
	await frames(2)

func _d_cursor() -> void:
	print("\n═════ D. КУРСОР НАД ИНТЕРФЕЙСОМ ═════")
	var ctl: Control = _hud_control()
	if ctl == null:
		verdict("D0 нашлась панель интерфейса под мышь", false, "")
		return
	var ui_pt: Vector2 = ctl.get_global_rect().get_center()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var field_pt := Vector2(vp.x * 0.5, vp.y * 0.4)
	await _hover(field_pt)
	var field_free: bool = get_viewport().gui_get_hovered_control() == null
	var sm = main.selection_manager
	var CA = load("res://scripts/CursorArt.gd")
	# Режим [A]: мечи над полем, палец над интерфейсом
	sm._apply_attack_cursor(true)
	await _hover(ui_pt)
	main._cursor_timer = 0.0
	main._update_hover_cursor(1.0)
	var d1: bool = bool(main._ui_finger)
	await _hover(field_pt)
	main._cursor_timer = 0.0
	main._update_hover_cursor(1.0)
	var d2: bool = not bool(main._ui_finger) and field_free
	sm._apply_attack_cursor(false)
	verdict("D1 [A]: над интерфейсом — палец вместо мечей", d1, "панель %s" % ctl.name)
	verdict("D2 [A]: над полем — снова мечи", d2, "поле свободно от интерфейса: %s" % field_free)
	# Обычный вид: над интерфейсом — перчатка-указатель (HAND)
	await _hover(ui_pt)
	main._cursor_timer = 0.0
	main._update_hover_cursor(1.0)
	verdict("D3 над интерфейсом курсор — перчатка-указатель", int(main._cursor_kind) == int(CA.HAND),
		"вид %d" % int(main._cursor_kind))
