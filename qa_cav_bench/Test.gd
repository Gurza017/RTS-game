extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗАМЕР СВИНОВСАДНИКОВ (ТЗ 29.09.2026, третье письмо, блок 6)
## ═══════════════════════════════════════════════════════════════════════════
## «Как было / как стало»: одна и та же сцена до и после переработки.
## Орда: RIDERS отрядов всадников идут маршем на строй игрока. Игрок: лучники,
## мечники, копейщики в «Защите» лицом к ним и рабочие на пути всадников.
## Печатает каждые 5 с: состояния всадников (стоят / идут / бьют, охота,
## разгон, отход), удары с разгона, «двойные» удары (второй всадник того же
## отряда по тому же месту в пределах CAV_DOUBLE_WIN), павших по родам, «стоят
## в копейщиках» (бьют копейщика в упор и не двигались > 2 с), рабочих,
## убитых в метре от всадника. В конце — цена тика по родам (class_meter:
## ТОЛЬКО ранжирование, профиль завышает на 25-35 %), сканы по местам вызова
## (scan_meter) и честная цена всего тика армии (tick_meter).
## Запуск: godot --headless --path . res://qa_cav_bench/Test.tscn [-- riders=3 secs=45]

const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN
var main = null
var RIDERS := 3
var SECS := 45.0
var _pass := 0
var _fail := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("riders="):
			RIDERS = int(s.substr(7))
		elif s.begins_with("secs="):
			SECS = float(s.substr(5))
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_cav_bench: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int, gap: float = 0.7) -> Array:
	var sid: int = GameManager.new_squad(f, uid)
	var out: Array = []
	for i in range(n):
		var u := _unit(uid, f, at + Vector3(float(i / cols) * gap, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * gap))
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return [sid, out]

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n0) and n0 is Unit:
			(n0 as Unit).take_damage(1.0e12)
	for fac in range(Constants.FACTION_COUNT):
		if fac == F:
			continue
		for b in get_tree().get_nodes_in_group(Constants.building_group(fac)):
			if is_instance_valid(b):
				(b as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await pframes(6)
	# Площадка: середина поля за стенами игрока (к броду), лес вычищен
	var base := Vector3(-60.0, 0.0, -10.0)
	main._clear_area_of_resources(base, 70.0)
	for rn in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(rn) and (rn as Node3D).global_position.distance_to(base) < 70.0:
			(rn as Node).queue_free()
	await pframes(4)
	# Строй игрока лицом на восток (+X)
	var sp: Array = []
	for i in range(2):
		var s: Array = _squad("spearman", F, base + Vector3(0.0, 0.0, -12.0 + 24.0 * float(i)), 24, 8)
		for u in s[1]:
			(u as Unit).set_stance("defense")
			(u as Unit)._facing = Vector3.RIGHT
		sp.append(s)
	var sw: Array = []
	for i in range(2):
		sw.append(_squad("warrior", F, base + Vector3(-6.0, 0.0, -24.0 + 48.0 * float(i)), 16, 4))
	var ar: Array = []
	for i in range(2):
		ar.append(_squad("archer", F, base + Vector3(-14.0, 0.0, -8.0 + 16.0 * float(i)), 20, 5))
	var workers: Array = []
	for i in range(6):
		var w := _unit("worker", F, base + Vector3(22.0 + float(i % 3) * 6.0, 0.0, -10.0 + float(i) * 4.0))
		GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
		workers.append(w)
	var riders: Array = []
	var rsids: Array = []
	for i in range(RIDERS):
		var rs: Array = _squad("goblin_rider", G, base + Vector3(70.0, 0.0, -20.0 + 20.0 * float(i)), 20, 5, 1.1)
		riders.append_array(rs[1])
		rsids.append(int(rs[0]))
	await pframes(10)
	# ── ФАЗА ПОКОЯ: конница стоит, врагов в 30 м нет — цена стоящих ──────
	_Opt.class_meter = true
	_Opt.class_reset()
	_Opt.scan_meter = true
	_Opt.scan_reset()
	_Opt.tick_meter = true
	_Opt.tick_reset()
	await pframes(600)
	var idle_rider := [0.0, 0.0]
	for row in _Opt.class_report():
		if String(row[0]) == "goblin_rider":
			idle_rider = [float(row[1]), float(row[2])]
	print("  ПОКОЙ 10 с: тик армии %.3f мс; всадники %.3f мс/кадр, %.1f мкс/тик; сканов %d" % [_Opt.tick_ms(), idle_rider[0], idle_rider[1], _Opt.scan_calls])
	# Марш орды на строй — дальше решает сама конница (охота, разгон)
	for u in riders:
		(u as Unit).command_move(base + Vector3(-10.0, 0.0, (u as Unit).global_position.z - base.z))
	_Opt.class_meter = true
	_Opt.class_reset()
	_Opt.scan_meter = true
	_Opt.scan_reset()
	_Opt.tick_meter = true
	_Opt.tick_reset()
	var dead0: Dictionary = {}
	var still_since: Dictionary = {}
	var stuck_spear_worst := 0
	var workers_dead := 0
	var w0_alive: int = workers.size()
	var t := 0
	var frames: int = int(SECS * 60.0)
	var imp_start: int = _impacts()
	var dbl_start: int = Unit.cav_double_hits
	while t < frames:
		await get_tree().physics_frame
		t += 1
		if t % 30 == 0:
			var stuck_spear := 0
			for u in riders:
				if u == null or not is_instance_valid(u) or (u as Unit).is_dead():
					continue
				var ru := u as Unit
				var tg = ru.attack_target
				var bad: bool = ru.state == Unit.State.ATTACKING and tg != null and is_instance_valid(tg) \
					and tg is Unit and (tg as Unit).stat_id == "spearman" and not ru.moved_recently() \
					and ru.global_position.distance_to((tg as Node3D).global_position) <= ru.attack_range + 1.0
				if bad:
					if not still_since.has(ru):
						still_since[ru] = t
					elif t - int(still_since[ru]) >= 120:
						stuck_spear += 1
				else:
					still_since.erase(ru)
			stuck_spear_worst = maxi(stuck_spear_worst, stuck_spear)
		if t % 300 == 0:
			var st := {"idle": 0, "move": 0, "attack": 0, "hunt": 0, "charge": 0, "withdraw": 0, "dead": 0}
			for u in riders:
				if u == null or not is_instance_valid(u) or (u as Unit).is_dead():
					st["dead"] += 1
					continue
				var ru := u as Unit
				match ru.state:
					Unit.State.IDLE: st["idle"] += 1
					Unit.State.MOVING: st["move"] += 1
					Unit.State.ATTACKING: st["attack"] += 1
				if bool(ru.get("hunting")):
					st["hunt"] += 1
				if ru.is_charging:
					st["charge"] += 1
				if ru.has_method("is_withdrawing") and bool(ru.call("is_withdrawing")):
					st["withdraw"] += 1
			var alive_w := 0
			for w2 in workers:
				if w2 != null and is_instance_valid(w2) and not (w2 as Unit).is_dead():
					alive_w += 1
			var cst := ""
			if main.get("cav_commander") != null and _Opt.cav_commander:
				for rs0 in rsids:
					cst += "%d:%s " % [int(rs0), String(main.cav_commander.state_of(int(rs0)))]
			print("        командир: %s" % cst)
			print("  [%2d с] всадники: %s; ударов с разгона %d; рабочих живо %d/%d; копейщиков %d, мечников %d, лучников %d" % [
				t / 60, str(st), _impacts() - imp_start, alive_w, workers.size(),
				_alive_n(sp), _alive_n(sw), _alive_n(ar)])
	# ── ИТОГ ЗАМЕРА ──────────────────────────────────────────────────────────
	print("\n═════ ЗАМЕР ═════")
	var ticks_ms: float = _Opt.tick_ms()
	print("  тик армии (честный, tick_meter): %.3f мс" % ticks_ms)
	for row in _Opt.class_report():
		print("  класс %-16s %.3f мс/кадр, %.1f мкс/тик, тиков %d (профиль — только ранжирование)" % [String(row[0]), float(row[1]), float(row[2]), int(row[3])])
	var scans: Array = _Opt.scan_report()
	var total_scan := 0
	for r in scans:
		total_scan += int(r[1])
	print("  сканов за замер: %d (%.0f/с), по местам: %s" % [total_scan, float(total_scan) / SECS, str(scans.slice(0, 8))])
	var rider_scans := 0
	for r in scans:
		if String(r[0]).begins_with("rider") or String(r[0]).begins_with("cav"):
			rider_scans += int(r[1])
	var alive_r := 0
	for u in riders:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			alive_r += 1
	var alive_w2 := 0
	for w3 in workers:
		if w3 != null and is_instance_valid(w3) and not (w3 as Unit).is_dead():
			alive_w2 += 1
	var dbl: int = Unit.cav_double_hits - dbl_start
	print("  ударов с разгона %d, из них задними рядами («двойных») %d; сканов конницы %d (%.1f на всадника в секунду)" % [
		_impacts() - imp_start, dbl, rider_scans, float(rider_scans) / maxf(float(riders.size()) * SECS, 1.0)])
	print("  всадников живо %d/%d; рабочих убито %d/%d; стоящих в копейщиках (худшее окно) %d" % [
		alive_r, riders.size(), workers.size() - alive_w2, workers.size(), stuck_spear_worst])
	print("  павшие игрока: копейщиков %d/48, мечников %d/32, лучников %d/40" % [
		48 - _alive_n(sp), 32 - _alive_n(sw), 40 - _alive_n(ar)])
	verdict("A1 замер прошёл: всадники дошли до строя (ударов с разгона > 0)", _impacts() - imp_start > 0)
	_finish()

func _alive_n(sqs: Array) -> int:
	var n := 0
	for s in sqs:
		for u in s[1]:
			if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
				n += 1
	return n

func _impacts() -> int:
	var n := 0
	for k in GameManager.tm_abilities.keys():
		if String(k) == "%d:charge_impact" % G:
			var v = GameManager.tm_abilities[k]
			n += int(v) if (v is int or v is float) else 0
	return n
