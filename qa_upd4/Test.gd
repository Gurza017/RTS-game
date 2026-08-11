extends Node

## СТЕНД: АПДЕЙТ ИЗ ЧЕТЫРЁХ БЛОКОВ
##   A ВЕТЕРАНСТВО — 7 грейдов, бронза/серебро/красная, звёзды −30 %
##   B КУЗНИЦА     — очередь исследований, отмена ПКМ с возвратом 100 %,
##                   светлое приглушение + зелёная галочка вместо тёмной плашки
##   C БОНУСЫ      — ряд иконок отряда, римский стек II/III/IV, окно-подсказка
##   D БЕГ         — двойной ПКМ, ×1.4, фаланга распускается, авто-бой выключен
##
## Числа НЕ хардкодятся: пороги, значения бонусов и цены читаются из
## unit_stats_config.gd — он владельческая таблица баланса и всегда прав.

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _Star := preload("res://scripts/VeterancyStar.gd")

var main: Node = null
var hud        = null
var sm         = null
var smithy: Smithy = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  %s  %s%s" % ["ПРОШЛО " if ok else "ПРОВАЛ ", title,
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	await frames(3)
	hud = main.hud
	sm  = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 5000000.0)
	await frames(2)

	_block_a()
	await _block_b()
	await _block_c()
	await _block_d()
	_summary()
	print("\n=== QA_UPD4 DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
	print("  провалов: %d из %d" % [bad, verdicts.size()])

# ═════════════════════════════════════════════════════════════════════════════
# A. ВЕТЕРАНСТВО: ГРЕЙДЫ ЗВЁЗД
# ═════════════════════════════════════════════════════════════════════════════

func _block_a() -> void:
	print("\n═════ A. ВЕТЕРАНСТВО (звёзды) ═════")
	# Конфиг теперь раздельный по 4 боевым типам (VET_CONFIG) — звёзды
	# (VET_STAR_TIERS) остались общим стилем показа, а вот пороги/бонусы
	# берём для представителя ("spearman"), тот же тип, что даёт _make_squad
	var utype := "spearman"
	var maxl: int = _UCfg.max_veteran_level(utype)
	print("  уровней: %d, порогов: %d, грейдов: %d" % [maxl,
		(_UCfg.VET_CONFIG[utype]["thresholds"] as Array).size(), _UCfg.VET_STAR_TIERS.size()])

	# A1 — таблицы согласованы: на каждый уровень есть и порог, и грейд, и выбор
	var ok1 := maxl > 0 and _UCfg.VET_STAR_TIERS.size() >= maxl
	var seen_tiers: Array = []
	for lvl in range(1, maxl + 1):
		var tier: Dictionary = _UCfg.veteran_star_tier(lvl)
		if tier.is_empty() or int(tier.get("count", 0)) < 1:
			ok1 = false
		if _UCfg.veteran_choices(utype, lvl).is_empty():
			ok1 = false
		if _UCfg.veteran_threshold(utype, lvl) <= 0:
			ok1 = false
		var tn: String = String(tier.get("tier", ""))
		if not (tn in seen_tiers):
			seen_tiers.append(tn)
	verdict("A1 у каждого уровня есть порог, грейд и список наград",
		ok1, "грейды по порядку: %s" % str(seen_tiers))

	# A2 — грейдов ТРИ и высший заметно крупнее базового
	var first: Dictionary = _UCfg.veteran_star_tier(1)
	var last: Dictionary  = _UCfg.veteran_star_tier(maxl)
	var ok2: bool = seen_tiers.size() >= 3 \
		and float(last.get("scale", 1.0)) > float(first.get("scale", 1.0)) \
		and (last.get("color") as Color) != (first.get("color") as Color)
	verdict("A2 три грейда, высший крупнее и другого цвета", ok2,
		"scale %0.2f → %0.2f" % [float(first.get("scale", 1.0)),
			float(last.get("scale", 1.0))])

	# A3 — РАЗМЕР ЗВЕЗДЫ ПЕРЕСМОТРЕН.
	# Прежние 0.098 (−30 % от 0.14) подбирались под звезду, висевшую над головой
	# ОДНОГО бойца-командира. Теперь она стоит над центром масс всего отряда
	# (см. qa_sel2 E6) и по заказу владельца увеличена ВДВОЕ
	var want_r: float = 0.14 * 0.7 * 2.0
	var ok3: bool = absf(_Star.STAR_RADIUS - want_r) < 0.0005
	verdict("A3 радиус звезды удвоен (0.098 → %0.3f)" % want_r, ok3,
		"STAR_RADIUS=%0.4f" % _Star.STAR_RADIUS)

	# A4 — мех строится на всех уровнях, ширина ряда растёт вместе с count,
	#      а высший грейд (одна звезда) выше базового с тем же count
	var ok4 := true
	var widths: Array = []
	var heights: Array = []
	for lvl in range(1, maxl + 1):
		var node: MeshInstance3D = _Star.create(lvl)
		if node.mesh == null:
			ok4 = false
			widths.append(0.0)
			heights.append(0.0)
		else:
			var aabb: AABB = node.mesh.get_aabb()
			widths.append(aabb.size.x)
			heights.append(aabb.size.y)
		node.free()
	# внутри одного грейда ряд из двух звёзд шире, чем из одной
	for lvl in range(2, maxl + 1):
		var t_prev: Dictionary = _UCfg.veteran_star_tier(lvl - 1)
		var t_cur: Dictionary  = _UCfg.veteran_star_tier(lvl)
		if String(t_prev.get("tier", "")) != String(t_cur.get("tier", "")):
			continue
		if int(t_cur.get("count", 0)) > int(t_prev.get("count", 0)):
			if float(widths[lvl - 1]) <= float(widths[lvl - 2]):
				ok4 = false
	# высшая (красная) звезда выше первой бронзовой — это и есть «чуть крупнее»
	if float(heights[maxl - 1]) <= float(heights[0]):
		ok4 = false
	verdict("A4 меши всех уровней строятся, высота высшего грейда больше",
		ok4, "h[1]=%0.3f h[%d]=%0.3f" % [float(heights[0]), maxl,
			float(heights[maxl - 1])])

# ═════════════════════════════════════════════════════════════════════════════
# B. КУЗНИЦА: ОЧЕРЕДЬ И ОТМЕНА
# ═════════════════════════════════════════════════════════════════════════════

## Слоты без предусловий, отсортированные как в конфиге
func _free_slots() -> Array:
	var out: Array = []
	for s in _UCfg.UPGRADE_SLOTS:
		var d: Dictionary = s
		if String(d.get("requires", "")).is_empty():
			out.append(String(d.get("id", "")))
	return out

func _bank(f: int) -> Dictionary:
	var out: Dictionary = {}
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		out[int(t)] = ResourceManager.get_amount(f, int(t))
	return out

func _bank_equal(a: Dictionary, b: Dictionary) -> bool:
	for k in a.keys():
		if absf(float(a[k]) - float(b.get(k, 0.0))) > 0.01:
			return false
	return true

func _block_b() -> void:
	print("\n═════ B. КУЗНИЦА ═════")
	var f: int = Constants.FACTION_PLAYER
	smithy = Smithy.new()
	smithy.faction = f
	main.world_add(smithy)
	smithy.global_position = Vector3(-420.0, 0.0, -420.0)
	await frames(3)

	var free: Array = _free_slots()
	if free.size() < 3:
		verdict("B0 в конфиге хватает свободных слотов", false,
			"нужно 3, есть %d" % free.size())
		return
	var id1: String = String(free[0])
	var id2: String = String(free[1])
	var id3: String = String(free[2])

	# B1 — второй заказ встаёт в очередь, а не отбивается
	var bank0: Dictionary = _bank(f)
	var r1: bool = smithy.research(id1)
	var r2: bool = smithy.research(id2)
	var bank1: Dictionary = _bank(f)
	var spent_both: bool = not _bank_equal(bank0, bank1)
	var ok1: bool = r1 and r2 and smithy.research_id == id1 \
		and smithy.queue_position(id2) == 1 and spent_both
	verdict("B1 занятая кузница ставит второй заказ в очередь", ok1,
		"текущее=%s, место %s=%d" % [smithy.research_id, id2,
			smithy.queue_position(id2)])

	# B2 — повторный заказ того же слота отбивается (он уже помечен «в работе»)
	var ok2: bool = not smithy.research(id2)
	verdict("B2 один и тот же слот нельзя заказать дважды", ok2)

	# B3 — ОТМЕНА ОЧЕРЕДНОГО: возврат 100 % и слот снова доступен
	var before: Dictionary = _bank(f)
	var cost2: Dictionary  = _UCfg.upgrade_cost(_UCfg.get_upgrade_slot(id2))
	var cancelled: bool = smithy.cancel_research(id2)
	var after: Dictionary = _bank(f)
	var refunded := true
	for k in cost2.keys():
		var want: float = float(before.get(int(k), 0.0)) + float(cost2[k])
		if absf(float(after.get(int(k), 0.0)) - want) > 0.01:
			refunded = false
	var ok3: bool = cancelled and refunded \
		and smithy.queue_position(id2) == -1 \
		and GameManager.can_research(f, id2)
	verdict("B3 ПКМ-отмена очередного возвращает 100 % цены", ok3,
		"возврат=%s, слот снова доступен=%s" % [str(refunded),
			str(GameManager.can_research(f, id2))])

	# B4 — ОТМЕНА ТЕКУЩЕГО: следующий из очереди сразу занимает его место
	smithy.research(id2)
	smithy.research(id3)
	var was_next: String = id2 if smithy.queue_position(id2) == 1 else id3
	var ok4: bool = smithy.cancel_research(smithy.research_id) \
		and smithy.research_id == was_next \
		and smithy.research_progress() <= 0.001
	verdict("B4 отмена текущего пропускает вперёд следующего из очереди", ok4,
		"теперь качается %s" % smithy.research_id)

	# B5 — очередь не бесконечная
	var added := 0
	for s in _UCfg.UPGRADE_SLOTS:
		var d: Dictionary = s
		if smithy.research(String(d.get("id", ""))):
			added += 1
	var ok5: bool = smithy.research_queue.size() <= smithy.QUEUE_MAX
	verdict("B5 очередь ограничена QUEUE_MAX", ok5,
		"в очереди %d при пределе %d" % [smithy.research_queue.size(),
			smithy.QUEUE_MAX])

	# B6 — исследование завершается по таймеру и подтягивает следующее
	var cur: String  = smithy.research_id
	var next: String = String((smithy.research_queue[0] as Dictionary).get("id", "")) \
		if not smithy.research_queue.is_empty() else ""
	smithy.research_timer = smithy.research_time   # домотать до конца
	await frames(3)
	var ok6: bool = GameManager.is_researched(f, cur) \
		and (next.is_empty() or smithy.research_id == next)
	verdict("B6 готовое исследование применяется и очередь двигается", ok6,
		"'%s' изучено, качается '%s'" % [cur, smithy.research_id])

	# ── HUD ──────────────────────────────────────────────────────────────────
	# ПАНЕЛЬ КУЗНИЦЫ — ЭТО ДРЕВО ТЕХНОЛОГИЙ (2026-08-07), а не строка кнопок в
	# общей нижней панели: старые плоские слоты (B1-B6 выше проверяют логику
	# очереди на них и это по-прежнему корректно) на ней не рисуются вовсе.
	# Поэтому для проверок ВИДА берём узлы открытой вкладки древа: смысл
	# требований прежний, сменились источник слотов и контейнеры
	hud.show_selection([smithy])
	await frames(2)
	# Один узел древа доводим до «изучено» — галочку ищем именно на сетке.
	# Заказ для проверки очереди берём ТОТ, ЧТО УЖЕ В НЕЙ СТОИТ: B5 выше
	# намеренно забила очередь до QUEUE_MAX, и добавить туда ещё один нечего.
	# Ряд очереди рисует любой заказанный слот, из древа он или из плоского
	# списка — _research_slot читает его через общий get_upgrade_slot
	var done_id: String = ""
	for n in _Forge.tree(hud._forge_unit):
		var d: Dictionary = n
		var nid: String = String(d.get("id", ""))
		if GameManager.can_research(f, nid):
			done_id = nid
			break
	if not done_id.is_empty():
		GameManager.research_upgrade(f, done_id)
	var queued_id: String = ""
	if not smithy.research_queue.is_empty():
		queued_id = String((smithy.research_queue[0] as Dictionary).get("id", ""))
	hud.show_selection([smithy])
	await frames(2)

	var btn_done: Button = hud._forge_nodes.get(done_id, null) as Button
	if btn_done != null and btn_done.get_node_or_null("DoneCheck") == null:
		btn_done = null
	var btn_queued: Button = hud._forge_queue.get_node_or_null(
		"ResearchSlot_" + queued_id) as Button

	# B7 — купленное НЕ становится тёмной плашкой: приглушение светлое
	var bright: float = 0.0
	if btn_done != null:
		bright = (btn_done.modulate.r + btn_done.modulate.g + btn_done.modulate.b) / 3.0
	var ok7: bool = btn_done != null and bright >= 0.75 and btn_done.modulate.a >= 0.95
	verdict("B7 изученное: светлое приглушение + зелёная галочка", ok7,
		"яркость %0.2f, alpha %0.2f" % [bright,
			btn_done.modulate.a if btn_done != null else -1.0])

	# B8 — заказ виден в ряду очереди исследований, и его ячейка ЖИВАЯ
	# (отключённая Button не пропускает мышь, а по ней должен работать ПКМ)
	var ok8: bool = btn_queued != null and not btn_queued.disabled
	verdict("B8 заказ виден в ряду очереди и принимает ПКМ", ok8,
		"ячейка найдена=%s, всего ячеек=%d" % [
			str(btn_queued != null), hud._forge_queue.get_child_count()])

	# B9 — ПКМ по кнопке действительно снимает заказ и возвращает ресурсы
	var ok9 := false
	if btn_queued != null and not queued_id.is_empty():
		var b9: Dictionary = _bank(f)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = true
		btn_queued.gui_input.emit(ev)
		await frames(2)
		var cost9: Dictionary = _UCfg.upgrade_cost(_UCfg.get_upgrade_slot(queued_id))
		var back := true
		for k in cost9.keys():
			var want9: float = float(b9.get(int(k), 0.0)) + float(cost9[k])
			if absf(ResourceManager.get_amount(f, int(k)) - want9) > 0.01:
				back = false
		ok9 = back and smithy.queue_position(queued_id) == -1
	verdict("B9 ПКМ по ячейке очереди снимает заказ и возвращает цену", ok9)

	hud.show_selection([])
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# C. БОНУСЫ ОТРЯДА: ИКОНКИ, СТЕК, ПОДСКАЗКА
# ═════════════════════════════════════════════════════════════════════════════

func _make_squad(n: int, pos: Vector3, p_faction: int = Constants.FACTION_PLAYER) -> int:
	var sid: int = GameManager.new_squad(p_faction, "spearman")
	for i in range(n):
		var u := Spearman.new()
		u.faction = p_faction
		main.world_add(u)
		u.global_position = pos + Vector3(float(i % 5) * 0.8, 0.0, float(i / 5) * 0.8)
		GameManager.add_to_squad(sid, u)
	await frames(2)
	return sid

## Найти узел по имени вглубь
func _find_deep(root: Node, nm: String) -> Node:
	if root == null:
		return null
	if root.name == nm:
		return root
	for c in root.get_children():
		var r: Node = _find_deep(c, nm)
		if r != null:
			return r
	return null

func _block_c() -> void:
	print("\n═════ C. БОНУСЫ ОТРЯДА ═════")
	var sid: int = await _make_squad(6, Vector3(-380.0, 0.0, 380.0))

	# Берём ОДИН И ТОТ ЖЕ вид награды на трёх первых уровнях — это и есть стек.
	# Индекс берём из конфига по id, а не числом: порядок кнопок может меняться
	var utype := "spearman"   # тот же тип, что и у _make_squad ниже
	var want_id: String = String((_UCfg.veteran_choices(utype, 1)[0] as Dictionary).get("id", ""))
	var levels_taken: Array = []
	var maxl: int = mini(3, _UCfg.max_veteran_level(utype))
	for lvl in range(1, maxl + 1):
		var idx := -1
		var choices: Array = _UCfg.veteran_choices(utype, lvl)
		for i in range(choices.size()):
			if String((choices[i] as Dictionary).get("id", "")) == want_id:
				idx = i
				break
		if idx < 0:
			continue
		GameManager.squads[sid]["level"]   = lvl
		GameManager.squads[sid]["pending"] = 1
		if GameManager.apply_veteran_choice(sid, idx):
			levels_taken.append(lvl)
	await frames(1)

	# C1 — выборы записаны по порядку уровней, повторы сохранены
	var chosen: Array = GameManager.squad_chosen(sid)
	var ok1: bool = chosen.size() == levels_taken.size() and chosen.size() >= 2
	for c in chosen:
		if String(c) != want_id:
			ok1 = false
	verdict("C1 squad_chosen хранит повторы по уровням", ok1,
		"chosen=%s" % str(chosen))

	# C2 — римские цифры
	var ok2: bool = hud._roman(1) == "I" and hud._roman(2) == "II" \
		and hud._roman(3) == "III" and hud._roman(4) == "IV" \
		and hud._roman(5) == "V" and hud._roman(9) == "IX"
	verdict("C2 римская запись стека (I, II, III, IV, V, IX)", ok2)

	# C3 — иконки уменьшены ровно на 30 %
	var ok3: bool = absf(hud.BONUS_ICON_SIZE - hud.BONUS_ICON_BASE * 0.7) < 0.001
	verdict("C3 иконка бонуса −30 % от базовой", ok3,
		"%0.1f → %0.1f" % [hud.BONUS_ICON_BASE, hud.BONUS_ICON_SIZE])

	# C4 — панель отряда строит ряд: ОДНА иконка на вид бонуса со стеком
	var units: Array = GameManager.squad_members(sid)
	hud._show_stat_panel(sid, units)
	await frames(2)
	var row: Node = _find_deep(hud, "BonusRow")
	var icon_count: int = row.get_child_count() if row != null else -1
	var holder: Control = null
	if row != null and row.get_child_count() > 0:
		holder = row.get_child(0) as Control
	var stack_lbl: Label = null
	if holder != null:
		stack_lbl = holder.get_node_or_null("Stack") as Label
	var ok4: bool = icon_count == 1 and stack_lbl != null \
		and stack_lbl.text == hud._roman(chosen.size()) \
		and holder.get_node_or_null("DoneCheck") == null \
		and absf(holder.custom_minimum_size.x - hud.BONUS_ICON_SIZE) < 0.01
	verdict("C4 ряд бонусов: одна иконка со стеком, без галочки", ok4,
		"иконок=%d, стек='%s'" % [icon_count,
			stack_lbl.text if stack_lbl != null else "нет"])

	# C5 — окно-подсказка по наведению, суммы посчитаны ПО УРОВНЯМ из конфига
	var total: float = 0.0
	for l in levels_taken:
		total += float(_UCfg.veteran_choice_at(utype, int(l), want_id).get("value", 0.0))
	var ok5 := false
	var tip_txt := ""
	if holder != null:
		holder.mouse_entered.emit()
		await frames(1)
		var tip: Node = _find_deep(hud, "BonusTip")
		if tip != null:
			for lb in _labels_of(tip):
				tip_txt += lb.text + " | "
			var fmt: String = "%.1f" if want_id == "speed" else "%.0f"
			ok5 = tip_txt.contains(fmt % total) \
				and tip_txt.contains(hud._roman(chosen.size()))
	verdict("C5 подсказка показывает стек и суммарный прирост", ok5,
		"ожидали +%0.2f; текст: %s" % [total, tip_txt.substr(0, 110)])

	# C6 — подсказка исчезает вместе с панелью (не остаётся висеть на экране)
	hud._hide_stat_panel()
	await frames(2)
	var ok6: bool = _find_deep(hud, "BonusTip") == null \
		and _find_deep(hud, "BonusRow") == null
	verdict("C6 подсказка и ряд убираются вместе с панелью", ok6)

	for u in units:
		if is_instance_valid(u):
			u.queue_free()
	await frames(2)

func _labels_of(root: Node) -> Array:
	var out: Array = []
	if root is Label:
		out.append(root)
	for c in root.get_children():
		out += _labels_of(c)
	return out

# ═════════════════════════════════════════════════════════════════════════════
# D. БЕГ ПО ДВОЙНОМУ ПКМ
# ═════════════════════════════════════════════════════════════════════════════

func _block_d() -> void:
	print("\n═════ D. БЕГ (SPRINT) ═════")

	# D1 — промежуточных режимов скорости не осталось: есть только бег
	var consts: Dictionary = (Unit as GDScript).get_script_constant_map()
	var ok1: bool = consts.has("SPRINT_SPEED_FACTOR") \
		and not consts.has("MARCH_SPEED_FACTOR")
	verdict("D1 маршевого множителя больше нет, есть только бег", ok1,
		"SPRINT=%0.2f" % float(consts.get("SPRINT_SPEED_FACTOR", 0.0)))

	var sid: int = await _make_squad(4, Vector3(300.0, 0.0, 300.0))
	var members: Array = GameManager.squad_members(sid)
	var u: Unit = members[0]

	# D2 — бег ровно в SPRINT_SPEED_FACTOR раз быстрее обычного шага
	u.command_move(Vector3(340.0, 0.0, 300.0), false, Vector3.ZERO, false, true, false)
	await frames(2)
	var walk_v: float = u._effective_speed()
	u.command_move(Vector3(340.0, 0.0, 300.0), false, Vector3.ZERO, false, true, true)
	await frames(2)
	var run_v: float = u._effective_speed()
	var kf: float = float(consts.get("SPRINT_SPEED_FACTOR", 1.0))
	var ok2: bool = u.sprinting and walk_v > 0.0 \
		and absf(run_v - walk_v * kf) < 0.05
	verdict("D2 скорость бега = шаг × SPRINT_SPEED_FACTOR", ok2,
		"%0.2f → %0.2f (ожидали %0.2f)" % [walk_v, run_v, walk_v * kf])

	# D3 — на бегу копья ПОДНЯТЫ даже в стойке «держать позицию».
	# Id стойки берём из конфига по признаку holds_ground, а не строкой
	var hold_stance := ""
	for k in _UCfg.STANCES.keys():
		if bool((_UCfg.STANCES[k] as Dictionary).get("holds_ground", false)):
			hold_stance = String(k)
			break
	var sp: Spearman = u as Spearman
	sp.set_stance(hold_stance)
	sp._live_rank = 0
	var leveled_run: bool = sp._spear_leveled()
	sp._set_sprinting(false)
	sp._spear_leveled()          # вход в стойку заводит личную задержку
	sp._spear_ready_ms = 0       # ...её на стенде не ждём
	var leveled_walk: bool = sp._spear_leveled()
	verdict("D3 на бегу фаланга распускается, шагом — нет",
		(not leveled_run) and leveled_walk,
		"стойка '%s': бег=%s, шаг=%s" % [hold_stance, str(leveled_run),
			str(leveled_walk)])

	# D4 — на бегу отряд не ввязывается в бой, но урон получает
	var run_sid: int = await _make_squad(4, Vector3(-300.0, 0.0, 300.0))
	var runners: Array = GameManager.squad_members(run_sid)
	var foe := Spearman.new()
	foe.faction = Constants.FACTION_ENEMY
	main.world_add(foe)
	foe.global_position = Vector3(-290.0, 0.0, 300.0)
	await frames(2)
	for m in runners:
		(m as Unit).command_move(Vector3(-275.0, 0.0, 300.0),
			false, Vector3.ZERO, false, true, true)
	var hp_before: float = (runners[0] as Unit).current_health
	(runners[0] as Unit).take_damage(5.0, foe)
	await frames(420)
	var engaged := 0
	var passed := 0
	for m in runners:
		var mu: Unit = m
		if not is_instance_valid(mu):
			continue
		if mu.attack_target != null:
			engaged += 1
		if mu.global_position.x > -287.0:
			passed += 1
	# Враг не должен получить НИ ЦАРАПИНЫ: бегущие не бьют вообще
	var foe_intact: bool = is_instance_valid(foe) \
		and foe.current_health >= foe.max_health
	var ok4: bool = engaged == 0 and passed == runners.size() and foe_intact \
		and (runners[0] as Unit).current_health < hp_before
	verdict("D4 бегущие игнорируют авто-бой, но урон получают", ok4,
		"в бою=%d, прошли мимо=%d/%d, враг цел=%s, HP %0.1f→%0.1f" % [engaged,
			passed, runners.size(), str(foe_intact), hp_before,
			(runners[0] as Unit).current_health])

	# D5 — по прибытии бег гаснет сам
	await frames(360)
	var still_running := 0
	for m in runners:
		if is_instance_valid(m) and (m as Unit).sprinting:
			still_running += 1
	verdict("D5 по прибытии бег выключается сам", still_running == 0,
		"ещё бегут: %d" % still_running)

	# D6 — контроль: ОБЫЧНЫЙ приказ по-прежнему перехватывается врагом
	var walk_sid: int = await _make_squad(4, Vector3(-300.0, 0.0, 340.0))
	var walkers: Array = GameManager.squad_members(walk_sid)
	var foe2 := Spearman.new()
	foe2.faction = Constants.FACTION_ENEMY
	main.world_add(foe2)
	foe2.global_position = Vector3(-290.0, 0.0, 340.0)
	await frames(2)
	for m in walkers:
		(m as Unit).command_move(Vector3(-275.0, 0.0, 340.0),
			false, Vector3.ZERO, false, true, false)
	var foe2_hp: float = foe2.max_health
	await frames(420)
	# Проверяем СЛЕД боя, а не мгновенный attack_target: четверо копейщиков
	# успевают добить одиночку и снова уйти в марш до момента замера
	var hurt: bool = (not is_instance_valid(foe2)) or foe2.is_dead() \
		or foe2.current_health < foe2_hp
	var eng2 := 0
	for m in walkers:
		if is_instance_valid(m) and (m as Unit).attack_target != null:
			eng2 += 1
	verdict("D6 без бега враг по-прежнему перехватывает марш", hurt,
		"враг получил урон=%s, в бою сейчас: %d из %d" % [str(hurt), eng2,
			walkers.size()])

	# D7 — распознавание двойного ПКМ в SelectionManager
	var p := Vector2(400.0, 300.0)
	var first: bool = sm._consume_rmb_double(p)
	var second: bool = sm._consume_rmb_double(p + Vector2(3.0, 2.0))
	var third: bool = sm._consume_rmb_double(p)
	# далёкий второй клик двойным не считается
	sm._last_rmb_time = -10.0
	var far_a: bool = sm._consume_rmb_double(p)
	var far_b: bool = sm._consume_rmb_double(p + Vector2(400.0, 0.0))
	var ok7: bool = (not first) and second and (not third) \
		and (not far_a) and (not far_b)
	verdict("D7 двойной ПКМ распознаётся, тройной сбрасывается", ok7,
		"[%s %s %s] далеко=[%s %s]" % [str(first), str(second), str(third),
			str(far_a), str(far_b)])
