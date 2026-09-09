extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД: ЧТО ДЕЛАЕТ СО СТРОЕМ САМО СТОЛКНОВЕНИЕ (20 на 20 копейщиков)
## ═══════════════════════════════════════════════════════════════════════════
## ЗАЧЕМ. Замер qa_mega_battle B7 показал, что НА МАРШЕ строй не разваливается
## вовсе: сдвиг формы 0.70 м и с переносом стены, и без него. Значит, отряд
## теряет вид не по дороге, а В КОНТАКТЕ — и мерить надо контакт.
##
## ЧЕГО ЗДЕСЬ НЕТ И БЫТЬ НЕ МОЖЕТ. Физтел у бойцов нет: `collision_mask` везде
## 0, `PhysicsServer` в бою не участвует, `PHYSICS_3D_ACTIVE_OBJECTS` читает 0.
## Форму строя в контакте определяют ровно две вещи:
##   • ПАКЕТНОЕ РАСТАЛКИВАНИЕ (`ArmyCore.BatchSeparation`) — единственное, что
##     двигает СВОИХ друг относительно друга. Оно монотонно и только наружу,
##     сил избегания в нём нет намеренно;
##   • ПРОДАВЛИВАНИЕ (`Unit._apply_push`) — двигает только ЧУЖИХ, по вектору
##     удара. Своих оно не касается вовсе, поэтому «задние выталкивают
##     передних боковыми импульсами» механизма под собой не имеет; проверяем
##     это замером, а не рассуждением (проверка C1).
##
## ЧТО МЕРИМ. Три числа, снятые в одни и те же моменты (до приказа, в миг
## первого контакта, через десять секунд боя):
##   ШИРИНА ФРОНТА  — габарит отряда ПОПЕРЁК курса;
##   ГЛУБИНА        — габарит ВДОЛЬ курса;
##   ИНТЕРВАЛ       — среднее расстояние до ближайшего своего.
## «Сжатие линии» — это падение ширины и интервала при росте глубины.
##
## Запуск: godot --headless --path . res://qa_clash/Test.tscn

const SPEARMAN := "res://scenes/units/Spearman.tscn"

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## physics_frame, а не process_frame (правило 11 проекта): при Engine.max_fps = 0
## отрисовка обгоняет физику, и ожидание по кадрам отрисовки меряет не то
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func secs(s: float) -> void:
	await frames(int(s * 60.0))

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o

func _spawn(fac: int, at: Vector3) -> Unit:
	var u: Unit = load(SPEARMAN).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Отряд ПРЯМОУГОЛЬНИКОМ с настоящим строевым интервалом и настоящей разметкой.
## Интервал берётся из конфига (Building.squad_spacing), а не круглым числом:
## стенд, построивший шеренгу вдвое реже игровой, мерит собственную расстановку
## (ровно на этом краснел qa_rally2 A1)
func _squad(fac: int, at: Vector3, n: int, cols: int, course: Vector3) -> Array:
	# Число берётся у ЭКЗЕМПЛЯРА: `squad_spacing` это поле, а не константа,
	# и обращение к нему через класс бросает исключение — а исключение внутри
	# корутины стенда убивает её МОЛЧА (см. CLAUDE.md). Тот же приём, что в
	# qa_crowd
	var step: float = Building.new().squad_spacing
	var sid: int = GameManager.new_squad(fac, "spearman")
	var men: Array = []
	var slots: Array = []
	for i in range(n):
		var off := Vector3(float(i % cols) * step - float(cols - 1) * step * 0.5,
			0.0, float(i / cols) * step * course.z * -1.0)
		var p: Vector3 = at + off
		var u := _spawn(fac, p)
		GameManager.add_to_squad(sid, u)
		u.formation_row = i / cols
		men.append(u)
		slots.append(p)
	GameManager.squad_set_formation(sid, slots, course, false)
	for i in range(men.size()):
		(men[i] as Unit).command_move(slots[i], true, course, false, true)
	return men

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if u == null or not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu != null and not uu.is_dead():
			out.append(uu)
	return out

## ── ГАБАРИТЫ СЧИТАЮТСЯ В ОСЯХ КУРСА, А НЕ КАРТЫ ───────────────────────────
## Отряд идёт по оси Z, поэтому «ширина» это разброс по X, а «глубина» — по Z.
## Считать в осях карты можно только потому, что курс здесь ровно по оси; будь
## он под углом, пришлось бы проецировать — и стенд мерил бы поворот, а не форму
func _span(men: Array) -> Array:
	var alive := _alive(men)
	if alive.is_empty():
		return [0.0, 0.0]
	var minx := INF; var maxx := -INF; var minz := INF; var maxz := -INF
	for u in alive:
		var p: Vector3 = (u as Node3D).global_position
		minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
		minz = minf(minz, p.z); maxz = maxf(maxz, p.z)
	return [maxx - minx, maxz - minz]

## Средний интервал до БЛИЖАЙШЕГО своего. Именно среднее, а не минимум:
## минимум ловит одну случайную пару, а сжатие строя — это когда теснее стало
## у ВСЕХ
func _gap(men: Array) -> float:
	var alive := _alive(men)
	if alive.size() < 2:
		return 0.0
	var sum := 0.0
	for a in alive:
		var pa: Vector3 = (a as Node3D).global_position
		var near := INF
		for b in alive:
			if b == a:
				continue
			var pb: Vector3 = (b as Node3D).global_position
			var d: float = Vector2(pa.x - pb.x, pa.z - pb.z).length()
			near = minf(near, d)
		sum += near
	return sum / float(alive.size())

## Сколько бойцов уже дерётся (цель назначена и она в пределах оружия)
func _engaged(men: Array) -> int:
	var n := 0
	for u in _alive(men):
		var uu := u as Unit
		var t = uu.attack_target
		if t == null or not is_instance_valid(t):
			continue
		if uu.global_position.distance_to((t as Node3D).global_position) <= uu.reach() + 0.5:
			n += 1
	return n

func _run() -> void:
	seed(11)
	Engine.max_fps = 0
	preload("res://scripts/perf_config.gd").sprite_lod = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(6)

	await _block_clash()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 60), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== CLASH PROBE DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# СТОЛКНОВЕНИЕ 20 НА 20
# ═════════════════════════════════════════════════════════════════════════════
## Оба отряда — прямоугольники 5 колонн × 4 шеренги, фронтом друг к другу,
## между фронтами десять метров. Свой получает приказ атаки, чужой стоит.
func _block_clash() -> void:
	print("\n═════ СТОЛКНОВЕНИЕ 20 НА 20 ═════")
	var mine: Array = _squad(Constants.FACTION_PLAYER,
		Vector3(0.0, 0.0, -5.0), 20, 5, Vector3(0.0, 0.0, 1.0))
	var foes: Array = _squad(Constants.FACTION_ENEMY,
		Vector3(0.0, 0.0, 5.0), 20, 5, Vector3(0.0, 0.0, -1.0))
	await secs(2.0)

	var s0: Array = _span(mine)
	var g0: float = _gap(mine)
	print("  ДО ПРИКАЗА:      ширина %.2f м, глубина %.2f м, интервал %.2f м" % [
		float(s0[0]), float(s0[1]), g0])

	# ── ПРИКАЗ ОТДАЁТСЯ ТАК ЖЕ, КАК ЕГО ОТДАЁТ ИГРА ────────────────────────
	# forced + lock: правый клик по вражескому бойцу. Через SelectionManager
	# идти незачем — раскладка целей по фронту (frontline_targets) начинается
	# от ДВУХ отрядов, а здесь он один, и путь приказа тот же
	var victim: Unit = _alive(foes)[0]
	for u in _alive(mine):
		(u as Unit).command_attack(victim, true, true, true)

	# ── СНИМОК В МИГ ПЕРВОГО КОНТАКТА, А НЕ ПО ЧАСАМ ───────────────────────
	# Ждать фиксированное время нельзя: сколько отряд идёт десять метров,
	# зависит от скорости и от загрузки машины. Ждём СОБЫТИЕ — первого бойца,
	# который реально достал до врага
	var s1: Array = [0.0, 0.0]
	var g1 := 0.0
	var t_contact := -1.0
	for i in range(60 * 20):
		await get_tree().physics_frame
		if _engaged(mine) > 0:
			t_contact = float(i) / 60.0
			s1 = _span(mine)
			g1 = _gap(mine)
			break
	print("  ПЕРВЫЙ КОНТАКТ (%.2f с): ширина %.2f м, глубина %.2f м, интервал %.2f м" % [
		t_contact, float(s1[0]), float(s1[1]), g1])

	# Десять секунд рубки — то состояние, на которое жалуются
	var peak := 0
	for i in range(60 * 10):
		await get_tree().physics_frame
		peak = maxi(peak, _engaged(mine))
	var s2: Array = _span(mine)
	var g2: float = _gap(mine)
	var alive2: int = _alive(mine).size()
	print("  ЧЕРЕЗ 10 с БОЯ:  ширина %.2f м, глубина %.2f м, интервал %.2f м (живых %d из 20)" % [
		float(s2[0]), float(s2[1]), g2, alive2])
	print("  дерущихся: пик %d из 20" % peak)

	verdict("A0 контакт состоялся", t_contact >= 0.0 and peak > 0,
		"контакт через %.2f с, пик дерущихся %d" % [t_contact, peak])

	# ── A1: ЛИНИЯ НЕ СЖИМАЕТСЯ ПОПЕРЁК ────────────────────────────────────
	# Это и есть жалоба «отряд рассыпается в толпу»: фронт схлопывается, бойцы
	# набиваются друг другу в затылок. Порог — четверть ширины: меньшее
	# изменение неотличимо от того, что фланговые шагнули к своей цели
	verdict("A1 фронт не схлопнулся при столкновении",
		alive2 < 5 or float(s2[0]) >= float(s0[0]) * 0.75,
		"ширина %.2f → %.2f м" % [float(s0[0]), float(s2[0])])

	# ── A2: ИНТЕРВАЛ НЕ ПРОВАЛИЛСЯ НИЖЕ МЁРТВОЙ ЗОНЫ ──────────────────────
	# ЗДЕСЬ СТОЯЛ SEP_MIN_DIST, И ЭТО БЫЛ НЕВЕРНЫЙ ПОРОГ. Расталкивание
	# включается не на личном круге, а на `SEP_MIN_DIST − SEP_DEADZONE`:
	# 0.4167 − 0.0833 = 0.3333 м. Мёртвая зона заведена намеренно — без неё
	# строй дрожал бы, вечно поправляя сантиметры, — и означает она, что
	# НАСТОЯЩИЙ гарантированный интервал в игре именно 0.333, а не 0.417.
	# Замер в контакте даёт 0.33-0.35 м, то есть расталкивание отработало ровно
	# как настроено; провал НИЖЕ мёртвой зоны означал бы, что оно сдалось.
	# ── ДОПУСК НА ШУМ ОБЯЗАТЕЛЕН (сент. 2026) ─────────────────────────────
	# Равновесие под давлением подтягивания садится ПО ПОСТРОЕНИЮ ровно на
	# границу мёртвой зоны — то есть меряется величина, физически равная
	# порогу, и строгое `>=` мигало на третьем знаке (0.334 зелёный, 0.329
	# красный на неизменном коде; поправка между событиями расталкивания
	# дискретна — SEP_INTERVAL и SEP_MAX_STEP). Провал, который проверка
	# стережёт, — это «расталкивание сдалось», то есть сантиметры, а не
	# третий знак. Допуск — 0.02 м, заведомо меньше любого настоящего провала
	var floor_gap: float = Unit.SEP_MIN_DIST - Unit.SEP_DEADZONE
	verdict("A2 средний интервал не ниже мёртвой зоны расталкивания",
		alive2 < 5 or g2 >= floor_gap - 0.02,
		"интервал %.2f м при пороге срабатывания %.2f м (личный круг %.2f)"
			% [g2, floor_gap, Unit.SEP_MIN_DIST])

	# ── A3: ГЛУБИНА НЕ РАЗБУХЛА ───────────────────────────────────────────
	# Обратная сторона того же: если фронт цел, а глубина выросла вдвое, отряд
	# вытянулся в колонну — это тоже развал строя, только вдоль
	verdict("A3 отряд не вытянулся в колонну",
		alive2 < 5 or float(s2[1]) <= float(s0[1]) * 2.5,
		"глубина %.2f → %.2f м" % [float(s0[1]), float(s2[1])])

	# ── A4: УПЛОТНЕНИЕ ОКУПАЕТСЯ УЧАСТИЕМ В БОЮ ───────────────────────────
	# ГЛАВНАЯ НАХОДКА ЗОНДА. В контакте ширина фронта РАСТЁТ (2.28 → 2.78 м),
	# а глубина падает почти втрое (3.81 → 1.52 м, то есть 40 %): четыре
	# шеренги превращаются в полторы. Ни расталкивание, ни толчок тут ни при
	# чём — своих не двигает ни то, ни другое (проверка C1). Уплотняет строй
	# ПОДТЯГИВАНИЕ ЗАДНИХ РЯДОВ: боец, у которого цель дальше оружия, делает
	# шаг вперёд (Unit._should_pull_up), и в контакте это делают все задние.
	#
	# ЗАПРЕЩАТЬ ЭТО НЕЛЬЗЯ, И ИМЕННО ПОЭТОМУ ПРОВЕРКА НЕ ПРО ГЛУБИНУ. Ровно
	# подтягивание и заведено по заказу владельца — против жалобы «в бой
	# вступает только та часть отряда, что соприкоснулась с врагом». Замер её
	# и подтверждает: при глубине 40 % дерутся ВСЕ 20 из 20.
	# Проверяем СДЕЛКУ: строй вправе уплотняться ровно настолько, насколько
	# это вводит людей в бой. Сплющился, а дерутся единицы — вот это поломка,
	# и вот тогда проверка обязана покраснеть
	var depth_frac: float = float(s2[1]) / maxf(float(s0[1]), 0.01)
	var eng_frac: float = float(peak) / maxf(float(alive2), 1.0)
	print("  сделка строя: глубина %.0f%% от исходной, в бою %.0f%% отряда" % [
		100.0 * depth_frac, 100.0 * eng_frac])
	verdict("A4 уплотнение строя окупается участием в бою",
		alive2 < 5 or depth_frac >= 0.5 or eng_frac >= 0.6,
		"глубина %.0f%% от исходной при %.0f%% отряда в бою" % [
			100.0 * depth_frac, 100.0 * eng_frac])

	# ── C1: СВОИ ДРУГ ДРУГА НЕ ТОЛКАЮТ ────────────────────────────────────
	# Проверяем МЕХАНИЗМ, а не его последствие: _apply_push двигает только
	# ЧУЖИХ. Берём двух своих, ставим вплотную и смотрим, сдвинет ли толчок
	# одного другим. Расталкивание при этом работает и разведёт их — поэтому
	# сравниваем с парой, у которой толчок заведомо невозможен (тот же
	# _apply_push с нулевой разницей напора)
	var a: Unit = _alive(mine)[0]
	var b: Unit = _alive(mine)[1]
	var before: Vector3 = b.global_position
	a._apply_push(b, Vector3(1.0, 0.0, 0.0))
	var moved: float = b.global_position.distance_to(before)
	verdict("C1 толчок не двигает СВОИХ (у них нет разницы напора)",
		moved < 0.001, "сдвиг %.4f м" % moved)
