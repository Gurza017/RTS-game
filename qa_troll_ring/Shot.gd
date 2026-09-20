extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СТЕНД: У ТРОЛЛЯ ПОД НОГАМИ РОВНО ОДНО КОЛЬЦО (спринт 16, блок 3)
## ═══════════════════════════════════════════════════════════════════════════
## СКРИНШОТ ВЛАДЕЛЬЦА: под троллем три красных круга — толстая дуга у ног и
## тонкий овал в стороне. Причина была в покадровом обновлении наведения
## (SelectionDecalRenderer._update_hover_positions): индекс слота ТОНКОГО
## слоя писался в ГРУБЫЙ слой грубым масштабом — третье кольцо, а настоящее
## оставалось на месте постановки.
##
## Стенд наводит курсорное кольцо на ИДУЩЕГО тролля (без движения покадровый
## путь не работает вовсе) и считает ЖИВЫЕ слоты во всех слоях колец в
## радиусе 6 м от него — по буферам ядра (rb_slot), а не по картинке:
##   A — только наведение: ровно ОДИН слот, и он в тонком слое;
##   B — наведение плюс приказ: два слота (одно кольцо на каждое), в грубых
##       слоях по-прежнему ноль.
## Снимок — для глаза. Запуск:
##   godot --path . res://qa_troll_ring/Shot.tscn -- --out=<путь без .png>

var main = null
var _out: String = ""
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 120 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_troll_ring: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

## Ровная площадка рядом с base: перепад высот в круге 6 м наименьший
func _flat_spot(base: Vector3, span: float) -> Vector3:
	var best: Vector3 = base
	var best_d: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * span, 0.0, base.z + float(iz) * span)
			var lo := 1e9
			var hi := -1e9
			var wet := false
			for d in [Vector3.ZERO, Vector3(6.0, 0.0, 0.0), Vector3(-6.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 6.0), Vector3(0.0, 0.0, -6.0)]:
				var h: float = GameManager.get_terrain_height(p.x + d.x, p.z + d.z)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				if main.is_water(p.x + d.x, p.z + d.z):
					wet = true
			if hi - lo < best_d and not wet:
				best_d = hi - lo
				best = p
	print("  площадка стенда: %s (перепад %.2f м)" % [str(best), best_d])
	return best

## Живые слоты слоя (ненулевой базис) в радиусе r от точки p
func _live_slots(lay, p: Vector3, r: float) -> int:
	if lay == null or lay.core_id < 0:
		return 0
	var n := 0
	for i in range(lay.capacity):
		var s: PackedFloat32Array = GameManager.army.rb_slot(lay.core_id, i)
		if s.size() < 12:
			continue
		var basis_sq: float = 0.0
		for k in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
			basis_sq += s[k] * s[k]
		if basis_sq < 1e-6:
			continue
		var dx: float = s[3] - p.x
		var dz: float = s[11] - p.z
		if dx * dx + dz * dz <= r * r:
			n += 1
	return n

## Слоты по всем слоям колец: [грубые (hover + order), тонкие (hover_b + order_b), выделение]
func _count_rings(p: Vector3) -> Array:
	var d = GameManager.sel_decals
	var coarse: int = _live_slots(d._hover, p, 6.0) + _live_slots(d._order_ring, p, 6.0)
	var fine: int = _live_slots(d._hover_b, p, 6.0) + _live_slots(d._order_ring_b, p, 6.0)
	var sel: int = _live_slots(d._rings, p, 6.0)
	return [coarse, fine, sel]

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1600, 900)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	var lair = GameManager.troll_lair
	var troll: Unit = null
	if lair != null:
		for t in lair.trolls:
			if is_instance_valid(t):
				troll = t
				break
	if troll == null:
		verdict("A0 тролль на карте есть", false)
		_finish()
		return
	# Чистое поле, стражам логова здесь делать нечего
	if lair.has_method("set"):
		lair.set("aggro_enabled", false)
	# Ровная сухая площадка у базы игрока: (0, −40) прежних снимков лежит в
	# русле, и кольцо там прячется под зеркалом воды; площадка ищется по
	# рельефу (правило «сценарий ставит окружение сам»)
	var base: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(30.0, 0.0, 30.0), 8.0)
	# Лес сеется случайно: площадку чистим сами, иначе кольцо прячется за
	# кронами (правило «сценарий ставит окружение сам»)
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n0 as Node3D
		if rn != null and is_instance_valid(rn) and Vector2(rn.global_position.x - base.x,
				rn.global_position.z - base.z).length() < 40.0:
			rn.queue_free()
	await pframes(6)
	troll.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z)
	troll.sync_row()
	main.focus_camera_on(base + Vector3(0.0, 0.0, 1.5))
	await frames(4)
	(main._camera as Node).set_process(false)
	(get_viewport().get_camera_3d() as Camera3D).size = 22.0
	# Курсор игрока «стоит» на тролле: тот же вход, что у опроса курсора в Main
	main.set_process(false)   # чтобы опрос курсора не гасил наведение
	await pframes(2)

	print("\n═════ A. ТОЛЬКО НАВЕДЕНИЕ, ТРОЛЛЬ ИДЁТ ═════")
	GameManager.sel_decals.set_hover_units([troll], main.world_root())
	# Тролль ИДЁТ — только так работает покадровый путь, который и рисовал
	# лишние кольца. Пинать его нельзя: заморозка гасит ту самую ветку
	troll.command_move(GameManager.land_target(base + Vector3(5.0, 0.0, 0.0)))
	var worst_coarse := 0
	var worst_fine := 0
	var moved := 0.0
	var start: Vector3 = troll.global_position
	for _i in range(60):
		await get_tree().physics_frame
		await get_tree().process_frame
		var c: Array = _count_rings(troll.global_position)
		worst_coarse = maxi(worst_coarse, int(c[0]))
		worst_fine = maxi(worst_fine, int(c[1]))
		moved = maxf(moved, Vector2(troll.global_position.x - start.x,
			troll.global_position.z - start.z).length())
	var cnt: Array = _count_rings(troll.global_position)
	print("  прошёл %.2f м; сейчас: грубых %d, тонких %d, выделения %d; худшее за ход: грубых %d, тонких %d" % [
		moved, cnt[0], cnt[1], cnt[2], worst_coarse, worst_fine])
	verdict("A1 тролль за время замера шёл (покадровый путь работал)", moved > 0.5,
		"%.2f м" % moved)
	verdict("A2 под идущим троллем РОВНО ОДНО кольцо наведения", int(cnt[0]) + int(cnt[1]) == 1,
		"грубых %d + тонких %d" % [cnt[0], cnt[1]])
	verdict("A3 и оно в ТОНКОМ слое (64 сегмента), не в грубом", int(cnt[1]) == 1 and int(cnt[0]) == 0)
	verdict("A4 ни в одном кадре хода лишнего кольца не было",
		worst_coarse == 0 and worst_fine <= 1,
		"худшее: грубых %d, тонких %d" % [worst_coarse, worst_fine])
	# Ступни на кольце и на ходу ВПРАВО (лента зеркалится): замер тем же
	# способом, что в блоке C, кольцо на время пары снимков снято
	_collect_layers(get_tree().root)
	GameManager.sel_decals.clear_hover()
	await frames(2)
	var right_d: float = await _bottom_vs_ring(troll, cam_now())
	var sl0 = GameManager.far_units.slot_of(troll)
	print("  на ходу вправо: низ рисунка относительно центра кольца %.2f м, зеркало=%s, |v|=%.2f" % [
		right_d, str(sl0.mirror) if sl0 != null else "-", troll.velocity.length()])
	verdict("A5 и на ходу вправо ступни на кольце", right_d > -90.0 and right_d >= -0.35 and right_d <= 1.5,
		"%.2f м" % right_d)
	GameManager.sel_decals.set_hover_units([troll], main.world_root())
	if _out != "":
		await frames(2)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out + ".png")
		print("  снимок: %s.png" % _out)

	print("\n═════ B. НАВЕДЕНИЕ + ПРИКАЗ ═════")
	GameManager.sel_decals.set_order_targets([troll], main.world_root())
	troll.command_move(GameManager.land_target(base + Vector3(0.0, 0.0, 4.0)))
	worst_coarse = 0
	var worst_total := 0
	for _i in range(45):
		await get_tree().physics_frame
		await get_tree().process_frame
		# Метку приказа за живой целью везёт GameManager (set_order_targets
		# каждый кадр); здесь она задаётся стендом и переписывается им же
		GameManager.sel_decals.set_order_targets([troll], main.world_root())
		var c: Array = _count_rings(troll.global_position)
		worst_coarse = maxi(worst_coarse, int(c[0]))
		worst_total = maxi(worst_total, int(c[0]) + int(c[1]))
	cnt = _count_rings(troll.global_position)
	print("  сейчас: грубых %d, тонких %d; худшее: грубых %d, всего %d" % [
		cnt[0], cnt[1], worst_coarse, worst_total])
	verdict("B1 наведение и приказ — два кольца, по одному на каждое, оба тонкие",
		int(cnt[1]) == 2 and int(cnt[0]) == 0, "тонких %d, грубых %d" % [cnt[1], cnt[0]])
	verdict("B2 третьего кольца не появлялось ни в одном кадре", worst_total <= 2 and worst_coarse == 0,
		"худшее всего %d, грубых %d" % [worst_total, worst_coarse])
	GameManager.sel_decals.clear_hover()
	GameManager.sel_decals.set_order_targets([], null)
	await frames(2)
	cnt = _count_rings(troll.global_position)
	verdict("B3 сняли наведение и приказ — колец нет", int(cnt[0]) + int(cnt[1]) == 0,
		"осталось %d" % (int(cnt[0]) + int(cnt[1])))

	print("\n═════ C. КОЛЬЦО ЛЕЖИТ ПОД НОГАМИ, А НЕ ПЕРЕД НИМИ ═════")
	# Тролль стоит; кольцо наведения снова на нём. Сравниваем ЭКРАННУЮ точку
	# земли тролля (там лежит центр кольца) с нижней кромкой его РИСУНКА —
	# разностью снимков «слои армии погашены / показаны», как в qa_visual_smoke
	troll.command_move(GameManager.land_target(troll.global_position))
	await pframes(30)
	GameManager.sel_decals.set_hover_units([troll], main.world_root())
	await frames(3)
	var cam: Camera3D = get_viewport().get_camera_3d()
	_collect_layers(get_tree().root)
	for l in _unit_layers:
		l.visible = false
	var bg: Image = await _grab()
	for l in _unit_layers:
		l.visible = true
	var fg: Image = await _grab()
	var gp: Vector2 = cam.unproject_position(troll.draw_position())
	var px_per_m: float = float(fg.get_height()) / cam.size
	var ground_px_per_m: float = px_per_m * 0.7071   # метр по земле под камерой в 45°
	var x0: int = maxi(int(gp.x) - 40, 0)
	var x1: int = mini(int(gp.x) + 40, fg.get_width())
	var y0: int = maxi(int(gp.y) - 320, 0)
	var y1: int = mini(int(gp.y) + 100, fg.get_height())
	var y_bottom := -1
	var y_top := -1
	for y in range(y0, y1):
		var n := 0
		for x in range(x0, x1):
			var a: Color = bg.get_pixel(x, y)
			var b: Color = fg.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) >= 0.08:
				n += 1
		if n >= 3:
			y_bottom = y
			if y_top < 0:
				y_top = y
	var d_m: float = float(y_bottom - int(gp.y)) / ground_px_per_m if y_bottom >= 0 else -99.0
	# Что доехало до шейдера — печатается для разбора
	var sf: Array = troll.sheet_frame()
	var slot = GameManager.far_units.slot_of(troll)
	if sf.size() >= 5 and slot != null and slot.bucket != null:
		var qm := slot.bucket.mm.mesh as QuadMesh
		print("  лента %s px=%.4f base_y=%.3f foot_drop=%.3f квад %.2fx%.2f м" % [
			str((sf[0] as Texture2D).get_size()), float(sf[3]), slot.base_y, slot.bucket._foot, qm.size.x, qm.size.y])
	print("  точка земли на экране y=%.0f; рисунок тролля: верх y=%d, низ y=%d; низ относительно центра кольца %.2f м по земле (плюс — ниже кольца)" % [
		gp.y, y_top, y_bottom, d_m])
	verdict("C0 рисунок тролля найден на снимке", y_bottom >= 0)
	# Нижняя кромка РИСУНКА — это край впечатанной в арт полупрозрачной тени
	# (у тролля 15 строк под ступнями ≈ 0.8 м по земле). Точка земли стоит на
	# СТУПНЯХ (TROLL_FOOT_ALPHA), значит кромка тени лежит чуть НИЖЕ центра
	# кольца, но не дальше полутора метров; выше центра — ноги над кольцом
	verdict("C1 нижняя кромка рисунка лежит на кольце, а не над ним",
		y_bottom >= 0 and d_m >= -0.15 and d_m <= 1.5, "%.2f м" % d_m)
	if _out != "":
		fg.save_png(_out + "_stand.png")
	# ── И НА ХОДУ: лента ходьбы привязана к земле так же, как покой ────────
	# Именно на марше владелец снял «смещённый тонкий овал»: у ленты ходьбы
	# своё поле под ступнями, и выравнивание между лентами зажато
	# (Unit.BASE_Y_FIX_MAX) — у тролля с крупным пикселем зажим срабатывал
	# Кольцо на время замера снимается: оно едет вместе с троллем, и его
	# сдвиг между двумя снимками попадал бы в разность как «низ рисунка»
	troll.command_move(GameManager.land_target(troll.global_position + Vector3(-25.0, 0.0, 0.0)))
	await pframes(30)
	var d_lp: Vector3 = troll.draw_position()
	var lp: Vector3 = troll.global_position
	var sl = GameManager.far_units.slot_of(troll)
	var q_pos := Vector3.INF
	if sl != null and sl.bucket != null:
		var s: PackedFloat32Array = GameManager.army.rb_slot(sl.bucket.core_id, int(sl.index))
		if s.size() >= 12:
			q_pos = Vector3(s[3], s[7], s[11])
	print("  на ходу: логическая %s, нарисованная %s, начало квада %s; экран земли %s, экран квада %s" % [
		str(lp), str(d_lp), str(q_pos), str(cam.unproject_position(d_lp)),
		str(cam.unproject_position(q_pos)) if q_pos != Vector3.INF else "-"])
	var hs: int = int(GameManager.sel_decals._hover_slot.get(troll, -1))
	var hb = GameManager.sel_decals._hover_b
	if hs >= 0 and hb != null:
		var rs: PackedFloat32Array = GameManager.army.rb_slot(hb.core_id, hs)
		if rs.size() >= 12:
			print("  на ходу: слот кольца %s, экран %s; идёт=%s, |v|=%.2f" % [str(Vector3(rs[3], rs[7], rs[11])),
				str(cam.unproject_position(Vector3(rs[3], rs[7], rs[11]))), str(troll.moved_recently()), troll.velocity.length()])
	# Кольцо на время пары снимков снимается: оно едет с троллем, и его сдвиг
	# между снимками попадал бы в разность; сам тролль в «фоне» погашен слоем
	GameManager.sel_decals.clear_hover()
	await frames(2)
	var walk_d: float = await _bottom_vs_ring(troll, cam)
	print("  на ходу: низ рисунка относительно центра кольца %.2f м" % walk_d)
	verdict("C2 и на ходу ступни на кольце (лента ходьбы выровнена с покоем)",
		walk_d > -90.0 and walk_d >= -0.35 and walk_d <= 1.5, "%.2f м" % walk_d)
	_finish()

## То же ОДНИМ снимком, по впечатанной в арт тени (тёмный овал под ступнями):
## боец на ходу, и разность двух снимков ловила бы его же сдвиг
func _shadow_bottom_vs_ring(u: Unit, cam: Camera3D) -> float:
	var gp: Vector2 = cam.unproject_position(u.draw_position())
	await RenderingServer.frame_post_draw
	var fg: Image = get_viewport().get_texture().get_image()
	var ground_px_per_m: float = float(fg.get_height()) / cam.size * 0.7071
	var x0: int = maxi(int(gp.x) - 60, 0)
	var x1: int = mini(int(gp.x) + 60, fg.get_width())
	var y0: int = maxi(int(gp.y) - 200, 0)
	var y1: int = mini(int(gp.y) + 100, fg.get_height())
	var y_bottom := -1
	for y in range(y0, y1):
		var n := 0
		for x in range(x0, x1):
			var c: Color = fg.get_pixel(x, y)
			if c.r < 0.36 and c.g < 0.58 and c.g > c.r and c.b < 0.4:
				n += 1
		if n >= 6:
			y_bottom = y
	if _out != "":
		fg.save_png(_out + "_walk.png")
	if y_bottom < 0:
		return -99.0
	return float(y_bottom - int(gp.y)) / ground_px_per_m

## Низ рисунка бойца относительно экранной точки его земли, в метрах по земле
## (плюс — ниже кольца). −99 — рисунок на снимке не найден
func _bottom_vs_ring(u: Unit, cam: Camera3D) -> float:
	for l in _unit_layers:
		l.visible = false
	var bg: Image = await _grab()
	for l in _unit_layers:
		l.visible = true
	var fg: Image = await _grab()
	var gp: Vector2 = cam.unproject_position(u.draw_position())
	var ground_px_per_m: float = float(fg.get_height()) / cam.size * 0.7071
	var x0: int = maxi(int(gp.x) - 60, 0)
	var x1: int = mini(int(gp.x) + 60, fg.get_width())
	var y0: int = maxi(int(gp.y) - 320, 0)
	var y1: int = mini(int(gp.y) + 100, fg.get_height())
	var y_bottom := -1
	for y in range(y0, y1):
		var n := 0
		for x in range(x0, x1):
			var a: Color = bg.get_pixel(x, y)
			var b: Color = fg.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) >= 0.08:
				n += 1
		if n >= 3:
			y_bottom = y
	if y_bottom < 0:
		return -99.0
	if _out != "":
		fg.save_png(_out + "_walk.png")
	return float(y_bottom - int(gp.y)) / ground_px_per_m

var _unit_layers: Array = []

func cam_now() -> Camera3D:
	return get_viewport().get_camera_3d()

func _collect_layers(n: Node) -> void:
	var mm := n as MultiMeshInstance3D
	if mm != null and mm.multimesh != null and mm.multimesh.mesh != null:
		var sm := mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
		if sm != null and sm.shader != null \
				and sm.shader.resource_path == "res://shaders/mm_unit_sprite.gdshader":
			_unit_layers.append(mm)
	for c in n.get_children():
		_collect_layers(c)

func _grab() -> Image:
	for _i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()
