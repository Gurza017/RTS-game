extends Control
class_name MainMenu

const FACTION_LABELS = ["Люди", "Нежить", "Орки", "Эльфы", "Гномы"]
const FACTION_KEYS   = ["humans", "undead", "orc", "elves", "dwarves"]

const _GS       := preload("res://scripts/game_settings.gd")
const _SSParser := preload("res://scripts/SpriteSheetParser.gd")

var _player_opt: OptionButton
var _ai_opt:     OptionButton
var _player_color_opt: OptionButton
var _ai_color_opt:     OptionButton

func _ready() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0
	_build_ui()
	# Панель выбора расы играет основную тему
	AudioManager.play_menu_music()

## ВЕРСТКА СТАРТОВОГО ЭКРАНА — КОМПАКТНАЯ, С ГАРАНТИЕЙ ПОМЕЩЕНИЯ В ОКНО.
## Раньше separation=20 у vbox складывался ЕЩЁ и с явными _add_spacer() между
## теми же самыми элементами (двойной отступ), а сам блок стоял в
## CenterContainer, который при переполнении не обрезает контент, а раздвигает
## его симметрично за оба края окна — так кнопка «Старт» пряталась под нижней
## границей. Итоговая высота той версты ~970px против 720px окна.
## Здесь: ужатые отступы, раса+цвет сведены в HBox-строки, все четыре строки —
## в GridContainer 2×2 (Игрок/ИИ × Раса/Цвет), а сверху — ScrollContainer как
## страховка на случай ещё меньшего разрешения, чем 1280×720.
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

	var center := CenterContainer.new()
	# Заполняет всю ширину скролла, чтобы CenterContainer мог отцентровать
	# vbox по горизонтали; по высоте раскладка выше — скролл сам решает,
	# нужна ли прокрутка, сравнивая её с высотой окна
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	# Заголовок — шрифт и отступ над ним уменьшены
	var title := Label.new()
	title.text = "10 000 КОПЕЙЩИКОВ"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Стратегия реального времени"
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.60, 0.62, 0.72))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	_add_spacer(vbox, 8)

	# Раса и цвет сведены в сетку 2×2: строка — сторона (Игрок/ИИ),
	# столбец — параметр (Раса/Цвет). Вдвое ниже прежних четырёх пар
	# «подпись сверху + выпадающий список»
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

	_add_spacer(vbox, 14)

	# Кнопка старт — заметная, но КОМПАКТНАЯ и соразмерная соседним.
	# Была 360×56 во всю ширину плашки; ширина ополовинена (180), а
	# SHRINK_CENTER не даёт VBoxContainer растянуть её по ширине сетки 2×2
	var btn := Button.new()
	btn.text = "▶  НАЧАТЬ  ▶"
	btn.custom_minimum_size = Vector2(180, 44)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.06, 0.10, 0.04))
	btn.add_theme_color_override("font_hover_color", Color(0.06, 0.10, 0.04))
	_style_btn(btn, Color(0.30, 0.82, 0.22), Color(0.42, 0.95, 0.32), Color(0.65, 1.0, 0.55))
	btn.pressed.connect(_on_start)
	vbox.add_child(btn)

	_add_spacer(vbox, 10)

	# ─── ОПЦИИ ЗВУКА ПРЯМО В ГЛАВНОМ МЕНЮ ────────────────────────────────────
	# Раньше громкость крутилась только внутри партии через Escape: игрок,
	# которому меню грянуло слишком громко, не мог сделать тише, не начав игру.
	# Кнопка разворачивает три ползунка на месте, не уводя на отдельный экран
	var opt_btn := Button.new()
	opt_btn.text = "  Опции звука  "
	opt_btn.custom_minimum_size = Vector2(180, 34)
	opt_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	opt_btn.add_theme_font_size_override("font_size", 15)
	_style_btn(opt_btn, Color(0.10, 0.20, 0.32), Color(0.16, 0.30, 0.46), Color(0.28, 0.50, 0.72))
	vbox.add_child(opt_btn)

	_audio_box = VBoxContainer.new()
	_audio_box.add_theme_constant_override("separation", 4)
	_audio_box.visible = false
	vbox.add_child(_audio_box)
	_build_audio_sliders(_audio_box)
	opt_btn.pressed.connect(func():
		_audio_box.visible = not _audio_box.visible
		opt_btn.text = "  Опции звука ▲  " if _audio_box.visible else "  Опции звука  ")

	_add_spacer(vbox, 8)

	var quit_btn := Button.new()
	quit_btn.text = "  Выход  "
	quit_btn.custom_minimum_size = Vector2(180, 34)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.add_theme_font_size_override("font_size", 15)
	_style_btn(quit_btn, Color(0.28, 0.08, 0.08), Color(0.42, 0.12, 0.12), Color(0.60, 0.22, 0.22))
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)
	_add_spacer(vbox, 4)

## Панель ползунков громкости в главном меню
var _audio_box: VBoxContainer = null

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

## Подпись + выпадающий список в одной строке (вместо подписи НАД списком) —
## вдвое компактнее по высоте; используется в сетке 2×2 расы/цвета
func _make_option_row(text: String, opt: OptionButton) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
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

func _on_start() -> void:
	var pi: int = _player_opt.selected
	var ai: int = _ai_opt.selected
	GameManager.player_faction_name = FACTION_KEYS[pi]
	GameManager.ai_faction_name     = FACTION_KEYS[ai]

	var pc: int = _player_color_opt.selected
	var ac: int = _ai_color_opt.selected
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

	get_tree().change_scene_to_file("res://scenes/Main.tscn")
