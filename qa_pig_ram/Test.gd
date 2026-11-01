extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_pig_ram — УДАР СВИНОБОССА, ГОРН, ЗОНДЫ ДЛЯ .exe (ТЗ 29.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   R ТАРАН     — мозг выбирает строй копейщиков и свиту всадников, босс
##                 пробивает BOSS_RAM_PIERCE_ROWS ряда (полоса гибели, разлёт
##                 вбок), встаёт перед следующим, бьётся «как тролль»; свита
##                 бегом в прорыв и в атаку отряда-цели; откат BOSS_RAM_CD_SEC;
##                 копья и Стена копий босса не держат; оружие туши; запасные
##                 виды свиты (своя свита → подкрепление); ручка boss_ram.
##   H ГОРН      — отряды орды в ауре рыкают; ручка boss_horn.
##   P ЗОНДЫ     — знамя (banner_pass), отход отряда (squad_retreat), штандарт
##                 (standard_pass), минутная сводка (probe_summary), зонд босса
##                 (boss_ram_*/boss_status); ручки probes_ext, boss_probe.
##   Y ПРОРЫВ    — бегущий босс проходит строй копейщиков насквозь, расталкивая
##                 (ТЗ 31.10.2026); ручка boss_flee_break (Y0 — выключена).
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_pig_ram/Test.tscn [-- knob=…]

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _UStats := preload("res://scripts/unit_stats_config.gd")
const _RCfg := preload("res://scripts/relic_config.gd")

var main = null
var cmd = null
var gai = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _base: Vector3 = Vector3.ZERO
var _boss = null
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
	print("\n═════ ИТОГ qa_pig_ram: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _events(kind: String) -> int:
	var n := 0
	for e in GameManager.tm_events:
		if String((e as Array)[1]) == kind:
			n += 1
	return n

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
	GameManager.probes.print_lines = true
	_base = _flat_spot(Vector3(-40.0, 0.0, -30.0))
	main._clear_area_of_resources(_base, 70.0)
	await pframes(6)
	print("  площадка (%.0f, %.0f)" % [_base.x, _base.z])
	await _r_ram()
	await _h_horn()
	await _r_escort_fallback()
	await _p_probes()
	await _x_rage()
	await _y_flee_break()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# R. ТАРАН
# ═════════════════════════════════════════════════════════════════════════════
func _r_ram() -> void:
	print("\n═════ R. УДАР СВИНОБОССА ═════")
	GameManager.pig_boss_fallen = false
	# Рывки после тарана (ТЗ 30.10, boss_surge) переписали бы _ram_hit и увели
	# босса из боя до вердиктов R8-R13 — их стережёт qa_tz1030 C
	var surge0: bool = _Opt.boss_surge
	_Opt.boss_surge = false
	_boss_sid = int(main.spawn_boss_squad(_base + Vector3(0.0, 0.0, -14.0)))
	for m in _members(_boss_sid):
		if (m as Unit).is_pig_boss():
			_boss = m
	verdict("R0 отряд босса есть", _boss != null)
	if _boss == null:
		return
	# Свиту босса держим на месте: геометрия тарана — только босс и строй
	for m in _members(_boss_sid):
		if m != _boss:
			(m as Unit).set_tick(false)
	_immortal(_boss)
	var bs: Dictionary = _UStats.STATS["big_goblin"]
	verdict("R1 оружие туши: длина %.1f, урон %.0f (STATS big_goblin)" % [_boss.attack_range, _boss.attack_damage],
		is_equal_approx(_boss.attack_range, float(bs["attack_range"]))
		and is_equal_approx(_boss.attack_damage, float(bs["attack_1"])))
	# Строй копейщиков игрока: 10 колонок × 5 рядов со штатным интервалом
	# (Building.squad_spacing), фронтом к боссу
	var probe_b := Building.new()
	var spc: float = probe_b.squad_spacing
	probe_b.free()
	var sp: Array = _squad("spearman", F, _base + Vector3(0.0, 0.0, 8.0), 50, 10, spc)
	var tsid: int = int(sp[0])
	var spear: Array = sp[1]
	for u in spear:
		(u as Unit)._facing = Vector3(0.0, 0.0, -1.0)
		(u as Unit).set_stance("defense")
	# Отряд всадников орды рядом — предпочтительная свита
	var rs: Array = _squad("goblin_rider", GF, _base + Vector3(8.0, 0.0, -20.0), 10, 5, 1.2)
	var esid: int = int(rs[0])
	await pframes(10)
	verdict("R2 таран готов с рождения, иммунитет к копьям", bool(_boss.ram_ready()) and _boss.immune_to_spears())
	cmd.tick_now()
	var ram: Dictionary = cmd.ram
	verdict("R3 мозг начал таран: цель — строй копейщиков, свита — всадники",
		not ram.is_empty() and int(ram.get("target", 0)) == tsid and int(ram.get("escort", 0)) == esid
		and String(ram.get("kind", "")) == "riders" and _boss.ram_phase() == _boss.RAM_PREP,
		"ram=%s, фаза %d" % [str(ram), _boss.ram_phase()])
	verdict("R4 откат тарана взведён BOSS_RAM_CD_SEC по игровым часам: %.0f с" % _boss.ram_ready_in(),
		absf(_boss.ram_ready_in() - _GobCfg.BOSS_RAM_CD_SEC) < 1.0 and not _boss.ram_ready())
	# Снимок строя в момент старта бега (ряды считаются по факту стоящих)
	var snap: Dictionary = {}
	var f := 0
	while f < 600 and _boss.ram_phase() != _boss.RAM_RUN:
		await pframes(1)
		f += 1
		gai._drain_orders()
		if f % 60 == 0:
			cmd.tick_now()
	var origin: Vector3 = _boss._ram_origin
	var dir: Vector3 = _boss._ram_dir
	var side := Vector3(-dir.z, 0.0, dir.x)
	for u in spear:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			var off: Vector3 = (u as Unit).global_position - origin
			snap[(u as Unit).get_instance_id()] = [off.x * dir.x + off.z * dir.z, off.x * side.x + off.z * side.z, u]
	var rows: PackedFloat32Array = _boss.ram_rows
	print("    ряды по ходу: %s" % str(rows))
	verdict("R5 подготовка %.1f с, затем бег; рядов строя в полосе %d (нужно > %d)" % [
		_GobCfg.BOSS_RAM_PREP_SEC, rows.size(), _GobCfg.BOSS_RAM_PIERCE_ROWS],
		_boss.ram_phase() == _boss.RAM_RUN and rows.size() > _GobCfg.BOSS_RAM_PIERCE_ROWS)
	# Бег до конца и свита до приказа атаки
	f = 0
	while f < 900 and (_boss.ram_phase() != _boss.RAM_NONE or not cmd.ram.is_empty()):
		await pframes(1)
		f += 1
		gai._drain_orders()
		if f % 60 == 0:
			cmd.tick_now()
	for _k in range(30):
		gai._drain_orders()
		await pframes(1)
	var pr: int = _GobCfg.BOSS_RAM_PIERCE_ROWS
	print("    конец: %s, по ходу %.2f м; раздавлено %d, раскидано %d" % [
		_boss.ram_end_reason, _boss.ram_end_along, _boss.ram_kills, _boss.ram_flung])
	verdict("R6 таран встал перед рядом №%d: %.2f м (ряд %.2f, стоп за %.1f м), причина «rows»" % [
		pr + 1, _boss.ram_end_along, rows[pr] if rows.size() > pr else -1.0, _GobCfg.BOSS_RAM_STOP_GAP],
		rows.size() > pr and _boss.ram_end_reason == "rows"
		and _boss.ram_end_along < rows[pr] and _boss.ram_end_along > rows[pr - 1])
	verdict("R7 пробиты первые ряды: раздавлено %d (в пределах 1..%d), раскидано вбок %d" % [
		_boss.ram_kills, _GobCfg.BOSS_RAM_KILL_MAX, _boss.ram_flung],
		_boss.ram_kills >= 1 and _boss.ram_kills <= _GobCfg.BOSS_RAM_KILL_MAX and _boss.ram_flung >= 1)
	# Третий ряд и глубже тараном не тронут
	var deep_hit := 0
	var deep_n := 0
	for k in snap:
		var rec: Array = snap[k]
		if rows.size() > pr and float(rec[0]) >= rows[pr] - 0.15:
			deep_n += 1
			if _boss._ram_hit.has(k):
				deep_hit += 1
	verdict("R8 ряд №%d и глубже тараном не задет: %d из %d" % [pr + 1, deep_hit, deep_n],
		deep_n > 0 and deep_hit == 0)
	# Раскиданные ушли вбок от оси
	await pframes(40)
	var moved := 0
	var flung_n := 0
	for k in snap:
		if not _boss._ram_hit.has(k):
			continue
		var rec2: Array = snap[k]
		var u2 = rec2[2]
		if not is_instance_valid(u2) or (u2 as Unit).is_dead():
			continue
		flung_n += 1
		var off2: Vector3 = (u2 as Unit).global_position - origin
		var lat2: float = absf(off2.x * side.x + off2.z * side.z)
		if lat2 > absf(float(rec2[1])) + 1.0:
			moved += 1
	verdict("R9 раскиданные отлетели вбок от оси больше чем на 1 м: %d из %d" % [moved, flung_n],
		flung_n > 0 and moved * 2 >= flung_n)
	verdict("R10 после тарана — бой «как тролль»: brawling, цель есть",
		_boss.brawling() and _boss.attack_target != null and is_instance_valid(_boss.attack_target))
	# Свита: бегом в прорыв и атака отряда-цели
	var att := 0
	var tmen: Array = (GameManager.squads[tsid] as Dictionary)["members"] if GameManager.squads.has(tsid) else []
	for m in _members(esid):
		var t = (m as Unit).attack_target
		if t != null and is_instance_valid(t) and tmen.has(t):
			att += 1
	verdict("R11 свита в прорыве: рывок %d, атака %d; бойцов свиты бьют отряд-цель %d из %d" % [
		cmd.escort_rushes, cmd.escort_attacks, att, _members(esid).size()],
		cmd.escort_rushes >= 1 and cmd.escort_attacks >= 1 and att * 2 >= _members(esid).size())
	# Копья и «Стена копий» босса не держат
	var sp0: Unit = null
	for m in _members(tsid):
		sp0 = m
		break
	if sp0 != null:
		var h0: float = _boss.current_health
		_boss._slow_until_ms = 0
		sp0.spear_wall_strike(_boss)
		verdict("R12 Стена копий не ранит и не тормозит босса (hp %.0f → %.0f, замедлен %s)" % [
			h0, _boss.current_health, _boss.is_slowed()],
			is_equal_approx(h0, _boss.current_health) and not _boss.is_slowed())
	# Повторно до отката — нет
	cmd.tick_now()
	verdict("R13 второго тарана до отката нет", cmd.ram.is_empty() and _boss.ram_phase() == _boss.RAM_NONE)
	# Ручка снята — таран не готов даже без отката
	_boss._ram_ready_ms = 0
	_Opt.boss_ram = false
	verdict("R14 ручка boss_ram=false: таран не готов, иммунитета нет",
		not _boss.ram_ready() and not _boss.immune_to_spears())
	_Opt.boss_ram = true
	_boss._ram_ready_ms = Unit.game_ms() + int(_GobCfg.BOSS_RAM_CD_SEC * 1000.0)
	_Opt.boss_surge = surge0
	verdict("R15 зонд: boss_ram_start / boss_ram_breach / boss_ram_escort в телеметрии (%d/%d/%d)" % [
		_events("boss_ram_start"), _events("boss_ram_breach"), _events("boss_ram_escort")],
		_events("boss_ram_start") >= 1 and _events("boss_ram_breach") >= 1 and _events("boss_ram_escort") >= 1)

# ═════════════════════════════════════════════════════════════════════════════
# H. ГОРН
# ═════════════════════════════════════════════════════════════════════════════
func _h_horn() -> void:
	print("\n═════ H. ГОБЛИНСКИЙ ГОРН ═════")
	if _boss == null:
		return
	var gs: Array = _squad("goblin_spearman", GF, _boss.global_position + Vector3(-6.0, 0.0, -4.0), 8, 4, 0.9)
	await pframes(4)
	_boss._cry_ready_ms = 0
	var ok: bool = _boss.screech()
	var m0: Unit = _members(int(gs[0]))[0]
	verdict("H1 горн: отряды орды в ауре рыкнули (%d), свои ослаблены ×%.2f до конца горна" % [
		_boss.horn_roared, m0._frail_mult],
		ok and _boss.horn_roared >= 1 and m0._frail_until_ms > Unit.game_ms()
		and is_equal_approx(m0._frail_mult, _GobCfg.BOSS_HORN_ALLY_FRAIL_MULT)
		and is_equal_approx(m0._screech_mult, _GobCfg.BOSS_HORN_ALLY_ATK_MULT))

# ═════════════════════════════════════════════════════════════════════════════
# R. СВИТА: ЗАПАСНЫЕ ВИДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _r_escort_fallback() -> void:
	print("\n═════ R. СВИТА: ЗАПАСНЫЕ ВИДЫ ═════")
	if _boss == null:
		return
	var sp: Array = _squad("spearman", F, _base + Vector3(-20.0, 0.0, 10.0), 12, 6, 0.7)
	var tsid: int = int(sp[0])
	# Всадников рядом нет — своя свита босса
	for key in GameManager.squads.keys():
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) == GF and int(key) != _boss_sid:
			_kill(_members(int(key)))
	await pframes(3)
	var p1: Array = cmd._pick_escort(_boss, gai, {}, tsid)
	verdict("R16 нет всадников рядом — свита своя (%s, живых %d)" % [String(p1[1]), cmd._retinue_alive(_boss)],
		String(p1[1]) == "retinue" and int(p1[0]) == _boss_sid)
	# Своей свиты мало — подкрепление всадников
	for m in _members(_boss_sid):
		if m != _boss:
			(m as Unit).take_damage(1e12)
	await pframes(3)
	var r0: int = cmd.reinforcements
	var p2: Array = cmd._pick_escort(_boss, gai, {}, tsid)
	await pframes(3)
	var n2: int = _members(int(p2[0])).size() if int(p2[0]) > 0 else 0
	verdict("R17 ни свиты, ни отрядов рядом — подкрепление всадников (%s, отряд %d, живых %d)" % [
		String(p2[1]), int(p2[0]), n2],
		String(p2[1]) == "reinforce" and n2 > 0 and cmd.reinforcements == r0 + 1
		and String(GameManager.squads[int(p2[0])].get("type", "")) == "goblin_rider")

# ═════════════════════════════════════════════════════════════════════════════
# P. ЗОНДЫ ДЛЯ .exe
# ═════════════════════════════════════════════════════════════════════════════
func _p_probes() -> void:
	print("\n═════ P. ЗОНДЫ ═════")
	var pr = GameManager.probes
	var sp: Array = _squad("spearman", F, _base + Vector3(20.0, 0.0, -20.0), 12, 6, 0.7)
	var sid: int = int(sp[0])
	await pframes(4)
	# P1 знамя: пал знаменосец
	var b0: int = pr.banner_passes
	var bearer = GameManager.squad_bearer(sid)
	if bearer != null and is_instance_valid(bearer):
		(bearer as Unit).take_damage(1e12)
	await pframes(3)
	verdict("P1 пал знаменосец — зонд banner_pass (%d → %d), знамя у соседа" % [b0, pr.banner_passes],
		pr.banner_passes == b0 + 1 and int(pr.last_banner.get("sid", 0)) == sid and bool(pr.last_banner.get("heir", false)))
	# P2 отход отряда — раз на отряд за окно
	var r0: int = pr.retreat_reports
	var men: Array = _members(sid)
	(men[0] as Unit).begin_retreat()
	(men[1] as Unit).begin_retreat()
	verdict("P2 отход отряда — один squad_retreat на отряд (%d → %d), живых %d" % [
		r0, pr.retreat_reports, int(pr.last_retreat.get("alive", -1))],
		pr.retreat_reports == r0 + 1 and int(pr.last_retreat.get("sid", 0)) == sid)
	for m in men:
		(m as Unit).end_retreat(true)
	# P3 штандарт: носитель пал — передача соседу
	var rm = GameManager.relic_mgr()
	var s0: int = pr.standard_passes
	if rm != null:
		rm.add_xp(_RCfg.POOL_COST / _RCfg.POOL_PER_KILL)
		rm.grant_to_squad(sid)
		await pframes(3)
		var car = null
		for r in rm.relics:
			if int((r as Dictionary).get("bsid", 0)) == sid:
				car = (r as Dictionary)["carrier"]
		if car != null and is_instance_valid(car):
			(car as Unit).take_damage(1e12)
		for _i in range(30):
			await pframes(1)
			if pr.standard_passes > s0:
				break
	verdict("P3 пал носитель штандарта — зонд standard_pass (%d → %d)" % [s0, pr.standard_passes],
		rm != null and pr.standard_passes == s0 + 1 and int(pr.last_standard.get("sid", 0)) == sid)
	# P4 минутная сводка зондов и навигации
	var m0: int = pr.summaries
	pr._sum_next = 1
	pr.tick()
	verdict("P4 сводка probe_summary: зонды и навигация (%d → %d), ключи A* на месте" % [m0, pr.summaries],
		pr.summaries == m0 + 1 and pr.last_summary.has("nav_calls") and pr.last_summary.has("nav_worst_us")
		and pr.last_summary.has("stuck") and pr.last_summary.has("retreat"))
	# P5 сводка босса
	var e0: int = _events("boss_status")
	if _boss != null and not _boss.is_dead():
		cmd.probe_status()
	verdict("P5 зонд босса boss_status: hp, свита, откаты (%d → %d)" % [e0, _events("boss_status")],
		_boss == null or _boss.is_dead() or _events("boss_status") == e0 + 1)
	# P6 ручка снята — зонд молчит
	_Opt.probes_ext = false
	var r1: int = pr.retreat_reports
	(men[2] as Unit).begin_retreat()
	pr._retreat_last.clear()
	(men[3] as Unit).begin_retreat()
	verdict("P6 ручка probes_ext=false: отход без зонда (%d → %d)" % [r1, pr.retreat_reports],
		pr.retreat_reports == r1)
	_Opt.probes_ext = true

# ═════════════════════════════════════════════════════════════════════════════
# X. ЯРОСТЬ, ИССТУПЛЕНИЕ, БЕГСТВО НА БАЗУ (ТЗ 29.10.2026, 2В)
# ═════════════════════════════════════════════════════════════════════════════
func _hp(b, f: float) -> void:
	b.current_health = b.max_health * f
	b._soa_push_stats()

func _x_rage() -> void:
	print("\n═════ X. ЯРОСТЬ И БЕГСТВО ═════")
	# Прежний (бессмертный) босс уходит, новый — со штатным запасом
	if _boss != null and is_instance_valid(_boss) and not _boss.is_dead():
		_kill(_members(_boss_sid))
	await pframes(4)
	GameManager.pig_boss_fallen = false
	var at: Vector3 = _base + Vector3(-25.0, 0.0, -25.0)
	var bsid: int = int(main.spawn_boss_squad(at))
	var b = null
	for m in _members(bsid):
		if (m as Unit).is_pig_boss():
			b = m
	verdict("X0 новый отряд босса", b != null)
	if b == null:
		return
	for m in _members(bsid):
		if m != b:
			(m as Unit).set_tick(false)
	await pframes(4)
	b._apply_pace()
	var s0: float = b._rage_speed0
	var cd0: float = b._rage_cd0
	var r0: int = _events("boss_rage")
	# X1 ярость
	_hp(b, _GobCfg.BOSS_RAGE_HP - 0.02)
	await pframes(4)
	verdict("X1 ярость при hp %.2f: скорость %.2f (×%.2f), перезарядка %.2f (×%.2f)" % [
		b.hp_frac(), b.move_speed, b.move_speed / s0, b.attack_cooldown, b.attack_cooldown / cd0],
		b.rage_level() == 1 and is_equal_approx(b.move_speed, s0 * _GobCfg.BOSS_RAGE_SPEED)
		and is_equal_approx(b.attack_cooldown, cd0 * _GobCfg.BOSS_RAGE_CD_MULT))
	verdict("X2 рыки тролля/туши в ярости (%d), хрюк — big_grunt" % b.rage_growls,
		b.rage_growls >= 1 and b._sfx_grunt() == "big_grunt")
	b._cry_ready_ms = 0
	b.screech()
	var cd_left: float = float(b._cry_ready_ms - Unit.game_ms()) * 0.001
	verdict("X3 откат горна в ярости %.0f с (×%.2f)" % [cd_left, cd_left / _GobCfg.BOSS_SCREECH_CD_SEC],
		absf(cd_left - _GobCfg.BOSS_SCREECH_CD_SEC * _GobCfg.BOSS_RAGE_CD_MULT) < 1.0)
	# X4 исступление
	_hp(b, _GobCfg.BOSS_FRENZY_HP - 0.01)
	await pframes(40)
	verdict("X4 исступление при hp %.2f: скорость ×%.2f, перезарядка ×%.2f, накал %d вспышек, пик %.2f" % [
		b.hp_frac(), b.move_speed / s0, b.attack_cooldown / cd0, b.frenzy_glows, b.hit_flash_peak()],
		b.rage_level() == 2 and is_equal_approx(b.move_speed, s0 * _GobCfg.BOSS_FRENZY_SPEED)
		and is_equal_approx(b.attack_cooldown, cd0 * _GobCfg.BOSS_FRENZY_CD_MULT)
		and b.frenzy_glows >= 2 and is_equal_approx(b.hit_flash_peak(), _GobCfg.BOSS_FRENZY_GLOW_PEAK))
	verdict("X5 зонд boss_rage: ярость и исступление (%d → %d)" % [r0, _events("boss_rage")],
		_events("boss_rage") == r0 + 2)
	# X6 ручка boss_rage снята — фазы нет
	_Opt.boss_rage = false
	await pframes(4)
	verdict("X6 ручка boss_rage=false: hp %.2f без ярости, скорость ×%.2f" % [b.hp_frac(), b.move_speed / s0],
		b.rage_level() == 0 and is_equal_approx(b.move_speed, s0))
	_Opt.boss_rage = true
	_hp(b, 0.9)
	await pframes(4)
	# ── БЕГСТВО ─────────────────────────────────────────────────────────
	var w: Dictionary = {"id": 990, "sids": [bsid], "stage": "engage", "pos": _base + Vector3(0.0, 0.0, 30.0),
		"pts": {}, "t0": gai.clock, "node": null, "tactic": 0}
	gai.waves.append(w)
	cmd._st = cmd.ST_COMMAND
	var esc: int = _members(bsid).size() - 1
	var lvl: int = int(GameManager.squads[bsid].get("level", 0))
	var f0: int = cmd.flees
	var e0: int = _events("boss_flee")
	_hp(b, _GobCfg.BOSS_FLEE_HP - 0.02)
	await pframes(3)
	cmd.tick_now()
	var ds: int = cmd.dropped_sid
	verdict("X7 hp %.2f — бегство: свита сброшена %d из %d → отряд %d (всадники, ранг %d), в волне вместо босса" % [
		b.hp_frac(), cmd.retinue_dropped, esc, ds, int(GameManager.squads.get(ds, {}).get("level", -1))],
		cmd.flees == f0 + 1 and cmd._st == cmd.ST_FLEE and cmd.retinue_dropped == esc and esc > 0
		and _members(bsid).size() == 1 and (w["sids"] as Array).has(ds) and not (w["sids"] as Array).has(bsid)
		and String(GameManager.squads[ds]["type"]) == "goblin_rider"
		and int(GameManager.squads[ds]["level"]) == lvl and _events("boss_flee") == e0 + 1)
	verdict("X8 бежит быстрее: скорость ×%.2f (ярость ×бегство), отход с билетом" % (b.move_speed / s0),
		b.is_fleeing() and is_equal_approx(b.move_speed, s0 * _GobCfg.BOSS_RAGE_SPEED * _GobCfg.BOSS_FLEE_SPEED_MULT)
		and b.retreating)
	var home: Vector3 = cmd.flee_home
	var bp: Vector3 = b.global_position
	var d0: float = Vector2(bp.x - home.x, bp.z - home.z).length()
	var hp_run: float = b.hp_frac()
	await pframes(180)
	bp = b.global_position
	var d1: float = Vector2(bp.x - home.x, bp.z - home.z).length()
	verdict("X9 бежит к лагерю орды: до базы %.0f → %.0f м за 3 с, в пути не лечится (%.3f → %.3f)" % [
		d0, d1, hp_run, b.hp_frac()],
		d0 - d1 > s0 * 2.0 and b.hp_frac() <= hp_run + 0.001
		and Vector2(home.x - gai.village.x, home.z - gai.village.z).length() < _GobCfg.BOSS_BASE_BACK + 12.0)
	# Прибытие — переносим к точке базы (лагерь далеко)
	b.global_position = Vector3(home.x + 2.0, GameManager.get_terrain_height(home.x + 2.0, home.z), home.z)
	b.sync_row()
	await pframes(2)
	var a0: int = cmd.base_arrivals
	cmd.tick_now()
	await pframes(3)
	var full: int = int(_GobCfg.SQUAD_SIZE.get("pig_boss", 31))
	verdict("X10 на базе: лечится, новая свита +%d (в отряде %d из %d)" % [
		cmd.retinue_refilled, _members(bsid).size(), full],
		cmd.base_arrivals == a0 + 1 and cmd._st == cmd.ST_RECOVER and b.is_recovering()
		and cmd.retinue_refilled > 0 and _members(bsid).size() > 1 and _events("boss_base") >= 1)
	var h0: float = b.hp_frac()
	await pframes(120)
	cmd.tick_now()
	verdict("X11 лечение на базе: hp %.3f → %.3f за 2 с (ставка %.2f/с), в строй не рвётся" % [
		h0, b.hp_frac(), _GobCfg.BOSS_BASE_REGEN_PER_SEC],
		b.hp_frac() - h0 > _GobCfg.BOSS_BASE_REGEN_PER_SEC * 1.5 and cmd._st == cmd.ST_RECOVER)
	_hp(b, _GobCfg.BOSS_BASE_READY_HP + 0.01)
	var j0: int = cmd.rejoins
	cmd.tick_now()
	verdict("X12 исцелён — в строй: волна снова ведёт отряд босса, приказы принимает, скорость ×%.2f" % (b.move_speed / s0),
		cmd.rejoins == j0 + 1 and cmd._st == cmd.ST_COMMAND and (w["sids"] as Array).has(bsid)
		and not b.is_withdrawing() and not b.is_fleeing() and is_equal_approx(b.move_speed, s0)
		and _events("boss_rejoin") >= 1)
	# X13 сразу после тарана в ярости — бежит
	_hp(b, _GobCfg.BOSS_RAGE_HP - 0.03)
	await pframes(3)
	var f1: int = cmd.flees
	cmd.tick_now()
	var no_ram: bool = cmd.flees == f1
	b.ram_end_ms = Unit.game_ms()
	cmd.tick_now()
	verdict("X13 hp %.2f: без тарана держится, сразу после тарана — бегство (%s)" % [b.hp_frac(), cmd.last_flee_reason],
		no_ram and cmd.flees == f1 + 1 and cmd.last_flee_reason.find("тарана") >= 0)
	# X14 ручка boss_flee_base снята — прежний отход к волне
	_hp(b, 0.9)
	b.resume_command()
	cmd._st = cmd.ST_COMMAND
	if not (w["sids"] as Array).has(bsid):
		(w["sids"] as Array).append(bsid)
	_Opt.boss_flee_base = false
	var f2: int = cmd.flees
	_hp(b, _GobCfg.BOSS_WITHDRAW_HP - 0.02)
	cmd.tick_now()
	verdict("X14 ручка boss_flee_base=false: прежний отход (%s), бегства нет" % cmd.ST_NAMES[cmd._st],
		cmd.flees == f2 and cmd._st == cmd.ST_WITHDRAW and not b.is_fleeing())
	_Opt.boss_flee_base = true
	gai.waves.erase(w)

# ═════════════════════════════════════════════════════════════════════════════
# Y. ПРОРЫВ В БЕГСТВЕ (ТЗ 31.10.2026): бегущий босс не застревает в строю
# ═════════════════════════════════════════════════════════════════════════════
## Один прогон: строй «Защиты» 10×5 поперёк курса, босс в 6 м перед ним бежит к
## точке в 30 м за строем. Ответ: [прошёл строй, сек до прохода, рывков,
## павших копейщиков, раскидано (лежали)]
func _y_run(knob: bool) -> Array:
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead() 				and (u as Unit).faction != F and ((u as Unit).is_pig_boss()
				or (u as Unit).global_position.distance_to(_base) < 60.0):
			(u as Unit).take_damage(1e12)
	await pframes(4)
	GameManager.pig_boss_fallen = false
	_Opt.boss_flee_break = knob
	var probe_b := Building.new()
	var spc: float = probe_b.squad_spacing
	probe_b.free()
	var sp: Array = _squad("spearman", F, _base + Vector3(0.0, 0.0, 4.0), 50, 10, spc)
	var spear: Array = sp[1]
	for u in spear:
		(u as Unit)._facing = Vector3(0.0, 0.0, -1.0)
		(u as Unit).set_stance("defense")
	GameManager.on_squad_stance(int(sp[0]), "defense")
	var bsid: int = int(main.spawn_boss_squad(_base + Vector3(0.0, 0.0, -2.0)))
	var b = null
	for m in _members(bsid):
		if (m as Unit).is_pig_boss():
			b = m
		else:
			(m as Unit).take_damage(1e12)
	if b == null:
		return [false, -1.0, 0, 0, 0]
	_immortal(b)
	await pframes(10)
	var line_back: float = _base.z + 4.0 + 4.0 * spc
	var goal: Vector3 = _base + Vector3(0.0, 0.0, 34.0)
	b.flee_to(goal)
	var d0: int = b.flee_dashes
	var t_pass := -1.0
	var downed := 0
	var seen: Dictionary = {}
	for i in range(8 * 60):
		await get_tree().physics_frame
		for u in spear:
			if u != null and is_instance_valid(u) and not (u as Unit).is_dead() 					and (u as Unit).is_down() and not seen.has((u as Unit).get_instance_id()):
				seen[(u as Unit).get_instance_id()] = true
				downed += 1
		if t_pass < 0.0 and b.global_position.z > line_back + 2.0:
			t_pass = float(i) / 60.0
			break
	var dead := 0
	for u in spear:
		if u == null or not is_instance_valid(u) or (u as Unit).is_dead():
			dead += 1
	var dashes: int = b.flee_dashes - d0
	_kill(_members(bsid))
	_kill(spear)
	_Opt.boss_flee_break = true
	await pframes(6)
	return [t_pass >= 0.0, t_pass, dashes, dead, downed]

func _y_flee_break() -> void:
	print("
═════ Y. ПРОРЫВ В БЕГСТВЕ ═════")
	var on: Array = await _y_run(true)
	print("  с прорывом: прошёл %s за %.1f с, рывков %d, павших %d, сбито с ног %d" % [str(on[0]), on[1], on[2], on[3], on[4]])
	var off: Array = await _y_run(false)
	print("  без прорыва: прошёл %s за %.1f с" % [str(off[0]), off[1]])
	verdict("Y1 бегущий босс проходит строй 10×5 «Защиты» насквозь за %.1f с (рывков %d)" % [on[1], on[2]],
		bool(on[0]) and int(on[2]) >= 1 and float(on[1]) <= 5.0)
	verdict("Y2 расталкивает, а не давит: сбито с ног %d, павших %d" % [on[4], on[3]],
		int(on[4]) >= 3 and int(on[3]) <= 2)
	verdict("Y0 ручка boss_flee_break=false: за 8 с строй не пройден (%s) — механизм доказан" % str(off[0]),
		not bool(off[0]))
