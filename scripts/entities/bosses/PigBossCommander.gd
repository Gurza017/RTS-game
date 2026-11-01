extends Node
const _OptPB := preload("res://scripts/perf_config.gd")

## ═══════════════════════════════════════════════════════════════════════════
## МОЗГ СВИНОБОССА — ОДИН ТАКТИЧЕСКИЙ УЗЕЛ НА ПАРТИЮ (ТЗ 28.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Узел рядом с CavalryCommander (Main._ready), ручка perf_config.pig_boss.
## Такт BOSS_TICK_SEC по игровым часам (GameClockStep). Работает, пока жив
## босс (GameManager.pig_boss) и его волна (GoblinAI.waves) в стадии
## engage/flank. За такт:
##   • центр волны (GoblinAI._wave_centre), ось чужого фронта
##     (GameManager.enemy_front_axis — тот же ковариационный расчёт, что у
##     EnemyAI._enemy_front_normal, по строкам ядра);
##   • плотность чужих в ПЯТИ точках (army.enemy_count, ядро, без массивов):
##     перед фронтом, два фланга, два дальних фланга;
##   • приказы ПАЧКОЙ через очередь орды (GoblinAI._order_* → _drain_orders с
##     бюджетом): конница — на фланг с меньшей плотностью; пехота — добить
##     чужой отряд силой < BOSS_FINISH_STRENGTH, иначе держит фронт (волна
##     ведёт её сама); туши — по постройкам. Отряд в бою (squad_in_combat)
##     приказов не получает, остальные — не чаще BOSS_REISSUE_SEC;
##   • клич — когда волна в контакте и чужих в ауре >= BOSS_SCREECH_MIN_FOES.
## САМОСОХРАНЕНИЕ: hp < BOSS_WITHDRAW_HP → WITHDRAW: цель снята, отход с
## билетом выхода (begin_retreat) в точку «центр волны минус курс ×
## BOSS_SHELTER_DIST»; из окружения — через самый свободный из четырёх
## секторов (enemy_count). Возврат в COMMAND при hp > BOSS_RETURN_HP
## (регенерация BOSS_REGEN_PER_SEC внутри своей волны). Аура работает и на
## отходе — её ведёт сам босс.
## УДАР СВИНОБОССА (ТЗ 29.10.2026, ручка boss_ram, _tick_ram): готов таран и
## в BOSS_RAM_SCAN_R стоит строй копейщиков (>= BOSS_RAM_MIN_MEN живых) —
## мозг берёт свиту (чужой отряд всадников рядом → своя свита босса → самый
## крупный отряд рядом → подкрепление BOSS_RAM_REINF_N всадников), ставит её
## за спину, даёт боссу ram_begin; на бреши — свита бегом в прорыв за спину
## босса, через BOSS_RAM_RUSH_SEC (или по прибытии) — атака отряда-цели.
## БЕГСТВО НА БАЗУ (ТЗ 29.10.2026, 2В, ручка boss_flee_base; заменяет отход
## к волне): hp <= BOSS_FLEE_HP или конец тарана при hp <= BOSS_RAGE_HP →
## FLEE: свита сброшена (живые всадники уходят в свой отряд, остаются в волне),
## таран прерван, бег к лагерю (главная хата + BOSS_BASE_BACK) → RECOVER:
## лечение BOSS_BASE_REGEN_PER_SEC, свита добирается до штата
## (Main.refill_boss_retinue) → при hp >= BOSS_BASE_READY_HP — в идущую волну,
## а без неё — на площадку сбора (GoblinAI._to_muster, следующий план).
## ЗОНД БОССА (ручка boss_probe): приказы, горн, фазы тарана, отход/возврат,
## сводка hp/свиты/откатов раз в BOSS_PROBE_STATUS_SEC — события телеметрии
## и строки «[ЗОНД boss_…]» в логе .exe (свой бюджет строк).

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const SquadProbesRef := preload("res://scripts/army/SquadProbes.gd")

const ST_IDLE := 0
const ST_COMMAND := 1
const ST_WITHDRAW := 2
const ST_FLEE := 3
const ST_RECOVER := 4
const ST_NAMES := ["idle", "command", "withdraw", "flee", "recover"]

var _gclk = preload("res://scripts/GameClockStep.gd").new()
var _t: float = 0.0
var _st: int = ST_IDLE
## sid → игровые секунды последнего приказа от мозга
var _last_issue: Dictionary = {}
var _withdraw_point: Vector3 = Vector3.INF
var _withdraw_t: float = 0.0

## ── СЧЁТЧИКИ ДЛЯ СТЕНДОВ ───────────────────────────────────────────────────
var ticks: int = 0
var orders_batched: int = 0      ## приказов, положенных в очередь орды
var orders_cav: int = 0
var orders_inf: int = 0
var orders_big: int = 0
var screeches: int = 0
var withdrawals: int = 0
var returns: int = 0
var density_calls: int = 0       ## вызовов enemy_count за последний такт
var usec_total: int = 0
var last_axis: Vector3 = Vector3.ZERO
var last_density: PackedInt32Array = PackedInt32Array()
## ── ТАРАН: состояние свиты и счётчики стендам ─────────────────────────────
## Пусто — тарана нет; иначе {target, escort, kind, phase, t, dir, breach}
var ram: Dictionary = {}
var rams_started: int = 0
var escort_rushes: int = 0
var escort_attacks: int = 0
var reinforcements: int = 0
var last_escort_kind: String = ""
## ── БЕГСТВО НА БАЗУ (2В) ───────────────────────────────────────────────────
var flee_home: Vector3 = Vector3.INF
var flees: int = 0
var base_arrivals: int = 0
var rejoins: int = 0
var retinue_dropped: int = 0         ## всадников сброшено при последнем бегстве
var dropped_sid: int = 0             ## их новый отряд
var retinue_refilled: int = 0        ## всадников набрано на базе при последнем лечении
var last_flee_reason: String = ""
var _flee_t: float = 0.0
var _ram_end_seen: int = 0
## ── ЗОНД ───────────────────────────────────────────────────────────────────
var probe_events: int = 0
var probe_lines: int = 0
var _status_t: float = 0.0
var _plog_at: int = 0
var _plog_used: int = 0
const PROBE_LOG_WINDOW_MS := 10000
const PROBE_LOG_BUDGET := 20

func state_name() -> String:
	return ST_NAMES[_st]

func _process(_delta: float) -> void:
	var delta: float = _gclk.step()
	if not _Opt.pig_boss:
		return
	_t += delta
	_status_t += delta
	if _t < _GobCfg.BOSS_TICK_SEC:
		return
	_t = 0.0
	tick_now()
	if _status_t >= _GobCfg.BOSS_PROBE_STATUS_SEC:
		_status_t = 0.0
		probe_status()

## Один такт мозга. Публичный — стенды зовут его напрямую
func tick_now() -> void:
	if not _Opt.pig_boss:
		return
	var t0: int = Time.get_ticks_usec()
	ticks += 1
	var boss = GameManager.pig_boss
	if boss == null or not is_instance_valid(boss) or (boss as Unit).is_dead():
		_st = ST_IDLE
		return
	var b := boss as Unit
	var gai = GameManager.main.get("goblin_ai") if GameManager.main != null else null
	if gai == null or not is_instance_valid(gai):
		return
	var sid: int = b.squad_id
	var w: Dictionary = _wave_of(gai, sid)
	var now: float = float(Unit.game_ms()) * 0.001
	# ── САМОСОХРАНЕНИЕ — РАНЬШЕ ЛЮБЫХ ПРИКАЗОВ ───────────────────────────
	if _Opt.boss_withdraw and _Opt.boss_flee_base:
		if _tick_flee(b, gai, w, now):
			usec_total += Time.get_ticks_usec() - t0
			return
		# Вернувшийся в строй мог только что встать в волну
		w = _wave_of(gai, sid)
	elif _Opt.boss_withdraw:
		var hp: float = float(b.call("hp_frac"))
		if _st != ST_WITHDRAW and hp < _GobCfg.BOSS_WITHDRAW_HP:
			_begin_withdraw(b, gai, w, now)
			usec_total += Time.get_ticks_usec() - t0
			return
		if _st == ST_WITHDRAW:
			if hp > _GobCfg.BOSS_RETURN_HP:
				_end_withdraw(b, gai, w)
			else:
				_tick_withdraw(b, gai, w, now)
				usec_total += Time.get_ticks_usec() - t0
				return
	elif bool(b.call("is_withdrawing")):
		# Ручка снята на живой сцене — отход не держим
		_end_withdraw(b, gai, w)
	# ── УДАР СВИНОБОССА — РАНЬШЕ ПРИКАЗОВ ВОЛНЕ: свиту волна не перебивает ──
	if _Opt.boss_ram:
		_tick_ram(b, gai, w, now)
	# ── КОМАНДОВАНИЕ ВОЛНОЙ ──────────────────────────────────────────────
	if w.is_empty():
		_st = ST_IDLE
		if _Opt.boss_sortie and ram.is_empty():
			_tick_idle(b, gai, now)
		usec_total += Time.get_ticks_usec() - t0
		return
	_idle_since = -1.0
	_st = ST_COMMAND
	var stage: String = String(w.get("stage", ""))
	if stage != "engage" and stage != "flank":
		usec_total += Time.get_ticks_usec() - t0
		return
	_command(b, gai, w, now)
	usec_total += Time.get_ticks_usec() - t0

## ── БЕЗ ВОЛНЫ (ТЗ 30.10.2026, разбор партии 30.10) ────────────────────────
## Прежде ST_IDLE значил «ничего»: босс 11 мин стоял у лагеря до конца партии.
## Теперь: идущая волна (поход, бой, фланг) — встать в неё; нет — через
## BOSS_IDLE_SORTIE_SEC вылазка (GoblinAI.boss_sortie, цели — брод и рудник)
var _idle_since: float = -1.0
var sorties: int = 0
var idle_joins: int = 0

func _tick_idle(b: Unit, gai, now: float) -> void:
	var bsid: int = int(gai.boss_free_sid()) if gai.has_method("boss_free_sid") else 0
	if bsid <= 0:
		_idle_since = -1.0
		return
	if _idle_since < 0.0:
		_idle_since = now
	for wv in gai.waves:
		var st: String = String((wv as Dictionary).get("stage", ""))
		if st == "march" or st == "engage" or st == "flank":
			if not ((wv as Dictionary)["sids"] as Array).has(bsid):
				((wv as Dictionary)["sids"] as Array).append(bsid)
			if gai._muster_slot.has(bsid):
				gai.muster.erase(gai._muster_slot[bsid])
				gai._muster_slot.erase(bsid)
			gai._homing.erase(bsid)
			gai._wake_squad(bsid)
			gai._engage_squad(bsid, wv)
			idle_joins += 1
			_idle_since = -1.0
			_st = ST_COMMAND
			_bprobe("boss_join", {"wave": int((wv as Dictionary).get("id", 0)), "stage": st},
				"без дела — в идущую волну %d (%s)" % [int((wv as Dictionary).get("id", 0)), st])
			return
	if now - _idle_since < _GobCfg.BOSS_IDLE_SORTIE_SEC:
		return
	_idle_since = now
	if bool(gai.boss_sortie(bsid)):
		sorties += 1
		var w2: Dictionary = _wave_of(gai, bsid)
		_bprobe("boss_sortie", {"wave": int(w2.get("id", 0)), "goal": String(w2.get("name", "")),
			"squads": (w2.get("sids", []) as Array).size()},
			"вылазка: волна %d → %s, отрядов %d" % [int(w2.get("id", 0)), String(w2.get("name", "")),
			(w2.get("sids", []) as Array).size()])

func _wave_of(gai, sid: int) -> Dictionary:
	for w in gai.waves:
		if ((w as Dictionary)["sids"] as Array).has(sid):
			return w
	return {}

# ─────────────────────────────────────────────────────────────────────────────
# КОМАНДОВАНИЕ: ОСЬ ФРОНТА, ПЛОТНОСТЬ, ПРИКАЗЫ ПАЧКОЙ, КЛИЧ
# ─────────────────────────────────────────────────────────────────────────────
func _command(b: Unit, gai, w: Dictionary, now: float) -> void:
	var centre: Vector3 = gai._wave_centre(w)
	if centre.x == INF:
		return
	var fac: int = b.faction
	var army = GameManager.army
	var axis: Vector3 = GameManager.enemy_front_axis(centre, fac, _GobCfg.BOSS_FRONT_SCAN_R)
	if axis == Vector3.ZERO:
		axis = w.get("dir", Vector3.FORWARD) as Vector3
		var goal: Vector3 = w.get("pos", centre) as Vector3
		var to := Vector3(goal.x - centre.x, 0.0, goal.z - centre.z)
		if to.length_squared() > 1.0:
			axis = to.normalized()
	last_axis = axis
	var side := Vector3(-axis.z, 0.0, axis.x)
	var f: float = _GobCfg.BOSS_PROBE_AHEAD
	var d: float = _GobCfg.BOSS_PROBE_SIDE
	var r: float = _GobCfg.BOSS_PROBE_R
	# Пять точек: фронт, левый/правый фланг, дальние фланги (<= 10 вызовов)
	var pts: Array = [
		centre + axis * f,
		centre + axis * f * 0.5 + side * d,
		centre + axis * f * 0.5 - side * d,
		centre + side * d * 1.8,
		centre - side * d * 1.8,
	]
	var dens := PackedInt32Array()
	dens.resize(pts.size())
	for i in range(pts.size()):
		var p: Vector3 = pts[i]
		dens[i] = army.enemy_count(p.x, p.z, r, fac)
	density_calls = pts.size()
	last_density = dens
	# Фланг с меньшей плотностью — туда конницу (ближний, при равенстве — левый)
	var flank_i: int = 1 if dens[1] <= dens[2] else 2
	var flank_pt: Vector3 = pts[flank_i]
	if dens[flank_i] > 0 and dens[3 if flank_i == 1 else 4] < dens[flank_i]:
		flank_pt = pts[3 if flank_i == 1 else 4]
	# Слабый чужой отряд у фронта — пехоте добить
	var weak_sid: int = _weakest_foe(centre, fac)
	var boss_sid: int = b.squad_id
	# Подача дозами идёт (WaveFeed) — отрядами волны ведает она (boss_wave_sync)
	var fed: bool = _OptPB.boss_wave_sync and _OptPB.wave_feed and w.has("feed")
	for s in (w["sids"] as Array):
		var sid: int = int(s)
		if sid == boss_sid or fed:
			continue
		if not ram.is_empty() and int(ram.get("escort", 0)) == sid:
			continue
		if now - float(_last_issue.get(sid, -1.0e9)) < _GobCfg.BOSS_REISSUE_SEC:
			continue
		if GameManager.squad_in_combat(sid):
			continue
		var c: Vector3 = gai._centre(sid)
		if c.x == INF:
			continue
		var t: String = gai._type(sid)
		match t:
			"goblin_rider":
				if c.distance_to(flank_pt) > _GobCfg.BOSS_FLANK_ARRIVE:
					gai._order_move(sid, GameManager.land_target(flank_pt), true)
					_note(sid, now)
					orders_cav += 1
					_order_probe(sid, "cav_flank", flank_pt)
			"big_goblin":
				var node: Node3D = gai._raze_target(c)
				if node == null:
					var wn = w.get("node")
					if wn != null and is_instance_valid(wn) and (wn is Building) \
							and not (wn as Building).is_dead() and gai._hostile_building(wn):
						node = wn
				if node != null:
					gai._order_attack_node(sid, node)
					_note(sid, now)
					orders_big += 1
					_order_probe(sid, "big_raze", node.global_position)
			_:
				if weak_sid > 0:
					gai._order_attack_squad(sid, weak_sid)
					_note(sid, now)
					orders_inf += 1
					_order_probe(sid, "inf_finish", c, weak_sid)
				# иначе фронт держит сама волна (GoblinAI._engage_squad)
	# ── КЛИЧ: ВОЛНА В КОНТАКТЕ, ЧУЖИХ В АУРЕ ДОСТАТОЧНО ─────────────────
	if bool(b.call("screech_ready")):
		var bp: Vector3 = b.global_position
		var foes: int = army.enemy_count(bp.x, bp.z, _GobCfg.BOSS_AURA_R, fac)
		density_calls += 1
		if foes >= _GobCfg.BOSS_SCREECH_MIN_FOES and bool(b.call("screech")):
			screeches += 1
			_bprobe("boss_horn" if _Opt.boss_horn else "boss_screech", {"foes": foes,
				"squads": int(b.get("horn_roared")),
				"hp": snappedf(float(b.call("hp_frac")), 0.01)},
				"горн: чужих в ауре %d, отрядов орды рыкнуло %d, hp %.2f" % [
				foes, int(b.get("horn_roared")), float(b.call("hp_frac"))])

func _note(sid: int, now: float) -> void:
	_last_issue[sid] = now
	orders_batched += 1

## Чужой отряд силой < BOSS_FINISH_STRENGTH ближе BOSS_FINISH_R к центру волны;
## 0 — нет. Обход реестра отрядов (сотня записей), не бойцов
func _weakest_foe(centre: Vector3, fac: int) -> int:
	var best := 0
	var best_d: float = _GobCfg.BOSS_FINISH_R * _GobCfg.BOSS_FINISH_R
	for key in GameManager.squads.keys():
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) == fac:
			continue
		var men: Array = sq["members"]
		var full: int = maxi(int(sq.get("full", 0)), 1)
		if men.is_empty() or men.size() < 2:
			continue
		if float(men.size()) / float(full) >= _GobCfg.BOSS_FINISH_STRENGTH:
			continue
		var c: Vector2 = GameManager.squad_centre_xz(int(key))
		if c == Vector2.INF:
			continue
		var dd: float = (c.x - centre.x) * (c.x - centre.x) + (c.y - centre.z) * (c.y - centre.z)
		if dd < best_d:
			best_d = dd
			best = int(key)
	return best

# ─────────────────────────────────────────────────────────────────────────────
# САМОСОХРАНЕНИЕ
# ─────────────────────────────────────────────────────────────────────────────
func _begin_withdraw(b: Unit, gai, w: Dictionary, now: float) -> void:
	_st = ST_WITHDRAW
	withdrawals += 1
	var bp0: Vector3 = b.global_position
	var foes0: int = GameManager.army.enemy_count(bp0.x, bp0.z, _GobCfg.BOSS_ESCAPE_R, b.faction)
	_bprobe("boss_withdraw", {"hp": snappedf(float(b.call("hp_frac")), 0.01),
		"trigger": "hp<%.2f" % _GobCfg.BOSS_WITHDRAW_HP, "foes_near": foes0,
		"ram": int(b.call("ram_phase")), "escort": _retinue_alive(b),
		"orders": "%d/%d/%d" % [orders_cav, orders_inf, orders_big]},
		"отход: hp %.2f < %.2f, чужих в %.0f м %d, свита %d" % [float(b.call("hp_frac")),
		_GobCfg.BOSS_WITHDRAW_HP, _GobCfg.BOSS_ESCAPE_R, foes0, _retinue_alive(b)])
	if not ram.is_empty():
		_ram_release("withdraw")
	_withdraw_point = _shelter_point(b, gai, w)
	_withdraw_t = now
	b.call("withdraw_to", _withdraw_point)

func _tick_withdraw(b: Unit, gai, w: Dictionary, now: float) -> void:
	# Точка уехала с волной — переиздать не чаще BOSS_REISSUE_SEC
	if now - _withdraw_t < _GobCfg.BOSS_REISSUE_SEC:
		return
	_withdraw_t = now
	var p: Vector3 = _shelter_point(b, gai, w)
	if _withdraw_point.x == INF or p.distance_to(_withdraw_point) > 6.0 \
			or b.global_position.distance_to(p) > 8.0:
		_withdraw_point = p
		b.call("withdraw_to", p)

func _end_withdraw(b: Unit, gai, w: Dictionary) -> void:
	if _st == ST_WITHDRAW:
		returns += 1
		_bprobe("boss_return", {"hp": snappedf(float(b.call("hp_frac")), 0.01),
			"trigger": "hp>%.2f" % _GobCfg.BOSS_RETURN_HP},
			"возврат: hp %.2f > %.2f" % [float(b.call("hp_frac")), _GobCfg.BOSS_RETURN_HP])
	_st = ST_COMMAND if not w.is_empty() else ST_IDLE
	b.call("resume_command")
	if not w.is_empty() and gai.has_method("_engage_squad"):
		gai._engage_squad(b.squad_id, w)

# ─────────────────────────────────────────────────────────────────────────────
# УДАР СВИНОБОССА: ЦЕЛЬ, СВИТА, ПРОРЫВ
# ─────────────────────────────────────────────────────────────────────────────
func _tick_ram(b: Unit, gai, w: Dictionary, now: float) -> void:
	if ram.is_empty():
		if not bool(b.call("ram_ready")):
			return
		var tgt: int = _ram_target(b)
		if tgt <= 0:
			return
		_ram_start(b, gai, w, tgt, now)
		return
	var phase: String = String(ram["phase"])
	var esc: int = int(ram["escort"])
	var bphase: int = int(b.call("ram_phase"))
	var dir: Vector3 = ram["dir"]
	if phase == "prep" or phase == "run":
		if bphase == 2:
			ram["phase"] = "run"
		var breached: bool = bool(b.get("ram_breached"))
		# Таран кончился (или брешь пробита) — свита бегом в прорыв за спину
		if breached or bphase == 0:
			var bp: Vector3 = b.global_position
			var bat: Vector3 = b.get("ram_breach_at")
			var at: Vector3 = bat if bat.x != INF else bp
			var pt: Vector3 = GameManager.land_target(at - dir * _GobCfg.BOSS_RAM_BREACH_BACK)
			ram["breach"] = pt
			ram["phase"] = "rush"
			ram["t"] = now
			if esc > 0 and _alive(esc) > 0:
				gai._order_move(esc, pt, true)
				_last_issue[esc] = now
				escort_rushes += 1
			_bprobe("boss_ram_breach", {"target": int(ram["target"]), "escort": esc,
				"kills": int(b.get("ram_kills")), "flung": int(b.get("ram_flung")),
				"rows": (b.get("ram_rows") as PackedFloat32Array).size(),
				"breached": breached, "end": String(b.get("ram_end_reason"))},
				"брешь: раздавлено %d, раскидано %d, рядов %d, свита %d бегом в прорыв" % [
				int(b.get("ram_kills")), int(b.get("ram_flung")),
				(b.get("ram_rows") as PackedFloat32Array).size(), esc])
		return
	if phase == "rush":
		if bphase == 0 and String(b.get("ram_end_reason")) != "":
			ram["stopped"] = true
		var pt2: Vector3 = ram["breach"]
		var c: Vector3 = gai._centre(esc) if esc > 0 and _alive(esc) > 0 else Vector3.INF
		var arrived: bool = c.x != INF and Vector2(c.x - pt2.x, c.z - pt2.z).length() < 6.0
		if arrived or now - float(ram["t"]) >= _GobCfg.BOSS_RAM_RUSH_SEC:
			var tsid: int = int(ram["target"])
			if esc > 0 and _alive(esc) > 0 and GameManager.squads.has(tsid) and _alive(tsid) > 0:
				gai._order_attack_squad(esc, tsid)
				_last_issue[esc] = now
				escort_attacks += 1
			_bprobe("boss_ram_escort", {"escort": esc, "target": tsid, "arrived": arrived,
				"escort_alive": _alive(esc) if esc > 0 else 0,
				"target_alive": _alive(tsid)},
				"свита %d в прорыве (дошла: %s, живых %d) — атака отряда %d (живых %d)" % [
				esc, arrived, _alive(esc) if esc > 0 else 0, tsid, _alive(tsid)])
			_ram_release("done")

## Цель тарана: ближайший к боссу чужой отряд копейщиков (строй игрока или
## красных) в BOSS_RAM_SCAN_R с живыми >= BOSS_RAM_MIN_MEN. Обход реестра отрядов
func _ram_target(b: Unit) -> int:
	var bp: Vector3 = b.global_position
	var best := 0
	var best_d: float = _GobCfg.BOSS_RAM_SCAN_R * _GobCfg.BOSS_RAM_SCAN_R
	for key in GameManager.squads.keys():
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) == b.faction:
			continue
		if String(sq.get("type", "")) != "spearman":
			continue
		if _alive(int(key)) < _GobCfg.BOSS_RAM_MIN_MEN:
			continue
		var c: Vector2 = GameManager.squad_centre_xz(int(key))
		if c == Vector2.INF:
			continue
		var dd: float = (c.x - bp.x) * (c.x - bp.x) + (c.y - bp.z) * (c.y - bp.z)
		if dd < best_d:
			best_d = dd
			best = int(key)
	return best

func _ram_start(b: Unit, gai, w: Dictionary, tgt: int, now: float) -> void:
	var pick: Array = _pick_escort(b, gai, w, tgt)
	var esc: int = int(pick[0])
	var kind: String = String(pick[1])
	if not bool(b.call("ram_begin", tgt)):
		return
	rams_started += 1
	last_escort_kind = kind
	var bp: Vector3 = b.global_position
	var c: Vector2 = GameManager.squad_centre_xz(tgt)
	var dir := Vector3(c.x - bp.x, 0.0, c.y - bp.z).normalized()
	ram = {"target": tgt, "escort": esc, "kind": kind, "phase": "prep", "t": now,
		"dir": dir, "breach": Vector3.INF}
	# Свита — за спину босса, бегом (своя свита: босс приказ не примет — он на таране)
	if esc > 0:
		gai._order_move(esc, GameManager.land_target(bp - dir * 6.0), true)
		_last_issue[esc] = now
	_bprobe("boss_ram_start", {"target": tgt, "target_alive": _alive(tgt), "escort": esc,
		"escort_kind": kind, "escort_alive": _alive(esc) if esc > 0 else 0,
		"dist": snappedf(Vector2(c.x - bp.x, c.y - bp.z).length(), 0.1),
		"hp": snappedf(float(b.call("hp_frac")), 0.01)},
		"таран: цель отряд %d (живых %d) в %.1f м, свита %d (%s, живых %d)" % [tgt, _alive(tgt),
		Vector2(c.x - bp.x, c.y - bp.z).length(), esc, kind, _alive(esc) if esc > 0 else 0])

## Свита тарана → [sid, вид]: чужой отряд всадников рядом, своя свита босса,
## самый крупный отряд орды рядом, иначе подкрепление всадников за спиной
func _pick_escort(b: Unit, gai, w: Dictionary, tgt: int) -> Array:
	var bp: Vector3 = b.global_position
	var r2: float = _GobCfg.BOSS_RAM_ESCORT_R * _GobCfg.BOSS_RAM_ESCORT_R
	var best_rider := 0
	var best_rider_n := 0
	var best_any := 0
	var best_any_n := 0
	for key in GameManager.squads.keys():
		var sid: int = int(key)
		if sid == b.squad_id:
			continue
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) != b.faction:
			continue
		var n: int = _alive(sid)
		if n <= 0 or GameManager.squad_panicked(sid):
			continue
		var c: Vector2 = GameManager.squad_centre_xz(sid)
		if c == Vector2.INF or (c.x - bp.x) * (c.x - bp.x) + (c.y - bp.z) * (c.y - bp.z) > r2:
			continue
		var t: String = String(sq.get("type", ""))
		if t == "goblin_rider":
			if n > best_rider_n:
				best_rider_n = n
				best_rider = sid
		elif t != "big_goblin" and t != "gnoll":
			if n > best_any_n:
				best_any_n = n
				best_any = sid
	if best_rider > 0:
		return [best_rider, "riders"]
	if _retinue_alive(b) >= _GobCfg.BOSS_RAM_ESCORT_MIN:
		return [b.squad_id, "retinue"]
	if best_any > 0:
		return [best_any, "largest"]
	# Подкрепление: всадники за спиной босса, в волну — чтобы её такт их вёл
	var m = GameManager.main
	if m != null and is_instance_valid(m) and m.has_method("spawn_goblin_squad"):
		var c2: Vector2 = GameManager.squad_centre_xz(tgt)
		var back := Vector3(bp.x - c2.x, 0.0, bp.z - c2.y).normalized() if c2 != Vector2.INF else Vector3.BACK
		var at: Vector3 = GameManager.land_target(bp + back * 8.0)
		var sid2: int = int(m.call("spawn_goblin_squad", "goblin_rider", _GobCfg.BOSS_RAM_REINF_N, at))
		if sid2 > 0:
			reinforcements += 1
			if not w.is_empty():
				(w["sids"] as Array).append(sid2)
			_bprobe("boss_ram_reinforce", {"sid": sid2, "n": _alive(sid2)},
				"подкрепление: отряд %d всадников (%d)" % [sid2, _alive(sid2)])
			return [sid2, "reinforce"]
	return [0, "none"]

func _ram_release(why: String) -> void:
	if why == "withdraw":
		_bprobe("boss_ram_abort", {"target": int(ram.get("target", 0)), "why": why},
			"таран прерван: %s" % why)
	ram = {}

func _alive(sid: int) -> int:
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return 0
	var n := 0
	for m in ((sq as Dictionary)["members"] as Array):
		if is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n

## Живая свита босса (свой отряд без самого босса)
func _retinue_alive(b: Unit) -> int:
	return maxi(_alive(b.squad_id) - 1, 0)

# ─────────────────────────────────────────────────────────────────────────────
# ЗОНД БОССА
# ─────────────────────────────────────────────────────────────────────────────
func _bprobe(kind: String, d: Dictionary, line: String) -> void:
	GameManager.tm_event(kind, d)
	if not _Opt.boss_probe:
		return
	probe_events += 1
	var nowms: int = Unit.game_ms()
	if nowms - _plog_at > PROBE_LOG_WINDOW_MS:
		_plog_at = nowms
		_plog_used = 0
	_plog_used += 1
	if _plog_used > PROBE_LOG_BUDGET:
		return
	probe_lines += 1
	if GameManager.probes.print_lines:
		print("[ЗОНД %s] t=%.1f %s" % [kind, float(nowms) * 0.001, line])

func _order_probe(sid: int, what: String, at: Vector3, foe: int = 0) -> void:
	if not _Opt.boss_probe:
		return
	_bprobe("boss_order", {"sid": sid, "what": what, "foe": foe,
		"x": snappedf(at.x, 0.1), "z": snappedf(at.z, 0.1)},
		"приказ %s отряду %d → (%.0f, %.0f)%s" % [what, sid, at.x, at.z,
		(" враг %d" % foe) if foe > 0 else ""])

## Сводка раз в BOSS_PROBE_STATUS_SEC: здоровье, состояние, свита, откаты
func probe_status() -> void:
	if not _Opt.boss_probe:
		return
	var boss = GameManager.pig_boss
	if boss == null or not is_instance_valid(boss) or (boss as Unit).is_dead():
		return
	var b := boss as Unit
	var full: int = 0
	var sq: Variant = GameManager.squads.get(b.squad_id)
	if sq != null:
		full = int((sq as Dictionary).get("full", 0))
	_bprobe("boss_status", {"hp": snappedf(float(b.call("hp_frac")), 0.01),
		"hp_abs": int(b.current_health), "state": state_name(),
		"unit_state": SquadProbesRef._st_name(b.state),
		"retinue": _retinue_alive(b), "full": full,
		"ram": int(b.call("ram_phase")), "ram_in": snappedf(float(b.call("ram_ready_in")), 1.0),
		"horn_in": snappedf(float(b.call("horn_ready_in")), 1.0),
		"brawl": bool(b.call("brawling")), "suppressed": int(b.get("suppressed_n")),
		"escort": int(ram.get("escort", 0)), "orders": orders_batched,
		"x": snappedf(b.global_position.x, 0.1), "z": snappedf(b.global_position.z, 0.1)},
		"hp %.2f (%d), %s/%s, свита %d/%d, таран через %.0f с, горн через %.0f с, подавлено %d" % [
		float(b.call("hp_frac")), int(b.current_health), state_name(),
		SquadProbesRef._st_name(b.state), _retinue_alive(b), maxi(full - 1, 0),
		float(b.call("ram_ready_in")), float(b.call("horn_ready_in")), int(b.get("suppressed_n"))])

# ─────────────────────────────────────────────────────────────────────────────
# БЕГСТВО НА БАЗУ, ЛЕЧЕНИЕ, НОВАЯ СВИТА (ТЗ 29.10.2026, 2В)
# ─────────────────────────────────────────────────────────────────────────────
## true — такт занят бегством/лечением (приказов волне и тарана нет)
func _tick_flee(b: Unit, gai, w: Dictionary, now: float) -> bool:
	var hp: float = float(b.call("hp_frac"))
	if _st != ST_FLEE and _st != ST_RECOVER:
		var why: String = ""
		if hp <= _GobCfg.BOSS_FLEE_HP:
			why = "hp<=%.2f" % _GobCfg.BOSS_FLEE_HP
		var rem: int = int(b.get("ram_end_ms"))
		if rem > _ram_end_seen:
			_ram_end_seen = rem
			if why == "" and hp <= _GobCfg.BOSS_RAGE_HP:
				why = "после тарана, hp<=%.2f" % _GobCfg.BOSS_RAGE_HP
		if why == "":
			return false
		_begin_flee(b, gai, w, now, why)
		return true
	if _st == ST_FLEE:
		var bp: Vector3 = b.global_position
		if Vector2(bp.x - flee_home.x, bp.z - flee_home.z).length() <= _GobCfg.BOSS_BASE_ARRIVE_R:
			_arrive_base(b, gai)
		elif now - _flee_t >= _GobCfg.BOSS_REISSUE_SEC and b.state != Unit.State.MOVING:
			# Застрял или сбит с курса — тот же приказ ещё раз
			_flee_t = now
			b.call("flee_to", flee_home)
		return true
	# RECOVER: лечится; готов — в строй
	if hp >= _GobCfg.BOSS_BASE_READY_HP:
		_rejoin(b, gai)
		return false
	return true

func _begin_flee(b: Unit, gai, w: Dictionary, now: float, why: String) -> void:
	_st = ST_FLEE
	flees += 1
	last_flee_reason = why
	if not ram.is_empty():
		_ram_release("flee")
	_drop_retinue(b, gai, w)
	# Из волны — вон: её такт больше не ведёт отряд босса
	if not w.is_empty():
		(w["sids"] as Array).erase(b.squad_id)
	flee_home = _base_point(b, gai)
	_flee_t = now
	b.call("flee_to", flee_home)
	var bp: Vector3 = b.global_position
	_bprobe("boss_flee", {"hp": snappedf(float(b.call("hp_frac")), 0.01), "why": why,
		"dropped": retinue_dropped, "dropped_sid": dropped_sid,
		"dist": snappedf(Vector2(bp.x - flee_home.x, bp.z - flee_home.z).length(), 0.1),
		"x": snappedf(flee_home.x, 0.1), "z": snappedf(flee_home.z, 0.1)},
		"бегство на базу (%s): hp %.2f, свита сброшена %d → отряд %d, до базы %.0f м" % [
		why, float(b.call("hp_frac")), retinue_dropped, dropped_sid,
		Vector2(bp.x - flee_home.x, bp.z - flee_home.z).length()])

## Сбросить свиту: живые всадники отряда босса — в свой отряд (ранг тот же),
## он остаётся в волне вместо отряда босса и ведётся ею дальше
func _drop_retinue(b: Unit, gai, w: Dictionary) -> void:
	retinue_dropped = 0
	dropped_sid = 0
	var bsid: int = b.squad_id
	var sq: Variant = GameManager.squads.get(bsid)
	if sq == null:
		return
	var men: Array = []
	for m in ((sq as Dictionary)["members"] as Array):
		if is_instance_valid(m) and m != b and not (m as Unit).is_dead():
			men.append(m)
	if men.is_empty():
		return
	var nsid: int = GameManager.new_squad(b.faction, "goblin_rider")
	for key in ["level", "kills", "chosen", "pending", "bonuses", "perk_bits", "perk_n"]:
		if (sq as Dictionary).has(key):
			var v: Variant = (sq as Dictionary)[key]
			GameManager.squads[nsid][key] = v.duplicate() if (v is Array or v is Dictionary) else v
	for m in men:
		GameManager.remove_from_squad(m)
		GameManager.add_to_squad(nsid, m)
	GameManager.refresh_squad_banner(nsid)
	GameManager.refresh_squad_banner(bsid)
	retinue_dropped = men.size()
	dropped_sid = nsid
	if not w.is_empty():
		(w["sids"] as Array).append(nsid)
		var stage: String = String(w.get("stage", ""))
		if (stage == "march" or stage == "engage" or stage == "flank") and gai.has_method("_engage_squad"):
			gai._engage_squad(nsid, w)

## База: от главной хаты лагеря орды на BOSS_BASE_BACK к краю (прочь от
## босса — не через лагерь), на проходимую клетку
func _base_point(b: Unit, gai) -> Vector3:
	var v: Vector3 = gai.village
	var bp: Vector3 = b.global_position
	var away := Vector3(v.x - bp.x, 0.0, v.z - bp.z)
	away = away.normalized() if away.length_squared() > 1.0 else Vector3.BACK
	var p: Vector3 = v + away * _GobCfg.BOSS_BASE_BACK
	var np: Vector2 = GameManager.nearest_passable(p.x, p.z)
	if np.is_finite():
		return Vector3(np.x, 0.0, np.y)
	return GameManager.land_target(p)

func _arrive_base(b: Unit, gai) -> void:
	_st = ST_RECOVER
	base_arrivals += 1
	b.call("recover_at_base")
	retinue_refilled = 0
	var m = GameManager.main
	if m != null and is_instance_valid(m) and m.has_method("refill_boss_retinue"):
		retinue_refilled = int(m.call("refill_boss_retinue", b.squad_id, b.global_position))
	_bprobe("boss_base", {"hp": snappedf(float(b.call("hp_frac")), 0.01),
		"refilled": retinue_refilled, "retinue": _retinue_alive(b)},
		"на базе: hp %.2f, лечится; новая свита +%d (всего %d)" % [
		float(b.call("hp_frac")), retinue_refilled, _retinue_alive(b)])

## В строй: идущая волна (поход, бой, фланг) — туда; нет — на площадку сбора
func _rejoin(b: Unit, gai) -> void:
	rejoins += 1
	b.call("resume_command")
	_st = ST_IDLE
	var bsid: int = b.squad_id
	var into: Dictionary = {}
	for wv in gai.waves:
		var st: String = String((wv as Dictionary).get("stage", ""))
		if st == "march" or st == "engage" or st == "flank":
			into = wv
	if not into.is_empty():
		if not (into["sids"] as Array).has(bsid):
			(into["sids"] as Array).append(bsid)
		if gai.has_method("_engage_squad"):
			gai._engage_squad(bsid, into)
		_st = ST_COMMAND
	elif gai.has_method("_to_muster"):
		gai._to_muster(bsid)
	_bprobe("boss_rejoin", {"hp": snappedf(float(b.call("hp_frac")), 0.01),
		"retinue": _retinue_alive(b), "wave": int(into.get("id", 0)) if not into.is_empty() else 0},
		"в строй: hp %.2f, свита %d, %s" % [float(b.call("hp_frac")), _retinue_alive(b),
		("волна %d" % int(into.get("id", 0))) if not into.is_empty() else "на площадку сбора"])

## Укрытие: центр волны минус курс × BOSS_SHELTER_DIST. Если босс в окружении
## (чужие во всех четырёх секторах у него), первый отрезок — через самый
## свободный сектор; без волны — прочь от ближайшей плотности
func _shelter_point(b: Unit, gai, w: Dictionary) -> Vector3:
	var bp: Vector3 = b.global_position
	var fac: int = b.faction
	var army = GameManager.army
	var course: Vector3 = Vector3.FORWARD
	var centre: Vector3 = bp
	if not w.is_empty():
		var wc: Vector3 = gai._wave_centre(w)
		if wc.x != INF:
			centre = wc
		course = w.get("dir", Vector3.FORWARD) as Vector3
	var shelter: Vector3 = centre - course * _GobCfg.BOSS_SHELTER_DIST
	# Четыре сектора вокруг босса: самый свободный
	var dirs: Array = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var best_i := -1
	var best_n := 1 << 30
	var min_n := 1 << 30
	var r: float = _GobCfg.BOSS_ESCAPE_R
	for i in range(dirs.size()):
		var q: Vector3 = bp + (dirs[i] as Vector3) * r
		var n: int = army.enemy_count(q.x, q.z, r, fac)
		min_n = mini(min_n, n)
		if n < best_n:
			best_n = n
			best_i = i
	density_calls += dirs.size()
	var to_shelter := Vector3(shelter.x - bp.x, 0.0, shelter.z - bp.z)
	# Окружён (во всех секторах чужие): идём через самый свободный, иначе прямо
	if min_n > 0 and best_i >= 0:
		var esc: Vector3 = bp + (dirs[best_i] as Vector3) * r * 2.0
		var np: Vector2 = GameManager.nearest_passable(esc.x, esc.z)
		if np.is_finite():
			return Vector3(np.x, 0.0, np.y)
		return esc
	if to_shelter.length_squared() < 4.0:
		return bp
	var np2: Vector2 = GameManager.nearest_passable(shelter.x, shelter.z)
	if np2.is_finite():
		return Vector3(np2.x, 0.0, np2.y)
	return shelter
