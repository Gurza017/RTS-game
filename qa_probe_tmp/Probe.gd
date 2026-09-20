extends Node
var main = null
func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func(): print("СТОРОЖ"); get_tree().quit())
func _spawn(kind: String, faction: int, pos: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		_:          u = Warrior.new()
	u.faction = faction
	main.world_add(u)
	u.global_position = Vector3(pos.x, GameManager.get_terrain_height(pos.x, pos.z), pos.z)
	u.sync_row()
	return u
func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	# ── FOG C4 ──
	var fog = main.fog
	var spot := Vector3(0.0, 0.0, 0.0)
	var before: bool = fog.is_lit(spot.x, spot.z)
	var sp := Spearman.new()
	sp.faction = Constants.FACTION_PLAYER
	main.world_add(sp)
	sp.global_position = Vector3(spot.x, main.get_terrain_height(spot.x, spot.z), spot.z)
	await pframes(2)
	fog.refresh()
	var after: bool = fog.is_lit(spot.x, spot.z)
	print("FOG C4: before=%s after=%s soa=%d dead=%s water=%s h=%.2f tick_on=%s state=%d" % [before, after, sp._soa, sp.is_dead(), GameManager.is_water(0.0, 0.0), main.get_terrain_height(0.0, 0.0), sp.tick_on, sp.state])
	await pframes(30)
	fog.refresh()
	print("FOG C4 after 30 pframes: lit=%s  vis_r=%.1f atk_range=%.1f" % [fog.is_lit(0.0, 0.0), 0.0, sp.attack_range])
	sp.queue_free()
	# ── HOLD C3 ──
	GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	await pframes(2)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var men: Array = []
	for i in range(4):
		var u := _spawn("archer", Constants.FACTION_PLAYER, Vector3(0.0 + float(i) * 0.8, 0.0, -300.0))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	var foe := _spawn("warrior", Constants.FACTION_ENEMY, Vector3(0.0, 0.0, -292.0))
	foe.set_tick(false)
	await pframes(10)
	for u in men:
		(u as Unit).command_attack(foe, true, true, true)
	await pframes(90)
	foe.global_position = Vector3(0.0, GameManager.get_terrain_height(0.0, -250.0), -250.0)
	foe.sync_row()
	await pframes(300)
	print("HOLD: after flee tgt=%s lock=%s state=%d" % [str((men[0] as Unit).attack_target), str((men[0] as Unit).target_lock), (men[0] as Unit).state])
	var foe2 := _spawn("warrior", Constants.FACTION_ENEMY, Vector3(3.0, 0.0, -288.0))
	foe2.set_tick(false)
	for k in range(5):
		await pframes(30)
		var u0 := men[0] as Unit
		print("HOLD k=%d tgt=%s lock=%s state=%d aggro_t=%.2f idle_wait=%s clear=%s radar_active=%s radar_foe=%s d=%.1f" % [k, str(u0.attack_target), str(u0.target_lock), u0.state, u0._aggro_timer, str(u0._idle_wait), str(u0._clear_enemy), str(GameManager.squad_radar_active(sid)), str(GameManager.squad_radar_foe(sid)), u0.global_position.distance_to(foe2.global_position)])
	# ── TARGET_LOCK C2 ──
	var p0 := Vector3(400, 0, 0)
	var sid2: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var men2: Array = []
	for i in range(5):
		var u := _spawn("archer", Constants.FACTION_PLAYER, p0 + Vector3(float(i) * 0.8, 0, 0))
		GameManager.add_to_squad(sid2, u)
		men2.append(u)
	var sid3: int = GameManager.new_squad(Constants.FACTION_ENEMY, "spearman")
	var tg: Array = []
	for i in range(5):
		var u := _spawn("spearman", Constants.FACTION_ENEMY, p0 + Vector3(float(i) * 0.8, 0, 27.0))
		GameManager.add_to_squad(sid3, u)
		u.max_health = 1e9; u.current_health = 1e9
		tg.append(u)
	await pframes(5)
	for u in men2:
		(u as Unit).command_attack(tg[0], true, true, true)
	for k in range(120):
		await pframes(5)
		var u0 := men2[0] as Unit
		if k >= 60 and k <= 72:
			var foeS: int = GameManager.squad_melee_foe(sid2)
			print("MOR k=%d frac=%.2f mult=%.2f foe=%d foe_frac=%.2f in_combat=%s wfull=%.1f walive=%.1f raw=%s" % [k, GameManager.squad_morale_frac(sid2), GameManager._legend_morale_mult(sid2), foeS, (GameManager.squad_morale_frac(foeS) if foeS > 0 else -1.0), str(GameManager.squad_in_combat(sid2)), GameManager._weight_of_squad(sid2, true), GameManager._weight_of_squad(sid2, false), str(GameManager.squads[sid2].get("morale"))])
		if k >= 50 and k <= 75 and false:
			print("TLf k=%d z=%.2f st=%d tgt=%s lock=%s pan=%s spr=%s ret=%s mt=%s post=%s dis=%s hold=%s vel=%s" % [k, u0.global_position.z, u0.state, str(u0.attack_target), str(u0.target_lock), str(u0._panicked), str(u0.sprinting), str(u0.retreating), str(u0.move_target), str(u0.post_pos), str(u0._disengaging), str(u0._hold_goal_set), str(u0.velocity)])
		if k % 12 != 0:
			continue
		print("TL k=%d z=%.1f state=%d tgt=%s inrange=%s lock=%s atk_route=%d vel=%s engaged=%s" % [k, u0.global_position.z, u0.state, str(u0.attack_target), str(u0.target_in_range()), str(u0.target_lock), u0._atk_route.size(), str(u0.velocity), str(GameManager.squad_ranged_engaged(sid2))])
	get_tree().quit()
