extends Node
## СТРЕСС АВТОСОХРАНЕНИЯ (разбор вылета .exe 01.11.2026). Вылет пришёлся ровно
## на срок следующего автосейва (слепок 20:47:50, дамп 21:03:48 при интервале
## 15 мин по часам кадров). Поднимает слепок и гонит партию со всеми ИИ, зовя
## Autosave.trigger() каждые every секунд стены (идущая запись — пропуск, как в
## игре); every=0 — без автосейвов вовсе (контроль). Раз в 30 с стены — строка
## в out-файл с flush: при сегфолте последняя остаётся. Вердиктов нет.
##   godot --headless --path . res://qa_crash1101/Stress.tscn -- save=<путь> minutes=10 every=3 out=<путь>
const _Opt := preload("res://scripts/perf_config.gd")
var main: Node
var _save := "user://autosave.tts"
var _minutes := 10.0
var _every := 3.0
var _out := ""
var _log: FileAccess = null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("save="):
			_save = s.substr(5)
		elif s.begins_with("minutes="):
			_minutes = float(s.substr(8))
		elif s.begins_with("every="):
			_every = float(s.substr(6))
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
	# Релизный exe не берёт путь сцены из командной строки — стенд стартует
	# главной сценой из override.cfg, и SaveLoadManager не узнаёт в нём стенд
	# (признак — res://qa_* в аргументах). Пишем в qa_saves явно: автосейв
	# владельца не трогаем
	var SL = load("res://scripts/SaveLoadManager.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa_saves/"))
	SL.SAVE_DIR = "user://qa_saves/"
	SL.AUTOSAVE_PATH = "user://qa_saves/autosave_stress.tts"
	if _out != "":
		_log = FileAccess.open(_out, FileAccess.WRITE)
	var st: Dictionary = _read(_save)
	if st.is_empty():
		_note("слепка нет: " + _save)
		get_tree().quit()
		return
	_note("слепок: часы %.0f; автосейв каждые %.1f с стены; сборка %s" % [
		float(st["meta"].get("clock", 0.0)), _every, "отладка" if OS.is_debug_build() else "РЕЛИЗ"])
	GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(60):
		await get_tree().physics_frame
	var asv: Node = main.get("autosave")
	if asv != null:
		# Свой отсчёт стенда: таймер узла сдвинут далеко, чтобы не мешал
		asv.set("seconds_left", 1.0e9)
	var t0: int = Unit.game_ms()
	var w0: int = Time.get_ticks_msec()
	var next_save: int = w0 + int(_every * 1000.0)
	var next_note: int = w0 + 30000
	var asked := 0
	while Unit.game_ms() - t0 < int(_minutes * 60000.0):
		await get_tree().process_frame
		var now: int = Time.get_ticks_msec()
		if _every > 0.0 and asv != null and now >= next_save:
			next_save = now + int(_every * 1000.0)
			asked += 1
			_note("  → автосейв %d, часы %.1f" % [asked, float(main.game_clock())])
			asv.call("trigger")
		if now >= next_note:
			next_note = now + 30000
			_note("стена %.0f с: часы %.0f, бойцов %d, запросов %d, записано %d, пропущено %d, захват %.1f мс, запись %d мс, ошибка «%s»" % [
				(now - w0) / 1000.0, float(main.game_clock()), GameManager._live_units.size(), asked,
				int(asv.get("saves_done")) if asv != null else -1,
				int(asv.get("saves_skipped")) if asv != null else -1,
				float(asv.get("last_capture_usec")) / 1000.0 if asv != null else -1.0,
				int(asv.get("last_write_ms")) if asv != null else -1,
				String(asv.get("last_error")) if asv != null else "?"])
	if asv != null:
		asv.call("flush")
	_note("=== ДОШЁЛ ДО КОНЦА БЕЗ ВЫЛЕТА ===")
	get_tree().quit()
