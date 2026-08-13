extends Node2D
class_name FormationPreview

var _slot_screen:  Array   = []   # Vector2 — позиции слотов в экранных координатах
var _facing_angle: float   = 0.0  # угол поворота треугольников (радианы)
var _line_a:       Vector2 = Vector2.ZERO
var _line_b:       Vector2 = Vector2.ZERO
var _active:       bool    = false

func show_formation(slots: Array, facing_angle_rad: float, a: Vector2, b: Vector2) -> void:
	_slot_screen  = slots
	_facing_angle = facing_angle_rad
	_line_a       = a
	_line_b       = b
	_active       = true
	visible       = true
	queue_redraw()

func hide_all() -> void:
	_active = false
	visible = false
	queue_redraw()

# ─────────────────────────────────────────────────────────────────────────────
# ТОЛЬКО ТРЕУГОЛЬНИКИ. Жёлтая полоса вдоль линии формации и крупная
# стрелка-ромб посередине убраны: полоса выглядела грубо и перечёркивала
# карту. Теперь при растягивании ПКМ игрок видит ровно то, что расставляет —
# по треугольнику на место каждого бойца, остриём в заданном направлении.
# ─────────────────────────────────────────────────────────────────────────────
const TRI_SIZE := 6.5
const TRI_FILL    := Color(0.99, 0.94, 0.35, 0.85)
const TRI_OUTLINE := Color(0.35, 0.28, 0.02, 0.75)

# ─────────────────────────────────────────────────────────────────────────────
# ВЕСЬ СТРОЙ — ДВА ВЫЗОВА ОТРИСОВКИ, А НЕ ДВА НА БОЙЦА
#
# Было: на каждое место draw_colored_polygon + draw_polyline, то есть 2N
# примитивов на кадр. На выделении в несколько сотен бойцов это сотни
# отдельных элементов канваса, и вместе с пересчётом на каждое событие мыши
# (см. SelectionManager._process) давало падение с 60 до 29 к/с при
# растягивании линии.
#
# Стало: все треугольники собираются в ОДИН индексированный массив и уходят
# одним canvas_item_add_triangle_array, а все контуры — одним draw_multiline.
# Картинка та же до пикселя: те же вершины, те же цвета, та же толщина.
#
# Вершины считаются БЕЗ Vector2.rotated() на каждую точку: синус и косинус
# угла общие для всего строя, поэтому берутся один раз до цикла
# ─────────────────────────────────────────────────────────────────────────────
func _draw() -> void:
	if not _active or _slot_screen.is_empty():
		return
	var s := TRI_SIZE
	var ca := cos(_facing_angle)
	var sa := sin(_facing_angle)
	# Три вершины треугольника в местных осях (остриё вверх)
	var lx0 := 0.0;         var ly0 := -s
	var lx1 := -s * 0.62;   var ly1 := s * 0.75
	var lx2 := s * 0.62;    var ly2 := s * 0.75
	# Поворот местных вершин — общий для всех мест
	var rx0 := lx0 * ca - ly0 * sa; var ry0 := lx0 * sa + ly0 * ca
	var rx1 := lx1 * ca - ly1 * sa; var ry1 := lx1 * sa + ly1 * ca
	var rx2 := lx2 * ca - ly2 * sa; var ry2 := lx2 * sa + ly2 * ca

	var n := _slot_screen.size()
	var pts := PackedVector2Array()
	pts.resize(n * 3)
	var cols := PackedColorArray()
	cols.resize(n * 3)
	var idx := PackedInt32Array()
	idx.resize(n * 3)
	# Контуры: draw_multiline рисует ОТДЕЛЬНЫЕ отрезки парами точек, поэтому на
	# треугольник приходится три пары
	var lines := PackedVector2Array()
	lines.resize(n * 6)
	for i in range(n):
		var c: Vector2 = _slot_screen[i]
		var a := Vector2(c.x + rx0, c.y + ry0)
		var b := Vector2(c.x + rx1, c.y + ry1)
		var d := Vector2(c.x + rx2, c.y + ry2)
		var o := i * 3
		pts[o] = a;      pts[o + 1] = b;      pts[o + 2] = d
		cols[o] = TRI_FILL; cols[o + 1] = TRI_FILL; cols[o + 2] = TRI_FILL
		idx[o] = o;      idx[o + 1] = o + 1;  idx[o + 2] = o + 2
		var l := i * 6
		lines[l] = a;     lines[l + 1] = b
		lines[l + 2] = b; lines[l + 3] = d
		lines[l + 4] = d; lines[l + 5] = a
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), idx, pts, cols)
	draw_multiline(lines, TRI_OUTLINE, 1.0)
