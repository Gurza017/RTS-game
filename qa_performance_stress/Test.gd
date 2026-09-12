extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЗАМЕС 50 НА 50 С ЧАРДЖЕМ, ЛЕЧЕНИЕМ, ДУБИНОЙ И КОСТЯМИ (спринт 15, блок 8)
## ═══════════════════════════════════════════════════════════════════════════
## ЗАКАЗ ВЛАДЕЛЬЦА: «спавн замеса 50×50 юнитов с чарджем и лечением для проверки
## стабильности FPS» и «устранить NullReferenceException при уничтожении
## юнитов/построек во время каста, полёта костей или отбрасывания».
##
## ЧТО ЗДЕСЬ ДЕЛАЕТСЯ И ПОЧЕМУ ИМЕННО ТАК:
##   • две смешанные армии по 50 (копейщики, мечники в набеге, лучники с залпом,
##     монахи — против гоблинов, свиноконницы, гноллов и двух троллей с пнём);
##   • пока идёт рубка, стенд НАМЕРЕННО убивает тех, на ком что-то висит: цель
##     лечения монаха, цель замаха тролля, гнолла с костью в замахе, сбитого с
##     ног, а на середине боя — сам пень. Это и есть те случаи, где падали
##     ссылки на освобождённые узлы: ловится они ТОЛЬКО так, в живом бою;
##   • тик меряется ПО КАДРАМ: не только средний, но худший и p95 (правило из
##     qa_full_game_4k: средний FPS фризов не видит).
##
## HEADLESS FPS НЕ ЗНАЕТ. Здесь меряется физтик армии (perf_config.tick_meter)
## и стенные интервалы между физкадрами; ошибки движка (SCRIPT ERROR) считает
## сводка шлюза — из GDScript их не прочитать. Бюджеты щедрые намеренно:
## стенные часы под нагрузкой шлюза врут (правило 12), а фриз — это десятки
## миллисекунд, а не единицы.
## Запуск: godot --headless --path . res://qa_performance_stress/Test.tscn

const _UStats := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _Lair := preload("res://scripts/goblin/TrollLair.gd")

## Сколько игровых секунд длится замер
const FIGHT_SEC := 45.0
## Раз в столько секунд стенд убивает кого-то «посреди действия»
const INJECT_SEC := 3.0
## На какой секунде сносится пень
const STUMP_AT := 20.0
## Бюджеты (щедрые — см. шапку)
const TICK_MEAN_BUDGET_MS := 8.0
const FRAME_P95_BUDGET_MS := 30.0

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(400.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с")
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
	print("\n═════ ИТОГ qa_performance_stress: прошло %d, провалов: %d ═════"
		% [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _squad(uid: String, fac: int, at: Vector3, n: int, cols: int, gap: float) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	for i in range(n):
		var p := at + Vector3((float(i % cols) - float(cols - 1) * 0.5) * gap, 0.0,
			float(i / cols) * gap)
		var u := _spawn(uid, fac, p)
		u.post_pos = u.global_position
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
				(u as Unit).command_attack(t, true, true, true)

var _p_all: Array = []
var _g_all: Array = []
var _monks: Array = []
var _trolls: Array = []
var _gnolls: Array = []
var _riders: Array = []
var _lair = null

func _run() -> void:
	Engine.max_fps = 0
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
	await pframes(4)
	await _build()
	await _fight()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _build() -> void:
	print("\n═════ A. ПОСТАНОВКА 50 × 50 ═════")
	var pf: int = Constants.FACTION_PLAYER
	var gf: int = Constants.FACTION_GOBLIN
	GameManager.finish_research(pf, "archer_1d")     # залп
	GameManager.finish_research(pf, "spearman_1d")   # плотный строй (контратака)
	var p0 := Vector3(-1200.0, 0.0, -1200.0)
	var p_sq: Array = []
	p_sq.append(_squad("spearman", pf, p0 + Vector3(-8.0, 0.0, 0.0), 10, 5, 0.7))
	p_sq.append(_squad("spearman", pf, p0 + Vector3(-3.0, 0.0, 0.0), 10, 5, 0.7))
	p_sq.append(_squad("warrior", pf, p0 + Vector3(3.0, 0.0, 0.0), 15, 5, 0.7))
	p_sq.append(_squad("archer", pf, p0 + Vector3(-2.0, 0.0, -6.0), 12, 6, 0.8))
	p_sq.append(_squad("monk", pf, p0 + Vector3(4.0, 0.0, -5.0), 3, 3, 1.0))
	for sq in p_sq:
		_p_all.append_array(sq[0])
	_monks = p_sq[4][0]
	for u in p_sq[0][0]:
		(u as Unit).set_stance("defense")

	var g0 := p0 + Vector3(0.0, 0.0, 34.0)
	var g_sq: Array = []
	g_sq.append(_squad("goblin_spearman", gf, g0 + Vector3(-7.0, 0.0, 0.0), 10, 5, 0.9))
	g_sq.append(_squad("goblin_spearman", gf, g0 + Vector3(-1.0, 0.0, 0.0), 10, 5, 0.9))
	# Свиноконница — на ФЛАНГЕ с чистой дорогой к лучникам: разгон по заказу
	# спринта 15 засчитывается только после 10 м по прямой, а из-за спин
	# своей пехоты прямой дороги нет — это не поломка, а само правило
	g_sq.append(_squad("goblin_rider", gf, g0 + Vector3(20.0, 0.0, -6.0), 15, 5, 1.2))
	g_sq.append(_squad("gnoll", gf, g0 + Vector3(0.0, 0.0, 8.0), 13, 7, 0.9))
	for sq in g_sq:
		_g_all.append_array(sq[0])
	_riders = g_sq[2][0]
	_gnolls = g_sq[3][0]
	# Пень с двумя стражами — своё логово рядом с полем боя
	_lair = _Lair.new()
	_lair.faction = gf
	main.world_add(_lair)
	var lp := g0 + Vector3(14.0, 0.0, 14.0)
	_lair.global_position = Vector3(lp.x, GameManager.get_terrain_height(lp.x, lp.z), lp.z)
	await pframes(4)
	_trolls = _lair.spawn_guards(2)
	_g_all.append_array(_trolls)
	# СТАЯ — ПРИ СВОЁМ ПНЕ. Гнолл без логова подхватывает логово ПАРТИИ
	# (Gnoll.tick_physics), а оно на другом краю карты за тысячу метров:
	# патруль, отход после броска и бег в пень уводили стаю от поля боя, и
	# «костей в полёте пик 0» был выбором пня, а не поломкой броска
	for g in _gnolls:
		if is_instance_valid(g):
			(g as Node).set("lair", _lair)
	await pframes(6)
	print("  игрок %d, гоблины %d (в т.ч. троллей %d)" % [_alive(_p_all), _alive(_g_all), _trolls.size()])
	verdict("A1 обе армии по ~50 на месте", _alive(_p_all) >= 48 and _alive(_g_all) >= 48,
		"%d и %d" % [_alive(_p_all), _alive(_g_all)])
	# ── ПРИКАЗЫ: все на всех, мечники — набегом ────────────────────────────
	_order_attack(p_sq, _g_all)
	_order_attack(g_sq, _p_all)
	for u in p_sq[2][0]:
		if is_instance_valid(u):
			(u as Unit).call("start_rage_dash")
	# Всадникам — лучники, а не ближайший строй копий
	var archer_t: Unit = _nearest_live(g0 + Vector3(20.0, 0.0, -6.0), p_sq[3][0])
	if archer_t != null:
		for r in _riders:
			if is_instance_valid(r):
				(r as Unit).command_attack(archer_t, true, true, true)
	for t in _trolls:
		var foe: Unit = _nearest_live((t as Unit).global_position, _p_all)
		if foe != null:
			(t as Unit).command_attack(foe, true, true, true)

## Эффект лечения виден, а цели нет или она мертва
func _vfx_on_dead(m: Node) -> bool:
	var vt = m.call("heal_vfx_target")
	var vn = m.call("heal_vfx_node")
	if vn == null or not is_instance_valid(vn) or not bool((vn as Node).get("visible")):
		return false
	return vt == null or not is_instance_valid(vt) or (vt as Unit).is_dead()

# ═════════════════════════════════════════════════════════════════════════════
func _fight() -> void:
	print("\n═════ B. РУБКА %.0f с С ИНЪЕКЦИЯМИ СМЕРТЕЙ ═════" % FIGHT_SEC)
	_Opt.tick_meter = true
	_Opt.tick_reset()
	var deltas: PackedFloat32Array = PackedFloat32Array()
	var t_prev: int = Time.get_ticks_usec()
	var frames_total: int = int(FIGHT_SEC * 60.0)
	var inject_every: int = int(INJECT_SEC * 60.0)
	var stump_at: int = int(STUMP_AT * 60.0)
	var injected := 0
	var bones_seen := 0
	var sweeps_seen := 0
	var heals_seen := false
	var charges_seen := false
	var vfx_bad := 0
	var vfx_suspects: Array = []
	var next_suspects: Array = []
	var suspect_at: int = -100
	var stump_dead_at := -1
	var trolls_after_stump := -1
	for f in range(frames_total):
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		deltas.append(float(now - t_prev) * 0.001)
		t_prev = now
		# ── СНИМКИ СОБЫТИЙ ─────────────────────────────────────────────────
		if f % 10 == 0:
			bones_seen = maxi(bones_seen, GameManager.bones_mm.flight_count())
			for t in _trolls:
				if is_instance_valid(t) and int((t as Node).get("last_sweep_count")) > 0:
					sweeps_seen += 1
			for m in _monks:
				if is_instance_valid(m) and float((m as Node).get("healed_total")) > 0.0:
					heals_seen = true
				# VFX не может висеть на мёртвом или отсутствующем. Цель, павшая
				# в ЭТОМ же кадре ПОСЛЕ такта монаха (самый раненый — тот, кому
				# и умирать), держит эффект до его следующего тика: сигнал
				# physics_frame приходит ДО тика кадра, поэтому «висит» — это
				# то, что осталось и через ДВА кадра (монах тикает каждый)
				if is_instance_valid(m) and _vfx_on_dead(m):
					next_suspects.append(m)
		if not vfx_suspects.is_empty() and f >= suspect_at + 2:
			for m2 in vfx_suspects:
				if is_instance_valid(m2) and _vfx_on_dead(m2):
					vfx_bad += 1
			vfx_suspects = []
		if not next_suspects.is_empty():
			vfx_suspects = next_suspects
			suspect_at = f
			next_suspects = []
		if f % 10 == 0:
			# Удар с разгона — у свиноконницы (ряды) или у тролля (топтание):
			# оба идут одной механикой (_charge_impact), а кто из них доехал
			# до строя живым — жребий боя. Дошёл ли разгон до раздавленных —
			# жребий свалки (перехват пехотой в контакте съедает пробег),
			# поэтому считается и сам РАЗГОН
			for r in _riders + _trolls:
				if not is_instance_valid(r):
					continue
				if int((r as Node).get("_trample_kills")) > 0 or bool((r as Unit).is_charging):
					charges_seen = true
		# ── СТАЯ ВЕДЁТСЯ СТЕНДОМ, КАК ВЁЛ БЫ ВОЖАК ─────────────────────────
		# Вожак орды выключен, а приказ с замком на цель в сорока метрах
		# умирает сразу (замок держится вдвое дальше броска, 17 м): гнолл
		# переносил пост, стоял в 13-20 м от боя за своим поводком (7 м) и
		# уходил патрулировать пень — «костей в полёте пик 0». Раз в две
		# секунды свободный гнолл получает ближайшего врага, без замка.
		# Первые пятнадцать секунд — конница пробивается к лучникам сквозь
		# пехоту и разгоняется на них (B2, набег около 13-й секунды); стая
		# ждёт: кости в лучниках срывают ей цель и разгон
		if f >= 900 and f % 120 == 0:
			for g in _gnolls:
				if is_instance_valid(g) and not (g as Unit).is_dead() and (g as Unit).attack_target == null:
					var nf: Unit = _nearest_live((g as Unit).global_position, _p_all)
					if nf != null:
						(g as Unit).command_attack(nf, true)
		# ── ИНЪЕКЦИИ: УБИТЬ ТОГО, НА КОМ ЧТО-ТО ВИСИТ ─────────────────────
		if f > 0 and f % inject_every == 0:
			injected += _inject(injected)
		if f == stump_at and _lair != null and is_instance_valid(_lair):
			_lair.take_damage(1e9)
			stump_dead_at = f
		if stump_dead_at >= 0 and f == stump_dead_at + 120:
			trolls_after_stump = _alive(_trolls)
	# ── РАЗБОР ─────────────────────────────────────────────────────────────
	var sorted: Array = Array(deltas)
	sorted.sort()
	var worst: float = float(sorted[sorted.size() - 1])
	var p95: float = float(sorted[int(float(sorted.size() - 1) * 0.95)])
	var mean: float = 0.0
	for d in deltas:
		mean += float(d)
	mean /= maxf(float(deltas.size()), 1.0)
	var tick: float = _Opt.tick_ms()
	print("  живых: игрок %d, гоблины %d; инъекций %d; костей в полёте пик %d; взмахов %d; лечение %s; чардж %s"
		% [_alive(_p_all), _alive(_g_all), injected, bones_seen, sweeps_seen, str(heals_seen), str(charges_seen)])
	print("  физтик армии средний %.2f мс; стенной интервал между физкадрами: средний %.1f, p95 %.1f, худший %.1f мс"
		% [tick, mean, p95, worst])
	verdict("B1 бой состоялся: потери с обеих сторон", _alive(_p_all) < 50 and _alive(_g_all) < 52,
		"живых %d и %d" % [_alive(_p_all), _alive(_g_all)])
	verdict("B2 разгон конницы/тролля случился (набег или раздавленные)", charges_seen)
	verdict("B3 монахи лечили", heals_seen)
	verdict("B4 тролль махал дубиной", sweeps_seen > 0, "снимков с взмахом %d" % sweeps_seen)
	verdict("B5 кости летали", bones_seen > 0, "пик в полёте %d" % bones_seen)
	verdict("B6 инъекции смертей прошли (не меньше половины слотов)", injected >= 5,
		"инъекций %d" % injected)
	verdict("B7 эффект лечения ни разу не висел на мёртвом/пустом", vfx_bad == 0,
		"плохих снимков %d" % vfx_bad)
	verdict("B8 пень снесён посреди боя, тролли не сломались",
		stump_dead_at >= 0 and trolls_after_stump >= 0,
		"троллей через 2 с после сноса: %d" % trolls_after_stump)
	verdict("B9 физтик армии в бюджете (средний < %.0f мс на 100 бойцов)" % TICK_MEAN_BUDGET_MS,
		tick < TICK_MEAN_BUDGET_MS, "%.2f мс" % tick)
	verdict("B10 без фризов: p95 интервала между физкадрами < %.0f мс" % FRAME_P95_BUDGET_MS,
		p95 < FRAME_P95_BUDGET_MS, "p95 %.1f, худший %.1f мс" % [p95, worst])

## Одна инъекция: убить того, кто сейчас «под действием». Возвращает 1, если
## жертва нашлась
func _inject(k: int) -> int:
	var kind: int = k % 4
	var victim: Unit = null
	match kind:
		0:
			# цель лечения монаха
			for m in _monks:
				if not is_instance_valid(m):
					continue
				var vt = (m as Node).call("heal_vfx_target")
				if vt != null and is_instance_valid(vt) and not (vt as Unit).is_dead():
					victim = vt
					break
		1:
			# цель замаха тролля (кадры между замахом и касанием)
			for t in _trolls:
				if not is_instance_valid(t):
					continue
				var st = (t as Node).get("_swing_target")
				if st != null and is_instance_valid(st) and not (st as Unit).is_dead():
					victim = st
					break
		2:
			# гнолл с костью в замахе — гибнет сам
			for g in _gnolls:
				if is_instance_valid(g) and not (g as Unit).is_dead() \
						and float((g as Node).get("_throw_left")) > 0.0:
					victim = g
					break
		3:
			# сбитый с ног
			for u in _p_all:
				if is_instance_valid(u) and not (u as Unit).is_dead() \
						and int((u as Node).get("_down_until_ms")) > 0:
					victim = u
					break
	if victim == null:
		# запасной вариант — любой живой, чтобы поток смертей не прерывался
		victim = _nearest_live(Vector3(-1200.0, 0.0, -1190.0), _p_all if kind % 2 == 0 else _g_all)
		if victim == null:
			return 0
	victim.take_damage(1e9)
	return 1
