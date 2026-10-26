extends Node
## Зонд разбора партии 26.10.2026: проход в лесной стене базы красных.
## Лог: t=2594 56 копейщиков трёх отрядов игрока сбились в кучу ~1.5 м у
## угла лесной клетки, выступающей в проход (x −175…−173, z 37.44…39.44),
## вызволение «no_progress» всем разом. Стены баз от зерна не зависят —
## сцена ставится на обычной карте. Три отряда копейщиков идут сквозь проход
## групповым ПКМ туда (с юга внутрь базы) и обратно. Вердиктов нет — числа:
## дошли, вызволений, сдач, бойцов в «куче» у угла (2.5 м) дольше 4 с.
## Запуск: godot --headless --path . res://qa_log_1026/Gap.tscn [-- dir=in|out|both]
const F := Constants.FACTION_PLAYER
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const CORNER := Vector3(-174.0, 0.0, 37.4)
const SOUTH := Vector3(-166.0, 0.0, 8.0)
const NORTH := Vector3(-163.0, 0.0, 62.0)
var main = null
var sm = null

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился")
		get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _squad(at: Vector3) -> int:
	var cfg: Dictionary = _UCfg.train_cfg("barracks", "spearman")
	var cnt: int = int(cfg.get("squad", 20))
	var cols: int = int(cfg.get("cols", 5))
	var sid: int = GameManager.new_squad(F, "spearman")
	for i in range(cnt):
		var u: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
		u.faction = F
		main.world_add(u)
		var p: Vector3 = at + Vector3((float(i % cols) - float(cols - 1) * 0.5) * 0.65, 0.0, float(i / cols) * 0.65)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
	return sid

func _run() -> void:
	var dir := "both"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("dir="): dir = String(a).substr(4)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	sm = main.selection_manager
	for k in ["enemy_ai", "gnoll_ai", "enemy_guard", "goblin_ai", "goblin_reserve"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
			n.set_physics_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit and (n0 as Unit).faction != F \
				and (n0 as Unit).global_position.distance_to(CORNER) < 120.0:
			(n0 as Unit).take_damage(1.0e12)
	await pframes(30)
	if dir == "in" or dir == "both":
		await _leg("ВНУТРЬ (юг → база)", SOUTH, NORTH)
	if dir == "out" or dir == "both":
		await _leg("НАРУЖУ (база → юг)", NORTH, SOUTH)
	get_tree().quit()

func _leg(tag: String, from: Vector3, to: Vector3) -> void:
	var sids: Array = []
	for i in range(3):
		sids.append(_squad(from + Vector3(-12.0 + 12.0 * float(i), 0.0, 0.0)))
	await pframes(30)
	var men: Array = []
	for s in sids:
		men.append_array(_members(int(s)))
	sm.select_units(men)
	await pframes(2)
	var u0: int = Unit.unstuck_total
	var g0: int = Unit.unstuck_giveups
	sm.order_at_world(to, false)
	var near_t: Dictionary = {}
	var pile_max := 0
	var arrived_at := -1.0
	for f in range(60 * 90):
		await get_tree().physics_frame
		if f % 30 != 0:
			continue
		var pile := 0
		var home := 0
		for u in men:
			if not is_instance_valid(u):
				continue
			var uu := u as Unit
			var p: Vector3 = uu.global_position
			if Vector2(p.x - CORNER.x, p.z - CORNER.z).length() < 2.5:
				near_t[uu] = float(near_t.get(uu, 0.0)) + 0.5
			if Vector2(p.x - uu.post_pos.x, p.z - uu.post_pos.z).length() < 3.0 and uu.state == Unit.State.IDLE:
				home += 1
		for uu in near_t:
			if float(near_t[uu]) > 4.0:
				pile += 1
		pile_max = maxi(pile_max, pile)
		if home >= men.size() * 9 / 10 and arrived_at < 0.0:
			arrived_at = float(f) / 60.0
			break
	var home2 := 0
	var mid_x: Array = []
	for u in men:
		var uu := u as Unit
		if Vector2(uu.global_position.x - uu.post_pos.x, uu.global_position.z - uu.post_pos.z).length() < 3.0:
			home2 += 1
		mid_x.append(snappedf(uu.global_position.x, 0.1))
	print("%s: бойцов %d, дошли %d, 90%% за %s с, вызволений %d, сдач %d, у угла >4 с: %d" % [tag, men.size(), home2,
		("%.1f" % arrived_at) if arrived_at >= 0.0 else "НЕ ДОШЛИ", Unit.unstuck_total - u0, Unit.unstuck_giveups - g0, pile_max])
	for s in sids:
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)
	await pframes(30)
