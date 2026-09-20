extends Node

## ═══════════════════════════════════════════════════════════════════════════
## qa_arrow_bench — ЦЕНА СНАРЯДОВ: ЗАПУСК, ПОЛЁТ, ПРИЛЁТ, ЗАЛП В ОДИН ТИК
## ═══════════════════════════════════════════════════════════════════════════
## Измеритель без вердиктов («провалов: 0»), BigStand-5 этап 0
## (docs/BIGSTAND_2026-09-17.md, § 5). Живой Main, 510 лучников (17 отрядов
## по 30, залп archer_1d изучен) против 300 бессмертных целей; ИИ молчат, тик
## у целей снят — они стоят и принимают стрелы.
##   A  ЗАЛП ПО РАДАРУ — 12 с штатной стрельбы отрядами (окна залпа);
##   B  ПО ГОТОВНОСТИ — те же 12 с с выключенным режимом залпа;
##   C  ЗАЛП В ОДИН ТИК — все живые лучники стреляют ОДНИМ кадром
##      (_on_attack_fired у каждого), три раза: цена кадра запуска, кадров
##      прилёта (arrow_core по кадрам, прилётов в кадр), GC за окно залпа;
##   D  МИКРО-БЕНЧ spawn_arrow ×500 из тёплого и холодного пула и цена
##      кадра полёта при 500+ стрелах в воздухе.
## В каждой фазе: честный физтик (tick_meter), кадр логики, стена кадра,
## выстрелов / прилётов (макс за кадр), стрел в полёте, торчащих (потолок
## MAX_STUCK_ARROWS считает только негаснущие), пул узлов, GC (КБ/кадр,
## сборки), ветки профиля (arrow_core = полёт ядра + события + core_event —
## удар/втыкание; atk_strike = выстрел лучника целиком) и пиковые кадры.
## Запуск: `godot --headless --path . res://qa_arrow_bench/Test.tscn
##          -- squads=17 men=30 foes=300 sec=12 volleys=3`
## Профиль ВКЛЮЧЁН в фазах A-C намеренно (нужны ветки стрел): физтик здесь
## завышен на цену меток; честный тик — qa_bigstand detail=0.

const _Opt := preload("res://scripts/perf_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const ARCHER := "res://scenes/units/Archer.tscn"
const FOE := "res://scenes/units/GoblinSpearman.tscn"
const IMMORTAL := 1.0e9
## Сколько кадров после залпа в один тик считать прилёты (дуга ~1-2 с)
const VOLLEY_TAIL_FRAMES := 150

var SQUADS := 17
var MEN := 30
var FOES := 300
var SEC := 12.0
var VOLLEYS := 3
var main = null
var _sids: Array = []
var _archers: Array = []
var _foes: Array = []
var _anchor := Vector3.ZERO

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(a).split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"squads": SQUADS = int(kv[1])
			"men": MEN = int(kv[1])
			"foes": FOES = int(kv[1])
			"sec": SEC = float(kv[1])
			"volleys": VOLLEYS = int(kv[1])
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = _g(at)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _alive_archers() -> Array:
	var out: Array = []
	for a in _archers:
		if a != null and is_instance_valid(a) and not (a as Unit).is_dead():
			out.append(a)
	return out

func _nearest_foe(from: Vector3) -> Unit:
	var best: Unit = null
	var bd := INF
	for f in _foes:
		if f == null or not is_instance_valid(f) or (f as Unit).is_dead():
			continue
		var d: float = (f as Unit).global_position.distance_squared_to(from)
		if d < bd:
			bd = d
			best = f
	return best

func _run() -> void:
	seed(7)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	for nm in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var ai = main.get(nm)
		if ai != null and is_instance_valid(ai) and ai is Node:
			(ai as Node).set_process(false)
			(ai as Node).set_physics_process(false)
	await pframes(4)
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	_anchor = Vector3(base.x + 40.0, 0.0, base.z + 40.0)
	main._clear_area_of_resources(_anchor, 90.0)
	main.focus_camera_on(_anchor)
	if main._camera != null:
		main._camera._update_position()
		main._camera.set_process(false)
	GameManager.update_view_point(_anchor, 110.0, 0.5)
	GameManager.pop_limit_enabled = false
	var pf: int = Constants.FACTION_PLAYER
	GameManager.finish_research(pf, _Forge.node_id("archer", "1d"))
	# ── Лучники: блоки 10 колонок по 0.9 м, по 6 блоков в ряд ─────────────
	var blocks_per_row := 6
	for s in range(SQUADS):
		var sid: int = GameManager.new_squad(pf, "archer")
		_sids.append(sid)
		var bx: float = _anchor.x + float(s % blocks_per_row) * 11.0
		var bz: float = _anchor.z + float(s / blocks_per_row) * 5.0
		var slots: Array = []
		for k in range(MEN):
			var u := _spawn(ARCHER, pf, Vector3(bx + float(k % 10) * 0.9, 0.0, bz + float(k / 10) * 0.9))
			u.max_health = IMMORTAL
			u.current_health = IMMORTAL
			GameManager.add_to_squad(sid, u)
			_archers.append(u)
			slots.append(u.global_position)
		GameManager.squad_set_formation(sid, slots, Vector3(0.0, 0.0, -1.0), false)
		if s % 5 == 0:
			await get_tree().physics_frame
	# ── Цели: блок пехоты в 11 м перед первой шеренгой; стоят (тик снят) ───
	var fz: float = _anchor.z - 11.0
	var cols := 40
	for i in range(FOES):
		var f := _spawn(FOE, Constants.FACTION_GOBLIN, Vector3(_anchor.x + float(i % cols) * 1.5, 0.0, fz - float(i / cols) * 1.2))
		f.max_health = IMMORTAL
		f.current_health = IMMORTAL
		f.set_tick(false)
		_foes.append(f)
		if i % 60 == 0:
			await get_tree().physics_frame
	await pframes(60)
	print("  сцена: лучников %d (отрядов %d), целей %d, узлов в дереве %d" % [
		_archers.size(), SQUADS, _foes.size(), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	var r1: Dictionary = await _measure("A. ЗАЛП ПО РАДАРУ (archer_1d включён)", SEC)
	for sid in _sids:
		GameManager.squad_set_ability(int(sid), _Forge.node_id("archer", "1d"), false)
	await pframes(60)
	var r2: Dictionary = await _measure("B. ПО ГОТОВНОСТИ (залп выключен)", SEC)
	_report([r1, r2])
	await _one_tick_volleys()
	await _spawn_bench()
	print("═════ ИТОГ qa_arrow_bench: провалов: 0 (измеритель, вердиктов нет) ═════")
	get_tree().quit()

## ── C. ЗАЛП В ОДИН ТИК: все живые лучники стреляют одним кадром ────────────
func _one_tick_volleys() -> void:
	print("\n═══ C. ЗАЛП В ОДИН ТИК (%d повторов) ═══" % VOLLEYS)
	for v in range(VOLLEYS):
		# Стрелы прежнего залпа долетели и вернулись в пул
		await pframes(120)
		var shooters: Array = _alive_archers()
		var targets: Array = []
		for a in shooters:
			targets.append(_nearest_foe((a as Unit).global_position))
		_Opt.tick_meter = true; _Opt.tick_reset()
		_Opt.vis_meter = true; _Opt.vis_reset()
		_Opt.profile_physics = true; _Opt.prof_reset()
		var fired0: int = GameManager.arrows_fired
		var gc0: int = GameManager.army.gc_allocated()
		var g0_0: int = GameManager.army.gc_count(0)
		var g0_1: int = GameManager.army.gc_count(1)
		# Кадр запуска: все выстрелы подряд ДО физшага, стена меряется вокруг
		# самого цикла (это и есть цена «залпа в один тик» на стороне стрелка)
		var t0: int = Time.get_ticks_usec()
		var n := 0
		for k in range(shooters.size()):
			var a := shooters[k] as Unit
			var t: Unit = targets[k]
			if t == null:
				continue
			a._on_attack_fired(t, a.attack_damage)
			n += 1
		var launch_ms: float = float(Time.get_ticks_usec() - t0) * 0.001
		var gc_launch: float = float(GameManager.army.gc_allocated() - gc0) / 1024.0
		var flights0: int = GameManager.army.arrow_flights()
		# Хвост: прилёты по кадрам
		var prof_prev: Dictionary = _Opt._prof_usec.duplicate()
		var fl_prev: int = flights0
		var land_max := 0
		var land_max_f := 0
		var arrow_max := 0.0
		var arrow_max_f := 0
		var arrow_sum := 0.0
		var land_frames := 0
		var wall_max := 0.0
		var wall_prev: int = Time.get_ticks_usec()
		var tick_prev: int = _Opt._tick_usec
		var tick_max := 0.0
		var landed_total := 0
		for f in range(VOLLEY_TAIL_FRAMES):
			await get_tree().physics_frame
			var now: int = Time.get_ticks_usec()
			var wall: float = float(now - wall_prev) * 0.001
			wall_prev = now
			var t_ms: float = float(_Opt._tick_usec - tick_prev) * 0.001
			tick_prev = _Opt._tick_usec
			var cur: Dictionary = _Opt._prof_usec.duplicate()
			var a_ms: float = float(int(cur.get("arrow_core", 0)) - int(prof_prev.get("arrow_core", 0))) * 0.001
			prof_prev = cur
			var fl_now: int = GameManager.army.arrow_flights()
			var land: int = fl_prev - fl_now
			fl_prev = fl_now
			if land > 0:
				landed_total += land
				land_frames += 1
				arrow_sum += a_ms
				if land > land_max:
					land_max = land
					land_max_f = f
			if a_ms > arrow_max:
				arrow_max = a_ms
				arrow_max_f = f
			if f >= 1:
				wall_max = maxf(wall_max, wall)
				tick_max = maxf(tick_max, t_ms)
		_Opt.profile_physics = false
		print("  залп %d: выстрелов %d за один вызов, цикл запуска %.2f мс (%.1f мкс на выстрел), в полёте после запуска %d, управл. аллокаций за запуск %.0f КБ" % [
			v + 1, n, launch_ms, launch_ms * 1000.0 / float(maxi(n, 1)), flights0, gc_launch])
		print("           прилётов %d за %d кадров (макс %d в кадре %d); arrow_core в кадрах прилёта ср. %.2f мс, худший %.2f (кадр %d) = %.0f мкс на прилёт; худший физтик хвоста %.2f мс, худшая стена %.1f; сборок gen0 %d, gen1 %d" % [
			landed_total, VOLLEY_TAIL_FRAMES, land_max, land_max_f, arrow_sum / float(maxi(land_frames, 1)), arrow_max, arrow_max_f,
			(arrow_sum / float(landed_total) * 1000.0) if landed_total > 0 else 0.0, tick_max, wall_max,
			GameManager.army.gc_count(0) - g0_0, GameManager.army.gc_count(1) - g0_1])

## ── Один замер фазы (A/B) ──────────────────────────────────────────────────
func _measure(label: String, secs: float) -> Dictionary:
	_Opt.tick_meter = true; _Opt.tick_reset()
	_Opt.vis_meter = true; _Opt.vis_reset()
	_Opt.profile_physics = true; _Opt.prof_reset()
	var frames_total: int = int(secs * 60.0)
	var walls := PackedFloat32Array()
	var arrow_ms := PackedFloat32Array()
	var strike_ms := PackedFloat32Array()
	var landed := PackedInt32Array()
	var fired_f := PackedInt32Array()
	var gc_f := PackedFloat32Array()
	var flights_f := PackedInt32Array()
	var wall_prev: int = Time.get_ticks_usec()
	var prof_prev: Dictionary = _Opt._prof_usec.duplicate()
	var fired_prev: int = GameManager.arrows_fired
	var fl_prev: int = GameManager.army.arrow_flights()
	var gc_prev: int = GameManager.army.gc_allocated()
	var gc0: int = GameManager.army.gc_count(0)
	var gc1: int = GameManager.army.gc_count(1)
	var obj0: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var node0: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var tick_prev: int = _Opt._tick_usec
	var vis_prev: int = _Opt._vis_usec
	var spikes: Array = []
	var stuck_max := 0
	var flights_max := 0
	for f in range(frames_total):
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		var wall_ms: float = float(now - wall_prev) * 0.001
		wall_prev = now
		var t_ms: float = float(_Opt._tick_usec - tick_prev) * 0.001
		var v_ms: float = float(_Opt._vis_usec - vis_prev) * 0.001
		tick_prev = _Opt._tick_usec
		vis_prev = _Opt._vis_usec
		var cur: Dictionary = _Opt._prof_usec.duplicate()
		var branches: Array = []
		for kb in cur:
			var d_us: int = int(cur[kb]) - int(prof_prev.get(kb, 0))
			if d_us > 200:
				branches.append([String(kb), float(d_us) * 0.001])
		branches.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
		var a_ms: float = float(int(cur.get("arrow_core", 0)) - int(prof_prev.get("arrow_core", 0))) * 0.001
		var s_ms: float = float(int(cur.get("atk_strike", 0)) - int(prof_prev.get("atk_strike", 0))) * 0.001
		prof_prev = cur
		var fired_now: int = GameManager.arrows_fired
		var fl_now: int = GameManager.army.arrow_flights()
		var fired_d: int = fired_now - fired_prev
		var land_d: int = fl_prev + fired_d - fl_now
		fired_prev = fired_now
		fl_prev = fl_now
		var gc_now: int = GameManager.army.gc_allocated()
		var gc_kb: float = float(gc_now - gc_prev) / 1024.0
		gc_prev = gc_now
		if f >= 5:
			walls.append(wall_ms)
			arrow_ms.append(a_ms)
			strike_ms.append(s_ms)
			landed.append(land_d)
			fired_f.append(fired_d)
			gc_f.append(gc_kb)
			flights_f.append(fl_now)
			spikes.append([wall_ms, t_ms, v_ms, f, branches.slice(0, 6), land_d, fired_d, gc_kb])
		stuck_max = maxi(stuck_max, GameManager.stuck_arrow_count())
		flights_max = maxi(flights_max, fl_now)
	var r := {}
	r["label"] = label
	r["frames"] = frames_total
	r["tick"] = _Opt.tick_ms()
	r["vis"] = _Opt.vis_ms()
	r["wall_avg"] = _avg(walls)
	r["wall_p95"] = _pct(walls, 0.95)
	r["wall_max"] = _max(walls)
	r["arrow_avg"] = _avg(arrow_ms)
	r["arrow_p95"] = _pct(arrow_ms, 0.95)
	r["arrow_max"] = _max(arrow_ms)
	r["strike_avg"] = _avg(strike_ms)
	r["strike_max"] = _max(strike_ms)
	var land_sum := 0
	var land_max := 0
	var fired_sum := 0
	var fired_max := 0
	var land_frames := 0
	var arrow_on_land := 0.0
	for i in range(landed.size()):
		land_sum += landed[i]
		land_max = maxi(land_max, landed[i])
		fired_sum += fired_f[i]
		fired_max = maxi(fired_max, fired_f[i])
		if landed[i] > 0:
			land_frames += 1
			arrow_on_land += arrow_ms[i]
	r["land_sum"] = land_sum
	r["land_max"] = land_max
	r["fired_sum"] = fired_sum
	r["fired_max"] = fired_max
	r["arrow_per_land"] = (arrow_on_land / float(land_sum) * 1000.0) if land_sum > 0 else 0.0
	r["land_frames"] = land_frames
	r["gc_avg"] = _avg(gc_f)
	r["gc_max"] = _max(gc_f)
	r["gc0"] = GameManager.army.gc_count(0) - gc0
	r["gc1"] = GameManager.army.gc_count(1) - gc1
	r["obj_delta"] = int(Performance.get_monitor(Performance.OBJECT_COUNT)) - obj0
	r["node_delta"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - node0
	r["stuck_max"] = stuck_max
	r["flights_max"] = flights_max
	r["flights_avg"] = _avgi(flights_f)
	r["pool"] = GameManager.arrow_pool_size()
	spikes.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	r["spikes"] = spikes.slice(0, 5)
	r["prof"] = _Opt.prof_report()
	_Opt.profile_physics = false
	return r

func _report(rs: Array) -> void:
	for d in rs:
		var fr: float = float(int(d["frames"]))
		print("\n═══ %s ═══" % String(d["label"]))
		print("  физтик %.2f мс (с профилем), кадр логики %.2f мс; стена ср. %.2f / p95 %.1f / худший %.1f мс" % [
			float(d["tick"]), float(d["vis"]), float(d["wall_avg"]), float(d["wall_p95"]), float(d["wall_max"])])
		print("  выстрелов %d (%.0f/с, макс за кадр %d), прилётов %d (макс за кадр %d, кадров с прилётами %d из %d), в полёте ср. %.0f / макс %d, торчащих макс %d, пул узлов %d" % [
			int(d["fired_sum"]), float(int(d["fired_sum"])) / (fr / 60.0), int(d["fired_max"]), int(d["land_sum"]), int(d["land_max"]),
			int(d["land_frames"]), int(fr) - 5, float(d["flights_avg"]), int(d["flights_max"]), int(d["stuck_max"]), int(d["pool"])])
		print("  arrow_core (полёт ядра + события + core_event: удар/втыкание): ср. %.3f мс/кадр, p95 %.2f, худший %.2f; в кадрах с прилётами — %.1f мкс на прилёт" % [
			float(d["arrow_avg"]), float(d["arrow_p95"]), float(d["arrow_max"]), float(d["arrow_per_land"])])
		print("  atk_strike (выстрел лучника: анимация, звук, упреждение, spawn_arrow): ср. %.3f мс/кадр, худший %.2f" % [
			float(d["strike_avg"]), float(d["strike_max"])])
		print("  GC: %.1f КБ/кадр ср., %.1f КБ худший кадр; сборок gen0 %d, gen1 %d; OBJECT_COUNT %+d, узлов %+d" % [
			float(d["gc_avg"]), float(d["gc_max"]), int(d["gc0"]), int(d["gc1"]), int(d["obj_delta"]), int(d["node_delta"])])
		print("  ВЕТКИ (топ-14, мс/кадр):")
		var k := 0
		for row in d["prof"]:
			var name: String = String(row[0])
			if name.begins_with("!"):
				continue
			k += 1
			if k > 14:
				break
			print("    %2d. %-20s %6.3f  (%d вызовов, %.1f мкс каждый, худший %d)" % [
				k, name, float(int(row[1])) / 1000.0 / fr, int(row[2]), float(row[3]), int(row[4])])
		for sp in d["spikes"]:
			var br := ""
			for b in sp[4]:
				br += "%s %.1f; " % [String(b[0]), float(b[1])]
			print("    пик кадр %4d: стена %.1f = физтик %.1f + логика %.1f + прочее %.1f; прилётов %d, выстрелов %d, GC %.0f КБ  [%s]" % [
				int(sp[3]), float(sp[0]), float(sp[1]), float(sp[2]), float(sp[0]) - float(sp[1]) - float(sp[2]), int(sp[5]), int(sp[6]), float(sp[7]), br])

## ── D. Микро-бенч запуска: 500 spawn_arrow подряд, тёплый и холодный пул ──
func _spawn_bench() -> void:
	print("\n═══ D. fire_projectile ×500 (ручка projectile_core = %s) ═══" % str(_Opt.projectile_core))
	var parent: Node = _archers[0].get_parent()
	var from: Vector3 = _anchor + Vector3(0, 1.2, 0)
	var to: Vector3 = _anchor + Vector3(0, 0, -15)
	for rep in range(2):
		await pframes(120)   # прежние стрелы долетели и вернулись в пул
		var pool0: int = GameManager.arrow_pool_size()
		var gc0: int = GameManager.army.gc_allocated()
		var t0: int = Time.get_ticks_usec()
		for i in range(500):
			GameManager.fire_projectile(parent, from, to + Vector3(float(i % 20) * 0.3, 0.0, float(i / 20) * 0.3),
				15.0, 9.0, 0.5, 1.0, _archers[0], Constants.FACTION_PLAYER)
		var dt: int = Time.get_ticks_usec() - t0
		print("  выстрелов ×500 (в пуле узлов было %d): %.2f мс = %.1f мкс на стрелу; управл. аллокаций %.1f КБ" % [
			pool0, float(dt) * 0.001, float(dt) / 500.0, float(GameManager.army.gc_allocated() - gc0) / 1024.0])
		_Opt.profile_physics = true; _Opt.prof_reset()
		await pframes(1)
		var pr: Dictionary = _Opt._prof_usec.duplicate()
		print("  кадр с %d полётами: arrow_core %.3f мс (%.2f мкс на стрелу в воздухе)" % [
			GameManager.army.arrow_flights(), float(int(pr.get("arrow_core", 0))) * 0.001,
			float(int(pr.get("arrow_core", 0))) / float(maxi(GameManager.army.arrow_flights(), 1))])
		_Opt.profile_physics = false
		if rep == 0:
			await pframes(120)
			GameManager.clear_arrow_pool()
			print("  пул очищен → следующий заход рождает узлы заново")

func _avg(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / float(a.size())

func _avgi(a: PackedInt32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())

func _max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m

func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(float(b.size() - 1) * q), 0, b.size() - 1)]
