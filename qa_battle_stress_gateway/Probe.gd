extends Node
## Зонд географии для qa_battle_stress_gateway: печатает ключевые точки карты
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(10):
		await get_tree().physics_frame
	print("PLAYER_BASE ", main.PLAYER_BASE_ANCHOR, " ENEMY_BASE ", main.ENEMY_BASE_ANCHOR)
	print("river_x(0)=", main.river_x(0.0), " river_x(-80)=", main.river_x(-80.0), " river_x(80)=", main.river_x(80.0))
	print("village ", main.goblin_village_center())
	print("mines ", main.territory_mine_spots())
	for l in GameManager.troll_lairs:
		if is_instance_valid(l):
			print("lair ", (l as Node3D).global_position, " fac ", l.faction)
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and int(b.faction) != Constants.FACTION_PLAYER:
			print("bld ", b.get_script().resource_path.get_file(), " ", (b as Node3D).global_position.round(), " fac ", b.faction)
	var cnt := {}
	for u in get_tree().get_nodes_in_group("all_units"):
		if u is Unit:
			var k: String = "%d:%s" % [int(u.faction), u.stat_id]
			cnt[k] = int(cnt.get(k, 0)) + 1
	print("units ", cnt)
	print("map half ", main.MAP_HALF_X, " ", main.MAP_HALF_Z)
	get_tree().quit()
