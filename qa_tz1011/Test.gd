extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ТЗ 11.10.2026: ЧАСТЬ 1 (UI, ресурсы) И ВТОРОЕ ПИСЬМО (панель отрядов, Tab)
## ═══════════════════════════════════════════════════════════════════════════
## A — стартовые ресурсы: в зоне игрока и в зоне красного ровно 2 кучи золота
##     и 2 кучи камня; по одной каждого у крепости, второй камень — в углу у
##     внешней кромки, второе золото — в углу у центра карты.
## B — дома: одна кнопка «Дом» у рабочего; установка серией чередует ракурсы
##     (house / house2 / house3), подряд два одинаковых не бывает.
## C — панель рабочих: подписи «Артель…» нет, колонки «что выбрано» нет,
##     портрет рабочего крупнее кнопок построек.
## D — строй: текста «строй [1]» в правой верхней панели нет, окошко строя
##     над мини-картой есть, клик по ячейке меняет режим.
## E — значок опыта (кнопка копилки) стоит под иконкой рабочих с тем же
##     отступом, что иконка рабочих — от плашки ресурсов.
## F — панель отрядов: ширина сетки карточек одна при 1, 3 и 5 отрядах;
##     смена рода и Tab не оставляют в сетке чужих карточек; Tab листает роды
##     и тогда, когда фокус у кнопки панели.
## Запуск: godot --headless --path . res://qa_tz1011/Test.tscn [-- only=abcdef]

const F := Constants.FACTION_PLAYER
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var hud = null
var sm = null
var _pass := 0
var _fail := 0
var _only := "abcdef"

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz1011: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	hud = main.hud
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if _only.contains("a"): _block_a()
	if _only.contains("b"): await _block_b()
	if _only.contains("c"): await _block_c()
	if _only.contains("d"): await _block_d()
	if _only.contains("e"): await _block_e()
	if _only.contains("f"): await _block_f()
	_finish()

# ── A. РЕСУРСЫ ЗОНЫ БАЗЫ ─────────────────────────────────────────────────────
func _block_a() -> void:
	print("\n═════ A. РЕСУРСЫ СТАРТОВЫХ ЗОН ═════")
	for anchor in [main.PLAYER_BASE_ANCHOR, main.ENEMY_BASE_ANCHOR]:
		var a: Vector3 = anchor
		var who: String = "игрок" if a.z < 0.0 else "красный"
		var gold: Array = []
		var stone: Array = []
		for cid in main.res_clusters:
			var info: Dictionary = main.res_clusters[cid]
			var c: Vector3 = info["center"]
			if not main._in_base_zone(c.x, c.z):
				continue
			if signf(c.z) != signf(a.z):
				continue
			if int(info["type"]) == Constants.RESOURCE_GOLD:
				gold.append(c)
			elif int(info["type"]) == Constants.RESOURCE_STONE:
				stone.append(c)
		verdict("A1 %s: в зоне 2 золота и 2 камня" % who, gold.size() == 2 and stone.size() == 2,
			"золота %d, камня %d" % [gold.size(), stone.size()])
		if gold.size() != 2 or stone.size() != 2:
			continue
		var near_g: int = 0
		var near_s: int = 0
		for g in gold:
			if Vector2((g as Vector3).x - a.x, (g as Vector3).z - a.z).length() < 25.0:
				near_g += 1
		for st in stone:
			if Vector2((st as Vector3).x - a.x, (st as Vector3).z - a.z).length() < 25.0:
				near_s += 1
		verdict("A2 %s: по одной куче золота и камня у крепости" % who, near_g == 1 and near_s == 1,
			"у крепости золота %d, камня %d" % [near_g, near_s])
		# Дальние: камень — к внешней кромке (|z| больше), золото — к центру
		var far_g: Vector3 = gold[0] if Vector2(gold[0].x - a.x, gold[0].z - a.z).length() >= 25.0 else gold[1]
		var far_s: Vector3 = stone[0] if Vector2(stone[0].x - a.x, stone[0].z - a.z).length() >= 25.0 else stone[1]
		verdict("A3 %s: 2-й камень в углу у кромки, 2-е золото — у центра" % who,
			absf(far_s.z) > absf(a.z) and absf(far_g.z) < absf(a.z) and far_s.x > a.x + 20.0 and far_g.x > a.x + 20.0,
			"камень (%.0f, %.0f), золото (%.0f, %.0f), крепость (%.0f, %.0f)" % [far_s.x, far_s.z, far_g.x, far_g.z, a.x, a.z])

# ── B. ДОМА ──────────────────────────────────────────────────────────────────
func _workers() -> Array:
	var o: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(u) and u is Worker:
			o.append(u)
	return o

func _block_b() -> void:
	print("\n═════ B. ДОМА ═════")
	var ws: Array = _workers()
	sm._clear_selection()
	for w in ws:
		sm._select(w)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(4)
	var houses := 0
	for b in hud.button_container.get_children():
		var tip: String = String((b as Control).tooltip_text) if b is Control else ""
		if tip.contains("Дом"):
			houses += 1
	verdict("B1 у рабочего одна кнопка дома", houses == 1, "кнопок с «Дом»: %d" % houses)
	var seq: Array = []
	for _i in range(12):
		seq.append(GameManager.next_house_variant())
	var repeat := false
	var kinds: Dictionary = {}
	for i in range(seq.size()):
		kinds[seq[i]] = true
		if i > 0 and seq[i] == seq[i - 1]:
			repeat = true
	verdict("B2 ракурсы чередуются, подряд одинаковых нет", not repeat and kinds.size() == 3, str(seq))

# ── C. ПАНЕЛЬ РАБОЧИХ ────────────────────────────────────────────────────────
func _block_c() -> void:
	print("\n═════ C. ПАНЕЛЬ РАБОЧИХ ═════")
	var ws: Array = _workers()
	sm._clear_selection()
	for w in ws:
		sm._select(w)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(4)
	verdict("C1 подписи «Артель…» нет", not String(hud.info_label.text).contains("Артель"),
		"«%s»" % hud.info_label.text)
	verdict("C2 колонки «что выбрано» нет между портретом и постройками", not hud._info_col.visible)
	var pw: float = hud._portrait_wrap.custom_minimum_size.x
	var bw: float = hud.BTN_SIZE * hud.WORKER_ICON_BOOST
	verdict("C3 портрет рабочего крупнее кнопок построек", pw > bw + 1.0, "портрет %.0f, кнопка %.0f" % [pw, bw])

# ── D. СТРОЙ ─────────────────────────────────────────────────────────────────
func _block_d() -> void:
	print("\n═════ D. ОКОШКО СТРОЯ ═════")
	verdict("D1 текста «строй [1]» в правой верхней панели нет", hud._formation_label == null)
	var fp: Control = main.minimap.formation_panel
	verdict("D2 окошко строя есть и стоит над мини-картой", fp != null and is_instance_valid(fp)
		and fp.get_global_rect().end.y <= main.minimap.panel_rect().position.y + 0.5,
		"окошко %s, карта %s" % [fp.get_global_rect() if fp != null else Rect2(), main.minimap.panel_rect()])
	sm.formation_mode = sm.FORM_WIDE
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = fp._cell_rect(1).get_center()
	fp._gui_input(ev)
	verdict("D3 клик по ячейке [2] включает коробочку", int(sm.formation_mode) == int(sm.FORM_DEEP))
	ev.position = fp._cell_rect(0).get_center()
	fp._gui_input(ev)
	verdict("D4 клик по ячейке [1] возвращает широкий фронт", int(sm.formation_mode) == int(sm.FORM_WIDE))

# ── E. ЗНАЧОК ОПЫТА ──────────────────────────────────────────────────────────
func _block_e() -> void:
	print("\n═════ E. ЗНАЧОК ОПЫТА ПОД ИКОНКОЙ РАБОЧИХ ═════")
	await frames(40)
	var rb: Control = null
	var layer = GameManager.relic_mgr().get("_ui")
	if layer != null and is_instance_valid(layer):
		rb = (layer as Node).get_node_or_null("RelicButton")
	var idle: Control = hud._idle_btn
	var res: Control = hud._res_panel
	if rb == null:
		verdict("E1 кнопка копилки найдена", false)
		return
	var gap_top: float = idle.position.y - (res.position.y + res.size.y)
	var gap_rb: float = rb.position.y - (idle.position.y + idle.size.y)
	verdict("E1 кнопка копилки под иконкой рабочих, отступ как у иконки от плашки",
		absf(gap_rb - gap_top) <= 1.0 and absf(rb.position.x - idle.position.x) <= 1.0,
		"отступ иконки %.1f, кнопки %.1f, x %.0f/%.0f" % [gap_top, gap_rb, idle.position.x, rb.position.x])

# ── F. ПАНЕЛЬ ОТРЯДОВ И TAB ──────────────────────────────────────────────────
func _squad(utype: String, n: int, at: Vector3) -> int:
	var sid: int = GameManager.new_squad(F, utype)
	var scn: String = {"spearman": "Spearman", "archer": "Archer", "warrior": "Warrior", "monk": "Monk"}[utype]
	for i in range(n):
		var u: Unit = load("res://scenes/units/%s.tscn" % scn).instantiate()
		u.faction = F
		main.world_add(u)
		var p := at + Vector3(float(i % 6) * 0.8, 0.0, float(i / 6) * 0.8)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
	return sid

func _select(sids: Array) -> void:
	sm._clear_selection()
	for sid in sids:
		for m in GameManager.squad_members(int(sid)):
			sm._select(m)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(4)

func _block_f() -> void:
	print("\n═════ F. ПАНЕЛЬ ОТРЯДОВ, TAB ═════")
	var at := Vector3(-150.0, 0.0, -70.0)
	var all: Array = []
	for i in range(5):
		all.append(_squad("spearman", 10, at + Vector3(i * 6.0, 0, 0)))
	for i in range(3):
		all.append(_squad("archer", 8, at + Vector3(i * 6.0, 0, 6)))
	all.append(_squad("warrior", 8, at + Vector3(0, 0, 12)))
	await frames(4)
	await _select(all)
	var widths: Dictionary = {}
	var cards: Dictionary = {}
	for t in ["spearman", "archer", "warrior", "spearman"]:
		hud._on_type_filter_pressed(String(t))
		await frames(3)
		hud._sync_panel_height()
		widths[t] = hud._bottom_panel.custom_minimum_size.x
		cards[t] = hud._squad_strip.get_child_count()
		if OS.get_cmdline_user_args().has("diag=1"):
			print("  [%s] ширина %.0f" % [t, widths[t]])
			for ch in hud._bottom_panel.get_child(1).get_child(1).get_children():
				if ch is Control and (ch as Control).visible:
					print("     %s min=%s" % [ch.name, (ch as Control).get_combined_minimum_size()])
	# РАЗВОРОТ ТЗ 12.10.2026 (второе письмо): плашка «резиновая» — обтягивает
	# сетку карточек; больше отрядов — не уже, чем меньше
	verdict("F1 плашка растёт с числом отрядов рода (5 ≥ 3 ≥ 1), без пустых дыр",
		float(widths["spearman"]) >= float(widths["archer"]) and float(widths["archer"]) >= float(widths["warrior"]),
		str(widths))
	verdict("F2 в сетке ровно карточки показанного рода (без старых)",
		int(cards["archer"]) == 3 and int(cards["warrior"]) == 1 and int(cards["spearman"]) == 5, str(cards))
	verdict("F3 плашка не шире половины экрана", float(widths["spearman"]) < 640.0, "%.0f px" % float(widths["spearman"]))
	# Tab при фокусе на кнопке панели: событие — через настоящий ввод
	var b0: Control = null
	for ch in hud._squad_cmd_bar.get_children():
		if ch is Button:
			b0 = ch
			break
	if b0 != null:
		b0.focus_mode = Control.FOCUS_ALL
		b0.grab_focus()
	var before: String = String(hud._expanded_type)
	var seen: Dictionary = {before: true}
	for _i in range(3):
		var k := InputEventKey.new()
		k.keycode = KEY_TAB
		k.physical_keycode = KEY_TAB
		k.pressed = true
		Input.parse_input_event(k)
		await frames(3)
		var up := InputEventKey.new()
		up.keycode = KEY_TAB
		up.physical_keycode = KEY_TAB
		up.pressed = false
		Input.parse_input_event(up)
		await frames(2)
		seen[String(hud._expanded_type)] = true
	verdict("F4 Tab листает роды и при фокусе на кнопке панели", seen.size() >= 3,
		"роды за 3 нажатия: %s" % str(seen.keys()))
	# Кузница: Tab — следующая вкладка
	var smithy := Smithy.new()
	smithy.faction = F
	main.world_add(smithy)
	smithy.global_position = at + Vector3(20, 0, -10)
	await frames(3)
	hud.show_selection([smithy])
	await frames(3)
	var t0: String = String(hud._forge_unit)
	var k2 := InputEventKey.new()
	k2.keycode = KEY_TAB
	k2.physical_keycode = KEY_TAB
	k2.pressed = true
	Input.parse_input_event(k2)
	await frames(3)
	var k2u := InputEventKey.new()
	k2u.keycode = KEY_TAB
	k2u.physical_keycode = KEY_TAB
	Input.parse_input_event(k2u)
	await frames(2)
	verdict("F5 Tab в кузнице — следующая вкладка", String(hud._forge_unit) != t0, "%s → %s" % [t0, hud._forge_unit])
