extends Control

## ═══════════════════════════════════════════════════════════════════════════
## ОКНО НАСТРОЕК С ВКЛАДКАМИ (ТЗ 21.10.2026, редизайн меню)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: настройки — одна длинная лента сверху вниз, её приходится крутить
## (и в главном меню, и в паузе). Теперь ОДНО окно для обоих мест: рама по
## центру экрана, три вкладки, внутри каждой — две колонки «название |
## переключатель». Всё помещается без прокрутки уже при 1280x720.
##
##   «Партия»   раса и цвет игрока/ИИ, сложность, перемирие, автосохранение
##   «Звук»     общая громкость, музыка, эффекты (ползунок + проценты)
##   «Графика»  V-Sync, отображение FPS, камера от края экрана
##
## ДВА РЕЖИМА — in_game. В меню раса и цвет выбираются (их читает START через
## player_opt/…); в партии они уже розданы и показываются погашенными с
## текущим выбором. Подсказка сложности в партии честно говорит, что меняется
## сразу, а что — со следующей партии (прежнее правило паузы).
##
## ВСЕ РУЧКИ ПИШУТ НА ДИСК СРАЗУ, как и раньше: сложность — _Diff, громкость —
## AudioManager, отображение/перемирие/автосохранение — game_settings. Кнопки
## «Применить» нет. Имена узлов прежние (DifficultyOption, AutosaveOption,
## ArmisticeCheck, FpsCheck, EdgePanCheck) — по ним ищут стенды.
##
## PROCESS_MODE_ALWAYS ставится КАЖДОМУ элементу явно: в партии окно живёт на
## паузе, и стенд qa_audio G2 проверяет режим у самих ползунков.

signal closed

const _MUI      := preload("res://scripts/ui/MedievalUI.gd")
const _GS       := preload("res://scripts/game_settings.gd")
const _Diff     := preload("res://scripts/game_difficulty_config.gd")
const _GobCfg   := preload("res://scripts/goblin/goblin_config.gd")

const FACTION_LABELS = ["Люди", "Нежить", "Орки", "Эльфы", "Гномы"]
const FACTION_KEYS   = ["humans", "undead", "orc", "elves", "dwarves"]

const AUDIO_BUSES := [
	{"bus": "Master", "name": "Общая громкость"},
	{"bus": "Music",  "name": "Музыка"},
	{"bus": "SFX",    "name": "Эффекты"},
]

## Ширина окна и колонок. Окно сужается под узкий экран (см. _fit)
const WIN_W := 760.0
const LABEL_W := 230.0
const CTRL_W := 300.0

var in_game: bool = false

var player_opt: OptionButton = null
var ai_opt: OptionButton = null
var player_color_opt: OptionButton = null
var ai_color_opt: OptionButton = null
var diff_opt: OptionButton = null
var diff_hint: Label = null
var tabs: TabContainer = null
var panel: PanelContainer = null

func setup(game: bool) -> void:
	in_game = game

func _ready() -> void:
	name = "SettingsWindow" if name.is_empty() or name.begins_with("@") else name
	theme = _MUI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.name = "SettingsDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	panel = PanelContainer.new()
	panel.name = "SettingsPanel"
	cc.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(_MUI.title_label("Настройки", 30))
	col.add_child(_MUI.divider(320.0))

	tabs = TabContainer.new()
	tabs.name = "SettingsTabs"
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	tabs.process_mode = Node.PROCESS_MODE_ALWAYS
	tabs.focus_mode = Control.FOCUS_NONE
	col.add_child(tabs)
	tabs.add_child(_tab_game())
	tabs.add_child(_tab_sound())
	tabs.add_child(_tab_video())
	tabs.tab_changed.connect(func(_i: int): AudioManager.play_ui("menu_tab"))

	var back := Button.new()
	back.name = "SettingsBack"
	back.text = "Назад" if not in_game else "Готово"
	back.custom_minimum_size = Vector2(220, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.process_mode = Node.PROCESS_MODE_ALWAYS
	_MUI.style_button(back, "wood", 18)
	back.pressed.connect(close)
	col.add_child(back)
	_fit()
	get_viewport().size_changed.connect(_fit)

## Под узкий экран окно сужается, колонки — следом (контролы растягиваются)
func _fit() -> void:
	if panel == null or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	panel.custom_minimum_size = Vector2(minf(WIN_W, vp.x - 32.0), 0)

## В главном меню окно живёт всю жизнь меню и только прячется (keep_alive):
## выбор расы/цвета и стенды читают его элементы и при закрытом окне
var keep_alive: bool = false

func close() -> void:
	closed.emit()
	if keep_alive:
		hide()
	else:
		queue_free()

## Escape закрывает окно настроек, а не всю паузу/меню под ним
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		close()

# ═════════════════════════════════════════════════════════════════════════════
# СЕТКА ВКЛАДКИ: две колонки
# ═════════════════════════════════════════════════════════════════════════════
func _grid(tab_name: String) -> GridContainer:
	var g := GridContainer.new()
	g.name = tab_name
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 12)
	g.process_mode = Node.PROCESS_MODE_ALWAYS
	return g

func _row(g: GridContainer, text: String, ctrl: Control, hint: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(LABEL_W, 36)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", _MUI.TEXT_DIM)
	g.add_child(l)
	ctrl.process_mode = Node.PROCESS_MODE_ALWAYS
	if hint.is_empty():
		ctrl.custom_minimum_size.x = maxf(ctrl.custom_minimum_size.x, CTRL_W)
		g.add_child(ctrl)
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size = Vector2(CTRL_W, 0)
	ctrl.custom_minimum_size.x = maxf(ctrl.custom_minimum_size.x, CTRL_W)
	box.add_child(ctrl)
	var h := _MUI.hint_label(hint, 12)
	h.custom_minimum_size = Vector2(CTRL_W, 0)
	box.add_child(h)
	g.add_child(box)
	return h

func _option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(CTRL_W, 36)
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 16)
	for it in items:
		o.add_item(String(it))
	o.get_popup().process_mode = Node.PROCESS_MODE_ALWAYS
	_MUI.wire_sound(o, "menu_tab")
	return o

func _check(node_name: String, text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.name = node_name
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 15)
	_MUI.wire_sound(c, "menu_button")
	return c

# ═════════════════════════════════════════════════════════════════════════════
# ВКЛАДКА «ПАРТИЯ»
# ═════════════════════════════════════════════════════════════════════════════
func _tab_game() -> Control:
	var g := _grid("Партия")
	player_opt = _option(FACTION_LABELS)
	player_opt.name = "PlayerRaceOption"
	player_opt.select(maxi(FACTION_KEYS.find(GameManager.player_faction_name), 0))
	_row(g, "Раса игрока", player_opt)
	player_color_opt = _color_option(GameManager.player_color, _GS.DEFAULT_PLAYER_COLOR)
	player_color_opt.name = "PlayerColorOption"
	_row(g, "Цвет игрока", player_color_opt)
	ai_opt = _option(FACTION_LABELS)
	ai_opt.name = "AiRaceOption"
	ai_opt.select(maxi(FACTION_KEYS.find(GameManager.ai_faction_name), 0))
	_row(g, "Раса противника", ai_opt)
	ai_color_opt = _color_option(GameManager.ai_color, _GS.DEFAULT_AI_COLOR)
	ai_color_opt.name = "AiColorOption"
	_row(g, "Цвет противника", ai_color_opt)
	# В меню выбор сразу уезжает в GameManager — его и читает START
	player_opt.item_selected.connect(func(i: int): GameManager.player_faction_name = FACTION_KEYS[i])
	ai_opt.item_selected.connect(func(i: int): GameManager.ai_faction_name = FACTION_KEYS[i])
	player_color_opt.item_selected.connect(func(i: int): GameManager.player_color = String(_GS.COLORS[i]))
	ai_color_opt.item_selected.connect(func(i: int): GameManager.ai_color = String(_GS.COLORS[i]))
	# В партии стороны уже розданы: видно, кто есть кто, но не меняется
	if in_game:
		for o in [player_opt, player_color_opt, ai_opt, ai_color_opt]:
			(o as OptionButton).disabled = true
			(o as OptionButton).tooltip_text = "Выбирается до начала партии"

	diff_opt = _option([])
	diff_opt.name = "DifficultyOption"
	for id in _Diff.ORDER:
		diff_opt.add_item(_Diff.label(String(id)))
	var cur: String = _Diff.current()
	for i in range(_Diff.ORDER.size()):
		if String(_Diff.ORDER[i]) == cur:
			diff_opt.select(i)
	diff_hint = _row(g, "Сложность", diff_opt, _diff_text(cur))
	# НА ДИСК ПИШЕМ СРАЗУ: файл крошечный, «применить» — лишний шаг
	diff_opt.item_selected.connect(func(idx: int):
		var key: String = String(_Diff.ORDER[idx])
		_Diff.set_current(key)
		_Diff.save()
		if diff_hint != null:
			diff_hint.text = _diff_text(key))

	var truce := _check("ArmisticeCheck",
		"первые %d мин без атак ИИ" % int(round(_GobCfg.TRUCE_SEC / 60.0)), _GS.armistice())
	_row(g, "Перемирие", truce)
	truce.toggled.connect(func(on: bool): _GS.set_armistice(on))

	var auto := _option(_GS.AUTOSAVE_LABELS)
	auto.name = "AutosaveOption"
	auto.select(_GS.autosave_choice_index())
	_row(g, "Автосохранение", auto)
	auto.item_selected.connect(func(idx: int):
		_GS.set_autosave_minutes(int(_GS.AUTOSAVE_CHOICES[idx]))
		# В партии смена интервала начинает отсчёт заново
		var m = GameManager.main
		if m != null and is_instance_valid(m) and m.get("autosave") != null:
			m.autosave.reset_timer())
	return g

func _diff_text(key: String) -> String:
	var s: String = _Diff.hint(key)
	if in_game:
		s += ". Лимиты и темп противника — сразу; стартовый запас и отряды — со следующей партии."
	return s

## Список цветов с квадратиком-образцом. Выбор — текущий цвет стороны, если он
## из списка, иначе умолчание
func _color_option(current: String, fallback: String) -> OptionButton:
	var o := _option([])
	var want: String = current if _GS.COLORS.has(current) else fallback
	for i in range(_GS.COLORS.size()):
		var key: String = _GS.COLORS[i]
		o.add_item(String(_GS.COLOR_LABELS[i]))
		o.set_item_icon(i, _swatch(_GS.color_tint(key)))
		if key == want:
			o.select(i)
	return o

static func _swatch(c: Color) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(c)
	var border := Color(0.10, 0.06, 0.04)
	for i in range(20):
		img.set_pixel(i, 0, border);  img.set_pixel(i, 19, border)
		img.set_pixel(0, i, border);  img.set_pixel(19, i, border)
	return ImageTexture.create_from_image(img)

# ═════════════════════════════════════════════════════════════════════════════
# ВКЛАДКА «ЗВУК»
# ═════════════════════════════════════════════════════════════════════════════
func _tab_sound() -> Control:
	var g := _grid("Звук")
	for entry in AUDIO_BUSES:
		var e: Dictionary = entry
		var bus: String = String(e["bus"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var sl := HSlider.new()
		sl.name = "Slider" + bus
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.01
		sl.value = AudioManager.get_bus_volume(bus)
		sl.custom_minimum_size = Vector2(CTRL_W - 70.0, 30)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.focus_mode = Control.FOCUS_NONE
		sl.process_mode = Node.PROCESS_MODE_ALWAYS
		row.add_child(sl)
		var pct := Label.new()
		pct.text = "%d%%" % int(round(sl.value * 100.0))
		pct.custom_minimum_size = Vector2(58, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct.add_theme_font_size_override("font_size", 16)
		pct.add_theme_color_override("font_color", _MUI.GOLD_TITLE)
		row.add_child(pct)
		# Громкость — на лету, на диск — тем же обработчиком
		sl.value_changed.connect(func(v: float):
			AudioManager.set_bus_volume(bus, v)
			pct.text = "%d%%" % int(round(v * 100.0))
			AudioManager.save_settings())
		_row(g, String(e["name"]), row)
	return g

# ═════════════════════════════════════════════════════════════════════════════
# ВКЛАДКА «ГРАФИКА»
# ═════════════════════════════════════════════════════════════════════════════
func _tab_video() -> Control:
	var g := _grid("Графика")
	# V-Sync: пока включён, FPS упирается в развёртку монитора, и любой замер
	# производительности показывает её частоту (см. HUD, «инженерный переключатель»)
	var vs := _check("VsyncCheck", "кадры по развёртке монитора",
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)
	_row(g, "Вертикальная синхронизация", vs, "выключите для честного замера FPS")
	vs.toggled.connect(func(on: bool):
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0)
	var fps := _check("FpsCheck", "счётчик в правом верхнем углу", _GS.show_fps())
	_row(g, "Отображать FPS", fps)
	fps.toggled.connect(func(on: bool):
		_GS.set_show_fps(on)
		# в партии счётчик уже построен — показываем/прячем сразу
		var m = GameManager.main
		if m != null and is_instance_valid(m) and m.get("hud") != null:
			var lbl = m.hud.get("_fps_label")
			if lbl != null and is_instance_valid(lbl):
				lbl.visible = on)
	var edge := _check("EdgePanCheck", "прокрутка мышью у кромки", _GS.edge_pan())
	_row(g, "Камера от края экрана", edge)
	edge.toggled.connect(func(on: bool): _GS.set_edge_pan(on))
	return g
