extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СЕТКА ОТРЯДОВ, ПРОХОД СКВОЗЬ СВОИХ, ВОЗВРАТ В СТРОЙ
## ═══════════════════════════════════════════════════════════════════════════
##   A. СЕТКА ГРУПП — 2/3/4/5 отрядов по клику в одну точку встают блоками и не
##      сваливаются в кучу; при 3-4 центральный отряд стоит РОВНО в точке клика;
##   B. ПРОХОД СКВОЗЬ СВОИХ — отряд, которому приказали пройти через плотный
##      строй союзников, доходит до точки, а не упирается в них;
##   C. ВОЗВРАТ В СТРОЙ — после боя отряд снова стоит блоком и смотрит в одну
##      сторону, даже если строевого приказа ему никогда не давали.
##
## Запуск: godot --headless --path . res://qa_group_grid/Test.tscn

var main = null
var sm = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## physics_frame: при Engine.max_fps=0 рендер тикает быстрее физики, и «N
## process_frame» перестаёт значить «N/60 сек» (см. CLAUDE.md)
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

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

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	return u

func _squad(kind: String, fac: int, center: Vector3, count: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(count):
		var p := center + Vector3(float(i % 5) * 0.6, 0.0, float(i / 5) * 0.6)
		var u := _new(kind, fac, p)
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _centroid(arr: Array) -> Vector3:
	var live := _alive(arr)
	if live.is_empty():
		return Vector3.INF
	var c := Vector3.ZERO
	for u in live:
		c += (u as Unit).global_position
	return c / float(live.size())

func _cleanup(groups: Array) -> void:
	for g in groups:
		for u in g:
			if is_instance_valid(u):
				(u as Node).queue_free()
	await frames(3)

func _run() -> void:
	seed(777)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	sm = main.selection_manager
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  СЕТКА ОТРЯДОВ / ПРОХОД СКВОЗЬ СВОИХ / ВОЗВРАТ В СТРОЙ           ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	await _a_group_grid()
	await _b_through_allies()
	await _c_reform_after_fight()

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %s%s" % [_pad(String(row[0]), 58),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== GROUP GRID TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. СЕТКА ГРУПП
# ═════════════════════════════════════════════════════════════════════════════

## Развести n отрядов по карте, отдать им общий приказ в одну точку и вернуть
## список их центров масс после прихода
func _grid_case(tag: String, n: int, base: Vector3, target: Vector3) -> Array:
	var squads: Array = []
	var all: Array = []
	for i in range(n):
		# Стартуют КУЧНО и с перехлёстом — именно из такой позиции старый приказ
		# и приводил их в одну точку
		var s := _squad("spearman", Constants.FACTION_PLAYER,
			base + Vector3(float(i) * 1.5, 0.0, 0.0), 9)
		squads.append(s)
		all.append_array(s)
	await frames(5)

	sm.selected_units = all.duplicate()
	sm._issue_formation_move(target, false)

	# Ждём прихода: отряды идут своим ходом, порог — по расстоянию
	for _i in range(2400):
		await get_tree().physics_frame
		var settled := 0
		for u in all:
			if is_instance_valid(u) and (u as Unit).state == Unit.State.IDLE:
				settled += 1
		if settled >= all.size() - 2:
			break

	var centres: Array = []
	for s in squads:
		centres.append(_centroid(s as Array))
	print("  [%s] центры отрядов:" % tag)
	for c in centres:
		print("      (%.1f, %.1f)" % [(c as Vector3).x, (c as Vector3).z])
	return [squads, centres, all]

func _a_group_grid() -> void:
	print("\n═════ A. СЕТКА ГРУПП ═════")

	# ── A1/A2: ДВА ОТРЯДА ────────────────────────────────────────────────────
	var t2 := Vector3(-300, 0, 0)
	var r2: Array = await _grid_case("2 отряда", 2, Vector3(-300, 0, -40), t2)
	var c2: Array = r2[1]
	var gap2: float = (c2[0] as Vector3).distance_to(c2[1] as Vector3)
	# Блоки по 9 бойцов с интервалом 0.6 — это ~2 м в поперечнике. Разъехаться
	# они обязаны заметно дальше собственного размера, иначе это и есть «куча»
	verdict("A1 два отряда встали раздельно, а не в одну кучу", gap2 >= 4.0,
		"между центрами %.1f м" % gap2)
	var mid2: Vector3 = ((c2[0] as Vector3) + (c2[1] as Vector3)) * 0.5
	verdict("A2 середина между блоками — это точка клика",
		Vector2(mid2.x - t2.x, mid2.z - t2.z).length() <= 4.0,
		"середина (%.1f, %.1f), клик (%.1f, %.1f)" % [mid2.x, mid2.z, t2.x, t2.z])
	await _cleanup([r2[2]])

	# ── A3/A4: ТРИ ОТРЯДА — ЦЕНТРАЛЬНЫЙ РОВНО В ТОЧКЕ КЛИКА ─────────────────
	var t3 := Vector3(-150, 0, 0)
	var r3: Array = await _grid_case("3 отряда", 3, Vector3(-150, 0, -40), t3)
	var c3: Array = r3[1]
	var best_d := INF
	for c in c3:
		best_d = minf(best_d, Vector2((c as Vector3).x - t3.x, (c as Vector3).z - t3.z).length())
	verdict("A3 при трёх отрядах центральный стоит в точке клика", best_d <= 4.0,
		"ближайший центр в %.1f м от клика" % best_d)
	var min_gap3 := INF
	for i in range(c3.size()):
		for j in range(i + 1, c3.size()):
			min_gap3 = minf(min_gap3, (c3[i] as Vector3).distance_to(c3[j] as Vector3))
	verdict("A4 три отряда не перекрываются", min_gap3 >= 4.0,
		"минимальный просвет %.1f м" % min_gap3)
	await _cleanup([r3[2]])

	# ── A5: ПЯТЬ ОТРЯДОВ — ПРЯМОУГОЛЬНАЯ СЕТКА, ВСЕ РАЗДЕЛЬНО ───────────────
	var t5 := Vector3(100, 0, 0)
	var r5: Array = await _grid_case("5 отрядов", 5, Vector3(100, 0, -40), t5)
	var c5: Array = r5[1]
	var min_gap5 := INF
	for i in range(c5.size()):
		for j in range(i + 1, c5.size()):
			min_gap5 = minf(min_gap5, (c5[i] as Vector3).distance_to(c5[j] as Vector3))
	verdict("A5 пять отрядов стоят раздельной сеткой", min_gap5 >= 4.0,
		"минимальный просвет %.1f м" % min_gap5)
	# Сетка ceil(√5) = 3 колонки → ДВА ряда по глубине
	var depths: Array = []
	for c in c5:
		var d := snappedf((c as Vector3).z, 2.0)
		if not (d in depths):
			depths.append(d)
	verdict("A6 пять отрядов разложены в НЕСКОЛЬКО рядов, а не в линию",
		depths.size() >= 2, "различных глубин: %d" % depths.size())
	await _cleanup([r5[2]])

# ═════════════════════════════════════════════════════════════════════════════
# B. ПРОХОД СКВОЗЬ СТРОЙ СОЮЗНИКОВ
#
# Жалоба владельца: отряд, которому приказали сменить позицию, застревает,
# упершись в строй своих же копейщиков, и до точки не доходит
# ═════════════════════════════════════════════════════════════════════════════
func _b_through_allies() -> void:
	print("\n═════ B. ПРОХОД СКВОЗЬ СВОИХ ═════")
	var start := Vector3(400, 0, -30)
	var goal  := Vector3(400, 0, 30)
	var movers := _squad("spearman", Constants.FACTION_PLAYER, start, 9)
	# ПЛОТНАЯ СТЕНА СОЮЗНИКОВ ровно посередине пути: 30 копейщиков в три
	# шеренги поперёк курса. Пройти мимо неё нельзя — только сквозь
	var wall: Array = []
	var wsid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(30):
		var p := Vector3(400.0 + float(i % 10) * 0.5 - 2.5, 0.0, float(i / 10) * 0.5)
		var u := _new("spearman", Constants.FACTION_PLAYER, p)
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(wsid, u)
		wall.append(u)
	await frames(5)

	for u in movers:
		(u as Unit).command_move(goal, false, Vector3.ZERO, false, true)

	for _i in range(3600):
		await get_tree().physics_frame
		var done := 0
		for u in movers:
			if is_instance_valid(u) \
					and Vector2((u as Unit).global_position.x - goal.x,
						(u as Unit).global_position.z - goal.z).length() <= 3.0:
				done += 1
		if done >= movers.size():
			break

	var arrived := 0
	var worst := 0.0
	for u in movers:
		if not is_instance_valid(u):
			continue
		var d: float = Vector2((u as Unit).global_position.x - goal.x,
			(u as Unit).global_position.z - goal.z).length()
		worst = maxf(worst, d)
		if d <= 3.0:
			arrived += 1
	verdict("B1 отряд прошёл сквозь союзный строй и дошёл до точки",
		arrived >= movers.size() - 1,
		"дошло %d из %d, худший в %.1f м от цели" % [arrived, movers.size(), worst])

	# И НЕ ЗАСТРЯЛ ПЕРЕД СТЕНОЙ: центр масс обязан быть ЗА ней, а не перед
	var cm := _centroid(movers)
	verdict("B2 центр отряда за стеной союзников, а не перед ней",
		cm.z > 5.0, "центр по z = %.1f (стена на z≈0, цель z=%.0f)" % [cm.z, goal.z])

	await _cleanup([movers, wall])

# ═════════════════════════════════════════════════════════════════════════════
# C. ВОЗВРАТ В СТРОЙ ПОСЛЕ БОЯ
#
# Отряду НИКОГДА не давали строевого приказа — он вышел и сразу подрался.
# Раньше «строиться не во что», и после боя он оставался бесформенным пятном
# ═════════════════════════════════════════════════════════════════════════════
func _c_reform_after_fight() -> void:
	print("\n═════ C. ВОЗВРАТ В СТРОЙ ПОСЛЕ БОЯ ═════")
	var p0 := Vector3(700, 0, 0)
	var men := _squad("spearman", Constants.FACTION_PLAYER, p0, 12)
	var foes := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0, 0, 4.0), 6)
	var sid: int = (men[0] as Unit).squad_id
	# Никакой разметки строя у отряда нет — проверяем именно этот случай
	GameManager.squad_clear_formation(sid)
	await frames(5)

	for u in men:
		(u as Unit).command_attack(foes[0], true, true, true)

	# Ждём конца боя и последующего смыкания (у него свой откат и окно «недавно
	# били», см. GameManager.RECENT_HIT_WINDOW_MS)
	for _i in range(3600):
		await get_tree().physics_frame
		if _alive(foes).is_empty():
			break
	await frames(600)

	var live := _alive(men)
	verdict("C0 бой закончился, отряд жив (подготовка)",
		_alive(foes).is_empty() and live.size() >= 6,
		"выжило %d, врагов осталось %d" % [live.size(), _alive(foes).size()])

	# СТРОЙ ПОЯВИЛСЯ САМ: разметки не было, а после боя она есть
	verdict("C1 отряд получил строй, хотя приказа на построение не было",
		GameManager.squad_has_formation(sid),
		"разметка: %s" % ("есть" if GameManager.squad_has_formation(sid) else "нет"))

	# ВСЕ СМОТРЯТ В ОДНУ СТОРОНУ — «никаких фантомных солдат с копьями в
	# пустую сторону». Меряем разброс направлений взгляда
	var avg := Vector3.ZERO
	for u in live:
		avg += (u as Unit)._facing
	var spread := 0.0
	if avg.length_squared() > 1e-6:
		avg = avg.normalized()
		for u in live:
			var f: Vector3 = (u as Unit)._facing
			if f.length_squared() > 1e-6:
				spread = maxf(spread, rad_to_deg(avg.angle_to(f.normalized())))
	verdict("C2 отряд смотрит в одну сторону, а не врассыпную", spread <= 50.0,
		"максимальное расхождение взгляда %.0f°" % spread)

	# И СТОИТ БЛОКОМ, а не растянутой кишкой: разброс вокруг центра масс
	var cm := _centroid(live)
	var far := 0.0
	for u in live:
		far = maxf(far, Vector2((u as Unit).global_position.x - cm.x,
			(u as Unit).global_position.z - cm.z).length())
	verdict("C3 отряд собран в блок, а не разбросан по полю", far <= 8.0,
		"самый дальний боец в %.1f м от центра" % far)

	await _cleanup([men, foes])
	await _d_helper_returns_to_post()

# ═════════════════════════════════════════════════════════════════════════════
# D. СОСЕД, УШЕДШИЙ ПОМОГАТЬ, ВОЗВРАЩАЕТСЯ НА СВОЙ ПОСТ
#
# Заказ владельца: «соседний отряд при агро помогает ближним строем, а после
# победы полностью восстанавливает исходную позицию и шеренгу». Отличие от C:
# там отряд ПОСЛАЛИ приказом и он строится по месту боя (иначе маршировал бы
# обратно на устаревшую точку); здесь он сорвался САМ и обязан вернуться
# ═════════════════════════════════════════════════════════════════════════════
func _d_helper_returns_to_post() -> void:
	print("\n═════ D. ПОМОЩЬ СОСЕДА И ВОЗВРАТ НА ПОСТ ═════")
	var post := Vector3(1000, 0, 0)
	var helper := _squad("spearman", Constants.FACTION_PLAYER, post, 9)
	var hsid: int = (helper[0] as Unit).squad_id
	# Ставим отряд НА ПОСТ приказом игрока — именно эта точка и есть «исходная»
	for u in helper:
		(u as Unit).command_move(post, false, Vector3.FORWARD, false, true)
	for _i in range(600):
		await get_tree().physics_frame
		var idle := 0
		for u in helper:
			if is_instance_valid(u) and (u as Unit).state == Unit.State.IDLE:
				idle += 1
		if idle >= helper.size():
			break
	var home := _centroid(helper)

	# Враг появляется В СТОРОНЕ, но в пределах поводка — отряд идёт помогать САМ
	var foes := _squad("spearman", Constants.FACTION_ENEMY,
		post + Vector3(9.0, 0.0, 0.0), 4)
	for _i in range(3600):
		await get_tree().physics_frame
		if _alive(foes).is_empty():
			break
	verdict("D0 сосед сам ввязался в бой и победил (подготовка)",
		_alive(foes).is_empty() and _alive(helper).size() >= 5,
		"выжило %d, врагов %d" % [_alive(helper).size(), _alive(foes).size()])

	await frames(900)
	var back := _centroid(helper)
	var drift: float = Vector2(back.x - home.x, back.z - home.z).length()
	verdict("D1 после победы сосед вернулся на свой пост", drift <= 6.0,
		"центр сместился на %.1f м от исходной позиции" % drift)

	var live := _alive(helper)
	var avg := Vector3.ZERO
	for u in live:
		avg += (u as Unit)._facing
	var spread := 0.0
	if avg.length_squared() > 1e-6:
		avg = avg.normalized()
		for u in live:
			var f: Vector3 = (u as Unit)._facing
			if f.length_squared() > 1e-6:
				spread = maxf(spread, rad_to_deg(avg.angle_to(f.normalized())))
	verdict("D2 и восстановил шеренгу — все смотрят в одну сторону",
		spread <= 50.0, "расхождение взгляда %.0f°" % spread)

	await _cleanup([helper, foes])
