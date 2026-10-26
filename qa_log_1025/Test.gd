extends Node
## РАЗБОР ПАРТИИ 25.10.2026 (logs/godot.log + performance_log_2026-10-25_0006.json)
##   A — копейщик в коробке под замком игрока, когда ближе всех в длине оружия
##       ВРАЖЕСКОЕ ЗДАНИЕ: Unit._box_hold читал у постройки squad_id — 313
##       SCRIPT ERROR за партию (бараки, дома, стрельбище), боец не бил
##   B — у кромки карты нет замкнутых коридоров: со всякой проходимой точки
##       вдоль края A* находит дорогу к базе (два отряда орды 11 минут стояли
##       в коридоре в клетку между рощей и краем, 300 «unstuck_giveup»)
var main: Node
var _pass := 0
var _fail := 0
var _only := "ab"
var _done := false
var _errs := 0
var _err_first := ""

class ErrLog extends Logger:
	var owner_ref: WeakRef
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		var o = owner_ref.get_ref()
		if o != null:
			o.call_deferred("_on_err", "%s:%d %s" % [file, line, rationale])
	func _log_message(_message: String, _error: bool) -> void:
		pass

func _boom() -> void:
	var bad: Variant = null
	bad.call("no_such")

func _on_err(s: String) -> void:
	_errs += 1
	if _err_first == "":
		_err_first = s

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	var lg := ErrLog.new()
	lg.owner_ref = weakref(self)
	OS.add_logger(lg)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_log_1025: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var p: Vector3 = at + Vector3(-float(i / cols) * 0.7, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * 0.7)
		GameManager.add_to_squad(sid, _unit(uid, f, p))
	return sid

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _clear_area(at: Vector3, r: float) -> void:
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(n0) and Vector2((n0 as Node3D).global_position.x - at.x, (n0 as Node3D).global_position.z - at.z).length() < r:
			n0.queue_free()
	for f in [Constants.FACTION_ENEMY, Constants.FACTION_GOBLIN]:
		for u in get_tree().get_nodes_in_group(Constants.unit_group(f)):
			if is_instance_valid(u) and Vector2((u as Node3D).global_position.x - at.x, (u as Node3D).global_position.z - at.z).length() < r:
				(u as Unit).set_tick(false)
				(u as Node3D).global_position += Vector3(0.0, 0.0, 400.0)

func _run() -> void:
	# Коробки выключены по развороту ТЗ 25.10.2026 (третье письмо, п. 2), а
	# стенд разбирает ошибку именно в коробке: включает ручку сам, если её не
	# задали явно (knob=box_front:N)
	var _knob_set := false
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("knob=box_front"):
			_knob_set = true
	if not _knob_set:
		preload("res://scripts/perf_config.gd").box_front = true
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "x" in _only:
		call_deferred("_boom")
		await pframes(3)
		print("  самопроверка ловушки ошибок: поймано %d" % _errs)
	if "b" in _only: _b_edge()
	if "a" in _only: await _a_box_building()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. КОРОБКА ПОД ЗАМКОМ У ВРАЖЕСКОГО ЗДАНИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _a_box_building() -> void:
	print("\n═════ A. КОРОБКА ПОД ЗАМКОМ, РЯДОМ ВРАЖЕСКИЕ БАРАКИ ═════")
	var c: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(30.0, 0.0, 30.0)
	_clear_area(c, 30.0)
	await pframes(3)
	# Свои — колонкой по 6, лицом на +X; гоблины в 9 м; бараки красных
	# на месте переднего ряда (здания не преграда, building_obstacles) —
	# передним рядам они ближе любого врага
	var my_sid: int = _squad("spearman", Constants.FACTION_PLAYER, c, 24, 6)
	var foe_sid: int = _squad("goblin_spearman", Constants.FACTION_GOBLIN, c + Vector3(9.0, 0.0, 0.0), 20, 5)
	var b: Building = Barracks.new()
	b.faction = Constants.FACTION_ENEMY
	main.world_add(b)
	var bp: Vector3 = c + Vector3(5.0, 0.0, 1.0)
	b.global_position = Vector3(bp.x, GameManager.get_terrain_height(bp.x, bp.z), bp.z)
	if "nobld" in OS.get_cmdline_user_args():
		b.global_position += Vector3(0.0, 0.0, 300.0)
	await pframes(10)
	var foe0: Array = _members(foe_sid)
	var n0: int = foe0.size()
	var hp0 := 0.0
	for g in foe0:
		hp0 += (g as Unit).current_health
	var errs0: int = _errs
	var tgt: Unit = foe0[0]
	for u in _members(my_sid):
		(u as Unit).command_attack(tgt, true, false, true)
	var boxed := false
	for _t in range(900):
		await get_tree().physics_frame
		if _t % 150 == 149:
			var lk := 0
			var bx := 0
			var at := 0
			var sx := 0.0
			var mm: Array = _members(my_sid)
			for u in mm:
				var uu: Unit = u
				lk += 1 if uu.target_lock else 0
				bx += 1 if uu._box_goal.x != INF else 0
				at += 1 if uu.state == Unit.State.ATTACKING else 0
				sx += uu.global_position.x - c.x
			var gx := 0.0
			var gm: Array = _members(foe_sid)
			for g in gm:
				gx += (g as Unit).global_position.x - c.x
			print("  t%3d: наших %d (замок %d, коробка %d, в атаке %d, x %.1f), гоблинов %d (x %.1f)" % [_t + 1,
				mm.size(), lk, bx, at, sx / maxf(1.0, mm.size()), gm.size(), gx / maxf(1.0, gm.size())])
		if not boxed:
			for u in _members(my_sid):
				if (u as Unit)._box_goal.x != INF:
					boxed = true
					break
	var hp1 := 0.0
	for g in _members(foe_sid):
		hp1 += (g as Unit).current_health
	var lost: float = 1.0 - hp1 / maxf(hp0, 1.0)
	verdict("A1 отряд встал коробкой", boxed)
	verdict("A2 ни одной SCRIPT ERROR, пока коробка стоит у бараков", _errs == errs0,
		"ошибок %d%s" % [_errs - errs0, ("; первая: " + _err_first) if _err_first != "" else ""])
	verdict("A3 отряд под замком бьёт цель (гоблины теряют здоровье)", lost > 0.05, "%.0f %% запаса отряда" % (lost * 100.0))
	b.queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# B. ЗАМКНУТЫХ КОРИДОРОВ ВДОЛЬ КРОМКИ НЕТ
# ═════════════════════════════════════════════════════════════════════════════
func _b_edge() -> void:
	print("\n═════ B. ВДОЛЬ КРОМКИ КАРТЫ НЕТ ЗАМКНУТЫХ КОРИДОРОВ ═════")
	var lx: float = GameManager.map_lim_x - 0.3
	var lz: float = GameManager.map_lim_z - 0.3
	var home: Vector3 = main.PLAYER_BASE_ANCHOR
	var pts: Array = []
	var x := -lx
	while x <= lx:
		pts.append(Vector2(x, -lz))
		pts.append(Vector2(x, lz))
		x += 2.0
	var z := -lz
	while z <= lz:
		pts.append(Vector2(-lx, z))
		pts.append(Vector2(lx, z))
		z += 2.0
	var tried := 0
	var shut: Array = []
	for p in pts:
		var q: Vector2 = p
		if not GameManager.is_passable(q.x, q.y) or GameManager.is_water(q.x, q.y):
			continue
		tried += 1
		GameManager.army.nav_path(q.x, q.y, home.x, home.z, 1.5, 0.0)
		if not GameManager.army.nav_last_found():
			shut.append(q)
	print("  проходимых точек у кромки: %d, без дороги к базе: %d %s" % [tried, shut.size(), str(shut.slice(0, 6))])
	verdict("B1 с каждой проходимой точки у кромки есть дорога к базе", shut.is_empty() and tried > 0,
		"%d из %d" % [shut.size(), tried])
