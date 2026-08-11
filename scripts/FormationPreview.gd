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

func _draw() -> void:
	if not _active:
		return
	for pos in _slot_screen:
		_draw_unit_tri(pos as Vector2, _facing_angle)

# Треугольник места одного бойца: остриё смотрит по вектору формации.
# Контур тонкой тёмной линией — иначе на светлой траве заливка теряется
func _draw_unit_tri(center: Vector2, angle: float) -> void:
	var s := TRI_SIZE
	var pts := PackedVector2Array([
		Vector2(0.0,  -s),                # остриё
		Vector2(-s * 0.62,  s * 0.75),
		Vector2( s * 0.62,  s * 0.75),
	])
	var out := PackedVector2Array()
	for p in pts:
		out.append(p.rotated(angle) + center)
	draw_colored_polygon(out, TRI_FILL)
	out.append(out[0])
	draw_polyline(out, TRI_OUTLINE, 1.0)
