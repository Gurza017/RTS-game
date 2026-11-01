extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 25.10.2026: ГОБЛИНЫ БЕЗ КОРОБОК, НАТИСК КОРОБОК, ЗНАМЁНА,
## ЛЫЧКИ СВЕРХ ЛЕГЕНДЫ, ЗОНДЫ ОТРЯДОВ, ЗНАЧКИ HUD
## ═══════════════════════════════════════════════════════════════════════════
##   A ГОБЛИНЫ  — в свалке с копейщиками ни один отряд орды не встаёт в
##                коробку, а наши — встают (блок 2 ТЗ)
##   B НАТИСК   — коробка с перевесом напора теснит чужую коробку: линия
##                фронта едет; та же сцена с box_press=false стоит (блок 4)
##   C ЗНАМЁНА  — орда: зелёные язычки крупнее людских, в панике ТОТ ЖЕ флаг
##                белеет; легенда: золотой квадрат, мини-флажки (блок 3)
##   D ЛЫЧКИ    — сверх легенды: пороги растут с увеличением шага; без
##                штандарта — цветные мини-флажки, со штандартом — его уровень
##   E ЗОНДЫ    — squad_split на порванном отряде, order_override_bug на
##                снятии приказа внутренней механикой, stuck_running на бойцах,
##                «бегущих» по кругу на месте (блок 5)
##   F HUD      — плашка бездельников вдвое меньше, значок рудников справа той
##                же величины с мелкой цифрой; иконка рудника — шахта (письмо UI)
## ЧИСЛА НЕ ХАРДКОДЯТСЯ: пороги, масштабы, цвета — из конфигов и модулей.
## Запуск: godot --headless --path . res://qa_tz1025/Test.tscn [-- only=abcdef]

const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const G := Constants.FACTION_GOBLIN
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _BA := preload("res://scripts/BannerArt.gd")
const _SB := preload("res://scripts/SquadBanner.gd")
const _Opt := preload("res://scripts/perf_config.gd")

var main: Node = null
var sm = null
var _pass := 0
var _fail := 0
var _log: Array = []
## Бойцы, которых стенд водит по кругу (блок E, stuck_running)
var _circle: Array = []
var _circle_c: Vector3 = Vector3.ZERO

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд завис")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else: _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_tz1025 ═════")
	for e in _log:
		if not bool(e[1]):
			print("  НЕ ПРОШЛО: %s" % String(e[0]))
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)

func _physics_process(_d: float) -> void:
	# Блок E: бойцы «бегут» по кругу радиусом 0.2 м с периодом 0.5 с — за
	# окно ленты (0.2 с) смещаются на ~0.38 м (лента ходьбы), за окно зонда
	# (0.5 с) возвращаются в ту же точку
	if _circle.is_empty():
		return
	var t: float = float(Unit.game_ms()) * 0.001
	var k := 0
	for m in _circle:
		if m == null or not is_instance_valid(m):
			continue
		var u: Unit = m
		var a: float = TAU * t / 0.5 + float(k)
		var p := _circle_c + Vector3(float(k) * 2.0 + cos(a) * 0.2, 0.0, sin(a) * 0.2)
		p.y = GameManager.get_terrain_height(p.x, p.z)
		u.global_position = p
		u.sync_row()
		k += 1

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _wipe(at: Vector3, r: float) -> void:
	main._clear_area_of_resources(at, r)
	main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()

func _box(uid: String, fac: int, front_c: Vector3, course: Vector3, n: int, cols: int, gap: float) -> int:
	var sid: int = GameManager.new_squad(fac, uid)
	var side := Vector3(-course.z, 0.0, course.x)
	var slots: Array = []
	for i in range(n):
		var p: Vector3 = front_c + side * ((float(i % cols) - float(cols - 1) * 0.5) * gap) \
			- course * (float(i / cols) * gap)
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = fac
		main.world_add(u)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		u._facing = course
		u.formation_row = i / cols
		GameManager.add_to_squad(sid, u)
		slots.append(u.global_position)
	GameManager.squad_set_formation(sid, slots, course, false)
	return sid

func _crowd(fac: int, base: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(fac, "goblin_spearman")
	var slots: Array = []
	for k in range(n):
		var ho: Vector2 = _GobCfg.horde_offset(k, n, sid)
		var u: Unit = Building.PRELOAD_SCENES["goblin_spearman"].instantiate()
		u.faction = fac
		main.world_add(u)
		var x: float = base.x + ho.x
		var z: float = base.z + ho.y
		u.global_position = Vector3(x, GameManager.get_terrain_height(x, z), z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		slots.append(u.global_position)
	GameManager.squad_set_formation(sid, slots, Vector3(-1, 0, 0), false)
	return sid

func _kill_all(sids: Array) -> void:
	for s in sids:
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)
	await pframes(30)

func _spot(dx: float, dz: float) -> Vector3:
	return main.PLAYER_BASE_ANCHOR + Vector3(dx, 0.0, dz)

func _run() -> void:
	seed(25102026)
	# Коробки выключены по развороту ТЗ 25.10.2026 (третье письмо, п. 2):
	# стенд механики включает ручку сам, если её не задали явно (knob=box_front:N)
	var _knob_set := false
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("knob=box_front"):
			_knob_set = true
	if not _knob_set:
		preload("res://scripts/perf_config.gd").box_front = true
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.probes.print_lines = false
	sm = main.selection_manager
	var only := "abcdef"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			only = String(a).substr(5)
	if "a" in only: await _block_a()
	if "b" in only: await _block_b()
	if "c" in only: await _block_c()
	if "d" in only: _block_d()
	if "e" in only: await _block_e()
	if "f" in only: _block_f()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ГОБЛИНЫ БЕЗ КОРОБОК
# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. ГОБЛИНЫ БЕЗ КОРОБОК ═════")
	var spot: Vector3 = _spot(45.0, 15.0)
	_wipe(spot, 70.0)
	await pframes(10)
	var course := Vector3(1, 0, 0)
	var n_sp: int = int(_UCfg.train_cfg("barracks", "spearman").get("squad", 60))
	var n_gb: int = _UCfg.squad_size("goblin_spearman")
	var mine: Array = []
	var foes: Array = []
	for i in range(3):
		var z: float = spot.z + (float(i) - 1.0) * 12.0
		mine.append(_box("spearman", F, Vector3(spot.x - 10.0, 0, z), course, n_sp, 12, 0.55))
		foes.append(_crowd(G, Vector3(spot.x + 10.0, 0, z), n_gb))
	await pframes(10)
	for i in range(3):
		var tf: Array = _members(int(foes[i]))
		for u in _members(int(mine[i])):
			(u as Unit).command_attack(tf[0], true, true, true)
		var tm: Array = _members(int(mine[i]))
		for g in _members(int(foes[i])):
			(g as Unit).command_attack(tm[0], true, false, false)
	var gob_boxed := 0
	var ours_boxed := 0
	for _k in range(40):
		await pframes(30)
		for s in foes:
			if not GameManager.box.box_of(int(s)).is_empty():
				gob_boxed += 1
		for s2 in mine:
			if not GameManager.box.box_of(int(s2)).is_empty():
				ours_boxed += 1
	verdict("A1 ни один отряд орды не встал в коробку за 20 с свалки", gob_boxed == 0,
		"тактов с коробкой орды %d" % gob_boxed)
	verdict("A2 наши копейщики в той же свалке держат коробку", ours_boxed > 0,
		"тактов с коробкой наших %d" % ours_boxed)
	verdict("A3 род goblin_spearman исключён из BOX_TYPES",
		not GameManager.box.BOX_TYPES.has("goblin_spearman"))
	await _kill_all(mine + foes)

# ═════════════════════════════════════════════════════════════════════════════
# B. НАТИСК КОРОБОК
# ═════════════════════════════════════════════════════════════════════════════
## Медиана положения бойцов отряда вдоль курса
func _median_along(sid: int, course: Vector3) -> float:
	var v: Array = []
	for u in _members(sid):
		v.append((u as Unit).global_position.dot(course))
	if v.is_empty():
		return 0.0
	v.sort()
	return float(v[v.size() / 2])

## Один бой «сильные на равных по числу»: наши копейщики с напором +boost
## против красных копейщиков. Возвращает [сдвиг линии фронта к врагу, м;
## натисков за бой]
func _press_fight(spot: Vector3, boost: float, secs: int) -> Array:
	_wipe(spot, 60.0)
	await pframes(10)
	var course := Vector3(1, 0, 0)
	var n: int = 48
	var mine: int = _box("spearman", F, Vector3(spot.x - 3.0, 0, spot.z), course, n, 12, 0.55)
	var foe: int = _box("spearman", R, Vector3(spot.x + 3.0, 0, spot.z), -course, n, 12, 0.55)
	for u in _members(mine):
		(u as Unit).push_force += boost
		# Бой не должен кончиться раньше замера: живучесть обеих сторон ×6
		(u as Unit).max_health *= 6.0
		(u as Unit).current_health = (u as Unit).max_health
		(u as Unit)._soa_push_stats()
	for e in _members(foe):
		(e as Unit).max_health *= 6.0
		(e as Unit).current_health = (e as Unit).max_health
		(e as Unit)._soa_push_stats()
	await pframes(5)
	var fm: Array = _members(foe)
	var mm: Array = _members(mine)
	for u in mm:
		(u as Unit).command_attack(fm[0], true, false, false)
	for e in fm:
		(e as Unit).command_attack(mm[0], true, false, false)
	# Ждём, пока обе коробки встанут в контакт
	var t0 := -1
	for k in range(60 * 15):
		await get_tree().physics_frame
		if not GameManager.box.box_of(foe).is_empty() and not GameManager.box.box_of(mine).is_empty():
			t0 = k
			break
	await pframes(60 * 2)
	var p0: int = GameManager.box.presses
	var f0: float = _median_along(foe, course)
	await pframes(60 * secs)
	var f1: float = _median_along(foe, course)
	var pr: int = GameManager.box.presses - p0
	print("  натиск +%.1f: контакт через %d кадров, чужая медиана %.2f → %.2f, натисков %d, наших %d / чужих %d" % [
		boost, t0, f0, f1, pr, _members(mine).size(), _members(foe).size()])
	await _kill_all([mine, foe])
	return [f1 - f0, pr]

func _block_b() -> void:
	print("\n═════ B. НАТИСК КОРОБОК ═════")
	var was: bool = _Opt.box_press
	_Opt.box_press = true
	var on: Array = await _press_fight(_spot(40.0, -30.0), 4.0, 15)
	_Opt.box_press = false
	var off: Array = await _press_fight(_spot(40.0, -30.0), 4.0, 15)
	_Opt.box_press = was
	verdict("B1 сильная коробка теснит: линия фронта уехала к врагу ≥ 1 м за 15 с",
		float(on[0]) >= 1.0, "сдвиг %.2f м" % float(on[0]))
	verdict("B2 натиск сработал (presses > 0)", int(on[1]) > 0, "натисков %d" % int(on[1]))
	verdict("B3 без натиска (box_press=false) линия стоит заметно ближе",
		float(off[0]) < float(on[0]) - 1.0, "с натиском %.2f, без %.2f" % [float(on[0]), float(off[0])])

# ═════════════════════════════════════════════════════════════════════════════
# C. ЗНАМЁНА
# ═════════════════════════════════════════════════════════════════════════════
## Счёт пикселей по признаку цвета
func _count(tex: Texture2D, pred: Callable) -> int:
	if tex == null:
		return -1
	var img: Image = tex.get_image()
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5 and pred.call(c):
				n += 1
	return n

## Маска непрозрачности (для «та же форма»)
func _alpha_mask(tex: Texture2D) -> PackedByteArray:
	var img: Image = tex.get_image()
	var out := PackedByteArray()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			out.append(1 if img.get_pixel(x, y).a > 0.5 else 0)
	return out

func _block_c() -> void:
	print("\n═════ C. ЗНАМЁНА ═════")
	var is_green := func(c: Color) -> bool: return c.g > 0.45 and c.g > c.r * 1.6 and c.g > c.b * 1.6
	var is_white := func(c: Color) -> bool: return c.r > 0.85 and c.g > 0.85 and c.b > 0.8
	var is_gold := func(c: Color) -> bool: return c.r > 0.8 and c.g > 0.6 and c.b < 0.35
	var gt: Texture2D = _BA.goblin_tongue_texture(4)
	var gw: Texture2D = _BA.goblin_tongue_texture(4, true)
	var gr: int = _count(gt, is_green)
	verdict("C1 знамя орды — насыщенный зелёный", gr > 300, "зелёных пикселей %d" % gr)
	verdict("C2 белый флаг орды — без зелени, тот же силуэт язычков",
		_count(gw, is_green) == 0 and _count(gw, is_white) > 300 and _alpha_mask(gt) == _alpha_mask(gw),
		"зелёных %d, белых %d" % [_count(gw, is_green), _count(gw, is_white)])
	verdict("C3 знамя орды крупнее людского вымпела (GOBLIN_SCALE > 1)",
		float(_SB.spec(4, false, true, 0)[1]) > 1.0, "k = %.2f" % float(_SB.spec(4, false, true, 0)[1]))
	# Паника: тот же узел знамени орды белеет (а не людской вымпел)
	var spot: Vector3 = _spot(40.0, 40.0)
	_wipe(spot, 30.0)
	await pframes(5)
	var gsid: int = _crowd(G, spot, 12)
	(GameManager.squads[gsid] as Dictionary)["level"] = 4
	GameManager.refresh_squad_banner(gsid)
	var bn = (GameManager.squads[gsid] as Dictionary).get("banner")
	var before_ok: bool = bn != null and is_instance_valid(bn) and bool(bn.shown_goblin)
	(GameManager.squads[gsid] as Dictionary)["panic_until"] = Unit.game_ms() + 8000
	GameManager.refresh_squad_banner(gsid)
	bn = (GameManager.squads[gsid] as Dictionary).get("banner")
	var ok_w: bool = bn != null and is_instance_valid(bn) and bool(bn.shown_white) and bool(bn.shown_goblin)
	verdict("C4 паника орды: знамя белеет своими язычками",
		before_ok and ok_w and _SB.spec(4, false, true, 0, 0, true)[0] == gw,
		"белое %s" % (str(bn.shown_white) if bn != null else "-"))
	await _kill_all([gsid])
	# Легенда
	var top: int = _UCfg.VET_BANNER_TIERS.size()
	var leg: Dictionary = _UCfg.veteran_banner_tier(top)
	# РАЗВОРОТ ТЗ 30.10.2026: легенда — золотой вымпел той же формы, что шкала
	verdict("C5 легендарный ранг — золотой вымпел (признак legend)",
		bool(leg.get("legend", false)) and int(leg.get("shape", -1)) == _UCfg.BANNER_PENNANT)
	var l0: Texture2D = _BA.legend_texture(0)
	# РАЗВОРОТ ТЗ 31.10.2026: легенда — синее поле в фиолетовой рамке, жёлтого нет
	var is_purple := func(c: Color) -> bool: return c.a > 0.5 and absf(c.r - _UCfg.BANNER_PURPLE.r) < 0.06 		and absf(c.g - _UCfg.BANNER_PURPLE.g) < 0.06 and absf(c.b - _UCfg.BANNER_PURPLE.b) < 0.06
	verdict("C6 легендарный флаг — фиолетовая рамка, без золота", _count(l0, is_purple) > 30 and _count(l0, is_gold) < 20,
		"рамка %d, золотых %d" % [_count(l0, is_purple), _count(l0, is_gold)])
	# Чистая легенда — ни бордового отростка, ни красных лычек
	var bord := 0
	var img0: Image = l0.get_image()
	for y in range(img0.get_height()):
		for x in range(img0.get_width()):
			var c: Color = img0.get_pixel(x, y)
			if c.a > 0.5 and absf(c.r - _BA.ELITE_CLOTH.r) < 0.06 and absf(c.g - _BA.ELITE_CLOTH.g) < 0.06 \
					and absf(c.b - _BA.ELITE_CLOTH.b) < 0.06:
				bord += 1
	verdict("C7 чистая легенда — без бордового отростка", bord == 0, "бордовых пикселей %d" % bord)
	var top_l: int = _UCfg.VET_BANNER_TIERS.size()
	# Штандарт за общий опыт у легенды — бордовый; пятак показывает РАНГ (ТЗ 30.10)
	verdict("C8 штандарт игрока у легенды — бордовый, без штандарта — чистое золото",
		_SB.spec(top_l, true, false, 3, 0)[0] == _BA.elite_texture(3, top_l) and _SB.spec(top_l, false, false, 0, 0)[0] == l0)
	verdict("C9 ступени престижа — разные ленты", _BA.legend_texture(1) != _BA.legend_texture(3))
	verdict("C10 флажок ранга в панели у легенды той же рамки, что у шкалы (crop_for)",
		_BA.crop_for(top) == _BA.crop_for(2), "%s / %s" % [str(_BA.crop_for(top)), str(_BA.crop_for(2))])

# ═════════════════════════════════════════════════════════════════════════════
# D. ЛЫЧКИ СВЕРХ ЛЕГЕНДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _block_d() -> void:
	print("\n═════ D. ЛЫЧКИ СВЕРХ ЛЕГЕНДЫ ═════")
	var ut := "spearman"
	var top: int = _UCfg.max_veteran_level(ut)
	var last: int = _UCfg.veteran_threshold(ut, top)
	var t1: int = _UCfg.legend_extra_threshold(ut, 1)
	var t2: int = _UCfg.legend_extra_threshold(ut, 2)
	var t3: int = _UCfg.legend_extra_threshold(ut, 3)
	verdict("D1 пороги лычек выше легенды и шаг растёт",
		t1 > last and t2 - t1 > t1 - last and t3 - t2 > t2 - t1,
		"легенда %d → %d, %d, %d" % [last, t1, t2, t3])
	verdict("D2 больше LEGEND_EXTRA_MAX лычек нет",
		_UCfg.legend_extra_threshold(ut, _UCfg.LEGEND_EXTRA_MAX + 1) < 0)
	# Отряд без штандарта: мини-флажки
	var spot: Vector3 = _spot(40.0, 60.0)
	var sid: int = _box("spearman", F, spot, Vector3(1, 0, 0), 12, 6, 0.55)
	var u0: Unit = _members(sid)[0]
	GameManager.credit_kills(sid, last)
	var sq: Dictionary = GameManager.squads[sid]
	verdict("D3 отряд на легенде", int(sq["level"]) == top, "уровень %d" % int(sq["level"]))
	var att0: float = u0.vet_attack
	GameManager.credit_kills(sid, t2 - last)
	var bn = sq.get("banner")
	verdict("D4 две ступени престижа — на знамени хвост второй ступени",
		int(sq.get("legend_extra", 0)) == 2 and bn != null and int(bn.shown_flags) == 2,
		"ступеней %d, на знамени %s" % [int(sq.get("legend_extra", 0)),
			str(bn.shown_flags) if bn != null else "-"])
	verdict("D5 каждая лычка — ещё ступень прибавок рода", u0.vet_attack > att0,
		"атака %.2f → %.2f" % [att0, u0.vet_attack])
	# Штандарт игрока на легенду: элита ставится, уровень штандарта растёт лычкой
	GameManager.grant_squad_level(sid)
	var el0: int = GameManager.squad_elite_level(sid)
	verdict("D6 штандарт игрока выдаётся и легендарному отряду", GameManager.squad_elite(sid) and el0 >= 1,
		"элита %s, уровень %d" % [str(GameManager.squad_elite(sid)), el0])
	GameManager.credit_kills(sid, t3 - t2)
	# РАЗВОРОТ ТЗ 29.10.2026: личный опыт (престиж) уровень штандарта не
	# растит — он только от общего опыта
	verdict("D7 ступень престижа уровень штандарта не меняет",
		GameManager.squad_elite_level(sid) == el0 and int(sq.get("legend_extra", 0)) == 3,
		"уровень %d → %d" % [el0, GameManager.squad_elite_level(sid)])
	bn = sq.get("banner")
	verdict("D8 знамя: ступень престижа 3 записана, висит бордовый штандарт",
		bn != null and int(bn.shown_flags) == 3 and bool(bn.shown_elite), "на знамени %s" % (str(bn.shown_flags) if bn != null else "-"))
	GameManager.credit_kills(sid, 5000)
	verdict("D9 потолок лычек держится", int(sq.get("legend_extra", 0)) == _UCfg.LEGEND_EXTRA_MAX)
	for m in _members(sid):
		(m as Unit).take_damage(1.0e12)

# ═════════════════════════════════════════════════════════════════════════════
# E. ЗОНДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _block_e() -> void:
	print("\n═════ E. ЗОНДЫ ═════")
	var pr = GameManager.probes
	var spot: Vector3 = _spot(-40.0, 40.0)
	_wipe(spot, 50.0)
	await pframes(5)
	# Разрыв: 20 копейщиков двумя кучами в 20 м
	var sid: int = _box("spearman", F, spot, Vector3(1, 0, 0), 10, 5, 0.55)
	var sid_b: int = _box("spearman", F, spot + Vector3(0, 0, 20), Vector3(1, 0, 0), 10, 5, 0.55)
	for u in _members(sid_b):
		GameManager.add_to_squad(sid, u)
	var sp: Dictionary = pr.split_of(sid)
	verdict("E1 squad_split видит отряд, порванный на две кучи в 20 м",
		not sp.is_empty() and float(sp.get("gap", 0.0)) > 15.0 and int(sp.get("a", 0)) >= 8,
		str(sp))
	var whole: int = _box("spearman", F, spot + Vector3(15, 0, 0), Vector3(1, 0, 0), 20, 5, 0.55)
	verdict("E2 целый отряд разрывом не считается", pr.split_of(whole).is_empty())
	# Сброс приказа: замок цели снят отходом и внутренним приказом на движение
	var foe: int = _box("spearman", R, spot + Vector3(30, 0, 0), Vector3(-1, 0, 0), 6, 3, 0.55)
	var u1: Unit = _members(whole)[0]
	var e1: Unit = _members(foe)[0]
	pr.flush_now()
	var r0: int = pr.override_reports
	u1.command_attack(e1, true, false, true)
	u1.begin_retreat()
	pr.flush_now()
	var ok_ret: bool = pr.override_reports > r0 and String(pr.last_override.get("reason", "")) == "retreat"
	verdict("E3 order_override_bug: замок приказа снят отходом — записан с причиной",
		ok_ret, str(pr.last_override))
	var u2: Unit = _members(whole)[1]
	u2.command_move(spot + Vector3(15, 0, 10), false, Vector3.ZERO, false, true)
	r0 = pr.override_reports
	u2.command_move(spot + Vector3(15, 0, -10))
	pr.flush_now()
	verdict("E4 внутренний приказ на движение поверх приказа игрока — записан",
		pr.override_reports > r0 and String(pr.last_override.get("reason", "")) == "internal_move_over_move",
		str(pr.last_override))
	var u3: Unit = _members(whole)[2]
	r0 = pr.override_notes
	u3.command_move(spot + Vector3(15, 0, 12), false, Vector3.ZERO, false, true)
	u3.command_move(spot + Vector3(15, 0, -12), false, Vector3.ZERO, false, true)
	verdict("E5 новый приказ игрока поверх своего — не сброс", pr.override_notes == r0)
	# Бег на месте: 4 бойца одного отряда в ходьбе водятся по кругу на месте
	var ssid: int = _box("spearman", F, spot + Vector3(-15, 0, -15), Vector3(1, 0, 0), 4, 4, 0.55)
	var far: Vector3 = spot + Vector3(-15, 0, -60)
	_circle_c = spot + Vector3(-18, 0, -15)
	for u in _members(ssid):
		(u as Unit).command_move(far)
		_circle.append(u)
	# Контроль: 4 бойца другого отряда честно идут
	var wsid: int = _box("spearman", F, spot + Vector3(-15, 0, 15), Vector3(1, 0, 0), 4, 4, 0.55)
	for u in _members(wsid):
		(u as Unit).command_move(spot + Vector3(-15, 0, 60))
	var s0: int = pr.stuck_reports
	var hit_s := false
	var hit_w := false
	for _k in range(16):
		await pframes(30)
		if pr.stuck_reports > s0:
			var sid_r: int = int(pr.last_stuck.get("sid", -1))
			if sid_r == ssid:
				hit_s = true
			if sid_r == wsid:
				hit_w = true
			s0 = pr.stuck_reports
	_circle.clear()
	verdict("E6 stuck_running: «бег на месте» по кругу пойман", hit_s,
		"последняя сводка %s" % str(pr.last_stuck))
	verdict("E7 идущий честно отряд в сводку не попал", not hit_w)
	await _kill_all([sid, whole, foe, ssid, wsid])

# ═════════════════════════════════════════════════════════════════════════════
# F. HUD
# ═════════════════════════════════════════════════════════════════════════════
func _block_f() -> void:
	print("\n═════ F. HUD ═════")
	var hud = main.hud
	var ib: Control = hud._idle_btn
	var mb: Control = hud._mine_box
	# ×1.5 к 26 px (ТЗ 27.10.2026, второе письмо: иконки HUD крупнее) —
	# размер берётся из HUD, а не числом
	verdict("F1 плашка бездельников размера HUD.IDLE_WIDGET_SIZE (26 × 1.5)", ib != null and absf(ib.size.x - float(hud.IDLE_WIDGET_SIZE)) < 0.5
			and absf(float(hud.IDLE_WIDGET_SIZE) - 39.0) < 0.5,
		"%s" % str(ib.size if ib != null else Vector2.ZERO))
	verdict("F2 значок рудников справа от плашки, той же величины",
		mb != null and mb.get_parent() == hud and absf(mb.size.x - ib.size.x) < 0.5
			and mb.position.x > ib.position.x + ib.size.x - 0.5 and absf(mb.position.y - ib.position.y) < 0.5,
		"плашка %s, рудники %s" % [str(ib.position), str(mb.position if mb != null else Vector2.ZERO)])
	var fs_m: int = hud._mine_count_lbl.get_theme_font_size("font_size")
	verdict("F3 цифра рудников мелкая (≤ трети значка)", fs_m <= int(ib.size.y / 2.5), "кегль %d" % fs_m)
	verdict("F4 иконка рудника в панели — шахта, а не кусок золота",
		String(_UCfg.building_cfg("mine").get("icon", "")).get_file() == "GoldMine_Active.png")
