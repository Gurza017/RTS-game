extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ВЫДЕЛЕНИЕ ОВЕЦ, УДАЛЕНИЕ, СБОР РАЗБЕЖАВШИХСЯ, ТУША (ТЗ 19.09.2026,
## блоки 2-4)
## ═══════════════════════════════════════════════════════════════════════════
##   A ВЫДЕЛЕНИЕ — настоящий ввод (root.push_input, in_local_coords): ЛКМ по
##     овце подсвечивает её (кольцо), ПКМ выделенной овце ничего не приказывает,
##     клик по земле снимает, двойной ЛКМ выделяет всех овец того же загона,
##     Delete утилизирует выделенных, клик по бойцу вытесняет овец из выделения.
##   B СБОР — рабочий по ПКМ на блуждающую овцу игрока НЕ режет её: несёт в
##     ближайший незаполненный загон, затем сам обходит окрестности за
##     другими, а когда блуждающих нет — берётся за штатный забой в загоне;
##     свободных загонов нет — овца остаётся, рабочий встаёт.
##   C РАЗБЕГАНИЕ — снесённый загон: овцы теряют привязку, становятся
##     блуждающими и расходятся от места ограды.
##   D ТУША — забитая овца: кадр заморожен (frame_fps 0, один кадр), спрайт
##     ТОТ ЖЕ, перевёрнут ногами вверх (180°), подкрашен кровью, лежит
##     неподвижно; рабочий режет её на месте и носит мясо на склад.
## Запуск: godot --headless --path . res://qa_sheep_herding/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _Pen := preload("res://scripts/SheepPen.gd")
const _Sheep := preload("res://scripts/goblin/Sheep.gd")

var main = null
var sm = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _castle: Building = null

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с"); _finish())

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
	print("\n═════ ИТОГ qa_sheep_herding: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

# ─────────────────────────────────────────────────────────────────────────────
func _pen(at: Vector3) -> Building:
	var pen: Building = _Pen.new()
	pen.faction = Constants.FACTION_PLAYER
	main.world_add(pen)
	pen.global_position = Vector3(at.x, main.get_terrain_height(at.x, at.z), at.z)
	return pen

## Овца в точке; tick — тикает ли сама
func _sheep(at: Vector3, tick: bool = true) -> Node3D:
	var s: Node3D = _Sheep.new()
	s.set("home", at)
	main.world_root().add_child(s)
	s.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	s.set_process(tick)
	return s

## Блуждающая овца игрока: хозяйская, но без загона и без замка
func _stray(at: Vector3, tick: bool = true) -> Node3D:
	var s: Node3D = _sheep(at, tick)
	s.set("owner_faction", Constants.FACTION_PLAYER)
	return s

func _spawn_worker(at: Vector3) -> Worker:
	var w: Unit = (Building.PRELOAD_SCENES["worker"] as PackedScene).instantiate()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	w.sync_row()
	GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "worker"), w)
	return w as Worker

func _spawn_spear(at: Vector3) -> Unit:
	var u: Unit = (Building.PRELOAD_SCENES["spearman"] as PackedScene).instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "spearman"), u)
	return u

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _mouse(btn: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	# В ЛОКАЛЬНЫХ координатах вьюпорта: без второго аргумента корень применяет
	# обратное растяжение окна (ловушка qa_monk_click_fix)
	get_tree().root.push_input(e, true)

func _click(btn: MouseButton, pos: Vector2) -> void:
	_mouse(btn, true, pos)
	await frames(1)
	_mouse(btn, false, pos)
	await frames(2)

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	get_tree().root.push_input(e, true)
	await frames(1)
	var e2 := InputEventKey.new()
	e2.keycode = code
	e2.physical_keycode = code
	e2.pressed = false
	get_tree().root.push_input(e2, true)
	await frames(1)

func _screen_of(n: Node3D, lift: float = 0.5) -> Vector2:
	return (sm.camera as Camera3D).unproject_position(n.global_position + Vector3(0.0, lift, 0.0))

## Клик по МИРОВОЙ точке: камера ставится над ней и точка экрана считается
## ТЕМ ЖЕ кадром (объектив между кликами уезжал на метры — ловушка стендов
## из CLAUDE.md «камеру замораживать и пересчитывать экранную точку»)
func _click_world(btn: MouseButton, p: Vector3, lift: float = 0.5) -> void:
	main._camera.pan_to(Vector3(p.x, 0.0, p.z))
	main._camera._update_position()
	await frames(1)
	var scr: Vector2 = (sm.camera as Camera3D).unproject_position(p + Vector3(0.0, lift, 0.0))
	await _click(btn, scr)

## Камера над точкой и заморожена (точка экрана считается тем же кадром)
func _freeze_cam(at: Vector3) -> void:
	main.set_process(false)
	(sm.camera as Camera3D).get_parent().set_process(false)
	main._camera.pan_to(Vector3(at.x, 0.0, at.z))
	main._camera._update_position()
	await frames(2)

func _thaw_cam() -> void:
	main.set_process(true)
	(sm.camera as Camera3D).get_parent().set_process(true)

func _cleanup(list: Array) -> void:
	for n in list:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	await pframes(3)

# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if main.get("goblin_reserve") != null:
		main.goblin_reserve.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	for lair in GameManager.troll_lairs:
		if lair == null or not is_instance_valid(lair):
			continue
		for t in lair.get("trolls"):
			if t != null and is_instance_valid(t):
				(t as Unit).set_tick(false)
		for g in lair.get("gnolls"):
			if g != null and is_instance_valid(g):
				(g as Node).queue_free()
		for s in lair.get("sheep"):
			if s != null and is_instance_valid(s):
				(s as Node).queue_free()
	await pframes(4)
	_castle = Castle.new()
	_castle.faction = Constants.FACTION_PLAYER
	main.world_add(_castle)
	var cp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, 26.0)
	_castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(6)

	await _a_select()
	if OS.get_cmdline_user_args().has("only_a"):
		_finish()
		return
	await _b_herd()
	await _c_scatter()
	await _d_corpse()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ВЫДЕЛЕНИЕ, ПОДСВЕТКА, DELETE
# ═════════════════════════════════════════════════════════════════════════════
func _a_select() -> void:
	print("\n═════ A. ВЫДЕЛЕНИЕ ОВЕЦ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-40.0, 0.0, 40.0)
	main._clear_area_of_resources(base, 30.0)
	var pen: Building = _pen(base)
	await pframes(4)
	var flock: Array = []
	for i in range(3):
		var s: Node3D = _sheep(base + Vector3(-2.0 + 2.0 * float(i), 0.0, 1.5), false)
		s.call("bind_to_pen", pen, Constants.FACTION_PLAYER)
		flock.append(s)
	var lone: Node3D = _stray(base + Vector3(30.0, 0.0, 0.0), false)
	var w: Worker = _spawn_worker(base + Vector3(0.0, 0.0, 9.0))
	w.set_tick(false)
	await pframes(3)
	await _freeze_cam(base)
	var s0: Node3D = flock[0]
	var scr: Vector2 = _screen_of(s0)
	var pick = sm._pick_at(scr, Constants.LAYER_RESOURCES)["target"]
	verdict("A0 луч ЛКМ по слою ресурсов находит под курсором овцу",
		pick == s0, "под курсором: %s" % (String((pick as Node).name) if pick != null else "ничего"))
	_Opt.cmd_meter = true
	_Opt.cmd_reset()
	await _click_world(MOUSE_BUTTON_LEFT, s0.global_position)
	verdict("A1 ЛКМ по овце — она выделена и подсвечена кольцом, бойцов в выделении нет",
		sm.selected_sheep.size() == 1 and sm.selected_sheep[0] == s0
			and bool(s0.call("is_selected")) and sm.selected_units.is_empty(),
		"овец выделено %d, кольцо=%s" % [sm.selected_sheep.size(), str(s0.call("is_selected"))])
	# ПКМ по земле — овце ничего не приказывается
	var tgt0: Vector3 = s0.call("current_target")
	await _click_world(MOUSE_BUTTON_RIGHT, base + Vector3(6.0, 0.0, 6.0), 0.0)
	await pframes(3)
	verdict("A2 ПКМ выделенной овце ничего не приказывает (цель не появилась, приказов 0)",
		(s0.call("current_target") as Vector3) == tgt0 and _Opt.cmd_total == 0
			and sm.selected_sheep.size() == 1,
		"цель %s, приказов %d" % [str(s0.call("current_target")), _Opt.cmd_total])
	_Opt.cmd_meter = false
	# ЛКМ по пустой земле снимает выделение
	await _click_world(MOUSE_BUTTON_LEFT, base + Vector3(-9.0, 0.0, 8.0), 0.0)
	verdict("A3 ЛКМ по земле снимает выделение овцы, кольцо погашено",
		sm.selected_sheep.is_empty() and not bool(s0.call("is_selected")))
	# Двойной ЛКМ — все овцы того же загона; блуждающая в 30 м — нет
	# Окно двойного клика (0.35 с) шире трёх кадров: пауза, чтобы первый клик
	# пары не склеился с кликом A1
	await get_tree().create_timer(0.5).timeout
	await _click_world(MOUSE_BUTTON_LEFT, s0.global_position)
	await _click_world(MOUSE_BUTTON_LEFT, s0.global_position)
	var all_in := true
	for s in flock:
		if not sm.selected_sheep.has(s) or not bool(s.call("is_selected")):
			all_in = false
	verdict("A4 двойной ЛКМ выделяет всех овец того же загона (%d), чужая блуждающая — нет" % flock.size(),
		all_in and sm.selected_sheep.size() == flock.size() and not sm.selected_sheep.has(lone),
		"выделено %d" % sm.selected_sheep.size())
	# Delete — утилизация
	var group0: int = get_tree().get_nodes_in_group("sheep").size()
	await _key(KEY_DELETE)
	await pframes(3)
	var gone := 0
	for s in flock:
		if s == null or not is_instance_valid(s) or bool(s.get("eaten")):
			gone += 1
	verdict("A5 Delete утилизирует выделенных овец: %d из %d исчезли, загон пуст, выделение снято" % [gone, flock.size()],
		gone == flock.size() and int(pen.call("sheep_count")) == 0 and sm.selected_sheep.is_empty()
			and get_tree().get_nodes_in_group("sheep").size() == group0 - flock.size(),
		"в загоне %d, в группе %d → %d" % [int(pen.call("sheep_count")), group0,
			get_tree().get_nodes_in_group("sheep").size()])
	verdict("A5б блуждающая (не выделенная) цела", is_instance_valid(lone) and not bool(lone.get("eaten")))
	# Овца, потом боец: клик по бойцу вытесняет овцу из выделения
	await get_tree().create_timer(0.5).timeout
	await _click_world(MOUSE_BUTTON_LEFT, lone.global_position)
	var had_lone: bool = sm.selected_sheep.has(lone)
	await _click_world(MOUSE_BUTTON_LEFT, w.global_position, 0.8)
	verdict("A6 ЛКМ по бойцу после овцы: боец выделен, овца снята",
		had_lone and sm.selected_units.has(w) and sm.selected_sheep.is_empty()
			and not bool(lone.call("is_selected")),
		"была выделена=%s, бойцов %d, овец %d" % [str(had_lone), sm.selected_units.size(), sm.selected_sheep.size()])
	sm.clear_selection()
	_thaw_cam()
	await _cleanup([pen, lone, w] + flock)

# ═════════════════════════════════════════════════════════════════════════════
# B. СБОР БЛУЖДАЮЩИХ
# ═════════════════════════════════════════════════════════════════════════════
func _b_herd() -> void:
	print("\n═════ B. СБОР РАЗБЕЖАВШИХСЯ ОВЕЦ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 40.0)
	main._clear_area_of_resources(base, 40.0)
	var pen: Building = _pen(base)
	await pframes(4)
	# Одна овца уже в загоне — для штатной рутины после сбора
	var resident: Node3D = _sheep(base + Vector3(1.0, 0.0, 1.0), false)
	resident.call("bind_to_pen", pen, Constants.FACTION_PLAYER)
	var w: Worker = _spawn_worker(base + Vector3(0.0, 0.0, 10.0))
	var s1: Node3D = _stray(base + Vector3(0.0, 0.0, 22.0), false)
	var s2: Node3D = _stray(base + Vector3(24.0, 0.0, 14.0), false)
	await pframes(3)
	verdict("B0 овца без загона у игрока — блуждающая (is_stray), а не «своя на выпасе»",
		bool(s1.call("is_stray")) and not bool(s1.call("is_owned")) and not bool(resident.call("is_stray")))
	# ПКМ рабочим по блуждающей овце настоящим вводом
	sm.select_units([w])
	await _freeze_cam(s1.global_position)
	var scr: Vector2 = _screen_of(s1)
	var pick = sm._pick_at(scr, sm.order_pick_mask())["target"]
	verdict("B1 под курсором ПКМ — блуждающая овца", pick == s1,
		"под курсором: %s" % (String((pick as Node).name) if pick != null else "ничего"))
	await _click_world(MOUSE_BUTTON_RIGHT, s1.global_position)
	_thaw_cam()
	sm.clear_selection()
	verdict("B2 приказ принят как СБОР: рабочий идёт за овцой в режиме пастуха",
		w.is_stealing_sheep() and w.is_herding() and w.sheep_phase() == Worker.SheepPhase.GO,
		"работа=%s, пастух=%s, фаза %d" % [str(w.is_stealing_sheep()), str(w.is_herding()), w.sheep_phase()])
	var g := 0
	while g < 60 * 30 and w.sheep_phase() == Worker.SheepPhase.GO:
		await get_tree().physics_frame
		g += 1
	await pframes(2)
	verdict("B3 дошёл — НЕ режет, а несёт (CARRY, овца над головой)",
		w.sheep_phase() == Worker.SheepPhase.CARRY and s1.get("captor") == w and bool(s1.call("is_carried")),
		"фаза %d за %d кадров" % [w.sheep_phase(), g])
	g = 0
	while g < 60 * 60 and is_instance_valid(s1) and s1.get("pen") != pen:
		await get_tree().physics_frame
		g += 1
	verdict("B4 овца донесена в загон и привязана, живая",
		is_instance_valid(s1) and s1.get("pen") == pen and not bool(s1.get("dead")) and not bool(s1.call("is_stray")),
		"pen=%s, за %d кадров" % [str(s1.get("pen") == pen), g])
	# Сам взялся за вторую блуждающую
	await pframes(4)
	verdict("B5 после доставки сам пошёл за следующей блуждающей (в 60 м)",
		w.is_stealing_sheep() and w.is_herding() and w.get("_sheep") == s2,
		"работа=%s, пастух=%s, цель=%s" % [str(w.is_stealing_sheep()), str(w.is_herding()),
			str(w.get("_sheep") == s2)])
	g = 0
	while g < 60 * 90 and is_instance_valid(s2) and s2.get("pen") != pen:
		await get_tree().physics_frame
		g += 1
	verdict("B6 вторая тоже в загоне", is_instance_valid(s2) and s2.get("pen") == pen, "за %d кадров" % g)
	# Блуждающих нет — штатная рутина: забой в загоне
	g = 0
	while g < 60 * 10 and not (w.is_stealing_sheep() and not w.is_herding()):
		await get_tree().physics_frame
		g += 1
	var routine_ok: bool = w.is_stealing_sheep() and not w.is_herding()
	var tgt: Node = w.get("_sheep")
	verdict("B7 блуждающих не осталось — рабочий сам перешёл к забою овцы загона",
		routine_ok and tgt != null and is_instance_valid(tgt) and tgt.get("pen") == pen,
		"работа=%s, пастух=%s" % [str(w.is_stealing_sheep()), str(w.is_herding())])
	g = 0
	while g < 60 * 40 and not (tgt != null and is_instance_valid(tgt) and bool(tgt.get("dead"))):
		await get_tree().physics_frame
		g += 1
	verdict("B8 забой пошёл: овца загона забита ножом (лежит тушей)",
		tgt != null and is_instance_valid(tgt) and bool(tgt.get("dead")), "за %d кадров" % g)
	w.command_move(w.global_position)
	await pframes(3)
	# Свободных загонов нет — овца остаётся, рабочий встаёт
	var filler: Array = []
	while int(pen.call("sheep_count")) < int(pen.call("capacity")):
		var f: Node3D = _sheep(base + Vector3(2.0, 0.0, -2.0), false)
		f.call("bind_to_pen", pen, Constants.FACTION_PLAYER)
		filler.append(f)
	var s3: Node3D = _stray(w.global_position + Vector3(8.0, 0.0, 0.0), false)
	await pframes(2)
	w.command_steal_sheep(s3)
	await pframes(4)
	verdict("B9 свободных загонов нет — рабочий за блуждающей не идёт (встал), овца остаётся свободной",
		not w.is_stealing_sheep() and bool(s3.call("is_free")) and bool(s3.call("is_stray"))
			and not bool(s3.get("dead")),
		"работа=%s, свободна=%s" % [str(w.is_stealing_sheep()), str(s3.call("is_free"))])
	await _cleanup([pen, w, s1, s2, s3, resident] + filler)

# ═════════════════════════════════════════════════════════════════════════════
# C. СНЕСЁННЫЙ ЗАГОН — ОВЦЫ РАЗБЕГАЮТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _c_scatter() -> void:
	print("\n═════ C. СНОС ЗАГОНА ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-40.0, 0.0, -40.0)
	main._clear_area_of_resources(base, 30.0)
	var pen: Building = _pen(base)
	await pframes(4)
	var flock: Array = []
	for i in range(4):
		var s: Node3D = _sheep(base + Vector3(-1.5 + float(i), 0.0, 0.5), true)
		s.call("bind_to_pen", pen, Constants.FACTION_PLAYER)
		flock.append(s)
	await pframes(3)
	pen.queue_free()
	await pframes(6)
	var strays := 0
	var scattered := 0
	for s in flock:
		if bool(s.call("is_stray")) and s.get("pen") == null and int(s.get("owner_faction")) == Constants.FACTION_PLAYER:
			strays += 1
		if (s.call("current_target") as Vector3).x != INF or int(s.get("hops")) > 0:
			scattered += 1
	verdict("C1 после сноса все %d овцы — блуждающие игрока (привязки нет, хозяин остался)" % flock.size(),
		strays == flock.size(), "блуждающих %d" % strays)
	verdict("C2 овцы разбегаются: у всех взведена перебежка", scattered == flock.size(),
		"разбежалось %d из %d" % [scattered, flock.size()])
	verdict("C3 блуждающая пасётся от места, где стояла, а не от несуществующего загона",
		_xz(flock[0].call("graze_home"), flock[0].global_position) < 12.0
			and float(flock[0].call("graze_radius")) >= 10.0,
		"дом в %.1f м, радиус %.1f" % [_xz(flock[0].call("graze_home"), flock[0].global_position),
			float(flock[0].call("graze_radius"))])
	await _cleanup(flock)

# ═════════════════════════════════════════════════════════════════════════════
# D. ТУША
# ═════════════════════════════════════════════════════════════════════════════
func _d_corpse() -> void:
	print("\n═════ D. ТУША ЗАБИТОЙ ОВЦЫ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, -40.0)
	main._clear_area_of_resources(base, 30.0)
	var pen: Building = _pen(base)
	await pframes(4)
	var s: Node3D = _sheep(base + Vector3(1.0, 0.0, 1.0), true)
	s.call("bind_to_pen", pen, Constants.FACTION_PLAYER)
	var sp: Unit = _spawn_spear(base + Vector3(1.0, 0.0, 3.5))
	await pframes(3)
	var live_tex: Texture2D = s.call("sprite_texture")
	var live_fps: float = float(s._mat.get_shader_parameter("frame_fps"))
	var hops0: int = int(s.get("hops"))
	# Боец рубит одним ударом — тот же kill_by, что и у ножа рабочего
	sp.command_hunt_sheep(s)
	var g := 0
	while g < 60 * 15 and not bool(s.get("dead")):
		await get_tree().physics_frame
		g += 1
	verdict("D1 боец зарубил овцу: лежит тушей", bool(s.get("dead")), "за %d кадров" % g)
	# Перебежки считаем ОТ СМЕРТИ: пока боец шёл, живая овца могла прыгнуть
	hops0 = int(s.get("hops"))
	var mat: ShaderMaterial = s._mat
	var fps: float = float(mat.get_shader_parameter("frame_fps"))
	var fc: float = float(mat.get_shader_parameter("frame_count"))
	verdict("D2 анимация дыхания выключена: frame_fps %.0f → 0, один кадр (frame_count %.0f)" % [live_fps, fc],
		fps == 0.0 and fc == 1.0 and live_fps > 0.0)
	var mi: MeshInstance3D = s._mi
	verdict("D3 квад в мировой ориентации и перевёрнут ногами вверх (180° вокруг оси взгляда)",
		float(mat.get_shader_parameter("world_fixed")) >= 0.5
			and absf(absf(mi.rotation_degrees.z) - 180.0) < 0.01,
		"world_fixed=%s, поворот %s" % [str(mat.get_shader_parameter("world_fixed")), str(mi.rotation_degrees)])
	var mod = mat.get_shader_parameter("modulate")
	verdict("D4 подкраска красноватая (BLOOD_TINT): R больше G и B",
		mod != null and (mod as Color).r > (mod as Color).g + 0.2 and (mod as Color).r > (mod as Color).b + 0.2,
		"modulate=%s" % str(mod))
	var dead_tex: Texture2D = s.call("sprite_texture")
	# Та же лента овцы: один кадр той же ширины и той же (срезанной) высоты, что
	# у кадров живой ленты покоя, — а не какая-то чужая картинка
	var live_fw: float = live_tex.get_size().x / float(_Sheep.frames_in(_Sheep.SHEET_IDLE))
	verdict("D5 на земле ТОТ ЖЕ спрайт овцы (один кадр овечьей ленты, не иконка мяса)",
		dead_tex != null and dead_tex.get_size().y == live_tex.get_size().y
			and absf(dead_tex.get_size().x - live_fw) < 0.5,
		"живая %s, туша %s, кадр %.0f px" % [str(live_tex.get_size()), str(dead_tex.get_size()), live_fw])
	var p0: Vector3 = s.global_position
	var rot0: Vector3 = mi.rotation_degrees
	await pframes(180)
	verdict("D6 туша лежит неподвижно три секунды: ни перебежек, ни сдвига, ни поворота",
		_xz(p0, s.global_position) < 0.001 and int(s.get("hops")) == hops0
			and (s.call("current_target") as Vector3).x == INF and mi.rotation_degrees == rot0,
		"сдвиг %.3f м, перебежек +%d" % [_xz(p0, s.global_position), int(s.get("hops")) - hops0])
	verdict("D7 мясо лежит у туши: %d кусков" % int(s.get("meat_left")),
		int(s.get("meat_left")) == _Sheep.MEAT_TRIPS)
	# Рабочий режет на месте и носит на склад
	sp.take_damage(1.0e9)
	var w: Worker = _spawn_worker(base + Vector3(3.0, 0.0, 6.0))
	await pframes(3)
	w.command_steal_sheep(s)
	g = 0
	while g < 60 * 20 and w.sheep_phase() != Worker.SheepPhase.BUTCHER:
		await get_tree().physics_frame
		g += 1
	verdict("D8 рабочий по ПКМ на тушу подошёл и режет её НА МЕСТЕ (BUTCHER)",
		w.sheep_phase() == Worker.SheepPhase.BUTCHER and _xz(w.global_position, p0) < 3.0,
		"фаза %d, в %.1f м от туши" % [w.sheep_phase(), _xz(w.global_position, p0)])
	var meat0: int = int(s.get("meat_left"))
	var food0: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD)
	g = 0
	while g < 60 * 60 and w.sheep_trips() < 1:
		await get_tree().physics_frame
		g += 1
	verdict("D9 первый кусок отрезан и унесён на склад: запас туши %d → %d, ходок %d" % [meat0, int(s.get("meat_left")), w.sheep_trips()],
		int(s.get("meat_left")) == meat0 - 1 and w.sheep_trips() >= 1
			and ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD) > food0 - 5.0
			and bool(s.get("dead")) and _xz(p0, s.global_position) < 0.001,
		"за %d кадров" % g)
	await _cleanup([pen, s, w])
