extends PanelContainer
## ОКНО РЫНКА (ТЗ 27.10.2026, п. 4; пересобрано ТЗ 29.10.2026) — калькулятор
## обмена «как в Казаках».
##
## ОДНА ПАНЕЛЬ (ТЗ 29.10.2026): нижняя карточка здания с текстами («Рынок
## 3000/3000 HP», «Обмен ресурсов — окно над панелью») и заголовок «Рынок»
## сняты — HUD прячет нижнюю панель, пока выделен рынок, и ставит окно на её
## место. Иконка здания — в правом верхнем углу (подсказка — имя и HP).
## Строки «Продать» и «Купить» — четыре ресурса, кнопки начинаются с одной
## вертикали (подписи одной ширины). Внизу — «Количество [−] [поле] [+]
## [Всё]», итог по курсу (Market.quote), курс с пошлиной и «Обменять».
##
## КОЛИЧЕСТВО — ПО СЕТКЕ MARKET.steps (100 … 20 000): «−/+» и колесо мыши
## над полем ходят по сетке; ввод с клавиатуры и «Всё» зажимаются в
## [lot_min, lot_max]. Готовых кнопок партий больше нет (ТЗ 29.10.2026).
## Поле теряет фокус при клике мимо и по Enter: цифры, набранные потом для
## горячих групп (SelectionManager), в количество не уходят.
##
## ИКОНКИ ОБРЕЗАНЫ ПО РИСУНКУ (_trimmed): Rock2 и самородок взяты из мировых
## спрайтов, где картинка сидит посреди прозрачного холста.
##
## Окно стоит ВНЕ прямоугольника нижней панели — HUD кладёт его в
## _focus_panels(): клик по просвету окна не проваливается в мир.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _MUI := preload("res://scripts/ui/MedievalUI.gd")
const _MarketS := preload("res://scripts/Market.gd")

const RES := [
	{"t": Constants.RESOURCE_WOOD,  "name": "дерево", "icon": "res://assets/factions/humans/icons/hud/Woods.png"},
	{"t": Constants.RESOURCE_STONE, "name": "камень", "icon": "res://assets/environment/resources/Rock2.png"},
	{"t": Constants.RESOURCE_GOLD,  "name": "золото", "icon": "res://assets/environment/resources/Gold Stone 3.png"},
	{"t": Constants.RESOURCE_FOOD,  "name": "еда",    "icon": "res://assets/factions/humans/icons/hud/Meat.png"},
]
const BTN := 46.0
## Ширина подписи строки: кнопки всех строк начинаются с одной вертикали
const CAPTION_W := 112.0
## Иконка здания в правом верхнем углу
const ICON_PX := 72.0

var market: Node = null
var give_t: int = Constants.RESOURCE_WOOD
var get_t: int = Constants.RESOURCE_GOLD
var lot: float = 1000.0

var _give_btns: Dictionary = {}
var _get_btns: Dictionary = {}
var _lot_edit: LineEdit = null
## Не хватает запаса на количество — строка итога краснеет
const SHORT_COL := Color(0.95, 0.42, 0.36)
var _stock_lbls: Dictionary = {}
var _result: Label = null
var _rate: Label = null
var _go: Button = null
var _icon: TextureRect = null

static func steps() -> Array:
	return _UCfg.MARKET["steps"]

static func lot_min() -> float:
	return float(_UCfg.MARKET["lot_min"])

static func lot_max() -> float:
	return float(_UCfg.MARKET["lot_max"])

func _ready() -> void:
	name = "MarketPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _MUI.frame_style(16.0))
	theme = _MUI.theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	# ── Верх: строки ресурсов слева, иконка здания справа ─────────────────
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.add_child(_row("Продать", _give_btns, true))
	rows.add_child(_row("Купить", _get_btns, false))
	top.add_child(rows)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	_icon = TextureRect.new()
	_icon.name = "MarketIcon"
	_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var ip: String = String(_UCfg.building_cfg("market").get("icon", ""))
	if ip != "" and ResourceLoader.exists(ip):
		_icon.texture = _trimmed(ip)
	top.add_child(_icon)
	v.add_child(top)
	lot = clampf(1000.0, lot_min(), lot_max())
	# ── Низ: «Количество  [−] [ 1 000 ] [+] [Всё]» ────────────────────────
	var qty := HBoxContainer.new()
	qty.add_theme_constant_override("separation", 6)
	var ll := Label.new()
	ll.text = "Количество"
	ll.custom_minimum_size = Vector2(CAPTION_W, 0)
	ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qty.add_child(ll)
	qty.add_child(_small_btn("MarketMinus", "−", 34, func(): _step_lot(-1)))
	_lot_edit = LineEdit.new()
	_lot_edit.name = "MarketLot"
	_lot_edit.custom_minimum_size = Vector2(112, 32)
	_lot_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lot_edit.max_length = 7
	_lot_edit.select_all_on_focus = true
	_lot_edit.context_menu_enabled = false
	_lot_edit.add_theme_font_size_override("font_size", 17)
	_lot_edit.tooltip_text = "Введите количество или крутите колесо мыши"
	_lot_edit.text_submitted.connect(func(_t): _commit_edit(true))
	_lot_edit.focus_exited.connect(func(): _commit_edit(false))
	_lot_edit.gui_input.connect(_on_edit_input)
	qty.add_child(_lot_edit)
	qty.add_child(_small_btn("MarketPlus", "+", 34, func(): _step_lot(1)))
	qty.add_child(_small_btn("MarketAll", "Всё", 56, _lot_all))
	v.add_child(qty)
	_result = Label.new()
	_result.name = "MarketResult"
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 16)
	v.add_child(_result)
	_rate = _MUI.hint_label("", 11)
	_rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_rate)
	_go = Button.new()
	_go.name = "MarketTrade"
	_go.text = "Обменять"
	_go.custom_minimum_size = Vector2(160, 34)
	_go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_MUI.style_button(_go, "wood", 17)
	_go.pressed.connect(do_trade)
	v.add_child(_go)
	ResourceManager.resources_changed.connect(_on_res)
	_refresh()

func _row(caption: String, store: Dictionary, give: bool) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = caption
	l.custom_minimum_size = Vector2(CAPTION_W, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	for r in RES:
		var t: int = int(r["t"])
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(BTN, BTN)
		b.tooltip_text = String(r["name"])
		_MUI.style_button(b, "wood", 12)
		var tex: Texture2D = _trimmed(String(r["icon"]))
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tr.offset_left = 7; tr.offset_top = 5; tr.offset_right = -7; tr.offset_bottom = -12
			b.add_child(tr)
		else:
			b.text = String(r["name"])
		if give:
			var sl := Label.new()
			sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sl.add_theme_font_size_override("font_size", 10)
			sl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
			sl.add_theme_constant_override("outline_size", 3)
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			sl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			sl.offset_bottom = -1
			b.add_child(sl)
			_stock_lbls[t] = sl
			b.pressed.connect(func(): _set_give(t))
		else:
			b.pressed.connect(func(): _set_get(t))
		h.add_child(b)
		store[t] = b
	return h

func _set_give(t: int) -> void:
	give_t = t
	if get_t == give_t:
		get_t = Constants.RESOURCE_GOLD if t != Constants.RESOURCE_GOLD else Constants.RESOURCE_WOOD
	_refresh()

func _set_get(t: int) -> void:
	get_t = t
	if get_t == give_t:
		give_t = Constants.RESOURCE_WOOD if t != Constants.RESOURCE_WOOD else Constants.RESOURCE_GOLD
	_refresh()

func _set_lot(a: float) -> void:
	lot = clampf(floorf(a), lot_min(), lot_max())
	_refresh()

func _small_btn(nm: String, txt: String, w: float, cb: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.custom_minimum_size = Vector2(w, 32)
	_MUI.style_button(b, "wood", 17)
	b.pressed.connect(cb)
	return b

## Следующая ступень сетки вверх (dir > 0) или вниз от текущего количества:
## 1 000 → «+» → 2 000; 1 300 → «−» → 1 000, «+» → 2 000
static func next_step(cur: float, dir: int) -> float:
	var st: Array = steps()
	if dir > 0:
		for s in st:
			if float(s) > cur + 0.5:
				return float(s)
		return float(st[st.size() - 1])
	for i in range(st.size() - 1, -1, -1):
		if float(st[i]) < cur - 0.5:
			return float(st[i])
	return float(st[0])

func _step_lot(dir: int) -> void:
	_set_lot(next_step(lot, dir))

## «Всё»: весь запас продаваемого ресурса в пределах [lot_min, lot_max]
func _lot_all() -> void:
	_set_lot(floorf(ResourceManager.get_amount(Constants.FACTION_PLAYER, give_t)))

func _commit_edit(submit: bool) -> void:
	if _lot_edit == null:
		return
	var digits := ""
	for ch in _lot_edit.text:
		if ch >= "0" and ch <= "9":
			digits += ch
	if not digits.is_empty():
		lot = clampf(float(digits.to_int()), lot_min(), lot_max())
	if submit:
		_lot_edit.release_focus()
	_refresh()

func _on_edit_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_step_lot(1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_step_lot(-1)
			accept_event()

## Клик мимо поля снимает с него фокус (см. шапку)
func _input(ev: InputEvent) -> void:
	if _lot_edit == null or not _lot_edit.has_focus():
		return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and not _lot_edit.get_global_rect().has_point(mb.position):
		_lot_edit.release_focus()

## 10000 → «10 000» (пробел — разделитель тысяч)
static func fmt(n: float) -> String:
	var s: String = "%d" % int(n)
	var out := ""
	var k := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		k += 1
		if k % 3 == 0 and i > 0 and s[i - 1] != "-":
			out = " " + out
	return out

## Иконка, обрезанная по непрозрачному рисунку (см. шапку)
static func _trimmed(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return tex
	if img.is_compressed() and img.decompress() != OK:
		return tex
	var used: Rect2i = img.get_used_rect()
	if used.size.x <= 0 or (used.position == Vector2i.ZERO and used.size == img.get_size()):
		return tex
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(used)
	return at

func _name_of(t: int) -> String:
	for r in RES:
		if int(r["t"]) == t:
			return String(r["name"])
	return "?"

func _on_res(f: int) -> void:
	if f == Constants.FACTION_PLAYER and is_inside_tree():
		_refresh()

func _refresh() -> void:
	if _result == null:
		return
	for t in _give_btns:
		(_give_btns[t] as Button).set_pressed_no_signal(int(t) == give_t)
	for t2 in _get_btns:
		(_get_btns[t2] as Button).set_pressed_no_signal(int(t2) == get_t)
	if _lot_edit != null and not _lot_edit.has_focus():
		_lot_edit.text = fmt(lot)
	for t3 in _stock_lbls:
		(_stock_lbls[t3] as Label).text = "%d" % int(ResourceManager.get_amount(Constants.FACTION_PLAYER, int(t3)))
	if _icon != null:
		if _market_ok():
			_icon.tooltip_text = "%s  %d/%d HP" % [String((market as Building).display_name),
				int((market as Building).current_health), int((market as Building).max_health)]
		else:
			_icon.tooltip_text = "Рынок"
	var got: float = _MarketS.quote(give_t, get_t, lot)
	_result.text = "%s %s  →  %s %s" % [fmt(lot), _name_of(give_t), fmt(got), _name_of(get_t)]
	var one: float = _MarketS.quote(give_t, get_t, 100.0)
	_rate.text = "Курс: 100 %s = %d %s · пошлина %d%%" % [_name_of(give_t), int(one), _name_of(get_t),
		int(round(float(_UCfg.MARKET["fee"]) * 100.0))]
	var have: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, give_t)
	if have < lot:
		_result.add_theme_color_override("font_color", SHORT_COL)
		_result.tooltip_text = "Не хватает: есть %s" % fmt(have)
	else:
		_result.remove_theme_color_override("font_color")
		_result.tooltip_text = ""
	_go.disabled = have < lot or got <= 0.0 or not _market_ok()

func _market_ok() -> bool:
	return market != null and is_instance_valid(market) and not (market as Building).is_dead()

## Обмен текущей связкой (публичный — его зовут кнопка и стенды)
func do_trade() -> bool:
	if not _market_ok():
		return false
	var ok: bool = bool(market.call("trade", Constants.FACTION_PLAYER, give_t, get_t, lot))
	AudioManager.play_ui("order_unit" if ok else "menu_tab")
	_refresh()
	return ok
