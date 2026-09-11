extends Node

## Зонд: чем стреляет лучник и чем гнолл. Печатает слой, текстуру и признак
## `bone` у обоих снарядов — без вердиктов, это диагностика.

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func():
		print("СТОРОЖ"); get_tree().quit())

func pf(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(uid: String, fac: int, at: Vector3, main) -> Unit:
	var sc: PackedScene = Building.PRELOAD_SCENES.get(uid)
	var u: Unit = sc.instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, main.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _tex_name(mm) -> String:
	if mm == null or mm.mat == null:
		return "<нет слоя>"
	var t: Texture2D = mm.mat.get_shader_parameter("albedo_tex") as Texture2D
	if t == null:
		return "<нет текстуры>"
	return "%s %s" % [t.get_class(), str(t.get_size())]

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	await pf(6)

	var a: Unit = _spawn("archer", Constants.FACTION_PLAYER, Vector3(0, 0, 0), main)
	var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN, Vector3(4, 0, 0), main)
	var tgt: Unit = _spawn("spearman", Constants.FACTION_ENEMY, Vector3(0, 0, 8), main)
	await pf(4)
	a.set_tick(false)
	g.set_tick(false)
	tgt.set_tick(false)

	print("\n═════ ЧЕМ СТРЕЛЯЕТ КТО ═════")
	# ПОРЯДОК ВАЖЕН: сначала ГНОЛЛ, чтобы слой костей завёлся первым
	g._on_attack_fired(tgt, 4.0)
	await pf(2)
	print("  после броска гнолла: слой стрел [%s], слой костей [%s]" % [
		_tex_name(GameManager.arrows_mm), _tex_name(GameManager.bones_mm)])
	print("  в полёте: стрел %d, костей %d" % [
		GameManager.arrows_mm.flight_count(), GameManager.bones_mm.flight_count()])

	a._on_attack_fired(tgt, 10.0)
	await pf(2)
	print("  после выстрела лучника: слой стрел [%s], слой костей [%s]" % [
		_tex_name(GameManager.arrows_mm), _tex_name(GameManager.bones_mm)])
	print("  в полёте: стрел %d, костей %d" % [
		GameManager.arrows_mm.flight_count(), GameManager.bones_mm.flight_count()])
	print("  core_id: стрелы %d, кости %d" % [
		GameManager.arrows_mm.core_id, GameManager.bones_mm.core_id])
	print("  пулы: стрел %d, костей %d" % [
		GameManager.arrow_pool_size(), GameManager.bone_pool_size()])

	# Кто из живых узлов Arrow какой признак носит
	var n_bone := 0
	var n_arrow := 0
	for node in main.world_root().get_children():
		if node.get_script() == null:
			continue
		if not ("bone" in node):
			continue
		if bool(node.get("bone")):
			n_bone += 1
		else:
			n_arrow += 1
	print("  узлов снарядов на карте: с признаком кости %d, без %d" % [n_bone, n_arrow])
	get_tree().quit()
