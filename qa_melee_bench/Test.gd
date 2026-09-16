extends Node

## ═══════════════════════════════════════════════════════════════════════════
## БЕНЧМАРК ЗАМЕСА — qa_melee_bench (ТЗ 14.09.2026, «Profiling & Performance»)
## ═══════════════════════════════════════════════════════════════════════════
## Быстрый и репрезентативный замер: по ДВА уставных отряда КАЖДОГО рода войск
## (люди — копейщики, лучники, мечники, монахи; орда — гоблины, конница, туши,
## гноллы, два тролля) друг напротив друга в CONTACT_M метрах — «мясо» с
## первых секунд. Три фазы на одной сцене, одни и те же бойцы:
##   IDLE   — стоят в 60 м друг от друга, целей нет;
##   MOVE   — марш навстречу (сближение, без контакта);
##   COMBAT — переставлены в CONTACT_M и брошены в бой.
## В каждой фазе: честный физтик армии (tick_meter), кадр логики (vis_meter),
## стенные интервалы физкадра (худший, p95), мониторы Performance, FPS в
## окне, аллокации C# (GC churn, сборки по поколениям) и рост объектов
## GDScript (OBJECT_COUNT), раскладка по родам войск (class_meter) и ветки
## физтика (profile_physics). Вердиктов нет — это измеритель.
## Запуск: `godot --path . res://qa_melee_bench/Test.tscn -- secs=20 idle=4 move=4`
## FPS честен ТОЛЬКО В ОКНЕ; headless годится для мс и аллокаций.
## Ручки perf_config через `-- knob=name:0/1` (A/B: два прогона подряд).

const _Opt := preload("res://scripts/perf_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Lair := preload("res://scripts/goblin/TrollLair.gd")

var COMBAT_SEC := 20.0
var IDLE_SEC := 4.0
var MOVE_SEC := 4.0
## Потолок кадров. 0 — без потолка (FPS мин/ср честные); 60 — ровно один
## физшаг на кадр, и мониторы TIME_PROCESS / TIME_PHYSICS_PROCESS становятся
## временем ОДНОГО кадра — их сумма и есть «CPU-кадр», который обязан быть
## меньше 16.6 мс (иначе мониторы усредняются по догоняющим шагам)
var CAP_FPS := 0
## Отрядов каждого рода на сторону (2 — по ТЗ; 4-6 — масштаб партии владельца)
var MULT := 2
const CONTACT_M := 12.0
const FAR_M := 60.0
const WARM := 60

var main = null
var _p_sq: Array = []     # [[men, sid], ...]
var _g_sq: Array = []
var _p_all: Array = []
var _g_all: Array = []
var _trolls: Array = []
var _lair = null
var _knobs: Dictionary = {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(a).split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"secs": COMBAT_SEC = float(kv[1])
			"idle": IDLE_SEC = float(kv[1])
			"move": MOVE_SEC = float(kv[1])
			"cap": CAP_FPS = int(kv[1])
			"mult": MULT = maxi(int(kv[1]), 1)
			"knob":
				var nv: PackedStringArray = kv[1].split(":")
				if nv.size() == 2:
					_knobs[nv[0]] = nv[1]
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с")
		get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

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

func _nearest_live(from: Vector3, list: Array) -> Unit:
	var best: Unit = null
	var bd := INF
	for u in list:
		if u == null or not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var d: float = from.distance_to((u as Unit).global_position)
		if d < bd:
			bd = d
			best = u
	return best

## Переставить отряды: люди — в ряд по X на строке z0, орда — на z0 + gap
func _place(z_people: float, z_horde: float) -> void:
	var x := -40.0 * float(MULT) * 0.5
	for sq in _p_sq:
		var men: Array = sq[0]
		var cols: int = int(ceil(sqrt(float(men.size()) * 1.6)))
		for i in range(men.size()):
			var u := men[i] as Unit
			if not is_instance_valid(u) or u.is_dead():
				continue
			var p := Vector3(x + float(i % cols) * 0.7, 0.0, z_people - float(i / cols) * 0.7)
			u.global_position = _g(p)
			u.sync_row()
			u.post_pos = u.global_position
		x += float(cols) * 0.7 + 3.0
	x = -46.0 * float(MULT) * 0.5
	for sq in _g_sq:
		var men: Array = sq[0]
		var cols: int = int(ceil(sqrt(float(men.size()) * 1.6)))
		var gap: float = 0.9 if men.size() > 20 else 1.4
		for i in range(men.size()):
			var u := men[i] as Unit
			if not is_instance_valid(u) or u.is_dead():
				continue
			var p := Vector3(x + float(i % cols) * gap, 0.0, z_horde + float(i / cols) * gap)
			u.global_position = _g(p)
			u.sync_row()
			u.post_pos = u.global_position
		x += float(cols) * gap + 3.0

func _stop_all() -> void:
	for u in _p_all + _g_all:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).command_move((u as Unit).global_position)

func _order_attack(squads: Array, foes: Array) -> void:
	for sq in squads:
		var men: Array = sq[0]
		if men.is_empty():
			continue
		var c: Vector2 = GameManager.squad_centre_xz(int(sq[1]))
		var from := Vector3(c.x, 0.0, c.y) if c.x != INF else (men[0] as Unit).global_position
		var t: Unit = _nearest_live(from, foes)
		if t == null:
			continue
		for u in men:
			if is_instance_valid(u) and not (u as Unit).is_dead():
				(u as Unit).command_attack(t, true, false, false)

func _run() -> void:
	seed(7)
	Engine.max_fps = CAP_FPS
	# V-Sync снимается ВСЕГДА: с ним «прочее» в кадре — это ожидание монитора
	# (75 Гц → 19 мс «прочего» на стоящей сцене), и FPS мин/ср меряет
	# монитор, а не игру. Потолок 60 при этом честный — его держит max_fps
	if not DisplayServer.get_name().begins_with("headless"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# ЛОД спрайтов: в headless точки обзора нет, а без разбора поз замер
	# кадра логики не про партию
	_Opt.sprite_lod = false
	# Ручки perf_config — статические поля: доступ через инстанс скрипта
	var opt_inst = _Opt.new()
	for k in _knobs:
		var v: String = String(_knobs[k])
		var cur: Variant = opt_inst.get(k)
		if cur == null:
			print("  ручки %s в perf_config нет" % k)
			continue
		if cur is bool:
			opt_inst.set(k, v == "1" or v == "true")
		elif cur is int:
			opt_inst.set(k, int(v))
		elif cur is float:
			opt_inst.set(k, float(v))
		else:
			opt_inst.set(k, v)
		print("  ручка %s = %s" % [k, str(opt_inst.get(k))])
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	await pframes(4)
	# Чужих на площадке быть не должно: стартовые рабочие и орда партии — прочь
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	# Площадка — центр карты, сухая (брод); лес вокруг вычищен
	main._clear_area_of_resources(Vector3(0.0, 0.0, 0.0), 90.0)
	var pf: int = Constants.FACTION_PLAYER
	var gf: int = Constants.FACTION_GOBLIN
	GameManager.pop_limit_enabled = false
	GameManager.finish_research(pf, _Forge.node_id("archer", "1d"))
	GameManager.finish_research(pf, _Forge.node_id("spearman", "1d"))
	GameManager.finish_research(pf, _Forge.node_id("monk", "2d"))
	GameManager.finish_research(pf, _Forge.node_id("monk", "3d"))
	# ── ЛЮДИ: по два уставных отряда каждого рода ────────────────────────
	var n_sp: int = _UCfg.squad_size("spearman")
	var n_ar: int = _UCfg.squad_size("archer")
	var n_wr: int = _UCfg.squad_size("warrior")
	for k in range(MULT):
		_p_sq.append(_squad("spearman", pf, Vector3(-30.0 + float(k) * 12.0, 0.0, -30.0), n_sp, 8, 0.7))
	for k in range(MULT):
		_p_sq.append(_squad("warrior", pf, Vector3(-6.0 + float(k) * 12.0, 0.0, -30.0), n_wr, 8, 0.7))
	for k in range(MULT):
		_p_sq.append(_squad("archer", pf, Vector3(18.0 + float(k) * 12.0, 0.0, -30.0), n_ar, 8, 0.8))
	for k in range(MULT):
		var msq: Array = _squad("monk", pf, Vector3(0.0 + float(k) * 4.0, 0.0, -36.0), 1, 1, 1.0)
		_p_sq.append(msq)
		var b: Dictionary = GameManager.squads[int(msq[1])]["bonuses"]
		b["aura_armor"] = 1.0
		b["aura_attack"] = 1.0
		b["aura_rate"] = 0.08
	for sq in _p_sq:
		_p_all.append_array(sq[0])
	# ── ОРДА: по два уставных отряда каждого рода + два тролля ──────────
	var gs: Dictionary = _GobCfg.SQUAD_SIZE
	for k in range(MULT):
		_g_sq.append(_squad("goblin_spearman", gf, Vector3(-40.0 + float(k) * 14.0, 0.0, 30.0), int(gs["goblin_spearman"]), 10, 0.9))
	for k in range(MULT):
		_g_sq.append(_squad("goblin_rider", gf, Vector3(-8.0 + float(k) * 14.0, 0.0, 30.0), int(gs["goblin_rider"]), 8, 1.2))
	for k in range(MULT):
		_g_sq.append(_squad("big_goblin", gf, Vector3(20.0 + float(k) * 10.0, 0.0, 30.0), int(gs["big_goblin"]), 3, 2.4))
	for k in range(MULT):
		_g_sq.append(_squad("gnoll", gf, Vector3(40.0 + float(k) * 10.0, 0.0, 30.0), int(gs["gnoll"]), 4, 0.9))
	_lair = _Lair.new()
	_lair.faction = gf
	main.world_add(_lair)
	_lair.global_position = _g(Vector3(60.0, 0.0, 70.0))
	await pframes(4)
	_trolls = _lair.spawn_guards(MULT)
	# Стражи и стая — при СВОЁМ пне (иначе подхватят логово партии за сотню метров)
	for t in _trolls:
		(t as Node).set("home_pos", Vector3.INF)
	for sq in _g_sq:
		_g_all.append_array(sq[0])
		if String(GameManager.squad_type(int(sq[1]))) == "gnoll":
			for g in sq[0]:
				(g as Node).set("lair", _lair)
				(g as Node).set("home_pos", _lair.global_position)
	_g_all.append_array(_trolls)
	await pframes(6)
	print("  сцена: людей %d (отрядов %d), орды %d (отрядов %d + %d тролля); по два уставных отряда каждого рода" % [
		_alive(_p_all), _p_sq.size(), _alive(_g_all), _g_sq.size(), _trolls.size()])
	var headless: bool = DisplayServer.get_name() == "headless"
	# ── ФАЗА IDLE ───────────────────────────────────────────────────────
	_place(-FAR_M * 0.5, FAR_M * 0.5)
	await pframes(4)
	_stop_all()
	await pframes(WARM)
	var r_idle: Dictionary = await _measure("IDLE (стоят, 60 м)", IDLE_SEC, headless)
	# ── ФАЗА MOVE ───────────────────────────────────────────────────────
	_place(-FAR_M * 0.5, FAR_M * 0.5)
	await pframes(4)
	for u in _p_all:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			var p: Vector3 = (u as Unit).global_position
			(u as Unit).command_move(Vector3(p.x, 0.0, p.z + FAR_M * 0.35), false, Vector3.ZERO, false, true)
	for u in _g_all:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			var p: Vector3 = (u as Unit).global_position
			(u as Unit).command_move(Vector3(p.x, 0.0, p.z - FAR_M * 0.35))
	await pframes(WARM)
	var r_move: Dictionary = await _measure("MOVE (марш навстречу, без контакта)", MOVE_SEC, headless)
	_stop_all()
	# ── ФАЗА COMBAT ─────────────────────────────────────────────────────
	_place(-CONTACT_M * 0.5, CONTACT_M * 0.5)
	await pframes(4)
	for u in _p_sq[0][0]:
		if is_instance_valid(u):
			(u as Unit).set_stance("defense")
	_order_attack(_p_sq, _g_all)
	_order_attack(_g_sq, _p_all)
	for t in _trolls:
		var foe: Unit = _nearest_live((t as Unit).global_position, _p_all)
		if foe != null:
			(t as Unit).command_attack(foe, true, true, false)
	await pframes(WARM)
	var r_cmb: Dictionary = await _measure("COMBAT (замес в %.0f м)" % CONTACT_M, COMBAT_SEC, headless, true)
	_summary([r_idle, r_move, r_cmb], headless)
	get_tree().quit()

## Один замер фазы: секунды по физкадрам. detail — печатать классы и ветки
func _measure(label: String, secs: float, headless: bool, detail: bool = false) -> Dictionary:
	_Opt.tick_meter = true; _Opt.tick_reset()
	_Opt.vis_meter = true; _Opt.vis_reset()
	_Opt.class_meter = detail; _Opt.class_reset()
	_Opt.profile_physics = detail; _Opt.prof_reset()
	var frames_total: int = int(secs * 60.0)
	var fps_min := 1.0e9
	var fps_sum := 0.0
	var fps_n := 0
	var wall_prev: int = Time.get_ticks_usec()
	var walls: PackedFloat32Array = PackedFloat32Array()
	var phys_all: PackedFloat32Array = PackedFloat32Array()
	var proc_all: PackedFloat32Array = PackedFloat32Array()
	var draw_peak := 0
	var gc_alloc0: int = GameManager.army.gc_allocated()
	var gc0: Array = [GameManager.army.gc_count(0), GameManager.army.gc_count(1), GameManager.army.gc_count(2)]
	var obj0: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var mem0: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var alive0: int = _alive(_p_all) + _alive(_g_all)
	# Разбор пиков: для каждого физкадра — сколько ушло на физтик армии и
	# кадры логики (по счётчикам perf_config), остальное — «прочее»
	# (рендер, туман, HUD, аудио, ИИ, движок)
	var spikes: Array = []     # [wall, tick, vis, f, branches]
	var tick_prev: int = _Opt._tick_usec
	var vis_prev: int = _Opt._vis_usec
	var prof_prev: Dictionary = _Opt._prof_usec.duplicate() if detail else {}
	var nav_prev: int = _Opt.nav_usec
	for f in range(frames_total):
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		var wall_ms: float = float(now - wall_prev) * 0.001
		walls.append(wall_ms)
		wall_prev = now
		var t_ms: float = float(_Opt._tick_usec - tick_prev) * 0.001
		var v_ms: float = float(_Opt._vis_usec - vis_prev) * 0.001
		tick_prev = _Opt._tick_usec
		vis_prev = _Opt._vis_usec
		var branches: Array = []
		if detail:
			var nav_d: int = _Opt.nav_usec - nav_prev
			nav_prev = _Opt.nav_usec
			if nav_d > 300:
				branches.append(["nav_route", float(nav_d) * 0.001])
			var cur: Dictionary = _Opt._prof_usec.duplicate()
			for kb in cur:
				var d_us: int = int(cur[kb]) - int(prof_prev.get(kb, 0))
				if d_us > 300:
					branches.append([String(kb), float(d_us) * 0.001])
			branches.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
			prof_prev = cur
		if f >= 5:
			spikes.append([wall_ms, t_ms, v_ms, f, branches.slice(0, 6)])
		phys_all.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		proc_all.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		var fps: float = float(Performance.get_monitor(Performance.TIME_FPS))
		if not headless and fps > 0.0:
			fps_min = minf(fps_min, fps)
			fps_sum += fps
			fps_n += 1
		draw_peak = maxi(draw_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var r := {}
	r["label"] = label
	r["frames"] = frames_total
	r["tick"] = _Opt.tick_ms()
	r["vis"] = _Opt.vis_ms()
	r["fps_min"] = fps_min if fps_n > 0 else 0.0
	r["fps_avg"] = (fps_sum / float(fps_n)) if fps_n > 0 else 0.0
	r["wall_worst"] = _max(walls)
	r["wall_p95"] = _pct(walls, 0.95)
	r["wall_avg"] = _avg(walls)
	r["phys_p95"] = _pct(phys_all, 0.95)
	r["phys_peak"] = _max(phys_all)
	r["proc_p95"] = _pct(proc_all, 0.95)
	var cpu: PackedFloat32Array = PackedFloat32Array()
	for i in range(phys_all.size()):
		cpu.append(phys_all[i] + proc_all[i])
	r["cpu_avg"] = _avg(cpu)
	r["cpu_p95"] = _pct(cpu, 0.95)
	r["draw"] = draw_peak
	r["gc_kb_frame"] = float(GameManager.army.gc_allocated() - gc_alloc0) / 1024.0 / float(frames_total)
	r["gc"] = [GameManager.army.gc_count(0) - int(gc0[0]), GameManager.army.gc_count(1) - int(gc0[1]), GameManager.army.gc_count(2) - int(gc0[2])]
	r["obj_delta"] = int(Performance.get_monitor(Performance.OBJECT_COUNT)) - obj0
	r["mem_delta_kb"] = float(int(Performance.get_monitor(Performance.MEMORY_STATIC)) - mem0) / 1024.0
	r["alive0"] = alive0
	r["alive1"] = _alive(_p_all) + _alive(_g_all)
	spikes.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	r["spikes"] = spikes.slice(0, 5)
	if detail:
		r["classes"] = _Opt.class_report()
		r["prof"] = _Opt.prof_report()
	_Opt.class_meter = false
	_Opt.profile_physics = false
	print("  [%s] физтик армии %.2f мс, кадр логики %.2f мс, интервал физкадра p95 %.1f / худший %.1f мс, живых %d → %d, C# %.1f КБ/кадр, GC %s" % [
		label, r["tick"], r["vis"], r["wall_p95"], r["wall_worst"], alive0, r["alive1"], r["gc_kb_frame"], str(r["gc"])])
	for sp in r["spikes"]:
		var br := ""
		for b in sp[4]:
			br += "%s %.1f; " % [String(b[0]), float(b[1])]
		print("      пик кадр %4d: интервал %.1f мс = физтик %.1f + логика %.1f + прочее %.1f  [%s]" % [
			int(sp[3]), float(sp[0]), float(sp[1]), float(sp[2]), float(sp[0]) - float(sp[1]) - float(sp[2]), br])
	return r

func _max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a: m = maxf(m, v)
	return m
func _avg(a: PackedFloat32Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for v in a: s += v
	return s / float(a.size())
func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty(): return 0.0
	var s: Array = Array(a)
	s.sort()
	return float(s[int(float(s.size() - 1) * q)])

func _class_label(id: String) -> String:
	match id:
		"archer": return "Лучники"
		"spearman": return "Копейщики"
		"warrior": return "Мечники"
		"monk": return "Монахи"
		"goblin_spearman": return "Гоблины-копейщики"
		"goblin_rider": return "Свиноконница"
		"big_goblin": return "Большие гоблины"
		"gnoll": return "Гноллы"
		"troll": return "Тролли"
	return id

func _summary(rs: Array, headless: bool) -> void:
	print("\n📊 **БЕНЧМАРК ЗАМЕСА (qa_melee_bench)** — сцена %s; по два уставных отряда каждого рода войск" % [
		"headless (FPS не показателен)" if headless else "окно"])
	if CAP_FPS > 0:
		print("  потолок %d к/с: TIME_PHYSICS + TIME_PROCESS = CPU-кадр (бюджет 16.6 мс)" % CAP_FPS)
	print("| Фаза | физтик армии | кадр логики | физкадр p95 / худший | TIME_PHYSICS p95 | TIME_PROCESS p95 | CPU-кадр ср / p95 | FPS мин / ср | C# КБ/кадр | GC g0/g1/g2 | Δобъектов | Δпамяти КБ | живых |")
	print("| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	for r in rs:
		var d: Dictionary = r
		print("| %s | %.2f мс | %.2f мс | %.1f / %.1f мс | %.1f мс | %.1f мс | %.1f / %.1f мс | %s | %.1f | %s | %d | %.0f | %d → %d |" % [
			String(d["label"]), float(d["tick"]), float(d["vis"]), float(d["wall_p95"]), float(d["wall_worst"]),
			float(d["phys_p95"]), float(d["proc_p95"]), float(d["cpu_avg"]), float(d["cpu_p95"]),
			("%.0f / %.0f" % [float(d["fps_min"]), float(d["fps_avg"])]) if not headless else "—",
			float(d["gc_kb_frame"]), str(d["gc"]), int(d["obj_delta"]), float(d["mem_delta_kb"]),
			int(d["alive0"]), int(d["alive1"])])
	var cmb: Dictionary = rs[rs.size() - 1]
	var frames_total: int = int(cmb["frames"])
	print("\n📋 **ЗАМЕС — ПО РОДАМ ВОЙСК** (мс кадра на класс, мкс на тик бойца)")
	print("| Род войск | мс/кадр | мкс/тик бойца | худший тик, мкс (состояние) |")
	print("| :--- | ---: | ---: | ---: |")
	for r in cmb.get("classes", []):
		var mx: Array = _Opt.class_max(String(r[0]))
		print("| %s | %.2f | %.1f | %d (%d) |" % [_class_label(String(r[0])), float(r[1]), float(r[2]), int(mx[0]), int(mx[1])])
	print("\n💡 **ЗАМЕС — ВЕТКИ ФИЗТИКА** (доли профиля, только ранжирование — см. docs/PERF_6000.md §6)")
	var k := 0
	for row in cmb.get("prof", []):
		var name: String = String(row[0])
		if name.begins_with("!"):
			continue
		k += 1
		if k > 14:
			break
		print("  %2d. %-24s %6.2f мс/кадр  (%d вызовов, %.1f мкс каждый)" % [
			k, name, float(int(row[1])) / 1000.0 / float(maxi(frames_total, 1)), int(row[2]), float(row[3])])
	# СОБЫТИЙНЫЕ ВЕТКИ — редкие, но дорогие на вызов (событие, не покадровый
	# путь): в топе по сумме их нет, а кадр они рвут. Порог — худший вызов от 1 мс
	print("
⚡ **ЗАМЕС — СОБЫТИЙНЫЕ ВЕТКИ** (худший вызов ≥ 1 мс; это цена события, не кадра)")
	var ev: Array = []
	for row in cmb.get("prof", []):
		if String(row[0]).begins_with("!"):
			continue
		# Порог по ХУДШЕМУ вызову: 1 мс — уже заметная доля кадра
		if int(row[4]) >= 1000 or String(row[0]).begins_with("monk_"):
			ev.append(row)
	ev.sort_custom(func(a, b): return int(a[4]) > int(b[4]))
	for row in ev:
		print("  %-24s худший %6d мкс, %6.0f мкс/вызов × %5d вызовов = %7.2f мс всего" % [
			String(row[0]), int(row[4]), float(row[3]), int(row[2]), float(int(row[1])) / 1000.0])
	print("═════ ИТОГ qa_melee_bench: провалов: 0 (измеритель, вердиктов нет) ═════")
