extends Building
## СТРОЙПЛОЩАДКА (фундамент).
##
## Ставится вместо готового здания, когда игрок заказал постройку у рабочего.
## Ресурсы списываются В МОМЕНТ РАЗМЕЩЕНИЯ (как и раньше — см. Main._placing_refund),
## а сама постройка растёт, только пока рядом стоит хотя бы один рабочий
## с молотком. По готовности площадка подменяет себя настоящим зданием.
##
## Файл НАМЕРЕННО без class_name: подключается через load(), поэтому не зависит
## от global_script_class_cache.cfg (тот же приём, что у FormationPreview).
## Наследование от Building даёт бесплатно: группы зданий, кольцо выделения,
## take_damage и клик мышью.

signal built(new_building)

# Что строим: ключ из game_settings.BUILDING_SPRITES ("barracks"/"smithy"/"mine")
var target_id: String   = ""
var target_name: String = "Здание"
var build_time: float   = 12.0
var progress: float     = 0.0

# Рабочие, которые СЕЙЧАС стучат молотками по этой стройке
var _builders: Array = []
var _done: bool = false

## СТРОЙКА, КОТОРОЙ РАБОЧИЕ НЕ НУЖНЫ. Так ставится Замок: он бесплатен, а на
## момент его закладки рабочих на карте ещё нет вовсе — их спавнит сам Замок
## уже после постройки. Требуй он бригаду, партия просто не началась бы
var self_building: bool = false

# Вклад КАЖДОГО дополнительного рабочего в скорость стройки (см. _process)
const BUILDER_SPEEDUP := 0.6

var _fill_node: MeshInstance3D = null   # растущий «сруб» (только запасной вид)
var _fill_full_h: float = 1.0
## Спрайт стройки; пока он есть, процедурных лесов не строим вовсе
var _site_sprite: MeshInstance3D = null
var _site_tex: Texture2D = null

## СЧЁТЧИК ГОТОВНОСТИ 1%–100% над стройкой. Работает одинаково для обоих
## визуалов (картинка стройки и запасные леса) — висит над зданием независимо
## от того, что нарисовано ниже. Ребёнок узла, поэтому исчезает сам собой в
## _complete() вместе со всей площадкой — отдельно прятать не нужно
var _progress_label: Label3D = null

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _House  := preload("res://scripts/House.gd")
const _BBUtil2 := preload("res://scripts/BillboardUtil.gd")

func _ready() -> void:
	display_name = "Стройка: " + target_name
	# У недостроя мало здоровья — его легко снести, пока он не готов.
	# Значение крутится в конфиге: BUILDINGS["construction_site"].max_hp
	max_health = _UCfg.building_stat("construction_site", "max_hp", 120.0)
	is_dropoff = false
	# building_id пустой: цветной спрайт готового здания тут не нужен,
	# у стройки свой процедурный вид (леса + растущий сруб)
	building_id = ""
	sprite_path = ""
	# ПОРОГ ВИДИМОСТИ СТРОЙКИ. В балансной таблице у всех зданий build_time = 0
	# («строится мгновенно» — отладочная настройка владельца), и площадка
	# исчезала бы в том же кадре, в котором появилась: картинку стройки увидеть
	# было бы негде. Число живёт в конфиге (CONSTRUCTION_MIN_SEC), поставить 0 —
	# вернуть прежнее мгновенное появление
	build_time = maxf(build_time, _UCfg.CONSTRUCTION_MIN_SEC)
	super._ready()
	add_to_group("construction_sites")
	_build_progress_label()

# ─────────────────────────────────────────────────────────────────────────────
# ВИД НЕДОСТРОЯ
#
# ОСНОВНОЙ — картинка стройки из папки process_building_destroeyrs:
# Castle_Construction для замка и House_Construction для всего остального.
# Она рисуется ровно тем же способом, что и готовое здание (тот же квад по
# пропорциям картинки, тот же материал без доворота к камере, та же поправка
# на наклон камеры), поэтому недострой и достроенное здание совпадают по
# габаритам и не «прыгают» в момент подмены.
#
# ЗАПАСНОЙ — прежние процедурные леса с растущим срубом. Остаются на случай,
# когда картинки нет на диске: правило проекта — визуал никогда не роняет игру.
# ─────────────────────────────────────────────────────────────────────────────
func _build_visual() -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = build_size
	collider.shape = shape
	collider.position.y = build_size.y * 0.5
	add_child(collider)

	if _build_site_sprite():
		# Маркер выделения — общий для всех построек, и по картинке стройки он
		# подгоняется тем же способом, что и по готовому зданию
		selection_ring = make_selection_marker()
		add_child(selection_ring)
		_fit_marker_to_sprite(_site_tex, _site_sprite.mesh as QuadMesh)
		return

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.46, 0.32, 0.16)
	wood.roughness = 0.95

	# Помост-основание
	var base := MeshInstance3D.new()
	var base_box := BoxMesh.new()
	base_box.size = Vector3(build_size.x, 0.18, build_size.z)
	base_box.material = wood
	base.mesh = base_box
	base.position.y = 0.09
	add_child(base)

	# Четыре угловые стойки
	var hx: float = build_size.x * 0.5 - 0.12
	var hz: float = build_size.z * 0.5 - 0.12
	for corner in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.14, build_size.y, 0.14)
		pb.material = wood
		post.mesh = pb
		post.position = Vector3(corner.x, build_size.y * 0.5, corner.y)
		add_child(post)

	# Растущий сруб: высота = доля готовности
	_fill_full_h = maxf(build_size.y - 0.25, 0.3)
	_fill_node = MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(build_size.x * 0.78, _fill_full_h, build_size.z * 0.78)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.53, 0.48)
	stone.roughness = 0.9
	fb.material = stone
	_fill_node.mesh = fb
	add_child(_fill_node)
	_apply_progress_visual()

	# Тот же маркер выделения, что и у готовых зданий
	selection_ring = make_selection_marker()
	add_child(selection_ring)

## РАЗМЕР ЦИФР ГОТОВНОСТИ. Ровно вдвое больше прежних 44: счётчик читается
## с обычного игрового зума, а не только когда камера уткнулась в стройку.
const PROGRESS_FONT_SIZE := 88
## ТЁМНАЯ ОБВОДКА. Стройка стоит на траве, на камне, в тени леса и на фоне
## собственных лесов — светлые цифры без контура сливались с любым из них.
## Держится пропорционально кеглю (≈30% высоты буквы), иначе на удвоенном
## шрифте прежние 10 px выглядели бы волоском
const PROGRESS_OUTLINE := 26
## Цвет обводки задаётся ЯВНО, а не по умолчанию: Label3D наследует
## outline_modulate из темы проекта, и «по умолчанию чёрный» — не гарантия
const PROGRESS_OUTLINE_COLOR := Color(0.05, 0.04, 0.03, 1.0)

## Текстовый счётчик готовности над стройкой (см. поле _progress_label выше)
func _build_progress_label() -> void:
	_progress_label = Label3D.new()
	_progress_label.name = "BuildProgressLabel"
	_progress_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_progress_label.no_depth_test = true
	_progress_label.font_size = PROGRESS_FONT_SIZE
	_progress_label.outline_size = PROGRESS_OUTLINE
	_progress_label.outline_modulate = PROGRESS_OUTLINE_COLOR
	_progress_label.modulate = Color(1.0, 0.92, 0.55)
	# Цифры стали вдвое выше, а привязаны они по ЦЕНТРУ строки: на прежней высоте
	# нижняя половина текста заехала бы на крышу стройки. Поднимаем на половину
	# прибавки кегля (font_size × pixel_size — это высота строки в метрах)
	_progress_label.position.y = build_size.y + 1.0 \
		+ float(PROGRESS_FONT_SIZE - 44) * _progress_label.pixel_size * 0.5
	_progress_label.text = "1%"
	add_child(_progress_label)

func _update_progress_label() -> void:
	if _progress_label == null or not is_instance_valid(_progress_label):
		return
	var pct: int = clampi(int(round(progress / maxf(build_time, 0.01) * 100.0)), 1, 100)
	_progress_label.text = "%d%%" % pct

# Сруб растёт снизу вверх: масштабируем по Y и поднимаем на половину высоты
func _apply_progress_visual() -> void:
	_update_progress_label()
	# У картинки стройки стадий нет — она одна на весь срок работ
	if _fill_node == null:
		return
	var frac: float = clampf(progress / maxf(build_time, 0.01), 0.02, 1.0)
	_fill_node.scale.y = frac
	_fill_node.position.y = _fill_full_h * frac * 0.5

func add_builder(w: Node) -> void:
	if not (w in _builders):
		_builders.append(w)

func remove_builder(w: Node) -> void:
	_builders.erase(w)

func builder_count() -> int:
	_builders = _builders.filter(func(b): return is_instance_valid(b))
	return _builders.size()

## Картинка стройки. false — её нет, строим процедурные леса
func _build_site_sprite() -> bool:
	var path: String = GameManager.construction_sprite_path(faction, target_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var tex := load(path) as Texture2D
	if tex == null:
		return false
	var quad := QuadMesh.new()
	quad.size = sprite_quad_size(tex, build_size)
	quad.material = _BBUtil2.make_static_material(tex)
	_site_sprite = MeshInstance3D.new()
	_site_sprite.name = "ConstructionSprite"
	_site_sprite.mesh = quad
	# Низ на грунте, как у любой постройки (см. Building._maybe_load_building_sprite)
	_site_sprite.position.y = quad.size.y * 0.5
	add_child(_site_sprite)
	_site_tex = tex
	return true

## НАСКОЛЬКО РАБОЧИЙ ОТСТУПАЕТ ОТ СТЕНЫ, встав на работу. Ровно на длину
## вытянутых с доской рук: молоток должен доставать до лесов, а не махать
## воздухом в метре от них. Читает и Worker._process_build — порог прихода и
## точка стояния обязаны быть согласованы, иначе рабочий «доходит» раньше,
## чем встаёт куда надо (та же связка, что SLOT_ARRIVE/SLOT_SETTLE у жилы)
const WORK_PAD := 0.25

## РАССТОЯНИЕ ОТ ЦЕНТРА ПЛОЩАДКИ ДО ЕЁ СТЕНЫ по направлению dir (в плане).
##
## Раньше здесь стоял maxf(build_size.x, build_size.z) * 0.5 — радиус описанной
## окружности. У прямоугольной постройки (барак 6×4) это значит, что с КОРОТКОЙ
## стороны рабочий останавливался на метр дальше стены, и именно так выглядит
## жалоба «стоит на расстоянии от фундамента». Теперь считается честное
## пересечение луча из центра с коробкой габарита: с любой стороны рабочий
## подходит к своей стене, а не к воображаемому кругу вокруг здания
func edge_distance(dir: Vector3) -> float:
	var hx: float = build_size.x * 0.5
	var hz: float = build_size.z * 0.5
	var dx: float = absf(dir.x)
	var dz: float = absf(dir.z)
	var n: float = sqrt(dx * dx + dz * dz)
	if n < 0.001:
		return maxf(hx, hz)
	# Луч единичной длины: до какой из двух пар стен он дотянется раньше
	dx /= n
	dz /= n
	var tx: float = hx / dx if dx > 0.0001 else INF
	var tz: float = hz / dz if dz > 0.0001 else INF
	return minf(tx, tz)

## Точка, куда рабочему идти: край площадки, а не её центр.
## Запас за габаритом — WORK_PAD (25 см): рабочий стоит ВПЛОТНУЮ к стене/лесам
func work_position(from: Vector3) -> Vector3:
	var dir := from - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	return global_position + dir * (edge_distance(dir) + WORK_PAD)

# Недострой считает прогресс — тикает, пока не готов
func _needs_tick() -> bool:
	return not _done

func _process(delta: float) -> void:
	super._process(delta)
	if _done:
		return
	var n := builder_count()
	if n <= 0:
		if not self_building:
			return    # без рабочих стройка стоит
		progress += delta
		_apply_progress_visual()
		if progress >= build_time:
			_complete()
		return
	# АРТЕЛЬ: каждый следующий рабочий ускоряет стройку, но с убывающей
	# отдачей. 1 рабочий — ×1.0, 2 — ×1.6, 3 — ×2.2, 5 — ×3.4.
	# Убывание намеренное: иначе выгодно было бы сгонять на фундамент всех
	# рабочих базы, и экономика на время стройки останавливалась бы
	progress += delta * (1.0 + float(n - 1) * BUILDER_SPEEDUP)
	_apply_progress_visual()
	if progress >= build_time:
		_complete()

func _complete() -> void:
	if _done:
		return
	_done = true
	var parent := get_parent()
	var pos := global_position
	var f := faction
	var made: Building = _make_target()
	if made != null and parent != null:
		made.faction = f
		parent.add_child(made)
		made.global_position = pos
		built.emit(made)
	# Рабочих отпускаем: стройка кончилась, пусть возвращаются к делам
	for b in _builders:
		if is_instance_valid(b) and b.has_method("on_construction_finished"):
			b.on_construction_finished()
	_builders.clear()
	queue_free()

func _make_target() -> Building:
	match target_id:
		"barracks": return Barracks.new()
		"smithy":   return Smithy.new()
		"mine":     return Mine.new()
		"house":    return _House.new()
		"castle":   return Castle.new()
	return null
