extends Node

## ПУЛ СТРЕЛ: переиспользование не должно менять поведение выстрела.
## Проверяется ровно то, что ломается при неверном пуле: стрела, взятая из
## пула ВТОРОЙ раз, обязана лететь заново и наносить урон, а не быть погашенной
## копией прошлой жизни. Плюс — что пул не растёт бесконечно и не оставляет
## узлов вне дерева.
##
## Запуск: godot --headless --path . res://qa_arrow/Pool.tscn

var _fail := 0
var _checks := 0

func _ready() -> void:
	call_deferred("_run")

func ok(name: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fail += 1
	print("  [%s] %s%s" % ["OK " if cond else "НЕ ПРОШЛО", name,
		("  — " + detail) if detail != "" else ""])

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(3)

	var world: Node3D = main.world_root()
	GameManager.clear_arrow_pool()

	print("\n───── A. ВЫСТРЕЛ И ВОЗВРАТ В ПУЛ ─────")
	var a1 = GameManager.spawn_arrow(world, Vector3(0, 1, 0), Vector3(6, 0, 0),
		6.0, 12.0, 0.4, 5.0, null, Constants.FACTION_PLAYER)
	ok("A1 стрела выдана", a1 != null)
	ok("A2 пул опустел", GameManager.arrow_pool_size() == 0,
		"в пуле %d" % GameManager.arrow_pool_size())
	ok("A3 стрела в дереве и видима", a1.get_parent() == world and a1.visible)
	var iid1: int = a1.get_instance_id()

	# Промах: долетит до точки, воткнётся, дальше её снимет срок жизни
	await _frames(90)
	ok("A4 стрела воткнулась", bool(a1.get("_spent")))

	print("\n───── B. ПОВТОРНОЕ ИСПОЛЬЗОВАНИЕ ─────")
	# Гасим принудительно, не дожидаясь MAX_LIFETIME
	a1.call("_despawn")
	ok("B1 вернулась в пул", GameManager.arrow_pool_size() == 1,
		"в пуле %d" % GameManager.arrow_pool_size())
	ok("B2 погашенная невидима", not a1.visible)
	ok("B3 ссылка на стрелка снята", a1.get("shooter") == null)

	var a2 = GameManager.spawn_arrow(world, Vector3(0, 1, 20), Vector3(4, 0, 20),
		4.0, 12.0, 0.4, 5.0, null, Constants.FACTION_PLAYER)
	ok("B4 выдан ТОТ ЖЕ узел", a2.get_instance_id() == iid1,
		"iid %d против %d" % [a2.get_instance_id(), iid1])
	ok("B5 взведена заново", not bool(a2.get("_spent"))
		and is_equal_approx(float(a2.get("_progress")), 0.0)
		and is_equal_approx(float(a2.get("_life")), 0.0))
	ok("B6 снова видима и тикает", a2.visible and a2.is_processing())

	print("\n───── C. УРОН ПОСЛЕ ПЕРЕИСПОЛЬЗОВАНИЯ ─────")
	# Мишень: обычный копейщик вражеской стороны
	var Spear := load("res://scenes/units/Spearman.tscn") as PackedScene
	var victim: Unit = Spear.instantiate()
	victim.faction = Constants.FACTION_ENEMY
	world.add_child(victim)
	victim.global_position = Vector3(40, 0, 40)
	await _frames(2)
	var hp_before: float = victim.current_health

	a2.call("_despawn")   # освобождаем узел обратно в пул
	var a3 = GameManager.spawn_arrow(world, Vector3(40, 1.2, 34),
		victim.global_position + Vector3(0, 0.8, 0), 6.0, 12.0, 0.4, 7.0,
		null, Constants.FACTION_PLAYER)
	ok("C1 снова тот же узел (третья жизнь)", a3.get_instance_id() == iid1)
	await _frames(120)
	ok("C2 урон нанесён переиспользованной стрелой",
		victim.current_health < hp_before,
		"HP %.1f → %.1f" % [hp_before, victim.current_health])

	print("\n───── D. БЕЗ УТЕЧЕК И БЕЗ ORPHAN-УЗЛОВ ─────")
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ok("D1 узлов вне дерева нет", orphans == 0, "orphan=%d" % orphans)
	# Потолок пула соблюдается
	var many: Array = []
	for i in range(GameManager.ARROW_POOL_MAX + 40):
		many.append(GameManager.spawn_arrow(world, Vector3(0, 1, 0),
			Vector3(1, 0, 0), 1.0, 12.0, 0.4, 1.0, null, Constants.FACTION_PLAYER))
	for a in many:
		a.call("_despawn")
	ok("D2 пул не растёт выше потолка",
		GameManager.arrow_pool_size() <= GameManager.ARROW_POOL_MAX,
		"в пуле %d при потолке %d" % [GameManager.arrow_pool_size(),
			GameManager.ARROW_POOL_MAX])

	print("\n=== ПУЛ СТРЕЛ: провалов: %d из %d ===" % [_fail, _checks])
	get_tree().quit(1 if _fail > 0 else 0)
