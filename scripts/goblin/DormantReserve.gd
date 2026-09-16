extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ДРЕМЛЮЩИЙ РЕЗЕРВ ОРДЫ (заказ владельца, 13.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Одноразовый спавн на 00:00 ЗА лагерем гоблинов (goblin_config.RESERVE_*):
## элитная конница трёх рангов, туши и пехота. Спит тем же механизмом, что и
## стартовая орда (GoblinAI._set_dormant: тик снят, бит F_DORMANT в ядре,
## картинка живёт — туман прячет бойца сам). На дальние раздражители не
## реагирует: физтика у спящего нет, авто-агро не работает по построению.
##
## ПРОСЫПАЕТСЯ ТОЛЬКО НА ШТУРМ ЛАГЕРЯ: RESERVE_WAKE_FOES чужих боевых в
## RESERVE_WAKE_RADIUS от деревни, удар по самому резерву или по хижине.
## Отбил — через RESERVE_CALM_SEC без угрозы идёт на посты и засыпает снова.
## Наскоком базу гоблинов не взять.
##
## ВОЖАК ВПРАВЕ ЗАНЯТЬ КОННИЦУ (borrow_cavalry): взятый отряд вожак ведёт
## своим рейдом (GoblinAI._raid_plan, hit & run через брод), по концу рейда
## отдаёт обратно (return_squad) — отряд возвращается на пост и лечится
## там (RESERVE_HEAL_FRAC в секунду), а не в хижине.
##
## Проверки — по таймеру RESERVE_TICK_SEC, не покадрово; угроза ищется по
## сетке ядра (nearest_of_side), а не обходом групп.

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var main = null
var ai = null                    # GoblinAI
var village: Vector3 = Vector3.ZERO
## Записи: {"sid": int, "post": Vector3, "unit": String, "vet": int}
var squads: Array = []
var lent: Dictionary = {}        # sid → true: отряд у вожака на вылазке
var alarm: bool = false
var wakes: int = 0
var _calm_t: float = 0.0
var _tick_t: float = 0.0
var _asleep: Dictionary = {}     # sid → true: отряд сейчас спит

# ═════════════════════════════════════════════════════════════════════════════
# СПАВН
# ═════════════════════════════════════════════════════════════════════════════
func spawn(p_main, p_village: Vector3, p_ai) -> int:
	main = p_main
	village = p_village
	ai = p_ai
	# «За лагерем» — дальше от центра карты, чем сама деревня
	var away: Vector3 = village
	away.y = 0.0
	away = Vector3(1.0, 0.0, -1.0).normalized() if away.length() < 0.01 else away.normalized()
	var right := Vector3(-away.z, 0.0, away.x)
	var cols: int = maxi(_GobCfg.RESERVE_COLS, 1)
	var made := 0
	for i in range(_GobCfg.RESERVE_SQUADS.size()):
		var row: Dictionary = _GobCfg.RESERVE_SQUADS[i]
		var uid: String = String(row["unit"])
		var n: int = int(row["count"])
		if n <= 0:
			n = int(_GobCfg.SQUAD_SIZE.get(uid, 10))
		var c: int = i % cols
		var r: int = i / cols
		var lateral: float = (float(c) - float(cols - 1) * 0.5) * _GobCfg.RESERVE_STEP
		var depth: float = _GobCfg.VILLAGE_RADIUS + _GobCfg.RESERVE_BACK \
			+ float(r) * _GobCfg.RESERVE_STEP
		var p: Vector3 = village + away * depth + right * lateral
		p.x = clampf(p.x, -main.GEN_HALF_X, main.GEN_HALF_X)
		p.z = clampf(p.z, -main.GEN_HALF_Z, main.GEN_HALF_Z)
		p = GameManager.land_target(Vector3(p.x, 0.0, p.z))
		var sid: int = int(main.spawn_goblin_squad(uid, n, p))
		if sid <= 0:
			continue
		var vet: int = int(row["vet"])
		if vet > 0:
			main.grant_squad_veterancy(sid, vet, int(row["picks"]), _GobCfg.VETERAN_PREFERENCE)
		squads.append({"sid": sid, "post": p, "unit": uid, "vet": vet})
		if ai != null:
			ai.register_reserve(sid)
		made += 1
	_sleep_all()
	set_process(made > 0)
	return made

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
	if ai == null:
		return
	for m in _members(sid):
		var u := m as Unit
		ai._set_dormant(u, on)
		if not on:
			u.wake_for_lod()
	if on:
		_asleep[sid] = true
	else:
		_asleep.erase(sid)

func _sleep_all() -> void:
	for s in squads:
		if not lent.has(int(s["sid"])):
			_set_sleep(int(s["sid"]), true)

func is_asleep(sid: int) -> bool:
	return _asleep.has(sid)

func asleep_count() -> int:
	return _asleep.size()

func _centroid(sid: int) -> Vector3:
	var ms: Array = _members(sid)
	if ms.is_empty():
		return Vector3.INF
	return GameManager._centroid_of(ms)

## Ближайший чужой боец к точке (по сетке ядра, все чужие стороны)
func _nearest_foe(p: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for f in Constants.other_factions(Constants.FACTION_GOBLIN):
		var cand = GameManager.army.nearest_of_side(p.x, p.z, int(f), r)
		if cand == null or not is_instance_valid(cand):
			continue
		var u := cand as Unit
		if u == null or u.is_dead() or u is Worker:
			continue
		var d: float = Vector2(u.global_position.x - p.x, u.global_position.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = u
	return best

## Чужих БОЕВЫХ у деревни — по сетке соседей, рабочие не в счёт
func _foes_at_village() -> int:
	var n := 0
	for m in GameManager.unit_grid.query_radius(village, _GobCfg.RESERVE_WAKE_RADIUS):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead() or u is Worker or int(u.faction) == Constants.FACTION_GOBLIN:
			continue
		n += 1
	return n

## Штурм лагеря: много чужих у деревни ЛИБО бьют сам резерв
func _threatened() -> bool:
	if _foes_at_village() >= _GobCfg.RESERVE_WAKE_FOES:
		return true
	for s in squads:
		var sid: int = int(s["sid"])
		if not lent.has(sid) and GameManager.squad_in_combat(sid):
			return true
	return false

func _process(delta: float) -> void:
	_tick_t += delta
	if _tick_t < _GobCfg.RESERVE_TICK_SEC:
		return
	var dt: float = _tick_t
	_tick_t = 0.0
	# Выбитые отряды — вон из реестра
	var kept: Array = []
	for s in squads:
		if GameManager.squads.has(int(s["sid"])) and not _members(int(s["sid"])).is_empty():
			kept.append(s)
		else:
			_asleep.erase(int(s["sid"]))
			lent.erase(int(s["sid"]))
	squads = kept
	if squads.is_empty():
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
		if _calm_t >= _GobCfg.RESERVE_CALM_SEC:
			alarm = false
			_go_home()
		return
	# Мирно: вернувшиеся на пост засыпают, спящие лечатся
	for s in squads:
		var sid: int = int(s["sid"])
		if lent.has(sid):
			continue
		if _asleep.has(sid):
			_heal(sid, dt)
			continue
		var c: Vector3 = _centroid(sid)
		if c.x == INF:
			continue
		var post: Vector3 = s["post"]
		if Vector2(c.x - post.x, c.z - post.z).length() <= _GobCfg.RESERVE_HOME_RADIUS:
			_set_sleep(sid, true)
		elif not GameManager.squad_in_combat(sid) and _all_idle(sid):
			_order_home(sid, post)

func _all_idle(sid: int) -> bool:
	for m in _members(sid):
		if (m as Unit).state != Unit.State.IDLE:
			return false
	return true

## Тревога: разбудить и бросить на ближайшего чужого у деревни
func _fight() -> void:
	for s in squads:
		var sid: int = int(s["sid"])
		if lent.has(sid):
			continue
		if _asleep.has(sid):
			_set_sleep(sid, false)
		if GameManager.squad_in_combat(sid):
			continue
		var c: Vector3 = _centroid(sid)
		if c.x == INF:
			continue
		var foe: Node3D = _nearest_foe(village, _GobCfg.RESERVE_WAKE_RADIUS + 20.0)
		if foe == null:
			foe = _nearest_foe(c, _GobCfg.RESERVE_WAKE_RADIUS)
		if foe == null:
			continue
		for m in _members(sid):
			(m as Unit).command_attack(foe, true)

func _go_home() -> void:
	for s in squads:
		var sid: int = int(s["sid"])
		if lent.has(sid) or _asleep.has(sid):
			continue
		_order_home(sid, s["post"])

## На пост — толпой вокруг точки, теми же местами, что при рождении
func _order_home(sid: int, post: Vector3) -> void:
	var ms: Array = _members(sid)
	var n: int = ms.size()
	for k in range(n):
		var ho: Vector2 = _GobCfg.horde_offset(k, n, sid)
		(ms[k] as Unit).command_move(GameManager.land_target(
			Vector3(post.x + ho.x, 0.0, post.z + ho.y)))

func _heal(sid: int, dt: float) -> void:
	var per: float = _GobCfg.RESERVE_HEAL_FRAC * dt
	for m in _members(sid):
		var u := m as Unit
		if u.current_health < u.max_health:
			u.current_health = minf(u.max_health, u.current_health + u.max_health * per)
			u._soa_push_stats()

# ═════════════════════════════════════════════════════════════════════════════
# КОННИЦА ВЗАЙМЫ ВОЖАКУ
# ═════════════════════════════════════════════════════════════════════════════
## Отдать вожаку до `n` конных отрядов (не больше RESERVE_LEND_MAX сразу,
## только спящих и целых). Возвращает список sid; отряды разбужены
func borrow_cavalry(n: int) -> Array:
	var out: Array = []
	var room: int = _GobCfg.RESERVE_LEND_MAX - lent.size()
	for s in squads:
		if out.size() >= mini(n, room):
			break
		var sid: int = int(s["sid"])
		if String(s["unit"]) != "goblin_rider" or lent.has(sid) or not _asleep.has(sid):
			continue
		if alarm:
			break
		_set_sleep(sid, false)
		lent[sid] = true
		out.append(sid)
	return out

## Вожак вернул отряд: пост его прежний, дойдёт — уснёт и полечится
func return_squad(sid: int) -> Vector3:
	lent.erase(sid)
	for s in squads:
		if int(s["sid"]) == sid:
			if not _asleep.has(sid) and GameManager.squads.has(sid):
				_order_home(sid, s["post"])
			return s["post"]
	return village

func post_of(sid: int) -> Vector3:
	for s in squads:
		if int(s["sid"]) == sid:
			return s["post"]
	return village
