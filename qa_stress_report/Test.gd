extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТРЕСС-ОТЧЁТ — qa_stress_report (Big QA: экономика + замес + монахи)
## ═══════════════════════════════════════════════════════════════════════════
## Одна сцена с максимальной нагрузкой на партийных механиках:
##   • экономика: крепость, две стройплощадки с артелями, лесорубы, загон
##     с овцами и рабочие на разделке;
##   • замес: 100+ солдат игрока (копейщики, мечники, лучники, монахи с аурами
##     и «Благодатью») против 100+ орды (гоблины, свиноконница, гноллы при
##     своём пне, два тролля) в одной точке;
##   • навигация: марш второй волны с глухой стороны плато (обход по спуску).
## Снимает раз в физкадр Performance.get_monitor (TIME_PROCESS,
## TIME_PHYSICS_PROCESS, FPS), честные измерители проекта (tick_meter,
## vis_meter) и раскладку по родам войск (perf_config.class_meter: мс кадра на
## класс и мкс на тик бойца), время навигации (NavPath) и доли веток
## (profile_physics). Пик — кадр с наибольшим физическим временем.
## FPS честен ТОЛЬКО В ОКНЕ: `godot --path . res://qa_stress_report/Test.tscn`.
## Параметры: `-- secs=S` (умолчание 40). Вердиктов нет — это измеритель
## (печатает отчёт по шаблону владельца).

const _Opt := preload("res://scripts/perf_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _Lair := preload("res://scripts/goblin/TrollLair.gd")
const _Sheep := preload("res://scripts/goblin/Sheep.gd")
const _Pen := preload("res://scripts/SheepPen.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")

var MEASURE_SEC := 40.0
## Первые WARM кадров — старт (приказы, маршруты, первый туман), не замес
const WARM := 300
var main = null
var _p_all: Array = []
var _g_all: Array = []
var _workers: Array = []
var _monks: Array = []
var _gnolls: Array = []
var _lair = null
var _castle: Castle = null
var phys_p95: float = 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(a).split("=")
		if kv.size() == 2 and kv[0] == "secs":
			MEASURE_SEC = float(kv[1])
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

func _site(id: String, at: Vector3) -> Building:
	var site: Building = _CSite.new()
	site.faction = Constants.FACTION_PLAYER
	site.target_id = id
	site.target_name = id
	site.build_time = 9999.0
	site.build_size = load("res://scripts/unit_stats_config.gd").building_size(id)
	main.world_add(site)
	site.global_position = _g(at)
	return site

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	# Туман, границы, деревня — как в партии: это стресс партийных механик
	await pframes(4)
	var pf: int = Constants.FACTION_PLAYER
	var gf: int = Constants.FACTION_GOBLIN
	GameManager.finish_research(pf, _Forge.node_id("archer", "1d"))
	GameManager.finish_research(pf, _Forge.node_id("spearman", "1d"))
	GameManager.finish_research(pf, _Forge.node_id("monk", "2d"))
	GameManager.finish_research(pf, _Forge.node_id("monk", "3d"))
	GameManager.pop_limit_enabled = false
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(pf, int(t), 100000.0)
	# ── ЭКОНОМИКА У БАЗЫ ИГРОКА ──────────────────────────────────────────
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	_castle = Castle.new()
	_castle.faction = pf
	main.world_add(_castle)
	_castle.global_position = _g(base)
	await pframes(4)
	var s1: Building = _site("barracks", base + Vector3(18.0, 0.0, 6.0))
	var s2: Building = _site("smithy", base + Vector3(-18.0, 0.0, 8.0))
	var pen: Building = _Pen.new()
	pen.faction = pf
	main.world_add(pen)
	pen.global_position = _g(base + Vector3(0.0, 0.0, 22.0))
	await pframes(3)
	var sheep: Array = []
	for i in range(8):
		var sh: Node3D = _Sheep.new()
		main.world_root().add_child(sh)
		sh.global_position = _g(base + Vector3(float(i % 4) - 1.5, 0.0, 22.0 + float(i / 4)))
		sh.call("bind_to_pen", pen, pf)
		sheep.append(sh)
	for i in range(18):
		_workers.append(_spawn("worker", pf, base + Vector3(float(i % 6) * 1.2 - 3.0, 0.0, 12.0 + float(i / 6) * 1.2)))
	await pframes(3)
	for i in range(18):
		var w: Worker = _workers[i]
		if i < 6:
			w.command_build(s1)
		elif i < 12:
			w.command_build(s2)
		elif i < 15:
			w.command_steal_sheep(sheep[i - 12])
		else:
			w._auto_find_resource(Constants.RESOURCE_WOOD)
	# ── ЗАМЕС: ПОЛЕ В 60 М ОТ БАЗЫ ───────────────────────────────────────
	var p0: Vector3 = base + Vector3(60.0, 0.0, 30.0)
	var p_sq: Array = []
	p_sq.append(_squad("spearman", pf, p0 + Vector3(-9.0, 0.0, 0.0), 20, 10, 0.7))
	p_sq.append(_squad("spearman", pf, p0 + Vector3(-1.0, 0.0, 0.0), 20, 10, 0.7))
	p_sq.append(_squad("warrior", pf, p0 + Vector3(8.0, 0.0, 0.0), 30, 10, 0.7))
	p_sq.append(_squad("archer", pf, p0 + Vector3(-6.0, 0.0, -7.0), 15, 8, 0.8))
	p_sq.append(_squad("archer", pf, p0 + Vector3(4.0, 0.0, -7.0), 15, 8, 0.8))
	for k in range(3):
		var msq: Array = _squad("monk", pf, p0 + Vector3(-4.0 + float(k) * 4.0, 0.0, -4.0), 1, 1, 1.0)
		p_sq.append(msq)
		_monks.append(msq[0][0])
		var b: Dictionary = GameManager.squads[int(msq[1])]["bonuses"]
		b["aura_armor"] = 1.0
		b["aura_attack"] = 1.0
		b["aura_rate"] = 0.08
	for sq in p_sq:
		_p_all.append_array(sq[0])
	for u in p_sq[0][0]:
		(u as Unit).set_stance("defense")
	var g0: Vector3 = p0 + Vector3(0.0, 0.0, 34.0)
	var g_sq: Array = []
	g_sq.append(_squad("goblin_spearman", gf, g0 + Vector3(-9.0, 0.0, 0.0), 25, 10, 0.9))
	g_sq.append(_squad("goblin_spearman", gf, g0 + Vector3(2.0, 0.0, 0.0), 25, 10, 0.9))
	g_sq.append(_squad("goblin_spearman", gf, g0 + Vector3(-4.0, 0.0, 6.0), 20, 10, 0.9))
	g_sq.append(_squad("goblin_rider", gf, g0 + Vector3(22.0, 0.0, -6.0), 20, 5, 1.2))
	g_sq.append(_squad("gnoll", gf, g0 + Vector3(0.0, 0.0, 12.0), 20, 7, 0.9))
	for sq in g_sq:
		_g_all.append_array(sq[0])
	_gnolls = g_sq[4][0]
	_lair = _Lair.new()
	_lair.faction = gf
	main.world_add(_lair)
	_lair.global_position = _g(g0 + Vector3(16.0, 0.0, 16.0))
	await pframes(4)
	var trolls: Array = _lair.spawn_guards(2)
	_g_all.append_array(trolls)
	for g in _gnolls:
		if is_instance_valid(g):
			(g as Node).set("lair", _lair)
	await pframes(6)
	print("  сцена: солдат игрока %d (+ %d рабочих, %d овец), орды %d (в т.ч. троллей %d); экономика: 2 стройки, лесорубы, загон" % [
		_alive(_p_all), _workers.size(), sheep.size(), _alive(_g_all), trolls.size()])
	_order_attack(p_sq, _g_all)
	_order_attack(g_sq, _p_all)
	for t in trolls:
		var foe: Unit = _nearest_live((t as Unit).global_position, _p_all)
		if foe != null:
			(t as Unit).command_attack(foe, true, true, false)
	await _measure()
	get_tree().quit()

func _measure() -> void:
	_Opt.tick_meter = true
	_Opt.tick_reset()
	_Opt.vis_meter = true
	_Opt.vis_reset()
	_Opt.class_meter = true
	_Opt.class_reset()
	_Opt.profile_physics = true
	_Opt.prof_reset()
	var headless: bool = DisplayServer.get_name() == "headless"
	var frames_total: int = int(MEASURE_SEC * 60.0)
	var fps_min := 1.0e9
	var fps_sum := 0.0
	var fps_n := 0
	var phys_peak := 0.0
	var proc_peak := 0.0
	var proc_at_peak := 0.0
	var frame_at_peak := 0.0
	var peak_f := 0
	var alive_at_peak := 0
	var wall_prev: int = Time.get_ticks_usec()
	var worst_wall := 0.0
	var wall_sum := 0.0
	var wall_n := 0
	var draw_peak := 0
	var phys_all: PackedFloat32Array = PackedFloat32Array()
	for f in range(frames_total):
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		var wall_ms: float = float(now - wall_prev) * 0.001
		wall_prev = now
		worst_wall = maxf(worst_wall, wall_ms)
		wall_sum += wall_ms
		wall_n += 1
		var phys_ms: float = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		var proc_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		var fps: float = float(Performance.get_monitor(Performance.TIME_FPS))
		if not headless and fps > 0.0 and f >= WARM:
			fps_min = minf(fps_min, fps)
			fps_sum += fps
			fps_n += 1
		# Первые две секунды — раздача приказов, маршруты, первый пересчёт
		# тумана: это старт, а не замес; пики ищем после него
		if f >= WARM:
			phys_all.append(phys_ms)
		if f >= WARM and phys_ms > phys_peak:
			phys_peak = phys_ms
			proc_at_peak = proc_ms
			frame_at_peak = (1000.0 / fps) if (fps > 0.0 and not headless) else wall_ms
			peak_f = f
			alive_at_peak = _alive(_p_all) + _alive(_g_all)
		if f >= WARM:
			proc_peak = maxf(proc_peak, proc_ms)
			draw_peak = maxi(draw_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		# Стая ведётся стендом, как вёл бы вожак (см. qa_performance_stress)
		if f >= 300 and f % 120 == 0:
			for g in _gnolls:
				if is_instance_valid(g) and not (g as Unit).is_dead() and (g as Unit).attack_target == null:
					var nf: Unit = _nearest_live((g as Unit).global_position, _p_all)
					if nf != null:
						(g as Unit).command_attack(nf, true)
	_Opt.class_meter = false
	_Opt.profile_physics = false
	var sorted: Array = Array(phys_all)
	sorted.sort()
	phys_p95 = float(sorted[int(float(sorted.size() - 1) * 0.95)]) if not sorted.is_empty() else 0.0
	_report(headless, fps_min, fps_sum / maxf(float(fps_n), 1.0), phys_peak, proc_at_peak, frame_at_peak,
		peak_f, alive_at_peak, worst_wall, wall_sum / maxf(float(wall_n), 1.0), frames_total, draw_peak, proc_peak)

func _class_label(id: String) -> String:
	match id:
		"worker": return "Рабочие (Workers)"
		"archer": return "Лучники (Archers)"
		"spearman": return "Копейщики (Spearmen)"
		"warrior": return "Мечники (Warriors)"
		"monk": return "Монахи (Healers)"
		"goblin_spearman": return "Гоблины-копейщики"
		"goblin_rider": return "Свиноконница"
		"gnoll": return "Гноллы"
		"troll": return "Тролли"
	return id

## Главное узкое место класса — по СМЫСЛУ его тика, а число — общая доля
## веток профиля (profile_physics), которая к нему относится
func _class_bottleneck(id: String, prof: Dictionary) -> String:
	var atk: float = float(prof.get("process_attack", 0.0))
	var mv: float = float(prof.get("process_move", 0.0))
	var aggro: float = float(prof.get("check_auto_aggro", 0.0))
	match id:
		"worker": return "стройка/добыча/овцы (Worker.tick: свой шаг мимо пакета, _move_blocked)"
		"archer": return "process_attack %.1f мс: выбор цели, залп (squad_volley_mode), упреждение" % atk
		"monk": return "поиск раненых (query_radius в heal_radius), аура раз в 1 с, VFX"
		"gnoll": return "кайт/фланг (command_move раз в такт) + бросок"
		"troll": return "дуга дубины (query_radius каждый взмах), окружение (_foes_around)"
		_: return "process_attack %.1f / process_move %.1f / auto_aggro %.1f мс: сетка боя, шаг" % [atk, mv, aggro]

func _report(headless: bool, fps_min: float, fps_avg: float, phys_peak: float, proc_at_peak: float,
		frame_at_peak: float, peak_f: int, alive_at_peak: int, worst_wall: float, wall_avg: float,
		frames_total: int, draw_peak: int, proc_peak: float) -> void:
	var tick: float = _Opt.tick_ms()
	var vis: float = _Opt.vis_ms()
	var nav_ms: float = float(_Opt.nav_usec) / 1000.0 / float(maxi(frames_total, 1))
	var prof: Dictionary = {}
	for row in _Opt.prof_report():
		prof[String(row[0])] = float(int(row[1])) / 1000.0 / float(maxi(frames_total, 1))
	var counts: Dictionary = {}
	for u in _p_all + _g_all + _workers:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			var id: String = String((u as Unit).stat_id)
			counts[id] = int(counts.get(id, 0)) + 1
	print("\n📊 **ПИКИ И НАГРУЗКА (STRESS TEST REPORT)**  — сцена %s, %.0f с, живых в пике %d" % [
		"headless (FPS не показателен)" if headless else "окно", MEASURE_SEC, alive_at_peak])
	if headless:
		print("* **Минимальный FPS в замесе:** — (headless; интервал физкадра по стене: худший %.1f мс, средний %.1f)" % [worst_wall, wall_avg])
	else:
		print("* **Минимальный FPS в замесе:** %.0f fps (средний %.0f)" % [fps_min, fps_avg])
	print("* **Время кадра (Total Frame Time):** %.1f ms в пике (Бюджет для 60 FPS: 16.6 ms); худший интервал физкадра %.1f ms" % [frame_at_peak, worst_wall])
	print("* **Physics Process Time:** %.1f ms в пике, p95 %.1f ms (монитор TIME_PHYSICS_PROCESS); честный физтик армии средний %.2f ms (tick_meter)" % [phys_peak, phys_p95, tick])
	print("* **Script Idle Time:** %.1f ms в пике физтика, худший %.1f ms (TIME_PROCESS); кадр логики средний %.2f ms (vis_meter)" % [proc_at_peak, proc_peak, vis])
	print("* **Отрисовка:** до %d вызовов отрисовки в кадре; пик физтика на %.1f-й секунде" % [draw_peak, float(peak_f) / 60.0])
	print("* **Navigation Time:** %.3f ms на кадр (NavPath: %d маршрутов за замер); пакетный шаг ядра — %.2f ms" % [
		nav_ms, _Opt.nav_calls, float(prof.get("batch_move", 0.0))])
	print("\n📋 **ДЕТАЛИЗАЦИЯ ПО ТИПАМ ЮНИТОВ (Ms per Unit / Class)**")
	print("| Тип Юнита / Модуль | Кол-во | Время на 1 юнит (ms) | Суммарно (ms) | Главный Bottleneck |")
	print("| :--- | :--- | :--- | :--- | :--- |")
	var rows: Array = _Opt.class_report()
	for r in rows:
		var id: String = String(r[0])
		var per_frame_ms: float = float(r[1])
		var per_tick_us: float = float(r[2])
		var n: int = int(counts.get(id, 0))
		print("| **%s** | %d шт. | %.3f ms | %.2f ms | %s |" % [
			_class_label(id), n, per_tick_us / 1000.0, per_frame_ms, _class_bottleneck(id, prof)])
	print("\n💡 **ТОП-3 КРИТИЧЕСКИХ УЗКИХ ГОРЛЫШКА (ветки физтика, мс на кадр):**")
	var k := 0
	for row in _Opt.prof_report():
		var name: String = String(row[0])
		if name.begins_with("!"):
			continue
		k += 1
		print("%d. %s — %.2f ms/кадр (%d вызовов, %.1f мкс каждый)" % [
			k, name, float(int(row[1])) / 1000.0 / float(maxi(frames_total, 1)), int(row[2]), float(row[3])])
		if k >= 3:
			break
	print("\n  остальные ветки:")
	var j := 0
	for row in _Opt.prof_report():
		j += 1
		if j <= 3 or j > 16:
			continue
		print("    %-22s %6.2f ms/кадр" % [String(row[0]), float(int(row[1])) / 1000.0 / float(maxi(frames_total, 1))])
	print("═════ ИТОГ qa_stress_report: провалов: 0 (измеритель, вердиктов нет) ═════")
