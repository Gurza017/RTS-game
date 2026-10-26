extends Control
## ═══════════════════════════════════════════════════════════════════════════
## ОКОШКО СТРОЯ НАД МИНИ-КАРТОЙ (ТЗ 11.10.2026, ч. 1 п. 6)
## ═══════════════════════════════════════════════════════════════════════════
## Заменило текстовый индикатор «строй [1] широкий» в правой верхней панели.
## Три ячейки со СХЕМОЙ, а не словами:
##   [1] широкий фронт — точки в одну линию;
##   [2] блоки сеткой (с ТЗ 20.10.2026 три шеренги копейщикам не навязываются);
##   [3] авангард — передняя шеренга цветом рода, который ставится вперёд
##       (копейщики → мечники → лучники по кругу).
## Активный режим — в золотой рамке. Клик по ячейке — то же, что клавиша
## (SelectionManager._formation_key): режим запоминается и действует на
## следующий растяг ПКМ. Состояние читается ПРЯМО из SelectionManager каждый
## кадр отрисовки (второго источника правды нет — тот же принцип, что был у
## текстового индикатора). Создаёт и ставит Minimap (тот же слой, над картой).

const CELLS := 3
const PAD := 4.0
const GAP := 4.0
const C_BG := Color(0.04, 0.04, 0.08, 0.92)
const C_BORDER := Color(0.30, 0.25, 0.15)
const C_CELL := Color(0.10, 0.10, 0.16)
const C_ON := Color(0.98, 0.80, 0.30)
const C_DOT := Color(0.82, 0.86, 0.92)
const C_KEY := Color(0.95, 0.85, 0.55)
## Цвет авангарда по SelectionManager.formation_front: копейщики, мечники, лучники
const FRONT_COLORS := [Color(0.45, 0.70, 1.0), Color(0.86, 0.45, 0.95), Color(0.45, 0.90, 0.45)]
const FRONT_NAMES := ["копейщики", "мечники", "лучники"]
## ПОДПИСИ (ТЗ 12.10.2026): короче, вдвое мельче системной подсказки и
## аккуратно НАД окошком, а не у курсора (системный tooltip_text рисовался
## крупно и налезал на поле)
const TIPS := [
	"1 - Широкий фронт",
	"2 - Глубокий фронт",
	"3 - Смена юнитов в авангарде",
]
const TIP_FONT := 10
const TIP_GAP := 3.0

var _last_key: int = -1
var _tip: PanelContainer = null
var _tip_lbl: Label = null
var _tip_cell: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

func _sm():
	var m = GameManager.main
	if m == null or not is_instance_valid(m):
		return null
	return m.get("selection_manager")

func _process(_delta: float) -> void:
	var sm = _sm()
	if sm == null:
		return
	if _press_left > 0.0:
		_press_left -= _delta
		if _press_left <= 0.0:
			_press_cell = -1
			queue_redraw()
	var key: int = int(sm.formation_mode) * 10 + int(sm.formation_front)
	if key != _last_key:
		_last_key = key
		queue_redraw()

func _cell_rect(i: int) -> Rect2:
	var cw: float = (size.x - PAD * 2.0 - GAP * float(CELLS - 1)) / float(CELLS)
	return Rect2(PAD + float(i) * (cw + GAP), PAD, cw, size.y - PAD * 2.0)

## ── КНОПКИ-ПЛИТКИ (ТЗ 20.10.2026, блок 2) ─────────────────────────────────
## «Сделать кнопочки над картой явными, красивыми прямоугольными/почти
## квадратными с чётким визуальным откликом». Каждая ячейка — объёмная плитка:
## светлая фаска сверху, тёмная снизу, наведение подсвечивает плитку, нажатие
## «вдавливает» её (фаски меняются местами, схема смещается на пиксель) на
## PRESS_SEC, активный режим — золотая рамка и подсветка фона
const C_CELL_HI := Color(0.17, 0.17, 0.26)
const C_CELL_ON := Color(0.22, 0.19, 0.10)
const C_BEVEL_LT := Color(1.0, 1.0, 1.0, 0.16)
const C_BEVEL_DK := Color(0.0, 0.0, 0.0, 0.45)
const PRESS_SEC := 0.14
var _hover_cell: int = -1
var _press_cell: int = -1
var _press_left: float = 0.0

func _draw() -> void:
	var sm = _sm()
	draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), C_BORDER, false, 2.0)
	var mode: int = int(sm.formation_mode) if sm != null else 1
	var front: int = int(sm.formation_front) if sm != null else 0
	var deep_id: int = int(sm.FORM_DEEP) if sm != null else 2
	var font: Font = get_theme_default_font()
	for i in range(CELLS):
		var r := _cell_rect(i)
		var on: bool = (i == 0 and mode != deep_id) or (i == 1 and mode == deep_id)
		if i == 2:
			on = front != 0
		var pressed: bool = i == _press_cell and _press_left > 0.0
		var bg: Color = C_CELL_ON if on else C_CELL
		if i == _hover_cell and not pressed:
			bg = bg.lightened(0.18) if on else C_CELL_HI
		draw_rect(r, bg, true)
		# Фаски: выпуклая плитка — свет сверху/слева; вдавленная — наоборот
		var lt: Color = C_BEVEL_DK if pressed else C_BEVEL_LT
		var dk: Color = C_BEVEL_LT if pressed else C_BEVEL_DK
		draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), lt, 2.0)
		draw_line(r.position + Vector2(1, 1), Vector2(r.position.x + 1, r.end.y - 1), lt, 2.0)
		draw_line(Vector2(r.position.x + 1, r.end.y - 1), r.end - Vector2(1, 1), dk, 2.0)
		draw_line(Vector2(r.end.x - 1, r.position.y + 1), r.end - Vector2(1, 1), dk, 2.0)
		draw_rect(r, C_ON if on else (C_KEY if i == _hover_cell else C_BORDER), false, 2.0 if on else 1.0)
		var sh := Vector2(1.0, 1.0) if pressed else Vector2.ZERO
		# Номер клавиши — в левом верхнем углу ячейки
		if font != null:
			draw_string(font, r.position + Vector2(4.0, 12.0) + sh, str(i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, C_ON if on else C_KEY)
		var c: Vector2 = r.get_center() + Vector2(3.0, 2.0) + sh
		var dot: float = 1.8
		match i:
			0:
				for k in range(5):
					draw_circle(c + Vector2((float(k) - 2.0) * 6.0, 0.0), dot, C_DOT)
			1:
				for row in range(3):
					for col in range(3):
						draw_circle(c + Vector2((float(col) - 1.0) * 6.0, (float(row) - 1.0) * 5.0), dot, C_DOT)
			2:
				var fc: Color = FRONT_COLORS[clampi(front, 0, FRONT_COLORS.size() - 1)]
				for k in range(4):
					draw_circle(c + Vector2((float(k) - 1.5) * 6.0, -3.5), dot + 0.4, fc)
					draw_circle(c + Vector2((float(k) - 1.5) * 6.0, 3.5), dot, C_DOT)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var p: Vector2 = (ev as InputEventMouseMotion).position
		var hit := -1
		for i in range(CELLS):
			if _cell_rect(i).has_point(p):
				hit = i
		_show_tip(hit)
		if hit != _hover_cell:
			_hover_cell = hit
			queue_redraw()
		return
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var sm = _sm()
	if sm == null:
		return
	for i in range(CELLS):
		if _cell_rect(i).has_point(mb.position):
			var keys := [KEY_1, KEY_2, KEY_3]
			sm._formation_key(keys[i])
			_press_cell = i
			_press_left = PRESS_SEC
			AudioManager.play_ui("menu_button")
			queue_redraw()
			accept_event()
			return

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_show_tip(-1)
		if _hover_cell != -1:
			_hover_cell = -1
			queue_redraw()

## Подпись ячейки над окошком; -1 — спрятать
func _show_tip(i: int) -> void:
	if i == _tip_cell:
		return
	_tip_cell = i
	if i < 0:
		if _tip != null and is_instance_valid(_tip):
			_tip.visible = false
		return
	if _tip == null or not is_instance_valid(_tip):
		_tip = PanelContainer.new()
		_tip.name = "FormTip"
		_tip.top_level = true
		_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.04, 0.04, 0.08, 0.90)
		st.set_border_width_all(1)
		st.border_color = C_BORDER
		st.set_corner_radius_all(3)
		st.content_margin_left = 5; st.content_margin_right = 5
		st.content_margin_top = 1; st.content_margin_bottom = 1
		_tip.add_theme_stylebox_override("panel", st)
		_tip_lbl = Label.new()
		_tip_lbl.add_theme_font_size_override("font_size", TIP_FONT)
		_tip_lbl.add_theme_color_override("font_color", C_KEY)
		_tip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip.add_child(_tip_lbl)
		add_child(_tip)
	_tip_lbl.text = String(TIPS[i])
	_tip.reset_size()
	var sz: Vector2 = _tip.get_combined_minimum_size()
	var r := _cell_rect(i)
	var gx: float = global_position.x + r.get_center().x - sz.x * 0.5
	var vp: Vector2 = get_viewport_rect().size
	gx = clampf(gx, 2.0, maxf(vp.x - sz.x - 2.0, 2.0))
	_tip.global_position = Vector2(gx, global_position.y - sz.y - TIP_GAP)
	_tip.visible = true

## Текст видимой подписи (стенды)
func tip_text() -> String:
	if _tip == null or not is_instance_valid(_tip) or not _tip.visible:
		return ""
	return _tip_lbl.text
