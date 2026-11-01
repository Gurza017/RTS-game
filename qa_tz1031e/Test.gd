extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tz1031e — МЕЧНИКИ И «ВОЛЬНО» (ТЗ 31.10.2026, второе письмо)
## ═══════════════════════════════════════════════════════════════════════════
##   A ЩИТ ПО ДЕЛУ — в покое и на бегу рывка щит опущен; обстрел (стрелы и
##          кости гноллов) поднимает его, урон −70 %, обстрел кончился —
##          опущен (warrior_shield_dynamic; A0).
##   B РУКОПАШНАЯ — между ударами под щитом, после серии открыт: доля времени
##          под щитом в рубке между четвертью и девятью десятыми
##          (warrior_melee_guard; B0).
##   C СТЕНА ЩИТОВ — «Защита»: −80 % стали и стрел, удары втрое реже
##          (warrior_shield_wall; C0).
##   D ВОЛЬНО — отряд копейщиков в «Атаке» берёт целью чужой отряд ВЕСЬ, за
##          5 м до цели — рывок ×1.4, удар рывка ускоряет звуки боя
##          (ease_squad_engage, ease_rush, clash_audio_boost; D0).
##   E СТЕНА ЩИТОВ СМЫКАЕТ РЯДЫ — «Защита» сжимает строй мечников к передней
##          шеренге, выход из «Защиты» разжимает (warrior_wall_tight; E0).
## Запуск: godot --headless --path . res://qa_tz1031e/Test.tscn [-- only=abcde]

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN
const _Opt := preload("res://scripts/perf_config.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _base: Vector3 = Vector3.ZERO
var _only: String = "abcde"

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
	print("\n═════ ИТОГ qa_tz1031e: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

## Строй: колонки по X, ряды по −Z от точки at
func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int, sp: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0, at.z - float(i / cols) * sp))
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

func _face(men: Array, d: Vector3) -> void:
	for m in men:
		(m as Unit)._facing = d
		(m as Unit)._flip_dirty = true

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h := 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for dz in [-20.0, 0.0, 20.0]:
				for dx in [-20.0, 0.0, 20.0]:
					var q: Vector3 = p + Vector3(dx, 0.0, dz)
					h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
					if GameManager.is_water(q.x, q.z) or not GameManager.is_passable(q.x, q.z):
						h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

func _clean() -> void:
	main._clear_area_of_resources(_base, 50.0)
	main._clear_trees(_base, 50.0)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead() \
				and (u as Node3D).global_position.distance_to(_base) < 60.0:
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
	if "d" in _only: await _block_d()
	if "e" in _only: await _block_e()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _ratio(w: Unit, foe: Node3D) -> float:
	w._threat_until_ms = Unit.game_ms() + 5000
	w._update_guard()
	var on: float = w._incoming_damage_factor(foe)
	w._threat_until_ms = 0
	w._update_guard()
	var off: float = w._incoming_damage_factor(foe)
	return on / maxf(off, 1e-6)

func _block_a() -> void:
	print("\n═════ A. ЩИТ ПО ДЕЛУ ═════")
	await _clean()
	var w: Unit = _spawn("warrior", F, _base)
	_immortal(w)
	_face([w], Vector3(0, 0, 1))
	var ar: Unit = _spawn("archer", GF, _base + Vector3(0, 0, 15))
	var gn: Unit = _spawn("gnoll", GF, _base + Vector3(3, 0, 15))
	ar.set_tick(false)
	gn.set_tick(false)
	await pframes(30)
	verdict("A1 в покое щит опущен", not w.is_guarding())
	w.notify_incoming_fire(ar.global_position)
	w._update_guard()
	verdict("A2 обстрел поднимает щит", w.is_guarding())
	await pframes(int(float(w.GUARD_HOLD_MS) / 1000.0 * 60.0) + 40)
	verdict("A3 обстрел кончился — щит опущен", not w.is_guarding())
	var ra: float = _ratio(w, ar)
	var rg: float = _ratio(w, gn)
	verdict("A4 под щитом стрела ×%.2f, кость гнолла ×%.2f (остаётся 30 %%)" % [ra, rg],
		absf(ra - 0.30) < 0.02 and absf(rg - 0.30) < 0.02)
	# Рывок без цели рядом — бег без щита
	w._rage_left = 5
	w._rage_until_ms = Unit.game_ms() + 5000
	w._update_guard()
	var rush_guard: bool = w.is_guarding()
	verdict("A5 на бегу рывка (до цели далеко) щит опущен", not rush_guard)
	_Opt.warrior_shield_dynamic = false
	w._update_guard()
	var rush0: bool = w.is_guarding()
	w._rage_left = 0
	w._rage_until_ms = 0
	var rg0: float = _ratio(w, gn)
	_Opt.warrior_shield_dynamic = true
	verdict("A0 без ручки — рывок под щитом (%s), кость как сталь ×%.2f" % [str(rush0), rg0],
		rush0 and absf(rg0 - 0.50) < 0.02)

# ═════════════════════════════════════════════════════════════════════════════
func _melee_share(knob: bool) -> Array:
	await _clean()
	_Opt.warrior_melee_guard = knob
	var us: Array = _squad("warrior", F, _base, 8, 4, 0.9)
	var them: Array = _squad("goblin_spearman", GF, _base + Vector3(0, 0, 2.6), 8, 4, 0.9)
	for m in us[1]: _immortal(m)
	for m in them[1]: _immortal(m)
	_face(us[1], Vector3(0, 0, 1))
	_face(them[1], Vector3(0, 0, -1))
	GameManager.squad_attack_squad(int(us[0]), int(them[0]), true)
	GameManager.squad_attack_squad(int(them[0]), int(us[0]), true)
	var opens0 := 0
	for m in us[1]: opens0 += int(m.get("melee_opens"))
	await pframes(120)
	var seen := 0
	var guarded := 0
	for i in range(60):
		await pframes(6)
		for m in _alive(us[1]):
			var u := m as Unit
			if u.state == Unit.State.ATTACKING:
				seen += 1
				if u.is_guarding():
					guarded += 1
	var opens := 0
	for m in us[1]: opens += int(m.get("melee_opens"))
	_Opt.warrior_melee_guard = true
	return [float(guarded) / float(maxi(seen, 1)), opens - opens0, seen]

func _block_b() -> void:
	print("\n═════ B. ЩИТ В РУКОПАШНОЙ ═════")
	var r: Array = await _melee_share(true)
	verdict("B1 в рубке под щитом %.0f %% времени (замеров %d), открывался после серии %d раз" % [
		float(r[0]) * 100.0, int(r[2]), int(r[1])],
		float(r[0]) >= 0.25 and float(r[0]) <= 0.9 and int(r[1]) > 0 and int(r[2]) > 50)
	var r0: Array = await _melee_share(false)
	verdict("B0 без ручки — в рубке без щита (%.0f %%)" % (float(r0[0]) * 100.0), float(r0[0]) < 0.1)

# ═════════════════════════════════════════════════════════════════════════════
func _block_c() -> void:
	print("\n═════ C. СТЕНА ЩИТОВ ═════")
	await _clean()
	var w: Unit = _spawn("warrior", F, _base)
	_immortal(w)
	_face([w], Vector3(0, 0, 1))
	var ar: Unit = _spawn("archer", GF, _base + Vector3(0, 0, 15))
	var sp: Unit = _spawn("goblin_spearman", GF, _base + Vector3(0, 0, 1.5))
	ar.set_tick(false)
	sp.set_tick(false)
	w.stance = "defense"
	w._refresh_stance_cache()
	w._update_guard()
	verdict("C1 в «Защите» щит поднят", w.is_guarding())
	var m_on: float = w._incoming_damage_factor(sp)
	var a_on: float = w._incoming_damage_factor(ar)
	var c_on: float = w._effective_cooldown()
	_Opt.warrior_shield_wall = false
	var m_off: float = w._incoming_damage_factor(sp)
	var a_off: float = w._incoming_damage_factor(ar)
	var c_off: float = w._effective_cooldown()
	_Opt.warrior_shield_wall = true
	# Без стены: сталь ×0.5, стрела ×0.3 → со стеной обе ×0.2
	verdict("C2 сталь ×%.2f от прежних ×0.5 (стена −80 %%)" % (m_on / m_off * 0.5),
		absf(m_on / m_off * 0.5 - 0.20) < 0.02)
	verdict("C3 стрела ×%.2f от прежних ×0.3" % (a_on / a_off * 0.3), absf(a_on / a_off * 0.3 - 0.20) < 0.02)
	verdict("C4 удары реже в %.1f раза" % (c_on / c_off), absf(c_on / c_off - w.WALL_CD_MULT) < 0.05)
	verdict("C0 без ручки — прежние −50 %% стали (отношение %.2f)" % (m_off / m_on), m_off > m_on * 2.0)

# ═════════════════════════════════════════════════════════════════════════════
func _ease(knob: bool) -> Dictionary:
	await _clean()
	_Opt.ease_squad_engage = knob
	_Opt.ease_rush = knob
	_Opt.clash_audio_boost = knob
	AudioManager._clash_next_ms = 0
	var us: Array = _squad("spearman", F, _base, 12, 4, 1.0)
	var them: Array = _squad("goblin_spearman", GF, _base + Vector3(0, 0, 6.5), 12, 4, 1.0)
	for m in them[1]:
		_immortal(m)
		(m as Unit).set_tick(false)
	for m in us[1]:
		(m as Unit).stance = "attack"
		(m as Unit)._refresh_stance_cache()
	_face(us[1], Vector3(0, 0, 1))
	var e0: int = GameManager.ease_engages
	var cb0: int = AudioManager.clash_boosts
	var rushed: Dictionary = {}
	var ratio_max := 0.0
	for i in range(240):
		await pframes(1)
		for m in _alive(us[1]):
			var u := m as Unit
			if u.ease_rushing():
				rushed[u.get_instance_id()] = true
				ratio_max = maxf(ratio_max, u._effective_speed() / maxf(u._base_speed(), 0.01))
	var on_squad := 0
	for m in _alive(us[1]):
		var t = (m as Unit).attack_target
		if t != null and is_instance_valid(t) and t is Unit and (t as Unit).squad_id == int(them[0]):
			on_squad += 1
	var hits := 0
	for m in us[1]:
		if is_instance_valid(m):
			hits += int(m.get("ease_rush_hits"))
	_Opt.ease_squad_engage = true
	_Opt.ease_rush = true
	_Opt.clash_audio_boost = true
	return {"eng": GameManager.ease_engages - e0, "on": on_squad, "n": _alive(us[1]).size(),
		"rushed": rushed.size(), "ratio": ratio_max, "hits": hits, "boost": AudioManager.clash_boosts - cb0}

## Медиана расстояния до ближайшего соседа
func _nn(pts: Array) -> float:
	var ds: Array = []
	for i in range(pts.size()):
		var best := INF
		for j in range(pts.size()):
			if i != j:
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[j]
				best = minf(best, Vector2(a.x - b.x, a.z - b.z).length())
		ds.append(best)
	ds.sort()
	return float(ds[ds.size() / 2]) if not ds.is_empty() else 0.0

func _men_pos(men: Array) -> Array:
	var out: Array = []
	for m in _alive(men):
		out.append((m as Node3D).global_position)
	return out

func _front_z(pts: Array) -> float:
	var z := -INF
	for p in pts:
		z = maxf(z, (p as Vector3).z)
	return z

func _set_stance(sid: int, men: Array, st: String) -> void:
	for m in _alive(men):
		(m as Unit).set_stance(st)
	GameManager.on_squad_stance(sid, st)

func _wall(knob: bool) -> Dictionary:
	await _clean()
	_Opt.warrior_wall_tight = knob
	var sq: Array = _squad("warrior", F, _base, 24, 6, 0.6)
	var sid: int = int(sq[0])
	var men: Array = sq[1]
	_face(men, Vector3(0, 0, 1))
	var slots: Array = []
	for m in men:
		slots.append((m as Node3D).global_position)
	GameManager.squad_set_formation(sid, slots, Vector3(0, 0, 1), false)
	for m in men:
		(m as Unit).hold_post((m as Node3D).global_position, Vector3(0, 0, 1))
	await pframes(10)
	var p0: Array = _men_pos(men)
	var t0: int = GameManager.wall_tightens
	_set_stance(sid, men, "defense")
	await pframes(240)
	var p1: Array = _men_pos(men)
	var s1: Array = (GameManager.squads[sid] as Dictionary).get("slots", [])
	_set_stance(sid, men, "attack")
	await pframes(240)
	var p2: Array = _men_pos(men)
	_Opt.warrior_wall_tight = true
	return {"nn0": _nn(p0), "nn1": _nn(p1), "nn2": _nn(p2), "slot1": _nn(s1),
		"f0": _front_z(p0), "f1": _front_z(p1), "tight": GameManager.wall_tightens - t0}

func _block_e() -> void:
	print("\n═════ E. СТЕНА ЩИТОВ СМЫКАЕТ РЯДЫ ═════")
	var r: Dictionary = await _wall(true)
	print("    ", r)
	verdict("E1 разметка «Защиты» плотнее: шаг мест %.2f м (было %.2f)" % [r["slot1"], r["nn0"]],
		int(r["tight"]) == 1 and float(r["slot1"]) < float(r["nn0"]) - 0.08)
	verdict("E2 бойцы сомкнулись: сосед в %.2f м (было %.2f), не ближе разведения" % [r["nn1"], r["nn0"]],
		float(r["nn1"]) < float(r["nn0"]) - 0.06 and float(r["nn1"]) >= Unit.SEP_MIN_DIST - 0.03)
	verdict("E3 передняя шеренга на месте (сдвиг %.2f м)" % (float(r["f1"]) - float(r["f0"])),
		absf(float(r["f1"]) - float(r["f0"])) < 0.2)
	verdict("E4 выход из «Защиты» разжал строй: сосед в %.2f м" % r["nn2"],
		float(r["nn2"]) > float(r["nn1"]) + 0.06)
	var r0: Dictionary = await _wall(false)
	print("    ", r0)
	verdict("E0 без ручки — строй не сжимается (сосед %.2f → %.2f м)" % [r0["nn0"], r0["nn1"]],
		int(r0["tight"]) == 0 and absf(float(r0["nn1"]) - float(r0["nn0"])) < 0.05)

func _block_d() -> void:
	print("\n═════ D. ВОЛЬНО: ОТРЯДОМ И С РЫВКОМ ═════")
	var r: Dictionary = await _ease(true)
	print("    ", r)
	verdict("D1 весь отряд взял целью чужой отряд (%d из %d, решений %d)" % [r["on"], r["n"], r["eng"]],
		int(r["eng"]) >= 1 and int(r["on"]) >= int(r["n"]) - 1)
	verdict("D2 рывок: бежали %d бойцов, шаг ×%.2f, ударов с рывка %d" % [r["rushed"], r["ratio"], r["hits"]],
		int(r["rushed"]) >= 3 and absf(float(r["ratio"]) - Unit.EASE_RUSH_MULT) < 0.15 and int(r["hits"]) >= 1)
	verdict("D3 удар строя ускорил звуки боя (%d)" % r["boost"], int(r["boost"]) >= 1)
	var r0: Dictionary = await _ease(false)
	print("    ", r0)
	verdict("D0 без ручек — решений отряда нет, рывка нет, звук не ускорен",
		int(r0["eng"]) == 0 and int(r0["rushed"]) == 0 and int(r0["boost"]) == 0)
