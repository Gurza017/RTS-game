extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## КОМАНДИР ШТУРМА ОРДЫ — «ТАКТИЧЕСКИЙ РАЗУМ ГОБЛИНОВ» (заказ 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Вожак (GoblinAI) решает, КУДА идёт орда (фаза, точка). Этот объект решает,
## КАК она штурмует базу: вместо слепой лавины армия собирается на безопасной
## дистанции, выбирает ПАТТЕРН и разыгрывает его состояниями:
##
##   ASSEMBLING       сбор на линии в ASSAULT_STANDOFF м от ближайшей чужой
##                    постройки — вне полёта стрелы и башни, в зоне видимости
##   FEINT_ATTACK     паттерн А «хитрый провокатор»: лёгкая пехота щупает
##                    фланг и отходит к линии, за ней тот же фланг колет
##                    конница и мгновенно отходит; вектор меняется, и после
##                    PROBE_CYCLES прощупываний — общий навал в САМОЕ СЛАБОЕ
##                    место (где чужих меньше всего)
##   FULL_CHARGE      общий штурм; паттерн Б «откатные волны» входит сюда
##                    через удар конницы в лоб и её мгновенный отход, а
##                    пехота заходит в брешь; затяжной замес с потерями —
##                    отход всей армией
##   FLANK_SWEEP      паттерн В «широкий веер»: три группы (левый фланг,
##                    центр, правый) бьют с трёх сторон каскадом
##   RETREAT_AND_HEAL армия потеряла больше ASSAULT_RETREAT_HP запаса — все
##                    отходят в лагерь (деревня или передовая точка вне башен),
##                    лечатся у костров, восстановившись — новая волна с
##                    ДРУГИМ паттерном
##
## РЕЖИМОВ ТРИ (уточнение владельца): «штурм» (фаза охоты, выше), «марш»
## (волна в центр: тело идёт линией, конница-ДОЗОР впереди, контакт — дозор
## к телу и общий штурм) и «оборона» (деревня под ударом: пехота держит рубеж
## у костров и не бежит на убой, конница колет с флангов и отходит, раненые
## лечатся у костров). Отход по потерям и лечение общие для всех трёх.
##
## ── ЧТО ЗДЕСЬ НАМЕРЕННО НЕ НАПИСАНО ────────────────────────────────────────
## Ни движения, ни боя: командир выдаёт ПЛАН — список записей для очереди
## приказов вожака (GoblinAI._order_queue / _issue_squad). Решения принимаются
## раз в такт вожака (THINK_INTERVAL) и по ОТРЯДУ. Часы — clock вожака
## (игровые секунды): стенд двигает их сам и не ждёт минут стенными часами.
##
## ПЛАН НЕ ПЕРЕИЗДАЁТ НЕИЗМЕНИВШИЙСЯ ПРИКАЗ (правило stagnant target): марш в
## ту же точку — не чаще REISSUE_SEC, атака отряду, уже втянутому в бой, — не
## выдаётся вовсе, отход выдаётся один раз на смену состояния. Иначе каждые две
## секунды сотня гоблинов получала бы command_move и не спала бы никогда
## (см. «цена костыля была не там, где её мерили» в CLAUDE.md).

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

# ── СОСТОЯНИЯ АРМИИ ─────────────────────────────────────────────────────────
const ST_IDLE      := "idle"
const ST_ASSEMBLE  := "assembling"
const ST_FEINT     := "feint_attack"
const ST_SWEEP     := "flank_sweep"
const ST_CHARGE    := "full_charge"
const ST_RETREAT   := "retreat_and_heal"
const ST_ADVANCE   := "advance"        # марш: тело линией, дозор впереди
const ST_DEFEND    := "defend"         # оборона: рубеж у костров

# ── РЕЖИМЫ ──────────────────────────────────────────────────────────────────
const MODE_ASSAULT := "assault"
const MODE_ADVANCE := "advance"
const MODE_DEFENSE := "defense"

# ── ПАТТЕРНЫ ────────────────────────────────────────────────────────────────
const PAT_PROBE   := "probe"        # А: хитрый провокатор
const PAT_HITRUN  := "hit_and_run"  # Б: откатные волны
const PAT_FAN     := "fan"          # В: широкий веер
const PATTERNS := [PAT_PROBE, PAT_HITRUN, PAT_FAN]

## Как часто повторять марш в ту же точку (страховка от застрявших)
const REISSUE_SEC := 8.0

var state: String = ST_IDLE
var mode: String = MODE_ASSAULT
var pattern: String = ""
## Марш: дозор (конный отряд) и точка контакта
var vanguard_sid: int = 0
var contact_pt: Vector3 = Vector3.INF
## Оборона: центр угрозы (INF — угрозы нет), сторона и фаза удара конницы
var threat_pt: Vector3 = Vector3.INF
var _def_side: int = 1
var _def_cav_phase: String = "strike"
var _def_cav_since: float = 0.0
## Отряды, ушедшие к кострам лечиться (sid → true) — до ASSAULT_REARM_HP
var wounded: Dictionary = {}
## Стенд выставляет, чтобы разыграть конкретный паттерн; пусто — случайный
var force_pattern: String = ""
var last_pattern: String = ""
var last_action: String = ""
## Волны штурма: растёт на каждом выходе из RETREAT_AND_HEAL
var waves: int = 0

# ── ГЕОМЕТРИЯ ТЕКУЩЕГО ШТУРМА ───────────────────────────────────────────────
var aim: Vector3 = Vector3.ZERO          # точка базы, куда идёт орда
var front_pt: Vector3 = Vector3.ZERO     # ближайшая чужая постройка (край базы)
var axis: Vector3 = Vector3.FORWARD      # от армии к базе
var right: Vector3 = Vector3.RIGHT       # поперёк оси (фланги)
var assembly_pt: Vector3 = Vector3.ZERO  # центр линии сбора
var camp_pt: Vector3 = Vector3.ZERO      # куда отходить лечиться
var village: Vector3 = Vector3.ZERO

# ── ХОД ПАТТЕРНА ────────────────────────────────────────────────────────────
var _state_since: float = 0.0
var _probe_cycle: int = 0            # сколько векторов уже прощупано
var _probe_side: int = 1             # +1 правый фланг, −1 левый, 0 центр
var _probe_phase: String = ""        # "infantry" / "infantry_back" / "cavalry" / "cavalry_back" / "pause"
var _probe_since: float = 0.0
var probe_sid: int = 0               # отряд-щуп (лёгкая пехота)
var probe_cav_sid: int = 0           # конница укола
var weak_side: int = 0               # куда пришёлся общий навал
var _hr_phase: String = ""           # "cavalry" / "infantry"
var _hr_since: float = 0.0
var _charge_hp0: float = 1.0         # доля запаса на входе в штурм
var _retreat_issued: Dictionary = {} # sid → true: приказ отхода уже выдан
var _sweep_groups: Dictionary = {}   # sid → −1/0/+1
var _sweep_started: float = 0.0
var _sweep_issued: Dictionary = {}   # sid → true
## Что уже приказано (stagnant target): sid → {"goal","at","kind"}
var _ordered: Dictionary = {}
## Диагностика для стенда: доля запаса армии на последнем такте
var hp_frac: float = 1.0

func reset() -> void:
	state = ST_IDLE
	pattern = ""
	last_action = ""
	waves = 0
	_ordered.clear()
	_retreat_issued.clear()
	_sweep_groups.clear()
	_sweep_issued.clear()
	probe_sid = 0
	probe_cav_sid = 0
	weak_side = 0
	_probe_cycle = 0
	vanguard_sid = 0
	contact_pt = Vector3.INF
	threat_pt = Vector3.INF
	wounded.clear()

## Смена режима сбрасывает ход: у штурма, марша и обороны свои состояния
func _set_mode(m: String) -> void:
	if mode == m:
		return
	reset()
	mode = m

func is_active() -> bool:
	return state != ST_IDLE

## Отход: лечение уже кончилось, командир ждёт нового штурма?
func is_retreating() -> bool:
	return state == ST_RETREAT

# ═════════════════════════════════════════════════════════════════════════════
# ГЛАВНЫЙ ВХОД: ПЛАН НА ТАКТ
# ═════════════════════════════════════════════════════════════════════════════
## field — полевые отряды орды (словари вожака: id/type/members), p_aim — точка
## базы, clock — игровые секунды. Возвращает записи для _order_queue.
func plan(field: Array, p_aim: Vector3, p_village: Vector3, clock: float) -> Array:
	_set_mode(MODE_ASSAULT)
	village = p_village
	aim = p_aim
	last_action = ""
	var out: Array = []
	if field.is_empty():
		if state != ST_IDLE:
			state = ST_IDLE
			last_action = "армии нет — командир спит"
		return out
	var army_c: Vector3 = _army_center(field)
	_refresh_geometry(army_c)
	hp_frac = _army_hp_frac(field)

	# ── ОТХОД ПЕРЕБИВАЕТ ЛЮБОЙ ПАТТЕРН ───────────────────────────────────────
	if state != ST_RETREAT and state != ST_IDLE and _should_retreat(field, clock):
		_enter(ST_RETREAT, clock)
		last_action = "потери: запас %.0f %% — отход в лагерь" % (hp_frac * 100.0)

	match state:
		ST_IDLE:
			_start_assault(clock)
			out = _plan_assemble(field, clock)
		ST_ASSEMBLE:
			if _assembled(field) or clock - _state_since >= _GobCfg.ASSAULT_ASSEMBLE_TIMEOUT:
				_begin_pattern(clock)
				out = _plan_state(field, clock)
			else:
				out = _plan_assemble(field, clock)
		_:
			out = _plan_state(field, clock)
	return out

func _plan_state(field: Array, clock: float) -> Array:
	match state:
		ST_FEINT:   return _plan_probe(field, clock)
		ST_SWEEP:   return _plan_sweep(field, clock)
		ST_CHARGE:  return _plan_charge(field, clock)
		ST_RETREAT: return _plan_retreat(field, clock)
	return []

func _enter(st: String, clock: float) -> void:
	state = st
	_state_since = clock
	_ordered.clear()
	if st == ST_RETREAT:
		_retreat_issued.clear()

func _start_assault(clock: float) -> void:
	pattern = _pick_pattern()
	_enter(ST_ASSEMBLE, clock)
	_probe_cycle = 0
	_probe_side = 1 if (randi() % 2) == 0 else -1
	_probe_phase = ""
	probe_sid = 0
	probe_cav_sid = 0
	weak_side = 0
	_hr_phase = ""
	_sweep_groups.clear()
	_sweep_issued.clear()
	last_action = "штурм: паттерн %s, сбор на %.0f м" % [pattern, _GobCfg.ASSAULT_STANDOFF]

func _pick_pattern() -> String:
	if force_pattern != "" and PATTERNS.has(force_pattern):
		return force_pattern
	# Новая волна — ДРУГОЙ паттерн: игрок не должен видеть одно и то же дважды
	var pool: Array = []
	for p in PATTERNS:
		if String(p) != last_pattern:
			pool.append(p)
	return String(pool[randi() % pool.size()])

func _begin_pattern(clock: float) -> void:
	last_pattern = pattern
	match pattern:
		PAT_PROBE:
			_enter(ST_FEINT, clock)
			_probe_phase = "infantry"
			_probe_since = clock
			last_action = "провокатор: щуп на фланг %d" % _probe_side
		PAT_FAN:
			_enter(ST_SWEEP, clock)
			_sweep_started = clock
			last_action = "веер: три направления"
		_:
			_enter(ST_CHARGE, clock)
			_hr_phase = "cavalry"
			_hr_since = clock
			_charge_hp0 = hp_frac
			last_action = "откатные волны: конница в лоб"

# ═════════════════════════════════════════════════════════════════════════════
# ГЕОМЕТРИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _refresh_geometry(army_c: Vector3) -> void:
	# Край базы — ближайшая к армии чужая постройка; нет построек — сама точка
	front_pt = aim
	var bd := INF
	# Снимок — ПАРА [узлы, xz] (спринт 14): обход самой пары молча давал
	# ноль построек, и орда не выбирала здания целью вовсе
	for b in (GameManager.enemy_buildings_snapshot(Constants.FACTION_GOBLIN)[0] as Array):
		if b == null or not is_instance_valid(b):
			continue
		var bld := b as Building
		if bld == null or bld.is_dead():
			continue
		var p: Vector3 = bld.global_position
		# Только постройки ЭТОЙ базы: чужой дом за полкарты — не край цели
		if Vector2(p.x - aim.x, p.z - aim.z).length() > _GobCfg.ASSAULT_BASE_RADIUS:
			continue
		var d: float = Vector2(p.x - army_c.x, p.z - army_c.z).length_squared()
		if d < bd:
			bd = d
			front_pt = p
	var to := Vector3(front_pt.x - army_c.x, 0.0, front_pt.z - army_c.z)
	# Ось замораживается на время штурма: пока армия стоит на линии, «от армии
	# к базе» вырождалось бы в дрожание, и фланги менялись бы местами
	if state == ST_IDLE or state == ST_RETREAT:
		if to.length() > 1.0:
			axis = to.normalized()
			right = Vector3(-axis.z, 0.0, axis.x)
	assembly_pt = front_pt - axis * _GobCfg.ASSAULT_STANDOFF
	# Лагерь: деревня рядом — она, иначе передовая точка вне башен по оси отхода
	var to_village: float = Vector2(front_pt.x - village.x, front_pt.z - village.z).length()
	if to_village <= _GobCfg.ASSAULT_CAMP_FAR:
		camp_pt = village
	else:
		camp_pt = front_pt - axis * _GobCfg.ASSAULT_CAMP_DIST

## Точка фланга: side −1 / 0 / +1
func flank_point(side: int) -> Vector3:
	return front_pt + right * (float(side) * _GobCfg.PROBE_FLANK_OFFSET)

## Место отряда на линии сбора: отряды расходятся поперёк оси
func assembly_slot(idx: int, total: int) -> Vector3:
	var off: float = (float(idx) - float(total - 1) * 0.5) * _GobCfg.ASSAULT_LINE_STEP
	return assembly_pt + right * off

func _army_center(field: Array) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for s in field:
		var c: Vector3 = _squad_center(s)
		if c == Vector3.INF:
			continue
		acc += c
		n += 1
	return (acc / float(n)) if n > 0 else village

func _squad_center(sq: Dictionary) -> Vector3:
	var live: Array = []
	for m in (sq["members"] as Array):
		if is_instance_valid(m) and not (m as Unit).is_dead():
			live.append(m)
	if live.is_empty():
		return Vector3.INF
	return GameManager._centroid_of(live)

func _army_hp_frac(field: Array) -> float:
	var cur := 0.0
	var mx := 0.0
	for s in field:
		for m in (s["members"] as Array):
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u == null or u.is_dead():
				continue
			cur += u.current_health
			mx += u.max_health
	return (cur / mx) if mx > 0.0 else 1.0

## Собралась ли армия на линии: доля отрядов у своих мест
func _assembled(field: Array) -> bool:
	var n: int = field.size()
	var ok := 0
	for i in range(n):
		var c: Vector3 = _squad_center(field[i])
		if c == Vector3.INF:
			continue
		var slot: Vector3 = assembly_slot(i, n)
		if Vector2(c.x - slot.x, c.z - slot.z).length() <= _GobCfg.ASSAULT_ASSEMBLE_RADIUS:
			ok += 1
	return float(ok) >= float(n) * _GobCfg.ASSAULT_ASSEMBLE_FRAC

## Сколько чужих (не орды) стоит у точки — так ищется слабое место
func defenders_near(p: Vector3, radius: float) -> int:
	var n := 0
	for u in GameManager.army.query_radius(p.x, p.z, radius):
		if u == null or not is_instance_valid(u):
			continue
		var un := u as Unit
		if un == null or un.is_dead() or int(un.faction) == Constants.FACTION_GOBLIN:
			continue
		n += 1
	return n

func weakest_side() -> int:
	var best := 0
	var bn := 1 << 30
	for side in [-1, 0, 1]:
		var n: int = defenders_near(flank_point(int(side)), _GobCfg.PROBE_FLANK_OFFSET * 0.8)
		if n < bn:
			bn = n
			best = int(side)
	return best

# ═════════════════════════════════════════════════════════════════════════════
# ПРИКАЗЫ (записи плана)
# ═════════════════════════════════════════════════════════════════════════════
## Марш отряда в точку: не переиздаётся, если точка та же (в пределах tol) и
## срок не вышел
func _move(sq: Dictionary, goal: Vector3, clock: float, out: Array, tol: float = 0.5) -> void:
	var sid: int = int(sq["id"])
	var prev: Variant = _ordered.get(sid)
	if prev != null:
		var pd: Dictionary = prev
		if String(pd["kind"]) == "move" and (pd["goal"] as Vector3).distance_to(goal) < tol \
				and clock - float(pd["at"]) < REISSUE_SEC:
			return
	_ordered[sid] = {"kind": "move", "goal": goal, "at": clock}
	var c: Vector3 = _squad_center(sq)
	out.append({"sq": sq, "goal": goal, "center": (c if c != Vector3.INF else goal),
		"wake": true})

## Атака: ближайший чужой у точки (боец или постройка), иначе марш к точке.
## Отряд, уже втянутый в бой, приказа не получает (его ведут сцепка и агро)
func _attack_at(sq: Dictionary, p: Vector3, clock: float, out: Array, radius: float) -> void:
	var sid: int = int(sq["id"])
	if GameManager.squad_in_combat(sid):
		return
	var foe: Node3D = _nearest_foe(p, radius)
	if foe == null:
		foe = _nearest_building(p, radius)
	if foe == null:
		_move(sq, p, clock, out)
		return
	var prev: Variant = _ordered.get(sid)
	if prev != null:
		var pd: Dictionary = prev
		if String(pd["kind"]) == "attack" and pd.get("foe") == foe \
				and clock - float(pd["at"]) < REISSUE_SEC:
			return
	_ordered[sid] = {"kind": "attack", "goal": p, "at": clock, "foe": foe}
	out.append({"sq": sq, "foe": foe, "wake": true})

## Отход отряда в точку: режим отхода (сквозь тела, без агро), один раз
func _withdraw(sq: Dictionary, goal: Vector3, clock: float, out: Array) -> void:
	var sid: int = int(sq["id"])
	var prev: Variant = _ordered.get(sid)
	if prev != null:
		var pd: Dictionary = prev
		if String(pd["kind"]) == "retreat" and (pd["goal"] as Vector3).distance_to(goal) < 0.5 \
				and clock - float(pd["at"]) < REISSUE_SEC:
			return
	_ordered[sid] = {"kind": "retreat", "goal": goal, "at": clock}
	var c: Vector3 = _squad_center(sq)
	out.append({"sq": sq, "goal": goal, "center": (c if c != Vector3.INF else goal),
		"retreat": true})

func _nearest_foe(from: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius * radius
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		var seen = GameManager.army.nearest_of_side(from.x, from.z, f, radius)
		if seen == null:
			continue
		var nd := seen as Node3D
		var d: float = from.distance_squared_to(nd.global_position)
		if d < bd:
			bd = d
			best = nd
	return best

func _nearest_building(from: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var bd: float = radius * radius
	# Снимок — ПАРА [узлы, xz] (спринт 14): обход самой пары молча давал
	# ноль построек, и орда не выбирала здания целью вовсе
	for b in (GameManager.enemy_buildings_snapshot(Constants.FACTION_GOBLIN)[0] as Array):
		if b == null or not is_instance_valid(b):
			continue
		var bld := b as Building
		if bld == null or bld.is_dead() or not GameManager.goblin_may_raze(bld):
			continue
		var d: float = from.distance_squared_to(bld.global_position)
		if d < bd:
			bd = d
			best = bld
	return best

func _is_cavalry(sq: Dictionary) -> bool:
	return String(sq["type"]) == "goblin_rider"

func _sid(sq: Dictionary) -> int:
	return int(sq["id"])

func _find(field: Array, sid: int) -> Dictionary:
	for s in field:
		if int((s as Dictionary)["id"]) == sid:
			return s
	return {}

# ═════════════════════════════════════════════════════════════════════════════
# СБОР
# ═════════════════════════════════════════════════════════════════════════════
func _plan_assemble(field: Array, clock: float) -> Array:
	var out: Array = []
	var n: int = field.size()
	for i in range(n):
		_move(field[i], assembly_slot(i, n), clock, out)
	return out

# ═════════════════════════════════════════════════════════════════════════════
# ПАТТЕРН А: ХИТРЫЙ ПРОВОКАТОР
# ═════════════════════════════════════════════════════════════════════════════
## Щуп — один пеший отряд, укол — один конный; остальные держат линию. Каждый
## вектор: пехота идёт, дерётся PROBE_INFANTRY_SEC, отходит; конница колет
## PROBE_CAVALRY_SEC и отходит; пауза; следующий вектор. После PROBE_CYCLES —
## общий навал в слабейшее место
func _plan_probe(field: Array, clock: float) -> Array:
	var out: Array = []
	var n: int = field.size()
	# Щуп и конница выбираются один раз на вектор (и заново, если выбиты)
	if probe_sid == 0 or _find(field, probe_sid).is_empty():
		probe_sid = _pick_probe(field, false)
	if probe_cav_sid == 0 or _find(field, probe_cav_sid).is_empty():
		probe_cav_sid = _pick_probe(field, true)
	var fp: Vector3 = flank_point(_probe_side)
	var elapsed: float = clock - _probe_since
	match _probe_phase:
		"infantry":
			if elapsed >= _GobCfg.PROBE_INFANTRY_SEC:
				_probe_phase = "infantry_back"
				_probe_since = clock
				last_action = "щуп отходит к линии"
		"infantry_back":
			if elapsed >= _GobCfg.PROBE_RECOVER_SEC:
				_probe_phase = "cavalry" if probe_cav_sid != 0 else "pause"
				_probe_since = clock
				last_action = "конница колет фланг %d" % _probe_side
		"cavalry":
			if elapsed >= _GobCfg.PROBE_CAVALRY_SEC:
				_probe_phase = "cavalry_back"
				_probe_since = clock
				last_action = "конница отходит"
		"cavalry_back":
			if elapsed >= _GobCfg.PROBE_RECOVER_SEC:
				_probe_phase = "pause"
				_probe_since = clock
		"pause":
			_probe_cycle += 1
			if _probe_cycle >= _GobCfg.PROBE_CYCLES:
				weak_side = weakest_side()
				_enter(ST_CHARGE, clock)
				_hr_phase = "all"
				_charge_hp0 = hp_frac
				last_action = "прощупали — общий навал на сторону %d" % weak_side
				return _plan_charge(field, clock)
			# Смена вектора: другой фланг, потом центр
			_probe_side = -_probe_side if _probe_cycle == 1 else 0
			_probe_phase = "infantry"
			_probe_since = clock
			probe_sid = _pick_probe(field, false)
			probe_cav_sid = _pick_probe(field, true)
			fp = flank_point(_probe_side)
			last_action = "смена вектора: щуп на сторону %d" % _probe_side
	# Приказы
	for i in range(n):
		var sq: Dictionary = field[i]
		var sid: int = _sid(sq)
		if sid == probe_sid:
			match _probe_phase:
				"infantry":
					_attack_at(sq, fp, clock, out, _GobCfg.PROBE_FLANK_OFFSET)
				_:
					_withdraw(sq, assembly_slot(i, n), clock, out)
			continue
		if sid == probe_cav_sid:
			match _probe_phase:
				"cavalry":
					_attack_at(sq, fp, clock, out, _GobCfg.PROBE_FLANK_OFFSET)
				"infantry", "infantry_back", "pause":
					_move(sq, assembly_slot(i, n), clock, out)
				_:
					_withdraw(sq, assembly_slot(i, n), clock, out)
			continue
		_move(sq, assembly_slot(i, n), clock, out)
	return out

## Щуп — пеший отряд (не конница) с наибольшим составом; конница — конный
func _pick_probe(field: Array, cavalry: bool) -> int:
	var best := 0
	var bn := -1
	for s in field:
		var sq: Dictionary = s
		if _is_cavalry(sq) != cavalry:
			continue
		var n: int = (sq["members"] as Array).size()
		if n > bn:
			bn = n
			best = _sid(sq)
	return best

# ═════════════════════════════════════════════════════════════════════════════
# ПАТТЕРН В: ШИРОКИЙ ВЕЕР
# ═════════════════════════════════════════════════════════════════════════════
func _plan_sweep(field: Array, clock: float) -> Array:
	var out: Array = []
	if _sweep_groups.is_empty():
		# Три группы по порядку на линии: левые — влево, средние — в центр,
		# правые — вправо; конница уходит на фланги первой
		var n: int = field.size()
		for i in range(n):
			var sq: Dictionary = field[i]
			var third: int = (i * 3) / maxi(n, 1)
			_sweep_groups[_sid(sq)] = third - 1
	var elapsed: float = clock - _sweep_started
	for s in field:
		var sq: Dictionary = s
		var side: int = int(_sweep_groups.get(_sid(sq), 0))
		# Каскад: центр идёт первым, фланги — с задержкой FAN_CASCADE_SEC
		var delay: float = 0.0 if side == 0 else _GobCfg.FAN_CASCADE_SEC * (1.0 if side < 0 else 2.0)
		if elapsed < delay:
			continue
		_attack_at(sq, flank_point(side) if side != 0 else front_pt, clock, out, _GobCfg.FAN_OFFSET)
	# Веер после входа в контакт живёт как общий штурм: отход по потерям
	if elapsed >= _GobCfg.FAN_CASCADE_SEC * 2.0 + 1.0 and state == ST_SWEEP:
		_enter(ST_CHARGE, clock)
		_hr_phase = "all"
		_charge_hp0 = hp_frac
		last_action = "веер вошёл в бой"
	return out

# ═════════════════════════════════════════════════════════════════════════════
# ОБЩИЙ ШТУРМ (и паттерн Б: откатные волны)
# ═════════════════════════════════════════════════════════════════════════════
func _plan_charge(field: Array, clock: float) -> Array:
	var out: Array = []
	var target: Vector3 = flank_point(weak_side) if weak_side != 0 else front_pt
	match _hr_phase:
		"cavalry":
			# Конница бьёт в лоб, пехота ждёт на линии
			if clock - _hr_since >= _GobCfg.HR_CAVALRY_SEC:
				_hr_phase = "infantry"
				_hr_since = clock
				last_action = "конница откатывается, пехота в брешь"
			var n: int = field.size()
			for i in range(n):
				var sq: Dictionary = field[i]
				if _is_cavalry(sq):
					_attack_at(sq, front_pt, clock, out, _GobCfg.ASSAULT_STANDOFF)
				else:
					_move(sq, assembly_slot(i, n), clock, out)
		"infantry":
			# Конница отходит к линии, пехота заходит в брешь; через
			# HR_CAVALRY_BACK_SEC конница возвращается в бой вместе со всеми
			var back_done: bool = clock - _hr_since >= _GobCfg.HR_CAVALRY_BACK_SEC
			var n2: int = field.size()
			for i in range(n2):
				var sq: Dictionary = field[i]
				if _is_cavalry(sq) and not back_done:
					_withdraw(sq, assembly_slot(i, n2), clock, out)
				else:
					_attack_at(sq, front_pt, clock, out, _GobCfg.ASSAULT_STANDOFF)
			if back_done:
				_hr_phase = "all"
		_:
			for s in field:
				_attack_at(s, target, clock, out, _GobCfg.ASSAULT_STANDOFF)
	return out

# ═════════════════════════════════════════════════════════════════════════════
# ОТХОД И ЛЕЧЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
## Отходить: запас армии ниже порога; в затяжном замесе — проигрываем (за
## время штурма потеряли больше HR_LOSING_DROP доли)
func _should_retreat(field: Array, clock: float) -> bool:
	if hp_frac <= _GobCfg.ASSAULT_RETREAT_HP:
		return true
	if state == ST_CHARGE and clock - _state_since >= _GobCfg.HR_BRAWL_SEC \
			and _charge_hp0 - hp_frac >= _GobCfg.HR_LOSING_DROP:
		return true
	return false

func _plan_retreat(field: Array, clock: float) -> Array:
	var out: Array = []
	var n: int = field.size()
	# Все — в лагерь, каждый отряд на своё место у костров
	for i in range(n):
		var sq: Dictionary = field[i]
		var off: float = (float(i) - float(n - 1) * 0.5) * _GobCfg.ASSAULT_LINE_STEP * 0.6
		var goal: Vector3 = camp_pt + right * off
		if not _retreat_issued.has(_sid(sq)):
			_retreat_issued[_sid(sq)] = true
			_ordered.erase(_sid(sq))
		_withdraw(sq, goal, clock, out)
	# Лечение у костров: только те, кто дошёл до лагеря и не дерётся
	_heal_at_camp(field)
	# Восстановились — новая волна с другим паттерном, тем же тактом:
	# армия не стоит лишние две секунды в лагере с уже снятым отходом
	if hp_frac >= _GobCfg.ASSAULT_REARM_HP and _at_camp(field):
		waves += 1
		_end_retreat_all(field)
		if mode == MODE_ADVANCE:
			_enter(ST_ADVANCE, clock)
			contact_pt = Vector3.INF
			last_action = "силы восстановлены (%.0f %%) — марш продолжается" % (hp_frac * 100.0)
			return _plan_march(field, _army_center(field), clock)
		state = ST_IDLE
		_start_assault(clock)
		last_action = "силы восстановлены (%.0f %%) — новая волна, %s" % [hp_frac * 100.0, last_action]
		return _plan_assemble(field, clock)
	return out

## Лечение — раз в такт вожака на THINK_INTERVAL секунд вперёд: покадрового
## пути здесь нет, а лечащихся бойцов — сотни, не тысячи
func _heal_at_camp(field: Array) -> void:
	var amount: float = _GobCfg.CAMP_HEAL_PER_SEC * _GobCfg.THINK_INTERVAL
	var r2: float = _GobCfg.CAMP_HEAL_RADIUS * _GobCfg.CAMP_HEAL_RADIUS
	for s in field:
		var sq: Dictionary = s
		if GameManager.squad_in_combat(_sid(sq)):
			continue
		for m in (sq["members"] as Array):
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u == null or u.is_dead() or u.current_health >= u.max_health:
				continue
			var p: Vector3 = u.global_position
			if Vector2(p.x - camp_pt.x, p.z - camp_pt.z).length_squared() > r2:
				continue
			u.current_health = minf(u.max_health, u.current_health + amount)
			u.push_hp()
			u._soa_push_stats()

func _at_camp(field: Array) -> bool:
	var ok := 0
	var n := 0
	for s in field:
		var c: Vector3 = _squad_center(s)
		if c == Vector3.INF:
			continue
		n += 1
		if Vector2(c.x - camp_pt.x, c.z - camp_pt.z).length() <= _GobCfg.CAMP_HEAL_RADIUS:
			ok += 1
	return n > 0 and float(ok) >= float(n) * _GobCfg.ASSAULT_ASSEMBLE_FRAC

## Снять режим отхода со всех: новая волна начинается с чистого листа
func _end_retreat_all(field: Array) -> void:
	for s in field:
		for m in (s["members"] as Array):
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u != null and not u.is_dead() and u.retreating:
				u.end_retreat(true)

# ═════════════════════════════════════════════════════════════════════════════
# РЕЖИМ «МАРШ»: ВОЛНА В ЦЕНТР С ДОЗОРОМ (уточнение владельца, 10.09.2026)
# ═════════════════════════════════════════════════════════════════════════════
## Тело идёт к точке линией поперёк оси, конный дозор — впереди тела на
## VANGUARD_LEAD (цель дозора едет вместе с телом). Дозор заметил чужих в
## VANGUARD_SIGHT — отходит к телу, а армия переходит в общий штурм точки
## контакта; бой кончился — снова марш. Потери и лечение — как у штурма.
func plan_advance(field: Array, p_aim: Vector3, p_village: Vector3, clock: float) -> Array:
	_set_mode(MODE_ADVANCE)
	village = p_village
	aim = p_aim
	last_action = ""
	var out: Array = []
	if field.is_empty():
		state = ST_IDLE
		return out
	var army_c: Vector3 = _army_center(field)
	# Ось марша живая: тело движется, и «вперёд» — это к точке от тела
	var to := Vector3(aim.x - army_c.x, 0.0, aim.z - army_c.z)
	if to.length() > 1.0 and state != ST_CHARGE:
		axis = to.normalized()
		right = Vector3(-axis.z, 0.0, axis.x)
	front_pt = aim
	var to_village: float = Vector2(aim.x - village.x, aim.z - village.z).length()
	camp_pt = village if to_village <= _GobCfg.ASSAULT_CAMP_FAR else army_c - axis * _GobCfg.ASSAULT_CAMP_DIST
	hp_frac = _army_hp_frac(field)
	if state != ST_RETREAT and _should_retreat(field, clock):
		_enter(ST_RETREAT, clock)
		last_action = "потери на марше: запас %.0f %% — отход в лагерь" % (hp_frac * 100.0)
	match state:
		ST_RETREAT:
			return _plan_retreat(field, clock)
		ST_CHARGE:
			# Контакт исчерпан — никто не дерётся и чужих у армии нет
			var quiet := true
			for s in field:
				if GameManager.squad_in_combat(_sid(s)):
					quiet = false
			if quiet and _nearest_foe(army_c, _GobCfg.VANGUARD_SIGHT) == null:
				_enter(ST_ADVANCE, clock)
				contact_pt = Vector3.INF
				last_action = "контакт исчерпан — марш продолжается"
				return _plan_march(field, army_c, clock)
			return _plan_charge(field, clock)
		_:
			if state != ST_ADVANCE:
				_enter(ST_ADVANCE, clock)
				last_action = "марш: тело линией, дозор впереди"
			return _plan_march(field, army_c, clock)

func _plan_march(field: Array, army_c: Vector3, clock: float) -> Array:
	var out: Array = []
	if vanguard_sid == 0 or _find(field, vanguard_sid).is_empty():
		vanguard_sid = _pick_probe(field, true)
		if vanguard_sid == 0:
			vanguard_sid = _pick_smallest(field)
	# Тело: остальные отряды, их центр и линия к точке
	var body: Array = []
	for s in field:
		if _sid(s) != vanguard_sid:
			body.append(s)
	var body_c: Vector3 = _army_center(body) if not body.is_empty() else army_c
	var dist_left: float = Vector2(aim.x - body_c.x, aim.z - body_c.z).length()
	# Дозор: впереди тела, но не дальше точки
	var lead: float = minf(_GobCfg.VANGUARD_LEAD, dist_left)
	var vg: Vector3 = body_c + axis * lead
	var van: Dictionary = _find(field, vanguard_sid)
	if not van.is_empty():
		var vc: Vector3 = _squad_center(van)
		var foe: Node3D = _nearest_foe(vc if vc != Vector3.INF else vg, _GobCfg.VANGUARD_SIGHT)
		if foe != null:
			# КОНТАКТ: дозор к телу, армия — в штурм точки контакта
			contact_pt = foe.global_position
			front_pt = contact_pt
			weak_side = 0
			_enter(ST_CHARGE, clock)
			_hr_phase = "all"
			_charge_hp0 = hp_frac
			last_action = "дозор нашёл чужих в %.0f м — штурм" % Vector2(contact_pt.x - body_c.x, contact_pt.z - body_c.z).length()
			return _plan_charge(field, clock)
		_move(van, vg, clock, out, _GobCfg.VANGUARD_REISSUE_DIST)
	var n: int = body.size()
	for i in range(n):
		var off: float = (float(i) - float(n - 1) * 0.5) * _GobCfg.ASSAULT_LINE_STEP
		_move(body[i], aim + right * off, clock, out)
	return out

func _pick_smallest(field: Array) -> int:
	var best := 0
	var bn := 1 << 30
	for s in field:
		var n: int = ((s as Dictionary)["members"] as Array).size()
		if n < bn:
			bn = n
			best = _sid(s)
	return best

# ═════════════════════════════════════════════════════════════════════════════
# РЕЖИМ «ОБОРОНА»: ДЕРЕВНЯ ПОД УДАРОМ (уточнение владельца, 10.09.2026)
# ═════════════════════════════════════════════════════════════════════════════
## Угроза — чужие в DEFEND_RADIUS + DEFEND_ALERT_PAD от деревни, её центр —
## средняя их точка. Пехота держит РУБЕЖ у костров (DEFEND_LINE_DIST от
## центра в сторону угрозы) и бьёт только то, что подошло на DEFEND_ENGAGE;
## конница заходит с фланга угрозы, колет и отходит к деревне, сторона
## чередуется. Отряд ниже ASSAULT_RETREAT_HP — к кострам, лечится и
## возвращается на рубеж. Угрозы нет — все у костров, раненые лечатся.
func plan_defense(field: Array, p_village: Vector3, clock: float) -> Array:
	_set_mode(MODE_DEFENSE)
	village = p_village
	aim = village
	camp_pt = village
	last_action = ""
	var out: Array = []
	if field.is_empty():
		state = ST_IDLE
		return out
	if state != ST_DEFEND:
		_enter(ST_DEFEND, clock)
		_def_cav_phase = "strike"
		_def_cav_since = clock
	hp_frac = _army_hp_frac(field)
	threat_pt = _threat_center()
	var n: int = field.size()
	# ── Угрозы нет: все у костров, раненые лечатся ───────────────────────────
	if threat_pt == Vector3.INF:
		for i in range(n):
			var sq0: Dictionary = field[i]
			var ho: float = (float(i) - float(n - 1) * 0.5) * _GobCfg.ASSAULT_LINE_STEP * 0.6
			_move(sq0, village + Vector3(ho, 0.0, 0.0), clock, out)
			if wounded.has(_sid(sq0)) and _squad_hp_frac(sq0) >= _GobCfg.ASSAULT_REARM_HP:
				wounded.erase(_sid(sq0))
		_heal_at_camp(field)
		return out
	var dir := Vector3(threat_pt.x - village.x, 0.0, threat_pt.z - village.z)
	axis = dir.normalized() if dir.length() > 0.5 else axis
	right = Vector3(-axis.z, 0.0, axis.x)
	front_pt = threat_pt
	# ── Конница: удар с фланга и отход ──────────────────────────────────────
	var el: float = clock - _def_cav_since
	if _def_cav_phase == "strike" and el >= _GobCfg.DEFEND_CAV_STRIKE_SEC:
		_def_cav_phase = "back"
		_def_cav_since = clock
		last_action = "конница отходит к деревне"
	elif _def_cav_phase == "back" and el >= _GobCfg.DEFEND_CAV_BACK_SEC:
		_def_cav_phase = "strike"
		_def_cav_since = clock
		_def_side = -_def_side
		last_action = "конница заходит с фланга %d" % _def_side
	var line_c: Vector3 = village + axis * _GobCfg.DEFEND_LINE_DIST
	var inf_idx := 0
	var inf_n := 0
	for s in field:
		if not _is_cavalry(s):
			inf_n += 1
	for s in field:
		var sq: Dictionary = s
		var sid: int = _sid(sq)
		# Раненые — к кострам, до восстановления
		var frac: float = _squad_hp_frac(sq)
		if wounded.has(sid):
			if frac >= _GobCfg.ASSAULT_REARM_HP:
				wounded.erase(sid)
			else:
				_withdraw(sq, village, clock, out)
				continue
		elif frac <= _GobCfg.ASSAULT_RETREAT_HP:
			wounded[sid] = true
			_ordered.erase(sid)
			_withdraw(sq, village, clock, out)
			last_action += "|отряд %d к кострам" % sid
			continue
		if _is_cavalry(sq):
			if _def_cav_phase == "strike":
				var fp: Vector3 = threat_pt + right * (float(_def_side) * _GobCfg.DEFEND_CAV_FLANK)
				_attack_at(sq, fp, clock, out, _GobCfg.DEFEND_CAV_FLANK)
			else:
				_withdraw(sq, village - axis * 4.0, clock, out)
			continue
		# Пехота: место на рубеже; бьёт только то, что подошло к рубежу
		var off: float = (float(inf_idx) - float(inf_n - 1) * 0.5) * _GobCfg.ASSAULT_LINE_STEP * 0.7
		inf_idx += 1
		var slot: Vector3 = line_c + right * off
		if _nearest_foe(slot, _GobCfg.DEFEND_ENGAGE) != null:
			_attack_at(sq, slot, clock, out, _GobCfg.DEFEND_ENGAGE)
		else:
			_move(sq, slot, clock, out)
	_heal_at_camp(field)
	return out

## Центр угрозы у деревни: средняя точка чужих в радиусе тревоги, INF — пусто
func _threat_center() -> Vector3:
	var r: float = _GobCfg.DEFEND_RADIUS + _GobCfg.DEFEND_ALERT_PAD
	var acc := Vector3.ZERO
	var n := 0
	for u in GameManager.army.query_radius(village.x, village.z, r):
		if u == null or not is_instance_valid(u):
			continue
		var un := u as Unit
		if un == null or un.is_dead() or int(un.faction) == Constants.FACTION_GOBLIN:
			continue
		acc += un.global_position
		n += 1
	if n == 0:
		return Vector3.INF
	return acc / float(n)

func _squad_hp_frac(sq: Dictionary) -> float:
	var cur := 0.0
	var mx := 0.0
	for m in (sq["members"] as Array):
		if not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		cur += u.current_health
		mx += u.max_health
	return (cur / mx) if mx > 0.0 else 1.0
