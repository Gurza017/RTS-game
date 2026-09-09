extends Node

## ЗОНД: приказ игрока в замесе, атака зданий, агро от знаменосца.
## Печатает числа, вердиктов не выносит.

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var sm = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _mk(kind: String, at: Vector3, n: int, fac: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var scene := "res://scenes/units/Spearman.tscn"
	if kind == "warrior": scene = "res://scenes/units/Warrior.tscn"
	if kind == "archer":  scene = "res://scenes/units/Archer.tscn"
	for i in range(n):
		var u: Unit = load(scene).instantiate()
		u.faction = fac
		main.world_add(u)
		var p := at + Vector3(float(i % 6) * 0.6, 0.0, float(i / 6) * 0.6)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		GameManager.fog = null
	await frames(4)

	await _p3_building()
	await _p3_village()
	# await _p2_order()  # часть 2 воспроизвести не удалось, см. отчёт

	print("\n=== PROBE DONE ===")
	get_tree().quit(0)

## ── ЧАСТЬ 3: ДИСТАНЦИЯ ДО ЗДАНИЯ ──────────────────────────────────────────
func _p3_building() -> void:
	print("\n===== ЧАСТЬ 3: АТАКА ЗДАНИЯ =====")
	var hut = load("res://scripts/goblin/GoblinHut.gd").new()
	hut.faction = Constants.FACTION_GOBLIN
	main.world_add(hut)
	hut.global_position = Vector3(0.0, GameManager.get_terrain_height(0.0, 0.0), 0.0)
	await pframes(6)
	print("  хижина: build_size %s, полугабарит коробки %.2f, ring_radius (рисунок) %.2f" % [
		str(hut.build_size), maxf(hut.build_size.x, hut.build_size.z) * 0.5,
		hut.ring_radius()])

	var r: Array = _mk("spearman", Vector3(0.0, 0.0, 18.0), 12, Constants.FACTION_PLAYER)
	var sid: int = int(r[0])
	var men: Array = r[1]
	await pframes(4)
	var u0: Unit = men[0]
	print("  копейщик: attack_range %.2f, _pad_of(хижина) %.2f, reach = %.2f" % [
		u0.attack_range, Unit._pad_of(hut), u0.attack_range + Unit._pad_of(hut)])
	for m in men:
		(m as Unit).command_attack(hut, true, true, true)
	var t0: int = Time.get_ticks_msec()
	var hp0: float = hut.current_health
	while Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	var near := 999.0
	var far := 0.0
	for m in men:
		var u := m as Unit
		if not is_instance_valid(u) or u.is_dead():
			continue
		var d: float = Vector2(u.global_position.x - hut.global_position.x,
			u.global_position.z - hut.global_position.z).length()
		near = minf(near, d)
		far = maxf(far, d)
	print("  через 15 с: ближний в %.2f м от ЦЕНТРА хижины (стена рисунка на %.2f)" % [
		near, hut.ring_radius()])
	print("  то есть до СТЕНЫ %.2f м при длине оружия %.2f" % [
		near - hut.ring_radius(), u0.attack_range])
	print("  урон хижине за 15 с: %.0f (было %.0f, стало %.0f)" % [
		hp0 - hut.current_health, hp0, hut.current_health])
	for m in men:
		var u2 := m as Unit
		if is_instance_valid(u2) and not u2.is_dead():
			u2.take_damage(u2.max_health * 10.0, null)
	await pframes(4)
	hut.queue_free()
	await pframes(2)

## ── ЧАСТЬ 2: ПРИКАЗ В ЗАМЕСЕ ──────────────────────────────────────────────
## ── ТРИ ОТРЯДА НА ДЕРЕВНЮ ────────────────────────────────────────────────
func _p3_village() -> void:
	print("\n===== ЧАСТЬ 3: ТРИ ОТРЯДА НА ДЕРЕВНЮ =====")
	var huts: Array = []
	for i in range(3):
		var h = load("res://scripts/goblin/GoblinHut.gd").new()
		h.faction = Constants.FACTION_GOBLIN
		main.world_add(h)
		var p := Vector3(float(i) * 7.0, 0.0, 0.0)
		h.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		huts.append(h)
	await pframes(6)
	var sids: Array = []
	var all: Array = []
	sm._clear_selection()
	for i in range(3):
		var r: Array = _mk("spearman", Vector3(float(i) * 5.0 - 3.0, 0.0, 20.0),
			15, Constants.FACTION_PLAYER)
		sids.append(int(r[0]))
		for m in r[1]:
			all.append(m)
			sm._select(m)
	await pframes(6)
	var hp0: Array = []
	for h in huts:
		hp0.append((h as Building).current_health)
	var cam: Camera3D = main.get("_camera") as Camera3D
	main.focus_camera_on((huts[1] as Node3D).global_position)
	await frames(3)
	var scr: Vector2 = cam.unproject_position(
		(huts[1] as Node3D).global_position + Vector3(0.0, 1.0, 0.0))
	sm._handle_right_click(scr)
	await frames(2)
	var plan: Dictionary = {}
	for sid in sids:
		var tgt = GameManager.squad_orders.get(sid, {}).get("target")
		plan[sid] = tgt
		var hi := -1
		for k in range(huts.size()):
			if huts[k] == tgt:
				hi = k
		print("  отряд %d -> хижина %d, держит позицию=%s" % [
			sid, hi, str(GameManager.squad_attack_hold(sid))])
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await get_tree().physics_frame
	var hit := 0
	for k in range(huts.size()):
		# ПРОВЕРКА ЖИВОСТИ — ДО ПРИВЕДЕНИЯ ТИПА (правило 5 в CLAUDE.md):
		# снесённая хижина уже освобождена, и `var h: Building = ...` на ней
		# бросает исключение, не дав is_instance_valid ни одного шанса
		var raw = huts[k]
		var gone: bool = not is_instance_valid(raw)
		var hp_now: float = 0.0
		if not gone:
			hp_now = (raw as Building).current_health
			gone = (raw as Building).is_dead()
		var dmg: float = float(hp0[k]) - hp_now
		if dmg > 1.0:
			hit += 1
		print("  хижина %d: урона %.0f%s" % [k, dmg, "  (СНЕСЕНА)" if gone else ""])
	print("  ДОМОВ ПОД УДАРОМ: %d из 3" % hit)
	for m in all:
		var u := m as Unit
		if is_instance_valid(u) and not u.is_dead():
			u.take_damage(u.max_health * 10.0, null)
	await pframes(4)
	for h in huts:
		if is_instance_valid(h):
			(h as Node).queue_free()
	await pframes(2)

func _p2_order() -> void:
	print("\n===== ЧАСТЬ 2: ПРИКАЗ В ЗАМЕСЕ =====")
	# Две армии сходятся вплотную: шесть отрядов игрока против шести чужих
	var mine: Array = []
	var theirs: Array = []
	for i in range(6):
		var a: Array = _mk("spearman", Vector3(-60.0 + float(i) * 6.0, 0.0, -60.0),
			20, Constants.FACTION_PLAYER)
		mine.append(a)
		var b: Array = _mk("warrior", Vector3(-60.0 + float(i) * 6.0, 0.0, -56.0),
			20, Constants.FACTION_ENEMY)
		theirs.append(b)
	await pframes(6)
	# Даём им как следует сцепиться и потрепать друг друга
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000:
		await get_tree().physics_frame
	var alive := 0
	var panicked := 0
	var sids: Array = []
	for a in mine:
		var sid: int = int((a as Array)[0])
		sids.append(sid)
		if GameManager.squad_panicked(sid):
			panicked += 1
		for m in GameManager.squad_members(sid):
			if is_instance_valid(m) and not (m as Unit).is_dead():
				alive += 1
	print("  после 40 с замеса: живых своих %d, паникующих отрядов %d из %d" % [
		alive, panicked, sids.size()])

	# ПРИКАЗ ОТХОДА: выделяем всё своё и щёлкаем далеко назад
	sm._clear_selection()
	for a in mine:
		for m in GameManager.squad_members(int((a as Array)[0])):
			if is_instance_valid(m) and not (m as Unit).is_dead():
				sm._select(m)
	await frames(2)
	var before: Dictionary = {}
	var watched: Array = []
	for u in sm.selected_units:
		var uu := u as Unit
		if uu == null or not is_instance_valid(uu):
			continue
		before[uu] = uu.global_position
		watched.append(uu)
	print("  выделено бойцов: %d" % watched.size())
	var goal := Vector3(-60.0, 0.0, -110.0)
	sm._issue_formation_move(goal, false)
	await frames(2)
	# Кто ПРИНЯЛ приказ (состояние сменилось), а кто нет
	var moving := 0
	var refused := 0
	var refused_panic := 0
	for u in watched:
		var uu := u as Unit
		if not is_instance_valid(uu) or uu.is_dead():
			continue
		if uu.state == Unit.State.MOVING:
			moving += 1
		else:
			refused += 1
			if uu.is_panicked():
				refused_panic += 1
	print("  С ПЕРВОГО КЛИКА приняли приказ: %d, НЕ приняли: %d (из них паникуют %d)" % [
		moving, refused, refused_panic])
	# И реально ли уехали
	var t1: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 5000:
		await get_tree().physics_frame
	var went := 0
	var stuck := 0
	for u in watched:
		var uu := u as Unit
		if not is_instance_valid(uu) or uu.is_dead():
			continue
		var d: float = (uu.global_position - (before[uu] as Vector3)).length()
		if d > 2.0:
			went += 1
		else:
			stuck += 1
	print("  за 5 с сдвинулись дальше 2 м: %d, остались на месте: %d" % [went, stuck])
