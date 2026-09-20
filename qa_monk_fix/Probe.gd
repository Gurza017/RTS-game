extends Node
## Зонд: кого отдаёт most_wounded_of_side при двух одиночках в ауре
const F := Constants.FACTION_PLAYER
var main = null
func _ready() -> void:
	call_deferred("_run")
func _spawn(kind: String, at: Vector3, frac: float) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = F
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.current_health = u.max_health * frac
	u._soa_push_stats()
	u.set_tick(false)
	return u
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8): await get_tree().process_frame
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.goblin_ai != null: main.goblin_ai.set_process(false)
	GameManager.pop_limit_enabled = false
	var p := Vector3(0, 0, 0)
	var monk: Unit = Building.PRELOAD_SCENES["monk"].instantiate()
	monk.faction = F
	main.world_add(monk)
	monk.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
	monk.sync_row()
	var w: Unit = _spawn("warrior", p + Vector3(16, 0, 0), 0.2)
	var s: Unit = _spawn("spearman", p + Vector3(12, 0, 8), 0.35)
	var a: Unit = _spawn("archer", p + Vector3(9.6, 0, -9.6), 0.5)
	for _i in range(6): await get_tree().physics_frame
	for r in [10.0, 14.0, 16.5, 20.0, 25.0]:
		var c = GameManager.army.most_wounded_of_side(monk.global_position.x, monk.global_position.z, F, r, monk._soa)
		print("r=%.1f → %s (%s)" % [r, str(c), (c as Unit).stat_id if c != null else "-"])
	print("warrior hp %.0f/%.0f frac %.2f row %d; spear frac %.2f; archer frac %.2f" % [w.current_health, w.max_health, w.current_health / w.max_health, w._soa, s.current_health / s.max_health, a.current_health / a.max_health])
	print("dist monk→warrior %.1f, cast %.1f, leash %.1f" % [monk.global_position.distance_to(w.global_position), float(monk.call("cast_range")), preload("res://scripts/unit_stats_config.gd").MONK_HEAL_LEASH])
	print("squad ids: monk %d warrior %d spear %d archer %d" % [monk.squad_id, w.squad_id, s.squad_id, a.squad_id])
	var last = null
	for _i in range(60 * 5):
		await get_tree().physics_frame
		var ht = monk.heal_target
		if ht != last:
			last = ht
			print("  кадр %d: heal_target → %s, patient_sid %d, w %.2f s %.2f" % [_i, (ht as Unit).stat_id if ht != null else "-", int(monk.get("patient_sid")), w.current_health / w.max_health, s.current_health / s.max_health])
	print("после 5 с: heal_target %s, warrior frac %.2f spear frac %.2f archer frac %.2f, ticks %d" % [
		str(monk.heal_target), w.current_health / w.max_health, s.current_health / s.max_health, a.current_health / a.max_health, int(monk.get("heal_ticks"))])
	get_tree().quit()
