extends Control

## ═══════════════════════════════════════════════════════════════════════════
## КРУГОВОЙ ПРОГРЕСС «РАДАР» ПОВЕРХ КНОПКИ (заказ 13.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Ложится поверх кнопки исследования ранга рыцарей и рисует, сколько
## осталось: НЕВЫПОЛНЕННАЯ доля затемнена сектором, по кромке сектора бежит
## яркий луч развёртки, вокруг — тонкое кольцо. Заполнение идёт по часовой
## стрелке от «двенадцати часов», как у любого кругового индикатора.
##
## Мышь не ловит (MOUSE_FILTER_IGNORE): под ним живая кнопка, и клик обязан
## доходить до неё. Перерисовка — только когда меняется доля (queue_redraw
## в сеттере), а не каждый кадр: панель и так пересобирается по событиям.
##
## Без class_name намеренно: имя попадает в кэш классов только после импорта
## редактором, а стенды поднимают HUD без него (память проекта) — берётся
## через preload(...).new().

const SEG := 40                       # сегментов на полный круг
const DIM := Color(0.02, 0.03, 0.05, 0.62)   # затемнение невыполненной доли
const RING := Color(0.95, 0.82, 0.38, 0.85)  # кольцо
const SWEEP := Color(1.0, 0.95, 0.70, 0.95)  # луч развёртки
const DONE := Color(0.55, 0.85, 0.45, 0.30)  # лёгкая зелень на выполненной доле
const RING_W := 1.5
const INSET := 1.5                    # отступ круга от кромки кнопки

## Доля 0..1
var progress: float = 0.0:
	set(v):
		var nv: float = clampf(v, 0.0, 1.0)
		if absf(nv - progress) > 0.0005:
			progress = nv
			queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Центр и радиус круга: вписан в короткую сторону прямоугольника
func _circle() -> Array:
	var c: Vector2 = size * 0.5
	var r: float = maxf(minf(size.x, size.y) * 0.5 - INSET, 2.0)
	return [c, r]

func _draw() -> void:
	var cr: Array = _circle()
	var c: Vector2 = cr[0]
	var r: float = cr[1]
	var a0: float = -PI * 0.5                    # «двенадцать часов»
	var a_done: float = a0 + TAU * progress
	# Выполненная доля — еле заметная зелень, чтобы глаз видел «сколько уже»
	if progress > 0.001:
		draw_colored_polygon(_sector(c, r, a0, a_done), DONE)
	# Невыполненная доля — затемнена: цифра под ней читается, но приглушённо
	if progress < 0.999:
		draw_colored_polygon(_sector(c, r, a_done, a0 + TAU), DIM)
	# Луч развёртки на кромке заполнения
	if progress > 0.001 and progress < 0.999:
		var tip: Vector2 = c + Vector2(cos(a_done), sin(a_done)) * r
		draw_line(c, tip, SWEEP, 1.5, true)
	draw_arc(c, r, 0.0, TAU, SEG, RING, RING_W, true)

## Сектор круга от угла a до угла b, замкнутый через центр
func _sector(c: Vector2, r: float, a: float, b: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(c)
	var span: float = b - a
	var n: int = maxi(int(ceil(span / TAU * float(SEG))), 1)
	for i in range(n + 1):
		var t: float = a + span * float(i) / float(n)
		pts.append(c + Vector2(cos(t), sin(t)) * r)
	return pts
