extends Node
## ЗОНД: ширина панели бараков до/после найма и с гарнизоном на крыше

const F := Constants.FACTION_PLAYER
var main = null

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(200.0)
	t.timeout.connect(func():
		print("  СТОРОЖ")
		get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var px: float = at.x - float(i / cols) * 0.9
		var pz: float = at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35
		var u: Unit = _spawn(kind, fac, Vector3(px, 0.0, pz))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _panel_buttons(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Button:
			out.append(c)
		if c is Control:
			_panel_buttons(c, out)

func _dump(hud, tag: String) -> void:
	await frames(3)
	var bp: Control = hud._bottom_panel
	var all: Array = []
	_panel_buttons(hud.button_container, all)
	var names: Array = []
	for b in all:
		var ic := ""
		for ch in (b as Button).get_children():
			var tr := ch as TextureRect
			if tr != null and tr.texture != null:
				ic = tr.texture.resource_path.get_file()
		names.append("%s[%s %.0fx%.0f]" % [(b as Button).text, ic, (b as Button).size.x, (b as Button).size.y])
	print("  %s: панель %.0f x %.0f, _panel_w %.0f, content %.0f; кнопки: %s" % [
		tag, bp.size.x, bp.size.y, hud._panel_w, bp.get_combined_minimum_size().x, str(names)])
	_walk(bp, 0)
	var qf = hud.get("_queue_frame")
	if qf != null and is_instance_valid(qf):
		print("    очередь: %.0f x %.0f" % [(qf as Control).size.x, (qf as Control).size.y])
	var gs = hud.get("_garrison_strip")
	if gs != null and is_instance_valid(gs):
		print("    полоса гарнизона: %.0f x %.0f at %.0f" % [(gs as Control).size.x, (gs as Control).size.y, (gs as Control).offset_left])

func _walk(n: Node, depth: int) -> void:
	if depth > 4:
		return
	for c in n.get_children():
		var cc := c as Control
		if cc == null:
			continue
		var ms: Vector2 = cc.get_combined_minimum_size()
		if cc.visible and (ms.x > 0.0 or cc.size.x > 30.0):
			print("      %s%s(%s) min %.0fx%.0f size %.0fx%.0f flags %d" % ["  ".repeat(depth), cc.name, cc.get_class(), ms.x, ms.y, cc.size.x, cc.size.y, cc.size_flags_horizontal])
		_walk(cc, depth + 1)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(4)
	var hud = main.hud
	var bp := Vector3(60.0, 0.0, -30.0)
	main._clear_area_of_resources(bp, 50.0)
	var b: Building = Barracks.new()
	b.faction = F
	main.world_add(b)
	b.global_position = Vector3(bp.x, GameManager.get_terrain_height(bp.x, bp.z), bp.z)
	await pframes(6)
	var sm0 = main.selection_manager
	sm0._clear_selection()
	sm0._select(b)
	GameManager.on_selection_changed(sm0.selected_units, true)
	await _dump(hud, "пусто")
	# 6 заказов
	for _i in range(6):
		b.train_from_config("spearman")
	await pframes(2)
	GameManager.on_selection_changed(sm0.selected_units, true)
	await _dump(hud, "6 заказов")
	# крепость для сравнения
	var c: Building = Castle.new()
	c.faction = F
	main.world_add(c)
	c.global_position = Vector3(bp.x + 30.0, 0.0, bp.z)
	await pframes(6)
	sm0._clear_selection()
	sm0._select(c)
	GameManager.on_selection_changed(sm0.selected_units, true)
	await _dump(hud, "крепость")
	# лучники на крыше бараков
	var ar: Array = _squad("archer", F, bp + Vector3(0, 0, 10), 30)
	await pframes(4)
	b.garrison_now(int(ar[0]))
	await pframes(4)
	sm0._clear_selection()
	sm0._select(b)
	GameManager.on_selection_changed(sm0.selected_units, true)
	await _dump(hud, "бараки с крышей")
	get_tree().quit()
