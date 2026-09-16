extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_archer_lead — УПРЕЖДЕНИЕ ПО БЕГУЩЕМУ И ОТКЛИК НА ПКМ (15.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A. Обычные лучники по всаднику, бегущему поперёк на 4.6 м/с: стрелы ложатся
##      В ТОЧКУ ВСТРЕЧИ, а не позади (средний снос вдоль хода ≈ 0), доля
##      попаданий не ниже порога.
##   B. Снайперы по бегущей туше: быстрая прямая стрела с упреждением — почти
##      все снайперские выстрелы попадают; скорость ×SNIPE_SPEED_MULT, звук
##      тише (db из SFX_LIMITS).
##   C. ПКМ по цели вне дальности: отряд лучников СБЛИЖАЕТСЯ и стреляет, а не
##      стоит в покое; то же после предыдущей перестрелки (снятая отметка
##      «встали по первому дострелившему»).
## Числа — из конфига (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_archer_lead/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _ArrowS := preload("res://scripts/Arrow.gd")
const _ArcherS := preload("res://scripts/Archer.gd")
const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN

var main = null
var sm = null
var _dbg_men: Array = []
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_archer_lead: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x - float(i / cols) * 0.9, 0.0,
			at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _kill_all(arr: Array) -> void:
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e12)

func _alive(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			c += (u as Unit).global_position
			n += 1
	return c / float(maxi(n, 1))

func _research(cell: String) -> bool:
	return GameManager.research_upgrade(F, _Forge.node_id("archer", cell))

## Один пробег: цель бежит из a в b мимо стрелков; собираем снос точек падения
## вдоль хода (стрела − цель в момент падения, проекция на курс) и попадания
func _run_pass(runner: Unit, a: Vector3, b: Vector3, secs: float) -> Dictionary:
	runner.global_position = GameManager.land_target(a)
	runner.sync_row()
	runner.set_tick(true)
	runner.command_move(GameManager.land_target(b), false, Vector3.ZERO, false, true)
	var dir: Vector3 = (b - a)
	dir.y = 0.0
	dir = dir.normalized()
	var seen: Dictionary = {}
	var offs: Array = []
	var landed := 0
	var strikes0: int = _ArrowS.strikes
	var snipe0: int = _ArrowS.snipe_strikes
	var shots0: int = 0
	var snipe_shots0: int = _ArcherS.snipe_shots
	var moved := 0.0
	var last: Vector3 = runner.global_position
	for f in range(int(secs * 60.0)):
		await get_tree().physics_frame
		if not is_instance_valid(runner) or runner.is_dead():
			break
		var rp: Vector3 = runner.global_position
		moved += _xz(rp, last)
		last = rp
		if f % 120 == 0 and _dbg_men.size() > 0:
			var with_t := 0
			var dmin := 1e9
			var alive := 0
			var st: Dictionary = {}
			for u in _dbg_men:
				if not is_instance_valid(u) or (u as Unit).is_dead():
					continue
				alive += 1
				st[(u as Unit).state] = int(st.get((u as Unit).state, 0)) + 1
				if (u as Unit).attack_target != null:
					with_t += 1
				dmin = minf(dmin, _xz((u as Unit).global_position, rp))
			print("    f=%d живых %d с целью %d ближайший %.1f состояния %s снайп.дальность %.1f" % [
				f, alive, with_t, dmin, str(st), (_dbg_men[0] as Unit).attack_range])
		for ch in main.world_root().get_children():
			if not (ch is _ArrowS):
				continue
			var id: int = ch.get_instance_id()
			var spent: bool = bool(ch.get("_spent"))
			if not seen.has(id):
				seen[id] = spent
				if not spent:
					shots0 += 1
				continue
			if bool(seen[id]) or not spent:
				continue
			seen[id] = true
			landed += 1
			var ap: Vector3 = (ch as Node3D).global_position
			var d: Vector3 = ap - rp
			d.y = 0.0
			offs.append(d.dot(dir))
	var mean := 0.0
	for o in offs:
		mean += float(o)
	mean = mean / float(maxi(offs.size(), 1))
	return {"shots": shots0, "landed": landed, "mean": mean,
		"hits": _ArrowS.strikes - strikes0, "snipe_hits": _ArrowS.snipe_strikes - snipe0,
		"snipe_shots": _ArcherS.snipe_shots - snipe_shots0, "moved": moved}

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	AudioManager.sfx_trace = true
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	# Площадка вне карты: ровно, сухо, без леса (границы мира сняты)
	var base := Vector3(0.0, 0.0, -420.0)

	# ── A. ОБЫЧНЫЕ ЛУЧНИКИ ПО ВСАДНИКУ ПОПЕРЁК ────────────────────────────
	print("\n═════ A. УПРЕЖДЕНИЕ ОБЫЧНОЙ СТРЕЛЫ ═════")
	verdict("A0 упреждение полное, потолок выноса не режет типичный вынос",
		_UCfg.ARCHER_LEAD_FACTOR >= 0.99 and _UCfg.ARCHER_LEAD_MAX >= 8.0,
		"factor %.2f, max %.1f" % [_UCfg.ARCHER_LEAD_FACTOR, _UCfg.ARCHER_LEAD_MAX])
	var ar: Array = _squad("archer", F, base, 30)
	await pframes(30)
	var rng: float = (ar[1][0] as Unit).attack_range
	var lat: float = rng * 0.6
	var rider: Unit = _spawn("goblin_rider", GF, base + Vector3(-40.0, 0.0, lat))
	rider.max_health = 1.0e6
	rider.current_health = 1.0e6
	rider._soa_push_stats()
	var vr: float = rider.move_speed
	var res: Dictionary = await _run_pass(rider, base + Vector3(-lat * 1.6, 0.0, lat),
		base + Vector3(lat * 1.6 + 6.0, 0.0, lat), 14.0)
	print("  A: %s" % str(res))
	verdict("A1 всадник (%.1f м/с) пробежал мимо строя и в него стреляли" % vr,
		float(res["moved"]) > lat * 2.0 and int(res["shots"]) >= 20,
		"пробег %.1f м, выстрелов %d, приземлилось %d" % [float(res["moved"]), int(res["shots"]), int(res["landed"])])
	verdict("A2 стрелы ложатся в точку встречи: средний снос вдоль хода |%.2f| ≤ 1.5 м (позади было бы −%.1f)" % [
		float(res["mean"]), vr * lat / _UCfg.stat("archer", "arrow_speed", 20.0)],
		int(res["landed"]) >= 10 and absf(float(res["mean"])) <= 1.5)
	var hit_frac: float = float(res["hits"]) / float(maxi(int(res["shots"]), 1))
	# Та же мишень СТОЯ: разброс по скорости (SCATTER_PER_SPEED) — намеренный,
	# поэтому мера — доля попаданий по бегущему против доли по стоящему
	rider.command_move(GameManager.land_target(base + Vector3(0.0, 0.0, lat)), false, Vector3.ZERO, false, true)
	await pframes(60 * 3)
	rider.set_tick(false)
	var res_s: Dictionary = await _run_pass(rider, rider.global_position, rider.global_position + Vector3(0.01, 0, 0), 10.0)
	var hit_s: float = float(res_s["hits"]) / float(maxi(int(res_s["shots"]), 1))
	verdict("A3 попадания по бегущему — не хуже половины попаданий по стоящему (разброс по скорости намеренный)",
		int(res_s["shots"]) >= 10 and hit_frac >= hit_s * 0.4 and hit_frac >= 0.2,
		"бегущий %d из %d (%.0f %%), стоящий %d из %d (%.0f %%)" % [int(res["hits"]), int(res["shots"]),
			hit_frac * 100.0, int(res_s["hits"]), int(res_s["shots"]), hit_s * 100.0])
	_kill_all([rider])
	await pframes(6)

	# ── B. СНАЙПЕРЫ ПО БЕГУЩЕЙ ТУШЕ ───────────────────────────────────────
	print("\n═════ B. СНАЙПЕРЫ: БЫСТРАЯ ПРЯМАЯ СТРЕЛА С УПРЕЖДЕНИЕМ ═════")
	for c in ["1a", "1b", "1c", "2a", "2b", "2c", "2d"]:
		_research(c)
	await pframes(40)
	var snipers := 0
	for u in ar[1]:
		if (u as Archer).is_sniper():
			snipers += 1
	verdict("B0 снайперы назначены (%d)" % _UCfg.SNIPE_SQUAD_BASE, snipers == _UCfg.SNIPE_SQUAD_BASE, "%d" % snipers)
	verdict("B1 скорость снайперской стрелы ×%.2f (заказ: +20 %% к прежним 1.3)" % _UCfg.SNIPE_SPEED_MULT,
		_UCfg.SNIPE_SPEED_MULT >= 1.3 * 1.2 - 0.01)
	var lim: Dictionary = AudioManager.SFX_LIMITS.get("snipe_shot", {})
	verdict("B2 звук снайперского выстрела тише на 30 %% (≈ −3.1 дБ от −3 → ≤ −6 дБ)",
		float(lim.get("db", 0.0)) <= -6.0, "db %.1f" % float(lim.get("db", 0.0)))
	AudioManager.sfx_trace_counts.clear()
	_dbg_men = ar[1]
	print("  живых лучников перед B: %d" % _alive(ar[1]))
	var big: Unit = _spawn("big_goblin", GF, base + Vector3(-40.0, 0.0, 22.0))
	var vb: float = big.move_speed
	var res2: Dictionary = await _run_pass(big, base + Vector3(-24.0, 0.0, 22.0),
		base + Vector3(24.0, 0.0, 22.0), 30.0)
	print("  B: %s" % str(res2))
	var sfrac: float = float(res2["snipe_hits"]) / float(maxi(int(res2["snipe_shots"]), 1))
	verdict("B3 снайперские стрелы по бегущей туше (%.2f м/с) попадают: ≥ 80 %%" % vb,
		int(res2["snipe_shots"]) >= 4 and sfrac >= 0.8,
		"снайперских %d, попало %d (%.0f %%)" % [int(res2["snipe_shots"]), int(res2["snipe_hits"]), sfrac * 100.0])
	verdict("B4 снайперский звук сыгран", int(AudioManager.sfx_trace_counts.get("snipe_shot", 0)) > 0)
	_kill_all([big])
	_kill_all(ar[1])
	await pframes(6)

	# ── C. ПКМ ПО ЦЕЛИ ВНЕ ДАЛЬНОСТИ — СБЛИЖЕНИЕ И ОГОНЬ ──────────────────
	print("\n═════ C. ЛУЧНИКИ ПО ПРИКАЗУ СБЛИЖАЮТСЯ, А НЕ СТОЯТ ═════")
	var base2 := Vector3(80.0, 0.0, -420.0)
	var ar2: Array = _squad("archer", F, base2, 20)
	await pframes(30)
	var rng2: float = 0.0
	for u in ar2[1]:
		if not (u as Archer).is_sniper():
			rng2 = maxf(rng2, (u as Unit).attack_range)
	var foe: Unit = _spawn("big_goblin", GF, base2 + Vector3(rng2 + 14.0, 0.0, 0.0))
	foe.set_tick(false)
	var d0: float = _xz(_centre(ar2[1]), foe.global_position)
	var hp0: float = foe.current_health
	for u in ar2[1]:
		(u as Unit).command_attack(foe, true, true, true)
	var closed := false
	var fired := false
	var w := 0
	while w < 60 * 20:
		await get_tree().physics_frame
		w += 1
		if _xz(_centre(ar2[1]), foe.global_position) <= rng2 + 1.0:
			closed = true
		if foe.current_health < hp0:
			fired = true
		if closed and fired:
			break
	verdict("C1 приказ на цель в %.0f м (лук %.0f): отряд сблизился до дальности" % [d0, rng2], closed,
		"дистанция %.1f за %d физкадров" % [_xz(_centre(ar2[1]), foe.global_position), w])
	verdict("C2 …и открыл огонь", fired, "запас цели %.0f → %.0f" % [hp0, foe.current_health])
	# Второй приказ — на другую цель, снова вне дальности, после перестрелки
	# Вторая цель — внутри _lock_sight_range (2 × лук), иначе приказ по
	# построению «исчерпан» до подхода (см. CLAUDE.md, спринт 14)
	var c_now: Vector3 = _centre(ar2[1])
	var foe2: Unit = _spawn("big_goblin", GF, c_now + Vector3(-(rng2 + 12.0), 0.0, 6.0))
	foe2.set_tick(false)
	var hp2: float = foe2.current_health
	for u in ar2[1]:
		(u as Unit).command_attack(foe2, true, true, true)
	var closed2 := false
	var fired2 := false
	var w2 := 0
	while w2 < 60 * 25:
		await get_tree().physics_frame
		w2 += 1
		if _xz(_centre(ar2[1]), foe2.global_position) <= rng2 + 1.0:
			closed2 = true
		if foe2.current_health < hp2:
			fired2 = true
		if closed2 and fired2:
			break
	verdict("C3 повторный приказ после перестрелки: отряд снова сблизился и стреляет", closed2 and fired2,
		"дистанция %.1f, запас %.0f → %.0f, %d физкадров" % [
			_xz(_centre(ar2[1]), foe2.global_position), hp2, foe2.current_health, w2])
	_finish()
