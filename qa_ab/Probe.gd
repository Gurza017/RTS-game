extends Node

## ЗОНД: опускается ли граница занятых строк после гибели армии.
## Не стенд — печатает числа. Запуск:
##   godot --headless --path . res://qa_ab/Probe.tscn

var main = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	seed(11)
	Engine.max_fps = 0
	preload("res://scripts/perf_config.gd").sprite_lod = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(8)

	var A = GameManager.army
	print("\n=== ЗОНД: ГРАНИЦА ЗАНЯТЫХ СТРОК ===")
	print("  пусто:            ёмкость=%d  граница=%d  занято=%d"
		% [A.capacity(), A.top(), A.used()])

	var men: Array = []
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(2000):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var x: float = float(i % 50) * 0.7 - 17.0
		var z: float = float(i / 50) * 0.7 - 14.0
		u.global_position = Vector3(x, GameManager.get_terrain_height(x, z), z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await frames(10)
	print("  после найма 2000: ёмкость=%d  граница=%d  занято=%d"
		% [A.capacity(), A.top(), A.used()])

	# ── СЛУЧАЙ 1: ГИБНУТ НИЖНИЕ СТРОКИ, ВЫЖИВШИЕ ДЕРЖАТ ВЕРХНИЕ ────────────
	# Худший для границы расклад: она упирается в самого верхнего живого и
	# опуститься не может НИ НА СТРОКУ
	for i in range(men.size() - 100):
		var u := men[i] as Unit
		if is_instance_valid(u) and not u.is_dead():
			u.take_damage(u.max_health * 10.0 + 1000.0, null)
	await frames(30)
	print("  осталось 100 СВЕРХУ: ёмкость=%d  граница=%d  занято=%d  (граница не опустится)"
		% [A.capacity(), A.top(), A.used()])
	print("  вхолостую за проход: %d строк" % (A.top() - A.used()))

	# ── СЛУЧАЙ 2: ГИБНУТ ВЕРХНИЕ ──────────────────────────────────────────
	for i in range(men.size() - 100, men.size()):
		var u := men[i] as Unit
		if is_instance_valid(u) and not u.is_dead():
			u.take_damage(u.max_health * 10.0 + 1000.0, null)
	await frames(30)
	print("  все выбиты:          ёмкость=%d  граница=%d  занято=%d"
		% [A.capacity(), A.top(), A.used()])
	print("  вхолостую за проход: %d строк" % (A.top() - A.used()))
	print("\n=== PROBE DONE ===")
	get_tree().quit(0)
