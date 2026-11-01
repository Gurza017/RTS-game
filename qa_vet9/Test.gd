extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЗНАМЁНА, ШКАЛА ЛЫЧЕК И ЭКОНОМИКА ОПЫТА (ТЗ 30.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ШКАЛА    — 9 ступеней на синем вымпеле: лычки белые 1-3 → красные 1-3 →
##                оранжевые 1-3; 10-я — легенда, синее поле в фиолетовой
##                рамке (РАЗВОРОТ ТЗ 31.10.2026, жёлтого нет)
##   B КРИВАЯ   — первый интервал рода прежний, каждый следующий растёт на
##                VET_XP_GROWTH (последняя золотая ступень — +30 %), без перекача
##   C БОНУСЫ   — 9 ступеней по цвету лычек, мораль и напор растут сильнее
##                прочего; живой отряд копейщиков на 9-й ступени несёт сумму
##   D ПАНИКА   — шанс срыва падает с рангом (ручка vet_panic_resist)
##   E РИСУНОК  — пиксели лычек нужного цвета на синем, легенда золотая с
##                1-3 красными лычками, хвоста престижа нет
##   F ШТАНДАРТ — бордовый с римской цифрой, пятак ранга синий с лычками цвета
##                ступени, у легенды — золотые; в мире пятак показывает РАНГ
##   G ЛЕГЕНДА  — при половине штата в бою уходит в крепость (ручка
##                legend_retreat), последний боец легенды уцелевает без кузницы
## Числа — из конфигов (правило 10), ожидание — физкадрами.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _BA := preload("res://scripts/BannerArt.gd")
const _SB := preload("res://scripts/SquadBanner.gd")
const _CSiteT := preload("res://scripts/ConstructionSite.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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
	print("\n═════ ИТОГ qa_vet9: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 10) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x + float(i % cols) * 0.7, 0.0, at.z + float(i / cols) * 0.7))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(sid: int) -> int:
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return 0
	var n := 0
	for m in (raw as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n

## Ранг отряду — честным путём: убийства через credit_kills
func _raise_to(sid: int, lvl: int) -> void:
	var t: String = GameManager.squad_type(sid)
	var need: int = _UCfg.veteran_threshold(t, lvl) - int(GameManager.squads[sid]["kills"])
	if need > 0:
		GameManager.credit_kills(sid, need)

func _near(a: Color, b: Color, tol: float = 0.06) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol and a.a > 0.5

## Сколько пикселей цвета col на картинке (в прямоугольнике r, если задан)
func _count(tex: Texture2D, col: Color, r: Rect2i = Rect2i()) -> int:
	var img: Image = tex.get_image()
	var rr: Rect2i = r if r.size != Vector2i.ZERO else Rect2i(0, 0, img.get_width(), img.get_height())
	var n := 0
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			if _near(img.get_pixel(x, y), col):
				n += 1
	return n

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(14.0, 0.0, 0.0), Vector3(-14.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 14.0), Vector3(0.0, 0.0, -14.0)]:
				var q: Vector3 = p + (d as Vector3)
				h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
				if GameManager.is_water(q.x, q.z) or not GameManager.is_passable(q.x, q.z):
					h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	_a_scale()
	_b_curve()
	_c_steps_table()
	_e_art()
	_f_standard_art()
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
	for n in get_tree().get_nodes_in_group("all_units"):
		var wu := n as Unit
		if wu != null and wu.faction != F:
			wu.set_tick(false)
	var base: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 30.0))
	main._clear_area_of_resources(base, 70.0)
	await _c_live(base)
	_d_panic(base + Vector3(0.0, 0.0, 14.0))
	await _f_live(base + Vector3(-20.0, 0.0, 14.0))
	await _g_legend(base)
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ШКАЛА
# ═════════════════════════════════════════════════════════════════════════════
func _a_scale() -> void:
	print("\n═════ A. ШКАЛА ЛЫЧЕК ═════")
	var tiers: Array = _UCfg.VET_BANNER_TIERS
	verdict("A1 ступеней 10, легенда — LEGEND_TIER (%d), у копейщика max_veteran_level %d" % [
		_UCfg.LEGEND_TIER, _UCfg.max_veteran_level("spearman")],
		tiers.size() == 10 and _UCfg.LEGEND_TIER == 10 and _UCfg.max_veteran_level("spearman") == 10)
	var cols: Array = [_UCfg.CHEV_WHITE, _UCfg.CHEV_RED, _UCfg.CHEV_ORANGE]
	var ok := true
	var bad := ""
	for i in range(9):
		var t: Dictionary = tiers[i]
		var want_c: Color = cols[i / 3]
		if int(t.get("chevrons", 0)) != i % 3 + 1 or (t.get("chevron_col") as Color) != want_c \
				or (t.get("cloth") as Color) != _UCfg.BANNER_BLUE or bool(t.get("legend", false)):
			ok = false
			bad += " %d" % (i + 1)
	verdict("A2 ступени 1-9: синий вымпел, лычки 1-2-3 белые → красные → оранжевые", ok, "сбой:" + bad)
	var lg: Dictionary = tiers[9]
	# РАЗВОРОТ ТЗ 31.10.2026: легенда — синее поле в фиолетовой рамке, одна
	# оранжевая лычка (+ престиж); жёлтого полотнища нет
	verdict("A3 10-я — легенда: синее поле в фиолетовой рамке, одна оранжевая лычка", bool(lg.get("legend", false))
		and (lg.get("cloth") as Color) == _UCfg.BANNER_BLUE and (lg.get("edge") as Color) == _UCfg.BANNER_PURPLE
		and int(lg.get("chevrons", -1)) == 1 and (lg.get("chevron_col") as Color) == _UCfg.CHEV_ORANGE)
	verdict("A4 престиж легенды — до 3 ступеней (LEGEND_EXTRA_MAX %d)" % _UCfg.LEGEND_EXTRA_MAX,
		_UCfg.LEGEND_EXTRA_MAX == 3)

# ═════════════════════════════════════════════════════════════════════════════
# B. КРИВАЯ ОПЫТА
# ═════════════════════════════════════════════════════════════════════════════
func _b_curve() -> void:
	print("\n═════ B. КРИВАЯ ОПЫТА ═════")
	var g: Array = _UCfg.VET_XP_GROWTH
	verdict("B1 рост интервалов не убывает, первый 0, последний золотой +30 %%: %s" % str(g),
		float(g[0]) == 0.0 and absf(float(g[8]) - 0.30) < 1e-6 and g.size() == 10
		and _monotone(g))
	for t in ["spearman", "warrior", "archer", "monk"]:
		var th: Array = _UCfg._vet_thresholds(t)
		var iv: Array = []
		var prev := 0
		for x in th:
			iv.append(int(x) - prev)
			prev = int(x)
		var ok: bool = th.size() == 10 and _monotone(iv)
		# Рост каждого интервала ≈ 1 + VET_XP_GROWTH[k] (округление порога до 5)
		var worst := 0.0
		for k in range(1, iv.size()):
			var want: float = float(iv[k - 1]) * (1.0 + float(g[k]))
			worst = maxf(worst, absf(float(iv[k]) - want) / maxf(want, 1.0))
		print("  %s: пороги %s, интервалы %s, худшее отклонение %.1f %%" % [t, str(th), str(iv), worst * 100.0])
		verdict("B2 %s: 10 порогов, интервалы растут по кривой (откл. ≤ 12 %%)" % t, ok and worst <= 0.12)
	# Без перекача: легенда копейщика — не дальше 25× первого интервала
	var th_s: Array = _UCfg._vet_thresholds("spearman")
	verdict("B3 легенда копейщика %d убийств ≤ 25 × первого интервала %d" % [int(th_s[9]), int(th_s[0])],
		int(th_s[9]) <= 25 * int(th_s[0]))

func _monotone(a: Array) -> bool:
	for i in range(1, a.size()):
		if float(a[i]) < float(a[i - 1]):
			return false
	return true

# ═════════════════════════════════════════════════════════════════════════════
# C. БОНУСЫ
# ═════════════════════════════════════════════════════════════════════════════
func _sum_steps(t: String, key: String) -> float:
	var s := 0.0
	for l in range(1, 10):
		s += float(_UCfg.vet_auto_step(t, l).get(key, 0.0))
	return s

func _c_steps_table() -> void:
	print("\n═════ C. БОНУСЫ СТУПЕНЕЙ ═════")
	for t in ["warrior", "spearman", "archer", "monk", "goblin_spearman"]:
		var w: Dictionary = _UCfg.vet_auto_step(t, 1)
		var r: Dictionary = _UCfg.vet_auto_step(t, 4)
		var gd: Dictionary = _UCfg.vet_auto_step(t, 7)
		var ok: bool = not w.has("bonus_speed") and not r.has("bonus_speed") and not gd.has("bonus_speed")
		ok = ok and float(w.get("bonus_morale", 0.0)) > 0.0
		ok = ok and float(w.get("bonus_morale", 0.0)) <= float(r.get("bonus_morale", 0.0)) \
			and float(r.get("bonus_morale", 0.0)) <= float(gd.get("bonus_morale", 0.0))
		ok = ok and _UCfg.vet_auto_step(t, 3) == w and _UCfg.vet_auto_step(t, 6) == r \
			and _UCfg.vet_auto_step(t, 9) == gd
		print("  %s: белые %s | красные %s | золотые %s" % [t, str(w), str(r), str(gd)])
		verdict("C1 %s: три ступени по цвету, мораль растёт белые ≤ красные ≤ золотые, без скорости" % t, ok)
	# Пехота: напор растёт и составляет заметную долю (упор ТЗ на мораль и напор)
	for t2 in ["warrior", "spearman"]:
		var p1: float = float(_UCfg.vet_auto_step(t2, 1).get("bonus_push", 0.0))
		var p9: float = float(_UCfg.vet_auto_step(t2, 9).get("bonus_push", 0.0))
		verdict("C2 %s: напор растёт (%.2f → %.2f), сумма за 9 ступеней %.2f, мораль %.0f" % [
			t2, p1, p9, _sum_steps(t2, "bonus_push"), _sum_steps(t2, "bonus_morale")],
			p1 > 0.0 and p9 > p1 and _sum_steps(t2, "bonus_morale") >= 30.0)

func _c_live(base: Vector3) -> void:
	print("\n═════ C. ЖИВОЙ ОТРЯД НА 9-Й СТУПЕНИ ═════")
	var fresh: Unit = _spawn("spearman", F, base + Vector3(0.0, 0.0, -10.0))
	var m0: float = fresh.morale
	var p0: float = fresh.push_force
	var h0: float = fresh.max_health
	var sq: Array = _squad("spearman", F, base, 20)
	var sid: int = int(sq[0])
	_raise_to(sid, 9)
	await pframes(2)
	var u: Unit = sq[1][0]
	var dm: float = u.morale - m0
	var dp: float = u.push_force - p0
	var want_m: float = _sum_steps("spearman", "bonus_morale")
	var want_p: float = _sum_steps("spearman", "bonus_push")
	verdict("C3 ранг 9 (уровень %d): мораль +%.1f (ждём %.1f), напор +%.2f (ждём %.2f), запас %.0f → %.0f" % [
		int(GameManager.squads[sid]["level"]), dm, want_m, dp, want_p, h0, u.max_health],
		int(GameManager.squads[sid]["level"]) == 9 and absf(dm - want_m) < 0.01
		and absf(dp - want_p) < 0.01 and u.max_health > h0)
	var chosen: Array = GameManager.squads[sid]["chosen"]
	verdict("C4 записи ступеней auto_1..auto_9 (%d)" % chosen.size(),
		chosen.has("auto_1") and chosen.has("auto_9"))
	# Легенда — перк, без десятой числовой прибавки
	_raise_to(sid, 10)
	await pframes(2)
	verdict("C5 легенда: мораль не прибавила (%.1f → %.1f), перк легенды выдан" % [m0 + dm, u.morale],
		absf(u.morale - (m0 + dm)) < 0.01 and int(GameManager.squads[sid]["level"]) == 10
		and (_UCfg.vet_auto_legend("spearman") == "" or chosen.has(_UCfg.vet_auto_legend("spearman"))))
	fresh.take_damage(1e12)
	for m in sq[1]:
		(m as Unit).take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. ПАНИКА
# ═════════════════════════════════════════════════════════════════════════════
func _d_panic(at: Vector3) -> void:
	print("\n═════ D. СТОЙКОСТЬ К ПАНИКЕ ═════")
	var r: Array = _UCfg.VET_PANIC_RESIST
	verdict("D1 стойкость растёт с рангом: %s" % str(r), r.size() == 11 and float(r[0]) == 0.0
		and _monotone(r) and float(r[10]) > float(r[9]))
	var chances: Array = []
	var sids: Array = []
	for lvl in [0, 3, 6, 9]:
		var sq: Array = _squad("spearman", F, at + Vector3(float(sids.size()) * 9.0, 0.0, 0.0), 6, 3)
		var sid: int = int(sq[0])
		if lvl > 0:
			_raise_to(sid, lvl)
		sids.append(sid)
		chances.append(GameManager.panic_chance_of(sid))
	print("  шанс срыва по рангам 0/3/6/9: %s" % str(chances))
	verdict("D2 шанс срыва падает с рангом, ранг 0 — PANIC_CHANCE",
		absf(float(chances[0]) - _UCfg.PANIC_CHANCE) < 1e-4 and _monotone([-float(chances[0]),
			-float(chances[1]), -float(chances[2]), -float(chances[3])]) and float(chances[3]) < float(chances[0]))
	_Opt.vet_panic_resist = false
	var off: float = GameManager.panic_chance_of(int(sids[3]))
	_Opt.vet_panic_resist = true
	verdict("D3 ручка vet_panic_resist=false: у ранга 9 шанс прежний (%.3f)" % off,
		absf(off - _UCfg.PANIC_CHANCE) < 1e-4)
	for sid2 in sids:
		for m in (GameManager.squads[sid2]["members"] as Array).duplicate():
			if m != null and is_instance_valid(m):
				(m as Unit).take_damage(1e12)

# ═════════════════════════════════════════════════════════════════════════════
# E. РИСУНОК ВЫМПЕЛОВ
# ═════════════════════════════════════════════════════════════════════════════
func _e_art() -> void:
	print("\n═════ E. РИСУНОК ═════")
	var cols: Array = [_UCfg.CHEV_WHITE, _UCfg.CHEV_RED, _UCfg.CHEV_ORANGE]
	var ok := true
	var info := ""
	var prev := 0
	for lvl in range(1, 10):
		var tex: Texture2D = _BA.texture_for(lvl)
		var c: int = _count(tex, cols[(lvl - 1) / 3])
		var blue: int = _count(tex, _UCfg.BANNER_BLUE)
		# Чужих цветов лычек нет (белый — и контур древка, его не считаем)
		var other := 0
		for j in range(1, 3):
			if j != (lvl - 1) / 3:
				other += _count(tex, cols[j])
		info += " %d:%d/%d/%d" % [lvl, c, blue, other]
		if c <= 0 or blue <= 0 or other > 0:
			ok = false
		# Больше лычек — больше пикселей лычек внутри цвета
		if (lvl - 1) % 3 > 0 and c <= prev:
			ok = false
		prev = c
	print("  ступень:лычки/синий/чужие —%s" % info)
	verdict("E1 ступени 1-9: синее полотнище и лычки своего цвета, число лычек растёт", ok)
	var lg0: Texture2D = _BA.legend_texture(0)
	var purple0: int = _count(lg0, _UCfg.BANNER_PURPLE)
	var red: Array = []
	for f in range(0, 4):
		red.append(_count(_BA.legend_texture(f), _UCfg.CHEV_ORANGE))
	print("  легенда: рамка %d, синего %d, оранжевых по престижу 0..3: %s" % [
		purple0, _count(lg0, _UCfg.BANNER_BLUE), str(red)])
	verdict("E2 легенда — синее поле в фиолетовой рамке, оранжевых лычек 1 + престиж",
		purple0 > 0 and _count(lg0, _UCfg.BANNER_BLUE) > 0 and _count(lg0, _UCfg.LEGEND_GOLD) == 0
		and int(red[0]) > 0 and int(red[1]) > int(red[0]) and int(red[2]) > int(red[1]) and int(red[3]) > int(red[2]))
	verdict("E3 хвост престижа удалён (legend_tail_spec нет), престиж сверх 3 зажат",
		not _has_static(_BA, "legend_tail_spec") and not _has_static(_BA, "_draw_legend_tail")
		and _BA.legend_texture(6) == _BA.legend_texture(3))
	verdict("E4 крой флажка легенды — общий вымпела (crop_for)",
		_BA.crop_for(_UCfg.LEGEND_TIER) == _BA.flag_crop())

func _has_static(scr: Script, fname: String) -> bool:
	for m in scr.get_script_method_list():
		if String(m["name"]) == fname:
			return true
	return false

# ═════════════════════════════════════════════════════════════════════════════
# F. БОРДОВЫЙ ШТАНДАРТ
# ═════════════════════════════════════════════════════════════════════════════
func _f_standard_art() -> void:
	print("\n═════ F. ШТАНДАРТ ═════")
	var cols: Array = [_UCfg.CHEV_WHITE, _UCfg.CHEV_RED, _UCfg.CHEV_ORANGE]
	var ok := true
	var info := ""
	for lvl in [1, 3, 4, 6, 7, 9]:
		var tex: Texture2D = _BA.elite_texture(2, lvl)
		var plate: int = _count(tex, _BA.ELITE_PLATE)
		var ch: int = _count(tex, cols[(lvl - 1) / 3])
		var yel: int = _count(tex, Color(0.98, 0.84, 0.18))
		info += " %d:%d/%d/%d" % [lvl, plate, ch, yel]
		if plate <= 0 or ch <= 0 or _BA.elite_chevron_color(lvl) != cols[(lvl - 1) / 3]:
			ok = false
		# Прежнего жёлтого пятака нет; у золотых лычек жёлтый — это сами лычки
		if lvl < 7 and yel > 0:
			ok = false
	print("  ранг:пятак/лычки/жёлтый —%s" % info)
	verdict("F1 пятак ранга синий, лычки цвета ступени (белые/красные/оранжевые)", ok)
	var lt: Texture2D = _BA.elite_texture(2, _UCfg.LEGEND_TIER)
	verdict("F2 легенда на штандарте: оранжевые лычки и фиолетовая рамка пятака",
		_count(lt, _UCfg.CHEV_ORANGE) > 0 and _count(lt, _UCfg.BANNER_PURPLE) > 0
		and _BA.elite_chevron_color(_UCfg.LEGEND_TIER) == _UCfg.CHEV_ORANGE)
	var r1: int = _count(_BA.elite_texture(1, 0), _BA.VEX_SIGN)
	var r6: int = _count(_BA.elite_texture(6, 0), _BA.VEX_SIGN)
	verdict("F3 римская цифра уровня на бордо (I: %d, VI: %d пикселей), бордо есть" % [r1, r6],
		r1 > 0 and r6 > 0 and _BA.elite_texture(1, 0) != _BA.elite_texture(6, 0) and _count(_BA.elite_texture(1, 0), _BA.ELITE_CLOTH) > 0
		and _BA.roman(6) == "VI")

func _f_live(at: Vector3) -> void:
	var sq: Array = _squad("spearman", F, at, 10, 5)
	var sid: int = int(sq[0])
	_raise_to(sid, 5)
	GameManager.squads[sid]["elite"] = true
	GameManager.squads[sid]["elite_lvl"] = 2
	var s: Array = _SB.spec(5, true, false, 2)
	verdict("F4 в мире штандарт показывает ранг отряда (5 — две красные лычки), уровень II",
		not s.is_empty() and s[0] == _BA.elite_texture(2, 5))
	for m in sq[1]:
		(m as Unit).take_damage(1e12)
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# G. ОТХОД ЛЕГЕНДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _legend_case(at: Vector3, foe_at: Vector3) -> Array:
	var full: int = _UCfg.squad_size("spearman")
	var sq: Array = _squad("spearman", F, at, full)
	var sid: int = int(sq[0])
	_raise_to(sid, _UCfg.LEGEND_TIER)
	var foe: Array = _squad("warrior", E, foe_at, 10, 5)
	await pframes(2)
	var killer: Unit = foe[1][0]
	# Выбить чуть больше половины — потери в бою, с ударом по отряду
	var cut: int = int(ceil(float(full) * (1.0 - _UCfg.LEGEND_RETREAT_FRAC))) + 1
	for i in range(cut):
		(sq[1][i] as Unit).take_damage(1e12, killer)
	for m in sq[1]:
		if not (m as Unit).is_dead():
			(m as Unit).command_attack(killer)
	return [sid, sq[1], foe]

func _g_legend(base: Vector3) -> void:
	print("\n═════ G. ЛЕГЕНДА: ОТХОД И ВОССТАНОВЛЕНИЕ ═════")
	if not _has_castle():
		var cas: Building = _CSiteT.make_building("castle")
		cas.faction = F
		main.world_add(cas)
		var cp: Vector3 = base + Vector3(-40.0, 0.0, -30.0)
		cas.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
		await pframes(3)
	GameManager.panic_chance_override = 0.0
	var r0: int = GameManager.legend_retreats
	var c: Array = await _legend_case(base + Vector3(0.0, 0.0, 30.0), base + Vector3(0.0, 0.0, 26.0))
	var sid: int = int(c[0])
	var went := false
	for _f in range(240):
		await get_tree().physics_frame
		# Удар по отряду держит «в бою» и «били недавно»
		GameManager.squad_mark_hit(sid, c[2][1][0])
		if GameManager.squad_is_to_castle(sid) or GameManager.legend_retreats > r0:
			went = true
			break
	verdict("G1 легенда при %d/%d живых в бою ушла в крепость (отходов +%d)" % [
		_alive(sid), _UCfg.squad_size("spearman"), GameManager.legend_retreats - r0], went)
	# Ручка снята — легенда остаётся в бою
	_Opt.legend_retreat = false
	var r1: int = GameManager.legend_retreats
	var c2: Array = await _legend_case(base + Vector3(30.0, 0.0, 30.0), base + Vector3(30.0, 0.0, 26.0))
	var sid2: int = int(c2[0])
	var went2 := false
	for _f in range(240):
		await get_tree().physics_frame
		GameManager.squad_mark_hit(sid2, c2[2][1][0])
		if GameManager.squad_is_to_castle(sid2) or GameManager.legend_retreats > r1:
			went2 = true
			break
	_Opt.legend_retreat = true
	verdict("G2 ручка legend_retreat=false: легенда не уходит (прежнее поведение)", not went2)
	await _g3(base, c[2][1][0])
	GameManager.panic_chance_override = -1.0

## Последний боец легенды уцелевает без узла кузницы, обычного отряда — нет.
## Состояние снимается сразу: призрак уходит в крепость, гарнизон узел освобождает
func _g3(base: Vector3, att0: Variant) -> void:
	var lone: Array = _squad("spearman", F, base + Vector3(60.0, 0.0, 30.0), 2, 2)
	_raise_to(int(lone[0]), _UCfg.LEGEND_TIER)
	var plain: Array = _squad("spearman", F, base + Vector3(60.0, 0.0, 40.0), 2, 2)
	(lone[1][0] as Unit).take_damage(1e12)
	(plain[1][0] as Unit).take_damage(1e12)
	await pframes(2)
	var lu: Unit = lone[1][1]
	var pu: Unit = plain[1][1]
	var forge: bool = GameManager.is_researched(F, "spearman_" + _UCfg.LAST_STAND_CELL)
	var att: Node3D = att0 if att0 != null and is_instance_valid(att0) else null
	var l_alive := false
	var l_ghost := false
	if is_instance_valid(lu):
		lu.take_damage(1e12, att)
		l_alive = not lu.is_dead()
		l_ghost = lu.is_ghost()
	var p_dead := true
	if is_instance_valid(pu):
		pu.take_damage(1e12, att)
		p_dead = pu.is_dead()
	verdict("G3 последний боец легенды уцелел без кузницы (призрак=%s), обычный — пал (%s)" % [
		str(l_ghost), str(p_dead)], l_alive and l_ghost and (p_dead or forge))
	_Opt.legend_retreat = false
	var lone2: Array = _squad("spearman", F, base + Vector3(70.0, 0.0, 30.0), 2, 2)
	_raise_to(int(lone2[0]), _UCfg.LEGEND_TIER)
	(lone2[1][0] as Unit).take_damage(1e12)
	await pframes(2)
	var lu2: Unit = lone2[1][1]
	var dead2 := true
	if is_instance_valid(lu2):
		lu2.take_damage(1e12, att)
		dead2 = lu2.is_dead()
	_Opt.legend_retreat = true
	verdict("G4 ручка legend_retreat=false: последний боец легенды без кузницы гибнет", dead2 or forge)
	await pframes(2)

func _has_castle() -> bool:
	for b in get_tree().get_nodes_in_group(Constants.building_group(F)):
		if b is Castle and not (b as Building).is_dead():
			return true
	return false
