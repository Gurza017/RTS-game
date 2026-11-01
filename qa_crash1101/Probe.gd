extends Node
## ЗОНД: вылет .exe 01.11.2026 на 85-й минуте (нативный 0xc0000005 в
## Dictionary::get_valid на главном потоке). Поднимает слепок (по умолчанию
## копию автосейва владельца 75:00) и гонит партию со всеми ИИ minutes игровых
## минут при ускорении speed; раз в игровую минуту пишет строку состояния в
## out-файл с flush — при сегфолте последняя строка остаётся на диске, а
## отладочная сборка печатает GDScript-бэктрейс. Вердиктов нет.
##   godot --headless --path . res://qa_crash1101/Probe.tscn -- save=<путь> minutes=15 speed=1 out=<путь>
var main: Node
var _save := "user://autosave.tts"
var _minutes := 15.0
var _speed := 1.0
var _out := ""
var _log: FileAccess = null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("save="):
			_save = s.substr(5)
		elif s.begins_with("minutes="):
			_minutes = float(s.substr(8))
		elif s.begins_with("speed="):
			_speed = float(s.substr(6))
		elif s.begins_with("out="):
			_out = s.substr(4)
	call_deferred("_run")

func _note(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.get_32()
	f.get_32()
	f.get_32()
	var d: Variant = f.get_var(false)
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _run() -> void:
	if _out != "":
		_log = FileAccess.open(_out, FileAccess.WRITE)
	var st: Dictionary = _read(_save)
	if st.is_empty():
		_note("слепка нет: " + _save)
		get_tree().quit()
		return
	_note("слепок %s: часы %.0f, отрядов %d" % [_save, float(st["meta"].get("clock", 0.0)), (st["squads"] as Array).size()])
	_Opt.squad_probes = true
	GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(60):
		await get_tree().physics_frame
	Engine.time_scale = _speed
	var t0: int = Unit.game_ms()
	var next_min := 1
	var wall0: int = Time.get_ticks_msec()
	while Unit.game_ms() - t0 < int(_minutes * 60000.0):
		await get_tree().physics_frame
		if Unit.game_ms() - t0 >= next_min * 60000:
			_note("мин %d: часы партии %.0f, бойцов %d, отрядов %d, тел %d, стена %.0f с, память %.0f МБ, объектов %d, узлов %d, сирот %d" % [
				next_min, float(main.game_clock()), GameManager._live_units.size(), GameManager.squads.size(),
				GameManager.corpses.count() if GameManager.corpses != null else -1,
				(Time.get_ticks_msec() - wall0) / 1000.0,
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				int(Performance.get_monitor(Performance.OBJECT_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
			next_min += 1
	_note("=== ДОШЁЛ ДО КОНЦА БЕЗ ВЫЛЕТА ===")
	get_tree().quit()

const _Opt := preload("res://scripts/perf_config.gd")
