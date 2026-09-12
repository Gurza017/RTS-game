extends Node
## ЗОНД: где лежат ячейки скал (спринт 18). Вердиктов нет
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	GameManager.world_bounds_enabled = true
	print("ячеек скал: %d" % GameManager.cliff_cells)
	for z in [0.0, 30.0, 60.0, -60.0]:
		var line := ""
		for xi in range(-40, 41):
			var x: float = float(xi) * 1.0
			line += "#" if GameManager.is_cliff(x, z) else ("~" if GameManager.is_water(x, z) else ".")
		print("z=%4.0f x[-40..40]: %s" % [z, line])
	# Карта целиком крупными клетками 5 м
	var cols: int = int(2.0 * main.MAP_HALF_X / 5.0)
	var rows: int = int(2.0 * main.MAP_HALF_Z / 5.0)
	for r in range(rows):
		var z2: float = -main.MAP_HALF_Z + (r + 0.5) * 5.0
		var ln := ""
		for c in range(cols):
			var x2: float = -main.MAP_HALF_X + (c + 0.5) * 5.0
			var any := false
			for dx in [-2.0, 0.0, 2.0]:
				for dz in [-2.0, 0.0, 2.0]:
					if GameManager.is_cliff(x2 + dx, z2 + dz):
						any = true
			ln += "#" if any else ("~" if GameManager.is_water(x2, z2) else ".")
		print(ln)
	get_tree().quit()
