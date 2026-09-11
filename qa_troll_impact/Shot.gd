extends Node

## ОКОННЫЙ СНИМОК: раненый тролль (пятна крови, слабая вспышка) и сбитые с ног
## копейщики рядом. Вердиктов нет — это картинка для глаза и проверка, что
## шейдер с пятнами компилируется (headless шейдеров не собирает).
## Запуск: godot --path . res://qa_troll_impact/Shot.tscn -- --out=<путь без .png>

var main = null
var _out: String = ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func():
		print("  СТОРОЖ"); get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1600, 900)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	var lair = GameManager.troll_lair
	var troll: Unit = null
	if lair != null:
		for t in lair.trolls:
			if is_instance_valid(t):
				troll = t
				break
	if troll == null:
		print("тролля нет"); get_tree().quit(); return
	var base := Vector3(0.0, 0.0, -40.0)
	troll.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z)
	troll.sync_row()
	# Копейщики перед ним — их накроет дубина
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var scene: PackedScene = Building.PRELOAD_SCENES["spearman"]
	for i in range(12):
		var u: Unit = scene.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var px: float = base.x + float(i % 6) * 0.6 - 1.5
		var pz: float = base.z + 3.0 + float(i / 6) * 0.6
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
	main.focus_camera_on(base + Vector3(0.0, 0.0, 1.5))
	await frames(4)
	(main._camera as Node).set_process(false)
	(get_viewport().get_camera_3d() as Camera3D).size = 22.0
	await pframes(90)
	# Ранен на 60 %: подкраска плюс пятна
	troll.current_health = troll.max_health * 0.4
	troll._dmg_dirty = true
	await frames(8)
	if _out != "":
		get_viewport().get_texture().get_image().save_png(_out + ".png")
		print("снимок: %s.png" % _out)
	print("=== QA_TROLL_SHOT DONE ===")
	get_tree().quit()
