extends RefCounted
class_name SpatialGrid

# Пространственное хеширование юнитов по ячейкам XZ-плоскости.
# Заменяет полный перебор групп при поиске целей, подсчёте рядов фаланги и
# проверке «упёрлись во вражеский строй».

# 1.0: короткие проверки (ряд фаланги, чужой строй — r < 2) сканируют минимум
# ячеек; поиск цели (r до 20) обходит больше, но выполняется редко
# (раз в 0.5 с / при смене цели)
const CELL_SIZE := 1.0

## ПУСТЫЕ ЯЧЕЙКИ ПРОПУСКАЮТСЯ БЕЗ АЛЛОКАЦИИ. Раньше здесь везде стояло
## `_cells.get(key, [])`: GDScript вычисляет значение по умолчанию НА КАЖДОМ
## вызове, то есть создавал новый пустой Array на каждую просмотренную ячейку —
## и на попадании тоже. Скан чужого строя на марше обходит 9-25 ячеек на бойца
## за кадр, на 810 моделях это десятки тысяч мусорных массивов в кадр, за
## которые потом платит сборщик. `get(key)` без второго аргумента возвращает
## null и ничего не создаёт (замер: ветка mb_enemyblock — 4.0 мкс на юнита)

var _cells: Dictionary = {}      # Vector2i -> Array[Node3D]
var _node_cell: Dictionary = {}  # instance_id -> Vector2i

# ─────────────────────────────────────────────────────────────────────────────
# ГРУБЫЙ СЛОЙ ПРИСУТСТВИЯ ФРАКЦИЙ
#
# Зачем: enemy_block() зовётся на КАЖДЫЙ шаг КАЖДОГО юнита и обходит 9-25
# ячеек по метру, отсеивая всех найденных по фракции. На марше своим же строем
# эти ячейки битком набиты СВОИМИ, и вся работа уходит впустую: замер показал
# 3.9 мкс на бойца в кадр при том, что врагов на карте не было вовсе.
#
# Здесь тот же вопрос решается одной проверкой словаря: карта поделена на
# редкие клетки по COARSE_CELL метров, и на каждую известно, сколько бойцов
# КАЖДОЙ стороны в ней стоит. Пока в округе нет ни одного чужого, подробный
# скан не запускается вовсе.
#
# Фракции ровно две (Constants.FACTION_PLAYER = 0, FACTION_ENEMY = 1), поэтому
# счётчик — пара чисел, а не словарь: PackedInt32Array из двух элементов.
const COARSE_CELL := 16.0

var _coarse: Dictionary = {}       # Vector2i -> PackedInt32Array[2] (счёт по фракциям)
var _node_coarse: Dictionary = {}  # instance_id -> Vector2i

func _coarse_key(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / COARSE_CELL), floori(pos.z / COARSE_CELL))

func _coarse_add(key: Vector2i, faction: int, delta: int) -> void:
	if faction < 0 or faction > 1:
		return
	var counts: Variant = _coarse.get(key)
	if counts == null:
		if delta <= 0:
			return
		var fresh := PackedInt32Array([0, 0])
		fresh[faction] = delta
		_coarse[key] = fresh
		return
	var arr: PackedInt32Array = counts
	arr[faction] = maxi(0, arr[faction] + delta)
	if arr[0] == 0 and arr[1] == 0:
		_coarse.erase(key)
	else:
		_coarse[key] = arr

## ЕСТЬ ЛИ ХОТЬ ОДИН БОЕЦ ЧУЖОЙ СТОРОНЫ в окрестности radius от точки.
## Дешёвый предварительный отсев для enemy_block: смотрит редкие клетки по
## COARSE_CELL метров, а не каждого соседа поимённо
func enemy_near(pos: Vector3, my_faction: int, radius: float) -> bool:
	if _coarse.is_empty():
		return false
	var foe: int = 1 - my_faction
	if foe < 0 or foe > 1:
		return true      # неизвестная сторона — честно идём в подробный скан
	# Ключи клеток — прямо здесь: _coarse_key это ещё два вызова функции и две
	# сборки Vector3 на каждый шаг каждого идущего бойца, а зовётся отсев из
	# enemy_block, то есть в самом горячем месте всего марша
	var inv: float = 1.0 / COARSE_CELL
	var cx0: int = floori((pos.x - radius) * inv)
	var cz0: int = floori((pos.z - radius) * inv)
	var cx1: int = floori((pos.x + radius) * inv)
	var cz1: int = floori((pos.z + radius) * inv)
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var counts: Variant = _coarse.get(Vector2i(cx, cz))
			if counts == null:
				continue
			if (counts as PackedInt32Array)[foe] > 0:
				return true
	return false

func _cell_key(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.z / CELL_SIZE))

const _NO_CELL := Vector2i(2147483647, 2147483647)

func update(node: Node3D) -> void:
	var key := _cell_key(node.global_position)
	var id := node.get_instance_id()
	if _node_cell.get(id, _NO_CELL) == key:
		return
	_remove_from_cell(node, id)
	if not _cells.has(key):
		_cells[key] = []
	(_cells[key] as Array).append(node)
	_node_cell[id] = key
	# Грубый слой перекладывается ТОЛЬКО при смене редкой клетки: она в 16 раз
	# крупнее обычной, и переход через её границу — событие редкое даже на марше
	var ckey := _coarse_key(node.global_position)
	var known: Variant = _node_coarse.get(id)
	if known == null or Vector2i((known as Vector3i).x, (known as Vector3i).y) != ckey:
		_coarse_move(node, id, ckey)

## Клетка И сторона хранятся вместе (x, z, фракция): снимать счётчик приходится
## и в remove(), где спрашивать фракцию у выбывшего узла уже поздно
func _coarse_move(node: Node3D, id: int, ckey: Vector2i) -> void:
	var faction: int = node.faction
	_coarse_drop(id)
	_coarse_add(ckey, faction, 1)
	_node_coarse[id] = Vector3i(ckey.x, ckey.y, faction)

func _coarse_drop(id: int) -> void:
	var old: Variant = _node_coarse.get(id)
	if old == null:
		return
	var o: Vector3i = old
	_coarse_add(Vector2i(o.x, o.y), o.z, -1)
	_node_coarse.erase(id)

## Сколько СВОИХ рядом с точкой, но НЕ БОЛЬШЕ limit. Без аллокации массива:
## эта проверка идёт в свалке сотнями раз за кадр, а query_radius() каждый раз
## отдавал новый Array — на тысяче бойцов это сотни мусорных массивов в кадр
func allies_count_near(node: Node3D, at: Vector3, radius: float, limit: int) -> int:
	var self_u := node as Unit
	if self_u == null:
		return 0
	var min_c := _cell_key(Vector3(at.x - radius, 0.0, at.z - radius))
	var max_c := _cell_key(Vector3(at.x + radius, 0.0, at.z + radius))
	var r_sq := radius * radius
	var found := 0
	for cx in range(min_c.x, max_c.x + 1):
		for cz in range(min_c.y, max_c.y + 1):
			var cell: Variant = _cells.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for n in (cell as Array):
				if n == node:
					continue
				var u := n as Unit
				if u == null or u.faction != self_u.faction or u.is_dead():
					continue
				var dx: float = at.x - u.global_position.x
				var dz: float = at.z - u.global_position.z
				if dx * dx + dz * dz >= r_sq:
					continue
				found += 1
				if found >= limit:
					return found
	return found

## ═══════════════════════════════════════════════════════════════════════════
## ЛИЧНЫЙ ОБЪЁМ: НА СКОЛЬКО НАДО ОТОЙТИ ОТ СЛИПШИХСЯ СОЮЗНИКОВ
## ═══════════════════════════════════════════════════════════════════════════
## Возвращает суммарное смещение (по XZ), которое разведёт бойца с союзниками,
## подошедшими ближе min_dist. Vector3.ZERO — расходиться не с кем.
##
## ЭТО НЕ СИЛА, А ПОПРАВКА ПОЛОЖЕНИЯ. Разница с вырезанным когда-то
## расталкиванием принципиальная: там были скорости, радиусы уступания и
## возврат в слот, то есть ВСТРЕЧНЫЕ воздействия — они гасили друг друга и
## давали вечное дрожание. Здесь поправка МОНОТОННА (только наружу, только
## пока есть наложение) и её никто не отменяет: как только расстояние набрано,
## она равна нулю и строй замирает. Стенд qa_crowd A3 проверяет именно это.
##
## Пробовалось сначала ОДНОСТОРОННЕЕ разведение (расходится только тот, у кого
## instance_id больше) — оно оказалось хуже: в плотной куче бойцы с малыми id
## стоят намертво, и остальным просто некуда деться (замер: 24 человека
## сходились до 0.13-0.15 м при пороге 0.29 и там и застревали). Двустороннее
## разведение раздувает кучу целиком и доводит зазор до нормы.
##
## Без аллокаций и без вызовов наружу: числа считаются здесь же, наружу уходит
## один Vector3. Итог обрезается по max_push — за одну проверку боец сдвигается
## на сантиметры, а не телепортируется из свалки.
func ally_overlap(node: Node3D, at: Vector3, min_dist: float, max_push: float) -> Vector3:
	var self_u := node as Unit
	if self_u == null:
		return Vector3.ZERO
	var my_id: int = node.get_instance_id()
	var my_faction: int = self_u.faction
	var min_c := _cell_key(Vector3(at.x - min_dist, 0.0, at.z - min_dist))
	var max_c := _cell_key(Vector3(at.x + min_dist, 0.0, at.z + min_dist))
	var d_sq: float = min_dist * min_dist
	var px: float = 0.0
	var pz: float = 0.0
	for cx in range(min_c.x, max_c.x + 1):
		for cz in range(min_c.y, max_c.y + 1):
			var cell: Variant = _cells.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for n in (cell as Array):
				if n == node:
					continue
				var u := n as Unit
				if u == null or u.faction != my_faction or u.is_dead():
					continue
				var up := u.global_position
				var dx: float = at.x - up.x
				var dz: float = at.z - up.z
				var dd: float = dx * dx + dz * dz
				if dd >= d_sq:
					continue
				if dd < 1e-8:
					# РОВНО В ОДНОЙ ТОЧКЕ (так спавнится отряд из здания и так
					# сходятся отряды на одну цель). Направление обязано быть
					# СВОИМ У КАЖДОГО: пара бит id давала всего четыре стороны,
					# бойцы одной четвёрки уезжали строго вместе, оставались
					# наложенными друг на друга и продолжали получать поправку
					# от чужих — куча не расходилась, а разъезжалась лучами по
					# десяткам метров (замер qa_crowd: радиус 78 м). Угол из id
					# даёт каждому свой луч, и второй же такт делает расстояние
					# нормальным
					var ang: float = float(my_id % 251) * (TAU / 251.0)
					dx = cos(ang) * 0.01
					dz = sin(ang) * 0.01
					dd = dx * dx + dz * dz
				var d: float = sqrt(dd)
				# Доля недостающего расстояния, вынесенная на единичный вектор
				var need: float = (min_dist - d) / d
				px += dx * need
				pz += dz * need
	var plen_sq: float = px * px + pz * pz
	if plen_sq <= 1e-10:
		return Vector3.ZERO
	if plen_sq > max_push * max_push:
		var k: float = max_push / sqrt(plen_sq)
		px *= k
		pz *= k
	return Vector3(px, 0.0, pz)

func remove(node: Node3D) -> void:
	var id := node.get_instance_id()
	_remove_from_cell(node, id)
	remove_all_layers(id)

func _remove_from_cell(node: Node3D, id: int) -> void:
	if not _node_cell.has(id):
		return
	var old_key: Vector2i = _node_cell[id]
	if _cells.has(old_key):
		(_cells[old_key] as Array).erase(node)
	_node_cell.erase(id)

## Полное снятие с учёта. Грубый слой чистится ТОЛЬКО здесь, а не в
## _remove_from_cell: тот зовётся и из update() при обычном переходе между
## ячейками по метру, где боец с карты никуда не делся
func remove_all_layers(id: int) -> void:
	_coarse_drop(id)

# Все зарегистрированные узлы в радиусе radius от pos (по XZ)
func query_radius(pos: Vector3, radius: float) -> Array:
	var result: Array = []
	var min_c := _cell_key(pos - Vector3(radius, 0.0, radius))
	var max_c := _cell_key(pos + Vector3(radius, 0.0, radius))
	var r_sq := radius * radius
	for cx in range(min_c.x, max_c.x + 1):
		for cz in range(min_c.y, max_c.y + 1):
			var cell: Variant = _cells.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for n in (cell as Array):
				if not is_instance_valid(n):
					continue
				var np: Vector3 = (n as Node3D).global_position
				var dx := pos.x - np.x
				var dz := pos.z - np.z
				if dx * dx + dz * dz <= r_sq:
					result.append(n)
	return result

# ─────────────────────────────────────────────────────────────────────────────
# ЗДЕСЬ БЫЛО РАСТАЛКИВАНИЕ СОЮЗНИКОВ (separation_push) — УДАЛЕНО
#
# Личное пространство пробовали делать разным по типу соседа: свой по отряду
# близко, проходящий мимо союзник далеко (коридор для сквозного прохода). Ни
# один набор дистанций так и не заработал: интервал слотов строя меньше любого
# разумного личного пространства, поэтому правильно построенная шеренга сама
# себя расталкивала, а возврат в строй тянул бойцов обратно — отряд вечно
# дрожал на месте. Ровно то, на что жаловался игрок.
#
# Теперь союзники НЕ ТОЛКАЮТ ДРУГ ДРУГА ВООБЩЕ и свободно перекрываются
# (см. шапку Unit.gd). Раздвигать ряды под проходящего не нужно — он идёт
# насквозь. Из горячего пути ушёл вызов на каждого юнита каждый физ. кадр.
# ─────────────────────────────────────────────────────────────────────────────

# Проверка «упёрлись во вражеский строй»: если в точке target_pos ближе
# min_dist есть юнит ЧУЖОЙ фракции — возвращает суммарную нормаль ОТ него
# к нам (по ней вызывающий срезает составляющую шага внутрь строя).
# Vector3.ZERO — путь свободен.
#
# Свои не блокируют — и не расталкиваются: союзники проходят друг сквозь друга.
# Непроходим ТОЛЬКО чужой строй, и это про бой, а не про толкотню.
func enemy_block(node: Node3D, target_pos: Vector3, min_dist: float) -> Vector3:
	var my_faction: int = node.faction
	# ПРЕДВАРИТЕЛЬНЫЙ ОТСЕВ ПО ГРУБОМУ СЛОЮ. Марш по своей половине карты — это
	# сотни бойцов, каждый кадр перебирающих плотно набитые СВОИМИ ячейки ради
	# ответа «чужих нет». Одна проверка редкой клетки отвечает на это сразу
	if not enemy_near(target_pos, my_faction, min_dist):
		return Vector3.ZERO
	var min_c := _cell_key(Vector3(target_pos.x - min_dist, 0.0, target_pos.z - min_dist))
	var max_c := _cell_key(Vector3(target_pos.x + min_dist, 0.0, target_pos.z + min_dist))
	var d_sq_limit := min_dist * min_dist
	var normal := Vector3.ZERO
	for cx in range(min_c.x, max_c.x + 1):
		for cz in range(min_c.y, max_c.y + 1):
			var cell: Variant = _cells.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for n in (cell as Array):
				if n == node:
					continue
				if n.faction == my_faction:
					continue
				if n.is_dead():
					continue
				var np: Vector3 = (n as Node3D).global_position
				var dx := target_pos.x - np.x
				var dz := target_pos.z - np.z
				var d_sq := dx * dx + dz * dz
				if d_sq >= d_sq_limit:
					continue
				if d_sq < 0.0001:
					normal += Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
				else:
					var inv := 1.0 / sqrt(d_sq)
					normal.x += dx * inv
					normal.z += dz * inv
	return normal

# СКОЛЬКО СВОИХ СТОИТ ПРЯМО ПЕРЕДО МНОЙ («в моей колонне»).
# По этому числу фаланга определяет фактический ряд бойца: 0 своих впереди —
# он первая шеренга, 1 — вторая, 2 и больше — задние ряды. Когда передний
# погибает, счётчик у стоящего сзади падает сам, и тот становится передовым.
#
# dir должен быть единичным и лежать в плоскости XZ.
# look — как далеко вперёд смотрим, half_width — половина ширины «колонны».
# Без аллокаций: обход ячеек напрямую, как и в allies_count_near.
func allies_ahead(node: Node3D, dir: Vector3, look: float, half_width: float) -> int:
	var my_faction: int = node.faction
	var pos := node.global_position
	# Прямоугольник поиска описываем квадратом вокруг середины отрезка
	var cx0 := pos.x + dir.x * look * 0.5
	var cz0 := pos.z + dir.z * look * 0.5
	var r: float = look * 0.5 + half_width + CELL_SIZE
	var min_c := _cell_key(Vector3(cx0 - r, 0.0, cz0 - r))
	var max_c := _cell_key(Vector3(cx0 + r, 0.0, cz0 + r))
	var count := 0
	for cx in range(min_c.x, max_c.x + 1):
		for cz in range(min_c.y, max_c.y + 1):
			var cell: Variant = _cells.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for n in (cell as Array):
				if n == node:
					continue
				if n.faction != my_faction:
					continue
				if n.is_dead():
					continue
				var np: Vector3 = (n as Node3D).global_position
				var dx := np.x - pos.x
				var dz := np.z - pos.z
				# Проекция на направление взгляда и боковое отклонение
				var along := dx * dir.x + dz * dir.z
				if along <= 0.12 or along > look:
					continue
				var lat := absf(dx * -dir.z + dz * dir.x)
				if lat > half_width:
					continue
				count += 1
	return count

# СМЕЩЕНИЕ ДО ГЕОМЕТРИЧЕСКИ БЛИЖАЙШЕГО ВРАГА (Vector3.ZERO — врагов нет).
# ВАЖНО: без «штрафа за занятость» цели, в отличие от Unit._find_nearest_enemy_in_range.
# Тот распределяет бойцов по целям и намеренно уводит выбор на дальнего врага —
# для ВЫБОРА ЦЕЛИ это правильно, а как «куда смотрит строй» давало разнобой:
# соседи в одной шеренге получали разные направления, и ряды считались вкривь.
# Без аллокаций.
func nearest_enemy_offset(node: Node3D, radius: float) -> Vector3:
	var my_faction: int = node.faction
	var pos := node.global_position
	var min_c := _cell_key(Vector3(pos.x - radius, 0.0, pos.z - radius))
	var max_c := _cell_key(Vector3(pos.x + radius, 0.0, pos.z + radius))
	var best_sq := radius * radius
	var best := Vector3.ZERO
	for cx in range(min_c.x, max_c.x + 1):
		for cz in range(min_c.y, max_c.y + 1):
			var cell: Variant = _cells.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for n in (cell as Array):
				if n == node:
					continue
				if n.faction == my_faction:
					continue
				if n.is_dead():
					continue
				var np: Vector3 = (n as Node3D).global_position
				var dx := np.x - pos.x
				var dz := np.z - pos.z
				var d_sq := dx * dx + dz * dz
				if d_sq < best_sq:
					best_sq = d_sq
					best = Vector3(dx, 0.0, dz)
	return best

# ЛУЧШАЯ ВРАЖЕСКАЯ ЦЕЛЬ В РАДИУСЕ — БЕЗ АЛЛОКАЦИЙ.
#
# Раньше Unit._find_nearest_enemy_in_range() звал query_radius(), а тот
# СОБИРАЕТ НОВЫЙ Array из всех соседей подряд — и своих, и чужих, и мёртвых.
# При радиусе лучника (20 м) и ячейке 1 м это обход 1681 ячейки с добавлением
# в массив каждого попавшегося. В свалке на 1200 моделей поиск цели идёт
# сотни раз в секунду, и каждый такой вызов оставлял после себя мусорный
# массив на десятки элементов — сборщик потом честно за это платил.
#
# Здесь тот же отбор сделан «на лету»: кандидаты не накапливаются, наружу
# уходит один-единственный победитель.
#
# ОТБОР ТОТ ЖЕ, ЧТО И БЫЛ: к дистанции добавляется штраф за каждого бойца,
# уже атакующего эту цель (crowd_penalty). Так линия разбирает противников
# почти один в один, а не сваливается толпой на ближайшего.
func best_enemy(node: Node3D, radius: float, crowd_penalty: float) -> Node3D:
	var self_u := node as Unit
	if self_u == null:
		return null
	var my_faction: int = self_u.faction
	var pos := node.global_position
	var min_c := _cell_key(Vector3(pos.x - radius, 0.0, pos.z - radius))
	var max_c := _cell_key(Vector3(pos.x + radius, 0.0, pos.z + radius))
	var r_sq := radius * radius
	var best: Node3D = null
	var best_score := INF
	for cx in range(min_c.x, max_c.x + 1):
		for cz in range(min_c.y, max_c.y + 1):
			var cell: Variant = _cells.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for n in (cell as Array):
				if n == node:
					continue
				var u := n as Unit
				if u == null or u.faction == my_faction or u.is_dead():
					continue
				var np: Vector3 = u.global_position
				var dx := pos.x - np.x
				var dz := pos.z - np.z
				var d_sq := dx * dx + dz * dz
				if d_sq > r_sq:
					continue
				# Корень берём только у тех, кто уже прошёл отбор по радиусу
				var score: float = sqrt(d_sq) + float(u.attackers) * crowd_penalty
				if score < best_score:
					best_score = score
					best = u
	return best

## ПОЗИЦИЯ ближайшего врага (а не смещение до него). Нужна отдельно от
## nearest_enemy_offset ради КЭША НА ОТРЯД: смещение годится только тому, кто
## его запросил, а по мировой точке каждый боец шеренги считает своё
## направление сам. Пустая позиция обозначена вторым значением false.
## Возвращает [Vector3 позиция, bool нашли]
func nearest_enemy_pos(node: Node3D, radius: float) -> Array:
	var off := nearest_enemy_offset(node, radius)
	if off.length_squared() < 1e-6:
		return [Vector3.ZERO, false]
	return [node.global_position + off, true]

func clear() -> void:
	_cells.clear()
	_node_cell.clear()
	_coarse.clear()
	_node_coarse.clear()
