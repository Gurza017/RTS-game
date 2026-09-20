extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_scout_raid — РАЗВЕДКА ВСАДНИКОВ ПОЛНЫМИ ОТРЯДАМИ (ТЗ 19.09.2026, 3.4)
## ═══════════════════════════════════════════════════════════════════════════
##   A — в фазе рейдов выходит 1-3 ПОЛНЫХ конных отряда (уставной размер),
##       все вне волны, у каждого своя дорожка, цели разведены веером.
##   B — у базы игрока: налёт на рабочего (harass), через SCOUT_HARASS_SEC —
##       отход (run, режим отхода), через SCOUT_RUN_SEC — снова орбита (out).
##   C — одинокий отряд лучников без пехоты — добыча; с пехотой рядом — нет.
##   D — потери — домой; передышка вдвое короче прежней (SCOUT_SORTIE_SEC ≤ 22).
## Деревня выключена, армию ставит стенд, часы вожака двигает стенд.
## Запуск: godot --headless --path . res://qa_scout_raid/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _OptCfg := preload("res://scripts/perf_config.gd")

var main = null
var ai = null
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_scout_raid: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func think(steps: int = 1, sec: float = _GobCfg.THINK_INTERVAL) -> void:
	for _s in range(steps):
		ai.clock += sec
		ai.tick()
		var guard := 0
		while ai._order_at < ai._order_queue.size() and guard < 64:
			ai._drain_orders()
			guard += 1
		await pframes(int(sec * 60.0))

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _sq_by_id(sid: int) -> Dictionary:
	for s in ai.squads:
		if int((s as Dictionary)["id"]) == sid:
			return s
	return {}

func _teleport_squad(sid: int, at: Vector3) -> void:
	var members: Array = GameManager.squad_members(sid)
	for i in range(members.size()):
		var u := members[i] as Unit
		var p := at + Vector3(float(i % 8) * 0.8, 0.0, float(i / 8) * 0.8)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position

func _scout_state(sid: int) -> String:
	var st: Variant = ai.scouts.get(sid)
	return String((st as Dictionary)["state"]) if st != null else ""

func _retreating(sid: int) -> bool:
	for m in GameManager.squad_members(sid):
		if (m as Unit).retreating:
			return true
	return false

func _run() -> void:
	_OptCfg.goblin_village = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for k in ["gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	ai = main.goblin_ai
	ai.set_process(false)
	var village := Vector3(120.0, 0.0, -70.0)
	ai.setup(main, GameManager.land_target(village))
	await pframes(4)
	var sids: Array = []
	for i in range(4):
		sids.append(main.spawn_goblin_squad("goblin_spearman", 20, ai.village + Vector3(float(i) * 12.0 - 18.0, 0.0, 14.0)))
	await pframes(4)
	await think(1)
	ai.clock = _GobCfg.PEACE_SEC
	await think(1)
	# Орда у пустого центра → фаза рейдов
	for k in range(sids.size()):
		_teleport_squad(int(sids[k]), Vector3(float(k) * 7.0 - 14.0, 0.0, 6.0))
	await pframes(2)
	await think(3)
	verdict("A0 фаза рейдов (harass)", String(ai.phase) == ai.PHASE_HARASS, String(ai.phase))

	print("\n═════ A. ВЫХОД РАЗВЕДКИ: ПОЛНЫЕ ОТРЯДЫ ВЕЕРОМ ═════")
	await think(2)
	var n_sc: int = ai.scouts.size()
	verdict("A1 разведка вышла: 1-3 отряда (пул ≤ %d)" % _GobCfg.SCOUT_MAX_SQUADS, n_sc >= 1 and n_sc <= _GobCfg.SCOUT_MAX_SQUADS,
		"отрядов %d, вылазок %d" % [n_sc, ai.scout_sorties])
	verdict("A1б передышка дома вдвое короче прежних 45 с (SCOUT_SORTIE_SEC ≤ 22.5)", _GobCfg.SCOUT_SORTIE_SEC <= 22.5,
		"%.0f" % _GobCfg.SCOUT_SORTIE_SEC)
	var full_ok := true
	var special_ok := true
	var lanes: Dictionary = {}
	var targets: Array = []
	for sid in ai.scouts:
		var st: Dictionary = ai.scouts[sid]
		if GameManager.squad_type(int(sid)) != "goblin_rider" \
				or GameManager.squad_members(int(sid)).size() != _GobCfg.scout_units():
			full_ok = false
		if not ai._is_special(int(sid)):
			special_ok = false
		lanes[int(st["lane"])] = true
		var sq: Dictionary = _sq_by_id(int(sid))
		targets.append(sq.get("target", Vector3.ZERO))
	verdict("A2 каждый разведотряд — ПОЛНЫЙ конный отряд (%d всадников)" % _GobCfg.scout_units(), full_ok)
	verdict("A3 разведотряды вне волны (особая роль)", special_ok)
	verdict("A4 у каждого своя дорожка (lane)", lanes.size() == n_sc, "дорожек %d" % lanes.size())
	var fan_ok := true
	var min_d := INF
	for i in range(targets.size()):
		for j in range(i + 1, targets.size()):
			var d: float = _xz(targets[i], targets[j])
			min_d = minf(min_d, d)
			if d < 20.0:
				fan_ok = false
	verdict("A5 цели разведотрядов разведены веером (≥ 20 м между точками) или отряд один",
		n_sc == 1 or fan_ok, "ближайшая пара точек %.1f м" % (min_d if min_d != INF else 0.0))
	verdict("A6 совместимость: scout_sid — первый разведотряд, scout_state — его состояние",
		ai.scout_sid > 0 and ai.scouts.has(ai.scout_sid) and String(ai.scout_state) == _scout_state(ai.scout_sid))

	print("\n═════ B. У БАЗЫ ИГРОКА: НАЛЁТ И ОТХОД ═════")
	var cp := Vector3(-40.0, 0.0, 30.0)
	main._clear_area_of_resources(cp, 50.0)
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(3)
	var workers: Array = []
	for i in range(4):
		var w := _spawn("worker", Constants.FACTION_PLAYER, cp + Vector3(8.0 + float(i) * 1.2, 0.0, 6.0))
		w.set_tick(false)
		w.current_health = w.max_health * 100.0
		w._soa_push_stats()
		workers.append(w)
	var first: int = ai.scout_sid
	_teleport_squad(first, cp + Vector3(-22.0, 0.0, 0.0))
	await pframes(2)
	await think(1)
	verdict("B1 разведчик увидел базу игрока", ai.known_bases.has(Constants.FACTION_PLAYER))
	verdict("B2 рабочий у базы — добыча: налёт (harass) на рабочего", _scout_state(first) == "harass"
		and ai.scout_harasses >= 1, "состояние %s" % _scout_state(first))
	var sq1: Dictionary = _sq_by_id(first)
	var tgt_ok: bool = false
	for w in workers:
		if _xz(sq1.get("target", Vector3.ZERO), w.global_position) < 2.0:
			tgt_ok = true
	verdict("B3 цель налёта — рабочий", tgt_ok)
	ai.clock += _GobCfg.SCOUT_HARASS_SEC
	await think(1)
	verdict("B4 после налёта — ОТХОД (run) в режиме отхода, не домой", _scout_state(first) == "run" and _retreating(first),
		"состояние %s, отход=%s" % [_scout_state(first), str(_retreating(first))])
	ai.clock += _GobCfg.SCOUT_RUN_SEC
	# Рабочих убираем подальше: иначе новый налёт тем же тактом
	for w in workers:
		(w as Unit).global_position = cp + Vector3(120.0, 0.0, 120.0)
		(w as Unit).sync_row()
	await think(1)
	verdict("B5 после отхода — снова орбита (out), отход снят", _scout_state(first) == "out" and not _retreating(first),
		"состояние %s" % _scout_state(first))
	var alive_w := 0
	for w in workers:
		if is_instance_valid(w) and not (w as Unit).is_dead():
			alive_w += 1
	verdict("B6 hit-and-run: разведка не остаётся выбивать базу (рабочие бессмертны, стоят)", alive_w == 4)

	print("\n═════ C. ОДИНОКИЕ ЛУЧНИКИ — ДОБЫЧА, ПРИКРЫТЫЕ — НЕТ ═════")
	var c_now: Vector3 = ai._squad_center(_sq_by_id(first))
	var arch_sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var archers: Array = []
	for i in range(10):
		var a := _spawn("archer", Constants.FACTION_PLAYER, c_now + Vector3(18.0 + float(i % 5) * 0.7, 0.0, float(i / 5) * 0.7))
		a.set_tick(false)
		a.current_health = a.max_health * 100.0
		a._soa_push_stats()
		GameManager.add_to_squad(arch_sid, a)
		archers.append(a)
	await pframes(2)
	var prey: Node3D = ai._scout_prey(c_now)
	verdict("C1 одинокий отряд лучников (без пехоты рядом) — добыча разведки",
		prey != null and prey is Unit and (prey as Unit).squad_id == arch_sid, str(prey))
	var sp_sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var guards: Array = []
	for i in range(10):
		var g := _spawn("spearman", Constants.FACTION_PLAYER, c_now + Vector3(18.0 + float(i % 5) * 0.7, 0.0, 6.0 + float(i / 5) * 0.7))
		g.set_tick(false)
		GameManager.add_to_squad(sp_sid, g)
		guards.append(g)
	await pframes(2)
	var prey2: Node3D = ai._scout_prey(c_now)
	verdict("C2 с пехотой в %.0f м лучники добычей не считаются" % _GobCfg.SCOUT_LONE_R,
		prey2 == null or not (prey2 is Unit) or (prey2 as Unit).squad_id != arch_sid, str(prey2))
	for g in guards:
		(g as Unit).take_damage(1e12)
	for a in archers:
		(a as Unit).take_damage(1e12)
	await pframes(4)

	print("\n═════ D. ПОТЕРИ — ДОМОЙ ═════")
	var men: Array = GameManager.squad_members(first)
	var kill_n: int = int(ceil(float(men.size()) * (1.0 - _GobCfg.RAID_RETREAT_HP)) + 1)
	for i in range(mini(kill_n, men.size())):
		(men[i] as Unit).take_damage(1e12)
	await pframes(4)
	await think(1)
	verdict("D1 отряд, потерявший больше %.0f %% состава, уходит домой" % ((1.0 - _GobCfg.RAID_RETREAT_HP) * 100.0),
		_scout_state(first) == "home" and _retreating(first), "состояние %s" % _scout_state(first))
	_finish()
