extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ГЛАВНЫЙ ЦИКЛ ИИ ЛЮДЕЙ — МИР 10 МИНУТ, РУДНИК, БАШНИ, РЕЙДЫ,
## ШТУРМ С 35-й; ТРИГГЕР ПОБЕДЫ (спринт 17, блоки 3-4)
## ═══════════════════════════════════════════════════════════════════════════
##   A — мирная фаза из конфига — 10 минут; в мире все отряды дома;
##   B — экспансия: один отряд идёт на ближайший не свой рудник, захватывает
##       и остаётся резервом;
##   C — башни на границе: после стрелковой ИИ закладывает башню на доле пути
##       к базе игрока;
##   D — рейды: по истечении мира выходит рейд-отряд на рабочих игрока, при
##       сильном сопротивлении отходит в замок; рейды повторяются;
##   E — штурм: до 35-й минуты — оборона, после и с набранным лимитом — волна
##       на базу игрока;
##   F — победа: вырезанные рабочие ИИ БЕЗ крепости — не победа; разбитый
##       ИИ с крепостью — победа.
## Запуск: godot --headless --path . res://qa_ai_loop/Test.tscn

const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _Diff := preload("res://scripts/game_difficulty_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var ai = null
var castle: Castle = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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

func _finish() -> void:
	print("\n═════ ИТОГ qa_ai_loop: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _ai_squad(kind: String, at: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(Constants.FACTION_ENEMY, kind)
	for i in range(n):
		var u := _spawn(kind, Constants.FACTION_ENEMY, at + Vector3(float(i % 5) * 0.7, 0.0, float(i / 5) * 0.7))
		GameManager.add_to_squad(sid, u)
	return sid

## Такт ИИ с продвижением его часов и разбором очереди
func think(steps: int = 1, sec: float = _AICfg.THINK_INTERVAL) -> void:
	for _s in range(steps):
		ai.clock += sec
		ai.tick()
		var guard := 0
		while ai._order_at < ai._order_queue.size() and guard < 64:
			ai._drain_orders()
			guard += 1
		await pframes(int(sec * 60.0))

func _sq_by_id(sid: int) -> Dictionary:
	for s in ai.squads:
		if ai._sid_of(s) == sid:
			return s
	return {}

func _roles() -> Dictionary:
	var out: Dictionary = {}
	for s in ai.squads:
		var r: String = String((s as Dictionary)["role"])
		out[r] = int(out.get(r, 0)) + 1
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	ai = main.enemy_ai
	ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	# Крепость ИИ ставит стенд: партия начинается без неё
	var cp: Vector3 = main.ENEMY_BASE_ANCHOR
	castle = Castle.new()
	castle.faction = Constants.FACTION_ENEMY
	main.world_add(castle)
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(3)
	ai._home_pos = castle.global_position

	print("\n═════ A. МИР 10 МИНУТ ═════")
	verdict("A1 мирная фаза ИИ людей — 600 с (10 минут)", is_equal_approx(_AICfg.PEACE_SECONDS, 600.0),
		"%.0f" % _AICfg.PEACE_SECONDS)
	# 13.09.2026: 30-я минута (1800), одно число с орды
	verdict("A2 штурм базы игрока — не раньше 30-й минуты (1800 с)",
		is_equal_approx(_AICfg.AI_ASSAULT_AT_SEC, 1800.0), "%.0f" % _AICfg.AI_ASSAULT_AT_SEC)
	# Армия: три копейщика, мечники, лучники — все дома в мире
	var sids: Array = []
	for i in range(3):
		sids.append(_ai_squad("spearman", cp + Vector3(-10.0 + float(i) * 8.0, 0.0, -14.0), 12))
	sids.append(_ai_squad("warrior", cp + Vector3(14.0, 0.0, -14.0), 8))
	sids.append(_ai_squad("archer", cp + Vector3(-18.0, 0.0, -14.0), 8))
	await pframes(3)
	ai._peace_over = false
	ai._peace_timer = 0.0
	await think(2)
	var far := 0
	for sid in sids:
		if _xz(GameManager.squad_centroid(int(sid)), cp) > 40.0:
			far += 1
	verdict("A3 в мире войска остаются у своего замка", far == 0 and not ai._peace_over, "ушло %d" % far)

	print("\n═════ B. ЭКСПАНСИЯ: РУДНИК ═════")
	ai._peace_over = true
	ai.clock = 601.0
	# Ничейный рудник в 30 м от замка — цель экспансии
	var mine := Mine.new()
	mine.faction = Constants.FACTION_NEUTRAL
	main.world_add(mine)
	var mp: Vector3 = GameManager.land_target(cp + Vector3(-30.0, 0.0, -26.0))
	mine.global_position = Vector3(mp.x, GameManager.get_terrain_height(mp.x, mp.z), mp.z)
	await pframes(2)
	await think(1)
	verdict("B1 один отряд получает роль «рудник»", int(_roles().get(ai.ROLE_MINE, 0)) == 1 and ai.mine_sid > 0,
		str(_roles()))
	var msq: Dictionary = _sq_by_id(ai.mine_sid)
	verdict("B2 цель — этот рудник", not msq.is_empty() and _xz(msq["target"], mine.global_position) < 6.0)
	await think(10)
	verdict("B3 рудник захвачен ИИ", int(mine.faction) == Constants.FACTION_ENEMY and ai.mines_captured >= 1,
		"владелец %d, захватов %d" % [int(mine.faction), ai.mines_captured])
	await think(2)
	verdict("B4 после захвата отряд остаётся на руднике резервом",
		ai.mine_sid > 0 and String(_sq_by_id(ai.mine_sid).get("role", "")) == ai.ROLE_MINE
		and _xz(GameManager.squad_centroid(ai.mine_sid), mine.global_position) < 16.0,
		"%.1f м" % _xz(GameManager.squad_centroid(ai.mine_sid), mine.global_position))

	print("\n═════ C. БАШНИ НА ГРАНИЦЕ ═════")
	# Барак, кузница и стрелковая уже стоят — иначе стройка идёт по порядку
	var made: Array = [Barracks.new(), Smithy.new(), load("res://scripts/Archery.gd").new()]
	for k in range(made.size()):
		var bld: Building = made[k]
		bld.faction = Constants.FACTION_ENEMY
		main.world_add(bld)
		bld.global_position = cp + Vector3(8.0 + float(k) * 8.0, 0.0, 8.0)
	await pframes(4)
	var towers0: int = ai._towers_count()
	var workers: Array = []
	for i in range(3):
		workers.append(_spawn("worker", Constants.FACTION_ENEMY, cp + Vector3(4.0 + float(i), 0.0, -4.0)))
	ResourceManager.add_resource(Constants.FACTION_ENEMY, Constants.RESOURCE_WOOD, 2000.0)
	ResourceManager.add_resource(Constants.FACTION_ENEMY, Constants.RESOURCE_STONE, 2000.0)
	ResourceManager.add_resource(Constants.FACTION_ENEMY, Constants.RESOURCE_GOLD, 2000.0)
	await pframes(2)
	ai._construction(castle)
	await pframes(2)
	var towers1: int = ai._towers_count()
	verdict("C1 после стрелковой ИИ закладывает башню на границе", towers1 > towers0, "башен %d → %d" % [towers0, towers1])
	var tspot: Vector3 = ai._tower_spot(castle, 0)
	var axis_d: float = _xz(cp, main.PLAYER_BASE_ANCHOR) * _AICfg.TOWER_BORDER_FRACTION
	verdict("C2 башня стоит на доле пути к базе игрока, а не у стены замка",
		absf(_xz(tspot, cp) - sqrt(axis_d * axis_d + _AICfg.TOWER_SIDE * _AICfg.TOWER_SIDE)) < 8.0,
		"%.0f м от замка" % _xz(tspot, cp))

	print("\n═════ D. РЕЙДЫ ═════")
	# База игрока с рабочими — в 60 м
	var pp: Vector3 = cp + Vector3(-60.0, 0.0, 10.0)
	var pcastle := Castle.new()
	pcastle.faction = Constants.FACTION_PLAYER
	main.world_add(pcastle)
	pcastle.global_position = Vector3(pp.x, GameManager.get_terrain_height(pp.x, pp.z), pp.z)
	await pframes(3)
	var pworkers: Array = []
	for i in range(3):
		var w := _spawn("worker", Constants.FACTION_PLAYER, pp + Vector3(6.0 + float(i), 0.0, 5.0))
		w.set_tick(false)
		w.current_health = w.max_health * 100.0
		w._soa_push_stats()
		pworkers.append(w)
	ai._raid_last = -1.0e9
	await think(1)
	verdict("D1 после мира выходит рейд на экономику игрока", ai.raids_launched >= 1 and ai.raid_sid > 0,
		"рейдов %d" % ai.raids_launched)
	var rsq: Dictionary = _sq_by_id(ai.raid_sid)
	verdict("D2 рейд-отряд — мечники", not rsq.is_empty() and String(rsq["type"]) == "warrior", String(rsq.get("type", "-")))
	var prey_worker := false
	var rp: Variant = rsq.get("raid_prey")
	if rp != null and is_instance_valid(rp) and rp is Worker:
		prey_worker = true
	verdict("D3 цель рейда — рабочий игрока", prey_worker)
	# Сильное сопротивление — отход в замок
	var rc: Vector3 = GameManager.squad_centroid(ai.raid_sid)
	var wall: Array = []
	for i in range(16):
		var f := _spawn("spearman", Constants.FACTION_PLAYER, rc + Vector3(2.0 + float(i % 8) * 0.6, 0.0, -2.0 + float(i / 8) * 0.6))
		f.set_tick(false)
		f.current_health = f.max_health * 100.0
		f._soa_push_stats()
		wall.append(f)
	await pframes(2)
	var ret0: int = ai.raid_retreats
	var rsid: int = ai.raid_sid
	await think(1)
	rsq = _sq_by_id(rsid)
	verdict("D4 при сильном сопротивлении рейд отходит в замок (hit-and-run)",
		ai.raid_retreats > ret0 and ai.raid_sid == 0 and String(rsq.get("role", "")) == ai.ROLE_RETREAT,
		"отходов %d, роль %s" % [ai.raid_retreats, String(rsq.get("role", "-"))])
	for f in wall:
		if is_instance_valid(f):
			(f as Unit).take_damage(1e9)
	await pframes(2)
	# Отошедший отряд лечится в замке; следующий рейд идёт другим отрядом
	ai._raid_last = -1.0e9
	await think(1)
	verdict("D5 рейды повторяются (следующий — свежим отрядом)", ai.raids_launched >= 2, "рейдов %d" % ai.raids_launched)

	print("\n═════ E. ШТУРМ С 35-й МИНУТЫ ═════")
	# Лимит набран (лимиты сложности) — но часы ещё до 35-й минуты
	while not ai.army_ready():
		var need: String = ""
		for t in _AICfg.combat_types():
			if ai.squad_count(String(t)) < _Diff.ai_squad_limit(String(t)):
				need = String(t)
				break
		if need == "":
			break
		_ai_squad(need, cp + Vector3(-20.0 + float(ai.squads.size() % 6) * 6.0, 0.0, -30.0 - float(ai.squads.size() / 6) * 6.0), 6)
		await pframes(1)
		ai._regroup()
	verdict("E0 лимит армии набран", ai.army_ready())
	ai.clock = 1500.0
	await think(1)
	verdict("E1 до 35-й минуты — оборонительный режим (штурма нет)",
		not ai._assault_time() and int(_roles().get(ai.ROLE_ASSAULT, 0)) == 0, str(_roles()))
	ai.clock = _AICfg.AI_ASSAULT_AT_SEC + 1.0
	await think(1)
	verdict("E2 с 35-й минуты и набранным лимитом — волна на базу игрока",
		ai._assault_time() and (int(_roles().get(ai.ROLE_ASSAULT, 0)) > 0 or int(_roles().get(ai.ROLE_FIELD, 0)) > 0),
		str(_roles()))

	print("\n═════ F. ТРИГГЕР ПОБЕДЫ ═════")
	# Живой ИИ (крепость есть) — не победа
	main._match_clock = 300.0
	main._check_victory()
	verdict("F1 живой ИИ с крепостью — не победа", main._phase == main.Phase.PLAYING)
	# Убираем всё у ИИ, КРОМЕ крепости: живых нет, крепость стоит — не победа
	# И укрытых в замке тоже (они вне групп, но живы): бьём по реестру живых
	var enemy_units: Array = get_tree().get_nodes_in_group("enemy_units").duplicate()
	for lu in GameManager._live_units:
		if is_instance_valid(lu) and lu is Unit and int((lu as Unit).faction) == Constants.FACTION_ENEMY:
			enemy_units.append(lu)
	for u in enemy_units:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
			if (u as Unit).garrisoned:
				(u as Unit).garrisoned = false
			(u as Unit).take_damage(1e9)
	await pframes(3)
	main._check_victory()
	verdict("F2 вырезаны все бойцы ИИ, но крепость стоит — не победа", main._phase == main.Phase.PLAYING)
	verdict("F3 крепость ИИ отмечена как «была»", bool(main._ai_castle_placed))
	# Крепость снесена — теперь победа законна
	castle.take_damage(1e9)
	await pframes(3)
	for b in get_tree().get_nodes_in_group("enemy_buildings").duplicate():
		if is_instance_valid(b) and b is Building and not (b as Building).is_dead():
			(b as Building).take_damage(1e9)
	await pframes(3)
	main._check_victory()
	verdict("F4 крепость снесена и живых нет — победа", main._phase == main.Phase.VICTORY)
	# И обратный случай: ИИ БЕЗ крепости (старт партии) с вырезанными рабочими
	main._phase = main.Phase.PLAYING
	main._ai_castle_placed = false
	main._ai_wiped_since = -1.0
	main._match_clock = 280.0
	main._check_victory()
	verdict("F5 на 4:40 вырезанные рабочие ИИ без крепости — НЕ победа", main._phase == main.Phase.PLAYING)
	main._match_clock = 280.0 + main.AI_WIPED_GRACE_SEC + 1.0
	main._check_victory()
	verdict("F6 но ИИ, у которого %.0f с подряд нет ни живых, ни построек, — разбит (партия не висит вечно)" % main.AI_WIPED_GRACE_SEC,
		main._phase == main.Phase.VICTORY)
	_finish()
