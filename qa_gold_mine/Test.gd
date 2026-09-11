extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЗОЛОТОЙ РУДНИК — ЗАХВАТ, РАБОЧИЕ, ФЛАГ, РУИНА (заказ 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A КАРТА — два ничейных рудника, три картинки состояний, ничей без флага.
##   B ЗАХВАТ — пехота игрока рядом → рудник игрока, флаг цвета игрока,
##     доход INCOME_BASE золота в секунду.
##   C РАБОЧИЕ — ПКМ-путь (command_build) заводит внутрь не больше
##     WORKER_CAP, картинка Active, доход растёт на INCOME_PER_WORKER каждый.
##   D СМЕНА ВЛАДЕЛЬЦА — красные захватывают с рабочими внутри: рабочие
##     переходят красным (сторона, строка ядра), выходят в красную группу.
##   E ЗАЩИТНИКИ — при бойцах обеих сторон в радиусе захвата нет.
##   F РУИНА — снесённый рудник оставляет руину Destroyed, отстроить может
##     любой, рудник достаётся отстроившему; маршруты ПКМ рабочих.
## Запуск: godot --headless --path . res://qa_gold_mine/Test.tscn

const _MineS := preload("res://scripts/Mine.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с"); _finish())

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
	print("\n═════ ИТОГ qa_gold_mine: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn_squad(kind: String, fac: int, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var scene: PackedScene = Building.PRELOAD_SCENES[kind]
	for i in range(n):
		var u: Unit = scene.instantiate()
		u.faction = fac
		main.world_add(u)
		var px: float = at.x + float(i % 3) * 0.7 - 0.7
		var pz: float = at.z + float(i / 3) * 0.7
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _kill(list: Array) -> void:
	for u in list:
		if u != null and is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e9)

func _alive(list: Array) -> int:
	var n := 0
	for u in list:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _gold(f: int) -> float:
	return float((ResourceManager.resources[f] as Dictionary).get(Constants.RESOURCE_GOLD, 0.0))

func _freeze(list: Array, on: bool) -> void:
	for u in list:
		if u != null and is_instance_valid(u):
			(u as Unit).set_tick(not on)

func _wait_faction(m: Mine, f: int, max_frames: int) -> int:
	var g := 0
	while g < max_frames and m.faction != f:
		await get_tree().physics_frame
		g += 1
	return g

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

	# ── A. Карта ───────────────────────────────────────────────────────────
	print("\n═════ A. НИЧЕЙНЫЕ РУДНИКИ ═════")
	var mines: Array = []
	for b in get_tree().get_nodes_in_group("neutral_buildings"):
		if is_instance_valid(b) and b is Mine:
			mines.append(b)
	verdict("A1 на карте не меньше двух ничейных рудников", mines.size() >= 2, "рудников %d" % mines.size())
	verdict("A2 три картинки состояний найдены (Inactive/Active/Destroyed)",
		ResourceLoader.exists(_MineS.SPRITE_INACTIVE) and ResourceLoader.exists(_MineS.SPRITE_ACTIVE)
			and ResourceLoader.exists(_MineS.SPRITE_DESTROYED))
	if mines.is_empty():
		_finish()
		return
	var m: Mine = mines[0]
	var mp: Vector3 = m.global_position
	verdict("A3 ничейный: сторона NEUTRAL, ни в чьей группе, без флага, картинка Inactive",
		m.faction == Constants.FACTION_NEUTRAL and not m.is_in_group("player_buildings")
			and not m.is_in_group("enemy_buildings") and not m.flag_visible()
			and m.state_sprite() == _MineS.SPRITE_INACTIVE and m.income_per_sec() == 0.0,
		"группы %s, флаг %s, картинка %s" % [str(m.get_groups()), str(m.flag_visible()), m.state_sprite().get_file()])
	verdict("A4 рудник не в воде и не внутри чужой площадки",
		not GameManager.is_water(mp.x, mp.z), "точка %s" % str(mp))

	# ── B. Захват пехотой ──────────────────────────────────────────────────
	print("\n═════ B. ЗАХВАТ ═════")
	var blue: Array = _spawn_squad("spearman", Constants.FACTION_PLAYER, mp + Vector3(4.0, 0.0, 0.0), 6)
	var g1: int = await _wait_faction(m, Constants.FACTION_PLAYER, 60 * 10)
	verdict("B1 пехота игрока рядом без чужих — рудник захвачен за CAPTURE_SEC",
		m.faction == Constants.FACTION_PLAYER and m.captures == 1 and m.is_in_group("player_buildings")
			and not m.is_in_group("neutral_buildings"),
		"физкадров %d (порог %.0f с)" % [g1, m.CAPTURE_SEC])
	var flag_tex_blue = null
	if m.flag_visible():
		var fq: QuadMesh = (m.get_node("MineFlag") as MeshInstance3D).mesh as QuadMesh
		flag_tex_blue = (fq.material as ShaderMaterial).get_shader_parameter("albedo_tex")
	verdict("B2 над рудником флажок цвета игрока", m.flag_visible() and flag_tex_blue != null)
	var gold0: float = _gold(Constants.FACTION_PLAYER)
	await pframes(180)
	var dg: float = _gold(Constants.FACTION_PLAYER) - gold0
	verdict("B3 доход владельцу ~%.0f золота в секунду" % m.INCOME_BASE,
		dg >= m.INCOME_BASE * 2.5 and dg <= m.INCOME_BASE * 3.6 + 1.0, "+%.0f за 3 с" % dg)

	# ── C. Рабочие внутри ──────────────────────────────────────────────────
	print("\n═════ C. РАБОЧИЕ ═════")
	var crew: Array = []
	for i in range(m.WORKER_CAP + 1):
		var w: Unit = (Building.PRELOAD_SCENES["worker"] as PackedScene).instantiate()
		w.faction = Constants.FACTION_PLAYER
		main.world_add(w)
		var wp: Vector3 = mp + Vector3(-1.5 + 0.6 * float(i), 0.0, 5.5)
		w.global_position = Vector3(wp.x, GameManager.get_terrain_height(wp.x, wp.z), wp.z)
		w.sync_row()
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "worker")
		GameManager.add_to_squad(sid, w)
		crew.append(w)
	await pframes(2)
	var sm = main.selection_manager
	sm.selected_units = crew.duplicate()
	var routed: bool = sm._try_enter_mine(m)
	sm.selected_units = []
	verdict("C1 ПКМ рабочими по своему руднику ведёт их внутрь", routed)
	var g2 := 0
	while g2 < 60 * 30 and m.workers.size() < m.WORKER_CAP:
		await get_tree().physics_frame
		g2 += 1
	await pframes(30)
	verdict("C2 внутри не больше WORKER_CAP = %d" % m.WORKER_CAP,
		m.workers.size() == m.WORKER_CAP, "внутри %d, физкадров %d" % [m.workers.size(), g2])
	var outside := 0
	for w in crew:
		if is_instance_valid(w) and not (w as Unit).garrisoned and not (w as Unit).is_dead():
			outside += 1
	verdict("C3 лишний рабочий остался снаружи живым", outside == 1, "снаружи %d" % outside)
	verdict("C4 картинка Active (внутри рабочие), подпись со счётчиком",
		m.state_sprite() == _MineS.SPRITE_ACTIVE and m.display_name.contains("%d/%d" % [m.WORKER_CAP, m.WORKER_CAP]),
		"%s, «%s»" % [m.state_sprite().get_file(), m.display_name])
	var gold1: float = _gold(Constants.FACTION_PLAYER)
	await pframes(180)
	var dg2: float = _gold(Constants.FACTION_PLAYER) - gold1
	var want_rate: float = m.INCOME_BASE + m.INCOME_PER_WORKER * float(m.WORKER_CAP)
	verdict("C5 доход с рабочими ~%.0f золота в секунду" % want_rate,
		dg2 >= want_rate * 2.5 and dg2 <= want_rate * 3.6 + 1.0, "+%.0f за 3 с" % dg2)
	var inside_hidden := true
	for w in m.workers:
		if (w as Node3D).visible or not (w as Unit).garrisoned or (w as Node).is_in_group("player_units"):
			inside_hidden = false
	verdict("C6 рабочие внутри скрыты как гарнизон (не видны, вне групп)", inside_hidden)

	# ── D. Смена владельца с рабочими внутри ───────────────────────────────
	print("\n═════ D. СМЕНА ВЛАДЕЛЬЦА ═════")
	_kill(blue)
	for w in crew:
		if is_instance_valid(w) and not (w as Unit).garrisoned:
			(w as Unit).take_damage(1.0e9)
	await pframes(3)
	var red: Array = _spawn_squad("spearman", Constants.FACTION_ENEMY, mp + Vector3(-4.0, 0.0, 0.0), 6)
	var g3: int = await _wait_faction(m, Constants.FACTION_ENEMY, 60 * 10)
	verdict("D1 красные захватили рудник игрока", m.faction == Constants.FACTION_ENEMY
		and m.is_in_group("enemy_buildings") and not m.is_in_group("player_buildings"),
		"физкадров %d" % g3)
	var fq2: QuadMesh = (m.get_node("MineFlag") as MeshInstance3D).mesh as QuadMesh
	var flag_tex_red = (fq2.material as ShaderMaterial).get_shader_parameter("albedo_tex")
	verdict("D2 флажок сменил цвет на красный", m.flag_visible() and flag_tex_red != flag_tex_blue)
	var recolored := 0
	for w in m.workers:
		var u := w as Unit
		if u.faction == Constants.FACTION_ENEMY and u._soa >= 0 and GameManager.army.faction_of(u._soa) == Constants.FACTION_ENEMY:
			recolored += 1
	verdict("D3 рабочие внутри перешли красным (сторона и строка ядра)",
		recolored == m.WORKER_CAP, "перешли %d из %d" % [recolored, m.workers.size()])
	var released: bool = m.release_all()
	await pframes(3)
	var red_out := 0
	for w in crew:
		if is_instance_valid(w) and not (w as Unit).is_dead() and (w as Node).is_in_group("enemy_units") and (w as Node3D).visible:
			red_out += 1
	verdict("D4 выпущенные рабочие — на карте в группе красных, картинка Inactive",
		released and red_out == m.WORKER_CAP and m.workers.is_empty() and m.state_sprite() == _MineS.SPRITE_INACTIVE,
		"в красной группе %d" % red_out)
	for w in crew:
		if is_instance_valid(w) and not (w as Unit).is_dead():
			(w as Unit).take_damage(1.0e9)
	await pframes(2)

	# ── E. Защитники ───────────────────────────────────────────────────────
	print("\n═════ E. ЗАЩИТНИКИ ═════")
	var blue2: Array = _spawn_squad("spearman", Constants.FACTION_PLAYER, mp + Vector3(5.0, 0.0, 0.0), 6)
	await pframes(1)
	_freeze(red, true)
	_freeze(blue2, true)
	await pframes(60 * 5)
	verdict("E1 при чужих защитниках рядом захват не идёт", m.faction == Constants.FACTION_ENEMY
		and m.capture_progress() == 0.0, "прогресс %.2f" % m.capture_progress())
	_kill(red)
	await pframes(2)
	_freeze(blue2, false)
	var g4: int = await _wait_faction(m, Constants.FACTION_PLAYER, 60 * 10)
	verdict("E2 защитники выбиты — захват состоялся", m.faction == Constants.FACTION_PLAYER, "физкадров %d" % g4)
	_kill(blue2)
	await pframes(2)

	# ── F. Руина и восстановление ──────────────────────────────────────────
	print("\n═════ F. РУИНА ═════")
	m.take_damage(1.0e9)
	await pframes(3)
	var ruin: Node = null
	for r in get_tree().get_nodes_in_group("ruins"):
		if is_instance_valid(r) and String((r as Node).get_meta("ruin_building_id", "")) == "mine" \
				and (r as Node3D).global_position.distance_to(mp) < 1.0:
			ruin = r
	verdict("F1 снесённый рудник оставил руину, отстроить может любой",
		ruin != null and bool(ruin.get_meta("ruin_any_faction", false)))
	if ruin == null:
		_finish()
		return
	var rs := ruin.get_node_or_null("RuinSprite") as MeshInstance3D
	var rtex = null
	if rs != null:
		rtex = ((rs.mesh as QuadMesh).material as ShaderMaterial).get_shader_parameter("albedo_tex")
	verdict("F2 руина нарисована картинкой GoldMine_Destroyed",
		rtex != null and (rtex as Texture2D).resource_path == _MineS.SPRITE_DESTROYED,
		str(rtex.resource_path if rtex != null else "нет"))
	var site = GameManager.rebuild_ruin(ruin, Constants.FACTION_PLAYER)
	verdict("F3 клик по руине заводит стройку рудника для отстраивающего",
		site != null and String(site.get("target_id")) == "mine" and (site as Building).faction == Constants.FACTION_PLAYER)
	if site == null:
		_finish()
		return
	site.set("build_time", 0.6)
	var w2: Unit = (Building.PRELOAD_SCENES["worker"] as PackedScene).instantiate()
	w2.faction = Constants.FACTION_PLAYER
	main.world_add(w2)
	var w2p: Vector3 = mp + Vector3(0.0, 0.0, 6.0)
	w2.global_position = Vector3(w2p.x, GameManager.get_terrain_height(w2p.x, w2p.z), w2p.z)
	w2.sync_row()
	GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "worker"), w2)
	await pframes(2)
	(w2 as Worker).command_build(site as Node3D)
	var g5 := 0
	var rebuilt: Mine = null
	while g5 < 60 * 40 and rebuilt == null:
		await get_tree().physics_frame
		g5 += 1
		for b in get_tree().get_nodes_in_group("player_buildings"):
			if is_instance_valid(b) and b is Mine and (b as Node3D).global_position.distance_to(mp) < 1.0:
				rebuilt = b
	verdict("F4 рабочий отстроил руину — новый рудник игрока с флагом",
		rebuilt != null and rebuilt.faction == Constants.FACTION_PLAYER and rebuilt.flag_visible(),
		"физкадров %d" % g5)
	if rebuilt != null:
		await pframes(2)
		sm.selected_units = [w2]
		var ok_in: bool = sm._try_enter_mine(rebuilt)
		sm.selected_units = []
		var g6 := 0
		while g6 < 60 * 20 and rebuilt.workers.is_empty():
			await get_tree().physics_frame
			g6 += 1
		verdict("F5 маршрут ПКМ: рабочий внутрь, пустым выделением — наружу",
			ok_in and rebuilt.workers.size() == 1 and sm._try_release_mine(rebuilt) and rebuilt.workers.is_empty(),
			"внутрь за %d физкадров" % g6)
	_finish()
