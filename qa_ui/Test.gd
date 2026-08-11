extends Node

## СТЕНД ПРОВЕРКИ ПАКЕТА UI/КОНФИГА
## Разделы пронумерованы так же, как пункты задания:
##   1 КОНФИГ  2 КНОПКИ  3 КАРТОЧКА  4 ВЁРСТКА ОЧЕРЕДИ
##   5 ПОСЛЕДОВАТЕЛЬНОСТЬ ОЧЕРЕДИ  6 ИССЛЕДОВАНИЯ  7 РЕГРЕССИИ

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")

var main: Node = null
var hud = null

func _ready() -> void:
	call_deferred("_run")

## Подождать n кадров (короткая запись вместо цикла в каждом тесте)
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _run() -> void:
	# Окно фиксируем: вёрстка и правый край экрана должны мериться при
	# заведомо известном размере, а не при том, что даст headless по умолчанию
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	await frames(2)
	hud = main.hud
	# Денег вдоволь обеим сторонам: проверяем интерфейс, а не экономику
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 100000.0)
		ResourceManager.add_resource(Constants.FACTION_ENEMY,  int(t), 100000.0)
	await frames(1)
	print("\n### РАЗМЕРЫ: окно=%s, видимая область=%s" % [
		str(get_tree().root.size), str(get_viewport().get_visible_rect().size)])

	_test_config()
	await _test_config_live()
	await _test_buttons_all_panels()
	await _test_cards()
	await _test_queue_layout()
	await _test_queue_order()
	await _test_research_timer()
	await _test_house()
	await _test_enemy_training()
	print("\n=== UI TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# 1. КОНФИГ
# ═════════════════════════════════════════════════════════════════════════════
func _test_config() -> void:
	print("\n═════ 1. КОНФИГ ПОСТРОЕК (unit_stats_config.BUILDINGS) ═════")
	print("  %-18s %8s %10s %14s %s" % ["id", "max_hp", "build_time", "цена", "рабочий строит"])
	for key in _UCfg.BUILDINGS:
		var bid: String = String(key)
		var cfg: Dictionary = _UCfg.BUILDINGS[bid]
		print("  %-18s %8.0f %10.1f %14s %s" % [
			bid,
			_UCfg.building_stat(bid, "max_hp", 0.0),
			_UCfg.building_stat(bid, "build_time", 0.0),
			str(_UCfg.building_cost(bid)),
			"да" if bool(cfg.get("worker_buildable", false)) else "нет"])
	print("  рабочий может строить: %s" % str(_UCfg.worker_buildable_ids()))

	print("\n───── СВЕРКА: ЖИВОЕ ЗДАНИЕ == КОНФИГ (max_hp) ─────")
	var pairs := [
		["castle",   Castle.new()],
		["barracks", Barracks.new()],
		["smithy",   Smithy.new()],
		["mine",     Mine.new()],
		["town_center", TownCenter.new()],
		["house",    load("res://scripts/House.gd").new()],
	]
	for p in pairs:
		var b: Building = p[1]
		b.faction = Constants.FACTION_PLAYER
		main.world_add(b)
		b.global_position = Vector3(200.0, 0.0, 200.0)
	var mismatch := 0
	for p in pairs:
		var bid: String = String(p[0])
		var b: Building = p[1]
		var want: float = _UCfg.building_stat(bid, "max_hp", -1.0)
		var ok: bool = absf(b.max_health - want) < 0.01
		if not ok:
			mismatch += 1
		print("  %-12s max_health=%6.0f  конфиг=%6.0f  %s  (%s)" % [
			bid, b.max_health, want, "OK" if ok else "РАСХОЖДЕНИЕ", b.display_name])
		b.queue_free()
	print("  расхождений max_hp: %d" % mismatch)

	print("\n───── ВРЕМЯ ИССЛЕДОВАНИЙ (UPGRADE_SLOTS.research_time) ─────")
	for slot in _UCfg.UPGRADE_SLOTS:
		var d: Dictionary = slot
		print("  %-10s %-28s %5.0f c   требует=%-8s цена=%s" % [
			String(d.get("id", "")), String(d.get("desc", "")),
			_UCfg.upgrade_research_time(d),
			String(d.get("requires", "—")) if String(d.get("requires", "")) != "" else "—",
			str(_UCfg.upgrade_cost(d))])
	print("  DEFAULT_RESEARCH_TIME = %.0f c" % _UCfg.DEFAULT_RESEARCH_TIME)

	print("\n───── НАЙМ (TRAINING): что реально попадает в очередь ─────")
	for bkey in _UCfg.TRAINING:
		var bid: String = String(bkey)
		var per: Dictionary = _UCfg.TRAINING[bid]
		for ukey in per:
			var uid: String = String(ukey)
			var c: Dictionary = per[uid]
			print("  %-11s %-9s время=%6.1f c  отряд=%2d  колонн=%d  цена=%s" % [
				bid, uid, float(c.get("time", 0.0)), int(c.get("squad", 1)),
				int(c.get("cols", 1)), str(_UCfg.train_cost(bid, uid))])

## Живые значения: то, чем реально играет игра (фундамент рабочего и готовое здание)
func _test_config_live() -> void:
	print("\n───── ЖИВЫЕ ЗНАЧЕНИЯ ЧЕРЕЗ GameManager.worker_buildings() ─────")
	var catalog: Dictionary = GameManager.worker_buildings()
	for key in catalog:
		var bid: String = String(key)
		var d: Dictionary = catalog[bid]
		var site: Building = _CSite.new()
		site.faction     = Constants.FACTION_PLAYER
		site.target_id   = bid
		site.target_name = String(d.get("name", bid))
		var t: float = d.get("time", 12.0)
		site.build_time  = t
		site.build_size  = d.get("size", Vector3(3.0, 2.0, 3.0))
		main.world_add(site)
		site.global_position = Vector3(210.0, 0.0, 210.0)
		var made: Building = site._make_target()
		var hp := -1.0
		if made != null:
			made.faction = Constants.FACTION_PLAYER
			main.world_add(made)
			hp = made.max_health
			made.queue_free()
		print("  %-10s фундамент build_time=%5.1f c (конфиг %5.1f)   готовое max_hp=%6.0f (конфиг %6.0f)  %s" % [
			bid, site.build_time, _UCfg.building_stat(bid, "build_time", -1.0),
			hp, _UCfg.building_stat(bid, "max_hp", -1.0),
			"OK" if (absf(site.build_time - _UCfg.building_stat(bid, "build_time", -1.0)) < 0.01
				and absf(hp - _UCfg.building_stat(bid, "max_hp", -1.0)) < 0.01) else "РАСХОЖДЕНИЕ"])
		site.queue_free()
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# 2. КНОПКИ: иконка на всю площадь, текста нет
# ═════════════════════════════════════════════════════════════════════════════
## Разбор ОДНОЙ панели: возвращает число нарушений
func _audit_panel(panel_name: String) -> int:
	var btns: Array = hud.button_container.get_children()
	print("  [%s] кнопок: %d" % [panel_name, btns.size()])
	var bad := 0
	for b in btns:
		var btn: Button = b
		var icon: TextureRect = null
		for c in btn.get_children():
			if c is TextureRect:
				icon = c
		if icon == null:
			print("    · БЕЗ ИКОНКИ: текст=«%s» (подпись оставлена намеренно)" % btn.text)
			continue
		var fills: bool = absf(icon.size.x - (btn.size.x - 6.0)) < 1.5 \
			and absf(icon.size.y - (btn.size.y - 6.0)) < 1.5
		var ok: bool = btn.text == "" \
			and icon.expand_mode == TextureRect.EXPAND_IGNORE_SIZE \
			and icon.stretch_mode == TextureRect.STRETCH_SCALE and fills
		if not ok:
			bad += 1
		print("    · %-16s текст=«%s» кнопка=%.0fx%.0f иконка=%.0fx%.0f expand=%d stretch=%d заполняет=%s → %s" % [
			icon.texture.resource_path.get_file(), btn.text,
			btn.size.x, btn.size.y, icon.size.x, icon.size.y,
			icon.expand_mode, icon.stretch_mode,
			"да" if fills else "НЕТ", "OK" if ok else "НАРУШЕНИЕ"])
	return bad

func _test_buttons_all_panels() -> void:
	print("\n═════ 2. КНОПКИ ВСЕХ ПАНЕЛЕЙ ═════")
	print("  эталон: expand=%d (EXPAND_IGNORE_SIZE), stretch=%d (STRETCH_SCALE), текст пустой" % [
		TextureRect.EXPAND_IGNORE_SIZE, TextureRect.STRETCH_SCALE])
	var total := 0

	# а) Пустое выделение — предложение построить Замок
	hud.show_selection([])
	await frames(3)
	total += _audit_panel("пустое выделение")

	# б) Замок
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-60.0, 0.0, -60.0)
	await frames(1)
	hud.show_selection([castle])
	await frames(3)
	total += _audit_panel("замок")

	# в) Бараки
	var barracks := Barracks.new()
	barracks.faction = Constants.FACTION_PLAYER
	main.world_add(barracks)
	barracks.global_position = Vector3(-52.0, 0.0, -60.0)
	await frames(1)
	hud.show_selection([barracks])
	await frames(3)
	total += _audit_panel("бараки")

	# г) Кузница
	var smithy := Smithy.new()
	smithy.faction = Constants.FACTION_PLAYER
	main.world_add(smithy)
	smithy.global_position = Vector3(-46.0, 0.0, -60.0)
	await frames(1)
	hud.show_selection([smithy])
	await frames(3)
	total += _audit_panel("кузница")

	# д) Артель рабочих
	var crew: Array = []
	var WorkerScene := load("res://scenes/units/Worker.tscn") as PackedScene
	for i in range(4):
		var w: Unit = WorkerScene.instantiate()
		w.faction = Constants.FACTION_PLAYER
		main.add_child(w)
		w.global_position = Vector3(-5.0 + float(i), 0.0, -5.0)
		crew.append(w)
	await frames(1)
	hud.show_selection(crew)
	await frames(3)
	print("  подпись артели: «%s»" % hud.info_label.text)
	total += _audit_panel("артель рабочих")

	# е) Стойки отряда: выделение должно совпадать с горячей группой Ctrl+1
	var squad: Array = []
	var SpearScene := load("res://scenes/units/Spearman.tscn") as PackedScene
	for i in range(3):
		var s: Unit = SpearScene.instantiate()
		s.faction = Constants.FACTION_PLAYER
		main.add_child(s)
		s.global_position = Vector3(10.0 + float(i), 0.0, 10.0)
		squad.append(s)
	await frames(1)
	var sm = main.selection_manager
	sm.selected_units = squad.duplicate()
	sm._groups[0] = squad.duplicate()
	print("  индекс горячей группы: %d (нужен >= 0)" % sm.current_group_index())
	hud.show_selection(squad)
	await frames(3)
	print("  подпись отряда: «%s»" % hud.info_label.text)
	total += _audit_panel("стойки отряда")

	print("  ВСЕГО НАРУШЕНИЙ ПО ВСЕМ ПАНЕЛЯМ: %d (норма 0)" % total)

	for w in crew:
		w.queue_free()
	for s in squad:
		s.queue_free()
	sm.selected_units = []
	sm._groups[0] = []
	castle.queue_free()
	barracks.queue_free()
	smithy.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 3. КАРТОЧКА ПРИ НАВЕДЕНИИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_cards() -> void:
	print("\n═════ 3. КАРТОЧКА ПРИ НАВЕДЕНИИ ═════")
	var barracks := Barracks.new()
	barracks.faction = Constants.FACTION_PLAYER
	main.world_add(barracks)
	barracks.global_position = Vector3(-40.0, 0.0, -40.0)
	await frames(1)
	hud.show_selection([barracks])
	await frames(3)

	var vp := get_viewport().get_visible_rect().size
	var panel_top: float = vp.y + float(hud.PANEL_TOP)
	print("  экран=%.0fx%.0f, верхняя кромка нижней панели y=%.0f" % [vp.x, vp.y, panel_top])

	var target: Button = hud.button_container.get_child(0)
	target.mouse_entered.emit()
	await frames(2)
	_report_card("кнопка «Копейщик» на панели бараков", panel_top, vp)
	target.mouse_exited.emit()
	await frames(1)
	print("  после mouse_exited карточка удалена: %s" % [
		"да" if (hud._stat_card == null) else "НЕТ"])

	# ── ПРАВЫЙ КРАЙ ЭКРАНА ───────────────────────────────────────────────────
	# Кнопка-пустышка ставится у самой правой кромки: карточка обязана
	# прижаться к краю, а не уехать за экран
	print("\n  ── карточка у ПРАВОГО КРАЯ ──")
	var probe := Button.new()
	probe.size = Vector2(hud.BTN_SIZE, hud.BTN_SIZE)
	hud.add_child(probe)
	probe.global_position = Vector2(vp.x - float(hud.BTN_SIZE) - 4.0, panel_top - 100.0)
	await frames(1)
	print("  кнопка-пустышка: x=%.0f..%.0f (правый край экрана %.0f)" % [
		probe.global_position.x, probe.global_position.x + probe.size.x, vp.x])
	hud._show_card(probe, hud._building_card("barracks"))
	await frames(2)
	_report_card("кнопка у правого края", panel_top, vp)
	hud._hide_card()
	probe.queue_free()

	# ── ЛЕВЫЙ КРАЙ (проверка нижней границы clamp) ────────────────────────────
	print("\n  ── карточка у ЛЕВОГО КРАЯ ──")
	var probe2 := Button.new()
	probe2.size = Vector2(hud.BTN_SIZE, hud.BTN_SIZE)
	hud.add_child(probe2)
	probe2.global_position = Vector2(0.0, panel_top - 100.0)
	await frames(1)
	hud._show_card(probe2, hud._building_card("house"))
	await frames(2)
	_report_card("кнопка у левого края", panel_top, vp)
	hud._hide_card()
	probe2.queue_free()

	barracks.queue_free()
	await frames(1)

func _report_card(what: String, panel_top: float, vp: Vector2) -> void:
	var card = hud._stat_card
	if card == null or not is_instance_valid(card):
		print("  ПРОВАЛ (%s): карточка не появилась" % what)
		return
	var found := {"icon": 0, "bar": 0, "labels": 0}
	_scan_card(card, found)
	var l: float = card.global_position.x
	var r: float = card.global_position.x + card.size.x
	var t: float = card.global_position.y
	var bt: float = card.global_position.y + card.size.y
	print("  %s: размер=%.0fx%.0f, прямоугольник x=[%.0f..%.0f] y=[%.0f..%.0f]" % [
		what, card.size.x, card.size.y, l, r, t, bt])
	print("    внутри: иконок=%d, шкал HP=%d, строк текста=%d" % [
		int(found["icon"]), int(found["bar"]), int(found["labels"])])
	print("    за левый край не ушла: %s | за правый край не ушла: %s | не перекрывает панель: %s" % [
		"да" if l >= 0.0 else "НЕТ",
		"да" if r <= vp.x else "НЕТ (на %.0f px)" % (r - vp.x),
		"да" if bt <= panel_top else "НЕТ (на %.0f px)" % (bt - panel_top)])
	for line in _card_lines(card):
		print("     | %s" % line)

func _scan_card(node: Node, acc: Dictionary) -> void:
	for c in node.get_children():
		if c is TextureRect:
			acc["icon"] = int(acc["icon"]) + 1
		elif c is Range:
			acc["bar"] = int(acc["bar"]) + 1
		elif c is Label:
			acc["labels"] = int(acc["labels"]) + 1
		_scan_card(c, acc)

func _card_lines(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append((c as Label).text)
		out.append_array(_card_lines(c))
	return out

# ═════════════════════════════════════════════════════════════════════════════
# 4. ВЁРСТКА ОЧЕРЕДИ: сдвиг должен быть 0.00 px
# ═════════════════════════════════════════════════════════════════════════════
var _base_btn: Vector2
var _base_info: Vector2
var _base_queue: Vector2
var _drift_max: float = 0.0

func _snapshot_layout() -> void:
	_base_btn   = hud.button_container.global_position
	_base_info  = hud.info_label.get_parent().size
	_base_queue = hud._queue_box.global_position
	_drift_max  = 0.0
	print("  исходно: кнопки=(%.1f, %.1f), колонка инфо=%.0fx%.0f, очередь=(%.1f, %.1f), ширина очереди=%.0f" % [
		_base_btn.x, _base_btn.y, _base_info.x, _base_info.y,
		_base_queue.x, _base_queue.y, hud._queue_box.size.x])

func _measure(tag: String, bld: Building) -> void:
	var d_btn: float   = (hud.button_container.global_position - _base_btn).length()
	var d_queue: float = (hud._queue_box.global_position - _base_queue).length()
	var d_info: float  = (hud.info_label.get_parent().size - _base_info).length()
	_drift_max = maxf(_drift_max, maxf(d_btn, maxf(d_queue, d_info)))
	print("    %-26s очередь=%2d заказов, типов=%d, сдвиг кнопок=%.2f px, сдвиг очереди=%.2f px, изм. инфо=%.2f px, ширина очереди=%.0f" % [
		tag, bld.production_queue.size(), hud._queue_box.get_child_count(),
		d_btn, d_queue, d_info, hud._queue_box.size.x])

func _test_queue_layout() -> void:
	print("\n═════ 4. ВЁРСТКА ПАНЕЛИ ПРИ РОСТЕ ОЧЕРЕДИ ═════")
	# ── 4а. Бараки: копейщики + лучники ──────────────────────────────────────
	print("\n  ── 4а. БАРАКИ: 5 копейщиков + 3 лучника ──")
	var barracks := Barracks.new()
	barracks.faction = Constants.FACTION_PLAYER
	main.world_add(barracks)
	barracks.global_position = Vector3(-30.0, 0.0, -30.0)
	await frames(1)
	hud.show_selection([barracks])
	await frames(4)
	_snapshot_layout()
	var spear_btn: Button = hud.button_container.get_child(0)
	var arch_btn: Button  = hud.button_container.get_child(1)
	for step in range(5):
		spear_btn.pressed.emit()
		await frames(3)
		_measure("копейщик #%d" % (step + 1), barracks)
	for step in range(3):
		arch_btn.pressed.emit()
		await frames(3)
		_measure("лучник #%d" % (step + 1), barracks)
	print("  МАКСИМАЛЬНЫЙ СДВИГ (бараки): %.2f px (норма 0.00)" % _drift_max)
	_dump_queue_cells()
	barracks.queue_free()
	await frames(2)

	# ── 4б. Замок: 4 РАЗНЫХ типа, очередь 11 заказов ─────────────────────────
	print("\n  ── 4б. ЗАМОК: 4 разных типа юнитов, очередь 11+ ──")
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-64.0, 0.0, -30.0)
	await frames(1)
	hud.show_selection([castle])
	await frames(4)
	_snapshot_layout()
	var worker_btn: Button  = hud.button_container.get_child(0)
	var warrior_btn: Button = hud.button_container.get_child(1)
	for step in range(5):
		worker_btn.pressed.emit()
		await frames(2)
		_measure("рабочий #%d" % (step + 1), castle)
	for step in range(2):
		warrior_btn.pressed.emit()
		await frames(2)
		_measure("мечник #%d" % (step + 1), castle)
	# Копейщики и лучники в замке кнопок не имеют (они для ИИ) — заказываем
	# напрямую, чтобы в очереди оказалось 4 РАЗНЫХ типа сразу
	for step in range(2):
		castle.train_from_config("spearman")
		await frames(2)
		_measure("копейщик(прямо) #%d" % (step + 1), castle)
	for step in range(2):
		castle.train_from_config("archer")
		await frames(2)
		_measure("лучник(прямо) #%d" % (step + 1), castle)
	print("  МАКСИМАЛЬНЫЙ СДВИГ (замок, 4 типа, %d заказов): %.2f px (норма 0.00)" % [
		castle.production_queue.size(), _drift_max])
	print("  колонка инфо: было %.0fx%.0f, стало %.0fx%.0f" % [
		_base_info.x, _base_info.y,
		hud.info_label.get_parent().size.x, hud.info_label.get_parent().size.y])
	print("  колонка очереди: QUEUE_W=%d, фактическая ширина=%.0f, ячеек=%d" % [
		hud.QUEUE_W, hud._queue_box.size.x, hud._queue_box.get_child_count()])
	_dump_queue_cells()
	castle.queue_free()
	await frames(2)

func _dump_queue_cells() -> void:
	print("  ЯЧЕЙКИ ОЧЕРЕДИ (подпись состава = «%s»):" % hud._queue_sig)
	var bars := 0
	for slot in hud._queue_box.get_children():
		var has_bar := false
		var text := ""
		var icon := ""
		for ch in slot.get_children():
			if ch is ProgressBar:
				has_bar = true
			elif ch is Label:
				text = (ch as Label).text
			elif ch is PanelContainer:
				for g in ch.get_children():
					# Сводная ячейка «остальное»: вместо иконки счётчик «+N»
					if g is Label:
						icon = "счётчик %s" % (g as Label).text
					for t in g.get_children():
						if t is TextureRect:
							icon = (t as TextureRect).texture.resource_path.get_file()
		if has_bar:
			bars += 1
		print("    иконка=%-12s шкала=%-4s подпись=«%s»" % [
			icon, "есть" if has_bar else "нет", text])
	print("    шкал прогресса всего: %d (норма 1 — только у активного типа)" % bars)

# ═════════════════════════════════════════════════════════════════════════════
# 5. ОЧЕРЕДЬ ПОСЛЕДОВАТЕЛЬНА: активный выходит — следующий становится активным
# ═════════════════════════════════════════════════════════════════════════════
func _test_queue_order() -> void:
	print("\n═════ 5. ПОСЛЕДОВАТЕЛЬНОСТЬ ОЧЕРЕДИ ═════")
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(-70.0, 0.0, -20.0)
	await frames(1)
	hud.show_selection([b])
	await frames(3)

	var t_arch: float = _UCfg.train_cfg("barracks", "archer").get("time", 0.0)
	var n_arch: int   = int(_UCfg.train_cfg("barracks", "archer").get("squad", 1))
	b.train_from_config("archer")
	b.train_from_config("archer")
	b.train_from_config("spearman")
	await frames(3)
	print("  заказано: лучник ×2 + копейщик ×1 (время лучника по конфигу %.1f c, отряд %d)" % [
		t_arch, n_arch])
	_dump_queue_cells()

	var before: int = get_tree().get_nodes_in_group("player_units").size()
	# Досрочно доводим АКТИВНЫЙ заказ до готовности: ждать 10 секунд незачем
	b._production_timer = t_arch - 0.001
	await frames(40)
	var after: int = get_tree().get_nodes_in_group("player_units").size()
	print("  первый отряд вышел: юнитов игрока было %d, стало %d (+%d, ожидалось +%d)" % [
		before, after, after - before, n_arch])
	print("  очередь: %d заказов" % b.production_queue.size())
	_dump_queue_cells()

	# Ещё один выход: теперь активным должен стать КОПЕЙЩИК
	b._production_timer = t_arch - 0.001
	await frames(40)
	print("  второй отряд вышел, очередь: %d заказов, активный тип по signature=«%s»" % [
		b.production_queue.size(), hud._queue_sig])
	_dump_queue_cells()
	b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 6. ИССЛЕДОВАНИЯ ПО ТАЙМЕРУ
# ═════════════════════════════════════════════════════════════════════════════
func _test_research_timer() -> void:
	print("\n═════ 6. ТАЙМЕР ИССЛЕДОВАНИЙ В КУЗНИЦЕ ═════")
	var smithy := Smithy.new()
	smithy.faction = Constants.FACTION_PLAYER
	main.world_add(smithy)
	smithy.global_position = Vector3(-20.0, 0.0, -20.0)
	await frames(1)
	hud.show_selection([smithy])
	await frames(2)

	var slot: Dictionary = _UCfg.get_upgrade_slot("spears")
	var want: float = _UCfg.upgrade_research_time(slot)
	var before_atk: float = GameManager.unit_bonus(Constants.FACTION_PLAYER, "spearman", "bonus_attack")
	var gold0: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD)
	var wood0: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD)
	var started: bool = smithy.research("spears")
	var gold1: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD)
	var wood1: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD)
	print("  заказ «Копья» принят: %s, research_time по конфигу=%.0f c, у здания research_time=%.0f c" % [
		str(started), want, smithy.research_time])
	print("  РЕСУРСЫ СПИСАНЫ СРАЗУ: золото %.0f→%.0f (-%.0f, цена %.0f), дерево %.0f→%.0f (-%.0f, цена %.0f)" % [
		gold0, gold1, gold0 - gold1, float(slot.get("cost_gold", 0.0)),
		wood0, wood1, wood0 - wood1, float(slot.get("cost_wood", 0.0))])
	print("  сразу после заказа: исследуется=%s, изучено=%s, бонус_атаки=%.1f (должен быть %.1f)" % [
		str(GameManager.is_researching(Constants.FACTION_PLAYER, "spears")),
		str(GameManager.is_researched(Constants.FACTION_PLAYER, "spears")),
		GameManager.unit_bonus(Constants.FACTION_PLAYER, "spearman", "bonus_attack"), before_atk])
	var gold_mid: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD)
	var second: bool = smithy.research("shields")
	print("  ВТОРОЙ заказ во время работы: research()=%s → отклонён=%s, ресурсы не тронуты=%s" % [
		str(second), str(not second),
		str(absf(ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD) - gold_mid) < 0.01)])

	smithy.research_timer = want * 0.5
	await frames(2)
	print("  на половине: прогресс=%.2f, шкала видна=%s, подпись HUD = «%s»" % [
		smithy.research_progress(), str(hud.progress_bar.visible), hud.progress_label.text])
	smithy.research_timer = want - 0.001
	await frames(20)
	print("  по готовности: исследуется=%s, изучено=%s, бонус_атаки=%.1f (было %.1f)" % [
		str(GameManager.is_researching(Constants.FACTION_PLAYER, "spears")),
		str(GameManager.is_researched(Constants.FACTION_PLAYER, "spears")),
		GameManager.unit_bonus(Constants.FACTION_PLAYER, "spearman", "bonus_attack"), before_atk])

	# ── ЦЕПОЧКА requires: «Броня» открывается только после «Щитов» ───────────
	print("\n  ── ЦЕПОЧКА ЗАВИСИМОСТЕЙ: shields → armor ──")
	print("  до заказа: armor доступен=%s (requires=%s, изучен=%s)" % [
		str(GameManager.can_research(Constants.FACTION_PLAYER, "armor")),
		String(_UCfg.get_upgrade_slot("armor").get("requires", "")),
		str(GameManager.is_researched(Constants.FACTION_PLAYER, "shields"))])
	var sh_time: float = _UCfg.upgrade_research_time(_UCfg.get_upgrade_slot("shields"))
	var sh_ok: bool = smithy.research("shields")
	await frames(2)
	print("  заказ «Щиты» принят=%s; пока идёт: armor доступен=%s (должен быть false)" % [
		str(sh_ok), str(GameManager.can_research(Constants.FACTION_PLAYER, "armor"))])
	smithy.research_timer = sh_time - 0.001
	await frames(20)
	print("  «Щиты» готовы: изучено=%s, armor теперь доступен=%s (должен быть true)" % [
		str(GameManager.is_researched(Constants.FACTION_PLAYER, "shields")),
		str(GameManager.can_research(Constants.FACTION_PLAYER, "armor"))])

	# Меню кузницы перерисовано: статусы слотов
	hud.show_selection([smithy])
	await frames(3)
	var ubtns: Array = hud.button_container.get_children()
	print("  кнопок апгрейдов: %d" % ubtns.size())
	for i in range(ubtns.size()):
		var btn: Button = ubtns[i]
		var d: Dictionary = _UCfg.UPGRADE_SLOTS[i]
		var uid: String = String(d.get("id", ""))
		var status := "доступен"
		if GameManager.is_researched(Constants.FACTION_PLAYER, uid):
			status = "ИЗУЧЕН"
		elif GameManager.is_researching(Constants.FACTION_PLAYER, uid):
			status = "исследуется"
		elif not GameManager.can_research(Constants.FACTION_PLAYER, uid):
			status = "закрыт (requires %s)" % String(d.get("requires", "?"))
		print("    %-10s подпись=«%s» %s" % [uid, btn.text, status])
	var armor_btn: Button = ubtns[3]
	armor_btn.mouse_entered.emit()
	await frames(2)
	if hud._stat_card != null:
		print("  карточка «Броня»:")
		for line in _card_lines(hud._stat_card):
			print("     | %s" % line)
	armor_btn.mouse_exited.emit()
	await frames(1)
	smithy.queue_free()
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# ДОМ
# ═════════════════════════════════════════════════════════════════════════════
func _test_house() -> void:
	print("\n───── НОВАЯ ПОСТРОЙКА «ДОМ» ─────")
	var catalog: Dictionary = GameManager.worker_buildings()
	print("  каталог рабочего: %s" % str(catalog.keys()))
	var site: Building = _CSite.new()
	site.faction     = Constants.FACTION_PLAYER
	site.target_id   = "house"
	site.target_name = "Дом"
	site.build_time  = _UCfg.building_stat("house", "build_time", 8.0)
	site.build_size  = _UCfg.building_size("house")
	main.world_add(site)
	site.global_position = Vector3(-10.0, 0.0, -10.0)
	await frames(1)
	var made: Building = site._make_target()
	if made == null:
		print("  ПРОВАЛ: стройка дома не создаёт здание")
	else:
		made.faction = Constants.FACTION_PLAYER
		main.world_add(made)
		await frames(1)
		print("  дом построен: %s, HP=%.0f, еда +%d каждые %d c" % [
			made.display_name, made.max_health,
			int(_UCfg.HOUSE_FOOD_INCOME), int(_UCfg.HOUSE_FOOD_INTERVAL)])
		var food0: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD)
		made._food_timer = _UCfg.HOUSE_FOOD_INTERVAL - 0.01
		await frames(5)
		var food1: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD)
		print("  еда: было %.0f, стало %.0f (прирост %.0f)" % [food0, food1, food1 - food0])
		made.queue_free()
	site.queue_free()
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# 7. РЕГРЕССИЯ: ИИ ПРОТИВНИКА ВСЁ ЕЩЁ НАНИМАЕТ ВОЙСКА
# ИИ зовёт enemy_castle.train_spearman()/train_archer(), а те теперь идут
# через TRAINING["castle"] → train_from_config().
# ═════════════════════════════════════════════════════════════════════════════
func _test_enemy_training() -> void:
	print("\n═════ 7. НАЙМ У ИИ ПРОТИВНИКА ═════")
	var enemy_castle: Castle = null
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is Castle:
			enemy_castle = b as Castle
			break
	if enemy_castle == null:
		print("  ПРОВАЛ: у врага нет замка (start_game не поставил базу)")
		return
	print("  замок врага найден: %s, building_id=«%s», HP=%.0f" % [
		enemy_castle.display_name, enemy_castle.building_id, enemy_castle.max_health])

	var before: int = get_tree().get_nodes_in_group("enemy_units").size()
	var c_sp: Dictionary = _UCfg.train_cfg("castle", "spearman")
	var ok_sp: bool = enemy_castle.train_spearman()
	var ok_ar: bool = enemy_castle.train_archer()
	var ok_wk: bool = enemy_castle.train_worker()
	print("  train_spearman()=%s, train_archer()=%s, train_worker()=%s; в очереди %d заказов" % [
		str(ok_sp), str(ok_ar), str(ok_wk), enemy_castle.production_queue.size()])
	print("  первый заказ: тип=%s, время=%.1f c, отряд=%d (конфиг TRAINING[castle][spearman]: %.1f c / %d)" % [
		String(enemy_castle.production_queue[0].get("name", "")),
		float(enemy_castle.production_queue[0].get("time", 0.0)),
		int(enemy_castle.production_queue[0].get("size", 0)),
		float(c_sp.get("time", 0.0)), int(c_sp.get("squad", 0))])

	enemy_castle._production_timer = float(c_sp.get("time", 20.0)) - 0.001
	await frames(60)
	var after: int = get_tree().get_nodes_in_group("enemy_units").size()
	var spearmen := 0
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if u is Spearman:
			spearmen += 1
	print("  юнитов врага было %d, стало %d (+%d); копейщиков врага на карте: %d" % [
		before, after, after - before, spearmen])
	print("  осталось в очереди: %d заказов" % enemy_castle.production_queue.size())
