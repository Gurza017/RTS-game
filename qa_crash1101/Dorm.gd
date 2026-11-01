extends Node
## ЗОНД «СПЯТ НА ХОДУ» (разбор 01.11.2026): зонд марша нашёл 80-91 % идущих
## гоблинов со снятым тиком (F_DORMANT) в состоянии MOVING — тик погашен, лента
## ходьбы листается, то есть бег на месте на привале. Кто дал им последний
## приказ: раз в 5 с снимает таких бойцов и сводит dbg_src (стек command_move/
## command_attack), состояние строки в ядре и признак dormant узла. Вердиктов нет.
##   godot --headless --path . res://qa_crash1101/Dorm.tscn -- save=<путь> minutes=4 out=<путь>
const _Opt := preload("res://scripts/perf_config.gd")
const _Soa := preload("res://scripts/army/ArmySoA.gd")
var main: Node
var _save := "user://autosave.tts"
var _minutes := 4.0
var _out := ""
var _log: FileAccess = null
var _src: Dictionary = {}
var _samples := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("save="):
			_save = s.substr(5)
		elif s.begins_with("minutes="):
			_minutes = float(s.substr(8))
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

func _sample() -> void:
	_samples += 1
	var A = GameManager.army
	var n := 0
	for u in GameManager._live_units:
		if not is_instance_valid(u):
			continue
		var un := u as Unit
		if un.is_dead() or un._soa < 0:
			continue
		if not A.has_flag(un._soa, _Soa.F_DORMANT):
			continue
		if un.state != Unit.State.MOVING:
			continue
		n += 1
		var key := "%s | узел dormant=%s tick=%s | %s" % [String(un.stat_id), str(un.dormant), str(un.tick_on), un.dbg_src.substr(0, 150)]
		_src[key] = int(_src.get(key, 0)) + 1
	_note("  выборка %d: спящих в MOVING %d" % [_samples, n])

func _run() -> void:
	if _out != "":
		_log = FileAccess.open(_out, FileAccess.WRITE)
	var st: Dictionary = _read(_save)
	if st.is_empty():
		_note("слепка нет: " + _save)
		get_tree().quit()
		return
	Unit.dbg_order_src = true
	GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	var t0: int = Unit.game_ms()
	var next_s := 5
	while Unit.game_ms() - t0 < int(_minutes * 60000.0):
		await get_tree().physics_frame
		if Unit.game_ms() - t0 >= next_s * 1000:
			_sample()
			next_s += 5
	_note("═══ СПЯЩИЕ В MOVING: источник последнего приказа (бойцо-выборок) ═══")
	var keys: Array = _src.keys()
	keys.sort_custom(func(a, b): return int(_src[a]) > int(_src[b]))
	for i in range(mini(30, keys.size())):
		_note("%7d  %s" % [int(_src[keys[i]]), keys[i]])
	_note("=== ГОТОВО ===")
	get_tree().quit()
