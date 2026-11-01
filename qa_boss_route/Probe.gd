extends Node
## ЗОНД разбора партии 30.10.2026 (performance_log_2026-10-30_0058.json):
## Свинобосс 8.5 мин «бежал на месте» в (85.5, −77) по дороге на базу и 11 мин
## в (133.7, −59.4) у лагеря (состояние MOVING, координата не меняется).
## Поднимает автосейв владельца (то же зерно — та же карта), печатает клетки
## вокруг обеих точек, ставит туда Свинобосса и даёт тот же приказ бегства.
## Вердиктов нет. -- at=x,z to=x,z  (по умолчанию — обе точки партии)
const _Save = preload("res://scripts/SaveLoadManager.gd")
const _BossScene := preload("res://scenes/units/PigBoss.tscn")
var main: Node

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit())

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

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _map(cx: float, cz: float, tag: String) -> void:
	print("\n── клетки 2 м вокруг %s (%.1f, %.1f): F лес, W вода, B здание, # стена сетки, p непроходимо, @ точка" % [tag, cx, cz])
	for j in range(-9, 10):
		var z: float = cz + float(j) * 2.0
		var row := "%7.1f " % z
		for i in range(-16, 17):
			var x: float = cx + float(i) * 2.0
			var ch := "."
			if i == 0 and j == 0: ch = "@"
			elif GameManager.army.forest_at(x, z): ch = "F"
			elif GameManager.is_water(x, z): ch = "W"
			elif GameManager.in_building(x, z): ch = "B"
			elif not GameManager.army.nav_free(x, z): ch = "#"
			elif not GameManager.is_passable(x, z): ch = "p"
			row += ch
		print(row)

func _run() -> void:
	var st: Dictionary = _read("user://autosave.tts")
	print("слепок: ключей %d, зерно %s" % [st.size(), str(st.get("meta", {}).get("world_seed", "?"))])
	GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(40)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager", "boss_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	var gai = main.get("goblin_ai")
	var village: Vector3 = gai.village if gai != null else Vector3.ZERO
	print("лагерь орды (village) (%.1f, %.1f)" % [village.x, village.z])
	var pts: Array = [[Vector2(85.5, -77.0), Vector2(171.8, -92.2), "бегство"],
		[Vector2(133.7, -59.4), Vector2(village.x, village.z), "сбор"]]
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("at="):
			var v := s.substr(3).split(",")
			pts = [[Vector2(float(v[0]), float(v[1])), Vector2(village.x, village.z), "точка"]]
		if s.begins_with("to=") and not pts.is_empty():
			var v2 := s.substr(3).split(",")
			pts[0][1] = Vector2(float(v2[0]), float(v2[1]))
	for pt in pts:
		var at: Vector2 = pt[0]
		var to: Vector2 = pt[1]
		_map(at.x, at.y, String(pt[2]))
		await _try_boss(at, to, String(pt[2]))
	get_tree().quit()

func _try_boss(at: Vector2, to: Vector2, tag: String) -> void:
	var b: Unit = _BossScene.instantiate()
	b.faction = Constants.FACTION_GOBLIN
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.y), at.y)
	b.sync_row()
	b.post_pos = b.global_position
	await pframes(5)
	print("\n── %s: Свинобосс в (%.1f, %.1f) → (%.1f, %.1f); nav_clearance %.1f, проходимо %s" % [tag,
		at.x, at.y, to.x, to.y, float(b.nav_clearance()), str(GameManager.is_passable(at.x, at.y))])
	var goal := Vector3(to.x, 0.0, to.y)
	if b.has_method("flee_to"):
		b.call("flee_to", goal)
	else:
		b.command_move(goal)
	var last: Vector3 = b.global_position
	var still := 0
	for k in range(30):
		await pframes(60)
		var p: Vector3 = b.global_position
		var d: float = Vector2(p.x - last.x, p.z - last.z).length()
		still = still + 1 if d < 0.25 and b.state == Unit.State.MOVING else 0
		if k < 6 or k % 5 == 4 or still == 3:
			print("  +%2d с: (%.1f, %.1f) сдвиг %.2f м, %s, до цели %.1f м, бег на месте %d с" % [k + 1, p.x, p.z, d,
				Unit.State.keys()[b.state], Vector2(p.x - to.x, p.z - to.y).length(), still])
		last = p
	b.queue_free()
	await pframes(5)
