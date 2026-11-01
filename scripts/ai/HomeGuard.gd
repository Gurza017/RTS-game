extends Node
const _OptSys := preload("res://scripts/perf_config.gd")

## ═══════════════════════════════════════════════════════════════════════════
## ОХРАНА КРЕПОСТИ КРАСНОГО ИИ (заказ 15.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Стартовые отряды охраны (spawn_config.AI_HOME_GUARD_SQUADS: мечники 4-й
## лычки и копейщики 2-й) стоят колонной В ГЛУБИНЕ базы — за замком, по оси от
## центра карты — и СПЯТ тем же механизмом, что дремлющий резерв орды
## (Unit.set_dormant: физтик снят, бит F_DORMANT в ядре, картинка живёт).
## На дальние раздражители не реагируют по построению: у спящего нет тика,
## значит нет ни авто-агро, ни перехвата, ни патруля.
##
## ПРОСЫПАЮТСЯ ТОЛЬКО НА ШТУРМ: удар по замку (Building.last_hit_ms не старше
## HOME_GUARD_HIT_SEC), чужой БОЕВОЙ боец в HOME_GUARD_ZONE от замка (от
## HOME_GUARD_WAKE_FOES штук) или удар по самой охране. Отбились — через
## HOME_GUARD_CALM_SEC без угрозы возвращаются на посты, засыпают и лечатся там.
##
## ЭТО НЕ АРМИЯ ИИ: отряды помечены GameManager.squad_set_home_guard, и
## EnemyAI._regroup их не подбирает — иначе первый же такт раздал бы им посты
## заслона и увёл с места. Проверки — по таймеру HOME_GUARD_TICK_SEC, угроза
## ищется по сетке (query_radius / nearest_of_side), не обходом групп.
##
## Устройство списано с scripts/goblin/DormantReserve.gd намеренно: одна и та
## же задача («спящие отряды у дома, будит только штурм») решается одним и тем
## же способом у обеих сторон.

const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var castle: Castle = null
## Записи: {"sid": int, "post": Vector3, "unit": String, "vet": int,
##          "cols": int, "spacing": float}
var squads: Array = []
var alarm: bool = false
var wakes: int = 0
var _calm_t: float = 0.0
var _tick_t: float = 0.0
var _asleep: Dictionary = {}     # sid → true: отряд сейчас спит
## Оси раскладки: «фронт» — к центру карты, «вбок» — перпендикуляр
var _front: Vector3 = Vector3.FORWARD
var _side: Vector3 = Vector3.RIGHT

# ═════════════════════════════════════════════════════════════════════════════
# НАСТРОЙКА И УСЫНОВЛЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func setup(p_main, p_castle: Castle) -> void:
	main = p_main
	castle = p_castle
	if castle != null and is_instance_valid(castle):
		_front = castle.front_dir()
		_side = Vector3(-_front.z, 0.0, _front.x)
	set_process(false)

## Взять отряд под охрану: пост — его нынешний центр, сон — сразу.
## front/side — оси СВОЕЙ раскладки (ТЗ 25.09.2026: кольцо смотрит наружу,
## линии — по курсу обороны); пустые — общие оси замка
func adopt(sid: int, post: Vector3, cols: int, spacing: float,
		front: Vector3 = Vector3.ZERO, side: Vector3 = Vector3.ZERO, level: int = 0) -> void:
	if sid <= 0 or not GameManager.squads.has(sid):
		return
	for s in squads:
		if int(s["sid"]) == sid:
			return
	GameManager.squad_set_home_guard(sid, true)
	squads.append({
		"sid": sid, "post": post, "unit": GameManager.squad_type(sid),
		"vet": int(GameManager.squads[sid].get("level", 0)),
		"cols": maxi(cols, 1), "spacing": spacing,
		"front": front if front.length_squared() > 1e-6 else _front,
		"side": side if side.length_squared() > 1e-6 else _side,
		"level": level,          # уровень обороны (1 кольцо, 2 линии, 3 периметр; 0 — не задан)
	})
	_set_sleep(sid, true)
	set_process(true)

## После загрузки партии: отряды с признаком home_guard в реестре — снова под
## охрану, пост — где стоят. Замок ищется заново: узлы после загрузки другие
func adopt_loaded(p_main) -> void:
	main = p_main
	var keep: Castle = null
	for b in main.get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_ENEMY)):
		if not is_instance_valid(b):
			continue
		var c := b as Castle
		if c != null and c.is_stronghold() and not c.is_dead():
			keep = c
			break
	if keep == null:
		return
	setup(main, keep)
	for rec in GameManager.squads_of_faction(Constants.FACTION_ENEMY):
		var sid: int = int((rec as Dictionary).get("id", 0))
		if sid <= 0 or not GameManager.squad_is_home_guard(sid):
			continue
		var c: Vector3 = _centroid(sid)
		if c.x == INF:
			continue
		adopt(sid, c, main.START_SQUAD_COLS, main.START_SQUAD_SPACING)

# ═════════════════════════════════════════════════════════════════════════════
# СОН И ПРОБУЖДЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _members(sid: int) -> Array:
	# НАПРЯМУЮ, а не squad_members(): тот распускает опустевший отряд в геттере
	var rec: Variant = GameManager.squads.get(sid)
	if rec == null:
		return []
	var out: Array = []
	for m in (rec as Dictionary).get("members", []):
		if is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _set_sleep(sid: int, on: bool) -> void:
	for m in _members(sid):
		var u := m as Unit
		u.set_dormant(on)
		if not on:
			u.wake_for_lod()
	if on:
		_asleep[sid] = true
	else:
		_asleep.erase(sid)

func is_asleep(sid: int) -> bool:
	return _asleep.has(sid)

func asleep_count() -> int:
	return _asleep.size()

func _centroid(sid: int) -> Vector3:
	var ms: Array = _members(sid)
	if ms.is_empty():
		return Vector3.INF
	return GameManager._centroid_of(ms)

func _castle_pos() -> Vector3:
	if castle != null and is_instance_valid(castle):
		return castle.global_position
	return Vector3.INF

## Чужой боевой боец для красного ИИ: не своя сторона, не нейтрал, не рабочий
func _is_foe(u: Unit) -> bool:
	if u == null or u.is_dead() or u is Worker or u.garrisoned:
		return false
	var f: int = int(u.faction)
	return f != Constants.FACTION_ENEMY and f != Constants.FACTION_NEUTRAL

## Ближайший чужой боец к точке (по сетке ядра, все чужие стороны)
func _nearest_foe(p: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for f in Constants.other_factions(Constants.FACTION_ENEMY):
		var cand = GameManager.army.nearest_of_side(p.x, p.z, int(f), r)
		if cand == null or not is_instance_valid(cand):
			continue
		var u := cand as Unit
		if not _is_foe(u):
			continue
		var d: float = Vector2(u.global_position.x - p.x, u.global_position.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = u
	return best

## Чужих БОЕВЫХ в зоне охраны замка — по сетке соседей
func _foes_in_zone() -> int:
	var cp: Vector3 = _castle_pos()
	if cp.x == INF:
		return 0
	var n := 0
	for m in GameManager.unit_grid.query_radius(cp, _AICfg.HOME_GUARD_ZONE):
		if m == null or not is_instance_valid(m):
			continue
		if _is_foe(m as Unit):
			n += 1
	return n

## Замок под ударом: по нему били не позже HOME_GUARD_HIT_SEC назад
func castle_under_attack() -> bool:
	if castle == null or not is_instance_valid(castle) or castle.is_dead():
		return false
	return float(Unit.game_ms() - castle.last_hit_ms) * 0.001 < _AICfg.HOME_GUARD_HIT_SEC

## Штурм: удар по замку, прорыв в зону, бьют саму охрану ЛИБО чужой боевой
## подобрался к ЛЮБОМУ посту гарнизона (HOME_GUARD_POST_ZONE, ТЗ 25.09.2026:
## линии гарнизона стоят дальше зоны замка, и враг, вставший перед ними,
## иначе не будил никого)
## Почему тревога (стендам): castle / zone / hit:<sid> / post:<sid> / ""
var last_reason: String = ""
## Своя постройка базы, по которой били последней (тревога «bld»)
var _hit_bld: Building = null
const BASE_ALARM_R := 80.0

func _base_building_hit() -> Building:
	var cp: Vector3 = _castle_pos()
	if cp.x == INF:
		return null
	var now: int = Unit.game_ms()
	var win: int = int(_AICfg.HOME_GUARD_HIT_SEC * 1000.0)
	for b in GameManager.nodes_in_group_cached(Constants.building_group(Constants.FACTION_ENEMY)):
		if b == null or not is_instance_valid(b):
			continue
		var bl := b as Building
		if bl == null or bl == castle or bl.is_dead():
			continue
		if now - bl.last_hit_ms >= win:
			continue
		if _xz2(bl.global_position, cp) <= BASE_ALARM_R * BASE_ALARM_R:
			return bl
	return null

func _threatened() -> bool:
	if castle_under_attack():
		last_reason = "castle"
		return true
	if _foes_in_zone() >= _AICfg.HOME_GUARD_WAKE_FOES:
		last_reason = "zone"
		return true
	# «Бьют саму охрану» — УДАР, а не наличие цели (см. DormantReserve)
	for s in squads:
		if GameManager.squad_hit_recently(int(s["sid"])):
			last_reason = "hit:%d" % int(s["sid"])
			return true
	# ── БЬЮТ ПОСТРОЙКУ БАЗЫ (ТЗ 23.10.2026, п. 7) ─────────────────────────
	# Скриншоты 23.10: армия игрока сносит башню и бараки красных в 30-40 м от
	# крепости, а охрана спит в лесу рядом — тревогу поднимали только удар по
	# САМОЙ крепости, враг в её зоне и враг у поста. Теперь — и удар по любой
	# своей постройке в BASE_ALARM_R от крепости; цель — тот, кто её бьёт
	_hit_bld = _base_building_hit() if _OptSys.home_guard_buildings else null
	if _hit_bld != null:
		last_reason = "bld:%s" % _hit_bld.name
		return true
	var pz: float = _AICfg.HOME_GUARD_POST_ZONE
	if pz > 0.0:
		for s in squads:
			var f: Node3D = _nearest_foe(s["post"], pz)
			if f != null:
				last_reason = "post:%d foe %s" % [int(s["sid"]), f.name]
				return true
	last_reason = ""
	return false

## Шаг игровых часов (scripts/GameClockStep.gd, аудит 22.10.2026): часы и
## таймеры этого узла идут от Unit.game_ms(), а не от delta отрисовки —
## при просадке FPS мир замедляется, и сроки этого узла вместе с ним
var _gclk = preload("res://scripts/GameClockStep.gd").new()

func _process(delta: float) -> void:
	# Часы подсистемы (perf_config.sys_meter, qa_bigstand): одна проверка bool
	if not _OptSys.sys_meter:
		_process_timed(delta)
		return
	var _sys_t0: int = Time.get_ticks_usec()
	_process_timed(delta)
	_OptSys.sys_add("home_guard", Time.get_ticks_usec() - _sys_t0)

func _process_timed(delta: float) -> void:
	delta = _gclk.step()   # игровое время вместо delta отрисовки (GameClockStep)
	_tick_t += delta
	if _tick_t < _AICfg.HOME_GUARD_TICK_SEC:
		return
	var dt: float = _tick_t
	_tick_t = 0.0
	# Выбитые отряды — вон из реестра
	var kept: Array = []
	for s in squads:
		var sid: int = int(s["sid"])
		if GameManager.squads.has(sid) and not _members(sid).is_empty():
			kept.append(s)
		else:
			_asleep.erase(sid)
	squads = kept
	if squads.is_empty():
		set_process(false)
		return
	# Замка не стало — охрана больше не охрана: будим и отпускаем в армию
	if castle == null or not is_instance_valid(castle) or castle.is_dead():
		_disband_to_army()
		set_process(false)
		return
	var threat: bool = _threatened()
	if threat:
		_calm_t = 0.0
		if not alarm:
			alarm = true
			wakes += 1
			waves = 0
			wave_clock = _AICfg.HOME_GUARD_WAVE_GAP_SEC   # первая волна — сразу
			GameManager.tm_event("guard_alarm", {"squads": squads.size()})
		else:
			wave_clock += dt
		_fight()
		return
	if alarm:
		_calm_t += dt
		if _calm_t >= _AICfg.HOME_GUARD_CALM_SEC:
			alarm = false
			waves = 0
			wave_clock = 0.0
			_go_home()
		return
	# Мирно: вернувшиеся на пост засыпают, спящие лечатся
	for s in squads:
		var sid: int = int(s["sid"])
		if _asleep.has(sid):
			_heal(sid, dt)
			continue
		var c: Vector3 = _centroid(sid)
		if c.x == INF:
			continue
		var post: Vector3 = s["post"]
		if Vector2(c.x - post.x, c.z - post.z).length() <= _AICfg.HOME_GUARD_HOME_R:
			# ── СПАТЬ, КОГДА СОБРАЛИСЬ, А НЕ КОГДА ПРИШЁЛ ЦЕНТР (аудит
			# 27.10.2026, ручка guard_sleep_gathered). Центр — медиана: при
			# 33 бойцах на постах и 21, оставшихся IDLE там, где добили
			# чужого, она уже «дома», и сон замораживал обе кучи в 15 м друг
			# от друга до конца партии (зонд qa_tz1027d/Diag, отряды 65/67).
			# Теперь отставшие получают приказ на СВОЁ место поста, и отряд
			# засыпает, когда каждый ближе HOME_GUARD_GATHER_R к нему; не
			# собрались за HOME_GUARD_GATHER_SEC (место занято, застряли) —
			# спят как есть, чтобы охрана не бодрствовала вечно
			if not _OptSys.guard_sleep_gathered:
				_set_sleep(sid, true)
				continue
			var nms: int = Unit.game_ms()
			if int(s.get("gather_ms", 0)) <= 0:
				s["gather_ms"] = nms
			var stray: Array = _stragglers(s)
			if stray.is_empty() \
					or nms - int(s["gather_ms"]) >= int(_AICfg.HOME_GUARD_GATHER_SEC * 1000.0):
				s["gather_ms"] = 0
				_set_sleep(sid, true)
			elif not GameManager.squad_hit_recently(sid) and _home_due(s):
				_order_spots(s, stray)
		else:
			s["gather_ms"] = 0
			if not GameManager.squad_hit_recently(sid) and _home_due(s):
				_order_home(s)

## Бойцы отряда охраны, стоящие дальше HOME_GUARD_GATHER_R от своего места
## поста; ответ — пары [боец, место]
func _stragglers(s: Dictionary) -> Array:
	var out: Array = []
	var ms: Array = _members(int(s["sid"]))
	var r2: float = _AICfg.HOME_GUARD_GATHER_R * _AICfg.HOME_GUARD_GATHER_R
	for k in range(ms.size()):
		var u: Unit = ms[k]
		var p: Vector3 = post_spot(s, k)
		if _xz2(u.global_position, p) > r2:
			out.append([u, p])
	return out

func _order_spots(s: Dictionary, pairs: Array) -> void:
	_OptSys.cmd_src = "home_guard"
	for pr in pairs:
		var u: Unit = pr[0]
		var p: Vector3 = pr[1]
		u.command_move(GameManager.land_target(Vector3(p.x, 0.0, p.z)))
	_OptSys.cmd_src = ""
	s["home_ms"] = Unit.game_ms()

## Пора ли переиздать приказ домой (см. DormantReserve._home_due)
func _home_due(s: Dictionary) -> bool:
	var sid: int = int(s["sid"])
	var nms: int = Unit.game_ms()
	if _all_idle(sid) or nms - int(s.get("home_ms", 0)) >= int(_AICfg.HOME_GUARD_HOME_RETRY_SEC * 1000.0):
		s["home_ms"] = nms
		return true
	return false

func _all_idle(sid: int) -> bool:
	for m in _members(sid):
		if (m as Unit).state != Unit.State.IDLE:
			return false
	return true

## ── ВОЛНЫ ПРОБУЖДЕНИЯ (ТЗ 19.09.2026, блок 3.3) ────────────────────────────
## По тревоге просыпается HOME_GUARD_WAVE_SQUADS отрядов, следующая волна —
## через HOME_GUARD_WAVE_GAP_SEC тревоги; тот, по кому бьют, — вне очереди
var wave_clock: float = 0.0
var waves: int = 0
var waves_total: int = 0

## Тревога: разбудить ВОЛНУ и бросить на ближайшего чужого у замка.
## HOME_GUARD_WAVE_SQUADS <= 0 — ВЕСЬ гарнизон разом (ТЗ 25.09.2026, п. 1:
## обстрел любого отряда базы поднимает все резервы)
func _fight() -> void:
	var cp: Vector3 = _castle_pos()
	var budget: int = 0
	if wave_clock >= _AICfg.HOME_GUARD_WAVE_GAP_SEC:
		budget = _AICfg.HOME_GUARD_WAVE_SQUADS if _AICfg.HOME_GUARD_WAVE_SQUADS > 0 \
			else squads.size()
		wave_clock = 0.0
		waves += 1
		waves_total += 1
	# ОБЩАЯ ЦЕЛЬ ГАРНИЗОНА ищется один раз на такт: у замка, иначе у любого
	# поста (ТЗ 25.09.2026 — весь гарнизон идёт на того, кто обстреливает
	# линию; прежде отряд без чужого в СВОЕЙ зоне просыпался и стоял столбом)
	var shared: Node3D = null
	if cp.x != INF:
		shared = _nearest_foe(cp, _AICfg.HOME_GUARD_ZONE + 20.0)
	# Бьют постройку базы — общая цель у неё (тот, кто бьёт)
	if shared == null and _hit_bld != null and is_instance_valid(_hit_bld):
		shared = _nearest_foe(_hit_bld.global_position, 30.0)
	if shared == null:
		var bd := INF
		for s in squads:
			var f: Node3D = _nearest_foe(s["post"], _AICfg.HOME_GUARD_POST_ZONE + 20.0)
			if f == null:
				continue
			var d: float = _xz2(f.global_position, s["post"])
			if d < bd:
				bd = d
				shared = f
	for s in squads:
		var sid: int = int(s["sid"])
		if _asleep.has(sid):
			if budget > 0 or GameManager.squad_hit_recently(sid):
				_set_sleep(sid, false)
				budget -= 1
			else:
				continue
		if GameManager.squad_in_combat(sid):
			continue
		var c: Vector3 = _centroid(sid)
		if c.x == INF:
			continue
		# Ближний к САМОМУ отряду — первым (он уже в зоне), иначе общая цель
		var foe: Node3D = _nearest_foe(c, _AICfg.HOME_GUARD_ZONE)
		if foe == null:
			foe = shared
		if foe == null:
			continue
		for m in _members(sid):
			(m as Unit).command_attack(foe, true)

func _xz2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length_squared()

func _go_home() -> void:
	for s in squads:
		if _asleep.has(int(s["sid"])):
			continue
		_order_home(s)

## На пост — тем же прямоугольником, каким отряд родился (см.
## Main._spawn_home_defense): колонки вбок от оси, шеренги вглубь от замка
func post_spot(s: Dictionary, k: int) -> Vector3:
	var cols: int = int(s["cols"])
	var sp: float = float(s["spacing"])
	var post: Vector3 = s["post"]
	var lateral: float = (float(k % cols) - float(cols - 1) * 0.5) * sp
	var depth: float = float(k / cols) * sp
	var f: Vector3 = s.get("front", _front)
	var sd: Vector3 = s.get("side", _side)
	return post + sd * lateral - f * depth

func _order_home(s: Dictionary) -> void:
	var ms: Array = _members(int(s["sid"]))
	_OptSys.cmd_src = "home_guard"
	for k in range(ms.size()):
		var p: Vector3 = post_spot(s, k)
		(ms[k] as Unit).command_move(GameManager.land_target(Vector3(p.x, 0.0, p.z)))
	_OptSys.cmd_src = ""

func _heal(sid: int, dt: float) -> void:
	var per: float = _AICfg.HOME_GUARD_HEAL_FRAC * dt
	for m in _members(sid):
		var u := m as Unit
		if u.current_health < u.max_health:
			u.current_health = minf(u.max_health, u.current_health + u.max_health * per)
			u.push_hp()
			u._soa_push_stats()

## Замок снесён: снять отметку, разбудить — дальше их подберёт EnemyAI как
## обычное пополнение
## ── ОДОЛЖИТЬ ОХРАНУ ПОД ОТВЕТНЫЙ УДАР (ТЗ 29.09.2026, п. 1) ──────────────
## Спящие отряды уровня min_level и выше (линии, периметр) без тревоги. Кольцо
## (уровень 1) не отдаётся. Одолженный — обычный полевой отряд (флаг снят,
## разбужен), запись хранится до take_back
var _lent: Dictionary = {}     # sid → запись охраны
var lent_total: int = 0
func lendable(min_level: int) -> int:
	if alarm:
		return 0
	var n := 0
	for s in squads:
		if int(s.get("level", 0)) >= min_level and _asleep.has(int(s["sid"])) \
				and not _members(int(s["sid"])).is_empty():
			n += 1
	return n

func lend(n: int, min_level: int) -> Array:
	var out: Array = []
	if alarm or n <= 0:
		return out
	var kept: Array = []
	for s in squads:
		var sid: int = int(s["sid"])
		if out.size() < n and int(s.get("level", 0)) >= min_level and _asleep.has(sid) \
				and not _members(sid).is_empty():
			_set_sleep(sid, false)
			GameManager.squad_set_home_guard(sid, false)
			_lent[sid] = s
			out.append(sid)
		else:
			kept.append(s)
	squads = kept
	lent_total += out.size()
	return out

## Вернуть одолженных: снова охрана, приказ на свой пост (уснут по приходу)
func take_back() -> int:
	var n := 0
	for sid in _lent.keys():
		if not GameManager.squads.has(int(sid)) or _members(int(sid)).is_empty():
			continue
		var rec: Dictionary = _lent[sid]
		GameManager.squad_set_home_guard(int(sid), true)
		rec["home_ms"] = 0
		squads.append(rec)
		_order_home(rec)
		n += 1
	_lent.clear()
	if n > 0:
		set_process(true)
	return n

func _disband_to_army() -> void:
	_lent.clear()
	for s in squads:
		var sid: int = int(s["sid"])
		if _asleep.has(sid):
			_set_sleep(sid, false)
		GameManager.squad_set_home_guard(sid, false)
	squads.clear()
	_asleep.clear()
	alarm = false
