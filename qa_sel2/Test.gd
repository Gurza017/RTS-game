extends Node

## СТЕНД: ПЕРЕСБОРКА ПАНЕЛИ ВЫДЕЛЕНИЯ (5 блоков заказчика)
##
##   A. Двухуровневое выделение отрядов
##      уровень 1 — только компактные групповые иконки (4 и 3), панели нет;
##      уровень 2 — клик по «3» даёт ровно 3 карточки лучников с HP и звёздами;
##      клик по карточке сужает выделение до одного отряда.
##   B. Нижняя панель и кнопки приказов уменьшены вдвое.
##   C. Пауза по Z и по иконке — вместе со звуком.
##   D. Руины: ПКМ рабочими ставит стройплощадку; иконка бездельников выделяет ВСЕХ.
##   E. Кузница: зелёная #32CD32 галочка в углу, без цифр на иконках,
##      ряд очереди исследований; звёзды — по центру масс и вдвое крупнее.
##
## Числа берём из конфига и из констант HUD, а не хардкодим: балансную таблицу
## правит владелец, и стенд обязан следовать за ней (см. CLAUDE.md).

const _UCfg    := preload("res://scripts/unit_stats_config.gd")
const _Forge   := preload("res://scripts/forge_config.gd")
const _VetStar := preload("res://scripts/VeterancyStar.gd")

## Как было ДО этой правки — только чтобы посчитать процент уменьшения
const PREV_PANEL_H  := 72.0
const PREV_BTN_SIZE := 44.0

var main: Node = null
var hud       = null
var sm        = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  %s %s%s" % ["ПРОШЛО" if ok else "ПРОВАЛ", title,
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(3)
	hud = main.hud
	sm  = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	_give(3000.0)
	await frames(2)

	await _test_group_levels()
	_test_scale()
	await _test_pause()
	await _test_ruins()
	await _test_idle()
	await _test_smithy()
	await _test_stars()

	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		if not bool((v as Array)[1]):
			bad += 1
	print("  провалов: %d из %d" % [bad, verdicts.size()])
	print("\n=== QA_SEL2 DONE ===")
	get_tree().quit()

func _give(amount: float) -> void:
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), amount)

## Отряд из n бойцов заданного типа в точке at. Возвращает [sid, members]
func _make_squad(kind: String, n: int, at: Vector3) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit
		match kind:
			"archer":   u = Archer.new()
			"spearman": u = Spearman.new()
			_:          u = Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = at + Vector3(float(i % 5) * 1.0, 0.0, float(i / 5) * 1.0)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

## Найти в поддереве первый узел, у которого имя начинается с prefix
func _find_prefixed(root: Node, prefix: String) -> Node:
	if root.name.begins_with(prefix):
		return root
	for c in root.get_children():
		var f := _find_prefixed(c, prefix)
		if f != null:
			return f
	return null

func _find_all_prefixed(root: Node, prefix: String, out: Array) -> void:
	if root.name.begins_with(prefix):
		out.append(root)
	for c in root.get_children():
		_find_all_prefixed(c, prefix, out)

## Первый Label в поддереве (звезда/бейдж живут внутри кнопки)
func _labels_in(root: Node, out: Array) -> void:
	if root is Label:
		out.append(root)
	for c in root.get_children():
		_labels_in(c, out)

# ═════════════════════════════════════════════════════════════════════════════
# A. ДВУХУРОВНЕВОЕ ВЫДЕЛЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _test_group_levels() -> void:
	print("\n═════ A. ДВА УРОВНЯ ВЫДЕЛЕНИЯ ═════")
	# 4 отряда копейщиков и 3 отряда лучников — ровно случай из задания
	var spear_sids: Array = []
	var archer_sids: Array = []
	var all_men: Array = []
	for i in range(4):
		var r: Array = _make_squad("spearman", 6, Vector3(-60.0 + float(i) * 9.0, 0.0, -40.0))
		spear_sids.append(int(r[0]))
		all_men += (r[1] as Array)
	# У лучников состав разный, чтобы «57 бойцов» была суммой, а не n×отряд
	for i in range(3):
		var cnt: int = 5 + i * 2          # 5 + 7 + 9 = 21
		var r2: Array = _make_squad("archer", cnt, Vector3(-60.0 + float(i) * 9.0, 0.0, -25.0))
		archer_sids.append(int(r2[0]))
		all_men += (r2[1] as Array)
	await frames(3)

	# Дадим одному отряду лучников звание — карточка обязана показать звезду
	var star_sid: int = int(archer_sids[1])
	GameManager.squads[star_sid]["level"] = 2
	GameManager.refresh_star(star_sid)

	sm._clear_selection()
	for u in all_men:
		sm._select_one(u)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)

	# ── A1: уровень 1 — панели нет, есть полоса с ДВУМЯ иконками
	var bar_visible: bool = hud._overbar != null and hud._overbar.visible
	var slots: int = hud.type_slots()
	var panel_hidden: bool = hud._bottom_panel == null or not hud._bottom_panel.visible
	verdict("A1 смешанное выделение: только компактная полоса, детальной панели нет",
		bar_visible and slots == 2 and panel_hidden,
		"полоса=%s слотов=%d панель_скрыта=%s" % [bar_visible, slots, panel_hidden])

	# ── A2: на иконках цифры 4 и 3 (число ОТРЯДОВ, не бойцов)
	var badges: Array = []
	for slot in hud._overbar_row.get_children():
		var lbls: Array = []
		_labels_in(slot, lbls)
		for l in lbls:
			var s: String = (l as Label).text
			if s.is_valid_int():
				badges.append(int(s))
				break
	verdict("A2 на групповых иконках стоят 4 и 3",
		badges.size() == 2 and badges[0] == 4 and badges[1] == 3,
		"цифры=%s" % str(badges))

	# ── A3: клик по группе лучников → ровно 3 карточки
	hud._on_type_filter_pressed("archer")
	await frames(2)
	var cards: Array = []
	_find_all_prefixed(hud._squad_strip, "SquadCard", cards)
	verdict("A3 клик по «3» разворачивает РОВНО 3 карточки лучников",
		cards.size() == 3 and hud._bottom_panel.visible,
		"карточек=%d панель=%s" % [cards.size(), hud._bottom_panel.visible])

	# ── A4: суммарная численность типа в подписи
	var archers_total := 0
	for s2 in archer_sids:
		archers_total += GameManager.squad_members(int(s2)).size()
	verdict("A4 подпись показывает суммарную численность типа",
		hud.info_label.text.contains("%d бойцов" % archers_total),
		"ожидали %d, текст: «%s»" % [archers_total, hud.info_label.text])

	# ── A5: у каждой карточки есть состав, шкала HP и (где есть звание) звезда
	var with_count := 0
	var with_bar := 0
	var with_star := 0
	for c in cards:
		var lbls: Array = []
		_labels_in(c, lbls)
		for l in lbls:
			var t: String = (l as Label).text
			if t.is_valid_int() and int(t) > 0:
				with_count += 1
			elif t.contains("★"):
				with_star += 1
		# Шкала — ColorRect ненулевой ширины внутри карточки
		for ch in c.get_children():
			if ch is PanelContainer:
				for f in (ch as Node).get_children():
					if f is ColorRect and (f as ColorRect).custom_minimum_size.x > 0.0:
						with_bar += 1
	verdict("A5 на каждой карточке — состав, шкала здоровья и звезда у ветеранов",
		with_count == 3 and with_bar == 3 and with_star == 1,
		"состав=%d шкал=%d звёзд=%d (звание есть у 1 отряда)" % [with_count, with_bar, with_star])

	# ── A6: клик по карточке сужает выделение до одного отряда
	var target_sid: int = -1
	for c in cards:
		var nm: String = String(c.name)
		var sid_txt: String = nm.substr("SquadCard".length())
		if sid_txt.is_valid_int() and int(sid_txt) == star_sid:
			target_sid = star_sid
			(c.get_child(0) as Button).emit_signal("pressed")
			break
	await frames(2)
	var only_one := true
	for u in sm.selected_units:
		if not is_instance_valid(u) or (u as Unit).squad_id != target_sid:
			only_one = false
	verdict("A6 клик по карточке отряда сужает выделение до него одного",
		target_sid == star_sid and only_one and sm.selected_units.size() \
			== GameManager.squad_members(star_sid).size(),
		"выделено=%d в отряде=%d" % [sm.selected_units.size(),
			GameManager.squad_members(star_sid).size()])

	# ── A7: один тип — обычная панель, полоса групп спрятана
	verdict("A7 один тип: детальная панель на месте, полоса групп скрыта",
		hud._bottom_panel.visible and not hud._overbar.visible,
		"панель=%s полоса=%s" % [hud._bottom_panel.visible, hud._overbar.visible])

	# ── A7б: ГЕОМЕТРИЯ. Ни полоса групп, ни развёрнутая панель не должны ни
	# вылезать за нижнюю кромку экрана, ни налезать друг на друга, ни обрезать
	# подписи многоточием (подпись «32 бойцов» в 34 px именно так и терялась)
	sm._clear_selection()
	for u in all_men:
		if is_instance_valid(u):
			sm._select_one(u)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	var bar_r: Rect2 = hud._overbar.get_global_rect()
	verdict("A7б полоса групп целиком на экране (уровень 1)",
		bar_r.end.y <= vp.y + 0.5 and bar_r.position.x >= 0.0,
		"низ полосы=%.0f при экране %.0f" % [bar_r.end.y, vp.y])
	# Подписи не обрезаны: ширина текста укладывается в ячейку
	var clipped := 0
	for slot in hud._overbar_row.get_children():
		var lbls: Array = []
		_labels_in(slot, lbls)
		for l in lbls:
			var lb := l as Label
			if not lb.text.contains("бойцов"):
				continue
			var f: Font = lb.get_theme_font("font")
			var fs: int = lb.get_theme_font_size("font_size")
			if f != null and f.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT,
					-1.0, fs).x > lb.size.x + 0.5:
				clipped += 1
	verdict("A7в подпись «N бойцов» помещается в ячейку и не режется многоточием",
		clipped == 0, "обрезано подписей: %d" % clipped)

	hud._on_type_filter_pressed("archer")
	await frames(2)
	var p_r: Rect2 = hud._bottom_panel.get_global_rect()
	bar_r = hud._overbar.get_global_rect()
	verdict("A7г развёрнутая панель на экране, полоса групп над ней без наложения",
		p_r.end.y <= vp.y + 0.5 and bar_r.end.y <= p_r.position.y + 0.5,
		"панель %.0f..%.0f, полоса кончается на %.0f, экран %.0f" % [
			p_r.position.y, p_r.end.y, bar_r.end.y, vp.y])
	hud._on_type_filter_pressed("archer")
	await frames(1)

	# ── A8: повторный клик по групповой иконке сворачивает обратно в уровень 1
	sm._clear_selection()
	for u in all_men:
		if is_instance_valid(u):
			sm._select_one(u)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	hud._on_type_filter_pressed("archer")
	await frames(1)
	var lvl2: bool = hud._bottom_panel.visible
	hud._on_type_filter_pressed("archer")
	await frames(1)
	verdict("A8 повторный клик по той же иконке возвращает уровень 1",
		lvl2 and not hud._bottom_panel.visible,
		"после 1-го клика панель=%s, после 2-го=%s" % [lvl2, hud._bottom_panel.visible])

	# Уборка: отряды больше не нужны, дальше стенд работает с чистой сценой
	for u in all_men:
		if is_instance_valid(u):
			u.queue_free()
	sm._clear_selection()
	GameManager.on_selection_changed([])
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. МАСШТАБ ПАНЕЛИ И КНОПОК
# ═════════════════════════════════════════════════════════════════════════════
func _test_scale() -> void:
	print("\n═════ B. ПАНЕЛЬ И КНОПКИ ВДВОЕ МЕНЬШЕ ═════")
	var panel_cut: float = 1.0 - float(HUD.PANEL_H) / PREV_PANEL_H
	var btn_cut: float   = 1.0 - float(HUD.BTN_SIZE) / PREV_BTN_SIZE
	verdict("B1 кнопка приказа уменьшена ровно вдвое",
		absf(btn_cut - 0.50) <= 0.02,
		"%.0f → %.0f (−%.0f%%)" % [PREV_BTN_SIZE, float(HUD.BTN_SIZE), btn_cut * 100.0])
	verdict("B2 минимальная высота панели уменьшена примерно вдвое",
		panel_cut >= 0.40,
		"%.0f → %.0f (−%.0f%%)" % [PREV_PANEL_H, float(HUD.PANEL_H), panel_cut * 100.0])

	# Реальная геометрия: панель Рабочего теперь НАРОЧНО крупнее общего минимума
	# (см. HUD.WORKER_PANEL_H_BOOST/_W_BOOST, владелец 2026-08-07 попросил
	# "выше в 2 раза" — иконки построек и портрет были нечитаемо мелкими). Не
	# вылезать за экран — всё ещё обязательно; сама высота ниже общего минимума
	# упасть уже не должна, раз буст взведён
	var w := Worker.new()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = Vector3(0.0, 0.0, 10.0)
	hud.show_selection([w])
	var r: Rect2 = hud._bottom_panel.get_global_rect()
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	verdict("B3 панель Рабочего укрупнена (буст взведён) и не вылезает за экран",
		hud._worker_boost and r.size.y > float(HUD.PANEL_H) and r.end.y <= vp.y + 0.5,
		"буст=%s, высота=%.0f (минимум %d), низ=%.0f при экране %.0f" % [
			hud._worker_boost, r.size.y, HUD.PANEL_H, r.end.y, vp.y])

	# Кнопки построек на панели рабочего — крупнее обычных приказных, по
	# BTN_SIZE * WORKER_ICON_BOOST (владелец: "иконки построек... на +50%")
	var expect_btn: float = float(HUD.BTN_SIZE) * HUD.WORKER_ICON_BOOST
	var btn_ok := true
	var btn_n := 0
	for b in hud.button_container.get_children():
		if b is Button:
			btn_n += 1
			if absf((b as Button).size.x - expect_btn) > 1.0:
				btn_ok = false
	verdict("B4 все кнопки приказов нарисованы в укрупненном (+50%) размере",
		btn_n > 0 and btn_ok, "кнопок=%d, ожидали по %.0f px" % [btn_n, expect_btn])
	w.queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# C. ПАУЗА (Z + иконка) ВМЕСТЕ СО ЗВУКОМ
# ═════════════════════════════════════════════════════════════════════════════
func _test_pause() -> void:
	print("\n═════ C. ПАУЗА ═════")
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.physical_keycode = KEY_Z
	ev.pressed = true
	hud._unhandled_input(ev)
	await frames(1)
	verdict("C1 Z ставит игру и звук на паузу",
		get_tree().paused and AudioManager.is_paused(),
		"игра=%s звук=%s" % [get_tree().paused, AudioManager.is_paused()])

	hud._unhandled_input(ev)
	await frames(1)
	verdict("C2 повторная Z снимает паузу и с игры, и со звука",
		not get_tree().paused and not AudioManager.is_paused(),
		"игра=%s звук=%s" % [get_tree().paused, AudioManager.is_paused()])

	hud._on_pause_btn_pressed()
	await frames(1)
	var by_icon: bool = get_tree().paused and AudioManager.is_paused()
	hud._on_pause_btn_pressed()
	await frames(1)
	verdict("C3 иконка ⏸ работает тем же путём, что и Z",
		by_icon and not get_tree().paused and not AudioManager.is_paused(),
		"по иконке пауза=%s, снятие=%s" % [by_icon, not get_tree().paused])

# ═════════════════════════════════════════════════════════════════════════════
# D. РУИНЫ
# ═════════════════════════════════════════════════════════════════════════════
func _test_ruins() -> void:
	print("\n═════ D. ВОССТАНОВЛЕНИЕ РУИН ═════")
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	var at := Vector3(30.0, 0.0, 30.0)
	b.global_position = at
	await frames(2)
	b.take_damage(b.max_health * 2.0, null)
	await frames(3)

	var ruin: Node = null
	for n in get_tree().get_nodes_in_group("ruins"):
		if (n as Node3D).global_position.distance_to(at) < 2.0:
			ruin = n
			break
	verdict("D1 на месте снесённой постройки появилась руина",
		ruin != null, "найдено руин: %d" % get_tree().get_nodes_in_group("ruins").size())
	if ruin == null:
		return

	# Руина НЕ здание: ни в группах построек, ни в маске левого клика
	var in_bld: bool = ruin.is_in_group("all_buildings") or ruin.is_in_group("player_buildings")
	var layer_ok: bool = (ruin as StaticBody3D).collision_layer == Constants.LAYER_RUINS
	verdict("D2 руина остаётся декорацией: своя маска, никаких групп зданий",
		not in_bld and layer_ok,
		"в группах зданий=%s слой=%d (ждали %d)" % [
			in_bld, (ruin as StaticBody3D).collision_layer, Constants.LAYER_RUINS])

	var w := Worker.new()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = at + Vector3(4.0, 0.0, 0.0)
	await frames(2)
	sm._clear_selection()
	sm._select_one(w)
	_give(2000.0)

	# ПРИКАЗ ОТДАЁТСЯ ЧЕРЕЗ НАСТОЯЩИЙ ПРАВЫЙ КЛИК, а не вызовом обработчика:
	# половина работы здесь — попадание луча по руине, а это зависит от маски
	# (LAYER_RUINS есть только в маске ПКМ) и от того, что _resolve_node узнаёт
	# руину по группе. Вызов _try_rebuild_ruin(ruin) напрямую всё это обошёл бы
	if main._camera != null:
		main._camera.jump_to(at, main._camera.max_height * 0.35)
	await frames(6)
	var cam: Camera3D = sm.camera
	var screen: Vector2 = cam.unproject_position(at + Vector3(0.0, 1.0, 0.0))
	var picked = sm._pick_at(screen,
		Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS | Constants.LAYER_RESOURCES \
		| Constants.LAYER_RUINS | Constants.LAYER_GROUND)["target"]
	verdict("D2б правый клик по руине наводится на неё лучом",
		picked == ruin, "под курсором: %s" % (
			String((picked as Node).name) if picked != null else "ничего"))
	sm._handle_right_click(screen)
	var handled: bool = true
	await frames(3)

	var site: Node = null
	for n in get_tree().get_nodes_in_group("construction_sites"):
		if (n as Node3D).global_position.distance_to(at) < 2.0:
			site = n
			break
	verdict("D3 ПКМ по руине сразу ставит стройплощадку на её месте",
		handled and site != null and not is_instance_valid(ruin),
		"приказ принят=%s площадка=%s руина жива=%s" % [
			handled, site != null, is_instance_valid(ruin)])
	verdict("D4 рабочий отправлен на эту стройку",
		site != null and w.build_target == site,
		"цель рабочего=%s" % ("та самая" if w.build_target == site else str(w.build_target)))
	if site != null:
		site.queue_free()
	w.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# D2. ПЛАШКА БЕЗДЕЛЬНИКОВ
# ═════════════════════════════════════════════════════════════════════════════
func _test_idle() -> void:
	print("\n═════ D. СВОБОДНЫЕ РАБОЧИЕ ═════")
	var idle: Array = []
	for i in range(4):
		var w := Worker.new()
		w.faction = Constants.FACTION_PLAYER
		main.world_add(w)
		w.global_position = Vector3(-20.0 + float(i) * 2.0, 0.0, 20.0)
		idle.append(w)
	await frames(3)
	var found: int = hud._idle_workers().size()
	sm._clear_selection()
	GameManager.on_selection_changed([])
	hud._select_idle_workers()
	await frames(2)
	verdict("D5 один клик по плашке выделяет ВСЕХ незанятых рабочих",
		found >= 4 and sm.selected_units.size() == found,
		"без дела=%d выделено=%d" % [found, sm.selected_units.size()])

	# Цифра сидит прямо в кнопке, без тёмной подложки под ней
	var lbl: Label = hud._idle_count_label
	var parent_is_btn: bool = lbl != null and lbl.get_parent() == hud._idle_btn
	var no_panel := true
	if hud._idle_btn != null:
		for c in hud._idle_btn.get_children():
			if c is PanelContainer:
				no_panel = false
	verdict("D6 под цифрой нет чёрного квадрата — Label с обводкой прямо в углу",
		parent_is_btn and no_panel \
			and lbl.get_theme_constant("outline_size") > 0,
		"родитель=кнопка:%s подложек=%s обводка=%d" % [
			parent_is_btn, not no_panel,
			lbl.get_theme_constant("outline_size") if lbl != null else -1])
	for w2 in idle:
		if is_instance_valid(w2):
			w2.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# E. КУЗНИЦА
# ═════════════════════════════════════════════════════════════════════════════
func _test_smithy() -> void:
	print("\n═════ E. КУЗНИЦА ═════")
	var s := Smithy.new()
	s.faction = Constants.FACTION_PLAYER
	main.world_add(s)
	s.global_position = Vector3(-40.0, 0.0, 40.0)
	await frames(3)
	_give(9000.0)

	# Закажем два улучшения: одно качается, второе ждёт в очереди.
	# Время исследования в конфиге может быть нулевым (отладка владельца) —
	# тогда заказ выполняется мгновенно; растягиваем его на месте.
	#
	# СЛОТЫ БЕРУТСЯ ИЗ ДРЕВА КУЗНИЦЫ, а не из старого плоского UPGRADE_SLOTS:
	# панель кузницы теперь показывает древо (см. E1/E2/E3 ниже), и старый слот
	# в ней не рисуется вовсе — искать его галочку было бы бессмысленно.
	# Открытую вкладку спрашиваем у самой панели, чтобы не гадать
	hud.show_selection([s])
	await frames(2)
	var ids: Array = []
	for node in _Forge.tree(hud._forge_unit):
		var d: Dictionary = node
		var nid: String = String(d.get("id", ""))
		if GameManager.can_research(Constants.FACTION_PLAYER, nid) \
				and _UCfg.upgrade_research_time(d) > 0.0:
			ids.append(nid)
		if ids.size() >= 2:
			break
	if ids.size() >= 1:
		s.research(String(ids[0]))
		s.research_time  = 60.0     # растянуть, чтобы очередь была наблюдаема
		s.research_timer = 0.0
	if ids.size() >= 2:
		s.research(String(ids[1]))
	hud.show_selection([s])
	await frames(2)

	# У КУЗНИЦЫ ТЕПЕРЬ СВОЯ ПАНЕЛЬ (древо технологий, 2026-08-07): и ряд очереди,
	# и кнопки улучшений переехали из общей нижней панели в неё. Требования к ним
	# те же самые — сменилось только место, поэтому проверки смотрят в
	# _forge_queue/_forge_grid вместо _queue_box/button_container
	var qn: int = hud._forge_queue.get_child_count()
	verdict("E1 в левом блоке — горизонтальный ряд иконок очереди исследований",
		qn == ids.size() and hud._forge_queue.columns == qn and qn > 0,
		"ячеек=%d колонок=%d (ожидали %d в один ряд)" % [
			qn, hud._forge_queue.columns, ids.size()])

	# ── На кнопках улучшений нет цифр очереди
	var badges: Array = []
	_find_all_prefixed(hud._forge_grid, "QueueBadge", badges)
	verdict("E2 с иконок улучшений убраны цифры мест в очереди",
		badges.is_empty(), "найдено цифр: %d" % badges.size())

	# ── Изученное улучшение: яркая зелёная галочка ВНУТРИ угла кнопки
	if not ids.is_empty():
		GameManager.finish_research(Constants.FACTION_PLAYER, String(ids[0]))
		s.research_id = ""
		hud.show_selection([s])
		await frames(2)
	var checks: Array = []
	_find_all_prefixed(hud._forge_grid, "DoneCheck", checks)
	var col_ok := false
	var inside := false
	if not checks.is_empty():
		var mark := checks[0] as Label
		var c: Color = mark.get_theme_color("font_color")
		col_ok = c.is_equal_approx(HUD.UPG_CHECK_COLOR)
		var btn := mark.get_parent() as Control
		# «Внутри угла»: прямоугольник галочки целиком в прямоугольнике кнопки
		inside = mark.position.x >= -0.5 and mark.position.y >= -0.5 \
			and mark.position.x + mark.size.x <= btn.size.x + 0.5 \
			and mark.position.y + mark.size.y <= btn.size.y + 0.5
	verdict("E3 у изученного — зелёная #32CD32 галочка внутри угла кнопки",
		not checks.is_empty() and col_ok and inside,
		"галочек=%d цвет=%s внутри=%s" % [checks.size(), col_ok, inside])

	# ── Изученное НЕ темнеет (прежнее требование владельца — не сломано)
	if not checks.is_empty():
		var btn2 := (checks[0] as Label).get_parent() as Button
		verdict("E4 изученная кнопка не превращается в тёмную плашку",
			btn2.modulate.r >= 0.8 and btn2.modulate.g >= 0.8,
			"modulate=%s" % str(btn2.modulate))
	s.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# E2. ЗВЁЗДЫ ВЕТЕРАНСТВА
# ═════════════════════════════════════════════════════════════════════════════
func _test_stars() -> void:
	print("\n═════ E. ЗВЁЗДЫ ВЕТЕРАНСТВА ═════")
	var r: Array = _make_squad("spearman", 5, Vector3(60.0, 0.0, 60.0))
	var sid: int = int(r[0])
	var men: Array = r[1]
	await frames(3)
	GameManager.squads[sid]["level"] = 1
	GameManager.refresh_star(sid)
	await frames(2)
	var star = GameManager.squads[sid]["star"]
	verdict("E5 звезда отряда создана и живёт в мире, а не на бойце",
		star != null and is_instance_valid(star) and not (star.get_parent() is Unit),
		"родитель=%s" % (star.get_parent().name if star != null else "нет"))
	if star == null:
		return

	# ── Центр масс: расставим бойцов заведомо несимметрично
	var pts: Array = [Vector3(60.0, 0.0, 60.0), Vector3(70.0, 0.0, 60.0),
		Vector3(60.0, 0.0, 74.0), Vector3(80.0, 0.0, 66.0), Vector3(64.0, 0.0, 62.0)]
	var acc := Vector3.ZERO
	for i in range(men.size()):
		var p: Vector3 = pts[i]
		(men[i] as Node3D).global_position = Vector3(
			p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		acc += (men[i] as Node3D).global_position
	var want: Vector3 = acc / float(men.size())
	# Обновление идёт раз в STAR_UPDATE_FRAMES кадров — дадим ему сработать
	await frames(GameManager.STAR_UPDATE_FRAMES * 2 + 2)
	var got: Vector3 = (star as Node3D).global_position
	var dxz: float = Vector2(got.x - want.x, got.z - want.z).length()
	verdict("E6 звезда стоит строго по центру масс выживших",
		dxz <= 0.05,
		"центр=(%.2f, %.2f) звезда=(%.2f, %.2f), расхождение %.3f м" % [
			want.x, want.z, got.x, got.z, dxz])

	# ── Гибель бойца сдвигает центр, а не «перевешивает» звезду на соседа
	var dead: Unit = men[3]
	var acc2 := Vector3.ZERO
	var alive_n := 0
	for m in men:
		if m == dead:
			continue
		acc2 += (m as Node3D).global_position
		alive_n += 1
	dead.take_damage(dead.max_health * 3.0, null)
	await frames(GameManager.STAR_UPDATE_FRAMES * 2 + 4)
	var want2: Vector3 = acc2 / float(alive_n)
	var got2: Vector3 = (star as Node3D).global_position
	var dxz2: float = Vector2(got2.x - want2.x, got2.z - want2.z).length()
	verdict("E7 после потери бойца центр масс пересчитан",
		dxz2 <= 0.05 and is_instance_valid(star),
		"новый центр=(%.2f, %.2f) звезда=(%.2f, %.2f), расхождение %.3f м" % [
			want2.x, want2.z, got2.x, got2.z, dxz2])

	# ── Размер вдвое и бронза на 1-3
	verdict("E8 звезда вдвое крупнее прежней",
		absf(_VetStar.STAR_RADIUS / 0.098 - 2.0) <= 0.02,
		"радиус %.3f м (было 0.098)" % _VetStar.STAR_RADIUS)
	var bronze_ok := true
	var grades: Array = []
	for lvl in [1, 2, 3]:
		var t: Dictionary = _UCfg.veteran_star_tier(lvl)
		grades.append("%d:%s×%d" % [lvl, String(t.get("tier", "?")), int(t.get("count", 0))])
		if String(t.get("tier", "")) != "bronze":
			bronze_ok = false
	verdict("E9 ранги 1-3 — бронзовые звёзды", bronze_ok, ", ".join(grades))

	for m in men:
		if is_instance_valid(m):
			m.queue_free()
	await frames(2)
