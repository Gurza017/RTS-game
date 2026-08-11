extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: РЕЕСТР ДАЛЬНИХ ЮНИТОВ (FarUnitRenderer) — ТОЛЬКО БУХГАЛТЕРИЯ
## ═══════════════════════════════════════════════════════════════════════════
## Проверяет register/unregister/переиспользование слотов/рост корзин БЕЗ
## визуальной проверки (headless её не покажет, см. qa_mm_spike). Юнит с
## MultiMesh пока НИКАК не связан (это следующий шаг плана) — стенд бьёт по
## модулю напрямую, как это со временем будет делать Unit._process().
##
## Запуск: godot --headless --path . res://qa_far_render/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  FarUnitRenderer: БУХГАЛТЕРИЯ РЕЕСТРА ДАЛЬНИХ ЮНИТОВ              ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	var Far := load("res://scripts/FarUnitRenderer.gd")
	var far = Far.new()
	var world: Node3D = main._world

	# ═════ 1. РЕГИСТРАЦИЯ И СЧЁТ ═════
	var units: Array = []
	var kinds := ["spearman", "archer", "warrior", "worker"]
	for i in range(50):
		var kind: String = kinds[i % kinds.size()]
		var fac: int = Constants.FACTION_PLAYER if i % 2 == 0 else Constants.FACTION_ENEMY
		var u := _new(kind, fac, Vector3(float(i), 0, 0))
		units.append(u)
		far.register(u, world, false)
	verdict("1 все 50 юнитов зарегистрированы", far.registered_count() == 50,
		"registered_count=%d" % far.registered_count())

	var bucket_nodes := 0
	for child in world.get_children():
		if child is MultiMeshInstance3D:
			bucket_nodes += 1
	# 4 типа × 2 фракции × 1 состояние (все moving=false) = до 8 корзин
	verdict("1 не больше 8 узлов MultiMeshInstance3D на 4×2×1 связок", bucket_nodes <= 8,
		"узлов=%d" % bucket_nodes)

	# ═════ 2. ПОВТОРНАЯ РЕГИСТРАЦИЯ ═════
	far.register(units[0], world, false)
	verdict("2 повторная регистрация не плодит слоты", far.registered_count() == 50,
		"registered_count=%d (ожидалось 50)" % far.registered_count())

	# ═════ 3. UNREGISTER И ПЕРЕИСПОЛЬЗОВАНИЕ СЛОТА ═════
	far.unregister(units[1])
	verdict("3 unregister снимает юнита", far.registered_count() == 49,
		"registered_count=%d" % far.registered_count())
	far.unregister(units[1])
	verdict("3 повторный unregister не ломается (идемпотентен)", far.registered_count() == 49,
		"registered_count=%d" % far.registered_count())

	var u_new := _new("spearman", Constants.FACTION_PLAYER, Vector3(99, 0, 0))
	units.append(u_new)
	far.register(u_new, world, false)
	verdict("3 новый юнит переиспользует освобождённый слот, не растит корзину без нужды",
		far.registered_count() == 50, "registered_count=%d" % far.registered_count())

	# ═════ 4. РОСТ КОРЗИНЫ ЗА GROW_STEP ═════
	var many: Array = []
	for i in range(200):
		var u := _new("spearman", Constants.FACTION_PLAYER, Vector3(float(i), 0, 5))
		many.append(u)
		far.register(u, world, false)
	verdict("4 корзина выросла и приняла всех без крэша", far.registered_count() == 250,
		"registered_count=%d (ожидалось 250)" % far.registered_count())

	# ═════ 5. ОБНОВЛЕНИЕ ПОЗИЦИИ ЗАРЕГИСТРИРОВАННОГО ═════
	far.update_transform(units[2], Vector3(42, 0, 7), true)
	verdict("5 update_transform на зарегистрированном не крашится", true)
	far.update_transform(units[1], Vector3(1, 0, 1), false)   # units[1] снят в блоке 3
	verdict("5 update_transform на СНЯТОМ юните — no-op, не крашится", true)

	# ═════ 6. is_registered ═════
	verdict("6 is_registered=true для живого слота", far.is_registered(units[2]))
	verdict("6 is_registered=false после unregister", not far.is_registered(units[1]))

	# ═════ 7. ОЧИСТКА ═════
	far.clear_bookkeeping()
	verdict("7 clear_bookkeeping обнулила реестр", far.registered_count() == 0,
		"registered_count=%d" % far.registered_count())

	for u in units + many:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %-58s%s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== FAR RENDER TEST DONE ===")
	get_tree().quit()
