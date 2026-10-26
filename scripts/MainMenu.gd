extends Control
class_name MainMenu

## ═══════════════════════════════════════════════════════════════════════════
## ГЛАВНОЕ МЕНЮ — ЧЕТЫРЕ КНОПКИ В РАМЕ ПОВЕРХ ИЛЛЮСТРАЦИИ (ТЗ 21.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Порядок страниц прежний (заказ владельца 10.09.2026):
##
##   ГЛАВНАЯ    заголовок «10 000 копейщиков» и РОВНО ЧЕТЫРЕ кнопки:
##              START / Загрузить / Опции / Выход
##   ЗАГРУЗИТЬ  слоты сохранений (пустой слот виден, но не нажимается)
##   ОПЦИИ      окно настроек с вкладками (scripts/ui/SettingsWindow.gd) —
##              то же окно, что открывается из паузы
##
## РЕДИЗАЙН 21.10.2026: вместо тёмно-синего фона и столбца плоских кнопок —
## процедурная иллюстрация (MenuArt), кованая рама с деревянными кнопками
## (MedievalUI), настройки — модальным окном с вкладками без прокрутки, а
## загрузка партии — полноэкранным экраном с прогрессом (LoadingScreen).
##
## ВЫБОР ЖИВЁТ НА ДИСКЕ, А НЕ В ПАМЯТИ МЕНЮ: сложность — user://difficulty.cfg,
## громкость — user://audio_settings.cfg, отображение — user://view_settings.cfg.
## Раса и цвет — в GameManager (окно настроек пишет их по выбору).

const FACTION_LABELS = ["Люди", "Нежить", "Орки", "Эльфы", "Гномы"]
const FACTION_KEYS   = ["humans", "undead", "orc", "elves", "dwarves"]

const _GS       := preload("res://scripts/game_settings.gd")
const _UIAssets := preload("res://scripts/UIAssets.gd")
const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _Diff     := preload("res://scripts/game_difficulty_config.gd")
const _SaveLoad := preload("res://scripts/SaveLoadManager.gd")
const _MUI      := preload("res://scripts/ui/MedievalUI.gd")
const _Art      := preload("res://scripts/ui/MenuArt.gd")
const _Settings := preload("res://scripts/ui/SettingsWindow.gd")
const _Loading  := preload("res://scripts/ui/LoadingScreen.gd")

## Размер кнопок главной страницы
const BTN_W := 280
const BTN_H := 50

## Ссылки на элементы окна настроек (окно живёт всю жизнь меню, см. keep_alive)
var _player_opt: OptionButton
var _ai_opt:     OptionButton
var _player_color_opt: OptionButton
var _ai_color_opt:     OptionButton
var _diff_opt:   OptionButton
var _diff_hint:  Label = null

## Страницы: главная и загрузка — в раме меню; опции — окно поверх
var _page_main: VBoxContainer = null
var _page_load: VBoxContainer = null
var _page_opts: Control = null
var _menu_panel: PanelContainer = null

func _ready() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0
	theme = _MUI.theme()
	# ВЫБОР ЧИТАЕТСЯ С ДИСКА ДО ВЁРСТКИ: списки строятся уже с прошлым выбором
	_Diff.load_saved()
	_GS.load_view_settings()
	# Игровой курсор — с первого кадра меню, а не после старта партии
	_UIAssets.install_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	AudioManager.play_menu_music()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var backdrop: TextureRect = _Art.backdrop()
	if backdrop != null:
		add_child(backdrop)
	var art = _Art.new()
	art.name = "MenuArt"
	art.overlay_only = backdrop != null
	add_child(art)

	# Заголовок — один, без подзаголовка (заказ владельца)
	var head := VBoxContainer.new()
	head.name = "MenuHead"
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 36
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var title := _MUI.title_label("10 000 КОПЕЙЩИКОВ", 54)
	title.name = "MenuTitle"
	head.add_child(title)
	head.add_child(_MUI.divider(420.0))

	# Рама с кнопками — по центру, чуть ниже середины (заголовок сверху)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.offset_top = 120
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "MenuPanel"
	cc.add_child(_menu_panel)
	var stack := VBoxContainer.new()
	_menu_panel.add_child(stack)

	_page_main = VBoxContainer.new()
	_page_main.name = "PageMain"
	_page_main.add_theme_constant_override("separation", 12)
	stack.add_child(_page_main)
	_build_main_page(_page_main)

	_page_load = VBoxContainer.new()
	_page_load.name = "PageLoad"
	_page_load.add_theme_constant_override("separation", 8)
	_page_load.visible = false
	stack.add_child(_page_load)
	_build_load_page(_page_load)

	# ОКНО НАСТРОЕК строится сразу и прячется: START и стенды читают его
	# элементы, даже если игрок опции не открывал
	var win = _Settings.new()
	win.name = "PageOptions"
	win.setup(false)
	win.keep_alive = true
	add_child(win)
	win.visible = false
	win.closed.connect(func(): show_page("main"))
	_page_opts = win
	_player_opt = win.player_opt
	_ai_opt = win.ai_opt
	_player_color_opt = win.player_color_opt
	_ai_color_opt = win.ai_color_opt
	_diff_opt = win.diff_opt
	_diff_hint = win.diff_hint

	var ver := Label.new()
	ver.name = "MenuFooter"
	ver.text = "Esc — назад  ·  настройки сохраняются сразу"
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62, 0.7))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -16
	ver.offset_bottom = -10
	add_child(ver)

## Показать ровно одну страницу. Стенд зовёт её по имени
func show_page(which: String) -> void:
	if _page_main != null: _page_main.visible = (which == "main" or which == "options")
	if _page_load != null: _page_load.visible = (which == "load")
	if _page_opts != null: _page_opts.visible = (which == "options")
	# под окном настроек рама меню и заголовок не нужны — окно модальное,
	# по центру, и заголовок просвечивал бы над его рамой
	if _menu_panel != null: _menu_panel.visible = (which != "options")
	var head: Node = get_node_or_null("MenuHead")
	if head != null: (head as CanvasItem).visible = (which != "options")

## Escape на странице загрузки — назад (окно настроек ловит его само)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		if _page_load != null and _page_load.visible:
			show_page("main")
			get_viewport().set_input_as_handled()

# ═════════════════════════════════════════════════════════════════════════════
# ГЛАВНАЯ СТРАНИЦА: РОВНО ЧЕТЫРЕ КНОПКИ
# ═════════════════════════════════════════════════════════════════════════════
func _build_main_page(vbox: VBoxContainer) -> void:
	var start := _menu_button("START", "green", 24)
	start.name = "StartButton"
	start.custom_minimum_size = Vector2(BTN_W, 62)
	start.pressed.connect(_on_start)
	vbox.add_child(start)

	var load_btn := _menu_button("Загрузить", "steel")
	load_btn.name = "LoadButton"
	load_btn.pressed.connect(func(): show_page("load"))
	vbox.add_child(load_btn)

	var opt_btn := _menu_button("Опции", "wood")
	opt_btn.name = "OptionsButton"
	opt_btn.pressed.connect(func(): show_page("options"))
	vbox.add_child(opt_btn)

	var quit_btn := _menu_button("Выход", "red")
	quit_btn.name = "QuitButton"
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)

func _menu_button(text: String, kind: String, fs: int = 19) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(BTN_W, BTN_H)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	_MUI.style_button(b, kind, fs)
	return b

# ═════════════════════════════════════════════════════════════════════════════
# ПОДМЕНЮ «ЗАГРУЗИТЬ»
# ═════════════════════════════════════════════════════════════════════════════
## СЛОТЫ ВИДНЫ ВСЕГДА, ПУСТЫЕ — НЕ НАЖИМАЮТСЯ: пустой слот сообщает, что место
## есть, а партии в нём нет
func _build_load_page(vbox: VBoxContainer) -> void:
	vbox.add_child(_MUI.title_label("Загрузить партию", 24))
	vbox.add_child(_MUI.divider(260.0))
	var err_lbl := _MUI.hint_label("", 12)
	err_lbl.name = "LoadError"
	err_lbl.add_theme_color_override("font_color", Color(0.95, 0.62, 0.52))
	err_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	err_lbl.custom_minimum_size = Vector2(440, 0)

	var slots: Array = [_SaveLoad.AUTOSAVE_SLOT]
	for i in range(_SaveLoad.SLOT_COUNT):
		slots.append(i + 1)
	for s in slots:
		var slot: int = int(s)
		var has: bool = _SaveLoad.has_save(slot)
		var btn := Button.new()
		btn.name = "Slot%d" % slot
		btn.text = _SaveLoad.slot_label(slot)
		btn.custom_minimum_size = Vector2(440, 40)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = not has
		_MUI.style_button(btn, "steel", 14)
		vbox.add_child(btn)
		if not has:
			continue
		btn.pressed.connect(func():
			# Кэш листов сбрасывается ровно как при обычном старте
			_SSParser.clear_cache()
			var err: String = _SaveLoad.request_load(get_tree(), slot)
			if not err.is_empty():
				err_lbl.text = err)
	vbox.add_child(err_lbl)
	var back := _menu_button("Назад", "wood", 17)
	back.name = "BackButton"
	back.custom_minimum_size = Vector2(200, 42)
	back.pressed.connect(func(): show_page("main"))
	vbox.add_child(back)

# ═════════════════════════════════════════════════════════════════════════════
# СТАРТ ПАРТИИ И ЭКРАН ЗАГРУЗКИ
# ═════════════════════════════════════════════════════════════════════════════
func _on_start() -> void:
	# Окно настроек уже записало выбор в GameManager; читаем и сверяемся
	GameManager.player_faction_name = FACTION_KEYS[maxi(_player_opt.selected, 0)]
	GameManager.ai_faction_name     = FACTION_KEYS[maxi(_ai_opt.selected, 0)]
	GameManager.player_color = String(_GS.COLORS[maxi(_player_color_opt.selected, 0)])
	GameManager.ai_color     = String(_GS.COLORS[maxi(_ai_color_opt.selected, 0)])
	# Одинаковый цвет у сторон = неразличимые армии. Разводим принудительно
	if GameManager.player_color == GameManager.ai_color:
		for c in _GS.COLORS:
			if String(c) != GameManager.player_color:
				GameManager.ai_color = String(c)
				break
	# Кэш спрайт-листов держит НАБОРЫ ПО ПУТЯМ и переживает смену сцены
	_SSParser.clear_cache()
	_show_loader()
	await get_tree().process_frame
	await get_tree().process_frame
	# ── РЕСУРСЫ СЦЕНЫ — В ФОНЕ, С ЧЕСТНОЙ ДОЛЕЙ ─────────────────────────────
	# Пока поток грузит Main.tscn и его зависимости, кадры идут, и полоса с
	# иллюстрацией живые. Не вышло запросить фоновую загрузку — обычная
	const SCENE := "res://scenes/Main.tscn"
	var packed: PackedScene = null
	if ResourceLoader.load_threaded_request(SCENE) == OK:
		var prog: Array = []
		while true:
			var st: int = ResourceLoader.load_threaded_get_status(SCENE, prog)
			if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var p: float = float(prog[0]) if not prog.is_empty() else 0.0
				_Loading.stage("Загрузка ресурсов…", 0.04 + 0.26 * p)
				await get_tree().process_frame
				continue
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				packed = ResourceLoader.load_threaded_get(SCENE) as PackedScene
			break
	if packed == null:
		packed = load(SCENE) as PackedScene
	_Loading.stage("Подготовка карты…", 0.32)
	await get_tree().process_frame
	# Курсор на время синхронной сборки прячется (Main вернёт игровой)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	get_tree().change_scene_to_packed(packed)

## Экран загрузки (scripts/ui/LoadingScreen.gd): иллюстрация, полоса с
## процентами, советы и этапы. Висит на корне дерева и переживает смену
## сцены; закрывает его Main в конце _ready. Стенд ловит по счётчику
var loader_shown: int = 0

func _show_loader():
	var ls = _Loading.begin(get_tree(), "Подготовка ресурсов…")
	ls.set_target(0.03)
	loader_shown += 1
	return ls
