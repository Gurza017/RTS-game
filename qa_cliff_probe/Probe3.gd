extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8): await get_tree().process_frame
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = true
	var z0: float = main.FORD_Z - main.FORD_HALF - 40.0
	var ax: float = main.river_x(z0)
	var off: float = main.RIVER_HALF_W + main.RIVER_BANK + 14.0
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(24):
		var col: int = i % 6
		var rank: int = i / 6
		var px: float = ax - off - float(rank) * 1.0
		var pz: float = z0 + (float(col) - 2.5) * 1.0
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	for _i in range(6): await get_tree().physics_frame
	var goal := Vector3(ax + off, 0.0, z0)
	var c0: Vector2 = GameManager.squad_centre_xz(sid)
	print("центр отряда (%.1f, %.1f), цель (%.1f, %.1f)" % [c0.x, c0.y, goal.x, goal.z])
	for u in men:
		var p: Vector3 = u.global_position
		var tgt := Vector3(goal.x + (p.x - c0.x), 0.0, goal.z + (p.z - c0.y))
		u.command_move(GameManager.land_target(tgt), false, Vector3.ZERO, false, true)
	var pl: Array = main.plateau_list()[0]
	for k in range(24):
		var uu: Unit = men[k]
		var r0: float = Vector2(uu.global_position.x - float(pl[0]), uu.global_position.z - float(pl[1])).length()
		print("  старт %2d (%.1f,%.1f) r=%.1f скала=%s" % [k, uu.global_position.x, uu.global_position.z, r0, str(GameManager.is_cliff(uu.global_position.x, uu.global_position.z))])
	for sec in range(0, 180, 30):
		for _f in range(600): await get_tree().physics_frame
		var c: Vector2 = GameManager.squad_centre_xz(sid)
		var moving := 0
		var cliff := 0
		for u in men:
			if (u as Unit).state == Unit.State.MOVING: moving += 1
			if GameManager.is_cliff(u.global_position.x, u.global_position.z): cliff += 1
		var u0: Unit = men[0]
		print("t=%3d центр (%.1f, %.1f) идут %d на скале %d" % [sec + 10, c.x, c.y, moving, cliff])
		for k in range(24):
			var uu: Unit = men[k]
			var r1: float = Vector2(uu.global_position.x - float(pl[0]), uu.global_position.z - float(pl[1])).length()
			print("  %2d (%.1f,%.1f) r=%.1f скала=%s цель (%.1f,%.1f) st=%d" % [k, uu.global_position.x, uu.global_position.z, r1, str(GameManager.is_cliff(uu.global_position.x, uu.global_position.z)), uu.move_target.x, uu.move_target.z, uu.state])
	get_tree().quit()
