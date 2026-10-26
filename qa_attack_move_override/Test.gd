extends "res://qa_forced_retreat_in_combat/Test.gd"
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПРИКАЗ ОТХОДА ПЕРЕБИВАЕТ ATTACK-MOVE (ТЗ 21.10.2026, письмо 4, п. 3)
## ═══════════════════════════════════════════════════════════════════════════
## Цепочка «Attack-Move [A] → контакт → ПКМ назад»:
##   A — копейщики + лучники: режим [A] снят у всех отрядов, все дошли до
##       точки отхода, по дороге в бой никто не вернулся
##   B — одни лучники: то же
##   C — после прихода новый [A] снова ведёт в бой (режим не «сломан»)
## Общая часть сценария — qa_forced_retreat_in_combat (_retreat_case).
## Запуск: godot --headless --path . res://qa_attack_move_override/Test.tscn [-- only=abc]

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_attack_move_override: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if _only == "abcd":
		_only = "abc"
	if "a" in _only:
		var r: Dictionary = await _retreat_case(Vector3(-80, 0, -10), true, true)
		_judge_am("A", "копейщики + лучники", r)
	if "b" in _only:
		var r2: Dictionary = await _retreat_case(Vector3(-30, 0, -10), false, true)
		_judge_am("B", "одни лучники", r2)
	if "c" in _only:
		await _c_am_again()
	_finish()

func _judge_am(tag: String, what: String, r: Dictionary) -> void:
	print("\n═════ %s. %s: [A] → КОНТАКТ → ПКМ НАЗАД ═════" % [tag, what])
	verdict("%s0 %s: перед приказом отряды были в [A]" % [tag, what],
		int(r.am_before) == int(r.squads), "%d из %d" % [r.am_before, r.squads])
	verdict("%s0б %s: приказ отхода снял [A] со всех отрядов" % [tag, what],
		int(r.am_after) == 0, "осталось %d" % r.am_after)
	_judge(tag, what, r)

func _c_am_again() -> void:
	print("\n═════ C. ПОСЛЕ ОТХОДА НОВЫЙ [A] СНОВА ВЕДЁТ В БОЙ ═════")
	var at := Vector3(-80, 0, 40)
	_clear(at, 60.0)
	await pframes(3)
	var mine: Array = _squad("spearman", at, 24, F)
	var foes: Array = _squad("goblin_spearman", at + Vector3(0, 0, 14), 12, G, 6)
	await pframes(10)
	var sm = main.selection_manager
	sm.select_units(mine)
	sm.order_at_world(at + Vector3(0, 0, -20), false)
	var t := 0
	while t < 900:
		await pframes(10)
		t += 10
		var idle := 0
		for m in _alive(mine):
			if (m as Unit).state == Unit.State.IDLE:
				idle += 1
		if idle == _alive(mine).size():
			break
	sm.select_units(_alive(mine))
	sm.order_at_world(at + Vector3(0, 0, 30), true)
	sm.clear_selection()
	var fight := 0
	t = 0
	while t < 1500:
		await pframes(10)
		t += 10
		fight = 0
		for m in _alive(mine):
			var tg = (m as Unit).attack_target
			if tg != null and is_instance_valid(tg) and tg is Unit and (tg as Unit).faction == G:
				fight += 1
		if fight * 2 >= _alive(mine).size():
			break
	verdict("C1 новый [A] после отхода ведёт отряд в бой", fight * 2 >= _alive(mine).size(),
		"в бою %d из %d за %.1f с" % [fight, _alive(mine).size(), float(t) / 60.0])
	_free(mine)
	_free(foes)
