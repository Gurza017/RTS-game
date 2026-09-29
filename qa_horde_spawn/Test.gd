extends Node

## ═══════════════════════════════════════════════════════════════════════════
## РАСТЯЖКА СПАВНА ОРДЫ (ТЗ 29.09.2026, второе письмо, п. 2)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба по логу партии 29.09 16:06: на t=3848 повторный набег (шесть отрядов
## по 100, туши, конница) родил 637 бойцов в одном кадре — 9 FPS.
## Стенд запускает тот же состав через GoblinRaids.launch ДВАЖДЫ: с растяжкой
## (perf_config.horde_spawn_stagger) и без, и меряет стену кадра запуска и
## пик рождений за физкадр. Плюс: все бойцы дошли, опоздавшие получили то же,
## что старшие (приказ, награды).
## Запуск: godot --headless --path . res://qa_horde_spawn/Test.tscn

const _Opt := preload("res://scripts/perf_config.gd")
var main = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_horde_spawn: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _men(sids: Array) -> int:
	var n := 0
	for sid in sids:
		var raw: Variant = GameManager.squads.get(int(sid))
		if raw != null:
			n += ((raw as Dictionary)["members"] as Array).size()
	return n

func _kill(sids: Array) -> void:
	for sid in sids:
		var raw: Variant = GameManager.squads.get(int(sid))
		if raw == null:
			continue
		for m in ((raw as Dictionary)["members"] as Array).duplicate():
			if is_instance_valid(m) and not (m as Unit).is_dead():
				(m as Unit).take_damage(1.0e12)

func _launch(stagger: bool) -> Dictionary:
	_Opt.horde_spawn_stagger = stagger
	var gai = main.goblin_ai
	var comp: Dictionary = {"goblin_spearman": 6, "big_goblin": 2, "goblin_rider": 3}
	var target: Vector3 = main.PLAYER_BASE_ANCHOR
	await get_tree().physics_frame
	var peak0: int = int(main.horde_spawn_peak)
	main.horde_spawn_peak = 0
	var t0: int = Time.get_ticks_usec()
	var r: Dictionary = gai.raids.launch(comp, float(gai.clock), target, false)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var first: int = _men(r["sids"])
	var frames := 0
	while main.horde_spawn_pending() > 0 and frames < 600:
		await get_tree().physics_frame
		frames += 1
	await pframes(3)
	var out := {"ms": ms, "first": first, "total": _men(r["sids"]), "frames": frames,
		"peak": int(main.horde_spawn_peak), "sids": r["sids"], "raid": r}
	print("    растяжка=%s: кадр запуска %.1f мс, сразу %d бойцов, всего %d, дорождение %d физкадров, пик за кадр %d" % [
		str(stagger), ms, first, out["total"], frames, out["peak"]])
	main.horde_spawn_peak = maxi(peak0, main.horde_spawn_peak)
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
	var budget: int = _Opt.horde_spawn_budget
	var off: Dictionary = await _launch(false)
	_kill(off["sids"])
	await pframes(10)
	var on: Dictionary = await _launch(true)
	verdict("A1 состав набега тот же с растяжкой и без (%d / %d)" % [on["total"], off["total"]],
		on["total"] == off["total"] and on["total"] > 500)
	# Бюджет кадра плюс по четыре «головных» на каждый отряд набега: отряд
	# обязан существовать в кадр запуска (Main.spawn_goblin_squad)
	var cap: int = budget + 4 * (on["sids"] as Array).size()
	verdict("A2 пик рождений за физкадр в пределах бюджета (%d ≤ %d; без растяжки %d)" % [on["peak"], cap, off["peak"]],
		on["peak"] <= cap)
	verdict("A3 кадр запуска дешевле хотя бы втрое (%.1f против %.1f мс)" % [on["ms"], off["ms"]],
		on["ms"] * 3.0 <= off["ms"])
	verdict("A4 весь набег дорождается быстрее секунды (%d физкадров)" % on["frames"], on["frames"] <= 60)
	var r: Dictionary = on["raid"]
	verdict("A5 штат набега (peak) — полный состав, а не рождённые в первый кадр (%d, всего %d)" % [int(r["peak"]), on["total"]],
		int(r["peak"]) >= on["total"])
	# Опоздавшие: приказ, отданный до дорождения, доходит и до них
	_kill(on["sids"])
	await pframes(10)
	_Opt.horde_spawn_stagger = true
	var vc: Vector3 = main.goblin_village_center()
	var sid: int = main.spawn_goblin_squad("goblin_spearman", 100, vc + Vector3(0, 0, 25), true)
	var sid2: int = main.spawn_goblin_squad("goblin_spearman", 100, vc + Vector3(0, 0, 40), true)
	var goal: Vector3 = GameManager.land_target(vc + Vector3(30.0, 0.0, 40.0))
	for m in GameManager.squads[sid2]["members"]:
		(m as Unit).command_move(goal)
	var early: int = (GameManager.squads[sid2]["members"] as Array).size()
	var f := 0
	while main.horde_spawn_pending() > 0 and f < 600:
		await get_tree().physics_frame
		f += 1
	await pframes(2)
	var late_ok := 0
	var late_n := 0
	var ms2: Array = GameManager.squads[sid2]["members"]
	for i in range(early, ms2.size()):
		var u := ms2[i] as Unit
		late_n += 1
		if u.state == Unit.State.MOVING and Vector2(u.move_target.x - goal.x, u.move_target.z - goal.z).length() < 14.0:
			late_ok += 1
	verdict("A6 опоздавшие получили приказ старших (%d из %d идут к точке)" % [late_ok, late_n],
		late_n > 0 and late_ok == late_n)
	_kill([sid, sid2])
	_finish()
