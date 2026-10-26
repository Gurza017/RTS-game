extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 22.10.2026: знамёна элиты, рабочие и «в замок», разрыв у замка,
## охрана рудника, курсор монаха, дома на 35 отрядов, лимит населения
## ═══════════════════════════════════════════════════════════════════════════
##   A — бордовый штандарт элиты: ни одного жёлтого пикселя, выдаётся только
##       реликвией/наградой игрока, заменяет вымпел (один флагшток), римская
##       цифра растёт, лычки внизу (белые у «Опытных», синяя плашка у
##       «Ветеранов»), полотнище крупнее прежнего штандарта; флаг реликвии
##       над элитным отрядом не висит
##   B — тревога: рабочие бегут в замок под ударами конницы и не дерутся
##   C — «в замок» десяти раненых отрядов одним кликом при лимите 8: все
##       уходят сразу (отход), восемь садятся, остальные ждут у ворот
##   D — атака крепости двумя отрядами: отряд не рвётся, за замок не уходит
##   E — спящая охрана рудника просыпается от обстрела и идёт на стрелков
##   F — монах: знак медицины над раненым своим отрядом, звук снадобья
##   G — дома: 35 отрядов достижимы (21 дом), цена 21-го дома разумна
##   H — найм поверх лимита: красная плашка «Превышен лимит населения!»
## Запуск: godot --headless --path . res://qa_tz1022/Test.tscn [-- only=abcdefgh]

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _BannerArtT := preload("res://scripts/BannerArt.gd")
const _CursorArtT := preload("res://scripts/CursorArt.gd")
const _BarracksT := preload("res://scripts/Barracks.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcdefgh"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(1200.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_tz1022: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _spawn(kind: String, at: Vector3, fac: int = F) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int = F, cols: int = 8) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _place(b: Building, at: Vector3, fac: int = F) -> void:
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _clear(at: Vector3, r: float) -> void:
	main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and (b as Node3D).global_position.distance_to(at) < r:
			b.queue_free()

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "a" in _only: await _a_banners()
	if "b" in _only: await _b_workers()
	if "c" in _only: await _c_to_castle()
	if "d" in _only: await _d_castle_split()
	if "e" in _only: await _e_guard_wake()
	if "f" in _only: await _f_monk_cursor()
	if "g" in _only: _g_houses()
	if "h" in _only: await _h_pop_alert()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
# A. БОРДОВЫЙ ШТАНДАРТ ЭЛИТЫ
# ─────────────────────────────────────────────────────────────────────────────
## Жёлтый: красный и зелёный высоки, синий низок (золото, «★»)
func _yellow_px(tex: Texture2D) -> int:
	if tex == null:
		return -1
	var img: Image = tex.get_image()
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.7 and c.g > 0.55 and c.b < 0.45 and c.r - c.b > 0.3:
				n += 1
	return n

func _count_px(tex: Texture2D, rect: Rect2i, pred: Callable) -> int:
	var img: Image = tex.get_image()
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if pred.call(img.get_pixel(x, y)):
				n += 1
	return n

func _cloth_rect(tex: Texture2D, cloth_pred: Callable) -> Rect2i:
	var img: Image = tex.get_image()
	var x0 := 9999
	var y0 := 9999
	var x1 := -1
	var y1 := -1
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if cloth_pred.call(img.get_pixel(x, y)):
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func _a_banners() -> void:
	print("\n═════ A. БОРДОВЫЙ ШТАНДАРТ ЭЛИТЫ ═════")
	_BannerArtT.clear_cache()
	var yellow := 0
	for e in [1, 2, 3]:
		for v in range(0, 8):
			yellow += maxi(_yellow_px(_BannerArtT.elite_texture(e, v)), 0)
	var relic_y: int = _yellow_px(GameManager.relic_mgr().relic_texture())
	verdict("A1 на штандарте элиты и реликвии нет жёлтого", yellow == 0 and relic_y == 0,
		"жёлтых пикселей %d, у реликвии %d" % [yellow, relic_y])
	# Размер: полотнище против прежнего штандарта (_render_vexillum)
	var red_cloth := func(c: Color) -> bool: return c.a > 0.5 and c.r > 0.25 and c.g < 0.12 and c.b < 0.2
	var old_r: Rect2i = _cloth_rect(_BannerArtT._render_vexillum(1), red_cloth)
	var new_r: Rect2i = _cloth_rect(_BannerArtT.elite_texture(1, 0), red_cloth)
	verdict("A2 полотнище крупнее прежнего (~+20 % высоты) и шире",
		float(new_r.size.y) >= float(old_r.size.y) * 1.15 and float(new_r.size.x) >= float(old_r.size.x) * 1.2,
		"было %dx%d, стало %dx%d" % [old_r.size.x, old_r.size.y, new_r.size.x, new_r.size.y])
	# Лычки: «Опытные» — белые полосы без синего, «Ветераны» — синяя плашка
	var low := Rect2i(_BannerArtT.ELITE_POLE_X - 16, _BannerArtT.ELITE_TOP + _BannerArtT.ELITE_H - 30, 36, 30)
	var white := func(c: Color) -> bool: return c.a > 0.5 and c.r > 0.9 and c.g > 0.9 and c.b > 0.85
	var blue := func(c: Color) -> bool: return c.a > 0.5 and c.b > 0.4 and c.b > c.r + 0.2
	var t2: Texture2D = _BannerArtT.elite_texture(1, 2)
	var t5: Texture2D = _BannerArtT.elite_texture(1, 5)
	var t0: Texture2D = _BannerArtT.elite_texture(1, 0)
	var w2: int = _count_px(t2, low, white)
	var b2: int = _count_px(t2, low, blue)
	var b5: int = _count_px(t5, low, blue)
	var w0: int = _count_px(t0, low, white)
	verdict("A3 «Опытные» — белые лычки внизу, «Ветераны» — синяя плашка",
		w2 > w0 + 20 and b2 == 0 and b5 > 60,
		"белых у Опытных %d (без ранга %d), синих у Опытных %d, у Ветеранов %d" % [w2, w0, b2, b5])
	# Римская цифра: I и II — разный рисунок середины
	var mid := Rect2i(_BannerArtT.ELITE_POLE_X - 14, _BannerArtT.ELITE_TOP + 10, 30, 30)
	var wi: int = _count_px(_BannerArtT.elite_texture(1, 0), mid, white)
	var wii: int = _count_px(_BannerArtT.elite_texture(2, 0), mid, white)
	verdict("A4 римская цифра по центру: II крупнее I", wi > 20 and wii > wi, "I %d px, II %d px" % [wi, wii])
	# Живой отряд: реликвия → элита, штандарт вместо вымпела, без флага реликвии
	var at := Vector3(-60, 0, -40)
	_clear(at, 30.0)
	await pframes(3)
	var men: Array = _squad("spearman", at, 24)
	var sid: int = (men[0] as Unit).squad_id
	GameManager.grant_squad_level(sid)
	(GameManager.squads[sid] as Dictionary).erase("elite")
	(GameManager.squads[sid] as Dictionary).erase("elite_lvl")
	GameManager.refresh_squad_banner(sid)
	await pframes(5)
	var ban0 = (GameManager.squads[sid] as Dictionary).get("banner")
	var plain_ok: bool = ban0 != null and is_instance_valid(ban0) and not bool(ban0.shown_elite) \
		and not GameManager.squad_elite(sid)
	verdict("A5 ранг без награды игрока — обычный вымпел, не штандарт", plain_ok)
	var rm = GameManager.relic_mgr()
	rm.grant_to_squad(sid, true)
	await pframes(10)
	await frames(5)
	var ban = (GameManager.squads[sid] as Dictionary).get("banner")
	# Один флагшток: знамя отряда — штандарт, а узел реликвии над носителем
	# из элитного отряда скрыт (видимость знамени headless не судится —
	# знаменосец не рисуется)
	var relic_shown := false
	for r in rm.relics:
		var rn = (r as Dictionary)["node"]
		if rn != null and is_instance_valid(rn) and (rn as Node3D).visible:
			relic_shown = true
	verdict("A6 реликвия — отряд элита: штандарт I вместо вымпела, один флагшток",
		GameManager.squad_elite(sid) and ban != null and bool(ban.shown_elite) and int(ban.shown_elite_lvl) == 1
		and not relic_shown, "элита %s, штандарт %s, ур. %s, флаг реликвии виден %s" % [GameManager.squad_elite(sid),
			ban != null and bool(ban.shown_elite), ban.shown_elite_lvl if ban != null else -1, relic_shown])
	rm.grant_to_squad(sid, true)
	await pframes(5)
	ban = (GameManager.squads[sid] as Dictionary).get("banner")
	verdict("A7 вторая реликвия — цифра II", ban != null and int(ban.shown_elite_lvl) == 2,
		"ур. %s" % [ban.shown_elite_lvl if ban != null else -1])
	# Высший ранг по убийствам без награды — не элита
	var men2: Array = _squad("spearman", at + Vector3(0, 0, 14), 12)
	var sid2: int = (men2[0] as Unit).squad_id
	(GameManager.squads[sid2] as Dictionary)["level"] = _UCfgT.max_veteran_level("spearman")
	GameManager.refresh_squad_banner(sid2)
	await pframes(3)
	verdict("A8 «Легендарные» без награды игрока — вымпел, не штандарт", not GameManager.squad_elite(sid2))
	rm.reset()
	_free(men)
	_free(men2)
	await pframes(5)

# ─────────────────────────────────────────────────────────────────────────────
# B. ТРЕВОГА: РАБОЧИЕ БЕГУТ ПОД УДАРАМИ И НЕ ДЕРУТСЯ
# ─────────────────────────────────────────────────────────────────────────────
func _b_workers() -> void:
	print("\n═════ B. ТРЕВОГА ПОД УДАРОМ КОННИЦЫ ═════")
	var base := Vector3(-110, 0, 40)
	_clear(base, 50.0)
	await pframes(3)
	var c: Building = Castle.new()
	_place(c, base)
	await pframes(10)
	var ws: Array = []
	for k in range(10):
		var w := _spawn("worker", base + Vector3(-26.0 + float(k % 5) * 1.2, 0, 4.0 + float(k / 5) * 1.2))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
		ws.append(w)
	var riders: Array = _squad("goblin_rider", base + Vector3(-38, 0, 6), 6, G, 3)
	await pframes(5)
	GameManager.worker_alert[F] = false
	GameManager.toggle_worker_alert(F)
	for k2 in range(riders.size()):
		(riders[k2] as Unit).command_attack(ws[k2 % ws.size()], true)
	var fought := 0
	var fought_set: Dictionary = {}
	var t := 0
	while t < 60 * 30:
		await pframes(10)
		t += 10
		for w in _alive(ws):
			var wu := w as Unit
			if wu.attack_target != null or wu.state == Unit.State.ATTACKING:
				fought_set[wu] = true
		if int(c.call("shelter_count")) + (ws.size() - _alive(ws).size()) >= ws.size():
			break
	fought = fought_set.size()
	var sheltered: int = int(c.call("shelter_count"))
	var dead: int = ws.size() - _alive(ws).size()
	var outside := 0
	for w2 in _alive(ws):
		if not (w2 as Unit).garrisoned:
			outside += 1
	print("  B: в укрытии %d, погибли %d, снаружи %d, отвечали врагу %d (за %.0f с)" % [
		sheltered, dead, outside, fought, float(t) / 60.0])
	verdict("B1 под ударами конницы рабочие не вступают в бой", fought == 0, "%d отвечали" % fought)
	verdict("B2 все выжившие добежали до замка", outside == 0 and sheltered > 0,
		"снаружи %d, в укрытии %d" % [outside, sheltered])
	GameManager.toggle_worker_alert(F)
	_free(riders)
	_free(ws)
	c.queue_free()
	await pframes(5)

# ─────────────────────────────────────────────────────────────────────────────
# C. «В ЗАМОК» ДЕСЯТИ ОТРЯДОВ ОДНИМ КЛИКОМ
# ─────────────────────────────────────────────────────────────────────────────
func _c_to_castle() -> void:
	print("\n═════ C. «В ЗАМОК» С ПЕРВОГО КЛИКА ═════")
	var base := Vector3(-110, 0, -40)
	_clear(base, 60.0)
	await pframes(3)
	var c: Building = Castle.new()
	_place(c, base)
	await pframes(10)
	var all: Array = []
	var sids: Array = []
	for k in range(10):
		var men: Array = _squad("spearman", base + Vector3(-40.0 + float(k % 5) * 7.0, 0, 18.0 + float(k / 5) * 7.0), 12, F, 4)
		for m in men:
			(m as Unit).current_health = (m as Unit).max_health * 0.5
		all.append_array(men)
		sids.append((men[0] as Unit).squad_id)
	await pframes(10)
	var sm = main.selection_manager
	sm.select_units(all)
	main.hud._on_send_to_castle(sm)
	await pframes(60)
	var going := 0
	for m2 in _alive(all):
		if (m2 as Unit).retreating or (m2 as Unit).garrisoned:
			going += 1
	verdict("C1 через 1 с после клика все бойцы всех 10 отрядов уходят в замок (отход)",
		going == _alive(all).size(), "%d из %d" % [going, _alive(all).size()])
	var t := 0
	var inside := 0
	while t < 60 * 50:
		await pframes(30)
		t += 30
		inside = 0
		for s in sids:
			if (c as Castle)._slot_of(int(s)) >= 0:
				inside += 1
		if inside >= 8:
			break
	await pframes(240)
	var waiting := 0
	var ring: float = (c as Castle).ring_radius()
	for s2 in sids:
		if (c as Castle)._slot_of(int(s2)) >= 0:
			continue
		var cc: Vector2 = GameManager.squad_centre_xz(int(s2))
		if cc.x != INF and Vector2(cc.x - base.x, cc.y - base.z).length() <= ring + 12.0:
			waiting += 1
	print("  C: внутри %d отрядов, у ворот ждут %d (лимит %d)" % [inside, waiting, (c as Castle).garrison_limit()])
	verdict("C2 восемь отрядов внутри, остальные ждут у ворот", inside == 8 and waiting == 2,
		"внутри %d, у ворот %d" % [inside, waiting])
	sm.clear_selection()
	_free(all)
	c.queue_free()
	await pframes(10)

# ─────────────────────────────────────────────────────────────────────────────
# D. АТАКА КРЕПОСТИ: ОТРЯД НЕ РВЁТСЯ
# ─────────────────────────────────────────────────────────────────────────────
## Компоненты связности бойцов (звено LINK м): размер крупнейшей
func _largest_component(men: Array, link: float) -> int:
	var pts: Array = []
	for m in men:
		pts.append((m as Node3D).global_position)
	var seen: Array = []
	seen.resize(pts.size())
	seen.fill(false)
	var best := 0
	for i in range(pts.size()):
		if seen[i]:
			continue
		var stack := [i]
		seen[i] = true
		var n := 0
		while not stack.is_empty():
			var a: int = stack.pop_back()
			n += 1
			for j in range(pts.size()):
				if not seen[j] and (pts[a] as Vector3).distance_to(pts[j]) <= link:
					seen[j] = true
					stack.append(j)
		best = maxi(best, n)
	return best

func _d_castle_split() -> void:
	print("\n═════ D. АТАКА КРЕПОСТИ ДВУМЯ ОТРЯДАМИ ═════")
	var at := Vector3(-40, 0, 40)
	_clear(at, 60.0)
	await pframes(3)
	var c: Building = Castle.new()
	_place(c, at, E)
	await pframes(10)
	c.max_health *= 50.0
	c.current_health = c.max_health
	var men: Array = []
	var n: int = _UCfgT.squad_size("spearman")
	men.append_array(_squad("spearman", at + Vector3(-12, 0, 28), n, F, 10))
	men.append_array(_squad("spearman", at + Vector3(2, 0, 28), n, F, 10))
	await pframes(20)
	var sm = main.selection_manager
	sm.select_units(men)
	sm._ring_squads_around(c)
	for u in men:
		(u as Unit).command_attack(c, true, true, true)
	sm.clear_selection()
	# Ось подхода: от замка к стартовой точке отрядов
	var axis := Vector3(0, 0, 1)
	var worst_behind := 0
	var worst_split := 0
	var t := 0
	while t < 60 * 40:
		await pframes(30)
		t += 30
		if t < 60 * 12:
			continue
		var alive: Array = _alive(men)
		var behind := 0
		for u2 in alive:
			var rel: Vector3 = (u2 as Node3D).global_position - c.global_position
			rel.y = 0.0
			# За замком: по другую сторону от подхода, дальше полугабарита
			if rel.dot(axis) < -maxf(c.build_size.x, c.build_size.z) * 0.5:
				behind += 1
		worst_behind = maxi(worst_behind, behind)
		# Разрыв — внутри КАЖДОГО отряда: два отряда законно стоят в разных
		# секторах кольца осады (SelectionManager._ring_squads_around)
		var split := 0
		for half in [men.slice(0, n), men.slice(n)]:
			var ah: Array = _alive(half)
			split += ah.size() - _largest_component(ah, 3.0)
		worst_split = maxi(worst_split, split)
	print("  D: за замком (пик) %d из %d, вне основного тела (пик) %d" % [worst_behind, men.size(), worst_split])
	verdict("D1 отряды не уходят за замок «вверх по карте»", worst_behind <= men.size() / 20,
		"за замком %d" % worst_behind)
	verdict("D2 отряд не рвётся: вне основного тела ≤ 5 %", worst_split <= men.size() / 20,
		"оторвались %d" % worst_split)
	_free(men)
	c.queue_free()
	await pframes(10)

# ─────────────────────────────────────────────────────────────────────────────
# E. ОХРАНА РУДНИКА ПРОСЫПАЕТСЯ ОТ ОБСТРЕЛА
# ─────────────────────────────────────────────────────────────────────────────
func _e_guard_wake() -> void:
	print("\n═════ E. СПЯЩАЯ ОХРАНА РУДНИКА ПОД ОБСТРЕЛОМ ═════")
	var gai = main.get("goblin_ai")
	var pick_sid := 0
	var mine_p := Vector3.ZERO
	for sid in gai.guards:
		var g: Dictionary = gai.guards[sid]
		var m = g["mine"]
		if m == null or not is_instance_valid(m) or not GameManager.squads.has(int(sid)):
			continue
		var mem: Array = _alive((GameManager.squads[int(sid)] as Dictionary)["members"])
		if mem.size() >= 4 and String(GameManager.squad_type(int(sid))) == "goblin_spearman":
			pick_sid = int(sid)
			mine_p = (m as Node3D).global_position
			break
	if pick_sid == 0:
		verdict("E0 на карте есть охрана рудника", false)
		return
	var gmem: Array = _alive((GameManager.squads[pick_sid] as Dictionary)["members"])
	for u in gmem:
		(u as Unit).set_dormant(true)
	var gc: Vector3 = GameManager._centroid_of(gmem)
	# Стрелки с внешней стороны от рудника, в 13 м от охраны
	var away: Vector3 = gc - mine_p
	away.y = 0.0
	away = away.normalized() if away.length() > 0.5 else Vector3.RIGHT
	var spot: Vector3 = gc + away * 13.0
	main._clear_trees(spot, 6.0)
	var arch: Array = _squad("archer", spot, 12, F, 4)
	await pframes(5)
	gai.set_physics_process(true)
	gai.set_process(true)
	for a in arch:
		(a as Unit).command_attack(gmem[0], true)
	var woke_t := -1.0
	var engaged := 0
	var t := 0
	while t < 60 * 8:
		await pframes(10)
		t += 10
		var dorm := 0
		engaged = 0
		for u2 in _alive(gmem):
			if (u2 as Unit).dormant:
				dorm += 1
			var tg = (u2 as Unit).attack_target
			if tg != null and is_instance_valid(tg) and tg is Unit and (tg as Unit).faction == F:
				engaged += 1
		if dorm == 0 and woke_t < 0.0:
			woke_t = float(t) / 60.0
		if woke_t >= 0.0 and engaged >= _alive(gmem).size() / 2:
			break
	print("  E: охрана проснулась за %s с, на стрелков пошли %d из %d" % [
		("%.2f" % woke_t) if woke_t >= 0.0 else "—", engaged, _alive(gmem).size()])
	verdict("E1 спящая охрана просыпается от обстрела (≤ 1 с)", woke_t >= 0.0 and woke_t <= 1.0,
		"за %s с" % str(woke_t))
	verdict("E2 охрана идёт в бой на стрелков", engaged >= maxi(1, _alive(gmem).size() / 2),
		"%d из %d" % [engaged, _alive(gmem).size()])
	gai.set_physics_process(false)
	gai.set_process(false)
	_free(arch)
	await pframes(5)

# ─────────────────────────────────────────────────────────────────────────────
# F. МОНАХ: ЗНАК МЕДИЦИНЫ И ЗВУК СНАДОБЬЯ; МЕЧ И ТОПОР ШИРЕ
# ─────────────────────────────────────────────────────────────────────────────
func _bbox(kind: int) -> Rect2i:
	var tex: Texture2D = _CursorArtT.texture(kind)
	if tex == null:
		return Rect2i()
	return tex.get_image().get_used_rect()

func _f_monk_cursor() -> void:
	print("\n═════ F. КУРСОР И ЗВУК МОНАХА ═════")
	var at := Vector3(-60, 0, 60)
	_clear(at, 30.0)
	await pframes(3)
	var monks: Array = _squad("monk", at + Vector3(-6, 0, 0), 1)
	var men: Array = _squad("spearman", at + Vector3(2, 0, 0), 12, F, 4)
	await pframes(5)
	var sm = main.selection_manager
	var cam = main.get("_camera")
	cam.set_process(false)
	main.set_process(false)
	var target := men[5] as Unit
	cam.jump_to(target.global_position, 22.0)
	await frames(4)
	sm.selected_units = monks.duplicate()
	sm._sel_set.clear()
	for m in monks:
		sm._sel_set[m] = true
	var sp: Vector2 = cam.unproject_position(target.global_position + Vector3(0, 0.8, 0))
	var k_full: int = sm.hover_cursor_kind(sp)
	(men[2] as Unit).current_health = (men[2] as Unit).max_health * 0.4
	(men[2] as Unit)._soa_push_stats()
	var k_hurt: int = sm.hover_cursor_kind(sp)
	verdict("F1 монах над раненым своим отрядом — знак медицины", k_hurt == _CursorArtT.MEDIC,
		"вид %d (над целым отрядом %d)" % [k_hurt, k_full])
	verdict("F2 над целым отрядом знака нет", k_full != _CursorArtT.MEDIC)
	var orders0: int = int(sm.monk_heal_orders)
	sm._handle_right_click(sp)
	await pframes(3)
	var stream: AudioStream = AudioManager._stream(AudioManager.HEAL_POTION_ID)
	verdict("F3 ПКМ — приказ лечить и звук снадобья", int(sm.monk_heal_orders) == orders0 + 1
		and stream != null and AudioManager.UI_BANK.has("monk_heal"),
		"приказов %d → %d, поток %s" % [orders0, int(sm.monk_heal_orders), stream != null])
	var arrow: Texture2D = load("res://scripts/UIAssets.gd").cursor(1)
	var ar: Rect2i = arrow.get_image().get_used_rect() if arrow != null else Rect2i()
	var sw: Rect2i = _bbox(_CursorArtT.SWORD)
	var ax: Rect2i = _bbox(_CursorArtT.AXE)
	var sw_px := 0
	var simg: Image = _CursorArtT.texture(_CursorArtT.SWORD).get_image()
	for y in range(simg.get_height()):
		for x in range(simg.get_width()):
			if simg.get_pixel(x, y).a > 0.5:
				sw_px += 1
	print("  F: стрелка %dx%d, меч %dx%d (%d px), топор %dx%d" % [ar.size.x, ar.size.y,
		sw.size.x, sw.size.y, sw_px, ax.size.x, ax.size.y])
	verdict("F4 меч и топор не уже стрелки курсора", sw.size.x >= ar.size.x and ax.size.x >= ar.size.x
		and sw_px >= 200, "стрелка %d, меч %d (%d px), топор %d" % [ar.size.x, sw.size.x, sw_px, ax.size.x])
	main.set_process(true)
	cam.set_process(true)
	sm.clear_selection()
	_free(monks)
	_free(men)
	await pframes(5)

# ─────────────────────────────────────────────────────────────────────────────
# G. ДОМА: 35 ОТРЯДОВ ДОСТИЖИМЫ
# ─────────────────────────────────────────────────────────────────────────────
func _g_houses() -> void:
	print("\n═════ G. ДОМА НА 35 ОТРЯДОВ ═════")
	var per: int = maxi(_UCfgT.squad_size("spearman"), 1)
	var need_h: int = 0
	while int(floor(float(_UCfgT.pop_army_cap(need_h, 1)) / float(per))) < 35 and need_h < 80:
		need_h += 1
	var total := 0.0
	for k in range(need_h):
		total += _UCfgT.building_cost_mult("house", k)
	var last: float = _UCfgT.building_cost_mult("house", need_h - 1)
	print("  G: на 35 отрядов нужно домов %d, последний ×%.2f, всего %.1f базовых цен" % [need_h, last, total])
	verdict("G1 35 отрядов достижимы: последний дом не дороже ×6 базы", need_h <= 26 and last <= 6.0,
		"домов %d, последний ×%.2f" % [need_h, last])
	verdict("G2 все дома на 35 отрядов — не больше 60 базовых цен", total <= 60.0, "%.1f" % total)

# ─────────────────────────────────────────────────────────────────────────────
# H. НАЙМ ПОВЕРХ ЛИМИТА: КРАСНАЯ ПЛАШКА
# ─────────────────────────────────────────────────────────────────────────────
func _h_pop_alert() -> void:
	print("\n═════ H. «ПРЕВЫШЕН ЛИМИТ НАСЕЛЕНИЯ!» ═════")
	var at := Vector3(-90, 0, 90)
	_clear(at, 30.0)
	await pframes(3)
	var b: Building = _BarracksT.new()
	_place(b, at)
	await pframes(10)
	var was: bool = GameManager.pop_limit_enabled
	GameManager.pop_limit_enabled = true
	var extra: Array = []
	var lim: int = GameManager.pop_squad_limit(F)
	for k in range(lim + 1):
		extra.append_array(_squad("spearman", at + Vector3(-30.0 + float(k % 6) * 4.0, 0, 12.0 + float(k / 6) * 4.0), 1, F, 1))
	await pframes(3)
	var allowed: bool = GameManager.pop_allows(F, "spearman")
	var hud = main.hud
	var a0: int = int(hud.pop_alerts)
	var q0: int = b.production_queue.size()
	hud._on_train_click(b, "spearman")
	await frames(2)
	var node: Control = hud.get_node_or_null("PopLimitAlert") as Control
	var txt: String = ""
	if node != null:
		var lbl: Label = node.get_node_or_null("PopLimitText") as Label
		if lbl != null:
			txt = lbl.text
	verdict("H1 клик найма поверх лимита — плашка «Превышен лимит населения!», заказа нет",
		not allowed and int(hud.pop_alerts) == a0 + 1 and txt == "Превышен лимит населения!"
		and b.production_queue.size() == q0,
		"разрешено %s, плашек %d → %d, текст «%s»" % [allowed, a0, int(hud.pop_alerts), txt])
	GameManager.pop_limit_enabled = was
	_free(extra)
	b.queue_free()
	await pframes(5)
