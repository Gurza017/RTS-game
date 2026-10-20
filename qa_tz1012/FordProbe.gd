extends Node
## Зонд «петли назад у брода» (ТЗ 12.10.2026, второе письмо, блок 1.2):
## отряды стоят В БРОДУ и на подходе к нему, приказ на дальний берег —
## печатаем маршрут каждого бойца и считаем тех, чья первая точка лежит
## ПОЗАДИ (против хода к цели) больше чем на 2 м.
const P := Constants.FACTION_PLAYER
var main = null

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(200.0).timeout.connect(func(): get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = P
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.goblin_ai != null: main.goblin_ai.set_process(false)
	var ax: float = main.river_x(0.0)
	var groups := [
		["в броду у левого берега", Vector3(ax - 6.0, 0, -6.0)],
		["в броду посередине", Vector3(ax, 0, 4.0)],
		["в броду у правого берега", Vector3(ax + 6.0, 0, 10.0)],
		["на левом откосе", Vector3(ax - 13.0, 0, -2.0)],
		["на левом берегу у брода", Vector3(ax - 22.0, 0, 8.0)],
		["далеко на левом берегу", Vector3(ax - 45.0, 0, 35.0)],
		["растянут через брод", Vector3(ax - 30.0, 0, 0.0)],
	]
	var sids: Array = []
	for g in groups:
		var sid: int = GameManager.new_squad(P, "spearman")
		var c: Vector3 = g[1]
		var stretched: bool = String(g[0]) == "растянут через брод"
		for i in range(24):
			var off := Vector3(float(i % 6) * 0.8 - 2.0, 0, float(i / 6) * 0.8 - 1.2)
			if stretched:
				# голова отряда уже на воде брода, хвост — в 30 м на берегу
				off = Vector3(float(i) * 1.3, 0, float(i % 3) * 1.0 - 1.0)
			var u := _spawn("spearman", c + off)
			GameManager.add_to_squad(sid, u)
		sids.append(sid)
	await pframes(20)
	var sm = main.selection_manager
	for goal in [Vector3(ax + 60.0, 0, 30.0), Vector3(ax - 60.0, 0, -25.0)]:
		print("\n=== ЦЕЛЬ %s ===" % str(goal))
		var all: Array = []
		for sid in sids:
			all.append_array((GameManager.squads[sid]["members"] as Array))
		sm.select_units(all)
		sm.set_attack_move_armed(true)
		sm.order_at_world(goal, true)
		await pframes(3)
		# Реальный ход: откат каждого бойца ПРОТИВ хода к цели за 40 с
		var start: Dictionary = {}
		var dirs: Dictionary = {}
		var worst: Dictionary = {}
		for sid in sids:
			for m in GameManager.squads[sid]["members"]:
				var u := m as Unit
				start[u] = u.global_position
				var d := Vector2(u.post_pos.x - u.global_position.x, u.post_pos.z - u.global_position.z)
				dirs[u] = d.normalized() if d.length() > 0.1 else Vector2.ZERO
				worst[u] = 0.0
		for t in range(120):
			await pframes(30)
			for u in start:
				if not is_instance_valid(u):
					continue
				var p: Vector3 = (u as Unit).global_position
				var s0: Vector3 = start[u]
				var back: float = -Vector2(p.x - s0.x, p.z - s0.z).dot(dirs[u])
				worst[u] = maxf(float(worst[u]), back)
		var tot := 0
		for gi in range(sids.size()):
			var bad := 0
			var mx := 0.0
			var arrived := 0
			for m in GameManager.squads[sids[gi]]["members"]:
				var u := m as Unit
				if float(worst[u]) > 3.0:
					bad += 1
				mx = maxf(mx, float(worst[u]))
				if Vector2(u.global_position.x - u.post_pos.x, u.global_position.z - u.post_pos.z).length() < 4.0:
					arrived += 1
			tot += bad
			print("  %-26s откат > 3 м: %d, худший %.1f м, дошли %d" % [groups[gi][0], bad, mx, arrived])
		print("  ИТОГО откат: %d" % tot)
	get_tree().quit()
