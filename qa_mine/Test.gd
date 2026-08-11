extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: КОЛЬЦО РАБОЧИХ МЕСТ У ЖИЛЫ И СЧЁТЧИК ПРОСТОЯ
## ═══════════════════════════════════════════════════════════════════════════
##   A КОЛЬЦО     — слоты размечены снаружи силуэта, не в центре
##   B РАСПРЕДЕЛЕНИЕ — бригада обступает камень, никто не лезет внутрь
##   C ОСВОБОЖДЕНИЕ — слот отдаётся при смене приказа и при смерти
##   D ДОБЫЧА     — со слота рабочий реально дотягивается и копает
##   E ПРОСТОЙ    — счётчик видит рабочего, который дошёл и встал

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n: out += " "
	return out

func _new_node(rtype: int, at: Vector3, scale_v: float = 1.0) -> ResourceNode:
	var r := ResourceNode.new()
	r.resource_type = rtype
	r.size_scale    = scale_v
	r.remaining     = 100000.0
	main.world_add(r)
	r.global_position = at
	return r

func _new_worker(at: Vector3) -> Worker:
	var w := Worker.new()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = at
	return w

## Расстояние по горизонтали
func _hd(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	await _a_ring()
	await _b_spread()
	await _c_release()
	await _d_gather()
	await _e_idle()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 60), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== MINE TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ГЕОМЕТРИЯ КОЛЬЦА
# ═════════════════════════════════════════════════════════════════════════════
func _a_ring() -> void:
	print("\n═════ A. ГЕОМЕТРИЯ КОЛЬЦА ═════")
	for sc in [0.65, 1.0, 1.6]:
		var s: float = sc
		var g := _new_node(Constants.RESOURCE_GOLD, Vector3(0, 0, -300 - s * 30), s)
		await frames(2)
		var n: int = g.slot_count()
		var r: float = g.slot_radius()
		# Слот обязан лежать СНАРУЖИ коллайдера жилы (0.85 * size_scale)
		var body_r: float = 0.85 * s
		var outside := true
		var dists: Array = []
		for i in range(n):
			var d: float = _hd(g.slot_position(i), g.global_position)
			dists.append(snappedf(d, 0.01))
			if d <= body_r + 0.05:
				outside = false
		print("  scale %.2f: слотов %d, радиус %.2f, тело %.2f" % [s, n, r, body_r])
		verdict("A размер %.2f: слоты снаружи силуэта" % s, outside,
			"радиус слота %.2f против тела %.2f" % [r, body_r])
		verdict("A размер %.2f: слотов от 4 до 12" % s, n >= 4 and n <= 12, "%d" % n)
		g.queue_free()
		await frames(2)

	# Слоты не совпадают между собой — это кольцо, а не одна точка
	var g2 := _new_node(Constants.RESOURCE_GOLD, Vector3(0, 0, -360), 1.0)
	await frames(2)
	var uniq: Dictionary = {}
	for i in range(g2.slot_count()):
		uniq[str(g2.slot_position(i).snapped(Vector3(0.01, 1, 0.01)))] = true
	verdict("A слоты кольца различны", uniq.size() == g2.slot_count(),
		"уникальных %d из %d" % [uniq.size(), g2.slot_count()])
	g2.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. БРИГАДА ОБСТУПАЕТ КАМЕНЬ, А НЕ ЛЕЗЕТ ВНУТРЬ
# Главный баг: раньше все шли в global_position жилы и дрожали в одной точке.
# ═════════════════════════════════════════════════════════════════════════════
func _b_spread() -> void:
	print("\n═════ B. РАСПРЕДЕЛЕНИЕ БРИГАДЫ ═════")
	var ore := _new_node(Constants.RESOURCE_GOLD, Vector3(0, 0, -400), 1.6)
	await frames(2)
	var crew: Array = []
	for i in range(6):
		crew.append(_new_worker(Vector3(-12 + i * 0.8, 0, -412)))
	await frames(3)
	for w in crew:
		(w as Worker).command_gather(ore)

	# Даём дойти и улечься
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame

	var body_r: float = 0.85 * ore.size_scale
	var inside := 0
	var min_pair := INF
	var arrived := 0
	for w in crew:
		var p: Vector3 = (w as Node3D).global_position
		var d: float = _hd(p, ore.global_position)
		if d < body_r:
			inside += 1
		if d < ore.slot_radius() + 1.2:
			arrived += 1
	for i in range(crew.size()):
		for j in range(i + 1, crew.size()):
			var dd: float = _hd((crew[i] as Node3D).global_position,
				(crew[j] as Node3D).global_position)
			min_pair = minf(min_pair, dd)
	print("  внутри силуэта: %d, дошли до кольца: %d, минимальный зазор между рабочими: %.2f м"
		% [inside, arrived, min_pair])
	verdict("B1 никто не влез внутрь текстуры жилы", inside == 0, "внутри %d" % inside)
	verdict("B2 бригада дошла до кольца", arrived >= 5, "дошло %d из 6" % arrived)
	verdict("B3 рабочие не стоят друг в друге", min_pair > 0.35,
		"минимальный зазор %.2f м" % min_pair)

	# Все ли получили РАЗНЫЕ слоты
	var slots: Dictionary = {}
	for w in crew:
		var id: int = (w as Object).get_instance_id()
		if ore._slot_owner.has(id):
			slots[int(ore._slot_owner[id])] = true
	verdict("B4 слоты бригады не пересекаются", slots.size() == crew.size(),
		"разных слотов %d на %d рабочих" % [slots.size(), crew.size()])

	# ДЁРГАНЬЕ: за секунду наблюдения рабочий на месте почти не смещается
	var before: Array = []
	for w in crew:
		before.append((w as Node3D).global_position)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		await get_tree().process_frame
	var max_drift := 0.0
	for i in range(crew.size()):
		max_drift = maxf(max_drift, _hd((crew[i] as Node3D).global_position, before[i]))
	print("  смещение за 1 с на добыче: %.3f м" % max_drift)
	verdict("B5 на месте не дёргаются", max_drift < 0.6, "%.3f м за секунду" % max_drift)

	for w in crew:
		(w as Node).queue_free()
	ore.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. СЛОТ ОСВОБОЖДАЕТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _c_release() -> void:
	print("\n═════ C. ОСВОБОЖДЕНИЕ СЛОТА ═════")
	var ore := _new_node(Constants.RESOURCE_STONE, Vector3(0, 0, -440), 1.0)
	var w := _new_worker(Vector3(-6, 0, -440))
	await frames(3)
	w.command_gather(ore)
	var id: int = w.get_instance_id()
	verdict("C1 слот забронирован", ore._slot_owner.has(id))

	# Повторный приказ на ТУ ЖЕ жилу слот не меняет
	var kept: int = int(ore._slot_owner[id])
	w.command_gather(ore)
	verdict("C2 повторный приказ слот не перевыдаёт",
		ore._slot_owner.has(id) and int(ore._slot_owner[id]) == kept)

	# Приказ идти освобождает
	w.command_move(Vector3(-20, 0, -440))
	verdict("C3 приказ идти освобождает слот", not ore._slot_owner.has(id))

	# Смерть освобождает
	w.command_gather(ore)
	var id2: int = w.get_instance_id()
	verdict("C4 слот снова занят", ore._slot_owner.has(id2))
	w.queue_free()
	await frames(3)
	verdict("C5 смерть рабочего освобождает слот", not ore._slot_owner.has(id2))

	# Перебор: рабочих больше, чем слотов — никто не уходит в центр
	var many: Array = []
	for i in range(ore.slot_count() + 4):
		many.append(_new_worker(Vector3(-10 + i * 0.5, 0, -448)))
	await frames(3)
	var to_center := 0
	for m in many:
		(m as Worker).command_gather(ore)
		var mt: Vector3 = (m as Worker).move_target
		if _hd(mt, ore.global_position) < 0.3:
			to_center += 1
	verdict("C6 при нехватке слотов никто не идёт в центр", to_center == 0,
		"в центр отправлено %d" % to_center)

	for m in many:
		(m as Node).queue_free()
	ore.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. СО СЛОТА РЕАЛЬНО ДОБЫВАЕТСЯ
# Кольцо бесполезно, если рабочий с него не дотягивается до жилы.
# ═════════════════════════════════════════════════════════════════════════════
func _d_gather() -> void:
	print("\n═════ D. ДОБЫЧА СО СЛОТА ═════")
	for sc in [0.65, 1.6]:
		var s: float = sc
		var ore := _new_node(Constants.RESOURCE_GOLD, Vector3(0, 0, -470 - s * 20), s)
		var w := _new_worker(Vector3(-8, 0, -470 - s * 20))
		await frames(3)
		var before: float = ore.remaining
		w.command_gather(ore)
		var t0: int = Time.get_ticks_msec()
		var reached_state := false
		while Time.get_ticks_msec() - t0 < 12000:
			await get_tree().process_frame
			if w.state == Unit.State.GATHERING or w.carrying_amount > 0.0:
				reached_state = true
				break
		verdict("D размер %.2f: рабочий добрался и копает" % s, reached_state,
			"state=%d, дистанция %.2f" % [w.state, _hd(w.global_position, ore.global_position)])
		w.queue_free(); ore.queue_free()
		await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. СЧЁТЧИК ПРОСТОЯ
# ═════════════════════════════════════════════════════════════════════════════
func _e_idle() -> void:
	print("\n═════ E. СЧЁТЧИК ПРОСТОЯ ═════")
	var hud = main.hud
	# Рабочий, которого послали ИДТИ и который дошёл, — простаивает
	var w := _new_worker(Vector3(0, 0, -500))
	await frames(3)
	w.command_move(Vector3(6, 0, -500))
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		if w.state == Unit.State.IDLE:
			break
	var idle1: Array = hud._idle_workers()
	verdict("E1 дошедший до точки и вставший — в счётчике", w in idle1,
		"state=%d, в списке %d" % [w.state, idle1.size()])

	# Рабочий на добыче в счётчик НЕ попадает
	var ore := _new_node(Constants.RESOURCE_GOLD, Vector3(10, 0, -500), 1.0)
	await frames(2)
	w.command_gather(ore)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
		if w.state == Unit.State.GATHERING:
			break
	var idle2: Array = hud._idle_workers()
	verdict("E2 работающий в счётчик не попадает", not (w in idle2),
		"state=%d, в списке %d" % [w.state, idle2.size()])

	# Застрявший (IDLE с целью) — попадает
	w.state = Unit.State.IDLE
	w.carrying_amount = 0.0
	var idle3: Array = hud._idle_workers()
	verdict("E3 застрявший у жилы — в счётчике", w in idle3, "в списке %d" % idle3.size())

	w.queue_free(); ore.queue_free()
	await frames(2)
