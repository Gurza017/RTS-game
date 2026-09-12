extends Node
## ЗОНД 2: настоящий флоу партии — start_game, крепость и бараки через
## стройплощадку, лимит населения, найм копейщиков, СВОБОДНЫЙ ход времени
const _CSite := preload("res://scripts/ConstructionSite.gd")
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
func _site(id: String, at: Vector3) -> Building:
	var site: Building = _CSite.new()
	site.target_id = id
	site.faction = Constants.FACTION_PLAYER
	main.world_add(site)
	site.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	var before: Array = get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_PLAYER)).duplicate()
	site._complete()
	for b in get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_PLAYER)):
		if not (b in before) and b is Building and String((b as Building).building_id) == id:
			return b as Building
	return null
func _report(tag: String) -> void:
	var by_sid: Dictionary = {}
	var solo := 0
	var total := 0
	for u in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_PLAYER)):
		if u is Spearman and not (u as Unit).is_dead():
			total += 1
			var sid: int = (u as Unit).squad_id
			if sid <= 0: solo += 1
			by_sid[sid] = int(by_sid.get(sid, 0)) + 1
	print("  [%s] копейщиков %d, без отряда %d, по отрядам %s" % [tag, total, solo, str(by_sid)])
func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(3)
	main.start_game()
	GameManager.pop_limit_enabled = true
	await frames(3)
	var ws: Array = get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_PLAYER))
	var origin: Vector3 = (ws[0] as Node3D).global_position if not ws.is_empty() else Vector3.ZERO
	print("рабочих на старте %d, точка %s" % [ws.size(), str(origin)])
	var castle: Building = _site("castle", origin + Vector3(14.0, 0.0, 0.0))
	await frames(3)
	var bar: Building = _site("barracks", origin + Vector3(14.0, 0.0, 22.0))
	await frames(3)
	print("крепость=%s бараки=%s pop_allows(spearman)=%s" % [str(castle != null), str(bar != null), str(GameManager.pop_allows(Constants.FACTION_PLAYER, "spearman"))])
	var ok: bool = bar.train_from_config("spearman")
	print("заказ принят: %s очередь %d" % [str(ok), bar.production_queue.size()])
	# СВОБОДНЫЙ ход: таймер производства проматываем, но выход шеренг — как в игре
	bar._production_timer = 99999.0
	var t := 0
	while t < 60 * 40 and not (bar.production_queue.is_empty() and bar._pending_spawns.is_empty()):
		await get_tree().physics_frame
		t += 1
		if t % 60 == 0:
			_report("t=%ds" % (t / 60))
	await pframes(120)
	_report("итог")
	var sm = main.selection_manager
	var one = null
	for u in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_PLAYER)):
		if u is Spearman: one = u; break
	if one != null:
		var sid: int = (one as Unit).squad_id
		print("отряд %d: состав %d, слотов %d, в реестре type=%s" % [sid, GameManager.squad_members(sid).size(), (GameManager.squads.get(sid, {}).get("slots", []) as Array).size(), str(GameManager.squads.get(sid, {}).get("type"))])
		# Клик по одному бойцу — что выделяет игра?
		if sm.has_method("select_unit_or_squad"):
			sm.select_unit_or_squad(one)
		else:
			sm.select_units(GameManager.squad_members(sid))
		print("выделено %d, selected_squad_count=%d" % [sm.selected_units.size(), sm.selected_squad_count()])
	get_tree().quit()
