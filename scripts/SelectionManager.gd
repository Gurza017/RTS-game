extends Node
class_name SelectionManager

const DRAG_THRESHOLD        := 6.0
const GROUP_DOUBLE_TAP_TIME := 0.35
const DOUBLE_CLICK_TIME     := 0.35  # сек — окно двойного клика ЛКМ
# Строй «плечом к плечу»: интервалы вдвое меньше прежних (было 1.0 / 1.1)
const UNIT_SPACING          := 0.58  # метров между юнитами в шеренге
const ROW_DEPTH             := 0.62  # метров между рядами

## Combined Arms: базовый класс раскладки по эшелонам (копейщики/лучники/
## мечники). Грузится через preload — новый файл, без class_name (см. шапку
## Formations.gd)
const _Formations := preload("res://scripts/Formations.gd")
## Разрыв между эшелонами разных типов войск, метры. Заметно больше ROW_DEPTH
## между шеренгами ОДНОГО отряда — это разные тактические линии, а не просто
## соседний ряд
const RANK_GAP              := 2.2

var camera: Camera3D
var selected_units: Array  = []
## ── ЧЛЕНСТВО В ВЫДЕЛЕНИИ — СЛОВАРЁМ, А НЕ ПОИСКОМ ПО МАССИВУ ────────────────
## Тот же набор, что и selected_units, но ключами. Заведён ради одной строки:
## `_select_one` проверяла `node in selected_units`, то есть ЛИНЕЙНЫМ перебором
## всего выделения на каждого добавляемого бойца. Выделение армии целиком
## разворачивается по отрядам (клик по бойцу тянет весь его отряд), поэтому
## добавлений столько же, сколько бойцов, и стоимость выходила квадратичной.
## Замер (qa_fps, 2000 бойцов): разбор одного «выделить всё» — 1271 мс, то есть
## полторы секунды намертво замершей игры. Со словарём — единицы миллисекунд.
##
## Правится ТОЛЬКО вместе с selected_units и только в четырёх местах:
## _select_one, _purge_invalid, keep_only_type, _clear_selection
var _sel_set: Dictionary = {}
var drag_start: Vector2    = Vector2.ZERO
var drag_rect_ui: ColorRect

# ── Горячие группы ────────────────────────────────────────────────────────────
var _groups: Array = [[], [], [], [], [], [], [], [], []]
var _last_group_pressed:    int   = -1
var _last_group_press_time: float = 0.0

# ── ПКМ-формация ─────────────────────────────────────────────────────────────
var _rmb_down:         bool    = false
var _rmb_screen_start: Vector2 = Vector2.ZERO

## ── СВЁРТКА СОБЫТИЙ МЫШИ ДЛЯ ПРЕДПРОСМОТРА СТРОЯ ───────────────────────────
## Событий движения приходит больше, чем кадров; считать построение на каждое —
## чистая переплата. Копим последнюю точку и обрабатываем её раз в кадр
var _fp_pending: bool    = false
var _fp_mouse:   Vector2 = Vector2.ZERO
var _fp_last:    Vector2 = Vector2(-1e9, -1e9)
## Сдвиг курсора, меньше которого пересчитывать нечего: треугольники сместятся
## меньше чем на пиксель, а стоит это полного перестроения раскладки
const FP_MIN_MOVE_SQ := 4.0
var _rmb_world_start:  Vector3 = Vector3.ZERO

# ── Двойной ПКМ = БЕГ ────────────────────────────────────────────────────────
## Время и экранная точка предыдущего одиночного ПКМ-клика. Второй клик в то же
## место в пределах RMB_DOUBLE_TIME включает бег (Unit.sprinting).
## Проверяется именно ЭКРАННАЯ точка, а не мировая: камера за 0.35 с сдвинуться
## успевает, и мировые координаты двух кликов «в одно место» разъезжаются
var _last_rmb_time: float   = -10.0
var _last_rmb_pos:  Vector2 = Vector2(-9999.0, -9999.0)
## Окно двойного клика ПКМ. Отдельная константа, а не общий DOUBLE_CLICK_TIME:
## это разные жесты, и подкручивать их приходится независимо
const RMB_DOUBLE_TIME := 0.35
## Насколько далеко по экрану может уехать второй клик, чтобы он всё ещё считался
## двойным. Заметно больше DRAG_THRESHOLD — мышь при быстром двойном щелчке
## всегда чуть смещается
const RMB_DOUBLE_SLOP := 24.0

# ── Двойной клик ЛКМ ─────────────────────────────────────────────────────────
var _last_lmb_click_time: float = -10.0
var _last_lmb_click_id:   int   = 0
var _fp                        = null   # FormationPreview — нетипизировано, чтобы не зависеть от кэша классов

func setup(p_camera: Camera3D, p_drag_rect: ColorRect) -> void:
	camera       = p_camera
	drag_rect_ui = p_drag_rect
	drag_rect_ui.visible = false

	var cl := CanvasLayer.new()
	cl.layer = 9
	add_child(cl)
	# Грузим скрипт напрямую — не требует FormationPreview в global_script_class_cache
	var fp_script = load("res://scripts/FormationPreview.gd")
	if fp_script:
		_fp = fp_script.new()
		_fp.visible = false
		cl.add_child(_fp)

# ═════════════════════════════════════════════════════════════════════════════
# ЖЕСТ, НАЧАВШИЙСЯ НА ИНТЕРФЕЙСЕ, МИРА НЕ КАСАЕТСЯ
#
# ЗДЕСЬ БЫЛА ПРИЧИНА «панель кузницы закрывается от любого клика внутри неё».
#
# Нажатие по кнопке (вкладка, узел улучшения) или по фону панели ПОГЛОЩАЕТ сам
# интерфейс, и до _unhandled_input оно не доходит вовсе. А drag_start писался
# ТОЛЬКО там — то есть оставался от прошлого клика по карте, где-нибудь за
# полэкрана. Стоило до обработчика добраться отпусканию, как расстояние
# «начало → конец» оказывалось огромным, клик уезжал в ветку РАМКИ ВЫДЕЛЕНИЯ,
# а она проверяла «это интерфейс?» по НАЧАЛЬНОЙ точке — то есть по той самой
# точке на карте. Проверка честно отвечала «нет», рамка отрабатывала, выделение
# слетало, кузница закрывалась. Геометрия панели тут ни при чём: сравнивалась
# не та точка.
#
# Поэтому точка нажатия пишется в _input(): он получает событие ДО интерфейса и
# ничего не поглощает, так что drag_start верен ВСЕГДА — и когда нажали по
# карте, и когда по кнопке. Заодно сразу запоминаем, был ли сам нажим над
# интерфейсом: этого хватает, чтобы отбросить весь жест целиком, каким бы
# длинным ни оказалось «перетаскивание».
# ═════════════════════════════════════════════════════════════════════════════
## Нажатие ЛКМ пришлось на интерфейс — отпускание мира не касается
var _press_over_ui: bool = false

func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	# Никаких set_input_as_handled: здесь только ЗАПОМИНАЕМ, но не перехватываем
	if mb.button_index == MOUSE_BUTTON_LEFT:
		drag_start = mb.position
		_press_over_ui = _over_ui(mb.position)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_rmb_press_over_ui = _over_ui(mb.position)

## То же самое для ПКМ: приказ не отдаётся, если жест начался на панели
var _rmb_press_over_ui: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return

	# ── Горячие группы ────────────────────────────────────────────────────────
	if event is InputEventKey and event.pressed and not event.echo:
		var grp := _key_to_group_index(event.keycode)
		if grp >= 0:
			if event.ctrl_pressed:
				_save_group(grp)
			else:
				_recall_group(grp)
			get_viewport().set_input_as_handled()
			return

	# ── Мышь ─────────────────────────────────────────────────────────────────
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				pass          # точку нажатия уже записал _input() — см. шапку выше
			else:
				var drag_end: Vector2 = event.position
				# ЖЕСТ НАЧАЛСЯ НА ПАНЕЛИ — мира он не касается ни при каком
				# расстоянии. Именно этот случай и закрывал кузницу: нажатие
				# съедала кнопка, а отпускание уходило в ветку рамки
				if _press_over_ui:
					_press_over_ui = false
					drag_rect_ui.visible = false
					return
				if drag_start.distance_to(drag_end) < DRAG_THRESHOLD:
					_handle_single_click(drag_end, event.shift_pressed)
				else:
					_handle_box_select(drag_start, drag_end, event.shift_pressed)
				drag_rect_ui.visible = false

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# Нажатие на панели приказом не становится (см. _rmb_press_over_ui)
				if _rmb_press_over_ui:
					return
				_rmb_down = true
				_rmb_screen_start = event.position
				var hit := _screen_ray_hit(event.position, Constants.LAYER_GROUND)
				if hit.has("position"):
					_rmb_world_start = hit["position"]
					_rmb_world_start.y = 0.0
			else:
				if _fp:
					_fp.hide_all()
				# Отложенный пересчёт снимаем вместе с предпросмотром: иначе
				# движение мыши, пришедшее перед самым отпусканием, показало бы
				# треугольники уже ПОСЛЕ отданного приказа (см. _process)
				_fp_pending = false
				_fp_last = Vector2(-1e9, -1e9)
				# Жест ПКМ, начатый на панели, закончился — снимаем пометку.
				# Именно здесь, а не в _input: между нажатием и отпусканием
				# может прийти сколько угодно движений мыши
				if _rmb_press_over_ui:
					_rmb_press_over_ui = false
					_rmb_down = false
					return
				if _rmb_down:
					var drag_dist := _rmb_screen_start.distance_to(event.position)
					if drag_dist < DRAG_THRESHOLD:
						_handle_right_click(event.position, _consume_rmb_double(event.position))
					else:
						# Протяжка сбрасывает счётчик: строй по линии — это не
						# половина двойного клика
						_last_rmb_time = -10.0
						var hit := _screen_ray_hit(event.position, Constants.LAYER_GROUND)
						if hit.has("position"):
							var world_end: Vector3 = hit["position"]
							world_end.y = 0.0
							_execute_line_formation(_rmb_world_start, world_end)
				_rmb_down = false

	elif event is InputEventMouseMotion:
		# Рамку не рисуем вовсе, если жест начался на панели: иначе игрок,
		# промахнувшийся мимо кнопки кузницы, видит поверх интерфейса синий
		# прямоугольник выделения, который заведомо ничего не выделит
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _press_over_ui:
			if drag_start.distance_to(event.position) > DRAG_THRESHOLD:
				_update_drag_rect(drag_start, event.position)
		if _rmb_down and not selected_units.is_empty():
			if _rmb_screen_start.distance_to(event.position) > DRAG_THRESHOLD:
				# ── ПРЕДПРОСМОТР ПЕРЕСЧИТЫВАЕТСЯ НЕ ЧАЩЕ КАДРА ─────────────
				# Здесь стоял прямой вызов _update_formation_preview. События
				# движения мыши приходят С ЧАСТОТОЙ ОПРОСА МЫШИ, а не кадра —
				# это 5-10 событий на кадр на обычной мыши и вдвое больше на
				# игровой. Каждый пересчёт — луч в физику, слот на КАЖДОГО
				# выделенного бойца, unproject_position на каждого и две
				# примитивы отрисовки на каждого. На большом выделении это
				# тысячи вызовов в кадр, отсюда и падение с 60 до 29 к/с.
				# Теперь запоминаем последнюю точку, а считаем один раз за
				# кадр (см. _process): промежуточные положения курсора всё
				# равно никто не увидел бы — кадр между ними не рисовался
				_fp_pending = true
				_fp_mouse = event.position

# ─── Горячие группы ──────────────────────────────────────────────────────────

func _key_to_group_index(keycode: Key) -> int:
	match keycode:
		KEY_1: return 0
		KEY_2: return 1
		KEY_3: return 2
		KEY_4: return 3
		KEY_5: return 4
		KEY_6: return 5
		KEY_7: return 6
		KEY_8: return 7
		KEY_9: return 8
	return -1

func _save_group(idx: int) -> void:
	_purge_invalid()
	_groups[idx] = selected_units.duplicate()

func _recall_group(idx: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var double_tap := (_last_group_pressed == idx) and (now - _last_group_press_time < GROUP_DOUBLE_TAP_TIME)
	_last_group_pressed    = idx
	_last_group_press_time = now

	var grp: Array = _groups[idx].filter(func(u): return is_instance_valid(u))
	_groups[idx] = grp
	if grp.is_empty():
		return

	_clear_selection()
	for u in grp:
		_select(u)
	GameManager.on_selection_changed(selected_units)

	if double_tap and camera is RTSCamera:
		var center := Vector3.ZERO
		for u in grp:
			center += (u as Node3D).global_position
		center /= float(grp.size())
		(camera as RTSCamera).pan_to(center)

# ─── Формация по линии ────────────────────────────────────────────────────────

# Вычисляет слоты в мировом пространстве по нарисованной линии.
# Длина линии определяет количество юнитов в шеренге → количество рядов.
func _compute_line_slots(line_start: Vector3, line_end: Vector3, count: int) -> Array:
	var slots: Array = []
	if count == 0:
		return slots
	var line_vec    := line_end - line_start
	var line_length := line_vec.length()
	if line_length < 0.1:
		return slots
	var line_dir    := line_vec.normalized()
	# Юниты стоят на линии и смотрят "вперёд" (перпендикулярно линии, по часовой)
	var facing_dir  := Vector3(line_dir.z, 0.0, -line_dir.x)
	# Ряды располагаются ПОЗАДИ фронтальной линии (противоположно facing_dir)
	var row_offset  := -facing_dir

	# Сколько юнитов помещается в один ряд при данной длине линии
	var per_row := maxi(1, int(floor(line_length / UNIT_SPACING)))
	var rows    := int(ceil(float(count) / float(per_row)))

	for i in range(count):
		var rank := i / per_row
		var file := i % per_row
		var t    := (float(file) + 0.5) / float(per_row)
		var pos  := line_start.lerp(line_end, t) + row_offset * (rank * ROW_DEPTH)
		pos.y    = 0.0
		slots.append(pos)

	return slots

# ─────────────────────────────────────────────────────────────────────────────
# ФОРМАЦИЯ НЕСКОЛЬКИХ ОТРЯДОВ: СЕКЦИИ («КИРПИЧИКИ»)
#
# Раньше растянутая линия заполнялась ОДНИМ сплошным потоком: слот i получал
# боец i, и три отряда по 20 человек перемешивались между собой — в одной
# шеренге стояли вперемешку копейщики двух разных отрядов и лучники.
# Теперь линия сначала делится на блоки по числу бойцов в каждом отряде, между
# блоками оставляется зазор BLOCK_GAP, и КАЖДЫЙ отряд строится внутри своего
# блока по прежним правилам (шеренги по UNIT_SPACING, ряды по ROW_DEPTH).
# Порядок блоков — порядок появления отрядов в выделении, поэтому построение
# повторяемо: один и тот же набор отрядов встаёт одинаково.
# ─────────────────────────────────────────────────────────────────────────────
## Просвет между блоками соседних отрядов, метры
const BLOCK_GAP := 1.6

## Разбить выделение на отряды, сохранив порядок первого появления.
## Ключ 0 — бойцы вне реестра отрядов, они образуют один общий блок
func _split_into_blocks(movable: Array) -> Array:
	var order: Array = []
	var by_squad: Dictionary = {}
	for u in movable:
		var sid: int = (u as Unit).squad_id if u is Unit else 0
		if not by_squad.has(sid):
			order.append(sid)
			by_squad[sid] = []
		(by_squad[sid] as Array).append(u)
	var blocks: Array = []
	for sid in order:
		blocks.append(by_squad[sid])
	return blocks

## ── ОТРЯДЫ РАСКЛАДЫВАЮТСЯ ПО ФАКТИЧЕСКОМУ ПОЛОЖЕНИЮ, А НЕ ПО ПОРЯДКУ ВЫДЕЛЕНИЯ
##
## _split_into_blocks отдаёт отряды в порядке ПОЯВЛЕНИЯ в выделении, то есть по
## сути в порядке реестра. Раздавать участки линии по нему нельзя: отряд,
## стоящий на левом фланге, легко получал участок справа и шёл туда НАСКВОЗЬ
## через соседей. На пяти отрядах это выглядит как перетасовка всей группы по
## дороге — жалоба «отряды меняются местами и линия фронта переворачивается».
##
## Сортируем по проекции центра масс на направление линии: кто стоял левее,
## тот левее и встанет. Векторы движения отрядов выходят параллельными, и пути
## не пересекаются по построению.
##
## Тот же приём уже применён к сетке групп (_issue_group_grid_move); здесь он
## был пропущен, а это ВТОРАЯ из двух веток, которыми игрок двигает группу
func _blocks_along(movable: Array, dir: Vector3) -> Array:
	var blocks := _split_into_blocks(movable)
	if blocks.size() < 2:
		return blocks
	var keys: Array = []
	for b in blocks:
		var arr: Array = b
		var c := Vector3.ZERO
		for u in arr:
			c += (u as Node3D).global_position
		c /= float(maxi(arr.size(), 1))
		keys.append(c.dot(dir))
	var idx: Array = []
	for i in range(blocks.size()):
		idx.append(i)
	idx.sort_custom(func(a, b): return float(keys[a]) < float(keys[b]))
	var out: Array = []
	for i in idx:
		out.append(blocks[int(i)])
	return out

# ─────────────────────────────────────────────────────────────────────────────
# ТОПОЛОГИЧЕСКИЙ ПОРЯДОК: КТО ГДЕ СТОЯЛ, ТОТ ТАМ И ВСТАНЕТ
#
# Слоты раскладываются строго по индексу (см. _compute_line_slots: сначала вся
# передняя шеренга слева направо, потом следующая), а бойцы приходили в этот
# список в порядке РЕЕСТРА ОТРЯДА. Связи с тем, кто где реально стоит, не было
# никакой: боец из последней шеренги мог получить слот в первой и шёл туда
# СКВОЗЬ весь свой отряд, а передний уходил назад. Отряд выворачивался
# наизнанку на каждом растягивании строя.
#
# Здесь состав пересортировывается ровно в порядке слотов: сперва по ГЛУБИНЕ
# (кто ближе к фронту — тот раньше), потом внутри каждой шеренги по её ширине
# слева направо. Пути перестают пересекаться: строй просто сдвигается.
#
# Сортировка двухуровневая, а не по одному ключу: единый ключ вида
# «глубина × K + ширина» требует знать масштаб обеих осей и разваливается на
# косом строе, а разбиение на шеренги по per_row — ровно та же нарезка,
# которой пользуется сама раскладка.
# ─────────────────────────────────────────────────────────────────────────────
func _topo_order(block: Array, line_dir: Vector3, facing_dir: Vector3,
		per_row: int) -> Array:
	var ordered: Array = block.duplicate()
	# По глубине: стоящий ближе к фронту (больше проекция на facing) — раньше
	ordered.sort_custom(func(a, b):
		return (a as Node3D).global_position.dot(facing_dir) \
			> (b as Node3D).global_position.dot(facing_dir))
	# Внутри каждой шеренги — слева направо вдоль линии
	var n: int = ordered.size()
	var step: int = maxi(per_row, 1)
	var i := 0
	while i < n:
		var last: int = mini(i + step, n)
		var rank_slice: Array = ordered.slice(i, last)
		rank_slice.sort_custom(func(a, b):
			return (a as Node3D).global_position.dot(line_dir) \
				< (b as Node3D).global_position.dot(line_dir))
		for k in range(rank_slice.size()):
			ordered[i + k] = rank_slice[k]
		i = last
	return ordered

## Слоты для всего выделения: линия делится на секции по отрядам.
## Возвращает {"slots": …, "rows": …, "flat": …} — все три в ОДНОМ порядке.
## `flat` обязателен к использованию вместо исходного movable: состав внутри
## каждого блока пересортирован по фактическому положению (см. _topo_order)
func _block_formation_slots(line_start: Vector3, line_end: Vector3, movable: Array) -> Dictionary:
	var out := {"slots": [], "rows": [], "flat": []}
	var line_vec := line_end - line_start
	var total_len := line_vec.length()
	if total_len < 0.1:
		return out
	var dir := line_vec / total_len
	# Участки линии раздаются СЛЕВА НАПРАВО по фактическому положению отрядов,
	# а не по порядку выделения (см. _blocks_along) — иначе отряды идут к своим
	# местам крест-накрест
	var blocks := _blocks_along(movable, dir)
	if blocks.is_empty():
		return out
	var total_men := 0
	for b in blocks:
		total_men += (b as Array).size()
	if total_men <= 0:
		return out
	# Зазоры съедают часть линии, но не больше её половины — иначе при пяти
	# отрядах на короткой линии на сами шеренги ничего бы не осталось
	var gaps: float = minf(float(blocks.size() - 1) * BLOCK_GAP, total_len * 0.5)
	var usable: float = total_len - gaps
	var gap_each: float = gaps / maxf(float(blocks.size() - 1), 1.0)

	# Фронт строя — перпендикуляр к линии, та же формула, что в _compute_line_slots
	var facing := Vector3(dir.z, 0.0, -dir.x)
	var cursor := 0.0
	for b in blocks:
		var block: Array = b
		var share: float = usable * float(block.size()) / float(total_men)
		var b_start := line_start + dir * cursor
		var b_end   := line_start + dir * (cursor + share)
		var slots := _compute_line_slots(b_start, b_end, block.size())
		var per_row := maxi(1, int(floor(share / UNIT_SPACING)))
		# Состав выстраивается в том же порядке, в каком лежат слоты
		var ordered: Array = _topo_order(block, dir, facing, per_row)
		for i in range(ordered.size()):
			out["slots"].append(slots[i] if i < slots.size() else b_start)
			out["rows"].append(i / per_row)
			out["flat"].append(ordered[i])
		cursor += share + gap_each
	return out

## Порядок бойцов, соответствующий раскладке по блокам
func _blocks_flat(movable: Array) -> Array:
	var flat: Array = []
	for b in _split_into_blocks(movable):
		flat.append_array(b as Array)
	return flat

# ─────────────────────────────────────────────────────────────────────────────
# COMBINED ARMS: РАСКЛАДКА ПО ЭШЕЛОНАМ (см. Formations.gd)
#
# Смешанное по типам выделение (копейщики + лучники + мечники) больше не
# делится на секции ВДОЛЬ линии (это осталось для однотипного выделения) —
# вместо этого линия целиком отдаётся под ПЕРВЫЙ эшелон (копейщики), а
# следующие типы строятся ТОЙ ЖЕ секционной раскладкой (свои отряды —
# side-by-side по ширине линии), но сдвинутой назад вдоль facing_dir на
# глубину предыдущего эшелона + RANK_GAP. Получается сетка в глубину: по
# фронту — секции отрядов одного типа, по глубине — сами типы войск.
# ─────────────────────────────────────────────────────────────────────────────
## Возвращает {"slots": Array[Vector3], "rows": Array[int], "flat": Array}
## — все три в одном и том же порядке (rows/slots[i] относятся к flat[i])
func _layered_formation_slots(line_start: Vector3, line_end: Vector3, movable: Array) -> Dictionary:
	var out := {"slots": [], "rows": [], "flat": []}
	var line_vec := line_end - line_start
	var line_dir := Vector3.FORWARD
	if line_vec.length() > 0.001:
		line_dir = line_vec.normalized()
	var facing_dir := Vector3(line_dir.z, 0.0, -line_dir.x)
	var back_dir    := -facing_dir
	var depth_cursor := 0.0
	# ── ТЫЛОВЫЕ ЭШЕЛОНЫ ЦЕНТРИРУЮТСЯ ПО ФРОНТУ ПЕРВОГО ──────────────────────
	# Здесь КАЖДЫЙ эшелон получал ЛИНИЮ ЦЕЛИКОМ. Для копейщиков это правильно —
	# они и есть фронт, — а вот один отряд лучников, растянутый на ту же ширину,
	# что и четыре отряда копейщиков, ложится в ОДНУ шеренгу длиной во весь строй.
	# На экране это тонкая нитка позади блоков (видно на скриншоте предпросмотра),
	# и она же — источник жалобы «лучники встают с краю»: боец такой шеренги
	# оказывается где угодно, только не за спиной у своих.
	#
	# Ширина тылового эшелона теперь берётся по ЕГО численности относительно
	# первого, а сам он центрируется на середине фронта. Двадцать лучников за
	# восемьюдесятью копейщиками занимают четверть фронта ровно посередине и
	# ложатся в столько же шеренг, сколько и копейщики, — то есть плотность
	# строя у всех эшелонов одинаковая, а не «фронт блоками, тыл ниткой».
	var front_men := 0
	var mid_line := (line_start + line_end) * 0.5
	var full_len: float = line_vec.length()
	for bucket in _Formations.group_by_rank(movable):
		var b: Array = bucket
		if b.is_empty():
			continue
		if front_men == 0:
			front_men = b.size()
		var seg_start := line_start
		var seg_end   := line_end
		if b.size() < front_men and full_len > 0.001:
			# Не уже, чем нужно на пару человек в шеренге: иначе крошечный
			# эшелон вырождается в колонну по одному, а при совсем малой длине
			# _block_formation_slots вернул бы пустой план и эшелон пропал бы
			var want: float = full_len * float(b.size()) / float(front_men)
			var half: float = maxf(want, UNIT_SPACING * 3.0) * 0.5
			half = minf(half, full_len * 0.5)
			seg_start = mid_line - line_dir * half
			seg_end   = mid_line + line_dir * half
		var plan := _block_formation_slots(seg_start, seg_end, b)
		var b_slots: Array = plan["slots"]
		var b_rows: Array  = plan["rows"]
		if b_slots.size() < b.size():
			continue    # линия слишком короткая для этого эшелона — пропускаем его целиком
		var max_row := 0
		for r in b_rows:
			max_row = maxi(max_row, int(r))
		# Порядок бойцов — из плана, а не исходный: внутри каждого блока состав
		# пересортирован по фактическому положению (см. _topo_order)
		var b_flat: Array = plan["flat"]
		for i in range(b_flat.size()):
			out["slots"].append((b_slots[i] as Vector3) + back_dir * depth_cursor)
			out["rows"].append(b_rows[i])
			out["flat"].append(b_flat[i])
		# Следующий эшелон встаёт позади уже занятой этим эшелоном глубины
		depth_cursor += float(max_row + 1) * ROW_DEPTH + RANK_GAP
	return out

func _movable_count() -> int:
	var c := 0
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("command_move"):
			c += 1
	return c

## Свёрнутые события мыши обрабатываются здесь — ровно один пересчёт за кадр
## отрисовки, и только если курсор реально сместился
func _process(_delta: float) -> void:
	if not _fp_pending:
		return
	_fp_pending = false
	if _fp_mouse.distance_squared_to(_fp_last) < FP_MIN_MOVE_SQ:
		return
	_fp_last = _fp_mouse
	_update_formation_preview(_fp_mouse)

func _update_formation_preview(mouse_screen: Vector2) -> void:
	if _fp == null:
		return
	var cnt := _movable_count()
	if cnt == 0 or _rmb_world_start == Vector3.ZERO:
		_fp.hide_all()
		return
	var hit := _screen_ray_hit(mouse_screen, Constants.LAYER_GROUND)
	if not hit.has("position"):
		_fp.hide_all()
		return

	var world_end: Vector3 = hit["position"]
	world_end.y = 0.0
	var line_vec   := world_end - _rmb_world_start
	if line_vec.length() < 0.1:
		_fp.hide_all()
		return

	# Превью считается ТОЙ ЖЕ раскладкой, что и сам приказ (секции или эшелоны
	# Combined Arms, см. _execute_line_formation), — иначе игрок видел бы одно
	# построение при растягивании и другое по отпусканию кнопки
	var movable: Array = []
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("command_move"):
			movable.append(u)
	var slots: Array
	if _Formations.is_mixed(movable):
		slots = _layered_formation_slots(_rmb_world_start, world_end, movable)["slots"]
	else:
		slots = _block_formation_slots(_rmb_world_start, world_end, movable)["slots"]

	var line_dir   := line_vec.normalized()
	var facing_dir := Vector3(line_dir.z, 0.0, -line_dir.x)
	var mid_world  := (_rmb_world_start + world_end) * 0.5
	var elev       := Vector3(0, 0.5, 0)
	var mid_scr    := camera.unproject_position(mid_world + elev)
	var face_scr   := camera.unproject_position(mid_world + facing_dir * 2.0 + elev)
	var facing_angle := (face_scr - mid_scr).angle() + PI * 0.5

	var screen_slots: Array = []
	for slot in slots:
		screen_slots.append(camera.unproject_position((slot as Vector3) + elev))

	_fp.show_formation(screen_slots, facing_angle, _rmb_screen_start, mouse_screen)

# ═════════════════════════════════════════════════════════════════════════════
# РАСТЯНУТАЯ ЛИНИЯ = МАРШЕВЫЙ ШАГ СТРОЕМ.
#
# Два режима движения различаются ИМЕННО ЖЕСТОМ, а не составом выделения:
#   • короткий ПКМ по карте  → БЫСТРЫЙ ШАГ: отряд идёт полным ходом, строй
#     держит вольно (см. _issue_formation_move);
#   • ПКМ с растягиванием    → МАРШ: игрок сам нарисовал фронт, отряд идёт
#     шагом и держит нарисованный «кирпичик» на всём пути.
#
# РАНЬШЕ БЫЛО НАОБОРОТ: короткий клик уводил отряд маршем на половине скорости,
# а растянутая линия — бегом врассыпную. То есть жест, которым игрок задаёт
# строгий строй, этот строй как раз и ломал.
# ═════════════════════════════════════════════════════════════════════════════
## ── НИ ОДИН ВЫДЕЛЕННЫЙ БОЕЦ НЕ ОСТАЁТСЯ БЕЗ ПРИКАЗА ────────────────────────
## Жалоба владельца: из пяти выделенных отрядов один игнорирует команду и
## остаётся стоять с жёлтым кольцом. Так и было — и не в одном месте:
##   • эшелон, которому не хватило длины нарисованной линии, ПРОПУСКАЛСЯ
##     целиком (_layered_formation_slots, ветка `continue`);
##   • бойцы вне реестра отрядов (sid = 0) выпадали из сетки блоков
##     (_issue_group_grid_move) — а она при этом возвращала «приказ отдан»;
##   • несовпадение числа мест и бойцов ОТМЕНЯЛО ВЕСЬ приказ разом
##     (`if slots.size() < flat.size(): return`).
##
## Ловить каждый случай по отдельности бессмысленно — их будет ещё, раскладка
## строя живёт и меняется. Здесь стоит ОБЩАЯ страховка: кто не получил места в
## плане, идёт в точку приказа обычным шагом. Это хуже строя, но несравнимо
## лучше «отряд не пошёл».
##
## Возвращает, скольких пришлось спасать: число читает стенд qa_orders — в
## норме оно ноль, и рост означает, что раскладка снова начала терять людей
var last_unordered: int = 0

func _order_leftovers(movable: Array, served: Array, fallback: Vector3,
		course: Vector3, run: bool = false) -> int:
	var got: Dictionary = {}
	for u in served:
		got[u] = true
	var n := 0
	for u in movable:
		if got.has(u) or not is_instance_valid(u):
			continue
		u.command_move(fallback, false, course, false, true, run)
		n += 1
	last_unordered = n
	return n

func _execute_line_formation(line_start: Vector3, line_end: Vector3) -> void:
	var movable: Array = []
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("command_move"):
			movable.append(u)
	if movable.is_empty():
		return
	if (line_end - line_start).length() < 0.2:
		_issue_formation_move(line_start)   # клич подаст она сама
		return
	_order_battle_cry(movable)   # марш по линии — такой же приказ, те же правила
	var line_vec := line_end - line_start
	var flat: Array
	var slots: Array
	var rows: Array
	if _Formations.is_mixed(movable):
		# COMBINED ARMS: смешанное выделение строится эшелонами по типу войск
		# (копейщики / лучники / мечники), см. _layered_formation_slots
		var lplan := _layered_formation_slots(line_start, line_end, movable)
		flat  = lplan["flat"]
		slots = lplan["slots"]
		rows  = lplan["rows"]
	else:
		# СЕКЦИИ: каждый отряд получает свой участок линии и не перемешивается
		# с соседями (см. _block_formation_slots).
		# ПОРЯДОК БОЙЦОВ БЕРЁТСЯ ИЗ ПЛАНА, а не из _blocks_flat: внутри блока
		# состав пересортирован по фактическому положению, и старый «порядок
		# реестра» рассыпал бы соответствие слотов бойцам
		var plan := _block_formation_slots(line_start, line_end, movable)
		flat  = plan["flat"]
		slots = plan["slots"]
		rows  = plan["rows"]
	# ── НЕСОВПАДЕНИЕ ЧИСЛА МЕСТ НЕ ОТМЕНЯЕТ ПРИКАЗ ──────────────────────────
	# Здесь стоял `return`: план вышел короче состава — и НИКТО никуда не шёл,
	# включая отряды, места которым посчитались нормально. Теперь обслуживаем
	# столько, сколько мест есть, а остальных подбирает страховка ниже
	var served: int = mini(slots.size(), flat.size())
	# ЕДИНЫЙ ФРОНТ: направление взгляда считается ОДИН РАЗ по нарисованной
	# линии и выдаётся всем бойцам. Тот же вектор рисует превью формации,
	# так что отряд встаёт ровно так, как игрок видел при растягивании
	var line_dir   := line_vec.normalized()
	var facing_dir := Vector3(line_dir.z, 0.0, -line_dir.x)
	for i in range(served):
		# Ряд в фаланге — для порядка построения (глубина в шеренге)
		flat[i].formation_row = int(rows[i])
		# player_order = true: приказ игрока непрерываем FORCED_MOVE_SEC секунд
		# (см. Unit._move_lock) — иначе отряд, которому дали приказ вплотную к
		# врагу, перехватывается на первом же шаге и с места не уходит
		flat[i].command_move(slots[i], true, facing_dir, false, true)
	# РАЗМЕТКА ОСТАЁТСЯ ЗА ОТРЯДОМ. Благодаря ей после потерь можно сомкнуть
	# ряды: выживших пересаживают на первые места списка, и задняя шеренга
	# переходит вперёд на места павших (см. GameManager.squad_close_ranks)
	_remember_formation(flat, slots, facing_dir, true)
	# ── И НИКОГО НЕ ЗАБЫЛИ ──────────────────────────────────────────────────
	# Эшелон, которому не хватило длины линии, план пропускает целиком; после
	# этого его бойцы стояли с жёлтым кольцом и без приказа
	_order_leftovers(movable, flat.slice(0, served), line_start, facing_dir)

# ─── Существующие методы ─────────────────────────────────────────────────────

func _update_drag_rect(a: Vector2, b: Vector2) -> void:
	drag_rect_ui.visible = true
	var pos  := Vector2(min(a.x, b.x), min(a.y, b.y))
	var size := Vector2(abs(a.x - b.x), abs(a.y - b.y))
	drag_rect_ui.position = pos
	drag_rect_ui.size     = size

func _screen_ray_hit(screen_pos: Vector2, mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to   := from + camera.project_ray_normal(screen_pos) * 1000.0
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	return space_state.intersect_ray(query)

# ─────────────────────────────────────────────────────────────────────────────
# ПРИОРИТЕТ КЛИКА: ЧТО ИМЕННО ПОД КУРСОРОМ
#
# Коллайдер дерева — цилиндр радиусом 1.35 и ВЫСОТОЙ 4.8 м: он обязан покрывать
# всю крону, иначе по кроне нельзя кликнуть. Но камера смотрит сверху под углом,
# поэтому этот столб воздуха накрывает и землю ПЕРЕД деревом: клик по жиле
# золота, лежащей у ствола, ловил дерево, и рабочий уходил рубить лес.
#
# intersect_ray возвращает только БЛИЖАЙШЕЕ попадание, поэтому идём по лучу
# насквозь (исключая уже найденные тела) и собираем всех кандидатов, пока не
# упрёмся в землю.
#
# ПРАВИЛО ВЫБОРА: побеждает тот, чьё ОСНОВАНИЕ ближе к точке, куда курсор
# показывает НА ЗЕМЛЕ. Луч продолжается до плоскости грунта, и дальше сравнение
# идёт в плане (по x/z), а не в воздухе:
#   • клик по жиле у ствола — точка земли лежит на жиле, она и выигрывает;
#   • клик по стволу — точка земли уходит за дерево, но комель всё равно ближе
#     к ней, чем соседняя жила, поэтому дерево остаётся выбранным;
#   • клик по верхушке крупного здания — из дистанции вычитается его габарит,
#     поэтому замок не проигрывает случайному бойцу у стены.
# При равенстве (обе дистанции внутри собственного габарита) выигрывает МЕНЬШИЙ
# объект: мелкая цель точнее, по крупной попасть проще в другом месте.
# ─────────────────────────────────────────────────────────────────────────────
const PICK_MAX_HITS := 8
## Разница счёта, ниже которой кандидаты считаются равными
const PICK_TIE := 0.01

## Высота туловища спрайта бойца: на неё считается поправка ракурса
const UNIT_BODY_H := 1.0
## Потолок поправки: при совсем пологой камере боец не должен «расползаться»
const UNIT_PICK_MAX := 2.5

## Габарит объекта в плане: на столько «прощается» промах по земле.
## unit_slack — габарит бойца с поправкой на наклон камеры (см. _pick_at)
func _pick_radius(node, unit_slack: float = 0.35) -> float:
	if node is Building:
		var s: Vector3 = (node as Building).build_size
		return maxf(s.x, s.z) * 0.5
	if node is ResourceNode:
		var rn := node as ResourceNode
		if rn.resource_type == Constants.RESOURCE_WOOD:
			# СТВОЛ, А НЕ КРОНА. Здесь стояло 1.35 — радиус прежнего коллайдера
			# «на весь спрайт». Кликбокс дерева ужат до ствола (см.
			# ResourceNode.TRUNK_PICK_RADIUS), и наземный круг обязан поехать
			# следом: иначе луч не находил бы дерево, а счёт всё равно считался
			# бы по кроне, и правило «что подсвечено, то и приказано» разъехалось
			return ResourceNode.TRUNK_PICK_RADIUS
		return 0.85 * rn.size_scale
	return unit_slack    # боец

## Кого предпочесть при РАВНОМ счёте. Боец важнее жилы и здания: маски
## столкновений везде нулевые, поэтому бойцы свободно стоят на габарите
## построек, и клик по бойцу внутри коробки замка обязан выбрать бойца.
##
## ── РУДА ВЫШЕ ДЕРЕВА, И ЭТО ПОЛОВИНА ЛЕЧЕНИЯ «КЛИКНУЛ ПО КАМНЮ — ПОШЁЛ РУБИТЬ
## СОСЕДНИЙ КУСТ» ────────────────────────────────────────────────────────────
## Раньше вся растительность и вся руда делили один ранг 1, и спор решался
## размером: «по мелкой цели попасть труднее, она и важнее». Звучит логично, но
## работает наоборот, потому что радиусы тут несравнимы. У дерева наземный круг
## ФИКСИРОВАННЫЕ 1.35 м (коллайдер накрывает всю крону, чтобы ПКМ по любой ветке
## отправлял рубить), а у куска руды — 0.85 × size_scale, то есть от 1.36 м у
## крупного самородка до 0.53 м у мелкого осколка. Осколок формально «мельче» и
## выигрывал спор — но лишь тогда, когда вообще до него доходило: чаще счёт у
## дерева оказывался строго лучше, потому что его круг вчетверо больше по
## площади и накрывал точку земли целиком.
##
## В лесу и на опушке — а руду генератор ставит именно там — куст или ствол
## почти всегда стоит в паре метров от кучи. Поэтому: если под курсором есть и
## руда, и дерево, выигрывает руда. Обратный случай безопасен — целясь в ствол
## посреди леса, игрок просто не наводит курсор на самородок, и руда в
## кандидатах не появляется вовсе
func _pick_rank(node) -> int:
	if node is Unit:
		return 0
	if node is ResourceNode:
		return 1 if (node as ResourceNode).resource_type != Constants.RESOURCE_WOOD else 2
	return 3

## Разбор клика: {"target": Node|null, "position": Vector3}
## position — точка на земле (или на ближайшем теле, если земли на луче нет)
func _pick_at(screen_pos: Vector2, mask: int) -> Dictionary:
	var out := {"target": null, "position": Vector3.ZERO}
	if camera == null:
		return out
	var from  := camera.project_ray_origin(screen_pos)
	var dirn  := camera.project_ray_normal(screen_pos)
	var to    := from + dirn * 1000.0
	var space := camera.get_world_3d().direct_space_state
	# ── БОЙЦЫ ИЩУТСЯ ПО СЕТКЕ, А НЕ ЛУЧОМ ───────────────────────────────────
	# У юнитов больше нет физических тел (см. шапку Unit.gd): тело стоило
	# 5.7 мкс на бойца в кадр только за факт своего существования в
	# PhysicsServer3D, при том что маски в проекте нулевые и ни с чем оно не
	# сталкивалось. Единственным его потребителем был вот этот клик.
	#
	# Правило выбора при этом не меняется НИ НА ЙОТУ: победитель и раньше
	# определялся расстоянием ОТ ОСНОВАНИЯ объекта ДО ТОЧКИ ЗЕМЛИ под курсором
	# (переменная ground ниже), а не геометрией коллайдера — луч лишь собирал
	# список кандидатов. Теперь тот же список для бойцов даёт запрос к
	# пространственной сетке вокруг той же самой точки земли.
	var want_units: bool = (mask & Constants.LAYER_UNITS) != 0
	var ray_mask: int = mask & ~Constants.LAYER_UNITS
	var exclude: Array[RID] = []
	var best: Node = null
	var best_score := INF
	var best_radius := INF
	var best_rank := 99
	var first_pos := Vector3.ZERO
	var have_pos  := false
	# ТОЧКА ЗЕМЛИ ПОД КУРСОРОМ. Грунт плоский (get_terrain_height = 0), поэтому
	# пересечение с плоскостью y=0 считается аналитически и не зависит от того,
	# перехватил ли луч коллайдер земли
	var ground := Vector2(INF, INF)
	if absf(dirn.y) > 1e-4:
		var t_g: float = -from.y / dirn.y
		if t_g > 0.0:
			var gp := from + dirn * t_g
			ground = Vector2(gp.x, gp.z)
	# ПОПРАВКА РАКУРСА ДЛЯ БОЙЦА. Курсор наводят на туловище спрайта, а точка
	# земли под курсором уходит за спину бойца на высота/tan(наклон камеры) —
	# при пологой камере это больше метра. Без поправки боец всегда проигрывал
	# зданию, на габарите которого стоит
	var unit_slack := 0.35
	if absf(dirn.y) > 1e-4:
		var lean: float = Vector2(dirn.x, dirn.z).length() / absf(dirn.y)
		unit_slack = minf(0.35 + UNIT_BODY_H * lean, UNIT_PICK_MAX)
	# КАНДИДАТЫ СОБИРАЮТСЯ, ПОТОМ ОЦЕНИВАЮТСЯ. Раньше это был один цикл по лучу;
	# теперь источников два (луч — для построек, жил и грунта; сетка — для
	# бойцов), а правило выбора для них общее и должно применяться одинаково
	var cands: Array = []
	if ray_mask != 0:
		for _i in range(PICK_MAX_HITS):
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.collision_mask = ray_mask
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if not hit.has("collider"):
				break
			if hit.has("rid"):
				exclude.append(hit["rid"])
			var hit_pos: Vector3 = hit["position"]
			if not have_pos:
				first_pos = hit_pos
				have_pos  = true
			var node = _resolve_node(hit["collider"])
			if node == null:
				# Земля (или что-то, что не является сущностью игры) — за ней
				# смотреть нечего: всё дальше по лучу скрыто грунтом
				out["position"] = hit_pos
				break
			cands.append(node)
	# Бойцы вокруг точки земли под курсором. Радиус берётся с запасом на
	# поправку ракурса (unit_slack): при пологой камере точка земли уходит
	# за спину бойца больше чем на метр
	if want_units and ground.x != INF:
		var gp3 := Vector3(ground.x, 0.0, ground.y)
		for n in GameManager.unit_grid.query_radius(gp3, unit_slack + 1.0):
			var u := n as Unit
			if u != null and not u.is_dead():
				cands.append(u)
	# ── ПОПРАВКА РАКУРСА ДЛЯ ЖИЛ: ВТОРАЯ ПОЛОВИНА ЛЕЧЕНИЯ ───────────────────
	# Она же — корень жалобы «показал на камень, рабочий ушёл к соседнему кусту».
	# Точка земли под курсором лежит НЕ под тем, на что смотрит игрок: наведясь
	# на кусок руды, нарисованный на высоте ~0.6-1.0 м, при камере в 45° игрок
	# получает точку земли примерно на столько же метров ЗА камнем. У бойцов эта
	# поправка есть с самого начала (unit_slack выше), у жил её не было вовсе —
	# то есть кусок руды систематически «проигрывал» самому себе, а выигрывал тот,
	# кто стоял на метр дальше от камеры. В редколесье это почти всегда дерево.
	#
	# Поправка СДВИГАЕТ круг цели, а не раздувает его (как unit_slack). Это
	# принципиально: раздутый круг сделал бы мелкий осколок «жирной» целью и он
	# начал бы перехватывать клики соседей — ровно та болезнь, от которой лечим
	var lean := Vector2.ZERO
	if absf(dirn.y) > 1e-4:
		lean = Vector2(dirn.x, dirn.z) / absf(dirn.y)
	for node in cands:
		var np: Vector3 = (node as Node3D).global_position
		var radius: float = _pick_radius(node, unit_slack)
		var rank: int = _pick_rank(node)
		var anchor := Vector2(np.x, np.z)
		if node is ResourceNode:
			var bh: float = (node as ResourceNode).pick_body_h()
			if bh > 0.0:
				anchor += lean * bh
		var score: float
		if ground.x == INF:
			# Луч смотрит горизонтально — сравниваем по расстоянию до основания
			score = maxf(np.distance_to(first_pos if have_pos else from) - radius, 0.0)
		else:
			score = maxf(anchor.distance_to(ground) - radius, 0.0)
		var better := false
		if score < best_score - PICK_TIE:
			better = true
		elif absf(score - best_score) <= PICK_TIE:
			# Счёт равный (оба накрывают точку земли): решает сначала ранг,
			# затем размер — по мелкой цели попасть труднее, она и важнее
			better = rank < best_rank or (rank == best_rank and radius < best_radius)
		if better:
			best_score = score
			best_radius = radius
			best_rank = rank
			best = node
	out["target"] = best
	if (out["position"] as Vector3) == Vector3.ZERO:
		if ground.x != INF:
			out["position"] = Vector3(ground.x, 0.0, ground.y)
		elif have_pos:
			out["position"] = first_pos
	return out

func _resolve_node(collider: Node):
	var n := collider
	while n:
		if n is Unit or n is Building or n is ResourceNode:
			return n
		# Руина — не Building (намеренно: ни групп, ни здоровья, ни выделения),
		# но по ней отдаётся приказ «отстроить заново», поэтому кликом она
		# обязана распознаваться. Ловим по группе — типа у неё нет
		if n.is_in_group("ruins"):
			return n
		n = n.get_parent()
	return null

## КЛИК ПО ИНТЕРФЕЙСУ — НЕ КЛИК ПО МИРУ.
## Панель здания закрывается строго по Escape или по клику ВНЕ её границ
## (заказ владельца), поэтому любой клик, попавший в видимую панель, до разбора
## мира не доходит вовсе. Проверка геометрическая: одного лишь MOUSE_FILTER_STOP
## на кнопках мало — в панели полно прозрачных мест (подписи и иконки стоят в
## IGNORE, просветы между кнопками не накрыты ничем, у кузницы сетка узлов и
## холст стрелок — голые Control), и попадание МИМО кнопки проваливалось в мир,
## где читалось как «клик по пустой земле» и снимало выделение.
## См. HUD.point_over_ui — там же список панелей, которые держат фокус
func _over_ui(screen_pos: Vector2) -> bool:
	var hud = GameManager.main.hud if GameManager.main != null else null
	if hud == null or not is_instance_valid(hud):
		return false
	return hud.point_over_ui(screen_pos)

## Публичное снятие выделения (Escape в HUD). Внутренний _clear_selection
## только гасит кольца — панель об этом узнаёт из on_selection_changed
func clear_selection() -> void:
	_clear_selection()
	GameManager.on_selection_changed(selected_units)

func _handle_single_click(screen_pos: Vector2, additive: bool) -> void:
	if _over_ui(screen_pos):
		return
	_purge_invalid()
	if not additive:
		_clear_selection()
	var pick := _pick_at(screen_pos, Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS)
	if pick["target"] != null:
		var target = pick["target"]
		# ── ЛКМ ПО ЧУЖОМУ ОТРЯДУ = РАЗВЕДКА, А НЕ ВЫДЕЛЕНИЕ ─────────────────
		# Раньше эта ветка просто не срабатывала: условие требовало своей
		# фракции, и клик по врагу молча снимал выделение. Теперь он открывает
		# карточку — но чужой отряд по-прежнему НЕ попадает в selected_units
		# (см. recon_units), поэтому приказать ему ничего нельзя
		if target is Unit and (target as Unit).faction != Constants.FACTION_PLAYER:
			if _visible_to_player(target as Unit) and not additive:
				# ПОРЯДОК ВАЖЕН: сначала уведомляем о (пустом) своём выделении,
				# и только потом открываем разведку. Наоборот — карточка гасла
				# бы в тот же кадр, потому что show_selection сам сбрасывает
				# разведку (свои и чужие в панели не смешиваются)
				GameManager.on_selection_changed(selected_units)
				_set_recon(target as Unit)
				return
		elif (target is Unit or target is Building) and target.faction == Constants.FACTION_PLAYER:
			# Двойной клик по юниту → выделить всех однотипных юнитов на экране
			var now := Time.get_ticks_msec() / 1000.0
			var is_double: bool = target is Unit \
				and target.get_instance_id() == _last_lmb_click_id \
				and (now - _last_lmb_click_time) < DOUBLE_CLICK_TIME
			_last_lmb_click_time = now
			_last_lmb_click_id   = target.get_instance_id()
			if is_double:
				_select_same_type_on_screen(target)
			else:
				_select(target)
	# Досюда доходит только клик, который разведкой НЕ стал (на чужой ветке
	# стоит return): значит открытую карточку пора закрыть
	clear_recon()
	GameManager.on_selection_changed(selected_units)

# Двойной клик: выделить ВСЕ ОТРЯДЫ этого типа, видимые сейчас на экране
func _select_same_type_on_screen(sample: Unit) -> void:
	var vp_rect := get_viewport().get_visible_rect()
	for u in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(u):
			continue
		if u.get_script() != sample.get_script():
			continue
		var world_pos: Vector3 = (u as Node3D).global_position
		if camera.is_position_behind(world_pos):
			continue
		if vp_rect.has_point(camera.unproject_position(world_pos)):
			_select(u)   # развернётся на весь отряд

# РАМКОЙ ВЫДЕЛЯЮТСЯ ОТРЯДЫ ЦЕЛИКОМ. Достаточно задеть рамкой одного бойца —
# в выделение попадёт весь его отряд, даже если остальные вне рамки. Иначе
# игрок отрывал бы от отряда «хвост» и управлял бы половинками строя
func _handle_box_select(a: Vector2, b: Vector2, additive: bool) -> void:
	# ПРАВИЛО ДЕРЖИТСЯ НА ОБОИХ КОНЦАХ РАМКИ. Начало на панели — это промах
	# мимо кнопки; конец на панели — это отпускание внутри «безопасной зоны», и
	# по требованию владельца оно тоже поглощается, а не сбрасывает выделение.
	#
	# Проверка продублирована здесь НАМЕРЕННО, хотя жест уже отсекается по
	# _press_over_ui в _unhandled_input: та защита знает, где было НАЖАТИЕ, а эта
	# работает от самих координат и потому верна при любом способе вызова
	# (в том числе из стендов). Дублирование дешёвое — два сравнения на клик
	if _over_ui(a) or _over_ui(b):
		return
	_purge_invalid()
	if not additive:
		_clear_selection()
	var rect := Rect2(Vector2(min(a.x, b.x), min(a.y, b.y)), Vector2(abs(a.x - b.x), abs(a.y - b.y)))
	var touched: Array = []      # id уже развёрнутых отрядов
	for unit in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(unit):
			continue
		if camera.is_position_behind(unit.global_position):
			continue
		var screen_pos := camera.unproject_position(unit.global_position)
		if not rect.has_point(screen_pos):
			continue
		var sid: int = (unit as Unit).squad_id
		if sid > 0:
			if sid in touched:
				continue     # отряд уже целиком в выделении
			touched.append(sid)
		_select(unit)
	GameManager.on_selection_changed(selected_units)

func _purge_invalid() -> void:
	selected_units = selected_units.filter(func(u): return is_instance_valid(u))
	_sel_rebuild()

## Пересобрать словарь членства по массиву. Зовётся везде, где массив меняют
## не добавлением одного узла
func _sel_rebuild() -> void:
	_sel_set.clear()
	for u in selected_units:
		_sel_set[u] = true

# ─────────────────────────────────────────────────────────────────────────────
# ВЫДЕЛЕНИЕ ИДЁТ ОТРЯДАМИ, А НЕ БОЙЦАМИ
# Клик по одному солдату разворачивается на ВЕСЬ его отряд; выделить половину
# отряда невозможно в принципе. Поэтому и все приказы ниже по файлу
# (формация, марш, атака) всегда получает отряд целиком.
# Здания отрядами не являются — они выделяются поштучно, как и раньше.
# ─────────────────────────────────────────────────────────────────────────────

## Выделить ОТРЯД, в котором состоит node (для здания — само здание)
func _select(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not (node is Unit):
		_select_one(node)
		return
	for m in GameManager.squad_of(node):
		_select_one(m)

## Один узел в выделение, без разворачивания на отряд
func _select_one(node) -> void:
	if _sel_set.has(node):
		return
	selected_units.append(node)
	_sel_set[node] = true
	if node.has_method("set_selected"):
		node.set_selected(true)

## ФИЛЬТР ПО ТИПУ: оставить в выделении только отряды указанного типа.
## Дёргается кнопкой на панели мульти-выбора (левый нижний угол)
func keep_only_type(unit_id: String) -> void:
	_purge_invalid()
	var keep: Array = []
	for u in selected_units:
		if not (u is Unit):
			# ПОСТРОЙКА В СМЕШАННОМ ВЫДЕЛЕНИИ (её добавляет Shift+клик по зданию)
			# фильтром по типу войск выбрасывается — и обязана погасить кольцо.
			# Раньше здесь стоял голый continue: здание пропадало из
			# selected_units, а подсветка под ним продолжала гореть
			if u.has_method("set_selected"):
				u.set_selected(false)
			continue
		var sid: int = (u as Unit).squad_id
		var t: String = GameManager.squad_type(sid) if sid > 0 else (u as Unit).stat_id
		if t == unit_id:
			keep.append(u)
		elif u.has_method("set_selected"):
			u.set_selected(false)
	selected_units = keep
	_sel_rebuild()
	GameManager.on_selection_changed(selected_units)

## Идентификаторы выделенных отрядов (для панелей интерфейса)
func selected_squad_ids() -> Array:
	var ids: Array = []
	for u in selected_units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var sid: int = (u as Unit).squad_id
		if sid > 0 and not (sid in ids):
			ids.append(sid)
	return ids

# ═════════════════════════════════════════════════════════════════════════════
# РАЗВЕДКА: ЧУЖОЙ ОТРЯД ПОД ЛУПОЙ
# ═════════════════════════════════════════════════════════════════════════════
# Разведанный отряд ЖИВЁТ В ОТДЕЛЬНОМ СПИСКЕ, а не в selected_units, и это не
# вопрос чистоты. _handle_right_click перебирает именно selected_units и раздаёт
# приказы всем, кто там лежит: вражеский боец в этом списке получил бы от игрока
# приказ идти и атаковать. Отдельный список делает это невозможным по
# построению, а не по внимательности.
#
# Кольца на разведанном отряде тоже не зажигаются: set_selected — это признак
# «мой и мною управляется». Чужой строй подсвечивается красным по НАВЕДЕНИЮ
# (см. enemy_squad_under_cursor), и это ровно тот же ответ, что даёт прицел
var recon_units: Array = []

## Виден ли этот боец игроку ПРЯМО СЕЙЧАС. Разведать можно только то, что
## видно: без этой проверки игрок тыкал бы в чёрное поле и получал полную
## карточку отряда, которого «не видит» — то есть находил бы армию противника
## наощупь, мимо всей механики тумана.
## Туман выключен (стенды, fog.enabled = false) — видно всё, как и раньше
func _visible_to_player(u: Unit) -> bool:
	if u == null or not is_instance_valid(u) or u.is_dead():
		return false
	var fog = GameManager.fog
	if fog == null or not is_instance_valid(fog) or not fog.enabled:
		return true
	return fog.is_lit(u.global_position.x, u.global_position.z)

## Чужой боец под курсором. `use_zone` — разрешить попадание «рядом со строем»
## (тот же SQUAD_CLICK_REACH, что у приказа атаки): игрок целится в отряд, а не
## в пиксель модели
func enemy_unit_under_cursor(screen_pos: Vector2, use_zone: bool = true) -> Unit:
	if camera == null or _over_ui(screen_pos):
		return null
	var pick := _pick_at(screen_pos, Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS
		| Constants.LAYER_GROUND)
	var u := pick["target"] as Unit
	if u != null and u.faction != Constants.FACTION_PLAYER and _visible_to_player(u):
		return u
	# Луч нашёл грунт или своего — но рядом может стоять чужой строй
	if not use_zone:
		return null
	if u != null and u.faction != Constants.FACTION_PLAYER:
		return null      # чужой есть, но он в тумане — «рядом» искать нечего
	var pos: Vector3 = pick["position"]
	if pos == Vector3.ZERO and pick["target"] == null:
		return null
	var best: Unit = null
	var best_d := SQUAD_CLICK_REACH * SQUAD_CLICK_REACH
	for n in GameManager.unit_grid.query_radius(pos, SQUAD_CLICK_REACH):
		var e := n as Unit
		if e == null or e.faction == Constants.FACTION_PLAYER:
			continue
		if not _visible_to_player(e):
			continue
		var dx: float = e.global_position.x - pos.x
		var dz: float = e.global_position.z - pos.z
		var d2: float = dx * dx + dz * dz
		if d2 < best_d:
			best_d = d2
			best   = e
	return best

## Весь чужой ОТРЯД под курсором — это он получает красные кольца и это он
## открывается в карточке разведки. Отряд, а не боец: игра оперирует отрядами,
## и подсветить одного человека из двадцати было бы враньём о том, что будет
## атаковано
func enemy_squad_under_cursor(screen_pos: Vector2, use_zone: bool = true) -> Array:
	var u := enemy_unit_under_cursor(screen_pos, use_zone)
	if u == null:
		return []
	if u.squad_id <= 0:
		return [u]
	var out: Array = []
	for m in GameManager.squad_members(u.squad_id):
		var mu := m as Unit
		# В отряде подсвечиваем только тех, кого игрок реально видит: половина
		# строя может стоять в тумане, и рисовать кольца по ней — выдавать
		# позицию, которую туман как раз и скрывает
		if mu != null and _visible_to_player(mu):
			out.append(mu)
	return out if not out.is_empty() else [u]

## Открыть карточку разведки по этому бойцу. Возвращает false, если разведывать
## нечего (никого не видно) — тогда клик остаётся обычным «снять выделение»
func _set_recon(u: Unit) -> bool:
	var members: Array = []
	if u.squad_id > 0:
		for m in GameManager.squad_members(u.squad_id):
			var mu := m as Unit
			if mu != null and not mu.is_dead():
				members.append(mu)
	if members.is_empty():
		members = [u]
	recon_units = members
	GameManager.on_recon_changed(recon_units)
	return true

## Закрыть карточку разведки. Отдельного уведомления HUD НЕ шлёт намеренно:
## любой путь, который снимает разведку, тут же выделяет что-то своё (или
## пустоту), а show_selection гасит карточку сам. Лишний вызов заставил бы
## панель пересобираться дважды за клик
func clear_recon() -> void:
	recon_units.clear()

func _clear_selection() -> void:
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("set_selected"):
			u.set_selected(false)
	selected_units.clear()
	_sel_set.clear()

## ЭТО ВТОРОЙ ПКМ ПОДРЯД В ТУ ЖЕ ТОЧКУ?
## Возвращает true и СБРАСЫВАЕТ счётчик (тройной клик — это не два бега подряд,
## а бег и новый первый клик). Иначе запоминает клик как первый половину пары
func _consume_rmb_double(screen_pos: Vector2) -> bool:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var is_double: bool = (now - _last_rmb_time) <= RMB_DOUBLE_TIME \
		and _last_rmb_pos.distance_to(screen_pos) <= RMB_DOUBLE_SLOP
	if is_double:
		_last_rmb_time = -10.0
		_last_rmb_pos  = Vector2(-9999.0, -9999.0)
		return true
	_last_rmb_time = now
	_last_rmb_pos  = screen_pos
	return false

# ═════════════════════════════════════════════════════════════════════════════
# УМНЫЙ КЛИК ПО ЛЕСУ (SMART TARGETING)
#
# Дерево — цель ТОЛЬКО для рабочего. Коллайдер дерева это цилиндр радиусом 1.35
# и высотой 4.8 м, а камера смотрит под 45°, поэтому столб кроны накрывает
# несколько метров земли ПЕРЕД стволом. Для отряда солдат это означало, что
# приказ «иди/атакуй вон туда» в редколесье регулярно упирался в дерево и
# полностью пропадал: команды «рубить» у мечника нет, и клик просто съедался.
#
# Решение — на уровне МАСКИ ЛУЧА, а не фильтра результата: если в выделении нет
# ни одного рабочего, LAYER_RESOURCES в маску вообще не попадает. Тогда луч
# проходит сквозь лес до грунта, точка земли считается за деревьями, и вокруг
# неё как обычно ищутся вражеские бойцы (см. _pick_at) — то есть клик по врагу,
# стоящему В ЛЕСУ, работает сам собой, без отдельной ветки.
# ═════════════════════════════════════════════════════════════════════════════

## Есть ли в выделении хоть один рабочий. Публичная — её же читает
## Main._update_hover_cursor, чтобы курсор сбора показывался ровно тогда, когда
## клик по дереву действительно что-то сделает
func selection_has_worker() -> bool:
	for u in selected_units:
		if is_instance_valid(u) and u is Worker:
			return true
	return false

## НАСКОЛЬКО ДАЛЕКО ОТ ТОЧКИ КЛИКА ИЩЕТСЯ ЧУЖОЙ СТРОЙ.
## Отряд — это блок из 20 моделей с интервалом 0.5 м, то есть плотное пятно
## примерно 3×2 м. Игрок целится «в отряд», а не в пиксель конкретного бойца, и
## промах на полтора шага мимо силуэта обязан читаться как приказ атаки, а не
## как «идите в эту точку» (после чего отряд встаёт вплотную к врагу и ждёт).
## 2.5 м = расстояние до соседней модели в блоке с запасом; больше брать нельзя,
## иначе станет невозможно приказать «встать РЯДОМ с врагом»
const SQUAD_CLICK_REACH := 2.5

## Ближайший ЧУЖОЙ боец в пределах SQUAD_CLICK_REACH от точки на земле.
## null — рядом никого, клик остаётся приказом движения.
## Через сетку, а не через группы: у юнитов нет физических тел (см. Unit.gd),
## и это тот же источник кандидатов, которым пользуется _pick_at
func _enemy_in_squad_zone(ground: Vector3) -> Node3D:
	if not _selection_can_attack():
		return null
	var best: Node3D = null
	var best_d := SQUAD_CLICK_REACH * SQUAD_CLICK_REACH
	for n in GameManager.unit_grid.query_radius(ground, SQUAD_CLICK_REACH):
		var u := n as Unit
		if u == null or u.is_dead() or u.faction == Constants.FACTION_PLAYER:
			continue
		var dx: float = u.global_position.x - ground.x
		var dz: float = u.global_position.z - ground.z
		var d2: float = dx * dx + dz * dz
		if d2 < best_d:
			best_d = d2
			best   = u
	return best

## Есть ли в выделении хоть кто-то, кому приказ атаки вообще осмыслен.
## Артель рабочих не должна превращать клик у вражеского строя в самоубийство:
## у рабочего attack_damage = 0, приказ атаки для него бессмыслен
func _selection_can_attack() -> bool:
	for u in selected_units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		if (u as Unit).attack_damage > 0.0:
			return true
	return false

# ═════════════════════════════════════════════════════════════════════════════
# ЖЁСТКИЙ КОНТРАКТ: ЧТО ПОДСВЕЧЕНО — ТО И БУДЕТ ПРИКАЗАНО
# ═════════════════════════════════════════════════════════════════════════════
# Маска луча вынесена в отдельную функцию, а разбор наведения ходит РОВНО ТЕМ ЖЕ
# путём, что и разбор клика. Это не «красиво», это единственный способ дать
# обещание, которое нельзя нарушить: подсветка не «показывает похожее», она
# показывает результат того же самого вычисления, которое через мгновение
# выполнит правая кнопка. Раньше наведение (Main._update_hover_cursor) и приказ
# (_handle_right_click) собирали свои маски по отдельности, и они уже разошлись:
# у наведения LAYER_RESOURCES стоял ВСЕГДА, а у приказа — только при выделенном
# рабочем. Курсор обещал сбор там, где клик его не отдавал
func order_pick_mask() -> int:
	# LAYER_RUINS есть ТОЛЬКО в маске правого клика: руину нельзя выделить,
	# но по ней можно отдать приказ «отстроить» (см. _try_rebuild_ruin)
	#
	# LAYER_RESOURCES — ТОЛЬКО ЕСЛИ В ВЫДЕЛЕНИИ ЕСТЬ РАБОЧИЙ (см. selection_has_worker)
	var mask: int = Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS \
		| Constants.LAYER_RUINS | Constants.LAYER_GROUND
	if selection_has_worker():
		mask |= Constants.LAYER_RESOURCES
	return mask

## КЛИК В ПРОСВЕТ МЕЖДУ САМОРОДКАМИ — ЭТО КЛИК ПО КУЧЕ.
## Куча руды это полтора десятка кусков с промежутками, и целится игрок в
## МЕСТОРОЖДЕНИЕ (именно его и обводит зелёный овал), а не в конкретный
## самородок. Попадание мимо куска, но внутрь овала, обязано читаться как приказ
## на добычу, иначе «клик по подсвеченной зоне» — обещание, которое сдерживается
## через раз. Это ровно тот же приём, которым промах мимо модели у вражеского
## строя читается как приказ атаки (см. _enemy_in_squad_zone).
##
## Проверка — ЭЛЛИПС, ровно тот, что рисует подсветка (Main.res_clusters.half
## плюс CLUSTER_RIM): обещание и его исполнение обязаны совпадать по геометрии,
## а не «примерно». Куч на карте пара десятков, цикл дешёвый и крутится только
## по наведению и по клику
func _ore_in_cluster_zone(ground: Vector3) -> ResourceNode:
	var m = GameManager.main
	if m == null or not is_instance_valid(m):
		return null
	var rim: float = m.CLUSTER_RIM
	var best_cid: int = 0
	var best_norm := 1.0
	for cid in m.res_clusters:
		var info: Dictionary = m.res_clusters[cid]
		var c: Vector3 = info["center"]
		var half: Vector2 = info["half"]
		var ax: float = half.x + rim
		var az: float = half.y + rim
		if ax <= 0.0 or az <= 0.0:
			continue
		var nx: float = (ground.x - c.x) / ax
		var nz: float = (ground.z - c.z) / az
		var norm: float = nx * nx + nz * nz
		# Внутри овала и ближе к его середине, чем предыдущий кандидат: кучи
		# могут перекрываться краями, и выигрывает та, в которую целились
		if norm <= 1.0 and norm < best_norm:
			best_norm = norm
			best_cid  = int(cid)
	if best_cid == 0:
		return null
	# Отдаём БЛИЖАЙШИЙ К ТОЧКЕ КЛИКА живой кусок этой кучи, а не первый попавшийся:
	# бригада должна начать с того края, куда показали
	var best: ResourceNode = null
	var best_d2 := INF
	for n in GameManager.nodes_in_group_cached("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null or rn.cluster_id != best_cid or not rn.is_gatherable():
			continue
		var d2: float = Vector2(rn.global_position.x - ground.x,
			rn.global_position.z - ground.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = rn
	return best

## ЖИЛА, НА КОТОРУЮ ПОКАЗЫВАЕТ ЭТОТ РАЗБОР КЛИКА. Единая точка: ею пользуется
## и подсветка наведения, и правый клик, поэтому «промах в просвет кучи»
## работает в обоих одинаково по построению, а не по совпадению
func gather_target_from_pick(pick: Dictionary) -> ResourceNode:
	var rn := pick["target"] as ResourceNode
	if rn != null:
		return rn if rn.is_gatherable() else null
	# Под курсором нашлось здание/боец/руина — это не приказ на добычу
	if pick["target"] != null:
		return null
	return _ore_in_cluster_zone(pick["position"])

## НА КАКУЮ ЖИЛУ СЕЙЧАС ПОКАЖЕТ ПРИКАЗ. null — ни на какую (курсор над
## интерфейсом, над своим бойцом, над зданием, над пустой землёй, или в
## выделении нет рабочего).
## Это ЕДИНСТВЕННЫЙ ответ на вопрос «по чему я сейчас кликну»: его рисует
## подсветка (Main._update_hover_highlight) и его же исполняет _handle_right_click
func resource_under_cursor(screen_pos: Vector2) -> ResourceNode:
	if camera == null or _over_ui(screen_pos):
		return null
	_purge_invalid()
	if selected_units.is_empty() or not selection_has_worker():
		return null
	return gather_target_from_pick(_pick_at(screen_pos, order_pick_mask()))

func _handle_right_click(screen_pos: Vector2, run: bool = false) -> void:
	# ПКМ по панели — тоже не приказ миру (см. _over_ui): иначе правый клик по
	# ячейке очереди, снимающий заказ, заодно гнал бы выделенный отряд в точку
	# «под панелью», куда игрок вообще не показывал
	if _over_ui(screen_pos):
		return
	_purge_invalid()
	if selected_units.is_empty():
		return
	# Маска — общая с подсветкой наведения (см. order_pick_mask): то, что
	# подсвечено зелёным, обязано быть тем же самым узлом, что придёт сюда
	var pick := _pick_at(screen_pos, order_pick_mask())
	var target = pick["target"]
	var pos: Vector3 = pick["position"]
	if target == null and pos == Vector3.ZERO:
		return
	pos.y = 0.0
	# ── КЛИК ПО ХИТБОКСУ ОТРЯДА, А НЕ ПО ЧЕЛОВЕЧКУ ──────────────────────────
	# Луч/сетка нашли под курсором только грунт (или своего), а рядом с этой
	# точкой стоит чужой строй — значит игрок целился в отряд и промазал мимо
	# конкретной модели на полтора шага. Это приказ атаки (см. SQUAD_CLICK_REACH)
	if target == null or (target is Unit and target.faction == Constants.FACTION_PLAYER):
		var zone := _enemy_in_squad_zone(pos)
		if zone != null:
			target = zone

	# ПКМ ОТРЯДОМ ПО СВОЕМУ ЗАМКУ — завести отряд в гарнизон: там его лечат
	# и доукомплектовывают. Рабочих это не касается — им замок нужен как склад
	if target is Castle and target.faction == Constants.FACTION_PLAYER:
		if _try_garrison(target as Castle):
			return

	# ПКМ ПО РУИНЕ — отстроить заново: на её месте сразу встаёт стройплощадка,
	# и вся выделенная артель бежит туда с молотками
	if _try_rebuild_ruin(target):
		return

	# ПКМ ПО СТРОЙПЛОЩАДКЕ — поставить выделенных рабочих на стройку.
	# Раньше недострой был обычным своим зданием: приказ проваливался в
	# «идти в точку», рабочий доходил до фундамента и вставал рядом без дела
	if _try_join_construction(target):
		return

	# ТОЧКА СБОРА ЗДАНИЯ: выделена своя постройка — ПКМ по карте назначает,
	# куда пойдут новые отряды (см. Building.set_rally_point)
	if _try_set_rally(pos, target):
		return

	# ── ПРОМАХ В ПРОСВЕТ КУЧИ РУДЫ = ПРИКАЗ НА КУЧУ ─────────────────────────
	# Только когда луч не нашёл вообще ничего (под курсором грунт) и только при
	# выделенном рабочем. Явный клик по дереву, зданию или бойцу здесь уже
	# отработал и не перебивается — см. gather_target_from_pick
	if target == null and selection_has_worker():
		var ore := _ore_in_cluster_zone(pos)
		if ore != null:
			target = ore

	var is_gather_cmd: bool = target != null and target is ResourceNode
	var is_attack_cmd: bool = target != null and (target is Unit or target is Building) and target.faction != Constants.FACTION_PLAYER

	if is_gather_cmd or is_attack_cmd:
		# ═══════════════════════════════════════════════════════════════════════
		# ПРИКАЗ АТАКИ = ЗАМОК НА УКАЗАННЫЙ ОТРЯД (приоритет №1, см. Unit.target_lock)
		#
		# ЗДЕСЬ БЫЛ ГЛАВНЫЙ ИСТОЧНИК «ОТРЯД ДЕЛИТСЯ И РАЗБЕГАЕТСЯ»: для каждого
		# выделенного бойца собирался ПОЛНЫЙ список врагов на карте (все юниты +
		# все здания вражеской фракции), и боец получал приказ на СВОЮ ближайшую
		# цель из него. Кликнув по одному отряду противника, игрок фактически
		# отдавал N разных приказов: фланговые бойцы уходили на соседние отряды,
		# на пробегающего рабочего, на здание за спиной. Указанная цель при этом
		# могла не получить вообще никого.
		#
		# Теперь цель ОДНА для всех, а разбор чужого строя по моделям делает сам
		# Unit.command_attack через GameManager.squad_pick_member — то есть отряд
		# бьёт назначенный отряд сообща, но не сваливается всей толпой на одну модель
		# ═══════════════════════════════════════════════════════════════════════
		var atk_squads: Array = []
		for u in selected_units:
			if not is_instance_valid(u): continue
			if is_gather_cmd and u is Worker:
				u.command_gather(target)
			elif is_attack_cmd and u.has_method("command_attack"):
				# lock = true — приказ игрока, держится до истребления цели
				u.command_attack(target, true, true, true)
				var sid: int = (u as Unit).squad_id if u is Unit else 0
				if sid > 0 and not (sid in atk_squads):
					atk_squads.append(sid)
			elif is_gather_cmd and u.has_method("command_move"):
				# СОЛДАТ В СМЕШАННОМ ВЫДЕЛЕНИИ (рабочие + войска) по клику в лес
				# не остаётся без приказа: рубить он не умеет, значит идёт туда,
				# куда показали. Раньше такой боец просто игнорировал клик
				u.command_move(pos, false, Vector3.ZERO, false, true, run)
		# Приказ АТАКИ горячей группе — такой же повод крикнуть, как и марш
		# (см. _order_battle_cry). Сбор ресурсов поводом не является
		if is_attack_cmd:
			_order_battle_cry(selected_units)
			# ── ЧТО ПРИКАЗАНО, ИГРОК ОБЯЗАН ВИДЕТЬ ──────────────────────────
			# Приказ запоминается за отрядом и подсвечивает цель красным
			# кольцом — в том числе ПОЗЖЕ, когда игрок вернётся к этому отряду
			# (см. GameManager._refresh_order_marks). Снимется сам, когда цель
			# истребят
			for sid2 in atk_squads:
				GameManager.squad_note_order(int(sid2), GameManager.ORDER_ATTACK,
					(target as Node3D).global_position, target)
		# РАЗМЕТКУ СТРОЯ НА ВРЕМЯ АТАКИ НЕ СТИРАЕМ — ОНА ПРОСТО НЕ ДЕЙСТВУЕТ.
		# Смыкание рядов зовёт command_move каждому бойцу и сняло бы замок цели
		# посреди исполнения приказа, поэтому оно заблокировано, пока замок жив
		# (см. GameManager.squad_close_ranks). Но именно ЗАБЛОКИРОВАНО, а не
		# «слоты удалены»: форма строя нужна целой, чтобы отряд вернулся в неё
		# после боя (заказ владельца — «никаких застрявших фантомных солдат»).
		# Раньше здесь стоял squad_clear_formation, и отряд, сходивший в атаку,
		# терял свой строй навсегда
		return

	_issue_formation_move(pos, run)

# ОБЫЧНЫЙ ПКМ В ТОЧКУ = БЫСТРЫЙ ШАГ.
# Отряд идёт на полной скорости, форма строя переносится как есть, но держится
# вольно: это команда «быстро туда», а не «маршируйте». Строгий марш «кирпичиком»
# отдаётся другим жестом — растягиванием ПКМ (см. _execute_line_formation).
## run = true — ДВОЙНОЙ ПКМ: отряд бежит (Unit.SPRINT_SPEED_FACTOR), фаланга
## на время бега распускается, авто-бой игнорируется. Сбрасывается сам по
## прибытии (см. Unit._set_sprinting)
func _issue_formation_move(center: Vector3, run: bool = false) -> void:
	var movable: Array = []
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("command_move"):
			movable.append(u)
	if movable.is_empty():
		return
	_order_battle_cry(movable)
	var count := movable.size()
	# ОТРЯД (Ctrl+1..9) ИДЁТ МАРШЕМ, СОХРАНЯЯ СВОЙ СТРОЙ.
	# Раньше здесь всегда строилась заново квадратная сетка ceil(√N), и
	# прямоугольник 30 копейщиков в 3 ряда по обычному ПКМ схлопывался
	# в квадрат 6×5. Теперь строй переносится КАК ЕСТЬ: у каждого бойца
	# берётся его смещение от центра отряда, и весь блок сдвигается в точку
	# приказа. Форма, интервалы и номера рядов сохраняются в точности.
	# ОТРЯД ИДЁТ МАРШЕМ, СОХРАНЯЯ СВОЙ СТРОЙ. Признак — выделен именно отряд,
	# а не сохранённая горячая группа: теперь выделение ВСЕГДА отрядное, и
	# требовать Ctrl+1..9 больше незачем (раньше строй 30 копейщиков по
	# обычному ПКМ схлопывался в квадрат, если группа не была назначена)
	# НЕСКОЛЬКО ОТРЯДОВ — СЕТКА БЛОКОВ, А НЕ ОБЩАЯ КУЧА (см. _issue_group_grid_move)
	if _issue_group_grid_move(movable, center, run):
		return
	if _selection_is_squad():
		_issue_march_keeping_shape(movable, center, false, run)   # false = быстрым шагом
		return

	var cols := maxi(1, int(ceil(sqrt(float(count)))))
	# Вдвое плотнее прежнего (было 1.0): по ПКМ отряд сбивается в тесную кучу
	var spacing := UNIT_SPACING
	# Курс движения = общее направление взгляда для всей кучи
	var course := _group_course(movable, center)
	for i in range(count):
		var col := i % cols
		var row := i / cols
		var offset_x := (col - (cols - 1) * 0.5) * spacing
		var offset_z := row * spacing
		movable[i].formation_row = row
		movable[i].command_move(center + Vector3(offset_x, 0.0, offset_z), false, course,
			false, true, run)     # player_order — см. Unit._move_lock

# ═════════════════════════════════════════════════════════════════════════════
# СЕТКА ОТРЯДОВ: НЕСКОЛЬКО БЛОКОВ НЕ СВАЛИВАЮТСЯ В ОДНУ КУЧУ
#
# Жалоба владельца: выделяешь 2-5 отрядов, кликаешь в точку — и они лезут все в
# одно место. Так и было: приказ уводил ВСЁ выделение одним «кирпичом»
# (_issue_march_keeping_shape переносит общий центр масс), то есть форма группы
# бралась ИЗ ТОГО, КАК ОТРЯДЫ СТОЯЛИ ДО ПРИКАЗА. Стояли они друг на друге —
# придут друг на друга; шли из боя вперемешку — так и встанут.
#
# Теперь точка клика — это ЦЕНТР ГРУППЫ, а отряды раскладываются по ячейкам
# сетки, каждый СО СВОИМ строем внутри (внутренняя форма переносится как есть,
# см. _issue_march_keeping_shape):
#   • 1-2 отряда  — в один ряд: два блока встают бок о бок;
#   • 3-4 отряда  — ряд из трёх (центральный ровно в точке клика, соседи слева
#                   и справа), четвёртый уходит во второй ряд, назад;
#   • 5 и больше  — прямоугольник ceil(√n) в ширину: 3×2, 3×3 и так далее.
# Ряды центрируются каждый по себе, поэтому неполный последний ряд стоит
# посередине, а не прижимается к флангу.
# ═════════════════════════════════════════════════════════════════════════════

## Просвет между соседними блоками отрядов, метры. Больше интервала между
## шеренгами ВНУТРИ отряда (ROW_DEPTH): это граница между отрядами, и по ней
## должно быть видно, где кончается один блок и начинается другой.
##
## ЗАКАЗ ВЛАДЕЛЬЦА — ПЛОТНЕЕ. Было 3.0, и на нескольких отрядах группа
## расползалась по полю: блоки стояли на таком расстоянии, что читались как
## отдельные кучки, а не как одно войско у указанной точки. Метр — это всё ещё
## видимая граница между блоками (внутри отряда интервал вчетверо меньше), но
## уже не поле между ними
const GROUP_CELL_GAP := 1.0

## Потолок габарита ячейки, метры (см. разбор у cell_w). Двадцать метров — это
## заведомо больше любого компактного отряда и заведомо меньше растянутой в
## нитку колонны, из-за которой сетка и разъезжалась
const GROUP_CELL_MAX := 20.0

## Насколько отряды считаются стоящими НА ОДНОЙ ГЛУБИНЕ при раздаче ячеек.
## Больше обычного разброса центров масс у выровненной группы и заметно меньше
## расстояния между настоящими эшелонами
const GROUP_DEPTH_EPS := 6.0

## Сколько блоков в ряду сетки. 3 для трёх-четырёх отрядов — это прямое
## требование задания («центральный в точку клика, остальные слева, справа и
## сзади»), а не общая формула: при ceil(√4) = 2 четыре отряда встали бы
## квадратом 2×2, и НИ ОДИН не оказался бы в точке клика
func _group_grid_cols(n: int) -> int:
	if n <= 2:
		return maxi(n, 1)
	if n <= 4:
		return 3
	return int(ceil(sqrt(float(n))))

## Габарит отряда в системе координат марша: [ширина поперёк курса, глубина вдоль].
## Меряется по РЕАЛЬНЫМ позициям бойцов, а не по их числу: отряд, растянутый
## игроком в длинную шеренгу, и он же, сбитый в квадрат, требуют разного места
func _squad_extent(men: Array, course: Vector3, across: Vector3) -> Vector2:
	if men.is_empty():
		return Vector2.ZERO
	var min_a := INF; var max_a := -INF
	var min_c := INF; var max_c := -INF
	for u in men:
		var p: Vector3 = (u as Node3D).global_position
		var a: float = p.dot(across)
		var c: float = p.dot(course)
		min_a = minf(min_a, a); max_a = maxf(max_a, a)
		min_c = minf(min_c, c); max_c = maxf(max_c, c)
	return Vector2(max_a - min_a, max_c - min_c)

## Расставить выделенные отряды сеткой вокруг точки клика.
## false — отрядов меньше двух, и раскладывать нечего: приказ отрабатывает
## прежним путём (перенос общего строя)
func _issue_group_grid_move(movable: Array, center: Vector3, run: bool) -> bool:
	var blocks := _split_into_blocks(movable)
	# Блок с sid = 0 — это бойцы вне реестра отрядов (одиночки, рабочие).
	# Сеткой их не строим: у них нет ни своего строя, ни курса
	var squads: Array = []
	for b in blocks:
		var arr: Array = b
		if arr.is_empty():
			continue
		var sid: int = (arr[0] as Unit).squad_id if arr[0] is Unit else 0
		if sid > 0:
			squads.append(arr)
	if squads.size() < 2:
		return false
	# ── ОДИНОЧКИ ИЗ ВЫДЕЛЕНИЯ НЕ ПРОПАДАЮТ ─────────────────────────────────
	# Блоки с sid = 0 (рабочие, бойцы вне реестра отрядов) сеткой не строятся —
	# у них нет ни своего строя, ни курса. Но приказ они получить ОБЯЗАНЫ:
	# раньше их просто отбрасывал фильтр выше, а функция возвращала «приказ
	# отдан», и вызывающий уходил, никого больше не спросив
	var loose: Array = []
	for b2 in blocks:
		var arr2: Array = b2
		if arr2.is_empty():
			continue
		var sid2: int = (arr2[0] as Unit).squad_id if arr2[0] is Unit else 0
		if sid2 <= 0:
			loose.append_array(arr2)

	# ЕДИНЫЙ КУРС ВСЕЙ ГРУППЫ: от общего центра масс к точке приказа. По нему
	# же ориентируется сетка, поэтому «слева/справа/сзади» — это слева, справа
	# и сзади ОТНОСИТЕЛЬНО ХОДА ГРУППЫ, а не сторон света
	var course := _group_course(movable, center)
	if course.length_squared() < 1e-6:
		course = Vector3.FORWARD
	var across := Vector3(-course.z, 0.0, course.x)

	# Ячейка одна на всех — по самому крупному отряду: разные размеры ячеек
	# развалили бы ряды, а одинаковые дают ровную сетку при любом составе
	var cell_w := 0.0
	var cell_d := 0.0
	for s in squads:
		var e := _squad_extent(s as Array, course, across)
		cell_w = maxf(cell_w, e.x)
		cell_d = maxf(cell_d, e.y)
	# ── ЯЧЕЙКА ПО САМОМУ КРУПНОМУ, НО НЕ ПО САМОМУ ШИРОКОМУ ────────────────
	# Ячейка одна на всех и берётся по МАКСИМУМУ габаритов — иначе ряды
	# развалятся. Но максимум по разношёрстному выделению задаёт один
	# растянутый отряд, и все остальные получают ячейку под него: пять
	# компактных блоков разъезжались, потому что в выделении был один широкий.
	# Поэтому габарит зажимается сверху: шире GROUP_CELL_MAX ячейка не растёт,
	# а отряд, который в неё не влез, просто стоит чуть плотнее к соседу
	cell_w = minf(cell_w, GROUP_CELL_MAX) + GROUP_CELL_GAP
	cell_d = minf(cell_d, GROUP_CELL_MAX) + GROUP_CELL_GAP

	var n: int = squads.size()
	var cols: int = mini(_group_grid_cols(n), n)

	# ── ЯЧЕЙКИ РАЗДАЮТСЯ ПО ФАКТИЧЕСКОМУ ПОЛОЖЕНИЮ ОТРЯДОВ ──────────────────
	# Порядок в `squads` — это порядок появления отрядов в выделении, то есть по
	# сути порядок реестра. Раздавать ячейки по нему нельзя: отряд, стоящий на
	# левом фланге, легко получал ячейку справа и шёл туда НАСКВОЗЬ через соседей.
	# Десять отрядов при этом пересекались все со всеми, перемешивались и, пока
	# расталкивание разбирало кашу, разбегались в стороны — ровно жалоба «бегут в
	# одну точку и встают хаотично».
	#
	# Сортируем ровно в том порядке, в каком раскладываются ячейки: сперва по
	# глубине вдоль курса (передние ряды сетки — передним отрядам), затем внутри
	# каждого ряда слева направо. Это та же топология, что у шеренг внутри отряда
	# (см. _topo_order), только единица здесь — отряд, а точка — его центр масс.
	# Пути перестают пересекаться: группа сдвигается параллельно
	var cents: Array = []
	for s in squads:
		var c := Vector3.ZERO
		for u in (s as Array):
			c += (u as Node3D).global_position
		c /= float(maxi((s as Array).size(), 1))
		cents.append(c)
	var order: Array = []
	for i0 in range(n):
		order.append(i0)
	# Сортировка по глубине с ДОПУСКОМ и добором по ширине. Без допуска отряды,
	# стоящие в одну шеренгу (а это самый обычный случай — они и так выровнены),
	# имеют почти равную глубину, сравнение решает микрометровая разница, и
	# порядок выходит случайным: соседние по фронту отряды попадали в разные ряды
	# сетки вперемешку. С допуском такая группа честно упорядочивается слева
	# направо, и ряды сетки набираются подряд идущими соседями
	order.sort_custom(func(a, b):
		var da: float = (cents[a] as Vector3).dot(course)
		var db: float = (cents[b] as Vector3).dot(course)
		if absf(da - db) > GROUP_DEPTH_EPS:
			return da > db
		return (cents[a] as Vector3).dot(across) < (cents[b] as Vector3).dot(across))
	var oi := 0
	while oi < n:
		var last: int = mini(oi + cols, n)
		var row_slice: Array = order.slice(oi, last)
		row_slice.sort_custom(func(a, b):
			return (cents[a] as Vector3).dot(across) < (cents[b] as Vector3).dot(across))
		for k in range(row_slice.size()):
			order[oi + k] = row_slice[k]
		oi = last
	var sorted_squads: Array = []
	for i1 in order:
		sorted_squads.append(squads[int(i1)])
	squads = sorted_squads

	for i in range(n):
		var row: int = i / cols
		var col: int = i % cols
		# Сколько блоков реально стоит в ЭТОМ ряду — по нему ряд и центрируется,
		# поэтому неполный последний ряд стоит посередине, а не с краю
		var in_row: int = mini(cols, n - row * cols)
		var off_a: float = (float(col) - float(in_row - 1) * 0.5) * cell_w
		# ПЕРВЫЙ РЯД ВСТАЁТ РОВНО В ТОЧКУ КЛИКА, следующие — позади него.
		# Именно поэтому при трёх отрядах центральный оказывается точно там,
		# куда показал игрок, а не «где-то в середине общей кучи»
		var cell_centre: Vector3 = center + across * off_a - course * (float(row) * cell_d)
		# Внутренний строй отряда переносится как есть; курс — общий на группу,
		# иначе фланговые блоки пришли бы веером (см. course_override)
		_issue_march_keeping_shape(squads[i] as Array, cell_centre, false, run, course)
	# Одиночки — своей ячейкой позади сетки: строя у них нет, но приказ есть
	if not loose.is_empty():
		var rows_n: int = int(ceil(float(n) / float(maxi(cols, 1))))
		_issue_march_keeping_shape(loose,
			center - course * (float(rows_n) * cell_d), false, run, course)
	return true

## ЗАПОМНИТЬ РАЗМЕТКУ ЗА КАЖДЫМ ОТРЯДОМ ВЫДЕЛЕНИЯ.
## Выделение может состоять из нескольких отрядов (построение секциями), и
## каждому достаётся ТОЛЬКО его кусок общего списка мест — иначе при потерях
## копейщики полезли бы смыкать ряды на слоты лучников
func _remember_formation(flat: Array, slots: Array, course: Vector3, slow: bool) -> void:
	var by_squad: Dictionary = {}
	for i in range(flat.size()):
		if i >= slots.size():
			break
		var u = flat[i]
		if not (u is Unit):
			continue
		var sid: int = (u as Unit).squad_id
		if sid <= 0:
			continue
		if not by_squad.has(sid):
			by_squad[sid] = []
		(by_squad[sid] as Array).append(slots[i])
	for sid in by_squad:
		GameManager.squad_set_formation(int(sid), by_squad[sid], course, slow)
		# ── КУДА ОТРЯД ПОСЛАН, ИГРОК ОБЯЗАН ВИДЕТЬ ──────────────────────────
		# Метка ложится в СРЕДНЮЮ точку выданных отряду мест, а не в точку
		# клика: у нескольких отрядов, разведённых по ячейкам, точка клика одна
		# на всех, и метки легли бы стопкой в одном месте.
		# Снимется сама, когда отряд дойдёт (GameManager._refresh_order_marks)
		var acc := Vector3.ZERO
		for sp in by_squad[sid]:
			acc += sp as Vector3
		acc /= float((by_squad[sid] as Array).size())
		GameManager.squad_note_order(int(sid), GameManager.ORDER_MOVE, acc)

# Общее направление движения отряда: от его центра масс к точке приказа.
# Нужно, чтобы после прихода ВСЕ смотрели одинаково, а не каждый в свой слот
func _group_course(movable: Array, center: Vector3) -> Vector3:
	var centroid := Vector3.ZERO
	for u in movable:
		centroid += (u as Node3D).global_position
	centroid /= float(movable.size())
	var course := center - centroid
	course.y = 0.0
	if course.length() < 0.01:
		return Vector3.ZERO
	return course.normalized()

# Перенос строя без изменения его формы: смещения относительно центра отряда
# сохраняются, номер ряда пересчитывается по глубине вдоль курса марша.
# slow = true — маршевый шаг (половина скорости, строй держится жёстко),
# slow = false — быстрый шаг по обычному ПКМ
## course_override — ЕДИНЫЙ ФРОНТ ДЛЯ ВСЕЙ ГРУППЫ. Когда отряды расставляются
## сеткой (см. _issue_group_grid_move), каждый идёт в СВОЮ ячейку, и курс
## «от своего центра к своей точке» у фланговых отрядов расходится с курсом
## центрального на десятки градусов — группа приходит веером вместо строя.
## Пустой вектор = прежнее поведение (курс считает сам)
func _issue_march_keeping_shape(movable: Array, center: Vector3,
		slow: bool = true, run: bool = false,
		course_override: Vector3 = Vector3.ZERO) -> void:
	var centroid := Vector3.ZERO
	for u in movable:
		centroid += (u as Node3D).global_position
	centroid /= float(movable.size())
	centroid.y = 0.0

	var course := center - centroid
	if course_override.length_squared() > 1e-6:
		course = course_override
	course.y = 0.0
	if course.length() < 0.01:
		course = Vector3.FORWARD
	course = course.normalized()

	# Порядок ОТ ПЕРЕДОВОЙ К ТЫЛУ: разметка отряда обязана начинаться с первой
	# шеренги, иначе смыкание рядов (SquadFormation.close_ranks) подтянет
	# выживших не вперёд, а назад
	var ordered: Array = movable.duplicate()
	ordered.sort_custom(func(a, b):
		return (a as Node3D).global_position.dot(course) \
			> (b as Node3D).global_position.dot(course))

	var slots: Array = []
	for u in ordered:
		var offset: Vector3 = (u as Node3D).global_position - centroid
		offset.y = 0.0
		# Ряд = глубина юнита вдоль курса: те, кто впереди по ходу марша,
		# получают ряд 0-1 и несут копья наперевес
		var depth: float = -offset.dot(course)
		u.formation_row = maxi(0, int(round((depth + ROW_DEPTH * 0.5) / ROW_DEPTH)))
		var slot: Vector3 = center + offset
		slots.append(slot)
		# Весь отряд смотрит по курсу марша — единым фронтом
		u.command_move(slot, slow, course, false, true, run)   # player_order
	_remember_formation(ordered, slots, course, slow)

# ─── Горячая группа: стойки и признак «выделен именно отряд» ─────────────────

## Индекс горячей группы, совпадающей с текущим выделением (-1 — не группа).
## Совпадением считается: все выделенные юниты входят в группу и наоборот.
func current_group_index() -> int:
	if selected_units.is_empty():
		return -1
	for idx in range(_groups.size()):
		var grp: Array = _groups[idx]
		if grp.is_empty() or grp.size() != selected_units.size():
			continue
		# Членство в группе — тоже словарём: перебор `u in grp` внутри цикла по
		# выделению давал ту же квадратичную стоимость, что и в _select_one
		var in_grp: Dictionary = {}
		for g in grp:
			in_grp[g] = true
		var same := true
		for u in selected_units:
			if not in_grp.has(u):
				same = false
				break
		if same:
			return idx
	return -1

## Завести выделенные БОЕВЫЕ отряды в гарнизон замка.
## false — ни один отряд не годится (одни рабочие) или гарнизон полон,
## тогда правый клик отрабатывает как обычный приказ движения
func _try_garrison(castle: Castle) -> bool:
	var sent := 0
	for sid in selected_squad_ids():
		var members := GameManager.squad_members(int(sid))
		if members.is_empty():
			continue
		if members[0] is Worker:
			continue                       # рабочему в гарнизоне делать нечего
		if castle.request_garrison(int(sid)):
			sent += 1
	return sent > 0

## ПОДКЛЮЧИТЬ РАБОЧИХ К СТРОЙКЕ. Возвращает true, если приказ отдан хотя бы
## одному — тогда обычный приказ движения уже не нужен.
## Недострой опознаётся по группе construction_sites, а не по классу:
## ConstructionSite намеренно живёт без class_name (грузится через load)
## ПКМ РАБОЧИМИ ПО РУИНЕ: заменить её стройплощадкой и отправить туда артель.
##
## false — цель не руина, не своя, рабочих в выделении нет или не хватило
## ресурсов. В последнем случае приказ намеренно ПРОВАЛИВАЕТСЯ ДАЛЬШЕ и
## становится обычным «идти туда»: молча съесть клик хуже, чем сходить на место
func _try_rebuild_ruin(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not (target is Node) or not (target as Node).is_in_group("ruins"):
		return false
	if int((target as Node).get_meta("ruin_faction", -1)) != Constants.FACTION_PLAYER:
		return false
	var crew: Array = []
	for u in selected_units:
		if is_instance_valid(u) and u is Worker:
			crew.append(u)
	if crew.is_empty():
		return false
	var site = GameManager.rebuild_ruin(target as Node)
	if site == null:
		return false
	for w in crew:
		(w as Worker).command_build(site as Node3D)
	return true

func _try_join_construction(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not (target is Node) or not (target as Node).is_in_group("construction_sites"):
		return false
	if (target as Building).faction != Constants.FACTION_PLAYER:
		return false
	var sent := 0
	for u in selected_units:
		if is_instance_valid(u) and u is Worker:
			(u as Worker).command_build(target as Node3D)
			sent += 1
	return sent > 0

## ТОЧКА СБОРА: если выделены ТОЛЬКО свои постройки, ПКМ по карте назначает им
## точку сбора, а не отдаёт приказ движения (двигать здание всё равно нечем).
## Клик по вражескому объекту сюда не попадает — там обычная логика атаки
func _try_set_rally(pos: Vector3, target) -> bool:
	if target != null and (target is Unit or target is ResourceNode):
		return false
	var buildings: Array = []
	for u in selected_units:
		if not is_instance_valid(u):
			continue
		if not (u is Building) or (u as Building).faction != Constants.FACTION_PLAYER:
			return false          # в выделении есть кто-то кроме своих зданий
		buildings.append(u)
	if buildings.is_empty():
		return false
	for b in buildings:
		(b as Building).set_rally_point(pos)
	return true

func _selection_is_hotkey_group() -> bool:
	return current_group_index() >= 0

# ═════════════════════════════════════════════════════════════════════════════
# БОЕВОЙ КЛИЧ НА ПРИКАЗ — ТОЛЬКО ГОРЯЧИМ ГРУППАМ И ЧЕРЕЗ РАЗ
#
# Раньше клич звучал на КАЖДЫЙ приказ движения любому выделению. Обычный
# микроконтроль — это десятки кликов по земле в минуту, и солдаты орали не
# замолкая; из «переклички перед атакой» звук превратился в фон, который
# хочется выключить.
#
# Теперь клич — признак ОСМЫСЛЕННОГО манёвра, а не любого клика:
#   • отряды должны быть сведены в горячую группу (Ctrl+1..9). Разовое
#     выделение рамкой командует молча — им игрок и пользуется чаще всего;
#   • даже у группы клич идёт с шансом и длинным откатом
#     (GameManager.CRY_ORDER_CHANCE / CRY_ORDER_COOLDOWN_MS).
#
# Смена стойки под это правило НЕ подпадает: она нажимается кнопкой, случается
# редко и отвечать на неё звуком нужно каждый раз (см. set_selection_stance).
# ═════════════════════════════════════════════════════════════════════════════
func _order_battle_cry(movable: Array) -> int:
	if not _selection_is_hotkey_group():
		return 0
	return GameManager.order_battle_cry(movable)

## Выделен ли настоящий отряд (а не одиночка вне реестра). Боевые отряды
## всегда состоят больше чем из одного бойца, рабочий — отряд из одного,
## поэтому марш строем осмыслен от двух человек
func _selection_is_squad() -> bool:
	if selected_units.size() < 2:
		return false
	for u in selected_units:
		if not is_instance_valid(u) or not (u is Unit):
			return false
		if (u as Unit).squad_id <= 0:
			return false
	return true

## Переключить стойку всему текущему выделению (кнопки [АТАКА]/[ЗАЩИТА])
func set_selection_stance(stance_id: String) -> void:
	_purge_invalid()
	# КЛИЧ — ТОЛЬКО НА РЕАЛЬНУЮ СМЕНУ СТОЙКИ. Игрок, повторно ткнувший в уже
	# активную кнопку, ничего не переключает — и орать по этому поводу нечего.
	# Состояние снимаем ДО переключения, по каждому отряду отдельно: в выделении
	# отряды могут стоять в разных стойках, и «сменилось» у них тоже своё
	var was: Dictionary = {}
	for u in selected_units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var sid: int = (u as Unit).squad_id
		if sid > 0 and not was.has(sid):
			was[sid] = (u as Unit).stance
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("set_stance"):
			u.set_stance(stance_id)
	for sid2 in was:
		if String(was[sid2]) != stance_id:
			GameManager.squad_battle_cry(int(sid2))

## Стойка выделения: общая, если у всех одна; иначе пустая строка
func selection_stance() -> String:
	var result := ""
	for u in selected_units:
		if not is_instance_valid(u) or not ("stance" in u):
			continue
		var s: String = u.stance
		if result == "":
			result = s
		elif result != s:
			return ""
	return result
