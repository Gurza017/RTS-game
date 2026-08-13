extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_order — СТРОЙ НЕ ВЫВОРАЧИВАЕТСЯ НАИЗНАНКУ
## ═══════════════════════════════════════════════════════════════════════════
## Слоты раскладываются строго по индексу, а бойцы приходили в этот список в
## порядке реестра отряда — связи с тем, кто где стоит, не было. Боец из задней
## шеренги получал слот в передней и шёл туда СКВОЗЬ свой отряд.
##
##   A ШЕРЕНГИ ПКМ    — кто стоял впереди, тот впереди и встанет; пути бойцов
##                      не пересекаются.
##   B СПАУН          — шеренга, вышедшая первой, не пропускает следующие
##                      сквозь себя.
##   C ГРУППА ОТРЯДОВ — ячейки сетки достаются отрядам по их фактическому
##                      положению, а не по порядку в выделении.
##
## Мера пересечения одна на все разделы: доля пар, у которых ОТНОСИТЕЛЬНЫЙ
## порядок вдоль курса поменялся на противоположный. Ноль — строй сдвинулся
## параллельно; заметная доля — он вывернулся.
##
## Запуск: godot --headless --path . res://qa_order/Test.tscn

const SPEARMAN := preload("res://scenes/units/Spearman.tscn")

var main = null
var sel = null
var _pass := 0
var _fail := 0
var _trash: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _squad(fac: int, at: Vector3, n: int, cols: int) -> int:
	var sid: int = GameManager.new_squad(fac, "spearman")
	for i in range(n):
		var u: Unit = SPEARMAN.instantiate()
		u.faction = fac
		main.world_add(u)
		var p := Vector3(at.x + float(i % cols) * 1.2, 0.0, at.z + float(i / cols) * 1.2)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		GameManager.add_to_squad(sid, u)
		_trash.append(u)
	return sid

func _live(sid: int) -> Array:
	var out: Array = []
	for m in GameManager.squad_members(sid):
		var u := m as Unit
		if u != null and is_instance_valid(u) and not u.is_dead():
			out.append(u)
	return out

## ДОЛЯ ПЕРЕВЁРНУТЫХ ПАР вдоль оси `axis`: для каждой пары бойцов сравниваем,
## сохранился ли их относительный порядок между «где стояли» и «куда идут».
## Это и есть формальная запись «строй не выворачивается»
## `min_sep` — с какого расстояния пара вообще задаёт порядок. Параметр, а не
## константа, и это выяснилось замером: у бойцов внутри строя значим уже
## полуметровый разнос, а у ОТРЯДОВ центры масс стоят в шестнадцати метрах друг
## от друга, и полуметровая разница между ними — это шум формы, а не порядок.
## С общим порогом такие пары считались упорядоченными, после переноса
## расходились на микроны со случайным знаком и давали ложные 13 % «выворота»
func _inversions(units: Array, from: Array, to: Array, axis: Vector3,
		min_sep: float = 0.4) -> float:
	var n: int = units.size()
	if n < 2:
		return 0.0
	var bad := 0
	var total := 0
	for i in range(n):
		for j in range(i + 1, n):
			var a0: float = (from[i] as Vector3).dot(axis)
			var b0: float = (from[j] as Vector3).dot(axis)
			var a1: float = (to[i] as Vector3).dot(axis)
			var b1: float = (to[j] as Vector3).dot(axis)
			# Пары, стоявшие на одной глубине, порядка не задают — пропускаем
			if absf(a0 - b0) < min_sep:
				continue
			total += 1
			if (a0 - b0) * (a1 - b1) < 0.0:
				bad += 1
	if total == 0:
		return 0.0
	return float(bad) / float(total)

func _sweep() -> void:
	# ТОЛЬКО БОЙЦЫ. В мусоре лежит и барак, а remove_from_squad читает squad_id,
	# которого у постройки нет: обращение падает, корутина _run обрывается на
	# середине, quit() не вызывается — и стенд висит до таймаута, ничего не
	# напечатав. Час на диагностику, одна строка на починку
	for n in _trash:
		if is_instance_valid(n) and n is Unit:
			GameManager.remove_from_squad(n as Unit)
	for n in _trash:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_trash.clear()
	await frames(8)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	sel = main.selection_manager if main.get("selection_manager") != null else null
	if sel == null:
		for c in main.get_children():
			if c is SelectionManager:
				sel = c
				break
	await frames(3)
	print("\n  SelectionManager найден: %s" % str(sel != null))

	# ── A. РАСТЯГИВАНИЕ ПКМ ──────────────────────────────────────────────────
	print("\n───── A. РАСТЯНУТАЯ ЛИНИЯ НЕ ВЫВОРАЧИВАЕТ СТРОЙ ─────")
	# Отряд стоит квадратом 5×4 и получает линию ПЕРЕД собой: курс на +Z
	var sid := _squad(Constants.FACTION_PLAYER, Vector3(-40, 0, -40), 20, 5)
	await frames(6)
	var men: Array = _live(sid)
	var before: Array = []
	for u in men:
		before.append((u as Node3D).global_position)
	# Линия рисуется поперёк курса, впереди отряда
	var line_start := Vector3(-44, 0, -25)
	var line_end   := Vector3(-32, 0, -25)
	var plan: Dictionary = sel._block_formation_slots(line_start, line_end, men)
	var flat: Array  = plan["flat"]
	var slots: Array = plan["slots"]
	verdict("A1 план покрывает весь отряд",
		flat.size() == men.size() and slots.size() >= men.size(),
		"бойцов %d, мест %d, порядок %d" % [men.size(), slots.size(), flat.size()])
	# Сверяем в порядке ПЛАНА: from[i] — где стоит flat[i], to[i] — куда идёт
	var f_from: Array = []
	var f_to: Array = []
	for i in range(flat.size()):
		f_from.append((flat[i] as Node3D).global_position)
		f_to.append(slots[i])
	var line_dir: Vector3 = (line_end - line_start).normalized()
	var facing := Vector3(line_dir.z, 0.0, -line_dir.x)
	var inv_depth: float = _inversions(flat, f_from, f_to, facing)
	var inv_side: float  = _inversions(flat, f_from, f_to, line_dir)
	print("  перевёрнутых пар: по глубине %.0f%%, по фронту %.0f%%"
		% [inv_depth * 100.0, inv_side * 100.0])
	verdict("A2 передние остаются впереди", inv_depth < 0.05,
		"перевёрнуто %.0f%% пар по глубине" % (inv_depth * 100.0))
	verdict("A3 фланги не меняются местами", inv_side < 0.05,
		"перевёрнуто %.0f%% пар по фронту" % (inv_side * 100.0))
	await _sweep()

	# ── B. СПАУН ИЗ БАРАКА ───────────────────────────────────────────────────
	print("\n───── B. ВЫХОД ИЗ БАРАКА ─────")
	var b: Building = Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(60, 0, 40)
	_trash.append(b)
	await frames(4)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	var gate: Vector3 = b._gate_position()
	var exit_dir: Vector3 = b.spawn_offset
	exit_dir.y = 0.0
	exit_dir = exit_dir.normalized()
	var seen: Array = get_tree().get_nodes_in_group("player_units").duplicate()
	b.squad_size = 12
	b.queue_unit("spearman", {}, 0.01)
	if not b.production_queue.is_empty():
		(b.production_queue[0] as Dictionary)["time"] = 0.01
	# Собираем бойцов В ПОРЯДКЕ ВЫХОДА и их назначенные точки
	var out_order: Array = []
	var out_goal: Array = []
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and out_order.size() < 12:
		await get_tree().physics_frame
		for nd in get_tree().get_nodes_in_group("player_units"):
			if nd in seen:
				continue
			seen.append(nd)
			_trash.append(nd)
			out_order.append(nd)
			out_goal.append((nd as Unit).move_target)
	print("  вышло %d бойцов" % out_order.size())
	# ГЛУБИНА ЦЕЛИ ОБЯЗАНА УБЫВАТЬ С ПОРЯДКОМ ВЫХОДА: первый вышедший идёт
	# дальше всех, каждый следующий — ближе, и никто никого не обгоняет
	var bad_pairs := 0
	var checked := 0
	for i in range(out_order.size()):
		for j in range(i + 1, out_order.size()):
			var di: float = (out_goal[i] as Vector3 - gate).dot(exit_dir)
			var dj: float = (out_goal[j] as Vector3 - gate).dot(exit_dir)
			if absf(di - dj) < 0.3:
				continue
			checked += 1
			if dj > di:
				bad_pairs += 1
	verdict("B1 вышел раньше — стоит глубже", checked > 0 and bad_pairs == 0,
		"нарушений %d из %d пар" % [bad_pairs, checked])
	await _sweep()

	# ── C. ГРУППА ОТРЯДОВ ────────────────────────────────────────────────────
	print("\n───── C. ЯЧЕЙКИ ДОСТАЮТСЯ ПО ПОЛОЖЕНИЮ, А НЕ ПО ПОРЯДКУ ─────")
	# ФОРМА ГРУППЫ ПОДОБРАНА ПОД СЕТКУ — и это не подгонка, а единственное
	# условие, при котором «без перекрещивания» вообще возможно. Шесть отрядов,
	# выстроенных в ОДНУ линию, в сетку 3x2 без перестановок не ложатся никак:
	# трое обязаны уйти во второй ряд, и какая-то пара поменяется местами
	# поперёк курса по чистой геометрии. Поэтому ставим их так, как сетка их и
	# разложит: три в ряд, два ряда в глубину
	# ПОРЯДОК СОЗДАНИЯ НАМЕРЕННО ПЕРЕМЕШАН относительно расположения. Без этого
	# проверка ничего не значит: если отряды заводить слева направо, порядок
	# реестра совпадёт с пространственным сам собой, и раздача ячеек «по индексу»
	# выглядела бы правильной. Проверено — на откате фикса раздел проходил
	var spots := [5, 2, 0, 4, 1, 3]
	var sids: Array = []
	for k in spots:
		sids.append(_squad(Constants.FACTION_PLAYER,
			Vector3(-16.0 + float(int(k) % 3) * 16.0, 0, 30.0 + float(int(k) / 3) * 14.0),
			12, 4))
	await frames(6)
	var all_men: Array = []
	var cent_before: Array = []
	for s in sids:
		var mm: Array = _live(int(s))
		all_men.append_array(mm)
		var c := Vector3.ZERO
		for u in mm:
			c += (u as Node3D).global_position
		cent_before.append(c / float(mm.size()))
	var target := Vector3(0, 0, -10)
	var ok_call: bool = sel._issue_group_grid_move(all_men, target, false)
	verdict("C1 сетка отрядов сработала", ok_call)
	# Куда каждый отряд назначен — по среднему move_target его бойцов
	var cent_after: Array = []
	for s in sids:
		var c := Vector3.ZERO
		var mm: Array = _live(int(s))
		for u in mm:
			c += (u as Unit).move_target
		cent_after.append(c / float(mm.size()))
	var gc := Vector3.ZERO
	for c in cent_before:
		gc += c as Vector3
	gc /= float(cent_before.size())
	var course: Vector3 = target - gc
	course.y = 0.0
	course = course.normalized()
	var across := Vector3(-course.z, 0.0, course.x)
	var grp_side: float = _inversions(sids, cent_before, cent_after, across, 4.0)
	var grp_deep: float = _inversions(sids, cent_before, cent_after, course, 4.0)
	print("  перевёрнутых пар отрядов: поперёк %.0f%%, по глубине %.0f%%"
		% [grp_side * 100.0, grp_deep * 100.0])
	verdict("C2 отряды не меняются местами поперёк курса", grp_side < 0.05,
		"перевёрнуто %.0f%%" % (grp_side * 100.0))
	verdict("C2б передние отряды остаются впереди", grp_deep < 0.05,
		"перевёрнуто %.0f%%" % (grp_deep * 100.0))
	# И целевые коробки не должны накладываться
	var overlaps := 0
	for i in range(cent_after.size()):
		for j in range(i + 1, cent_after.size()):
			if (cent_after[i] as Vector3).distance_to(cent_after[j] as Vector3) < 4.0:
				overlaps += 1
	verdict("C3 целевые точки отрядов разнесены", overlaps == 0,
		"слишком близких пар: %d" % overlaps)
	await _sweep()

	print("\n═══ qa_order: прошло %d, провалов: %d ═══" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
