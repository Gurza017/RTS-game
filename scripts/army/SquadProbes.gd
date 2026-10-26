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
	stuck_reports = 0
	stuck_units_total = 0
	split_reports = 0
	override_reports = 0
	override_notes = 0

# ─────────────────────────────────────────────────────────────────────────────
func tick() -> void:
	if not _Opt.squad_probes:
		return
	var now: int = Unit.game_ms()
	if now >= _stuck_next:
		_stuck_next = now + STUCK_TICK_MS
		_tick_stuck(now)
	if now >= _split_next:
		_split_next = now + SPLIT_TICK_MS
		_tick_split(now)
	if now >= _ovr_next:
		_ovr_next = now + OVERRIDE_FLUSH_MS
		_flush_override(now)

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
		if u == null or u.is_dead() or u.squad_id <= 0:
			continue
		var lst: Variant = per.get(u.squad_id)
		if lst == null:
			lst = []
			per[u.squad_id] = lst
		(lst as Array).append(u)
	for sid in per:
		var men: Array = per[sid]
		if men.size() < STUCK_MIN_MEN:
			continue
		var lastv: Variant = _stuck_last.get(sid)
		if lastv != null and now - int(lastv) < STUCK_LOG_MS:
			continue
		_stuck_last[sid] = now
		_report_stuck(int(sid), men)

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
	var alive: int = _alive_count(sid)
	var d := {
		"sid": sid, "type": GameManager.squad_type(sid),
		"fac": int((GameManager.squads[sid] as Dictionary).get("faction", 0)) if GameManager.squads.has(sid) else -1,
		"stuck": men.size(), "alive": alive, "states": states,
		"in_box": in_box, "sprint": sprint, "player_order": porder, "lock": lock, "contact": contact,
		"box_goal_med": snappedf(float(goal_d[goal_d.size() / 2]), 0.01) if not goal_d.is_empty() else -1.0,
		"move_goal_med": snappedf(float(move_d[move_d.size() / 2]), 0.01) if not move_d.is_empty() else -1.0,
		"in_combat": GameManager.squad_in_combat(sid),
	}
	last_stuck = d
	stuck_reports += 1
	stuck_units_total += men.size()
	_emit("stuck_running", d, "отряд %d (%s, сторона %d): бегут на месте %d из %d; состояния %s; в коробке %d (до места %.2f м), к точке хода %.2f м, бег %d, приказ игрока %d, замок %d, в контакте %d, бой %s" % [
		sid, String(d["type"]), int(d["fac"]), men.size(), alive, str(states), in_box,
		float(d["box_goal_med"]), float(d["move_goal_med"]), sprint, porder, lock, contact, str(d["in_combat"])])

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
	_emit("squad_split", res, "отряд %d (%s, сторона %d): порван на %d куч, крупнейшие %d и %d бойцов в %.1f м друг от друга; состояния %s / %s; бой %s" % [
		sid, String(res["type"]), int(res["fac"]), int(res["parts"]), int(res["a"]), int(res["b"]),
		float(res["gap"]), str(res["states_a"]), str(res["states_b"]), str(res["in_combat"])])

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
