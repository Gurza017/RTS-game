extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_ECONOMY_LATE — ТЗ 28.10.2026, блок 2: ребаланс еды и глубокая кузница
## под 40+ отрядов. Ни одного числа из конфигов стенд не повторяет — проверяет
## СВОЙСТВА заказа; каждая ручка проверена выключением (knob=имя:0 красит блок).
## ═══════════════════════════════════════════════════════════════════════════
## A — модель (economy_model): таблица «приход / содержание» при 10, 20, 40
##     отрядах; при 40 без улучшений — дефицит, при 10-20 — нет; с полной
##     веткой мяса кузницы 40 отрядов кормятся; ручка food_big_army
##     выключена — дефицит при 40 исчезает (старый линейный расход).
## B — древо рабочего: глубокие ряды 3-5 изучаются 60-90 с и стоят дорого,
##     ступени мяса и груза, точечные золото/дерево ≥ +20 %, «ленивых» узлов
##     на все промыслы нет, узлы ускорения Кузницы, ключи в BONUS_KEYS.
## C — живая партия: фермер с «выходом мяса +30 %» несёт кусок ×1.3
##     (ручка meat_yield_bonus), Кузница с «темпом исследований +50 %»
##     качает за секунду полторы (ручка forge_research_speed), золотой узел
##     режет цикл только золоту, расход еды живого склада растёт с
##     FOOD_UPKEEP_BIG_ARMY_HEADS голов (ручка food_big_army).
## Запуск: godot --headless --path . res://qa_economy_late/Test.tscn [-- only=abc]
##         [-- knob=food_big_army:0] [-- knob=meat_yield_bonus:0] [-- knob=forge_research_speed:0]

const _M := preload("res://scripts/economy_model.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _Pen := preload("res://scripts/SheepPen.gd")
const _Sheep := preload("res://scripts/goblin/Sheep.gd")
const P := Constants.FACTION_PLAYER

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only: String = "abc"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(420.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else: _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_economy_late: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _run() -> void:
	print("  ручки: food_big_army=%s meat_yield_bonus=%s forge_research_speed=%s" % [
		str(_Opt.food_big_army), str(_Opt.meat_yield_bonus), str(_Opt.forge_research_speed)])
	if "a" in _only: _a_model()
	if "b" in _only: _b_tree()
	if "c" in _only:
		main = load("res://scenes/Main.tscn").instantiate()
		get_tree().root.add_child(main)
		await pframes(8)
		if main.enemy_ai != null: main.enemy_ai.set_process(false)
		if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
		if GameManager.fog != null: GameManager.fog.enabled = false
		for w in get_tree().get_nodes_in_group("all_units"):
			if w is Unit and (w as Unit).faction != P:
				(w as Unit).set_tick(false)
		await pframes(4)
		await _c_live()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
func _row_str(r: Dictionary) -> String:
	return "%2d отр (%4.0f голов, ставка ×%.2f) дома %2d фермеров %2d рабочих %3d: содержание %6.2f/с (армия %5.2f, рабочие %4.2f)  приход %6.2f/с (дома %4.2f, фермы %5.2f)  баланс %+6.2f/с = %+5.0f/мин" % [
		int(r["squads"]), float(r["heads"]), float(r["mult"]), int(r["houses"]), int(r["farmers"]),
		int(r["workers"]), float(r["upkeep"]), float(r["upkeep_army"]), float(r["upkeep_workers"]),
		float(r["income"]), float(r["income_houses"]), float(r["income_farms"]), float(r["balance"]),
		float(r["balance"]) * 60.0]

func _a_model() -> void:
	print("\n═════ A. МОДЕЛЬ: ПРИХОД / СОДЕРЖАНИЕ ЕДЫ ПО РАЗМЕРУ АРМИИ ═════")
	print("  допущения: голов в отряде по составу %s = %.0f, рабочих %d + %.1f на отряд, фермеров = отрядов (потолок %d), дома — по лимиту бойцов" % [
		str(_M.ARMY_MIX), _M.squad_heads(), _M.FOOD_WORKERS_BASE, _M.FOOD_WORKERS_PER_SQUAD, _UCfg.SHEEP_PLAYER_MAX])
	print("  ── без улучшений кузницы ──")
	var base := {}
	for n in _M.FOOD_TABLE_SQUADS:
		var r: Dictionary = _M.food_balance_row(int(n), 0)
		base[int(n)] = r
		print("  " + _row_str(r))
	print("  ── с полной веткой рабочего (ряды 1-%d) ──" % _Forge.ROWS)
	var full := {}
	for n in _M.FOOD_TABLE_SQUADS:
		var r: Dictionary = _M.food_balance_row(int(n), _Forge.ROWS)
		full[int(n)] = r
		print("  " + _row_str(r))
	var r40: Dictionary = base[40]
	verdict("A1 при 40 отрядах без улучшений — дефицит еды (ощутимый: хуже −1 еды/с)",
		float(r40["balance"]) <= -1.0, "%+.2f/с" % float(r40["balance"]))
	verdict("A2 при 10 и 20 отрядах без улучшений еды хватает (ранняя игра не наказана)",
		float(base[10]["balance"]) >= 0.0 and float(base[20]["balance"]) >= 0.0,
		"10: %+.2f/с, 20: %+.2f/с" % [float(base[10]["balance"]), float(base[20]["balance"])])
	verdict("A3 ставка на голову растёт с армией: ×1 при 20 отрядах, > ×1.2 при 40",
		is_equal_approx(float(base[20]["mult"]), 1.0) and float(r40["mult"]) > 1.2,
		"20: ×%.2f, 40: ×%.2f" % [float(base[20]["mult"]), float(r40["mult"])])
	var f40: Dictionary = full[40]
	verdict("A4 полная ветка рабочего кормит 40 отрядов с запасом (баланс > +1 еды/с)",
		float(f40["balance"]) >= 1.0, "%+.2f/с (фермы %.2f → %.2f)" % [
			float(f40["balance"]), float(r40["income_farms"]), float(f40["income_farms"])])
	# Ступени: половина ветки (ряды 1-3) уже выводит в ноль или лучше
	var h40: Dictionary = _M.food_balance_row(40, 3)
	verdict("A5 ряды 1-3 ветки рабочего выводят 40 отрядов из минуса",
		float(h40["balance"]) >= 0.0, "%+.2f/с" % float(h40["balance"]))
	verdict("A6 модель читает прирост фермы из узлов древа (econ_gain(еда) > 1)",
		_M.econ_gain(Constants.RESOURCE_FOOD) > 1.05, "×%.2f" % _M.econ_gain(Constants.RESOURCE_FOOD))
	# Ручка выключена — старый линейный расход, дефицита при 40 нет
	var was: bool = _Opt.food_big_army
	_Opt.food_big_army = false
	var off40: Dictionary = _M.food_balance_row(40, 0)
	_Opt.food_big_army = was
	verdict("A7 ручка food_big_army выключена — ставка ×1 и дефицит при 40 исчезает (проверка выключением)",
		is_equal_approx(float(off40["mult"]), 1.0) and float(off40["balance"]) > float(r40["balance"]) + 1.0,
		"выкл: ×%.2f, %+.2f/с; вкл: %+.2f/с" % [float(off40["mult"]), float(off40["balance"]), float(r40["balance"])])
	# Модель партии: 90 минут при 40 отрядах — еда содержания считается с надбавкой
	var up: Dictionary = _M.upkeep_cost(float(_M.workers_total(_M.recommended_workers())))
	_Opt.food_big_army = false
	var up_off: Dictionary = _M.upkeep_cost(float(_M.workers_total(_M.recommended_workers())))
	_Opt.food_big_army = was
	verdict("A8 бюджет содержания партии на 90 мин считает надбавку большой армии",
		float(up[Constants.RESOURCE_FOOD]) > float(up_off[Constants.RESOURCE_FOOD]) * 1.05,
		"с надбавкой %.0f еды, без %.0f" % [float(up[Constants.RESOURCE_FOOD]), float(up_off[Constants.RESOURCE_FOOD])])

# ─────────────────────────────────────────────────────────────────────────────
const _GATHER_KEYS := ["bonus_gather_wood", "bonus_gather_stone", "bonus_gather_gold"]
const DEEP_T_MIN := 60.0
const DEEP_T_MAX := 90.0

func _b_tree() -> void:
	print("\n═════ B. ДРЕВО РАБОЧЕГО: ГЛУБОКИЕ ИССЛЕДОВАНИЯ ═════")
	var tree: Array = _Forge.tree("worker")
	var deep_bad: Array = []
	var early_bad: Array = []
	var cyr_bad: Array = []
	var lazy: Array = []
	var meat_steps: Array = []
	var carry_steps: Array = []
	var research_steps: Array = []
	var gold_only := 0.0
	var wood_only := 0.0
	var gold_id := ""
	var wood_id := ""
	var cheap_deep: Array = []
	var sq: Dictionary = _M.squad_cost("spearman")
	var sq_sum: float = float(sq.get(Constants.RESOURCE_WOOD, 0.0)) + float(sq.get(Constants.RESOURCE_GOLD, 0.0)) \
		+ float(sq.get(Constants.RESOURCE_STONE, 0.0))
	var rx := RegEx.new()
	rx.compile("[А-Яа-яЁё]")
	for n in tree:
		var d: Dictionary = n
		var id: String = String(d["id"])
		var row: int = int(d["row"])
		var t: float = float(d.get("research_time", 0.0))
		print("  %-10s %-24s %3.0f с  д%5.0f з%5.0f к%5.0f е%5.0f  %s" % [id, String(d.get("name", "")), t,
			float(d.get("cost_wood", 0.0)), float(d.get("cost_gold", 0.0)), float(d.get("cost_stone", 0.0)),
			float(d.get("cost_food", 0.0)), String(d.get("desc", ""))])
		if row >= 3:
			if t < DEEP_T_MIN or t > DEEP_T_MAX:
				deep_bad.append("%s=%.0f" % [id, t])
			var c: float = float(d.get("cost_wood", 0.0)) + float(d.get("cost_gold", 0.0)) + float(d.get("cost_stone", 0.0))
			if c < sq_sum * 3.0:
				cheap_deep.append("%s=%.0f" % [id, c])
		elif t >= DEEP_T_MIN:
			early_bad.append("%s=%.0f" % [id, t])
		if rx.search(String(d.get("name", ""))) == null or rx.search(String(d.get("desc", ""))) == null:
			cyr_bad.append(id)
		var gk := 0
		for k in _GATHER_KEYS:
			if float(d.get(k, 0.0)) > 0.0:
				gk += 1
		if gk >= 2:
			lazy.append(id)
		if gk == 1 and float(d.get("bonus_gather_gold", 0.0)) > gold_only:
			gold_only = float(d["bonus_gather_gold"]); gold_id = id
		if gk == 1 and float(d.get("bonus_gather_wood", 0.0)) > wood_only:
			wood_only = float(d["bonus_gather_wood"]); wood_id = id
		if float(d.get("bonus_meat_pct", 0.0)) > 0.0:
			meat_steps.append([row, float(d["bonus_meat_pct"]), id])
		if float(d.get("bonus_carry_pct", 0.0)) > 0.0:
			carry_steps.append([row, float(d["bonus_carry_pct"]), id])
		if float(d.get("bonus_research_pct", 0.0)) > 0.0:
			research_steps.append([row, float(d["bonus_research_pct"]), id, String(d["col"])])
	verdict("B1 глубокие ряды 3-5 изучаются %.0f-%.0f с (верхняя граница владельца — полторы минуты)" % [DEEP_T_MIN, DEEP_T_MAX],
		deep_bad.is_empty(), str(deep_bad))
	verdict("B2 ряды 1-2 остаются быстрыми (< %.0f с)" % DEEP_T_MIN, early_bad.is_empty(), str(early_bad))
	verdict("B3 глубокий узел стоит не меньше трёх отрядов копейщиков (отряд %.0f)" % sq_sum,
		cheap_deep.is_empty(), str(cheap_deep))
	var meat_ok: bool = meat_steps.size() >= 2
	var meat_sum := 0.0
	meat_steps.sort()
	for i in range(meat_steps.size()):
		meat_sum += float(meat_steps[i][1])
		if i > 0 and float(meat_steps[i][1]) <= float(meat_steps[i - 1][1]):
			meat_ok = false
	verdict("B4 «выход мяса с туши» — не меньше двух ступеней, каждая следующая больше, в сумме ≥ +50 %",
		meat_ok and meat_sum >= 0.5, "%s, сумма +%.0f %%" % [str(meat_steps), meat_sum * 100.0])
	var carry_ok: bool = carry_steps.size() >= 2
	carry_steps.sort()
	var carry_sum := 0.0
	for i in range(carry_steps.size()):
		carry_sum += float(carry_steps[i][1])
		if i > 0 and float(carry_steps[i][1]) <= float(carry_steps[i - 1][1]):
			carry_ok = false
	verdict("B5 «объём переносимого» — не меньше двух растущих ступеней", carry_ok,
		"%s, сумма +%.0f %%" % [str(carry_steps), carry_sum * 100.0])
	verdict("B6 точечный узел золота ≥ +20 %, без других промыслов в том же узле",
		gold_only >= 0.2, "%s +%.0f %%" % [gold_id, gold_only * 100.0])
	verdict("B7 точечный узел дерева ≥ +20 %, без других промыслов в том же узле",
		wood_only >= 0.2, "%s +%.0f %%" % [wood_id, wood_only * 100.0])
	verdict("B8 «ленивых» узлов на два-три промысла сразу в древе нет", lazy.is_empty(), str(lazy))
	var rs_sum := 0.0
	var rs_col_d := true
	for s in research_steps:
		rs_sum += float(s[1])
		if String(s[3]) != _Forge.ABILITY_COL:
			rs_col_d = false
	verdict("B9 «ускорение исследований» — узлы колонки D (награда за полный ряд), в сумме ≥ +40 %",
		research_steps.size() >= 1 and rs_col_d and rs_sum >= 0.4,
		"%s, сумма +%.0f %%" % [str(research_steps), rs_sum * 100.0])
	verdict("B10 новые ключи в BONUS_KEYS (иначе finish_research их не копит)",
		_UCfg.BONUS_KEYS.has("bonus_meat_pct") and _UCfg.BONUS_KEYS.has("bonus_research_pct"))
	verdict("B11 названия и описания узлов по-русски", cyr_bad.is_empty(), str(cyr_bad))
	verdict("B12 сетка рабочего цела: %d узлов, у каждого имя" % (_Forge.ROWS * _Forge.COLS.size()),
		tree.size() == _Forge.ROWS * _Forge.COLS.size())

# ─────────────────────────────────────────────────────────────────────────────
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
		var u := _spawn(kind, P, at + Vector3(float(i % 8) * 0.8, 0, float(i / 8) * 0.8))
		GameManager.add_to_squad(sid, u)
		u.set_tick(false)
	return sid

func _worker_bonus(key: String, v: float) -> void:
	var ub: Dictionary = GameManager.unit_bonuses
	if not ub.has(P): ub[P] = {}
	var pf: Dictionary = ub[P]
	if not pf.has("worker"): pf["worker"] = {}
	var pw: Dictionary = pf["worker"]
	if v == 0.0:
		pw.erase(key)
	else:
		pw[key] = v
	GameManager.bonus_version += 1

func _c_live() -> void:
	print("\n═════ C. ЖИВАЯ ПАРТИЯ: МЯСО, КУЗНИЦА, ЗОЛОТО, СОДЕРЖАНИЕ ═════")
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	# ── C1-C2: фермер с «выходом мяса» ───────────────────────────────────────
	var base: Vector3 = a + Vector3(-60.0, 0.0, 60.0)
	main._clear_area_of_resources(base, 30.0)
	var pen: Building = _Pen.new()
	pen.faction = P
	pen.set("auto_restock", false)
	main.world_add(pen)
	pen.global_position = Vector3(base.x, main.get_terrain_height(base.x, base.z), base.z)
	var castle := Castle.new()
	castle.faction = P
	main.world_add(castle)
	var cp: Vector3 = base + Vector3(14.0, 0.0, 0.0)
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(4)
	var s: Node3D = _Sheep.new()
	s.set("home", base)
	main.world_root().add_child(s)
	s.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z + 1.0)
	s.call("bind_to_pen", pen, P)
	var w: Worker = _spawn("worker", P, base + Vector3(-4.0, 0.0, 0.0)) as Worker
	await pframes(2)
	var rate0: float = Worker.farmer_meat_per_sec(P)
	_worker_bonus("bonus_meat_pct", 0.3)
	var rate1: float = Worker.farmer_meat_per_sec(P)
	verdict("C1 расчётный темп фермера с «выходом мяса +30 %» — ×1.3",
		absf(rate1 / maxf(rate0, 0.0001) - 1.3) <= 0.01, "%.3f → %.3f (×%.3f)" % [rate0, rate1, rate1 / maxf(rate0, 0.0001)])
	w.command_farm_pen(pen)
	var guard := 0
	var carried := -1.0
	while guard < 60 * 120 and carried < 0.0:
		await get_tree().physics_frame
		guard += 1
		if w.sheep_phase() == Worker.SheepPhase.HAUL and w.carrying_amount > 0.0 \
				and w.carrying_type == Constants.RESOURCE_FOOD:
			carried = w.carrying_amount
	verdict("C2 кусок на руках фермера = базовый × 1.3 (ручка meat_yield_bonus)",
		carried > 0.0 and absf(carried - Worker.MEAT_PER_TRIP * 1.3) <= 0.01,
		"%.2f при базовом %.2f, физкадров %d, фаза %d" % [carried, Worker.MEAT_PER_TRIP, guard, w.sheep_phase()])
	# Проверка выключением: ручка снята — следующий кусок базовый
	var was_meat: bool = _Opt.meat_yield_bonus
	_Opt.meat_yield_bonus = false
	guard = 0
	# дождаться, пока текущий кусок сдан, и взять следующий
	while guard < 60 * 60 and w.sheep_phase() == Worker.SheepPhase.HAUL:
		await get_tree().physics_frame
		guard += 1
	var carried2 := -1.0
	while guard < 60 * 180 and carried2 < 0.0:
		await get_tree().physics_frame
		guard += 1
		if w.sheep_phase() == Worker.SheepPhase.HAUL and w.carrying_amount > 0.0 \
				and w.carrying_type == Constants.RESOURCE_FOOD:
			carried2 = w.carrying_amount
	var rate_off: float = Worker.farmer_meat_per_sec(P)
	_Opt.meat_yield_bonus = was_meat
	verdict("C3 ручка meat_yield_bonus выключена — кусок и расчётный темп базовые (проверка выключением)",
		carried2 > 0.0 and absf(carried2 - Worker.MEAT_PER_TRIP) <= 0.01 and absf(rate_off - rate0) <= 0.001,
		"кусок %.2f, темп %.3f (база %.3f), физкадров %d" % [carried2, rate_off, rate0, guard])
	_worker_bonus("bonus_meat_pct", 0.0)
	w.take_damage(1e9)
	# ── C4-C5: Кузница с «темпом исследований» ───────────────────────────────
	var sm := Smithy.new()
	sm.faction = P
	main.world_add(sm)
	var sp: Vector3 = base + Vector3(0.0, 0.0, -14.0)
	sm.global_position = Vector3(sp.x, GameManager.get_terrain_height(sp.x, sp.z), sp.z)
	await pframes(2)
	sm.research_id = _Forge.node_id("warrior", "1a")   # чужая вкладка: ускорение общее
	sm.research_time = 600.0
	sm.research_timer = 0.0
	_worker_bonus("bonus_research_pct", 0.5)
	sm._process(1.0)
	var adv_on: float = sm.research_timer
	var was_rs: bool = _Opt.forge_research_speed
	_Opt.forge_research_speed = false
	sm.research_timer = 0.0
	sm._process(1.0)
	var adv_off: float = sm.research_timer
	_Opt.forge_research_speed = was_rs
	verdict("C4 «темп исследований +50 %»: секунда кузницы = 1.5 с исследования любой вкладки",
		absf(adv_on - 1.5) <= 0.001, "%.3f с за 1 с" % adv_on)
	verdict("C5 ручка forge_research_speed выключена — секунда за секунду (проверка выключением)",
		absf(adv_off - 1.0) <= 0.001, "%.3f с за 1 с" % adv_off)
	_worker_bonus("bonus_research_pct", 0.0)
	sm.research_id = ""
	sm.research_time = 0.0
	# ── C6: точечный золотой узел режет цикл только золоту ───────────────────
	var w2: Worker = _spawn("worker", P, base + Vector3(-8.0, 0.0, -8.0)) as Worker
	await pframes(2)
	var gold_node := {}
	for n in _Forge.tree("worker"):
		var d: Dictionary = n
		if float(d.get("bonus_gather_gold", 0.0)) >= 0.2 and float(d.get("bonus_gather_wood", 0.0)) == 0.0:
			gold_node = d
			break
	# Цикл добычи берёт ресурс по жиле, а без жилы — по грузу на руках (Worker._work_res_type)
	w2.carrying_type = Constants.RESOURCE_GOLD
	var cg0: float = w2._cycle_time()
	w2.carrying_type = Constants.RESOURCE_WOOD
	var cw0: float = w2._cycle_time()
	var gval: float = float(gold_node.get("bonus_gather_gold", 0.0))
	_worker_bonus("bonus_gather_gold", gval)
	w2.carrying_type = Constants.RESOURCE_GOLD
	var cg1: float = w2._cycle_time()
	w2.carrying_type = Constants.RESOURCE_WOOD
	var cw1: float = w2._cycle_time()
	_worker_bonus("bonus_gather_gold", 0.0)
	verdict("C6 узел золота (%s +%.0f %%) режет цикл золота ровно на долю, дерево не трогает" % [
		String(gold_node.get("id", "?")), gval * 100.0],
		not gold_node.is_empty() and absf(cg1 - cg0 * (1.0 - gval)) <= 0.01 and absf(cw1 - cw0) <= 0.001,
		"золото %.2f → %.2f с, дерево %.2f → %.2f с" % [cg0, cg1, cw0, cw1])
	w2.take_damage(1e9)
	await pframes(2)
	# ── C7-C8: живое содержание большой армии ────────────────────────────────
	var far: Vector3 = a + Vector3(80.0, 0.0, 80.0)
	var per: int = _UCfg.squad_size("spearman")
	var want_heads: float = _UCfg.FOOD_UPKEEP_BIG_ARMY_HEADS * 1.6
	var nsq: int = int(ceil(want_heads / float(per)))
	for i in range(nsq):
		_squad("spearman", per, far + Vector3(float(i % 6) * 9.0, 0.0, float(i / 6) * 9.0))
	await pframes(int(_UCfg.FOOD_UPKEEP_TICK * 60.0) + 30)
	var heads := 0.0
	var workers := 0
	for sid in GameManager.squads:
		var sq: Dictionary = GameManager.squads[sid]
		if int(sq["faction"]) != P or (sq["members"] as Array).is_empty():
			continue
		if GameManager.squad_is_single_agent(int(sid)):
			for m in sq["members"]:
				if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
					workers += 1
			continue
		heads += float((sq["members"] as Array).size())
	var mult: float = _UCfg.food_upkeep_mult(heads)
	var got: float = float(GameManager.food_upkeep_rate.get(P, 0.0))
	var plain: float = heads * _UCfg.FOOD_UPKEEP_SOLDIER_PER_SEC + float(workers) * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC
	var want: float = heads * _UCfg.FOOD_UPKEEP_SOLDIER_PER_SEC * mult + float(workers) * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC
	verdict("C7 %.0f голов сверх порога %.0f: расход склада = головы × ставка × %.2f (ручка food_big_army)" % [
		heads, _UCfg.FOOD_UPKEEP_BIG_ARMY_HEADS, mult],
		heads > _UCfg.FOOD_UPKEEP_BIG_ARMY_HEADS and mult > 1.2 and absf(got - want) < 0.02 and got > plain * 1.2,
		"%.3f против %.3f в секунду (линейно было бы %.3f)" % [got, want, plain])
	var was_big: bool = _Opt.food_big_army
	_Opt.food_big_army = false
	await pframes(int(_UCfg.FOOD_UPKEEP_TICK * 60.0) + 30)
	var got_off: float = float(GameManager.food_upkeep_rate.get(P, 0.0))
	_Opt.food_big_army = was_big
	verdict("C8 ручка food_big_army выключена — расход линейный (проверка выключением)",
		absf(got_off - plain) < 0.02, "%.3f против %.3f" % [got_off, plain])
