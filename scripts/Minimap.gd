extends CanvasLayer
## ═══════════════════════════════════════════════════════════════════════════
## МИНИ-КАРТА (ТЗ 10.10.2026) — С ТЗ 20.10.2026 ЛЕВЫЙ НИЖНИЙ УГОЛ
## ═══════════════════════════════════════════════════════════════════════════
## ТЗ 20.10.2026, блок 2: карта переехала в левый нижний угол и стала на 30 %
## меньше (240×135 → 168×95). Она — левый «флаг» нижнего интерфейса: нижняя
## панель выделенного объекта стыкуется к её ПРАВОМУ краю (HUD._dock_bottom_panel
## читает dock_right_x()), над картой — окошко строя с кнопками-плитками
## ═══════════════════════════════════════════════════════════════════════════
## Что на ней: ландшафт (трава, река, брод, лес, жилы), граница карты, туман
## войны (неразведанное темнее, разведанное, но не видимое — притушено),
## точки бойцов по фракциям, квадраты построек и рамка того, что видит камера.
##
## ── ЦЕНА: ОДИН ВЫЗОВ ЯДРА РАЗ В UNIT_INTERVAL ─────────────────────────────
## Подложка запекается ОДИН раз (порциями строк по кадрам — is_water стоит
## дорого), лес перезапекается раз в TREES_INTERVAL. Точки бойцов НЕ обходят
## узлы: ArmyCore.MinimapPaint идёт по плотному списку живых строк, сам
## накладывает туман по своей маске и рисует метки построек из готового
## списка. Наружу — один массив RGBA на обновление. Список построек
## собирается обходом группы раз в BLD_INTERVAL. Рамка камеры — в _draw,
## четыре луча на землю за кадр.
##
## ── ВВОД ───────────────────────────────────────────────────────────────────
## ЛКМ (клик и протяжка) — камера в точку. ПКМ — приказ выделению
## (SelectionManager.order_at_world: марш или Attack-Move, если взведён [A]).
## ЛКМ при взведённом [A] — тоже Attack-Move, а не камера. Событие
## поглощается панелью (accept_event): в мир оно не проваливается, рамка
## выделения и приказ по полю не заводятся.

const _Opt := preload("res://scripts/perf_config.gd")
const _FormPanel := preload("res://scripts/FormationPanel.gd")
## Окошко строя над картой (ТЗ 11.10.2026): высота и зазор до карты
const FORM_H := 40.0
const FORM_GAP := 3.0
var formation_panel: Control = null

## Размер картинки = размер на экране (без растяжения): карта 450 × 253 м.
## ТЗ 20.10.2026: −30 % (было 240 × 135)
const MAP_W := 168
const MAP_H := 95
## Отступ от левой кромки экрана — та же ось, что у левого столбца HUD
## (PANEL_LEFT_MIN), от нижней — тот же зазор, что у нижней панели
const MARGIN := 6.0
const MARGIN_BOTTOM := 4.0
const BORDER := 3.0
## Зазор между картой и пристыкованной к ней нижней панелью
const DOCK_GAP := 6.0

## Правый край карты в координатах экрана + зазор: отсюда начинается нижняя
## панель выделенного (HUD). Считается из констант, а не из прямоугольника
## узла: панель раскладывается раньше, чем карта получает размер
static func dock_right_x() -> float:
	return MARGIN + float(MAP_W) + BORDER * 2.0 + DOCK_GAP

const UNIT_INTERVAL := 0.2
const BLD_INTERVAL := 1.0
const TREES_INTERVAL := 15.0
## Строк подложки за кадр при запекании
const BAKE_ROWS_PER_FRAME := 12

const C_GRASS := Color(0.29, 0.47, 0.21)
const C_GRASS2 := Color(0.25, 0.42, 0.18)
const C_WATER := Color(0.20, 0.40, 0.66)
const C_SAND := Color(0.66, 0.60, 0.40)
const C_TREE := Color(0.13, 0.29, 0.12)
const C_WALL_TREE := Color(0.08, 0.20, 0.08)
const C_GOLD := Color(0.95, 0.80, 0.25)
const C_STONE := Color(0.62, 0.62, 0.64)

## Палитра ядра: 0..3 — точки бойцов (игрок, красный, гоблины, нейтральные),
## 4..7 — постройки тех же сторон, 8 — ничейный рудник / пень
const PAL := [
	Color(0.30, 0.95, 0.45), Color(0.98, 0.20, 0.18), Color(1.00, 0.58, 0.12), Color(0.80, 0.80, 0.80),
	Color(0.35, 0.65, 1.00), Color(0.80, 0.10, 0.10), Color(0.85, 0.42, 0.05), Color(0.70, 0.70, 0.70),
	Color(0.62, 0.62, 0.62),
]
const PAL_NEUTRAL_BLD := 8

var _root: Control = null
var _img: Image = null
var _tex: ImageTexture = null
var _bg: PackedByteArray = PackedByteArray()      # земля без леса
var _bg_trees: PackedByteArray = PackedByteArray()  # земля + лес (подложка ядру)
var _pal: PackedByteArray = PackedByteArray()
var _marks: PackedFloat32Array = PackedFloat32Array()
var _half_x: float = 225.0
var _half_z: float = 126.5625
var _bake_row: int = 0
var _baked: bool = false
var _t_units: float = 0.0
var _t_bld: float = 0.0
var _t_trees: float = 0.0
var _lmb_drag: bool = false

## Стендам: число обновлений, цена последнего (мкс), точек на последнем
var updates: int = 0
var last_update_usec: int = 0
var last_dots: int = 0

func _ready() -> void:
	layer = 9                      # под HUD (10): плавающие окна HUD поверх
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m = GameManager.main
	if m != null:
		_half_x = float(m.MAP_HALF_X)
		_half_z = float(m.MAP_HALF_Z)
	_pal.resize(PAL.size() * 4)
	for i in range(PAL.size()):
		var c: Color = PAL[i]
		_pal[i * 4] = c.r8; _pal[i * 4 + 1] = c.g8; _pal[i * 4 + 2] = c.b8; _pal[i * 4 + 3] = 255
	_bg.resize(MAP_W * MAP_H * 4)
	_img = Image.create(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	_img.fill(C_GRASS)
	_tex = ImageTexture.create_from_image(_img)
	_root = Control.new()
	_root.name = "MinimapPanel"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.anchor_left = 0.0; _root.anchor_right = 0.0
	_root.anchor_top = 1.0; _root.anchor_bottom = 1.0
	var w: float = MAP_W + BORDER * 2.0
	var h: float = MAP_H + BORDER * 2.0
	_root.offset_left = MARGIN
	_root.offset_right = MARGIN + w
	_root.offset_bottom = -MARGIN_BOTTOM
	_root.offset_top = -MARGIN_BOTTOM - h
	_root.tooltip_text = ""
	_root.draw.connect(_on_draw)
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)
	# ОКОШКО СТРОЯ — ВПЛОТНУЮ НАД КАРТОЙ, той же ширины (ТЗ 11.10.2026)
	var fp := Control.new()
	fp.set_script(_FormPanel)
	fp.name = "FormationPanel"
	fp.anchor_left = 0.0; fp.anchor_right = 0.0
	fp.anchor_top = 1.0; fp.anchor_bottom = 1.0
	fp.offset_left = MARGIN
	fp.offset_right = MARGIN + w
	fp.offset_bottom = -MARGIN_BOTTOM - h - FORM_GAP
	fp.offset_top = -MARGIN_BOTTOM - h - FORM_GAP - FORM_H
	add_child(fp)
	formation_panel = fp

## Прямоугольник панели на экране (стендам и HUD)
func panel_rect() -> Rect2:
	return _root.get_global_rect() if _root != null else Rect2()

## Прямоугольник самой карты на экране (без рамки)
func map_rect() -> Rect2:
	var r := panel_rect()
	return Rect2(r.position + Vector2(BORDER, BORDER), Vector2(MAP_W, MAP_H))

func world_to_map(p: Vector3) -> Vector2:
	return Vector2((p.x + _half_x) / (2.0 * _half_x) * MAP_W,
		(p.z + _half_z) / (2.0 * _half_z) * MAP_H)

## Точка экрана → точка мира (y = 0)
func screen_to_world(sp: Vector2) -> Vector3:
	var r := map_rect()
	var u: float = clampf((sp.x - r.position.x) / r.size.x, 0.0, 1.0)
	var v: float = clampf((sp.y - r.position.y) / r.size.y, 0.0, 1.0)
	return Vector3(-_half_x + u * 2.0 * _half_x, 0.0, -_half_z + v * 2.0 * _half_z)

func image() -> Image:
	return _img

# ═════════════════════════════════════════════════════════════════════════════
# ПОДЛОЖКА
# ═════════════════════════════════════════════════════════════════════════════

func _bake_rows(count: int) -> void:
	var m = GameManager.main
	var has_water: bool = m != null and m.has_method("is_water")
	var has_sand: bool = m != null and m.has_method("ford_sand")
	var mx: float = 2.0 * _half_x / MAP_W
	var mz: float = 2.0 * _half_z / MAP_H
	var end: int = mini(_bake_row + count, MAP_H)
	for y in range(_bake_row, end):
		var wz: float = -_half_z + (y + 0.5) * mz
		for x in range(MAP_W):
			var wx: float = -_half_x + (x + 0.5) * mx
			var c: Color = C_GRASS if ((x / 6 + y / 6) & 1) == 0 else C_GRASS2
			if has_water and m.is_water(wx, wz):
				c = C_WATER
			elif has_sand and m.ford_sand(wx, wz):
				c = C_SAND
			var o: int = (y * MAP_W + x) * 4
			_bg[o] = c.r8; _bg[o + 1] = c.g8; _bg[o + 2] = c.b8; _bg[o + 3] = 255
	_bake_row = end
	if _bake_row >= MAP_H:
		_baked = true
		_bake_trees()

## Лес и жилы поверх земли. Рубка меняет лес медленно — раз в TREES_INTERVAL
func _bake_trees() -> void:
	_bg_trees = _bg.duplicate()
	var sx: float = MAP_W / (2.0 * _half_x)
	var sz: float = MAP_H / (2.0 * _half_z)
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if float(n.get("remaining")) <= 0.0:
			continue
		var p: Vector3 = (n as Node3D).position
		var px: int = int((p.x + _half_x) * sx)
		var py: int = int((p.z + _half_z) * sz)
		if px < 0 or py < 0 or px >= MAP_W or py >= MAP_H:
			continue
		var rt: int = int(n.get("resource_type"))
		var c: Color = C_TREE
		if rt == Constants.RESOURCE_GOLD:
			c = C_GOLD
		elif rt == Constants.RESOURCE_STONE:
			c = C_STONE
		elif int(n.get("forest_kind")) == 1:
			c = C_WALL_TREE
		var o: int = (py * MAP_W + px) * 4
		_bg_trees[o] = c.r8; _bg_trees[o + 1] = c.g8; _bg_trees[o + 2] = c.b8

# ═════════════════════════════════════════════════════════════════════════════
# ОБНОВЛЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not _baked:
		_bake_rows(BAKE_ROWS_PER_FRAME)
		if not _baked:
			return
		_collect_buildings()
		refresh()
	_t_trees += delta
	if _t_trees >= TREES_INTERVAL:
		_t_trees = 0.0
		_bake_trees()
	_t_bld += delta
	if _t_bld >= BLD_INTERVAL:
		_t_bld = 0.0
		_collect_buildings()
	_t_units += delta
	if _t_units >= UNIT_INTERVAL:
		_t_units = 0.0
		refresh()
	_root.queue_redraw()        # рамка камеры

## Метки построек: [x, z, полуразмер px, палитра]. Чужие — только разведанные
func _collect_buildings() -> void:
	_marks.resize(0)
	var fog = GameManager.fog
	var fog_on: bool = fog != null and is_instance_valid(fog) and fog.enabled
	var mpp: float = 2.0 * _half_x / MAP_W
	for b in get_tree().get_nodes_in_group("all_buildings"):
		if not is_instance_valid(b) or not (b is Node3D) or b.is_queued_for_deletion():
			continue
		if b.has_method("is_dead") and b.is_dead():
			continue
		var p: Vector3 = (b as Node3D).position
		var f: int = int(b.get("faction"))
		var ci: int = 4 + clampi(f, 0, 3)
		if b.has_method("is_neutral") and b.is_neutral():
			ci = PAL_NEUTRAL_BLD
		elif f == Constants.FACTION_NEUTRAL:
			ci = PAL_NEUTRAL_BLD
		if fog_on and f != Constants.FACTION_PLAYER and not fog.is_seen(p.x, p.z):
			continue
		var r: float = 3.0
		if b.has_method("ring_radius"):
			r = float(b.ring_radius())
		var half_px: float = clampf(r / mpp * 0.7, 1.0, 4.0)
		_marks.append(p.x); _marks.append(p.z)
		_marks.append(half_px); _marks.append(float(ci))

## Перерисовать точки (публичная — стенды зовут сразу, без ожидания такта)
func refresh() -> void:
	if not _baked or GameManager.army == null:
		return
	var t0: int = Time.get_ticks_usec()
	var fog = GameManager.fog
	var fog_on: bool = fog != null and is_instance_valid(fog) and fog.enabled and _Opt.fog_core
	var bg: PackedByteArray = _bg_trees if not _bg_trees.is_empty() else _bg
	var data: PackedByteArray = GameManager.army.minimap_paint(bg, MAP_W, MAP_H,
		_half_x, _half_z, fog_on, Constants.FACTION_PLAYER, _pal, _marks)
	_img.set_data(MAP_W, MAP_H, false, Image.FORMAT_RGBA8, data)
	_tex.update(_img)
	last_dots = GameManager.army.minimap_dots()
	last_update_usec = Time.get_ticks_usec() - t0
	updates += 1

## Принудительно пересобрать постройки (стендам)
func refresh_buildings() -> void:
	_collect_buildings()

## Дождаться запекания немедленно (стендам)
func bake_now() -> void:
	while not _baked:
		_bake_rows(MAP_H)
	_collect_buildings()
	refresh()

# ═════════════════════════════════════════════════════════════════════════════
# ОТРИСОВКА
# ═════════════════════════════════════════════════════════════════════════════

func _on_draw() -> void:
	var w: float = MAP_W + BORDER * 2.0
	var h: float = MAP_H + BORDER * 2.0
	_root.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.04, 0.04, 0.09, 0.94))
	_root.draw_texture(_tex, Vector2(BORDER, BORDER))
	_root.draw_rect(Rect2(Vector2(1, 1), Vector2(w - 2, h - 2)), Color(0.30, 0.25, 0.15), false, 2.0)
	_draw_camera_frame()

func _draw_camera_frame() -> void:
	var m = GameManager.main
	if m == null:
		return
	var cam: Camera3D = m.get("_camera")
	if cam == null or not is_instance_valid(cam):
		return
	var vs: Vector2 = cam.get_viewport().get_visible_rect().size
	var corners := [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(0, vs.y)]
	var pts := PackedVector2Array()
	var lo := Vector2(BORDER, BORDER)
	var hi := Vector2(BORDER + MAP_W, BORDER + MAP_H)
	for c in corners:
		var o: Vector3 = cam.project_ray_origin(c)
		var d: Vector3 = cam.project_ray_normal(c)
		if absf(d.y) < 1e-4:
			return
		var t: float = -o.y / d.y
		var g: Vector3 = o + d * t
		var mp: Vector2 = world_to_map(g) + lo
		pts.append(mp.clamp(lo, hi))
	pts.append(pts[0])
	_root.draw_polyline(pts, Color(1, 1, 1, 0.9), 1.0)

# ═════════════════════════════════════════════════════════════════════════════
# ВВОД
# ═════════════════════════════════════════════════════════════════════════════

func _on_gui_input(event: InputEvent) -> void:
	var sm = GameManager.main.selection_manager if GameManager.main != null else null
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var wp: Vector3 = screen_to_world(_root.get_global_transform() * mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if sm != null and is_instance_valid(sm) and bool(sm.attack_move_armed):
					sm.order_at_world(wp, true)
					_lmb_drag = false
				else:
					_lmb_drag = true
					_camera_to(wp)
			else:
				_lmb_drag = false
			_root.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and sm != null and is_instance_valid(sm):
				sm.order_at_world(wp, false)
			_root.accept_event()
	elif event is InputEventMouseMotion and _lmb_drag:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_lmb_drag = false
		else:
			_camera_to(screen_to_world(_root.get_global_transform() * mm.position))
		_root.accept_event()

func _camera_to(wp: Vector3) -> void:
	var m = GameManager.main
	if m == null:
		return
	var cam = m.get("_camera")
	if cam != null and is_instance_valid(cam) and cam.has_method("jump_to"):
		cam.jump_to(wp)
		_root.queue_redraw()
