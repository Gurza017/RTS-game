extends Node
## Зонд: карта клеток навигации вокруг точки (аргументы cx= cz=). Вердиктов нет
var main: Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var cx := 0.0
	var cz := 0.0
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("cx="): cx = float(String(a).substr(3))
		if String(a).begins_with("cz="): cz = float(String(a).substr(3))
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(30):
		await get_tree().physics_frame
	var x0: float = floor((cx + 225.0) / 2.0) * 2.0 - 225.0 + 1.0
	var z0: float = floor((cz + 126.5625) / 2.0) * 2.0 - 126.5625 + 1.0
	for j in range(-10, 11):
		var z: float = z0 + float(j) * 2.0
		var row := "%8.2f " % z
		for i in range(-14, 15):
			var x: float = x0 + float(i) * 2.0
			var ch := "."
			if absf(x) > 225.0 or absf(z) > 126.5625: ch = " "
			elif GameManager.army.forest_at(x, z): ch = "F"
			elif GameManager.is_water(x, z): ch = "W"
			elif GameManager.in_building(x, z): ch = "B"
			elif not GameManager.army.nav_free(x, z): ch = "#"
			elif not GameManager.is_passable(x, z): ch = "p"
			row += ch
		print(row)
	get_tree().quit()
