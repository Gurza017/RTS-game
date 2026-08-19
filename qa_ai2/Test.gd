extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТАКТИЧЕСКИЙ И ЭКОНОМИЧЕСКИЙ ИИ
## ═══════════════════════════════════════════════════════════════════════════
##   A КУЗНИЦА   — ИИ покупает узлы ДРЕВА, а не только плоские слоты
##   B ФАЛАНГА   — ровные шеренги и опущенные копья на марше
##   C ФЛАНГ     — мечники обходят строй и идут к стрелкам
##   D КАЙТ      — лучники прячутся за спины своей пехоты
##   E ОТХОД     — выбитый отряд уходит в замок на восстановление
##   F ЗАСЛОН    — гарнизон стоит строем лицом к противнику, а не кольцом
##   G ЦЕНА      — такт размышления укладывается в бюджет
##
## Числа берутся из ai_start_army_limit / unit_stats_config / forge_config —
## стенд проверяет СВОЙСТВА поведения, а не конкретные значения баланса

const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _FCfg  := preload("res://scripts/forge_config.gd")

var main = null
var ai = null
var castle: Castle = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

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

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"archer":  u = Archer.new()
		"warrior": u = Warrior.new()
		_:         u = Spearman.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return u

## Отряд ИИ: настоящий отряд GameManager (нужен для гарнизона) плюс запись в ai
func _ai_squad(kind: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_ENEMY, kind)
	var out: Array = []
	for i in range(n):
		var u := _spawn(kind, Constants.FACTION_ENEMY,
			at + Vector3(float(i % 5) * 0.7, 0.0, float(i / 5) * 0.7))
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _clear_ai() -> void:
	for s in ai.squads:
		for m in (s as Dictionary)["members"]:
			if is_instance_valid(m):
				(m as Node).queue_free()
	ai.squads = []

func _kill(arr: Array) -> void:
	for u in arr:
		if is_instance_valid(u):
			(u as Node).queue_free()

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	ai = main.enemy_ai
	if ai == null:
		print("НЕТ enemy_ai — стенд бессмыслен")
		get_tree().quit(1)
		return
	# ИИ думает ТОЛЬКО когда его позовёт стенд: иначе он переиздаёт приказы
	# посреди замера и результат зависит от того, куда попал таймер
	ai.set_process(false)
	ai._peace_over = true
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	castle = ai._find_castle()
	await frames(3)

	await _a_forge()
	await _b_phalanx()
	await _c_flank()
	await _d_kite()
	await _e_retreat()
	await _f_screen()
	await _g_cost()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 66), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== AI2 TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. КУЗНИЦА
# ═════════════════════════════════════════════════════════════════════════════
func _a_forge() -> void:
	print("\n═════ A. КУЗНИЦА ═════")
	var smithy := Smithy.new()
	smithy.faction = Constants.FACTION_ENEMY
	main.world_add(smithy)
	smithy.global_position = Vector3(80.0, 0.0, 40.0)
	await frames(4)

	# Денег вдоволь: проверяем ВЫБОР, а не экономику
	ResourceManager.add_resource(Constants.FACTION_ENEMY, Constants.RESOURCE_GOLD, 40000.0)
	ResourceManager.add_resource(Constants.FACTION_ENEMY, Constants.RESOURCE_WOOD, 40000.0)
	await frames(2)

	ai._research_forge(smithy)
	await frames(2)
	var started: String = smithy.research_id
	var queued: int = smithy.research_queue.size()
	var picked: bool = started != "" or queued > 0
	verdict("A1 ИИ начал исследование узла ДРЕВА", picked and _is_forge_id(started),
		"начато «%s», в очереди %d" % [started, queued])

	# Узел обязан быть из рода войск, который ИИ реально нанимает
	var trained := false
	for t in _AICfg.combat_types():
		if started.begins_with(String(t) + "_"):
			trained = true
	verdict("A2 качается род войск, который ИИ нанимает", trained,
		"узел «%s», типы найма %s" % [started, _AICfg.combat_types()])

	# Резерв золота: опустошаем банк — новых заказов быть не должно
	var before_q: int = smithy.research_queue.size()
	ResourceManager.spend(Constants.FACTION_ENEMY,
		{Constants.RESOURCE_GOLD: ResourceManager.get_amount(
			Constants.FACTION_ENEMY, Constants.RESOURCE_GOLD)})
	await frames(2)
	ai._research_forge(smithy)
	await frames(2)
	verdict("A3 при пустом банке ИИ науку не заказывает",
		smithy.research_queue.size() == before_q,
		"очередь была %d, стала %d, резерв %.0f" % [
			before_q, smithy.research_queue.size(), _AICfg.AI_RESEARCH_GOLD_RESERVE])

	smithy.queue_free()
	await frames(3)

func _is_forge_id(id: String) -> bool:
	if id.is_empty():
		return false
	return not _FCfg.get_node(id).is_empty()

# ═════════════════════════════════════════════════════════════════════════════
# B. ФАЛАНГА
# ═════════════════════════════════════════════════════════════════════════════
func _b_phalanx() -> void:
	print("\n═════ B. ФАЛАНГА ═════")
	var base := Vector3(60.0, 0.0, 30.0)
	var n: int = _UCfg.squad_size("spearman")
	var men := _ai_squad("spearman", base, n)
	await frames(3)
	ai._regroup()
	var sq: Dictionary = ai.squads[0]
	sq["role"] = ai.ROLE_ASSAULT
	sq["target"] = base + Vector3(-30.0, 0.0, 0.0)
	sq["issued"] = false
	ai._apply_orders()
	await frames(3)

	# Ряды обязаны быть РОВНЫМИ: длина каждой шеренги отличается не больше чем
	# на одного бойца, а глубина равна заданной
	var rows: Dictionary = {}
	for u in men:
		var r: int = (u as Unit).formation_row
		rows[r] = int(rows.get(r, 0)) + 1
	var depth: int = rows.size()
	var lo := 9999
	var hi := 0
	for k in rows:
		lo = mini(lo, int(rows[k]))
		hi = maxi(hi, int(rows[k]))
	verdict("B1 глубина строя равна заданному числу шеренг",
		depth == _AICfg.PHALANX_RANKS,
		"шеренг %d при PHALANX_RANKS=%d, состав %s" % [depth, _AICfg.PHALANX_RANKS, rows])
	verdict("B2 шеренги ровные (разница не больше бойца)", hi - lo <= 1,
		"самая длинная %d, самая короткая %d" % [hi, lo])

	# На марше без контакта — стойка ЗАЩИТА, то есть копья опущены
	var def_cnt := 0
	for u in men:
		if (u as Unit).stance == _UCfg.STANCE_DEFENSE:
			def_cnt += 1
	verdict("B3 на марше без контакта копейщики держат ЗАЩИТУ (копья опущены)",
		def_cnt == men.size(),
		"в защите %d из %d" % [def_cnt, men.size()])

	# Появился противник в радиусе контакта — стойка меняется на АТАКУ
	var foe := _spawn("warrior", Constants.FACTION_PLAYER,
		base + Vector3(_AICfg.CONTACT_RADIUS * 0.5, 0.0, 0.0))
	await frames(3)
	sq["issued"] = false
	ai._apply_orders()
	await frames(3)
	var atk_cnt := 0
	for u in men:
		if (u as Unit).stance == _UCfg.STANCE_ATTACK:
			atk_cnt += 1
	verdict("B4 при контакте копейщики переходят в АТАКУ", atk_cnt == men.size(),
		"в атаке %d из %d" % [atk_cnt, men.size()])

	foe.queue_free()
	_clear_ai()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ФЛАНГОВЫЙ ОБХОД МЕЧНИКОВ
# ═════════════════════════════════════════════════════════════════════════════
func _c_flank() -> void:
	print("\n═════ C. ФЛАНГ ═════")
	var base := Vector3(60.0, 0.0, 0.0)
	var goal := Vector3(0.0, 0.0, 0.0)
	var men := _ai_squad("warrior", base, 6)
	await frames(3)
	# Строй игрока: копейщики стеной у цели, лучники ЗА ними
	var wall: Array = []
	for i in range(8):
		wall.append(_spawn("spearman", Constants.FACTION_PLAYER,
			goal + Vector3(0.0, 0.0, float(i) * 0.8 - 3.0)))
	var bows: Array = []
	for i in range(4):
		bows.append(_spawn("archer", Constants.FACTION_PLAYER,
			goal + Vector3(-8.0, 0.0, float(i) * 0.8 - 1.5)))
	await frames(4)

	ai._regroup()
	var sq: Dictionary = ai.squads[0]
	sq["role"] = ai.ROLE_ASSAULT
	sq["target"] = goal
	sq["issued"] = false
	ai._apply_orders()
	await frames(3)

	verdict("C1 отряд мечников получил роль обхода", String(sq["role"]) == ai.ROLE_FLANK,
		"роль «%s»" % String(sq["role"]))

	# Цель обхода обязана лежать СБОКУ от стрелков, а не между ними и нами:
	# иначе это не обход, а тот же лобовой удар
	var tgt: Vector3 = sq["target"]
	var bow_pos: Vector3 = (bows[0] as Unit).global_position
	var course := (bow_pos - base); course.y = 0.0; course = course.normalized()
	var right := Vector3(-course.z, 0.0, course.x)
	var lateral: float = absf((tgt - bow_pos).dot(right))
	verdict("C2 точка обхода вынесена вбок от стрелков", lateral > _AICfg.FLANK_ARC_RADIUS * 0.6,
		"вбок %.1f м при радиусе обхода %.1f" % [lateral, _AICfg.FLANK_ARC_RADIUS])

	# Далеко — идут БЕГОМ: бегущий не перехватывается чужой линией
	var run_cnt := 0
	for u in men:
		if (u as Unit).sprinting:
			run_cnt += 1
	verdict("C3 на обход отряд идёт бегом", run_cnt == men.size(),
		"бегут %d из %d" % [run_cnt, men.size()])

	# Подводим отряд вплотную — обход завершается атакой стрелков
	for u in men:
		var uu := u as Unit
		uu.global_position = bow_pos + Vector3(0.0, 0.0, 6.0)
		uu.sync_row()
	await frames(3)
	sq["issued"] = false
	ai._apply_orders()
	await frames(3)
	var on_bow := 0
	for u in men:
		var t = (u as Unit).attack_target
		if t != null and is_instance_valid(t) and t in bows:
			on_bow += 1
	verdict("C4 вблизи отряд атакует именно стрелков", on_bow > 0,
		"по стрелкам бьют %d из %d, роль «%s»" % [on_bow, men.size(), String(sq["role"])])

	_kill(wall); _kill(bows)
	_clear_ai()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. КАЙТ ЛУЧНИКОВ
# ═════════════════════════════════════════════════════════════════════════════
func _d_kite() -> void:
	print("\n═════ D. КАЙТ ═════")
	var base := Vector3(40.0, 0.0, -40.0)
	var bows := _ai_squad("archer", base, 5)
	# Своя пехота — прикрытие, стоит между лучниками и противником
	var cover := _ai_squad("spearman", base + Vector3(-6.0, 0.0, 0.0), 6)
	await frames(4)
	ai._regroup()

	var sq: Dictionary = {}
	for s in ai.squads:
		if String((s as Dictionary)["type"]) == "archer":
			sq = s
	sq["role"] = ai.ROLE_LINE
	sq["target"] = base
	sq["issued"] = false

	# Без угрозы кайта нет
	ai._apply_orders()
	await frames(2)
	verdict("D1 без угрозы лучники роль кайта не получают",
		String(sq["role"]) != ai.ROLE_KITE, "роль «%s»" % String(sq["role"]))

	# Пехота игрока подошла вплотную
	var foe := _spawn("warrior", Constants.FACTION_PLAYER,
		base + Vector3(_AICfg.KITE_TRIGGER_DIST * 0.5, 0.0, 0.0))
	await frames(3)
	var before: Vector3 = ai._squad_centroid(bows)
	var d_before: float = before.distance_to(foe.global_position)
	sq["issued"] = false
	ai._apply_orders()
	await frames(2)
	verdict("D2 подошедшая пехота включает кайт", String(sq["role"]) == ai.ROLE_KITE,
		"роль «%s», угроза в %.1f м (порог %.1f)" % [
			String(sq["role"]), d_before, _AICfg.KITE_TRIGGER_DIST])

	var tgt: Vector3 = sq["target"]
	verdict("D3 отход направлен ОТ угрозы",
		tgt.distance_to(foe.global_position) > d_before,
		"было %.1f м, цель отхода в %.1f м" % [
			d_before, tgt.distance_to(foe.global_position)])

	# И именно ЗА спину своих: прикрытие оказывается между угрозой и целью отхода
	var cover_c: Vector3 = ai._squad_centroid(cover)
	verdict("D4 отход уводит за спину своей пехоты",
		tgt.distance_to(foe.global_position) > cover_c.distance_to(foe.global_position),
		"цель в %.1f м от угрозы, прикрытие в %.1f м" % [
			tgt.distance_to(foe.global_position), cover_c.distance_to(foe.global_position)])

	foe.queue_free()
	_clear_ai()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. ОТСТУПЛЕНИЕ В КРЕПОСТЬ
# ═════════════════════════════════════════════════════════════════════════════
func _e_retreat() -> void:
	print("\n═════ E. ОТХОД ═════")
	if castle == null:
		verdict("E0 у ИИ есть замок", false, "замок не найден")
		return
	var base: Vector3 = castle.global_position + Vector3(-25.0, 0.0, 0.0)
	# ОТРЯД ПОЛНЫЙ. Малочисленность сама по себе поводом к отходу быть не должна:
	# отряды ИИ собираются пополнением, барак выпускает бойцов шеренгами, и
	# «мало людей» — это нормальное состояние только что нанятого отряда, а не
	# признак разгрома. Поводом должен быть УРОН, что и проверяется ниже
	var full: int = _UCfg.squad_size("spearman")
	var men := _ai_squad("spearman", base, full)
	await frames(3)
	ai._regroup()
	var sq: Dictionary = ai.squads[0]
	sq["role"] = ai.ROLE_LINE
	sq["target"] = base
	sq["issued"] = false

	# Рядом уже стоит противник — и всё равно целый отряд никуда не уходит
	var foe := _spawn("warrior", Constants.FACTION_PLAYER,
		base + Vector3(_AICfg.RETREAT_THREAT_RADIUS * 0.5, 0.0, 0.0))
	await frames(3)
	ai._apply_orders()
	await frames(2)
	verdict("E1 целый отряд не отступает даже при противнике рядом",
		String(sq["role"]) != ai.ROLE_RETREAT and ai._squad_strength(sq) > 0.9,
		"роль «%s», боеспособность %.2f" % [String(sq["role"]), ai._squad_strength(sq)])

	# ── ТЕПЕРЬ КРИТИЧЕСКИЙ УРОН ──────────────────────────────────────────────
	# Выбиваем половину отряда и калечим остальных: боеспособность считается от
	# ПИКА отряда, поэтому потери и раны опускают её, а численность сама по себе
	# — нет
	var alive: Array = []
	for i in range(men.size()):
		var u := men[i] as Unit
		if i % 2 == 0:
			u._die()
		else:
			u.take_damage(u.max_health * 0.85, null)
			alive.append(u)
	await frames(3)
	ai._regroup()
	var strength: float = ai._squad_strength(sq)
	verdict("E2 урон и потери роняют боеспособность ниже порога",
		strength < _AICfg.RETREAT_STRENGTH,
		"%.2f при пороге %.2f (осталось %d из пика %d)" % [
			strength, _AICfg.RETREAT_STRENGTH, alive.size(), int(sq.get("peak", 0))])

	sq["issued"] = false
	ai._apply_orders()
	await frames(3)
	verdict("E3 под угрозой выбитый отряд уходит в замок",
		String(sq["role"]) == ai.ROLE_RETREAT, "роль «%s»" % String(sq["role"]))
	men = alive

	var retreating := 0
	for u in men:
		if (u as Unit).retreating:
			retreating += 1
	verdict("E4 бойцы переведены в режим отхода", retreating == men.size(),
		"в отходе %d из %d" % [retreating, men.size()])

	# И ИИ больше не шлёт им приказов: любой command_move снял бы режим отхода
	ai._apply_orders()
	await frames(3)
	var still := 0
	for u in men:
		if (u as Unit).retreating:
			still += 1
	verdict("E5 повторный такт не сбивает режим отхода", still == retreating,
		"было %d, стало %d" % [retreating, still])

	foe.queue_free()
	_clear_ai()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# F. ЗАСЛОН У БАЗЫ
# ═════════════════════════════════════════════════════════════════════════════
func _f_screen() -> void:
	print("\n═════ F. ЗАСЛОН ═════")
	if castle == null:
		verdict("F0 у ИИ есть замок", false, "замок не найден")
		return
	# Ориентир «где противник»: точка отсчёта для всей раскладки
	var mark := _spawn("spearman", Constants.FACTION_PLAYER, Vector3(-60.0, 0.0, -20.0))
	await frames(3)
	var course: Vector3 = ai._defense_course(castle)

	var spear_post: Vector3 = ai._screen_post(castle, "spearman", 0, 1)
	var bow_post: Vector3   = ai._screen_post(castle, "archer",   0, 1)
	var wr_post: Vector3    = ai._screen_post(castle, "warrior",  0, 1)
	var home: Vector3 = castle.global_position

	# Глубина по курсу «на противника»: копейщики дальше всех от замка
	var d_spear: float = (spear_post - home).dot(course)
	var d_bow: float   = (bow_post - home).dot(course)
	verdict("F1 копейщики стоят ПЕРЕД лучниками", d_spear > d_bow,
		"копейщики %.1f м по курсу, лучники %.1f м" % [d_spear, d_bow])

	var right := Vector3(-course.z, 0.0, course.x)
	verdict("F2 мечники вынесены на фланг", absf((wr_post - home).dot(right)) > 5.0,
		"вбок %.1f м" % absf((wr_post - home).dot(right)))

	# Всё построение смотрит НА противника, а не в тыл
	verdict("F3 заслон развёрнут в сторону противника", d_spear > 0.0 and d_bow > 0.0,
		"копейщики %.1f, лучники %.1f (по курсу на базу игрока)" % [d_spear, d_bow])

	mark.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# G. ЦЕНА ТАКТА
# ═════════════════════════════════════════════════════════════════════════════
# Тактика считается раз в THINK_INTERVAL и раз на ОТРЯД. Проверяем, что полный
# такт с реальной армией укладывается в бюджет кадра с большим запасом —
# он ведь и случается раз в две секунды
func _g_cost() -> void:
	print("\n═════ G. ЦЕНА ═════")
	var base: Vector3 = castle.global_position + Vector3(-20.0, 0.0, 0.0)
	var kinds := ["spearman", "archer", "warrior"]
	for i in range(9):
		_ai_squad(String(kinds[i % 3]), base + Vector3(float(i) * 4.0, 0.0, 0.0),
			_UCfg.squad_size(String(kinds[i % 3])))
	# И противник, чтобы тактические ветки реально отрабатывали
	for i in range(30):
		_spawn("spearman", Constants.FACTION_PLAYER,
			base + Vector3(-30.0 + float(i % 6), 0.0, float(i / 6)))
	await frames(5)
	ai._regroup()

	var best := INF
	for _r in range(5):
		for s in ai.squads:
			(s as Dictionary)["issued"] = false
		var t0: int = Time.get_ticks_usec()
		ai.tick()
		var dt: float = float(Time.get_ticks_usec() - t0) / 1000.0
		best = minf(best, dt)
		await frames(2)
	verdict("G1 такт ИИ дешевле кадра (16.6 мс)", best < 16.6,
		"%.2f мс на %d отрядов / %d бойцов" % [best, ai.squads.size(), ai.army_size()])
	print("  (справочно) %s" % ai.report())
