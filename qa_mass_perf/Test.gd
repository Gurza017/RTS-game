extends Node

const _OptCfgG = preload("res://scripts/perf_config.gd")

## ═══════════════════════════════════════════════════════════════════════════
## МАСШТАБ: 3000 И 5000 БОЙЦОВ НА МАРШЕ — ТИХИЙ ЗАМЕР
## ═══════════════════════════════════════════════════════════════════════════
## qa_march_perf меряет 810 моделей В КАДРЕ — там узкое место общее (рендер
## плюс тик). Здесь проверяется другое: ВЫДЕРЖИВАЕТ ЛИ ЛОГИКА заявленный
## масштаб. Врагов нет, армия идёт большими блоками.
##
## ЗАПУСК БЕЗ ОКНА (штатный режим, GPU и VRAM не трогаются вовсе):
##   godot --headless --path . res://qa_mass_perf/Test.tscn
## Только 5000:            ... --headless ... -- --count=5000
## Свои ступени:           ... -- --steps=810,3000,5000
## Разбивка по веткам:     ... -- --verbose      (профиль, вывод длиннее)
##
## ТИХО ПО УМОЛЧАНИЮ. За весь прогон в терминал не уходит ни строки — всё
## копится и печатается ОДНОЙ таблицей в конце. Консольный буфер VS Code
## подвешивает интерфейс на потоковом выводе, поэтому здесь его нет.
##
## ЧЕСТНОСТЬ ЧИСЕЛ (читать до того, как ссылаться на них):
##   • time_per_tick — сколько миллисекунд физического кадра съедает ВСЯ армия.
##     Меряется лёгким счётчиком (_Opt.tick_meter): одна пара Time.get_ticks_usec
##     НА КАДР. Разбивка по веткам (--verbose) носит на себе свой же замер —
##     два вызова на каждую ветку каждого бойца — и завышает итог, поэтому
##     PASS/FAIL считается по счётчику, а не по профилю.
##   • Бюджет физтика при 60 Гц — 16.60 мс. Это и есть критерий PASS.
##   • FPS БЕЗ ОКНА — НЕ ЗАМЕР ОТРИСОВКИ. Godot в headless не рисует ничего:
##     это темп главного цикла, то есть потолок ЛОГИКИ. Настоящий FPS и
##     вызовы отрисовки даёт только оконный прогон (qa_march_perf).

const _OptCfg = preload("res://scripts/perf_config.gd")

## Ступени замера по умолчанию. Каждая — своя армия, поставленная с нуля
const DEFAULT_STEPS := [810, 3000, 5000]

const SQUAD_SIZE := 50
const COLS       := 10
## Шаг между бойцами в строю и между отрядами: та же плотность, что у игрока
const GAP        := 0.9
const SQUAD_GAP  := 3.0

## Бюджет одного физического кадра при 60 Гц
const BUDGET_MS := 16.6

var main = null
var _units: Array = []
var _squads: Array = []

var _headless: bool = false
var _verbose: bool = false
var _steps: Array = []

## Всё, что стенд хочет сказать, копится здесь и печатается один раз в конце
var _rows: Array = []
var _notes: Array = []

func _ready() -> void:
	call_deferred("_run")

# ─────────────────────────────────────────────────────────────────────────────
# АРГУМЕНТЫ
# ─────────────────────────────────────────────────────────────────────────────
func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func _parse_args() -> void:
	_steps = DEFAULT_STEPS.duplicate()
	for a in _args():
		var s: String = String(a)
		if s == "--verbose":
			_verbose = true
		elif s.begins_with("--count="):
			var n: int = int(s.substr(8))
			if n > 0:
				_steps = [n]
		elif s.begins_with("--steps="):
			var list: Array = []
			for part in s.substr(8).split(",", false):
				var v: int = int(String(part).strip_edges())
				if v > 0:
					list.append(v)
			if not list.is_empty():
				_steps = list

# ─────────────────────────────────────────────────────────────────────────────
# ОЖИДАНИЕ
# ─────────────────────────────────────────────────────────────────────────────
## ФИЗИЧЕСКИЕ кадры: при Engine.max_fps = 0 рендер тикает быстрее физики,
## и ожидание process_frame не соответствует симулированному времени
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

## Камера RTS крутит краевую прокрутку по позиции курсора в своём _process, а
## курсор в запущенном стендом окне стоит в углу — за секунды камера уезжает,
## и стенд мерит пустой экран. Прибиваем её и держим точку обзора сами.
## В headless окна нет, но точка обзора всё равно нужна: по ней считается LOD
func _freeze_camera(at: Vector3, size: float) -> void:
	if main == null:
		return
	if main.has_method("focus_camera_on"):
		main.focus_camera_on(at)
	await get_tree().process_frame
	if main._camera != null:
		(main._camera as Node).set_process(false)
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			(cam as Camera3D).size = size
	GameManager.update_view_point(at)

func _clear_army() -> void:
	for u in _units:
		if is_instance_valid(u):
			(u as Node).queue_free()
	_units.clear()
	_squads.clear()
	await frames(6)

## Армия ставится квадратом отрядов вокруг начала координат — так же плотно,
## как войска стоят после выхода из казарм
func _spawn(total: int) -> void:
	var squads_n: int = int(ceil(float(total) / float(SQUAD_SIZE)))
	var per_row: int = int(ceil(sqrt(float(squads_n))))
	var rows_in_squad: int = int(ceil(float(SQUAD_SIZE) / float(COLS)))
	var sq_w: float = float(COLS) * GAP + SQUAD_GAP
	var sq_h: float = float(rows_in_squad) * GAP + SQUAD_GAP
	var origin_x: float = -0.5 * float(per_row) * sq_w
	var origin_z: float = -0.5 * float(per_row) * sq_h
	var placed := 0
	for s in range(squads_n):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		_squads.append(sid)
		var base_x: float = origin_x + float(s % per_row) * sq_w
		var base_z: float = origin_z + float(s / per_row) * sq_h
		for i in range(SQUAD_SIZE):
			if placed >= total:
				break
			var u: Unit = Spearman.new()
			u.faction = Constants.FACTION_PLAYER
			main.world_add(u)
			u.global_position = Vector3(
				base_x + float(i % COLS) * GAP,
				0.0,
				base_z + float(i / COLS) * GAP)
			# Бессмертные: стенд меряет марш, а не бой
			u.max_health = 1e9
			u.current_health = 1e9
			GameManager.add_to_squad(sid, u)
			_units.append(u)
			placed += 1

## КАЖДЫЙ ОТРЯД ИДЁТ В СВОЮ ТОЧКУ, сохраняя место в общем построении. Общая
## цель на всех — грубая ошибка замера: отряды сошлись бы в один квадрат, и
## мерилась бы предельная плотность, а не марш
func _march_by(offset: Vector3) -> void:
	for sid in _squads:
		var members: Array = GameManager.squad_members(int(sid))
		if members.is_empty():
			continue
		var centroid := Vector3.ZERO
		for u in members:
			centroid += (u as Node3D).global_position
		centroid /= float(members.size())
		centroid.y = 0.0
		var target: Vector3 = centroid + offset
		var course: Vector3 = offset.normalized()
		var slots: Array = []
		for u in members:
			var slot: Vector3 = target + ((u as Node3D).global_position - centroid)
			slot.y = 0.0
			slots.append(slot)
			(u as Unit).command_move(slot, false, course)
		GameManager.squad_set_formation(int(sid), slots, course, false)

func _moving_count() -> int:
	var n := 0
	for u in _units:
		if is_instance_valid(u) and (u as Unit).state == Unit.State.MOVING:
			n += 1
	return n

# ─────────────────────────────────────────────────────────────────────────────
# ЗАМЕР
# ─────────────────────────────────────────────────────────────────────────────
## Одно окно замера: цена тика армии (лёгкий счётчик) и темп главного цикла.
## Возвращает [мс_на_тик, кадров_в_секунду, кадров_физики_снято]
func _window(n_frames: int) -> Array:
	_OptCfg.tick_meter = true
	_OptCfg.vis_meter  = true
	_OptCfg.tick_reset()
	_OptCfg.vis_reset()
	var fps_acc := 0.0
	var fps_n := 0
	for _i in range(n_frames):
		await get_tree().physics_frame
		var f: float = Performance.get_monitor(Performance.TIME_FPS)
		if f > 0.0:
			fps_acc += f
			fps_n += 1
	var ms: float = _OptCfg.tick_ms()
	var vis: float = _OptCfg.vis_ms()
	var got: int = _OptCfg.tick_frames()
	_OptCfg.tick_meter = false
	_OptCfg.vis_meter  = false
	return [ms, (fps_acc / float(maxi(fps_n, 1))), got, vis]

## Разбивка по веткам — только по --verbose: профиль дорог сам по себе
func _breakdown(n_frames: int) -> Array:
	_OptCfg.profile_physics = true
	_OptCfg.prof_reset()
	await frames(n_frames)
	var rows: Array = _OptCfg.prof_report()
	_OptCfg.profile_physics = false
	var out: Array = []
	var sum_us := 0
	for row in rows:
		if not String(row[0]).begins_with("!"):
			sum_us += int(row[1])
	for row in rows:
		var bucket: String = String(row[0])
		if bucket.begins_with("!"):
			continue
		out.append("    %-18s %6.1f%% | %8d вызовов | %6.2f мкс/вызов"
			% [bucket, 100.0 * float(int(row[1])) / float(maxi(sum_us, 1)),
			   int(row[2]), float(row[3])])
	return out

func _mem_mb() -> float:
	return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0

# ─────────────────────────────────────────────────────────────────────────────
# ПРОГОН
# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	_parse_args()
	_headless = DisplayServer.get_name() == "headless"
	# Окно трогаем ТОЛЬКО если оно есть: в headless DisplayServer — заглушка,
	# и обращение к vsync/размеру там бессмысленно
	if not _headless:
		get_tree().root.size = Vector2i(1280, 720)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	# ДЕРЕВНЯ ГОБЛИНОВ ВЫКЛЮЧЕНА: стенд меряет ровно ту армию, которую
	# заявляет, и не растягивает габарит сетки на свой угол карты
	_OptCfgG.goblin_village = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	# Границы карты стенду не мешают, но 5000 бойцов занимают ~200×200 м —
	# отключаем зажим, чтобы марш не упирался в бортик
	GameManager.world_bounds_enabled = false
	await frames(3)

	var mem_base: float = _mem_mb()

	for total in _steps:
		await _clear_army()
		_spawn(int(total))
		# Обзор подгоняем под размер армии, чтобы камера смотрела на войска
		var span: float = 1.4 * sqrt(float(total)) * GAP + 40.0
		await _freeze_camera(Vector3.ZERO, span)
		await frames(120)      # прогрев: первый спавн разбирает спрайтлисты
		GameManager.update_view_point(Vector3.ZERO)

		var stand: Array = await _window(90)
		var mem_stand: float = _mem_mb()

		_march_by(Vector3(90.0, 0.0, 0.0))
		await frames(20)
		GameManager.update_view_point(Vector3.ZERO)
		var march: Array = await _window(90)

		var draws: int = 0
		if not _headless:
			draws = int(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

		_rows.append({
			"n": int(total),
			"stand_ms": float(stand[0]),
			"march_ms": float(march[0]),
			"vis_ms": float(march[3]),
			"shards": _OptCfg.shards_for(int(total)),
			"fps": float(march[1]),
			"moving": _moving_count(),
			"mem": mem_stand - mem_base,
			"bodies": int(Performance.get_monitor(
				Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
			"draws": draws,
		})

		if _verbose and int(total) == int(_steps[_steps.size() - 1]):
			_march_by(Vector3(90.0, 0.0, 0.0))
			await frames(10)
			_notes.append("Разбивка марша на %d (профиль включён, он же и" % int(total))
			_notes.append("завышает суммы — смотреть на доли, не на абсолют):")
			_notes.append_array(await _breakdown(90))

	_report()
	get_tree().quit(0 if _all_pass() else 1)

func _all_pass() -> bool:
	for r in _rows:
		if float((r as Dictionary)["march_ms"]) > BUDGET_MS:
			return false
	return true

# ─────────────────────────────────────────────────────────────────────────────
# ЕДИНСТВЕННЫЙ ВЫВОД
# ─────────────────────────────────────────────────────────────────────────────
func _report() -> void:
	var lines: Array = []
	var mode: String = "HEADLESS (без отрисовки)" if _headless else "ОКНО 1280x720"
	lines.append("")
	lines.append("=== MASS PERF | %s | бюджет физтика 60 Гц = %.2f мс ===" % [mode, BUDGET_MS])
	lines.append("")
	if _headless:
		lines.append("  FPS здесь — темп ГЛАВНОГО ЦИКЛА без отрисовки, то есть потолок")
		lines.append("  логики, а не кадры на экране. Вызовы отрисовки меряет qa_march_perf.")
		lines.append("")
	lines.append("  бойцов | тик стоя | тик марш | % бюджета | визуал | кадр | шард |    FPS | память |  итог")
	lines.append("  -------+----------+----------+-----------+--------+------+------+--------+--------+------")
	for r in _rows:
		var d: Dictionary = r
		var n: int = int(d["n"])
		var march_ms: float = float(d["march_ms"])
		var fps: float = float(d["fps"])
		var frame_ms: float = (1000.0 / fps) if fps > 0.0 else 0.0
		var pass_ok: bool = march_ms <= BUDGET_MS
		lines.append("  %6d | %6.2f мс | %6.2f мс | %8.0f%% | %4.1f мс | %4.0f | 1/%d | %6.1f | %4.0f МБ | %s"
			% [n, float(d["stand_ms"]), march_ms,
			   100.0 * march_ms / BUDGET_MS,
			   float(d["vis_ms"]), frame_ms, int(d["shards"]),
			   fps, float(d["mem"]),
			   "PASS" if pass_ok else "FAIL"])
	lines.append("")
	lines.append("  «тик» — вся армия в физическом кадре (критерий PASS), «визуал» — она же")
	lines.append("  в кадре отрисовки, «кадр» — полное время кадра главного цикла.")
	lines.append("  «шард» 1/2 = боец опрашивается через кадр, то есть 30 раз в секунду")
	lines.append("  (perf_config.shards_for). Путь и откаты от этого не меняются — delta")
	lines.append("  передаётся умноженной.")
	lines.append("")
	for r in _rows:
		var d2: Dictionary = r
		if int(d2["moving"]) < int(d2["n"]) * 0.5:
			lines.append("  ВНИМАНИЕ: на %d в движении только %d — замер марша недостоверен"
				% [int(d2["n"]), int(d2["moving"])])
	var bodies: int = int(_rows[0]["bodies"]) if not _rows.is_empty() else 0
	lines.append("  физических тел в мире: %d (норма — 0)" % bodies)
	if not _headless and not _rows.is_empty():
		lines.append("  вызовов отрисовки на последней ступени: %d"
			% int(_rows[_rows.size() - 1]["draws"]))
	if not _notes.is_empty():
		lines.append("")
		lines.append_array(_notes)
	lines.append("")
	lines.append("=== ИТОГ: %s ===" % ("PASS" if _all_pass() else "FAIL"))
	print("\n".join(PackedStringArray(lines)))
