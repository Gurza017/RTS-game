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

## ── ТЗ 20.10.2026, блок 6 ──────────────────────────────────────────────────
##   AXE     — рабочий над деревом;
##   PICKAXE — рабочий над камнем и золотом;
##   KNIFE   — рабочий над мясом (загон, овца, туша);
##   FINGER  — пехота/рабочие над своим замком или зданием (ПКМ — «сюда»);
##   SWORD   — теперь НАКЛОНЁН на 45°: рукоять вверху справа, остриё внизу
##             слева — горячая точка на острие;
##   DOOR    — только лучникам над укреплением, которое их примет
## ── ТЗ 22.10.2026, блок 5 ──────────────────────────────────────────────────
##   MEDIC — монах над своим раненым отрядом: крест медицины со змеёй (ПКМ —
##           лечить); меч и топор — шире и жирнее штрихом, под габарит
##           основной стрелки и перчатки (22-27 px по ширине)
## ── ТЗ 24.10.2026, второе письмо, блок 1 ───────────────────────────────────
##   ARROW — стрела по той же диагонали, что меч: выделены ТОЛЬКО стрелки
##           (лучники, башня/укрепление с гарнизоном) и под курсором враг
## ── ТЗ 27.10.2026, UI/UX (курсоры) ─────────────────────────────────────────
##   МЕЧ И СТРЕЛА СМОТРЯТ НА «10 ЧАСОВ»: остриё/наконечник в ВЕРХНЕМ ЛЕВОМ
##   углу, рукоять/оперение уходят вниз-вправо (прежде — остриё внизу слева,
##   рукоять вверху справа). Горячая точка — на острие (TIP).
##   ARROW     — оперение ЗЕЛЁНОЕ: выделенные стрелки/башни достают до цели;
##   ARROW_FAR — оперение КРАСНОЕ: цель под курсором дальше их дальности
##               (SelectionManager.selection_reaches, опрос Main.CURSOR_POLL)
## ── ТЗ 29.10.2026, п. 2 ───────────────────────────────────────────────────
##   ARROW_FAR — ещё и маленький КРАСНЫЙ КРЕСТИК на острие («не достанут»).
##   ARROWS_X / ARROWS_X_FAR — две скрещённые стрелы: курсор режима [A] у
##   одних стрелков (у пехоты и смешанного выделения — скрещённые мечи);
##   оперение по той же досягаемости, крестик — в перекрестии
enum { NONE = 0, HAND = 1, DOOR = 2, FORBID = 3, SWORD = 4, HAMMER = 5,
	AXE = 6, PICKAXE = 7, KNIFE = 8, FINGER = 9, MEDIC = 10, ARROW = 11,
	ARROW_FAR = 12, ARROWS_X = 13, ARROWS_X_FAR = 14 }

## Остриё меча и наконечник стрелы (пиксели); горячая точка обоих курсоров
const TIP := Vector2(3.0, 3.5)
## Ось «от острия к рукояти»: вниз-вправо, то есть рисунок смотрит на 10 часов
const TIP_AX := Vector2(0.70710678, 0.70710678)
## Поперечная ось
const TIP_PX := Vector2(0.70710678, -0.70710678)

const SZ := 32
const OUTLINE := Color(0.07, 0.07, 0.09, 1.0)

static var _cache: Dictionary = {}

static func texture(kind: int) -> ImageTexture:
	if _cache.has(kind):
		return _cache[kind]
	# ПАЛЕЦ — ИСХОДНЫЙ АССЕТ, А НЕ РИСУНОК КОДОМ (ТЗ 21.10.2026): владелец
	# просил вернуть перчатку-указатель из набора интерфейса (Cursor_02).
	# Рисованный _finger() остался запасным — на случай, если файла нет
	if kind == FINGER:
		var orig = load("res://scripts/UIAssets.gd").cursor(2)
		if orig is ImageTexture:
			_cache[kind] = orig
			return orig
	var img: Image = null
	match kind:
		DOOR: img = _door()
		FORBID: img = _forbid()
		SWORD: img = _sword()
		ARROW: img = _arrow(true)
		ARROW_FAR: img = _arrow_far()
		ARROWS_X: img = _arrows_x(true)
		ARROWS_X_FAR: img = _arrows_x(false)
		HAMMER: img = _hammer()
		AXE: img = _axe()
		PICKAXE: img = _pickaxe()
		KNIFE: img = _knife()
		FINGER: img = _finger()
		MEDIC: img = _medic()
	if img == null:
		return null
	_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[kind] = tex
	return tex

static func hotspot(kind: int) -> Vector2:
	match kind:
		DOOR: return Vector2(16, 28)
		MEDIC: return Vector2(16, 16)
		FORBID: return Vector2(16, 16)
		SWORD: return Vector2(3, 3)
		ARROW: return Vector2(3, 3)
		ARROW_FAR: return Vector2(3, 3)
		ARROWS_X: return Vector2(16, 16)
		ARROWS_X_FAR: return Vector2(16, 16)
		HAMMER: return Vector2(9, 8)
		AXE: return Vector2(AXE_EDGE)
		PICKAXE: return Vector2(4, 9)
		KNIFE: return Vector2(4, 4)
		FINGER:
			# у исходной перчатки остриё — кончик пальца (верхний левый пиксель)
			var ui = load("res://scripts/UIAssets.gd")
			if ui.cursor(2) != null:
				return ui.cursor_hotspot(2)
			return Vector2(13, 2)
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

## Меч, наклонённый на 45° (ТЗ 20.10.2026, блок 6): рукоять вверху справа,
## клинок уходит вниз влево, остриё — горячая точка. Рисуется в осях клинка
## (u — вдоль от острия к навершию, v — поперёк), как молоток
static func _sword() -> Image:
	var img := _blank()
	var blade := Color(0.90, 0.92, 0.96)
	var blade_dk := Color(0.60, 0.64, 0.72)
	var gold := Color(0.93, 0.76, 0.24)
	var grip := Color(0.45, 0.28, 0.14)
	# ТЗ 27.10.2026: остриё в верхнем левом углу, рукоять — вниз-вправо
	var tip := TIP
	var ax := TIP_AX    # от острия к рукояти
	var px := TIP_PX    # поперёк
	for y in range(SZ):
		for x in range(SZ):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - tip
			var u: float = d.dot(ax)
			var v: float = d.dot(px)
			if u < 0.0 or u > 33.0:
				continue
			if u <= 20.5:
				# Клинок: сужается к острию в первых 5 пикселях. ШИРЕ
				# (ТЗ 22.10.2026): было 1.9 — тоньше стрелки курсора вдвое
				var half: float = 2.8 if u > 5.0 else 0.6 + u * 0.44
				if absf(v) <= half:
					_put(img, x, y, blade if v < 0.0 else blade_dk)
			elif u <= 23.5:
				if absf(v) <= 6.8:
					_put(img, x, y, gold)              # гарда
			elif u <= 29.5:
				if absf(v) <= 1.9:
					_put(img, x, y, grip)              # рукоять
			elif absf(v) <= 2.9:
				_put(img, x, y, gold)                  # навершие
	return img

## Стрела по той же диагонали, что меч: наконечник-ромб у горячей точки
## (верхний левый угол), древко вниз-вправо, оперение двумя «ёлочками» у
## нижнего правого угла. Цвет оперения — ответ «достанут ли» (ТЗ 27.10.2026):
## in_range — зелёное, иначе красное
const FLETCH_NEAR := Color(0.30, 0.86, 0.34)
const FLETCH_NEAR_DK := Color(0.14, 0.56, 0.20)
const FLETCH_FAR := Color(0.94, 0.26, 0.20)
const FLETCH_FAR_DK := Color(0.64, 0.14, 0.11)
static func _arrow(in_range: bool = true) -> Image:
	var img := _blank()
	var iron := Color(0.86, 0.88, 0.94)
	var iron_dk := Color(0.55, 0.58, 0.66)
	var shaft := Color(0.74, 0.52, 0.28)
	var shaft_dk := Color(0.52, 0.34, 0.16)
	var fl := FLETCH_NEAR if in_range else FLETCH_FAR
	var fl_dk := FLETCH_NEAR_DK if in_range else FLETCH_FAR_DK
	var tip := TIP
	var ax := TIP_AX
	var px := TIP_PX
	for y in range(SZ):
		for x in range(SZ):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - tip
			var u: float = d.dot(ax)
			var v: float = d.dot(px)
			if u < 0.0 or u > 35.0:
				continue
			if u <= 8.0:
				# Наконечник: ширится до 4 px к 6-му пикселю и сходится к древку
				var half: float = u * 0.62 if u <= 6.0 else 3.7 - (u - 6.0) * 1.2
				if absf(v) <= maxf(half, 0.6):
					_put(img, x, y, iron if v < 0.0 else iron_dk)
			elif u <= 25.0:
				if absf(v) <= 1.1:
					_put(img, x, y, shaft if v < 0.0 else shaft_dk)
			else:
				# Оперение: два пера, расходящихся назад
				var w: float = 1.1 + (u - 25.0) * 0.42
				if absf(v) <= minf(w, 4.2) and absf(v) >= 0.9:
					_put(img, x, y, fl if v < 0.0 else fl_dk)
				elif absf(v) <= 1.1:
					_put(img, x, y, shaft_dk)
	return img

## Красный крестик «не достанут»: косой крест с тёмной обводкой
## (обводка своя: общая _outline обводит только прозрачное вокруг рисунка)
const CROSS_RED := Color(0.98, 0.16, 0.12)
static func _red_cross(img: Image, c: Vector2i, arm: int = 2) -> void:
	# Штрих в два пикселя толщиной (диагональ + сосед справа), затем
	# обводка в один пиксель ровно вокруг красного
	var red: Dictionary = {}
	for k in range(-arm, arm + 1):
		for p in [Vector2i(c.x + k, c.y + k), Vector2i(c.x + k + 1, c.y + k),
				Vector2i(c.x + k, c.y - k), Vector2i(c.x + k + 1, c.y - k)]:
			red[p] = true
	for p in red.keys():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if not red.has(q):
				_put(img, q.x, q.y, OUTLINE)
	for p in red.keys():
		_put(img, p.x, p.y, CROSS_RED)

## Стрела «не достанут»: красное оперение и крестик на острие
static func _arrow_far() -> Image:
	var img := _arrow(false)
	_red_cross(img, Vector2i(int(TIP.x) + 2, int(TIP.y) + 2))
	return img

## Две скрещённые стрелы (курсор [A] у стрелков): стрела «на 10 часов» и
## её зеркало «на 2 часа», перекрестие в центре (горячая точка 16,16)
static func _arrows_x(in_range: bool) -> Image:
	var a := _arrow(in_range)
	var b := _arrow(in_range)
	b.flip_x()
	for y in range(SZ):
		for x in range(SZ):
			var cb: Color = b.get_pixel(x, y)
			if cb.a > 0.5 and a.get_pixel(x, y).a <= 0.5:
				a.set_pixel(x, y, cb)
	if not in_range:
		_red_cross(a, Vector2i(15, 16), 2)
	return a

## Топор: рукоять из правого нижнего угла, головка вверху слева, ЛЕЗВИЕ
## СМОТРИТ ВНИЗ-ВЛЕВО — в дерево под курсором (ТЗ 21.10.2026, письмо 4:
## прежде полумесяц глядел вверх-вправо, от ствола). Лезвие расширяется от
## проуха к выпуклой кромке; горячая точка — середина кромки (AXE_EDGE)
const AXE_HEAD := Vector2(13.0, 10.0)
const AXE_EDGE := Vector2(6, 17)

static func _axe() -> Image:
	var img := _blank()
	var iron := Color(0.80, 0.82, 0.88)
	var iron_dk := Color(0.48, 0.50, 0.56)
	var wood := Color(0.72, 0.47, 0.22)
	var wood_dk := Color(0.52, 0.32, 0.14)
	var c := AXE_HEAD
	var ax := Vector2(1, 1).normalized()      # вдоль рукояти, к руке
	var px := Vector2(-1, 1).normalized()     # поперёк, к лезвию (вниз-влево)
	for y in range(SZ):
		for x in range(SZ):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - c
			var u: float = d.dot(ax)
			var v: float = d.dot(px)
			# Рукоять и лезвие ШИРЕ (ТЗ 22.10.2026): было 1.4 и кромка 9.5
			if u > -3.0 and u < 23.0 and absf(v) <= 2.0:
				_put(img, x, y, wood if v < 0.5 else wood_dk)
			# Лезвие: от проуха (v = 1) к выпуклой кромке, ширина растёт
			var edge: float = 11.0 - u * u * 0.032
			if v > 1.5 and v < edge and absf(u) < 2.8 + (v - 1.5) * 0.62:
				_put(img, x, y, iron if v > edge - 2.6 else iron_dk)
			# Обух — короткий, по другую сторону рукояти
			if absf(u) <= 2.6 and v <= -1.5 and v >= -4.0:
				_put(img, x, y, iron_dk)
	return img

## Знак медицины (ТЗ 22.10.2026): зелёный крест с белой каймой, по оси —
## посох со змеёй (жезл Асклепия). Горячая точка — центр знака
static func _medic() -> Image:
	var img := _blank()
	var green := Color(0.20, 0.66, 0.32)
	var green_dk := Color(0.12, 0.44, 0.20)
	var rim := Color(0.96, 0.97, 0.94)
	var staff := Color(0.56, 0.36, 0.18)
	var snake := Color(0.88, 0.95, 0.80)
	# Кайма креста (на пиксель шире) и сам крест
	for y in range(SZ):
		for x in range(SZ):
			var dx: int = absi(x - 16)
			var dy: int = absi(y - 16)
			var arm: int = 6
			var reach: int = 14
			var in_rim: bool = (dx <= arm and dy <= reach) or (dy <= arm and dx <= reach)
			var in_cross: bool = (dx <= arm - 1 and dy <= reach - 1) or (dy <= arm - 1 and dx <= reach - 1)
			if in_cross:
				_put(img, x, y, green if (x + y) % 7 != 0 else green_dk)
			elif in_rim:
				_put(img, x, y, rim)
	# Посох по вертикали
	_rect(img, 15, 4, 16, 27, staff)
	# Змея: синусоида вокруг посоха, голова сверху
	for k in range(0, 44):
		var t: float = float(k) / 43.0
		var yy: float = 25.0 - t * 19.0
		var xx: float = 15.5 + sin(t * TAU * 1.5) * 3.2
		_put(img, int(round(xx)), int(round(yy)), snake)
		_put(img, int(round(xx)) + 1, int(round(yy)), snake)
	_rect(img, 17, 5, 19, 7, snake)
	return img

## Кирка: дугой поперёк вверху, рукоять вниз вправо; клюв слева — точка удара
static func _pickaxe() -> Image:
	var img := _blank()
	var iron := Color(0.74, 0.76, 0.82)
	var iron_dk := Color(0.46, 0.48, 0.54)
	var wood := Color(0.72, 0.47, 0.22)
	var wood_dk := Color(0.52, 0.32, 0.14)
	var c := Vector2(13.0, 13.0)
	var ax := Vector2(1, 1).normalized()
	var px := Vector2(-1, 1).normalized()
	for y in range(SZ):
		for x in range(SZ):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - c
			var u: float = d.dot(ax)
			var v: float = d.dot(px)
			if u > 0.0 and u < 22.0 and absf(v) <= 1.4:
				_put(img, x, y, wood if v < 0.3 else wood_dk)
			# Головка: дуга поперёк рукояти, концы загнуты к рукояти
			var bend: float = 0.06 * v * v
			if absf(v) <= 12.5 and absf(u + 1.5 - bend) <= 1.6 - absf(v) * 0.07:
				_put(img, x, y, iron if u < -1.0 + bend else iron_dk)
	return img

## Нож мясника: широкое лезвие от левого верхнего угла, рукоять вниз вправо
static func _knife() -> Image:
	var img := _blank()
	var blade := Color(0.88, 0.90, 0.94)
	var blade_dk := Color(0.58, 0.62, 0.70)
	var wood := Color(0.55, 0.32, 0.16)
	var rivet := Color(0.93, 0.80, 0.40)
	var tip := Vector2(4.0, 4.0)
	var ax := Vector2(1, 1).normalized()
	var px := Vector2(-1, 1).normalized()
	for y in range(SZ):
		for x in range(SZ):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - tip
			var u: float = d.dot(ax)
			var v: float = d.dot(px)
			if u < 0.0:
				continue
			if u <= 18.0:
				# Обух прямой (v ≤ 0), режущая кромка изогнута к острию
				var belly: float = minf(4.2, 0.6 + u * 0.45)
				if v >= -1.2 and v <= belly:
					_put(img, x, y, blade if v < belly - 1.2 else blade_dk)
			elif u <= 32.0 and absf(v - 1.0) <= 2.0:
				var r: bool = (int(u) == 22 or int(u) == 28) and absf(v - 1.0) < 0.8
				_put(img, x, y, rivet if r else wood)
	return img

## Указательный палец: кисть внизу, палец вверх — горячая точка на кончике
static func _finger() -> Image:
	var img := _blank()
	var skin := Color(0.98, 0.86, 0.70)
	var skin_dk := Color(0.82, 0.64, 0.48)
	var cuff := Color(0.30, 0.46, 0.82)
	# Указательный палец
	for y in range(2, 16):
		for x in range(11, 16):
			var top_round: bool = y > 3 or (x > 11 and x < 15)
			if top_round:
				_put(img, x, y, skin_dk if x == 15 else skin)
	# Кисть с поджатыми пальцами
	for y in range(13, 26):
		for x in range(8, 25):
			if y == 13 and (x < 15 or x > 22):
				continue
			var knuckle: bool = y >= 14 and y <= 15 and (x == 18 or x == 21)
			_put(img, x, y, skin_dk if knuckle or x == 24 or y == 25 else skin)
	# Большой палец сбоку
	for y in range(16, 21):
		for x in range(5, 9):
			_put(img, x, y, skin if x > 5 else skin_dk)
	# Манжета
	_rect(img, 9, 26, 24, 30, cuff)
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
