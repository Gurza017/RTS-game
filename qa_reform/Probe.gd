extends Node
## Диагностика: почему отряд не смыкается после прохода союзника.
## Воспроизводит скриншот — несколько стоящих отрядов, сквозь которые идёт
## союзный отряд, и печатает, КАКИЕ ВОРОТА обхода кого отсекают.

var main = null
var sm = null
var walls: Array = []      # [sid, men]

func _ready() -> void: call_deferred("_run")
func pf(n: int) -> void:
	for _i in range(n): await get_tree().physics_frame

func _spawn(scene: String, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _report(tag: String) -> void:
	print("  ── %s ──" % tag)
	for rec in walls:
		var sid: int = int(rec[0])
		var men: Array = GameManager.squad_members(sid)
		var mv := 0
		var idle := 0
		var atk := 0
		var drift := 0
		var live := 0
		var worst := 0.0
		for m in men:
			var u := m as Unit
			if u == null or not is_instance_valid(u) or u.is_dead(): continue
			live += 1
			if u.state == Unit.State.MOVING: mv += 1
			elif u.state == Unit.State.ATTACKING: atk += 1
			else: idle += 1
			if not u._post_valid: continue
			var d: float = Vector2(u.global_position.x - u.post_pos.x,
				u.global_position.z - u.post_pos.z).length()
			worst = maxf(worst, d)
			if d > GameManager.REFORM_DRIFT: drift += 1
		# Какие ворота срабатывают
		var gate := "—"
		if (GameManager.squads[sid] as Dictionary).get("slots", []).is_empty():
			gate = "НЕТ РАЗМЕТКИ"
		elif String((GameManager.squads[sid] as Dictionary).get("type", "")) == "worker":
			gate = "РАБОЧИЙ — строй его не касается"
		elif GameManager.squad_in_combat(sid):
			gate = "в бою — строй ждёт"
		elif Time.get_ticks_msec() - int((GameManager.squads[sid] as Dictionary).get("calm_ms", 0)) 				< int(GameManager.REFORM_SETTLE_SEC * 1000.0):
			gate = "пауза после воздействия"
		elif atk > 0:
			gate = "кто-то занят боем"
		elif mv * 2 > live:
			gate = "отряд НА МАРШЕ"
		elif drift == 0:
			gate = "повода нет"
		else:
			gate = "смыкание разрешено"
		print("    отряд %d: живых %d | идут %d, стоят %d, дерутся %d | съехало %d, худший %.2f м | ворота: %s"
			% [sid, live, mv, idle, atk, drift, worst, gate])

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(8)
	sm = main.selection_manager
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null: GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"): (n as Node).queue_free()
	await pf(4)
	print("=== ЗОНД: ПОЧЕМУ СТРОЙ НЕ СМЫКАЕТСЯ ===")
	print("  порог съезда %.2f м, пауза после воздействия %.2f с, такт обхода %.2f с" % [
		GameManager.REFORM_DRIFT, GameManager.REFORM_SETTLE_SEC,
		GameManager.REFORM_SWEEP_SEC])

	var base := Vector3(-700.0, 0.0, -700.0)
	# ПЯТЬ отрядов в ряд — как на скриншоте
	for s in range(5):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		var men: Array = []
		for i in range(40):
			var u := _spawn("res://scenes/units/Spearman.tscn",
				base + Vector3(float(s) * 16.0 + float(i % 10) * 0.7, 0.0,
					float(i / 10) * 0.7))
			GameManager.add_to_squad(sid, u)
			men.append(u)
		walls.append([sid, men])
	await pf(6)
	# Строевой приказ каждому — так появляется разметка
	for rec in walls:
		sm._clear_selection()
		for u2 in (rec[1] as Array): sm._select(u2)
		await pf(2)
		var c: Vector3 = GameManager.squad_centroid(int(rec[0]))
		sm._execute_line_formation(c + Vector3(-5.0, 0.0, 0.0), c + Vector3(5.0, 0.0, 0.0))
	sm._clear_selection()
	await pf(900)
	_report("строй встал")

	# СОЮЗНИК ИДЁТ СКВОЗЬ ВСЕХ ПЯТЕРЫХ
	var asid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var arch: Array = []
	for i in range(24):
		var a := _spawn("res://scenes/units/Archer.tscn",
			base + Vector3(-14.0 + float(i % 6) * 0.7, 0.0, float(i / 6) * 0.7))
		GameManager.add_to_squad(asid, a)
		arch.append(a)
	await pf(6)
	sm._clear_selection()
	for a2 in arch: sm._select(a2)
	await pf(2)
	sm._issue_formation_move(base + Vector3(80.0, 0.0, 1.0), false)
	sm._clear_selection()
	await pf(300)
	_report("союзник внутри")
	await pf(600)
	_report("союзник ушёл")
	for t in range(4):
		await pf(300)
		_report("+%d с после ухода" % ((t + 1) * 5))
	get_tree().quit(0)
