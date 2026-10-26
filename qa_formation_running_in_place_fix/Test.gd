extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД «БЕГ НА МЕСТЕ» ПОСЛЕ РАССТАНОВКИ (ТЗ 22.10.2026, скриншот 46:15)
## ═══════════════════════════════════════════════════════════════════════════
## Четыре отряда копейщиков протяжкой ПКМ (настоящий SelectionManager.
## _execute_line_formation) встают у пня. Судится свойство: после того как
## строй встал, через SETTLE_SEC ни один боец не в ленте бега
## (Unit.walk_anim_recently — лента копейщика по факту смещения) и не в
## State.MOVING. Дрожание меряется окном: путь бойца за WATCH_SEC при
## нулевом итоговом смещении.
##   A — плотная протяжка вплотную к пню (диагональ, как на скриншоте)
##   B — короткая протяжка (глубокие блоки) у пня
##   C — контроль: та же протяжка в чистом поле
## Запуск: godot --headless --path . res://qa_formation_running_in_place_fix/Test.tscn [-- only=abc]

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const F := Constants.FACTION_PLAYER

## Сколько после «встали» даётся на успокоение (ТЗ: 1-2 с)
const SETTLE_SEC := 2.0
## Окно замера дрожания
const WATCH_SEC := 3.0

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abc"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_formation_running_in_place_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3, fac: int = F) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int = F, cols: int = 10) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

## Убрать всех живых в радиусе (тролли, гноллы, овцы пня, охрана) и чужие
## постройки, кроме пня — он и есть окружение сценария
func _clear(at: Vector3, r: float, keep: Node = null) -> void:
	main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b != keep and (b as Node3D).global_position.distance_to(at) < r \
				and not (b as Building).is_stronghold():
			b.queue_free()

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	var lair: Node3D = null
	for l in GameManager.troll_lairs:
		if l != null and is_instance_valid(l):
			lair = l
			break
	if lair != null:
		# Пень стоит (он — окружение), но тролли, гноллы и овцы его не рожают
		lair.process_mode = Node.PROCESS_MODE_DISABLED
	var lp: Vector3 = lair.global_position if lair != null else Vector3(0, 0, 0)
	print("  пень: %s" % [lp])
	if "a" in _only:
		await _case("A", "плотная протяжка у пня", lp, lp + Vector3(-15, 0, -16), lp + Vector3(-8, 0, 12), lair)
	if "b" in _only:
		await _case("B", "короткая протяжка у пня", lp, lp + Vector3(-11, 0, -6), lp + Vector3(-9, 0, 5), lair)
	if "c" in _only:
		var fp := Vector3(-60, 0, -40)
		await _case("C", "контроль: чистое поле", fp, fp + Vector3(-4, 0, -14), fp + Vector3(3, 0, 14), null)
	_finish()

func _case(tag: String, title: String, centre: Vector3, a: Vector3, b: Vector3, lair: Node) -> void:
	print("\n═════ %s. %s ═════" % [tag, title])
	_clear(centre, 55.0, lair)
	await pframes(5)
	var n: int = _UCfgT.squad_size("spearman")
	var men: Array = []
	for k in range(4):
		men.append_array(_squad("spearman", centre + Vector3(-34, 0, -20 + k * 11), n))
	await pframes(10)
	var sm = main.selection_manager
	sm.select_units(men)
	sm._execute_line_formation(GameManager.land_target(a), GameManager.land_target(b))
	sm.clear_selection()
	# «Встали»: 95 % в покое или 30 с
	var t := 0
	while t < 60 * 30:
		await pframes(15)
		t += 15
		var idle := 0
		for m in _alive(men):
			if (m as Unit).state == Unit.State.IDLE:
				idle += 1
		if idle >= int(0.95 * float(men.size())):
			break
	print("  %s: строй встал за %.1f с" % [tag, float(t) / 60.0])
	await pframes(int(SETTLE_SEC * 60.0))
	# Окно замера: путь каждого и итоговое смещение
	var start: Dictionary = {}
	var prev: Dictionary = {}
	var path: Dictionary = {}
	for m in _alive(men):
		start[m] = (m as Node3D).global_position
		prev[m] = start[m]
		path[m] = 0.0
	var run_peak := 0
	var moving_peak := 0
	var w := 0
	while w < int(WATCH_SEC * 60.0):
		await pframes(5)
		w += 5
		var run_n := 0
		var mov_n := 0
		for m in _alive(men):
			var u := m as Unit
			var p: Vector3 = u.global_position
			path[m] = float(path[m]) + Vector2(p.x - (prev[m] as Vector3).x, p.z - (prev[m] as Vector3).z).length()
			prev[m] = p
			if u.walk_anim_recently():
				run_n += 1
			if u.state == Unit.State.MOVING:
				mov_n += 1
		run_peak = maxi(run_peak, run_n)
		moving_peak = maxi(moving_peak, mov_n)
	var jitter := 0
	var worst_path := 0.0
	var st_hist: Dictionary = {}
	for m in _alive(men):
		var u2 := m as Unit
		var net: float = Vector2(u2.global_position.x - (start[m] as Vector3).x,
			u2.global_position.z - (start[m] as Vector3).z).length()
		var pth: float = float(path[m])
		worst_path = maxf(worst_path, pth)
		# Дрожит: прошёл заметный путь, а итогом почти на месте
		if pth > 0.6 and net < pth * 0.5:
			jitter += 1
		var k2: int = u2.state
		st_hist[k2] = int(st_hist.get(k2, 0)) + 1
	var total: int = _alive(men).size()
	print("  %s: в ленте бега (пик) %d, MOVING (пик) %d, дрожащих %d из %d; худший путь за %.0f с %.2f м; состояния %s" % [
		tag, run_peak, moving_peak, jitter, total, WATCH_SEC, worst_path, st_hist])
	verdict("%s %s: никто не бежит на месте" % [tag, title], run_peak == 0,
		"в ленте бега %d из %d" % [run_peak, total])
	verdict("%s %s: все в покое" % [tag, title], moving_peak <= maxi(1, total / 100),
		"MOVING %d из %d" % [moving_peak, total])
	_free(men)
	await pframes(10)
