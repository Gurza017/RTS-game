extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_gnoll_fix — ГНОЛЛЫ: БЕГ НА МЕСТЕ, АГРО, ДУГА, ПУЛЫ (спринт 14)
## ═══════════════════════════════════════════════════════════════════════════
##   A АГРО      — поводок инициативы ровно 10 м, дальность броска срезана
##                 до GNOLL_THROW_RANGE; враг внутри поводка поднимает гнолла,
##                 враг за ним — нет.
##   B БЕГ НА МЕСТЕ — гнолл, окружённый чужими телами, получает приказ отойти,
##                 не сдвигается и ЧЕРЕЗ GNOLL_KITE_GIVEUP признаёт отход
##                 невозможным: выходит из MOVING и встаёт. Это и есть лечение
##                 «бежит на месте с зацикленным звуком шагов».
##   C ДУГА      — кость летит БРОСКОМ ОТ РУКИ: пологая дуга, а не свеча
##                 (спринт 15 развернул навес спринта 14), вылетает с кадра
##                 замаха и кувыркается в полёте, а воткнувшись — замирает.
##   F СРОК      — упавшая кость исчезает за пять секунд.
##   D ПРОМАХ    — доля бросков уходит в землю и втыкается там КОСТЬЮ.
##   E ПУЛЫ      — стрела человека и кость гнолла в воздухе ОДНОВРЕМЕННО не
##                 путаются: у слоёв разные буферы и разные картинки, и каждый
##                 снаряд ведёт СВОЙ буфер до самой земли. Это стережёт ту
##                 самую жалобу «стрелы на лету превращались в кости».
##
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_gnoll_fix/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Arrow  := preload("res://scripts/Arrow.gd")

## ЧИСЛА ДО СПРИНТА 15. Требования сформулированы ОТНОСИТЕЛЬНО прежних
## («уменьшить до 2.5», «увеличить на 30 %»), и назвать их иначе нечем;
## нынешние читаются из конфига
const SPEED_BEFORE_S15 := 3.6
const COOLDOWN_BEFORE_S15 := 1.6
## Прежняя дуга — навес спринта 14, развёрнутый спринтом 15
const ARC_BEFORE_S15 := 1.35

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(300.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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
	print("\n═════ ИТОГ qa_gnoll_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var sc: PackedScene = Building.PRELOAD_SCENES.get(uid)
	if sc == null:
		return null
	var u: Unit = sc.instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

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

	await _a_aggro()
	await _b_running_in_place()
	await _c_arc()
	await _d_miss()
	await _e_pools()
	await _f_bone_life()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ПОВОДОК ИНИЦИАТИВЫ И ДАЛЬНОСТЬ БРОСКА
# ═════════════════════════════════════════════════════════════════════════════
func _a_aggro() -> void:
	print("\n═════ A. АГРО НА 10 М И КОРОТКИЙ БРОСОК ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, 60.0)
	var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN, spot)
	if g == null:
		verdict("A0 гнолл поставлен", false, "сцены gnoll нет в PRELOAD_SCENES")
		return
	await pframes(4)
	print("  поводок гнолла %.1f м (у пехоты %.1f), бросок %.1f м" % [
		g.aggro_leash(), Unit.AGGRO_LEASH, g.attack_range])
	verdict("A1 поводок инициативы — заказанные 10 м",
		absf(g.aggro_leash() - 10.0) < 0.01,
		"%.1f м" % g.aggro_leash())
	verdict("A2 поводок гнолла уже общего",
		g.aggro_leash() < Unit.AGGRO_LEASH,
		"%.1f против %.1f м" % [g.aggro_leash(), Unit.AGGRO_LEASH])
	verdict("A3 бросок кости короче выстрела лучника",
		absf(g.attack_range - _GobCfg.GNOLL_THROW_RANGE) < 0.01
			and g.attack_range < _UCfg.stat("archer", "attack_range", 20.0),
		"кость %.1f м, лук %.1f м" % [g.attack_range,
			_UCfg.stat("archer", "attack_range", 20.0)])
	verdict("A4 бросать дальше, чем видишь, нельзя: поводок шире броска",
		g.aggro_leash() > g.attack_range,
		"поводок %.1f, бросок %.1f м" % [g.aggro_leash(), g.attack_range])
	# ── ШАГ И ТЕМП БРОСКА (заказ спринта 15) ──────────────────────────────
	# Прежние числа записаны здесь прямо: требования звучат как «уменьшить до
	# 2.5» и «увеличить на 30 %», и выразить их иначе, чем назвав прежнее
	# значение, нечем
	print("  шаг гнолла %.2f (было %.2f), кулдаун %.2f с (было %.2f)" % [
		g.move_speed, SPEED_BEFORE_S15,
		_UCfg.stat("gnoll", "attack_cooldown", 0.0), COOLDOWN_BEFORE_S15])
	# Число правит владелец (14.09.2026: 2.5 → 2.2): стережём «не выше 2.5»
	verdict("A7 шаг гнолла срезан не выше 2.5",
		g.move_speed <= 2.5 + 0.01, "%.2f" % g.move_speed)
	verdict("A8 шаг стал медленнее прежнего", g.move_speed < SPEED_BEFORE_S15,
		"%.2f против %.2f" % [g.move_speed, SPEED_BEFORE_S15])
	# СПРИНТ 20: поверх +30 % спринта 15 владелец срезал 15 % («гноллы
	# бросают чаще»): 1.6 × 1.3 × 0.85 = 1.77
	verdict("A9 кулдаун броска: +30 % (спринт 15) и −15 % (спринт 20)",
		absf(_UCfg.stat("gnoll", "attack_cooldown", 0.0)
			- COOLDOWN_BEFORE_S15 * 1.3 * 0.85) < 0.01,
		"%.2f при ожидаемых %.2f" % [_UCfg.stat("gnoll", "attack_cooldown", 0.0),
			COOLDOWN_BEFORE_S15 * 1.3 * 0.85])

	# ── ВРАГ ВНУТРИ ПОВОДКА — ГНОЛЛ ВСТУПАЕТ ───────────────────────────────
	var near_foe: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(g.aggro_leash() * 0.7, 0.0, 0.0))
	await pframes(4)
	near_foe.set_tick(false)
	var took_near: bool = await _watch_aggro(g, spot, 120)
	verdict("A5 враг ВНУТРИ поводка поднимает гнолла", took_near,
		"враг в %.1f м при поводке %.1f м" % [
			g.aggro_leash() * 0.7, g.aggro_leash()])
	_kill(near_foe)
	g.set_attack_target(null)
	g.state = g.State.IDLE
	await pframes(20)

	# ── ВРАГ ЗА ПОВОДКОМ — ГНОЛЛ ОСТАЁТСЯ У ПНЯ ────────────────────────────
	var far_foe: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(g.aggro_leash() * 2.2, 0.0, 0.0))
	await pframes(4)
	far_foe.set_tick(false)
	g.set_attack_target(null)
	g.state = g.State.IDLE
	var took_far: bool = await _watch_aggro(g, spot, 120)
	verdict("A6 враг ЗА поводком гнолла не поднимает", not took_far,
		"враг в %.1f м при поводке %.1f м" % [
			g.aggro_leash() * 2.2, g.aggro_leash()])
	_kill(far_foe)
	_kill(g)
	await pframes(4)

## Брал ли гнолл цель хоть раз за n физкадров, СТОЯ НА МЕСТЕ.
##
## ГНОЛЛА ПРИХОДИТСЯ ПРИКАЛЫВАТЬ К ТОЧКЕ, И ЭТО НЕ ПОДТАСОВКА. Тик гнолла
## подхватывает логово ПАРТИИ (оно есть на любой живой карте) и уводит его
## патрулировать кольцо вокруг пня — вместе с постом, от которого поводок и
## отмеряется. Замер тогда судил бы о том, куда гнолла унесло, а не о поводке.
## Тик при этом НЕ гасится: авто-агро живёт именно в нём, и без него проверка
## стала бы пустой
func _watch_aggro(g: Unit, at: Vector3, n: int) -> bool:
	var took := false
	for _i in range(n):
		g.global_position = at
		g.post_pos = at
		g.sync_row()
		await get_tree().physics_frame
		if g.attack_target != null and is_instance_valid(g.attack_target):
			took = true
	return took

# ═════════════════════════════════════════════════════════════════════════════
# B. БЕГ НА МЕСТЕ
#
# СЦЕНАРИЙ ВОСПРОИЗВОДИТ ЖАЛОБУ ДОСЛОВНО: гнолл в кольце чужих тел. Кайт видит
# пехоту вплотную и раз в GNOLL_KITE_SEC выдаёт приказ отойти, а сквозь чужой
# строй не проходит никто — приказ не исполняется НИ НА САНТИМЕТР, и боец
# вечно остаётся в MOVING с зацикленным лупом шагов.
# ═════════════════════════════════════════════════════════════════════════════
func _b_running_in_place() -> void:
	print("\n═════ B. НЕ БЕЖИТ НА МЕСТЕ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-60.0, 0.0, 60.0)
	var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN, spot)
	if g == null:
		verdict("B0 гнолл поставлен", false)
		return
	await pframes(4)
	g.post_pos = spot
	# КОЛЬЦО ЧУЖИХ ТЕЛ. Радиус тесный: просвет между соседями обязан быть уже
	# двух радиусов тела, иначе гнолл проскользнёт между ними и замер выйдет
	# не про то. Копейщики заморожены — они не должны его убить за время замера
	var ring: Array = []
	var n := 12
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var p: Vector3 = spot + Vector3(cos(a) * 1.6, 0.0, sin(a) * 1.6)
		var s: Unit = _spawn("spearman", Constants.FACTION_PLAYER, p)
		s.set_tick(false)
		ring.append(s)
	await pframes(6)
	var start: Vector3 = g.global_position
	# Ждём дольше, чем окно кайта плюс срок проверки: первый отход обязан быть
	# выдан, признан безрезультатным и заглушён
	var wait_f: int = int((_GobCfg.GNOLL_KITE_SEC + _GobCfg.GNOLL_KITE_GIVEUP
		+ 1.5) * 60.0)
	await pframes(wait_f)
	var moved: float = start.distance_to(g.global_position)
	print("  отходов выдано %d, признано невозможными %d, сдвинулся на %.2f м, состояние %d" % [
		int(g.kites), int(g.kite_blocked), moved, int(g.state)])
	verdict("B1 кайт вообще пробовался (сцена воспроизводит жалобу)",
		int(g.kites) > 0, "отходов %d" % int(g.kites))
	# Внутри кольца радиусом 1.6 м гнолл вправе качнуться на метр (серия
	# кайтов, 14.09.2026): «некуда» — это не вышел из кольца, порог ×1.5
	verdict("B2 отойти было и правда некуда (из кольца не вышел)",
		moved < _GobCfg.GNOLL_KITE_MIN_GAIN * 1.5,
		"сдвинулся на %.2f м при пороге %.2f" % [moved,
			_GobCfg.GNOLL_KITE_MIN_GAIN * 1.5])
	verdict("B3 гнолл ПРИЗНАЛ отход невозможным",
		int(g.kite_blocked) > 0, "блокировок %d" % int(g.kite_blocked))
	verdict("B4 и вышел из состояния ХОДЬБЫ — лупа шагов больше нет",
		g.state != g.State.MOVING,
		"состояние %d (MOVING=%d)" % [int(g.state), int(g.State.MOVING)])
	verdict("B5 скорость обнулена, ноги не перебирают",
		g.velocity.length() < 0.05 and not g.moved_recently(),
		"|v|=%.3f, признак хода=%s" % [g.velocity.length(),
			str(g.moved_recently())])
	for s in ring:
		_kill(s)
	_kill(g)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# C. ЧЕСТНАЯ НАВЕСНАЯ ДУГА
# ═════════════════════════════════════════════════════════════════════════════
func _c_arc() -> void:
	print("\n═════ C. КОСТЬ ЛЕТИТ НАВЕСОМ, А НЕ ПО ПРЯМОЙ ═════")
	# Подъём дуги считается как dist × arc_factor (Arrow.launch), поэтому сам
	# множитель И ЕСТЬ отношение «высота дуги к дальности» — сравнивать можно
	# прямо его, не гоняя снаряд
	var bone_arc: float = _GobCfg.GNOLL_BONE_ARC
	var arrow_arc: float = _UCfg.stat("archer", "arrow_arc", 0.5)
	var bone_r: float = _GobCfg.GNOLL_THROW_RANGE
	print("  кость: дуга ×%.2f на %.1f м = подъём %.1f м; стрела: ×%.2f" % [
		bone_arc, bone_r, bone_arc * bone_r, arrow_arc])
	# ── РАЗВОРОТ СПРИНТА 15: БРОСОК ОТ РУКИ, А НЕ НАВЕС ───────────────────
	# Спринт 14 требовал навеса и получил дугу ×1.35 — подъём БОЛЬШЕ самой
	# дальности, то есть свечу под облака. Заказ спринта 15 прямо разворачивает
	# это: «почти по прямой с минимальной дугой». Ноль при этом не годится —
	# совсем прямая кость читается зависшей палкой, поэтому проверяются ОБА
	# берега
	verdict("C1 дуга стала пологой, а не свечой", bone_arc < ARC_BEFORE_S15 * 0.25,
		"×%.2f против прежних ×%.2f" % [bone_arc, ARC_BEFORE_S15])
	verdict("C2 но и не строго прямая: дуга различима глазом",
		bone_arc > 0.05 and bone_arc * bone_r > 0.8,
		"подъём %.2f м при броске %.1f м" % [bone_arc * bone_r, bone_r])
	verdict("C3 дальность броска короткая — далеко по прямой не улетит",
		bone_r <= 9.0, "%.1f м" % bone_r)
	# И ЖИВОЙ ЗАМЕР: кость в полёте обязана подняться над прямой «стрелок → цель»
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, -60.0)
	var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN, spot)
	var foe: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(bone_r * 0.95, 0.0, 0.0))
	await pframes(4)
	# ── МЕТАТЕЛЯ ЗАМОРАЖИВАТЬ НЕЛЬЗЯ ──────────────────────────────────────
	# Со спринта 15 бросок ОТЛОЖЕН до кадра замаха, а отсчёт задержки живёт в
	# тике гнолла: у замороженного (`set_tick(false)`) кость не вылетит вовсе.
	# Первая версия этой проверки так и намеряла «в воздухе 0» на работающем
	# коде. Стоять на месте гнолла заставляет не заморозка, а прикалывание
	# точки (_pin) — патруль иначе уводит его с площадки замера
	foe.set_tick(false)
	var pin_c: Vector3 = g.global_position
	# ── СВОЁ АГРО ГНОЛЛА ГЛУШИМ (14.09.2026) ──────────────────────────────
	# Гнолл без пня раньше «отходил» к первому логову партии и своего броска
	# не делал; с домашней точкой он стоит и сам берёт копейщика в 8 м —
	# его собственная кость залетала в окно C5/C6 и мигала обоими вердиктами.
	# Бросок здесь — РУЧНОЙ (_on_attack_fired), автоагро на время замера снято
	g.set_attack_target(null)
	g.set("_aggro_timer", 1.0e9)
	await _pin(g, pin_c, 30)
	while _bones_in_flight() > 0:
		await _pin(g, pin_c, 10)
	# ── БРОСОК ВЫЛЕТАЕТ НЕ В ТОТ ЖЕ КАДР, И ЭТО ТРЕБОВАНИЕ ────────────────
	# Боевая петля зовёт _on_attack_fired в момент удара, а кость обязана
	# покинуть руку на кадре замаха (GNOLL_THROW_FRAME). Проверяем оба конца:
	# сразу после вызова в воздухе пусто, а через задержку кость появилась
	var flying0: int = _bones_in_flight()
	g._on_attack_fired(foe, g.attack_damage)
	await _pin(g, pin_c, 2)
	verdict("C5 в тот же кадр кость НЕ вылетает — рука ещё за спиной",
		_bones_in_flight() == flying0,
		"в воздухе %d" % _bones_in_flight())
	var wait_f: int = int(g.call("_throw_delay") * 60.0) + 8
	await _pin(g, pin_c, wait_f)
	verdict("C6 на кадре замаха кость вылетела",
		_bones_in_flight() > flying0,
		"ждали %.2f с, в воздухе %d" % [g.call("_throw_delay"),
			_bones_in_flight()])
	# ── ТОЧКУ ЛЕТЯЩЕГО СНАРЯДА ЗНАЕТ БУФЕР, А НЕ УЗЕЛ ──────────────────────
	# На время полёта стрела (и кость) — ЗАПИСЬ в ядре: узел без своего тика
	# стоит там, где взлетел, а позицию ведёт BatchArrows и пишет прямо в слот
	# общего MultiMesh. Мерить высоту дуги по global_position значит мерить
	# точку вылета — первая версия этой проверки так и сделала и намеряла
	# ровно GNOLL_THROW_Y
	var peak := 0.0
	var spin_flying := 0.0
	for _i in range(60):
		g.global_position = pin_c
		g.sync_row()
		await get_tree().physics_frame
		for b in _projectiles(true):
			if bool(b.get("_spent")) or bool(b.get("_pooled")):
				continue
			var p: Vector3 = _drawn_point(b)
			if p == Vector3.INF:
				continue
			peak = maxf(peak, p.y - GameManager.get_terrain_height(p.x, p.z))
			spin_flying = maxf(spin_flying, _axis_len(b))
	print("  живой замер: кость поднялась на %.2f м над грунтом (бросок %.1f м)" % [
		peak, bone_r])
	# Пик считается НАД ТОЧКОЙ ВЫЛЕТА: сама рука гнолла на GNOLL_THROW_Y, и
	# путать высоту броска с высотой дуги нельзя
	var rise: float = peak - _GobCfg.GNOLL_THROW_Y
	verdict("C4 живая кость поднимается НЕМНОГО, а не свечой",
		rise > 0.15 and rise < bone_r * 0.5,
		"подъём над рукой %.2f м при броске %.1f м" % [rise, bone_r])
	print("  модуль оси в полёте %.2f (кувырок), у стрелы %.2f" % [
		spin_flying, _GobCfg.GNOLL_BONE_AXIS_K])
	# ── КУВЫРОК ЕДЕТ В МОДУЛЕ ОСИ ─────────────────────────────────────────
	# Шейдер ось нормирует, поэтому её длина свободна и несёт один бит: короче
	# порога — снаряд летит и кувыркается, ровно единица — воткнулся и лежит.
	# Проверяется именно ЧИСЛО В БУФЕРЕ: картинку headless не рисует вовсе
	verdict("C7 летящая кость помечена в буфере как кувыркающаяся",
		spin_flying > 0.0
			and absf(spin_flying - _GobCfg.GNOLL_BONE_AXIS_K) < 0.05,
		"модуль оси %.2f при заказанном %.2f" % [spin_flying,
			_GobCfg.GNOLL_BONE_AXIS_K])
	_kill(g)
	_kill(foe)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. ПРОМАХ ВТЫКАЕТСЯ В ЗЕМЛЮ КОСТЬЮ
# ═════════════════════════════════════════════════════════════════════════════
func _d_miss() -> void:
	print("\n═════ D. ПРОМАХ ТОРЧИТ КОСТЬЮ В ЗЕМЛЕ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-60.0, 0.0, -60.0)
	var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN, spot)
	var foe: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(_GobCfg.GNOLL_THROW_RANGE * 0.8, 0.0, 0.0))
	await pframes(4)
	# ── МЕТАТЕЛЯ ЗАМОРАЖИВАТЬ НЕЛЬЗЯ ──────────────────────────────────────
	# Со спринта 15 бросок ОТЛОЖЕН до кадра замаха, а отсчёт задержки живёт в
	# тике гнолла: у замороженного (`set_tick(false)`) кость не вылетит вовсе.
	# Первая версия этой проверки так и намеряла «в воздухе 0» на работающем
	# коде. Стоять на месте гнолла заставляет не заморозка, а прикалывание
	# точки (_pin) — патруль иначе уводит его с площадки замера
	foe.set_tick(false)
	foe.current_health = foe.max_health * 100.0
	var pin_d: Vector3 = g.global_position
	var stuck0: int = GameManager.stuck_arrow_count()
	# ── БРОСКИ РАЗНЕСЕНЫ ВО ВРЕМЕНИ, И ЭТО НЕ ФОРМАЛЬНОСТЬ ────────────────
	# Замах теперь занимает GNOLL_THROW_FRAME кадров ленты, и второй приказ,
	# отданный в тот же кадр, ПЕРЕБИВАЕТ первый: в руке одна кость, а не
	# очередь. В бою так и есть — бросок раз в кулдаун; стенд обязан вести
	# себя так же, иначе он проверял бы очередь, которой в игре нет
	var shots := 20
	var gap_f: int = int(g.call("_throw_delay") * 60.0) + 6
	for _i in range(shots):
		g._on_attack_fired(foe, 0.0)
		await _pin(g, pin_d, gap_f)
	await _pin(g, pin_d, 200)
	var stuck_bones: int = _count_stuck(true)
	print("  бросков %d, из них промахов %d; торчит костей %d (было торчащих %d)" % [
		int(g.bones_thrown), int(g.bones_missed), stuck_bones, stuck0])
	verdict("D1 промахи есть и их доля близка к заказанной",
		int(g.bones_missed) > 0
			and float(g.bones_missed) / float(maxi(int(g.bones_thrown), 1))
				< _GobCfg.GNOLL_MISS_CHANCE * 2.2,
		"%d из %d при доле %.2f" % [int(g.bones_missed), int(g.bones_thrown),
			_GobCfg.GNOLL_MISS_CHANCE])
	verdict("D2 промахнувшаяся кость ВТЫКАЕТСЯ В ЗЕМЛЮ и лежит там",
		stuck_bones > 0, "костей в земле %d" % stuck_bones)
	# ── ЛЕЖАЩАЯ КОСТЬ НЕ КУВЫРКАЕТСЯ (заказ спринта 16) ─────────────────
	# Кувырок включает шейдер по КОРОТКОЙ оси (модуль < spin_gate); у
	# воткнувшейся кости узел пишет ось единичной длины (Arrow.axis_scale
	# отвечает 1.0 у _spent) — значит в буфере обязана лежать полная ось
	var short_axes := 0
	var stuck_seen := 0
	for b in _projectiles(true):
		if not bool(b.get("_spent")) or bool(b.get("_pooled")):
			continue
		stuck_seen += 1
		if _axis_len(b) < 0.75:
			short_axes += 1
	verdict("D2б лежащая кость помечена НЕПОДВИЖНОЙ (ось полной длины)",
		stuck_seen > 0 and short_axes == 0,
		"лежит %d, с короткой осью %d" % [stuck_seen, short_axes])
	verdict("D3 торчащих на поле стало больше",
		GameManager.stuck_arrow_count() > stuck0,
		"%d против %d" % [GameManager.stuck_arrow_count(), stuck0])
	_kill(g)
	_kill(foe)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# E. ПУЛЫ СНАРЯДОВ РАЗДЕЛЕНЫ ДО САМОЙ ЗЕМЛИ
#
# ЖАЛОБА ВЛАДЕЛЬЦА ДОСЛОВНО: «лучники стреляли стрелами, стрелы летели и в
# какой-то момент превращались в кости». То есть ломалась не выдача снаряда
# (её проверяют E1-E3), а САМ ПОЛЁТ: номер буфера отрисовки в ядре был ОДНИМ
# ПОЛЕМ на все полёты сразу, и следующий взлетевший снаряд забирал буфер себе.
# Поэтому решающая проверка — E4: стрела и кость летят ОДНОВРЕМЕННО, и точка
# каждой обязана лежать в СВОЁМ буфере.
# ═════════════════════════════════════════════════════════════════════════════
func _e_pools() -> void:
	print("\n═════ E. СТРЕЛА НЕ СТАНОВИТСЯ КОСТЬЮ ═════")
	# ── ПЛОЩАДКИ РАЗНЕСЕНЫ НАМЕРЕННО ───────────────────────────────────────
	# Коридор полёта стрелы и коридор полёта кости не должны пересекаться
	# нигде: только тогда «точка снаряда лежит в чужом коридоре» однозначно
	# означает подмену буфера, а не совпадение
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, 80.0)
	# ЛОВУШКА: площадка лежит в 30 м от «красного пня», а его гноллы патрулируют
	# кольцом 26 м и с 13 м бросают кость в замороженного лучника — стенд
	# ронял SCRIPT ERROR «previously freed» в трёх прогонах из четырёх
	# (19.09.2026). Дикие пня на время блока стоят
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction == Constants.FACTION_GOBLIN:
			(n as Unit).set_tick(false)
	var arch: Unit = _spawn("archer", Constants.FACTION_PLAYER, spot)
	# Цель — ВНУТРИ дальности лука (правило 10): с ТЗ 19.09.2026 снаряд не
	# рождается дальше досягаемости (Archer._shot_reach), и прежние 16 м при
	# базе 15 оставляли слой стрел пустым — E1/E2/E6 краснели без единой стрелы
	var tgt_a: Unit = _spawn("spearman", Constants.FACTION_GOBLIN,
		spot + Vector3(0.0, 0.0, minf(16.0, arch.attack_range - 2.0)))
	var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN,
		spot + Vector3(48.0, 0.0, 0.0))
	var tgt_g: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(48.0, 0.0, 7.0))
	await pframes(4)
	# Метателя не морозим (см. оговорку в блоке C); остальные стоят
	for u in [arch, tgt_a, tgt_g]:
		u.set_tick(false)
	var pin_e: Vector3 = g.global_position
	tgt_a.current_health = tgt_a.max_health * 1000.0
	tgt_g.current_health = tgt_g.max_health * 1000.0

	# ВЗЛЕТАЮТ ВПЕРЕМЕЖКУ: именно чередование и ловило прежнюю ошибку — номер
	# буфера в ядре был ОДНИМ ПОЛЕМ на все полёты, и второй взлетевший забирал
	# буфер у первого, то есть стрела на лету начинала рисоваться костью
	for _i in range(6):
		arch._on_attack_fired(tgt_a, 0.0)
		g._on_attack_fired(tgt_g, 0.0)
		await _pin(g, pin_e, int(g.call("_throw_delay") * 60.0) + 6)

	var am = GameManager.arrows_mm
	var bm = GameManager.bones_mm
	verdict("E1 у стрел и костей РАЗНЫЕ буферы отрисовки",
		am != null and bm != null and am.core_id >= 0 and bm.core_id >= 0
			and am.core_id != bm.core_id,
		"стрелы %d, кости %d" % [
			am.core_id if am != null else -1, bm.core_id if bm != null else -1])
	# Картинку слой держит не полем, а параметром своего шейдера: материал у
	# бакета ОДИН на все снаряды, и подменить её на лету нельзя — ровно потому
	# кости и понадобился второй слой
	var tex_a: Variant = null
	var tex_b: Variant = null
	if am != null and am.mat != null:
		tex_a = am.mat.get_shader_parameter("albedo_tex")
	if bm != null and bm.mat != null:
		tex_b = bm.mat.get_shader_parameter("albedo_tex")
	verdict("E2 и разные картинки",
		tex_a != null and tex_b != null and tex_a != tex_b,
		"%s против %s" % [str(tex_a), str(tex_b)])

	var bad_arrow := 0
	var bad_bone := 0
	var checked := 0
	for _step in range(50):
		g.global_position = pin_e
		g.sync_row()
		await get_tree().physics_frame
		for p in _projectiles(false):
			if bool(p.get("_spent")) or bool(p.get("_pooled")):
				continue
			var is_bone: bool = bool(p.get("bone"))
			var dp: Vector3 = _drawn_point(p)
			if dp == Vector3.INF:
				continue
			checked += 1
			# СНАРЯД ОБЯЗАН ЛЕЖАТЬ В СВОЁМ КОРИДОРЕ. Отклонение по земле от
			# отрезка «вылет → цель» у честного полёта нулевое: дуга поднимает
			# только высоту. Метровый допуск — чистый запас
			var off: float = _off_corridor(p, dp)
			if off > 1.0:
				if is_bone: bad_bone += 1
				else:       bad_arrow += 1
	print("  сверок точки со своим коридором %d: увело стрел %d, костей %d" % [
		checked, bad_arrow, bad_bone])
	verdict("E3 замер вообще состоялся (снаряды были в воздухе)", checked > 0,
		"сверок %d" % checked)
	verdict("E4 стрела всю дорогу летит СВОИМ путём, а не чужим", bad_arrow == 0,
		"увело %d раз" % bad_arrow)
	verdict("E5 и кость тоже", bad_bone == 0, "увело %d раз" % bad_bone)

	# ── И ПОСЛЕ ПРИЗЕМЛЕНИЯ ────────────────────────────────────────────────
	# Цели убираем: непопавший снаряд втыкается в землю, и на поле обязаны
	# оказаться И стрелы, И кости — каждая своим видом
	var stuck0_a := _count_stuck(false)
	var stuck0_b := _count_stuck(true)
	# ── ЦЕЛЬ ОТХОДИТ В СТОРОНУ СРАЗУ ПОСЛЕ ВЫСТРЕЛА ───────────────────────
	# Снаряд обязан лечь в ЗЕМЛЮ, иначе мерить нечего. Прежде цели убивали
	# после всего залпа — это работало, пока весь залп уходил в один кадр; с
	# отложенным броском между выстрелами проходит почти полсекунды, и стрелы
	# успевали попасть в живую цель. Точка прицеливания у обоих снимается В
	# МОМЕНТ ВЫСТРЕЛА, поэтому достаточно сдвинуть цель сразу после него:
	# снаряд долетит до пустого места и воткнётся
	var side := 1.0
	# Кость лежит в земле BONE_STUCK_LIFETIME (5 с), а двенадцать бросков с
	# ожиданием замаха занимают дольше: к концу окна первые кости уже сняты
	# сроком, и «конец минус начало» мигал (спринт 18: +7 / +1 / −1). Судим по
	# ПИКУ прироста за окно — втыкалась ли кость вообще
	var peak_b := 0
	for _i in range(12):
		peak_b = maxi(peak_b, _count_stuck(true) - stuck0_b)
		arch._on_attack_fired(tgt_a, 0.0)
		g._on_attack_fired(tgt_g, 0.0)
		await _pin(g, pin_e, int(g.call("_throw_delay") * 60.0) + 4)
		side = -side
		for t in [tgt_a, tgt_g]:
			if is_instance_valid(t):
				var tp: Vector3 = t.global_position
				tp.x += side * 7.0
				t.global_position = Vector3(tp.x,
					GameManager.get_terrain_height(tp.x, tp.z), tp.z)
				t.sync_row()
	await pframes(220)
	var stuck_a: int = _count_stuck(false)
	var stuck_b: int = _count_stuck(true)
	print("  воткнулось за замер: стрел %d, костей %d" % [
		stuck_a - stuck0_a, stuck_b - stuck0_b])
	peak_b = maxi(peak_b, stuck_b - stuck0_b)
	verdict("E6 на земле лежат и стрелы, и кости — каждая своим видом",
		stuck_a > stuck0_a and peak_b > 0,
		"стрел +%d, костей +%d (пик за окно +%d)" % [stuck_a - stuck0_a, stuck_b - stuck0_b, peak_b])
	_kill(arch)
	_kill(g)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# F. УПАВШАЯ КОСТЬ ИСЧЕЗАЕТ ЗА ПЯТЬ СЕКУНД
#
# Гноллов у пня три отряда, и бросают они вчетверо чаще, чем стреляет лучник:
# со сроком стрелы (45 с) поле вокруг пня превращалось в ковёр из костей.
# Срок теперь СВОЙ по виду снаряда, и стенд стережёт обе его стороны — и что
# кость исчезает, и что СТРЕЛА при этом лежит по-прежнему долго
# ═════════════════════════════════════════════════════════════════════════════
func _f_bone_life() -> void:
	print("\n═════ F. КОСТЬ ЛЕЖИТ ПЯТЬ СЕКУНД ═════")
	print("  срок кости %.1f с, срок стрелы %.1f с" % [
		_Arrow.BONE_STUCK_LIFETIME, _Arrow.STUCK_LIFETIME])
	verdict("F1 у кости свой срок, и он ровно пять секунд",
		absf(_Arrow.BONE_STUCK_LIFETIME - 5.0) < 0.01,
		"%.1f с" % _Arrow.BONE_STUCK_LIFETIME)
	verdict("F2 стрела по-прежнему лежит долго — срок разделён по виду",
		_Arrow.STUCK_LIFETIME > _Arrow.BONE_STUCK_LIFETIME * 5.0,
		"стрела %.1f с против кости %.1f" % [_Arrow.STUCK_LIFETIME,
			_Arrow.BONE_STUCK_LIFETIME])
	verdict("F3 растворение короче самого срока, иначе кость мигала бы сразу",
		_Arrow.BONE_STUCK_FADE < _Arrow.BONE_STUCK_LIFETIME * 0.5,
		"%.1f из %.1f с" % [_Arrow.BONE_STUCK_FADE,
			_Arrow.BONE_STUCK_LIFETIME])

	# ── ЖИВОЙ ЗАМЕР ───────────────────────────────────────────────────────
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, -80.0)
	var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN, spot)
	var foe: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(_GobCfg.GNOLL_THROW_RANGE * 0.8, 0.0, 0.0))
	await pframes(4)
	# ── МЕТАТЕЛЯ ЗАМОРАЖИВАТЬ НЕЛЬЗЯ ──────────────────────────────────────
	# Со спринта 15 бросок ОТЛОЖЕН до кадра замаха, а отсчёт задержки живёт в
	# тике гнолла: у замороженного (`set_tick(false)`) кость не вылетит вовсе.
	# Первая версия этой проверки так и намеряла «в воздухе 0» на работающем
	# коде. Стоять на месте гнолла заставляет не заморозка, а прикалывание
	# точки (_pin) — патруль иначе уводит его с площадки замера
	foe.set_tick(false)
	foe.current_health = foe.max_health * 100.0
	var pin_f: Vector3 = g.global_position
	var stuck0: int = _count_stuck(true, pin_f)
	# Бросаем, пока хоть одна кость не ляжет в землю: доля промахов — 0.3,
	# и одного броска на это не хватит
	var guard := 0
	while guard < 60 * 40 and _count_stuck(true, pin_f) <= stuck0:
		if int(g.get("_throw_left")) == 0 and g.get("_throw_left") <= 0.0:
			g._on_attack_fired(foe, 0.0)
		for _i in range(int(g.call("_throw_delay") * 60.0) + 90):
			g.global_position = pin_f
			g.sync_row()
			await get_tree().physics_frame
			guard += 1
			if _count_stuck(true, pin_f) > stuck0:
				break
	var landed: int = _count_stuck(true, pin_f)
	verdict("F4 кость и правда легла в землю (иначе мерить нечего)",
		landed > stuck0, "торчит костей %d" % landed)
	if landed <= stuck0:
		_kill(g)
		_kill(foe)
		return
	# ── ИСТОЧНИК КОСТЕЙ УБИРАЕМ, ИНАЧЕ ЗАМЕР СЧИТАЕТ ЧУЖИЕ ────────────────
	# Гнолл тикает (иначе бросок не вылетит вовсе) и потому продолжает метать
	# в живого врага сам: первая версия ловила на поле СВЕЖУЮ кость и считала,
	# что старая не истекла
	_kill(g)
	_kill(foe)
	await pframes(4)
	var base: int = _count_stuck(true, pin_f)
	# ── ЖДЁМ ТЕМИ ЖЕ ЧАСАМИ, КОТОРЫМИ ИДЁТ СРОК ───────────────────────────
	# Срок торчащих считает ОБЩИЙ ОБХОД в _process (см. GameManager.
	# _sweep_stuck_arrows), то есть по кадрам ОТРИСОВКИ и реальному времени, а
	# не по физкадрам. В headless эти часы расходятся в разы: первая версия
	# ждала 150 физкадров и находила поле уже чистым (правило 12)
	await get_tree().create_timer(_Arrow.BONE_STUCK_LIFETIME * 0.4).timeout
	var mid: int = _count_stuck(true, pin_f)
	await get_tree().create_timer(_Arrow.BONE_STUCK_LIFETIME * 0.9).timeout
	var gone: int = _count_stuck(true, pin_f)
	stuck0 = base - (landed - stuck0)
	print("  костей в земле: легло %d, через полсрока %d, через срок %d" % [
		base, mid, gone])
	verdict("F5 на полусроке кость ещё лежит", mid > 0,
		"костей %d" % mid)
	verdict("F6 через пять секунд её на поле нет", gone == 0,
		"осталось %d" % gone)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# СЛУЖЕБНОЕ
# ═════════════════════════════════════════════════════════════════════════════
## Подождать n физкадров, удерживая бойца на месте. Тик ему при этом НУЖЕН
## (в нём живут и авто-агро, и отложенный бросок), а патруль иначе уводит его
## с площадки замера — та же оговорка, что у _watch_aggro
func _pin(u: Unit, at: Vector3, n: int) -> void:
	for _i in range(n):
		if is_instance_valid(u):
			u.global_position = at
			u.sync_row()
		await get_tree().physics_frame

## Сколько костей сейчас в воздухе (не воткнувшихся и не в пуле)
func _bones_in_flight() -> int:
	var n := 0
	for b in _projectiles(true):
		if not bool(b.get("_spent")) and not bool(b.get("_pooled")):
			n += 1
	return n

## Модуль оси, записанной снаряду в буфер отрисовки. Единица — снаряд лежит
## смирно, меньше — помечен кувырком (см. mm_arrow.gdshader)
func _axis_len(p) -> float:
	if p is Dictionary:
		return (p["axis"] as Vector3).length()
	var lay = GameManager.bones_mm if bool(p.get("bone")) else GameManager.arrows_mm
	if lay == null or lay.core_id < 0:
		return -1.0
	var si: int = int(p.get("_slot_i"))
	if si < 0:
		return -1.0
	var slot: PackedFloat32Array = GameManager.army.rb_slot(lay.core_id, si)
	if slot.size() < 16:
		return -1.0
	return Vector3(slot[12] * 2.0 - 1.0, slot[13] * 2.0 - 1.0,
		slot[14] * 2.0 - 1.0).length()

## Снаряды на поле. СНАРЯД БЕЗ УЗЛА (BigStand-5, этап 3): полёты и торчащие —
## записи ядра, здесь они СЛОВАРИ с теми же ключами, что стенд читал у узлов
## (_spent / _pooled / bone / _start_pos / _end_pos), плюс точка и ось из слота.
## Legacy-узлы Arrow (ручка выключена) добавляются как прежде. bones_only —
## только кости
func _projectiles(bones_only: bool) -> Array:
	var out: Array = []
	for fr in GameManager.flight_records():
		if bool(fr["legacy"]) or (bones_only and not bool(fr["bone"])):
			continue
		out.append({"_spent": false, "_pooled": false, "bone": fr["bone"],
			"_start_pos": fr["start"], "_end_pos": fr["end"],
			"pos": fr["pos"], "axis": fr["axis"]})
	for sr in GameManager.stuck_arrow_records():
		if bones_only and not bool(sr["bone"]):
			continue
		out.append({"_spent": true, "_pooled": false, "bone": sr["bone"],
			"_start_pos": sr["pos"], "_end_pos": sr["pos"],
			"pos": sr["pos"], "axis": sr["axis"]})
	var root: Node = main.world_root()
	for c in root.get_children():
		var n3 := c as Node3D
		if n3 == null:
			continue
		var sc: Variant = n3.get_script()
		if sc == null or not String((sc as Script).resource_path).ends_with("Arrow.gd"):
			continue
		if bones_only and not bool(n3.get("bone")):
			continue
		out.append(n3)
	return out

## ── ТОЧКА ЛЕТЯЩЕГО СНАРЯДА ЖИВЁТ В БУФЕРЕ ОТРИСОВКИ, А НЕ В УЗЛЕ ──────────
## Пока снаряд летит, он ЗАПИСЬ в ядре: узел стоит в точке вылета, а позицию
## ведёт BatchArrows и пишет прямо в слот общего MultiMesh (раскладка слота —
## 16 float, точка в 3/7/11). Vector3.INF — «слота нет, судить не о чем»
func _drawn_point(p) -> Vector3:
	if p is Dictionary:
		return p["pos"]
	var lay = GameManager.bones_mm if bool(p.get("bone")) else GameManager.arrows_mm
	if lay == null or lay.core_id < 0:
		return Vector3.INF
	var si: int = int(p.get("_slot_i"))
	if si < 0:
		return Vector3.INF
	var slot: PackedFloat32Array = GameManager.army.rb_slot(lay.core_id, si)
	if slot.size() < 16 or slot[0] == 0.0:
		return Vector3.INF
	return Vector3(slot[3], slot[7], slot[11])

## Насколько снаряд ушёл ПО ЗЕМЛЕ от собственного отрезка «вылет → цель».
## У честного полёта это ноль: дуга поднимает только высоту
func _off_corridor(p, at: Vector3) -> float:
	var s: Vector3 = p.get("_start_pos")
	var e: Vector3 = p.get("_end_pos")
	var a := Vector2(s.x, s.z)
	var b := Vector2(e.x, e.z)
	var q := Vector2(at.x, at.z)
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 0.0001:
		return q.distance_to(a)
	var t: float = clampf((q - a).dot(ab) / len2, 0.0, 1.0)
	return q.distance_to(a + ab * t)

## Сколько снарядов нужного вида торчит в земле прямо сейчас
## near/radius — считать только вокруг площадки замера: стая у пня живёт своей
## жизнью (со спринта 17 мимо неё ходят рейды и разведка обеих сторон), и её
## кости на другом конце карты замеру срока не принадлежат
func _count_stuck(bones: bool, near: Vector3 = Vector3.INF, radius: float = 40.0) -> int:
	var n := 0
	for r in GameManager.stuck_arrow_records():
		if bool(r["bone"]) != bones:
			continue
		if near != Vector3.INF:
			var rp: Vector3 = r["pos"]
			if Vector2(rp.x - near.x, rp.z - near.z).length() > radius:
				continue
		n += 1
	for a in GameManager._stuck_arrows:
		if a == null or not is_instance_valid(a):
			continue
		if bool((a as Node3D).get("bone")) != bones:
			continue
		if near != Vector3.INF:
			var p: Vector3 = (a as Node3D).global_position
			if Vector2(p.x - near.x, p.z - near.z).length() > radius:
				continue
		n += 1
	return n

## Убрать бойца со сцены смертью — единственным путём, на котором он снимает
## с себя строку ядра, место в сетке и место в отряде
func _kill(u: Node) -> void:
	if u == null or not is_instance_valid(u):
		return
	var un := u as Unit
	if un != null and not un.is_dead():
		# Бьём от БОЛЬШЕГО из запасов: стенд местами задирает current_health
		# выше максимума, чтобы цель пережила залп, и удар «десять максимумов»
		# такую не убивал бы вовсе
		un.take_damage(maxf(un.max_health, un.current_health) * 10.0, null)
