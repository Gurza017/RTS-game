extends CanvasLayer

## ═══════════════════════════════════════════════════════════════════════════
## ЭКРАН ЗАГРУЗКИ ПАРТИИ (ТЗ 21.10.2026, редизайн меню)
## ═══════════════════════════════════════════════════════════════════════════
## Было: тёмная плашка с кольцом, которое на время сборки сцены замирало.
## Стало: полноэкранная иллюстрация (MenuArt), внизу — полоса прогресса в
## кованой раме с процентами, над ней совет, под ней — этап загрузки
## («Генерация рельефа…», «Размещение отрядов…»).
##
## СЛОЙ ВИСИТ НА КОРНЕ ДЕРЕВА, а не в меню: смена сцены сносит меню, а
## экран обязан пережить её и закрыться, только когда партия построена.
##
## ПРОГРЕСС — ЧЕСТНЫЙ ПО ЭТАПАМ. Ресурсы сцены грузятся в фоне
## (ResourceLoader.load_threaded_*, доля 0-30 %), дальше Main._ready строит
## мир СИНХРОННО и на каждом этапе зовёт stage(текст, доля). Кадров в это
## время нет, поэтому stage() сам перерисовывает экран
## (RenderingServer.force_draw, не чаще раза в FORCE_DRAW_MS) — полоса и
## надпись движутся и посреди синхронной сборки. В headless рисовать нечего,
## и force_draw не зовётся.
##
## Без открытого экрана stage()/finish() — пустые вызовы: стенды грузят
## Main.tscn напрямую, и им этот экран не нужен.
##
## Плавность: показанная доля догоняет целевую (_shown → _target), полоса
## не прыгает. finish() доводит до 100 %, ждёт мгновение и гасит экран.

const _MUI  := preload("res://scripts/ui/MedievalUI.gd")
const _Art  := preload("res://scripts/ui/MenuArt.gd")

## Советы — по механикам ЭТОЙ игры (не общие места)
const TIPS := [
	"Копейщики в стойке [S] держат удар конницы: кабаны о сомкнутый строй ломают разгон.",
	"Стройте дома: каждый поднимает лимит армии. С десятого дома цена растёт.",
	"Протяните ПКМ, чтобы задать ширину строя: фронт и глубину выбираете только вы.",
	"Лучникам нужна дистанция: держите их за копейщиками и стреляйте залпом.",
	"[F1] отправляет выделенные отряды в замок — лечиться и пополнять ряды.",
	"Колокол в панели крепости уводит всех рабочих под защиту стен.",
	"Отряд, потерявший много бойцов, может дрогнуть и побежать — берегите мораль.",
	"Монах лечит отряды рядом с собой; бегущих он не сопровождает.",
	"[A] — марш с боем: армия идёт к точке и вступает в бой со всем, что встретит.",
	"Улучшения кузницы дороги, но именно они решают затяжную войну.",
	"Броды — узкие места реки. Тот, кто держит брод, решает, где будет бой.",
	"Орда выходит волнами по часам. Встретьте её строем, а не толпой.",
	"Золото даёт рудник: захватите ничейный и поставьте охрану.",
	"Пробел или Z — пауза. На паузе можно отдавать приказы.",
]

const FORCE_DRAW_MS := 40
const TIP_SEC := 5.5
## Скорость догона полосы, доля в секунду (в обычных кадрах)
const FILL_SPEED := 0.9

static var _active = null

var _root: Control = null
var _bar: Control = null
var _pct: Label = null
var _status: Label = null
var _tip: Label = null
var _target: float = 0.0
var _shown: float = 0.0
var _tip_i: int = 0
var _tip_t: float = 0.0
var _finishing: bool = false
var _last_draw_ms: int = 0
var _born_ms: int = 0
var _rng := RandomNumberGenerator.new()

## Открыть экран (или вернуть уже открытый). Вешается на корень дерева
static func begin(tree: SceneTree, status: String = "Подготовка карты…"):
	if _active != null and is_instance_valid(_active):
		_active.set_status(status)
		return _active
	var ls = load("res://scripts/ui/LoadingScreen.gd").new()
	ls.name = "LoadingLayer"
	tree.root.add_child(ls)
	ls.set_status(status)
	_active = ls
	return ls

static func is_active() -> bool:
	return _active != null and is_instance_valid(_active)

static func current():
	return _active if is_active() else null

## Этап загрузки: подпись и доля (0..1). Доля только растёт
static func stage(text: String, frac: float) -> void:
	if not is_active():
		return
	_active.set_status(text)
	_active.set_target(frac)
	_active.pump()

## Конец сборки: довести до 100 % и плавно закрыть
static func finish() -> void:
	if not is_active():
		return
	_active.begin_finish()

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_born_ms = Time.get_ticks_msec()
	_rng.seed = Time.get_ticks_usec()
	_tip_i = _rng.randi() % TIPS.size()
	_build()

func _build() -> void:
	_root = Control.new()
	_root.name = "LoadingRoot"
	_root.theme = _MUI.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	# Подложка — непрозрачная: меню под экраном не видно ни на кадр
	var back := ColorRect.new()
	back.name = "LoadingBack"
	back.color = Color(0.03, 0.02, 0.03, 1.0)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)
	var backdrop: TextureRect = _Art.backdrop()
	if backdrop != null:
		backdrop.name = "LoadingBackdrop"
		_root.add_child(backdrop)
	var art = _Art.new()
	art.name = "LoadingArt"
	art.vignette = 0.35
	art.overlay_only = backdrop != null
	_root.add_child(art)
	# Затемнение низа под полосу и текст
	var shade := _Shade.new()
	shade.name = "LoadingShade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var title := _MUI.title_label("10 000 КОПЕЙЩИКОВ", 46)
	title.name = "LoadingTitle"
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40
	title.offset_bottom = 110
	_root.add_child(title)

	# Низ: совет — полоса — этап
	var bottom := VBoxContainer.new()
	bottom.name = "LoadingBottom"
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -34
	bottom.add_theme_constant_override("separation", 10)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom)

	_tip = Label.new()
	_tip.name = "LoadingTip"
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(760, 48)
	_tip.add_theme_font_override("font", _MUI.serif())
	_tip.add_theme_font_size_override("font_size", 18)
	_tip.add_theme_color_override("font_color", Color(0.98, 0.93, 0.78))
	_tip.add_theme_color_override("font_outline_color", _MUI.INK)
	_tip.add_theme_constant_override("outline_size", 4)
	_tip.text = "Совет: " + String(TIPS[_tip_i])
	bottom.add_child(_tip)

	_bar = _Bar.new()
	_bar.name = "LoadingBar"
	_bar.custom_minimum_size = Vector2(760, 40)
	bottom.add_child(_bar)
	_pct = Label.new()
	_pct.name = "LoadingPercent"
	_pct.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pct.add_theme_font_override("font", _MUI.serif())
	_pct.add_theme_font_size_override("font_size", 18)
	_pct.add_theme_color_override("font_color", Color(1.0, 0.97, 0.86))
	_pct.add_theme_color_override("font_outline_color", _MUI.INK)
	_pct.add_theme_constant_override("outline_size", 5)
	_pct.text = "0%"
	_bar.add_child(_pct)

	_status = Label.new()
	_status.name = "LoadingLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", _MUI.TEXT_DIM)
	_status.add_theme_color_override("font_outline_color", _MUI.INK)
	_status.add_theme_constant_override("outline_size", 3)
	_status.text = "Загрузка…"
	bottom.add_child(_status)
	_fit()
	get_viewport().size_changed.connect(_fit)

## Полоса — 60 % ширины экрана, но не уже 420 и не шире 900
func _fit() -> void:
	if _bar == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = clampf(vp.x * 0.6, minf(420.0, vp.x - 32.0), 900.0)
	_bar.custom_minimum_size.x = w
	_tip.custom_minimum_size.x = w

func set_status(text: String) -> void:
	if _status != null:
		_status.text = text

func set_target(frac: float) -> void:
	_target = clampf(maxf(_target, frac), 0.0, 1.0)

func progress() -> float:
	return _shown

func status_text() -> String:
	return _status.text if _status != null else ""

## Перерисовать экран посреди синхронной сборки. Показанная доля сразу
## подтягивается к цели (плавность — между этапами, а не внутри одного)
func pump() -> void:
	_shown = maxf(_shown, lerpf(_shown, _target, 0.85))
	_apply()
	if DisplayServer.get_name() == "headless":
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_draw_ms < FORCE_DRAW_MS:
		return
	_last_draw_ms = now
	RenderingServer.force_draw(true, 0.0)

func begin_finish() -> void:
	if _finishing:
		return
	_finishing = true
	set_target(1.0)
	set_status("Готово — к оружию!")

func _apply() -> void:
	if _bar != null:
		_bar.set("value", _shown)
		_bar.queue_redraw()
	if _pct != null:
		_pct.text = "%d%%" % int(floor(_shown * 100.0 + 0.0001))

func _process(delta: float) -> void:
	# Ожидание фоновой загрузки: полоса ползёт к цели, а не стоит
	_shown = move_toward(_shown, _target, delta * (FILL_SPEED * 2.5 if _finishing else FILL_SPEED))
	_apply()
	_tip_t += delta
	if _tip_t >= TIP_SEC and _tip != null:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = "Совет: " + String(TIPS[_tip_i])
	if _finishing and _shown >= 0.999 and _root != null and not _root.has_meta("fading"):
		_root.set_meta("fading", true)
		var tw := _root.create_tween()
		tw.tween_interval(0.25)
		tw.tween_property(_root, "modulate:a", 0.0, 0.45)
		tw.tween_callback(_close)
	# Страховка: экран не может висеть вечно (ошибка сборки сцены)
	if not _finishing and Time.get_ticks_msec() - _born_ms > 90000:
		begin_finish()

func _close() -> void:
	if _active == self:
		_active = null
	queue_free()

func _exit_tree() -> void:
	if _active == self:
		_active = null

## Полоса прогресса: кованая рама, утопленный жёлоб, бронзово-огненная
## заливка с бликом и бегущей искрой на кромке
class _Bar extends Control:
	var value: float = 0.0
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var mui = load("res://scripts/ui/MedievalUI.gd")
		var frame: StyleBox = mui.frame_style(0.0)
		draw_style_box(frame, r)
		var inner := r.grow(-15.0)
		draw_rect(inner, Color(0.05, 0.03, 0.02))
		var fw: float = inner.size.x * clampf(value, 0.0, 1.0)
		if fw > 1.0:
			var top := Color(1.0, 0.78, 0.36)
			var bot := Color(0.62, 0.30, 0.10)
			var fr := Rect2(inner.position, Vector2(fw, inner.size.y))
			draw_polygon(PackedVector2Array([fr.position, fr.position + Vector2(fr.size.x, 0),
				fr.end, fr.position + Vector2(0, fr.size.y)]),
				PackedColorArray([top, top, bot, bot]))
			draw_rect(Rect2(fr.position, Vector2(fw, 2.0)), Color(1.0, 0.93, 0.70, 0.8))
			var ex: float = fr.end.x
			draw_rect(Rect2(Vector2(ex - 3.0, fr.position.y), Vector2(3.0, fr.size.y)), Color(1.0, 0.95, 0.75))
		# деления по четвертям
		for i in range(1, 4):
			var x: float = inner.position.x + inner.size.x * float(i) / 4.0
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.35), 1.0)

class _Shade extends Control:
	func _draw() -> void:
		var h: float = size.y
		var w: float = size.x
		var y0: float = h * 0.62
		var c0 := Color(0, 0, 0, 0.0)
		var c1 := Color(0, 0, 0, 0.72)
		draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([c0, c0, c1, c1]))
