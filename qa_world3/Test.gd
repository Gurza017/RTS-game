extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_world3 — ДЫРЫ, НЕ ЗАКРЫТЫЕ СТЕНДАМИ qa_world И qa_world2
## ═══════════════════════════════════════════════════════════════════════════
## qa_world  проверяет «что построено» (константы, размеры мешей, один боец).
## qa_world2 проверяет «что происходит при вводе» (стресс камеры, клики, ИИ).
## Оба меряют границы ОДНИМ числом MAP_HALF_X — по короткой оси Z их проверки
## заведомо зелёные и дыры там не видят. Здесь всё разведено по осям, и
## добавлено то, чего нет ни там ни там:
##
##   Г РАКУРС     — 45° считается ПО МИРОВОЙ МАТРИЦЕ камеры в 54 положениях,
##                  а не по переменной _orbit_pitch; вместе с ним — вынос,
##                  вектор «вверх», лучи верхней и нижней кромки кадра и
##                  сквозная проверка «под центром экрана лежит фокус»
##   З ЗУМ        — новый потолок 40 м: плавный проезд зума кадр за кадром,
##                  разные пределы фокуса ПО ОСЯМ, положение камеры на полу
##                  и потолке зума в углу карты
##   П ФОРМА      — прямоугольность НЕ на словах: заполнение обеих осей до
##                  края, полосы-гистограммы, обитаемость всех 4 углов,
##                  лесные подковы баз, кусты, облака, размеры стен
##   С СПАУНЫ     — живой поток постановки замка игрока (не только функция
##                  clamp_to_player_start), стартовые рабочие обеих сторон,
##                  призрак замка, попытки поставить замок в угол ИИ и за край
##   М МАРШ       — диагональ во всю карту (~233 м) в обе стороны и живой
##                  ИИ, идущий из своего угла к игроку через центр
##
## Границы мира НЕ отключаются: вся площадка стенда лежит внутри карты.

var main = null
var cam: RTSCamera = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _notes: Array = []

## Снимок стартового состояния ИИ, снятый ДО того, как стенд что-либо трогает
var _ai_snap: Dictionary = {}

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

## Предел хождения юнита по КАЖДОЙ оси
func _lim_x() -> float:
	return float(main.MAP_HALF_X) - float(main.MAP_EDGE_MARGIN)

func _lim_z() -> float:
	return float(main.MAP_HALF_Z) - float(main.MAP_EDGE_MARGIN)

## Ставит камеру и ПЕРЕСОБИРАЕТ трансформ вручную: писать global_position
## бесполезно, _process всё равно соберёт его заново из _focus/_height
func look(fx: float, fz: float, h: float) -> void:
	cam._focus = Vector3(
		clampf(fx, cam.bounds_min.x, cam.bounds_max.x), 0.0,
		clampf(fz, cam.bounds_min.y, cam.bounds_max.y))
	cam._target_height = h
	cam._height = h
	cam._update_position()

## Фактический наклон взгляда, градусы НИЖЕ горизонта, ПО МИРОВОЙ МАТРИЦЕ
func real_pitch() -> float:
	var fwd: Vector3 = -cam.global_transform.basis.z
	return rad_to_deg(asin(clampf(-fwd.y, -1.0, 1.0)))

func real_yaw() -> float:
	var fwd: Vector3 = -cam.global_transform.basis.z
	return rad_to_deg(atan2(-fwd.x, -fwd.z))

## Точка земли (y=0) под экранной точкой, аналитически по лучу
func ground_under(screen: Vector2) -> Vector3:
	var from: Vector3 = cam.project_ray_origin(screen)
	var dirn: Vector3 = cam.project_ray_normal(screen)
	if dirn.y >= -1e-6:
		return Vector3(INF, 0.0, INF)
	var t: float = -from.y / dirn.y
	if t <= 0.0:
		return Vector3(INF, 0.0, INF)
	var p: Vector3 = from + dirn * t
	return Vector3(p.x, 0.0, p.z)

## Угол луча экранной точки НИЖЕ горизонта, градусы (отрицательный — выше)
func ray_pitch(screen: Vector2) -> float:
	var dirn: Vector3 = cam.project_ray_normal(screen)
	return rad_to_deg(asin(clampf(-dirn.y, -1.0, 1.0)))

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	cam = main._camera

	# СНИМОК СТАРТА ИИ снимается ПЕРВЫМ делом: дальше стенд ставит замки,
	# чистит ресурсы и гоняет отряды — рабочие ИИ успеют разбрестись
	_snapshot_ai_start()

	# Скролл краем экрана в headless работает всё время (курсор висит в 0,0) и
	# незаметно уводит фокус между вызовом look() и замером. Для геометрии это
	# смертельно, поэтому панораму глушим: её пределы и так проверяет qa_world2
	cam.pan_speed = 0.0
	cam.edge_pan_margin = 0.0

	print("карта %.1f × %.1f м; пределы юнитов ±%.2f / ±%.2f; фокус камеры ±%.1f / ±%.1f" % [
		main.MAP_HALF_X * 2.0, main.MAP_HALF_Z * 2.0,
		_lim_x(), _lim_z(), main.CAM_BOUND_X, main.CAM_BOUND_Z])

	await _g_angle()
	await _z_zoom()
	await _p_shape()
	await _s_spawns()
	await _m_march()

	print("\n═════ ИТОГ qa_world3 ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 66), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	if not _notes.is_empty():
		print("\n───── ЗАМЕТКИ ─────")
		for n in _notes:
			print("  %s" % String(n))
	print("\n=== WORLD3 TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# Г. ГЕОМЕТРИЯ РАКУРСА: 45° ПО МИРОВОЙ МАТРИЦЕ, А НЕ ПО ПЕРЕМЕННОЙ
# _orbit_pitch — обычная переменная, и она врёт, если сломан расчёт положения
# (_update_position, пивот, look_at). Здесь всё считается из global_transform.
# ═════════════════════════════════════════════════════════════════════════════
func _g_angle() -> void:
	print("\n═════ Г. ГЕОМЕТРИЯ РАКУРСА ═════")

	# Проекция камеры печатается в отчёт: стенд СПЕЦИАЛЬНО не завязан на неё.
	# 0 = перспектива, 1 = ортография. Ракурс, пределы зума и вся геометрия
	# ниже проверяются через МИРОВУЮ МАТРИЦУ и ЛУЧИ, поэтому смена проекции
	# стенд не ломает — и наоборот, любой срыв ракурса будет виден при любой
	var proj: String = "ортография" if cam.projection == Camera3D.PROJECTION_ORTHOGONAL \
		else "перспектива"
	print("  проекция: %s; зум %.1f .. %.1f (%s)" % [proj, cam.min_height, cam.max_height,
		"метров видимой высоты кадра" if cam.projection == Camera3D.PROJECTION_ORTHOGONAL
			else "метров подвеса камеры"])
	_notes.append("проекция камеры: %s, зум %.1f..%.1f" % [proj, cam.min_height, cam.max_height])

	verdict("Г1 наклон прибит к 45° (было 60°, ракурс изменён намеренно)",
		absf(RTSCamera.FIXED_PITCH - 45.0) < 0.001,
		"FIXED_PITCH = %.2f" % RTSCamera.FIXED_PITCH)
	verdict("Г2 пределы зума заданы в правильном порядке и не выродились",
		cam.min_height > 0.0 and cam.max_height > cam.min_height * 1.5,
		"%.1f .. %.1f" % [cam.min_height, cam.max_height])

	# ── СВОДКА ПО 54 ПОЛОЖЕНИЯМ ─────────────────────────────────────────────
	# Высоты берутся ИЗ ТЕКУЩИХ пределов зума, а не литералами: пределы за
	# время работы стенда уже менялись (8..40 → 24..110)
	var hs: Array[float] = []
	for i in range(6):
		hs.append(lerpf(cam.min_height, cam.max_height, float(i) / 5.0))
	var fs: Array = [
		Vector2(0.0, 0.0),
		Vector2(main.CAM_BOUND_X, main.CAM_BOUND_Z),
		Vector2(-main.CAM_BOUND_X, -main.CAM_BOUND_Z),
		Vector2(main.CAM_BOUND_X, -main.CAM_BOUND_Z),
		Vector2(-main.CAM_BOUND_X, main.CAM_BOUND_Z),
		Vector2(main.CAM_BOUND_X, 0.0),
		Vector2(-main.CAM_BOUND_X, 0.0),
		Vector2(0.0, main.CAM_BOUND_Z),
		Vector2(0.0, -main.CAM_BOUND_Z),
	]
	var worst_pitch := 0.0
	var worst_yaw   := 0.0
	var bad_up      := 0
	var bad_high    := 0
	var worst_reach := 0.0
	var bad_dir     := 0
	var worst_center := 0.0
	var samples     := 0
	for h in hs:
		for f in fs:
			var fv: Vector2 = f
			look(fv.x, fv.y, h)
			samples += 1
			worst_pitch = maxf(worst_pitch, absf(real_pitch() - RTSCamera.FIXED_PITCH))
			worst_yaw   = maxf(worst_yaw, absf(real_yaw()))
			var up: Vector3 = cam.global_transform.basis.y
			if up.y <= 0.5:
				bad_up += 1
			var cp: Vector3 = cam.global_position
			# Камера обязана висеть НАД землёй, а фокус — лежать ровно на её
			# луче взгляда. Так проверка не зависит от того, чем задан масштаб:
			# высотой подвеса (перспектива) или размером кадра (ортография)
			var to_focus: Vector3 = (cam._focus - cp)
			var fwd2: Vector3 = -cam.global_transform.basis.z
			if not _finite3(cp) or cp.y <= 0.0 \
					or to_focus.normalized().distance_to(fwd2) > 0.001:
				bad_high += 1
			# При 45° ПОДЪЁМ камеры над фокусом равен её горизонтальному выносу,
			# и вынос направлен строго назад по +Z. Верно для обеих проекций
			var dx: float = cp.x - cam._focus.x
			var dz: float = cp.z - cam._focus.z
			worst_reach = maxf(worst_reach, absf(sqrt(dx * dx + dz * dz) - cp.y))
			if absf(dx) > 0.001 or dz <= 0.0:
				bad_dir += 1
			# Сквозная проверка всей цепочки: под центром экрана обязан лежать фокус
			var g: Vector3 = ground_under(Vector2(640.0, 360.0))
			if _finite3(g):
				worst_center = maxf(worst_center,
					Vector2(g.x - cam._focus.x, g.z - cam._focus.z).length())
			else:
				worst_center = INF
	print("  %d положений (6 ступеней зума × 9 точек фокуса, включая все 4 угла):" % samples)
	print("    худшее отклонение наклона %.6f°, азимута %.6f°" % [worst_pitch, worst_yaw])
	print("    перевёрнутых кадров %d, камер не на луче собственного взгляда %d" % [
		bad_up, bad_high])
	print("    худший разбег «подъём против выноса» %.6f м, неверных направлений выноса %d" % [
		worst_reach, bad_dir])
	print("    худшее расхождение «земля под центром экрана» и фокуса: %.6f м" % worst_center)

	verdict("Г3 наклон по МИРОВОЙ МАТРИЦЕ ровно 45° во всех 54 положениях",
		worst_pitch < 0.01, "худшее отклонение %.6f°" % worst_pitch)
	verdict("Г4 азимут по матрице ровно 0° (мир не развернулся)",
		worst_yaw < 0.01, "худшее отклонение %.6f°" % worst_yaw)
	verdict("Г5 камера ни в одном положении не перевёрнута", bad_up == 0,
		"перевёрнутых %d из %d" % [bad_up, samples])
	verdict("Г6 камера всегда над землёй, и фокус лежит ровно на её луче взгляда",
		bad_high == 0, "сбоев %d из %d" % [bad_high, samples])
	verdict("Г7 подъём камеры равен её горизонтальному выносу назад по +Z (следствие 45°)",
		worst_reach < 0.001 and bad_dir == 0,
		"разбег %.6f м, неверных направлений %d" % [worst_reach, bad_dir])
	verdict("Г8 под центром экрана лежит ровно точка фокуса",
		worst_center < 0.02, "худшее расхождение %.6f м" % worst_center)

	# ── ЛУЧИ ВЕРХНЕЙ И НИЖНЕЙ КРОМКИ КАДРА ──────────────────────────────────
	# В перспективе верхний луч отклоняется от центрального на половину угла
	# обзора (при 45° и fov 75° это 7.5° ниже горизонта), в ортографии все лучи
	# параллельны и идут ровно под 45°. В обоих случаях требование одно: верхний
	# луч НЕ ВЫШЕ горизонта (иначе земля уходит в бесконечность и в кадр лезет
	# небо), а нижний не заваливается за вертикаль
	var mid_h: float = (cam.min_height + cam.max_height) * 0.5
	look(0.0, 0.0, mid_h)
	var top: float = ray_pitch(Vector2(640.0, 1.0))
	var bot: float = ray_pitch(Vector2(640.0, 719.0))
	print("  лучи кадра: верхний %.2f° ниже горизонта, нижний %.2f° (проекция: %s)" % [
		top, bot, proj])
	_notes.append("верхний луч кадра: %.2f° ниже горизонта" % top)
	verdict("Г9 верхний луч кадра остаётся НИЖЕ горизонта (неба в кадре нет)",
		top > 0.5, "верхний луч %.2f°" % top)
	verdict("Г10 нижний луч кадра не заваливается за вертикаль",
		bot < 89.0 and bot >= 45.0 - 0.01, "нижний луч %.2f°" % bot)

	# ── СКОЛЬКО КАДРА ЗАНИМАЕТ ПОЛЕ НА ПОТОЛКЕ ЗУМА ─────────────────────────
	# Ради этого потолок и снижали с 60 до 40: с 60 м поле читалось «зелёной
	# плитой в черноте». Меряем долю центральной вертикали кадра, под которой
	# лежит игровое поле
	look(0.0, 0.0, cam.max_height)
	var inside := 0
	for i in range(101):
		var g2: Vector3 = ground_under(Vector2(640.0, 7.2 * float(i)))
		if _finite3(g2) and absf(g2.x) <= main.MAP_HALF_X and absf(g2.z) <= main.MAP_HALF_Z:
			inside += 1
	var share: float = float(inside) / 101.0
	print("  на потолке зума над центром поле занимает %.0f%% центральной вертикали кадра" % [
		share * 100.0])
	_notes.append("доля кадра под полем на потолке зума: %.0f%%" % (share * 100.0))
	verdict("Г11 на потолке зума карта занимает больше 2/3 кадра, а не тонет в черноте",
		share > 0.67, "поле занимает %.0f%% кадра" % (share * 100.0))

	# ── Г12а. САМОЕ НЕВЫГОДНОЕ ПОЛОЖЕНИЕ: ПОТОЛОК ЗУМА У КОРОТКОЙ КРОМКИ ─────
	# Камера смотрит ВДОЛЬ оси Z, а короткая сторона карты — тоже Z. Значит
	# худший кадр в игре — предельное отдаление с фокусом, упёртым в северную
	# кромку: за ней сразу чернота. Проверка центра карты (Г11) этот случай
	# не ловит вовсе, а игрок в него попадает одним движением мыши
	look(0.0, -main.CAM_BOUND_Z, cam.max_height)
	var inside2 := 0
	for i2 in range(101):
		var g3: Vector3 = ground_under(Vector2(640.0, 7.2 * float(i2)))
		if _finite3(g3) and absf(g3.x) <= main.MAP_HALF_X and absf(g3.z) <= main.MAP_HALF_Z:
			inside2 += 1
	var share_edge: float = float(inside2) / 101.0
	print("  худший кадр (потолок зума у короткой кромки): поле занимает %.0f%% вертикали" % [
		share_edge * 100.0])
	_notes.append("худший кадр (потолок зума у короткой кромки): поле занимает %.0f%% вертикали" % [
		share_edge * 100.0])
	verdict("Г12 даже в худшем кадре (потолок зума у короткой кромки) поле занимает больше половины",
		share_edge > 0.5, "поле занимает %.0f%% кадра" % (share_edge * 100.0))

	# ── Г13. ЗУМ ДЕЙСТВИТЕЛЬНО МЕНЯЕТ МАСШТАБ ───────────────────────────────
	# Меряем не переменную, а КУСОК МИРА В КАДРЕ: сколько метров земли влезает
	# по вертикали и горизонтали на обоих упорах зума
	var spans: Array[float] = []
	for h2 in [cam.min_height, cam.max_height]:
		look(0.0, 0.0, float(h2))
		var g_top: Vector3 = ground_under(Vector2(640.0, 1.0))
		var g_bot2: Vector3 = ground_under(Vector2(640.0, 719.0))
		var g_l: Vector3 = ground_under(Vector2(1.0, 360.0))
		var g_r: Vector3 = ground_under(Vector2(1279.0, 360.0))
		var depth: float = absf(g_top.z - g_bot2.z) if _finite3(g_top) and _finite3(g_bot2) else INF
		var width: float = absf(g_r.x - g_l.x) if _finite3(g_l) and _finite3(g_r) else INF
		spans.append(depth)
		spans.append(width)
		print("  зум %.1f: в кадр влезает %.1f м земли вглубь и %.1f м вширь" % [
			float(h2), depth, width])
	_notes.append("охват кадра: вблизи %.0f×%.0f м, вдали %.0f×%.0f м земли" % [
		spans[1], spans[0], spans[3], spans[2]])
	verdict("Г13 зум реально меняет охват кадра, и дальний упор шире ближнего",
		is_finite(spans[0]) and is_finite(spans[2]) and spans[2] > spans[0] * 1.5
			and spans[3] > spans[1] * 1.5,
		"вглубь %.1f → %.1f м, вширь %.1f → %.1f м" % [spans[0], spans[2], spans[1], spans[3]])

# ═════════════════════════════════════════════════════════════════════════════
# З. ЗУМ И ГРАНИЦЫ ФОКУСА
# ═════════════════════════════════════════════════════════════════════════════
func _z_zoom() -> void:
	print("\n═════ З. ЗУМ И ГРАНИЦЫ ФОКУСА ═════")

	# ── З1. ПРЕДЕЛЫ ФОКУСА РАЗНЫЕ ПО ОСЯМ ───────────────────────────────────
	print("  bounds камеры: min (%.3f, %.3f), max (%.3f, %.3f)" % [
		cam.bounds_min.x, cam.bounds_min.y, cam.bounds_max.x, cam.bounds_max.y])
	verdict("З1 пределы фокуса разведены по осям (не квадрат)",
		absf(cam.bounds_max.x - main.CAM_BOUND_X) < 0.001
			and absf(cam.bounds_max.y - main.CAM_BOUND_Z) < 0.001
			and absf(cam.bounds_max.x - cam.bounds_max.y) > 1.0,
		"(%.3f, %.3f) при ожидаемых (%.3f, %.3f)" % [
			cam.bounds_max.x, cam.bounds_max.y, main.CAM_BOUND_X, main.CAM_BOUND_Z])

	cam.pan_to(Vector3(9999.0, 0.0, 9999.0))
	var pz: float = cam._focus.z
	cam.pan_to(Vector3(-9999.0, 0.0, -9999.0))
	var nz: float = cam._focus.z
	print("  увод фокуса по КОРОТКОЙ оси: +∞ → %.3f, −∞ → %.3f (ждали ±%.3f, НЕ ±%.3f)" % [
		pz, nz, main.CAM_BOUND_Z, main.CAM_BOUND_X])
	verdict("З2 по короткой оси фокус упирается в CAM_BOUND_Z, а не в CAM_BOUND_X",
		absf(pz - main.CAM_BOUND_Z) < 0.001 and absf(nz + main.CAM_BOUND_Z) < 0.001,
		"+%.3f / %.3f" % [pz, nz])

	# ── З3. ПРОЕЗД ЗУМА КАДР ЗА КАДРОМ ──────────────────────────────────────
	# Высота идёт к цели через lerp в _process. Проверяем КАЖДЫЙ кадр проезда:
	# ни выброса за пределы, ни провала под землю, ни срыва ракурса
	cam.pan_to(Vector3(0.0, 0.0, 0.0))
	cam._height = cam.max_height
	cam._target_height = cam.min_height
	var out_range := 0
	var under := 0
	var tilt := 0
	var flip := 0
	var prev: float = cam._height
	var rising := 0
	for _i in range(180):
		await get_tree().process_frame
		var h: float = cam._height
		if h < cam.min_height - 0.001 or h > cam.max_height + 0.001:
			out_range += 1
		if cam.global_position.y <= 0.5 or not _finite3(cam.global_position):
			under += 1
		if absf(real_pitch() - RTSCamera.FIXED_PITCH) > 0.01:
			tilt += 1
		if cam.global_transform.basis.y.y <= 0.5:
			flip += 1
		if h > prev + 0.0001:
			rising += 1
		prev = h
	print("  проезд зума %.0f→%.0f за 180 кадров: выходов за пределы %d, провалов под землю %d," % [
		cam.max_height, cam.min_height, out_range, under])
	print("    срывов наклона %d, переворотов %d, кадров с ростом высоты %d; итог %.3f м" % [
		tilt, flip, rising, cam._height])
	verdict("З3 при наезде зума высота ни разу не вышла за min..max", out_range == 0,
		"выходов %d" % out_range)
	verdict("З4 при наезде зума камера ни разу не провалилась под землю", under == 0,
		"провалов %d" % under)
	verdict("З5 при наезде зума ракурс не сорвался и камера не перевернулась",
		tilt == 0 and flip == 0, "срывов наклона %d, переворотов %d" % [tilt, flip])
	verdict("З6 наезд зума монотонный, без отскоков вверх", rising == 0,
		"кадров с ростом %d" % rising)

	# ── З7. ЗУМ НЕ УВОДИТ ТОЧКУ ПОД ЦЕНТРОМ ЭКРАНА ──────────────────────────
	look(-40.0, 25.0, cam.min_height)
	var g_min: Vector3 = ground_under(Vector2(640.0, 360.0))
	look(-40.0, 25.0, cam.max_height)
	var g_max: Vector3 = ground_under(Vector2(640.0, 360.0))
	var drift: float = Vector2(g_min.x - g_max.x, g_min.z - g_max.z).length()
	print("  точка под центром экрана: на полу зума (%.3f, %.3f), на потолке (%.3f, %.3f), разбег %.4f м" % [
		g_min.x, g_min.z, g_max.x, g_max.z, drift])
	verdict("З7 зум не сдвигает точку, лежащую под центром экрана", drift < 0.02,
		"разбег %.4f м" % drift)

	# ── З8. ПОТОЛОК ЗУМА В УГЛУ КАРТЫ ───────────────────────────────────────
	# Фокус в углу, камера при этом физически уезжает ЗА край поля по +Z
	# (фокус 61.1 + вынос 40 = 101 при полуоси 73). Проверяем, что она всё
	# равно висит над миром, а центр экрана остаётся на карте
	look(main.CAM_BOUND_X, main.CAM_BOUND_Z, cam.max_height)
	var cp: Vector3 = cam.global_position
	var gc: Vector3 = ground_under(Vector2(640.0, 360.0))
	print("  потолок зума в углу: камера (%.1f, %.1f, %.1f), под центром экрана (%.1f, %.1f)" % [
		cp.x, cp.y, cp.z, gc.x, gc.z])
	verdict("З8 на потолке зума в углу камера цела, а центр экрана — внутри карты",
		_finite3(cp) and cp.y > 0.0 and _finite3(gc)
			and absf(gc.x) <= main.MAP_HALF_X and absf(gc.z) <= main.MAP_HALF_Z,
		"камера %s, центр экрана (%.1f, %.1f)" % [str(cp), gc.x, gc.z])

	# ── З9. ПОЛ ЗУМА: НИЖНЯЯ КРОМКА КАДРА ЛОЖИТСЯ НА ЗЕМЛЮ ──────────────────
	# Расстояние меряется ОТ ФОКУСА, а не от камеры: в ортографии камера унесена
	# на постоянные 400 м и её удаление к масштабу отношения не имеет
	look(0.0, 0.0, cam.min_height)
	var g_bot: Vector3 = ground_under(Vector2(640.0, 719.0))
	var near_d: float = Vector2(g_bot.x - cam._focus.x, g_bot.z - cam._focus.z).length()
	print("  пол зума: ближняя кромка кадра на земле в (%.2f, %.2f), в %.2f м от фокуса" % [
		g_bot.x, g_bot.z, near_d])
	verdict("З9 на полу зума нижняя кромка кадра лежит на земле перед фокусом",
		_finite3(g_bot) and near_d > 0.1 and near_d < cam.min_height * 2.0,
		"%.2f м от фокуса при охвате %.1f м" % [near_d, cam.min_height])

	cam.pan_to(Vector3.ZERO)
	cam._target_height = 28.0
	cam._height = 28.0
	cam._update_position()

# ═════════════════════════════════════════════════════════════════════════════
# П. ПРЯМОУГОЛЬНОСТЬ ПО ВСЕЙ ИГРЕ
# Карта 260 × 146.25. Любое место, где осталось ОДНО число на обе оси, даёт
# либо пустую полосу вдоль длинной оси, либо выброс за короткую.
# ═════════════════════════════════════════════════════════════════════════════
func _p_shape() -> void:
	print("\n═════ П. ФОРМА КАРТЫ В ЖИВОЙ ГЕНЕРАЦИИ ═════")
	var hx: float = main.MAP_HALF_X
	var hz: float = main.MAP_HALF_Z

	# ── П1. ФУНКЦИИ ЗАЖИМА АСИММЕТРИЧНЫ ─────────────────────────────────────
	var fits_x_in: bool  = main._fits_in_map(hx - 6.0, 0.0)
	var fits_x_out: bool = main._fits_in_map(hx - 1.0, 0.0)
	var fits_z_in: bool  = main._fits_in_map(0.0, hz - 6.0)
	var fits_z_out: bool = main._fits_in_map(0.0, hz - 1.0)
	# Точка, которая лежит внутри карты по длинной оси, но ЗА краем по короткой
	var trap: bool = main._fits_in_map(0.0, hx - 6.0)
	print("  _fits_in_map: (%.0f,0)=%s (%.0f,0)=%s (0,%.0f)=%s (0,%.0f)=%s; ловушка (0,%.0f)=%s" % [
		hx - 6.0, str(fits_x_in), hx - 1.0, str(fits_x_out),
		hz - 6.0, str(fits_z_in), hz - 1.0, str(fits_z_out), hx - 6.0, str(trap)])
	verdict("П1 _fits_in_map меряет каждую ось своей полуосью",
		fits_x_in and not fits_x_out and fits_z_in and not fits_z_out and not trap,
		"X: %s/%s, Z: %s/%s, ловушка %s" % [
			str(fits_x_in), str(fits_x_out), str(fits_z_in), str(fits_z_out), str(trap)])

	var cm: Vector2 = main.clamp_to_map(500.0, 500.0)
	print("  clamp_to_map(500, 500) = (%.3f, %.3f); ждали (%.3f, %.3f)" % [
		cm.x, cm.y, _lim_x(), _lim_z()])
	verdict("П2 clamp_to_map зажимает Z по короткой оси, а не по длинной",
		absf(cm.x - _lim_x()) < 0.001 and absf(cm.y - _lim_z()) < 0.001,
		"(%.3f, %.3f)" % [cm.x, cm.y])

	# ── СБОР ВСЕЙ ГЕНЕРАЦИИ ─────────────────────────────────────────────────
	var trees: Array = []
	var ores: Array = []
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null or not is_instance_valid(rn):
			continue
		if rn.resource_type == Constants.RESOURCE_WOOD:
			trees.append(rn.global_position)
		else:
			ores.append(rn.global_position)
	# Кусты и облака — обычные MeshInstance3D под World; различаем по высоте
	var bushes: Array = []
	var clouds: Array = []
	for c in (main._world as Node3D).get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		if mi.position.y > 20.0:
			clouds.append(mi)
		else:
			bushes.append(mi.global_position)
	print("  сгенерировано: деревьев %d, куч руды %d, кустов %d, облаков %d" % [
		trees.size(), ores.size(), bushes.size(), clouds.size()])

	# ── П3. ОБЕ ОСИ ЗАСЕЯНЫ ДО КРАЯ И НИ ОДНА НЕ ПЕРЕПОЛНЕНА ────────────────
	var all_pts: Array = []
	all_pts.append_array(trees)
	all_pts.append_array(ores)
	all_pts.append_array(bushes)
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var outside := 0
	for p in all_pts:
		var v: Vector3 = p
		min_x = minf(min_x, v.x); max_x = maxf(max_x, v.x)
		min_z = minf(min_z, v.z); max_z = maxf(max_z, v.z)
		if absf(v.x) > hx or absf(v.z) > hz:
			outside += 1
	print("  габарит всей генерации: X %.1f .. %.1f (край ±%.1f), Z %.1f .. %.1f (край ±%.1f)" % [
		min_x, max_x, hx, min_z, max_z, hz])
	verdict("П3 ни один объект генерации не вылез за поле НИ ПО ОДНОЙ оси", outside == 0,
		"за краем %d из %d" % [outside, all_pts.size()])
	verdict("П4 длинная ось засеяна до края с ОБЕИХ сторон",
		min_x < -(hx - 14.0) and max_x > hx - 14.0,
		"X %.1f .. %.1f при полуоси %.1f" % [min_x, max_x, hx])
	verdict("П5 короткая ось засеяна до края с ОБЕИХ сторон",
		min_z < -(hz - 14.0) and max_z > hz - 14.0,
		"Z %.1f .. %.1f при полуоси %.1f" % [min_z, max_z, hz])

	# ── П6. ПОЛОСЫ: НИ ОДНОЙ ПУСТОЙ ─────────────────────────────────────────
	# Одноосевой зажим, оставшийся в генераторе, обычно выедает крайние полосы
	# ДЛИННОЙ оси — гистограмма ловит это сразу
	var bands_x: Array[int] = []
	for _i in range(10):
		bands_x.append(0)
	var bands_z: Array[int] = []
	for _i in range(6):
		bands_z.append(0)
	for p2 in all_pts:
		var v2: Vector3 = p2
		var bx: int = clampi(int((v2.x + hx) / (2.0 * hx) * 10.0), 0, 9)
		var bz: int = clampi(int((v2.z + hz) / (2.0 * hz) * 6.0), 0, 5)
		bands_x[bx] += 1
		bands_z[bz] += 1
	var empty_x := 0
	var empty_z := 0
	for b in bands_x:
		if b < 5:
			empty_x += 1
	for b2 in bands_z:
		if b2 < 5:
			empty_z += 1
	print("  полосы по X (10 шт, по 26 м): %s" % str(bands_x))
	print("  полосы по Z (6 шт, по 24.4 м): %s" % str(bands_z))
	verdict("П6 ни одна полоса длинной оси не осталась пустой", empty_x == 0,
		"пустых полос %d из 10" % empty_x)
	verdict("П7 ни одна полоса короткой оси не осталась пустой", empty_z == 0,
		"пустых полос %d из 6" % empty_z)

	# ── П8. ВСЕ ЧЕТЫРЕ УГЛА ОБИТАЕМЫ ────────────────────────────────────────
	var corner_names: Array[String] = ["нижний левый (игрок)", "нижний правый",
		"верхний левый", "верхний правый (ИИ)"]
	var corners: Array = [
		Vector2(-hx + 20.0, -hz + 20.0), Vector2(hx - 20.0, -hz + 20.0),
		Vector2(-hx + 20.0, hz - 20.0),  Vector2(hx - 20.0, hz - 20.0)]
	var poor_corners := 0
	var ore_less := 0
	for i in range(4):
		var c2: Vector2 = corners[i]
		var t_cnt := 0
		var o_cnt := 0
		for p3 in trees:
			var v3: Vector3 = p3
			if Vector2(v3.x - c2.x, v3.z - c2.y).length() < 28.0:
				t_cnt += 1
		for p4 in ores:
			var v4: Vector3 = p4
			if Vector2(v4.x - c2.x, v4.z - c2.y).length() < 28.0:
				o_cnt += 1
		print("    угол %s: деревьев %d, кусков руды %d" % [corner_names[i], t_cnt, o_cnt])
		if t_cnt < 20:
			poor_corners += 1
		if o_cnt < 3:
			ore_less += 1
	verdict("П8 во всех 4 углах карты есть густой лес", poor_corners == 0,
		"пустых углов %d из 4" % poor_corners)
	verdict("П9 во всех 4 углах карты есть руда", ore_less == 0,
		"углов без руды %d из 4" % ore_less)

	# ── П10. ЛЕСНАЯ ПОДКОВА ВОКРУГ КАЖДОЙ БАЗЫ ──────────────────────────────
	# _add_base_forest_pocket сажает 74 попытки в кольце POCKET_INNER..OUTER
	# вокруг ЯКОРЯ базы, обходя открытый сектор в 120°, смотрящий в центр карты.
	#
	# СЧИТАТЬ ПРОСТО «СКОЛЬКО ДЕРЕВЬЕВ В КОЛЬЦЕ» БЕСПОЛЕЗНО: в то же кольцо
	# попадает край УГЛОВОГО лесного массива, и проверка зеленеет, даже когда
	# подковы нет вовсе. Разница между подковой и угловым массивом — В ФОРМЕ:
	# подкова размазана по всем 240° закрытого сектора, угловой массив — пятно
	# в одну сторону. Поэтому считаем по 12 угловым секторам
	for i2 in range(2):
		var anchor: Vector3 = main.PLAYER_BASE_ANCHOR if i2 == 0 else main.ENEMY_BASE_ANCHOR
		var who: String = "игрока" if i2 == 0 else "ИИ"
		var sectors: Array[int] = []
		for _s in range(12):
			sectors.append(0)
		var ring := 0
		for p5 in trees:
			var v5: Vector3 = p5
			var d2v := Vector2(v5.x - anchor.x, v5.z - anchor.z)
			var d: float = d2v.length()
			if d < main.POCKET_INNER - 1.0 or d > main.POCKET_OUTER + 1.0:
				continue
			ring += 1
			var ang: float = fmod(rad_to_deg(atan2(d2v.y, d2v.x)) + 360.0, 360.0)
			sectors[clampi(int(ang / 30.0), 0, 11)] += 1
		# Открытый сектор смотрит в центр карты — там деревьев быть и не должно
		var open_ang: float = fmod(rad_to_deg(atan2(-anchor.z, -anchor.x)) + 360.0, 360.0)
		var closed := 0
		var thin := 0
		for s2 in range(12):
			var mid: float = float(s2) * 30.0 + 15.0
			if absf(fmod(mid - open_ang + 540.0, 360.0) - 180.0) <= 60.0:
				continue                      # это открытый плац перед замком
			closed += 1
			if sectors[s2] < 3:
				thin += 1
		print("    подкова базы %s: в кольце %.0f..%.0f м всего %d деревьев, по секторам %s" % [
			who, main.POCKET_INNER, main.POCKET_OUTER, ring, str(sectors)])
		print("      открытый плац смотрит на %.0f°; закрытых секторов %d, пустых из них %d" % [
			open_ang, closed, thin])
		# ПОРОГ С ЗАПАСОМ, А НЕ «НИ ОДНОГО ПУСТОГО». Подкова сажается 74
		# случайными попытками с отбраковкой по резервам и минимальному
		# просвету, поэтому один тощий сектор из восьми выпадает и на здоровой
		# генерации (замер: 5 прогонов, в одном сектор оказался пустым).
		# Со СЛОМАННОЙ подковой пустых сразу 4–5 из 8 — разрыв огромный,
		# и допуск в один сектор дефект не пропускает
		verdict("П%d лесная подкова базы %s опоясывает замок со всех закрытых сторон" % [
			10 + i2, who],
			ring >= 60 and thin <= 1,
			"деревьев %d, пустых закрытых секторов %d из %d" % [ring, thin, closed])

	# ── П12. СВОИ КУЧИ РУДЫ У БАЗ НЕ СПЛЮЩЕНЫ ЗАЖИМОМ ───────────────────────
	var bad_spots := 0
	for i3 in range(2):
		var anchor2: Vector3 = main.PLAYER_BASE_ANCHOR if i3 == 0 else main.ENEMY_BASE_ANCHOR
		for s in main._base_resource_spots(anchor2):
			var sp: Vector3 = s
			var dd: float = Vector2(sp.x - anchor2.x, sp.z - anchor2.z).length()
			if absf(dd - main.BASE_RESOURCE_DIST) > 0.01:
				bad_spots += 1
			if absf(sp.x) > hx or absf(sp.z) > hz:
				bad_spots += 1
	verdict("П12 базовые кучи руды стоят ровно на своём кольце и внутри карты",
		bad_spots == 0, "сплющенных/выпавших точек %d из 4" % bad_spots)

	# ── П13. СТЕНЫ ПЕРИМЕТРА ПРЯМОУГОЛЬНЫ ───────────────────────────────────
	var walls: Node = null
	for c3 in (main._world as Node3D).get_children():
		if (c3 as Node).name == "WorldWalls":
			walls = c3
	var horiz_len := 0.0
	var vert_len  := 0.0
	if walls != null:
		for c4 in walls.get_children():
			var cs := c4 as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var sz: Vector3 = (cs.shape as BoxShape3D).size
			if sz.x > sz.z:
				horiz_len = maxf(horiz_len, sz.x)
			else:
				vert_len = maxf(vert_len, sz.z)
	print("  стены периметра: вдоль X длиной %.1f, вдоль Z длиной %.1f" % [horiz_len, vert_len])
	verdict("П13 стены периметра построены прямоугольником, а не квадратом",
		absf(horiz_len - hx * 2.0) > 1.0 - 0.001 and horiz_len > hx * 2.0
			and vert_len > hz * 2.0 and absf(horiz_len - vert_len) > 100.0,
		"вдоль X %.1f, вдоль Z %.1f" % [horiz_len, vert_len])

	# ── П14. ОБЛАКА ─────────────────────────────────────────────────────────
	# Облачный слой висит на 40..65 м и при ЛЮБОЙ проекции ведёт себя плохо:
	#   • в перспективе с наклоном 45° верхний луч кадра идёт НИЖЕ горизонта,
	#     поэтому всё, что выше объектива, не рисуется вообще — 33 билборда
	#     создавались впустую;
	#   • в ортографии наоборот: фрустум — коробка, и облако проецируется прямо
	#     на поле, читаясь как белая клякса, лежащая на траве рядом с замком
	#     (снято стендом qa_world3/Shot.gd, кадр 07).
	# Поэтому проверка одна и та же для обеих проекций: облаков в кадре быть
	# не должно. Если слой отключён (CLOUDS_ENABLED = false) — проверка
	# тривиально зелёная, и это правильный способ его держать
	var c_min_x := INF
	var c_max_x := -INF
	var c_min_z := INF
	var c_max_z := -INF
	var c_out := 0
	var lowest := INF
	for cl in clouds:
		var m2 := cl as MeshInstance3D
		var p6: Vector3 = m2.global_position
		c_min_x = minf(c_min_x, p6.x); c_max_x = maxf(c_max_x, p6.x)
		c_min_z = minf(c_min_z, p6.z); c_max_z = maxf(c_max_z, p6.z)
		if absf(p6.x) > hx + 0.01 or absf(p6.z) > hz + 0.01:
			c_out += 1
		var qh: float = 0.0
		if m2.mesh is QuadMesh:
			qh = (m2.mesh as QuadMesh).size.y
		lowest = minf(lowest, p6.y - qh * 0.5)
	if clouds.is_empty():
		print("  облака: слой отключён — в сцене нет ни одного билборда")
	else:
		print("  облака: X %.1f .. %.1f, Z %.1f .. %.1f, за краем %d; нижняя кромка самого низкого %.1f м" % [
			c_min_x, c_max_x, c_min_z, c_max_z, c_out, lowest])
	verdict("П14 облака не вылезают за поле по короткой оси", c_out == 0,
		"за краем %d из %d" % [c_out, clouds.size()])

	# Эмпирика: обходим 12 положений камеры и смотрим, попадает ли хоть одно
	# облако во фрустум хоть раз
	var seen := 0
	for hh in [cam.min_height, 24.0, cam.max_height]:
		for f in [Vector2(0.0, 0.0), Vector2(-main.CAM_BOUND_X, -main.CAM_BOUND_Z),
				Vector2(main.CAM_BOUND_X, main.CAM_BOUND_Z), Vector2(0.0, -main.CAM_BOUND_Z)]:
			var fv2: Vector2 = f
			look(fv2.x, fv2.y, float(hh))
			for cl2 in clouds:
				var m3 := cl2 as MeshInstance3D
				var qh2: float = 0.0
				if m3.mesh is QuadMesh:
					qh2 = (m3.mesh as QuadMesh).size.y
				var bottom: Vector3 = m3.global_position - Vector3(0.0, qh2 * 0.5, 0.0)
				if cam.is_position_in_frustum(m3.global_position) \
						or cam.is_position_in_frustum(bottom):
					seen += 1
	var checks: int = clouds.size() * 12
	print("  облаков во фрустуме: %d попаданий на %d проверок (%d облаков × 12 положений камеры)" % [
		seen, checks, clouds.size()])
	_notes.append("облачный слой: %d билбордов, %d попаданий во фрустум на %d проверок" % [
		clouds.size(), seen, checks])
	verdict("П15 облачный слой не лезет в кадр наземной кляксой (или отключён совсем)",
		seen == 0, "попаданий %d на %d проверок при %d облаках" % [seen, checks, clouds.size()])

	cam.pan_to(Vector3.ZERO)
	cam._height = 28.0
	cam._target_height = 28.0
	cam._update_position()

# ═════════════════════════════════════════════════════════════════════════════
# С. СТАРТОВЫЕ СПАУНЫ И ПОСТАНОВКА ЗАМКА
# ═════════════════════════════════════════════════════════════════════════════

## Снимок стартового состояния ИИ до того, как стенд что-либо трогает
func _snapshot_ai_start() -> void:
	var castle: Vector3 = Vector3.ZERO
	var has_castle := false
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if b is Castle:
			castle = (b as Node3D).global_position
			has_castle = true
	var workers: Array = []
	var busy := 0
	for u in get_tree().get_nodes_in_group("enemy_units"):
		var w := u as Worker
		if w == null or not is_instance_valid(w):
			continue
		workers.append(w.global_position)
		if w.state != Unit.State.IDLE:
			busy += 1
	_ai_snap = {"castle": castle, "has": has_castle, "workers": workers, "busy": busy}

func _s_spawns() -> void:
	print("\n═════ С. СПАУНЫ И ПОСТАНОВКА ЗАМКА ═════")
	var pa: Vector3 = main.PLAYER_BASE_ANCHOR
	var ea: Vector3 = main.ENEMY_BASE_ANCHOR
	var half: float = float(main.PLAYER_PLACE_HALF)

	# ── С1. СТАРТОВЫЕ РАБОЧИЕ ИИ ────────────────────────────────────────────
	var wpts: Array = _ai_snap["workers"]
	var ec: Vector3 = _ai_snap["castle"]
	var far := 0.0
	var wrong_corner := 0
	for p in wpts:
		var v: Vector3 = p
		far = maxf(far, Vector2(v.x - ec.x, v.z - ec.z).length())
		if v.x <= 0.0 or v.z <= 0.0:
			wrong_corner += 1
	print("  ИИ на старте: замок (%.1f, %.1f), рабочих %d, самый дальний в %.1f м от замка, занятых %d" % [
		ec.x, ec.z, wpts.size(), far, int(_ai_snap["busy"])])
	verdict("С1 у ИИ ровно столько же стартовых рабочих, сколько у игрока",
		wpts.size() == 5, "рабочих %d" % wpts.size())
	verdict("С2 стартовые рабочие ИИ появились ВПЛОТНУЮ к своему замку",
		bool(_ai_snap["has"]) and far < 12.0, "самый дальний в %.1f м" % far)
	verdict("С3 все стартовые рабочие ИИ — в его собственном углу (+X, +Z)",
		wrong_corner == 0, "не в своём углу %d из %d" % [wrong_corner, wpts.size()])
	verdict("С4 стартовые рабочие ИИ сразу получили работу",
		int(_ai_snap["busy"]) == wpts.size(),
		"работают %d из %d" % [int(_ai_snap["busy"]), wpts.size()])

	# ── С5. ЖИВОЙ ПОТОК ПОСТАНОВКИ ЗАМКА ИГРОКА ─────────────────────────────
	# Не «функция зажима вернула что надо», а вся цепочка: фаза → призрак →
	# клик мышью → замок → пять рабочих на ресурсах
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD, 3000.0)
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD, 3000.0)
	main.enter_castle_placement()
	print("  фаза после нажатия «построить замок»: %d (PLACING_CASTLE = 1)" % main._phase)
	verdict("С5 нажатие «построить замок» переводит игру в режим постановки",
		main._phase == 1 and main._ghost != null,
		"фаза %d, призрак %s" % [main._phase, str(main._ghost != null)])

	# ── С6. ПРИЗРАК НЕ ВЫЛЕЗАЕТ ИЗ СТАРТОВОГО КВАДРАТА ──────────────────────
	# Курсор в headless висит в (0,0) — это верхний левый угол экрана, луч
	# уходит далеко. Гоняем камеру по всей карте и каждый раз спрашиваем призрак
	var ghost_bad := 0
	var ghost_far := 0.0
	for f in [Vector2(0.0, 0.0), Vector2(main.CAM_BOUND_X, main.CAM_BOUND_Z),
			Vector2(-main.CAM_BOUND_X, -main.CAM_BOUND_Z),
			Vector2(main.CAM_BOUND_X, -main.CAM_BOUND_Z),
			Vector2(-main.CAM_BOUND_X, main.CAM_BOUND_Z)]:
		var fv: Vector2 = f
		for hh in [cam.min_height, 28.0, cam.max_height]:
			look(fv.x, fv.y, float(hh))
			main._update_ghost(0.016)
			var gp: Vector3 = main._ghost.global_position
			ghost_far = maxf(ghost_far, Vector2(gp.x - pa.x, gp.z - pa.z).length())
			if absf(gp.x - pa.x) > half + 0.01 or absf(gp.z - pa.z) > half + 0.01 \
					or not _finite3(gp):
				ghost_bad += 1
	print("  призрак замка в 15 положениях камеры: вылазок за стартовый квадрат %d, дальше всего %.1f м от якоря" % [
		ghost_bad, ghost_far])
	verdict("С6 призрак замка не выходит за стартовый квадрат игрока ни при каком ракурсе",
		ghost_bad == 0, "вылазок %d из 15" % ghost_bad)

	# Ставим замок кликом по своему углу
	look(pa.x, pa.z, 28.0)
	var aim_pt: Vector3 = pa + Vector3(6.0, 0.0, 6.0)
	var screen: Vector2 = cam.unproject_position(aim_pt)
	main._try_place_castle(screen)
	await frames(6)
	var pc: Castle = null
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b is Castle:
			pc = b as Castle
	var err: float = 999.0
	if pc != null:
		err = Vector2(pc.global_position.x - aim_pt.x, pc.global_position.z - aim_pt.z).length()
	print("  клик в свой угол (%.1f, %.1f) → замок в (%.1f, %.1f), ошибка %.2f м, фаза %d" % [
		aim_pt.x, aim_pt.z, pc.global_position.x if pc != null else 0.0,
		pc.global_position.z if pc != null else 0.0, err, main._phase])
	verdict("С7 замок игрока встаёт туда, куда кликнули внутри своего угла",
		pc != null and err < 1.0, "ошибка %.2f м" % err)

	var pw: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		var w := u as Worker
		if w != null and is_instance_valid(w):
			pw.append(w)
	var w_far := 0.0
	var w_idle := 0
	var w_bad := 0
	for w2 in pw:
		var ww := w2 as Worker
		var d: float = Vector2(ww.global_position.x - pc.global_position.x,
			ww.global_position.z - pc.global_position.z).length()
		w_far = maxf(w_far, d)
		if ww.state == Unit.State.IDLE:
			w_idle += 1
		if ww.global_position.x > 0.0 or ww.global_position.z > 0.0:
			w_bad += 1
	print("  стартовые рабочие игрока: %d, самый дальний в %.1f м от замка, простаивают %d, не в своём углу %d" % [
		pw.size(), w_far, w_idle, w_bad])
	verdict("С8 у игрока появились 5 стартовых рабочих у своего замка",
		pw.size() == 5 and w_far < 12.0, "рабочих %d, дальний %.1f м" % [pw.size(), w_far])
	verdict("С9 стартовые рабочие игрока — в его углу и сразу при деле",
		w_bad == 0 and w_idle == 0, "не в углу %d, простаивают %d" % [w_bad, w_idle])

	# ── С10. КЛИК В УГОЛ ИИ И ЗА КРАЙ КАРТЫ ─────────────────────────────────
	# Замок ставим повторно (движок это позволяет) — важен ТОЛЬКО итоговый
	# зажим точки. Лишние постройки и рабочих сразу убираем
	var probes: Array = [
		{"nm": "угол ИИ", "p": ea},
		{"nm": "центр карты", "p": Vector3(0.0, 0.0, 0.0)},
		{"nm": "далеко за краем", "p": Vector3(-900.0, 0.0, -900.0)},
	]
	var clamp_bad := 0
	for pr in probes:
		var d2: Dictionary = pr
		var tgt: Vector3 = d2["p"]
		look(clampf(tgt.x, -main.CAM_BOUND_X, main.CAM_BOUND_X),
			clampf(tgt.z, -main.CAM_BOUND_Z, main.CAM_BOUND_Z), 28.0)
		var sc: Vector2 = cam.unproject_position(Vector3(tgt.x, 0.0, tgt.z))
		var before: Array = get_tree().get_nodes_in_group("player_buildings")
		main._try_place_castle(sc)
		await frames(4)
		var fresh: Castle = null
		for b2 in get_tree().get_nodes_in_group("player_buildings"):
			if b2 is Castle and not (b2 in before):
				fresh = b2 as Castle
		var ok := false
		var pos := Vector3.ZERO
		if fresh != null:
			pos = fresh.global_position
			ok = absf(pos.x - pa.x) <= half + 0.01 and absf(pos.z - pa.z) <= half + 0.01 \
				and absf(pos.x) <= main.MAP_CLAMP_X + 0.01 \
				and absf(pos.z) <= main.MAP_CLAMP_Z + 0.01 \
				and pos.x < 0.0 and pos.z < 0.0
		print("    клик «%s» (%.0f, %.0f) → замок в (%.1f, %.1f) %s" % [
			String(d2["nm"]), tgt.x, tgt.z, pos.x, pos.z, "ОК" if ok else "МИМО"])
		if not ok:
			clamp_bad += 1
		# Уборка: лишний замок и его пятеро рабочих
		if fresh != null:
			for u2 in get_tree().get_nodes_in_group("player_units"):
				var w3 := u2 as Worker
				if w3 != null and is_instance_valid(w3) \
						and w3.global_position.distance_to(pos) < 6.0:
					w3.queue_free()
			fresh.queue_free()
		await frames(4)
	verdict("С10 куда бы игрок ни ткнул, замок остаётся в его стартовом квадрате",
		clamp_bad == 0, "промахов %d из 3" % clamp_bad)

	# ── С11. МАССОВАЯ ПРОВЕРКА clamp_to_player_start ─────────────────────────
	var rng := RandomNumberGenerator.new()
	rng.seed = 30071
	var out_sq := 0
	var out_map := 0
	var on_enemy := 0
	var non_idem := 0
	var nanned := 0
	for _i in range(4000):
		var x: float = rng.randf_range(-600.0, 600.0)
		var z: float = rng.randf_range(-600.0, 600.0)
		var a: Vector2 = main.clamp_to_player_start(x, z)
		var b: Vector2 = main.clamp_to_player_start(a.x, a.y)
		if not (is_finite(a.x) and is_finite(a.y)):
			nanned += 1
			continue
		if absf(a.x - b.x) > 1e-6 or absf(a.y - b.y) > 1e-6:
			non_idem += 1
		if absf(a.x - pa.x) > half + 1e-4 or absf(a.y - pa.z) > half + 1e-4:
			out_sq += 1
		if absf(a.x) > main.MAP_CLAMP_X + 1e-4 or absf(a.y) > main.MAP_CLAMP_Z + 1e-4:
			out_map += 1
		if a.x >= 0.0 or a.y >= 0.0:
			on_enemy += 1
	print("  4000 случайных точек через clamp_to_player_start: вне квадрата %d, вне карты %d," % [
		out_sq, out_map])
	print("    на половине ИИ %d, неидемпотентных %d, мусорных %d" % [
		on_enemy, non_idem, nanned])
	verdict("С11 clamp_to_player_start ни разу не выпустил точку из стартового квадрата",
		out_sq == 0 and nanned == 0, "вне квадрата %d, мусорных %d" % [out_sq, nanned])
	verdict("С12 clamp_to_player_start ни разу не выпустил точку за край карты",
		out_map == 0, "вне карты %d" % out_map)
	verdict("С13 ни одна точка постановки не оказалась на половине ИИ",
		on_enemy == 0, "на половине ИИ %d" % on_enemy)
	verdict("С14 clamp_to_player_start идемпотентен", non_idem == 0,
		"неидемпотентных %d" % non_idem)

	# Реальный размер площадки: квадрат ±30 от якоря частично торчит за карту,
	# и настоящая свобода игрока по осям РАЗНАЯ — это стоит знать явно
	var lo: Vector2 = main.clamp_to_player_start(-9999.0, -9999.0)
	var hi: Vector2 = main.clamp_to_player_start(9999.0, 9999.0)
	print("  фактическая площадка под замок: X %.2f .. %.2f (%.1f м), Z %.2f .. %.2f (%.1f м)" % [
		lo.x, hi.x, hi.x - lo.x, lo.y, hi.y, hi.y - lo.y])
	_notes.append("площадка под замок игрока: %.1f × %.1f м (квадрат ±%.0f срезан краем карты)" % [
		hi.x - lo.x, hi.y - lo.y, half])
	verdict("С15 стартовая площадка не выродилась и не съехала за карту",
		hi.x - lo.x > 20.0 and hi.y - lo.y > 20.0 and lo.x >= -main.MAP_CLAMP_X - 0.01
			and lo.y >= -main.MAP_CLAMP_Z - 0.01,
		"%.1f × %.1f м" % [hi.x - lo.x, hi.y - lo.y])

	# ── С16. ДИАГОНАЛЬ БАЗ ПРОХОДИТ ЧЕРЕЗ ЦЕНТР ─────────────────────────────
	var diag: float = Vector2(ea.x - pa.x, ea.z - pa.z).length()
	var mid: Vector3 = main.ai_rally_point()
	var off_line: float = absf((ea.x - pa.x) * (0.0 - pa.z) - (0.0 - pa.x) * (ea.z - pa.z)) / diag
	print("  диагональ баз %.1f м; центр карты отстоит от прямой между базами на %.3f м; точка сбора ИИ (%.1f, %.1f)" % [
		diag, off_line, mid.x, mid.z])
	verdict("С16 базы стоят по диагонали через центр карты, и точка сбора ИИ — этот центр",
		off_line < 0.01 and absf(mid.x) < 0.01 and absf(mid.z) < 0.01 and diag > 200.0,
		"смещение %.3f м, точка сбора (%.1f, %.1f)" % [off_line, mid.x, mid.z])

	main._phase = 3     # PLAYING
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# М. МАРШ ЧЕРЕЗ ВСЮ КАРТУ
# ═════════════════════════════════════════════════════════════════════════════
func _m_march() -> void:
	print("\n═════ М. МАРШ ПО ДИАГОНАЛИ ВО ВСЮ КАРТУ ═════")
	var pa: Vector3 = main.PLAYER_BASE_ANCHOR
	var ea: Vector3 = main.ENEMY_BASE_ANCHOR
	var lim_x: float = _lim_x()
	var lim_z: float = _lim_z()

	# ── М1. ЖИВОЙ ИИ ИДЁТ ИЗ СВОЕГО УГЛА К ИГРОКУ ───────────────────────────
	# Своя армия у базы ИИ, мир объявляем закончившимся — и смотрим, КУДА ИИ
	# её ведёт: по диагонали через центр или вдоль границы.
	#
	# БОЙЦОВ НУЖНО БОЛЬШЕ ОДНОГО ОТРЯДА. Отряд копейщиков — 50 моделей, а
	# первый отряд каждого типа ИИ оставляет дома гарнизоном
	# (HOME_GUARD_PER_TYPE = 1). С 16 бойцами получался ровно один отряд, он
	# честно вставал на кольцо обороны — и «поход» не начинался вовсе.
	# Берём 60: первый отряд остаётся дома, излишек уходит в поле
	var army: Array = []
	for i in range(60):
		var e := _spawn("spearman", Constants.FACTION_ENEMY,
			ea + Vector3(float(i % 8) * 0.9 - 3.15, 0.0, float(i / 8) * 0.9 - 3.15))
		army.append(e)
	await frames(8)
	var ai = main.enemy_ai
	ai._peace_over = true
	ai.tick()
	# Следим ТОЛЬКО за полевыми отрядами: гарнизон обязан стоять дома
	var field: Array = []
	var roles: Array = []
	for s in ai.squads:
		var sq: Dictionary = s
		roles.append("%s×%d" % [String(sq["role"]), (sq["members"] as Array).size()])
		if String(sq["role"]) != "guard":
			field.append_array(sq["members"] as Array)
	print("  ИИ разложил %d отрядов: %s; в поле %d бойцов" % [
		ai.squads.size(), str(roles), field.size()])
	verdict("М0 ИИ отправляет излишки в поле, а не держит всё дома",
		field.size() > 0, "полевых бойцов %d при %d отрядах" % [field.size(), ai.squads.size()])
	if field.is_empty():
		field = army
	army = field
	var start_c: Vector2 = _centroid(army)
	var t0: int = Time.get_ticks_msec()
	var near_edge := 0
	var min_center := INF
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		var c: Vector2 = _centroid(army)
		min_center = minf(min_center, c.length())
		if lim_x - absf(c.x) < 8.0 or lim_z - absf(c.y) < 8.0:
			near_edge += 1
	var end_c: Vector2 = _centroid(army)
	var toward: float = start_c.distance_to(Vector2(pa.x, pa.z)) \
		- end_c.distance_to(Vector2(pa.x, pa.z))
	var out_army := 0
	for a in army:
		if not is_instance_valid(a):
			continue
		var p: Vector3 = (a as Node3D).global_position
		if absf(p.x) > lim_x + 0.01 or absf(p.z) > lim_z + 0.01 or not _finite3(p):
			out_army += 1
	print("  полевые отряды ИИ (%d бойцов), 60 с: центр отряда (%.1f, %.1f) → (%.1f, %.1f)" % [
		army.size(),
		start_c.x, start_c.y, end_c.x, end_c.y])
	print("    продвижение к базе игрока %.1f м, ближе всего к центру карты %.1f м, кадров у границы %d, за краем %d" % [
		toward, min_center, near_edge, out_army])
	verdict("М1 армия ИИ идёт из своего угла В СТОРОНУ игрока, а не топчется дома",
		toward > 50.0, "продвижение %.1f м за 60 с" % toward)
	verdict("М2 армия ИИ идёт серединой карты, а не вдоль границы", near_edge == 0,
		"кадров у границы %d" % near_edge)
	verdict("М3 ни один боец ИИ не вышел за край на марше", out_army == 0,
		"за краем %d из %d" % [out_army, army.size()])

	# Дальше проверяется ДВИЖЕНИЕ, а не бой: армию ИИ и его рабочих убираем,
	# ИИ усыпляем — иначе марширующие через всю карту сцепятся у чужой базы
	# и до угла просто не дойдут (агро-радиус 10 м)
	ai.set_process(false)
	for n in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(n):
			(n as Node).queue_free()
	await frames(6)

	# ── М4. ОДИНОЧКА И ОТРЯД ЧЕРЕЗ ВСЮ ДИАГОНАЛЬ, ОБА НАПРАВЛЕНИЯ ───────────
	var diag: float = Vector2(ea.x - pa.x, ea.z - pa.z).length()
	var solo := _spawn("spearman", Constants.FACTION_PLAYER, pa)
	var back := _spawn("spearman", Constants.FACTION_PLAYER, ea)
	var squad: Array = []
	for i2 in range(12):
		var s := _spawn("spearman", Constants.FACTION_PLAYER,
			pa + Vector3(float(i2 % 4) * 0.8 - 1.2, 0.0, float(i2 / 4) * 0.8 - 0.8))
		squad.append(s)
	await frames(6)
	solo.command_move(ea)
	back.command_move(pa)
	for s2 in squad:
		(s2 as Unit).command_move(ea + Vector3(-4.0, 0.0, -4.0))

	# Расстояние до цели фиксируется В МОМЕНТ ПРИБЫТИЯ, а не в конце цикла:
	# дойдя до угла ИИ, боец видит вражеский замок в 5 м и сам идёт его бить
	# (агро-радиус 10 м) — это правильное поведение, но замер «дошёл ли» оно
	# портит: юнит уже сошёл с точки приказа
	var t1: int = Time.get_ticks_msec()
	var solo_center := INF
	var back_center := INF
	var solo_edge := 0
	var solo_done := 0
	var back_done := 0
	var solo_left := 999.0
	var back_left := 999.0
	var squad_idle := 0
	while Time.get_ticks_msec() - t1 < 300000:
		await get_tree().process_frame
		var sp: Vector3 = solo.global_position
		var bp: Vector3 = back.global_position
		solo_center = minf(solo_center, Vector2(sp.x, sp.z).length())
		back_center = minf(back_center, Vector2(bp.x, bp.z).length())
		if absf(sp.x) > lim_x - 0.05 or absf(sp.z) > lim_z - 0.05:
			solo_edge += 1
		if solo.state == Unit.State.IDLE and solo_done == 0:
			solo_done = Time.get_ticks_msec() - t1
			solo_left = Vector2(sp.x - solo.move_target.x, sp.z - solo.move_target.z).length()
		if back.state == Unit.State.IDLE and back_done == 0:
			back_done = Time.get_ticks_msec() - t1
			back_left = Vector2(bp.x - back.move_target.x, bp.z - back.move_target.z).length()
		squad_idle = 0
		for s3 in squad:
			if is_instance_valid(s3) and (s3 as Unit).state == Unit.State.IDLE:
				squad_idle += 1
		if solo_done > 0 and back_done > 0 and squad_idle == squad.size():
			break
	var ideal: float = diag / maxf(solo.move_speed, 0.1)
	print("  диагональ %.1f м, теоретический марш %.0f с при скорости %.1f м/с" % [
		diag, ideal, solo.move_speed])
	print("    одиночка туда : IDLE через %.1f с, осталось %.2f м, ближе всего к центру %.1f м, кадров у стены %d" % [
		float(solo_done) / 1000.0, solo_left, solo_center, solo_edge])
	print("    одиночка назад: IDLE через %.1f с, осталось %.2f м, ближе всего к центру %.1f м" % [
		float(back_done) / 1000.0, back_left, back_center])
	print("    отряд 12      : в IDLE %d из %d" % [squad_idle, squad.size()])
	verdict("М4 одиночка проходит всю диагональ карты и встаёт в IDLE",
		solo_done > 0 and solo_left < 1.5,
		"состояние %d, осталось %.2f м" % [solo.state, solo_left])
	verdict("М5 обратный маршрут (из угла ИИ в угол игрока) тоже доходит",
		back_done > 0 and back_left < 1.5,
		"состояние %d, осталось %.2f м" % [back.state, back_left])
	verdict("М6 отряд из 12 доходит через всю карту и встаёт", squad_idle == squad.size(),
		"в IDLE %d из %d" % [squad_idle, squad.size()])
	verdict("М7 маршрут идёт через центр карты, а не вдоль стены",
		solo_center < 8.0 and back_center < 8.0 and solo_edge == 0,
		"ближе всего к центру %.1f / %.1f м, кадров у стены %d" % [
			solo_center, back_center, solo_edge])
	verdict("М8 марш укладывается в разумное время (не залипает у границы)",
		solo_done > 0 and float(solo_done) / 1000.0 < ideal * 1.8,
		"%.0f с при теоретических %.0f с" % [float(solo_done) / 1000.0, ideal])
	_notes.append("марш через всю карту: %.1f м за %.0f с (теория %.0f с)" % [
		diag, float(solo_done) / 1000.0, ideal])

	solo.queue_free()
	back.queue_free()
	for s4 in squad:
		if is_instance_valid(s4):
			(s4 as Node).queue_free()
	await frames(4)

## Центр масс живых узлов на плоскости XZ
func _centroid(arr: Array) -> Vector2:
	var acc := Vector2.ZERO
	var n := 0
	for a in arr:
		if not is_instance_valid(a):
			continue
		var p: Vector3 = (a as Node3D).global_position
		acc += Vector2(p.x, p.z)
		n += 1
	if n == 0:
		return Vector2.ZERO
	return acc / float(n)
