extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = true
	var z0: float = main.FORD_Z - main.FORD_HALF - 40.0
	var start := Vector3(main.river_x(z0) - 28.0, 0.0, z0)
	var goal := Vector3(main.river_x(z0) + 28.0, 0.0, z0)
	var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(start.x, GameManager.get_terrain_height(start.x, start.z), start.z)
	u.sync_row()
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	GameManager.add_to_squad(sid, u)
	for _i in range(2): await get_tree().physics_frame
	for pl in main.plateau_list():
		print("плато: центр (%.1f, %.1f) r_flat %.1f h %.1f спуск %.0f°" % [float(pl[0]), float(pl[1]), float(pl[2]), float(pl[3]), rad_to_deg(float(pl[4]))])
	print("PLATEAU_MINE_R=%s STEEP=%s GENTLE=%s CONE=%s" % [str(main.PLATEAU_MINE_R), str(main.PLATEAU_RAMP_STEEP), str(main.PLATEAU_RAMP_GENTLE), str(main.PLATEAU_RAMP_CONE)])
	var lt: Vector3 = GameManager.land_target(goal)
	print("start (%.1f,%.1f) cliff=%s water=%s; goal (%.1f,%.1f) → land_target (%.1f,%.1f) cliff=%s" % [start.x, start.z, str(GameManager.is_cliff(start.x, start.z)), str(GameManager.is_water(start.x,start.z)), goal.x, goal.z, lt.x, lt.z, str(GameManager.is_cliff(lt.x, lt.z))])
	u.command_move(lt, false, Vector3.ZERO, false, true)
	for sec in range(60):
		for _f in range(60): await get_tree().physics_frame
		var p: Vector3 = u.global_position
		var d: Vector3 = (u.move_target - p); d.y = 0.0
		var nd: Vector3 = d.normalized() * 0.5
		print("t=%2d pos (%.1f,%.1f) state=%d cliff_here=%s cliff_ahead=%s water_ahead=%s tgt (%.1f,%.1f) vel=%.2f soa=%d" % [sec, p.x, p.z, u.state, str(GameManager.is_cliff(p.x,p.z)), str(GameManager.is_cliff(p.x+nd.x,p.z+nd.z)), str(GameManager.is_water(p.x+nd.x,p.z+nd.z)), u.move_target.x, u.move_target.z, u.velocity.length(), u._soa])
	var pc: Vector3 = u.global_position
	print("локальная карта 0.1 м вокруг (%.2f, %.2f): строки z−1..z+1, столбцы x−1..x+1" % [pc.x, pc.z])
	for dz in range(-10, 11):
		var ln := ""
		for dx in range(-10, 11):
			var cx: float = pc.x + float(dx) * 0.1
			var cz: float = pc.z + float(dz) * 0.1
			ln += ("@" if (dx == 0 and dz == 0) else ("#" if GameManager.is_cliff(cx, cz) else "."))
		print(ln)
	get_tree().quit()
