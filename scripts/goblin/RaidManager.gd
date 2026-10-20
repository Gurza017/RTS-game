extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## РЕГУЛЯРНЫЕ РЕЙДЫ ОРДЫ: РАСПИСАНИЕ И ПРИОРИТЕТ ЦЕЛЕЙ (ТЗ 14.10.2026, п. 1)
## ═══════════════════════════════════════════════════════════════════════════
## Файл без class_name и без узла: всё статическое, подключается preload-ом из
## движка волн (GoblinFortressAssaultEvent). Движок у рейда и у штурма ОДИН —
## площадка сбора, кулак, маршрут бродом в нижний проход базы, групповое агро;
## здесь живёт то, чем рейд отличается от штурма:
##   • РАСПИСАНИЕ партии (spawn_config.RAID_SCHEDULE + ASSAULT_EVENT_TIMES /
##     WAVES) в ОДИН список по времени, со сдвоенными волнами крупных сроков:
##     состав срока делится пополам, вторая половина выходит через PAIR_GAP
##     вслед первой (ТЗ: «сначала 1 отряд, через пару минут второй вслед»);
##   • ПРИОРИТЕТ ЦЕЛЕЙ рейда: рабочие → башни → бараки → дома и прочие
##     постройки → крепости последними. Списки целей собираются ОДИН раз на
##     такт движка (кэш по номеру такта), а не на каждый отряд — иначе десять
##     отрядов рейда десять раз обходили бы группу бойцов игрока.
##
## Производительность: здесь нет ни покадрового пути, ни сканов — только
## редкие обходы групп по запросу отряда, которому нужна новая цель.

const _Spawn := preload("res://scripts/spawn_config.gd")
const _UCfgR := preload("res://scripts/unit_stats_config.gd")

const KIND_RAID := "raid"
const KIND_ASSAULT := "assault"

## ── РАСПИСАНИЕ ─────────────────────────────────────────────────────────────
## [{t, kind, comp, label, pair_i}] по возрастанию t. pair — делить ли состав
## пополам со второй половиной через gap (крупные сроки штурма)
static func schedule(pair: bool = _Spawn.ASSAULT_EVENT_PAIR,
		gap: float = _Spawn.ASSAULT_EVENT_PAIR_GAP_SEC) -> Array:
	var out: Array = []
	if _Spawn.RAID_ENABLED:
		for e in _Spawn.RAID_SCHEDULE:
			var d: Dictionary = e
			out.append({"t": float(d["t"]), "kind": KIND_RAID,
				"comp": (d["comp"] as Dictionary).duplicate(),
				"label": "рейд %d:%02d" % [int(float(d["t"]) / 60.0), int(float(d["t"])) % 60], "pair_i": 0})
	if _Spawn.ASSAULT_EVENT_ENABLED:
		var times: Array = _Spawn.ASSAULT_EVENT_TIMES
		var comps: Array = _Spawn.ASSAULT_EVENT_WAVES
		for i in range(times.size()):
			var t: float = float(times[i])
			var comp: Dictionary = comps[mini(i, comps.size() - 1)]
			var lbl: String = "штурм %d:00" % int(t / 60.0)
			if pair:
				var halves: Array = split_comp(comp)
				out.append({"t": t, "kind": KIND_ASSAULT, "comp": halves[0], "label": lbl + " (1/2)", "pair_i": 1})
				out.append({"t": t + gap, "kind": KIND_ASSAULT, "comp": halves[1], "label": lbl + " (2/2)", "pair_i": 2})
			else:
				out.append({"t": t, "kind": KIND_ASSAULT, "comp": comp.duplicate(), "label": lbl, "pair_i": 0})
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return out

## Состав пополам по каждому роду: первая половина — округление вверх
## (голова кулака не слабее хвоста)
static func split_comp(comp: Dictionary) -> Array:
	var a: Dictionary = {}
	var b: Dictionary = {}
	for k in comp:
		var n: int = int(comp[k])
		var first: int = int(ceil(float(n) / 2.0))
		if first > 0:
			a[k] = first
		if n - first > 0:
			b[k] = n - first
	return [a, b]

## Порядок выхода отрядов: чередование родов, голова кулака не из одной
## конницы (тот же приём, что был у штурма)
static func spawn_order(comp: Dictionary) -> Array:
	var q: Array = []
	var left: Dictionary = comp.duplicate()
	var kinds: Array = ["goblin_spearman", "goblin_rider", "big_goblin"]
	for k in comp:
		if not (k in kinds):
			kinds.append(k)
	var any := true
	while any:
		any = false
		for k in kinds:
			if int(left.get(k, 0)) > 0:
				q.append(String(k))
				left[k] = int(left[k]) - 1
				any = true
	return q

## ── ЦЕЛИ РЕЙДА ─────────────────────────────────────────────────────────────
## Кэш списков на такт: ключ — номер такта движка (tick), в одном такте
## спрашивают несколько отрядов
static var _cache_tick: int = -1
static var _workers: Array = []
static var _towers: Array = []
static var _barracks: Array = []
static var _houses: Array = []
static var _strongholds: Array = []

static func _ok_unit(u) -> bool:
	return u != null and is_instance_valid(u) and (u is Unit) and not (u as Unit).is_dead() \
		and not (u as Unit).garrisoned

static func _ok_bld(b) -> bool:
	return b != null and is_instance_valid(b) and (b is Building) and not (b as Building).is_dead() \
		and int((b as Building).faction) == Constants.FACTION_PLAYER

static func refresh(tree: SceneTree, tick: int) -> void:
	if tick == _cache_tick:
		return
	_cache_tick = tick
	_workers.clear(); _towers.clear(); _barracks.clear(); _houses.clear(); _strongholds.clear()
	for u in tree.get_nodes_in_group(Constants.unit_group(Constants.FACTION_PLAYER)):
		if u is Worker and _ok_unit(u):
			_workers.append(u)
	for b in tree.get_nodes_in_group(Constants.building_group(Constants.FACTION_PLAYER)):
		if not _ok_bld(b) or b is Mine or not GameManager.goblin_may_raze(b):
			continue
		var bld := b as Building
		var id: String = String(bld.building_id)
		if id.is_empty():
			continue   # стройплощадка
		if bld.has_method("is_stronghold") and bool(bld.call("is_stronghold")):
			# Бараки — тоже «крепость» по классу (Barracks extends Castle), но в
			# приоритете рейда они свой пункт
			if bld is Barracks:
				_barracks.append(bld)
			elif id == "tower":
				_towers.append(bld)
			else:
				_strongholds.append(bld)
		elif id == "tower":
			_towers.append(bld)
		elif bld is Barracks or id == "barracks":
			_barracks.append(bld)
		else:
			_houses.append(bld)

static func _nearest(list: Array, from: Vector3, r: float = INF) -> Node3D:
	var best: Node3D = null
	var bd: float = r * r
	for n in list:
		if n == null or not is_instance_valid(n):
			continue
		if (n is Unit and (n as Unit).is_dead()) or (n is Building and (n as Building).is_dead()):
			continue
		var p: Vector3 = (n as Node3D).global_position
		var d: float = Vector2(p.x - from.x, p.z - from.z).length_squared()
		if d < bd:
			bd = d
			best = n
	return best

## Цель рейда для отряда в точке from: рабочий в RAID_WORKER_R → башня →
## бараки → дом/прочее → крепость. null — целей у игрока нет
static func raid_target(tree: SceneTree, tick: int, from: Vector3) -> Node3D:
	refresh(tree, tick)
	var t: Node3D = _nearest(_workers, from, _Spawn.RAID_WORKER_R)
	if t != null:
		return t
	for list in [_towers, _barracks, _houses, _strongholds]:
		t = _nearest(list as Array, from)
		if t != null:
			return t
	return null

## Какой пункт приоритета занимает цель (стенды и телеметрия): 1 рабочий,
## 2 башня, 3 бараки, 4 дом/прочее, 5 крепость, 0 — не цель рейда
static func target_rank(t) -> int:
	if t == null or not is_instance_valid(t):
		return 0
	if t is Worker:
		return 1
	if not (t is Building):
		return 0
	var bld := t as Building
	var id: String = String(bld.building_id)
	if id == "tower":
		return 2
	if bld is Barracks or id == "barracks":
		return 3
	if bld.has_method("is_stronghold") and bool(bld.call("is_stronghold")):
		return 5
	return 4
