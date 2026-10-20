extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 12.10.2026: экономика мяса, лимит, победа, рыцари, туши, интерфейс
## ═══════════════════════════════════════════════════════════════════════════
## A — лимит отрядов жёсткий: живые + заказанные, рыцари — один слот.
## B — едят головы: расход = головы × ставка (рыцарь × множитель), монах ест.
## C — победа: все постройки красного и орды снесены (рудник и пень не в счёт).
## D — рыцари: серия 10 ударов, +5 от «Неистовства».
## E — брод: после выхода из брода дорога не возвращается на старый берег.
## F — деревья: запас ×10; толпа орды шире (HORDE_SPREAD).
## G — интерфейс: подсказки A/C/S/F1 — одна строка; подписи строя; нож у мяса;
##     панель по центру; загон N/5 и выработка; рудник: значок, доход, вывод.
## H — рисунок зданий сдвинут к камере (кольцо вокруг рисунка).
## ── второе письмо 12.10.2026 ──
## I — брод: отряд с дальнего берега доходит (дорога после брода — от выхода).
## J — режим [A]: ЛКМ снимает режим и выделение; ПКМ-клик — марш с боем;
##     протяжка ПКМ в [A] — строй по линии, у каждого отряда своя точка.
## K — загон: 10 мест и 10 рабочих.
## L — панель армии: в развороте рода нет портрета и приёмов, сетка ≤ 10 в ряд.
## M — орда: стартовый резерв на площадке, пауза между волнами 7-10 мин.
## Запуск: godot --headless --path . res://qa_tz1012/Test.tscn [-- only=abcdefgh]

const P := Constants.FACTION_PLAYER
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _Tower := preload("res://scripts/Tower.gd")

var main = null
var _pass := 0
var _fail := 0
var _only := "abcdefghijklm"
var _done := false

func _ready() -> void:
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
	print("\n═════ ИТОГ qa_tz1012: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, n: int, at: Vector3) -> int:
	var sid: int = GameManager.new_squad(P, kind)
	for i in range(n):
		var u := _spawn(kind, P, at + Vector3(float(i % 6) * 0.8, 0, float(i / 6) * 0.8))
		GameManager.add_to_squad(sid, u)
		u.set_tick(false)
	return sid

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if _only.contains("a"): await _block_a()
	if _only.contains("g"): await _block_g()
	if _only.contains("h"): _block_h()
	if _only.contains("d"): _block_d()
	if _only.contains("e"): _block_e()
	if _only.contains("f"): _block_f()
	if _only.contains("b"): await _block_b()
	if _only.contains("i"): await _block_i()
	if _only.contains("j"): await _block_j()
	if _only.contains("k"): _block_k()
	if _only.contains("l"): await _block_l()
	if _only.contains("m"): _block_m()
	if _only.contains("c"): await _block_c()
	_finish()

# ── A. ЛИМИТ ─────────────────────────────────────────────────────────────────
func _block_a() -> void:
	print("\n═════ A. ЛИМИТ ОТРЯДОВ ═════")
	GameManager.pop_limit_enabled = true
	var lim: int = GameManager.pop_squad_limit(P)
	var base := Vector3(-40, 0, 60)
	var k := 0
	var last: int = -1
	while GameManager.pop_army_squads(P) < lim and k < 200:
		last = _squad("archer", 1, base + Vector3(float(k % 10) * 3.0, 0, float(k / 10) * 3.0))
		k += 1
	verdict("A1 при «отрядов = лимит» новый отряд рыцарей не заказать",
		not GameManager.pop_allows(P, "warrior"),
		"отрядов %d, лимит %d, голов %d из %d" % [GameManager.pop_army_squads(P), lim,
			GameManager.pop_army_used(P), GameManager.pop_army_cap(P)])
	verdict("A2 и лучников (30 голов) тоже — лимит в отрядах жёсткий",
		not GameManager.pop_allows(P, "archer"))
	if last > 0:
		for m in (GameManager.squads[last]["members"] as Array).duplicate():
			(m as Unit).take_damage(1.0e9)
	await pframes(3)
	verdict("A3 освободился слот — рыцарей можно (один слот)", GameManager.pop_allows(P, "warrior"),
		"отрядов %d, лимит %d" % [GameManager.pop_army_squads(P), lim])
	GameManager.pop_limit_enabled = false

# ── B. ЕДА ───────────────────────────────────────────────────────────────────
func _block_b() -> void:
	print("\n═════ B. ЕДЯТ ГОЛОВЫ ═════")
	var base := Vector3(-60, 0, 40)
	_squad("spearman", 20, base)
	_squad("warrior", 10, base + Vector3(10, 0, 0))
	_squad("monk", 1, base + Vector3(20, 0, 0))
	await pframes(90)
	var heads := 0.0
	var workers := 0
	var monk_heads := 0.0
	for sid in GameManager.squads:
		var sq: Dictionary = GameManager.squads[sid]
		if int(sq["faction"]) != P or (sq["members"] as Array).is_empty():
			continue
		if String(sq["type"]) == "worker":
			workers += (sq["members"] as Array).size()
			continue
		var h: float = float((sq["members"] as Array).size()) \
			* float(_UCfg.FOOD_UPKEEP_UNIT_MULT.get(String(sq["type"]), 1.0))
		heads += h
		if String(sq["type"]) == "monk":
			monk_heads += h
	var want: float = heads * _UCfg.FOOD_UPKEEP_SOLDIER_PER_SEC + float(workers) * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC
	var got: float = float(GameManager.food_upkeep_rate.get(P, 0.0))
	verdict("B1 расход еды = головы × ставка (рыцарь ×%.1f) + рабочие" % float(_UCfg.FOOD_UPKEEP_UNIT_MULT.get("warrior", 1.0)),
		absf(got - want) < 0.01, "%.3f против %.3f в секунду" % [got, want])
	verdict("B2 монах в счёте голов", monk_heads >= 1.0, "%.0f" % monk_heads)

# ── C. ПОБЕДА ────────────────────────────────────────────────────────────────
func _alive_blds(group: String) -> Array:
	var o: Array = []
	for b in get_tree().get_nodes_in_group(group):
		if main.counts_for_victory(b):
			o.append(b)
	return o

func _block_c() -> void:
	print("\n═════ C. ПОБЕДА — ПОСТРОЙКИ КРАСНОГО И ОРДЫ ═════")
	var red_g: String = Constants.building_group(Constants.FACTION_ENEMY)
	var gob_g: String = Constants.building_group(Constants.FACTION_GOBLIN)
	var red: Array = _alive_blds(red_g)
	var gob: Array = _alive_blds(gob_g)
	var skipped := 0
	for g in [Constants.FACTION_ENEMY, Constants.FACTION_GOBLIN, Constants.FACTION_NEUTRAL]:
		for b in get_tree().get_nodes_in_group(Constants.building_group(g)):
			if (b is Mine or (b is Building and String((b as Building).building_id) == "troll_lair")) \
					and not main.counts_for_victory(b):
				skipped += 1
	verdict("C0 рудники и пни в условие не входят", skipped > 0, "пропущено %d" % skipped)
	verdict("C1 пока стоят постройки — победы нет", not main._ai_beaten(), "красных %d, орды %d" % [red.size(), gob.size()])
	for b in red:
		(b as Building).take_damage(1.0e9)
	await pframes(5)
	var gob2: Array = _alive_blds(gob_g)
	verdict("C2 красный снесён, орда стоит — победы нет", not gob2.is_empty() and not main._ai_beaten(), "орды %d" % gob2.size())
	for _i in range(6):
		var rest: Array = _alive_blds(gob_g) + _alive_blds(red_g)
		if rest.is_empty():
			break
		for b in rest:
			(b as Building).take_damage(1.0e9)
		await pframes(3)
	var left: int = _alive_blds(gob_g).size() + _alive_blds(red_g).size()
	var units_left := 0
	for n in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_GOBLIN)):
		if n is Unit and not (n as Unit).is_dead():
			units_left += 1
	verdict("C3 всё снесено — победа (юниты орды не мешают)", left == 0 and main._ai_beaten(),
		"построек осталось %d, живых гоблинов %d" % [left, units_left])

# ── D. РЫЦАРИ ────────────────────────────────────────────────────────────────
func _block_d() -> void:
	print("\n═════ D. ЯРОСТНАЯ АТАКА ═════")
	var k = _spawn("warrior", P, Vector3(-50, 0, 20))
	verdict("D1 серия без кузницы — 10 ударов", int(k.rage_hits_total()) == 10, "%d" % int(k.rage_hits_total()))
	var n3: Dictionary = _Forge.get_node("warrior_3d")
	verdict("D2 «Неистовство» даёт +5 (итого 15)", float(n3.get("bonus_rage_hits", 0.0)) == 5.0,
		str(n3.get("bonus_rage_hits", 0.0)))
	var cd: float = float(_UCfg.STATS["warrior"]["attack_cooldown"])
	verdict("D3 срок серии вмещает 15 быстрых ударов",
		float(k.RAGE_SEC) >= 15.0 * cd * float(k.RAGE_COOLDOWN_MULT), "%.1f с" % float(k.RAGE_SEC))

# ── E. БРОД ──────────────────────────────────────────────────────────────────
func _block_e() -> void:
	print("\n═════ E. ДОРОГА ПОСЛЕ БРОДА ═════")
	var from := Vector3(-20, 0, 40)
	var goal := Vector3(90, 0, 40)
	var sid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "big_goblin")
	for i in range(5):
		var u := _spawn("big_goblin", Constants.FACTION_GOBLIN, from + Vector3(float(i), 0, 0))
		GameManager.add_to_squad(sid, u)
		u.set_tick(false)
	var r: PackedVector3Array = GameManager.build_route(from, goal, 0.0, Vector2.ZERO, 3.5, sid)
	var fe: int = GameManager.route_ford_entry
	var rx: float = main.river_x(0.0)
	var back := false
	if fe >= 0:
		for i in range(fe + 2, r.size()):
			if (r[i].x - rx) * (goal.x - rx) < 0.0:
				back = true
	verdict("E1 маршрут через брод не возвращается на старый берег", fe >= 0 and not back, str(r))

# ── F. ДЕРЕВЬЯ, ТОЛПА ────────────────────────────────────────────────────────
func _block_f() -> void:
	print("\n═════ F. ДЕРЕВЬЯ И ТОЛПА ═════")
	var mn := 1e9
	var n := 0
	for t in get_tree().get_nodes_in_group("resource_nodes"):
		if t is ResourceNode and int((t as ResourceNode).resource_type) == Constants.RESOURCE_WOOD:
			mn = minf(mn, (t as ResourceNode).remaining)
			n += 1
	verdict("F1 запас дерева ≥ 4800 (×10)", n > 0 and mn >= 4800.0 * 0.99, "деревьев %d, минимум %.0f" % [n, mn])
	verdict("F2 толпа орды раздвинута", _GobCfg.HORDE_SPREAD > 1.0, str(_GobCfg.HORDE_SPREAD))

# ── G. ИНТЕРФЕЙС ─────────────────────────────────────────────────────────────
func _block_g() -> void:
	print("\n═════ G. ИНТЕРФЕЙС ═════")
	var hud = main.hud
	var btn := Button.new()
	hud.add_child(btn)
	hud._show_scmd_hint(btn, "C")
	verdict("G1 подсказка [C] — одна строка «Вольно [C]»", hud.scmd_hint_text() == "Вольно [C]", hud.scmd_hint_text())
	hud._show_scmd_hint(btn, "F1")
	verdict("G2 подсказка [F1] — «Отступить в замок [F1]»", hud.scmd_hint_text() == "Отступить в замок [F1]", hud.scmd_hint_text())
	hud._hide_scmd_hint()
	btn.queue_free()
	var fp = main.minimap.formation_panel
	verdict("G3 подписи строя", fp.TIPS == ["1 - Широкий фронт", "2 - Глубокий фронт", "3 - Смена юнитов в авангарде"] and int(fp.TIP_FONT) <= 11, str(fp.TIPS))
	fp._show_tip(1)
	var tip = fp._tip
	var tip_ok: bool = tip != null and tip.visible and tip.global_position.y + tip.size.y <= fp.global_position.y + 0.5
	verdict("G4 подпись строя — над окошком", tip_ok, fp.tip_text())
	fp._show_tip(-1)
	verdict("G5 у мяса — нож", String(hud.RES_TOOL_GLYPHS[Constants.RESOURCE_FOOD]) == "🔪")
	var sid: int = _squad("spearman", 6, Vector3(-50, 0, 10))
	var men: Array = (GameManager.squads[sid]["members"] as Array).duplicate()
	main.selection_manager.select_units(men)
	await get_tree().process_frame
	await get_tree().process_frame
	var r: Rect2 = hud._bottom_panel.get_global_rect()
	var vw: float = hud.get_viewport().get_visible_rect().size.x
	verdict("G6 нижняя панель отряда — по центру экрана", absf(r.get_center().x - vw * 0.5) <= 2.0,
		"центр %.0f, экран %.0f" % [r.get_center().x, vw * 0.5])
	var pen: Building = load("res://scripts/SheepPen.gd").new()
	pen.faction = P
	main.world_add(pen)
	pen.global_position = Vector3(-70, GameManager.get_terrain_height(-70, -10), -10)
	await pframes(3)
	main.selection_manager.select_units([pen])
	await get_tree().process_frame
	var dt: String = hud.detail_text()
	# РАЗВОРОТ ТЗ 14.10.2026, п. 2: загон компактно — итог прироста зелёной
	# строкой, рабочие — иконкой «N/M» в ряду кнопок
	var pen_cnt := ""
	for lb in hud.button_container.find_children("CountLabel", "Label", true, false):
		pen_cnt = (lb as Label).text
	verdict("G7 загон: рабочие «N/M» иконкой и итог еды в минуту",
		dt.contains("еды в минуту") and pen_cnt == "0/%d" % _UCfg.SHEEP_PEN_WORKERS, dt + " | " + pen_cnt)
	var mine: Mine = null
	for b in GameManager.nodes_in_group_cached(Constants.building_group(Constants.FACTION_NEUTRAL)):
		if b is Mine:
			mine = b
			break
	if mine == null:
		verdict("G8 ничейный рудник найден", false)
		return
	mine.set_owner_faction(P)
	var ws: Array = []
	for i in range(3):
		var w := _spawn("worker", P, mine.global_position + Vector3(4, 0, 4))
		GameManager.add_to_squad(GameManager.new_squad(P, "worker"), w)
		mine._absorb(w)
		ws.append(w)
	await pframes(90)
	verdict("G8 золото: рабочие рудника в счёте, значок рудника и доход",
		int(hud.mine_stat["mines"]) >= 1 and int(hud.mine_stat["workers"]) == 3 and float(hud.mine_stat["per_min"]) > 0.0
		and hud._mine_box.visible, str(hud.mine_stat))
	main.selection_manager.select_units([mine])
	await get_tree().process_frame
	var mine_cnt := ""
	for lb in hud.button_container.find_children("CountLabel", "Label", true, false):
		mine_cnt = (lb as Label).text
	verdict("G9 панель рудника: рабочие 3/5 иконкой, доход строкой",
		mine_cnt == "3/%d" % Mine.WORKER_CAP and hud.detail_text().contains("золота в минуту"),
		hud.detail_text() + " | " + mine_cnt)
	hud._on_mine_release(mine)
	verdict("G10 кнопка рабочих выводит их из рудника", mine.workers.is_empty() and not (ws[0] as Unit).garrisoned,
		"внутри %d" % mine.workers.size())
	main.selection_manager.select_units([])

# ── H. РИСУНОК ЗДАНИЙ ────────────────────────────────────────────────────────
func _block_h() -> void:
	print("\n═════ H. РИСУНОК ПО ЦЕНТРУ ЗОНЫ ═════")
	var tw: Building = _Tower.new()
	tw.faction = P
	main.world_add(tw)
	tw.global_position = Vector3(-80, GameManager.get_terrain_height(-80, 30), 30)
	var spr := tw.get_node_or_null("BuildingSprite") as Node3D
	verdict("H1 рисунок башни сдвинут к камере", spr != null and spr.position.z > 0.3 and is_equal_approx(spr.position.z, tw._draw_z),
		"%.2f" % (spr.position.z if spr != null else -1.0))
	verdict("H2 рамка выделения — в плоскости рисунка",
		tw.selection_ring != null and absf(tw.selection_ring.position.z - tw._draw_z - Building.MARKER_Z_LIFT) < 0.01)

# ── I. БРОД: ДАЛЬНИЙ БЕРЕГ ───────────────────────────────────────────────────
func _block_i() -> void:
	print("\n═════ I. МАРШ ЧЕРЕЗ БРОД С ДАЛЬНЕГО БЕРЕГА ═════")
	var ax: float = main.river_x(0.0)
	var sid: int = _squad("spearman", 24, Vector3(ax - 45.0, 0, 35.0))
	var men: Array = (GameManager.squads[sid]["members"] as Array).duplicate()
	for m in men:
		(m as Unit).set_tick(true)
	main.selection_manager.select_units(men)
	main.selection_manager.order_at_world(Vector3(ax + 60.0, 0, 30.0), false)
	await pframes(60 * 60)
	var near := 0
	for m in men:
		var u := m as Unit
		if is_instance_valid(u) and Vector2(u.global_position.x - u.post_pos.x, u.global_position.z - u.post_pos.z).length() < 4.0:
			near += 1
	verdict("I1 отряд с дальнего берега дошёл через брод (≥ 20 из 24)", near >= 20, "%d" % near)
	main.selection_manager.select_units([])

# ── J. РЕЖИМ [A] ─────────────────────────────────────────────────────────────
func _mouse(btn: int, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = at
	return e

func _block_j() -> void:
	print("\n═════ J. РЕЖИМ [A]: ЛКМ/ПКМ ═════")
	var sm = main.selection_manager
	var cmd = sm._squad_cmd()
	var a: int = _squad("spearman", 12, Vector3(-120, 0, 40))
	var b: int = _squad("spearman", 12, Vector3(-120, 0, 46))
	var men: Array = (GameManager.squads[a]["members"] as Array) + (GameManager.squads[b]["members"] as Array)
	sm.select_units(men)
	sm.set_attack_move_armed(true)
	var cam: Camera3D = main.get("_camera") as Camera3D
	var c2: Vector2 = cam.unproject_position(Vector3(-110, 0, 40))
	sm._press_over_ui = false
	sm.drag_start = c2
	sm._unhandled_input(_mouse(MOUSE_BUTTON_LEFT, false, c2))
	verdict("J1 ЛКМ во взведённом [A] снимает режим и выделение",
		not sm.attack_move_armed and sm.selected_units.is_empty(), "взведён=%s, выделено %d" % [str(sm.attack_move_armed), sm.selected_units.size()])
	sm.select_units(men)
	sm.set_attack_move_armed(true)
	sm._rmb_press_over_ui = false
	sm._unhandled_input(_mouse(MOUSE_BUTTON_RIGHT, true, c2))
	sm._unhandled_input(_mouse(MOUSE_BUTTON_RIGHT, false, c2))
	verdict("J2 ПКМ-клик во взведённом [A] — марш с боем обоим отрядам",
		cmd._am.has(a) and cmd._am.has(b) and not sm.attack_move_armed, "в [A]: %s" % str(cmd._am.keys()))
	sm.select_units(men)
	sm.set_attack_move_armed(true)
	var n: int = sm.attack_move_line(Vector3(-130, 0, 60), Vector3(-100, 0, 60))
	var da: Vector3 = (cmd._am.get(a, {}) as Dictionary).get("dest", Vector3.ZERO)
	var db: Vector3 = (cmd._am.get(b, {}) as Dictionary).get("dest", Vector3.ZERO)
	verdict("J3 протяжка ПКМ в [A]: строй по линии, у каждого отряда своя точка",
		n == 2 and da.distance_to(db) > 5.0, "точки %s и %s" % [str(da), str(db)])
	sm.select_units([])

# ── K. ЗАГОН 10/10 ───────────────────────────────────────────────────────────
func _block_k() -> void:
	print("\n═════ K. ЗАГОН НА 10 ═════")
	verdict("K1 загон на 10 овец и 10 рабочих", _UCfg.SHEEP_PEN_CAPACITY == 10 and _UCfg.SHEEP_PEN_WORKERS == 10,
		"%d / %d" % [_UCfg.SHEEP_PEN_CAPACITY, _UCfg.SHEEP_PEN_WORKERS])

# ── L. ПАНЕЛЬ АРМИИ ──────────────────────────────────────────────────────────
func _block_l() -> void:
	print("\n═════ L. ПАНЕЛЬ АРМИИ ═════")
	var hud = main.hud
	var sm = main.selection_manager
	var sids: Array = []
	var all: Array = []
	for i in range(13):
		var sid: int = _squad("archer", 2, Vector3(-140 + float(i % 10) * 2.5, 0, 70 + float(i / 10) * 2.5))
		sids.append(sid)
		all.append_array(GameManager.squads[sid]["members"])
	var sp: int = _squad("spearman", 2, Vector3(-140, 0, 80))
	all.append_array(GameManager.squads[sp]["members"])
	sm.select_units(all)
	await get_tree().process_frame
	hud._parent_sids = sids + [sp]
	hud._expand_type_from_parent("archer")
	await get_tree().process_frame
	await get_tree().process_frame
	verdict("L1 в развороте рода нет большой иконки слева", not hud._portrait_wrap.visible)
	var abil := 0
	for c in hud.button_container.get_children():
		if String(c.name).begins_with("Ability") or (c is Button and String((c as Button).tooltip_text).contains("приём")):
			abil += 1
	verdict("L2 у 13 отрядов нет кнопок приёмов в ряду команд", hud.button_container.get_child_count() == 0 or abil == 0,
		"кнопок в сетке %d" % hud.button_container.get_child_count())
	verdict("L3 сетка карточек — не больше 10 в ряд", int(hud._squad_strip.columns) == 10, "колонок %d" % int(hud._squad_strip.columns))
	sm.select_units([])

# ── M. ОРДА: РЕЗЕРВ И ТЕМП ───────────────────────────────────────────────────
func _block_m() -> void:
	print("\n═════ M. ОРДА: РЕЗЕРВ И ТЕМП ═════")
	var g = main.goblin_ai
	var Sp = load("res://scripts/spawn_config.gd")
	# Вожак в стенде выключен (set_process(false)) — резерв рожаем его же функцией
	if not bool(g._reserve_done):
		g._spawn_start_reserve()
	verdict("M1 стартовый резерв родился на площадке (10 отрядов)",
		int(g.reserve_spawned) == (Sp.START_RESERVE as Array).size() and (g.muster as Dictionary).size() >= int(g.reserve_spawned),
		"резерв %d, на площадке %d" % [int(g.reserve_spawned), (g.muster as Dictionary).size()])
	verdict("M2 темп волн 7-10 минут", float(Sp.WAVE_GAP_MIN_SEC) >= 420.0 and float(Sp.WAVE_GAP_MAX_SEC) <= 600.0)
