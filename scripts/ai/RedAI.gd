extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## ТАКТИЧЕСКИЙ МОДУЛЬ КРАСНОГО ИИ (заказ владельца, 13.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Живёт внутри EnemyAI (ai) и держит четыре новых поведения; сам EnemyAI
## остался владельцем реестра отрядов, ролей и очереди приказов:
##   • ПЕРИМЕТР У БАШЕН — копейщики и лучники гарнизона встают у башен
##     (perimeter_post), не поместившиеся — на прежний заслон;
##   • БОРЬБА ЗА БРОД — ударная группа FORD_SPEAR_SQUADS копейщиков +
##     FORD_ARCHER_SQUADS лучников идёт на рудник у брода строем
##     (assign_ford_group), копейщики впереди, лучники позади;
##   • ГЛУБОКИЙ СТРОЙ У БРОДА — на марше копейщики идут широко,
##     ближе FORD_DEEP_RANGE перестраиваются в PHALANX_RANKS шеренг (ranks_for);
##   • ВЫЛАЗКИ НА ТРОЛЛЕЙ ради опыта с отходом при критическом уроне
##     (assign_hunt) и РАЗВЕДКА 2:1 — каждый третий рейд без боя (recon_*).
## Всё считается в такте размышления (THINK_INTERVAL), покадрового пути нет.

const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _TowerS := preload("res://scripts/Tower.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var ai = null                      # EnemyAI
var hunt_sid: int = 0
var _hunt_since: float = 0.0
var _hunt_last: float = -1.0e9
var hunts_launched: int = 0
var hunt_retreats: int = 0
var ford_group: Array = []         # sid-ы ударной группы
var ford_owned: bool = false
var recon_runs: int = 0
var deep_switches: int = 0

func _main():
	return ai.main

# ═════════════════════════════════════════════════════════════════════════════
# ПЕРИМЕТР У БАШЕН
# ═════════════════════════════════════════════════════════════════════════════
func towers() -> Array:
	var out: Array = []
	if ai == null or _main() == null:
		return out
	for b in _main().get_tree().get_nodes_in_group("enemy_buildings"):
		if b == null or not is_instance_valid(b):
			continue
		# Именно башня: бараки с 14.09.2026 тоже Castle (крыша для лучников),
		# и «не столица» больше не значит «башня» — пары периметра вставали
		# вокруг бараков (qa_ai 5)
		if b is _TowerS and not (b as Building).is_dead():
			out.append(b)
	return out

## Пост у башни для отряда рода uid с номером idx; Vector3.INF — башен нет
## или этот номер к башням не относится (пусть встаёт на заслон)
func perimeter_post(castle: Castle, uid: String, idx: int, count: int) -> Vector3:
	if not _AICfg.AI_TOWER_PERIMETER or castle == null:
		return Vector3.INF
	var course: Vector3 = ai._defense_course(castle)
	# ТОЛЬКО БАШНИ ВПЕРЕДИ ЗАМКА. Стартовая оборона (15.09.2026) ставит одну
	# башню и ПОЗАДИ крепости; пара у неё стояла бы в тылу — а ни один пост
	# заслона в тыл не смотрит (см. EnemyAI, qa_ai 5). У тыловой башни есть
	# свой гарнизон лучников, пехота ей не нужна
	var tw: Array = []
	for b in towers():
		var off: Vector3 = (b as Node3D).global_position - castle.global_position
		if off.x * course.x + off.z * course.z > 0.0:
			tw.append(b)
	if tw.is_empty():
		return Vector3.INF
	# По одной паре (копейщики + лучники) на башню; сверх — на заслон
	if idx >= tw.size():
		return Vector3.INF
	var t: Node3D = tw[idx] as Node3D
	var right := Vector3(-course.z, 0.0, course.x)
	var side: float = -1.0 if idx % 2 == 0 else 1.0
	var p: Vector3
	if uid == "archer":
		p = t.global_position - course * _AICfg.PERIMETER_BOW_BEHIND + right * (side * 2.0)
	else:
		p = t.global_position + course * _AICfg.PERIMETER_SPEAR_AHEAD \
			+ right * (side * _AICfg.PERIMETER_SIDE * 0.5)
	return GameManager.land_target(p)

# ═════════════════════════════════════════════════════════════════════════════
# БРОД
# ═════════════════════════════════════════════════════════════════════════════
func ford_point() -> Vector3:
	var m = _main()
	if m != null and m.has_method("ford_point"):
		return m.ford_point()
	return Vector3.ZERO

## Рудник у брода (ближайший к точке брода), null — нет
func ford_mine() -> Node3D:
	var best: Node3D = null
	var bd: float = 30.0 * 30.0
	var fp: Vector3 = ford_point()
	for grp in ["neutral_buildings", "player_buildings", "goblin_buildings", "enemy_buildings"]:
		for b in _main().get_tree().get_nodes_in_group(grp):
			if b == null or not is_instance_valid(b) or not (b is Mine) or (b as Building).is_dead():
				continue
			var d: float = fp.distance_squared_to((b as Node3D).global_position)
			if d < bd:
				bd = d
				best = b
	return best

## Ударная группа на брод: копейщики впереди в линию, лучники позади на
## дистанции прикрытия. Возвращает остаток излишков
func assign_ford_group(rest: Array) -> Array:
	ford_group.clear()
	if not _AICfg.AI_FORD_FIRST or rest.is_empty():
		return rest
	# Рудника на броде больше нет (разворот 13.09.2026): группа держит САМ
	# БРОД — точку переправы; рудник, если однажды вернётся, — та же цель
	var mine: Node3D = ford_mine()
	# Ударная группа — когда армия набрана (фаза 2 сценария)
	if ai.squads.size() < _AICfg.FORD_MIN_SQUADS:
		return rest
	ford_owned = mine != null and (mine as Building).faction == Constants.FACTION_ENEMY
	var spears: Array = []
	var bows: Array = []
	for s in rest:
		var uid: String = String((s as Dictionary)["type"])
		if uid == "spearman" and spears.size() < _AICfg.FORD_SPEAR_SQUADS:
			spears.append(s)
		elif uid == "archer" and bows.size() < _AICfg.FORD_ARCHER_SQUADS:
			bows.append(s)
	if spears.is_empty():
		return rest
	var goal: Vector3 = GameManager.land_target(
		mine.global_position if mine != null else ford_point())
	var course: Vector3 = goal - ai._home_pos
	course.y = 0.0
	course = Vector3.FORWARD if course.length() < 0.01 else course.normalized()
	var right := Vector3(-course.z, 0.0, course.x)
	var step: float = ai._screen_step_for("spearman")
	var out: Array = []
	for s in rest:
		var sq: Dictionary = s
		var i: int = spears.find(s)
		if i >= 0:
			var centered: float = float(i) - float(spears.size() - 1) * 0.5
			# Линия копейщиков ПЕРЕД рудником (со своей стороны), плечом к плечу
			var p: Vector3 = goal - course * 6.0 + right * (centered * step)
			ai._set_role(sq, ai.ROLE_FIELD, GameManager.land_target(p), course)
			ford_group.append(ai._sid_of(sq))
			continue
		var j: int = bows.find(s)
		if j >= 0:
			var centered2: float = float(j) - float(bows.size() - 1) * 0.5
			# Лучники — за спинами копейщиков, на дистанции прикрытия
			var p2: Vector3 = goal - course * (6.0 + _AICfg.SCREEN_SPEAR_DIST - _AICfg.SCREEN_BOW_DIST) \
				+ right * (centered2 * step)
			ai._set_role(sq, ai.ROLE_FIELD, GameManager.land_target(p2), course)
			ford_group.append(ai._sid_of(sq))
			continue
		out.append(s)
	return out

## Число шеренг для отряда: копейщик на марше идёт широко, у брода — глубоко.
## Только для ПОЛЕВЫХ ролей; гарнизон и заслон не трогаются (их ширина уже
## размечена по PHALANX_RANKS)
func ranks_for(sq: Dictionary, uid: String, members: Array) -> int:
	if uid != "spearman" or _AICfg.PHALANX_RANKS <= 0:
		return 0
	var role: String = String(sq.get("role", ""))
	if role != ai.ROLE_FIELD and role != ai.ROLE_RECAP and role != ai.ROLE_ASSAULT \
			and role != ai.ROLE_MINE:
		return _AICfg.PHALANX_RANKS
	var c: Vector3 = ai._squad_centroid(members)
	var fp: Vector3 = ford_point()
	var near: bool = Vector2(c.x - fp.x, c.z - fp.z).length() <= _AICfg.FORD_DEEP_RANGE
	var ranks: int = _AICfg.PHALANX_RANKS if near else _AICfg.PHALANX_RANKS_MARCH
	if int(sq.get("ranks_now", 0)) != ranks:
		if sq.has("ranks_now"):
			deep_switches += 1
			sq["issued"] = false          # перестроение — новый приказ строю
		sq["ranks_now"] = ranks
	return ranks

# ═════════════════════════════════════════════════════════════════════════════
# ВЫЛАЗКИ НА ТРОЛЛЕЙ (ОПЫТ)
# ═════════════════════════════════════════════════════════════════════════════
func own_lair() -> Node3D:
	var l = GameManager.lair_for(Constants.FACTION_ENEMY)
	if l == null or not is_instance_valid(l):
		return null
	if l.has_method("is_dead") and bool(l.call("is_dead")):
		return null
	return l as Node3D

func nearest_troll(from: Vector3) -> Node3D:
	var l: Node3D = own_lair()
	if l == null:
		return null
	var raw: Variant = l.get("trolls")
	if raw == null:
		return null
	var best: Node3D = null
	var bd := INF
	for t in (raw as Array):
		if t == null or not is_instance_valid(t):
			continue
		var u := t as Unit
		if u == null or u.is_dead():
			continue
		var d: float = from.distance_squared_to(u.global_position)
		if d < bd:
			bd = d
			best = u
	return best

## Сколько отрядов вправе быть в вылазках (доля армии)
func sortie_cap() -> int:
	return maxi(int(floor(float(ai.squads.size()) * _AICfg.SORTIE_ARMY_FRACTION)), 1)

## Отряд-охотник на троллей: копейщики (первыми) идут бить троллей у своего
## пня; отход — по сроку или при запасе ниже HUNT_RETREAT_STRENGTH.
## Возвращает остаток
func assign_hunt(rest: Array, castle: Castle) -> Array:
	if not _AICfg.AI_TROLL_HUNT or castle == null or rest.is_empty():
		return rest
	var pick: Dictionary = {}
	for s in rest:
		if hunt_sid > 0 and ai._sid_of(s) == hunt_sid:
			pick = s
			break
	if pick.is_empty():
		hunt_sid = 0
		if ai.clock < _AICfg.HUNT_FIRST_SEC or ai.clock - _hunt_last < _AICfg.HUNT_INTERVAL_SEC:
			return rest
		if nearest_troll(ai._home_pos) == null or ai.squads.size() < _AICfg.RAID_MIN_ARMY:
			return rest
		# Стычки вне баз — не больше SORTIE_ARMY_FRACTION армии (вылазка + рейд)
		if 1 + (1 if ai.raid_sid > 0 else 0) > sortie_cap():
			return rest
		for s in rest:
			if String((s as Dictionary)["type"]) == "spearman":
				pick = s
				break
		if pick.is_empty():
			for s in rest:
				if String((s as Dictionary)["type"]) == "warrior":
					pick = s
					break
		if pick.is_empty():
			return rest
		hunt_sid = ai._sid_of(pick)
		_hunt_since = ai.clock
		_hunt_last = ai.clock
		hunts_launched += 1
		ai.last_action += "|вылазка №%d на троллей" % hunts_launched
	var troll: Node3D = nearest_troll(ai._squad_centroid(pick["members"]))
	var weak: bool = ai._squad_strength(pick) < _AICfg.HUNT_RETREAT_STRENGTH
	var expired: bool = ai.clock - _hunt_since > _AICfg.HUNT_MAX_SEC
	var broken: bool = String(pick.get("role", "")) == ai.ROLE_RETREAT
	if weak or expired or broken or troll == null:
		hunt_sid = 0
		hunt_retreats += 1
		ai.last_action += "|вылазка отходит (%s)" % (
			"урон" if weak else ("срок" if expired else "троллей нет"))
		var sid: int = ai._sid_of(pick)
		if sid > 0 and castle.request_garrison(sid):
			pick["role"] = ai.ROLE_RETREAT
			pick["retreat_until"] = Time.get_ticks_msec() + int(_AICfg.RETREAT_MIN_SEC * 1000.0)
			pick["issued"] = true
		else:
			ai._set_role(pick, ai.ROLE_GUARD, castle.global_position)
	else:
		pick["hunt_prey"] = troll
		ai._set_role(pick, ai.ROLE_HUNT, GameManager.land_target(troll.global_position))
		pick["issued"] = false
	var out: Array = []
	for s in rest:
		if s != pick:
			out.append(s)
	return out

# ═════════════════════════════════════════════════════════════════════════════
# РАЗВЕДКА 2 : 1
# ═════════════════════════════════════════════════════════════════════════════
## Этот рейд — чистая разведка? Каждый RECON_EVERY-й (третий, шестой…):
## первые два — боем, чтобы экономику игрока щупали сразу после перемирия
func recon_mode(raid_no: int) -> bool:
	return _AICfg.RECON_EVERY > 0 and raid_no % _AICfg.RECON_EVERY == 0

## Точка разведки: на RECON_DEPTH м от базы игрока со стороны ИИ
func recon_point(base: Vector3) -> Vector3:
	var d: Vector3 = ai._home_pos - base
	d.y = 0.0
	d = Vector3.FORWARD if d.length() < 0.01 else d.normalized()
	return GameManager.land_target(base + d * _AICfg.RECON_DEPTH)

## Разведка боем: самая слабая цель у базы игрока — рабочий; иначе боец из
## одиночного/раненого отряда (меньше живых × доля запаса)
func weakest_prey(base: Vector3) -> Node3D:
	var worker: Node3D = ai._raid_prey(base)
	if worker != null and worker is Worker:
		return worker
	var best: Node3D = null
	var bs := INF
	var r2: float = _AICfg.RAID_HUNT_RADIUS * _AICfg.RAID_HUNT_RADIUS
	for n in _main().get_tree().get_nodes_in_group("player_units"):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.garrisoned or u is Worker:
			continue
		if base.distance_squared_to(u.global_position) > r2:
			continue
		var alive: int = maxi(GameManager.squad_member_count(u.squad_id), 1) if u.squad_id > 0 else 1
		var score: float = float(alive) * (u.current_health / maxf(u.max_health, 1.0))
		if score < bs:
			bs = score
			best = u
	return best if best != null else worker
