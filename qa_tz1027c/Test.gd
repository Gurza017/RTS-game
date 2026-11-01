extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_TZ1027C — ТЗ 27.10.2026, третье и четвёртое письма. Headless.
## ═══════════════════════════════════════════════════════════════════════════
## A — значки «+» ауры идут за нарисованным бойцом каждый кадр, круги ауры и
##     башни без теста глубины (ручки aura_follow_draw, aura_ring_no_depth)
## B — полоса родов: строгий порядок копейщик → лучник → рыцарь → монах,
##     ячейка выше, число рядом с фигуркой, копейщик в рост монаха
## C — река: громкость +15 %, зона слышимости ×1.2
## D — опыт монахов +20 % на каждой ступени
## E — знамя легенды: хвостовой вымпел (красный → лычки → синий с лычками),
##     без цветных мини-флажков; прибавки — только за первые три лычки
## F — строй — цельный кирпичик: неполная последняя шеренга по центру
##     (ручка formation_centred_tail)
## G — лечение «бега на месте» (ручка run_in_place_cure)
## H — суровая сплочённость дерущихся (ручка cohesion_strict)
## Каждая ручка проверяется и выключением — вердикт обязан различать.
## Ручки: only=abc…

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _BannerArt := preload("res://scripts/BannerArt.gd")
const _SB_E := preload("res://scripts/SquadBanner.gd")
const _SqF := preload("res://scripts/units/SquadFormation.gd")
const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY

var main = null
var sm = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abcdefgh"
var _done := false
var _diag := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		elif String(a) == "diag=1":
			_diag = true
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz1027c: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int = 6) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var p: Vector3 = at + Vector3((float(i % cols) - float(cols - 1) * 0.5) * 0.65, 0.0, float(i / cols) * 0.65)
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

func _kill(sids: Array) -> void:
	for s in sids:
		for u in _members(int(s)):
			(u as Unit).take_damage(1.0e12)

func _wipe(at: Vector3, r: float) -> void:
	main._clear_area_of_resources(at, r)
	main._clear_trees(at, r)
	for u in GameManager._live_units.duplicate():
		if is_instance_valid(u) and not (u as Unit).is_dead() \
				and (u as Node3D).global_position.distance_to(at) < r:
			(u as Unit).take_damage(1.0e12)

func _spot(dx: float, dz: float) -> Vector3:
	return _free_spot(main.PLAYER_BASE_ANCHOR + Vector3(dx, 0.0, dz))

## Площадка, где весь квадрат ±12 м проходим и сух (ловушка «стенд на
## случайной карте»: лесная клетка навигации выносит точку приказа наружу)
func _free_spot(base: Vector3) -> Vector3:
	for ring in range(0, 8):
		for ix in range(-ring, ring + 1):
			for iz in range(-ring, ring + 1):
				if maxi(absi(ix), absi(iz)) != ring:
					continue
				var c := base + Vector3(float(ix) * 10.0, 0.0, float(iz) * 10.0)
				# В поле карты: у кромки land_target прижимает места строя
				var ok: bool = absf(c.x) < main.MAP_HALF_X - 30.0 and absf(c.z) < main.MAP_HALF_Z - 30.0
				for gx in range(-6, 7):
					for gz in range(-6, 7):
						var x: float = c.x + float(gx) * 2.0
						var z: float = c.z + float(gz) * 2.0
						if not GameManager.is_passable(x, z) or GameManager.is_water(x, z):
							ok = false
							break
					if not ok:
						break
				if ok:
					return c
	return base

func _run() -> void:
	seed(2710)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	_Opt.squad_probes = false
	sm = main.selection_manager
	if "a" in _only: await _a_aura()
	if "b" in _only: await _b_hud()
	if "c" in _only: _c_river()
	if "d" in _only: _d_monk_xp()
	if "e" in _only: _e_legend()
	if "f" in _only: await _f_brick()
	if "g" in _only: await _g_cure()
	if "h" in _only: await _h_cohesion()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
# A. ЗНАЧКИ И КРУГИ АУРЫ
# ─────────────────────────────────────────────────────────────────────────────
## Доля кадров отрисовки, в которых значок НЕ сдвинулся, пока отряд шёл
func _icon_static_share(rm: Node, sid: int, to: Vector3) -> Array:
	for u in _members(sid):
		(u as Unit).command_move(to + ((u as Unit).global_position - _members(sid)[0].global_position) * 0.0, false)
	await pframes(20)
	var still := 0
	var total := 0
	var worst := 0.0
	var prev := Vector3.INF
	for _i in range(90):
		await get_tree().process_frame
		if int(rm.aura_view_icons) <= 0 or (rm._icons as Array).is_empty():
			continue
		var lab: Label3D = rm._icons[0]
		var p: Vector3 = lab.global_position
		if prev.x != INF:
			total += 1
			if p.distance_to(prev) < 0.001:
				still += 1
		prev = p
		# Отклонение от нарисованной точки якоря + смещение (только при ручке)
		var a = rm._icon_anchor[0] if (rm._icon_anchor as Array).size() > 0 else null
		if a != null and is_instance_valid(a):
			var want: Vector3 = (a as Unit).draw_position() + (rm._icon_off[0] as Vector3)
			worst = maxf(worst, Vector2(p.x - want.x, p.z - want.z).length())
	return [float(still) / float(maxi(total, 1)), worst, total]

func _a_aura() -> void:
	print("\n═════ A. ЗНАЧКИ И КРУГИ АУРЫ ═════")
	var spot: Vector3 = _spot(45.0, -45.0)
	_wipe(spot, 70.0)
	await pframes(5)
	var c: int = _squad("spearman", F, spot, 18)
	await pframes(5)
	var rm: Node = GameManager.relic_mgr()
	rm.grant_to_squad(c, true)
	sm.select_units(_members(c))
	await pframes(20)
	var on: Array = await _icon_static_share(rm, c, spot + Vector3(0, 0, 40))
	print("    ручка вкл: кадров без сдвига значка %.2f, отклонение от якоря %.3f м, кадров %d" % [on[0], on[1], on[2]])
	_Opt.aura_follow_draw = false
	var off: Array = await _icon_static_share(rm, c, spot + Vector3(0, 0, 0))
	_Opt.aura_follow_draw = true
	print("    ручка выкл: кадров без сдвига значка %.2f" % off[0])
	verdict("A1 на марше значок «+» движется каждый кадр (стоит ≤ 25 %% кадров; без ручки %.0f %%)" % (float(off[0]) * 100.0),
		int(on[2]) > 30 and float(on[0]) <= 0.25 and float(off[0]) >= 0.5,
		"с ручкой %.2f, без %.2f" % [on[0], off[0]])
	verdict("A2 значок держится нарисованной точки якоря (≤ 0.05 м)", float(on[1]) <= 0.05, "%.3f м" % on[1])
	var ring_ok: bool = rm._ring_mat != null and bool(rm._ring_mat.no_depth_test)
	verdict("A3 круг ауры без теста глубины — холм его не режет", ring_ok)
	# Башенный круг — тот же материал
	rm._tower_ring_node(0)
	verdict("A4 круг дальности башни тоже без теста глубины",
		rm._tring_mat != null and bool(rm._tring_mat.no_depth_test) and bool(rm._tring_mat_empty.no_depth_test))
	sm._clear_selection()
	_kill([c])
	await pframes(30)

# ─────────────────────────────────────────────────────────────────────────────
# B. ПОЛОСА РОДОВ
# ─────────────────────────────────────────────────────────────────────────────
func _disp_h(tr: TextureRect) -> float:
	var t: Texture2D = tr.texture
	var r: Vector2 = tr.size
	var k: float = minf(r.x / float(t.get_width()), r.y / float(t.get_height()))
	return float(t.get_height()) * k

func _b_hud() -> void:
	print("\n═════ B. ПОЛОСА РОДОВ ═════")
	var spot: Vector3 = _spot(45.0, 30.0)
	_wipe(spot, 50.0)
	await pframes(5)
	# Нарочно в обратном порядке появления
	var sids: Array = []
	sids.append(_squad("monk", F, spot, 4, 4))
	sids.append(_squad("warrior", F, spot + Vector3(0, 0, 6), 6))
	sids.append(_squad("archer", F, spot + Vector3(0, 0, 12), 6))
	sids.append(_squad("spearman", F, spot + Vector3(0, 0, 18), 6))
	await pframes(5)
	var all: Array = []
	for s in sids:
		all.append_array(_members(int(s)))
	sm.select_units(all)
	await frames(6)
	var hud = main.hud
	var names: Array = []
	for slot in hud._overbar_row.get_children():
		names.append(String(slot.name).replace("GroupSlot_", ""))
	verdict("B1 строгий порядок родов: копейщик → лучник → рыцарь → монах (%s)" % str(names),
		names == ["spearman", "archer", "warrior", "monk"])
	var sp_slot: Control = hud._overbar_row.get_child(0)
	var btn: Button = sp_slot.get_child(0) as Button
	verdict("B2 ячейка рода выше прежних 34 px (%.0f×%.0f)" % [btn.size.x, btn.size.y],
		btn.size.y >= float(hud.FILTER_SLOT_H) - 0.5 and btn.size.y > 40.0)
	var fig: TextureRect = btn.get_node_or_null("GroupFigure") as TextureRect
	var num: Label = btn.get_node_or_null("GroupCount") as Label
	var side_ok := false
	var fd := ""
	if fig != null and num != null:
		var fr: Rect2 = fig.get_global_rect()
		var nr: Rect2 = num.get_global_rect()
		side_ok = nr.position.x >= fr.end.x - 0.5 and num.text == "1"
		fd = "фигурка до x=%.0f, число с x=%.0f, «%s»" % [fr.end.x, nr.position.x, num.text]
	verdict("B3 число отрядов — рядом с фигуркой, а не поверх неё", side_ok, fd)
	var monk_slot: Control = hud._overbar_row.get_child(3)
	var mfig: TextureRect = (monk_slot.get_child(0) as Button).get_node_or_null("GroupFigure") as TextureRect
	var ratio := 0.0
	if fig != null and mfig != null:
		ratio = _disp_h(fig) / maxf(_disp_h(mfig), 1.0)
	verdict("B4 копейщик с копьём в рост монаха (высота на экране ×%.2f, 0.85-1.35)" % ratio,
		ratio >= 0.85 and ratio <= 1.35)
	var fig_px: float = _disp_h(fig) if fig != null else 0.0
	verdict("B5 фигурки крупнее прежних (копейщик %.0f px на экране, было ≤ 28)" % fig_px, fig_px > 32.0)
	sm._clear_selection()
	_kill(sids)
	await pframes(20)

# ─────────────────────────────────────────────────────────────────────────────
# C. РЕКА
# ─────────────────────────────────────────────────────────────────────────────
func _c_river() -> void:
	print("\n═════ C. РЕКА ═════")
	var lin: float = db_to_linear(AudioManager.RIVER_DB) / db_to_linear(AudioManager.RIVER_DB_BASE)
	verdict("C1 река громче на 15 %% (×%.3f по амплитуде)" % lin, absf(lin - 1.15) < 0.002)
	if not main.RIVER_ENABLED:
		verdict("C2 река на карте", false, "RIVER_ENABLED = false")
		return
	var rz: float = 60.0
	var rx: float = float(main.river_x(rz))
	var half: float = float(main.RIVER_HALF_W)
	var zone_old: float = half + AudioManager.RIVER_FADE_BASE
	var zone_new: float = half + AudioManager.RIVER_FADE_M
	var g_old_edge: float = AudioManager.river_gain_at(Vector3(rx + zone_old + 0.5, 0.0, rz))
	var g_left: float = AudioManager.river_gain_at(Vector3(rx - zone_old - 0.5, 0.0, rz))
	var g_out: float = AudioManager.river_gain_at(Vector3(rx + zone_new + 0.3, 0.0, rz))
	verdict("C2 зона слышимости ×1.2 в обе стороны (%.1f → %.1f м от оси)" % [zone_old, zone_new],
		is_equal_approx(zone_new, zone_old * 1.2) and g_old_edge > 0.0 and g_left > 0.0 and is_zero_approx(g_out),
		"за прежней кромкой справа %.3f, слева %.3f, за новой %.3f" % [g_old_edge, g_left, g_out])

# ─────────────────────────────────────────────────────────────────────────────
# D. ОПЫТ МОНАХОВ
# ─────────────────────────────────────────────────────────────────────────────
func _d_monk_xp() -> void:
	print("\n═════ D. ОПЫТ МОНАХОВ +20 % ═════")
	var raw: Array = (_UCfg.VET_CONFIG["monk"] as Dictionary)["thresholds"]
	var ok := true
	var got: Array = []
	for k in range(1, raw.size() + 1):
		var t: int = _UCfg.veteran_threshold("monk", k)
		got.append(t)
		if t != int(round(float(raw[k - 1]) * 1.2)):
			ok = false
	verdict("D1 каждая ступень монаха дороже на 20 %% (%s из %s)" % [str(got), str(raw)], ok)
	var sp_raw: Array = (_UCfg.VET_CONFIG["spearman"] as Dictionary)["thresholds"]
	verdict("D2 у копейщика пороги прежние", _UCfg.veteran_threshold("spearman", 1) == int(sp_raw[0])
		and _UCfg.veteran_threshold("spearman", sp_raw.size()) == int(sp_raw[sp_raw.size() - 1]))
	verdict("D3 уровень монаха по счёту — по новым порогам",
		_UCfg.veteran_level_for_kills("monk", int(raw[0])) == 0
		and _UCfg.veteran_level_for_kills("monk", int(got[0])) == 1)

# ─────────────────────────────────────────────────────────────────────────────
# E. ЗНАМЯ ЛЕГЕНДЫ
# ─────────────────────────────────────────────────────────────────────────────
func _near(a: Color, b: Color, tol: float = 0.06) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol and a.a > 0.5

## [красных, синих, белых лычек, строк с тканью хвоста, длина хвоста, цветных флажков]
## Знамя легенды по шкале ТЗ 30.10.2026: золотой вымпел, престиж — 1-3
## красные лычки на нём; [красных, синих, бордовых, золотых]
func _tail_stats(f: int) -> Array:
	_BannerArt.clear_cache()
	var img: Image = (_BannerArt.legend_texture(f) as Texture2D).get_image()
	var red := 0
	var blue := 0
	var bord := 0
	var gold := 0
	var purple := 0
	# ШКАЛА ТЗ 31.10.2026: лычки легенды оранжевые (red — их счёт), поле
	# синее в фиолетовой рамке; золота нет
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if _near(c, _UCfg.CHEV_ORANGE):
				red += 1
			elif _near(c, _UCfg.BANNER_BLUE):
				blue += 1
			elif _near(c, _BannerArt.ELITE_CLOTH):
				bord += 1
			elif _near(c, _UCfg.LEGEND_GOLD):
				gold += 1
			elif _near(c, _UCfg.BANNER_PURPLE):
				purple += 1
	return [red, blue, bord, gold, purple]

func _e_legend() -> void:
	print("\n═════ E. ЗНАМЯ ЛЕГЕНДЫ ═════")
	var st: Array = []
	for f in range(0, _UCfg.LEGEND_EXTRA_MAX + 1):
		st.append(_tail_stats(f))
		print("    f=%d: красных %d, синих %d, бордовых %d, золота %d" % [f, st[f][0], st[f][1], st[f][2], st[f][3]])
	# ШКАЛА ТЗ 30.10.2026: легенда — золотой вымпел, престиж 1-3 красные лычки
	# РАЗВОРОТ ТЗ 31.10.2026: легенда — синее поле в фиолетовой рамке, одна
	# оранжевая лычка + ступень престижа
	verdict("E1 чистая легенда — синее поле в фиолетовой рамке, одна оранжевая лычка",
		int(st[0][0]) > 0 and int(st[0][1]) > 200 and int(st[0][4]) > 30)
	verdict("E2 первая ступень престижа — оранжевых лычек больше", int(st[1][0]) > int(st[0][0]))
	verdict("E3 1-3 — оранжевых лычек больше с каждой ступенью",
		int(st[2][0]) > int(st[1][0]) and int(st[3][0]) > int(st[2][0]))
	verdict("E4 потолок — три лычки (LEGEND_EXTRA_MAX %d), сверх — та же картинка" % _UCfg.LEGEND_EXTRA_MAX,
		_UCfg.LEGEND_EXTRA_MAX == 3 and _BannerArt.legend_texture(5) == _BannerArt.legend_texture(3))
	var gold_any := 0
	var bord_any := 0
	for r in st:
		gold_any += int(r[3])
		bord_any += int(r[2])
	verdict("E5 золота (жёлтого) нет ни на одной ступени", gold_any == 0, "золотых %d" % gold_any)
	verdict("E6 бордового флажка на легенде нет ни на одной ступени", bord_any == 0, "бордовых %d" % bord_any)
	verdict("E7 штандарт игрока у легенды — бордовый, на пятаке ранг легенды",
		_SB_E.spec(_UCfg.LEGEND_TIER, true, false, 3, 2)[0] == _BannerArt.elite_texture(3, _UCfg.LEGEND_TIER))
	# Прибавки — только за первые LEGEND_EXTRA_BONUS_MAX лычек
	var spot: Vector3 = _spot(-45.0, 30.0)
	var sid: int = _squad("spearman", F, spot, 4)
	var sq: Dictionary = GameManager.squads[sid]
	sq["level"] = _UCfg.max_veteran_level("spearman")
	var step: Dictionary = _UCfg.vet_auto_step("spearman", _UCfg.LEGEND_TIER)
	var key: String = ""
	for k in step:
		if float(step[k]) != 0.0:
			key = String(k)
			break
	var short: String = _UCfg.modifier_stat_name(key)
	var b0: float = float((sq["bonuses"] as Dictionary).get(short, 0.0))
	sq["kills"] = _UCfg.legend_extra_threshold("spearman", _UCfg.LEGEND_EXTRA_MAX)
	GameManager._check_legend_extra(sid)
	var b1: float = float((sq["bonuses"] as Dictionary).get(short, 0.0))
	var want: float = float(step[key]) * float(_UCfg.LEGEND_EXTRA_BONUS_MAX)
	verdict("E8 все ступени престижа, прибавки — только за первые %d (%s +%.2f, ждём +%.2f)" % [
			_UCfg.LEGEND_EXTRA_BONUS_MAX, short, b1 - b0, want],
		int(sq.get("legend_extra", 0)) == _UCfg.LEGEND_EXTRA_MAX and absf((b1 - b0) - want) < 0.001
		and GameManager.squad_legend_marks(sid) == _UCfg.LEGEND_EXTRA_MAX)
	_kill([sid])

# ─────────────────────────────────────────────────────────────────────────────
# F. ЦЕЛЬНЫЙ КИРПИЧИК
# ─────────────────────────────────────────────────────────────────────────────
## Смещение центра последней (неполной) шеренги от центра первой поперёк курса
func _tail_offset(sid: int, course: Vector3) -> float:
	var side := Vector3(-course.z, 0.0, course.x)
	var by_row: Dictionary = {}
	for u in _members(sid):
		var uu := u as Unit
		# НАЗНАЧЕННОЕ место, а не где стоит: идущий из хвоста вправе встать,
		# упёршись в соседа (stall_arrive), — строй мерится по разметке приказа
		var p: Vector3 = uu.move_target if uu.state == Unit.State.MOVING else uu.post_pos
		# Шеренга — по координате вдоль курса (шаг шеренг 0.9 м от площадки)
		var r: int = int(round(-(p - _brick_spot).dot(course) / 0.9))
		if not by_row.has(r):
			by_row[r] = []
		(by_row[r] as Array).append(p.dot(side))
	var rows: Array = by_row.keys()
	rows.sort()
	if _diag:
		for r0 in rows:
			print("      DBG ряд %d: %s" % [r0, str(by_row[r0])])
	if rows.size() < 2:
		return INF
	var first: Array = by_row[rows[0]]
	var last: Array = by_row[rows[rows.size() - 1]]
	var m0 := 0.0
	for v in first: m0 += float(v)
	m0 /= float(first.size())
	var m1 := 0.0
	for v2 in last: m1 += float(v2)
	m1 /= float(last.size())
	return absf(m1 - m0)

var _brick_spot := Vector3.ZERO

func _brick_once(spot: Vector3) -> float:
	_brick_spot = spot
	var course := Vector3.FORWARD
	var sid: int = _squad("spearman", F, spot, 30)
	await pframes(3)
	var slots: Array = []
	var side := Vector3(-course.z, 0.0, course.x)
	for i in range(30):
		slots.append(spot + side * ((float(i % 6) - 2.5) * 0.65) - course * (float(i / 6) * 0.9))
	GameManager.squad_set_formation(int(sid), slots, course, false)
	var men: Array = _members(sid)
	for i in range(men.size()):
		(men[i] as Unit).global_position = slots[i]
		(men[i] as Unit).sync_row()
		(men[i] as Unit).hold_post(slots[i], course)
	await pframes(3)
	for i2 in range(7):
		(men[i2] as Unit).take_damage(1.0e12)
	await pframes(2)
	(GameManager.squads[sid] as Dictionary)["reshuffled"] = 0
	(GameManager.squads[sid] as Dictionary)["at_order"] = 30
	# Смыкание ПО ПОТЕРЯМ (7 из 30): строй стоит на постах, и путь force
	# счёл бы его целым
	var ok_cr: bool = GameManager.squad_close_ranks(sid, false)
	if _diag:
		var sts: Array = []
		for m in _members(sid):
			sts.append([int((m as Unit).state), snappedf((m as Unit).move_target.x, 0.01), snappedf((m as Unit).move_target.z, 0.01)])
		print("      DBG close_ranks=%s spot=%s %s" % [ok_cr, str(spot), str(sts)])
	await pframes(1)
	var off: float = _tail_offset(sid, course)
	_kill([sid])
	await pframes(10)
	return off

func _f_brick() -> void:
	print("\n═════ F. ЦЕЛЬНЫЙ КИРПИЧИК ═════")
	# Чистая функция: 23 из 30 по 6 в шеренге — хвост из 5 по центру
	var course := Vector3.FORWARD
	var side := Vector3(-course.z, 0.0, course.x)
	var slots: Array = []
	for i in range(30):
		slots.append(side * ((float(i % 6) - 2.5) * 0.65) - course * (float(i / 6) * 0.9))
	var out: Array = _SqF.centred_tail(slots, 23, course)
	var m_last := 0.0
	for i2 in range(18, 23):
		m_last += (out[i2] as Vector3).dot(side)
	m_last /= 5.0
	verdict("F1 centred_tail: 23 из 30 — хвост из 5 по центру строя (смещение %.3f м), полные шеренги не тронуты" % m_last,
		out.size() == 23 and absf(m_last) < 0.01 and (out[0] as Vector3).is_equal_approx(slots[0] as Vector3)
		and (out[17] as Vector3).is_equal_approx(slots[17] as Vector3))
	var spot: Vector3 = _spot(80.0, 45.0)
	_wipe(spot, 40.0)
	await pframes(5)
	spot = _free_spot(spot)
	var on: float = await _brick_once(spot)
	_Opt.formation_centred_tail = false
	var off: float = await _brick_once(spot + Vector3(0, 0, 0))
	_Opt.formation_centred_tail = true
	verdict("F2 смыкание после потерь: хвост по центру (%.2f м; без ручки %.2f м — огрызок сбоку)" % [on, off],
		on < 0.12 and off > 0.2)
	# Разметка по умолчанию: 23 бойца — последняя шеренга по центру
	var sid: int = _squad("spearman", F, spot, 23)
	await pframes(3)
	var def: Array = GameManager._default_block_slots(sid, _members(sid))
	var cr: Vector3 = (GameManager.squads[sid] as Dictionary).get("course", Vector3.FORWARD)
	var sd := Vector3(-cr.z, 0.0, cr.x)
	var cols: int = int(ceil(sqrt(23.0)))
	var c0 := 0.0
	for i3 in range(cols):
		c0 += (def[i3] as Vector3).dot(sd)
	c0 /= float(cols)
	var tail_from: int = (23 / cols) * cols
	var c1 := 0.0
	for i4 in range(tail_from, 23):
		c1 += (def[i4] as Vector3).dot(sd)
	c1 /= float(23 - tail_from)
	verdict("F3 разметка по умолчанию — неполная шеренга по центру (%.3f м)" % absf(c1 - c0), absf(c1 - c0) < 0.01)
	_kill([sid])
	await pframes(10)

# ─────────────────────────────────────────────────────────────────────────────
# G. «БЕГ НА МЕСТЕ»
# ─────────────────────────────────────────────────────────────────────────────
func _g_cure() -> void:
	print("\n═════ G. ЛЕЧЕНИЕ «БЕГА НА МЕСТЕ» ═════")
	var spot: Vector3 = _spot(45.0, 60.0)
	_wipe(spot, 60.0)
	await pframes(5)
	var sid: int = _squad("spearman", R, spot, 1)
	var u: Unit = _members(sid)[0]
	var goal: Vector3 = spot + Vector3(0, 0, 30)
	u.command_move(goal)
	await pframes(2)
	var r1: int = u.cure_run_in_place()
	var g1: Vector3 = u.march_goal()
	verdict("G1 далеко от цели — новый путь к той же цели (ответ %d, состояние %d)" % [r1, int(u.state)],
		r1 == 2 and u.state == Unit.State.MOVING and Vector2(g1.x - goal.x, g1.z - goal.z).length() < 1.0)
	var here: Vector3 = u.global_position
	var r2: int = u.cure_run_in_place()
	var g2: Vector3 = u.march_goal()
	verdict("G2 повтор в окне 20 с без приказа игрока — встал на месте (ответ %d, до цели хода %.2f м)" % [
			r2, Vector2(g2.x - here.x, g2.z - here.z).length()],
		r2 == 1 and (u.state != Unit.State.MOVING or Vector2(g2.x - here.x, g2.z - here.z).length() < 0.5))
	# Приказ игрока вдали: повтор — снова путь, приказ не снят
	var su: int = _squad("spearman", F, spot + Vector3(6, 0, 0), 1)
	var pu: Unit = _members(su)[0]
	pu.command_move(goal + Vector3(6, 0, 0), false, Vector3.ZERO, false, true)
	await pframes(2)
	pu.cure_run_in_place()
	var r3: int = pu.cure_run_in_place()
	verdict("G3 приказ игрока молча не снимается: повтор — снова путь (ответ %d, приказ %s)" % [r3, pu.player_order_active()],
		r3 == 2 and pu.player_order_active() and pu.state == Unit.State.MOVING)
	_kill([sid, su])
	await pframes(10)
	# Сквозной путь: ядро видит ленту ходьбы без продвижения → зонд → лечение
	var sid2: int = _squad("spearman", R, spot, 1)
	var w: Unit = _members(sid2)[0]
	var hold: Vector3 = w.global_position
	w.command_move(spot + Vector3(0, 0, 40))
	var c0: int = GameManager.probes.rip_cures
	var cured := false
	var waited := 0
	for _i in range(60 * 8):
		await get_tree().physics_frame
		waited += 1
		# Дрожит на месте, как зажатый в толпе: шаг 0.12 м туда-обратно —
		# лента ходьбы есть, продвижения за окно зонда нет
		# Собственный детектор застревания бойца слеп к такому дрожанию в
		# партии (34922 бойцов в сводках зонда за одну партию 27.10) — здесь
		# его гасим, чтобы мерить именно лечение
		if w.state == Unit.State.MOVING:
			w.global_position = hold + (Vector3(0.12, 0, 0) if waited % 2 == 0 else Vector3.ZERO)
			w.sync_row()
			w._reset_stuck()
		if GameManager.probes.rip_cures > c0:
			cured = true
			break
		if _diag and waited % 30 == 0:
			var row: int = w._soa
			print("      DBG t=%d st=%d rip=%d bound=%s cur=%d" % [waited, int(w.state), GameManager.probes._rip.size(),
				str(GameManager.army._c.RowLookBound(row)),
				int(GameManager.army._c.RowLookCur(row))])
	verdict("G4 ядро → зонд → лечение: застрявший с лентой бега вылечен за %.1f с (порог %.1f с)" % [
			float(waited) / 60.0, float(GameManager.probes.RIP_CURE_MS) / 1000.0],
		cured and float(waited) / 60.0 <= 6.0)
	_kill([sid2])
	await pframes(5)
	var sid3: int = _squad("spearman", R, spot, 1)
	var w3: Unit = _members(sid3)[0]
	var hold3: Vector3 = w3.global_position
	w3.command_move(spot + Vector3(0, 0, 40))
	_Opt.run_in_place_cure = false
	var c1: int = GameManager.probes.rip_cures
	for _i2 in range(60 * 5):
		await get_tree().physics_frame
		if w3.state == Unit.State.MOVING:
			w3.global_position = hold3 + (Vector3(0.12, 0, 0) if _i2 % 2 == 0 else Vector3.ZERO)
			w3.sync_row()
			w3._reset_stuck()
	_Opt.run_in_place_cure = true
	verdict("G5 без ручки лечения нет (вердикт различает)", GameManager.probes.rip_cures == c1)
	_kill([sid3])
	await pframes(10)

# ─────────────────────────────────────────────────────────────────────────────
# H. СУРОВАЯ СПЛОЧЁННОСТЬ
# ─────────────────────────────────────────────────────────────────────────────
## Один боец отряда дерётся в k зонах от медианы: отозван ли он
func _coh_case(spot: Vector3, k: float, forced: bool) -> bool:
	var sid: int = _squad("spearman", R, spot, 12)
	await pframes(3)
	var lim: float = GameManager._cohesion_limit(sid)
	var men: Array = _members(sid)
	var far: Unit = men[11]
	var at: Vector3 = spot + Vector3(lim * k, 0.0, 0.0)
	far.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	far.sync_row()
	var foe: Unit = _unit("spearman", F, at + Vector3(1.0, 0, 0))
	foe.set_tick(false)
	await pframes(2)
	far.command_attack(foe, forced)
	far.state = Unit.State.ATTACKING
	var xs: Array = []
	var zs: Array = []
	for m in men:
		xs.append((m as Unit).global_position.x)
		zs.append((m as Unit).global_position.z)
	xs.sort()
	zs.sort()
	GameManager._cohesion_last.erase(sid)
	GameManager._cohesion_guard(sid, men, float(xs[xs.size() / 2]), float(zs[zs.size() / 2]), Unit.game_ms())
	var recalled: bool = far.attack_target == null or far.state == Unit.State.MOVING
	_kill([sid])
	foe.take_damage(1.0e12)
	await pframes(5)
	return recalled

func _h_cohesion() -> void:
	print("\n═════ H. СУРОВАЯ СПЛОЧЁННОСТЬ ═════")
	var spot: Vector3 = _spot(-45.0, 60.0)
	_wipe(spot, 80.0)
	await pframes(5)
	var own_on: bool = await _coh_case(spot, 1.6, false)
	_Opt.cohesion_strict = false
	var own_off: bool = await _coh_case(spot, 1.6, false)
	_Opt.cohesion_strict = true
	verdict("H1 дерущийся по своей инициативе в 1.6 зоны — отозван (без ручки — нет)", own_on and not own_off,
		"с ручкой %s, без %s" % [own_on, own_off])
	var near_on: bool = await _coh_case(spot, 1.1, false)
	verdict("H2 дерущийся в пределах 1.25 зоны — остаётся драться", not near_on)
	var fo_mid: bool = await _coh_case(spot, 1.6, true)
	var fo_far: bool = await _coh_case(spot, 2.4, true)
	_Opt.cohesion_strict = false
	var fo_far_off: bool = await _coh_case(spot, 2.4, true)
	_Opt.cohesion_strict = true
	verdict("H3 атака по приказу ИИ/[A]: в 1.6 зоны держится, в 2.4 — отозвана (без ручки — держится)",
		not fo_mid and fo_far and not fo_far_off, "1.6: %s, 2.4: %s, 2.4 без ручки: %s" % [fo_mid, fo_far, fo_far_off])
