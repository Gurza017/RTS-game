extends Node
const _OptSys := preload("res://scripts/perf_config.gd")

## ═══════════════════════════════════════════════════════════════════════════
## КОНТРОЛЛЕР ГНОЛЛОВ: ЗОНА ОТВЕТСТВЕННОСТИ И ОХОТА В ЛЕСАХ (13.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Гноллы держат лес СЛЕВА, СПРАВА И НИЖЕ своего пня и НЕ ЛЕЗУТ К БАЗЕ
## людей своей стороны (у пня игрока база — вверх по экрану, у пня ИИ — к
## его крепости). Зона — круг GNOLL_ZONE_RADIUS вокруг пня минус полуплоскость
## «к базе» дальше GNOLL_ZONE_TOWARD_BASE, и минус полоса брода всегда: на
## брод гноллы не выходят ни патрулём, ни погоней.
##
## ОХОТА: раз в GNOLL_HUNT_TICK контроллер ищет рабочих чужой стороны в лесу
## у пня (в зоне, GNOLL_HUNT_RADIUS) — тех, кто прячется или ворует овец, —
## и шлёт на каждого до GNOLL_HUNTERS_PER_PREY свободных гноллов. На охоте
## гнолл ПРЕСЛЕДУЕТ (Gnoll.hunt), закидывает костями и добивает.
##
## Скан идёт по таймеру, не покадрово: рабочие — обход кэша группы
## (их десятки), гноллы — список пня (TrollLair.gnolls).

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var main = null
var _t: float = 0.0
var hunts_issued: int = 0
var zone_clamps: int = 0

func _ready() -> void:
	set_process(true)

func setup(p_main) -> void:
	main = p_main

func _main_ok() -> bool:
	if main == null or not is_instance_valid(main):
		main = GameManager.main
	return main != null and is_instance_valid(main)

# ═════════════════════════════════════════════════════════════════════════════
# ЗОНА
# ═════════════════════════════════════════════════════════════════════════════
## Куда от пня лежит база людей его стороны (единичный, по XZ)
func base_dir(lair: Node3D) -> Vector3:
	if not _main_ok():
		return Vector3(0.0, 0.0, -1.0)
	var side: int = int(lair.get("side_faction")) if lair.get("side_faction") != null else Constants.FACTION_PLAYER
	var base: Vector3 = main.ENEMY_BASE_ANCHOR if side == Constants.FACTION_ENEMY else main.PLAYER_BASE_ANCHOR
	var d: Vector3 = base - lair.global_position
	d.y = 0.0
	return Vector3(0.0, 0.0, -1.0) if d.length() < 0.01 else d.normalized()

## ── К ЛЮБОЙ БАЗЕ ЛЮДЕЙ ГНОЛЛ НЕ ЛЕЗЕТ (ТЗ 14.09.2026, п. 3/5) ─────────────
## «Красный пень» стоит МЕЖДУ базами игрока и ИИ, и полуплоскость только «к
## своей» базе оставляла бы открытой дорогу ко второй. Зона режется
## полуплоскостями к ОБЕИМ базам; base_dir выше остался для стендов
func base_dirs(lair: Node3D) -> Array:
	var out: Array = []
	if not _main_ok():
		return out
	for base in [main.PLAYER_BASE_ANCHOR, main.ENEMY_BASE_ANCHOR]:
		var d: Vector3 = base - lair.global_position
		d.y = 0.0
		if d.length() > 0.01:
			out.append(d.normalized())
	return out

## ── ЛЕС У ПНЯ: ТОЧКИ СТВОЛОВ В ЗОНЕ (ТЗ 14.09.2026, п. 5) ─────────────────
## Кэш на пень, обновляется раз в FOREST_REFRESH_SEC (деревья рубят). По
## нему патруль притягивает точки отрезка к деревьям — стая ходит по
## лесу, а не по чистому полю. Обход resource_nodes — редкий, не покадровый
const FOREST_REFRESH_SEC := 60.0
var _forest: Dictionary = {}     # id пня → {"t": часы, "pts": PackedVector3Array}

func forest_spots(lair: Node3D) -> PackedVector3Array:
	if lair == null or not is_instance_valid(lair):
		return PackedVector3Array()
	var key: int = lair.get_instance_id()
	var now: float = float(Time.get_ticks_msec()) * 0.001
	var rec: Variant = _forest.get(key)
	if rec != null and now - float((rec as Dictionary)["t"]) < FOREST_REFRESH_SEC:
		return (rec as Dictionary)["pts"]
	var pts := PackedVector3Array()
	var c: Vector3 = lair.global_position
	var r2: float = _GobCfg.GNOLL_ZONE_RADIUS * _GobCfg.GNOLL_ZONE_RADIUS
	for n in GameManager.nodes_in_group_cached("resource_nodes"):
		if n == null or not is_instance_valid(n):
			continue
		var rn := n as ResourceNode
		if rn == null or rn.resource_type != Constants.RESOURCE_WOOD:
			continue
		var p: Vector3 = rn.global_position
		if Vector2(p.x - c.x, p.z - c.z).length_squared() > r2:
			continue
		if in_zone(lair, p):
			pts.append(Vector3(p.x, 0.0, p.z))
	_forest[key] = {"t": now, "pts": pts}
	return pts

## Ближайшее дерево к точке в пределах snap; INF — нет
func nearest_forest_spot(lair: Node3D, p: Vector3, snap: float) -> Vector3:
	var best := Vector3.INF
	var bd: float = snap * snap
	for q in forest_spots(lair):
		var d2: float = Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d2 < bd:
			bd = d2
			best = q
	return best

## Полоса брода (с запасом GNOLL_FORD_PAD): сюда гноллам нельзя
func in_ford_band(p: Vector3) -> bool:
	if not _main_ok() or not bool(main.RIVER_ENABLED):
		return false
	if absf(p.z - float(main.FORD_Z)) > float(main.FORD_HALF) + _GobCfg.GNOLL_FORD_PAD:
		return false
	var rx: float = float(main.river_x(p.z))
	return absf(p.x - rx) < float(main.RIVER_HALF_W) + float(main.RIVER_BANK) + _GobCfg.GNOLL_FORD_PAD

func in_zone(lair: Node3D, p: Vector3, slack: float = 0.0) -> bool:
	if lair == null or not is_instance_valid(lair):
		return true
	var d: Vector3 = p - lair.global_position
	d.y = 0.0
	if d.length() > _GobCfg.GNOLL_ZONE_RADIUS + slack:
		return false
	for bd in base_dirs(lair):
		if d.dot(bd) > _GobCfg.GNOLL_ZONE_TOWARD_BASE + slack:
			return false
	return not in_ford_band(p)

## Ближайшая к p точка зоны
func clamp_to_zone(lair: Node3D, p: Vector3) -> Vector3:
	if lair == null or not is_instance_valid(lair):
		return p
	var c: Vector3 = lair.global_position
	var d: Vector3 = p - c
	d.y = 0.0
	# Полуплоскостей две (обе базы) и круг: одна проекция может нарушить
	# соседнее ограничение — прогоняем несколько раз до сходимости
	var dirs: Array = base_dirs(lair)
	for _pass in range(4):
		var moved := false
		for bd in dirs:
			var t: float = d.dot(bd)
			if t > _GobCfg.GNOLL_ZONE_TOWARD_BASE:
				d -= (bd as Vector3) * (t - _GobCfg.GNOLL_ZONE_TOWARD_BASE)
				zone_clamps += 1
				moved = true
		if d.length() > _GobCfg.GNOLL_ZONE_RADIUS:
			d = d.normalized() * _GobCfg.GNOLL_ZONE_RADIUS
			zone_clamps += 1
			moved = true
		if not moved:
			break
	var q := Vector3(c.x + d.x, 0.0, c.z + d.z)
	if in_ford_band(q) and _main_ok():
		# Прочь от русла поперёк реки, на сторону пня
		var rx: float = float(main.river_x(q.z))
		var side: float = -1.0 if c.x < rx else 1.0
		q.x = rx + side * (float(main.RIVER_HALF_W) + float(main.RIVER_BANK) + _GobCfg.GNOLL_FORD_PAD + 1.0)
		zone_clamps += 1
	return q

# ═════════════════════════════════════════════════════════════════════════════
# ОХОТА НА РАБОЧИХ
# ═════════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	# Часы подсистемы (perf_config.sys_meter, qa_bigstand): одна проверка bool
	if not _OptSys.sys_meter:
		_process_timed(delta)
		return
	var _sys_t0: int = Time.get_ticks_usec()
	_process_timed(delta)
	_OptSys.sys_add("gnoll_ai", Time.get_ticks_usec() - _sys_t0)

func _process_timed(delta: float) -> void:
	_t += delta
	if _t < _GobCfg.GNOLL_HUNT_TICK:
		return
	_t = 0.0
	for l in GameManager.troll_lairs:
		if l == null or not is_instance_valid(l):
			continue
		if l.has_method("is_dead") and bool(l.call("is_dead")):
			continue
		_hunt(l as Node3D)

## Рабочие чужой стороны в лесу у пня (в зоне)
func prey_near(lair: Node3D) -> Array:
	var out: Array = []
	var side: int = int(lair.get("side_faction")) if lair.get("side_faction") != null else Constants.FACTION_PLAYER
	if side < 0:
		side = Constants.FACTION_PLAYER
	var r2: float = _GobCfg.GNOLL_HUNT_RADIUS * _GobCfg.GNOLL_HUNT_RADIUS
	var c: Vector3 = lair.global_position
	for n in GameManager.nodes_in_group_cached(Constants.unit_group(side)):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or not (u is Worker) or u.is_dead() or u.garrisoned:
			continue
		var p: Vector3 = u.global_position
		if Vector2(p.x - c.x, p.z - c.z).length_squared() > r2:
			continue
		if not in_zone(lair, p):
			continue
		out.append(u)
	return out

func _hunt(lair: Node3D) -> void:
	var raw: Variant = lair.get("gnolls")
	if raw == null:
		return
	var pack: Array = []
	for g in (raw as Array):
		if g == null or not is_instance_valid(g):
			continue
		var gn := g as Unit
		if gn == null or gn.is_dead() or bool(gn.get("hidden")) or bool(gn.get("hiding_to_lair")):
			continue
		pack.append(gn)
	if pack.is_empty():
		return
	var prey: Array = prey_near(lair)
	if prey.is_empty():
		return
	for w in prey:
		var hunters := 0
		for g in pack:
			if (g as Unit).attack_target == w:
				hunters += 1
		while hunters < _GobCfg.GNOLL_HUNTERS_PER_PREY:
			var best: Unit = null
			var bd := INF
			for g in pack:
				var gn := g as Unit
				if gn.attack_target != null and is_instance_valid(gn.attack_target):
					continue
				var d: float = gn.global_position.distance_squared_to((w as Node3D).global_position)
				if d < bd:
					bd = d
					best = gn
			if best == null:
				break
			best.call("hunt", w)
			hunters += 1
			hunts_issued += 1
