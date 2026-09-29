extends Node2D
class_name FormationPreview

var _slot_screen:  Array   = []   # Vector2 — позиции слотов в экранных координатах
var _facing_angle: float   = 0.0  # угол поворота треугольников (радианы)
var _line_a:       Vector2 = Vector2.ZERO
var _line_b:       Vector2 = Vector2.ZERO
var _active:       bool    = false

## ═══════════════════════════════════════════════════════════════════════════
## ПРИЗРАК ФОРМАЦИИ ПОСЛЕ КЛИКА (ТЗ 23.09.2026, п. 4)
## ═══════════════════════════════════════════════════════════════════════════
## Заказ: «в точке назначения мгновенно отображается призрак формации — не
## кружочки, а силуэты на местах, чтобы игрок видел, КАК встанут войска».
## Растяг ПКМ это и так показывает (_slot_screen выше), но у ОБЫЧНОГО клика
## растяга нет вовсе: приказ отдаётся и исчезает без следа.
##
## ЭТО ОТДЕЛЬНОЕ СОСТОЯНИЕ, А НЕ «show_formation с таймером». Причина: растяг
## и призрак живут ОДНОВРЕМЕННО — игрок успевает начать новый растяг, пока
## гаснет призрак прошлого приказа, и общий буфер точек затирался бы на
## полпути. Два набора точек, один _draw.
##
## ЦВЕТ ГАСНЕТ, А НЕ РАЗМЕР. Расползающийся строй читался бы как «войска
## разбегаются» — ровно противоположное тому, что показывают
var _ghost_screen: Array = []
var _ghost_angle: float = 0.0
var _ghost_left: float = 0.0
## Одиночки (рабочий, монах): вместо строя — расходящееся кольцо в точке.
## Строить «формацию из одного треугольника» бессмысленно, а отклик на клик
## нужен и им (заказ прямо просит «минималистичную плавную анимацию»)
var _ping_screen: Vector2 = Vector2.ZERO
var _ping_left: float = 0.0

const GHOST_SEC := 0.85          # сколько живёт призрак строя
const PING_SEC := 0.55           # сколько живёт кольцо одиночки
const PING_R0 := 5.0             # начальный радиус кольца, px
const PING_R1 := 22.0            # конечный
const PING_COL := Color(0.99, 0.94, 0.35, 0.9)
## ── ДВОЙНОЙ КЛИК (БЕГ) — ОДИН ПУЛЬСАР С ОТТЕНКОМ (ТЗ 29.09.2026, п. 3) ────
## Второй клик пары не перезапускает вспышку первого (прежде было два
## пульсара подряд), а перекрашивает её в цвет бега и досчитывает её время
const RUN_TINT := Color(1.0, 0.50, 0.18)
var _run_tint: bool = false
var run_flashes: int = 0          # стендам: сколько вспышек ушло в цвет бега
var flash_starts: int = 0         # стендам: сколько вспышек стартовало с нуля

## Показать призрак строя в точке приказа. slots — те же экранные точки, что
## и у растяга: раскладку считает вызывающий ТЕМ ЖЕ кодом, каким отдаёт приказ
func flash_formation(slots: Array, facing_angle_rad: float, run: bool = false) -> void:
	if slots.is_empty():
		return
	_ghost_screen = slots
	_ghost_angle = facing_angle_rad
	_set_run_tint(run)
	if not (run and _ghost_left > 0.0):
		_ghost_left = GHOST_SEC
		flash_starts += 1
	visible = true
	set_process(true)
	queue_redraw()

## Кольцо в точке клика — для одиночек и для случая, когда строя нет
func flash_ping(screen_pos: Vector2, run: bool = false) -> void:
	_ping_screen = screen_pos
	_set_run_tint(run)
	if not (run and _ping_left > 0.0):
		_ping_left = PING_SEC
		flash_starts += 1
	visible = true
	set_process(true)
	queue_redraw()

func _set_run_tint(run: bool) -> void:
	_run_tint = run
	if run:
		run_flashes += 1

func _process(delta: float) -> void:
	var busy := false
	if _ghost_left > 0.0:
		_ghost_left -= delta
		busy = true
		if _ghost_left <= 0.0:
			_ghost_left = 0.0
			_ghost_screen = []
	if _ping_left > 0.0:
		_ping_left -= delta
		busy = true
		if _ping_left <= 0.0:
			_ping_left = 0.0
	if busy:
		queue_redraw()
	else:
		# ГАСНЕМ ПОЛНОСТЬЮ: узел без дела не тикает и не перерисовывается.
		# Видимость при этом снимаем, только если и растяг не идёт — иначе
		# погасший призрак утащил бы за собой живое превью
		set_process(false)
		if not _active:
			visible = false
		queue_redraw()

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
	# ВИДИМОСТЬ СНИМАЕТСЯ, ТОЛЬКО ЕСЛИ НЕЧЕГО ПОКАЗЫВАТЬ. hide_all зовётся по
	# отпусканию ПКМ — то есть ровно в тот миг, когда приказ отдан и призрак
	# ТОЛЬКО ЧТО зажёгся. Гаси мы узел безусловно, призрак не увидел бы никто
	if _ghost_left <= 0.0 and _ping_left <= 0.0:
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
	# ПРИЗРАК И КОЛЬЦО РИСУЮТСЯ ВСЕГДА, независимо от растяга: они и заведены
	# ради клика, у которого растяга нет
	if _ghost_left > 0.0:
		var k: float = clampf(_ghost_left / GHOST_SEC, 0.0, 1.0)
		_draw_triangles(_ghost_screen, _ghost_angle, k * k, _run_tint)
	if _ping_left > 0.0:
		var t: float = 1.0 - clampf(_ping_left / PING_SEC, 0.0, 1.0)
		var r: float = PING_R0 + (PING_R1 - PING_R0) * t
		var col := PING_COL
		if _run_tint:
			col = Color(RUN_TINT.r, RUN_TINT.g, RUN_TINT.b, PING_COL.a)
		col.a *= (1.0 - t) * (1.0 - t)
		draw_arc(_ping_screen, r, 0.0, TAU, 24, col, 1.6, true)
	if not _active or _slot_screen.is_empty():
		return
	_draw_triangles(_slot_screen, _facing_angle, 1.0)

## Весь строй — два вызова отрисовки (разбор ниже). fade — доля непрозрачности
func _draw_triangles(slots: Array, angle: float, fade: float, run: bool = false) -> void:
	if slots.is_empty() or fade <= 0.01:
		return
	var _facing_angle_local := angle
	var s := TRI_SIZE
	var ca := cos(_facing_angle_local)
	var sa := sin(_facing_angle_local)
	# Три вершины треугольника в местных осях (остриё вверх)
	var lx0 := 0.0;         var ly0 := -s
	var lx1 := -s * 0.62;   var ly1 := s * 0.75
	var lx2 := s * 0.62;    var ly2 := s * 0.75
	# Поворот местных вершин — общий для всех мест
	var rx0 := lx0 * ca - ly0 * sa; var ry0 := lx0 * sa + ly0 * ca
	var rx1 := lx1 * ca - ly1 * sa; var ry1 := lx1 * sa + ly1 * ca
	var rx2 := lx2 * ca - ly2 * sa; var ry2 := lx2 * sa + ly2 * ca

	var fill := TRI_FILL
	if run:
		fill = Color(RUN_TINT.r, RUN_TINT.g, RUN_TINT.b, TRI_FILL.a)
	var outline := TRI_OUTLINE
	fill.a *= fade
	outline.a *= fade
	var n := slots.size()
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
		var c: Vector2 = slots[i]
		var a := Vector2(c.x + rx0, c.y + ry0)
		var b := Vector2(c.x + rx1, c.y + ry1)
		var d := Vector2(c.x + rx2, c.y + ry2)
		var o := i * 3
		pts[o] = a;      pts[o + 1] = b;      pts[o + 2] = d
		cols[o] = fill; cols[o + 1] = fill; cols[o + 2] = fill
		idx[o] = o;      idx[o + 1] = o + 1;  idx[o + 2] = o + 2
		var l := i * 6
		lines[l] = a;     lines[l + 1] = b
		lines[l + 2] = b; lines[l + 3] = d
		lines[l + 4] = d; lines[l + 5] = a
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), idx, pts, cols)
	draw_multiline(lines, outline, 1.0)
