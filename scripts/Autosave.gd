extends Node
## ═══════════════════════════════════════════════════════════════════════════
## АВТОСОХРАНЕНИЕ ПАРТИИ (ТЗ 13.10.2026, письмо 7)
## ═══════════════════════════════════════════════════════════════════════════
## Узел Main.autosave. Раз в N минут игрового времени (N — ручка
## game_settings.autosave_minutes: 0 / 5 / 10 / 15) пишет партию в ОДИН
## выделенный файл SaveLoadManager.AUTOSAVE_PATH (слот 0), перезаписывая его.
##
## ── ПОЧЕМУ НЕ ФРИЗИТ ───────────────────────────────────────────────────────
## Сохранение — три шага, и дорог из них на главном потоке только первый:
##   1. СЛЕПОК (SaveLoadManager.capture) — обход живых бойцов и построек,
##      колонки чисел. Идёт на главном потоке в одном кадре: слепок обязан быть
##      согласованным (отряд и его бойцы из одного мгновения), а узлы дерева
##      из другого потока читать нельзя. Замер — qa_autosave C (строка
##      «главный поток»);
##   2. КОДИРОВАНИЕ в байты (var_to_bytes) и
##   3. ЗАПИСЬ на диск через временный файл с переименованием —
##      оба в ФОНОВОМ ПОТОКЕ (Thread): словарь слепка после capture() главному
##      потоку не нужен, ни дерева сцены, ни RenderingServer поток не трогает
##      (правило многопоточности ядра: только чистые данные).
## Готовность потока опрашивается в _process (is_alive), wait_to_finish —
## только по завершении; второй запуск, пока первый пишет, пропускается.
##
## ── ЧАСЫ ───────────────────────────────────────────────────────────────────
## Считает СВОЁ время, а не читает game_clock: отсчёт обязан замирать на
## паузе (get_tree().paused) и в любой фазе, кроме живой партии (расстановка
## крепости, победа, поражение), а начинаться заново — со старта партии и
## при смене интервала в меню. В главном меню узла нет вовсе (сцена другая).
##
## Запись в main-меню/паузе не делается и по второй причине: слепок на паузе
## ничем не отличается от слепка перед ней.

const _Save := preload("res://scripts/SaveLoadManager.gd")
const _GS := preload("res://scripts/game_settings.gd")

## Сколько секунд осталось до следующего автосохранения
var seconds_left: float = 0.0

## Счётчики и последний итог — стендам и плашке
var saves_done: int = 0
var saves_skipped: int = 0
var last_error: String = ""
## Цена ПОСЛЕДНЕГО слепка на главном потоке, мкс (capture), и длительность
## фоновой записи, мс
var last_capture_usec: int = 0
var last_write_ms: int = 0

signal saved(ok: bool, err: String)

var _main: Node = null
var _thread: Thread = null
var _write_started_ms: int = 0
## Запрет (стенды, загрузка): пока true — таймер стоит
var suspended: bool = false

func setup(main: Node) -> void:
	_main = main
	# Узел живёт на паузе (как Main), чтобы ДОПИСАТЬ начатый файл и снять
	# поток; сам отсчёт на паузе стоит явной проверкой ниже
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_timer()

## Отсчёт заново — от старта партии и после смены интервала в меню
func reset_timer() -> void:
	seconds_left = interval_sec()

func interval_sec() -> float:
	return float(_GS.autosave_minutes()) * 60.0

func enabled() -> bool:
	return _GS.autosave_minutes() > 0

## Идёт ли сейчас фоновая запись
func writing() -> bool:
	return _thread != null and _thread.is_alive()

func _process(delta: float) -> void:
	_poll_thread()
	if suspended or not enabled():
		return
	if _main == null or not is_instance_valid(_main):
		return
	if get_tree().paused or not bool(_main.call("is_playing")):
		return
	seconds_left -= delta
	if seconds_left > 0.0:
		return
	seconds_left = interval_sec()
	trigger()

## Сохранить сейчас (таймер, стенд, горячая клавиша). Возвращает "" при
## запуске, иначе причину, по которой запись не пошла
func trigger() -> String:
	if _main == null or not is_instance_valid(_main):
		return "нет партии"
	if _thread != null:
		# Предыдущая запись ещё идёт (диск занят, очень большая партия) —
		# этот такт пропускаем, следующий придёт по часам
		saves_skipped += 1
		return "предыдущее автосохранение ещё пишется"
	var t0: int = Time.get_ticks_usec()
	var state: Dictionary = _Save.capture(_main)
	last_capture_usec = Time.get_ticks_usec() - t0
	_write_started_ms = Time.get_ticks_msec()
	_thread = Thread.new()
	var err: int = _thread.start(_worker.bind(state))
	if err != OK:
		# Поток не поднялся (редкость: лимит потоков) — пишем на месте, это
		# лучше потерянной партии
		_thread = null
		var e: String = _Save.write_bytes(_Save.AUTOSAVE_PATH, _Save.encode_state(state))
		_finish(e)
	return ""

## Тело фонового потока: только чистые данные и файловая система
func _worker(state: Dictionary) -> String:
	return _Save.write_bytes(_Save.AUTOSAVE_PATH, _Save.encode_state(state))

func _poll_thread() -> void:
	if _thread == null or _thread.is_alive():
		return
	var err: String = String(_thread.wait_to_finish())
	_thread = null
	last_write_ms = Time.get_ticks_msec() - _write_started_ms
	_finish(err)

func _finish(err: String) -> void:
	last_error = err
	if err.is_empty():
		saves_done += 1
	saved.emit(err.is_empty(), err)
	var hud = _main.get("hud") if _main != null and is_instance_valid(_main) else null
	if hud != null and is_instance_valid(hud) and hud.has_method("show_autosave_note"):
		hud.call("show_autosave_note", "Игра сохранена" if err.is_empty()
			else "Автосохранение не удалось: " + err)

## Дождаться записи (стенд, выход из сцены): поток нельзя бросать живым
func flush() -> void:
	if _thread != null:
		var err: String = String(_thread.wait_to_finish())
		_thread = null
		last_write_ms = Time.get_ticks_msec() - _write_started_ms
		_finish(err)

func _exit_tree() -> void:
	flush()
