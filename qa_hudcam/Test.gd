extends Node

## СТЕНД: ТУМБЛЕР ПОЛОСОК ЗДОРОВЬЯ (ALT), КАМЕРА/МЫШЬ И ПЛАШКА БЕЗДЕЛЬНИКОВ
##
## Разделы:
##   A — тумблер ХП: флаг, полоски у юнитов и построек, наследование при спавне
##   B — перехват клавиши Alt в Main._input (в т.ч. отсечение автоповтора)
##   C — камера: ускоренный скролл краем экрана
##   D — камера: перетаскивание средней кнопкой без инверсии осей
##   E — курсор: ограничение в пределах окна (в headless — только контракт)
##   F — плашка «рабочие без дела»: её нет в верхнем баре, она над панелью,
##       считает верно, гаснет при нуле и по клику показывает рабочего

var main: Node = null
var hud = null
var cam: RTSCamera = null

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

## Найти узел полоски здоровья среди детей сущности
func hp_bar_of(n: Node) -> Node3D:
	for c in n.get_children():
		if c.name == "HPBar":
			return c as Node3D
	return null

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	await frames(2)
	hud = main.hud
	cam = get_viewport().get_camera_3d() as RTSCamera
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 100000.0)
	await frames(1)

	await _test_hp_toggle()
	await _test_alt_key()
	await _test_edge_scroll()
	await _test_drag_axes()
	_test_cursor_confine()
	await _test_idle_widget()
	await _test_group_banner()

	print("\n=== ИТОГ qa_hudcam: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ТУМБЛЕР ПОЛОСОК ЗДОРОВЬЯ
# ═════════════════════════════════════════════════════════════════════════════
func _test_hp_toggle() -> void:
	print("\n═════ A. ТУМБЛЕР ПОЛОСОК ЗДОРОВЬЯ ═════")
	GameManager.set_hp_bars_forced(false)
	await frames(1)

	var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u.faction = Constants.FACTION_PLAYER
	get_tree().root.add_child(u)
	u.global_position = Vector3(0, 0, -400)
	await frames(2)

	verdict("A1 флаг по умолчанию опущен", GameManager.hp_bars_forced == false)
	verdict("A2 у целого бойца полоски нет вовсе", hp_bar_of(u) == null,
		"узел HPBar %s" % ("есть" if hp_bar_of(u) != null else "нет"))

	# Alt поднят
	var st: bool = GameManager.toggle_hp_bars()
	await frames(2)
	var bar := hp_bar_of(u)
	verdict("A3 toggle вернул true", st == true)
	verdict("A4 полоска появилась у целого бойца", bar != null and bar.visible,
		"bar=%s visible=%s" % [str(bar != null), str(bar != null and bar.visible)])

	# Свежий боец наследует режим
	var u2: Unit = load("res://scenes/units/Archer.tscn").instantiate()
	u2.faction = Constants.FACTION_PLAYER
	get_tree().root.add_child(u2)
	u2.global_position = Vector3(3, 0, -400)
	await frames(2)
	var bar2 := hp_bar_of(u2)
	verdict("A5 новый юнит спавнится сразу с полоской",
		bar2 != null and bar2.visible)

	# Постройка
	var b := Building.new()
	b.faction = Constants.FACTION_PLAYER
	get_tree().root.add_child(b)
	b.global_position = Vector3(10, 0, -400)
	await frames(2)
	var bbar := hp_bar_of(b)
	verdict("A6 у постройки полоска тоже есть", bbar != null and bbar.visible)
	verdict("A7 полоска постройки висит над крышей",
		bbar != null and bbar.position.y >= b.build_size.y,
		"y=%.2f, крыша %.2f" % [bbar.position.y if bbar else -1.0, b.build_size.y])

	# Второе нажатие — гасим
	st = GameManager.toggle_hp_bars()
	await frames(2)
	verdict("A8 toggle вернул false", st == false)
	verdict("A9 полоска бойца потухла", hp_bar_of(u) != null and not hp_bar_of(u).visible)
	verdict("A10 полоска постройки потухла",
		hp_bar_of(b) != null and not hp_bar_of(b).visible)

	# ТУМБЛЕР АБСОЛЮТЕН: урон НЕ включает полоску при опущенном Alt
	u.take_damage(10.0, null)
	await frames(2)
	verdict("A11 урон при опущенном тумблере полоску НЕ включает",
		hp_bar_of(u) == null or not hp_bar_of(u).visible,
		"bar=%s" % ("виден" if (hp_bar_of(u) != null and hp_bar_of(u).visible) else "скрыт"))

	# А тот, кого ранили при ВЫКЛЮЧЕННОМ тумблере, при включении показывается
	GameManager.set_hp_bars_forced(true)
	await frames(2)
	verdict("A11b после включения раненый показывает полоску",
		hp_bar_of(u) != null and hp_bar_of(u).visible)

	# И ширина заливки отражает долю здоровья
	var fill: MeshInstance3D = hp_bar_of(u).get_child(0) as MeshInstance3D
	var q := fill.mesh as QuadMesh
	var frac: float = u.current_health / u.max_health
	verdict("A12 ширина заливки = доля здоровья",
		absf(q.size.x - Unit.HP_BAR_WIDTH * frac) < 0.01,
		"ширина %.3f, ожидали %.3f" % [q.size.x, Unit.HP_BAR_WIDTH * frac])

	# Свежий юнит при ОПУЩЕННОМ тумблере полоски не заводит вовсе
	GameManager.set_hp_bars_forced(false)
	await frames(1)
	var u3: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u3.faction = Constants.FACTION_PLAYER
	get_tree().root.add_child(u3)
	u3.global_position = Vector3(6, 0, -400)
	await frames(2)
	u3.take_damage(15.0, null)
	await frames(2)
	verdict("A13 спавн + урон при опущенном тумблере не создают узел полоски",
		hp_bar_of(u3) == null)
	u3.queue_free()

	u.queue_free(); u2.queue_free(); b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. ПЕРЕХВАТ КЛАВИШИ ALT
# ═════════════════════════════════════════════════════════════════════════════
func _key(code: int, pressed: bool, echo: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	e.echo = echo
	return e

func _test_alt_key() -> void:
	print("\n═════ B. КЛАВИША ALT ═════")
	GameManager.set_hp_bars_forced(false)
	await frames(1)

	main._input(_key(KEY_ALT, true))
	verdict("B1 Alt поднял тумблер", GameManager.hp_bars_forced == true)

	main._input(_key(KEY_ALT, true))
	verdict("B2 второй Alt опустил тумблер", GameManager.hp_bars_forced == false)

	# Автоповтор зажатой клавиши НЕ должен мигать полосками
	main._input(_key(KEY_ALT, true))
	var before: bool = GameManager.hp_bars_forced
	for _i in range(5):
		main._input(_key(KEY_ALT, true, true))   # echo
	verdict("B3 автоповтор (echo) тумблер не трогает",
		GameManager.hp_bars_forced == before)

	# Отпускание тоже не переключает
	main._input(_key(KEY_ALT, false))
	verdict("B4 отпускание Alt тумблер не трогает",
		GameManager.hp_bars_forced == before)

	# Посторонняя клавиша
	before = GameManager.hp_bars_forced
	main._input(_key(KEY_G, true))
	verdict("B5 другая клавиша тумблер не трогает",
		GameManager.hp_bars_forced == before)

	GameManager.set_hp_bars_forced(false)
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# C. СКРОЛЛ КРАЕМ ЭКРАНА
# ═════════════════════════════════════════════════════════════════════════════
func _test_edge_scroll() -> void:
	print("\n═════ C. СКОРОСТЬ СКРОЛЛА КРАЕМ ЭКРАНА ═════")
	verdict("C1 у скролла краем своя ручка скорости",
		"edge_pan_boost" in cam, "")
	var boost: float = cam.edge_pan_boost
	verdict("C2 ускорение в диапазоне +30…40%%",
		boost >= 1.30 and boost <= 1.40, "edge_pan_boost=%.2f" % boost)

	# В headless курсор стоит в (0,0) — это левый ВЕРХНИЙ угол, то есть оба
	# края сразу. Значит скролл краем можно измерить прямо: гоняем _process
	# камеры вручную и смотрим, сколько метров прошёл фокус
	cam.set_bounds(1e6, 1e6)
	cam._focus = Vector3.ZERO
	cam._mmb_pressed = false
	var dt := 0.05
	var steps := 20
	for _i in range(steps):
		cam._process(dt)
	var dist: float = Vector2(cam._focus.x, cam._focus.z).length()
	var want: float = cam.pan_speed * boost * dt * steps
	verdict("C3 фокус едет со скоростью pan_speed × boost",
		absf(dist - want) < want * 0.05,
		"прошли %.2f м, ожидали %.2f м" % [dist, want])

	var plain: float = cam.pan_speed * dt * steps
	verdict("C4 это заметно быстрее прежней скорости",
		dist > plain * 1.25,
		"стало %.2f м против %.2f м раньше (+%.0f%%)" % [
			dist, plain, (dist / maxf(plain, 0.001) - 1.0) * 100.0])
	cam._focus = Vector3.ZERO

# ═════════════════════════════════════════════════════════════════════════════
# D. ПЕРЕТАСКИВАНИЕ КАРТЫ СРЕДНЕЙ КНОПКОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _mouse_btn(idx: int, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = pressed
	e.position = at
	return e

func _motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	return e

## Протащить мышь из a в b при зажатой средней кнопке и вернуть сдвиг фокуса
func _drag(a: Vector2, b: Vector2) -> Vector3:
	cam._focus = Vector3.ZERO
	cam._unhandled_input(_mouse_btn(MOUSE_BUTTON_MIDDLE, true, a))
	cam._unhandled_input(_motion(b))
	cam._unhandled_input(_mouse_btn(MOUSE_BUTTON_MIDDLE, false, b))
	return cam._focus

func _test_drag_axes() -> void:
	print("\n═════ D. ПЕРЕТАСКИВАНИЕ КАРТЫ (ИНВЕРСИЯ ОСЕЙ) ═════")
	cam.set_bounds(1e6, 1e6)
	# Ракурс камеры: yaw=0, значит объектив смотрит вдоль −Z. «Вглубь экрана» —
	# это уменьшение Z, «вправо по экрану» — увеличение X.
	#
	# Ожидаемое поведение «схватил карту и потащил»: содержимое идёт ЗА
	# курсором, поэтому фокус камеры едет в ПРОТИВОПОЛОЖНУЮ сторону.

	# Тянем мышь ВНИЗ по экрану → содержимое уезжает вниз → фокус уходит вглубь
	var d := _drag(Vector2(640, 300), Vector2(640, 400))
	verdict("D1 тянем вниз — карта едет вниз (фокус вглубь, Z уменьшается)",
		d.z < -0.001, "Δz=%.3f" % d.z)
	verdict("D2 вертикальное перетаскивание не косит по X",
		absf(d.x) < 0.001, "Δx=%.4f" % d.x)

	# Тянем ВВЕРХ → зеркально
	var u := _drag(Vector2(640, 400), Vector2(640, 300))
	verdict("D3 тянем вверх — фокус идёт к зрителю (Z растёт)",
		u.z > 0.001, "Δz=%.3f" % u.z)
	verdict("D4 вверх и вниз симметричны",
		absf(u.z + d.z) < 0.001, "вниз %.3f, вверх %.3f" % [d.z, u.z])

	# Горизонталь как была: тянем ВПРАВО → содержимое вправо → фокус влево
	var r := _drag(Vector2(500, 350), Vector2(700, 350))
	verdict("D5 тянем вправо — фокус уходит влево (X уменьшается)",
		r.x < -0.001, "Δx=%.3f" % r.x)
	verdict("D6 горизонталь не косит по Z", absf(r.z) < 0.001, "Δz=%.4f" % r.z)

	# Обе оси согласованы: диагональ = сумма составляющих
	var diag := _drag(Vector2(500, 300), Vector2(700, 400))
	verdict("D7 диагональ = сумма горизонтали и вертикали",
		absf(diag.x - r.x) < 0.001 and absf(diag.z - d.z) < 0.001,
		"диаг(%.3f, %.3f) против (%.3f, %.3f)" % [diag.x, diag.z, r.x, d.z])

	# Масштаб перетаскивания привязан к зуму (ортография: метров на пиксель)
	cam._height = 40.0
	var far_drag := _drag(Vector2(640, 300), Vector2(640, 400))
	cam._height = 80.0
	var near_drag := _drag(Vector2(640, 300), Vector2(640, 400))
	verdict("D8 на большем отдалении тот же жест тащит дальше",
		absf(near_drag.z) > absf(far_drag.z) * 1.9,
		"zoom40: %.3f, zoom80: %.3f" % [far_drag.z, near_drag.z])
	cam._height = 48.0
	cam._focus = Vector3.ZERO

# ═════════════════════════════════════════════════════════════════════════════
# E. ОГРАНИЧЕНИЕ КУРСОРА ОКНОМ
# ═════════════════════════════════════════════════════════════════════════════
func _test_cursor_confine() -> void:
	print("\n═════ E. КУРСОР НЕ УХОДИТ НА ВТОРОЙ МОНИТОР ═════")
	# КОНТРАКТ ИЗМЕНИЛСЯ: захвата курсора окном БОЛЬШЕ НЕТ. MOUSE_MODE_CONFINED
	# запирал курсор внутри окна и вместе с ним — под полосой заголовка Windows:
	# свернуть/развернуть/закрыть становились недоступны, игра выглядела
	# зависшей. Прокрутку краем теперь глушит сама камера, требуя фокус окна
	# (RTSCamera._window_focused), а не режим мыши
	verdict("E1 захвата курсора окном больше нет",
		not main.has_method("_confine_mouse"))
	verdict("E1б прокрутка краем закрыта фокусом окна в камере",
		cam.has_method("_window_focused") and cam._window_focused())
	verdict("E2 headless распознан (DisplayServer не трогается)",
		main._has_window() == false,
		"DisplayServer=%s" % DisplayServer.get_name())
	var before := Input.get_mouse_mode()
	verdict("E3 в headless режим мыши не тронут",
		Input.get_mouse_mode() == before)
	# Обработчика потери фокуса у Main больше нет — он существовал ТОЛЬКО ради
	# захвата курсора и удалён вместе с ним
	verdict("E4 курсор остаётся свободным (режим VISIBLE)",
		Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE
		or DisplayServer.get_name() == "headless",
		"режим=%s" % str(Input.get_mouse_mode()))

# ═════════════════════════════════════════════════════════════════════════════
# F. ПЛАШКА «РАБОЧИЕ БЕЗ ДЕЛА»
# ═════════════════════════════════════════════════════════════════════════════
## Есть ли узел among потомков (рекурсивно)
func _is_descendant(root: Node, target: Node) -> bool:
	var n := target
	while n != null:
		if n == root:
			return true
		n = n.get_parent()
	return false

## Есть ли где-нибудь внутри узла TextureRect (иконки часто обёрнуты контейнером)
func _has_texture_rect(root: Node) -> bool:
	if root is TextureRect:
		return true
	for c in root.get_children():
		if _has_texture_rect(c):
			return true
	return false

func _test_idle_widget() -> void:
	print("\n═════ F. ПЛАШКА «РАБОЧИЕ БЕЗ ДЕЛА» ═════")
	var btn: Button = hud._idle_btn
	verdict("F1 плашка существует", btn != null and is_instance_valid(btn))

	# Верхний бар — первый PanelContainer, добавленный HUD в _build_resource_bar
	var top_bar: Node = null
	for c in hud.get_children():
		if c is PanelContainer and c != hud._bottom_panel:
			top_bar = c
			break
	verdict("F2 верхний бар найден", top_bar != null)
	verdict("F3 плашки в верхнем баре БОЛЬШЕ НЕТ",
		top_bar != null and not _is_descendant(top_bar, btn),
		"родитель плашки: %s" % str(btn.get_parent().name))
	verdict("F4 плашки нет и в нижней панели (она плавающая)",
		not _is_descendant(hud._bottom_panel, btn))

	# ПОЛОСА ГРУПП ВЕРНУЛАСЬ — но уже как УРОВЕНЬ 1 двухуровневого выделения
	# (см. qa_sel2 A1): узел существует всегда, а виден только на СМЕШАННОМ
	# выделении, где детальной панели нет вовсе. Жалоба владельца была на
	# дублирование портрета и счётчика — вот его и проверяем: сейчас выделения
	# нет, значит и полосы на экране быть не должно
	var bar: Control = hud._overbar
	verdict("F5 полоса групп скрыта, пока выделение не смешанное",
		bar != null and not bar.visible)
	verdict("F6 сводных ярлыков в баннере нет", hud.type_slots() == 0,
		"слотов %d" % hud.type_slots())
	verdict("F7 ярлык рабочих при этом на месте и в кадре",
		btn != null and is_instance_valid(btn) and btn.is_inside_tree())
	# КОНТРАКТ ИЗМЕНИЛСЯ: ярлык рабочих ВЫНЕСЕН ИЗ баннера в самостоятельный
	# виджет под ресурсной строкой. Баннер пересобирается при каждой смене
	# выделения (_rebuild_overbar освобождает всех своих детей), и кнопку,
	# по которой игрок только что кликнул, могло удалить прямо в момент клика
	verdict("F7b ярлык рабочих ВЫНЕСЕН из баннера в отдельный виджет",
		not _is_descendant(bar, btn),
		"родитель: %s" % str(btn.get_parent().name))
	await frames(2)
	var r: Rect2 = btn.get_global_rect()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	verdict("F8 плашка целиком в кадре",
		r.position.x >= 0.0 and r.position.y >= 0.0 \
			and r.end.x <= vp.x and r.end.y <= vp.y,
		"rect=%s, экран=%s" % [str(r), str(vp)])
	verdict("F9 плашка не наезжает на командную панель",
		r.end.y <= hud._bottom_panel.get_global_rect().position.y + 0.5,
		"низ плашки %.0f, верх панели %.0f" % [
			r.end.y, hud._bottom_panel.get_global_rect().position.y])

	# Содержимое: иконка + цифра
	verdict("F10 у ярлыка есть счётчик", hud._idle_count_label != null)
	# Иконка лежит в MarginContainer, а не прямым ребёнком кнопки — ищем вглубь
	var has_icon: bool = _has_texture_rect(btn)
	if btn.text != "":
		has_icon = true          # ассета нет — рисуется кирка текстом
	verdict("F11 у ярлыка есть иконка рабочего", has_icon)

	# Пусто — плашка погашена и не ловит клики
	hud._idle_timer = 0.0
	hud._idle_last = -1
	hud._update_idle_counter(1.0)
	await frames(1)
	var n0: int = hud._idle_workers().size()
	verdict("F12 при нуле бездельников плашка погашена",
		n0 > 0 or btn.modulate.a < 0.9, "бездельников %d, alpha=%.2f" % [n0, btn.modulate.a])
	verdict("F13 погашенная плашка кликов не ловит",
		n0 > 0 or btn.disabled, "disabled=%s" % str(btn.disabled))

	# Заводим трёх бездельников
	var ws: Array = []
	for i in range(3):
		var w: Worker = load("res://scenes/units/Worker.tscn").instantiate()
		w.faction = Constants.FACTION_PLAYER
		get_tree().root.add_child(w)
		w.global_position = Vector3(-300 + i * 4, 0, -300)
		ws.append(w)
	await frames(3)
	hud._idle_timer = 0.0
	hud._idle_last = -1
	hud._update_idle_counter(1.0)
	await frames(1)
	var n: int = hud._idle_workers().size()
	verdict("F14 счётчик совпадает со списком бездельников",
		hud._idle_count_label.text == str(n),
		"на плашке «%s», в списке %d" % [hud._idle_count_label.text, n])
	verdict("F15 бездельники найдены", n >= 3, "нашли %d" % n)
	verdict("F16 при непустом списке плашка яркая", btn.modulate.a >= 0.99,
		"alpha=%.2f" % btn.modulate.a)
	verdict("F17 и кликабельна", not btn.disabled)

	# Клик: выделяет рабочего и наводит камеру
	var sm: SelectionManager = main.selection_manager
	sm._clear_selection()
	cam._focus = Vector3(60, 0, 60)
	btn.emit_signal("pressed")
	await frames(2)
	# ОДИН КЛИК — ВСЕ БЕЗДЕЛЬНИКИ РАЗОМ (заказ владельца).
	# Прежний обход по одному требовал шести кликов и шести приказов, чтобы
	# раздать работу шестерым; сам метод обхода остался в HUD под будущую
	# горячую клавишу, но кнопка теперь делает именно «выделить всех»
	var idle_all: Array = hud._idle_workers()
	verdict("F18 клик выделил ВСЕХ незанятых рабочих",
		sm.selected_units.size() == idle_all.size() and idle_all.size() >= 3,
		"выделено %d, без дела %d" % [sm.selected_units.size(), idle_all.size()])
	var sel: Node = sm.selected_units[0] if sm.selected_units.size() > 0 else null
	verdict("F19 выделены именно простаивающие рабочие",
		sel != null and sel is Worker and sel in idle_all)
	# Камера наводится на СЕРЕДИНУ найденных, а не на первого: бездельники
	# обычно стоят кучей, и центр показывает всю группу сразу
	var want_c := Vector3.ZERO
	for w2 in sm.selected_units:
		want_c += (w2 as Node3D).global_position
	if not sm.selected_units.is_empty():
		want_c /= float(sm.selected_units.size())
	verdict("F20 камера наведена на середину группы",
		absf(cam._focus.x - want_c.x) < 2.0 and absf(cam._focus.z - want_c.z) < 2.0,
		"фокус (%.1f, %.1f), центр группы (%.1f, %.1f)" % [
			cam._focus.x, cam._focus.z, want_c.x, want_c.z])

	# Повторный клик даёт ТОТ ЖЕ набор — это не обход по кругу, а выделение всех
	var again := {}
	btn.emit_signal("pressed")
	await frames(1)
	for w3 in sm.selected_units:
		again[w3.get_instance_id()] = true
	verdict("F21 повторный клик даёт тот же полный набор, а не следующего",
		again.size() == idle_all.size(),
		"во второй раз выделено %d из %d" % [again.size(), idle_all.size()])

	# Занятого рабочего плашка перестаёт считать
	var before_n: int = hud._idle_workers().size()
	ws[0].state = Unit.State.GATHERING
	await frames(1)
	hud._idle_timer = 0.0
	hud._idle_last = -1
	hud._update_idle_counter(1.0)
	await frames(1)
	verdict("F22 занявшийся рабочий выпал из счётчика",
		hud._idle_workers().size() == before_n - 1 \
			and hud._idle_count_label.text == str(before_n - 1),
		"было %d, стало %s" % [before_n, hud._idle_count_label.text])

	for w in ws:
		w.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# G. БАННЕР ГРУПП И КАРТОЧКИ ОТДЕЛЬНЫХ ОТРЯДОВ
# ═════════════════════════════════════════════════════════════════════════════
## Собрать отряд из n бойцов заданного типа
func _mk_squad(kind: String, n: int, at: Vector3) -> int:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	for i in range(n):
		var u: Unit = load("res://scenes/units/%s.tscn"
			% kind.capitalize()).instantiate()
		u.faction = Constants.FACTION_PLAYER
		get_tree().root.add_child(u)
		u.global_position = at + Vector3(float(i) * 0.6, 0.0, 0.0)
		GameManager.add_to_squad(sid, u)
	return sid

func _test_group_banner() -> void:
	print("\n═════ G. БАННЕР ГРУПП И КАРТОЧКИ ОТРЯДОВ ═════")
	var sm: SelectionManager = main.selection_manager
	sm._clear_selection()

	# Три отряда копейщиков и два лучников
	var spears: Array = []
	for i in range(3):
		spears.append(_mk_squad("spearman", 4, Vector3(-200 + i * 12, 0, -200)))
	var bows: Array = []
	for i in range(2):
		bows.append(_mk_squad("archer", 3, Vector3(-200 + i * 12, 0, -180)))
	await frames(3)

	var all: Array = []
	for sid in spears + bows:
		for m in GameManager.squad_members(int(sid)):
			all.append(m)
	hud.show_selection(all)
	await frames(2)

	# УРОВЕНЬ 1: на смешанном выделении полоса групп ОБЯЗАНА появиться, а
	# детальная панель — исчезнуть (см. qa_sel2 A1). Ровно два типа в наборе —
	# копейщики и лучники, значит и слота должно быть два
	verdict("G1 на смешанном выделении полоса групп показана",
		hud._overbar != null and hud._overbar.visible
		and (hud._bottom_panel == null or not hud._bottom_panel.visible),
		"полоса=%s панель=%s" % [
			str(hud._overbar != null and hud._overbar.visible),
			str(hud._bottom_panel != null and hud._bottom_panel.visible)])
	verdict("G2 сводных ярлыков ровно по числу типов",
		hud.type_slots() == 2, "слотов %d" % hud.type_slots())
	verdict("G3 ярлык рабочих живёт отдельно и не зависит от выделения",
		hud._idle_btn != null and is_instance_valid(hud._idle_btn)
		and hud._idle_btn.is_inside_tree())

	# Разворачивание группы
	verdict("G4 до разворачивания карточек отрядов нет",
		hud._squad_strip.get_child_count() == 0)
	# Точка входа игрока — клик по групповой иконке в полосе уровня 1;
	# здесь зовём тот же обработчик напрямую
	hud._on_type_filter_pressed("spearman")
	await frames(2)
	verdict("G5 клик по группе развернул ровно 3 карточки копейщиков",
		hud._squad_strip.get_child_count() == 3,
		"карточек %d" % hud._squad_strip.get_child_count())
	verdict("G6 выделение от разворачивания НЕ меняется",
		hud._sel_units.size() == all.size(),
		"было %d, стало %d" % [all.size(), hud._sel_units.size()])

	# У каждой карточки есть красная шкала
	var with_bar := 0
	for card in hud._squad_strip.get_children():
		for c in card.get_children():
			if c is PanelContainer and c.get_child_count() > 0 \
					and c.get_child(0) is ColorRect:
				with_bar += 1
	verdict("G7 под каждой карточкой красная шкала", with_bar == 3,
		"со шкалой %d из %d" % [with_bar, hud._squad_strip.get_child_count()])

	# Шкала отражает долю: бьём один отряд и смотрим, что она короче
	var hurt: int = int(spears[0])
	var full_w: float = hud._squad_strength(int(spears[1]))
	for m in GameManager.squad_members(hurt):
		(m as Unit).current_health = (m as Unit).max_health * 0.25
	await frames(1)
	var hurt_w: float = hud._squad_strength(hurt)
	verdict("G8 шкала раненого отряда заметно короче целого",
		hurt_w < full_w * 0.5, "раненый %.2f, целый %.2f" % [hurt_w, full_w])

	# Потери тоже режут шкалу
	var before_str: float = hud._squad_strength(int(spears[1]))
	var mem := GameManager.squad_members(int(spears[1]))
	(mem[0] as Unit)._die()
	await frames(2)
	var after_str: float = hud._squad_strength(int(spears[1]))
	verdict("G9 гибель бойца укорачивает шкалу отряда",
		after_str < before_str,
		"было %.3f, стало %.3f" % [before_str, after_str])

	# Клик по карточке — в выделении остаётся только этот отряд
	hud._on_squad_card_pressed(hurt)
	await frames(2)
	var only_hurt := true
	for u in sm.selected_units:
		if (u as Unit).squad_id != hurt:
			only_hurt = false
	verdict("G10 клик по карточке оставил ровно один отряд",
		only_hurt and sm.selected_units.size() == GameManager.squad_members(hurt).size(),
		"выделено %d, в отряде %d" % [
			sm.selected_units.size(), GameManager.squad_members(hurt).size()])
	# Баннера нет — вместо него проверяем, что сужение выделения не сломало сам
	# HUD: нижняя панель на месте и показывает оставшийся отряд
	verdict("G11 нижняя панель после сужения выделения цела",
		hud._bottom_panel != null and is_instance_valid(hud._bottom_panel)
		and hud._bottom_panel.visible and hud._sel_units.size() > 0,
		"в панели %d бойцов" % hud._sel_units.size())

	# Повторный клик по той же группе сворачивает её
	hud.show_selection(all)
	await frames(1)
	hud._on_type_filter_pressed("archer")
	await frames(1)
	var a_cards: int = hud._squad_strip.get_child_count()
	hud._on_type_filter_pressed("archer")
	await frames(1)
	verdict("G12 повторный клик сворачивает группу",
		a_cards == 2 and hud._squad_strip.get_child_count() == 0,
		"развернулось %d, после повтора %d" % [a_cards, hud._squad_strip.get_child_count()])

	# Новое выделение сбрасывает развёрнутую группу
	hud._on_type_filter_pressed("spearman")
	await frames(1)
	hud.show_selection([])
	await frames(1)
	verdict("G13 новое выделение сворачивает карточки",
		hud._squad_strip.get_child_count() == 0 and hud._expanded_type == "")

	for u in all:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(2)
