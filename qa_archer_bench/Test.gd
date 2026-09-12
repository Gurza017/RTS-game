extends Node

## ═══════════════════════════════════════════════════════════════════════════
## БЕНЧМАРК ЛУЧНИКОВ — qa_archer_bench (агент «Archer & FPS Optimizer»)
## ═══════════════════════════════════════════════════════════════════════════
## Ставит ARCHERS лучников игрока (отрядами по SQUAD) против неподвижной стены
## чужой пехоты в TARGET_DIST метрах и меряет ДВА режима стрельбы подряд на
## одной и той же сцене:
##   • «ЗАЛП»          — способность archer_1d включена (squad_volley_mode);
##   • «ПО ГОТОВНОСТИ» — способность выключена, каждый стреляет сам.
## На каждый режим: MEASURE_SEC игровых секунд (физкадрами, правило 11):
##   средний FPS и интервал кадра по стенным часам (средний / p95 / худший),
##   цена физтика армии (perf_config.tick_meter → tick_ms) и кадра логики
##   (vis_meter), стрелы в воздухе (пик), выстрелов, попаданий, пиков залпа.
## В HEADLESS честны только ФИЗТИК и счётчики: FPS и кадр — только в окне
## (`godot --path . res://qa_archer_bench/Test.tscn`). Вердиктов два и оба —
## свойства, а не числа: залп даёт пики (>= половины отряда в один кадр), режим
## «по готовности» пиков не даёт; стрелы из пула (узлов не больше потолка).
## Параметры: `-- archers=N squad=M dist=D secs=S` (умолчания ниже).
## Запуск: godot --headless --path . res://qa_archer_bench/Test.tscn
##         godot --path . res://qa_archer_bench/Test.tscn  (окно: FPS)

const _Opt := preload("res://scripts/perf_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

var ARCHERS := 120
var SQUAD := 30
var TARGET_DIST := 16.0
var MEASURE_SEC := 20.0
const PEAK_WIN := 6

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _archers: Array = []
var _sids: Array = []
var _foes: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(a).split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"archers": ARCHERS = int(kv[1])
			"squad": SQUAD = int(kv[1])
			"dist": TARGET_DIST = float(kv[1])
			"secs": MEASURE_SEC = float(kv[1])
	call_deferred("_run")
	var t := get_tree().create_timer(400.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: бенчмарк не завершился за 400 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_archer_bench: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = _g(at)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, fac: int, at: Vector3, n: int, cols: int, gap: float) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	for i in range(n):
		var p := at + Vector3((float(i % cols) - float(cols - 1) * 0.5) * gap, 0.0, float(i / cols) * gap)
		var u := _spawn(uid, fac, p)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [men, sid]

func _alive(list: Array) -> int:
	var n := 0
	for u in list:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	_Opt.goblin_village = false
	await pframes(4)
	var pf: int = Constants.FACTION_PLAYER
	var ef: int = Constants.FACTION_ENEMY
	GameManager.finish_research(pf, _Forge.node_id("archer", "1d"))
	var p0 := Vector3(-900.0, 0.0, -900.0)
	var squads: int = int(ceil(float(ARCHERS) / float(SQUAD)))
	for s in range(squads):
		var n: int = mini(SQUAD, ARCHERS - s * SQUAD)
		var sq: Array = _squad("archer", pf, p0 + Vector3(float(s) * 9.0, 0.0, 0.0), n, 10, 0.8)
		_archers.append_array(sq[0])
		_sids.append(int(sq[1]))
	# Стена чужой пехоты: неподвижная (замороженный тик) и бессмертная, чтобы
	# оба режима стреляли по одной и той же цели одинаковое время
	var foe_n: int = maxi(ARCHERS, 40)
	var fsq: Array = _squad("spearman", ef, p0 + Vector3(float(squads - 1) * 4.5, 0.0, TARGET_DIST), foe_n, 20, 0.6)
	_foes = fsq[0]
	for f in _foes:
		var fu := f as Unit
		fu.set_tick(false)
		fu.max_health = 1.0e7
		fu.current_health = 1.0e7
		fu._soa_push_stats()
	await pframes(6)
	print("  лучников %d (отрядов %d по %d), целей %d на %.0f м; замер %.0f с на режим" % [
		_alive(_archers), squads, SQUAD, _alive(_foes), TARGET_DIST, MEASURE_SEC])
	var t_target: Unit = _foes[_foes.size() / 2]
	var pool_before: int = (GameManager.get("_arrow_pool") as Array).size()
	# СНАЧАЛА «ПО ГОТОВНОСТИ», ПОТОМ ЗАЛП: залп синхронизирует перезарядки
	# всего отряда, и после него стрелки стреляли бы пачками ещё минуту —
	# в обратном порядке режим «по готовности» мерил бы хвост залпа
	var report_b: Dictionary = await _measure("ПО ГОТОВНОСТИ (archer_1d выкл.)", false, t_target)
	await _cooldown()
	var report_a: Dictionary = await _measure("ЗАЛП (archer_1d вкл.)", true, t_target)
	_print_table([report_b, report_a])
	# ── ВЕРДИКТЫ — СВОЙСТВА ──────────────────────────────────────────────
	var half: int = SQUAD / 2
	verdict("V1 залп идёт пачками: пик выстрелов за 0.1 с %d ≥ половины отряда (%d)" % [int(report_a["peak_frame"]), half],
		int(report_a["peak_frame"]) >= half)
	verdict("V2 по готовности пачек нет: пик за 0.1 с %d < половины отряда" % int(report_b["peak_frame"]),
		int(report_b["peak_frame"]) < half)
	verdict("V3 оба режима стреляют: выстрелов %d и %d" % [int(report_a["shots"]), int(report_b["shots"])],
		int(report_a["shots"]) > 0 and int(report_b["shots"]) > 0)
	var nodes: int = get_tree().get_nodes_in_group("arrows").size() if get_tree().has_group("arrows") else -1
	verdict("V4 стрелы из пула: узлов стрел %d, потолок торчащих %d, пул до/после %d/%d" % [
			nodes, GameManager.MAX_STUCK_ARROWS, pool_before, (GameManager.get("_arrow_pool") as Array).size()],
		nodes < 0 or nodes <= GameManager.MAX_STUCK_ARROWS + ARCHERS * 2)
	_finish()

## Пауза между режимами: стрелы долетают, торчащие остаются (их потолок общий)
func _cooldown() -> void:
	await pframes(60 * 4)

func _measure(label: String, volley: bool, target: Unit) -> Dictionary:
	print("\n═════ РЕЖИМ: %s ═════" % label)
	for sid in _sids:
		GameManager.squad_set_ability(sid, "archer_1d", volley)
	var shots0: int = _shots_total()
	# Стрелки «подошли в разное время»: перезарядка у каждого в своей фазе.
	# Иначе первый залп синхронен по построению в ОБОИХ режимах, и режим
	# «по готовности» держал бы строй выстрелов вечно — сравнивать нечего.
	# Залп обязан свести их обратно (это его работа), готовность — нет
	for a in _archers:
		if is_instance_valid(a) and not (a as Unit).is_dead():
			var au := a as Unit
			# ДО приказа: после первого выстрела перезарядку держит ядро
			# (дрёма), и поле уже не перепишешь
			au.set("_attack_timer", AudioManager.rng.randf() * au.attack_cooldown)
			au.command_attack(target, true, false, true)
	_Opt.tick_meter = true
	_Opt.tick_reset()
	_Opt.vis_meter = true
	_Opt.vis_reset()
	var deltas: PackedFloat32Array = PackedFloat32Array()
	var t_prev: int = Time.get_ticks_usec()
	var t0: int = t_prev
	var frames_total: int = int(MEASURE_SEC * 60.0)
	var peak_flight := 0
	var peak_frame := 0
	var prev_shots: int = shots0
	var draw_frames0: int = Engine.get_frames_drawn()
	# «Пачка» — выстрелы за короткое ОКНО (PEAK_WIN кадров, 0.1 с), а не за
	# один кадр: окно залпа открывается на доли секунды, и стрелки в нём
	# спускают тетиву по своей готовности, разбросанной на несколько кадров
	var per_frame: PackedInt32Array = PackedInt32Array()
	for f in range(frames_total):
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		deltas.append(float(now - t_prev) * 0.001)
		t_prev = now
		var cur: int = _shots_total()
		per_frame.append(cur - prev_shots)
		prev_shots = cur
		var win := 0
		for k in range(maxi(per_frame.size() - PEAK_WIN, 0), per_frame.size()):
			win += per_frame[k]
		peak_frame = maxi(peak_frame, win)
		if f % 5 == 0:
			peak_flight = maxi(peak_flight, GameManager.arrows_mm.flight_count())
	var wall_sec: float = float(Time.get_ticks_usec() - t0) / 1.0e6
	var drawn: int = Engine.get_frames_drawn() - draw_frames0
	var sorted: Array = Array(deltas)
	sorted.sort()
	var worst: float = float(sorted[sorted.size() - 1])
	var p95: float = float(sorted[int(float(sorted.size() - 1) * 0.95)])
	var mean := 0.0
	for d in deltas:
		mean += float(d)
	mean /= maxf(float(deltas.size()), 1.0)
	var rep := {
		"label": label, "shots": _shots_total() - shots0, "peak_flight": peak_flight,
		"peak_frame": peak_frame, "tick_ms": _Opt.tick_ms(), "vis_ms": _Opt.vis_ms(),
		"frame_mean": mean, "frame_p95": p95, "frame_worst": worst,
		"fps": float(drawn) / maxf(wall_sec, 0.001), "headless": DisplayServer.get_name() == "headless",
		"stuck": GameManager.stuck_arrow_count(),
	}
	_Opt.tick_meter = false
	_Opt.vis_meter = false
	return rep

## Сумма выстрелов по всем лучникам — счётчик ударов бойца (Unit._strike_count
## растёт на каждый выстрел: у стрелка «удар» и есть выстрел)
func _shots_total() -> int:
	var n := 0
	for a in _archers:
		if is_instance_valid(a):
			n += int((a as Node).get("_strike_count"))
	return n

func _print_table(reps: Array) -> void:
	print("\n═════ ОТЧЁТ БЕНЧМАРКА ЛУЧНИКОВ (%d лучников) ═════" % _alive(_archers))
	print("  %-34s %8s %8s %8s %9s %9s %9s %8s %7s %7s" % [
		"режим", "выстр.", "пик/0.1с", "в возд.", "физтик мс", "кадр лог.", "кадр ср.", "p95 мс", "худш.", "FPS"])
	for r in reps:
		print("  %-34s %8d %8d %8d %9.2f %9.2f %9.1f %8.1f %7.1f %7.1f%s" % [
			String(r["label"]), int(r["shots"]), int(r["peak_frame"]), int(r["peak_flight"]),
			float(r["tick_ms"]), float(r["vis_ms"]), float(r["frame_mean"]), float(r["frame_p95"]),
			float(r["frame_worst"]), float(r["fps"]), " (headless: FPS не показателен)" if bool(r["headless"]) else ""])
	print("  торчащих стрел на поле: %d (потолок %d)" % [GameManager.stuck_arrow_count(), GameManager.MAX_STUCK_ARROWS])
