extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_long_battle (QA_LongBattle_90Min) — ТЗ 19.09.2026, блок 5
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: на 70-90-й минуте партии FPS падает до 16-17 при ~1000-2000 бойцах
## на экране; короткие стенды этого не ловили. Здесь — две армии по SIZE
## (игрок и красный ИИ, роды войск вперемешку) на живой карте партии (туман,
## HUD, деревня орды, телеметрия), сходящиеся на 60 м; раз в REGEN_SEC
## игрового времени обе стороны ПОПОЛНЯЮТСЯ до штата (павшие — новыми
## отрядами у своей кромки, живые — полным запасом) и снова идут в бой:
## стычки не кончаются, тела, стрелы и паники копятся, как в долгой партии.
## Ускорение ×MULT (как qa_ai_loop/Smoke): physics_ticks × MULT, time_scale
## × MULT — дельта тика прежняя, ходов в секунду стены больше.
## Раз в игровую минуту печатается строка TelemetryLogger (fps, кадр,
## физтик, кадр логики, бойцы, тела, стрелы, маршрутов/с, застрявшие,
## паникующие, очередь в замок). Вердикты — по ПОСЛЕДНЕЙ минуте:
##   L1 физтик + кадр логики ≤ 16.7 мс (бюджет 60 FPS; в headless FPS — не
##      мера, честные счётчики tick_meter/vis_meter — мера);
##   L2 Pathfinding Requests < 100/с;
##   L3 застрявших (MOVING без хода) < 3 % живых;
##   L4 за прогон ни одного среза телеметрии по FPS < 30 (только окно).
## Запуск: godot --headless --path . res://qa_long_battle/Test.tscn
##         -- minutes=60 size=1000 mult=4
## Окно (FPS честный): без --headless, mult=1.

const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY

var MINUTES := 60.0
var SIZE := 1000
var MULT := 4
const REGEN_SEC := 60.0
const SQUAD_N := 24
const COMPOSITION := ["spearman", "spearman", "archer", "warrior", "spearman", "archer", "warrior"]
const BASE_A := Vector3(-120.0, 0.0, -50.0)
const BASE_B := Vector3(-120.0, 0.0, 20.0)

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _last_min := -1
var _regen_t := 0.0
var _done := false
var _squads_a: Array = []
var _squads_b: Array = []
var _rows: Array = []
var _spawned_total := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("minutes="):
			MINUTES = float(s.substr(8))
		elif s.begins_with("size="):
			SIZE = int(s.substr(5))
		elif s.begins_with("mult="):
			MULT = int(s.substr(5))
	call_deferred("_run")
	get_tree().create_timer(6000.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_long_battle: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	var sp: Vector3 = GameManager.land_target(at)
	u.global_position = _g(sp)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(SQUAD_N):
		var u: Unit = _spawn(kind, fac, Vector3(
			at.x + (float(i % 6) - 2.5) * 0.7, 0.0, at.z + float(i / 6) * 0.7))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	_spawned_total += SQUAD_N
	return [sid, men]

func _alive_of(fac: int) -> Array:
	var out: Array = []
	for u in GameManager._live_units:
		if u == null or not is_instance_valid(u):
			continue
		var un := u as Unit
		if un != null and not un.is_dead() and int(un.faction) == fac and un.attack_damage > 0.0 \
				and not un.garrisoned:
			out.append(un)
	return out

## Пополнить сторону до штата: новые отряды у своей кромки (в сторону от врага)
func _refill(fac: int, base: Vector3, list: Array) -> int:
	var alive: int = _alive_of(fac).size()
	var added := 0
	var k := list.size()
	while alive + added < SIZE:
		var kind: String = COMPOSITION[k % COMPOSITION.size()]
		var col: int = k % 8
		var row: int = (k / 8) % 6
		var at: Vector3 = base + Vector3(float(col - 4) * 6.0, 0.0,
			(float(row) * 5.0) * (-1.0 if fac == F else 1.0))
		list.append(_squad(kind, fac, at))
		added += SQUAD_N
		k += 1
	return added

func _heal_all(fac: int) -> void:
	for u in _alive_of(fac):
		var un := u as Unit
		if un.current_health < un.max_health:
			un.current_health = un.max_health
			un._soa_push_stats()

## Все отряды стороны — на ближайшего живого врага (приказ игрока: замок цели)
func _engage(fac: int, foe_fac: int) -> void:
	var foes: Array = _alive_of(foe_fac)
	if foes.is_empty():
		return
	var mine: Array = _alive_of(fac)
	var done: Dictionary = {}
	for u in mine:
		var un := u as Unit
		var sid: int = un.squad_id
		if sid <= 0 or done.has(sid):
			continue
		done[sid] = true
		if GameManager.squad_panicked(sid) or GameManager.squad_in_heal_queue(sid):
			continue
		var c: Vector2 = GameManager.squad_centre_xz(sid)
		if c.x == INF:
			continue
		var best: Unit = null
		var bd := INF
		# Ближайший из выборки: тысяча против тысячи — выборка каждого 7-го
		for j in range(0, foes.size(), 7):
			var f := foes[j] as Unit
			var d: float = Vector2(f.global_position.x - c.x, f.global_position.z - c.y).length_squared()
			if d < bd:
				bd = d
				best = f
		if best == null:
			continue
		for m in GameManager.squads[sid]["members"]:
			var mu := m as Unit
			if mu != null and is_instance_valid(mu) and not mu.is_dead():
				mu.command_attack(best, true, false, true)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	_Opt.tick_meter = true
	_Opt.vis_meter = true
	if main.telemetry == null:
		main.telemetry = load("res://scripts/TelemetryLogger.gd").new()
		main.telemetry.main = main
		main.add_child(main.telemetry)
	main.telemetry.write_file = false
	await pframes(4)
	_refill(F, BASE_A, _squads_a)
	_refill(E, BASE_B, _squads_b)
	await pframes(30)
	_engage(F, E)
	_engage(E, F)
	print("  qa_long_battle: %d на %d, %.0f минут игрового времени, ускорение ×%d, пополнение раз в %.0f с" % [
		_alive_of(F).size(), _alive_of(E).size(), MINUTES, MULT, REGEN_SEC])
	print("  колонки: мин | fps | кадр мс | физтик мс | логика мс | живых | тел | стрел (полёт/земля) | A*/с | застряли | паника | очередь замка | скрытых на низкой частоте")
	Engine.physics_ticks_per_second = 60 * MULT
	Engine.max_physics_steps_per_frame = 8 * MULT
	Engine.time_scale = float(MULT)

func _process(delta: float) -> void:
	if main == null or _done:
		return
	var clock: float = float(main._match_clock)
	_regen_t += delta
	if _regen_t >= REGEN_SEC:
		_regen_t = 0.0
		_heal_all(F)
		_heal_all(E)
		var a: int = _refill(F, BASE_A, _squads_a)
		var b: int = _refill(E, BASE_B, _squads_b)
		_engage(F, E)
		_engage(E, F)
		if a + b > 0:
			print("    пополнение: +%d игроку, +%d ИИ (всего рождено %d)" % [a, b, _spawned_total])
	var m: int = int(clock / 60.0)
	if m != _last_min:
		_last_min = m
		var s: Dictionary = main.telemetry.last_sample
		if not s.is_empty():
			_rows.append(s)
			print("  [%3d мин] fps %5.1f | кадр %5.2f | физтик %5.2f | логика %5.2f | живых %4d | тел %5d | стрел %3d/%4d | A* %5.1f/с | застряли %3d | паника %3d | очередь %2d | скрыто %4d" % [
				m, float(s["fps"]), float(s["frame_ms"]), float(s["phys_ms"]), float(s["vis_ms"]), int(s["units"]),
				int(s["corpses"]), int(s["arrows_flying"]), int(s["arrows_stuck"]), float(s["nav_per_sec"]),
				int(s["stuck"]), int(s["panicking"]), int(s["heal_queue"]), int(s["hidden_slow"])])
	if clock >= MINUTES * 60.0:
		Engine.time_scale = 1.0
		var s: Dictionary = main.telemetry.last_sample
		var phys: float = float(s.get("phys_ms", -1.0))
		var vis: float = float(s.get("vis_ms", -1.0))
		verdict("L1 последняя минута: физтик %.2f + кадр логики %.2f = %.2f мс ≤ 16.7 (бюджет 60 FPS)" % [phys, vis, phys + vis],
			phys >= 0.0 and vis >= 0.0 and phys + vis <= 16.7)
		verdict("L2 Pathfinding Requests %.1f/с < 100" % float(s.get("nav_per_sec", 0.0)), float(s.get("nav_per_sec", 0.0)) < 100.0)
		var units: int = maxi(int(s.get("units", 1)), 1)
		verdict("L3 застрявших %d из %d < 3 %%" % [int(s.get("stuck", 0)), units], float(int(s.get("stuck", 0))) < float(units) * 0.03)
		verdict("L4 срезов телеметрии по FPS < 30 за прогон: %d (headless — всегда 0)" % main.telemetry.spike_count(),
			main.telemetry.spike_count() == 0 or DisplayServer.get_name() == "headless")
		_finish()
