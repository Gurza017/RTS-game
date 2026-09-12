extends Node
## Зонд: марш через реку вдали от брода (сценарий qa_rally2 C5) с маршрутом
var main = null
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(200.0).timeout.connect(func(): print("СТОРОЖ"); get_tree().quit())
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	print("bounds=%s nav_on=%s blocked=%d" % [str(GameManager.world_bounds_enabled), str(GameManager.nav_on()), GameManager.nav_cells_blocked])
	var from_p := Vector3(-35.0, 0.0, -26.0)
	var to_p := Vector3(35.0, 0.0, -26.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(10):
		var u: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var p := from_p + Vector3(float(i % 5) * 1.0, 0.0, float(i / 5) * 1.0)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(3)
	# Лагерь врага поперёк брода, как в qa_rally2 C5
	var camp: Array = []
	for i in range(12):
		var e: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
		e.faction = Constants.FACTION_ENEMY
		main.world_add(e)
		var ep := Vector3(-6.6 + float(i) * 1.2, 0.0, 0.0)
		e.global_position = Vector3(ep.x, GameManager.get_terrain_height(ep.x, ep.z), ep.z)
		e.sync_row()
		e.post_pos = e.global_position
		camp.append(e)
	await pframes(2)
	for e in camp:
		(e as Unit).command_move((e as Node3D).global_position)
	print("ford_route: %s" % str(GameManager.ford_route(from_p, to_p, 0.0)))
	print("nav_route from→ford0: %s" % str(GameManager.nav_route(from_p, Vector3(-12.5, 0, 0))))
	print("water at ford0? %s  nav_free ford0 %s" % [str(GameManager.is_water(-12.5, 0.0)), str(GameManager.nav_free(Vector3(-12.5, 0, 0)))])
	for u in men:
		(u as Unit).command_move(to_p + ((u as Node3D).global_position - from_p))
	var u0: Unit = men[0]
	print("route0: %s goal %s" % [str(u0.get("_route")), str(u0.get("_route_goal"))])
	for k in range(30):
		await pframes(60)
		var p: Vector3 = u0.global_position
		var moving := 0
		var attacking := 0
		for u in men:
			if (u as Unit).state == Unit.State.MOVING: moving += 1
			if (u as Unit).state == Unit.State.ATTACKING: attacking += 1
		print("t=%2d s: pos (%.1f, %.1f) state %d route_i %d/%d target (%.1f, %.1f) tgt %s | moving %d attacking %d" % [
			k + 1, p.x, p.z, int(u0.state), u0.route_index(), u0.route_size(), u0.move_target.x, u0.move_target.z,
			str(u0.attack_target != null), moving, attacking])
	get_tree().quit()
