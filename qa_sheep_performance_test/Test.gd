extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЦЕНА СТАДА ОВЕЦ И ЖЁСТКИЕ ЛИМИТЫ (ТЗ 19.09.2026, блок 1)
## ═══════════════════════════════════════════════════════════════════════════
## Три загона игрока, замеры на 0 / 20 / 30 / 50 / 100 овец и при активном
## забое (четыре рабочих носят мясо). Меряется:
##   • мс физтика армии (perf_config.tick_meter) и кадра логики (vis_meter);
##   • цена овец ОТДЕЛЬНО — свои часы вокруг Sheep._process (Sheep.prof_*),
##     мкс на овцу за кадр и мс на всё стадо за кадр;
##   • стена кадра (усреднённый интервал между process_frame — в headless
##     физшаг ждёт реального времени, поэтому читать её только как A/B
##     внутри одного прогона, правило 12);
##   • число узлов сцены, вызовов отрисовки (в headless ВСЕГДА 0 — так и
##     печатается), приказов command_move (perf_config.cmd_meter).
## Точка перегиба — первое N, где стадо стоит больше KNEE_MS за кадр.
## Вердикты: цена стада на 100 овцах, лимиты (3 загона, 30 в загоне, 90 у
## игрока) и стадо при забое. Стенд молчит до конца и печатает одну таблицу.
## Запуск: godot --headless --path . res://qa_sheep_performance_test/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _Pen := preload("res://scripts/SheepPen.gd")
const _Sheep := preload("res://scripts/goblin/Sheep.gd")

## Сколько физкадров держится каждый замер
const MEASURE_FRAMES := 300
## Порог «перегиба»: стадо дороже этого за кадр — точка названа
const KNEE_MS := 1.0
## Вердикт: овца не дороже этого за кадр (мкс)
const SHEEP_USEC_MAX := 20.0
## Вердикт: сто овец не дороже этого за кадр (мс)
const FLOCK_100_MS_MAX := 2.0

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _rows: Array = []
var _pens: Array = []
var _castle: Building = null
var _base: Vector3 = Vector3.ZERO

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с"); _finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok, d])

func _finish() -> void:
	print("\n═════ ТАБЛИЦА: ЦЕНА СТАДА ═════")
	print("  %-22s %6s %8s %8s %9s %9s %8s %6s %6s %8s" % [
		"сцена", "овец", "тик мс", "лог мс", "стена мс", "стадо мс", "мкс/овц", "узлов", "draw", "приказов"])
	for r in _rows:
		print("  %-22s %6d %8.3f %8.3f %9.3f %9.3f %8.2f %6d %6d %8d" % [
			r["label"], r["sheep"], r["tick"], r["vis"], r["wall"], r["flock_ms"],
			r["per_sheep"], r["nodes"], r["draw"], r["cmds"]])
	var knee := "не достигнута до 100 овец (стадо < %.1f мс за кадр)" % KNEE_MS
	for r in _rows:
		if r["kind"] == "scale" and r["flock_ms"] >= KNEE_MS:
			knee = "%d овец (стадо %.2f мс за кадр)" % [r["sheep"], r["flock_ms"]]
			break
	print("  ТОЧКА ПЕРЕГИБА: %s" % knee)
	print("  (вызовов отрисовки в headless всегда 0 — рендера нет)")
	print("\n═════ ВЕРДИКТЫ ═════")
	for l in _log:
		print("  ВЕРДИКТ %s: %s%s" % [String(l[0]), "ПРОШЛО" if bool(l[1]) else "НЕ ПРОШЛО",
			("  — " + String(l[2])) if String(l[2]) != "" else ""])
	print("\n═════ ИТОГ qa_sheep_performance_test: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

# ─────────────────────────────────────────────────────────────────────────────
# ПЛОЩАДКА
# ─────────────────────────────────────────────────────────────────────────────
func _pen(at: Vector3) -> Building:
	var pen: Building = _Pen.new()
	pen.faction = Constants.FACTION_PLAYER
	main.world_add(pen)
	pen.global_position = Vector3(at.x, main.get_terrain_height(at.x, at.z), at.z)
	return pen

## Хозяйская овца, привязанная к загону НАПРЯМУЮ (bind_to_pen): замер обязан
## ставить и сто голов, а потолки стережёт отдельный блок
func _pen_sheep(pen: Building, at: Vector3) -> Node3D:
	var s: Node3D = _Sheep.new()
	main.world_root().add_child(s)
	s.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	s.call("bind_to_pen", pen, Constants.FACTION_PLAYER)
	return s

func _spawn_worker(at: Vector3) -> Worker:
	var w: Unit = (Building.PRELOAD_SCENES["worker"] as PackedScene).instantiate()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	w.sync_row()
	GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "worker"), w)
	return w as Worker

func _live_sheep_count() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("sheep"):
		if s != null and is_instance_valid(s) and not bool(s.get("eaten")):
			n += 1
	return n

func _fill(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		var pen: Building = _pens[i % _pens.size()]
		var k: int = i / _pens.size()
		var ang: float = float(k) * 2.399963
		var rr: float = 1.0 + 0.35 * sqrt(float(k))
		var p: Vector3 = pen.global_position + Vector3(cos(ang) * rr, 0.0, sin(ang) * rr)
		out.append(_pen_sheep(pen, p))
	return out

func _free_all(list: Array) -> void:
	for s in list:
		if s != null and is_instance_valid(s):
			(s as Node).queue_free()
	await pframes(3)

# ─────────────────────────────────────────────────────────────────────────────
# ЗАМЕР
# ─────────────────────────────────────────────────────────────────────────────
func _measure(label: String, kind: String) -> Dictionary:
	# Разогрев: первые кадры после расстановки — ленты, снап к земле
	await pframes(30)
	_Opt.tick_meter = true
	_Opt.vis_meter = true
	_Opt.tick_reset()
	_Opt.vis_reset()
	_Opt.cmd_meter = true
	_Opt.cmd_reset()
	_Sheep.prof_on = true
	_Sheep.prof_reset()
	var t0: int = Time.get_ticks_usec()
	var pf0: int = Engine.get_physics_frames()
	var draw_max: int = 0
	var nframes := 0
	while Engine.get_physics_frames() - pf0 < MEASURE_FRAMES:
		await get_tree().process_frame
		nframes += 1
		draw_max = maxi(draw_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var wall_us: int = Time.get_ticks_usec() - t0
	var pfr: int = Engine.get_physics_frames() - pf0
	_Sheep.prof_on = false
	var sheep_n: int = _live_sheep_count()
	var row := {
		"label": label, "kind": kind, "sheep": sheep_n,
		"tick": _Opt.tick_ms(), "vis": _Opt.vis_ms(),
		"wall": float(wall_us) / 1000.0 / float(maxi(nframes, 1)),
		# Стадо за ПРОЦЕСС-кадр: часы овец копятся в _process, делим на число
		# кадров отрисовки, а не физкадров
		"flock_ms": float(_Sheep.prof_usec) / 1000.0 / float(maxi(nframes, 1)),
		"per_sheep": (float(_Sheep.prof_usec) / float(_Sheep.prof_calls)) if _Sheep.prof_calls > 0 else 0.0,
		"nodes": get_tree().get_node_count(),
		"draw": draw_max,
		"cmds": _Opt.cmd_total,
		"pframes": pfr, "frames": nframes,
	}
	_Opt.tick_meter = false
	_Opt.vis_meter = false
	_Opt.cmd_meter = false
	_rows.append(row)
	return row

# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if main.get("goblin_reserve") != null:
		main.goblin_reserve.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	# Дикие стада и стражи логов — не участники замера: тролли спят, овцы
	# логов убираются (иначе они же попадут в часы Sheep.prof_*)
	for lair in GameManager.troll_lairs:
		if lair == null or not is_instance_valid(lair):
			continue
		for t in lair.get("trolls"):
			if t != null and is_instance_valid(t):
				(t as Unit).set_tick(false)
		for g in lair.get("gnolls"):
			if g != null and is_instance_valid(g):
				(g as Node).queue_free()
		for s in lair.get("sheep"):
			if s != null and is_instance_valid(s):
				(s as Node).queue_free()
	await pframes(4)
	_base = main.PLAYER_BASE_ANCHOR + Vector3(-30.0, 0.0, 30.0)
	main._clear_area_of_resources(_base, 45.0)
	_castle = Castle.new()
	_castle.faction = Constants.FACTION_PLAYER
	main.world_add(_castle)
	var cp: Vector3 = _base + Vector3(0.0, 0.0, -24.0)
	_castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	for i in range(3):
		_pens.append(_pen(_base + Vector3(-22.0 + 22.0 * float(i), 0.0, 4.0)))
	await pframes(6)

	# ── БАЗА: ноль овец ────────────────────────────────────────────────────
	var base_row: Dictionary = await _measure("0 овец (база)", "base")
	var rows_by_n: Dictionary = {}
	for n in [20, 30, 50, 100]:
		var flock: Array = _fill(n)
		var r: Dictionary = await _measure("%d овец" % n, "scale")
		rows_by_n[n] = r
		await _free_all(flock)
	# ── ЗАБОЙ: сто овец, четверо рабочих носят мясо ───────────────────────
	var flock2: Array = _fill(100)
	var workers: Array = []
	for i in range(4):
		var w: Worker = _spawn_worker(_pens[i % 3].global_position + Vector3(3.0, 0.0, 4.0 + float(i)))
		workers.append(w)
	await pframes(4)
	for i in range(4):
		(workers[i] as Worker).command_steal_sheep(flock2[i * 7])
	# Дать разделке начаться: пять ударов до смерти, десять на кусок и первая
	# ходка — ждём СВОЙСТВО (первая ходка у кого-то из четырёх), потолок 40 с
	var gw := 0
	while gw < 60 * 40:
		await get_tree().physics_frame
		gw += 1
		var any_haul := false
		for w in workers:
			if (w as Worker).sheep_trips() >= 1:
				any_haul = true
		if any_haul:
			break
	var busy := 0
	for w in workers:
		if (w as Worker).is_stealing_sheep():
			busy += 1
	var r_butcher: Dictionary = await _measure("100 овец + забой ×4", "butcher")
	var hauls := 0
	for w in workers:
		hauls += (w as Worker).sheep_trips()
	await _free_all(flock2)
	for w in workers:
		if is_instance_valid(w):
			(w as Unit).take_damage(1.0e9)
	await pframes(3)

	# ── ВЕРДИКТЫ ПО ЦЕНЕ ──────────────────────────────────────────────────
	var r100: Dictionary = rows_by_n[100]
	verdict("P1 сто овец: не дороже %.1f мкс на овцу за кадр" % SHEEP_USEC_MAX,
		r100["per_sheep"] <= SHEEP_USEC_MAX, "%.2f мкс/овцу" % r100["per_sheep"])
	verdict("P2 сто овец: стадо не дороже %.1f мс за кадр" % FLOCK_100_MS_MAX,
		r100["flock_ms"] <= FLOCK_100_MS_MAX, "%.3f мс за кадр" % r100["flock_ms"])
	verdict("P3 физтик армии от овец не растёт (они не в ядре): +%.3f мс против базы" % (r100["tick"] - base_row["tick"]),
		r100["tick"] - base_row["tick"] <= 0.5,
		"база %.3f, сто овец %.3f" % [base_row["tick"], r100["tick"]])
	verdict("P4 узлов на овцу — не больше 4 (узел, спрайт, тело, форма)",
		(r100["nodes"] - base_row["nodes"]) <= 4 * 100 + 8,
		"узлов +%d на %d овец" % [r100["nodes"] - base_row["nodes"], r100["sheep"]])
	verdict("P5 забой идёт: четверо рабочих при деле, ходок с мясом %d" % hauls,
		busy == 4 and hauls >= 1, "занятых %d из 4, ходок %d" % [busy, hauls])
	verdict("P6 при забое стадо не дороже %.1f мс за кадр" % FLOCK_100_MS_MAX,
		r_butcher["flock_ms"] <= FLOCK_100_MS_MAX, "%.3f мс" % r_butcher["flock_ms"])

	# ── ЛИМИТЫ ────────────────────────────────────────────────────────────
	await _limits()
	_finish()

func _limits() -> void:
	# L1 вместимость загона 30 из конфига
	var pen: Building = _pens[0]
	verdict("L1 вместимость загона = SHEEP_PEN_CAPACITY = %d" % _UCfg.SHEEP_PEN_CAPACITY,
		int(pen.call("capacity")) == _UCfg.SHEEP_PEN_CAPACITY and _UCfg.SHEEP_PEN_CAPACITY == 30,
		"capacity() = %d" % int(pen.call("capacity")))
	# L2 тридцать первую загон не принимает (accept_sheep)
	var flock: Array = []
	var taken := 0
	for i in range(_UCfg.SHEEP_PEN_CAPACITY + 1):
		var s: Node3D = _Sheep.new()
		main.world_root().add_child(s)
		var p: Vector3 = pen.global_position + Vector3(float(i % 6) - 2.5, 0.0, float(i / 6) - 2.5)
		s.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		s.set("owner_faction", Constants.FACTION_PLAYER)
		flock.append(s)
		if bool(pen.call("accept_sheep", s)):
			taken += 1
	verdict("L2 загон принял ровно %d, %d-ю отверг" % [_UCfg.SHEEP_PEN_CAPACITY, _UCfg.SHEEP_PEN_CAPACITY + 1],
		taken == _UCfg.SHEEP_PEN_CAPACITY and not bool(pen.call("has_room")),
		"принято %d, has_room=%s" % [taken, str(pen.call("has_room"))])
	# Отвергнутая осталась бы блуждающей овцой игрока и шла бы в зачёт потолка
	# — убираем её, чтобы L3 считал ровно привязанных
	var rejected: Node3D = flock.pop_back()
	rejected.queue_free()
	await pframes(2)
	# L3 потолок 90 у игрока: два других загона по 30 → 90 привязано,
	# приплод не рождается, замок не принимает
	var more: Array = []
	for k in range(1, 3):
		for i in range(_UCfg.SHEEP_PEN_CAPACITY):
			var s2: Node3D = _Sheep.new()
			main.world_root().add_child(s2)
			var p2: Vector3 = _pens[k].global_position + Vector3(float(i % 6) - 2.5, 0.0, float(i / 6) - 2.5)
			s2.global_position = Vector3(p2.x, GameManager.get_terrain_height(p2.x, p2.z), p2.z)
			s2.set("owner_faction", Constants.FACTION_PLAYER)
			more.append(s2)
			_pens[k].call("accept_sheep", s2)
	await pframes(2)
	var owned: int = int(_Sheep.owned_count(Constants.FACTION_PLAYER))
	verdict("L3 у игрока ровно SHEEP_PLAYER_MAX = %d овец" % _UCfg.SHEEP_PLAYER_MAX,
		owned == _UCfg.SHEEP_PLAYER_MAX and _UCfg.SHEEP_PLAYER_MAX == 90, "привязано %d" % owned)
	var s_any: Node3D = flock[0]
	s_any.set("_calm_t", 1.0e6)
	var born: int = int(s_any.call("breed_one"))
	verdict("L4 на потолке 90 приплод не рождается (breed_one → 0)", born == 0, "родилось %d" % born)
	verdict("L5 на потолке 90 замок овцу не принимает (owned_cap_ok=false)",
		not bool(_Sheep.owned_cap_ok(Constants.FACTION_PLAYER)))
	# L6 после освобождения места приплод снова идёт
	var victim: Node3D = flock[taken - 1]
	victim.call("eat")
	await pframes(2)
	var born2: int = int(s_any.call("breed_one"))
	verdict("L6 освободилось место — приплод снова родился", born2 == 1 and _Sheep.owned_cap_ok(Constants.FACTION_PLAYER) == false,
		"родилось %d, снова на потолке=%s" % [born2, str(not _Sheep.owned_cap_ok(Constants.FACTION_PLAYER))])
	# L7 загонов не больше трёх: четвёртый не ставится, ресурсы не списаны
	var w: Worker = _spawn_worker(_base + Vector3(0.0, 0.0, 16.0))
	await pframes(2)
	verdict("L7 три загона стоят — четвёртый запрещён (sheep_pen_allowed=false)",
		GameManager.sheep_pen_total(Constants.FACTION_PLAYER) == 3
			and not GameManager.sheep_pen_allowed(Constants.FACTION_PLAYER)
			and _UCfg.SHEEP_PEN_MAX_COUNT == 3,
		"загонов %d" % GameManager.sheep_pen_total(Constants.FACTION_PLAYER))
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD, 1000.0)
	var wood0: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD)
	var pens0: int = get_tree().get_nodes_in_group("sheep_pens").size()
	# Приказ рабочего идёт через тот же путь, что и кнопка панели: отказ стоит
	# ДО списания и до режима размещения (как у крепости)
	GameManager.try_worker_build(w, "sheep_pen")
	await pframes(3)
	var pens1: int = get_tree().get_nodes_in_group("sheep_pens").size()
	verdict("L8 попытка четвёртого загона: не поставлен и дерево не списано",
		pens1 == pens0 and is_equal_approx(ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD), wood0),
		"загонов %d → %d, дерево %.0f → %.0f" % [pens0, pens1, wood0,
			ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD)])
	# L9 снесли один — снова можно
	var gone: Building = _pens[2]
	_pens.remove_at(2)
	gone.queue_free()
	await pframes(3)
	verdict("L9 снесли загон — третий снова разрешён",
		GameManager.sheep_pen_total(Constants.FACTION_PLAYER) == 2
			and GameManager.sheep_pen_allowed(Constants.FACTION_PLAYER))
	await _free_all(flock)
	await _free_all(more)
