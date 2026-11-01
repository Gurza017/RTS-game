extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tz1031g — МАРШ ВОЛНЫ КРАСНЫХ ПРИВАЛАМИ (ТЗ 31.10.2026, ai_wave_stages)
## ═══════════════════════════════════════════════════════════════════════════
##   A ПРИВАЛЫ — поход через реку даёт выход, подступ к броду и выход за брод;
##          план волны переносится на привал целиком (взаимные места те же);
##          пока не собрались — стоим; собрались и простояли — следующий;
##          враг ближе CONTACT_R — привалы сняты.
##   B ЖИВОЙ ТАКТ — EnemyAI._command_squads с волной в атаке ставит её на
##          привал; без ручки (B0) — сразу к цели.
## Запуск: godot --headless --path . res://qa_tz1031g/Test.tscn [-- only=ab]

const F := Constants.FACTION_PLAYER
const FE := Constants.FACTION_ENEMY
const _Opt := preload("res://scripts/perf_config.gd")
const _Spawn := preload("res://scripts/spawn_config.gd")

var main = null
var ai = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only: String = "ab"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
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
	print("\n═════ ИТОГ qa_tz1031g: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	var p: Vector3 = GameManager.land_target(at)
	u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Отряд ИИ: запись реестра GameManager + запись EnemyAI
func _red_squad(kind: String, at: Vector3, n: int) -> Dictionary:
	var sid: int = GameManager.new_squad(FE, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, FE, at + Vector3(float(i % 5) * 0.7, 0, float(i / 5) * 0.7))
		u.set_tick(false)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return {"sid": sid, "members": men, "type": kind, "role": ai.ROLE_FIELD, "target": at,
		"issued": false, "flank_side": 0, "flank_close": false, "peak": 0}

func _move_to(sq: Dictionary, p: Vector3) -> void:
	var c: Vector3 = ai._squad_centroid(sq["members"])
	for m in sq["members"]:
		var u := m as Unit
		var q: Vector3 = u.global_position - c + p
		u.global_position = Vector3(q.x, GameManager.get_terrain_height(q.x, q.z), q.z)
		u.sync_row()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	ai = main.enemy_ai
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd",
			"raid_manager", "lair_director"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	for n2 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n2) and n2 is Unit:
			(n2 as Unit).take_damage(1e12)
	await pframes(10)
	if "a" in _only: await _block_a()
	if "b" in _only: await _block_b()
	_finish()

func _plan_reset(plan: Array, to: Vector3) -> void:
	for i in range(plan.size()):
		plan[i][1] = to + Vector3(0, 0, -8.0 + 8.0 * float(i))

# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. ПРИВАЛЫ ═════")
	var m = ai.march
	m.reset()
	# Вдали от полосы брода по Z: оба конца в полосе — дороги через брод нет
	var from := Vector3(70.0, 0.0, 70.0)
	var to := Vector3(-140.0, 0.0, 70.0)
	m.launch(from, to)
	print("    привалы: ", m.legs)
	verdict("A1 поход через реку — %d привала (выход, подступ, за бродом)" % m.legs.size(),
		m.active and m.legs.size() >= 2)
	var crossed := false
	for p in m.legs:
		if (p as Vector3).x < 0.0:
			crossed = true
	verdict("A2 последний привал — за бродом", crossed and (m.legs[m.legs.size() - 1] as Vector3).x < 0.0)
	# План из трёх отрядов в линию поперёк курса
	var sqs: Array = []
	var plan: Array = []
	for i in range(3):
		var sq: Dictionary = _red_squad("spearman", from + Vector3(0, 0, -8.0 + 8.0 * float(i)), 10)
		sqs.append(sq)
		plan.append([sq, to + Vector3(0, 0, -8.0 + 8.0 * float(i)), "spearman"])
	var gaps0: float = ((plan[2][1] as Vector3) - (plan[0][1] as Vector3)).length()
	m.stage(plan, to, from)
	var hp: Vector3 = m.halt_point()
	var gaps1: float = ((plan[2][1] as Vector3) - (plan[0][1] as Vector3)).length()
	var mid_d: float = Vector2((plan[1][1] as Vector3).x - hp.x, (plan[1][1] as Vector3).z - hp.z).length()
	verdict("A3 план перенесён на привал целиком (центр в %.1f м, разнос %.1f → %.1f м)" % [mid_d, gaps0, gaps1],
		mid_d < 2.0 and absf(gaps1 - gaps0) < 2.0)
	var leg0: int = m.leg
	_plan_reset(plan, to)
	m.stage(plan, to, from)
	verdict("A4 не собрались — стоим на привале %d" % (m.leg + 1), m.leg == leg0 and m.active)
	for i in range(3):
		_move_to(sqs[i], plan[i][1])
	_plan_reset(plan, to)
	m.stage(plan, to, from)
	ai.clock += m.RED_HALT_MIN_SEC + 0.5
	_plan_reset(plan, to)
	m.stage(plan, to, from)
	verdict("A5 собрались и простояли — следующий привал (%d → %d, собраний %d)" % [leg0 + 1, m.leg + 1, m.halts_done],
		m.leg == leg0 + 1 and m.halts_done >= 1)
	# Контакт: игрок у центра волны
	var c: Vector3 = ai._squad_centroid(sqs[1]["members"])
	var foe: Unit = _spawn("spearman", F, c + Vector3(10, 0, 0))
	foe.set_tick(false)
	await pframes(6)
	_plan_reset(plan, to)
	m.stage(plan, to, c)
	verdict("A6 враг у волны — привалы сняты (контактов %d)" % m.contacts, not m.active and m.contacts >= 1)
	foe.take_damage(1e12)
	for sq in sqs:
		for u in sq["members"]:
			(u as Unit).take_damage(1e12)
	await pframes(10)
	m.reset()

# ═════════════════════════════════════════════════════════════════════════════
## Живой такт: волна в атаке; куда _command_squads поставил её отряды
func _live(knob: bool) -> Dictionary:
	_Opt.ai_wave_stages = knob
	var castle = ai._find_castle()
	ai.march.reset()
	ai.squads.clear()
	# При прямой загрузке Main крепостей нет: цель штурма — боец игрока у его
	# базы, волна — у базы красных
	var goal: Unit = _spawn("spearman", F, main.PLAYER_BASE_ANCHOR)
	goal.set_tick(false)
	var at: Vector3 = main.ENEMY_BASE_ANCHOR + Vector3(0, 0, 25)
	var made: Array = []
	var kinds := {"spearman": 14, "archer": 5, "warrior": 5}
	var k := 0
	for kind in kinds:
		for i in range(int(kinds[kind])):
			var sq: Dictionary = _red_squad(kind, at + Vector3(float(k % 6) * 6.0 - 15.0, 0, float(k / 6) * 6.0), 5)
			ai.squads.append(sq)
			made.append(sq)
			k += 1
	ai._wave_out = true
	ai._command_squads(castle)
	var base: Vector3 = ai._player_base_pos()
	var near_base := 0
	var field := 0
	for sq in made:
		if String(sq["role"]) == ai.ROLE_GUARD:
			continue
		field += 1
		var t: Vector3 = sq["target"]
		if Vector2(t.x - base.x, t.z - base.z).length() < 40.0:
			near_base += 1
	var res := {"launched": ai.march.launched, "active": ai.march.active, "legs": ai.march.legs.size(),
		"field": field, "near_base": near_base, "act": ai.last_action, "base": base, "at": at,
		"legs_p": ai.march.legs.duplicate()}
	for sq in made:
		for u in sq["members"]:
			(u as Unit).take_damage(1e12)
	goal.take_damage(1e12)
	ai.squads.clear()
	ai._wave_out = false
	ai.march.reset()
	_Opt.ai_wave_stages = true
	await pframes(10)
	return res

func _block_b() -> void:
	print("\n═════ B. ЖИВОЙ ТАКТ ИИ ═════")
	var r: Dictionary = await _live(true)
	print("    ", r)
	verdict("B1 волна в атаке встала на привал (привалов %d, у базы игрока %d из %d)" % [r["legs"], r["near_base"], r["field"]],
		bool(r["launched"]) and bool(r["active"]) and int(r["near_base"]) == 0 and int(r["field"]) > 0)
	var r0: Dictionary = await _live(false)
	print("    ", r0)
	verdict("B0 без ручки — волна сразу к базе игрока (у базы %d из %d)" % [r0["near_base"], r0["field"]],
		not bool(r0["launched"]) and int(r0["near_base"]) > 0)
