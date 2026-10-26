extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: РЕДИЗАЙН МЕНЮ И ПОЛИРОВКА ИНТЕРФЕЙСА (ТЗ 21.10.2026, три письма)
## ═══════════════════════════════════════════════════════════════════════════
##   A — главное меню: иллюстрация, заголовок, рама, ровно 4 кнопки со
##       средневековыми стилями (обычная / наведение / нажата различны);
##   B — опции: окно с вкладками Партия / Звук / Графика, две колонки, без
##       прокрутки, целиком в экране 1280x720 на КАЖДОЙ вкладке;
##   C — экран загрузки: арт, полоса с процентами, совет, этап; кольца нет;
##       этапы двигают полосу; finish закрывает экран;
##   D — пауза: компактная рама в экране, 7 кнопок, «Настройки» — то же окно
##       с вкладками поверх паузы (раса/цвет погашены), закрытие — назад;
##   E — замок: колокол в правом верхнем углу панели и переливается,
##       отдельной кнопки слота рабочих нет; укрытые — мини-слот «Гарнизона»,
##       ЛКМ выпускает одного;
##   F — курсор-палец — исходная перчатка Cursor_02; сброс выделения кликом
##       мимо — «клац» (menu_close, короткий щелчок, не тон).
## Запуск: godot --headless --path . res://qa_menu_ui/Test.tscn [-- only=abcdef]

const _UIAssets := preload("res://scripts/UIAssets.gd")
const _CursorArt := preload("res://scripts/CursorArt.gd")
const _Loading := preload("res://scripts/ui/LoadingScreen.gd")
const F := Constants.FACTION_PLAYER

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcdef"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_menu_ui: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().paused = false
	get_tree().quit()

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _find(root: Node, nm: String) -> Node:
	if root == null:
		return null
	if root.name == nm:
		return root
	for c in root.get_children():
		var r := _find(c, nm)
		if r != null:
			return r
	return null

func _collect(root: Node, cls: String, out: Array) -> void:
	if root.is_class(cls):
		out.append(root)
	for c in root.get_children():
		_collect(c, cls, out)

func _vp() -> Rect2:
	return get_viewport().get_visible_rect()

func _inside(c: Control) -> bool:
	var r: Rect2 = c.get_global_rect()
	return _vp().grow(1.0).encloses(r)

func _run() -> void:
	if "a" in _only or "b" in _only:
		await _ab_menu()
	if "c" in _only:
		await _c_loading()
	if "d" in _only or "e" in _only or "f" in _only:
		main = load("res://scenes/Main.tscn").instantiate()
		get_tree().root.add_child(main)
		await pframes(30)
		for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
			var nd = main.get(n)
			if nd != null:
				nd.set_process(false)
				nd.set_physics_process(false)
		if "d" in _only: await _d_pause()
		if "e" in _only: await _e_castle()
		if "f" in _only: await _f_cursor_sound()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _ab_menu() -> void:
	print("\n═════ A. ГЛАВНОЕ МЕНЮ ═════")
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	await frames(4)
	verdict("A1 фон — иллюстрация (MenuArt), а не заливка", _find(menu, "MenuArt") is Control)
	var title := _find(menu, "MenuTitle") as Label
	verdict("A2 заголовок «10 000 КОПЕЙЩИКОВ»", title != null and title.text == "10 000 КОПЕЙЩИКОВ")
	var panel := _find(menu, "MenuPanel") as PanelContainer
	verdict("A3 кнопки в раме (PanelContainer) и рама в экране", panel != null and _inside(panel),
		str(panel.get_global_rect()) if panel != null else "")
	var page := _find(menu, "PageMain")
	var btns: Array = []
	for c in page.get_children():
		if c is Button and (c as Button).visible:
			btns.append((c as Button).text)
	verdict("A4 ровно четыре кнопки START / Загрузить / Опции / Выход",
		btns == ["START", "Загрузить", "Опции", "Выход"], str(btns))
	var start := _find(menu, "StartButton") as Button
	var sn = start.get_theme_stylebox("normal")
	var sh = start.get_theme_stylebox("hover")
	var sp = start.get_theme_stylebox("pressed")
	verdict("A5 у кнопок три разных состояния (фактура дерева)",
		sn is StyleBoxTexture and sh is StyleBoxTexture and sp is StyleBoxTexture
		and (sn as StyleBoxTexture).texture != (sh as StyleBoxTexture).texture
		and (sn as StyleBoxTexture).texture != (sp as StyleBoxTexture).texture)
	verdict("A6 нажатая кнопка «вдавлена» (содержимое ниже)",
		(sp as StyleBoxTexture).content_margin_top > (sn as StyleBoxTexture).content_margin_top)
	var calls0: int = AudioManager.ui_calls
	start.get_signal_connection_list("pressed")
	(_find(menu, "OptionsButton") as Button).pressed.emit()
	verdict("A7 нажатие кнопки меню звучит щелчком", AudioManager.ui_calls > calls0 and AudioManager.ui_last == "menu_button",
		"последнее %s" % AudioManager.ui_last)

	print("\n═════ B. ОПЦИИ: ВКЛАДКИ БЕЗ ПРОКРУТКИ ═════")
	await frames(3)
	var win := _find(menu, "PageOptions") as Control
	verdict("B1 «Опции» открывают окно настроек поверх меню", win != null and win.visible)
	var tabs := _find(win, "SettingsTabs") as TabContainer
	var names: Array = []
	if tabs != null:
		for i in range(tabs.get_tab_count()):
			names.append(tabs.get_tab_title(i))
	verdict("B2 три верхние вкладки: Партия / Звук / Графика", names == ["Партия", "Звук", "Графика"], str(names))
	var scrolls: Array = []
	_collect(win, "ScrollContainer", scrolls)
	verdict("B3 прокрутки в окне нет", scrolls.is_empty(), "ScrollContainer: %d" % scrolls.size())
	var all_fit := true
	var info := ""
	for i in range(tabs.get_tab_count()):
		tabs.current_tab = i
		await frames(3)
		var p := _find(win, "SettingsPanel") as Control
		var ok: bool = _inside(p)
		all_fit = all_fit and ok
		info += "%s %s; " % [names[i], str(p.get_global_rect().size)]
	verdict("B4 окно целиком в экране %s на каждой вкладке" % str(_vp().size), all_fit, info)
	var two_col := true
	for g in tabs.get_children():
		if not (g is GridContainer and (g as GridContainer).columns == 2):
			two_col = false
	verdict("B5 содержимое вкладок — две колонки (название | переключатель)", two_col)
	var game_tab := tabs.get_child(0)
	var need := ["PlayerRaceOption", "PlayerColorOption", "AiRaceOption", "AiColorOption",
		"DifficultyOption", "ArmisticeCheck", "AutosaveOption"]
	var miss: Array = []
	for n in need:
		if _find(game_tab, n) == null:
			miss.append(n)
	verdict("B6 «Партия»: раса/цвет обеих сторон, сложность, перемирие, автосохранение", miss.is_empty(), "нет: %s" % str(miss))
	var sl: Array = []
	_collect(tabs.get_child(1), "HSlider", sl)
	verdict("B7 «Звук»: три ползунка с процентами", sl.size() == 3, "%d" % sl.size())
	var vid := tabs.get_child(2)
	verdict("B8 «Графика»: V-Sync, FPS, камера от края",
		_find(vid, "VsyncCheck") != null and _find(vid, "FpsCheck") != null and _find(vid, "EdgePanCheck") != null)
	# Выбор расы уезжает в GameManager — его читает START
	var ro := _find(game_tab, "AiRaceOption") as OptionButton
	var was: String = GameManager.ai_faction_name
	ro.select(2)
	ro.item_selected.emit(2)
	verdict("B9 выбор расы в окне сразу в GameManager", GameManager.ai_faction_name == "orc", GameManager.ai_faction_name)
	GameManager.ai_faction_name = was
	ro.select(0)
	verdict("B10 START читает те же элементы (_player_opt — элемент окна)", menu._player_opt == _find(game_tab, "PlayerRaceOption"))
	(_find(win, "SettingsBack") as Button).pressed.emit()
	await frames(2)
	verdict("B11 «Назад» закрывает окно, меню снова видно", not win.visible and panel.visible)
	remove_child(menu)
	menu.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
func _c_loading() -> void:
	print("\n═════ C. ЭКРАН ЗАГРУЗКИ ═════")
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	await frames(2)
	var before: int = int(menu.loader_shown)
	var ls = menu._show_loader()
	await frames(3)
	var layer: Node = get_tree().root.get_node_or_null("LoadingLayer")
	verdict("C1 слой загрузки на корне дерева (переживает смену сцены), поверх всего",
		layer != null and layer == ls and (layer as CanvasLayer).layer >= 100)
	verdict("C2 фон — арт (LoadingArt) поверх непрозрачной подложки",
		_find(layer, "LoadingArt") is Control and (_find(layer, "LoadingBack") as ColorRect).color.a >= 0.99)
	verdict("C3 кольца-спиннера больше нет", _find(layer, "LoadingSpinner") == null)
	var bar := _find(layer, "LoadingBar") as Control
	var pct := _find(layer, "LoadingPercent") as Label
	var tip := _find(layer, "LoadingTip") as Label
	var st := _find(layer, "LoadingLabel") as Label
	verdict("C4 внизу полоса с процентами, над ней совет, под ней этап",
		bar != null and pct != null and tip != null and st != null
		and tip.get_global_rect().position.y < bar.get_global_rect().position.y
		and st.get_global_rect().position.y > bar.get_global_rect().position.y
		and bar.get_global_rect().position.y > _vp().size.y * 0.6
		and pct.text.ends_with("%") and tip.text.begins_with("Совет"),
		"полоса y=%.0f, «%s», «%s»" % [bar.get_global_rect().position.y if bar != null else -1.0,
			pct.text if pct != null else "", tip.text.left(40) if tip != null else ""])
	verdict("C5 полоса в экране и шире половины его", bar != null and _inside(bar)
		and bar.get_global_rect().size.x >= _vp().size.x * 0.5)
	_Loading.stage("Генерация рельефа…", 0.40)
	await frames(2)
	var p1: float = float(ls.progress())
	_Loading.stage("Размещение отрядов…", 0.88)
	await frames(30)
	var p2: float = float(ls.progress())
	verdict("C6 этапы двигают полосу и подпись", p2 > p1 and p1 > 0.2 and st.text == "Размещение отрядов…",
		"%.2f → %.2f, «%s», текст %s" % [p1, p2, st.text, pct.text])
	verdict("C7 проценты по показанной доле", pct.text == "%d%%" % int(floor(p2 * 100.0 + 0.0001)), pct.text)
	var tip0: String = tip.text
	ls.set("_tip_t", 100.0)
	await frames(2)
	verdict("C8 советы сменяются", tip.text != tip0 and tip.text.begins_with("Совет"))
	verdict("C9 счётчик показов меню вырос", int(menu.loader_shown) == before + 1)
	_Loading.finish()
	var gone := false
	for _i in range(240):
		await frames(1)
		if not is_instance_valid(layer) or layer.is_queued_for_deletion():
			gone = true
			break
	verdict("C10 finish доводит до 100 % и закрывает экран", gone and not _Loading.is_active())
	remove_child(menu)
	menu.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
func _btn_texts(root: Node) -> Array:
	var all: Array = []
	_collect(root, "Button", all)
	var out: Array = []
	for b in all:
		if (b as Button).is_visible_in_tree() and not (b is OptionButton) and not (b is CheckBox):
			out.append((b as Button).text)
	return out

func _d_pause() -> void:
	print("\n═════ D. ПАУЗА ═════")
	var hud = main.hud
	hud._pause_options_open = false
	hud._show_pause_menu()
	await frames(3)
	var panel := _find(hud._overlay, "ModalPanel") as Control
	verdict("D1 пауза — рама по центру экрана, целиком в нём", panel != null and _inside(panel)
		and absf(panel.get_global_rect().get_center().y - _vp().size.y * 0.5) < 30.0
		and absf(panel.get_global_rect().get_center().x - _vp().size.x * 0.5) < 30.0,
		str(panel.get_global_rect()) if panel != null else "")
	var texts: Array = _btn_texts(hud._overlay)
	verdict("D2 семь кнопок паузы", texts == ["Продолжить", "Сохранить игру", "Загрузить игру",
		"Настройки", "Заново", "Выйти в меню", "Выход из игры"], str(texts))
	verdict("D3 рама компактная (не выше 70 % экрана)", panel.get_global_rect().size.y <= _vp().size.y * 0.7,
		"%.0f из %.0f" % [panel.get_global_rect().size.y, _vp().size.y])
	(_find(hud._overlay, "PauseOptions") as Button).pressed.emit()
	await frames(3)
	var win := _find(hud._overlay, "PauseOptionsBox") as Control
	verdict("D4 «Настройки» — окно с вкладками поверх паузы, рама паузы спрятана",
		win != null and _find(win, "SettingsTabs") != null and not panel.is_visible_in_tree())
	var sp := _find(win, "SettingsPanel") as Control
	verdict("D5 окно настроек в экране, прокрутки нет", sp != null and _inside(sp))
	var ro := _find(win, "PlayerRaceOption") as OptionButton
	verdict("D6 в партии раса/цвет показаны, но погашены", ro != null and ro.disabled)
	var all_always := true
	var sl: Array = []
	_collect(win, "HSlider", sl)
	for s in sl:
		if (s as Node).process_mode != Node.PROCESS_MODE_ALWAYS:
			all_always = false
	verdict("D7 ползунки работают на паузе (ALWAYS)", sl.size() == 3 and all_always)
	(_find(win, "SettingsBack") as Button).pressed.emit()
	await frames(3)
	verdict("D8 закрытие настроек возвращает раму паузы", panel.is_visible_in_tree()
		and _find(hud._overlay, "PauseOptionsBox") == null or (_find(hud._overlay, "PauseOptionsBox") as Node).is_queued_for_deletion())
	hud._show_save_menu(false)
	await frames(3)
	var sp2 := _find(hud._overlay, "ModalPanel") as Control
	verdict("D9 экран загрузки сохранений — та же рама, в экране", sp2 != null and _inside(sp2)
		and _find(hud._overlay, "SaveSlot0") != null)
	hud._clear_overlay()
	get_tree().paused = false
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
func _e_castle() -> void:
	print("\n═════ E. ЗАМОК: КОЛОКОЛ В УГЛУ, СЛОТ РАБОЧИХ ═════")
	var base := Vector3(-120, 0, 60)
	main._clear_trees(base, 30.0)
	var c: Building = Castle.new()
	c.faction = F
	main.world_add(c)
	c.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z)
	await pframes(10)
	var sm = main.selection_manager
	var hud = main.hud
	sm.select_units([c])
	GameManager.on_selection_changed(sm.selected_units, true)
	await frames(6)
	var bell := hud._bell_btn as Button
	var pr: Rect2 = hud._bottom_panel.get_global_rect()
	var br: Rect2 = bell.get_global_rect() if bell != null else Rect2()
	# РАЗВОРОТ ТЗ 22.10.2026: квадрат, вписанный в правый верхний угол рамы
	# (прежде — значок на верхней кромке, наполовину над панелью); на низкой
	# панели угол занят кнопкой найма — колокол встаёт на раму над ней (E3)
	verdict("E1 колокол — квадратом в правом верхнем углу панели замка", bell != null
		and bell.visible and absf(br.end.x - (pr.end.x - hud.ALERT_BELL_INSET)) < 3.0
		and br.position.y >= pr.position.y - hud.ALERT_BELL * 0.5 and br.position.y <= pr.position.y + 8.0
		and absf(br.size.x - br.size.y) < 1.0,
		"панель %s, колокол %s" % [str(pr), str(br)])
	var big_alerts := 0
	var rects: Array = []
	for b in hud.button_container.get_children():
		if b is Button and String((b as Button).name) in ["AlertBtn", "ShelterSlot"]:
			big_alerts += 1
		if b is Control and String(b.name) != "AlertCorner" and (b as Control).visible:
			rects.append((b as Control).get_global_rect())
	verdict("E2 в ряду кнопок нет ни колокола, ни отдельной кнопки высадки рабочих",
		big_alerts == 0 and _find(hud.button_container, "ShelterSlot") == null
		and _find(hud.button_container, "AlertBtn") == null)
	var overlap := false
	var hit_note := ""
	for r in rects:
		if (r as Rect2).intersects(br):
			overlap = true
			hit_note += str(r) + " "
	verdict("E3 колокол не накрывает кнопки панели", not overlap, "колокол %s; задеты %s" % [br, hit_note])
	# РАЗВОРОТ ТЗ 22.10.2026: кнопка строго статична — ни свечения, ни
	# перелива яркости за 240 кадров
	var glow_seen := false
	var mod_changed := false
	var mod0: Color = bell.self_modulate if bell != null else Color.WHITE
	for _i in range(240):
		await frames(1)
		if bell == null or not is_instance_valid(bell):
			break
		if _find(bell, "BellGlow") != null:
			glow_seen = true
		if bell.self_modulate != mod0:
			mod_changed = true
	verdict("E4 колокол статичен: без свечения и мерцания", not glow_seen and not mod_changed,
		"свечение %s, яркость менялась %s" % [glow_seen, mod_changed])
	# Тревога: рабочие в замке — мини-слот в «Гарнизоне»
	for k in range(3):
		var w: Unit = Building.PRELOAD_SCENES["worker"].instantiate()
		w.faction = F
		main.world_add(w)
		var at := base + Vector3(10.0 + float(k), 0, 6.0)
		w.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
		w.sync_row()
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
	await pframes(5)
	GameManager.toggle_worker_alert(F)
	var t := 0
	while int(c.call("shelter_count")) < 3 and t < 1500:
		await pframes(10)
		t += 10
	sm.select_units([c])
	GameManager.on_selection_changed(sm.selected_units, true)
	await frames(8)
	var slot := _find(hud.button_container, "ShelterSlot") as Button
	var sec := _find(hud.button_container, "GarrisonSection")
	verdict("E5 укрытые рабочие — мини-слот секции «Гарнизон» с числом", slot != null and sec != null
		and slot.get_parent().get_parent() == sec and (hud._shelter_ui.get("lbl") as Label).text.begins_with(str(int(c.call("shelter_count")))),
		"внутри %d, слот %s, секция %s, родитель %s, число «%s»" % [int(c.call("shelter_count")), str(slot), str(sec), str(slot.get_parent().get_parent()) if slot != null else "", (hud._shelter_ui.get("lbl") as Label).text if hud._shelter_ui.has("lbl") else "—"])
	if slot != null:
		slot.pressed.emit()
		await frames(2)
		verdict("E6 ЛКМ по слоту — выходит один", int(c.call("shelter_count")) == 2)
	GameManager.toggle_worker_alert(F)
	await frames(10)
	verdict("E7 все вышли — слот исчез сам", _find(hud.button_container, "ShelterSlot") == null
		or (_find(hud.button_container, "ShelterSlot") as Node).is_queued_for_deletion())

# ═════════════════════════════════════════════════════════════════════════════
func _f_cursor_sound() -> void:
	print("\n═════ F. КУРСОР-ПАЛЕЦ И ЗВУК СБРОСА ═════")
	var orig = _UIAssets.cursor(2)
	verdict("F1 палец над зданием — исходная перчатка Cursor_02, не рисунок кодом",
		orig != null and _CursorArt.texture(_CursorArt.FINGER) == orig)
	verdict("F2 горячая точка — кончик пальца исходной картинки",
		_CursorArt.hotspot(_CursorArt.FINGER) == _UIAssets.cursor_hotspot(2), str(_CursorArt.hotspot(_CursorArt.FINGER)))
	var w := AudioManager._proc_click_stream(AudioManager.MENU_CLOSE_ID) as AudioStreamWAV
	var sec: float = float(w.data.size()) / 4.0 / float(w.mix_rate)
	# «Клац» — щелчок: почти вся энергия в первые 15 мс; прежний тон тянулся
	var e_head := 0.0
	var e_all := 0.0
	var n: int = w.data.size() / 4
	for i in range(n):
		var v: float = float(w.data.decode_s16(i * 4)) / 32767.0
		e_all += v * v
		if i < int(0.015 * w.mix_rate):
			e_head += v * v
	verdict("F3 звук сброса — короткий щелчок (≤ 60 мс, ≥ 75 % энергии в первые 15 мс)",
		sec <= 0.06 and e_head / maxf(e_all, 1e-9) >= 0.75, "%.3f с, доля головы %.2f" % [sec, e_head / maxf(e_all, 1e-9)])
	# Клик мимо при выделенном бойце — звучит menu_close
	var sm = main.selection_manager
	var u: Unit = null
	for x in get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(x) and not (x as Unit).is_dead():
			u = x
			break
	sm.select_units([u])
	await frames(2)
	AudioManager.ui_last = ""
	main.set_process(false)
	sm._handle_single_click(Vector2(_vp().size.x * 0.5, 4.0), false)
	await frames(2)
	verdict("F4 ЛКМ мимо при выделенном бойце — сброс и «клац»",
		sm.selected_units.is_empty() and AudioManager.ui_last == "menu_close", "последний звук «%s»" % AudioManager.ui_last)
	main.set_process(true)
