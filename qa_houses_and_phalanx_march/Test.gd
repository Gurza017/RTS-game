extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 14.10.2026 (третье письмо): лимит армии от домов и марш фаланги
## ═══════════════════════════════════════════════════════════════════════════
##   A — лимит: 20 домов + крепость дают ~2000+ бойцов (формулой и живыми
##       домами), цена домов по-прежнему экспонента с 10-го;
##   B — марш копейщиков: [C] — копья подняты, 100 % скорости; [S] с
##       «Фалангой» — копья опущены и на ходу, скорость ×0.8.
## Запуск: godot --headless --path . res://qa_houses_and_phalanx_march/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const F := Constants.FACTION_PLAYER

var main: Node = null
var _pass := 0
var _fail := 0
var _done := false

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_houses_and_phalanx_march: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = F
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _clear(at: Vector3, r: float) -> void:
	main._clear_trees(at, r)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
			u.queue_free()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "raid_manager"]:
		var nd = main.get(n)
		if nd != null and nd is Node:
			(nd as Node).set_process(false)
			(nd as Node).set_physics_process(false)
	_a_houses()
	await _a_live_houses()
	await _b_march()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
func _a_houses() -> void:
	print("\n═════ A. ЛИМИТ АРМИИ ОТ ДОМОВ ═════")
	var cap20: int = _UCfg.pop_army_cap(20, 1)
	var cap10: int = _UCfg.pop_army_cap(10, 1)
	print("  лимит: 10 домов — %d, 20 домов — %d, полный кап %d за %d домов" % [
		cap10, cap20, _UCfg.ARMY_HARD_CAP, _UCfg.houses_for_full_army(1)])
	verdict("A1 20 домов + крепость — ~2000+ бойцов", cap20 >= 2000 and cap20 <= 2200, "%d" % cap20)
	verdict("A2 потолок не пробит", _UCfg.pop_army_cap(60, 3) == _UCfg.ARMY_HARD_CAP)
	var m20: float = _UCfg.building_cost_mult("house", 19)
	verdict("A3 цена по-прежнему экспонента: 20-й дом ×100 и дороже, 9-й по базе",
		m20 >= 100.0 and _UCfg.building_cost_mult("house", 8) == 1.0, "20-й ×%.0f" % m20)

func _a_live_houses() -> void:
	var at := Vector3(-30, 0, -70)
	_clear(at, 40.0)
	await pframes(3)
	var hs: Array = []
	var have: int = GameManager.house_total(F)
	for k in range(maxi(0, 20 - have)):
		var h: Building = load("res://scripts/House.gd").new()
		h.variant_id = String(_UCfg.HOUSE_IDS[k % 3])
		h.faction = F
		main.world_add(h)
		var p := at + Vector3(float(k % 5) * 4.5, 0, float(k / 5) * 4.5)
		h.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		hs.append(h)
	var cs: Building = null
	if GameManager.castle_total(F) <= 0:
		cs = Castle.new()
		cs.faction = F
		main.world_add(cs)
		cs.global_position = Vector3(at.x + 30.0, GameManager.get_terrain_height(at.x + 30.0, at.z), at.z)
	await pframes(5)
	var live_cap: int = GameManager.pop_army_cap(F)
	verdict("A4 живыми постройками: 20 домов и крепость — лимит ≥ 2000",
		GameManager.house_total(F) >= 20 and live_cap >= 2000,
		"домов %d, лимит %d" % [GameManager.house_total(F), live_cap])

# ─────────────────────────────────────────────────────────────────────────────
## Средняя скорость отряда на ровном участке марша: медиана бойцов, первые
## 0.7 с (разгон) не считаются
func _march(men: Array, dist: float) -> Dictionary:
	var c := Vector3.ZERO
	for u in men:
		c += (u as Node3D).global_position
	c /= float(men.size())
	for u in men:
		var off: Vector3 = (u as Node3D).global_position - c
		(u as Unit).command_move(c + Vector3(0, 0, -dist) + off, false, Vector3.ZERO, false, true)
	await pframes(42)
	var p0: Array = []
	for u in men:
		p0.append((u as Node3D).global_position)
	var frames := 150
	var leveled := 0
	var samples := 0
	for f in range(frames):
		await pframes(1)
		if f % 15 == 7:
			for u in men:
				var sp := u as Spearman
				if sp.state == Unit.State.MOVING:
					samples += 1
					if sp._spear_leveled():
						leveled += 1
	var sp_list: Array = []
	for i in range(men.size()):
		var d: float = Vector2((men[i] as Node3D).global_position.x - (p0[i] as Vector3).x,
			(men[i] as Node3D).global_position.z - (p0[i] as Vector3).z).length()
		sp_list.append(d / (float(frames) / float(Engine.physics_ticks_per_second)))
	sp_list.sort()
	return {"speed": float(sp_list[sp_list.size() / 2]), "leveled": leveled, "samples": samples}

func _b_march() -> void:
	print("\n═════ B. КОПЕЙЩИКИ НА МАРШЕ: [C] И [S] ═════")
	GameManager.finish_research(F, "spearman_1d")
	var at := Vector3(60, 0, 40)
	_clear(at, 60.0)
	await pframes(3)
	var sid: int = GameManager.new_squad(F, "spearman")
	var men: Array = []
	for k in range(12):
		var u := _spawn("spearman", at + Vector3(float(k % 6) * 0.7, 0, float(k / 6) * 0.7))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(10)
	verdict("B0 «Фаланга» изучена — [S] у отряда даёт фалангу", GameManager.spear_wall_ready(sid))
	# [C] — вольно
	for u in men:
		(u as Unit).set_stance("attack")
	var free: Dictionary = await _march(men, 30.0)
	await pframes(60)
	# [S] — держать строй (фаланга)
	for u in men:
		(u as Unit).set_stance("defense")
	await pframes(5)
	var phal: Dictionary = await _march(men, -30.0)
	var ratio: float = float(phal["speed"]) / maxf(float(free["speed"]), 0.001)
	print("  [C] %.2f м/с, копья опущены %d из %d выборок; [S] %.2f м/с, опущены %d из %d; отношение %.3f" % [
		free["speed"], free["leveled"], free["samples"], phal["speed"], phal["leveled"], phal["samples"], ratio])
	verdict("B1 [C]: на марше копья подняты", int(free["samples"]) > 0 and int(free["leveled"]) == 0,
		"опущены %d из %d" % [free["leveled"], free["samples"]])
	verdict("B2 [S]: на марше копья опущены («щетина»)", int(phal["samples"]) > 0
		and int(phal["leveled"]) >= int(float(int(phal["samples"])) * 0.9),
		"опущены %d из %d" % [phal["leveled"], phal["samples"]])
	var want: float = float(_UCfg.STANCES["defense"]["move_speed_mult"])
	verdict("B3 [S]: фаланга идёт на 20 %% медленнее (×%.2f)" % want,
		absf(want - 0.8) < 0.001 and absf(ratio - want) <= 0.05, "×%.3f" % ratio)
