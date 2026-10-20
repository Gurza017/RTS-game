extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СТЕНД ТЗ 14.10.2026 (интерфейс, курсоры, силуэты, тела)
## ═══════════════════════════════════════════════════════════════════════════
## Снимки для глаза + вердикты по свойствам, которые видно только в окне:
##   A  крепость достроена — рабочие перед рисунком, а не за ним (п. 1)
##   B  силуэт бойца за башней: пиксели цвета фракции на рисунке башни (п. 1)
##   C  раненая башня — полоска видна без Alt; починена — пропала (п. 5)
##   D  панели: стрелковая, бараки, крепость, загон, рудник; подсказка найма
##      без «ЛКМ/ПКМ»; плашка ресурсов (п. 2)
##   E  курсоры: дверь/запрет/меч/молоток по разбору под курсором (п. 4)
##   F  посадка лучников в башню — башня светлеет (п. 4)
##   G  тела рядом с живыми — снимок (п. 10)
## Запуск: godot --windowed --position -5000,-5000 --path . res://qa_tz1014ui/Shot.tscn -- --out=<путь без .png> bg=1

const F := Constants.FACTION_PLAYER
const _Tower := preload("res://scripts/Tower.gd")
const _Archery := preload("res://scripts/Archery.gd")
const _Site := preload("res://scripts/ConstructionSite.gd")
const _CursorArt := preload("res://scripts/CursorArt.gd")
var main = null
var _out := ""
var _fails := 0
var _checks := 0

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("СТОРОЖ: стенд не уложился в 240 с")
		get_tree().quit())

func verdict(name: String, ok: bool, info: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s  %s" % ["ПРОШЛО" if ok else "НЕ ПРОШЛО", name, info])

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _grab() -> Image:
	await frames(6)
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _shot(suffix: String) -> Image:
	var img: Image = await _grab()
	if not _out.is_empty():
		img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)
	return img

func _crop(img: Image, suffix: String, r: Rect2i) -> void:
	if _out.is_empty():
		return
	var rr := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if rr.size.x <= 0 or rr.size.y <= 0:
		return
	img.get_region(rr).save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

func _place(b: Building, at: Vector3, fac: int = F) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _spawn(kind: String, at: Vector3, fac: int = F) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int = F) -> int:
	var sid: int = GameManager.new_squad(fac, kind)
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % 6) * 0.7, 0, float(k / 6) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
	return sid

## Экранная точка мира (камера заморожена — считать в том же кадре)
func _screen(p: Vector3) -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	return cam.unproject_position(p)

## Пиксели в окрестности экранной точки, близкие к цвету (доля)
func _color_share(img: Image, at: Vector2, half: int, col: Color, tol: float) -> float:
	var sz: Vector2i = img.get_size()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var k: Vector2 = Vector2(sz) / vp
	var cx: int = int(at.x * k.x)
	var cy: int = int(at.y * k.y)
	var hit := 0
	var tot := 0
	for y in range(cy - half, cy + half):
		for x in range(cx - half, cx + half):
			if x < 0 or y < 0 or x >= sz.x or y >= sz.y:
				continue
			tot += 1
			var c: Color = img.get_pixel(x, y)
			if absf(c.r - col.r) < tol and absf(c.g - col.g) < tol and absf(c.b - col.b) < tol:
				hit += 1
	return float(hit) / float(maxi(tot, 1))

## Доля пикселей окрестности, заметно различающихся между двумя кадрами
func _diff_share(a: Image, b: Image, at: Vector2, half: int) -> float:
	var sz: Vector2i = a.get_size()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var k: Vector2 = Vector2(sz) / vp
	var cx: int = int(at.x * k.x)
	var cy: int = int(at.y * k.y)
	var hit := 0
	var tot := 0
	for y in range(cy - half, cy + half):
		for x in range(cx - half, cx + half):
			if x < 0 or y < 0 or x >= sz.x or y >= sz.y:
				continue
			tot += 1
			var c1: Color = a.get_pixel(x, y)
			var c2: Color = b.get_pixel(x, y)
			if absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b) > 0.12:
				hit += 1
	return float(hit) / float(maxi(tot, 1))

func _run() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		if s == "bg=1":
			GameManager._apply_background_window()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	for n in ["enemy_ai", "goblin_ai"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	var cam = main.get("_camera")
	# Окно за экраном: мышь «у края» — камеру уносит прокрутка от края.
	# jump_to мгновенный, поэтому камера заморожена на весь стенд
	cam.set_process(false)
	main.set_process(false)
	var sm = main.selection_manager
	var hud = main.hud
	var base := Vector3(-60.0, 0.0, 60.0)
	main._clear_trees(base, 45.0)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(base) < 70.0:
			u.queue_free()
	await frames(5)

	# ── A. КРЕПОСТЬ ДОСТРОЕНА: РАБОЧИЕ ПЕРЕД РИСУНКОМ ─────────────────────
	print("\n═════ A. РАБОЧИЕ ПОСЛЕ СТРОЙКИ ═════")
	var site: Building = _Site.new()
	site.set("target_id", "castle")
	_place(site, base + Vector3(-14, 0, -10))
	await frames(5)
	var crew: Array = []
	var sp: Vector3 = site.global_position
	for k in range(6):
		var a: float = PI + TAU * float(k) / 6.0
		var w := _spawn("worker", sp + Vector3(cos(a) * 6.0, 0, sin(a) * 6.0 - 3.0))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
		w.command_build(site)
		crew.append(w)
	var built: Array = []
	site.connect("built", func(b): built.append(b))
	site.set("progress", float(site.get("build_time")) * 0.9)
	var t0 := 0
	while built.is_empty() and t0 < 1200:
		await pframes(1)
		t0 += 1
	verdict("A0 крепость достроена", not built.is_empty(), "кадров %d" % t0)
	await pframes(240)
	var hidden := 0
	if not built.is_empty():
		var c: Building = built[0]
		var line_z: float = c.global_position.z + c._draw_z
		for w in crew:
			if not is_instance_valid(w):
				continue
			var p: Vector3 = (w as Node3D).global_position
			if p.z < line_z and absf(p.x - c.global_position.x - c._draw_cx) < c._draw_half_w:
				hidden += 1
		cam.jump_to(c.global_position + Vector3(0, 0, 3), 26.0)
		await frames(30)
	verdict("A1 за рисунком крепости не стоит ни один рабочий", hidden == 0, "за рисунком %d из %d" % [hidden, crew.size()])
	await _shot("a_castle_built")

	# ── B. СИЛУЭТ БОЙЦА ЗА БАШНЕЙ ─────────────────────────────────────────
	print("\n═════ B. СИЛУЭТ ЗА ПОСТРОЙКОЙ ═════")
	var tw: Building = _Tower.new()
	_place(tw, base + Vector3(14, 0, -12))
	await frames(5)
	# Боец строго позади рисунка (меньший Z), на высоте рисунка его не видно
	var behind: Vector3 = tw.global_position + Vector3(tw._draw_cx, 0, tw._draw_z - 2.2)
	var hid_u := _spawn("spearman", behind)
	GameManager.add_to_squad(GameManager.new_squad(F, "spearman"), hid_u)
	hid_u.set_tick(false)
	cam.jump_to(tw.global_position + Vector3(0, 0, 4), 16.0)
	await frames(40)
	var img_b: Image = await _shot("b_ghost")
	var head: Vector2 = _screen(hid_u.global_position + Vector3(0, 1.0, 0))
	# РАЗНОСТНО: кадр с бойцом за башней против кадра без него. Цвет башни сам
	# сине-голубой — сравнение с цветом силуэта отвечало «да» и без силуэта
	GameManager.far_units.unregister(hid_u)
	var img_b0: Image = await _grab()
	var diff: float = _diff_share(img_b, img_b0, head, 14)
	print("  разница кадров у силуэта: %.3f (точка %s)" % [diff, str(head)])
	verdict("B1 за башней виден силуэт бойца (кадр меняется на рисунке башни)", diff > 0.03, "%.3f" % diff)
	# Тот же боец ПЕРЕД башней: силуэта поверх самого бойца нет — его пиксели
	# такие же, как без силуэта (знак — та же картинка с выключенным проходом)
	hid_u.queue_free()

	# ── C. ПОЛОСКА ЗДОРОВЬЯ ПОСТРОЙКИ ─────────────────────────────────────
	print("\n═════ C. ПОЛОСКА РАНЕНОЙ ПОСТРОЙКИ ═════")
	GameManager.set_hp_bars_forced(false)
	var full_vis: bool = tw._hp_bar_root != null and tw._hp_bar_root.visible
	verdict("C0 целая башня без полоски", not full_vis)
	tw.take_damage(tw.max_health * 0.4)
	await frames(3)
	var hurt_vis: bool = tw._hp_bar_root != null and tw._hp_bar_root.visible
	verdict("C1 раненая башня — полоска видна сама", hurt_vis)
	await _shot("c_tower_hp")
	tw.current_health = tw.max_health - 1.0
	tw.add_builder(crew[0])
	for _i in range(120):
		await pframes(1)
		if tw.current_health >= tw.max_health - 0.01:
			break
	await frames(3)
	var fixed_vis: bool = tw._hp_bar_root != null and tw._hp_bar_root.visible
	verdict("C2 починили до 100 % — полоска пропала", not fixed_vis, "запас %.0f/%.0f" % [tw.current_health, tw.max_health])

	# ── D. ПАНЕЛИ ─────────────────────────────────────────────────────────
	print("\n═════ D. ПАНЕЛИ ═════")
	var ar: Building = _Archery.new(); _place(ar, base + Vector3(-2, 0, 14))
	var br: Building = Barracks.new(); _place(br, base + Vector3(12, 0, 14))
	var pen: Building = load("res://scripts/SheepPen.gd").new(); _place(pen, base + Vector3(26, 0, 14))
	await frames(10)
	var panels := {"archery": ar, "barracks": br, "castle": built[0] if not built.is_empty() else null, "pen": pen}
	# Загон с рабочими 8 из 10
	for k in range(8):
		var w2 := _spawn("worker", pen.global_position + Vector3(4.0 + float(k) * 0.3, 0, 4.0))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w2)
		w2.command_farm_pen(pen)
	await pframes(30)
	for key in panels:
		var b = panels[key]
		if b == null:
			continue
		sm.select_units([b])
		await frames(20)
		var img: Image = await _grab()
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var k2: float = float(img.get_width()) / vp.x
		var pr: Rect2 = hud._bottom_panel.get_global_rect() if hud._bottom_panel != null else Rect2(0, vp.y - 160, vp.x, 160)
		_crop(img, "d_panel_" + String(key), Rect2i(int((pr.position.x - 20) * k2), int((pr.position.y - 20) * k2), int((pr.size.x + 40) * k2), int((pr.size.y + 30) * k2)))
		print("  %s: панель %s" % [key, str(pr)])
		if key == "pen":
			var txt: String = hud.info_label.text + "\n" + hud.detail_text()
			print("  текст загона: %s" % txt.replace("\n", " | "))
			verdict("D1 загон без «Пастбище/Вместимость/Мясо с рабочего/Выработка/ЛКМ»",
				not ("Пастбище" in txt or "Вместимость" in txt or "Мясо с рабочего" in txt or "Выработка" in txt or "ЛКМ" in txt), txt.replace("\n", " | "))
	# Рудник игрока с тремя рабочими: панель и значок рудников под золотом
	var mine: Mine = null
	for b2 in get_tree().get_nodes_in_group("all_buildings"):
		if b2 is Mine:
			mine = b2
			break
	if mine != null:
		mine.set_owner_faction(F)
		for k3 in range(3):
			var w3 := _spawn("worker", mine.global_position + Vector3(3, 0, 3))
			GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w3)
			mine._absorb(w3)
		await frames(30)
		sm.select_units([mine])
		await frames(70)
		var img_m: Image = await _grab()
		var vpm: Vector2 = get_viewport().get_visible_rect().size
		var km: float = float(img_m.get_width()) / vpm.x
		var prm: Rect2 = hud._bottom_panel.get_global_rect()
		_crop(img_m, "d_panel_mine", Rect2i(int((prm.position.x - 20) * km), int((prm.position.y - 20) * km), int((prm.size.x + 40) * km), int((prm.size.y + 30) * km)))
		_crop(img_m, "d_resbar_mine", Rect2i(0, 0, int(img_m.get_width() * 0.6), int(img_m.get_height() * 0.14)))
		var mtxt: String = hud.info_label.text + " | " + hud.detail_text()
		print("  текст рудника: %s" % mtxt.replace("\n", " | "))
		verdict("D4 значок рудников под золотом виден, отдельного «+N» нет",
			hud._mine_box != null and hud._mine_box.visible and not hud._mine_income_lbl.visible,
			"рудников %s" % hud._mine_count_lbl.text)
	else:
		print("  рудника на карте нет")
	# Подсказка найма лучника — без ЛКМ/ПКМ
	sm.select_units([ar])
	await frames(20)
	var badge = hud._train_badges.get("archer")
	if badge != null and is_instance_valid(badge):
		var btn: Control = badge.get_parent()
		btn.mouse_entered.emit()
		await frames(20)
		var card_txt := ""
		if hud._stat_card != null and is_instance_valid(hud._stat_card):
			for n in hud._stat_card.find_children("*", "Label", true, false):
				card_txt += (n as Label).text + " | "
			for n in hud._stat_card.find_children("*", "RichTextLabel", true, false):
				card_txt += (n as RichTextLabel).get_parsed_text() + " | "
		print("  карточка лучника: %s" % card_txt)
		verdict("D2 карточка найма без «ЛКМ — заказать, ПКМ — отменить»", not card_txt.is_empty() and not ("ЛКМ" in card_txt), "")
		var img_c: Image = await _shot("d_card_archer")
		# Мерцание: 30 кадров наведения — карточка жива и не пересоздаётся
		var card0 = hud._stat_card
		var stable := true
		for _i in range(30):
			await frames(1)
			if hud._stat_card != card0 or card0 == null or not is_instance_valid(card0):
				stable = false
				break
		verdict("D3 карточка держится 30 кадров без пересоздания (мерцание)", stable)
		btn.mouse_exited.emit()
	await _shot("d_full")
	var img_r: Image = await _grab()
	_crop(img_r, "d_resbar", Rect2i(0, 0, int(img_r.get_width() * 0.6), int(img_r.get_height() * 0.12)))

	# ── E. КУРСОРЫ ────────────────────────────────────────────────────────
	print("\n═════ E. КУРСОРЫ ═════")
	cam.jump_to(tw.global_position + Vector3(0, 0, 4), 22.0)
	await frames(30)
	var arch_sid: int = _squad("archer", tw.global_position + Vector3(-4, 0, 8), 12)
	await frames(5)
	sm.select_units(GameManager.squads[arch_sid]["members"].duplicate())
	await frames(5)
	var k_door: int = sm.hover_cursor_kind(_screen(tw.global_position + Vector3(tw._draw_cx, 2.5, tw._draw_z)))
	verdict("E1 лучники над своей башней — дверь", k_door == _CursorArt.DOOR, "вид %d" % k_door)
	# Враг для меча
	var foe_sid: int = _squad("spearman", tw.global_position + Vector3(10, 0, 6), 6, Constants.FACTION_ENEMY)
	for m in GameManager.squads[foe_sid]["members"]:
		(m as Unit).set_tick(false)
	await frames(5)
	var foe0: Unit = GameManager.squads[foe_sid]["members"][0]
	var foes: Array = sm.enemy_squad_under_cursor(_screen(foe0.global_position + Vector3(0, 0.8, 0)))
	verdict("E2 лучники над врагом — прицел (меч вниз)", not foes.is_empty() and sm.hover_cursor_kind(_screen(foe0.global_position + Vector3(0, 0.8, 0))) == _CursorArt.NONE, "целей %d" % foes.size())
	# Рабочий над раненой башней — молоток
	tw.take_damage(tw.max_health * 0.3)
	sm.select_units([crew[1]])
	await frames(3)
	var k_ham: int = sm.hover_cursor_kind(_screen(tw.global_position + Vector3(tw._draw_cx, 2.5, tw._draw_z)))
	verdict("E3 рабочий над раненой башней — молоток", k_ham == _CursorArt.HAMMER, "вид %d" % k_ham)
	for kk in [_CursorArt.DOOR, _CursorArt.FORBID, _CursorArt.SWORD, _CursorArt.HAMMER]:
		var tex: ImageTexture = _CursorArt.texture(kk)
		if tex != null and not _out.is_empty():
			var im: Image = tex.get_image()
			im.resize(96, 96, Image.INTERPOLATE_NEAREST)
			im.save_png("%s_e_cursor_%d.png" % [_out, kk])
	verdict("E4 все четыре курсора нарисованы", _CursorArt.texture(_CursorArt.DOOR) != null and _CursorArt.texture(_CursorArt.SWORD) != null and _CursorArt.texture(_CursorArt.HAMMER) != null and _CursorArt.texture(_CursorArt.FORBID) != null)

	# ── F. ПОСАДКА — БАШНЯ МОРГАЕТ ────────────────────────────────────────
	print("\n═════ F. ОТКЛИК ПОСТРОЙКИ НА ПОСАДКУ ═════")
	sm.select_units(GameManager.squads[arch_sid]["members"].duplicate())
	await frames(3)
	var fl0: int = tw.accept_flashes
	sm._try_garrison(tw)
	var peak := 0.0
	for _i in range(20):
		await frames(1)
		peak = maxf(peak, tw.accept_flash_level())
	verdict("F1 башня моргнула светлым при посадке", tw.accept_flashes > fl0 and peak > 0.1, "пик %.2f" % peak)
	await frames(40)
	verdict("F2 моргание погасло", tw.accept_flash_level() < 0.02, "%.2f" % tw.accept_flash_level())

	# ── G. ТЕЛА РЯДОМ С ЖИВЫМИ ────────────────────────────────────────────
	print("\n═════ G. ТЕЛА И ЖИВЫЕ ═════")
	var gb := base + Vector3(0, 0, -30)
	var live_sid: int = _squad("spearman", gb, 18)
	var dead_sid: int = _squad("spearman", gb + Vector3(5, 0, 0), 18, Constants.FACTION_ENEMY)
	await pframes(5)
	for m in GameManager.squads[dead_sid]["members"].duplicate():
		if is_instance_valid(m):
			(m as Unit).take_damage(99999.0)
	for m in GameManager.squads[live_sid]["members"]:
		(m as Unit).set_tick(false)
	cam.jump_to(gb + Vector3(3, 0, 3), 12.0)
	await frames(60)
	await _shot("g_corpses")

	print("\n=== TZ1014 UI SHOT: проверок %d, провалов: %d ===" % [_checks, _fails])
	get_tree().quit()
