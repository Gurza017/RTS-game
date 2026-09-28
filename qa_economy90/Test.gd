extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЭКОНОМИКА ПАРТИИ НА 90 МИНУТ (ТЗ 24.09.2026, «партия перед сном»)
## ═══════════════════════════════════════════════════════════════════════════
## Печатает экономическую матрицу партии (scripts/economy_model.gd) и
## проверяет СВОЙСТВА заказа — ни одного числа из конфигов стенд не повторяет:
##   A — модель читает цены и темп из конфигов, а не держит свои
##   B — нормы добычи и бригада: помещается в лимит, армию кормят ≤ 20 рабочих
##   C — дилемма кузницы: 65 % закрывается, 100 % — нет
##   D — темп: ряд 1 к 5-й мин, ряд 2 к 15-й, элита дорогая, камень ≤ 4 мин
##   E — живой рабочий: приток по подписи = модели, груз +25 % → сразу ×1.25
##   F — волны на захваченный рудник: 240 с, от полотряда до двух к 45-й мин
## Запуск: godot --headless --path . res://qa_economy90/Test.tscn [-- only=abcdef]

const _M := preload("res://scripts/economy_model.gd")
const _UCfgE := preload("res://scripts/unit_stats_config.gd")
const _ForgeE := preload("res://scripts/forge_config.gd")
const _RaidsE := preload("res://scripts/goblin/GoblinRaids.gd")
const _WorkerE := preload("res://scripts/Worker.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var only: String = "abcdef"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			only = String(a).substr(5)
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

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_economy90: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _run() -> void:
	if "a" in only: _a_model()
	if "b" in only: _b_rates()
	if "c" in only: _c_forge()
	if "d" in only: _d_pacing()
	if "e" in only or "f" in only:
		main = load("res://scenes/Main.tscn").instantiate()
		get_tree().root.add_child(main)
		await pframes(8)
		if main.enemy_ai != null: main.enemy_ai.set_process(false)
		if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
		if GameManager.fog != null: GameManager.fog.enabled = false
		for w in get_tree().get_nodes_in_group("all_units"):
			if w is Unit and (w as Unit).faction != Constants.FACTION_PLAYER:
				(w as Unit).set_tick(false)
		await pframes(4)
		if "e" in only: await _e_worker()
		if "f" in only: await _f_mine_waves()
	_finish()

func _row(title: String, d: Dictionary) -> void:
	print("  %-34s дерево %8.0f  золото %8.0f  камень %8.0f  еда %8.0f" % [title,
		float(d.get(Constants.RESOURCE_WOOD, 0.0)), float(d.get(Constants.RESOURCE_GOLD, 0.0)),
		float(d.get(Constants.RESOURCE_STONE, 0.0)), float(d.get(Constants.RESOURCE_FOOD, 0.0))])

func _sum(d: Dictionary) -> float:
	var s := 0.0
	for k in d.keys():
		s += float(d[k])
	return s

# ─────────────────────────────────────────────────────────────────────────────
func _a_model() -> void:
	print("\n═════ A. МАТРИЦА ПАРТИИ НА %d МИНУТ ═════" % int(_M.SESSION_MIN))
	var w: Dictionary = _M.recommended_workers()
	var tot: int = _M.workers_total(w)
	print("  армия: %d отрядов на поле × потери %.1f = %d отрядов за партию, состав %s"
		% [_M.ARMY_SQUADS_ON_FIELD, _M.LOSS_FACTOR, int(_M.army_squads_total()), str(_M.ARMY_MIX)])
	_row("средний отряд", _M.mean_squad_cost())
	_row("80 отрядов", _M.army_cost())
	_row("постройки " + str(_M.BUILD_PLAN), _M.buildings_cost())
	_row("кузница 100 %", _M.forge_cost_full())
	_row("кузница %d %%" % int(_M.FORGE_TARGET_SHARE * 100.0), _M.forge_cost(_M.FORGE_TARGET_SHARE))
	_row("наём рабочих + содержание", _M.upkeep_cost(float(tot)))
	var bud: Dictionary = _M.session_budget(_M.FORGE_TARGET_SHARE, float(tot))
	_row("ИТОГО (кузница 65 %)", bud)
	_row("ИТОГО (кузница 100 %)", _M.session_budget(1.0, float(tot)))
	_row("стартовый банк", _UCfgE.starting_resources(Constants.FACTION_PLAYER))
	_row("дома (пассивно)", _M.passive_income())
	var per_min := {}
	for r in _M.RES:
		per_min[r] = float(bud[r]) / _M.SESSION_MIN
	_row("нужно в минуту (бюджет / 90)", per_min)
	var sq_sp: Dictionary = _M.squad_cost("spearman")
	verdict("A1 модель берёт цену отряда из TRAINING, а не держит свою",
		sq_sp == _UCfgE.train_cost("barracks", "spearman"), str(sq_sp))
	verdict("A2 плечо модели = плечо подписи притока (Worker.INCOME_NOMINAL_ARM)",
		is_equal_approx(_M.NOMINAL_ARM, float(_WorkerE.INCOME_NOMINAL_ARM)))

func _b_rates() -> void:
	print("\n═════ B. НОРМЫ ДОБЫЧИ И БРИГАДА ═════")
	var w: Dictionary = _M.recommended_workers()
	for r in _M.RES:
		print("  %-6s база %6.1f/мин на рабочего (плечо %.0f м), ветка рабочего ×%.2f, на деле %6.1f/мин → рабочих %d"
			% [_M.res_name(r), _M.worker_rate(r) * 60.0, _M.NOMINAL_ARM, _M.econ_gain(r),
			_M.worker_per_min_effective(r), int(w[r])])
	var tot: int = _M.workers_total(w)
	var cap: int = _UCfgE.pop_worker_cap(int(_M.BUILD_PLAN["house"]), 1)
	print("  рекомендуемая бригада: %d рабочих (+2-4 строителя), лимит при плане домов %d" % [tot, cap])
	verdict("B1 бригада помещается в лимит рабочих", tot <= cap, "%d из %d" % [tot, cap])
	verdict("B2 бригада — десятки, а не сотни (20-60)", tot >= 20 and tot <= 60, "%d" % tot)
	# Постоянный найм войск: 80 отрядов с минуты ARMY_START_MIN до конца партии
	var span: float = _M.SESSION_MIN - _M.ARMY_START_MIN
	var army: Dictionary = _M.army_cost()
	var need_army := 0
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE]:
		need_army += int(ceil(float(army[r]) / (_M.worker_rate(r) * 60.0 * _M.WORKER_EFFICIENCY * span)))
	verdict("B3 постоянный найм армии кормят 15-20 рабочих (с запасом)", need_army <= 20,
		"нужно %d на дерево/золото/камень" % need_army)

func _c_forge() -> void:
	print("\n═════ C. ДИЛЕММА КУЗНИЦЫ ═════")
	var w: Dictionary = _M.recommended_workers()
	var tot: int = _M.workers_total(w)
	var inc: Dictionary = _M.session_income(w)
	var b65: Dictionary = _M.session_budget(_M.FORGE_TARGET_SHARE, float(tot))
	var b100: Dictionary = _M.session_budget(1.0, float(tot))
	_row("приход бригады за партию", inc)
	var ok65 := true
	var worst := 0.0
	var worst_r := ""
	for r in _M.RES:
		if float(inc[r]) < float(b65[r]) * 0.999:
			ok65 = false
		var over: float = float(b100[r]) / maxf(float(inc[r]), 1.0)
		if over > worst:
			worst = over
			worst_r = _M.res_name(r)
	verdict("C1 кузница 65 % закрывается рекомендуемой бригадой", ok65)
	verdict("C2 кузница 100 %% НЕ закрывается ею (дороже хотя бы в %.2f раза)" % _M.FORGE_UNREACHABLE_MARGIN,
		worst >= _M.FORGE_UNREACHABLE_MARGIN, "%s: в %.2f раза" % [worst_r, worst])
	var w100: Dictionary = _M.workers_for(1.0)
	print("  на 100 %% кузницы нужно %d рабочих против %d" % [_M.workers_total(w100), tot])
	# Прогрессия: средняя цена узла по рядам (все вкладки)
	var per_row: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var cnt: Array = [0, 0, 0, 0, 0, 0]
	for n in _ForgeE.all_nodes():
		var d: Dictionary = n
		var row: int = int(d["row"])
		per_row[row] = float(per_row[row]) + float(d.get("cost_wood", 0.0)) \
			+ float(d.get("cost_gold", 0.0)) + float(d.get("cost_stone", 0.0))
		cnt[row] = int(cnt[row]) + 1
	var mono := true
	var line := ""
	for row in range(1, 6):
		per_row[row] = float(per_row[row]) / maxf(float(cnt[row]), 1.0)
		line += "  р%d %.0f" % [row, float(per_row[row])]
		if row > 1 and float(per_row[row]) <= float(per_row[row - 1]):
			mono = false
	print("  средняя цена узла по рядам:" + line)
	verdict("C3 ранние ряды дешевле, поздние дороже (строго растёт, р5 ≥ 4 × р1)",
		mono and float(per_row[5]) >= 4.0 * float(per_row[1]))

func _d_pacing() -> void:
	print("\n═════ D. ТЕМП ДЕЙСТВИЙ ═════")
	var w: Dictionary = _M.recommended_workers()
	for row in [1, 2]:
		var lim: float = float(_M.FORGE_ROW_BY_MIN[row])
		var t: float = _M.forge_row_minute(row, w)
		verdict("D1 узел ряда %d по золоту доступен к %.0f-й минуте" % [row, lim], t <= lim,
			"%.1f мин (кузнице — %.0f %% золота)" % [t, _M.FORGE_GOLD_SHARE * 100.0])
	# Элита: узел элитного ряда стоит не меньше ELITE_MIN_SQUADS отрядов копейщиков
	var sq: float = _sum(_M.squad_cost("spearman"))
	var cheapest := INF
	for n in _ForgeE.tree("spearman"):
		var d: Dictionary = n
		if int(d["row"]) == _M.ELITE_ROW:
			cheapest = minf(cheapest, float(d.get("cost_wood", 0.0)) + float(d.get("cost_gold", 0.0))
				+ float(d.get("cost_stone", 0.0)))
	verdict("D2 элитный ряд %d: узел ≥ %.0f отрядов копейщиков («нанять ИЛИ вкачать»)"
		% [_M.ELITE_ROW, _M.ELITE_MIN_SQUADS], cheapest >= sq * _M.ELITE_MIN_SQUADS,
		"узел %.0f против отряда %.0f (×%.1f)" % [cheapest, sq, cheapest / maxf(sq, 1.0)])
	# Значимое действие с первых минут: стартовая бригада, разложенная как
	# рекомендованная, копит на отряд копейщиков (без банка) не дольше 3 мин
	var tot: float = float(_M.workers_total(w))
	var worst := 0.0
	var c: Dictionary = _M.squad_cost("spearman")
	for r in c.keys():
		var need: float = float(c[r])
		if need <= 0.0:
			continue
		var share: float = float(w.get(r, 0)) / maxf(tot, 1.0) * float(_M.START_WORKERS)
		var per_min: float = maxf(share, 1.0) * _M.worker_rate(int(r)) * 60.0 * _M.WORKER_EFFICIENCY
		worst = maxf(worst, need / per_min)
	verdict("D3 на старте значимое действие (отряд) — не реже раза в %.0f мин" % _M.ACTION_EVERY_MIN_MAX,
		worst <= _M.ACTION_EVERY_MIN_MAX, "%.1f мин" % worst)
	# Камень: самый дорогой по камню узел или постройка (кроме прогрессивного замка)
	var st_need := 0.0
	var who := ""
	for n2 in _ForgeE.all_nodes():
		var d2: Dictionary = n2
		if float(d2.get("cost_stone", 0.0)) > st_need:
			st_need = float(d2.get("cost_stone", 0.0))
			who = String(d2["id"])
	for b in ["barracks", "archery", "tower", "smithy", "house"]:
		var bc: Dictionary = _UCfgE.building_cost(b)
		if float(bc.get(Constants.RESOURCE_STONE, 0.0)) > st_need:
			st_need = float(bc.get(Constants.RESOURCE_STONE, 0.0))
			who = b
	var st_rate: float = float(w[Constants.RESOURCE_STONE]) * _M.worker_rate(Constants.RESOURCE_STONE) \
		* 60.0 * _M.WORKER_EFFICIENCY
	verdict("D4 самую дорогую нужду в камне бригада закрывает за ≤ %.0f мин" % _M.STONE_CLOSE_MIN_MAX,
		st_need / maxf(st_rate, 1.0) <= _M.STONE_CLOSE_MIN_MAX,
		"%s: %.0f камня / %.0f в мин = %.1f мин" % [who, st_need, st_rate, st_need / maxf(st_rate, 1.0)])

# ─────────────────────────────────────────────────────────────────────────────
func _e_worker() -> void:
	print("\n═════ E. ЖИВОЙ РАБОЧИЙ: ПРИТОК И ГРУЗ ═════")
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	var wk: Unit = Building.PRELOAD_SCENES["worker"].instantiate()
	wk.faction = Constants.FACTION_PLAYER
	main.world_add(wk)
	wk.global_position = Vector3(a.x + 30.0, GameManager.get_terrain_height(a.x + 30.0, a.z), a.z)
	wk.sync_row()
	await pframes(2)
	wk.set("_gather_res_type", Constants.RESOURCE_WOOD)
	var base: float = float(wk.call("nominal_income_per_sec"))
	var model: float = _M.worker_rate(Constants.RESOURCE_WOOD)
	verdict("E1 подпись притока рабочего = модели (дерево, плечо %.0f м)" % _M.NOMINAL_ARM,
		absf(base - model) <= model * 0.02, "рабочий %.3f/с, модель %.3f/с" % [base, model])
	# +25 % груза — прибавка видна в ТОТ ЖЕ кадр, без ожидания ходки
	var ub: Dictionary = GameManager.unit_bonuses
	if not ub.has(Constants.FACTION_PLAYER): ub[Constants.FACTION_PLAYER] = {}
	var pf: Dictionary = ub[Constants.FACTION_PLAYER]
	if not pf.has("worker"): pf["worker"] = {}
	var pw: Dictionary = pf["worker"]
	var was: float = float(pw.get("bonus_carry_pct", 0.0))
	pw["bonus_carry_pct"] = was + 0.25
	var boosted: float = float(wk.call("nominal_income_per_sec"))
	pw["bonus_carry_pct"] = was
	verdict("E2 груз +25 % → приток сразу ×1.25", absf(boosted / maxf(base, 0.0001) - 1.25) <= 0.01,
		"%.3f → %.3f (×%.3f)" % [base, boosted, boosted / maxf(base, 0.0001)])
	wk.take_damage(1e9)

func _f_mine_waves() -> void:
	print("\n═════ F. ВОЛНЫ НА ЗАХВАЧЕННЫЙ РУДНИК ═════")
	verdict("F1 интервал волн 240 с (3-5 минут)", _M.MINE_WAVE_INTERVAL_SEC >= 180.0
		and _M.MINE_WAVE_INTERVAL_SEC <= 300.0, "%.0f с" % _M.MINE_WAVE_INTERVAL_SEC)
	var s0: float = _M.mine_wave_squads(0.0)
	var s45: float = _M.mine_wave_squads(45.0 * 60.0)
	var s20: float = _M.mine_wave_squads(20.0 * 60.0)
	var s80: float = _M.mine_wave_squads(80.0 * 60.0)
	verdict("F2 волна растёт плавно: полотряда в начале, 2 отряда к 45-й, дальше не растёт",
		is_equal_approx(s0, 0.5) and is_equal_approx(s45, 2.0) and s20 > s0 and s20 < s45
		and is_equal_approx(s80, 2.0), "0 мин %.2f, 20 мин %.2f, 45 мин %.2f, 80 мин %.2f" % [s0, s20, s45, s80])
	# Живой рудник: берём любой Mine на карте и отдаём игроку захватом
	var mine: Mine = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Mine and not (b as Building).is_dead():
			mine = b
			break
	if mine == null:
		for n in get_tree().root.find_children("*", "Node3D", true, false):
			if n is Mine:
				mine = n
				break
	verdict("F3 на карте есть рудник", mine != null)
	if mine == null:
		return
	if int(mine.faction) == Constants.FACTION_PLAYER:
		mine.set_owner_faction(Constants.FACTION_GOBLIN)
	mine.set_owner_faction(Constants.FACTION_PLAYER)
	var gr = _RaidsE.new()
	gr.setup(main, main.goblin_ai.village if main.goblin_ai != null else Vector3(150.0, 0.0, -80.0))
	var t0 := 100.0
	gr.tick(t0, Vector3.ZERO)
	gr.tick(t0 + _M.MINE_WAVE_INTERVAL_SEC - 1.0, Vector3.ZERO)
	var early: int = gr.mine_waves_launched
	gr.tick(t0 + _M.MINE_WAVE_INTERVAL_SEC + 1.0, Vector3.ZERO)
	var size_sq: int = _UCfgE.squad_size("goblin_spearman")
	var exp1: float = _M.mine_wave_squads(t0 + _M.MINE_WAVE_INTERVAL_SEC + 1.0) * float(size_sq)
	verdict("F4 после захвата первая волна — через интервал, не раньше", early == 0
		and gr.mine_waves_launched == 1, "до срока %d, после %d" % [early, gr.mine_waves_launched])
	verdict("F5 ранняя волна — около полуотряда", absf(float(gr.last_mine_wave_men) - exp1) <= 1.5,
		"%d бойцов при ожидаемых %.1f (отряд %d)" % [gr.last_mine_wave_men, exp1, size_sq])
	var r0: Dictionary = gr.raids[gr.raids.size() - 1]
	verdict("F6 волна идёт на рудник, строем через сбор", (r0["target"] as Vector3).distance_to(mine.global_position) < 0.5
		and String(r0["state"]) == "assemble")
	# Поздняя: 45-я минута — два полных отряда
	var t45: float = 45.0 * 60.0
	gr._mine_next[mine.get_instance_id()] = t45
	gr.tick(t45 + 0.5, Vector3.ZERO)
	verdict("F7 к 45-й минуте волна — два полных отряда", gr.last_mine_wave_men == 2 * size_sq,
		"%d бойцов (отряд %d)" % [gr.last_mine_wave_men, size_sq])
	# Потерянный рудник волн не получает
	mine.set_owner_faction(Constants.FACTION_GOBLIN)
	var before: int = gr.mine_waves_launched
	gr.tick(t45 + 2.0 * _M.MINE_WAVE_INTERVAL_SEC, Vector3.ZERO)
	verdict("F8 рудник отбит обратно — волн больше нет", gr.mine_waves_launched == before)
	for r in gr.raids:
		for sid in (r as Dictionary)["sids"]:
			var raw: Variant = GameManager.squads.get(int(sid))
			if raw != null:
				for m in (raw as Dictionary)["members"]:
					if is_instance_valid(m) and not (m as Unit).is_dead():
						(m as Unit).take_damage(1e9)
