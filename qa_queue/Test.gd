extends Node

## СТЕНД ПАКЕТА «ОЧЕРЕДЬ ПКМ + ФИЛЬТР ТИПОВ»
##   1 ОТМЕНА ПКМ  — cancel_order снимает последний заказ и возвращает ровно
##                   столько ресурсов, сколько было списано
##   2 ЦИФРА       — ярлык на иконке найма показывает число заказов этого типа
##   3 ОДНА ПОЛОСА — большой прогресс-бар при найме скрыт, полоса только на
##                   иконке в колонке очереди; у исследования бар остаётся
##   4 ФИЛЬТР      — панель мультивыделения в левом нижнем углу и keep_only_type

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var hud = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	await frames(2)
	hud = main.hud
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 100000.0)
	await frames(1)

	await _test_cancel_refund()
	await _test_cancel_active()
	await _test_badges()
	await _test_single_bar()
	await _test_type_filter()
	_summary()
	print("\n=== QUEUE TEST DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-58s %s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

## Снимок банка игрока по всем четырём ресурсам
func _bank() -> Dictionary:
	var d: Dictionary = {}
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		d[int(t)] = ResourceManager.get_amount(Constants.FACTION_PLAYER, int(t))
	return d

func _bank_delta(a: Dictionary, b: Dictionary) -> float:
	var s := 0.0
	for key in a:
		s += absf(float(b[key]) - float(a[key]))
	return s

## ПРИТОРМОЗИТЬ ПРОИЗВОДСТВО НА ВРЕМЯ ПРОВЕРКИ ОЧЕРЕДИ.
##
## В балансной ведомости владельца время найма сейчас НОЛЬ (см. TRAINING в
## unit_stats_config.gd): заказ выполняется в тот же кадр, очередь опустошается
## мгновенно, и проверять на ней интерфейс очереди попросту нечего — стенд
## видел «2» вместо «3» и пустую очередь там, где ждал заказ. Конфиг прав, а
## стенд проверяет ВЁРСТКУ очереди, а не баланс, поэтому подменяем время уже
## поставленным в очередь заказам: каждый элемент хранит своё "time" сам
## (см. Building._process), так что конфига это не касается
func _hold(b: Building, secs: float = 60.0) -> void:
	for item in b.production_queue:
		(item as Dictionary)["time"] = secs

func _new_barracks(at: Vector3) -> Barracks:
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = at
	return b

# ═════════════════════════════════════════════════════════════════════════════
# 1. ОТМЕНА ПКМ С ВОЗВРАТОМ
# ═════════════════════════════════════════════════════════════════════════════
func _test_cancel_refund() -> void:
	print("\n═════ 1. ОТМЕНА ЗАКАЗА ПКМ: ВОЗВРАТ РЕСУРСОВ ═════")
	var b := _new_barracks(Vector3(-120.0, 0.0, -120.0))
	await frames(2)

	var before := _bank()
	print("  банк до заказов: %s" % str(before))
	var cost: Dictionary = _UCfg.train_cost("barracks", "spearman")
	print("  цена копейщиков по конфигу: %s" % str(cost))

	# Три заказа копейщиков и два лучников
	for _i in range(3):
		b.train_from_config("spearman")
	for _i in range(2):
		b.train_from_config("archer")
	await frames(1)
	var after_queue := _bank()
	print("  очередь: %d заказов, банк после списания: %s" % [
		b.production_queue.size(), str(after_queue)])
	print("  списано суммарно: %.0f" % _bank_delta(before, after_queue))

	# Отменяем всё в обратном порядке — банк обязан вернуться к исходному
	var cancels := 0
	while b.production_queue.size() > 0:
		var uid := "spearman" if cancels % 2 == 0 else "archer"
		if not b.cancel_order(uid):
			# этого типа больше нет — снимаем оставшийся
			uid = "archer" if uid == "spearman" else "spearman"
			if not b.cancel_order(uid):
				break
		cancels += 1
	await frames(1)
	var after_cancel := _bank()
	var diff := _bank_delta(before, after_cancel)
	print("  отменено заказов: %d, очередь: %d" % [cancels, b.production_queue.size()])
	print("  банк после отмены: %s" % str(after_cancel))
	print("  расхождение с исходным банком: %.2f" % diff)
	verdict("1a отмена возвращает ресурсы полностью", diff < 0.01,
		"расхождение %.2f" % diff)
	verdict("1b очередь пуста после отмены всех", b.production_queue.size() == 0,
		"осталось %d" % b.production_queue.size())

	# Отмена в пустой очереди ничего не ломает и не печатает деньги
	var empty_before := _bank()
	var got: bool = b.cancel_order("spearman")
	await frames(1)
	var empty_diff := _bank_delta(empty_before, _bank())
	print("  отмена в пустой очереди: вернула %s, изменение банка %.2f" % [
		str(got), empty_diff])
	verdict("1c отмена пустой очереди безвредна", (not got) and empty_diff < 0.01)
	b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 2. ОТМЕНА АКТИВНОГО ЗАКАЗА
# ═════════════════════════════════════════════════════════════════════════════
func _test_cancel_active() -> void:
	print("\n═════ 2. ОТМЕНА АКТИВНОГО (НУЛЕВОГО) ЗАКАЗА ═════")
	var b := _new_barracks(Vector3(-140.0, 0.0, -120.0))
	await frames(2)
	b.train_from_config("spearman")
	b.train_from_config("spearman")
	_hold(b)                  # иначе оба заказа выполнятся в тот же кадр
	await frames(20)          # первый заказ успел набрать прогресс
	var t_before: float = b._production_timer
	print("  прогресс активного заказа до отмены: %.3f с" % t_before)

	# ПКМ снимает ПОСЛЕДНИЙ заказ — таймер активного трогать нельзя
	b.cancel_order("spearman")
	await frames(1)
	var t_mid: float = b._production_timer
	print("  после отмены хвостового: очередь=%d, таймер=%.3f с" % [
		b.production_queue.size(), t_mid])
	verdict("2a отмена хвоста не сбрасывает прогресс активного",
		b.production_queue.size() == 1 and t_mid >= t_before - 0.001,
		"было %.3f стало %.3f" % [t_before, t_mid])

	# Теперь снимаем сам активный — таймер обязан обнулиться
	b.cancel_order("spearman")
	await frames(1)
	print("  после отмены активного: очередь=%d, таймер=%.3f с" % [
		b.production_queue.size(), b._production_timer])
	verdict("2b отмена активного обнуляет таймер",
		b.production_queue.is_empty() and b._production_timer == 0.0)
	b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 3. ЦИФРА КОЛИЧЕСТВА НА ИКОНКЕ
# ═════════════════════════════════════════════════════════════════════════════
func _test_badges() -> void:
	print("\n═════ 3. ЦИФРА ЗАКАЗОВ НА ИКОНКЕ НАЙМА ═════")
	var b := _new_barracks(Vector3(-160.0, 0.0, -120.0))
	await frames(2)
	hud.show_selection([b])
	await frames(2)

	print("  ярлыков создано: %d, ключи: %s" % [
		hud._train_badges.size(), str(hud._train_badges.keys())])
	verdict("3a ярлык есть у каждого типа найма",
		hud._train_badges.has("spearman") and hud._train_badges.has("archer"),
		str(hud._train_badges.keys()))

	var spear_lbl: Label = hud._train_badges.get("spearman")
	var arch_lbl: Label  = hud._train_badges.get("archer")
	print("  пустая очередь: копейщик видим=%s, лучник видим=%s" % [
		str(spear_lbl.visible), str(arch_lbl.visible)])
	verdict("3b при пустой очереди цифры скрыты",
		(not spear_lbl.visible) and (not arch_lbl.visible))

	for _i in range(3):
		b.train_from_config("spearman")
	b.train_from_config("archer")
	_hold(b)
	hud._refresh_train_badges(b)
	await frames(1)
	print("  очередь 3 копейщика + 1 лучник: «%s» (видим=%s) / «%s» (видим=%s)" % [
		spear_lbl.text, str(spear_lbl.visible), arch_lbl.text, str(arch_lbl.visible)])
	verdict("3c цифры совпадают с очередью",
		spear_lbl.text == "3" and spear_lbl.visible
		and arch_lbl.text == "1" and arch_lbl.visible,
		"%s / %s" % [spear_lbl.text, arch_lbl.text])

	# ПКМ по кнопке копейщиков: −1 и цифра обновляется тем же кадром
	var btn: Button = hud.button_container.get_child(0)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	hud._on_train_rmb(ev, b, "spearman")
	await frames(1)
	print("  после одного ПКМ: очередь копейщиков=%d, цифра «%s»" % [
		b.queued_count("spearman"), spear_lbl.text])
	verdict("3d ПКМ снимает ровно один заказ",
		b.queued_count("spearman") == 2 and spear_lbl.text == "2",
		"очередь %d, цифра %s" % [b.queued_count("spearman"), spear_lbl.text])

	# Дожимаем до нуля — ярлык обязан спрятаться
	hud._on_train_rmb(ev, b, "spearman")
	hud._on_train_rmb(ev, b, "spearman")
	await frames(1)
	print("  очередь копейщиков опустела: видим=%s" % str(spear_lbl.visible))
	verdict("3e на нуле цифра прячется",
		b.queued_count("spearman") == 0 and not spear_lbl.visible)

	# Ярлык не мешает клику: MOUSE_FILTER_IGNORE и он внутри кнопки
	print("  фильтр мыши у ярлыка: %d (2 = IGNORE), родитель кнопки: %s" % [
		int(spear_lbl.mouse_filter), str(spear_lbl.get_parent() is Button)])
	verdict("3f ярлык не перехватывает клики",
		spear_lbl.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and spear_lbl.get_parent() is Button)

	# ЛКМ по самой кнопке всё ещё заказывает
	# Кнопки без текста (на них только иконка), поэтому берём по порядку:
	# у бараков это [0] копейщик, [1] лучник
	var q_before: int = b.queued_count("archer")
	btn = hud.button_container.get_child(1) as Button
	if btn != null:
		btn.emit_signal("pressed")
		_hold(b)
		await frames(1)
		print("  ЛКМ по кнопке лучника: очередь %d → %d" % [
			q_before, b.queued_count("archer")])
		verdict("3g ЛКМ по кнопке по-прежнему заказывает",
			b.queued_count("archer") == q_before + 1)
	else:
		verdict("3g ЛКМ по кнопке по-прежнему заказывает", false, "кнопка не найдена")

	hud.show_selection([])
	b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 4. ОДНА ПОЛОСА ПРОГРЕССА
# ═════════════════════════════════════════════════════════════════════════════
func _test_single_bar() -> void:
	print("\n═════ 4. ДУБЛИРУЮЩАЯ ПОЛОСА ПРОГРЕССА ═════")
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-180.0, 0.0, -140.0)
	await frames(2)
	hud.show_selection([castle])
	await frames(2)
	castle.train_from_config("worker")
	_hold(castle)
	await frames(6)

	var bars_in_queue := 0
	for slot in hud._queue_box.get_children():
		for node in _all_children(slot):
			if node is ProgressBar or node is TextureProgressBar:
				bars_in_queue += 1
	print("  замок производит: большой бар видим=%s, текст «%s»" % [
		str(hud.progress_bar.visible), hud.progress_label.text])
	print("  полос в колонке очереди: %d" % bars_in_queue)
	verdict("4a большой бар при найме скрыт", not hud.progress_bar.visible)
	verdict("4b полоса осталась ровно одна — на иконке", bars_in_queue == 1,
		"нашли %d" % bars_in_queue)

	# У ИССЛЕДОВАНИЯ большой бар обязан остаться
	var smithy := Smithy.new()
	smithy.faction = Constants.FACTION_PLAYER
	main.world_add(smithy)
	smithy.global_position = Vector3(-200.0, 0.0, -140.0)
	await frames(2)
	# СЛОТ ВЫБИРАЕТСЯ ПО can_research, А НЕ БЕРЁТСЯ UPGRADE_SLOTS[0].
	# У первого слота в балансной таблице владельца стоит заглушка
	# "requires": "Bla bla bla" — такого улучшения не существует, поэтому
	# can_research() отбивает его НАВСЕГДА, research() возвращает false и
	# исследование не начинается вовсе. Конфиг — источник правды, значит
	# стенд обязан спросить у него доступный слот, а не назначить первый
	var slot_id: String = ""
	for slot in _UCfg.UPGRADE_SLOTS:
		var sid: String = String((slot as Dictionary).get("id", ""))
		if GameManager.can_research(Constants.FACTION_PLAYER, sid) \
				and _UCfg.upgrade_research_time(slot) > 0.0:
			slot_id = sid
			break
	if slot_id != "":
		smithy.research(slot_id)
	hud.show_selection([smithy])
	await frames(6)
	print("  кузница исследует «%s»: большой бар видим=%s, текст «%s»" % [
		slot_id, str(hud.progress_bar.visible), hud.progress_label.text])
	verdict("4c у исследования большой бар остаётся", hud.progress_bar.visible)

	hud.show_selection([])
	castle.queue_free()
	smithy.queue_free()
	await frames(2)

func _all_children(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all_children(c))
	return out

# ═════════════════════════════════════════════════════════════════════════════
# 5. ПАНЕЛЬ ФИЛЬТРА ТИПОВ ПРИ МУЛЬТИВЫДЕЛЕНИИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_type_filter() -> void:
	print("\n═════ 5. ФИЛЬТР ТИПОВ В ЛЕВОМ НИЖНЕМ УГЛУ ═════")
	var sm = main.selection_manager
	var spears := _make_squad("spearman", 6, Vector3(-220.0, 0.0, -100.0))
	var archers := _make_squad("archer",   4, Vector3(-232.0, 0.0, -100.0))
	var worker_squads: Array = []
	var workers: Array = []
	for i in range(3):
		var w := _make_squad("worker", 1, Vector3(-244.0 - float(i) * 2.0, 0.0, -100.0))
		worker_squads.append(w)
		workers.append_array(w["units"])
	await frames(3)

	# Один тип — панели быть не должно
	sm.selected_units = spears["units"].duplicate()
	for u in sm.selected_units:
		u.set_selected(true)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	print("  выделен один тип (копейщики): панель=%s" % (
		"есть" if hud.type_slots() >= 2 else "нет"))
	verdict("5a один тип — панель фильтра не показывается", hud.type_slots() < 2)

	# Три типа: 1 отряд копейщиков + 1 лучников + 3 рабочих
	var all: Array = []
	all.append_array(spears["units"])
	all.append_array(archers["units"])
	all.append_array(workers)
	sm.selected_units = all.duplicate()
	for u in sm.selected_units:
		u.set_selected(true)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)

	print("  выделено бойцов: %d, отрядов: %d" % [
		sm.selected_units.size(), sm.selected_squad_ids().size()])
	# ПОЛОСА СВОДНЫХ ЯРЛЫКОВ — ЭТО УРОВЕНЬ 1 ДВУХУРОВНЕВОГО ВЫДЕЛЕНИЯ.
	# На смешанном выделении она показана ВМЕСТО детальной панели (жалоба на
	# дублирование была именно про «то же самое дважды», см. qa_sel2 A1),
	# а на однотипном — скрыта (проверка 5a выше)
	var want_types: int = 3          # копейщики + лучники + рабочие
	var panel = hud._overbar_row
	verdict("5b при трёх типах показана полоса групп, а не детальная панель",
		panel != null and hud._overbar.visible and hud.type_slots() == want_types
		and not hud._bottom_panel.visible,
		"слотов=%d панель=%s" % [hud.type_slots(), hud._bottom_panel.visible])
	if panel == null:
		_cleanup_units(all)
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	print("  панель: позиция=%s размер=%s, экран=%s" % [
		str(panel.global_position), str(panel.size), str(vp)])
	var bottom_left: bool = panel.global_position.x < vp.x * 0.3 \
		and panel.global_position.y + panel.size.y <= vp.y + 1.0 \
		and panel.global_position.y > vp.y * 0.4
	verdict("5c панель в левом нижнем углу", bottom_left,
		"x=%.0f y=%.0f h=%.0f" % [panel.global_position.x, panel.global_position.y, panel.size.y])
	# НЕ НАЕЗЖАЕТ НИ НА ЧТО. Раньше сравнивали с hud.PANEL_TOP; теперь на
	# уровне 1 детальной панели НЕТ ВОВСЕ, и полоса законно опускается на её
	# место (см. HUD._position_group_bar). Проверяем то, что осталось верным:
	# полоса целиком на экране и, если панель всё же видна, не залезает на неё
	var limit: float = vp.y
	if hud._bottom_panel.visible:
		limit = vp.y + float(hud.PANEL_TOP)
	print("  низ полосы=%.0f, предел=%.0f (панель видна: %s)" % [
		panel.global_position.y + panel.size.y, limit, hud._bottom_panel.visible])
	verdict("5d полоса групп не наезжает на нижнюю панель и не уходит за экран",
		panel.global_position.y + panel.size.y <= limit + 1.0)

	# ЯЧЕЙКИ ЛЕЖАТ ПРЯМО В ПОЛОСЕ. Ярлыка «рабочие без дела» здесь больше нет —
	# он давно самостоятельный виджет под панелью ресурсов, поэтому последний
	# слот больше НЕ выбрасывается: все дети полосы — это типы войск
	var slots: Array = []
	for slot in panel.get_children():
		slots.append(slot)
	print("  ячеек в панели: %d" % slots.size())
	verdict("5e ячейка на каждый тип", slots.size() == want_types,
		"нашли %d, ожидали %d" % [slots.size(), want_types])
	for slot in slots:
		var btn: Button = null
		var lbl: Label = null
		for c in slot.get_children():
			if c is Button:
				btn = c
			elif c is Label:
				lbl = c
		var badge := ""
		if btn != null:
			for c in btn.get_children():
				if c is Label:
					badge = (c as Label).text
		print("    ячейка: цифра отрядов «%s», подпись «%s»" % [badge, lbl.text if lbl else "—"])

	# Рабочих трое, каждый — свой отряд: цифра должна быть 3, а бойцов 3
	var worker_badge := ""
	var worker_caption := ""
	for slot in slots:
		for c in slot.get_children():
			if c is Label and String((c as Label).text).contains("бойц"):
				pass
	# Ищем ячейку рабочих по третьей позиции (порядок добавления = порядок типов)
	var w_slot = slots[2]
	for c in w_slot.get_children():
		if c is Button:
			for cc in c.get_children():
				if cc is Label:
					worker_badge = (cc as Label).text
		elif c is Label:
			worker_caption = (c as Label).text
	print("  ячейка рабочих: отрядов «%s», подпись «%s»" % [worker_badge, worker_caption])
	verdict("5f рабочий считается отдельным отрядом",
		worker_badge == "3" and worker_caption.begins_with("3"),
		"«%s» / «%s»" % [worker_badge, worker_caption])

	# Клик по ячейке лучников оставляет только их
	sm.keep_only_type("archer")
	await frames(2)
	var only_archers := true
	for u in sm.selected_units:
		if GameManager.squad_type((u as Unit).squad_id) != "archer":
			only_archers = false
	print("  после keep_only_type(«archer»): выделено %d бойцов, все лучники=%s" % [
		sm.selected_units.size(), str(only_archers)])
	verdict("5g клик оставляет только выбранный тип",
		only_archers and sm.selected_units.size() == archers["units"].size(),
		"%d из %d" % [sm.selected_units.size(), archers["units"].size()])

	# Снятые с выделения обязаны потерять подсветку (кольцо под ногами)
	# Подсветку теперь рисует общий MultiMesh, а не узел-ребёнок бойца
	# (см. SelectionDecalRenderer): спрашиваем реестр, а не дерево сцены
	var still_lit := 0
	for u in spears["units"]:
		if is_instance_valid(u) and GameManager.sel_decals.is_registered(u):
			still_lit += 1
	print("  копейщиков с висящей подсветкой: %d" % still_lit)
	verdict("5h снятые с выделения гасят подсветку", still_lit == 0)

	# Один тип остался — панель обязана исчезнуть
	print("  панель после фильтра: %s" % ("есть" if hud.type_slots() >= 2 else "нет"))
	verdict("5i после фильтра панель убирается", hud.type_slots() < 2)

	_cleanup_units(all)
	await frames(2)

## Отряд из n бойцов заданного типа, зарегистрированный в GameManager
func _make_squad(unit_id: String, n: int, at: Vector3) -> Dictionary:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, unit_id)
	var units: Array = []
	for i in range(n):
		var u: Unit = _spawn(unit_id)
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = at + Vector3(float(i) * 0.8, 0.0, 0.0)
		GameManager.add_to_squad(sid, u)
		units.append(u)
	return {"sid": sid, "units": units}

func _spawn(unit_id: String) -> Unit:
	match unit_id:
		"spearman": return Spearman.new()
		"archer":   return Archer.new()
		"warrior":  return Warrior.new()
		_:          return Worker.new()

func _cleanup_units(units: Array) -> void:
	var sm = main.selection_manager
	sm.selected_units = []
	GameManager.on_selection_changed([])
	for u in units:
		if is_instance_valid(u):
			u.queue_free()
