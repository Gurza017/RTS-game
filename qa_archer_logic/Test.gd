extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_archer_logic — ЛУЧНИКИ ВСТАЮТ ОТРЯДОМ И СТРЕЛЯЮТ (спринт 14)
## ═══════════════════════════════════════════════════════════════════════════
## Заказ дословно: «При клике ПКМ по конкретному врагу отряд лучников бежит к
## нему, и как только ПЕРВАЯ модель выходит на дистанцию атаки — ВЕСЬ отряд
## останавливается и начинает вести огонь. При приказе на движение/атаку они
## идут и останавливаются стрелять, если враг появился в радиусе. Никакой
## хаотичной непрерывной погони: приоритет — стоять и стрелять по доступным.»
##
##   A ОТМЕТКА    — «отряд дострелил» это ОТРЯДНАЯ величина: ставится один раз,
##                  читается всеми, снимается новым приказом.
##   B ПЕРВЫЙ ЗА ВСЕХ — живой отряд идёт на конкретного врага; в миг, когда
##                  дострелил ПЕРВЫЙ, отряд встаёт ЦЕЛИКОМ, хотя задние ряды
##                  до цели ещё не достают, и открывает огонь.
##   C НЕТ ПОГОНИ — после остановки отряд не подползает к цели и продолжает
##                  стрелять, а не бегает челноком.
##   D НОВЫЙ ПРИКАЗ — снимает отметку: отряду снова можно подходить.
##   E ПЕХОТЫ НЕ КАСАЕТСЯ — копейщики по тому же приказу доходят до контакта,
##                  и отметка у их отряда не заводится вовсе.
##   F НА МАРШЕ   — враг, появившийся в радиусе по дороге, останавливает отряд
##                  и получает стрелы.
##
## Числа — из полей бойца и конфига (правило 10), ожидание — физкадрами
## (правило 11). Запуск: godot --headless --path . res://qa_archer_logic/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(400.0)
	t.timeout.connect(func():
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_archer_logic: прошло %d, провалов: %d ═════" % [
		_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

## Отряд КОЛОННОЙ: задние ряды намеренно отстают на несколько метров — именно
## на них и видно, встал ли отряд ЦЕЛИКОМ по первому дострелившему
func _squad(kind: String, fac: int, at: Vector3, n: int, depth: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var sc: PackedScene = Building.PRELOAD_SCENES[kind]
	for i in range(n):
		var u: Unit = sc.instantiate()
		u.faction = fac
		main.world_add(u)
		var px: float = at.x - float(i / 4) * depth
		var pz: float = at.z + float(i % 4) * 0.9 - 1.35
		u.global_position = Vector3(px,
			GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		u.post_pos = u.global_position
		men.append(u)
	return [sid, men]

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)

	await _a_flag()
	await _b_first_for_all()
	await _e_infantry()
	await _f_on_march()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ОТМЕТКА — ОТРЯДНАЯ, А НЕ ЛИЧНАЯ
# ═════════════════════════════════════════════════════════════════════════════
func _a_flag() -> void:
	print("\n═════ A. ОТМЕТКА «ОТРЯД ДОСТРЕЛИЛ» ═════")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	verdict("A1 у свежего отряда отметки нет",
		not GameManager.squad_ranged_engaged(sid))
	GameManager.squad_ranged_engaged_set(sid)
	verdict("A2 первый достреливший ставит её за всех",
		GameManager.squad_ranged_engaged(sid))
	GameManager.squad_ranged_engaged_set(sid)
	verdict("A3 повторная установка ничего не ломает",
		GameManager.squad_ranged_engaged(sid))
	GameManager.squad_ranged_release(sid)
	verdict("A4 снимается явно", not GameManager.squad_ranged_engaged(sid))
	# ── И ВМЕСТЕ С ЯКОРЕМ ПОГОНИ ───────────────────────────────────────────
	# У них общий жизненный цикл: обоими правит первый дотянувшийся, и оба
	# снимает новый приказ. Отдельного места снятия заводить нельзя — оно
	# разошлось бы с якорем на первой же правке
	GameManager.squad_ranged_engaged_set(sid)
	GameManager.squad_pursuit_release(sid)
	verdict("A5 снятие якоря погони снимает и её",
		not GameManager.squad_ranged_engaged(sid))
	verdict("A6 у отряда 0 («без отряда») отметки не бывает",
		not GameManager.squad_ranged_engaged(0))

# ═════════════════════════════════════════════════════════════════════════════
# B и C. ПЕРВЫЙ ДОСТРЕЛИВШИЙ ОСТАНАВЛИВАЕТ ВЕСЬ ОТРЯД
# ═════════════════════════════════════════════════════════════════════════════
func _b_first_for_all() -> void:
	print("\n═════ B. ВСТАЁТ ВЕСЬ ОТРЯД ПО ПЕРВОМУ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, 60.0)
	# Колонна в четыре ряда с шагом 3 м: между первой и последней шеренгой 9 м
	var mine: Array = _squad("archer", Constants.FACTION_PLAYER, spot, 16, 3.0)
	var sid: int = mine[0]
	var men: Array = mine[1]
	# ── ДИСТАНЦИЯ ПРИКАЗА ВЫВЕДЕНА ИЗ ПРАВИЛА ЗАМКА, А НЕ ВЗЯТА С ПОТОЛКА ──
	# Замок цели держится, пока она в пределах ДВОЙНОЙ дальности оружия
	# (Unit._lock_sight_range); дальше приказ считается исчерпанным и боец
	# возвращается на пост. Первая версия ставила противника в 46 м при
	# дальности лука 20 (то есть за 40 м двойной): отряд честно шёл, на
	# девятой секунде терял замок и разворачивался домой — стенд краснел на
	# ПРАВИЛЬНОМ поведении. Ставим так, чтобы В ЗАМОК ПОПАДАЛ ВЕСЬ ОТРЯД,
	# включая заднюю шеренгу
	var rng0: float = _UCfg.stat("archer", "attack_range", 20.0)
	var gap: float = rng0 * 2.0 - 9.0 - 2.0
	var foe: Array = _squad("spearman", Constants.FACTION_ENEMY,
		spot + Vector3(gap, 0.0, 0.0), 8, 1.0)
	var foes: Array = foe[1]
	await pframes(6)
	# Противник заморожен: здесь меряется поведение СТРЕЛКОВ, а бегущая на них
	# пехота смазала бы и дистанции, и момент первого выстрела
	for f in foes:
		(f as Unit).set_tick(false)
		(f as Unit).current_health = (f as Unit).max_health * 500.0
	var target: Unit = foes[0]
	var rng: float = (men[0] as Unit).attack_range
	print("  дальность лучника %.1f м, дистанция до цели %.1f м" % [
		rng, (men[0] as Unit).global_position.distance_to(target.global_position)])

	var shots0: int = GameManager.arrows_fired
	var centre0: Vector3 = _centre(men)
	for u in men:
		(u as Unit).command_attack(target, true, true, true)
	await pframes(2)

	# ── ЖДЁМ МИГ, КОГДА ОТРЯД ОБЪЯВИЛ «ДОСТРЕЛИЛИ» ─────────────────────────
	var guard := 0
	var engaged := false
	var in_range_at_moment := 0
	var centre_at_moment := Vector3.ZERO
	while guard < 60 * 45:
		await get_tree().physics_frame
		guard += 1
		if guard % 600 == 0:
			print("    %.0f с: центр %.1f м от цели, ближний %.1f м" % [
				float(guard) / 60.0,
				_centre(men).distance_to(target.global_position),
				_nearest_gap(men, target)])
		if GameManager.squad_ranged_engaged(sid):
			engaged = true
			centre_at_moment = _centre(men)
			for u in men:
				# ── «ДОСТАЮ» СЧИТАЕТСЯ ДО БЛИЖАЙШЕГО ИЗ ЧУЖОГО ОТРЯДА ──
				# Цель приказа ОДНА на отряд, а жертву внутри неё разбирает
				# squad_pick_member: каждому стрелку достаётся своя модель.
				# Мерить дистанцию до одной-единственной foes[0] значит
				# мерить не то — первая версия так и намеряла «достают 0 из
				# 16» в тот самый миг, когда передние уже стреляли
				if is_instance_valid(u) and _gap_to_squad(u, foes) <= (u as Unit).reach():
					in_range_at_moment += 1
			break
	verdict("B1 отряд объявил, что дострелил", engaged,
		"кадров ждали %d" % guard)
	if not engaged:
		return
	var far_men := 0
	for u in men:
		if is_instance_valid(u) and _gap_to_squad(u, foes) > (u as Unit).reach():
			far_men += 1
	print("  в миг объявления: НЕ достают %d из %d, центр в %.1f м от цели" % [
		far_men, men.size(),
		centre_at_moment.distance_to(target.global_position)])
	# ── СУДИМ ПО ЗАДНИМ РЯДАМ, И ТОЛЬКО ПО НИМ ────────────────────────────
	# «Объявил первый» — событие ОДНОГО кадра, а стенд видит его уже на
	# следующем и СНАРУЖИ: точной геометрии того мига по ней не восстановить
	# (дистанция удара считается с поправкой на габарит цели, которую снимает
	# сам боец при смене цели). Устойчиво проверяется ровно то, ради чего
	# правка и делалась: ЗАДНИЕ ряды до врага НЕ ДОТЯГИВАЮТСЯ, а отряд всё
	# равно встал (B3) и стреляет (B4) — то есть ради них он больше не
	# подползает
	verdict("B2 задние ряды до врага не достают, а отряд всё равно встал",
		far_men > 0, "не достают %d из %d" % [far_men, men.size()])

	# ── ДАЛЬШЕ ОТРЯД СТОИТ И СТРЕЛЯЕТ ──────────────────────────────────────
	var shots_at_moment: int = GameManager.arrows_fired
	var far0: float = centre_at_moment.distance_to(target.global_position)
	# ── ОКНО ЗАМЕРА КОНЧАЕТСЯ ВМЕСТЕ С ПРИКАЗОМ, А НЕ ПО ТАЙМЕРУ ──────────
	# Требование — «встал и ведёт огонь», и оно про то время, ПОКА ПРИКАЗ ЖИВ.
	# Замок приказа снимается сам, когда цель признана недостижимой, и дальше
	# отряд законно возвращается на пост — но МОМЕНТ этого снятия в headless
	# плавает: часть ворот боя отмеряется настенными часами, а физкадры их
	# обгоняют (правило 12). Первая версия ловила на этом сама себя: один и
	# тот же код давал то «гулял 0.27 м», то «гулял 11.14 м».
	# Поэтому окно закрывается ПО СВОЙСТВУ — по снятию замка, — а сколько оно
	# продержалось, печатается числом. Что будет ПОСЛЕ, меряет зонд ниже,
	# и вердикта у него нет
	var wandered := 0.0
	var held := 0
	var win: int = int(_UCfg.stat("archer", "attack_cooldown", 2.0) * 3.0 * 60.0) + 90
	for _i in range(win):
		if not (men[0] as Unit).target_lock:
			break
		await get_tree().physics_frame
		held += 1
		wandered = maxf(wandered,
			absf(_centre(men).distance_to(target.global_position) - far0))
	print("  приказ держался %.1f с из %.1f отведённых" % [
		float(held) / 60.0, float(win) / 60.0])
	var far1: float = _centre(men).distance_to(target.global_position)
	var moving := 0
	for u in men:
		if is_instance_valid(u) and (u as Unit).moved_recently():
			moving += 1
	print("  за 2.5 с после объявления: центр %.1f → %.1f м, шагают %d из %d, выстрелов +%d" % [
		far0, far1, moving, men.size(),
		GameManager.arrows_fired - shots_at_moment])
	verdict("B3 отряд ВСТАЛ: центр к цели дальше не подполз",
		far1 > far0 - 1.5,
		"%.1f → %.1f м" % [far0, far1])
	verdict("B3б замер вообще состоялся: приказ прожил хотя бы перезарядку",
		float(held) / 60.0 >= _UCfg.stat("archer", "attack_cooldown", 2.0),
		"держался %.1f с при перезарядке %.1f" % [float(held) / 60.0,
			_UCfg.stat("archer", "attack_cooldown", 2.0)])
	verdict("B4 и открыл огонь", GameManager.arrows_fired > shots_at_moment,
		"выстрелов +%d" % (GameManager.arrows_fired - shots_at_moment))
	# ЧТО ОТРЯД ДО ЭТОГО ШЁЛ — ОТДЕЛЬНОЕ ТРЕБОВАНИЕ («бежит к нему»), и без
	# него «встал и стреляет» выполнялось бы и у отряда, который не тронулся
	print("  до объявления отряд прошёл %.1f м (выстрелов по дороге %d)" % [
		centre0.distance_to(centre_at_moment), shots_at_moment - shots0])
	verdict("B5 до выхода на дистанцию отряд ШЁЛ к цели, а не стоял",
		centre0.distance_to(centre_at_moment) > 3.0,
		"прошёл %.1f м" % centre0.distance_to(centre_at_moment))

	print("\n═════ C. НЕТ ХАОТИЧНОЙ ПОГОНИ ═════")
	print("  за окно огня центр гулял на %.2f м" % wandered)
	verdict("C1 отряд не бегает челноком к цели и обратно", wandered < 2.0,
		"гулял на %.2f м" % wandered)
	# Стреляют только те, кто достаёт, а их в колонне единицы, и число залпов
	# зависит и от перезарядки, и от того, сколько прожил приказ. Требование —
	# «ведёт огонь всё это время», то есть не меньше выстрела на перезарядку
	var want_shots: int = maxi(int(float(held) / 60.0
		/ maxf(_UCfg.stat("archer", "attack_cooldown", 2.0), 0.1)), 1)
	verdict("C2 и стрелял он всё это время, а не разово",
		GameManager.arrows_fired - shots_at_moment >= want_shots,
		"выстрелов +%d при ожидаемых %d за %.1f с" % [
			GameManager.arrows_fired - shots_at_moment, want_shots,
			float(held) / 60.0])
	# ── ЗОНД БЕЗ ВЕРДИКТА: ЧТО БУДЕТ ЧЕРЕЗ ПОЛМИНУТЫ ──────────────────────
	# Замер показал, что спустя десяток секунд отряд иногда уходит обратно к
	# исходным местам. Держится это на ЧАСАХ (Time.get_ticks_msec), а в
	# headless физкадры обгоняют настенное время — то есть в стенде событие
	# плавает от прогона к прогону (правило 12). Вердикта здесь поэтому нет:
	# число печатается, чтобы его было видно, и разобрано в ENGINEERING_LOG
	var probe0: float = _centre(men).distance_to(target.global_position)
	var probe_shots: int = GameManager.arrows_fired
	await pframes(60 * 20)
	print("  ЗОНД (без вердикта): ещё через 20 с центр %.1f → %.1f м, выстрелов +%d" % [
		probe0, _centre(men).distance_to(target.global_position),
		GameManager.arrows_fired - probe_shots])

	print("\n═════ D. НОВЫЙ ПРИКАЗ СНИМАЕТ ОТМЕТКУ ═════")
	var back: Vector3 = spot - Vector3(20.0, 0.0, 0.0)
	for u in men:
		(u as Unit).command_move(back, true)
	await pframes(6)
	verdict("D1 приказ на движение снял отметку отряда",
		not GameManager.squad_ranged_engaged(sid))
	for u in men:
		_kill(u)
	for f in foes:
		_kill(f)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# E. ПЕХОТЫ ПРАВИЛО НЕ КАСАЕТСЯ ВОВСЕ
# ═════════════════════════════════════════════════════════════════════════════
func _e_infantry() -> void:
	print("\n═════ E. ПЕХОТА ПО-ПРЕЖНЕМУ ДОХОДИТ ДО КОНТАКТА ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, -60.0)
	var mine: Array = _squad("spearman", Constants.FACTION_PLAYER, spot, 8, 2.0)
	var sid: int = mine[0]
	var men: Array = mine[1]
	# ── ДВЕ ОГОВОРКИ, И ОБЕ ПРО ЗАМЕР, А НЕ ПРО КОД ───────────────────────
	# 1. Замок цели держится, пока она ближе _lock_sight_range() = максимум из
	#    двойной дальности оружия и двойного радиуса агро (20 м у пехоты).
	#    Цель дальше — «приказ исчерпан», боец встаёт где стоит.
	# 2. Долгий подход в headless НЕУСТОЙЧИВ: часть ворот боя отмеряется
	#    настенными часами (Time.get_ticks_msec), а физкадры их обгоняют —
	#    один и тот же код доходил то за 421 кадр, то не доходил за 3000
	#    (правило 12). Проверяется здесь НЕ длина марша, а то, что пехота
	#    по-прежнему идёт В КОНТАКТ и отметки стрелков у неё не заводится:
	#    для этого хватает короткой дистанции
	var foe: Array = _squad("spearman", Constants.FACTION_ENEMY,
		spot + Vector3(7.0, 0.0, 0.0), 6, 1.0)
	var foes: Array = foe[1]
	await pframes(6)
	for f in foes:
		(f as Unit).set_tick(false)
		(f as Unit).current_health = (f as Unit).max_health * 500.0
	var target: Unit = foes[0]
	for u in men:
		(u as Unit).command_attack(target, true, true, true)
	var guard := 0
	var reached := false
	while guard < 60 * 50:
		await get_tree().physics_frame
		guard += 1
		if guard % 600 == 0:
			print("    %.0f с: центр в %.1f м от цели, ближний в %.1f м, сост=%d" % [
				float(guard) / 60.0,
				_centre(men).distance_to(target.global_position),
				_nearest_gap(men, target), int((men[0] as Unit).state)])
		for u in men:
			if not is_instance_valid(u):
				continue
			# ── ДОПУСК — ЭТО РАДИУС ТЕЛА, А НЕ КРУГЛОЕ ЧИСЛО ─────────────
			# Ближе, чем на сумму радиусов тел, подойти физически нельзя:
			# шаг упирается в чужое тело (BLOCK_RADIUS). Копейщик встаёт
			# в 2.6 м при копье в 2.0 и честно дерётся — а проверка с
			# допуском «+0.5» считала это недоходом и краснела на
			# исправном коде (замер: 2.9 м центр, 2.6 м ближний, 50 с)
			var d_c: float = (u as Node3D).global_position.distance_to(
				target.global_position)
			if d_c <= (u as Unit).reach() + Unit.BLOCK_RADIUS + 0.2:
				reached = true
				break
		if reached:
			break
	verdict("E1 копейщики доходят до дистанции удара", reached,
		"кадров %d" % guard)
	verdict("E2 отметки «встали и стреляем» у пехоты не заводится",
		not GameManager.squad_ranged_engaged(sid),
		"отметка %s" % str(GameManager.squad_ranged_engaged(sid)))
	# ПРАВИЛО РАЗДЕЛЯЕТ РОДА ВОЙСК ПО pursues_target, и обе стороны берутся у
	# ЖИВЫХ бойцов на сцене: узел, созданный ради одного вопроса и не внесённый
	# в дерево, остался бы висеть утечкой в ObjectDB
	var probe: Array = _squad("archer", Constants.FACTION_PLAYER,
		spot + Vector3(0.0, 0.0, 12.0), 1, 1.0)
	var arch: Unit = probe[1][0]
	await pframes(2)
	verdict("E3 и правило по-прежнему про НЕПРЕСЛЕДУЮЩИХ",
		(men[0] as Unit).pursues_target() and not arch.pursues_target(),
		"копейщик преследует=%s, лучник=%s" % [
			str((men[0] as Unit).pursues_target()), str(arch.pursues_target())])
	_kill(arch)
	for u in men:
		_kill(u)
	for f in foes:
		_kill(f)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# F. НА МАРШЕ: ВРАГ В РАДИУСЕ — ВСТАЛИ И СТРЕЛЯЕМ
#
# Марш-перехват в проекте есть и равен attack_range + INTERCEPT_MARGIN. Здесь
# проверяется, что он и правда РАБОТАЕТ у стрелков: отряд, посланный мимо
# противника, не пробегает его молча
# ═════════════════════════════════════════════════════════════════════════════
func _f_on_march() -> void:
	print("\n═════ F. НА МАРШЕ ВСТАЮТ И СТРЕЛЯЮТ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-70.0, 0.0, 0.0)
	var mine: Array = _squad("archer", Constants.FACTION_PLAYER, spot, 8, 1.2)
	var men: Array = mine[1]
	var rng: float = (men[0] as Unit).attack_range
	# Противник стоит В СТОРОНЕ от маршрута, но в пределах выстрела
	var foe: Array = _squad("spearman", Constants.FACTION_ENEMY,
		spot + Vector3(30.0, 0.0, rng * 0.7), 4, 1.0)
	var foes: Array = foe[1]
	await pframes(6)
	for f in foes:
		(f as Unit).set_tick(false)
		(f as Unit).current_health = (f as Unit).max_health * 500.0
	var goal: Vector3 = spot + Vector3(60.0, 0.0, 0.0)
	var shots0: int = GameManager.arrows_fired
	for u in men:
		(u as Unit).command_move(goal, true)
	# Замок приказа игрока (FORCED_MOVE_SEC) намеренно глушит перехват — это
	# лечение «отряд отходит и разворачивается стрелять». Ждём его истечения:
	# заказ про огонь на марше, а не про отмену замка
	await pframes(int((Unit.FORCED_MOVE_SEC + 1.0) * 60.0))
	var guard := 0
	var stopped := false
	while guard < 60 * 25:
		await get_tree().physics_frame
		guard += 1
		if GameManager.arrows_fired > shots0:
			stopped = true
			break
	verdict("F1 отряд на марше заметил врага в радиусе и открыл огонь", stopped,
		"выстрелов +%d за %d кадров" % [GameManager.arrows_fired - shots0, guard])
	# И ВСТАЛ: приказ на движение исполняется дальше только после боя
	var p0: Vector3 = _centre(men)
	await pframes(60)
	var p1: Vector3 = _centre(men)
	print("  за секунду после первого выстрела центр прошёл %.2f м" % [
		p0.distance_to(p1)])
	verdict("F2 и остановился, а не пробежал мимо", p0.distance_to(p1) < 2.0,
		"прошёл %.2f м" % p0.distance_to(p1))
	for u in men:
		_kill(u)
	for f in foes:
		_kill(f)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# СЛУЖЕБНОЕ
# ═════════════════════════════════════════════════════════════════════════════
## Центр отряда — СРЕДНЕЕ по живым. Медиана здесь не нужна: отряд стенда цел и
## не расколот, а среднее ловит подползание точнее
## До ближайшего бойца ЧУЖОГО ОТРЯДА — по нему и судят «достаю ли я»
func _gap_to_squad(u: Node3D, foes: Array) -> float:
	var best := INF
	for f in foes:
		if f != null and is_instance_valid(f) and not (f as Unit).is_dead():
			best = minf(best,
				u.global_position.distance_to((f as Node3D).global_position))
	return best

## Насколько близко к цели подобрался самый передний
func _nearest_gap(men: Array, target: Node3D) -> float:
	var best := INF
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			best = minf(best,
				(u as Node3D).global_position.distance_to(target.global_position))
	return best

func _centre(men: Array) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			sum += (u as Node3D).global_position
			n += 1
	return sum / maxf(float(n), 1.0)

func _kill(u: Node) -> void:
	if u == null or not is_instance_valid(u):
		return
	var un := u as Unit
	if un != null and not un.is_dead():
		un.take_damage(maxf(un.max_health, un.current_health) * 10.0, null)
