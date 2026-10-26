extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 23.10.2026 (вечер): отклик, коробки, строй групп, дома, штандарты,
## приёмы, монах, тела, оборона базы ИИ
## ═══════════════════════════════════════════════════════════════════════════
##   A — перевод огня: лучники, стрелявшие по одной цели, на ПКМ по другой
##       стреляют сразу, а темп стрельбы за бой не растёт от частых кликов
##   B — коробки: каша после свалки ПКМ-кликом группы встаёт отрядами без
##       чужих соседей, посты разных отрядов не накладываются
##   C — строй группы Ctrl+N: схема переживает поворот курса и Attack-Move
##   D — дома: роскошь сверх 35 отрядов лимита
##   E — штандарты: награда ветеранства не даёт штандарта, реликвия даёт,
##       красный ИИ вручает его своему лучшему отряду из копилки
##   F — круг ауры и значки над отрядами в круге по выделению носителя
##   G — «Яростная атака»: откат на отряд, самозапуск в ближнем бою
##   H — [S] не замедляет марш
##   I — «Фаланга» встаёт сама под ударом, ручное отключение действует
##   J — монах: без кузницы один пациент, массовое лечение медленнее на 40 %
##   K — тела светлее и с подтоном своей стороны
##   L — охрана базы красного просыпается от удара по башне базы
##   M — значок [C] «Вольно» — картинка бойца, а не буква
## Зонд с числами «до/после» — Probe.tscn.
## Запуск: godot --headless --path . res://qa_tz1023/Test.tscn [-- only=abcdefghijklm]

const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _RCfg := preload("res://scripts/relic_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _TowerS := preload("res://scripts/Tower.gd")
var main: Node = null
var sm = null
var _pass := 0
var _fail := 0
var _only: String = "abcdefghijklmnopqrt"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_tz1023: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _staff(kind: String) -> Array:
	var bld: String = "archery" if kind == "archer" else "barracks"
	var cfg: Dictionary = _UCfg.train_cfg(bld, kind)
	return [int(cfg.get("squad", 20)), int(cfg.get("cols", 5))]

func _squad(uid: String, f: int, at: Vector3, n: int = -1, jitter: float = 0.0) -> int:
	var st: Array = _staff(uid)
	if n < 0: n = int(st[0])
	var cols: int = maxi(int(st[1]), 1)
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var p: Vector3 = at + Vector3(float(i / cols) * 0.65, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * 0.65)
		if jitter > 0.0:
			p += Vector3(randf_range(-jitter, jitter), 0.0, randf_range(-jitter, jitter))
		GameManager.add_to_squad(sid, _unit(uid, f, p))
	return sid

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _all(sids: Array) -> Array:
	var o: Array = []
	for s in sids:
		o.append_array(_members(int(s)))
	return o

func _wipe(at: Vector3, r: float) -> void:
	main._clear_area_of_resources(at, r)
	main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()

func _kill(sids: Array) -> void:
	for u in _all(sids):
		(u as Unit).take_damage(1.0e12)

func _spot(dx: float = 45.0, dz: float = 15.0) -> Vector3:
	return main.PLAYER_BASE_ANCHOR + Vector3(dx, 0.0, dz)

func _run() -> void:
	seed(4242)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	sm = main.selection_manager
	if "a" in _only: await _a_retarget()
	if "b" in _only: await _b_boxes()
	if "c" in _only: await _c_group_layout()
	if "d" in _only: _d_houses()
	if "e" in _only: await _e_banners()
	if "f" in _only: await _f_aura_view()
	if "g" in _only: await _g_rage()
	if "h" in _only: await _h_hold_speed()
	if "i" in _only: await _i_phalanx_auto()
	if "k" in _only: await _k_corpses()
	if "l" in _only: await _l_base_alarm()
	if "m" in _only: await _m_at_ease_icon()
	if "n" in _only: await _n_wide_am()
	if "o" in _only: await _o_deep_front()
	if "p" in _only: await _p_revive_frame()
	if "q" in _only: await _q_clash()
	if "r" in _only: _r_late_horde()
	if "t" in _only: await _t_forest_root()
	if "j" in _only: await _j_monk()      # последним: изучает узлы кузницы
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
# A. ПЕРЕВОД ОГНЯ
# ─────────────────────────────────────────────────────────────────────────────
func _order_attack(men: Array, target: Unit) -> void:
	sm.select_units(men)
	for u in men:
		(u as Unit).command_attack(target, true, true, true)

func _a_retarget() -> void:
	print("\n═════ A. ПЕРЕВОД ОГНЯ ═════")
	var spot: Vector3 = _spot()
	_wipe(spot, 45.0)
	await pframes(5)
	var mine: int = _squad("archer", F, spot)
	var f1: int = _squad("spearman", R, spot + Vector3(12.0, 0.0, -6.0))
	var f2: int = _squad("spearman", R, spot + Vector3(12.0, 0.0, 8.0))
	await pframes(10)
	for u in _all([f1, f2]):
		(u as Unit).set_tick(false)
		(u as Unit).max_health = 1.0e9
		(u as Unit).current_health = 1.0e9
	var men: Array = _members(mine)
	_order_attack(men, _members(f1)[0])
	await pframes(90)                     # первый залп ушёл, все перезаряжаются
	var a0: int = GameManager.arrows_fired
	_order_attack(men, _members(f2)[0])
	var t_first := -1.0
	for fr in range(240):
		await get_tree().physics_frame
		if GameManager.arrows_fired > a0:
			t_first = float(fr + 1) / 60.0
			break
	verdict("A1 по ПКМ на новую цель первая стрела не позже %.2f с" % (Unit.QUICK_RETARGET_SEC + 0.2),
		t_first > 0.0 and t_first <= Unit.QUICK_RETARGET_SEC + 0.2, "%.2f с" % t_first)
	# Темп за бой: 24 с без кликов против 24 с с переводом огня раз в 1.2 с
	await pframes(240)
	var b0: int = GameManager.arrows_fired
	await pframes(60 * 24)
	var calm: int = GameManager.arrows_fired - b0
	var c0: int = GameManager.arrows_fired
	for k in range(20):
		_order_attack(_members(mine), _members(f1 if k % 2 == 0 else f2)[0])
		await pframes(72)
	var busy: int = GameManager.arrows_fired - c0
	verdict("A2 частые клики темп стрельбы не поднимают (долг перезарядки)",
		calm > 0 and float(busy) <= float(calm) * 1.15 + 3.0, "без кликов %d, с кликами %d стрел" % [calm, busy])
	_kill([mine, f1, f2])
	await pframes(30)

# ─────────────────────────────────────────────────────────────────────────────
# B. КОРОБКИ
# ─────────────────────────────────────────────────────────────────────────────
func _foreign_share(men: Array, k: int = 4) -> float:
	var n: int = men.size()
	if n < k + 1:
		return 0.0
	var step: int = maxi(1, n / 200)
	var tot := 0
	var foreign := 0
	var i := 0
	while i < n:
		var u := men[i] as Unit
		var p: Vector3 = u.global_position
		var best: Array = []
		for j in range(n):
			if j == i: continue
			var v := men[j] as Unit
			var d2: float = (v.global_position - p).length_squared()
			if best.size() < k or d2 < float(best[best.size() - 1][0]):
				best.append([d2, v.squad_id])
				best.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
				if best.size() > k:
					best.resize(k)
		for b in best:
			tot += 1
			if int(b[1]) != u.squad_id:
				foreign += 1
		i += step
	return float(foreign) / float(maxi(tot, 1))

## Наложение постов разных отрядов: пары ближе шага строя
func _post_overlaps(men: Array) -> int:
	var n := 0
	for i in range(men.size()):
		var a: Unit = men[i]
		for j in range(i + 1, men.size()):
			var b: Unit = men[j]
			if a.squad_id == b.squad_id:
				continue
			if Vector2(a.post_pos.x - b.post_pos.x, a.post_pos.z - b.post_pos.z).length() < 0.5:
				n += 1
	return n

func _blob(spot: Vector3, kinds: Array) -> Array:
	var sids: Array = []
	for i in range(kinds.size()):
		var a: float = TAU * float(i) / float(kinds.size())
		var at: Vector3 = spot + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 7.0)
		sids.append(_squad(String(kinds[i]), F, at, -1, 2.5))
	return sids

func _b_boxes() -> void:
	print("\n═════ B. КОРОБКИ ВМЕСТО КАШИ ═════")
	var spot: Vector3 = _spot()
	var kinds := ["spearman", "archer", "warrior", "spearman", "archer", "spearman", "warrior", "spearman"]
	var res: Dictionary = {}
	for knob in [false, true]:
		_wipe(spot, 60.0)
		await pframes(5)
		_Opt.squad_boxes = knob
		var sids: Array = _blob(spot, kinds)
		await pframes(30)
		var men: Array = _all(sids)
		var before: float = _foreign_share(men)
		sm.select_units(men)
		sm._issue_formation_move(spot + Vector3(0.0, 0.0, 26.0), false)
		await pframes(3)
		var ov: int = _post_overlaps(men)
		var arrived := 0.0
		for _w in range(40):
			await pframes(60)
			var ok := 0
			for u in men:
				if Vector2((u as Unit).global_position.x - (u as Unit).post_pos.x,
						(u as Unit).global_position.z - (u as Unit).post_pos.z).length() < 1.2:
					ok += 1
			arrived = float(ok) / float(men.size())
			if arrived > 0.95:
				break
		res[knob] = {"before": before, "after": _foreign_share(men), "ov": ov, "arr": arrived}
		print("  коробки %s: чужих соседей в каше %.2f → после клика %.2f, наложений постов %d, на постах %.0f%%" % [
			"вкл" if knob else "выкл", before, float(res[knob]["after"]), ov, arrived * 100.0])
		_kill(sids)
		await pframes(30)
	_Opt.squad_boxes = true
	verdict("B1 после одного ПКМ-клика отряды стоят коробками (чужих соседей ≤ 0.05)",
		float(res[true]["after"]) <= 0.05, "%.2f (без коробок %.2f)" % [float(res[true]["after"]), float(res[false]["after"])])
	verdict("B2 посты разных отрядов не накладываются", int(res[true]["ov"]) == 0, "%d" % int(res[true]["ov"]))
	verdict("B3 приказ исполнен с первого раза (на постах ≥ 95 %)", float(res[true]["arr"]) >= 0.95,
		"%.0f%%" % (float(res[true]["arr"]) * 100.0))
	verdict("B4 без коробок каша переносилась бы как есть (стенд различает правку)",
		float(res[false]["after"]) > float(res[true]["after"]) + 0.15,
		"%.2f против %.2f" % [float(res[false]["after"]), float(res[true]["after"])])

# ─────────────────────────────────────────────────────────────────────────────
# C. СТРОЙ ГРУППЫ CTRL+N
# ─────────────────────────────────────────────────────────────────────────────
func _sq_centre(sid: int) -> Vector3:
	return GameManager._centroid_of(_members(sid))

func _post_centre(sid: int) -> Vector3:
	var acc := Vector3.ZERO
	var m: Array = _members(sid)
	for u in m:
		acc += (u as Unit).post_pos
	return acc / float(maxi(m.size(), 1))

func _c_group_layout() -> void:
	print("\n═════ C. СТРОЙ ГРУППЫ CTRL+N ═════")
	var spot: Vector3 = _spot()
	_wipe(spot, 70.0)
	await pframes(5)
	# «Пирог»: копейщики по центру впереди, лучники за ними, рыцари по флангам
	var sp: int = _squad("spearman", F, spot + Vector3(0, 0, 0))
	var ar: int = _squad("archer", F, spot + Vector3(-9, 0, 0))
	var k1: int = _squad("warrior", F, spot + Vector3(0, 0, -16))
	var k2: int = _squad("warrior", F, spot + Vector3(0, 0, 16))
	var sids := [sp, ar, k1, k2]
	await pframes(20)
	# Курс отрядов — на +X (вперёд); выстроить строем по месту
	for s in sids:
		var m: Array = _members(int(s))
		var slots: Array = []
		for u in m:
			slots.append((u as Unit).global_position)
		GameManager.squad_set_formation(int(s), slots, Vector3.RIGHT, false)
	var men: Array = _all(sids)
	sm.select_units(men)
	sm._save_group(0)
	var saved: Dictionary = sm._group_layouts[0]
	verdict("C0 Ctrl+1 запомнил схему всех четырёх отрядов", saved.size() == 4, "%d" % saved.size())
	# Приказ на север (курс −Z): «вперёд» схемы теперь −Z, фланги — по X
	sm._clear_selection()
	sm._recall_group(0)
	var dest: Vector3 = spot + Vector3(0, 0, -45)
	var u0: int = sm.group_layout_uses
	sm._issue_formation_move(dest, false)
	await pframes(3)
	var course: Vector3 = (dest - GameManager._centroid_of(men))
	course.y = 0.0
	course = course.normalized()
	var across := Vector3(-course.z, 0.0, course.x)
	var ok_order := true
	var txt := ""
	for s2 in sids:
		var lay: Vector2 = saved[int(s2)]
		var pc: Vector3 = _post_centre(int(s2)) - dest
		var got := Vector2(pc.dot(across), pc.dot(course))
		txt += " %d:(%.1f,%.1f)→(%.1f,%.1f)" % [int(s2), lay.x, lay.y, got.x, got.y]
	# Свойство схемы: порядок поперёк курса (фланги) и вдоль (кто впереди)
	var ax := {}
	var cy := {}
	for s3 in sids:
		var pc2: Vector3 = _post_centre(int(s3)) - dest
		ax[s3] = pc2.dot(across)
		cy[s3] = pc2.dot(course)
	for i in range(sids.size()):
		for j in range(sids.size()):
			if i == j: continue
			var li: Vector2 = saved[int(sids[i])]
			var lj: Vector2 = saved[int(sids[j])]
			if li.x < lj.x - 2.0 and not (float(ax[sids[i]]) < float(ax[sids[j]])):
				ok_order = false
			if li.y > lj.y + 2.0 and not (float(cy[sids[i]]) > float(cy[sids[j]])):
				ok_order = false
	verdict("C1 приказ группе с новым курсом держит схему (фланги и глубина)",
		ok_order and sm.group_layout_uses > u0, txt)
	# Схема сохраняется и после каши: отряды перемешаны — приказ раскладывает по схеме
	for s4 in sids:
		for u in _members(int(s4)):
			(u as Unit).global_position = spot + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)) + Vector3(0, 0, -45)
			(u as Unit).sync_row()
	await pframes(10)
	sm.select_units(_all(sids))
	var dest2: Vector3 = spot + Vector3(30, 0, -45)
	var n_am: int = sm._squad_cmd().attack_move(sm, dest2, false)
	await pframes(3)
	course = Vector3.RIGHT
	across = Vector3(-course.z, 0.0, course.x)
	var ok2 := true
	for i2 in range(sids.size()):
		for j2 in range(sids.size()):
			if i2 == j2: continue
			var li2: Vector2 = saved[int(sids[i2])]
			var lj2: Vector2 = saved[int(sids[j2])]
			var pi: Vector3 = _post_centre(int(sids[i2])) - dest2
			var pj: Vector3 = _post_centre(int(sids[j2])) - dest2
			if li2.x < lj2.x - 2.0 and not (pi.dot(across) < pj.dot(across)):
				ok2 = false
	verdict("C2 Attack-Move группы из каши раскладывает отряды по схеме Ctrl+1", ok2 and n_am > 0,
		"[A] отрядов %d" % n_am)
	_kill(sids)
	await pframes(30)

# ─────────────────────────────────────────────────────────────────────────────
# D. ДОМА
# ─────────────────────────────────────────────────────────────────────────────
func _d_houses() -> void:
	print("\n═════ D. ДОМА: РОСКОШЬ СВЕРХ 35 ОТРЯДОВ ═════")
	var per: float = float(_UCfg.squad_size("spearman"))
	var castles := 1
	var line := ""
	var ok_below := true
	var first_over := -1
	var at40 := -1.0
	var prev := 0.0
	var mono := true
	for h in range(0, 40):
		var after: float = float(_UCfg.pop_army_cap(h + 1, castles)) / per
		var lux: float = _UCfg.house_luxury_mult(h, castles)
		var total: float = _UCfg.building_cost_mult("house", h) * lux
		if after <= _UCfg.HOUSE_LUXURY_FROM and absf(lux - 1.0) > 1e-6:
			ok_below = false
		if after > _UCfg.HOUSE_LUXURY_FROM and first_over < 0:
			first_over = h
		if after >= _UCfg.HOUSE_LUXURY_STEEP_FROM and at40 < 0.0:
			at40 = lux
		if total + 1e-6 < prev:
			mono = false
		prev = total
		if h >= 18 and h <= 26:
			line += " %d-й→%.1f отр ×%.1f;" % [h + 1, after, total]
	print("  1 крепость:" + line)
	verdict("D1 дом, после которого лимит не выше 35 отрядов, — прежняя цена", ok_below)
	verdict("D2 сверх 35 отрядов цена дома растёт и не падает", first_over >= 0 and mono)
	verdict("D3 дом, открывающий 40 отрядов, — роскошь (≥ ×25 к прежнему закону)", at40 >= 25.0, "×%.0f" % at40)
	var over41: float = _UCfg.house_luxury_mult(first_over + 4, castles)
	verdict("D3б сверх 40 — астрономически (≥ ×500 к прежнему закону)", over41 >= 500.0, "×%.0f" % over41)
	var c_house: Dictionary = GameManager.build_cost_for(F, "house")
	verdict("D4 цена в игре идёт через закон роскоши (build_cost_for)",
		absf(GameManager.build_cost_mult_for(F, "house") - _UCfg.building_cost_mult("house", GameManager.house_total(F))
			* _UCfg.house_luxury_mult(GameManager.house_total(F), GameManager.castle_count(F))) < 1e-4 and not c_house.is_empty())

# ─────────────────────────────────────────────────────────────────────────────
# E. ШТАНДАРТЫ
# ─────────────────────────────────────────────────────────────────────────────
func _e_banners() -> void:
	print("\n═════ E. ШТАНДАРТЫ ═════")
	var spot: Vector3 = _spot()
	_wipe(spot, 40.0)
	await pframes(5)
	var a: int = _squad("spearman", F, spot)
	var b: int = _squad("spearman", F, spot + Vector3(0, 0, 10))
	await pframes(5)
	var sq: Dictionary = GameManager.squads[a]
	sq["pending"] = int(sq.get("pending", 0)) + 1
	sq["level"] = maxi(int(sq.get("level", 0)), 1)
	var picked: bool = GameManager.apply_veteran_choice(a, 0)
	verdict("E1 награда ветеранства (как у ИИ и найма ветеранов) штандарта не даёт",
		picked and not GameManager.squad_elite(a), "выбрана %s, элита %s" % [picked, GameManager.squad_elite(a)])
	var rm: Node = GameManager.relic_mgr()
	var r_id: int = rm.grant_to_squad(b, true)
	verdict("E2 реликвия из копилки опыта даёт штандарт", r_id >= 0 and GameManager.squad_elite(b))
	# Красный ИИ: копилка → лучший отряд
	var r1: int = _squad("spearman", R, spot + Vector3(20, 0, 0))
	var r2: int = _squad("spearman", R, spot + Vector3(20, 0, 10))
	await pframes(5)
	for u in _all([r1, r2]):
		(u as Unit).set_tick(false)
	GameManager.squads[r2]["kills"] = 50
	GameManager.squads[r1]["kills"] = 3
	var g0: int = int(rm.ai_grants)
	var need: float = _RCfg.POOL_COST / maxf(_RCfg.POOL_PER_KILL, 1e-6)
	rm.add_ai_xp(need * 0.5)
	var early: bool = int(rm.ai_grants) == g0
	rm.add_ai_xp(need * 0.6)
	verdict("E3 красный ИИ вручает штандарт по копилке и своему лучшему отряду",
		early and int(rm.ai_grants) == g0 + 1 and GameManager.squad_elite(r2) and not GameManager.squad_elite(r1),
		"вручений %d, r1 %s, r2 %s" % [int(rm.ai_grants) - g0, GameManager.squad_elite(r1), GameManager.squad_elite(r2)])
	_kill([a, b, r1, r2])
	await pframes(30)

# ─────────────────────────────────────────────────────────────────────────────
# F. КРУГ АУРЫ
# ─────────────────────────────────────────────────────────────────────────────
func _f_aura_view() -> void:
	print("\n═════ F. КРУГ АУРЫ ПО ВЫДЕЛЕНИЮ ═════")
	var spot: Vector3 = _spot(45.0, -45.0)   # реликвии блока E лежат у его площадки
	_wipe(spot, 50.0)
	await pframes(5)
	var c: int = _squad("spearman", F, spot)
	var near: int = _squad("archer", F, spot + Vector3(0, 0, 8))
	var far: int = _squad("archer", F, spot + Vector3(0, 0, 45))
	await pframes(5)
	var rm: Node = GameManager.relic_mgr()
	rm.grant_to_squad(c, true)
	sm.select_units(_members(near))
	await pframes(20)
	var none_rings: int = int(rm.aura_view_rings)
	sm.select_units(_members(c))
	await pframes(20)
	var rings: int = int(rm.aura_view_rings)
	var icons: int = int(rm.aura_view_icons)
	verdict("F1 выделен носитель — круг ауры показан, без носителя — нет", rings == 1 and none_rings == 0,
		"кругов %d (без носителя %d)" % [rings, none_rings])
	verdict("F2 значки над отрядами в круге (сам и сосед), дальний — без значка", icons == 2, "значков %d" % icons)
	sm._clear_selection()
	await pframes(20)
	verdict("F3 снято выделение — круг и значки спрятаны", int(rm.aura_view_rings) == 0 and int(rm.aura_view_icons) == 0)
	_kill([c, near, far])
	await pframes(40)

# ─────────────────────────────────────────────────────────────────────────────
# G. «ЯРОСТНАЯ АТАКА»
# ─────────────────────────────────────────────────────────────────────────────
func _g_rage() -> void:
	print("\n═════ G. «ЯРОСТНАЯ АТАКА» ═════")
	var spot: Vector3 = _spot()
	_wipe(spot, 40.0)
	await pframes(5)
	var w: int = _squad("warrior", F, spot)
	await pframes(5)
	(GameManager.squads[w] as Dictionary)["abilities"] = {GameManager.RAGE_NODE: true}
	var ok1: bool = GameManager.squad_start_rage(w, false)
	var ok2: bool = GameManager.squad_start_rage(w, false)
	var cd: float = GameManager.squad_rage_cd_frac(w)
	verdict("G1 ручной вызов срабатывает, повтор сразу — нет (откат на отряд)", ok1 and not ok2 and cd > 0.9,
		"1-й %s, 2-й %s, откат %.2f" % [ok1, ok2, cd])
	_kill([w])
	await pframes(20)
	# Самозапуск: отряд с купленным приёмом входит в ближний бой
	var w2: int = _squad("warrior", F, spot)
	var foe: int = _squad("spearman", R, spot + Vector3(6, 0, 0))
	await pframes(5)
	(GameManager.squads[w2] as Dictionary)["abilities"] = {GameManager.RAGE_NODE: true}
	for u in _members(foe):
		(u as Unit).set_tick(false)
	var a0: int = GameManager.rage_auto_starts
	for u in _members(w2):
		(u as Unit).command_attack(_members(foe)[0], true, true, true)
	var started := false
	for _i in range(60 * 10):
		await get_tree().physics_frame
		if GameManager.rage_auto_starts > a0:
			started = true
			break
	verdict("G2 приём запускается сам на первом ударе в ближнем бою", started and GameManager.squad_rage_cd_frac(w2) > 0.0)
	verdict("G3 самозапуск — один на откат", GameManager.rage_auto_starts - a0 == 1, "%d" % (GameManager.rage_auto_starts - a0))
	_kill([w2, foe])
	await pframes(30)

# ─────────────────────────────────────────────────────────────────────────────
# H. [S] НЕ ЗАМЕДЛЯЕТ МАРШ
# ─────────────────────────────────────────────────────────────────────────────
func _h_hold_speed() -> void:
	print("\n═════ H. [S] НЕ ЗАМЕДЛЯЕТ МАРШ ═════")
	var spot: Vector3 = _spot()
	_wipe(spot, 40.0)
	await pframes(5)
	var res: Dictionary = {}
	for st in ["attack", "defense"]:
		var s: int = _squad("spearman", F, spot)
		await pframes(5)
		var men: Array = _members(s)
		for u in men:
			(u as Unit).set_stance(st)
		for u2 in men:
			(u2 as Unit).command_move((u2 as Unit).global_position + Vector3(0, 0, 25), false, Vector3.ZERO, false, true)
		await pframes(30)
		var sp := 0.0
		for u3 in men:
			sp += (u3 as Unit)._effective_speed()
		res[st] = sp / float(men.size())
		_kill([s])
		await pframes(20)
	verdict("H1 скорость марша в [S] равна обычной", absf(float(res["defense"]) - float(res["attack"])) < 0.01,
		"[S] %.3f, [C] %.3f м/с" % [float(res["defense"]), float(res["attack"])])

# ─────────────────────────────────────────────────────────────────────────────
# I. ФАЛАНГА САМА
# ─────────────────────────────────────────────────────────────────────────────
func _i_phalanx_auto() -> void:
	print("\n═════ I. ФАЛАНГА ПОД УДАРОМ ═════")
	var spot: Vector3 = _spot()
	_wipe(spot, 40.0)
	await pframes(5)
	var s: int = _squad("spearman", F, spot)
	await pframes(5)
	var u: Spearman = _members(s)[0]
	var none_calm: bool = u.spear_wall_active()
	(GameManager.squads[s] as Dictionary)["abilities"] = {"spearman_1d": true}
	var calm: bool = u.spear_wall_active()
	GameManager.squad_mark_hit(s)
	var hit: bool = u.spear_wall_active()
	GameManager.squad_set_ability(s, "spearman_1d", false)
	var off: bool = u.spear_wall_active()
	verdict("I1 изученная «Фаланга» встаёт сама под ударом без [S]", not none_calm and not calm and hit,
		"без узла %s, в покое %s, под ударом %s" % [none_calm, calm, hit])
	verdict("I2 выключенный переключатель приёма фалангу не ставит", not off)
	_kill([s])
	await pframes(20)

# ─────────────────────────────────────────────────────────────────────────────
# J. МОНАХ
# ─────────────────────────────────────────────────────────────────────────────
func _j_case(spot: Vector3) -> Dictionary:
	_wipe(spot, 40.0)
	await pframes(5)
	var p: int = _squad("spearman", F, spot)
	var mk: int = _squad("monk", F, spot + Vector3(-6, 0, 0), 1)
	await pframes(10)
	for u in _members(p):
		(u as Unit).max_health = 1000.0
		(u as Unit).current_health = 100.0
		(u as Unit)._soa_push_stats()
	var monk: Monk = _members(mk)[0]
	var t0: int = monk.heal_ticks
	var h0: float = monk.healed_total
	var most := 0
	for _i in range(60 * 12):
		await get_tree().physics_frame
		most = maxi(most, monk.aoe_touched)
	var ticks: int = monk.heal_ticks - t0
	var per_tick: float = (monk.healed_total - h0) / float(maxi(ticks, 1))
	var res := {"most": most, "per_target": per_tick / float(maxi(most, 1)), "ticks": ticks}
	_kill([p, mk])
	await pframes(30)
	return res

func _j_monk() -> void:
	print("\n═════ J. МОНАХ: МАССОВОЕ ЛЕЧЕНИЕ ═════")
	var spot: Vector3 = _spot()
	var one: Dictionary = await _j_case(spot)
	GameManager.finish_research(F, "monk_1d")
	var many: Dictionary = await _j_case(spot)
	print("  без узла: целей за такт до %d, %.1f HP цели за такт; с «Троичным потоком»: до %d, %.1f" % [
		int(one["most"]), float(one["per_target"]), int(many["most"]), float(many["per_target"])])
	verdict("J1 без улучшения кузницы монах лечит одного", int(one["most"]) == 1 and int(one["ticks"]) > 0)
	verdict("J2 с улучшением — нескольких сразу", int(many["most"]) > 1)
	var k: float = float(one["per_target"]) / maxf(float(many["per_target"]), 1e-6)
	verdict("J3 массовое лечение каждому на 40 % медленнее точечного", absf(k - 1.4) < 0.1, "×%.2f" % k)

# ─────────────────────────────────────────────────────────────────────────────
# K. ТЕЛА
# ─────────────────────────────────────────────────────────────────────────────
func _k_corpses() -> void:
	print("\n═════ K. ТЕЛА ПО СТОРОНАМ ═════")
	var spot: Vector3 = _spot()
	_wipe(spot, 40.0)
	await pframes(5)
	var a: int = _squad("spearman", F, spot, 3)
	var b: int = _squad("spearman", R, spot + Vector3(0, 0, 8), 3)
	await pframes(5)
	_kill([a, b])
	await pframes(30)
	var cr = GameManager.corpses
	var tints: Dictionary = {}
	var dims: Array = []
	if cr != null:
		for key in cr._buckets:
			var bk = cr._buckets[key]
			if not bk.tint_set:
				continue
			var mat := (bk.mm.mesh as QuadMesh).material as ShaderMaterial
			tints[str(mat.get_shader_parameter("dead_tint"))] = true
			dims.append(float(mat.get_shader_parameter("dead_dim")))
	var light := not dims.is_empty()
	for d in dims:
		if float(d) <= 0.74 + 1e-3:
			light = false
	verdict("K1 тела светлее прежнего (dead_dim > 0.74)", light, str(dims))
	verdict("K2 подтон тел разный у сторон", tints.size() >= 2, str(tints.keys()))

# ─────────────────────────────────────────────────────────────────────────────
# L. ОХРАНА БАЗЫ ОТ УДАРА ПО БАШНЕ
# ─────────────────────────────────────────────────────────────────────────────
func _l_base_alarm() -> void:
	print("\n═════ L. ОХРАНА БАЗЫ КРАСНОГО: УДАР ПО БАШНЕ ═════")
	var guard = main.get("enemy_guard")
	var tower: Building = null
	for bb in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(bb) and bb is Building and not (bb as Building).is_dead() \
				and bb.get_class() != "" and (bb as Building).has_method("is_stronghold") == false:
			pass
	for bb2 in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(bb2) and bb2 is _TowerS and not (bb2 as Building).is_dead():
			tower = bb2
			break
	if guard == null or tower == null:
		verdict("L0 у красного есть охрана базы и башня", false)
		return
	await pframes(120)
	var was_alarm: bool = bool(guard.alarm)
	# Бьёт «издали»: чужих в зоне замка и у постов нет — тревогу может
	# поднять только удар по самой башне
	tower.take_damage(1.0, null)
	for _i in range(90):
		await get_tree().physics_frame
		if bool(guard.alarm):
			break
	verdict("L1 удар по башне базы поднимает охрану", not was_alarm and bool(guard.alarm)
		and String(guard.last_reason).begins_with("bld"), "тревога %s, причина «%s»" % [guard.alarm, guard.last_reason])
	await pframes(30)

# ─────────────────────────────────────────────────────────────────────────────
# M. ЗНАЧОК «ВОЛЬНО»
# ─────────────────────────────────────────────────────────────────────────────
func _m_at_ease_icon() -> void:
	print("\n═════ M. ЗНАЧОК [C] «ВОЛЬНО» ═════")
	var hud = main.hud
	var tex: Texture2D = hud._at_ease_icon()
	var spot: Vector3 = _spot()
	var s: int = _squad("spearman", F, spot, 6)
	await pframes(5)
	sm.select_units(_members(s))
	await pframes(10)
	var btn = null
	for n in hud.find_children("SquadCmdBtn_C", "", true, false):
		btn = n
		break
	var has_icon := false
	if btn != null:
		has_icon = (btn as Button).text == "" and (btn as Button).get_child_count() > 0
	verdict("M1 кнопка [C] — картинка бойца в покое, а не буква", tex != null and has_icon,
		"текстура %s, кнопка %s" % [tex != null, btn != null])
	_kill([s])
	await pframes(10)

# ─────────────────────────────────────────────────────────────────────────────
# N. ATTACK-MOVE ШИРОКОЙ ГРУППОЙ НЕ СХОДИТСЯ В КУЧУ; ЛИНИЯ CTRL+N ДЕРЖИТ ФРОНТ
# ─────────────────────────────────────────────────────────────────────────────
func _n_case(own: bool) -> Dictionary:
	var spot: Vector3 = _spot(40.0, 0.0)
	_wipe(spot, 80.0)
	await pframes(5)
	_Opt.am_own_dest = own
	var sids: Array = []
	for i in range(7):
		sids.append(_squad("spearman" if i % 2 == 0 else "archer", F, spot + Vector3(0, 0, -36.0 + float(i) * 12.0)))
	await pframes(20)
	var men: Array = _all(sids)
	sm.select_units(men)
	var n_am: int = sm._squad_cmd().attack_move(sm, spot + Vector3(40, 0, 0), false)
	await pframes(60 * 30)
	var cents: Array = []
	for s in sids:
		cents.append(_sq_centre(int(s)))
	var span := 0.0
	for c in cents:
		span = maxf(span, absf((c as Vector3).z - spot.z))
	var res := {"span": span, "foreign": _foreign_share(_all(sids)), "lost": int(sm._squad_cmd().lost_reissued), "am": n_am}
	_kill(sids)
	await pframes(30)
	_Opt.am_own_dest = true
	return res

func _n_wide_am() -> void:
	print("\n═════ N. ATTACK-MOVE ШИРОКОЙ ГРУППОЙ ═════")
	var off: Dictionary = await _n_case(false)
	var on: Dictionary = await _n_case(true)
	print("  своя точка выкл: полуширина группы %.1f м, чужих соседей %.2f; вкл: %.1f м, %.2f" % [
		float(off["span"]), float(off["foreign"]), float(on["span"]), float(on["foreign"])])
	verdict("N1 группа шириной 72 м в [A] приходит той же ширины (не стягивается в центр)",
		float(on["span"]) >= 30.0 and float(on["foreign"]) <= 0.05, "%.1f м, %.2f" % [float(on["span"]), float(on["foreign"])])
	verdict("N2 без правки крайние стягивались (стенд различает правку)",
		float(off["span"]) < float(on["span"]) - 8.0, "%.1f против %.1f м" % [float(off["span"]), float(on["span"])])
	# Линия Ctrl+N держит фронт
	var spot: Vector3 = _spot(40.0, 0.0)
	_wipe(spot, 80.0)
	await pframes(5)
	var line: Array = []
	for i in range(5):
		line.append(_squad("spearman", F, spot + Vector3(0, 0, -24.0 + float(i) * 12.0)))
	var foe: int = _squad("spearman", R, spot + Vector3(16, 0, 0))
	await pframes(20)
	for u in _members(foe):
		(u as Unit).set_tick(false)
		(u as Unit).max_health = 1.0e9
		(u as Unit).current_health = 1.0e9
	for s in line:
		var slots: Array = []
		for u2 in _members(int(s)):
			slots.append((u2 as Unit).global_position)
		GameManager.squad_set_formation(int(s), slots, Vector3.RIGHT, false)
	sm.select_units(_all(line))
	sm._save_group(1)
	sm._clear_selection()
	sm._recall_group(1)
	var h0: int = int(sm._squad_cmd().line_halts)
	sm._squad_cmd().attack_move(sm, spot + Vector3(60, 0, 0), false)
	await pframes(60 * 12)
	var flank_z := []
	for k in [0, 4]:
		flank_z.append(_sq_centre(int(line[k])).z - spot.z)
	var halts: int = int(sm._squad_cmd().line_halts) - h0
	if _Opt.group_line_hold:
		verdict("N3 центр упёрся — фланги встают держать фронт, а не бегут к угрозе",
			halts >= 2 and absf(float(flank_z[0])) > 18.0 and absf(float(flank_z[1])) > 18.0,
			"остановок %d, фланги z %.1f / %.1f" % [halts, float(flank_z[0]), float(flank_z[1])])
	else:
		# Разворот ТЗ 25.10.2026 (третье письмо, п. 2): «задние отряды в [A]
		# не замирают» — удержание линии выключено, ни один отряд не встаёт
		verdict("N3 (разворот 25.10) центр упёрся — фланги не замирают, идут в бой",
			halts == 0, "остановок %d, фланги z %.1f / %.1f" % [halts, float(flank_z[0]), float(flank_z[1])])
	_kill(line + [foe])
	await pframes(30)

# ═════════════════════════════════════════════════════════════════════════════
# ВТОРОЕ ПИСЬМО 23.10.2026: O глубокий фронт, P воскрешение в рамке, Q бой
# 5×5, R поздняя орда (S реплики откачены по ТЗ 24.10.2026)
# ═════════════════════════════════════════════════════════════════════════════
func _deep_rows(n: int) -> Array:
	var spot: Vector3 = _spot(40.0, 0.0)
	_wipe(spot, 90.0)
	await pframes(5)
	var sids: Array = []
	for i in range(n):
		sids.append(_squad("spearman", F, spot + Vector3(-20.0, 0, -float(n) * 6.0 + float(i) * 12.0)))
	await pframes(10)
	var men: Array = _all(sids)
	sm.select_units(men)
	var keep: int = sm.formation_mode
	sm.formation_mode = sm.FORM_DEEP
	var a := spot + Vector3(10.0, 0, -45.0)
	var b := spot + Vector3(10.0, 0, 45.0)
	var plan: Dictionary = sm._deep_formation_slots(a, b, men)
	sm.formation_mode = keep
	var acc: Dictionary = {}
	for i in range((plan["flat"] as Array).size()):
		var u: Unit = plan["flat"][i]
		var sp: Vector3 = plan["slots"][i]
		if not acc.has(u.squad_id):
			acc[u.squad_id] = [0.0, 0]
		acc[u.squad_id][0] = float(acc[u.squad_id][0]) + sp.x
		acc[u.squad_id][1] = int(acc[u.squad_id][1]) + 1
	# Линия вдоль Z: эшелоны — разные X (глубина)
	var depths: Array = []
	for s in acc:
		depths.append(float(acc[s][0]) / float(acc[s][1]))
	depths.sort()
	depths.reverse()
	var rows: Array = []
	var last := INF
	for d in depths:
		if last == INF or absf(float(d) - last) > 2.5:
			rows.append(1)
		else:
			rows[rows.size() - 1] = int(rows[rows.size() - 1]) + 1
		last = float(d)
	_kill(sids)
	await pframes(20)
	return rows

func _o_deep_front() -> void:
	print("\n═════ O. ГЛУБОКИЙ ФРОНТ [2]: РАВНЫЕ ЭШЕЛОНЫ ═════")
	var want := {7: [4, 3], 11: [6, 5], 15: [5, 5, 5], 20: [7, 7, 6]}
	var ok_f := true
	for n in want:
		if sm.deep_row_counts(int(n)) != want[n]:
			ok_f = false
	verdict("O1 формула эшелонов: 7 → 4+3, 11 → 6+5, 15 → 5+5+5, 20 → 7+7+6", ok_f,
		"%s %s %s %s" % [sm.deep_row_counts(7), sm.deep_row_counts(11), sm.deep_row_counts(15), sm.deep_row_counts(20)])
	for n2 in [7, 11, 15]:
		var rows: Array = await _deep_rows(int(n2))
		verdict("O2 протяжка [2] %d отрядов — эшелоны %s" % [int(n2), str(want[n2])], rows == want[n2], str(rows))

func _p_revive_frame() -> void:
	print("\n═════ P. ВОСКРЕШЁННЫЙ — В РАМКЕ ОТРЯДА ═════")
	var spot: Vector3 = _spot(40.0, 0.0)
	_wipe(spot, 60.0)
	await pframes(5)
	var s: int = _squad("spearman", F, spot)
	await pframes(10)
	# Разметка отряда — далеко (прошлый приказ), отряд стоит здесь
	var far_slots: Array = []
	for u in _members(s):
		far_slots.append((u as Unit).global_position + Vector3(0, 0, 40))
	GameManager.squad_set_formation(s, far_slots, Vector3.RIGHT, false)
	var victim: Unit = _members(s)[0]
	victim.take_damage(1.0e12)
	await pframes(10)
	var corpse = null
	var lst: Variant = GameManager.corpses._raisable.get(F)
	if lst != null and not (lst as Array).is_empty():
		corpse = (lst as Array).back()
	if corpse == null:
		verdict("P0 тело павшего копейщика есть", false)
		_kill([s])
		return
	var u2: Unit = GameManager.raise_fallen(corpse, null)
	var c0: Vector3 = GameManager._centroid_of(_members(s))
	var d: float = Vector2(u2.global_position.x - c0.x, u2.global_position.z - c0.z).length() if u2 != null else INF
	var span := 0.0
	for m in _members(s):
		if m != u2:
			span = maxf(span, Vector2((m as Unit).global_position.x - c0.x, (m as Unit).global_position.z - c0.z).length())
	verdict("P1 воскрешённый встал в рамке своего отряда, а не в старой разметке",
		u2 != null and d <= span + 1.0 and GameManager.is_passable(u2.global_position.x, u2.global_position.z),
		"от центра %.1f м при рамке %.1f м" % [d, span])
	_kill([s])
	await pframes(20)

func _q_case() -> Dictionary:
	var spot: Vector3 = _spot(40.0, 0.0)
	_wipe(spot, 70.0)
	await pframes(5)
	var mine: Array = []
	var foes: Array = []
	for i in range(5):
		mine.append(_squad("spearman", F, spot + Vector3(-14.0, 0, -28.0 + float(i) * 14.0)))
		foes.append(_squad("goblin_spearman" if i % 2 == 0 else "goblin_rider", Constants.FACTION_GOBLIN,
			spot + Vector3(14.0, 0, -28.0 + float(i) * 14.0)))
	await pframes(20)
	for i in range(5):
		var tf: Array = _members(int(foes[i]))
		var tm: Array = _members(int(mine[i]))
		for u in tm:
			(u as Unit).command_attack(tf[0], true, true, true)
		for u2 in tf:
			(u2 as Unit).command_attack(tm[0], true, true, false)
	var n_my0: int = _all(mine).size()
	var n_fo0: int = _all(foes).size()
	var fs := 0.0
	var samples := 0
	var t_half := -1.0
	for sec in range(1, 61):
		await pframes(60)
		var a: Array = _all(mine)
		var b: Array = _all(foes)
		if sec % 5 == 0 and a.size() > 20:
			fs += _foreign_share(a)
			samples += 1
		if t_half < 0.0 and (a.size() < n_my0 / 2 or b.size() < n_fo0 / 2):
			t_half = float(sec)
	var res := {"t_half": t_half, "foreign": fs / float(maxi(samples, 1))}
	_kill(mine + foes)
	await pframes(30)
	return res

func _q_clash() -> void:
	print("\n═════ Q. БОЙ 5×5: КОРОБКИ И ДЛИТЕЛЬНОСТЬ ═════")
	var r1: Dictionary = await _q_case()
	_Opt.ttk_press = false
	var r0: Dictionary = await _q_case()
	_Opt.ttk_press = true
	print("  до половины потерь: с правкой %.0f с, без %.0f с; чужих соседей в бою %.2f / %.2f" % [
		float(r1["t_half"]), float(r0["t_half"]), float(r1["foreign"]), float(r0["foreign"])])
	verdict("Q1 бой 5×5 идёт отрядами (чужих соседей у своих ≤ 0.15)", float(r1["foreign"]) <= 0.15,
		"%.2f" % float(r1["foreign"]))
	verdict("Q2 схватка дольше прежней (до половины потерь)",
		float(r1["t_half"]) < 0.0 or float(r1["t_half"]) > float(r0["t_half"]),
		"%.0f против %.0f с" % [float(r1["t_half"]), float(r0["t_half"])])

func _r_late_horde() -> void:
	print("\n═════ R. ПОЗДНЯЯ ОРДА ═════")
	var Sp = load("res://scripts/spawn_config.gd")
	var early_f: int = Sp.field_cap(Sp.LATE_SURGE_FROM_SEC - 60.0)
	var late_f: int = Sp.field_cap(Sp.LATE_SURGE_FROM_SEC + 60.0)
	var early_h: int = Sp.horde_cap(0.0)
	var late_h: int = Sp.horde_cap(Sp.LATE_SURGE_FROM_SEC + 60.0)
	verdict("R1 после 30-й минуты потолки волн и орды выше", late_f > early_f and late_h > early_h,
		"поле %d → %d, орда %d → %d" % [early_f, late_f, early_h, late_h])
	var sched: Array = load("res://scripts/goblin/RaidManager.gd").schedule(false, 0.0)
	var n30 := 0
	var n45 := 0
	for e in sched:
		var d: Dictionary = e
		if String(d["kind"]) != "assault":
			continue
		var cnt := 0
		for k in (d["comp"] as Dictionary):
			cnt += int(d["comp"][k])
		if absf(float(d["t"]) - Sp.ASSAULT_EVENT_TIMES[0]) < 1.0: n30 = cnt
		if absf(float(d["t"]) - Sp.ASSAULT_EVENT_TIMES[1]) < 1.0: n45 = cnt
	var base30 := 0
	var base45 := 0
	for k1 in Sp.ASSAULT_EVENT_WAVES[0]:
		base30 += int(Sp.ASSAULT_EVENT_WAVES[0][k1])
	for k2 in Sp.ASSAULT_EVENT_WAVES[1]:
		base45 += int(Sp.ASSAULT_EVENT_WAVES[1][k2])
	verdict("R2 штурм 45:00 крупнее табличного, 30:00 — как в таблице", n45 > base45 and n30 == base30,
		"30:00 %d (таблица %d), 45:00 %d (таблица %d)" % [n30, base30, n45, base45])

# ═════════════════════════════════════════════════════════════════════════════
# ТРЕТЬЕ ПИСЬМО 23.10.2026: T — первопричина ловушек в лесной стене.
# Свалка прижата к сплошной лесной стене (Main._wall_row): сколько бойцов
# ОКАЗЫВАЕТСЯ в закрытой клетке навигации (просвет между стволами, куда у A*
# нет дороги), сколько вызволений и выносов из стволов. A/B ручкой
# forest_nav_solid: с ней в стену не попадает никто, вызволять некого
# ═════════════════════════════════════════════════════════════════════════════
const T_WALL_X := -70.0
const T_WALL_Z0 := -40.0
const T_WALL_Z1 := 16.0
const T_WALL_HALF := 3.0
var _t_wall_built := false

func _t_case(solid: bool) -> Dictionary:
	_Opt.forest_nav_solid = solid
	if not _t_wall_built:
		_t_wall_built = true
		_wipe(Vector3(T_WALL_X - 20.0, 0, -12.0), 45.0)
		var z: float = T_WALL_Z0
		while z <= T_WALL_Z1:
			main._wall_row(Vector2(T_WALL_X, z), Vector2(1.0, 0.0), T_WALL_HALF)
			z += main.WALL_STEP
		await pframes(60 * 3)
	var mine: Array = []
	var foes: Array = []
	for i in range(4):
		var z2: float = -30.0 + float(i) * 12.0
		mine.append(_squad("spearman", F, Vector3(T_WALL_X - T_WALL_HALF - 6.0, 0, z2)))
		foes.append(_squad("goblin_spearman" if i % 2 == 0 else "goblin_rider", Constants.FACTION_GOBLIN,
			Vector3(T_WALL_X - T_WALL_HALF - 26.0, 0, z2)))
	await pframes(10)
	for i in range(4):
		var tm: Array = _members(int(mine[i]))
		for u in _members(int(foes[i])):
			(u as Unit).command_attack(tm[0], true, true, false)
	var u0: int = Unit.unstuck_total
	var t0: int = GameManager.trap_pushes
	var peak := 0
	var inside_s := 0
	for f in range(60 * 45):
		await get_tree().physics_frame
		if f % 30 == 0:
			var n_in := 0
			for u2 in _all(mine + foes):
				var p: Vector3 = (u2 as Unit).global_position
				if not GameManager.army.nav_free(p.x, p.z):
					n_in += 1
			peak = maxi(peak, n_in)
			inside_s += n_in
	var res := {"peak": peak, "inside": inside_s, "unstuck": Unit.unstuck_total - u0,
		"trap": GameManager.trap_pushes - t0}
	_kill(mine + foes)
	await pframes(40)
	_Opt.forest_nav_solid = true
	return res

func _t_forest_root() -> void:
	print("\n═════ T. ЛОВУШКИ В ЛЕСНОЙ СТЕНЕ: ПЕРВОПРИЧИНА ═════")
	var off: Dictionary = await _t_case(false)
	var on: Dictionary = await _t_case(true)
	print("  без правки: в закрытых клетках до %d бойцов (сумма проб %d), вызволений %d, выносов %d" % [
		int(off["peak"]), int(off["inside"]), int(off["unstuck"]), int(off["trap"])])
	print("  с правкой:  в закрытых клетках до %d бойцов (сумма проб %d), вызволений %d, выносов %d" % [
		int(on["peak"]), int(on["inside"]), int(on["unstuck"]), int(on["trap"])])
	verdict("T1 свалка у лесной стены не загоняет бойцов в закрытые клетки навигации",
		int(on["peak"]) == 0, "до %d (без правки %d)" % [int(on["peak"]), int(off["peak"])])
	verdict("T2 выносить из стволов некого (вынос — страховка, а не механика)",
		int(on["trap"]) <= int(off["trap"]) and int(on["trap"]) <= 2,
		"%d (без правки %d)" % [int(on["trap"]), int(off["trap"])])
