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

## ── ПРЯМАЯ ССЫЛКА НА СОЛВЕР ────────────────────────────────────────────────
## Каждый скан шёл тремя вызовами: Unit → SpatialGrid → ArmySoA → C#. Два из
## них — чистая переадресация, и на горячем пути (скан соседей идёт на каждого
## бойца в каждом кадре) они стоят столько же, сколько сам скан. Ссылка берётся
## лениво: автозагрузка GameManager создаёт ядро в своём объявлении полей, и на
## момент первого обращения оно уже есть
var _c = null

func _core():
	if _c == null:
		_c = GameManager.army.core()
	return _c

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
	_core().SetFlag(u._soa, 1, false)   # 1 = F_POS_VALID

func remove_all_layers(_id: int) -> void:
	pass

func clear() -> void:
	pass

## ── СКАНЫ ───────────────────────────────────────────────────────────────────

func enemy_near(pos: Vector3, my_faction: int, radius: float) -> bool:
	return _core().EnemyNear(pos.x, pos.z, my_faction, radius)

func allies_count_near(node: Node3D, at: Vector3, radius: float, limit: int) -> int:
	var u := node as Unit
	if u == null or u._soa < 0:
		return 0
	return _core().AlliesCountNear(u._soa, at.x, at.z, radius, limit)

func ally_overlap(node: Node3D, at: Vector3, min_dist: float, max_push: float) -> Vector3:
	var u := node as Unit
	if u == null or u._soa < 0:
		return Vector3.ZERO
	return _core().AllyOverlap(u._soa, at.x, at.z, min_dist, max_push)

func enemy_block(node: Node3D, target_pos: Vector3, min_dist: float) -> Vector3:
	var u := node as Unit
	if u == null or u._soa < 0:
		return Vector3.ZERO
	return _core().EnemyBlock(u._soa, target_pos.x, target_pos.z, min_dist)

## dir должен быть единичным и лежать в плоскости XZ
func allies_ahead(node: Node3D, dir: Vector3, look: float, half_width: float) -> int:
	var u := node as Unit
	if u == null or u._soa < 0:
		return 0
	return _core().AlliesAhead(u._soa, dir.x, dir.z, look, half_width)

func nearest_enemy_offset(node: Node3D, radius: float) -> Vector3:
	var u := node as Unit
	if u == null or u._soa < 0:
		return Vector3.ZERO
	return _core().NearestEnemyOffset(u._soa, radius)

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
	return _core().BestEnemy(u._soa, radius, crowd_penalty)

## Все бойцы в радиусе от точки. Холодный путь (клик, попадание стрелы)
func query_radius(pos: Vector3, radius: float) -> Array:
	return _core().QueryRadius(pos.x, pos.z, radius)
