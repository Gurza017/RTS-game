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
##   I КОНЕЦ ПАРТИИ — снесённая крепость без живых юнитов даёт победу, а не
##                  вечно недостроенный фундамент
##   J ЗАСЛОН ИИ  — отряды у базы стоят линией и НЕ налезают друг на друга
##   K ЛУЧНИКИ    — жёсткий потолок дальности; клик по врагу вплотную не гонит
##                  стрелка в рукопашную; за убегающим он не идёт
##   L ОБОРОНА    — залоченная стойка не двигается ни по какому приказу, но
##                  смыкание рядов ей разрешено
##   M ОТХОД      — решение об отходе держится и не отменяется чужим приказом
##   N ПОГОНЯ     — поводок общий на отряд, а не личный у каждого бойца
##   O ЗНАМЯ      — падает только от ГИБЕЛИ отряда, а не от перевода бойцов
##                  (иначе за ордой тянется след «синих флажков»)
##
## Каждая проверка утверждает СВОЙСТВО и берёт числа из конфига, а не из себя.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _AICfgB := preload("res://scripts/ai_start_army_limit.gd")

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
	await _k_archers()
	await _l_defense_lock()
	await _m_retreat_lock()
	_n_pursuit_anchor()
	await _o_banner_trail()
	await _i_game_over()
	_j_ai_screen()

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

# ═════════════════════════════════════════════════════════════════════════════
# I. КОНЕЦ ПАРТИИ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца: последняя крепость ИИ снесена, живых у него не осталось —
## а крепость «уходит в режим повторной постройки», и игра не кончается.
##
## Причин было две, и обе проверяются здесь:
##   • ИИ закладывал новую крепость, проверяя только деньги. Фундамент попадал
##     в группу зданий фракции, достроить его без единого рабочего было
##     некому — и условие «у врага не осталось зданий» не выполнялось никогда;
##   • само условие требовало ПОЛНОГО отсутствия зданий, то есть висело, пока
##     игрок не обойдёт карту и не снесёт последний домик.
func _i_game_over() -> void:
	print("\n═════ I. КОНЕЦ ПАРТИИ ═════")
	# ── I1: без единого живого юнита ИИ не закладывает крепость ────────────
	var ai = main.get("enemy_ai")
	if ai != null and ai.has_method("_has_living_units"):
		var alive_before: bool = bool(ai.call("_has_living_units"))
		for n in get_tree().get_nodes_in_group("enemy_units"):
			if is_instance_valid(n) and n is Unit:
				(n as Unit).take_damage((n as Unit).max_health * 10.0 + 1000.0, null)
		await pframes(4)
		var alive_after: bool = bool(ai.call("_has_living_units"))
		verdict("I1 ИИ видит, что живых у него не осталось",
			alive_before and not alive_after,
			"было живых=%s, стало=%s" % [str(alive_before), str(alive_after)])
	else:
		verdict("I1 ИИ видит, что живых у него не осталось", false,
			"нет доступа к EnemyAI")

	# ── I2: победа объявляется по СНЕСЁННОЙ КРЕПОСТИ, а не по пустой карте ──
	# Сносим замок ИИ, оставляя прочие его постройки на месте: прежнее условие
	# на таком поле не сработало бы вовсе
	var killed := 0
	var left_others := 0
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if not is_instance_valid(b) or not (b is Building):
			continue
		if b is Castle:
			(b as Building).take_damage((b as Building).max_health * 10.0 + 1000.0)
			killed += 1
		else:
			left_others += 1
	await pframes(6)
	var beaten: bool = bool(main.call("_faction_beaten", "enemy_units",
		"enemy_buildings"))
	print("  снесено крепостей %d, прочих построек осталось %d" % [killed, left_others])
	verdict("I2 нет живых и нет крепости — фракция разбита", beaten,
		"разбита=%s (прочих построек %d)" % [str(beaten), left_others])

# ═════════════════════════════════════════════════════════════════════════════
# J. ЗАСЛОН ИИ У БАЗЫ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца: гарнизон ИИ «собирается в единую плотную кучу в центре,
## расталкивается, разлетается импульсом и снова пытается собраться».
##
## Причина была арифметическая: ширина заслона стояла числом (18 м) и делилась
## на число отрядов, а отряд из шестидесяти человек занимает около трёх метров
## в ширину — семь отрядов получали центры в 2.6 м друг от друга и физически не
## могли не перекрыться. Проверяем СВОЙСТВО: шаг между соседними местами
## заслона не меньше ширины самого отряда
func _j_ai_screen() -> void:
	print("\n═════ J. ЗАСЛОН ИИ У БАЗЫ ═════")
	var ai = main.get("enemy_ai")
	if ai == null or not ai.has_method("_screen_step"):
		verdict("J1 шаг заслона не меньше ширины отряда", false, "нет доступа к EnemyAI")
		return
	var step: float = float(ai.call("_screen_step"))
	# Ширина отряда считается ТЕМ ЖЕ построением, каким ИИ его и разворачивает
	var squad_w: float = float(ai.get("SQUAD_COLS")) * float(ai.get("SQUAD_SPACING"))
	print("  шаг между отрядами %.2f м при ширине отряда %.2f м" % [step, squad_w])
	verdict("J1 шаг заслона не меньше ширины отряда", step >= squad_w,
		"шаг %.2f м, отряд %.2f м" % [step, squad_w])
	# И линия не бесконечна: лишние отряды уходят во второй эшелон
	var per_row: int = int(ai.call("_screen_per_row"))
	print("  в одну линию помещается отрядов: %d" % per_row)
	verdict("J2 линия заслона имеет предел, за ним — второй эшелон",
		per_row >= 1 and float(per_row) * step <= _AICfgB.SCREEN_MAX_WIDTH + step,
		"в линии %d отрядов по %.2f м при потолке %.1f м"
			% [per_row, step, _AICfgB.SCREEN_MAX_WIDTH])

# ═════════════════════════════════════════════════════════════════════════════
# K. ЛУЧНИКИ: ДАЛЬНОСТЬ И ЦЕЛИ
# ═════════════════════════════════════════════════════════════════════════════
func _k_archers() -> void:
	print("\n═════ K. ЛУЧНИКИ ═════")
	# ── K1: ЖЁСТКИЙ ПОТОЛОК ДАЛЬНОСТИ ──────────────────────────────────────
	# Жалоба: «случайные сверхдальние выстрелы через всю карту». Дальность
	# растёт от кузницы и вписывается прямо в поле бойца — потолка не было
	var cap: float = _UCfg.stat("archer", "attack_range_cap", 0.0)
	var base_r: float = _UCfg.stat("archer", "attack_range", 0.0)
	verdict("K1 у лучника есть потолок дальности и он выше базовой",
		cap > 0.0 and cap >= base_r,
		"потолок %.1f м при базовой %.1f м" % [cap, base_r])
	var a := _spawn("res://scenes/units/Archer.tscn", Constants.FACTION_PLAYER,
		Vector3(-820.0, 0.0, -820.0))
	await pframes(3)
	# Выдаём заведомо непомерную прибавку — потолок обязан её срезать
	var before: float = a.attack_range
	a.attack_range = a.clamp_attack_range(a.attack_range + 500.0)
	verdict("K2 потолок срезает любую прибавку кузницы",
		absf(a.attack_range - cap) < 0.01,
		"было %.1f, после +500 стало %.1f при потолке %.1f"
			% [before, a.attack_range, cap])

	# ── K3: КЛИК ПО ВРАГУ ВПЛОТНУЮ НЕ ГОНИТ СТРЕЛКА В РУКОПАШНУЮ ───────────
	# Чужой отряд: один боец рядом со стрелком, второй далеко. Приказ отдаётся
	# по ДАЛЬНЕМУ — ровно так и делает squad_pick_member («наименее
	# обстрелянный»), и стрелок раньше шёл к нему сквозь ближнего
	var esid: int = GameManager.new_squad(Constants.FACTION_ENEMY, "spearman")
	var near_foe := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_ENEMY, Vector3(-820.0, 0.0, -815.0))
	var far_foe := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_ENEMY, Vector3(-820.0, 0.0, -780.0))
	GameManager.add_to_squad(esid, near_foe)
	GameManager.add_to_squad(esid, far_foe)
	await pframes(4)
	var start: Vector3 = a.global_position
	a.command_attack(far_foe, true, true, true)
	verdict("K3 стрелок взял того, до кого достаёт, а не дальнего",
		a.attack_target == near_foe,
		"цель = %s" % ("ближний" if a.attack_target == near_foe else "дальний"))
	await pframes(120)
	var walked: float = Vector2(a.global_position.x - start.x,
		a.global_position.z - start.z).length()
	verdict("K4 и никуда не побежал", walked < 1.0,
		"прошёл %.2f м" % walked)

	# ── K5: ЗА УБЕГАЮЩИМ НЕ ИДЁТ ──────────────────────────────────────────
	verdict("K5 стрелок не преследует по определению", not a.pursues_target())
	for u in [a, near_foe, far_foe]:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# L. ОБОРОНА: СТРОЕМ ХОДИТ, ПООДИНОЧКЕ — НЕТ
# ═════════════════════════════════════════════════════════════════════════════
## ТРЕБОВАНИЕ РАЗВЕРНУЛОСЬ ВТОРОЙ РАЗ, и оба разворота стоит помнить.
##
## Жалоба одна и та же: «в обороне крайние копейщики выбегают из строя на
## отдельных врагов». Первым решением был ГЛУХОЙ ЗАМОК позиции — не двигаться
## вообще. Он закрыл жалобу и создал другую: фаланга перестала ходить строем по
## приказу игрока, а это её штатная работа.
##
## Настоящая причина выбега оказалась не в разрешении двигаться, а в ТОЧКЕ:
## приказ атаки давал КАЖДОМУ бойцу одну и ту же цель — координату врага, и
## строй честно сходился в неё, то есть схлопывался. Первыми это видно на
## флангах, им идти дальше всех.
##
## Поэтому проверяем ДВЕ ВЕЩИ ПОРОЗНЬ:
##   • по приказу отряд идёт и СОХРАНЯЕТ СТРОЙ (L1/L2);
##   • сам, по собственной инициативе, боец не делает к врагу ни шагу (L3).
func _l_defense_lock() -> void:
	print("\n═════ L. ОБОРОНА: СТРОЙ ХОДИТ, ОДИНОЧКА — НЕТ ═════")
	var locked_cfg: bool = bool(_UCfg.get_stance(_UCfg.STANCE_DEFENSE)
		.get("lock_position", false))
	verdict("L0 глухой замок позиции снят (фаланга обязана ходить строем)",
		not locked_cfg, "lock_position = %s" % str(locked_cfg))

	# ── СТРОЙ ИДЁТ ПО ПРИКАЗУ И ОСТАЁТСЯ СТРОЕМ ───────────────────────────
	var base := Vector3(-880.0, 0.0, -880.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(8):
		var u := _spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER, base + Vector3(float(i) * 0.9 - 3.2, 0.0, 0.0))
		GameManager.add_to_squad(sid, u)
		u.set_stance(_UCfg.STANCE_DEFENSE)
		men.append(u)
	# Враг далеко впереди — по нему и отдаётся приказ
	var foe := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_ENEMY,
		base + Vector3(0.0, 0.0, -14.0))
	foe.set_tick(false)
	await pframes(6)
	var span0: float = _line_span(men)
	var mid0: float = _line_mid_z(men)
	for u in men:
		(u as Unit).command_attack(foe, true, true, true)
	for _i in range(300):
		await get_tree().physics_frame
	var span1: float = _line_span(men)
	var mid1: float = _line_mid_z(men)
	print("  ширина строя %.2f → %.2f м, центр по глубине %.2f → %.2f"
		% [span0, span1, mid0, mid1])
	verdict("L1 стена по приказу пошла вперёд", absf(mid1 - mid0) > 1.0,
		"центр сдвинулся на %.2f м" % absf(mid1 - mid0))
	# ШИРИНА — ЭТО И ЕСТЬ «СТРОЙ ОСТАЛСЯ СТРОЕМ». Схлопывание в точку врага
	# сжало бы её в разы (ровно это и было видно как «фланги выбегают»)
	verdict("L2 и осталась строем, а не схлопнулась в точку",
		span1 > span0 * 0.7,
		"ширина %.2f → %.2f м" % [span0, span1])
	for u in men:
		if is_instance_valid(u):
			(u as Node).queue_free()
	if is_instance_valid(foe):
		(foe as Node).queue_free()
	await pframes(4)

	# ── ОДИНОЧКА САМ К ВРАГУ НЕ ИДЁТ ──────────────────────────────────────
	# Ни приказа, ни отряда — только замеченный поблизости противник. Раньше
	# авто-агро выдавало цель, и боец шёл к ней: так фланговые и «выбегали»
	var solo := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, Vector3(-920.0, 0.0, -920.0))
	solo.set_stance(_UCfg.STANCE_DEFENSE)
	var bait := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_ENEMY, Vector3(-920.0, 0.0, -912.0))
	bait.set_tick(false)
	await pframes(6)
	var at: Vector3 = solo.global_position
	for _i in range(300):
		await get_tree().physics_frame
	var crept: float = Vector2(solo.global_position.x - at.x,
		solo.global_position.z - at.z).length()
	verdict("L3 по своей инициативе боец обороны к врагу не идёт",
		crept < 0.5, "прошёл %.2f м к врагу в восьми метрах" % crept)
	for u in [solo, bait]:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await pframes(3)

## Ширина строя по оси X — по ней и видно, схлопнулся ли он
func _line_span(men: Array) -> float:
	var lo := INF
	var hi := -INF
	for m in men:
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		lo = minf(lo, u.global_position.x)
		hi = maxf(hi, u.global_position.x)
	return 0.0 if lo == INF else hi - lo

## Средняя глубина строя по оси Z
func _line_mid_z(men: Array) -> float:
	var sum := 0.0
	var n := 0
	for m in men:
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		sum += u.global_position.z
		n += 1
	return 0.0 if n == 0 else sum / float(n)

# ═════════════════════════════════════════════════════════════════════════════
# M. ОТХОД НЕ ОТМЕНЯЕТСЯ ЧУЖИМ ПРИКАЗОМ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба: отряд ИИ начинает убегать, разворачивается назад и умирает от стрел
## в спину. До бойца доходят приказы не только от ИИ (смыкание рядов,
## сплочённость, возврат на пост), и любой из них звал command_move без
## keep_retreat — то есть гасил отход
func _m_retreat_lock() -> void:
	print("\n═════ M. ЗАМОК ОТХОДА ═════")
	var u := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_ENEMY,
		Vector3(-940.0, 0.0, -940.0))
	await pframes(3)
	u.begin_retreat()
	verdict("M1 отход взведён и защищён замком времени",
		u.retreating and u.retreat_locked(),
		"отход=%s замок=%s" % [str(u.retreating), str(u.retreat_locked())])
	# Обычный приказ на движение — тот самый путь, которым отход и гасился
	u.command_move(u.global_position + Vector3(0.0, 0.0, 5.0))
	verdict("M2 обычный приказ движения отход НЕ отменяет", u.retreating,
		"отход=%s" % str(u.retreating))
	# А прибытие в замок — отменяет: там отход кончился по факту
	u.end_retreat(true)
	verdict("M3 прибытие в замок отменяет отход принудительно", not u.retreating)
	verdict("M4 срок замка совпадает у бойца и у ИИ",
		absf(Unit.RETREAT_LOCK_SEC - _AICfgB.RETREAT_MIN_SEC) < 0.01,
		"боец %.1f c, ИИ %.1f c" % [Unit.RETREAT_LOCK_SEC,
			_AICfgB.RETREAT_MIN_SEC])
	if is_instance_valid(u):
		(u as Node).queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# N. ПОВОДОК ПОГОНИ — ОБЩИЙ НА ОТРЯД
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба: «задние бойцы отстают, теряют цель и возвращаются в строй, а передние
## продолжают бежать; отряд растягивается на полкарты». Личный якорь и давал два
## противоположных решения внутри одного отряда
func _n_pursuit_anchor() -> void:
	print("\n═════ N. ЯКОРЬ ПОГОНИ ═════")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	verdict("N1 у свежего отряда якоря погони нет",
		GameManager.squad_pursuit_anchor(sid) == Vector3.INF)
	var at := Vector3(-1000.0, 0.0, -1000.0)
	GameManager.squad_pursuit_anchor_set(sid, at)
	verdict("N2 первое касание ставит якорь ОТРЯДУ",
		GameManager.squad_pursuit_anchor(sid) == at,
		"якорь %s" % str(GameManager.squad_pursuit_anchor(sid)))
	# Второй боец касается позже и дальше — якорь обязан остаться ПЕРВЫМ,
	# иначе поводок «едет» вместе с передними и не кончается никогда
	GameManager.squad_pursuit_anchor_set(sid, at + Vector3(0.0, 0.0, 30.0))
	verdict("N3 второе касание якорь не переставляет",
		GameManager.squad_pursuit_anchor(sid) == at,
		"якорь %s" % str(GameManager.squad_pursuit_anchor(sid)))
	GameManager.squad_pursuit_release(sid)
	verdict("N4 конец погони снимает якорь всему отряду",
		GameManager.squad_pursuit_anchor(sid) == Vector3.INF)

# ═════════════════════════════════════════════════════════════════════════════
# O. ЗНАМЯ ПАДАЕТ ТОЛЬКО ОТ ГИБЕЛИ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца: «при перемещении отрядов орков по их траектории остаются
## синие флажки».
##
## Разбор. Отряд пустеет ДВУМЯ путями, и в коде они выглядели одинаково:
## последнего бойца УБИЛИ — или его ПЕРЕВЕЛИ в другой отряд (add_to_squad
## первым делом зовёт remove_from_squad). ИИ и орда перекладывают бойцов по
## отрядам каждый такт размышления, и на каждом перекладывании на землю падало
## знамя — тянущийся за ордой след из знамён её же живых отрядов. Синих потому,
## что синий — это грейды 4-6.
func _o_banner_trail() -> void:
	print("\n═════ O. СЛЕД ИЗ ЗНАМЁН ═════")
	GameManager.corpses.clear()
	await pframes(2)
	var sid_a: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_spearman")
	var sid_b: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_spearman")
	var u := _spawn("res://scenes/units/GoblinSpearman.tscn",
		Constants.FACTION_GOBLIN, Vector3(-1780.0, 0.0, -1780.0))
	GameManager.add_to_squad(sid_a, u)
	# Отряду выдаём звание: без него знамени нет вовсе и ронять нечего
	(GameManager.squads[sid_a] as Dictionary)["level"] = 5
	GameManager.refresh_squad_banner(sid_a)
	await pframes(4)
	var before: int = GameManager.corpses.count()

	# ── ПЕРЕВОД ПОСЛЕДНЕГО БОЙЦА В ДРУГОЙ ОТРЯД ──────────────────────────
	# Отряд A пустеет и расформировывается, но НИКТО не погиб
	GameManager.add_to_squad(sid_b, u)
	await pframes(6)
	verdict("O1 перевод бойца расформировал прежний отряд",
		not GameManager.squads.has(sid_a))
	verdict("O2 но знамени на землю не уронил",
		GameManager.corpses.count() == before,
		"тел на поле было %d, стало %d" % [before, GameManager.corpses.count()])

	# ── А ГИБЕЛЬ — РОНЯЕТ ─────────────────────────────────────────────────
	(GameManager.squads[sid_b] as Dictionary)["level"] = 5
	GameManager.refresh_squad_banner(sid_b)
	await pframes(4)
	var before2: int = GameManager.corpses.count()
	u.take_damage(u.max_health * 10.0 + 1000.0, null)
	await pframes(8)
	var got: int = GameManager.corpses.count() - before2
	verdict("O3 гибель последнего роняет знамя (тело + знамя)", got == 2,
		"прибавилось %d, ждали 2" % got)
	GameManager.corpses.clear()
	await pframes(2)
