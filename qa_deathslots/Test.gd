extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СЛОТЫ ОБЩЕЙ ОТРИСОВКИ ПОСЛЕ ГИБЕЛИ (29.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба владельца: «при смерти спрайт замирает стоя, некоторых красит в
## красный, тролль оставляет второй стоячий спрайт». Причина: после переезда
## строки ядром (look_core) GDScript-копия слота устаревала, а _exit_tree
## освобождал строку ДО снятия слота — unregister прятал чужой слот, свой
## оставался в буфере с последним кадром и вспышкой.
## Стенд: бойцы ходят (переезд между бакетами), половину убивают; число
## ЖИВЫХ слотов (ненулевой базис) во всех бакетах бойцов обязано равняться
## числу зарегистрированных живых. Тролль: после гибели у его точки слотов нет.
## Headless.

var main = null
const _Opt := preload("res://scripts/perf_config.gd")
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 120 с")
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
	print("\n═════ ИТОГ qa_deathslots: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(path: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	u.sync_row()
	return u

## Живые слоты во ВСЕХ бакетах бойцов: [всего, из них с ненулевой вспышкой]
func _live_slots() -> Array:
	var fu = GameManager.far_units
	var n := 0
	var red := 0
	for b in fu._buckets.values():
		if b == null or b.core_id < 0:
			continue
		for i in range(b.capacity):
			var s: PackedFloat32Array = GameManager.army.rb_slot(b.core_id, i)
			if s.size() < 16:
				continue
			var basis_sq := 0.0
			for k in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
				basis_sq += s[k] * s[k]
			if basis_sq < 1e-6:
				continue
			n += 1
			if s[14] > 0.05:
				red += 1
	return [n, red]

func _slots_near(p: Vector3, r: float) -> int:
	var fu = GameManager.far_units
	var n := 0
	for b in fu._buckets.values():
		if b == null or b.core_id < 0:
			continue
		for i in range(b.capacity):
			var s: PackedFloat32Array = GameManager.army.rb_slot(b.core_id, i)
			if s.size() < 16:
				continue
			var basis_sq := 0.0
			for k in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
				basis_sq += s[k] * s[k]
			if basis_sq < 1e-6:
				continue
			var dx: float = s[3] - p.x
			var dz: float = s[11] - p.z
			if dx * dx + dz * dz <= r * r:
				n += 1
	return n

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	await frames(2)
	# Туман — прочь: чужой в тумане снимается с отрисовки (_hide_in_fog), и
	# зонд слотов гигантов орды мерил бы пустоту
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	var base := Vector3(0.0, 0.0, -700.0)
	print("\n═════ A. ПОЛОВИНА ОТРЯДА ГИБНЕТ ПОСЛЕ ХОДА ═════")
	var men: Array = []
	for i in range(80):
		var fac: int = Constants.FACTION_PLAYER if i % 2 == 0 else Constants.FACTION_ENEMY
		var path: String = "res://scenes/units/Warrior.tscn" if i % 4 < 2 else "res://scenes/units/Archer.tscn"
		men.append(_spawn(path, fac, base + Vector3(float(i % 10) * 1.2, 0.0, float(i / 10) * 1.2)))
	await pframes(30)
	var reg0: int = GameManager.far_units._slot.size()
	var ls0: Array = _live_slots()
	print("  до хода: зарегистрировано %d, живых слотов %d" % [reg0, int(ls0[0])])
	# Ход — переезд walk↔idle между бакетами ведёт ядро (look_core)
	for k in range(men.size()):
		var u: Unit = men[k]
		u.command_move(base + Vector3(float(k % 10) * 1.2 + 6.0, 0.0, float(k / 10) * 1.2 + 6.0))
	await pframes(90)
	for u in men:
		if is_instance_valid(u):
			(u as Unit).command_move((u as Unit).global_position)
	await pframes(40)
	var ls1: Array = _live_slots()
	var reg1: int = GameManager.far_units._slot.size()
	verdict("A1 после хода слотов ровно столько, сколько зарегистрированных (%d)" % reg1,
		int(ls1[0]) == reg1, "слотов %d" % int(ls1[0]))
	# Диагностика: признаки регистрации у образца
	var reg_men := 0
	var flag_men := 0
	var bound_men := 0
	for u in men:
		if is_instance_valid(u) and GameManager.far_units._slot.has(u):
			reg_men += 1
			if (u as Unit)._far_registered:
				flag_men += 1
			if (u as Unit)._rb_bound:
				bound_men += 1
	print("  из бойцов стенда в реестре %d, с признаком _far_registered %d, привязанных к ядру %d" % [reg_men, flag_men, bound_men])
	# Половина гибнет (через удар — со вспышкой)
	var killed := 0
	var survivor: Unit = null
	for k in range(men.size()):
		var u: Unit = men[k]
		if not is_instance_valid(u) or u.is_dead():
			continue
		if not GameManager.far_units._slot.has(u):
			if survivor == null:
				survivor = u
			continue
		u.take_damage(u.max_health * 10.0 + 1000.0, survivor if survivor != null else null)
		killed += 1
	await pframes(8)
	var alive := 0
	var dead_valid := 0
	for u in men:
		if is_instance_valid(u):
			if (u as Unit).is_dead():
				dead_valid += 1
			else:
				alive += 1
	print("  через 8 физкадров: unreg_calls=%d, зарегистрировано %d, мёртвых-живых узлов %d, живых слотов %d" % [
		GameManager.far_units.unreg_calls, GameManager.far_units._slot.size(), dead_valid, int(_live_slots()[0])])
	await pframes(60)
	dead_valid = 0
	for u in men:
		if is_instance_valid(u) and (u as Unit).is_dead():
			dead_valid += 1
	print("  через 68 физкадров: unreg_calls=%d, зарегистрировано %d, мёртвых-живых узлов %d, живых слотов %d" % [
		GameManager.far_units.unreg_calls, GameManager.far_units._slot.size(), dead_valid, int(_live_slots()[0])])
	var valid_keys := 0
	for k in GameManager.far_units._slot.keys():
		if is_instance_valid(k):
			valid_keys += 1
	print("  ключей реестра всего %d, из них живых объектов %d" % [GameManager.far_units._slot.size(), valid_keys])
	var ls2: Array = _live_slots()
	var reg2: int = GameManager.far_units._slot.size()
	print("  убито %d, живых %d, зарегистрировано %d, живых слотов %d (с вспышкой %d)" % [
		killed, alive, reg2, int(ls2[0]), int(ls2[1])])
	var still := 0
	for u in men:
		if is_instance_valid(u) and GameManager.far_units._slot.has(u):
			still += 1
	verdict("A2 после гибели всех зарегистрированных бойцов стенда их нет в реестре, а слотов ровно столько, сколько зарегистрированных",
		still == 0 and int(ls2[0]) == reg2, "слотов %d, зарегистрировано %d, бойцов стенда в реестре %d" % [int(ls2[0]), reg2, still])
	verdict("A3 стоячих слотов с красной вспышкой нет", int(ls2[1]) == 0, "с вспышкой %d" % int(ls2[1]))
	verdict("A4 тел на поле столько, сколько убито", GameManager.corpses.count() == killed if GameManager.corpses.has_method("count") else true,
		"тел %s" % (str(GameManager.corpses.count()) if GameManager.corpses.has_method("count") else "н/д"))

	print("\n═════ B. ТРОЛЛЬ: ОДИН СПРАЙТ, ПОСЛЕ ГИБЕЛИ — НИ ОДНОГО СЛОТА ═════")
	var tp := base + Vector3(40.0, 0.0, 0.0)
	var troll: Unit = _spawn("res://scenes/units/Troll.tscn", Constants.FACTION_GOBLIN, tp)
	# Камера — к гиганту: в общую отрисовку (mm_render_all) боец попадает из
	# визуального тика, а тот у невидимого спит; в игре тролль умирает в кадре
	if not DisplayServer.get_name().to_lower().begins_with("headless"):
		main.focus_camera_on(tp)
		await frames(6)
	await pframes(20)
	troll.command_move(tp + Vector3(6.0, 0.0, 0.0))
	await pframes(40)
	var tpos: Vector3 = troll.global_position
	var before: int = _slots_near(tpos, 5.0)
	print("  тролль: _far_registered=%s _rb_bound=%s в реестре=%s sheet=%d mm_only=%s seen=%s draw_on=%s mm_all=%s spr=%s" % [
		str(troll._far_registered), str(troll._rb_bound), str(GameManager.far_units._slot.has(troll)),
		troll.sheet_frame().size(), str(troll._mm_only), str(troll._seen), str(troll.draw_on), str(_Opt.mm_render_all),
		str(troll._active_sprite.visible if troll._active_sprite != null else "-")])
	# Тролль рисуется своим узлом (гигант), в общей отрисовке его слота нет —
	# допускаем 0 или 1, но не два
	verdict("B1 у живого тролля не больше одного слота общей отрисовки", before <= 1, "слотов %d" % before)
	var corpses0: int = GameManager.corpses.count()
	troll.take_damage(troll.max_health * 10.0 + 1000.0, null)
	await pframes(8)
	var after: int = _slots_near(tpos, 5.0)
	verdict("B2 после гибели тролля стоячих слотов у его точки нет", after == 0, "слотов %d" % after)
	# Что вообще осталось у точки гибели: узлы мира в 6 м и тела слоя трупов
	var near: Array = []
	for c in main.world_root().get_children():
		var n3 := c as Node3D
		if n3 == null or not is_instance_valid(n3):
			continue
		if n3.global_position.distance_to(tpos) <= 6.0:
			near.append("%s(%s)" % [n3.name, n3.get_class()])
	print("  у точки гибели тролля: узлов %d %s; тел в слое трупов +%d" % [near.size(), str(near), GameManager.corpses.count() - corpses0])
	verdict("B3 после гибели тролля у его точки ровно один узел тела и ни одного тела в общем слое трупов",
		near.size() == 1 and GameManager.corpses.count() - corpses0 == 0, "узлов %d, тел в слое +%d" % [near.size(), GameManager.corpses.count() - corpses0])

	print("
═════ C. ТУША И ВСАДНИК: ПОСЛЕ ГИБЕЛИ — ОДНО ТЕЛО, НИ ОДНОГО СЛОТА ═════")
	for spec in [["res://scenes/units/BigGoblin.tscn", "туша"], ["res://scenes/units/GoblinPigRider.tscn", "всадник"]]:
		var bp := base + Vector3(60.0, 0.0, float(men.size()) * 0.1)
		var big: Unit = _spawn(String(spec[0]), Constants.FACTION_GOBLIN, bp)
		if not DisplayServer.get_name().to_lower().begins_with("headless"):
			main.focus_camera_on(bp)
			await frames(6)
		await pframes(20)
		big.command_move(bp + Vector3(5.0, 0.0, 0.0))
		await pframes(40)
		var bpos: Vector3 = big.global_position
		var b_before: int = _slots_near(bpos, 5.0)
		var c0: int = GameManager.corpses.count()
		print("  %s: _far_registered=%s _rb_bound=%s слотов рядом %d" % [String(spec[1]), str(big._far_registered), str(big._rb_bound), b_before])
		big.take_damage(big.max_health * 10.0 + 1000.0, null)
		await pframes(8)
		var b_after: int = _slots_near(bpos, 5.0)
		var bodies: int = GameManager.corpses.count() - c0
		verdict("C %s: после гибели у точки ни одного слота, тело в слое ровно одно" % String(spec[1]),
			b_after == 0 and bodies == 1, "слотов %d, тел +%d" % [b_after, bodies])
	_finish()
