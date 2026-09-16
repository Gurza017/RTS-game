extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: КЛАВИШИ 1/2/3 ПРИ РАСТЯГЕ ПКМ — ШИРОКИЙ ФРОНТ, КОРОБОЧКА, ИНВЕРТОР
## (спринт 17, блок 1)
## ═══════════════════════════════════════════════════════════════════════════
##   A — [1] широкий фронт: раскладка по линии, отряды секциями, глубина мала;
##   B — [2] коробочка: каждый отряд не глубже DEEP_ROWS шеренг, блоки
##       переносятся на следующий ряд сетки, когда не влезают в линию;
##   C — [3] инвертор: мечники впереди, копейщики сзади; повтор — обратно;
##   D — клавиши вне растяга остаются горячими группами; превью
##       перерисовывается по клавише тем же кадром; приказ отдаётся тем же
##       режимом, что показывало превью.
## Запуск: godot --headless --path . res://qa_formation_keys/Test.tscn

const _Formations := preload("res://scripts/Formations.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(180.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 180 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

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
	print("\n═════ ИТОГ qa_formation_keys: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _squad(uid: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, uid)
	var men: Array = []
	for i in range(n):
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var p := at + Vector3(float(i % 5) * 0.6, 0.0, float(i / 5) * 0.6)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

## Отпустить ПКМ ТЕМ ЖЕ ПУТЁМ, каким это делает игра: событие в
## `_unhandled_input`. Дёргать поля напрямую нельзя — именно в обработчике
## отпускания и стоял сброс режима, который проверяется
func _release_rmb(_world_at: Vector3) -> void:
	var sm = main.selection_manager
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = false
	# Дальше порога протяжки — иначе отпускание прочтётся как одиночный клик
	ev.position = sm._rmb_screen_start + Vector2(400, 0)
	sm._unhandled_input(ev)

func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	main.selection_manager._unhandled_input(ev)

## Габарит раскладки вдоль линии (ширина) и поперёк (глубина)
func _extent(slots: Array, line_dir: Vector3) -> Vector2:
	if slots.is_empty():
		return Vector2.ZERO
	var facing := Vector3(line_dir.z, 0.0, -line_dir.x)
	var w_lo := INF; var w_hi := -INF; var d_lo := INF; var d_hi := -INF
	for s in slots:
		var v: Vector3 = s
		w_lo = minf(w_lo, v.dot(line_dir)); w_hi = maxf(w_hi, v.dot(line_dir))
		d_lo = minf(d_lo, v.dot(facing));   d_hi = maxf(d_hi, v.dot(facing))
	return Vector2(w_hi - w_lo, d_hi - d_lo)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	await pframes(4)
	var sm = main.selection_manager
	var p0 := Vector3(-1200.0, 0.0, -1200.0)
	# Три отряда копейщиков по 20 (однотипное выделение)
	var all: Array = []
	for k in range(3):
		all.append_array(_squad("spearman", p0 + Vector3(float(k) * 8.0, 0.0, 0.0), 20))
	await pframes(4)
	sm.selected_units = all.duplicate()
	var a := p0 + Vector3(-5.0, 0.0, 30.0)
	var b := p0 + Vector3(25.0, 0.0, 30.0)
	var line_dir := (b - a).normalized()

	print("\n═════ A. [1] ШИРОКИЙ ФРОНТ ═════")
	sm.formation_mode = sm.FORM_DEEP
	sm.formation_front = 1
	# Растяг: нажатие ПКМ и движение дальше порога
	sm._rmb_down = true
	sm._rmb_dragging = true
	sm._rmb_press_over_ui = false
	sm._rmb_world_start = a
	sm._fp_mouse = Vector2(300, 300)
	sm._rmb_screen_start = Vector2(100, 300)
	_key(KEY_1)
	verdict("A1 [1] при растяге переключает режим на широкий фронт", sm.formation_mode == sm.FORM_WIDE)
	var wide: Dictionary = sm._mono_formation_slots(a, b, all)
	var ew: Vector2 = _extent(wide["slots"], line_dir)
	print("  широкий фронт: ширина %.1f м, глубина %.1f м, мест %d" % [ew.x, ew.y, (wide["slots"] as Array).size()])
	verdict("A2 все 60 получили место", (wide["slots"] as Array).size() == 60)
	verdict("A3 ширина строя — почти вся линия (30 м)", ew.x >= 24.0, "%.1f м" % ew.x)
	verdict("A4 глубина мала: не больше двух шеренг", ew.y <= sm.ROW_DEPTH * 1.5 + 0.01, "%.2f м" % ew.y)

	print("\n═════ B. [2] КОРОБОЧКА ═════")
	_key(KEY_2)
	verdict("B1 [2] переключает на коробочку", sm.formation_mode == sm.FORM_DEEP)
	# ── СПРИНТ 19 (письмо 9): коробочка [2] — ВСЕМ родам войск, без условий ──
	# (разворот хотфикса спринта 18, где её давали только копейщикам со
	# «Стеной копий»). Без исследования [2] обязана дать глубокий строй
	var deep0: Dictionary = sm._mono_formation_slots(a, b, all)
	var ed0: Vector2 = _extent(deep0["slots"], line_dir)
	verdict("B0 без изученной «Стены копий» [2] всё равно коробочка (глубина %.2f > широкого %.2f)" % [ed0.y, ew.y],
		ed0.y > ew.y + sm.ROW_DEPTH * 0.5)
	GameManager.finish_research(Constants.FACTION_PLAYER, "spearman_1d")
	verdict("B0б после исследования право на стену есть у всех трёх отрядов",
		GameManager.spear_wall_ready((all[0] as Unit).squad_id) and GameManager.spear_wall_ready((all[59] as Unit).squad_id))
	var deep: Dictionary = sm._mono_formation_slots(a, b, all)
	var ed: Vector2 = _extent(deep["slots"], line_dir)
	var max_row := 0
	for r in deep["rows"]:
		max_row = maxi(max_row, int(r))
	print("  коробочка: ширина %.1f м, глубина %.1f м, шеренг в блоке %d" % [ed.x, ed.y, max_row + 1])
	verdict("B2 все 60 получили место", (deep["slots"] as Array).size() == 60)
	verdict("B3 отряд стоит в DEEP_ROWS шеренги, не в одну", max_row + 1 == sm.DEEP_ROWS,
		"шеренг %d при заказанных %d" % [max_row + 1, sm.DEEP_ROWS])
	verdict("B4 коробочка глубже широкого фронта", ed.y > ew.y + sm.ROW_DEPTH * 0.5, "%.2f против %.2f м" % [ed.y, ew.y])
	verdict("B5 и уже его по фронту", ed.x < ew.x, "%.1f против %.1f м" % [ed.x, ew.x])
	# Короткая линия — блоки переносятся во второй ряд сетки
	var b_short := a + line_dir * 9.0
	var deep2: Dictionary = sm._mono_formation_slots(a, b_short, all)
	var ed2: Vector2 = _extent(deep2["slots"], line_dir)
	print("  короткая линия 9 м: ширина %.1f м, глубина %.1f м" % [ed2.x, ed2.y])
	verdict("B6 на короткой линии блоки переносятся в следующий ряд (сетка)",
		ed2.y > ed.y + sm.ROW_DEPTH and ed2.x < ed.x, "глубина %.1f против %.1f м" % [ed2.y, ed.y])
	# Ширина по ЦЕНТРАМ мест: у блока в 7 колонн это 6 интервалов
	verdict("B7 но ширина не уже одного блока", ed2.x >= 6.0 * sm.UNIT_SPACING - 0.01, "%.1f м" % ed2.x)

	print("\n═════ C. [3] АВАНГАРД ПО КРУГУ ═════")
	# Смешанное выделение: копейщики + лучники + мечники + монах
	var mixed: Array = []
	mixed.append_array(_squad("spearman", p0 + Vector3(0.0, 0.0, 60.0), 12))
	mixed.append_array(_squad("archer", p0 + Vector3(10.0, 0.0, 60.0), 8))
	mixed.append_array(_squad("warrior", p0 + Vector3(20.0, 0.0, 60.0), 8))
	mixed.append_array(_squad("monk", p0 + Vector3(30.0, 0.0, 60.0), 1))
	await pframes(3)
	sm.selected_units = mixed.duplicate()
	sm.formation_front = 0
	sm.formation_mode = sm.FORM_WIDE
	var a2 := p0 + Vector3(0.0, 0.0, 90.0)
	var b2 := p0 + Vector3(30.0, 0.0, 90.0)
	var facing := Vector3(line_dir.z, 0.0, -line_dir.x)
	var plan_a: Dictionary = sm._layered_formation_slots(a2, b2, mixed)
	verdict("C0 всем нашлось место в эшелонах", (plan_a["slots"] as Array).size() == mixed.size(),
		"%d из %d" % [(plan_a["slots"] as Array).size(), mixed.size()])
	var front_a: String = _front_type(plan_a, facing)
	var back_a: String = _back_type(plan_a, facing)
	verdict("C1 режим А: копейщики впереди, монахи сзади", front_a == "spearman" and back_a == "monk",
		"впереди %s, сзади %s" % [front_a, back_a])
	# Спринт 19: [3] крутит авангард по кругу — копейщики → мечники → лучники
	_key(KEY_3)
	verdict("C2 первое [3] — мечники впереди", sm.formation_front == 1)
	var plan_b: Dictionary = sm._layered_formation_slots(a2, b2, mixed)
	var front_b: String = _front_type(plan_b, facing)
	var order_b: Array = _echelon_order(plan_b, facing)
	verdict("C3 порядок: мечники, лучники, копейщики, монахи",
		order_b == ["warrior", "archer", "spearman", "monk"], str(order_b))
	verdict("C3б впереди строя — мечник", front_b == "warrior", front_b)
	_key(KEY_3)
	verdict("C4 второе [3] — лучники впереди", sm.formation_front == 2)
	var plan_c: Dictionary = sm._layered_formation_slots(a2, b2, mixed)
	verdict("C5 порядок: лучники, копейщики, мечники, монахи",
		_echelon_order(plan_c, facing) == ["archer", "spearman", "warrior", "monk"], str(_echelon_order(plan_c, facing)))
	_key(KEY_3)
	verdict("C5б третье [3] — снова копейщики впереди (круг замкнулся)",
		sm.formation_front == 0 and _echelon_order(sm._layered_formation_slots(a2, b2, mixed), facing) == ["spearman", "archer", "warrior", "monk"])
	# Круг поверх коробочки
	_key(KEY_2)
	_key(KEY_3)
	var plan_d: Dictionary = sm._layered_formation_slots(a2, b2, mixed)
	verdict("C6 [3] действует и на коробочку (мечники впереди)",
		sm.formation_mode == sm.FORM_DEEP and _front_type(plan_d, facing) == "warrior")
	verdict("C6б в коробочке все получили место", (plan_d["slots"] as Array).size() == mixed.size())
	# ── СПРИНТ 19: коробочка — ВСЕМ эшелонам смешанного выделения ──────────
	sm.formation_front = 0
	sm.formation_mode = sm.FORM_WIDE
	var plan_w: Dictionary = sm._layered_formation_slots(a2, b2, mixed)
	sm.formation_mode = sm.FORM_DEEP
	var plan_x: Dictionary = sm._layered_formation_slots(a2, b2, mixed)
	var ok_rows := true
	var sp_rows := 0
	var other_rows_w := 0
	var other_rows_d := 0
	for i in range((plan_x["flat"] as Array).size()):
		var ux := plan_x["flat"][i] as Unit
		var kind: String = GameManager.squad_type(ux.squad_id)
		if kind == "spearman":
			sp_rows = maxi(sp_rows, int(plan_x["rows"][i]))
		else:
			other_rows_d = maxi(other_rows_d, int(plan_x["rows"][i]))
	for j in range((plan_w["flat"] as Array).size()):
		var uw := plan_w["flat"][j] as Unit
		if GameManager.squad_type(uw.squad_id) != "spearman":
			other_rows_w = maxi(other_rows_w, int(plan_w["rows"][j]))
	# Под [2] и копейщики (12 → 3 шеренги), и лучники с мечниками (8 → 3 шеренги)
	# стоят коробочкой; под [1] прочие лежали в одну-две шеренги
	ok_rows = sp_rows + 1 == sm.DEEP_ROWS and other_rows_d + 1 == sm.DEEP_ROWS and other_rows_w < other_rows_d
	verdict("C7 смешанное выделение под [2]: коробочка у ВСЕХ родов (копейщики %d, прочие %d шеренг; под [1] прочих %d)" % [sp_rows + 1, other_rows_d + 1, other_rows_w + 1], ok_rows)
	# Копейщики с ВЫКЛЮЧЕННЫМ режимом стены — коробочка всё равно (стена копий
	# по стойке — другая механика, к клавише [2] отношения не имеет)
	var sp_sid: int = (mixed[0] as Unit).squad_id
	GameManager.squad_set_ability(sp_sid, "spearman_1d", false)
	var plan_y: Dictionary = sm._layered_formation_slots(a2, b2, mixed)
	var sp_rows_off := 0
	for i2 in range((plan_y["flat"] as Array).size()):
		if GameManager.squad_type((plan_y["flat"][i2] as Unit).squad_id) == "spearman":
			sp_rows_off = maxi(sp_rows_off, int(plan_y["rows"][i2]))
	verdict("C7б [2] не зависит от «Стены копий» (шеренг %d)" % (sp_rows_off + 1), sp_rows_off + 1 == sm.DEEP_ROWS)
	GameManager.squad_set_ability(sp_sid, "spearman_1d", true)

	print("\n═════ D. ПРЕВЬЮ И ПРИКАЗ ═════")
	sm._fp_pending = false
	sm._fp_last = Vector2(300, 300)
	_key(KEY_1)
	verdict("D1 клавиша взводит перерисовку превью тем же кадром",
		sm._fp_pending and sm._fp_last.x < -1e8)
	var presses0: int = sm.formation_key_presses
	# Вне растяга цифры — горячие группы, а не строй
	sm._rmb_dragging = false
	sm._rmb_down = false
	sm.formation_mode = sm.FORM_WIDE
	_key(KEY_2)
	verdict("D2 без растяга [2] режим не трогает (это горячая группа)",
		sm.formation_mode == sm.FORM_WIDE and sm.formation_key_presses == presses0)
	# Приказ по отпусканию — тем же режимом, что превью: коробочка
	sm.formation_mode = sm.FORM_DEEP
	sm.formation_front = 0
	sm.selected_units = all.duplicate()
	sm._execute_line_formation(a, b)
	await pframes(2)
	# Сверяется НАБОР мест, а не «кто на какое»: разметка отряда после приказа
	# вправе пересадить бойцов внутри своего блока (squad_set_formation)
	var got := 0
	var plan_e: Dictionary = sm._mono_formation_slots(a, b, all)
	var targets: Array = []
	for u in all:
		targets.append((u as Unit).move_target as Vector3)
	for sl in plan_e["slots"]:
		var ws: Vector3 = sl
		for ti in range(targets.size()):
			var mt: Vector3 = targets[ti]
			if Vector2(mt.x - ws.x, mt.z - ws.z).length() < 0.05:
				got += 1
				targets.remove_at(ti)
				break
	verdict("D3 приказ по отпусканию раздал места коробочки (те же, что превью)",
		got == all.size(), "%d из %d" % [got, all.size()])
	await _e_persist(all, a, b)
	_finish()

func _front_type(plan: Dictionary, facing: Vector3) -> String:
	var best := -INF
	var t := ""
	var slots: Array = plan["slots"]
	var flat: Array = plan["flat"]
	for i in range(slots.size()):
		var d: float = (slots[i] as Vector3).dot(facing)
		if d > best:
			best = d
			t = _Formations.unit_type(flat[i])
	return t

func _back_type(plan: Dictionary, facing: Vector3) -> String:
	var best := INF
	var t := ""
	var slots: Array = plan["slots"]
	var flat: Array = plan["flat"]
	for i in range(slots.size()):
		var d: float = (slots[i] as Vector3).dot(facing)
		if d < best:
			best = d
			t = _Formations.unit_type(flat[i])
	return t

## Типы войск в порядке от фронта в тыл (по среднему положению эшелона)
func _echelon_order(plan: Dictionary, facing: Vector3) -> Array:
	var acc: Dictionary = {}
	var cnt: Dictionary = {}
	var slots: Array = plan["slots"]
	var flat: Array = plan["flat"]
	for i in range(slots.size()):
		var t: String = _Formations.unit_type(flat[i])
		acc[t] = float(acc.get(t, 0.0)) + (slots[i] as Vector3).dot(facing)
		cnt[t] = int(cnt.get(t, 0)) + 1
	var types: Array = acc.keys()
	types.sort_custom(func(x, y): return float(acc[x]) / float(cnt[x]) > float(acc[y]) / float(cnt[y]))
	return types

# ═════════════════════════════════════════════════════════════════════════════
# E. РЕЖИМ СТРОЯ ПЕРЕЖИВАЕТ РАСТЯГ, ВЫДЕЛЕНИЕ И ПРИКАЗ (заказ 13.09.2026)
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба (ТЗ 14.09.2026, п. 4, пятый разворот ручки): «после каждого
## растяга режим сбрасывается на широкий фронт, и [2] приходится жать
## заново». Сбрасывала его одна строка в обработчике отпускания ПКМ. Здесь
## проверяется, что её больше нет — и что менять режим по-прежнему может
## ТОЛЬКО игрок клавишей
func _e_persist(all: Array, a: Vector3, b: Vector3) -> void:
	var sm = main.selection_manager
	print("
═════ E. ЗАПОМИНАНИЕ РЕЖИМА ═════")
	sm.selected_units = all.duplicate()
	# Растяг: зажали ПКМ, увели мышь дальше порога, нажали [2]
	sm._rmb_down = true
	sm._rmb_dragging = true
	sm._rmb_press_over_ui = false
	sm._rmb_world_start = a
	sm._fp_mouse = Vector2(300, 300)
	sm._rmb_screen_start = Vector2(100, 300)
	_key(KEY_2)
	verdict("E1 [2] при растяге включает коробочку",
		sm.formation_mode == sm.FORM_DEEP)
	# ОТПУСКАЕМ ПКМ — тем же путём, каким это делает игра.
	# ── ПЯТЫЙ РАЗВОРОТ (ТЗ 14.09.2026, п. 4): РЕЖИМ ЗАПОМИНАЕТСЯ ─────────
	# «Все последующие растяги ПКМ строят сетку строго по запомненному
	# пресету, пока игрок явно не переключит хоткей». Сброса по отпусканию
	# ПКМ больше нет
	_release_rmb(b)
	verdict("E2 отпускание ПКМ режим НЕ сбрасывает (коробочка запомнена)",
		sm.formation_mode == sm.FORM_DEEP,
		"режим %d" % sm.formation_mode)
	# Смена выделения, снятие, приказ — режим остаётся коробочкой
	sm.selected_units = [all[0]]
	GameManager.on_selection_changed(sm.selected_units, true)
	await pframes(2)
	verdict("E3 смена выделения режим не трогает (коробочка)",
		sm.formation_mode == sm.FORM_DEEP, "режим %d" % sm.formation_mode)
	sm.selected_units = []
	GameManager.on_selection_changed(sm.selected_units, true)
	await pframes(2)
	verdict("E4 снятие выделения режим не трогает (коробочка)",
		sm.formation_mode == sm.FORM_DEEP, "режим %d" % sm.formation_mode)
	sm.selected_units = all.duplicate()
	sm._execute_line_formation(a, b)
	await pframes(2)
	verdict("E5 приказ на движение режим не трогает (коробочка)",
		sm.formation_mode == sm.FORM_DEEP, "режим %d" % sm.formation_mode)
	# ── ВТОРОЙ РАСТЯГ ИДЁТ УЖЕ КОРОБОЧКОЙ ────────────────────────────────
	# Это и есть суть жалобы: игрок растягивает второй раз и ждёт тот же строй
	# МЕРИМ НА ЛУЧНИКАХ, А НЕ НА КОПЕЙЩИКАХ: к этому блоку «Стена копий»
	# уже изучена (блок B), и копейщики ложатся в три шеренги при ЛЮБОМ
	# режиме (_block_formation_slots, спринт 20) — на них два режима
	# неразличимы по построению, и проверка краснела бы на исправном коде
	var arch: Array = _squad("archer", a + Vector3(0.0, 0.0, -40.0), 20)
	await pframes(4)
	var line_dir: Vector3 = (b - a).normalized()
	var a2 := a + Vector3(0.0, 0.0, -40.0)
	var b2 := b + Vector3(0.0, 0.0, -40.0)
	var again: Dictionary = sm._mono_formation_slots(a2, b2, arch)
	var e2: Vector2 = _extent(again["slots"], line_dir)
	sm.formation_mode = sm.FORM_WIDE
	var wide2: Dictionary = sm._mono_formation_slots(a2, b2, arch)
	var ew2: Vector2 = _extent(wide2["slots"], line_dir)
	sm.formation_mode = sm.FORM_DEEP
	print("  второй растяг: глубина без нажатий %.1f м против широкого %.1f м" % [
		e2.y, ew2.y])
	verdict("E6 второй растяг без нажатий идёт запомненной КОРОБОЧКОЙ, а не широким фронтом",
		e2.y > ew2.y + 0.5, "%.1f против %.1f м" % [e2.y, ew2.y])
	# ── РУЧНОЙ ВОЗВРАТ ───────────────────────────────────────────────────
	sm.formation_mode = sm.FORM_DEEP
	sm._rmb_down = true
	sm._rmb_dragging = true
	_key(KEY_1)
	verdict("E7 [1] возвращает широкий фронт — режим меняет только игрок",
		sm.formation_mode == sm.FORM_WIDE, "режим %d" % sm.formation_mode)
	_release_rmb(b)
