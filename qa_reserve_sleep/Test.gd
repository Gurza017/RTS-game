extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_reserve_sleep — СОН РЕЗЕРВА ОРДЫ И ОХРАНЫ КРЕПОСТИ ПОСЛЕ БОЯ
## ═══════════════════════════════════════════════════════════════════════════
## Лог партии 19.09.2026: спящих (F_DORMANT) 1045 → 0 к 10-й минуте, и назад
## никто не уснул. Стенд на живой карте партии:
##   A резерв орды: штурм лагеря будит; противник УШЁЛ (отведён и заморожен
##     за радиусом тревоги) — через RESERVE_CALM_SEC на посты и спать;
##   B резерв: противник ПОГИБ — то же;
##   C охрана крепости ИИ: удар по замку будит; противник ушёл — спать;
##   D охрана: противник погиб — спать.
## На провале печатается разбор по отрядам: тревога, чужих в зоне, в бою,
## все ли в покое, расстояние до поста, состояния и цели бойцов.
## Запуск: godot --headless --path . res://qa_reserve_sleep/Test.tscn

const F := Constants.FACTION_PLAYER
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const WAIT_SEC := 150.0
var _only: String = ""

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(a).split("=")
		if kv.size() == 2 and kv[0] == "only":
			_only = kv[1].to_lower()
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 900 с")
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
	print("\n═════ ИТОГ qa_reserve_sleep: прошло %d, провалов: %d ═════" % [_pass, _fail])
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
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int, sp: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(
			at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0,
			at.z + float(i / cols) * sp))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _kill(men: Array) -> void:
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _immortal(men: Array) -> void:
	for u in men:
		var un := u as Unit
		un.max_health = 1e9
		un.current_health = 1e9
		un._soa_push_stats()

## Отвести и заморозить: враг «ушёл» с поля, но жив
func _withdraw(men: Array, to: Vector3) -> void:
	var k := 0
	for u in _alive(men):
		var un := u as Unit
		un.command_move(un.global_position)
		un.set_attack_target(null)
		un.global_position = Vector3(to.x + float(k % 8) * 0.8, GameManager.get_terrain_height(to.x, to.z), to.z + float(k / 8) * 0.8)
		un.sync_row()
		un.post_pos = un.global_position
		un.set_tick(false)
		k += 1

## Разбор, почему отряд не спит
func _explain(node, label: String) -> void:
	print("  — %s: тревога %s, отрядов %d, спит %d" % [label, str(node.alarm), (node.squads as Array).size(), node.asleep_count()])
	var mine: Dictionary = {}
	for s in node.squads:
		mine[int(s["sid"])] = true
	var by_src: Dictionary = {}
	for r in _Opt.cmd_sid_report():
		if mine.has(int(r[1])):
			by_src[String(r[0])] = int(by_src.get(String(r[0]), 0)) + int(r[2])
	print("    приказы отрядам с момента отвода, по источникам: %s" % str(by_src))
	if node.has_method("_foes_at_village"):
		print("    чужих у деревни %d (порог %d)" % [node._foes_at_village(), _GobCfg.RESERVE_WAKE_FOES])
	if node.has_method("_foes_in_zone"):
		print("    чужих в зоне %d (порог %d), замок под ударом %s" % [node._foes_in_zone(), _AICfg.HOME_GUARD_WAKE_FOES, str(node.castle_under_attack())])
	for s in node.squads:
		var sid: int = int(s["sid"])
		var post: Vector3 = s["post"]
		var c: Vector3 = node._centroid(sid)
		var lent: bool = node.get("lent") != null and (node.get("lent") as Dictionary).has(sid)
		var states: Dictionary = {}
		var tgt := 0
		var moving := 0
		var mt_post := 0.0
		var mt_n := 0
		for m in node._members(sid):
			var u := m as Unit
			var k: String = Unit.State.keys()[u.state]
			states[k] = int(states.get(k, 0)) + 1
			var t = u.attack_target
			if t != null and is_instance_valid(t):
				tgt += 1
			if u.moved_recently():
				moving += 1
			if u.state == Unit.State.MOVING:
				mt_post += _xz(u.move_target, post)
				mt_n += 1
		print("    отряд %d: спит %s, взаймы %s, в бою %s, до поста %.1f, цели у %d, реально идут %d, цель хода от поста %.1f, состояния %s" % [
			sid, str(node.is_asleep(sid)), str(lent), str(GameManager.squad_in_combat(sid)),
			_xz(c, post) if c.x != INF else -1.0, tgt, moving,
			mt_post / maxf(float(mt_n), 1.0), str(states)])

func _all_asleep(node) -> bool:
	var lent = node.get("lent")
	for s in node.squads:
		var sid: int = int(s["sid"])
		if lent != null and (lent as Dictionary).has(sid):
			continue
		if not node.is_asleep(sid):
			return false
	return true

func _wait_asleep(node, secs: float) -> float:
	for f in range(int(secs * 60.0)):
		await get_tree().physics_frame
		if f % 30 == 0 and not node.alarm and _all_asleep(node):
			return float(f) / 60.0
	return -1.0

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.pop_limit_enabled = false
	await pframes(6)
	var res = main.get("goblin_reserve")
	var guard = main.get("enemy_guard")
	verdict("A0 резерв орды и охрана крепости на карте", res != null and guard != null)
	if res == null or guard == null:
		_finish()
		return
	if _only == "" or _only.contains("a"):
		await _reserve_case(res, false, "A")
	if _only == "" or _only.contains("b"):
		await _reserve_case(res, true, "B")
	if _only == "" or _only.contains("c"):
		await _guard_case(guard, false, "C")
	if _only == "" or _only.contains("d"):
		await _guard_case(guard, true, "D")
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _reserve_case(res, kill: bool, tag: String) -> void:
	print("\n═════ %s. РЕЗЕРВ ОРДЫ: противник %s ═════" % [tag, "погиб" if kill else "ушёл"])
	verdict("%s1 до штурма резерв спит целиком (%d из %d)" % [tag, res.asleep_count(), (res.squads as Array).size()],
		_all_asleep(res) and not res.alarm)
	var v: Vector3 = res.village
	print("  деревня (%.0f, %.0f), посты: %s" % [v.x, v.z, str((res.squads[0] as Dictionary)["post"])])
	var at: Vector3 = GameManager.land_target(v + Vector3(0.0, 0.0, _GobCfg.RESERVE_WAKE_RADIUS - 10.0))
	var force: Array = []
	var sids: Array = []
	for k in range(2):
		var sq: Array = _squad("spearman", F, at + Vector3(float(k) * 10.0 - 5.0, 0.0, 0.0), 24, 6, 0.7)
		force += sq[1]
		sids.append(sq[0])
	_immortal(force)
	await pframes(6)
	var woke := -1
	for f in range(60 * 20):
		await get_tree().physics_frame
		if res.alarm:
			woke = f
			break
	verdict("%s2 штурм лагеря будит резерв (за %.1f с)" % [tag, float(maxi(woke, 0)) / 60.0], woke >= 0)
	# Бой 12 с, затем противник уходит / гибнет
	await pframes(60 * 12)
	if kill:
		_kill(force)
	else:
		_withdraw(force, GameManager.land_target(v + Vector3(0.0, 0.0, _GobCfg.RESERVE_WAKE_RADIUS + 26.0)))
	await pframes(6)
	_Opt.cmd_reset()
	_Opt.cmd_meter = true
	var t: float = await _wait_asleep(res, WAIT_SEC)
	verdict("%s3 после ухода противника резерв вернулся и уснул (за %.0f с при откате %.0f)" % [tag, t, _GobCfg.RESERVE_CALM_SEC],
		t >= 0.0)
	if t < 0.0:
		_explain(res, "резерв")
	_kill(force)
	await pframes(60 * 2)
	# Резерв должен быть готов к следующему случаю
	if not _all_asleep(res):
		await _wait_asleep(res, 30.0)

func _guard_case(guard, kill: bool, tag: String) -> void:
	print("\n═════ %s. ОХРАНА КРЕПОСТИ ИИ: противник %s ═════" % [tag, "погиб" if kill else "ушёл"])
	verdict("%s1 до штурма охрана спит целиком (%d из %d)" % [tag, guard.asleep_count(), (guard.squads as Array).size()],
		_all_asleep(guard) and not guard.alarm)
	var cp: Vector3 = guard._castle_pos()
	var at: Vector3 = GameManager.land_target(cp + Vector3(0.0, 0.0, _AICfg.HOME_GUARD_ZONE - 6.0))
	var sq: Array = _squad("spearman", F, at, 24, 6, 0.7)
	_immortal(sq[1])
	await pframes(6)
	for u in sq[1]:
		(u as Unit).command_attack(guard.castle, true, false, true)
	var woke := -1
	for f in range(60 * 20):
		await get_tree().physics_frame
		if guard.alarm:
			woke = f
			break
	verdict("%s2 удар по замку будит охрану (за %.1f с)" % [tag, float(maxi(woke, 0)) / 60.0], woke >= 0)
	await pframes(60 * 12)
	if kill:
		_kill(sq[1])
	else:
		_withdraw(sq[1], GameManager.land_target(cp + Vector3(0.0, 0.0, _AICfg.HOME_GUARD_ZONE + 30.0)))
	await pframes(6)
	_Opt.cmd_reset()
	_Opt.cmd_meter = true
	var t: float = await _wait_asleep(guard, WAIT_SEC)
	verdict("%s3 после ухода противника охрана вернулась и уснула (за %.0f с при откате %.0f)" % [tag, t, _AICfg.HOME_GUARD_CALM_SEC],
		t >= 0.0)
	if t < 0.0:
		_explain(guard, "охрана")
	_kill(sq[1])
	await pframes(60 * 2)
	if not _all_asleep(guard):
		await _wait_asleep(guard, 30.0)
