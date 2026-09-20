extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ФИКС «ЗАЛИПАНИЯ» ОРДЫ — АГРО В ОБЗОРЕ, ОТВЕТ НА ОБСТРЕЛ ИЗДАЛЕКА
## (спринт 17, блок 4)
## ═══════════════════════════════════════════════════════════════════════════
##   A — радиус инициативы орды равен её обзору (vision_radius), у людей —
##       прежние AGGRO_RADIUS; поводок орды не короче обзора;
##   B — гоблин-копейщик, увидев врага в обзоре (дальше прежних 10 м, ближе
##       обзора), сам идёт в атаку; тот же враг для копейщика игрока — нет;
##   C — обстрел из-за предела ответной атаки (COUNTER_CHARGE_RANGE): гоблин
##       с полным запасом бежит на стрелка; с малым — отходит к лагерю;
##       у гнолла и тролля свой ответ, общий выключен.
## Запуск: godot --headless --path . res://qa_aggro_fix/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(200.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 200 с")
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
	print("\n═════ ИТОГ qa_aggro_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
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
	u.post_pos = u.global_position
	return u

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
	GameManager.world_bounds_enabled = false
	await pframes(4)
	var p0 := Vector3(-1200.0, 0.0, -1200.0)

	print("\n═════ A. РАДИУС ИНИЦИАТИВЫ ═════")
	var g := _spawn("goblin_spearman", Constants.FACTION_GOBLIN, p0)
	var h := _spawn("spearman", Constants.FACTION_PLAYER, p0 + Vector3(0.0, 0.0, 200.0))
	await pframes(2)
	var vis: float = _UCfg.vision_radius(g.attack_range)
	verdict("A1 у орды радиус агро равен обзору (%.1f м)" % vis, is_equal_approx(g.aggro_radius(), vis),
		"%.1f" % g.aggro_radius())
	verdict("A2 обзор шире прежних AGGRO_RADIUS", vis > Unit.AGGRO_RADIUS, "%.1f против %.1f" % [vis, Unit.AGGRO_RADIUS])
	verdict("A3 у людей радиус прежний (AGGRO_RADIUS)", is_equal_approx(h.aggro_radius(), Unit.AGGRO_RADIUS))
	verdict("A4 поводок орды не короче её обзора", g.aggro_leash() >= g.aggro_radius(),
		"поводок %.1f, обзор %.1f" % [g.aggro_leash(), g.aggro_radius()])
	h.take_damage(1e9)
	await pframes(2)

	print("\n═════ B. ВРАГ В ОБЗОРЕ — АТАКА ═════")
	# Враг между прежним радиусом (10) и обзором: гоблин обязан пойти сам
	var d_far: float = (Unit.AGGRO_RADIUS + vis) * 0.5
	var foe := _spawn("spearman", Constants.FACTION_PLAYER, p0 + Vector3(0.0, 0.0, d_far))
	foe.set_tick(false)
	foe.current_health = foe.max_health * 100.0
	foe._soa_push_stats()
	await pframes(4)
	var got := false
	var start_d: float = _xz(g.global_position, foe.global_position)
	for _i in range(60 * 6):
		await get_tree().physics_frame
		if g.attack_target == foe:
			got = true
			break
	await pframes(90)
	var end_d: float = _xz(g.global_position, foe.global_position)
	verdict("B1 гоблин взял врага в обзоре (%.1f м) целью сам" % d_far, got)
	verdict("B2 и пошёл к нему (дистанция сократилась)", end_d < start_d - 1.0, "%.1f → %.1f м" % [start_d, end_d])
	# Тот же сценарий у копейщика игрока: 10 м — его предел, дальше не срывается
	var hp := _spawn("spearman", Constants.FACTION_PLAYER, p0 + Vector3(60.0, 0.0, 0.0))
	var hfoe := _spawn("goblin_spearman", Constants.FACTION_GOBLIN, p0 + Vector3(60.0, 0.0, d_far))
	hfoe.set_tick(false)
	await pframes(4)
	var hgot := false
	for _i in range(60 * 3):
		await get_tree().physics_frame
		if hp.attack_target == hfoe:
			hgot = true
			break
	verdict("B3 копейщик игрока на той же дистанции с места не срывается", not hgot)
	for u in [g, foe, hp, hfoe]:
		if is_instance_valid(u):
			(u as Unit).take_damage(1e9)
	await pframes(3)

	print("\n═════ C. ОТВЕТ НА ОБСТРЕЛ ИЗДАЛЕКА ═════")
	var d_shot: float = Unit.COUNTER_CHARGE_RANGE + 6.0
	var g2 := _spawn("goblin_spearman", Constants.FACTION_GOBLIN, p0 + Vector3(0.0, 0.0, 100.0))
	var archer := _spawn("archer", Constants.FACTION_PLAYER, p0 + Vector3(0.0, 0.0, 100.0 + d_shot))
	archer.set_tick(false)
	archer.current_health = archer.max_health * 100.0
	archer._soa_push_stats()
	await pframes(4)
	# Гоблин сам врага в обзоре не видит: он ДАЛЬШЕ обзора
	verdict("C0 стрелок стоит за обзором гоблина (%.1f > %.1f)" % [d_shot, vis], d_shot > vis)
	var a0: int = g2.far_fire_answers
	g2.take_damage(2.0, archer)
	await pframes(3)
	verdict("C1 стрела из-за обзора — гоблин отвечает (счётчик ответов)", g2.far_fire_answers > a0,
		"ответов %d" % g2.far_fire_answers)
	verdict("C2 цель — стрелок", g2.attack_target == archer)
	var d0: float = _xz(g2.global_position, archer.global_position)
	await pframes(90)
	var d1: float = _xz(g2.global_position, archer.global_position)
	verdict("C3 гоблин сокращает дистанцию к стрелку", d1 < d0 - 1.0, "%.1f → %.1f м" % [d0, d1])
	# Малый запас — отход к лагерю, а не наскок
	var g3 := _spawn("goblin_spearman", Constants.FACTION_GOBLIN, p0 + Vector3(40.0, 0.0, 100.0))
	var archer2 := _spawn("archer", Constants.FACTION_PLAYER, p0 + Vector3(40.0, 0.0, 100.0 + d_shot))
	archer2.set_tick(false)
	await pframes(3)
	g3.current_health = g3.max_health * (Unit.FAR_FIRE_FLEE_HP - 0.05)
	g3._soa_push_stats()
	var f0: int = g3.far_fire_flees
	g3.take_damage(1.0, archer2)
	await pframes(3)
	var camp: Vector3 = GameManager.goblin_camp_point(g3.global_position)
	verdict("C4 лагерь орды известен (деревня)", camp != Vector3.INF)
	verdict("C5 гоблин с малым запасом ОТХОДИТ к лагерю, а не бежит на стрелка",
		g3.far_fire_flees > f0 and g3.retreating and g3.attack_target == null,
		"отходов %d, retreating=%s" % [g3.far_fire_flees, str(g3.retreating)])
	var d2: float = _xz(g3.global_position, camp)
	await pframes(90)
	var d3: float = _xz(g3.global_position, camp)
	verdict("C6 и реально идёт в сторону лагеря", d3 < d2 - 1.0, "%.0f → %.0f м" % [d2, d3])
	# Человек игрока на дальний обстрел общим путём не отвечает
	var hp2 := _spawn("spearman", Constants.FACTION_PLAYER, p0 + Vector3(80.0, 0.0, 100.0))
	var garcher := _spawn("gnoll", Constants.FACTION_GOBLIN, p0 + Vector3(80.0, 0.0, 100.0 + d_shot))
	garcher.set_tick(false)
	await pframes(3)
	hp2.take_damage(1.0, garcher)
	await pframes(3)
	# ТЗ 19.09.2026-3 (п. 3): на дальний обстрел отвечает и стоящий боец
	# игрока без приказа — идёт на стрелка (отход в лагерь — только у орды)
	verdict("C7 стоящий боец игрока отвечает на дальний обстрел (идёт на стрелка)",
		hp2.far_fire_answers == 1 and hp2.attack_target == garcher,
		"ответов %d, цель %s" % [hp2.far_fire_answers, str(hp2.attack_target)])
	verdict("C8 у гнолла и тролля общий ответ выключен (свой)", not garcher.answers_far_fire()
		and not Building.PRELOAD_SCENES["troll"].instantiate().answers_far_fire())
	_finish()
