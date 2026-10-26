extends Node

## СТЕНД: КОПИЛКА ОПЫТА АРМИИ И РЕЛИКВИЯ-ШТАНДАРТ (ТЗ 10.10.2026, блок 5)
##   A КОПИЛКА   — убийства игрока копят, чужие нет; на POOL_COST заряжается
##   B ВЫДАЧА    — взвод, клик по своему бойцу: отряду +1 уровень, реликвия у
##                 центрального бойца, копилка списана
##   C АУРА      — союзник в R−1 получает атаку/мораль/кулдаун, в R+1 нет;
##                 скорость не меняется
##   D ПРОКАЧКА  — повторная выдача тому же отряду: уровень 2, радиус +5
##   E ВЫПАДЕНИЕ — носитель пал: реликвия на земле, аура снята
##   F ПОДБОР    — красный наступил: реликвия у красного, аура на красных;
##                 гоблин тоже подбирает
##   G СОХРАНЕНИЕ— слепок копилки и реликвий

const _RCfg := preload("res://scripts/relic_config.gd")

const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN

var main: Node = null
var rm: Node = null
var verdicts: Array = []

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 180.0
	wd.one_shot = true
	wd.timeout.connect(func():
		print("  ВЕРДИКТ сторож: НЕ ПРОШЛО — стенд не уложился в 180 с")
		print("  провалов: 1 (сторож)")
		get_tree().quit())
	add_child(wd)
	wd.start()
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 20.0), Vector3(0.0, 0.0, -20.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
				if GameManager.is_water(p.x + d.x, p.z + d.z):
					h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if main.fog != null:
		main.fog.enabled = false
	GameManager.pop_limit_enabled = false
	await frames(3)
	rm = GameManager.relic_mgr()
	var base: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 30.0))
	main._clear_area_of_resources(base, 70.0)
	# Чужие и свои ходячие у площадки — вон (дикие, охрана, рабочие базы)
	for n in get_tree().get_nodes_in_group("all_units"):
		var wu := n as Unit
		if wu == null or wu.is_dead():
			continue
		wu.set_tick(false)
		if wu.global_position.distance_to(base) < 45.0:
			wu.take_damage(1e9, null)
	await pframes(4)
	rm.reset()
	await _run_tests(base)
	_summary()
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		if not bool(v[1]):
			bad += 1
		print("  %-60s %s" % [String(v[0]), "ПРОШЛО" if bool(v[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

## Отряд n бойцов в линию с шагом step (шаг больше радиуса подбора: сосед
## павшего носителя не должен подбирать реликвию сам собой)
func _squad(utype: String, fac: int, pos: Vector3, n: int, step: float = 2.0) -> Array:
	var sid: int = GameManager.new_squad(fac, utype)
	var us: Array = []
	for i in range(n):
		var u: Unit
		match utype:
			"goblin_spearman": u = load("res://scripts/goblin/GoblinSpearman.gd").new()
			_: u = Spearman.new()
		u.faction = fac
		main.world_add(u)
		u.global_position = pos + Vector3(float(i) * step, 0.0, 0.0)
		GameManager.add_to_squad(sid, u)
		us.append(u)
	await pframes(3)
	for u2 in us:
		(u2 as Unit).set_tick(false)
	return [sid, us]

func _wait_until(cond: Callable, cap: int) -> bool:
	for _i in range(cap):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()

func _run_tests(base: Vector3) -> void:
	# ── A. КОПИЛКА ──────────────────────────────────────────────────────────
	print("\n═════ A. КОПИЛКА ═════")
	var sq: Array = await _squad("spearman", F, base, 7)
	var sid: int = sq[0]
	var members: Array = sq[1]
	var foe_sq: Array = await _squad("spearman", R, base + Vector3(0.0, 0.0, 40.0), 1)
	var foe: Unit = foe_sq[1][0]
	for i in range(10):
		GameManager.credit_kill(members[i % members.size()], foe)
	verdict("A1 10 убийств игрока → копилка 10", is_equal_approx(rm.pool, 10.0 * _RCfg.POOL_PER_KILL),
		"копилка %.1f" % rm.pool)
	var p0: float = rm.pool
	GameManager.credit_kill(foe, members[0])
	verdict("A2 убийство красного копилку игрока не трогает", is_equal_approx(rm.pool, p0))
	verdict("A3 до порога не заряжена и не взводится", not rm.charged())
	rm.arm(true)
	verdict("A3б взвод без заряда отклонён", not rm.armed)
	# Копим чужим отрядом-кормильцем: порогами убийств он сам дойдёт до
	# потолка званий, а проверяемому отряду нужен запас для «+1 уровня»
	var feeder: Array = await _squad("spearman", F, base + Vector3(-30.0, 0.0, 20.0), 1)
	GameManager.credit_kills(int(feeder[0]), int(_RCfg.POOL_COST) - 10, foe)
	verdict("A4 на %d — заряжена" % int(_RCfg.POOL_COST), rm.charged(), "копилка %.0f" % rm.pool)
	var lvl0: int = GameManager.squad_level(sid)

	# ── B. ВЫДАЧА ───────────────────────────────────────────────────────────
	print("\n═════ B. ВЫДАЧА ═════")
	rm.arm(true)
	verdict("B1 первый клик взводит выдачу", rm.armed)
	var centre: Vector3 = GameManager._centroid_of(members)
	var expect: Unit = null
	var bd := INF
	for m in members:
		var d: float = Vector2((m as Unit).global_position.x - centre.x,
			(m as Unit).global_position.z - centre.z).length()
		if d < bd:
			bd = d
			expect = m
	rm.click_unit(foe)
	verdict("B2 клик по чужому — выдачи нет, режим держится", rm.armed and rm.relics.is_empty())
	rm.click_unit(members[0])
	verdict("B3 выдача сняла взвод", not rm.armed)
	var lvl_cap: int = preload("res://scripts/unit_stats_config.gd").max_veteran_level("spearman")
	verdict("B4 отряду +1 уровень", GameManager.squad_level(sid) == mini(lvl0 + 1, lvl_cap),
		"%d → %d" % [lvl0, GameManager.squad_level(sid)])
	verdict("B5 одна реликвия уровня 1", rm.relics.size() == 1
		and int(rm.relics[0]["level"]) == 1)
	var carrier: Unit = rm.relics[0]["carrier"] if rm.relics.size() == 1 else null
	verdict("B6 несёт центральный боец", carrier != null and carrier == expect)
	verdict("B7 копилка списана", rm.pool < _RCfg.POOL_COST, "копилка %.0f" % rm.pool)
	var node = rm.relics[0]["node"] if rm.relics.size() == 1 else null
	verdict("B8 флаг реликвии в сцене", node != null and is_instance_valid(node) and node.is_inside_tree())

	# ── C. АУРА ─────────────────────────────────────────────────────────────
	print("\n═════ C. АУРА ═════")
	var r1: float = _RCfg.aura_radius(1)
	var cp: Vector3 = carrier.global_position
	var near_sq: Array = await _squad("spearman", F, cp + Vector3(0.0, 0.0, r1 - 1.0), 1)
	var far_sq: Array = await _squad("spearman", F, cp + Vector3(0.0, 0.0, r1 + 1.0), 1)
	var near: Unit = near_sq[1][0]
	var far: Unit = far_sq[1][0]
	var near_atk: float = near.vet_attack
	var near_cd: float = near.attack_cooldown
	var near_mor: float = near.morale
	var near_spd: float = near._effective_speed()
	var near_ms: float = near.move_speed
	var far_atk: float = far.vet_attack
	await _wait_until(func(): return rm.aura_level_on(near) > 0, 90)
	verdict("C1 союзник в %.0f м: атака +%.1f" % [r1 - 1.0, _RCfg.aura_attack(1)],
		is_equal_approx(near.vet_attack - near_atk, _RCfg.aura_attack(1)),
		"Δ %.2f" % (near.vet_attack - near_atk))
	verdict("C2 мораль +%.0f" % _RCfg.AURA_MORALE, is_equal_approx(near.morale - near_mor, _RCfg.AURA_MORALE))
	verdict("C3 кулдаун меньше", near.attack_cooldown < near_cd - 0.001,
		"%.3f → %.3f" % [near_cd, near.attack_cooldown])
	verdict("C4 скорость не изменилась", is_equal_approx(near._effective_speed(), near_spd)
		and is_equal_approx(near.move_speed, near_ms))
	verdict("C5 союзник в %.0f м ауры не получил" % (r1 + 1.0),
		is_equal_approx(far.vet_attack, far_atk) and rm.aura_level_on(far) == 0)
	verdict("C6 носитель сам под аурой", rm.aura_level_on(carrier) == 1)

	# ── D. ПРОКАЧКА ─────────────────────────────────────────────────────────
	print("\n═════ D. ПРОКАЧКА ═════")
	var lvl1: int = GameManager.squad_level(sid)
	rm.add_xp(_RCfg.POOL_COST)
	rm.arm(true)
	rm.click_unit(members[1])
	verdict("D1 та же реликвия, уровень 2", rm.relics.size() == 1 and int(rm.relics[0]["level"]) == 2)
	verdict("D2 отряду ещё +1 уровень", GameManager.squad_level(sid) == mini(lvl1 + 1, lvl_cap))
	verdict("D3 радиус %.0f м" % _RCfg.aura_radius(2), is_equal_approx(_RCfg.aura_radius(2), r1 + 5.0))
	await _wait_until(func(): return rm.aura_level_on(far) == 2 and rm.aura_level_on(near) == 2, 90)
	verdict("D4 союзник в %.0f м теперь под аурой ур. 2" % (r1 + 1.0), rm.aura_level_on(far) == 2)
	verdict("D5 атака у ближнего +%.1f (не сложилась с ур. 1)" % _RCfg.aura_attack(2),
		is_equal_approx(near.vet_attack - near_atk, _RCfg.aura_attack(2)),
		"Δ %.2f" % (near.vet_attack - near_atk))
	# Вторая реликвия другому отряду
	var sq2: Array = await _squad("spearman", F, base + Vector3(-30.0, 0.0, -20.0), 3)
	rm.add_xp(_RCfg.POOL_COST)
	rm.arm(true)
	rm.click_unit(sq2[1][0])
	verdict("D6 другой отряд — вторая реликвия", rm.relics.size() == 2)

	# ── E. ВЫПАДЕНИЕ ────────────────────────────────────────────────────────
	print("\n═════ E. ВЫПАДЕНИЕ ═════")
	var rel: Dictionary = rm.relics[0]
	var drop_at: Vector3 = carrier.global_position
	carrier.take_damage(1e9, null)
	await _wait_until(func(): return rm.drops >= 1, 60)
	verdict("E1 носитель пал — реликвия на земле", rel["carrier"] == null and rm.drops >= 1,
		"носитель %s, выпадений %d, мёртв %s" % [str(rel["carrier"]), rm.drops,
		str(carrier.is_dead()) if is_instance_valid(carrier) else "освобождён"])
	verdict("E2 лежит там, где пал носитель",
		Vector2(rel["pos"].x - drop_at.x, rel["pos"].z - drop_at.z).length() < 0.6)
	await _wait_until(func(): return rm.aura_level_on(near) == 0, 90)
	verdict("E3 аура с союзника снята, атака вернулась", rm.aura_level_on(near) == 0
		and is_equal_approx(near.vet_attack, near_atk) and is_equal_approx(near.attack_cooldown, near_cd)
		and is_equal_approx(near.morale, near_mor))
	verdict("E4 уровень реликвии сохранён", int(rel["level"]) == 2)

	# ── F. ПОДБОР ───────────────────────────────────────────────────────────
	print("\n═════ F. ПОДБОР ═════")
	# Красный наступает на реликвию, его товарищ стоит в 10 м
	var red_sq: Array = await _squad("spearman", R, drop_at + Vector3(0.6, 0.0, 0.0), 1)
	var red_mate_sq: Array = await _squad("spearman", R, drop_at + Vector3(-10.0, 0.0, 0.0), 1)
	var red: Unit = red_sq[1][0]
	var red_mate: Unit = red_mate_sq[1][0]
	var rm_atk: float = red_mate.vet_attack
	await _wait_until(func(): return rel["carrier"] == red, 60)
	verdict("F1 красный подобрал реликвию", rel["carrier"] == red and rm.pickups >= 1)
	await _wait_until(func(): return rm.aura_level_on(red_mate) > 0, 90)
	verdict("F2 аура работает на красных", rm.aura_level_on(red_mate) == 2
		and is_equal_approx(red_mate.vet_attack - rm_atk, _RCfg.aura_attack(2)))
	verdict("F3 игрок рядом ауры не получает", rm.aura_level_on(near) == 0)
	# Красный пал — гоблин подбирает
	var at2: Vector3 = red.global_position
	red.take_damage(1e9, null)
	red_mate.take_damage(1e9, null)
	var drops_was: int = rm.drops
	await _wait_until(func(): return rm.drops > drops_was, 60)
	var gob_sq: Array = await _squad("goblin_spearman", G, at2 + Vector3(0.5, 0.0, 0.0), 1)
	var gob: Unit = gob_sq[1][0]
	await _wait_until(func(): return rel["carrier"] == gob, 60)
	verdict("F4 гоблин подобрал реликвию", rel["carrier"] == gob)
	await _wait_until(func(): return rm.aura_level_on(gob) > 0, 90)
	verdict("F5 аура на гоблинах (носитель сам)", rm.aura_level_on(gob) == 2)

	# ── G. СОХРАНЕНИЕ ───────────────────────────────────────────────────────
	print("\n═════ G. СОХРАНЕНИЕ ═════")
	rm.add_xp(123.0)
	var snap: Dictionary = rm.capture()
	verdict("G1 слепок: копилка и две реликвии", is_equal_approx(float(snap["pool"]), rm.pool)
		and (snap["list"] as Array).size() == 2)
	var pool_was: float = rm.pool
	var gsid: int = gob.squad_id
	rm.restore(snap, {gsid: gsid, int(sq2[0]): int(sq2[0])})
	await pframes(2)
	var ok_g: bool = is_equal_approx(rm.pool, pool_was) and rm.relics.size() == 2
	var lv: Array = []
	for r in rm.relics:
		lv.append(int(r["level"]))
		ok_g = ok_g and r["carrier"] != null
	verdict("G2 восстановление: копилка, уровни, носители", ok_g, "уровни %s" % str(lv))

	# ── H. НАСТОЯЩИЙ ВВОД: КНОПКА → ЛКМ ПО ОТРЯДУ, ПКМ ОТМЕНЯЕТ ────────────────
	print("\n═════ H. НАСТОЯЩИЙ ВВОД ═════")
	await _h_input(base + Vector3(0.0, 0.0, -25.0))

func _mouse(btn: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	get_tree().root.push_input(e, true)

func _h_input(at: Vector3) -> void:
	var hq: Array = await _squad("spearman", F, at, 5)
	var hsid: int = hq[0]
	var cam = main.selection_manager.camera
	main.set_process(false)
	cam.jump_to(at + Vector3(4.0, 0.0, 0.0))
	await frames(3)
	cam.set_process(false)
	var n0: int = rm.relics.size()
	rm.add_xp(_RCfg.POOL_COST)
	rm.arm(true)
	var spt: Vector2 = cam.unproject_position((hq[1][2] as Unit).global_position)
	# ТЗ 24.10.2026 (второе письмо): ПКМ — выдать, ЛКМ/Esc — отмена
	_mouse(MOUSE_BUTTON_LEFT, true, spt)
	_mouse(MOUSE_BUTTON_LEFT, false, spt)
	await frames(2)
	verdict("H1 ЛКМ снимает взвод, выдачи нет", not rm.armed and rm.relics.size() == n0)
	rm.arm(true)
	spt = cam.unproject_position((hq[1][2] as Unit).global_position)
	_mouse(MOUSE_BUTTON_RIGHT, true, spt)
	_mouse(MOUSE_BUTTON_RIGHT, false, spt)
	await frames(2)
	verdict("H2 ПКМ по своему отряду вручает реликвию", rm.relics.size() == n0 + 1
		and rm.relic_of_squad(hsid) != null and not rm.armed,
		"экран %s, реликвий %d → %d" % [str(spt), n0, rm.relics.size()])
	rm.arm(true)
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	get_tree().root.push_input(ev, true)
	await frames(2)
	verdict("H3 Esc снимает взвод", not rm.armed)
	main.set_process(true)
	cam.set_process(true)
