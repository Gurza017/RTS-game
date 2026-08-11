extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: КУЗНИЦА — ДРЕВО ТЕХНОЛОГИЙ И СПЕЦ-СПОСОБНОСТИ ОТРЯДА
## ═══════════════════════════════════════════════════════════════════════════
##   A КОНФИГ    — сетка 5×4 у всех вкладок, id уникальны, иконки на месте
##   B ЗАВИСИМОСТИ — узел закрыт, пока не изучен родитель по стрелке
##   C КОЛОНКА D — открывается только полным рядом A+B+C, не стрелкой
##   D ПАНЕЛЬ    — вкладки переключают древо, узлы и стрелки на местах
##   E СПОСОБНОСТЬ — двухэтапная покупка: кузница, затем золото за отряд
##
## ЧИСЛА НЕ ХАРДКОДЯТСЯ: всё берётся из forge_config (см. CLAUDE.md,
## «Config is the source of truth») — стенд проверяет СВОЙСТВА, а не значения.

const _Forge := preload("res://scripts/forge_config.gd")
const _UCfg  := preload("res://scripts/unit_stats_config.gd")

var main = null
var hud = null
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

func _give(amount: float) -> void:
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), amount)

## Мгновенно «изучить» узел, минуя кузницу и таймеры
func _grant(cell_unit: String, cell: String) -> void:
	GameManager.finish_research(Constants.FACTION_PLAYER,
		_Forge.node_id(cell_unit, cell))

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	hud = main.hud
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	await frames(3)

	await _a_config()
	await _b_prereq()
	await _c_ability_gate()
	await _d_panel()
	await _e_squad_ability()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 66), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== FORGE TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. КОНФИГ
# ═════════════════════════════════════════════════════════════════════════════
func _a_config() -> void:
	print("\n═════ A. КОНФИГ ДРЕВА ═════")

	# A1 — у каждой вкладки ровно ROWS × COLS узлов
	var want: int = _Forge.ROWS * _Forge.COLS.size()
	var bad: Array = []
	for u in _Forge.UNIT_TABS:
		var n: int = _Forge.tree(String(u)).size()
		if n != want:
			bad.append("%s=%d" % [String(u), n])
	verdict("A1 у каждой вкладки сетка %d×%d" % [_Forge.ROWS, _Forge.COLS.size()],
		bad.is_empty(), "ожидали %d узлов; расхождения: %s" % [want, str(bad)])

	# A2 — id глобально уникальны (иначе два узла делили бы одну отметку
	# «изучено» в GameManager.researched)
	var seen: Dictionary = {}
	var dups: Array = []
	for n in _Forge.all_nodes():
		var nid: String = String((n as Dictionary).get("id", ""))
		if seen.has(nid):
			dups.append(nid)
		seen[nid] = true
	verdict("A2 id узлов уникальны по всем вкладкам", dups.is_empty(),
		"узлов=%d, дубликатов=%s" % [seen.size(), str(dups)])

	# A3 — узел древа виден системе исследований как обычный слот улучшения
	var probe: String = _Forge.node_id(String(_Forge.UNIT_TABS[0]), "1a")
	var slot: Dictionary = _UCfg.get_upgrade_slot(probe)
	verdict("A3 узел древа находится через get_upgrade_slot",
		not slot.is_empty() and String(slot.get("id", "")) == probe,
		"искали %s, нашли «%s»" % [probe, String(slot.get("id", "—"))])

	# A4 — иконки реально лежат на диске (в конфиге только имена файлов)
	var missing: Array = []
	for n in _Forge.all_nodes():
		var d: Dictionary = n
		var path: String = _UCfg.smith_icon_path(String(d.get("icon", "")))
		if path.is_empty() or not ResourceLoader.exists(path):
			missing.append(String(d.get("id", "")))
	verdict("A4 все иконки узлов существуют", missing.is_empty(),
		"не найдено: %d %s" % [missing.size(), str(missing.slice(0, 5))])

	# A5 — у каждого узла есть имя и цена: пустой узел на панели выглядит багом
	var empty: Array = []
	for n in _Forge.all_nodes():
		var d: Dictionary = n
		var cost: Dictionary = _UCfg.upgrade_cost(d)
		if String(d.get("name", "")).is_empty() or cost.is_empty():
			empty.append(String(d.get("id", "")))
	verdict("A5 у каждого узла есть название и ненулевая цена", empty.is_empty(),
		"пустых: %d %s" % [empty.size(), str(empty.slice(0, 5))])

	# A6 — колонка D помечена как способность отряда и имеет цену за отряд
	var d_bad: Array = []
	for u in _Forge.UNIT_TABS:
		for n in _Forge.ability_nodes(String(u)):
			var d: Dictionary = n
			if String(d.get("col", "")) != _Forge.ABILITY_COL \
					or _Forge.squad_unlock_cost(d) <= 0.0:
				d_bad.append(String(d.get("id", "")))
	var d_count: int = _Forge.ability_nodes(String(_Forge.UNIT_TABS[0])).size()
	verdict("A6 колонка D — способности отряда с ценой за отряд",
		d_bad.is_empty() and d_count == _Forge.ROWS,
		"способностей на вкладку=%d (ожидали %d), брак: %s" % [
			d_count, _Forge.ROWS, str(d_bad)])

	# A7 — бонусы копятся ТОЛЬКО своему роду войск
	var cross: Array = []
	for u in _Forge.UNIT_TABS:
		for n in _Forge.tree(String(u)):
			var d: Dictionary = n
			var app: Array = d.get("applies_to", [])
			if app.size() != 1 or String(app[0]) != String(u):
				cross.append(String(d.get("id", "")))
	verdict("A7 узел вкладки усиливает только свой род войск", cross.is_empty(),
		"чужих applies_to: %d" % cross.size())

# ═════════════════════════════════════════════════════════════════════════════
# B. ЗАВИСИМОСТИ ПО СТРЕЛКАМ
# ═════════════════════════════════════════════════════════════════════════════
func _b_prereq() -> void:
	print("\n═════ B. ЗАВИСИМОСТИ ═════")
	var f: int = Constants.FACTION_PLAYER
	var u: String = "spearman"
	_give(500000.0)

	# B1 — первый ряд A/B/C открыт сразу, второй закрыт
	var open_1: bool = GameManager.can_research(f, _Forge.node_id(u, "1a"))
	var shut_2: bool = not GameManager.can_research(f, _Forge.node_id(u, "2a"))
	verdict("B1 верхний ряд открыт, следующий за ним закрыт", open_1 and shut_2,
		"1a доступен=%s, 2a доступен=%s" % [open_1, not shut_2])

	# B2 — изучили родителя, ребёнок открылся
	_grant(u, "1a")
	var now_open: bool = GameManager.can_research(f, _Forge.node_id(u, "2a"))
	verdict("B2 изучение родителя открывает узел по стрелке", now_open,
		"2a доступен=%s после 1a" % now_open)

	# B3 — соседняя ветка при этом НЕ открылась (стрелки не перепутаны)
	var neighbour: bool = GameManager.can_research(f, _Forge.node_id(u, "2b"))
	verdict("B3 соседняя ветка чужим родителем не открывается", not neighbour,
		"2b доступен=%s (родитель 1b не изучен)" % neighbour)

	# B4 — причина закрытия называется поимённо
	var node_2b: Dictionary = _Forge.get_node(_Forge.node_id(u, "2b"))
	var blockers: Array = GameManager.research_blockers(f, node_2b)
	verdict("B4 стенд может узнать, ЧЕГО именно не хватает",
		blockers.size() == 1 and String(blockers[0]) == _Forge.node_id(u, "1b"),
		"не хватает: %s" % str(blockers))

	# B5 — цепочка держится до конца колонки: 5a закрыт, пока не пройдены 2a..4a
	var deep: bool = GameManager.can_research(f, _Forge.node_id(u, "5a"))
	verdict("B5 глубокий узел колонки закрыт без всей цепочки", not deep,
		"5a доступен=%s (изучен только 1a)" % deep)

	# B6 — горизонтальная связка НЕ является зависимостью (иначе пара ячеек
	# заблокировала бы друг друга навсегда: на схеме стрелка двусторонняя)
	var loops: Array = []
	for n in _Forge.tree(u):
		var d: Dictionary = n
		for l in d.get("link", []):
			var other: Dictionary = _Forge.get_node(_Forge.node_id(u, String(l)))
			if other.is_empty():
				continue
			if (other.get("prerequisites", []) as Array).has(String(d.get("id", ""))) \
					and (d.get("prerequisites", []) as Array).has(String(other.get("id", ""))):
				loops.append("%s<->%s" % [String(d.get("id", "")), String(other.get("id", ""))])
	verdict("B6 горизонтальные связки не создают взаимной блокировки",
		loops.is_empty(), "взаимных зависимостей: %s" % str(loops))

	# ── B7-B9: ШАГ ВБОК ПО ВИДИМОЙ СТРЕЛКЕ ──────────────────────────────────
	# Заказ владельца: «переход разрешён строго при наличии видимой стрелки;
	# идёт стрелка вбок — можно шагнуть вбок». То есть горизонтальная связка —
	# это АЛЬТЕРНАТИВНЫЙ вход в узел, равноправный вертикальному, а не
	# украшение и не дополнительное требование
	var side_f: int = Constants.FACTION_ENEMY      # чистая фракция: у неё ничего не изучено
	var n2a: String = _Forge.node_id(u, "2a")
	var n2b: String = _Forge.node_id(u, "2b")
	verdict("B7 без единой стрелки соседний узел закрыт",
		not GameManager.can_research(side_f, n2a),
		"2a доступен=%s при пустом древе" % GameManager.can_research(side_f, n2a))

	# Изучаем 2b (в обход — напрямую в реестр, стенд проверяет ПРАВИЛО, а не
	# экономику) и смотрим, открылся ли связанный с ним стрелкой 2a
	if not GameManager.researched.has(side_f):
		GameManager.researched[side_f] = {}
	(GameManager.researched[side_f] as Dictionary)[n2b] = true
	verdict("B8 сосед по горизонтальной стрелке открывает узел",
		GameManager.can_research(side_f, n2a),
		"2a доступен=%s после изучения 2b (они связаны стрелкой)"
			% GameManager.can_research(side_f, n2a))

	# А узел БЕЗ стрелки к изученному — по-прежнему закрыт: правило именно
	# «строго по стрелке», а не «всё в соседнем ряду открыто»
	var n4a: String = _Forge.node_id(u, "4a")
	verdict("B9 узел без стрелки к изученному остаётся закрытым",
		not GameManager.can_research(side_f, n4a),
		"4a доступен=%s (стрелки от 2b к нему нет)"
			% GameManager.can_research(side_f, n4a))
	(GameManager.researched[side_f] as Dictionary).erase(n2b)

# ═════════════════════════════════════════════════════════════════════════════
# C. КОЛОНКА D — ТОЛЬКО ПОЛНЫМ РЯДОМ
# ═════════════════════════════════════════════════════════════════════════════
func _c_ability_gate() -> void:
	print("\n═════ C. ВОРОТА КОЛОНКИ D ═════")
	var f: int = Constants.FACTION_PLAYER
	var u: String = "archer"
	var d_id: String = _Forge.node_id(u, "1d")

	verdict("C1 1D закрыта, пока ряд не изучен вовсе",
		not GameManager.can_research(f, d_id), "доступна=%s" % GameManager.can_research(f, d_id))

	_grant(u, "1a")
	_grant(u, "1b")
	verdict("C2 1D всё ещё закрыта при двух из трёх",
		not GameManager.can_research(f, d_id),
		"изучено 1a+1b, доступна=%s" % GameManager.can_research(f, d_id))

	# Причина обязана называть ИМЕННО недостающую ячейку ряда
	var node_d: Dictionary = _Forge.get_node(d_id)
	var miss: Array = GameManager.research_blockers(f, node_d)
	verdict("C3 не хватает ровно оставшейся ячейки ряда",
		miss.size() == 1 and String(miss[0]) == _Forge.node_id(u, "1c"),
		"не хватает: %s" % str(miss))

	_grant(u, "1c")
	verdict("C4 полный ряд A+B+C открывает 1D",
		GameManager.can_research(f, d_id),
		"изучено 1a+1b+1c, доступна=%s" % GameManager.can_research(f, d_id))

	# C5 — ворота ряда независимы: открытие 1D не открывает 2D
	verdict("C5 открытие 1D не открывает 2D",
		not GameManager.can_research(f, _Forge.node_id(u, "2d")),
		"2d доступна=%s" % GameManager.can_research(f, _Forge.node_id(u, "2d")))

	# C6 — ворота считаются по СВОЕЙ вкладке, а не по любой
	verdict("C6 ряд другой вкладки чужую D не открывает",
		not GameManager.can_research(f, _Forge.node_id("monk", "1d")),
		"monk_1d доступна=%s" % GameManager.can_research(f, _Forge.node_id("monk", "1d")))

# ═════════════════════════════════════════════════════════════════════════════
# D. ПАНЕЛЬ КУЗНИЦЫ
# ═════════════════════════════════════════════════════════════════════════════
var _smithy: Smithy = null

func _d_panel() -> void:
	print("\n═════ D. ПАНЕЛЬ ═════")
	_smithy = Smithy.new()
	_smithy.faction = Constants.FACTION_PLAYER
	main.world_add(_smithy)
	_smithy.global_position = Vector3(-60.0, 0.0, 60.0)
	await frames(3)
	_give(500000.0)

	hud.show_selection([_smithy])
	await frames(3)

	# D1 — у кузницы своя панель, общая нижняя при этом убрана
	verdict("D1 выделенная кузница открывает свою панель вместо общей",
		hud.forge_visible() and not hud._bottom_panel.visible,
		"панель кузницы=%s, нижняя=%s" % [hud.forge_visible(), hud._bottom_panel.visible])

	# D2 — вкладок ровно столько, сколько родов войск в конфиге
	verdict("D2 вкладок по числу родов войск",
		hud._forge_tabs.get_child_count() == _Forge.UNIT_TABS.size(),
		"вкладок=%d, в конфиге=%d" % [
			hud._forge_tabs.get_child_count(), _Forge.UNIT_TABS.size()])

	# D3 — на сетке ровно 20 кнопок узлов текущей вкладки
	var want: int = _Forge.ROWS * _Forge.COLS.size()
	verdict("D3 на сетке все узлы вкладки", hud._forge_nodes.size() == want,
		"кнопок=%d, ожидали %d" % [hud._forge_nodes.size(), want])

	# D4 — все кнопки принадлежат ИМЕННО открытой вкладке
	var alien: Array = []
	for k in hud._forge_nodes.keys():
		if String(_Forge.get_node(String(k)).get("unit", "")) != hud._forge_unit:
			alien.append(String(k))
	verdict("D4 на сетке узлы только открытой вкладки", alien.is_empty(),
		"вкладка=%s, чужих=%s" % [hud._forge_unit, str(alien.slice(0, 4))])

	# D5 — переключение вкладки меняет древо
	var first: String = hud._forge_unit
	var other: String = ""
	for t in _Forge.UNIT_TABS:
		if String(t) != first:
			other = String(t)
			break
	hud.forge_set_tab(other)
	await frames(2)
	var switched: bool = hud._forge_unit == other \
		and hud._forge_nodes.has(_Forge.node_id(other, "1a")) \
		and not hud._forge_nodes.has(_Forge.node_id(first, "1a"))
	verdict("D5 клик по вкладке переключает древо на её узлы", switched,
		"было %s, стало %s, узлов=%d" % [first, hud._forge_unit, hud._forge_nodes.size()])

	# D6 — сетка геометрически 5×4: 4 разные X, 5 разных Y, без наложений
	var xs: Dictionary = {}
	var ys: Dictionary = {}
	var overlap := false
	var rects: Array = []
	for k in hud._forge_nodes.keys():
		var b: Button = hud._forge_nodes[k]
		xs[int(b.position.x)] = true
		ys[int(b.position.y)] = true
		for r in rects:
			if (r as Rect2).intersects(Rect2(b.position, b.size)):
				overlap = true
		rects.append(Rect2(b.position, b.size))
	verdict("D6 узлы стоят сеткой %d×%d без наложений" % [
			_Forge.ROWS, _Forge.COLS.size()],
		xs.size() == _Forge.COLS.size() and ys.size() == _Forge.ROWS and not overlap,
		"колонок=%d рядов=%d наложения=%s" % [xs.size(), ys.size(), overlap])

	# D7 — колонка D отставлена вправо дальше обычного шага между колонками
	var xa: float = hud._forge_cell_pos("1a").x
	var xb: float = hud._forge_cell_pos("1b").x
	var xc: float = hud._forge_cell_pos("1c").x
	var xd: float = hud._forge_cell_pos("1d").x
	verdict("D7 колонка способностей визуально отбита от A/B/C",
		(xd - xc) > (xb - xa) + 0.5,
		"шаг A→B=%.0f, C→D=%.0f" % [xb - xa, xd - xc])

	# D8 — панель целиком помещается на экран (сетка не свисает за нижний край)
	await frames(2)
	var pr: Rect2 = hud._forge_panel.get_global_rect()
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	var lowest: float = 0.0
	for k in hud._forge_nodes.keys():
		var b: Button = hud._forge_nodes[k]
		lowest = maxf(lowest, b.position.y + b.size.y)
	verdict("D8 панель вмещает всю сетку и стоит на экране",
		pr.position.y >= -0.5 and pr.position.y + pr.size.y <= vp.y + 0.5 \
			and lowest <= float(hud.FORGE_GRID_H + hud.FORGE_ROOT_H) + 0.5,
		"панель y=%.0f h=%.0f экран=%.0f, низ сетки=%.0f из %d" % [
			pr.position.y, pr.size.y, vp.y, lowest,
			hud.FORGE_GRID_H + hud.FORGE_ROOT_H])

	# D9 — всплывающее окно строится и стоит СПРАВА от панели, вне её
	hud._show_forge_tip(_Forge.node_id(hud._forge_unit, "1a"))
	await frames(2)
	var tip_ok := false
	var tip_right := false
	if hud._forge_tip != null and is_instance_valid(hud._forge_tip):
		tip_ok = true
		tip_right = hud._forge_tip.position.x >= pr.position.x + pr.size.x - 0.5
	verdict("D9 окно описания появляется справа от панели", tip_ok and tip_right,
		"окно=%s, x окна=%.0f, правый край панели=%.0f" % [tip_ok,
			hud._forge_tip.position.x if tip_ok else -1.0, pr.position.x + pr.size.x])

	# D10 — окно называет ПРИЧИНУ закрытия узла колонки D, а не молчит
	hud._show_forge_tip(_Forge.node_id(hud._forge_unit, "5d"))
	await frames(2)
	var said_row := false
	if hud._forge_tip != null and is_instance_valid(hud._forge_tip):
		var texts: Array = []
		_collect_labels(hud._forge_tip, texts)
		for t in texts:
			if String(t).findn("ряд") >= 0:
				said_row = true
	verdict("D10 закрытая D объясняет, что нужен весь ряд", said_row,
		"в окне %s строки про ряд" % ("есть" if said_row else "нет"))
	hud._hide_forge_tip()

	# D11 — очередь исследований рисуется в панели кузницы, а не в общей
	var qid: String = ""
	for n in _Forge.tree(hud._forge_unit):
		var nid: String = String((n as Dictionary).get("id", ""))
		if GameManager.can_research(Constants.FACTION_PLAYER, nid) \
				and _UCfg.upgrade_research_time(n) > 0.0:
			qid = nid
			break
	if not qid.is_empty():
		_smithy.research(qid)
		_smithy.research_time  = 60.0
		_smithy.research_timer = 0.0
		hud.show_selection([_smithy])
		await frames(3)
	verdict("D11 ряд очереди исследований живёт в панели кузницы",
		not qid.is_empty() and hud._forge_queue.get_child_count() == 1,
		"заказ=%s, ячеек в ряду=%d" % [qid, hud._forge_queue.get_child_count()])

	# ── D11б/в: ИНДИКАТОР ТЕКУЩЕГО ИССЛЕДОВАНИЯ ─────────────────────────────
	# Заказ владельца: «убери пустой чёрный прямоугольник под иконкой Кузницы,
	# опусти иконку исследуемой технологии ниже и увеличь её». Прямоугольником
	# была САМА ячейка очереди: она строилась размером QUEUE_ORDER_ICON (10 px),
	# и технология в ней не читалась
	var ind: Control = null
	if hud._forge_queue.get_child_count() > 0:
		ind = hud._forge_queue.get_child(0) as Control
	verdict("D11б индикатор исследования крупнее узла древа",
		ind != null and ind.size.x >= float(HUD.FORGE_CELL),
		"сторона %.0f, узел древа %d, в конфиге %d" % [
			ind.size.x if ind != null else -1.0, HUD.FORGE_CELL, HUD.FORGE_QUEUE_ICON])

	# И он ПОД иконкой здания, а не рядом с ней
	var bld_icon: Control = hud._forge_panel.find_child("ForgeBuildingIcon", true, false)
	verdict("D11в индикатор опущен ПОД иконку Кузницы",
		ind != null and bld_icon != null
			and ind.get_global_rect().position.y
				>= bld_icon.get_global_rect().position.y + bld_icon.size.y,
		"верх индикатора %.0f, низ иконки здания %.0f" % [
			ind.get_global_rect().position.y if ind != null else -1.0,
			(bld_icon.get_global_rect().position.y + bld_icon.size.y) if bld_icon != null else -1.0])

	# D12 — заказанный узел на сетке помечен «идёт», а не остался доступным
	var busy_btn: Button = hud._forge_nodes.get(qid, null)
	verdict("D12 заказанный узел на сетке погашен как «идёт»",
		busy_btn != null and busy_btn.modulate.is_equal_approx(hud.UPG_BUSY_MODULATE),
		"modulate=%s" % (str(busy_btn.modulate) if busy_btn != null else "кнопки нет"))

	# D13 — снятие выделения убирает панель кузницы
	hud.show_selection([])
	await frames(2)
	verdict("D13 панель кузницы уходит вместе с выделением",
		not hud.forge_visible(), "видна=%s" % hud.forge_visible())

func _collect_labels(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		_collect_labels(c, out)

# ═════════════════════════════════════════════════════════════════════════════
# E. ДВУХЭТАПНАЯ СПОСОБНОСТЬ ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _e_squad_ability() -> void:
	print("\n═════ E. СПОСОБНОСТЬ ОТРЯДА ═════")
	var f: int = Constants.FACTION_PLAYER
	var u: String = "spearman"
	var d_id: String = _Forge.node_id(u, "1d")
	var cost: float = _Forge.squad_unlock_cost(_Forge.get_node(d_id))

	# Отряд копейщиков
	var sid: int = GameManager.new_squad(f, u)
	var men: Array = []
	for i in range(3):
		var sp := Spearman.new()
		sp.faction = f
		main.world_add(sp)
		sp.global_position = Vector3(-120.0 + float(i) * 1.5, 0.0, 120.0)
		GameManager.add_to_squad(sid, sp)
		men.append(sp)
	await frames(3)

	# E1 — пока в кузнице не исследовано, отряд купить не может
	_give(500000.0)
	verdict("E1 без исследования в кузнице отряд способность не купит",
		not GameManager.squad_can_buy_ability(sid, d_id),
		"причина: %s" % GameManager.squad_ability_blocker(sid, d_id))

	# Исследуем весь ряд и саму способность
	for c in ["1a", "1b", "1c"]:
		_grant(u, String(c))
	_grant(u, "1d")

	# E2 — теперь может, но она НЕ выдана автоматически
	verdict("E2 после исследования способность доступна, но не выдана даром",
		GameManager.squad_can_buy_ability(sid, d_id) \
			and not GameManager.squad_has_ability(sid, d_id),
		"можно купить=%s, уже есть=%s" % [
			GameManager.squad_can_buy_ability(sid, d_id),
			GameManager.squad_has_ability(sid, d_id)])

	# E3 — покупка списывает ровно squad_unlock_cost золота
	var before: float = ResourceManager.get_amount(f, Constants.RESOURCE_GOLD)
	var bought: bool = GameManager.squad_buy_ability(sid, d_id)
	var spent: float = before - ResourceManager.get_amount(f, Constants.RESOURCE_GOLD)
	verdict("E3 покупка списывает цену за отряд из конфига",
		bought and absf(spent - cost) < 0.01,
		"списано %.0f, в конфиге %.0f" % [spent, cost])

	# E4 — способность появилась именно у этого отряда
	verdict("E4 способность записана этому отряду",
		GameManager.squad_has_ability(sid, d_id)
			and GameManager.squad_abilities(sid).has(d_id),
		"есть=%s, список=%s" % [GameManager.squad_has_ability(sid, d_id),
			str(GameManager.squad_abilities(sid))])

	# E5 — ВТОРОЙ отряд того же типа её НЕ получил: платит каждый сам
	var sid2: int = GameManager.new_squad(f, u)
	var sp2 := Spearman.new()
	sp2.faction = f
	main.world_add(sp2)
	sp2.global_position = Vector3(-140.0, 0.0, 140.0)
	GameManager.add_to_squad(sid2, sp2)
	await frames(2)
	verdict("E5 другому отряду способность не досталась даром",
		not GameManager.squad_has_ability(sid2, d_id)
			and GameManager.squad_can_buy_ability(sid2, d_id),
		"есть у второго=%s, может купить=%s" % [
			GameManager.squad_has_ability(sid2, d_id),
			GameManager.squad_can_buy_ability(sid2, d_id)])

	# E6 — дважды одному отряду не продаётся
	var before2: float = ResourceManager.get_amount(f, Constants.RESOURCE_GOLD)
	var again: bool = GameManager.squad_buy_ability(sid, d_id)
	verdict("E6 повторная покупка тому же отряду отбивается",
		not again and absf(ResourceManager.get_amount(f, Constants.RESOURCE_GOLD) - before2) < 0.01,
		"вернуло %s, золото не изменилось=%s" % [again,
			absf(ResourceManager.get_amount(f, Constants.RESOURCE_GOLD) - before2) < 0.01])

	# E7 — не хватает золота: покупка не проходит и денег не трогает
	var sid3: int = GameManager.new_squad(f, u)
	var sp3 := Spearman.new()
	sp3.faction = f
	main.world_add(sp3)
	sp3.global_position = Vector3(-160.0, 0.0, 160.0)
	GameManager.add_to_squad(sid3, sp3)
	await frames(2)
	ResourceManager.spend(f, {Constants.RESOURCE_GOLD:
		ResourceManager.get_amount(f, Constants.RESOURCE_GOLD)})
	var poor: bool = GameManager.squad_buy_ability(sid3, d_id)
	verdict("E7 без золота способность не покупается",
		not poor and not GameManager.squad_has_ability(sid3, d_id),
		"купилось=%s, причина: %s" % [poor,
			GameManager.squad_ability_blocker(sid3, d_id)])

	# E8 — способность чужого рода войск отряду не продаётся вовсе
	var alien: String = _Forge.node_id("archer", "1d")
	verdict("E8 отряду не продать способность другого рода войск",
		not GameManager.squad_can_buy_ability(sid2, alien),
		"причина: %s" % GameManager.squad_ability_blocker(sid2, alien))

	# E9 — кнопка покупки появляется в панели ВЫДЕЛЕННОГО отряда
	_give(500000.0)
	hud.show_selection(men)
	await frames(3)
	var found: Button = _find_button_with(hud.button_container,
		String(_Forge.get_node(d_id).get("name", "")))
	verdict("E9 в панели выделенного отряда есть кнопка способности",
		found != null, "кнопка «%s» %s" % [
			String(_Forge.get_node(d_id).get("name", "")),
			"найдена" if found != null else "не найдена"])

	# E10 — у отряда БЕЗ исследованной способности кнопки нет
	var sid4: int = GameManager.new_squad(f, "warrior")
	var wr := Warrior.new()
	wr.faction = f
	main.world_add(wr)
	wr.global_position = Vector3(-180.0, 0.0, 180.0)
	GameManager.add_to_squad(sid4, wr)
	await frames(2)
	hud.show_selection([wr])
	await frames(3)
	var w_names: Array = []
	for a in _Forge.ability_nodes("warrior"):
		w_names.append(String((a as Dictionary).get("name", "")))
	var stray: Button = null
	for nm in w_names:
		var b: Button = _find_button_with(hud.button_container, String(nm))
		if b != null:
			stray = b
			break
	verdict("E10 неисследованная способность в панель отряда не попадает",
		stray == null, "лишняя кнопка: %s" % ("есть" if stray != null else "нет"))

## Кнопка, в подписи или подсказке которой встречается текст
func _find_button_with(root: Node, needle: String) -> Button:
	if needle.is_empty() or root == null:
		return null
	if root is Button:
		var b := root as Button
		if b.text.findn(needle) >= 0 or b.tooltip_text.findn(needle) >= 0:
			return b
	for c in root.get_children():
		var r: Button = _find_button_with(c, needle)
		if r != null:
			return r
	return null
