extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД УТЕЧЕК ПРИ МАССОВОМ СПАВНЕ
## ═══════════════════════════════════════════════════════════════════════════
## Три волны по 300 бойцов: спавн → бой до последнего → полная зачистка.
## Между волнами сверяем ЧИСЛО ЖИВЫХ ОБЪЕКТОВ и ОСИРОТЕВШИХ УЗЛОВ. Если
## что-то не освобождается, счётчик растёт от волны к волне — линейно и заметно.
##
## Замер именно так, а не по «leaked at exit»: движок печатает эту строку и на
## совершенно здоровом проекте (статические кэши живут до конца процесса), и
## отличить по ней настоящую течь от кэша нельзя.

var main = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _objs() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))

func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

func _nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

func _wave(n: int) -> void:
	var made: Array = []
	var sid_p: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var sid_e: int = GameManager.new_squad(Constants.FACTION_ENEMY, "spearman")
	for i in range(n):
		var enemy: bool = i >= n / 2
		var u: Unit = Spearman.new()
		u.faction = Constants.FACTION_ENEMY if enemy else Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(
			float(i % 20) * 0.7 - 7.0, 0.0,
			(6.0 if enemy else -6.0) + float(i / 20) * 0.7)
		GameManager.add_to_squad(sid_e if enemy else sid_p, u)
		made.append(u)
	await frames(4)
	# Сводим их в бой: гибель — главный путь, на котором и теряются ссылки
	for u in made:
		var un: Unit = u
		if is_instance_valid(un):
			un.command_attack(made[0] if un.faction == Constants.FACTION_ENEMY \
				else made[n - 1], true, true)
	await frames(240)
	# Полная зачистка: остаток убираем руками
	for u in made:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(20)

func _run() -> void:
	seed(99)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await frames(10)

	print("\n===== ЗОНД УТЕЧЕК (3 волны по 300 бойцов) =====")
	var base_o := 0
	var base_n := 0
	for w in range(3):
		await _wave(300)
		await frames(30)
		var o := _objs()
		var nd := _nodes()
		var orph := _orphans()
		if w == 0:
			base_o = o
			base_n = nd
		print("  волна %d: объектов %6d (%+d к первой), узлов %5d (%+d), осиротевших %d"
			% [w + 1, o, o - base_o, nd, nd - base_n, orph])

	var drift_o := _objs() - base_o
	var drift_n := _nodes() - base_n
	print("  ── дрейф за 2 волны: объектов %+d, узлов %+d" % [drift_o, drift_n])
	# Порог мягкий: часть роста — законные кэши (SpriteFrames, атласы кадров),
	# они наполняются в первую волну и дальше не растут. Течь видна как рост
	# СОТНЯМИ на каждую волну — по 300 бойцов за раз
	var ok: bool = drift_n < 100 and drift_o < 400
	print("  ВЕРДИКТ: %s" % ("ПРОШЛО — течи при спавне/гибели нет" if ok
		else "НЕ ПРОШЛО — объекты не освобождаются"))
	print("===== ЗОНД ЗАВЕРШЁН =====\n")
	get_tree().quit(0 if ok else 1)
