extends Control
## ── КРУГ ОТКАТА ПОВЕРХ КНОПКИ ПРИЁМА (ТЗ 23.10.2026, п. 6) ──────────────────
## «Радар восстановления»: тёмный сектор по часовой стрелке от верха — доля
## оставшегося отката «Яростной атаки» (GameManager.squad_rage_cd_frac), в
## середине — секунды. Готово — ничего не рисуется. Откат — самый длинный из
## выделенных отрядов (кнопка одна на выделение)

var sids: Array = []
var _last: float = -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func frac() -> float:
	var f := 0.0
	for s in sids:
		f = maxf(f, GameManager.squad_rage_cd_frac(int(s)))
	return f

func _process(_d: float) -> void:
	var f: float = frac()
	if absf(f - _last) > 0.004 or (f == 0.0) != (_last == 0.0):
		_last = f
		queue_redraw()

func _draw() -> void:
	var f: float = frac()
	if f <= 0.0:
		return
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5
	var pts := PackedVector2Array([c])
	var steps: int = maxi(3, int(48.0 * f))
	for i in range(steps + 1):
		var a: float = -PI * 0.5 + TAU * f * float(i) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * r * 1.5)
	# Сектор режется рамкой кнопки (clip_contents у кнопки не обязателен:
	# радиус 1.5 только чтобы углы квадрата тоже темнели)
	draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.62))
	draw_arc(c, r - 2.0, -PI * 0.5, -PI * 0.5 + TAU * f, 32, Color(1.0, 0.55, 0.2, 0.9), 2.0, true)
	var left: float = f * GameManager.RAGE_ABILITY_COOLDOWN_SEC
	draw_string(ThemeDB.fallback_font, Vector2(0.0, c.y + 5.0), "%d" % int(ceil(left)),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(1, 0.95, 0.85))
