extends Node

## QA п.2 — БАЛЛИСТИКА СТРЕЛ

const _Arrow := preload("res://scripts/Arrow.gd")

var main: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await _t21()
	await _t22()
	await _t23()
	await _t24()
	print("\n=== ARROW DONE ===")
	get_tree().quit()

func _mk(from_pos: Vector3, aim: Vector3, arc: float, dmg: float, shooter: Node3D) -> Node3D:
	var a: Node3D = _Arrow.new()
	a.set("_start_pos", from_pos)
	a.set("_end_pos",   aim)
	a.set("_dist",      from_pos.distance_to(aim))
	a.set("_speed",     9.0)
	a.set("_arc_factor", arc)
	a.set("damage",     dmg)
	a.set("faction",    Constants.FACTION_PLAYER)
	if shooter != null:
		a.set("shooter", shooter)
	main.add_child(a)
	a.global_position = from_pos
	return a

func _mat_of(a: Node3D) -> ShaderMaterial:
	var mi := a.get_node_or_null("ArrowSprite") as MeshInstance3D
	if mi == null:
		return null
	return (mi.mesh as QuadMesh).material as ShaderMaterial

# ── 2.1 наклон по вектору скорости + сверка с uniform axis каждый кадр ────────
func _t21() -> void:
	print("\n===== 2.1 НАКЛОН ПО СКОРОСТИ =====")
	var a := _mk(Vector3(0, 1.2, 0), Vector3(12, 0.8, 0), 0.3, 10.0, null)
	await get_tree().process_frame
	var mat := _mat_of(a)
	var quad := (a.get_node("ArrowSprite") as MeshInstance3D).mesh as QuadMesh
	print("квад: длина=%.3f м, толщина=%.3f м" % [quad.size.x, quad.size.y])

	for s in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var t: float = s
		var d: Vector3 = a.call("_velocity_dir", t)
		print("  t=%.2f  ось=(%+.3f, %+.3f, %+.3f)  наклон=%+6.2f град" %
			[t, d.x, d.y, d.z, rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))])
	var d0: Vector3 = a.call("_velocity_dir", 0.0)
	var d5: Vector3 = a.call("_velocity_dir", 0.5)
	var d1: Vector3 = a.call("_velocity_dir", 1.0)
	print("взлёт y=%+.4f (>0 ждём) | вершина y=%+.6f (~0 ждём) | падение y=%+.4f (<0 ждём)"
		% [d0.y, d5.y, d1.y])
	# В вершине вклад ДУГИ строго ноль; остаточный y — это перепад высот
	# старт(1.2) → цель(0.8), делённый на дальность
	var expected_apex: float = (0.8 - 1.2) / Vector3(12, 0.8, 0).distance_to(Vector3(0, 1.2, 0))
	print("вершина: ожидаемый y (перепад высот/дальность) = %+.6f, факт %+.6f" % [expected_apex, d5.y])
	var ok_shape: bool = d0.y > 0.05 and absf(d5.y - expected_apex) < 1e-4 and d1.y < -0.05
	print("ВЕРДИКТ формы траектории: %s" % ("PASS" if ok_shape else "FAIL"))

	# Покадровая сверка uniform axis == _velocity_dir(_progress)
	var frames := 0
	var mism := 0
	var maxerr := 0.0
	var checked := 0
	var log_pts: Array = []
	while frames < 3000:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(a):
			break
		if bool(a.get("_spent")):
			break
		var p: float = a.get("_progress")
		var expect: Vector3 = a.call("_velocity_dir", p)
		var got: Vector3 = mat.get_shader_parameter("axis")
		var err: float = (got - expect).length()
		maxerr = maxf(maxerr, err)
		checked += 1
		if err > 1e-5:
			mism += 1
		if checked <= 3 or absf(p - 0.5) < 0.03 or p > 0.97:
			log_pts.append("p=%.3f axis.y=%+.4f" % [p, got.y])
	print("кадров полёта: %d, сверено кадров: %d, расхождений axis vs _velocity_dir: %d, max откл = %.9f"
		% [frames, checked, mism, maxerr])
	print("  контрольные точки: %s" % str(log_pts))
	print("ВЕРДИКТ покадровой сверки: %s" % ("PASS" if mism == 0 and checked > 5 else "FAIL"))
	if is_instance_valid(a):
		a.queue_free()
	await get_tree().process_frame

# ── 2.2 втыкание остриём вниз на разных дальностях ───────────────────────────
func _t22() -> void:
	print("\n===== 2.2 ВТЫКАНИЕ ОСТРИЁМ =====")
	var cases: Array = [
		[5.0, 0.3], [12.0, 0.3], [25.0, 0.3],
		[5.0, 0.05], [12.0, 0.05], [25.0, 0.05],
	]
	var all_ok := true
	for c in cases:
		var dist: float = c[0]
		var arc: float  = c[1]
		var a := _mk(Vector3(0, 1.2, 0), Vector3(dist, 0.8, 0), arc, 5.0, null)
		var mat := _mat_of(a)
		var quad := (a.get_node("ArrowSprite") as MeshInstance3D).mesh as QuadMesh
		var half: float = quad.size.x * 0.5
		var guard := 0
		while guard < 4000 and is_instance_valid(a) and not bool(a.get("_spent")):
			await get_tree().process_frame
			guard += 1
		if not is_instance_valid(a):
			print("  дальность %5.1f м, arc=%.2f — стрела исчезла до втыкания! FAIL" % [dist, arc])
			all_ok = false
			continue
		var axis: Vector3 = mat.get_shader_parameter("axis")
		var tip: Vector3  = a.global_position + axis * half
		var tail: Vector3 = a.global_position - axis * half
		var ok: bool = tip.y < 0.0 and tail.y > 0.0
		all_ok = all_ok and ok
		var exposed: float = tail.y / maxf(tail.y - tip.y, 0.0001)
		print("  дальн=%5.1f м arc=%.2f | ось.y=%+.3f | остриё y=%+.4f | оперение y=%+.4f | над землёй %.0f%% | %s%s"
			% [dist, arc, axis.y, tip.y, tail.y, exposed * 100.0,
			   "OK" if ok else "FAIL",
			   "  <- сработала STUCK_MIN_DOWN" if absf(axis.y + 0.35) < 0.02 else ""])
		print("      _process выкл: %s, Area3D снята: %s, кадров полёта: %d"
			% [str(not a.is_processing()), str(a.get("_area") == null), guard])
		a.queue_free()
		await get_tree().process_frame
	print("ВЕРДИКТ 2.2: %s" % ("PASS" if all_ok else "FAIL"))

# ── 2.3 урон ТОЛЬКО при касании ──────────────────────────────────────────────
func _t23() -> void:
	print("\n===== 2.3 УРОН ТОЛЬКО ПРИ КАСАНИИ =====")
	var res := await _shoot_scenario(false)
	var fire_f: int = res.get("fire_frame", -1)
	var hit_f: int  = res.get("hit_frame", -1)
	print("кадр появления стрелы: %d, кадр падения HP жертвы: %d, зазор: %d кадров (~%.0f мс)"
		% [fire_f, hit_f, hit_f - fire_f, float(hit_f - fire_f) * 1000.0 / 60.0])
	print("HP жертвы: было %.1f, стало %.1f (урон %.1f)"
		% [res.get("hp0", 0.0), res.get("hp1", 0.0), float(res.get("hp0", 0.0)) - float(res.get("hp1", 0.0))])
	print("HP в кадр выстрела: %.1f (должно быть = исходному, т.е. анимация урона не наносит)"
		% res.get("hp_at_fire", -1.0))
	var ok: bool = hit_f > fire_f + 3 and float(res.get("hp_at_fire", -1.0)) == float(res.get("hp0", 0.0))
	print("ВЕРДИКТ 2.3: %s" % ("PASS" if ok else "FAIL"))

# ── 2.4 стрелок погиб в полёте ───────────────────────────────────────────────
func _t24() -> void:
	print("\n===== 2.4 СТРЕЛОК ПОГИБ В ПОЛЁТЕ =====")
	var res := await _shoot_scenario(true)
	var hit_f: int = res.get("hit_frame", -1)
	print("лучник удалён на кадре %d, попадание на кадре %d" % [res.get("kill_frame", -1), hit_f])
	print("HP жертвы: было %.1f, стало %.1f" % [res.get("hp0", 0.0), res.get("hp1", 0.0)])
	var ok: bool = hit_f > 0 and float(res.get("hp1", 999.0)) < float(res.get("hp0", 0.0))
	print("ВЕРДИКТ 2.4: %s  (ошибки 'previously freed' ищи выше в stderr)" % ("PASS" if ok else "FAIL"))
	await _t24_root_cause()

## Почему защита в Arrow.gd не сработала: в Godot 4 Variant, содержащий
## ОСВОБОЖДЁННЫЙ объект, сравнивается с null как РАВНЫЙ (get_validated_object()
## возвращает nullptr). Значит `shooter != null` = false, и левая часть
## условия короткозамыкает всю проверку.
func _t24_root_cause() -> void:
	print("\n----- 2.4 разбор причины -----")
	var n := Node3D.new()
	main.add_child(n)
	await get_tree().process_frame
	var ref: Node3D = n
	n.free()
	print("после free():  ref != null  -> %s" % str(ref != null))
	print("               ref == null  -> %s" % str(ref == null))
	print("               is_instance_valid(ref) -> %s" % str(is_instance_valid(ref)))
	print("условие Arrow.gd:113 `shooter != null and not is_instance_valid(shooter)` -> %s"
		% str(ref != null and not is_instance_valid(ref)))
	print("правильное условие `not is_instance_valid(shooter)` -> %s" % str(not is_instance_valid(ref)))

## Общий сценарий: лучник стреляет в жертву. kill_shooter — убить стрелка
## сразу после появления стрелы.
func _shoot_scenario(kill_shooter: bool) -> Dictionary:
	var ArchS := load("res://scenes/units/Archer.tscn") as PackedScene
	var SpearS := load("res://scenes/units/Spearman.tscn") as PackedScene
	var arch: Unit = ArchS.instantiate()
	arch.faction = Constants.FACTION_PLAYER
	main.add_child(arch)
	arch.global_position = Vector3(-40, 0, -40)
	var vic: Unit = SpearS.instantiate()
	vic.faction = Constants.FACTION_ENEMY
	main.add_child(vic)
	vic.global_position = Vector3(-40, 0, -46)
	await get_tree().process_frame
	vic.armor = 0.0
	vic.defense = 0.0
	vic.max_health = 500.0
	vic.current_health = 500.0
	# Жертва не двигается и не отвечает — нужен чистый замер
	vic.state = Unit.State.IDLE
	arch.command_attack(vic, true)

	var hp0: float = vic.current_health
	var fire_frame := -1
	var hit_frame  := -1
	var kill_frame := -1
	var hp_at_fire := -1.0
	var arrow_seen: Node = null
	for f in range(1200):
		await get_tree().process_frame
		if fire_frame < 0:
			for n in main.get_children():
				if n is Arrow and not bool(n.get("_spent")):
					arrow_seen = n
					fire_frame = f
					hp_at_fire = vic.current_health
					break
			if fire_frame >= 0 and kill_shooter:
				arch.queue_free()
				kill_frame = f
		if fire_frame >= 0 and vic.current_health < hp0:
			hit_frame = f
			break
	var hp1: float = vic.current_health
	if is_instance_valid(vic):
		vic.queue_free()
	if is_instance_valid(arch):
		arch.queue_free()
	await get_tree().process_frame
	return {
		"fire_frame": fire_frame, "hit_frame": hit_frame, "kill_frame": kill_frame,
		"hp0": hp0, "hp1": hp1, "hp_at_fire": hp_at_fire,
	}
