extends Control
class_name MainMenu

## ═══════════════════════════════════════════════════════════════════════════
## ГЛАВНОЕ МЕНЮ — ЧЕТЫРЕ КНОПКИ И ДВА ПОДМЕНЮ (заказ владельца 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Прежний экран был свалкой: подзаголовок, четыре выпадающих списка, ряд
## сложности со строкой-подсказкой, кнопка старта, ряд слотов сохранений,
## кнопка звука и выход — всё в одном столбце. Теперь так:
##
##   ГЛАВНАЯ    заголовок «10 000 копейщиков» и РОВНО ЧЕТЫРЕ кнопки:
##              START / Загрузить / Опции / Выход
##   ЗАГРУЗИТЬ  подменю со слотами (пустой слот виден, но не нажимается)
##   ОПЦИИ      подменю: партия (расы и цвета), сложность ВЫПАДАЮЩИМ СПИСКОМ,
##              звук (три шины) и отображение (FPS, прокрутка камеры краем)
##
## СТРАНИЦЫ — ЭТО ТРИ VBox'а В ОДНОМ КОНТЕЙНЕРЕ, а не отдельные сцены: выбор
## расы и цвета читается кнопкой «START» с той же самой страницы опций, и
## разнеси их по сценам — пришлось бы заводить второе хранилище выбора.
##
## ВЫБОР ЖИВЁТ НА ДИСКЕ, А НЕ В ПАМЯТИ МЕНЮ: сложность — user://difficulty.cfg
## (_Diff), громкость — user://audio_settings.cfg (AudioManager), отображение —
## user://view_settings.cfg (_GS). Поэтому «применить» нигде не нужно.

const FACTION_LABELS = ["Люди", "Нежить", "Орки", "Эльфы", "Гномы"]
const FACTION_KEYS   = ["humans", "undead", "orc", "elves", "dwarves"]

const _GS       := preload("res://scripts/game_settings.gd")
const _UIAssets := preload("res://scripts/UIAssets.gd")
const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
## Пресеты сложности: подписи, подсказки и сам выбор живут там
const _Diff     := preload("res://scripts/game_difficulty_config.gd")
const _GobCfgMM := preload("res://scripts/goblin/goblin_config.gd")   # срок перемирия для подписи
## Загрузка сохранённой партии прямо со стартового экрана
const _SaveLoad := preload("res://scripts/SaveLoadManager.gd")

## Ширина кнопок главной страницы и подменю
const BTN_W := 220
const BTN_H := 44

var _player_opt: OptionButton
var _ai_opt:     OptionButton
var _player_color_opt: OptionButton
var _ai_color_opt:     OptionButton
var _diff_opt:   OptionButton
var _diff_hint:  Label = null

## Страницы: главная, загрузка, опции. Видна всегда ровно одна
var _page_main: VBoxContainer = null
var _page_load: VBoxContainer = null
var _page_opts: VBoxContainer = null

func _ready() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0
	# ВЫБОР ЧИТАЕТСЯ С ДИСКА ДО ВЁРСТКИ: списки строятся уже с прошлым выбором
	_Diff.load_saved()
	_GS.load_view_settings()
	# Игровой курсор — с первого кадра меню, а не после старта партии
	_UIAssets.install_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	# Панель выбора расы играет основную тему
	AudioManager.play_menu_music()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color          = Color(0.06, 0.08, 0.14)
	bg.anchor_right   = 1.0
	bg.anchor_bottom  = 1.0
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.anchor_right  = 1.0
	scroll.anchor_bottom = 1.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	# CenterContainer внутри ScrollContainer обязан тянуться по ОБЕИМ осям:
	# прокрутка выдаёт ребёнку ровно его минимум, и свёрнутая страница
	# прижалась бы к верхней кромке вместо середины экрана
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	center.add_child(stack)

	# ЗАГОЛОВОК — ОДИН, БЕЗ ПОДЗАГОЛОВКА (заказ владельца): строка «Стратегия
	# реального времени» ничего не сообщала игроку, который её и так открыл
	var title := Label.new()
	title.name = "MenuTitle"
	title.text = "10 000 КОПЕЙЩИКОВ"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	_add_spacer(stack, 18)

	_page_main = VBoxContainer.new()
	_page_main.name = "PageMain"
	_page_main.add_theme_constant_override("separation", 10)
	stack.add_child(_page_main)
	_build_main_page(_page_main)

	_page_load = VBoxContainer.new()
	_page_load.name = "PageLoad"
	_page_load.add_theme_constant_override("separation", 8)
	_page_load.visible = false
	stack.add_child(_page_load)
	_build_load_page(_page_load)

	_page_opts = VBoxContainer.new()
	_page_opts.name = "PageOptions"
	_page_opts.add_theme_constant_override("separation", 8)
	_page_opts.visible = false
	stack.add_child(_page_opts)
	_build_options_page(_page_opts)

## Показать ровно одну страницу. Стенд зовёт её по имени, поэтому строка, а не
## enum: страниц три, и таблица соответствий была бы длиннее самой функции
func show_page(which: String) -> void:
	if _page_main != null: _page_main.visible = (which == "main")
	if _page_load != null: _page_load.visible = (which == "load")
	if _page_opts != null: _page_opts.visible = (which == "options")

# ═════════════════════════════════════════════════════════════════════════════
# ГЛАВНАЯ СТРАНИЦА: РОВНО ЧЕТЫРЕ КНОПКИ
# ═════════════════════════════════════════════════════════════════════════════
func _build_main_page(vbox: VBoxContainer) -> void:
	# START — КВАДРАТНАЯ, БЕЗ СТРЕЛОК. Чёрные треугольники по бокам («▶ НАЧАТЬ ▶»)
	# читались как кнопки перемотки, а не как акцент
	var start := Button.new()
	start.name = "StartButton"
	start.text = "START"
	start.custom_minimum_size = Vector2(BTN_W, 64)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.add_theme_font_size_override("font_size", 22)
	start.add_theme_color_override("font_color", Color(0.06, 0.10, 0.04))
	start.add_theme_color_override("font_hover_color", Color(0.06, 0.10, 0.04))
	_style_btn(start, Color(0.30, 0.82, 0.22), Color(0.42, 0.95, 0.32), Color(0.65, 1.0, 0.55))
	start.pressed.connect(_on_start)
	vbox.add_child(start)

	var load_btn := _menu_button("Загрузить", Color(0.10, 0.20, 0.32),
		Color(0.16, 0.30, 0.46), Color(0.28, 0.50, 0.72))
	load_btn.name = "LoadButton"
	load_btn.pressed.connect(func(): show_page("load"))
	vbox.add_child(load_btn)

	var opt_btn := _menu_button("Опции", Color(0.10, 0.20, 0.32),
		Color(0.16, 0.30, 0.46), Color(0.28, 0.50, 0.72))
	opt_btn.name = "OptionsButton"
	opt_btn.pressed.connect(func(): show_page("options"))
	vbox.add_child(opt_btn)

	var quit_btn := _menu_button("Выход", Color(0.28, 0.08, 0.08),
		Color(0.42, 0.12, 0.12), Color(0.60, 0.22, 0.22))
	quit_btn.name = "QuitButton"
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)

func _menu_button(text: String, normal: Color, hover: Color, border: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(BTN_W, BTN_H)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 17)
	_style_btn(b, normal, hover, border)
	return b

# ═════════════════════════════════════════════════════════════════════════════
# ПОДМЕНЮ «ЗАГРУЗИТЬ»
# ═════════════════════════════════════════════════════════════════════════════
## СЛОТЫ ВИДНЫ ВСЕГДА, ПУСТЫЕ — НЕ НАЖИМАЮТСЯ. Прежде ряд слотов пропадал с
## главного экрана целиком, если сохранений нет, — и игрок не знал, есть ли
## тут вообще загрузка. В отдельном подменю пустой слот сообщает ровно то, что
## нужно: место есть, партии в нём нет
func _build_load_page(vbox: VBoxContainer) -> void:
	vbox.add_child(_caption("Загрузить партию"))
	var err_lbl := Label.new()
	err_lbl.name = "LoadError"
	err_lbl.add_theme_font_size_override("font_size", 11)
	err_lbl.add_theme_color_override("font_color", Color(0.92, 0.66, 0.60))
	err_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err_lbl.custom_minimum_size = Vector2(420, 0)

	for i in range(_SaveLoad.SLOT_COUNT):
		var slot: int = i + 1
		var has: bool = _SaveLoad.has_save(slot)
		var btn := Button.new()
		btn.name = "Slot%d" % slot
		btn.text = _SaveLoad.slot_label(slot) if has else "Слот %d — пусто" % slot
		btn.custom_minimum_size = Vector2(420, 32)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = not has
		btn.add_theme_font_size_override("font_size", 13)
		_style_btn(btn, Color(0.12, 0.22, 0.32), Color(0.18, 0.32, 0.46),
			Color(0.30, 0.50, 0.70))
		vbox.add_child(btn)
		if not has:
			continue
		btn.pressed.connect(func():
			# Кэш листов сбрасывается ровно как при обычном старте: цвета
			# сторон приедут из сохранения, и набор прошлой партии тут не при чём
			_SSParser.clear_cache()
			var err: String = _SaveLoad.request_load(get_tree(), slot)
			if not err.is_empty():
				err_lbl.text = err)
	vbox.add_child(err_lbl)
	_add_spacer(vbox, 10)
	vbox.add_child(_back_button())

# ═════════════════════════════════════════════════════════════════════════════
# ПОДМЕНЮ «ОПЦИИ»
# ═════════════════════════════════════════════════════════════════════════════
func _build_options_page(vbox: VBoxContainer) -> void:
	# ── ПАРТИЯ: РАСЫ И ЦВЕТА ────────────────────────────────────────────────
	vbox.add_child(_caption("Партия"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	_player_opt = _make_option()
	grid.add_child(_make_option_row("Раса Игрока:", _player_opt))
	_player_color_opt = _make_color_option(_GS.DEFAULT_PLAYER_COLOR)
	grid.add_child(_make_option_row("Цвет Игрока:", _player_color_opt))
	_ai_opt = _make_option()
	grid.add_child(_make_option_row("Раса ИИ:", _ai_opt))
	_ai_color_opt = _make_color_option(_GS.DEFAULT_AI_COLOR)
	grid.add_child(_make_option_row("Цвет ИИ:", _ai_color_opt))

	# ── СЛОЖНОСТЬ — ВЫПАДАЮЩИМ СПИСКОМ (заказ владельца) ────────────────────
	# Был ряд из трёх кнопок с подсветкой выбранной: он занимал полосу в треть
	# экрана и требовал строки-подсказки под собой. В опциях сложность — такой
	# же список, как раса, а подсказка выбранного уровня осталась строкой ПОД
	# списком: в пункт списка её не положить, а объяснять выбор словами надо
	_add_spacer(vbox, 6)
	_diff_opt = OptionButton.new()
	_diff_opt.name = "DifficultyOption"
	_diff_opt.custom_minimum_size = Vector2(170, 36)
	_diff_opt.add_theme_font_size_override("font_size", 16)
	for id in _Diff.ORDER:
		_diff_opt.add_item(_Diff.label(String(id)))
	var cur: String = _Diff.current()
	for i in range(_Diff.ORDER.size()):
		if String(_Diff.ORDER[i]) == cur:
			_diff_opt.select(i)
	vbox.add_child(_make_option_row("Сложность:", _diff_opt))
	_diff_hint = Label.new()
	_diff_hint.add_theme_font_size_override("font_size", 12)
	_diff_hint.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	_diff_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_hint.custom_minimum_size = Vector2(420, 0)
	_diff_hint.text = _Diff.hint(cur)
	vbox.add_child(_diff_hint)
	# НА ДИСК ПИШЕМ СРАЗУ: файл крошечный, а отдельная кнопка «применить» —
	# лишний шаг для игрока
	_diff_opt.item_selected.connect(func(idx: int):
		var key: String = String(_Diff.ORDER[idx])
		_Diff.set_current(key)
		_Diff.save()
		_diff_hint.text = _Diff.hint(key))

	# ── ЗВУК ────────────────────────────────────────────────────────────────
	_add_spacer(vbox, 10)
	vbox.add_child(_caption("Звук"))
	_build_audio_sliders(vbox)

	# ── ОТОБРАЖЕНИЕ ─────────────────────────────────────────────────────────
	_add_spacer(vbox, 10)
	vbox.add_child(_caption("Отображение"))
	var fps_box := CheckBox.new()
	fps_box.name = "FpsCheck"
	fps_box.text = "Отображать FPS"
	fps_box.button_pressed = _GS.show_fps()
	fps_box.add_theme_font_size_override("font_size", 15)
	fps_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(fps_box)
	fps_box.toggled.connect(func(on: bool):
		_GS.set_show_fps(on))

	var cam_box := CheckBox.new()
	cam_box.name = "EdgePanCheck"
	cam_box.text = "Камера едет от края экрана"
	cam_box.button_pressed = _GS.edge_pan()
	cam_box.add_theme_font_size_override("font_size", 15)
	cam_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(cam_box)
	cam_box.toggled.connect(func(on: bool):
		_GS.set_edge_pan(on))

	# ── ПЕРЕМИРИЕ (ТЗ 14.09.2026, п. 2) ─────────────────────────────────────
	# Та же ручка, что в паузе (HUD._add_armistice_toggle): game_settings.armistice
	_add_spacer(vbox, 10)
	vbox.add_child(_caption("Партия"))
	var truce_box := CheckBox.new()
	truce_box.name = "ArmisticeCheck"
	truce_box.text = "Перемирие (первые %d мин без атак ИИ)" % int(round(_GobCfgMM.TRUCE_SEC / 60.0))
	truce_box.button_pressed = _GS.armistice()
	truce_box.add_theme_font_size_override("font_size", 15)
	truce_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(truce_box)
	truce_box.toggled.connect(func(on: bool):
		_GS.set_armistice(on))

	_add_spacer(vbox, 10)
	vbox.add_child(_back_button())

func _back_button() -> Button:
	var b := _menu_button("Назад", Color(0.14, 0.16, 0.22),
		Color(0.20, 0.24, 0.32), Color(0.34, 0.38, 0.48))
	b.name = "BackButton"
	b.pressed.connect(func(): show_page("main"))
	return b

func _caption(text: String) -> Label:
	var cap := Label.new()
	cap.text = text
	cap.add_theme_font_size_override("font_size", 15)
	cap.add_theme_color_override("font_color", Color(0.82, 0.84, 0.90))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return cap

## Те же три шины, что и в меню паузы. Значения берутся и пишутся через
## AudioManager, поэтому выставленное здесь сразу действует и переживает
## старт партии — настройки лежат в user://audio_settings.cfg
const MENU_BUSES := [
	{"bus": "Master", "name": "Общая"},
	{"bus": "Music",  "name": "Музыка"},
	{"bus": "SFX",    "name": "Эффекты"},
]

func _build_audio_sliders(box: VBoxContainer) -> void:
	for entry in MENU_BUSES:
		var e: Dictionary = entry
		var bus: String = String(e["bus"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(row)
		var cap := Label.new()
		cap.text = String(e["name"])
		cap.custom_minimum_size = Vector2(96, 0)
		cap.add_theme_font_size_override("font_size", 15)
		cap.add_theme_color_override("font_color", Color(0.78, 0.80, 0.88))
		row.add_child(cap)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step      = 0.01
		sl.value     = AudioManager.get_bus_volume(bus)
		sl.custom_minimum_size = Vector2(190, 22)
		row.add_child(sl)
		var pct := Label.new()
		pct.text = "%d%%" % int(sl.value * 100.0)
		pct.custom_minimum_size = Vector2(48, 0)
		pct.add_theme_font_size_override("font_size", 15)
		pct.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86))
		row.add_child(pct)
		sl.value_changed.connect(func(v: float):
			AudioManager.set_bus_volume(bus, v)
			pct.text = "%d%%" % int(v * 100.0)
			AudioManager.save_settings())

func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.82, 0.84, 0.90))
	return lbl

## Подпись + выпадающий список в одной строке (вместо подписи НАД списком)
func _make_option_row(text: String, opt: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(112, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.82, 0.84, 0.90))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	row.add_child(opt)
	return row

func _make_option() -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(170, 36)
	opt.add_theme_font_size_override("font_size", 16)
	for lbl in FACTION_LABELS:
		opt.add_item(lbl)
	return opt

## Список цветов с квадратиком-образцом у каждого пункта
func _make_color_option(default_color: String) -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(170, 36)
	opt.add_theme_font_size_override("font_size", 15)
	for i in range(_GS.COLORS.size()):
		var key: String = _GS.COLORS[i]
		opt.add_item(String(_GS.COLOR_LABELS[i]))
		opt.set_item_icon(i, _color_swatch(_GS.color_tint(key)))
		if key == default_color:
			opt.select(i)
	return opt

## Маленькая цветная плашка 22x22 для пункта списка
func _color_swatch(c: Color) -> ImageTexture:
	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	img.fill(c)
	# Тёмная рамка, чтобы светлые цвета не сливались с фоном списка
	var border := Color(0.06, 0.07, 0.10)
	for i in range(22):
		img.set_pixel(i, 0, border);  img.set_pixel(i, 21, border)
		img.set_pixel(0, i, border);  img.set_pixel(21, i, border)
	return ImageTexture.create_from_image(img)

func _add_spacer(parent: VBoxContainer, height: int) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, height)
	parent.add_child(sp)

func _style_btn(btn: Button, normal: Color, hover: Color, border: Color) -> void:
	var sn := StyleBoxFlat.new()
	sn.bg_color = normal; sn.border_color = border
	sn.set_border_width_all(2); sn.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", sn)
	var sh := StyleBoxFlat.new()
	sh.bg_color = hover; sh.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := StyleBoxFlat.new()
	sp.bg_color = normal.darkened(0.2); sp.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("pressed", sp)
	var sd := StyleBoxFlat.new()
	sd.bg_color = normal.darkened(0.55); sd.border_color = border.darkened(0.5)
	sd.set_border_width_all(2); sd.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("disabled", sd)

func _on_start() -> void:
	var pi: int = maxi(_player_opt.selected, 0)
	var ai: int = maxi(_ai_opt.selected, 0)
	GameManager.player_faction_name = FACTION_KEYS[pi]
	GameManager.ai_faction_name     = FACTION_KEYS[ai]

	var pc: int = maxi(_player_color_opt.selected, 0)
	var ac: int = maxi(_ai_color_opt.selected, 0)
	GameManager.player_color = String(_GS.COLORS[pc])
	GameManager.ai_color     = String(_GS.COLORS[ac])
	# Одинаковый цвет у сторон = неразличимые армии. Разводим принудительно
	if GameManager.player_color == GameManager.ai_color:
		for c in _GS.COLORS:
			if String(c) != GameManager.player_color:
				GameManager.ai_color = String(c)
				break
	# Кэш спрайт-листов держит НАБОРЫ ПО ПУТЯМ и переживает смену сцены —
	# сбрасываем, чтобы новая партия не подхватила цвета прошлой
	_SSParser.clear_cache()
	# ── ИГРОВОЙ ЭКРАН ЗАГРУЗКИ ВМЕСТО СИСТЕМНОГО КРУЖКА (спринт 17) ─────────
	# Сцена партии строится синхронно (рельеф, лес, тысяча бойцов), и на это
	# время окно не отвечает: ОС показывала свой курсор ожидания поверх меню.
	# Теперь на экран выводится игровая плашка загрузки, ей даётся два кадра
	# на отрисовку, курсор на время сборки прячется (Main вернёт его вместе с
	# игровым курсором), и только потом грузится сцена
	_show_loader()
	await get_tree().process_frame
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

## Плашка загрузки: затемнение, надпись и вращающийся кольцевой индикатор
## (крутится, пока кадры идут; на время синхронной сборки замирает — это
## честная картинка, а не системный кружок). Стенд ловит её по имени узла
var loader_shown: int = 0

func _show_loader() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LoadingLayer"
	layer.layer = 100
	var back := ColorRect.new()
	back.name = "LoadingBack"
	back.color = Color(0.03, 0.05, 0.03, 0.96)
	back.anchor_right = 1.0
	back.anchor_bottom = 1.0
	layer.add_child(back)
	var spin := _LoaderSpinner.new()
	spin.name = "LoadingSpinner"
	spin.anchor_left = 0.5
	spin.anchor_right = 0.5
	spin.anchor_top = 0.5
	spin.anchor_bottom = 0.5
	spin.offset_left = -40
	spin.offset_right = 40
	spin.offset_top = -80
	spin.offset_bottom = 0
	layer.add_child(spin)
	var lbl := Label.new()
	lbl.name = "LoadingLabel"
	lbl.text = "Загрузка карты…"
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 0.80))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.5
	lbl.anchor_bottom = 0.5
	lbl.offset_top = 12
	lbl.offset_bottom = 52
	layer.add_child(lbl)
	add_child(layer)
	loader_shown += 1

## Кольцевой индикатор, нарисованный кодом: дуга бежит по кругу
class _LoaderSpinner extends Control:
	var _t: float = 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.42
		draw_arc(c, r, 0.0, TAU, 48, Color(0.25, 0.35, 0.22), 6.0, true)
		var a0: float = fmod(_t * 4.0, TAU)
		draw_arc(c, r, a0, a0 + TAU * 0.3, 24, Color(0.45, 0.95, 0.35), 6.0, true)
