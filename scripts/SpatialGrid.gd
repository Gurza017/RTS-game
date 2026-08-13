extends RefCounted
class_name SpatialGrid

## ═══════════════════════════════════════════════════════════════════════════
## ФАСАД НАД ПЛОСКОЙ СЕТКОЙ ЯДРА АРМИИ (Фаза 2)
## ═══════════════════════════════════════════════════════════════════════════
## Здесь ЖИЛО пространственное хеширование бойцов: Dictionary<Vector2i,
## Array[Node3D]> плюс отдельный «грубый слой» присутствия фракций из редких
## клеток по 16 м. Обе структуры удалены — их работу делает плоская сетка в
## scripts/army/ArmySoA.gd:
##   • ячейка — число, а не Vector2i (нет сборки ключа и поиска по словарю);
##   • содержимое ячейки — связный список НОМЕРОВ СТРОК, а не Array объектов
##     (нет аллокаций за кадр);
##   • координаты и сторона берутся из столбцов, а не из свойств узла —
##     global_position у Node3D проверяет и при нужде пересобирает мировую
##     матрицу, и в скане соседей это делалось на КАЖДОГО кандидата;
##   • грубый слой не нужен вовсе: он существовал только потому, что обход
##     словаря был дорог, а обход ячеек плоской сетки дёшев сам по себе.
##
## КЛАСС ОСТАВЛЕН И ИМЕНА МЕТОДОВ НЕ ТРОНУТЫ. На него ссылаются Unit, Worker,
## Castle, Arrow, SelectionManager, GameManager и стенды; менять их всех ради
## переезда хранилища — лишний риск без единой выгоды. Каждый метод здесь —
## одна строчка переадресации.
##
## ЕДИНСТВЕННОЕ СМЫСЛОВОЕ ОТЛИЧИЕ, о котором надо знать: сетка перестраивается
## ОДИН РАЗ ЗА КАДР (GameManager._physics_process → army.rebuild_grid), поэтому
## внутри кадра все видят положения «на начало кадра». Прежде порядок был
## последовательным: кто раньше в реестре, тот двигался первым, и следующие
## видели его уже сдвинувшимся. Одновременность строже и лучше — разбор
## наложения перестал зависеть от порядка в реестре, — а отставание составляет
## один кадр, то есть 6.7 см на скорости 4 м/с при пороге разведения 0.29 м.

## ── УЧЁТ ────────────────────────────────────────────────────────────────────
## Поштучного учёта больше нет: сетка собирается из строк целиком раз в кадр.
## Метод оставлен, потому что его зовут Unit.tick_physics и Worker — там он
## теперь просто ничего не делает
func update(_node: Node3D) -> void:
	pass

## СНЯТЬ С ПОЛЯ. Зовут Castle.absorb_unit (боец ушёл в гарнизон) и
## Unit._exit_tree. Строка помечается «координаты нет», и ближайшая перестройка
## сетки её пропустит; вернётся боец сам, первым же своим тиком
func remove(node: Node3D) -> void:
	var u := node as Unit
	if u == null or u._soa < 0:
		return
	var a = GameManager.army
	a.set_flag(u._soa, a.F_POS_VALID, false)

func remove_all_layers(_id: int) -> void:
	pass

func clear() -> void:
	pass

## ── СКАНЫ ───────────────────────────────────────────────────────────────────

func enemy_near(pos: Vector3, my_faction: int, radius: float) -> bool:
	return GameManager.army.enemy_near(pos.x, pos.z, my_faction, radius)

func allies_count_near(node: Node3D, at: Vector3, radius: float, limit: int) -> int:
	var u := node as Unit
	if u == null or u._soa < 0:
		return 0
	return GameManager.army.allies_count_near(u._soa, at.x, at.z, radius, limit)

func ally_overlap(node: Node3D, at: Vector3, min_dist: float, max_push: float) -> Vector3:
	var u := node as Unit
	if u == null or u._soa < 0:
		return Vector3.ZERO
	return GameManager.army.ally_overlap(u._soa, at.x, at.z, min_dist, max_push)

func enemy_block(node: Node3D, target_pos: Vector3, min_dist: float) -> Vector3:
	var u := node as Unit
	if u == null or u._soa < 0:
		return Vector3.ZERO
	return GameManager.army.enemy_block(u._soa, target_pos.x, target_pos.z, min_dist)

## dir должен быть единичным и лежать в плоскости XZ
func allies_ahead(node: Node3D, dir: Vector3, look: float, half_width: float) -> int:
	var u := node as Unit
	if u == null or u._soa < 0:
		return 0
	return GameManager.army.allies_ahead(u._soa, dir.x, dir.z, look, half_width)

func nearest_enemy_offset(node: Node3D, radius: float) -> Vector3:
	var u := node as Unit
	if u == null or u._soa < 0:
		return Vector3.ZERO
	return GameManager.army.nearest_enemy_offset(u._soa, radius)

## Возвращает [Vector3 позиция, bool нашли] — см. GameManager.squad_enemy_pos:
## по мировой точке каждый боец шеренги считает своё направление сам, поэтому
## кэшируется именно точка, а не смещение
func nearest_enemy_pos(node: Node3D, radius: float) -> Array:
	var off := nearest_enemy_offset(node, radius)
	if off.length_squared() < 1e-6:
		return [Vector3.ZERO, false]
	return [node.global_position + off, true]

func best_enemy(node: Node3D, radius: float, crowd_penalty: float) -> Node3D:
	var u := node as Unit
	if u == null or u._soa < 0:
		return null
	return GameManager.army.best_enemy(u._soa, radius, crowd_penalty)

## Все бойцы в радиусе от точки. Холодный путь (клик, попадание стрелы)
func query_radius(pos: Vector3, radius: float) -> Array:
	return GameManager.army.query_radius(pos.x, pos.z, radius)
