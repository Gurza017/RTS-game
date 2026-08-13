extends Node

## ЦЕНА МАССОВОЙ ГИБЕЛИ АРМИИ.
## GameManager.unregister_unit снимал бойца с учёта через Array.erase — линейный
## поиск по всему реестру. Одна смерть в среднем полреестра сравнений, гибель
## всей армии — квадрат от её размера. В qa_mass_perf этого не видно вовсе:
## там никто не умирает.
##
## Здесь армия спавнится и целиком уничтожается, меряется время СНЯТИЯ С УЧЁТА.
## Запуск: godot --headless --path . res://qa_soa_floor/Unreg.tscn -- --count=6000

const DEFAULT_N := 6000

func _ready() -> void:
	call_deferred("_run")

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func _run() -> void:
	var n := DEFAULT_N
	for a in _args():
		var s := String(a)
		if s.begins_with("--count="):
			var v := int(s.substr(8))
			if v > 0:
				n = v

	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var Spear := load("res://scenes/units/Spearman.tscn") as PackedScene
	var world: Node3D = main.world_root()
	var units: Array = []
	units.resize(n)
	for i in range(n):
		var u = Spear.instantiate()
		u.faction = Constants.FACTION_PLAYER
		world.add_child(u)
		u.global_position = Vector3(
			float(i % 100) * 0.9 - 45.0, 0.0, float(i / 100) * 0.9 - 20.0)
		units[i] = u
	await get_tree().process_frame
	await get_tree().process_frame

	var live: int = GameManager._live_units.size()

	# ПОРЯДОК ГИБЕЛИ РЕШАЕТ ВСЁ для прежнего Array.erase: тот ищет бойца
	# ЛИНЕЙНО С НАЧАЛА. Гибель в порядке регистрации — его ЛУЧШИЙ случай
	# (всегда индекс 0), в обратном — худший (полный проход каждый раз).
	# Настоящий бой лежит между ними, поэтому меряем оба края
	var order := "forward"
	for a in _args():
		var s := String(a)
		if s.begins_with("--order="):
			order = s.substr(8)
	if order == "reverse":
		units.reverse()
	elif order == "shuffle":
		units.shuffle()
	print("порядок гибели: %s" % order)
	var t0 := Time.get_ticks_usec()
	for u in units:
		u.free()
	var dt := float(Time.get_ticks_usec() - t0) / 1000.0

	var out := PackedStringArray()
	out.append("")
	out.append("═══ СНЯТИЕ АРМИИ С УЧЁТА, N = %d ═══" % n)
	out.append("было в реестре:        %d" % live)
	out.append("осталось в реестре:    %d" % GameManager._live_units.size())
	out.append("время снятия ВСЕХ:     %.1f мс" % dt)
	out.append("на одного бойца:       %.2f мкс" % (dt * 1000.0 / float(maxi(n, 1))))
	print("\n".join(out))
	get_tree().quit(0)
