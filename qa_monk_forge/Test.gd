extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_monk_forge — ВЕТКА МОНАХА: 3×5 + БОНУСНЫЙ СТОЛБЕЦ
## ═══════════════════════════════════════════════════════════════════════════
##   A  ФОРМА    — 15 узлов a/b/c и 5 бонусов d; цены и время ПО РЯДУ,
##                 бонусы даром; иконки на месте и файлы существуют
##   B  КОЛОНКА D — ПЛАТНАЯ И ПОСЛЕДОВАТЕЛЬНАЯ (ТЗ-B 19.09.2026): ряд A+B+C
##                 только ОТКРЫВАЕТ узел D, даром он не выдаётся, 2d требует 1d
##   C  ЭФФЕКТЫ  — радиус ауры, такт, объём, число целей, самохил читаются
##                 монахом ПРЯМО из реестра изученного
##   D  СПАСЕНИЯ — щит, «Второе Дыхание», самовоскрешение
##   E  ОТХОД    — под уроном монах отбегает на 5 м, не чаще раза в секунду,
##                 и продолжает лечить на ходу
##
## Запуск: <godot> --headless --path . res://qa_monk_forge/Test.tscn

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

const F := Constants.FACTION_PLAYER
const MONK := "res://scenes/units/Monk.tscn"
const FOE := "res://scenes/units/GoblinSpearman.tscn"
const ALLY := "res://scenes/units/Spearman.tscn"

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(420.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
		_finish())

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
	print("\n═════ ИТОГ qa_monk_forge: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Изучить узел мгновенно, тем же путём, каким это делает кузница
func _learn(cell: String) -> void:
	GameManager.finish_research(F, "monk_" + cell)

## Ряд r изучен целиком, предыдущих D нет: rd остаётся закрытым (цепочка D);
## с предыдущими D — открыт
func _row_then_check(r: String) -> bool:
	GameManager.researched.erase(F)
	_learn(r + "a"); _learn(r + "b"); _learn(r + "c")
	var closed: bool = not GameManager.can_research(F, "monk_" + r + "d")
	for k in range(1, int(r)):
		_learn("%dd" % k)
	return closed and GameManager.can_research(F, "monk_" + r + "d")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	print("\n═════ qa_monk_forge ═════")
	_a_shape()
	_b_bonus()
	await _c_effects()
	await _d_saves()
	await _e_retreat()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_shape() -> void:
	print("\n═════ A. ФОРМА ВЕТКИ ═════")
	var rows := {1: [100.0, 0.0, 0.0, 15.0], 2: [250.0, 0.0, 0.0, 30.0],
		3: [500.0, 50.0, 0.0, 45.0], 4: [1000.0, 0.0, 150.0, 60.0],
		5: [2000.0, 0.0, 300.0, 90.0]}
	var ok_cost := true
	var ok_free := true
	var ok_icon := true
	var missing := ""
	for r in range(1, 6):
		for col in ["a", "b", "c", "d"]:
			var node: Dictionary = _Forge.get_node("monk_%d%s" % [r, col])
			if node.is_empty():
				missing += " %d%s" % [r, col]
				continue
			var ic: String = String(node.get("icon", ""))
			if ic == "" or not ResourceLoader.exists(_UCfg.SMITH_ICONS_DIR + ic):
				ok_icon = false
				missing += " иконка:%d%s" % [r, col]
			if col == "d":
				# Колонка D ПЛАТНАЯ (ТЗ-B 19.09.2026): цена и время больше нуля
				if float(node.get("cost_gold", 0.0)) <= 0.0 \
						or float(node.get("research_time", 0.0)) <= 0.0:
					ok_free = false
			else:
				var want: Array = rows[r]
				if absf(float(node.get("cost_gold", 0.0)) - float(want[0])) > 0.01 \
						or absf(float(node.get("cost_wood", 0.0)) - float(want[1])) > 0.01 \
						or absf(float(node.get("cost_stone", 0.0)) - float(want[2])) > 0.01 \
						or absf(float(node.get("research_time", 0.0)) - float(want[3])) > 0.01:
					ok_cost = false
	verdict("A1 все 20 ячеек ветки на месте", missing == "", "нет:%s" % missing)
	verdict("A2 цена и время — по ряду (100/15, 250/30, 500+50/45, 1000+150/60, 2000+300/90)",
		ok_cost)
	verdict("A3 столбец D платный: у каждого узла цена и время", ok_free)
	verdict("A4 у каждой ячейки есть существующая иконка", ok_icon)
	# Столбцы идут сверху вниз: 2a требует 1a и так далее
	var chain := true
	for r in range(2, 6):
		for col in ["a", "b", "c"]:
			var pre: Array = _Forge.get_node("monk_%d%s" % [r, col]).get("prereq", [])
			# Ячейка в конфиге записана коротко ("1a"), а get_node может отдать
			# её развёрнутой ("monk_1a") — принимаем оба вида: проверяется
			# СВЯЗЬ рядов, а не способ записи
			var want_s: String = "%d%s" % [r - 1, col]
			var got_s: String = String(pre[0]) if pre.size() == 1 else ""
			if got_s != want_s and got_s != "monk_" + want_s:
				chain = false
	verdict("A5 столбцы идут сверху вниз (2a после 1a и так далее)", chain)

# ═════════════════════════════════════════════════════════════════════════════
func _b_bonus() -> void:
	print("\n═════ B. КОЛОНКА D ПОКУПАЕТСЯ, А НЕ ВЫДАЁТСЯ ═════")
	GameManager.researched.erase(F)
	_learn("1a")
	verdict("B1 одного узла мало — 1d закрыт", not GameManager.can_research(F, "monk_1d"))
	_learn("1b")
	verdict("B2 двух узлов мало — 1d закрыт", not GameManager.can_research(F, "monk_1d"))
	_learn("1c")
	verdict("B3 третий узел ряда ОТКРЫВАЕТ 1d, но даром не выдаёт",
		GameManager.can_research(F, "monk_1d") and not GameManager.is_researched(F, "monk_1d"))
	GameManager._grant_row_bonuses(F, "monk_1c")
	verdict("B4 прежний путь бонуса ряда ничего не выдаёт (платный узел)",
		not GameManager.is_researched(F, "monk_1d"))
	# Покупка списывает золото по цене узла
	ResourceManager.add_resource(F, Constants.RESOURCE_GOLD, 10000.0)
	var g0: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
	var t: float = GameManager.start_research(F, "monk_1d")
	var cost1d: float = float(_Forge.get_node("monk_1d").get("cost_gold", 0.0))
	verdict("B5 1d покупается за золото и время (%.0f з, %.0f с)" % [cost1d, float(_Forge.get_node("monk_1d").get("research_time", 0.0))],
		t > 0.0 and absf(g0 - ResourceManager.get_amount(F, Constants.RESOURCE_GOLD) - cost1d) < 0.01,
		"время %.0f, списано %.0f" % [t, g0 - ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)])
	GameManager.finish_research(F, "monk_1d")
	verdict("B6 2d без 1d недоступен даже с изученным рядом 2, а с 1d — доступен",
		_row_then_check("2"))

# ═════════════════════════════════════════════════════════════════════════════
func _c_effects() -> void:
	print("\n═════ C. ЭФФЕКТЫ ЧИТАЮТСЯ ИЗ РЕЕСТРА ═════")
	GameManager.researched.erase(F)
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(120.0, 0.0, 0.0)
	var monk: Unit = _spawn(MONK, F, spot)
	await pframes(6)
	var r0: float = monk.heal_radius()
	var t0: float = monk.heal_tick_sec()
	print("  без исследований: радиус %.1f м, такт %.2f с, целей %d, самохил %.0f %%" % [
		r0, t0, monk.max_heal_targets(), monk.self_heal_frac() * 100.0])
	verdict("C1 без узлов лечит одного и себя не лечит",
		monk.max_heal_targets() == 1 and monk.self_heal_frac() == 0.0)
	_learn("1a")
	verdict("C2 «Расширение Ауры I» даёт +3 м",
		absf(monk.heal_radius() - (r0 + 3.0)) < 0.01,
		"%.1f → %.1f" % [r0, monk.heal_radius()])
	_learn("1b")
	verdict("C3 «Быстрое Снадобье I» ускоряет такт",
		monk.heal_tick_sec() < t0 - 0.01,
		"%.2f → %.2f с" % [t0, monk.heal_tick_sec()])
	_learn("1c")
	verdict("C4 «Самохил I» — 30 % отданного",
		absf(monk.self_heal_frac() - 0.30) < 0.01)
	_learn("1d")
	verdict("C5 купленный 1d включил лечение троих",
		GameManager.is_researched(F, "monk_1d") and monk.max_heal_targets() == 3,
		"целей %d" % monk.max_heal_targets())
	# Ряд 2: воскрешение
	verdict("C6 без «Первого Чуда» воскрешения нет", not monk.can_resurrect())
	_learn("2a"); _learn("2b"); _learn("2c"); _learn("2d")
	verdict("C7 купленный 2d включил воскрешение",
		monk.can_resurrect() and monk.max_resurrect_count() == 1
			and absf(monk.res_health_frac() - 0.3) < 0.01,
		"поднимает %d с %.0f %%" % [monk.max_resurrect_count(),
			monk.res_health_frac() * 100.0])
	# Ряд 4: конвейерные числа
	_learn("3a"); _learn("3b"); _learn("3c"); _learn("3d")
	verdict("C8 купленный 3d — лечит весь отряд и даёт самовоскрешение",
		monk.max_heal_targets() > 3 and monk.has_self_revive(),
		"целей %d" % monk.max_heal_targets())
	_learn("4a"); _learn("4b"); _learn("4c"); _learn("4d")
	# «TickSpeed = 0.3s» читается как ПОТОЛОК, а не как жёсткое равенство:
	# к четвёртому ряду такт от прежних узлов уже быстрее трёх десятых, и
	# «поставить ровно 0.3» означало бы УХУДШИТЬ его этим исследованием
	verdict("C9 «Непрерывный Поток» — такт не медленнее 0.3 с",
		monk.heal_tick_sec() <= 0.301, "%.2f с" % monk.heal_tick_sec())
	verdict("C10 купленный 4d — двое за канал с половины запаса",
		monk.max_resurrect_count() == 2 and absf(monk.res_health_frac() - 0.5) < 0.01)
	_learn("5a"); _learn("5b"); _learn("5c"); _learn("5d")
	verdict("C11 «Глобальный Покров» — аура на всю карту",
		monk.heal_radius() > 1000.0, "%.0f м" % monk.heal_radius())
	# Откат конвейера — из конфига (17.09.2026: 15/12/3 → 5/4/2, правило 10)
	verdict("C12 купленный 5d — конвейер по 3-4 с коротким откатом (MONK_RES_COOLDOWN_5D)",
		monk.max_resurrect_count() >= 3 and absf(monk.res_cooldown() - _UCfg.MONK_RES_COOLDOWN_5D) < 0.01,
		"%d за канал, откат %.0f с" % [monk.max_resurrect_count(), monk.res_cooldown()])
	verdict("C13 «Абсолютное Целительство» включено",
		monk.full_heal_tick())
	monk.take_damage(1e12)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
func _d_saves() -> void:
	print("\n═════ D. ЩИТ, ВТОРОЕ ДЫХАНИЕ, САМОВОСКРЕШЕНИЕ ═════")
	# Только щит: ряд 4 целиком (бонус ряда 3 не нужен — иначе спасёт он)
	GameManager.researched.erase(F)
	_learn("4c")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(120.0, 0.0, 40.0)
	var monk: Unit = _spawn(MONK, F, spot)
	await pframes(60 * 12)          # щит копится вне боя
	print("  щит набран: %.0f из %.0f" % [monk.get("shield_hp"), 150.0])
	verdict("D1 «Святой Щит» набирается вне боя",
		float(monk.get("shield_hp")) > 100.0, "%.0f" % monk.get("shield_hp"))
	var hp0: float = monk.current_health
	monk.take_damage(40.0)
	verdict("D2 щит съедает урон раньше запаса жизни",
		monk.current_health >= hp0 - 0.01,
		"запас %.0f, щит %.0f" % [monk.current_health, monk.get("shield_hp")])
	monk.take_damage(1e12)
	await pframes(6)
	# Второе Дыхание
	GameManager.researched.erase(F)
	_learn("5c")
	var m2: Unit = _spawn(MONK, F, spot + Vector3(6.0, 0.0, 0.0))
	await pframes(6)
	m2.take_damage(1e9)
	verdict("D3 «Второе Дыхание» оставляет 1 HP, а не убивает",
		not m2.is_dead() and m2.current_health <= 1.01,
		"запас %.2f" % m2.current_health)
	var saves: int = int(m2.get("death_saves"))
	m2.take_damage(1e9)
	verdict("D4 и даёт неуязвимость — второй удар подряд не проходит",
		not m2.is_dead() and int(m2.get("death_saves")) == saves,
		"спасений %d" % int(m2.get("death_saves")))
	m2.queue_free()
	await pframes(6)
	# Самовоскрешение (узел 3d)
	GameManager.researched.erase(F)
	_learn("3d")
	var m3: Unit = _spawn(MONK, F, spot + Vector3(12.0, 0.0, 0.0))
	await pframes(6)
	verdict("D5 самовоскрешение доступно", m3.has_self_revive())
	m3.take_damage(1e9)
	verdict("D6 первая смерть — монах встаёт с половины запаса",
		not m3.is_dead() and m3.current_health > m3.max_health * 0.4,
		"запас %.0f из %.0f" % [m3.current_health, m3.max_health])
	verdict("D7 самовоскрешение потрачено", not m3.has_self_revive())
	m3.take_damage(1e9)
	verdict("D8 вторая смерть окончательна", m3.is_dead())
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
func _e_retreat() -> void:
	print("\n═════ E. ОТХОД ПОД УРОНОМ ═════")
	GameManager.researched.erase(F)
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(120.0, 0.0, 80.0)
	var monk: Unit = _spawn(MONK, F, spot)
	monk.max_health = 1e9
	monk.current_health = 1e9
	# Раненый союзник рядом: проверяем, что лечение НЕ прерывается отходом
	var ally: Unit = _spawn(ALLY, F, spot + Vector3(1.5, 0.0, 0.0))
	ally.current_health = ally.max_health * 0.3
	ally._soa_push_stats()   # монах ищет раненого по колонке ядра (14.09.2026)
	var foe: Unit = _spawn(FOE, Constants.FACTION_GOBLIN, spot + Vector3(-4.0, 0.0, 0.0))
	foe.set_tick(false)
	await pframes(10)
	var p0: Vector3 = monk.global_position
	var hp0: float = ally.current_health
	monk.take_damage(5.0, foe)
	var r0: int = int(monk.get("retreats"))
	# Спам уроном: откат обязан погасить лишние отходы
	for _i in range(10):
		monk.take_damage(1.0, foe)
	verdict("E1 откат гасит спам: один отход, а не десять",
		int(monk.get("retreats")) - r0 + 1 <= 2,
		"отходов %d" % (int(monk.get("retreats"))))
	# ── МЕРИМ ПИК ОТХОДА, А НЕ КОНЕЧНУЮ ТОЧКУ ─────────────────────────────
	# Монах отбегает, а потом ВОЗВРАЩАЕТСЯ к пациенту — это и есть задуманное
	# поведение. Замер в конце окна показывает уже вернувшегося (0.5-0.9 м) и
	# краснеет на исправном коде; требование же про САМ ОТХОД
	var moved := 0.0
	var away := 0.0
	for _k in range(60 * 6):
		await get_tree().physics_frame
		moved = maxf(moved, Vector2(monk.global_position.x - p0.x,
			monk.global_position.z - p0.z).length())
		away = maxf(away, Vector2(monk.global_position.x - foe.global_position.x,
			monk.global_position.z - foe.global_position.z).length())
	var was_away: float = Vector2(p0.x - foe.global_position.x,
		p0.z - foe.global_position.z).length()
	print("  пик отхода %.1f м; до обидчика было %.1f, стало %.1f" % [
		moved, was_away, away])
	verdict("E2 монах отбегает от обидчика", away > was_away + 1.0,
		"%.1f → %.1f м" % [was_away, away])
	verdict("E3 отход примерно на 5 м", moved >= 4.0,
		"%.1f м" % moved)
	verdict("E4 лечение на ходу не прерывается",
		ally.current_health > hp0 + 0.01,
		"союзник %.0f → %.0f" % [hp0, ally.current_health])
	verdict("E5 монах в драку не лезет вовсе",
		monk.attack_target == null and not monk.is_combatant())
	monk.take_damage(1e12)
	ally.take_damage(1e12)
	foe.take_damage(1e12)
	await pframes(6)
