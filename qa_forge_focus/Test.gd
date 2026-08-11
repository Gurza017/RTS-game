extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ФОКУС ПАНЕЛИ КУЗНИЦЫ
## ═══════════════════════════════════════════════════════════════════════════
## Правило владельца: вся прямоугольная область панели кузницы — «безопасная
## зона». Клик внутри неё (вкладка, узел, ПУСТОЙ ПРОСВЕТ, фон) панель не
## закрывает и выделение с Кузницы не снимает. Закрывают только клик по миру
## ВНЕ прямоугольника и Escape.
##
## Проверяется на уровне SelectionManager._handle_single_click — это ровно та
## функция, которая решает судьбу выделения. Синтетические события мыши в HUD
## в этом проекте ненадёжны (см. qa_queue2), поэтому решение проверяется
## напрямую, а не через InputEvent.

var main = null
var hud = null
var sm = null
var _smithy: Smithy = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n: out += " "
	return out

## Заново выделить кузницу (после проверки, которая её закрыла)
func _reselect() -> void:
	sm._clear_selection()
	sm._select(_smithy)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)

func _run() -> void:
	seed(5)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	hud = main.hud
	sm  = main.selection_manager
	await frames(3)

	_smithy = Smithy.new()
	_smithy.faction = Constants.FACTION_PLAYER
	main.world_add(_smithy)
	_smithy.global_position = Vector3(-60.0, 0.0, 60.0)
	await frames(3)
	await _reselect()

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  ФОКУС ПАНЕЛИ КУЗНИЦЫ                                            ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	verdict("0 панель кузницы открыта (подготовка)", hud.forge_visible(),
		"видна=%s" % hud.forge_visible())
	if not hud.forge_visible():
		_finish()
		return

	var pr: Rect2 = hud._forge_panel.get_global_rect()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	print("  панель кузницы: x %.0f..%.0f, y %.0f..%.0f   (вьюпорт %.0fx%.0f)"
		% [pr.position.x, pr.position.x + pr.size.x,
			pr.position.y, pr.position.y + pr.size.y, vp.x, vp.y])

	# ── A. ГЕОМЕТРИЯ: точки внутри прямоугольника опознаются как интерфейс ───
	var centre: Vector2 = pr.position + pr.size * 0.5
	verdict("A1 центр панели опознан как интерфейс", hud.point_over_ui(centre),
		"точка (%.0f, %.0f)" % [centre.x, centre.y])

	# Все четыре угла (с отступом в 2 px внутрь) — bounding box целиком
	var corners := {
		"левый верх":   pr.position + Vector2(2, 2),
		"правый верх":  Vector2(pr.position.x + pr.size.x - 2, pr.position.y + 2),
		"левый низ":    Vector2(pr.position.x + 2, pr.position.y + pr.size.y - 2),
		"правый низ":   pr.position + pr.size - Vector2(2, 2),
	}
	var bad_corners: Array = []
	for cname in corners:
		if not hud.point_over_ui(corners[cname]):
			bad_corners.append(cname)
	verdict("A2 все четыре угла панели — «безопасная зона»", bad_corners.is_empty(),
		"вне зоны: %s" % str(bad_corners))

	# Точка ЗА пределами панели интерфейсом считаться не должна
	var outside := Vector2(pr.position.x + pr.size.x + 80.0, pr.position.y - 60.0)
	verdict("A3 точка вне панели интерфейсом НЕ считается",
		not hud.point_over_ui(outside),
		"точка (%.0f, %.0f)" % [outside.x, outside.y])

	# ── B. КЛИК В ПУСТОЙ ПРОСВЕТ ПАНЕЛИ НЕ ЗАКРЫВАЕТ ────────────────────────
	# Просвет ищем честно: точка внутри панели, не накрытая ни одной кнопкой
	var gap := _find_gap(pr)
	print("  пустой просвет найден в (%.0f, %.0f)" % [gap.x, gap.y])
	sm._handle_single_click(gap, false)
	await frames(3)
	verdict("B1 клик в ПРОСВЕТ панели не закрывает кузницу", hud.forge_visible(),
		"видна=%s, выделено %d" % [hud.forge_visible(), sm.selected_units.size()])
	verdict("B2 и не сбрасывает выделение Кузницы",
		sm.selected_units.size() == 1 and sm.selected_units[0] == _smithy,
		"в выделении %d" % sm.selected_units.size())

	# ── C. КЛИК ПО ВКЛАДКЕ И ПО УЗЛУ ────────────────────────────────────────
	if not hud.forge_visible():
		await _reselect()
	var tab_btn: Button = null
	for c in hud._forge_tabs.get_children():
		var b := c as Button
		if b != null and b.visible:
			tab_btn = b
	if tab_btn != null:
		var tp: Vector2 = tab_btn.get_global_rect().position \
			+ tab_btn.get_global_rect().size * 0.5
		var before: String = hud._forge_unit
		sm._handle_single_click(tp, false)   # клик «мимо» — как если бы событие дошло
		await frames(2)
		tab_btn.pressed.emit()               # и сам нажим вкладки
		await frames(3)
		verdict("C1 клик по вкладке не закрывает кузницу", hud.forge_visible(),
			"вкладка %s → %s, видна=%s" % [before, hud._forge_unit, hud.forge_visible()])
	else:
		verdict("C1 клик по вкладке не закрывает кузницу", false, "вкладок нет")

	if not hud.forge_visible():
		await _reselect()
	var node_btn: Button = null
	var node_id := ""
	for nid in hud._forge_nodes:
		var nb: Button = hud._forge_nodes[nid]
		if nb != null and is_instance_valid(nb) and nb.visible:
			node_btn = nb
			node_id = String(nid)
			break
	if node_btn != null:
		var np: Vector2 = node_btn.get_global_rect().position \
			+ node_btn.get_global_rect().size * 0.5
		sm._handle_single_click(np, false)
		await frames(2)
		verdict("C2 клик по узлу улучшения не закрывает кузницу",
			hud.forge_visible(), "узел %s, видна=%s" % [node_id, hud.forge_visible()])
	else:
		verdict("C2 клик по узлу улучшения не закрывает кузницу", false, "узлов нет")

	# ── B3. ПРОТУХШИЙ drag_start: НАЖАЛИ В ПАНЕЛИ, А РАМКА СЧИТАЕТСЯ ОТ
	# ПРОШЛОГО КЛИКА ПО КАРТЕ ───────────────────────────────────────────────
	# Нажатие по кнопке/фону панели ПОГЛОЩАЕТСЯ интерфейсом и до
	# SelectionManager._unhandled_input не доходит, поэтому drag_start остаётся
	# от прошлого клика по земле. Если до обработчика доберётся отпускание,
	# расстояние окажется огромным, и клик уедет в ветку РАМКИ — а она смотрит
	# на «интерфейс ли это» по НАЧАЛЬНОЙ точке, то есть по точке на карте
	if not hud.forge_visible():
		await _reselect()
	var far_map := Vector2(vp.x - 40.0, 60.0)      # прошлый клик где-то по карте
	sm.drag_start = far_map
	sm._handle_box_select(far_map, centre, false)  # отпустили ВНУТРИ панели
	await frames(3)
	verdict("B3 протухший drag_start не закрывает кузницу", hud.forge_visible(),
		"видна=%s, выделено %d" % [hud.forge_visible(), sm.selected_units.size()])

	# ── B4. ТОТ ЖЕ СЛУЧАЙ, НО ПО НАСТОЯЩЕМУ ПУТИ СОБЫТИЯ ────────────────────
	# Воспроизводим ровно то, что делает игрок: нажатие ПОГЛОЩЕНО кнопкой (в
	# _unhandled_input не приходит вовсе — имитируем, отправив туда только
	# отпускание), а до этого drag_start остался от клика по карте
	if not hud.forge_visible():
		await _reselect()
	sm._input(_press_at(far_map))          # «прошлый клик по карте»
	await frames(1)
	sm._input(_press_at(centre))           # нажали ВНУТРИ панели (ловит _input)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = centre
	sm._unhandled_input(rel)               # интерфейс отпускание пропустил дальше
	await frames(3)
	verdict("B4 нажатие внутри панели поглощается целиком (реальный путь)",
		hud.forge_visible(),
		"видна=%s, выделено %d" % [hud.forge_visible(), sm.selected_units.size()])

	# ── B5. И НАОБОРОТ: жест, начатый НА КАРТЕ, работает как раньше ─────────
	if not hud.forge_visible():
		await _reselect()
	sm._input(_press_at(outside))
	var rel2 := InputEventMouseButton.new()
	rel2.button_index = MOUSE_BUTTON_LEFT
	rel2.pressed = false
	rel2.position = outside
	sm._unhandled_input(rel2)
	await frames(3)
	verdict("B5 клик, начатый на карте, по-прежнему закрывает панель",
		not hud.forge_visible(), "видна=%s" % hud.forge_visible())

	# ── D. КЛИК ПО МИРУ ЗАКРЫВАЕТ ───────────────────────────────────────────
	if not hud.forge_visible():
		await _reselect()
	sm._handle_single_click(outside, false)
	await frames(3)
	verdict("D1 клик по карте ВНЕ панели закрывает кузницу",
		not hud.forge_visible(),
		"видна=%s, выделено %d" % [hud.forge_visible(), sm.selected_units.size()])
	verdict("D2 и снимает выделение с Кузницы", sm.selected_units.is_empty(),
		"в выделении %d" % sm.selected_units.size())

	# ── E. ESCAPE ЗАКРЫВАЕТ ─────────────────────────────────────────────────
	await _reselect()
	verdict("E0 кузница снова открыта (подготовка)", hud.forge_visible())
	var closed: bool = hud._close_building_panel()
	await frames(3)
	verdict("E1 Escape закрывает панель кузницы",
		closed and not hud.forge_visible(),
		"обработано=%s, видна=%s" % [closed, hud.forge_visible()])

	_finish()

## Событие «нажали ЛКМ вот здесь» — для проверки настоящего пути обработки
func _press_at(p: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	return e

## Точка ВНУТРИ панели, не накрытая ни одной кнопкой — тот самый «просвет».
## Ищем сеткой, чтобы проверка не зависела от конкретной раскладки
func _find_gap(pr: Rect2) -> Vector2:
	var btns: Array = []
	_collect_buttons(hud._forge_panel, btns)
	for gy in range(4, int(pr.size.y) - 4, 3):
		for gx in range(4, int(pr.size.x) - 4, 3):
			var p := pr.position + Vector2(float(gx), float(gy))
			var hit := false
			for b in btns:
				if (b as Control).get_global_rect().has_point(p):
					hit = true
					break
			if not hit:
				return p
	return pr.position + pr.size * 0.5

func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button and (n as Control).visible:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)

func _finish() -> void:
	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %s%s" % [_pad(String(row[0]), 52),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== FORGE FOCUS TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)
