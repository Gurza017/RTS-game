extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_reform_idle — ШТОРМ СМЫКАНИЯ У СТОЯЩИХ ОТРЯДОВ (ТЗ 19.09.2026, блок 3.1)
## ═══════════════════════════════════════════════════════════════════════════
##   A — шесть стоящих отрядов копейщиков с потерями (30 %): после одного
##       смыкания приказов в покое НЕ ДОЛЖНО БЫТЬ (было: центр разметки по
##       всем ячейкам, живые — в первых n, разница ненулевая всегда → строй
##       полз бесконечно, 600+ приказов/с у армии из 130 отрядов).
##   B — чужие мёртвые тела рядом (выбитый отряд у самого строя) смыкание
##       не взводят: приказов по-прежнему ноль.
##   C — сдвинутый на 0.6 м боец (разбором наложения) приказа не получает
##       (порог закрепления = порог дрейфа 0.70), сдвинутый на 2 м — получает
##       ОДИН и возвращается.
## Приказы считает perf_config.cmd_meter по источникам (cmd_src).
## Запуск: godot --headless --path . res://qa_reform_idle/Test.tscn

const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_reform_idle: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Отряд блоком cols × rows с настоящим строевым интервалом и разметкой:
## приказ строем в свою же точку (как ПКМ) — тогда есть slots
func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var px: float = at.x + float(i % cols) * 0.6 - float(cols - 1) * 0.3
		var pz: float = at.z + float(i / cols) * 0.6
		var u: Unit = _spawn(kind, fac, Vector3(px, 0.0, pz))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _src_counts() -> Dictionary:
	var out: Dictionary = {}
	for rec in _Opt.cmd_report():
		var src: String = String((rec as Array)[0])
		out[src] = int(out.get(src, 0)) + int((rec as Array)[3])
	return out

## Приказы по источникам ТОЛЬКО для наших отрядов (дикие гноллы/тролли партии
## патрулируют своими приказами и в замер не идут)
func _src_for(sids: Array) -> Dictionary:
	var out: Dictionary = {}
	var total := 0
	for rec in _Opt.cmd_sid_report():
		var src: String = String((rec as Array)[0])
		var sid: int = int((rec as Array)[1])
		if not sids.has(sid):
			continue
		out[src] = int(out.get(src, 0)) + int((rec as Array)[2])
		total += int((rec as Array)[2])
	out["_total"] = total
	return out

func _moving(arr: Array) -> int:
	var n := 0
	for u in _alive(arr):
		if (u as Unit).state == Unit.State.MOVING:
			n += 1
	return n

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for k in ["goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	var base := Vector3(30.0, 0.0, -30.0)
	main._clear_area_of_resources(base, 60.0)

	print("\n═════ A. СТОЯЩИЕ ОТРЯДЫ С ПОТЕРЯМИ ═════")
	var squads: Array = []
	var all_men: Array = []
	for k in range(6):
		var s: Array = _squad("spearman", F, base + Vector3(float(k) * 9.0, 0.0, 0.0), 30)
		squads.append(s)
		all_men.append_array(s[1])
	await pframes(6)
	# Разметка: приказ строем в свою точку (тот же путь, что растяг ПКМ)
	var sm = main.selection_manager
	for s in squads:
		sm._clear_selection()
		for u in s[1]:
			sm._select(u)
		var c: Vector3 = GameManager.squad_centroid(int(s[0]))
		sm._issue_formation_move(c, false)
	sm._clear_selection()
	# Ждём прихода всех
	var settle := 0
	for f in range(60 * 20):
		await get_tree().physics_frame
		settle = f
		if _moving(all_men) == 0 and f > 60:
			break
	var with_slots := 0
	for s in squads:
		if not (GameManager.squads[int(s[0])] as Dictionary).get("slots", []).is_empty():
			with_slots += 1
	verdict("A0 шесть отрядов встали строем, разметка есть у всех", _moving(all_men) == 0 and with_slots == 6,
		"идут %d, с разметкой %d, за %d кадров" % [_moving(all_men), with_slots, settle])
	# Потери 30 % — каждого третьего, тела остаются под ногами
	var killed := 0
	for s in squads:
		var men: Array = s[1]
		for i in range(men.size()):
			if i % 3 == 1:
				(men[i] as Unit).take_damage(1.0e12)
				killed += 1
	await pframes(60 * 6)
	# Одно смыкание после потерь — законно; дальше в покое приказов быть не должно
	var my_sids: Array = []
	for s in squads:
		my_sids.append(int(s[0]))
	_Opt.cmd_reset()
	_Opt.cmd_meter = true
	await pframes(60 * 20)
	_Opt.cmd_meter = false
	var by_src: Dictionary = _src_for(my_sids)
	var total: int = int(by_src.get("_total", 0))
	var reform_n: int = int(by_src.get("close_ranks", 0)) + int(by_src.get("cohesion", 0))
	verdict("A1 20 с покоя после потерь: приказов смыкания/сплочённости ≤ 3 (было сотни)",
		reform_n <= 3, "close_ranks+cohesion %d, всего %d за 20 с: %s (все источники: %s)" % [reform_n, total, str(by_src), str(_src_counts())])
	verdict("A2 всего приказов нашим отрядам в покое < 0.5/с", float(total) / 20.0 < 0.5, "%.2f/с" % (float(total) / 20.0))
	var still := _moving(all_men)
	verdict("A3 никто не идёт (строй стоит, не ползёт)", still == 0, "идут %d из %d" % [still, _alive(all_men).size()])

	print("\n═════ B. ЧУЖИЕ ТЕЛА У СТРОЯ ═════")
	# Чужой отряд выбивается вплотную к первому отряду: 20 тел в двух метрах
	var c0: Vector3 = GameManager.squad_centroid(int(squads[0][0]))
	var foes: Array = _squad("goblin_spearman", GF, c0 + Vector3(0.0, 0.0, -3.0), 20, 5)
	for g in foes[1]:
		(g as Unit).set_tick(false)
	await pframes(2)
	for g in foes[1]:
		(g as Unit).take_damage(1.0e12)
	await pframes(60 * 4)
	_Opt.cmd_reset()
	_Opt.cmd_meter = true
	await pframes(60 * 12)
	_Opt.cmd_meter = false
	var by_src2: Dictionary = _src_for(my_sids)
	var reform2: int = int(by_src2.get("close_ranks", 0)) + int(by_src2.get("cohesion", 0))
	verdict("B1 двадцать чужих тел у строя смыкание не взводят (приказов смыкания ≤ 2)",
		reform2 <= 2, "close_ranks+cohesion %d, всего %d: %s" % [reform2, int(by_src2.get("_total", 0)), str(by_src2)])

	print("\n═════ C. СДВИНУТЫЙ БОЕЦ ═════")
	var men0: Array = _alive(squads[1][1])
	var u_small: Unit = men0[0]
	var u_big: Unit = men0[1]
	var ps: Vector3 = u_small.global_position + Vector3(0.6, 0.0, 0.0)
	u_small.global_position = Vector3(ps.x, GameManager.get_terrain_height(ps.x, ps.z), ps.z)
	u_small.sync_row()
	var pb: Vector3 = u_big.global_position + Vector3(0.0, 0.0, 2.2)
	u_big.global_position = Vector3(pb.x, GameManager.get_terrain_height(pb.x, pb.z), pb.z)
	u_big.sync_row()
	_Opt.cmd_reset()
	_Opt.cmd_meter = true
	var big_moved := false
	for f in range(60 * 10):
		await get_tree().physics_frame
		if u_big.state == Unit.State.MOVING:
			big_moved = true
	_Opt.cmd_meter = false
	var d_big: float = Vector2(u_big.global_position.x - u_big.post_pos.x, u_big.global_position.z - u_big.post_pos.z).length()
	var by_src3: Dictionary = _src_for(my_sids)
	verdict("C1 сдвинутый на 2 м вернулся к посту (< 0.8 м)", d_big < 0.8,
		"видели MOVING=%s, до поста %.2f" % [str(big_moved), d_big])
	verdict("C2 приказов на весь отряд — единицы (≤ 8 за 10 с), а не по всему составу и не по кругу",
		int(by_src3.get("close_ranks", 0)) <= 8, "close_ranks %d: %s" % [int(by_src3.get("close_ranks", 0)), str(by_src3)])
	_finish()
