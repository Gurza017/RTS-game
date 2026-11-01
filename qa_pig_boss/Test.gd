extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_pig_boss — СВИНОБОСС-ПОЛКОВОДЕЦ (ТЗ 28.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A СПАВН     — spawn_boss_squad: один босс + свита наездников ранга
##                 BOSS_ESCORT_VET, признак boss у отряда, ×3 по листу, тело в
##                 ядре, перекрашенный лист (свой бакет), знамя с цифрой и
##                 хвостом (своя текстура), второго босса нет, ручка pig_boss.
##   B АУРА      — чужой в BOSS_AURA_R подавлен (бонус ауры монаха снят),
##                 дальше — нет; ручка boss_aura.
##   C КЛИЧ      — откат BOSS_SCREECH_CD_SEC по game_ms, ×FOE/×ALLY урон у
##                 жертвы, замешательство один раз на клич; ручка boss_screech.
##   D ОТХОД     — hp < BOSS_WITHDRAW_HP → withdraw, возврат при > RETURN_HP;
##                 ручка boss_withdraw.
##   E МОЗГ      — приказы пачкой через очередь орды, повтор не чаще
##                 BOSS_REISSUE_SEC, ≤ 10 вызовов плотности, клич по решению;
##                 ручка pig_boss.
##   F ИНТЕГРАЦИЯ— PRELOAD_SCENES/HUD/сохранение знают босса.
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_pig_boss/Test.tscn

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _Spawn := preload("res://scripts/spawn_config.gd")
const _BannerArt := preload("res://scripts/BannerArt.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Save := preload("res://scripts/SaveLoadManager.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _base: Vector3 = Vector3.ZERO
var _boss: Unit = null
var _boss_sid: int = 0

func _ready() -> void:
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_pig_boss: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int, sp: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(
			at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0,
			at.z + float(i / cols) * sp))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _members(sid: int) -> Array:
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return []
	var out: Array = []
	for m in (sq as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _kill(men: Array) -> void:
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _freeze(men: Array) -> void:
	for u in men:
		if u != null and is_instance_valid(u):
			(u as Unit).set_tick(false)

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
			for d in [Vector3.ZERO, Vector3(40.0, 0.0, 0.0), Vector3(-40.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 40.0), Vector3(0.0, 0.0, -40.0), Vector3(0.0, 0.0, 70.0)]:
				var q: Vector3 = p + (d as Vector3)
				h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
				if GameManager.is_water(q.x, q.z) or GameManager.is_cliff(q.x, q.z):
					h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

## Босс отряда (has_method is_pig_boss) — по составу напрямую (правило squad_members)
func _boss_of(sid: int) -> Unit:
	for m in _members(sid):
		if (m as Unit).is_pig_boss():
			return m as Unit
	return null

func _spawn_boss(at: Vector3) -> int:
	# Блоки независимы: босс прошлого блока пал — признак партии снимаем
	GameManager.pig_boss_fallen = false
	var sid: int = int(main.spawn_boss_squad(at))
	_boss_sid = sid
	_boss = _boss_of(sid) if sid > 0 else null
	return sid

func _run() -> void:
	# Босс и отряды ставятся на точку стенда: вход орды из-за кромки (ТЗ
	# 31.10.2026, стережёт qa_tz1031c) увёл бы их к краю карты
	_Opt.horde_edge_entry = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.call_deferred("thaw_lairs_now")
	for _i in range(8):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("cav_commander") != null:
		main.cav_commander.set_process(false)
	if main.get("pig_boss_cmd") != null:
		main.pig_boss_cmd.set_process(false)
	if main.get("assault_event") != null:
		main.assault_event.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction != F:
			(n as Unit).set_tick(false)
	GameManager.troll_lair = null
	GameManager.pop_limit_enabled = false
	_base = _flat_spot(Vector3(-40.0, 0.0, -30.0))
	main._clear_area_of_resources(_base, 90.0)
	await pframes(6)
	print("  площадка (%.0f, %.0f)" % [_base.x, _base.z])
	await _a_spawn()
	await _b_aura()
	await _c_screech()
	# ТЗ 29.10.2026, 2В: бегство на базу заменило отход к волне; блок D — страж
	# прежнего пути при снятой ручке boss_flee_base (новый — qa_pig_ram X)
	var fb0: bool = _Opt.boss_flee_base
	_Opt.boss_flee_base = false
	await _d_withdraw()
	_Opt.boss_flee_base = fb0
	await _e_brain()
	await _f_integration()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_spawn() -> void:
	print("\n═════ A. СПАВН ОТРЯДА БОССА ═════")
	var sid: int = _spawn_boss(_base)
	verdict("A1 spawn_boss_squad вернул отряд (sid=%d)" % sid, sid > 0)
	if sid <= 0:
		return
	await pframes(3)
	var men: Array = _members(sid)
	var bosses := 0
	var riders := 0
	for m in men:
		if (m as Unit).is_pig_boss():
			bosses += 1
		elif (m as Unit).stat_id == "goblin_rider":
			riders += 1
	var want_riders: int = int(_GobCfg.SQUAD_SIZE.get("pig_boss", 31)) - 1
	verdict("A2 состав: боссов %d (ждём 1), наездников %d (ждём %d)" % [bosses, riders, want_riders],
		bosses == 1 and riders == want_riders)
	var sq: Dictionary = GameManager.squads[sid]
	verdict("A3 свита — ветераны ранга BOSS_ESCORT_VET: level=%d" % int(sq["level"]),
		int(sq["level"]) == _GobCfg.BOSS_ESCORT_VET)
	verdict("A4 у отряда признак boss и тип pig_boss", bool(sq.get("boss", false)) and String(sq["type"]) == "pig_boss")
	var b: Unit = _boss
	verdict("A5 босс зарегистрирован в GameManager.pig_boss", b != null and GameManager.pig_boss == b and GameManager.pig_boss_alive())
	if b == null:
		return
	var asp := b._active_sprite as AnimatedSprite3D
	var px: float = asp.pixel_size if asp != null else 0.0
	verdict("A6 модель ×3 наездника по листу: pixel_size %.5f = PIXEL_SIZE × %.1f" % [px, _GobCfg.BOSS_SIZE_SCALE],
		asp != null and absf(px - _GobCfg.PIXEL_SIZE * _GobCfg.BOSS_SIZE_SCALE) < 1e-6)
	var fh: float = 0.0
	if asp != null:
		var first: Texture2D = asp.sprite_frames.get_frame_texture("idle", 0)
		var at := first as AtlasTexture
		fh = at.region.size.y if at != null else first.get_size().y
		var pad: int = Unit._anim_bottom_px(first)
		var want_y: float = (fh * 0.5 - float(pad)) * px
		verdict("A7 центр спрайта по ленте: %.3f (ждём %.3f)" % [asp.position.y, want_y], absf(asp.position.y - want_y) < 1e-4)
	var sr: float = GameManager.army.get_sep_radius(b._soa)
	verdict("A8 тело в ядре: sep_radius %.2f > SEP_MIN_DIST %.2f, fine_ring_radius %.2f > 0" % [sr, Unit.SEP_MIN_DIST, b.fine_ring_radius()],
		sr > Unit.SEP_MIN_DIST and b.fine_ring_radius() > 0.0 and b.giant_class())
	# Перекрашенный лист — своя текстура, значит свой бакет общей отрисовки
	var rider: Unit = null
	for m in men:
		if (m as Unit).stat_id == "goblin_rider":
			rider = m
			break
	var tex_ok := false
	if asp != null and rider != null:
		var rasp := rider._active_sprite as AnimatedSprite3D
		var bt := asp.sprite_frames.get_frame_texture("idle", 0) as AtlasTexture
		var rt := rasp.sprite_frames.get_frame_texture("idle", 0) as AtlasTexture
		tex_ok = bt != null and rt != null and bt.atlas != rt.atlas \
			and bt.atlas.get_size() == rt.atlas.get_size()
		if tex_ok:
			# Подтон холодный: синий канал среднего непрозрачного пикселя выше красного
			var img: Image = (bt.atlas as Texture2D).get_image()
			var acc := Color(0, 0, 0, 0)
			var k := 0
			for y in range(0, img.get_height(), 8):
				for x in range(0, img.get_width(), 8):
					var c: Color = img.get_pixel(x, y)
					if c.a > 0.5:
						acc += c
						k += 1
			if k > 0:
				acc = acc / float(k)
			tex_ok = k > 0 and acc.b > acc.r
			print("    средний цвет доспеха: r=%.2f g=%.2f b=%.2f (%d пикс.)" % [acc.r, acc.g, acc.b, k])
	verdict("A9 доспех: лист босса — своя перекрашенная копия листа наездника (холодный подтон)", tex_ok)
	await pframes(2)
	var banner = sq.get("banner")
	var ban_ok: bool = banner != null and is_instance_valid(banner) and bool(banner.shown_boss)
	# РАЗВОРОТ ТЗ 30.10.2026: знамя полководца — общая шкала, синий вымпел с
	# лычками ранга отряда, не ниже трёх белых; рваной зелёной тряпки больше нет
	var blvl: int = int(sq.get("level", 0))
	var bt_tex: Texture2D = _BannerArt.boss_texture(blvl)
	var gt_tex: Texture2D = _BannerArt.goblin_tongue_texture(maxi(blvl, 1))
	# РАЗВОРОТ ТЗ 31.10.2026: знамёна орды — только зелёные; у Свинобосса —
	# зелёные язычки ранга отряда, не ниже BOSS_BANNER_MIN_TIER
	var want: Texture2D = _BannerArt.goblin_tongue_texture(maxi(blvl, _BannerArt.BOSS_BANNER_MIN_TIER))
	verdict("A10 знамя полководца: узел есть, shown_boss, текстура — зелёные язычки орды (gt %s)" % str(gt_tex != null),
		ban_ok and bt_tex != null and bt_tex == want and (banner.mesh != null if ban_ok else false))
	var img_b: Image = (bt_tex as ImageTexture).get_image()
	var n_blue := 0
	var n_white := 0
	var n_green := 0
	for y in range(img_b.get_height()):
		for x in range(img_b.get_width()):
			var c: Color = img_b.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if _near(c, _UCfg.BANNER_BLUE):
				n_blue += 1
			if _near(c, _UCfg.CHEV_WHITE):
				n_white += 1
			if c.g > c.r + 0.2 and c.g > c.b + 0.2:
				n_green += 1
	var b0: Texture2D = _BannerArt.boss_texture(0)
	var b8: Texture2D = _BannerArt.boss_texture(8)
	verdict("A11 знамя полководца — зелёное орды (%d синих, %d белых, зелёного %d), ранг %d" % [
		n_blue, n_white, n_green, blvl], bt_tex == want and n_green > 200 and n_blue < 20
		and b0 == _BannerArt.goblin_tongue_texture(3) and b8 == _BannerArt.goblin_tongue_texture(8))
	var sid2: int = int(main.spawn_boss_squad(_base + Vector3(30.0, 0.0, 0.0)))
	verdict("A12 второго живого босса не бывает: повторный спавн вернул %d" % sid2, sid2 == 0)
	# Ручка: без pig_boss босс не рождается
	_kill(men)
	await pframes(3)
	verdict("A13 после гибели босса pig_boss_alive() = false", not GameManager.pig_boss_alive())
	# ТЗ 29.10.2026: босс пал — окончательно, нового орда не нанимает
	var sid_again: int = int(main.spawn_boss_squad(_base))
	verdict("A15 босс пал окончательно: признак %s, повторный спавн вернул %d" % [GameManager.pig_boss_fallen, sid_again],
		GameManager.pig_boss_fallen and sid_again == 0 and not GameManager.pig_boss_may_spawn())
	_Opt.pig_boss = false
	var sid3: int = int(main.spawn_boss_squad(_base))
	_Opt.pig_boss = true
	verdict("A14 ручка pig_boss=false: отряд не рождается (sid=%d)" % sid3, sid3 == 0)

# ═════════════════════════════════════════════════════════════════════════════
func _b_aura() -> void:
	print("\n═════ B. АУРА ПОДАВЛЕНИЯ ═════")
	var sid: int = _spawn_boss(_base)
	await pframes(2)
	if _boss == null:
		verdict("B0 босс для блока B", false)
		return
	# Свиту замораживаем — она бы бросилась на бойцов игрока
	for m in _members(sid):
		if m != _boss:
			(m as Unit).set_tick(false)
	_immortal(_boss)
	var near: Unit = _spawn("spearman", F, _base + Vector3(28.0, 0.0, 0.0))
	var far: Unit = _spawn("spearman", F, _base + Vector3(70.0, 0.0, 0.0))
	near.set_tick(false)
	far.set_tick(false)
	var until: int = Unit.game_ms() + 120000
	near.aura_apply(5.0, 5.0, 0.3, until)
	far.aura_apply(5.0, 5.0, 0.3, until)
	var d_near0: float = near._upgrade_damage_bonus()
	await pframes(90)
	verdict("B1 чужой в %.0f м от босса подавлен (suppressed), подавленных в такте: %d" % [_xz(near.global_position, _boss.global_position), _boss.suppressed_n],
		near.suppressed() and _boss.suppressed_n >= 1)
	verdict("B2 чужой в %.0f м (дальше BOSS_AURA_R %.0f) не подавлен" % [_xz(far.global_position, _boss.global_position), _GobCfg.BOSS_AURA_R],
		not far.suppressed() and _xz(far.global_position, _boss.global_position) > _GobCfg.BOSS_AURA_R)
	var d_near: float = near._upgrade_damage_bonus()
	var d_far: float = far._upgrade_damage_bonus()
	verdict("B3 бонус атаки ауры снят только у подавленного: %.1f (было %.1f) против %.1f у дальнего" % [d_near, d_near0, d_far],
		absf(d_far - d_near - 5.0) < 1e-3 and absf(d_near0 - d_far) < 1e-3)
	# Монах не раздаёт ауру подавленному: прямой вызов раздачи с бонусом отряда
	var mk: Array = _squad("monk", F, _base + Vector3(24.0, 0.0, 6.0), 1, 1, 1.0)
	var monk: Unit = mk[1][0]
	monk.set_tick(false)
	GameManager.squads[int(mk[0])]["bonuses"]["aura_attack"] = 4.0
	var ally2: Unit = _spawn("spearman", F, _base + Vector3(24.0, 0.0, 9.0))
	ally2.set_tick(false)
	await pframes(60)
	monk._tick_aura(0.0, true)
	verdict("B4 аура монаха не ложится на подавленного соседа (aura_touched=%d, у соседа _aura_attack=%.1f)" % [monk.aura_touched, ally2._aura_attack],
		ally2.suppressed() and ally2._aura_attack <= 0.0)
	verdict("B5 ветеранство не аура: vet_attack подавленного не тронут (%.1f)" % near.vet_attack, near.vet_attack == 0.0)
	_Opt.boss_aura = false
	await pframes(int(ceil(float(_GobCfg.BOSS_AURA_HOLD_MS) / 1000.0 * 60.0)) + 30)
	verdict("B6 ручка boss_aura=false: подавление спадает (suppressed=%s)" % str(near.suppressed()), not near.suppressed())
	_Opt.boss_aura = true
	_kill([near, far, monk, ally2])
	_kill(_members(sid))
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _c_screech() -> void:
	print("\n═════ C. ВАРВАРСКИЙ КЛИЧ ═════")
	var sid: int = _spawn_boss(_base)
	await pframes(2)
	if _boss == null:
		verdict("C0 босс для блока C", false)
		return
	var rider: Unit = null
	for m in _members(sid):
		if m != _boss:
			(m as Unit).set_tick(false)
			if rider == null:
				rider = m
	_immortal(_boss)
	var near: Unit = _spawn("spearman", F, _base + Vector3(28.0, 0.0, 0.0))
	var far: Unit = _spawn("spearman", F, _base + Vector3(70.0, 0.0, 0.0))
	var victim: Unit = _spawn("spearman", F, _base + Vector3(70.0, 0.0, 10.0))
	for u in [near, far, victim]:
		(u as Unit).set_tick(false)
	victim.armor = 0.0
	victim.defense = 0.0
	_immortal(victim)
	await pframes(40)
	verdict("C1 клич готов с рождения", _boss.screech_ready())
	var t0: int = Unit.game_ms()
	var ok: bool = _boss.screech()
	verdict("C2 screech() сработал", ok)
	# РАЗВОРОТ ТЗ 29.10.2026: клич стал «Гоблинским горном» — свои ×1.30 атаки
	# и ×FRAIL входящего урона (было ×1.15), чужие ×0.85 (ручка boss_horn)
	var foe_k: float = _GobCfg.BOSS_HORN_FOE_ATK_MULT if _Opt.boss_horn else _GobCfg.BOSS_SCREECH_FOE_MULT
	var ally_k: float = _GobCfg.BOSS_HORN_ALLY_ATK_MULT if _Opt.boss_horn else _GobCfg.BOSS_SCREECH_ALLY_MULT
	verdict("C3 чужой в ауре: замешательство (%d мс), ×%.2f, срок клича стоит" % [near._hesitate_until_ms - t0, near._screech_mult],
		near._hesitate_until_ms > t0 and absf(near._screech_mult - foe_k) < 1e-6 and near._screech_until_ms > t0)
	verdict("C4 свой в ауре: ×%.2f" % (rider._screech_mult if rider != null else 0.0),
		rider != null and absf(rider._screech_mult - ally_k) < 1e-6 and rider._screech_until_ms > t0)
	verdict("C5 дальний (вне ауры) не задет: срок клича %d" % far._screech_until_ms, far._screech_until_ms <= t0)
	var cd_ms: int = _boss._cry_ready_ms - t0
	verdict("C6 откат BOSS_SCREECH_CD_SEC по игровым часам: %d мс, клич не готов" % cd_ms,
		not _boss.screech_ready() and absi(cd_ms - int(_GobCfg.BOSS_SCREECH_CD_SEC * 1000.0)) <= 100)
	# Урон у жертвы: чужой в ауре ×0.85, свой ×1.15, незадетый ×1.0
	var h0: float = victim.current_health
	victim.take_damage(100.0, near)
	var d_foe: float = h0 - victim.current_health
	h0 = victim.current_health
	victim.take_damage(100.0, far)
	var d_plain: float = h0 - victim.current_health
	h0 = victim.current_health
	victim.take_damage(100.0, rider)
	var d_ally: float = h0 - victim.current_health
	verdict("C7 урон 100 у жертвы: от чужого в ауре %.1f, от незадетого %.1f, от своего %.1f" % [d_foe, d_plain, d_ally],
		absf(d_foe / maxf(d_plain, 1e-3) - foe_k) < 0.02
		and absf(d_ally / maxf(d_plain, 1e-3) - ally_k) < 0.02)
	# Цена горна: свой в ауре получает урон ×FRAIL (−20 % стойкости)
	if _Opt.boss_horn and rider != null:
		var rh0: float = rider.current_health
		rider.take_damage(60.0, far)
		var r_horn: float = rh0 - rider.current_health
		var fr_until: int = rider._frail_until_ms
		rider._frail_until_ms = 0
		rh0 = rider.current_health
		rider.take_damage(60.0, far)
		var r_plain: float = rh0 - rider.current_health
		rider._frail_until_ms = fr_until
		verdict("C7б горн: свой в ауре получает урон ×%.2f (%.1f против %.1f)" % [
			_GobCfg.BOSS_HORN_ALLY_FRAIL_MULT, r_horn, r_plain],
			r_plain > 0.0 and absf(r_horn / r_plain - _GobCfg.BOSS_HORN_ALLY_FRAIL_MULT) < 0.03)
	var hes0: int = near._hesitate_until_ms
	await pframes(int(_GobCfg.BOSS_AURA_TICK * 60.0) * 3 + 10)
	verdict("C8 замешательство выдано один раз на клич (срок не продлён: %d = %d), aura_ticks=%d" % [near._hesitate_until_ms, hes0, _boss.aura_ticks],
		near._hesitate_until_ms == hes0 and _boss.hesitated >= 1)
	verdict("C9 срок замешательства BOSS_HESITATE_SEC: %d мс" % (hes0 - t0), absi(hes0 - t0 - int(_GobCfg.BOSS_HESITATE_SEC * 1000.0)) <= 100)
	_Opt.boss_screech = false
	verdict("C10 ручка boss_screech=false: клич не активен и не готов", not _boss.screech_active() and not _boss.screech_ready())
	_Opt.boss_screech = true
	_kill([near, far, victim])
	_kill(_members(sid))
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _fake_wave(sids: Array, pos: Vector3, dir: Vector3) -> Dictionary:
	return {"id": 9000 + sids.size(), "tpl": "boss", "sids": sids, "name": "ford_patrol",
		"pos": pos, "node": null, "tactic": "frontal", "stage": "engage",
		"t0": 0.0, "st_t": 0.0, "men0": 0, "feint_done": false, "calm": 0.0,
		"pts": {}, "roles": {}, "track": {}, "dir": dir}

func _d_withdraw() -> void:
	print("\n═════ D. САМОСОХРАНЕНИЕ ═════")
	var cmd = main.pig_boss_cmd
	var gai = main.goblin_ai
	var sid: int = _spawn_boss(_base)
	await pframes(2)
	if _boss == null or cmd == null:
		verdict("D0 босс и мозг для блока D", false)
		return
	_freeze(_members(sid))
	_boss.set_tick(true)
	var dir := Vector3(0.0, 0.0, 1.0)
	var w: Dictionary = _fake_wave([sid], _base + dir * 60.0, dir)
	gai.waves.append(w)
	_boss.current_health = _boss.max_health * (_GobCfg.BOSS_WITHDRAW_HP - 0.05)
	_boss._soa_push_stats()
	cmd.tick_now()
	verdict("D1 hp < BOSS_WITHDRAW_HP → состояние withdraw, босс отходит с билетом (retreating)",
		cmd.state_name() == "withdraw" and _boss.retreating and _boss.is_withdrawing() and cmd.withdrawals >= 1)
	var want: Vector3 = _base - dir * _GobCfg.BOSS_SHELTER_DIST
	var wp: Vector3 = cmd._withdraw_point
	verdict("D2 укрытие — центр волны минус курс × BOSS_SHELTER_DIST: (%.0f, %.0f), ждём (%.0f, %.0f)" % [wp.x, wp.z, want.x, want.z],
		wp.x != INF and _xz(wp, want) < 10.0)
	await pframes(30)
	verdict("D3 отходящий не принимает приказ атаки (цель пуста)", _boss.attack_target == null)
	verdict("D4 на отходе лечится (regen): hp растёт", _boss.current_health > _boss.max_health * (_GobCfg.BOSS_WITHDRAW_HP - 0.05))
	_boss.current_health = _boss.max_health * (_GobCfg.BOSS_RETURN_HP + 0.1)
	cmd.tick_now()
	verdict("D5 hp > BOSS_RETURN_HP → возврат в command, отход снят",
		cmd.state_name() == "command" and not _boss.retreating and not _boss.is_withdrawing() and cmd.returns >= 1)
	# Окружение: чужие во всех четырёх секторах — точка выхода через самый свободный
	var ring: Array = []
	for i in range(4):
		var d: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][i]
		var cnt: int = 1 if i == 3 else 4
		for k in range(cnt):
			var u: Unit = _spawn("spearman", F, _boss.global_position + d * (_GobCfg.BOSS_ESCAPE_R + float(k) * 1.5))
			u.set_tick(false)
			ring.append(u)
	await pframes(2)
	_boss.current_health = _boss.max_health * 0.1
	cmd.tick_now()
	var wp2: Vector3 = cmd._withdraw_point
	var esc_dir := Vector3(wp2.x - _boss.global_position.x, 0.0, wp2.z - _boss.global_position.z).normalized()
	verdict("D6 в окружении уходит через самый свободный сектор (−Z): направление (%.2f, %.2f)" % [esc_dir.x, esc_dir.z],
		cmd.state_name() == "withdraw" and esc_dir.z < -0.7)
	_kill(ring)
	_boss.current_health = _boss.max_health
	cmd.tick_now()
	_Opt.boss_withdraw = false
	_boss.current_health = _boss.max_health * 0.1
	cmd.tick_now()
	verdict("D7 ручка boss_withdraw=false: отхода нет (%s)" % cmd.state_name(), cmd.state_name() != "withdraw" and not _boss.retreating)
	_Opt.boss_withdraw = true
	_boss.current_health = _boss.max_health
	gai.waves.erase(w)
	_kill(_members(sid))
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _e_brain() -> void:
	print("\n═════ E. МОЗГ: ПРИКАЗЫ ПАЧКОЙ ═════")
	var cmd = main.pig_boss_cmd
	var gai = main.goblin_ai
	var sid: int = _spawn_boss(_base)
	await pframes(2)
	if _boss == null:
		verdict("E0 босс для блока E", false)
		return
	_freeze(_members(sid))
	var dir := Vector3(0.0, 0.0, 1.0)
	var inf: Array = _squad("goblin_spearman", GF, _base + Vector3(-12.0, 0.0, 0.0), 20, 5, 1.2)
	var cav: Array = _squad("goblin_rider", GF, _base + Vector3(12.0, 0.0, 0.0), 10, 5, 1.6)
	var big: Array = _squad("big_goblin", GF, _base + Vector3(0.0, 0.0, -8.0), 3, 3, 3.0)
	for s in [inf, cav, big]:
		_freeze(s[1])
	# Чужие: слабый отряд (штат 30, живых 8) перед фронтом, плотная линия лучников правее
	var weak: Array = _squad("spearman", F, _base + dir * 32.0, 8, 4, 1.2)
	GameManager.squads[int(weak[0])]["full"] = 30
	var line: Array = _squad("archer", F, _base + dir * 30.0 + Vector3(20.0, 0.0, 0.0), 16, 8, 1.5)
	_freeze(weak[1])
	_freeze(line[1])
	await pframes(3)
	var w: Dictionary = _fake_wave([sid, int(inf[0]), int(cav[0]), int(big[0])], _base + dir * 40.0, dir)
	gai.waves.append(w)
	var oq0: int = gai._oq.size()
	var issued0: int = gai.orders_issued
	cmd.tick_now()
	verdict("E1 мозг работает по волне в engage: состояние %s, приказов в очередь %d" % [cmd.state_name(), cmd.orders_batched],
		cmd.state_name() == "command" and cmd.orders_batched >= 2)
	verdict("E2 ось чужого фронта найдена: (%.2f, %.2f)" % [cmd.last_axis.x, cmd.last_axis.z], cmd.last_axis != Vector3.ZERO)
	verdict("E3 плотность — не больше 10 вызовов enemy_count за такт (%d)" % cmd.density_calls, cmd.density_calls <= 10)
	var kinds: Dictionary = {}
	for o in gai._oq:
		kinds[int((o as Dictionary)["sid"])] = String((o as Dictionary)["k"])
	verdict("E4 конница — марш на фланг (move), пехота — добить слабый отряд (pairs): %s" % str(kinds),
		kinds.get(int(cav[0]), "") == "move" and kinds.get(int(inf[0]), "") == "pairs"
		and cmd.orders_cav >= 1 and cmd.orders_inf >= 1)
	verdict("E5 приказы лежат в очереди орды, а не розданы напрямую (очередь %d → %d, выдано %d)" % [oq0, gai._oq.size(), gai.orders_issued - issued0],
		gai._oq.size() > oq0 and gai.orders_issued == issued0)
	gai._drain_orders()
	var moving := 0
	for u in cav[1]:
		if (u as Unit).state == Unit.State.MOVING:
			moving += 1
	verdict("E6 после _drain_orders всадники идут на фланг: MOVING %d из %d" % [moving, cav[1].size()], moving >= cav[1].size() - 1)
	var before: int = cmd.orders_batched
	cmd.tick_now()
	verdict("E7 повтор не чаще BOSS_REISSUE_SEC: второй такт не добавил приказов (%d = %d)" % [cmd.orders_batched, before], cmd.orders_batched == before)
	# Отряд в бою приказов не получает
	cmd._last_issue.clear()
	var foe: Unit = weak[1][0]
	(inf[1][0] as Unit).command_attack(foe, true, false)
	GameManager.squad_mark_hit(int(inf[0]), foe)
	before = cmd.orders_inf
	cmd.tick_now()
	verdict("E8 отряд в бою (squad_in_combat) переприказов не получает (%d = %d)" % [cmd.orders_inf, before],
		GameManager.squad_in_combat(int(inf[0])) and cmd.orders_inf == before)
	# Клич по решению: чужих в ауре ≥ BOSS_SCREECH_MIN_FOES
	_boss._cry_ready_ms = 0
	var pack: Array = _squad("spearman", F, _boss.global_position + Vector3(0.0, 0.0, 15.0), _GobCfg.BOSS_SCREECH_MIN_FOES + 2, 6, 1.2)
	_freeze(pack[1])
	await pframes(3)
	cmd.tick_now()
	verdict("E9 клич по решению мозга при %d чужих в ауре (screeches=%d)" % [GameManager.army.enemy_count(_boss.global_position.x, _boss.global_position.z, _GobCfg.BOSS_AURA_R, GF), cmd.screeches],
		cmd.screeches >= 1 and _boss.screeches >= 1)
	cmd._last_issue.clear()
	before = cmd.orders_batched
	_Opt.pig_boss = false
	cmd.tick_now()
	_Opt.pig_boss = true
	verdict("E10 ручка pig_boss=false: мозг молчит (%d = %d)" % [cmd.orders_batched, before], cmd.orders_batched == before)
	gai.waves.erase(w)
	for s in [inf, cav, big, weak, line, pack]:
		_kill(s[1])
	_kill(_members(sid))
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _f_integration() -> void:
	print("\n═════ F. ИНТЕГРАЦИЯ ═════")
	verdict("F1 PRELOAD_SCENES знает pig_boss (иначе босс пропадает при загрузке)", Building.PRELOAD_SCENES.has("pig_boss"))
	verdict("F2 HUD: иконка и название", HUD.UNIT_ICONS.has("pig_boss") and HUD.UNIT_TITLES.has("pig_boss"))
	verdict("F3 цена и штат отряда босса в spawn_config", _Spawn.SQUAD_PRICE.has("pig_boss") and int(_Spawn.GOBLIN_SQUAD_SIZE.get("pig_boss", 0)) >= 2)
	verdict("F4 волна полководца в WAVE_TEMPLATES содержит pig_boss", (_Spawn.WAVE_TEMPLATES.get("boss", []) as Array).has("pig_boss"))
	var sid: int = _spawn_boss(_base)
	await pframes(2)
	var rows: Array = _Save._capture_squads()
	var found := false
	for r in rows:
		if int((r as Dictionary)["id"]) == sid and bool((r as Dictionary).get("boss", false)):
			found = true
	verdict("F5 слепок отряда несёт признак boss", found)
	var map: Dictionary = _Save._restore_squads([{"id": 777, "faction": GF, "type": "pig_boss", "kills": 0, "level": 4, "pending": 0, "chosen": [], "bonuses": {}, "abilities": [], "boss": true}])
	var nsid: int = int(map.get(777, 0))
	verdict("F6 восстановленный отряд получает признак boss", nsid > 0 and bool(GameManager.squads[nsid].get("boss", false)))
	if nsid > 0:
		GameManager.squads.erase(nsid)
	_kill(_members(sid))
	await pframes(3)
