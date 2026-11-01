extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ПНИ: ПОХОДЫ К БРОДУ И ОЖИВЛЕНИЕ (ТЗ 31.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Походы (ручка lair_ford_sorties): пни ПРАВОГО берега раз в
## LAIR_SORTIE_NEAR_SEC (ближний, сторона игрока) / LAIR_SORTIE_FAR_SEC
## (дальний, зеркальный) выпускают LAIR_SORTIE_TROLLS троллей и
## LAIR_SORTIE_GNOLLS отрядов гноллов на пятак за бродом на левом берегу.
## Вышедшие пню больше не принадлежат: тролль держит пятак (Troll.ford_hold),
## гнолл — дом на пятаке (home_pos, lair = null). Потолок живых на пятаке —
## свой (LAIR_PATCH_*), потолков пней походы не занимают. Левый пень не ходит.
## Пень замороженный — поход всё равно идёт: пятак держат и до перехода игрока.
##
## Оживление (ручка lair_revive): снесённый пень через LAIR_REVIVE_SEC встаёт на
## своей точке запечатанным (GameManager.restore_lair(f, true)): внутри
## LAIR_REVIVE_TROLLS и LAIR_REVIVE_GNOLLS отрядов, выходят по одному от удара.
##
## Такт — раз в TICK_SEC по часам партии (Main.game_clock: на паузе стоят).
## Состояние в сохранение не идёт: после загрузки сроки отсчитываются заново.

const _Opt := preload("res://scripts/perf_config.gd")
const _Spawn := preload("res://scripts/spawn_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _TrollScene := preload("res://scenes/units/Troll.tscn")

const TICK_SEC := 1.0

var main: Node = null
var _next_tick: float = 0.0
## пень (instance id) → часы следующего похода
var _sortie_at: Dictionary = {}
## Вышедшие на пятак (стенды, потолок)
var patch_trolls: Array = []
var patch_gnoll_squads: Array = []
var sorties: int = 0
var sortie_trolls: int = 0
var sortie_gnolls: int = 0
var revives: int = 0
## Походы на привале (lair_sortie_march): {"halt", "t0", "first", "all_t",
## "len", "trolls": [[тролль, пятак]], "gnolls": [[sid, дом]]}
var marches: Array = []
var march_halts: int = 0
var march_timeouts: int = 0
var march_contacts: int = 0

func _clock() -> float:
	if main != null and is_instance_valid(main) and main.has_method("game_clock"):
		return float(main.call("game_clock"))
	return Unit.game_sec

func _process(_delta: float) -> void:
	var now: float = _clock()
	if now < _next_tick:
		return
	_next_tick = now + TICK_SEC
	if main == null or not is_instance_valid(main) or not _Opt.goblin_village:
		return
	if _Opt.lair_ford_sorties:
		_tick_sorties(now)
	if not marches.is_empty():
		_tick_marches(now)
	if _Opt.lair_revive:
		_tick_revive(now)

# ── ПОХОДЫ ──────────────────────────────────────────────────────────────────

## Пятак: сухая кромка левого берега на оси брода + LAIR_PATCH_OUT
func patch_point() -> Vector3:
	# Выход брода на левом берегу — тем же путём, каким брод ведёт бойцов
	var r: Array = main.call("ford_route", Vector3(60.0, 0.0, 0.0), Vector3(-60.0, 0.0, 0.0), 0.0)
	var b: Vector3 = r[1] if r.size() >= 2 else Vector3(-12.5, 0.0, 0.0)
	return GameManager.land_target(b + Vector3(-_Spawn.LAIR_PATCH_OUT, 0.0, 0.0))

## Период похода пня; < 0 — пень не ходит (левый берег, чужая сторона)
func sortie_period(l: Node) -> float:
	var side: int = int(main.call("river_side", (l as Node3D).global_position))
	if side <= 0:
		return -1.0
	var sf: int = int(l.get("side_faction"))
	if sf == Constants.FACTION_PLAYER:
		return _Spawn.LAIR_SORTIE_NEAR_SEC
	if sf == Constants.FACTION_GOBLIN:
		return _Spawn.LAIR_SORTIE_FAR_SEC
	return -1.0

func _tick_sorties(now: float) -> void:
	for l in GameManager.troll_lairs:
		if l == null or not is_instance_valid(l) or (l as Building).is_dead():
			continue
		var per: float = sortie_period(l)
		if per <= 0.0:
			continue
		var key: int = l.get_instance_id()
		if not _sortie_at.has(key):
			_sortie_at[key] = now + per
			continue
		if now < float(_sortie_at[key]):
			continue
		_sortie_at[key] = now + per
		launch_sortie(l)

func _alive_patch_trolls() -> int:
	var keep: Array = []
	for t in patch_trolls:
		if t != null and is_instance_valid(t) and not (t as Unit).is_dead():
			keep.append(t)
	patch_trolls = keep
	return keep.size()

func _alive_patch_gnolls() -> int:
	var keep: Array = []
	for sid in patch_gnoll_squads:
		var sq: Variant = GameManager.squads.get(int(sid))
		if sq == null:
			continue
		for m in (sq as Dictionary)["members"]:
			if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
				keep.append(int(sid))
				break
	patch_gnoll_squads = keep
	return keep.size()

## Выпустить поход из пня (стенды зовут напрямую). Возвращает [троллей, отрядов]
func launch_sortie(l: Node) -> Array:
	if l == null or not is_instance_valid(l) or (l as Building).is_dead():
		return [0, 0]
	var at: Vector3 = (l as Node3D).global_position
	var goal: Vector3 = patch_point()
	var nt: int = mini(_Spawn.LAIR_SORTIE_TROLLS, _Spawn.LAIR_PATCH_TROLLS_MAX - _alive_patch_trolls())
	var ng: int = mini(_Spawn.LAIR_SORTIE_GNOLLS, _Spawn.LAIR_PATCH_GNOLLS_MAX - _alive_patch_gnolls())
	var made_t := 0
	var made_g := 0
	var parent: Node = (l as Node).get_parent()
	# Привал у подступа к броду: вышедшие идут сперва туда (lair_sortie_march)
	var halt: Vector3 = halt_point(at) if _Opt.lair_sortie_march else Vector3.INF
	var mr := {"halt": halt, "t0": _clock(), "first": -1.0, "all_t": -1.0,
		"len": Vector2(halt.x - at.x, halt.z - at.z).length() if halt.is_finite() else 0.0,
		"trolls": [], "gnolls": []}
	for i in range(maxi(nt, 0)):
		var u: Unit = _TrollScene.instantiate()
		u.faction = Constants.FACTION_GOBLIN
		u.set("ford_hold", _spread(goal, sortie_trolls, 6.0))
		parent.add_child(u)
		var a: float = TAU * float(sortie_trolls) * 0.618
		var px: float = at.x + cos(a) * 9.0
		var pz: float = at.z + sin(a) * 9.0
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		var sid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "troll")
		GameManager.add_to_squad(sid, u)
		if halt.is_finite():
			var hp: Vector3 = _spread(halt, sortie_trolls, 6.0)
			mr["trolls"].append([u, u.get("ford_hold"), hp])
			u.set("ford_hold", hp)
		u.post_pos = u.get("ford_hold")
		u.command_move(GameManager.land_target(u.get("ford_hold")))
		patch_trolls.append(u)
		sortie_trolls += 1
		made_t += 1
	var size: int = int(_GobCfg.SQUAD_SIZE.get("gnoll", 12))
	for i in range(maxi(ng, 0)):
		var a: float = TAU * float(sortie_gnolls) * 0.618 + 1.3
		var base: Vector3 = GameManager.land_target(at + Vector3(cos(a) * 11.0, 0.0, sin(a) * 11.0))
		var sid: int = int(main.call("spawn_goblin_squad", "gnoll", size, base, false, 0, false))
		if sid <= 0:
			continue
		var home: Vector3 = _spread(goal, sortie_gnolls + 1, 12.0)
		if halt.is_finite():
			var gh: Vector3 = _spread(halt, sortie_gnolls + 1, 12.0)
			mr["gnolls"].append([sid, home, gh])
			home = gh
		for m in GameManager.squads[sid]["members"]:
			if m == null or not is_instance_valid(m):
				continue
			m.set("lair", null)
			m.set("home_pos", home)
			(m as Unit).post_pos = home
			(m as Unit).command_move(GameManager.land_target(home))
		patch_gnoll_squads.append(sid)
		sortie_gnolls += 1
		made_g += 1
	if halt.is_finite() and made_t + made_g > 0:
		marches.append(mr)
	if made_t + made_g > 0:
		sorties += 1
		GameManager.tm_event("lair_sortie", {"lair": int(l.get("side_faction")),
			"trolls": made_t, "gnolls": made_g})
	return [made_t, made_g]

## ── ПРИВАЛ ПОХОДА (ТЗ 31.10.2026, lair_sortie_march) ──────────────────────
## Подступ к броду: вход брода с берега пня минус HALT_FORD_APPROACH поперёк
## реки. INF — дороги через брод нет или пень ближе HALT_MIN_GAP к привалу
func halt_point(from: Vector3) -> Vector3:
	var goal: Vector3 = patch_point()
	var fr: Array = main.call("ford_route", from, goal, 0.0)
	if fr.size() != 2:
		return Vector3.INF
	var a: Vector3 = fr[0]
	var across: Vector3 = (fr[1] as Vector3) - a
	across.y = 0.0
	if across.length() < 0.1:
		return Vector3.INF
	var h: Vector3 = a - across.normalized() * _Spawn.HALT_FORD_APPROACH
	if Vector2(h.x - from.x, h.z - from.z).length() < _Spawn.HALT_MIN_GAP:
		return Vector3.INF
	return GameManager.land_target(h)

func _tick_marches(now: float) -> void:
	var keep: Array = []
	for mr in marches:
		if not _march_step(mr, now):
			keep.append(mr)
	marches = keep

## Такт одного похода; true — привал снят (дальше на пятак)
func _march_step(mr: Dictionary, now: float) -> bool:
	var alive := 0
	var there := 0
	var sx := 0.0
	var sz := 0.0
	var cnt := 0
	if not mr.has("arrived"):
		mr["arrived"] = {}
	var arrived: Dictionary = mr["arrived"]
	for e in mr["trolls"]:
		var t = e[0]
		if t == null or not is_instance_valid(t) or (t as Unit).is_dead():
			continue
		alive += 1
		var p: Vector3 = (t as Node3D).global_position
		sx += p.x
		sz += p.z
		cnt += 1
		# Дошедший отмечается раз: дальше он патрулирует вокруг привала
		# (радиус патруля больше HALT_ARRIVE_R) и «уходом» это не считается
		var hp: Vector3 = e[2]
		var key: int = (t as Node).get_instance_id()
		if Vector2(p.x - hp.x, p.z - hp.z).length() <= _Spawn.HALT_ARRIVE_R:
			arrived[key] = true
		if arrived.has(key):
			there += 1
	for e2 in mr["gnolls"]:
		var sq: Variant = GameManager.squads.get(int(e2[0]))
		if sq == null:
			continue
		var gh: Vector3 = e2[2]
		var n := 0
		var near := 0
		for m in (sq as Dictionary)["members"]:
			if m == null or not is_instance_valid(m) or (m as Unit).is_dead():
				continue
			n += 1
			var q: Vector3 = (m as Node3D).global_position
			sx += q.x
			sz += q.z
			cnt += 1
			if Vector2(q.x - gh.x, q.z - gh.z).length() <= _Spawn.HALT_ARRIVE_R + 6.0:
				near += 1
		if n == 0:
			continue
		alive += 1
		if float(near) >= float(n) * _Spawn.HALT_SETTLE_SHARE:
			arrived[-int(e2[0])] = true
		if arrived.has(-int(e2[0])):
			there += 1
	mr["there"] = there
	mr["alive"] = alive
	if alive == 0:
		return true
	var why := ""
	var c := Vector3(sx / float(cnt), 0.0, sz / float(cnt))
	if _foe_near(c, _Spawn.CONTACT_R):
		why = "contact"
		march_contacts += 1
	if why == "" and there > 0 and float(mr["first"]) < 0.0:
		mr["first"] = now
	if why == "" and there >= alive:
		if float(mr["all_t"]) < 0.0:
			mr["all_t"] = now
		if now - float(mr["all_t"]) >= _Spawn.HALT_MIN_SEC:
			why = "gathered"
			march_halts += 1
	if why == "" and ((float(mr["first"]) >= 0.0 and now - float(mr["first"]) >= _Spawn.HALT_WAIT_MAX_SEC)
			or now - float(mr["t0"]) >= _Spawn.HALT_LEG_BASE_SEC + float(mr["len"]) / _Spawn.HALT_LEG_SPEED):
		why = "timeout"
		march_timeouts += 1
	if why == "":
		return false
	_march_release(mr)
	GameManager.tm_event("lair_sortie_halt", {"why": why, "groups": alive})
	return true

## Привал снят: тролли — на свой пятак, гноллы — дом на пятаке
func _march_release(mr: Dictionary) -> void:
	for e in mr["trolls"]:
		var t = e[0]
		if t == null or not is_instance_valid(t) or (t as Unit).is_dead():
			continue
		var u := t as Unit
		u.set("ford_hold", e[1])
		u.post_pos = e[1]
		u.command_move(GameManager.land_target(e[1]))
	for e2 in mr["gnolls"]:
		var sq: Variant = GameManager.squads.get(int(e2[0]))
		if sq == null:
			continue
		for m in (sq as Dictionary)["members"]:
			if m == null or not is_instance_valid(m) or (m as Unit).is_dead():
				continue
			m.set("home_pos", e2[1])
			(m as Unit).post_pos = e2[1]
			(m as Unit).command_move(GameManager.land_target(e2[1]))

func _foe_near(c: Vector3, r: float) -> bool:
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		if GameManager.army.nearest_of_side(c.x, c.z, f, r) != null:
			return true
	return false

## Точка вокруг центра пятака: вышедшие не встают друг на друга
func _spread(c: Vector3, i: int, r: float) -> Vector3:
	if i <= 0:
		return c
	var a: float = TAU * float(i) * 0.618
	return GameManager.land_target(c + Vector3(cos(a) * r, 0.0, sin(a) * r))

# ── ОЖИВЛЕНИЕ ───────────────────────────────────────────────────────────────

func _tick_revive(now: float) -> void:
	for f in GameManager.lair_spots:
		if GameManager.lair_for(int(f)) != null:
			continue
		if not GameManager.lair_fell_at.has(f):
			continue
		if now - float(GameManager.lair_fell_at[f]) < _Spawn.LAIR_REVIVE_SEC:
			continue
		revive(int(f))

## Поставить пень стороны f запечатанным (стенды зовут напрямую)
func revive(f: int) -> Node:
	var l: Node = GameManager.restore_lair(f, true)
	if l != null:
		GameManager.lair_fell_at.erase(f)
		revives += 1
		GameManager.tm_event("lair_revive", {"side": f})
	return l
