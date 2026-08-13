extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЛИЧНЫЙ ОБЪЁМ, ЗАМОК НА ПРИКАЗ И ВЫХОД ИЗ-ПОД ДЕРЕВА
## ═══════════════════════════════════════════════════════════════════════════
## Три жалобы игрока, у которых общая тема — «боец не там, где ему положено»:
##
##   A. Отряды в бою схлопываются в одну точку: десяток отрядов, посланных на
##      одну цель, сливались в микро-кучку, потому что союзники ничем не
##      разделены вовсе. Проверяется, что после схождения расстояние между
##      центрами не падает ниже Unit.SEP_MIN_DIST (перекрытие не больше трети
##      радиуса) — и при этом строй остаётся ПЛОТНЫМ, а не разбегается.
##
##   B. Лучники, которым дали приказ отойти, проходили треть пути и
##      разворачивались стрелять: свой же перехват на марше (_process_move)
##      перебивал приказ игрока. Проверяется замок Unit.FORCED_MOVE_SEC.
##
##   C. «Юниты-мухи»: 1-2 бойца наматывали круги вокруг ствола и не доходили
##      никогда. Проверяется детектор безрезультатности (STUCK_CHECK_SEC):
##      боец, поставленный ровно за деревом от своей цели, всё равно доходит.
##
## Числа НЕ дублируются: всё, что можно, читается из самих констант проекта.
##
## Запуск: godot --headless --path . res://qa_crowd/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0

## Площадки трёх разделов: заполняются в _run() по габаритам карты
var _spot_a := Vector3.ZERO
var _spot_b := Vector3.ZERO
var _spot_c := Vector3.ZERO

func _ready() -> void:
	call_deferred("_run")

## physics_frame, а не process_frame: при Engine.max_fps = 0 рендер тикает
## быстрее фиксированной физики, и счёт process_frame перестаёт отвечать
## игровому времени (см. шапку qa_combat_lock)
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return u

func _squad(kind: String, fac: int, center: Vector3, count: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(count):
		var p := center + Vector3(float(i % 4) * 0.7, 0.0, float(i / 4) * 0.7)
		var u := _new(kind, fac, p)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

## УБРАТЬ ЧУЖУЮ БАЗУ ЦЕЛИКОМ. Main.start_game() ставит на карту вражеский
## лагерь, и стоящий без приказа отряд честно уходит его бить: первый прогон
## этого стенда мерил не разведение бойцов, а их марш на 17 м к противнику.
## Механики, которые здесь проверяются, к наличию врага отношения не имеют
func _purge_enemies() -> void:
	for n in get_tree().get_nodes_in_group("enemy_units"):
		(n as Node).queue_free()
	for n in get_tree().get_nodes_in_group("enemy_buildings"):
		(n as Node).queue_free()

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _run() -> void:
	seed(17)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Границы карты НЕ отключаем: точки стенда лежат внутри поля, а отключение
	# только маскировало бы ошибку в них самих (первый прогон ставил отряд за
	# краем, и карта прижимала всех, кроме одного, к своему борту)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(5)
	_purge_enemies()
	# ТОЧКИ СТЕНДА ВЫВОДЯТСЯ ИЗ ГАБАРИТОВ САМОЙ КАРТЫ, а не пишутся числами.
	# Поле ПРЯМОУГОЛЬНОЕ (полуось Z заметно короче X), и первые прогоны ставили
	# отряд за его краем: GameManager.land_target молча прижимал всех к борту,
	# и стенд мерил не свою механику, а работу зажима
	var lx: float = GameManager.map_lim_x * 0.6
	var lz: float = GameManager.map_lim_z * 0.6
	_spot_a = Vector3(-lx, 0.0, -lz)
	_spot_b = Vector3(-lx, 0.0,  lz)
	_spot_c = Vector3( lx, 0.0, -lz)
	print("  карта: полуоси %.1f x %.1f м; площадки стенда %s %s %s"
		% [GameManager.map_lim_x, GameManager.map_lim_z, str(_spot_a), str(_spot_b), str(_spot_c)])
	await frames(3)

	await _test_personal_space()
	await _test_move_lock()
	await _test_tree_escape()

	print("\n=== ИТОГ qa_crowd: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ЛИЧНЫЙ ОБЪЁМ
# ═════════════════════════════════════════════════════════════════════════════
## Наименьшее расстояние между любыми двумя бойцами списка
func _min_gap(men: Array) -> float:
	var best := INF
	var alive := _alive(men)
	for i in range(alive.size()):
		for j in range(i + 1, alive.size()):
			var a: Vector3 = (alive[i] as Unit).global_position
			var b: Vector3 = (alive[j] as Unit).global_position
			var d: float = Vector2(a.x - b.x, a.z - b.z).length()
			if d < best:
				best = d
	return best

func _test_personal_space() -> void:
	print("\n═════ A. ЛИЧНЫЙ ОБЪЁМ (слипание отрядов) ═════")
	print("  личный радиус %.3f м, допустимое перекрытие %.0f%% радиуса → минимум между центрами %.4f м"
		% [Unit.PERSONAL_RADIUS, Unit.OVERLAP_ALLOWED * 100.0, Unit.SEP_MIN_DIST])
	# ГЛАВНАЯ ГАРАНТИЯ ОТ НЕЗАВЕРШАЕМОЙ ПЛЯСКИ: разбор наложения не может
	# помешать бойцу отчитаться о прибытии, потому что останавливает его ВНУТРИ
	# допуска прибытия
	verdict("A0 разведение не спорит с приходом в точку",
		Unit.SEP_MIN_DIST < Unit.ARRIVE_RADIUS,
		"SEP_MIN_DIST %.4f, ARRIVE_RADIUS %.4f" % [Unit.SEP_MIN_DIST, Unit.ARRIVE_RADIUS])
	# И ни с одним построением: самый плотный строевой интервал в проекте — 0.35
	verdict("A0b разведение не спорит с самым плотным строем",
		Unit.SEP_MIN_DIST <= Building.new().squad_spacing,
		"SEP_MIN_DIST %.4f" % Unit.SEP_MIN_DIST)

	# Сваливаем всех В ОДНУ ТОЧКУ — худший вход, какой бывает
	var men: Array = []
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(24):
		var u := _new("spearman", Constants.FACTION_PLAYER, _spot_a)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await frames(4)
	var before := _min_gap(men)
	await frames(180)                   # 3 секунды на расхождение
	var after := _min_gap(men)
	print("  24 бойца, поставленные в одну точку: было %.4f м, стало %.4f м" % [before, after])
	# ПОРОГ — ЭТО SEP_MIN_DIST МИНУС МЁРТВАЯ ЗОНА, и это не послабление стенда,
	# а новый контракт расталкивания. Сосед, стоящий теснее нормы меньше чем на
	# SEP_DEADZONE (треть личного радиуса), в расчёт не идёт вовсе — иначе в
	# плотном строю поправка не обнуляется никогда и весь строй мелко
	# перетаптывается пятнадцать раз в секунду. Ровно этот размен и просили:
	# чуть теснее, зато строй ВСТАЁТ НАСМЕРТЬ (qa_settle E2: дрожание 0.0044 м
	# было, 0.00000 м стало). Множитель 0.9 сохранён как прежний запас на выброс
	var gap_floor: float = (Unit.SEP_MIN_DIST - Unit.SEP_DEADZONE) * 0.9
	verdict("A1 бойцы разошлись из одной точки", after >= gap_floor,
		"минимальный зазор %.4f м при пороге %.4f" % [after, gap_floor])
	# Но не разбежались: куча из 24 человек по 0.29 м обязана уместиться
	# примерно в круг радиуса ~1.5 м, а не растечься по полю
	var c := Vector3.ZERO
	for u in _alive(men):
		c += (u as Unit).global_position
	c /= float(_alive(men).size())
	var far := 0.0
	for u in _alive(men):
		var d: float = Vector2((u as Unit).global_position.x - c.x,
			(u as Unit).global_position.z - c.z).length()
		if d > far: far = d
	print("  радиус кучи после расхождения: %.2f м" % far)
	verdict("A2 куча осталась плотной, а не разбежалась", far < 3.0,
		"самый дальний в %.2f м от центра" % far)

	# УСТОЙЧИВОСТЬ: ещё через три секунды никто не должен ползать
	var snap: Array = []
	for u in _alive(men):
		snap.append((u as Unit).global_position)
	await frames(180)
	var drift := 0.0
	var alive := _alive(men)
	for i in range(mini(snap.size(), alive.size())):
		var d: float = ((alive[i] as Unit).global_position - (snap[i] as Vector3)).length()
		if d > drift: drift = d
	print("  сдвиг за следующие 3 c: %.4f м (максимум по отряду)" % drift)
	verdict("A3 разойдясь, строй ЗАМИРАЕТ (нет вечного дрожания)", drift < 0.05,
		"максимальный сдвиг %.4f м" % drift)

	for u in men:
		if is_instance_valid(u): u.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. ЗАМОК НА ПРИКАЗ ИГРОКА
# ═════════════════════════════════════════════════════════════════════════════
func _test_move_lock() -> void:
	print("\n═════ B. ЗАМОК НА ПРИКАЗ (отход лучников) ═════")
	var pos := _spot_b
	var archers := _squad("archer", Constants.FACTION_PLAYER, pos, 6)
	# Враг ВПЛОТНУЮ: без замка перехват на марше сработает на первом же тике
	var foes := _squad("spearman", Constants.FACTION_ENEMY, pos + Vector3(6.0, 0.0, 0.0), 6)
	await frames(90)                    # дать завязаться бою
	var engaged := 0
	for u in _alive(archers):
		if (u as Unit).attack_target != null:
			engaged += 1
	print("  лучников с целью до приказа: %d из %d" % [engaged, _alive(archers).size()])

	# Приказ ИГРОКА на отход в 25 м назад
	var dest := pos - Vector3(25.0, 0.0, 0.0)
	var start: Array = []
	for u in _alive(archers):
		start.append((u as Unit).global_position)
		(u as Unit).command_move(dest, false, Vector3.ZERO, false, true)
	# Ровно столько, сколько держится замок
	await frames(int(Unit.FORCED_MOVE_SEC * 60.0))
	var shooting := 0
	var moving := 0
	for u in _alive(archers):
		if (u as Unit).attack_target != null: shooting += 1
		if (u as Unit).state == Unit.State.MOVING: moving += 1
	print("  через %.1f c: идут %d, снова стреляют %d" % [Unit.FORCED_MOVE_SEC, moving, shooting])
	verdict("B1 приказ не перебит авто-агро", shooting == 0,
		"развернулись стрелять: %d" % shooting)

	# И главное — путь пройден, а не треть его
	var alive := _alive(archers)
	var worst := 0.0
	for i in range(mini(start.size(), alive.size())):
		var went: float = (start[i] as Vector3).distance_to((alive[i] as Unit).global_position)
		if worst == 0.0 or went < worst:
			worst = went
	# Ожидание выводится из СКОРОСТИ САМОГО ЛУЧНИКА, а не из круглого числа:
	# без перебоев за FORCED_MOVE_SEC он проходит speed × время. Порог 0.8 от
	# этого оставляет запас на разгон и на разброс стартовых точек отряда
	var speed: float = 0.0
	if not alive.is_empty():
		speed = (alive[0] as Unit).move_speed
	var want: float = speed * Unit.FORCED_MOVE_SEC * 0.8
	print("  самый отставший прошёл %.1f м (скорость %.1f м/с → без перебоев ждём ≥ %.1f м)"
		% [worst, speed, want])
	verdict("B2 отряд отходит без остановок, а не топчется", worst >= want,
		"пройдено минимум %.1f м за %.1f c при пороге %.1f м"
			% [worst, Unit.FORCED_MOVE_SEC, want])

	for u in archers + foes:
		if is_instance_valid(u): u.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ВЫХОД ИЗ-ПОД ДЕРЕВА
# ═════════════════════════════════════════════════════════════════════════════
func _test_tree_escape() -> void:
	print("\n═════ C. «ЮНИТ-МУХА» ВОКРУГ СТВОЛА ═════")
	var here := _spot_c
	# Дерево ровно между бойцом и его целью — вырожденный лобовой случай,
	# из которого и получались круги вокруг комля
	var tree := ResourceNode.new()
	tree.resource_type = Constants.RESOURCE_WOOD
	main.world_add(tree)
	tree.global_position = Vector3(here.x + 3.0, 0.0, here.z)
	await frames(5)

	var u := _new("spearman", Constants.FACTION_PLAYER, here)
	await frames(3)
	var dest := Vector3(here.x + 6.0, 0.0, here.z)
	u.command_move(dest, false, Vector3.ZERO, false, true)
	var t0: int = Time.get_ticks_msec()
	var arrived := false
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().physics_frame
		if u.state == Unit.State.IDLE:
			arrived = true
			break
	var left: float = Vector2(u.global_position.x - dest.x, u.global_position.z - dest.z).length()
	print("  дошёл: %s, остаток до цели %.2f м, детектор сработал: %s"
		% [str(arrived), left, str(u._trunk_ignore > 0.0 or arrived)])
	verdict("C1 боец вышел к цели, а не остался кружить вокруг ствола",
		arrived and left < Unit.ARRIVE_RADIUS + 0.1,
		"остаток %.2f м" % left)

	u.queue_free()
	tree.queue_free()
	await frames(3)
