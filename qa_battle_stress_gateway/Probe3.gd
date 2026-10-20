extends Node
## Зонд: [F1] к крепости, поставленной стендом — почему не всасывает
var main = null
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(150.0).timeout.connect(func(): get_tree().quit())
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
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(10)
	var sm = main.selection_manager
	var hud = main.hud
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai"]:
		var n = main.get(k)
		if n != null: n.set_process(false); n.set_physics_process(false)
	var cp: Vector3 = main.PLAYER_BASE_ANCHOR
	main._clear_area_of_resources(cp, 12.0)
	main._clear_trees(cp, 12.0)
	var cb: Building = load("res://scripts/Castle.gd").new()
	cb.faction = 0
	main.world_add(cb)
	cb.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pf(4)
	var p := Vector3(-55.0, 0.0, -22.0)
	main._clear_trees(p, 30.0)
	var sids: Array = []
	var men: Array = []
	for k in range(4):
		var sid: int = GameManager.new_squad(0, "spearman")
		for i in range(60):
			var u := _unit("spearman", 0, p + Vector3(float(i / 6) * 0.65, 0, -18.0 + 12.0 * float(k) + float(i % 6) * 0.65))
			GameManager.add_to_squad(sid, u)
			men.append(u)
		sids.append(sid)
	await pf(10)
	sm.select_units(men)
	await pf(2)
	hud._on_squad_cmd("F1")
	await pf(4)
	print("  gate ", cb._gate_position().round(), " incoming ", cb._incoming, " processing ", cb.is_processing())
	for f in range(60 * 200):
		await get_tree().physics_frame
		if f % 600 == 0:
			var line := "  t=%d: " % (f / 60)
			for sid2 in sids:
				var near5 := 0
				var moved := 0
				var gar := 0
				var alive := 0
				var dmin := INF
				var idle := 0
				for m in GameManager.squads[sid2]["members"]:
					if not is_instance_valid(m) or (m as Unit).is_dead(): continue
					alive += 1
					if (m as Unit).garrisoned: gar += 1; continue
					var d: float = (m as Unit).global_position.distance_to(cb._gate_position())
					dmin = minf(dmin, d)
					if d <= 5.0: near5 += 1
					if (m as Unit).moved_recently(): moved += 1
					if (m as Unit).state == 0: idle += 1
				line += "sq%d[in %d/%d dmin %.1f <5m %d moved %d idle %d retreat %s slot %d] " % [sid2, gar, alive, dmin, near5, moved, idle, str(GameManager.squad_is_to_castle(sid2)), cb._slot_of(sid2)]
			print(line + " incoming " + str(cb._incoming) + " enter_r %.1f" % cb._enter_radius(sids[0]))
		var done := true
		for sid3 in sids:
			if cb._slot_of(sid3) < 0: done = false
		if done:
			print("  ВСЕ ВОШЛИ на %d с" % (f / 60))
			break
	get_tree().quit()
