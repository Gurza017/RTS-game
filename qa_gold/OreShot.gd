extends Node
## Оконный снимок рудных куч ПОСЛЕ смены масштаба пикселя (сент. 2026):
## поднимает живую карту, находит ближайшую к базе игрока кучу золота и кучу
## камня, ставит рядом копейщика для сравнения плотности пикселей и снимает
## кадр каждой кучи крупным планом. Вердиктов нет — это снимок для глаза,
## как qa_banner/Shot. Запуск:
##   godot --path . res://qa_gold/OreShot.tscn -- --out=<путь без .png>

var main = null
var _out := "user://oreshot"

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(30)

	# СЦЕНАРИЙ СТАВИТ ОКРУЖЕНИЕ САМ (правило проекта: стенд на случайной карте
	# не доказательство): по куче каждого типа на расчищенном пятачке
	var spots := {"gold": Vector3(-20.0, 0.0, 0.0), "stone": Vector3(20.0, 0.0, 0.0)}
	for k in spots:
		var c: Vector3 = spots[k]
		for t in GameManager.nodes_in_group_cached("resource_nodes"):
			var n3 := t as Node3D
			if n3 != null and Vector2(n3.global_position.x - c.x,
					n3.global_position.z - c.z).length() < 9.0:
				n3.queue_free()
	await frames(3)
	main._spawn_resource_cluster(spots["gold"], Constants.RESOURCE_GOLD, true)
	main._spawn_resource_cluster(spots["stone"], Constants.RESOURCE_STONE, true)
	await frames(5)
	var shots: Array = [["gold", spots["gold"]], ["stone", spots["stone"]]]

	for s in shots:
		var label: String = s[0]
		var c: Vector3 = s[1]
		# Копейщик рядом — эталон плотности пикселей
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(c.x + 4.0,
			GameManager.get_terrain_height(c.x + 4.0, c.z), c.z)
		u.sync_row()
		await frames(5)
		if main._camera != null:
			(main._camera as Node).set_process(true)
		main.focus_camera_on(c)
		await frames(5)
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			(cam as Camera3D).size = 16.0
		if main._camera != null:
			(main._camera as Node).set_process(false)
		await frames(20)
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s_%s.png" % [_out, label])
		print("СНИМОК %s: куча (%.1f, %.1f) -> %s_%s.png" % [label, c.x, c.z, _out, label])
	print("=== ORESHOT DONE ===")
	get_tree().quit()
