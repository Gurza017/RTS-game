extends Node

## СТЕНД: ВИЗУАЛЬНЫЕ СОСТОЯНИЯ УЗЛОВ ДРЕВА КУЗНИЦЫ
##
## Разделы:
##   A — исходное состояние: доступные узлы естественного цвета и рабочие
##   B — после покупки: приглушение, галочка, повторно не покупается
##   C — соседние узлы покупкой не задеты
##   D — идущее исследование и закрытые зависимости
##   E — статус переживает пересборку панели (сохраняется, а не рисуется разово)
##
## ЧИСЛА И СПИСКИ БЕРУТСЯ ИЗ КОНФИГА: узлы, цены и зависимости правит владелец,
## стенд обязан следовать за forge_config.gd, а не за зашитыми значениями.
##
## ── ЧТО ИЗМЕНИЛОСЬ 2026-08-07 ───────────────────────────────────────────────
## Кузница переехала из общей нижней панели в свою (древо технологий 5×4), и
## слоты в ней теперь не плоский UPGRADE_SLOTS, а узлы forge_config. СМЫСЛ всех
## проверок прежний — сменились источник списка (_slots) и место, где искать
## кнопку (_btn_of). Одно требование изменилось по сути и отмечено на месте:
## закрытый узел больше НЕ disabled (см. D3).

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

var main: Node = null
var hud = null
var smithy: Smithy = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

## Узлы ОТКРЫТОЙ вкладки — то, что панель показывает прямо сейчас
func _slots() -> Array:
	return _Forge.tree(hud._forge_unit)

## Кнопка узла. Панель держит прямой указатель id -> Button, гадать по подписи
## (как раньше по тултипу) больше не нужно
func _btn_of(upg_id: String) -> Button:
	var b = hud._forge_nodes.get(upg_id, null)
	return b as Button if b != null and is_instance_valid(b) else null

func _has_check(b: Button) -> bool:
	for c in b.get_children():
		if c is Label and c.name == "DoneCheck":
			return true
	return false

## Открыть панель кузницы заново (пересборка с нуля)
func _reopen() -> void:
	hud.show_selection([smithy])
	await frames(2)

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)
	hud = main.hud
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	smithy = Smithy.new()
	smithy.faction = Constants.FACTION_PLAYER
	main.world_add(smithy)
	smithy.global_position = Vector3(-400, 0, -400)
	await frames(3)

	await _test_initial()
	await _test_after_research()
	await _test_neighbours()
	await _test_busy_and_locked()
	await _test_persists()

	print("\n=== ИТОГ qa_upgrade: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit()

## Первый узел без предусловий — с него и начинаем (берём из конфига).
## Колонку D пропускаем: она открывается не стрелкой, а полным рядом
func _first_free_slot() -> String:
	for s in _slots():
		var d: Dictionary = s
		if (d.get("prerequisites", []) as Array).is_empty() \
				and (d.get("row_gate", []) as Array).is_empty():
			return String(d.get("id", ""))
	return ""

# ═════════════════════════════════════════════════════════════════════════════
# A. ИСХОДНОЕ СОСТОЯНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _test_initial() -> void:
	print("\n═════ A. ДО ПОКУПКИ ═════")
	await _reopen()
	var f := smithy.faction
	var checked := 0
	var natural := 0
	var clickable := 0
	for s in _slots():
		var uid: String = String((s as Dictionary).get("id", ""))
		if not GameManager.can_research(f, uid):
			continue                       # закрытые проверяем в разделе D
		var b := _btn_of(uid)
		if b == null:
			continue
		checked += 1
		if b.modulate.is_equal_approx(Color.WHITE):
			natural += 1
		if not b.disabled:
			clickable += 1
	print("  доступных узлов на панели: %d" % checked)
	verdict("A1 доступные узлы на панели есть", checked > 0,
		"нашли %d" % checked)
	verdict("A2 доступные кнопки естественного цвета (Color.WHITE)",
		natural == checked, "белых %d из %d" % [natural, checked])
	verdict("A3 доступные кнопки нажимаются", clickable == checked,
		"активных %d из %d" % [clickable, checked])
	verdict("A4 галочки «изучено» на них нет", not _any_check())

func _any_check() -> bool:
	for k in hud._forge_nodes.keys():
		var b := _btn_of(String(k))
		if b != null and _has_check(b):
			return true
	return false

# ═════════════════════════════════════════════════════════════════════════════
# B. ПОСЛЕ ПОКУПКИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_after_research() -> void:
	print("\n═════ B. ПОСЛЕ ИЗУЧЕНИЯ ═════")
	var uid := _first_free_slot()
	verdict("B1 в конфиге есть узел без предусловий", uid != "", uid)
	if uid == "":
		return
	var f := smithy.faction
	# Покупаем и мгновенно завершаем: время исследования берётся из конфига,
	# ждать его вживую стенду незачем
	GameManager.research_upgrade(f, uid)
	await frames(1)
	verdict("B2 улучшение числится изученным",
		GameManager.is_researched(f, uid))
	await _reopen()

	var b := _btn_of(uid)
	verdict("B3 кнопка изученного узла на панели найдена", b != null)
	if b == null:
		return
	print("  modulate=%s disabled=%s tooltip=«%s»" % [
		str(b.modulate), str(b.disabled), b.tooltip_text])
	# ЗАКАЗ ВЛАДЕЛЬЦА: изученное больше НЕ темнеет. Приглушение светлое, а
	# признаком «куплено» служит яркая зелёная галочка поверх иконки
	verdict("B4 приглушение СВЕТЛОЕ, кнопка не превращается в тёмную плашку",
		b.modulate.r >= 0.75 and b.modulate.g >= 0.75 and b.modulate.b >= 0.75,
		"modulate=%s" % str(b.modulate))
	verdict("B5 но картинка осталась различимой (не в ноль)",
		b.modulate.r > 0.25 and b.modulate.a > 0.5,
		"modulate=%s" % str(b.modulate))
	var check := b.get_node_or_null("DoneCheck")
	verdict("B5б поверх иконки стоит зелёная галочка",
		check != null and (check as Label).get_theme_color("font_color").g > 0.7,
		"галочка=%s" % str(check != null))
	# ЗАЩИТА ОТ ПОВТОРНОГО ЗАКАЗА — В ЛОГИКЕ, А НЕ В disabled (см. D3):
	# кнопка живая ради всплывающего окна, но исследование отбивается
	verdict("B6 повторно заказать нельзя", not smithy.research(uid),
		"research() вернул %s" % str(smithy.research(uid)))
	verdict("B7 тултип сообщает статус",
		HUD.UPG_TIP_DONE in b.tooltip_text, "«%s»" % b.tooltip_text)
	verdict("B8 тултип начинается с названия узла",
		b.tooltip_text.begins_with(_title_of(uid)), "«%s»" % b.tooltip_text)
	verdict("B9 поверх иконки стоит зелёная галочка", _has_check(b))

	# Клик по изученной кнопке ничего не ломает и не меняет
	var before: int = _researched_count(f)
	b.emit_signal("pressed")
	await frames(2)
	verdict("B10 сигнал по изученной кнопке ничего не покупает",
		_researched_count(f) == before,
		"изучено было %d, стало %d" % [before, _researched_count(f)])

func _title_of(uid: String) -> String:
	var d: Dictionary = _Forge.get_node(uid)
	return String(d.get("name", uid)) if not d.is_empty() else uid

func _researched_count(f: int) -> int:
	var n := 0
	for s in _slots():
		if GameManager.is_researched(f, String((s as Dictionary).get("id", ""))):
			n += 1
	return n

# ═════════════════════════════════════════════════════════════════════════════
# C. СОСЕДНИЕ КНОПКИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_neighbours() -> void:
	print("\n═════ C. СОСЕДИ НЕ ЗАДЕТЫ ═════")
	var f := smithy.faction
	await _reopen()
	var still_white := 0
	var still_live := 0
	var total := 0
	for s in _slots():
		var uid: String = String((s as Dictionary).get("id", ""))
		if GameManager.is_researched(f, uid) or not GameManager.can_research(f, uid):
			continue
		var b := _btn_of(uid)
		if b == null:
			continue
		total += 1
		if b.modulate.is_equal_approx(Color.WHITE):
			still_white += 1
		if not b.disabled:
			still_live += 1
	print("  ещё не купленных и доступных: %d" % total)
	verdict("C1 некупленные остались естественного цвета",
		total > 0 and still_white == total,
		"белых %d из %d" % [still_white, total])
	verdict("C2 и по-прежнему нажимаются", still_live == total,
		"активных %d из %d" % [still_live, total])

# ═════════════════════════════════════════════════════════════════════════════
# D. ИДЁТ ИССЛЕДОВАНИЕ И ЗАКРЫТЫЕ ЗАВИСИМОСТИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_busy_and_locked() -> void:
	print("\n═════ D. В РАБОТЕ И ЗАКРЫТЫЕ ═════")
	var f := smithy.faction
	# Узел с ненулевым временем исследования — чтобы застать состояние «идёт»
	var busy_id := ""
	for s in _slots():
		var d: Dictionary = s
		var uid: String = String(d.get("id", ""))
		if GameManager.can_research(f, uid) \
				and _UCfg.upgrade_research_time(d) > 0.0:
			busy_id = uid
			break
	if busy_id == "":
		print("  в конфиге нет доступного узла с временем исследования — пропуск")
	else:
		smithy.research(busy_id)
		await frames(1)
		await _reopen()
		var bb := _btn_of(busy_id)
		# КНОПКА ИДУЩЕГО ИССЛЕДОВАНИЯ ОСТАЁТСЯ ЖИВОЙ: по ней работает ПКМ-отмена
		# с возвратом ресурсов, а отключённая Button мышь не пропускает.
		# От повторного заказа защищает Smithy.research, а не disabled
		verdict("D1 идущее исследование нельзя заказать повторно",
			bb != null and not bb.disabled and not smithy.research(busy_id),
			"disabled=%s" % (str(bb.disabled) if bb else "кнопки нет"))
		verdict("D2 тултип сообщает, что исследование идёт",
			bb != null and HUD.UPG_TIP_BUSY in bb.tooltip_text,
			"«%s»" % (bb.tooltip_text if bb else ""))

	# Закрытая зависимость: узел, чьи prerequisites не выполнены
	var locked_id := ""
	for s2 in _slots():
		var d2: Dictionary = s2
		if (d2.get("row_gate", []) as Array).is_empty() \
				and not GameManager.research_blockers(f, d2).is_empty():
			locked_id = String(d2.get("id", ""))
			break
	if locked_id == "":
		print("  в конфиге нет узла с невыполненным предусловием — пропуск")
		return
	var lb := _btn_of(locked_id)
	# ЗАКРЫТЫЙ УЗЕЛ ЖИВОЙ, А НЕ disabled — И ЭТО НАМЕРЕННО (изменено 2026-08-07).
	# Отключённая Button не отдаёт mouse_entered, то есть по САМОМУ нужному узлу
	# («а почему сюда нельзя?») всплывающее окно с причиной не открылось бы
	# вовсе. Запрет держится там же, где и для изученного, — в Smithy.research
	verdict("D3 закрытый узел не исследуется по клику",
		lb != null and not smithy.research(locked_id),
		"research() вернул %s" % str(lb != null and smithy.research(locked_id)))
	verdict("D4 но цвет у него ЕСТЕСТВЕННЫЙ (он не куплен, а лишь закрыт)",
		lb != null and lb.modulate.is_equal_approx(Color.WHITE),
		"modulate=%s" % (str(lb.modulate) if lb else "-"))
	verdict("D5 тултип объясняет, чего не хватает",
		lb != null and HUD.UPG_TIP_LOCK in lb.tooltip_text,
		"«%s»" % (lb.tooltip_text if lb else ""))
	verdict("D6 закрытый узел остаётся живым ради всплывающего окна",
		lb != null and not lb.disabled,
		"disabled=%s" % (str(lb.disabled) if lb else "-"))

# ═════════════════════════════════════════════════════════════════════════════
# E. СОСТОЯНИЕ СОХРАНЯЕТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _test_persists() -> void:
	print("\n═════ E. СТАТУС ПЕРЕЖИВАЕТ ПЕРЕСБОРКУ ═════")
	var f := smithy.faction
	var uid := _first_free_slot()
	if uid == "" or not GameManager.is_researched(f, uid):
		verdict("E1 есть изученный узел для проверки", false, uid)
		return
	# Уходим с кузницы и возвращаемся: панель собирается заново с нуля
	hud.show_selection([])
	await frames(2)
	await _reopen()
	var b := _btn_of(uid)
	verdict("E1 после пересборки панели статус на месте",
		b != null and _has_check(b) and not smithy.research(uid),
		"галочка=%s" % (str(_has_check(b)) if b else "-"))
	verdict("E2 и приглушение тоже",
		b != null and not b.modulate.is_equal_approx(Color.WHITE),
		"modulate=%s" % (str(b.modulate) if b else "-"))
