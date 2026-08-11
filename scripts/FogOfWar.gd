extends Node3D
class_name FogOfWar

## ═══════════════════════════════════════════════════════════════════════════
## ТУМАН ВОЙНЫ
## ═══════════════════════════════════════════════════════════════════════════
##
## Карта закрыта серой полупрозрачной пеленой; свои юниты и постройки
## раскрывают её вокруг себя. Состояний ДВА, и это принципиально:
##
##   • ВИДНО СЕЙЧАС (lit)  — в радиусе обзора кого-то из своих. Тумана нет,
##                           чужие юниты рисуются.
##   • РАЗВЕДАНО (seen)    — здесь когда-то были. Пелена светлее (рельеф,
##                           лес и постройки помнятся), но ЮНИТОВ не видно:
##                           разведанная земля не показывает, кто там сейчас.
##   • ОСТАЛЬНОЕ           — сплошной туман.
##
## Одного состояния не хватило бы: с чисто накопительной маской однажды
## посещённый угол навсегда показывал бы всё, что там происходит, и «юниты в
## тумане не рисуются» перестало бы что-либо значить.
##
## ── ПОЧЕМУ СЕТКА, А НЕ ПОЛЕ ИСТОЧНИКОВ В ШЕЙДЕРЕ ────────────────────────────
## Передавать в шейдер массив из сотен источников света нельзя: в GL
## Compatibility это упирается и в лимит юниформов, и в стоимость перебора на
## каждый пиксель. Маска — одна текстура MASK_CELL-метрового разрешения,
## пересчитывается на CPU редко (UPDATE_INTERVAL), а шейдер делает одну выборку.
##
## ── СТОИМОСТЬ ПЕРЕСЧЁТА ─────────────────────────────────────────────────────
## Наивный проход «по кругу на каждого юнита» — это πr²/CELL² записей на бойца;
## у лучника с обзором 60 м это ~2800 ячеек, и на сотне бойцов пересчёт
## становится дороже всего остального в кадре. Поэтому источники СХЛОПЫВАЮТСЯ
## по грубой сетке SRC_CELL: в одной ячейке остаётся один круг с наибольшим
## радиусом. Плотный отряд из двадцати человек даёт один-два круга вместо
## двадцати, а результат отличается лишь мягким запасом по краю.

const _UCfg := preload("res://scripts/unit_stats_config.gd")

## Сторона ячейки маски, метры. 1.5 м на карте 260×146 даёт 174×98 — текстура
## всё ещё крошечная (68 КБ на перезаливку), но кромка тумана заметно ровнее:
## на 2 м «лесенка» по краю раскрытого круга читалась с обычного зума
const MASK_CELL := 1.5
## Ширина мягкого края круга обзора, метры. Без неё круг обрывается в один
## пиксель маски, и линейная фильтрация растягивает этот обрыв в ступеньки
## размером с ячейку. Значение по краю пишется рампой, поэтому граница
## размывается предсказуемо и одинаково на любом зуме
const EDGE_FEATHER := 3.0
## Сторона ячейки СХЛОПЫВАНИЯ ИСТОЧНИКОВ (см. «стоимость пересчёта»)
const SRC_CELL := 8.0
## Как часто пересчитывается маска, секунды. Обзор меняется медленно —
## 6-7 раз в секунду глазу неотличимо от покадрового
const UPDATE_INTERVAL := 0.15
## Насколько плоскость тумана поднята над нулём. Рельеф ходит на ±RELIEF_AMP,
## так что смысла в большем нет, а больший подъём дал бы параллакс: камера
## ортографическая под 45°, и туман «съезжал» бы с земли, которую закрывает
const PLANE_Y := 0.05

var _shader: Shader = preload("res://shaders/fog_of_war.gdshader")

var cols: int = 0
var rows: int = 0
var _half_x: float = 0.0
var _half_z: float = 0.0

## Байтовые карты состояний, по ячейке на элемент (0 или 255)
var _lit: PackedByteArray = PackedByteArray()
var _seen: PackedByteArray = PackedByteArray()

var _img: Image = null
var _tex: ImageTexture = null
var _mat: ShaderMaterial = null
var _plane: MeshInstance3D = null

var _timer: float = 0.0
## Круги, раскрытые НАВСЕГДА и независимо от юнитов: стартовая площадка под
## замок открыта ещё до того, как на карте появился хоть кто-то свой
var _permanent: Array = []      # [{"x": float, "z": float, "r": float}, ...]

## Выключатель. Стенды и режимы отладки гасят туман целиком: при false
## is_lit() отвечает true везде, и ни один юнит не прячется
var enabled: bool = true

func setup(half_x: float, half_z: float) -> void:
	_half_x = half_x
	_half_z = half_z
	cols = int(ceil(2.0 * half_x / MASK_CELL))
	rows = int(ceil(2.0 * half_z / MASK_CELL))
	_lit  = PackedByteArray(); _lit.resize(cols * rows)
	_seen = PackedByteArray(); _seen.resize(cols * rows)
	_img = Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 1))
	_tex = ImageTexture.create_from_image(_img)
	_build_plane()
	_upload()

func _build_plane() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0 * _half_x, 2.0 * _half_z)
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("fog_mask", _tex)
	_mat.set_shader_parameter("map_half", Vector2(_half_x, _half_z))
	quad.material = _mat
	_plane = MeshInstance3D.new()
	_plane.name = "FogPlane"
	_plane.mesh = quad
	# QuadMesh лежит в плоскости XY — кладём его на землю
	_plane.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_plane.position = Vector3(0.0, PLANE_Y, 0.0)
	# Рисуется ПОСЛЕ всего наземного: приоритет выше, чем у растительности (0)
	# и бойцов (1), иначе порядок отрисовки решался бы дистанцией до камеры
	_plane.sorting_offset = 0.0
	_mat.render_priority = 8
	# Плоскость размером с карту всегда в кадре — отсечение по AABB только
	# тратило бы время на пересчёт
	_plane.extra_cull_margin = 4096.0
	add_child(_plane)

## Открыть круг НАВСЕГДА. Стартовая площадка под замок раскрыта заранее, ещё
## до появления своих юнитов (заказ владельца: игрок должен сразу видеть
## открытую площадку, а не тыкать замок в темноту)
func add_permanent_reveal(pos: Vector3, radius: float) -> void:
	_permanent.append({"x": pos.x, "z": pos.z, "r": radius})
	_stamp(_lit, pos.x, pos.z, radius)
	_stamp(_seen, pos.x, pos.z, radius)
	_upload()

func clear_permanent() -> void:
	_permanent.clear()

func reset() -> void:
	if _lit.is_empty():
		return
	for i in range(_lit.size()):
		_lit[i] = 0
		_seen[i] = 0
	_permanent.clear()
	_upload()

# ─────────────────────────────────────────────────────────────────────────────
# ЗАПРОСЫ
# ─────────────────────────────────────────────────────────────────────────────

## Индекс ячейки маски по мировой точке; -1 — за картой
func cell_index(x: float, z: float) -> int:
	if cols <= 0:
		return -1
	var cx: int = int((x + _half_x) / MASK_CELL)
	var cz: int = int((z + _half_z) / MASK_CELL)
	if cx < 0 or cz < 0 or cx >= cols or cz >= rows:
		return -1
	return cz * cols + cx

## Просматривается ли точка прямо сейчас. Выключенный туман отвечает true
## везде — так стенды и отладка получают прежнее поведение без ветвлений
## на стороне вызывающего
func is_lit(x: float, z: float) -> bool:
	if not enabled:
		return true
	var i: int = cell_index(x, z)
	if i < 0:
		return false
	return _lit[i] != 0

func is_seen(x: float, z: float) -> bool:
	if not enabled:
		return true
	var i: int = cell_index(x, z)
	if i < 0:
		return false
	return _seen[i] != 0

## Доля раскрытой карты 0..1 — для стендов и отладки
func lit_fraction() -> float:
	if _lit.is_empty():
		return 0.0
	var n := 0
	for i in range(_lit.size()):
		if _lit[i] != 0:
			n += 1
	return float(n) / float(_lit.size())

func seen_fraction() -> float:
	if _seen.is_empty():
		return 0.0
	var n := 0
	for i in range(_seen.size()):
		if _seen[i] != 0:
			n += 1
	return float(n) / float(_seen.size())

# ─────────────────────────────────────────────────────────────────────────────
# ПЕРЕСЧЁТ
# ─────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not enabled or cols <= 0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_INTERVAL
	refresh()

## Пересобрать маску прямо сейчас (стенды зовут напрямую, не дожидаясь таймера)
func refresh() -> void:
	if cols <= 0:
		return
	for i in range(_lit.size()):
		_lit[i] = 0
	var sources: Dictionary = {}
	_collect_unit_sources(sources)
	_collect_building_sources(sources)
	for p in _permanent:
		var d: Dictionary = p
		_stamp(_lit, float(d["x"]), float(d["z"]), float(d["r"]))
	for key in sources.keys():
		var s: Array = sources[key]
		_stamp(_lit, float(s[0]), float(s[1]), float(s[2]))
	# «Разведано» только накапливается: увидели однажды — помним всегда.
	# По МАКСИМУМУ, а не «стало 255»: иначе мягкая кайма круга обзора
	# записывалась бы в разведанное как жёсткий обрыв, и по следу прошедшего
	# отряда тянулась бы полоса со ступенчатым краем
	for i in range(_lit.size()):
		if _lit[i] > _seen[i]:
			_seen[i] = _lit[i]
	_apply_enemy_building_visibility()
	_upload()

## ЧУЖИЕ ПОСТРОЙКИ ПРЯЧУТСЯ ПО «РАЗВЕДАНО», А НЕ ПО «ВИДНО СЕЙЧАС».
##
## Здание неподвижно, поэтому однажды найденная база обязана остаться на карте
## как последнее известное положение — под дымкой, но на месте. Если бы они
## гасились по is_lit(), как бойцы, вражеский замок мигал бы при каждом отходе
## разведчика, и разведка не имела бы смысла вовсе.
##
## Разница между зданиями и бойцами — это ровно то, чего просил владелец:
## база после разведки видна, а перемещения и найм войск под дымкой — нет
## (бойцы гасятся по is_lit в Unit.tick_visual).
##
## Проход дешёвый: зданий на карте десятки, и идёт он на том же такте, что и
## пересчёт маски (UPDATE_INTERVAL), а не в кадре
func _apply_enemy_building_visibility() -> void:
	for group in ["enemy_buildings", "construction_sites"]:
		for b in GameManager.nodes_in_group_cached(String(group)):
			var bl := b as Node3D
			if bl == null or not is_instance_valid(bl):
				continue
			if not bl.has_method("set_fog_hidden"):
				continue
			# Свои стройплощадки прятать не от кого: группа construction_sites
			# общая на обе стороны
			if int(bl.get("faction")) == Constants.FACTION_PLAYER:
				continue
			var gp := bl.global_position
			bl.set_fog_hidden(not is_seen(gp.x, gp.z))

## СХЛОПЫВАНИЕ ИСТОЧНИКОВ ПО ГРУБОЙ СЕТКЕ. Ключ — ячейка SRC_CELL, значение —
## [x, z, r] с НАИБОЛЬШИМ радиусом из попавших в неё. К радиусу добавляется
## половина диагонали ячейки: круг рисуется из её центра, а закрывать обязан
## обзор любого, кто в ней стоит
func _collect_unit_sources(out: Dictionary) -> void:
	var pad: float = SRC_CELL * 0.71
	for u in GameManager._live_units:
		var un := u as Unit
		if un == null or not is_instance_valid(un) or un.is_dead():
			continue
		if un.faction != Constants.FACTION_PLAYER:
			continue
		var gp := un.global_position
		var r: float = _UCfg.vision_radius(un.attack_range)
		_add_source(out, gp.x, gp.z, r + pad)

func _collect_building_sources(out: Dictionary) -> void:
	var pad: float = SRC_CELL * 0.71
	for b in GameManager.nodes_in_group_cached("player_buildings"):
		var bl := b as Node3D
		if bl == null or not is_instance_valid(bl):
			continue
		var gp := bl.global_position
		_add_source(out, gp.x, gp.z, _UCfg.BUILDING_VISION + pad)
	# Стройплощадки — тоже свои глаза: пока замок строится, вокруг него должно
	# быть видно, иначе бригада работает в темноте
	for s in GameManager.nodes_in_group_cached("construction_sites"):
		var st := s as Node3D
		if st == null or not is_instance_valid(st):
			continue
		var gp2 := st.global_position
		_add_source(out, gp2.x, gp2.z, _UCfg.BUILDING_VISION + pad)

func _add_source(out: Dictionary, x: float, z: float, r: float) -> void:
	var kx: int = int(floor(x / SRC_CELL))
	var kz: int = int(floor(z / SRC_CELL))
	var key: int = kz * 100000 + kx
	var prev = out.get(key)
	if prev == null:
		out[key] = [(float(kx) + 0.5) * SRC_CELL, (float(kz) + 0.5) * SRC_CELL, r]
	elif r > float((prev as Array)[2]):
		(prev as Array)[2] = r

## Залить круг в байтовую карту. Обход по строкам с половинной хордой —
## перебирать квадрат и отбрасывать углы было бы в 1.27 раза дороже.
##
## Круги НАКЛАДЫВАЮТСЯ ПО МАКСИМУМУ, а не перезаписью: соседние источники
## перекрываются, и запись «внахлёст» затирала бы яркую середину одного круга
## бледной каймой другого — по стыку шёл бы тёмный шов.
##
## sqrt считается ТОЛЬКО в кайме (внешнее кольцо шириной EDGE_FEATHER):
## внутренность круга — это простое сравнение квадратов, а кайма занимает малую
## долю площади, поэтому мягкий край почти ничего не стоит
func _stamp(map: PackedByteArray, x: float, z: float, radius: float) -> void:
	if radius <= 0.0 or cols <= 0:
		return
	var cx: float = (x + _half_x) / MASK_CELL
	var cz: float = (z + _half_z) / MASK_CELL
	var rc: float = radius / MASK_CELL
	var inner: float = maxf(rc - EDGE_FEATHER / MASK_CELL, 0.0)
	var inner2: float = inner * inner
	var feather: float = maxf(rc - inner, 0.001)
	var z0: int = maxi(int(floor(cz - rc)), 0)
	var z1: int = mini(int(ceil(cz + rc)), rows - 1)
	var r2: float = rc * rc
	for iz in range(z0, z1 + 1):
		var dz: float = float(iz) + 0.5 - cz
		var dz2: float = dz * dz
		var half: float = r2 - dz2
		if half <= 0.0:
			continue
		half = sqrt(half)
		var x0: int = maxi(int(floor(cx - half)), 0)
		var x1: int = mini(int(ceil(cx + half)), cols - 1)
		var base: int = iz * cols
		for ix in range(x0, x1 + 1):
			var dx: float = float(ix) + 0.5 - cx
			var d2: float = dx * dx + dz2
			var v: int = 255
			if d2 > inner2:
				# Кайма: от полной яркости на inner до нуля на rc
				v = int(clampf((rc - sqrt(d2)) / feather, 0.0, 1.0) * 255.0)
			var o: int = base + ix
			if v > map[o]:
				map[o] = v

## Переложить обе карты в текстуру: R — видно сейчас, G — разведано
func _upload() -> void:
	if _img == null or cols <= 0:
		return
	var data := PackedByteArray()
	data.resize(cols * rows * 4)
	for i in range(cols * rows):
		var o: int = i * 4
		data[o]     = _lit[i]
		data[o + 1] = _seen[i]
		data[o + 2] = 0
		data[o + 3] = 255
	_img.set_data(cols, rows, false, Image.FORMAT_RGBA8, data)
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)

## Показать/скрыть саму пелену, не трогая расчёт видимости
func set_plane_visible(v: bool) -> void:
	if _plane != null and is_instance_valid(_plane):
		_plane.visible = v
