extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## КОРОБКА ОТРЯДА В БОЮ (ТЗ 24.10.2026, ручка perf_config.box_front)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба владельца: при столкновении отряды теряют структуру и сливаются в
## один ком. Зонд qa_box_front (3 отряда копейщиков на 3 отряда гоблинов, до
## правки): глубина отряда в контакте падает до 0.5-0.6 исходной (пять шеренг
## сплющиваются в две), две трети контактов дают задние ряды, вылезшие вперёд
## (каждый идёт к СВОЕЙ цели, а автопилот подхода обходит своих сбоку), а
## коробки соседних отрядов накладываются до 39 %.
##
## ЧТО ДЕЛАЕТ МОДУЛЬ. Отряд рукопашной пехоты (BOX_TYPES), подошедший к врагу
## ближе ENGAGE_R, становится КОРОБКОЙ: каждому бойцу — постоянное место
## (колонка, ряд) в прямоугольнике с передней гранью F и курсом course.
## Двигается ТОЛЬКО коробка: F идёт вперёд, пока зазор от передней грани до
## ближайшего врага в своей полосе больше `standoff` (длина оружия минус
## интервал — то есть достают два первых ряда копий и один ряд мечей). Боец
## в коробке к своей цели сам не идёт: стоит на месте и бьёт то, до чего
## достаёт (Unit._box_hold). Выбит передний — колонка сдвигается на шаг
## вперёд (refill по колонкам). Коробки одной стороны не накладываются —
## разводятся вбок по общей линии фронта (_push_off).
##
## ЧЕМ ЭТО НЕ ЧЕТВЁРТАЯ ПОПЫТКА «ПЕРЕНОСА СТЕНЫ» (docs/ENGINEERING_LOG.md,
## 31.08.2026). Там строй сохранялся потому, что отряд ПЕРЕСТАВАЛ СБЛИЖАТЬСЯ
## (приход стены гасил приказ), и бой 60 на 60 шёл 148 с вместо 32. Здесь
## приказ и замок цели не трогаются вовсе (вся работа с замком живёт в ветке
## «цель пала», куда коробка не заходит), а коробка подаётся вперёд всякий раз,
## когда передний ряд противника выбит и зазор вырос. Бой идёт дольше по
## ДРУГОЙ причине и по заказу: бьют два ряда, а не пять.
##
## ЦЕНА. Один скан ядра (query_radius_rows) на отряд за пересчёт, пересчёт
## раз в SWEEP_MS; проходимость — пять точек коробки, а не каждый боец
## (правило 1). Покадрового пути здесь нет: боец читает своё поле _box_goal.

const _Opt := preload("res://scripts/perf_config.gd")
const _UStatsB := preload("res://scripts/unit_stats_config.gd")

## Рода войск, которые держат коробку. Стрелки бьют с места и так, конница
## живёт разгоном, туши и гноллы — одиночки.
## ГОБЛИНОВ ЗДЕСЬ НЕТ (ТЗ 25.10.2026, блок 2): орда дерётся прежней живой
## толпой (goblin_config.horde_offset), а не прямоугольником. Отряд стороны
## FACTION_GOBLIN не встаёт в коробку ни при каком роде войск (_wants_box)
const BOX_TYPES := {"spearman": true, "warrior": true}
## Коробка включается, когда враг ближе этого к передней грани отряда
const ENGAGE_R := 9.0
## И снимается, если врага нет ближе RELEASE_R дольше RELEASE_MS
const RELEASE_R := 15.0
const RELEASE_MS := 2500
## ПОВОДОК КОРОБКИ: передняя грань не уходит от точки ПОСЛЕДНЕГО КОНТАКТА
## дальше ENGAGE_R + поводок погони (Unit.PURSUIT_LIMIT). Якорь едет вместе
## с гранью, пока коробка в контакте: в свалке грань законно продвигается
## сквозь глубокий строй по мере гибели передних рядов, и якорь «где встала»
## останавливал её на 16 м (qa_mega_battle B4-1: рыцари встали вне дальности
## лучников, «целятся 0 из 400»). Без поводка коробка
## шла за отходящим врагом бесконечно, держась в семи метрах позади (зонд
## qa_box_front/DisProbe: 20 м за 12 с и дальше) — обычная погоня бойца
## обрезана поводком, коробка его обходила. Под замком игрока поводка нет
const CHASE_MAX := ENGAGE_R + 7.0
## Период пересчёта одного отряда (фазы разнесены по номеру отряда)
const SWEEP_MS := 150
## Меньше стольких живых — не коробка
const MIN_MEN := 6
## Коробка не подаётся вперёд, пока медиана отставания бойцов от своих мест
## больше этого: иначе точка уехала бы, а люди остались
const LAG_MAX := 0.7
## Зазор между коробками союзников поперёк фронта
const SIDE_GAP := 0.6
## Запас под длину оружия: standoff = reach − интервал − STAND_PAD
const STAND_PAD := 0.2
## Ширина коробки не больше WIDE_MAX глубин (толпа орды иначе вытянулась бы
## ниткой в пятнадцать метров)
const WIDE_MAX := 3.0
## Враг не в своей полосе дольше этого — коробка перестраивается на него
const TURN_MS := 2000
const TURN_COS := 0.64          # ~50°

## ── НАТИСК КОРОБКИ (ТЗ 25.10.2026, блок 4) ────────────────────────────────
## Жалоба со скриншотом: десяток отрядов в контакте «ковыряют шпажками» —
## коробки встали на standoff и стоят, линия фронта мертва. Толчок на удар
## (_apply_push) у равных по напору строёв нулевой (разница сил ≤ 0), а
## коробка вперёд ходит только в зазор. Теперь коробка в контакте МЕРИТ
## НАПОР: своя сила — сумма _push_power() всех её бойцов с весом ряда (задние
## ряды давят в спину передним — PRESS_ROW_W), сила врага — сумма
## _stand_power() его бойцов в нашей полосе на глубину PRESS_DEPTH с тем же
## весом по глубине (и упор фаланги: делится на push_resist). Перевес больше
## PRESS_DEADBAND — коробка теснит: враги полосы отходят на шаг, грань едет
## за ними. Шаг — PRESS_SPEED × доля перевеса (полный при PRESS_FULL-кратном).
## Коробку врага сдвигаем тем же шагом, что её людей, — иначе её места тянули
## бы людей обратно в нашу шеренгу. Равные силы стоят: двигают линию потери
## (меньше людей — меньше напор), то есть бой сам решает, куда она поедет
const PRESS_ROW_W := [1.0, 0.85, 0.7, 0.55, 0.45, 0.35]
const PRESS_ROW_TAIL := 0.3
## Насколько вглубь чужой толпы считается её упор (и кого сдвигает натиск)
const PRESS_DEPTH := 4.0
## Дальше этого от грани враги в кандидаты натиска не берутся
const PRESS_SCAN := 9.0
const PRESS_DEADBAND := 0.06
const PRESS_FULL := 1.0
## м/с при полном перевесе: медленно и слитно, как наваливается строй
const PRESS_SPEED := 0.45
## Доля LAG_MAX, при которой коробке ещё разрешено давить
const PRESS_LAG_K := 0.5
## Счётчики стендам: сколько пересчётов кончилось натиском и сколько метров
var presses: int = 0
var press_dist: float = 0.0

## sid → запись коробки (см. _build)
var boxes: Dictionary = {}
var _next: Dictionary = {}
## Счётчики для стендов
var activations: int = 0
var releases: int = 0
var refills: int = 0
var turns: int = 0
var side_pushes: int = 0

# ─────────────────────────────────────────────────────────────────────────────
func sweep() -> void:
	if not _Opt.box_front:
		if not boxes.is_empty():
			for sid in boxes.keys():
				_release(int(sid))
		return
	var squads: Dictionary = GameManager.squads
	if squads.is_empty():
		return
	var now: int = Unit.game_ms()
	for sid in squads:
		var nx: Variant = _next.get(sid)
		if nx == null:
			_next[sid] = now + (int(sid) * 37) % SWEEP_MS
			continue
		if now < int(nx):
			continue
		_next[sid] = now + SWEEP_MS
		_update(int(sid), now)
	# Отряды, которых больше нет
	if _next.size() > squads.size() + 16:
		for k in _next.keys():
			if not squads.has(k):
				_next.erase(k)
				if boxes.has(k):
					boxes.erase(k)

## Пересчитать один отряд; true — коробка этого отряда жива после пересчёта
func _update(sid: int, now: int) -> bool:
	var b: Variant = boxes.get(sid)
	if b == null:
		if not _wants_box(sid):
			return false
		var nb: Dictionary = _build(sid, Vector3.ZERO, 0)
		if nb.is_empty():
			return false
		boxes[sid] = nb
		activations += 1
		b = nb
	var bx: Dictionary = b
	if not _still_on(sid, bx, now):
		_release(sid)
		return false
	_advance(sid, bx, now)
	return true

# ─────────────────────────────────────────────────────────────────────────────
# ВКЛЮЧЕНИЕ И СНЯТИЕ
# ─────────────────────────────────────────────────────────────────────────────
func _live(sid: int) -> Array:
	var out: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return out
	for m in ((sq as Dictionary)["members"] as Array):
		# Правило 5: живость — на сырой ссылке, до приведения
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead() or u.garrisoned or u.squad_id != sid:
			continue
		out.append(u)
	return out

func _wants_box(sid: int) -> bool:
	if not BOX_TYPES.has(GameManager.squad_type(sid)):
		return false
	if int((GameManager.squads[sid] as Dictionary).get("faction", 0)) == Constants.FACTION_GOBLIN:
		return false
	var men: Array = _live(sid)
	if men.size() < MIN_MEN:
		return false
	var u0: Unit = men[0]
	if u0._stance_holds_ground() or u0.retreating or u0._panicked:
		return false
	# Отряд ДЕРЁТСЯ С БОЙЦАМИ: четверть состава в атаке на живого бойца.
	# Осада постройки — свой подход по кольцу (SelectionManager._ring_squads_around)
	var atk := 0
	for m in men:
		var u: Unit = m
		if u.state != Unit.State.ATTACKING or u.retreating or u.sprinting:
			continue
		var t = u.attack_target
		if t != null and is_instance_valid(t) and t is Unit:
			atk += 1
	if atk < maxi(2, men.size() / 4):
		return false
	var ep: Vector3 = _lock_point(men)
	if ep == Vector3.INF:
		ep = GameManager.squad_enemy_point(sid, u0, ENGAGE_R + 4.0)
	if ep == Vector3.INF:
		return false
	var c: Vector3 = GameManager._centroid_of(men)
	return Vector2(ep.x - c.x, ep.z - c.z).length() <= ENGAGE_R + 4.0

## ЗАМОК ЦЕЛИ ИГРОКА ЗАДАЁТ КУРС КОРОБКИ. Большинство отряда под замком —
## точка (медиана) их целей, иначе INF. Без этого коробка ложилась курсом на
## ближайшего врага — стрелков сбоку — и уводила отряд с приказа
## (qa_target_lock D: «переключились на стрелков 4»)
func _lock_point(men: Array) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for m in men:
		var u: Unit = m
		if not u.target_lock:
			continue
		var t = u.attack_target
		if t == null or not is_instance_valid(t) or not (t is Unit):
			continue
		var tp: Vector3 = (t as Unit).global_position
		xs.append(tp.x)
		zs.append(tp.z)
	if xs.size() * 2 <= men.size():
		return Vector3.INF
	xs.sort()
	zs.sort()
	var k: int = xs.size() / 2
	return Vector3(float(xs[k]), 0.0, float(zs[k]))

func _still_on(sid: int, b: Dictionary, now: int) -> bool:
	var men: Array = _live(sid)
	if men.size() < MIN_MEN / 2:
		return false
	var u0: Unit = men[0]
	if u0._stance_holds_ground():
		return false
	# Отход, бег и ПРИКАЗ ИГРОКА НА ДВИЖЕНИЕ снимают коробку сразу: строй
	# уходит туда, куда его послали, а не стоит у чужой шеренги
	var gone := 0
	for m in men:
		var u: Unit = m
		if u.retreating or u.sprinting or u._panicked \
				or (u.state == Unit.State.MOVING and u.player_order_active()):
			gone += 1
	if gone * 2 > men.size():
		return false
	return now - int(b["seen"]) <= RELEASE_MS

func _release(sid: int) -> void:
	var b: Variant = boxes.get(sid)
	boxes.erase(sid)
	if b == null:
		return
	releases += 1
	for m in ((b as Dictionary)["units"] as Array):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u != null:
			u.box_leave()
	# Вышли из боя — строй собирает обычное смыкание (squad_close_ranks сам
	# откажет, пока отряд числится в бою)
	if GameManager.squads.has(sid) and not GameManager.squad_in_combat(sid):
		GameManager.call_deferred("squad_close_ranks", sid, true)

# ─────────────────────────────────────────────────────────────────────────────
# ПОСТРОЕНИЕ
# ─────────────────────────────────────────────────────────────────────────────
## Интервал отряда — медиана расстояния до ближайшего соседа по РАЗМЕТКЕ
## (у людей Building.squad_spacing, у орды своя толпа); без разметки — 0.6
func _spacing(sid: int) -> float:
	var sq: Dictionary = GameManager.squads[sid]
	var sl: Variant = sq.get("slots")
	if sl == null or (sl as Array).size() < 3:
		return 0.6
	var pts: Array = sl
	var n: int = mini(pts.size(), 24)
	var ds: Array = []
	for i in range(n):
		var a: Vector3 = pts[i]
		var best := INF
		for j in range(pts.size()):
			if j == i:
				continue
			var p: Vector3 = pts[j]
			best = minf(best, Vector2(p.x - a.x, p.z - a.z).length())
		if best < INF:
			ds.append(best)
	if ds.is_empty():
		return 0.6
	ds.sort()
	return clampf(float(ds[ds.size() / 2]), 0.45, 1.2)

## Коробка из ТЕКУЩЕГО положения бойцов: ряды — по глубине вдоль курса, в ряду
## — слева направо. Так никто не идёт крест-накрест через строй.
## force_course ≠ 0 — перестроение на новый фронт (враг ушёл во фланг);
## cols_hint > 0 — число колонок прежней коробки: при развороте на 90° ширина
## «по нынешнему строю» — это прежняя ГЛУБИНА, и коробка вставала бы колонной
func _build(sid: int, force_course: Vector3, cols_hint: int) -> Dictionary:
	var men: Array = _live(sid)
	if men.size() < MIN_MEN:
		return {}
	var u0: Unit = men[0]
	var c: Vector3 = GameManager._centroid_of(men)
	var course: Vector3 = force_course
	if course == Vector3.ZERO:
		var ep: Vector3 = _lock_point(men)
		if ep == Vector3.INF:
			ep = GameManager.squad_enemy_point(sid, u0, ENGAGE_R + 4.0)
		if ep == Vector3.INF:
			return {}
		var ed := Vector3(ep.x - c.x, 0.0, ep.z - c.z)
		if ed.length_squared() < 1e-4:
			return {}
		ed = ed.normalized()
		# Курс разметки, если он смотрит на врага: тогда коробка ложится на
		# уже стоящий строй, и никто не переходит на другое место
		course = ed
		var fc: Vector3 = GameManager.squad_course(sid)
		fc.y = 0.0
		if fc.length_squared() > 1e-4:
			fc = fc.normalized()
			if fc.dot(ed) > 0.77:
				course = fc
	var side := Vector3(-course.z, 0.0, course.x)
	var gap: float = _spacing(sid)
	var n: int = men.size()
	# Колонки — по ширине нынешнего строя, но не шире WIDE_MAX глубин
	var sds: Array = []
	for m in men:
		sds.append(((m as Unit).global_position - c).dot(side))
	sds.sort()
	var w: float = float(sds[int(float(n) * 0.9)]) - float(sds[int(float(n) * 0.1)])
	var cols: int = int(round(w / 0.8 / gap)) + 1
	cols = clampi(cols, 2, maxi(2, int(ceil(sqrt(float(n) * WIDE_MAX)))))
	if cols_hint > 0:
		cols = cols_hint
	cols = mini(cols, n)
	# Ряды: по глубине (передние — первыми), внутри ряда — по боку
	var keyed: Array = []
	for m in men:
		var p: Vector3 = (m as Unit).global_position
		keyed.append([(p - c).dot(course), (p - c).dot(side), m])
	keyed.sort_custom(func(a, b2): return float(a[0]) > float(b2[0]))
	var units: Array = []
	var col := PackedInt32Array()
	var row := PackedInt32Array()
	var front: Array = []
	var r := 0
	var i := 0
	while i < n:
		var chunk: Array = keyed.slice(i, mini(i + cols, n))
		chunk.sort_custom(func(a, b2): return float(a[1]) < float(b2[1]))
		var k: int = chunk.size()
		var c0: int = (cols - k) / 2
		for j in range(k):
			units.append(chunk[j][2])
			col.append(c0 + j)
			row.append(r)
			if r == 0:
				front.append(float(chunk[j][0]))
		i += cols
		r += 1
	front.sort()
	var f_al: float = float(front[front.size() / 2]) if not front.is_empty() else 0.0
	var mid: float = float(sds[n / 2])
	var F: Vector3 = Vector3(c.x, 0.0, c.z) + course * f_al + side * mid
	var reach: float = u0.attack_range
	var b := {
		"F": F, "course": course, "side": side, "gap": gap, "cols": cols, "fac": u0.faction,
		"units": units, "col": col, "row": row,
		"standoff": maxf(Unit.BLOCK_RADIUS * 2.0 + 0.05, reach - gap - STAND_PAD),
		"speed": u0._effective_speed() * 0.9,
		"seen": Unit.game_ms(), "off_lane": 0, "moving": true, "anchor": F, "home": F,
	}
	for m in units:
		(m as Unit).box_enter(course)
	_write_goals(b)
	return b

# ─────────────────────────────────────────────────────────────────────────────
# ПЕРЕСЧЁТ
# ─────────────────────────────────────────────────────────────────────────────
func _advance(sid: int, b: Dictionary, now: int) -> void:
	_refill(sid, b)
	var units: Array = b["units"]
	if units.is_empty():
		return
	var F: Vector3 = b["F"]
	var course: Vector3 = b["course"]
	var side: Vector3 = b["side"]
	var gap: float = b["gap"]
	var cols: int = b["cols"]
	var half_w: float = float(cols - 1) * gap * 0.5 + 0.3
	var standoff: float = b["standoff"]
	var dt: float = float(SWEEP_MS) * 0.001
	var step: float = float(b["speed"]) * dt
	# ── ОТСТАВАНИЕ ЛЮДЕЙ ОТ СВОИХ МЕСТ ───────────────────────────────────────
	var lags: Array = []
	for m in units:
		var u: Unit = m
		var g: Vector3 = u._box_goal
		if g.x == INF:
			continue
		var p: Vector3 = u.position if u._local_xform else u.global_position
		lags.append(Vector2(p.x - g.x, p.z - g.z).length())
	lags.sort()
	# 80-й перцентиль, а не медиана: передний ряд в контакте прижат к чужим
	# телам («упёрся — дерись», шагнуть он не может), и по медиане коробка
	# уезжала бы, оставляя его позади (qa_box_front B: 90 % — 8 м)
	var lag: float = float(lags[int(float(lags.size()) * 0.8)]) if not lags.is_empty() else 0.0
	# ── ВРАГ: БЛИЖАЙШИЙ В СВОЕЙ ПОЛОСЕ И БЛИЖАЙШИЙ ВООБЩЕ ───────────────────
	var my_fac: int = (units[0] as Unit).faction
	var scan_c: Vector3 = F + course * 4.0
	var rows: PackedInt32Array = GameManager.army.query_radius_rows(scan_c.x, scan_c.z, half_w + ENGAGE_R)
	var ru: Array = GameManager._row_units
	var rcap: int = ru.size()
	var lane_al := INF
	var near_d2 := INF
	var near_al := 0.0
	var near_sd := 0.0
	# Враги в полосе — кандидаты под натиск (_press), чтобы не сканировать
	# второй раз: боец и его глубина вдоль курса от передней грани
	var lane_e: Array = []
	var lane_a := PackedFloat32Array()
	for rr in rows:
		if rr < 0 or rr >= rcap:
			continue
		var e_raw = ru[rr]
		if e_raw == null or not is_instance_valid(e_raw):
			continue
		var e := e_raw as Unit
		if e == null or e.faction == my_fac or e.faction < 0 \
				or e.faction >= Constants.FACTION_COUNT or e.is_dead() or e.garrisoned:
			continue
		var ep: Vector3 = e.position if e._local_xform else e.global_position
		var dx: float = ep.x - F.x
		var dz: float = ep.z - F.z
		var al: float = dx * course.x + dz * course.z
		var sd: float = dx * side.x + dz * side.z
		if absf(sd) <= half_w + 0.6 and al > -1.5:
			if al < lane_al:
				lane_al = al
			if al < PRESS_SCAN:
				lane_e.append(e)
				lane_a.append(al)
		var d2: float = dx * dx + dz * dz
		if d2 < near_d2:
			near_d2 = d2
			near_al = al
			near_sd = sd
	if near_d2 < RELEASE_R * RELEASE_R:
		b["seen"] = now
	# Под замком вбок и в разворот ведёт ТОЛЬКО цель приказа: чужие сбоку
	# (стрелки, обходящий отряд) коробку с приказа не уводят
	var lp: Vector3 = _lock_point(units)
	if lp != Vector3.INF:
		var lx: float = lp.x - F.x
		var lz: float = lp.z - F.z
		near_al = lx * course.x + lz * course.z
		near_sd = lx * side.x + lz * side.z
		near_d2 = lx * lx + lz * lz
	var adv := 0.0
	var lat := 0.0
	# В КОНТАКТЕ КОРОБКА ВБОК НЕ ХОДИТ: её передний ряд уже стоит у чужих тел
	# и за местом не пойдёт. Линия фронта складывается на подходе
	var engaged: bool = lane_al < standoff + 0.5
	if lane_al < INF:
		b["off_lane"] = 0
		if lag < LAG_MAX:
			adv = clampf(lane_al - standoff, 0.0, step)
	elif near_d2 < INF:
		# Враг рядом, но не в полосе: сдвиг вбок к нему и подход по курсу
		if lag < LAG_MAX:
			if absf(near_sd) > half_w:
				lat = signf(near_sd) * minf(absf(near_sd) - half_w + 0.3, step)
				# Вбок — только в свободное место: сосед по линии фронта уже
				# стоит там, и сдвиг к врагу спорил бы с разводом каждый такт.
				# Заперт с боков — дальше решает разворот (TURN_MS)
				if _blocked_side(sid, b, F + side * lat):
					lat = 0.0
			adv = clampf(near_al - standoff, 0.0, step)
		# Враг во фланге или за спиной слишком долго — разворот коробки
		var nl := Vector2(near_al, near_sd).normalized()
		if nl.x < TURN_COS and lag < LAG_MAX:
			b["off_lane"] = int(b["off_lane"]) + SWEEP_MS
			if int(b["off_lane"]) >= TURN_MS:
				_turn(sid, b, Vector3(course.x * near_al + side.x * near_sd, 0.0,
					course.z * near_al + side.z * near_sd).normalized())
				return
	# ── СОЮЗНАЯ КОРОБКА ВПЕРЕДИ — ПРЕПЯТСТВИЕ ────────────────────────────────
	# Полоса меряется до ВРАГА, и вторая линия иначе въезжала бы в первую
	# (qa_box_front B: две пары коробок слились внахлёст 0.5). Задняя встаёт
	# за передней на интервал, а пока сама не в контакте — уходит во фланг и
	# удлиняет линию фронта
	var fr: Array = _friend_ahead(sid, b, F)
	if adv > float(fr[0]):
		adv = maxf(float(fr[0]), 0.0)
		if not engaged and lag < LAG_MAX and absf(lat) < 0.01:
			var sg: float = float(fr[1])
			if not _blocked_side(sid, b, F + side * (sg * step)):
				lat = sg * step
			elif not _blocked_side(sid, b, F - side * (sg * step)):
				lat = -sg * step
	# ── НАТИСК В КОНТАКТЕ (ТЗ 25.10.2026, блок 4) ───────────────────────────
	# Коробка, упёршаяся в чужую шеренгу, не замирает: сильнейшая по напору
	# сторона теснит слабейшую, и линия фронта едет. Тянет коробку вперёд
	# только то, что она САМА сдвинула врага (_press) — пустой шаг в тела
	# невозможен, и «упёрся — дерись» у переднего ряда остаётся
	# Давит только собранная коробка (отставание вдвое строже обычного шага):
	# иначе грань уезжала от растянутых рядов, и коробка вытягивалась в
	# глубину и наезжала на соседнюю (qa_box_front B2/B4)
	if _Opt.box_press and engaged and lag < LAG_MAX * PRESS_LAG_K and adv < 0.01 and absf(lat) < 0.01:
		var pr: float = _press(sid, b, lane_e, lane_a, lane_al, dt)
		if pr > 0.0 and pr <= float(fr[0]):
			adv = pr
	var F2: Vector3 = F + course * adv + side * lat
	if engaged:
		b["anchor"] = F
	if lp == Vector3.INF:
		var anc: Vector3 = b["anchor"]
		var far2: float = Vector2(F2.x - anc.x, F2.z - anc.z).length_squared()
		var near2: float = Vector2(F.x - anc.x, F.z - anc.z).length_squared()
		# Отряд игрока держит свой поводок (Unit.CHASE_LEASH, 8 м): коробка не
		# вправе уводить строй дальше, чем ушёл бы боец за агро
		# (qa_squad_leash_test E — бегущую орду гнали на 12 м от постов).
		# Меряется от места, где коробка встала (как у бойца — от поста), а не
		# от якоря контакта: бегущий враг держит контакт у самой грани, и
		# якорь уезжал вместе с ней,
		if int(b["fac"]) == Constants.FACTION_PLAYER and _Opt.squad_leash:
			anc = b["home"]
			far2 = Vector2(F2.x - anc.x, F2.z - anc.z).length_squared()
			near2 = Vector2(F.x - anc.x, F.z - anc.z).length_squared()
			# минус глубина: распад коробки зовёт смыкание, и оно вправе
			# отдать переднему бойцу пост задней шеренги
			var lim: float = maxf(2.0, Unit.CHASE_LEASH - _depth(b))
			if far2 > lim * lim and far2 > near2:
				F2 = F
		elif far2 > CHASE_MAX * CHASE_MAX and far2 > near2:
			F2 = F
	# Развод с союзными коробками — своей коробкой, своим пересчётом и не
	# быстрее своего шага; пока люди отстают от мест, место не уводится
	if lag < LAG_MAX and not engaged:
		F2 += _push_off(sid, b, F2, step)
	# Всё вместе — не быстрее шага коробки
	var mv := Vector2(F2.x - F.x, F2.z - F.z)
	if mv.length() > step:
		mv = mv.normalized() * step
		F2 = Vector3(F.x + mv.x, 0.0, F.z + mv.y)
	b["moving"] = Vector2(F2.x - F.x, F2.z - F.z).length() > 0.01
	b["F"] = F2
	_write_goals(b)

static func _row_w(r: int) -> float:
	return float(PRESS_ROW_W[r]) if r < PRESS_ROW_W.size() else PRESS_ROW_TAIL

## Натиск коробки sid: если её напор перевешивает упор врагов полосы, враги
## на глубину PRESS_DEPTH отходят на шаг, их коробки — тоже. Возвращает шаг
## (метры за пересчёт), на который можно подать свою грань; 0 — равновесие
func _press(sid: int, b: Dictionary, lane_e: Array, lane_a: PackedFloat32Array,
		lane_al: float, dt: float) -> float:
	if lane_e.is_empty():
		return 0.0
	var units: Array = b["units"]
	var row: PackedInt32Array = b["row"]
	var gap: float = b["gap"]
	var mine := 0.0
	for i in range(units.size()):
		var m = units[i]
		if m == null or not is_instance_valid(m):
			continue
		var u: Unit = m
		if u.is_dead():
			continue
		mine += u._push_power() * _row_w(row[i])
	if mine <= 0.0:
		return 0.0
	var theirs := 0.0
	var pushed: Array = []
	for k in range(lane_e.size()):
		var e_raw = lane_e[k]
		if e_raw == null or not is_instance_valid(e_raw):
			continue
		var e: Unit = e_raw
		if e.is_dead():
			continue
		var dep: float = float(lane_a[k]) - lane_al
		if dep > PRESS_DEPTH:
			continue
		var rs: float = maxf(_UStatsB.stance_stat(e.stance, "push_resist", 1.0), 0.1)
		theirs += e._stand_power() * _row_w(int(maxf(dep, 0.0) / gap)) / rs
		pushed.append(e)
	if pushed.is_empty():
		return 0.0
	var ratio: float = mine / maxf(theirs, 0.01)
	if ratio < 1.0 + PRESS_DEADBAND:
		return 0.0
	var share: float = clampf((ratio - 1.0) / PRESS_FULL, 0.15, 1.0)
	var d: float = PRESS_SPEED * share * dt
	var course: Vector3 = b["course"]
	var mv: Vector3 = course * d
	var moved := 0
	var esq: Dictionary = {}
	for e2 in pushed:
		var e: Unit = e2
		var gp: Vector3 = e.global_position
		var np := Vector3(gp.x + mv.x, gp.y, gp.z + mv.z)
		# Те же запреты, что у толчка на удар (Unit._apply_push): не в чужое
		# тело (за спиной врага бывает наш фланг), не в скалу, не в воду
		if GameManager.unit_grid.enemy_block(e, np, Unit.BLOCK_RADIUS).length_squared() > 1e-8:
			continue
		if GameManager.is_cliff(np.x, np.z) and not GameManager.is_cliff(gp.x, gp.z):
			continue
		if GameManager.is_water(np.x, np.z):
			continue
		var lim: Vector2 = GameManager.clamp_to_map(np.x, np.z)
		np = Vector3(lim.x, GameManager.get_terrain_height(lim.x, lim.y), lim.y)
		e.global_position = np
		# Строку ядра сводим сразу: дремлющий в ядре боец (дрёма перезарядки)
		# GDScript-тика не получит, и разведение вернуло бы его по колонке
		e.sync_row()
		moved += 1
		if e.squad_id > 0:
			esq[e.squad_id] = true
	# Большинство не сдвинулось (зажаты своими, кромкой) — линия стоит
	if moved * 2 < pushed.size():
		return 0.0
	for es in esq:
		var eb: Variant = boxes.get(es)
		if eb == null or int(es) == sid:
			continue
		var ebd: Dictionary = eb
		ebd["F"] = (ebd["F"] as Vector3) + mv
		ebd["anchor"] = (ebd["anchor"] as Vector3) + mv
		_write_goals(ebd)
	presses += 1
	press_dist += d
	return d

## Выбитые уходят из коробки; в каждой колонке выжившие сдвигаются вперёд на
## освободившиеся места — шаг за шагом, без перехода в чужую колонку
func _refill(sid: int, b: Dictionary) -> void:
	var units: Array = b["units"]
	var col: PackedInt32Array = b["col"]
	var row: PackedInt32Array = b["row"]
	var nu: Array = []
	var nc := PackedInt32Array()
	var nr := PackedInt32Array()
	var lost := false
	for i in range(units.size()):
		var m = units[i]
		if m == null or not is_instance_valid(m):
			lost = true
			continue
		var u := m as Unit
		if u == null or u.is_dead() or u.squad_id != sid or u.garrisoned:
			if u != null and is_instance_valid(u):
				u.box_leave()
			lost = true
			continue
		nu.append(u)
		nc.append(col[i])
		nr.append(row[i])
	if lost:
		# По колонкам: ряды выживших — 0, 1, 2… в прежнем порядке
		var by_col: Dictionary = {}
		for i in range(nu.size()):
			var k: int = nc[i]
			if not by_col.has(k):
				by_col[k] = []
			(by_col[k] as Array).append([nr[i], i])
		for k in by_col:
			var lst: Array = by_col[k]
			lst.sort_custom(func(a, b2): return int(a[0]) < int(b2[0]))
			for r in range(lst.size()):
				var idx: int = int(lst[r][1])
				if nr[idx] != r:
					nr[idx] = r
					refills += 1
	b["units"] = nu
	b["col"] = nc
	b["row"] = nr

## Перестроение на новый фронт: та же процедура, что при включении, с курсом
## на врага. Счётчик для стендов
func _turn(sid: int, b: Dictionary, course: Vector3) -> void:
	var nb: Dictionary = _build(sid, course, int(b["cols"]))
	if nb.is_empty():
		return
	nb["seen"] = b["seen"]
	nb["anchor"] = b["anchor"]
	nb["home"] = b["home"]
	boxes[sid] = nb
	turns += 1

## Места бойцам: F + бок·колонка − курс·ряд. Проходимость — по пяти точкам
## коробки (углы и центр); если хоть одна закрыта, проверяется каждый боец
## (место в лесу или воде — боец идёт обычной дорогой, _box_goal = INF)
func _write_goals(b: Dictionary) -> void:
	var units: Array = b["units"]
	var col: PackedInt32Array = b["col"]
	var row: PackedInt32Array = b["row"]
	var F: Vector3 = b["F"]
	var course: Vector3 = b["course"]
	var side: Vector3 = b["side"]
	var gap: float = b["gap"]
	var cols: int = b["cols"]
	var moving: bool = b["moving"]
	var rows_n := 0
	for r in row:
		rows_n = maxi(rows_n, r + 1)
	var hw: float = float(cols - 1) * gap * 0.5
	var depth: float = float(maxi(rows_n - 1, 0)) * gap
	var each := false
	if GameManager.world_bounds_enabled:
		for q in [Vector2(0.0, 0.0), Vector2(-hw, 0.0), Vector2(hw, 0.0),
				Vector2(-hw, -depth), Vector2(hw, -depth)]:
			var pq: Vector3 = F + side * q.x + course * q.y
			if not GameManager.is_passable(pq.x, pq.z):
				each = true
				break
	var mid: float = float(cols - 1) * 0.5
	for i in range(units.size()):
		# Правило 5: боец мог пасть после refill этой коробки
		var m = units[i]
		if m == null or not is_instance_valid(m):
			continue
		var u: Unit = m
		var g: Vector3 = F + side * ((float(col[i]) - mid) * gap) - course * (float(row[i]) * gap)
		if each and not GameManager.is_passable(g.x, g.z):
			g = Vector3.INF
		u.box_set(g, row[i], moving)

## ── КОРОБКИ ОДНОЙ СТОРОНЫ НЕ НАКЛАДЫВАЮТСЯ ─────────────────────────────────
## Сдвиг вбок (по своей оси) прочь от союзных коробок, перекрытых с этой и
## по глубине, и поперёк: на половину перекрытия плюс SIDE_GAP — вторую
## половину сделает сосед своим пересчётом. Не больше шага коробки за
## пересчёт. Несколько отрядов, брошенных в одну точку, так ложатся в линию
## фронта. ПЕРВАЯ ВЕРСИЯ разводила все пары в каждом кадре (сдвиг до 0.4 м
## за кадр, 24 м/с): места уезжали на 8 м, люди отставали на 3-5 м, а
## разворот ставил коробку на чужую толпу (qa_box_front B)
func _push_off(sid: int, b: Dictionary, F2: Vector3, step: float) -> Vector3:
	var ca: Vector3 = b["course"]
	var sa: Vector3 = b["side"]
	var hw: float = _half_w(b)
	var dep: float = _depth(b)
	var acc := 0.0
	for k in boxes:
		if int(k) == sid:
			continue
		var B: Dictionary = boxes[k]
		if int(B["fac"]) != int(b["fac"]):
			continue
		var d: Vector3 = (B["F"] as Vector3) - F2
		var da: float = d.dot(ca)
		if da - _depth(B) > 0.3 or da < -dep - 0.3:
			continue
		var ds: float = d.dot(sa)
		var need: float = hw + _half_w(B) + SIDE_GAP - absf(ds)
		# Сантиметры не разводим: на стыке двух коробок это дрожь мест
		if need <= 0.05:
			continue
		var sgn: float = signf(ds)
		if sgn == 0.0:
			sgn = 1.0 if sid < int(k) else -1.0
		acc -= sgn * need * 0.5
	if acc == 0.0:
		return Vector3.ZERO
	side_pushes += 1
	return sa * clampf(acc, -step, step)

## Ближайшая союзная коробка ВПЕРЕДИ в своей полосе: [сколько можно
## пройти, в какую сторону её обходить]. Нет такой — [INF, 0]
func _friend_ahead(sid: int, b: Dictionary, F: Vector3) -> Array:
	var ca: Vector3 = b["course"]
	var sa: Vector3 = b["side"]
	var hw: float = _half_w(b)
	var gap: float = b["gap"]
	var room := INF
	var sg := 0.0
	for k in boxes:
		if int(k) == sid:
			continue
		var B: Dictionary = boxes[k]
		if int(B["fac"]) != int(b["fac"]):
			continue
		var d: Vector3 = (B["F"] as Vector3) - F
		var da: float = d.dot(ca)
		if da <= 0.05:
			continue
		var ds: float = d.dot(sa)
		if absf(ds) >= hw + _half_w(B) + SIDE_GAP:
			continue
		var r: float = da - _depth(B) - gap
		if r < room:
			room = r
			sg = -signf(ds)
			if sg == 0.0:
				sg = 1.0 if sid < int(k) else -1.0
	return [room, sg]

## Встала бы коробка sid с передней гранью F2 внахлёст на союзную
func _blocked_side(sid: int, b: Dictionary, F2: Vector3) -> bool:
	var ca: Vector3 = b["course"]
	var sa: Vector3 = b["side"]
	var hw: float = _half_w(b)
	var dep: float = _depth(b)
	for k in boxes:
		if int(k) == sid:
			continue
		var B: Dictionary = boxes[k]
		if int(B["fac"]) != int(b["fac"]):
			continue
		var d: Vector3 = (B["F"] as Vector3) - F2
		var da: float = d.dot(ca)
		if da - _depth(B) > 0.3 or da < -dep - 0.3:
			continue
		if absf(d.dot(sa)) < hw + _half_w(B) + SIDE_GAP:
			return true
	return false

func _half_w(b: Dictionary) -> float:
	return float(int(b["cols"]) - 1) * float(b["gap"]) * 0.5 + 0.3

func _depth(b: Dictionary) -> float:
	var rows_n := 0
	for r in (b["row"] as PackedInt32Array):
		rows_n = maxi(rows_n, r + 1)
	return float(maxi(rows_n - 1, 0)) * float(b["gap"])

## Стендам: сколько живых коробок и сколько бойцов в них
func box_of(sid: int) -> Dictionary:
	var b: Variant = boxes.get(sid)
	return b if b != null else {}
