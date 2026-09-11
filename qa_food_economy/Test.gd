extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СОДЕРЖАНИЕ АРМИИ ЕДОЙ И ГОЛОД (заказ владельца, 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A БАЛАНС — из констант: десять домов кормят ровно 30 рабочих и 15
##     отрядов; ключ bonus_build есть; кузница строится вдвое дольше бараков;
##     цена узла кузницы умеет еду.
##   B РАСХОД — живые рабочие и боевые отряды съедают ожидаемое за 5 с,
##     расход отдаётся складу и виден в HUD как «−N».
##   C ГОЛОД — склад пуст: мораль отряда вне боя тает до пола и не ниже,
##     еда вернулась — голод снят, мораль растёт.
##   D ТЕМП СТРОЙКИ — улучшение bonus_build ускоряет площадку.
## Запуск: godot --headless --path . res://qa_food_economy/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с"); _finish())

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

func _finish() -> void:
	print("\n═════ ИТОГ qa_food_economy: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn_squad(kind: String, at: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var scene: PackedScene = Building.PRELOAD_SCENES[kind]
	for i in range(n):
		var u: Unit = scene.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var px: float = at.x + float(i % 3) * 0.7
		var pz: float = at.z + float(i / 3) * 0.7
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
	return sid

func _food() -> float:
	return ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD)

func _kill_player_units() -> void:
	for n in get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(n) and n is Unit and not (n as Unit).is_dead():
			(n as Unit).take_damage(1.0e9)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)

	# ── A. Баланс из констант ──────────────────────────────────────────────
	print("\n═════ A. БАЛАНС ═════")
	var houses10: float = 10.0 * _UCfg.HOUSE_FOOD_INCOME / _UCfg.HOUSE_FOOD_INTERVAL
	var need: float = 30.0 * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC + 15.0 * _UCfg.FOOD_UPKEEP_SQUAD_PER_SEC
	verdict("A1 десять домов кормят ровно 30 рабочих и 15 отрядов (±2 %)",
		absf(houses10 - need) <= need * 0.02, "дома %.3f еды/с, нужно %.3f" % [houses10, need])
	verdict("A2 отряд копейщиков ест около 60 еды за 10 минут",
		absf(_UCfg.FOOD_UPKEEP_SQUAD_PER_SEC * 600.0 - 60.0) <= 6.0,
		"%.0f за 10 мин" % (_UCfg.FOOD_UPKEEP_SQUAD_PER_SEC * 600.0))
	verdict("A3 кузница строится не меньше чем вдвое дольше бараков",
		_UCfg.building_stat("smithy", "build_time", 0.0) >= 2.0 * _UCfg.building_stat("barracks", "build_time", 1.0),
		"кузница %.0f с, бараки %.0f с" % [_UCfg.building_stat("smithy", "build_time", 0.0), _UCfg.building_stat("barracks", "build_time", 0.0)])
	verdict("A4 ключ bonus_build в BONUS_KEYS", _UCfg.BONUS_KEYS.has("bonus_build"))
	var has_build := false
	var has_gather := false
	var food_priced := false
	for node in _Forge.tree("worker"):
		var nd: Dictionary = node
		if float(nd.get("bonus_build", 0.0)) > 0.0:
			has_build = true
		if float(nd.get("bonus_gather", 0.0)) > 0.0:
			has_gather = true
		if _UCfg.upgrade_cost(nd).has(Constants.RESOURCE_FOOD):
			food_priced = true
	verdict("A5 в ветке рабочего есть улучшения темпа добычи и темпа стройки", has_build and has_gather)
	verdict("A6 цена узла кузницы умеет еду (cost_food → RESOURCE_FOOD)", food_priced)

	# ── B. Расход ──────────────────────────────────────────────────────────
	print("\n═════ B. РАСХОД ═════")
	_kill_player_units()
	await pframes(3)
	var base := Vector3(-120.0, 0.0, -60.0)
	var workers: Array = []
	for i in range(3):
		var w: Unit = (Building.PRELOAD_SCENES["worker"] as PackedScene).instantiate()
		w.faction = Constants.FACTION_PLAYER
		main.world_add(w)
		var wp: Vector3 = base + Vector3(float(i) * 0.8, 0.0, 0.0)
		w.global_position = Vector3(wp.x, GameManager.get_terrain_height(wp.x, wp.z), wp.z)
		w.sync_row()
		GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "worker"), w)
		workers.append(w)
	var sid_a: int = _spawn_squad("spearman", base + Vector3(0.0, 0.0, 6.0), 6)
	var sid_b: int = _spawn_squad("archer", base + Vector3(6.0, 0.0, 6.0), 6)
	await pframes(2)
	ResourceManager.set_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD, 1000.0)
	var f0: float = _food()
	await pframes(60 * 5)
	var rate: float = 3.0 * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC + 2.0 * _UCfg.FOOD_UPKEEP_SQUAD_PER_SEC
	var ate: float = f0 - _food()
	verdict("B1 три рабочих и два отряда съели ожидаемое за 5 с (±25 %)",
		ate >= rate * 5.0 * 0.75 and ate <= rate * 5.0 * 1.25 + 0.1,
		"съедено %.2f при ожидаемых %.2f" % [ate, rate * 5.0])
	verdict("B2 расход отдан складу и считает 3 рабочих + 2 отряда",
		is_equal_approx(ResourceManager.upkeep_rate(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD), rate)
			and int(GameManager.food_upkeep_workers.get(Constants.FACTION_PLAYER, 0)) == 3
			and int(GameManager.food_upkeep_squads.get(Constants.FACTION_PLAYER, 0)) == 2,
		"расход %.3f/с, рабочих %d, отрядов %d" % [ResourceManager.upkeep_rate(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD),
			int(GameManager.food_upkeep_workers.get(Constants.FACTION_PLAYER, 0)), int(GameManager.food_upkeep_squads.get(Constants.FACTION_PLAYER, 0))])
	var hud = main.hud
	var lbl: Label = hud._res_income_labels.get(Constants.RESOURCE_FOOD)
	await frames(3)
	verdict("B3 в панели ресурсов у еды виден расход «−N»",
		lbl != null and lbl.visible and lbl.text.contains("−"), "текст «%s»" % (lbl.text if lbl else "нет"))
	verdict("B4 голода нет, пока склад не пуст", not GameManager.is_starving(Constants.FACTION_PLAYER))

	# ── C. Голод ───────────────────────────────────────────────────────────
	print("\n═════ C. ГОЛОД ═════")
	ResourceManager.set_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD, 0.0)
	GameManager.squads[sid_a]["morale"] = _UCfg.MORALE_MAX
	await pframes(60 * 2)
	verdict("C1 склад пуст — объявлен голод", GameManager.is_starving(Constants.FACTION_PLAYER))
	var m1: float = float(GameManager.squads[sid_a]["morale"])
	await pframes(60 * 4)
	var m2: float = float(GameManager.squads[sid_a]["morale"])
	verdict("C2 мораль отряда вне боя тает (%.1f → %.1f)" % [m1, m2], m2 < m1 - 1.0)
	await pframes(60 * 40)
	var m3: float = float(GameManager.squads[sid_a]["morale"])
	var floor_m: float = _UCfg.MORALE_MAX * _UCfg.STARVE_MORALE_FLOOR
	verdict("C3 …но не ниже пола голода (%.0f %% — выше порога паники)" % (_UCfg.STARVE_MORALE_FLOOR * 100.0),
		m3 >= floor_m - _UCfg.STARVE_MORALE_PER_SEC and m3 <= floor_m + 1.0
			and _UCfg.STARVE_MORALE_FLOOR > _UCfg.PANIC_THRESHOLD,
		"мораль %.1f, пол %.1f" % [m3, floor_m])
	verdict("C4 цифра расхода в HUD покраснела", lbl != null
		and lbl.get_theme_color("font_color").r > 0.8)
	ResourceManager.set_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD, 1000.0)
	await pframes(60 * 3)
	var m4: float = float(GameManager.squads[sid_a]["morale"])
	verdict("C5 еда вернулась — голод снят, мораль растёт",
		not GameManager.is_starving(Constants.FACTION_PLAYER) and m4 > m3 + 1.0, "мораль %.1f → %.1f" % [m3, m4])

	# ── D. Темп стройки от улучшения ───────────────────────────────────────
	print("\n═════ D. ТЕМП СТРОЙКИ ═════")
	var site: Building = _CSite.new()
	site.faction = Constants.FACTION_PLAYER
	site.target_id = "house"
	site.target_name = "Дом"
	site.build_time = 600.0
	site.build_size = _UCfg.building_size("house")
	main.world_add(site)
	var spp: Vector3 = base + Vector3(20.0, 0.0, 0.0)
	site.global_position = Vector3(spp.x, GameManager.get_terrain_height(spp.x, spp.z), spp.z)
	var fake := Node.new()
	add_child(fake)
	site.add_builder(fake)
	await pframes(2)
	var p0: float = site.progress
	await pframes(60)
	var p_base: float = site.progress - p0
	if not GameManager.unit_bonuses.has(Constants.FACTION_PLAYER):
		GameManager.unit_bonuses[Constants.FACTION_PLAYER] = {}
	GameManager.unit_bonuses[Constants.FACTION_PLAYER]["worker"] = {"bonus_build": 1.0}
	var p1: float = site.progress
	await pframes(60)
	var p_fast: float = site.progress - p1
	verdict("D1 bonus_build 1.0 удваивает темп стройки", p_base > 0.0 and absf(p_fast / p_base - 2.0) < 0.1,
		"база %.2f, с улучшением %.2f" % [p_base, p_fast])
	_finish()
