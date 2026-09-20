extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНДЫ ПАРТИИ — TelemetryLogger (ТЗ 19.09.2026, «Достижение стабильных 60 FPS»)
## ═══════════════════════════════════════════════════════════════════════════
## Лёгкий фоновый модуль: раз в perf_config.telemetry_sec (10 с) снимает
## метрики партии и дописывает их в user://performance_log_<дата>.json.
## Просадка FPS ниже telemetry_spike_fps (30) — мгновенный СРЕЗ: кто на карте
## по родам войск и состояниям, кто просил A* с прошлого среза, состояние
## обоих ИИ, стек тика ядра. Срезы не чаще SPIKE_GAP_SEC.
##
## ЦЕНА: обход реестра бойцов раз в 10 с (4000 бойцов — ~0.3 мс) и запись
## файла целиком (десятки КБ за час). Покадрового пути нет: счётчики
## (nav_routes_built, army_ticks, scan_calls) ведут сами системы, зонд лишь
## берёт разность. В headless FPS движка — частота кадров отрисовки без
## ограничения, срез по нему там не срабатывает; стенды читают last_sample.
##
## ЧТО В СТРОКЕ: t (секунды партии), fps, frame_ms (среднее по окну
## по стенным часам между _process), phys_ms / vis_ms (честные счётчики
## perf_config, если включены), units (живые тикающие), dormant, hidden_slow
## (чужие под пеленой на низкой частоте), corpses, arrows_flying,
## arrows_stuck, nav_per_sec (A* в секунду), nav_blocked_per_sec, scans_per_sec,
## ticks_per_sec (тики бойцов), stuck (MOVING без продвижения), panicking,
## heal_queue (отряды в очереди в замок), squads, gc_kb.

const _Opt := preload("res://scripts/perf_config.gd")
const SPIKE_GAP_SEC := 30.0

var main = null
var last_sample: Dictionary = {}
var samples: Array = []
var spikes: Array = []
var path: String = ""
var _acc: float = 0.0
var _frames: int = 0
var _frame_ms_acc: float = 0.0
var _last_wall_us: int = 0
var _spike_at: float = -1e9
var _prev: Dictionary = {}
var _nav_class_prev: Dictionary = {}
## Прошлые снимки накопителей — разность за образец (ТЗ 19.09.2026, п. 3)
var _tm_prev: Dictionary = {}
var _tm_events_written: int = 0
var enabled: bool = true
var write_file: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var d: Dictionary = Time.get_datetime_dict_from_system()
	path = "user://performance_log_%04d-%02d-%02d_%02d%02d.json" % [
		int(d["year"]), int(d["month"]), int(d["day"]), int(d["hour"]), int(d["minute"])]
	_last_wall_us = Time.get_ticks_usec()
	# Честные счётчики физтика и кадра логики — одна пара get_ticks_usec на
	# кадр (perf_config): без них лог партии 19.09 не разделял физику и
	# логику при кадре 25-34 мс
	_Opt.tick_meter = true
	_Opt.vis_meter = true
	_Opt.tick_reset()
	_Opt.vis_reset()
	_prev = _counters()

func _counters() -> Dictionary:
	return {
		"nav": GameManager.nav_routes_built,
		"nav_blk": GameManager.nav_blocked_calls,
		"scan": _Opt.scan_calls,
		"ticks": GameManager.army_ticks,
		"unit_ticks": GameManager.army.tick_listed() if GameManager.army != null and GameManager.army.has_method("tick_listed") else 0,
		"wall_us": Time.get_ticks_usec(),
	}

func _process(delta: float) -> void:
	if not enabled:
		return
	var now_us: int = Time.get_ticks_usec()
	_frame_ms_acc += float(now_us - _last_wall_us) * 0.001
	_last_wall_us = now_us
	_frames += 1
	_acc += delta
	var fps: float = Engine.get_frames_per_second()
	if fps < _Opt.telemetry_spike_fps and _clock() - _spike_at >= SPIKE_GAP_SEC and _frames > 30:
		_spike_at = _clock()
		spikes.append(_snapshot(fps))
		_flush()
	if _acc >= _Opt.telemetry_sec:
		_sample()

func _clock() -> float:
	if main != null and is_instance_valid(main):
		return float(main.get("_match_clock"))
	return float(Time.get_ticks_msec()) * 0.001

## Юнит «застрял»: хочет идти (MOVING, цель дальше допуска), а не движется
static func unit_stuck(u: Unit) -> bool:
	if u.state != Unit.State.MOVING or not u.tick_on:
		return false
	var p: Vector3 = u.global_position
	var t: Vector3 = u.move_target
	if Vector2(t.x - p.x, t.z - p.z).length() < 2.0:
		return false
	return not u.moved_recently()

func _sample() -> void:
	var cur: Dictionary = _counters()
	var wall: float = maxf(float(int(cur["wall_us"]) - int(_prev["wall_us"])) * 1e-6, 0.001)
	var units := 0
	var stuck := 0
	var panicking := 0
	var moving := 0
	var attacking := 0
	for u in GameManager._live_units:
		if u == null or not is_instance_valid(u):
			continue
		var un := u as Unit
		if un == null or un.is_dead():
			continue
		units += 1
		if un.state == Unit.State.MOVING:
			moving += 1
			if unit_stuck(un):
				stuck += 1
		elif un.state == Unit.State.ATTACKING:
			attacking += 1
		if un.is_panicked():
			panicking += 1
	var hq := 0
	for sid in GameManager.squads:
		if bool((GameManager.squads[sid] as Dictionary).get("heal_queue", false)):
			hq += 1
	var row: Dictionary = {
		"t": snappedf(_clock(), 0.1),
		"fps": snappedf(Engine.get_frames_per_second(), 0.1),
		"frame_ms": snappedf(_frame_ms_acc / maxf(float(_frames), 1.0), 0.01),
		"phys_ms": snappedf(_Opt.tick_ms(), 0.01) if _Opt.tick_meter else -1.0,
		"vis_ms": snappedf(_Opt.vis_ms(), 0.01) if _Opt.vis_meter else -1.0,
		"units": units,
		"moving": moving,
		"attacking": attacking,
		"dormant": GameManager.dormant_units,
		"hidden_slow": GameManager.army.tick_hidden() if GameManager.army != null else 0,
		"corpses": GameManager.corpses.count() if GameManager.corpses != null else 0,
		"arrows_flying": GameManager.army.arrow_flights() if GameManager.army != null and GameManager.army.has_method("arrow_flights") else 0,
		"arrows_stuck": GameManager.stuck_arrow_count(),
		"nav_per_sec": snappedf(float(int(cur["nav"]) - int(_prev["nav"])) / wall, 0.1),
		"nav_blocked_per_sec": snappedf(float(int(cur["nav_blk"]) - int(_prev["nav_blk"])) / wall, 0.1),
		"scans_per_sec": snappedf(float(int(cur["scan"]) - int(_prev["scan"])) / wall, 0.1),
		"ticks_per_sec": snappedf(float(int(cur["ticks"]) - int(_prev["ticks"])) / wall, 0.1),
		"stuck": stuck,
		"panicking": panicking,
		"heal_queue": hq,
		"squads": GameManager.squads.size(),
		"reserve": _sleeper_state(GameManager.main.get("goblin_reserve") if GameManager.main != null else null),
		"guard": _sleeper_state(GameManager.main.get("enemy_guard") if GameManager.main != null else null),
		"gc_kb": snappedf(float(GameManager.army.gc_allocated()) / 1024.0, 0.1) if GameManager.army != null and GameManager.army.has_method("gc_allocated") else -1.0,
		# ── ТЗ 19.09.2026, п. 3: ИИ, экономика, урон, способности ─────────
		"ai": _ai_state(),
		"economy": _economy(),
		"damage_in": _delta_nested(GameManager.tm_damage_in, "dmg_in"),
		"damage_out": _delta_nested(GameManager.tm_damage_out, "dmg_out"),
		"abilities": _delta_flat(GameManager.tm_abilities, "abil"),
	}
	if _Opt.tick_meter:
		_Opt.tick_reset()
	if _Opt.vis_meter:
		_Opt.vis_reset()
	last_sample = row
	samples.append(row)
	_prev = cur
	_acc = 0.0
	_frames = 0
	_frame_ms_acc = 0.0
	_flush()

## Состояние обоих ИИ — в каждом образце, а не только в срезе (аудит
## партий 19.09.2026: фазы орды между срезами не видны, goblin_squads = −1)
func _ai_state() -> Dictionary:
	var ai: Dictionary = {}
	if main == null or not is_instance_valid(main):
		return ai
	var gai = main.get("goblin_ai")
	if gai != null and is_instance_valid(gai):
		ai["goblin_phase"] = String(gai.get("phase"))
		var gs = gai.get("squads")
		ai["goblin_squads"] = (gs as Array).size() if gs is Array else ((gs as Dictionary).size() if gs is Dictionary else -1)
		if gai.has_method("assault_gate"):
			ai["goblin_gate"] = gai.call("assault_gate")
		ai["goblin_clock"] = snappedf(float(gai.get("clock")), 1.0)
	var eai = main.get("enemy_ai")
	if eai != null and is_instance_valid(eai):
		ai["red_retaliation"] = bool(eai.call("retaliation_active")) if eai.has_method("retaliation_active") else false
		var rs = eai.get("squads")
		ai["red_squads"] = (rs as Array).size() if rs is Array else -1
		ai["red_clock"] = snappedf(float(eai.get("clock")), 1.0)
		ai["red_retaliations"] = int(eai.get("retaliations"))
		ai["red_retaliation_refusals"] = int(eai.get("retaliation_refusals"))
	return ai

## Склад, приток и расход за образец — игрок, красный ИИ, орда
func _economy() -> Dictionary:
	var out: Dictionary = {}
	for fac in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY, Constants.FACTION_GOBLIN]:
		var stock: Dictionary = {}
		var per: Variant = ResourceManager.resources.get(fac)
		if per != null:
			for t in (per as Dictionary):
				stock[str(t)] = snappedf(float((per as Dictionary)[t]), 0.1)
		out[str(fac)] = {
			"stock": stock,
			"income": _delta_res(ResourceManager.tm_income, fac, "inc"),
			"spent": _delta_res(ResourceManager.tm_spent, fac, "spent"),
		}
	return out

func _delta_res(src: Dictionary, fac: int, tag: String) -> Dictionary:
	var out: Dictionary = {}
	var per: Variant = src.get(fac)
	if per == null:
		return out
	var key: String = "%s:%d" % [tag, fac]
	var prev: Dictionary = _tm_prev.get(key, {})
	var cur: Dictionary = (per as Dictionary).duplicate()
	for t in cur:
		var d: float = float(cur[t]) - float(prev.get(t, 0.0))
		if d > 0.001:
			out[str(t)] = snappedf(d, 0.1)
	_tm_prev[key] = cur
	return out

## Разность вложенного накопителя (сторона → род → число) за образец
func _delta_nested(src: Dictionary, tag: String) -> Dictionary:
	var out: Dictionary = {}
	for fac in src:
		var per: Dictionary = src[fac]
		var key: String = "%s:%s" % [tag, str(fac)]
		var prev: Dictionary = _tm_prev.get(key, {})
		var cur: Dictionary = per.duplicate()
		var row: Dictionary = {}
		for k in cur:
			var d: float = float(cur[k]) - float(prev.get(k, 0.0))
			if d > 0.001:
				row[String(k)] = snappedf(d, 0.1)
		_tm_prev[key] = cur
		if not row.is_empty():
			out[str(fac)] = row
	return out

## Разность плоского накопителя за образец
func _delta_flat(src: Dictionary, tag: String) -> Dictionary:
	var out: Dictionary = {}
	var prev: Dictionary = _tm_prev.get(tag, {})
	var cur: Dictionary = src.duplicate()
	for k in cur:
		var d: int = int(cur[k]) - int(prev.get(k, 0))
		if d > 0:
			out[String(k)] = d
	_tm_prev[tag] = cur
	return out

## Резерв орды / охрана крепости: сколько отрядов спит, тревога, взаймы
func _sleeper_state(node) -> Dictionary:
	if node == null or not is_instance_valid(node) or not node.has_method("asleep_count"):
		return {}
	var out: Dictionary = {
		"squads": (node.get("squads") as Array).size(),
		"asleep": int(node.call("asleep_count")),
		"alarm": bool(node.get("alarm")),
	}
	var lent = node.get("lent")
	if lent != null:
		out["lent"] = (lent as Dictionary).size()
	return out

## Срез на просадке: кто на карте, кто просит A*, что делают ИИ
func _snapshot(fps: float) -> Dictionary:
	var by_class: Dictionary = {}
	for u in GameManager._live_units:
		if u == null or not is_instance_valid(u):
			continue
		var un := u as Unit
		if un == null or un.is_dead():
			continue
		var k: String = String(un.stat_id)
		var e: Dictionary = by_class.get(k, {"n": 0, "moving": 0, "attacking": 0, "stuck": 0, "panic": 0, "ticking": 0})
		e["n"] = int(e["n"]) + 1
		if un.tick_on:
			e["ticking"] = int(e["ticking"]) + 1
		if un.state == Unit.State.MOVING:
			e["moving"] = int(e["moving"]) + 1
			if unit_stuck(un):
				e["stuck"] = int(e["stuck"]) + 1
		elif un.state == Unit.State.ATTACKING:
			e["attacking"] = int(e["attacking"]) + 1
		if un.is_panicked():
			e["panic"] = int(e["panic"]) + 1
		by_class[k] = e
	var nav_delta: Dictionary = {}
	for k in GameManager.nav_req_class:
		var d: int = int(GameManager.nav_req_class[k]) - int(_nav_class_prev.get(k, 0))
		if d > 0:
			nav_delta[k] = d
	_nav_class_prev = GameManager.nav_req_class.duplicate()
	var ai: Dictionary = {}
	if main != null and is_instance_valid(main):
		ai = _ai_state()
	return {
		"t": snappedf(_clock(), 0.1),
		"fps": snappedf(fps, 0.1),
		"by_class": by_class,
		"nav_requests_since_last": nav_delta,
		"ai": ai,
		"core": {
			"tick_listed": GameManager.army.tick_listed() if GameManager.army.has_method("tick_listed") else -1,
			"tick_skipped": GameManager.army.tick_skipped() if GameManager.army.has_method("tick_skipped") else -1,
			"hidden_slow": GameManager.army.tick_hidden(),
		},
		"nav_worst_usec": GameManager.nav_worst_usec,
	}

func _flush() -> void:
	if not write_file:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"samples": samples, "spikes": spikes,
		"events": GameManager.tm_events}, "", false))
	f.close()

func spike_count() -> int:
	return spikes.size()
