extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## СБОР ПЕРЕД УДАРОМ: АТАКА ВОЛНОЙ, А НЕ «ГУСЬКОМ» (ТЗ 24.09.2026, п. 8)
## ═══════════════════════════════════════════════════════════════════════════
## ЖАЛОБА: «враги растягиваются в цепочку по одному и по очереди умирают на
## копьях». Причина — приказ атаки раздавался ОТРЯДУ, как только тот видел
## врага: отряды шли с разных мест и разной скоростью, и каждый входил в бой
## сам, как дойдёт.
##
## ЛЕЧЕНИЕ — СБОР НА ЛИНИИ ПЕРЕД ЦЕЛЬЮ. Все отряды, нацеленные на ОДНОГО
## противника (ключ — его отряд), сперва встают в линию в STAGE_DIST перед
## ним, поперёк оси подхода (слоты по SLOT_W, больше SLOTS_PER_ROW — второй
## ряд). Волна уходит РАЗОМ, когда:
##   • на местах не меньше READY_FRAC отрядов группы (и сбор шёл хотя бы
##     MIN_STAGE_SEC — иначе первый дошедший «собирал» бы сам себя), или
##   • сбор длится дольше MAX_STAGE_SEC (застрявший не держит всех), или
##   • противник САМ подошёл к линии ближе ENGAGE_NOW_DIST, или отряд группы
##     уже в бою / по нему бьют — тогда стоять под ударом незачем.
## Одиночке (группа из одного отряда) собираться не с кем — сразу в бой.
##
## Модуль без узла и без тика: зовётся из такта мышления владельца (GoblinAI,
## DormantReserve), решение — O(отрядов группы). Часы — те, что даёт владелец.

const STAGE_DIST := 18.0
const SLOT_W := 9.0
const SLOTS_PER_ROW := 5
const ROW_DEPTH := 8.0
const READY_FRAC := 0.75
const ARRIVE_R := 6.0
const MIN_STAGE_SEC := 2.0
const MAX_STAGE_SEC := 16.0
const ENGAGE_NOW_DIST := 12.0
## Выпущенная волна держит «выпущено» столько, потом группа забывается
const RELEASED_KEEP_SEC := 25.0
## Отряд, о котором не спрашивали столько, выбывает из группы
const MEMBER_STALE_SEC := 4.0

## ключ цели → {sids: {sid: last_seen}, since, released, rel_at, axis, anchor}
var groups: Dictionary = {}
## Стендам: сколько волн выпущено и сколько отрядов в них ушло
var waves_released: int = 0
var last_release_size: int = 0

static func key_of(foe: Node3D) -> int:
	if foe is Unit and (foe as Unit).squad_id > 0:
		return (foe as Unit).squad_id
	return -foe.get_instance_id()

## Решение для одного отряда. Ответ: {"attack": true} — бить сейчас;
## {"stage": точка} — идти на своё место в линии сбора
## Выключатель для A/B-сверок стендами (false — прежнее «бить сразу»)
static var enabled: bool = true

func gate(sid: int, center: Vector3, foe: Node3D, now: float) -> Dictionary:
	if not enabled:
		return {"attack": true}
	if foe == null or not is_instance_valid(foe) or not (foe is Unit):
		return {"attack": true}           # постройки штурмует командир — не здесь
	var key: int = key_of(foe)
	var g: Variant = groups.get(key)
	if g == null:
		g = {"sids": {}, "since": now, "released": false, "rel_at": 0.0,
			"axis": Vector3.ZERO, "anchor": Vector3.ZERO}
		groups[key] = g
	var gd: Dictionary = g
	if bool(gd["released"]):
		if now - float(gd["rel_at"]) <= RELEASED_KEEP_SEC:
			return _go(gd, sid, center, foe)
		gd["released"] = false
		gd["sids"] = {}
		gd["since"] = now
	var sids: Dictionary = gd["sids"]
	# Отряд → [когда спрашивал, где стоял]: центр даёт владелец, модуль
	# сам в состав не лезет
	sids[sid] = [now, center]
	# Выбывшие (погибли, ушли на другой приказ) — вон из группы
	for k in sids.keys():
		if now - float(sids[k][0]) > MEMBER_STALE_SEC:
			sids.erase(k)
	var fp: Vector3 = foe.global_position
	# Бой уже идёт у кого-то из группы — вся волна в бой
	var engaged := false
	for k2 in sids.keys():
		if GameManager.squad_in_combat(int(k2)) or GameManager.squad_hit_recently(int(k2)):
			engaged = true
			break
	var d_self: float = Vector2(center.x - fp.x, center.z - fp.z).length()
	if engaged or d_self <= ENGAGE_NOW_DIST * 0.6:
		_release(gd, now)
		return _go(gd, sid, center, foe)
	# ── ОСЬ ПОДХОДА: от цели к середине группы, заморожена на время сбора ──
	var axis: Vector3 = gd["axis"]
	if axis == Vector3.ZERO:
		var acc := Vector3.ZERO
		var n := 0
		for k3 in sids.keys():
			var c3: Vector3 = sids[k3][1]
			acc += c3
			n += 1
		var mid: Vector3 = acc / float(n) if n > 0 else center
		axis = Vector3(mid.x - fp.x, 0.0, mid.z - fp.z)
		axis = axis.normalized() if axis.length() > 0.5 else Vector3.BACK
		gd["axis"] = axis
		gd["anchor"] = fp
	var anchor: Vector3 = gd["anchor"]
	# Противник сам подошёл к линии — стоять незачем
	if Vector2(fp.x - anchor.x, fp.z - anchor.z).length() > STAGE_DIST - ENGAGE_NOW_DIST:
		_release(gd, now)
		return _go(gd, sid, center, foe)
	# Готовность группы
	var ready := 0
	var order: Array = _ordered(sids.keys())
	for i in range(order.size()):
		var c4: Vector3 = sids[order[i]][1]
		var sp: Vector3 = _slot(gd, i, order.size())
		if Vector2(c4.x - sp.x, c4.z - sp.z).length() <= ARRIVE_R:
			ready += 1
	var waited: float = now - float(gd["since"])
	# Одиночке собираться не с кем. Решается НЕ на первом вопросе: соседи по
	# тому же такту регистрируются следом, и первый спрошенный всегда один
	if order.size() <= 1 and waited >= MIN_STAGE_SEC:
		_release(gd, now)
		return _go(gd, sid, center, foe)
	if waited >= MAX_STAGE_SEC or (waited >= MIN_STAGE_SEC
			and float(ready) >= READY_FRAC * float(order.size())):
		_release(gd, now)
		return _go(gd, sid, center, foe)
	return {"stage": _slot(gd, order.find(sid), order.size())}

## ── ПОРЯДОК В ЛИНИИ: ПЕХОТА В ЦЕНТРЕ, ТЯЖЁЛЫЕ И КОННИЦА ПО ФЛАНГАМ ────────
## (ТЗ 24.09.2026, второе письмо: «3 отряда гоблинов впереди, туши и тролли
## по флангам»). Слоты ряда заполняются слева направо, поэтому фланговые
## ставятся попеременно в НАЧАЛО и в КОНЕЦ списка, пехота — в середину
func _ordered(keys: Array) -> Array:
	keys.sort()
	var inf: Array = []
	var side: Array = []
	for k in keys:
		var raw: Variant = GameManager.squads.get(int(k))
		var t: String = String((raw as Dictionary).get("type", "")) if raw != null else ""
		if t == "big_goblin" or t == "troll" or t == "goblin_rider" or t == "pig_boss":
			side.append(k)
		else:
			inf.append(k)
	var left: Array = []
	var right: Array = []
	for i in range(side.size()):
		if i % 2 == 0:
			left.append(side[i])
		else:
			right.push_front(side[i])
	return left + inf + right

func _slot(gd: Dictionary, idx: int, count: int) -> Vector3:
	var axis: Vector3 = gd["axis"]
	var anchor: Vector3 = gd["anchor"]
	var side := Vector3(-axis.z, 0.0, axis.x)
	var row: int = idx / SLOTS_PER_ROW
	var in_row: int = mini(count - row * SLOTS_PER_ROW, SLOTS_PER_ROW)
	var col: int = idx % SLOTS_PER_ROW
	var lat: float = (float(col) - float(in_row - 1) * 0.5) * SLOT_W
	var p: Vector3 = anchor + axis * (STAGE_DIST + float(row) * ROW_DEPTH) + side * lat
	return Vector3(p.x, 0.0, p.z)

func _release(gd: Dictionary, now: float) -> void:
	if bool(gd["released"]):
		return
	gd["released"] = true
	gd["rel_at"] = now
	waves_released += 1
	last_release_size = (gd["sids"] as Dictionary).size()
	gd["pairs"] = {}
	gd["pairs_done"] = false

## ── ФРОНТ НА ФРОНТ ПРИ ВЫПУСКЕ ВОЛНЫ (ТЗ 25.09.2026, п. 4) ─────────────────
## Ключ группы — ОДИН чужой отряд, и прежде вся волна уходила в него: пять
## отрядов на один, «молотилка», а соседние чужие отряды стояли без дела.
## Теперь при выпуске волна делит чужую линию у цели по ширине фронта
## (GameManager.front_pairs): каждый отряд бьёт чужой отряд перед собой.
## Раскладка считается один раз на выпуск (лениво, на первом вопросе) и
## держится RELEASED_KEEP_SEC. Ответ — боец назначенного отряда, ближайший
## к нашему центру: forced-приказ владельца дальше сам раздаст бойцам жертвы
## по этому отряду (Unit.command_attack → squad_pick_member)
const PAIR_RADIUS := 34.0
var pairs_assigned: int = 0

func _go(gd: Dictionary, sid: int, center: Vector3, foe: Node3D) -> Dictionary:
	if not bool(gd.get("pairs_done", false)):
		gd["pairs_done"] = true
		var sids: Array = (gd["sids"] as Dictionary).keys()
		if sids.size() >= 2:
			var at: Vector3 = foe.global_position
			gd["pairs"] = GameManager.front_pairs(sids, at,
				PAIR_RADIUS + SLOT_W * float(sids.size()) * 0.5, Constants.FACTION_GOBLIN)
	var fsid: Variant = (gd.get("pairs", {}) as Dictionary).get(sid)
	if fsid == null:
		return {"attack": true}
	var fsq: Variant = GameManager.squads.get(int(fsid))
	if fsq == null:
		return {"attack": true}
	var best: Node3D = null
	var bd := INF
	for m in (fsq as Dictionary)["members"]:
		if m == null or not is_instance_valid(m) or (m as Unit).is_dead():
			continue
		var d: float = center.distance_squared_to((m as Node3D).global_position)
		if d < bd:
			bd = d
			best = m
	if best == null:
		return {"attack": true}
	pairs_assigned += 1
	return {"attack": true, "foe": best}

func reset() -> void:
	groups.clear()
