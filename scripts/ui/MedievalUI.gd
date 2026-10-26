extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## СРЕДНЕВЕКОВОЕ ОФОРМЛЕНИЕ МЕНЮ (ТЗ 21.10.2026, редизайн меню)
## ═══════════════════════════════════════════════════════════════════════════
## Одна тема на главное меню, окно настроек, паузу, сохранение и экран
## загрузки: дерево с бронзовой окантовкой у кнопок, кованая рама у окон,
## вкладки-«ярлыки», ползунки с бронзовым ползуном, чекбоксы в железной оправе.
##
## ВСЁ РИСУЕТСЯ КОДОМ ОДИН РАЗ ЗА ЗАПУСК (кэш _tex): своих картинок рамок в
## assets нет, а качать арт со стороны — вопрос прав. Текстуры маленькие
## (64-96 px) и тянутся как девять кусков (StyleBoxTexture): боковины
## фиксированы, середина ТАЙЛИТСЯ, поэтому волокно дерева не размазывается
## на широкой кнопке.
##
## СЛУЧАЙНОСТИ ЗДЕСЬ НЕТ ВОВСЕ — фактуры из синусов: меню и экран загрузки
## работают, пока Main сеет партию, и общий randf() сдвинул бы все жребии
## карты (правило CLAUDE.md о сеяных лотереях).
##
## Файл без class_name — подключать через preload.

## ── ПАЛИТРА ──────────────────────────────────────────────────────────────────
const INK        := Color(0.10, 0.06, 0.04)
const WOOD       := Color(0.34, 0.22, 0.12)
const WOOD_DARK  := Color(0.17, 0.11, 0.07)
const BRONZE     := Color(0.78, 0.60, 0.30)
const BRONZE_HI  := Color(1.00, 0.86, 0.50)
const IRON       := Color(0.30, 0.31, 0.34)
const TEXT       := Color(0.96, 0.90, 0.74)
const TEXT_DIM   := Color(0.74, 0.68, 0.56)
const TEXT_HINT  := Color(0.64, 0.60, 0.52)
const GOLD_TITLE := Color(1.00, 0.84, 0.40)

## Оттенки кнопок: дерево, мох (продолжить/старт), сталь (сохранить/загрузить),
## кровь (выход). Цвет — ТОЛЬКО подсказка о роде действия; фактура общая
const KINDS := {
	"wood":  Color(0.36, 0.23, 0.12),
	"green": Color(0.24, 0.33, 0.13),
	"steel": Color(0.21, 0.26, 0.33),
	"red":   Color(0.42, 0.13, 0.10),
}

static var _tex: Dictionary = {}
static var _theme: Theme = null
static var _serif: Font = null

# ═════════════════════════════════════════════════════════════════════════════
# ШРИФТ ЗАГОЛОВКОВ
# ═════════════════════════════════════════════════════════════════════════════
## Засечки ОС (Georgia / Times / Liberation Serif) — у всех кириллица. Нет ни
## одного — SystemFont сам отдаёт запасной, и надпись остаётся читаемой
static func serif() -> Font:
	if _serif == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Georgia", "Constantia", "Cambria",
			"Times New Roman", "Liberation Serif", "DejaVu Serif", "serif"])
		f.font_weight = 700
		_serif = f
	return _serif

# ═════════════════════════════════════════════════════════════════════════════
# ПРОЦЕДУРНЫЕ ФАКТУРЫ
# ═════════════════════════════════════════════════════════════════════════════
## Волокно дерева: продольные полосы с волной, тайлится по X без шва
static func _wood_px(x: int, y: int, w: int, base: Color, phase: int) -> Color:
	# Волокно — продольные полосы с пологим изгибом (без «ряби»), плюс мелкий
	# зернистый шум из хэша — доска, а не вода
	var fx: float = float(x) / float(w) * TAU
	var g: float = sin(float(y) * 0.55 + sin(fx + float(phase)) * 0.45)
	var g2: float = sin(float(y) * 1.9 + float(phase) * 2.0 + sin(fx * 2.0) * 0.3)
	var hsh: int = ((x * 73856093) ^ (y * 19349663) ^ (phase * 83492791)) & 0xFFFF
	var n: float = float(hsh % 1000) / 1000.0 - 0.5
	var k: float = 0.90 + g * 0.05 + g2 * 0.025 + n * 0.05
	return Color(base.r * k, base.g * k, base.b * k, 1.0)

static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)

## Заклёпка 3x3 с бликом
static func _rivet(img: Image, cx: int, cy: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_put(img, cx + dx, cy + dy, BRONZE.darkened(0.25))
	_put(img, cx - 1, cy - 1, BRONZE_HI)
	_put(img, cx, cy, BRONZE)

## КНОПКА: тёмный контур, бронзовая фаска, дерево внутри с бликом сверху и
## тенью снизу. state: 0 обычная, 1 наведение (фаска ярче, дерево светлее),
## 2 нажата (фаска тусклая, свет снизу — «вдавлена»), 3 погашена
static func button_texture(kind: String, state: int) -> Texture2D:
	var key := "btn_%s_%d" % [kind, state]
	if _tex.has(key):
		return _tex[key]
	var W := 64
	var H := 40
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var base: Color = KINDS.get(kind, KINDS["wood"])
	var rim: Color = BRONZE
	if state == 1:
		base = base.lightened(0.16)
		rim = BRONZE_HI
	elif state == 2:
		base = base.darkened(0.22)
		rim = BRONZE.darkened(0.30)
	elif state == 3:
		base = base.darkened(0.45).lerp(Color(0.2, 0.2, 0.2), 0.5)
		rim = IRON
	for y in range(H):
		for x in range(W):
			var c: Color = _wood_px(x, y, W, base, 3)
			# свет сверху, тень снизу (у нажатой — наоборот)
			var t: float = float(y) / float(H - 1)
			var shade: float = lerpf(0.14, -0.18, t) if state != 2 else lerpf(-0.16, 0.06, t)
			c = c.lightened(shade) if shade > 0.0 else c.darkened(-shade)
			img.set_pixel(x, y, c)
	# фаска 2 px и контур 1 px
	for x in range(W):
		img.set_pixel(x, 0, INK)
		img.set_pixel(x, H - 1, INK)
		img.set_pixel(x, 1, rim.lightened(0.15 if state != 2 else 0.0))
		img.set_pixel(x, 2, rim.darkened(0.10))
		img.set_pixel(x, H - 2, rim.darkened(0.35))
		img.set_pixel(x, H - 3, rim.darkened(0.15))
	for y in range(1, H - 1):
		img.set_pixel(0, y, INK)
		img.set_pixel(W - 1, y, INK)
		img.set_pixel(1, y, rim.lightened(0.05))
		img.set_pixel(2, y, rim.darkened(0.15))
		img.set_pixel(W - 2, y, rim.darkened(0.35))
		img.set_pixel(W - 3, y, rim.darkened(0.15))
	# скруглённые углы — срезаем пиксель
	for p in [Vector2i(0, 0), Vector2i(W - 1, 0), Vector2i(0, H - 1), Vector2i(W - 1, H - 1)]:
		img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
	if state != 3:
		_rivet(img, 5, 5)
		_rivet(img, W - 6, 5)
		_rivet(img, 5, H - 6)
		_rivet(img, W - 6, H - 6)
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex

## РАМА ОКНА: кованая железная полоса с бронзовой нитью и заклёпками,
## внутри тёмное дерево. Края 22 px — неподвижные куски девятки
static func frame_texture() -> Texture2D:
	if _tex.has("frame"):
		return _tex["frame"]
	var S := 96
	var B := 14
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in range(S):
		for x in range(S):
			var edge: int = mini(mini(x, y), mini(S - 1 - x, S - 1 - y))
			var c: Color
			if edge == 0:
				c = INK
			elif edge < B - 3:
				# железо: рябь ковки + свет к верхнему левому краю
				var n: float = sin(float(x * 7 + y * 13)) * 0.04 + sin(float(x * 3 - y * 5) * 0.7) * 0.03
				c = IRON.lightened(clampf(0.10 - float(edge) * 0.01 + n, 0.0, 1.0))
				if (y < S - 1 - x and edge == y) or (x < S - 1 - y and edge == x):
					c = c.lightened(0.06)
				else:
					c = c.darkened(0.12)
			elif edge == B - 3:
				c = BRONZE_HI
			elif edge == B - 2:
				c = BRONZE.darkened(0.2)
			elif edge == B - 1:
				c = INK
			else:
				c = _wood_px(x, y, S, WOOD_DARK, 7)
				# мягкая внутренняя тень у кромки
				var d: float = clampf(float(edge - B) / 8.0, 0.0, 1.0)
				c = c.darkened(0.35 * (1.0 - d))
			img.set_pixel(x, y, c)
	# угловые бронзовые накладки
	for p in [Vector2i(6, 6), Vector2i(S - 7, 6), Vector2i(6, S - 7), Vector2i(S - 7, S - 7)]:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if absi(dx) + absi(dy) <= 3:
					_put(img, p.x + dx, p.y + dy, BRONZE.darkened(0.3))
		_put(img, p.x - 1, p.y - 1, BRONZE_HI)
		_put(img, p.x, p.y, BRONZE)
	var tex := ImageTexture.create_from_image(img)
	_tex["frame"] = tex
	return tex

## ЯРЛЫК ВКЛАДКИ: дерево с бронзовой кромкой сверху и с боков, снизу открыт.
## state: 0 выбрана, 1 не выбрана, 2 наведение
static func tab_texture(state: int) -> Texture2D:
	var key := "tab_%d" % state
	if _tex.has(key):
		return _tex[key]
	var W := 48
	var H := 34
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var base: Color = WOOD.lightened(0.10)
	var rim: Color = BRONZE_HI
	if state == 1:
		base = WOOD_DARK
		rim = IRON
	elif state == 2:
		base = WOOD
		rim = BRONZE
	for y in range(H):
		for x in range(W):
			var c: Color = _wood_px(x, y, W, base, 11)
			c = c.lightened(0.10 * (1.0 - float(y) / float(H)))
			if y == 0 or x == 0 or x == W - 1:
				c = INK
			elif y == 1 or x == 1 or x == W - 2:
				c = rim
			elif y == 2 or x == 2 or x == W - 3:
				c = rim.darkened(0.3)
			img.set_pixel(x, y, c)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	img.set_pixel(W - 1, 0, Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex

## Чекбокс 22x22: железная оправа; включён — бронзовая «галочка»
static func check_icon(on: bool, hover: bool = false) -> Texture2D:
	var key := "chk_%s_%s" % [str(on), str(hover)]
	if _tex.has(key):
		return _tex[key]
	var S := 22
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(1, S - 1):
		for x in range(1, S - 1):
			var edge: int = mini(mini(x - 1, y - 1), mini(S - 2 - x, S - 2 - y))
			var c: Color = INK
			if edge >= 1 and edge <= 2:
				c = (BRONZE if hover else IRON.lightened(0.2)).lightened(0.15 if edge == 1 else 0.0)
			elif edge > 2:
				c = WOOD_DARK.darkened(0.35)
			img.set_pixel(x, y, c)
	if on:
		var pts: Array = []
		for i in range(5):
			pts.append(Vector2i(5 + i, 10 + i))
		for i in range(9):
			pts.append(Vector2i(9 + i, 14 - i))
		for p in pts:
			var q: Vector2i = p
			_put(img, q.x, q.y - 1, BRONZE.darkened(0.1))
			_put(img, q.x, q.y, BRONZE_HI)
			_put(img, q.x, q.y + 1, BRONZE)
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex

## Ползун ползунка: бронзовый ромб-щиток 18x24
static func grabber_icon(hover: bool) -> Texture2D:
	var key := "grab_%s" % str(hover)
	if _tex.has(key):
		return _tex[key]
	var W := 18
	var H := 24
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: float = float(W - 1) * 0.5
	var cy: float = float(H - 1) * 0.5
	for y in range(H):
		for x in range(W):
			var d: float = absf(float(x) - cx) / (W * 0.5) + absf(float(y) - cy) / (H * 0.5)
			if d < 0.86:
				var c: Color = BRONZE_HI if hover else BRONZE
				var lt: float = 0.25 * (1.0 - float(y) / H) - 0.1
				c = c.lightened(lt) if lt > 0.0 else c.darkened(-lt)
				if d > 0.68:
					c = c.darkened(0.35)
				img.set_pixel(x, y, c)
			elif d < 1.0:
				img.set_pixel(x, y, INK)
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex

## Стрелка выпадающего списка
static func arrow_icon() -> Texture2D:
	if _tex.has("arrow"):
		return _tex["arrow"]
	var img := Image.create(14, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(7):
		for x in range(y, 13 - y):
			img.set_pixel(x, y + 1, BRONZE_HI if y < 2 else BRONZE)
	var tex := ImageTexture.create_from_image(img)
	_tex["arrow"] = tex
	return tex

# ═════════════════════════════════════════════════════════════════════════════
# СТИЛИ
# ═════════════════════════════════════════════════════════════════════════════
static func _box(tex: Texture2D, m: int, cl: float, ct: float, cr: float, cb: float) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = m
	s.texture_margin_top = m
	s.texture_margin_right = m
	s.texture_margin_bottom = m
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.content_margin_left = cl
	s.content_margin_top = ct
	s.content_margin_right = cr
	s.content_margin_bottom = cb
	return s

static func button_style(kind: String, state: int) -> StyleBoxTexture:
	# нажатая — содержимое ниже на 2 px: «кнопку вдавили»
	var dy: float = 2.0 if state == 2 else 0.0
	return _box(button_texture(kind, state), 9, 16.0, 6.0 + dy, 16.0, 6.0 - dy)

## Рама окна; pad — внутренний отступ содержимого
static func frame_style(pad: float = 28.0) -> StyleBoxTexture:
	var s := _box(frame_texture(), 22, pad, pad, pad, pad)
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return s

## Утопленная плашка внутри окна (под строки настроек, слоты сохранений)
static func inset_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.05, 0.04, 0.72)
	s.border_color = Color(0.45, 0.34, 0.18, 0.9)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

## Оформить одну кнопку целиком (стили, шрифт, звук нажатия). Нужна там, где
## кнопка живёт вне корня с темой или ей нужен свой оттенок
static func style_button(b: Button, kind: String = "wood", font_size: int = 17) -> void:
	b.add_theme_stylebox_override("normal", button_style(kind, 0))
	b.add_theme_stylebox_override("hover", button_style(kind, 1))
	b.add_theme_stylebox_override("pressed", button_style(kind, 2))
	b.add_theme_stylebox_override("hover_pressed", button_style(kind, 2))
	b.add_theme_stylebox_override("disabled", button_style(kind, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", serif())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.78))
	b.add_theme_color_override("font_pressed_color", BRONZE_HI)
	b.add_theme_color_override("font_hover_pressed_color", BRONZE_HI)
	b.add_theme_color_override("font_disabled_color", Color(0.52, 0.50, 0.46))
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 3)
	wire_sound(b)

## ЗВУКОВОЙ ОТКЛИК НАЖАТИЯ — один на все меню. Метка не даёт подключить дважды
static func wire_sound(b: BaseButton, event: String = "menu_button") -> void:
	if b.has_meta("mui_snd"):
		return
	b.set_meta("mui_snd", true)
	b.pressed.connect(func():
		AudioManager.play_ui(event))

## Заголовок окна: засечки, золото, обводка
static func title_label(text: String, size: int = 30) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", serif())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD_TITLE)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l

## Подпись-подсказка мелким кеглем
static func hint_label(text: String, size: int = 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT_HINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## Узорная перемычка под заголовком: линия с ромбом посередине
static func divider(width: float = 280.0) -> Control:
	var c := _Divider.new()
	c.custom_minimum_size = Vector2(width, 12)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

class _Divider extends Control:
	func _draw() -> void:
		var y: float = size.y * 0.5
		var cx: float = size.x * 0.5
		var col := Color(0.78, 0.60, 0.30, 0.85)
		draw_line(Vector2(0, y), Vector2(cx - 12, y), col, 1.5, true)
		draw_line(Vector2(cx + 12, y), Vector2(size.x, y), col, 1.5, true)
		draw_colored_polygon(PackedVector2Array([Vector2(cx, y - 5), Vector2(cx + 7, y),
			Vector2(cx, y + 5), Vector2(cx - 7, y)]), Color(1.0, 0.86, 0.5))
		draw_circle(Vector2(cx - 16, y), 2.0, col)
		draw_circle(Vector2(cx + 16, y), 2.0, col)

# ═════════════════════════════════════════════════════════════════════════════
# ТЕМА — ставится КОРНЮ окна; дети наследуют
# ═════════════════════════════════════════════════════════════════════════════
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 16
	# ── Кнопки и выпадающие списки
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, button_style("wood", 0))
		t.set_stylebox("hover", cls, button_style("wood", 1))
		t.set_stylebox("pressed", cls, button_style("wood", 2))
		t.set_stylebox("hover_pressed", cls, button_style("wood", 2))
		t.set_stylebox("disabled", cls, button_style("wood", 3))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color(1.0, 0.95, 0.78))
		t.set_color("font_pressed_color", cls, BRONZE_HI)
		t.set_color("font_hover_pressed_color", cls, BRONZE_HI)
		t.set_color("font_focus_color", cls, TEXT)
		t.set_color("font_disabled_color", cls, Color(0.58, 0.55, 0.50))
	t.set_icon("arrow", "OptionButton", arrow_icon())
	t.set_constant("arrow_margin", "OptionButton", 12)
	# ── Список выпадающего меню
	var pop := StyleBoxFlat.new()
	pop.bg_color = Color(0.12, 0.08, 0.05, 0.98)
	pop.border_color = BRONZE
	pop.set_border_width_all(2)
	pop.set_corner_radius_all(3)
	pop.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", pop)
	var pop_h := StyleBoxFlat.new()
	pop_h.bg_color = Color(0.45, 0.30, 0.14, 0.95)
	pop_h.set_corner_radius_all(2)
	t.set_stylebox("hover", "PopupMenu", pop_h)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1.0, 0.95, 0.80))
	t.set_color("font_disabled_color", "PopupMenu", TEXT_HINT)
	t.set_font_size("font_size", "PopupMenu", 15)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_icon("radio_checked", "PopupMenu", check_icon(true))
	t.set_icon("radio_unchecked", "PopupMenu", check_icon(false))
	# ── Чекбокс
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2
	empty.content_margin_top = 2
	empty.content_margin_bottom = 2
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(st, "CheckBox", empty)
	t.set_icon("checked", "CheckBox", check_icon(true))
	t.set_icon("unchecked", "CheckBox", check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", check_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", check_icon(false))
	t.set_constant("h_separation", "CheckBox", 10)
	for fc in ["font_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(fc, "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color(1.0, 0.95, 0.78))
	t.set_color("font_hover_pressed_color", "CheckBox", Color(1.0, 0.95, 0.78))
	# ── Ползунок
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.06, 0.04, 0.03)
	groove.border_color = Color(0.40, 0.30, 0.16)
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(3)
	groove.content_margin_top = 4
	groove.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.72, 0.52, 0.22)
	fill.border_color = Color(0.95, 0.78, 0.42)
	fill.border_width_top = 1
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", grabber_icon(false))
	t.set_icon("grabber_highlight", "HSlider", grabber_icon(true))
	t.set_icon("grabber_disabled", "HSlider", grabber_icon(false))
	# ── Вкладки
	var ts := _box(tab_texture(0), 6, 22.0, 8.0, 22.0, 8.0)
	var tu := _box(tab_texture(1), 6, 22.0, 8.0, 22.0, 8.0)
	var th := _box(tab_texture(2), 6, 22.0, 8.0, 22.0, 8.0)
	for cls2 in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", cls2, ts)
		t.set_stylebox("tab_unselected", cls2, tu)
		t.set_stylebox("tab_hovered", cls2, th)
		t.set_stylebox("tab_focus", cls2, StyleBoxEmpty.new())
		t.set_color("font_selected_color", cls2, GOLD_TITLE)
		t.set_color("font_unselected_color", cls2, TEXT_DIM)
		t.set_color("font_hovered_color", cls2, TEXT)
		t.set_color("font_outline_color", cls2, INK)
		t.set_constant("outline_size", cls2, 3)
		t.set_font("font", cls2, serif())
		t.set_font_size("font_size", cls2, 17)
	var tab_panel := inset_style()
	tab_panel.content_margin_left = 28
	tab_panel.content_margin_right = 28
	tab_panel.content_margin_top = 22
	tab_panel.content_margin_bottom = 22
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_constant("side_margin", "TabContainer", 0)
	# ── Подписи, панели, подсказки
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", frame_style())
	t.set_stylebox("panel", "TooltipPanel", pop)
	t.set_color("font_color", "TooltipLabel", TEXT)
	_theme = t
	return _theme
