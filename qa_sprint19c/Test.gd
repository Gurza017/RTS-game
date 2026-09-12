extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_sprint19c — ПИСЬМО 12: ЭКОНОМИКА РАБОЧИХ, СТРОЙКА, SHIFT, МОНАХИ
## ═══════════════════════════════════════════════════════════════════════════
##   A ЭКОНОМИКА — рабочий на старте медленнее прежнего и учится дольше;
##                 кузница даёт обучение (bonus_train режет найм), удар (3c).
##   B ЗАЩИТА    — ударили рабочего — соседи бросают работу и идут на
##                 обидчика; на армию (много чужих рядом) артель не кидается.
##   C СТРОЙКА   — рабочий с рубки на стройку: у стены лента молотка, а не
##                 бега; четверо у фасада встают все и вдоль стены, а не в
##                 одной точке.
##   D АРТЕЛЬ    — трое по ПКМ на одну овцу расходятся по трём овцам.
##   E SHIFT     — очередь площадок у строителя; клик по интерфейсу в режиме
##                 размещения фантом не ставит; Shift повторяет заказ.
##   F МОНАХ     — не дерётся; два монаха расходятся на MONK_SPACING; лечение
##                 одиночное медленное, «Благодать» вдвое медленнее каждого;
##                 воскрешение (monk_3d): павший встаёт с 1 HP в свой отряд,
##                 вспышка, тело снято; опыт за лечение; ауры по наградам.
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_sprint19c/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _Forge  := preload("res://scripts/forge_config.gd")
const _Sheep  := preload("res://scripts/goblin/Sheep.gd")
const _CSite  := preload("res://scripts/ConstructionSite.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _castle: Castle = null

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(560.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 560 с")
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
	print("\n═════ ИТОГ qa_sprint19c: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = _g(at)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, fac: int, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(uid, fac, at + Vector3(float(i % 5) * 0.7, 0.0, float(i / 5) * 0.7))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _site(id: String, at: Vector3, secs: float = 9999.0) -> Building:
	var site: Building = _CSite.new()
	site.faction = Constants.FACTION_PLAYER
	site.target_id = id
	site.target_name = id
	site.build_time = secs
	site.build_size = _UCfg.building_size(id)
	main.world_add(site)
	site.global_position = _g(at)
	return site

func _wild_sheep(at: Vector3) -> Node3D:
	var s: Node3D = _Sheep.new()
	s.set("home", at)
	main.world_root().add_child(s)
	s.global_position = _g(at)
	s.call("bind_to_keep", _castle, Constants.FACTION_PLAYER)
	s.set("home", at)
	s.set_process(false)
	return s

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _clear_trees(at: Vector3, r: float) -> void:
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn0 := n0 as ResourceNode
		if rn0 != null and is_instance_valid(rn0) and _xz(rn0.global_position, at) < r:
			rn0.queue_free()

func _free_all(arr: Array) -> void:
	for n in arr:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	var lair = GameManager.troll_lair
	if lair != null and is_instance_valid(lair):
		for t in lair.get("trolls"):
			if is_instance_valid(t):
				(t as Unit).set_tick(false)
		for g in lair.get("gnolls"):
			if g != null and is_instance_valid(g):
				(g as Node).queue_free()
	_castle = Castle.new()
	_castle.faction = Constants.FACTION_PLAYER
	main.world_add(_castle)
	var cp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, 26.0)
	_castle.global_position = _g(cp)
	await pframes(6)

	await _a_economy()
	await _b_rally()
	await _c_build()
	await _d_crew_sheep()
	await _e_shift()
	await _f_monks()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_economy() -> void:
	print("\n═════ A. ЭКОНОМИКА РАБОЧИХ И КУЗНИЦА ═════")
	var st: Dictionary = _UCfg.get_stats("worker")
	verdict("A1 рабочий на старте медленный: %.1f м/с без груза (< 3.0), %.1f с цикл (> 5), %.0f за ходку (< 6)" % [
			float(st.get("walk_speed_empty", 0.0)), float(st.get("gather_time", 0.0)), float(st.get("gather_amount", 0.0))],
		float(st.get("walk_speed_empty", 9.0)) < 3.0 and float(st.get("gather_time", 0.0)) > 5.0
			and float(st.get("gather_amount", 9.0)) < 6.0)
	var tt: float = float(_UCfg.TRAINING["castle"]["worker"]["time"])
	verdict("A2 обучение рабочего дольше прежних 10 с (%.0f с)" % tt, tt > 10.0)
	var cells: Array = ["1d", "2d", "3d", "4d", "5d"]
	var train_cells := 0
	var build_cells := 0
	for c in cells:
		var node: Dictionary = _Forge.get_node(_Forge.node_id("worker", c))
		if float(node.get("bonus_train", 0.0)) > 0.0:
			train_cells += 1
		if float(node.get("bonus_build", 0.0)) > 0.0:
			build_cells += 1
	verdict("A3 колонка D рабочего — обучение (%d узлов) и стройка (%d узлов)" % [train_cells, build_cells],
		train_cells >= 4 and build_cells >= 3)
	var atk_cells := 0
	for c2 in ["3c", "4c", "5c"]:
		if float(_Forge.get_node(_Forge.node_id("worker", c2)).get("bonus_attack", 0.0)) > 0.0:
			atk_cells += 1
	verdict("A4 колонка C даёт удар (%d узлов)" % atk_cells, atk_cells == 3)
	# Найм: bonus_train режет время заказа
	var pf: int = Constants.FACTION_PLAYER
	ResourceManager.add_resource(pf, Constants.RESOURCE_WOOD, 500.0)
	_castle.production_queue.clear()
	GameManager.pop_limit_enabled = false
	_castle.train_from_config("worker")
	var t0: float = float(_castle.production_queue[-1]["time"]) if not _castle.production_queue.is_empty() else -1.0
	GameManager.finish_research(pf, _Forge.node_id("worker", "1d"))
	_castle.train_from_config("worker")
	var t1: float = float(_castle.production_queue[-1]["time"]) if not _castle.production_queue.is_empty() else -1.0
	verdict("A5 «Артельный подряд» ускорил найм: %.1f → %.1f с" % [t0, t1], t1 > 0.0 and t1 < t0 - 0.5)
	_castle.production_queue.clear()
	var w: Worker = _spawn("worker", pf, main.PLAYER_BASE_ANCHOR + Vector3(30.0, 0.0, 30.0)) as Worker
	await pframes(2)
	var d0: float = w._upgrade_damage_bonus()
	GameManager.finish_research(pf, _Forge.node_id("worker", "3c"))
	var d1: float = w._upgrade_damage_bonus()
	verdict("A6 узел 3c прибавил удар рабочему (%.1f → %.1f)" % [d0, d1], d1 > d0)
	w.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
func _b_rally() -> void:
	print("\n═════ B. АВТО-ЗАЩИТА БАЗЫ АРТЕЛЬЮ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-40.0, 0.0, 40.0)
	var crew: Array = []
	for i in range(5):
		crew.append(_spawn("worker", Constants.FACTION_PLAYER, base + Vector3(float(i) * 2.0, 0.0, 0.0)))
	# Враг ДАЛЬШЕ радиуса агро (10 м): сбор идёт по удару, а не по авто-агро
	var foe: Unit = _spawn("goblin_rider", Constants.FACTION_GOBLIN, base + Vector3(4.0, 0.0, 12.0))
	foe.set_tick(false)
	await pframes(2)
	var r0: int = GameManager.worker_rallies
	(crew[0] as Unit).take_damage(5.0, foe)
	await pframes(3)
	var on_foe := 0
	for c in crew:
		if (c as Unit).attack_target == foe:
			on_foe += 1
	verdict("B1 удар по рабочему поднял артель: %d из 5 идут на обидчика" % on_foe,
		on_foe >= 4 and GameManager.worker_rallies == r0 + 1)
	_free_all(crew)
	foe.queue_free()
	await pframes(3)
	# Большая угроза — артель не кидается
	var crew2: Array = []
	for i in range(4):
		crew2.append(_spawn("worker", Constants.FACTION_PLAYER, base + Vector3(float(i) * 2.0, 0.0, 30.0)))
	var horde: Array = []
	for k in range(7):
		var h: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, base + Vector3(float(k) * 1.2, 0.0, 36.0))
		h.set_tick(false)
		horde.append(h)
	await pframes(2)
	var r1: int = GameManager.worker_rallies
	GameManager.set("_worker_rally_ms", {})
	(crew2[0] as Unit).take_damage(5.0, horde[0])
	await pframes(3)
	var on2 := 0
	for c in crew2:
		if c != crew2[0] and (c as Unit).attack_target != null:
			on2 += 1
	verdict("B2 на семерых чужих артель не кидается (пошли %d, сборов +%d)" % [on2, GameManager.worker_rallies - r1],
		GameManager.worker_rallies == r1)
	_free_all(crew2)
	_free_all(horde)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _c_build() -> void:
	print("\n═════ C. СТРОЙКА: С РУБКИ — МОЛОТОК У СТЕНЫ, АРТЕЛЬ ВДОЛЬ ФАСАДА ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, -40.0)
	_clear_trees(base, 30.0)
	await pframes(3)
	# Дерево ставим сами
	var tree: ResourceNode = null
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n0 as ResourceNode
		if rn != null and is_instance_valid(rn) and rn.resource_type == Constants.RESOURCE_WOOD:
			tree = rn
			break
	var w: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(0.0, 0.0, 12.0)) as Worker
	await pframes(2)
	var chopping := false
	if tree != null:
		tree.global_position = _g(base + Vector3(3.0, 0.0, 12.0))
		w.command_gather(tree)
		for _i in range(60 * 12):
			await get_tree().physics_frame
			if w.state == Unit.State.GATHERING:
				chopping = true
				break
	verdict("C0 рабочий рубит дерево (исходное состояние)", chopping)
	var site: Building = _site("barracks", base)
	w.command_build(site)
	var settled := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if bool(w.get("_build_settled")):
			settled = true
			break
	# Добор вплотную (SETTLE_SPEED) — тоже шаг; ждём, пока он кончится
	for _i in range(60 * 5):
		await get_tree().physics_frame
		if not w.moved_recently():
			break
	w.call("_update_sprite_anim")
	verdict("C1 с рубки на стройку: дошёл и встал (settled)", settled)
	verdict("C2 у стены — лента МОЛОТКА, а не бега (лента %s, шаг %s)" % [String(w.get("_anim_name")), str(w.moved_recently())],
		String(w.get("_anim_name")) == "build" and not w.moved_recently())
	# Четверо с лицевой стороны: все встают, и вдоль стены
	var crew: Array = []
	for i in range(4):
		crew.append(_spawn("worker", Constants.FACTION_PLAYER, base + Vector3(float(i) * 1.5 - 2.0, 0.0, 10.0)))
	await pframes(2)
	for c in crew:
		(c as Worker).command_build(site)
	var all_in := false
	for _i in range(60 * 25):
		await get_tree().physics_frame
		if site.builder_count() >= 5:
			all_in = true
			break
	var xs: Array = []
	var worst_z := 0.0
	for c in crew:
		var p: Vector3 = (c as Node3D).global_position - site.global_position
		xs.append(snappedf(p.x, 0.5))
		worst_z = maxf(worst_z, p.z)
	var distinct: Dictionary = {}
	for x in xs:
		distinct[x] = true
	verdict("C3 все четверо встали в артель (строителей %d)" % site.builder_count(), all_in)
	verdict("C4 стоят вдоль стены, а не в одной точке: разных x %d из 4, худший вынос %.2f м" % [distinct.size(), worst_z],
		distinct.size() >= 3 and worst_z <= _CSite.FRONT_EDGE + _CSite.WORK_PAD + Worker.BUILD_ARRIVE_PAD + 0.3)
	_free_all(crew)
	w.queue_free()
	site.queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _d_crew_sheep() -> void:
	print("\n═════ D. АРТЕЛЬ ПО ОВЦАМ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-40.0, 0.0, -40.0)
	var sheep: Array = []
	for i in range(3):
		sheep.append(_wild_sheep(base + Vector3(float(i) * 6.0, 0.0, 0.0)))
	var crew: Array = []
	for i in range(3):
		crew.append(_spawn("worker", Constants.FACTION_PLAYER, base + Vector3(float(i) * 1.5, 0.0, 8.0)))
	await pframes(2)
	for c in crew:
		(c as Worker).command_steal_sheep(sheep[0])
	var spread := false
	for _i in range(60 * 30):
		await get_tree().physics_frame
		var tg: Dictionary = {}
		var n := 0
		for c in crew:
			var s = (c as Node).get("_sheep")
			if s != null and is_instance_valid(s):
				tg[s.get_instance_id()] = true
				n += 1
		if n == 3 and tg.size() == 3:
			spread = true
			break
	verdict("D1 трое по ПКМ на одну овцу разошлись по трём разным овцам", spread)
	_free_all(crew)
	_free_all(sheep)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _e_shift() -> void:
	print("\n═════ E. ОЧЕРЕДЬ SHIFT И КЛИК ПО ИНТЕРФЕЙСУ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, 0.0)
	_clear_trees(base, 30.0)
	await pframes(2)
	var w: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(0.0, 0.0, 10.0)) as Worker
	var s1: Building = _site("house", base, 3.0)
	var s2: Building = _site("house", base + Vector3(14.0, 0.0, 0.0), 3.0)
	await pframes(2)
	w.command_build(s1)
	w.command_build(s2, true)
	verdict("E1 вторая площадка под Shift встала в очередь (в очереди %d, цель — первая)" % w.build_queue_size(),
		w.build_queue_size() == 1 and w.build_target == s1)
	var moved := false
	for _i in range(60 * 40):
		await get_tree().physics_frame
		if w.build_target == s2:
			moved = true
			break
	verdict("E2 достроив первую, рабочий сам пошёл на вторую", moved)
	w.command_move(base + Vector3(0.0, 0.0, 20.0))
	verdict("E3 приказ на движение снимает очередь", w.build_queue_size() == 0)
	# ── Режим размещения: клик по интерфейсу фантом не ставит ─────────────
	var sm = main.selection_manager
	sm.selected_units = [w]
	GameManager.on_selection_changed(sm.selected_units, true)
	var pf: int = Constants.FACTION_PLAYER
	ResourceManager.add_resource(pf, Constants.RESOURCE_WOOD, 5000.0)
	ResourceManager.add_resource(pf, Constants.RESOURCE_GOLD, 5000.0)
	ResourceManager.add_resource(pf, Constants.RESOURCE_STONE, 5000.0)
	var placed0: int = main.placements_done
	GameManager.try_worker_build(w, "house")
	await frames(2)
	verdict("E4 заказ дома открыл режим размещения", int(main.get("_phase")) == main.Phase.PLACING_BUILDING)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ui_pt := Vector2(-1, -1)
	for y in range(4, int(vp.y), 8):
		for x in range(4, int(vp.x), 16):
			if main.hud.point_over_ui(Vector2(x, y)):
				ui_pt = Vector2(x, y)
				break
		if ui_pt.x >= 0:
			break
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = ui_pt
	main._input(ev)
	await frames(1)
	verdict("E5 клик по панели (%s) фантом не ставит: размещений %d, режим остался" % [str(ui_pt), main.placements_done - placed0],
		ui_pt.x >= 0 and main.placements_done == placed0 and int(main.get("_phase")) == main.Phase.PLACING_BUILDING)
	# Переключение типа постройки из режима размещения — без сквозного клика
	GameManager.try_worker_build(w, "house2")
	await frames(1)
	verdict("E6 повторный заказ другого дома переключил фантом, режим один",
		int(main.get("_phase")) == main.Phase.PLACING_BUILDING and main.placements_done == placed0)
	# ── Shift: постановка повторяет заказ ──────────────────────────────────
	var cam: Camera3D = main.get("_camera")
	var target_w: Vector3 = _g(base + Vector3(-20.0, 0.0, 0.0))
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	await frames(1)
	var scr: Vector2 = cam.unproject_position(target_w)
	main.call("_try_place_building", scr)
	await frames(2)
	var again: bool = int(main.get("_phase")) == main.Phase.PLACING_BUILDING
	verdict("E7 с зажатым Shift после постановки (%d) фантом встал снова" % (main.placements_done - placed0),
		main.placements_done == placed0 + 1 and again and Input.is_key_pressed(KEY_SHIFT))
	# Второй фантом — тоже под Shift: площадка встаёт строителю в очередь
	if int(main.get("_phase")) == main.Phase.PLACING_BUILDING:
		main.call("_try_place_building", cam.unproject_position(_g(base + Vector3(-20.0, 0.0, 14.0))))
	await frames(2)
	var q2: int = w.build_queue_size()
	var shift_up := InputEventKey.new()
	shift_up.keycode = KEY_SHIFT
	shift_up.physical_keycode = KEY_SHIFT
	shift_up.pressed = false
	Input.parse_input_event(shift_up)
	await frames(1)
	main.call("_cancel_or_keep_placing")
	await frames(1)
	verdict("E8 второй фантом под Shift встал в очередь строителя (%d), Shift отпущен — режим закрыт" % q2,
		q2 >= 1 and int(main.get("_phase")) != main.Phase.PLACING_BUILDING)
	sm.selected_units = []
	w.queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _f_monks() -> void:
	print("\n═════ F. МОНАХИ ═════")
	var pf: int = Constants.FACTION_PLAYER
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-70.0, 0.0, 0.0)
	_clear_trees(base, 30.0)
	var monks: Array = []
	for i in range(2):
		monks.append(_squad("monk", pf, base + Vector3(float(i) * 1.0, 0.0, 0.0), 1)[0])
	var m: Monk = monks[0]
	await pframes(3)
	verdict("F1 монах не дерётся: урон 0, не боевой", m.attack_damage <= 0.0 and not m.is_combatant()
		and not GameManager.squad_is_combat(m.squad_id))
	var foe: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, base + Vector3(2.0, 0.0, 3.0))
	foe.set_tick(false)
	m.command_attack(foe, true, false, true)
	await pframes(60)
	verdict("F2 приказ атаки монах не принимает (цели нет)", m.attack_target == null)
	foe.queue_free()
	# Дистанция между монахами
	var d_before: float = _xz((monks[0] as Node3D).global_position, (monks[1] as Node3D).global_position)
	for _i in range(60 * 6):
		await get_tree().physics_frame
	var d_after: float = _xz((monks[0] as Node3D).global_position, (monks[1] as Node3D).global_position)
	verdict("F3 два монаха разошлись: %.1f → %.1f м (≥ %.0f − 1)" % [d_before, d_after, _UCfg.MONK_SPACING],
		d_after >= _UCfg.MONK_SPACING - 1.0 and d_after > d_before + 1.5)
	(monks[1] as Node).queue_free()
	await pframes(2)
	# ── Одиночное лечение медленное ─────────────────────────────────────
	var sp: Array = _squad("spearman", pf, base + Vector3(2.5, 0.0, 0.0), 1)
	var pat: Unit = sp[0]
	pat.current_health = pat.max_health * 0.5
	pat._soa_push_stats()
	var t_start: int = Engine.get_physics_frames()
	var healed_at := -1
	for _i in range(60 * 40):
		await get_tree().physics_frame
		if pat.current_health >= pat.max_health - 0.5:
			healed_at = Engine.get_physics_frames() - t_start
			break
	var expect: float = _UCfg.MONK_HEAL_SEC_PER_MAN * 0.5
	verdict("F4 половина запаса одиночным лечением за %.1f с (ожидание ~%.0f с, не быстрее %.0f)" % [
			float(healed_at) / 60.0, expect, expect * 0.7],
		healed_at > 0 and float(healed_at) / 60.0 >= expect * 0.7)
	# ── Благодать (2d): отряд разом, каждый вдвое медленнее ──────────────
	GameManager.finish_research(pf, _Forge.node_id("monk", "2d"))
	verdict("F6 «Благодать» — узел 2d, переключатель", m.aoe_active())
	var grp: Array = _squad("warrior", pf, base + Vector3(0.0, 0.0, 3.0), 4)
	for u in grp:
		(u as Unit).current_health = (u as Unit).max_health * 0.5
		(u as Unit)._soa_push_stats()
	var t2: int = Engine.get_physics_frames()
	var all_at := -1
	for _i in range(60 * 60):
		await get_tree().physics_frame
		var ok := true
		for u in grp:
			if (u as Unit).current_health < (u as Unit).max_health - 0.5:
				ok = false
		if ok:
			all_at = Engine.get_physics_frames() - t2
			break
	verdict("F7 отряд из четверых вылечен разом за %.1f с (не быстрее %.0f с: вдвое медленнее одиночного)" % [
			float(all_at) / 60.0, expect * 2.0 * 0.7],
		all_at > 0 and float(all_at) / 60.0 >= expect * 2.0 * 0.7 and m.aoe_touched >= 3)
	GameManager.squad_set_ability(m.squad_id, "monk_2d", false)
	verdict("F5 опыт за лечение (%.0f HP): зачётов %d, убийств у отряда %d" % [m.healed_total, m.heal_xp_kills, GameManager.squad_kills(m.squad_id)],
		m.heal_xp_kills >= 1 and GameManager.squad_kills(m.squad_id) >= 1)
	# ── Воскрешение (3d) ─────────────────────────────────────────────────
	var victim: Unit = grp[0]
	var vsid: int = victim.squad_id
	var vpos: Vector3 = victim.global_position
	var corpses0: int = GameManager.corpses.raisable_count(pf)
	victim.take_damage(1.0e9, null)
	await pframes(3)
	verdict("F8 павший оставил тело, годное к подъёму (+%d)" % (GameManager.corpses.raisable_count(pf) - corpses0),
		GameManager.corpses.raisable_count(pf) == corpses0 + 1)
	await pframes(60 * 3)
	verdict("F9 без исследования монах павших не поднимает", m.resurrected_total == 0 and m.res_target() == null)
	GameManager.finish_research(pf, _Forge.node_id("monk", "3d"))
	var channel := false
	var raised := false
	var res_frames := 0
	for _i in range(60 * 60):
		await get_tree().physics_frame
		if m.res_target() != null:
			channel = true
			res_frames += 1
		if m.resurrected_total >= 1:
			raised = true
			break
	verdict("F10 с «Воскрешением» монах подошёл и вёл канал (%d кадров ≈ %.0f с, срок %.0f с)" % [
			res_frames, float(res_frames) / 60.0, m.res_sec()],
		channel and float(res_frames) / 60.0 >= m.res_sec() * 0.8)
	verdict("F11 павший поднят: тел −1, вспышка %d" % m.res_flashes,
		raised and GameManager.corpses.raisable_count(pf) == corpses0 and m.res_flashes == 1)
	var risen: Unit = null
	for n in get_tree().get_nodes_in_group("all_units"):
		var u := n as Unit
		if u != null and is_instance_valid(u) and not u.is_dead() and u.faction == pf \
				and u.stat_id == "warrior" and u.squad_id == vsid and not grp.has(u):
			risen = u
	verdict("F12 поднятый — воин в СВОЁМ отряде, у тела, с 1 HP", risen != null
		and _xz(risen.global_position, vpos) < 3.0 and risen.max_health > 5.0,
		"найден %s" % str(risen != null))
	var hp_at_rise: float = risen.current_health if risen != null else -1.0
	await pframes(60 * 4)
	verdict("F13 монах лечит поднятого: %.1f → %.1f" % [hp_at_rise, risen.current_health if risen != null else -1.0],
		risen != null and hp_at_rise <= 2.0 and risen.current_health > hp_at_rise)
	# ── Ауры по наградам ─────────────────────────────────────────────────
	var choices: Array = _UCfg.veteran_choices("monk", 1)
	var aura_ids: Dictionary = {}
	for c in choices:
		aura_ids[String((c as Dictionary).get("id", ""))] = true
	verdict("F14 награды монаха — ауры (%s)" % str(aura_ids.keys()),
		choices.size() == 3 and aura_ids.has("aura_armor") and aura_ids.has("aura_attack"))
	var b: Dictionary = GameManager.squads[m.squad_id]["bonuses"]
	b["aura_attack"] = 2.0
	b["aura_armor"] = 1.0
	b["aura_rate"] = 0.1
	var arc: Array = _squad("archer", pf, base + Vector3(-2.0, 0.0, 2.0), 1)
	var ar: Unit = arc[0]
	var cd0: float = ar._effective_cooldown()
	var dmg0: float = (grp[1] as Unit)._upgrade_damage_bonus()
	await pframes(60 * 2)
	verdict("F15 аура удара: мечник рядом +2 к удару (%.1f → %.1f), аура действует" % [dmg0, (grp[1] as Unit)._upgrade_damage_bonus()],
		(grp[1] as Unit).aura_active() and (grp[1] as Unit)._upgrade_damage_bonus() >= dmg0 + 2.0 - 0.01)
	verdict("F16 аура скорострельности: перезарядка лучника %.2f → %.2f" % [cd0, ar._effective_cooldown()],
		ar._effective_cooldown() < cd0 - 0.01)
	m.command_move(base + Vector3(0.0, 0.0, -40.0), false, Vector3.ZERO, false, true)
	await pframes(60 * 4)
	verdict("F17 монах ушёл — аура гаснет (%.1f с срок)" % (float(_UCfg.MONK_AURA_HOLD_MS) / 1000.0),
		not (grp[1] as Unit).aura_active())
	_free_all(grp)
	_free_all(arc)
	_free_all(sp)
	if risen != null and is_instance_valid(risen):
		risen.queue_free()
	m.queue_free()
	await pframes(3)
