extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## МАРШ ВОЛНЫ ЭТАПАМИ (ТЗ 31.10.2026, «главная мысль» владельца)
## ═══════════════════════════════════════════════════════════════════════════
## Прежде волна шла от площадки сбора одним приказом прямо к точке
## развёртывания: отряды растягивались по скорости родов, у брода сбивались в
## ком, к врагу приходили кучей по одному (скриншот 30.10, 1:29:39).
## Теперь путь разбит на ПРИВАЛЫ:
##   1. выход с базы       — HALT_EXIT_DIST от центра волны к цели;
##   2. подступ к броду    — HALT_FORD_APPROACH до входа в брод (свой берег);
##   3. за бродом          — HALT_FORD_EXIT за выходом (пятак чужого берега);
##   затем — прежняя точка развёртывания (GoblinAI._assign_points).
## На привале каждый отряд получает своё место в БЛОКЕ волны (ряды поперёк
## курса: туши в центре первого ряда, пехота по краям, конница сзади) — тем же
## отрядным приказом, что и марш: «отряд сам себе кликает под нос», без
## поводков и стягиваний. Дошедший и вставший отряд СПИТ (тик погашен, удар
## будит весь отряд — Unit.take_damage → wake_dormant_squad): накопленная
## волна FPS не ест. Дальше волна идёт, когда собрались все или вышел срок;
## опоздавшие и порвавшиеся — в лог («[ВОЛНА …]») с причиной.
## Скан — передовые отряды (центр и углы первого ряда, 1-5), раз в
## SCAN_SEC; увидели врага — чаще (SCAN_HOT_SEC); враг ближе CONTACT_R —
## развёртывание здесь же. Фазы сканов волн разведены по номеру волны.
## Ручка perf_config.wave_stages.

const _Spawn := preload("res://scripts/spawn_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

## Точки привалов волны: w["legs"] — Array[Vector3]; пусто — привалов нет
static func build_legs(gai, w: Dictionary) -> void:
	var t: Vector3 = w["pos"]
	var c: Vector3 = gai._wave_centre(w)
	var legs: Array = []
	var dir0: Vector3 = t - c
	dir0.y = 0.0
	if dir0.length() < 1.0:
		w["legs"] = legs
		return
	dir0 = dir0.normalized()
	var raw: Array = [c + dir0 * _Spawn.HALT_EXIT_DIST]
	var main = gai.main
	if main != null and main.has_method("ford_route"):
		var fr: Array = main.call("ford_route", c, t, 0.0)
		if fr.size() == 2:
			var a: Vector3 = fr[0]
			var b: Vector3 = fr[1]
			var across: Vector3 = b - a
			across.y = 0.0
			across = across.normalized() if across.length() > 0.1 else dir0
			raw.append(a - across * _Spawn.HALT_FORD_APPROACH)
			raw.append(b + across * _Spawn.HALT_FORD_EXIT)
	# Привал ближе HALT_MIN_GAP к прошлому, не ближе к цели, чем прошлый, или
	# в зоне развёртывания — снимается (короткий поход идёт без лишних стоянок)
	var prev: Vector3 = c
	var stage_r: float = _Spawn.WAVE_STAGE_DIST + _Spawn.HALT_MIN_GAP * 0.5
	for p in raw:
		var q: Vector3 = p
		var dq: float = _flat(q - t)
		if _flat(q - prev) < _Spawn.HALT_MIN_GAP or dq >= _flat(prev - t) or dq < stage_r:
			continue
		legs.append(GameManager.land_target(q))
		prev = q
	w["legs"] = legs
	w["leg"] = -1
	w["scan_ph"] = float(int(w["id"]) % 4) * 1.7     # фаза скана — шахматкой по волнам
	w["scan_t"] = -1.0e9
	w["scan_hot"] = false
	w["halt_log"] = {}

static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

## Следующий привал: места блока и приказ каждому отряду (спящих будит _issue)
static func next_leg(gai, w: Dictionary) -> void:
	w["leg"] = int(w["leg"]) + 1
	w["leg_t"] = gai.clock
	w["gather_t"] = -1.0
	w["halt_log"] = {}
	var legs: Array = w["legs"]
	var li: int = int(w["leg"])
	if li >= legs.size():
		return
	var p: Vector3 = legs[li]
	# Длина этапа — от центра волны в момент приказа (срок этапа от неё)
	w["leg_len"] = _flat(p - (gai._wave_centre(w) as Vector3))
	w["settled"] = {}
	var nxt: Vector3 = legs[li + 1] if li + 1 < legs.size() else (w["pos"] as Vector3)
	var dir: Vector3 = nxt - p
	dir.y = 0.0
	if dir.length() < 1.0:
		dir = w.get("dir", Vector3.FORWARD)
	dir = dir.normalized()
	w["leg_dir"] = dir
	var hp: Dictionary = block_points(gai, w["sids"], p, dir)
	w["hpts"] = hp
	var track: Dictionary = {}
	for sid in hp:
		gai._order_move(int(sid), hp[sid], false)
		track[sid] = {"c": gai._centre(int(sid)), "t": gai.clock, "told": false}
	w["htrack"] = track
	gai.halts_ordered += 1

## БЛОК ВОЛНЫ НА ПРИВАЛЕ: ряды по HALT_COLS отрядов поперёк курса, шаг по
## диаметру самой крупной толпы. Первый ряд — туши в центре, пехота к
## краям; конница и полководец — в задних рядах
static func block_points(gai, sids: Array, p: Vector3, dir: Vector3) -> Dictionary:
	var big: Array = []
	var inf: Array = []
	var cav: Array = []
	var rmax: float = 0.0
	for s in sids:
		var sid: int = int(s)
		var ty: String = gai._type(sid)
		if ty == "goblin_rider" or ty == "pig_boss":
			cav.append(sid)
		elif ty == "big_goblin" or ty == "troll":
			big.append(sid)
		else:
			inf.append(sid)
		rmax = maxf(rmax, _GobCfg.horde_radius(gai._alive_n(sid)))
	# Первый ряд: центр — туши, края — пехота (порядок «из центра наружу»)
	var order: Array = []
	order.append_array(big)
	order.append_array(inf)
	order.append_array(cav)
	var gap: float = maxf(2.0 * rmax + _Spawn.HALT_SQUAD_PAD, _Spawn.HALT_GAP_MIN)
	var side := Vector3(-dir.z, 0.0, dir.x)
	var cols: int = mini(_Spawn.HALT_COLS, maxi(order.size(), 1))
	var out: Dictionary = {}
	var i := 0
	var row := 0
	while i < order.size():
		var n: int = mini(cols, order.size() - i)
		var lat: Array = _centre_out(n)
		for k in range(n):
			var off: float = float(lat[k]) * gap
			var q: Vector3 = p + side * off - dir * float(row) * gap
			out[order[i + k]] = GameManager.land_target(q)
		i += n
		row += 1
	return out

## Места ряда из n по порядку «из центра наружу», в шагах: нечётный ряд —
## 0, -1, +1, -2, +2 …; чётный — -0.5, +0.5, -1.5, +1.5 …
static func _centre_out(n: int) -> Array:
	var out: Array = []
	var base: float = 0.0 if n % 2 == 1 else 0.5
	if n % 2 == 1:
		out.append(0.0)
	var k := 0 if n % 2 == 0 else 1
	while out.size() < n:
		out.append(-(base + float(k)))
		if out.size() < n:
			out.append(base + float(k))
		k += 1
	return out

## Такт марша. Возвращает:
##   "march"   — идём/стоим на привале;
##   "done"    — привалы пройдены, дальше прежний марш к развёртыванию;
##   "contact" — скан нашёл врага ближе CONTACT_R: развёртываться здесь
static func tick(gai, w: Dictionary) -> String:
	var legs: Array = w["legs"]
	if int(w["leg"]) < 0:
		next_leg(gai, w)
	var li: int = int(w["leg"])
	if li >= legs.size():
		return "done"
	if _scan(gai, w):
		_wake_all(gai, w)
		_log(gai, w, "скан: враг в %.0f м у головы — развёртывание на привале %d" % [float(w.get("scan_d", 0.0)), li + 1])
		return "contact"
	var hp: Dictionary = w["hpts"]
	var track: Dictionary = w["htrack"]
	var settled := 0
	var live: Array = w["sids"]
	for s in live:
		var sid: int = int(s)
		if not hp.has(sid):
			continue
		var goal: Vector3 = hp[sid]
		var c: Vector3 = gai._centre(sid)
		if c.x == INF:
			continue
		var d: float = _flat(c - goal)
		var men: Array = gai._alive(sid)
		var still := 0
		var asleep := 0
		for m in men:
			var u := m as Unit
			if u.dormant:
				asleep += 1
			if u.state != Unit.State.MOVING:
				still += 1
		var near: bool = d < _Spawn.HALT_ARRIVE_R
		var tr: Dictionary = track.get(sid, {"c": c, "t": gai.clock, "told": false})
		# У точки дольше HALT_SETTLE_GRACE_SEC — собран, даже если толпа ещё
		# доталкивается до мест: сон ставит идущих на месте (Unit.set_dormant)
		if near and not tr.has("near_t"):
			tr["near_t"] = gai.clock
		elif not near:
			tr.erase("near_t")
		var grace: bool = near and gai.clock - float(tr.get("near_t", gai.clock)) > _Spawn.HALT_SETTLE_GRACE_SEC
		track[sid] = tr
		if near and (grace or float(still) >= float(men.size()) * _Spawn.HALT_SETTLE_SHARE):
			settled += 1
			(w["settled"] as Dictionary)[sid] = true
			if asleep < men.size() and _sleeps(gai, sid):
				gai._sleep_squad(sid)
			continue
		# Прогресс: не сдвинулся на STUCK_M за HALT_STUCK_SEC — в лог и переприказ
		var pc: Vector3 = tr["c"]
		if pc.x == INF or _flat(c - pc) > _Spawn.HALT_STUCK_M:
			tr["c"] = c
			tr["t"] = gai.clock
		elif gai.clock - float(tr["t"]) > _Spawn.HALT_STUCK_SEC:
			tr["t"] = gai.clock
			gai.halt_stuck += 1
			if not bool(tr["told"]):
				tr["told"] = true
				_log(gai, w, "отряд %d (%s) стоит %.0f с в %.0f м от привала %d: %s" % [
					sid, gai._type(sid), _Spawn.HALT_STUCK_SEC, d, li + 1, _why(gai, sid, men, goal)])
			gai._order_move(sid, goal, false)
		track[sid] = tr
	var n_live: int = 0
	for s2 in live:
		if hp.has(int(s2)):
			n_live += 1
	if settled > 0 and float(w["gather_t"]) < 0.0:
		w["gather_t"] = gai.clock
	var all_in: bool = settled >= n_live
	var leg_len: float = float(w.get("leg_len", 0.0))
	# Отставших ждём, пока они ИДУТ (медленные туши — хвост, его подтягивают);
	# стоящий без хода HALT_STUCK_SEC отставший срок ожидания не продлевает
	var progressing := false
	for s4 in live:
		var tr4: Variant = track.get(int(s4))
		if tr4 != null and not (w["settled"] as Dictionary).has(int(s4)) and ((tr4 as Dictionary).has("near_t") \
				or gai.clock - float((tr4 as Dictionary)["t"]) < _Spawn.HALT_STUCK_SEC):
			progressing = true
	var waited: bool = float(w["gather_t"]) >= 0.0 and gai.clock - float(w["gather_t"]) > _Spawn.HALT_WAIT_MAX_SEC \
		and not progressing
	var leg_over: bool = gai.clock - float(w["leg_t"]) > _Spawn.HALT_LEG_BASE_SEC + leg_len / _Spawn.HALT_LEG_SPEED
	# Привал держится не меньше HALT_MIN_SEC от сбора последнего — «встали,
	# подтянули хвосты, построились, обнюхались»
	if all_in and gai.clock - float(w["gather_t"]) < _Spawn.HALT_MIN_SEC:
		return "march"
	if all_in or waited or leg_over:
		if not all_in:
			for s3 in live:
				var sid3: int = int(s3)
				if not hp.has(sid3):
					continue
				var c3: Vector3 = gai._centre(sid3)
				if c3.x == INF:
					continue
				var men3: Array = gai._alive(sid3)
				var d3: float = _flat(c3 - (hp[sid3] as Vector3))
				if not (w["settled"] as Dictionary).has(sid3):
					gai.halt_late += 1
					_log(gai, w, "привал %d: отряд %d (%s) не собрался за %.0f с — %.0f м, %s" % [
						li + 1, sid3, gai._type(sid3), gai.clock - float(w["leg_t"]), d3, _why(gai, sid3, men3, hp[sid3])])
		gai.halts_done += 1
		_log(gai, w, "привал %d пройден за %.0f с (этап %.0f м): %s" % [li + 1, gai.clock - float(w["leg_t"]), leg_len,
			"все собрались" if all_in else ("ждать некого" if waited else "вышел срок")])
		next_leg(gai, w)
		if int(w["leg"]) >= legs.size():
			_wake_all(gai, w)
			return "done"
	return "march"

static func _settled_men(men: Array) -> bool:
	var still := 0
	for m in men:
		if (m as Unit).state != Unit.State.MOVING:
			still += 1
	return float(still) >= float(men.size()) * _Spawn.HALT_SETTLE_SHARE

## Спит ли отряд на привале: полководец — никогда (его ведёт свой мозг)
static func _sleeps(gai, sid: int) -> bool:
	return preload("res://scripts/perf_config.gd").wave_halt_sleep and not gai._is_boss_sid(sid)

static func _wake_all(gai, w: Dictionary) -> void:
	for s in (w["sids"] as Array):
		gai._wake_squad(int(s))

## Почему отряд не дошёл: разброс (порвался), доля в MOVING, ближайший к
## месту и дальний боец
static func _why(_gai, _sid: int, men: Array, goal: Vector3) -> String:
	if men.is_empty():
		return "пуст"
	var moving := 0
	var dmin := INF
	var dmax := 0.0
	for m in men:
		var u := m as Unit
		if u.state == Unit.State.MOVING:
			moving += 1
		var d: float = Vector2(u.position.x - goal.x, u.position.z - goal.z).length()
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
	var tags: Array = []
	if dmax - dmin > _Spawn.HALT_TORN_M:
		tags.append("порвался (разброс %.0f м)" % (dmax - dmin))
	if moving * 2 > men.size():
		tags.append("идут %d/%d" % [moving, men.size()])
	else:
		tags.append("стоят %d/%d" % [men.size() - moving, men.size()])
	var u0 := men[0] as Unit
	if not GameManager.is_passable(u0.position.x, u0.position.z):
		tags.append("в непроходимом")
	return ", ".join(tags)

## Скан передовых: центр и углы первого ряда блока (до SCAN_HEADS отрядов);
## раз в SCAN_SEC, после находки — раз в SCAN_HOT_SEC. true — враг у головы
## ближе CONTACT_R
static func _scan(gai, w: Dictionary) -> bool:
	var every: float = _Spawn.SCAN_HOT_SEC if bool(w["scan_hot"]) else _Spawn.SCAN_SEC
	if gai.clock + float(w["scan_ph"]) - float(w["scan_t"]) < every:
		return false
	w["scan_t"] = gai.clock + float(w["scan_ph"])
	gai.scans_done += 1
	var dir: Vector3 = w.get("leg_dir", w.get("dir", Vector3.FORWARD))
	var heads: Array = _heads(gai, w, dir)
	var hot := false
	var best := INF
	for h in heads:
		var c: Vector3 = gai._centre(int(h))
		if c.x == INF:
			continue
		var probe: Vector3 = c + dir * _Spawn.SCAN_AHEAD
		var foe: Node3D = gai._nearest_foe(probe, _Spawn.SCAN_R)
		if foe == null:
			continue
		hot = true
		best = minf(best, _flat(foe.global_position - c))
	w["scan_hot"] = hot
	w["scan_d"] = best
	return best < _Spawn.CONTACT_R

## Передовые: отряды, ближайшие к следующему привалу по курсу — центр и
## крайние слева/справа (1-5 по числу отрядов)
static func _heads(gai, w: Dictionary, dir: Vector3) -> Array:
	var live: Array = w["sids"]
	var nh: int = clampi(1 + live.size() / 4, 1, _Spawn.SCAN_HEADS)
	if live.size() <= nh:
		return live
	var side := Vector3(-dir.z, 0.0, dir.x)
	var rows: Array = []
	for s in live:
		var c: Vector3 = gai._centre(int(s))
		if c.x == INF:
			continue
		rows.append(Vector3(-(c.x * dir.x + c.z * dir.z), float(int(s)), c.x * side.x + c.z * side.z))
	rows.sort()
	# Центров нет (отряды волны в гарнизоне/выбиты в этом такте) — скан молчит
	if rows.is_empty():
		return []
	var front: Array = rows.slice(0, mini(rows.size(), maxi(nh, _Spawn.HALT_COLS)))
	# В первой линии: центр и края по поперечной координате
	front.sort_custom(func(a, b): return (a as Vector3).z < (b as Vector3).z)
	var out: Array = []
	var pick: Array = [front.size() / 2, 0, front.size() - 1, front.size() / 4, front.size() * 3 / 4]
	for k in pick:
		var sid: int = int((front[k] as Vector3).y)
		if not out.has(sid):
			out.append(sid)
		if out.size() >= nh:
			break
	return out

static func _log(gai, w: Dictionary, text: String) -> void:
	if not preload("res://scripts/perf_config.gd").wave_march_log:
		return
	print("[ВОЛНА %d %s] t=%.0f %s" % [int(w["id"]), String(w["name"]), gai.clock, text])
	if GameManager.has_method("tm_event"):
		GameManager.tm_event("wave_march", {"wave": int(w["id"]), "msg": text})
