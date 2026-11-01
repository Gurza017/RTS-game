extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tz1031f — ТОЛЧОК МАССОЙ (ТЗ 31.10.2026, «главная мысль»)
## ═══════════════════════════════════════════════════════════════════════════
##   A СООТНОШЕНИЕ ОТРЯДОВ — mass_push_mult по снимку _sweep_mass:
##          1 на 1 — паритет (в т. ч. сотня гоблинов против шестидесяти
##          копейщиков), кулак 3 на 1 — сильнее, два отряда конницы против
##          ослабленного отряда копий — ≥ ×2, против трёх полных вглубь — < 1.
##   B УДАР — первые MASS_IMPACT_SEC контакта множитель выше, потом гаснет
##          (mass_impact; B0).
##   C ЖИВОЙ ЗАМЕР — отряд копейщиков против одного и против трёх отрядов
##          гоблинов (все бессмертные): кулак отодвигает строй дальше
##          (mass_push; C0 — без ручки разница пропадает).
## Запуск: godot --headless --path . res://qa_tz1031f/Test.tscn [-- only=abc]

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN
const _Opt := preload("res://scripts/perf_config.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _base: Vector3 = Vector3.ZERO
var _only: String = "abc"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_tz1031f: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Строй: колонки по X, ряды от точки at в сторону back
func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int, sp: float, back: float = -1.0) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0,
			at.z + back * float(i / cols) * sp))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _immortal(u: Unit) -> void:
	u.max_health = 1e9
	u.current_health = 1e9
	u._soa_push_stats()

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h := 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for dz in [-25.0, 0.0, 25.0]:
				for dx in [-25.0, 0.0, 25.0]:
					var q: Vector3 = p + Vector3(dx, 0.0, dz)
					h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
					if GameManager.is_water(q.x, q.z) or not GameManager.is_passable(q.x, q.z):
						h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

func _clean() -> void:
	main._clear_area_of_resources(_base, 60.0)
	main._clear_trees(_base, 60.0)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead() \
				and (u as Node3D).global_position.distance_to(_base) < 80.0:
			(u as Unit).take_damage(1e12)
	await pframes(20)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd",
			"raid_manager", "lair_director"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	for n2 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n2) and n2 is Unit and (n2 as Unit).faction != F:
			(n2 as Unit).set_tick(false)
	GameManager.troll_lair = null
	GameManager.pop_limit_enabled = false
	_base = _flat_spot(Vector3(-40.0, 0.0, -50.0))
	print("  площадка (%.0f, %.0f)" % [_base.x, _base.z])
	if "a" in _only: await _block_a()
	if "b" in _only: await _block_b()
	if "c" in _only: await _block_c()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
## Отряд «в бою» и центр в нужной точке — снимок массы без живого боя
func _stage(sid: int, at: Vector3) -> void:
	var sq: Dictionary = GameManager.squads[sid]
	sq["last_hit_ms"] = Unit.game_ms()
	GameManager._squad_centre[sid] = Vector2(at.x, at.z)

func _freeze(men: Array) -> void:
	for m in men:
		(m as Unit).set_tick(false)

func _sweep() -> void:
	GameManager._mass_t = 0.0
	GameManager._sweep_mass(0.016)

func _block_a() -> void:
	print("\n═════ A. СООТНОШЕНИЕ ОТРЯДОВ ═════")
	await _clean()
	# 1 на 1: сотня гоблинов против шестидесяти копейщиков
	var t: Array = _squad("spearman", F, _base, 60, 10, 0.6)
	var g1: Array = _squad("goblin_spearman", GF, _base + Vector3(0, 0, 4), 100, 10, 0.7, 1.0)
	_freeze(t[1]); _freeze(g1[1])
	_stage(t[0], _base); _stage(g1[0], _base + Vector3(0, 0, 6))
	_sweep()
	var k11: float = GameManager.mass_push_mult(t[0], GF, -1)
	verdict("A1 один отряд на один — паритет (×%.2f при 100 против 60 голов)" % k11, absf(k11 - 1.0) < 0.05)
	var g2: Array = _squad("goblin_spearman", GF, _base + Vector3(-6, 0, 4), 100, 10, 0.7, 1.0)
	var g3: Array = _squad("goblin_spearman", GF, _base + Vector3(6, 0, 4), 100, 10, 0.7, 1.0)
	_freeze(g2[1]); _freeze(g3[1])
	_stage(g2[0], _base + Vector3(-6, 0, 6)); _stage(g3[0], _base + Vector3(6, 0, 6))
	_sweep()
	var k31: float = GameManager.mass_push_mult(t[0], GF, -1)
	verdict("A2 кулак из трёх отрядов на один — ×%.2f" % k31, k31 > 1.7)
	var kback: float = GameManager.mass_push_mult(g1[0], F, -1)
	verdict("A3 одиночка по кулаку толкает слабее (×%.2f)" % kback, kback < 0.75)
	await _clean()
	# Ослабленный отряд копий против двух отрядов конницы
	var w: Array = _squad("spearman", F, _base, 60, 10, 0.6)
	var cav1: Array = _squad("goblin_rider", GF, _base + Vector3(-3, 0, 5), 50, 10, 0.9, 1.0)
	var cav2: Array = _squad("goblin_rider", GF, _base + Vector3(3, 0, 5), 50, 10, 0.9, 1.0)
	_freeze(w[1]); _freeze(cav1[1]); _freeze(cav2[1])
	for i in range(50):
		(w[1][i] as Unit).take_damage(1e12)
	await pframes(3)
	_stage(w[0], _base); _stage(cav1[0], _base + Vector3(-3, 0, 7)); _stage(cav2[0], _base + Vector3(3, 0, 7))
	_sweep()
	var kweak: float = GameManager.mass_push_mult(w[0], GF, -1)
	verdict("A4 две конницы по ослабленному отряду копий — ×%.2f" % kweak, kweak >= 2.0)
	# Три полных отряда копий вглубь
	var d1: Array = _squad("spearman", F, _base + Vector3(0, 0, -6), 60, 10, 0.6)
	var d2: Array = _squad("spearman", F, _base + Vector3(0, 0, -11), 60, 10, 0.6)
	var d0: Array = _squad("spearman", F, _base + Vector3(0, 0, -1), 60, 10, 0.6)
	_freeze(d1[1]); _freeze(d2[1]); _freeze(d0[1])
	_stage(d0[0], _base + Vector3(0, 0, -2)); _stage(d1[0], _base + Vector3(0, 0, -7)); _stage(d2[0], _base + Vector3(0, 0, -12))
	_sweep()
	var kdeep: float = GameManager.mass_push_mult(d0[0], GF, -1)
	verdict("A5 те же две конницы по трём отрядам вглубь — ×%.2f (не сдвинут)" % kdeep, kdeep < 0.8)

func _block_b() -> void:
	print("\n═════ B. УДАР ПЕРВЫХ СЕКУНД ═════")
	await _clean()
	var t: Array = _squad("spearman", F, _base, 60, 10, 0.6)
	var g: Array = _squad("goblin_spearman", GF, _base + Vector3(0, 0, 4), 100, 10, 0.7, 1.0)
	_freeze(t[1]); _freeze(g[1])
	GameManager._mass_contact.clear()
	_stage(t[0], _base); _stage(g[0], _base + Vector3(0, 0, 6))
	_sweep()
	var k0: float = GameManager.mass_push_mult(t[0], GF, g[0])
	var t0: int = Unit.game_ms()
	while Unit.game_ms() - t0 < int((GameManager.MASS_IMPACT_SEC + 1.0) * 1000.0):
		await pframes(10)
		_stage(t[0], _base); _stage(g[0], _base + Vector3(0, 0, 6))
		_sweep()
	var k6: float = GameManager.mass_push_mult(t[0], GF, g[0])
	verdict("B1 в момент удара толчок ×%.2f" % k0, k0 > 1.4)
	verdict("B2 через %.0f с удар погас (×%.2f)" % [GameManager.MASS_IMPACT_SEC + 1.0, k6], absf(k6 - 1.0) < 0.05)
	_Opt.mass_impact = false
	GameManager._mass_contact.clear()
	_sweep()
	var koff: float = GameManager.mass_push_mult(t[0], GF, g[0])
	_Opt.mass_impact = true
	verdict("B0 без ручки — удара нет (×%.2f)" % koff, absf(koff - 1.0) < 0.05)

# ═════════════════════════════════════════════════════════════════════════════
## Живой бой бессмертных: на сколько отъехала передняя шеренга копейщиков
func _live(n_goblin_squads: int, knob: bool) -> float:
	await _clean()
	_Opt.mass_push = knob
	var t: Array = _squad("spearman", F, _base, 30, 10, 0.6)
	for m in t[1]:
		_immortal(m)
		(m as Unit)._facing = Vector3(0, 0, 1)
	var gs: Array = []
	var xs: Array = [0.0, -6.5, 6.5]
	for i in range(n_goblin_squads):
		var g: Array = _squad("goblin_spearman", GF, _base + Vector3(xs[i], 0, 3.0), 30, 6, 0.8, 1.0)
		for m in g[1]:
			_immortal(m)
		gs.append(g)
	await pframes(5)
	var z0 := 0.0
	for m in t[1]:
		z0 += (m as Node3D).global_position.z
	z0 /= float(t[1].size())
	for g in gs:
		for m in g[1]:
			(m as Unit).command_attack(t[1][randi() % t[1].size()], true)
	await pframes(60 * 15)
	var z1 := 0.0
	for m in t[1]:
		z1 += (m as Node3D).global_position.z
	z1 /= float(t[1].size())
	_Opt.mass_push = true
	return z0 - z1

func _block_c() -> void:
	print("\n═════ C. ЖИВОЙ ЗАМЕР: ОДИН ОТРЯД И КУЛАК ═════")
	var one: float = await _live(1, true)
	var fist: float = await _live(3, true)
	print("    отъехали: от одного %.2f м, от кулака %.2f м" % [one, fist])
	# Сдвиг строя назад (плюс) или вперёд (минус): копейщики в «Атаке» сами
	# шагают на врага — меряется разница «кулак минус один»
	verdict("C1 кулак из трёх отрядов отодвинул строй дальше (%.2f против %.2f м)" % [fist, one],
		fist - one > 0.5)
	var one0: float = await _live(1, false)
	var fist0: float = await _live(3, false)
	print("    без ручки: от одного %.2f м, от кулака %.2f м" % [one0, fist0])
	verdict("C0 без ручки кулак толкает не сильнее суммы касаний (%.2f / %.2f против %.2f / %.2f)" % [fist0, one0, fist, one],
		(fist0 - one0) < (fist - one) - 0.4)
