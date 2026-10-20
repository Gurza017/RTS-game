extends Node

## ═══════════════════════════════════════════════════════════════════════════
## qa_campaign, БЛОК D: ДЛИННАЯ ПАРТИЯ ДО 30+ МИНУТЫ — ОРДА И FPS
## (ТЗ 11.10.2026, часть 2: отчёт «до / после»)
## ═══════════════════════════════════════════════════════════════════════════
## Живая сцена Main со всеми ИИ (красный, орда, пни), игрок пассивен: его
## постройки каждую минуту долечиваются, чтобы партия дожила до замера (набег
## снёс бы крепость, и сцена ушла бы в «Поражение»). Время ускорено ×TICKS_MULT
## до REAL_FROM_MIN, затем REAL_SEC секунд стены — НАСТОЯЩИЙ ×1: по ним считаются
## средний FPS, p99 кадра (min FPS), худший кадр. Раз в игровую минуту — строка:
## гоблины по родам, всего юнитов, тикающих, вызволений (unstuck) за минуту.
## Оконный зонд (FPS честен только в окне):
##   godot --windowed --position -5000,-5000 --path . res://qa_campaign/Long.tscn -- bg=1 [minutes=30]
## Вердикты: D1 партия дожила, D2 зацикленного вызволения нет (ни один
## гоблин не вызволен LOOP_PER_UNIT раз и больше, за последние 10 минут не
## больше UNSTUCK_MAX_10MIN вызволений всех сторон), D3 гоблинов не больше
## потолка орды (goblin_config.HORDE_CAP). Провалы — «НЕ ПРОШЛО» / «провалов:».

const TICKS_MULT := 4
const REAL_SEC := 60.0
const UNSTUCK_MAX_10MIN := 300   # событий ОРДЫ за последние 10 игровых минут
## Зацикленным считается гоблин, вызволенный столько раз и больше за партию
const LOOP_PER_UNIT := 5
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var MINUTES := 30.0
var main = null
var _done := false
var _pass := 0
var _fail := 0
var _last_min := -1
var _unstuck_at_min: Array = []      # Unit.unstuck_total на начало каждой минуты
var _real := false
var _real_t0 := 0
var _frames: PackedFloat32Array = PackedFloat32Array()
var _prev_us := 0
var _gob_peak := 0
var _max_steps := 8

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("minutes="):
			MINUTES = float(s.substr(8))
	call_deferred("_run")
	get_tree().create_timer(5400.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	print("\n═════ ИТОГ qa_campaign/Long: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	_max_steps = Engine.max_physics_steps_per_frame
	_set_speed(TICKS_MULT)
	print("  зонд D: %.0f игровых минут, ускорение ×%d, затем %.0f с стены ×1" % [MINUTES, TICKS_MULT, REAL_SEC])

func _set_speed(k: int) -> void:
	Engine.physics_ticks_per_second = 60 * k
	Engine.max_physics_steps_per_frame = _max_steps * k
	Engine.time_scale = float(k)

func _goblins() -> Dictionary:
	var by: Dictionary = {}
	var n := 0
	var unst := 0
	for u in get_tree().get_nodes_in_group("goblin_units"):
		if not is_instance_valid(u) or not (u is Unit) or (u as Unit).is_dead():
			continue
		n += 1
		var t: String = String((u as Unit).stat_id)
		by[t] = int(by.get(t, 0)) + 1
		unst += (u as Unit).unstuck_count
	return {"n": n, "by": by, "unst_alive": unst}

func _units_total() -> int:
	return GameManager._live_units.size()

func _heal_player() -> void:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b is Building and not (b as Building).is_dead():
			(b as Building).current_health = (b as Building).max_health

func _minute_line(m: int) -> void:
	_unstuck_at_min.append(Unit.unstuck_total)
	var du: int = 0
	if _unstuck_at_min.size() >= 2:
		du = int(_unstuck_at_min[-1]) - int(_unstuck_at_min[-2])
	var g: Dictionary = _goblins()
	_gob_peak = maxi(_gob_peak, int(g["n"]))
	var gai = main.goblin_ai
	var ph: String = String(gai.phase) if gai != null and "phase" in gai else "?"
	var food: float = ResourceManager.get_amount(Constants.FACTION_GOBLIN, Constants.RESOURCE_FOOD)
	print("  [%2d мин] гоблинов %d %s · юнитов %d · тикают %d · unstuck за минуту %d (всего %d) · фаза %s · еда орды %.0f" % [
		m, int(g["n"]), str(g["by"]), _units_total(), GameManager.active_units(), du,
		Unit.unstuck_total, ph, food])
	if gai != null and gai.has_method("assault_gate"):
		print("           вожак: %s · %s" % [str(gai.call("assault_gate")), String(gai.get("last_action"))])

func _process(_delta: float) -> void:
	if main == null or _done:
		return
	var now_us: int = Time.get_ticks_usec()
	if _real:
		if _prev_us > 0:
			_frames.append(float(now_us - _prev_us) / 1000.0)
		_prev_us = now_us
		if float(now_us - _real_t0) / 1.0e6 >= REAL_SEC:
			_report()
		return
	var clock: float = float(main._match_clock)
	var m: int = int(clock / 60.0)
	var ph: int = int(main._phase)
	if ph == main.Phase.VICTORY or ph == main.Phase.DEFEAT:
		verdict("D1 партия дожила до %.0f-й минуты" % MINUTES, false, "конец партии на %.0f с" % clock)
		_finish()
		return
	if m != _last_min:
		_last_min = m
		_heal_player()
		_minute_line(m)
	if clock >= MINUTES * 60.0:
		_set_speed(1)
		_real = true
		_real_t0 = now_us
		_prev_us = 0
		print("  — замер FPS: %.0f с стены в реальном времени —" % REAL_SEC)

func _report() -> void:
	var fr: Array = Array(_frames)
	fr.sort()
	var n: int = fr.size()
	var avg_ms: float = 0.0
	for f in fr:
		avg_ms += float(f)
	avg_ms /= maxf(1.0, float(n))
	var p50: float = float(fr[n / 2]) if n > 0 else 0.0
	var p99: float = float(fr[mini(n - 1, int(n * 0.99))]) if n > 0 else 0.0
	var worst: float = float(fr[n - 1]) if n > 0 else 0.0
	var g: Dictionary = _goblins()
	var last10: int = Unit.unstuck_total - int(_unstuck_at_min[maxi(0, _unstuck_at_min.size() - 11)]) \
		if _unstuck_at_min.size() > 0 else Unit.unstuck_total
	print("\n  ═══ ЗАМЕР НА %.0f-Й МИНУТЕ ═══" % MINUTES)
	print("  кадров %d за %.0f с: средний FPS %.1f (кадр %.2f мс), p50 %.2f мс, p99 %.2f мс → min FPS (p99) %.1f, худший %.1f мс" % [
		n, REAL_SEC, 1000.0 / maxf(0.001, avg_ms), avg_ms, p50, p99, 1000.0 / maxf(0.001, p99), worst])
	print("  гоблинов на карте %d (пик за партию %d) %s, юнитов всего %d" % [int(g["n"]), _gob_peak, str(g["by"]), _units_total()])
	print("  вызволений (unstuck) всего %d, за последние 10 минут %d, событий unstuck в телеметрии %d, отказов от недостижимой цели %d" % [
		Unit.unstuck_total, last10, _tm_unstuck(), Unit.unstuck_giveups])
	# ЗАЦИКЛЕННОЕ вызволение — один и тот же боец раз за разом (охрана на
	# кольце, куда толпа не помещалась, вызволялась каждые ~14 с всю партию).
	# Разовые вызволения на марше у стены леса или у брода — штатная механика
	var loopers := 0
	var max_per: int = 0
	var by_type: Dictionary = {}
	for u in get_tree().get_nodes_in_group("goblin_units"):
		if not is_instance_valid(u) or not (u is Unit) or (u as Unit).is_dead():
			continue
		var uc: int = (u as Unit).unstuck_count
		max_per = maxi(max_per, uc)
		if uc >= LOOP_PER_UNIT:
			loopers += 1
			by_type[String((u as Unit).stat_id)] = int(by_type.get(String((u as Unit).stat_id), 0)) + 1
	print("  бойцов орды с %d+ вызволениями: %d %s, больше всего у одного: %d" % [LOOP_PER_UNIT, loopers, str(by_type), max_per])
	# Разбор событий вызволения: по стороне/роду и по отрядам (кто и где)
	var by_ft: Dictionary = {}
	var by_sid: Dictionary = {}
	for e in GameManager.tm_events:
		var ea: Array = e
		if String(ea[1]) != "unstuck":
			continue
		var d: Dictionary = ea[2]
		var key: String = "%s/%s/%s/st%s/tgt%s" % [str(d.get("fac", "?")), str(d.get("type", "?")),
			str(d.get("why", "?")), str(d.get("st", "?")), str(d.get("tgt", "?"))]
		by_ft[key] = int(by_ft.get(key, 0)) + 1
		var sk: String = "%s:%s" % [str(d.get("sid", 0)), str(d.get("type", "?"))]
		if not by_sid.has(sk):
			by_sid[sk] = [0, d.get("at", [])]
		(by_sid[sk] as Array)[0] = int((by_sid[sk] as Array)[0]) + 1
	print("  вызволения по стороне/роду: %s" % str(by_ft))
	var top: Array = []
	for k in by_sid:
		top.append([int((by_sid[k] as Array)[0]), k, (by_sid[k] as Array)[1]])
	top.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	for i in range(mini(8, top.size())):
		print("     отряд %s: %d раз, последнее у %s" % [top[i][1], int(top[i][0]), str(top[i][2])])
	verdict("D1 партия дожила до %.0f-й минуты" % MINUTES, true)
	# Вызволений ОРДЫ за последние 10 игровых минут — по событиям телеметрии
	var clock_now: float = float(main._match_clock)
	var gob10 := 0
	var gob_all := 0
	for e2 in GameManager.tm_events:
		var ea2: Array = e2
		if String(ea2[1]) != "unstuck" or int((ea2[2] as Dictionary).get("fac", -1)) != Constants.FACTION_GOBLIN:
			continue
		gob_all += 1
		if float(ea2[0]) >= clock_now - 600.0:
			gob10 += 1
	print("  вызволений ОРДЫ: всего %d, за последние 10 игровых минут %d" % [gob_all, gob10])
	verdict("D2 зацикленного вызволения у орды нет (ни у одного гоблина ≥ %d, у орды за 10 мин ≤ %d)" % [LOOP_PER_UNIT, UNSTUCK_MAX_10MIN],
		loopers == 0 and gob10 <= UNSTUCK_MAX_10MIN, "зацикленных %d, у орды за 10 мин %d" % [loopers, gob10])
	var gai = main.goblin_ai
	if gai != null and gai.has_method("assault_gate"):
		print("  вожак: волн %d, вернулось %d, куплено отрядов %d, еды потрачено %.0f, переприказов застрявшим %d, побудок охраны %d" % [
			int(gai.get("waves_launched")), int(gai.get("waves_returned")), int(gai.get("squads_bought")),
			float(gai.get("food_spent")), int(gai.get("stuck_reissues")), int(gai.get("guard_wakes"))])
		print("  сценарии %s, тактики %s" % [str(gai.get("scenario_counts")), str(gai.get("tactic_counts"))])
	var gscr: Script = load("res://scripts/goblin/goblin_config.gd")
	var cmap: Dictionary = gscr.get_script_constant_map()
	if cmap.has("HORDE_CAP"):
		var cap: int = int(cmap["HORDE_CAP"])
		verdict("D3 гоблинов не больше потолка орды %d" % cap, _gob_peak <= cap + 50, "пик %d" % _gob_peak)
	_finish()

func _tm_unstuck() -> int:
	var k := 0
	for e in GameManager.tm_events:
		if String((e as Array)[1]) == "unstuck":
			k += 1
	return k
