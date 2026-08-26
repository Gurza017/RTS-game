extends Node

## СТЕНД-ДОПОЛНЕНИЕ К qa_queue: то, чего первый стенд НЕ проверял.
##   6  НАСТОЯЩИЙ ПКМ — событие идёт через Viewport.push_input по реальной
##      кнопке, а не вызовом _on_train_rmb() руками; заодно проверяем, что оно
##      НЕ протекает в SelectionManager (иначе отряд получал бы приказ идти)
##   7  ЦИФРА САМА — ярлык обновляется из HUD._process, без ручного вызова
##   8  ЦЕНА В ЗАКАЗЕ — cost.duplicate() изолирует словарь вызывающего
##   9  КНОПКА ФИЛЬТРА — настоящий клик мышью по ячейке панели типов
##   10 ЗДАНИЕ В ВЫДЕЛЕНИИ — что с ним делает keep_only_type
##   11 ЧУЖИЕ ЮНИТЫ — панель фильтра не показывается
##   12 РЕГРЕССИИ — смена выделения, гарнизон, вёрстка панели, ветеранское меню

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _SpyScript := preload("res://qa_queue2/Spy.gd")

var main = null
var hud = null
var spy: Node = null
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
	# СТАРТ ПАРТИИ ТЕПЕРЬ СРАЗУ ВКЛЮЧАЕТ ВЫБОР МЕСТА ПОД ЗАМОК: под курсором
	# висит фантом, а Main._input в этом режиме СЪЕДАЕТ правый клик (это отмена
	# постройки). Стенд проверяет ПКМ по иконке очереди, поэтому режим выбора
	# места сначала закрываем — иначе клик до интерфейса просто не доходит
	if main._phase == Main.Phase.PLACING_CASTLE:
		main._refund_and_cancel()
	await frames(2)
	hud = main.hud
	spy = Node.new()
	spy.set_script(_SpyScript)
	add_child(spy)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 500000.0)
	await frames(1)

	await _test_real_rmb()
	await _test_badge_selfupdate()
	await _test_cost_isolation()
	await _test_real_filter_click()
	await _test_building_in_selection()
	await _test_enemy_selection()
	await _test_regressions()
	await _test_dead_building()
	await _test_four_types()
	_summary()
	print("\n=== QUEUE2 TEST DONE ===")
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

func _new_barracks(at: Vector3) -> Barracks:
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = at
	return b

## Настоящий щелчок мышью: событие уходит в Viewport ровно как от драйвера
func _click(pos: Vector2, button: int) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed  = true
	down.position = pos
	down.global_position = pos
	get_viewport().push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed  = false
	up.position = pos
	up.global_position = pos
	get_viewport().push_input(up)

func _btn_center(btn: Control) -> Vector2:
	return btn.get_global_rect().get_center()

# ═════════════════════════════════════════════════════════════════════════════
# 6. НАСТОЯЩИЙ ПКМ ЧЕРЕЗ ОЧЕРЕДЬ ВВОДА
# ═════════════════════════════════════════════════════════════════════════════
func _test_real_rmb() -> void:
	print("\n═════ 6. ПКМ ПО КНОПКЕ ЧЕРЕЗ НАСТОЯЩИЙ ВВОД ═════")
	var b := _new_barracks(Vector3(-120.0, 0.0, -160.0))
	await frames(2)
	hud.show_selection([b])
	await frames(2)
	for _i in range(3):
		b.train_from_config("spearman")
	await frames(2)

	var btn: Button = hud.button_container.get_child(0) as Button
	var c := _btn_center(btn)
	print("  кнопка копейщика: rect=%s центр=%s" % [str(btn.get_global_rect()), str(c)])
	var spear_lbl: Label = hud._train_badges.get("spearman")
	print("  до клика: очередь=%d, цифра «%s»" % [b.queued_count("spearman"), spear_lbl.text])

	spy.reset()
	_click(c, MOUSE_BUTTON_RIGHT)
	await frames(2)
	print("  после ПКМ по кнопке: очередь=%d, цифра «%s», шпион поймал ПКМ=%d" % [
		b.queued_count("spearman"), spear_lbl.text, spy.rmb_press])
	verdict("6a настоящий ПКМ по иконке снимает заказ",
		b.queued_count("spearman") == 2, "осталось %d" % b.queued_count("spearman"))
	verdict("6b цифра обновилась без ручного вызова", spear_lbl.text == "2",
		"цифра «%s»" % spear_lbl.text)
	verdict("6c ПКМ по кнопке НЕ уходит в мир (нет приказа отряду)",
		spy.rmb_press == 0, "шпион поймал %d" % spy.rmb_press)

	# Контроль: тот же ПКМ мимо панели обязан дойти до мира — иначе проверка 6c
	# ничего не значит (шпион мог бы молчать всегда)
	spy.reset()
	_click(Vector2(640.0, 200.0), MOUSE_BUTTON_RIGHT)
	await frames(2)
	print("  контрольный ПКМ по центру экрана: шпион поймал ПКМ=%d" % spy.rmb_press)
	verdict("6d контроль: ПКМ мимо панели доходит до мира", spy.rmb_press == 1,
		"шпион поймал %d" % spy.rmb_press)

	# ЛКМ по той же кнопке — заказ обратно
	var before: int = b.queued_count("spearman")
	_click(c, MOUSE_BUTTON_LEFT)
	await frames(2)
	print("  ЛКМ по кнопке: очередь %d → %d" % [before, b.queued_count("spearman")])
	verdict("6e настоящий ЛКМ по иконке добавляет заказ",
		b.queued_count("spearman") == before + 1,
		"%d → %d" % [before, b.queued_count("spearman")])

	hud.show_selection([])
	b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 7. ЦИФРА ПАДАЕТ САМА, КОГДА ЗАКАЗ ВЫШЕЛ
# ═════════════════════════════════════════════════════════════════════════════
func _test_badge_selfupdate() -> void:
	print("\n═════ 7. ЦИФРА ПАДАЕТ САМА ПРИ ВЫХОДЕ ОТРЯДА ═════")
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-260.0, 0.0, -160.0)
	await frames(2)
	hud.show_selection([castle])
	await frames(2)
	castle.train_from_config("worker")
	castle.train_from_config("worker")
	await frames(2)
	var lbl: Label = hud._train_badges.get("worker")
	print("  два заказа рабочих: цифра «%s» видим=%s" % [lbl.text, str(lbl.visible)])
	verdict("7a два заказа — цифра 2", lbl.text == "2" and lbl.visible,
		"«%s»" % lbl.text)

	# Ускоряем текущий заказ, чтобы не ждать реальное время найма
	var head: Dictionary = castle.production_queue[0]
	head["time"] = 0.02
	var waited := 0
	while castle.queued_count("worker") > 1 and waited < 120:
		await frames(1)
		waited += 1
	await frames(2)
	print("  заказ вышел за %d кадров: очередь=%d, цифра «%s»" % [
		waited, castle.queued_count("worker"), lbl.text])
	verdict("7b после выхода отряда цифра сама стала 1",
		castle.queued_count("worker") == 1 and lbl.text == "1",
		"очередь %d, цифра «%s»" % [castle.queued_count("worker"), lbl.text])

	# Дожимаем второй заказ отменой — ярлык обязан спрятаться сам из _process
	castle.cancel_order("worker")
	await frames(3)
	print("  очередь опустела: цифра видима=%s" % str(lbl.visible))
	verdict("7c пустая очередь — цифра спряталась", not lbl.visible)

	hud.show_selection([])
	castle.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 8. ЦЕНА ЕДЕТ ВМЕСТЕ С ЗАКАЗОМ (cost.duplicate())
# ═════════════════════════════════════════════════════════════════════════════
func _test_cost_isolation() -> void:
	print("\n═════ 8. ЦЕНА ХРАНИТСЯ В ЗАКАЗЕ, А НЕ ПО ССЫЛКЕ ═════")
	var b := _new_barracks(Vector3(-300.0, 0.0, -160.0))
	await frames(2)

	var my_cost: Dictionary = {
		Constants.RESOURCE_GOLD: 111.0,
		Constants.RESOURCE_WOOD: 222.0,
	}
	var before := _bank()
	b.queue_unit("spearman", my_cost, 999.0)
	await frames(1)
	var spent := _bank_delta(before, _bank())
	print("  списано по заказу: %.0f (ожидалось 333)" % spent)

	# Словарь вызывающего меняется ПОСЛЕ заказа: заказ не должен это заметить
	my_cost[Constants.RESOURCE_GOLD] = 9999.0
	my_cost[Constants.RESOURCE_STONE] = 5000.0
	my_cost.erase(Constants.RESOURCE_WOOD)
	b.cancel_order("spearman")
	await frames(1)
	var diff := _bank_delta(before, _bank())
	print("  после порчи словаря и отмены: расхождение с исходным банком %.2f" % diff)
	verdict("8a списано ровно по цене заказа", absf(spent - 333.0) < 0.01,
		"списано %.0f" % spent)
	verdict("8b отмена вернула старую цену, порча словаря не подействовала",
		diff < 0.01, "расхождение %.2f" % diff)

	# Второй заказ той же ценой — она не «слиплась» с первым
	var before2 := _bank()
	b.queue_unit("spearman", {Constants.RESOURCE_GOLD: 50.0}, 999.0)
	b.queue_unit("spearman", {Constants.RESOURCE_GOLD: 70.0}, 999.0)
	await frames(1)
	b.cancel_order("spearman")   # снимается ПОСЛЕДНИЙ — тот, что за 70
	await frames(1)
	var d2 := _bank_delta(before2, _bank())
	print("  два разных по цене заказа, снят последний: списано %.0f (ожидалось 50)" % d2)
	verdict("8c отменяется последний заказ со своей ценой",
		absf(d2 - 50.0) < 0.01, "списано %.0f" % d2)
	b.cancel_order("spearman")
	b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 9. НАСТОЯЩИЙ КЛИК ПО ЯЧЕЙКЕ ПАНЕЛИ ФИЛЬТРА
# ═════════════════════════════════════════════════════════════════════════════
func _test_real_filter_click() -> void:
	print("\n═════ 9. КЛИК ПО ЯЧЕЙКЕ ФИЛЬТРА ТИПОВ ═════")
	var sm = main.selection_manager
	var spears := _make_squad("spearman", 5, Vector3(-320.0, 0.0, -60.0))
	var archers := _make_squad("archer",   3, Vector3(-330.0, 0.0, -60.0))
	await frames(2)

	# Выделение НАСТОЯЩИМ путём SelectionManager, а не присвоением массива
	sm._clear_selection()
	sm._select(spears["units"][0])
	sm._select(archers["units"][0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	print("  выделено бойцов: %d, отрядов: %d, панель=%s" % [
		sm.selected_units.size(), sm.selected_squad_ids().size(),
		"есть" if hud.type_slots() >= 2 else "нет"])
	verdict("9a выделение через SelectionManager поднимает панель",
		hud.type_slots() >= 2 and sm.selected_units.size() == 8,
		"бойцов %d" % sm.selected_units.size())
	if hud.type_slots() < 2:
		_cleanup(spears["units"] + archers["units"])
		return

	var slots := _filter_slots()
	print("  ячеек: %d" % slots.size())
	var arch_btn: Button = _slot_button(slots[1])
	var c := _btn_center(arch_btn)
	print("  ячейка лучников: rect=%s центр=%s" % [str(arch_btn.get_global_rect()), str(c)])
	spy.reset()
	_click(c, MOUSE_BUTTON_LEFT)
	await frames(3)
	# КОНТРАКТ ИЗМЕНИЛСЯ. Раньше клик по сводной ячейке СУЖАЛ выделение до
	# своего типа. Теперь он РАЗВОРАЧИВАЕТ группу на нижней панели отдельными
	# карточками отрядов (со шкалами здоровья), а выделение не трогает: сузить
	# его до одного отряда можно кликом по конкретной карточке
	var cards: int = hud._squad_strip.get_child_count()
	print("  после клика: выделено %d, карточек отрядов=%d, шпион поймал ЛКМ=%d" % [
		sm.selected_units.size(), cards, spy.lmb_press])
	verdict("9b клик мышью по ячейке разворачивает карточки отрядов этого типа",
		cards >= 1 and hud._expanded_type == "archer",
		"карточек %d, развёрнут «%s»" % [cards, hud._expanded_type])
	# А клик по карточке уже сужает выделение до одного отряда
	var card_btn: Button = _slot_button(hud._squad_strip.get_child(0))
	if card_btn != null:
		card_btn.emit_signal("pressed")
		await frames(2)
	var only_arch := true
	for u in sm.selected_units:
		if GameManager.squad_type((u as Unit).squad_id) != "archer":
			only_arch = false
	verdict("9b2 клик по карточке оставляет только этот отряд",
		only_arch and sm.selected_units.size() == 3,
		"%d бойцов, все лучники=%s" % [sm.selected_units.size(), str(only_arch)])
	verdict("9c клик по ячейке не сбрасывает выделение через мир",
		spy.lmb_press == 0, "шпион поймал %d" % spy.lmb_press)

	_cleanup(spears["units"] + archers["units"])
	await frames(2)

func _filter_slots() -> Array:
	var out: Array = []
	if hud.type_slots() < 2:
		return out
	# Ячейки лежат прямо в полосе баннера; ПОСЛЕДНЯЯ — «рабочие без дела»,
	# к разбивке типов войск она не относится
	for slot in hud._overbar_row.get_children():
		out.append(slot)
	if out.size() > 0:
		out.remove_at(out.size() - 1)
	return out

func _slot_button(slot: Node) -> Button:
	for c in slot.get_children():
		if c is Button:
			return c as Button
	return null

# ═════════════════════════════════════════════════════════════════════════════
# 10. ЗДАНИЕ, ПОПАВШЕЕ В СМЕШАННОЕ ВЫДЕЛЕНИЕ (Shift+клик по постройке)
# ═════════════════════════════════════════════════════════════════════════════
func _test_building_in_selection() -> void:
	print("\n═════ 10. ЗДАНИЕ В СМЕШАННОМ ВЫДЕЛЕНИИ ═════")
	var sm = main.selection_manager
	var spears := _make_squad("spearman", 4, Vector3(-360.0, 0.0, -60.0))
	var archers := _make_squad("archer",   2, Vector3(-370.0, 0.0, -60.0))
	var b := _new_barracks(Vector3(-380.0, 0.0, -60.0))
	await frames(2)

	sm._clear_selection()
	sm._select(spears["units"][0])
	sm._select(archers["units"][0])
	sm._select(b)              # Shift+клик по постройке делает ровно это
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	print("  выделено узлов: %d (в т.ч. постройка), панель=%s" % [
		sm.selected_units.size(), "есть" if hud.type_slots() >= 2 else "нет"])
	var ring_before: bool = b.selection_ring != null and b.selection_ring.visible
	print("  кольцо постройки до фильтра: %s" % str(ring_before))

	sm.keep_only_type("archer")
	await frames(2)
	var still_selected: bool = b in sm.selected_units
	var ring_after: bool = b.selection_ring != null and b.selection_ring.visible
	print("  после keep_only_type: постройка в выделении=%s, кольцо горит=%s" % [
		str(still_selected), str(ring_after)])
	verdict("10a постройка выброшена из выделения фильтром", not still_selected)
	verdict("10b подсветка выброшенной постройки погашена", not ring_after,
		"кольцо горит=%s" % str(ring_after))

	_cleanup(spears["units"] + archers["units"])
	b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 11. ЧУЖИЕ ЮНИТЫ В ВЫДЕЛЕНИИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_enemy_selection() -> void:
	print("\n═════ 11. ЧУЖИЕ ЮНИТЫ — ПАНЕЛИ НЕТ ═════")
	var sm = main.selection_manager
	var mine := _make_squad("spearman", 3, Vector3(-400.0, 0.0, -60.0))
	var foe := _make_squad_faction("archer", 3, Vector3(-410.0, 0.0, -60.0),
		Constants.FACTION_ENEMY)
	await frames(2)
	sm._clear_selection()
	sm.selected_units = mine["units"] + foe["units"]
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	print("  смешанное свой+чужой: панель=%s" % (
		"есть" if hud.type_slots() >= 2 else "нет"))
	verdict("11a чужие юниты в выделении — панель не показывается",
		hud.type_slots() < 2)
	_cleanup(mine["units"] + foe["units"])
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 12. РЕГРЕССИИ В СОСЕДНИХ МЕСТАХ
# ═════════════════════════════════════════════════════════════════════════════
func _test_regressions() -> void:
	print("\n═════ 12. РЕГРЕССИИ ═════")
	var sm = main.selection_manager
	var b := _new_barracks(Vector3(-440.0, 0.0, -160.0))
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-480.0, 0.0, -160.0)
	await frames(2)

	# 12a вёрстка нижней панели: число кнопок не зависит от наличия заказов
	hud.show_selection([b])
	await frames(2)
	var n_empty: int = hud.button_container.get_child_count()
	for _i in range(3):
		b.train_from_config("spearman")
	await frames(3)
	var n_busy: int = hud.button_container.get_child_count()
	print("  кнопок у барака: пустая очередь=%d, с очередью=%d" % [n_empty, n_busy])
	verdict("12a вёрстка нижней панели не зависит от очереди",
		n_empty == 2 and n_busy == 2, "%d / %d" % [n_empty, n_busy])

	# 12b смена выделения барак → замок: ярлыки пересобраны под новое здание
	hud.show_selection([castle])
	await frames(3)
	var keys: Array = hud._train_badges.keys()
	keys.sort()
	print("  ярлыки у замка: %s" % str(keys))
	verdict("12b при смене здания ярлыки пересобираются",
		keys == ["warrior", "worker"], str(keys))
	# и ни один ярлык не показывает чужую очередь
	var w_lbl: Label = hud._train_badges.get("worker")
	print("  у замка заказов нет: цифра рабочего видима=%s" % str(w_lbl.visible))
	verdict("12c ярлык нового здания не наследует чужую очередь", not w_lbl.visible)

	# 12d обратно на барак: старые ярлыки мертвы, новые живы, очередь та же
	hud.show_selection([b])
	await frames(3)
	var s_lbl: Label = hud._train_badges.get("spearman")
	print("  вернулись на барак: очередь=%d, цифра «%s» видима=%s" % [
		b.queued_count("spearman"), s_lbl.text, str(s_lbl.visible)])
	verdict("12d возврат на барак восстанавливает цифру",
		s_lbl.visible and s_lbl.text == "3",
		"«%s»" % s_lbl.text)
	while b.cancel_order("spearman"):
		pass

	# 12e гарнизон замка: полоса на месте, фильтр типов не лезет
	var gsq := _make_squad("spearman", 4, Vector3(-500.0, 0.0, -60.0))
	castle.garrison.append({"sid": int(gsq["sid"]), "type": "spearman", "revive": 0.0})
	hud.show_selection([castle])
	await frames(3)
	print("  замок с гарнизоном: полоса=%s, фильтр=%s" % [
		"есть" if hud._garrison_strip != null else "нет",
		"есть" if hud.type_slots() >= 2 else "нет"])
	verdict("12e гарнизонная полоса цела", hud._garrison_strip != null)
	verdict("12f фильтр типов не вылезает поверх гарнизона", hud.type_slots() < 2)
	castle.garrison.clear()

	# 12g ветеранское меню: отряд ждёт выбора награды
	var vsq := _make_squad("spearman", 4, Vector3(-520.0, 0.0, -60.0))
	var vsid: int = int(vsq["sid"])
	# Состояние «есть неразобранная награда» ставится ровно так же, как это
	# делает credit_kill: уровень поднялся, pending = сколько наград не выбрано
	GameManager.squads[vsid]["level"] = 1
	GameManager.squads[vsid]["pending"] = 1
	sm._clear_selection()
	sm._select(vsq["units"][0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)
	var n_vet: int = hud.button_container.get_child_count()
	print("  отряд ждёт награды: кнопок=%d, инфо «%s», фильтр=%s" % [
		n_vet, hud.info_label.text, "есть" if hud.type_slots() >= 2 else "нет"])
	# ── ПОДПИСЬ «★ Ветеран N» ЗАМЕНЕНА ФЛАЖКАМИ РАНГА ──────────────────────
	# Требование развёрнуто владельцем (авг. 2026): текст удалён целиком, на его
	# месте — знамёна «было → стало» (HUD._show_vet_rank_row). Проверяем то же
	# самое СВОЙСТВОМ: меню наград открыто и ряд флажков показан
	verdict("12g ветеранское меню на месте",
		n_vet > 0 and hud._vet_rank_row != null and hud._vet_rank_row.visible,
		"кнопок %d, флажки=%s" % [n_vet,
			str(hud._vet_rank_row != null and hud._vet_rank_row.visible)])
	verdict("12h один тип — фильтр не появляется рядом с наградами",
		hud.type_slots() < 2)

	# 12i панель фильтра не остаётся висеть после сброса выделения
	var other := _make_squad("archer", 3, Vector3(-540.0, 0.0, -60.0))
	sm._clear_selection()
	sm._select(vsq["units"][0])
	sm._select(other["units"][0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	var had: bool = hud.type_slots() >= 2
	sm._clear_selection()
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)
	print("  панель была=%s, после сброса выделения=%s" % [
		str(had), "есть" if hud.type_slots() >= 2 else "нет"])
	verdict("12i панель убирается вместе с выделением",
		had and hud.type_slots() < 2)

	# 12j счётчик бойцов в панели считает ЖИВЫХ, а не заявленных
	sm._clear_selection()
	sm._select(vsq["units"][0])
	sm._select(other["units"][0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	var slots := _filter_slots()
	var caps: Array = []
	for s in slots:
		for c in s.get_children():
			if c is Label:
				caps.append((c as Label).text)
	print("  подписи ячеек: %s (в отрядах 4 и 3 бойца)" % str(caps))
	verdict("12j подписи совпадают с составом отрядов",
		caps.size() == 2 and String(caps[0]).begins_with("4")
		and String(caps[1]).begins_with("3"), str(caps))

	_cleanup(gsq["units"] + vsq["units"] + other["units"])
	b.queue_free()
	castle.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 13. ВЫДЕЛЕННОЕ ЗДАНИЕ СНЕСЛИ, ПОКА ЕГО ПАНЕЛЬ НА ЭКРАНЕ
# Кнопки найма держат ссылку на здание в лямбде, а ярлык — его очередь.
# Если панель не убрать, клик по кнопке уходит в освобождённый объект.
# ═════════════════════════════════════════════════════════════════════════════
func _test_dead_building() -> void:
	print("\n═════ 13. СНОС ВЫДЕЛЕННОГО ЗДАНИЯ ═════")
	var b := _new_barracks(Vector3(-560.0, 0.0, -160.0))
	await frames(2)
	hud.show_selection([b])
	await frames(2)
	for _i in range(2):
		b.train_from_config("spearman")
	await frames(2)
	var lbl: Label = hud._train_badges.get("spearman")
	print("  барак выделен: кнопок=%d, цифра «%s»" % [
		hud.button_container.get_child_count(), lbl.text])

	b.take_damage(b.max_health * 2.0, null)
	await frames(4)
	# КОРЕНЬ ПРОБЛЕМЫ: в Godot 4 освобождённый объект РАВЕН null, поэтому
	# сторож «_selected_node != null and not is_instance_valid(...)» никогда
	# не срабатывал — панель мёртвого объекта не убиралась вообще
	print("  ДИАГ: валидно=%s, _selected_node=%s, (_selected_node == null)=%s, HUD тикает=%s" % [
		str(is_instance_valid(b)), str(hud._selected_node),
		str(hud._selected_node == null), str(hud.is_processing())])
	var left: int = hud.button_container.get_child_count()
	var stale := ""
	if is_instance_valid(lbl):
		stale = "«%s» видима=%s" % [lbl.text, str(lbl.visible)]
	else:
		stale = "ярлык удалён вместе с кнопкой"
	print("  барак снесён: кнопок найма на панели=%d, ярлык: %s" % [left, stale])
	# Оставшиеся кнопки — не косметика: они зовут лямбду с освобождённым
	# зданием и дают «SCRIPT ERROR: Nonexistent function ... in base 'Nil'».
	# На панели допустима только кнопка «Замок» из пустого выделения
	verdict("13a панель снесённого здания не оставляет кнопок найма",
		left <= 1, "осталось %d кнопок" % left)
	verdict("13b зависшей цифры заказов не остаётся",
		(not is_instance_valid(lbl)) or (not lbl.visible),
		stale)
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 14. ВСЕ ЧЕТЫРЕ ТИПА СРАЗУ — САМАЯ ШИРОКАЯ ПАНЕЛЬ ФИЛЬТРА
# ═════════════════════════════════════════════════════════════════════════════
func _test_four_types() -> void:
	print("\n═════ 14. ЧЕТЫРЕ ТИПА В ПАНЕЛИ ФИЛЬТРА ═════")
	var sm = main.selection_manager
	var made: Array = []
	var all: Array = []
	var z := -20.0
	for t in ["spearman", "archer", "warrior", "worker"]:
		var uid: String = String(t)
		# По два отряда каждого типа и по 20 бойцов — самые длинные подписи
		for k in range(2):
			var sq := _make_squad(uid, 20, Vector3(-600.0 - float(k) * 20.0, 0.0, z))
			made.append(sq)
			all.append_array(sq["units"])
		z -= 20.0
	await frames(3)
	sm._clear_selection()
	for sq in made:
		sm._select((sq as Dictionary)["units"][0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)

	var panel = hud._overbar_row
	verdict("14a четыре типа — панель есть", panel != null)
	if panel == null:
		_cleanup(all)
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var slots := _filter_slots()
	var caps: Array = []
	for s in slots:
		for c in s.get_children():
			if c is Label:
				caps.append((c as Label).text)
	print("  панель: позиция=%s размер=%s, экран=%s" % [
		str(panel.global_position), str(panel.size), str(vp)])
	print("  ячеек=%d, подписи=%s" % [slots.size(), str(caps)])
	verdict("14b ячейка на каждый из четырёх типов", slots.size() == 4,
		"нашли %d" % slots.size())
	verdict("14c панель целиком на экране",
		panel.global_position.x >= 0.0
		and panel.global_position.x + panel.size.x <= vp.x
		and panel.global_position.y >= 0.0,
		"x=%.0f w=%.0f" % [panel.global_position.x, panel.size.x])
	verdict("14d панель не наезжает на нижнюю панель команд",
		panel.global_position.y + panel.size.y <= vp.y + float(hud.PANEL_TOP) + 1.0,
		"низ %.0f" % (panel.global_position.y + panel.size.y))
	# Подпись «40 бойцов» обязана влезать в ячейку, а не резаться многоточием
	var fits := true
	for s in slots:
		for c in s.get_children():
			if c is Label:
				var l: Label = c
				var need: float = l.get_theme_font("font").get_string_size(
					l.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
					l.get_theme_font_size("font_size")).x
				print("    подпись «%s»: нужно %.0f px, ячейка %d px" % [
					l.text, need, hud.FILTER_SLOT])
				if need > float(hud.FILTER_SLOT):
					fits = false
	verdict("14e подписи влезают в ячейку без обрезки", fits)

	_cleanup(all)
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
func _make_squad(unit_id: String, n: int, at: Vector3) -> Dictionary:
	return _make_squad_faction(unit_id, n, at, Constants.FACTION_PLAYER)

func _make_squad_faction(unit_id: String, n: int, at: Vector3, f: int) -> Dictionary:
	var sid: int = GameManager.new_squad(f, unit_id)
	var units: Array = []
	for i in range(n):
		var u: Unit = _spawn(unit_id)
		u.faction = f
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

func _cleanup(units: Array) -> void:
	var sm = main.selection_manager
	sm.selected_units = []
	GameManager.on_selection_changed([])
	for u in units:
		if is_instance_valid(u):
			u.queue_free()
