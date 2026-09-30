extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТЗ 29.09.2026, ТРЕТЬЕ ПИСЬМО (блоки 1-3)
## ═══════════════════════════════════════════════════════════════════════════
##   A — БЕГ: новобранец из здания, выход из замка, поход в замок (со сбросом
##       приёмов, и из «Защиты»), паника — бегом; лечение в замке на 30 % быстрее.
##   B — ДВОЙНОЙ КЛИК: один пульсар (второй клик не перезапускает вспышку, а
##       красит её в цвет бега) и один изменённый щелчок вместо второго.
##   C — КУРСОР-ПАЛЕЦ И ЗАГОН: лучники над своей башней, рабочие над загоном
##       (ограда, овца загона, земля внутри); ПКМ по земле загона ставит
##       рабочих на загон, а не в центр.
##   D — ВЫЗВОЛЕНИЕ: боец, упёршийся в лес-стену без продвижения, сбрасывает
##       путь и цель и бегом возвращается к отряду.
##   E — СТЕНЫ БАЗ: у красного и у орды полосы леса с двумя проходами;
##       маршрут от базы красного к базе игрока и от деревни к броду есть.
##   F — РУДНИКИ: центральных нет; два ничейных на территориях игрока и
##       красного, у каждого охрана орды, патрулирующая СВОЙ рудник.
##   G — ТАРАН ПО МЕЧНИКАМ: первый ряд затоптан без отлёта, второй отлетает на
##       2.5-3.5 м, третий теснится; задние всадники с разгона не бьют.
## Запуск: godot --headless --path . res://qa_tz0929c/Test.tscn [-- only=abcde]

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _CSiteT := preload("res://scripts/ConstructionSite.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var only: String = "abcdefg"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz0929c: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int = 5, gap: float = 0.7) -> Array:
	var sid: int = GameManager.new_squad(f, uid)
	var out: Array = []
	for i in range(n):
		var u := _unit(uid, f, at + Vector3(float(i % cols) * gap, 0.0, float(i / cols) * gap))
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return [sid, out]

func _kill(arr: Array) -> void:
	for u in arr:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e12)

func _spot() -> Vector3:
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	return Vector3(a.x + 30.0, 0.0, a.z + 24.0)

func _place(b: Building, at: Vector3) -> void:
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for w in get_tree().get_nodes_in_group("all_units"):
		if w is Unit and (w as Unit).faction != Constants.FACTION_PLAYER:
			(w as Unit).set_tick(false)
	await pframes(4)
	if "a" in only: await _block_run()
	if "b" in only: await _block_double()
	if "c" in only: await _block_cursor()
	if "d" in only: await _block_unstick()
	if "e" in only: _block_walls()
	if "f" in only: await _block_mines()
	if "g" in only: await _block_charge_rows()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. БЕГ
# ═════════════════════════════════════════════════════════════════════════════
func _block_run() -> void:
	print("\n═════ A. БЕГ ИЗ ЗДАНИЙ, В ЗАМОК И В ПАНИКЕ ═════")
	var at: Vector3 = _spot()
	main._clear_area_of_resources(at, 40.0)
	var bar: Building = _CSiteT.make_building("barracks")
	_place(bar, at)
	await pframes(4)
	var u := _unit("spearman", Constants.FACTION_PLAYER, bar._gate_position())
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var rally: Vector3 = at + Vector3(0.0, 0.0, 22.0)
	bar._place_spawned(u, bar._gate_position(), rally, sid, Vector3.BACK)
	await pframes(3)
	verdict("A1 новобранец бежит на точку сбора", u.sprinting and u.state == Unit.State.MOVING,
		"бег %s, состояние %d" % [str(u.sprinting), int(u.state)])
	_kill([u])
	# Замок: поход бегом, из «Защиты», приёмы сброшены
	var kp: Vector3 = at + Vector3(40.0, 0.0, 0.0)
	main._clear_area_of_resources(kp, 30.0)
	var keep: Castle = Castle.new()
	_place(keep, kp)
	await pframes(4)
	# Полный штат: неполный лазарет доукомплектовывает по бойцу раз в 3.5 с
	var sq: Array = _squad("spearman", Constants.FACTION_PLAYER, kp + Vector3(0.0, 0.0, 26.0), _UCfgT.squad_size("spearman"), 6)
	for m in sq[1]:
		(m as Unit).set_stance("defense")
		(m as Unit)._charge_order = true
	# Раненые — иначе полный здоровый отряд выходит в тот же такт, что вошёл
	for m in sq[1]:
		(m as Unit).current_health = (m as Unit).max_health - 2.0
	await pframes(2)
	var ok: bool = keep.request_garrison(int(sq[0]))
	await pframes(2)
	# Бег в замок включается ПОСЛЕ выхода из зоны билета отхода (2.5 м от
	# точки начала): сразу после заявки боец идёт шагом, но бег ему обещан
	var promised := 0
	var charged := 0
	for m in sq[1]:
		if (m as Unit).sprinting or (m as Unit)._sprint_after_pass:
			promised += 1
		if (m as Unit)._charge_order:
			charged += 1
	var wr := 0
	var runners := 0
	while wr < 60 * 6:
		await get_tree().physics_frame
		wr += 1
		runners = 0
		for m in sq[1]:
			if is_instance_valid(m) and (m as Unit).sprinting:
				runners += 1
		if runners >= (sq[1] as Array).size() / 2:
			break
	verdict("A2 в замок — бегом и из «Защиты», приёмы сброшены (бег обещан %d из %d, бегут %d через %.1f с, с натиском %d)" % [promised, (sq[1] as Array).size(), runners, float(wr) / 60.0, charged],
		ok and promised == (sq[1] as Array).size() and runners >= (sq[1] as Array).size() / 2 and charged == 0)
	var w := 0
	while w < 60 * 25 and keep._slot_of(int(sq[0])) < 0:
		await get_tree().physics_frame
		w += 1
	var gin := 0
	for m in sq[1]:
		if (m as Unit).garrisoned:
			gin += 1
	print("    A: в гарнизоне запись %d, внутри %d из %d за %.1f с" % [keep._slot_of(int(sq[0])), gin, (sq[1] as Array).size(), float(w) / 60.0])
	# Раненые (до заявки) лечатся и выходят сами — бегом
	w = 0
	var out_run := -1
	while w < 60 * 20:
		await get_tree().physics_frame
		w += 1
		if keep._slot_of(int(sq[0])) < 0:
			out_run = 0
			for m in sq[1]:
				if is_instance_valid(m) and (m as Unit).sprinting:
					out_run += 1
			break
	verdict("A3 из замка — бегом на точку сбора (бегут %d)" % out_run, out_run > 0)
	verdict("A4 лечение в замке на 30 %% быстрее (%.2f HP/с, доукомплектование %.1f с)" % [_UCfgT.GARRISON_HEAL_PER_SEC, _UCfgT.GARRISON_REVIVE_SECONDS],
		absf(_UCfgT.GARRISON_HEAL_PER_SEC - 1.0 / 0.7) < 0.01 and absf(_UCfgT.GARRISON_REVIVE_SECONDS - 3.5) < 0.01)
	_kill(sq[1])
	# Паника из «Защиты» — бегом
	var ps: Array = _squad("spearman", Constants.FACTION_PLAYER, at + Vector3(-20.0, 0.0, 10.0), 6)
	for m in ps[1]:
		(m as Unit).set_stance("defense")
	await pframes(2)
	var pm := (ps[1] as Array)[0] as Unit
	pm.panic_flee(pm.global_position + Vector3(0.0, 0.0, 20.0))
	await pframes(2)
	verdict("A5 паника в «Защите» — бегом", pm.sprinting, "бег %s" % str(pm.sprinting))
	_kill(ps[1])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# B. ДВОЙНОЙ КЛИК
# ═════════════════════════════════════════════════════════════════════════════
func _block_double() -> void:
	print("\n═════ B. ДВОЙНОЙ КЛИК: ОДИН ПУЛЬСАР, ОДИН ЩЕЛЧОК ═════")
	var at: Vector3 = _spot() + Vector3(0.0, 0.0, 30.0)
	var sq: Array = _squad("spearman", Constants.FACTION_PLAYER, at, 10)
	var sm = main.selection_manager
	sm.selected_units = (sq[1] as Array).duplicate()
	var fp = sm._fp
	if fp == null:
		verdict("B0 превью формации есть", false)
		return
	var s0: int = int(fp.flash_starts)
	var r0: int = int(fp.run_flashes)
	var v0: int = int(AudioManager.ui_variant_calls)
	var c0: int = int(AudioManager.ui_calls)
	sm._issue_formation_move(at + Vector3(0.0, 0.0, 12.0), false)
	await frames(2)
	sm._issue_formation_move(at + Vector3(0.0, 0.0, 12.0), true)
	await frames(2)
	verdict("B1 пара кликов — ОДНА вспышка, второй клик красит её в цвет бега (стартов %d, в цвет бега %d)" % [int(fp.flash_starts) - s0, int(fp.run_flashes) - r0],
		int(fp.flash_starts) - s0 == 1 and int(fp.run_flashes) - r0 == 1)
	verdict("B2 второй клик — не второй обычный щелчок, а изменённый (обычных %d, изменённых %d)" % [int(AudioManager.ui_calls) - c0, int(AudioManager.ui_variant_calls) - v0],
		int(AudioManager.ui_calls) - c0 == 1 and int(AudioManager.ui_variant_calls) - v0 == 1)
	var run_n := 0
	for m in sq[1]:
		if (m as Unit).sprinting:
			run_n += 1
	verdict("B3 после двойного клика отряд бежит (%d из %d)" % [run_n, (sq[1] as Array).size()], run_n == (sq[1] as Array).size())
	sm.selected_units = []
	_kill(sq[1])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# C. КУРСОР-ПАЛЕЦ И ЗАГОН
# ═════════════════════════════════════════════════════════════════════════════
func _screen(p: Vector3) -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	return cam.unproject_position(p)

func _block_cursor() -> void:
	print("\n═════ C. КУРСОР-ПАЛЕЦ И КЛИК ПО ЗАГОНУ ═════")
	var at: Vector3 = _spot() + Vector3(10.0, 0.0, -8.0)
	main._clear_area_of_resources(at, 30.0)
	var pen: Building = _CSiteT.make_building("sheep_pen")
	pen.set("stock_on_ready", true)
	_place(pen, at)
	var tw: Building = _CSiteT.make_building("tower")
	_place(tw, at + Vector3(-16.0, 0.0, 0.0))
	await pframes(6)
	main.focus_camera_on(at)
	await frames(6)
	main.set_process(false)
	if main._camera != null:
		(main._camera as Node).set_process(false)
	await frames(2)
	var sm = main.selection_manager
	# Лучники над своей башней
	var ar: Array = _squad("archer", Constants.FACTION_PLAYER, at + Vector3(-10.0, 0.0, 12.0), 6)
	sm.selected_units = (ar[1] as Array).duplicate()
	var tw_top: Vector3 = tw.global_position + Vector3(0.0, 2.0, 0.0)
	var f_tower: bool = sm.finger_under_cursor(_screen(tw_top))
	var f_ground: bool = sm.finger_under_cursor(_screen(at + Vector3(0.0, 0.0, 14.0)))
	verdict("C1 лучники: «палец» над своей башней, но не над пустой землёй", f_tower and not f_ground,
		"башня %s, земля %s" % [str(f_tower), str(f_ground)])
	# Рабочие над загоном: ограда, земля внутри
	var workers: Array = []
	for i in range(3):
		var w := _unit("worker", Constants.FACTION_PLAYER, at + Vector3(-4.0 + float(i) * 1.2, 0.0, 14.0))
		GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "worker"), w)
		workers.append(w)
	await pframes(2)
	sm.selected_units = workers.duplicate()
	var inner: Vector3 = at + Vector3(pen.build_size.x * 0.25, 0.0, pen.build_size.z * 0.2)
	var f_inner: bool = sm.finger_under_cursor(_screen(inner))
	verdict("C2 рабочие: «палец» над землёй внутри загона", f_inner)
	# ПКМ по земле внутри загона — рабочие на загоне, а не марш в центр
	var pc0: int = int(sm.pen_clicks)
	sm._handle_right_click(_screen(inner))
	await pframes(3)
	var farming := 0
	for w2 in workers:
		if (w2 as Worker).farm_pen() == pen:
			farming += 1
	verdict("C3 ПКМ по земле загона ставит рабочих на загон (на загоне %d из %d, кликов «на загон» %d)" % [farming, workers.size(), int(sm.pen_clicks) - pc0],
		farming == workers.size() and int(sm.pen_clicks) - pc0 == 1)
	# ПКМ по овце загона — тоже загон, не кража
	var sheep: Node3D = null
	for s in get_tree().get_nodes_in_group("sheep"):
		if s.get("pen") == pen and not bool(s.get("dead")):
			sheep = s
			break
	if sheep != null:
		var pen_t = sm._own_pen_for(sheep, sheep.global_position)
		verdict("C4 клик по овце загона читается как клик по загону", pen_t == pen)
	else:
		verdict("C4 клик по овце загона читается как клик по загону", false, "овец нет")
	sm.selected_units = []
	_kill(ar[1])
	_kill(workers)
	main.set_process(true)
	if main._camera != null:
		(main._camera as Node).set_process(true)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. ВЫЗВОЛЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _block_unstick() -> void:
	print("\n═════ D. ВЫЗВОЛЕНИЕ ЗАСТРЯВШЕГО У ЛЕСА-СТЕНЫ ═════")
	# Точка у нижней стены игрока, цель — за стеной, прямо сквозь неё
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	var x: float = a.x - 20.0
	var zb: float = main._wall_bottom_z(x)
	var start := Vector3(x, 0.0, zb - main._wall_half(x) - 1.2)
	var sq: Array = _squad("spearman", Constants.FACTION_PLAYER, start + Vector3(0.0, 0.0, -6.0), 4, 2)
	await pframes(3)
	var u := _unit("spearman", Constants.FACTION_PLAYER, start)
	GameManager.add_to_squad(int(sq[0]), u)
	await pframes(2)
	var goal := Vector3(x, 0.0, zb + 12.0)
	# Прямой приказ без маршрута: сквозь полосу
	u.command_move(goal, false, Vector3.ZERO, false, true)
	print("    D: старт %s, цель приказа %s, move_target %s, маршрут %d, zb %.1f" % [str(u.global_position), str(goal), str(u.move_target), u._route.size(), zb])
	u._route = PackedVector3Array()
	u.move_target = goal
	var n0: int = u.unstuck_count
	var w := 0
	while w < 60 * 8 and u.unstuck_count == n0:
		await get_tree().physics_frame
		w += 1
		if u._route.size() > 0 and u.unstuck_count == n0:
			u._route = PackedVector3Array()
			u.move_target = goal
	var freed: bool = u.unstuck_count > n0
	if not freed:
		print("    D: state=%d pos=%s цель=%s streak=%d may=%s cliff_near=%s moved=%s" % [int(u.state), str(u.global_position), str(u.move_target), u._stuck_streak, str(u._may_unstick()), str(GameManager.is_cliff(u.global_position.x, u.global_position.z + 1.5)), str(u.moved_recently())])
	verdict("D1 упёршийся в лес-стену вызволен (за %.1f с)" % (float(w) / 60.0), freed)
	if freed:
		var c2: Vector2 = GameManager.squad_centre_xz(int(sq[0]))
		var toward: bool = Vector2(u.move_target.x - c2.x, u.move_target.z - c2.y).length() < 6.0
		verdict("D2 после вызволения — бегом к своему отряду", u.sprinting and toward,
			"бег %s, цель в %.1f м от центра отряда" % [str(u.sprinting), Vector2(u.move_target.x - c2.x, u.move_target.z - c2.y).length()])
	_kill(sq[1])
	_kill([u])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# E. СТЕНЫ БАЗ
# ═════════════════════════════════════════════════════════════════════════════
func _block_walls() -> void:
	print("\n═════ E. ЛЕС-СТЕНЫ У БАЗ КРАСНОГО И ОРДЫ ═════")
	var specs: Array = main._wall_specs()
	verdict("E1 стены у красного и у орды посажены (%d деревьев, баз %d)" % [int(main.base_wall_trees), specs.size()],
		int(main.base_wall_trees) > 300 and specs.size() >= 1)
	var r1: PackedVector3Array = GameManager.nav_route(main.ENEMY_BASE_ANCHOR + Vector3(6.0, 0.0, -6.0), main.PLAYER_BASE_ANCHOR + Vector3(6.0, 0.0, 6.0), 1.5)
	verdict("E2 от базы красного к базе игрока дорога есть (%d точек)" % r1.size(), r1.size() > 0)
	if specs.size() >= 2:
		var vc: Vector3 = main.goblin_village_center()
		var r2: PackedVector3Array = GameManager.nav_route(vc + Vector3(-20.0, 0.0, 6.0), main.ford_point() + Vector3(30.0, 0.0, 0.0), 1.5)
		verdict("E3 от деревни орды к броду дорога есть (%d точек)" % r2.size(), r2.size() > 0)
	# Проходы чистые: точки в середине проходов — не в полосе
	var sp: Dictionary = specs[0]
	var a: Vector3 = sp["a"]
	var gz: float = a.z + float(sp["sz"]) * main.WALL_GAP_RIGHT_AT
	var gx: float = main._wall_x_of(sp, gz)
	var hx: float = a.x + float(sp["sx"]) * main.WALL_GAP_DOWN_AT
	var hz: float = main._wall_z_of(sp, hx)
	# Тело стены — в маске непроходимости (лес-стена = скала для шага и A*)
	var wz: float = a.z + float(sp["sz"]) * 30.0
	var wx: float = main._wall_x_of(sp, wz)
	var px: float = main.PLAYER_BASE_ANCHOR.x
	var pwz: float = main._wall_bottom_z(px - 30.0)
	verdict("E5 стена красного непроходима, как стена игрока (красный %s в (%.0f,%.0f), игрок %s)" % [str(GameManager.is_cliff(wx, wz)), wx, wz, str(GameManager.is_cliff(px - 30.0, pwz))],
		GameManager.is_cliff(wx, wz) == GameManager.is_cliff(px - 30.0, pwz) and GameManager.is_cliff(wx, wz))
	var r3: PackedVector3Array = GameManager.nav_route(Vector3(wx - 8.0 * float(sp["sx"]), 0.0, wz), Vector3(wx + 8.0 * float(sp["sx"]), 0.0, wz), 1.5)
	verdict("E6 сквозь стену красного A* ведёт в обход (%d точек)" % r3.size(), r3.size() >= 2)
	verdict("E4 два прохода у красного свободны от стены",
		not GameManager.is_cliff(gx, gz) and not GameManager.is_cliff(hx, hz),
		"проход вбок (%.0f,%.0f) %s, проход к игроку (%.0f,%.0f) %s" % [gx, gz, str(GameManager.is_cliff(gx, gz)), hx, hz, str(GameManager.is_cliff(hx, hz))])

# ═════════════════════════════════════════════════════════════════════════════
# F. РУДНИКИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_mines() -> void:
	print("
═════ F. ДВА РУДНИКА ПОД ОХРАНОЙ ОРДЫ ═════")
	var neutral: Array = []
	for b in get_tree().get_nodes_in_group("neutral_buildings"):
		if b is Mine:
			neutral.append(b)
	var ford: Vector3 = main.ford_point()
	var nearest_ford := INF
	var sides := {}
	for m in neutral:
		var p: Vector3 = (m as Node3D).global_position
		nearest_ford = minf(nearest_ford, Vector2(p.x - ford.x, p.z - ford.z).length())
		sides[signf(p.z)] = true
	verdict("F1 ничейных рудников два — на половине игрока и на половине красного (%d, ближайший к броду %.0f м)" % [neutral.size(), nearest_ford],
		neutral.size() == 2 and sides.size() == 2 and nearest_ford > 90.0)
	var want: int = 2 * (load("res://scripts/goblin/goblin_config.gd").MINE_GUARD as Array).size()
	verdict("F2 у каждого рудника охрана орды (отрядов %d, ждём %d)" % [int(main.territory_guard_squads), want],
		int(main.territory_guard_squads) == want)
	# Охрана патрулирует СВОЙ рудник: вожак орды включается на время
	var gai = main.goblin_ai
	gai.set_process(true)
	for w0 in get_tree().get_nodes_in_group("all_units"):
		if w0 is Unit and (w0 as Unit).faction == Constants.FACTION_GOBLIN:
			(w0 as Unit).set_tick(true)
	await pframes(60 * 12)
	gai.set_process(false)
	var far := 0
	var guards := 0
	for sid in gai.mine_guard_sids.keys():
		var own = gai.mine_guard_sids[sid]
		if not (own is Node) or not is_instance_valid(own):
			continue
		guards += 1
		var c: Vector2 = GameManager.squad_centre_xz(int(sid))
		if c.x == INF:
			continue
		var mp: Vector3 = (own as Node3D).global_position
		if Vector2(c.x - mp.x, c.y - mp.z).length() > 25.0:
			far += 1
	verdict("F3 охрана держится у своего рудника (%d отрядов, дальше 25 м — %d)" % [guards, far], guards == want and far == 0)

# ═════════════════════════════════════════════════════════════════════════════
# G. ТАРАН ПО МЕЧНИКАМ
# ═════════════════════════════════════════════════════════════════════════════
func _block_charge_rows() -> void:
	print("
═════ G. ТАРАН СВИНОВСАДНИКОВ ПО МЕЧНИКАМ ═════")
	var at := Vector3(-60.0, 0.0, -10.0)
	main._clear_area_of_resources(at, 50.0)
	for rn in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(rn) and (rn as Node3D).global_position.distance_to(at) < 50.0:
			(rn as Node).queue_free()
	for u0 in get_tree().get_nodes_in_group("all_units"):
		if u0 is Unit and not (u0 as Unit).is_dead() and (u0 as Unit).global_position.distance_to(at) < 60.0:
			(u0 as Unit).take_damage(1.0e12)
	await pframes(4)
	# Три ряда по 6 мечников лицом на восток (+X): ряд 0 — передний
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "warrior")
	var rows: Array = [[], [], []]
	var start: Dictionary = {}
	for r in range(3):
		for k in range(6):
			var u := _unit("warrior", Constants.FACTION_PLAYER, at + Vector3(-1.1 * float(r), 0.0, (float(k) - 2.5) * 0.9))
			u._facing = Vector3.RIGHT
			GameManager.add_to_squad(sid, u)
			rows[r].append(u)
			start[u] = u.global_position
	# Всадники: три полосы по два в глубину, в 30 м
	var rsid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_rider")
	var riders: Array = []
	for lane in range(3):
		for d in range(2):
			var ru := _unit("goblin_rider", Constants.FACTION_GOBLIN, at + Vector3(30.0 + 1.8 * float(d), 0.0, (float(lane) - 1.0) * 1.1))
			GameManager.add_to_squad(rsid, ru)
			riders.append(ru)
	await pframes(4)
	var imp0: int = Unit.cav_impacts_dealt
	var dbl0: int = Unit.cav_double_hits
	var w := 0
	var first_imp := -1
	while w < 60 * 15:
		await get_tree().physics_frame
		w += 1
		if first_imp < 0 and Unit.cav_impacts_dealt > imp0:
			first_imp = w
			var cc = main.cav_commander
			print("    [первый удар на %d кадре] командир: состояние %s, таранов %d, первая линия %d" % [w, String(cc.state_of(rsid)), int(cc.charges), int(cc.front_riders)])
			for ru0 in riders:
				var r0 := ru0 as Unit
				print("      всадник x=%.1f no_charge=%d charging=%s ready=%s state=%d" % [r0.global_position.x, r0.no_charge_until_ms - Time.get_ticks_msec(), str(r0.is_charging), str(r0._charge_ready), int(r0.state)])
		if first_imp >= 0 and w - first_imp > 150:
			break
	var dealt: int = Unit.cav_impacts_dealt - imp0
	var dead0 := 0
	for u in rows[0]:
		if u == null or not is_instance_valid(u) or (u as Unit).is_dead():
			dead0 += 1
	var disp: Array = [[], [], []]
	for r in range(3):
		for u in rows[r]:
			if u == null or not is_instance_valid(u) or (u as Unit).is_dead():
				continue
			var p0: Vector3 = start[u]
			disp[r].append(Vector2((u as Unit).global_position.x - p0.x, (u as Unit).global_position.z - p0.z).length())
	var max1: float = 0.0
	for v in disp[1]:
		max1 = maxf(max1, float(v))
	var med2: float = 0.0
	if not (disp[2] as Array).is_empty():
		var s2: Array = (disp[2] as Array).duplicate()
		s2.sort()
		med2 = float(s2[s2.size() / 2])
	print("    ударов с разгона %d (двойных отсечено %d), в первом ряду погибло %d, отлёт второго ряда до %.2f м, третий ряд сдвинут на %.2f м (медиана)" % [
		dealt, Unit.cav_double_hits - dbl0, dead0, max1, med2])
	verdict("G1 первый ряд: принявшие удар погибли на месте", dead0 >= 1, "погибло %d" % dead0)
	verdict("G2 второй ряд отлетает на 2.5-3.5 м (до %.2f м)" % max1, max1 >= 2.3 and max1 <= 3.9)
	var row3_alive := 0
	var row3_fight := 0
	for u3 in rows[2]:
		if u3 == null or not is_instance_valid(u3) or (u3 as Unit).is_dead():
			continue
		row3_alive += 1
		var t3 = (u3 as Unit).attack_target
		if (u3 as Unit).state == Unit.State.ATTACKING and t3 != null and is_instance_valid(t3) and (t3 as Unit).faction == Constants.FACTION_GOBLIN:
			row3_fight += 1
	# ТЗ: третий ряд «вступает в бой, задерживая кавалерию; всадники теснят
	# их через Push» — жив, дерётся и сдвинут меньше отлетевшего второго
	verdict("G3 третий ряд в бою и теснится напором, а не разлетается (живы %d/6, дерутся %d, сдвиг %.2f м < отлёта второго %.2f)" % [row3_alive, row3_fight, med2, max1],
		row3_alive >= 5 and row3_fight >= 3 and med2 < max1)
	verdict("G4 с разгона бьёт только первая линия (ударов %d при трёх полосах)" % dealt, dealt >= 1 and dealt <= 3)
	_kill(riders)
	for r in range(3):
		_kill(rows[r])
	await pframes(4)
