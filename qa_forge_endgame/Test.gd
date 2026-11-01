extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_FORGE_ENDGAME — ТЗ 28.10.2026, п. 2: сток ресурсов в Кузнице игрока.
## К первому часу у игрока копятся сотни тысяч ресурсов — ряды 3-5 древа
## обязаны стоить по-настоящему дорого (эндгейм — десятки и сотни тысяч), ряды
## 1-2 — остаться доступными в первые 15-20 мин, время любого узла ≤ 90 с.
## Чисел конфига стенд не повторяет — проверяет СВОЙСТВА; ручка
## forge_endgame_sink проверена выключением (A7, B-печать «до»).
## ═══════════════════════════════════════════════════════════════════════════
## A — таблица цен по рядам каждой вкладки (ядро «до» и со стоком «после»),
##     время ≤ 90 с, ряды 1-2 не тронуты, рост по рядам, эндгейм ≥ десятков тысяч.
## B — модель партии (economy_model): излишек богатой партии на 30/45/60/90 мин,
##     полная кузница ≥ излишка к 60-й, ряды 1-2 по карману к 20-й мин,
##     самый дорогой узел достижим к 90-й (сток, а не стена).
## C — красный ИИ на живой сцене: ряды 1-2 исследует, на цене стока не виснет
##     и при большом банке уходит в ряд 3.
## Запуск: godot --headless --path . res://qa_forge_endgame/Test.tscn [-- only=abc]
##         [-- knob=forge_endgame_sink:0]

const _M := preload("res://scripts/economy_model.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const E := Constants.FACTION_ENEMY
## Граница владельца: «в пределах полутора минут»
const TIME_MAX_SEC := 90.0
## «Эндгейм — десятки и сотни тысяч»: средний узел ряда 5 и самый дорогой
const ENDGAME_AVG_MIN := 50000.0
const ENDGAME_TOP_MIN := 100000.0
## «Особенно 3-й и 4-й этажи»: средний узел
const ROW3_AVG_MIN := 5000.0
const ROW4_AVG_MIN := 20000.0
## «Сотни тысяч к первому часу» — модель обязана воспроизводить жалобу
const SURPLUS_60_MIN := 100000.0

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
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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
	print("\n═════ ИТОГ qa_forge_endgame: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _run() -> void:
	print("  ручка forge_endgame_sink=%s" % str(_Opt.forge_endgame_sink))
	if "a" in _only: _a_table()
	if "b" in _only: _b_model()
	if "c" in _only:
		main = load("res://scenes/Main.tscn").instantiate()
		get_tree().root.add_child(main)
		await pframes(8)
		await _c_ai()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
func _sum(c: Dictionary) -> float:
	var s := 0.0
	for k in c.keys():
		s += float(c[k])
	return s

func _node_sum(d: Dictionary, with_sink: bool) -> float:
	return _sum(_M.forge_node_cost(d, with_sink))

func _fmt(v: float) -> String:
	if v >= 10000.0:
		return "%.0fk" % (v / 1000.0)
	return "%.0f" % v

func _res_line(title: String, d: Dictionary) -> void:
	print("  %-36s дерево %9.0f  золото %9.0f  камень %8.0f  еда %9.0f  | сумма %9.0f" % [title,
		float(d.get(Constants.RESOURCE_WOOD, 0.0)), float(d.get(Constants.RESOURCE_GOLD, 0.0)),
		float(d.get(Constants.RESOURCE_STONE, 0.0)), float(d.get(Constants.RESOURCE_FOOD, 0.0)), _sum(d)])

func _a_table() -> void:
	print("\n═════ A. ЦЕНЫ ДРЕВА ПО РЯДАМ (средний узел: ядро → со стоком; д/з/к/е — средний узел после) ═════")
	var t_bad: Array = []
	var t_max := 0.0
	var early_bad: Array = []
	var stone_bad: Array = []
	var mono_bad: Array = []
	var row_avg: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var row_cnt: Array = [0, 0, 0, 0, 0, 0]
	var row5_min := INF
	var row5_max := 0.0
	var row5_max_id := ""
	var grand_core := 0.0
	var grand := 0.0
	for tab in _Forge.UNIT_TABS:
		var uid: String = String(tab)
		var per_row_core: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		var per_row: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		var per_res: Array = []
		var cnt: Array = [0, 0, 0, 0, 0, 0]
		for _i in range(6):
			per_res.append({})
		for n in _Forge.tree(uid):
			var d: Dictionary = n
			if not d.has("core_cost"):
				continue
			var row: int = int(d["row"])
			var t: float = float(d.get("research_time", 0.0))
			t_max = maxf(t_max, t)
			if t > TIME_MAX_SEC:
				t_bad.append("%s=%.0f" % [String(d["id"]), t])
			var core: float = _node_sum(d, false)
			var now: float = _node_sum(d, true)
			per_row_core[row] = float(per_row_core[row]) + core
			per_row[row] = float(per_row[row]) + now
			cnt[row] = int(cnt[row]) + 1
			var pr: Dictionary = per_res[row]
			var nc: Dictionary = _M.forge_node_cost(d, true)
			for r in nc.keys():
				pr[r] = float(pr.get(r, 0.0)) + float(nc[r])
			row_avg[row] = float(row_avg[row]) + now
			row_cnt[row] = int(row_cnt[row]) + 1
			grand_core += core
			grand += now
			if row <= 2 and absf(now - core) > 0.5:
				early_bad.append(String(d["id"]))
			var cc: Dictionary = d["core_cost"]
			if absf(float(d.get("cost_stone", 0.0)) - float(cc.get("cost_stone", 0.0))) > 0.5:
				stone_bad.append(String(d["id"]))
			if row == 5:
				row5_min = minf(row5_min, now)
				if now > row5_max:
					row5_max = now
					row5_max_id = String(d["id"])
		var tab_core := 0.0
		var tab_now := 0.0
		print("  ── вкладка %s ──" % uid)
		for row in range(1, 6):
			var c: int = maxi(int(cnt[row]), 1)
			tab_core += float(per_row_core[row])
			tab_now += float(per_row[row])
			var pr2: Dictionary = per_res[row]
			print("    ряд %d: узел %7s → %7s  (д %7s з %7s к %6s е %7s)  ряд %8s → %8s" % [row,
				_fmt(float(per_row_core[row]) / c), _fmt(float(per_row[row]) / c),
				_fmt(float(pr2.get(Constants.RESOURCE_WOOD, 0.0)) / c), _fmt(float(pr2.get(Constants.RESOURCE_GOLD, 0.0)) / c),
				_fmt(float(pr2.get(Constants.RESOURCE_STONE, 0.0)) / c), _fmt(float(pr2.get(Constants.RESOURCE_FOOD, 0.0)) / c),
				_fmt(float(per_row_core[row])), _fmt(float(per_row[row]))])
			if row > 1 and float(per_row[row]) / c <= float(per_row[row - 1]) / maxi(int(cnt[row - 1]), 1):
				mono_bad.append("%s р%d" % [uid, row])
		print("    вся вкладка: %s → %s" % [_fmt(tab_core), _fmt(tab_now)])
	print("  ВСЯ КУЗНИЦА: %s → %s" % [_fmt(grand_core), _fmt(grand)])
	for row in range(1, 6):
		row_avg[row] = float(row_avg[row]) / maxf(float(row_cnt[row]), 1.0)
	verdict("A1 время любого узла любой вкладки ≤ %.0f с" % TIME_MAX_SEC, t_bad.is_empty(),
		"максимум %.0f с %s" % [t_max, str(t_bad)])
	verdict("A2 ряды 1-2 сток не трогает (цена = ядро)", early_bad.is_empty(), str(early_bad))
	verdict("A3 на каждой вкладке средний узел ряда строго дороже предыдущего ряда", mono_bad.is_empty(), str(mono_bad))
	if not _Opt.forge_endgame_sink:
		print("  (ручка выключена — A4-A6 проверяют сток и обязаны краснеть)")
	verdict("A4 эндгейм: средний узел ряда 5 ≥ %s, самый дорогой ≥ %s, самый дешёвый — десятки тысяч" % [
		_fmt(ENDGAME_AVG_MIN), _fmt(ENDGAME_TOP_MIN)],
		float(row_avg[5]) >= ENDGAME_AVG_MIN and row5_max >= ENDGAME_TOP_MIN and row5_min >= 10000.0,
		"средний %s, %s = %s, дешёвый %s" % [_fmt(float(row_avg[5])), row5_max_id, _fmt(row5_max), _fmt(row5_min)])
	verdict("A5 «этажи» 3 и 4 дороги: средний узел ряда 3 ≥ %s, ряда 4 ≥ %s" % [_fmt(ROW3_AVG_MIN), _fmt(ROW4_AVG_MIN)],
		float(row_avg[3]) >= ROW3_AVG_MIN and float(row_avg[4]) >= ROW4_AVG_MIN,
		"ряд 3 %s, ряд 4 %s" % [_fmt(float(row_avg[3])), _fmt(float(row_avg[4]))])
	verdict("A6 камень сток не трогает (самый редкий ресурс партии)", stone_bad.is_empty(), str(stone_bad))
	# Проверка выключением: ручка снята — цены всех узлов = ядро, древо пересобрано
	var was: bool = _Opt.forge_endgame_sink
	_Opt.forge_endgame_sink = false
	var off_sum := 0.0
	var off_bad := 0
	for n in _Forge.all_nodes():
		var d: Dictionary = n
		if not d.has("core_cost"):
			continue
		off_sum += _node_sum(d, true)
		if absf(_node_sum(d, true) - _node_sum(d, false)) > 0.5:
			off_bad += 1
	_Opt.forge_endgame_sink = was
	var on_sum := 0.0
	for n in _Forge.all_nodes():
		on_sum += _node_sum(n as Dictionary, true)
	verdict("A7 ручка forge_endgame_sink выключена — цены = ядро, кузница дешевле в разы (проверка выключением)",
		off_bad == 0 and (not was or on_sum >= off_sum * 3.0),
		"выкл %s, вкл %s (×%.1f), расхождений с ядром при выкл %d" % [_fmt(off_sum), _fmt(on_sum), on_sum / maxf(off_sum, 1.0), off_bad])

# ─────────────────────────────────────────────────────────────────────────────
func _b_model() -> void:
	print("\n═════ B. МОДЕЛЬ: ИЗЛИШЕК ПАРТИИ И ЁМКОСТЬ СТОКА ═════")
	var rich: Dictionary = _M.RICH_WORKERS
	var rec: Dictionary = _M.recommended_workers()
	print("  богатая бригада %s (%d), рекомендуемая %s (%d)" % [str(rich), _M.workers_total(rich), str(rec), _M.workers_total(rec)])
	print("  ── излишек богатой партии (куплены ряды 1-%d всех вкладок к %.0f-й мин) ──" % [_M.FORGE_CORE_ROWS, _M.FORGE_CORE_BY_MIN])
	var sur := {}
	for t in _M.SURPLUS_MINUTES:
		var s: Dictionary = _M.surplus_at(float(t), rich)
		sur[int(t)] = s
		_res_line("%2.0f мин: приход − расход" % float(t), s)
	print("  ── ёмкость стока ──")
	var deep: Dictionary = _M.forge_cost_full(true)
	var core_rows: Dictionary = _M.forge_cost_full(true, _M.FORGE_CORE_ROWS)
	var sink_now := {}
	var sink_core := {}
	var core_full: Dictionary = _M.forge_cost_full(false)
	for r in _M.RES:
		sink_now[r] = float(deep[r]) - float(core_rows[r])
		sink_core[r] = float(core_full[r]) - float(core_rows[r])
	_res_line("ряды 3-5, ядро (до)", sink_core)
	_res_line("ряды 3-5, со стоком (после)", sink_now)
	for t2 in _M.SURPLUS_MINUTES:
		var s2: Dictionary = sur[int(t2)]
		print("  %2.0f мин: излишек %s; ряды 3-5 до %s (остаток %s), после %s (остаток %s)" % [float(t2),
			_fmt(_M.surplus_total(s2)), _fmt(_sum(sink_core)), _fmt(_M.surplus_total(s2) - _sum(sink_core)),
			_fmt(_sum(sink_now)), _fmt(_M.surplus_total(s2) - _sum(sink_now))])
	var s60: float = _M.surplus_total(sur[60])
	var s90: float = _M.surplus_total(sur[90])
	verdict("B1 модель воспроизводит жалобу: излишек богатой партии к 60-й мин ≥ %s" % _fmt(SURPLUS_60_MIN),
		s60 >= SURPLUS_60_MIN, _fmt(s60))
	# По каждому копящемуся ресурсу отдельно: излишек дерева (главный по телеметрии) не должен
	# покрываться прежними ценами рядов 3-5 — именно это и было жалобой
	var b2 := true
	var b3 := true
	var bd := ""
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD]:
		var s60r: float = float((sur[60] as Dictionary)[r])
		var s90r: float = float((sur[90] as Dictionary)[r])
		if float(sink_now[r]) < s60r: b2 = false
		if float(sink_now[r]) < s90r: b3 = false
		bd += "%s: ряды 3-5 %s (до %s), излишек 60 мин %s, 90 мин %s; " % [_M.res_name(int(r)), _fmt(float(sink_now[r])),
			_fmt(float(sink_core[r])), _fmt(s60r), _fmt(s90r)]
	verdict("B2 ряды 3-5 всех вкладок съедают излишек дерева и золота к 60-й мин (сумма %s против %s)" % [
		_fmt(_sum(sink_now)), _fmt(s60)], b2 and _sum(sink_now) >= s60, bd)
	verdict("B3 и к 90-й: сток не выбирается до конца партии (сумма %s против %s)" % [_fmt(_sum(sink_now)), _fmt(s90)],
		b3 and _sum(sink_now) >= s90)
	# Самый дорогой узел — сток, а не стена: по каждому ресурсу он достижим излишком к 90-й мин
	var top: Dictionary = {}
	var top_sum := 0.0
	for n in _Forge.all_nodes():
		var d: Dictionary = n
		if _node_sum(d, true) > top_sum:
			top_sum = _node_sum(d, true)
			top = d
	var tc: Dictionary = _M.forge_node_cost(top, true)
	var reach := true
	var s90d: Dictionary = sur[90]
	for r in _M.RES:
		if r == Constants.RESOURCE_FOOD:
			continue   # еда — узкое место по замыслу (qa_economy90 C1б): её добирают рынком и веткой мяса
		if float(tc[r]) > maxf(float(s90d[r]), 0.0):
			reach = false
	verdict("B4 самый дорогой узел (%s, %s) достижим излишком к 90-й мин по дереву, золоту и камню" % [
		String(top.get("id", "?")), _fmt(top_sum)], reach,
		"узел д%s з%s к%s, излишек д%s з%s к%s" % [_fmt(float(tc[Constants.RESOURCE_WOOD])), _fmt(float(tc[Constants.RESOURCE_GOLD])),
			_fmt(float(tc[Constants.RESOURCE_STONE])), _fmt(float(s90d[Constants.RESOURCE_WOOD])),
			_fmt(float(s90d[Constants.RESOURCE_GOLD])), _fmt(float(s90d[Constants.RESOURCE_STONE]))])
	# Ряды 1-2: рекомендуемая (не богатая) бригада к 20-й мин успевает их целиком по дереву/золоту/камню
	var s20: Dictionary = _M.surplus_at(_M.FORGE_CORE_BY_MIN, rec, _M.FORGE_CORE_ROWS)
	_res_line("20 мин, рекомендуемая бригада, ряды 1-2", s20)
	var ok20 := true
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE]:
		if float(s20[r]) < 0.0:
			ok20 = false
	verdict("B5 ряды 1-2 всех вкладок по карману рекомендуемой бригаде к %.0f-й мин (дерево, золото, камень)" % _M.FORGE_CORE_BY_MIN, ok20)
	for row in [1, 2]:
		var tm: float = _M.forge_row_minute(row, rec)
		verdict("B6 узел ряда %d доступен по золоту к %.0f-й мин (как до стока)" % [row, float(_M.FORGE_ROW_BY_MIN[row])],
			tm <= float(_M.FORGE_ROW_BY_MIN[row]), "%.1f мин" % tm)

# ─────────────────────────────────────────────────────────────────────────────
func _ai_nodes() -> Array:
	var out: Array = []
	var branches: Array = _AICfg.combat_types().duplicate()
	branches.append_array(_AICfg.AI_FORGE_EXTRA_BRANCHES)
	for t in branches:
		for n in _Forge.tree(String(t)):
			if (n as Dictionary).has("core_cost"):
				out.append(n)
	return out

func _researched_rows(nodes: Array) -> Array:
	var rows: Array = [0, 0, 0, 0, 0, 0]
	for n in nodes:
		var d: Dictionary = n
		if GameManager.is_researched(E, String(d["id"])):
			rows[int(d["row"])] = int(rows[int(d["row"])]) + 1
	return rows

var pick_log: Array = []
## Гонять кузницу ИИ: заказ → мгновенное завершение, пока ИИ заказывает
func _drive(ai, smithy: Smithy, max_iter: int) -> int:
	var idle := 0
	var picks := 0
	for _i in range(max_iter):
		var before: String = smithy.research_id
		var qb: int = smithy.research_queue.size()
		ai._research_forge(smithy)
		var took: bool = smithy.research_id != before or smithy.research_queue.size() != qb
		if took:
			picks += 1
			pick_log.append(smithy.research_id)
		for _k in range(8):
			smithy._process(1000.0)
		if took:
			idle = 0
		else:
			idle += 1
			if idle >= 3:
				break
	return picks

## Один прогон ИИ: банк ровно на ряды 1-2 своих веток (+ резервы ИИ), затем банк в миллионы
func _ai_run(ai, smithy: Smithy, nodes: Array, sink: bool) -> Dictionary:
	var was: bool = _Opt.forge_endgame_sink
	_Opt.forge_endgame_sink = sink
	GameManager.reset_research()
	pick_log.clear()
	var early_cost := {}
	var n_early := 0
	for n in _ai_nodes():
		var d: Dictionary = n
		if int(d["row"]) <= 2:
			n_early += 1
			var c: Dictionary = _M.forge_node_cost(d, true)
			for r in c.keys():
				early_cost[r] = float(early_cost.get(r, 0.0)) + float(c[r])
	for r in _M.RES:
		ResourceManager.set_amount(E, int(r), float(early_cost.get(r, 0.0)) + 1000.0)
	ResourceManager.add_resource(E, Constants.RESOURCE_GOLD, _AICfg.AI_RESEARCH_GOLD_RESERVE)
	ResourceManager.add_resource(E, Constants.RESOURCE_WOOD, _AICfg.AI_RESEARCH_WOOD_RESERVE)
	var p1: int = _drive(ai, smithy, 200)
	var rows1: Array = _researched_rows(_ai_nodes())
	var log1: Array = pick_log.duplicate()
	var idle1: bool = smithy.research_id.is_empty() and smithy.research_queue.is_empty()
	for r2 in _M.RES:
		ResourceManager.set_amount(E, int(r2), 5000000.0)
	var p2: int = _drive(ai, smithy, 200)
	var rows2: Array = _researched_rows(_ai_nodes())
	_Opt.forge_endgame_sink = was
	print("  сток %s: банк рядов 1-2 → по рядам %s (заказов %d, узлов рядов 1-2 в ветках %d); банк в миллионы → %s (заказов %d)" % [
		"вкл" if sink else "выкл", str(rows1.slice(1)), p1, n_early, str(rows2.slice(1)), p2])
	print("    порядок на банке рядов 1-2: %s" % str(log1))
	return {"rows1": rows1, "rows2": rows2, "p1": p1, "p2": p2, "idle1": idle1}

func _c_ai() -> void:
	print("
═════ C. КРАСНЫЙ ИИ: РЯДЫ 1-2 И ЦЕНА СТОКА ═════")
	var ai = main.enemy_ai
	if ai == null:
		verdict("C0 на сцене есть красный ИИ", false)
		return
	ai.set_process(false)
	ai._peace_over = true
	var smithy := Smithy.new()
	smithy.faction = E
	main.world_add(smithy)
	smithy.global_position = Vector3(80.0, 0.0, 40.0)
	await pframes(4)
	print("  ветки ИИ %s + %s" % [str(_AICfg.combat_types()), str(_AICfg.AI_FORGE_EXTRA_BRANCHES)])
	var on: Dictionary = _ai_run(ai, smithy, [], true)
	var off: Dictionary = _ai_run(ai, smithy, [], false)
	var r1: Array = on["rows1"]
	var r2: Array = on["rows2"]
	var early_on: int = int(r1[1]) + int(r1[2])
	var early_rich: int = int(r2[1]) + int(r2[2])
	var early_off: int = int((off["rows1"] as Array)[1]) + int((off["rows1"] as Array)[2])
	# «Ценные» для ИИ узлы рядов 1-2 — те, что он берёт с бесконечным банком (у колонки D и узлов
	# без весов AI_FORGE_WEIGHTS оценка ноль — так было и до стока)
	verdict("C1 на банке рядов 1-2 ИИ изучает ряды 1 и 2 (≥ 85 % узлов, которые он вообще берёт)",
		int(r1[1]) > 0 and int(r1[2]) > 0 and float(early_on) >= 0.85 * float(early_rich),
		"%d из %d" % [early_on, early_rich])
	verdict("C2 ИИ не виснет на цене стока: заказы кончаются сами, кузница пуста",
		bool(on["idle1"]) and int(on["p1"]) < 200 and int(on["p2"]) < 200,
		"заказов %d / %d" % [int(on["p1"]), int(on["p2"])])
	verdict("C3 с банком в миллионы ИИ продолжает в ряд 3+ (сток — цена, а не стена)",
		int(r2[3]) > 0, "по рядам %s" % str(r2.slice(1)))
	verdict("C4 со стоком ИИ проходит ряды 1-2 не хуже, чем без него (проверка выключением)",
		early_on >= early_off, "со стоком %d, без %d" % [early_on, early_off])
	GameManager.reset_research()
	smithy.queue_free()
	await pframes(2)
