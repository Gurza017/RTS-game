extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: АВТОНОМНЫЙ МОНАХ (ТЗ 16.09.2026), headless
## ═══════════════════════════════════════════════════════════════════════════
##   A ВЫБОР    — свободный монах выбирает САМЫЙ ПОБИТЫЙ отряд в ауре 20 м
##   B ФРОНТ    — нет раненых в ауре → один скан по карте и марш к ближайшему
##                своему отряду на ~10 м
##   C ДРЕМОТА  — некого лечить и не к кому идти → редкий скан, ноль приказов
##   D ПРИКАЗ   — ПКМ по отряду перебивает автономию; вылечен и укомплектован
##                → возврат в автономию
##   E МАССОВЫЙ — «Троичный поток» лечит троих за такт, VFX на КАЖДОМ
##   F ПОДЪЁМ   — павший встаёт в свободный слот разметки своего отряда
##   G ОТХОД    — под ударом уходит ~10 м К СВОИМ, потом лечит снова
##   H ЦЕНА     — сканов и тактов в секунду у стоящего монаха
## Числа — из unit_stats_config (правило 10), время — физкадрами (правило 11).

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const F := Constants.FACTION_PLAYER

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(420.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_monk_auto: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 4) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x - float(i / cols) * 0.8, 0.0,
			at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _wound(u: Unit, frac: float) -> void:
	u.current_health = u.max_health * frac
	u._soa_push_stats()

func _kill_all(men: Array) -> void:
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			c += (u as Unit).global_position
			n += 1
	return c / float(maxi(n, 1))

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(14.0, 0.0, 0.0), Vector3(-14.0, 0.0, 0.0), Vector3(0.0, 0.0, 8.0), Vector3(30.0, 0.0, 0.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
			if GameManager.is_water(p.x, p.z) or GameManager.is_water(p.x + 30.0, p.z):
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
	# Дикие (стражи пней, гноллы, патрули) на площадку не заходят: их тик снят
	# (17.09.2026: патруль тролля добрался до монаха в блоке B — правило 5 на
	# freed-монахе и 20 м «дрожания» в C были им, а не кодом)
	for n in get_tree().get_nodes_in_group("all_units"):
		var wu := n as Unit
		if wu != null and wu.faction != F:
			wu.set_tick(false)
	var base: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 30.0))
	main._clear_area_of_resources(base, 60.0)
	await _a_pick(base)
	await _b_front(base + Vector3(0.0, 0.0, 60.0))
	await _c_idle(base + Vector3(-60.0, 0.0, 0.0))
	await _d_order(base + Vector3(60.0, 0.0, 0.0))
	await _e_multi(base + Vector3(0.0, 0.0, -60.0))
	await _f_revive(base + Vector3(60.0, 0.0, 60.0))
	await _g_retreat(base + Vector3(-60.0, 0.0, 60.0))
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ВЫБОР САМОГО ПОБИТОГО ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _a_pick(base: Vector3) -> void:
	print("\n═════ A. ВЫБОР САМОГО ПОБИТОГО ОТРЯДА ═════")
	var monk: Unit = _spawn("monk", F, base)
	# Три отряда в ауре: слегка (90 %), средне (60 %), сильно (30 %) побитые.
	# Сильно побитый — дальше всех, чтобы «ближайший» и «самый побитый» разошлись
	var light: Array = _squad("spearman", F, base + Vector3(5.0, 0.0, 0.0), 8)
	var mid: Array = _squad("spearman", F, base + Vector3(-9.0, 0.0, 6.0), 8)
	var heavy: Array = _squad("spearman", F, base + Vector3(14.0, 0.0, -8.0), 8)
	for u in light[1]: _wound(u, 0.9)
	for u in mid[1]: _wound(u, 0.6)
	for u in heavy[1]: _wound(u, 0.3)
	await pframes(int(_UCfg.MONK_SCAN_SEC * 60.0) + 20)
	var psid: int = int(monk.get("patient_sid"))
	verdict("A1 отряд-пациент — самый побитый, а не ближайший",
		psid == int(heavy[0]),
		"пациент sid %d (побитый %d, средний %d, лёгкий %d)" % [psid, int(heavy[0]), int(mid[0]), int(light[0])])
	# ТЗ 17.09.2026: каст — из любой точки ауры, к отряду В АУРЕ монах не
	# идёт вовсе (границу ауры и подход к дальнему стережёт qa_monk_fix A)
	var p_a: Vector3 = monk.global_position
	var drift_a := 0.0
	for _i in range(60 * 6):
		await get_tree().physics_frame
		drift_a = maxf(drift_a, _xz(monk.global_position, p_a))
	verdict("A2 к отряду в ауре монах не идёт: лечит с места (сдвиг < 1 м за 6 с)", drift_a < 1.0,
		"сдвиг %.2f м, до центра %.1f м (каст %.1f)" % [drift_a, _xz(monk.global_position, _centre(heavy[1])), float(monk.call("cast_range"))])
	var hp0: float = 0.0
	for u in heavy[1]: hp0 += (u as Unit).current_health
	await pframes(int(_UCfg.MONK_SCAN_SEC * 60.0 * 3.0))
	var hp1: float = 0.0
	for u in heavy[1]: hp1 += (u as Unit).current_health
	verdict("A3 лечит именно его", hp1 > hp0 + 1.0, "запас отряда %.0f → %.0f" % [hp0, hp1])
	verdict("A4 радиус ауры — 20 м (heal_radius)",
		absf(monk.call("heal_radius") - _UCfg.MONK_AURA_R) < 0.01,
		"%.1f м" % monk.call("heal_radius"))
	monk.take_damage(1e12)
	for s in [light, mid, heavy]: _kill_all(s[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. НЕТ РАНЕНЫХ — МАРШ К ФРОНТУ
# ═════════════════════════════════════════════════════════════════════════════
func _b_front(base: Vector3) -> void:
	print("\n═════ B. МАРШ К ФРОНТУ ═════")
	var monk: Unit = _spawn("monk", F, base)
	# Целый отряд за пределами ауры (32 м) — монах идёт к нему на ~10 м
	var sq: Array = _squad("warrior", F, base + Vector3(32.0, 0.0, 0.0), 8)
	var d0: float = _xz(monk.global_position, _centre(sq[1]))
	var best: float = d0
	for _i in range(60 * 25):
		await get_tree().physics_frame
		best = minf(best, _xz(monk.global_position, _centre(sq[1])))
		if best <= float(monk.call("stand_dist")) + 1.5:
			break
	verdict("B1 монах выдвинулся к ближайшему своему отряду",
		best < d0 - 5.0, "было %.1f, стало %.1f м" % [d0, best])
	# ТЗ 17.09.2026: у фронта монах встаёт на границе ауры (stand_dist =
	# MONK_STAND_FRAC × радиус), снаружи строя
	var sd: float = float(monk.call("stand_dist"))
	verdict("B2 держится в ~%.0f м от отряда (граница ауры), а не лезет в строй" % sd,
		best >= sd - 4.0 and best <= sd + 4.0,
		"ближайшая дистанция %.1f м" % best)
	var fm: int = int(monk.get("front_moves"))
	await pframes(60 * 6)
	verdict("B3 у фронта стоит, приказов не сыплет (≤ 2 за 6 с)",
		int(monk.get("front_moves")) - fm <= 2,
		"приказов марша %d" % (int(monk.get("front_moves")) - fm))
	monk.take_damage(1e12)
	_kill_all(sq[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ДРЕМОТА: НЕКОГО ЛЕЧИТЬ, НЕ К КОМУ ИДТИ
# ═════════════════════════════════════════════════════════════════════════════
func _c_idle(base: Vector3) -> void:
	print("\n═════ C. ДРЕМОТА ═════")
	var monk: Unit = _spawn("monk", F, base)
	await pframes(60 * 3)
	var sc0: int = int(monk.get("scans"))
	var mv0: int = int(monk.get("front_moves")) + int(monk.get("retreats"))
	var p0: Vector3 = monk.global_position
	await pframes(60 * 10)
	var per_sec: float = float(int(monk.get("scans")) - sc0) / 10.0
	verdict("C1 стоящий монах сканирует ≤ 1 раза в секунду", per_sec <= 1.0,
		"%.2f сканов/с" % per_sec)
	verdict("C2 приказов движения ноль",
		int(monk.get("front_moves")) + int(monk.get("retreats")) == mv0)
	verdict("C3 не дёргается: сдвиг < 0.1 м за 10 с",
		_xz(monk.global_position, p0) < 0.1, "%.3f м" % _xz(monk.global_position, p0))
	# Появился раненый рядом — заметил без приказа и удара
	var w: Unit = _spawn("spearman", F, base + Vector3(3.0, 0.0, 0.0))
	_wound(w, 0.4)
	var hp0: float = w.current_health
	await pframes(int((_UCfg.MONK_SCAN_SEC + 1.5) * 60.0) + int(_UCfg.MONK_SCAN_SEC * 60.0) + 30)
	verdict("C4 раненого рядом заметил из дремоты", w.current_health > hp0 + 0.5,
		"%.0f → %.0f" % [hp0, w.current_health])
	monk.take_damage(1e12)
	w.take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. ПРИКАЗ ИГРОКА ПЕРЕБИВАЕТ АВТОНОМИЮ
# ═════════════════════════════════════════════════════════════════════════════
func _d_order(base: Vector3) -> void:
	print("\n═════ D. ПРИКАЗ ПКМ ═════")
	var monk: Unit = _spawn("monk", F, base)
	var heavy: Array = _squad("spearman", F, base + Vector3(6.0, 0.0, 0.0), 8)
	var light: Array = _squad("spearman", F, base + Vector3(-12.0, 0.0, 4.0), 8)
	for u in heavy[1]: _wound(u, 0.3)
	for u in light[1]: _wound(u, 0.8)
	await pframes(int(_UCfg.MONK_SCAN_SEC * 60.0) + 20)
	verdict("D0 автономно взят побитый отряд", int(monk.get("patient_sid")) == int(heavy[0]))
	# ПКМ по ЛЁГКОМУ отряду — приказ перебивает
	monk.call("command_heal", light[1][0])
	await pframes(10)
	verdict("D1 приказ ПКМ сразу переключил пациента на указанный отряд",
		int(monk.get("patient_sid")) == int(light[0]),
		"пациент %d, указан %d" % [int(monk.get("patient_sid")), int(light[0])])
	var done := false
	var t := 0
	while t < 60 * 60:
		await get_tree().physics_frame
		t += 1
		var full := true
		for u in light[1]:
			if (u as Unit).current_health < (u as Unit).max_health - 0.01:
				full = false
				break
		if full:
			done = true
			break
	verdict("D2 указанный отряд вылечен целиком", done, "за %d физкадров" % t)
	await pframes(int(_UCfg.MONK_SCAN_SEC * 60.0) * 2 + 20)
	verdict("D3 приказ исполнен — приказ снят, монах снова в автономии",
		int(monk.get("_order_sid")) == 0 and int(monk.get("patient_sid")) == int(heavy[0]),
		"order_sid %d, пациент %d (ждём %d)" % [int(monk.get("_order_sid")), int(monk.get("patient_sid")), int(heavy[0])])
	monk.take_damage(1e12)
	_kill_all(heavy[1]); _kill_all(light[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. МАССОВЫЙ ТАКТ И VFX НА КАЖДОМ
# ═════════════════════════════════════════════════════════════════════════════
func _e_multi(base: Vector3) -> void:
	print("\n═════ E. МАССОВЫЙ ТАКТ (Троичный поток 1d) ═════")
	GameManager.researched.erase(F)
	for cell in ["1a", "1b", "1c", "1d"]:
		GameManager.finish_research(F, "monk_" + cell)
	var monk: Unit = _spawn("monk", F, base)
	var sq: Array = _squad("spearman", F, base + Vector3(2.0, 0.0, 0.0), 6, 3)
	for u in sq[1]: _wound(u, 0.5)
	verdict("E0 потолок целей за такт — 3 (1d)", int(monk.call("max_heal_targets")) == 3,
		"%d" % int(monk.call("max_heal_targets")))
	var peak := 0
	var vfx_peak := 0
	for _i in range(60 * 8):
		await get_tree().physics_frame
		var ht: Array = monk.get("heal_targets")
		peak = maxi(peak, ht.size())
		var vis := 0
		if monk.call("heal_vfx_target") != null:
			vis += 1
		for q in monk.get("_extra_vfx"):
			if is_instance_valid(q) and (q as MeshInstance3D).visible:
				vis += 1
		vfx_peak = maxi(vfx_peak, vis)
	verdict("E1 за такт лечатся трое", peak == 3, "пик целей %d" % peak)
	verdict("E2 VFX горит на каждом лечимом (3 квада)", vfx_peak >= 3, "пик видимых квадов %d" % vfx_peak)
	monk.take_damage(1e12)
	_kill_all(sq[1])
	GameManager.researched.erase(F)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# F. ВОСКРЕШЕНИЕ В СЛОТ РАЗМЕТКИ
# ═════════════════════════════════════════════════════════════════════════════
func _f_revive(base: Vector3) -> void:
	print("\n═════ F. ПОДЪЁМ ПАВШЕГО В СЛОТ ═════")
	GameManager.researched.erase(F)
	for cell in ["1a", "1b", "1c", "1d", "2a", "2b", "2c", "2d"]:
		GameManager.finish_research(F, "monk_" + cell)
	var monk: Unit = _spawn("monk", F, base)
	var sq: Array = _squad("spearman", F, base + Vector3(3.0, 0.0, 0.0), 8)
	# Разметка отряда — как после приказа игрока
	for u in sq[1]:
		(u as Unit).command_move((u as Unit).global_position, false, Vector3.FORWARD)
	GameManager.squad_close_ranks(int(sq[0]), true)
	await pframes(20)
	verdict("F0 воскрешение изучено (2d)", bool(monk.call("can_resurrect")))
	var victim: Unit = sq[1][2]
	var vpos: Vector3 = victim.global_position
	victim.take_damage(1e12)
	await pframes(5)
	var raised: Unit = null
	for _i in range(60 * 40):
		await get_tree().physics_frame
		var rt: int = int(monk.get("resurrected_total"))
		if rt > 0:
			for m in GameManager.squad_members(int(sq[0])):
				if m != victim and not (m as Unit).is_dead() and not sq[1].has(m):
					raised = m
			break
	verdict("F1 павший поднят", raised != null, "поднято %d" % int(monk.get("resurrected_total")))
	if raised != null:
		verdict("F2 встал в свой отряд", raised.squad_id == int(sq[0]))
		var slots: Array = GameManager.squads[int(sq[0])].get("slots", [])
		var near_slot := 1e9
		for s in slots:
			near_slot = minf(near_slot, _xz(raised.global_position, s))
		verdict("F3 встал в слот разметки (ближе 1.5 м к свободному месту)",
			near_slot <= 1.5, "до ближайшего слота %.2f м (слотов %d)" % [near_slot, slots.size()])
	monk.take_damage(1e12)
	_kill_all(GameManager.squad_members(int(sq[0])))
	GameManager.researched.erase(F)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# G. ОТХОД ПОД УДАРОМ — К СВОИМ
# ═════════════════════════════════════════════════════════════════════════════
func _g_retreat(base: Vector3) -> void:
	print("\n═════ G. ОТХОД К СВОИМ ═════")
	var monk: Unit = _spawn("monk", F, base)
	monk.max_health = 1e9
	monk.current_health = 1e9
	# Свои — на +X в 14 м, обидчик — на −X вплотную
	var sq: Array = _squad("warrior", F, base + Vector3(14.0, 0.0, 0.0), 8)
	for u in sq[1]: _wound(u, 0.5)
	var foe: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, base + Vector3(-1.5, 0.0, 0.0))
	foe.set_tick(false)
	await pframes(10)
	var p0: Vector3 = monk.global_position
	monk.take_damage(5.0, foe)
	var moved := 0.0
	var toward := 0.0
	for _i in range(60 * 8):
		await get_tree().physics_frame
		var d: float = _xz(monk.global_position, p0)
		if d > moved:
			moved = d
			toward = monk.global_position.x - p0.x
	verdict("G1 отошёл на ~%.0f м" % _UCfg.MONK_RETREAT_DIST,
		moved >= _UCfg.MONK_RETREAT_DIST * 0.6, "%.1f м" % moved)
	verdict("G2 отход — В СТОРОНУ СВОИХ (+X), а не просто прочь", toward > 2.0,
		"сдвиг по X %.1f м" % toward)
	var hp0: float = 0.0
	for u in sq[1]: hp0 += (u as Unit).current_health
	await pframes(60 * 12)
	var hp1: float = 0.0
	for u in sq[1]: hp1 += (u as Unit).current_health
	verdict("G3 после отхода возобновил лечение своих", hp1 > hp0 + 1.0,
		"запас отряда %.0f → %.0f" % [hp0, hp1])
	monk.take_damage(1e12)
	_kill_all(sq[1])
	foe.take_damage(1e12)
	await pframes(3)
