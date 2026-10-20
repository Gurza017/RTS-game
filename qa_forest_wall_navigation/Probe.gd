extends Node
## Зонд: почему красные по приказу атаки за стену снимают цель
const WALL_X := -70.0
var main = null
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(200.0).timeout.connect(func(): get_tree().quit())
func pf(n: int) -> void:
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
func _squad(uid: String, f: int, at: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		GameManager.add_to_squad(sid, _unit(uid, f, at + Vector3(float(i / 6) * 0.65, 0, float(i % 6) * 0.65)))
	return sid
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(10)
	for k in ["enemy_ai", "gnoll_ai", "enemy_guard", "goblin_ai", "goblin_reserve"]:
		var n = main.get(k)
		if n != null: n.set_process(false); n.set_physics_process(false)
	var centre := Vector3(WALL_X, 0.0, -12.0)
	main._clear_area_of_resources(centre, 75.0)
	main._clear_trees(centre, 75.0)
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if n0 is Unit and ((n0 as Unit).faction != 0 or (n0 as Unit).stat_id == "worker") and (n0 as Unit).global_position.distance_to(centre) < 110.0:
			(n0 as Unit).take_damage(1.0e12)
	await pf(4)
	var z := -76.0
	while z <= 16.0:
		main._wall_row(Vector2(WALL_X, z), Vector2(1.0, 0.0), 3.0)
		z += main.WALL_STEP
	await pf(60 * 3)
	var arch: int = _squad("archer", 0, Vector3(WALL_X - 4.5, 0, -12.0), 30)
	var red: int = _squad("spearman", 1, Vector3(WALL_X + 5.5, 0, -12.0), 30)
	await pf(30)
	Unit.losses_frozen = true
	GameManager.squad_attack_squad(red, arch, true)
	await pf(2)
	var men: Array = GameManager.squads[red]["members"]
	var u: Unit = men[0]
	for f in range(60 * 60):
		await get_tree().physics_frame
		if f % 60 == 0 or (f >= 60 * 25 and f % 15 == 0 and f <= 60 * 40):
			var t = u.attack_target
			var tp: Vector3 = (t as Node3D).global_position if t != null and is_instance_valid(t) else Vector3.INF
			var mp: Vector3 = u.global_position
			var line := "  t=%.2f (%.1f,%.1f) st%d" % [f / 60.0, mp.x, mp.z, int(u.state)]
			if tp.x != INF:
				var d: float = mp.distance_to(tp)
				var kk: float = maxf(u.reach() - 0.5, 0.0) / maxf(d, 0.01)
				var ntp := Vector3(tp.x + (mp.x - tp.x) * kk, 0.0, tp.z + (mp.z - tp.z) * kk)
				line += " tgt=(%.1f,%.1f) d=%.1f reach=%.1f blk_tp=%s blk_ntp=%s free_tp=%s cliff_tp=%s free_ntp=%s route=%d/%d vel=%.2f contact=%s detour=%s dead=%s" % [
					tp.x, tp.z, d, u.reach(), str(GameManager.nav_blocked(mp, tp, u._nav_clear)), str(GameManager.nav_blocked(mp, ntp, u._nav_clear)),
					str(GameManager.army.nav_free(tp.x, tp.z)), str(GameManager.is_cliff(tp.x, tp.z)), str(GameManager.army.nav_free(ntp.x, ntp.z)),
					u._atk_route_i, u._atk_route.size(), u.velocity.length(), str(u._enemy_contact), "-", str(u._nav_dead_end)]
			print(line)
	get_tree().quit()
