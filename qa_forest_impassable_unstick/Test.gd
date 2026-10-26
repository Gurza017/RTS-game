extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД «ЗАПЕРТЫЕ В ЛЕСУ» (ТЗ 22.10.2026, скриншот 16:05)
## ═══════════════════════════════════════════════════════════════════════════
## Стенд сам находит глубокую клетку леса-стены (непроходимая маска ядра:
## is_cliff и в точке, и в 2.5 м во все стороны) и ставит туда отряд красных
## копейщиков. Судится свойство: за EXIT_SEC 100 % бойцов стоят на
## проходимой земле (is_cliff = false), не дальше FAR_M от старта, ОТТУДА ЕСТЬ
## ДОРОГА (A* до базы находится), и никто не погиб/не пропал.
## FAR_M был 12 м, пока вынос клал бойцов в замкнутые клетки у кромки карты
## между стволами и краем (разбор партии 25.10.2026): ближе было, но дороги
## оттуда нет. Клочки теперь закрыты (NavFillIsolated), до настоящей кромки
## массива у края карты — 12-20 м
##   A — отряд стоит без приказа (пост внутри массива)
##   B — отряду ИИ велено идти в точку глубже в массив
##   C — справочно (-- ab=1): то же с ручкой trap_sweep выключенной
## Запуск: godot --headless --path . res://qa_forest_impassable_unstick/Test.tscn [-- ab=1]

const _Opt := preload("res://scripts/perf_config.gd")
const E := Constants.FACTION_ENEMY
const EXIT_SEC := 2.0
const FAR_M := 24.0

var main: Node = null
var _pass := 0
var _fail := 0
var _ab := false
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "ab=1":
			_ab = true
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
	print("\n═════ ИТОГ qa_forest_impassable_unstick: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3, fac: int) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

## Глубокая клетка: непроходимо в точке и в 2.5 м во все 4 стороны
func _deep_cell(skip: Array) -> Vector3:
	var lim: float = 230.0
	var x := -lim
	while x <= lim:
		var z := -lim
		while z <= lim:
			var ok := GameManager.is_cliff(x, z)
			if ok:
				for d in [Vector2(2.5, 0), Vector2(-2.5, 0), Vector2(0, 2.5), Vector2(0, -2.5)]:
					if not GameManager.is_cliff(x + d.x, z + d.y):
						ok = false
						break
			if ok:
				var p := Vector3(x, 0, z)
				var near := false
				for s in skip:
					if (s as Vector3).distance_to(p) < 30.0:
						near = true
				if not near:
					return p
			z += 4.0
		x += 4.0
	return Vector3.INF

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	print("  клеток скал/леса в маске: %d" % GameManager.cliff_cells)
	var used: Array = []
	var p1: Vector3 = _deep_cell(used)
	if p1 == Vector3.INF:
		verdict("стенд нашёл глубокую клетку леса", false)
		_finish()
		return
	used.append(p1)
	await _case("A", "стоят без приказа внутри массива", p1, false, true)
	var p2: Vector3 = _deep_cell(used)
	if p2 != Vector3.INF:
		used.append(p2)
		await _case("B", "идут в точку глубже в массив", p2, true, true)
	if _ab:
		var p3: Vector3 = _deep_cell(used)
		if p3 != Vector3.INF:
			_Opt.trap_sweep = false
			await _case("C", "справочно: ручка trap_sweep выключена", p3, false, false)
			_Opt.trap_sweep = true
	_finish()

func _case(tag: String, title: String, at: Vector3, order_in: bool, judge: bool) -> void:
	print("\n═════ %s. %s (%.0f, %.0f) ═════" % [tag, title, at.x, at.z])
	var sid: int = GameManager.new_squad(E, "spearman")
	var men: Array = []
	for k in range(12):
		var off := Vector3(float(k % 4) * 0.6 - 0.9, 0, float(k / 4) * 0.6 - 0.6)
		var u := _spawn("spearman", at + off, E)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(2)
	var inside0 := 0
	for m in men:
		if GameManager.is_cliff((m as Node3D).global_position.x, (m as Node3D).global_position.z):
			inside0 += 1
	if order_in:
		for m in men:
			(m as Unit).command_move(at + Vector3(2.0, 0, 2.0))
	var t := 0
	var out_t := -1.0
	while t < int(EXIT_SEC * 60.0) + 60:
		await pframes(5)
		t += 5
		var inside := 0
		for m in men:
			if is_instance_valid(m) and GameManager.is_cliff((m as Node3D).global_position.x, (m as Node3D).global_position.z):
				inside += 1
		if inside == 0 and out_t < 0.0:
			out_t = float(t) / 60.0
	var inside_end := 0
	var lost := 0
	var far := 0
	var shut := 0
	var home: Vector3 = main.PLAYER_BASE_ANCHOR
	var worst := 0.0
	for m in men:
		if not is_instance_valid(m) or (m as Unit).is_dead():
			lost += 1
			continue
		var p: Vector3 = (m as Node3D).global_position
		if GameManager.is_cliff(p.x, p.z):
			inside_end += 1
		worst = maxf(worst, p.distance_to(at))
		if p.distance_to(at) > FAR_M:
			far += 1
		GameManager.army.nav_path(p.x, p.z, home.x, home.z, 1.5, 0.0)
		if not GameManager.army.nav_last_found():
			shut += 1
	print("  %s: в массиве на старте %d из %d; вышли все за %s с; в массиве к концу %d, дальше %.0f м %d (худший %.1f м), без дороги %d, пропало %d" % [
		tag, inside0, men.size(), ("%.2f" % out_t) if out_t >= 0.0 else "—", inside_end, FAR_M, far, worst, shut, lost])
	if judge:
		verdict("%s %s: 100 %% вышли за %.0f с" % [tag, title, EXIT_SEC],
			inside0 >= men.size() / 2 and out_t >= 0.0 and out_t <= EXIT_SEC,
			"на старте %d, вышли за %s" % [inside0, str(out_t)])
		verdict("%s %s: вышли к кромке, не пропали" % [tag, title], far == 0 and lost == 0,
			"дальше %.0f м %d, пропало %d" % [FAR_M, far, lost])
		verdict("%s %s: вышли туда, откуда есть дорога" % [tag, title], shut == 0,
			"без дороги %d" % shut)
	_free(men)
	await pframes(10)
