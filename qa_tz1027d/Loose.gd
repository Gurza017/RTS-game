extends "res://qa_ai_loop/Smoke.gd"
## ЗОНД «БОЙЦЫ БЕЗ ОТРЯДА» (27.10.2026): та же длинная партия, что Smoke;
## каждый физкадр следит за реестром отрядов — печатает отряд, распущенный
## ПУСТЫМ (ни одного бойца за всю жизнь: распуск геттером squad_members до
## первого спавна) — и раз в 30 кадров ищет живых боевых бойцов красного с
## squad_id 0: откуда они (род, точка, ближайший отряд того же рода).
## Запуск: godot --headless --path . res://qa_tz1027d/Loose.tscn -- minutes=14 seed=27102026

var _known: Dictionary = {}       # sid → {"t", "type", "fac", "full"}
var _loose_seen: Dictionary = {}  # instance_id → true
var _frame: int = 0
var _empty_disbands: int = 0
var _loose_total: int = 0

func _physics_process(_delta: float) -> void:
	if main == null or _done:
		return
	_frame += 1
	var now: float = Unit.game_sec
	# 1) реестр: новые и исчезнувшие
	for key in GameManager.squads.keys():
		var sid: int = int(key)
		var rec: Dictionary = GameManager.squads[sid]
		var k: Variant = _known.get(sid)
		if k == null:
			_known[sid] = {"t": now, "type": String(rec.get("type", "?")), "fac": int(rec.get("faction", -1)),
				"full": int(rec.get("full", 0)), "men": (rec["members"] as Array).size()}
		else:
			(k as Dictionary)["full"] = maxi(int((k as Dictionary)["full"]), int(rec.get("full", 0)))
			(k as Dictionary)["men"] = (rec["members"] as Array).size()
	for key in _known.keys():
		if GameManager.squads.has(key):
			continue
		var k: Dictionary = _known[key]
		if int(k["full"]) == 0 and int(k["fac"]) == Constants.FACTION_ENEMY:
			_empty_disbands += 1
			print("  [ЗОНД loose] t=%.1f отряд %d (%s, фр.%d) РАСПУЩЕН ПУСТЫМ через %.2f с после создания" % [
				now, int(key), String(k["type"]), int(k["fac"]), now - float(k["t"])])
		_known.erase(key)
	# 2) живые боевые бойцы красного без отряда
	if _frame % 30 != 0:
		return
	for n in main.get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u is Worker or u.is_dead() or u.garrisoned or u.squad_id != 0:
			continue
		var iid: int = u.get_instance_id()
		if _loose_seen.has(iid):
			continue
		_loose_seen[iid] = true
		_loose_total += 1
		# ближайший отряд реестра того же рода
		var best_sid := 0
		var best_d := 1e9
		var best_men := 0
		for key in GameManager.squads.keys():
			var rec: Dictionary = GameManager.squads[key]
			if int(rec.get("faction", -1)) != Constants.FACTION_ENEMY or String(rec.get("type", "")) != u.stat_id:
				continue
			var mem: Array = rec["members"]
			var c := Vector3.ZERO
			var cnt := 0
			for m in mem:
				if is_instance_valid(m) and not (m as Unit).is_dead():
					c += (m as Unit).global_position
					cnt += 1
			if cnt == 0:
				continue
			c /= float(cnt)
			var d: float = c.distance_to(u.global_position)
			if d < best_d:
				best_d = d
				best_sid = int(key)
				best_men = cnt
		if _loose_total <= 40:
			print("  [ЗОНД loose] t=%.1f боец без отряда: %s у (%.1f, %.1f) сост=%d возраст_узла=%s; ближайший отряд %d (%d бойцов) в %.1f м" % [
				now, u.stat_id, u.global_position.x, u.global_position.z, int(u.state), str(u.name), best_sid, best_men, best_d])

func _finish() -> void:
	if _done:
		return
	print("  [ЗОНД loose] ИТОГ: отрядов красного, распущенных пустыми: %d; бойцов без отряда замечено: %d" % [_empty_disbands, _loose_total])
	super._finish()
