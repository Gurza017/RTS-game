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
##   H ЗАМОРОЗКА — стоящий заслон не переиздаёт приказ («пульсирующая армия»)
##   I ЦЕНТР     — полная армия выходит отвоёвывать центр карты
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
	await _h_frozen()
	await _i_recap()
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
# H. ЗАМОРОЖЕННАЯ ЦЕЛЬ: СТОЯЩИЙ ЗАСЛОН НЕ ПЕРЕИЗДАЁТ ПРИКАЗ
# ═════════════════════════════════════════════════════════════════════════════
# Жалоба владельца: армия ИИ у базы «сжимается в точку и разъезжается обратно»
# раз в секунду, просаживая кадр. Причин было две, и обе проверяются здесь.
#
#   H1. ШИРИНА МЕСТА. Шаг между соседними отрядами заслона выводился из ОБЩЕЙ
#       шестёрки колонок, а копейщиков ИИ разворачивает по числу шеренг — 15
#       колонок, 8.7 м. Места перекрывались, отряды лезли друг в друга,
#       расталкивание их разбрасывало. Проверяем СВОЙСТВО: шаг не меньше
#       ширины отряда ЭТОГО рода войск.
#
#   H2-H3. ЗАМОРОЗКА. Стоящему на своих местах заслону приказ переиздавался
#       каждый такт — а это set_stance и command_move каждому бойцу, то есть
#       вся оборона разом делала шаг. Проверяем, что второй такт подряд НЕ
#       трогает никого: ни один боец не ушёл из IDLE и никто не сдвинулся.
func _h_frozen() -> void:
	print("\n═════ H. ЗАМОРОЗКА СЕТКИ ═════")
	if castle == null:
		verdict("H0 у ИИ есть замок", false, "замок не найден")
		return
	_clear_ai()
	await frames(2)

	# H1: шаг заслона не уже отряда — у КАЖДОГО рода войск по отдельности
	var narrow: Array = []
	for t in _AICfg.combat_types():
		var uid: String = String(t)
		var w: float = float(ai._squad_width(uid))
		var step: float = float(ai._screen_step_for(uid))
		print("  %-9s ширина отряда %.2f м, шаг заслона %.2f м" % [uid, w, step])
		if step < w:
			narrow.append(uid)
	verdict("H1 шаг заслона не уже отряда ни у одного рода войск",
		narrow.is_empty(), "уже нормы: %s" % str(narrow))

	# H2-H3: два такта подряд по одной и той же обстановке
	var base: Vector3 = castle.global_position \
		+ ai._defense_course(castle) * _AICfg.SCREEN_SPEAR_DIST
	var men := _ai_squad("spearman", base, _UCfg.squad_size("spearman"))
	await frames(3)
	ai._regroup()
	# Первый такт: приказ выдаётся и отряд расходится по местам
	ai._assign_home_posts(castle, ai.squads)
	ai._apply_orders()
	# ── ЖДЁМ, ПОКА ВСЕ ВСТАНУТ, И ЖДЁМ ДОЛГО ────────────────────────────────
	# Заморозка судит СТОЯЩИЙ отряд, и «стоящий» здесь не фигура речи:
	# _posts_intact на идущем отряде отвечает «не трогать» (он и так исполняет
	# прошлый приказ), то есть на неустоявшемся строю проверка проверяла бы не
	# то. Шестидесяти копейщикам, которых высадили кучей и развели в строй
	# 15×4 в двадцати метрах в стороне, на это нужно около 1200 физкадров —
	# первая версия ждала 600 и мерила отряд НА ХОДУ
	var walking := 0
	var waited := 0
	for _i in range(1200):
		walking = 0
		for u in men:
			if is_instance_valid(u) and (u as Unit).state != Unit.State.IDLE:
				walking += 1
		if walking == 0:
			break
		waited += 1
		await frames(1)
	var states: Dictionary = {}
	for u in men:
		var st: int = (u as Unit).state
		states[st] = int(states.get(st, 0)) + 1
	print("  ожидание остановки: %d кадров, ещё в движении %d, состояния %s" % [
		waited, walking, str(states)])

	var before: Array = []
	for u in men:
		before.append((u as Node3D).global_position)
	var sqd: Dictionary = ai.squads[0]
	var issued_before: bool = bool(sqd["issued"])
	# Диагностика: ровно те три числа, по которым заморозка и принимает решение
	var f_face: Vector3 = sqd.get("face", Vector3.ZERO)
	var f_cols: int = int(ai._squad_cols("spearman", (sqd["members"] as Array).size()))
	var f_intact: bool = bool(ai._posts_intact(sqd["members"], sqd["target"],
		f_face, f_cols))
	var f_threat = ai._nearest_player_target(ai._squad_centroid(sqd["members"]),
		_AICfg.DEFENSE_ENGAGE_RADIUS)
	print("  зонд заморозки: роль=%s issued=%s курс=(%.2f,%.2f) колонок=%d стоят_по_местам=%s угроза=%s" % [
		String(sqd["role"]), str(issued_before), f_face.x, f_face.z, f_cols,
		str(f_intact), "нет" if f_threat == null else String((f_threat as Node).name)])

	# ── СЧИТАЕМ РАЗБУЖЕННЫХ ЭТИМ ВЫЗОВОМ, А НЕ ВСЕХ ИДУЩИХ ─────────────────
	# Здесь стояло «после двух кадров посчитать, кто не в покое», и проверка
	# ловила НЕ ТО, что утверждает. Идти боец может не только по приказу ИИ:
	# за эти кадры проходит обход смыкания строя (GameManager._sweep_reform), и
	# он законно уводит на места тех, кого оттёрло расталкиванием — замер дал
	# «разбужено 3 из 60», и все трое были от смыкания.
	# Утверждение же здесь ровно одно: ТАКТ ИИ стоящий заслон не трогает.
	# Значит, и мерить надо разницу ДО и ПОСЛЕ вызова, а сам вызов синхронен
	# (command_move ставит State.MOVING тут же)
	var was_idle: Array = []
	for i0 in range(men.size()):
		var u0 := men[i0] as Unit
		was_idle.append(is_instance_valid(u0) and u0.state == Unit.State.IDLE)

	# Второй такт по НЕИЗМЕННОЙ обстановке — обязан не сделать ничего
	ai._assign_home_posts(castle, ai.squads)
	ai._apply_orders()

	var woken := 0
	for i1 in range(men.size()):
		var u1 := men[i1] as Unit
		if not bool(was_idle[i1]) or not is_instance_valid(u1):
			continue
		if u1.state != Unit.State.IDLE:
			woken += 1
	await frames(2)

	var shifted := 0.0
	for i in range(men.size()):
		var u := men[i] as Unit
		if not is_instance_valid(u):
			continue
		shifted = maxf(shifted, (u.global_position as Vector3).distance_to(before[i]))
	print("  после повторного такта: разбужено %d из %d, худший сдвиг %.2f м" % [
		woken, men.size(), shifted])
	verdict("H2 повторный такт не будит стоящий заслон", woken == 0,
		"разбужено %d из %d (приказ был выдан=%s)" % [woken, men.size(), str(issued_before)])
	verdict("H3 повторный такт не двигает строй", shifted < 0.5,
		"худший сдвиг %.2f м" % shifted)
	_clear_ai()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# I. ОТВОЕВАТЬ ЦЕНТР
# ═════════════════════════════════════════════════════════════════════════════
# Жалоба владельца: игрок берёт центр карты, ИИ садится в глухую оборону у базы
# и не выходит из неё, даже восстановив армию до лимита.
#
# Проверяем ТРИ свойства решения, а не числа из конфига:
#   I1 — при полной армии и занятом игроком центре ИИ переходит в наступление;
#   I2 — дома остаётся ровно RECAP_HOME_GUARD отрядов на род, остальные идут
#        на ЦЕНТР («не оставлять лишних юнитов в бесконечной обороне»);
#   I3 — гистерезис: отвоёванный центр возвращает ИИ в оборону сам.
func _i_recap() -> void:
	print("\n═════ I. ОТВОЕВАТЬ ЦЕНТР ═════")
	if not _AICfg.AI_RECAP_CENTER:
		print("  AI_RECAP_CENTER выключен — раздел пропущен")
		return
	if castle == null:
		verdict("I0 у ИИ есть замок", false, "замок не найден")
		return
	_clear_ai()
	ai.recap_center = false
	await frames(2)

	var center: Vector3 = ai._rally_point()
	# Армия ИИ: набираем ВЫШЕ порога наступления. Считается доля по БОЙЦАМ,
	# поэтому и набираем по бойцам, а не по числу отрядов
	var cap: int = _AICfg.total_army_cap()
	var need: int = int(ceil(float(cap) * _AICfg.RECAP_ARMY_FRACTION))
	var kinds := ["spearman", "archer", "warrior"]
	var have := 0
	var ki := 0
	var home: Vector3 = castle.global_position + Vector3(-14.0, 0.0, 0.0)
	while have < need:
		var uid: String = String(kinds[ki % kinds.size()])
		var n: int = _UCfg.squad_size(uid)
		_ai_squad(uid, home + Vector3(float(ki % 8) * 6.0, 0.0, float(ki / 8) * 6.0), n)
		have += n
		ki += 1
	# Центр держит игрок: его бойцов там больше, чем наших (наших там нет вовсе)
	var theirs: Array = []
	for i in range(40):
		theirs.append(_spawn("spearman", Constants.FACTION_PLAYER,
			center + Vector3(float(i % 8) * 0.8, 0.0, float(i / 8) * 0.8)))
	await frames(4)
	ai._regroup()
	print("  армия ИИ %d бойцов (%d%% лимита %d), у центра бойцов игрока %d" % [
		ai.army_size(), int(ai._army_fill() * 100.0), cap,
		ai._player_combat_near(center)])

	ai._command_squads_defensive(castle)
	await frames(2)
	verdict("I1 полная армия при потерянном центре идёт в наступление",
		ai.recap_center, "recap=%s, армия %d%% при пороге %d%%" % [
			str(ai.recap_center), int(ai._army_fill() * 100.0),
			int(_AICfg.RECAP_ARMY_FRACTION * 100.0)])

	var guards: Dictionary = {}
	var to_center := 0
	var worst_off := 0.0
	for s in ai.squads:
		var sq: Dictionary = s
		var uid2: String = String(sq["type"])
		if String(sq["role"]) == ai.ROLE_GUARD:
			guards[uid2] = int(guards.get(uid2, 0)) + 1
		elif String(sq["role"]) == ai.ROLE_RECAP:
			to_center += 1
			worst_off = maxf(worst_off, (sq["target"] as Vector3).distance_to(center))
	var guard_ok := true
	for k in guards:
		if int(guards[k]) > _AICfg.RECAP_HOME_GUARD:
			guard_ok = false
	print("  роли: дома %s, на центр %d отрядов, дальше всех от центра %.1f м" % [
		str(guards), to_center, worst_off])
	verdict("I2 дома не больше RECAP_HOME_GUARD на род, остальное — на центр",
		guard_ok and to_center > 0,
		"дома %s при лимите %d, на центр %d" % [
			str(guards), _AICfg.RECAP_HOME_GUARD, to_center])

	# I3: центр отбит — наступление сворачивается само
	for u in theirs:
		if is_instance_valid(u):
			(u as Node).queue_free()
	# Свои у центра есть: переносим один отряд туда, иначе «отвоёван» не считается
	var mine: Array = ai.squads[0]["members"]
	for u in mine:
		if is_instance_valid(u):
			(u as Node3D).global_position = center
	await frames(4)
	ai._update_recap()
	verdict("I3 отвоёванный центр возвращает ИИ в оборону", not ai.recap_center,
		"recap=%s, у центра своих %d, чужих %d" % [str(ai.recap_center),
			ai._own_near(center), ai._player_combat_near(center)])
	_clear_ai()
	await frames(2)

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
