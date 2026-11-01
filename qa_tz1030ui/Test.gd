extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 30.10.2026 (интерфейс, логика разблокировки, золото и тени)
## ═══════════════════════════════════════════════════════════════════════════
## A — ступени разблокировки построек рабочего (build_unlock)
## B — овцеферма строится рабочими (pen_construct), имя «Овцеферма»
## C — ступень в сохранении
## D — панель рабочего сеткой 3 + «В замок» (worker_grid_panel), замки
## E — панель армии: нет «Отрядов: N — M», бейдж = отряды, Tab раскрывает
##     один род, F1 — дверь крепости (army_count_badge)
## F — рабочие в мульти-выборе (mixed_worker_group)
## G — плотные кучи золота (gold_dense_heap), H — тень у основания (building_shadow)
## Каждая ручка проверяется и выключенной. Снимки — qa_tz1030ui/Shot (окно).

const F := Constants.FACTION_PLAYER
const _CSite := preload("res://scripts/ConstructionSite.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _SLM := preload("res://scripts/SaveLoadManager.gd")
var main = null
var sm = null
var hud = null
var fails := 0
var total := 0

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("СТОРОЖ: стенд не уложился в 240 с — НЕ ПРОШЛО")
		print("провалов: %d из %d (+сторож)" % [fails + 1, total])
		get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(name: String, ok: bool, info: String = "") -> void:
	total += 1
	if not ok:
		fails += 1
	print("%s  %s%s" % ["ПРОШЛО" if ok else "НЕ ПРОШЛО", name, ("  [" + info + "]") if info != "" else ""])

func _place(b: Building, at: Vector3, fac: int = F) -> Building:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return b

func _spawn(kind: String, at: Vector3, fac: int = F) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(F, kind)
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % 5) * 0.7, 0, float(k / 5) * 0.7))
		GameManager.add_to_squad(sid, u)
	return sid

func _members(sid: int) -> Array:
	return (GameManager.squads[sid]["members"] as Array).duplicate()

## Подтвердить режим размещения в точке — как _try_place_building после клика
func _confirm(at: Vector3) -> void:
	if main._ghost:
		main._ghost.queue_free()
		main._ghost = null
	main._ghost_mats.clear()
	main._phase = main._play_phase()
	main.hud.hide_placement_hint()
	main._placing_refund = {}
	var fn: Callable = main._placing_build_fn
	fn.call(Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z))

func _sites_of(id: String) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group(Constants.building_group(F)):
		if is_instance_valid(b) and b is _CSite and String(b.get("target_id")) == id:
			n += 1
	return n

func _placing() -> bool:
	return int(main._phase) == int(main.Phase.PLACING_BUILDING)

func _cancel_placing() -> void:
	if _placing():
		main._refund_and_cancel()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	for n in ["enemy_ai", "goblin_ai"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(F, r, 90000.0)
	sm = main.selection_manager
	hud = main.hud
	var base := Vector3(-60.0, 0.0, 60.0)
	main._clear_trees(base, 50.0)
	# Чужие постройки игрока, если сцена что-то поставила, — снести: стенду
	# нужна ступень 0
	for b in get_tree().get_nodes_in_group(Constants.building_group(F)):
		if is_instance_valid(b):
			b.queue_free()
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(base) < 70.0:
			u.queue_free()
	await frames(5)
	GameManager.build_unlock = {}
	var unlock_sig := [0]
	GameManager.build_unlock_changed.connect(func(_f, _s): unlock_sig[0] += 1)
	var workers: Array = []
	for i in range(3):
		# Как в партии (Main._spawn_starting_workers): один рабочий — один отряд
		var w := _spawn("worker", base + Vector3(2.0 + float(i), 0, 2))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
		workers.append(w)
	await pframes(4)

	# ── A. ступень 0 ──────────────────────────────────────────────────────────
	verdict("A1 ступень 0: открыта только крепость",
		GameManager.build_unlock_stage(F) == 0 and GameManager.build_unlocked(F, "castle")
		and not GameManager.build_unlocked(F, "sheep_pen") and not GameManager.build_unlocked(F, "house")
		and not GameManager.build_unlocked(F, "barracks"),
		"ступень %d" % GameManager.build_unlock_stage(F))
	var wood0: float = ResourceManager.get_amount(F, Constants.RESOURCE_WOOD)
	GameManager.try_worker_build(workers[0], "barracks")
	await frames(1)
	verdict("A2 закрытые бараки не строятся: нет режима размещения, ресурсы целы",
		not _placing() and is_equal_approx(ResourceManager.get_amount(F, Constants.RESOURCE_WOOD), wood0))
	_cancel_placing()
	verdict("A2б красный ИИ ступенями не заперт",
		GameManager.build_unlocked(Constants.FACTION_ENEMY, "barracks"))

	# ── D. панель рабочего на ступени 0 ─────────────────────────────────────
	sm.select_units([workers[0]])
	await frames(6)
	var bc: GridContainer = hud.button_container
	var door: Node = bc.get_node_or_null("WorkerShelterBtn")
	var locked_n := 0
	var lock_icons := 0
	for ch in bc.get_children():
		if ch is Button and String(ch.name).begins_with("Build_"):
			if bool(ch.get_meta("locked", false)):
				locked_n += 1
			if ch.get_node_or_null("LockIcon") != null:
				lock_icons += 1
	var castle_btn: Node = bc.get_node_or_null("Build_castle")
	verdict("D1 сетка рабочего: 4 колонки, «В замок» четвёртой в верхнем ряду",
		bc.columns == 4 and door != null and door.get_index() == 3,
		"колонок %d, дверь %d" % [bc.columns, door.get_index() if door != null else -1])
	verdict("D2 закрытые постройки — с замочком, крепость открыта",
		locked_n > 0 and lock_icons == locked_n and castle_btn != null
		and not bool(castle_btn.get_meta("locked", false)),
		"закрыто %d, замков %d" % [locked_n, lock_icons])
	verdict("D3 подписи «Рабочий N/N HP» нет", not hud.info_label.text.begins_with("Рабочий"), hud.info_label.text)
	_Opt.worker_grid_panel = false
	sm.select_units([])
	await frames(2)
	sm.select_units([workers[0]])
	await frames(6)
	bc = hud.button_container
	door = bc.get_node_or_null("WorkerShelterBtn")
	verdict("D0 ручка worker_grid_panel выключена: прежний ряд, дверь последней",
		door != null and bc.columns == bc.get_child_count() and door.get_index() == bc.get_child_count() - 1)
	_Opt.worker_grid_panel = true

	# ── A. крепость → овцеферма ────────────────────────────────────────────
	var castle: Building = _place(Castle.new(), base + Vector3(-14, 0, -20))
	await pframes(3)
	GameManager.note_building_done(F)
	verdict("A3 после крепости открыта овцеферма, дома ещё закрыты",
		GameManager.build_unlock_stage(F) == 1 and GameManager.build_unlocked(F, "sheep_pen")
		and not GameManager.build_unlocked(F, "house") and not GameManager.build_unlocked(F, "storehouse"))
	verdict("A3б сигнал build_unlock_changed пришёл", unlock_sig[0] >= 1)

	# ── B. овцеферма строится площадкой ────────────────────────────────────
	verdict("B1 загон переименован в «Овцеферма»",
		String(_UCfg.building_cfg("sheep_pen").get("name", "")) == "Овцеферма")
	GameManager.try_worker_build(workers[0], "sheep_pen", workers)
	await frames(1)
	var pen_at := base + Vector3(10, 0, -6)
	var ok_mode: bool = _placing()
	if ok_mode:
		_confirm(pen_at)
	await pframes(3)
	verdict("B2 овцеферма игрока встаёт площадкой стройки",
		ok_mode and _sites_of("sheep_pen") == 1, "площадок %d" % _sites_of("sheep_pen"))
	var pen_now := 0
	for p in get_tree().get_nodes_in_group("sheep_pens"):
		if is_instance_valid(p) and int(p.get("faction")) == F:
			pen_now += 1
	verdict("B3 готовой овцефермы до стройки нет", pen_now == 0)
	verdict("B4 стройка ещё не открыла дома", GameManager.build_unlock_stage(F) == 1)
	_Opt.pen_construct = false
	GameManager.try_worker_build(workers[1], "sheep_pen")
	await frames(1)
	if _placing():
		_confirm(base + Vector3(18, 0, -6))
	await pframes(3)
	var pen_inst := 0
	for p in get_tree().get_nodes_in_group("sheep_pens"):
		if is_instance_valid(p) and int(p.get("faction")) == F:
			pen_inst += 1
	verdict("B0 ручка pen_construct выключена: овцеферма встаёт сразу", pen_inst == 1 and _sites_of("sheep_pen") == 1)
	_Opt.pen_construct = true
	await pframes(2)
	verdict("A4 после овцефермы открыты дома и склад, бараки закрыты",
		GameManager.build_unlock_stage(F) == 2 and GameManager.build_unlocked(F, "house")
		and GameManager.build_unlocked(F, "storehouse") and not GameManager.build_unlocked(F, "barracks"))

	# ── C. сохранение ───────────────────────────────────────────────────────
	var meta: Dictionary = _SLM._capture_meta(main)
	verdict("C1 ступень пишется в сохранение", int(meta.get("build_unlock", -1)) == 2,
		str(meta.get("build_unlock", "нет")))

	# ── A. дом → всё ────────────────────────────────────────────────────────
	var house: Building = _place(load("res://scripts/House.gd").new(), base + Vector3(6, 0, -24))
	await pframes(3)
	GameManager.note_building_done(F)
	verdict("A5 после дома открыто всё", GameManager.build_unlock_stage(F) == 3
		and GameManager.build_unlocked(F, "barracks") and GameManager.build_unlocked(F, "smithy"))
	house.queue_free()
	await pframes(3)
	verdict("A6 ступень не падает, когда дом снесён", GameManager.build_unlock_stage(F) == 3)
	var keep: Dictionary = GameManager.build_unlock.duplicate()
	GameManager.build_unlock = {}
	_Opt.build_unlock = false
	var off_ok: bool = GameManager.build_unlocked(F, "barracks") and GameManager.build_unlocked(F, "sheep_pen")
	_Opt.build_unlock = true
	var on_lock: bool = not GameManager.build_unlocked(F, "barracks")
	verdict("A0 ручка build_unlock выключена: всё открыто с нуля", off_ok and on_lock)
	GameManager.build_unlock = keep
	sm.select_units([workers[0]])
	await frames(6)
	var any_locked := false
	for ch in hud.button_container.get_children():
		if bool(ch.get_meta("locked", false)):
			any_locked = true
	verdict("D4 на ступени 3 замков на панели нет", not any_locked)

	# ── E. панель армии ─────────────────────────────────────────────────────
	var s1: int = _squad("spearman", base + Vector3(-8, 0, 6), 20)
	var s2: int = _squad("spearman", base + Vector3(-14, 0, 0), 20)
	var s3: int = _squad("spearman", base + Vector3(-2, 0, 0), 20)
	var mk: int = _squad("monk", base + Vector3(8, 0, 6), 6)
	await pframes(4)
	var spears: Array = _members(s1) + _members(s2) + _members(s3)
	sm.select_units(spears)
	await frames(6)
	verdict("E1 строки «Отрядов: N — M» нет", not hud.info_label.text.begins_with("Отрядов"),
		hud.info_label.text)
	verdict("E2 бейдж портрета — число отрядов (3), а не бойцов",
		hud._portrait_count_lbl.visible and hud._portrait_count_lbl.text == "3",
		hud._portrait_count_lbl.text)
	var tab1: bool = hud.cycle_expanded_type()
	await frames(4)
	verdict("E3 Tab на одном роде раскрывает карточки отрядов",
		tab1 and hud._expanded_type == "spearman" and hud._squad_strip.get_child_count() == 3,
		"род «%s», карточек %d" % [hud._expanded_type, hud._squad_strip.get_child_count()])
	hud.cycle_expanded_type()
	await frames(4)
	verdict("E4 повторный Tab сворачивает, выделение целое",
		hud._expanded_type == "" and sm.selected_units.size() == 60)
	var f1: Control = hud._build_squad_cmd_col("F1", {})
	var f1_tex: Texture2D = null
	for ch in f1.get_children():
		if ch is TextureRect:
			f1_tex = (ch as TextureRect).texture
	verdict("E5 на [F1] — дверь крепости", f1_tex == hud._castle_door_texture())
	f1.free()
	_Opt.army_count_badge = false
	sm.select_units([])
	await frames(2)
	sm.select_units(spears)
	await frames(6)
	var f1b: Control = hud._build_squad_cmd_col("F1", {})
	var f1b_tex: Texture2D = null
	for ch in f1b.get_children():
		if ch is TextureRect:
			f1b_tex = (ch as TextureRect).texture
	f1b.free()
	verdict("E0 ручка army_count_badge выключена: строка «Отрядов», бейдж 60, F1 — крепость",
		hud.info_label.text.begins_with("Отрядов") and hud._portrait_count_lbl.text == "60"
		and f1b_tex != hud._castle_door_texture(), "%s / %s" % [hud.info_label.text, hud._portrait_count_lbl.text])
	_Opt.army_count_badge = true

	# ── F. рабочие в мульти-выборе ──────────────────────────────────────────
	var mixed: Array = _members(s1) + _members(mk) + workers
	sm.select_units([])
	await frames(2)
	sm.select_units(mixed)
	await frames(6)
	var g: Dictionary = hud._selection_groups()
	verdict("F1 рабочие — своя группа полосы родов (3)",
		(g["order"] as Array).has("worker") and int((g["squads"] as Dictionary).get("worker", 0)) == 3
		and hud._overbar.visible, str(g["order"]))
	var slot: Node = hud._overbar_row.get_node_or_null("GroupSlot_worker")
	var fig_ok := false
	if slot != null:
		for b in slot.get_children():
			var fg: Node = b.get_node_or_null("GroupFigure")
			if fg != null and (fg as TextureRect).texture != null \
					and (fg as TextureRect).texture.resource_path.ends_with("worker.png"):
				fig_ok = true
	verdict("F2 на ячейке рабочих — фигура рабочего", fig_ok)
	hud._on_type_filter_pressed("worker")
	await frames(6)
	var only_w: bool = sm.selected_units.size() == 3
	for u in sm.selected_units:
		if not (u is Worker):
			only_w = false
	verdict("F3 клик по рабочим — выделены одни рабочие, их панель построек",
		only_w and hud._worker_boost and hud.button_container.get_node_or_null("WorkerShelterBtn") != null,
		"выделено %d" % sm.selected_units.size())
	verdict("F4 полоса родов остаётся (рабочие подсвечены)",
		hud._overbar.visible and hud._expanded_type == "worker")
	# Артель строит вместе: заказ из панели — вся тройка на площадку
	GameManager.try_worker_build(sm.selected_units[0], "house", sm.selected_units.duplicate())
	await frames(1)
	if _placing():
		_confirm(base + Vector3(-4, 0, -30))
	await pframes(3)
	var on_site := 0
	for w in workers:
		if (w as Worker).build_target != null and is_instance_valid((w as Worker).build_target):
			on_site += 1
	verdict("F5 приказ строить — все три рабочих идут на площадку", on_site == 3, "%d из 3" % on_site)
	hud._on_type_filter_pressed("worker")
	await frames(6)
	verdict("F6 повторный клик возвращает всё выделение", sm.selected_units.size() == mixed.size(),
		"%d из %d" % [sm.selected_units.size(), mixed.size()])
	hud.cycle_expanded_type()
	hud.cycle_expanded_type()
	hud.cycle_expanded_type()
	await frames(4)
	verdict("F7 Tab доходит до рабочих", hud._expanded_type == "worker"
		and sm.selected_units.size() == 3, hud._expanded_type)
	_Opt.mixed_worker_group = false
	sm.select_units([])
	await frames(2)
	sm.select_units(mixed)
	await frames(6)
	# Без ручки рабочие в полосе — род их одиночных отрядов (как было), и клик
	# открывает детальную панель рода с карточками, а не панель построек
	hud._on_type_filter_pressed("worker")
	await frames(6)
	verdict("F0 ручка mixed_worker_group выключена: клик по рабочим — карточки рода, не стройка",
		hud.button_container.get_node_or_null("WorkerShelterBtn") == null,
		"род «%s», выделено %d" % [hud._expanded_type, sm.selected_units.size()])
	_Opt.mixed_worker_group = true
	# Одни рабочие (у каждого свой отряд рода «worker») — артель: панель
	# построек, полосы родов нет (qa_tz1011 B1)
	sm.select_units([])
	await frames(2)
	sm.select_units(workers.duplicate())
	await frames(6)
	verdict("F8 одни рабочие — панель построек, полосы родов нет",
		hud._worker_boost and not hud._overbar.visible
		and hud.button_container.get_node_or_null("WorkerShelterBtn") != null)
	sm.select_units([])

	# ── G. золото ───────────────────────────────────────────────────────────
	var heap_r: float = _mean_r(main.GOLD_LAYOUTS) * main.LAYOUT_SPAN_GOLD_HEAP
	var old_r: float = _mean_r(main.CLUSTER_LAYOUTS) * main.LAYOUT_SPAN_GOLD
	verdict("G1 куча золота плотнее прежнего облака (средний разнос)", heap_r < old_r * 0.8,
		"%.2f против %.2f м" % [heap_r, old_r])

	# ── H. тень у основания ─────────────────────────────────────────────────
	await frames(4)
	var sh: Node = castle.get_node_or_null("GroundShadow")
	verdict("H1 у постройки есть тень у основания", sh != null and sh is MeshInstance3D)
	_Opt.building_shadow = false
	var h2: Building = _place(load("res://scripts/House.gd").new(), base + Vector3(20, 0, -26))
	await frames(4)
	verdict("H0 ручка building_shadow выключена: тени нет", h2.get_node_or_null("GroundShadow") == null)
	_Opt.building_shadow = true

	print("провалов: %d из %d" % [fails, total])
	print("=== QA_TZ1030UI TEST DONE ===")
	get_tree().quit()

func _mean_r(layouts: Array) -> float:
	var s := 0.0
	var n := 0
	for lay in layouts:
		for p in lay:
			s += Vector2(float(p[0]), float(p[1])).length()
			n += 1
	return s / maxf(1.0, float(n))
