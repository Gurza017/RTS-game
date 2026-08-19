extends Node

## СТЕНД: ГАРНИЗОН ЗАМКА
##   1 ВХОД     — ПКМ отрядом по своему замку заводит отряд внутрь
##   2 СНЯТ С КАРТЫ — внутри бойцы невидимы, вне сетки и вне групп фракции
##   3 ЛЕЧЕНИЕ  — раненые восстанавливают HP
##   4 ПОПОЛНЕНИЕ — погибшие модели возвращаются до полного состава
##   5 ЛИМИТ    — больше GARRISON_SQUAD_LIMIT отрядов не влезает
##   6 ВЫХОД    — отряд выпускается наружу целым
##   7 НАГРАДЫ  — пополнение получает ветеранские бонусы отряда

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main: Node = null
var hud = null
var sm = null
var castle: Castle = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	await frames(2)
	hud = main.hud
	sm  = main.selection_manager
	castle = Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(-46.0, 0.0, -46.0)
	await frames(3)
	print("  конфиг: лимит=%d отрядов, лечение=%.0f HP/c, модель за %.0f c, вход с %.0f м" % [
		_UCfg.GARRISON_SQUAD_LIMIT, _UCfg.GARRISON_HEAL_PER_SEC,
		_UCfg.GARRISON_REVIVE_SECONDS, _UCfg.GARRISON_ENTER_RADIUS])

	await _test_enter()
	await _test_heal_and_refill()
	await _test_limit()
	await _test_release()
	_summary()
	print("\n=== GARRISON TEST DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-56s %s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

## Отряд копейщиков рядом с замком
func make_squad(n: int, pos: Vector3) -> int:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(n):
		var u := Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = pos + Vector3(float(i) * 0.6, 0.0, 0.0)
		GameManager.add_to_squad(sid, u)
	await frames(2)
	return sid

var squad_a: int = 0

# ═════════════════════════════════════════════════════════════════════════════
func _test_enter() -> void:
	print("\n═════ 1-2. ВХОД В ЗАМОК ═════")
	squad_a = await make_squad(8, castle.global_position + Vector3(3.0, 0.0, 3.0))
	var members := GameManager.squad_members(squad_a)
	print("  отряд из %d бойцов рядом с замком" % members.size())

	var ok: bool = castle.request_garrison(squad_a)
	print("  запрос гарнизона принят: %s" % str(ok))
	# Даём отряду дойти и всосаться.
	# ЗАПАС УВЕЛИЧЕН С 20 ДО 60 ШАГОВ (3.3 → 10 с симуляции), и это не «ослабили
	# проверку». Ворота переехали к НАРИСОВАННОМУ фасаду (мировой +Z, см.
	# Building — «ТОЧКА ВЫХОДА»), а отряд стенд ставит по диагонали от замка: до
	# прежних ворот, смотревших к середине карты, ему было 2.9 м, до нынешних —
	# 8.0 м, то есть ровно вчетверо дольше хода. Диагностика показала, что
	# восьмой боец честно ИДЁТ (state=MOVING, 5.3 м до ворот) и не успевает
	# в прежнее окно; проверяется здесь механика гарнизона, а не скорость шага
	for _i in range(60):
		await frames(10)
		if castle._slot_of(squad_a) >= 0:
			break
	var inside: bool = castle._slot_of(squad_a) >= 0
	print("  отряд внутри: %s, гарнизон=%d, на подходе=%d" % [
		str(inside), castle.garrison.size(), castle._incoming.size()])
	verdict("1 отряд зашёл в замок", inside)

	var hidden := 0
	var off_tick := 0
	var off_group := 0
	var no_ghost := 0
	for m in GameManager.squad_members(squad_a):
		var u: Unit = m
		if not u.visible: hidden += 1
		# БЫЛО `u.collision_layer == 0`. Физического тела у бойца больше нет
		# (Unit наследует Node3D), само свойство исчезло вместе с ним — стенд
		# валился ошибкой доступа. Проверяем то, что этот признак и означал:
		# боец снят с тика
		if not u.is_physics_processing(): off_tick += 1
		if not u.is_in_group("player_units"): off_group += 1
		# ФАНТОМЫ ГАРНИЗОНА. Картинка бойца — слот в общем MultiMesh, и он живёт
		# НЕ под узлом бойца: u.visible = false его не гасит. Пока слот не
		# возвращали явно (Unit.leave_render), ушедший в замок отряд оставался
		# нарисованным на месте входа
		if GameManager.far_units.slot_of(u) == null: no_ghost += 1
	var n: int = GameManager.squad_members(squad_a).size()
	print("  из %d бойцов: невидимы=%d, сняты с тика=%d, вне группы фракции=%d, без слота отрисовки=%d" % [
		n, hidden, off_tick, off_group, no_ghost])
	verdict("2 бойцы сняты с карты (невидимы, вне тика, вне групп)",
		n > 0 and hidden == n and off_tick == n and off_group == n)
	verdict("2 фантомов в общей отрисовке не осталось", n > 0 and no_ghost == n,
		"слот остался у %d из %d" % [n - no_ghost, n])
	verdict("2 отряд по-прежнему числится живым", n > 0, "бойцов=%d" % n)

# ═════════════════════════════════════════════════════════════════════════════
func _test_heal_and_refill() -> void:
	print("\n═════ 3-4. ЛЕЧЕНИЕ И ПОПОЛНЕНИЕ ═════")
	var members := GameManager.squad_members(squad_a)
	# Ранить половину
	var hurt := 0
	for i in range(members.size()):
		if i % 2 == 0:
			var u: Unit = members[i]
			u.current_health = 20.0
			hurt += 1
	var before_hp := 0.0
	for m in GameManager.squad_members(squad_a):
		before_hp += (m as Unit).current_health
	print("  ранено бойцов: %d, суммарное HP отряда: %.0f" % [hurt, before_hp])
	# ВРЕМЯ МЕРИМ ЧАСАМИ, А НЕ КАДРАМИ: в headless кадр заметно короче 1/60 c,
	# и «180 кадров» — это НЕ 3 секунды игрового времени
	var t0: int = Time.get_ticks_msec()
	await frames(180)
	var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var after_hp := 0.0
	var full := 0
	for m in GameManager.squad_members(squad_a):
		after_hp += (m as Unit).current_health
		if (m as Unit).current_health >= (m as Unit).max_health - 0.01:
			full += 1
	var gained: float = after_hp - before_hp
	var rate: float = gained / maxf(elapsed, 0.001) / float(maxi(hurt, 1))
	print("  за %.2f c: HP %.0f → %.0f (+%.0f), полностью здоровы=%d из %d" % [
		elapsed, before_hp, after_hp, gained, full,
		GameManager.squad_members(squad_a).size()])
	print("  фактический темп: %.2f HP/c на бойца (конфиг %.2f)" % [
		rate, _UCfg.GARRISON_HEAL_PER_SEC])
	verdict("3 раненые лечатся внутри замка", gained > 0.0,
		"прирост HP=%.0f за %.2f c" % [gained, elapsed])
	verdict("3 темп лечения совпадает с конфигом (±20%%)",
		absf(rate - _UCfg.GARRISON_HEAL_PER_SEC) <= _UCfg.GARRISON_HEAL_PER_SEC * 0.2,
		"факт=%.2f конфиг=%.2f HP/c" % [rate, _UCfg.GARRISON_HEAL_PER_SEC])

	# Пополнение: убиваем часть отряда прямо внутри
	var alive := GameManager.squad_members(squad_a)
	var target: int = _UCfg.squad_size("spearman")
	var kill: int = maxi(alive.size() / 2, 1)
	for i in range(kill):
		(alive[i] as Unit)._die()
	await frames(3)
	var after_kill: int = GameManager.squad_members(squad_a).size()
	var missing: int = castle.garrison_missing(squad_a)
	print("  убито внутри: %d, осталось %d, не хватает до полного (%d): %d" % [
		kill, after_kill, target, missing])
	# Крутим до тех пор, пока НЕ пройдёт заданное игровое время (по часам)
	var t1: int = Time.get_ticks_msec()
	var want_sec: float = _UCfg.GARRISON_REVIVE_SECONDS * 4.0
	while float(Time.get_ticks_msec() - t1) / 1000.0 < want_sec:
		await frames(30)
	var spent: float = float(Time.get_ticks_msec() - t1) / 1000.0
	var refilled: int = GameManager.squad_members(squad_a).size()
	var made: int = refilled - after_kill
	var per_model: float = spent / float(maxi(made, 1))
	print("  за %.1f c: бойцов %d → %d (восстановлено %d)" % [
		spent, after_kill, refilled, made])
	print("  фактический темп: %.1f c на модель (конфиг %.1f)" % [
		per_model, _UCfg.GARRISON_REVIVE_SECONDS])
	print("  => полный отряд из %d с нуля соберётся примерно за %.0f c" % [
		target, float(target) * _UCfg.GARRISON_REVIVE_SECONDS])
	verdict("4 погибшие модели восстанавливаются", made > 0,
		"было=%d стало=%d" % [after_kill, refilled])
	verdict("4 темп пополнения совпадает с конфигом (±25%%)",
		made > 0 and absf(per_model - _UCfg.GARRISON_REVIVE_SECONDS)
			<= _UCfg.GARRISON_REVIVE_SECONDS * 0.25,
		"факт=%.1f конфиг=%.1f c" % [per_model, _UCfg.GARRISON_REVIVE_SECONDS])
	var new_hidden := 0
	for m in GameManager.squad_members(squad_a):
		if not (m as Unit).visible:
			new_hidden += 1
	verdict("4 пополнение тоже внутри, а не на карте",
		new_hidden == refilled, "скрытых=%d из %d" % [new_hidden, refilled])

# ═════════════════════════════════════════════════════════════════════════════
func _test_limit() -> void:
	print("\n═════ 5. ЛИМИТ ГАРНИЗОНА ═════")
	var accepted := 0
	var rejected := 0
	for i in range(_UCfg.GARRISON_SQUAD_LIMIT + 2):
		var sid: int = await make_squad(3, castle.global_position + Vector3(2.0, 0.0, 2.0))
		if castle.request_garrison(sid):
			accepted += 1
		else:
			rejected += 1
	print("  попыток=%d, принято=%d, отказано=%d (лимит %d, один слот уже занят)" % [
		_UCfg.GARRISON_SQUAD_LIMIT + 2, accepted, rejected, _UCfg.GARRISON_SQUAD_LIMIT])
	var total: int = castle.garrison.size() + castle._incoming.size()
	print("  всего в гарнизоне + на подходе: %d" % total)
	verdict("5 сверх лимита отряды не принимаются",
		total <= _UCfg.GARRISON_SQUAD_LIMIT and rejected > 0,
		"всего=%d отказов=%d" % [total, rejected])

# ═════════════════════════════════════════════════════════════════════════════
func _test_release() -> void:
	print("\n═════ 6-7. ВЫХОД ИЗ ЗАМКА ═════")
	# Награда отряду, чтобы проверить наследование пополнением
	GameManager.squads[squad_a]["level"] = 1
	GameManager.squads[squad_a]["pending"] = 1
	GameManager.apply_veteran_choice(squad_a, 0)
	var bonus: float = GameManager.squad_bonus(squad_a, "attack")
	var with_bonus := 0
	for m in GameManager.squad_members(squad_a):
		if absf((m as Unit).vet_attack - bonus) < 0.001:
			with_bonus += 1
	var n: int = GameManager.squad_members(squad_a).size()
	print("  награда отряда: +%.0f к атаке, получили %d из %d бойцов" % [bonus, with_bonus, n])
	verdict("7 весь состав (включая пополнение) имеет награду", with_bonus == n,
		"с бонусом=%d из %d" % [with_bonus, n])

	var before: int = castle.garrison.size()
	var ok: bool = castle.release_garrison(squad_a)
	await frames(5)
	var out_visible := 0
	var in_group := 0
	for m in GameManager.squad_members(squad_a):
		var u: Unit = m
		if u.visible: out_visible += 1
		if u.is_in_group("player_units"): in_group += 1
	print("  выпуск принят=%s, гарнизон %d → %d" % [str(ok), before, castle.garrison.size()])
	print("  наружу вышло: видимых=%d, в группе фракции=%d из %d" % [
		out_visible, in_group, GameManager.squad_members(squad_a).size()])
	verdict("6 отряд выпущен целиком и вернулся на карту",
		ok and out_visible == GameManager.squad_members(squad_a).size()
		and in_group == out_visible and castle.garrison.size() == before - 1)
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("  осиротевших узлов: %d" % orphan)
	verdict("6 нет утечки узлов", orphan == 0, "orphan=%d" % orphan)
