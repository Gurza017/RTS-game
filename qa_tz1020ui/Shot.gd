extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СТЕНД ТЗ 20.10.2026 (интерфейс): карта слева, стыковка, карточки,
## колокол и слот рабочих, укрепление башни, курсоры, знамёна
## ═══════════════════════════════════════════════════════════════════════════
##   A  мини-карта в левом нижнем углу, на 30 % меньше; кнопки строя над ней —
##      почти квадратные плитки
##   B  панель выделенного (замок, бараки, башня, стрелковая, загон, рабочий,
##      отряд) стыкуется к правому краю карты и не наезжает на неё
##   C  карточка найма: столбик характеристик, «Тип/Умения/Особое», без мусора;
##      висит над панелью, не на карте
##   D  замок: колокол тревоги и слот рабочих; башня: кнопка укрепления
##   E  курсоры: топор/кирка/нож/палец/дверь/меч под 45°
##   F  знамёна в мире: опытные, ветераны, легендарный штандарт, язычки орды
## Запуск: godot --audio-driver Dummy --windowed --position -5000,-5000 --path .
##         res://qa_tz1020ui/Shot.tscn -- --out=<путь без .png> bg=1

const F := Constants.FACTION_PLAYER
const _Tower := preload("res://scripts/Tower.gd")
const _Archery := preload("res://scripts/Archery.gd")
const _CursorArt := preload("res://scripts/CursorArt.gd")
const _Minimap := preload("res://scripts/Minimap.gd")
var main = null
var _out := ""
var _fails := 0
var _checks := 0

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("СТОРОЖ: стенд не уложился в 240 с")
		_end())

func verdict(name: String, ok: bool, info: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s  %s" % ["ПРОШЛО" if ok else "НЕ ПРОШЛО", name, info])

func _end() -> void:
	print("\n═════ ИТОГ qa_tz1020ui: проверок %d, провалов: %d ═════" % [_checks, _fails])
	get_tree().quit()

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
		var u := _spawn(kind, at + Vector3(float(k % 5) * 0.7, 0, float(k / 5) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
	return sid

func _screen(p: Vector3) -> Vector2:
	return main.get("_camera").unproject_position(p)

func _card_text(hud) -> String:
	var t := ""
	if hud._stat_card != null and is_instance_valid(hud._stat_card):
		for n in hud._stat_card.find_children("*", "Label", true, false):
			t += (n as Label).text + " | "
		for n in hud._stat_card.find_children("*", "RichTextLabel", true, false):
			t += (n as RichTextLabel).get_parsed_text() + " | "
	return t

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
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(F, r, 50000.0)
	var cam = main.get("_camera")
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
	var vp: Vector2 = get_viewport().get_visible_rect().size

	# ── A. МИНИ-КАРТА ─────────────────────────────────────────────────────
	print("\n═════ A. МИНИ-КАРТА СЛЕВА ═════")
	var mm = main.minimap
	var mr: Rect2 = mm.panel_rect()
	print("  карта %s, экран %s" % [str(mr), str(vp)])
	verdict("A1 карта в левом нижнем углу", mr.position.x <= 10.0 and absf(mr.end.y - vp.y) <= 8.0, str(mr))
	verdict("A2 карта на ~30 %% меньше (240×135 → %d×%d)" % [_Minimap.MAP_W, _Minimap.MAP_H],
		absf(float(_Minimap.MAP_W) / 240.0 - 0.70) < 0.02 and absf(float(_Minimap.MAP_H) / 135.0 - 0.70) < 0.02)
	var fp = mm.formation_panel
	var cr: Rect2 = fp._cell_rect(0)
	var asp: float = cr.size.x / maxf(cr.size.y, 1.0)
	verdict("A3 кнопки строя над картой — почти квадратные плитки", asp >= 1.0 and asp <= 1.9
		and fp.get_global_rect().end.y <= mr.position.y + 0.5, "ячейка %.0f×%.0f" % [cr.size.x, cr.size.y])
	# Наведение и нажатие дают видимый отклик (состояние плитки)
	var mv := InputEventMouseMotion.new()
	mv.position = cr.get_center()
	fp._gui_input(mv)
	var hov: int = int(fp._hover_cell)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = fp._cell_rect(1).get_center()
	fp._gui_input(mb)
	verdict("A4 плитка подсвечивается и «вдавливается»", hov == 0 and int(fp._press_cell) == 1)
	await _shot("a_minimap")
	var k_fp := InputEventMouseButton.new()
	k_fp.button_index = MOUSE_BUTTON_LEFT
	k_fp.pressed = true
	k_fp.position = fp._cell_rect(0).get_center()
	fp._gui_input(k_fp)

	# ── B. СТЫКОВКА ПАНЕЛЕЙ ───────────────────────────────────────────────
	print("\n═════ B. ПАНЕЛИ У ПРАВОГО КРАЯ КАРТЫ ═════")
	var castle: Building = Castle.new(); _place(castle, base + Vector3(-12, 0, -8))
	var tw: Building = _Tower.new(); _place(tw, base + Vector3(14, 0, -12))
	var ar: Building = _Archery.new(); _place(ar, base + Vector3(-2, 0, 14))
	var br: Building = Barracks.new(); _place(br, base + Vector3(12, 0, 14))
	var pen: Building = load("res://scripts/SheepPen.gd").new(); _place(pen, base + Vector3(26, 0, 14))
	await frames(10)
	var w0 := _spawn("worker", base + Vector3(2, 0, 2))
	GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w0)
	var sq_sid: int = _squad("warrior", base + Vector3(4, 0, 6), 15)
	cam.jump_to(base, 34.0)
	await frames(20)
	var dock: float = _Minimap.dock_right_x()
	var sel := {"castle": [castle], "tower": [tw], "archery": [ar], "barracks": [br],
		"pen": [pen], "worker": [w0], "squad": GameManager.squads[sq_sid]["members"].duplicate()}
	var bad: Array = []
	for key in sel:
		sm.select_units(sel[key])
		await frames(12)
		var pr: Rect2 = hud._bottom_panel.get_global_rect()
		var ok: bool = absf(pr.position.x - dock) <= 1.5 and not pr.intersects(mr)
		if not ok:
			bad.append("%s:%s" % [key, str(pr)])
		print("  %s: панель %s" % [key, str(pr)])
		if key == "tower":
			print("  башня: info=[%s] vis=%s detail=[%s] dvis=%s dsize=%s" % [hud.info_label.text.c_escape(), str(hud.info_label.visible),
				hud._detail_label.text.c_escape(), str(hud._detail_label.visible), str(hud._detail_label.size)])
		await _shot("b_" + String(key))
	verdict("B1 все панели стыкуются к правому краю карты (x = %.0f) и не наезжают на неё" % dock,
		bad.is_empty(), str(bad))

	# ── C. КАРТОЧКА НАЙМА ─────────────────────────────────────────────────
	print("\n═════ C. КАРТОЧКИ ═════")
	sm.select_units([castle])
	await frames(15)
	var badge = hud._train_badges.get("warrior")
	if badge != null and is_instance_valid(badge):
		var btn: Control = badge.get_parent()
		btn.mouse_entered.emit()
		await frames(20)
		var txt: String = _card_text(hud)
		print("  карточка мечника: %s" % txt)
		verdict("C1 карточка мечника без «ветераном», «Содержание», «ЛКМ»",
			not txt.is_empty() and not ("ветераном" in txt or "Содержание" in txt or "ЛКМ" in txt))
		verdict("C2 «Тип / Умения / Особое умение»", "Тип:" in txt and "Умения:" in txt and "Особое умение:" in txt)
		verdict("C3 столбик: Здоровье, Атака, Броня, Скорость", "Здоровье" in txt and "Атака" in txt
			and "Броня" in txt and "Скорость" in txt)
		var cr2: Rect2 = hud._stat_card.get_global_rect()
		verdict("C4 карточка не лежит на мини-карте", not cr2.intersects(mr), str(cr2))
		await _shot("c_card_warrior")
		btn.mouse_exited.emit()
	# Карточка здания (кнопка постройки у рабочего)
	sm.select_units([w0])
	await frames(15)
	for b in hud.button_container.get_children():
		if b is Button and String((b as Button).tooltip_text) == "Башня":
			(b as Button).mouse_entered.emit()
			await frames(20)
			print("  карточка башни: %s" % _card_text(hud))
			verdict("C5 карточка здания — «Тип» и «Назначение»", "Тип:" in _card_text(hud) and "Назначение:" in _card_text(hud))
			await _shot("c_card_tower")
			(b as Button).mouse_exited.emit()
			break

	# ── D. КОЛОКОЛ, СЛОТ РАБОЧИХ, УКРЕПЛЕНИЕ ──────────────────────────────
	print("\n═════ D. ЗАМОК И БАШНЯ ═════")
	sm.select_units([castle])
	await frames(15)
	# ТЗ 21.10.2026: колокол — в правом верхнем углу панели, отдельной кнопки
	# слота нет; укрытые рабочие — мини-слот «Гарнизона», когда они есть (D2)
	var alert = hud.get("_bell_btn")
	verdict("D1 у замка есть колокол", alert != null)
	GameManager.toggle_worker_alert(F)
	for _i in range(120):
		await pframes(5)
		if int(castle.call("shelter_count")) >= 1:
			break
	sm.select_units([castle])
	await frames(15)
	await _shot("d_castle_alert")
	var lbl = hud._shelter_ui.get("lbl")
	verdict("D2 слот показывает число укрытых", lbl != null and (lbl as Label).visible and (lbl as Label).text.begins_with("1"),
		(lbl as Label).text if lbl != null else "")
	GameManager.toggle_worker_alert(F)
	sm.select_units([tw])
	await frames(15)
	var fb = hud.button_container.find_child("TowerFortBtn", true, false)
	verdict("D3 у башни есть кнопка укрепления", fb != null)
	tw.call("fort_start")
	sm.select_units([tw])
	await frames(15)
	await _shot("d_tower_fort")
	tw.call("fort_apply", 2)
	cam.jump_to(tw.global_position + Vector3(0, 0, 4), 18.0)
	await frames(20)
	await _shot("d_tower_fortified")

	# ── E. КУРСОРЫ ────────────────────────────────────────────────────────
	print("\n═════ E. КУРСОРЫ ═════")
	cam.jump_to(base, 30.0)
	await frames(20)
	sm.select_units([w0])
	await frames(3)
	var kpen: int = sm.hover_cursor_kind(_screen(pen.global_position + Vector3(0, 0.5, 0)))
	verdict("E1 рабочий над загоном — нож", kpen == _CursorArt.KNIFE, "вид %d" % kpen)
	var kc: int = sm.hover_cursor_kind(_screen(castle.global_position + Vector3(castle._draw_cx, 3.0, castle._draw_z)))
	verdict("E2 рабочий над замком — палец", kc == _CursorArt.FINGER, "вид %d" % kc)
	var arch_sid: int = _squad("archer", tw.global_position + Vector3(-4, 0, 8), 12)
	await frames(3)
	sm.select_units(GameManager.squads[arch_sid]["members"].duplicate())
	await frames(3)
	var kd: int = sm.hover_cursor_kind(_screen(tw.global_position + Vector3(tw._draw_cx, 2.5, tw._draw_z)))
	verdict("E3 лучники над башней — дверь", kd == _CursorArt.DOOR, "вид %d" % kd)
	sm.select_units(GameManager.squads[sq_sid]["members"].duplicate())
	await frames(3)
	var kb: int = sm.hover_cursor_kind(_screen(br.global_position + Vector3(br._draw_cx, 2.5, br._draw_z)))
	verdict("E4 пехота над бараками — палец", kb == _CursorArt.FINGER, "вид %d" % kb)
	var all_ok := true
	for kk in [_CursorArt.AXE, _CursorArt.PICKAXE, _CursorArt.KNIFE, _CursorArt.FINGER, _CursorArt.SWORD, _CursorArt.DOOR]:
		var tex: ImageTexture = _CursorArt.texture(kk)
		if tex == null:
			all_ok = false
		elif not _out.is_empty():
			var im: Image = tex.get_image()
			im.resize(96, 96, Image.INTERPOLATE_NEAREST)
			im.save_png("%s_e_cursor_%d.png" % [_out, kk])
	verdict("E5 все шесть курсоров нарисованы", all_ok)
	# Меч наклонён: остриё (горячая точка) внизу слева, рукоять вверху справа
	var hs: Vector2 = _CursorArt.hotspot(_CursorArt.SWORD)
	verdict("E6 меч наклонён: остриё слева внизу", hs.x < 8.0 and hs.y > 24.0, str(hs))

	# ── F. ЗНАМЁНА ────────────────────────────────────────────────────────
	print("\n═════ F. ЗНАМЁНА ═════")
	var fb_at := base + Vector3(0, 0, 30)
	main._clear_trees(fb_at, 25.0)
	var lv := [2, 5, 7]
	var xs := [-10.0, 0.0, 10.0]
	for i in range(3):
		var s1: int = _squad("spearman", fb_at + Vector3(xs[i], 0, 0), 10)
		(GameManager.squads[s1] as Dictionary)["level"] = lv[i]
		GameManager.refresh_squad_banner(s1)
	var gs: int = _squad("goblin_spearman", fb_at + Vector3(20, 0, 0), 10, Constants.FACTION_GOBLIN)
	(GameManager.squads[gs] as Dictionary)["level"] = 4
	GameManager.refresh_squad_banner(gs)
	for m in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(m) and (m as Node3D).global_position.distance_to(fb_at) < 30.0:
			(m as Unit).set_tick(false)
	cam.jump_to(fb_at + Vector3(5, 0, 2), 30.0)
	await frames(40)
	await _shot("f_banners")
	_end()
