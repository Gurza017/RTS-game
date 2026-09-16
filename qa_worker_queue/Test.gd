extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_worker_queue — SHIFT-ОЧЕРЕДЬ СТРОЕК И ПАНЕЛЬ РАБОЧЕГО (13.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Две жалобы владельца:
##   1. «три рабочих, пять зданий через Shift — строят только первые два,
##      дальше фундаменты стоят». Причина: Worker.on_construction_finished
##      брал следующую площадку через command_build(nxt) с queue = false, а
##      тот ОЧИЩАЕТ остаток очереди (см. Worker._advance_build_queue);
##   2. «поставил здание — панель построек рабочего закрывается». Причина:
##      Main._input съедал НАЖАТИЕ ЛКМ размещения, а ОТПУСКАНИЕ доходило до
##      SelectionManager и читалось как клик по пустой земле — снятие
##      выделения (см. Main._swallow_lmb_release).
##
##   A  ЦЕПОЧКА — три рабочих, пять площадок через API очереди: очередь не
##      сбрасывается после второй, все пять достроены
##   B  ПАНЕЛЬ  — живая сессия: выделение артели, размещение кликами через
##      ввод (Shift зажат), смена типа постройки из панели (дом → кузница →
##      башня) без снятия выделения, единый стек Дом1→Дом2→Дом3→Кузница→Башня,
##      выход по ПКМ; панель артели всё это время на месте
##
## Запуск: <godot> --headless --path . res://qa_worker_queue/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")
const F := Constants.FACTION_PLAYER

var main = null
var sm = null
var hud = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(360.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 360 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_worker_queue: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn_worker(at: Vector3) -> Unit:
	var u: Unit = load("res://scenes/units/Worker.tscn").instantiate()
	u.faction = F
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Площадка стройки НАПРЯМУЮ (так же, как её ставит try_worker_build)
func _make_site(bid: String, at: Vector3, sec: float) -> Building:
	var site: Building = _CSite.new()
	site.faction     = F
	site.target_id   = bid
	site.target_name = String(_UCfg.building_cfg(bid).get("name", bid))
	site.build_time  = sec
	site.build_size  = _UCfg.building_size(bid)
	main.world_add(site)
	site.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return site

func _site_done(s) -> bool:
	return s == null or not is_instance_valid(s) or bool(s.get("_done"))

func _sites_done(sites: Array) -> int:
	var n := 0
	for s in sites:
		if _site_done(s):
			n += 1
	return n

## Живые стройплощадки игрока (по скрипту, а не по имени класса)
func _player_sites() -> Array:
	var out: Array = []
	for b in GameManager.nodes_in_group_cached(Constants.building_group(F)):
		if not is_instance_valid(b):
			continue
		if (b as Node).get_script() == _CSite and not bool(b.get("_done")):
			out.append(b)
	return out

func _count_buildings(bid: String) -> int:
	var n := 0
	for b in GameManager.nodes_in_group_cached(Constants.building_group(F)):
		if not is_instance_valid(b):
			continue
		var bb := b as Building
		if bb != null and bb.get_script() != _CSite and bb.building_id == bid:
			n += 1
	return n

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.pop_limit_enabled = false
	sm = main.selection_manager
	hud = main.hud
	for node in get_tree().get_nodes_in_group("all_units"):
		(node as Node).queue_free()
	await pframes(6)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(F, int(t), 90000.0)
	print("\n═════ qa_worker_queue ═════")
	await _a_chain()
	await _b_panel()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ЦЕПОЧКА ИЗ ПЯТИ ПЛОЩАДОК ТРЕМЯ РАБОЧИМИ
# ═════════════════════════════════════════════════════════════════════════════
func _a_chain() -> void:
	print("\n═════ A. ЦЕПОЧКА ЧЕРЕЗ ОЧЕРЕДЬ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(30.0, 0.0, 22.0)
	main._clear_area_of_resources(spot, 60.0)
	var crew: Array = []
	for i in range(3):
		crew.append(_spawn_worker(spot + Vector3(float(i) * 1.2, 0.0, 0.0)))
	var sites: Array = []
	for i in range(5):
		sites.append(_make_site("house", spot + Vector3(-12.0 + float(i) * 9.0, 0.0, 14.0), 2.0))
	await pframes(2)
	# Так раздаёт площадки try_worker_build с зажатым Shift: первая —
	# свободному сразу, остальные — в очередь занятого
	for s in sites:
		for w in crew:
			(w as Worker).command_build(s, true)
	await pframes(2)
	var q_ok := true
	for w in crew:
		if (w as Worker).build_queue_size() != 4 or (w as Worker).build_target != sites[0]:
			q_ok = false
	verdict("A1 у каждого из трёх рабочих: первая площадка в работе, четыре в очереди",
		q_ok, "очереди %s" % str(crew.map(func(w): return (w as Worker).build_queue_size())))
	# Ждём достройки, по дороге снимаем очередь в момент «две готовы»
	var q_after_two: int = -1
	var t_two: int = -1
	var done_all := false
	for f in range(60 * 150):
		await get_tree().physics_frame
		var d: int = _sites_done(sites)
		if d >= 2 and q_after_two < 0:
			# Дадим кадр на переход к третьей — и смотрим, жива ли очередь
			await pframes(3)
			q_after_two = 0
			for w in crew:
				q_after_two = maxi(q_after_two, (w as Worker).build_queue_size())
			t_two = f
		if d >= 5:
			done_all = true
			print("  все пять достроены на физкадре %d" % f)
			break
	verdict("A2 после второй достройки очередь НЕ сброшена (третья и дальше в ней)",
		q_after_two >= 1, "в очереди после второй: %d (кадр %d)" % [q_after_two, t_two])
	verdict("A3 все пять площадок достроены", done_all,
		"готово %d из 5" % _sites_done(sites))
	verdict("A4 на карте пять домов", _count_buildings("house") >= 5,
		"домов %d" % _count_buildings("house"))
	var idle_ok := true
	for w in crew:
		if (w as Worker).build_queue_size() != 0 or (w as Worker).build_target != null:
			idle_ok = false
	verdict("A5 очереди рабочих опустели, стройки у них нет", idle_ok)
	for w in crew:
		if is_instance_valid(w):
			(w as Unit).take_damage(1e12)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# B. ЖИВАЯ СЕССИЯ: ПАНЕЛЬ, SHIFT, СМЕНА ТИПА, ЕДИНЫЙ СТЕК, ВЫХОД ПО ПКМ
# ═════════════════════════════════════════════════════════════════════════════
func _key(keycode: Key, pressed: bool) -> void:
	var k := InputEventKey.new()
	k.keycode = keycode
	k.physical_keycode = keycode
	k.pressed = pressed
	Input.parse_input_event(k)

func _mouse(btn: MouseButton, pressed: bool, pos: Vector2, shift: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.shift_pressed = shift
	get_tree().root.push_input(e)

## Клик размещения по мировой точке ЧЕРЕЗ ВВОД: нажатие и отпускание, как у
## игрока. Именно отпускание раньше снимало выделение
func _place_click(world: Vector3, shift: bool) -> void:
	var pos: Vector2 = main._camera.unproject_position(world)
	_mouse(MOUSE_BUTTON_LEFT, true, pos, shift)
	await frames(1)
	_mouse(MOUSE_BUTTON_LEFT, false, pos, shift)
	await frames(2)

func _selected_workers() -> int:
	var n := 0
	for u in sm.selected_units:
		if is_instance_valid(u) and u is Worker:
			n += 1
	return n

func _b_panel() -> void:
	print("\n═════ B. ПАНЕЛЬ И СЕССИЯ ПОСТРОЙКИ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(70.0, 0.0, 30.0)
	main._clear_area_of_resources(spot, 60.0)
	var crew: Array = []
	for i in range(3):
		crew.append(_spawn_worker(spot + Vector3(float(i) * 1.2, 0.0, -6.0)))
	await pframes(2)
	# Камера над площадкой и заморожена: экранные точки считаются в том же
	# кадре, что и клики (правила стендов, целящихся по экрану)
	main._camera.pan_to(spot)
	main._camera._update_position()
	main._camera.set_process(false)
	# Выделение артели — через SelectionManager, как рамкой
	sm._clear_selection()
	for w in crew:
		sm._select(w)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	verdict("B0 артель выделена, панель построек рабочего открыта",
		_selected_workers() == 3 and bool(hud._worker_boost),
		"рабочих в выделении %d, панель артели %s" % [
			_selected_workers(), str(bool(hud._worker_boost))])
	# Shift зажат на всё время расстановки
	_key(KEY_SHIFT, true)
	await frames(1)
	var shift_ok: bool = Input.is_key_pressed(KEY_SHIFT)
	print("  Shift по Input.is_key_pressed: %s" % str(shift_ok))
	var sel_crew: Array = sm.selected_units.duplicate()
	var placing: int = main.Phase.PLACING_BUILDING
	# ── ТРИ ДОМА ─────────────────────────────────────────────────────────────
	GameManager.try_worker_build(crew[0], "house", sel_crew)
	await frames(1)
	verdict("B1 клик по иконке дома открывает режим размещения",
		int(main._phase) == placing)
	var spots: Array = []
	for i in range(3):
		spots.append(spot + Vector3(-14.0 + float(i) * 10.0, 0.0, 12.0))
	for i in range(3):
		await _place_click(spots[i], true)
	verdict("B2 после трёх кликов размещения выделение артели ЦЕЛО, панель на месте",
		_selected_workers() == 3 and bool(hud._worker_boost),
		"рабочих в выделении %d" % _selected_workers())
	verdict("B3 с Shift режим размещения жив (фантом следующего дома)",
		int(main._phase) == placing)
	verdict("B3б три площадки домов стоят на карте",
		_player_sites().size() == 3, "площадок %d" % _player_sites().size())
	# ── СМЕНА ТИПА ИЗ ПАНЕЛИ: КУЗНИЦА, ПОТОМ БАШНЯ — НЕ СНИМАЯ ВЫДЕЛЕНИЯ ────
	GameManager.try_worker_build(crew[0], "smithy", sel_crew)
	await frames(1)
	await _place_click(spot + Vector3(16.0, 0.0, 12.0), true)
	GameManager.try_worker_build(crew[0], "tower", sel_crew)
	await frames(1)
	await _place_click(spot + Vector3(26.0, 0.0, 12.0), true)
	var sites: Array = _player_sites()
	var kinds: Array = sites.map(func(s): return String(s.get("target_id")))
	kinds.sort()
	verdict("B4 смена типа из панели ставит площадки, не закрывая сессию: 3 дома + кузница + башня",
		sites.size() == 5 and kinds == ["house", "house", "house", "smithy", "tower"]
			and _selected_workers() == 3 and bool(hud._worker_boost),
		"площадки %s, рабочих в выделении %d" % [str(kinds), _selected_workers()])
	# ── ЕДИНЫЙ СТЕК У КАЖДОГО РАБОЧЕГО ──────────────────────────────────────
	var stack_ok := true
	var stack_txt := ""
	for w in crew:
		var ww := w as Worker
		var cur: String = String(ww.build_target.get("target_id")) \
			if ww.build_target != null and is_instance_valid(ww.build_target) else "—"
		var q: Array = ww._build_queue.map(func(s): return String(s.get("target_id")))
		stack_txt = "%s + %s" % [cur, str(q)]
		if cur != "house" or q != ["house", "house", "smithy", "tower"]:
			stack_ok = false
	verdict("B5 у каждого рабочего единый стек Дом1 → Дом2 → Дом3 → Кузница → Башня",
		stack_ok, stack_txt)
	# ── ВЫХОД ИЗ РЕЖИМА: ОТПУСТИЛИ SHIFT, ПКМ — ФАНТОМ СНЯТ, ВЫДЕЛЕНИЕ ЦЕЛО ─
	_key(KEY_SHIFT, false)
	await frames(1)
	var g0: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
	var pos: Vector2 = main._camera.unproject_position(spot)
	_mouse(MOUSE_BUTTON_RIGHT, true, pos, false)
	await frames(1)
	_mouse(MOUSE_BUTTON_RIGHT, false, pos, false)
	await frames(2)
	verdict("B6 ПКМ отменяет фантом (с возвратом), выделение и панель остаются",
		int(main._phase) == main.Phase.PLAYING
			and ResourceManager.get_amount(F, Constants.RESOURCE_GOLD) >= g0
			and _selected_workers() == 3 and bool(hud._worker_boost),
		"фаза %d, рабочих в выделении %d" % [int(main._phase), _selected_workers()])
	verdict("B6б ПКМ-отмена не тронула стек площадок",
		_player_sites().size() == 5 and (crew[0] as Worker).build_queue_size() == 4)
	# ── ДОСТРОЙКА ВСЕЙ ЦЕПОЧКИ ──────────────────────────────────────────────
	for s in sites:
		if is_instance_valid(s):
			s.build_time = 2.0
	var done_all := false
	for f in range(60 * 180):
		await get_tree().physics_frame
		if _sites_done(sites) >= 5:
			done_all = true
			print("  вся цепочка достроена на физкадре %d" % f)
			break
	verdict("B7 вся цепочка из пяти разных построек достроена без сброса",
		done_all, "готово %d из 5" % _sites_done(sites))
	verdict("B8 на карте появились 3 дома, кузница и башня",
		_count_buildings("house") >= 3 and _count_buildings("smithy") >= 1
			and _count_buildings("tower") >= 1,
		"домов %d, кузниц %d, башен %d" % [_count_buildings("house"),
			_count_buildings("smithy"), _count_buildings("tower")])
	# ── ОДИНОЧНОЕ РАЗМЕЩЕНИЕ БЕЗ SHIFT: ФАНТОМ ГАСНЕТ, ПАНЕЛЬ ОСТАЁТСЯ ───────
	GameManager.try_worker_build(crew[0], "house", sel_crew)
	await frames(1)
	await _place_click(spot + Vector3(0.0, 0.0, 24.0), false)
	verdict("B9 одиночное размещение без Shift: режим закрыт, а выделение и панель целы",
		int(main._phase) == main.Phase.PLAYING
			and _selected_workers() == 3 and bool(hud._worker_boost),
		"фаза %d, рабочих в выделении %d, панель %s" % [int(main._phase),
			_selected_workers(), str(bool(hud._worker_boost))])
	# Прибираемся
	sm._clear_selection()
	GameManager.on_selection_changed(sm.selected_units)
	main._camera.set_process(true)
