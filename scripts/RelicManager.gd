extends Node
## ═══════════════════════════════════════════════════════════════════════════
## РЕЛИКВИИ-ШТАНДАРТЫ И ОБЩАЯ КОПИЛКА ОПЫТА АРМИИ (ТЗ 10.10.2026, блок 5)
## ═══════════════════════════════════════════════════════════════════════════
## Узел живёт ребёнком автозагрузки GameManager (GameManager.relic_mgr()), числа
## — в relic_config.gd, кнопка — RelicButton.gd.
##
## ЧЕМ РЕЛИКВИЯ ОТЛИЧАЕТСЯ ОТ ЗНАМЕНИ ОТРЯДА. Знамя ветеранства — картинка
## звания отряда, его несёт [ряд 0, колонка 0] и оно не даёт ничего, кроме
## вида. Реликвия — ПРЕДМЕТ: её несёт конкретный боец (центральный в момент
## выдачи), она даёт ауру, падает на землю с гибелью носителя и переходит к
## тому, кто на неё наступит, — в том числе к врагу. Второй механики знамени
## здесь нет: знамя отряда продолжает жить своей жизнью.
##
## ── ЦЕНА ─────────────────────────────────────────────────────────────────
## Ни одной строки в покадровом пути бойца. Аура — один проход по всем
## реликвиям раз в AURA_TICK_SEC: по одному запросу строк к ядру на реликвию
## (query_radius_rows — PackedInt32Array, без массива узлов), бонус раздаётся
## ПОЛЯМИ бойца (vet_attack, morale, attack_cooldown — то, что уже читает бой)
## и снимается ровно тем же числом при выходе из радиуса. Носитель и подбор
## лежащих — раз в PICK_TICK_SEC. Флаги двигаются в _process: реликвий
## единицы.

const _RCfg := preload("res://scripts/relic_config.gd")
const _UCfgR := preload("res://scripts/unit_stats_config.gd")
const _SquadBannerR := preload("res://scripts/SquadBanner.gd")
const _BannerArtR := preload("res://scripts/BannerArt.gd")

signal pool_changed(value: float)
signal armed_changed(on: bool)

## Копилка опыта армии игрока
var pool: float = 0.0
## Взведён ли режим выдачи (кнопка нажата один раз, ждём клика по отряду)
var armed: bool = false

## Реликвии: {"id", "level", "carrier": Unit|null, "pos": Vector3,
## "node": MeshInstance3D|null, "label": Label3D|null}. carrier == null —
## лежит на земле в pos
var relics: Array = []
var _next_id: int = 1

## Розданные бонусы: id бойца → [боец, атака, доля кулдауна (абс.), мораль,
## уровень]. Снимается ровно то, что выдано
var _applied: Dictionary = {}

var _aura_t: float = 0.0
var _pick_t: float = 0.0

## Стендам
var grants: int = 0
var drops: int = 0
var pickups: int = 0
var aura_ticks: int = 0

# ═════════════════════════════════════════════════════════════════════════════
# КОПИЛКА И ВЫДАЧА
# ═════════════════════════════════════════════════════════════════════════════

func add_xp(n: float) -> void:
	if n <= 0.0:
		return
	var was: bool = charged()
	pool = minf(pool + n * _RCfg.POOL_PER_KILL, _RCfg.POOL_COST * 9.0)
	pool_changed.emit(pool)
	if charged() and not was:
		AudioManager.play_ui("smith_pick")

func charged() -> bool:
	return pool >= _RCfg.POOL_COST

func pool_frac() -> float:
	return clampf(pool / _RCfg.POOL_COST, 0.0, 1.0)

func arm(on: bool) -> void:
	if on and not charged():
		on = false
	if armed == on:
		return
	armed = on
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if on else Input.CURSOR_ARROW)
	armed_changed.emit(on)

## Клик ЛКМ во взведённом режиме (зовёт SelectionManager). true — клик
## израсходован. Промах (не свой отряд) режим не снимает: снимают Esc и ПКМ
func click_unit(target) -> bool:
	if not armed:
		return false
	if target == null or not is_instance_valid(target) or not (target is Unit):
		return true
	var u := target as Unit
	if u.is_dead() or u.faction != Constants.FACTION_PLAYER or u.squad_id <= 0:
		return true
	if grant_to_squad(u.squad_id) >= 0:
		arm(false)
	return true

## ВЫДАТЬ ОТРЯДУ: +1 уровень ветеранства и реликвия центральному бойцу; если
## отряд уже несёт реликвию — её уровень +1. Списывает POOL_COST (force —
## без списания, для стендов и загрузки). Возвращает id реликвии или −1
func grant_to_squad(sid: int, force: bool = false) -> int:
	if not GameManager.squads.has(sid):
		return -1
	if not force and not charged():
		return -1
	var alive: Array = _alive_members(sid)
	if alive.is_empty():
		return -1
	if not force:
		pool -= _RCfg.POOL_COST
		pool_changed.emit(pool)
	GameManager.grant_squad_level(sid)
	var r: Variant = relic_of_squad(sid)
	if r != null:
		(r as Dictionary)["level"] = int((r as Dictionary)["level"]) + 1
		_refresh_visual(r)
	else:
		r = _new_relic(1, _central_member(alive), Vector3.ZERO)
	grants += 1
	_aura_t = 0.0          # аура — в ближайшем такте, а не через полсекунды
	return int((r as Dictionary)["id"])

## Реликвия, которую несёт живой боец отряда (первая найденная)
func relic_of_squad(sid: int) -> Variant:
	for r in relics:
		var c = (r as Dictionary)["carrier"]
		if c != null and is_instance_valid(c) and not (c as Unit).is_dead() \
				and (c as Unit).squad_id == sid:
			return r
	return null

func relic_of_unit(u: Node) -> Variant:
	for r in relics:
		if (r as Dictionary)["carrier"] == u:
			return r
	return null

func _alive_members(sid: int) -> Array:
	var out: Array = []
	# Состав напрямую: squad_members() распускает опустевший отряд в геттере
	for m in ((GameManager.squads[sid] as Dictionary)["members"] as Array):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u != null and not u.is_dead() and not u.garrisoned:
			out.append(u)
	return out

## Центральный боец — ближайший к медиане отряда (GameManager._centroid_of)
func _central_member(alive: Array) -> Unit:
	var c: Vector3 = GameManager._centroid_of(alive)
	var best: Unit = null
	var bd := INF
	for m in alive:
		var p: Vector3 = (m as Unit).global_position
		var d: float = (p.x - c.x) * (p.x - c.x) + (p.z - c.z) * (p.z - c.z)
		if d < bd:
			bd = d
			best = m
	return best

func _new_relic(level: int, carrier: Unit, pos: Vector3) -> Dictionary:
	var p0: Vector3 = carrier.global_position if carrier != null else pos
	p0.y = 0.0
	# Пустой носитель — настоящий nil, а не типизированный null-объект:
	# занятость слота проверяется по типу (см. _tick_carriers)
	var cv: Variant = null
	if carrier != null:
		cv = carrier
	var r: Dictionary = {"id": _next_id, "level": level, "carrier": cv,
		"pos": p0, "node": null, "label": null}
	_next_id += 1
	relics.append(r)
	_refresh_visual(r)
	return r

## Положить реликвию на землю (загрузка, стенды)
func place_on_ground(level: int, pos: Vector3) -> Dictionary:
	pos.y = 0.0
	return _new_relic(level, null, pos)

# ═════════════════════════════════════════════════════════════════════════════
# ТАКТЫ
# ═════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if relics.is_empty():
		if not _applied.is_empty():
			_apply_desired({})
		return
	_pick_t -= delta
	if _pick_t <= 0.0:
		_pick_t = _RCfg.PICK_TICK_SEC
		_tick_carriers()
	_aura_t -= delta
	if _aura_t <= 0.0:
		_aura_t = _RCfg.AURA_TICK_SEC
		_tick_aura()

## Носитель пал — реликвия на землю; лежащая — подбор первым наступившим
func _tick_carriers() -> void:
	if GameManager.unit_grid == null:
		return
	for r in relics:
		var d: Dictionary = r
		var c = d["carrier"]
		# ОСВОБОЖДЁННЫЙ ОБЪЕКТ В Variant РАВЕН null: «c != null» пропустил бы
		# павшего и уже освобождённого носителя как «лежит на земле», без
		# выпадения. Занятость слота — по типу, жизнь — is_instance_valid
		if typeof(c) == TYPE_OBJECT:
			# Правило 5: is_instance_valid на сырой ссылке до приведения
			if not is_instance_valid(c) or (c as Unit).is_dead():
				_drop(d)
			elif not (c as Unit).garrisoned:
				var p: Vector3 = (c as Unit).global_position
				p.y = 0.0
				d["pos"] = p
			continue
		var who: Unit = _picker_at(d["pos"])
		if who != null:
			d["carrier"] = who
			pickups += 1
			_refresh_visual(d)
			_aura_t = 0.0

func _drop(d: Dictionary) -> void:
	d["carrier"] = null
	drops += 1
	_refresh_visual(d)

## Ближайший живой боец любой фракции в PICK_RADIUS. Рабочие, овцы и
## безоружные реликвию не поднимают; уже несущий — тоже
func _picker_at(pos: Vector3) -> Unit:
	var rows: PackedInt32Array = GameManager.unit_grid.query_radius_rows(pos, _RCfg.PICK_RADIUS)
	if rows.is_empty():
		return null
	var reg: Array = GameManager._row_units
	var cap: int = reg.size()
	var best: Unit = null
	var bd := INF
	for row in rows:
		if row >= cap:
			continue
		var raw = reg[row]
		if raw == null or not is_instance_valid(raw):
			continue
		var u := raw as Unit
		if u == null or u.is_dead() or u.garrisoned or u.attack_damage <= 0.0:
			continue
		if u is Worker or relic_of_unit(u) != null:
			continue
		var p: Vector3 = u.global_position
		var dd: float = (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
		if dd < bd:
			bd = dd
			best = u
	return best

## ОДИН ПРОХОД ПО ВСЕМ РЕЛИКВИЯМ: кто в чьей ауре (лучшая по уровню), затем
## разница с уже розданным — выдать новым, снять ушедшим
func _tick_aura() -> void:
	aura_ticks += 1
	var desired: Dictionary = {}
	if GameManager.unit_grid == null:
		_apply_desired(desired)
		return
	var reg: Array = GameManager._row_units
	var cap: int = reg.size()
	var sq_seen: Dictionary = {}
	for r in relics:
		var d: Dictionary = r
		var c = d["carrier"]
		if c == null or not is_instance_valid(c) or (c as Unit).is_dead() \
				or (c as Unit).garrisoned:
			continue
		var cu := c as Unit
		var lvl: int = int(d["level"])
		var fac: int = cu.faction
		var rows: PackedInt32Array = GameManager.unit_grid.query_radius_rows(
			cu.global_position, _RCfg.aura_radius(lvl))
		for row in rows:
			if row >= cap:
				continue
			var raw = reg[row]
			if raw == null or not is_instance_valid(raw):
				continue
			var u := raw as Unit
			if u == null or u.is_dead() or u.faction != fac or u.attack_damage <= 0.0:
				continue
			var iid: int = u.get_instance_id()
			var cur: Variant = desired.get(iid)
			if cur == null or int((cur as Array)[1]) < lvl:
				desired[iid] = [u, lvl]
			if u.squad_id > 0:
				sq_seen[u.squad_id] = true
	_apply_desired(desired)
	var gain: float = _RCfg.AURA_SQUAD_MORALE_PER_SEC * _RCfg.AURA_TICK_SEC
	for sid in sq_seen:
		GameManager.squad_add_morale(int(sid), gain)

func _apply_desired(desired: Dictionary) -> void:
	for iid in _applied.keys():
		var a: Array = _applied[iid]
		var want: Variant = desired.get(iid)
		if want != null and int((want as Array)[1]) == int(a[4]):
			continue
		_unbuff(a)
		_applied.erase(iid)
	for iid2 in desired:
		if _applied.has(iid2):
			continue
		var w: Array = desired[iid2]
		_applied[iid2] = _buff(w[0], int(w[1]))

func _buff(u: Unit, lvl: int) -> Array:
	var atk: float = _RCfg.aura_attack(lvl)
	var cd0: float = u.attack_cooldown
	var cd1: float = maxf(cd0 * (1.0 - _RCfg.AURA_COOLDOWN_FRAC), _UCfgR.MIN_COOLDOWN)
	var dcd: float = maxf(cd0 - cd1, 0.0)
	u.vet_attack += atk
	u.attack_cooldown = cd0 - dcd
	u.morale += _RCfg.AURA_MORALE
	u._soa_push_stats()
	return [u, atk, dcd, _RCfg.AURA_MORALE, lvl]

func _unbuff(a: Array) -> void:
	var raw = a[0]
	if raw == null or not is_instance_valid(raw):
		return
	var u := raw as Unit
	if u.is_dead():
		return
	u.vet_attack -= float(a[1])
	u.attack_cooldown += float(a[2])
	u.morale -= float(a[3])
	u._soa_push_stats()

## Есть ли на бойце аура и какого уровня (0 — нет). Стендам и карточке
func aura_level_on(u: Node) -> int:
	if u == null:
		return 0
	var a: Variant = _applied.get(u.get_instance_id())
	return 0 if a == null else int((a as Array)[4])

# ═════════════════════════════════════════════════════════════════════════════
# КАРТИНКА: ЗОЛОТОЙ ШТАНДАРТ НАД НОСИТЕЛЕМ ИЛИ ВОТКНУТЫЙ В ЗЕМЛЮ
# ═════════════════════════════════════════════════════════════════════════════

static var _tex: Texture2D = null

static func relic_texture() -> Texture2D:
	if _tex == null:
		_tex = _BannerArtR._render({"shape": _UCfgR.BANNER_STANDARD,
			"cloth": _RCfg.CLOTH, "chevrons": 0, "chevron_dir": 1, "tip": true})
	return _tex

func _host() -> Node:
	var m = GameManager.main
	if m != null and is_instance_valid(m):
		return m
	var tree := get_tree()
	return tree.current_scene if tree != null else null

func _refresh_visual(d: Dictionary) -> void:
	var node = d["node"]
	if node == null or not is_instance_valid(node):
		var host := _host()
		if host == null:
			return
		node = _SquadBannerR.create(1)
		node.name = "RelicBanner"
		node.build_texture(relic_texture())
		host.add_child(node)
		var lab := Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.pixel_size = 0.008
		lab.font_size = 56
		lab.outline_size = 12
		lab.modulate = Color(1.0, 0.86, 0.3)
		lab.position = Vector3(0.0, 1.05, 0.0)
		node.add_child(lab)
		d["node"] = node
		d["label"] = lab
	var l = d["label"]
	if l != null and is_instance_valid(l):
		(l as Label3D).text = "★%d" % int(d["level"])

const _RelicButtonS := preload("res://scripts/RelicButton.gd")
var _ui: Node = null

func _process(_delta: float) -> void:
	# Кнопка копилки — в сцене партии (в меню и в стендах без Main её нет)
	if _ui == null or not is_instance_valid(_ui):
		var m = GameManager.main
		if m != null and is_instance_valid(m) and m.is_inside_tree():
			_ui = _RelicButtonS.create_layer()
			m.add_child(_ui)
	if relics.is_empty():
		return
	var fog = GameManager.fog
	for r in relics:
		var d: Dictionary = r
		var node = d["node"]
		if node == null or not is_instance_valid(node):
			_refresh_visual(d)
			node = d["node"]
			if node == null:
				continue
		var c = d["carrier"]
		if c != null and is_instance_valid(c) and not (c as Unit).is_dead():
			var u := c as Unit
			# Видна ровно тогда, когда виден носитель (та же логика, что у
			# знамени отряда: факт отрисовки плюс туман по логической точке)
			if u.garrisoned or not u.is_inside_tree() or not u.is_drawn():
				node.visible = false
				continue
			var gp: Vector3 = u.global_position
			node.visible = fog == null or not is_instance_valid(fog) or fog.is_lit(gp.x, gp.z)
			if node.visible:
				var p: Vector3 = u.draw_position()
				node.global_position = Vector3(p.x + _SquadBannerR.POLE_OFFSET_X,
					GameManager.get_terrain_height(p.x, p.z) + _RCfg.CARRY_Y, p.z)
			continue
		# На земле: игроку видна только освещённая (туман войны)
		var pos: Vector3 = d["pos"]
		node.visible = fog == null or not is_instance_valid(fog) or fog.is_lit(pos.x, pos.z)
		if node.visible:
			node.global_position = Vector3(pos.x + _SquadBannerR.POLE_OFFSET_X,
				GameManager.get_terrain_height(pos.x, pos.z) + _RCfg.GROUND_Y, pos.z)

# ═════════════════════════════════════════════════════════════════════════════
# СБРОС И СОХРАНЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════

func reset() -> void:
	_apply_desired({})
	for r in relics:
		var n = (r as Dictionary)["node"]
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	relics.clear()
	pool = 0.0
	if armed:
		arm(false)
	_next_id = 1
	grants = 0
	drops = 0
	pickups = 0
	pool_changed.emit(pool)

## Слепок: копилка и реликвии. Несомая записывается номером отряда носителя
## (squad, сопоставляется при загрузке через sid_map), лежащая — точкой
func capture() -> Dictionary:
	var list: Array = []
	for r in relics:
		var d: Dictionary = r
		var c = d["carrier"]
		var sid: int = 0
		if c != null and is_instance_valid(c) and not (c as Unit).is_dead():
			sid = (c as Unit).squad_id
		var p: Vector3 = d["pos"]
		list.append({"level": int(d["level"]), "squad": sid, "x": p.x, "z": p.z})
	return {"pool": pool, "list": list}

func restore(src: Dictionary, sid_map: Dictionary) -> void:
	reset()
	pool = float(src.get("pool", 0.0))
	for row in (src.get("list", []) as Array):
		var e: Dictionary = row
		var lvl: int = int(e.get("level", 1))
		var pos := Vector3(float(e.get("x", 0.0)), 0.0, float(e.get("z", 0.0)))
		var nsid: int = int(sid_map.get(int(e.get("squad", 0)), 0))
		var carrier: Unit = null
		if nsid > 0 and GameManager.squads.has(nsid):
			var alive: Array = _alive_members(nsid)
			if not alive.is_empty():
				carrier = _central_member(alive)
		_new_relic(lvl, carrier, pos)
	pool_changed.emit(pool)
