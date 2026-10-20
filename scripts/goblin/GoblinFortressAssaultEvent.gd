extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ВОЛНЫ ОРДЫ ПО ЧАСАМ: РЕЙДЫ И ШТУРМ БАЗЫ ИГРОКА (ТЗ 13.10.2026 → 14.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Один движок на все волны по расписанию (RaidManager.schedule): регулярные
## РЕЙДЫ (10:00 три конницы, 12:00 ещё три, 15:00 — 3/3/3) и ШТУРМ (30:00 /
## 45:00 / 60:00, состав 8 → 14 → 20, СДВОЕННЫЙ: половина в срок, вторая
## половина через PAIR_GAP вслед). Срабатывает ТОЛЬКО пока главная хата жива —
## снесена к сроку, срок отменяется (cancelled).
##
## ЖИЗНЬ ВОЛНЫ (каждая волна живёт СВОИМ учётом, волн в поле может быть
## несколько — первая половина пары марширует, когда вторая выходит):
##   stage  — отряды рождаются ПО ОДНОМУ (шаг SPAWN_STEP) каждый на СВОЁ место
##            сетки площадки сбора у хаты и стоят; внутри отряда бойцы идут
##            очередью Main.spawn_goblin_squad(staggered). Гуськом никто не
##            уходит: марш начинается, когда вышла вся волна и прошла пауза
##            STAGE_SETTLE.
##   march  — КУЛАК: у каждого отряда своё место в блоке вокруг текущей путевой
##            точки (сетка поперёк хода, шаг BLOCK_STEP), следующая точка —
##            когда дошла доля WP_GATE отрядов (или WP_WAIT_MAX). Маршрут (один
##            на партию, строится лениво): дальний берег брода → ближний →
##            обход центрального пня со стороны базы → перед нижним проходом →
##            за проходом.
##   fight  — чужие люди ближе AM_R к отряду; ГРУППОВОЕ АГРО: угроза любого
##            отряда поднимает все отряды волны в ASSIST_R — раскладка фронта
##            (GameManager.front_pairs), нет пары — подход к угрозе; рабочий
##            бьётся отрядом напрямую. Тихо CALM_SEC — перегруппировка и марш.
##   siege  — маршрут пройден. ШТУРМ: крепости игрока (is_stronghold),
##            ближайшая к проходу первой; снесена — следующая; нет крепостей —
##            любая постройка по goblin_may_raze. РЕЙД: приоритет
##            RaidManager.raid_target — рабочие → башни → бараки → дома и
##            прочее → крепости последними.
##
## ЦЕНА: такт 0.5 с; на отряд один запрос ядра (ближайший чужой), приказы —
## ОЧЕРЕДЬЮ ВОЖАКА ОРДЫ (GoblinAI._order_*, бюджет бойцов на кадр): своего
## канала приказов нет, иначе два раздатчика в одном кадре сложили бы пики.
## Списки целей рейда кэшируются на такт (RaidManager.refresh). Дорога отряда
## — одна на отряд от центра (GameManager.squad_leg, кэш A*). Командир
## конницы отряды эвента не берёт (GoblinAI.is_special_squad спрашивает
## owns()). Не сохраняется: после загрузки часы эвента идут заново.

const _Spawn := preload("res://scripts/spawn_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Raid := preload("res://scripts/goblin/RaidManager.gd")

const THINK_SEC := 0.5
const CENTRE_NONE := Vector3(INF, 0.0, INF)

var main: Node3D = null
var clock: float = 0.0
var _t: float = 0.0
var _tick: int = 0
var _next_i: int = 0
## Расписание партии (RaidManager.schedule); стенды вправе подменить
var _sched: Array = []
## Сдвоенные волны крупных сроков — выключатель для стендов кулака
var pair_enabled: bool = _Spawn.ASSAULT_EVENT_PAIR

## Волны: id → {"id", "kind", "label", "stage": "stage"/"march", "wp", "wp_t",
## "threat", "calm", "n", "k", "t0", "slots", "slowest", "spawned_t", "retry"}
var _waves: Dictionary = {}
var _wave_id: int = 0
## Очередь выхода: [{"uid", "wave"}]
var _spawn_q: Array = []
var _spawn_t: float = 0.0
var _route: Array = []
var _stage: Array = []         # места площадки последней волны (стенды)
## sid → {"i", "mode": "stage"/"march"/"fight"/"siege", "goal", "c", "t", "n", "tgt", "tgt_sh", "wave"}
var _sq: Dictionary = {}

# ── счётчики (стенды qa_goblin_base_assault / qa_tz1014, телеметрия) ─────────
var fired: Array = []          # [{"at", "wave", "sched", "kind", "label"}]
var cancelled: Array = []      # секунды отменённых сроков
var spawned: Array = []        # [{"t", "sid", "type", "wave"}]
var launched: Array = []       # [{"t", "wave", "squads"}]
var wp_reached: Dictionary = {}    # индекс точки → число отрядов
var strongholds_razed: int = 0
var buildings_razed: int = 0
var raid_kills: int = 0        # цели рейда (рабочие/постройки), снятые по приоритету
var raid_targets: Array = []   # [{"t", "wave", "rank", "sid"}] — какие цели брал рейд
var stuck_reissues: int = 0
var spawn_refusals: int = 0
var engages: int = 0
var assists: int = 0
var regroups: int = 0
var last_action: String = ""

## Регулярные рейды в расписании — выключатель для стендов штурма
var raids_enabled: bool = _Spawn.RAID_ENABLED

func setup(main_node: Node3D) -> void:
	main = main_node
	_rebuild_schedule()

## Подменить расписание (стенды); сбрасывает указатель на первый срок ≥ clock
func set_schedule(s: Array) -> void:
	_sched = s.duplicate()
	_sched.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	_next_i = 0
	while _next_i < _sched.size() and float(_sched[_next_i]["t"]) < clock:
		_next_i += 1

func _rebuild_schedule() -> void:
	var s: Array = []
	for e in _Raid.schedule(pair_enabled):
		if String(e["kind"]) == _Raid.KIND_RAID and not raids_enabled:
			continue
		s.append(e)
	set_schedule(s)

func set_pair(on: bool) -> void:
	pair_enabled = on
	_rebuild_schedule()

func set_raids(on: bool) -> void:
	raids_enabled = on
	_rebuild_schedule()

func schedule() -> Array:
	return _sched

func owns(sid: int) -> bool:
	return _sq.has(sid)

func route() -> Array:
	return _route

func stage_slots() -> Array:
	return _stage

func squad_ids() -> Array:
	return _sq.keys()

func wave_ids() -> Array:
	return _waves.keys()

## Последняя (самая новая) волна — для стендов, которые смотрят одну
func _last_wave() -> Dictionary:
	if _waves.is_empty():
		return {}
	return _waves[int(_waves.keys().max())]

func wave_stage(wave: int = -1) -> String:
	var w: Dictionary = _waves.get(wave, {}) if wave >= 0 else _last_wave()
	return String(w.get("stage", ""))

func wave_wp(wave: int = -1) -> int:
	var w: Dictionary = _waves.get(wave, {}) if wave >= 0 else _last_wave()
	return int(w.get("wp", -1))

func wave_kind(wave: int = -1) -> String:
	var w: Dictionary = _waves.get(wave, {}) if wave >= 0 else _last_wave()
	return String(w.get("kind", ""))

func squad_mode(sid: int) -> String:
	var s: Variant = _sq.get(sid)
	return String((s as Dictionary)["mode"]) if s != null else ""

func squad_wave(sid: int) -> int:
	var s: Variant = _sq.get(sid)
	return int((s as Dictionary)["wave"]) if s != null else -1

func squad_target(sid: int) -> Node3D:
	var s: Variant = _sq.get(sid)
	if s == null:
		return null
	var t = (s as Dictionary).get("tgt")
	return t if t != null and is_instance_valid(t) else null

func set_clock(sec: float) -> void:
	clock = sec

func _ai() -> Node:
	return main.get("goblin_ai") if main != null else null

# ═════════════════════════════════════════════════════════════════════════════
# ТАКТ
# ═════════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	if main == null or not (_Spawn.ASSAULT_EVENT_ENABLED or _Spawn.RAID_ENABLED):
		return
	clock += delta
	if not _spawn_q.is_empty():
		_spawn_tick(delta)
	_t += delta
	if _t < THINK_SEC:
		return
	_t = 0.0
	_tick += 1
	while _next_i < _sched.size() and clock >= float(_sched[_next_i]["t"]):
		_trigger(_sched[_next_i])
		_next_i += 1
	if not _sq.is_empty() or not _waves.is_empty():
		_think()

## Запустить волну по записи расписания {"t", "kind", "comp", "label"}.
## Публичный: стенды и будущие эвенты зовут напрямую. Возвращает id волны,
## 0 — хаты нет (срок отменён)
func launch_wave(e: Dictionary) -> int:
	return _trigger(e)

func _trigger(e: Dictionary) -> int:
	var at: float = float(e.get("t", clock))
	var ai: Node = _ai()
	if ai == null or not is_instance_valid(ai) or not bool(ai.call("chief_alive")):
		cancelled.append(at)
		last_action = "%s отменён — главной хаты нет" % String(e.get("label", "срок"))
		return 0
	_wave_id += 1
	var kind: String = String(e.get("kind", _Raid.KIND_ASSAULT))
	fired.append({"at": clock, "wave": _wave_id, "sched": at, "kind": kind, "label": String(e.get("label", ""))})
	var order: Array = _Raid.spawn_order(e.get("comp", {}))
	for uid in order:
		_spawn_q.append({"uid": String(uid), "wave": _wave_id})
	if _route.is_empty():
		_build_route(ai)
	_build_stage(ai, order.size())
	_waves[_wave_id] = {"id": _wave_id, "kind": kind, "label": String(e.get("label", "")),
		"stage": "stage", "wp": 0, "wp_t": clock, "threat": CENTRE_NONE, "calm": 0.0,
		"n": order.size(), "k": 0, "t0": clock, "slots": _stage.duplicate(), "retry": 0}
	if _spawn_q.size() == order.size():
		_spawn_t = 0.0
		_spawn_tick(0.0)
	last_action = "%s: волна %d (%d отрядов) выходит на площадку" % [String(e.get("label", "")), _wave_id, order.size()]
	if AudioManager.has_method("play_horn"):
		AudioManager.play_horn()
	return _wave_id

# ═════════════════════════════════════════════════════════════════════════════
# СПАВН ПО ОДНОМУ ОТРЯДУ НА ПЛОЩАДКУ СБОРА
# ═════════════════════════════════════════════════════════════════════════════
func _spawn_tick(delta: float) -> void:
	_spawn_t -= delta
	if _spawn_t > 0.0:
		return
	_spawn_t += _Spawn.ASSAULT_EVENT_SPAWN_STEP
	var ai: Node = _ai()
	if ai == null or not is_instance_valid(ai) or not bool(ai.call("chief_alive")):
		# Хату снесли посреди выхода — остаток волн не рождается
		for q in _spawn_q:
			var wq: Variant = _waves.get(int((q as Dictionary)["wave"]))
			if wq != null:
				(wq as Dictionary)["spawned_t"] = clock
		_spawn_q.clear()
		return
	var item: Dictionary = _spawn_q.pop_front()
	var uid: String = String(item["uid"])
	var wid: int = int(item["wave"])
	var w: Variant = _waves.get(wid)
	if w == null:
		return
	var wd: Dictionary = w
	var k: int = int(wd["k"])
	var slots: Array = wd["slots"]
	var slot: Vector3 = slots[k % slots.size()]
	var n: int = int(_GobCfg.SQUAD_SIZE.get(uid, 50))
	var sid: int = int(main.call("spawn_goblin_squad", uid, n, slot, true, _Spawn.ASSAULT_EVENT_CAP_EXTRA))
	if sid <= 0:
		# Потолок орды: тот же род — на следующем шаге; RETRY_MAX отказов —
		# волна идёт тем, что вышло
		spawn_refusals += 1
		wd["retry"] = int(wd["retry"]) + 1
		if int(wd["retry"]) <= _Spawn.ASSAULT_EVENT_SPAWN_RETRY_MAX:
			_spawn_q.push_front(item)
		else:
			for i in range(_spawn_q.size() - 1, -1, -1):
				if int((_spawn_q[i] as Dictionary)["wave"]) == wid:
					_spawn_q.remove_at(i)
		if not _queued(wid):
			wd["spawned_t"] = clock
		return
	wd["k"] = k + 1
	_sq[sid] = {"i": k, "mode": "stage", "goal": CENTRE_NONE, "c": CENTRE_NONE, "t": clock, "n": 0,
		"tgt": null, "tgt_sh": false, "wave": wid}
	spawned.append({"t": clock, "sid": sid, "type": uid, "wave": wid})
	# Разметка толпы на месте — отряд стоит, пока не выйдет вся волна
	ai.call("_set_horde_formation", sid, slot, n, Vector3(-1.0, 0.0, 0.0))
	if not _queued(wid):
		wd["spawned_t"] = clock

func _queued(wid: int) -> bool:
	for q in _spawn_q:
		if int((q as Dictionary)["wave"]) == wid:
			return true
	return false

func _wave_count(wave: int) -> int:
	var n := 0
	for s in _sq.values():
		if int((s as Dictionary)["wave"]) == wave:
			n += 1
	return n

## Площадка сбора: сетка мест от хаты в сторону первой точки маршрута
func _build_stage(ai: Node, n: int) -> void:
	_stage.clear()
	var chief = ai.get("chief")
	var hp: Vector3 = (chief as Node3D).global_position if chief != null and is_instance_valid(chief) else ai.get("village")
	hp.y = 0.0
	var first: Vector3 = _route[0] if not _route.is_empty() else hp + Vector3(-1.0, 0.0, 0.0)
	var dir: Vector3 = first - hp
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(-1.0, 0.0, 0.0)
	var c: Vector3 = hp + dir * _Spawn.ASSAULT_EVENT_STAGE_DIST
	var slots: Array = _block_slots(c, dir, maxi(n, 1), _Spawn.ASSAULT_EVENT_STAGE_STEP)
	for p in slots:
		var q: Vector3 = GameManager.land_target(p)
		if main.has_method("_clear_trees"):
			main.call("_clear_trees", q, 9.0)
		_stage.append(q)

## Места блока вокруг центра: cols = ceil(√n) поперёк хода, ряды назад
func _block_slots(c: Vector3, dir: Vector3, n: int, step: float, cols_max: int = 99) -> Array:
	var out: Array = []
	var side := Vector3(-dir.z, 0.0, dir.x)
	var cols: int = clampi(int(ceil(sqrt(float(n)))), 1, maxi(cols_max, 1))
	var rows: int = int(ceil(float(n) / float(cols)))
	for k in range(n):
		var col: int = k % cols
		var row: int = k / cols
		var in_row: int = mini(cols, n - row * cols)
		var off: float = (float(col) - float(in_row - 1) * 0.5) * step
		var back: float = (float(row) - float(rows - 1) * 0.5) * step
		out.append(c + side * off - dir * back)
	return out

# ═════════════════════════════════════════════════════════════════════════════
# МАРШРУТ: БРОД → ОБХОД ПНЯ → НИЖНИЙ ПРОХОД → ЗА ПРОХОД (один на партию)
# ═════════════════════════════════════════════════════════════════════════════
func _build_route(ai: Node) -> void:
	_route.clear()
	var fz: float = float(main.get("FORD_Z"))
	var rx: float = float(main.call("river_x", fz))
	var base: Vector3 = main.get("PLAYER_BASE_ANCHOR")
	var home_side: int = int(main.call("river_side", base))
	var ford_far := Vector3(rx - float(home_side) * 24.0, 0.0, fz)
	var ford_near := Vector3(rx + float(home_side) * 24.0, 0.0, fz)
	_route.append(GameManager.land_target(ford_far))
	_route.append(GameManager.land_target(ford_near))
	var gx: float = base.x + float(main.get("WALL_GAP_DOWN_AT"))
	var wz: float = float(main.call("_wall_bottom_z", gx))
	var outside: float = signf(wz - base.z)
	var gate_out := Vector3(gx, 0.0, wz + outside * _Spawn.ASSAULT_EVENT_GATE_OUT)
	var gate_in := Vector3(gx, 0.0, wz - outside * _Spawn.ASSAULT_EVENT_GATE_IN)
	var lair: Vector3 = _central_lair(home_side)
	if lair.x != INF:
		var a: Vector3 = ford_near - lair
		a.y = 0.0
		var b: Vector3 = gate_out - lair
		b.y = 0.0
		var bis: Vector3 = a.normalized() + b.normalized()
		if bis.length() < 0.1:
			bis = Vector3(-a.z, 0.0, a.x)
		_route.append(GameManager.land_target(lair + bis.normalized() * _Spawn.ASSAULT_EVENT_LAIR_BYPASS_R))
	_route.append(GameManager.land_target(gate_out))
	_route.append(GameManager.land_target(gate_in))
	_gate_from = _route.size() - 2
	# Старт уплотнения — площадка сбора (строится до маршрута на первой волне)
	var chief = ai.get("chief")
	var hp: Vector3 = (chief as Node3D).global_position if chief != null and is_instance_valid(chief) else ai.get("village")
	hp.y = 0.0
	var dir: Vector3 = _route[0] - hp
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(-1.0, 0.0, 0.0)
	_densify(hp + dir * _Spawn.ASSAULT_EVENT_STAGE_DIST)

## Индекс первой точки у прохода базы (с неё блок сужается)
var _gate_from: int = 999

## Длинные ноги режутся на отрезки ≤ LEG_MAX: ворота каждой точки держат
## быстрых до подхода медленных, и поперечник кулака ограничен ногой
func _densify(start: Vector3) -> void:
	var out: Array = []
	var prev: Vector3 = start
	var gate_new := 999
	for i in range(_route.size()):
		var p: Vector3 = _route[i]
		var d: float = Vector2(p.x - prev.x, p.z - prev.z).length()
		var k: int = maxi(int(ceil(d / _Spawn.ASSAULT_EVENT_LEG_MAX)), 1)
		for j in range(1, k):
			out.append(GameManager.land_target(prev.lerp(p, float(j) / float(k))))
		if i == _gate_from:
			gate_new = out.size()
		out.append(p)
		prev = p
	_route = out
	_gate_from = gate_new

func _central_lair(home_side: int) -> Vector3:
	var a: Vector3 = main.get("PLAYER_BASE_ANCHOR")
	var e: Vector3 = main.get("ENEMY_BASE_ANCHOR")
	var mid: Vector3 = (a + e) * 0.5
	var best := CENTRE_NONE
	var bd := INF
	for l in GameManager.troll_lairs:
		if l == null or not is_instance_valid(l):
			continue
		var p: Vector3 = (l as Node3D).global_position
		p.y = 0.0
		if int(main.call("river_side", p)) != home_side:
			continue
		var d: float = p.distance_to(mid)
		if d < bd:
			bd = d
			best = p
	return best

# ═════════════════════════════════════════════════════════════════════════════
# ТАКТ ВОЛН
# ═════════════════════════════════════════════════════════════════════════════
func _think() -> void:
	var ai: Node = _ai()
	if ai == null or not is_instance_valid(ai):
		return
	for sid in _sq.keys():
		if int(ai.call("_alive_n", int(sid))) == 0:
			_sq.erase(sid)
	# Центры — один запрос на отряд на такт, общие для всех волн
	var centres: Dictionary = {}
	for sid2 in _sq:
		var c: Vector3 = ai.call("_centre", int(sid2))
		if c.x != INF:
			centres[int(sid2)] = c
	var ids: Array = _waves.keys()
	ids.sort()
	for wid in ids:
		var w: Dictionary = _waves[wid]
		var alive_n: int = _wave_count(int(wid))
		if alive_n == 0 and not _queued(int(wid)):
			# Волна выбита или выродилась (потолок) — учёт снимается
			if String(w.get("stage", "")) == "stage":
				last_action = "волна %d не вышла (потолок/хата)" % int(wid)
			_waves.erase(wid)
			continue
		_think_wave(w, ai, centres)

func _think_wave(w: Dictionary, ai: Node, centres: Dictionary) -> void:
	var wave: int = int(w["id"])
	# ── СБОР: вышли все — пауза — марш кулаком ───────────────────────────────
	if String(w["stage"]) == "stage":
		if not _queued(wave) and w.has("spawned_t") \
				and clock - float(w["spawned_t"]) >= _Spawn.ASSAULT_EVENT_STAGE_SETTLE:
			_launch(w, ai)
		return
	var live: Array = []
	for sid in centres:
		if int((_sq[sid] as Dictionary)["wave"]) == wave:
			live.append(int(sid))
	# ── 1. УГРОЗА ВОЛНЫ: бой любого отряда поднимает всех в ASSIST_R ──────────
	var foes: Dictionary = {}
	var threat: Vector3 = CENTRE_NONE
	for sid3 in live:
		var foe: Node3D = ai.call("_nearest_foe", centres[sid3], _Spawn.ASSAULT_EVENT_AM_R)
		if foe != null:
			foes[sid3] = foe
			if threat.x == INF:
				threat = foe.global_position
	if threat.x != INF:
		w["threat"] = threat
		w["calm"] = 0.0
	else:
		w["calm"] = float(w["calm"]) + THINK_SEC
	var was_fighting: bool = (w["threat"] as Vector3).x != INF
	for sid4 in live:
		var s: Dictionary = _sq[sid4]
		var c4: Vector3 = centres[sid4]
		var own: Node3D = foes.get(sid4)
		if own != null:
			_engage(int(sid4), s, own, ai, false, w)
			continue
		if threat.x != INF \
				and Vector2(c4.x - threat.x, c4.z - threat.z).length() <= _Spawn.ASSAULT_EVENT_ASSIST_R:
			_engage(int(sid4), s, null, ai, true, w, threat)
			continue
		if String(s["mode"]) == "fight":
			# Для этого отряда чисто — ждёт общей перегруппировки
			continue
		_squad_duty(int(sid4), s, c4, ai, w)
	# ── 2. ТИХО — ПЕРЕГРУППИРОВКА: все на одну точку, марш дальше ───────────
	if was_fighting and threat.x == INF and float(w["calm"]) >= _Spawn.ASSAULT_EVENT_CALM_SEC:
		w["threat"] = CENTRE_NONE
		regroups += 1
		for sid5 in live:
			var s5: Dictionary = _sq[sid5]
			if String(s5["mode"]) == "fight":
				s5["mode"] = "siege" if int(w["wp"]) >= _route.size() else "march"
			s5["goal"] = CENTRE_NONE
			s5["tgt"] = null
			s5["n"] = 0
	# ── 3. ВОРОТА ТОЧКИ: дошла доля волны — следующая точка ──────────────────
	if int(w["wp"]) < _route.size() and threat.x == INF:
		var wp: Vector3 = _route[int(w["wp"])]
		var at_n := 0
		var n_live := 0
		for sid6 in live:
			if String((_sq[sid6] as Dictionary)["mode"]) != "march":
				continue
			n_live += 1
			var c6: Vector3 = centres[sid6]
			if Vector2(c6.x - wp.x, c6.z - wp.z).length() <= _Spawn.ASSAULT_EVENT_WP_R + _Spawn.ASSAULT_EVENT_BLOCK_STEP:
				at_n += 1
		if n_live > 0 and at_n > 0:
			var key: String = "at_" + str(int(w["wp"]))
			if not w.has(key):
				w[key] = clock
				wp_reached[int(w["wp"])] = at_n
			else:
				wp_reached[int(w["wp"])] = maxi(int(wp_reached.get(int(w["wp"]), 0)), at_n)
			var waited: float = clock - float(w[key])
			if float(at_n) >= ceilf(float(n_live) * _Spawn.ASSAULT_EVENT_WP_GATE) or waited >= _Spawn.ASSAULT_EVENT_WP_WAIT_MAX:
				w["wp"] = int(w["wp"]) + 1
				w["wp_t"] = clock
				for sid7 in live:
					var s7: Dictionary = _sq[sid7]
					s7["goal"] = CENTRE_NONE
					s7["n"] = 0
					if int(w["wp"]) >= _route.size() and String(s7["mode"]) == "march":
						s7["mode"] = "siege"

## Марш кулаком начинается: вся волна на первую точку, каждый на своё место
func _launch(w: Dictionary, ai: Node) -> void:
	w["stage"] = "march"
	w["wp"] = 0
	w["wp_t"] = clock
	var wave: int = int(w["id"])
	var n := 0
	# ТЕМП КУЛАКА — ПО САМОМУ МЕДЛЕННОМУ: конница (4.6 м/с) и пехота (2.2)
	# на марше идут шагом туши (1.54) с запасом PACE_SLACK, иначе кулак
	# растягивается на всю ногу, а ворота точки лишь собирают его заново
	var slowest := INF
	for sid in _sq:
		var s: Dictionary = _sq[sid]
		if int(s["wave"]) != wave:
			continue
		s["mode"] = "march"
		s["goal"] = CENTRE_NONE
		n += 1
		for m in (ai.call("_alive", int(sid)) as Array):
			slowest = minf(slowest, float((m as Unit).move_speed))
	w["slowest"] = slowest if slowest < INF else 0.0
	launched.append({"t": clock, "wave": wave, "squads": n})
	last_action = "волна %d (%s) собрана (%d отрядов) — марш на брод" % [wave, String(w.get("label", "")), n]

## Чем занят отряд без угрозы: марш на своё место у точки или штурм/рейд
func _squad_duty(sid: int, s: Dictionary, c: Vector3, ai: Node, w: Dictionary) -> void:
	var mode: String = s["mode"]
	if mode == "march":
		# Постройка игрока по ходу (башня, бараки) — снести
		var nb: Node3D = ai.call("_nearest_building_of", Constants.FACTION_PLAYER, c, _Spawn.ASSAULT_EVENT_AM_BLD_R)
		if nb != null and not (nb is Mine):
			_attack_node(sid, s, nb, ai, w)
			return
		if s.get("tgt") != null:
			if not _target_ok(s.get("tgt")):
				buildings_razed += 1
			s["tgt"] = null
			s["goal"] = CENTRE_NONE
		_march(sid, s, ai, w)
		_stuck_check(sid, s, c, ai)
		return
	if mode != "siege":
		return
	var tgt = s.get("tgt")
	if not _target_ok(tgt):
		if tgt != null:
			if tgt is Worker:
				raid_kills += 1
			elif bool(s.get("tgt_sh", false)):
				strongholds_razed += 1
			else:
				buildings_razed += 1
			s["tgt"] = null
		if String(w.get("kind", "")) == _Raid.KIND_RAID:
			tgt = _Raid.raid_target(get_tree(), _tick, c)
			if tgt != null:
				raid_targets.append({"t": clock, "wave": int(w["id"]), "rank": _Raid.target_rank(tgt), "sid": sid})
		else:
			tgt = _siege_target(c)
		if tgt == null:
			last_action = "%s: целей у игрока не осталось" % String(w.get("label", ""))
			return
		_attack_node(sid, s, tgt, ai, w)
	elif bool(ai.call("_squad_idle", sid)):
		_attack_node(sid, s, tgt, ai, w)

## Бой: раскладка фронта по угрозе; пары нет (угроза далеко) — подход.
## Рабочий игрока — цель отряда напрямую (у рабочих нет строя для пар)
func _engage(sid: int, s: Dictionary, foe: Node3D, ai: Node, assist: bool, w: Dictionary,
		threat: Vector3 = CENTRE_NONE) -> void:
	var at: Vector3 = foe.global_position if foe != null else threat
	var mode: String = s["mode"]
	var idle: bool = bool(ai.call("_squad_idle", sid))
	var goal: Vector3 = s["goal"]
	# Уже дерётся или уже идёт на эту угрозу — не дёргать (приказ один на этап)
	if mode == "fight" and not idle and goal.x != INF and Vector2(goal.x - at.x, goal.z - at.z).length() < 12.0:
		return
	if mode == "fight" and not idle and goal.x == INF:
		return
	_set_pace(sid, ai, false, w)
	if foe != null and foe is Worker:
		if s.get("tgt") != foe or idle:
			s["tgt"] = foe
			s["tgt_sh"] = false
			ai.call("_order_attack_node", sid, foe)
			engages += 1
		s["goal"] = CENTRE_NONE
		s["mode"] = "fight"
		return
	var pairs: Dictionary = GameManager.front_pairs([sid], at, _Spawn.ASSAULT_EVENT_AM_R + 12.0, Constants.FACTION_GOBLIN)
	if pairs.has(sid):
		ai.call("_order_attack_squad", sid, int(pairs[sid]))
		s["goal"] = CENTRE_NONE
		engages += 1
	elif assist:
		ai.call("_order_move", sid, GameManager.land_target(at), true)
		s["goal"] = at
		assists += 1
	else:
		return
	if mode != "fight":
		s["mode"] = "fight"
	s["tgt"] = null

func _target_ok(t) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if t is Building:
		return not (t as Building).is_dead() and int((t as Building).faction) == Constants.FACTION_PLAYER
	if t is Unit:
		return not (t as Unit).is_dead() and not (t as Unit).garrisoned \
			and int((t as Unit).faction) == Constants.FACTION_PLAYER
	return false

func _attack_node(sid: int, s: Dictionary, node: Node3D, ai: Node, w: Dictionary) -> void:
	if s.get("tgt") == node and not bool(ai.call("_squad_idle", sid)):
		return
	s["tgt"] = node
	s["tgt_sh"] = node.has_method("is_stronghold") and bool(node.call("is_stronghold"))
	_set_pace(sid, ai, false, w)
	ai.call("_order_attack_node", sid, node)

## Цель штурма: крепость игрока, ближайшая к нижнему проходу (первая), иначе
## ближайшая к отряду постройка, которую орде можно сносить (кроме рудников)
func _siege_target(from: Vector3) -> Node3D:
	var gate: Vector3 = _route[_route.size() - 1] if not _route.is_empty() else from
	var best: Node3D = null
	var bd := INF
	for b in get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_PLAYER)):
		if not _target_ok(b) or b is Mine:
			continue
		if not ((b as Building).has_method("is_stronghold") and bool((b as Building).call("is_stronghold"))):
			continue
		var d: float = gate.distance_to((b as Node3D).global_position)
		if d < bd:
			bd = d
			best = b
	if best != null:
		return best
	for b2 in get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_PLAYER)):
		if not _target_ok(b2) or b2 is Mine or not GameManager.goblin_may_raze(b2):
			continue
		var d2: float = from.distance_to((b2 as Node3D).global_position)
		if d2 < bd:
			bd = d2
			best = b2
	return best

## Приказ на СВОЁ место в блоке у текущей точки — один раз на точку
func _march(sid: int, s: Dictionary, ai: Node, w: Dictionary) -> void:
	var i: int = int(w["wp"])
	if i >= _route.size():
		s["mode"] = "siege"
		return
	if (s["goal"] as Vector3).x != INF:
		return
	var wp: Vector3 = _route[i]
	var slots0: Array = w["slots"]
	var prev: Vector3 = _route[i - 1] if i > 0 else (slots0[0] if not slots0.is_empty() else wp + Vector3(1.0, 0.0, 0.0))
	var dir: Vector3 = wp - prev
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(-1.0, 0.0, 0.0)
	var n: int = int(w["n"])
	var cols_max: int = _Spawn.ASSAULT_EVENT_GATE_COLS if i >= _gate_from else 99
	var slots: Array = _block_slots(wp, dir, n, _Spawn.ASSAULT_EVENT_BLOCK_STEP, cols_max)
	var goal: Vector3 = GameManager.land_target(slots[int(s["i"]) % slots.size()])
	s["goal"] = goal
	s["c"] = CENTRE_NONE
	s["t"] = clock
	ai.call("_order_move", sid, goal, false)
	_set_pace(sid, ai, true, w)

const PACE_SLACK := 1.15
## Темп марша кулаком (Unit.pace_mult, только MOVING): march — шаг самого
## медленного рода волны × PACE_SLACK, иначе — свой
func _set_pace(sid: int, ai: Node, march: bool, w: Dictionary) -> void:
	var slowest: float = float(w.get("slowest", 0.0))
	for m in (ai.call("_alive", sid) as Array):
		var u := m as Unit
		var want: float = 1.0
		if march and slowest > 0.0 and u.move_speed > 0.0:
			want = clampf(slowest * PACE_SLACK / u.move_speed, 0.3, 1.0)
		if u.pace_mult != want:
			u.pace_mult = want

func _stuck_check(sid: int, s: Dictionary, c: Vector3, ai: Node) -> void:
	var pc: Vector3 = s["c"]
	if pc.x == INF or Vector2(c.x - pc.x, c.z - pc.z).length() > _Spawn.ASSAULT_EVENT_STUCK_M:
		s["c"] = c
		s["t"] = clock
	elif clock - float(s["t"]) > _Spawn.ASSAULT_EVENT_STUCK_SEC and int(s["n"]) < _Spawn.ASSAULT_EVENT_STUCK_MAX:
		s["n"] = int(s["n"]) + 1
		s["t"] = clock
		stuck_reissues += 1
		var goal: Vector3 = s["goal"]
		if goal.x != INF:
			ai.call("_order_move", sid, goal, false)
