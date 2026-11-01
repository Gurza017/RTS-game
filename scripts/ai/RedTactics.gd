extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ТАКТИКА КРАСНОГО ИИ (ТЗ 30.10.2026) — четыре механизма поверх EnemyAI
## ═══════════════════════════════════════════════════════════════════════════
## Скриншоты 27.10 и 30.10: красные копейщики после стычки бродят толпой.
## Причина — в EnemyAI._issue_plan: при угрозе каждый боец получает
## command_attack, строй распадается, а после боя отряд возвращается на
## пост поштучно (_hold_at) из той точки, где кого застал, — и сразу
## получает новую цель. Строя между двумя боями не бывает вовсе.
##
##   1. ПЕРЕГРУППИРОВКА ПОСЛЕ БОЯ (ручка ai_regroup). Отряды поля
##      кластеризуются по близости (RG_CLUSTER_R). Кластер дрался недавно
##      (RG_RECENT_SEC), уже RG_QUIET_SEC тихо и врага нет в RG_SCAN_R —
##      глобальный конец боя: всем отрядам кластера — место в «кирпичах» у
##      медианы (пехота рядами по 2-4 отряда, лучники за ней), стойка Защита,
##      лицом к месту боя. Пока кластер собирается, план ИИ его не двигает
##      (EnemyAI._apply_orders подменяет точку и курс); встали все или вышел
##      RG_MAX_SEC — приказы снимаются, и следующий такт выдаёт новые цели.
##      Появился враг — сбор отменяется, отряд дерётся.
##   2. КОРПУС ПО СИГНАЛУ (ai_corps). Патруль/рейд/рудничный отряд вступил в
##      бой в CORPS_MIN_DIST..CORPS_REACH от рубежа — заслон снимается с
##      линии и встаёт кирпичами 2×N в CORPS_STANDOFF перед стычкой (лучники
##      сзади) на CORPS_HOLD_SEC и ДЕРЖИТ место: с поста срывается только на
##      врага ближе CORPS_ENGAGE_R, а не в DEFENSE_ENGAGE_RADIUS.
##   3. КЛЕЩИ ШТУРМА (ai_pincer). Волна от PINCER_MIN отрядов: по
##      PINCER_SHARE на каждое крыло (рыцари первыми, затем крайние пехотные);
##      крыло бегом уходит за край чужого фронта, потом бьёт в тыл; центр — по
##      прежнему плану фронтом.
##   4. ОПОРНАЯ ТОЧКА (ai_strongpoint). Группа брода или рудничный отряд
##      простояли у цели SP_HOLD_SEC — у точки закладывается вышка, на неё
##      садятся лучники группы.
## Всё считается в такте ИИ раз в 2 с по уже собранным центрам отрядов —
## покадровой работы модуль не добавляет.

const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

const F := Constants.FACTION_ENEMY

var ai = null                      # EnemyAI

## Стенды и телеметрия
var regroups: int = 0              # сколько раз кластер пошёл на сбор
var regroup_squads: int = 0        # отрядов, получивших место сбора
var regroups_done: int = 0         # сборов, завершённых построением
var regroups_timeout: int = 0      # сборов, снятых по сроку
var regroups_broken: int = 0       # отрядов, сорванных врагом со сбора
var corps_signals: int = 0
var pincer_wings: int = 0
var sp_towers: int = 0
var sp_garrisons: int = 0

var _rg_seq: int = 0
## Сигнал корпусу: точка стычки и срок
var _corps_p: Vector3 = Vector3.INF
var _corps_until: float = -1.0
## Опорные точки: ключ (Vector2i ячейки 8 м) → с какого времени группа стоит
var _sp_since: Dictionary = {}

func reset() -> void:
	regroups = 0
	regroup_squads = 0
	regroups_done = 0
	regroups_timeout = 0
	regroups_broken = 0
	corps_signals = 0
	pincer_wings = 0
	sp_towers = 0
	sp_garrisons = 0
	_rg_seq = 0
	_corps_p = Vector3.INF
	_corps_until = -1.0
	_sp_since.clear()

static func _is_ranged(uid: String) -> bool:
	return uid == "archer"

# ═════════════════════════════════════════════════════════════════════════════
# ТАКТ (до раздачи ролей)
# ═════════════════════════════════════════════════════════════════════════════
func tick() -> void:
	if not (_Opt.ai_regroup or _Opt.ai_corps):
		return
	var now: float = ai.clock
	# Отметка боя: отряд в рукопашной или хоть один боец с живой целью-бойцом
	for s in ai.squads:
		var sq: Dictionary = s
		var role: String = String(sq["role"])
		if role == ai.ROLE_RETREAT:
			continue
		var members: Array = sq["members"]
		if members.is_empty():
			continue
		if _fighting(sq):
			sq["fight_t"] = now
			var c: Vector3 = ai._squad_centroid(members)
			if c != Vector3.ZERO:
				sq["fight_p"] = c
			if _Opt.ai_corps and role in [ai.ROLE_PATROL, ai.ROLE_RAID, ai.ROLE_MINE, ai.ROLE_FIELD] \
					and not bool(sq.get("corps", false)) and c != Vector3.ZERO \
					and ai._nearest_player_target(c, _AICfg.CONTACT_RADIUS) != null:
				_signal(c)
	if _Opt.ai_regroup:
		_tick_regroup(now)

## Дерётся ли отряд: рукопашная по ядру или боец с живой целью рядом
func _fighting(sq: Dictionary) -> bool:
	if ai._in_melee(sq):
		return true
	var n := 0
	for m in sq["members"]:
		if not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		var t = u.attack_target
		if t != null and is_instance_valid(t) and t is Unit and not (t as Unit).is_dead():
			n += 1
			if n >= 2:
				return true
	return false

# ═════════════════════════════════════════════════════════════════════════════
# 1. ПЕРЕГРУППИРОВКА ПОСЛЕ БОЯ
# ═════════════════════════════════════════════════════════════════════════════
## Отряд собирается — EnemyAI._apply_orders держит его на месте сбора
func regrouping(sq: Dictionary) -> bool:
	return _Opt.ai_regroup and int(sq.get("rg_id", 0)) > 0

## Враг рядом — сбор этому отряду снимается, он дерётся
func break_regroup(sq: Dictionary) -> void:
	if int(sq.get("rg_id", 0)) > 0:
		regroups_broken += 1
		_clear_rg(sq)

func _clear_rg(sq: Dictionary) -> void:
	sq.erase("rg_id")
	sq.erase("rg_post")
	sq.erase("rg_face")
	sq.erase("rg_until")
	sq["issued"] = false           # следующий такт — новый анализ целей

## Роли, которые собираются: всё поле. Гарнизон замка (GUARD) стоит на постах,
## отходящий уходит в замок, разведчик бежит своей дорогой
func _regroup_role(sq: Dictionary) -> bool:
	var role: String = String(sq["role"])
	if role == ai.ROLE_GUARD or role == ai.ROLE_RETREAT:
		return false
	if role == ai.ROLE_RAID and bool(sq.get("recon", false)):
		return false
	return true

func _tick_regroup(now: float) -> void:
	# Идущие сборы: завершить или снять по сроку
	var groups: Dictionary = {}
	for s in ai.squads:
		var sq: Dictionary = s
		var gid: int = int(sq.get("rg_id", 0))
		if gid <= 0:
			continue
		if (sq["members"] as Array).is_empty() or String(sq["role"]) == ai.ROLE_RETREAT:
			_clear_rg(sq)
			continue
		if not groups.has(gid):
			groups[gid] = []
		(groups[gid] as Array).append(sq)
	for gid2 in groups:
		var lst: Array = groups[gid2]
		var all_in := true
		var late := false
		for sq2 in lst:
			if now >= float((sq2 as Dictionary)["rg_until"]):
				late = true
			if not _settled(sq2):
				all_in = false
		if all_in or late:
			if all_in:
				regroups_done += 1
			else:
				regroups_timeout += 1
			for sq3 in lst:
				_clear_rg(sq3)
	# Новые сборы: кластеры отрядов поля по близости центров
	var pool: Array = []
	for s4 in ai.squads:
		var sq4: Dictionary = s4
		if int(sq4.get("rg_id", 0)) > 0 or not _regroup_role(sq4):
			continue
		var members: Array = sq4["members"]
		if members.is_empty():
			continue
		var c: Vector3 = ai._squad_centroid(members)
		if c == Vector3.ZERO:
			continue
		pool.append([sq4, c])
	var r2: float = _AICfg.RG_CLUSTER_R * _AICfg.RG_CLUSTER_R
	var used: Dictionary = {}
	for i in range(pool.size()):
		if used.has(i):
			continue
		var cl: Array = [pool[i]]
		used[i] = true
		# Жадное наращивание: соседи соседей тоже в кластере
		var k := 0
		while k < cl.size():
			var ck: Vector3 = cl[k][1]
			for j in range(pool.size()):
				if used.has(j):
					continue
				var cj: Vector3 = pool[j][1]
				if Vector2(cj.x - ck.x, cj.z - ck.z).length_squared() <= r2:
					used[j] = true
					cl.append(pool[j])
			k += 1
		_maybe_regroup(cl, now)

## Кластер дрался и бой кончился — раздать места сбора
func _maybe_regroup(cl: Array, now: float) -> void:
	var last_fight: float = -1.0e9
	var fight_p: Vector3 = Vector3.INF
	for e in cl:
		var sq: Dictionary = e[0]
		var ft: float = float(sq.get("fight_t", -1.0e9))
		if ft > last_fight:
			last_fight = ft
			fight_p = sq.get("fight_p", Vector3.INF)
	if now - last_fight > _AICfg.RG_RECENT_SEC or now - last_fight < _AICfg.RG_QUIET_SEC:
		return
	# Этот бой кластер уже отработал
	var fresh := false
	for e2 in cl:
		if float((e2[0] as Dictionary).get("rg_fight", -1.0e9)) < last_fight:
			fresh = true
	if not fresh:
		return
	var xs: Array = []
	var zs: Array = []
	for e3 in cl:
		xs.append((e3[1] as Vector3).x)
		zs.append((e3[1] as Vector3).z)
	xs.sort()
	zs.sort()
	var anchor := Vector3(float(xs[xs.size() / 2]), 0.0, float(zs[zs.size() / 2]))
	# Враг ещё рядом — бой не кончился
	if GameManager.army != null and GameManager.army.enemy_count(anchor.x, anchor.z, _AICfg.RG_SCAN_R, F) > 0:
		return
	# Лицом — к месту боя; оно под ногами — к базе игрока
	var face := Vector3.ZERO
	if fight_p.x != INF:
		face = Vector3(fight_p.x - anchor.x, 0.0, fight_p.z - anchor.z)
	if face.length() < 3.0:
		var base: Vector3 = ai._player_base_pos()
		face = Vector3(base.x - anchor.x, 0.0, base.z - anchor.z)
	face = Vector3.FORWARD if face.length() < 0.01 else face.normalized()
	var sqs: Array = []
	for e4 in cl:
		sqs.append(e4[0])
		(e4[0] as Dictionary)["rg_fight"] = last_fight
	var posts: Array = brick_layout(sqs, anchor, face)
	_rg_seq += 1
	for n in range(sqs.size()):
		var sq5: Dictionary = sqs[n]
		sq5["rg_id"] = _rg_seq
		sq5["rg_post"] = GameManager.land_target(posts[n])
		sq5["rg_face"] = face
		sq5["rg_until"] = now + _AICfg.RG_MAX_SEC
		sq5["issued"] = false
		regroup_squads += 1
	regroups += 1
	ai.last_action += "|сбор после боя: %d отр." % sqs.size()

## Отряд стоит на месте сбора
func _settled(sq: Dictionary) -> bool:
	var members: Array = sq["members"]
	var c: Vector3 = ai._squad_centroid(members)
	if c == Vector3.ZERO:
		return true
	var post: Vector3 = sq["rg_post"]
	if Vector2(c.x - post.x, c.z - post.z).length() > _AICfg.RG_ARRIVE_M:
		return false
	var live := 0
	var idle := 0
	for m in members:
		if not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		live += 1
		if u.state == Unit.State.IDLE:
			idle += 1
	return live == 0 or float(idle) >= float(live) * _AICfg.RG_IDLE_FRAC

## ── КИРПИЧИ: пехота рядами по cols отрядов, лучники рядами за ней ─────────
## Ширина колонки — по самому широкому роду в ряду (шаг заслона), глубина ряда —
## по числу шеренг отряда + RG_ROW_GAP. Отряды ряда — по их боковой координате,
## чтобы при сборе никто не шёл крест-накрест
func brick_layout(sqs: Array, anchor: Vector3, face: Vector3) -> Array:
	var right := Vector3(-face.z, 0.0, face.x)
	var melee: Array = []
	var bows: Array = []
	for i in range(sqs.size()):
		if _is_ranged(String((sqs[i] as Dictionary)["type"])):
			bows.append(i)
		else:
			melee.append(i)
	var cols: int = 2 if melee.size() <= 4 else (3 if melee.size() <= 9 else 4)
	var out: Array = []
	out.resize(sqs.size())
	var step: float = ai._widest_step()
	# Боковая координата отряда сейчас — для порядка в ряду
	var lat: Dictionary = {}
	for i2 in range(sqs.size()):
		var c: Vector3 = ai._squad_centroid((sqs[i2] as Dictionary)["members"])
		lat[i2] = (c.x - anchor.x) * right.x + (c.z - anchor.z) * right.z
	var depth_back := 0.0
	for group in [melee, bows]:
		var g: Array = group
		var gc: int = cols if g == melee else maxi(2, mini(cols, g.size()))
		var r := 0
		while r * gc < g.size():
			var row: Array = g.slice(r * gc, mini((r + 1) * gc, g.size()))
			row.sort_custom(func(a, b): return float(lat[a]) < float(lat[b]))
			var row_depth := 0.0
			for k in range(row.size()):
				var idx: int = row[k]
				var sq: Dictionary = sqs[idx]
				var nmen: int = maxi((sq["members"] as Array).size(), 1)
				var ccols: int = ai._squad_cols(String(sq["type"]), nmen)
				var rows: int = int(ceil(float(nmen) / float(maxi(ccols, 1))))
				row_depth = maxf(row_depth, float(rows) * ai.SQUAD_SPACING)
				var centered: float = float(k) - float(row.size() - 1) * 0.5
				out[idx] = anchor + right * (centered * step) - face * depth_back
			depth_back += row_depth + _AICfg.RG_ROW_GAP
			r += 1
	# Весь блок сдвинуть так, чтобы его середина по глубине была на медиане
	var shift: Vector3 = face * (maxf(depth_back - _AICfg.RG_ROW_GAP, 0.0) * 0.5)
	for n in range(out.size()):
		out[n] = (out[n] as Vector3) + shift
	return out

# ═════════════════════════════════════════════════════════════════════════════
# 2. КОРПУС ПО СИГНАЛУ
# ═════════════════════════════════════════════════════════════════════════════
func _signal(p: Vector3) -> void:
	var c: Vector3 = ai._defense_center(ai._find_castle()) if ai._find_castle() != null else Vector3.INF
	if c.x == INF:
		return
	var d: float = Vector2(p.x - c.x, p.z - c.z).length()
	if d < _AICfg.CORPS_MIN_DIST or d > _AICfg.CORPS_REACH:
		return
	if ai.clock >= _corps_until or _corps_p.x == INF or _corps_p.distance_to(p) > 15.0:
		corps_signals += 1
		ai.last_action += "|сигнал корпусу: стычка в %.0f м" % d
	_corps_p = p
	_corps_until = ai.clock + _AICfg.CORPS_HOLD_SEC

func corps_active() -> bool:
	return _Opt.ai_corps and _corps_p.x != INF and ai.clock < _corps_until

## Заслон встаёт кирпичами перед стычкой. line — записи ИИ на рубеже
func assign_corps(line: Array, line_center: Vector3) -> void:
	for s in ai.squads:
		(s as Dictionary).erase("corps")
	if not corps_active() or line.is_empty():
		return
	var face := Vector3(_corps_p.x - line_center.x, 0.0, _corps_p.z - line_center.z)
	face = Vector3.FORWARD if face.length() < 0.01 else face.normalized()
	var anchor: Vector3 = _corps_p - face * _AICfg.CORPS_STANDOFF
	var posts: Array = brick_layout(line, anchor, face)
	for i in range(line.size()):
		var sq: Dictionary = line[i]
		sq["corps"] = true
		ai._set_role(sq, ai.ROLE_LINE, GameManager.land_target(posts[i]), face)

## Радиус контратаки с поста: корпус держит место, обычный рубеж — как был
func engage_radius(sq: Dictionary) -> float:
	if corps_active() and bool(sq.get("corps", false)):
		return _AICfg.CORPS_ENGAGE_R
	return _AICfg.DEFENSE_ENGAGE_RADIUS

# ═════════════════════════════════════════════════════════════════════════════
# 3. КЛЕЩИ ШТУРМА
# ═════════════════════════════════════════════════════════════════════════════
## plan — [sq, tgt, uid] волны после разноса. Крылья переписывают свою цель и
## роль (ROLE_FLANK — бегом мимо строя), центр не трогается
func pincer(plan: Array, target: Vector3, course: Vector3, wave_c: Vector3) -> void:
	if not _Opt.ai_pincer or plan.size() < _AICfg.PINCER_MIN:
		for p0 in plan:
			(p0[0] as Dictionary).erase("wing")
		return
	var right := Vector3(-course.z, 0.0, course.x)
	var per: int = maxi(1, int(round(float(plan.size()) * _AICfg.PINCER_SHARE)))
	# Кандидаты в крылья: не стрелки; рыцари первыми, затем крайние по фронту
	var cand: Array = []
	for i in range(plan.size()):
		var uid: String = String(plan[i][2])
		if _is_ranged(uid):
			continue
		var tgt: Vector3 = plan[i][1]
		var lat: float = (tgt.x - target.x) * right.x + (tgt.z - target.z) * right.z
		cand.append([i, lat, 0 if uid == "warrior" else 1])
	var wings: Dictionary = {}     # индекс плана → сторона
	for side in [-1.0, 1.0]:
		var pick: Array = cand.filter(func(e): return not wings.has(int(e[0])) and float(e[1]) * side >= 0.0)
		if pick.size() < per:
			pick = cand.filter(func(e): return not wings.has(int(e[0])))
		pick.sort_custom(func(a, b):
			if int(a[2]) != int(b[2]):
				return int(a[2]) < int(b[2])
			return float(a[1]) * side > float(b[1]) * side)
		for k in range(mini(per, pick.size())):
			wings[int(pick[k][0])] = side
	# Нельзя оставить центр пустым
	if plan.size() - wings.size() < 2:
		return
	var half_front := 0.0
	for i2 in range(plan.size()):
		if wings.has(i2):
			continue
		var t2: Vector3 = plan[i2][1]
		half_front = maxf(half_front, absf((t2.x - target.x) * right.x + (t2.z - target.z) * right.z))
	var ordinal: Dictionary = {-1.0: 0, 1.0: 0}   # номер крыла на своей стороне
	for i3 in range(plan.size()):
		var sq: Dictionary = plan[i3][0]
		if not wings.has(i3):
			sq.erase("wing")
			continue
		var side2: float = wings[i3]
		# Крылья одной стороны разводятся по PINCER_WING_GAP: иначе они шли в одну точку
		var k: int = int(ordinal[side2])
		ordinal[side2] = k + 1
		var spread: float = float(k) * _AICfg.PINCER_WING_GAP
		if float(sq.get("wing", 0.0)) != side2:
			sq["wing"] = side2
			sq["wing_stage"] = 0
			pincer_wings += 1
		var outer: Vector3 = target - course * _AICfg.PINCER_BACK \
			+ right * side2 * (half_front + _AICfg.PINCER_WIDE + spread)
		var rear: Vector3 = target + course * _AICfg.PINCER_DEEP + right * side2 * (half_front * 0.5 + spread)
		var c: Vector3 = ai._squad_centroid(sq["members"])
		if int(sq.get("wing_stage", 0)) == 0 and c != Vector3.ZERO:
			# Дошёл до внешней точки или уже вышел за линию фронта — в тыл
			var past: float = (c.x - target.x) * course.x + (c.z - target.z) * course.z
			if Vector2(c.x - outer.x, c.z - outer.z).length() < _AICfg.PINCER_STAGE_M \
					or past > -_AICfg.PINCER_BACK * 0.5:
				sq["wing_stage"] = 1
		plan[i3][1] = GameManager.land_target(outer if int(sq.get("wing_stage", 0)) == 0 else rear)

## Роль крыла на этот такт: обход бегом или штурм
func wing_role(sq: Dictionary, base_role: String) -> String:
	if not _Opt.ai_pincer or not sq.has("wing"):
		return base_role
	return ai.ROLE_FLANK if int(sq.get("wing_stage", 0)) == 0 else base_role

# ═════════════════════════════════════════════════════════════════════════════
# 4. ОПОРНЫЕ ТОЧКИ: ВЫШКА У БРОДА И РУДНИКА
# ═════════════════════════════════════════════════════════════════════════════
## Точки, которые держит ИИ: [центр группы, курс от дома, sid-ы лучников]
func _held_points() -> Array:
	var out: Array = []
	var groups: Dictionary = {}
	for s in ai.squads:
		var sq: Dictionary = s
		var role: String = String(sq["role"])
		var sid: int = ai._sid_of(sq)
		var key := ""
		if ai.red.ford_group.has(sid):
			key = "ford"
		elif role == ai.ROLE_MINE:
			key = "mine"
		if key.is_empty():
			continue
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(sq)
	for key2 in groups:
		var lst: Array = groups[key2]
		var tgt := Vector3.ZERO
		var n := 0
		var bows: Array = []
		var near_all := true
		for sq2 in lst:
			var t: Vector3 = (sq2 as Dictionary)["target"]
			tgt += t
			n += 1
			var c: Vector3 = ai._squad_centroid((sq2 as Dictionary)["members"])
			if c == Vector3.ZERO or Vector2(c.x - t.x, c.z - t.z).length() > _AICfg.SP_NEAR_M:
				near_all = false
			if _is_ranged(String((sq2 as Dictionary)["type"])):
				bows.append(ai._sid_of(sq2))
		if n == 0 or not near_all:
			continue
		out.append([tgt / float(n), bows])
	return out

func _tower_near(p: Vector3, r: float) -> Building:
	for grp in ["enemy_buildings", "construction_sites"]:
		for b in ai.main.get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(b) or (b as Building).faction != F or (b as Building).is_dead():
				continue
			var bid: String = (b as Building).building_id
			if b.get("target_id") != null:
				bid = String(b.get("target_id"))
			if bid != "tower":
				continue
			var q: Vector3 = (b as Node3D).global_position
			if Vector2(q.x - p.x, q.z - p.z).length() < r:
				return b as Building
	return null

## Шаг стройки опорных точек; true — площадка заложена
func build_step(castle: Castle, crew: int) -> bool:
	if not _Opt.ai_strongpoint:
		return false
	var now: float = ai.clock
	var seen: Dictionary = {}
	for hp in _held_points():
		var p: Vector3 = hp[0]
		var key := Vector2i(int(floor(p.x / 8.0)), int(floor(p.z / 8.0)))
		seen[key] = true
		if not _sp_since.has(key):
			_sp_since[key] = now
		var tw: Building = _tower_near(p, 25.0)
		if tw == null:
			if now - float(_sp_since[key]) < _AICfg.SP_HOLD_SEC or sp_towers >= _AICfg.SP_TOWERS:
				continue
			var course := Vector3(p.x - castle.global_position.x, 0.0, p.z - castle.global_position.z)
			course = Vector3.FORWARD if course.length() < 0.01 else course.normalized()
			var spot: Vector3 = GameManager.land_target(p - course * _AICfg.SP_BEHIND)
			if not GameManager.is_passable(spot.x, spot.z):
				continue
			if ai._start_site("tower", spot, false, crew):
				sp_towers += 1
				ai.last_action += "|вышка на опорной точке"
				return true
			continue
		# Вышка стоит — лучники группы на неё
		if tw.has_method("request_garrison") and not ("target_id" in tw) and tw.has_method("has_garrison") \
				and not bool(tw.call("has_garrison")):
			for sid in hp[1]:
				if int(sid) > 0 and tw.request_garrison(int(sid), false):
					sp_garrisons += 1
					ai.last_action += "|лучники на вышку"
					break
	for k in _sp_since.keys():
		if not seen.has(k):
			_sp_since.erase(k)
	return false
