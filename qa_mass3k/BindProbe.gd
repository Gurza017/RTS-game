extends Node
## Зонд привязки строк к отрисовке (этап C.1): сколько живых бойцов реально
## ведёт ядро (_rb_bound), а сколько ходит старым GDScript-путём
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for i in range(30):
		await get_tree().process_frame
	var us: Array = []
	for i in range(200):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(-40.0 + float(i % 20), 0.0, -30.0 + float(i / 20))
		u.sync_row()
		us.append(u)
	for i in range(120):
		await get_tree().process_frame
	var bound := 0
	var reg := 0
	var soa_ok := 0
	for u in us:
		var uu := u as Unit
		if uu._far_registered: reg += 1
		if uu._rb_bound: bound += 1
		if uu._soa >= 0: soa_ok += 1
	print("ZOND-BIND: из 200: зарегистрировано=%d, привязано=%d, со строкой=%d" % [reg, bound, soa_ok])
	print("=== BINDPROBE DONE ===")
	get_tree().quit()
