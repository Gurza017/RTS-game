extends Node
## Зонд: [F1] у моно-отряда и взгляд/лента туши при ударе
var main = null
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(200.0).timeout.connect(func(): get_tree().quit())
func pf(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(10)
	var sm = main.selection_manager
	var hud = main.hud
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai"]:
		var n = main.get(k)
		if n != null: n.set_process(false); n.set_physics_process(false)
	# ── F1 ──
	var p := Vector3(-110.0, 0.0, -22.0)
	main._clear_trees(p, 20.0)
	var sid: int = GameManager.new_squad(0, "spearman")
	var men: Array = []
	for i in range(12):
		var u := _unit("spearman", 0, p + Vector3(float(i / 4), 0, float(i % 4)))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pf(10)
	sm.select_units(men)
	await pf(2)
	var castles: Array = []
	for b in get_tree().get_nodes_in_group("player_buildings"):
		print("  bld ", b.get_script().resource_path.get_file(), " is Castle=", b is Castle, " stronghold=", (b.has_method("is_stronghold") and b.is_stronghold()), " at ", (b as Node3D).global_position.round())
		if b is Castle and b.is_stronghold(): castles.append(b)
	print("  selected ", sm.selected_units.size(), " squad ids ", sm.selected_squad_ids(), " castles ", castles.size())
	if not castles.is_empty():
		print("  limit ", castles[0].garrison_limit(), " accepts spearman ", castles[0].garrison_accepts("spearman"), " garrison ", castles[0].garrison.size())
	hud._on_squad_cmd("F1")
	await pf(4)
	print("  after F1: to_castle=", GameManager.squad_is_to_castle(sid), " retreating=", men[0].retreating, " hud=", hud.active_squad_cmd(), " state=", men[0].state)
	# ── туша ──
	var q := Vector3(-70.0, 0.0, 30.0)
	main._clear_trees(q, 20.0)
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if n0 is Unit and (n0 as Unit).faction == 2 and (n0 as Unit).global_position.distance_to(q) < 80.0:
			(n0 as Unit).take_damage(1.0e12)
	await pf(4)
	var big: Unit = _unit("big_goblin", 2, q)
	var vs: Array = []
	for k in range(5):
		var a: float = deg_to_rad(-40.0 + 20.0 * float(k))
		var v: Unit = _unit("spearman", 0, q + Vector3(cos(a), 0.0, sin(a)) * 2.6)
		v.set_tick(false)
		vs.append(v)
	await pf(4)
	print("  big facing before ", big._facing, " look_bound ", big._look_bound(), " anim ", big.anim_shown())
	big.command_attack(vs[2], true, false, true)
	var hp := {}
	for v in vs: hp[v] = v.current_health
	for f in range(60 * 10):
		await get_tree().physics_frame
		if f % 60 == 0:
			print("  t=%d facing %s anim %s state %d tgt %s sweeps %d" % [f / 60, str(big._facing.round()), big.anim_shown(), big.state, str(big.attack_target), big.sweeps])
		for v in vs:
			if is_instance_valid(v) and v.current_health < float(hp[v]) - 0.01:
				print("    hit f=%d victim %d dmg %.2f" % [f, vs.find(v), float(hp[v]) - v.current_health])
				hp[v] = v.current_health
	for v in vs:
		if is_instance_valid(v): v.take_damage(1.0e12)
	var prev_anim := StringName("")
	for f2 in range(60 * 7):
		await get_tree().physics_frame
		if big.anim_shown() != prev_anim:
			prev_anim = big.anim_shown()
			print("  CHANGE f=%d anim %s state %d tgt %s swings %d sweeps %d lock_until %d now %d" % [f2, prev_anim, big.state, str(big.attack_target), big._swings, big.sweeps, big._anim_lock_until_ms, Unit.game_ms()])
		if f2 % 30 == 0:
			print("  after t=%.1f anim %s state %d tgt %s lock_until %d now %d lock_pending %s proc_sleep %s" % [f2 / 60.0, big.anim_shown(), big.state, str(big.attack_target), big._anim_lock_until_ms, Unit.game_ms(), str(big._lock_pending), str(big._proc_sleeping)])
	get_tree().quit()
