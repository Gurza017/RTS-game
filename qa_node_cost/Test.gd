extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТАДИЯ 0: PhysicsServer3D vs GDScript-диспетчеризация vs логика
## ═══════════════════════════════════════════════════════════════════════════
## Пустая сцена (НЕ Main.tscn) — никаких спрайтов, боя, HUD. Три группы по
## N нод, поочерёдно: замеряем, освобождаем, замеряем следующую. Разница
## между группами и есть ответ на вопрос плана.

const N := 900
const DummyBodyScript := preload("res://qa_node_cost/DummyBody.gd")
const DummyNodeScript := preload("res://qa_node_cost/DummyNode.gd")

var _root: Node3D = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _avg(mon: int, n: int) -> float:
	var acc := 0.0
	for _i in range(n):
		await get_tree().process_frame
		acc += Performance.get_monitor(mon)
	return acc / float(n)

## Прогрев ЩЕДРЫЙ (совпадает с qa_mass_move/qa_perf): первые кадры после
## спавна ловят одноразовые издержки инициализации, не установившуюся цену
func _measure(label: String, warm: int, window: int) -> float:
	await frames(warm)
	var phys: float = await _avg(Performance.TIME_PHYSICS_PROCESS, window)
	print("  %-52s физика %7.3f мс/кадр" % [label, phys * 1000.0])
	return phys * 1000.0

func _make_capsule() -> CollisionShape3D:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	col.shape = shape
	col.position.y = 0.9
	return col

func _spawn_bodies(count: int, do_work: bool) -> Array:
	var made: Array = []
	for i in range(count):
		var b := CharacterBody3D.new()
		b.set_script(DummyBodyScript)
		b.collision_layer = 2   # LAYER_UNITS-подобный, не 0, как у настоящих юнитов
		b.collision_mask  = 0
		b.add_child(_make_capsule())
		b.do_work = do_work
		_root.add_child(b)
		b.global_position = Vector3(float(i % 30) * 1.0, 0.0, float(i / 30) * 1.0)
		made.append(b)
	return made

func _spawn_nodes(count: int) -> Array:
	var made: Array = []
	for i in range(count):
		var n := Node3D.new()
		n.set_script(DummyNodeScript)
		_root.add_child(n)
		n.global_position = Vector3(float(i % 30) * 1.0, 0.0, float(i / 30) * 1.0)
		made.append(n)
	return made

func _free_all(arr: Array) -> void:
	for n in arr:
		if is_instance_valid(n):
			n.queue_free()
	await frames(3)

## ГРУППЫ ИЗМЕРЯЮТСЯ В ОТДЕЛЬНЫХ ПРОЦЕССАХ (--group=1/2/3), не в одном забеге:
## одноразовые издержки движка (рост аллокаторов PhysicsServer3D, прогрев
## broad-phase) переживают queue_free() и МОНОТОННО занижали каждую следующую
## группу в общем процессе (было 6.17 → 3.03 → 1.27 мс — явный артефакт
## порядка, а не реальная цена групп). Отдельный холодный процесс на группу —
## единственный честный способ сравнить их между собой.
func _group_from_args() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--group="):
			return int(a.substr(8))
	return 0

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_root = Node3D.new()
	get_tree().root.add_child(_root)
	await frames(5)

	var grp := _group_from_args()
	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  СТАДИЯ 0 (холодный процесс): ГРУППА %d, N=%d                      ║" % [grp, N])
	print("╚══════════════════════════════════════════════════════════════════╝")

	var idle_bg := await _measure("фон: пустая сцена, 0 нод", 30, 60)
	var m := 0.0
	match grp:
		1:
			var g1 := _spawn_bodies(N, false)
			print("  поставлено: %d" % g1.size())
			m = await _measure("(1) CharacterBody3D, _physics_process ПУСТОЙ", 150, 90)
		2:
			var g2 := _spawn_bodies(N, true)
			print("  поставлено: %d" % g2.size())
			m = await _measure("(2) CharacterBody3D, IDLE-логика", 150, 90)
		3:
			var g3 := _spawn_nodes(N)
			print("  поставлено: %d" % g3.size())
			m = await _measure("(3) Node3D без тела, та же логика", 150, 90)
		_:
			print("  ОШИБКА: передайте -- --group=1|2|3")
			get_tree().quit(1)
			return

	print("\n─── ИТОГ (группа %d) ───" % grp)
	print("  фон (0 нод):        %7.3f мс" % idle_bg)
	print("  группа %d:           %7.3f мс  (net %+7.3f)" % [grp, m, m - idle_bg])
	print("\n=== NODE COST TEST DONE (group=%d) ===" % grp)
	get_tree().quit()
