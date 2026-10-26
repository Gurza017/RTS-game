extends Node
## ЗОНД: почему всадник у занятой точки встаёт без вызволения (ТЗ 21.10)
const G := Constants.FACTION_GOBLIN
var main: Node = null
func _ready() -> void:
	call_deferred("_run")
func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
func _spawn(kind: String, at: Vector3, fac: int) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	var at := Vector3(-80, 0, -10)
	main._clear_trees(at, 30)
	var sa: int = GameManager.new_squad(G, "goblin_spearman")
	var blocker := _spawn("goblin_spearman", at, G)
	GameManager.add_to_squad(sa, blocker)
	await pframes(30)
	blocker.command_move(at)
	await pframes(60)
	var mode: String = ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("mode="):
			mode = String(a).substr(5)
	if mode == "dormant":
		blocker.set_dormant(true)
	elif mode == "enemy":
		blocker.queue_free()
		blocker = _spawn("spearman", at, Constants.FACTION_PLAYER)
		await pframes(5)
		blocker.set_tick(false)
	print("mode=", mode)
	var sb: int = GameManager.new_squad(G, "goblin_rider")
	var r := _spawn("goblin_rider", at + Vector3(0, 0, -10), G)
	GameManager.add_to_squad(sb, r)
	await pframes(10)
	r.command_move(at)
	for s in range(12):
		await pframes(30)
		print("t=%.1f st=%d dist=%.2f mt=%s settled=%s streak=%d blk=%.2f unst=%d" % [float(s + 1) * 0.5, int(r.state),
			Vector2(r.global_position.x - at.x, r.global_position.z - at.z).length(), str(r.move_target - at),
			r._settled, r._stuck_streak, Vector2(blocker.global_position.x - at.x, blocker.global_position.z - at.z).length(), Unit.unstuck_total])
	get_tree().quit()
