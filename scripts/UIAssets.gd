extends RefCounted
## Ассеты интерфейса из assets/environment/menu ui.
## Файл намеренно без class_name — подключать через preload.
##
## BigBar_Base.png / SmallBar_Base.png — ленты 320x64 из пяти слотов по 64 px:
##   слот 0 — ЛЕВАЯ шапка, слот 2 — СРЕДНЯЯ (тянущаяся) часть,
##   слот 4 — ПРАВАЯ шапка, слоты 1 и 3 пустые.
## Напрямую такую ленту использовать нельзя (пустоты растянулись бы дырами),
## поэтому три куска склеиваются в одну плотную текстуру, пригодную для
## NinePatchRect: боковины фиксированы, центр тянется.
##
## BigBar_Fill.png / SmallBar_Fill.png — сплошные полосы заливки 64x64
## (значимая часть по вертикали вырезается по альфе).

## РЕГИСТР ЗДЕСЬ КРИТИЧЕН. На диске папка называется «menu ui» строчными; было
## написано «menu UI». В редакторе на Windows это сходило с рук — файловая
## система регистр не различает, — но виртуальная файловая система внутри .pck
## регистрозависима НА ЛЮБОЙ ОС. В собранном .exe ResourceLoader.exists() по
## такому пути отвечал false, запасная ветка через globalize_path в пакете тоже
## не работает, и _load_image возвращал null: пропадали курсоры игры и полосы
## здоровья HUD. Ошибка не проявлялась вообще никак до самой сборки
const DIR := "res://assets/environment/menu ui"

# Кэш готовых текстур: склейка делается один раз за запуск
static var _cache: Dictionary = {}

# Ширина боковых шапок склеенной текстуры (для patch_margin у NinePatchRect)
static var _caps: Dictionary = {}

static func big_bar_base() -> Texture2D:
	return _composed_base("BigBar_Base")

static func small_bar_base() -> Texture2D:
	return _composed_base("SmallBar_Base")

static func big_bar_fill() -> Texture2D:
	return _trimmed_fill("BigBar_Fill")

static func small_bar_fill() -> Texture2D:
	return _trimmed_fill("SmallBar_Fill")

## Ширина левой/правой шапки склеенной основы — для patch_margin_left/right
static func cap_width(key: String) -> int:
	if not _caps.has(key):
		_composed_base(key)
	return int(_caps.get(key, 8))

## Курсор игры (Cursor_01 — обычная стрелка)
static func cursor(index: int = 1) -> Texture2D:
	var key := "Cursor_%02d" % index
	if _cache.has(key):
		return _cache[key]
	var img := _load_image(key)
	if img == null:
		return null
	var rect := img.get_used_rect()
	if rect.size.x > 0 and rect.size.y > 0:
		img = img.get_region(rect)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	_hotspots[key] = _tip_of(img)
	return tex

# ── ОСТРИЁ КУРСОРА ───────────────────────────────────────────────────────────
# Input.set_custom_mouse_cursor принимает hotspot — ТОЧКУ КАРТИНКИ, которая
# совпадает с фактическим положением мыши. Раньше передавался Vector2.ZERO,
# то есть левый верхний угол КАДРА. Даже после обрезки по альфе это не остриё:
# у Cursor_01 верхняя строка рисунка начинается не от левого края кадра, и клик
# уходил на несколько пикселей мимо той точки, куда игрок целится, — по краю
# юнита или мелкого куска руды промах был стабильным.
# Берём настоящий кончик стрелки: самый левый непрозрачный пиксель в САМОЙ
# ВЕРХНЕЙ непрозрачной строке.
static var _hotspots: Dictionary = {}

## Остриё курсора в пикселях его текстуры. Считается вместе с загрузкой
static func cursor_hotspot(index: int = 1) -> Vector2:
	var key := "Cursor_%02d" % index
	if not _hotspots.has(key):
		cursor(index)
	return _hotspots.get(key, Vector2.ZERO)

static func _tip_of(img: Image) -> Vector2:
	if img == null:
		return Vector2.ZERO
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.02:
				return Vector2(float(x), float(y))
	return Vector2.ZERO

# ─────────────────────────────────────────────────────────────────────────────

## Склеить левую шапку + середину + правую шапку в одну плотную текстуру
static func _composed_base(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var img := _load_image(key)
	if img == null:
		return null

	var left  := _slot_region(img, 0)
	var mid   := _slot_region(img, 2)
	var right := _slot_region(img, 4)
	if left == null or mid == null or right == null:
		# Нестандартная раскладка — отдаём картинку как есть
		var raw := ImageTexture.create_from_image(img)
		_cache[key] = raw
		_caps[key]  = 8
		return raw

	var h: int = maxi(maxi(left.get_height(), mid.get_height()), right.get_height())
	var w: int = left.get_width() + mid.get_width() + right.get_width()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	_blit(out, left,  0)
	_blit(out, mid,   left.get_width())
	_blit(out, right, left.get_width() + mid.get_width())

	var tex := ImageTexture.create_from_image(out)
	_cache[key] = tex
	_caps[key]  = left.get_width()
	return tex

## Заливка: обрезаем прозрачные поля, остаётся сплошная полоса
static func _trimmed_fill(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var img := _load_image(key)
	if img == null:
		return null
	var rect := img.get_used_rect()
	if rect.size.x > 0 and rect.size.y > 0:
		img = img.get_region(rect)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Непрозрачный кусок внутри слота шириной 64 px (слот index)
static func _slot_region(img: Image, index: int) -> Image:
	var x0: int = index * 64
	if x0 + 64 > img.get_width():
		return null
	var slot := img.get_region(Rect2i(x0, 0, 64, img.get_height()))
	var used := slot.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	return slot.get_region(used)

static func _blit(dst: Image, src: Image, x: int) -> void:
	dst.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(x, 0))

static func _load_image(key: String) -> Image:
	var path := "%s/%s.png" % [DIR, key]
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			var img := tex.get_image()
			if img != null:
				if img.is_compressed():
					if img.decompress() != OK:
						return null
				img.convert(Image.FORMAT_RGBA8)
				return img
	# Запасной путь: PNG без метаданных импорта
	var img2 := Image.new()
	if img2.load(ProjectSettings.globalize_path(path)) == OK:
		img2.convert(Image.FORMAT_RGBA8)
		return img2
	return null

## Материал для полоски здоровья в 3D: билборд, без освещения, поверх спрайтов
static func bar_material(tex: Texture2D, tint: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture          = tex
	m.albedo_color            = tint
	m.shading_mode            = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode          = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode               = BaseMaterial3D.CULL_DISABLED
	m.transparency            = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test           = true      # полоска не тонет в спрайте юнита
	m.render_priority         = priority + 3
	m.texture_filter          = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m
