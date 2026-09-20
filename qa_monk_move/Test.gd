extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_monk_move — ПКМ ПО ЗЕМЛЕ У МОНАХА (ТЗ 19.09.2026, блок 2)
## ═══════════════════════════════════════════════════════════════════════════
##   A — клик по земле МЕЖДУ двумя своими отрядами (узкое место): монах
##       получает марш, а не приказ лечить, идёт и приходит в точку.
##   B — клик по земле у чужого строя: монаху не атака (он не умеет), а марш.
##   C — клик далеко (30 м) при раненом отряде за спиной: автоматы монаха
##       (к фронту, к пациенту, дистанция монахов, отход) приказ не перебивают,
##       монах доходит до точки.
##   D — клик ПО своему бойцу по-прежнему приказ лечить.
## Клик — настоящим разбором ПКМ (SelectionManager._handle_right_click по
## экранной точке); камера заморожена, точка считается тем же кадром.
## Запуск: godot --headless --path . res://qa_monk_move/Test.tscn

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN

var main = null
var sm = null
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
	print("\n═════ ИТОГ qa_monk_move: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 5) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x + float(i % cols) * 0.6, 0.0, at.z + float(i / cols) * 0.6))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _screen_of(p: Vector3) -> Vector2:
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	return cam.unproject_position(p)

func _look_at(p: Vector3) -> void:
	main.focus_camera_on(p)
	await frames(12)

## ПКМ по точке земли p через штатный разбор; возвращает, что нашёл pick
func _rmb_ground(p: Vector3) -> Dictionary:
	await _look_at(p)
	var scr: Vector2 = _screen_of(Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z))
	var pick: Dictionary = sm._pick_at(scr, sm.order_pick_mask())
	sm._handle_right_click(scr, false)
	return pick

## Ждать прихода монаха в точку (пик ≤ tol) с потолком в физкадрах
func _wait_arrive(m: Unit, p: Vector3, tol: float, cap: int) -> Array:
	var best := INF
	var f := 0
	while f < cap:
		await get_tree().physics_frame
		f += 1
		var d: float = _xz(m.global_position, p)
		best = minf(best, d)
		# Приход = точка достигнута; состояние не судим: по приходу автономия
		# тем же тактом может увести монаха к раненым (C3 это и проверяет)
		if d <= tol:
			return [true, d, f]
	return [false, best, f]

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for k in ["goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)
	GameManager.world_bounds_enabled = false
	GameManager.pop_limit_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	main.set_process(false)
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	if cam != null:
		cam.set_process(false)
	var base := Vector3(20.0, 0.0, -20.0)
	main._clear_area_of_resources(base, 70.0)

	print("\n═════ A. КЛИК МЕЖДУ ДВУМЯ СВОИМИ ОТРЯДАМИ ═════")
	var monk: Unit = _spawn("monk", F, base + Vector3(0.0, 0.0, 12.0))
	var left: Array = _squad("spearman", F, base + Vector3(-6.0, 0.0, 0.0), 15)
	var right: Array = _squad("spearman", F, base + Vector3(3.0, 0.0, 0.0), 15)
	await pframes(10)
	# Точка ровно между отрядами: до ближайшего бойца ~1.3 м
	var gap := Vector3(base.x + 0.9, 0.0, base.z + 0.6)
	var nearest := INF
	for u in left[1] + right[1]:
		nearest = minf(nearest, _xz((u as Unit).global_position, gap))
	sm._clear_selection()
	sm._select(monk)
	GameManager.on_selection_changed(sm.selected_units, true)
	var heals0: int = int(sm.monk_heal_orders)
	var pick: Dictionary = await _rmb_ground(gap)
	await pframes(2)
	verdict("A0 клик лёг между отрядами (ближайший свой в %.1f м), под курсором %s" % [nearest, str(pick.get("target"))],
		nearest >= 0.8 and nearest <= 2.5)
	verdict("A1 это МАРШ, а не приказ лечить (heal_orders не вырос, монах идёт)",
		sm.monk_heal_orders == heals0 and monk.state == Unit.State.MOVING and int(monk.player_goal_moves) >= 1,
		"heal_orders %d, state %d, goal_moves %d" % [sm.monk_heal_orders - heals0, monk.state, int(monk.player_goal_moves)])
	verdict("A2 точка приказа — точка клика (± 1 м)", _xz(monk.post_pos, gap) <= 1.0,
		"пост в %.2f м от клика" % _xz(monk.post_pos, gap))
	var arr: Array = await _wait_arrive(monk, gap, 1.2, 60 * 20)
	verdict("A3 монах пришёл строго в точку (≤ 1.2 м, пик %.2f м за %d кадров)" % [float(arr[1]), int(arr[2])], bool(arr[0]))

	print("\n═════ B. КЛИК У ЧУЖОГО СТРОЯ ═════")
	var foes: Array = _squad("goblin_spearman", GF, base + Vector3(18.0, 0.0, 10.0), 10)
	for g in foes[1]:
		(g as Unit).set_tick(false)
	await pframes(4)
	var near_foe := Vector3(base.x + 18.0 - 2.0, 0.0, base.z + 10.0 + 0.6)
	sm._clear_selection()
	sm._select(monk)
	GameManager.on_selection_changed(sm.selected_units, true)
	await _rmb_ground(near_foe)
	await pframes(2)
	verdict("B1 монах у чужого строя получает марш (не пустую «атаку»)", monk.state == Unit.State.MOVING
		and _xz(monk.post_pos, near_foe) <= 1.5, "state %d, пост в %.2f м" % [monk.state, _xz(monk.post_pos, near_foe)])
	# Уводим гоблинов, чтобы монах дошёл живым
	for g in foes[1]:
		(g as Unit).take_damage(1e12)
	await pframes(4)

	print("\n═════ C. ДАЛЬНИЙ ПРИКАЗ ПРИ РАНЕНЫХ ЗА СПИНОЙ ═════")
	# Раненые копейщики рядом с монахом: автомат хочет лечить и идти к фронту
	for u in left[1]:
		var uu := u as Unit
		uu.current_health = uu.max_health * 0.4
		uu._soa_push_stats()
	var far := base + Vector3(-32.0, 0.0, 30.0)
	sm._clear_selection()
	sm._select(monk)
	GameManager.on_selection_changed(sm.selected_units, true)
	await _rmb_ground(far)
	await pframes(2)
	var front0: int = int(monk.front_moves)
	var arr2: Array = await _wait_arrive(monk, far, 1.5, 60 * 40)
	verdict("C1 монах дошёл до дальней точки (%.0f м), автоматы приказ не перебили (пик %.2f м, %d кадров)" % [
		_xz(base + Vector3(0, 0, 12), far), float(arr2[1]), int(arr2[2])], bool(arr2[0]))
	verdict("C2 по дороге ни одного самовольного марша к фронту", int(monk.front_moves) == front0,
		"front_moves +%d" % (int(monk.front_moves) - front0))
	# Пришёл — приказ исчерпан, автономия снова работает: монах идёт лечить
	var d_before: float = _xz(far, GameManager.squad_centroid(int(left[0])))
	await pframes(60 * 12)
	var d_after: float = _xz(monk.global_position, GameManager.squad_centroid(int(left[0])))
	verdict("C3 после прихода автономия вернулась: монах пошёл к раненым (ближе точки приказа на 5+ м)",
		d_after < d_before - 5.0, "от точки приказа до раненых %.1f, монах теперь в %.1f м" % [d_before, d_after])

	print("\n═════ D. КЛИК ПО СВОЕМУ БОЙЦУ — ЛЕЧИТЬ ═════")
	sm._clear_selection()
	sm._select(monk)
	GameManager.on_selection_changed(sm.selected_units, true)
	var victim: Unit = right[1][0]
	await _look_at(victim.global_position)
	var scr: Vector2 = _screen_of(victim.global_position + Vector3(0.0, 0.7, 0.0))
	var pk: Dictionary = sm._pick_at(scr, sm.order_pick_mask())
	var h0: int = int(sm.monk_heal_orders)
	sm._handle_right_click(scr, false)
	await pframes(2)
	verdict("D1 клик в фигуру своего бойца — приказ лечить (pick score %.2f)" % float(pk.get("score", -1.0)),
		pk.get("target") != null and pk.get("target") is Unit and (pk.get("target") as Unit).squad_id == victim.squad_id
		and sm.monk_heal_orders == h0 + 1,
		"heal_orders +%d, цель %s" % [sm.monk_heal_orders - h0, str(pk.get("target"))])
	_finish()
