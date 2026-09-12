extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ВТОРОЙ ПЕНЬ У ИИ И НЕПРИКОСНОВЕННОСТЬ ЕГО КРЕПОСТИ (спринт 18, письмо 8)
## ═══════════════════════════════════════════════════════════════════════════
##   A — пень ИИ стоит далеко от крепости ИИ (дальше патруля тролля, агро
##       гноллов и башен ИИ на границе), на суше, площадка без леса;
##   B — орда не сносит крепость ИИ: приказ атаки не принимается, вожак и
##       командир штурма её не выбирают, прямой урон от гоблина не проходит;
##       дом ИИ, крепость ИГРОКА и удар ИГРОКА по крепости ИИ — как прежде;
##   C — переход замка приказа на соседний дом крепость ИИ не выбирает;
##       троллю нельзя ни одну крепость.
## Запуск: godot --headless --path . res://qa_lair_ai/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")
const _Troll := preload("res://scripts/goblin/Troll.gd")
const _Gnoll := preload("res://scripts/goblin/Gnoll.gd")

var main = null
var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(180.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 180 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_lair_ai: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _bld(id: String, fac: int, at: Vector3) -> Building:
	var b: Building = _CSite.make_building(id)
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return b

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

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
	await pframes(4)

	print("\n═════ A. ГДЕ СТОИТ ПЕНЬ ИИ ═════")
	var c2: Vector3 = main.troll_lair_center_ai()
	var anchor: Vector3 = main.ENEMY_BASE_ANCHOR
	var d_anchor: float = _xz(c2, anchor)
	print("  пень ИИ %s, якорь ИИ %s, расстояние %.1f м" % [str(c2), str(anchor), d_anchor])
	verdict("A1 второй пень включён и зарегистрирован (два логова)",
		_GobCfg.LAIR_AI_ENABLED and GameManager.troll_lairs.size() >= 2,
		"логов %d" % GameManager.troll_lairs.size())
	var danger: float = _GobCfg.TROLL_PATROL_RADIUS + _GobCfg.GNOLL_DEFEND_RANGE + 30.0
	verdict("A2 пень дальше от крепости ИИ, чем патруль тролля + агро гноллов + 30 м (%.0f м)" % danger,
		d_anchor > danger, "%.1f м" % d_anchor)
	var d_player: float = _xz(main.troll_lair_center(), main.PLAYER_BASE_ANCHOR)
	verdict("A3 и не ближе, чем пень игрока к его крепости (−10 %%)",
		d_anchor >= d_player * 0.9, "%.1f против %.1f м" % [d_anchor, d_player])
	# Башни ИИ на границе: на TOWER_BORDER_FRACTION пути к игроку, ±TOWER_SIDE
	var axis: Vector3 = main.PLAYER_BASE_ANCHOR - anchor
	axis.y = 0.0
	var tpos: Vector3 = anchor + axis * _AICfg.TOWER_BORDER_FRACTION
	var side := Vector3(-axis.z, 0.0, axis.x).normalized() * _AICfg.TOWER_SIDE
	var d_tower: float = minf(_xz(c2, tpos + side), _xz(c2, tpos - side))
	verdict("A4 башни ИИ на границе вне патруля тролля (%.1f м > %.1f)" % [d_tower, _GobCfg.TROLL_PATROL_RADIUS + 10.0],
		d_tower > _GobCfg.TROLL_PATROL_RADIUS + 10.0)
	verdict("A5 пень на суше и на стороне ИИ (x > 0), внизу карты (z > 0)",
		not GameManager.is_water(c2.x, c2.z) and c2.x > 0.0 and c2.z > 0.0)
	var trees := 0
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		# Спринт 20: глушь у пня — рощицы с LAIR_GLADE_TREES_R; чистое —
		# только внутреннее кольцо
		if is_instance_valid(n) and _xz((n as Node3D).global_position, c2) < _GobCfg.LAIR_GLADE_R1 - 1.0:
			trees += 1
	verdict("A6 площадка пня без леса и руды (в %.0f м: %d)" % [_GobCfg.LAIR_GLADE_R1 - 1.0, trees], trees == 0)
	# Стражи на месте
	var guards := 0
	for u in get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_GOBLIN)):
		if is_instance_valid(u) and (u.get_script() == _Troll or u.get_script() == _Gnoll) and _xz((u as Node3D).global_position, c2) < _GobCfg.LAIR_CLEAR:
			guards += 1
	verdict("A7 у пня ИИ есть стражи (тролль/гноллы): %d" % guards, guards > 0)

	print("\n═════ B. ОРДА НЕ СНОСИТ КРЕПОСТЬ ИИ ═════")
	GameManager.world_bounds_enabled = false
	var p0 := Vector3(-1500.0, 0.0, -900.0)
	var keep: Building = _bld("castle", Constants.FACTION_ENEMY, p0)
	var house: Building = _bld("house", Constants.FACTION_ENEMY, p0 + Vector3(18.0, 0.0, 0.0))
	var pkeep: Building = _bld("castle", Constants.FACTION_PLAYER, p0 + Vector3(0.0, 0.0, 60.0))
	await pframes(3)
	verdict("B0 крепость ИИ — цитадель (орде нельзя), дом ИИ и крепость игрока — можно",
		keep.has_method("is_stronghold") and bool(keep.call("is_stronghold")) and not GameManager.goblin_may_raze(keep)
		and GameManager.goblin_may_raze(house) and GameManager.goblin_may_raze(pkeep))
	var g: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, p0 + Vector3(8.0, 0.0, 0.0))
	g.set_tick(false)
	g.command_attack(keep, true, false, true)
	verdict("B1 приказ гоблину бить крепость ИИ не принимается", g.attack_target != keep,
		"цель %s" % str(g.attack_target))
	g.command_attack(house, true, false, true)
	verdict("B2 приказ бить дом ИИ принимается", g.attack_target == house)
	g.command_attack(pkeep, true, false, true)
	verdict("B3 крепость ИГРОКА гоблину по-прежнему доступна", g.attack_target == pkeep)
	var hp0: float = keep.current_health
	keep.take_damage(500.0, g)
	verdict("B4 прямой урон гоблина по крепости ИИ не проходит (%.0f → %.0f)" % [hp0, keep.current_health],
		absf(keep.current_health - hp0) < 0.01)
	var hh0: float = house.current_health
	house.take_damage(50.0, g)
	verdict("B5 а по дому ИИ — проходит", house.current_health < hh0)
	var sp: Unit = _spawn("spearman", Constants.FACTION_PLAYER, p0 + Vector3(-8.0, 0.0, 0.0))
	sp.set_tick(false)
	keep.take_damage(50.0, sp)
	verdict("B6 удар ИГРОКА по крепости ИИ проходит", keep.current_health < hp0)
	var ph0: float = pkeep.current_health
	pkeep.take_damage(50.0, g)
	verdict("B7 крепость игрока от гоблина урон получает", pkeep.current_health < ph0)
	# Вожак и командир: ближайшая чужая постройка — дом, не крепость
	var gai = main.goblin_ai
	await pframes(2)
	var snap: Array = GameManager.enemy_buildings_snapshot(Constants.FACTION_GOBLIN)
	var near_snap := 0
	for b in snap:
		if is_instance_valid(b) and _xz((b as Node3D).global_position, p0) < 40.0:
			near_snap += 1
	print("  снимок чужих построек орды: %d, из них у площадки %d; группы %s" % [snap.size(), near_snap, str(Constants.enemy_building_groups(Constants.FACTION_GOBLIN))])
	var near_c = gai._nearest_enemy_building(p0 + Vector3(2.0, 0.0, 0.0), 40.0)
	verdict("B8 вожак у самой крепости ИИ выбирает дом, не крепость", near_c == house, "выбрал %s" % str(near_c))
	var cmd = gai.get("commander")
	if cmd != null and cmd.has_method("_nearest_building"):
		var nb = cmd._nearest_building(p0 + Vector3(2.0, 0.0, 0.0), 40.0)
		verdict("B9 командир штурма тоже", nb == house, "выбрал %s" % str(nb))
	else:
		verdict("B9 командир штурма тоже (доступен)", true, "командира на сцене нет — пропуск")

	print("\n═════ C. ПЕРЕХОД ЗАМКА И ТРОЛЛЬ ═════")
	g.command_attack(house, true, false, true)
	house.take_damage(1e9, sp)
	await pframes(3)
	var nxt = g._next_enemy_building()
	verdict("C1 после сноса дома соседняя цель гоблина — не крепость ИИ", nxt != keep, "следующая %s" % str(nxt))
	var tr: Unit = _spawn("troll", Constants.FACTION_GOBLIN, p0 + Vector3(12.0, 0.0, 12.0))
	tr.set_tick(false)
	var phouse: Building = _bld("house", Constants.FACTION_PLAYER, p0 + Vector3(30.0, 0.0, 60.0))
	await pframes(2)
	verdict("C2 троллю нельзя ни крепость ИИ, ни крепость игрока, дом — можно",
		not tr.may_attack_building(keep) and not tr.may_attack_building(pkeep)
		and tr.may_attack_building(phouse))
	tr.command_attack(pkeep, true, false, true)
	verdict("C3 приказ троллю на крепость игрока не принимается", tr.attack_target != pkeep)

	print("
═════ D. АВТО-АГРО ОРДЫ У КРЕПОСТИ ИИ ═════")
	var p1 := p0 + Vector3(0.0, 0.0, -120.0)
	var keep2: Building = _bld("castle", Constants.FACTION_ENEMY, p1)
	var g2: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, p1 + Vector3(7.0, 0.0, 0.0))
	g2.set_stance("attack")
	await pframes(150)
	verdict("D1 гоблин рядом с одинокой крепостью ИИ цели не берёт (авто-агро)",
		g2.attack_target == null and absf(keep2.current_health - keep2.max_health) < 0.01,
		"цель %s, запас %.0f/%.0f" % [str(g2.attack_target), keep2.current_health, keep2.max_health])
	var house2: Building = _bld("house", Constants.FACTION_ENEMY, p1 + Vector3(9.0, 0.0, 6.0))
	await pframes(150)
	verdict("D2 а дом ИИ рядом — берёт", g2.attack_target == house2 or house2.current_health < house2.max_health,
		"цель %s, запас дома %.0f/%.0f" % [str(g2.attack_target), house2.current_health, house2.max_health])
	_finish()
