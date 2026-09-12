extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: РУДНИК ОРДЫ, ЕГО ОХРАНА, ТРЕВОГА, БАЗОВАЯ ЖИЛА (спринт 17, блок 2)
## ═══════════════════════════════════════════════════════════════════════════
##   A — рудник в MINE_OFFSET от деревни к центру, с рождения ЗАХВАЧЕН ордой,
##       золото капает в её банк; базовая жила игрока и ИИ на месте;
##   B — охрана: три ветеранских отряда (конный + два пеших), патрулируют
##       кольцом, в волны не уходят;
##   C — тревога: чужие встали на захват / ударили по руднику — вся орда идёт
##       к нему; гарнизон деревни при этом остаётся дома;
##   D — рудник умеют захватывать и гоблины (стоя на ничейном).
## Запуск: godot --headless --path . res://qa_goblin_mine/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
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
	print("\n═════ ИТОГ qa_goblin_mine: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Такт вожака: его _process выключен (часы двигает стенд), поэтому очередь
## приказов разбирается здесь же до пустой — как в qa_goblin_tactics
func _tick_ai(ai, sec: float) -> void:
	ai.clock += sec
	ai.tick()
	for _k in range(64):
		if ai._order_queue.is_empty():
			break
		ai._drain_orders()

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _gold_pieces_near(p: Vector3, r: float) -> int:
	var n := 0
	for rn in get_tree().get_nodes_in_group("resource_nodes"):
		var node := rn as ResourceNode
		if node == null or not is_instance_valid(node) or node.resource_type != Constants.RESOURCE_GOLD:
			continue
		if _xz(node.global_position, p) <= r:
			n += 1
	return n

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	var ai = main.goblin_ai
	ai.set_process(false)
	await pframes(4)

	print("\n═════ A. РУДНИК ОРДЫ И БАЗОВАЯ ЖИЛА ═════")
	var mine = GameManager.goblin_mine
	verdict("A1 рудник орды заведён", mine != null and is_instance_valid(mine))
	if mine == null:
		_finish()
		return
	var village: Vector3 = main.goblin_village_center()
	var d_v: float = _xz(mine.global_position, village)
	var want_d: float = _GobCfg.VILLAGE_RADIUS + _GobCfg.MINE_OFFSET
	verdict("A2 стоит в %.0f м от деревни (околица + %.0f)" % [want_d, _GobCfg.MINE_OFFSET],
		absf(d_v - want_d) < 6.0, "%.1f м" % d_v)
	var to_c: float = _xz(mine.global_position, Vector3.ZERO)
	verdict("A3 и ближе к центру карты, чем деревня", to_c < _xz(village, Vector3.ZERO),
		"рудник %.0f, деревня %.0f м до центра" % [to_c, _xz(village, Vector3.ZERO)])
	verdict("A4 с рождения захвачен ордой", int(mine.faction) == Constants.FACTION_GOBLIN
		and mine.is_in_group("goblin_buildings") and not mine.is_in_group("neutral_buildings"))
	var gold0: float = ResourceManager.gathered_total(Constants.FACTION_GOBLIN, Constants.RESOURCE_GOLD)
	await pframes(150)
	var gold1: float = ResourceManager.gathered_total(Constants.FACTION_GOBLIN, Constants.RESOURCE_GOLD)
	verdict("A5 золото капает орде (%.0f за 2.5 с)" % (gold1 - gold0), gold1 > gold0 + 10.0)
	# Базовая жила: по золотому куску у обеих баз
	var pieces_p: int = _gold_pieces_near(main.PLAYER_BASE_ANCHOR, main.BASE_RESOURCE_DIST + 8.0)
	var pieces_e: int = _gold_pieces_near(main.ENEMY_BASE_ANCHOR, main.BASE_RESOURCE_DIST + 8.0)
	verdict("A6 базовая золотая жила игрока на месте", pieces_p > 0, "кусков %d" % pieces_p)
	verdict("A7 базовая золотая жила ИИ на месте", pieces_e > 0, "кусков %d" % pieces_e)
	verdict("A8 ничейные рудники на пути между базами не тронуты",
		get_tree().get_nodes_in_group("neutral_buildings").size() >= 2)

	print("\n═════ B. ОХРАНА ═════")
	verdict("B1 охраны три отряда", ai.mine_guard_sids.size() == 3, "%d" % ai.mine_guard_sids.size())
	var cav := 0
	var inf := 0
	var vets := 0
	var near := 0
	for sid in ai.mine_guard_sids:
		var t: String = GameManager.squad_type(int(sid))
		if t == "goblin_rider": cav += 1
		elif t == "goblin_spearman": inf += 1
		# Ранг — СВОЙСТВО из конфига (спринт 18: vet 3 при более сильной лестнице)
		var want_vet: int = int((_GobCfg.MINE_GUARD[0] as Dictionary).get("vet", 0))
		if GameManager.squad_level(int(sid)) >= want_vet and want_vet > 0:
			vets += 1
		var c: Vector3 = GameManager.squad_centroid(int(sid))
		if _xz(c, mine.global_position) < 25.0:
			near += 1
	verdict("B2 один конный и два пеших", cav == 1 and inf == 2, "конных %d, пеших %d" % [cav, inf])
	verdict("B3 все ветераны (ранг по конфигу MINE_GUARD)", vets == 3, "ветеранов %d" % vets)
	verdict("B4 стоят у рудника", near == 3, "у рудника %d" % near)
	verdict("B5 гарнизон деревни зарегистрирован (%d отряда)" % _GobCfg.GARRISON_SQUADS,
		ai.garrison_sids.size() == _GobCfg.GARRISON_SQUADS, "%d" % ai.garrison_sids.size())
	# Патруль: за 25 с охрана меняет точки, но не уходит далеко
	var g0: Array = []
	for sid in ai.mine_guard_sids:
		g0.append(GameManager.squad_centroid(int(sid)))
	for _i in range(12):
		_tick_ai(ai, 1.0)
		await pframes(60)
	var moved := 0
	var far := 0
	var k := 0
	for sid in ai.mine_guard_sids:
		var c2: Vector3 = GameManager.squad_centroid(int(sid))
		if _xz(c2, g0[k]) > 2.0:
			moved += 1
		if _xz(c2, mine.global_position) > 25.0:
			far += 1
		k += 1
	verdict("B6 охрана патрулирует (сменила место)", moved >= 2, "сдвинулись %d из 3" % moved)
	verdict("B7 и не уходит от рудника", far == 0, "ушло %d" % far)
	verdict("B8 охрана не в полевых отрядах волны", ai._field_squads() == ai.squads.size() \
		- ai.mine_guard_sids.size() - ai.garrison_sids.size(),
		"в поле %d из %d" % [ai._field_squads(), ai.squads.size()])

	print("\n═════ C. ТРЕВОГА ═════")
	# Чужой отряд встаёт на захват — тревога; вся орда идёт к руднику
	var mp: Vector3 = mine.global_position
	var foes: Array = []
	var fsid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(8):
		var f := _spawn("spearman", Constants.FACTION_PLAYER, mp + Vector3(3.0 + float(i % 4) * 0.6, 0.0, float(i / 4) * 0.6))
		f.current_health = f.max_health * 100.0
		f._soa_push_stats()
		f.set_tick(false)
		GameManager.add_to_squad(fsid, f)
		foes.append(f)
	var alarms0: int = int(mine.alarms)
	await pframes(40)
	verdict("C1 чужие на захвате поднимают тревогу рудника", int(mine.alarms) > alarms0,
		"тревог %d" % int(mine.alarms))
	verdict("C1б вожак слышит тревогу", ai.mine_alarm_active(), "до %.0f при часах %.0f" % [ai.mine_alarm_until, ai.clock])
	_tick_ai(ai, 1.0)
	var to_mine := 0
	var field_n := 0
	for s in ai.squads:
		var sq: Dictionary = s
		var sid: int = int(sq["id"])
		if ai._is_special(sid) or String(sq["role"]) == ai.ROLE_HEAL:
			continue
		field_n += 1
		if String(sq["role"]) == ai.ROLE_MINE_ALARM:
			to_mine += 1
	verdict("C2 по тревоге ВСЯ полевая орда получает роль «к руднику»", field_n > 0 and to_mine == field_n,
		"%d из %d" % [to_mine, field_n])
	var home := 0
	for gs in ai.garrison_sids:
		var gsq: Dictionary = {}
		for s in ai.squads:
			if int((s as Dictionary)["id"]) == int(gs):
				gsq = s
		if not gsq.is_empty() and String(gsq["role"]) == ai.ROLE_GARRISON:
			home += 1
	verdict("C3 гарнизон деревни остаётся дома", home == ai.garrison_sids.size(), "%d из %d" % [home, ai.garrison_sids.size()])
	# Доходят ли: центр масс полевых отрядов приближается к руднику
	var before: float = _field_dist(ai, mp)
	for _i in range(15):
		_tick_ai(ai, 1.0)
		await pframes(60)
	var after: float = _field_dist(ai, mp)
	verdict("C4 орда реально идёт к руднику (центр поля приблизился)", after < before - 8.0,
		"было %.0f, стало %.0f м" % [before, after])
	verdict("C5 захват чужими сорван (рудник у орды)", int(mine.faction) == Constants.FACTION_GOBLIN)
	# Удар по руднику — тоже тревога
	# Обидчик — СВЕЖИЙ боец: прежние к этому моменту вырезаны ордой (правило 5)
	var hitter := _spawn("spearman", Constants.FACTION_PLAYER, mp + Vector3(0.0, 0.0, -30.0))
	hitter.set_tick(false)
	mine._alarm_at_ms = -100000
	var alarms1: int = int(mine.alarms)
	mine.take_damage(1.0, hitter)
	verdict("C6 удар по руднику — тревога", int(mine.alarms) > alarms1)
	for f in foes:
		if is_instance_valid(f):
			(f as Unit).take_damage(1e9)
	if is_instance_valid(hitter):
		hitter.take_damage(1e9)
	await pframes(3)

	print("\n═════ D. ГОБЛИНЫ ЗАХВАТЫВАЮТ ═════")
	# Ничейный рудник и отряд орды на нём
	var nm := Mine.new()
	nm.faction = Constants.FACTION_NEUTRAL
	main.world_add(nm)
	var np: Vector3 = Vector3(-1200.0, 0.0, -1200.0)
	nm.global_position = Vector3(np.x, GameManager.get_terrain_height(np.x, np.z), np.z)
	await pframes(2)
	var gsid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_spearman")
	for i in range(6):
		var g := _spawn("goblin_spearman", Constants.FACTION_GOBLIN, np + Vector3(2.0 + float(i) * 0.6, 0.0, 0.0))
		g.set_tick(false)
		GameManager.add_to_squad(gsid, g)
	await pframes(int((Mine.CAPTURE_SEC + 1.5) * 60.0))
	verdict("D1 отряд орды, стоя на ничейном руднике, захватывает его",
		int(nm.faction) == Constants.FACTION_GOBLIN, "владелец %d" % int(nm.faction))
	_finish()

func _field_dist(ai, p: Vector3) -> float:
	var acc := 0.0
	var n := 0
	for s in ai.squads:
		var sq: Dictionary = s
		if ai._is_special(int(sq["id"])) or String(sq["role"]) == ai.ROLE_HEAL:
			continue
		acc += _xz(ai._squad_center(sq), p)
		n += 1
	return acc / float(maxi(n, 1))
