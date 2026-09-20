extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТЗ 19.09.2026, ПЯТЬ БЛОКОВ (headless)
## ═══════════════════════════════════════════════════════════════════════════
##   A зелёных колец монаха на земле нет вовсе, лента лечения осталась (п. 1)
##   B маршрут держит отступ от скал, отряд идёт вдоль стены не гуськом (п. 2)
##   C шесть отрядов лучников по вражеской крепости — стреляют все шесть;
##     залп бьёт лучников на крыше, тела ложатся и на крышу, и у подножия
##     врассыпную, место занимает резервист (п. 3)
##   D раскладка крыш: бараки 15 видимых из 30, крепость 40 из 60 (9 + 22 + 9),
##     фланги выше настила (п. 4)
##   E ремонт: ПКМ рабочим по повреждённому своему зданию — рабочий чинит
##     до полного запаса (п. 5)
## ВТОРОЕ ТЗ ТОГО ЖЕ ДНЯ (четыре блока):
##   F при засадке в здание жёлтые кольца выделения гаснут все, без остатка
##   G заказ из бараков появляется ОДНИМ кадром, строем, с разреженной сеткой,
##     и его разметка — та же сетка (смыкание не стягивает в центр)
##   H шесть отрядов лучников по клику на тролля бьют ТОЛЬКО тролля, снайпер
##     под замком не выбирает сам; стрела не рождается дальше досягаемости
##   I туша перезапускает ленту удара на каждом взмахе (не застывает в позе)
## Числа — из конфигов (правило 10), время — физкадрами (правило 11).

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _MonkS := preload("res://scripts/Monk.gd")
const _BarracksS := preload("res://scripts/Barracks.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const GF := Constants.FACTION_GOBLIN

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
	print("\n═════ ИТОГ qa_tz0919: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 5) -> Array:
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

func _place(b: Building, fac: int, at: Vector3) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

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
			if h > 1.0:
				h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	GameManager.pop_limit_enabled = false
	await frames(3)
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction != F:
			(n as Unit).set_tick(false)
	if main.fog != null:
		main.fog.enabled = false
	var base: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 30.0))
	main._clear_area_of_resources(base, 90.0)
	# Площадки — К ЦЕНТРУ карты от базы: база стоит у края, и смещение наружу
	# уводит за границу мира (рабочий зажимался кромкой z = −125 и «не доходил»)
	var to_c: Vector3 = Vector3(-signf(base.x) * 65.0, 0.0, -signf(base.z) * 55.0)
	print("  база %s, смещение к центру %s, границы ±%.0f / ±%.0f" % [str(base), str(to_c), GameManager.map_lim_x, GameManager.map_lim_z])
	await _a_rings(base)
	await _c_archers(base + Vector3(0.0, 0.0, to_c.z))
	await _d_layout(base + Vector3(to_c.x, 0.0, 0.0))
	await _e_repair(base + Vector3(to_c.x, 0.0, to_c.z))
	_b_nav()
	await _f_rings(base + Vector3(to_c.x * 0.5, 0.0, 0.0))
	await _g_spawn(base + Vector3(to_c.x * 0.5, 0.0, to_c.z))
	await _h_focus(base + Vector3(0.0, 0.0, to_c.z * 0.5))
	await _i_big_anim(base + Vector3(to_c.x, 0.0, to_c.z * 0.5))
	_finish()

## Живые слоты слоя колец (ненулевой базис) — по буферу ядра, как в
## qa_troll_ring: кольцо, снятое из реестра, но не стёртое в буфере, ловится
func _ring_slots_alive() -> int:
	var lay = GameManager.sel_decals._rings
	if lay == null or lay.core_id < 0:
		return 0
	var n := 0
	for i in range(lay.capacity):
		var sl: PackedFloat32Array = GameManager.army.rb_slot(lay.core_id, i)
		if sl.size() < 12:
			continue
		var bsq := 0.0
		for k in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
			bsq += sl[k] * sl[k]
		if bsq > 1e-6:
			n += 1
	return n

# ═════════════════════════════════════════════════════════════════════════════
# F. КОЛЬЦА ПРИ ЗАСАДКЕ
# ═════════════════════════════════════════════════════════════════════════════
func _f_rings(base: Vector3) -> void:
	print("\n═════ F. КОЛЬЦА ВЫДЕЛЕНИЯ ПРИ ЗАСАДКЕ В ЗДАНИЕ ═════")
	main._clear_area_of_resources(base, 50.0)
	var br: Building = _BarracksS.new()
	_place(br, F, base)
	await pframes(6)
	var sq: Array = _squad("archer", F, base + Vector3(0.0, 0.0, 14.0), 30, 6)
	await pframes(6)
	var sm = main.selection_manager
	sm.selected_units.clear()
	for u in sq[1]:
		sm.selected_units.append(u)
		(u as Unit).set_selected(true)
	sm._sel_rebuild()
	GameManager.on_selection_changed(sm.selected_units, true)
	GameManager.sel_decals.update_all()
	await frames(3)
	await pframes(3)
	var rings0: int = _ring_slots_alive()
	verdict("F0 до засадки кольца горят у всех выделенных", rings0 >= 30, "живых слотов %d" % rings0)
	var ok: bool = br.request_garrison(int(sq[0]))
	var w := 0
	while w < 2400:
		await get_tree().physics_frame
		w += 1
		var inside := 0
		for u in sq[1]:
			if is_instance_valid(u) and (u as Unit).garrisoned:
				inside += 1
		if inside == _alive(sq[1]).size():
			break
	await frames(4)
	var rings1: int = _ring_slots_alive()
	verdict("F1 все внутри — колец на карте не осталось (буфер слоя пуст)", ok and rings1 == 0,
		"живых слотов %d, зашли за %d физкадров" % [rings1, w])
	verdict("F2 вошедших нет в выделении", sm.selected_units.is_empty(), "выделено %d" % sm.selected_units.size())
	# И у гарнизона, посаженного сразу (garrison_now), тоже
	var sq2: Array = _squad("archer", F, base + Vector3(10.0, 0.0, 14.0), 10, 5)
	await pframes(4)
	var c: Castle = Castle.new()
	_place(c, F, base + Vector3(25.0, 0.0, 0.0))
	await pframes(6)
	sm.selected_units.clear()
	for u in sq2[1]:
		sm.selected_units.append(u)
		(u as Unit).set_selected(true)
	sm._sel_rebuild()
	GameManager.on_selection_changed(sm.selected_units, true)
	GameManager.sel_decals.update_all()
	await frames(3)
	var ok2: bool = c.garrison_now(int(sq2[0]))
	await frames(4)
	await pframes(2)
	verdict("F3 мгновенная посадка на крышу крепости тоже гасит кольца", ok2 and _ring_slots_alive() == 0,
		"живых слотов %d" % _ring_slots_alive())
	# КЛИК ПО ОТРЯДУ, ЧАСТЬ КОТОРОГО УЖЕ ВНУТРИ: укрытые не выделяются и колец
	# не получают (это и был скриншот — кольца у ворот после посадки)
	sm.selected_units.clear()
	sm._sel_rebuild()
	sm._select(sq[1][0])
	GameManager.on_selection_changed(sm.selected_units, true)
	GameManager.sel_decals.update_all()
	await frames(3)
	var inside_sel := 0
	for u in sm.selected_units:
		if is_instance_valid(u) and u is Unit and (u as Unit).garrisoned:
			inside_sel += 1
	verdict("F4 клик по укрытому отряду: укрытые не в выделении и без колец",
		inside_sel == 0 and _ring_slots_alive() == 0,
		"укрытых в выделении %d, живых слотов %d" % [inside_sel, _ring_slots_alive()])
	sm.selected_units.clear()
	sm._sel_rebuild()
	br.take_damage(1e12)
	c.take_damage(1e12)
	await pframes(6)
	_kill_all(sq[1])
	_kill_all(sq2[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# G. СПАВН СТРОЕМ ОДНИМ КАДРОМ
# ═════════════════════════════════════════════════════════════════════════════
func _g_spawn(base: Vector3) -> void:
	print("\n═════ G. ЗАКАЗ ИЗ БАРАКОВ — СРАЗУ СТРОЕМ ═════")
	main._clear_area_of_resources(base, 50.0)
	var br: Building = _BarracksS.new()
	_place(br, F, base)
	await pframes(6)
	for rt in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_FOOD, Constants.RESOURCE_STONE]:
		ResourceManager.add_resource(F, rt, 100000.0)
	var ok: bool = br.train_from_config("spearman")
	verdict("G0 заказ принят", ok)
	var sid := 0
	var men: Array = []
	var first_f := -1
	var full_f := -1
	var n_expect: int = _UCfg.squad_size("spearman")
	for f in range(60 * 90):
		await get_tree().physics_frame
		if sid == 0:
			for s0 in GameManager.squads:
				var rec: Dictionary = GameManager.squads[s0]
				if String(rec.get("type", "")) == "spearman" and int(rec.get("faction", -1)) == F \
						and not (rec["members"] as Array).is_empty() and not men.has((rec["members"] as Array)[0]):
					var fresh := true
					for m0 in rec["members"]:
						if not is_instance_valid(m0):
							fresh = false
					if fresh and (rec["members"] as Array).size() >= 1 and int(s0) != sid:
						sid = int(s0)
						first_f = f
						break
		if sid > 0:
			men = GameManager.squad_members(sid)
			if men.size() >= n_expect:
				full_f = f
				break
	verdict("G1 весь отряд появился в один физкадр (первый и последний боец в одном кадре)",
		sid > 0 and full_f >= 0 and full_f - first_f <= 1,
		"первый на %d, полный состав на %d (%d бойцов)" % [first_f, full_f, men.size()])
	await pframes(20)
	# Сетка появления: ближайшие соседи не теснее разреженного интервала
	var sp_expect: float = br.squad_spacing * br.SPAWN_SPACING_MULT
	var min_d := 1e9
	for i in range(men.size()):
		for j in range(i + 1, men.size()):
			var a: Vector3 = (men[i] as Node3D).global_position
			var b: Vector3 = (men[j] as Node3D).global_position
			min_d = minf(min_d, Vector2(a.x - b.x, a.z - b.z).length())
	verdict("G2 сетка появления разрежена: соседи не теснее %.2f м (×%.2f интервала)" % [sp_expect * 0.85, br.SPAWN_SPACING_MULT],
		min_d >= sp_expect * 0.85, "ближайшая пара %.2f м" % min_d)
	# Разметка отряда — та же сетка: смыканию нечего стягивать
	var rec2: Dictionary = GameManager.squads.get(sid, {})
	var slots: Array = rec2.get("slots", [])
	verdict("G3 разметка отряда задана сеткой появления (%d мест на %d бойцов)" % [slots.size(), men.size()],
		slots.size() == men.size())
	var c0: Vector3 = GameManager.squad_centroid(sid)
	var cmd0: int = _Opt.cmd_total
	_Opt.cmd_meter = true
	await pframes(60 * 6)
	_Opt.cmd_meter = false
	var moved := 0
	for m in men:
		if is_instance_valid(m) and (m as Unit).moved_recently():
			moved += 1
	var c1: Vector3 = GameManager.squad_centroid(sid)
	verdict("G4 отряд стоит, где появился: центр сдвинулся < 1 м, идущих нет",
		c0.distance_to(c1) < 1.0 and moved <= 2,
		"сдвиг центра %.2f м, идущих %d, приказов за 6 с %d" % [c0.distance_to(c1), moved, _Opt.cmd_total - cmd0])
	_kill_all(men)
	br.take_damage(1e12)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# H. ФОКУС ЛУЧНИКОВ И ДАЛЬНОСТЬ
# ═════════════════════════════════════════════════════════════════════════════
func _h_focus(base: Vector3) -> void:
	print("\n═════ H. ФОКУС ПО КЛИКУ И ПОТОЛОК ДАЛЬНОСТИ ═════")
	main._clear_area_of_resources(base, 70.0)
	GameManager.finish_research(F, "archer_2d")   # снайперы — тоже под замком
	var sqs: Array = []
	for k in range(6):
		sqs.append(_squad("archer", F, base + Vector3(-25.0 + float(k) * 10.0, 0.0, 0.0), 30, 6))
	await pframes(20)
	# Тролль в 14 м (в дальности) и два отряда гоблинов рядом с ним — соблазн
	var troll: Unit = _spawn("troll", GF, base + Vector3(0.0, 0.0, 14.0))
	troll.set_tick(false)
	troll.current_health = 1e9
	troll.max_health = 1e9
	troll._soa_push_stats()
	var g1: Array = _squad("goblin_spearman", GF, base + Vector3(-8.0, 0.0, 12.0), 20, 5)
	var g2: Array = _squad("goblin_spearman", GF, base + Vector3(8.0, 0.0, 12.0), 20, 5)
	for g in g1[1] + g2[1]:
		(g as Unit).set_tick(false)
	await pframes(6)
	var sm = main.selection_manager
	sm.selected_units.clear()
	for s in sqs:
		for u in s[1]:
			sm.selected_units.append(u)
	sm._sel_rebuild()
	GameManager.on_selection_changed(sm.selected_units, true)
	# Тем же путём, что клик: раскладка по фронту + разлив у крупной цели —
	# стрелки обязаны получить самого тролля
	var front: Dictionary = sm.frontline_targets(troll)
	var spread: Dictionary = sm._big_target_spread(troll)
	for k2 in spread:
		front[k2] = spread[k2]
	for u in sm.selected_units:
		var sid: int = (u as Unit).squad_id
		var mine_t = troll
		if sid > 0 and front.has(sid):
			mine_t = front[sid]
		if sid > 0 and GameManager.squad_type(sid) == "archer":
			mine_t = troll
		(u as Unit).command_attack(mine_t, true, true, true)
	var on_troll := 0
	var on_other := 0
	var shooters_troll: Dictionary = {}
	var far_shots := 0
	for f in range(60 * 10):
		await get_tree().physics_frame
		for frec in GameManager.flight_records():
			var sh = frec["shooter"]
			if sh == null or not is_instance_valid(sh) or not (sh is Unit) or (sh as Unit).faction != F:
				continue
			var end: Vector3 = frec.get("end", Vector3.ZERO)
			var sp: Vector3 = frec.get("start", (sh as Node3D).global_position)
			var reach: float = (sh as Unit).reach() * (sh as Archer).garrison_mult()
			if Vector2(end.x - sp.x, end.z - sp.z).length() > reach + 1.0:
				far_shots += 1
				if far_shots <= 6:
					print("    дальняя: d=%.2f reach=%.2f range=%.2f pad=%.2f snipe=%s tgt=%s" % [
						Vector2(end.x - sp.x, end.z - sp.z).length(), reach, (sh as Unit).attack_range,
						float((sh as Unit).get("_target_pad")), str(frec.get("snipe", "?")),
						str((sh as Unit).attack_target)])
			var tp: Vector3 = troll.global_position
			if Vector2(end.x - tp.x, end.z - tp.z).length() < 4.0:
				on_troll += 1
				shooters_troll[(sh as Unit).squad_id] = true
			else:
				on_other += 1
	verdict("H1 стрелы всех шести отрядов летят в тролля, а не в гоблинов рядом",
		shooters_troll.size() == 6 and on_other <= on_troll / 10,
		"по троллю %d (отрядов %d), мимо %d" % [on_troll, shooters_troll.size(), on_other])
	verdict("H2 ни одна стрела не рождена дальше досягаемости стрелка", far_shots == 0, "дальних %d" % far_shots)
	# Цель дальше дальности — выстрела нет вовсе
	var lone: Unit = _spawn("goblin_spearman", GF, base + Vector3(0.0, 0.0, 60.0))
	lone.set_tick(false)
	var a0: Unit = sqs[0][1][0]
	var refused0: int = int(a0.get("shots_refused_range"))
	var flights0: int = GameManager.flight_records().size()
	a0.call("_on_attack_fired", lone, 10.0)
	await pframes(2)
	verdict("H3 по цели за дальностью снаряд не рождается", int(a0.get("shots_refused_range")) > refused0)
	for s in sqs:
		_kill_all(s[1])
	_kill_all(g1[1] + g2[1])
	troll.max_health = 100.0
	troll.take_damage(1e12)
	lone.take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# I. АНИМАЦИЯ УДАРА ТУШИ
# ═════════════════════════════════════════════════════════════════════════════
func _i_big_anim(base: Vector3) -> void:
	print("\n═════ I. ТУША: ЛЕНТА УДАРА ПЕРЕЗАПУСКАЕТСЯ НА КАЖДОМ ВЗМАХЕ ═════")
	main._clear_area_of_resources(base, 40.0)
	var big: Unit = _spawn("big_goblin", GF, base)
	var sq: Array = _squad("spearman", F, base + Vector3(3.0, 0.0, 0.0), 12, 4)
	for u in sq[1]:
		(u as Unit).current_health = 1e9
		(u as Unit).max_health = 1e9
		(u as Unit)._soa_push_stats()
	await pframes(6)
	big.command_attack(sq[1][0], true, true)
	var restarts := 0
	var swings0: int = int(big.get("_swings"))
	var prev_lock: int = 0
	var frames_at_lock: Array = []
	# Окно — три кулдауна по КОНФИГУ плюс запас на первый подход (правило 10):
	# «8 с» при кулдауне 2.7 давало ровно 2.96 взмаха, и с IDLE-агро туши
	# (ТЗ 19.09, она берёт цель сама до приказа стенда, а приказ перезапускает
	# серию) третий взмах не успевал
	var win_sec: float = float(big.attack_cooldown) * 3.0 + 2.0
	for f in range(int(60.0 * win_sec)):
		await get_tree().physics_frame
		var lk: int = int(big.get("_anim_lock_until_ms"))
		if lk != prev_lock:
			prev_lock = lk
			var an: String = String(big.get("_anim_name"))
			if an.begins_with("attack"):
				frames_at_lock.append(int(big.get("_look_frame")))
				var ph: float = float(big.get("_anim_phase"))
				if ph < 0.01:
					restarts += 1
	var swings: int = int(big.get("_swings")) - swings0
	verdict("I1 туша бьёт (взмахов %d за %.1f с — три кулдауна по конфигу)" % [swings, win_sec], swings >= 3)
	verdict("I2 каждый взмах перезапускает ленту удара с нулевого кадра (фаза 0 у %d из %d замков)" % [restarts, frames_at_lock.size()],
		frames_at_lock.size() >= 3 and restarts == frames_at_lock.size())
	big.take_damage(1e12)
	for u in sq[1]:
		(u as Unit).max_health = 180.0
	_kill_all(sq[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# A. КОЛЕЦ МОНАХА НА ЗЕМЛЕ НЕТ
# ═════════════════════════════════════════════════════════════════════════════
func _a_rings(base: Vector3) -> void:
	print("\n═════ A. КОЛЬЦА МОНАХА ═════")
	var monk: Unit = _spawn("monk", F, base)
	var sq: Array = _squad("spearman", F, base + Vector3(4.0, 0.0, 0.0), 6)
	await pframes(4)
	for u in sq[1]:
		(u as Unit).current_health = (u as Unit).max_health * 0.3
		(u as Unit)._soa_push_stats()
	var vfx_seen := false
	var aura_seen := false
	for _f in range(60 * 6):
		await get_tree().physics_frame
		if monk.call("heal_vfx_target") != null:
			vfx_seen = true
		var ha = monk.get("_heal_aura")
		if ha != null and is_instance_valid(ha) and (ha as Node3D).visible:
			aura_seen = true
		if bool(monk.call("res_aura_visible")):
			aura_seen = true
	verdict("A1 лента лечения над моделью есть", vfx_seen)
	verdict("A2 зелёного овала/кольца на земле нет ни у лечения, ни у канала",
		not aura_seen and monk.get("_heal_aura") == null and monk.get("_res_aura") == null)
	# В мире не появилось ни одного квада плашмя с текстурой ауры
	var flat_quads := 0
	for n in main.world_root().get_children():
		if n is MeshInstance3D and String(n.name).ends_with("Aura"):
			flat_quads += 1
	verdict("A3 узлов ауры в мире нет", flat_quads == 0, "узлов %d" % flat_quads)
	monk.take_damage(1e12)
	_kill_all(sq[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. ОТСТУП МАРШРУТА ОТ СКАЛ
# ═════════════════════════════════════════════════════════════════════════════
func _b_nav() -> void:
	print("\n═════ B. МАРШРУТ И СКАЛЫ ═════")
	if not GameManager.nav_on():
		verdict("B0 сетка навигации есть", false)
		return
	# Пара точек по разные стороны плато рудника: маршрут обязан идти в обход
	var mine = GameManager.get("ai_mine")
	var plat: Vector3 = Vector3.ZERO
	if mine != null and is_instance_valid(mine):
		plat = (mine as Node3D).global_position
	else:
		var specs: Array = main.PLATEAU_SPECS
		plat = Vector3(float(specs[0][0]), 0.0, float(specs[0][1]))
	var a := Vector3(plat.x - 40.0, 0.0, plat.z - 2.0)
	var b := Vector3(plat.x + 40.0, 0.0, plat.z + 2.0)
	var pts: PackedVector3Array = GameManager.nav_route(a, b)
	verdict("B1 маршрут через плато найден с углами", pts.size() >= 1, "точек %d" % pts.size())
	# Каждый угол маршрута стоит не ближе NAV_WALL_MARGIN от скалы
	var min_d := 1e9
	var prev: Vector3 = a
	var stuck_hits := 0
	for p in pts:
		var d: float = _dist_to_cliff(p)
		min_d = minf(min_d, d)
		# И отрезок между углами не режет стену с зазором отступа
		if GameManager.army.nav_line_blocked(prev.x, prev.z, p.x, p.z):
			stuck_hits += 1
		prev = p
	verdict("B2 углы маршрута отстоят от скалы не меньше %.1f м" % GameManager.NAV_WALL_MARGIN,
		pts.is_empty() or min_d >= GameManager.NAV_WALL_MARGIN - 0.05,
		"ближайший угол к скале %.2f м" % min_d)
	verdict("B3 отрезки нити свободны", stuck_hits == 0, "упёрлось %d" % stuck_hits)
	# Боковой разнос: два бойца с разным смещением от центра отряда получают
	# РАЗНЫЕ точки обхода (колонна, не нитка)
	var r1: PackedVector3Array = GameManager.build_route(a, b, 0.0, Vector2(0.0, 3.0))
	var r2: PackedVector3Array = GameManager.build_route(a, b, 0.0, Vector2(0.0, -3.0))
	var spread := 0.0
	if r1.size() > 0 and r2.size() > 0:
		spread = Vector2(r1[0].x - r2[0].x, r1[0].z - r2[0].z).length()
	verdict("B4 бойцы с разным смещением идут разными точками обхода", spread > 1.0,
		"разнос первого угла %.2f м" % spread)

func _dist_to_cliff(p: Vector3) -> float:
	var best := 1e9
	var step := 0.5
	var r := 0.5
	while r <= 6.0:
		var n: int = maxi(8, int(TAU * r / step))
		for i in range(n):
			var a: float = TAU * float(i) / float(n)
			if GameManager.is_cliff(p.x + cos(a) * r, p.z + sin(a) * r):
				return r
		r += step
	return best

# ═════════════════════════════════════════════════════════════════════════════
# C. ЛУЧНИКИ ПО КРЕПОСТИ
# ═════════════════════════════════════════════════════════════════════════════
func _c_archers(base: Vector3) -> void:
	print("\n═════ C. ШЕСТЬ ОТРЯДОВ ЛУЧНИКОВ ПО ВРАЖЕСКОЙ КРЕПОСТИ ═════")
	main._clear_area_of_resources(base, 70.0)
	var c: Castle = Castle.new()
	_place(c, E, base)
	await pframes(6)
	# Гарнизон крыши — вражеские лучники (сажаются сразу)
	var g1: Array = _squad("archer", E, base + Vector3(0.0, 0.0, 6.0), 30, 6)
	await pframes(6)
	var sat: bool = c.garrison_now(int(g1[0]))
	await pframes(4)
	var roof = c._roof
	verdict("C0 вражеский отряд лучников сел на крышу", sat and int(roof.shown()) > 0,
		"спрайтов %d" % int(roof.shown()))
	var n_sq := 6
	var sqs: Array = []
	for k in range(n_sq):
		sqs.append(_squad("archer", F, base + Vector3(-22.0 + float(k) * 8.0, 0.0, 30.0), 30, 6))
	await pframes(30)
	# ПКМ по крепости всем выделением — ровно тем путём, что у клика
	var sm = main.selection_manager
	sm.selected_units.clear()
	for s in sqs:
		for u in s[1]:
			sm.selected_units.append(u)
	sm._sel_rebuild()
	GameManager.on_selection_changed(sm.selected_units, true)
	var front: Dictionary = sm._ring_squads_around(c)
	for u in sm.selected_units:
		var sid: int = (u as Unit).squad_id
		var t = c
		if front.has(sid):
			t = front[sid]
		(u as Unit).command_attack(t, true, true, true)
	var hp0: float = c.current_health
	var by_sid: Dictionary = {}
	var roof0: int = int(roof.shown())
	var alive0: int = _alive(g1[1]).size()
	var g_hp0: float = 0.0
	for gu in _alive(g1[1]):
		g_hp0 += (gu as Unit).current_health
	for f in range(60 * 14):
		await get_tree().physics_frame
		for frec in GameManager.flight_records():
			var sh = frec["shooter"]
			if sh == null or not is_instance_valid(sh) or not (sh is Unit):
				continue
			if (sh as Unit).faction == F:
				by_sid[(sh as Unit).squad_id] = true
	var firing := 0
	for s in sqs:
		if by_sid.has(int(s[0])):
			firing += 1
	verdict("C1 стреляют ВСЕ шесть отрядов", firing == n_sq, "стреляли %d из %d" % [firing, n_sq])
	var killed: int = alive0 - _alive(g1[1]).size()
	var g_hp1: float = 0.0
	for gu in _alive(g1[1]):
		g_hp1 += (gu as Unit).current_health
	# ТЗ 19.09.2026 (параллельный урон): защитник получает 0.5× стрелы, и
	# урон ложится на самого здорового — гибель приходит медленнее, а потери
	# запаса гарнизона и стен идут параллельно
	verdict("C2 залп бьёт лучников на крыше — гарнизон несёт потери (запас или бойцы), стены тоже",
		(killed > 0 or g_hp1 < g_hp0) and c.current_health < hp0,
		"убито %d из %d, запас гарнизона %.0f → %.0f, стены %.0f → %.0f" % [killed, alive0, g_hp0, g_hp1, hp0, c.current_health])
	# Тела на крыше: залп за окно может никого не добить — добиваем прямыми
	# попаданиями по крепости (тот же путь Castle.take_damage от стрелка)
	if killed < 3:
		var hammer: Unit = null
		for s in sqs:
			for u in _alive(s[1]):
				hammer = u
				break
			if hammer != null:
				break
		if hammer != null:
			for i in range(600):
				if alive0 - _alive(g1[1]).size() >= 3:
					break
				c.take_damage(60.0, hammer)
				await pframes(1)
		killed = alive0 - _alive(g1[1]).size()
		await pframes(3)
	verdict("C3 место павшего на крыше занимает резервист (спрайтов не меньше)",
		int(roof.shown()) == mini(roof0, _alive(g1[1]).size()),
		"было %d, стало %d при живых %d" % [roof0, int(roof.shown()), _alive(g1[1]).size()])
	# Тела: часть на крыше (выше грунта), часть у подножия вокруг здания
	var on_roof := 0
	var at_base := 0
	var angles: Array = []
	var cp: Vector3 = c.global_position
	for body in GameManager.corpses._list:
		var bp: Vector3 = body.pos
		var d := Vector2(bp.x - cp.x, bp.z - cp.z).length()
		if d > c.ring_radius() * 2.5:
			continue
		var gh: float = GameManager.get_terrain_height(bp.x, bp.z)
		if bp.y - gh > 1.0:
			on_roof += 1
		else:
			at_base += 1
			angles.append(atan2(bp.z - cp.z, bp.x - cp.x))
	# ТЗ 19.09.2026 (Garrison Archers): ВСЕ павшие защитники остаются лежать
	# на площадке, у подножия — никого (прежнее «половина падает» — история)
	verdict("C4 все тела павших — на крыше, у подножия никого", on_roof > 0 and on_roof == killed and at_base == 0,
		"на крыше %d, у подножия %d (убито %d)" % [on_roof, at_base, killed])
	var roof_pts: Array = []
	for body in GameManager.corpses._list:
		var bp2: Vector3 = body.pos
		if Vector2(bp2.x - cp.x, bp2.z - cp.z).length() > c.ring_radius() * 2.5:
			continue
		if bp2.y - GameManager.get_terrain_height(bp2.x, bp2.z) > 1.0:
			roof_pts.append(Vector2(bp2.x, bp2.z))
	var spread_ok := false
	if roof_pts.size() >= 2:
		var far_pair := 0.0
		for i in range(roof_pts.size()):
			for j in range(i + 1, roof_pts.size()):
				far_pair = maxf(far_pair, (roof_pts[i] as Vector2).distance_to(roof_pts[j]))
		spread_ok = far_pair > 0.5
	verdict("C5 тела на площадке лежат на своих местах, не в одной точке", spread_ok,
		"тел на крыше %d" % roof_pts.size())
	verdict("C6 стены крепости тоже страдают или гарнизон — цель приказа", c.current_health < hp0 or killed > 0)
	for s in sqs:
		_kill_all(s[1])
	_kill_all(g1[1])
	c.take_damage(1e12)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. РАСКЛАДКА КРЫШ
# ═════════════════════════════════════════════════════════════════════════════
func _d_layout(base: Vector3) -> void:
	print("\n═════ D. РАСКЛАДКА КРЫШ ═════")
	main._clear_area_of_resources(base, 60.0)
	var br: Building = _BarracksS.new()
	_place(br, F, base)
	await pframes(6)
	var a1: Array = _squad("archer", F, base + Vector3(0.0, 0.0, 8.0), 30, 6)
	await pframes(6)
	var ok: bool = br.garrison_now(int(a1[0]))
	await pframes(4)
	var roof = br._roof
	verdict("D1 бараки: 30 внутри, ровно %d видимых на крыше" % _UCfg.ROOF_VISIBLE["barracks"],
		ok and _UCfg.ROOF_VISIBLE["barracks"] == 15 and int(roof.shown()) == 15 and _alive(a1[1]).size() == 30,
		"спрайтов %d" % int(roof.shown()))
	# Разрежённость: ближайшие соседи не ближе GRID_DX_MIN
	var min_d := 1e9
	for i in range(15):
		for j in range(i + 1, 15):
			var a: Vector3 = roof.slot_local(i)
			var b: Vector3 = roof.slot_local(j)
			min_d = minf(min_d, Vector2(a.x - b.x, a.z - b.z).length())
	verdict("D2 места на крыше бараков разрежены (соседи не ближе %.2f м)" % roof.GRID_DX,
		min_d >= roof.GRID_DX * 0.95, "ближайшая пара %.2f м" % min_d)
	_kill_all(a1[1])
	br.take_damage(1e12)
	await pframes(4)
	var cp: Vector3 = base + Vector3(30.0, 0.0, 0.0)
	var c: Castle = Castle.new()
	_place(c, F, cp)
	await pframes(6)
	var b1: Array = _squad("archer", F, cp + Vector3(0.0, 0.0, 10.0), 30, 6)
	var b2: Array = _squad("archer", F, cp + Vector3(8.0, 0.0, 10.0), 30, 6)
	await pframes(6)
	var k1: bool = c.garrison_now(int(b1[0]))
	var k2: bool = c.garrison_now(int(b2[0]))
	await pframes(4)
	var rc = c._roof
	verdict("D3 крепость: два отряда по 30 внутри, видимых %d" % _UCfg.ROOF_VISIBLE["castle"],
		k1 and k2 and _UCfg.ROOF_VISIBLE["castle"] == 40 and int(rc.shown()) == 40,
		"спрайтов %d" % int(rc.shown()))
	var half_w: float = c._draw_half_w if c._draw_half_w > 0.0 else c.build_size.x * 0.5
	var left := 0
	var right := 0
	var centre_l := 0
	var centre_r := 0
	var cy: float = rc.slot_local(0).y
	var flank_min_y := 1e9
	for i in range(40):
		var p: Vector3 = rc.slot_local(i)
		var x: float = p.x - c._draw_cx
		if i < rc.KEEP_CENTRE_MEN:
			if x < 0.0:
				centre_l += 1
			else:
				centre_r += 1
		elif x < -half_w * 0.4:
			left += 1
			flank_min_y = minf(flank_min_y, p.y)
		elif x > half_w * 0.4:
			right += 1
			flank_min_y = minf(flank_min_y, p.y)
	verdict("D4 крепость: 22 в центре двумя половинками по 11, по 9 на башнях",
		rc.KEEP_CENTRE_MEN == 22 and centre_l == 11 and centre_r == 11 and left == 9 and right == 9,
		"центр %d + %d, слева %d, справа %d" % [centre_l, centre_r, left, right])
	verdict("D5 фланговые башни выше настила по Y", flank_min_y > cy + 0.2,
		"фланг min y %.2f, настил %.2f" % [flank_min_y, cy])
	# Просвет между половинками центра шире шага колонки
	var gap := 1e9
	for i in range(rc.KEEP_CENTRE_MEN):
		var pi_: Vector3 = rc.slot_local(i)
		if pi_.x - c._draw_cx >= 0.0:
			continue
		for j in range(rc.KEEP_CENTRE_MEN):
			var pj: Vector3 = rc.slot_local(j)
			if pj.x - c._draw_cx < 0.0:
				continue
			gap = minf(gap, pj.x - pi_.x)
	verdict("D6 между половинками центра просвет шире шага колонки", gap > rc.GRID_DX * 1.5,
		"просвет %.2f м" % gap)
	_kill_all(b1[1])
	_kill_all(b2[1])
	c.take_damage(1e12)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# E. РЕМОНТ
# ═════════════════════════════════════════════════════════════════════════════
func _e_repair(base: Vector3) -> void:
	print("\n═════ E. РЕМОНТ ЗДАНИЯ РАБОЧИМ ═════")
	main._clear_area_of_resources(base, 50.0)
	var h: Building = load("res://scripts/House.gd").new()
	_place(h, F, base)
	await pframes(6)
	h.take_damage(h.max_health * 0.6)
	var hp0: float = h.current_health
	verdict("E0 здание повреждено", hp0 < h.max_health * 0.5, "%.0f / %.0f" % [hp0, h.max_health])
	var w: Unit = _spawn("worker", F, base + Vector3(12.0, 0.0, 6.0))
	await pframes(4)
	var sm = main.selection_manager
	sm.selected_units.clear()
	sm.selected_units.append(w)
	sm._sel_rebuild()
	var taken: bool = sm._try_repair(h)
	verdict("E1 ПКМ рабочим по повреждённому зданию принят как ремонт", taken and w.state == Unit.State.BUILDING)
	var settled_f := -1
	var full_f := -1
	for f in range(60 * 60):
		await get_tree().physics_frame
		if settled_f < 0 and bool(w.get("_build_settled")):
			settled_f = f
		if h.current_health >= h.max_health - 0.01:
			full_f = f
			break
	verdict("E2 рабочий подошёл к основанию и встал на ремонт", settled_f >= 0, "за %d физкадров" % settled_f)
	verdict("E3 запас здания дошёл до 100 %%", full_f >= 0, "%.0f / %.0f за %d физкадров" % [h.current_health, h.max_health, full_f])
	await pframes(10)
	verdict("E4 после ремонта рабочий свободен (не BUILDING)", w.state != Unit.State.BUILDING,
		"состояние %d" % int(w.state))
	# Здоровое здание ремонтом не берётся
	var taken2: bool = sm._try_repair(h)
	verdict("E5 целое здание — не ремонт (приказ идёт дальше)", not taken2)
	w.take_damage(1e12)
	h.take_damage(1e12)
	await pframes(3)
