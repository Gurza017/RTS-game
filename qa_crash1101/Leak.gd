extends Node
## ЗОНД НАКОПИТЕЛЬНЫХ УТЕЧЕК (разбор партии .exe 01.11.2026, 1.5 часа боя).
## Поднимает слепок, гонит партию со всеми ИИ и раз в игровую минуту снимает
## РАЗМЕРЫ всех полей-контейнеров (Dictionary, Array, Packed*) у автозагрузок
## и у узлов со скриптом в Main (на глубину 2 — ИИ, командиры, рендереры), а
## также счётчики объектов движка. В конце печатает контейнеры, выросшие за
## прогон монотонно, — кандидатов в утечку. Вердиктов нет.
##   godot --headless --path . res://qa_crash1101/Leak.tscn -- save=<путь> minutes=20 speed=2 out=<путь>
const _Opt := preload("res://scripts/perf_config.gd")
var main: Node
var _save := "user://autosave.tts"
var _minutes := 20.0
var _speed := 2.0
var _out := ""
var _log: FileAccess = null
var _hist: Dictionary = {}   # "узел.поле" → Array размеров по минутам

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

func _size_of(v: Variant) -> int:
	match typeof(v):
		TYPE_DICTIONARY:
			return (v as Dictionary).size()
		TYPE_ARRAY:
			return (v as Array).size()
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
				TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, \
				TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return v.size()
	return -1

func _scan_obj(tag: String, o: Object) -> void:
	if o == null or o.get_script() == null:
		return
	for p in o.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = String(p["name"])
		var v: Variant = o.get(n)
		var sz := _size_of(v)
		if sz < 0:
			continue
		var key := tag + "." + n
		if not _hist.has(key):
			_hist[key] = []
		(_hist[key] as Array).append(sz)

func _snapshot() -> void:
	for al in ["GameManager", "ResourceManager", "AudioManager"]:
		_scan_obj(al, get_tree().root.get_node_or_null(al))
	_scan_obj("Main", main)
	for c in main.get_children():
		if c.get_script() != null:
			_scan_obj("Main/" + String(c.name), c)
		for cc in c.get_children():
			if cc.get_script() != null and not (cc is Unit) and not (cc is Building):
				_scan_obj("Main/%s/%s" % [c.name, cc.name], cc)
	var eng := {"objects": Performance.OBJECT_COUNT, "nodes": Performance.OBJECT_NODE_COUNT,
		"orphans": Performance.OBJECT_ORPHAN_NODE_COUNT, "resources": Performance.OBJECT_RESOURCE_COUNT,
		"mem_kb": Performance.MEMORY_STATIC}
	for k in eng:
		var key := "engine." + String(k)
		if not _hist.has(key):
			_hist[key] = []
		var val := Performance.get_monitor(eng[k])
		(_hist[key] as Array).append(int(val / 1024.0) if k == "mem_kb" else int(val))

func _run() -> void:
	if _out != "":
		_log = FileAccess.open(_out, FileAccess.WRITE)
	var st: Dictionary = _read(_save)
	if st.is_empty():
		_note("слепка нет: " + _save)
		get_tree().quit()
		return
	_Opt.squad_probes = true
	GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(60):
		await get_tree().physics_frame
	Engine.time_scale = _speed
	var t0: int = Unit.game_ms()
	var next_min := 0
	while Unit.game_ms() - t0 < int(_minutes * 60000.0):
		await get_tree().physics_frame
		if Unit.game_ms() - t0 >= next_min * 60000:
			_snapshot()
			_note("мин %d: бойцов %d, отрядов %d, объектов %d, узлов %d, сирот %d, память %.0f МБ" % [next_min,
				GameManager._live_units.size(), GameManager.squads.size(),
				int(Performance.get_monitor(Performance.OBJECT_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
			next_min += 1
	_note("=== РОСТ КОНТЕЙНЕРОВ (первая → последняя минута; монотонно = ни разу не убыл) ===")
	var rows: Array = []
	for k in _hist:
		var h: Array = _hist[k]
		if h.size() < 3:
			continue
		var grow: int = int(h[h.size() - 1]) - int(h[0])
		if grow <= 0:
			continue
		var mono := true
		for i in range(1, h.size()):
			if int(h[i]) < int(h[i - 1]):
				mono = false
				break
		rows.append([grow, k, h, mono])
	rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	for r in rows:
		var h: Array = r[2]
		_note("%s %-70s %d → %d (+%d)  %s" % ["МОНОТОННО" if r[3] else "         ", r[1], int(h[0]), int(h[h.size() - 1]), int(r[0]), str(h)])
	_note("=== ГОТОВО ===")
	get_tree().quit()
