extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_GOBLIN_FORGE — ТЗ 28.10.2026: Кузница гоблинов, древо, окно, ИИ орды.
## ═══════════════════════════════════════════════════════════════════════════
## A — здание: крупнее хижины (build_size, квад спрайта, нарисованная полуширина —
##     по свойству GOBLIN_FORGE_SIZE_MULT), дым (sprite_fps), не столица, без
##     гарнизона; фундамент в ядре: круги шире хаты, при building_obstacles
##     точка под рисунком непроходима, рядом — проходима.
## B — древо читается из конфига: число узлов, slot по id из unit_stats_config,
##     цена = дерево + золото + еда (доля по конфигу), ряд II требует ряд I,
##     «Ядовитые наконечники» — заготовка.
## C — стоимость списывает дерево, еду и золото из банка FACTION_GOBLIN ровно
##     по slot (камень и банк игрока не трогаются); таймер, прогресс, сигнал
##     research_finished с фракцией орды; отмена возвращает всё.
## D — применение: броня/удар/скорость/темп/HP/мораль гоблину живому и
##     новорождённому (Main.spawn_goblin_squad), людям — нет; «Зазубренные
##     пики» ×(1+bonus_giant_melee) только по цели с разгоном (giant_class).
## E — окно: открывается по выделению своей кузницы, статус «Доступно» →
##     «Изучается» с полосой → «Изучено» по сигналу за два process_frame при
##     обезоруженном опросе; ручка forge_live_refresh выключена — статус стоит;
##     чужая кузница окно не открывает; клик по окну — над интерфейсом.
## F — ИИ орды: приток дерева/золота, закладка кузницы у лагеря за build_time,
##     заказ исследования не-заготовки; ручка perf_config.goblin_forge
##     выключена — ни закладки, ни притока.
## Запуск: godot --headless --path . res://qa_goblin_forge/Test.tscn [-- only=abcdef]
const G := Constants.FACTION_GOBLIN
const P := Constants.FACTION_PLAYER
const _GF := preload("res://scripts/economy/goblin_forge/goblin_forge_config.gd")
const _GFB := preload("res://scripts/economy/goblin_forge/GoblinForgeBonus.gd")
const _GForgeS := preload("res://scripts/economy/goblin_forge/GoblinForge.gd")
const _GoblinHutS := preload("res://scripts/goblin/GoblinHut.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")

var main: Node = null
var hud = null
var _pass := 0
var _fail := 0
var _only: String = "abcdef"
var _done := false
var _sig: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_goblin_forge: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _bank(f: int, w: float, g: float, fd: float, st: float = 0.0) -> void:
	ResourceManager.set_amount(f, Constants.RESOURCE_WOOD, w)
	ResourceManager.set_amount(f, Constants.RESOURCE_GOLD, g)
	ResourceManager.set_amount(f, Constants.RESOURCE_FOOD, fd)
	ResourceManager.set_amount(f, Constants.RESOURCE_STONE, st)

func _amt(f: int, t: int) -> float:
	return ResourceManager.get_amount(f, t)

## Нарастающий расход фракции по ресурсу (ResourceManager.tm_spent)
func _spent(f: int, t: int) -> float:
	var per: Variant = ResourceManager.tm_spent.get(f)
	if per == null:
		return 0.0
	var v: Variant = (per as Dictionary).get(t)
	return 0.0 if v == null else float(v)

func _spot(dx: float, dz: float) -> Vector3:
	var p: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(dx, 0.0, dz)
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func _forge(at: Vector3, f: int) -> Node:
	var b = _GForgeS.new()
	b.faction = f
	main.world_add(b)
	b.global_position = at
	return b

func _hut(at: Vector3, f: int) -> Node:
	var b = _GoblinHutS.new()
	b.faction = f
	main.world_add(b)
	b.global_position = at
	return b

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _sprite_w(b: Node) -> float:
	var s: Node = b.find_child("BuildingSprite", true, false)
	if s == null or not (s is MeshInstance3D):
		return -1.0
	var q := (s as MeshInstance3D).mesh as QuadMesh
	return q.size.x if q != null else -1.0

func _boot() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	hud = main.hud
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if main.get("cav_commander") != null:
		main.cav_commander.set_process(false)
	await frames(3)
	GameManager.research_finished.connect(func(f: int, id: String): _sig.append([f, id]))

func _run() -> void:
	await _boot()
	if _only.contains("a"): await _block_a()
	if _only.contains("b"): await _block_b()
	if _only.contains("c"): await _block_c()
	if _only.contains("d"): await _block_d()
	if _only.contains("e"): await _block_e()
	if _only.contains("f"): await _block_f()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ЗДАНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. ЗДАНИЕ: КРУПНЕЕ ХИЖИНЫ, ФУНДАМЕНТ ═════")
	var hut = _hut(_spot(60.0, 30.0), G)
	var fg = _forge(_spot(60.0, 48.0), G)
	await pframes(4)
	var k: float = _GobCfg.GOBLIN_FORGE_SIZE_MULT
	verdict("A1 коробка кузницы = хижина × GOBLIN_FORGE_SIZE_MULT",
		is_equal_approx(fg.build_size.x, hut.build_size.x * k) and is_equal_approx(fg.build_size.z, hut.build_size.z * k),
		"кузница %.2f, хижина %.2f, k=%.2f" % [fg.build_size.x, hut.build_size.x, k])
	var wf: float = _sprite_w(fg)
	var wh: float = _sprite_w(hut)
	verdict("A2 квад спрайта кузницы крупнее хижины в k раз",
		wf > 0.0 and wh > 0.0 and absf(wf / wh - k) < 0.05, "квад %.2f / %.2f" % [wf, wh])
	verdict("A3 нарисованная полуширина (_draw_half_w) крупнее в k раз",
		fg._draw_half_w > 0.0 and hut._draw_half_w > 0.0 and absf(fg._draw_half_w / hut._draw_half_w - k) < 0.05,
		"%.2f / %.2f" % [fg._draw_half_w, hut._draw_half_w])
	verdict("A4 рисунок к камере (_draw_z) и дым из трубы (sprite_fps > 0)",
		fg._draw_z != 0.0 and fg.sprite_fps() > 0.0, "draw_z %.2f, fps %.1f" % [fg._draw_z, fg.sprite_fps()])
	verdict("A5 не столица, без гарнизона, id goblin_forge, HP из конфига",
		not fg.is_stronghold() and fg.garrison_limit() == 0 and String(fg.building_id) == "goblin_forge"
		and is_equal_approx(fg.max_health, _UCfg.building_stat("goblin_forge", "max_hp", -1.0)))
	# Фундамент: круги шире хаты; непроходимость — при включённой ручке
	var cf: PackedFloat32Array = fg.block_circles()
	var ch: PackedFloat32Array = hut.block_circles()
	var span_f: float = (cf[cf.size() - 3] - cf[0]) + 2.0 * cf[2] if cf.size() >= 3 else 0.0
	var span_h: float = (ch[ch.size() - 3] - ch[0]) + 2.0 * ch[2] if ch.size() >= 3 else 0.0
	verdict("A6 ряд кругов фундамента кузницы шире хижины", cf.size() >= 3 and span_f > span_h * 1.3,
		"ширина %.2f / %.2f м" % [span_f, span_h])
	var was_obst: bool = _Opt.building_obstacles
	_Opt.building_obstacles = true
	fg._sync_obstacle()
	await pframes(3)
	var cx: float = cf[0] if cf.size() >= 3 else fg.global_position.x
	var cz: float = cf[1] if cf.size() >= 3 else fg.global_position.z
	var inside: bool = GameManager.is_passable(cx, cz)
	var outside: bool = GameManager.is_passable(fg.global_position.x, fg.global_position.z + 12.0)
	verdict("A7 фундамент непроходим под рисунком, проходим в 12 м перед", (not inside) and outside,
		"внутри=%s снаружи=%s" % [inside, outside])
	_Opt.building_obstacles = was_obst
	fg._sync_obstacle()
	await pframes(2)
	hut._die(); fg._die()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. ДРЕВО ИЗ КОНФИГА
# ═════════════════════════════════════════════════════════════════════════════
func _block_b() -> void:
	print("\n═════ B. ДРЕВО ЧИТАЕТСЯ ИЗ КОНФИГА ═════")
	var nodes: Array = _GF.all_nodes()
	verdict("B1 узлов = веток × рядов", nodes.size() == _GF.BRANCH_ORDER.size() * _GF.ROWS,
		"%d узлов" % nodes.size())
	var ok_slot := true
	var ok_cost := true
	var ok_req := true
	var ok_apply := true
	for n in nodes:
		var d: Dictionary = n
		var id: String = String(d["id"])
		var slot: Dictionary = _UCfg.get_upgrade_slot(id)
		if String(slot.get("id", "")) != id:
			ok_slot = false
		var w: float = float(d.get("cost_wood", 0.0))
		var g: float = float(d.get("cost_gold", 0.0))
		var f: float = float(d.get("cost_food", 0.0))
		if w <= 0.0 or g <= 0.0 or f <= 0.0 or not is_equal_approx(f, round((w + g) * _GF.FOOD_SHARE)):
			ok_cost = false
		var row: int = int(d["row"])
		var reqs: Array = d.get("prerequisites", [])
		if row == 1 and not reqs.is_empty():
			ok_req = false
		if row > 1 and (reqs.size() != 1 or String(reqs[0]) != _GF.node_id(String(d["branch"]), row - 1)):
			ok_req = false
		if (d.get("applies_to", []) as Array).is_empty():
			ok_apply = false
	verdict("B2 каждый узел находится unit_stats_config.get_upgrade_slot по id", ok_slot)
	verdict("B3 цена каждого узла: дерево, золото и еда = доля FOOD_SHARE", ok_cost)
	verdict("B4 ряд N требует ряд N-1 своей ветки, ряд I без условий", ok_req)
	verdict("B5 у каждого узла есть applies_to", ok_apply)
	verdict("B6 «Ядовитые наконечники» — заготовка (stub) под goblin_archer",
		bool(_GF.get_node("gforge_poison_1").get("stub", false))
		and (_GF.get_node("gforge_poison_1").get("applies_to", []) as Array).has("goblin_archer"))
	verdict("B7 доступность: ряд I открыт, ряд II закрыт до ряда I",
		GameManager.can_research(G, "gforge_hide_1") and not GameManager.can_research(G, "gforge_hide_2"))

# ═════════════════════════════════════════════════════════════════════════════
# C. СТОИМОСТЬ И ТАЙМЕР
# ═════════════════════════════════════════════════════════════════════════════
func _block_c() -> void:
	print("\n═════ C. ЦЕНА ИЗ БАНКА ОРДЫ, ТАЙМЕР, ОТМЕНА ═════")
	var fg = _forge(_spot(60.0, 48.0), G)
	await pframes(3)
	_bank(G, 5000.0, 4000.0, 3000.0, 777.0)
	_bank(P, 1111.0, 2222.0, 3333.0, 4444.0)
	var id := "gforge_hide_1"
	var slot: Dictionary = _UCfg.get_upgrade_slot(id)
	var ok: bool = fg.research(id)
	verdict("C1 заказ принят", ok)
	var dw: float = 5000.0 - _amt(G, Constants.RESOURCE_WOOD)
	var dg: float = 4000.0 - _amt(G, Constants.RESOURCE_GOLD)
	var df: float = 3000.0 - _amt(G, Constants.RESOURCE_FOOD)
	verdict("C2 списано дерево+золото+еда ровно по slot",
		is_equal_approx(dw, float(slot["cost_wood"])) and is_equal_approx(dg, float(slot["cost_gold"]))
		and is_equal_approx(df, float(slot["cost_food"])),
		"−%d л, −%d з, −%d е (конфиг %d/%d/%d)" % [dw, dg, df, slot["cost_wood"], slot["cost_gold"], slot["cost_food"]])
	verdict("C3 камень орды и банк игрока не тронуты",
		is_equal_approx(_amt(G, Constants.RESOURCE_STONE), 777.0) and is_equal_approx(_amt(P, Constants.RESOURCE_WOOD), 1111.0)
		and is_equal_approx(_amt(P, Constants.RESOURCE_FOOD), 3333.0))
	verdict("C4 слот «в работе», позиция 0, время из конфига",
		GameManager.is_researching(G, id) and fg.queue_position(id) == 0
		and is_equal_approx(fg.research_time, float(slot["research_time"])))
	await pframes(30)
	verdict("C5 прогресс растёт", fg.research_progress() > 0.0, "%.3f" % fg.research_progress())
	verdict("C6 повторный заказ того же узла отбит", not fg.research(id))
	_sig.clear()
	fg.research_timer = fg.research_time - 0.001
	var waited := 0
	while not GameManager.is_researched(G, id) and waited < 300:
		await pframes(1)
		waited += 1
	verdict("C7 исследование доехало по таймеру", GameManager.is_researched(G, id) and fg.research_id.is_empty(),
		"кадров %d" % waited)
	await frames(2)
	var got := false
	for s in _sig:
		if int(s[0]) == G and String(s[1]) == id:
			got = true
	verdict("C8 сигнал research_finished(FACTION_GOBLIN, id)", got)
	verdict("C9 ряд II открылся", GameManager.can_research(G, "gforge_hide_2"))
	# Отмена: полный возврат
	var w0: float = _amt(G, Constants.RESOURCE_WOOD)
	var g0: float = _amt(G, Constants.RESOURCE_GOLD)
	var f0: float = _amt(G, Constants.RESOURCE_FOOD)
	verdict("C10 второй заказ и отмена возвращают всё",
		fg.research("gforge_pikes_1") and fg.cancel_research("gforge_pikes_1")
		and is_equal_approx(_amt(G, Constants.RESOURCE_WOOD), w0) and is_equal_approx(_amt(G, Constants.RESOURCE_GOLD), g0)
		and is_equal_approx(_amt(G, Constants.RESOURCE_FOOD), f0) and not GameManager.is_researching(G, "gforge_pikes_1"))
	fg._die()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. ПРИМЕНЕНИЕ БОНУСОВ
# ═════════════════════════════════════════════════════════════════════════════
func _block_d() -> void:
	print("\n═════ D. БОНУСЫ: ГОБЛИНАМ ЖИВЫМ И НОВОРОЖДЁННЫМ, ЛЮДЯМ — НЕТ ═════")
	var gob: Unit = _unit("goblin_spearman", G, _spot(70.0, 60.0))
	var rider: Unit = _unit("goblin_rider", G, _spot(72.0, 64.0))
	var man: Unit = _unit("spearman", P, _spot(74.0, 60.0))
	await pframes(3)
	var base_hp: float = gob.max_health
	var wb: float = _UCfg.walk_boost("goblin_spearman")
	# Скорость: гоблин с целью бежит (GoblinSpearman._sync_run_speed меняет move_speed),
	# поэтому сравнивается ДОБАВКА сверх move_speed × walk_boost, а не само число
	var spd0: float = gob._base_speed() - gob.move_speed * wb
	var cd0: float = gob._effective_cooldown()
	var mor0: float = gob._effective_morale()
	var man_spd0: float = man._base_speed()
	var man_hp0: float = man.max_health

	var hide: Dictionary = _GF.get_node("gforge_hide_1")
	var howl: Dictionary = _GF.get_node("gforge_howl_1")
	var dop: Dictionary = _GF.get_node("gforge_doping_1")
	var pik: Dictionary = _GF.get_node("gforge_pikes_1")
	# hide_1 уже изучен блоком C, если тот шёл; иначе — выдаём
	if not GameManager.is_researched(G, "gforge_hide_1"):
		GameManager.finish_research(G, "gforge_hide_1")
	GameManager.finish_research(G, "gforge_howl_1")
	GameManager.finish_research(G, "gforge_doping_1")
	GameManager.finish_research(G, "gforge_pikes_1")
	await pframes(2)

	verdict("D1 броня копится орде по роду (unit_bonus)",
		is_equal_approx(GameManager.unit_bonus(G, "goblin_spearman", "bonus_armor"), float(hide["bonus_armor"]))
		and is_equal_approx(GameManager.unit_bonus(G, "goblin_rider", "bonus_armor"), float(hide["bonus_armor"])))
	verdict("D2 людям не применяется (ни их роду, ни гоблинскому у фракции игрока)",
		GameManager.unit_bonus(P, "spearman", "bonus_armor") == 0.0
		and GameManager.unit_bonus(P, "goblin_spearman", "bonus_armor") == 0.0
		and GameManager.unit_bonus(Constants.FACTION_ENEMY, "goblin_spearman", "bonus_armor") == 0.0)
	# Броня вживую: потеря от удара = damage_after_armor с бонусом кузницы и меньше, чем без него
	var hp_b: float = gob.current_health
	gob.take_damage(40.0, man)
	var loss_after: float = hp_b - gob.current_health
	var def_base: float = gob.defense + gob.armor + _UCfg.stance_stat(gob.stance, "defense_bonus", 0.0)
	var want_loss: float = _UCfg.damage_after_armor(40.0, def_base + float(hide["bonus_armor"]))
	var loss_no_bonus: float = _UCfg.damage_after_armor(40.0, def_base)
	verdict("D3 живой гоблин теряет от удара по броне с бонусом (меньше, чем без него)",
		absf(loss_after - want_loss) < 0.05 and loss_after < loss_no_bonus - 0.05,
		"потеря %.2f, ждали %.2f, без бонуса %.2f" % [loss_after, want_loss, loss_no_bonus])
	# Ночной вой
	var spd1: float = gob._base_speed() - gob.move_speed * wb
	var want_spd: float = float(howl["bonus_speed"]) * wb
	verdict("D4 «Ночной вой»: скорость хода живого +bonus_speed", absf((spd1 - spd0) - want_spd) < 0.01,
		"добавка %.3f → %.3f (ждали +%.3f)" % [spd0, spd1, want_spd])
	var cd1: float = gob._effective_cooldown()
	verdict("D5 «Ночной вой»: перезарядка ×(1−bonus_cooldown_pct)",
		absf(cd1 / cd0 - (1.0 - float(howl["bonus_cooldown_pct"]))) < 0.01, "%.3f → %.3f" % [cd0, cd1])
	verdict("D6 скорость и темп человека не изменились",
		is_equal_approx(man._base_speed(), man_spd0) and is_equal_approx(man.max_health, man_hp0))
	# Орочий допинг
	verdict("D7 «Орочий допинг»: HP живого гоблина +bonus_health",
		is_equal_approx(gob.max_health, base_hp + float(dop["bonus_health"])), "%.0f → %.0f" % [base_hp, gob.max_health])
	var mor1: float = gob._effective_morale()
	var mult: float = _UCfg.stance_stat(gob.stance, "morale_mult", 1.0)
	verdict("D8 «Орочий допинг»: мораль +bonus_morale", absf((mor1 - mor0) - float(dop["bonus_morale"]) * mult) < 0.01,
		"%.1f → %.1f" % [mor0, mor1])
	var sid: int = main.spawn_goblin_squad("goblin_spearman", 3, _spot(80.0, 70.0))
	await pframes(3)
	var born_ok := sid > 0
	var born_hp := -1.0
	if sid > 0:
		for m in (GameManager.squads[sid]["members"] as Array):
			if m != null and is_instance_valid(m):
				born_hp = (m as Unit).max_health
				if not is_equal_approx(born_hp, base_hp + float(dop["bonus_health"])):
					born_ok = false
	verdict("D9 новорождённый гоблин (Main.spawn_goblin_squad) получает HP при рождении", born_ok,
		"HP %.0f (ждали %.0f)" % [born_hp, base_hp + float(dop["bonus_health"])])
	# Зазубренные пики
	verdict("D10 «Зазубренные пики»: удар +bonus_attack в _upgrade_damage_bonus",
		is_equal_approx(GameManager.unit_bonus(G, "goblin_spearman", "bonus_attack"), float(pik["bonus_attack"]))
		and gob._upgrade_damage_bonus() >= float(pik["bonus_attack"]))
	gob._combo_step = 0
	gob.set_attack_target(rider)
	var d_cav: float = gob._strike_damage()
	gob._combo_step = 0
	gob.set_attack_target(man)
	var d_inf: float = gob._strike_damage()
	var gm: float = float(pik["bonus_giant_melee"])
	verdict("D11 против конницы (giant_class) ×(1+bonus_giant_melee), против пехоты — нет",
		rider.giant_class() and not man.giant_class()
		and is_equal_approx(d_cav, gob.attack_damage * (1.0 + gm)) and is_equal_approx(d_inf, gob.attack_damage),
		"конница %.1f, пехота %.1f, база %.1f" % [d_cav, d_inf, gob.attack_damage])
	verdict("D12 человек бьёт без гоблинского множителя", GameManager.unit_bonus(P, "spearman", "bonus_giant_melee") == 0.0)
	for u in [gob, rider, man]:
		(u as Unit).take_damage(1e12)
	if sid > 0:
		for m in (GameManager.squads[sid]["members"] as Array).duplicate():
			if m != null and is_instance_valid(m):
				(m as Unit).take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. ОКНО
# ═════════════════════════════════════════════════════════════════════════════
func _block_e() -> void:
	print("\n═════ E. ОКНО КУЗНИЦЫ: РЕАКТИВНЫЙ СТАТУС ═════")
	var fgP = _forge(_spot(60.0, 48.0), P)
	var fgG = _forge(_spot(60.0, 70.0), G)
	await pframes(3)
	_bank(P, 5000.0, 5000.0, 5000.0, 100.0)
	var g_armor0: float = GameManager.unit_bonus(G, "goblin_spearman", "bonus_armor")
	hud.show_selection([fgG])
	await frames(2)
	var pg = hud._gforge_panel
	verdict("E1 чужая (гоблинская) кузница окно игроку не открывает",
		pg == null or not is_instance_valid(pg) or not pg.visible)
	hud.show_selection([fgP])
	await frames(2)
	var panel = hud._gforge_panel
	verdict("E2 своя кузница открывает окно", panel != null and is_instance_valid(panel) and panel.visible)
	if panel == null or not is_instance_valid(panel):
		fgP._die(); fgG._die()
		return
	var id1 := "gforge_hide_1"
	var id2 := "gforge_pikes_1"
	verdict("E3 узел ряда I — «Доступно», ряда II — «Закрыто», заготовка помечена",
		panel.status_of(id1) == panel.ST_AVAIL and panel.status_of("gforge_hide_2") == panel.ST_LOCK
		and panel.status_of("gforge_poison_1").contains(panel.ST_STUB),
		"%s / %s / %s" % [panel.status_of(id1), panel.status_of("gforge_hide_2"), panel.status_of("gforge_poison_1")])
	var r: Rect2 = panel.get_global_rect()
	verdict("E4 точка окна — над интерфейсом (point_over_ui)", hud.point_over_ui(r.position + r.size * 0.5))
	panel._on_node_pressed(id1)
	panel._on_node_pressed(id2)
	await frames(2)
	verdict("E5 первый узел «Изучается» с полосой, второй «В очереди»",
		panel.status_of(id1).begins_with(panel.ST_BUSY) and panel.node_bars.has(id1)
		and panel.status_of(id2).begins_with(panel.ST_QUEUED),
		"%s / %s" % [panel.status_of(id1), panel.status_of(id2)])
	await pframes(20)
	var bar: ProgressBar = panel.node_bars.get(id1)
	verdict("E6 полоса живёт (value > 0)", bar != null and is_instance_valid(bar) and bar.value > 0.0)
	# Опрос обезоружен: следующий id уже «виден» окну — сработать обязан сигнал
	panel._last_rid = id2
	fgP.research_timer = fgP.research_time - 0.001
	var waited := 0
	while not GameManager.is_researched(P, id1) and waited < 300:
		await pframes(1)
		waited += 1
	await frames(2)
	verdict("E7 по сигналу за два process_frame: первый «Изучено», второй «Изучается»",
		panel.status_of(id1) == panel.ST_DONE and panel.status_of(id2).begins_with(panel.ST_BUSY),
		"%s / %s" % [panel.status_of(id1), panel.status_of(id2)])
	# Ручка выключена, опрос обезоружен — старое поведение: статус стоит
	_Opt.forge_live_refresh = false
	panel._last_rid = ""
	fgP.research_timer = fgP.research_time - 0.001
	waited = 0
	while not GameManager.is_researched(P, id2) and waited < 300:
		await pframes(1)
		waited += 1
	await frames(2)
	verdict("E8 ручка forge_live_refresh выключена + опрос обезоружен — статус не менялся",
		panel.status_of(id2).begins_with(panel.ST_BUSY), panel.status_of(id2))
	_Opt.forge_live_refresh = true
	panel._rebuild()
	verdict("E9 после перестройки второй «Изучено»", panel.status_of(id2) == panel.ST_DONE)
	hud.show_selection([])
	await frames(2)
	verdict("E10 снятие выделения закрывает окно", not panel.visible)
	verdict("E11 бонусы кузницы игрока легли на гоблинов фракции ИГРОКА, не орды",
		is_equal_approx(GameManager.unit_bonus(P, "goblin_spearman", "bonus_armor"), float(_GF.get_node(id1)["bonus_armor"]))
		and is_equal_approx(GameManager.unit_bonus(G, "goblin_spearman", "bonus_armor"), g_armor0))
	fgP._die(); fgG._die()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# F. ИИ ОРДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _block_f() -> void:
	print("\n═════ F. ВОЖАК ОРДЫ: ПРИТОК, ЗАКЛАДКА, ИССЛЕДОВАНИЕ, РУЧКА ═════")
	var gai = main.goblin_ai
	if gai == null or not _Opt.goblin_village:
		verdict("F0 вожак и лагерь есть", false)
		return
	var ai = gai._gforge
	_Opt.goblin_forge = true
	ai.lay_after_sec = 1.0e9
	_bank(G, 100.0, 50.0, 2000.0, 0.0)
	gai.set_process(true)
	var w0: float = _amt(G, Constants.RESOURCE_WOOD)
	await pframes(60 * 12)
	var w1: float = _amt(G, Constants.RESOURCE_WOOD)
	var g1: float = _amt(G, Constants.RESOURCE_GOLD)
	verdict("F1 приток дерева и золота лагеря", w1 > w0 + 1.0 and g1 > 50.0 and ai.wood_income_min > 0.0,
		"дерево %.0f → %.0f, золото %.0f, %.1f л/мин" % [w0, w1, g1, ai.wood_income_min])
	# Закладка: ресурсы есть, срок снят
	ai.lay_after_sec = 0.0
	var cost: Dictionary = _UCfg.building_cost("goblin_forge")
	_bank(G, 2000.0, 1000.0, 2000.0, 0.0)
	var sw0: float = _spent(G, Constants.RESOURCE_WOOD)
	var sg0: float = _spent(G, Constants.RESOURCE_GOLD)
	var sf0: float = _spent(G, Constants.RESOURCE_FOOD)
	var build_t: float = _UCfg.building_stat("goblin_forge", "build_time", 30.0)
	var fg: Node = null
	var fr := 0
	var cap: int = int((build_t + 20.0) * 60.0)
	while fg == null and fr < cap:
		await pframes(30)
		fr += 30
		fg = _GFB.forge_of(get_tree(), G)
	verdict("F2 вожак заложил кузницу (через build_time)", fg != null and ai.forges_laid == 1,
		"кадров %d, laid=%d, %s" % [fr, ai.forges_laid, ai.last_action])
	if fg == null:
		gai.set_process(false)
		return
	var dv: Vector3 = fg.global_position - gai.village
	var off: float = Vector2(dv.x, dv.z).length()
	verdict("F3 кузница у лагеря и в поле карты", off > 10.0 and off < 45.0
		and GameManager.is_passable(fg.global_position.x, fg.global_position.z + 10.0), "%.1f м от центра" % off)
	# Списание — по телеметрии расхода (tm_spent): банк орды параллельно кормит
	# рудник лагеря (золото) и экономика еды, арифметика по остатку врёт
	var dw: float = _spent(G, Constants.RESOURCE_WOOD) - sw0
	var dg: float = _spent(G, Constants.RESOURCE_GOLD) - sg0
	var df: float = _spent(G, Constants.RESOURCE_FOOD) - sf0
	verdict("F4 цена закладки списана: расход дерева, золота и еды ≥ цены конфига",
		dw >= float(cost[Constants.RESOURCE_WOOD]) - 0.5 and dg >= float(cost[Constants.RESOURCE_GOLD]) - 0.5
		and df >= float(cost[Constants.RESOURCE_FOOD]) - 0.5,
		"расход %.0f л / %.0f з / %.0f е (цена %d/%d/%d)" % [dw, dg, df,
			cost[Constants.RESOURCE_WOOD], cost[Constants.RESOURCE_GOLD], cost[Constants.RESOURCE_FOOD]])
	# Исследование
	_bank(G, 2000.0, 1000.0, 2000.0, 0.0)
	fr = 0
	while String(fg.research_id).is_empty() and fr < 60 * 60:
		await pframes(30)
		fr += 30
	var rid: String = String(fg.research_id)
	verdict("F5 вожак заказал исследование (не заготовку)", not rid.is_empty() and ai.researches_ordered >= 1
		and not bool(_GF.get_node(rid).get("stub", false)), "%s за %d кадров" % [rid, fr])
	# Ручка выключена: кузницу снесли — новая не закладывается, притока нет
	gai.set_process(false)
	fg._die()
	await pframes(3)
	_Opt.goblin_forge = false
	_bank(G, 2000.0, 1000.0, 2000.0, 0.0)
	var laid0: int = ai.forges_laid
	gai.set_process(true)
	await pframes(int((build_t + 15.0) * 60.0))
	gai.set_process(false)
	verdict("F6 ручка perf_config.goblin_forge выключена — ни закладки, ни притока",
		ai.forges_laid == laid0 and _GFB.forge_of(get_tree(), G) == null
		and is_equal_approx(_amt(G, Constants.RESOURCE_WOOD), 2000.0),
		"laid %d→%d, дерево %.0f" % [laid0, ai.forges_laid, _amt(G, Constants.RESOURCE_WOOD)])
	_Opt.goblin_forge = true
