extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_world2 — ДЫРЫ, НЕ ЗАКРЫТЫЕ СТЕНДОМ qa_world
## ═══════════════════════════════════════════════════════════════════════════
## qa_world проверяет «что построено»: константы, размеры мешей, один юнит
## у стены. Здесь проверяется «что происходит при работе»:
##   A КАМЕРА     — ракурс не плывёт ни от какой последовательности ввода,
##                  вырожденные шаги панорамы не дают NaN/inf
##   B КЛИКИ      — разбор луча при НОВОМ ракурсе 60°: край карты, чернота,
##                  не крадёт ли клики 12-метровая стена периметра
##   C ГРАНИЦЫ    — не «просачивание», а ПРИБЫТИЕ: отряд у стены обязан
##                  дойти и встать, а не топтаться вечно и не слипнуться
##   D ИИ         — рубеж, патрули и посты в новых координатах, приказы ИИ
##                  не уводят отряды за край
##   E БЕЗ ОЗЕРА  — код воды остался в проекте: не виснет ли он вхолостую
##                  (nearest_land, slide_around_water, выход из гарнизона,
##                  полный цикл рабочего через бывшее озеро)
##   F ЦЕНА       — сколько стоит зажим границ в горячих путях
##
## Границы мира НЕ отключаются: вся площадка стенда лежит внутри карты.
## Единственное исключение — раздел F, где выключатель и есть предмет замера.

const _UCfg = preload("res://scripts/unit_stats_config.gd")

var main = null
var cam: RTSCamera = null
var sm: SelectionManager = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _perf: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n:
		out += " "
	return out

func _spawn(kind: String, fac: int, pos: Vector3) -> Unit:
	var u: Unit = null
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"worker":   u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = pos
	return u

func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _lim() -> float:
	return float(main.MAP_HALF_X) - float(main.MAP_EDGE_MARGIN)

## Инструмент прицеливания: ставим фокус камеры и возвращаем экранную точку
## мирового места. Пересчёт трансформа делается ВРУЧНУЮ — писать
## camera.global_position бесполезно, _process всё равно пересоберёт его
func aim(world: Vector3) -> Vector2:
	cam._focus = Vector3(
		clampf(world.x, cam.bounds_min.x, cam.bounds_max.x), 0.0,
		clampf(world.z, cam.bounds_min.y, cam.bounds_max.y))
	cam._height = cam._target_height
	cam._update_position()
	return cam.unproject_position(world)

## Аналитическая точка земли под экранной точкой: пересечение луча с y=0
func ground_under(screen: Vector2) -> Vector3:
	var from := cam.project_ray_origin(screen)
	var dirn := cam.project_ray_normal(screen)
	if absf(dirn.y) < 1e-5:
		return Vector3(INF, 0.0, INF)
	var t: float = -from.y / dirn.y
	if t <= 0.0:
		return Vector3(INF, 0.0, INF)
	var p := from + dirn * t
	return Vector3(p.x, 0.0, p.z)

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	cam = main._camera
	sm  = main.selection_manager
	# ГРАНИЦЫ КАМЕРЫ БОЛЬШЕ НЕ КОНСТАНТА. Здесь читалось main.CAM_BOUND_X —
	# число, убранное вместе с переходом на зум- и аспект-зависимый зажим
	# (RTSCamera._clamp_focus считает его из _map_half под текущую высоту и
	# соотношение сторон окна). Стенд падал на этой строке ещё до первой
	# проверки. Печатаем сырую полукарту, которую камера и хранит
	print("карта: половина %.1f, предел юнитов ±%.1f, полукарта камеры ±%.1f" % [
		main.MAP_HALF_X, _lim(), cam._map_half.x])

	await _a_camera()
	await _b_picking()
	await _c_bounds()
	await _d_ai()
	await _e_no_lake()
	await _f_perf()

	print("\n═════ ИТОГ qa_world2 ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 64), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n───── ЗАМЕРЫ ─────")
	for p in _perf:
		print("  %s" % String(p))
	print("\n=== WORLD2 TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. КАМЕРА: РАКУРС НЕ ПЛЫВЁТ НИ ОТ ЧЕГО
# qa_world проверял ракурс после одной аккуратной последовательности. Здесь —
# перемешанный поток ввода и вырожденные величины.
# ═════════════════════════════════════════════════════════════════════════════
func _a_camera() -> void:
	print("\n═════ A. КАМЕРА: СТРЕСС ВВОДА ═════")

	# ── A1. МИР НЕ ВРАЩАЕТСЯ ВООБЩЕ ─────────────────────────────────────────
	var wt: Transform3D = (main._world as Node3D).global_transform
	print("  трансформ узла World: %s" % str(wt))
	verdict("A1 контейнер карты World остался единичным (мир не вращают)",
		wt.is_equal_approx(Transform3D.IDENTITY), str(wt))

	# ── A2. ФАКТИЧЕСКИЙ РАКУРС В МИРЕ, А НЕ ЗНАЧЕНИЕ ПЕРЕМЕННОЙ ─────────────
	cam._target_height = 28.0
	cam._height = 28.0
	cam.pan_to(Vector3.ZERO)
	cam._update_position()
	var fwd: Vector3 = -cam.global_transform.basis.z
	var real_pitch: float = rad_to_deg(asin(clampf(-fwd.y, -1.0, 1.0)))
	var real_yaw: float   = rad_to_deg(atan2(-fwd.x, -fwd.z))
	print("  фактический взгляд камеры: наклон %.3f°, азимут %.3f°" % [real_pitch, real_yaw])
	verdict("A2 камера реально висит под FIXED_PITCH, а не только в переменной",
		absf(real_pitch - RTSCamera.FIXED_PITCH) < 0.05 and absf(real_yaw) < 0.05,
		"наклон %.3f, азимут %.3f" % [real_pitch, real_yaw])

	# ── A3. ПЕРЕМЕШАННЫЙ ПОТОК ВВОДА ────────────────────────────────────────
	var yaw0: float   = cam._orbit_yaw
	var pitch0: float = cam._orbit_pitch
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	var mx := 0.0
	var my := 0.0
	for i in range(1200):
		var pick: int = rng.randi_range(0, 4)
		if pick == 0:
			var w := InputEventMouseButton.new()
			w.button_index = MOUSE_BUTTON_WHEEL_UP if rng.randf() < 0.5 else MOUSE_BUTTON_WHEEL_DOWN
			w.pressed = true
			cam._unhandled_input(w)
		elif pick == 1:
			var d := InputEventMouseButton.new()
			d.button_index = MOUSE_BUTTON_MIDDLE
			d.pressed = (i % 2 == 0)
			d.position = Vector2(mx, my)
			cam._unhandled_input(d)
		elif pick == 2:
			mx += rng.randf_range(-400.0, 400.0)
			my += rng.randf_range(-400.0, 400.0)
			var mm := InputEventMouseMotion.new()
			mm.position = Vector2(mx, my)
			cam._unhandled_input(mm)
		elif pick == 3:
			cam.pan_to(Vector3(rng.randf_range(-9000.0, 9000.0), 0.0,
				rng.randf_range(-9000.0, 9000.0)))
		else:
			cam._pan_by(Vector2(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0)))
			cam._update_position()
	print("  1200 случайных событий (колесо/средняя кнопка/рывки мыши/pan_to за карту)")
	print("  ракурс после: поворот %.9f, наклон %.9f" % [cam._orbit_yaw, cam._orbit_pitch])
	verdict("A3 ракурс не сдвинулся ни на йоту после потока ввода",
		cam._orbit_yaw == yaw0 and cam._orbit_pitch == pitch0,
		"поворот %.9f (было %.9f), наклон %.9f (было %.9f)" % [
			cam._orbit_yaw, yaw0, cam._orbit_pitch, pitch0])
	verdict("A4 фокус остался внутри границ камеры после потока ввода",
		absf(cam._focus.x) <= main.CAM_BOUND_X + 0.001 and absf(cam._focus.z) <= main.CAM_BOUND_X + 0.001,
		"(%.2f, %.2f)" % [cam._focus.x, cam._focus.z])
	verdict("A5 высота зума осталась в min..max после потока ввода",
		cam._target_height >= cam.min_height - 0.001 and cam._target_height <= cam.max_height + 0.001,
		"%.2f при пределах %.1f..%.1f" % [cam._target_height, cam.min_height, cam.max_height])

	# ── A6. ВЫРОЖДЕННЫЕ ШАГИ ПАНОРАМЫ ───────────────────────────────────────
	cam.pan_to(Vector3(10.0, 0.0, -20.0))
	var f_before: Vector3 = cam._focus
	cam._pan_by(Vector2.ZERO)
	var zero_ok: bool = cam._focus.x == f_before.x and cam._focus.z == f_before.z
	print("  нулевой шаг: фокус (%.6f, %.6f) → (%.6f, %.6f)" % [
		f_before.x, f_before.z, cam._focus.x, cam._focus.z])
	verdict("A6 нулевой шаг панорамы не двигает фокус", zero_ok)

	var huge: Array[float] = [1.0e6, -1.0e6, 1.0e12, -1.0e12, 1.0e30, -1.0e30]
	var bad_focus := 0
	var bad_cam := 0
	for h in huge:
		cam._pan_by(Vector2(h, h * 0.5))
		cam._update_position()
		if not _finite3(cam._focus) or absf(cam._focus.x) > main.CAM_BOUND_X + 0.001 \
				or absf(cam._focus.z) > main.CAM_BOUND_X + 0.001:
			bad_focus += 1
		if not _finite3(cam.global_position):
			bad_cam += 1
	print("  6 гигантских шагов панорамы: фокус (%.2f, %.2f), камера %s" % [
		cam._focus.x, cam._focus.z, str(cam.global_position)])
	verdict("A7 гигантский шаг панорамы не даёт NaN/inf и не рвёт границы фокуса",
		bad_focus == 0, "сбоев фокуса %d из 6" % bad_focus)
	verdict("A8 позиция камеры остаётся конечной при гигантских шагах",
		bad_cam == 0, "сбоев позиции %d из 6" % bad_cam)

	# ── A9. ЗУМ НА УПОРЕ НЕ ТРОГАЕТ ФОКУС ───────────────────────────────────
	cam.pan_to(Vector3(30.0, 0.0, 30.0))
	var fz: Vector3 = cam._focus
	for _i in range(60):
		var w2 := InputEventMouseButton.new()
		w2.button_index = MOUSE_BUTTON_WHEEL_UP
		w2.pressed = true
		cam._unhandled_input(w2)
	for _i in range(120):
		var w3 := InputEventMouseButton.new()
		w3.button_index = MOUSE_BUTTON_WHEEL_DOWN
		w3.pressed = true
		cam._unhandled_input(w3)
	print("  зум до обоих упоров: фокус (%.3f, %.3f) → (%.3f, %.3f), высота %.2f" % [
		fz.x, fz.z, cam._focus.x, cam._focus.z, cam._target_height])
	verdict("A9 зум до упоров не сдвигает фокус и не ломает его границы",
		cam._focus.x == fz.x and cam._focus.z == fz.z,
		"(%.3f, %.3f) против (%.3f, %.3f)" % [cam._focus.x, cam._focus.z, fz.x, fz.z])

	# ── A10. ПАНОРАМА КЛАВИАТУРОЙ/КРАЕМ ЭКРАНА ЗА КАДРЫ ─────────────────────
	# В headless курсор стоит в (0,0) — это ровно случай «скролл краем экрана».
	# Камера обязана уехать в угол и ТАМ ОСТАНОВИТЬСЯ, а не уползти в черноту
	cam._target_height = 28.0
	await frames(240)
	print("  240 кадров скролла краем экрана: фокус (%.3f, %.3f), предел ±%.1f" % [
		cam._focus.x, cam._focus.z, main.CAM_BOUND_X])
	verdict("A10 панорама краем экрана упирается в границы, а не уходит в черноту",
		_finite3(cam._focus)
			and absf(cam._focus.x) <= main.CAM_BOUND_X + 0.001
			and absf(cam._focus.z) <= main.CAM_BOUND_X + 0.001,
		"(%.3f, %.3f)" % [cam._focus.x, cam._focus.z])
	verdict("A11 длинная панорама не сдвинула ракурс",
		cam._orbit_yaw == yaw0 and cam._orbit_pitch == pitch0,
		"поворот %.9f, наклон %.9f" % [cam._orbit_yaw, cam._orbit_pitch])

	# ── A12. set_bounds УМЕНЬШИЛИ — ФОКУС ВТЯГИВАЕТСЯ СРАЗУ ─────────────────
	cam.pan_to(Vector3(main.CAM_BOUND_X, 0.0, main.CAM_BOUND_X))
	cam.set_bounds(20.0)
	var pulled: bool = absf(cam._focus.x - 20.0) < 0.001 and absf(cam._focus.z - 20.0) < 0.001
	print("  set_bounds(20) при фокусе на границе → (%.2f, %.2f)" % [cam._focus.x, cam._focus.z])
	verdict("A12 сужение границ втягивает фокус немедленно", pulled,
		"(%.2f, %.2f)" % [cam._focus.x, cam._focus.z])
	cam.set_bounds(main.CAM_BOUND_X)

# ═════════════════════════════════════════════════════════════════════════════
# B. РАЗБОР КЛИКОВ ПРИ РАКУРСЕ 60°
# ═════════════════════════════════════════════════════════════════════════════
func _b_picking() -> void:
	print("\n═════ B. КЛИКИ ПРИ РАКУРСЕ 60° ═════")
	var mask_all: int = Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS \
		| Constants.LAYER_RESOURCES | Constants.LAYER_GROUND
	var mask_sel: int = Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS
	var lim: float = _lim()
	cam._target_height = 28.0
	cam._height = 28.0

	# Площадка у ЗАПАДНОГО края, подальше от базы ИИ
	var base := Vector3(-lim + 6.0, 0.0, 10.0)
	var soldier := _spawn("spearman", Constants.FACTION_PLAYER, base)
	var barracks := Barracks.new()
	barracks.faction = Constants.FACTION_PLAYER
	main.world_add(barracks)
	barracks.global_position = base + Vector3(0.0, 0.0, -12.0)
	await frames(6)

	# ── B1. КЛИК ПО БОЙЦУ ───────────────────────────────────────────────────
	var s1 := aim(soldier.global_position + Vector3(0.0, 0.9, 0.0))
	var p1: Dictionary = sm._pick_at(s1, mask_sel)
	print("  клик по бойцу (экран %.0f,%.0f) → %s" % [s1.x, s1.y, _nm(p1["target"])])
	verdict("B1 клик по бойцу при 60° выбирает бойца", p1["target"] == soldier,
		"выбрано %s" % _nm(p1["target"]))

	# ── B2. КЛИК ПО ЗДАНИЮ ──────────────────────────────────────────────────
	var s2 := aim(barracks.global_position + Vector3(0.0, barracks.build_size.y * 0.6, 0.0))
	var p2: Dictionary = sm._pick_at(s2, mask_sel)
	print("  клик по бараку (экран %.0f,%.0f) → %s" % [s2.x, s2.y, _nm(p2["target"])])
	verdict("B2 клик по зданию при 60° выбирает здание", p2["target"] == barracks,
		"выбрано %s" % _nm(p2["target"]))

	# ── B3. КЛИК ПО ЗЕМЛЕ У САМОГО КРАЯ КАРТЫ ───────────────────────────────
	var edge := Vector3(-lim + 0.2, 0.0, 40.0)
	var s3 := aim(edge)
	var p3: Dictionary = sm._pick_at(s3, mask_all)
	var g3: Vector3 = p3["position"]
	var err3: float = Vector2(g3.x - edge.x, g3.z - edge.z).length()
	print("  клик по земле у края: ждали (%.2f, %.2f), получили (%.2f, %.2f), ошибка %.3f м" % [
		edge.x, edge.z, g3.x, g3.z, err3])
	verdict("B3 клик по земле у самого края даёт точку земли, а не тело стены",
		p3["target"] == null and err3 < 0.6, "цель %s, ошибка %.3f м" % [_nm(p3["target"]), err3])

	# ── B4. КЛИК ЗА КАРТУ (В ЧЕРНОТУ) ───────────────────────────────────────
	# Фокус держим у края и целимся ЗА поле. Проверяем не только точку, но и
	# ВЕСЬ путь приказа: правая кнопка не должна увести отряд за границу
	var beyond := Vector3(-main.MAP_HALF_X - 40.0, 0.0, 40.0)
	cam.pan_to(Vector3(-main.CAM_BOUND_X, 0.0, 40.0))
	cam._height = cam._target_height
	cam._update_position()
	var s4: Vector2 = cam.unproject_position(beyond)
	var p4: Dictionary = sm._pick_at(s4, mask_all)
	var g4: Vector3 = p4["position"]
	print("  клик в черноту (мир x=%.1f): точка (%.2f, %.2f, %.2f), цель %s" % [
		beyond.x, g4.x, g4.y, g4.z, _nm(p4["target"])])
	verdict("B4 клик в черноту не выбирает объект и даёт конечную точку",
		p4["target"] == null and _finite3(g4), "цель %s, точка %s" % [_nm(p4["target"]), str(g4)])

	sm._clear_selection()
	sm.selected_units = [soldier]
	soldier.set_selected(true)
	sm._handle_right_click(s4)
	var mt: Vector3 = soldier.move_target
	print("  приказ ПКМ в черноту → цель бойца (%.2f, %.2f)" % [mt.x, mt.z])
	verdict("B5 приказ ПКМ в черноту зажимается в границы карты",
		absf(mt.x) <= lim + 0.01 and absf(mt.z) <= lim + 0.01 and _finite3(mt),
		"(%.2f, %.2f) при пределе %.2f" % [mt.x, mt.z, lim])
	sm._clear_selection()

	# ── B6. СТЕНА ПЕРИМЕТРА НЕ КРАДЁТ КЛИКИ ─────────────────────────────────
	# WorldWalls — тела высотой 12 м, стоящие СНАРУЖИ поля. На максимальном
	# отдалении камера физически оказывается ЗА южной стеной (фокус до
	# CAM_BOUND + вынос _height/tan(60°)), и луч к южной кромке карты идёт
	# СКВОЗЬ стену. Если стена на слое выбора — правый клик по южной полосе
	# возвращает точку на ней, а разбор целей обрывается: врага, жилу и своего
	# бойца там назначить целью нельзя
	cam._target_height = cam.max_height
	cam._height = cam.max_height
	var worst := 0.0
	var stolen := 0
	var probes := 0
	var blockers: Array = []
	for k in range(9):
		var wz: float = lim - float(k) * 2.0
		var wpt := Vector3(float(k - 4) * 12.0, 0.0, wz)
		cam.pan_to(Vector3(wpt.x, 0.0, main.CAM_BOUND_X))
		cam._update_position()
		var sc: Vector2 = cam.unproject_position(wpt)
		if sc.x < 0.0 or sc.x > 1280.0 or sc.y < 0.0 or sc.y > 720.0:
			continue
		probes += 1
		var pk: Dictionary = sm._pick_at(sc, mask_all)
		var gp: Vector3 = pk["position"]
		var err: float = Vector2(gp.x - wpt.x, gp.z - wpt.z).length()
		worst = maxf(worst, err)
		if err > 1.0:
			stolen += 1
			# Кто именно перехватил луч — имя тела в отчёт, чтобы дефект
			# читался без догадок
			var raw: Dictionary = sm._screen_ray_hit(sc, mask_all)
			var who: String = "ничего"
			if raw.has("collider") and raw["collider"] != null:
				who = "%s (y=%.2f)" % [(raw["collider"] as Node).name,
					(raw["position"] as Vector3).y]
			if not (who in blockers):
				blockers.append(who)
	print("  %d проб у южного края на максимальном отдалении: худшая ошибка %.3f м, украдено %d" % [
		probes, worst, stolen])
	if not blockers.is_empty():
		print("  луч перехватывают: %s" % str(blockers))
	verdict("B6 стена периметра не перехватывает лучи выбора у южной кромки",
		probes > 0 and stolen == 0, "проб %d, украдено %d, худшая ошибка %.3f м, перехват: %s" % [
			probes, stolen, worst, str(blockers)])

	# ── B7. СЕТКА ПО ВСЕМУ ЭКРАНУ: НИ ОДИН КЛИК НЕ ДАЁТ МУСОРА ──────────────
	cam._target_height = 28.0
	cam._height = 28.0
	cam.pan_to(Vector3(main.CAM_BOUND_X, 0.0, main.CAM_BOUND_X))
	cam._update_position()
	var bad := 0
	var outside := 0
	var total := 0
	for ix in range(7):
		for iy in range(7):
			var sc2 := Vector2(20.0 + float(ix) * 206.0, 20.0 + float(iy) * 113.0)
			var pk2: Dictionary = sm._pick_at(sc2, mask_all)
			var gp2: Vector3 = pk2["position"]
			total += 1
			if not _finite3(gp2):
				bad += 1
				continue
			var lt: Vector3 = GameManager.land_target(gp2)
			if absf(lt.x) > lim + 0.01 or absf(lt.z) > lim + 0.01 or not _finite3(lt):
				outside += 1
	print("  сетка %d кликов в углу карты: мусорных точек %d, приказов за краем %d" % [
		total, bad, outside])
	verdict("B7 ни один клик по экрану не даёт NaN/inf в точке земли", bad == 0,
		"мусорных %d из %d" % [bad, total])
	verdict("B8 ни один клик по экрану не превращается в приказ за край карты",
		outside == 0, "за краем %d из %d" % [outside, total])

	# ── B9. БОЕЦ НА ГАБАРИТЕ ЗДАНИЯ ─────────────────────────────────────────
	# Поправка ракурса unit_slack считается от наклона луча. Ракурс сменился на
	# 60° — проверяем, что боец у стены здания всё ещё выигрывает клик
	var guard := _spawn("spearman", Constants.FACTION_PLAYER,
		barracks.global_position + Vector3(0.0, 0.0, maxf(barracks.build_size.z, 1.0) * 0.5 + 0.6))
	await frames(4)
	var s9 := aim(guard.global_position + Vector3(0.0, 0.9, 0.0))
	var p9: Dictionary = sm._pick_at(s9, mask_sel)
	print("  клик по бойцу вплотную к бараку → %s" % _nm(p9["target"]))
	verdict("B9 при 60° боец у стены здания всё ещё выигрывает клик",
		p9["target"] == guard, "выбрано %s" % _nm(p9["target"]))

	soldier.queue_free()
	guard.queue_free()
	barracks.queue_free()
	await frames(3)

func _nm(n) -> String:
	if n == null:
		return "ничего"
	if n is Unit:
		return "боец %s" % (n as Unit).display_name
	if n is Building:
		return "здание %s" % (n as Building).display_name
	if n is ResourceNode:
		return "ресурс"
	return str(n)

# ═════════════════════════════════════════════════════════════════════════════
# C. ГРАНИЦЫ: НЕ «НЕ ПРОЛЕЗ», А «ДОШЁЛ И ВСТАЛ»
# ═════════════════════════════════════════════════════════════════════════════
func _c_bounds() -> void:
	print("\n═════ C. ГРАНИЦЫ: ПРИБЫТИЕ И УГЛЫ ═════")
	var lim: float = _lim()

	# ── C1. ОДИНОЧКА С ПРИКАЗОМ РОВНО В УГОЛ ────────────────────────────────
	var corner := Vector3(-main.MAP_HALF_X, 0.0, main.MAP_HALF_X)      # ровно угол поля
	var u := _spawn("spearman", Constants.FACTION_PLAYER, Vector3(-lim + 14.0, 0.0, lim - 14.0))
	await frames(3)
	u.command_move(corner)
	var goal: Vector3 = u.move_target
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await get_tree().process_frame
		if u.state == Unit.State.IDLE:
			break
	var dt1: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var left1: float = Vector2(u.global_position.x - goal.x, u.global_position.z - goal.z).length()
	print("  приказ в угол (%.1f, %.1f) → цель зажата в (%.2f, %.2f); за %.1f с состояние %d, осталось %.2f м" % [
		corner.x, corner.z, goal.x, goal.z, dt1, u.state, left1])
	verdict("C1 приказ ровно в угол карты доводит бойца до IDLE, а не топчет вечно",
		u.state == Unit.State.IDLE and left1 < 0.6,
		"состояние %d, осталось %.2f м за %.1f с" % [u.state, left1, dt1])
	verdict("C2 дошедший в угол боец стоит внутри карты",
		absf(u.global_position.x) <= lim + 0.01 and absf(u.global_position.z) <= lim + 0.01,
		"(%.2f, %.2f)" % [u.global_position.x, u.global_position.z])
	u.queue_free()
	await frames(3)

	# ── C3. ОТРЯД 50 С ПРИКАЗОМ В ТОЧКУ У САМОЙ СТЕНЫ ───────────────────────
	# Слоты строя, попавшие за границу, зажимаются в одну и ту же точку.
	# Отряд обязан ПРИЙТИ и встать, а не толкаться в ней бесконечно
	var wall_pt := Vector3(-lim + 0.3, 0.0, -20.0)
	var squad: Array = []
	for i in range(50):
		var col: int = i % 10
		var row: int = i / 10
		var s := _spawn("spearman", Constants.FACTION_PLAYER,
			Vector3(-lim + 22.0 + float(row) * 0.6, 0.0, -24.0 + float(col) * 0.6))
		squad.append(s)
	await frames(5)
	for i in range(50):
		var col2: int = i % 10
		var row2: int = i / 10
		var off := Vector3(float(row2) * 0.55 - 1.1, 0.0, (float(col2) - 4.5) * 0.5)
		(squad[i] as Unit).command_move(wall_pt + off)
	var t2: int = Time.get_ticks_msec()
	var idle := 0
	while Time.get_ticks_msec() - t2 < 40000:
		await get_tree().process_frame
		idle = 0
		for s2 in squad:
			if (s2 as Unit).state == Unit.State.IDLE:
				idle += 1
		if idle == 50:
			break
	var dt2: float = float(Time.get_ticks_msec() - t2) / 1000.0
	var m := _spread(squad)
	print("  отряд 50 к стене: в IDLE %d/50 за %.1f с; за краем %d; пятно %.2f×%.2f м; ближайший сосед в среднем %.3f м, минимум %.3f м" % [
		idle, dt2, int(m["outside"]), float(m["w"]), float(m["h"]),
		float(m["nn_avg"]), float(m["nn_min"])])
	verdict("C3 отряд 50 у самой стены ДОХОДИТ и встаёт в IDLE", idle == 50,
		"в IDLE %d из 50 за %.1f с" % [idle, dt2])
	verdict("C4 отряд у стены не просочился за границу", int(m["outside"]) == 0,
		"за краем %d" % int(m["outside"]))
	verdict("C5 отряд у стены не слипся в одну точку",
		float(m["nn_min"]) > 0.05 and float(m["w"]) * float(m["h"]) > 4.0,
		"пятно %.2f×%.2f м, минимальный зазор %.3f м" % [
			float(m["w"]), float(m["h"]), float(m["nn_min"])])

	# ── C6. ТОТ ЖЕ ОТРЯД ГОНИМ В СТЕНУ В ЛОБ, МИНУЯ ЗАЖИМ ПРИКАЗА ────────────
	for s3 in squad:
		var uu := s3 as Unit
		uu.move_target = Vector3(-main.MAP_HALF_X - 80.0, 0.0, -20.0)
		uu.state = Unit.State.MOVING
		uu._wake_process()
	var t3: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t3 < 12000:
		await get_tree().process_frame
	var m2 := _spread(squad)
	print("  тот же отряд 12 с давит в стену напрямую: за краем %d; пятно %.2f×%.2f м; минимальный зазор %.3f м; самый дальний x=%.3f" % [
		int(m2["outside"]), float(m2["w"]), float(m2["h"]), float(m2["nn_min"]),
		float(m2["min_x"])])
	verdict("C6 давление отряда в стену не выталкивает никого за край",
		int(m2["outside"]) == 0, "за краем %d, самый дальний x=%.3f" % [
			int(m2["outside"]), float(m2["min_x"])])
	verdict("C7 отряд, упёршийся в стену, не схлопывается в точку",
		float(m2["nn_min"]) > 0.05, "минимальный зазор %.3f м" % float(m2["nn_min"]))
	for s4 in squad:
		(s4 as Node).queue_free()
	await frames(4)

	# ── C8. ТОЛЧКИ В УГОЛ С ДВУХ СТОРОН ─────────────────────────────────────
	var victim := _spawn("spearman", Constants.FACTION_PLAYER, Vector3(lim - 0.4, 0.0, lim - 0.4))
	var bully  := _spawn("spearman", Constants.FACTION_ENEMY,  Vector3(lim - 2.0, 0.0, lim - 2.0))
	await frames(4)
	for i in range(400):
		bully._apply_push(victim, Vector3(1.0, 0.0, 0.0))
		bully._apply_push(victim, Vector3(0.0, 0.0, 1.0))
		bully._apply_push(victim, Vector3(0.7071, 0.0, 0.7071))
	var vp: Vector3 = victim.global_position
	var bp: Vector3 = bully.global_position
	print("  1200 толчков в угол: жертва (%.3f, %.3f), толкатель (%.3f, %.3f)" % [
		vp.x, vp.z, bp.x, bp.z])
	verdict("C8 толкание в угол не выдавливает ни жертву, ни толкателя",
		_finite3(vp) and _finite3(bp)
			and absf(vp.x) <= lim + 0.01 and absf(vp.z) <= lim + 0.01
			and absf(bp.x) <= lim + 0.01 and absf(bp.z) <= lim + 0.01,
		"жертва (%.3f, %.3f), толкатель (%.3f, %.3f)" % [vp.x, vp.z, bp.x, bp.z])
	victim.queue_free(); bully.queue_free()
	await frames(3)

	# ── C9. clamp_to_map: ИДЕМПОТЕНТНОСТЬ И УСТОЙЧИВОСТЬ ────────────────────
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var non_idem := 0
	var nanned := 0
	for _i in range(4000):
		var x: float = rng.randf_range(-500.0, 500.0)
		var z: float = rng.randf_range(-500.0, 500.0)
		var a: Vector2 = GameManager.clamp_to_map(x, z)
		var b: Vector2 = GameManager.clamp_to_map(a.x, a.y)
		if not (is_finite(a.x) and is_finite(a.y)):
			nanned += 1
		if absf(a.x - b.x) > 1e-6 or absf(a.y - b.y) > 1e-6:
			non_idem += 1
	var big: Vector2 = GameManager.clamp_to_map(1.0e30, -1.0e30)
	var inf_c: Vector2 = GameManager.clamp_to_map(INF, -INF)
	print("  4000 случайных зажимов: неидемпотентных %d, мусорных %d; 1e30 → (%.2f, %.2f); inf → (%.2f, %.2f)" % [
		non_idem, nanned, big.x, big.y, inf_c.x, inf_c.y])
	verdict("C9 clamp_to_map идемпотентен и не даёт мусора",
		non_idem == 0 and nanned == 0 and is_finite(big.x) and is_finite(inf_c.x),
		"неидемпотентных %d, мусорных %d" % [non_idem, nanned])

## Метрики разброса группы юнитов
func _spread(arr: Array) -> Dictionary:
	var lim: float = _lim()
	var minx := INF
	var maxx := -INF
	var minz := INF
	var maxz := -INF
	var outside := 0
	var pts: Array = []
	for a in arr:
		var n := a as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var p: Vector3 = n.global_position
		pts.append(Vector2(p.x, p.z))
		minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
		minz = minf(minz, p.z); maxz = maxf(maxz, p.z)
		if absf(p.x) > lim + 0.01 or absf(p.z) > lim + 0.01 or not _finite3(p):
			outside += 1
	var nn_min := INF
	var nn_sum := 0.0
	for i in range(pts.size()):
		var best := INF
		var pi: Vector2 = pts[i]
		for j in range(pts.size()):
			if i == j:
				continue
			var pj: Vector2 = pts[j]
			best = minf(best, pi.distance_to(pj))
		nn_sum += best
		nn_min = minf(nn_min, best)
	return {
		"outside": outside,
		"w": maxx - minx,
		"h": maxz - minz,
		"min_x": minx,
		"nn_min": nn_min,
		"nn_avg": nn_sum / maxf(float(pts.size()), 1.0),
	}

# ═════════════════════════════════════════════════════════════════════════════
# D. ИИ НА РАСШИРЕННОЙ КАРТЕ
# ═════════════════════════════════════════════════════════════════════════════
func _d_ai() -> void:
	print("\n═════ D. ИИ НА РАСШИРЕННОЙ КАРТЕ ═════")
	var lim: float = _lim()
	var legacy: float = float(main.MAP_HALF_EQUIV)

	# ── D1. ТОЧКА СБОРА БЕЗ ОЗЕРА ───────────────────────────────────────────
	var rp: Vector3 = main.ai_rally_point()
	var mid: Vector3 = (main.PLAYER_BASE_ANCHOR + main.ENEMY_BASE_ANCHOR) * 0.5
	print("  ai_rally_point() = (%.2f, %.2f); середина между базами (%.2f, %.2f); вода=%s" % [
		rp.x, rp.z, mid.x, mid.z, str(GameManager.is_water(rp.x, rp.z))])
	verdict("D1 точка сбора ИИ без озера лежит на суше внутри карты",
		_finite3(rp) and absf(rp.x) <= lim and absf(rp.z) <= lim
			and not GameManager.is_water(rp.x, rp.z),
		"(%.2f, %.2f)" % [rp.x, rp.z])
	verdict("D2 точка сбора ИИ — середина между базами, а не остаток от озера",
		absf(rp.x - mid.x) < 0.01 and absf(rp.z - mid.z) < 0.01,
		"(%.2f, %.2f) против (%.2f, %.2f)" % [rp.x, rp.z, mid.x, mid.z])

	# ── D2. ЗАМОК ИГРОКА, АРМИЯ ИИ, НАСТОЯЩИЕ ТАКТЫ ─────────────────────────
	var ai = main.enemy_ai
	var ecastle: Castle = null
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if b is Castle:
			ecastle = b as Castle
	var pcastle: Castle = null
	for b2 in get_tree().get_nodes_in_group("player_buildings"):
		if b2 is Castle:
			pcastle = b2 as Castle
	if pcastle == null:
		pcastle = Castle.new()
		pcastle.faction = Constants.FACTION_PLAYER
		main.world_add(pcastle)
		pcastle.global_position = main.PLAYER_BASE_ANCHOR
		await frames(3)
	print("  замок ИИ (%.1f, %.1f), замок игрока (%.1f, %.1f)" % [
		ecastle.global_position.x if ecastle != null else 0.0,
		ecastle.global_position.z if ecastle != null else 0.0,
		pcastle.global_position.x, pcastle.global_position.z])

	# Своя армия ИИ: по 12 бойцов трёх партий у базы
	var army: Array = []
	for i in range(36):
		var kind: String = "spearman" if i % 3 != 2 else "archer"
		var e := _spawn(kind, Constants.FACTION_ENEMY,
			(ecastle.global_position if ecastle != null else main.ENEMY_BASE_ANCHOR)
				+ Vector3(float(i % 6) * 0.8 - 2.4, 0.0, float(i / 6) * 0.8 - 2.4))
		army.append(e)
	await frames(6)
	ai._peace_over = true
	for _t in range(4):
		ai.tick()
		await frames(4)

	var pts: Array = []
	var far := 0.0
	var out_targets := 0
	for s in ai.squads:
		var sq: Dictionary = s
		var tg: Vector3 = sq["target"]
		pts.append(tg)
		far = maxf(far, maxf(absf(tg.x), absf(tg.z)))
		if absf(tg.x) > lim + 0.01 or absf(tg.z) > lim + 0.01 or not _finite3(tg):
			out_targets += 1
	print("  отрядов ИИ: %d; целей за краем: %d; самая дальняя цель на %.1f м от центра" % [
		ai.squads.size(), out_targets, far])
	verdict("D3 ИИ разложил отряды и ни одна цель не ушла за край",
		ai.squads.size() > 0 and out_targets == 0,
		"отрядов %d, за краем %d" % [ai.squads.size(), out_targets])

	# Рубеж, патрули и посты — в новых координатах
	var dc: Vector3 = ai._defense_center(ecastle)
	var gp_far := 0.0
	for i in range(6):
		var g: Vector3 = ai._guard_post(ecastle, i, 6)
		gp_far = maxf(gp_far, maxf(absf(g.x), absf(g.z)))
	var pp_far := 0.0
	var pp_out := 0
	for i in range(8):
		# Четвёртый аргумент — КУРС патруля (фронтовая дуга, добавлен вместе с
		# «патруль не уходит в тыловой лес»). Здесь проверяется только зажим
		# границ карты, поэтому курс берём к её середине
		var pp: Vector3 = ai._patrol_point(dc, i, 8, (Vector3.ZERO - dc).normalized())
		pp_far = maxf(pp_far, maxf(absf(pp.x), absf(pp.z)))
		if absf(pp.x) > lim + 0.01 or absf(pp.z) > lim + 0.01:
			pp_out += 1
	print("  рубеж обороны (%.1f, %.1f); посты гарнизона дотягиваются до %.1f м; патрули до %.1f м (за краем %d)" % [
		dc.x, dc.z, gp_far, pp_far, pp_out])
	verdict("D4 рубеж обороны ИИ внутри карты и на суше",
		absf(dc.x) <= lim and absf(dc.z) <= lim and not GameManager.is_water(dc.x, dc.z),
		"(%.1f, %.1f)" % [dc.x, dc.z])
	verdict("D5 патрульные точки ИИ не выходят за край", pp_out == 0,
		"за краем %d из 8" % pp_out)
	verdict("D6 ИИ реально работает на НОВОЙ площади (дальше прежней границы ±%.0f)" % legacy,
		gp_far > legacy, "посты дотягиваются до %.1f м" % gp_far)

	# ── D3. ЖИВОЙ ПРОГОН: НИ ОДИН БОЕЦ ИИ НЕ УШЁЛ ЗА КРАЙ ───────────────────
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
	var eout := 0
	var ebad := 0
	var etot := 0
	for e2 in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(e2):
			continue
		etot += 1
		var p: Vector3 = (e2 as Node3D).global_position
		if not _finite3(p):
			ebad += 1
		elif absf(p.x) > lim + 0.01 or absf(p.z) > lim + 0.01:
			eout += 1
	print("  12 с живого ИИ: бойцов %d, за краем %d, с мусорной позицией %d" % [etot, eout, ebad])
	verdict("D7 за 12 с живого ИИ ни один его боец не вышел за край",
		eout == 0 and ebad == 0, "за краем %d, мусорных %d из %d" % [eout, ebad, etot])

	for a in army:
		if is_instance_valid(a):
			(a as Node).queue_free()
	await frames(4)

# ═════════════════════════════════════════════════════════════════════════════
# E. ЖИЗНЬ БЕЗ ОЗЕРА: НЕ ВИСНЕТ ЛИ КОД ВОДЫ ВХОЛОСТУЮ
# ═════════════════════════════════════════════════════════════════════════════
func _e_no_lake() -> void:
	print("\n═════ E. ЖИЗНЬ БЕЗ ОЗЕРА ═════")
	var lim: float = _lim()

	# ── E1. nearest_land НЕ УХОДИТ В ПОИСК ──────────────────────────────────
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var moved := 0
	var t0: int = Time.get_ticks_usec()
	for _i in range(20000):
		var x: float = rng.randf_range(-lim, lim)
		var z: float = rng.randf_range(-lim, lim)
		var p: Vector2 = main.nearest_land(x, z)
		if absf(p.x - x) > 1e-4 or absf(p.y - z) > 1e-4:
			moved += 1
	var us1: int = Time.get_ticks_usec() - t0
	# Центр бывшего озера — самая опасная точка: раньше отсюда шёл поиск берега
	var lc: Vector2 = main.nearest_land(main.LAKE_CENTER.x, main.LAKE_CENTER.z)
	print("  20000 вызовов nearest_land за %.1f мс; сдвинуто точек %d; центр бывшего озера (%.2f, %.2f) → (%.2f, %.2f)" % [
		float(us1) / 1000.0, moved, main.LAKE_CENTER.x, main.LAKE_CENTER.z, lc.x, lc.y])
	_perf.append("nearest_land ×20000: %.1f мс" % (float(us1) / 1000.0))
	verdict("E1 nearest_land без озера возвращает ту же точку и не ищет берег",
		moved == 0 and absf(lc.x - main.LAKE_CENTER.x) < 1e-4
			and absf(lc.y - main.LAKE_CENTER.z) < 1e-4,
		"сдвинуто %d, центр озера → (%.2f, %.2f)" % [moved, lc.x, lc.y])

	# ── E2. slide_around_water ВОЗВРАЩАЕТ ШАГ КАК ЕСТЬ ──────────────────────
	var changed := 0
	var t1: int = Time.get_ticks_usec()
	for _i in range(20000):
		var from := Vector3(rng.randf_range(-lim, lim), 0.0, rng.randf_range(-lim, lim))
		var step := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		if _i % 500 == 0:
			step = Vector3.ZERO
		var got: Vector3 = main.slide_around_water(from, step)
		if not got.is_equal_approx(step):
			changed += 1
	var us2: int = Time.get_ticks_usec() - t1
	print("  20000 вызовов slide_around_water за %.1f мс; изменённых шагов %d (включая нулевые)" % [
		float(us2) / 1000.0, changed])
	_perf.append("slide_around_water ×20000: %.1f мс" % (float(us2) / 1000.0))
	verdict("E2 slide_around_water без озера отдаёт шаг без изменений и не виснет",
		changed == 0, "изменено %d из 20000" % changed)

	# ── E3. ВЫХОД ИЗ ГАРНИЗОНА У САМОГО КРАЯ ────────────────────────────────
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(lim - 5.0, 0.0, -lim + 5.0)
	await frames(4)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var members: Array = []
	for i in range(12):
		var s := _spawn("spearman", Constants.FACTION_PLAYER,
			castle.global_position + Vector3(float(i % 4) * 0.6 - 0.9, 0.0, 3.0 + float(i / 4) * 0.6))
		GameManager.add_to_squad(sid, s)
		members.append(s)
	await frames(4)
	var entered: bool = castle.request_garrison(sid)
	var t2: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 15000:
		await get_tree().process_frame
		var inside := 0
		for mm in members:
			if is_instance_valid(mm) and (mm as Unit).garrisoned:
				inside += 1
		if inside == members.size():
			break
	var in_cnt := 0
	for mm2 in members:
		if is_instance_valid(mm2) and (mm2 as Unit).garrisoned:
			in_cnt += 1
	print("  гарнизон у края: запрос=%s, внутри %d из %d" % [str(entered), in_cnt, members.size()])
	var released: bool = castle.release_garrison(sid)
	await frames(10)
	var bad_out := 0
	var still_in := 0
	for mm3 in members:
		if not is_instance_valid(mm3):
			continue
		var uu := mm3 as Unit
		if uu.garrisoned:
			still_in += 1
			continue
		var p2: Vector3 = uu.global_position
		if not _finite3(p2) or absf(p2.x) > lim + 0.01 or absf(p2.z) > lim + 0.01:
			bad_out += 1
	print("  выпуск гарнизона: released=%s, осталось внутри %d, вышло за край %d" % [
		str(released), still_in, bad_out])
	verdict("E3 выход из гарнизона у края ставит всех на сушу внутри карты",
		in_cnt > 0 and released and bad_out == 0 and still_in == 0,
		"внутри %d, за краем %d, не вышло %d" % [in_cnt, bad_out, still_in])

	# Дошли ли выпущенные до места (приказ у стены не должен зависнуть)
	var t3: int = Time.get_ticks_msec()
	var idle3 := 0
	while Time.get_ticks_msec() - t3 < 25000:
		await get_tree().process_frame
		idle3 = 0
		for mm4 in members:
			if is_instance_valid(mm4) and (mm4 as Unit).state == Unit.State.IDLE:
				idle3 += 1
		if idle3 == members.size():
			break
	print("  выпущенные бойцы у стены: в IDLE %d из %d за %.1f с" % [
		idle3, members.size(), float(Time.get_ticks_msec() - t3) / 1000.0])
	verdict("E4 выпущенный у стены гарнизон доходит и встаёт, а не топчется",
		idle3 == members.size(), "в IDLE %d из %d" % [idle3, members.size()])
	for mm5 in members:
		if is_instance_valid(mm5):
			(mm5 as Node).queue_free()
	await frames(3)

	# ── E5. ПОЛНЫЙ ЦИКЛ РАБОЧЕГО ЧЕРЕЗ БЫВШЕЕ ОЗЕРО ─────────────────────────
	# Склад с одной стороны бывшего озера, дерево — с другой: путь с грузом
	# идёт РОВНО через центр воды. Раньше здесь работал обход берега
	var lake_c: Vector3 = main.LAKE_CENTER
	castle.global_position = lake_c + Vector3(-16.0, 0.0, -10.0)
	await frames(4)
	var tree := ResourceNode.new()
	tree.resource_type = Constants.RESOURCE_WOOD
	main.world_add(tree)
	tree.global_position = lake_c + Vector3(16.0, 0.0, 10.0)
	tree.remaining = 500.0
	await frames(4)
	var wood0: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD)
	var w := _spawn("worker", Constants.FACTION_PLAYER, castle.global_position + Vector3(2.0, 0.0, 2.0))
	await frames(4)
	w.command_gather(tree)
	var t4: int = Time.get_ticks_msec()
	var delivered := false
	var seen_return := false
	while Time.get_ticks_msec() - t4 < 60000:
		await get_tree().process_frame
		if w.state == Unit.State.RETURNING:
			seen_return = true
		if ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD) > wood0 + 0.5:
			delivered = true
			break
	var wood1: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD)
	print("  рабочий через центр бывшего озера: доставил=%s (было %.0f, стало %.0f) за %.1f с, фаза возврата видена=%s" % [
		str(delivered), wood0, wood1, float(Time.get_ticks_msec() - t4) / 1000.0, str(seen_return)])
	verdict("E5 полный цикл рабочего через бывшее озеро завершается доставкой",
		delivered and seen_return,
		"доставлено=%s, возврат=%s, дерево %.0f" % [str(delivered), str(seen_return), tree.remaining])
	verdict("E6 рабочий не застрял в бывшем озере",
		_finite3(w.global_position) and absf(w.global_position.x) <= lim
			and absf(w.global_position.z) <= lim,
		str(w.global_position))

	w.queue_free(); tree.queue_free(); castle.queue_free()
	await frames(4)

	# ── E7. ТОЧКА СБОРА ЗДАНИЯ, НАЗНАЧЕННАЯ ЗА КАРТОЙ ───────────────────────
	var b2 := Barracks.new()
	b2.faction = Constants.FACTION_PLAYER
	main.world_add(b2)
	b2.global_position = Vector3(-40.0, 0.0, 0.0)
	await frames(4)
	b2.set_rally_point(Vector3(-main.MAP_HALF_X - 200.0, 0.0, main.MAP_HALF_X + 200.0))
	var rp2: Vector3 = b2.rally_point
	print("  точка сбора здания, назначенная за картой: (%.1f, %.1f); предел ±%.1f" % [
		rp2.x, rp2.z, lim])
	verdict("E7 точка сбора здания зажимается в границы карты",
		absf(rp2.x) <= lim + 0.01 and absf(rp2.z) <= lim + 0.01,
		"(%.1f, %.1f)" % [rp2.x, rp2.z])
	b2.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# F. ЦЕНА ЗАЖИМА ГРАНИЦ В ГОРЯЧИХ ПУТЯХ
# _move_blocked зовёт GameManager.clamp_to_map() на каждый шаг каждого юнита.
# Меряем разницу кадра при включённом и выключенном зажиме.
# ═════════════════════════════════════════════════════════════════════════════
func _f_perf() -> void:
	print("\n═════ F. ЦЕНА ЗАЖИМА ГРАНИЦ ═════")
	# Чистим поле от чужих бойцов, чтобы мерить только свою нагрузку
	for e in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(e):
			(e as Node).queue_free()
	await frames(6)

	var n := 1000
	var host: Array = []
	for i in range(n):
		var col: int = i % 40
		var row: int = i / 40
		var u := _spawn("spearman", Constants.FACTION_PLAYER,
			Vector3(-30.0 + float(col) * 0.7, 0.0, -30.0 + float(row) * 0.7))
		host.append(u)
	await frames(10)
	# Марш через полкарты: _move_blocked работает вовсю на каждом шаге
	for u2 in host:
		(u2 as Unit).command_move(Vector3(60.0, 0.0, 60.0))

	# ХОЛОСТОЙ ПРОГРЕВОЧНЫЙ ЗАМЕР: первое окно после спавна ловит разбор
	# спрайтлистов и завышает цифру в сто раз — его результат ВЫБРАСЫВАЕТСЯ
	var warm: float = await _measure(120)
	print("  прогрев (выбрасывается): %.3f мс/кадр" % warm)

	# ОКНА ЧЕРЕДУЮТСЯ. Один замер ВКЛ и один ВЫКЛ подряд ловят дрейф машины
	# (в первом прогоне два окна с ОДИНАКОВЫМИ условиями разошлись на 14%).
	# Четыре пары вперемешку разводят дрейф поровну между режимами
	var on_runs: Array[float] = []
	var off_runs: Array[float] = []
	for r in range(5):
		GameManager.world_bounds_enabled = true
		var a: float = await _measure(120)
		GameManager.world_bounds_enabled = false
		var b: float = await _measure(120)
		# ПЕРВАЯ ПАРА — ТОЖЕ ПРОГРЕВ и тоже выбрасывается: сразу после
		# основного прогрева окно ещё ловит хвост раскладки строя (замер:
		# 22.3 мс против 17.2 в соседних окнах того же режима)
		if r == 0:
			print("  первая пара (выбрасывается): ВКЛ %.3f, ВЫКЛ %.3f мс/кадр" % [a, b])
			continue
		on_runs.append(a)
		off_runs.append(b)
	GameManager.world_bounds_enabled = true

	var alive := 0
	for u3 in host:
		if is_instance_valid(u3):
			alive += 1
	var with_b: float = _median(on_runs)
	var without_b: float = _median(off_runs)
	var delta_ms: float = with_b - without_b
	var pct: float = 100.0 * delta_ms / maxf(without_b, 0.0001)
	var per_unit: float = delta_ms * 1000.0 / maxf(float(alive), 1.0)
	print("  %d бойцов на марше, 4 зачётные пары окон по 120 физических кадров:" % alive)
	print("    зажим ВКЛ  : медиана %.3f мс/кадр, окна %s" % [with_b, _fmt(on_runs)])
	print("    зажим ВЫКЛ : медиана %.3f мс/кадр, окна %s" % [without_b, _fmt(off_runs)])
	print("    разница    : %+.3f мс/кадр (%+.1f%%), на бойца %+.4f мкс/кадр" % [
		delta_ms, pct, per_unit])
	_perf.append("%d бойцов: зажим ВКЛ %.3f мс, ВЫКЛ %.3f мс, разница %+.3f мс (%+.1f%%, %+.3f мкс на бойца)" % [
		alive, with_b, without_b, delta_ms, pct, per_unit])
	# Бюджет задан в АБСОЛЮТЕ на бойца: именно он определяет потолок при
	# движении к цели «10 000 юнитов», а процент от кадра зависит от того,
	# что ещё крутится в сцене
	verdict("F1 зажим границ стоит меньше 2 мкс на бойца в кадр", per_unit < 2.0,
		"%+.3f мкс на бойца (%+.3f мс на %d, %+.1f%%)" % [per_unit, delta_ms, alive, pct])
	# УРОВЕНЬ ШУМА — разброс окон ОДНОГО режима: меньше него замер не различает
	# ничего в принципе. Требовать «окна сходятся» бессмысленно (машина плавает
	# на 20–25%), а вот «разница между режимами не выходит за шум» — это ровно
	# тот вывод, ради которого замер и делается
	var noise_ms: float = maxf(
		with_b * _spread_pct(on_runs) * 0.01, without_b * _spread_pct(off_runs) * 0.01)
	print("    уровень шума: %.3f мс/кадр (разброс окон ВКЛ %.1f%%, ВЫКЛ %.1f%%)" % [
		noise_ms, _spread_pct(on_runs), _spread_pct(off_runs)])
	_perf.append("уровень шума замера: %.3f мс/кадр" % noise_ms)
	verdict("F2 подорожание кадра от зажима не выходит за уровень шума замера",
		delta_ms <= noise_ms,
		"разница %+.3f мс при шуме %.3f мс" % [delta_ms, noise_ms])

	for u4 in host:
		if is_instance_valid(u4):
			(u4 as Node).queue_free()
	await frames(5)

func _median(arr: Array[float]) -> float:
	var c: Array[float] = arr.duplicate()
	c.sort()
	if c.is_empty():
		return 0.0
	if c.size() % 2 == 1:
		return c[c.size() / 2]
	return (c[c.size() / 2 - 1] + c[c.size() / 2]) * 0.5

## Разброс окон в процентах от медианы
func _spread_pct(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var lo := INF
	var hi := -INF
	for v in arr:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return 100.0 * (hi - lo) / maxf(_median(arr), 0.0001)

func _fmt(arr: Array[float]) -> String:
	var parts: Array = []
	for v in arr:
		parts.append("%.3f" % v)
	return "[" + ", ".join(parts) + "]"

## Среднее время физического кадра за n кадров, мс
func _measure(n: int) -> float:
	var acc := 0.0
	var cnt := 0
	for _i in range(n):
		await get_tree().physics_frame
		acc += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		cnt += 1
	return (acc / maxf(float(cnt), 1.0)) * 1000.0
