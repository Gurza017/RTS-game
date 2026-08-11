extends Node

## СТЕНД: ДОВОДКА UI ПО 9 ПУНКТАМ ЗАКАЗЧИКА
##   1 баннера «N бойцов» над панелью больше нет
##   2 иконки зданий вписаны по пропорциям, а не растянуты
##   3 нижняя панель уменьшена ~на 40%, бейдж количества — в нижнем правом углу
##   4 панель ресурсов уже прежней, но выше; приток ГОРИТ ПОСТОЯННО
##   6 все 4 иконки ресурсов одного визуального размера
##   7 правая верхняя панель уменьшена ~на 30%, «Меню» без вложенной рамки
##   8 у правой панели нет пустого хвоста справа
##   9 у панели ресурсов скруглены все 4 угла, как у правой
##
## Пункт 5 (куча золота и свечение) — не про верстку, проверяется отдельно
## в _test_gold().
##
## Прогоняется на ДВУХ разрешениях: 1280x720 (ноутбук) и 3428x1386 (монитор
## заказчика, с которого сняты скриншоты).

const _RN := preload("res://scripts/ResourceNode.gd")

var main: Node = null
var hud       = null
var verdicts: Array = []
## Эталон «как было» — из истории правок, для процента уменьшения
const OLD_PANEL_H     := 120.0
const OLD_BTN_SIZE    := 72.0
const OLD_RES_CARD_W  := 24.0 + 44.0 + 38.0 + 8.0    # иконка+число+приток+зазоры
const OLD_TOP_RIGHT_W := 361.0

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
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 900.0)
	await frames(2)

	_test_constants()
	_test_gold()
	await _test_income()
	for res in [Vector2i(1280, 720), Vector2i(3428, 1386)]:
		await _test_layout(res)

	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		if not bool((v as Array)[1]):
			bad += 1
	print("  провалов: %d из %d" % [bad, verdicts.size()])
	print("\n=== QA_UI9 DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# КОНСТАНТЫ МАСШТАБА (пункты 3, 4, 7)
# ═════════════════════════════════════════════════════════════════════════════
func _test_constants() -> void:
	print("\n═════ МАСШТАБЫ ═════")
	# ПРОВЕРКА ПЕРЕПИСАНА ПОД ВТОРОЙ ПРОХОД МАСШТАБИРОВАНИЯ.
	# Тогда владелец просил −40% от исходных 120/72, теперь — ЕЩЁ ВДВОЕ от
	# полученных 72/44 (см. qa_sel2 B1/B2). Точное «−50% от предыдущего шага»
	# проверяет qa_sel2; здесь остаётся то, ради чего пункт 3 писался вообще:
	# панель и кнопки стали заметно меньше исходных
	var panel_cut: float = 1.0 - float(HUD.PANEL_H) / OLD_PANEL_H
	var btn_cut: float   = 1.0 - float(HUD.BTN_SIZE) / OLD_BTN_SIZE
	verdict("3 нижняя панель и кнопки радикально меньше исходных",
		panel_cut >= 0.40 and btn_cut >= 0.40,
		"панель −%.0f%%, кнопка приказа −%.0f%%" % [panel_cut * 100.0, btn_cut * 100.0])

	# ПОРОГ СНИЖЕН С 30% ДО 20% (владелец вернул счётчик рабочих на ресурсе —
	# "⛏N" рядом с притоком, см. HUD._res_workers_labels, — который прежде
	# был снят как раз ради этих 30%). Секция всё равно ощутимо уже исходной
	# 114px планки, просто не настолько агрессивно, как без этой колонки
	var card_cut: float = 1.0 - HUD.RES_CARD_SIZE.x / OLD_RES_CARD_W
	verdict("4 секция ресурса уже прежней не меньше чем на 20%",
		card_cut >= 0.20,
		"ширина секции %.0f → %.0f (−%.0f%%)" % [OLD_RES_CARD_W,
			HUD.RES_CARD_SIZE.x, card_cut * 100.0])
	verdict("4 при этом секция стала ВЫШЕ, а не ниже",
		HUD.RES_CARD_SIZE.y > 36.0,
		"высота %.0f (было 36)" % HUD.RES_CARD_SIZE.y)
	# Иконка ужимается заметно слабее панели: рисунок в ней обрезан по
	# содержимому, поэтому «чистых» 21 px читаются лучше прежних 24 с полями
	verdict("6 иконка ресурса ужата слабее самой панели",
		1.0 - HUD.RES_ICON_DISPLAY / 24.0 < card_cut,
		"иконка %.0f px (было 24)" % HUD.RES_ICON_DISPLAY)

# ═════════════════════════════════════════════════════════════════════════════
# ПУНКТ 5: КУЧА ЗОЛОТА И СВЕЧЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _test_gold() -> void:
	print("\n═════ 5. ЗОЛОТО ═════")
	# ПЕРЕЛИВ ВЕРНУЛИ (заказ владельца, 2026-08-07). Проверка ИНВЕРТИРОВАНА:
	# раньше здесь стояло «перелив выключен» — гало в *_Highlight.png оказалось
	# мифом (непрозрачная область блика попиксельно совпадает с базовым
	# спрайтом), а настоящей причиной грязного пятна была яркость: blend_add
	# СКЛАДЫВАЕТ блики соседних кусков, а кучи стоят внахлёст. Лечится не
	# выключением, а низким gain — его и сторожим ниже
	verdict("5 аддитивный перелив золота включён", _RN.GOLD_SHIMMER)

	# У каждой золотой жилы обязан быть узел блика, у камня — нет
	var shimmer := 0
	var gold_n := 0
	var stone_shimmer := 0
	var gold_pts: Array = []
	var stone_pts: Array = []
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null or not is_instance_valid(rn):
			continue
		var has_sh: bool = rn.find_child("GoldShimmer", true, false) != null
		if rn.resource_type == Constants.RESOURCE_GOLD:
			gold_n += 1
			if has_sh:
				shimmer += 1
			gold_pts.append(rn.global_position)
		else:
			if has_sh:
				stone_shimmer += 1
			if rn.resource_type == Constants.RESOURCE_STONE:
				stone_pts.append(rn.global_position)
	verdict("5 блик есть у золота и только у золота",
		gold_n > 0 and shimmer == gold_n and stone_shimmer == 0,
		"золота %d, с бликом %d, чужих бликов %d" % [gold_n, shimmer, stone_shimmer])

	# ЯРКОСТЬ — ЭТО И ЕСТЬ ЛЕКАРСТВО ОТ «ГРЯЗНОГО ПЯТНА». Сторожим не число, а
	# свойство: перекрытие трёх кусков не должно уходить за единицу
	var gain := 0.0
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null or rn.resource_type != Constants.RESOURCE_GOLD:
			continue
		var sh := rn.find_child("GoldShimmer", true, false) as MeshInstance3D
		if sh == null or sh.mesh == null:
			continue
		var m := (sh.mesh as QuadMesh).material as ShaderMaterial
		if m != null:
			gain = float(m.get_shader_parameter("gain"))
			break
	verdict("5 яркость блика не прогорает при наложении кусков",
		gain > 0.0 and gain * 3.0 <= 1.0,
		"gain=%.2f, тройное наложение даёт %.2f" % [gain, gain * 3.0])

	# ПЛОТНОСТЬ МЕРЯЕМ НА КОНТРОЛЬНЫХ КУЧАХ, а не на случайной карте: на карте
	# соседние жилы стоят близко, любая наивная кластеризация их сливает, и
	# «радиус кучи» скачет от прогона к прогону. Здесь мы сами ставим кучи
	# в заведомо пустом углу через тот же _spawn_resource_cluster и усредняем
	# по нескольким — разброс пресетов (CLUSTER_PRESETS) так не мешает
	var gr: float = _probe_cluster_radius(Constants.RESOURCE_GOLD)
	var sr: float = _probe_cluster_radius(Constants.RESOURCE_STONE)
	verdict("5 куча золота плотнее каменной",
		gr > 0.0 and sr > 0.0 and gr < sr,
		"золото R=%.2f м, камень R=%.2f м" % [gr, sr])

## Средний радиус куска контрольной кучи данного типа. Ставим SAMPLES куч
## далеко в стороне, каждую в своей точке, и считаем разброс кусков вокруг
## её центра
func _probe_cluster_radius(res_type: int, samples: int = 6) -> float:
	var sum := 0.0
	var cnt := 0
	for s in range(samples):
		var center := Vector3(-900.0 + float(s) * 40.0, 0.0,
			-900.0 if res_type == Constants.RESOURCE_GOLD else -820.0)
		var before: Array = get_tree().get_nodes_in_group("resource_nodes")
		main._spawn_resource_cluster(center, res_type, true)
		for n in get_tree().get_nodes_in_group("resource_nodes"):
			if n in before:
				continue
			var rn := n as ResourceNode
			if rn == null or not is_instance_valid(rn):
				continue
			var d := Vector2(rn.global_position.x - center.x,
				rn.global_position.z - center.z).length()
			sum += d
			cnt += 1
			rn.queue_free()
	return sum / float(cnt) if cnt > 0 else 0.0

## Средний радиус куска от центра своей кучи (кучи режем по разрыву 12 м)
func _mean_cluster_radius(pts: Array) -> float:
	if pts.size() < 3:
		return 0.0
	var used: Array = []
	for i in range(pts.size()):
		used.append(false)
	var sum := 0.0
	var cnt := 0
	for i in range(pts.size()):
		if used[i]:
			continue
		var group: Array = [pts[i]]
		used[i] = true
		# один проход «волной»: куски одной кучи ближе 12 м друг к другу
		var qi := 0
		while qi < group.size():
			var base: Vector3 = group[qi]
			for j in range(pts.size()):
				if used[j]:
					continue
				if base.distance_to(pts[j]) < 12.0:
					used[j] = true
					group.append(pts[j])
			qi += 1
		if group.size() < 3:
			continue
		var c := Vector3.ZERO
		for p in group:
			c += p
		c /= float(group.size())
		for p in group:
			sum += (p as Vector3).distance_to(c)
			cnt += 1
	return sum / float(cnt) if cnt > 0 else 0.0

# ═════════════════════════════════════════════════════════════════════════════
# ПУНКТ 4: ПРИТОК ГОРИТ ПОСТОЯННО
# ═════════════════════════════════════════════════════════════════════════════
func _test_income() -> void:
	print("\n═════ 4. ПРИТОК ═════")
	var f := Constants.FACTION_PLAYER
	# Счётчик добытого не должен реагировать на ТРАТЫ — только на добычу
	var before: float = ResourceManager.gathered_total(f, Constants.RESOURCE_WOOD)
	ResourceManager.spend(f, {Constants.RESOURCE_WOOD: 100.0})
	var after_spend: float = ResourceManager.gathered_total(f, Constants.RESOURCE_WOOD)
	ResourceManager.gather_resource(f, Constants.RESOURCE_WOOD, 40.0)
	var after_gather: float = ResourceManager.gathered_total(f, Constants.RESOURCE_WOOD)
	verdict("4 счётчик добытого не проседает от трат",
		absf(after_spend - before) < 0.01 and absf(after_gather - before - 40.0) < 0.01,
		"было %.0f, после траты %.0f, после сдачи %.0f" % [before, after_spend, after_gather])

	# ИМИТАЦИЯ РЕЙСОВ: рабочий сдаёт груз редкими порциями — раз в 5 секунд,
	# как реальная ходка. Прежняя реализация гасила подпись между сдачами —
	# именно это и называлось «мигает». Гоним 30 секунд модельного времени,
	# замеряем после того, как окно набрало INC_MIN_SAMPLE_SEC данных
	var lbl: Label = hud._res_income_labels.get(Constants.RESOURCE_WOOD)
	var seen_off := 0
	var seen_on := 0
	var warm: int = int(HUD.INC_MIN_SAMPLE_SEC / 0.1) + 20
	for step in range(300):
		if step % 50 == 0:
			ResourceManager.gather_resource(f, Constants.RESOURCE_WOOD, 12.0)
		hud._update_resource_income(0.1)
		if step > warm:
			if lbl != null and lbl.visible and lbl.text != "+0":
				seen_on += 1
			else:
				seen_off += 1
	verdict("4 приток горит между сдачами, а не мигает в такт им",
		seen_on > 0 and seen_off == 0,
		"кадров горит %d, погашен %d" % [seen_on, seen_off])

# ═════════════════════════════════════════════════════════════════════════════
# ВЁРСТКА НА КОНКРЕТНОМ РАЗРЕШЕНИИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_layout(res: Vector2i) -> void:
	print("\n═════ ВЁРСТКА %dx%d ═════" % [res.x, res.y])
	get_tree().root.size = res
	await frames(3)
	# Выделяем артель рабочих — тот же случай, что на скриншоте заказчика:
	# именно у неё в панели показываются кнопки построек
	var workers: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Worker and is_instance_valid(u):
			workers.append(u)
	while workers.size() < 5:
		var w := Worker.new()
		w.faction = Constants.FACTION_PLAYER
		main.world_add(w)
		w.global_position = Vector3(-430.0 + float(workers.size()), 0.0, -430.0)
		workers.append(w)
	await frames(2)
	hud.show_selection(workers)
	await frames(3)
	var vp: Vector2 = Vector2(res)
	var tag := "%dx%d" % [res.x, res.y]

	# ── 1. ПОЛОСА ГРУПП НЕ ДУБЛИРУЕТ ПАНЕЛЬ ──────────────────────────────────
	# Пункт 1 требовал убрать квадрат «иконка + N бойцов», который дублировал
	# портрет и счётчик нижней панели. Сам узел с тех пор вернулся — но уже как
	# УРОВЕНЬ 1 двухуровневого выделения (см. qa_sel2 A1): он появляется ТОЛЬКО
	# на смешанном выделении, где детальной панели нет вовсе, и потому ничего не
	# дублирует. Здесь выделение однотипное (артель рабочих), значит полоса
	# обязана быть скрыта и пуста — ровно то, на что жаловался владелец
	var overbar: Control = _find_deep(hud, "OverBar") as Control
	var bar_shown: bool = overbar != null and overbar.visible
	verdict("1 [%s] полоса групп не дублирует однотипное выделение" % tag,
		not bar_shown and hud.type_slots() == 0,
		"видна=%s, слотов=%d" % [str(bar_shown), hud.type_slots()])

	# ── 3. НИЖНЯЯ ПАНЕЛЬ ─────────────────────────────────────────────────────
	var bp: Control = hud._bottom_panel
	var br: Rect2 = bp.get_global_rect()
	print("    нижняя панель: %.0fx%.0f в точке (%.0f, %.0f)" % [
		br.size.x, br.size.y, br.position.x, br.position.y])
	# Порог поднят с 80 до 160: панель Артели рабочих теперь НАРОЧНО укрупнена
	# (HUD.WORKER_PANEL_H_BOOST = ×2, владелец 2026-08-07 — иконки построек и
	# портрет были нечитаемо мелкими). Точный множитель проверяет qa_sel2 B3;
	# здесь остаётся только санитарная проверка "не разрослась до абсурда"
	verdict("3 [%s] нижняя панель не выше 160 px" % tag, br.size.y <= 160.0,
		"высота %.0f" % br.size.y)
	verdict("3 [%s] нижняя панель занимает меньше половины ширины экрана" % tag,
		br.size.x < vp.x * 0.5, "%.0f из %.0f" % [br.size.x, vp.x])
	verdict("3 [%s] нижняя панель целиком в кадре" % tag,
		br.position.x >= -0.5 and br.end.y <= vp.y + 0.5 and br.end.x <= vp.x + 0.5,
		"rect=%s" % str(br))

	# Бейдж количества — в НИЖНЕМ ПРАВОМ углу портрета
	var badge: Label = hud._portrait_count_lbl
	var prect: Rect2 = (badge.get_parent() as Control).get_global_rect()
	var brect: Rect2 = badge.get_global_rect()
	var dx: float = prect.end.x - brect.end.x
	var dy: float = prect.end.y - brect.end.y
	verdict("3 [%s] бейдж количества прижат к нижнему правому углу" % tag,
		badge.visible and dx <= 6.0 and dy <= 6.0
		and brect.size.x < prect.size.x * 0.75,
		"отступ от угла (%.0f, %.0f), бейдж %.0fx%.0f в портрете %.0fx%.0f"
			% [dx, dy, brect.size.x, brect.size.y, prect.size.x, prect.size.y])

	# ── 2. ИКОНКИ В КНОПКАХ ──────────────────────────────────────────────────
	var icons := 0
	var stretched := 0
	var overflow := 0
	for c in hud.button_container.get_children():
		var b := c as Button
		if b == null:
			continue
		for ch in b.get_children():
			var tr := ch as TextureRect
			if tr == null:
				continue
			icons += 1
			if tr.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
				stretched += 1
			# Картинка обязана помещаться внутрь кнопки с полями
			if tr.get_global_rect().size.x > b.get_global_rect().size.x + 0.5:
				overflow += 1
	verdict("2 [%s] иконки зданий вписаны по пропорциям" % tag,
		icons > 0 and stretched == 0 and overflow == 0,
		"иконок %d, растянутых %d, вылезших %d" % [icons, stretched, overflow])
	verdict("2 [%s] кнопки приказов остались квадратными" % tag,
		_buttons_square(), "сторона %d" % HUD.BTN_SIZE)

	# ── 4/6/9. ПАНЕЛЬ РЕСУРСОВ ───────────────────────────────────────────────
	var rp: Control = hud._res_panel
	var rr: Rect2 = rp.get_global_rect()
	print("    панель ресурсов: %.0fx%.0f" % [rr.size.x, rr.size.y])
	# ПОРОГ ПОДНЯТ 0.30 → 0.36. Проверка сторожит РАЗРАСТАНИЕ панели поперёк
	# экрана, а не конкретное число: старые 30% отражали состав панели, в котором
	# хвост «инструмент + число рабочих» был ровно в ОДНОЙ секции из четырёх.
	# Владелец вернул счётчик рабочих на КАЖДЫЙ ресурс (дерево/камень/золото
	# показывают своих добытчиков, еда — общий счёт), и три дополнительных хвоста
	# физически не влезают в прежний бюджет: сама просьба его и отменяет.
	# Хвост при этом ужат до минимума (RES_WORKER_GLYPH_W 15→12, RES_WORKERS_W
	# 11→9), поэтому 0.36 — это по-прежнему «панель не расползается», а не
	# порог, подогнанный под факт
	verdict("4 [%s] панель ресурсов у́же 36%% экрана" % tag,
		rr.size.x < vp.x * 0.36, "%.0f из %.0f" % [rr.size.x, vp.x])
	verdict("4 [%s] панель ресурсов не ниже 34 px" % tag, rr.size.y >= 34.0,
		"высота %.0f" % rr.size.y)

	# Все 4 секции показывают иконку и белое число
	var shown := 0
	for rd in HUD.RES_DEFS:
		var l: Label = hud._res_labels.get(rd["key"])
		if l != null and l.visible and l.get_global_rect().size.x > 8.0 \
				and l.get_global_rect().size.y > 8.0:
			shown += 1
	verdict("6 [%s] все 4 секции показывают своё число" % tag, shown == 4,
		"видно %d из 4" % shown)

	# Иконки одного визуального размера: рамки равны И заполнены содержимым
	var sizes: Array = []
	var fills: Array = []
	for tr2 in _icons_of(rp):
		sizes.append(tr2.get_global_rect().size)
		fills.append(_fill_ratio(tr2))
	var same := sizes.size() == 4
	for s in sizes:
		if absf((s as Vector2).x - (sizes[0] as Vector2).x) > 1.0:
			same = false
	var worst := 1.0
	for fr in fills:
		worst = minf(worst, float(fr))
	verdict("6 [%s] 4 иконки ресурсов одного размера и заполнены" % tag,
		same and worst >= 0.80,
		"рамки %s, худшее заполнение %.2f" % [str(sizes.size()), worst])

	var st: StyleBoxFlat = rp.get_theme_stylebox("panel") as StyleBoxFlat
	verdict("9 [%s] у панели ресурсов скруглены все 4 угла" % tag,
		st != null and st.corner_radius_top_left > 0 and st.corner_radius_top_right > 0
		and st.corner_radius_bottom_left > 0 and st.corner_radius_bottom_right > 0,
		"радиусы %d/%d/%d/%d" % [st.corner_radius_top_left, st.corner_radius_top_right,
			st.corner_radius_bottom_right, st.corner_radius_bottom_left])

	# ── 7/8. ПРАВАЯ ВЕРХНЯЯ ПАНЕЛЬ ───────────────────────────────────────────
	var tw: Control = _find_deep(hud, "TopRightWidget") as Control
	var twr: Rect2 = tw.get_global_rect()
	print("    правая панель: %.0fx%.0f, правый край в %.0f (экран %.0f)" % [
		twr.size.x, twr.size.y, twr.end.x, vp.x])
	var cut: float = 1.0 - twr.size.x / OLD_TOP_RIGHT_W
	verdict("7 [%s] правая панель уменьшена примерно на 30%%" % tag,
		cut >= 0.22, "ширина %.0f против %.0f (−%.0f%%)"
			% [twr.size.x, OLD_TOP_RIGHT_W, cut * 100.0])

	# Хвост: расстояние от правого края последнего элемента до края панели
	var menu_btn: Button = _find_deep(hud, "MenuButton") as Button
	var tail: float = twr.end.x - menu_btn.get_global_rect().end.x
	verdict("8 [%s] пустого хвоста справа нет" % tag, tail <= 12.0,
		"хвост %.0f px" % tail)

	# Кнопка «Меню» — без своей рамки и во всю высоту секции
	var mstyle: StyleBoxFlat = menu_btn.get_theme_stylebox("normal") as StyleBoxFlat
	var mrect: Rect2 = menu_btn.get_global_rect()
	verdict("7 [%s] у «Меню» нет вложенной рамки" % tag,
		mstyle != null and mstyle.border_width_left == 0
		and mstyle.border_width_right == 0 and mstyle.border_width_top == 0
		and mstyle.border_width_bottom == 0 and mstyle.bg_color.a <= 0.01,
		"рамка %d, фон a=%.2f" % [mstyle.border_width_left, mstyle.bg_color.a])
	verdict("7 [%s] «Меню» кликабельно всей секцией по высоте" % tag,
		mrect.size.y >= twr.size.y - 10.0,
		"кнопка %.0f при панели %.0f" % [mrect.size.y, twr.size.y])
	verdict("7 [%s] правая панель целиком в кадре" % tag,
		twr.position.x >= 0.0 and twr.end.x <= vp.x + 0.5, "rect=%s" % str(twr))

	hud.show_selection([])
	await frames(1)

func _buttons_square() -> bool:
	for c in hud.button_container.get_children():
		var b := c as Button
		if b == null:
			continue
		var r: Rect2 = b.get_global_rect()
		if absf(r.size.x - r.size.y) > 1.0:
			return false
	return true

## Какую долю своей рамки занимает НЕПРОЗРАЧНАЯ часть картинки. Именно этим
## камень и золото проигрывали дереву и мясу: рамка та же, а рисунок сидел
## в середине большого прозрачного поля
func _fill_ratio(tr: TextureRect) -> float:
	var tex: Texture2D = tr.texture
	if tex == null:
		return 0.0
	var src: Texture2D = tex
	if tex is AtlasTexture:
		# Уже обрезано по содержимому — считаем по области атласа
		var at := tex as AtlasTexture
		var base: Texture2D = at.atlas
		var img0: Image = base.get_image()
		if img0 == null:
			return 1.0
		if img0.is_compressed():
			img0.decompress()
		var used0: Rect2i = img0.get_used_rect()
		var reg: Rect2 = at.region
		if reg.size.x <= 0.0 or reg.size.y <= 0.0:
			return 0.0
		return minf(float(used0.size.x) / reg.size.x, 1.0)
	var img: Image = src.get_image()
	if img == null:
		return 1.0
	if img.is_compressed():
		img.decompress()
	var used: Rect2i = img.get_used_rect()
	var w: float = float(img.get_width())
	if w <= 0.0:
		return 0.0
	return float(used.size.x) / w

func _icons_of(root: Node) -> Array:
	var out: Array = []
	if root is TextureRect:
		out.append(root)
	for c in root.get_children():
		out += _icons_of(c)
	return out

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
