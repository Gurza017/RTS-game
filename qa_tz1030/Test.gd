extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tz1030 — СВИНОБОСС ПО РАЗБОРУ ПАРТИЙ 29-30.10.2026 (ТЗ 30.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ВЫЛАЗКИ  — отряд босса не засыпает на площадке сбора (_sleep_squad),
##                свободный босс уходит с любой волной (_launch), цель волны с
##                боссом — брод или рудник (_boss_scenario), без волны мозг
##                встаёт в идущую или через BOSS_IDLE_SORTIE_SEC выводит
##                вылазку; ручка boss_sortie.
##   B ТАРАН    — доля BOSS_RAM_SURVIVE_SHARE растоптанных жива с запасом
##                <= BOSS_RAM_SURVIVE_HP, бег в ядре — ход (MOVING), свита,
##                бегущая сквозь босса, его не выталкивает, бег не дольше
##                BOSS_RAM_RUN_MAX_SEC; ручка boss_ram_survive.
##   C РЫВКИ    — в окружении после тарана босс пробегает дальше тем же курсом
##                (без гибели), в конце боя выходит насквозь; ручка boss_surge.
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_tz1030/Test.tscn [-- only=abc]

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")

var main = null
var cmd = null
var gai = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _base: Vector3 = Vector3.ZERO
var _boss = null
var _boss_sid: int = 0
var _only: String = "abc"

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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_tz1030: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

## Строй: колонки по X, ряды по +Z от точки at
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
			for d in [Vector3.ZERO, Vector3(30.0, 0.0, 0.0), Vector3(-30.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 30.0), Vector3(0.0, 0.0, -30.0)]:
				var q: Vector3 = p + (d as Vector3)
				h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
				if GameManager.is_water(q.x, q.z) or GameManager.is_cliff(q.x, q.z) \
						or not GameManager.is_passable(q.x, q.z):
					h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

func _spacing() -> float:
	var probe_b := Building.new()
	var spc: float = probe_b.squad_spacing
	probe_b.free()
	return spc

func _run() -> void:
	# Босс и отряды ставятся на точку стенда: вход орды из-за кромки (ТЗ
	# 31.10.2026, стережёт qa_tz1031c) увёл бы их к краю карты
	_Opt.horde_edge_entry = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	gai = main.get("goblin_ai")
	if gai != null:
		gai.set_process(false)
	if main.get("cav_commander") != null:
		main.cav_commander.set_process(false)
	cmd = main.get("pig_boss_cmd")
	if cmd != null:
		cmd.set_process(false)
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
	main._clear_area_of_resources(_base, 70.0)
	await pframes(6)
	print("  площадка (%.0f, %.0f)" % [_base.x, _base.z])
	GameManager.pig_boss_fallen = false
	_boss_sid = int(main.spawn_boss_squad(_base + Vector3(0.0, 0.0, -14.0)))
	for m in _members(_boss_sid):
		if (m as Unit).is_pig_boss():
			_boss = m
	verdict("0 отряд босса есть", _boss != null)
	if _boss == null:
		_finish()
		return
	_immortal(_boss)
	if "a" in _only:
		await _a_sortie()
	if "b" in _only:
		await _b_ram()
	if "c" in _only:
		await _c_surge()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ВЫЛАЗКИ ПОЛКОВОДЦА
# ═════════════════════════════════════════════════════════════════════════════
func _boss_in_wave() -> Dictionary:
	for w in gai.waves:
		if ((w as Dictionary)["sids"] as Array).has(_boss_sid):
			return w
	return {}

func _a_sortie() -> void:
	print("\n═════ A. ВЫЛАЗКИ ПОЛКОВОДЦА ═════")
	gai.waves.clear()
	gai._ready_q.clear()
	gai._plan = {}
	# A1. Площадка сбора: «дошёл или 60 с» — спать; полководец не спит
	gai._sleep_squad(_boss_sid)
	var asleep: bool = _boss.dormant
	verdict("A1 _sleep_squad: отряд босса не засыпает (dormant %s)" % str(asleep), not asleep)
	_Opt.boss_sortie = false
	gai._sleep_squad(_boss_sid)
	var asleep0: bool = _boss.dormant
	_Opt.boss_sortie = true
	gai._wake_squad(_boss_sid)
	verdict("A1б ручка boss_sortie=false: прежний сон на площадке (dormant %s)" % str(asleep0), asleep0)
	# A2. Свободный полководец уходит с любой волной
	verdict("A2 boss_free_sid без волны = отряд босса (%d)" % int(gai.boss_free_sid()),
		int(gai.boss_free_sid()) == _boss_sid)
	var gs: Array = _squad("goblin_spearman", GF, _base + Vector3(-30.0, 0.0, -30.0), 12, 4, 1.0)
	var gsid: int = int(gs[0])
	gai._launch("raid", [gsid])
	var w: Dictionary = _boss_in_wave()
	var goals: Array = ["ford_assault", "player_mine", "red_mine"]
	verdict("A3 волна из одного отряда пехоты взяла босса, цель — брод или рудник (%s)" % String(w.get("name", "—")),
		not w.is_empty() and goals.has(String(w.get("name", ""))))
	var gname1: String = String(w.get("name", ""))
	# A4. Две волны подряд — разные ключевые цели (брод ↔ рудник), если обе есть
	gai.waves.clear()
	gai._launch("raid", [gsid])
	var w2: Dictionary = _boss_in_wave()
	var have_both: bool = main.has_method("ford_point") and (gai._mine_of(F) != null
		or gai._mine_of(Constants.FACTION_ENEMY) != null)
	verdict("A4 вторая волна — другая цель при равной обороне (%s → %s)" % [gname1, String(w2.get("name", "—"))],
		not w2.is_empty() and (not have_both or String(w2.get("name", "")) != gname1),
		"цели по счёту: %s" % str(gai.boss_goals))
	# A5. Без волны: в идущую волну встать
	(w2["sids"] as Array).erase(_boss_sid)
	var j0: int = int(cmd.idle_joins)
	cmd.tick_now()
	verdict("A5 босс без волны встаёт в идущую (march): входов %d → %d" % [j0, int(cmd.idle_joins)],
		int(cmd.idle_joins) == j0 + 1 and ((w2["sids"] as Array).has(_boss_sid)))
	# A6. Нет волны вовсе — вылазка через BOSS_IDLE_SORTIE_SEC
	gai.waves.clear()
	var s0: int = int(cmd.sorties)
	cmd.tick_now()
	var early: bool = not _boss_in_wave().is_empty()
	cmd._idle_since = float(Unit.game_ms()) * 0.001 - _GobCfg.BOSS_IDLE_SORTIE_SEC - 1.0
	cmd.tick_now()
	var w3: Dictionary = _boss_in_wave()
	verdict("A6 простой %.0f с — вылазка (до срока — нет: %s; вылазок %d → %d, цель %s)" % [
		_GobCfg.BOSS_IDLE_SORTIE_SEC, str(not early), s0, int(cmd.sorties), String(w3.get("name", "—"))],
		not early and int(cmd.sorties) == s0 + 1 and not w3.is_empty() and goals.has(String(w3.get("name", ""))))
	# A7. Ручка снята — ни волны с собой, ни вылазки
	gai.waves.clear()
	_Opt.boss_sortie = false
	gai._launch("raid", [gsid])
	var w4: Dictionary = _boss_in_wave()
	gai.waves.clear()
	cmd._idle_since = float(Unit.game_ms()) * 0.001 - _GobCfg.BOSS_IDLE_SORTIE_SEC - 1.0
	var s1: int = int(cmd.sorties)
	cmd.tick_now()
	_Opt.boss_sortie = true
	verdict("A7 ручка boss_sortie=false: волна без босса (%s), вылазок нет (%d → %d)" % [
		str(w4.is_empty()), s1, int(cmd.sorties)],
		w4.is_empty() and int(cmd.sorties) == s1 and _boss_in_wave().is_empty())
	gai.waves.clear()
	_kill(gs[1])
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# B. ТАРАН: ВЫЖИВШИЕ, ХОД В ЯДРЕ, СВИТА НЕ ВЫТАЛКИВАЕТ
# ═════════════════════════════════════════════════════════════════════════════
## Босс у точки from, строй 10×rows фронтом к нему; таран целиком. Возвращает
## {tsid, men, run_frames, moving_frames, hp0}
func _one_ram(from: Vector3, rows: int, retinue_rush: bool) -> Dictionary:
	_boss.global_position = Vector3(from.x, GameManager.get_terrain_height(from.x, from.z), from.z)
	_boss.sync_row()
	_boss._ram_ready_ms = 0
	_boss._brawl_until_ms = 0
	var spc: float = _spacing()
	var sp: Array = _squad("spearman", F, from + Vector3(0.0, 0.0, 22.0), 10 * rows, 10, spc)
	for u in sp[1]:
		(u as Unit)._facing = Vector3(0.0, 0.0, -1.0)
		(u as Unit).set_stance("defense")
	await pframes(10)
	var ok: bool = _boss.ram_begin(int(sp[0]))
	var run_f := 0
	var mov_f := 0
	var f := 0
	var rushed := false
	while f < 900 and _boss.ram_phase() != _boss.RAM_NONE:
		await pframes(1)
		f += 1
		if _boss.ram_phase() == _boss.RAM_RUN and _boss._surge == 0:
			run_f += 1
			if GameManager.army.state_of(_boss._soa) == Unit.State.MOVING:
				mov_f += 1
			# Свита бегом сквозь босса за спину — как приказ «в прорыв»
			if retinue_rush and not rushed:
				rushed = true
				var goal: Vector3 = _boss.global_position + _boss._ram_dir * 30.0
				for m in _members(_boss_sid):
					if m != _boss:
						(m as Unit).set_tick(true)
						(m as Unit).global_position = _boss.global_position - _boss._ram_dir * 1.5 \
							+ Vector3(randf_range(-1.0, 1.0), 0.0, 0.0)
						(m as Unit).sync_row()
						(m as Unit).command_move(goal, true)
	return {"ok": ok, "tsid": int(sp[0]), "men": sp[1], "run_frames": run_f, "moving_frames": mov_f}

func _b_ram() -> void:
	print("\n═════ B. ТАРАН: ВЫЖИВШИЕ И ХОД ═════")
	var surge0: bool = _Opt.boss_surge
	_Opt.boss_surge = false
	var from: Vector3 = _base + Vector3(0.0, 0.0, -14.0)
	var r: Dictionary = await _one_ram(from, 5, true)
	var men: Array = r["men"]
	var hurt := 0
	var bad := 0
	for u in men:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		if _boss._ram_hit.has((u as Unit).get_instance_id()):
			var fr: float = (u as Unit).current_health / (u as Unit).max_health
			if fr <= _GobCfg.BOSS_RAM_SURVIVE_HP + 0.01:
				hurt += 1
	var tr: int = _boss.ram_trampled
	var sv: int = _boss.ram_survived
	print("    таран: конец «%s» на %.2f из %.2f м; растоптано %d, выжило %d, раздавлено %d, раскидано %d" % [
		_boss.ram_end_reason, _boss.ram_end_along, _boss._ram_stop_along, tr, sv, _boss.ram_kills, _boss.ram_flung])
	verdict("B1 из растоптанных живы около %.0f %%: %d из %d" % [_GobCfg.BOSS_RAM_SURVIVE_SHARE * 100.0, sv, tr],
		bool(r["ok"]) and tr >= 2 and absf(float(sv) - float(tr) * _GobCfg.BOSS_RAM_SURVIVE_SHARE) <= 1.0)
	verdict("B2 выжившие — с запасом <= %.0f %% (таких среди задетых %d, выживших %d)" % [
		_GobCfg.BOSS_RAM_SURVIVE_HP * 100.0, hurt, sv], hurt >= sv and sv >= 1)
	var run_sec: float = float(int(r["run_frames"])) / float(Engine.physics_ticks_per_second)
	verdict("B3 бег — ход в ядре: MOVING %d из %d кадров" % [int(r["moving_frames"]), int(r["run_frames"])],
		int(r["run_frames"]) > 0 and int(r["moving_frames"]) * 10 >= int(r["run_frames"]) * 9)
	verdict("B4 свита бегом сквозь босса его не выталкивает: бег %.2f с (<= %.1f), дошёл до стопа (%.2f из %.2f м), причина «%s»" % [
		run_sec, _GobCfg.BOSS_RAM_RUN_MAX_SEC, _boss.ram_end_along, _boss._ram_stop_along, _boss.ram_end_reason],
		run_sec <= _GobCfg.BOSS_RAM_RUN_MAX_SEC + 0.1 and _boss.ram_end_reason != "timeout"
		and _boss.ram_end_along >= _boss._ram_stop_along - 0.3)
	# B5. Срок бега: недостижимый стоп — конец по сроку
	_kill(men)
	await pframes(10)
	_boss._ram_ready_ms = 0
	var sp2: Array = _squad("spearman", F, from + Vector3(0.0, 0.0, 40.0), 10, 10, _spacing())
	await pframes(5)
	var began: bool = _boss.ram_begin(int(sp2[0]))
	print("    B5: ram_begin %s (фаза %d, отступает %s, готов через %.1f с)" % [str(began), _boss.ram_phase(),
		str(_boss._withdrawing), _boss.ram_ready_in()])
	var f := 0
	while f < 600 and _boss.ram_phase() != _boss.RAM_RUN:
		await pframes(1)
		f += 1
	_boss._ram_stop_along = 1e6
	_boss._ram_breach_along = 1e6
	var t0: int = Unit.game_ms()
	var to0: int = _boss.ram_timeouts
	while f < 1200 and _boss.ram_phase() != _boss.RAM_NONE:
		await pframes(1)
		f += 1
	var dt: float = float(Unit.game_ms() - t0) * 0.001
	verdict("B5 бег без стопа кончается по сроку: %.2f с (срок %.1f), причина «%s»" % [
		dt, _GobCfg.BOSS_RAM_RUN_MAX_SEC, _boss.ram_end_reason],
		_boss.ram_end_reason == "timeout" and _boss.ram_timeouts == to0 + 1
		and dt <= _GobCfg.BOSS_RAM_RUN_MAX_SEC + 0.2)
	_kill(sp2[1])
	await pframes(10)
	# B6. Ручка снята — все растоптанные гибнут
	_Opt.boss_ram_survive = false
	var r0: Dictionary = await _one_ram(from, 5, false)
	_Opt.boss_ram_survive = true
	verdict("B6 ручка boss_ram_survive=false: выживших нет (растоптано %d, раздавлено %d)" % [
		_boss.ram_trampled, _boss.ram_kills],
		_boss.ram_survived == 0 and _boss.ram_kills >= 2)
	_kill(r0["men"])
	for m in _members(_boss_sid):
		if m != _boss:
			(m as Unit).set_tick(false)
	_Opt.boss_surge = surge0
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# C. РЫВКИ ПОСЛЕ ТАРАНА И ВЫХОД НАСКВОЗЬ
# ═════════════════════════════════════════════════════════════════════════════
func _c_surge() -> void:
	print("\n═════ C. РЫВКИ И ВЫХОД ═════")
	var from: Vector3 = _base + Vector3(0.0, 0.0, -14.0)
	var r: Dictionary = await _one_ram(from, 10, false)
	var origin: Vector3 = _boss._ram_origin
	var dir: Vector3 = _boss._ram_dir
	var end_al: float = _boss.ram_end_along
	var kills0: int = _boss.ram_kills
	var s0: int = _boss.surges
	var e0: int = _boss.surge_exits
	# Бой после тарана; срок боя ужат, чтобы выход наступил в пределах стенда
	_boss._brawl_until_ms = Unit.game_ms() + int((_GobCfg.BOSS_SURGE_FIRST_SEC + _GobCfg.BOSS_SURGE_EVERY_SEC + 2.0) * 1000.0)
	var f := 0
	var cap: int = int((_GobCfg.BOSS_SURGE_FIRST_SEC + _GobCfg.BOSS_SURGE_EVERY_SEC + 8.0) * float(Engine.physics_ticks_per_second))
	var al_mid: float = end_al
	while f < cap and (_boss.surge_exits == e0 or _boss.ram_phase() != _boss.RAM_NONE):
		await pframes(1)
		f += 1
		if _boss.surge_exits == e0:
			var p: Vector3 = _boss.global_position - origin
			al_mid = maxf(al_mid, p.x * dir.x + p.z * dir.z)
	var p2: Vector3 = _boss.global_position - origin
	var al_end: float = p2.x * dir.x + p2.z * dir.z
	print("    конец тарана %.2f м, после рывков %.2f, после выхода %.2f; рывков %d, выходов %d, задето рывками %d" % [
		end_al, al_mid, al_end, _boss.surges - s0, _boss.surge_exits - e0, _boss.surge_hits])
	verdict("C1 в окружении — рывок дальше тем же курсом: рывков %d, прошёл %.2f м (нужно >= %.1f)" % [
		_boss.surges - s0, al_mid - end_al, _GobCfg.BOSS_SURGE_DIST * 0.6],
		_boss.surges > s0 and al_mid - end_al >= _GobCfg.BOSS_SURGE_DIST * 0.6)
	verdict("C2 рывки не убивают полосой: раздавлено %d → %d" % [kills0, _boss.ram_kills], _boss.ram_kills == kills0)
	verdict("C3 конец боя — выход насквозь: выходов %d, ещё %.2f м (нужно >= %.1f), стоит без бега" % [
		_boss.surge_exits - e0, al_end - al_mid, _GobCfg.BOSS_SURGE_EXIT_DIST * 0.6],
		_boss.surge_exits == e0 + 1 and al_end - al_mid >= _GobCfg.BOSS_SURGE_EXIT_DIST * 0.6
		and _boss.ram_phase() == _boss.RAM_NONE)
	_kill(r["men"])
	await pframes(10)
	# C4. Ручка снята — ни рывков, ни выхода
	_Opt.boss_surge = false
	var r0: Dictionary = await _one_ram(from, 10, false)
	var s1: int = _boss.surges
	var e1: int = _boss.surge_exits
	_boss._brawl_until_ms = Unit.game_ms() + int((_GobCfg.BOSS_SURGE_FIRST_SEC + _GobCfg.BOSS_SURGE_EVERY_SEC + 2.0) * 1000.0)
	await pframes(cap)
	_Opt.boss_surge = true
	verdict("C4 ручка boss_surge=false: рывков %d, выходов %d" % [_boss.surges - s1, _boss.surge_exits - e1],
		_boss.surges == s1 and _boss.surge_exits == e1)
	_kill(r0["men"])
	await pframes(10)
