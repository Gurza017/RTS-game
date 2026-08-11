extends Node

## СТЕНД: СЛИПАНИЕ И ПОКОЙ (борьба с микро-дёрганьем)
##
## Проверяет контракт «союзники друг друга не толкают» (см. шапку Unit.gd):
## они свободно перекрываются и проходят насквозь, а дошедший до точки встаёт
## намертво и больше не двигается никем и ничем.
##
## Разделы:
##   A — куча на одной точке: 5 отрядов в один пиксель, замирают и не дрожат
##   B — двое в одну точку: оба встают, никто не топчется вечно
##   C — якорь: стоящего не выталкивает подошедший вплотную сосед
##   D — сквозной проход: свои идут НАСКВОЗЬ, шеренга не шелохнулась
##   E — цена кадра на плотной куче
##
## Все пороги берутся из живых констант Unit — чисел, дублирующих код, здесь
## быть не должно (см. CLAUDE.md, «Config is the source of truth»)

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main: Node = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func wait_ms(ms: int) -> void:
	var end: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func mk(kind: String, n: int, at: Vector3, sid: int = -1) -> Array:
	var s: int = sid if sid > 0 else GameManager.new_squad(
		Constants.FACTION_PLAYER, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = load("res://scenes/units/%s.tscn" % kind.capitalize()).instantiate()
		u.faction = Constants.FACTION_PLAYER
		get_tree().root.add_child(u)
		u.global_position = at + Vector3(float(i % 7) * 0.8, 0.0, float(i / 7) * 0.8)
		GameManager.add_to_squad(s, u)
		men.append(u)
	return men

## СКОЛЬКО ВРЕМЕНИ ЗАВЕДОМО ХВАТИТ ДОЙТИ ДО ТОЧКИ.
## Считается по РЕАЛЬНОЙ скорости бойцов (move_speed приходит из
## unit_stats_config) и реальному расстоянию, а не по угаданному числу секунд.
## Так и должно быть: угаданные 15 с проваливали замер не потому, что куча
## дёргалась, а потому, что дальний отряд физически не успевал дойти
func travel_budget_ms(men: Array, to: Vector3) -> int:
	var far := 0.0
	var slow := 1e9
	for m in men:
		var u: Unit = m
		var p: Vector3 = u.global_position
		far = maxf(far, Vector2(p.x - to.x, p.z - to.z).length())
		slow = minf(slow, maxf(u.move_speed, 0.1))
	# Тройной запас: марш строем идёт вполовину скорости, плюс обходы преград
	return int(far / slow * 3000.0) + 2000

## Ждать, пока все не выйдут из состояния MOVING. Возвращает, сколько осталось
## идущих (0 — дошли все)
func await_stop(men: Array, budget_ms: int) -> int:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < budget_ms:
		await get_tree().process_frame
		var moving := 0
		for m in men:
			if (m as Unit).state == Unit.State.MOVING:
				moving += 1
		if moving == 0:
			return 0
	var left := 0
	for m in men:
		if (m as Unit).state == Unit.State.MOVING:
			left += 1
	return left

## Суммарное перемещение всех бойцов за n кадров — мера «дрожания»
func drift(men: Array, n: int) -> Dictionary:
	var start: Array = []
	for m in men:
		start.append((m as Node3D).global_position)
	var total := 0.0
	var worst := 0.0
	var prev: Array = start.duplicate()
	for _f in range(n):
		await get_tree().process_frame
		for i in range(men.size()):
			var p: Vector3 = (men[i] as Node3D).global_position
			var d: float = Vector2(p.x - (prev[i] as Vector3).x,
				p.z - (prev[i] as Vector3).z).length()
			total += d
			worst = maxf(worst, d)
			prev[i] = p
	return {"total": total, "worst": worst,
		"per_unit": total / maxf(float(men.size()), 1.0)}

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	await _test_pile()
	await _test_tail()
	await _test_anchor()
	await _test_corridor()
	await _test_cost()

	print("\n=== ИТОГ qa_settle: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. КУЧА НА ОДНОЙ ТОЧКЕ
# ═════════════════════════════════════════════════════════════════════════════
## Сколько ждать, пока сошедшаяся куча разойдётся на личный объём каждого
## (Unit.SEP_MIN_DIST). Разводка идёт шагами Unit.SEP_MAX_STEP раз в
## Unit.SEP_INTERVAL и заканчивается сама; трёх секунд хватает и на 240 человек
const SEP_SETTLE_MS := 3000

func _test_pile() -> void:
	print("\n═════ A. ПЯТЬ ОТРЯДОВ В ОДНУ ТОЧКУ ═════")
	var all: Array = []
	for k in range(5):
		var men := mk("spearman", 12, Vector3(-300 + float(k) * 6.0, 0, -300))
		all += men
	await frames(3)
	# Все получают приказ в ОДИН И ТОТ ЖЕ пиксель — худший случай
	var spot := Vector3(-300, 0, -280)
	var budget: int = travel_budget_ms(all, spot)
	for m in all:
		(m as Unit).command_move(spot)
	var still_moving: int = await await_stop(all, budget)
	print("  бойцов всего %d, срок на дорогу %.1f с, ещё в движении: %d" % [
		all.size(), float(budget) / 1000.0, still_moving])
	verdict("A1 вся куча встала (никто не «доезжает» вечно)",
		still_moving == 0, "в движении %d" % still_moving)

	var settled := 0
	for m in all:
		if (m as Unit)._settled:
			settled += 1
	# ТЕПЕРЬ ЯКОРЬ ОБЯЗАН БЫТЬ У КАЖДОГО. Раньше проходящий мимо союзник снимал
	# якорь у стоящего (механика уступки дороги), и часть кучи оставалась без
	# него — приходилось мириться с долей. Уступать дорогу больше не нужно:
	# снять якорь может только НОВЫЙ приказ, а его здесь никто не отдаёт
	verdict("A2 заякорились ВСЕ до одного", settled == all.size(),
		"якорей %d из %d" % [settled, all.size()])

	# ГЛАВНОЕ: после остановки они не должны шевелиться.
	# У бойца ПОЯВИЛСЯ ЛИЧНЫЙ ОБЪЁМ (Unit.SEP_MIN_DIST): куча, сошедшаяся в одну
	# точку, один раз расталкивается до этого расстояния и на этом замирает.
	# Замер поэтому делается ПОСЛЕ схождения, а не в его разгар — иначе стенд
	# ловит саму разводку и объявляет её дрожанием. Порог покоя не смягчён:
	# после разводки движения обязано не быть вовсе
	await wait_ms(SEP_SETTLE_MS)
	var d: Dictionary = await drift(all, 60)
	print("  за 60 кадров покоя: суммарный сдвиг %.4f м, на бойца %.5f м, худший кадр %.5f м" % [
		float(d["total"]), float(d["per_unit"]), float(d["worst"])])
	# Порог 5 см НА СЕКУНДУ движения. До фикса тот же замер давал 0.58 м на
	# бойца — то самое непрерывное дрожание; всё, что заметно ниже сантиметров
	# в секунду, глазом уже не читается как шевеление
	verdict("A3 куча стоит НЕПОДВИЖНО, а не дрожит",
		float(d["per_unit"]) < 0.05,
		"на бойца %.5f м за 60 кадров (до фикса было 0.58)" % float(d["per_unit"]))

	# И они действительно слиплись — стоят плотно, частично перекрываясь
	var min_gap := 1e9
	for i in range(all.size()):
		for j in range(i + 1, all.size()):
			var a: Vector3 = (all[i] as Node3D).global_position
			var b: Vector3 = (all[j] as Node3D).global_position
			min_gap = minf(min_gap, Vector2(a.x - b.x, a.z - b.z).length())
	# Мерим относительно BLOCK_RADIUS — расстояния, на котором остановил бы ВРАГ.
	# Свои обязаны сходиться теснее: для них преграды нет вовсе
	print("  минимальный просвет между соседями: %.3f м (враг встал бы на %.2f)" % [
		min_gap, Unit.BLOCK_RADIUS])
	verdict("A4 стоят вплотную, допускается частичное перекрытие",
		min_gap < Unit.BLOCK_RADIUS, "минимальный просвет %.3f м" % min_gap)

	for m in all:
		(m as Node).queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. ХВОСТОВОЙ БОЕЦ
# ═════════════════════════════════════════════════════════════════════════════
func _test_tail() -> void:
	print("\n═════ B. ДВОЕ В ОДНУ И ТУ ЖЕ ТОЧКУ ═════")
	# Раньше это был «хвостовой боец строя»: его точка оказывалась занята соседом,
	# встать в неё было физически некуда, и он топтался там до конца партии — ради
	# этого случая и заводился отдельный срок смирения (SETTLE_GRACE_MS).
	# ЗАНЯТЫХ ТОЧЕК БОЛЬШЕ НЕ БЫВАЕТ: союзники перекрываются свободно, поэтому в
	# одну и ту же точку спокойно встают оба, и никакого срока не нужно
	var men := mk("spearman", 2, Vector3(-350, 0, -350))
	await frames(3)
	var slot := Vector3(-345, 0, -345)
	var budget: int = travel_budget_ms(men, slot)
	(men[0] as Unit).command_move(slot)
	(men[1] as Unit).command_move(slot)
	await await_stop(men, budget)
	var u0: Unit = men[0]
	var u1: Unit = men[1]
	print("  боец A: state=%d settled=%s, боец B: state=%d settled=%s" % [
		u0.state, str(u0._settled), u1.state, str(u1._settled)])
	verdict("B1 оба встали, никто не топчется",
		u0.state != Unit.State.MOVING and u1.state != Unit.State.MOVING,
		"состояния %d и %d" % [u0.state, u1.state])
	verdict("B2 оба объявили себя стоящими", u0._settled and u1._settled)
	# Обоих устроила ОДНА И ТА ЖЕ точка: каждый встал в пределах допуска прибытия
	# от неё, а не в стороне «где получилось»
	var off0: float = Vector2(u0.global_position.x - slot.x,
		u0.global_position.z - slot.z).length()
	var off1: float = Vector2(u1.global_position.x - slot.x,
		u1.global_position.z - slot.z).length()
	print("  отклонение от общей точки: %.3f м и %.3f м (допуск %.2f)" % [
		off0, off1, Unit.ARRIVE_RADIUS])
	verdict("B3 оба встали В саму точку, а не рядом с ней",
		off0 < Unit.ARRIVE_RADIUS and off1 < Unit.ARRIVE_RADIUS,
		"отклонения %.3f и %.3f м" % [off0, off1])
	# Тем же порядком, что и в A3: сначала даём разойтись на личный объём
	await wait_ms(SEP_SETTLE_MS)
	var d: Dictionary = await drift(men, 60)
	print("  за 60 кадров: на бойца %.5f м" % float(d["per_unit"]))
	verdict("B4 стоящие не дёргаются на месте",
		float(d["per_unit"]) < 0.01, "сдвиг %.5f м" % float(d["per_unit"]))
	for m in men:
		(m as Node).queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. ЯКОРЬ НЕ ВЫТАЛКИВАЕТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _test_anchor() -> void:
	print("\n═════ C. СТОЯЩЕГО НЕ ВЫТАЛКИВАЮТ ═════")
	var a := mk("spearman", 1, Vector3(-400, 0, -400))
	var anchor: Unit = a[0]
	anchor.command_move(Vector3(-400, 0, -400))
	await wait_ms(600)
	verdict("C1 первый боец встал и заякорился", anchor._settled,
		"settled=%s state=%d" % [str(anchor._settled), anchor.state])
	var was: Vector3 = anchor.global_position

	# Второй идёт РОВНО в ту же точку
	var b := mk("spearman", 1, Vector3(-406, 0, -400))
	var comer: Unit = b[0]
	var goal: Vector3 = anchor.global_position
	var budget: int = travel_budget_ms(b, goal)
	comer.command_move(goal)
	await await_stop(b, budget)
	# И ещё секунда покоя: если бы подошедший выталкивал якорь, это случилось бы
	# уже после его прихода
	await wait_ms(1000)
	var moved: float = Vector2(anchor.global_position.x - was.x,
		anchor.global_position.z - was.z).length()
	var gap: float = Vector2(anchor.global_position.x - comer.global_position.x,
		anchor.global_position.z - comer.global_position.z).length()
	print("  якорь сместился на %.4f м, просвет между ними %.3f м" % [moved, gap])
	verdict("C2 стоящего не сдвинули с места", moved < 0.15,
		"сместился на %.4f м" % moved)
	verdict("C3 подошедший встал вплотную и тоже замер",
		comer.state != Unit.State.MOVING and comer._settled,
		"state=%d settled=%s" % [comer.state, str(comer._settled)])
	anchor.queue_free(); comer.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# D. СКВОЗНОЙ ПРОХОД НЕ СЛОМАН
# ═════════════════════════════════════════════════════════════════════════════
func _test_corridor() -> void:
	print("\n═════ D. СВОИ ИДУТ СКВОЗЬ СТРОЙ ═════")
	# КОНТРАКТ ПЕРЕВЁРНУТ. Раньше здесь проверялось, что шеренга РАЗДВИГАЕТСЯ,
	# пропуская своих коридором, и потом смыкается обратно. Ровно эта механика —
	# расталкивание плюс возврат в слот — и давала вечное дрожание, поэтому она
	# удалена целиком. Правильное поведение теперь обратное: проходящий идёт
	# НАСКВОЗЬ, а стоящая шеренга не двигается вовсе.
	var wall: Array = []
	var wsid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(8):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		get_tree().root.add_child(u)
		u.global_position = Vector3(-450, 0, -450 + float(i) * 0.7)
		GameManager.add_to_squad(wsid, u)
		wall.append(u)
	await frames(3)
	for u in wall:
		(u as Unit).command_move((u as Unit).global_position)
	await wait_ms(900)
	var anchored := 0
	for u in wall:
		if (u as Unit)._settled:
			anchored += 1
	verdict("D1 шеренга встала и заякорилась вся", anchored == wall.size(),
		"якорей %d из %d" % [anchored, wall.size()])
	var before: Array = []
	for u in wall:
		before.append((u as Node3D).global_position)

	# Сквозь неё идёт свой отряд: заходит слева, уходит направо
	var run := mk("spearman", 6, Vector3(-458, 0, -448))
	var goal := Vector3(-440, 0, -448)
	var run_budget: int = travel_budget_ms(run, goal)
	for m in run:
		(m as Unit).command_move(goal)
	# Смещение шеренги копим ВСЮ дорогу, а не смотрим только на итог: коридор,
	# если бы он открывался, открывался бы именно в момент прохода
	var t0: int = Time.get_ticks_msec()
	var peak := 0.0
	while Time.get_ticks_msec() - t0 < run_budget:
		await get_tree().process_frame
		var moving := 0
		for i in range(wall.size()):
			var wp: Vector3 = (wall[i] as Node3D).global_position
			peak = maxf(peak, Vector2(wp.x - (before[i] as Vector3).x,
				wp.z - (before[i] as Vector3).z).length())
		for m in run:
			if (m as Unit).state == Unit.State.MOVING:
				moving += 1
		if moving == 0:
			break
	print("  наибольшее смещение бойца шеренги В МОМЕНТ прохода: %.4f м" % peak)
	var worst := 0.0
	for i in range(wall.size()):
		var p: Vector3 = (wall[i] as Node3D).global_position
		worst = maxf(worst, Vector2(p.x - (before[i] as Vector3).x,
			p.z - (before[i] as Vector3).z).length())
	print("  итоговое смещение бойца шеренги: %.4f м" % worst)
	# БЫЛО: «проход НЕ шелохнул вовсе» (порог 5 см). Теперь у бойца есть личный
	# объём, и проходящий свой ОБЯЗАН слегка потеснить шеренгу — ровно этого
	# просил владелец («не проходить сквозь центр друг друга»). Проверяем не
	# нулевое смещение, а то, что оно не выходит за размер личного круга: строй
	# раздвигается на толщину человека и смыкается обратно, а не разваливается.
	# Что он после этого ЗАМИРАЕТ, проверяет D4 ниже
	verdict("D2 проход теснит шеренгу не больше, чем на личный объём",
		maxf(worst, peak) < Unit.SEP_MIN_DIST * 2.0,
		"худшее смещение %.4f м при личном круге %.4f" % [maxf(worst, peak), Unit.SEP_MIN_DIST])

	# И проход действительно СОСТОЯЛСЯ — отряд не увяз в шеренге.
	# «Прошёл» = оказался ЗА шеренгой (её x = -450) с запасом
	var through := 0
	for m in run:
		if (m as Node3D).global_position.x > -446.0:
			through += 1
	print("  прошло насквозь: %d из %d" % [through, run.size()])
	verdict("D3 союзный отряд прошёл сквозь строй, а не увяз в нём",
		through == run.size(), "прошло %d из %d" % [through, run.size()])

	for m in run:
		(m as Node).queue_free()
	await wait_ms(1500)
	var d: Dictionary = await drift(wall, 60)
	print("  после прохода за 60 кадров: на бойца %.5f м" % float(d["per_unit"]))
	verdict("D4 после прохода шеренга по-прежнему стоит спокойно",
		float(d["per_unit"]) < 0.02, "сдвиг %.5f м" % float(d["per_unit"]))
	for u in wall:
		(u as Node).queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# E. ЦЕНА КАДРА
# ═════════════════════════════════════════════════════════════════════════════
func _test_cost() -> void:
	print("\n═════ E. ЦЕНА КАДРА НА ПЛОТНОЙ КУЧЕ ═════")
	var all: Array = []
	for k in range(6):
		all += mk("spearman", 40, Vector3(-500 + float(k) * 5.0, 0, -500))
	await frames(3)
	var spot := Vector3(-500, 0, -480)
	var budget: int = travel_budget_ms(all, spot)
	for m in all:
		(m as Unit).command_move(spot)
	var left: int = await await_stop(all, budget)
	if left > 0:
		print("  ВНИМАНИЕ: за %.1f с не дошло %d из %d" % [
			float(budget) / 1000.0, left, all.size()])
	# Личный объём: дать куче разойтись, прежде чем мерить покой (см. A3)
	await wait_ms(SEP_SETTLE_MS)
	var samples: Array = []
	for _i in range(120):
		await get_tree().process_frame
		samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	samples.sort()
	var med: float = float(samples[samples.size() / 2])
	print("  юнитов в куче: %d, медиана физического кадра в покое: %.3f мс" % [
		all.size(), med])
	# Бюджет кадра при 60 к/с — 16.6 мс. Проверяем, что стоящая куча из 240
	# бойцов укладывается в него С ЗАПАСОМ, а не борется за него
	verdict("E1 стоящая куча укладывается в бюджет кадра с запасом", med < 12.0,
		"медиана %.3f мс на %d юнитах (бюджет 16.6)" % [med, all.size()])
	var d: Dictionary = await drift(all, 60)
	print("  дрожание кучи из %d: на бойца %.5f м за 60 кадров" % [
		all.size(), float(d["per_unit"])])
	verdict("E2 куча из 240 бойцов неподвижна",
		float(d["per_unit"]) < 0.05,
		"сдвиг %.5f м за 60 кадров (до фикса 0.56)" % float(d["per_unit"]))
	for m in all:
		(m as Node).queue_free()
	await frames(2)
