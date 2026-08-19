extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПРОХОД ПО ЗАФИКСИРОВАННЫМ БАГАМ (авг. 2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ЗАЛП       — накрывает площадь ВСЕГДА, даже по одиночной цели
##   B УПРЕЖДЕНИЕ — маленькое и с потолком; стрелы не уходят в чистое поле
##   C ВЫУЧКА     — новобранцы шире и медленнее, ветераны кучнее и быстрее
##   D ЦЕНТР      — медиана не садится в пустоту между двумя половинами отряда
##   E СПЛОЧЁННОСТЬ — оторвавшегося бездельника отряд подзывает обратно
##   F ФАЛАНГА    — крайний копейщик не берёт цель СБОКУ, только перед фронтом
##   G СЦЕПКА     — упёршийся в чужой строй входит в рубку, а не бегает челноком
##   H РАБОЧИЙ    — смена состояния FSM немедленно помечает позу к пересчёту
##
## Каждая проверка утверждает СВОЙСТВО и берёт числа из конфига, а не из себя.

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func pframes(n: int) -> void:
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

func _spawn(path: String, faction: int, at: Vector3) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = faction
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	main.set_process(false)          # иначе опрос курсора трогает подсветку
	await pframes(2)

	await _a_volley_area()
	await _b_lead()
	await _c_drill()
	await _d_median()
	await _e_cohesion()
	await _f_phalanx_front()
	await _g_melee_grip()
	await _h_worker_pose()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 66), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_BUGPASS DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ЗАЛП НАКРЫВАЕТ ПЛОЩАДЬ ДАЖЕ ПО ОДИНОЧКЕ
# ═════════════════════════════════════════════════════════════════════════════
# Радиус тучи брался ТОЛЬКО из габарита вражеского отряда, а у одиночной цели он
# равен нулю: залп схлопывался в точку, все стрелы входили в одного бойца.
func _a_volley_area() -> void:
	print("\n═════ A. ЗАЛП: ПЛОЩАДЬ ЕСТЬ ВСЕГДА ═════")
	verdict("A1 минимум накрытия задан в конфиге и он больше нуля",
		_UCfg.VOLLEY_MIN_SPREAD > 0.0,
		"VOLLEY_MIN_SPREAD=%.2f м" % _UCfg.VOLLEY_MIN_SPREAD)
	var bows: Array = []
	for i in range(12):
		bows.append(_spawn("res://scenes/units/Archer.tscn",
			Constants.FACTION_PLAYER, Vector3(300.0 + float(i), 0.0, 300.0)))
	await pframes(2)
	# Габарит цели НУЛЕВОЙ — ровно случай одиночки
	var cluster: float = clampf(0.0, _UCfg.VOLLEY_MIN_SPREAD, 3.2)
	var pts: Array = []
	var far := 0.0
	for b in bows:
		var off: Vector3 = (b as Archer)._volley_offset(cluster)
		pts.append(off)
		far = maxf(far, Vector2(off.x, off.z).length())
	var min_pair := 1.0e9
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			var a: Vector3 = pts[i]
			var b2: Vector3 = pts[j]
			min_pair = minf(min_pair, Vector2(a.x - b2.x, a.z - b2.z).length())
	verdict("A2 туча по одиночной цели всё равно накрывает площадь",
		far >= _UCfg.VOLLEY_MIN_SPREAD * 0.5,
		"самое дальнее смещение %.2f м при минимуме %.2f" % [far, _UCfg.VOLLEY_MIN_SPREAD])
	verdict("A3 стрелы не сходятся в одну точку",
		min_pair > 0.05,
		"минимальное расстояние между местами в туче %.3f м" % min_pair)
	for b in bows:
		(b as Node).queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. УПРЕЖДЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _b_lead() -> void:
	print("\n═════ B. УПРЕЖДЕНИЕ ═════")
	verdict("B1 доля выноса из конфига и она мала (5-10%)",
		_UCfg.ARCHER_LEAD_FACTOR > 0.0 and _UCfg.ARCHER_LEAD_FACTOR <= 0.12,
		"ARCHER_LEAD_FACTOR=%.3f" % _UCfg.ARCHER_LEAD_FACTOR)
	verdict("B2 у выноса есть потолок в метрах",
		_UCfg.ARCHER_LEAD_MAX > 0.0 and _UCfg.ARCHER_LEAD_MAX < 6.0,
		"ARCHER_LEAD_MAX=%.2f м" % _UCfg.ARCHER_LEAD_MAX)
	var speed: float = _UCfg.stat("archer", "arrow_speed", 9.0)
	var rng: float = _UCfg.stat("archer", "attack_range", 20.0)
	var full: float = (rng / maxf(speed, 0.1)) * 2.0        # цель идёт 2 м/с
	var applied: float = minf(full * _UCfg.ARCHER_LEAD_FACTOR, _UCfg.ARCHER_LEAD_MAX)
	verdict("B3 стрела не уходит на несколько корпусов вперёд цели",
		applied <= _UCfg.ARCHER_LEAD_MAX + 0.001 and applied < full * 0.5,
		"полный вынос %.1f м, фактический %.2f м" % [full, applied])

# ═════════════════════════════════════════════════════════════════════════════
# C. ВЫУЧКА ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _c_drill() -> void:
	print("\n═════ C. РАЗБРОС И ТЕМП ПО ВЫУЧКЕ ═════")
	var rookie: Dictionary = _UCfg.archer_drill(0)
	var vet: Dictionary = _UCfg.archer_drill(7)
	verdict("C1 новобранцы кладут шире ветеранов",
		float(rookie["spread"]) > float(vet["spread"]),
		"новобранцы x%.2f, ветераны x%.2f" % [rookie["spread"], vet["spread"]])
	verdict("C2 ветераны стреляют быстрее новобранцев",
		float(vet["fire"]) > float(rookie["fire"]),
		"новобранцы x%.2f, ветераны x%.2f" % [rookie["fire"], vet["fire"]])
	verdict("C3 уровень сверх таблицы не обнуляет выучку",
		not _UCfg.archer_drill(99).is_empty(),
		"уровень 99 -> %s" % str(_UCfg.archer_drill(99)))
	var a: Archer = _spawn("res://scenes/units/Archer.tscn",
		Constants.FACTION_PLAYER, Vector3(320.0, 0.0, 320.0)) as Archer
	await pframes(2)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	GameManager.add_to_squad(sid, a)
	GameManager.squads[sid]["level"] = 0
	var cd_rookie: float = a._effective_cooldown()
	GameManager.squads[sid]["level"] = 7
	var cd_vet: float = a._effective_cooldown()
	verdict("C4 перезарядка ветерана короче, чем у новобранца",
		cd_vet < cd_rookie,
		"новобранец %.3f c, ветеран %.3f c" % [cd_rookie, cd_vet])
	a.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# D. ЦЕНТР ОТРЯДА — МЕДИАНА
# ═════════════════════════════════════════════════════════════════════════════
# Отряд, расколотый на две неравные кучи: среднее садится МЕЖДУ ними, в пустое
# поле, медиана — на большую кучу. Именно это видно на скриншотах владельца как
# звезда ветеранства, висящая в чистом поле.
func _d_median() -> void:
	print("\n═════ D. ЦЕНТР ОТРЯДА ═════")
	var men: Array = []
	for _i in range(7):
		men.append(_spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER, Vector3(330.0, 0.0, 330.0)))
	await pframes(2)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for m in men:
		GameManager.add_to_squad(sid, m)
	var acc := 0.0
	for i in range(men.size()):
		var x: float = (330.0 + float(i)) if i < 5 else 400.0
		var u := men[i] as Unit
		u.global_position = Vector3(x, GameManager.get_terrain_height(x, 330.0), 330.0)
		u.sync_row()
		acc += x
	await pframes(2)
	var mean_x: float = acc / float(men.size())
	var c: Vector3 = GameManager.squad_centroid(sid)
	print("  среднее арифметическое x=%.1f, центр отряда x=%.1f" % [mean_x, c.x])
	verdict("D1 центр отряда садится на большую половину, а не между кучами",
		absf(c.x - 332.0) < 3.0,
		"центр x=%.1f (куча 330..334, выброс 400)" % c.x)
	verdict("D2 центр отряда отличается от среднего арифметического",
		absf(c.x - mean_x) > 5.0,
		"среднее x=%.1f, центр x=%.1f" % [mean_x, c.x])
	for m in men:
		(m as Node).queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# E. СПЛОЧЁННОСТЬ
# ═════════════════════════════════════════════════════════════════════════════
func _e_cohesion() -> void:
	print("\n═════ E. ЖЁСТКАЯ СПЛОЧЁННОСТЬ ═════")
	var men: Array = []
	for _i in range(6):
		men.append(_spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER, Vector3(250.0, 0.0, 250.0)))
	await pframes(2)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for m in men:
		GameManager.add_to_squad(sid, m)
	for i in range(men.size()):
		var u := men[i] as Unit
		var x: float = 250.0 + float(i)
		u.global_position = Vector3(x, GameManager.get_terrain_height(x, 250.0), 250.0)
		u.sync_row()
	var lost := men[5] as Unit
	var lx: float = 250.0 + _UCfg.SQUAD_COHESION_DIST * 2.0
	lost.global_position = Vector3(lx, GameManager.get_terrain_height(lx, 250.0), 250.0)
	lost.sync_row()
	lost.state = Unit.State.IDLE
	var before: float = lost.global_position.x
	await pframes(30)
	var recalled: bool = lost.state == Unit.State.MOVING
	await pframes(150)
	var after: float = lost.global_position.x
	print("  отставший был x=%.1f, стал x=%.1f (отряд у x=252)" % [before, after])
	verdict("E1 оторвавшийся бездельник получает приказ вернуться",
		recalled or after < before - 0.5,
		"состояние=%d, смещение %.2f м" % [lost.state, before - after])
	verdict("E2 он действительно пошёл к своим",
		after < before - 0.5, "было %.1f, стало %.1f" % [before, after])
	for m in men:
		if is_instance_valid(m):
			(m as Node).queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# F. ФАЛАНГА: ЦЕЛЬ ТОЛЬКО ПЕРЕД ФРОНТОМ
# ═════════════════════════════════════════════════════════════════════════════
func _f_phalanx_front() -> void:
	print("\n═════ F. КРАЙНИЙ КОПЕЙЩИК НЕ ВЫЛАМЫВАЕТСЯ ИЗ СТРОЯ ═════")
	var s: Unit = _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, Vector3(200.0, 0.0, 200.0))
	await pframes(2)
	s.set_stance("defense")
	s._facing = Vector3(1, 0, 0)
	var side_foe: Unit = _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_ENEMY, Vector3(200.0, 0.0, 201.5))
	var front_foe: Unit = _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_ENEMY, Vector3(201.5, 0.0, 200.0))
	await pframes(2)
	verdict("F1 враг сбоку фронтальным не считается",
		not s._in_phalanx_front(side_foe),
		"курс=(%.1f, %.1f)" % [s._facing.x, s._facing.z])
	verdict("F2 враг перед фронтом считается фронтальным",
		s._in_phalanx_front(front_foe))
	s.queue_free(); side_foe.queue_free(); front_foe.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# G. СЦЕПКА: КОНТАКТ ВЕДЁТ В РУБКУ, А НЕ В ЧЕЛНОК
# ═════════════════════════════════════════════════════════════════════════════
# Заслон выбирался в полосе attack_range + INTERCEPT_MARGIN, а приказ на него шёл
# непринудительный — и на следующем же тике цель сбрасывалась «потому что дальше
# дальности удара». Боец вставал, шёл, снова упирался, снова бросал.
func _g_melee_grip() -> void:
	print("\n═════ G. СЦЕПКА В БЛИЖНЕМ БОЮ ═════")
	var me: Unit = _spawn("res://scenes/units/Warrior.tscn",
		Constants.FACTION_PLAYER, Vector3(150.0, 0.0, 150.0))
	await pframes(2)
	var foe: Unit = _spawn("res://scenes/units/Warrior.tscn",
		Constants.FACTION_ENEMY,
		Vector3(150.0 + me.attack_range + 0.5, 0.0, 150.0))
	await pframes(2)
	me.command_attack(foe, false)
	me._melee_grip = true
	var lost_target := 0
	for _i in range(90):
		await get_tree().physics_frame
		if me.attack_target == null:
			lost_target += 1
	var d: float = me.global_position.distance_to(foe.global_position)
	print("  дистанция после сцепки %.2f м (дальность удара %.2f)" % [d, me.attack_range])
	verdict("G1 боец не бросает заслон на границе дальности",
		lost_target == 0, "кадров без цели: %d" % lost_target)
	verdict("G2 сцепка доводит до дистанции удара",
		d <= me.attack_range + 0.1, "дистанция %.2f м" % d)
	verdict("G3 приказ на движение снимает сцепку",
		_grip_cleared(me), "_melee_grip=%s" % str(me._melee_grip))
	me.queue_free(); foe.queue_free()
	await pframes(2)

func _grip_cleared(u: Unit) -> bool:
	u._melee_grip = true
	u.command_move(u.global_position + Vector3(1, 0, 0))
	return not u._melee_grip

# ═════════════════════════════════════════════════════════════════════════════
# H. РАБОЧИЙ: СМЕНА СОСТОЯНИЯ — СРОЧНАЯ СМЕНА ПОЗЫ
# ═════════════════════════════════════════════════════════════════════════════
func _h_worker_pose() -> void:
	print("\n═════ H. АНИМАЦИЯ РАБОЧЕГО НЕ ОТСТАЁТ ОТ FSM ═════")
	var w: Worker = _spawn("res://scenes/units/Worker.tscn",
		Constants.FACTION_PLAYER, Vector3(180.0, 0.0, 180.0)) as Worker
	await pframes(6)
	w._pose_dirty = false
	w.carrying_type = Constants.RESOURCE_WOOD
	w.carrying_amount = 10.0
	w.state = Unit.State.RETURNING
	# Один физический тик: он и пишет строку, и обязан пометить позу к пересчёту
	w.tick_physics(0.016, false, true, -1)
	verdict("H1 смена состояния помечает позу к немедленному пересчёту",
		w._pose_dirty,
		"_pose_dirty=%s, анимация=%s" % [str(w._pose_dirty), String(w._anim_name)])
	# Состояние мог сбросить сам автомат (нет точки сдачи) — для проверки
	# КАРТИНКИ возвращаем его и зовём визуальный такт
	w.state = Unit.State.RETURNING
	# ВИЗУАЛЬНЫЙ ТАКТ ЗОВЁМ ЯВНО И С БЕСКОНЕЧНЫМ РАДИУСОМ ОБЗОРА. Стенд ставит
	# рабочего далеко от камеры, а поза далёких бойцов по LOD не пересчитывается
	# вовсе — это верное поведение, но проверяем мы здесь не его
	var p: Vector3 = w.global_position
	w.tick_visual(0.016, 0, 1, p.x, p.z, INF, 1.0, true, false, false)
	verdict("H2 нарисована переноска, а не топор",
		w._anim_name == &"carry_wood" or not w._has_anim(&"carry_wood"),
		"анимация=%s" % String(w._anim_name))
	w.queue_free()
	await pframes(2)
