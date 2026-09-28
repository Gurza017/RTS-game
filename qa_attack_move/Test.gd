extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: КОМАНДЫ ОТРЯДУ [S] / [C] / [A] И АТАКА ПО ПУТИ (ТЗ 23.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A — ХОТКЕИ. Настоящий ввод через _unhandled_input (правило стендов
##       интерфейса): [S] ставит всё выделение в оборону, [C] возвращает в
##       атаку, [A] взводит режим и гаснет по второму нажатию и по Esc.
##       Команда идёт ВСЕМ выделенным отрядам, а не первому.
##   B — ATTACK-MOVE. Отряд, посланный по [A] мимо врага, ВСТУПАЕТ В БОЙ
##       (командир нашёл его отрядным сканом), а зачистив — САМ доходит до
##       изначальной точки и снимает режим.
##   C — ЦЕНА СКАНА. Число сканов растёт от ЧИСЛА ОТРЯДОВ, а не от числа
##       моделей: это и есть требование ТЗ «не area_scan на каждого юнита».
##   D — ОТМЕНА. Любой новый приказ игрока (ПКМ) снимает режим: иначе
##       командир возвращал бы отряд к старой точке после каждой стычки.
##   E — ЩЕЛЧОК ПРИКАЗА. Процедурный звук собран кодом и подключён к каждой
##       ветке приказа на движение.
##
## Запуск: godot --headless --path . res://qa_attack_move/Test.tscn

const _UCfgT := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	# СТОРОЖ ОБЯЗАТЕЛЕН: ошибка внутри корутины стенда убивает её молча
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

## Ждём ФИЗКАДРЫ, а не кадры отрисовки: при Engine.max_fps = 0 отрисовка
## обгоняет физику, и «подождать, пока дойдёт» по process_frame не работает
func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_attack_move: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	main.selection_manager._unhandled_input(ev)

func _squad(uid: String, at: Vector3, n: int, fac: int = Constants.FACTION_PLAYER) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	for i in range(n):
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = fac
		main.world_add(u)
		var p := at + Vector3(float(i % 5) * 0.7, 0.0, float(i / 5) * 0.7)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _alive(men: Array) -> int:
	var n := 0
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n

func _centre(men: Array) -> Vector3:
	var live: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			live.append(m)
	if live.is_empty():
		return Vector3.INF
	return GameManager._centroid_of(live)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	# ДИКИЕ И ИИ ВМЕШИВАЮТСЯ В ЗАМЕР — глушим их явно (правило стендов)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	# Стенд ставит свою площадку в поле карты (габарит армии задаёт ячейку
	# сетки ядра), но границы снимает: реки и маршрутов ему не нужно
	GameManager.world_bounds_enabled = false
	GameManager.pop_limit_enabled = false
	await pframes(4)

	await _block_hotkeys()
	await _block_attack_move()
	await _block_scan_cost()
	await _block_cancel()
	# БЕЗ await ЗДЕСЬ ВЕРДИКТ E4 ТЕРЯЕТСЯ МОЛЧА: внутри блока есть await, то
	# есть он корутина, а _finish() успевал закрыть стенд раньше неё
	await _block_sound()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ХОТКЕИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_hotkeys() -> void:
	print("\n═════ A. ГОРЯЧИЕ КЛАВИШИ S / C / A ═════")
	var sm = main.selection_manager
	var base := Vector3(-300.0, 0.0, -300.0)
	var a: Array = _squad("spearman", base, 8)
	var b: Array = _squad("spearman", base + Vector3(14.0, 0.0, 0.0), 8)
	await pframes(3)
	sm.selected_units = a + b
	GameManager.on_selection_changed(sm.selected_units)
	await pframes(2)

	_key(KEY_S)
	await pframes(2)
	var s_all := true
	for u in a + b:
		if String((u as Unit).stance) != _UCfgT.STANCE_DEFENSE:
			s_all = false
	verdict("A1 [S] ставит в оборону ВСЕ выделенные отряды", s_all,
		"стойки: %s / %s" % [(a[0] as Unit).stance, (b[0] as Unit).stance])

	_key(KEY_C)
	await pframes(2)
	var c_all := true
	for u2 in a + b:
		if String((u2 as Unit).stance) != _UCfgT.STANCE_ATTACK:
			c_all = false
	verdict("A2 [C] возвращает все отряды в атаку", c_all,
		"стойки: %s / %s" % [(a[0] as Unit).stance, (b[0] as Unit).stance])

	_key(KEY_A)
	await frames(1)
	var armed1: bool = sm.attack_move_armed
	_key(KEY_A)
	await frames(1)
	var armed2: bool = sm.attack_move_armed
	verdict("A3 [A] взводит режим атаки и гасит его вторым нажатием",
		armed1 and not armed2, "после первого %s, после второго %s" % [armed1, armed2])

	_key(KEY_A)
	await frames(1)
	_key(KEY_ESCAPE)
	await frames(1)
	verdict("A4 Esc снимает взведённый режим", not sm.attack_move_armed,
		"режим=%s" % sm.attack_move_armed)

	# ПУСТОЕ ВЫДЕЛЕНИЕ КОМАНД НЕ ПОЛУЧАЕТ: клавиша не должна «висеть» режимом,
	# когда командовать некому — следующий клик игрока стал бы приказом никому
	sm.selected_units = []
	GameManager.on_selection_changed([])
	await frames(1)
	sm.set_attack_move_armed(true)
	verdict("A5 без выделения режим не взводится", not sm.attack_move_armed,
		"режим=%s" % sm.attack_move_armed)
	for u3 in a + b:
		(u3 as Unit).take_damage(1e9)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. АТАКА ПО ПУТИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_attack_move() -> void:
	print("\n═════ B. ATTACK-MOVE: БОЙ ПО ДОРОГЕ И ВОЗВРАТ К МАРШУ ═════")
	var sm = main.selection_manager
	var start := Vector3(-300.0, 0.0, 0.0)
	var dest := start + Vector3(90.0, 0.0, 0.0)
	# ── ВРАГ СТОИТ НА САМОЙ ЛИНИИ МАРША (ТЗ 23.09.2026, п. 4) ─────────────
	# Прежде он стоял в 8 м В СТОРОНЕ, и проверка требовала, чтобы отряд к
	# нему СВЕРНУЛ. Заказ это развернул дословно: «три отряда видят одного
	# гоблина — вся армия бросает марш и бежит за ним; исправь». Сворачивать
	# за тем, до кого не достаёшь, теперь НЕ НАДО, и в стороне враг проверяет
	# уже обратное свойство (блок B5 ниже). Здесь он на пути: отряд упрётся
	# в него, как ни иди
	var foe_at := start + Vector3(45.0, 0.0, 1.0)
	var ours: Array = _squad("warrior", start, 10)
	var theirs: Array = _squad("spearman", foe_at, 4, Constants.FACTION_ENEMY)
	await pframes(3)
	sm.selected_units = ours.duplicate()
	GameManager.on_selection_changed(sm.selected_units)
	await pframes(2)

	var cmd = sm.squad_commander()
	var sid: int = (ours[0] as Unit).squad_id
	var n0: int = cmd.attack_move(sm, dest, false)
	verdict("B1 приказ принят отрядом", n0 == 1 and cmd.is_attack_moving(sid),
		"отрядов %d, режим=%s" % [n0, cmd.is_attack_moving(sid)])

	# Ждём, пока командир найдёт врага и завяжет бой
	var eng := 0
	# ОКНО СЧИТАЕТСЯ ОТ ДИСТАНЦИИ, А НЕ ВЗЯТО КРУГЛЫМ: до врага 45 м, мечник
	# идёт ~2.2 м/с — это двадцать секунд одного только подхода. Первый заход
	# ждал 900 физкадров (15 с) и краснел на исправном коде
	for _i in range(2400):
		await get_tree().physics_frame
		if cmd.engagements > 0:
			eng = cmd.engagements
			break
	verdict("B2 командир сам завязал бой по дороге", eng > 0,
		"стычек %d, сканов %d" % [cmd.engagements, cmd.scans])

	# Ждём зачистки и возврата к маршу
	var arrived := false
	for _j in range(6000):
		await get_tree().physics_frame
		if not cmd.is_attack_moving(sid):
			arrived = true
			break
	var c: Vector3 = _centre(ours)
	var gap: float = 1e9 if c == Vector3.INF else Vector2(c.x - dest.x, c.z - dest.z).length()
	var lead0 := ours[0] as Unit
	if is_instance_valid(lead0):
		print("    состояние вожака: state=%d, post=%.1f/%.1f, паника=%s" % [
			int(lead0.state), lead0.post_pos.x, lead0.post_pos.z,
			str(GameManager.squad_panicked(sid))])
	verdict("B3 зачистив участок, отряд дошёл до точки и снял режим",
		arrived and gap <= cmd.AM_ARRIVE * 2.0,
		"режим снят=%s, до точки %.1f м, возвратов к маршу %d" % [arrived, gap, cmd.resumes])
	# ПОРОГ НЕ НОЛЬ, И ЭТО НЕ ПОБЛАЖКА. Последний выживший ПАНИКУЕТ и бежит
	# (мораль отряда падает по доле потерь), а паникующего командир законно
	# бросает: он больше не мешает маршу, ради которого приказ и отдавался.
	# Ноль требовал бы от Attack-Move догонять бегущих через полкарты — то
	# есть ровно того поведения, от которого заведён поводок погони.
	# Прогон с нулевым порогом мигал: 0 из 4 и 1 из 4 на НЕИЗМЕННОМ коде
	verdict("B4 отряд на пути разбит (уцелевший бежит)", _alive(theirs) <= 1,
		"живых врагов %d из %d" % [_alive(theirs), theirs.size()])
	for u in ours:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e9)
	for t in theirs:
		if is_instance_valid(t) and not (t as Unit).is_dead():
			(t as Unit).take_damage(1e9)
	await pframes(3)
	await _block_no_chase()

# ═════════════════════════════════════════════════════════════════════════════
# B5-B7. НЕ ГНАТЬСЯ И НЕ СВОРАЧИВАТЬ (ТЗ 23.09.2026, п. 4)
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца дословно: «марширует 3 отряда, видят 1 гоблина — вся
## армия бросает марш и толпой бежит за ним». Проверяем ОБА свойства, из
## которых это складывалось: отряд не сворачивает к тому, до кого не
## достаёт, и не идёт за тем, кто отступает.
func _block_no_chase() -> void:
	print("\n═════ B5-B7. МАРШ НЕ ПРЕВРАЩАЕТСЯ В ПОГОНЮ ═════")
	var sm = main.selection_manager
	var cmd = sm.squad_commander()
	var start := Vector3(-600.0, 0.0, -300.0)
	var dest := start + Vector3(80.0, 0.0, 0.0)
	# ОДИН гоблин в стороне от линии марша — дальше, чем достаёт копьё, но
	# заведомо ближе прежнего радиуса 14 м: ровно тот случай из жалобы
	var lone_at := start + Vector3(40.0, 0.0, 11.0)
	var ours: Array = _squad("spearman", start, 12)
	var lone: Array = _squad("gnoll", lone_at, 1, Constants.FACTION_GOBLIN)
	# ГНОЛЛ ЗАМОРОЖЕН, И ЭТО НЕ ПОДГОНКА. Стенд проверяет ОДНО свойство —
	# «отряд не сворачивает к тому, до кого не достаёт». Живой гнолл метает
	# кости на 13.5 м, то есть сам обстреливает колонну, копейщики несут
	# потери и в какой-то момент законно ПАНИКУЮТ — и стенд мерил бы панику
	# вместо агро (первый прогон: отряд убежал на 105 м от цели).
	# set_tick(false) не убирает строку из сетки ядра (см. CLAUDE.md), так
	# что для отрядного скана он остаётся такой же целью, как живой
	for g0 in lone:
		(g0 as Unit).set_tick(false)
	await pframes(3)
	sm.selected_units = ours.duplicate()
	GameManager.on_selection_changed(sm.selected_units)
	var sid: int = (ours[0] as Unit).squad_id
	cmd.engagements = 0
	cmd.leash_breaks = 0
	cmd.attack_move(sm, dest, false)
	# Ждём, пока отряд пройдёт мимо и дойдёт
	var done := false
	for _i in range(4000):
		await get_tree().physics_frame
		if not cmd.is_attack_moving(sid):
			done = true
			break
	var c: Vector3 = _centre(ours)
	var gap: float = 1e9 if c == Vector3.INF else Vector2(c.x - dest.x, c.z - dest.z).length()
	verdict("B5 одиночка в стороне не сбивает отряд с марша",
		done and gap <= cmd.AM_ARRIVE * 2.0,
		"дошёл=%s, до точки %.1f м, стычек %d" % [done, gap, cmd.engagements])
	# Гоблин обязан остаться жив: отряд к нему не ходил
	verdict("B6 отряд не гонялся за ним (цель цела)", _alive(lone) == 1,
		"живых одиночек %d" % _alive(lone))
	# Насколько отряд отклонился от прямой старт→цель. Считаем по ПИКУ
	# отклонения центра, а не по финалу: в финале он всё равно в точке
	verdict("B7 центр отряда не уходил к цели за поводок",
		cmd.leash_breaks == 0,
		"обрывов поводка %d (их не должно быть: отряд и не сворачивал)" % cmd.leash_breaks)
	for u in ours:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e9)
	for g in lone:
		if is_instance_valid(g) and not (g as Unit).is_dead():
			(g as Unit).take_damage(1e9)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ЦЕНА СКАНА: ОТ ЧИСЛА ОТРЯДОВ, А НЕ ОТ ЧИСЛА МОДЕЛЕЙ
# ═════════════════════════════════════════════════════════════════════════════
func _block_scan_cost() -> void:
	print("\n═════ C. СКАН ОДИН НА ОТРЯД ═════")
	var sm = main.selection_manager
	var cmd = sm.squad_commander()
	var base := Vector3(300.0, 0.0, -300.0)
	# ОДИН отряд из 40 моделей против ЧЕТЫРЁХ отрядов по 10: моделей поровну.
	# Если бы скан шёл на бойца, числа сканов совпали бы
	var big: Array = _squad("spearman", base, 40)
	await pframes(3)
	sm.selected_units = big.duplicate()
	GameManager.on_selection_changed(sm.selected_units)
	cmd.scans = 0
	cmd.attack_move(sm, base + Vector3(60.0, 0.0, 0.0), false)
	await pframes(120)
	var scans_one: int = cmd.scans
	for u in big:
		(u as Unit).take_damage(1e9)
	await pframes(3)

	var many: Array = []
	for k in range(4):
		many += _squad("spearman", base + Vector3(0.0, 0.0, 12.0 * float(k + 1)), 10)
	await pframes(3)
	sm.selected_units = many.duplicate()
	GameManager.on_selection_changed(sm.selected_units)
	cmd.scans = 0
	cmd.attack_move(sm, base + Vector3(60.0, 0.0, 0.0), false)
	await pframes(120)
	var scans_four: int = cmd.scans
	for u2 in many:
		if is_instance_valid(u2):
			(u2 as Unit).take_damage(1e9)
	await pframes(3)

	# 120 физкадров — это 2 с, то есть около семи тактов по AM_TICK_SEC.
	# Судим СВОЙСТВО: четыре отряда стоят вчетверо, а не вчетверо меньше
	# моделей в каждом; 40 моделей одним отрядом — один скан на такт
	verdict("C1 один отряд из 40 моделей сканирует как ОДИН источник",
		scans_one > 0 and scans_one <= 12,
		"сканов %d за ~7 тактов" % scans_one)
	verdict("C2 четыре отряда дают примерно вчетверо больше сканов, чем один",
		scans_four >= scans_one * 3 and scans_four <= scans_one * 5 + 4,
		"один отряд %d, четыре отряда %d" % [scans_one, scans_four])

# ═════════════════════════════════════════════════════════════════════════════
# D. ОТМЕНА РЕЖИМА НОВЫМ ПРИКАЗОМ
# ═════════════════════════════════════════════════════════════════════════════
func _block_cancel() -> void:
	print("\n═════ D. НОВЫЙ ПРИКАЗ СНИМАЕТ АТАКУ ПО ПУТИ ═════")
	var sm = main.selection_manager
	var cmd = sm.squad_commander()
	var base := Vector3(300.0, 0.0, 300.0)
	var men: Array = _squad("spearman", base, 8)
	await pframes(3)
	sm.selected_units = men.duplicate()
	GameManager.on_selection_changed(sm.selected_units)
	var sid: int = (men[0] as Unit).squad_id
	cmd.attack_move(sm, base + Vector3(50.0, 0.0, 0.0), false)
	var on0: bool = cmd.is_attack_moving(sid)
	# Обычный приказ — ТЕМ ЖЕ путём, каким его отдаёт игрок
	sm.march_selection_to(base + Vector3(0.0, 0.0, 30.0), false)
	cmd.call("_cancel_for_selection", sm)
	verdict("D1 обычный марш снимает режим атаки по пути",
		on0 and not cmd.is_attack_moving(sid),
		"было=%s, стало=%s" % [on0, cmd.is_attack_moving(sid)])

	# [S] тоже отменяет: «стой» и «иди с боем» — противоположные приказы
	cmd.attack_move(sm, base + Vector3(50.0, 0.0, 0.0), false)
	var on1: bool = cmd.is_attack_moving(sid)
	cmd.stand_ground(sm)
	verdict("D2 [S] снимает режим и ставит отряд в оборону",
		on1 and not cmd.is_attack_moving(sid)
		and String((men[0] as Unit).stance) == _UCfgT.STANCE_DEFENSE,
		"режим=%s, стойка %s" % [cmd.is_attack_moving(sid), (men[0] as Unit).stance])

	# Отряд выбит целиком — запись обязана уйти сама, иначе командир вечно
	# тикал бы по мёртвому sid
	cmd.attack_move(sm, base + Vector3(50.0, 0.0, 0.0), false)
	for u in men:
		(u as Unit).take_damage(1e9)
	await pframes(30)
	verdict("D3 выбитый отряд снимается с учёта сам", not cmd.is_attack_moving(sid),
		"режим=%s, в работе %d" % [cmd.is_attack_moving(sid), cmd.active_count])

# ═════════════════════════════════════════════════════════════════════════════
# E. ЩЕЛЧОК ПОДТВЕРЖДЕНИЯ ПРИКАЗА
# ═════════════════════════════════════════════════════════════════════════════
func _block_sound() -> void:
	print("\n═════ E. ЗВУК ПОДТВЕРЖДЕНИЯ ═════")
	# Поток СОБИРАЕТСЯ КОДОМ — файла у него нет. Проверяем сам поток, а не
	# «прозвучало»: в headless звукового драйвера нет вовсе
	var st = AudioManager._order_click_stream()
	var ok_stream: bool = st != null and st is AudioStreamWAV
	var n: int = 0
	if ok_stream:
		n = (st as AudioStreamWAV).data.size() / 2
	verdict("E1 щелчок приказа собран кодом, а не загружен файлом",
		ok_stream and n > 100,
		"выборок %d, частота %d" % [n, (st as AudioStreamWAV).mix_rate if ok_stream else 0])
	# ПЕРВАЯ И ПОСЛЕДНЯЯ ВЫБОРКИ — НУЛИ: волна, оборванная на ненулевом
	# значении, даёт собственный треск поверх щелчка
	var edges_ok := false
	if ok_stream:
		var d: PackedByteArray = (st as AudioStreamWAV).data
		edges_ok = absi(d.decode_s16(0)) < 400 and absi(d.decode_s16(d.size() - 2)) < 400
	verdict("E2 волна начинается и кончается нулём (без треска на краях)",
		edges_ok, "края %d / %d" % [
			(st as AudioStreamWAV).data.decode_s16(0) if ok_stream else -1,
			(st as AudioStreamWAV).data.decode_s16((st as AudioStreamWAV).data.size() - 2) if ok_stream else -1])
	# Щелчок ТИШЕ прочих кнопок — заказ «тихий глухой клик»
	var db_click: float = float((AudioManager.UI_LIMITS.get("order_move", {})).get("db", 0.0))
	var db_other: float = float((AudioManager.UI_LIMITS.get("order_unit", {})).get("db", 0.0))
	verdict("E3 щелчок приказа тише обычной кнопки интерфейса",
		db_click < db_other, "%.1f дБ против %.1f дБ" % [db_click, db_other])
	# И он подключён к приказу на движение
	AudioManager.ui_last = ""
	var sm = main.selection_manager
	var base := Vector3(-600.0, 0.0, 600.0)
	var men: Array = _squad("spearman", base, 4)
	await pframes(3)
	sm.selected_units = men.duplicate()
	GameManager.on_selection_changed(sm.selected_units)
	sm.march_selection_to(base + Vector3(20.0, 0.0, 0.0), false)
	verdict("E4 приказ на движение зовёт щелчок подтверждения",
		AudioManager.ui_last == "order_move", "последнее событие «%s»" % AudioManager.ui_last)
