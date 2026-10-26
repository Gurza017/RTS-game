extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 25.10.2026 (ТРЕТЬЕ ПИСЬМО И ПИСЬМО UI №4)
## ═══════════════════════════════════════════════════════════════════════════
##   A БАШНИ    — с выделенными башнями курсор-стрела (прицел есть); ПКМ по
##                земле рядом с чужими — огонь гарнизона по ближайшему; ручная
##                цель держится, даже если ближе встал другой и цель ушла за
##                дальность огня (до MANUAL_HOLD_K дальностей); дальше — снята
##   B КВАДРАТЫ — коробки и «линия держит фронт» выключены ручками; в рубке
##                ни один наш отряд не встаёт в коробку
##   C CTRL+N   — группа из линии и колонны после марша в новую сторону:
##                расстояние между отрядами и форма каждого (длина/глубина)
##                те же, что при сохранении
##   D ОТХОД    — идущего по приказу игрока прочь бьют СЗАДИ: марш идёт
##                дальше; удар СПЕРЕДИ (на пути) — ответ, как прежде
##   E [A]+ПКМ  — во взведённом [A] ПКМ по врагу: прицельная атака (замок
##                цели на этом отряде), Attack-Move у отряда снят
##   F ВЫШКИ ИИ — две башни не в одной точке: выбили №0 при живой №1 — новая
##                встаёт на место №0, не ближе TOWER_SLOT_BUSY_R к живой; слоты
##                у разных входов в базу
##   G UI       — кнопка [C] — силуэт копейщика; фигурки в полный рост у
##                рыцаря, копейщика, лучника, монаха; портрет выделения — она
##   H ОСАДА    — вторая линия осады ждёт очереди в ядре (автопилот), а не
##                входит в GDScript-автомат каждый кадр
## ЧИСЛА НЕ ХАРДКОДЯТСЯ: дальности, радиусы, сроки — из модулей и конфигов.
## Запуск: godot --headless --path . res://qa_tz1025b/Test.tscn [-- only=abcdefgh]

const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN
const _Opt := preload("res://scripts/perf_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Roof := preload("res://scripts/RoofGarrison.gd")

var main: Node = null
var sm = null
var cam: Camera3D = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд завис")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else: _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_tz1025b ═════")
	for e in _log:
		if not bool(e[1]):
			print("  НЕ ПРОШЛО: %s" % String(e[0]))
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _wipe(at: Vector3, r: float) -> void:
	main._clear_area_of_resources(at, r)
	main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()

func _place_unit(uid: String, fac: int, p: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Отряд по точкам pts (смещения от at), курс course
func _squad_pts(uid: String, fac: int, at: Vector3, pts: Array, course: Vector3) -> int:
	var sid: int = GameManager.new_squad(fac, uid)
	var slots: Array = []
	for p in pts:
		var u := _place_unit(uid, fac, at + (p as Vector3))
		u._facing = course
		GameManager.add_to_squad(sid, u)
		slots.append(u.global_position)
	GameManager.squad_set_formation(sid, slots, course, false)
	return sid

func _grid(n: int, cols: int, gap: float) -> Array:
	var o: Array = []
	for i in range(n):
		o.append(Vector3((float(i % cols) - float(cols - 1) * 0.5) * gap, 0.0, float(i / cols) * gap))
	return o

func _move_squad(sid: int, p: Vector3) -> void:
	var men := _members(sid)
	var c: Vector3 = GameManager._centroid_of(men)
	for m in men:
		var u: Unit = m
		var q: Vector3 = u.global_position - c + p
		u.global_position = Vector3(q.x, GameManager.get_terrain_height(q.x, q.z), q.z)
		u.sync_row()

func _freeze(sid: int) -> void:
	for m in _members(sid):
		(m as Unit).set_tick(false)

func _kill(sids: Array) -> void:
	for s in sids:
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)
	await pframes(30)

func _select_squads(sids: Array) -> void:
	sm._clear_selection()
	for s in sids:
		for u in _members(int(s)):
			sm._select(u)

func _aim_cam(at: Vector3) -> void:
	cam.global_position = at + Vector3(0.0, 45.0, 32.0)
	cam.look_at(at, Vector3.UP)

func _scr(p: Vector3) -> Vector2:
	return cam.unproject_position(p)

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	seed(251026)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	sm = main.selection_manager
	main.set_process(false)
	cam = main.get_viewport().get_camera_3d()
	cam.set_process(false)
	var only := "abcdefgh"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			only = String(a).substr(5)
	if "a" in only: await _a_towers()
	if "b" in only: await _b_boxes()
	if "c" in only: await _c_group()
	if "d" in only: await _d_retreat()
	if "e" in only: await _e_am_click()
	if "f" in only: await _f_ai_towers()
	if "g" in only: await _g_ui()
	if "h" in only: await _h_siege()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_towers() -> void:
	print("\n═════ A. БАШНИ: КУРСОР И СТРОГАЯ ЦЕЛЬ ═════")
	var c: Vector3 = main.PLAYER_BASE_ANCHOR.lerp(Vector3.ZERO, 0.4)
	c.y = 0.0
	_wipe(c, 70.0)
	await pframes(4)
	var towers: Array = []
	for k in range(2):
		var t: Building = load("res://scripts/Tower.gd").new()
		t.faction = F
		main.world_add(t)
		var tp: Vector3 = c + Vector3(float(k) * 14.0 - 7.0, 0.0, 0.0)
		t.global_position = Vector3(tp.x, GameManager.get_terrain_height(tp.x, tp.z), tp.z)
		towers.append(t)
	await pframes(6)
	var sat := true
	for t in towers:
		var gs: int = _squad_pts("archer", F, (t as Node3D).global_position + Vector3(0, 0, 6), _grid(8, 4, 0.6), Vector3.FORWARD)
		await pframes(2)
		sat = sat and (t as Castle).garrison_now(gs)
	await pframes(6)
	var t0: Castle = towers[0]
	var roof = t0._roof
	var fr: float = roof.fire_range()
	verdict("A0 две башни с лучниками на крыше", sat and t0.has_roof_garrison() and (towers[1] as Castle).has_roof_garrison(),
		"дальность огня %.1f м" % fr)
	sm._clear_selection()
	sm._select(t0)
	verdict("A1 выделена одна башня: прицел есть, курсор — стрела",
		sm.selection_has_fire_forts() and sm.selection_ranged_only() and sm.selection_towers_only())
	sm._select(towers[1])
	verdict("A2 выделены две башни: курсор — стрела", sm.selection_has_fire_forts() and sm.selection_ranged_only()
		and sm.selection_towers_only())
	# Две чужие цели: дальняя E1 (в дальности) и ближняя E2
	var e1: int = _squad_pts("spearman", R, c + Vector3(-7.0, 0.0, -fr * 0.7), _grid(6, 3, 0.6), Vector3.BACK)
	var e2: int = _squad_pts("spearman", R, c + Vector3(-7.0, 0.0, -fr * 0.3), _grid(6, 3, 0.6), Vector3.BACK)
	_freeze(e1)
	_freeze(e2)
	await pframes(4)
	_aim_cam(c + Vector3(-7.0, 0.0, -fr * 0.5))
	await pframes(2)
	# ПКМ по ЗЕМЛЕ рядом с E1: в 7.5 м от центра — дальше зоны выбора отряда
	# под курсором (SQUAD_CLICK_REACH), но ближе TOWER_POINT_PICK_R
	var e1c: Vector3 = GameManager._centroid_of(_members(e1))
	var gp: Vector3 = e1c + Vector3(7.5, 0.0, 0.0)
	gp.y = GameManager.get_terrain_height(gp.x, gp.z)
	sm._handle_right_click(_scr(gp), false)
	await pframes(4)
	var mt = t0.roof_manual_target()
	var mt_sid: int = (mt as Unit).squad_id if mt != null and mt is Unit else -1
	verdict("A3 ПКМ по земле у чужих: гарнизон бьёт ближайшего к точке клика", mt_sid == e1,
		"ручная цель — отряд %d (E1 %d, E2 %d)" % [mt_sid, e1, e2])
	# E1 уходит за дальность огня (но ближе MANUAL_HOLD_K дальностей); E2 ближе
	_move_squad(e1, t0.global_position + Vector3(0.0, 0.0, -fr * (1.0 + (_Roof.MANUAL_HOLD_K - 1.0) * 0.5)))
	await pframes(90)
	mt = t0.roof_manual_target()
	var ft = roof._fire_target
	var ft_sid: int = (ft as Unit).squad_id if ft != null and is_instance_valid(ft) and ft is Unit else -1
	mt_sid = (mt as Unit).squad_id if mt != null and mt is Unit else -1
	verdict("A4 цель ушла за дальность, ближе встал другой: башня не переключается сама",
		mt_sid == e1 and ft_sid == e1, "ручная %d, огонь по %d" % [mt_sid, ft_sid])
	_move_squad(e1, t0.global_position + Vector3(0.0, 0.0, -fr * (_Roof.MANUAL_HOLD_K + 0.6)))
	await pframes(30)
	verdict("A5 цель дальше MANUAL_HOLD_K дальностей — приказ исчерпан, авто-выбор",
		t0.roof_manual_target() == null)
	sm._clear_selection()
	await _kill([e1, e2])
	for t in towers:
		(t as Building).take_damage(1.0e9)
	await pframes(20)

# ═════════════════════════════════════════════════════════════════════════════
func _b_boxes() -> void:
	print("\n═════ B. БЕЗ ПРИНУДИТЕЛЬНЫХ КВАДРАТОВ ═════")
	verdict("B1 коробки в бою выключены ручкой (box_front)", not _Opt.box_front)
	verdict("B2 «линия держит фронт» в [A] выключена (group_line_hold)", not _Opt.group_line_hold)
	var c: Vector3 = main.PLAYER_BASE_ANCHOR.lerp(Vector3.ZERO, 0.4) + Vector3(0.0, 0.0, 25.0)
	c.y = 0.0
	_wipe(c, 40.0)
	await pframes(4)
	var ours: Array = []
	for k in range(2):
		ours.append(_squad_pts("spearman", F, c + Vector3(float(k) * 8.0 - 4.0, 0.0, 6.0), _grid(20, 5, 0.6), Vector3.FORWARD))
	var gs: int = GameManager.new_squad(G, "goblin_spearman")
	for k2 in range(30):
		var ho: Vector2 = _GobCfg.horde_offset(k2, 30, gs)
		var gu := _place_unit("goblin_spearman", G, c + Vector3(ho.x, 0.0, -4.0 + ho.y))
		GameManager.add_to_squad(gs, gu)
	await pframes(4)
	var foe: Unit = _members(gs)[0]
	_select_squads(ours)
	_aim_cam(foe.global_position)
	await pframes(2)
	sm._handle_right_click(_scr(foe.global_position + Vector3(0, 0.8, 0)), false)
	var boxed := 0
	var seen := 0
	for _w in range(10):
		await pframes(30)
		for s in ours:
			for m in _members(int(s)):
				seen += 1
				if bool((m as Unit).get("_box_on")):
					boxed += 1
	verdict("B3 в рубке ни один наш боец не в коробке", seen > 0 and boxed == 0, "в коробке %d из %d замеров" % [boxed, seen])
	sm._clear_selection()
	await _kill(ours + [gs])

# ═════════════════════════════════════════════════════════════════════════════
func _shape_ext(sid: int, course: Vector3) -> Vector2:
	var across := Vector3(-course.z, 0.0, course.x)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for m in _members(sid):
		var p: Vector3 = (m as Unit).global_position
		var v := Vector2(p.dot(across), p.dot(course))
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	return hi - lo

func _c_group() -> void:
	print("\n═════ C. CTRL+N ЖЁСТКО ДЕРЖИТ ФОРМУ ═════")
	var c: Vector3 = main.PLAYER_BASE_ANCHOR.lerp(Vector3.ZERO, 0.4) + Vector3(0.0, 0.0, 10.0)
	c.y = 0.0
	_wipe(c, 60.0)
	await pframes(4)
	# Линия 12×1 и колонна 2×6 правее и позади
	var line_pts: Array = _grid(12, 12, 0.7)
	var col_pts: Array = _grid(12, 2, 0.7)
	var s1: int = _squad_pts("spearman", F, c, line_pts, Vector3.FORWARD)
	var s2: int = _squad_pts("spearman", F, c + Vector3(9.0, 0.0, 3.0), col_pts, Vector3.FORWARD)
	await pframes(6)
	var crs0 := Vector3.FORWARD
	var e1a: Vector2 = _shape_ext(s1, crs0)
	var e2a: Vector2 = _shape_ext(s2, crs0)
	var d0: float = _xz(GameManager._centroid_of(_members(s1)), GameManager._centroid_of(_members(s2)))
	_select_squads([s1, s2])
	sm._save_group(1)
	var uses0: int = sm.group_shape_uses
	# Марш вбок (+X): группа поворачивается на новый курс целиком
	var dest: Vector3 = c + Vector3(30.0, 0.0, -6.0)
	sm.march_selection_to(dest)
	for _w in range(40):
		await pframes(30)
		var moving := 0
		for s in [s1, s2]:
			for m in _members(int(s)):
				if (m as Unit).state == Unit.State.MOVING:
					moving += 1
		if moving == 0:
			break
	verdict("C0 приказ группе Ctrl+N взял сохранённую форму", sm.group_shape_uses > uses0,
		"применений %d → %d" % [uses0, sm.group_shape_uses])
	var crs: Vector3 = GameManager.squad_course(s1)
	crs.y = 0.0
	crs = crs.normalized() if crs.length_squared() > 1e-6 else (dest - c).normalized()
	var e1b: Vector2 = _shape_ext(s1, crs)
	var e2b: Vector2 = _shape_ext(s2, crs)
	var d1: float = _xz(GameManager._centroid_of(_members(s1)), GameManager._centroid_of(_members(s2)))
	verdict("C1 линия осталась линией той же длины (поперёк нового курса)",
		absf(e1b.x - e1a.x) < 1.0 and e1b.y < 1.0, "было %s, стало %s" % [str(e1a), str(e1b)])
	verdict("C2 колонна осталась колонной той же глубины",
		absf(e2b.y - e2a.y) < 1.0 and absf(e2b.x - e2a.x) < 1.0, "было %s, стало %s" % [str(e2a), str(e2b)])
	verdict("C3 расстояние между отрядами сохранено", absf(d1 - d0) < 1.5, "%.1f → %.1f м" % [d0, d1])
	sm._clear_selection()
	await _kill([s1, s2])

# ═════════════════════════════════════════════════════════════════════════════
func _d_retreat() -> void:
	print("\n═════ D. ОТХОД НЕ ПРЕРЫВАЕТСЯ УКОЛОМ СЗАДИ ═════")
	var c: Vector3 = main.PLAYER_BASE_ANCHOR.lerp(Vector3.ZERO, 0.4) + Vector3(0.0, 0.0, 30.0)
	c.y = 0.0
	_wipe(c, 60.0)
	await pframes(4)
	var s: int = _squad_pts("spearman", F, c, _grid(12, 4, 0.6), Vector3.FORWARD)
	var es: int = _squad_pts("spearman", R, c + Vector3(0.0, 0.0, 40.0), _grid(4, 4, 0.6), Vector3.FORWARD)
	_freeze(es)
	await pframes(4)
	var foe: Unit = _members(es)[0]
	_select_squads([s])
	# Уходим на −Z (враг будет позади, на +Z)
	sm.march_selection_to(c + Vector3(0.0, 0.0, -40.0))
	await pframes(int(Unit.FORCED_MOVE_SEC * 60.0) + 60)
	var men := _members(s)
	var u: Unit = men[men.size() - 1]
	var p: Vector3 = u.global_position
	foe.global_position = Vector3(p.x, p.y, p.z + 0.6)
	foe.sync_row()
	for k in range(3):
		u.take_damage(1.0, foe)
		await pframes(10)
	var tgt_in_es: int = 0
	for m in _members(s):
		var at = (m as Unit).attack_target
		if at != null and is_instance_valid(at) and at is Unit and (at as Unit).squad_id == es:
			tgt_in_es += 1
	verdict("D1 удар сзади по идущему прочь: марш не прерван, в бой не повернул никто",
		u.state == Unit.State.MOVING and tgt_in_es == 0, "состояние %s, целятся в обидчика %d" % [
			Unit.State.keys()[u.state], tgt_in_es])
	# Удар СПЕРЕДИ — по пути отхода: ответ как прежде
	var v: Unit = _members(s)[0]
	var q: Vector3 = v.global_position
	var g: Vector3 = v.march_goal()
	var fwd: Vector3 = (g - q)
	fwd.y = 0.0
	fwd = fwd.normalized()
	foe.global_position = q + fwd * 0.6
	foe.sync_row()
	v.take_damage(1.0, foe)
	await pframes(6)
	var answered: bool = v.attack_target == foe or v.state == Unit.State.ATTACKING
	verdict("D2 удар спереди (враг на пути) — ответ, как прежде", answered,
		"состояние %s" % Unit.State.keys()[v.state])
	sm._clear_selection()
	await _kill([s, es])

# ═════════════════════════════════════════════════════════════════════════════
func _e_am_click() -> void:
	print("\n═════ E. [A] + ПКМ ПО ВРАГУ — ПРИЦЕЛЬНАЯ АТАКА ═════")
	var c: Vector3 = main.PLAYER_BASE_ANCHOR.lerp(Vector3.ZERO, 0.4) + Vector3(0.0, 0.0, 30.0)
	c.y = 0.0
	_wipe(c, 60.0)
	await pframes(4)
	var s: int = _squad_pts("spearman", F, c, _grid(12, 4, 0.6), Vector3.FORWARD)
	var es: int = _squad_pts("spearman", R, c + Vector3(6.0, 0.0, -16.0), _grid(8, 4, 0.6), Vector3.BACK)
	_freeze(es)
	await pframes(4)
	_select_squads([s])
	# Сначала в [A] по земле — отряд под командиром
	_aim_cam(c + Vector3(0.0, 0.0, -10.0))
	await pframes(2)
	sm.set_attack_move_armed(true)
	var gp: Vector3 = c + Vector3(-8.0, 0.0, -20.0)
	gp.y = GameManager.get_terrain_height(gp.x, gp.z)
	sm._consume_attack_move_click(_scr(gp))
	await pframes(10)
	var cmd = sm.squad_commander()
	var am0: bool = cmd._am.has(s)
	# Взводим [A] снова и ПКМ по врагу
	var foe: Unit = _members(es)[0]
	sm.set_attack_move_armed(true)
	sm._consume_attack_move_click(_scr(foe.global_position + Vector3(0, 0.8, 0)))
	await pframes(10)
	var locked := 0
	var on_es := 0
	var men := _members(s)
	for m in men:
		var uu: Unit = m
		if uu.target_lock:
			locked += 1
		var at = uu.attack_target
		if at != null and is_instance_valid(at) and at is Unit and (at as Unit).squad_id == es:
			on_es += 1
	verdict("E1 до клика по врагу отряд шёл маршем с боем", am0)
	verdict("E2 ПКМ по врагу в [A]: замок цели на ЭТОМ отряде у всего отряда",
		locked == men.size() and on_es == men.size(), "замок %d, на цели %d из %d" % [locked, on_es, men.size()])
	verdict("E3 Attack-Move у отряда снят, режим [A] погашен", not cmd._am.has(s) and not sm.attack_move_armed)
	sm._clear_selection()
	await _kill([s, es])

# ═════════════════════════════════════════════════════════════════════════════
func _f_ai_towers() -> void:
	print("\n═════ F. ВЫШКИ ИИ НЕ В ОДНОЙ ТОЧКЕ ═════")
	var ai = main.get("enemy_ai")
	var castle: Castle = null
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is Castle and (b as Castle).is_stronghold() and not (b as Building).is_dead():
			castle = b
			break
	if ai == null or castle == null:
		verdict("F0 есть ИИ и его крепость", false)
		return
	# Уберём пограничные башни, если стоят
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and (b as Building).building_id == "tower" \
				and _xz((b as Node3D).global_position, castle.global_position) >= ai.HOME_TOWER_RADIUS:
			(b as Building).take_damage(1.0e9)
	await pframes(20)
	var put := func(p: Vector3) -> Building:
		var t: Building = load("res://scripts/Tower.gd").new()
		t.faction = R
		main.world_add(t)
		t.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		return t
	var sp0: Vector3 = ai._tower_spot(castle, 0)
	var t0: Building = put.call(sp0)
	await pframes(4)
	var sp1: Vector3 = ai._tower_spot(castle, 1)
	var t1: Building = put.call(sp1)
	await pframes(4)
	verdict("F1 вторая башня не вплотную к первой", _xz(sp0, sp1) >= ai.TOWER_SLOT_BUSY_R,
		"%.1f м" % _xz(sp0, sp1))
	var exits: Array = main.ai_base_exits()
	var ne0 := 1e9
	var ne1 := 1e9
	var ei0 := -1
	var ei1 := -1
	for k in range(exits.size()):
		var ep: Vector3 = (exits[k] as Dictionary)["p"]
		if _xz(sp0, ep) < ne0:
			ne0 = _xz(sp0, ep); ei0 = k
		if _xz(sp1, ep) < ne1:
			ne1 = _xz(sp1, ep); ei1 = k
	verdict("F2 обе башни у входов в базу, у разных", exits.is_empty() or (ne0 < 30.0 and ne1 < 30.0 and ei0 != ei1),
		"до входа %.1f и %.1f м, входы %d/%d" % [ne0, ne1, ei0, ei1])
	t0.take_damage(1.0e9)
	await pframes(20)
	# Прежде индекс = число живых (1) и точка совпадала с живой башней №1
	var sp2: Vector3 = ai._tower_spot(castle, 1)
	verdict("F3 выбили №0 при живой №1: новая — на месте №0, а не у живой",
		_xz(sp2, sp1) >= ai.TOWER_SLOT_BUSY_R and _xz(sp2, sp0) < 3.0,
		"до живой %.1f м, до места №0 %.1f м" % [_xz(sp2, sp1), _xz(sp2, sp0)])
	t1.take_damage(1.0e9)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
func _g_ui() -> void:
	print("\n═════ G. ЗНАЧКИ И ФИГУРКИ ═════")
	var hud_s = load("res://scripts/HUD.gd")
	var ease: String = String(hud_s.SCMD_ICONS.get("C", ""))
	verdict("G1 кнопка [C] «Вольно» — силуэт копейщика", ease == hud_s.ICON_AT_EASE and ResourceLoader.exists(ease), ease)
	var ok := true
	var det := ""
	for uid in ["warrior", "spearman", "archer", "monk"]:
		var fp: String = hud_s.unit_figure_path(uid, F)
		var good: bool = fp.begins_with(hud_s.UNIT_FIGURE_DIR) and ResourceLoader.exists(fp)
		if good:
			var tex: Texture2D = load(fp)
			# Фигура в полный рост выше, чем шире (монах — почти квадрат)
			good = tex != null and float(tex.get_height()) >= float(tex.get_width()) * 0.8
		ok = ok and good
		det += "%s:%s " % [uid, "да" if good else "нет"]
	verdict("G2 фигурки в полный рост у рыцаря, копейщика, лучника, монаха", ok, det)
	var c: Vector3 = main.PLAYER_BASE_ANCHOR.lerp(Vector3.ZERO, 0.4)
	var a := _place_unit("archer", F, c)
	await pframes(2)
	var pp: String = main.hud._portrait_icon_path([a])
	verdict("G3 портрет выделенного лучника — фигурка, а не голова", pp.begins_with(hud_s.UNIT_FIGURE_DIR), pp)
	a.take_damage(1.0e12)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
func _h_siege() -> void:
	print("\n═════ H. ВТОРАЯ ЛИНИЯ ОСАДЫ ЖДЁТ В ЯДРЕ ═════")
	var c: Vector3 = main.PLAYER_BASE_ANCHOR.lerp(Vector3.ZERO, 0.45)
	c.y = 0.0
	_wipe(c, 90.0)
	await pframes(6)
	var t: Building = load("res://scripts/Tower.gd").new()
	t.faction = R
	t.current_health = 1.0e7
	main.world_add(t)
	var tp: Vector3 = c + Vector3(0.0, 0.0, -22.0)
	t.global_position = Vector3(tp.x, GameManager.get_terrain_height(tp.x, tp.z), tp.z)
	await pframes(6)
	t.max_health = 1.0e7
	t.current_health = 1.0e7
	var sids: Array = []
	for q in range(12):
		sids.append(_squad_pts("spearman", F, c + Vector3(float(q % 4) * 9.0 - 13.5, 0.0, 20.0 + float(q / 4) * 7.0),
			_grid(30, 10, 0.6), Vector3.FORWARD))
	await pframes(10)
	_select_squads(sids)
	_aim_cam(t.global_position)
	await pframes(2)
	sm._handle_right_click(_scr(t.global_position + Vector3(0, 2, 0)), false)
	await pframes(600)
	var held := 0
	for s in sids:
		if GameManager.squad_attack_hold(int(s)):
			held += _members(int(s)).size()
	# A/B в одной сцене: вызовы GDScript-автомата боя за 300 кадров с ручкой
	# bld_autopilot и без неё (счётчик профиля — только число вызовов, время
	# здесь не читается: профиль завышает его, правило замера 2)
	var calls := func() -> int:
		_Opt.profile_physics = true
		_Opt.prof_reset()
		await pframes(300)
		var n := 0
		for r in _Opt.prof_report():
			if String(r[0]) == "process_attack":
				n = int(r[2])
		_Opt.profile_physics = false
		return n
	var on_calls: int = await calls.call()
	var was: bool = _Opt.bld_autopilot
	_Opt.bld_autopilot = false
	await pframes(60)
	var off_calls: int = await calls.call()
	_Opt.bld_autopilot = was
	verdict("H1 вторая линия осады ждёт очереди в ядре: вызовов автомата боя вчетверо меньше, чем без ручки",
		held > 0 and on_calls * 4 <= off_calls,
		"ждут %d бойцов; вызовов за 300 кадров %d против %d без bld_autopilot" % [held, on_calls, off_calls])
	sm._clear_selection()
	await _kill(sids)
	t.take_damage(1.0e9)
	await pframes(10)
