extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: КАМЕРА «КАЗАКИ 3», РАСШИРЕННАЯ КАРТА, КРАЙ МИРА
## ═══════════════════════════════════════════════════════════════════════════
##   1 КАМЕРА   — вращение запрещено (yaw/pitch), панорама и зум работают
##   2 КАРТА    — +30%, поле и коллайдер земли по новому размеру, лес разъехался
##   3 ОЗЕРО    — воды нет вовсе, центр карты проходим
##   4 ГРАНИЦЫ  — юнит упирается в край, приказы зажимаются, чернота на месте

const _UCfg = preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

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

func _find(node: Node, nm: String) -> Node:
	if node.name == nm:
		return node
	for c in node.get_children():
		var r: Node = _find(c, nm)
		if r != null:
			return r
	return null

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)

	await _t1_camera()
	await _t2_map()
	await _t3_lake()
	await _t4_bounds()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 62), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== WORLD TEST DONE ===")
	get_tree().quit()

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n:
		out += " "
	return out

# ═════════════════════════════════════════════════════════════════════════════
# 1. КАМЕРА: ВРАЩАТЬ НЕЛЬЗЯ, ВОЗИТЬ И ЗУМИТЬ МОЖНО
# ═════════════════════════════════════════════════════════════════════════════
func _t1_camera() -> void:
	print("\n═════ 1. КАМЕРА ═════")
	var cam: RTSCamera = main._camera
	var yaw0: float   = cam._orbit_yaw
	var pitch0: float = cam._orbit_pitch

	print("  ракурс: наклон %.1f°, поворот %.1f°" % [pitch0, yaw0])
	verdict("1a наклон камеры зафиксирован на FIXED_PITCH",
		absf(pitch0 - RTSCamera.FIXED_PITCH) < 0.001,
		"наклон %.1f, константа %.1f" % [pitch0, RTSCamera.FIXED_PITCH])

	# ── СРЕДНЯЯ КНОПКА: РАНЬШЕ ВРАЩАЛА, ТЕПЕРЬ ТАЩИТ ────────────────────────
	# ТАЩИМ ИЗ ЦЕНТРА КАРТЫ, А НЕ ОТКУДА ПРИДЁТСЯ. Партия теперь открывается
	# у базы игрока и ПОЛНОСТЬЮ ОТДАЛЁННОЙ камерой (Main.start_game →
	# jump_to(PLAYER_BASE_ANCHOR, max_height)), а на максимальном отдалении
	# _clamp_focus() разрешает фокусу наименьший ход — в углу карты он уже
	# упёрт в предел по обеим осям, и протяжка «дальше в угол» честно даёт
	# нулевое смещение. Проверяется здесь не клампинг (для него есть свои
	# пункты), а то, что средняя кнопка ВООБЩЕ возит карту
	cam.jump_to(Vector3.ZERO, cam.min_height)
	await frames(2)
	var focus0: Vector3 = cam._focus
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed  = true
	down.position = Vector2(640.0, 360.0)
	cam._unhandled_input(down)
	var total_drag := 0.0
	for i in range(20):
		var mm := InputEventMouseMotion.new()
		mm.position = Vector2(640.0 + float(i + 1) * 12.0, 360.0 + float(i + 1) * 6.0)
		cam._unhandled_input(mm)
		total_drag += 12.0
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_MIDDLE
	up.pressed  = false
	up.position = Vector2(880.0, 480.0)
	cam._unhandled_input(up)
	var moved: float = Vector2(cam._focus.x - focus0.x, cam._focus.z - focus0.z).length()
	print("  протащили среднюю кнопку на %.0f px: поворот %.3f°, наклон %.3f°, фокус уехал на %.2f м" % [
		total_drag, cam._orbit_yaw, cam._orbit_pitch, moved])
	verdict("1b средняя кнопка НЕ вращает сцену",
		absf(cam._orbit_yaw - yaw0) < 0.001 and absf(cam._orbit_pitch - pitch0) < 0.001,
		"поворот %.3f, наклон %.3f" % [cam._orbit_yaw, cam._orbit_pitch])
	verdict("1c средняя кнопка ТАЩИТ карту", moved > 1.0, "фокус уехал %.2f м" % moved)

	# ── КЛАВИАТУРА: Q/E БОЛЬШЕ НЕ КРУТЯТ ────────────────────────────────────
	# Ввод в headless не эмулируется через Input.is_key_pressed, поэтому
	# проверяем ИСХОДНИК: в камере не должно остаться ни одной ветки поворота
	var src: String = FileAccess.get_file_as_string("res://scripts/RTSCamera.gd")
	var has_qe: bool = src.contains("KEY_Q") or src.contains("KEY_E")
	var writes_yaw: bool = src.contains("_orbit_yaw +=") or src.contains("_orbit_yaw -=")
	var writes_pitch: bool = src.contains("_orbit_pitch =") \
		and not src.contains("_orbit_pitch = FIXED_PITCH")
	print("  в исходнике камеры: клавиши Q/E=%s, прибавка к повороту=%s, правка наклона=%s" % [
		str(has_qe), str(writes_yaw), str(writes_pitch)])
	verdict("1d в камере не осталось кода поворота (Q/E и накопление yaw)",
		not has_qe and not writes_yaw, "Q/E=%s, yaw+=%s" % [str(has_qe), str(writes_yaw)])
	verdict("1e в камере не осталось кода изменения наклона",
		not writes_pitch, "правка наклона=%s" % str(writes_pitch))

	# ── ЗУМ ─────────────────────────────────────────────────────────────────
	var h0: float = cam._target_height
	for _i in range(40):
		var w := InputEventMouseButton.new()
		w.button_index = MOUSE_BUTTON_WHEEL_UP
		w.pressed = true
		cam._unhandled_input(w)
	var h_min: float = cam._target_height
	for _i in range(80):
		var w2 := InputEventMouseButton.new()
		w2.button_index = MOUSE_BUTTON_WHEEL_DOWN
		w2.pressed = true
		cam._unhandled_input(w2)
	var h_max: float = cam._target_height
	print("  зум: старт %.1f → упор вблизи %.1f (min %.1f) → упор вдали %.1f (max %.1f)" % [
		h0, h_min, cam.min_height, h_max, cam.max_height])
	verdict("1f зум упирается в min_height и max_height",
		absf(h_min - cam.min_height) < 0.001 and absf(h_max - cam.max_height) < 0.001,
		"вблизи %.1f, вдали %.1f" % [h_min, h_max])
	verdict("1g колесо не трогает ракурс",
		absf(cam._orbit_yaw - yaw0) < 0.001 and absf(cam._orbit_pitch - pitch0) < 0.001)

	# ── ГРАНИЦЫ ПРОГУЛКИ КАМЕРЫ ─────────────────────────────────────────────
	cam.pan_to(Vector3(9999.0, 0.0, 9999.0))
	var fx: float = cam._focus.x
	cam.pan_to(Vector3(-9999.0, 0.0, -9999.0))
	var fx2: float = cam._focus.x
	print("  увод камеры за карту: +∞ → %.1f, −∞ → %.1f (предел ±%.1f)" % [fx, fx2, main.CAM_BOUND_X])
	verdict("1h камера не выходит за пределы карты",
		absf(fx - main.CAM_BOUND_X) < 0.01 and absf(fx2 + main.CAM_BOUND_X) < 0.01,
		"+%.1f / %.1f" % [fx, fx2])
	cam.pan_to(Vector3.ZERO)
	cam._target_height = 28.0
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# 2. КАРТА: ПРЯМОУГОЛЬНИК 16:9, ПЛОЩАДЬ СОХРАНЕНА, СПАУНЫ ПО ДИАГОНАЛИ
# ═════════════════════════════════════════════════════════════════════════════
func _t2_map() -> void:
	print("\n═════ 2. ФОРМА И РАЗМЕР КАРТЫ ═════")
	var hx: float = main.MAP_HALF_X
	var hz: float = main.MAP_HALF_Z
	var eq: float = main.MAP_HALF_EQUIV
	var aspect: float = hx / hz
	print("  поле %.1f × %.1f м, пропорция %.3f (ждали %.3f = 16:9)" % [
		hx * 2.0, hz * 2.0, aspect, 16.0 / 9.0])
	verdict("2a карта прямоугольная в пропорции 16:9",
		absf(aspect - 16.0 / 9.0) < 0.005, "пропорция %.3f" % aspect)

	var area: float = (hx * 2.0) * (hz * 2.0)
	var area_sq: float = (eq * 2.0) * (eq * 2.0)
	print("  площадь %.0f м² против прежнего квадрата %.0f м² (%.1f%%)" % [
		area, area_sq, area / area_sq * 100.0])
	verdict("2b площадь сохранена от прежней квадратной карты",
		absf(area / area_sq - 1.0) < 0.005, "%.0f против %.0f м²" % [area, area_sq])

	# ПОЛЕ БОЛЬШЕ НЕ PlaneMesh: с рельефом это сетка вершин (ArrayMesh), у неё
	# нет свойства size. Меряем фактический габарит меша — он и есть размер поля
	var field: Node = _find(main, "Playfield")
	var fsize := Vector2.ZERO
	if field != null:
		var fm: Mesh = (field as MeshInstance3D).mesh
		if fm is PlaneMesh:
			fsize = (fm as PlaneMesh).size
		elif fm != null:
			var ab: AABB = (field as MeshInstance3D).get_aabb()
			fsize = Vector2(ab.size.x, ab.size.z)
	print("  зелёное поле: %.1f × %.1f м" % [fsize.x, fsize.y])
	verdict("2c зелёное поле построено прямоугольным по осям",
		absf(fsize.x - hx * 2.0) < 0.01 and absf(fsize.y - hz * 2.0) < 0.01,
		"%.1f × %.1f, ждали %.1f × %.1f" % [fsize.x, fsize.y, hx * 2.0, hz * 2.0])

	var ground: Node = _find(main, "Ground")
	var gsize := Vector3.ZERO
	if ground != null:
		for c in ground.get_children():
			var cs := c as CollisionShape3D
			if cs != null and cs.shape is BoxShape3D:
				gsize = (cs.shape as BoxShape3D).size
	print("  коллайдер земли: %.1f × %.1f м" % [gsize.x, gsize.z])
	verdict("2d коллайдер земли совпадает с полем",
		absf(gsize.x - hx * 2.0) < 0.01 and absf(gsize.z - hz * 2.0) < 0.01,
		"%.1f × %.1f" % [gsize.x, gsize.z])

	# Ничего не должно торчать за границу — проверка ПО КАЖДОЙ ОСИ ОТДЕЛЬНО:
	# при прямоугольнике общий максимум по модулю ни о чём не говорит
	var out_cnt := 0
	var far_x := 0.0
	var far_z := 0.0
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var p: Vector3 = (n as Node3D).global_position
		far_x = maxf(far_x, absf(p.x))
		far_z = maxf(far_z, absf(p.z))
		if absf(p.x) > hx or absf(p.z) > hz:
			out_cnt += 1
	print("  самый дальний объект: по X %.1f (предел %.1f), по Z %.1f (предел %.1f)" % [
		far_x, hx, far_z, hz])
	verdict("2e ничего не вылезло за границу поля", out_cnt == 0,
		"за краем объектов: %d" % out_cnt)
	verdict("2f длинная ось реально засеяна до края",
		far_x > hx - 20.0, "самый дальний по X %.1f при пределе %.1f" % [far_x, hx])

	# ── ДИАГОНАЛЬНЫЕ СПАУНЫ ─────────────────────────────────────────────────
	var pa: Vector3 = main.PLAYER_BASE_ANCHOR
	var ea: Vector3 = main.ENEMY_BASE_ANCHOR
	print("  базы: игрок (%.1f, %.1f), ИИ (%.1f, %.1f), между ними %.1f м" % [
		pa.x, pa.z, ea.x, ea.z, pa.distance_to(ea)])
	verdict("2g игрок в НИЖНЕМ ЛЕВОМ углу", pa.x < 0.0 and pa.z < 0.0,
		"(%.1f, %.1f)" % [pa.x, pa.z])
	verdict("2h ИИ в ВЕРХНЕМ ПРАВОМ углу", ea.x > 0.0 and ea.z > 0.0,
		"(%.1f, %.1f)" % [ea.x, ea.z])
	verdict("2i базы симметричны относительно центра",
		absf(pa.x + ea.x) < 0.01 and absf(pa.z + ea.z) < 0.01,
		"сумма (%.2f, %.2f)" % [pa.x + ea.x, pa.z + ea.z])
	# Якорь обязан сидеть в углу, а не «где-то на своей половине»
	var inset_x: float = hx - absf(pa.x)
	var inset_z: float = hz - absf(pa.z)
	print("  отступ базы игрока от углового края: %.1f м по X, %.1f м по Z" % [inset_x, inset_z])
	verdict("2j базы прижаты к углам, а не размазаны по половине карты",
		inset_x < hx * 0.35 and inset_z < hz * 0.5,
		"отступы %.1f / %.1f при полуосях %.1f / %.1f" % [inset_x, inset_z, hx, hz])

	# ── ЗАМОК ИИ СТОИТ РОВНО В СВОЁМ ЯКОРЕ ──────────────────────────────────
	var ec: Node3D = null
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if b is Castle:
			ec = b
			break
	var off: float = 999.0
	if ec != null:
		off = Vector2(ec.global_position.x - ea.x, ec.global_position.z - ea.z).length()
	print("  замок ИИ в (%.1f, %.1f), отклонение от якоря %.2f м" % [
		ec.global_position.x if ec != null else 0.0,
		ec.global_position.z if ec != null else 0.0, off])
	verdict("2k замок ИИ стоит в верхнем правом углу, в своём якоре",
		ec != null and off < 0.01, "отклонение %.2f м" % off)

	# ── ЗОНА ПОСТАНОВКИ ЗАМКА ИГРОКА ────────────────────────────────────────
	var far_click: Vector2 = main.clamp_to_player_start(ea.x, ea.z)
	var near_click: Vector2 = main.clamp_to_player_start(pa.x + 5.0, pa.z + 5.0)
	print("  клик у базы ИИ (%.1f, %.1f) зажат в (%.1f, %.1f); клик у своей базы остался (%.1f, %.1f)" % [
		ea.x, ea.z, far_click.x, far_click.y, near_click.x, near_click.y])
	verdict("2l замок игрока нельзя поставить на половине ИИ",
		far_click.x < 0.0 and far_click.y < 0.0,
		"зажат в (%.1f, %.1f)" % [far_click.x, far_click.y])
	verdict("2m рядом со своим углом место выбирается свободно",
		absf(near_click.x - (pa.x + 5.0)) < 0.01 and absf(near_click.y - (pa.z + 5.0)) < 0.01,
		"(%.1f, %.1f)" % [near_click.x, near_click.y])

# ═════════════════════════════════════════════════════════════════════════════
# 3. ОЗЕРО И УТКА ОТКЛЮЧЕНЫ
# ═════════════════════════════════════════════════════════════════════════════
func _t3_lake() -> void:
	print("\n═════ 3. ОЗЕРО ═════")
	verdict("3a флаг озера выключен", not main.LAKE_ENABLED)

	# Сплошная проба по всей карте: воды не должно быть нигде
	var wet := 0
	var probes := 0
	var hx: float = main.MAP_HALF_X
	var hz: float = main.MAP_HALF_Z
	var sx: float = hx / 24.0
	var sz: float = hz / 24.0
	var x: float = -hx
	while x <= hx:
		var z: float = -hz
		while z <= hz:
			probes += 1
			if GameManager.is_water(x, z):
				wet += 1
			z += sz
		x += sx
	print("  проб по карте: %d, из них вода: %d" % [probes, wet])
	verdict("3b воды на карте нет ни в одной точке", wet == 0, "мокрых проб %d из %d" % [wet, probes])

	verdict("3c утка не создана", main._duck_node == null)
	var lake: Node = _find(main, "Lake")
	verdict("3d узла озера нет в сцене", lake == null,
		"найден узел: %s" % (lake.name if lake != null else "нет"))

	# Центр карты должен быть проходимой сушей
	# Ставим бойца по ту сторону бывшего озера и гоним сквозь его центр.
	# Запас по времени большой: скорость копейщика 2 м/с, а на марше строем
	# и вдвое меньше — на 6 с он просто не успевал дойти, и проверка врала
	var u := _spawn("spearman", Constants.FACTION_PLAYER, Vector3(-33.0, 0.0, -22.0))
	await frames(3)
	u.command_move(Vector3(-14.0, 0.0, -4.0))
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
		if Vector2(u.global_position.x + 14.0, u.global_position.z + 4.0).length() < 1.5:
			break
	var left: float = Vector2(u.global_position.x + 14.0, u.global_position.z + 4.0).length()
	print("  проход через бывшее озеро: осталось %.2f м до цели за %.1f с" % [
		left, float(Time.get_ticks_msec() - t0) / 1000.0])
	verdict("3e центр карты стал проходимой сушей", left < 1.5, "осталось %.2f м" % left)
	u.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# 4. КРАЙ МИРА
# ═════════════════════════════════════════════════════════════════════════════
func _t4_bounds() -> void:
	print("\n═════ 4. ГРАНИЦЫ И ОФОРМЛЕНИЕ КРАЯ ═════")
	# Пределы РАЗНЫЕ по осям: карта прямоугольная. Общий «half» здесь дал бы
	# заведомо зелёную проверку по короткой оси и пропустил бы дыру
	var hx: float = main.MAP_HALF_X
	var hz: float = main.MAP_HALF_Z
	var lim: float   = hx - main.MAP_EDGE_MARGIN
	var lim_z: float = hz - main.MAP_EDGE_MARGIN

	# ── ПРИКАЗ ЗА КРАЙ ──────────────────────────────────────────────────────
	var t: Vector3 = GameManager.land_target(Vector3(500.0, 0.0, -400.0))
	print("  приказ в (500, −400) превращён в (%.1f, %.1f), пределы ±%.1f / ±%.1f" % [
		t.x, t.z, lim, lim_z])
	verdict("4a приказ за карту зажимается в границы",
		absf(t.x) <= lim + 0.01 and absf(t.z) <= lim_z + 0.01,
		"(%.1f, %.1f)" % [t.x, t.z])

	# ── ЮНИТ ИДЁТ НА КРАЙ И УПИРАЕТСЯ ───────────────────────────────────────
	var u := _spawn("spearman", Constants.FACTION_PLAYER, Vector3(lim - 12.0, 0.0, 0.0))
	await frames(3)
	u.move_target = Vector3(hx + 60.0, 0.0, 0.0)   # приказ МИМО зажима, в лоб
	u.state = Unit.State.MOVING
	var t0: int = Time.get_ticks_msec()
	var max_x := 0.0
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		max_x = maxf(max_x, u.global_position.x)
	print("  боец шёл в стену 8 с: дальше всего ушёл на x=%.2f (предел %.2f)" % [max_x, lim])
	verdict("4b юнит упирается в край и не проваливается",
		max_x <= lim + 0.01, "дошёл до %.2f при пределе %.2f" % [max_x, lim])
	verdict("4c юнит дошёл до самого края (стена не срабатывает раньше времени)",
		max_x > lim - 1.0, "дошёл до %.2f" % max_x)

	# ── ЮНИТ, ПОСТАВЛЕННЫЙ ЗА КРАЕМ, ВОЗВРАЩАЕТСЯ ───────────────────────────
	u.global_position = Vector3(hx + 30.0, 0.0, hz + 30.0)
	u.command_move(Vector3(0.0, 0.0, 0.0))
	await frames(30)
	var back: bool = absf(u.global_position.x) <= lim + 0.01 \
		and absf(u.global_position.z) <= lim_z + 0.01
	print("  бойца телепортировали за край → через 30 кадров он в (%.1f, %.1f)" % [
		u.global_position.x, u.global_position.z])
	verdict("4d боец, оказавшийся за краем, возвращается на поле", back,
		"(%.1f, %.1f)" % [u.global_position.x, u.global_position.z])

	# ── ТОЛЧОК НЕ ВЫБИВАЕТ ЗА КРАЙ ──────────────────────────────────────────
	var pusher := _spawn("spearman", Constants.FACTION_ENEMY, Vector3(lim - 2.0, 0.0, 0.0))
	var pushed := _spawn("spearman", Constants.FACTION_PLAYER, Vector3(lim - 0.5, 0.0, 0.0))
	await frames(3)
	var dirn := Vector3(1.0, 0.0, 0.0)
	for _i in range(120):
		pusher._apply_push(pushed, dirn)
	print("  120 толчков в стену: боец стоит на x=%.2f (предел %.2f)" % [
		pushed.global_position.x, lim])
	verdict("4e толканием за край не выдавливает",
		pushed.global_position.x <= lim + 0.01,
		"x=%.2f" % pushed.global_position.x)

	# ── РАССТАЛКИВАНИЕ ТОЛПЫ У КРАЯ ─────────────────────────────────────────
	var crowd: Array = []
	for i in range(40):
		var s := _spawn("spearman", Constants.FACTION_PLAYER,
			Vector3(lim - 0.6 + float(i % 4) * 0.15, 0.0, -6.0 + float(i / 4) * 0.3))
		crowd.append(s)
	await frames(90)
	var out_cnt := 0
	var worst := 0.0
	for c in crowd:
		var p: Vector3 = (c as Node3D).global_position
		worst = maxf(worst, absf(p.x))
		if absf(p.x) > lim + 0.01 or absf(p.z) > lim_z + 0.01:
			out_cnt += 1
	print("  толпа из 40 у самой стены: за краем %d, дальше всех %.2f" % [out_cnt, worst])
	verdict("4f расталкивание не выдавливает толпу за край", out_cnt == 0,
		"за краем %d из 40" % out_cnt)
	for c in crowd:
		(c as Node).queue_free()
	u.queue_free(); pusher.queue_free(); pushed.queue_free()
	await frames(3)

	# ── ОФОРМЛЕНИЕ: БОРТИК И ЧЕРНОТА ────────────────────────────────────────
	var vd: Node = _find(main, "WorldVoid")
	var bv: Node = _find(main, "WorldBevel")
	var wl: Node = _find(main, "WorldWalls")
	var void_y := 0.0
	var void_size := Vector2.ZERO
	if vd != null:
		void_y = (vd as Node3D).global_position.y
		if (vd as MeshInstance3D).mesh is PlaneMesh:
			void_size = ((vd as MeshInstance3D).mesh as PlaneMesh).size
	print("  чернота: узел=%s, y=%.2f, размер %.0f×%.0f" % [
		str(vd != null), void_y, void_size.x, void_size.y])
	verdict("4g чёрная зона за краем создана и лежит НИЖЕ поля",
		vd != null and void_y < -0.1, "y=%.2f" % void_y)
	verdict("4h чернота заведомо больше карты",
		void_size.x > hx * 4.0, "%.0f при полуоси карты %.1f" % [void_size.x, hx])

	var bev_aabb := AABB()
	if bv != null:
		bev_aabb = (bv as MeshInstance3D).get_aabb()
	print("  бортик: габарит по X %.1f..%.1f, по Z %.1f..%.1f, по Y %.2f..%.2f" % [
		bev_aabb.position.x, bev_aabb.position.x + bev_aabb.size.x,
		bev_aabb.position.z, bev_aabb.position.z + bev_aabb.size.z,
		bev_aabb.position.y, bev_aabb.position.y + bev_aabb.size.y])
	verdict("4i зелёный бортик идёт по краю поля наружу ПО ОБЕИМ ОСЯМ",
		bv != null and absf(bev_aabb.position.x + hx + main.MAP_BEVEL) < 0.01
			and absf(bev_aabb.position.z + hz + main.MAP_BEVEL) < 0.01,
		"внешний край X %.2f (ждали %.2f), Z %.2f (ждали %.2f)" % [
			bev_aabb.position.x, -(hx + main.MAP_BEVEL),
			bev_aabb.position.z, -(hz + main.MAP_BEVEL)])
	verdict("4j бортик опускается в черноту",
		bv != null and absf(bev_aabb.position.y + main.MAP_BEVEL_DROP) < 0.01,
		"низ бортика %.2f" % bev_aabb.position.y)

	var walls := 0
	if wl != null:
		walls = wl.get_child_count()
	print("  физические стены: узел=%s, сегментов %d" % [str(wl != null), walls])
	verdict("4k по периметру стоят физические стены", wl != null and walls == 4,
		"сегментов %d" % walls)
