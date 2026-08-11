## БАЗОВЫЙ КЛАСС ПОСТРОЕНИЙ ("Combined Arms" и будущие типы стройов).
##
## Сейчас отвечает ровно за одну задачу — разложить смешанное по типам войск
## выделение на ЭШЕЛОНЫ (ranks), а не заставлять SelectionManager решать это
## инлайн. Раскладка бойцов ВНУТРИ эшелона (шеренги/ряды по отрядам) остаётся
## за SelectionManager._block_formation_slots — он уже умеет секции по отрядам
## и его незачем дублировать здесь.
##
## Файл НАМЕРЕННО без class_name (как ConstructionSite.gd/FormationPreview.gd):
## подключается через preload()/load(), поэтому не зависит от того, попала ли
## новая запись в global_script_class_cache.cfg.
##
## РАСШИРЕНИЕ: новый тип строя добавляется новой static-функцией здесь и одной
## веткой выбора на стороне вызывающего кода — сам класс ничего не хранит и не
## обращается к сцене, поэтому тестировать его можно без запуска игры.

## Порядок эшелонов "спереди назад" (вдоль направления атаки):
## копейщики держат фронт, лучники бьют из-за их спин, тяжёлая пехота — резерв.
## Типы, которых здесь нет (рабочие и т.п.), уходят одним общим эшелоном в тыл
const RANK_ORDER := ["spearman", "archer", "warrior"]

## Тип бойца для целей построения. squad_id не нужен — stat_id боец несёт
## сам по себе (см. Unit.gd), поэтому раскладка работает и для бойцов вне
## отряда
static func unit_type(u) -> String:
	if u == null or not is_instance_valid(u) or not (u is Unit):
		return ""
	return String((u as Unit).stat_id)

## Выделение содержит больше одного типа войск?
static func is_mixed(movable: Array) -> bool:
	var seen: Dictionary = {}
	for u in movable:
		seen[unit_type(u)] = true
		if seen.size() > 1:
			return true
	return false

## Разбить выделение на эшелоны в порядке RANK_ORDER (+ общий "прочие" эшелон
## последним). Порядок бойцов ВНУТРИ эшелона — порядок появления в movable,
## что совпадает с порядком отрядов в выделении (симметрично _split_into_blocks)
static func group_by_rank(movable: Array) -> Array:
	var buckets: Dictionary = {}
	var other: Array = []
	for u in movable:
		var t := unit_type(u)
		if t in RANK_ORDER:
			if not buckets.has(t):
				buckets[t] = []
			(buckets[t] as Array).append(u)
		else:
			other.append(u)
	var out: Array = []
	for t in RANK_ORDER:
		if buckets.has(t):
			out.append(buckets[t])
	if not other.is_empty():
		out.append(other)
	return out
