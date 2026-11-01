extends "res://qa_ai_loop/Smoke.gd"
## ЗОНД-ДИАГНОСТ (27.10.2026): та же длинная партия, что qa_ai_loop/Smoke, плюс
## разбор СТОЯЧЕГО разрыва отряда красного: если отряд реестра вне боя лежит
## двумя кучами на одних и тех же местах дольше STAND_SEC, один раз печатается
## его состав по группам ИИ (роль, пост, приказ выдан ли), флаги бойцов (сон,
## отход, тик, гарнизон) и признаки отряда (охрана, в замок). Раз в MIX_SEC —
## список групп ИИ, держащих бойцов нескольких отрядов реестра.
## Запуск: godot --headless --path . res://qa_tz1027d/Diag.tscn -- minutes=24 seed=27102026 knob=squad_probes:true

const STAND_SEC := 60.0
const MIX_SEC := 300.0
var _seen: Dictionary = {}      # sid → {"at": [a, b], "since": game_sec}
var _dumped: Dictionary = {}
var _next_check: float = 0.0
var _next_mix: float = 0.0

func _process(delta: float) -> void:
	super._process(delta)
	if main == null or _done:
		return
	var now: float = Unit.game_sec
	if now >= _next_mix:
		_next_mix = now + MIX_SEC
		_print_mix(now)
	if now < _next_check:
		return
	_next_check = now + 5.0
	var ai = main.enemy_ai
	if ai == null:
		return
	for rec in GameManager.squads_of_faction(Constants.FACTION_ENEMY):
		var sid: int = int((rec as Dictionary).get("id", 0))
		if sid <= 0 or _dumped.has(sid):
			continue
		var res: Dictionary = GameManager.probes.split_of(sid)
		if res.is_empty() or bool(res.get("in_combat", false)):
			_seen.erase(sid)
			continue
		var a: Vector2 = _v2(res["at_a"])
		var b: Vector2 = _v2(res["at_b"])
		var prev: Variant = _seen.get(sid)
		if prev == null or (prev["a"] as Vector2).distance_to(a) > 1.5 \
				or (prev["b"] as Vector2).distance_to(b) > 1.5:
			_seen[sid] = {"a": a, "b": b, "since": now}
			continue
		if now - float(prev["since"]) < STAND_SEC:
			continue
		_dumped[sid] = true
		_dump(ai, sid, res, now - float(prev["since"]))

## Точка кучи из сводки зонда: там Array [x, z] (или Vector2 у стендов)
func _v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float((v as Array)[0]), float((v as Array)[1]))
	return Vector2.INF

func _st(u: Unit) -> String:
	var keys: Array = Unit.State.keys()
	var i: int = int(u.state)
	return String(keys[i]) if i >= 0 and i < keys.size() else str(i)

func _dump(ai, sid: int, res: Dictionary, secs: float) -> void:
	print("  [ДИАГ стоячий разрыв] t=%.0f отряд %d (%s): %d+%d бойцов в %.1f м, стоит %.0f с; охрана=%s в_замок=%s" % [
		Unit.game_sec, sid, String(res["type"]), int(res["a"]), int(res["b"]), float(res["gap"]), secs,
		str(GameManager.squad_is_home_guard(sid)), str(GameManager.squad_is_to_castle(sid))])
	var guard = main.get("enemy_guard")
	if guard != null and is_instance_valid(guard):
		for s in guard.squads:
			if int((s as Dictionary)["sid"]) == sid:
				print("    HomeGuard держит отряд: пост %s уровень %d спит=%s" % [
					str((s as Dictionary)["post"]), int((s as Dictionary).get("level", 0)), str(guard._asleep.has(sid))])
		if guard._lent.has(sid):
			print("    HomeGuard: отряд одолжен армии")
	# Группы ИИ, где есть бойцы этого отряда
	var in_groups := 0
	for gi in range(ai.squads.size()):
		var sq: Dictionary = ai.squads[gi]
		var by: Dictionary = {}
		var mine := 0
		for m in sq["members"]:
			if m == null or not is_instance_valid(m):
				continue
			var k: int = (m as Unit).squad_id
			by[k] = int(by.get(k, 0)) + 1
			if k == sid:
				mine += 1
		if mine == 0:
			continue
		in_groups += 1
		var tgt: Vector3 = sq["target"]
		print("    группа #%d %s роль=%s цель=(%.1f, %.1f) issued=%s retreat_until=%d peak=%d состав по отрядам=%s" % [
			gi, String(sq["type"]), String(sq["role"]), tgt.x, tgt.z, str(sq["issued"]),
			int(sq.get("retreat_until", 0)), int(sq.get("peak", 0)), str(by)])
	print("    групп ИИ с бойцами отряда: %d" % in_groups)
	# Бойцы отряда: где стоят, что делают
	var rec0: Variant = GameManager.squads.get(sid)
	if rec0 == null:
		return
	var mem: Array = (rec0 as Dictionary)["members"]
	var shown := 0
	for m in mem:
		if m == null or not is_instance_valid(m):
			continue
		var u: Unit = m
		if u.is_dead():
			continue
		shown += 1
		if shown > 30:
			break
		var gidx := -1
		for gi in range(ai.squads.size()):
			if (ai.squads[gi]["members"] as Array).has(u):
				gidx = gi
				break
		print("      %s гр=%d (%.1f, %.1f) пост=(%.1f, %.1f) сост=%s отход=%s спит=%s тик=%s физсон=%s гарн=%s цель=%s lock=%.1f" % [
			u.stat_id, gidx, u.global_position.x, u.global_position.z, u.post_pos.x, u.post_pos.z, _st(u),
			str(u.retreating), str(u.dormant), str(u.tick_on), str(u._phys_asleep), str(u.garrisoned),
			str(u.attack_target != null), u._move_lock])

func _print_mix(now: float) -> void:
	var ai = main.enemy_ai
	if ai == null:
		return
	var mixed := 0
	var lines: Array = []
	for gi in range(ai.squads.size()):
		var sq: Dictionary = ai.squads[gi]
		var by: Dictionary = {}
		for m in sq["members"]:
			if m == null or not is_instance_valid(m):
				continue
			var k: int = (m as Unit).squad_id
			by[k] = int(by.get(k, 0)) + 1
		if by.size() > 1:
			mixed += 1
			lines.append("    смесь: группа #%d %s роль=%s состав=%s" % [gi, String(sq["type"]), String(sq["role"]), str(by)])
		# Бойцы без отряда реестра внутри группы: откуда они
		if by.has(0):
			var shown := 0
			for m in sq["members"]:
				if m == null or not is_instance_valid(m) or (m as Unit).squad_id != 0:
					continue
				var u: Unit = m
				shown += 1
				if shown > 3:
					break
				lines.append("    без отряда: гр #%d %s (%.1f, %.1f) сост=%s гарн=%s спит=%s тик=%s мёртв=%s пост=(%.1f, %.1f)" % [
					gi, u.stat_id, u.global_position.x, u.global_position.z, _st(u), str(u.garrisoned),
					str(u.dormant), str(u.tick_on), str(u.is_dead()), u.post_pos.x, u.post_pos.z])
	# Отряды реестра, разнесённые по нескольким группам
	var where: Dictionary = {}
	for gi in range(ai.squads.size()):
		for m in ai.squads[gi]["members"]:
			if m == null or not is_instance_valid(m):
				continue
			var k: int = (m as Unit).squad_id
			var st: Variant = where.get(k)
			if st == null:
				st = {}
				where[k] = st
			(st as Dictionary)[gi] = true
	var torn := 0
	for k in where:
		if (where[k] as Dictionary).size() > 1:
			torn += 1
			lines.append("    отряд %d в группах %s" % [int(k), str((where[k] as Dictionary).keys())])
	print("  [ДИАГ состав] t=%.0f групп ИИ %d, смешанных %d, отрядов реестра в нескольких группах %d" % [now, ai.squads.size(), mixed, torn])
	for l in lines:
		print(l)
