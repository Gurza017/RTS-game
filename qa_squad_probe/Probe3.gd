extends Node
## ЗОНД 3: где стоят строители относительно фундамента (письмо 9, п. 2)
const _CSite := preload("res://scripts/ConstructionSite.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
var main = null
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func(): print("СТОРОЖ"); get_tree().quit())
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(3)
	main.start_game()
	await frames(3)
	var ws: Array = []
	for u in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_PLAYER)):
		if u is Worker: ws.append(u)
	var origin: Vector3 = (ws[0] as Node3D).global_position
	print("рабочих %d, состояния на старте: %s" % [ws.size(), str(ws.map(func(w): return int((w as Unit).state)))])
	var pos := origin + Vector3(0.0, 0.0, -14.0)
	pos.y = GameManager.get_terrain_height(pos.x, pos.z)
	var site: Building = _CSite.new()
	site.faction = Constants.FACTION_PLAYER
	site.target_id = "barracks"
	site.target_name = "Бараки"
	site.build_time = 9999.0
	site.build_size = _UCfg.building_size("barracks")
	main.world_add(site)
	site.global_position = pos
	for w in ws:
		(w as Worker).command_build(site)
	await pframes(60 * 25)
	var sp = site.get("_site_sprite")
	if sp != null:
		var q: QuadMesh = (sp as MeshInstance3D).mesh
		print("спрайт стройки: квад %.2f x %.2f м, y узла %.2f, build_size %s" % [q.size.x, q.size.y, (sp as Node3D).position.y, str(site.build_size)])
	print("центр площадки %s" % str(site.global_position))
	for w in ws:
		var p: Vector3 = (w as Node3D).global_position
		var d := Vector2(p.x - pos.x, p.z - pos.z)
		print("  рабочий dxz=(%.2f, %.2f) |d|=%.2f settled=%s state=%d" % [d.x, d.y, d.length(), str(w.get("_build_settled")), int((w as Unit).state)])
	get_tree().quit()
