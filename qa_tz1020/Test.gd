extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 20.10.2026 (9 блоков): логика без окна
## ═══════════════════════════════════════════════════════════════════════════
##   A — строй копейщиков: после «Фаланги»/«Приёма копья» и улучшений лучников
##       протяжка ПКМ свободна в ОБОИХ режимах ([1] и [2]) — не три шеренги
##   B — тревога: все рабочие в ближайшую крепость, общий слот, лимит рабочих
##       не теряет укрытых, ЛКМ — один выходит, колокол снят — все выходят и
##       возвращаются к прежней работе (жила, стройка)
##   C — «В замок» у рабочего: личная команда без колокола
##   D — укрепление башни: цена дерево+камень, работы по таймеру, +прочность,
##       −урон, сохранение ступени
##   E — ремонт башни с гарнизоном: ПКМ рабочими не высаживает лучников
##   F — пауза: часы партии стоят, «мозги» мира паузуемые
##   G — гарнизон без «Залпового огня» стреляет вразнобой
##   H — стрелы по застрявшему одиночке: упреждение по факту, хитбокс по телу
##   I — карточки: столбик характеристик, «Тип/Умения/Особое умение», без мусора
##   J — звания и знамёна: Опытные/Ветераны/Легендарные, штандарт — только
##       легендарным, у орды — «язычки»
##   K — аудит лога: снос рудника не трогает чужую цель и не дублирует подписку;
##       ИИ не переспрашивает недостижимую точку
## Запуск: godot --headless --path . res://qa_tz1020/Test.tscn [-- only=abcdefghijk]

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Tower := preload("res://scripts/Tower.gd")
const _BannerArt := preload("res://scripts/BannerArt.gd")
const _Site := preload("res://scripts/ConstructionSite.gd")
const _Save := preload("res://scripts/SaveLoadManager.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcdefghijk"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(500.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_tz1020: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().paused = false
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

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

func _rich() -> void:
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(F, r, 50000.0)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	_rich()
	if "a" in _only: await _a_spear_drag()
	if "b" in _only: await _b_alert()
	if "c" in _only: await _c_worker_shelter()
	if "d" in _only: await _d_tower_fort()
	if "e" in _only: await _e_repair_garrison()
	if "f" in _only: await _f_pause()
	if "g" in _only: await _g_ragged_fire()
	if "h" in _only: await _h_stuck_goblin()
	if "i" in _only: _i_cards()
	if "j" in _only: await _j_banners()
	if "k" in _only: await _k_audit()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
func _rows_of(out: Dictionary) -> int:
	var rows_max := 0
	for r in out["rows"]:
		rows_max = maxi(rows_max, int(r))
	return rows_max + 1

func _a_spear_drag() -> void:
	print("\n═════ A. СТРОЙ КОПЕЙЩИКОВ ПОСЛЕ КУЗНИЦЫ ═════")
	for nid in ["spearman_1d", "spearman_2d", "spearman_1a", "spearman_1b", "archer_1a", "archer_1b"]:
		if not _Forge_node_exists(nid):
			continue
		GameManager.finish_research(F, nid)
	var at := Vector3(-80, 0, 0)
	_clear(at, 25.0)
	await pframes(3)
	var sid: int = _squad("spearman", at, 30)
	var sm = main.selection_manager
	var men: Array = _members(sid)
	var long_a := at + Vector3(-12, 0, 6)
	var long_b := at + Vector3(12, 0, 6)
	var short_b := at + Vector3(-12 + 30.0 * 0.58 / 6.0, 0, 6)
	var prev_mode: int = sm.formation_mode
	sm.formation_mode = sm.FORM_WIDE
	var w_long: int = _rows_of(sm._mono_formation_slots(long_a, long_b, men))
	sm.formation_mode = sm.FORM_DEEP
	var d_long: int = _rows_of(sm._mono_formation_slots(long_a, long_b, men))
	var d_short: int = _rows_of(sm._mono_formation_slots(long_a, short_b, men))
	sm.formation_mode = prev_mode
	verdict("A1 [1] длинная протяжка — меньше трёх шеренг", w_long < 3, "шеренг %d" % w_long)
	verdict("A2 [2] длинная протяжка — тоже свободно (было строго 3)", d_long < 3, "шеренг %d" % d_long)
	verdict("A3 [2] короткая протяжка — шеренг больше трёх (глубину задаёт игрок)", d_short > 3, "шеренг %d" % d_short)
	verdict("A4 стена копий (Фаланга) изучена — флаг отряда", GameManager.spear_wall_ready(sid))
	for m in men:
		m.queue_free()

func _Forge_node_exists(nid: String) -> bool:
	return not (load("res://scripts/forge_config.gd").get_node(nid) as Dictionary).is_empty()

# ─────────────────────────────────────────────────────────────────────────────
var _castle: Building = null
func _ensure_castle(at: Vector3) -> Building:
	if _castle != null and is_instance_valid(_castle):
		return _castle
	_clear(at, 30.0)
	var c: Building = Castle.new()
	_place(c, at)
	_castle = c
	return c

func _b_alert() -> void:
	print("\n═════ B. ТРЕВОГА: РАБОЧИЕ В ЗАМОК ═════")
	var base := Vector3(-120, 0, 60)
	var c: Building = _ensure_castle(base)
	await pframes(10)
	# Жила и стройка рядом с замком
	var wood: ResourceNode = main.find_nearest_resource(base + Vector3(20, 0, 0), Constants.RESOURCE_WOOD)
	var site: Building = _Site.new()
	site.set("target_id", "barracks")
	_place(site, base + Vector3(16, 0, 14))
	await pframes(5)
	var gatherers: Array = []
	var builders: Array = []
	for k in range(6):
		var w := _spawn("worker", base + Vector3(10.0 + float(k), 0, 6.0))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
		if k < 4 and wood != null:
			w.command_gather(wood)
			gatherers.append(w)
		else:
			w.command_build(site)
			builders.append(w)
	await pframes(60)
	var used0: int = GameManager.pop_workers_used(F)
	var on: bool = GameManager.toggle_worker_alert(F)
	verdict("B0 колокол взведён", on and GameManager.worker_alert_on(F))
	var t := 0
	while int(c.call("shelter_count")) < 6 and t < 1500:
		await pframes(10)
		t += 10
	var inside: int = int(c.call("shelter_count"))
	verdict("B1 все рабочие в замке, в одном слоте", inside == 6, "внутри %d за %d кадров" % [inside, t])
	var visible_n := 0
	for w in gatherers + builders:
		if is_instance_valid(w) and (w as Unit).visible:
			visible_n += 1
	verdict("B2 укрытые сняты с карты", visible_n == 0, "на карте %d" % visible_n)
	verdict("B3 лимит рабочих считает укрытых", GameManager.pop_workers_used(F) == used0,
		"было %d, стало %d" % [used0, GameManager.pop_workers_used(F)])
	var out1: int = int(c.call("shelter_release", 1))
	verdict("B4 ЛКМ по слоту — выходит один", out1 == 1 and int(c.call("shelter_count")) == 5,
		"вышло %d, внутри %d" % [out1, int(c.call("shelter_count"))])
	GameManager.toggle_worker_alert(F)
	await pframes(5)
	verdict("B5 отбой — все снаружи", int(c.call("shelter_count")) == 0)
	var back_g := 0
	for w in gatherers:
		if is_instance_valid(w) and (w as Worker).gather_target != null:
			back_g += 1
	var back_b := 0
	for w in builders:
		if is_instance_valid(w) and (w as Worker).build_target == site:
			back_b += 1
	verdict("B6 добытчики вернулись к жиле", back_g == gatherers.size(), "%d из %d" % [back_g, gatherers.size()])
	verdict("B7 строители вернулись на стройку", back_b == builders.size(), "%d из %d" % [back_b, builders.size()])
	for w in gatherers + builders:
		if is_instance_valid(w):
			w.queue_free()
	site.queue_free()

func _c_worker_shelter() -> void:
	print("\n═════ C. «В ЗАМОК» У РАБОЧЕГО ═════")
	var base := Vector3(-120, 0, 60)
	var c: Building = _ensure_castle(base)
	await pframes(3)
	var ws: Array = []
	for k in range(3):
		var w := _spawn("worker", base + Vector3(-14.0, 0, 4.0 + float(k)))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
		ws.append(w)
	var sent: int = GameManager.shelter_workers(ws)
	verdict("C0 отправлены трое", sent == 3)
	verdict("C1 колокол при этом не взведён", not GameManager.worker_alert_on(F))
	var t := 0
	while int(c.call("shelter_count")) < 3 and t < 1200:
		await pframes(10)
		t += 10
	verdict("C2 трое внутри", int(c.call("shelter_count")) == 3, "кадров %d" % t)
	var out: int = int(c.call("shelter_release", -1))
	verdict("C3 ПКМ — вышли все", out == 3 and int(c.call("shelter_count")) == 0)
	for w in ws:
		if is_instance_valid(w):
			w.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _d_tower_fort() -> void:
	print("\n═════ D. УКРЕПЛЕНИЕ БАШНИ ═════")
	var at := Vector3(-40, 0, 90)
	_clear(at, 20.0)
	var tw: Building = _Tower.new()
	_place(tw, at)
	await pframes(5)
	var hp0: float = tw.max_health
	var wood0: float = ResourceManager.get_amount(F, Constants.RESOURCE_WOOD)
	var stone0: float = ResourceManager.get_amount(F, Constants.RESOURCE_STONE)
	var gold0: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
	verdict("D0 работы начались", bool(tw.call("fort_start")))
	verdict("D1 цена — дерево и камень, золото не тронуто",
		ResourceManager.get_amount(F, Constants.RESOURCE_WOOD) < wood0
		and ResourceManager.get_amount(F, Constants.RESOURCE_STONE) < stone0
		and is_equal_approx(ResourceManager.get_amount(F, Constants.RESOURCE_GOLD), gold0))
	verdict("D2 повторный заказ во время работ отклонён", not bool(tw.call("fort_start")))
	var lvl1: Dictionary = _UCfg.TOWER_FORT_LEVELS[0]
	var need: int = int(float(lvl1["time"]) * 60.0) + 30
	var t := 0
	while int(tw.get("fort_level")) < 1 and t < need + 200:
		await pframes(10)
		t += 10
	verdict("D3 ступень 1 готова по таймеру", int(tw.get("fort_level")) == 1, "кадров %d (срок %.0f с)" % [t, float(lvl1["time"])])
	verdict("D4 прочность выросла", tw.max_health > hp0 + 1.0, "%.0f → %.0f" % [hp0, tw.max_health])
	var h0: float = tw.current_health
	tw.take_damage(100.0, null)
	var lost: float = h0 - tw.current_health
	verdict("D5 входящий урон срезан", lost < 99.0 and lost > 1.0, "100 → %.1f" % lost)
	var cap: Array = _Save._capture_buildings(main)
	var fort_saved := false
	for rec in cap:
		if int((rec as Dictionary).get("fort", 0)) == 1:
			fort_saved = true
	verdict("D6 ступень попадает в сохранение", fort_saved)
	tw.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _e_repair_garrison() -> void:
	print("\n═════ E. РЕМОНТ БАШНИ С ГАРНИЗОНОМ ═════")
	var at := Vector3(40, 0, 90)
	_clear(at, 25.0)
	var tw: Building = _Tower.new()
	_place(tw, at)
	await pframes(5)
	var sid: int = _squad("archer", at + Vector3(0, 0, 8), 12)
	verdict("E0 лучники сели в башню", bool((tw as Castle).garrison_now(sid)))
	tw.take_damage(tw.max_health * 0.4, null)
	var ws: Array = []
	for k in range(3):
		var w := _spawn("worker", at + Vector3(-3.0 + float(k), 0, 9.0))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
		ws.append(w)
	var sm = main.selection_manager
	var cam = main.get("_camera")
	cam.set_process(false)
	main.set_process(false)
	cam.jump_to(tw.global_position, 26.0)
	await frames(4)
	sm.selected_units = ws.duplicate()
	sm._sel_set.clear()
	for w in ws:
		sm._sel_set[w] = true
	var sp: Vector2 = cam.unproject_position(tw.global_position + Vector3(0, 2.0, 0))
	var pick: Dictionary = sm._pick_at(sp, sm.order_pick_mask())
	verdict("E1 под курсором — башня", pick["target"] == tw, "цель %s" % str(pick["target"]))
	sm._handle_right_click(sp)
	await pframes(5)
	verdict("E2 гарнизон остался внутри", (tw as Castle).garrison_squad_id() == sid)
	var rep := 0
	for w in ws:
		if (w as Worker).build_target == tw:
			rep += 1
	verdict("E3 рабочие ушли чинить", rep == ws.size(), "%d из %d" % [rep, ws.size()])
	var h0: float = tw.current_health
	await pframes(600)
	verdict("E4 запас растёт, лучники внутри", tw.current_health > h0 and (tw as Castle).garrison_squad_id() == sid,
		"%.0f → %.0f" % [h0, tw.current_health])
	main.set_process(true)
	cam.set_process(true)
	sm.selected_units = []
	sm._sel_set.clear()
	for w in ws:
		w.queue_free()
	(tw as Castle).release_garrison(sid)
	tw.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _f_pause() -> void:
	print("\n═════ F. ПАУЗА ═════")
	var c0: float = float(main.call("game_clock"))
	var tl0: float = GameManager.truce_left()
	get_tree().paused = true
	await frames(90)
	var c1: float = float(main.call("game_clock"))
	var tl1: float = GameManager.truce_left()
	get_tree().paused = false
	verdict("F1 часы партии стоят на паузе", absf(c1 - c0) < 0.001, "%.3f → %.3f" % [c0, c1])
	verdict("F2 перемирие не тает на паузе", absf(tl1 - tl0) < 0.001, "%.2f → %.2f" % [tl0, tl1])
	var paus := true
	var names := []
	for n in ["assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null and (nd as Node).process_mode != Node.PROCESS_MODE_PAUSABLE:
			paus = false
			names.append(n)
	verdict("F3 эвенты и командиры паузуемые", paus, str(names))
	await frames(10)
	verdict("F4 без паузы часы идут", float(main.call("game_clock")) > c1)

# ─────────────────────────────────────────────────────────────────────────────
func _g_ragged_fire() -> void:
	print("\n═════ G. ГАРНИЗОН БЕЗ ЗАЛПА — ВРАЗНОБОЙ ═════")
	var at := Vector3(10, 0, -90)
	_clear(at, 40.0)
	var tw: Building = _Tower.new()
	_place(tw, at)
	await pframes(5)
	var sid: int = _squad("archer", at + Vector3(0, 0, 8), 12)
	(tw as Castle).garrison_now(sid)
	var volley_on: bool = GameManager.squad_volley_mode(sid)
	var dummy_sid: int = _squad("goblin_spearman", at + Vector3(0, 0, 14), 6, G)
	for m in _members(dummy_sid):
		(m as Unit).set_tick(false)
		(m as Unit).max_health = 1.0e7
		(m as Unit).current_health = 1.0e7
	var roof = (tw as Castle)._roof
	var shot_frames: Dictionary = {}
	var last: int = int(roof.shots_fired)
	for f in range(240):
		await pframes(1)
		var now: int = int(roof.shots_fired)
		if now > last:
			shot_frames[f] = now - last
			last = now
	var max_burst := 0
	for k in shot_frames:
		max_burst = maxi(max_burst, int(shot_frames[k]))
	print("  режим залпа=%s, кадров с выстрелами %d, выстрелов %d, крупнейшая пачка %d" % [
		str(volley_on), shot_frames.size(), last, max_burst])
	verdict("G1 без улучшения режим залпа выключен", not volley_on)
	verdict("G2 выстрелы разнесены по кадрам (не хором)", shot_frames.size() >= 8 and max_burst <= 4,
		"кадров %d, пачка до %d" % [shot_frames.size(), max_burst])
	(tw as Castle).release_garrison(sid)
	for m in _members(dummy_sid):
		m.queue_free()
	tw.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _h_stuck_goblin() -> void:
	print("\n═════ H. СТРЕЛЫ ПО ЗАСТРЯВШЕМУ ОДИНОЧКЕ ═════")
	var at := Vector3(90, 0, 20)
	_clear(at, 30.0)
	await pframes(3)
	var gob := _spawn("goblin_spearman", at + Vector3(0, 0, -14), G)
	GameManager.add_to_squad(GameManager.new_squad(G, "goblin_spearman"), gob)
	gob.max_health = 1.0e7
	gob.current_health = 1.0e7
	gob._soa_push_stats()
	gob.set_tick(false)
	# «Бежит в дерево»: намерение есть, смещения нет
	gob.velocity = Vector3(3.0, 0.0, 0.0)
	verdict("H0 фактическая скорость застрявшего — ноль", gob.real_velocity().length() < 0.01,
		"velocity %.1f, real %.2f" % [gob.velocity.length(), gob.real_velocity().length()])
	var sid: int = _squad("archer", at, 10)
	var hp0: float = gob.current_health
	var fired0: int = GameManager.arrows_fired
	for m in _members(sid):
		(m as Unit).command_attack(gob, true)
	# Попадания — по потерянному запасу: несколько стрел в одном кадре
	# считаются каждая (урон одной стрелы — наименьшая разовая потеря)
	var deltas: Array = []
	var prev_hp: float = hp0
	for f in range(900):
		await pframes(1)
		gob.velocity = Vector3(3.0, 0.0, 0.0)
		if gob.current_health < prev_hp - 0.01:
			deltas.append(prev_hp - gob.current_health)
			prev_hp = gob.current_health
	var one: float = INF
	for d in deltas:
		one = minf(one, float(d))
	var dmg_events := 0
	for d in deltas:
		dmg_events += maxi(1, int(round(float(d) / one)))
	var fired: int = GameManager.arrows_fired - fired0
	var rate: float = float(dmg_events) / float(maxi(fired, 1))
	print("  выпущено %d, попаданий (кадров с уроном) %d, доля %.2f" % [fired, dmg_events, rate])
	verdict("H1 по застрявшему одиночке попадает больше половины стрел", fired >= 10 and rate >= 0.5,
		"%d из %d" % [dmg_events, fired])
	for m in _members(sid):
		m.queue_free()
	gob.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _i_cards() -> void:
	print("\n═════ I. КАРТОЧКИ ═════")
	var hud = main.hud
	var bad := ["ветераном", "Содержание", "ЛКМ", "ПКМ — отменить"]
	for uid in ["warrior", "spearman", "archer", "monk", "worker"]:
		var card: Dictionary = hud._unit_card(uid, F, {}, 30)
		var stats: Array = card.get("stats", [])
		var info: Array = card.get("info", [])
		var labels: Array = []
		for r in stats:
			labels.append(String((r as Dictionary).get("label", "")))
		var all_text: String = str(card.get("lines", [])) + str(info)
		var junk := false
		for b in bad:
			if b in all_text:
				junk = true
		var info_keys: Array = []
		for p in info:
			info_keys.append(String((p as Array)[0]))
		var want_stats: bool = uid == "worker" or ("Здоровье" in labels and "Атака" in labels and "Скорость" in labels)
		verdict("I-%s столбик статов, Тип/Умения/Особое, без мусора" % uid,
			want_stats and stats.size() >= 3 and info_keys == ["Тип", "Умения", "Особое умение"] and not junk,
			"статы %s; инфо %s" % [str(labels), str(info_keys)])
	var wc: Dictionary = hud._unit_card("warrior", F, {}, 30)
	var special := ""
	for p in wc.get("info", []):
		if String((p as Array)[0]) == "Особое умение":
			special = String((p as Array)[1])
	verdict("I-мечник: «Стена щитов» и «Яростная атака»",
		"Стена щитов" in str(wc["info"]) and "Яростная атака" in special)
	var bc: Dictionary = hud._building_card("tower")
	verdict("I-здание: столбик и «Тип»", (bc.get("stats", []) as Array).size() >= 2
		and str(bc.get("info", [])).contains("Тип"))
	# Карточка найма крепости — без «ветераном» и «Содержание»
	var src: String = FileAccess.get_file_as_string("res://scripts/HUD.gd")
	verdict("I-найм: строк «Выходит готовым ветераном»/«Содержание: еды» в коде нет",
		not src.contains("lines.append(\"Выходит готовым ветераном") and not src.contains("\"Содержание: еды"))

# ─────────────────────────────────────────────────────────────────────────────
func _j_banners() -> void:
	print("\n═════ J. ЗВАНИЯ И ЗНАМЁНА ═════")
	var names := []
	for l in range(0, 8):
		names.append(_UCfg.rank_title(l))
	verdict("J1 звания: 1-3 Опытные, 4-6 Ветераны, 7 Легендарные",
		names == ["Новобранцы", "Опытные", "Опытные", "Опытные", "Ветераны", "Ветераны", "Ветераны", "Легендарные"],
		str(names))
	var t1: Dictionary = _UCfg.veteran_banner_tier(2)
	var t5: Dictionary = _UCfg.veteran_banner_tier(5)
	verdict("J2 1-3 — красный треугольник, 4-6 — синий треугольник",
		int(t1["shape"]) == _UCfg.BANNER_PENNANT and int(t5["shape"]) == _UCfg.BANNER_PENNANT
		and (t1["cloth"] as Color).r > 0.5 and (t5["cloth"] as Color).b > 0.5)
	var at := Vector3(-30, 0, -100)
	_clear(at, 20.0)
	var sid: int = _squad("spearman", at, 6)
	var top: int = _UCfg.max_veteran_level("spearman")
	(GameManager.squads[sid] as Dictionary)["level"] = top - 1
	(GameManager.squads[sid] as Dictionary)["elite"] = true
	# РАЗВОРОТ ТЗ 22.10.2026: штандарт — по личной награде игрока ("elite"),
	# высший ранг шкалы сам его не даёт (прежде J3/J4 утверждали обратное)
	verdict("J3 награда игрока («elite») даёт штандарт и без высшего ранга", GameManager.squad_elite(sid))
	(GameManager.squads[sid] as Dictionary)["level"] = top
	(GameManager.squads[sid] as Dictionary)["elite"] = false
	verdict("J4 легендарный без награды — вымпел, не штандарт", not GameManager.squad_elite(sid))
	var gsid: int = _squad("goblin_spearman", at + Vector3(10, 0, 0), 6, G)
	(GameManager.squads[gsid] as Dictionary)["level"] = 3
	GameManager.refresh_squad_banner(gsid)
	await pframes(2)
	var ban = (GameManager.squads[gsid] as Dictionary).get("banner")
	verdict("J5 у орды — рваные язычки, не вымпел с лычками",
		ban != null and is_instance_valid(ban) and bool(ban.get("shown_goblin")))
	(GameManager.squads[gsid] as Dictionary)["level"] = top
	verdict("J6 у орды штандарта нет и на высшем ранге", not GameManager.squad_elite(gsid))
	for m in _members(sid) + _members(gsid):
		m.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
func _k_audit() -> void:
	print("\n═════ K. НАХОДКИ АУДИТА ЛОГА ═════")
	var mine: Mine = null
	for b in get_tree().get_nodes_in_group("all_buildings"):
		if b is Mine:
			mine = b
			break
	if mine != null:
		mine.set_owner_faction(E)
		var a: Unit = _spawn("archer", mine.global_position + Vector3(0, 0, 14))
		GameManager.add_to_squad(GameManager.new_squad(F, "archer"), a)
		a.set_attack_target(mine)
		await pframes(2)
		mine._die()
		await pframes(2)
		verdict("K1 снос рудника — подписка снята", not mine.died.is_connected(a._on_attack_target_died))
		# Снова целится в рудник, потом переключается на бойца; второй снос
		# рудника чужую цель не трогает
		mine.set_owner_faction(E)
		a.set_attack_target(mine)
		var foe := _spawn("goblin_spearman", mine.global_position + Vector3(4, 0, 14), G)
		foe.set_tick(false)
		a.set_attack_target(foe)
		mine.set_owner_faction(E)
		mine._die()
		await pframes(2)
		verdict("K2 второй снос рудника не снимает текущую цель", a.attack_target == foe)
		a.queue_free()
		foe.queue_free()
	# ИИ не переспрашивает недостижимую точку
	var u := _spawn("spearman", Vector3(60, 0, -20), E)
	GameManager.add_to_squad(GameManager.new_squad(E, "spearman"), u)
	var goal := Vector3(70, 0, -20)
	u.command_move(goal)
	u._giveup_goal = goal
	u._giveup_until_ms = Unit.game_ms() + 30000
	var sk0: int = Unit.giveup_orders_skipped
	u.command_move(goal + Vector3(1, 0, 0))
	verdict("K3 приказ ИИ в недостижимую точку не переисполняется", Unit.giveup_orders_skipped == sk0 + 1)
	u.command_move(goal + Vector3(20, 0, 0))
	verdict("K4 приказ ИИ в другую точку исполняется", Unit.giveup_orders_skipped == sk0 + 1)
	u.queue_free()
