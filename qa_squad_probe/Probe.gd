extends Node
## ЗОНД: копейщики из барака — один отряд из 60 или 60 одиночек? (спринт 18, письмо 7)
var main = null
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func(): print("СТОРОЖ"); get_tree().quit())
func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(2)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 500000.0)
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-46.0, 0.0, -46.0)
	await frames(2)
	var b: Building = Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(-20.0, 0.0, -46.0)
	await frames(2)
	print("pop_limit_enabled=%s" % str(GameManager.pop_limit_enabled))
	var ok: bool = b.train_from_config("spearman")
	print("заказ принят: %s, очередь %d" % [str(ok), b.production_queue.size()])
	var before: Dictionary = GameManager.squads.duplicate()
	var guard := 0
	while guard < 2400 and not (b.production_queue.is_empty() and b._pending_spawns.is_empty()):
		b._production_timer = 99999.0
		b._row_gate = 0.0
		await get_tree().process_frame
		guard += 1
	await frames(5)
	var news: Array = []
	for sid in GameManager.squads:
		if not before.has(sid):
			news.append(sid)
	print("новых отрядов: %d" % news.size())
	for sid in news:
		var sq: Dictionary = GameManager.squads[sid]
		var n: int = 0
		for m in sq["members"]:
			if is_instance_valid(m): n += 1
		print("  sid=%d type=%s members=%d slots=%d" % [sid, str(sq.get("type")), n, (sq.get("slots", []) as Array).size()])
	var solo := 0
	var sp_total := 0
	for u in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_PLAYER)):
		if u is Spearman:
			sp_total += 1
			if (u as Unit).squad_id <= 0: solo += 1
	print("копейщиков всего %d, без отряда %d" % [sp_total, solo])
	# выделение кликом по одному — весь отряд?
	var sm = main.selection_manager
	var one = null
	for u in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_PLAYER)):
		if u is Spearman: one = u; break
	if one != null:
		sm.select_units([one])
		print("select_units([один]) → выделено %d" % sm.selected_units.size())
		if sm.has_method("select_squad_of"):
			sm.select_squad_of(one)
		print("squad_id первого = %d, состав отряда %d" % [(one as Unit).squad_id, GameManager.squad_members((one as Unit).squad_id).size()])
	get_tree().quit()
