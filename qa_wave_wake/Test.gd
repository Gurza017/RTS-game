extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_wave_wake — ПРОБУЖДЕНИЕ РЕЗЕРВОВ ДОЗАМИ (ТЗ 19.09.2026, блок 3.3)
## ═══════════════════════════════════════════════════════════════════════════
##   A — резерв орды за лагерем: штурм лагеря будит ПЕРВУЮ ВОЛНУ
##       (RESERVE_WAVE_SQUADS отрядов), остальные спят; прошли
##       RESERVE_WAVE_GAP_SEC тревоги — просыпается следующая волна; ушедшие
##       в бой отряды получили приказ атаки; отряд, по которому ударили,
##       просыпается вне очереди.
##   B — охрана крепости ИИ: то же с HOME_GUARD_WAVE_SQUADS /
##       HOME_GUARD_WAVE_GAP_SEC.
## Часы волн — секунды тревоги (wave_clock), стенд их двигает сам.
## Запуск: godot --headless --path . res://qa_wave_wake/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const F := Constants.FACTION_PLAYER

var main = null
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

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_wave_wake: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _immortal(men: Array) -> void:
	for u in men:
		var un := u as Unit
		un.max_health = 1e9
		un.current_health = 1e9
		un._soa_push_stats()

func _kill(men: Array) -> void:
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

## Сколько проснувшихся отрядов получили цель (атака)
func _attacking(node) -> int:
	var n := 0
	for s in node.squads:
		var sid: int = int(s["sid"])
		if node.is_asleep(sid):
			continue
		for m in GameManager.squad_members(sid):
			var u := m as Unit
			if u != null and (u.attack_target != null or u.state == Unit.State.ATTACKING):
				n += 1
				break
	return n

func _wait_alarm(node, secs: float) -> bool:
	for f in range(int(secs * 60.0)):
		await get_tree().physics_frame
		if node.alarm:
			return true
	return false

func _case(node, wave_n: int, gap: float, foe_at: Vector3, tag: String, label: String) -> void:
	print("\n═════ %s. %s ═════" % [tag, label])
	var total: int = (node.squads as Array).size()
	verdict("%s0 до тревоги спят все (%d)" % [tag, total], node.asleep_count() == total and not node.alarm,
		"спит %d из %d" % [node.asleep_count(), total])
	var force: Array = []
	for k in range(2):
		var sq: Array = _squad("spearman", F, foe_at + Vector3(float(k) * 10.0 - 5.0, 0.0, 0.0), 24, 6, 0.7)
		force += sq[1]
	_immortal(force)
	if node.get("castle") != null:
		for u in force:
			(u as Unit).command_attack(node.castle, true, false, true)
	await pframes(6)
	var woke: bool = await _wait_alarm(node, 20.0)
	await pframes(30)
	var awake1: int = total - node.asleep_count()
	verdict("%s1 тревога будит ПЕРВУЮ ВОЛНУ: проснулось %d (волна %d), остальные спят" % [tag, awake1, wave_n],
		woke and awake1 == mini(wave_n, total) and node.waves == 1,
		"тревога %s, проснулось %d из %d, волн %d" % [str(woke), awake1, total, node.waves])
	verdict("%s2 проснувшиеся пошли в атаку (цель есть)" % tag, _attacking(node) >= 1,
		"с целью %d" % _attacking(node))
	# Секунды тревоги ещё не набежали — вторая волна не идёт
	await pframes(60 * 4)
	var awake_mid: int = total - node.asleep_count()
	verdict("%s3 до истечения %d с тревоги новых пробуждений нет" % [tag, int(gap)], awake_mid == awake1 and node.waves == 1,
		"проснулось %d, волн %d" % [awake_mid, node.waves])
	# Промотать часы волны: следующая волна на следующем такте
	node.wave_clock = gap
	await pframes(90)
	var awake2: int = total - node.asleep_count()
	verdict("%s4 по истечении срока — вторая волна (+%d, всего %d)" % [tag, mini(wave_n, total - awake1), mini(2 * wave_n, total)],
		awake2 == mini(awake1 + wave_n, total) and node.waves == 2,
		"проснулось %d из %d, волн %d" % [awake2, total, node.waves])
	# Уснувших не осталось, если 2 волны ≥ всего; иначе — удар по спящему
	# отряду будит его вне очереди
	if awake2 < total:
		var sleeper_sid: int = 0
		for s in node.squads:
			if node.is_asleep(int(s["sid"])):
				sleeper_sid = int(s["sid"])
				break
		var victim = null
		for m in GameManager.squad_members(sleeper_sid):
			victim = m
			break
		var hitter: Unit = null
		for fu in force:
			if fu != null and is_instance_valid(fu) and not (fu as Unit).is_dead():
				hitter = fu
				break
		if victim != null:
			(victim as Unit).take_damage(5.0, hitter)
		await pframes(90)
		verdict("%s5 удар по спящему отряду будит его вне очереди" % tag,
			sleeper_sid > 0 and not node.is_asleep(sleeper_sid), "отряд %d спит=%s" % [sleeper_sid, str(node.is_asleep(sleeper_sid))])
	_kill(force)
	await pframes(60 * 3)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.pop_limit_enabled = false
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await pframes(6)
	var res = main.get("goblin_reserve")
	var guard = main.get("enemy_guard")
	verdict("0 резерв орды и охрана крепости на карте", res != null and guard != null)
	if res == null or guard == null:
		_finish()
		return
	var v: Vector3 = res.village
	var at_r: Vector3 = GameManager.land_target(v + Vector3(0.0, 0.0, _GobCfg.RESERVE_WAKE_RADIUS - 10.0))
	await _case(res, _GobCfg.RESERVE_WAVE_SQUADS, _GobCfg.RESERVE_WAVE_GAP_SEC, at_r, "A", "РЕЗЕРВ ОРДЫ")
	var cp: Vector3 = guard._castle_pos()
	var at_g: Vector3 = GameManager.land_target(cp + Vector3(0.0, 0.0, _AICfg.HOME_GUARD_ZONE - 6.0))
	await _case(guard, _AICfg.HOME_GUARD_WAVE_SQUADS, _AICfg.HOME_GUARD_WAVE_GAP_SEC, at_g, "B", "ОХРАНА КРЕПОСТИ ИИ")
	_finish()
