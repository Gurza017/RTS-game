extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_red_ai_aggro — ТЗ 12.10.2026 (второе письмо, блок 3)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: «отряды Красного стоят, смотрят вниз, ходят спиной вперёд, не
## агрятся и не дерутся даже при расстреле в упор; застревают у башен».
## A — живая партия: у красных на старте есть отряды (охрана базы); к
##     ближайшему подходят лучники игрока и стреляют в упор. За 25 с красные
##     обязаны ответить: часть бойцов в бою, урон по лучникам есть.
## B — отряд копейщиков красного на марше: поза копий — по ходу (не спиной).
## C — то же у башни: лучники игрока за башней красных, отряд красных у
##     противоположной стены — дошёл и бьёт, а не встал у стены.
## Числа — из конфигов; ожидание — физкадрами.
## Запуск: godot --headless --path . res://qa_red_ai_aggro/Test.tscn [-- only=abc]

const P := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const _Tower := preload("res://scripts/Tower.gd")

var main = null
var _pass := 0
var _fail := 0
var _only := "abcde"
var _done := false

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(500.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_red_ai_aggro: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, n: int, at: Vector3) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u := _spawn(kind, fac, at + Vector3(float(i % 6) * 0.8, 0, float(i / 6) * 0.8))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(arr: Array) -> Array:
	var o: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			o.append(u)
	return o

func _members(sid: int) -> Array:
	var sq: Variant = GameManager.squads.get(sid)
	return _alive((sq as Dictionary)["members"]) if sq != null else []

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if _only.contains("a"): await _block_a()
	if _only.contains("b"): await _block_b()
	if _only.contains("c"): await _block_c()
	if _only.contains("e"): await _block_e()
	if _only.contains("d"): await _block_d()
	_finish()

# ── A. РАССТРЕЛ ОХРАНЫ БАЗЫ ─────────────────────────────────────────────────
func _block_a() -> void:
	print("\n═════ A. КРАСНЫЕ ОТВЕЧАЮТ НА ОБСТРЕЛ ═════")
	# Ближайший к центру карты боевой отряд красных
	var best := -1
	var bd := 1e9
	for sid in GameManager.squads:
		var sq: Dictionary = GameManager.squads[sid]
		if int(sq["faction"]) != R or String(sq["type"]) == "worker":
			continue
		var c: Vector2 = GameManager.squad_centre_xz(int(sid))
		if c == Vector2.INF:
			continue
		var d: float = c.length()
		if d < bd:
			bd = d
			best = int(sid)
	if best < 0:
		verdict("A0 у красных есть боевые отряды на старте", false)
		return
	var c2: Vector2 = GameManager.squad_centre_xz(best)
	var rc := Vector3(c2.x, 0, c2.y)
	var reds: Array = _members(best)
	print("  отряд красных %d %s, бойцов %d, центр %s, спит=%s" % [best, GameManager.squad_type(best), reds.size(), str(rc), str((reds[0] as Unit).dormant)])
	# Лучники игрока в 16 м — к центру карты от отряда
	var away: Vector3 = (-rc).normalized() if rc.length() > 1.0 else Vector3.FORWARD
	var arch: Array = _squad("archer", P, 20, rc + away * 16.0)
	var hp0: float = 0.0
	for u in arch[1]:
		hp0 += (u as Unit).current_health
	var reds_hp0: float = 0.0
	for u in reds:
		reds_hp0 += (u as Unit).current_health
	for u in arch[1]:
		(u as Unit).command_attack(reds[0], true, true)
	var first_fight := -1.0
	for t in range(50):
		await pframes(30)
		var fighting := 0
		for u in _members(best):
			if (u as Unit).state == Unit.State.ATTACKING:
				fighting += 1
		if fighting > 0 and first_fight < 0.0:
			first_fight = float(t + 1) * 0.5
	var hp1: float = 0.0
	for u in _alive(arch[1]):
		hp1 += (u as Unit).current_health
	var reds_hp1: float = 0.0
	for u in _members(best):
		reds_hp1 += (u as Unit).current_health
	verdict("A1 лучники и правда стреляли (красные потеряли запас)", reds_hp1 < reds_hp0 - 1.0,
		"%.0f → %.0f" % [reds_hp0, reds_hp1])
	verdict("A2 красные вступили в бой не позже 6 с", first_fight >= 0.0 and first_fight <= 6.0, "через %.1f с" % first_fight)
	verdict("A3 красные нанесли урон обидчикам", hp1 < hp0 - 1.0, "запас лучников %.0f → %.0f" % [hp0, hp1])
	for u in _alive(arch[1]):
		(u as Unit).take_damage(1e9)
	await pframes(10)

# ── B. ПОЗА НА МАРШЕ ─────────────────────────────────────────────────────────
func _block_b() -> void:
	print("\n═════ B. КОПЬЯ ПО ХОДУ ═════")
	# Свой приказ ИИ здесь не нужен: меряется поза на марше
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	var at := Vector3(-60, 0, 60)
	main._clear_trees(at, 30.0)
	# Площадку держит стенд: охрана рудников и бродячие гоблины рядом втягивали
	# отряд в бой (ловушка «стенд на случайной карте»)
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit and not (n0 as Unit).is_dead() \
				and (n0 as Unit).global_position.distance_to(at) < 70.0:
			(n0 as Unit).take_damage(1e9)
	await pframes(5)
	# ТЗ 14.10.2026: копья в «Защите» опускает только изученная «Фаланга»
	GameManager.finish_research(R, "spearman_1d")
	var sq: Array = _squad("spearman", R, 18, at)
	var sid: int = sq[0]
	# Курс отряда «вниз» (как после смыкания), а идут вверх — прежняя жалоба
	var slots: Array = []
	for u in sq[1]:
		slots.append((u as Unit).global_position)
	GameManager.squad_set_formation(sid, slots, Vector3(0, 0, 1), false)
	for u in sq[1]:
		if (u as Unit).has_method("set_stance"):
			(u as Unit).set_stance("defense")
		(u as Unit).command_move((u as Unit).global_position + Vector3(0, 0, -25))
	var bad := 0
	var n := 0
	for t in range(20):
		await pframes(15)
		for u in _alive(sq[1]):
			var sp := u as Spearman
			if sp == null or sp.state != Unit.State.MOVING or not sp._spear_leveled():
				continue
			n += 1
			var key: String = String(sp._cur_tex_key)
			if key.contains("down"):
				bad += 1
	verdict("B1 идущие вверх копейщики не смотрят вниз (поза по ходу)", n > 0 and bad == 0, "выборок с копьём наперевес %d, из них «вниз» %d" % [n, bad])
	await pframes(60 * 20)
	var cnt := 0
	for u in _alive(sq[1]):
		if absf((u as Unit).global_position.z - (at.z - 25.0)) < 4.0:
			cnt += 1
	var zs: Array = []
	for u in _alive(sq[1]):
		zs.append("%.1f/%d" % [(u as Unit).global_position.z - at.z, int((u as Unit).state)])
	verdict("B2 отряд дошёл", cnt >= 12, "%d из 18; z-сдвиг/состояние %s" % [cnt, str(zs)])
	for u in _alive(sq[1]):
		(u as Unit).take_damage(1e9)
	await pframes(10)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(true)

# ── C. ВРАГ ЗА БАШНЕЙ ────────────────────────────────────────────────────────
func _block_c() -> void:
	print("\n═════ C. ВРАГ ЗА БАШНЕЙ ═════")
	var at := Vector3(-40, 0, -40)
	main._clear_trees(at, 35.0)
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and not (n as Unit).is_dead() and (n as Unit).global_position.distance_to(at) < 40.0:
			(n as Unit).take_damage(1e9)
	await pframes(5)
	var tw: Building = _Tower.new()
	tw.faction = R
	main.world_add(tw)
	tw.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	var reds: Array = _squad("swordsman" if Building.PRELOAD_SCENES.has("swordsman") else "warrior", R, 12, at + Vector3(-1, 0, 5))
	var arch: Array = _squad("archer", P, 12, at + Vector3(0, 0, -14))
	for u in arch[1]:
		(u as Unit).command_attack(reds[1][0], true, true)
	var reached := 0
	for t in range(40):
		await pframes(30)
	var hp_a := 0.0
	for u in _alive(arch[1]):
		hp_a += (u as Unit).current_health
	var full: float = 0.0
	for u in arch[1]:
		full += (u as Unit).max_health
	for u in _alive(reds[1]):
		if Vector2((u as Unit).global_position.x - at.x, (u as Unit).global_position.z - (at.z - 14.0)).length() < 6.0:
			reached += 1
	var stc: Dictionary = {}
	var hpc := 0.0
	for u in _alive(reds[1]):
		stc[int((u as Unit).state)] = int(stc.get(int((u as Unit).state), 0)) + 1
		hpc += (u as Unit).current_health
	print("    красные C: состояния %s запас %.0f; пример %s цель %s" % [str(stc), hpc, str((reds[1][0] as Unit).global_position) if is_instance_valid(reds[1][0]) else "-", str((reds[1][0] as Unit).attack_target) if is_instance_valid(reds[1][0]) else "-"])
	verdict("C1 красные обошли башню и дошли до лучников", reached > 0 or hp_a < full * 0.6,
		"у лучников %d, запас лучников %.0f из %.0f" % [reached, hp_a, full])

# ── D. ВЗГЛЯД СПЯЩЕЙ ОХРАНЫ БАЗЫ ───────────────────────────────────────────
## Новая партия: охрана базы красных рождается постами (Main._spawn_squad_block)
## и сразу засыпает. Взгляд каждого копейщика — по фронту поста (курс отряда),
## а не «вниз» по умолчанию; курс у отряда есть
func _block_d() -> void:
	print("\n═════ D. ВЗГЛЯД ОХРАНЫ БАЗЫ ═════")
	if main != null:
		main.queue_free()
		await pframes(5)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(120)
	var n := 0
	var ok := 0
	var no_course := 0
	for sid in GameManager.squads:
		var sq: Dictionary = GameManager.squads[sid]
		if int(sq["faction"]) != R or String(sq["type"]) != "spearman":
			continue
		var c: Vector3 = GameManager.squad_course(int(sid))
		if c.length_squared() < 1e-6:
			no_course += 1
			continue
		for m in sq["members"]:
			if not is_instance_valid(m) or (m as Unit).is_dead():
				continue
			n += 1
			var f: Vector3 = (m as Unit)._facing
			if Vector2(f.x, f.z).normalized().dot(Vector2(c.x, c.z).normalized()) > 0.7:
				ok += 1
	verdict("D1 у отрядов копейщиков красных есть курс", no_course == 0, "без курса %d" % no_course)
	verdict("D2 копейщики охраны смотрят по курсу поста (≥ 90 %)", n > 0 and float(ok) >= float(n) * 0.9, "%d из %d" % [ok, n])

# ── E. ВРАГ ЗА ЛЕСНОЙ СТЕНОЙ ─────────────────────────────────────────────────
## Стена леса (FOREST_WALL — непроходима для отрядов) с проходом в 20 м сбоку;
## лучники игрока за стеной стреляют по копейщикам красных. Красные обязаны
## обойти через проход и рубить, а не стоять у стены под стрелами
func _block_e() -> void:
	print("\n═════ E. ВРАГ ЗА ЛЕСНОЙ СТЕНОЙ ═════")
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	var at := Vector3(-30, 0, 70)
	main._clear_trees(at, 45.0)
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit and not (n0 as Unit).is_dead() 				and (n0 as Unit).global_position.distance_to(at) < 70.0:
			(n0 as Unit).take_damage(1e9)
	await pframes(5)
	# Стена вдоль X на z = at.z, два ряда; проход x ∈ [at.x+14, at.x+22]
	var x := at.x - 30.0
	while x <= at.x + 30.0:
		if x < at.x + 14.0 or x > at.x + 22.0:
			main._plant_tree(Vector2(x, at.z), ResourceNode.FOREST_WALL, 1.0)
			main._plant_tree(Vector2(x + 0.9, at.z + 1.4), ResourceNode.FOREST_WALL, 1.0)
		x += 1.8
	# Сетка A* пересобирается по посадке не чаще FOREST_NAV_MIN_MS
	await pframes(150)
	var reds: Array = _squad("spearman", R, 18, at + Vector3(-4, 0, -8))
	var arch: Array = _squad("archer", P, 12, at + Vector3(-4, 0, 10))
	for u in arch[1]:
		(u as Unit).command_attack(reds[1][0], true, true)
	var full := 0.0
	for u in arch[1]:
		full += (u as Unit).max_health
	for t in range(80):
		await pframes(30)
	var hp_a := 0.0
	for u in _alive(arch[1]):
		hp_a += (u as Unit).current_health
	var crossed := 0
	for u in _alive(reds[1]):
		if (u as Unit).global_position.z > at.z + 2.0:
			crossed += 1
	var st_r: Dictionary = {}
	var hp_r := 0.0
	for u in _alive(reds[1]):
		st_r[int((u as Unit).state)] = int(st_r.get(int((u as Unit).state), 0)) + 1
		hp_r += (u as Unit).current_health
	var st_a: Dictionary = {}
	for u in _alive(arch[1]):
		st_a[int((u as Unit).state)] = int(st_a.get(int((u as Unit).state), 0)) + 1
	print("    красные: состояния %s, запас %.0f; лучники: %s; пример красного %s цель %s" % [str(st_r), hp_r, str(st_a),
		str((reds[1][0] as Unit).global_position) if is_instance_valid(reds[1][0]) else "-",
		str((reds[1][0] as Unit).attack_target) if is_instance_valid(reds[1][0]) else "-"])
	if is_instance_valid(reds[1][0]):
		var r0 := reds[1][0] as Unit
		var tp: Vector3 = (r0.attack_target as Node3D).global_position if r0.attack_target != null and is_instance_valid(r0.attack_target) else Vector3.ZERO
		print("    atk_route %s dead_end %s nav_route %s ok=%s line_blocked=%s clear %.1f" % [str(r0._atk_route), str(r0._nav_dead_end),
			str(GameManager.nav_route(r0.global_position, tp, r0._nav_clear)), str(GameManager.nav_last_ok),
			str(GameManager.nav_blocked(r0.global_position, tp, r0._nav_clear)), r0._nav_clear])
	verdict("E1 красные обошли стену через проход и ответили лучникам", crossed > 0 and hp_a < full * 0.8,
		"за стеной %d из %d живых, запас лучников %.0f из %.0f" % [crossed, _alive(reds[1]).size(), hp_a, full])
