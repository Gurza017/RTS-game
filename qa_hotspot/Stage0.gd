extends Node

## ЭТАП 0: ПРОВЕРКА ТОГО, ЧТО ПРОВЕРЯЕТСЯ ЧИСЛАМИ, А НЕ СЕКУНДОМЕРОМ.
##
## Времена кадра на загруженной машине пляшут (замерено: три прогона одного
## кода дали 8.2 / 16.6 / 22.5 мс). Поэтому здесь сверяется НЕ скорость, а
## поведение: та ли ступень дробления включается на боевых размерах армии,
## растягивается ли такт позы, и живут ли полоски здоровья одним слоем вместо
## двух узлов на бойца.
##
## Запуск: godot --headless --path . res://qa_hotspot/Stage0.tscn

const _Opt := preload("res://scripts/perf_config.gd")

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

func _run() -> void:
	print("\n───── A. ЛЕСТНИЦА ДРОБЛЕНИЯ ТИКА ─────")
	for pair in [[300, 1], [800, 1], [900, 2], [1200, 2], [1300, 3], [5000, 3]]:
		var n: int = pair[0]
		var want: int = pair[1]
		var got: int = _Opt.shards_for(n)
		ok("%d бойцов → %d шард(а)" % [n, want], got == want, "получено %d" % got)

	print("\n───── B. АДАПТИВНЫЙ ТАКТ ПОЗЫ ─────")
	var a300 := _Opt.anim_every_for(300)
	var a1300 := _Opt.anim_every_for(1300)
	var a5000 := _Opt.anim_every_for(5000)
	ok("малая армия — прежний такт", a300 == _Opt.anim_every_base,
		"такт %d" % a300)
	ok("в свалке такт растянут", a1300 > a300, "300 → %d, 1300 → %d" % [a300, a1300])
	ok("растяжение упирается в потолок", a5000 == _Opt.anim_every_max,
		"такт %d при потолке %d" % [a5000, _Opt.anim_every_max])
	ok("такт монотонно растёт", a300 <= a1300 and a1300 <= a5000)

	print("\n───── C. ПОЛОСКИ ЗДОРОВЬЯ — ОДНИМ СЛОЕМ ─────")
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(4):
		await get_tree().process_frame
	var world: Node3D = main.world_root()
	var Spear := load("res://scenes/units/Spearman.tscn") as PackedScene
	var units: Array = []
	for i in range(120):
		var u: Unit = Spear.instantiate()
		u.faction = Constants.FACTION_PLAYER
		world.add_child(u)
		u.global_position = Vector3(float(i % 12) * 1.0, 0.0, float(i / 12) * 1.0)
		units.append(u)
	await get_tree().process_frame

	var nodes_off := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	GameManager.set_hp_bars_forced(true)
	for _i in range(3):
		await get_tree().process_frame
	var nodes_on := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	# Допуск в несколько узлов: при первой регистрации создаётся сам
	# MultiMeshInstance3D слоя. Смысл проверки в том, что число НЕ растёт с
	# армией — прежний код давал по два узла на бойца, то есть +240 на 120
	ok("C1 включение Alt не плодит узлов", nodes_on - nodes_off <= 4,
		"узлов было %d, стало %d (прежний код давал +240 на 120 бойцов)"
		% [nodes_off, nodes_on])
	# На карте живут ещё и стартовые рабочие — они такие же юниты и полоски
	# получают наравне, поэтому сверяем со ВСЕМИ живыми, а не только со своими
	var all_units: int = get_tree().get_nodes_in_group("all_units").size()
	ok("C2 полоски числятся в общем слое",
		GameManager.hp_bars.registered_count() == all_units,
		"в слое %d, живых юнитов %d" % [GameManager.hp_bars.registered_count(), all_units])

	# Долю жизни слой обязан подхватывать сам, без пересборки узлов
	(units[0] as Unit).take_damage(30.0, null)
	for _i in range(3):
		await get_tree().process_frame
	ok("C3 узлов полосок у бойца нет вовсе",
		(units[0] as Unit).find_child("HPBar", true, false) == null)

	GameManager.set_hp_bars_forced(false)
	for _i in range(3):
		await get_tree().process_frame
	ok("C4 выключение Alt очищает слой",
		GameManager.hp_bars.registered_count() == 0,
		"в слое осталось %d" % GameManager.hp_bars.registered_count())

	GameManager.set_hp_bars_forced(true)
	for _i in range(3):
		await get_tree().process_frame
	var before: int = GameManager.hp_bars.registered_count()
	(units[1] as Unit).take_damage(99999.0, null)
	for _i in range(6):
		await get_tree().process_frame
	ok("C5 погибший освобождает слот",
		GameManager.hp_bars.registered_count() < before,
		"было %d, стало %d" % [before, GameManager.hp_bars.registered_count()])

	print("\n=== ЭТАП 0: провалов: %d из %d ===" % [_fail, _checks])
	get_tree().quit(1 if _fail > 0 else 0)
