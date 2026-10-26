extends Control
## ═══════════════════════════════════════════════════════════════════════════
## КНОПКА КОПИЛКИ ОПЫТА АРМИИ (ТЗ 10.10.2026, блок 5)
## ═══════════════════════════════════════════════════════════════════════════
## Круглая кнопка у левого края экрана. Кольцо — заполнение копилки
## (RelicManager.pool / POOL_COST), полная — золотая и мерцает; первый клик
## взводит выдачу — мерцает КРАСНЫМ, следующий ЛКМ по своему отряду вручает
## ему реликвию (разбор клика — SelectionManager, выдача — RelicManager).
## Свой CanvasLayer, а не узел HUD: панели HUD перестраиваются целиком, кнопке
## копилки там не место.

const _RCfgB := preload("res://scripts/relic_config.gd")

const SIZE := 58.0
const GOLD := Color(0.95, 0.76, 0.22)
const GOLD_DIM := Color(0.42, 0.33, 0.12)
const RED := Color(0.92, 0.18, 0.14)
const BG := Color(0.08, 0.07, 0.06, 0.88)

var _t: float = 0.0
var _tip_pool: int = -1

static func create_layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "RelicLayer"
	layer.layer = 11
	var b := Control.new()
	b.set_script(load("res://scripts/RelicButton.gd"))
	b.name = "RelicButton"
	layer.add_child(b)
	return layer

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_place()
	get_viewport().size_changed.connect(_place)

## ПОД ИКОНКОЙ РАБОЧИХ (ТЗ 11.10.2026, ч. 1 п. 2): левый край — по иконке
## рабочих, отступ сверху — ТОТ ЖЕ, что у иконки рабочих от нижней кромки
## плашки ресурсов. Числа берутся у живых виджетов HUD, а не константами:
## высота плашки зависит от шрифта и масштаба окна. Нет HUD (стенд) — прежнее
## место у левого края
func _place() -> void:
	var vs: Vector2 = get_viewport_rect().size
	var hud: Node = GameManager.main.hud if GameManager.main != null and is_instance_valid(GameManager.main) else null
	if hud != null:
		var idle = hud.get("_idle_btn")
		var res = hud.get("_res_panel")
		if is_instance_valid(idle) and is_instance_valid(res):
			var ic: Control = idle
			var rp: Control = res
			var gap: float = maxf(0.0, ic.position.y - (rp.position.y + rp.size.y))
			position = Vector2(ic.position.x, floorf(ic.position.y + ic.size.y + gap))
			return
	position = Vector2(12.0, floorf(vs.y * 0.34))

var _place_t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	# Плашка ресурсов меняет высоту после первой раскладки (шрифт, лимит
	# населения появляется позже) — место переспрашивается раз в полсекунды
	_place_t -= delta
	if _place_t <= 0.0:
		_place_t = 0.5
		_place()
	var m: Node = GameManager.relic_mgr()
	queue_redraw()
	if int(m.pool) == _tip_pool:
		return
	_tip_pool = int(m.pool)
	tooltip_text = tip_text(m.charged(), int(m.pool))

## ── ПОДСКАЗКА (ТЗ 24.10.2026, второе письмо, блок 2) ───────────────────────
## Была сплошная «стена текста» из шести строк. Теперь — состояние первой
## строкой, затем описание и повторное использование отдельными абзацами
static func tip_text(is_charged: bool, pool: int) -> String:
	var head: String
	if is_charged:
		head = "Штандарт готов!\nНажмите ПКМ, чтобы выбрать бонус и выдать отряду. ЛКМ/Esc — отмена."
	else:
		head = "[Недоступно] накапливается боевой опыт: %d / %d" % [pool, int(_RCfgB.POOL_COST)]
	var desc: String = "Штандарт выдаётся отряду за накопленный боевой опыт. Присваивает отряду\n" \
		+ "реликвию, увеличивая атаку, мораль и скорость удара в ауре %d м." % int(_RCfgB.AURA_RADIUS)
	var again: String = "При повторном использовании можно выдать новый штандарт или улучшить\nсуществующий."
	return head + "\n\n" + desc + "\n\n" + again

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	# ПКМ по самой кнопке тоже взводит (ТЗ 24.10.2026, второе письмо): в
	# подсказке выдача — ПКМ, и игрок жмёт ту же кнопку мыши с первого раза
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	var m: Node = GameManager.relic_mgr()
	if m.armed:
		m.arm(false)
	elif m.charged():
		m.arm(true)
		AudioManager.play_ui("order_unit")
	accept_event()

func _draw() -> void:
	var m: Node = GameManager.relic_mgr()
	var c := Vector2(SIZE, SIZE) * 0.5
	var r: float = SIZE * 0.5 - 3.0
	draw_circle(c, r, BG)
	var frac: float = m.pool_frac()
	var col: Color = GOLD
	var pulse: float = 0.5 + 0.5 * sin(_t * 6.0)
	if m.armed:
		col = RED.lerp(Color(1.0, 0.55, 0.45), pulse)
	elif frac >= 1.0:
		col = GOLD.lerp(Color(1.0, 0.95, 0.7), pulse)
	draw_arc(c, r - 2.0, 0.0, TAU, 48, GOLD_DIM, 4.0, true)
	# Крошечная дуга заряда рисуется скруглённой точкой — она читалась как
	# «жёлтая точка на ободе» (ТЗ 24.10.2026, блок 2). Видна от 2 %
	if frac >= 0.02:
		draw_arc(c, r - 2.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, col, 4.0, true)
	var full: bool = frac >= 1.0 and not m.armed
	if full:
		# Заряжен — мягкое свечение за полотнищем
		draw_circle(c, r * 0.80, Color(1.0, 0.82, 0.40, 0.10 + 0.14 * pulse))
	_draw_standard_icon(c, r, full)
	var charges: int = int(m.pool / _RCfgB.POOL_COST)
	if charges > 1:
		draw_string(ThemeDB.fallback_font, Vector2(SIZE - 16.0, SIZE - 4.0), "×%d" % charges,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)

## ── ЗНАЧОК ШТАНДАРТА В КРУГЕ ───────────────────────────────────────────────
## ТЗ 23.10.2026, п. 5: значок векторный — древко с перекладиной, полотнище с
## «ласточкиным хвостом» и золотой каймой, римская I; не тускнеет никогда,
## заряд показывает кольцо.
## ТЗ 24.10.2026 (второе письмо, блок 2): полотнище — благородный бордовый,
## как у знамени войск; фигура меньше прежней и ОТЦЕНТРОВАНА по своей рамке
## (прежде навершие древка садилось прямо на обод — «жёлтая точка»).
## Габарит фигуры — не дальше 0.80 r от центра, обод начинается с r − 4.
## Заряжен — по полотнищу бежит светлый блик (перелив)
const ICON_RED := Color(0.50, 0.06, 0.11)
const ICON_RED_DARK := Color(0.32, 0.03, 0.07)
const ICON_RED_HI := Color(0.74, 0.20, 0.24)
const ICON_POLE := Color(0.36, 0.22, 0.10)

## ── ДРЕВКО ЗА ПОЛОТНИЩЕМ, БЕЗ ТОЧКИ, ПОЛОТНИЩЕ УЖЕ (ТЗ 25.10.2026, UI, п. 2)
## Было: древко шло по левой кромке, над ним — золотая точка навершия
## («пиптык»). Теперь фигура симметрична по оси медальона: древко строго
## ПОЗАДИ полотнища по центру (рисуется первым, видно над перекладиной),
## навершия-точки нет, полотнище на 10 % уже (0.72 r против 0.80 r), цифра и
## кант пересчитаны от новой ширины и стоят по центру
const ICON_W_K := 0.72
func _draw_standard_icon(c: Vector2, r: float, shimmer: bool = false) -> void:
	var h: float = r * 1.15            # высота полотнища с древком
	var w: float = r * ICON_W_K        # ширина полотнища
	var box_h: float = h + r * 0.18
	var x0: float = c.x - w * 0.5
	var top: float = c.y - box_h * 0.5 + r * 0.13
	# Древко ПОЗАДИ полотнища, по оси; перекладина чуть шире ткани
	draw_line(Vector2(c.x, top - r * 0.02), Vector2(c.x, top + h + r * 0.05), ICON_POLE, maxf(2.0, r * 0.09), true)
	draw_line(Vector2(x0 - r * 0.07, top + r * 0.10), Vector2(x0 + w + r * 0.07, top + r * 0.10), ICON_POLE, maxf(2.0, r * 0.08), true)
	# Полотнище: прямоугольник с вырезом «ласточкин хвост» снизу
	var y_top: float = top + r * 0.16
	var y_bot: float = top + h
	var notch: float = h * 0.20
	var cloth := PackedVector2Array([
		Vector2(x0, y_top), Vector2(x0 + w, y_top), Vector2(x0 + w, y_bot),
		Vector2(x0 + w * 0.5, y_bot - notch), Vector2(x0, y_bot)])
	draw_colored_polygon(cloth, ICON_RED)
	# Тень складки по левой кромке
	draw_colored_polygon(PackedVector2Array([
		Vector2(x0, y_top), Vector2(x0 + w * 0.16, y_top),
		Vector2(x0 + w * 0.16, y_bot - notch * 0.32), Vector2(x0, y_bot)]), ICON_RED_DARK)
	if shimmer:
		# Перелив: косая светлая полоса едет по полотнищу слева направо раз
		# в 1.6 с; обрезана по прямоугольнику полотнища выше выреза
		var ph: float = fmod(_t / 1.6, 1.0)
		var bx: float = x0 - w * 0.4 + ph * w * 1.8
		var band := PackedVector2Array([
			Vector2(clampf(bx, x0, x0 + w), y_top),
			Vector2(clampf(bx + w * 0.22, x0, x0 + w), y_top),
			Vector2(clampf(bx + w * 0.02, x0, x0 + w), y_bot - notch),
			Vector2(clampf(bx - w * 0.20, x0, x0 + w), y_bot - notch)])
		var a: float = 0.55 * sin(PI * ph)
		draw_colored_polygon(band, Color(ICON_RED_HI.r, ICON_RED_HI.g, ICON_RED_HI.b, a))
	var edge := cloth.duplicate()
	edge.append(cloth[0])
	draw_polyline(edge, GOLD, maxf(1.5, r * 0.054), true)
	# Римская I — золотом по ОСИ медальона, засечки — от ширины полотнища
	var cx: float = c.x
	var iy0: float = y_top + h * 0.16
	var iy1: float = y_bot - notch - h * 0.08
	var iw: float = maxf(2.0, r * 0.108)
	var serif: float = w * 0.15
	draw_line(Vector2(cx, iy0), Vector2(cx, iy1), GOLD, iw, true)
	draw_line(Vector2(cx - serif, iy0), Vector2(cx + serif, iy0), GOLD, maxf(1.5, r * 0.063), true)
	draw_line(Vector2(cx - serif, iy1), Vector2(cx + serif, iy1), GOLD, maxf(1.5, r * 0.063), true)
