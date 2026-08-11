extends Node

## QA п.5 — ЕДИНЫЙ ФРОНТ ФАЛАНГИ И СТОЙКИ

var main: Node = null
var sm = null
var squad: Array = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	sm = main.selection_manager
	await _spawn_squad(30, Vector3(-30, 0, -30))
	await _t51()
	await _t52()
	await _t53()
	print("\n=== FRONT DONE ===")
	get_tree().quit()

func _spawn_squad(n: int, origin: Vector3) -> void:
	for u in squad:
		if is_instance_valid(u):
			u.queue_free()
	squad.clear()
	var S := load("res://scenes/units/Spearman.tscn") as PackedScene
	for i in range(n):
		var u: Unit = S.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.add_child(u)
		u.global_position = origin + Vector3(float(i % 6) * 0.5, 0.0, float(i / 6) * 0.5)
		squad.append(u)
	await get_tree().process_frame
	await get_tree().process_frame

func _select_squad() -> void:
	sm._clear_selection()
	for u in squad:
		if is_instance_valid(u):
			sm._select(u)

## Ждём, пока все встанут (или закончится терпение). Возвращает число кадров.
func _wait_arrival(limit: int = 2500) -> int:
	var f := 0
	while f < limit:
		await get_tree().process_frame
		f += 1
		var moving := 0
		for u in squad:
			if is_instance_valid(u) and u.state == Unit.State.MOVING:
				moving += 1
		if moving == 0:
			break
	# ещё несколько кадров на доворот спрайтов
	for _i in range(5):
		await get_tree().process_frame
	return f

## Сводка по направлению взгляда отряда
func _facing_report(expect: Vector3, tag: String) -> bool:
	var same := 0
	var worst := 2.0
	var flips: Dictionary = {}
	var alive := 0
	for u in squad:
		if not is_instance_valid(u):
			continue
		alive += 1
		var fv: Vector3 = u._facing
		var d: float = fv.normalized().dot(expect)
		worst = minf(worst, d)
		if d > 0.999:
			same += 1
		var fh: bool = u._flip_h_state
		flips[fh] = int(flips.get(fh, 0)) + 1
	var ok: bool = (same == alive) and flips.size() <= 1
	print("  %-28s ожидаем взгляд (%+.2f,%+.2f) | строго по фронту %d/%d | худший dot=%.5f | flip_h %s | %s"
		% [tag, expect.x, expect.z, same, alive, worst, str(flips), "OK" if ok else "FAIL"])
	return ok

# ── 5.1 растянутая линия ПКМ ─────────────────────────────────────────────────
func _t51() -> void:
	print("\n===== 5.1 ЛИНИЯ ФОРМАЦИИ (_execute_line_formation), 30 копейщиков =====")
	var cases: Array = [
		["линия на восток (фронт СЕВЕР)", Vector3(0, 0, 10),  Vector3(12, 0, 10)],
		["линия на запад (фронт ЮГ)",     Vector3(12, 0, 20), Vector3(0, 0, 20)],
		["линия на север (фронт ЗАПАД)",  Vector3(20, 0, 12), Vector3(20, 0, 0)],
		["линия на юг (фронт ВОСТОК)",    Vector3(30, 0, 0),  Vector3(30, 0, 12)],
		["линия по диагонали",            Vector3(-10, 0, 0), Vector3(-1.5, 0, 8.5)],
	]
	var all_ok := true
	for c in cases:
		var tag: String   = c[0]
		var a: Vector3    = c[1]
		var b: Vector3    = c[2]
		_select_squad()
		sm._execute_line_formation(a, b)
		var frames := await _wait_arrival()
		var line_dir := (b - a).normalized()
		var expect := Vector3(line_dir.z, 0.0, -line_dir.x)
		var ok := _facing_report(expect, tag)
		print("      (пришли за %d кадров)" % frames)
		all_ok = all_ok and ok
	print("ВЕРДИКТ 5.1: %s" % ("PASS" if all_ok else "FAIL"))

# ── 5.2 обычный ПКМ и марш горячей группы ────────────────────────────────────
func _t52() -> void:
	print("\n===== 5.2 ОБЫЧНЫЙ ПКМ И МАРШ ГОРЯЧЕЙ ГРУППЫ =====")
	var all_ok := true

	# --- обычный ПКМ в точку (НЕ горячая группа) ---
	await _spawn_squad(30, Vector3(-30, 0, -30))
	_select_squad()
	sm._groups[0] = []          # гарантируем: выделение не совпадает с группой
	var centroid := _centroid()
	var target := Vector3(0, 0, -10)
	var expect := (target - centroid)
	expect.y = 0.0
	expect = expect.normalized()
	print("  [_issue_formation_move] центроид (%.1f,%.1f) -> цель (%.1f,%.1f), горячая группа: %s"
		% [centroid.x, centroid.z, target.x, target.z, str(sm._selection_is_hotkey_group())])
	sm._issue_formation_move(target)
	var f1 := await _wait_arrival()
	all_ok = _facing_report(expect, "ПКМ в точку") and all_ok
	print("      (пришли за %d кадров)" % f1)

	# --- марш горячей группы: сначала Ctrl+1 ---
	_select_squad()
	sm._save_group(0)
	print("  [_issue_march_keeping_shape] после _save_group(0) горячая группа: %s"
		% str(sm._selection_is_hotkey_group()))
	var centroid2 := _centroid()
	var target2 := Vector3(25, 0, 25)
	var expect2 := (target2 - centroid2)
	expect2.y = 0.0
	expect2 = expect2.normalized()
	sm._issue_formation_move(target2)   # тот же вход, что у игрока по ПКМ
	var f2 := await _wait_arrival(4000)
	all_ok = _facing_report(expect2, "марш строем (Ctrl+1)") and all_ok
	print("      (пришли за %d кадров; марш идёт шагом — 50%% скорости)" % f2)
	print("ВЕРДИКТ 5.2: %s" % ("PASS" if all_ok else "FAIL"))

func _centroid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in squad:
		if is_instance_valid(u):
			c += (u as Node3D).global_position
			n += 1
	if n > 0:
		c /= float(n)
	c.y = 0.0
	return c

# ── 5.3 стойки ───────────────────────────────────────────────────────────────
func _t53() -> void:
	print("\n===== 5.3 СТОЙКИ: КОПЬЯ ПОДНЯТЫ/ОПУЩЕНЫ =====")
	# Настоящий найм из Бараков
	var bar := Barracks.new()
	bar.faction = Constants.FACTION_PLAYER
	main.world_add(bar)
	bar.global_position = Vector3(-50, 0, 50)
	await get_tree().process_frame
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD, 1000.0)
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD, 1000.0)
	var before: Array = get_tree().get_nodes_in_group("player_units")
	bar.train_spearman()
	var guard := 0
	var hired: Array = []
	while guard < 2500 and hired.size() < 20:
		await get_tree().process_frame
		guard += 1
		hired.clear()
		for n in get_tree().get_nodes_in_group("player_units"):
			if n is Spearman and not (n in before):
				hired.append(n)
	print("  нанято копейщиков: %d (за %d кадров)" % [hired.size(), guard])
	for _i in range(20):
		await get_tree().process_frame
	_report_stance(hired, "СРАЗУ ПОСЛЕ НАЙМА", false)

	# Ctrl+1..9: сохранить и вызвать группу
	sm._clear_selection()
	for u in hired:
		sm._select(u)
	sm._save_group(2)
	sm._recall_group(2)
	for _i in range(10):
		await get_tree().process_frame
	_report_stance(hired, "ПОСЛЕ Ctrl+3 / вызова группы", false)

	# ЗАЩИТА
	sm.set_selection_stance("defense")
	for _i in range(20):
		await get_tree().process_frame
	_report_stance(hired, "ПОСЛЕ [ЗАЩИТА]", true)

	# Возврат в АТАКУ
	sm.set_selection_stance("attack")
	for _i in range(20):
		await get_tree().process_frame
	_report_stance(hired, "ПОСЛЕ возврата в [АТАКА]", false)
	for u in hired:
		if is_instance_valid(u):
			u.queue_free()

func _report_stance(units: Array, tag: String, want_leveled: bool) -> void:
	var lev := 0
	var alive := 0
	var stances: Dictionary = {}
	var texkeys: Dictionary = {}
	for u in units:
		if not is_instance_valid(u):
			continue
		alive += 1
		if bool(u.call("_spear_leveled")):
			lev += 1
		var s: String = u.stance
		stances[s] = int(stances.get(s, 0)) + 1
		var k: String = String(u.get("_cur_tex_key"))
		texkeys[k] = int(texkeys.get(k, 0)) + 1
	var want: int = alive if want_leveled else 0
	var ok: bool = lev == want and stances.size() == 1
	var def_tex := 0
	for k in texkeys:
		if String(k).begins_with("defence"):
			def_tex += int(texkeys[k])
	var tex_ok: bool = (def_tex == alive) if want_leveled else (def_tex == 0)
	print("  %-30s stance=%s | _spear_leveled=true у %d/%d (ждём %d) | текстуры: %s | defence_* у %d %s"
		% [tag, str(stances), lev, alive, want, str(texkeys), def_tex,
		   "OK" if (ok and tex_ok) else "FAIL"])
	if not (ok and tex_ok):
		var shown := 0
		for u in units:
			if not is_instance_valid(u):
				continue
			var lv: bool = bool(u.call("_spear_leveled"))
			var hg: bool = bool(u.call("_stance_holds_ground"))
			if lv == want_leveled and shown > 2:
				continue
			shown += 1
			if shown > 8:
				break
			print("      диагностика: класс=%s stance='%s' _stance_holds_ground=%s _spear_leveled=%s state=%d tex='%s' row=%d live_rank=%d"
				% [u.get_class() + "/" + u.display_name, u.stance, str(hg), str(lv),
				   u.state, String(u.get("_cur_tex_key")), int(u.get("formation_row")), int(u.get("_live_rank"))])
