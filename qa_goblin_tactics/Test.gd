extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТАКТИЧЕСКИЙ РАЗУМ ГОБЛИНОВ — ШТУРМ БАЗЫ (заказ 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A СБОР НА ДИСТАНЦИИ — орда в фазе охоты останавливается на линии в
##     ASSAULT_STANDOFF м от края базы (вне стрелы, в зоне видимости) и ждёт,
##     пока соберётся, не вступая в бой.
##   B ПРОВОКАТОР — щуп (пеший отряд) идёт на фланг, остальные держат линию;
##     по сроку щуп ОТХОДИТ к линии (режим отхода), затем конница колет тот
##     же фланг и отходит; после PROBE_CYCLES векторов — общий навал.
##   C ОТХОД И ЛЕЧЕНИЕ — запас армии ниже ASSAULT_RETREAT_HP: все отряды в
##     режиме отхода идут в лагерь вне башен, у костров лечатся, восстановившись
##     — новая волна (режим отхода снят).
##   D ДРУГИЕ ПАТТЕРНЫ — веер делит армию на три направления, откатные волны
##     пускают в лоб конницу, а пехоту держат на линии.
##   E МАРШ В ЦЕНТР — тело идёт линией, конный дозор впереди на VANGUARD_LEAD;
##     дозор заметил чужих — армия в штурм точки контакта; бой кончился —
##     марш продолжается.
##   F ОБОРОНА ДЕРЕВНИ — угроза у деревни: пехота держит рубеж у костров и не
##     бежит к врагу, конница заходит с фланга и отходит, раненый отряд уходит
##     к кострам и лечится; угрозы нет — все у костров.
## Часы вожака двигает стенд (clock), ожидания — в физкадрах (правило 11).
## Запуск: godot --headless --path . res://qa_goblin_tactics/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _OptCfg := preload("res://scripts/perf_config.gd")

var main = null
var ai = null
var cmd = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var castle: Castle = null
var g_sids: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с"); _finish())

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
	print("\n═════ ИТОГ qa_goblin_tactics: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

## Один такт вожака: часы вперёд на THINK_INTERVAL, решение, раздача, и ровно
## столько же физкадров, чтобы игровое время совпадало с часами вожака
func think(steps: int = 1) -> void:
	for _s in range(steps):
		ai.clock += _GobCfg.THINK_INTERVAL
		ai.tick()
		var guard := 0
		while ai._order_at < ai._order_queue.size() and guard < 64:
			ai._drain_orders()
			guard += 1
		await pframes(int(_GobCfg.THINK_INTERVAL * 60.0))

func _field() -> Array:
	var out: Array = []
	for s in ai.squads:
		if String((s as Dictionary)["role"]) != ai.ROLE_HEAL and not ((s as Dictionary)["members"] as Array).is_empty():
			out.append(s)
	return out

func _squad_by_sid(sid: int) -> Dictionary:
	for s in ai.squads:
		if int((s as Dictionary)["id"]) == sid:
			return s
	return {}

func _members(sid: int) -> Array:
	var sq: Dictionary = _squad_by_sid(sid)
	var out: Array = []
	if sq.is_empty():
		return out
	for m in sq["members"]:
		if is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _center(sid: int) -> Vector3:
	var live: Array = _members(sid)
	if live.is_empty():
		return Vector3.INF
	return GameManager._centroid_of(live)

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _retreating_share(sid: int) -> float:
	var live: Array = _members(sid)
	if live.is_empty():
		return 0.0
	var n := 0
	for m in live:
		if (m as Unit).retreating:
			n += 1
	return float(n) / float(live.size())

func _all_goblins() -> Array:
	var out: Array = []
	for sid in g_sids:
		out.append_array(_members(int(sid)))
	return out

func _min_dist_to_castle() -> float:
	var best := INF
	for u in _all_goblins():
		best = minf(best, _xz((u as Unit).global_position, castle.global_position))
	return best

func _set_hp_all(frac: float) -> void:
	for u in _all_goblins():
		var un: Unit = u
		un.current_health = un.max_health * frac
		un._soa_push_stats()

func _teleport_squad(sid: int, at: Vector3) -> void:
	var live: Array = _members(sid)
	var n: int = live.size()
	# Паника прошлого блока снимается: паникующий не принимает command_move,
	# и цель прошлого боя пережила бы перенос
	if GameManager.squads.has(sid):
		(GameManager.squads[sid] as Dictionary)["panic_until"] = 0
	for k in range(n):
		var u: Unit = live[k]
		var ho: Vector2 = _GobCfg.horde_offset(k, n, sid)
		var px: float = at.x + ho.x
		var pz: float = at.z + ho.y
		u._panicked = false
		u.end_retreat(true)
		u.command_move(Vector3(px, 0.0, pz))
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()

func _spawn_player_squad(kind: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var men: Array = []
	var scene: PackedScene = Building.PRELOAD_SCENES[kind]
	for i in range(n):
		var u: Unit = scene.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var px: float = at.x + float(i % 10) * 0.6
		var pz: float = at.z + float(i / 10) * 0.6
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		u.set_stance("defense")
		men.append(u)
	return men

func _run() -> void:
	# Деревня орды выключена: стартовая орда в углу карты нам не нужна, армия
	# штурма ставится стендом у чужой базы (тот же приём, что у массовых стендов)
	_OptCfg.goblin_village = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	ai = main.goblin_ai
	if ai == null:
		verdict("A0 вожака нет", false)
		_finish()
		return
	ai.set_process(false)
	# Без деревни вожак не получает setup (его зовёт _spawn_goblin_village) —
	# даём ему сцену и точку деревни сами
	if ai.main == null:
		ai.setup(main, main.goblin_village_center())
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	main.set_process(false)
	await pframes(4)
	cmd = ai.commander

	# ── База игрока: замок и фаланга обороны ─────────────────────────────────
	var cp := Vector3(-90.0, 0.0, -40.0)
	castle = Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(3)
	var defenders: Array = _spawn_player_squad("spearman", cp + Vector3(-3.0, 0.0, 7.0), 20)
	# ── Армия орды: два пеших отряда и конный в 90 м «ниже» базы (+Z) ───────
	var g := cp + Vector3(0.0, 0.0, 90.0)
	g_sids.append(main.spawn_goblin_squad("goblin_spearman", 30, g + Vector3(-10.0, 0.0, 0.0)))
	g_sids.append(main.spawn_goblin_squad("goblin_spearman", 30, g + Vector3(10.0, 0.0, 0.0)))
	g_sids.append(main.spawn_goblin_squad("goblin_rider", 12, g + Vector3(0.0, 0.0, 8.0)))
	await pframes(4)
	ai._awake = true
	ai.phase = ai.PHASE_HUNT
	ai.hunt_target_override = castle.global_position
	cmd.force_pattern = cmd.PAT_PROBE
	var standoff: float = _GobCfg.ASSAULT_STANDOFF

	# ══ A. СБОР НА ДИСТАНЦИИ ══════════════════════════════════════════════════
	print("\n═════ A. СБОР НА ДИСТАНЦИИ ═════")
	await think(1)
	verdict("A1 в фазе охоты командир берёт армию: сбор, паттерн «провокатор»",
		String(cmd.state) == cmd.ST_ASSEMBLE and String(cmd.pattern) == cmd.PAT_PROBE,
		"состояние %s, паттерн %s" % [String(cmd.state), String(cmd.pattern)])
	var line_d: float = _xz(cmd.assembly_pt, castle.global_position)
	verdict("A2 линия сбора в ASSAULT_STANDOFF (%.0f м) от края базы" % standoff,
		absf(line_d - standoff) <= 1.0, "линия в %.1f м" % line_d)
	var min_seen := INF
	var fought := false
	var steps := 0
	# «Без боя» — без КОНТАКТА (squad_engaged): squad_in_combat отвечает «да»
	# уже на приказ атаки, а его щуп получает в тот же такт, что кончает сбор
	while String(cmd.state) == cmd.ST_ASSEMBLE and steps < 40:
		await think(1)
		steps += 1
		min_seen = minf(min_seen, _min_dist_to_castle())
		for sid in g_sids:
			if GameManager.squad_engaged(int(sid)) > 0:
				fought = true
	var army_d: float = _xz(cmd._army_center(_field()), castle.global_position)
	verdict("A3 армия собралась на линии и остановилась (за %d тактов, без боя)" % steps,
		String(cmd.state) != cmd.ST_ASSEMBLE and steps < 40 and not fought
			and absf(army_d - standoff) <= _GobCfg.ASSAULT_ASSEMBLE_RADIUS,
		"центр армии в %.1f м от базы, состояние %s, бой=%s" % [army_d, String(cmd.state), str(fought)])
	verdict("A4 во время сбора ни один гоблин не подходил ближе линии минус радиус сбора",
		min_seen >= standoff - _GobCfg.ASSAULT_ASSEMBLE_RADIUS - 3.0,
		"ближайший подходил на %.1f м" % min_seen)

	# ══ B. ПРОВОКАТОР ═════════════════════════════════════════════════════════
	print("\n═════ B. ХИТРЫЙ ПРОВОКАТОР ═════")
	verdict("B1 после сбора — прощупывание: щуп пеший, укол конный",
		String(cmd.state) == cmd.ST_FEINT and int(cmd.probe_sid) > 0 and int(cmd.probe_cav_sid) > 0
			and GameManager.squad_type(int(cmd.probe_sid)) == "goblin_spearman"
			and GameManager.squad_type(int(cmd.probe_cav_sid)) == "goblin_rider",
		"состояние %s, щуп %d (%s), конница %d (%s)" % [String(cmd.state), int(cmd.probe_sid),
			GameManager.squad_type(int(cmd.probe_sid)), int(cmd.probe_cav_sid),
			GameManager.squad_type(int(cmd.probe_cav_sid))])
	var probe: int = int(cmd.probe_sid)
	var side: int = int(cmd._probe_side)
	var fp: Vector3 = cmd.flank_point(side)
	var d0: float = _xz(_center(probe), fp)
	var line_sid := 0
	for sid in g_sids:
		if int(sid) != probe and int(sid) != int(cmd.probe_cav_sid):
			line_sid = int(sid)
	var field: Array = _field()
	var line_idx := 0
	for i in range(field.size()):
		if int((field[i] as Dictionary)["id"]) == line_sid:
			line_idx = i
	var line_slot: Vector3 = cmd.assembly_slot(line_idx, field.size())
	await think(2)
	var d1: float = _xz(_center(probe), fp)
	var held: float = _xz(_center(line_sid), line_slot)
	verdict("B2 щуп идёт на фланг (сдвиг поперёк оси %.0f м), остальная пехота держит линию" % _GobCfg.PROBE_FLANK_OFFSET,
		d0 - d1 >= 4.0 and held <= _GobCfg.ASSAULT_ASSEMBLE_RADIUS + 3.0 and side != 0,
		"щуп к флангу %.1f → %.1f м, линия держится в %.1f м от места" % [d0, d1, held])
	# Дожидаемся конца срока щупа — он обязан отойти к линии в режиме отхода
	var phase_seen: Array = []
	var back_share := 0.0
	var back_d0 := INF
	var back_d1 := INF
	steps = 0
	while steps < 12 and String(cmd._probe_phase) == "infantry":
		await think(1)
		steps += 1
	if String(cmd._probe_phase) == "infantry_back":
		back_share = _retreating_share(probe)
		var slot_p: Vector3 = cmd.assembly_slot(_field().find(_squad_by_sid(probe)), _field().size())
		back_d0 = _xz(_center(probe), slot_p)
		await think(2)
		back_d1 = _xz(_center(probe), slot_p)
	verdict("B3 по сроку щуп отходит к линии в режиме отхода",
		back_share >= 0.6 and back_d1 < back_d0 - 2.0,
		"в отходе %.0f %%, до места на линии %.1f → %.1f м" % [back_share * 100.0, back_d0, back_d1])
	# Конница: укол в тот же фланг и отход
	var cav: int = int(cmd.probe_cav_sid)
	var cav_hit := false
	var cav_back := false
	steps = 0
	while steps < 20 and not cav_back:
		await think(1)
		steps += 1
		var ph: String = String(cmd._probe_phase)
		if not phase_seen.has(ph):
			phase_seen.append(ph)
		if ph == "cavalry":
			var kind: String = String((cmd._ordered.get(cav, {}) as Dictionary).get("kind", ""))
			if kind == "attack" or kind == "move":
				cav_hit = true
		if ph == "cavalry_back" and _retreating_share(cav) >= 0.6:
			cav_back = true
	verdict("B4 после щупа конница колет тот же фланг и мгновенно отходит",
		cav_hit and cav_back, "фазы %s" % str(phase_seen))
	# Второй вектор и общий навал
	steps = 0
	while steps < 40 and String(cmd.state) == cmd.ST_FEINT:
		await think(1)
		steps += 1
		var ph2: String = String(cmd._probe_phase)
		if not phase_seen.has(ph2):
			phase_seen.append(ph2)
	verdict("B5 после %d векторов — общий навал в слабое место" % _GobCfg.PROBE_CYCLES,
		String(cmd.state) == cmd.ST_CHARGE and int(cmd._probe_cycle) >= _GobCfg.PROBE_CYCLES,
		"состояние %s, векторов %d, сторона навала %d" % [String(cmd.state), int(cmd._probe_cycle), int(cmd.weak_side)])
	await think(1)
	var attacking := 0
	for sid in g_sids:
		var kind2: String = String((cmd._ordered.get(int(sid), {}) as Dictionary).get("kind", ""))
		if kind2 == "attack" or GameManager.squad_in_combat(int(sid)):
			attacking += 1
	verdict("B6 в навале приказ атаки получили все отряды", attacking == g_sids.size(),
		"в атаке %d из %d" % [attacking, g_sids.size()])

	# ══ C. ОТХОД И ЛЕЧЕНИЕ ════════════════════════════════════════════════════
	print("\n═════ C. ОТХОД И ЛЕЧЕНИЕ ═════")
	_set_hp_all(0.3)
	await think(1)
	verdict("C1 запас армии ниже %.0f %% — состояние «отход и лечение»" % (_GobCfg.ASSAULT_RETREAT_HP * 100.0),
		String(cmd.state) == cmd.ST_RETREAT and float(cmd.hp_frac) <= _GobCfg.ASSAULT_RETREAT_HP,
		"состояние %s, запас %.0f %%" % [String(cmd.state), float(cmd.hp_frac) * 100.0])
	await think(1)
	var ret_share := 0.0
	for sid in g_sids:
		ret_share += _retreating_share(int(sid))
	ret_share /= float(g_sids.size())
	var camp_d: float = _xz(cmd.camp_pt, castle.global_position)
	verdict("C2 все отряды в режиме отхода, лагерь вне башен (≥ %.0f м от базы)" % _GobCfg.ASSAULT_CAMP_DIST,
		ret_share >= 0.8 and camp_d >= _GobCfg.ASSAULT_CAMP_DIST - 1.0,
		"в отходе %.0f %%, лагерь в %.1f м" % [ret_share * 100.0, camp_d])
	steps = 0
	while steps < 30 and not cmd._at_camp(_field()):
		await think(1)
		steps += 1
	var at_camp: bool = cmd._at_camp(_field())
	var hp_a: float = float(cmd.hp_frac)
	await think(3)
	var hp_b: float = float(cmd.hp_frac)
	verdict("C3 в лагере раны залечиваются (%.0f в секунду у костров)" % _GobCfg.CAMP_HEAL_PER_SEC,
		at_camp and hp_b > hp_a + 0.02,
		"дошли=%s, запас %.0f %% → %.0f %% за 3 такта" % [str(at_camp), hp_a * 100.0, hp_b * 100.0])
	steps = 0
	while steps < 60 and String(cmd.state) == cmd.ST_RETREAT:
		await think(1)
		steps += 1
	var still_retreating := 0
	for u in _all_goblins():
		if (u as Unit).retreating:
			still_retreating += 1
	verdict("C4 восстановившись до %.0f %% — новая волна, режим отхода снят" % (_GobCfg.ASSAULT_REARM_HP * 100.0),
		String(cmd.state) == cmd.ST_ASSEMBLE and int(cmd.waves) == 1 and still_retreating == 0
			and float(cmd.hp_frac) >= _GobCfg.ASSAULT_REARM_HP,
		"состояние %s, волн %d, ещё в отходе %d, запас %.0f %%" % [String(cmd.state), int(cmd.waves),
			still_retreating, float(cmd.hp_frac) * 100.0])

	# ══ D. ДРУГИЕ ПАТТЕРНЫ ════════════════════════════════════════════════════
	print("\n═════ D. ВЕЕР И ОТКАТНЫЕ ВОЛНЫ ═════")
	# Веер: армия на линии, паттерн задан — три направления с каскадом
	cmd.reset()
	cmd.force_pattern = cmd.PAT_FAN
	_set_hp_all(1.0)
	await think(1)
	var f2: Array = _field()
	for i in range(f2.size()):
		_teleport_squad(int((f2[i] as Dictionary)["id"]), cmd.assembly_slot(i, f2.size()))
	await pframes(3)
	await think(1)
	var sides: Array = []
	for sid in g_sids:
		var sd: int = int(cmd._sweep_groups.get(int(sid), 99))
		if not sides.has(sd):
			sides.append(sd)
	verdict("D1 веер: армия разбита на левый фланг, центр и правый фланг",
		String(cmd.state) == cmd.ST_SWEEP and sides.has(-1) and sides.has(0) and sides.has(1),
		"состояние %s, группы %s" % [String(cmd.state), str(sides)])
	# Откатные волны: конница получает атаку, пехота ждёт на линии
	cmd.reset()
	cmd.force_pattern = cmd.PAT_HITRUN
	for i in range(f2.size()):
		_teleport_squad(int((f2[i] as Dictionary)["id"]), cmd.assembly_slot(i, f2.size()))
	await pframes(3)
	await think(1)
	f2 = _field()
	for i in range(f2.size()):
		_teleport_squad(int((f2[i] as Dictionary)["id"]), cmd.assembly_slot(i, f2.size()))
	await pframes(3)
	await think(1)
	var cav_kind := ""
	var inf_kinds: Array = []
	for sid in g_sids:
		var k: String = String((cmd._ordered.get(int(sid), {}) as Dictionary).get("kind", ""))
		if GameManager.squad_type(int(sid)) == "goblin_rider":
			cav_kind = k
		else:
			inf_kinds.append(k)
	verdict("D2 откатные волны: конница бьёт в лоб, пехота держит линию до отката",
		String(cmd.state) == cmd.ST_CHARGE and String(cmd._hr_phase) == "cavalry"
			and cav_kind == "attack" and not inf_kinds.has("attack"),
		"состояние %s, фаза %s, конница «%s», пехота %s" % [String(cmd.state), String(cmd._hr_phase), cav_kind, str(inf_kinds)])

	# ══ E. МАРШ В ЦЕНТР С ДОЗОРОМ ═════════════════════════════════════════════
	print("\n═════ E. МАРШ В ЦЕНТР С ДОЗОРОМ ═════")
	# Оборона базы из блока A снимается: дозор нашёл бы её раньше пикета
	for u in defenders:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e9)
	await pframes(3)
	# Армия в 100 м от центра карты, чужой отряд в 35 м от центра на пути
	var m0 := Vector3(-100.0, 0.0, 0.0)
	f2 = _field()
	for i in range(f2.size()):
		_teleport_squad(int((f2[i] as Dictionary)["id"]), m0 + Vector3(0.0, 0.0, float(i - 1) * 10.0))
	_set_hp_all(1.0)
	var picket: Array = _spawn_player_squad("spearman", Vector3(-35.0, 0.0, -2.0), 12)
	await pframes(3)
	ai.phase = ai.PHASE_CENTER
	await think(1)
	var van: int = int(cmd.vanguard_sid)
	var van_goal: Vector3 = Vector3((cmd._ordered.get(van, {}) as Dictionary).get("goal", Vector3.INF))
	var body_goal_x := -INF
	for sid in g_sids:
		if int(sid) != van:
			var gg: Vector3 = Vector3((cmd._ordered.get(int(sid), {}) as Dictionary).get("goal", Vector3.INF))
			body_goal_x = maxf(body_goal_x, gg.x)
	verdict("E1 в фазе центра — марш: дозор конный, его цель впереди тела по оси",
		String(cmd.mode) == cmd.MODE_ADVANCE and String(cmd.state) == cmd.ST_ADVANCE
			and GameManager.squad_type(van) == "goblin_rider" and van_goal != Vector3.INF
			and van_goal.x > m0.x + _GobCfg.VANGUARD_LEAD * 0.7 and body_goal_x >= -1.0,
		"режим %s, состояние %s, дозор %d (%s), цель дозора x=%.0f, тело идёт к x=%.0f" % [String(cmd.mode),
			String(cmd.state), van, GameManager.squad_type(van), van_goal.x, body_goal_x])
	await think(3)
	var van_c: Vector3 = _center(van)
	var inf_x := -INF
	for sid in g_sids:
		if int(sid) != van:
			inf_x = maxf(inf_x, _center(int(sid)).x)
	verdict("E2 через три такта дозор идёт впереди пехоты",
		van_c.x > inf_x + 5.0, "дозор x=%.1f, пехота x=%.1f" % [van_c.x, inf_x])
	steps = 0
	while steps < 25 and String(cmd.state) == cmd.ST_ADVANCE:
		await think(1)
		steps += 1
	var charged: bool = String(cmd.state) == cmd.ST_CHARGE
	var contact_d: float = _xz(cmd.contact_pt, Vector3(-35.0, 0.0, -2.0)) if cmd.contact_pt != Vector3.INF else INF
	await think(1)
	var atk := 0
	for sid in g_sids:
		var k3: String = String((cmd._ordered.get(int(sid), {}) as Dictionary).get("kind", ""))
		if k3 == "attack" or GameManager.squad_in_combat(int(sid)):
			atk += 1
	verdict("E3 дозор заметил чужих — армия в штурм точки контакта (за %d тактов)" % steps,
		charged and contact_d <= 8.0 and atk == g_sids.size(),
		"состояние %s, контакт в %.1f м от чужих, в атаке %d из %d" % [String(cmd.state), contact_d, atk, g_sids.size()])
	# Бой кончился (чужие выбиты) — марш продолжается
	for u in picket:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e9)
	await pframes(3)
	steps = 0
	while steps < 6 and String(cmd.state) != cmd.ST_ADVANCE:
		await think(1)
		steps += 1
	verdict("E4 контакт исчерпан — марш продолжается", String(cmd.state) == cmd.ST_ADVANCE,
		"состояние %s" % String(cmd.state))

	# ══ F. ОБОРОНА ДЕРЕВНИ ════════════════════════════════════════════════════
	print("\n═════ F. ОБОРОНА ДЕРЕВНИ ═════")
	var vil := Vector3(60.0, 0.0, 60.0)
	ai.village = vil
	f2 = _field()
	for i in range(f2.size()):
		_teleport_squad(int((f2[i] as Dictionary)["id"]), vil + Vector3(float(i - 1) * 8.0, 0.0, 0.0))
	_set_hp_all(1.0)
	ai.phase = ai.PHASE_DEFEND
	await think(1)
	verdict("F1 угрозы нет — все у костров",
		String(cmd.mode) == cmd.MODE_DEFENSE and String(cmd.state) == cmd.ST_DEFEND and cmd.threat_pt == Vector3.INF,
		"режим %s, состояние %s" % [String(cmd.mode), String(cmd.state)])
	# Угроза: чужой отряд в 45 м «ниже» деревни
	var tp := vil + Vector3(0.0, 0.0, 45.0)
	var raiders: Array = _spawn_player_squad("spearman", tp, 20)
	await pframes(3)
	await think(1)
	var inf_ok := 0
	var inf_total := 0
	var cav_goal := Vector3.INF
	for sid in g_sids:
		var gd: Dictionary = cmd._ordered.get(int(sid), {})
		var goal_v: Vector3 = Vector3(gd.get("goal", Vector3.INF))
		if GameManager.squad_type(int(sid)) == "goblin_rider":
			cav_goal = goal_v
			continue
		inf_total += 1
		if goal_v != Vector3.INF:
			var dv: float = _xz(goal_v, vil)
			var toward: bool = (goal_v.z - vil.z) > 0.0
			if absf(dv - _GobCfg.DEFEND_LINE_DIST) <= _GobCfg.ASSAULT_LINE_STEP and toward:
				inf_ok += 1
	verdict("F2 угроза замечена: пехота встаёт на рубеж у костров (%.0f м к угрозе), а не бежит к ней" % _GobCfg.DEFEND_LINE_DIST,
		cmd.threat_pt != Vector3.INF and _xz(cmd.threat_pt, tp) <= 6.0 and inf_ok == inf_total and inf_total >= 2,
		"угроза в %.1f м от чужих, на рубеже %d из %d" % [_xz(cmd.threat_pt, tp) if cmd.threat_pt != Vector3.INF else INF, inf_ok, inf_total])
	var lateral: float = absf(cav_goal.x - tp.x) if cav_goal != Vector3.INF else 0.0
	var cav_kind2: String = String((cmd._ordered.get(int(cmd._pick_probe(_field(), true)), {}) as Dictionary).get("kind", ""))
	verdict("F3 конница заходит с фланга угрозы (сдвиг поперёк ≥ %.0f м) и бьёт" % (_GobCfg.DEFEND_CAV_FLANK * 0.7),
		lateral >= _GobCfg.DEFEND_CAV_FLANK * 0.7 and (cav_kind2 == "attack" or cav_kind2 == "move"),
		"сдвиг %.1f м, приказ «%s»" % [lateral, cav_kind2])
	var cav_sid2: int = int(cmd._pick_probe(_field(), true))
	steps = 0
	var cav_back2 := false
	while steps < 10 and not cav_back2:
		await think(1)
		steps += 1
		if String(cmd._def_cav_phase) == "back" and _retreating_share(cav_sid2) >= 0.6:
			cav_back2 = true
	var inf_far := 0.0
	for sid in g_sids:
		if GameManager.squad_type(int(sid)) != "goblin_rider":
			inf_far = maxf(inf_far, _xz(_center(int(sid)), vil))
	verdict("F4 после укола конница отходит к деревне; пехота за рубеж не выбегает",
		cav_back2 and inf_far <= _GobCfg.DEFEND_LINE_DIST + _GobCfg.ASSAULT_LINE_STEP + 3.0,
		"конница в отходе=%s, пехота не дальше %.1f м от деревни" % [str(cav_back2), inf_far])
	# Раненый отряд — к кострам, лечится
	var wsid := 0
	for sid in g_sids:
		if GameManager.squad_type(int(sid)) != "goblin_rider":
			wsid = int(sid)
	for u in _members(wsid):
		(u as Unit).current_health = (u as Unit).max_health * 0.3
		(u as Unit)._soa_push_stats()
	await think(1)
	var w_goal: Vector3 = Vector3((cmd._ordered.get(wsid, {}) as Dictionary).get("goal", Vector3.INF))
	var w_ret: float = _retreating_share(wsid)
	var w_hp0: float = cmd._squad_hp_frac(_squad_by_sid(wsid))
	steps = 0
	while steps < 12 and _xz(_center(wsid), vil) > _GobCfg.CAMP_HEAL_RADIUS * 0.5:
		await think(1)
		steps += 1
	await think(3)
	var w_hp1: float = cmd._squad_hp_frac(_squad_by_sid(wsid))
	verdict("F5 отряд с запасом ниже %.0f %% уходит к кострам и лечится" % (_GobCfg.ASSAULT_RETREAT_HP * 100.0),
		cmd.wounded.has(wsid) and w_goal != Vector3.INF and _xz(w_goal, vil) <= 2.0 and w_ret >= 0.6 and w_hp1 > w_hp0 + 0.02,
		"цель в %.1f м от деревни, в отходе %.0f %%, запас %.0f %% → %.0f %%" % [
			_xz(w_goal, vil) if w_goal != Vector3.INF else INF, w_ret * 100.0, w_hp0 * 100.0, w_hp1 * 100.0])
	for u in raiders:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e9)
	_finish()
