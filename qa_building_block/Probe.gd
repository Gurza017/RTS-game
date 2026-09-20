extends Node
## Зонд: блок B qa_rally2 (близкий обход, зазор 12 м) при живой и спящей орде
const SPEARMAN := preload("res://scenes/units/Spearman.tscn")
var main = null
var freeze_horde: bool = false
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "freeze":
			freeze_horde = true
	call_deferred("_run")
func _mk(fac: int, pos: Vector3, sid: int) -> Unit:
	var u: Unit = SPEARMAN.instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(pos.x, GameManager.get_terrain_height(pos.x, pos.z), pos.z)
	GameManager.add_to_squad(sid, u)
	return u
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(5):
		await get_tree().process_frame
	main.enemy_ai.set_process(false)
	if freeze_horde:
		main.goblin_ai.set_process(false)
	var wall_x := 60.0
	var wall_z := 30.0
	var fs: int = GameManager.new_squad(Constants.FACTION_ENEMY, "spearman")
	var foes: Array = []
	for i in range(20):
		foes.append(_mk(Constants.FACTION_ENEMY, Vector3(wall_x, 0.0, wall_z + (float(i) - 9.5) * 1.2), fs))
	for _i in range(3):
		await get_tree().process_frame
	for f in foes:
		(f as Unit).command_move((f as Node3D).global_position)
	var start := Vector3(wall_x - 12.0, 0.0, wall_z - 22.0)
	var goal := Vector3(wall_x - 12.0, 0.0, wall_z + 22.0)
	var ms: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var mine: Array = []
	for i in range(20):
		mine.append(_mk(Constants.FACTION_PLAYER, start + Vector3((i % 5 - 2.0) * 1.0, 0.0, float(i / 5) * 1.0), ms))
	for _i in range(3):
		await get_tree().process_frame
	print("  nav_line_blocked(start→goal): %s, obstacles %d, маршрут %s" % [str(GameManager.army.nav_line_blocked(start.x, start.z, goal.x, goal.z, 1.5)), GameManager.obstacle_count(), str(GameManager.nav_route(start, goal, 1.5))])
	var sm = main.selection_manager
	sm._clear_selection()
	for u in mine:
		sm._select_one(u)
	sm._issue_formation_move(goal)
	sm._clear_selection()
	var closest := INF
	var closest_gob := INF
	for f in range(60 * 25):
		await get_tree().physics_frame
		for u in mine:
			if not is_instance_valid(u):
				continue
			var p: Vector3 = (u as Node3D).global_position
			for e in foes:
				if is_instance_valid(e):
					closest = minf(closest, Vector2(p.x - e.global_position.x, p.z - e.global_position.z).length())
			var g = GameManager.army.nearest_of_side(p.x, p.z, Constants.FACTION_GOBLIN, 30.0)
			if g != null and is_instance_valid(g):
				closest_gob = minf(closest_gob, Vector2(p.x - g.global_position.x, p.z - g.global_position.z).length())
		if f % 300 == 299:
			var c: Vector2 = GameManager.squad_centre_xz(ms)
			var eng := 0
			for u in mine:
				if is_instance_valid(u) and (u as Unit).attack_target != null:
					eng += 1
			print("  t=%d с: центр (%.1f, %.1f), с целью %d, ближ. враг %.1f, ближ. гоблин %.1f" % [(f + 1) / 60, c.x, c.y, eng, closest, closest_gob])
	get_tree().quit()
