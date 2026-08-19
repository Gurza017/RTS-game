extends Node

## ВРЕМЕННЫЙ СТЕНД: СНИМКИ ВИЗУАЛЬНЫХ ПРАВОК ДНЯ ФИКСОВ.
## headless не рисует ничего, поэтому окно обязательно (как qa_veg/Shot).
## Запуск: godot --path . res://qa_shotvis/Shot.tscn -- --out=<абс.путь без .png>
## Пишет четыре файла: _tree, _ore, _stump, _rally.

var _out := ""
var _size := Vector2i(1280, 720)
var main = null

func _ready() -> void:
	call_deferred("_run")

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(suffix: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок: %s_%s.png" % [_out, suffix])

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--size="):
			var p := s.substr(7).split("x")
			if p.size() == 2:
				_size = Vector2i(int(p[0]), int(p[1]))
	if _out == "":
		push_error("нужен --out=<путь без расширения>")
		get_tree().quit(1)
		return
	# Окно проекта открывается Maximized (project.godot), и window_set_size в
	# этом режиме молча игнорируется — снимок выходил 3440 в ширину, камера
	# охватывала полполяны и разглядеть тонкую линию было нельзя
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_size)
	get_tree().root.content_scale_size = _size

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	# MAIN._process КАЖДЫЙ КАДР ОПРАШИВАЕТ КУРСОР и сбрасывает подсветку в то,
	# на что наведена мышь (то есть в null). Без этого выключения принудительная
	# подсветка гасла раньше, чем снимался кадр, и оба снимка выходили одинаковые
	main.set_process(false)
	var cam = main.get("_camera")
	if cam != null:
		cam.set_process(false)
		# Ближе штатного минимума: тонкую линию в 5 см надо разглядеть
		cam.min_height = 8.0

	# ── 1. Дерево: кольцо у комля + подмес на стволе ────────────────────────
	# Берём ОДИНОКОЕ дерево: в чаще кольцо у комля закрыто кронами соседей и
	# судить по такому снимку нельзя. Снимаем пару «до/после», иначе силу
	# подмеса не с чем сравнить
	# Дерево сажаем СВОЁ, на заведомо чистом месте: в готовом лесу кольцо у
	# комля закрывает крона соседа, стоящего ближе к камере, и судить по такому
	# снимку нельзя (первый прогон именно так и вышел)
	var spot0: Vector3 = _clear_spot()
	var tree := ResourceNode.new()
	tree.resource_type = Constants.RESOURCE_WOOD
	tree.remaining = 500.0
	main.world_add(tree)
	tree.global_position = Vector3(spot0.x,
		GameManager.get_terrain_height(spot0.x, spot0.z), spot0.z)
	await frames(6)
	cam.jump_to(tree.global_position, 9.0)
	main._update_hover_highlight(null)
	await _shot("tree_off")
	main._update_hover_highlight(tree)
	await _shot("tree")

	# ── 2. Куча руды: тонкий тёмно-зелёный овал, без заливки ────────────────
	var ore: ResourceNode = _find(Constants.RESOURCE_GOLD)
	if ore != null:
		cam.jump_to(ore.global_position, 14.0)
		main._update_hover_highlight(ore)
		await _shot("ore")
		# ── 3. Та же куча, выработанная на три четверти ─────────────────────
		var info: Dictionary = main.res_clusters.get(ore.cluster_id, {})
		var mc = info.get("mine", null)
		if mc != null:
			mc.extract(mc.max_stock * 0.75)
			await frames(3)
			await _shot("ore_depleted")

	# ── 4. Пенёк ────────────────────────────────────────────────────────────
	var tree2: ResourceNode = tree
	if tree2 != null:
		main._update_hover_highlight(null)
		cam.jump_to(tree2.global_position, 9.0)
		tree2.extract(1e9)
		await frames(4)
		await _shot("stump")

	# ── 5. Флажок точки сбора ───────────────────────────────────────────────
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	var spot := Vector3(0.0, 0.0, 0.0)
	b.global_position = Vector3(spot.x - 12.0,
		GameManager.get_terrain_height(spot.x - 12.0, spot.z), spot.z)
	await frames(4)
	b.set_rally_point(spot)
	b.set_selected(true)
	cam.jump_to(spot, 11.0)
	await _shot("rally")

	await _shot_spawn()
	await _shot_fog()
	await _shot_panel()

	print("=== SHOTVIS DONE ===")
	get_tree().quit(0)

func _find(rtype: int, skip: ResourceNode = null) -> ResourceNode:
	var best: ResourceNode = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null or rn.resource_type != rtype or rn == skip:
			continue
		var d: float = rn.global_position.length()
		if d < bd:
			bd = d
			best = rn
	return best

# ── БЛОК 1: ОТРЯД ВЫХОДИТ ИЗ НАРИСОВАННЫХ ДВЕРЕЙ, А НЕ СБОКУ ────────────────
func _shot_spawn() -> void:
	var at: Vector3 = _clear_spot()
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	await frames(6)
	b.squad_size = 20
	b._row_gate = 0.0
	b.queue_unit("spearman", {}, 0.01)
	if not b.production_queue.is_empty():
		(b.production_queue[0] as Dictionary)["time"] = 0.01
	var cam2 = main.get("_camera")
	cam2.jump_to(b.global_position + Vector3(0.0, 0.0, 5.0), 22.0)
	for _i in range(420):
		b._row_gate = 0.0
		await get_tree().process_frame
	await _shot("spawn")

# ── БЛОК 2: НЕРАЗВЕДАННОЕ — СПЛОШНАЯ ЧЕРНОТА ───────────────────────────────
func _shot_fog() -> void:
	if GameManager.fog == null:
		return
	GameManager.fog.enabled = true
	(GameManager.fog as Node3D).visible = true
	GameManager.fog.refresh()
	var cam3 = main.get("_camera")
	cam3.jump_to(Vector3.ZERO, cam3.max_height)
	await _shot("fog")
	cam3.jump_to(main.PLAYER_BASE_ANCHOR, cam3.max_height)
	await _shot("fog_base")

# ── БЛОК 4: НИЖНЯЯ ПЛАШКА + ОКНО СТАТОВ ────────────────────────────────────
func _shot_panel() -> void:
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	var at: Vector3 = _clear_spot()
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "warrior")
	var men: Array = []
	for i in range(30):
		var u := Warrior.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(at.x + float(i % 6) * 0.8, 0.0, at.z + float(i / 6) * 0.8)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await frames(6)
	# Немного опыта, чтобы шкала не была пустой
	GameManager.squads[sid]["kills"] = 12
	var sm = main.selection_manager
	sm._clear_selection()
	for u2 in men:
		sm._select(u2)
	GameManager.on_selection_changed(sm.selected_units)
	var cam4 = main.get("_camera")
	cam4.jump_to(at, 18.0)
	await _shot("panel")

## Дерево, у которого ближайший сосед дальше всех — то есть стоящее на виду
func _lonely_tree() -> ResourceNode:
	var best: ResourceNode = null
	var best_gap := -1.0
	var all: Array = []
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn != null and rn.resource_type == Constants.RESOURCE_WOOD:
			all.append(rn)
	for a in all:
		var ra: ResourceNode = a
		if ra.global_position.length() > 90.0:
			continue          # далеко от центра карты — камере туда незачем
		var gap := INF
		for b in all:
			var rb: ResourceNode = b
			if rb == ra:
				continue
			gap = minf(gap, ra.global_position.distance_to(rb.global_position))
		if gap > best_gap:
			best_gap = gap
			best = ra
	return best

## Точка, вокруг которой на 14 м нет ни ресурсов, ни воды
func _clear_spot() -> Vector3:
	for r in range(6, 70, 4):
		for a in range(0, 12):
			var ang: float = TAU * float(a) / 12.0
			var p := Vector3(cos(ang) * float(r), 0.0, sin(ang) * float(r))
			if main.is_water(p.x, p.z):
				continue
			var ok := true
			for n in get_tree().get_nodes_in_group("resource_nodes"):
				var rn := n as ResourceNode
				if rn != null and rn.global_position.distance_to(p) < 14.0:
					ok = false
					break
			if ok:
				return p
	return Vector3(0.0, 0.0, 40.0)
