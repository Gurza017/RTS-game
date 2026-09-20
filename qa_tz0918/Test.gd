extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТЗ 18.09.2026, ДЕСЯТЬ БЛОКОВ (headless)
## ═══════════════════════════════════════════════════════════════════════════
##   A VFX монаха гаснет, когда отряд или монах тронулись (п. 1)
##   B монах поднимает павших до полного штата, тело ищется ПО ОТРЯДУ (п. 2)
##   C кольцо пня под основанием, прицел по постройке — середина рисунка,
##     клик по туловищу пехотинца выбирает ЕГО, а не стоящего позади (п. 3)
##   D бег гоблина ×1.3 с целью; веса и радиусы конницы/пехоты; скан всадника
##     предпочитает лучника копейщику в строю (п. 4)
##   E касание по кадру замаха: урон приходит ПОЗЖЕ замаха (п. 4)
##   F замок стрелка живёт до 60 м (п. 5)
##   G тексты: «Кулдаун», «Стена копий» без строк про лучников (п. 6)
##   H панель бараков: ширина Крепости, найма лучников нет (п. 7)
##   I знамя ветеранов на крыше — в центре площадки (п. 7)
##   J обход скал у хода без маршрута (п. 8)
##   K порог овец будит ОБА пня (п. 9)
##   L рудники разведаны с начала партии (п. 10)
## Числа — из конфигов (правило 10), время — физкадрами (правило 11).

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _SheepScript := preload("res://scripts/goblin/Sheep.gd")
const _TowerS := preload("res://scripts/Tower.gd")   # у Tower нет class_name
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_tz0918: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 4) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x - float(i / cols) * 0.8, 0.0,
			at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	for u in men:
		(u as Unit).command_move((u as Unit).global_position, false, Vector3.FORWARD)
	GameManager.squad_close_ranks(sid, true)
	return [sid, men]

func _wound(u: Unit, frac: float) -> void:
	u.current_health = u.max_health * frac
	u._soa_push_stats()

func _kill_all(men: Array) -> void:
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(14.0, 0.0, 0.0), Vector3(-14.0, 0.0, 0.0), Vector3(0.0, 0.0, 8.0), Vector3(30.0, 0.0, 0.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
			if GameManager.is_water(p.x, p.z) or GameManager.is_water(p.x + 30.0, p.z):
				h += 100.0
			# Плато — ровное, но ВЫСОКОЕ: клик по бойцу на плато уводит точку
			# земли на высоту × lean за спину (см. SelectionManager._pick_at)
			if h > 1.0:
				h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _research_res() -> void:
	GameManager.researched.erase(F)
	for cell in ["1a", "1b", "1c", "1d", "2a", "2b", "2c", "2d"]:
		GameManager.finish_research(F, "monk_" + cell)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	GameManager.pop_limit_enabled = false
	await frames(3)
	# L — пока туман ещё включён
	_l_mines()
	# Дикие (тролли, гноллы, охрана) замораживаются — площадки у базы
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction != F:
			(n as Unit).set_tick(false)
	if main.fog != null:
		main.fog.enabled = false
	var base: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 30.0))
	main._clear_area_of_resources(base, 80.0)
	await _a_vfx(base)
	await _b_raise(base + Vector3(-50.0, 0.0, 0.0))
	await _c_pick(base + Vector3(0.0, 0.0, 50.0))
	await _d_aggro(base + Vector3(50.0, 0.0, 50.0))
	await _e_hit_delay(base + Vector3(-50.0, 0.0, 50.0))
	_f_lock()
	_g_texts()
	await _h_barracks(base + Vector3(50.0, 0.0, -50.0))
	await _i_roof_banner(base + Vector3(-50.0, 0.0, -50.0))
	_j_nav()
	await _k_lairs()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. VFX МОНАХА ТОЛЬКО У СТОЯЩИХ
# ═════════════════════════════════════════════════════════════════════════════
func _wait_vfx(monk: Unit, cap: int) -> int:
	for f in range(cap):
		await get_tree().physics_frame
		if monk.call("heal_vfx_target") != null:
			return f
	return -1

func _a_vfx(base: Vector3) -> void:
	print("\n═════ A. VFX ЛЕЧЕНИЯ ГАСНЕТ, КОГДА ОТРЯД ИЛИ МОНАХ ТРОНУЛИСЬ ═════")
	var monk: Unit = _spawn("monk", F, base)
	var sq: Array = _squad("spearman", F, base + Vector3(5.0, 0.0, 0.0), 4)
	await pframes(10)
	for u in sq[1]:
		_wound(u, 0.5)
	monk.call("_monk_wake")
	var got: int = await _wait_vfx(monk, 400)
	verdict("A1 монах лечит стоящий отряд — VFX на цели", got >= 0, "через %d физкадров" % got)
	# Отряд уходит приказом игрока
	for u in sq[1]:
		(u as Unit).command_move(base + Vector3(40.0, 0.0, 0.0), false, Vector3.ZERO, false, true)
	var off := -1
	for f in range(60):
		await get_tree().physics_frame
		if monk.call("heal_vfx_target") == null:
			off = f
			break
	verdict("A2 отряд тронулся — VFX снят в течение секунды", off >= 0 and off <= 40, "через %d физкадров" % off)
	# Возврат, снова лечим, теперь уходит МОНАХ
	for u in sq[1]:
		(u as Unit).command_move((u as Unit).global_position, false, Vector3.FORWARD)
	await pframes(30)
	for u in sq[1]:
		_wound(u, 0.5)
	monk.call("_monk_wake")
	got = await _wait_vfx(monk, 600)
	verdict("A3 отряд встал — VFX вернулся", got >= 0, "через %d" % got)
	monk.command_move(base + Vector3(0.0, 0.0, 30.0), false, Vector3.ZERO, false, true)
	await pframes(3)
	verdict("A4 приказ монаху на движение — VFX снят",
		monk.call("heal_vfx_target") == null and not bool(monk.call("res_aura_visible")))
	# Тик снят (гарнизон) — картинки гаснут тем же вызовом
	monk.command_move(monk.global_position, false, Vector3.FORWARD)
	await pframes(30)
	for u in sq[1]:
		_wound(u, 0.5)
	monk.call("_monk_wake")
	got = await _wait_vfx(monk, 600)
	monk.set_tick(false)
	verdict("A5 set_tick(false) гасит VFX сразу", got >= 0 and monk.call("heal_vfx_target") == null)
	monk.set_tick(true)
	monk.take_damage(1e12)
	_kill_all(sq[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. ВОСКРЕШЕНИЕ ДО ШТАТА, ТЕЛО — ПО ОТРЯДУ
# ═════════════════════════════════════════════════════════════════════════════
func _b_raise(base: Vector3) -> void:
	print("\n═════ B. МОНАХ ПОДНИМАЕТ ПАВШИХ ДО ПОЛНОГО ШТАТА ═════")
	_research_res()
	var monk: Unit = _spawn("monk", F, base)
	verdict("B0 воскрешение изучено", bool(monk.call("can_resurrect")))
	# Отряд-пациент в 12 м, трое павших
	var sq: Array = _squad("spearman", F, base + Vector3(12.0, 0.0, 0.0), 8)
	# Приманка: ДРУГОЙ отряд у самых ног монаха, один павший — прежний поиск
	# «ближайшее тело своей стороны, потом сверка отряда» на нём и ломался
	var decoy: Array = _squad("spearman", F, base + Vector3(2.0, 0.0, 2.5), 4)
	await pframes(20)
	for i in range(3):
		(sq[1][i] as Unit).take_damage(1e12)
	(decoy[1][0] as Unit).take_damage(1e12)
	await pframes(3)
	var c = GameManager.corpses.find_raisable_of_squad(F, int(sq[0]), monk.global_position, 40.0)
	verdict("B1 тело отряда-пациента находится по отряду (мимо приманки)",
		c != null and int(c.squad_id) == int(sq[0]))
	var live: Array = _alive(sq[1])
	monk.call("command_heal", live[0])
	var order_kept := true
	var raised := 0
	var done_f := -1
	for f in range(60 * 90):
		await get_tree().physics_frame
		raised = int(monk.get("resurrected_total"))
		var alive_n: int = _alive(GameManager.squad_members(int(sq[0]))).size()
		if alive_n < 8 and f > 60 and int(monk.get("_order_sid")) != int(sq[0]):
			order_kept = false
		if alive_n >= 8:
			done_f = f
			break
	verdict("B2 отряд укомплектован: все трое павших подняты", done_f >= 0,
		"поднято %d, за %.1f с" % [raised, float(done_f) / 60.0])
	verdict("B3 приказ ПКМ не сбрасывался на откате канала, пока отряд не полон", order_kept)
	verdict("B4 поднято именно 3 (не больше штата)", raised == 3, "%d" % raised)
	monk.take_damage(1e12)
	_kill_all(GameManager.squad_members(int(sq[0])))
	_kill_all(GameManager.squad_members(int(decoy[0])))
	GameManager.researched.erase(F)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. КОЛЬЦА, ПРИЦЕЛ, КЛИК ПО ТУЛОВИЩУ
# ═════════════════════════════════════════════════════════════════════════════
func _c_pick(base: Vector3) -> void:
	print("\n═════ C. КОЛЬЦО ПНЯ, ПРИЦЕЛ ПО БАШНЕ, КЛИК ПО ПЕХОТИНЦУ ═════")
	var lair = GameManager.troll_lair
	if lair != null and is_instance_valid(lair):
		var expect: Vector3 = lair.global_position + Vector3(lair._draw_cx, lair._draw_base_y, 0.0)
		verdict("C1 кольцо пня — ровно под основанием рисунка (сдвига к камере нет)",
			_xz(lair.ring_center(), expect) < 0.05 and _GobCfg.TROLL_LAIR_RING_SHIFT == 0.0,
			"снос %.2f м" % _xz(lair.ring_center(), expect))
	var t: Building = _TowerS.new()
	t.faction = F
	main.world_add(t)
	t.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z)
	await pframes(4)
	var ah: float = float(t.call("aim_height"))
	verdict("C2 прицел стрелка по башне — середина рисунка, не 0.8 м у подножия",
		ah > 1.5 and ah < t._draw_top_y, "%.2f м при верхе %.2f" % [ah, t._draw_top_y])
	t.queue_free()
	# Клик по туловищу: боец A впереди, боец B в 1.6 м позади (дальше от камеры)
	var sm = main.selection_manager
	var cam: Camera3D = sm.camera
	if cam == null:
		verdict("C3 камеры нет — клик не проверить", false)
		return
	main.set_process(false)
	cam.set_process(false)
	cam.call("pan_to", base + Vector3(20.0, 0.0, 0.0))
	if cam.has_method("_update_position"):
		cam.call("_update_position")
	await frames(2)
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Ровная И НИЗКАЯ площадка: на плато точка земли под курсором уезжает
	# за спину бойца на высоту × lean (ловушка _pick_at, спринт 20)
	var pa: Vector3 = _flat_spot(base + Vector3(20.0, 0.0, 0.0))
	cam.call("pan_to", pa)
	if cam.has_method("_update_position"):
		cam.call("_update_position")
	await frames(2)
	fwd = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var a: Unit = _spawn("spearman", F, pa)
	var b: Unit = _spawn("spearman", F, pa + fwd * 1.6)
	await pframes(3)
	var sp: Vector2 = cam.unproject_position(a.global_position + Vector3(0.0, 1.5, 0.0))
	var pick: Dictionary = sm._pick_at(sp, sm.order_pick_mask())
	var who3: String = "A" if pick["target"] == a else ("B" if pick["target"] == b else str(pick["target"]))
	for hh in [0.1, 0.8, 1.2, 1.5, 1.8]:
		var pk: Dictionary = sm._pick_at(cam.unproject_position(a.global_position + Vector3(0.0, hh, 0.0)), sm.order_pick_mask())
		print("    клик на высоте %.1f: %s (земля %s)" % [hh, "A" if pk["target"] == a else ("B" if pk["target"] == b else str(pk["target"])), str(pk["position"])])
	print("    A %s, B %s, fwd %s, cam %s" % [str(a.global_position), str(b.global_position), str(fwd), str(cam.global_position)])
	verdict("C3 клик по туловищу переднего бойца выбирает ЕГО, а не стоящего позади",
		pick["target"] == a, "выбран %s" % who3)
	var sp2: Vector2 = cam.unproject_position(a.global_position + Vector3(0.0, 0.1, 0.0))
	var pick2: Dictionary = sm._pick_at(sp2, sm.order_pick_mask())
	verdict("C4 клик по ногам по-прежнему выбирает бойца", pick2["target"] == a)
	a.take_damage(1e12)
	b.take_damage(1e12)
	main.set_process(true)
	cam.set_process(true)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. БЕГ ГОБЛИНА, ВЕСА КОННИЦЫ, РАДИУСЫ
# ═════════════════════════════════════════════════════════════════════════════
func _d_aggro(base: Vector3) -> void:
	print("\n═════ D. БЕГ ГОБЛИНА, ВЕСА И РАДИУСЫ АГРО ═════")
	var g: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, base)
	var foe: Unit = _spawn("spearman", F, base + Vector3(30.0, 0.0, 0.0))
	foe.set_tick(false)
	await pframes(3)
	var base_speed: float = g.move_speed
	g.command_attack(foe, true)
	await pframes(2)
	verdict("D1 гоблин с целью бежит ×%.1f" % _GobCfg.GOBLIN_RUN_MULT,
		is_equal_approx(g.move_speed, base_speed * _GobCfg.GOBLIN_RUN_MULT),
		"%.2f при базе %.2f" % [g.move_speed, base_speed])
	g.command_move(g.global_position)
	await pframes(2)
	verdict("D2 цель снята — шаг прежний", is_equal_approx(g.move_speed, base_speed))
	var w: Unit = _spawn("warrior", F, base + Vector3(0.0, 0.0, 10.0))
	var s: Unit = _spawn("spearman", F, base + Vector3(0.0, 0.0, 14.0))
	var ar: Unit = _spawn("archer", F, base + Vector3(0.0, 0.0, 18.0))
	var r: Unit = _spawn("goblin_rider", Constants.FACTION_GOBLIN, base + Vector3(20.0, 0.0, 14.0))
	await pframes(3)
	verdict("D3 мечник — авто-агро 5 м, всадник — 20 м",
		is_equal_approx(w.aggro_radius(), 5.0) and is_equal_approx(r.aggro_radius(), 20.0),
		"%.1f / %.1f" % [w.aggro_radius(), r.aggro_radius()])
	s.set_stance("attack")
	var r_att: float = s.aggro_radius()
	s.set_stance("defense")
	verdict("D4 копейщик: в «Защите» 5 м, в «Атаке» прежние %.0f" % Unit.AGGRO_RADIUS,
		is_equal_approx(s.aggro_radius(), 5.0) and is_equal_approx(r_att, Unit.AGGRO_RADIUS))
	verdict("D5 вес для конницы: копейщик в строю < 1 < мечник < лучник",
		s.cav_target_weight() < 1.0 and w.cav_target_weight() > 1.0
		and ar.cav_target_weight() > w.cav_target_weight())
	verdict("D6 всадник читает конный вес (prio 2)", int(r.call("target_prio_mode")) == 2)
	# Скан: копейщик в строю в 6 м, лучник в 12 м — всадник берёт лучника
	r.set_tick(false)
	s.global_position = r.global_position + Vector3(0.0, 0.0, 6.0); s.sync_row()
	ar.global_position = r.global_position + Vector3(0.0, 0.0, 12.0); ar.sync_row()
	w.global_position = r.global_position + Vector3(60.0, 0.0, 0.0); w.sync_row()
	await pframes(3)
	var picked: Node3D = r.call("_hunt_scan", _GobCfg.RIDER_HUNT_RADIUS)
	verdict("D7 скан всадника (30 м) предпочитает лучника в 12 м копейщику в строю в 6 м",
		picked == ar, "выбран %s" % [str(picked)])
	s.set_stance("attack")
	await pframes(2)
	var picked2: Node3D = r.call("_hunt_scan", _GobCfg.RIDER_HUNT_RADIUS)
	verdict("D8 тот же копейщик ВНЕ строя (Атака) — ближайший берётся как прежде",
		picked2 == s, "выбран %s" % [str(picked2)])
	verdict("D9 поводок всадника на охоте — %.0f м" % _GobCfg.RIDER_PURSUIT_LIMIT,
		is_equal_approx(_GobCfg.RIDER_PURSUIT_LIMIT, 40.0))
	for u in [g, foe, w, s, ar, r]:
		(u as Unit).set_tick(true)
		(u as Unit).take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. КАСАНИЕ ПО КАДРУ ЗАМАХА
# ═════════════════════════════════════════════════════════════════════════════
func _e_hit_delay(base: Vector3) -> void:
	print("\n═════ E. УРОН ПРИХОДИТ ПОЗЖЕ ЗАМАХА ═════")
	var a: Unit = _spawn("spearman", F, base)
	var v: Unit = _spawn("spearman", E, base + Vector3(1.2, 0.0, 0.0))
	v.set_tick(false)
	v.max_health = 1e6
	v.current_health = 1e6
	v._soa_push_stats()
	await pframes(3)
	a.command_attack(v, true)
	var swing_f := -1
	var hit_f := -1
	var hp0: float = v.current_health
	for f in range(600):
		await get_tree().physics_frame
		if swing_f < 0 and int(a.get("_strike_count")) > 0:
			swing_f = f
		if hit_f < 0 and v.current_health < hp0 - 0.01:
			hit_f = f
			break
	verdict("E1 удар нанесён", swing_f >= 0 and hit_f >= 0, "замах %d, урон %d" % [swing_f, hit_f])
	verdict("E2 урон списан ПОЗЖЕ кадра замаха (задержка %d мс)" % Unit.MELEE_HIT_DELAY_MS,
		swing_f >= 0 and hit_f > swing_f and hit_f - swing_f <= 30,
		"через %d физкадров" % (hit_f - swing_f))
	verdict("E3 отпущенных касаний ≥ 1, промахов по стоящей цели 0",
		int(a.get("hits_released")) >= 1 and int(a.get("hits_missed")) == 0)
	a.take_damage(1e12)
	v.set_tick(true)
	v.take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# F. ЗАМОК СТРЕЛКА
# ═════════════════════════════════════════════════════════════════════════════
func _f_lock() -> void:
	print("\n═════ F. ЗАМОК ПРИКАЗА У СТРЕЛКА ЖИВЁТ ДАЛЬШЕ ═════")
	var ar: Unit = _spawn("archer", F, Vector3(-900.0, 0.0, -900.0))
	var sp: Unit = _spawn("spearman", F, Vector3(-900.0, 0.0, -890.0))
	verdict("F1 лучник держит замок до %.0f м (≥ 3 дальности)" % ar._lock_sight_range(),
		ar._lock_sight_range() >= maxf(ar.attack_range * 3.0, 60.0) - 0.01)
	verdict("F2 у пехоты замок прежний (2 × агро)",
		is_equal_approx(sp._lock_sight_range(), maxf(sp.attack_range * 2.0, Unit.AGGRO_RADIUS * 2.0)))
	ar.take_damage(1e12)
	sp.take_damage(1e12)

# ═════════════════════════════════════════════════════════════════════════════
# G. ТЕКСТЫ
# ═════════════════════════════════════════════════════════════════════════════
func _g_texts() -> void:
	print("\n═════ G. ТЕКСТЫ ═════")
	var hud = main.hud
	verdict("G1 подпись строки — «Кулдаун»", String(hud.STAT_ROW_LABELS["cooldown"]) == "Кулдаун")
	var node: Dictionary = _Forge.UNITS["spearman"]["1d"]
	var d: String = String(node.get("desc", ""))
	verdict("G2 «Стена копий»: 300%, замедление конницы, без слов о стрелах",
		d.contains("300%") and d.contains("конницы") and not d.to_lower().contains("стрел")
		and not node.has("toggle_lines"), d)
	verdict("G3 строки про залп живут у узла лучника, а не в HUD",
		(_Forge.UNITS["archer"]["1d"] as Dictionary).has("toggle_lines"))
	verdict("G4 таблица статов прозрачна до наведения (прячется модуляцией, не visible)",
		"_stat_hover_portrait" in hud and not bool(hud.call("stat_panel_shown")))

# ═════════════════════════════════════════════════════════════════════════════
# H. ПАНЕЛЬ БАРАКОВ
# ═════════════════════════════════════════════════════════════════════════════
func _buttons(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Button:
			out.append(c)
		if c is Control:
			_buttons(c, out)

func _icons_of(hud) -> Array:
	var all: Array = []
	_buttons(hud.button_container, all)
	var out: Array = []
	for bt in all:
		for ch in (bt as Button).get_children():
			var tr := ch as TextureRect
			if tr != null and tr.texture != null:
				out.append(tr.texture.resource_path.get_file())
	return out

func _h_barracks(base: Vector3) -> void:
	print("\n═════ H. ПАНЕЛЬ БАРАКОВ — РАЗМЕР КРЕПОСТИ ═════")
	var hud = main.hud
	var b: Building = Barracks.new()
	b.faction = F
	main.world_add(b)
	b.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z)
	await pframes(6)
	var sm = main.selection_manager
	sm._clear_selection()
	sm._select(b)
	GameManager.on_selection_changed(sm.selected_units, true)
	await frames(3)
	for _i in range(6):
		b.train_from_config("spearman")
	await pframes(2)
	GameManager.on_selection_changed(sm.selected_units, true)
	await frames(3)
	# Живой такт панели (он и писал текст башни в колонку) — подождём его
	await pframes(40)
	await frames(3)
	var w6: float = hud._bottom_panel.get_combined_minimum_size().x
	verdict("H1 после шести заказов панель бараков не шире панели Крепости",
		w6 <= float(hud.CASTLE_PANEL_W) + 0.5, "содержимое %.0f при %.0f" % [w6, hud.CASTLE_PANEL_W])
	var ar: Array = _squad("archer", F, base + Vector3(0.0, 0.0, 12.0), 30, 6)
	await pframes(4)
	b.garrison_now(int(ar[0]))
	await pframes(4)
	sm._clear_selection()
	sm._select(b)
	GameManager.on_selection_changed(sm.selected_units, true)
	await frames(3)
	var icons: Array = _icons_of(hud)
	var wr: float = hud._bottom_panel.get_combined_minimum_size().x
	verdict("H2 с лучниками на крыше панель по-прежнему не шире Крепости",
		wr <= float(hud.CASTLE_PANEL_W) + 0.5, "содержимое %.0f" % wr)
	verdict("H3 в ряду кнопок бараков нет портрета лучника (найма лучников нет)",
		not icons.has("Archer.png"), str(icons))
	verdict("H4 копейщик и мечник в найме есть", icons.has("Lancer.png") and icons.has("Warrior.png"))
	sm._clear_selection()
	GameManager.on_selection_changed(sm.selected_units, true)
	b.call("release_roof")
	await pframes(10)
	_kill_all(ar[1])
	b.queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# I. ЗНАМЯ НА КРЫШЕ
# ═════════════════════════════════════════════════════════════════════════════
func _i_roof_banner(base: Vector3) -> void:
	print("\n═════ I. ЗНАМЯ ВЕТЕРАНОВ НА КРЫШЕ — В ЦЕНТРЕ ПЛОЩАДКИ ═════")
	var t: Building = _TowerS.new()
	t.faction = F
	main.world_add(t)
	t.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z)
	await pframes(6)
	var ar: Array = _squad("archer", F, base + Vector3(0.0, 0.0, 12.0), 10, 5)
	main.grant_squad_veterancy(int(ar[0]), 2, 0, [])
	GameManager.refresh_squad_banner(int(ar[0]))
	await pframes(4)
	var banner = (GameManager.squads[int(ar[0])] as Dictionary).get("banner")
	verdict("I0 у отряда с рангом есть знамя", banner != null and is_instance_valid(banner))
	t.garrison_now(int(ar[0]))
	await pframes(6)
	await frames(4)
	var roof = t.get("_roof")
	var pp: Vector3 = roof.platform_point()
	var ok := banner != null and is_instance_valid(banner) and (banner as Node3D).visible
	var d: float = _xz((banner as Node3D).global_position, pp) if ok else 99.0
	verdict("I1 знамя видно на крыше и стоит у центра площадки (≤ 0.6 м по XZ)",
		ok and d <= 0.6, "видно=%s, снос %.2f м" % [str(ok), d])
	verdict("I2 знамя поднято на высоту площадки",
		ok and absf((banner as Node3D).global_position.y - pp.y) < 3.0)
	t.call("release_roof")
	await pframes(10)
	_kill_all(ar[1])
	t.queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# J. ОБХОД СКАЛ У ХОДА БЕЗ МАРШРУТА
# ═════════════════════════════════════════════════════════════════════════════
func _j_nav() -> void:
	print("\n═════ J. ОБХОД СКАЛ ДЛЯ ЛЮБОГО ХОДА ═════")
	var pl: Array = main.plateau_list()
	if pl.is_empty() or not GameManager.nav_on():
		verdict("J0 плато и навигация есть", false)
		return
	# Плато под рудником: прямая через него между двумя точками по бокам
	var p: Array = pl[0]
	var cx: float = float(p[0])
	var cz: float = float(p[1])
	var rr: float = float(p[2]) + 6.0
	var a := Vector3(cx - rr, 0.0, cz)
	var b := Vector3(cx + rr, 0.0, cz)
	var blocked: bool = GameManager.nav_blocked(a, b)
	verdict("J1 прямая сквозь плато упирается в обрыв", blocked)
	var w: Unit = _spawn("worker", F, a)
	w.set_tick(false)
	var straight: Vector3 = (b - a).normalized()
	var dir: Vector3 = w.call("_nav_dir", a, b, 1.0, straight)
	verdict("J2 _nav_dir у рабочего даёт направление обхода, а не прямую",
		blocked and dir.dot(straight) < 0.98, "cos %.2f" % dir.dot(straight))
	w.take_damage(1e12)

# ═════════════════════════════════════════════════════════════════════════════
# K. ПОРОГ ОВЕЦ БУДИТ ОБА ПНЯ
# ═════════════════════════════════════════════════════════════════════════════
func _k_lairs() -> void:
	print("\n═════ K. КРИТИЧЕСКАЯ МАССА ОВЕЦ — ОБА ПНЯ ═════")
	var l1: Node = GameManager.lair_for(F)
	var l2: Node = GameManager.lair_for(E)
	if l1 == null or l2 == null:
		verdict("K0 оба пня на карте", false)
		return
	for l in [l1, l2]:
		l.set("aggro_enabled", false)
		for tr in (l.get("trolls") as Array).duplicate():
			if is_instance_valid(tr):
				(tr as Unit).set_tick(true)
				(tr as Unit).take_damage(1e12)
	await pframes(4)
	verdict("K1 троллей в обоих пнях нет", int(l1.call("trolls_alive")) == 0 and int(l2.call("trolls_alive")) == 0)
	var keep := Node3D.new()
	main.world_add(keep)
	var kp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(30.0, 0.0, 0.0)
	keep.global_position = kp
	var flock: Array = []
	for i in range(_GobCfg.TROLL_RAID_SHEEP + 2):
		var s: Node3D = _SheepScript.new()
		main.world_add(s)
		var sp := kp + Vector3(float(i % 8) * 1.2, 0.0, float(i / 8) * 1.2)
		s.global_position = Vector3(sp.x, GameManager.get_terrain_height(sp.x, sp.z), sp.z)
		s.call("bind_to_keep", keep, F)
		flock.append(s)
	await pframes(2)
	verdict("K2 у игрока овец больше порога, у ИИ — нет",
		GameManager.faction_sheep_count(F) > _GobCfg.TROLL_RAID_SHEEP
		and GameManager.faction_sheep_count(E) <= _GobCfg.TROLL_RAID_SHEEP)
	GameManager._sheep_pressure_check()
	await pframes(3)
	# ТЗ 19.09.2026 (блок 3.2): пень за рекой заморожен — его вор копится
	# всухую (virt_trolls) и выйдет с разморозкой; живой пень рождает нодой
	var t1: int = int(l1.call("trolls_alive")) + (int(l1.get("virt_trolls")) if bool(l1.get("frozen")) else 0)
	var t2: int = int(l2.call("trolls_alive")) + (int(l2.get("virt_trolls")) if bool(l2.get("frozen")) else 0)
	verdict("K3 проснулись ОБА пня: тролль-вор вышел (или посчитан всухую у замороженного) и у пня игрока, и у пня ИИ",
		t1 >= 1 and t2 >= 1,
		"пень игрока %d (заморожен=%s), пень ИИ %d (заморожен=%s)" % [t1, str(l1.get("frozen")), t2, str(l2.get("frozen"))])
	for s in flock:
		if is_instance_valid(s):
			s.call("eat")
	keep.queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# L. РУДНИКИ ПОД ПЕЛЕНОЙ НЕВИДИМЫ (ТЗ-C 19.09.2026 — разворот п. 10 ТЗ 18.09)
# ═════════════════════════════════════════════════════════════════════════════
## Было: «все рудники разведаны с начала» (штамп вокруг каждого). Владелец
## развернул: рудник на неразведанной ячейке невидим и проявляется только
## в обзоре. Подробный стенд — qa_mine_fog; здесь стережём разворот
func _l_mines() -> void:
	print("
═════ L. РУДНИКИ ПОД ПЕЛЕНОЙ НЕВИДИМЫ ═════")
	if main.fog != null:
		main.fog.refresh()      # обход видимости построек идёт на такте маски
	var mines: Array = []
	for grp in ["neutral_buildings", "enemy_buildings", "goblin_buildings", "player_buildings"]:
		for b in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(b) and b is Mine and not mines.has(b):
				mines.append(b)
	verdict("L1 рудников на карте не меньше трёх с рождения", mines.size() >= 3, "%d" % mines.size())
	var unseen := 0
	var hidden_unseen := 0
	var shown_seen := 0
	for m in mines:
		var gp: Vector3 = (m as Node3D).global_position
		var seen: bool = main.fog == null or main.fog.is_seen(gp.x, gp.z)
		if not seen:
			unseen += 1
			if not (m as Node3D).visible:
				hidden_unseen += 1
		elif (m as Node3D).visible:
			shown_seen += 1
	verdict("L2 на старте есть рудники вне разведанной земли (штампа «разведано» нет)",
		unseen >= 1 and main.mines_revealed == 0, "неразведанных %d, засветов %d" % [unseen, main.mines_revealed])
	verdict("L3 каждый неразведанный рудник спрятан пеленой", hidden_unseen == unseen,
		"%d из %d" % [hidden_unseen, unseen])
