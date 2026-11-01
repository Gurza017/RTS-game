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
const _Opt := preload("res://scripts/perf_config.gd")

signal pool_changed(value: float)
signal armed_changed(on: bool)

## Копилка опыта армии игрока
var pool: float = 0.0
## Взведён ли режим выдачи (кнопка нажата один раз, ждём клика по отряду)
var armed: bool = false

## Реликвии: {"id", "level", "carrier": Unit|null, "pos": Vector3,
## "node": MeshInstance3D|null, "shown": уровень на картинке}. carrier == null —
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
var passes: int = 0
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
		# Свой светлый перезвон (ТЗ 24.10.2026, второе письмо): прежний
		# щелчок кузницы не отличался от клика по исследованию
		AudioManager.play_ui("banner_ready")

## ── КОПИЛКА КРАСНОГО ИИ (ТЗ 23.10.2026, п. 5) ──────────────────────────────
## Штандарт — награда за общий опыт армии и у ИИ: та же цена POOL_COST, тот же
## путь grant_to_squad; вручается самому заслуженному полевому отряду (больше
## всех убийств). Прежде бордовые штандарты у красных были от наград
## ветеранства (apply_veteran_choice), то есть у каждого опытного отряда
var ai_pool: float = 0.0
var ai_grants: int = 0

func add_ai_xp(n: float) -> void:
	if n <= 0.0:
		return
	ai_pool = minf(ai_pool + n * _RCfg.POOL_PER_KILL, _RCfg.POOL_COST * 3.0)
	if ai_pool < _RCfg.POOL_COST:
		return
	var best: int = -1
	var best_k: int = -1
	for key in GameManager.squads.keys():
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) != Constants.FACTION_ENEMY:
			continue
		var t: String = String(sq.get("type", ""))
		if t == "worker" or t == "monk":
			continue
		if _alive_members(int(key)).is_empty():
			continue
		if _Opt.standard_squad and standard_level(int(key)) >= _RCfg.STANDARD_MAX_LEVEL:
			continue
		var k: int = int(sq.get("kills", 0))
		if k > best_k:
			best_k = k
			best = int(key)
	if best < 0:
		return
	if grant_to_squad(best, true) >= 0:
		ai_pool -= _RCfg.POOL_COST
		ai_grants += 1

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
	if _Opt.standard_squad:
		return _grant_standard(sid, alive, force)
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

## ── ШТАНДАРТ ЗА ОБЩИЙ ОПЫТ — СВОЙСТВО ОТРЯДА (ТЗ 29.10.2026) ──────────────
## Было: выдача поднимала РАНГ ветеранства (grant_squad_level подтягивал
## убийства до порога), и пять кликов по накопленной копилке делали из
## новобранцев легенду; штандарт жил предметом носителя и пропадал с его
## гибелью (аура гасла, на повторной выдаче заводился второй, уровня 1).
## Теперь: личный опыт — убийства и ранг, общий — только штандарт. Первая
## выдача — штандарт уровня 1, дальше только улучшение до STANDARD_MAX_LEVEL;
## ранг и убийства отряда не трогаются. Уровень живёт в записи отряда
## (elite / elite_lvl), реликвия — носитель ауры, переходит к соседу
func _grant_standard(sid: int, alive: Array, force: bool) -> int:
	var cur: int = standard_level(sid)
	if cur >= _RCfg.STANDARD_MAX_LEVEL:
		return -1
	if not force:
		pool -= _RCfg.POOL_COST
		pool_changed.emit(pool)
	var lvl: int = cur + 1
	var sq: Dictionary = GameManager.squads[sid]
	sq["elite"] = true
	sq["elite_lvl"] = lvl
	var r: Variant = relic_of_squad(sid)
	if r != null:
		(r as Dictionary)["level"] = lvl
		_refresh_visual(r)
	else:
		r = _new_relic(lvl, _central_member(alive), Vector3.ZERO)
	GameManager.refresh_squad_banner(sid)
	grants += 1
	_aura_t = 0.0
	GameManager.tm_event("standard_grant", {"sid": sid, "lvl": lvl,
		"fac": int(sq.get("faction", 0))})
	return int((r as Dictionary)["id"])

## Уровень штандарта отряда (0 — нет): реликвия у живого бойца или запись
func standard_level(sid: int) -> int:
	var r: Variant = relic_of_squad(sid)
	if r != null:
		return int((r as Dictionary)["level"])
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null or not bool((sq as Dictionary).get("elite", false)):
		return 0
	return maxi(1, int((sq as Dictionary).get("elite_lvl", 1)))

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
		"pos": p0, "node": null, "shown": 0}
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
				# ТЗ 29.10.2026: штандарт — свойство отряда; на землю — только
				# когда в отряде не осталось ни одного живого бойца
				var heir: Unit = _heir_of(d) if _Opt.standard_squad else null
				if heir != null:
					d["carrier"] = heir
					passes += 1
					GameManager.probes.note_standard("pass", int(d.get("bsid", 0)), int(d["level"]), heir)
					_refresh_visual(d)
					_aura_t = 0.0
				else:
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
			GameManager.probes.note_standard("pickup", who.squad_id, int(d["level"]), who)
			_refresh_visual(d)
			_aura_t = 0.0

## Наследник штандарта — центральный живой боец отряда прежнего носителя
## (отряд — из записи bsid: павший носитель мог быть уже освобождён)
func _heir_of(d: Dictionary) -> Unit:
	var sid: int = int(d.get("bsid", 0))
	if sid <= 0 or not GameManager.squads.has(sid):
		return null
	var alive: Array = _alive_members(sid)
	if alive.is_empty():
		return null
	return _central_member(alive)

## Есть ли у отряда штандарт (своя реликвия или запись) — второй не подбирает
func _squad_has_standard(sid: int) -> bool:
	return sid > 0 and standard_level(sid) > 0

func _drop(d: Dictionary) -> void:
	d["carrier"] = null
	drops += 1
	GameManager.probes.note_standard("drop", int(d.get("bsid", 0)), int(d["level"]), null)
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
		# Один штандарт на отряд (ТЗ 29.10.2026): отряд со своим упавший не берёт
		if _Opt.standard_squad and _squad_has_standard(u.squad_id):
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
			# Под аурой подавления свинобосса бонуса штандарта нет (ТЗ 28.10.2026)
			if u._suppressed_until_ms > Unit.now_ms:
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
# КАРТИНКА: БОРДОВЫЙ ШТАНДАРТ ЭЛИТЫ (ТЗ 22.10.2026, блок 1)
# ═════════════════════════════════════════════════════════════════════════════
## Золотой штандарт с подписью «★N» над носителем СНЯТ: жёлтых флагов на
## карте нет. Реликвия делает отряд элитой (GameManager.grant_squad_level →
## признак "elite"), и знамя САМОГО отряда превращается в бордовый штандарт
## с римской цифрой — один отряд, один флагшток. Свой узел реликвия
## показывает только там, где знамени отряда нет: лежит на земле или её
## несёт боец, чей отряд не элита (подобрал враг)

static func relic_texture() -> Texture2D:
	return _BannerArtR.elite_texture(1, 0)

func _host() -> Node:
	var m = GameManager.main
	if m != null and is_instance_valid(m):
		return m
	var tree := get_tree()
	return tree.current_scene if tree != null else null

func _refresh_visual(d: Dictionary) -> void:
	_touch_banners(d)
	var node = d["node"]
	if node == null or not is_instance_valid(node):
		var host := _host()
		if host == null:
			return
		node = _SquadBannerR.create(1)
		node.name = "RelicBanner"
		host.add_child(node)
		d["node"] = node
		d["shown"] = 0
	# Картинка — штандарт элиты с римской цифрой уровня реликвии
	if int(d.get("shown", 0)) != int(d["level"]):
		d["shown"] = int(d["level"])
		node.build_texture(_BannerArtR.elite_texture(int(d["level"]), 0),
			_SquadBannerR.ELITE_SCALE, _BannerArtR.elite_pole_offset_px() * _SquadBannerR.PIXEL_SIZE)

## ── ЗНАМЯ ОТРЯДА-НОСИТЕЛЯ ПЕРЕСТРАИВАЕТСЯ ПО СОБЫТИЮ РЕЛИКВИИ ─────────────
## Реликвия срастается со знаменем отряда (GameManager.refresh_squad_banner):
## подбор, выпадение и рост уровня меняют картинку И прежнего отряда-носителя
## (вернуть вымпел), И нового (штандарт). Отряд прошлого носителя помним в
## записи: на выпадении носитель уже мёртв и мог быть освобождён
func _touch_banners(d: Dictionary) -> void:
	var c = d["carrier"]
	var sid: int = 0
	if typeof(c) == TYPE_OBJECT and is_instance_valid(c) and not (c as Unit).is_dead():
		sid = (c as Unit).squad_id
	var was: int = int(d.get("bsid", 0))
	d["bsid"] = sid
	if was > 0 and was != sid:
		GameManager.refresh_squad_banner(was)
	if sid > 0:
		GameManager.refresh_squad_banner(sid)

## Знамя отряда носителя уже несёт реликвию на полотнище — своего узла не
## ставим (один отряд — один флагшток)
func _merged_into_banner(u: Unit) -> bool:
	if not _Opt.relic_merge_banner or u.squad_id <= 0:
		return false
	var sq: Variant = GameManager.squads.get(u.squad_id)
	if sq == null:
		return false
	var b = (sq as Dictionary).get("banner")
	return b != null and is_instance_valid(b)

const _RelicButtonS := preload("res://scripts/RelicButton.gd")
var _ui: Node = null

## ПОСЛЕ ВИЗУАЛЬНОГО ПРОХОДА АРМИИ (GameManager.process_priority = 1000):
## значки и круги ауры берут нарисованную точку бойца того же кадра, а не
## прошлого (ТЗ 27.10.2026, третье письмо, п. 1)
func _ready() -> void:
	process_priority = 1001

func _process(_delta: float) -> void:
	# Кнопка копилки — в сцене партии (в меню и в стендах без Main её нет)
	if _ui == null or not is_instance_valid(_ui):
		var m = GameManager.main
		if m != null and is_instance_valid(m) and m.is_inside_tree():
			_ui = _RelicButtonS.create_layer()
			m.add_child(_ui)
	_aura_view_tick(_delta)
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
			# Отряд носителя — элита: его знамя уже бордовый штандарт, второй
			# флагшток над тем же отрядом не ставится
			if GameManager.squad_elite(u.squad_id) or _merged_into_banner(u):
				node.visible = false
				continue
			# Видна ровно тогда, когда виден носитель (та же логика, что у
			# знамени отряда: факт отрисовки плюс туман по логической точке)
			if u.garrisoned or not u.is_inside_tree() or not u.is_drawn():
				node.visible = false
				continue
			var gp: Vector3 = u.global_position
			node.visible = fog == null or not is_instance_valid(fog) or fog.is_lit(gp.x, gp.z)
			if node.visible:
				var p: Vector3 = u.draw_position()
				node.global_position = Vector3(p.x + float(node.get("pole_offset")),
					GameManager.get_terrain_height(p.x, p.z) + _RCfg.CARRY_Y, p.z)
			continue
		# На земле: игроку видна только освещённая (туман войны)
		var pos: Vector3 = d["pos"]
		node.visible = fog == null or not is_instance_valid(fog) or fog.is_lit(pos.x, pos.z)
		if node.visible:
			node.global_position = Vector3(pos.x + float(node.get("pole_offset")),
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

# ═════════════════════════════════════════════════════════════════════════════
# РАДИУС АУРЫ ПО ВЫДЕЛЕНИЮ (ТЗ 23.10.2026, п. 5)
#
# Выделен отряд со штандартом — у носителя тонкий прозрачный зелёный круг
# радиуса ауры, над каждым своим отрядом в круге — зелёный значок «+».
# Раз в AURA_VIEW_SEC, узлы переиспользуются; нет выделенного носителя —
# всё спрятано. Кто в круге — тем же правилом центра отряда, что видит игрок
# ═════════════════════════════════════════════════════════════════════════════
const AURA_VIEW_SEC := 0.15
const AURA_RING_COLOR := Color(0.25, 0.95, 0.35, 0.38)
const AURA_ICON_COLOR := Color(0.35, 1.0, 0.40, 1.0)
var _view_t: float = 0.0
var _rings: Array = []
var _icons: Array = []
var aura_view_rings: int = 0      # стендам: сколько кругов показано сейчас
var aura_view_icons: int = 0      # стендам: сколько значков показано сейчас
var _ring_mat: StandardMaterial3D = null
## ── ЗНАЧКИ И КРУГИ ИДУТ ЗА НАРИСОВАННЫМ БОЙЦОМ (ТЗ 27.10.2026, третье
## письмо, п. 1; ручка perf_config.aura_follow_draw) ─────────────────────────
## Состав «кто в круге» по-прежнему решается раз в AURA_VIEW_SEC, а ПОЛОЖЕНИЕ
## значка и круга — каждый кадр: значок привязан к бойцу-якорю (ближайший к
## центру отряда) со смещением центра от него, круг — к носителю, и оба берут
## НАРИСОВАННУЮ точку (Unit.draw_position — её сглаживает ядро). Прежде
## значок стоял на логическом центре и прыгал раз в 0.15 с, а логическая
## точка бойца обгоняет картинку — «плюсики дёргаются» на марше
var _icon_anchor: Array = []      # Unit-якорь значка k (сырая ссылка)
var _icon_off: Array = []         # смещение значка от якоря (Vector3)
var _ring_anchor: Array = []      # носитель круга i (сырая ссылка)

func _aura_view_tick(delta: float) -> void:
	_view_t -= delta
	if _view_t <= 0.0:
		_view_t = AURA_VIEW_SEC
		_update_aura_view()
	if _Opt.aura_follow_draw:
		_follow_aura_view()

## Каждый кадр: значки и круги — к нарисованной точке якоря. Узлов единицы,
## переходов в ядро — по одному на значок
func _follow_aura_view() -> void:
	for k in range(mini(aura_view_icons, _icons.size())):
		if k >= _icon_anchor.size():
			break
		var a = _icon_anchor[k]
		var lab = _icons[k]
		# Правило 5: живость на сырой ссылке
		if a == null or not is_instance_valid(a) or lab == null or not is_instance_valid(lab):
			continue
		if (a as Unit).is_dead():
			continue
		(lab as Label3D).global_position = (a as Unit).draw_position() + (_icon_off[k] as Vector3)
	for i in range(mini(aura_view_rings, _rings.size())):
		if i >= _ring_anchor.size():
			break
		var c = _ring_anchor[i]
		var ring = _rings[i]
		if c == null or not is_instance_valid(c) or ring == null or not is_instance_valid(ring):
			continue
		if (c as Unit).is_dead():
			continue
		var dp: Vector3 = (c as Unit).draw_position()
		(ring as MeshInstance3D).global_position = Vector3(dp.x, GameManager.get_terrain_height(dp.x, dp.z) + 0.12, dp.z)

## Боец отряда, ближайший к его центру (якорь значка)
static func _anchor_of(alive: Array, cen: Vector3) -> Unit:
	var best: Unit = null
	var bd := INF
	for m in alive:
		var u := m as Unit
		var p: Vector3 = u.global_position
		var d: float = (p.x - cen.x) * (p.x - cen.x) + (p.z - cen.z) * (p.z - cen.z)
		if d < bd:
			bd = d
			best = u
	return best

func _selected_sids() -> Dictionary:
	var out: Dictionary = {}
	var m = GameManager.main
	if m == null or not is_instance_valid(m):
		return out
	var sm = m.get("selection_manager")
	if sm == null or not is_instance_valid(sm):
		return out
	for u in sm.selected_units:
		if u != null and is_instance_valid(u) and u is Unit and (u as Unit).squad_id > 0:
			out[(u as Unit).squad_id] = true
	return out

func _update_aura_view() -> void:
	# Узлы живут на сцене партии: после «Заново» прежние освобождены
	_rings = _rings.filter(func(n): return n != null and is_instance_valid(n))
	_icons = _icons.filter(func(n): return n != null and is_instance_valid(n))
	var sel: Dictionary = _selected_sids()
	var shown := 0
	var marked: Dictionary = {}
	for r in relics:
		var d: Dictionary = r
		var c = d["carrier"]
		if c == null or not is_instance_valid(c) or (c as Unit).is_dead():
			continue
		var cu := c as Unit
		if not sel.has(cu.squad_id):
			continue
		var rad: float = _RCfg.aura_radius(int(d["level"]))
		var ring: MeshInstance3D = _ring_node(shown)
		var p: Vector3 = cu.global_position
		var rp: Vector3 = cu.draw_position() if _Opt.aura_follow_draw else p
		ring.global_position = Vector3(rp.x, GameManager.get_terrain_height(rp.x, rp.z) + 0.12, rp.z)
		ring.scale = Vector3(rad, 1.0, rad)
		ring.visible = true
		if _ring_anchor.size() <= shown:
			_ring_anchor.resize(shown + 1)
		_ring_anchor[shown] = cu
		shown += 1
		# Свои отряды, чей центр в круге, — получают бонус
		for key in GameManager.squads.keys():
			var sq: Dictionary = GameManager.squads[key]
			if int(sq.get("faction", -1)) != cu.faction or marked.has(int(key)):
				continue
			var alive: Array = _alive_members(int(key))
			if alive.is_empty():
				continue
			var cen: Vector3 = GameManager._centroid_of(alive)
			if Vector2(cen.x - p.x, cen.z - p.z).length() <= rad:
				var anc: Unit = _anchor_of(alive, cen)
				marked[int(key)] = [cen, anc, cen - anc.global_position]
	for i in range(shown, _rings.size()):
		(_rings[i] as MeshInstance3D).visible = false
	var k := 0
	for sid in marked:
		var lab: Label3D = _icon_node(k)
		var rec: Array = marked[sid]
		var lift := Vector3(0.0, 3.4, 0.0)
		if _icon_anchor.size() <= k:
			_icon_anchor.resize(k + 1)
			_icon_off.resize(k + 1)
		_icon_anchor[k] = rec[1]
		_icon_off[k] = (rec[2] as Vector3) + lift
		if _Opt.aura_follow_draw:
			lab.global_position = (rec[1] as Unit).draw_position() + (rec[2] as Vector3) + lift
		else:
			lab.global_position = (rec[0] as Vector3) + lift
		lab.visible = true
		k += 1
	for j in range(k, _icons.size()):
		(_icons[j] as Label3D).visible = false
	aura_view_rings = shown
	aura_view_icons = k
	_update_tower_range_view()

# ── РАДИУС ОБСТРЕЛА ВЫДЕЛЕННОЙ БАШНИ (ТЗ 24.10.2026, второе письмо, блок 4) ──
# Тот же приём, что у ауры штандарта: тонкий прозрачный круг на земле, раз в
# AURA_VIEW_SEC, узлы переиспользуются. Цвет — тёплый янтарный, чтобы не
# спутать с зелёной аурой. Радиус — Tower.fire_range() (лучники внутри ×
# бафф высоты); пустая башня — та дальность, которую дал бы штатный отряд
# лучников, и круг бледнее: «вот сколько она будет бить с гарнизоном»
## ТЗ 29.10.2026, п. 2: башня со стрелками — ЗЕЛЁНОЕ кольцо точной дальности
## огня гарнизона; пустая — СИНЕЕ кольцо обзора (радиус тумана башни)
const TOWER_RING_COLOR := Color(0.32, 0.92, 0.38, 0.55)
const TOWER_RING_EMPTY := Color(0.38, 0.62, 1.00, 0.45)
var _trings: Array = []
var _tring_mat: StandardMaterial3D = null
var _tring_mat_empty: StandardMaterial3D = null
var tower_view_rings: int = 0     # стендам

func _selected_towers() -> Array:
	var out: Array = []
	var m = GameManager.main
	if m == null or not is_instance_valid(m):
		return out
	var sm = m.get("selection_manager")
	if sm == null or not is_instance_valid(sm):
		return out
	for u in sm.selected_units:
		if u != null and is_instance_valid(u) and u is Building \
				and String((u as Building).building_id) == "tower" and not (u as Building).is_dead() \
				and (u as Building).has_method("fire_range"):
			out.append(u)
	return out

func _update_tower_range_view() -> void:
	_trings = _trings.filter(func(n): return n != null and is_instance_valid(n))
	var shown := 0
	for t in _selected_towers():
		var b := t as Building
		var rad: float = float(b.call("fire_range"))
		var empty: bool = rad <= 0.0
		if empty:
			rad = float(b.vision_radius()) if b.has_method("vision_radius") \
				else float(_UCfgR.STATS["archer"].get("attack_range", 15.0)) * _UCfgR.GARRISON_RANGE_MULT
		var ring: MeshInstance3D = _tower_ring_node(shown)
		ring.material_override = _tring_mat_empty if empty else _tring_mat
		var p: Vector3 = b.global_position
		ring.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z) + 0.12, p.z)
		ring.scale = Vector3(rad, 1.0, rad)
		ring.visible = true
		shown += 1
	for i in range(shown, _trings.size()):
		(_trings[i] as MeshInstance3D).visible = false
	tower_view_rings = shown

## ── КРУГ НЕ РЕЖЕТСЯ ХОЛМОМ (ТЗ 27.10.2026, третье письмо, п. 2; ручка
## perf_config.aura_ring_no_depth) ───────────────────────────────────────────
## Круг — плоский тор на высоте рельефа в центре: на склоне его половина
## уходила под грунт и пропадала дугами. Без теста глубины он рисуется
## целиком поверх земли (и поверх бойцов — круг тонкий и прозрачный, а
## render_priority держит его над прочей прозрачностью)
func _ring_off_terrain(mat: StandardMaterial3D) -> void:
	if not _Opt.aura_ring_no_depth:
		return
	mat.no_depth_test = true
	mat.render_priority = 10

func _tower_ring_node(i: int) -> MeshInstance3D:
	if _tring_mat == null:
		for pair in [[TOWER_RING_COLOR, "full"], [TOWER_RING_EMPTY, "empty"]]:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = pair[0]
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_ring_off_terrain(mat)
			if pair[1] == "full":
				_tring_mat = mat
			else:
				_tring_mat_empty = mat
	while _trings.size() <= i:
		var host := _host()
		if host == null:
			return MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.990
		tm.outer_radius = 1.0
		tm.rings = 128
		tm.ring_segments = 3
		var mi := MeshInstance3D.new()
		mi.name = "TowerRangeRing"
		mi.mesh = tm
		mi.material_override = _tring_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mi)
		_trings.append(mi)
	return _trings[i]

func _ring_node(i: int) -> MeshInstance3D:
	while _rings.size() <= i:
		var host := _host()
		if host == null:
			return MeshInstance3D.new()
		if _ring_mat == null:
			_ring_mat = StandardMaterial3D.new()
			_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_ring_mat.albedo_color = AURA_RING_COLOR
			_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_ring_off_terrain(_ring_mat)
		# Кольцо единичного радиуса, толщина 0.18 м при радиусе 15 — масштаб
		# по XZ растягивает его до радиуса ауры
		var tm := TorusMesh.new()
		tm.inner_radius = 0.988
		tm.outer_radius = 1.0
		tm.rings = 96
		tm.ring_segments = 3
		var mi := MeshInstance3D.new()
		mi.name = "RelicAuraRing"
		mi.mesh = tm
		mi.material_override = _ring_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mi)
		_rings.append(mi)
	return _rings[i]

func _icon_node(i: int) -> Label3D:
	while _icons.size() <= i:
		var host := _host()
		var lab := Label3D.new()
		lab.name = "RelicAuraIcon"
		lab.text = "+"
		lab.font_size = 64
		lab.outline_size = 12
		lab.modulate = AURA_ICON_COLOR
		lab.outline_modulate = Color(0.05, 0.25, 0.05, 1.0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.fixed_size = true
		lab.pixel_size = 0.0012
		if host != null:
			host.add_child(lab)
		_icons.append(lab)
	return _icons[i]
