extends Node

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

## Взять отряд под охрану: пост — его нынешний центр, сон — сразу
func adopt(sid: int, post: Vector3, cols: int, spacing: float) -> void:
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
	return float(Time.get_ticks_msec() - castle.last_hit_ms) * 0.001 < _AICfg.HOME_GUARD_HIT_SEC

## Штурм: удар по замку, прорыв в зону ЛИБО бьют саму охрану
func _threatened() -> bool:
	if castle_under_attack():
		return true
	if _foes_in_zone() >= _AICfg.HOME_GUARD_WAKE_FOES:
		return true
	for s in squads:
		if GameManager.squad_in_combat(int(s["sid"])):
			return true
	return false

func _process(delta: float) -> void:
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
		_fight()
		return
	if alarm:
		_calm_t += dt
		if _calm_t >= _AICfg.HOME_GUARD_CALM_SEC:
			alarm = false
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
			_set_sleep(sid, true)
		elif not GameManager.squad_in_combat(sid) and _all_idle(sid):
			_order_home(s)

func _all_idle(sid: int) -> bool:
	for m in _members(sid):
		if (m as Unit).state != Unit.State.IDLE:
			return false
	return true

## Тревога: разбудить и бросить на ближайшего чужого у замка
func _fight() -> void:
	var cp: Vector3 = _castle_pos()
	for s in squads:
		var sid: int = int(s["sid"])
		if _asleep.has(sid):
			_set_sleep(sid, false)
		if GameManager.squad_in_combat(sid):
			continue
		var c: Vector3 = _centroid(sid)
		if c.x == INF:
			continue
		var foe: Node3D = null
		if cp.x != INF:
			foe = _nearest_foe(cp, _AICfg.HOME_GUARD_ZONE + 20.0)
		if foe == null:
			foe = _nearest_foe(c, _AICfg.HOME_GUARD_ZONE)
		if foe == null:
			continue
		for m in _members(sid):
			(m as Unit).command_attack(foe, true)

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
	return post + _side * lateral - _front * depth

func _order_home(s: Dictionary) -> void:
	var ms: Array = _members(int(s["sid"]))
	for k in range(ms.size()):
		var p: Vector3 = post_spot(s, k)
		(ms[k] as Unit).command_move(GameManager.land_target(Vector3(p.x, 0.0, p.z)))

func _heal(sid: int, dt: float) -> void:
	var per: float = _AICfg.HOME_GUARD_HEAL_FRAC * dt
	for m in _members(sid):
		var u := m as Unit
		if u.current_health < u.max_health:
			u.current_health = minf(u.max_health, u.current_health + u.max_health * per)
			u._soa_push_stats()

## Замок снесён: снять отметку, разбудить — дальше их подберёт EnemyAI как
## обычное пополнение
func _disband_to_army() -> void:
	for s in squads:
		var sid: int = int(s["sid"])
		if _asleep.has(sid):
			_set_sleep(sid, false)
		GameManager.squad_set_home_guard(sid, false)
	squads.clear()
	_asleep.clear()
	alarm = false
