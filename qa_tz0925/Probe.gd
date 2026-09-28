extends Node

## ЗОНД ТЗ 25.09.2026, п. 1: кто стоит у базы красного ИИ.
## Поднимает живую Main, печатает все отряды (фракция отряда, род, фракция
## бойцов, центр, спит ли) и якоря баз. Запуск:
##   godot --headless --path . res://qa_tz0925/Probe.tscn [-- sec=N]

var main = null
var _sec := 5.0
var _t0 := -1.0
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("sec="):
			_sec = float(s.substr(4))
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)

func _physics_process(_d: float) -> void:
	if main == null or _done:
		return
	var clock: float = float(main._match_clock)
	if clock < _sec:
		return
	_done = true
	print("ЯКОРЯ: игрок %s  ИИ %s  деревня %s" % [main.PLAYER_BASE_ANCHOR,
		main.ENEMY_BASE_ANCHOR, main.goblin_village_center()])
	var fac_mix := 0
	for sid in GameManager.squads.keys():
		var sq: Dictionary = GameManager.squads[sid]
		var ms: Array = sq["members"]
		var live: Array = []
		var facs := {}
		var sleep := 0
		for m in ms:
			if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
				live.append(m)
				facs[(m as Unit).faction] = true
				if not (m as Unit).tick_on:
					sleep += 1
		if live.is_empty():
			continue
		var c: Vector3 = GameManager._centroid_of(live)
		var de: float = Vector2(c.x - main.ENEMY_BASE_ANCHOR.x, c.z - main.ENEMY_BASE_ANCHOR.z).length()
		if facs.size() != 1 or not facs.has(int(sq["faction"])):
			fac_mix += 1
		print("  отряд %d фр=%d тип=%s n=%d фр_бойцов=%s спят=%d центр=(%.0f,%.0f) до_базы_ИИ=%.0f" % [
			sid, int(sq["faction"]), String(sq["type"]), live.size(), str(facs.keys()),
			sleep, c.x, c.z, de])
	print("ИТОГ: отрядов со смешанной фракцией %d" % fac_mix)
	get_tree().quit()
