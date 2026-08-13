extends Node

## ЕСТЬ ЛИ У БОЙЦОВ ФИЗТЕЛА В РЕАЛЬНОЙ ИГРЕ.
##
## Все массовые стенды создают бойцов как `Spearman.new()` — это чистый
## Node3D. А игра берёт их из scenes/units/*.tscn, и там корневой узел
## объявлен CharacterBody3D. Если так, то в игре у КАЖДОГО бойца есть тело в
## PhysicsServer3D (замер проекта: 5.7 мкс на бойца в кадр только за факт его
## существования), а стенды этого не видят вовсе.
##
## Стенд ставит две одинаковые армии — одну через сцену, другую через new() —
## и сравнивает и мониторы физики, и время тика.
##
## Запуск: godot --headless --path . res://qa_soa_floor/Bodies.tscn -- --count=3000

const SpearScript = preload("res://scripts/Spearman.gd")
const _OptCfg = preload("res://scripts/perf_config.gd")

var main = null
var _units: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	var n := 3000
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--count="):
			n = maxi(1, int(s.substr(8)))
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)

	var out := PackedStringArray()
	out.append("")
	out.append("═══ ФИЗТЕЛА У БОЙЦОВ: СЦЕНА ПРОТИВ new(), N = %d ═══" % n)

	var scene := load("res://scenes/units/Spearman.tscn") as PackedScene
	out.append("корневой узел scenes/units/Spearman.tscn: %s"
		% scene.instantiate().get_class())

	var a1 := await _measure(func(): return scene.instantiate(), n)
	out.append("")
	out.append("── армия ИЗ СЦЕНЫ (как в игре) ──")
	out.append("  активных физ. тел: %d" % a1["bodies"])
	out.append("  тик марша:         %.2f мс" % a1["tick"])

	var a2 := await _measure(func(): return SpearScript.new(), n)
	out.append("")
	out.append("── армия ЧЕРЕЗ new() (как в стендах) ──")
	out.append("  активных физ. тел: %d" % a2["bodies"])
	out.append("  тик марша:         %.2f мс" % a2["tick"])

	out.append("")
	out.append("разница тика: %.2f мс (%.0f%%)"
		% [a1["tick"] - a2["tick"],
		   100.0 * (a1["tick"] - a2["tick"]) / maxf(a2["tick"], 0.01)])
	print("\n".join(out))
	get_tree().quit(0)

func _measure(maker: Callable, n: int) -> Dictionary:
	for u in _units:
		if is_instance_valid(u):
			u.free()
	_units.clear()
	GameManager.reset_squads()
	await frames(6)

	var cols := 40
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(n):
		var u: Unit = maker.call()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(
			float(i % cols) * 0.9 - 18.0, 0.0, float(i / cols) * 0.9 - 30.0)
		u.max_health = 1e9
		u.current_health = 1e9
		if i % 50 == 0 and i > 0:
			sid = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		GameManager.add_to_squad(sid, u)
		_units.append(u)
	await frames(8)
	var bodies := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	for u in _units:
		(u as Unit).command_move(u.global_position + Vector3(60.0, 0.0, 0.0))
	_OptCfg.tick_meter = true
	_OptCfg.tick_reset()
	await frames(90)
	_OptCfg.tick_meter = false
	return {"bodies": bodies, "tick": _OptCfg.tick_ms()}
