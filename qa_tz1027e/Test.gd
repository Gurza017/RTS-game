extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_TZ1027E — ТЗ 27.10.2026, UI/UX: курсоры и выделение казарм.
## ═══════════════════════════════════════════════════════════════════════════
## A — курсор-меч и курсор-стрела смотрят на «10 часов»: остриё/наконечник в
##     верхнем левом углу картинки, тело уходит вниз-вправо, горячая точка — на
##     острие; у стрелы два вида оперения — зелёное (ARROW) и красное (ARROW_FAR)
## B — досягаемость (SelectionManager.selection_reaches, Main._arrow_kind_for):
##     лучники достают до врага в 10 м и не достают в 60; постройка-цель меряется
##     до края рисунка; башня с гарнизоном — по дальности крыши; ручка
##     arrow_reach_tint выключена — всегда зелёная стрела
## C — двойной клик (настоящий ввод) по казарме выделяет все казармы в кадре,
##     стрелковую не трогает; по стрелковой — все стрелковые; Ctrl+1 хранит и
##     возвращает такое выделение; ручка bld_double_click выключена — одна
## Запуск: godot --headless --path . res://qa_tz1027e/Test.tscn [-- only=abc]
const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const _CursorArt := preload("res://scripts/CursorArt.gd")
const _Opt := preload("res://scripts/perf_config.gd")

var main: Node = null
var sm = null
var _pass := 0
var _fail := 0
var _only: String = "abc"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_tz1027e: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var p: Vector3 = at + Vector3(float(i / 5) * 0.7, 0.0, (float(i % 5) - 2.0) * 0.7)
		GameManager.add_to_squad(sid, _unit(uid, f, p))
	return sid

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _kill(sid: int) -> void:
	for m in _members(sid):
		(m as Unit).take_damage(1e12)

func _spot(dx: float, dz: float) -> Vector3:
	return main.PLAYER_BASE_ANCHOR + Vector3(dx, 0.0, dz)

func _bld(script_path: String, at: Vector3) -> Building:
	var b: Building = load(script_path).new()
	b.faction = F
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return b

func _mouse(btn: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	get_tree().root.push_input(e, true)

## Двойной ЛКМ настоящим вводом по экранной точке. Перед ним — пауза дольше
## DOUBLE_CLICK_TIME, чтобы предыдущий клик стенда не склеился с первым.
## Точка обязана лежать ПРАВЕЕ мини-карты (левый край окна): та съедает
## нажатие, и обработчик клика его не видит
func _double_lmb(scr: Vector2) -> void:
	await get_tree().create_timer(sm.DOUBLE_CLICK_TIME + 0.1).timeout
	for _k in range(2):
		_mouse(MOUSE_BUTTON_LEFT, true, scr)
		await frames(1)
		_mouse(MOUSE_BUTTON_LEFT, false, scr)
		await frames(2)

func _freeze_cam(at: Vector3) -> void:
	main.set_process(false)
	main._camera.set_process(false)
	main._camera.pan_to(Vector3(at.x, 0.0, at.z))
	main._camera._update_position()
	await frames(2)

func _run() -> void:
	seed(10275)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	sm = main.selection_manager
	if "a" in _only: _a_cursors()
	if "b" in _only: await _b_reach()
	if "c" in _only: await _c_double_click()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
## Непрозрачные пиксели картинки (без обводки — её альфа 1, цвет OUTLINE):
## [число, центроид, есть ли пиксель в радиусе 1.5 от p]
func _opaque_stats(tex: ImageTexture, p: Vector2) -> Array:
	var img: Image = tex.get_image()
	var n := 0
	var cx := 0.0
	var cz := 0.0
	var near := false
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.5:
				n += 1
				cx += float(x)
				cz += float(y)
				if Vector2(float(x), float(y)).distance_to(p) <= 1.5:
					near = true
	return [n, Vector2(cx / maxf(1.0, float(n)), cz / maxf(1.0, float(n))), near]

## Средний цвет непрозрачных пикселей в прямоугольнике (нижний правый угол —
## оперение стрелы); обводка (почти чёрная) не считается
func _mean_color(tex: ImageTexture, x0: int, y0: int, x1: int, y1: int) -> Color:
	var img: Image = tex.get_image()
	var acc := Color(0, 0, 0, 0)
	var n := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and (c.r + c.g + c.b) > 0.4:
				acc += c
				n += 1
	return acc / float(maxi(n, 1))

func _a_cursors() -> void:
	print("\n═════ A. КУРСОРЫ НА «10 ЧАСОВ» ═════")
	var sw: ImageTexture = _CursorArt.texture(_CursorArt.SWORD)
	var ar: ImageTexture = _CursorArt.texture(_CursorArt.ARROW)
	var far: ImageTexture = _CursorArt.texture(_CursorArt.ARROW_FAR)
	verdict("A0 три картинки построены", sw != null and ar != null and far != null)
	if sw == null or ar == null or far == null:
		return
	var hs_s: Vector2 = _CursorArt.hotspot(_CursorArt.SWORD)
	var hs_a: Vector2 = _CursorArt.hotspot(_CursorArt.ARROW)
	var hs_f: Vector2 = _CursorArt.hotspot(_CursorArt.ARROW_FAR)
	var tl := hs_s.x < 8.0 and hs_s.y < 8.0 and hs_a.x < 8.0 and hs_a.y < 8.0 and hs_f == hs_a
	verdict("A1 горячая точка меча и стрелы — верхний левый угол", tl, "меч %s, стрела %s" % [str(hs_s), str(hs_a)])
	var st_s: Array = _opaque_stats(sw, hs_s)
	var st_a: Array = _opaque_stats(ar, hs_a)
	var c_s: Vector2 = st_s[1]
	var c_a: Vector2 = st_a[1]
	verdict("A2 меч: остриё под горячей точкой, тело уходит вниз-вправо",
		bool(st_s[2]) and c_s.x > 12.0 and c_s.y > 12.0 and absf(c_s.x - c_s.y) < 4.0,
		"центроид %s, пикселей %d" % [str(c_s), int(st_s[0])])
	verdict("A3 стрела: наконечник под горячей точкой, древко вниз-вправо",
		bool(st_a[2]) and c_a.x > 12.0 and c_a.y > 12.0 and absf(c_a.x - c_a.y) < 4.0,
		"центроид %s, пикселей %d" % [str(c_a), int(st_a[0])])
	# Старое место острия (3, 28) — внизу слева — теперь пусто у обоих
	var old_s: Array = _opaque_stats(sw, Vector2(3, 28))
	var old_a: Array = _opaque_stats(ar, Vector2(3, 28))
	verdict("A4 внизу слева (прежнее остриё) пусто", not bool(old_s[2]) and not bool(old_a[2]))
	var fl_near: Color = _mean_color(ar, 20, 20, 31, 31)
	var fl_far: Color = _mean_color(far, 20, 20, 31, 31)
	verdict("A5 оперение ARROW зелёное", fl_near.g > fl_near.r + 0.2 and fl_near.g > fl_near.b + 0.2, "%s" % str(fl_near))
	verdict("A6 оперение ARROW_FAR красное", fl_far.r > fl_far.g + 0.2 and fl_far.r > fl_far.b + 0.2, "%s" % str(fl_far))
	# Наконечник у обоих — железо, одинаковый: красится только оперение
	# Разворот ТЗ 29.10.2026, п. 2: у ARROW_FAR на острие красный крестик
	var tip_n: Color = _mean_color(ar, 0, 0, 9, 9)
	var tip_f: Color = _mean_color(far, 0, 0, 9, 9)
	verdict("A7 на острие ARROW_FAR — красный крестик, у ARROW его нет",
		tip_f.r > tip_n.r + 0.05 and tip_f.r > tip_f.g + 0.1 and tip_n.r < tip_n.b + 0.1,
		"%s / %s" % [str(tip_n), str(tip_f)])

# ═════════════════════════════════════════════════════════════════════════════
func _b_reach() -> void:
	print("\n═════ B. ДОСЯГАЕМОСТЬ — ЦВЕТ ОПЕРЕНИЯ ═════")
	var at := _spot(40, 10)
	main._clear_area_of_resources(at, 90.0)
	var arch: int = _squad("archer", F, at, 10)
	await pframes(3)
	var a0: Unit = _members(arch)[0]
	var rng: float = a0.attack_range
	var near_sid: int = _squad("spearman", R, at + Vector3(rng - 4.0, 0, 0), 5)
	var far_sid: int = _squad("spearman", R, at + Vector3(rng + 20.0, 0, 0), 5)
	await pframes(3)
	var near_u: Unit = _members(near_sid)[0]
	var far_u: Unit = _members(far_sid)[0]
	sm.select_units(_members(arch))
	await pframes(2)
	verdict("B1 лучники (дальность %.1f м) достают до врага в %.1f м" % [rng, a0.global_position.distance_to(near_u.global_position)],
		sm.selection_reaches(near_u, near_u.global_position))
	verdict("B2 и не достают до врага в %.1f м" % a0.global_position.distance_to(far_u.global_position),
		not sm.selection_reaches(far_u, far_u.global_position))
	# Точка земли без цели — как есть
	verdict("B3 точка земли в дальности — достают", sm.selection_reaches(null, at + Vector3(rng - 2.0, 0, 0)))
	verdict("B4 точка земли за дальностью — нет", not sm.selection_reaches(null, at + Vector3(rng + 2.0, 0, 0)))
	# Постройка-цель: центр за дальностью, стена — в дальности (Unit._pad_of)
	var hut: Building = load("res://scripts/Tower.gd").new()
	hut.faction = R
	main.world_add(hut)
	var hp: Vector3 = at + Vector3(0, 0, rng + 1.0)
	hut.global_position = Vector3(hp.x, GameManager.get_terrain_height(hp.x, hp.z), hp.z)
	await pframes(3)
	var pad: float = Unit._pad_of(hut)
	verdict("B5 постройка: центр в %.1f м (за дальностью), край рисунка (%.1f м) — достают" % [rng + 1.0, pad],
		pad > 1.0 and sm.selection_reaches(hut, hut.global_position))
	# Главная ветка: Main._arrow_kind_for по цели прицела
	main._hover_aim = near_u
	var k_near: int = main._arrow_kind_for(Vector2.ZERO, true)
	main._hover_aim = far_u
	var k_far: int = main._arrow_kind_for(Vector2.ZERO, true)
	verdict("B6 курсор над ближним врагом — ARROW (зелёный), над дальним — ARROW_FAR (красный)",
		k_near == _CursorArt.ARROW and k_far == _CursorArt.ARROW_FAR, "%d / %d" % [k_near, k_far])
	_Opt.arrow_reach_tint = false
	var k_off: int = main._arrow_kind_for(Vector2.ZERO, true)
	_Opt.arrow_reach_tint = true
	verdict("B7 ручка arrow_reach_tint выключена — над дальним врагом обычная стрела", k_off == _CursorArt.ARROW)
	# Башня с гарнизоном: дальность крыши
	var tw: Building = load("res://scripts/Tower.gd").new()
	tw.faction = F
	main.world_add(tw)
	var tp: Vector3 = at + Vector3(0, 0, -30)
	tw.global_position = Vector3(tp.x, GameManager.get_terrain_height(tp.x, tp.z), tp.z)
	await pframes(4)
	var gs: int = _squad("archer", F, tp + Vector3(0, 0, 6), 8)
	await pframes(2)
	var sat: bool = (tw as Castle).garrison_now(gs)
	await pframes(4)
	sm.clear_selection()
	sm.select_units([tw])
	await pframes(2)
	var tr: float = float(tw.call("fire_range"))
	var ok_t: bool = sat and tr > 0.0 \
		and sm.selection_reaches(null, tp + Vector3(tr - 2.0, 0, 0)) \
		and not sm.selection_reaches(null, tp + Vector3(tr + 3.0, 0, 0))
	verdict("B8 башня с гарнизоном: достаёт на дальность крыши (%.1f м) и не дальше" % tr, ok_t, "посажены=%s" % str(sat))
	sm.clear_selection()
	_kill(arch); _kill(near_sid); _kill(far_sid)
	hut.take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _c_double_click() -> void:
	print("\n═════ C. ДВОЙНОЙ КЛИК ПО КАЗАРМАМ ═════")
	var at := _spot(40, 70)
	main._clear_area_of_resources(at, 60.0)
	var b1: Building = _bld("res://scripts/Barracks.gd", at + Vector3(3, 0, 0))
	var b2: Building = _bld("res://scripts/Barracks.gd", at + Vector3(9, 0, 0))
	var ar1: Building = _bld("res://scripts/Archery.gd", at + Vector3(6, 0, 5))
	var ar2: Building = _bld("res://scripts/Archery.gd", at + Vector3(6, 0, -5))
	await pframes(6)
	sm.clear_selection()
	await _freeze_cam(at)
	var cam: Camera3D = sm.camera
	# Форма попадания постройки с рисунком — пластина по спрайту, сдвинутая к
	# камере (Building._fit_pick_to_sprite): целимся в неё, а не в центр коробки
	var scr: Vector2 = cam.unproject_position((b1._pick_shape as Node3D).global_position)
	await _double_lmb(scr)
	await pframes(2)
	var sel: Array = sm.selected_units.duplicate()
	var has := func(n) -> bool: return sel.has(n)
	verdict("C1 двойной клик по казарме — обе казармы выделены, стрелковые нет",
		has.call(b1) and has.call(b2) and not has.call(ar1) and not has.call(ar2),
		"выделено %d: b1=%s b2=%s ar1=%s ar2=%s" % [sel.size(), str(has.call(b1)), str(has.call(b2)), str(has.call(ar1)), str(has.call(ar2))])
	# Ctrl+1 — группа хранит здания и возвращает их
	sm._save_group(1)
	sm.clear_selection()
	await pframes(1)
	sm._recall_group(1)
	await pframes(1)
	var g: Array = sm.selected_units.duplicate()
	verdict("C2 Ctrl+1 хранит выделение казарм и возвращает его", g.size() == 2 and g.has(b1) and g.has(b2), "вернулось %d" % g.size())
	sm.clear_selection()
	await pframes(1)
	# Стрелковая: клик по ar1 — обе стрелковые, казармы нет
	var scr2: Vector2 = cam.unproject_position((ar1._pick_shape as Node3D).global_position)
	await _double_lmb(scr2)
	await pframes(2)
	var sel2: Array = sm.selected_units.duplicate()
	verdict("C3 двойной клик по стрелковой — обе стрелковые, казармы нет",
		sel2.has(ar1) and sel2.has(ar2) and not sel2.has(b1) and not sel2.has(b2), "выделено %d" % sel2.size())
	sm.clear_selection()
	await pframes(1)
	# Ручка выключена — одиночное выделение, как прежде
	_Opt.bld_double_click = false
	await _double_lmb(scr)
	await pframes(2)
	var sel3: Array = sm.selected_units.duplicate()
	_Opt.bld_double_click = true
	verdict("C4 ручка bld_double_click выключена — выделена одна казарма", sel3.size() == 1 and sel3.has(b1), "выделено %d" % sel3.size())
	# Казарма вне кадра не выделяется
	sm.clear_selection()
	var b3: Building = _bld("res://scripts/Barracks.gd", at + Vector3(400, 0, 0))
	await pframes(3)
	await _double_lmb(scr)
	await pframes(2)
	var sel4: Array = sm.selected_units.duplicate()
	verdict("C5 казарма вне кадра не попадает в выделение", sel4.has(b1) and sel4.has(b2) and not sel4.has(b3), "выделено %d" % sel4.size())
	sm.clear_selection()
	main.set_process(true)
	main._camera.set_process(true)
