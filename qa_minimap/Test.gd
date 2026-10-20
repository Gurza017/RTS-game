extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: МИНИ-КАРТА (ТЗ 10.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A1 есть и видна; A2 в правом нижнем углу экрана
##   B1 точка отряда игрока его цветом; B2 красный в тумане не виден;
##   B3 без тумана красный — красным; B4 гоблины — оранжевым; B5 своя постройка
##   C1 ЛКМ по мини-карте ставит камеру в точку; C2 выделение не сброшено
##       (клик не провалился в мир)
##   D1 ПКМ с выделенным отрядом — приказ в соответствующую точку (post_pos);
##   D2 ПКМ при взведённом [A] — отряд в Attack-Move; D3 режим [A] снят;
##   D4 ЛКМ при взведённом [A] — Attack-Move, камера не прыгает
##   E1 цена обновления на ~3000 бойцах < 1.5 мс; E2 точек столько, сколько живых
##
## Запуск: godot --headless --path . res://qa_minimap/Test.tscn

var main = null
var sm = null
var mm = null
var _pass: int = 0
var _fail: int = 0
var _done: bool = false

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(300.0)
	t.timeout.connect(func():
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("ИТОГ qa_minimap: прошло %d, провалов: %d" % [_pass, _fail])
	get_tree().quit()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai", "cav_commander"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
			n.set_physics_process(false)
	await frames(4)
	mm = main.get("minimap")
	verdict("A1", mm != null and is_instance_valid(mm) and mm.visible, "мини-карта есть")
	if mm == null:
		_finish()
		return
	mm.bake_now()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var r: Rect2 = mm.panel_rect()
	verdict("A2", r.end.x > vs.x - 20.0 and r.end.x <= vs.x and r.end.y > vs.y - 20.0
		and r.end.y <= vs.y and r.size.x >= 180.0,
		"панель %s, экран %s" % [r, vs])

	await _markers()
	await _input_checks()
	await _perf()
	_finish()

# ── B: МАРКЕРЫ ───────────────────────────────────────────────────────────────

var _pl_sid: int = 0

func _clear_near(p: Vector3, rad: float) -> void:
	for u in GameManager._live_units.duplicate():
		if u != null and is_instance_valid(u) and (u as Node3D).position.distance_to(p) < rad:
			u.queue_free()

func _count_color(world: Vector3, col: Color, half: int = 2) -> int:
	var img: Image = mm.image()
	var c: Vector2 = mm.world_to_map(world)
	var n := 0
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var x: int = int(c.x) + dx
			var y: int = int(c.y) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var p: Color = img.get_pixel(x, y)
			if absf(p.r - col.r) + absf(p.g - col.g) + absf(p.b - col.b) < 0.08:
				n += 1
	return n

func _markers() -> void:
	var pp := Vector3(-40.0, 0.0, 30.0)
	var rp := Vector3(60.0, 0.0, 30.0)
	var gp := Vector3(10.0, 0.0, -70.0)
	for p in [pp, rp, gp]:
		_clear_near(p, 20.0)
	await pframes(2)
	_pl_sid = main._spawn_squad_block("spearman", Constants.FACTION_PLAYER, pp,
		Vector3.FORWARD, Vector3.RIGHT, 12, 4, 1.0)
	main._spawn_squad_block("spearman", Constants.FACTION_ENEMY, rp,
		Vector3.FORWARD, Vector3.RIGHT, 12, 4, 1.0)
	main._spawn_squad_block("goblin_spearman", Constants.FACTION_GOBLIN, gp,
		Vector3.FORWARD, Vector3.RIGHT, 12, 4, 1.2)
	await pframes(6)
	await frames(20)          # туман пересчитан (раз в 0.15 с)
	mm.refresh_buildings()
	mm.refresh()
	var pal: Array = mm.PAL
	var pl_c: Vector3 = _squad_centre(_pl_sid)
	verdict("B1", _count_color(pl_c, pal[0]) >= 2, "точек игрока %d" % _count_color(pl_c, pal[0]))
	var fog = GameManager.fog
	var lit_red: bool = fog != null and fog.enabled and fog.is_lit(rp.x, rp.z - 1.0)
	var red_in_fog: int = _count_color(rp + Vector3(0, 0, 1.5), pal[1])
	verdict("B2", lit_red or red_in_fog == 0, "красных точек в тумане %d (освещено=%s)" % [red_in_fog, lit_red])
	if fog != null:
		fog.enabled = false
	mm.refresh_buildings()
	mm.refresh()
	var red_n: int = _count_color(rp + Vector3(0, 0, 1.5), pal[1])
	verdict("B3", red_n >= 2, "красных точек без тумана %d" % red_n)
	var gob_n: int = _count_color(gp + Vector3(0, 0, 1.8), pal[2])
	verdict("B4", gob_n >= 2, "оранжевых точек %d" % gob_n)
	# Своя постройка ставится стендом: стартовой крепости у игрока может не
	# быть (старт — банк под список построек)
	var keep := Castle.new()
	keep.faction = Constants.FACTION_PLAYER
	main.world_add(keep)
	keep.global_position = Vector3(-120.0, GameManager.get_terrain_height(-120.0, -60.0), -60.0)
	_clear_near(keep.position, 12.0)
	await pframes(3)
	mm.refresh_buildings()
	mm.refresh()
	var b_n: int = _count_color(keep.position, pal[4], 3) if keep != null else 0
	var dbg: String = ""
	if keep != null:
		var c: Vector2 = mm.world_to_map(keep.position)
		dbg = " %s @%s px %s цвет %s меток %d" % [keep.name, keep.position, c,
			mm.image().get_pixel(int(c.x), int(c.y)), mm._marks.size() / 4]
	verdict("B5", keep != null and b_n >= 3, "пикселей своей постройки %d%s" % [b_n, dbg])
	if fog != null:
		fog.enabled = true

func _squad_centre(sid: int) -> Vector3:
	var c: Vector2 = GameManager.squad_centre_xz(sid)
	return Vector3(c.x, 0.0, c.y)

# ── C, D: ВВОД ───────────────────────────────────────────────────────────────

func _click(world: Vector3, button: int) -> void:
	var r: Rect2 = mm.map_rect()
	var mp: Vector2 = mm.world_to_map(world)
	var sp: Vector2 = r.position + mp + Vector2(0.5, 0.5)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = sp
		e.global_position = sp
		e.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT
			else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
		get_viewport().push_input(e, true)
		await frames(1)

func _median_post(sid: int) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for m in GameManager.squads[sid]["members"]:
		if m != null and is_instance_valid(m):
			xs.append((m as Unit).post_pos.x)
			zs.append((m as Unit).post_pos.z)
	if xs.is_empty():
		return Vector3.INF
	xs.sort(); zs.sort()
	return Vector3(xs[xs.size() / 2], 0.0, zs[zs.size() / 2])

func _input_checks() -> void:
	var cam = main.get("_camera")
	var members: Array = (GameManager.squads[_pl_sid]["members"] as Array).duplicate()
	sm.select_units(members)
	await frames(2)
	# C1: ЛКМ — камера в точку
	var tgt := Vector3(12.0, 0.0, -8.0)
	await _click(tgt, MOUSE_BUTTON_LEFT)
	var f: Vector3 = cam._focus
	var err: float = Vector2(f.x - tgt.x, f.z - tgt.z).length()
	verdict("C1", err < 3.0, "фокус %s, цель %s, ошибка %.2f м (пиксель карты %.2f м)" % [f, tgt, err, 2.0 * mm._half_x / mm.MAP_W])
	verdict("C2", sm.selected_units.size() == members.size(),
		"выделено %d из %d после клика по мини-карте" % [sm.selected_units.size(), members.size()])
	# D1: ПКМ — марш в точку
	var dst := Vector3(-20.0, 0.0, 50.0)
	await _click(dst, MOUSE_BUTTON_RIGHT)
	await pframes(2)
	var mp: Vector3 = _median_post(_pl_sid)
	var d1: float = Vector2(mp.x - dst.x, mp.z - dst.z).length() if mp != Vector3.INF else 999.0
	verdict("D1", d1 < 6.0, "медиана post_pos %s, точка %s, %.2f м" % [mp, dst, d1])
	# D2/D3: ПКМ при [A]
	sm.set_attack_move_armed(true)
	var dst2 := Vector3(-10.0, 0.0, 60.0)
	await _click(dst2, MOUSE_BUTTON_RIGHT)
	await pframes(2)
	var cmd = sm.squad_commander()
	verdict("D2", cmd.is_attack_moving(_pl_sid), "Attack-Move после ПКМ по мини-карте")
	var amd: Vector3 = cmd.attack_move_dest(_pl_sid)
	verdict("D3", not sm.attack_move_armed and amd != Vector3.INF
		and Vector2(amd.x - dst2.x, amd.z - dst2.z).length() < 3.0,
		"режим снят=%s, точка %s" % [not sm.attack_move_armed, amd])
	# D4: ЛКМ при [A]
	cmd.cancel_squad(_pl_sid)
	var f0: Vector3 = cam._focus
	sm.set_attack_move_armed(true)
	var dst3 := Vector3(-60.0, 0.0, -40.0)
	await _click(dst3, MOUSE_BUTTON_LEFT)
	await pframes(2)
	var f1: Vector3 = cam._focus
	# Камера не прыгнула в точку клика (сдвиг на метр — довод зума у границы)
	var to_dst: float = Vector2(f1.x - dst3.x, f1.z - dst3.z).length()
	verdict("D4", cmd.is_attack_moving(_pl_sid) and to_dst > 20.0 and f0.distance_to(f1) < 3.0,
		"Attack-Move=%s, камера сдвинулась на %.2f м, до точки клика %.1f м" % [cmd.is_attack_moving(_pl_sid), f0.distance_to(f1), to_dst])
	cmd.cancel_squad(_pl_sid)

# ── E: ЦЕНА ──────────────────────────────────────────────────────────────────

func _perf() -> void:
	var t0: int = Time.get_ticks_msec()
	var fac := [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY, Constants.FACTION_GOBLIN]
	var uids := ["spearman", "spearman", "goblin_spearman"]
	var k := 0
	for ix in range(10):
		for iz in range(5):
			var f: int = fac[k % 3]
			var p := Vector3(-180.0 + ix * 38.0, 0.0, -100.0 + iz * 45.0)
			main._spawn_squad_block(uids[k % 3], f, p, Vector3.FORWARD, Vector3.RIGHT, 60, 10, 1.0)
			k += 1
	await pframes(4)
	# Живые НА КАРТЕ: гарнизон (снят FPosValid) мини-карта не показывает
	var live: int = 0
	var army = GameManager.army
	for u in GameManager._live_units:
		if u == null or not is_instance_valid(u) or (u as Unit).is_dead() \
				or (u as Unit).is_queued_for_deletion() or (u as Unit)._soa < 0:
			continue
		var fl: int = army.flags_of((u as Unit)._soa)
		if (fl & 1) != 0 and (fl & (1 << 6)) == 0:
			live += 1
	print("  заспавнено за %d мс, живых %d" % [Time.get_ticks_msec() - t0, live])
	var fog = GameManager.fog
	var costs: Array = []
	for fog_on in [false, true]:
		if fog != null:
			fog.enabled = fog_on
		costs.clear()
		for i in range(15):
			mm.refresh()
			costs.append(mm.last_update_usec)
			await frames(1)
		costs.sort()
		print("  туман=%s: обновление медиана %d мкс, худшее %d мкс, точек %d" % [fog_on, costs[7], costs[14], mm.last_dots])
		if not fog_on:
			verdict("E2", mm.last_dots >= live - 5, "точек %d при живых %d" % [mm.last_dots, live])
	verdict("E1", int(costs[7]) < 1500, "медиана %d мкс" % costs[7])
	var bt: int = Time.get_ticks_usec()
	mm.refresh_buildings()
	print("  сбор построек %d мкс" % (Time.get_ticks_usec() - bt))
