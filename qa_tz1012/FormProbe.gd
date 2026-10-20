extends Node
## Зонд «строй по ПКМ» (ТЗ 12.10.2026, второе письмо, блок 1.3): 10 отрядов
## (копейщики, лучники, мечники) россыпью, протяжка линии обычная и в [A].
## Печатает по каждому отряду: сколько бойцов встали в свои места (≤ 1.5 м от
## поста), сколько вообще получили приказ, сколько шли «назад» (дальше от
## линии, чем стояли в начале, больше чем на 3 м).
const P := Constants.FACTION_PLAYER
var main = null
var _am := false

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(280.0).timeout.connect(func(): get_tree().quit())

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

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(30, 0, 0), Vector3(-30, 0, 0), Vector3(0, 0, 25), Vector3(0, 0, -25)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
				if GameManager.is_water(p.x + d.x, p.z + d.z):
					h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "am=1":
			_am = true
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.goblin_ai != null: main.goblin_ai.set_process(false)
	var base: Vector3 = _flat_spot(Vector3(-110, 0, 40))
	main._clear_trees(base, 45.0)
	for n in get_tree().get_nodes_in_group("all_units"):
		if n is Unit and int((n as Unit).faction) != P \
				and (n as Unit).global_position.distance_to(base) < 70.0:
			(n as Unit).queue_free()
	var kinds := ["spearman", "spearman", "spearman", "archer", "archer", "warrior", "spearman", "archer", "warrior", "spearman"]
	var sizes := {"spearman": 30, "archer": 20, "warrior": 15}
	var sids: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1012
	for k in range(kinds.size()):
		var kind: String = kinds[k]
		var c := base + Vector3(rng.randf_range(-25, 25), 0, rng.randf_range(-20, 20))
		var sid: int = GameManager.new_squad(P, kind)
		for i in range(int(sizes[kind])):
			var u := _spawn(kind, c + Vector3(float(i % 6) * 0.8, 0, float(i / 6) * 0.8))
			GameManager.add_to_squad(sid, u)
		sids.append(sid)
	await pframes(20)
	var sm = main.selection_manager
	var all: Array = []
	for sid in sids:
		all.append_array(GameManager.squads[sid]["members"])
	sm.select_units(all)
	var a := base + Vector3(-22, 0, 30)
	var b := base + Vector3(22, 0, 30)
	var start: Dictionary = {}
	for u in all:
		start[u] = (u as Unit).global_position
	if _am:
		sm.set_attack_move_armed(true)
		sm.attack_move_line(a, b)
	else:
		sm._execute_line_formation(a, b)
	await pframes(3)
	var posts: Dictionary = {}
	for u in all:
		posts[u] = (u as Unit).post_pos
	await pframes(60 * 45)
	var line_n := (b - a).normalized()
	var nrm := Vector3(line_n.z, 0, -line_n.x)
	var tot_in := 0
	var tot := 0
	var tot_no := 0
	for gi in range(sids.size()):
		var inn := 0
		var no_order := 0
		var back := 0
		var n := 0
		for m in GameManager.squads[sids[gi]]["members"]:
			var u := m as Unit
			n += 1
			var pp: Vector3 = posts[u]
			if Vector2(pp.x - (start[u] as Vector3).x, pp.z - (start[u] as Vector3).z).length() < 0.5:
				no_order += 1
			if Vector2(u.global_position.x - pp.x, u.global_position.z - pp.z).length() <= 1.5:
				inn += 1
			var d0: float = absf((start[u] as Vector3 - a).dot(nrm))
			var d1: float = absf((u.global_position - a).dot(nrm))
			if d1 > d0 + 3.0:
				back += 1
		tot_in += inn
		tot += n
		tot_no += no_order
		print("  отряд %d %-8s: в местах %d/%d, без приказа %d, ушли от линии %d" % [gi, kinds[gi], inn, n, no_order, back])
	print("  ИТОГО в местах %d/%d, без приказа %d (am=%s, в [A] сейчас %d отрядов)" % [tot_in, tot, tot_no, str(_am), int(main.get("squad_commander").active_count) if main.get("squad_commander") != null else -1])
	get_tree().quit()
