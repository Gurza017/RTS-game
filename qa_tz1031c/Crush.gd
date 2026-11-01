extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД qa_tz1031c/Crush — СЖАТИЕ АРМИЙ В СТОЛКНОВЕНИИ (ТЗ 31.10.2026, п. 3)
## ═══════════════════════════════════════════════════════════════════════════
## Две армии стенка на стенку: S отрядов копейщиков игрока (cols × rows) против
## S отрядов мечников красного, фронтом друг к другу, отряд на отряд. Вердиктов
## нет — числа по окнам после первого контакта:
##   сжатых    — доля живых, у кого ближайший свой по отряду ближе SQUEEZE_R;
##   кисель    — доля живых, у кого своих в 0.45 м трое и больше;
##   глубина   — средний габарит отряда вдоль курса / исходный;
##   по рядам  — средний интервал до ближайшего своего в полосах глубины от
##               своего фронта (ряды 0-1, 2-3, 4+ по исходному шагу);
##   фронт     — где медиана передней пятой части каждой стороны (м по курсу);
##   тик       — tick_meter за окно, мс.
## Запуск: godot --headless --path . res://qa_tz1031c/Crush.tscn
##         -- squads=6 cols=10 rows=6 secs=30 [knob=имя:значение ...]

const _Opt := preload("res://scripts/perf_config.gd")
const SQUEEZE_R := 0.40
const P := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY

var main = null
var _squads := 6
var _cols := 10
var _rows := 6
var _secs := 30
var _red_unit := "warrior"
var _step := 0.55
var _a: Array = []      # [sid, men] игрока
var _b: Array = []      # [sid, men] красного
var _out: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("squads="): _squads = int(s.substr(7))
		elif s.begins_with("cols="): _cols = int(s.substr(5))
		elif s.begins_with("rows="): _rows = int(s.substr(5))
		elif s.begins_with("secs="): _secs = int(s.substr(5))
		elif s.begins_with("red="): _red_unit = s.substr(4)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился за 600 с")
		get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(30.0, 0.0, 0.0), Vector3(-30.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 20.0), Vector3(0.0, 0.0, -20.0)]:
				var q: Vector3 = p + (d as Vector3)
				h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
				if GameManager.is_water(q.x, q.z) or not GameManager.is_passable(q.x, q.z):
					h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

func _squad(fac: int, uid: String, at: Vector3, course: Vector3) -> Array:
	var scene: PackedScene = Building.PRELOAD_SCENES.get(uid)
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	var slots: Array = []
	for i in range(_cols * _rows):
		var off := Vector3(float(i % _cols) * _step - float(_cols - 1) * _step * 0.5,
			0.0, -course.z * float(i / _cols) * _step)
		var p: Vector3 = at + off
		var u: Unit = scene.instantiate()
		u.faction = fac
		main.world_add(u)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		u.formation_row = i / _cols
		men.append(u)
		slots.append(p)
	GameManager.squad_set_formation(sid, slots, course, false)
	for i in range(men.size()):
		(men[i] as Unit).command_move(slots[i], true, course, false, true)
	return [sid, men]

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

## Числа одной стороны: [сжатых, кисель, глубина/исходная, ряды 0-2, 3-5, 6+, фронт]
func _side(groups: Array, course_z: float) -> Array:
	var tot := 0
	var squeezed := 0
	var mush := 0
	var depth_sum := 0.0
	var depth_n := 0
	var band_s := [0.0, 0.0, 0.0]
	var band_n := [0, 0, 0]
	var fronts: Array = []
	for g in groups:
		var men: Array = _alive((g as Array)[1])
		if men.size() < 2:
			continue
		var proj: Array = []
		for u in men:
			proj.append((u as Unit).global_position.z * course_z)
		proj.sort()
		var front: float = proj[proj.size() - 1]
		depth_sum += (front - float(proj[0])) / maxf(float(_rows - 1) * _step, 0.1)
		depth_n += 1
		fronts.append(proj[int(proj.size() * 0.8)])
		for a in men:
			var pa: Vector3 = (a as Unit).global_position
			var near := INF
			var close := 0
			for b in men:
				if b == a:
					continue
				var pb: Vector3 = (b as Unit).global_position
				var d: float = Vector2(pa.x - pb.x, pa.z - pb.z).length()
				near = minf(near, d)
				if d < 0.45:
					close += 1
			tot += 1
			if near < SQUEEZE_R:
				squeezed += 1
			if close >= 3:
				mush += 1
			var rank: float = (front - pa.z * course_z) / _step
			var bi: int = 0 if rank < 1.5 else (1 if rank < 3.5 else 2)
			band_s[bi] += near
			band_n[bi] += 1
	fronts.sort()
	var fr: float = fronts[fronts.size() / 2] * course_z if not fronts.is_empty() else 0.0
	return [float(squeezed) / maxf(tot, 1), float(mush) / maxf(tot, 1),
		depth_sum / maxf(depth_n, 1),
		band_s[0] / maxf(band_n[0], 1), band_s[1] / maxf(band_n[1], 1), band_s[2] / maxf(band_n[2], 1),
		fr, tot]

func _row(t: String, s: Array) -> String:
	return "%s сжатых %4.1f%%  кисель %4.1f%%  глубина ×%.2f  интервал ряды 0-1 %.2f / 2-3 %.2f / 4+ %.2f  фронт %+.1f м  живых %d" % [
		t, float(s[0]) * 100.0, float(s[1]) * 100.0, float(s[2]), float(s[3]), float(s[4]), float(s[5]), float(s[6]), int(s[7])]

func _engaged(groups: Array) -> int:
	var n := 0
	for g in groups:
		for u in _alive((g as Array)[1]):
			var t = (u as Unit).attack_target
			if t != null and is_instance_valid(t) and (u as Unit).global_position.distance_to((t as Node3D).global_position) <= (u as Unit).reach() + 0.5:
				n += 1
	return n

func _run() -> void:
	seed(7)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.pop_limit_enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		var wu := n as Unit
		if wu != null and not wu.is_dead():
			wu.take_damage(1e12)
	await pframes(6)
	_step = Building.new().squad_spacing
	var c: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, 20.0))
	main._clear_area_of_resources(c, 80.0)
	await pframes(4)
	var w: float = float(_cols) * _step + 2.0
	for k in range(_squads):
		var x: float = c.x + (float(k) - float(_squads - 1) * 0.5) * w
		_a.append(_squad(P, "spearman", Vector3(x, 0.0, c.z - 8.0), Vector3(0.0, 0.0, 1.0)))
		_b.append(_squad(R, _red_unit, Vector3(x, 0.0, c.z + 8.0), Vector3(0.0, 0.0, -1.0)))
	await pframes(120)
	print("  арена (%.0f, %.0f), %d × %d бойцов на сторону (%d×%d), шаг %.2f м" % [
		c.x, c.z, _squads, _cols * _rows, _cols, _rows, _step])
	print(_row("  ДО:      игрок", _side(_a, 1.0)))
	print(_row("  ДО:      красн", _side(_b, -1.0)))
	for k in range(_squads):
		GameManager.squad_attack_squad(int(_a[k][0]), int(_b[k][0]), true)
		GameManager.squad_attack_squad(int(_b[k][0]), int(_a[k][0]), true)
	var g := 0
	while g < 60 * 30 and _engaged(_a) + _engaged(_b) == 0:
		await get_tree().physics_frame
		g += 1
	print("  первый контакт через %.1f с" % (float(g) / 60.0))
	var windows: Array = [3, 6, 10, 15, 20, 30]
	var last := 0
	for wsec in windows:
		if wsec > _secs:
			break
		_Opt.tick_meter = true
		_Opt.tick_reset()
		await pframes((wsec - last) * 60)
		var tk: float = _Opt.tick_ms()
		_Opt.tick_meter = false
		last = wsec
		var qh: int = GameManager.army.queue_holds() if GameManager.army.has_method("queue_holds") else -1
		print("  ── %2d с боя, тик %.2f мс, дерутся %d/%d, в очереди (шагов накоп.) %d" % [wsec, tk, _engaged(_a), _engaged(_b), qh])
		print(_row("     игрок", _side(_a, 1.0)))
		print(_row("     красн", _side(_b, -1.0)))
	print("=== CRUSH PROBE DONE ===")
	get_tree().quit()
