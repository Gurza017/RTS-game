extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_knight_forge — ДРЕВО РЫЦАРЯ, ПОДСКАЗКИ КУЗНИЦЫ, ПАНЕЛЬ СТАТОВ
## (ТЗ-B 19.09.2026, три блока)
## ═══════════════════════════════════════════════════════════════════════════
##   A ДРЕВО   — «Яростная Атака» (переименована), у рыцаря нет узлов скорости,
##               колонка D у ВСЕХ веток платная и последовательная (2d требует
##               1d), бонус ряда даром не выдаётся (монах 1a+1b+1c → 1d не
##               изучен, но доступен и стоит золота), у монаха есть
##               горизонтальные связки.
##   B СЕРИЯ   — 5 ударов базово, 7 с «Неистовством», ритм обычный/мощный.
##   C РАССЕЧЕНИЕ — без узла соседи целы; с 2d два соседа по 50 %; с 4d три
##               соседа по 75 %; одиночка — без ошибок.
##   D АГРО ПОСЛЕ РЫВКА — отряд рыцарей по двойному ПКМ бежит в точку перед
##               врагом и по прибытии САМ вступает в бой (цели у всех).
##   E БЕРСЕРК — ниже половины запаса удар ×1.25.
##   F HUD     — узлы кузницы без движкового пузыря (QuietTooltipButton),
##               карточка узла: описание, «Статус: Доступно/Недоступно»,
##               цена, без технических строк; предпросмотр на панели отряда
##               по наведению; панель статов компактная (уже панели отряда,
##               полоски BAR_W); наведение работает по всей иконке.
## Запуск: godot --headless --path . res://qa_knight_forge/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

var main = null
var hud = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с")
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
	print("\n═════ ИТОГ qa_knight_forge: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var px: float = at.x + float(i % cols) * 0.6 - float(cols - 1) * 0.3
		var pz: float = at.z + float(i / cols) * 0.6
		var u: Unit = _spawn(kind, fac, Vector3(px, 0.0, pz))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

## Замороженная бессмертная мишень
func _dummy(at: Vector3) -> Unit:
	var u: Unit = _spawn("goblin_spearman", G, at)
	u.set_tick(false)
	u.max_health = 1.0e6
	u.current_health = 1.0e6
	u._soa_push_stats()
	return u

func _kill(u) -> void:
	if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
		(u as Unit).max_health = 100.0
		(u as Unit).current_health = 100.0
		(u as Unit)._soa_push_stats()
		(u as Unit).take_damage(1.0e12)

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _research(ids: Array) -> void:
	for id in ids:
		GameManager.finish_research(F, String(id))

func _reset_research() -> void:
	GameManager.researched.erase(F)
	GameManager.researching.erase(F)
	GameManager.unit_bonuses.erase(F)
	GameManager.bonus_version += 1

func _labels(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).text)
	for c in node.get_children():
		_labels(c, out)

func _has_text(texts: Array, needle: String) -> bool:
	for t in texts:
		if String(t).findn(needle) >= 0:
			return true
	return false

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	hud = main.hud
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for k in ["goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)
	GameManager.world_bounds_enabled = false
	GameManager.pop_limit_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	var base := Vector3(30.0, 0.0, -30.0)
	main._clear_area_of_resources(base, 70.0)
	_reset_research()

	await _a_tree()
	await _b_rage(base)
	await _c_cleave(base + Vector3(0.0, 0.0, 30.0))
	await _d_rush(base + Vector3(40.0, 0.0, 0.0))
	await _e_berserk(base + Vector3(0.0, 0.0, -30.0))
	await _f_hud(base + Vector3(40.0, 0.0, 30.0))
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_tree() -> void:
	print("\n═════ A. ДРЕВО ═════")
	var n1d: Dictionary = _Forge.get_node("warrior_1d")
	verdict("A1 узел warrior_1d называется «Яростная Атака»",
		String(n1d.get("name", "")) == "Яростная Атака", String(n1d.get("name", "")))
	var old_name := false
	for n in _Forge.all_nodes():
		if String((n as Dictionary).get("name", "")).findn("Набег") >= 0:
			old_name = true
	verdict("A2 «Яростного Набега» в древе больше нет", not old_name)
	var speed_nodes: Array = []
	for n in _Forge.tree("warrior"):
		if float((n as Dictionary).get("bonus_speed", 0.0)) != 0.0:
			speed_nodes.append(String((n as Dictionary).get("cell", "")))
	verdict("A3 у рыцаря нет узлов скорости", speed_nodes.is_empty(), str(speed_nodes))
	var push_sum := 0.0
	var armor_sum := 0.0
	for n in _Forge.tree("warrior"):
		push_sum += float((n as Dictionary).get("bonus_push", 0.0))
		armor_sum += float((n as Dictionary).get("bonus_armor", 0.0))
	verdict("A4 сумма напора и брони в древе рыцаря выше прежних (2.4 / 5.0)",
		push_sum > 2.4 and armor_sum > 5.0, "напор %.1f, броня %.1f" % [push_sum, armor_sum])
	verdict("A5 узел прокачки серии даёт +2 удара (bonus_rage_hits)",
		float(_Forge.get_node("warrior_3d").get("bonus_rage_hits", 0.0)) == 2.0)
	verdict("A6 узел рассечения и его прокачка есть (bonus_cleave 2 + 1)",
		float(_Forge.get_node("warrior_2d").get("bonus_cleave", 0.0)) == 2.0
		and float(_Forge.get_node("warrior_4d").get("bonus_cleave", 0.0)) == 1.0)
	# Колонка D — платная и последовательная у всех веток
	var free_nodes: Array = []
	var chain_ok := true
	for n in _Forge.all_nodes():
		var d: Dictionary = n
		var cost: Dictionary = _UCfg.upgrade_cost(d)
		var total := 0.0
		for k in cost:
			total += float(cost[k])
		if total <= 0.0:
			free_nodes.append(String(d.get("id", "")))
		if String(d.get("col", "")) == "d" and int(d.get("row", 0)) >= 2:
			var prev: String = _Forge.node_id(String(d.get("unit", "")), "%dd" % (int(d.get("row", 0)) - 1))
			if not (prev in (d.get("prerequisites", []) as Array)):
				chain_ok = false
	verdict("A7 бесплатных узлов в древе нет", free_nodes.is_empty(), str(free_nodes))
	verdict("A8 узлы колонки D идут цепочкой (2d требует 1d и так далее) у всех веток", chain_ok)
	# Бонус ряда даром не выдаётся: монах 1a+1b+1c → 1d НЕ изучен
	_reset_research()
	_research(["monk_1a", "monk_1b", "monk_1c"])
	GameManager._grant_row_bonuses(F, "monk_1c")
	verdict("A9 ряд монаха изучен целиком, а 1d даром НЕ выдан",
		not GameManager.is_researched(F, "monk_1d"))
	verdict("A10 при этом 1d ДОСТУПЕН к покупке, а 2d — нет (нужен 1d)",
		GameManager.can_research(F, "monk_1d") and not GameManager.can_research(F, "monk_2d"))
	var links := 0
	for n in _Forge.tree("monk"):
		links += (n.get("link", []) as Array).size()
	verdict("A11 у ветки монаха есть горизонтальные связки", links >= 6, "%d" % links)
	_reset_research()

# ═════════════════════════════════════════════════════════════════════════════
func _b_rage(base: Vector3) -> void:
	print("\n═════ B. СЕРИЯ ЯРОСТНОЙ АТАКИ ═════")
	_reset_research()
	var k: Warrior = _spawn("warrior", F, base) as Warrior
	var sid: int = GameManager.new_squad(F, "warrior")
	GameManager.add_to_squad(sid, k)
	var t: Unit = _dummy(base + Vector3(1.2, 0.0, 0.0))
	await pframes(3)
	verdict("B1 без прокачки серия из %d ударов" % Warrior.RAGE_HITS, k.rage_hits_total() == Warrior.RAGE_HITS,
		"%d" % k.rage_hits_total())
	_research(["warrior_1d", "warrior_2d", "warrior_3d"])
	verdict("B2 с «Неистовством» серия из %d ударов" % (Warrior.RAGE_HITS + 2),
		k.rage_hits_total() == Warrior.RAGE_HITS + 2, "%d" % k.rage_hits_total())
	k.start_rage_dash()
	k.command_attack(t, true, false, true)
	for _f in range(60 * 12):
		await get_tree().physics_frame
		if k.rage_hits_done >= Warrior.RAGE_HITS + 2 or not k.rage_active():
			break
	verdict("B3 серия отбита целиком: %d ударов" % (Warrior.RAGE_HITS + 2),
		k.rage_hits_done == Warrior.RAGE_HITS + 2, "ударов %d, мощных %d" % [k.rage_hits_done, k.rage_strong_done])
	verdict("B4 ритм обычный/мощный: мощных 3 из 7", k.rage_strong_done == 3, "%d" % k.rage_strong_done)
	_kill(k); _kill(t)
	_reset_research()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _c_cleave(base: Vector3) -> void:
	print("\n═════ C. РАССЕЧЕНИЕ ═════")
	var cases: Array = [
		["C1 без узла", [], 0, 0.0],
		["C2 «Рассечение»", ["warrior_1d", "warrior_2d"], 2, 0.5],
		["C3 «Стальной вихрь»", ["warrior_1d", "warrior_2d", "warrior_3d", "warrior_4d"], 3, 0.75],
	]
	var off := 0.0
	for c in cases:
		_reset_research()
		_research(c[1])
		var at: Vector3 = base + Vector3(0.0, 0.0, off)
		off += 8.0
		var k: Warrior = _spawn("warrior", F, at + Vector3(-1.2, 0.0, 0.0)) as Warrior
		var sid: int = GameManager.new_squad(F, "warrior")
		GameManager.add_to_squad(sid, k)
		var mid: Unit = _dummy(at)
		# Четыре соседа полукольцом впереди рыцаря на 0.9 м от цели
		var side: Array = []
		for j in range(4):
			var ang: float = -1.0 + float(j) * 0.66
			side.append(_dummy(at + Vector3(0.9 * cos(ang), 0.0, 0.9 * sin(ang))))
		await pframes(3)
		k.command_attack(mid, true, false, true)
		var hits0: int = k.hits_released
		for _f in range(60 * 10):
			await get_tree().physics_frame
			if k.hits_released - hits0 >= 3:
				break
		var strikes: int = k.hits_released - hits0
		var d_mid: float = 1.0e6 - mid.current_health
		var hurt := 0
		var d_side_max := 0.0
		for s in side:
			var dv: float = 1.0e6 - (s as Unit).current_health
			if dv > 0.0:
				hurt += 1
				d_side_max = maxf(d_side_max, dv)
		var want_n: int = int(c[2])
		var frac: float = float(c[3])
		print("  %s: ударов %d, цель −%.0f, задето соседей %d (макс −%.0f), cleave_hits %d" % [
			String(c[0]), strikes, d_mid, hurt, d_side_max, k.cleave_hits])
		verdict("%s: ударов не меньше трёх, цель под уроном" % String(c[0]), strikes >= 3 and d_mid > 0.0,
			"ударов %d" % strikes)
		if want_n == 0:
			verdict("%s: соседи целы" % String(c[0]), hurt == 0 and k.cleave_hits == 0, "задето %d" % hurt)
		else:
			verdict("%s: задето ровно %d соседей за удар" % [String(c[0]), want_n],
				hurt == want_n and k.cleave_last == want_n, "задето %d, последним ударом %d" % [hurt, k.cleave_last])
			# Урон соседу за один удар = доля от удара по цели (та же броня)
			var per_hit_mid: float = d_mid / float(strikes)
			var per_hit_side: float = d_side_max / float(strikes)
			verdict("%s: сосед получает %.0f %% урона" % [String(c[0]), frac * 100.0],
				absf(per_hit_side - per_hit_mid * frac) <= maxf(1.0, per_hit_mid * 0.08),
				"по цели %.1f, соседу %.1f за удар" % [per_hit_mid, per_hit_side])
		_kill(k); _kill(mid)
		for s in side:
			_kill(s)
		await pframes(3)
	# Одиночка с узлом — без второго урона и без ошибок
	_reset_research()
	_research(["warrior_1d", "warrior_2d"])
	var at2: Vector3 = base + Vector3(20.0, 0.0, 0.0)
	var k2: Warrior = _spawn("warrior", F, at2 + Vector3(-1.2, 0.0, 0.0)) as Warrior
	GameManager.add_to_squad(GameManager.new_squad(F, "warrior"), k2)
	var lone: Unit = _dummy(at2)
	await pframes(3)
	k2.command_attack(lone, true, false, true)
	for _f in range(60 * 8):
		await get_tree().physics_frame
		if k2.hits_released >= 3:
			break
	verdict("C4 одиночная цель: бьёт, соседей нет, задетых ноль",
		k2.hits_released >= 3 and k2.cleave_hits == 0, "ударов %d, задето %d" % [k2.hits_released, k2.cleave_hits])
	_kill(k2); _kill(lone)
	_reset_research()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _d_rush(base: Vector3) -> void:
	print("\n═════ D. АГРО ПОСЛЕ РЫВКА ═════")
	_reset_research()
	_research(["warrior_1d"])
	var sq: Array = _squad("warrior", F, base, 12, 6)
	var sid: int = int(sq[0])
	var men: Array = sq[1]
	# Враг в 8 м за точкой приказа: рывок кончается перед строем, в 5 м агро
	# мечника (WARRIOR_AGGRO_RADIUS) никого — прежде отряд замирал
	var foes: Array = []
	var far: Vector3 = base + Vector3(0.0, 0.0, 22.0)
	for j in range(6):
		foes.append(_dummy(far + Vector3(float(j) * 1.0 - 2.5, 0.0, 8.0)))
	await pframes(3)
	verdict("D0 у отряда есть «Яростная Атака»", GameManager.squad_has_ability(sid, "warrior_1d"))
	# Двойной ПКМ по земле: приём + бег в точку (тот же путь, что
	# SelectionManager._trigger_double_rmb_abilities + command_move(run))
	for u in men:
		(u as Warrior).start_rage_dash()
	var course := Vector3(0.0, 0.0, 1.0)
	var i := 0
	for u in men:
		var dst: Vector3 = far + Vector3(float(i % 6) * 0.6 - 1.5, 0.0, float(i / 6) * 0.6)
		(u as Unit).command_move(dst, false, course, false, true, true)
		i += 1
	var arrived := 0
	for _f in range(60 * 14):
		await get_tree().physics_frame
		arrived = 0
		for u in _alive(men):
			if not (u as Unit).sprinting:
				arrived += 1
		if arrived >= men.size():
			break
	verdict("D1 весь отряд добежал (бег выключился)", arrived >= men.size(), "%d из %d" % [arrived, men.size()])
	# Сразу после прибытия — в бой: цели у бойцов, счётчик агро после рывка
	await pframes(45)
	var with_target := 0
	var rush_aggro := 0
	for u in _alive(men):
		if (u as Unit).attack_target != null and is_instance_valid((u as Unit).attack_target):
			with_target += 1
		rush_aggro += (u as Warrior).rush_aggro_count
	verdict("D2 по окончании рывка отряд сам входит в бой: цель у всех (0.75 с)",
		with_target == men.size(), "с целью %d из %d, агро после рывка %d" % [with_target, men.size(), rush_aggro])
	verdict("D3 цели выданы именно агро после рывка", rush_aggro >= men.size() / 2, "%d" % rush_aggro)
	# Через несколько секунд рыцари РУБЯТ: у мишеней снят запас
	await pframes(60 * 4)
	var hurt := 0
	for fz in foes:
		if (fz as Unit).current_health < 1.0e6:
			hurt += 1
	verdict("D4 бой идёт: мишени под уроном", hurt >= 3, "под уроном %d из %d" % [hurt, foes.size()])
	for u in men:
		_kill(u)
	for fz in foes:
		_kill(fz)
	_reset_research()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _e_berserk(base: Vector3) -> void:
	print("\n═════ E. КРОВЬ БЕРСЕРКА ═════")
	_reset_research()
	var k: Warrior = _spawn("warrior", F, base) as Warrior
	GameManager.add_to_squad(GameManager.new_squad(F, "warrior"), k)
	await pframes(2)
	var d0: float = k._strike_damage()
	k._combo_step = 0
	_research(["warrior_1d", "warrior_2d", "warrior_3d", "warrior_4d", "warrior_5d"])
	var d1: float = k._strike_damage()
	k._combo_step = 0
	verdict("E1 с полным запасом удар прежний", absf(d1 - d0) < 0.01, "%.1f → %.1f" % [d0, d1])
	k.current_health = k.max_health * 0.4
	k._soa_push_stats()
	var d2: float = k._strike_damage()
	verdict("E2 ниже половины запаса удар ×%.2f" % (1.0 + float(_Forge.get_node("warrior_5d").get("bonus_berserk", 0.0))),
		absf(d2 - d0 * 1.25) < 0.05, "%.1f → %.1f" % [d0, d2])
	_kill(k)
	_reset_research()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _f_hud(base: Vector3) -> void:
	print("\n═════ F. HUD: КУЗНИЦА И ПАНЕЛЬ СТАТОВ ═════")
	_reset_research()
	ResourceManager.add_resource(F, 0, 100000.0)
	var smithy: Smithy = Smithy.new()
	smithy.faction = F
	main.world_add(smithy)
	smithy.global_position = base
	await frames(3)
	var sq: Array = _squad("warrior", F, base + Vector3(20.0, 0.0, 0.0), 12, 6)
	var men: Array = sq[1]
	await frames(2)
	hud.show_selection([smithy])
	await frames(3)
	verdict("F0 панель кузницы открыта", hud.forge_visible())
	hud.forge_set_tab("warrior")
	await frames(2)
	# Узлы — без движкового пузыря
	var quiet := true
	var btn = hud._forge_nodes.get("warrior_2d")
	if btn == null or not is_instance_valid(btn):
		quiet = false
	else:
		quiet = (btn is QuietTooltipButton) and String(btn.call("_get_tooltip", Vector2.ZERO)).is_empty()
	verdict("F1 узел кузницы не рисует движковую подсказку (QuietTooltipButton, пустой _get_tooltip)", quiet,
		"tooltip_text=«%s»" % (String(btn.tooltip_text) if btn != null else "-"))
	# Карточка узла: описание, статус, цена, без технических строк
	hud._show_forge_tip("warrior_2d")
	await frames(2)
	var texts: Array = []
	if hud._forge_tip != null and is_instance_valid(hud._forge_tip):
		_labels(hud._forge_tip, texts)
	verdict("F2 карточка: название и описание человеческим языком",
		_has_text(texts, "Рассечение") and _has_text(texts, "задевает"))
	verdict("F3 карточка: «Статус: Недоступно» у закрытого узла (красным)",
		_has_text(texts, "Статус: Недоступно"))
	verdict("F4 карточка без технических строк (bonus_, «Исследование:», «Действует:»)",
		not _has_text(texts, "bonus_") and not _has_text(texts, "Исследование:") and not _has_text(texts, "Действует"),
		str(texts))
	hud._hide_forge_tip()
	_research(["warrior_1a", "warrior_1b", "warrior_1c"])
	hud._rebuild_forge()
	await frames(2)
	hud._show_forge_tip("warrior_1d")
	await frames(2)
	texts.clear()
	if hud._forge_tip != null and is_instance_valid(hud._forge_tip):
		_labels(hud._forge_tip, texts)
	verdict("F5 карточка: «Статус: Доступно» у открытого узла", _has_text(texts, "Статус: Доступно"))
	hud._hide_forge_tip()
	# Предпросмотр: наведение на узел с прибавкой — панель статов отряда
	# рыцарей поднимается (отряд не выделен — берётся свой отряд этого рода)
	var prev0: int = hud.forge_previews
	hud._show_forge_tip("warrior_1a")     # +1 к броне
	await frames(3)
	var shown: bool = hud.stat_panel_shown()
	var bar = hud._stat_bars.get("armor")
	var prev_v: float = float(bar.preview) if bar != null and is_instance_valid(bar) else 0.0
	verdict("F6 наведение на узел кузницы показывает панель статов рыцарей", shown and hud._stat_sid == int(sq[0]),
		"shown %s sid %d" % [str(shown), hud._stat_sid])
	verdict("F7 в таблице дописана прибавка узла (броня +1 предпросмотром)",
		hud.forge_previews > prev0 and absf(prev_v - 1.0) < 0.01, "preview %.2f" % prev_v)
	# Компактность: уже панели отряда, полоски BAR_W
	var sp: Rect2 = hud._stat_panel.get_global_rect() if hud._stat_panel != null else Rect2()
	verdict("F8 панель статов компактная: ширина = STAT_COMPACT_W (%d), полоска %.0f px" % [hud.STAT_COMPACT_W, hud.BAR_W],
		absf(sp.size.x - float(hud.STAT_COMPACT_W)) < 1.0 and bar != null and absf(bar.size.x - hud.BAR_W) < 1.0,
		"ширина %.0f, полоска %.0f" % [sp.size.x, bar.size.x if bar != null else -1.0])
	hud._hide_forge_tip()
	await frames(2)
	verdict("F9 курсор ушёл с узла — панель предпросмотра гаснет", not hud.stat_panel_shown())
	# Панель отряда: таблица уже нижней панели и по наведению на портрет
	# Выделение — через SelectionManager: панель читает sm.selected_squad_ids
	main.selection_manager.select_units(men)
	await frames(4)
	var bp: Rect2 = hud._bottom_panel.get_global_rect()
	var sp2: Rect2 = hud._stat_panel.get_global_rect() if hud._stat_panel != null else Rect2()
	verdict("F10 таблица статов уже нижней панели отряда и стоит над её левым краем",
		sp2.size.x < bp.size.x and absf(sp2.position.x - bp.position.x) < 1.0 and sp2.position.y + sp2.size.y <= bp.position.y + 1.0,
		"таблица %.0f×%.0f @%.0f,%.0f; панель %.0f @%.0f,%.0f" % [sp2.size.x, sp2.size.y, sp2.position.x, sp2.position.y, bp.size.x, bp.position.x, bp.position.y])
	verdict("F11 до наведения таблица прозрачна", not hud.stat_panel_shown())
	# Подложка портрета не глотает мышь — наведение по ВСЕЙ иконке
	verdict("F12 подложка и иконка портрета пропускают мышь (наведение по всей области)",
		hud.portrait.mouse_filter != Control.MOUSE_FILTER_STOP
		and hud._portrait_icon.mouse_filter != Control.MOUSE_FILTER_STOP)
	hud._set_stat_hover_portrait(true)
	await frames(1)
	verdict("F13 наведение на портрет показывает таблицу", hud.stat_panel_shown())
	hud._set_stat_hover_portrait(false)
	main.selection_manager.select_units([])
	hud.show_selection([])
	for u in men:
		_kill(u)
	smithy.queue_free()
	_reset_research()
	await frames(3)
