extends Node
var main = null
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit())
func pf(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(10)
	var ev = main.get("assault_event")
	var n := 0
	for b in get_tree().get_nodes_in_group("player_buildings"):
		n += 1
		print("  pb ", b.get_script().resource_path.get_file(), " stronghold=", (b.has_method("is_stronghold") and b.is_stronghold()))
	print("  player_buildings: ", n, " ; horde ", main.horde_alive(), " refusals ", main.horde_cap_refusals, " pending ", main.horde_spawn_pending())
	ev.set_clock(1799.9)
	var last := 0
	for f in range(60 * 16):
		await get_tree().physics_frame
		if ev.spawned.size() != last or f % 120 == 0:
			last = ev.spawned.size()
			print("  f=%d clock=%.2f spawned=%d q=%d spawn_t=%.2f pending=%d refusals=%d horde=%d chief=%s stage=%s rows=%s" % [f, ev.clock, ev.spawned.size(), ev._spawn_q.size(), ev._spawn_t, main.horde_spawn_pending(), main.horde_cap_refusals, main.horde_alive(), str(main.goblin_ai.chief_alive()), ev.wave_stage(), str(ev.spawned)])
	get_tree().quit()
