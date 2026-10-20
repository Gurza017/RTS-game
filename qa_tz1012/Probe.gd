extends Node
## Зонд: туши на марше — скорость по секундам (ТЗ 12.10.2026 «резко тормозят»)
var main = null
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	var base := Vector3(-20.0, 0.0, 40.0)
	var sid: int = main.spawn_goblin_squad("big_goblin", 5, base)
	var sid2: int = main.spawn_goblin_squad("goblin_spearman", 40, base + Vector3(0, 0, 8))
	await pframes(30)
	var goal := base + Vector3(110.0, 0.0, 0.0)
	for s in [sid, sid2]:
		var men: Array = GameManager.squads[s]["members"]
		var k := 0
		for m in men:
			var u := m as Unit
			if u.dormant:
				u.set_dormant(false)
			u.command_move(GameManager.land_target(goal + Vector3(float(k % 5) * 2.5, 0, float(k / 5) * 2.5)))
			k += 1
	var prev: Dictionary = {}
	for t in range(140):
		await pframes(30)
		var line := "t=%4.1f" % (float(t + 1) * 0.5)
		for m in GameManager.squads[sid]["members"]:
			var u := m as Unit
			var p: Vector3 = u.global_position
			var v: float = 0.0
			if prev.has(u):
				v = Vector2(p.x - prev[u].x, p.z - prev[u].z).length() / 0.5
			prev[u] = p
			line += " | (%.1f,%.1f) v=%.2f d=%.0f" % [p.x, p.z, v, Vector2(goal.x - p.x, goal.z - p.z).length()]
		print(line)
		if t == 2:
			var u0 := GameManager.squads[sid]["members"][0] as Unit
			print("  route: ", u0.get("_route"), " mt=", u0.move_target, " ford=", u0.get("_ford_stage"))
	get_tree().quit()
