extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНДЫ ОТРЯДОВ: «БЕГ НА МЕСТЕ», РАЗРЫВ ОТРЯДА, СБРОС ПРИКАЗА ИГРОКА
## (ТЗ 25.10.2026, блок 5; ручка perf_config.squad_probes)
## ═══════════════════════════════════════════════════════════════════════════
## Скриншот владельца: часть отряда держит место, остальные «бегут на месте»
## (лента ходьбы без продвижения), а приказ игрока местами слетает. Зонды не
## чинят ничего — они называют ВИНОВНИКА в логе партии, чтобы следующую
## правку делать по факту, а не по догадке.
##
##   stuck_running      — у бойца в слоте лента ходьбы, а за STUCK_WINDOW_MS
##                        он сместился меньше STUCK_MIN_DIST, STUCK_HITS окон
##                        подряд. Меряет ЯДРО (ArmyCore.ProbeStuckRows) одним
##                        проходом; здесь — сводка по отряду: сколько, в каком
##                        состоянии, в коробке ли, далеко ли до своего места
##                        и до точки хода, бег ли, приказ ли игрока.
##   squad_split        — живые бойцы отряда легли в две и больше кучи (связность
##                        по клеткам SPLIT_CELL), две крупнейшие дальше
##                        SPLIT_GAP друг от друга и каждая не меньше SPLIT_SHARE.
##   order_override_bug — приказ игрока (замок цели или замок движения) снят
##                        или перебит ВНУТРЕННЕЙ механикой. Точки снятия
##                        размечены в Unit (_probe_override) причиной; вызвавшая
##                        функция берётся из get_stack() (в отладочной сборке и
##                        редакторе; в экспорте — пусто).
##
## РАСШИРЕННЫЕ ЗОНДЫ ДЛЯ .exe (ТЗ 29.10.2026, ручка perf_config.probes_ext):
##   banner_pass        — пал знаменосец, знамя у соседа (кто, откуда, сколько живых);
##   standard_pass/drop/pickup — штандарт за общий опыт: передача соседу, на
##                        землю (отряд выбит), подбор;
##   squad_retreat      — отряд начал отход (раз на отряд за RETREAT_LOG_MS):
##                        паника ли, источник приказа, живых;
##   probe_summary      — раз в SUMMARY_MS: приросты всех зондов (бег на месте,
##                        разрывы, сбросы приказов, знамёна, отходы) и навигации
##                        (A*, промахи кэша, отказы, худший вызов, вызволения).
##
## ВЫВОД: строка «[ЗОНД вид] …» в лог (user://logs/…) и событие tm_event —
## оно уходит в performance_log_*.json. Сводки ограничены по частоте на отряд
## и глобально (LOG_BUDGET строк за LOG_WINDOW_MS): зонд не должен сам стать
## тем, что тормозит партию.
##
## ЦЕНА: stuck — один вызов в ядро раз в STUCK_TICK_MS; split — один отряд за
## такт по кругу (≤ 60 бойцов, словарь клеток); override — только на событии.
## Покадрового пути нет.

const _Opt := preload("res://scripts/perf_config.gd")

const STUCK_TICK_MS := 250
const STUCK_WINDOW_MS := 500
const STUCK_MIN_DIST := 0.15
const STUCK_HITS := 2
## Отряд попадает в сводку, когда «бегут на месте» не меньше стольких
const STUCK_MIN_MEN := 3
const STUCK_LOG_MS := 10000

const SPLIT_TICK_MS := 100
const SPLIT_CELL := 3.0
const SPLIT_GAP := 8.0
const SPLIT_SHARE := 0.2
const SPLIT_MIN_MEN := 8
const SPLIT_LOG_MS := 15000

const OVERRIDE_FLUSH_MS := 3000

## Метка источника текущего приказа для зонда order_override_bug: ставит
## вызывающий (SquadCommander._issue — «attack_move», сдача вызволения,
## сплочённость) на время своего command_*; в экспортной сборке стека нет
var ctx: String = ""

const LOG_WINDOW_MS := 10000
const LOG_BUDGET := 30

## Счётчики стендам и телеметрии
var stuck_reports: int = 0
var stuck_units_total: int = 0
var split_reports: int = 0
var override_reports: int = 0
var override_notes: int = 0
## Последние записи (стендам): Dictionary с полями сводки
var last_stuck: Dictionary = {}
var last_split: Dictionary = {}
var last_override: Dictionary = {}
## Печатать ли строки в лог (стенды гасят, чтобы не забить вывод)
var print_lines: bool = true

var _stuck_next: int = 0
var _split_next: int = 0
var _split_keys: Array = []
var _split_i: int = 0
var _split_state: Dictionary = {}     # sid → game_ms последней сводки (0 — цел)
var _stuck_last: Dictionary = {}      # sid → game_ms последней сводки
var _ovr: Dictionary = {}             # "sid|reason|caller" → [sid, reason, caller, count, stat_id]
var _ovr_next: int = 0
var _log_window_at: int = 0
var _log_used: int = 0

func reset() -> void:
	_stuck_next = 0
	_split_next = 0
	_split_keys.clear()
	_split_i = 0
	_split_state.clear()
	_stuck_last.clear()
	_ovr.clear()
	_rip.clear()
	rip_cures = 0
	stuck_reports = 0
	stuck_units_total = 0
	split_reports = 0
	override_reports = 0
	override_notes = 0
	banner_passes = 0
	standard_passes = 0
	standard_drops = 0
	standard_pickups = 0
	retreat_reports = 0
	unstuck_notes = 0
	summaries = 0
	_retreat_last.clear()
	_exit_watch.clear()
	_exit_next = 0
	exit_watches = 0
	exit_reports = 0
	_sum_next = 0
	_sum_prev.clear()

# ─────────────────────────────────────────────────────────────────────────────
func tick() -> void:
	# Лечение «бега на месте» (run_in_place_cure) берёт ту же сводку ядра, что
	# и зонд: работает и при выключенном зонде, печать — только при нём
	if not _Opt.squad_probes and not _Opt.run_in_place_cure and not _Opt.probes_ext:
		return
	var now: int = Unit.game_ms()
	if _Opt.probes_ext and now >= _sum_next:
		if _sum_next > 0:
			_tick_summary(now)
		else:
			_sum_prev = _snapshot()
		_sum_next = now + SUMMARY_MS
	if _Opt.probes_ext and not _exit_watch.is_empty() and now >= _exit_next:
		_exit_next = now + EXIT_SAMPLE_MS
		_tick_castle_exit(now)
	if not _Opt.squad_probes and not _Opt.run_in_place_cure:
		return
	if now >= _stuck_next:
		_stuck_next = now + STUCK_TICK_MS
		_tick_stuck(now)
	if not _Opt.squad_probes:
		return
	if now >= _split_next:
		_split_next = now + SPLIT_TICK_MS
		_tick_split(now)
	if now >= _ovr_next:
		_ovr_next = now + OVERRIDE_FLUSH_MS
		_flush_override(now)

# ─────────────────────────────────────────────────────────────────────────────
# ВЫХОД ИЗ ЗАМКА (ТЗ 30.10.2026, п. 3): «после лечения и выхода отряд почти
# сразу бежит на месте» — синтетика (qa_castle_exit/Probe, 9 сценариев) не
# воспроизводит, сводка ядра (лента ходьбы) после выпусков почти молчит. Зонд
# для партии .exe: EXIT_WATCH_MS после Castle._release_members раз в секунду —
# кто в MOVING сдвинулся меньше EXIT_STILL_M, с флагами; одна строка на выпуск
# ─────────────────────────────────────────────────────────────────────────────
const EXIT_WATCH_MS := 20000
const EXIT_SAMPLE_MS := 1000
const EXIT_STILL_M := 0.3
const EXIT_MIN_MEN := 3
var _exit_watch: Dictionary = {}      # sid → {t0, pos: {id: Vector3}, hits: {id: n}, told}
var _exit_next: int = 0
var exit_watches: int = 0             # стендам
var exit_reports: int = 0

func watch_release(sid: int) -> void:
	if not _Opt.probes_ext or sid <= 0:
		return
	exit_watches += 1
	_exit_watch[sid] = {"t0": Unit.game_ms(), "pos": {}, "hits": {}, "told": false}

func _tick_castle_exit(now: int) -> void:
	var done: Array = []
	for sid in _exit_watch:
		var w: Dictionary = _exit_watch[sid]
		if now - int(w["t0"]) > EXIT_WATCH_MS or not GameManager.squads.has(sid):
			done.append(sid)
			continue
		var pos: Dictionary = w["pos"]
		var hits: Dictionary = w["hits"]
		var stuck: Array = []
		var alive := 0
		for raw in (GameManager.squads[sid] as Dictionary)["members"]:
			if raw == null or not is_instance_valid(raw):
				continue
			var u := raw as Unit
			if u == null or u.is_dead() or u.garrisoned:
				continue
			alive += 1
			var id: int = u.get_instance_id()
			var p: Vector3 = u.global_position
			var pv: Variant = pos.get(id)
			pos[id] = p
			if pv == null:
				continue
			var d: float = Vector2(p.x - (pv as Vector3).x, p.z - (pv as Vector3).z).length()
			var cst: int = GameManager.army.state_of(u._soa) if u._soa >= 0 else -1
			if (u.state == Unit.State.MOVING or cst == Unit.State.MOVING) and d < EXIT_STILL_M:
				hits[id] = int(hits.get(id, 0)) + 1
				if int(hits[id]) >= 2:
					stuck.append(u)
			else:
				hits.erase(id)
		if bool(w["told"]) or stuck.size() < EXIT_MIN_MEN:
			continue
		w["told"] = true
		exit_reports += 1
		var u0 := stuck[0] as Unit
		var sprint := 0
		var retr := 0
		var panic := 0
		var arrived := 0
		var goal_d := 0.0
		for s in stuck:
			var su := s as Unit
			sprint += 1 if su.sprinting else 0
			retr += 1 if su.retreating else 0
			panic += 1 if su._panicked else 0
			arrived += 1 if su._squad_arrived else 0
			goal_d += Vector2(su.move_target.x - su.global_position.x, su.move_target.z - su.global_position.z).length()
		goal_d /= float(stuck.size())
		var sq: Dictionary = GameManager.squads[sid]
		_emit("castle_exit", {"sid": sid, "type": String(sq.get("type", "")), "stuck": stuck.size(),
			"alive": alive, "after_s": snappedf(float(now - int(w["t0"])) * 0.001, 0.1),
			"st": _st_name(u0.state), "core_st": _st_name(GameManager.army.state_of(u0._soa)) if u0._soa >= 0 else "-",
			"sprint": sprint, "retreat": retr, "panic": panic, "arrived": arrived,
			"no_control": GameManager.squad_no_control(sid), "goal_d": snappedf(goal_d, 0.1),
			"x": snappedf(u0.global_position.x, 0.1), "z": snappedf(u0.global_position.z, 0.1)},
			"отряд %d (%s) через %.0f с после выхода: %d из %d в MOVING стоят; бег %d, отход %d, паника %d, прибыл %d, до цели ~%.1f м, без управления %s, (%.0f, %.0f)" % [
			sid, String(sq.get("type", "")), float(now - int(w["t0"])) * 0.001, stuck.size(), alive,
			sprint, retr, panic, arrived, goal_d, str(GameManager.squad_no_control(sid)),
			u0.global_position.x, u0.global_position.z])
	for s2 in done:
		_exit_watch.erase(s2)

func _emit(kind: String, d: Dictionary, line: String) -> void:
	GameManager.tm_event(kind, d)
	if not print_lines:
		return
	var now: int = Unit.game_ms()
	if now - _log_window_at > LOG_WINDOW_MS:
		_log_window_at = now
		_log_used = 0
	_log_used += 1
	if _log_used > LOG_BUDGET:
		return
	print("[ЗОНД %s] t=%.1f %s" % [kind, float(now) * 0.001, line])

static func _st_name(st: int) -> String:
	var keys: Array = Unit.State.keys()
	return String(keys[st]) if st >= 0 and st < keys.size() else str(st)

# ─────────────────────────────────────────────────────────────────────────────
# БЕГ НА МЕСТЕ
# ─────────────────────────────────────────────────────────────────────────────
func _tick_stuck(now: int) -> void:
	var rows: PackedInt32Array = GameManager.army.probe_stuck_rows(now, STUCK_MIN_DIST,
		STUCK_WINDOW_MS, STUCK_HITS, Unit.State.MOVING)
	if rows.is_empty():
		if _Opt.run_in_place_cure:
			_rip_expire(now)
		return
	var ru: Array = GameManager._row_units
	var per: Dictionary = {}
	for r in rows:
		if r < 0 or r >= ru.size():
			continue
		var raw = ru[r]
		# Правило 5: живость на сырой ссылке
		if raw == null or not is_instance_valid(raw):
			continue
		var u := raw as Unit
		if u == null or u.is_dead():
			continue
		if _Opt.run_in_place_cure:
			_rip_note(u, now)
		if u.squad_id <= 0:
			continue
		var lst: Variant = per.get(u.squad_id)
		if lst == null:
			lst = []
			per[u.squad_id] = lst
		(lst as Array).append(u)
	if _Opt.run_in_place_cure:
		_rip_expire(now)
	if not _Opt.squad_probes:
		return
	for sid in per:
		var men: Array = per[sid]
		if men.size() < STUCK_MIN_MEN:
			continue
		var lastv: Variant = _stuck_last.get(sid)
		if lastv != null and now - int(lastv) < STUCK_LOG_MS:
			continue
		_stuck_last[sid] = now
		_report_stuck(int(sid), men)

## ── ЛЕЧЕНИЕ «БЕГА НА МЕСТЕ» (ТЗ 27.10.2026, четвёртое письмо, п. 1) ──────
## Ядро отдаёт застрявшего в каждом окне (раз в STUCK_WINDOW_MS), пока он
## стоит с лентой ходьбы. Здесь — с какого мига он стоит (первая отметка) и
## когда видели последний раз: пропал из сводки дольше RIP_GAP_MS — пошёл,
## запись снимается. Стоит дольше RIP_CURE_MS — Unit.cure_run_in_place, и
## отсчёт заново (повтор в окне 20 с сам решает «встать здесь»)
const RIP_CURE_MS := 2000
const RIP_GAP_MS := 1200
var _rip: Dictionary = {}           # instance_id → [первая отметка, последняя, узел]
var rip_cures: int = 0              # стендам

func _rip_note(u: Unit, now: int) -> void:
	var id: int = u.get_instance_id()
	var rec: Variant = _rip.get(id)
	if rec == null:
		_rip[id] = [now, now, u]
		return
	var a: Array = rec
	a[1] = now
	if now - int(a[0]) >= RIP_CURE_MS:
		_rip.erase(id)
		if u.garrisoned:
			return
		u.cure_run_in_place()
		rip_cures += 1

func _rip_expire(now: int) -> void:
	if _rip.is_empty():
		return
	var gone: Array = []
	for id in _rip:
		var a: Array = _rip[id]
		var raw = a[2]
		if now - int(a[1]) > RIP_GAP_MS or raw == null or not is_instance_valid(raw):
			gone.append(id)
	for id2 in gone:
		_rip.erase(id2)

func _report_stuck(sid: int, men: Array) -> void:
	var states: Dictionary = {}
	var in_box := 0
	var sprint := 0
	var porder := 0
	var lock := 0
	var contact := 0
	var goal_d: Array = []
	var move_d: Array = []
	for m in men:
		var u: Unit = m
		var sn: String = _st_name(int(u.state))
		states[sn] = int(states.get(sn, 0)) + 1
		var p: Vector3 = u.position if u._local_xform else u.global_position
		if u._box_on:
			in_box += 1
			if u._box_goal.x != INF:
				goal_d.append(Vector2(p.x - u._box_goal.x, p.z - u._box_goal.z).length())
		if u.sprinting:
			sprint += 1
		if u.player_order_active():
			porder += 1
		if u.target_lock:
			lock += 1
		if u._enemy_contact:
			contact += 1
		if u.state == Unit.State.MOVING:
			var g: Vector3 = u.march_goal()
			move_d.append(Vector2(p.x - g.x, p.z - g.z).length())
	goal_d.sort()
	move_d.sort()
	# Где это было (лог партии 27.10: без координат «бег на месте» по 8 минут
	# воспроизвести было нечем) — центр застрявших и точка хода первого из них
	var at: Vector3 = _centre(men, range(men.size()))
	var to := Vector3.INF
	for m2 in men:
		if (m2 as Unit).state == Unit.State.MOVING:
			to = (m2 as Unit).march_goal()
			break
	var alive: int = _alive_count(sid)
	var d := {
		"sid": sid, "type": GameManager.squad_type(sid),
		"fac": int((GameManager.squads[sid] as Dictionary).get("faction", 0)) if GameManager.squads.has(sid) else -1,
		"stuck": men.size(), "alive": alive, "states": states,
		"in_box": in_box, "sprint": sprint, "player_order": porder, "lock": lock, "contact": contact,
		"box_goal_med": snappedf(float(goal_d[goal_d.size() / 2]), 0.01) if not goal_d.is_empty() else -1.0,
		"move_goal_med": snappedf(float(move_d[move_d.size() / 2]), 0.01) if not move_d.is_empty() else -1.0,
		"in_combat": GameManager.squad_in_combat(sid),
		"at": [snappedf(at.x, 0.1), snappedf(at.z, 0.1)],
		"to": [snappedf(to.x, 0.1), snappedf(to.z, 0.1)] if to.x != INF else [],
	}
	last_stuck = d
	stuck_reports += 1
	stuck_units_total += men.size()
	_emit("stuck_running", d, "отряд %d (%s, сторона %d): бегут на месте %d из %d; состояния %s; в коробке %d (до места %.2f м), к точке хода %.2f м, бег %d, приказ игрока %d, замок %d, в контакте %d, бой %s; у (%.1f, %.1f) → %s" % [
		sid, String(d["type"]), int(d["fac"]), men.size(), alive, str(states), in_box,
		float(d["box_goal_med"]), float(d["move_goal_med"]), sprint, porder, lock, contact, str(d["in_combat"]),
		at.x, at.z, str(d["to"])])

func _alive_count(sid: int) -> int:
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return 0
	var n := 0
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n

# ─────────────────────────────────────────────────────────────────────────────
# РАЗРЫВ ОТРЯДА
# ─────────────────────────────────────────────────────────────────────────────
func _tick_split(now: int) -> void:
	if _split_i >= _split_keys.size():
		_split_keys = GameManager.squads.keys()
		_split_i = 0
		if _split_keys.is_empty():
			return
	var sid: int = int(_split_keys[_split_i])
	_split_i += 1
	if not GameManager.squads.has(sid):
		return
	# Гноллы патрулируют пень поодиночке, по кольцу в обе стороны
	# (Gnoll._tick_patrol) — «разрыв» у них штатный: в логе партии 26.10
	# 108 из 553 сводок, все вне боя
	if GameManager.squad_type(sid) == "gnoll":
		return
	var res: Dictionary = split_of(sid)
	if res.is_empty():
		_split_state.erase(sid)
		return
	var lastv: Variant = _split_state.get(sid)
	if lastv != null and now - int(lastv) < SPLIT_LOG_MS:
		return
	_split_state[sid] = now
	last_split = res
	split_reports += 1
	_emit("squad_split", res, "отряд %d (%s, сторона %d): порван на %d куч, крупнейшие %d и %d бойцов в %.1f м друг от друга; состояния %s / %s; бой %s; кучи у %s и %s" % [
		sid, String(res["type"]), int(res["fac"]), int(res["parts"]), int(res["a"]), int(res["b"]),
		float(res["gap"]), str(res["states_a"]), str(res["states_b"]), str(res["in_combat"]),
		str(res["at_a"]), str(res["at_b"])])

## Разбор связности отряда; пустой ответ — отряд цел. Публичный: стенды
## зовут его напрямую. Состав — напрямую из squads (squad_members распускает
## опустевший отряд в геттере)
func split_of(sid: int) -> Dictionary:
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return {}
	var men: Array = []
	for m in ((sq as Dictionary)["members"] as Array):
		if m == null or not is_instance_valid(m):
			continue
		var u: Unit = m
		if u.is_dead() or u.garrisoned:
			continue
		men.append(u)
	var n: int = men.size()
	if n < SPLIT_MIN_MEN:
		return {}
	# Клетки → индексы бойцов
	var cells: Dictionary = {}
	for i in range(n):
		var u: Unit = men[i]
		var p: Vector3 = u.position if u._local_xform else u.global_position
		var key := Vector2i(int(floor(p.x / SPLIT_CELL)), int(floor(p.z / SPLIT_CELL)))
		var lst: Variant = cells.get(key)
		if lst == null:
			lst = []
			cells[key] = lst
		(lst as Array).append(i)
	# Связные компоненты клеток (8 соседей)
	var comp: Dictionary = {}
	var parts: Array = []
	for c in cells:
		if comp.has(c):
			continue
		var idx: int = parts.size()
		var members: Array = []
		var stack: Array = [c]
		comp[c] = idx
		while not stack.is_empty():
			var cc: Vector2i = stack.pop_back()
			members.append_array(cells[cc] as Array)
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var nb := Vector2i(cc.x + dx, cc.y + dz)
					if cells.has(nb) and not comp.has(nb):
						comp[nb] = idx
						stack.append(nb)
		parts.append(members)
	if parts.size() < 2:
		return {}
	parts.sort_custom(func(a, b): return (a as Array).size() > (b as Array).size())
	var pa: Array = parts[0]
	var pb: Array = parts[1]
	var need: int = maxi(3, int(ceil(float(n) * SPLIT_SHARE)))
	if pb.size() < need:
		return {}
	var ca: Vector3 = _centre(men, pa)
	var cb: Vector3 = _centre(men, pb)
	var gap: float = Vector2(ca.x - cb.x, ca.z - cb.z).length()
	if gap < SPLIT_GAP:
		return {}
	return {
		"sid": sid, "type": GameManager.squad_type(sid),
		"fac": int((sq as Dictionary).get("faction", 0)),
		"parts": parts.size(), "a": pa.size(), "b": pb.size(), "alive": n,
		"gap": snappedf(gap, 0.1),
		"states_a": _states(men, pa), "states_b": _states(men, pb),
		"in_combat": GameManager.squad_in_combat(sid),
		"at_a": [snappedf(ca.x, 0.1), snappedf(ca.z, 0.1)],
		"at_b": [snappedf(cb.x, 0.1), snappedf(cb.z, 0.1)],
	}

func _centre(men: Array, idx: Array) -> Vector3:
	var s := Vector3.ZERO
	for i in idx:
		var u: Unit = men[int(i)]
		s += u.position if u._local_xform else u.global_position
	return s / float(maxi(idx.size(), 1))

func _states(men: Array, idx: Array) -> Dictionary:
	var out: Dictionary = {}
	for i in idx:
		var sn: String = _st_name(int((men[int(i)] as Unit).state))
		out[sn] = int(out.get(sn, 0)) + 1
	return out

# ─────────────────────────────────────────────────────────────────────────────
# СБРОС ПРИКАЗА ИГРОКА
# ─────────────────────────────────────────────────────────────────────────────
## Зовёт Unit._probe_override на событии: боец игрока, чей приказ перебит
## внутренней механикой. Копится по (отряд, причина, вызов) и сливается в лог
## раз в OVERRIDE_FLUSH_MS одной строкой на ключ
func note_override(u: Unit, reason: String, caller: String) -> void:
	override_notes += 1
	var key: String = "%d|%s|%s" % [u.squad_id, reason, caller]
	var rec: Variant = _ovr.get(key)
	if rec == null:
		_ovr[key] = [u.squad_id, reason, caller, 1, String(u.stat_id), _st_name(int(u.state))]
	else:
		(rec as Array)[3] = int((rec as Array)[3]) + 1

func _flush_override(_now: int) -> void:
	if _ovr.is_empty():
		return
	for key in _ovr:
		var r: Array = _ovr[key]
		var d := {"sid": int(r[0]), "reason": String(r[1]), "caller": String(r[2]),
			"units": int(r[3]), "type": String(r[4]), "state": String(r[5])}
		last_override = d
		override_reports += 1
		_emit("order_override_bug", d, "отряд %d (%s): приказ игрока снят — причина «%s», вызов %s, бойцов %d (состояние %s)" % [
			int(r[0]), String(r[4]), String(r[1]), String(r[2]) if String(r[2]) != "" else "?", int(r[3]), String(r[5])])
	_ovr.clear()

## Немедленно слить накопленное (стенды)
func flush_now() -> void:
	_flush_override(Unit.game_ms())

# ─────────────────────────────────────────────────────────────────────────────
# РАСШИРЕННЫЕ ЗОНДЫ (ТЗ 29.10.2026, ручка probes_ext) — только события
# ─────────────────────────────────────────────────────────────────────────────
const RETREAT_LOG_MS := 8000
const SUMMARY_MS := 60000
var banner_passes: int = 0
var standard_passes: int = 0
var standard_drops: int = 0
var standard_pickups: int = 0
var retreat_reports: int = 0
var unstuck_notes: int = 0
var summaries: int = 0
var last_banner: Dictionary = {}
var last_standard: Dictionary = {}
var last_retreat: Dictionary = {}
var last_summary: Dictionary = {}
var _retreat_last: Dictionary = {}     # sid → game_ms последней сводки
var _sum_next: int = 0
var _sum_prev: Dictionary = {}

static func _fac_name(f: int) -> String:
	match f:
		Constants.FACTION_PLAYER: return "игрок"
		Constants.FACTION_GOBLIN: return "орда"
	return "красные"

## Пал знаменосец: знамя ушло к ближайшему живому (GameManager.remove_from_squad)
func note_banner(sid: int, fallen: Unit, heir: Variant) -> void:
	if not _Opt.probes_ext:
		return
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return
	var alive: int = _alive_count(sid)
	var heir_ok: bool = heir != null and is_instance_valid(heir)
	var d := {"sid": sid, "fac": int((sq as Dictionary).get("faction", -1)),
		"type": String((sq as Dictionary).get("type", "")), "alive": alive,
		"heir": heir_ok, "elite": bool((sq as Dictionary).get("elite", false)),
		"lvl": int((sq as Dictionary).get("level", 0))}
	if fallen != null and is_instance_valid(fallen):
		var fp: Vector3 = fallen.global_position
		d["x"] = snappedf(fp.x, 0.1)
		d["z"] = snappedf(fp.z, 0.1)
	banner_passes += 1
	last_banner = d
	_emit("banner_pass", d, "отряд %d (%s, %s, ранг %d): пал знаменосец — знамя %s, живых %d" % [
		sid, String(d["type"]), _fac_name(int(d["fac"])), int(d["lvl"]),
		"у соседа" if heir_ok else "без носителя", alive])

## Штандарт за общий опыт: pass — сосед подхватил, drop — на землю (отряд
## выбит), pickup — подобрал боец (RelicManager._tick_carriers)
func note_standard(kind: String, sid: int, level: int, who: Variant) -> void:
	if not _Opt.probes_ext:
		return
	var d := {"kind": kind, "sid": sid, "lvl": level,
		"alive": _alive_count(sid) if sid > 0 else 0}
	if who != null and is_instance_valid(who):
		var u := who as Unit
		d["who_sid"] = u.squad_id
		d["fac"] = u.faction
		d["x"] = snappedf(u.global_position.x, 0.1)
		d["z"] = snappedf(u.global_position.z, 0.1)
	match kind:
		"pass": standard_passes += 1
		"drop": standard_drops += 1
		_: standard_pickups += 1
	last_standard = d
	var what: String = {"pass": "носитель пал — штандарт у соседа",
		"drop": "отряд выбит — штандарт на земле",
		"pickup": "штандарт подобран"}.get(kind, kind)
	_emit("standard_" + kind, d, "отряд %d: %s (ур. %d, живых %d)" % [sid, what, level, int(d["alive"])])

## Отряд начал отход (Unit.begin_retreat первого бойца) — раз на отряд за окно
func note_retreat(u: Unit) -> void:
	if not _Opt.probes_ext or u == null or u.squad_id <= 0:
		return
	var sid: int = u.squad_id
	var now: int = Unit.game_ms()
	var last: Variant = _retreat_last.get(sid)
	if last != null and now - int(last) < RETREAT_LOG_MS:
		return
	_retreat_last[sid] = now
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return
	var full: int = maxi(int((sq as Dictionary).get("full", 0)), 1)
	var alive: int = _alive_count(sid)
	var src: String = ctx if ctx != "" else String(_Opt.cmd_src)
	var d := {"sid": sid, "fac": u.faction, "type": String((sq as Dictionary).get("type", "")),
		"alive": alive, "full": full, "panic": GameManager.squad_panicked(sid),
		"src": src, "player": u.faction == Constants.FACTION_PLAYER,
		"x": snappedf(u.global_position.x, 0.1), "z": snappedf(u.global_position.z, 0.1)}
	retreat_reports += 1
	last_retreat = d
	_emit("squad_retreat", d, "отряд %d (%s, %s): отход — живых %d/%d, паника %s, источник «%s»" % [
		sid, String(d["type"]), _fac_name(u.faction), alive, full, bool(d["panic"]),
		src if src != "" else "?"])

## Вызволение застрявшего (Unit, событие unstuck) — для сводки
func note_unstuck() -> void:
	unstuck_notes += 1

func _snapshot() -> Dictionary:
	return {"stuck": stuck_reports, "stuck_units": stuck_units_total, "split": split_reports,
		"override": override_reports, "banner": banner_passes,
		"std": standard_passes + standard_drops + standard_pickups,
		"retreat": retreat_reports, "unstuck": unstuck_notes, "rip_cures": rip_cures,
		"nav_calls": int(_Opt.nav_calls), "nav_usec": int(_Opt.nav_usec),
		"nav_built": int(GameManager.nav_routes_built), "nav_failed": int(GameManager.nav_routes_failed),
		"nav_miss_key": int(GameManager.nav_miss_key), "nav_miss_reuse": int(GameManager.nav_miss_reuse)}

## Сводка за минуту: приросты счётчиков зондов и навигации, худший A*
func _tick_summary(_now: int) -> void:
	var cur: Dictionary = _snapshot()
	var d: Dictionary = {}
	for k in cur:
		d[k] = int(cur[k]) - int(_sum_prev.get(k, 0))
	d["nav_worst_us"] = int(GameManager.nav_worst_usec)
	d["nav_avg_us"] = int(d["nav_usec"]) / maxi(int(d["nav_calls"]), 1)
	GameManager.nav_worst_usec = 0
	_sum_prev = cur
	summaries += 1
	last_summary = d
	_emit("probe_summary", d, "за минуту: бег на месте %d сводок (%d бойцов), лечений %d, разрывов %d, сбросов приказа %d, знамён %d, штандартов %d, отходов %d, вызволений %d | A* %d (ср. %d мкс, худший %d), маршрутов %d, отказов %d, промахов кэша %d/%d" % [
		int(d["stuck"]), int(d["stuck_units"]), int(d["rip_cures"]), int(d["split"]),
		int(d["override"]), int(d["banner"]), int(d["std"]), int(d["retreat"]), int(d["unstuck"]),
		int(d["nav_calls"]), int(d["nav_avg_us"]), int(d["nav_worst_us"]), int(d["nav_built"]),
		int(d["nav_failed"]), int(d["nav_miss_key"]), int(d["nav_miss_reuse"])])
