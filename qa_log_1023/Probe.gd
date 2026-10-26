extends Node
## Зонд разбора партии 23.10.2026 (performance_log_2026-10-23_1338.json):
## точки вызволений из лога — что под ними на карте (стволы стены, просвет,
## единый предикат, ближайшая проходимая). Вердиктов нет.
const PTS := [
	["red archer 140 at", -126.0, -26.1], ["red archer 140 goal", -126.5, -25.4],
	["red sp 115 at", -127.0, 29.4], ["red sp 115 goal", -135.9, 28.9],
	["red sp 113 at", -125.0, 27.4], ["red sp 113 goal", -128.8, 21.2],
	["red sp 118 at", -121.0, 22.2], ["red sp 118 goal", -101.7, 24.7],
	["red sp 14 at", -135.7, 42.6], ["red sp 14 goal", -130.1, 38.7],
	["red sp 114 at", -152.8, 38.2], ["red sp 156 at", -144.8, 34.9],
	["red sp 162 at", -185.9, 35.3], ["red sp 162 goal", -171.8, 41.1],
	["gob 39 at", -109.4, 72.4], ["gob 39 goal", -105.8, 70.1],
	["gob 30 at", -102.6, -72.1], ["gob 30 goal", -98.6, -72.5],
	["gob 173 at", 121.3, -44.9], ["gob 173 goal", 120.4, -42.3], ["gob 173 cl", 120.2, -36.1],
	["rider 43 at", -14.8, 22.1], ["rider 43 goal", 14.6, 32.6],
	["rider 44 at", 15.0, 4.5], ["rider 44 goal", 13.1, 20.2],
	["pl 78 at", -122.2, -95.5], ["pl 158 at", -11.1, 13.2], ["pl 158 goal", -8.0, 19.6],
	["pl 194 at", -183.7, 15.8], ["pl 194 goal", -193.6, 46.4],
]
var main: Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(30):
		await get_tree().physics_frame
	print("маска %d, стволов стены %d" % [GameManager.passable_mask(), int(main.get("base_wall_trees"))])
	for p in PTS:
		var x: float = p[1]
		var z: float = p[2]
		var np: Vector2 = GameManager.nearest_passable(x, z)
		var trees: int = 0
		var near: float = INF
		for t in get_tree().get_nodes_in_group("trees"):
			if is_instance_valid(t):
				var d: float = Vector2((t as Node3D).global_position.x - x, (t as Node3D).global_position.z - z).length()
				near = minf(near, d)
				if d < 4.0:
					trees += 1
		print("%-20s (%7.1f,%6.1f) cliff=%s pocket=%s pass=%s navfree=%s water=%s nearest=%s (%.1f м) деревьев<4м=%d ближайшее %.1f м" % [
			p[0], x, z, GameManager.is_cliff(x, z), GameManager.nav_pocket(x, z), GameManager.is_passable(x, z),
			GameManager.army.nav_free(x, z), GameManager.is_water(x, z), np, np.distance_to(Vector2(x, z)) if np.is_finite() else -1.0, trees, near])
	get_tree().quit()
