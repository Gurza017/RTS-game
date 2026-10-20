extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## КУРСОРЫ КОНТЕКСТНОГО ДЕЙСТВИЯ (ТЗ 14.10.2026, п. 4)
## ═══════════════════════════════════════════════════════════════════════════
## Рисуются кодом, как и скрещённые мечи режима [A]
## (SelectionManager._make_swords_cursor): ассетов под них в паке нет, а
## пиксельный курсор 32×32 с тёмной обводкой читается на любой подложке.
##   DOOR   — арочная открытая дверь: ПКМ посадит выделенных в это здание;
##   FORBID — запрет: своё укрепление, но выделенных не примет (полно/не тот род);
##   SWORD  — острие меча вниз: ПКМ — атака этой цели;
##   HAMMER — молоток: ПКМ рабочими — ремонт или стройка.
## Каждая картинка строится один раз и кэшируется. Горячая точка — там, куда
## «смотрит» рисунок: кончик меча, низ дверного проёма, центр знака и боёк.

enum { NONE = 0, HAND = 1, DOOR = 2, FORBID = 3, SWORD = 4, HAMMER = 5 }

const SZ := 32
const OUTLINE := Color(0.07, 0.07, 0.09, 1.0)

static var _cache: Dictionary = {}

static func texture(kind: int) -> ImageTexture:
	if _cache.has(kind):
		return _cache[kind]
	var img: Image = null
	match kind:
		DOOR: img = _door()
		FORBID: img = _forbid()
		SWORD: img = _sword()
		HAMMER: img = _hammer()
	if img == null:
		return null
	_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[kind] = tex
	return tex

static func hotspot(kind: int) -> Vector2:
	match kind:
		DOOR: return Vector2(16, 28)
		FORBID: return Vector2(16, 16)
		SWORD: return Vector2(16, 30)
		HAMMER: return Vector2(9, 8)
	return Vector2.ZERO

static func _blank() -> Image:
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < SZ and y < SZ:
		img.set_pixel(x, y, c)

static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_put(img, x, y, c)

## Тёмная обводка в один пиксель вокруг всего непрозрачного
static func _outline(img: Image) -> void:
	var src := img.duplicate() as Image
	for y in range(SZ):
		for x in range(SZ):
			if src.get_pixel(x, y).a > 0.5:
				continue
			var near := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < SZ and ny < SZ and src.get_pixel(nx, ny).a > 0.5:
					near = true
					break
			if near:
				img.set_pixel(x, y, OUTLINE)

## Арка из камня, внутри — открытая створка (тёмный проём + светлая дверь,
## отведённая вбок)
static func _door() -> Image:
	var img := _blank()
	var stone := Color(0.78, 0.76, 0.70)
	var stone_dk := Color(0.55, 0.53, 0.49)
	var hole := Color(0.16, 0.12, 0.10)
	var wood := Color(0.72, 0.48, 0.24)
	var wood_dk := Color(0.50, 0.32, 0.15)
	var cx := 16.0
	var r_out := 11.0
	var r_in := 7.5
	var top := 13      # где кончается полукруг арки и начинаются прямые косяки
	for y in range(2, 30):
		for x in range(3, 30):
			var fx: float = float(x) + 0.5
			var fy: float = float(y) + 0.5
			var inside_out: bool
			var inside_in: bool
			if y < top:
				var d: float = Vector2(fx - cx, fy - float(top)).length()
				inside_out = d <= r_out
				inside_in = d <= r_in
			else:
				inside_out = absf(fx - cx) <= r_out
				inside_in = absf(fx - cx) <= r_in
			if not inside_out:
				continue
			if inside_in:
				_put(img, x, y, hole)
			else:
				_put(img, x, y, stone if (x + y / 3) % 5 != 0 else stone_dk)
	# Порог
	_rect(img, 4, 28, 28, 29, stone_dk)
	# Открытая створка — трапеция у правого косяка, «повёрнутая к зрителю»
	for y in range(9, 28):
		var w: int = 4 if y > 11 else 2
		for x in range(23 - w, 24):
			_put(img, x, y, wood if (y % 4) != 0 else wood_dk)
	_put(img, 20, 19, Color(0.95, 0.82, 0.30))   # кольцо-ручка
	# Тёплый свет из проёма — пол
	_rect(img, 10, 25, 18, 27, Color(0.98, 0.83, 0.42))
	return img

## Красный круг с косой чертой
static func _forbid() -> Image:
	var img := _blank()
	var red := Color(0.86, 0.14, 0.12)
	var c := Vector2(16, 16)
	for y in range(SZ):
		for x in range(SZ):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d: float = (p - c).length()
			if d <= 13.0 and d >= 9.5:
				_put(img, x, y, red)
			# Черта из верхнего левого в нижний правый
			var along: float = absf((p.x - c.x) - (p.y - c.y)) / sqrt(2.0)
			if d < 10.0 and along <= 1.8:
				_put(img, x, y, red)
	return img

## Меч остриём вниз: рукоять сверху, гарда, клинок до нижней кромки
static func _sword() -> Image:
	var img := _blank()
	var blade := Color(0.88, 0.90, 0.95)
	var blade_dk := Color(0.62, 0.66, 0.74)
	var gold := Color(0.93, 0.76, 0.24)
	var grip := Color(0.45, 0.28, 0.14)
	_rect(img, 15, 1, 17, 3, gold)        # навершие
	_rect(img, 15, 4, 16, 8, grip)        # рукоять
	_rect(img, 10, 9, 21, 10, gold)       # гарда
	for y in range(11, 27):
		_put(img, 15, y, blade)
		_put(img, 16, y, blade_dk)
		_put(img, 14, y, blade)
		_put(img, 17, y, blade_dk)
	# Остриё сходится в точку
	_rect(img, 15, 27, 16, 28, blade)
	_put(img, 16, 29, blade)
	_put(img, 16, 30, blade_dk)
	return img

## Молоток: боёк наискось сверху слева, рукоять вниз вправо. Рисуется по
## ПОВЁРНУТЫМ ПРЯМОУГОЛЬНИКАМ (координаты вдоль/поперёк рукояти), а не
## диагональными штрихами: штрихи давали «решётку» на бойке
static func _hammer() -> Image:
	var img := _blank()
	var iron := Color(0.72, 0.74, 0.80)
	var iron_dk := Color(0.46, 0.48, 0.54)
	var wood := Color(0.72, 0.47, 0.22)
	var wood_dk := Color(0.52, 0.32, 0.14)
	var c := Vector2(10.5, 10.5)          # центр бойка
	var ax := Vector2(1, 1).normalized()  # вдоль рукояти
	var px := Vector2(-1, 1).normalized() # поперёк
	for y in range(SZ):
		for x in range(SZ):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - c
			var u: float = d.dot(ax)
			var v: float = d.dot(px)
			# Рукоять: от бойка вниз-вправо
			if u > 2.0 and u < 26.0 and absf(v) <= 1.4:
				_put(img, x, y, wood if v < 0.3 else wood_dk)
			# Боёк: поперёк рукояти
			if absf(u) <= 3.2 and absf(v) <= 8.0:
				_put(img, x, y, iron if u < 1.0 else iron_dk)
	return img
