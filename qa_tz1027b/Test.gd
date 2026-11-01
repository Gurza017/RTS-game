extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_TZ1027B — ТЗ 27.10.2026 (второе письмо): поздняя орда, рынок, склад,
## кузница за еду, туши против зданий, HUD. Headless.
## ═══════════════════════════════════════════════════════════════════════════
## A — расписание рейдов: после 30:00 чаще, после 60:00 крупнее
##     (RaidManager.schedule, spawn_config.LATE_RAID_*, ручка goblin_late_raids)
## B — волна у базы игрока не стоит, а сносит постройки
##     (GoblinAI._raze_near_base, ручка goblin_base_raze)
## C — туша бьёт здание и бьёт его ×BIG_BUILDING_DMG_MULT
## D — кузница: у каждого узла есть цена в еде, всё дороже прежнего
## E — рынок: курс, пошлина, обмен, окно по выделению
## F — склад: рабочий сдаёт груз на ближайший склад, ресурс — в казну
## G — HUD: плашки бездельников и рудников ×1.5, башня — одна кнопка
##     гарнизона, кнопки башни одного размера
## Ручки: diag=1, block=X.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _Spawn := preload("res://scripts/spawn_config.gd")
const _Raid := preload("res://scripts/goblin/RaidManager.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const GF := Constants.FACTION_GOBLIN

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _diag := false
var _only := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "diag=1":
			_diag = true
		elif a.begins_with("block="):
			_only = a.substr(6)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_tz1027b: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _want(b: String) -> bool:
	return _only == "" or _only.find(b) >= 0

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _place(b: Building, at: Vector3, fac: int = F) -> Building:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return b

func _kill_area(c: Vector3, r: float) -> void:
	for u in GameManager._live_units.duplicate():
		if not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu == null or uu.is_dead():
			continue
		if uu.global_position.distance_to(c) < r:
			uu.take_damage(1e12)

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 30.0), Vector3(0.0, 0.0, -30.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
				if GameManager.is_water(p.x + d.x, p.z + d.z):
					h += 100.0
				if not GameManager.is_passable(p.x + d.x, p.z + d.z):
					h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _rich() -> void:
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(F, r, 50000.0)

func _run() -> void:
	main = get_tree().current_scene
	if main == null or not main.has_method("world_add"):
		var sc: PackedScene = load("res://scenes/Main.tscn")
		main = sc.instantiate()
		get_tree().root.add_child(main)
	await frames(30)
	_Opt.squad_probes = false
	var base: Vector3 = _flat_spot(Vector3(0.0, 0.0, 40.0))
	main._clear_trees(base, 60.0)
	_kill_area(base, 90.0)
	await pframes(10)
	if _want("A"):
		_a_schedule()
	if _want("D"):
		_d_forge()
	if _want("E"):
		await _e_market(base)
	if _want("C"):
		await _c_big_vs_building(base)
	if _want("F"):
		await _f_storehouse(base)
	if _want("G"):
		await _g_hud(base)
	if _want("B"):
		await _b_raze(base)
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. РАСПИСАНИЕ РЕЙДОВ
# ═════════════════════════════════════════════════════════════════════════════
func _men_of(e: Dictionary) -> int:
	var n := 0
	for k in (e["comp"] as Dictionary):
		n += int((e["comp"] as Dictionary)[k])
	return n

func _a_schedule() -> void:
	print("\n═════ A. РАСПИСАНИЕ РЕЙДОВ ═════")
	var s: Array = _Raid.schedule()
	var early := 0
	var mid := 0
	var late := 0
	var mid_sq := 0
	var late_sq := 0
	for e in s:
		var t: float = float(e["t"])
		if t < 1800.0:
			early += 1
		elif t < 3600.0:
			mid += 1
			mid_sq += _men_of(e)
		elif t < 5400.0:
			late += 1
			late_sq += _men_of(e)
	print("  сроков: до 30:00 %d, 30-60 %d (%d отрядов), 60-90 %d (%d отрядов)" % [early, mid, mid_sq, late, late_sq])
	# Прежде после 30:00 были только штурмы 30/45/60 (по паре сроков) — 6
	# сроков на 30 минут. Чаще — значит больше сроков, промежуток меньше
	var gaps_mid: Array = []
	var prev := -1.0
	for e2 in s:
		var t2: float = float(e2["t"])
		if t2 >= 1800.0 and t2 < 3600.0:
			if prev >= 0.0:
				gaps_mid.append(t2 - prev)
			prev = t2
	var worst_gap := 0.0
	for g in gaps_mid:
		worst_gap = maxf(worst_gap, float(g))
	verdict("A1 после 30:00 рейды чаще: сроков 30-60 больше 6, разрыв ≤ 6 мин", mid > 6 and worst_gap <= 360.0,
		"сроков %d, худший разрыв %.0f с" % [mid, worst_gap])
	verdict("A2 после 60:00 волны есть и они крупнее: отрядов на срок больше, чем в 30-60",
		late > 0 and mid > 0 and float(late_sq) / float(late) > float(mid_sq) / float(mid),
		"%.1f против %.1f отрядов на срок" % [float(late_sq) / float(maxi(late, 1)), float(mid_sq) / float(maxi(mid, 1))])
	# Волны вожака: пауза после 30:00 короче, после 60:00 — ещё короче и
	# планы крупнее
	verdict("A3 паузы волн вожака: 60+ < 30-60 < до 30", _Spawn.late_gap_k(4000.0) < _Spawn.late_gap_k(2000.0) \
		and _Spawn.late_gap_k(2000.0) < _Spawn.late_gap_k(100.0),
		"%.2f / %.2f / %.2f" % [_Spawn.late_gap_k(100.0), _Spawn.late_gap_k(2000.0), _Spawn.late_gap_k(4000.0)])

# ═════════════════════════════════════════════════════════════════════════════
# B. ВОЛНА У БАЗЫ СНОСИТ ПОСТРОЙКИ
# ═════════════════════════════════════════════════════════════════════════════
func _b_raze(base: Vector3) -> void:
	print("\n═════ B. ВОЛНА У БАЗЫ ═════")
	var ai: Node = main.goblin_ai
	if ai == null:
		verdict("B0 есть GoblinAI", false)
		return
	# Две постройки игрока: дом и башня, в 12 м друг от друга
	var h: Building = _place(load("res://scripts/House.gd").new(), base + Vector3(-6.0, 0.0, 0.0))
	var tw: Building = _place(load("res://scripts/Tower.gd").new(), base + Vector3(8.0, 0.0, 0.0))
	await pframes(10)
	var hp0: float = h.current_health + tw.current_health
	# Отряд орды рядом с базой — волна «разведка» (сценарий scout: цель —
	# главная постройка игрока, узла цели нет — прежде отряд вставал у цели
	# и через 12 с уходил домой)
	var sid: int = int(main.spawn_goblin_squad("goblin_spearman", 30, base + Vector3(0.0, 0.0, 22.0), false))
	await pframes(20)
	ai.call("_launch", "scout", [sid])
	var t_end: float = Unit.game_sec + 60.0
	var razed := false
	while Unit.game_sec < t_end:
		await pframes(30)
		var hp: float = (h.current_health if is_instance_valid(h) and not h.is_dead() else 0.0) \
			+ (tw.current_health if is_instance_valid(tw) and not tw.is_dead() else 0.0)
		if hp < hp0 * 0.98:
			razed = true
			break
	var st := ""
	for w in (ai.get("waves") as Array):
		if ((w as Dictionary)["sids"] as Array).has(sid):
			st = String((w as Dictionary)["stage"])
	verdict("B1 дошедшая до базы волна крушит постройки (урон за 60 с)", razed, "этап волны «%s»" % st)
	for m in GameManager.squad_members(sid):
		if is_instance_valid(m):
			(m as Unit).take_damage(1e12)
	for b in [h, tw]:
		if is_instance_valid(b) and not (b as Building).is_dead():
			(b as Building).take_damage(1e12)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# C. ТУША ПРОТИВ ЗДАНИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _c_big_vs_building(base: Vector3) -> void:
	print("\n═════ C. ТУША ПРОТИВ ЗДАНИЯ ═════")
	var tw: Building = _place(load("res://scripts/Tower.gd").new(), base + Vector3(0.0, 0.0, -20.0))
	await pframes(5)
	var bg: Unit = _spawn("big_goblin", GF, base + Vector3(0.0, 0.0, -14.0))
	await pframes(5)
	bg.command_attack(tw, true)
	var hp0: float = tw.current_health
	var sw0: int = int(bg.get("_swings"))
	var t_end: float = Unit.game_sec + 25.0
	while Unit.game_sec < t_end and int(bg.get("_swings")) - sw0 < 3:
		await pframes(10)
	var swings: int = int(bg.get("_swings")) - sw0
	var lost: float = hp0 - tw.current_health
	var per: float = lost / float(maxi(swings, 1))
	var want: float = (bg.attack_damage + bg._upgrade_damage_bonus()) * _GobCfg.BIG_BUILDING_DMG_MULT
	verdict("C1 туша наносит урон постройке", swings > 0 and lost > 0.0, "взмахов %d, урон %.0f" % [swings, lost])
	verdict("C2 урон по постройке = удар × %.1f" % _GobCfg.BIG_BUILDING_DMG_MULT,
		swings > 0 and absf(per - want) <= want * 0.05 + 0.5, "%.1f за взмах при ожидании %.1f" % [per, want])
	bg.take_damage(1e12)
	tw.take_damage(1e12)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# D. КУЗНИЦА ЗА ЕДУ
# ═════════════════════════════════════════════════════════════════════════════
func _d_forge() -> void:
	print("\n═════ D. КУЗНИЦА ЗА ЕДУ ═════")
	var nodes := 0
	var no_food := 0
	var tot_new := 0.0
	var tot_old := 0.0
	for uid in _Forge.UNITS:
		for n in _Forge.tree(String(uid)):
			var d: Dictionary = n
			if not d.has("cost_gold") and not d.has("cost_wood"):
				continue
			nodes += 1
			if float(d.get("cost_food", 0.0)) <= 0.0:
				no_food += 1
			var raw: Dictionary = (_Forge.UNITS[uid] as Dictionary).get(String(d["cell"]), {})
			var rk: float = _Forge.row_cost_mult(int(d["row"]))
			tot_old += (float(raw.get("cost_gold", 0.0)) + float(raw.get("cost_wood", 0.0)) \
				+ float(raw.get("cost_stone", 0.0)) + float(raw.get("cost_food", 0.0))) * rk
			tot_new += float(d.get("cost_gold", 0.0)) + float(d.get("cost_wood", 0.0)) \
				+ float(d.get("cost_stone", 0.0)) + float(d.get("cost_food", 0.0))
	print("  узлов %d, без еды %d, сумма цен %.0f → %.0f (×%.2f)" % [nodes, no_food, tot_old, tot_new, tot_new / maxf(tot_old, 1.0)])
	verdict("D1 у каждого узла кузницы есть цена в еде", nodes > 0 and no_food == 0, "без еды %d из %d" % [no_food, nodes])
	verdict("D2 исследования заметно дороже (×1.5 и больше)", tot_new >= tot_old * 1.5, "×%.2f" % (tot_new / maxf(tot_old, 1.0)))

# ═════════════════════════════════════════════════════════════════════════════
# E. РЫНОК
# ═════════════════════════════════════════════════════════════════════════════
func _e_market(base: Vector3) -> void:
	print("\n═════ E. РЫНОК ═════")
	var MS = load("res://scripts/Market.gd")
	var W := Constants.RESOURCE_WOOD
	var G := Constants.RESOURCE_GOLD
	var FD := Constants.RESOURCE_FOOD
	var q1: float = MS.quote(W, G, 1000.0)
	var back: float = MS.quote(G, W, q1)
	verdict("E1 курс: дерево → золото даёт меньше, чем отдано по «цене»", q1 > 0.0 and q1 < 1000.0, "1000 дерева → %d золота" % int(q1))
	verdict("E2 круг A → B → A в минус (пошлина)", back < 1000.0 and back > 0.0, "1000 → %d → %d" % [int(q1), int(back)])
	var mk: Building = _place(MS.new(), base + Vector3(-20.0, 0.0, 10.0))
	await pframes(5)
	_rich()
	var w0: float = ResourceManager.get_amount(F, W)
	var f0: float = ResourceManager.get_amount(F, FD)
	var ok: bool = bool(mk.call("trade", F, W, FD, 500.0))
	var dw: float = w0 - ResourceManager.get_amount(F, W)
	var df: float = ResourceManager.get_amount(F, FD) - f0
	verdict("E3 обмен списал отданное и зачислил полученное по курсу", ok and is_equal_approx(dw, 500.0) \
		and is_equal_approx(df, MS.quote(W, FD, 500.0)), "−%d дерева, +%d еды" % [int(dw), int(df)])
	ResourceManager.set_amount(F, Constants.RESOURCE_STONE, 10.0)
	verdict("E4 без запаса обмен отказывает", not bool(mk.call("trade", F, Constants.RESOURCE_STONE, G, 100.0)))
	verdict("E5 рынок есть в меню рабочего", GameManager.worker_buildings().has("market"))
	# Окно по выделению
	var hud = main.hud
	hud.show_selection([mk])
	await frames(3)
	var mp = hud.get("_market_panel")
	verdict("E6 выделение рынка открывает окно обмена", mp != null and is_instance_valid(mp) and (mp as Control).visible)
	if mp != null and is_instance_valid(mp):
		_rich()
		var g0: float = ResourceManager.get_amount(F, G)
		var traded: bool = bool(mp.call("do_trade"))
		verdict("E7 кнопка окна меняет ресурс", traded and ResourceManager.get_amount(F, G) > g0)
		verdict("E8 окно держит фокус (клик по нему — не клик по миру)",
			hud.point_over_ui((mp as Control).get_global_rect().get_center()))
		# ── КОЛИЧЕСТВО ПО СЕТКЕ (разворот ТЗ 29.10.2026: кнопок партий
		# 1 000 … 50 000 больше нет, сетка «−/+» MARKET.steps 100 … 20 000)
		var stp: Array = _UCfg.MARKET["steps"]
		var lmin: float = float(_UCfg.MARKET["lot_min"])
		var lmax: float = float(_UCfg.MARKET["lot_max"])
		verdict("E10 кнопок готовых партий нет, сетка и пределы — из конфига (%s)" % str(stp),
			mp.get("_lot_btns") == null and float(stp[0]) == lmin and float(stp[stp.size() - 1]) == lmax)
		mp.call("_set_lot", float(stp[3]))
		var l0: float = float(mp.get("lot"))
		mp.call("_step_lot", 1)
		var l1: float = float(mp.get("lot"))
		mp.call("_step_lot", -1)
		mp.call("_step_lot", -1)
		var l2: float = float(mp.get("lot"))
		mp.call("_set_lot", lmax)
		mp.call("_step_lot", 1)
		var lt: float = float(mp.get("lot"))
		mp.call("_set_lot", lmin)
		mp.call("_step_lot", -1)
		var lb: float = float(mp.get("lot"))
		verdict("E11 «+/−» ходят по сетке и не выходят за пределы",
			is_equal_approx(l1, float(stp[4])) and is_equal_approx(l2, float(stp[2]))
			and is_equal_approx(lt, lmax) and is_equal_approx(lb, lmin),
			"%d → %d → %d; потолок %d, пол %d" % [int(l0), int(l1), int(l2), int(lt), int(lb)])
		var ed: LineEdit = mp.get("_lot_edit")
		ed.text = "12 500"
		mp.call("_commit_edit", true)
		var e12a: float = float(mp.get("lot"))
		var e12t: String = ed.text
		ed.text = "999 999"
		mp.call("_commit_edit", true)
		verdict("E12 поле ввода принимает число с пробелами и зажимает его в пределы",
			is_equal_approx(e12a, 12500.0) and e12t == "12 500" and is_equal_approx(float(mp.get("lot")), lmax),
			"%d «%s», 999 999 → %d" % [int(e12a), e12t, int(mp.get("lot"))])
		_rich()
		mp.call("_set_give", W)
		mp.call("_lot_all")
		verdict("E13 «Всё» — запас продаваемого, не больше потолка",
			is_equal_approx(float(mp.get("lot")), minf(ResourceManager.get_amount(F, W), lmax)))
		mp.call("_set_lot", lmax)
		var w1: float = ResourceManager.get_amount(F, W)
		var big: bool = bool(mp.call("do_trade"))
		verdict("E14 обмен наибольшим количеством — один клик", big and is_equal_approx(w1 - ResourceManager.get_amount(F, W), lmax),
			"−%d дерева" % int(w1 - ResourceManager.get_amount(F, W)))
		var gb: Button = (mp.get("_give_btns") as Dictionary)[G]
		var gtex: Texture2D = null
		for ch in gb.get_children():
			if ch is TextureRect:
				gtex = (ch as TextureRect).texture
		verdict("E15 иконка золота — крупный самородок, обрезана по рисунку (заполняет рамку)",
			gtex != null and gtex is AtlasTexture and (gtex as AtlasTexture).region.size.y >= 40.0
			and String((gtex as AtlasTexture).atlas.resource_path).contains("Gold Stone"),
			"%s" % (str((gtex as AtlasTexture).region) if gtex is AtlasTexture else "нет обрезки"))
		# ── ОДНА ПАНЕЛЬ (ТЗ 29.10.2026) ──────────────────────────────────
		var bp = hud.get("_bottom_panel")
		verdict("E16 нижняя карточка здания с текстами скрыта, пока выделен рынок",
			bp == null or not (bp as Control).visible)
		var texts: Array = []
		_collect_texts(mp, texts)
		verdict("E17 подписи «Продать», «Купить», «Количество»; ни заголовка «Рынок», ни «Отдать/Получить/Партия»",
			texts.has("Продать") and texts.has("Купить") and texts.has("Количество")
			and not texts.has("Рынок") and not texts.has("Отдать") and not texts.has("Получить") and not texts.has("Партия"),
			str(texts))
		var gx: float = ((mp.get("_give_btns") as Dictionary)[W] as Control).get_global_rect().position.x
		var bx: float = ((mp.get("_get_btns") as Dictionary)[W] as Control).get_global_rect().position.x
		verdict("E18 кнопки «Продать» и «Купить» начинаются с одной вертикали", absf(gx - bx) < 1.0, "%.0f / %.0f" % [gx, bx])
		var ic: TextureRect = mp.get("_icon")
		var pr: Rect2 = (mp as Control).get_global_rect()
		verdict("E19 иконка здания — в правом верхнем углу панели",
			ic != null and ic.texture != null and ic.get_global_rect().get_center().x > pr.get_center().x
			and ic.get_global_rect().get_center().y < pr.get_center().y)
		var go: Control = mp.get("_go")
		var le: Control = mp.get("_lot_edit")
		verdict("E20 ввод и «Обменять» — в нижней части панели",
			le.get_global_rect().position.y > ic.get_global_rect().position.y and go.get_global_rect().end.y <= pr.end.y + 0.5
			and go.get_global_rect().position.y > le.get_global_rect().position.y)
	hud.show_selection([])
	await frames(3)
	var mp2 = hud.get("_market_panel")
	verdict("E9 снятие выделения закрывает окно", mp2 == null or not is_instance_valid(mp2) or not (mp2 as Control).visible)
	mk.take_damage(1e12)
	await pframes(5)

# ═════════════════════════════════════════════════════════════════════════════
# F. СКЛАД
# ═════════════════════════════════════════════════════════════════════════════
func _f_storehouse(base: Vector3) -> void:
	print("\n═════ F. СКЛАД ═════")
	var sh: Building = _place(load("res://scripts/Storehouse.gd").new(), base + Vector3(0.0, 0.0, -18.0))
	await pframes(5)
	verdict("F1 склад — точка сдачи (ближайшая к рабочему у склада)",
		GameManager.get_nearest_dropoff(F, base + Vector3(0.0, 0.0, -24.0)) == sh)
	verdict("F2 склад есть в меню рабочего", GameManager.worker_buildings().has("storehouse"))
	var w: Worker = _spawn("worker", F, base + Vector3(0.0, 0.0, -28.0)) as Worker
	await pframes(5)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_FOOD]:
		var r0: float = ResourceManager.get_amount(F, t)
		w.carrying_type = t
		w.carrying_amount = 20.0
		w.gather_target = null
		w.move_target = w._dest_point(sh)
		w.state = Unit.State.RETURNING
		w._wake_process()
		var t_end: float = Unit.game_sec + 20.0
		while Unit.game_sec < t_end and w.carrying_amount > 0.0:
			await pframes(10)
			if _diag:
				var dn: Node3D = GameManager.get_nearest_dropoff(F, w.global_position)
				print("    рабочий: st=%d carry=%.0f pos=%s склад=%s сдача=%s ближ=%s" % [int(w.state), w.carrying_amount,
					str(w.global_position), str(sh.global_position), str(w._dest_point(sh)) + " r=%.1f c=%s" % [sh.ring_radius(), str(sh.ring_center())], str(dn.name if dn != null else "-")])
		var got: float = ResourceManager.get_amount(F, t) - r0
		verdict("F3 груз (%s) сдан на складе и ушёл в казну" % ("дерево" if t == Constants.RESOURCE_WOOD else "мясо"),
			w.carrying_amount <= 0.0 and got >= (19.9 if t == Constants.RESOURCE_WOOD else 15.0) and w.global_position.distance_to(sh.global_position) < 8.0,
			"+%.0f, до склада %.1f м" % [got, w.global_position.distance_to(sh.global_position)])
		w.global_position = base + Vector3(0.0, 0.0, -28.0)
		w.sync_row()
		await pframes(3)
	w.take_damage(1e12)
	sh.take_damage(1e12)
	await pframes(10)
	verdict("F4 снесённый склад снят с точек сдачи", not (GameManager.dropoffs.get(F, []) as Array).has(sh))

# ═════════════════════════════════════════════════════════════════════════════
# G. HUD
# ═════════════════════════════════════════════════════════════════════════════
func _g_hud(base: Vector3) -> void:
	print("\n═════ G. HUD ═════")
	var hud = main.hud
	var idle: Control = hud.get("_idle_btn")
	var mine: Control = hud.get("_mine_box")
	var want: float = 26.0 * 1.5
	verdict("G1 плашка бездельников ×1.5", idle != null and absf(idle.size.x - want) < 0.6 and absf(idle.size.y - want) < 0.6,
		"%s" % str(idle.size if idle != null else Vector2.ZERO))
	verdict("G2 значок рудников ×1.5 и справа от плашки, без наезда", mine != null \
		and absf(mine.size.x - want) < 0.6 and mine.position.x >= idle.position.x + idle.size.x,
		"%s у %s" % [str(mine.size if mine != null else Vector2.ZERO), str(mine.position if mine != null else Vector2.ZERO)])
	var res: Control = hud.get("_res_panel")
	verdict("G3 плашка ниже панели ресурсов", res != null and idle.position.y >= res.position.y + res.size.y,
		"плашка y %.0f, низ панели %.0f" % [idle.position.y, res.position.y + res.size.y])
	# Башня с гарнизоном: одна кнопка гарнизона
	var tw: Building = _place(load("res://scripts/Tower.gd").new(), base + Vector3(-25.0, 0.0, -20.0))
	await pframes(5)
	var sid: int = GameManager.new_squad(F, "archer")
	var arch: Array = []
	for i in range(8):
		var a: Unit = _spawn("archer", F, tw.global_position + Vector3(float(i) * 0.6 - 2.0, 0.0, 5.0))
		GameManager.add_to_squad(sid, a)
		arch.append(a)
	await pframes(5)
	var seated: bool = (tw as Castle).garrison_now(sid)
	print("  гарнизон посажен: %s" % str(seated))
	await pframes(10)
	hud.show_selection([tw])
	await frames(3)
	var bc: Control = hud.get("button_container")
	var sect: Node = bc.find_child("GarrisonSection", true, false) if bc != null else null
	var rel: Button = null
	var fort: Button = null
	if bc != null:
		for c in bc.get_children():
			if c is Button and String((c as Button).tooltip_text).begins_with("Выпустить"):
				rel = c
			if c is Button and String((c as Node).name) == "TowerFortBtn":
				fort = c
	verdict("G4 у башни нет второй мелкой иконки гарнизона", sect == null,
		"гарнизон %d" % (tw as Castle).garrison.size())
	verdict("G5 крупная кнопка «Выпустить» на месте", rel != null)
	verdict("G6 кнопки «Выпустить» и «Укрепить» одного размера, меньше прежних",
		rel != null and fort != null and rel.custom_minimum_size == fort.custom_minimum_size \
		and fort.custom_minimum_size.x < 29.0 * 1.9 - 0.5,
		"%s / %s" % [str(rel.custom_minimum_size if rel != null else Vector2.ZERO), str(fort.custom_minimum_size if fort != null else Vector2.ZERO)])
	hud.show_selection([])
	await frames(2)
	tw.take_damage(1e12)
	await pframes(5)

func _collect_texts(n: Node, out: Array) -> void:
	if n is Label:
		out.append(String((n as Label).text))
	for ch in n.get_children():
		_collect_texts(ch, out)
