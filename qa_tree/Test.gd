extends Node

## СТЕНД: ВЗАИМОДЕЙСТВИЕ С ДЕРЕВЬЯМИ
##
## Разделы:
##   A — позиция рубки: рабочий встаёт вплотную к комлю, а не под кроной
##   B — вибрация и звук: чаще на 30%, дрожь заметна, удары синхронны
##   C — коллизия ствола: юниты обходят дерево, а не идут сквозь него
##   D — пень препятствием не остаётся

var main: Node = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _tree_at(p: Vector3) -> ResourceNode:
	var n := ResourceNode.new()
	n.resource_type = Constants.RESOURCE_WOOD
	n.remaining = 100000.0
	main.world_add(n)
	n.global_position = p
	return n

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	preload("res://scripts/perf_config.gd").sprite_lod = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	await _test_chop_position()
	await _test_shake_and_sound()
	await _test_trunk_collision()
	await _test_stump()

	print("\n=== ИТОГ qa_tree: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ПОЗИЦИЯ РУБКИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_chop_position() -> void:
	print("\n═════ A. ПОЗИЦИЯ РУБКИ ═════")
	var t := _tree_at(Vector3(-150, 0, -150))
	await frames(3)
	var r: float = t.slot_radius()
	print("  радиус комля=%.2f, кольцо рубки=%.2f, дотягивается до %.2f" % [
		ResourceNode.TRUNK_RADIUS, r, t.work_reach()])
	verdict("A1 кольцо рубки считается от ствола, а не от габарита кроны",
		r < 1.1, "радиус кольца %.2f м" % r)
	verdict("A2 но и не внутри самого ствола",
		r > ResourceNode.TRUNK_RADIUS, "кольцо %.2f, ствол %.2f"
			% [r, ResourceNode.TRUNK_RADIUS])

	# Рабочий реально доходит и начинает рубить
	var w: Worker = load("res://scenes/units/Worker.tscn").instantiate()
	w.faction = Constants.FACTION_PLAYER
	get_tree().root.add_child(w)
	w.global_position = Vector3(-156, 0, -150)
	await frames(3)
	w.command_gather(t)
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
		if w.state == Unit.State.GATHERING:
			break
	# Доводка до точной позиции идёт УЖЕ НА РАБОТЕ и намеренно медленная
	# (Worker.SETTLE_SPEED) — даём ей отработать, прежде чем мерить
	var t_settle: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_settle < 1500:
		await get_tree().process_frame
	var d: float = Vector2(w.global_position.x - t.global_position.x,
		w.global_position.z - t.global_position.z).length()
	print("  рабочий встал в %.2f м от центра дерева (состояние %d)" % [d, w.state])
	verdict("A3 рабочий дошёл до рубки", w.state == Unit.State.GATHERING,
		"состояние %d" % w.state)
	verdict("A4 стоит вплотную к стволу, а не рубит воздух",
		d < 1.2, "дистанция %.2f м (прежняя разметка давала 1.65)" % d)
	verdict("A5 и не влез в сам ствол", d > ResourceNode.TRUNK_RADIUS,
		"дистанция %.2f, ствол %.2f" % [d, ResourceNode.TRUNK_RADIUS])

	w.queue_free(); t.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. ВИБРАЦИЯ И ЗВУК
# ═════════════════════════════════════════════════════════════════════════════
func _test_shake_and_sound() -> void:
	print("\n═════ B. ВИБРАЦИЯ И ЗВУК ═════")
	# Темп взмаха задаёт И дрожь, И звук — они синхронны по построению
	var rate: float = Worker.CHOP_SWING_RATE
	print("  темп взмаха=%.2f (было 3.5), амплитуда дрожи=%.3f (было 0.02)" % [
		rate, ResourceNode.SHAKE_AMPLITUDE])
	verdict("B1 темп взмаха поднят примерно на 30%",
		absf(rate / 3.5 - 1.30) < 0.02, "стало %.2f против 3.5 (+%.0f%%)"
			% [rate, (rate / 3.5 - 1.0) * 100.0])
	verdict("B2 амплитуда дрожи заметно выросла",
		ResourceNode.SHAKE_AMPLITUDE >= 0.02 * 2.0,
		"амплитуда %.3f" % ResourceNode.SHAKE_AMPLITUDE)
	verdict("B3 ограничитель звука рубки пропускает возросший темп",
		float(AudioManager.SFX_LIMITS["chop"]["gap"]) < 1.0 / rate,
		"окно %.3f с при интервале удара %.3f с" % [
			float(AudioManager.SFX_LIMITS["chop"]["gap"]), 1.0 / rate])

	# Дрожь реально смещает визуал и сама затухает
	var t := _tree_at(Vector3(-170, 0, -170))
	await frames(3)
	# ── ГДЕ ЖИВЁТ СМЕЩЕНИЕ ОТ УДАРА ─────────────────────────────────────────
	# У дерева СО СПРАЙТОМ собственного узла картинки больше нет: оно рисуется
	# местом в общем MultiMesh растительности (см. VegetationRenderer), и
	# дрожание пишется туда, а не в _visual_root.position — тот остаётся нулём
	# навсегда. Проверка «сдвиг > 0» по старому владельцу числа теперь всегда
	# честно отвечает 0.0000; спрашиваем нынешнего владельца.
	# Тот же случай, что уже был с qa_fix #1 (spr.position.y → _sprite_base_y)
	var vis: Node3D = t.get("_visual_root")
	var slot = t.get("_veg_slot")
	verdict("B4 у дерева есть визуальный корень", vis != null or slot != null)
	if vis == null and slot == null:
		t.queue_free(); return
	var base := Vector2.ZERO
	if slot != null:
		base = Vector2(slot.pos.x, slot.pos.z)
	t.shake()
	var moved := 0.0
	for _i in range(12):
		await get_tree().process_frame
		if slot != null:
			moved = maxf(moved, Vector2(slot.pos.x, slot.pos.z).distance_to(base))
		else:
			moved = maxf(moved, Vector2(vis.position.x, vis.position.z).length())
	print("  максимальный сдвиг при ударе: %.4f м" % moved)
	verdict("B5 удар реально смещает дерево", moved > 0.01,
		"сдвиг %.4f м" % moved)
	# ...и успокаивается само
	var t1: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 3000:
		await get_tree().process_frame
		if t.get("_shake_power") <= 0.0:
			break
	verdict("B6 дрожь затухает сама",
		float(t.get("_shake_power")) <= 0.0,
		"остаточная сила %.3f" % float(t.get("_shake_power")))
	t.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. КОЛЛИЗИЯ СТВОЛА
# ═════════════════════════════════════════════════════════════════════════════
func _test_trunk_collision() -> void:
	print("\n═════ C. ОБХОД СТВОЛОВ ═════")
	var before: int = GameManager.trunk_count()
	var t := _tree_at(Vector3(0, 0, -250))
	await frames(3)
	verdict("C1 дерево встало на учёт препятствий",
		GameManager.trunk_count() == before + 1,
		"было %d, стало %d" % [before, GameManager.trunk_count()])

	# Точка в центре ствола занята, в стороне — свободна
	var hit: Vector3 = GameManager.trunk_block(0.0, -250.0, Unit.TRUNK_CLEARANCE)
	var free: Vector3 = GameManager.trunk_block(0.0, -246.0, Unit.TRUNK_CLEARANCE)
	verdict("C2 центр ствола занят", hit.length() > 0.0)
	verdict("C3 в четырёх метрах свободно", free.length() == 0.0)

	# Юнит идёт СКВОЗЬ дерево: должен обойти и всё равно дойти
	var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u.faction = Constants.FACTION_PLAYER
	get_tree().root.add_child(u)
	u.global_position = Vector3(-6, 0, -250)
	await frames(3)
	u.command_move(Vector3(6, 0, -250))
	var min_d := 1e9
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
		var d: float = Vector2(u.global_position.x, u.global_position.z + 250.0).length()
		min_d = minf(min_d, d)
		if u.state == Unit.State.IDLE:
			break
	print("  ближе всего юнит подошёл к центру ствола на %.2f м, дошёл=%s" % [
		min_d, str(u.state == Unit.State.IDLE)])
	verdict("C4 юнит не прошёл сквозь ствол",
		min_d >= ResourceNode.TRUNK_RADIUS - 0.02,
		"минимальная дистанция %.2f, радиус ствола %.2f"
			% [min_d, ResourceNode.TRUNK_RADIUS])
	verdict("C5 но дерево его не остановило — обошёл и дошёл",
		u.state == Unit.State.IDLE and u.global_position.x > 4.0,
		"x=%.2f, состояние %d" % [u.global_position.x, u.state])

	u.queue_free(); t.queue_free()
	await frames(3)
	verdict("C6 удалённое дерево снято с учёта",
		GameManager.trunk_count() == before,
		"осталось %d, было %d" % [GameManager.trunk_count(), before])

# ═════════════════════════════════════════════════════════════════════════════
# D. ПЕНЬ
# ═════════════════════════════════════════════════════════════════════════════
func _test_stump() -> void:
	print("\n═════ D. ПЕНЬ ═════")
	var before: int = GameManager.trunk_count()
	var t := _tree_at(Vector3(30, 0, -250))
	t.remaining = 5.0
	await frames(3)
	verdict("D1 живое дерево — препятствие",
		GameManager.trunk_count() == before + 1)
	t.extract(999.0)
	await frames(2)
	verdict("D2 срубленное дерево перестаёт быть препятствием",
		GameManager.trunk_count() == before,
		"на учёте %d, ожидали %d" % [GameManager.trunk_count(), before])
	verdict("D3 пень при этом остался на карте",
		is_instance_valid(t) and not t.is_queued_for_deletion())
	verdict("D4 через пень можно пройти",
		GameManager.trunk_block(30.0, -250.0, Unit.TRUNK_CLEARANCE).length() == 0.0)
	t.queue_free()
	await frames(2)
