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
##   C ДУГА      — кость летит НАВЕСОМ: подъём дуги против дальности у неё в
##                 разы круче, чем у стрелы лучника, и на своей дальности она
##                 поднимается выше собственного пути по земле.
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
	verdict("B2 отойти было и правда некуда",
		moved < _GobCfg.GNOLL_KITE_MIN_GAIN,
		"сдвинулся на %.2f м при пороге %.2f" % [moved,
			_GobCfg.GNOLL_KITE_MIN_GAIN])
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
	verdict("C1 дуга кости круче стрелы В РАЗЫ", bone_arc > arrow_arc * 2.0,
		"×%.2f против ×%.2f" % [bone_arc, arrow_arc])
	verdict("C2 на своей дальности кость поднимается выше, чем летит по земле",
		bone_arc > 1.0, "подъём %.1f м при броске %.1f м" % [
			bone_arc * bone_r, bone_r])
	verdict("C3 дальность броска короткая — далеко по прямой не улетит",
		bone_r <= 9.0, "%.1f м" % bone_r)
	# И ЖИВОЙ ЗАМЕР: кость в полёте обязана подняться над прямой «стрелок → цель»
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, -60.0)
	var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN, spot)
	var foe: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(bone_r * 0.95, 0.0, 0.0))
	await pframes(4)
	g.set_tick(false)
	foe.set_tick(false)
	g._on_attack_fired(foe, g.attack_damage)
	# ── ТОЧКУ ЛЕТЯЩЕГО СНАРЯДА ЗНАЕТ БУФЕР, А НЕ УЗЕЛ ──────────────────────
	# На время полёта стрела (и кость) — ЗАПИСЬ в ядре: узел без своего тика
	# стоит там, где взлетел, а позицию ведёт BatchArrows и пишет прямо в слот
	# общего MultiMesh. Мерить высоту дуги по global_position значит мерить
	# точку вылета — первая версия этой проверки так и сделала и намеряла
	# ровно GNOLL_THROW_Y
	var peak := 0.0
	for _i in range(60):
		await get_tree().physics_frame
		for b in _projectiles(true):
			if bool(b.get("_spent")) or bool(b.get("_pooled")):
				continue
			var p: Vector3 = _drawn_point(b)
			if p == Vector3.INF:
				continue
			peak = maxf(peak, p.y - GameManager.get_terrain_height(p.x, p.z))
	print("  живой замер: кость поднялась на %.2f м над грунтом (бросок %.1f м)" % [
		peak, bone_r])
	verdict("C4 живая кость и правда идёт по навесу, а не по прямой",
		peak > _GobCfg.GNOLL_THROW_Y + 1.5,
		"пик %.2f м при вылете с %.2f м" % [peak, _GobCfg.GNOLL_THROW_Y])
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
	g.set_tick(false)
	foe.set_tick(false)
	foe.current_health = foe.max_health * 100.0
	var stuck0: int = GameManager.stuck_arrow_count()
	var shots := 40
	for _i in range(shots):
		g._on_attack_fired(foe, 0.0)
	await pframes(200)
	var stuck_bones := 0
	for a in GameManager._stuck_arrows:
		if a == null or not is_instance_valid(a):
			continue
		if bool((a as Node3D).get("bone")):
			stuck_bones += 1
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
	var arch: Unit = _spawn("archer", Constants.FACTION_PLAYER, spot)
	var tgt_a: Unit = _spawn("spearman", Constants.FACTION_GOBLIN,
		spot + Vector3(0.0, 0.0, 16.0))
	var g: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN,
		spot + Vector3(48.0, 0.0, 0.0))
	var tgt_g: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(48.0, 0.0, 7.0))
	await pframes(4)
	for u in [arch, g, tgt_a, tgt_g]:
		u.set_tick(false)
	tgt_a.current_health = tgt_a.max_health * 1000.0
	tgt_g.current_health = tgt_g.max_health * 1000.0

	# ВЗЛЕТАЮТ ВПЕРЕМЕЖКУ: именно чередование и ловило прежнюю ошибку — номер
	# буфера в ядре был ОДНИМ ПОЛЕМ на все полёты, и второй взлетевший забирал
	# буфер у первого, то есть стрела на лету начинала рисоваться костью
	for _i in range(6):
		arch._on_attack_fired(tgt_a, 0.0)
		g._on_attack_fired(tgt_g, 0.0)
		await pframes(3)

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
	for _i in range(12):
		arch._on_attack_fired(tgt_a, 0.0)
		g._on_attack_fired(tgt_g, 0.0)
	# Цели убираем, ПОКА СНАРЯДЫ В ВОЗДУХЕ: попадание ищется сканом сетки в
	# конце дуги, и без цели снаряд честно втыкается в грунт
	await pframes(2)
	_kill(tgt_a)
	_kill(tgt_g)
	await pframes(220)
	var stuck_a: int = _count_stuck(false)
	var stuck_b: int = _count_stuck(true)
	print("  воткнулось за замер: стрел %d, костей %d" % [
		stuck_a - stuck0_a, stuck_b - stuck0_b])
	verdict("E6 на земле лежат и стрелы, и кости — каждая своим видом",
		stuck_a > stuck0_a and stuck_b > stuck0_b,
		"стрел +%d, костей +%d" % [stuck_a - stuck0_a, stuck_b - stuck0_b])
	_kill(arch)
	_kill(g)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# СЛУЖЕБНОЕ
# ═════════════════════════════════════════════════════════════════════════════
## Живые узлы снарядов. bones_only — только кости
func _projectiles(bones_only: bool) -> Array:
	var out: Array = []
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
func _drawn_point(p: Node) -> Vector3:
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
func _off_corridor(p: Node, at: Vector3) -> float:
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
func _count_stuck(bones: bool) -> int:
	var n := 0
	for a in GameManager._stuck_arrows:
		if a == null or not is_instance_valid(a):
			continue
		if bool((a as Node3D).get("bone")) == bones:
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
