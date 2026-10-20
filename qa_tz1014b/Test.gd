extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 14.10.2026 (второе письмо, 11 блоков): логика без окна
## ═══════════════════════════════════════════════════════════════════════════
##   A — монах бросает бегущего пациента (паника / отход / в замок)
##   B — дома: 9 по базе, с 10-го экспонента, счёт трёх картинок вместе
##   C — кузница: копейщик 1d Фаланга / 2d урон по крупным / 3d латы / 5d найм
##       −50 %, мечник и лучник — найм −50 %, мечник 5d — серия 20, элита дольше
##   D — копья: без «Фаланги» [S] не опускает копья, с ней — опускает
##   E — залп по расколотому отряду: точка у живой половины, а не посередине
##   F — снос рудника: стрелки снимают его с цели
##   G — фермеры загона: у каждого свой угол, точки ожидания разные
##   H — Alt больше не переключает полоски; протяжка ПКМ — без «три в ряд»
##   I — рабочие, шедшие к стройке, после её конца выходят перед рисунком
## Запуск: godot --headless --path . res://qa_tz1014b/Test.tscn [-- only=abcdefghi]

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _Site := preload("res://scripts/ConstructionSite.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcdefghi"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz1014b: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3, fac: int = F) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int = F, cols: int = 6) -> int:
	var sid: int = GameManager.new_squad(fac, kind)
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
	return sid

func _members(sid: int) -> Array:
	var out: Array = []
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return out
	for m in (raw as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _place(b: Building, at: Vector3, fac: int = F) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _clear(at: Vector3, r: float) -> void:
	main._clear_trees(at, r)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
			u.queue_free()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "a" in _only: await _a_monk()
	if "b" in _only: _b_houses()
	if "c" in _only: _c_forge()
	if "d" in _only: await _d_phalanx()
	if "e" in _only: await _e_volley()
	if "f" in _only: await _f_mine()
	if "g" in _only: await _g_farmers()
	if "h" in _only: await _h_alt_drag()
	if "i" in _only: await _i_builders()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
func _a_monk() -> void:
	print("\n═════ A. МОНАХ И БЕГУЩИЙ ПАЦИЕНТ ═════")
	var at := Vector3(-60, 0, -40)
	_clear(at, 30.0)
	await pframes(3)
	var sid: int = _squad("spearman", at, 12)
	var monk: Unit = _spawn("monk", at + Vector3(-6, 0, 0))
	GameManager.add_to_squad(GameManager.new_squad(F, "monk"), monk)
	await pframes(5)
	for m in _members(sid):
		(m as Unit).current_health = (m as Unit).max_health * 0.4
	monk.command_heal(_members(sid)[0])
	await pframes(5)
	verdict("A0 приказ лечить отряд принят", monk._order_sid == sid, "order=%d" % monk._order_sid)
	# Отряд бежит: паника + отход
	(GameManager.squads[sid] as Dictionary)["panic_until"] = Time.get_ticks_msec() + 20000
	for m in _members(sid):
		(m as Unit).retreating = true
	monk._monk_step()
	# Свой тик монаха тоже сканирует (и мог уже снять приказ раньше нас) —
	# судим после нескольких его тактов, пока паника в силе
	await pframes(90)
	(GameManager.squads[sid] as Dictionary)["panic_until"] = Time.get_ticks_msec() + 20000
	monk._monk_step()
	verdict("A1 паника пациента — приказ лечить снят", monk._order_sid != sid and monk.patient_sid != sid,
		"order=%d patient=%d drops=%d" % [monk._order_sid, monk.patient_sid, monk.fled_drops])
	verdict("A2 бегущий отряд не выбирается пациентом сам", monk._pick_patient_squad() != sid)
	# Паника кончилась — отряд снова лечится
	(GameManager.squads[sid] as Dictionary)["panic_until"] = 0
	for m in _members(sid):
		(m as Unit).retreating = false
	verdict("A3 отряд перестал бежать — снова пациент", monk._pick_patient_squad() == sid,
		"выбран %d" % monk._pick_patient_squad())

# ─────────────────────────────────────────────────────────────────────────────
func _b_houses() -> void:
	print("\n═════ B. ЦЕНА ДОМОВ ═════")
	var base: float = float(_UCfg.building_cost("house").get(Constants.RESOURCE_WOOD, 0.0))
	var row: Array = []
	for n in range(0, 20):
		row.append(_UCfg.building_cost_mult("house", n))
	print("  множители 1-20-го дома: %s" % str(row))
	var flat := true
	for n in range(0, _UCfg.HOUSE_FREE_COUNT):
		if absf(float(row[n]) - 1.0) > 1e-6:
			flat = false
	verdict("B1 первые %d домов по базовой цене" % _UCfg.HOUSE_FREE_COUNT, flat)
	var grows := true
	for n in range(_UCfg.HOUSE_FREE_COUNT, 19):
		if not (float(row[n + 1]) > float(row[n]) * 1.5):
			grows = false
	verdict("B2 с 10-го дома каждый следующий дороже ×1.5 и больше (экспонента)",
		float(row[_UCfg.HOUSE_FREE_COUNT]) > 1.0 and grows,
		"10-й ×%.2f, 15-й ×%.1f, 20-й ×%.0f" % [row[9], row[14], row[19]])
	verdict("B3 20-й дом — «целое состояние» (> 20 000 дерева)", base * float(row[19]) > 20000.0,
		"%.0f" % (base * float(row[19])))
	# Три картинки дома считаются вместе
	var at := Vector3(-30, 0, -70)
	_clear(at, 20.0)
	var hs: Array = []
	for k in range(_UCfg.HOUSE_FREE_COUNT):
		var h: Building = load("res://scripts/House.gd").new()
		h.variant_id = String(_UCfg.HOUSE_IDS[k % 3])
		h.building_id = h.variant_id
		_place(h, at + Vector3(float(k % 5) * 4.0, 0, float(k / 5) * 4.0))
		hs.append(h)
	var total: int = GameManager.house_total(F)
	var c_next: Dictionary = GameManager.build_cost_for(F, "house2")
	verdict("B4 домов трёх картинок считается вместе; следующий уже дороже",
		total >= _UCfg.HOUSE_FREE_COUNT and float(c_next.get(Constants.RESOURCE_WOOD, 0.0)) > base * 1.5,
		"домов %d, цена %.0f" % [total, float(c_next.get(Constants.RESOURCE_WOOD, 0.0))])
	for h in hs:
		h.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _c_forge() -> void:
	print("\n═════ C. КУЗНИЦА ═════")
	var n1: Dictionary = _Forge.get_node("spearman_1d")
	var n2: Dictionary = _Forge.get_node("spearman_2d")
	var n3: Dictionary = _Forge.get_node("spearman_3d")
	var n5: Dictionary = _Forge.get_node("spearman_5d")
	verdict("C1 копейщик: первое улучшение — Фаланга", String(n1.get("name", "")) == "Фаланга", String(n1.get("name", "")))
	verdict("C2 второе — урон по крупным (коннице/тушам)", float(n2.get("bonus_giant_melee", 0.0)) >= 1.0,
		"×%.1f" % (1.0 + float(n2.get("bonus_giant_melee", 0.0))))
	verdict("C3 третье — тяжёлые латы (существенная броня)", float(n3.get("bonus_armor", 0.0)) >= 4.0,
		"+%.1f" % float(n3.get("bonus_armor", 0.0)))
	var trains := 0
	for nid in ["spearman_5d", "warrior_4a", "archer_4d"]:
		if float(_Forge.get_node(nid).get("bonus_train", 0.0)) >= 1.0:
			trains += 1
	verdict("C4 найм −50 % — свой дорогой узел у копейщиков, мечников, лучников", trains == 3, "%d из 3" % trains)
	var gold5: float = float(n5.get("cost_gold", 0.0))
	verdict("C5 узел найма дорогой (≥ 2000 золота до множителя ряда)", gold5 >= 2000.0, "%.0f" % gold5)
	# Время найма −50 % живьём: бараки, до и после 5d
	var at := Vector3(0, 0, -80)
	_clear(at, 20.0)
	var br: Building = Barracks.new()
	_place(br, at)
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.gather_resource(F, r, 50000.0)
	br.train_from_config("spearman")
	var t0: float = float((br.production_queue[0] as Dictionary).get("time", 0.0)) if not br.production_queue.is_empty() else -1.0
	GameManager.finish_research(F, "spearman_5d")
	br.train_from_config("spearman")
	var t1: float = float((br.production_queue[br.production_queue.size() - 1] as Dictionary).get("time", 0.0)) if br.production_queue.size() > 1 else -1.0
	verdict("C6 после «Муштры» отряд копейщиков нанимается вдвое быстрее", t0 > 0.0 and absf(t1 - t0 * 0.5) < 0.05,
		"%.1f → %.1f с" % [t0, t1])
	br.queue_free()
	# Элита дольше: мечники 84 / 66
	var tw_c: float = float(_UCfg.train_cfg("castle", "warrior").get("time", 0.0))
	var tw_b: float = float(_UCfg.train_cfg("barracks", "warrior").get("time", 0.0))
	verdict("C7 элита (мечники) обучается дольше прежних 70/55 с", tw_c > 70.0 and tw_b > 55.0, "%.0f / %.0f" % [tw_c, tw_b])
	# Мечник: серия 20 со всеми узлами
	GameManager.finish_research(F, "warrior_3d")
	GameManager.finish_research(F, "warrior_5d")
	var hits: int = 10 + int(round(GameManager.unit_bonus(F, "warrior", "bonus_rage_hits")))
	verdict("C8 «Яростная атака» с финальным узлом — серия 20 ударов", hits == 20, "%d" % hits)

# ─────────────────────────────────────────────────────────────────────────────
func _d_phalanx() -> void:
	print("\n═════ D. ФАЛАНГА ТОЛЬКО С УЛУЧШЕНИЕМ ═════")
	var at := Vector3(40, 0, -60)
	_clear(at, 25.0)
	await pframes(3)
	# Сброс изученного у игрока (другие блоки могли изучить)
	if GameManager.researched.has(F):
		(GameManager.researched[F] as Dictionary).erase("spearman_1d")
	var sid: int = _squad("spearman", at, 12)
	for m in _members(sid):
		(m as Unit).set_stance("defense")
	await pframes(60)
	var down0 := 0
	for m in _members(sid):
		if (m as Spearman)._spear_leveled():
			down0 += 1
	verdict("D1 без «Фаланги» [S] держит строй, копья НЕ опущены", down0 == 0, "опущено %d из 12" % down0)
	verdict("D1б без «Фаланги» стены копий нет", not (_members(sid)[0] as Unit).spear_wall_active())
	GameManager.finish_research(F, "spearman_1d")
	await pframes(90)
	var down1 := 0
	# Первый вызов взводит ЛИЧНУЮ задержку опускания (_own_drop_delay_ms),
	# второй — позже по часам — уже судит
	for m in _members(sid):
		Unit.now_ms = Time.get_ticks_msec()
		(m as Spearman)._spear_leveled()
	for m in _members(sid):
		var sp := m as Spearman
		Unit.now_ms = Time.get_ticks_msec() + 10000
		if sp._spear_leveled():
			down1 += 1
	verdict("D2 с «Фалангой» [S] опускает копья у всего строя", down1 == 12, "опущено %d из 12" % down1)
	verdict("D2б с «Фалангой» стена копий работает", (_members(sid)[0] as Unit).spear_wall_active())
	for m in _members(sid):
		(m as Unit).set_stance("attack")
	await pframes(5)
	var down2 := 0
	for m in _members(sid):
		var sp2 := m as Spearman
		Unit.now_ms = Time.get_ticks_msec() + 5000
		if sp2._spear_leveled():
			down2 += 1
	verdict("D3 «Вольно» [C] — копья подняты и с «Фалангой»", down2 == 0, "опущено %d" % down2)
	# Приём копья: урон по коннице выше
	GameManager.finish_research(F, "spearman_2d")
	var sp3 := _members(sid)[0] as Spearman
	var rider: Unit = _spawn("goblin_rider", at + Vector3(0, 0, 4), E)
	if rider != null:
		rider.set_tick(false)
		sp3.set_attack_target(null)
		var d_plain: float = sp3._strike_damage()
		sp3.set_attack_target(rider)
		var d_big: float = sp3._strike_damage()
		verdict("D4 «Приём копья»: удар по коннице ×2.5", rider.giant_class() and absf(d_big - d_plain * 2.5) < 0.01,
			"%.1f → %.1f" % [d_plain, d_big])
		sp3.set_attack_target(null)
		rider.queue_free()
	else:
		print("  (конницы в PRELOAD_SCENES нет — D4 пропущен)")
	for m in _members(sid):
		m.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _e_volley() -> void:
	print("\n═════ E. ЗАЛП ПО РАСКОЛОТОМУ ОТРЯДУ ═════")
	var at := Vector3(-20, 0, 70)
	_clear(at, 35.0)
	await pframes(3)
	var foe: int = GameManager.new_squad(E, "spearman")
	for k in range(20):
		var side: float = -12.0 if k < 10 else 12.0
		var u := _spawn("spearman", at + Vector3(side + float(k % 5) * 0.7, 0, float((k % 10) / 5) * 0.7), E)
		GameManager.add_to_squad(foe, u)
		u.set_tick(false)
	var arch: int = _squad("archer", at + Vector3(0, 0, 14), 10)
	var sq: Dictionary = GameManager.squads[arch]
	var left0: Unit = _members(foe)[0]
	sq["volley_foe"] = foe
	sq["volley_aim"] = left0.global_position
	await pframes(2)
	var vp: Vector3 = GameManager.squad_volley_point(arch)
	var med: Vector3 = GameManager.squad_centroid(foe)
	print("  медиана отряда %s, точка залпа %s" % [str(med), str(vp)])
	verdict("E1 точка залпа — у живой половины, а не в пустоте между", vp != Vector3.ZERO and absf(vp.x - (at.x - 10.6)) < 3.0,
		"x=%.1f (левая половина ≈ %.1f, середина %.1f)" % [vp.x, at.x - 10.6, at.x])
	verdict("E2 туча — габарит половины, а не всего отряда", float(sq.get("volley_spread", 99.0)) < 5.0,
		"%.1f м" % float(sq.get("volley_spread", 99.0)))
	# Левая половина выбита — у прежней точки живых нет: точки залпа нет вовсе
	for k in range(10):
		var m = _members(foe)[0]
		(m as Unit).take_damage(99999.0)
	await pframes(3)
	var vp2: Vector3 = GameManager.squad_volley_point(arch)
	verdict("E3 у точки залпа никого — залп не бьёт по старым координатам", vp2 == Vector3.ZERO, str(vp2))
	for m in _members(foe) + _members(arch):
		m.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _f_mine() -> void:
	print("\n═════ F. СНОС РУДНИКА ОТПУСКАЕТ СТРЕЛКОВ ═════")
	var mine: Mine = null
	for b in get_tree().get_nodes_in_group("all_buildings"):
		if b is Mine:
			mine = b
			break
	if mine == null:
		verdict("F0 рудник на карте", false)
		return
	mine.set_owner_faction(E)
	var a: Unit = _spawn("archer", mine.global_position + Vector3(0, 0, 14))
	GameManager.add_to_squad(GameManager.new_squad(F, "archer"), a)
	a.set_attack_target(mine)
	await pframes(2)
	verdict("F0 стрелок целится в рудник", a.attack_target == mine)
	mine._die()
	await pframes(2)
	verdict("F1 рудник «снесён» (ничейный, полный запас) — цель снята",
		a.attack_target != mine, "цель %s, рудник ничейный=%s" % [str(a.attack_target), str(mine.is_neutral())])
	a.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _g_farmers() -> void:
	print("\n═════ G. МЕСТА ФЕРМЕРОВ У ЗАГОНА ═════")
	var at := Vector3(70, 0, 40)
	_clear(at, 25.0)
	await pframes(3)
	var pen: Building = load("res://scripts/SheepPen.gd").new()
	_place(pen, at)
	await pframes(10)
	var ws: Array = []
	for k in range(6):
		var w := _spawn("worker", at + Vector3(8, 0, float(k) * 0.4))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
		w.command_farm_pen(pen)
		ws.append(w)
	await pframes(5)
	var angs: Dictionary = {}
	var waits: Array = []
	for w in ws:
		angs[snappedf(pen.farmer_angle(w), 0.001)] = true
		waits.append(pen.farm_wait_point(w))
	verdict("G1 у каждого фермера свой угол на круге", angs.size() == ws.size(), "%d углов на %d" % [angs.size(), ws.size()])
	var min_d := INF
	for i in range(waits.size()):
		for j in range(i + 1, waits.size()):
			min_d = minf(min_d, (waits[i] as Vector3).distance_to(waits[j]))
	verdict("G2 точки ожидания разнесены (не в одной точке)", min_d > 0.8, "мин. %.2f м" % min_d)
	var r_ok := true
	for p in waits:
		var d: float = Vector2((p as Vector3).x - at.x, (p as Vector3).z - at.z).length()
		if d > minf(pen.build_size.x, pen.build_size.z) * 0.5:
			r_ok = false
	verdict("G3 радиус кольца меньше размера загона", r_ok)
	# Работают 20 с: попарное расстояние стоящих у туш — не в одной точке
	await pframes(1200)
	var close := 0
	for i in range(ws.size()):
		for j in range(i + 1, ws.size()):
			if (ws[i] as Node3D).global_position.distance_to((ws[j] as Node3D).global_position) < 0.35:
				close += 1
	verdict("G4 через 20 с работы фермеры не слиплись (пар ближе 0.35 м)", close <= 1, "%d пар" % close)
	for w in ws:
		w.queue_free()
	pen.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _h_alt_drag() -> void:
	print("\n═════ H. ALT И ПРОТЯЖКА ПКМ ═════")
	GameManager.set_hp_bars_forced(false)
	var ev := InputEventKey.new()
	ev.keycode = KEY_ALT
	ev.physical_keycode = KEY_ALT
	ev.pressed = true
	main._input(ev)
	verdict("H1 Alt не включает полоски", not GameManager.hp_bars_forced)
	# Протяжка: копейщики со «Стеной копий» — не строго три шеренги
	GameManager.finish_research(F, "spearman_1d")
	var at := Vector3(-80, 0, 0)
	_clear(at, 25.0)
	await pframes(3)
	var sid: int = _squad("spearman", at, 30)
	var sm = main.selection_manager
	var out: Dictionary = sm._block_formation_slots(at + Vector3(-12, 0, 6), at + Vector3(12, 0, 6), _members(sid))
	var rows_max := 0
	for r in out["rows"]:
		rows_max = maxi(rows_max, int(r))
	verdict("H2 копейщики на длинной протяжке — не три шеренги (свободный прямоугольник)",
		rows_max + 1 < GameManager.SPEAR_WALL_ROWS, "шеренг %d" % (rows_max + 1))
	for m in _members(sid):
		m.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _i_builders() -> void:
	print("\n═════ I. РАБОЧИЕ ПОСЛЕ СТРОЙКИ ═════")
	var at := Vector3(20, 0, 80)
	_clear(at, 30.0)
	await pframes(3)
	var site: Building = _Site.new()
	site.set("target_id", "barracks")
	_place(site, at)
	await pframes(5)
	var crew: Array = []
	for k in range(5):
		var a: float = PI + TAU * float(k) / 5.0
		var w := _spawn("worker", at + Vector3(cos(a) * 9.0, 0, sin(a) * 9.0 - 4.0))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
		w.command_build(site)
		crew.append(w)
	var built: Array = []
	site.connect("built", func(b): built.append(b))
	site.set("progress", float(site.get("build_time")) * 0.97)
	var t := 0
	while built.is_empty() and t < 900:
		await pframes(1)
		t += 1
	await pframes(300)
	var hidden := 0
	if not built.is_empty():
		var b: Building = built[0]
		var line_z: float = b.global_position.z + b._draw_z
		for w in crew:
			var p: Vector3 = (w as Node3D).global_position
			if p.z < line_z and absf(p.x - b.global_position.x - b._draw_cx) < b._draw_half_w:
				hidden += 1
	verdict("I1 бараки достроены, за рисунком ни одного рабочего", not built.is_empty() and hidden == 0,
		"за рисунком %d из %d" % [hidden, crew.size()])
