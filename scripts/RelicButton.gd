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
	tooltip_text = "Штандарт армии: %d / %d опыта\n" % [int(m.pool), int(_RCfgB.POOL_COST)] \
		+ "Заряжена — клик, затем ЛКМ по своему отряду:\n" \
		+ "+1 уровень отряду и реликвия-штандарт центральному бойцу\n" \
		+ "(аура %d м: атака, мораль, быстрее удар; скорость не меняет).\n" % int(_RCfgB.AURA_RADIUS) \
		+ "Повторно тому же отряду — реликвия +1 уровень. Павший носитель\n" \
		+ "роняет её: поднять может любой, и враг тоже. Esc/ПКМ — отмена"

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
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
	if frac > 0.0:
		draw_arc(c, r - 2.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, col, 4.0, true)
	var tex: Texture2D = GameManager.relic_mgr().relic_texture()
	if tex != null:
		var ts: Vector2 = tex.get_size()
		var h: float = SIZE * 0.70
		var w: float = h * ts.x / ts.y
		var mod := Color(1, 1, 1, 1) if frac >= 1.0 else Color(0.55, 0.55, 0.55, 0.9)
		draw_texture_rect(tex, Rect2(c - Vector2(w * 0.5, h * 0.5), Vector2(w, h)), false, mod)
	var charges: int = int(m.pool / _RCfgB.POOL_COST)
	if charges > 1:
		draw_string(ThemeDB.fallback_font, Vector2(SIZE - 16.0, SIZE - 4.0), "×%d" % charges,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)
