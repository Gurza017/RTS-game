extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЗАВИСШИЕ КОСТИ (спринт 18, пятое письмо)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: кости гноллов (снаряды) зависают в траве и крутятся вечно.
## Причина: события полёта из ядра — один список на оба слоя (стрелы и
## кости), слой стрел забирал и сбрасывал его первым — события костей терялись.
##   A — стрелы и кости в воздухе ОДНОВРЕМЕННО: все полёты кончаются, ни одна
##       кость не остаётся «в полёте» (flight_count = 0, _flight_id = −1 у всех);
##   B — страховка: полёт без события старше MAX_FLIGHT_SEC гасится обходом;
##   C — торчащая кость уходит с поля по своему сроку (BONE_STUCK_LIFETIME).
## Запуск: godot --headless --path . res://qa_bones_fix/Test.tscn

const _Arrow := preload("res://scripts/Arrow.gd")

## Костей в земле: записи ядра (снаряд без узла, этап 3) плюс legacy-узлы
func _stuck_bones() -> int:
	var n := 0
	for r in GameManager.stuck_arrow_records():
		if bool(r["bone"]):
			n += 1
	for a in GameManager._stuck_arrows:
		if is_instance_valid(a) and bool((a as Node3D).get("bone")):
			n += 1
	return n

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
	print("\n═════ ИТОГ qa_bones_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Кости — узлы в пуле GameManager._bone_pool (и живые, и погашенные)
func _bone_nodes_in_flight() -> int:
	var n := 0
	for a in GameManager._bone_pool:
		if is_instance_valid(a) and int(a.get("_flight_id")) >= 0:
			n += 1
	return n

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

	print("\n═════ A. СТРЕЛЫ И КОСТИ В ВОЗДУХЕ РАЗОМ ═════")
	var p0 := Vector3(-1300.0, 0.0, -900.0)
	# Лучники игрока стреляют по бессмертному гоблину; гноллы метают в бессмертного копейщика
	var archers: Array = []
	for i in range(6):
		archers.append(_spawn("archer", Constants.FACTION_PLAYER, p0 + Vector3(float(i) * 0.8, 0.0, 0.0)))
	var gob := _spawn("goblin_spearman", Constants.FACTION_GOBLIN, p0 + Vector3(2.0, 0.0, 14.0))
	gob.set_tick(false)
	gob.current_health = gob.max_health * 1000.0
	gob._soa_push_stats()
	var gnolls: Array = []
	for j in range(4):
		var g := _spawn("gnoll", Constants.FACTION_GOBLIN, p0 + Vector3(40.0 + float(j) * 0.8, 0.0, 0.0))
		gnolls.append(g)
	var sp := _spawn("spearman", Constants.FACTION_PLAYER, p0 + Vector3(42.0, 0.0, 8.0))
	sp.set_tick(false)
	sp.current_health = sp.max_health * 1000.0
	sp._soa_push_stats()
	await pframes(4)
	for a in archers:
		(a as Unit).command_attack(gob, true, false, true)
	for g2 in gnolls:
		(g2 as Unit).command_attack(sp, true, false, true)
	var peak_arrows := 0
	var peak_bones := 0
	var both := 0
	for _i in range(60 * 12):
		await get_tree().physics_frame
		var fa: int = GameManager.arrows_mm.flight_count()
		var fb: int = GameManager.bones_mm.flight_count()
		peak_arrows = maxi(peak_arrows, fa)
		peak_bones = maxi(peak_bones, fb)
		if fa > 0 and fb > 0:
			both += 1
	verdict("A1 в воздухе были и стрелы, и кости, и одновременно (пик %d / %d, кадров вместе %d)" % [peak_arrows, peak_bones, both],
		peak_arrows > 0 and peak_bones > 0 and both > 0)
	# Стоп стрельбе — и ждём, пока всё долетит
	for a2 in archers:
		(a2 as Unit).take_damage(1e9)
	for g3 in gnolls:
		(g3 as Unit).take_damage(1e9)
	await pframes(60 * 6)
	var fa2: int = GameManager.arrows_mm.flight_count()
	var fb2: int = GameManager.bones_mm.flight_count()
	verdict("A2 через 6 с в полёте никого: стрел %d, костей %d" % [fa2, fb2], fa2 == 0 and fb2 == 0)
	verdict("A3 ни одна кость не висит «в полёте» (узлов с flight_id ≥ 0: %d)" % _bone_nodes_in_flight(),
		_bone_nodes_in_flight() == 0)
	verdict("A4 стрелки погибли — их снаряды не зависли (проверка A2/A3 после гибели источников)", fa2 == 0 and fb2 == 0)

	print("\n═════ B. СТРАХОВКА СРОКОМ ПОЛЁТА ═════")
	var layer = GameManager.bones_mm
	var fake := Node3D.new()
	fake.set_script(load("res://qa_bones_fix/FakeArrow.gd"))
	add_child(fake)
	layer.register_flight(999999, fake)
	# Часы обхода — физкадры (игровое время), не стенные
	layer._flight_since[999999] = Engine.get_physics_frames() - int((_Arrow.MAX_FLIGHT_SEC + 1.0) * float(Engine.physics_ticks_per_second))
	var exp0: int = int(layer.flights_expired)
	layer.sweep_flights(_Arrow.MAX_FLIGHT_SEC)
	verdict("B1 полёт старше MAX_FLIGHT_SEC (%.1f с) без события погашен обходом" % _Arrow.MAX_FLIGHT_SEC,
		int(layer.flights_expired) == exp0 + 1 and bool(fake.get("despawned")) and layer.flight_count() == 0)
	verdict("B2 обход зовётся из GameManager раз в секунду", GameManager.get("_flight_sweep_t") != null)

	print("\n═════ C. ТОРЧАЩАЯ КОСТЬ УХОДИТ ПО СРОКУ ═════")
	verdict("C1 срок кости в земле %.1f с, растворение %.1f с" % [_Arrow.BONE_STUCK_LIFETIME, _Arrow.BONE_STUCK_FADE],
		_Arrow.BONE_STUCK_LIFETIME <= 5.0 and _Arrow.BONE_STUCK_FADE < _Arrow.BONE_STUCK_LIFETIME)
	var stuck_bones: int = _stuck_bones()
	await get_tree().create_timer(_Arrow.BONE_STUCK_LIFETIME + 1.0).timeout
	var stuck_after: int = _stuck_bones()
	verdict("C2 кости, лежавшие в земле (%d), через срок сняты (осталось %d)" % [stuck_bones, stuck_after], stuck_after == 0)
	_finish()
