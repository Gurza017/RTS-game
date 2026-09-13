extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД СПРИНТА 20: комплексный пакет фиксов (модули 1-6)
## ═══════════════════════════════════════════════════════════════════════════
##   A ВИЗУАЛ МОНАХА — аура: только овал под ногами (без креста и заливки),
##     лента лечения идёт от земли, а не от пояса.
##   B ЗВУК УБИЙСТВ — хор смеха только за убийство ГОБЛИНОМ и только в малой
##     стычке; убийство троллем — его рык.
##   C ПЕНЬ И ТРОЛЛИ — таймер восстановления пня 600 с, стражей не больше 2,
##     HP −20 %, гнолл бросает на 15 % чаще, стадо держится на 5.
##   D КЛИК И МАССОВЫЙ ПРИКАЗ — точка земли по рельефу, руина кликается по
##     картинке, лишние отряды на крупной цели идут на ближайшего врага,
##     стрелок откликается на приказ мгновенно (окно залпа открыто).
##   E КОПЕЙЩИКИ — «Стена копий» только копейщикам: включена — три шеренги на
##     любом растяге, выключена — прямоугольник по линии; коробочка [2] не
##     запоминается между растягами; фаланга в обороне подаётся к врагу
##     ЦЕЛИКОМ, одиночки из строя не выбегают.
##   F РЕМОНТ — ПКМ рабочими по пепелищу ставит стройплощадку.
##   G ПЕРЕМИРИЕ И ИИ ОРДЫ — 600 с без рейдов, защита красного ИИ до
##     AI_PROTECT_SEC, рейд без добычи возвращается.
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_sprint20/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _AICfg  := preload("res://scripts/ai_start_army_limit.gd")
const _MonkS  := preload("res://scripts/Monk.gd")
const _CSite  := preload("res://scripts/ConstructionSite.gd")
const _House  := preload("res://scripts/House.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(560.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 560 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_sprint20: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = _g(at)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, fac: int, at: Vector3, n: int, cols: int = 5) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(uid, fac, at + Vector3(float(i % cols) * 0.7, 0.0, float(i / cols) * 0.7))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			c += (m as Unit).global_position
			n += 1
	return c / float(maxi(n, 1))

func _clear_trees(at: Vector3, r: float) -> void:
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn0 := n0 as ResourceNode
		if rn0 != null and is_instance_valid(rn0) and _xz(rn0.global_position, at) < r:
			rn0.queue_free()

func _free_all(arr: Array) -> void:
	for n in arr:
		if n != null and is_instance_valid(n):
			if n is Unit and not (n as Unit).is_dead():
				(n as Unit).take_damage(1.0e9)
			else:
				(n as Node).queue_free()

func _freeze(men: Array) -> void:
	for m in men:
		(m as Unit).set_tick(false)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	var P: int = Constants.FACTION_PLAYER
	var E: int = Constants.FACTION_ENEMY
	var GB: int = Constants.FACTION_GOBLIN

	# ═══ A. ВИЗУАЛ МОНАХА ═══════════════════════════════════════════════════
	print("\n═════ A. АУРА МОНАХА — ОВАЛ ПОД НОГАМИ, ЛЕНТА ОТ ЗЕМЛИ ═════")
	var tex: Texture2D = _MonkS._aura_texture()
	var img: Image = tex.get_image()
	var c: int = _MonkS.AURA_PX / 2
	var centre_a: float = img.get_pixel(c, c).a
	var cross_hits := 0
	for k in range(3, 9):
		if img.get_pixel(c + k, c).a > 0.5 or img.get_pixel(c, c + k).a > 0.5:
			cross_hits += 1
	verdict("A1 в ауре нет ни креста, ни заливки (центр и лучи прозрачны)",
		centre_a < 0.5 and cross_hits == 0, "центр α=%.2f, лучей %d" % [centre_a, cross_hits])
	var ring_px := 0
	var wide := 0.0
	var tall := 0.0
	var minx := 999; var maxx := -1; var miny := 999; var maxy := -1
	for y in range(_MonkS.AURA_PX):
		for x in range(_MonkS.AURA_PX):
			if img.get_pixel(x, y).a > 0.5:
				ring_px += 1
				minx = mini(minx, x); maxx = maxi(maxx, x); miny = mini(miny, y); maxy = maxi(maxy, y)
	wide = float(maxx - minx + 1)
	tall = float(maxy - miny + 1)
	verdict("A2 контур — ОВАЛ (ниже, чем шире: %.0f × %.0f px), тонкий" % [wide, tall],
		ring_px > 20 and tall < wide * 0.7 and ring_px < _MonkS.AURA_PX * _MonkS.AURA_PX / 6,
		"пикселей контура %d" % ring_px)
	var mp := Vector3(-60.0, 0.0, -400.0)
	_clear_trees(mp, 20.0)
	var monk: Unit = _spawn("monk", P, mp)
	var pat: Unit = _spawn("spearman", P, mp + Vector3(2.5, 0.0, 0.0))
	pat.set_tick(false)
	pat.current_health = pat.max_health * 0.4
	pat._soa_push_stats()
	var vfx_ok := false
	var vfx: Node3D = null
	for _w in range(240):
		await get_tree().physics_frame
		vfx = monk.heal_vfx_node()
		if vfx != null and vfx.visible and monk.heal_vfx_target() == pat:
			vfx_ok = true
			break
	var pp: Vector3 = pat.draw_position()
	var vy: float = (vfx.global_position.y - pp.y) if vfx != null else -1.0
	verdict("A3 лента лечения стоит НИЖНЕЙ кромкой у ног (центр на %.2f м = половина квада %.2f)" % [vy, _MonkS.HEAL_VFX_SIZE_M],
		vfx_ok and absf(vy - _MonkS.HEAL_VFX_SIZE_M * 0.5) < 0.05)
	var aura: Node3D = monk.get("_heal_aura")
	var ay: float = (aura.global_position.y - pp.y) if aura != null else -1.0
	var aq := (aura.mesh as QuadMesh) if aura != null else null
	verdict("A4 овал лежит под ногами (%.2f м над точкой земли), квад %.2f × %.2f" % [ay,
		aq.size.x if aq != null else 0.0, aq.size.y if aq != null else 0.0],
		aura != null and aura.visible and ay < 0.35 and aq != null
		and aq.size.y < aq.size.x * 0.6 and absf(aq.size.x - _MonkS.AURA_DIAM_M) < 0.01)
	_free_all([monk, pat])
	await pframes(3)

	# ═══ B. ЗВУК УБИЙСТВ ═════════════════════════════════════════════════════
	print("\n═════ B. СМЕХ ТОЛЬКО ЗА ГОБЛИНОМ, РЫК ТРОЛЛЯ ═════")
	var bp := Vector3(-40.0, 0.0, -420.0)
	_clear_trees(bp, 25.0)
	var laugh0: int = GameManager.laugh_events
	var supp0: int = GameManager.laugh_suppressed
	var tv0: int = GameManager.troll_victory_events
	# Отряд игрока из одного, добивает ТРОЛЛЬ при гоблине рядом
	var v1: Array = _squad("spearman", P, bp, 1)
	var gob1: Array = _squad("goblin_spearman", GB, bp + Vector3(6.0, 0.0, 0.0), 3)
	_freeze(gob1)
	var trl: Unit = _spawn("troll", GB, bp + Vector3(0.0, 0.0, 6.0))
	trl.set_tick(false)
	(v1[0] as Unit).take_damage(1.0e9, trl)
	await pframes(2)
	verdict("B1 добил тролль при гоблинах рядом — хора смеха НЕТ, рык тролля есть",
		GameManager.laugh_events == laugh0 and GameManager.troll_victory_events == tv0 + 1,
		"смех %d→%d, рык %d→%d" % [laugh0, GameManager.laugh_events, tv0, GameManager.troll_victory_events])
	var v2: Array = _squad("spearman", P, bp + Vector3(2.0, 0.0, 0.0), 1)
	(v2[0] as Unit).take_damage(1.0e9, gob1[0])
	await pframes(2)
	verdict("B2 добил гоблин в малой стычке (1 отряд орды рядом) — хор смеха",
		GameManager.laugh_events == laugh0 + 1, "смех %d→%d" % [laugh0, GameManager.laugh_events])
	# Генеральное сражение: больше LAUGH_MAX_SQUADS отрядов орды в обзоре
	var horde: Array = []
	for k in range(_GobCfg.LAUGH_MAX_SQUADS + 1):
		horde.append_array(_squad("goblin_spearman", GB, bp + Vector3(-4.0 - 2.0 * float(k), 0.0, 4.0), 2))
	_freeze(horde)
	var v3: Array = _squad("spearman", P, bp + Vector3(1.0, 0.0, 1.0), 1)
	(v3[0] as Unit).take_damage(1.0e9, gob1[0])
	await pframes(2)
	verdict("B3 добил гоблин при %d+ отрядах орды рядом — хор подавлен" % (_GobCfg.LAUGH_MAX_SQUADS + 1),
		GameManager.laugh_events == laugh0 + 1 and GameManager.laugh_suppressed == supp0 + 1,
		"смех %d, подавлено %d→%d" % [GameManager.laugh_events, supp0, GameManager.laugh_suppressed])
	_free_all(gob1); _free_all(horde); _free_all([trl])
	await pframes(3)

	# ═══ C. ПЕНЬ И ТРОЛЛИ ═════════════════════════════════════════════════════
	print("\n═════ C. ПЕНЬ: ТАЙМЕР, СТРАЖИ, HP, ГНОЛЛЫ ═════")
	verdict("C1 стражей у пня не больше %d, помощников по удару нет" % _GobCfg.TROLL_GUARDS_MAX,
		_GobCfg.TROLL_GUARDS_MAX == 2 and _GobCfg.TROLL_AGGRO_HELPERS == 0 and _GobCfg.TROLL_AGGRO_BONUS == 0)
	verdict("C2 запас тролля −20 %% (%.0f = 12700 × 0.8)" % _UCfg.stat("troll", "health"),
		absf(_UCfg.stat("troll", "health") - 12700.0 * 0.8) < 1.0)
	verdict("C3 гнолл бросает на 15 %% чаще (кд %.2f ≈ 2.08 × 0.85)" % _UCfg.stat("gnoll", "attack_cooldown"),
		absf(_UCfg.stat("gnoll", "attack_cooldown") - 2.08 * 0.85) < 0.02)
	verdict("C4 стадо: старт 5, излишек сверх %d тролль ест, отара заново по 5" % _GobCfg.TROLL_HUNGRY_FLOCK,
		_GobCfg.SHEEP_START == 5 and _GobCfg.TROLL_HUNGRY_FLOCK == 5 and _GobCfg.SHEEP_RESPAWN_COUNT == 5)
	var t0: float = float(main.game_clock())
	GameManager.note_lair_fell(P)
	verdict("C5 сразу после сноса пень восстановить нельзя", not GameManager.lair_regen_ready(P))
	main.set_game_clock(t0 + _GobCfg.LAIR_REGEN_SEC - 1.0)
	var early: bool = GameManager.lair_regen_ready(P)
	main.set_game_clock(t0 + _GobCfg.LAIR_REGEN_SEC + 1.0)
	verdict("C6 …и можно только через %.0f с" % _GobCfg.LAIR_REGEN_SEC,
		not early and GameManager.lair_regen_ready(P))
	main.set_game_clock(t0)
	GameManager.lair_fell_at.erase(P)
	var lair = GameManager.troll_lair
	verdict("C7 руина пня — тот же рисунок, затенённый",
		lair != null and String(lair.call("ruin_sprite_override")).ends_with("Dead Tree.png")
		and (lair.call("ruin_tint") as Color).r < 0.6)
	verdict("C8 глушь вокруг пня посажена (декор %d, деревьев %d)" % [int(main.lair_glade_deco), int(main.lair_glade_trees)],
		int(main.lair_glade_deco) >= 20 and int(main.lair_glade_trees) >= 6)

	# ═══ D. КЛИК, МАССОВЫЙ ПРИКАЗ, СТРЕЛКИ ═══════════════════════════════════
	print("\n═════ D. КЛИК ПО РЕЛЬЕФУ, КРУПНАЯ ЦЕЛЬ, СТРЕЛКИ ═════")
	var sm = main.selection_manager
	var cam: Camera3D = get_viewport().get_camera_3d()
	# Точка земли по рельефу: берём точку на плато (высота > 1 м) и целимся в неё
	var hi := Vector3.INF
	for pl in main.plateau_list():
		var pa: Array = pl
		hi = Vector3(float(pa[0]), GameManager.get_terrain_height(float(pa[0]), float(pa[1])), float(pa[1]))
		break
	if hi == Vector3.INF or cam == null:
		verdict("D1 точка земли под курсором считается по рельефу (плато не найдено — пропуск)", true)
	else:
		main.set_process(false)
		cam.get_parent().set_process(false)
		main._camera.pan_to(Vector3(hi.x, 0.0, hi.z))
		main._camera._update_position()
		await frames(2)
		var scr: Vector2 = cam.unproject_position(hi)
		var pick: Dictionary = sm._pick_at(scr, Constants.LAYER_GROUND)
		var gp: Vector3 = pick["position"]
		var pick_pos_ok: bool = gp != Vector3.ZERO
		# Сравниваем с плоскостью y=0: у неё точка ушла бы на высота/tan(наклон)
		var from := cam.project_ray_origin(scr)
		var dirn := cam.project_ray_normal(scr)
		var flat := from + dirn * (-from.y / dirn.y)
		var err_flat: float = _xz(flat, hi)
		verdict("D1 точка земли под курсором считается по рельефу (плато %.2f м; ошибка плоскости y=0 была бы %.2f м)" % [hi.y, err_flat],
			pick_pos_ok and hi.y > 0.5 and err_flat > 0.3, "pick=%s" % str(gp))
		main.set_process(true)
		cam.get_parent().set_process(true)
	# Массовый клик по троллю: 5 отрядов, вокруг туши мест на BIG_TARGET_SQUADS
	var dp := Vector3(40.0, 0.0, -420.0)
	_clear_trees(dp, 30.0)
	var big: Unit = _spawn("troll", GB, dp)
	big.set_tick(false)
	var extra_foe: Array = _squad("goblin_spearman", GB, dp + Vector3(3.5, 0.0, 0.0), 2)
	_freeze(extra_foe)
	var five: Array = []
	var sq_ids: Array = []
	for k in range(5):
		var men_k: Array = _squad("warrior", P, dp + Vector3(-14.0 + 3.0 * float(k), 0.0, 10.0), 4, 2)
		five.append_array(men_k)
		sq_ids.append((men_k[0] as Unit).squad_id)
	sm.select_units(five)
	await pframes(3)      # сетка ядра собирается раз в физкадр
	var spread: Dictionary = sm._big_target_spread(big)
	var spilled := 0
	var to_other := 0
	for sid_s in spread:
		spilled += 1
		if spread[sid_s] != big:
			to_other += 1
	verdict("D2 из 5 отрядов на тушу идут %d, остальным %d — ближайший враг в %.0f м" % [sm.BIG_TARGET_SQUADS, spilled, sm.BIG_SPILL_R],
		spilled == 5 - sm.BIG_TARGET_SQUADS and to_other == spilled)
	# Застрявший на подходе переключается сам. Воспроизводим «не продвигаюсь»
	# честно и детерминированно: одиночный мечник с приказом на тушу в 8 м и
	# нулевым шагом (зажат), рядом в 3 м — чужой копейщик. Через
	# STUCK_RETARGET_STREAK проверок детектор обязан перевести его на соседа
	var jam: Unit = _spawn("warrior", P, dp + Vector3(8.0, 0.0, 0.0))
	var jam_foe: Unit = _spawn("goblin_spearman", GB, dp + Vector3(8.0, 0.0, 3.0))
	jam_foe.set_tick(false)
	await pframes(2)
	jam.command_attack(big, true, false, true)
	jam.move_speed = 0.0
	jam._soa_push_stats()
	var swapped := false
	for _w in range(int(Unit.STUCK_CHECK_SEC * 60.0 * (Unit.STUCK_RETARGET_STREAK + 2)) + 30):
		await get_tree().physics_frame
		var jt = jam.attack_target
		if jt != null and is_instance_valid(jt) and jt != big 				and _xz((jt as Node3D).global_position, jam.global_position) <= Unit.STUCK_RETARGET_RANGE + 0.5:
			swapped = true
			break
	verdict("D3 застрявший на подходе к туше (нет продвижения %d × %.1f с) переключился на врага в %.0f м (перехватов %d)" % [Unit.STUCK_RETARGET_STREAK, Unit.STUCK_CHECK_SEC, Unit.STUCK_RETARGET_RANGE, jam.stuck_retargets],
		swapped and jam.stuck_retargets >= 1)
	_free_all([jam, jam_foe])
	_free_all(five); _free_all(extra_foe); _free_all([big])
	await pframes(3)
	# Мгновенный отклик стрелков: отряд лучников в залпе, приказ по троллю
	var ap := Vector3(80.0, 0.0, -420.0)
	_clear_trees(ap, 25.0)
	GameManager.finish_research(P, "archer_1d")
	var arch: Array = _squad("archer", P, ap, 10)
	var asid: int = (arch[0] as Unit).squad_id
	GameManager.squad_set_ability(asid, "archer_1d", true)
	var big2: Unit = _spawn("troll", GB, ap + Vector3(0.0, 0.0, -12.0))
	big2.set_tick(false)
	await pframes(40)
	# Стрелки СТОЯТ без цели (как «зависшие рядом в замесе»): цель и дрёма
	# ядра сняты приказом на своё место, взгляд уведён в сторону
	for u in arch:
		(u as Unit).command_move((u as Unit).global_position)
	await pframes(2)
	for u in arch:
		(u as Unit)._attack_timer = 0.0
		(u as Unit)._facing = Vector3(1.0, 0.0, 0.0)
	# Окно залпа от авто-агро закрыто и пауза снята: клик обязан открыть своё
	(GameManager.squads[asid] as Dictionary)["volley_until"] = 0
	(GameManager.squads[asid] as Dictionary)["volley_next"] = Time.get_ticks_msec() + 100000
	var primes0: int = GameManager.volley_primes
	var fired0: int = GameManager.arrows_fired
	sm.select_units(arch)
	for u in arch:
		(u as Unit).command_attack(big2, true, false, true)
	# Готовые стрелки: остаток перезарядки возвращает дрёма ядра при смене
	# цели, поэтому «готов» ставится ПОСЛЕ приказа (стреляют те, кто готов)
	for u in arch:
		(u as Unit)._attack_timer = 0.0
	var faced := 0
	for u in arch:
		if (u as Unit)._facing.z < -0.7:
			faced += 1
	var primed: bool = GameManager.volley_primes > primes0
	var open_now: bool = GameManager.squad_volley_open(asid)
	await pframes(6)
	var fired1: int = GameManager.arrows_fired
	verdict("D4 по клику стрелки развернулись тем же кадром (%d из %d) и окно залпа открыто" % [faced, arch.size()],
		faced == arch.size() and open_now and (primed or GameManager.squad_volley_mode(asid)),
		"режим залпа %s, взводов %d, окно %s" % [str(GameManager.squad_volley_mode(asid)), GameManager.volley_primes - primes0, str(open_now)])
	verdict("D5 …и выстрелили в первые кадры, не дожидаясь такта залпов (%d стрел за 6 кадров)" % (fired1 - fired0), fired1 - fired0 >= 5)
	_free_all(arch); _free_all([big2])
	await pframes(3)

	# ═══ E. КОПЕЙЩИКИ: СТЕНА КОПИЙ, КОРОБОЧКА, ОБОРОНА ═══════════════════════
	print("\n═════ E. СТЕНА КОПИЙ ТОЛЬКО КОПЕЙЩИКАМ, ФАЛАНГА ЦЕЛИКОМ ═════")
	var ep := Vector3(-100.0, 0.0, -400.0)
	_clear_trees(ep, 30.0)
	GameManager.finish_research(P, "spearman_1d")
	var sp: Array = _squad("spearman", P, ep, 12)
	var wr: Array = _squad("warrior", P, ep + Vector3(10.0, 0.0, 0.0), 12)
	var ssid: int = (sp[0] as Unit).squad_id
	var wsid: int = (wr[0] as Unit).squad_id
	var all_e: Array = sp + wr
	sm.formation_mode = sm.FORM_WIDE
	var a := ep + Vector3(-20.0, 0.0, 15.0)
	var b := ep + Vector3(30.0, 0.0, 15.0)
	var plan: Dictionary = sm._mono_formation_slots(a, b, all_e)
	var rows_sp := 0
	var rows_wr := 0
	var flat: Array = plan["flat"]
	for i in range(flat.size()):
		var u := flat[i] as Unit
		if u.squad_id == ssid:
			rows_sp = maxi(rows_sp, int(plan["rows"][i]))
		elif u.squad_id == wsid:
			rows_wr = maxi(rows_wr, int(plan["rows"][i]))
	verdict("E1 стена включена: копейщики на длинной линии в %d шеренги, мечники — в %d (по линии)" % [rows_sp + 1, rows_wr + 1],
		GameManager.spear_wall_ready(ssid) and rows_sp + 1 == GameManager.SPEAR_WALL_ROWS and rows_wr + 1 == 1)
	var plan_s: Dictionary = sm._mono_formation_slots(ep + Vector3(-1.5, 0.0, 15.0), ep + Vector3(1.5, 0.0, 15.0), sp)
	var rows_short := 0
	for r in plan_s["rows"]:
		rows_short = maxi(rows_short, int(r))
	verdict("E2 …и на короткой линии тоже ровно %d (глубина не зависит от растяга)" % (rows_short + 1),
		rows_short + 1 == GameManager.SPEAR_WALL_ROWS)
	GameManager.squad_set_ability(ssid, "spearman_1d", false)
	var plan_off: Dictionary = sm._mono_formation_slots(a, b, sp)
	var rows_off := 0
	for r in plan_off["rows"]:
		rows_off = maxi(rows_off, int(r))
	verdict("E3 стена выключена — копейщики прямоугольником по линии (%d шеренга)" % (rows_off + 1),
		not GameManager.spear_wall_ready(ssid) and rows_off + 1 == 1)
	GameManager.squad_set_ability(ssid, "spearman_1d", true)
	# Коробочка [2] не запоминается: после отпускания ПКМ режим снова широкий
	sm.formation_mode = sm.FORM_DEEP
	sm.select_units(wr)
	sm._rmb_down = true
	sm._rmb_dragging = true
	sm._rmb_screen_start = Vector2(100.0, 100.0)
	sm._rmb_world_start = a
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = false
	ev.position = Vector2(400.0, 100.0)
	sm._unhandled_input(ev)
	await pframes(2)
	# ── ТРЕБОВАНИЕ РАЗВЁРНУТО ВЛАДЕЛЬЦЕМ 13.09.2026 ──────────────────────
	# Здесь проверялось, что отпускание ПКМ СБРАСЫВАЕТ коробочку в широкий
	# фронт (спринт 20, модуль 4). Жалоба пришла ровно наоборот: «каждый раз
	# приходится жать [2] заново». Режим теперь ЗАПОМИНАЕТСЯ, а прежнюю
	# жалобу («стена копий раздаётся всем») снимает не сброс, а ВИДИМОСТЬ:
	# текущий режим написан в верхней панели. Персистентность целиком
	# проверяет qa_formation_keys, блок E
	verdict("E4 режим построения переживает отпускание ПКМ (заказ 13.09.2026)",
		sm.formation_mode == sm.FORM_DEEP,
		"режим %d" % sm.formation_mode)
	# Оборона: фаланга подаётся к врагу целиком
	_free_all(wr)
	await pframes(2)
	sm.select_units(sp)
	sm.set_selection_stance("defense")
	await pframes(60 * 3)
	for u in sp:
		(u as Unit)._facing = Vector3(0.0, 0.0, -1.0)
	var course: Vector3 = GameManager.squad_course(ssid)
	var c0: Vector3 = _centre(sp)
	var foe_far: Unit = _spawn("goblin_spearman", GB, c0 + course * 9.0)
	foe_far.set_tick(false)
	await pframes(60 * 2)
	var c1: Vector3 = _centre(sp)
	verdict("E5 враг в 9 м (дальше %.0f м) — фаланга стоит (сдвиг %.2f м)" % [GameManager.PHALANX_PRESS_RANGE, _xz(c1, c0)],
		_xz(c1, c0) < 0.4)
	foe_far.take_damage(1.0e9)
	await pframes(2)
	var foe_near: Unit = _spawn("goblin_spearman", GB, c0 + course * 4.5)
	foe_near.set_tick(false)
	var presses0: int = GameManager.phalanx_presses
	# Разброс строя до и после: форма обязана сохраниться
	var spread0 := 0.0
	for u in sp:
		spread0 = maxf(spread0, _xz((u as Unit).global_position, c0))
	await pframes(60 * 4)
	var c2: Vector3 = _centre(sp)
	var spread1 := 0.0
	for u in sp:
		spread1 = maxf(spread1, _xz((u as Unit).global_position, c2))
	var adv: float = (c2 - c0).dot(course)
	verdict("E6 враг в 4.5 м — ВСЯ фаланга подалась вперёд (%.2f м, шагов %d), строй цел (разброс %.2f → %.2f)" % [adv, GameManager.phalanx_presses - presses0, spread0, spread1],
		GameManager.phalanx_presses > presses0 and adv >= 0.8 and spread1 <= spread0 + 0.6)
	var lone := 0
	for u in sp:
		var uu := u as Unit
		if uu.attack_target == foe_near and _xz(uu.global_position, c2) > spread0 + 1.0:
			lone += 1
	verdict("E7 одиночки из строя за врагом не выбегают (%d)" % lone, lone == 0 and not Unit.PHALANX_PULL_UP_SINGLE)
	_free_all(sp); _free_all([foe_near])
	await pframes(3)

	# ═══ F. РЕМОНТ ПЕПЕЛИЩА ═════════════════════════════════════════════════
	print("\n═════ F. ПКМ РАБОЧИМИ ПО РУИНЕ — СТРОЙПЛОЩАДКА ═════")
	var fp := Vector3(-140.0, 0.0, -420.0)
	_clear_trees(fp, 20.0)
	var house: Building = _House.new()
	house.faction = P
	house.set("variant_id", "house")
	main.world_add(house)
	house.global_position = _g(fp)
	await pframes(3)
	ResourceManager.add_resource(P, Constants.RESOURCE_WOOD, 5000.0)
	ResourceManager.add_resource(P, Constants.RESOURCE_STONE, 5000.0)
	ResourceManager.add_resource(P, Constants.RESOURCE_GOLD, 5000.0)
	house.take_damage(1.0e9)
	await pframes(3)
	var ruin: Node = null
	for r in get_tree().get_nodes_in_group("ruins"):
		if is_instance_valid(r) and _xz((r as Node3D).global_position, fp) < 3.0:
			ruin = r
	var shapes := 0
	if ruin != null:
		for ch in ruin.get_children():
			if ch is CollisionShape3D:
				shapes += 1
	verdict("F1 руина стоит и кликается ДВУМЯ формами: коробка у основания и пластина по картинке",
		ruin != null and shapes == 2, "форм %d" % shapes)
	var wk: Unit = _spawn("worker", P, fp + Vector3(0.0, 0.0, 8.0))
	sm.select_units([wk])
	var ok_rebuild: bool = sm._try_rebuild_ruin(ruin)
	await pframes(3)
	var site: Building = null
	for s0 in get_tree().get_nodes_in_group("construction_sites"):
		if is_instance_valid(s0) and _xz((s0 as Node3D).global_position, fp) < 3.0:
			site = s0
	verdict("F2 ПКМ рабочим — руина ушла, на её месте стройплощадка того же дома, рабочий идёт строить",
		ok_rebuild and site != null and (not is_instance_valid(ruin) or ruin.is_queued_for_deletion())
		and wk.state == Unit.State.BUILDING and (wk as Worker).build_target == site)
	_free_all([wk])
	if site != null:
		site.queue_free()
	await pframes(3)

	# ═══ G. ПЕРЕМИРИЕ И ИИ ОРДЫ ═════════════════════════════════════════════
	print("\n═════ G. ПЕРЕМИРИЕ, ЗАЩИТА КРАСНОГО ИИ, РЕЙДЫ ═════")
	main.set_game_clock(0.0)
	verdict("G1 первые %.0f с — перемирие (осталось %.0f с)" % [_GobCfg.TRUCE_SEC, GameManager.truce_left()],
		GameManager.truce_active() and absf(GameManager.truce_left() - _GobCfg.TRUCE_SEC) < 2.0
		and _AICfg.AI_TRUCE_SEC == _GobCfg.TRUCE_SEC and _GobCfg.PEACE_SEC == _GobCfg.TRUCE_SEC)
	main.set_game_clock(_GobCfg.TRUCE_SEC + 5.0)
	verdict("G2 после срока перемирия нет", not GameManager.truce_active())
	main.set_game_clock(0.0)
	var gai = main.goblin_ai
	if gai == null:
		verdict("G3 ИИ орды нет — пропуск", true)
	else:
		gai.clock = 0.0
		var early_ai: bool = gai._target_faction_allowed(E)
		gai.clock = _GobCfg.AI_PROTECT_SEC + 1.0
		# Крепость красного ИИ стоит с закладки партии (_spawn_enemy_base)
		var has_keep := false
		for kb in get_tree().get_nodes_in_group(Constants.building_group(E)):
			if is_instance_valid(kb) and (kb as Building).has_method("is_stronghold") and bool((kb as Building).call("is_stronghold")):
				has_keep = true
		var late_castle: bool = gai._target_faction_allowed(E)
		verdict("G3 база красного ИИ под защитой: до %.0f с — нельзя, после (крепость есть=%s) — можно" % [_GobCfg.AI_PROTECT_SEC, str(has_keep)],
			not early_ai and has_keep and late_castle,
			"рано=%s, поздно=%s" % [str(early_ai), str(late_castle)])
		verdict("G4 игрок защитой не прикрыт", gai._target_faction_allowed(P))
		# Рейд без добычи возвращается, а не пасётся у чужой базы
		gai.clock = 100.0
		gai.phase = gai.PHASE_HARASS
		gai.known_bases = {P: Vector3(300.0, 0.0, 300.0)}
		var lone_g: Unit = _spawn("goblin_spearman", GB, fp + Vector3(0.0, 0.0, -20.0))
		lone_g.set_tick(false)
		var rsq: Dictionary = {"id": 999999, "members": [lone_g], "role": gai.ROLE_RAID, "type": "goblin_spearman", "peak": 1}
		gai.raid_sids[999999] = 50.0
		var rplan: Dictionary = gai._raid_plan(rsq)
		verdict("G5 рейд без единой добычи у базы дольше %.0f с — снят и идёт домой (возвратов %d)" % [_GobCfg.RAID_IDLE_SEC, int(gai.raid_returns)],
			int(gai.raid_returns) >= 1 and not gai.raid_sids.has(999999) and rplan.has("goal")
			and (rplan["goal"] as Vector3).distance_to(Vector3(300.0, 0.0, 300.0)) > 50.0)
		gai.known_bases = {}
		gai.raid_sids = {}
		gai.phase = gai.PHASE_PEACE
		verdict("G6 диверсии — по 1-3 отряда", _GobCfg.RAID_SQUADS_SMALL >= 1 and _GobCfg.RAID_SQUADS_BIG <= 3)
	_finish()
