extends Node

## Разовая диагностика: сколько стоит РАСШИРЕННЫЙ агро-скан лучника.
## Один и тот же строй из 200 лучников меряется дважды: с дальностью 20 м
## (боевой вариант, скан идёт на 20 м) и с урезанной до 10 м — разница и есть
## цена того, что стрелки теперь смотрят на всю дальность оружия.

var main = null

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _ready() -> void:
	call_deferred("_run")

func _avg(mon: int, n: int) -> float:
	var acc := 0.0
	for _i in range(n):
		await get_tree().process_frame
		acc += Performance.get_monitor(mon)
	return acc / float(n)

func _spawn_wave(base: Vector3, cls: String, fac: int, cnt: int, step: float) -> Array:
	var out: Array = []
	for i in range(cnt):
		var u: Unit = (Archer.new() if cls == "archer" else Spearman.new())
		u.faction = fac
		main.world_add(u)
		u.global_position = base + Vector3(float(i % 20) * step, 0.0, float(i / 20) * step)
		out.append(u)
	return out

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(30)
	var idle: float = await _avg(Performance.TIME_PHYSICS_PROCESS, 40)
	print("фон пустой сцены: физика %.3f мс" % (idle * 1000.0))

	var base := Vector3(4000.0, 0.0, 4000.0)
	# ВРАГОВ НЕТ СОВСЕМ: иначе замер ловит бой (стрелы, сближение, расталкивание),
	# а нам нужна цена ОДНОГО ТОЛЬКО скана пустого радиуса
	var arch := _spawn_wave(base, "archer", Constants.FACTION_PLAYER, 200, 1.0)
	await frames(90)
	var _warm: float = await _avg(Performance.TIME_PHYSICS_PROCESS, 60)
	await frames(60)
	var wide: float = await _avg(Performance.TIME_PHYSICS_PROCESS, 60)
	var busy := 0
	for a in arch:
		if (a as Unit).attack_target != null:
			busy += 1
	print("дальность 20 м (боевая): физика %.3f мс, с целью %d лучников" % [wide * 1000.0, busy])

	for a in arch:
		var u: Unit = a
		u.attack_range = 10.0
		u.set_attack_target(null)
		u.state = Unit.State.IDLE
	await frames(90)
	var narrow: float = await _avg(Performance.TIME_PHYSICS_PROCESS, 60)
	var busy2 := 0
	for a in arch:
		if (a as Unit).attack_target != null:
			busy2 += 1
	print("дальность 10 м (контроль): физика %.3f мс, с целью %d лучников" % [narrow * 1000.0, busy2])
	print("цена расширенного скана: %.3f мс на 200 лучников (%.4f мс на бойца)" % [
		(wide - narrow) * 1000.0, (wide - narrow) * 1000.0 / 200.0])

	print("=== PROBE DONE ===")
	get_tree().quit()
