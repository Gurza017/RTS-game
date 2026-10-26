extends Control

## ═══════════════════════════════════════════════════════════════════════════
## ФОНОВАЯ ИЛЛЮСТРАЦИЯ МЕНЮ И ЭКРАНА ЗАГРУЗКИ (ТЗ 21.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Закат над долиной: небо, солнце, дальние горы, крепость на холме, туман
## по низинам и в переднем плане — шеренги копейщиков с поднятыми копьями и
## знамёнами. Рисуется кодом (_draw) в любом разрешении: готовой картинки без
## чужих прав в проекте нет, а растр под 4K весил бы больше всей игры.
##
## ФОРМА СЛУЧАЙНА, НО ПОСТОЯННА: свой RandomNumberGenerator с фиксированным
## зерном пересоздаётся на каждый кадр рисования. Общий randf() НЕ ТРОГАЕТСЯ —
## экран загрузки рисуется, пока Main сеет карту (правило сеяных лотерей).
##
## ТЗ 22.10.2026: ОСНОВНОЙ ФОН — ГОТОВАЯ КАРТИНКА `BACKDROP_PATH` (замок игры
## с лучниками на настиле, блоки копейщиков с вымпелами, стрелы, дым; собрана
## из спрайтов игры скриптом tools/make_menu_art.py, 3840x2160). Её ставит
## `backdrop()` — TextureRect с KEEP_ASPECT_COVERED: без искажений от 1280x720
## до 4K, лишнее срезается по краям. Поверх картинки этот узел рисует только
## искры и виньетку (`overlay_only`). Рисованная кодом сцена ниже — запасная:
## если картинки в сборке нет, фон остаётся прежним.
##
## Анимация дешёвая: знамёна колышутся, искры поднимаются (animate = true).
## На экране загрузки во время синхронной сборки сцены кадры не идут — тогда
## картинка просто стоит, это честно.

@export var animate: bool = true
## Сила затемнения краёв (виньетка) — под окнами меню текст читается лучше
@export var vignette: float = 0.55

const ART_SEED := 1066
const BACKDROP_PATH := "res://assets/ui/menu_background_castle.png"

## Только искры и виньетка — под ним лежит картинка `backdrop()`
@export var overlay_only: bool = false

## Фоновая картинка во весь экран или null, если её нет в сборке
static func backdrop() -> TextureRect:
	if not ResourceLoader.exists(BACKDROP_PATH):
		return null
	var tex := load(BACKDROP_PATH) as Texture2D
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.name = "MenuBackdrop"
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Картинка крупнее экрана почти всегда: сглаживание с мипами, иначе
	# пиксельные спрайты на уменьшении рябят
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr

var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not animate or not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 2.0 or h < 2.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = ART_SEED
	if overlay_only:
		_embers(w, h, rng)
		_vignette(w, h)
		return
	var horizon: float = h * 0.60
	_sky(w, h, horizon)
	_sun(Vector2(w * 0.68, horizon - h * 0.19), h * 0.075)
	_clouds(w, h, rng)
	_ridge(w, horizon - h * 0.16, h * 0.10, Color(0.36, 0.20, 0.26), rng, 9, horizon + 4.0)
	_ridge(w, horizon - h * 0.07, h * 0.07, Color(0.25, 0.14, 0.19), rng, 13, horizon + 4.0)
	_mist(w, horizon - h * 0.05, h * 0.09, Color(0.95, 0.55, 0.35, 0.18))
	_castle(Vector2(w * 0.22, horizon - h * 0.01), h * 0.00095)
	_hills(w, h, horizon, rng)
	_mist(w, horizon + h * 0.04, h * 0.08, Color(0.60, 0.32, 0.30, 0.20))
	_army(w, h, horizon, rng)
	_embers(w, h, rng)
	_vignette(w, h)

# ── НЕБО: вертикальный градиент полосами ─────────────────────────────────────
func _sky(w: float, h: float, horizon: float) -> void:
	var stops: Array = [
		[0.00, Color(0.07, 0.07, 0.16)],
		[0.30, Color(0.22, 0.12, 0.24)],
		[0.55, Color(0.62, 0.26, 0.20)],
		[0.80, Color(0.93, 0.52, 0.24)],
		[1.00, Color(0.99, 0.78, 0.42)],
	]
	for i in range(stops.size() - 1):
		var y0: float = float(stops[i][0]) * horizon
		var y1: float = float(stops[i + 1][0]) * horizon
		var c0: Color = stops[i][1]
		var c1: Color = stops[i + 1][1]
		draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]),
			PackedColorArray([c0, c0, c1, c1]))
	# земля под горизонтом — тёмная подложка
	var g0 := Color(0.16, 0.09, 0.10)
	var g1 := Color(0.05, 0.03, 0.04)
	draw_polygon(PackedVector2Array([Vector2(0, horizon), Vector2(w, horizon), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([g0, g0, g1, g1]))

func _sun(c: Vector2, r: float) -> void:
	for i in range(6, 0, -1):
		var k: float = float(i) / 6.0
		draw_circle(c, r * (1.0 + k * 2.2), Color(1.0, 0.70, 0.35, 0.05 * (1.0 - k) + 0.02))
	draw_circle(c, r, Color(1.0, 0.86, 0.55))
	draw_circle(c, r * 0.82, Color(1.0, 0.93, 0.70))

func _clouds(w: float, h: float, rng: RandomNumberGenerator) -> void:
	for i in range(7):
		var y: float = h * rng.randf_range(0.08, 0.42)
		var x0: float = w * rng.randf_range(-0.2, 0.9) + fmod(_t * (4.0 + i), w * 0.3)
		var len: float = w * rng.randf_range(0.18, 0.40)
		var th: float = h * rng.randf_range(0.008, 0.02)
		var col := Color(0.32, 0.16, 0.26, 0.55) if y < h * 0.3 else Color(0.85, 0.42, 0.28, 0.35)
		var pts := PackedVector2Array()
		var n := 14
		for k in range(n + 1):
			var u: float = float(k) / n
			pts.append(Vector2(x0 + len * u, y - th * sin(u * PI) * (1.0 + 0.3 * sin(u * 9.0 + i))))
		for k in range(n, -1, -1):
			var u2: float = float(k) / n
			pts.append(Vector2(x0 + len * u2, y + th * 0.5 * sin(u2 * PI)))
		draw_colored_polygon(pts, col)

## Хребет: ломаная по шагам с шумом, залита до низа
func _ridge(w: float, base_y: float, amp: float, col: Color, rng: RandomNumberGenerator, steps: int, bottom: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(0, bottom))
	for i in range(steps + 1):
		var x: float = w * float(i) / steps
		var y: float = base_y - amp * (0.3 + 0.7 * absf(sin(float(i) * 1.7 + rng.randf() * 2.0)))
		pts.append(Vector2(x, y))
		if i < steps:
			pts.append(Vector2(x + w / steps * 0.5, base_y - amp * rng.randf_range(0.0, 0.35)))
	pts.append(Vector2(w, bottom))
	draw_colored_polygon(pts, col)

func _mist(w: float, y: float, th: float, col: Color) -> void:
	var c0 := Color(col.r, col.g, col.b, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, y - th), Vector2(w, y - th), Vector2(w, y), Vector2(0, y)]),
		PackedColorArray([c0, c0, col, col]))
	draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(w, y), Vector2(w, y + th), Vector2(0, y + th)]),
		PackedColorArray([col, col, c0, c0]))

## КРЕПОСТЬ: донжон, две башни, стены с зубцами, окна с огнём, флаги
func _castle(base: Vector2, s: float) -> void:
	var col := Color(0.11, 0.06, 0.08)
	var u: float = 100.0 * s
	# холм под крепостью
	var hill := PackedVector2Array()
	for i in range(21):
		var a: float = PI * float(i) / 20.0
		hill.append(base + Vector2(-cos(a) * u * 3.4, -sin(a) * u * 0.55 + u * 0.3))
	draw_colored_polygon(hill, Color(0.14, 0.08, 0.10))
	# стена
	_battlement(Rect2(base.x - u * 2.2, base.y - u * 0.9, u * 4.4, u * 0.9), u * 0.16, col)
	# башни
	for tx in [-2.3, 1.75]:
		_tower(Vector2(base.x + u * tx, base.y), u * 0.55, u * 1.7, col)
	# донжон
	_battlement(Rect2(base.x - u * 0.7, base.y - u * 2.1, u * 1.4, u * 2.1), u * 0.18, col)
	_tower(Vector2(base.x + u * 0.05, base.y - u * 2.0), u * 0.45, u * 0.9, col)
	# окна с огнём
	var fire := Color(1.0, 0.62, 0.25, 0.85)
	for p in [Vector2(-0.35, -1.6), Vector2(0.2, -1.6), Vector2(-0.1, -1.05), Vector2(-2.05, -1.1), Vector2(2.0, -1.0), Vector2(1.0, -0.45), Vector2(-1.2, -0.45)]:
		var q: Vector2 = base + p * u
		draw_rect(Rect2(q.x, q.y, u * 0.09, u * 0.16), fire)
	# ворота
	var gate := PackedVector2Array()
	for i in range(11):
		var a2: float = PI * float(i) / 10.0
		gate.append(Vector2(base.x + cos(a2) * u * 0.28, base.y - u * 0.35 - sin(a2) * u * 0.2))
	gate.append(Vector2(base.x - u * 0.28, base.y))
	gate.append(Vector2(base.x + u * 0.28, base.y))
	draw_colored_polygon(gate, Color(0.05, 0.02, 0.03))
	# флаги на башнях
	_flag(Vector2(base.x + u * 0.05, base.y - u * 3.5), u * 0.9, Color(0.75, 0.12, 0.10), 0.0)
	_flag(Vector2(base.x - u * 2.3, base.y - u * 2.35), u * 0.6, Color(0.75, 0.12, 0.10), 1.3)
	_flag(Vector2(base.x + u * 1.75, base.y - u * 2.35), u * 0.6, Color(0.75, 0.12, 0.10), 2.1)

func _battlement(r: Rect2, tooth: float, col: Color) -> void:
	draw_rect(r, col)
	var n: int = int(r.size.x / (tooth * 2.0))
	for i in range(n + 1):
		draw_rect(Rect2(r.position.x + i * tooth * 2.0, r.position.y - tooth, tooth, tooth), col)

func _tower(foot: Vector2, wd: float, ht: float, col: Color) -> void:
	_battlement(Rect2(foot.x - wd * 0.5, foot.y - ht, wd, ht), wd * 0.2, col)
	draw_colored_polygon(PackedVector2Array([Vector2(foot.x - wd * 0.62, foot.y - ht - wd * 0.2),
		Vector2(foot.x + wd * 0.62, foot.y - ht - wd * 0.2), Vector2(foot.x, foot.y - ht - wd * 1.3)]), col)

## Знамя на древке: полотнище — ломаная с волной по времени
func _flag(top: Vector2, len: float, col: Color, phase: float) -> void:
	draw_line(top, top + Vector2(0, len * 1.4), Color(0.08, 0.05, 0.05), maxf(1.0, len * 0.05), true)
	var pts := PackedVector2Array()
	var n := 8
	var fh: float = len * 0.38
	for i in range(n + 1):
		var u: float = float(i) / n
		pts.append(top + Vector2(u * len, sin(_t * 3.0 + phase + u * 5.0) * len * 0.07 * u))
	for i in range(n, -1, -1):
		var u2: float = float(i) / n
		var tail: float = fh * (1.0 - 0.35 * u2)
		pts.append(top + Vector2(u2 * len, tail + sin(_t * 3.0 + phase + u2 * 5.0) * len * 0.07 * u2))
	draw_colored_polygon(pts, col)
	draw_polyline(pts, col.darkened(0.45), maxf(1.0, len * 0.02), true)

func _hills(w: float, h: float, horizon: float, rng: RandomNumberGenerator) -> void:
	var pts := PackedVector2Array([Vector2(0, h)])
	var n := 10
	for i in range(n + 1):
		var x: float = w * float(i) / n
		pts.append(Vector2(x, horizon + h * 0.05 + sin(float(i) * 1.1 + rng.randf()) * h * 0.025))
	pts.append(Vector2(w, h))
	draw_colored_polygon(pts, Color(0.12, 0.07, 0.08))

## АРМИЯ: шеренги силуэтов от дальних (мелкие, в дымке) к ближним
func _army(w: float, h: float, horizon: float, rng: RandomNumberGenerator) -> void:
	var rows: Array = [
		[horizon + h * 0.075, h * 0.050, Color(0.20, 0.11, 0.12), 46],
		[horizon + h * 0.13,  h * 0.075, Color(0.13, 0.07, 0.08), 32],
		[horizon + h * 0.22,  h * 0.115, Color(0.07, 0.04, 0.05), 22],
		[horizon + h * 0.36,  h * 0.170, Color(0.03, 0.02, 0.02), 14],
	]
	for ri in range(rows.size()):
		var r: Array = rows[ri]
		var y: float = float(r[0])
		var sh: float = float(r[1])
		var col: Color = r[2]
		var count: int = int(r[3])
		var step: float = w / float(count)
		# земля ряда
		draw_rect(Rect2(0, y - sh * 0.05, w, h - y + sh * 0.05), col)
		for i in range(count + 1):
			var x: float = step * (float(i) + rng.randf_range(-0.25, 0.25) + (0.5 if ri % 2 == 1 else 0.0))
			_soldier(Vector2(x, y), sh * rng.randf_range(0.92, 1.06), col, rng)
		# знамёна над рядом
		var flags: int = 2 + ri
		for f in range(flags):
			var fx: float = w * (float(f) + 0.5 + rng.randf_range(-0.2, 0.2)) / float(flags)
			var fc := Color(0.62, 0.10, 0.08) if (f + ri) % 2 == 0 else Color(0.70, 0.52, 0.16)
			fc = fc.darkened(0.62 - 0.12 * ri)
			_flag(Vector2(fx, y - sh * 2.0), sh * 0.42, fc, float(f) * 1.7 + ri)

## Копейщик: голова, корпус, щит, копьё под небольшим наклоном
func _soldier(foot: Vector2, s: float, col: Color, rng: RandomNumberGenerator) -> void:
	var bw: float = s * 0.30
	draw_colored_polygon(PackedVector2Array([
		foot + Vector2(-bw * 0.55, 0), foot + Vector2(bw * 0.55, 0),
		foot + Vector2(bw * 0.45, -s * 0.62), foot + Vector2(-bw * 0.45, -s * 0.62)]), col)
	draw_circle(foot + Vector2(0, -s * 0.72), s * 0.12, col)
	# шлем-конус
	draw_colored_polygon(PackedVector2Array([foot + Vector2(-s * 0.13, -s * 0.74),
		foot + Vector2(s * 0.13, -s * 0.74), foot + Vector2(0, -s * 0.92)]), col)
	# щит
	draw_colored_polygon(PackedVector2Array([foot + Vector2(-bw * 0.95, -s * 0.55),
		foot + Vector2(-bw * 0.15, -s * 0.58), foot + Vector2(-bw * 0.2, -s * 0.18),
		foot + Vector2(-bw * 0.6, -s * 0.05), foot + Vector2(-bw * 1.0, -s * 0.2)]), col.lightened(0.04))
	# копьё
	var lean: float = rng.randf_range(0.04, 0.12)
	var a := foot + Vector2(bw * 0.5, -s * 0.05)
	var b := a + Vector2(s * lean * 2.0, -s * 1.85)
	draw_line(a, b, col, maxf(1.0, s * 0.035), true)
	var dir: Vector2 = (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([b + dir * s * 0.14, b + nrm * s * 0.035, b - nrm * s * 0.035]),
		col.lerp(Color(0.85, 0.55, 0.35), 0.18))

func _embers(w: float, h: float, rng: RandomNumberGenerator) -> void:
	for i in range(46):
		var x0: float = rng.randf() * w
		var sp: float = rng.randf_range(14.0, 40.0)
		var ph: float = rng.randf() * 100.0
		var y: float = h - fmod(_t * sp + ph * 13.0, h * 0.75)
		var x: float = x0 + sin(_t * 0.8 + ph) * 18.0
		var life: float = clampf((y - h * 0.25) / (h * 0.75), 0.0, 1.0)
		draw_circle(Vector2(x, y), rng.randf_range(1.0, 2.4), Color(1.0, 0.62, 0.25, 0.55 * life))

func _vignette(w: float, h: float) -> void:
	if vignette <= 0.0:
		return
	var dark := Color(0.0, 0.0, 0.0, vignette)
	var none := Color(0.0, 0.0, 0.0, 0.0)
	var bw: float = w * 0.18
	var bh: float = h * 0.22
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(bw, 0), Vector2(bw, h), Vector2(0, h)]),
		PackedColorArray([dark, none, none, dark]))
	draw_polygon(PackedVector2Array([Vector2(w - bw, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - bw, h)]),
		PackedColorArray([none, dark, dark, none]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, bh), Vector2(0, bh)]),
		PackedColorArray([dark, dark, none, none]))
	draw_polygon(PackedVector2Array([Vector2(0, h - bh), Vector2(w, h - bh), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([none, none, dark, dark]))
