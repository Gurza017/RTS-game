extends Node
## ЗОНД: протяжка ПКМ копейщиков с изученной «Фалангой» в стойке [S] —
## где бойцы ФАКТИЧЕСКИ встают (шеренги и ширина после прихода), а не что
## посчитала раскладка. Варианты: без кузницы / с кузницей [C] / с кузницей [S].
const F := Constants.FACTION_PLAYER
var main: Node = null

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился")
		get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = F
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(F, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7))
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _clear(at: Vector3, r: float) -> void:
	main._clear_trees(at, r)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
			u.queue_free()

func _measure(men: Array, a: Vector3, b: Vector3) -> String:
	var dir := (b - a).normalized()
	var facing := Vector3(dir.z, 0.0, -dir.x)
	var lat: Array = []
	var dep: Array = []
	for m in men:
		var p: Vector3 = (m as Node3D).global_position - a
		p.y = 0.0
		lat.append(p.dot(dir))
		dep.append(p.dot(-facing))
	lat.sort()
	dep.sort()
	var rows := 1
	for i in range(1, dep.size()):
		if float(dep[i]) - float(dep[i - 1]) > 0.3:
			rows += 1
	return "ширина %.1f м (линия %.1f), глубина %.1f м, шеренг %d" % [
		float(lat[-1]) - float(lat[0]), (b - a).length(), float(dep[-1]) - float(dep[0]), rows]

func _case(title: String, research: bool, stance_s: bool, at: Vector3, deep: bool = false, squads: int = 1, archers: bool = false) -> void:
	_clear(at, 35.0)
	await pframes(3)
	if research:
		for nid in ["spearman_1d", "spearman_2d", "spearman_3d", "spearman_1a", "spearman_1b", "spearman_1c"]:
			GameManager.finish_research(F, nid)
	var men: Array = []
	for q in range(squads):
		men.append_array(_squad("spearman", at + Vector3(float(q) * 6.0, 0, 0), 60))
	if archers:
		men.append_array(_squad("archer", at + Vector3(0, 0, -8), 30))
	await pframes(10)
	var sm = main.selection_manager
	sm.select_units(men)
	sm.formation_mode = sm.FORM_DEEP if deep else sm.FORM_WIDE
	if stance_s:
		sm._squad_cmd().stand_ground(sm)
	else:
		sm._squad_cmd().at_ease(sm)
	await pframes(10)
	var a := at + Vector3(-15, 0, 10)
	var b := at + Vector3(15, 0, 10)
	var spears: Array = men.filter(func(m): return (m as Unit).stat_id == "spearman")
	var plan: Dictionary = sm._mono_formation_slots(a, b, spears)
	var prow := 0
	for r in plan["rows"]:
		prow = maxi(prow, int(r))
	sm._execute_line_formation(a, b)
	var waited := 0
	while waited < 1800:
		await pframes(10)
		waited += 10
		var moving := 0
		for m in men:
			if is_instance_valid(m) and (m as Unit).state == Unit.State.MOVING:
				moving += 1
		if moving == 0 and waited > 60:
			break
	await pframes(120)
	var sid: int = (men[0] as Unit).squad_id
	print("%s: план шеренг %d; факт %s; стена=%s стойка=%s, ждали %d физкадров" % [
		title, prow + 1, _measure(spears, a, b), GameManager.spear_wall_ready(sid),
		(men[0] as Unit).stance, waited])
	sm.clear_selection()
	for m in men:
		m.queue_free()
	await pframes(5)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	var only: String = ""
	for x in OS.get_cmdline_user_args():
		if String(x).begins_with("only="):
			only = String(x).substr(5)
	if only == "" or "1" in only: await _case("3 отряда БЕЗ кузницы, [C]", false, false, Vector3(-80, 0, -10), false, 3)
	if only == "" or "2" in only: await _case("3 отряда БЕЗ кузницы, [S]", false, true, Vector3(-80, 0, 30), false, 3)
	if only == "" or "3" in only: await _case("3 отряда Фаланга, [C]", true, false, Vector3(-30, 0, -10), false, 3)
	if only == "" or "4" in only: await _case("3 отряда Фаланга, [S]", true, true, Vector3(-30, 0, 30), false, 3)
	print("ЗОНД ГОТОВ")
	get_tree().quit()
