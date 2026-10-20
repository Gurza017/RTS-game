extends Node

## ЗОНД РАЗРЫВА ОТРЯДА (14.10.2026). Вердиктов нет — числа.
## Метрика раз в 0.5 с: компоненты связности отряда (звено 3 м), доля
## крупнейшей, наибольшее расстояние между центрами компонент (≥ 3 бойцов).
## A — красные копейщики под обстрелом лучников из-за рощи (половина фронта)
## B — наши копейщики атакуют отряд, который сам расходится на 2 половины
## C — марш мимо рощи: центр мимо, половина строя сквозь
## Аргументы: -- only=abc kind=wall|normal secs=40
## Запуск: godot --headless --path . res://qa_split_probe/Probe.tscn

const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const LINK_M := 3.0
const SITE := Vector3(-60.0, 0.0, 60.0)

var main = null
var sm = null
var _only := "abc"
var _kind := 1          # ResourceNode.FOREST_WALL
var _secs := 40.0
var _gz0 := -0.3
var _gz1 := 8.0
var _gx0 := -6.5
var _nred := 30
var _adist := 12.5
var _aorder := false
var _acols := 10
var _onetgt := false
var _done := false

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(1200.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился")
		_finish())

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ КОНЕЦ qa_split_probe ═════")
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead() and not (m as Unit).garrisoned:
			o.append(m)
	return o

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Блок: ряды назад от face (глубина), колонки по Z (фронт)
func _squad(uid: String, f: int, at: Vector3, n: int, cols: int, face: Vector3 = Vector3(-1, 0, 0)) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var row: int = i / cols
		var col: int = i % cols
		var p: Vector3 = at - face * (float(row) * 0.65) + Vector3(0, 0, (float(col) - float(cols - 1) * 0.5) * 0.65)
		var u := _unit(uid, f, p)
		u.set("_facing", face)
		GameManager.add_to_squad(sid, u)
	return sid

func _plant(p: Vector2) -> void:
	main._plant_tree(p, _kind, 1.0)

func _clean(centre: Vector3, r: float) -> void:
	main._clear_area_of_resources(centre, r)
	main._clear_trees(centre, r)
	var was: bool = Unit.losses_frozen
	Unit.losses_frozen = false
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit and (n0 as Unit).global_position.distance_to(centre) < r + 40.0:
			(n0 as Unit).take_damage(1.0e12)
	Unit.losses_frozen = was
	for sh in get_tree().get_nodes_in_group("sheep"):
		if is_instance_valid(sh) and (sh as Node3D).global_position.distance_to(centre) < r + 40.0:
			(sh as Node).queue_free()
	await pframes(10)

func _kill_sids(sids: Array) -> void:
	var was: bool = Unit.losses_frozen
	Unit.losses_frozen = false
	for s in sids:
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)
	Unit.losses_frozen = was
	await pframes(20)

## Компоненты: Array of Array[int] (индексы men), по убыванию размера
func _comps(men: Array) -> Array:
	var n: int = men.size()
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var l2: float = LINK_M * LINK_M
	var out: Array = []
	for i0 in range(n):
		if comp[i0] >= 0:
			continue
		var cid: int = out.size()
		var lst: Array = [i0]
		comp[i0] = cid
		var k := 0
		while k < lst.size():
			var i: int = lst[k]
			k += 1
			var pi: Vector3 = (men[i] as Unit).global_position
			for j in range(n):
				if comp[j] >= 0:
					continue
				var pj: Vector3 = (men[j] as Unit).global_position
				var dx: float = pi.x - pj.x
				var dz: float = pi.z - pj.z
				if dx * dx + dz * dz <= l2:
					comp[j] = cid
					lst.append(j)
		out.append(lst)
	out.sort_custom(func(a, b): return (a as Array).size() > (b as Array).size())
	return out

func _centre(men: Array, idx: Array) -> Vector3:
	var c := Vector3.ZERO
	for i in idx:
		c += (men[int(i)] as Unit).global_position
	c /= float(maxi(idx.size(), 1))
	c.y = 0.0
	return c

## Сводка по компоненте: состояния, цели, флаги, дороги
func _comp_info(men: Array, idx: Array) -> String:
	var st: Dictionary = {}
	var forced := 0
	var lock := 0
	var tgt := 0
	var tsq: Dictionary = {}
	var route := 0
	var aroute := 0
	var tc := Vector3.ZERO
	var mtc := Vector3.ZERO
	var nmt := 0
	for i in idx:
		var u := men[int(i)] as Unit
		st[int(u.state)] = int(st.get(int(u.state), 0)) + 1
		if bool(u.get("_attack_is_forced")): forced += 1
		if u.target_lock: lock += 1
		var t = u.attack_target
		if t != null and is_instance_valid(t):
			tgt += 1
			tc += (t as Node3D).global_position
			var ts: int = (t as Unit).squad_id if t is Unit else -1
			tsq[ts] = int(tsq.get(ts, 0)) + 1
		if (u.get("_route") as PackedVector3Array).size() > 0: route += 1
		if (u.get("_atk_route") as PackedVector3Array).size() > 0: aroute += 1
		if u.state == Unit.State.MOVING:
			mtc += u.move_target
			nmt += 1
	var s := "n=%d st%s forced=%d lock=%d tgt=%d тсквады%s _route=%d _atk_route=%d" % [idx.size(), str(st), forced, lock, tgt, str(tsq), route, aroute]
	if tgt > 0:
		tc /= float(tgt)
		s += " центр_целей(%.0f,%.0f)" % [tc.x, tc.z]
	if nmt > 0:
		mtc /= float(nmt)
		s += " move_target(%.0f,%.0f)" % [mtc.x, mtc.z]
	return s

## Наблюдатель: раз в 0.5 с; печать каждую секунду; разрыв = ≥ 2 компоненты
## по ≥ 3 бойца с центрами дальше 8 м
func _watch(tag: String, sid: int, secs: float) -> Dictionary:
	var res := {"split_s": 0.0, "split_max_run": 0.0, "dist_max": 0.0, "minshare": 1.0, "maxcomps": 1}
	var run := 0.0
	var dumped := 0
	var t := 0.0
	while t < secs:
		await pframes(30)
		t += 0.5
		var men: Array = _members(sid)
		if men.size() < 4:
			print("    [%s] %.1f с: отряд %d — осталось %d" % [tag, t, sid, men.size()])
			break
		var cs: Array = _comps(men)
		var big: Array = []
		for c in cs:
			if (c as Array).size() >= 3:
				big.append(c)
		var dmax := 0.0
		var cents: Array = []
		for c2 in big:
			cents.append(_centre(men, c2))
		for i in range(cents.size()):
			for j in range(i + 1, cents.size()):
				dmax = maxf(dmax, (cents[i] as Vector3).distance_to(cents[j]))
		var share: float = float((cs[0] as Array).size()) / float(men.size())
		res["dist_max"] = maxf(float(res["dist_max"]), dmax)
		res["minshare"] = minf(float(res["minshare"]), share)
		res["maxcomps"] = maxi(int(res["maxcomps"]), cs.size())
		var split: bool = big.size() >= 2 and dmax > 8.0
		if split:
			run += 0.5
			res["split_s"] = float(res["split_s"]) + 0.5
			res["split_max_run"] = maxf(float(res["split_max_run"]), run)
		else:
			run = 0.0
		if int(t * 2.0) % 2 == 0 or split:
			var all_c: Vector3 = _centre(men, range(men.size()))
			print("    [%s] %4.1f с: живых %d, компонент %d (≥3: %d), доля крупнейшей %.2f, центры разошлись до %.1f м, центр (%.0f,%.0f)%s" % [
				tag, t, men.size(), cs.size(), big.size(), share, dmax, all_c.x, all_c.z, "  РАЗРЫВ" if split else ""])
		if (split and (run == 0.5 or run == 3.0 or run == 8.0) and dumped < 6) or (int(t * 2.0) % 10 == 0 and t <= 10.0):
			dumped += 1 if split else 0
			for k in range(mini(cs.size(), 4)):
				var c3: Vector3 = _centre(men, cs[k])
				print("        комп %d (%.1f,%.1f): %s" % [k, c3.x, c3.z, _comp_info(men, cs[k])])
	print("  ИТОГ %s: в разрыве %.1f с всего, дольше подряд %.1f с; центры компонент до %.1f м; доля крупнейшей мин. %.2f; компонент до %d" % [
		tag, float(res["split_s"]), float(res["split_max_run"]), float(res["dist_max"]), float(res["minshare"]), int(res["maxcomps"])])
	return res

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="): _only = s.substr(5)
		elif s.begins_with("kind="): _kind = 1 if s.substr(5) == "wall" else 0
		elif s.begins_with("secs="): _secs = float(s.substr(5))
		elif s.begins_with("gz0="): _gz0 = float(s.substr(4))
		elif s.begins_with("gz1="): _gz1 = float(s.substr(4))
		elif s.begins_with("gx0="): _gx0 = float(s.substr(4))
		elif s.begins_with("nred="): _nred = int(s.substr(5))
		elif s.begins_with("adist="): _adist = float(s.substr(6))
		elif s.begins_with("aorder="): _aorder = s.substr(7) == "1"
		elif s.begins_with("acols="): _acols = int(s.substr(6))
		elif s.begins_with("onetgt="): _onetgt = s.substr(7) == "1"
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	sm = main.selection_manager
	for k in ["enemy_ai", "gnoll_ai", "enemy_guard", "goblin_ai", "goblin_reserve", "assault_event", "raid_manager"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)
			(n as Node).set_physics_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	print("  зонд: площадка (%.0f,%.0f), роща %s, сценарий до %.0f с" % [SITE.x, SITE.z, "лес-стена (маска)" if _kind == 1 else "обычные стволы", _secs])
	await _clean(SITE, 45.0)
	if _only.contains("a"):
		await _sc_a()
	if _only.contains("b"):
		await _sc_b()
	if _only.contains("c"):
		await _sc_c()
	_finish()

func _cliffs(men: Array) -> int:
	var n := 0
	for u in men:
		var p: Vector3 = (u as Unit).global_position
		if GameManager.is_cliff(p.x, p.z):
			n += 1
	return n

# ── A ───────────────────────────────────────────────────────────────────────
func _sc_a() -> void:
	print("\n═════ A. КРАСНЫЕ КОПЕЙЩИКИ ПОД ОБСТРЕЛОМ ИЗ-ЗА РОЩИ ═════")
	await _clean(SITE, 45.0)
	# Красные: фронт по Z (10 колонок = 5.9 м), лицом в −X, ряды назад в +X
	var red: int = _squad("spearman", E, SITE, _nred, mini(10, _nred), Vector3(-1, 0, 0))
	# Роща между: x ∈ [−6.5, −3] от фронта, z от центра на +8 (половина фронта с запасом)
	var x := SITE.x + _gx0
	while x <= SITE.x - 3.0:
		var z := SITE.z + _gz0
		while z <= SITE.z + _gz1:
			_plant(Vector2(x + randf_range(-0.2, 0.2), z + randf_range(-0.2, 0.2)))
			z += 1.7 if _kind == 1 else 1.4
		x += 1.6
	# Лучники игрока: передний ряд в 12.5 м от фронта красных, лицом в +X
	var arch: int = _squad("archer", F, SITE + Vector3(-_adist, 0, 1.5), 30, _acols, Vector3(1, 0, 0))
	await pframes(60 * 3)   # пересборка сетки A*
	print("    бойцов в маске скал: красных %d, лучников %d; прямая центр-центр заслонена: %s" % [
		_cliffs(_members(red)), _cliffs(_members(arch)),
		str(GameManager.nav_blocked(SITE + Vector3(0, 0, 2), SITE + Vector3(-_adist, 0, 2), 1.5))])
	if _aorder:
		var rm: Array = _members(red)
		for ua in _members(arch):
			(ua as Unit).command_attack(rm[0], true, true, true)
		print("    лучникам приказ атаки на отряд красных (замок)")
	if _onetgt:
		_one_target(red, arch)
	Unit.losses_frozen = true
	await _watch("A", red, _secs)
	Unit.losses_frozen = false
	await _kill_sids([red, arch])

# ── B ───────────────────────────────────────────────────────────────────────
func _sc_b() -> void:
	print("\n═════ B. АТАКА НА ОТРЯД, КОТОРЫЙ РАСХОДИТСЯ НАДВОЕ ═════")
	await _clean(SITE, 45.0)
	var mine: int = _squad("spearman", F, SITE + Vector3(-15, 0, 0), 30, 10, Vector3(1, 0, 0))
	var foe: int = _squad("spearman", E, SITE, 30, 10, Vector3(-1, 0, 0))
	await pframes(30)
	var fm: Array = _members(foe)
	# Атака приказом игрока (как SelectionManager): цель одна, замок
	var tgt: Unit = fm[0]
	for u in _members(mine):
		(u as Unit).command_attack(tgt, true, true, true)
	await pframes(6)
	# Враги расходятся: z ≥ центр — вправо (+Z 20), прочие влево
	for u2 in fm:
		var uu := u2 as Unit
		var dz: float = 20.0 if uu.global_position.z >= SITE.z else -20.0
		uu.command_move(uu.global_position + Vector3(4.0, 0, dz))
	Unit.losses_frozen = true
	await _watch("B", mine, _secs)
	Unit.losses_frozen = false
	await _kill_sids([mine, foe])

# ── C ───────────────────────────────────────────────────────────────────────
func _sc_c() -> void:
	print("\n═════ C. МАРШ МИМО РОЩИ: ПОЛОВИНА СТРОЯ СКВОЗЬ ═════")
	await _clean(SITE, 45.0)
	var mine: int = _squad("spearman", F, SITE + Vector3(-20, 0, 0), 30, 10, Vector3(1, 0, 0))
	# Роща 7 деревьев на 5 м по ходу, сдвинута в +Z на четверть фронта
	var pts := [Vector2(-8, 1.5), Vector2(-8, 3.0), Vector2(-6.5, 2.2), Vector2(-5, 1.2), Vector2(-5, 3.2), Vector2(-3.5, 2.0), Vector2(-6.5, 0.8)]
	for p in pts:
		_plant(Vector2(SITE.x + (p as Vector2).x, SITE.z + (p as Vector2).y))
	await pframes(60 * 3)
	sm.select_units(_members(mine))
	await pframes(2)
	sm.order_at_world(SITE + Vector3(12, 0, 0), false)
	sm.select_units([])
	await _watch("C", mine, minf(_secs, 30.0))
	await _kill_sids([mine])

## ЭКСПЕРИМЕНТ: всем красным, идущим на лучников, — ОДНА цель (средний
## лучник первого ряда) на 20 с. Проверка: разрыв даёт разбор целей по
## ширине чужого строя (squad_pick_member) — или нет
func _one_target(red: int, arch: int) -> void:
	var am: Array = _members(arch)
	var central: Unit = am[mini(am.size() - 1, _acols / 2)]
	var swaps := 0
	for _k in range(20 * 20):
		await pframes(3)
		if not is_instance_valid(central):
			return
		for u in _members(red):
			var uu := u as Unit
			var t = uu.attack_target
			if t != null and is_instance_valid(t) and t is Unit and (t as Unit).squad_id == arch and t != central:
				uu.set_attack_target(central)
				uu.set("_atk_route", PackedVector3Array())
				swaps += 1
	print("    эксперимент onetgt: подмен цели %d" % swaps)
