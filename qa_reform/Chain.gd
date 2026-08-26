extends Node
## Зонд: приказ снести лагерь построек не должен слетать после первого дома,
## а по исчерпании целей отряд обязан встать НА МЕСТЕ, а не уйти на старый пост.

var main = null
var sm = null

func _ready() -> void: call_deferred("_run")
func pf(n: int) -> void:
	for _i in range(n): await get_tree().physics_frame

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(8)
	sm = main.selection_manager
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null: GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"): (n as Node).queue_free()
	await pf(4)
	print("=== ЗОНД: ЛАГЕРЬ ПОСТРОЕК ===")

	# ТРИ ХИЖИНЫ РЯДОМ — как бунгало орков
	var camp := Vector3(-700.0, 0.0, -700.0)
	var huts: Array = []
	for i in range(3):
		var h = load("res://scripts/goblin/GoblinHut.gd").new()
		h.faction = Constants.FACTION_GOBLIN
		main.world_add(h)
		h.global_position = camp + Vector3(float(i) * 7.0, 0.0, 0.0)
		huts.append(h)
	await pf(8)

	# ОТРЯД ДАЛЕКО — чтобы «старый пост» был заметно в стороне
	var home := camp + Vector3(0.0, 0.0, -40.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "warrior")
	var men: Array = []
	for i in range(16):
		var u: Unit = load("res://scenes/units/Warrior.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(home.x + float(i % 4) * 0.8,
			GameManager.get_terrain_height(home.x, home.z), home.z + float(i / 4) * 0.8)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pf(6)
	# Ставим пост далеко от лагеря — приказом на движение
	for u1 in men:
		(u1 as Unit).command_move(home, false, Vector3.ZERO, false, true)
	await pf(120)
	print("  пост отряда: (%.0f, %.0f), лагерь: (%.0f, %.0f)" % [
		(men[0] as Unit).post_pos.x, (men[0] as Unit).post_pos.z, camp.x, camp.z])

	# ПРИКАЗ СНЕСТИ ПЕРВУЮ ХИЖИНУ
	for u2 in men:
		(u2 as Unit).command_attack(huts[0], true, true, true)
	await pf(30)
	print("  после приказа: замок у %d из %d" % [
		_locked(men), men.size()])

	for step in range(10):
		await pf(600)
		var alive := 0
		for h in huts:
			if is_instance_valid(h) and not (h as Building).is_dead(): alive += 1
		var c: Vector3 = GameManager.squad_centroid(sid)
		var far := 0.0
		for u3 in men:
			if is_instance_valid(u3):
				far = maxf(far, Vector2((u3 as Node3D).global_position.x - c.x,
					(u3 as Node3D).global_position.z - c.z).length())
		var u0 := men[0] as Unit
		if is_instance_valid(u0):
			var nb = u0._next_enemy_building()
			print("      зонд бойца: замок=%s дом=%s цель_жива=%s соседний_дом=%s дистанция_до_цели=%.1f обзор=%.1f" % [
				str(u0.target_lock), str(u0._lock_is_building),
				str(u0._lock_target != null and is_instance_valid(u0._lock_target)),
				"есть" if nb != null else "НЕТ",
				u0.global_position.distance_to((u0._lock_target as Node3D).global_position) if (u0._lock_target != null and is_instance_valid(u0._lock_target)) else -1.0,
				u0._lock_sight_range()])
		print("  +%2d с: хижин живо %d | замок у %d | центр (%.0f,%.0f) до лагеря %.0f м | разброс отряда %.1f м" % [
			(step + 1) * 10, alive, _locked(men), c.x, c.z,
			Vector2(c.x - camp.x, c.z - camp.z).length(), far])
		if alive == 0 and step > 2: break
	get_tree().quit(0)

func _locked(men: Array) -> int:
	var n := 0
	for u in men:
		if is_instance_valid(u) and (u as Unit).target_lock: n += 1
	return n
