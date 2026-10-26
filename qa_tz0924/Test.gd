extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТЗ 24.09.2026 — ЗАГОН, КОННИЦА, UI, СБОР ИИ, БРОД, КУЗНИЦА, МОНАХ, ЛЕС
## ═══════════════════════════════════════════════════════════════════════════
##   A — ЗАГОН: пять овец сразу; ПКМ десятью рабочими ставит ровно пятерых,
##       остальные сохраняют прежний приказ; снос убивает живых; пепелище
##       ложится плашмя в центр загона; респавн считает живых.
##   B — КОННИЦА: доля запаса мимо брони; тыл 50 %, фланг 25 %; лоб на копья —
##       первая волна 50 % своего запаса, следующая 25 %.
##   C — КУЗНИЦА: секунд «к циклу добычи» больше нет; мясо, груз и шаг —
##       доли, и доли доезжают до рабочего.
##   D — UI: иконки вместо «раб.»/«армия», число отрядов, красный расход еды.
##   E — СБОР ПЕРЕД УДАРОМ: группа сперва встаёт в линию, потом бьёт разом.
##   F — ЛЕС-СТЕНА: полоса с двумя проходами, непроходима для шага и A*,
##       отряд обходит её проходом, рабочий рубит кромку.
##   G — МЕЛОЧИ: копейщик по ступням, интервал выхода, брод без декора.
##
## Запуск: godot --headless --path . res://qa_tz0924/Test.tscn

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _ForgeT := preload("res://scripts/forge_config.gd")
const _CavT := preload("res://scripts/units/CavalryImpactHandler.gd")
const _StagerT := preload("res://scripts/goblin/WaveStager.gd")
const _CSiteT := preload("res://scripts/ConstructionSite.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var only: String = "abcdefg"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(420.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
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

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz0924: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int = 5, gap: float = 0.7) -> Array:
	var sid: int = GameManager.new_squad(f, uid)
	var out: Array = []
	for i in range(n):
		var u := _unit(uid, f, at + Vector3(float(i % cols) * gap, 0.0, float(i / cols) * gap))
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

## Базовая точка стенда: внутри зоны игрока, в стороне от стен и базы
func _spot() -> Vector3:
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	return Vector3(a.x + 30.0, 0.0, a.z + 24.0)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for w in get_tree().get_nodes_in_group("all_units"):
		if w is Unit and (w as Unit).faction != Constants.FACTION_PLAYER:
			(w as Unit).set_tick(false)
	await pframes(4)
	if "a" in only: await _block_pen()
	if "b" in only: await _block_cavalry()
	if "c" in only: _block_forge()
	if "d" in only: await _block_ui()
	if "e" in only: await _block_stager()
	if "f" in only: await _block_forest()
	if "g" in only: _block_misc()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ЗАГОН
# ═════════════════════════════════════════════════════════════════════════════
func _pen_sheep(pen: Node, live_only: bool) -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s) or s.get("pen") != pen:
			continue
		if bool(s.get("eaten")):
			continue
		if live_only and bool(s.get("dead")):
			continue
		out.append(s)
	return out

func _block_pen() -> void:
	print("\n═════ A. ЗАГОН ═════")
	var at: Vector3 = _spot()
	var pen: Building = _CSiteT.make_building("sheep_pen")
	pen.faction = Constants.FACTION_PLAYER
	pen.set("stock_on_ready", true)
	main.world_add(pen)
	pen.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	await pframes(4)
	var live: int = int(pen.call("live_count"))
	verdict("A1 новый загон сразу с %d овцами" % _UCfgT.SHEEP_PEN_CAPACITY,
		live == _UCfgT.SHEEP_PEN_CAPACITY, "живых %d" % live)
	# Десять рабочих, у каждого — свой прежний приказ (марш в точку)
	var workers: Array = []
	for i in range(10):
		var w := _unit("worker", Constants.FACTION_PLAYER, at + Vector3(-12.0 + float(i) * 1.2, 0.0, 10.0))
		GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "worker"), w)
		workers.append(w)
	await pframes(2)
	var goals: Dictionary = {}
	for i in range(workers.size()):
		var g: Vector3 = at + Vector3(-14.0 + float(i) * 1.5, 0.0, 22.0)
		(workers[i] as Unit).command_move(g, false, Vector3.ZERO, false, true)
		goals[workers[i]] = (workers[i] as Unit).post_pos
	await pframes(2)
	var sm = main.selection_manager
	sm.selected_units = workers.duplicate()
	var n: int = int(sm._assign_pen_farmers(pen))
	await pframes(2)
	var farming := 0
	var kept := 0
	for w2 in workers:
		var ww := w2 as Worker
		if ww.farm_pen() == pen:
			farming += 1
		elif ww.state == Unit.State.MOVING and ww.post_pos.distance_to(goals[ww]) < 0.5:
			kept += 1
	verdict("A2 ПКМ десятью рабочими по загону ставит ровно пятерых",
		n == _UCfgT.SHEEP_PEN_WORKERS and farming == _UCfgT.SHEEP_PEN_WORKERS,
		"поставлено %d, фермеров %d" % [n, farming])
	verdict("A3 остальные пятеро сохранили прежний приказ", kept == 10 - farming,
		"сохранили %d из %d" % [kept, 10 - farming])
	# Повторный ПКМ никого не добавляет
	var n2: int = int(sm._assign_pen_farmers(pen))
	verdict("A4 полный загон новых фермеров не берёт", n2 == 0, "добавлено %d" % n2)
	# Работа идёт: за минуту игрового времени хоть одна овца забита
	var g0 := 0
	while g0 < 60 * 40 and _pen_sheep(pen, true).size() >= _UCfgT.SHEEP_PEN_CAPACITY:
		await get_tree().physics_frame
		g0 += 1
	var dead_n: int = _pen_sheep(pen, false).size() - _pen_sheep(pen, true).size()
	verdict("A5 фермеры режут овец загона", dead_n >= 1 or _pen_sheep(pen, false).size() < _UCfgT.SHEEP_PEN_CAPACITY,
		"туш %d за %d кадров" % [dead_n, g0])
	# Респавн считает живых: подкрутили часы — одна новая
	var before_live: int = int(pen.call("live_count"))
	pen.call("_tick_restock", _UCfgT.SHEEP_PEN_RESPAWN_SEC + 0.1)
	var after_live: int = int(pen.call("live_count"))
	verdict("A6 пока туша лежит, загон восполняет живых", after_live == mini(before_live + 1, _UCfgT.SHEEP_PEN_CAPACITY),
		"живых %d → %d" % [before_live, after_live])
	# Второе письмо 24.09.2026 развернуло окно 20-30 с в «каждые 5 с»
	verdict("A7 пауза респавна — 5 с (второе письмо 24.09)",
		is_equal_approx(_UCfgT.SHEEP_PEN_RESPAWN_SEC, 5.0))
	# Снос: живые гибнут, пепелище плашмя в центре
	var live_before: Array = _pen_sheep(pen, true)
	var pen_pos: Vector3 = pen.global_position
	pen.call("_die")
	await pframes(3)
	var still_alive := 0
	for s in live_before:
		if is_instance_valid(s) and not bool(s.get("dead")):
			still_alive += 1
	verdict("A8 снос загона: живые овцы гибнут тушами", still_alive == 0 and live_before.size() > 0,
		"живых осталось %d из %d" % [still_alive, live_before.size()])
	var ruin: Node3D = null
	for r in get_tree().get_nodes_in_group("ruins"):
		if r is Node3D and (r as Node3D).global_position.distance_to(pen_pos) < 0.5:
			ruin = r
	var flat := false
	var centred := false
	if ruin != null:
		var rs: MeshInstance3D = ruin.get_node_or_null("RuinSprite") as MeshInstance3D
		flat = rs != null and rs.mesh is ArrayMesh
		if flat:
			var aabb: AABB = rs.mesh.get_aabb()
			var c: Vector3 = aabb.get_center()
			centred = absf(c.x) < 0.3 and absf(c.z) < 0.3 and aabb.size.y < 2.0
	verdict("A9 пепелище загона лежит плашмя по центру ограды", flat and centred,
		"руина=%s, плашмя=%s, по центру=%s" % [str(ruin != null), str(flat), str(centred)])
	for w3 in workers:
		if is_instance_valid(w3):
			(w3 as Unit).take_damage(99999.0)
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. КОННИЦА
# ═════════════════════════════════════════════════════════════════════════════
func _block_cavalry() -> void:
	print("\n═════ B. КОННИЦА ═════")
	var at: Vector3 = _spot() + Vector3(0.0, 0.0, -18.0)
	var sp := _unit("spearman", Constants.FACTION_PLAYER, at)
	sp.take_frac_damage(0.5)
	verdict("B1 доля запаса снимается ровно, мимо брони",
		absf(sp.current_health - sp.max_health * 0.5) < 0.01,
		"%.1f из %.1f" % [sp.current_health, sp.max_health])
	sp.take_damage(99999.0)
	verdict("B2 доли секторов: тыл 50 %, фланг 25 %",
		is_equal_approx(_CavT.sector_frac(_CavT.SECTOR_REAR), 0.5)
		and is_equal_approx(_CavT.sector_frac(_CavT.SECTOR_FLANK), 0.25))
	# ── Удар в тыл строя: все накрытые теряют половину запаса ─────────────
	_CavT.reset_stats()
	var line: Array = _squad("spearman", Constants.FACTION_PLAYER, at + Vector3(10.0, 0.0, 0.0), 10, 5, 0.7)
	for u in line:
		(u as Unit)._facing = Vector3(0.0, 0.0, 1.0)
	await pframes(3)
	var rider := _unit("goblin_rider", Constants.FACTION_GOBLIN, at + Vector3(11.4, 0.0, -1.0))
	rider.set_tick(false)
	await pframes(2)
	rider._charge_from = rider.global_position - Vector3(0.0, 0.0, 30.0)
	rider._charge_path = 30.0
	rider._charge_ready = true
	var tgt: Unit = line[1]
	rider._charge_impact(tgt, Vector3(0.0, 0.0, 1.0))
	await pframes(2)
	var hit := 0
	var half_ok := 0
	for u2 in line:
		if not is_instance_valid(u2):
			hit += 1; half_ok += 1
			continue
		var uu := u2 as Unit
		if uu.is_dead() or uu.current_health < uu.max_health - 0.1:
			hit += 1
			if uu.is_dead() or uu.current_health <= uu.max_health * 0.5 + 0.1:
				half_ok += 1
	verdict("B3 удар в тыл: накрытые копейщики теряют по 50 %% запаса",
		int(_CavT.last.get("sector", -1)) == _CavT.SECTOR_REAR and hit >= 3 and half_ok == hit,
		"сектор %s, задеты %d, из них ≤50 %% — %d" % [str(_CavT.last.get("sector")), hit, half_ok])
	verdict("B4 всадник цел: копья в спину не колют", is_instance_valid(rider) and not rider.is_dead()
		and rider.current_health >= rider.max_health - 0.1)
	for u3 in line:
		if is_instance_valid(u3):
			(u3 as Unit).take_damage(99999.0)
	# ── Лоб на копья: первая волна 50 %, следующая 25 % ──────────────────
	var wall: Array = _squad("spearman", Constants.FACTION_PLAYER, at + Vector3(20.0, 0.0, 0.0), 5, 5, 0.7)
	for u4 in wall:
		(u4 as Unit)._facing = Vector3(0.0, 0.0, -1.0)
		(u4 as Unit).set_tick(false)    # сами не бьют — меряем только навал
	await pframes(2)
	var r1 := _unit("goblin_rider", Constants.FACTION_GOBLIN, at + Vector3(21.4, 0.0, -1.2))
	var r2 := _unit("goblin_rider", Constants.FACTION_GOBLIN, at + Vector3(22.0, 0.0, -1.2))
	for r in [r1, r2]:
		(r as Unit).set_tick(false)
		(r as Unit)._charge_from = (r as Unit).global_position - Vector3(0.0, 0.0, -30.0)
		(r as Unit)._charge_path = 30.0
	var r1b := _unit("goblin_rider", Constants.FACTION_GOBLIN, at + Vector3(20.6, 0.0, -1.2))
	r1b.set_tick(false)
	r1b._charge_from = r1b.global_position - Vector3(0.0, 0.0, -30.0)
	r1b._charge_path = 30.0
	r1._charge_impact(wall[1], Vector3(0.0, 0.0, 1.0))
	var f1: float = r1.current_health / r1.max_health
	r1b._charge_impact(wall[0], Vector3(0.0, 0.0, 1.0))
	verdict("B5б первая волна: второй всадник гибнет на копьях", not is_instance_valid(r1b) or r1b.is_dead())
	await get_tree().create_timer(1.7).timeout
	r2._charge_impact(wall[2], Vector3(0.0, 0.0, 1.0))
	var f2: float = r2.current_health / r2.max_health
	verdict("B5 лоб на копья: первая волна теряет 50 % своего запаса", absf(f1 - 0.5) < 0.02, "осталось %.2f" % f1)
	verdict("B6 вторая волна — 25 %", absf(f2 - 0.75) < 0.02, "осталось %.2f" % f2)
	for u5 in wall + [r1, r2, rider]:
		if is_instance_valid(u5) and not (u5 as Unit).is_dead():
			(u5 as Unit).take_damage(99999.0)
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. КУЗНИЦА
# ═════════════════════════════════════════════════════════════════════════════
func _block_forge() -> void:
	print("\n═════ C. КУЗНИЦА ═════")
	var secs: Array = []
	var keys: Dictionary = {}
	for tab in ["worker"]:
		for nd in _ForgeT.tree(tab):
			var d: Dictionary = nd
			if float(d.get("bonus_gather", 0.0)) > 0.0:
				secs.append(String(d.get("id", "")))
			for k in ["bonus_gather_wood", "bonus_gather_stone", "bonus_gather_gold",
					"bonus_gather_food", "bonus_carry_pct", "bonus_walk_loaded_pct", "bonus_train"]:
				if float(d.get(k, 0.0)) > 0.0:
					keys[k] = true
			if String(d.get("desc", "")).contains(" с к циклу"):
				secs.append(String(d.get("id", "")))
	verdict("C1 секундных узлов «к циклу добычи» в древе рабочего нет", secs.is_empty(), str(secs))
	verdict("C2 одно древо рабочего: дерево, камень, золото, мясо, груз, ход с грузом, найм",
		keys.size() == 7 and not _ForgeT.UNIT_TABS.has("economy"), str(keys.keys()))
	var surv: Array = []
	for nd2 in _ForgeT.tree("worker"):
		if float((nd2 as Dictionary).get("bonus_attack", 0.0)) > 0.0 or float((nd2 as Dictionary).get("bonus_health", 0.0)) > 0.0:
			surv.append(String((nd2 as Dictionary).get("id", "")))
	verdict("C2б у рабочего в древе нет атаки и запаса жизни", surv.is_empty(), str(surv))
	verdict("C3 новые ключи учтены в BONUS_KEYS",
		_UCfgT.BONUS_KEYS.has("bonus_gather_food") and _UCfgT.BONUS_KEYS.has("bonus_carry_pct")
		and _UCfgT.BONUS_KEYS.has("bonus_walk_pct"))
	var f: int = Constants.FACTION_PLAYER
	var w := _unit("worker", f, _spot() + Vector3(-20.0, 0.0, 0.0)) as Worker
	var cap0: float = w.carry_capacity()
	var cut0: float = w._sheep_cut_sec()
	if not GameManager.unit_bonuses.has(f):
		GameManager.unit_bonuses[f] = {}
	var prev: Variant = GameManager.unit_bonuses[f].get("worker")
	GameManager.unit_bonuses[f]["worker"] = {"bonus_carry_pct": 0.5, "bonus_gather_food": 0.3}
	GameManager.bonus_version += 1
	var cap1: float = w.carry_capacity()
	var cut1: float = w._sheep_cut_sec()
	if prev == null:
		GameManager.unit_bonuses[f].erase("worker")
	else:
		GameManager.unit_bonuses[f]["worker"] = prev
	GameManager.bonus_version += 1
	verdict("C4 доля груза доезжает до рабочего", absf(cap1 - cap0 * 1.5) < 0.2, "%.1f → %.1f" % [cap0, cap1])
	verdict("C5 ветка «мясо» ускоряет разделку", absf(cut1 - cut0 * 0.7) < 0.01, "%.3f → %.3f с" % [cut0, cut1])
	w.take_damage(99999.0)

# ═════════════════════════════════════════════════════════════════════════════
# D. UI
# ═════════════════════════════════════════════════════════════════════════════
func _block_ui() -> void:
	print("\n═════ D. ИНТЕРФЕЙС ═════")
	var hud = main.hud
	GameManager.pop_limit_enabled = true
	hud._pop_timer = 0.0
	hud._refresh_pop(0.1)
	var t1: String = String(hud._pop_label.text)
	var t2: String = String(hud._pop_army_label.text)
	verdict("D1 «раб.» и «армия» заменены иконками", not t1.contains("раб") and not t2.contains("армия")
		and hud._pop_box.get_child_count() == 4, "«%s» / «%s»" % [t1, t2])
	verdict("D2 рядом с копейщиком — отряды «есть / лимит»", t2.contains(" / ") and not t2.contains("отр."), t2)
	verdict("D3 расход еды — отдельной красной цифрой", hud._food_upkeep_label != null
		and (hud._food_upkeep_label.get_theme_color("font_color") as Color).r > 0.8
		and (hud._food_upkeep_label.get_theme_color("font_color") as Color).g < 0.5)
	var card: Dictionary = hud._unit_card("spearman", Constants.FACTION_PLAYER, {}, 60)
	# ТЗ 20.10.2026: описание — строки «Тип / Умения / Особое умение» (info)
	var joined: String = "\n".join(PackedStringArray(card.get("lines", []))) + "\n" + str(card.get("info", []))
	verdict("D4 описание копейщика — про фалангу и строй",
		joined.to_lower().contains("фаланг") and joined.to_lower().contains("строй"))

# ═════════════════════════════════════════════════════════════════════════════
# E. СБОР ПЕРЕД УДАРОМ
# ═════════════════════════════════════════════════════════════════════════════
func _block_stager() -> void:
	print("\n═════ E. СБОР ИИ ═════")
	var at: Vector3 = _spot() + Vector3(0.0, 0.0, 30.0)
	var foe_sq: Array = _squad("spearman", Constants.FACTION_PLAYER, at, 5)
	await pframes(2)
	var foe: Unit = foe_sq[0]
	var st = _StagerT.new()
	var t: float = 100.0
	var c1 := at + Vector3(-40.0, 0.0, 0.0)
	var c2 := at + Vector3(-44.0, 0.0, 12.0)
	var c3 := at + Vector3(-50.0, 0.0, -10.0)
	var a1: Dictionary = st.gate(901, c1, foe, t)
	var a2: Dictionary = st.gate(902, c2, foe, t)
	var a3: Dictionary = st.gate(903, c3, foe, t)
	verdict("E1 далёкая группа сперва идёт на линию сбора", a1.has("stage") and a2.has("stage") and a3.has("stage"))
	var sp1: Vector3 = a1.get("stage", Vector3.ZERO)
	var sp2: Vector3 = a2.get("stage", Vector3.ZERO)
	var d_foe: float = Vector2(sp1.x - foe.global_position.x, sp1.z - foe.global_position.z).length()
	verdict("E2 линия сбора — в %.0f м перед целью, места разные" % _StagerT.STAGE_DIST,
		absf(d_foe - _StagerT.STAGE_DIST) < _StagerT.SLOT_W * 2.5 and sp1.distance_to(sp2) > 4.0,
		"до цели %.1f м, между местами %.1f м" % [d_foe, sp1.distance_to(sp2)])
	# Все на местах — волна уходит РАЗОМ
	# Места в линии пересчитываются по мере роста группы: берём свежие
	t += 1.0
	var p1: Vector3 = st.gate(901, c1, foe, t).get("stage", c1)
	var p2: Vector3 = st.gate(902, c2, foe, t).get("stage", c2)
	var s3: Vector3 = st.gate(903, c3, foe, t).get("stage", c3)
	t += 2.0
	st.gate(901, p1, foe, t)
	st.gate(902, p2, foe, t)
	st.gate(903, s3, foe, t)
	sp1 = p1
	sp2 = p2
	# Следующий такт мышления: все доложились с мест
	t += 2.0
	var b1: Dictionary = st.gate(901, sp1, foe, t)
	var b2: Dictionary = st.gate(902, sp2, foe, t)
	var b3: Dictionary = st.gate(903, s3, foe, t)
	verdict("E3 собрались — атакуют все три отряда одной волной",
		b1.has("attack") and b2.has("attack") and b3.has("attack") and st.waves_released == 1,
		"волн %d" % st.waves_released)
	for u in foe_sq:
		if is_instance_valid(u):
			(u as Unit).take_damage(99999.0)
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# F. ЛЕС-СТЕНА
# ═════════════════════════════════════════════════════════════════════════════
func _block_forest() -> void:
	print("\n═════ F. ЛЕС-СТЕНА ═════")
	await pframes(3)
	var wall_n: int = int(main.wall_trees_placed)
	verdict("F1 полоса леса-стены посажена", wall_n >= 150, "деревьев %d" % wall_n)
	verdict("F2 лес-стена лежит в маске ядра", GameManager.army.forest_cells() > 0,
		"ячеек %d" % GameManager.army.forest_cells())
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	# Проход вниз и проход вправо — чистые
	var gx: float = a.x + main.WALL_GAP_DOWN_AT
	var gz_down: float = main._wall_bottom_z(gx)
	var gz: float = a.z + main.WALL_GAP_RIGHT_AT
	var gx_right: float = main._wall_right_x(gz)
	var gap_clear := true
	for k in range(-4, 5):
		if GameManager.army.forest_at(gx + float(k), gz_down) or GameManager.army.forest_at(gx_right, gz + float(k)):
			gap_clear = false
	verdict("F3 два широких прохода (вниз и вправо) свободны", gap_clear)
	# Декор проходим: ни одного ствола в реестре у рощи-декора
	var decor := 0
	var decor_trunk := 0
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if n is ResourceNode and int((n as ResourceNode).forest_kind) == ResourceNode.FOREST_DECOR:
			decor += 1
			if bool((n as ResourceNode)._trunk_registered):
				decor_trunk += 1
	verdict("F4 лес-декор есть и он проходим (без стволов в реестре)", decor > 50 and decor_trunk == 0,
		"декора %d, со стволом %d" % [decor, decor_trunk])
	# Отряд из зоны игрока за нижнюю стену НЕ напрямую, а проходом
	var start := Vector3(a.x + 2.0, 0.0, a.z + 30.0)
	var goal := Vector3(a.x + 2.0, 0.0, main._wall_bottom_z(a.x + 2.0) + 16.0)
	var squad: Array = _squad("spearman", Constants.FACTION_PLAYER, start, 10)
	await pframes(3)
	for u in squad:
		(u as Unit).command_move(goal + ((u as Unit).global_position - start), false, Vector3.ZERO, false, true)
	var inside := 0
	var g := 0
	var arrived := 0
	while g < 60 * 50:
		await get_tree().physics_frame
		g += 1
		if g % 10 == 0:
			arrived = 0
			for u2 in squad:
				var p: Vector3 = (u2 as Unit).global_position
				if GameManager.army.forest_at(p.x, p.z):
					inside += 1
				if Vector2(p.x - goal.x, p.z - goal.z).length() < 6.0:
					arrived += 1
			if arrived >= 8:
				break
	verdict("F5 отряд обходит лес-стену проходом и доходит", arrived >= 8, "дошли %d из 10 за %d кадров" % [arrived, g])
	verdict("F6 никто не прошёл сквозь стену", inside == 0, "замеров в лесу %d" % inside)
	for u3 in squad:
		if is_instance_valid(u3):
			(u3 as Unit).take_damage(99999.0)
	# Рабочий рубит кромку стены
	var edge: ResourceNode = null
	var bd := INF
	var from := Vector3(a.x + 10.0, 0.0, main._wall_bottom_z(a.x + 10.0) - 12.0)
	for n2 in get_tree().get_nodes_in_group("resource_nodes"):
		if n2 is ResourceNode and int((n2 as ResourceNode).forest_kind) == ResourceNode.FOREST_WALL:
			var d: float = (n2 as Node3D).global_position.distance_to(from)
			if d < bd:
				bd = d
				edge = n2
	var w := _unit("worker", Constants.FACTION_PLAYER, from) as Worker
	GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "worker"), w)
	await pframes(2)
	w.command_gather(edge)
	var g2 := 0
	while g2 < 60 * 30 and w.state != Unit.State.GATHERING:
		await get_tree().physics_frame
		g2 += 1
		if g2 % 150 == 1 and OS.get_cmdline_user_args().has("dbg"):
			var wp: Vector3 = w.global_position
			print("    dbg f%d st=%d pos=(%.1f,%.1f) mt=(%.1f,%.1f) tree=(%.1f,%.1f) res=%d forest_here=%s flags=%d dead_end=%s trunkign=%.1f" % [g2, w.state, wp.x, wp.z,
				w.move_target.x, w.move_target.z, edge.global_position.x, edge.global_position.z,
				int(w._gather_res_type), str(GameManager.army.forest_at(wp.x, wp.z)),
				GameManager.army.flags_of(w._soa), str(w._nav_dead_end), float(w._trunk_ignore)])
	verdict("F7 рабочий дошёл до кромки леса-стены и рубит", w.state == Unit.State.GATHERING,
		"за %d кадров, до дерева %.1f м" % [g2, w.global_position.distance_to(edge.global_position)])
	# Вырубка снимает круг из маски
	var n_before: int = int(GameManager.army._c.ForestTreeCount())
	edge.extract(99999.0)
	await pframes(2)
	var n_after: int = int(GameManager.army._c.ForestTreeCount())
	verdict("F8 срубленное дерево стены снимает свой круг", n_after == n_before - 1,
		"кругов %d → %d" % [n_before, n_after])
	w.take_damage(99999.0)

# ═════════════════════════════════════════════════════════════════════════════
# G. МЕЛОЧИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_misc() -> void:
	print("\n═════ G. МЕЛОЧИ ═════")
	verdict("G1 интервал выхода из бараков не уже расталкивания",
		Building.spawn_spacing(0.35) >= 0.62)
	var sp := _unit("spearman", Constants.FACTION_PLAYER, _spot() + Vector3(5.0, 0.0, -30.0))
	sp.call("_apply_dir_tex", "defence_down")
	var by: float = float(sp.get("_sprite_base_y"))
	verdict("G2 копейщик в нижней позе стоит по ступням, а не по наконечнику",
		by < Unit.SPRITE_BASE_Y + 0.25, "база %.2f м (Idle %.2f)" % [by, Unit.SPRITE_BASE_Y])
	sp.take_damage(99999.0)
	var fx: float = main.river_x(main.FORD_Z)
	verdict("G3 в воде брода декор и деревья не сажаются", main.veg_river_blocked(fx, main.FORD_Z)
		and main.veg_river_blocked(fx + main.RIVER_HALF_W + main.RIVER_BANK + 2.0, main.FORD_Z))
	verdict("G4 у брода песчаная коса", main.ford_sand(fx + main.RIVER_HALF_W + main.RIVER_BANK + 3.0, main.FORD_Z))
	var deco_in_water := 0
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var p: Vector3 = (n as Node3D).global_position
		if main.in_water_mesh(p.x, p.z):
			deco_in_water += 1
	verdict("G5 ни одного дерева в воде", deco_in_water == 0, "в воде %d" % deco_in_water)
