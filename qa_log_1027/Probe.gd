extends Node
## Зонд разбора партии 27.10.2026 (performance_log_2026-10-27_1303.json):
## поднимает автосейв владельца и гоняет партию дальше с зондами отрядов
## (теперь с координатами). Вердиктов нет. `-- minutes=N` (умолч. 6),
## запускать с `--fixed-fps 60`, чтобы физика шла быстрее стены.
const _Save = preload("res://scripts/SaveLoadManager.gd")
var main: Node
var minutes: float = 6.0
var save_path: String = "user://autosave.tts"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("minutes="):
			minutes = float(a.substr(8))
		elif a.begins_with("save="):
			save_path = a.substr(5)
	call_deferred("_run")

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.get_32()
	f.get_32()
	f.get_32()
	var d: Variant = f.get_var(false)
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _run() -> void:
	if save_path != "none":
		var st: Dictionary = _read(save_path)
		print("слепок %s: ключей %d" % [save_path, st.size()])
		if st.is_empty():
			get_tree().quit()
			return
		GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(60):
		await get_tree().physics_frame
	var t0: float = Unit.game_sec
	print("старт: игровое время %.1f с, лимит карты %.1f x %.1f" % [t0, GameManager.map_lim_x, GameManager.map_lim_z])
	_census()
	_towers()
	var next: float = t0 + 60.0
	while Unit.game_sec < t0 + minutes * 60.0:
		await get_tree().physics_frame
		if Unit.game_sec >= next:
			next += 60.0
			print("── t=%.0f с" % Unit.game_sec)
			_census()
	print("=== QA_LOG_1027 PROBE DONE ===")
	get_tree().quit()

## Отряды по сторонам: центр, состояния
func _census() -> void:
	for sid in GameManager.squads:
		var sq: Dictionary = GameManager.squads[sid]
		var fac: int = int(sq.get("faction", 0))
		var men: Array = []
		for m in (sq["members"] as Array):
			if m != null and is_instance_valid(m) and not (m as Unit).is_dead() and not (m as Unit).garrisoned:
				men.append(m)
		if men.size() < 3:
			continue
		var c := Vector3.ZERO
		var stc: Dictionary = {}
		for m in men:
			c += (m as Unit).global_position
			var k: int = int((m as Unit).state)
			stc[k] = int(stc.get(k, 0)) + 1
		c /= float(men.size())
		print("  отряд %d %s ф%d: %d у (%.0f, %.0f) %s" % [sid, GameManager.squad_type(sid), fac, men.size(), c.x, c.z, str(stc)])

## Башни сторон и выходы базы красного
func _towers() -> void:
	for grp in ["enemy_buildings", "player_buildings", "construction_sites"]:
		for b in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(b):
				continue
			var bid: String = String(b.get("building_id"))
			var tid: String = String(b.get("target_id")) if b.get("target_id") != null else ""
			if bid == "tower" or tid == "tower":
				var p: Vector3 = (b as Node3D).global_position
				print("  башня %s ф%d (%.1f, %.1f) %s" % [grp, int(b.get("faction")), p.x, p.z, tid])
	for c in get_tree().get_nodes_in_group("enemy_buildings"):
		if c is Castle and is_instance_valid(c):
			print("  крепость красного %s (%.1f, %.1f)" % [String(c.building_id), (c as Node3D).global_position.x, (c as Node3D).global_position.z])
	var ai = main.get("enemy_ai")
	if ai != null:
		for c2 in get_tree().get_nodes_in_group("enemy_buildings"):
			if c2 is Castle and String(c2.building_id) == "castle":
				var sl: Array = ai._tower_slots(c2)
				for q in sl:
					print("  слот башни (%.1f, %.1f) от замка %.1f м" % [(q as Vector3).x, (q as Vector3).z, (q as Vector3).distance_to((c2 as Node3D).global_position)])
				break
	if main.has_method("ai_base_exits"):
		for ex in main.ai_base_exits():
			print("  выход базы красного: %s" % str(ex))
