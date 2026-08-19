extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: РАЗВЕДКА ЧУЖИХ ПОСТРОЕК, ПАНЕЛЬ РЕСУРСОВ, ПАНЕЛЬ ЗАМКА, ТУЛТИПЫ
## ═══════════════════════════════════════════════════════════════════════════
##   A РАЗВЕДКА  — чужая база скрыта до разведки, потом остаётся как «последнее
##                 известное положение», а её войска под дымкой — нет
##   B РЕСУРСЫ   — инструмент и счётчик рабочих только в секции еды
##   C ЗАМОК     — панель строго фиксированного размера, очередь внутри бокса
##   D ТУЛТИПЫ   — окно встаёт над наведённой иконкой и не наезжает на панель
##
## ЧИСЛА ИЗ КОНСТАНТ HUD/конфига: стенд проверяет СВОЙСТВА (не разъезжается,
## помещается, центрировано), а не переписанные значения.

const _UCfg := preload("res://scripts/unit_stats_config.gd")

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

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

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

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	hud = main.hud
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 90000.0)
	await frames(3)

	await _a_scouting()
	await _b_resource_bar()
	await _c_castle_panel()
	await _d_tooltips()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 66), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== HUD5 TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. РАЗВЕДКА ЧУЖОЙ БАЗЫ
# ═════════════════════════════════════════════════════════════════════════════
func _a_scouting() -> void:
	print("\n═════ A. РАЗВЕДКА ═════")
	var fog = main.fog
	var e: Vector3 = main.ENEMY_BASE_ANCHOR

	# Вражеский замок ставит _spawn_enemy_base() при старте партии
	var foe_castle: Building = null
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if b is Castle and is_instance_valid(b):
			foe_castle = b
			break
	verdict("A1 вражеский замок на карте есть", foe_castle != null)
	if foe_castle == null:
		return

	fog.refresh()
	await frames(2)

	# A2 — до разведки он полностью скрыт
	verdict("A2 чужая база скрыта до разведки",
		not foe_castle.visible and not fog.is_seen(e.x, e.z),
		"видима=%s, разведано=%s" % [foe_castle.visible, fog.is_seen(e.x, e.z)])

	# A3 — и не ловит клики: невидимое здание не должно выделяться мышью
	verdict("A3 скрытая база не ловит клики выделения",
		foe_castle.collision_layer == 0,
		"слой столкновений=%d" % foe_castle.collision_layer)

	# Разведчик доходит до базы
	var scout := Spearman.new()
	scout.faction = Constants.FACTION_PLAYER
	main.world_add(scout)
	scout.global_position = Vector3(e.x, main.get_terrain_height(e.x, e.z), e.z)
	await pframes(2)
	fog.refresh()
	await frames(2)

	verdict("A4 разведчик открыл базу — она видна",
		foe_castle.visible and foe_castle.collision_layer != 0,
		"видима=%s, слой=%d" % [foe_castle.visible, foe_castle.collision_layer])

	# A5 — ГЛАВНОЕ: разведчик ушёл, база ОСТАЛАСЬ как последнее известное
	# положение (в отличие от бойцов, которые снова прячутся)
	var foe_unit := Spearman.new()
	foe_unit.faction = Constants.FACTION_ENEMY
	main.world_add(foe_unit)
	foe_unit.global_position = Vector3(e.x + 2.0,
		main.get_terrain_height(e.x + 2.0, e.z), e.z)
	await pframes(2)
	fog.refresh()
	await frames(6)
	var foe_seen_lit: bool = GameManager.far_units.is_registered(foe_unit)

	scout.queue_free()
	await pframes(3)
	fog.refresh()
	# ЖДЁМ ДОЛЬШЕ ЗАДЕРЖКИ ГАШЕНИЯ. Чужой боец гаснет не в тот же кадр, а через
	# Unit.FOG_HIDE_GRACE: без задержки бойцы на кромке видимости дребезжали с
	# частотой пересчёта маски («армия мерцает», см. qa_fog D6). Проверка ниже
	# про «под дымкой войск не видно», а не про скорость гашения
	# ФИЗИЧЕСКИЕ кадры: обход, который будит спящих чужих бойцов, идёт
	# в физтике, а при Engine.max_fps = 0 отрисовка обгоняет его в разы
	await pframes(int(Unit.FOG_HIDE_GRACE * 60.0) + 40)

	verdict("A5 разведчик ушёл — база осталась видна как последнее известное",
		foe_castle.visible and fog.is_seen(e.x, e.z) and not fog.is_lit(e.x, e.z),
		"видима=%s, разведано=%s, просматривается=%s" % [
			foe_castle.visible, fog.is_seen(e.x, e.z), fog.is_lit(e.x, e.z)])

	# A6 — а вот ВОЙСКА под дымкой скрыты: это и есть разница между «помню
	# здание» и «вижу, что там происходит»
	verdict("A6 войска врага под дымкой скрыты, хотя база видна",
		foe_seen_lit and not GameManager.far_units.is_registered(foe_unit),
		"при разведчике рисовался=%s, после ухода=%s" % [
			foe_seen_lit, GameManager.far_units.is_registered(foe_unit)])

	# A7 — новое здание врага в уже разведанной точке видно сразу, а в
	# неразведанной — нет
	var far_spot := Vector3(e.x - 60.0, 0.0, e.z - 30.0)
	var b2 := Barracks.new()
	b2.faction = Constants.FACTION_ENEMY
	main.world_add(b2)
	b2.global_position = Vector3(far_spot.x,
		main.get_terrain_height(far_spot.x, far_spot.z), far_spot.z)
	await frames(3)
	verdict("A7 новая постройка врага в неразведанном месте скрыта сразу",
		not b2.visible and not fog.is_seen(far_spot.x, far_spot.z),
		"видима=%s, разведано=%s" % [b2.visible, fog.is_seen(far_spot.x, far_spot.z)])

	foe_unit.queue_free()
	b2.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. ПАНЕЛЬ РЕСУРСОВ
# ═════════════════════════════════════════════════════════════════════════════
func _b_resource_bar() -> void:
	print("\n═════ B. ПАНЕЛЬ РЕСУРСОВ ═════")

	# ── B1-B3 ПЕРЕВЁРНУТЫ: ВЛАДЕЛЕЦ ВЕРНУЛ СЧЁТЧИК НА КАЖДЫЙ РЕСУРС ──────────
	# Раньше эти три проверки требовали ровно обратного: глиф и счётчик живут
	# в ОДНОЙ секции (еда), а из дерева убраны. Требование отменено — игрок
	# должен видеть, сколько рабочих копает КАЖДЫЙ ресурс, иначе распределить
	# артель по дереву/камню/золоту можно только на память. Смысл проверок
	# сохранён: они по-прежнему стерегут СОСТАВ панели, просто состав другой
	var tool_keys: Array = hud._res_tool_labels.keys()
	verdict("B1 глиф инструмента есть в КАЖДОЙ секции",
		tool_keys.size() == HUD.RES_DEFS.size(),
		"секции с инструментом: %d из %d" % [tool_keys.size(), HUD.RES_DEFS.size()])

	# B2 — ИНСТРУМЕНТ СВОЙ У КАЖДОГО РЕСУРСА, и у дерева это ТОПОР.
	# Проверка требовала кирки на лесе — по лесу это просто неправда, дерево
	# рубят топором, и владелец попросил заменить глиф. Числа не хардкодим:
	# ждём ровно то, что стоит в конфиге панели (HUD.RES_TOOL_GLYPHS), и
	# отдельно — что у дерева и у камня глифы РАЗНЫЕ, иначе замена ничего не
	# дала бы (см. «Config is the source of truth» в CLAUDE.md)
	var wood_tool: Label = hud._res_tool_labels.get(Constants.RESOURCE_WOOD)
	var stone_tool: Label = hud._res_tool_labels.get(Constants.RESOURCE_STONE)
	var want_wood: String = String(HUD.RES_TOOL_GLYPHS.get(Constants.RESOURCE_WOOD, ""))
	var want_stone: String = String(HUD.RES_TOOL_GLYPHS.get(Constants.RESOURCE_STONE, ""))
	verdict("B2 у дерева свой инструмент (топор), не такой же, как у камня",
		wood_tool != null and stone_tool != null
			and wood_tool.text == want_wood and stone_tool.text == want_stone
			and want_wood != want_stone,
		"дерево «%s», камень «%s»" % [
			wood_tool.text if wood_tool != null else "—",
			stone_tool.text if stone_tool != null else "—"])

	# B3 — счётчик рабочих тоже в каждой секции
	var wk_keys: Array = hud._res_workers_labels.keys()
	verdict("B3 счётчик рабочих есть в КАЖДОЙ секции",
		wk_keys.size() == HUD.RES_DEFS.size(),
		"секции со счётчиком: %d из %d" % [wk_keys.size(), HUD.RES_DEFS.size()])

	# B4 — габарит с хвостом ШИРЕ базового ровно на место под инструмент и счётчик
	verdict("B4 габарит с хвостом шире базового",
		HUD.RES_CARD_SIZE_WORKERS.x > HUD.RES_CARD_SIZE.x,
		"с хвостом %.0f против базового %.0f" % [
			HUD.RES_CARD_SIZE_WORKERS.x, HUD.RES_CARD_SIZE.x])

	# B5 — БАЗОВЫЙ габарит (без хвоста) по-прежнему обтягивает иконку, число и
	# приток. Хвост теперь у всех секций, но он ДОБАВЛЯЕТСЯ к базе, а не
	# растворяется в ней: пустоты внутри секции быть не должно
	verdict("B5 базовый габарит не держит пустое место под инструмент",
		HUD.RES_CARD_SIZE.x <= HUD.RES_ICON_DISPLAY + HUD.RES_AMOUNT_W
			+ HUD.RES_INCOME_W + float(HUD.RES_INNER_SEP) * 2.0 + 0.01,
		"ширина базовой секции %.0f" % HUD.RES_CARD_SIZE.x)

	# B5б — ХВОСТ ВСЕХ СЕКЦИЙ ЗАНЯТ, А НЕ ЗАРЕЗЕРВИРОВАН ПУСТЫМ.
	# Это то самое, из-за чего хвост когда-то и свели в одну секцию: место под
	# него держалось в четырёх, а рисовалось в одной. Теперь у добывающих секций
	# счётчик виден ВСЕГДА (включая ноль), поэтому пустого места нет ни в одной
	var reserved_empty: Array = []
	for rd in HUD.RES_DEFS:
		var k: int = int(rd["key"])
		if k == HUD.RES_WORKER_SECTION:
			continue          # общий счёт гаснет при нуле рабочих — это норма
		var wl0: Label = hud._res_workers_labels.get(k)
		if wl0 == null or not wl0.visible:
			reserved_empty.append(k)
	verdict("B5б у добывающих секций хвост занят, а не пуст",
		reserved_empty.is_empty(), "пустых хвостов: %s" % str(reserved_empty))

	# B6 — счётчик показывает ВСЕХ рабочих игрока, а не «рабочих на еде»
	# (на еде их не бывает вовсе — еду дают Домики)
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-40.0, 0.0, 40.0)
	await frames(2)
	var made: Array = []
	for i in range(3):
		var w := Worker.new()
		w.faction = Constants.FACTION_PLAYER
		main.world_add(w)
		w.global_position = Vector3(-40.0 + float(i), 0.0, 44.0)
		made.append(w)
	await pframes(3)
	for i in range(140):
		hud._update_resource_income(0.1)
	await frames(2)
	var wl: Label = hud._res_workers_labels.get(Constants.RESOURCE_FOOD)
	var total: int = hud._total_player_workers()
	# ── СЕКЦИЯ ЕДЫ БОЛЬШЕ НЕ ИСКЛЮЧЕНИЕ (заказ владельца, разворот) ──────────
	# Она показывала ОБЩЕЕ число рабочих — потому что еду в этой игре не
	# добывают. Владелец попросил обратное: пусть стоит честный ноль, пока еду
	# дают Домики. Проверяем именно новое свойство — что все четыре секции
	# отвечают на ОДИН вопрос, и на еде это ноль при живых рабочих на других
	# ресурсах. Существование самих рабочих проверяется отдельно, иначе «ноль»
	# прошёл бы и на пустой карте
	verdict("B6 в секции еды честный ноль: еду добывают Домики, а не рабочие",
		wl != null and wl.visible and wl.text == "0" and total >= 3
			and HUD.RES_WORKER_SECTION < 0,
		"на плашке «%s», всего рабочих %d" % [
			wl.text if wl != null else "—", total])
	for w in made:
		w.queue_free()
	castle.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. ПАНЕЛЬ ЗАМКА
# ═════════════════════════════════════════════════════════════════════════════
func _c_castle_panel() -> void:
	print("\n═════ C. ПАНЕЛЬ ЗАМКА ═════")
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-70.0, 0.0, 70.0)
	await frames(3)

	hud.show_selection([castle])
	await frames(3)
	var w0: float = hud._bottom_panel.size.x
	var h0: float = hud._bottom_panel.size.y

	# C1 — размер ровно тот, что задан константами
	verdict("C1 панель Замка строго фиксированного размера",
		absf(w0 - HUD.CASTLE_PANEL_W) < 0.5 and absf(h0 - HUD.CASTLE_PANEL_H) < 0.5,
		"панель %.0f×%.0f, в конфиге %.0f×%.0f" % [
			w0, h0, HUD.CASTLE_PANEL_W, HUD.CASTLE_PANEL_H])

	# C2 — ЗАКАЗЫ НЕ ДВИГАЮТ ПАНЕЛЬ (главная жалоба)
	var sizes: Array = []
	for i in range(9):
		castle.train_from_config("worker")
		hud.show_selection([castle])
		await frames(2)
		sizes.append(Vector2(hud._bottom_panel.size.x, hud._bottom_panel.size.y))
	var moved := false
	for s in sizes:
		if absf((s as Vector2).x - w0) > 0.5 or absf((s as Vector2).y - h0) > 0.5:
			moved = true
	verdict("C2 панель не разъезжается при добавлении заказов", not moved,
		"после 9 заказов: %s (было %.0f×%.0f)" % [
			str(sizes[sizes.size() - 1]), w0, h0])

	# C3 — все иконки очереди СТРОГО ВНУТРИ жёлтого бокса
	var frame: Control = hud._queue_frame
	var fr: Rect2 = frame.get_global_rect()
	var outside: Array = []
	var n_cells := 0
	for c in hud._queue_box.get_children():
		var b := c as Control
		if b == null:
			continue
		n_cells += 1
		var br: Rect2 = b.get_global_rect()
		if br.position.x < fr.position.x - 0.5 or br.position.y < fr.position.y - 0.5 \
				or br.position.x + br.size.x > fr.position.x + fr.size.x + 0.5 \
				or br.position.y + br.size.y > fr.position.y + fr.size.y + 0.5:
			outside.append(str(br))
	verdict("C3 иконки очереди строго внутри жёлтого бокса",
		n_cells > 0 and outside.is_empty(),
		"ячеек %d, вылезло %d" % [n_cells, outside.size()])

	# ── C4-C6 ПЕРЕСЧИТАНЫ ПОД ДВУХРЯДНУЮ ЗОНУ ────────────────────────────────
	# Очередь стала сеткой 2×5 (заказ владельца: 5 сверху, 5 снизу) — прежние
	# три проверки считали ОДИН ряд и после переноса на вторую строку меряли
	# ерунду: «зазор» между последней ячейкой верхнего ряда и первой нижнего
	# выходил отрицательным (−112 px), а ширина «ряда» из максимума заказов —
	# вдвое больше зоны. Смысл проверок прежний: равные интервалы, честное
	# уменьшение при переполнении и «всё внутри зоны»

	# C4 — интервалы одинаковые ВНУТРИ КАЖДОГО РЯДА (переход на новый ряд —
	# не зазор, а перенос строки, и в сравнение он не входит)
	var gaps: Array = []
	var prev: Control = null
	for c in hud._queue_box.get_children():
		var b := c as Control
		if b == null:
			continue
		if prev != null and absf(b.position.y - prev.position.y) < 0.51:
			gaps.append(b.position.x - (prev.position.x + prev.size.x))
		prev = b
	var even := true
	for g in gaps:
		if absf(float(g) - float(gaps[0])) > 0.51:
			even = false
	verdict("C4 интервалы между иконками очереди одинаковые",
		gaps.size() > 0 and even, "зазоры: %s" % str(gaps.slice(0, 5)))

	# C5 — при ПЕРЕПОЛНЕНИИ зоны иконки уменьшаются. Порог сместился: девять
	# заказов в два ряда помещаются полным размером — ради этого сетку и делали
	# двухрядной. Мельчать они обязаны, когда рядов уже не хватает
	var side_many: float = hud._queue_cell_side(HUD.QUEUE_ORDER_MAX)
	var side_one: float  = hud._queue_cell_side(1)
	verdict("C5 при переполнении зоны иконки пропорционально уменьшаются",
		side_many < side_one and side_many >= HUD.QUEUE_CELL_MIN - 0.01,
		"1 заказ → %.1f px, %d заказов → %.1f px" % [
			side_one, HUD.QUEUE_ORDER_MAX, side_many])

	# C6 — сетка из максимума заказов влезает в зону по ширине.
	# Ширина считается по ЧИСЛУ КОЛОНОК (_queue_grid_cols), а не по числу
	# заказов: при двух рядах это разные величины
	var n_max: int = HUD.QUEUE_ORDER_MAX
	var cols_max: int = hud._queue_grid_cols(n_max)
	var row_w: float = float(cols_max) * hud._queue_cell_side(n_max) \
		+ float(cols_max - 1) * float(HUD.QUEUE_CELL_GAP)
	verdict("C6 даже максимум заказов укладывается в ширину бокса",
		row_w <= HUD.QUEUE_BOX_INNER.x + 0.01,
		"%d заказов = %.1f px при боксе %.0f" % [n_max, row_w, HUD.QUEUE_BOX_INNER.x])

	# C7 — подпись «Замок N/N HP» ВНУТРИ границ панели
	var cap: Control = hud._castle_caption
	var pr: Rect2 = hud._bottom_panel.get_global_rect()
	var cr: Rect2 = cap.get_global_rect() if cap != null else Rect2()
	verdict("C7 подпись Замка внутри границ панели",
		cap != null and cap.visible
			and cr.position.y >= pr.position.y - 0.5
			and cr.position.y + cr.size.y <= pr.position.y + pr.size.y + 0.5,
		"подпись y=%.0f..%.0f, панель y=%.0f..%.0f" % [
			cr.position.y, cr.position.y + cr.size.y,
			pr.position.y, pr.position.y + pr.size.y])

	# C8 — иконка Замка увеличена относительно обычного портрета
	verdict("C8 иконка Замка крупнее обычного портрета",
		HUD.CASTLE_PORTRAIT_W > float(HUD.PORTRAIT_W),
		"Замок %.0f против обычного %d" % [HUD.CASTLE_PORTRAIT_W, HUD.PORTRAIT_W])

	# ── C8б-C8е: ВЁРСТКА ПАНЕЛИ ЗАМКА ПО ЗАКАЗУ ВЛАДЕЛЬЦА ───────────────────
	# Числа не выдуманы стендом: каждое сверяется с константой HUD, чтобы
	# проверка не разошлась с конфигом при следующей правке (CLAUDE.md,
	# «Config is the source of truth»)

	# C8б — ПОДПИСЬ НАД ИКОНКОЙ, А НЕ ПОВЕРХ НЕЁ. Иконка опущена к нижней
	# кромке (SIZE_SHRINK_END), полоса сверху отдана строке «Замок N/N HP»
	var pw_r: Rect2 = hud._portrait_wrap.get_global_rect()
	verdict("C8б иконка Замка ниже подписи, они не пересекаются",
		cap != null and cr.position.y + cr.size.y <= pw_r.position.y + 0.5,
		"низ подписи %.0f, верх иконки %.0f" % [
			cr.position.y + cr.size.y, pw_r.position.y])

	# C8в — КНОПКИ НАЙМА ПО ВЕРТИКАЛЬНОМУ ЦЕНТРУ ПАНЕЛИ (были «задраны вверх»)
	var bc_r: Rect2 = hud.button_container.get_global_rect()
	var btn_mid: float = bc_r.position.y + bc_r.size.y * 0.5
	var panel_mid: float = pr.position.y + pr.size.y * 0.5
	verdict("C8в кнопки найма отцентрованы по высоте панели",
		absf(btn_mid - panel_mid) <= 2.0,
		"центр кнопок %.1f, центр панели %.1f" % [btn_mid, panel_mid])

	# C8г — ОТСТУП ОТ ПРАВОГО КРАЯ РОВНО CASTLE_BTN_RIGHT_PAD
	var right_gap: float = (pr.position.x + pr.size.x) - (bc_r.position.x + bc_r.size.x)
	verdict("C8г кнопки найма отступают от правого края на заданные px",
		absf(right_gap - HUD.CASTLE_BTN_RIGHT_PAD) <= 2.5,
		"отступ %.1f px, в конфиге %.0f" % [right_gap, HUD.CASTLE_BTN_RIGHT_PAD])

	# C8д — ОЧЕРЕДЬ В ДВА РЯДА: при девяти заказах ячейки стоят на ДВУХ разных
	# высотах (пять сверху, четыре снизу), а не вытянуты в одну строку
	var rows_seen: Array = []
	for c in hud._queue_box.get_children():
		var b2 := c as Control
		if b2 == null:
			continue
		var y := snappedf(b2.position.y, 1.0)
		if not (y in rows_seen):
			rows_seen.append(y)
	verdict("C8д очередь заказов выложена в два ряда",
		rows_seen.size() == HUD.QUEUE_ORDER_ROWS,
		"рядов %d, ожидали %d (заказов %d)" % [
			rows_seen.size(), HUD.QUEUE_ORDER_ROWS, hud._queue_box.get_child_count()])

	# C8е — ЖЁЛТОЙ РАМКИ БОЛЬШЕ НЕТ. Контейнер зоны остался (он держит габарит),
	# но не рисует ни рамки, ни фона — владелец просил убрать её целиком
	var qsb := hud._queue_frame.get_theme_stylebox("panel") as StyleBoxFlat
	var frame_gone: bool = qsb != null and qsb.border_width_top == 0 \
		and qsb.border_width_bottom == 0 and qsb.border_width_left == 0 \
		and qsb.border_width_right == 0 and not qsb.draw_center
	verdict("C8е жёлтая рамка вокруг очереди убрана", frame_gone,
		"рамка %d px, фон рисуется: %s" % [
			qsb.border_width_top if qsb != null else -1,
			str(qsb.draw_center) if qsb != null else "?"])

	# C9 — жёлтая цифра заказов в НИЖНЕМ ПРАВОМ углу иконки найма
	var badge: Label = null
	var host: Control = null
	for c in hud.button_container.get_children():
		var b := c as Button
		if b == null:
			continue
		for ch in b.get_children():
			var l := ch as Label
			if l != null and l.visible and l.text.strip_edges() != "":
				badge = l
				host = b
	var in_corner := false
	if badge != null and host != null:
		var brr: Rect2 = badge.get_global_rect()
		var hrr: Rect2 = host.get_global_rect()
		# Правый нижний: правый край цифры у правого края кнопки, нижний — у нижнего
		in_corner = (hrr.position.x + hrr.size.x) - (brr.position.x + brr.size.x) <= 4.0 \
			and (hrr.position.y + hrr.size.y) - (brr.position.y + brr.size.y) <= 4.0 \
			and brr.position.x >= hrr.position.x - 0.5 \
			and brr.position.y + brr.size.y <= hrr.position.y + hrr.size.y + 0.5
	verdict("C9 счётчик заказов в нижнем правом углу иконки найма",
		badge != null and in_corner,
		"цифра «%s», в углу=%s" % [badge.text if badge != null else "—", in_corner])

	castle.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# D. ТУЛТИПЫ
# ═════════════════════════════════════════════════════════════════════════════
func _d_tooltips() -> void:
	print("\n═════ D. ТУЛТИПЫ ═════")
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-90.0, 0.0, 90.0)
	await frames(3)
	hud.show_selection([castle])
	await frames(3)

	# Берём ВТОРУЮ кнопку найма: у первой центр близко к краю экрана, и зажим
	# по краю мог бы замаскировать ошибку центрирования
	var btns: Array = []
	for c in hud.button_container.get_children():
		if c is Button:
			btns.append(c)
	verdict("D0 кнопки найма на панели есть", btns.size() >= 2,
		"кнопок %d" % btns.size())
	if btns.size() < 2:
		castle.queue_free()
		return
	var btn: Button = btns[1]

	btn.emit_signal("mouse_entered")
	await frames(6)
	var tip: Control = hud._stat_card
	verdict("D1 окно описания появилось", tip != null and is_instance_valid(tip))
	if tip == null or not is_instance_valid(tip):
		castle.queue_free()
		return

	var tr: Rect2 = tip.get_global_rect()
	var br: Rect2 = btn.get_global_rect()
	var pr: Rect2 = hud._bottom_panel.get_global_rect()

	# D2 — СТРОГО НАД кнопкой: нижняя кромка окна выше верха кнопки
	verdict("D2 окно стоит НАД кнопкой, не наезжая на неё",
		tr.position.y + tr.size.y <= br.position.y + 0.5,
		"низ окна %.0f, верх кнопки %.0f" % [tr.position.y + tr.size.y, br.position.y])

	# D3 — и над панелью целиком
	verdict("D3 окно не наезжает на нижнюю панель",
		tr.position.y + tr.size.y <= pr.position.y + 0.5,
		"низ окна %.0f, верх панели %.0f" % [tr.position.y + tr.size.y, pr.position.y])

	# D4 — центр окна совпадает с центром КНОПКИ (а не с краем экрана)
	var tip_cx: float = tr.position.x + tr.size.x * 0.5
	var btn_cx: float = br.position.x + br.size.x * 0.5
	verdict("D4 окно отцентровано по наведённой иконке",
		absf(tip_cx - btn_cx) < 2.0,
		"центр окна %.0f, центр кнопки %.0f" % [tip_cx, btn_cx])

	# D5 — окно целиком на экране
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	verdict("D5 окно целиком помещается на экран",
		tr.position.x >= -0.5 and tr.position.y >= -0.5
			and tr.position.x + tr.size.x <= vp.x + 0.5,
		"окно x=%.0f..%.0f y=%.0f при экране %.0f×%.0f" % [
			tr.position.x, tr.position.x + tr.size.x, tr.position.y, vp.x, vp.y])

	# D6 — окно РАСТЁТ ВВЕРХ: нижняя кромка стоит на месте, верхняя уходит выше.
	# ОБА окна строим синтетически, коротким и длинным. Сравнивать с настоящей
	# карточкой найма нельзя: она сама по себе высокая (статы + описание + цена),
	# и «длинный» набор из семи коротких строк оказывался НИЖЕ неё — проверка
	# падала, хотя механика работала (низ у обеих совпадал до пикселя)
	btn.emit_signal("mouse_exited")
	hud._hide_card()
	await frames(2)
	hud._show_card(btn, {"title": "Коротко", "lines": ["одна строка"]})
	await frames(6)
	var short_tip: Control = hud._stat_card
	var bottom_short: float = 0.0
	var h_short: float = 0.0
	if short_tip != null and is_instance_valid(short_tip):
		var ts: Rect2 = short_tip.get_global_rect()
		bottom_short = ts.position.y + ts.size.y
		h_short = ts.size.y

	hud._hide_card()
	await frames(2)
	hud._show_card(btn, {"title": "Длинный", "lines": [
		"строка раз", "строка два", "строка три", "строка четыре",
		"строка пять", "строка шесть", "строка семь", "строка восемь"]})
	await frames(6)
	var tip2: Control = hud._stat_card
	var grew_up := false
	var bottom_long: float = 0.0
	var h_long: float = 0.0
	if tip2 != null and is_instance_valid(tip2):
		var t2: Rect2 = tip2.get_global_rect()
		bottom_long = t2.position.y + t2.size.y
		h_long = t2.size.y
		grew_up = absf(bottom_long - bottom_short) < 2.0 and h_long > h_short
	verdict("D6 длинный текст растит окно ВВЕРХ, низ остаётся на месте", grew_up,
		"низ %.0f→%.0f, высота %.0f→%.0f" % [
			bottom_short, bottom_long, h_short, h_long])

	castle.queue_free()
	await pframes(2)
