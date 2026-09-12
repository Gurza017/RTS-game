extends Node
## ЗОНД 4: форма отряда лучников на выходе из стрелковой (письмо 9, п. 4)
var main = null
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(170.0).timeout.connect(func(): print("СТОРОЖ"); get_tree().quit())
func _dump(tag: String, men: Array, c: Vector3, dirv: Vector3) -> void:
	var side := Vector3(-dirv.z, 0.0, dirv.x)
	var pts: Array = []
	for m in men:
		if not is_instance_valid(m): continue
		var p: Vector3 = (m as Node3D).global_position - c
		pts.append(Vector2(p.dot(side), p.dot(dirv)))
	pts.sort_custom(func(a, b): return a.y < b.y if absf(a.y - b.y) > 0.25 else a.x < b.x)
	print("  [%s] %d бойцов, (вбок, вперёд):" % [tag, pts.size()])
	var line := ""
	var last_y := -1e9
	for q in pts:
		if absf(q.y - last_y) > 0.25:
			if line != "": print("    " + line)
			line = "y=%5.2f:" % q.y
			last_y = q.y
		line += " %5.2f" % q.x
	if line != "": print("    " + line)
func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(3)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 500000.0)
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-60.0, 0.0, -60.0)
	await frames(2)
	var ar: Building = load("res://scripts/Archery.gd").new()
	ar.faction = Constants.FACTION_PLAYER
	main.world_add(ar)
	ar.global_position = Vector3(-30.0, 0.0, -60.0)
	await frames(2)
	# 1) без точки сбора
	ar.train_from_config("archer")
	var before: Dictionary = GameManager.squads.duplicate()
	var guard := 0
	while guard < 3000 and not (ar.production_queue.is_empty() and ar._pending_spawns.is_empty()):
		ar._production_timer = 99999.0
		await get_tree().physics_frame
		guard += 1
	await pframes(60 * 8)
	var sid1 := -1
	for sid in GameManager.squads:
		if not before.has(sid): sid1 = sid
	var men1: Array = GameManager.squad_members(sid1)
	var c1: Vector3 = GameManager._centroid_of(men1)
	var gate: Vector3 = ar._gate_position()
	var d1: Vector3 = (c1 - gate); d1.y = 0.0; d1 = d1.normalized()
	_dump("без точки сбора, ось от ворот", men1, c1, d1)
	_dump("без точки сбора, ось Z", men1, c1, Vector3(0, 0, 1))
	# 2) с точкой сбора по диагонали
	ar.set_rally_point(Vector3(10.0, 0.0, -20.0))
	before = GameManager.squads.duplicate()
	ar.train_from_config("archer")
	guard = 0
	while guard < 3000 and not (ar.production_queue.is_empty() and ar._pending_spawns.is_empty()):
		ar._production_timer = 99999.0
		await get_tree().physics_frame
		guard += 1
	await pframes(60 * 30)
	var sid2 := -1
	for sid in GameManager.squads:
		if not before.has(sid) and String(GameManager.squads[sid].get("type")) == "archer" and int(GameManager.squads[sid].get("faction")) == Constants.FACTION_PLAYER: sid2 = sid
	var men2: Array = GameManager.squad_members(sid2)
	var c2: Vector3 = GameManager._centroid_of(men2)
	var course: Vector3 = GameManager.squad_course(sid2)
	print("  курс отряда %s, центр %s, slots %d" % [str(course), str(c2), (GameManager.squads[sid2].get("slots", []) as Array).size()])
	var d2: Vector3 = course if course.length() > 0.1 else Vector3(0, 0, 1)
	_dump("с точкой сбора, ось курса", men2, c2, d2.normalized())
	get_tree().quit()
