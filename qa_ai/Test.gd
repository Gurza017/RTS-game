extends Node

## СТЕНД ПРОВЕРКИ ИИ И КОНФИГА ЛИМИТОВ
##   1 КОНФИГ            — лимиты и размеры отрядов читаются и наглядны
##   2 СТАРТ             — у ИИ нет войск, только замок и рабочие
##   3 ЭКОНОМИКА/СТРОЙКА — рабочие до лимита, барак ЗА РЕСУРСЫ, кузница, наука
##   4 НАЙМ ДО ЛИМИТОВ   — отряды набираются по SQUAD_LIMIT, по одному заказу
##   5 РОЛИ              — гарнизон в ЗАЩИТЕ по кольцу у замка, излишки к озеру
##   6 АТАКА И ТАКТИКИ   — лимит набран → штурм, раскладка по тактике
##   8 НАГРУЗКА          — медиана TIME_PHYSICS_PROCESS при полной армии
##   7 ВОССТАНОВЛЕНИЕ    — армию выбили → барак и найм заново
## (пункт 8 стоит ПЕРЕД 7 намеренно: мерить нагрузку надо на полной армии,
##  а тест 7 эту армию уничтожает)

const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _UCfg  := preload("res://scripts/unit_stats_config.gd")

var main: Node = null
var ai = null

## Накопленный журнал действий ИИ (все last_action по тикам)
var ai_log: Array = []
## Итоговые вердикты: [название, прошло?]
var verdicts: Array = []
## Снимок ролей в режиме «излишков»: армия ещё НЕ набрана, гарнизон уже полон.
## Именно этот режим и регулирует SEND_SURPLUS_TO_LAKE — после набора полного
## лимита отряды в любом случае уходят волной.
var surplus_snap: Dictionary = {}

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

## Один тик ИИ с записью действий в журнал
func ai_tick() -> void:
	ai.tick()
	var act: String = String(ai.last_action)
	if act != "":
		ai_log.append(act)

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	await frames(2)
	ai = main.enemy_ai

	_test_config()
	await _test_start()
	await _test_economy_and_build()
	await _test_training_to_limits()
	_test_roles()
	await _test_assault_and_tactics()
	await _test_load()
	await _test_recovery()
	_summary()
	print("\n=== AI TEST DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-46s %s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

# ═════════════════════════════════════════════════════════════════════════════
func _test_config() -> void:
	print("\n═════ 1. КОНФИГ ai_start_army_limit.gd ═════")
	print("  ЛИМИТЫ ОТРЯДОВ:")
	for key in _AICfg.SQUAD_LIMIT:
		var uid: String = String(key)
		print("    %-9s %d отрядов × %d моделей = %d бойцов" % [
			uid, _AICfg.squad_limit(uid), _UCfg.squad_size(uid),
			_AICfg.squad_limit(uid) * _UCfg.squad_size(uid)])
	var total_men := 0
	for key in _AICfg.SQUAD_LIMIT:
		var uid: String = String(key)
		total_men += _AICfg.squad_limit(uid) * _UCfg.squad_size(uid)
	print("    ВСЕГО: %d отрядов, %d бойцов" % [_AICfg.total_squad_limit(), total_men])
	print("  РАБОЧИЕ: старт=%d, лимит=%d" % [_AICfg.START_WORKERS, _AICfg.WORKER_LIMIT])
	print("  ГАРНИЗОН: %d отряда каждого типа у замка, излишки к озеру=%s" % [
		_AICfg.HOME_GUARD_PER_TYPE, str(_AICfg.SEND_SURPLUS_TO_LAKE)])
	print("  ТЕМП: мир=%.0f c, такт=%.1f c, заказов в очереди=%d" % [
		_AICfg.PEACE_SECONDS, _AICfg.THINK_INTERVAL, _AICfg.MAX_QUEUED_ORDERS])
	print("  ВОССТАНОВЛЕНИЕ: барак бесплатно=%s, порог потери армии=%d" % [
		str(_AICfg.REBUILD_BARRACKS_FREE), _AICfg.ARMY_LOST_THRESHOLD])
	print("  ТОЧКА СБОРА (озеро): %s, радиус спора=%.0f" % [
		str(main.ai_rally_point()), _AICfg.LAKE_CONTEST_RADIUS])
	print("  РАЗМЕР ОТРЯДА в unit_stats_config: копейщики=%d, лучники=%d, мечники=%d (предохранитель=%d)" % [
		_UCfg.SQUAD_SIZE_SPEARMEN, _UCfg.SQUAD_SIZE_ARCHERS,
		_UCfg.SQUAD_SIZE_SWORDSMEN, _UCfg.SQUAD_SIZE_HARD_CAP])
	print("  Building.MAX_SQUAD_SIZE=%d (должен равняться SQUAD_SIZE_HARD_CAP=%d)" % [
		Building.MAX_SQUAD_SIZE, _UCfg.SQUAD_SIZE_HARD_CAP])
	print("  ТАКТИКИ (%d, по кругу=%s), FLANK_SPREAD=%.0f:" % [
		_AICfg.TACTICS.size(), str(_AICfg.TACTICS_IN_ORDER), _AICfg.FLANK_SPREAD])
	for t in _AICfg.TACTICS:
		var d: Dictionary = t
		var parts: Array = []
		for uk in (d["layout"] as Dictionary):
			var uid: String = String(uk)
			var l: Dictionary = (d["layout"] as Dictionary)[uid]
			parts.append("%s(глубина %+.0f, фланг %.0f)" % [uid, float(l["depth"]), float(l["flank"])])
		print("    %-14s «%s»: %s" % [String(d["id"]), String(d["name"]), ", ".join(parts)])
	# Сверка: заказ найма реально берёт размер из SQUAD_SIZE_*
	var cfg_ok := Building.MAX_SQUAD_SIZE == _UCfg.SQUAD_SIZE_HARD_CAP
	for pair in [["barracks", "spearman"], ["barracks", "archer"], ["castle", "warrior"]]:
		var b: String = String(pair[0])
		var u: String = String(pair[1])
		var c: Dictionary = _UCfg.train_cfg(b, u)
		var want: int = _UCfg.squad_size(u)
		var same: bool = int(c.get("squad", -1)) == want
		cfg_ok = cfg_ok and same
		print("  TRAINING[%s][%s].squad=%d, squad_size()=%d → %s" % [
			b, u, int(c.get("squad", -1)), want, "OK" if same else "РАСХОЖДЕНИЕ"])
	verdict("1 конфиг связан с TRAINING и Building", cfg_ok)

# ═════════════════════════════════════════════════════════════════════════════
func _test_start() -> void:
	print("\n═════ 2. СТАРТ ИИ ═════")
	var workers := 0
	var combat := 0
	for n in get_tree().get_nodes_in_group("enemy_units"):
		if n is Worker: workers += 1
		else: combat += 1
	var blds: Array = []
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		blds.append((b as Building).display_name)
	print("  рабочих=%d (конфиг START_WORKERS=%d), БОЕВЫХ=%d (должно быть 0)" % [
		workers, _AICfg.START_WORKERS, combat])
	print("  постройки ИИ: %s" % str(blds))
	var only_castle: bool = blds.size() == 1 and String(blds[0]) == "Замок"
	verdict("2 старт: 0 боевых, %d рабочих, только замок" % _AICfg.START_WORKERS,
		combat == 0 and workers == _AICfg.START_WORKERS and only_castle,
		"боевых=%d рабочих=%d постройки=%s" % [combat, workers, str(blds)])
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
## Прокрутить производство здания мгновенно (в тесте ждать минуты незачем)
func flush(bld: Building, cap: int = 400) -> void:
	var guard := 0
	while guard < cap:
		if bld == null or not is_instance_valid(bld):
			return
		if bld.production_queue.is_empty() and bld._pending_spawns.is_empty():
			return
		bld._production_timer = 99999.0
		# ПАУЗУ МЕЖДУ ШЕРЕНГАМИ ТОЖЕ ПРОМАТЫВАЕМ. Отряд выходит из ворот
		# шеренга за шеренгой с задержкой ROW_RELEASE_SEC (см. Building):
		# у отряда в 50 человек это почти две секунды, и прежнего запаса кадров
		# не хватало — последняя шеренга не успевала выйти, и стенд мерил
		# неполный отряд (замер: 15 лучников из 20). Здесь нас интересует
		# ИТОГОВЫЙ состав, а не темп выхода: его проверяет qa_spear, раздел A
		bld._row_gate = 0.0
		await get_tree().process_frame
		guard += 1

## ДОВЕСТИ ВСЕ СТРОЙКИ ИИ ДО КОНЦА.
## Ждать вживую, пока рабочие дойдут до фундамента и настучат положенные
## секунды, стенд не может — прогон растянулся бы на минуты. Поэтому ждём
## РЕАЛЬНОГО прихода артели (это и есть проверяемое поведение: ИИ действительно
## посылает рабочих на стройку), а сам прогресс доматываем.
## Возвращает число достроенных зданий
func _finish_sites(max_frames: int = 240) -> int:
	var done := 0
	var guard := 0
	while guard < max_frames:
		var sites: Array = []
		for s in get_tree().get_nodes_in_group("construction_sites"):
			if is_instance_valid(s) and (s as Building).faction == Constants.FACTION_ENEMY:
				sites.append(s)
		if sites.is_empty():
			return done
		for s in sites:
			# Артель уже стучит — доматываем прогресс до готовности
			if s.builder_count() > 0:
				s.progress = s.build_time
				done += 1
		await get_tree().process_frame
		guard += 1
	return done

func _enemy_castle() -> Castle:
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if b is Castle:
			return b as Castle
	return null

func _enemy_barracks() -> Building:
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if b is Barracks:
			return b as Building
	return null

func _count_enemy(kind: String) -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		if (u as Unit).stat_id == kind:
			n += 1
	return n

func _rich() -> void:
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_ENEMY, int(t), 500000.0)

func _test_economy_and_build() -> void:
	print("\n═════ 3. ЭКОНОМИКА И СТРОЙКА ═════")
	var gold_before: float = ResourceManager.get_amount(
		Constants.FACTION_ENEMY, Constants.RESOURCE_GOLD)
	print("  ресурсы ИИ до накачки: золото=%.0f" % gold_before)
	_rich()
	ai._peace_over = true    # мирную фазу в тесте не выжидаем
	var castle := _enemy_castle()
	# Тикаем ИИ и прокручиваем очередь замка, пока рабочие не выйдут на лимит
	for step in range(40):
		await ai_tick()
		await flush(castle, 60)
		await _finish_sites()
		var w := _count_enemy("worker")
		if w >= _AICfg.WORKER_LIMIT:
			break
	# ИИ строит ЧЕРЕЗ ФУНДАМЕНТ, как и игрок: барак с кузницей появляются не
	# мгновенно, а после того, как артель достучит стройку. Даём ИИ ещё
	# несколько тактов на закладку и достройку обоих зданий
	for step2 in range(12):
		await ai_tick()
		await _finish_sites()
	var workers: int = _count_enemy("worker")
	print("  рабочих стало: %d (лимит %d)" % [workers, _AICfg.WORKER_LIMIT])
	var names: Array = []
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		names.append((b as Building).display_name)
	print("  постройки ИИ: %s" % str(names))
	# Первый барак должен быть КУПЛЕН, а не выдан бесплатно
	var free_early := false
	var research := 0
	for line in ai_log:
		var s: String = String(line)
		if s.find("бесплатно") >= 0:
			free_early = true
		if s.find("исследование") >= 0:
			research += 1
	print("  журнал ИИ (стройка): барак бесплатно до потери армии=%s, исследований=%d" % [
		str(free_early), research])
	var log_tail: Array = []
	for i in range(maxi(0, ai_log.size() - 6), ai_log.size()):
		log_tail.append(String(ai_log[i]))
	print("  последние записи журнала: %s" % str(log_tail))
	verdict("3 рабочие до WORKER_LIMIT", workers == _AICfg.WORKER_LIMIT,
		"%d из %d" % [workers, _AICfg.WORKER_LIMIT])
	verdict("3 барак и кузница построены",
		names.has("Бараки") and names.has("Кузница"), str(names))
	verdict("3 ПЕРВЫЙ барак куплен за ресурсы (не бесплатно)", not free_early)
	verdict("3 идут исследования в кузнице", research > 0, "исследований=%d" % research)

# ═════════════════════════════════════════════════════════════════════════════
func _test_training_to_limits() -> void:
	print("\n═════ 4. НАЙМ ДО ЛИМИТОВ ═════")
	var castle := _enemy_castle()
	var barracks := _enemy_barracks()
	if barracks == null:
		verdict("4 найм до лимитов", false, "барак не построен")
		return
	print("  барак есть: %s" % (barracks as Building).display_name)
	var max_queue := 0
	for step in range(200):
		await ai_tick()
		max_queue = maxi(max_queue, barracks.production_queue.size())
		max_queue = maxi(max_queue, castle.production_queue.size())
		await flush(barracks, 80)
		await flush(castle, 80)
		_snap_surplus()
		if ai.army_ready():
			break
		if step % 40 == 0:
			print("    шаг %3d: %s" % [step, ai.report()])
	# ДОЖДАТЬСЯ, ПОКА ПОСЛЕДНИЙ ЗАКАЗ ВЫЙДЕТ ИЗ ВОРОТ. Цикл выше обрывается по
	# army_ready(), а тот считает ОТРЯДЫ: последний отряд числится готовым, едва
	# из ворот вышла его первая шеренга. Замерять состав в этот момент — значит
	# ловить недособранный отряд (замер: 10 лучников из 20)
	await flush(barracks, 400)
	await flush(castle, 400)
	await ai_tick()
	print("  ИТОГ: %s" % ai.report())
	print("  максимум заказов в одной очереди: %d (лимит MAX_QUEUED_ORDERS=%d)" % [
		max_queue, _AICfg.MAX_QUEUED_ORDERS])
	# Число отрядов и размер каждого
	var sizes: Dictionary = {}
	for s in ai.squads:
		var sq: Dictionary = s
		var uid: String = String(sq["type"])
		if not sizes.has(uid):
			sizes[uid] = []
		(sizes[uid] as Array).append((sq["members"] as Array).size())
	var counts_ok := true
	var sizes_ok := true
	for t in _AICfg.combat_types():
		var uid: String = String(t)
		var arr: Array = sizes.get(uid, [])
		var want_n: int = _AICfg.squad_limit(uid)
		var want_sz: int = _UCfg.squad_size(uid)
		if arr.size() != want_n:
			counts_ok = false
		for v in arr:
			if int(v) != want_sz:
				sizes_ok = false
		print("    %-9s отрядов=%d (лимит %d), размеры=%s (ожидался %d)" % [
			uid, arr.size(), want_n, str(arr), want_sz])
	print("  всего боевых юнитов ИИ: %d" % ai.army_size())
	verdict("4 число отрядов = SQUAD_LIMIT по каждому типу", counts_ok)
	verdict("4 размер каждого отряда = squad_size()", sizes_ok)
	verdict("4 очередь здания <= MAX_QUEUED_ORDERS",
		max_queue <= _AICfg.MAX_QUEUED_ORDERS, "максимум %d" % max_queue)
	verdict("4 army_ready() = true", bool(ai.army_ready()))
	if surplus_snap.is_empty():
		print("  снимок режима излишков не получен (гарнизон не успел заполниться)")
	else:
		print("  снимок режима излишков (армия ещё не набрана, гарнизон полон): роли=%s, отрядов=%d" % [
			str(surplus_snap["roles"]), int(surplus_snap["total"])])
		print("    постов гарнизона в снимке=%d, минимальный зазор между постами=%.1f м" % [
			int(surplus_snap["guard_posts"]), float(surplus_snap["post_gap"])])
		verdict("5 посты гарнизона разнесены и в режиме удержания дома",
			float(surplus_snap["post_gap"]) > 2.0 or int(surplus_snap["guard_posts"]) < 2,
			"постов=%d, зазор=%.1f м" % [
				int(surplus_snap["guard_posts"]), float(surplus_snap["post_gap"])])

## Поймать момент, когда гарнизон уже укомплектован, а лимит армии ещё нет
func _snap_surplus() -> void:
	if not surplus_snap.is_empty() or ai.army_ready():
		return
	var want_guard: int = _AICfg.combat_types().size() * _AICfg.HOME_GUARD_PER_TYPE
	var roles: Dictionary = {}
	for s in ai.squads:
		var r: String = String((s as Dictionary)["role"])
		roles[r] = int(roles.get(r, 0)) + 1
	if ai.squads.size() <= want_guard:
		return
	if int(roles.get("guard", 0)) < want_guard:
		return
	# Заодно меряем разнос гарнизонных постов именно в этом режиме: при
	# SEND_SURPLUS_TO_LAKE=false домой садятся ВСЕ отряды, и кольцо постов
	# может оказаться поделено не на всех
	var posts: Array = []
	for s in ai.squads:
		var sq: Dictionary = s
		if String(sq["role"]) == ai.ROLE_GUARD:
			posts.append(sq["target"] as Vector3)
	var gap := 1.0e9
	for i in range(posts.size()):
		for j in range(i + 1, posts.size()):
			var a: Vector3 = posts[i]
			var b: Vector3 = posts[j]
			gap = minf(gap, a.distance_to(b))
	if posts.size() < 2:
		gap = -1.0
	surplus_snap = {
		"roles": roles, "total": ai.squads.size(),
		"guard_posts": posts.size(), "post_gap": gap,
	}

# ═════════════════════════════════════════════════════════════════════════════
func _test_roles() -> void:
	print("\n═════ 5. РОЛИ ОТРЯДОВ ═════")
	var castle := _enemy_castle()
	var by_role: Dictionary = {}
	var guard_stance_ok := 0
	var guard_total := 0
	var guard_by_type: Dictionary = {}
	var guard_posts: Array = []
	var field_targets: Array = []
	for s in ai.squads:
		var sq: Dictionary = s
		var r: String = String(sq["role"])
		var uid: String = String(sq["type"])
		by_role[r] = int(by_role.get(r, 0)) + 1
		var members: Array = sq["members"]
		if r == ai.ROLE_GUARD:
			guard_total += 1
			guard_by_type[uid] = int(guard_by_type.get(uid, 0)) + 1
			guard_posts.append(sq["target"] as Vector3)
			var all_def := true
			for m in members:
				if (m as Unit).stance != _UCfg.STANCE_DEFENSE:
					all_def = false
			if all_def:
				guard_stance_ok += 1
		else:
			field_targets.append(sq["target"] as Vector3)
	print("  роли: %s" % str(by_role))
	print("  гарнизонных отрядов=%d, из них полностью в стойке ЗАЩИТА=%d" % [
		guard_total, guard_stance_ok])
	print("  гарнизон по типам: %s (ожидалось по %d на тип)" % [
		str(guard_by_type), _AICfg.HOME_GUARD_PER_TYPE])
	# Гарнизон стоит у замка, поле — у озера
	var rally: Vector3 = main.ai_rally_point()
	for s in ai.squads:
		var sq: Dictionary = s
		var t: Vector3 = sq["target"]
		var d_castle: float = t.distance_to(castle.global_position) if castle != null else -1.0
		print("    %-9s роль=%-8s цель=(%.0f, %.0f)  до замка=%.0f м, до озера=%.0f м" % [
			String(sq["type"]), String(sq["role"]), t.x, t.z,
			d_castle, t.distance_to(rally)])
	# Посты гарнизона должны быть РАЗНЕСЕНЫ по кольцу
	var min_gap := 1.0e9
	for i in range(guard_posts.size()):
		for j in range(i + 1, guard_posts.size()):
			var a: Vector3 = guard_posts[i]
			var b: Vector3 = guard_posts[j]
			min_gap = minf(min_gap, a.distance_to(b))
	if guard_posts.size() < 2:
		min_gap = -1.0
	var ring_ok := true
	var ring_r: Array = []
	for p in guard_posts:
		var pv: Vector3 = p
		var d: float = pv.distance_to(castle.global_position) if castle != null else 0.0
		ring_r.append(snappedf(d, 0.1))
		if absf(d - ai.GUARD_RING) > 1.0:
			ring_ok = false
	print("  посты гарнизона: радиусы от замка=%s (GUARD_RING=%.0f), минимальный зазор между постами=%.1f м" % [
		str(ring_r), ai.GUARD_RING, min_gap])
	# Излишки — у озера
	var field_far := 0
	var min_field_gap := 1.0e9
	for i in range(field_targets.size()):
		var fa: Vector3 = field_targets[i]
		if fa.distance_to(rally) > _AICfg.LAKE_CONTEST_RADIUS:
			field_far += 1
		for j in range(i + 1, field_targets.size()):
			var fb: Vector3 = field_targets[j]
			min_field_gap = minf(min_field_gap, fa.distance_to(fb))
	if field_targets.size() < 2:
		min_field_gap = -1.0
	print("  полевых отрядов=%d, из них дальше %.0f м от озера=%d, минимальный зазор между целями=%.1f м" % [
		field_targets.size(), _AICfg.LAKE_CONTEST_RADIUS, field_far, min_field_gap])

	var want_guard: int = _AICfg.combat_types().size() * _AICfg.HOME_GUARD_PER_TYPE
	var per_type_ok := true
	for t in _AICfg.combat_types():
		if int(guard_by_type.get(String(t), 0)) != _AICfg.HOME_GUARD_PER_TYPE:
			per_type_ok = false
	if _AICfg.DEFENSIVE_MODE:
		# ОБОРОНИТЕЛЬНЫЙ РЕЖИМ: ролей field/assault не бывает вовсе — излишки
		# уходят в заслон (line) и патрули (patrol), см. EnemyAI._command_squads_defensive
		verdict("5 гарнизон = HOME_GUARD_PER_TYPE на тип",
			guard_total == want_guard and per_type_ok,
			"guard=%d, ожидалось %d, по типам %s" % [guard_total, want_guard, str(guard_by_type)])
		verdict("5 оборона: штурмовых ролей нет",
			int(by_role.get("assault", 0)) == 0 and int(by_role.get("field", 0)) == 0,
			"роли=%s" % str(by_role))
		var line_n: int = int(by_role.get("line", 0))
		var patrol_n: int = int(by_role.get("patrol", 0))
		verdict("5 оборона: излишки в заслоне или патруле",
			(line_n + patrol_n) > 0 or ai.squads.size() <= want_guard,
			"line=%d, patrol=%d, всего отрядов=%d" % [line_n, patrol_n, ai.squads.size()])
		verdict("5 оборона: патрулей не больше PATROL_SQUADS",
			patrol_n <= _AICfg.PATROL_SQUADS,
			"patrol=%d, лимит %d" % [patrol_n, _AICfg.PATROL_SQUADS])
	elif _AICfg.SEND_SURPLUS_TO_LAKE:
		verdict("5 гарнизон = HOME_GUARD_PER_TYPE на тип",
			guard_total == want_guard and per_type_ok,
			"guard=%d, ожидалось %d, по типам %s" % [guard_total, want_guard, str(guard_by_type)])
		verdict("5 излишки в роли field у озера",
			int(by_role.get("field", 0)) > 0 and field_far == 0,
			"field=%d, дальше радиуса озера=%d" % [int(by_role.get("field", 0)), field_far])
	else:
		# Вердикт берётся по СНИМКУ режима излишков: к моменту секции 5 армия уже
		# набрана целиком и уходит волной независимо от SEND_SURPLUS_TO_LAKE
		if surplus_snap.is_empty():
			verdict("5 SEND_SURPLUS_TO_LAKE=false: все излишки в guard", false,
				"снимок режима излишков не получен")
		else:
			var r: Dictionary = surplus_snap["roles"]
			verdict("5 SEND_SURPLUS_TO_LAKE=false: все излишки в guard",
				int(r.get("field", 0)) == 0 and int(r.get("assault", 0)) == 0
					and int(r.get("guard", 0)) == int(surplus_snap["total"]),
				"снимок излишков: роли=%s из %d отрядов; на момент секции 5 (лимит набран) роли=%s" % [
					str(r), int(surplus_snap["total"]), str(by_role)])
	verdict("5 все гарнизонные бойцы в стойке ЗАЩИТА",
		guard_total > 0 and guard_stance_ok == guard_total,
		"%d из %d" % [guard_stance_ok, guard_total])
	verdict("5 посты гарнизона на кольце вокруг замка", ring_ok, "радиусы=%s" % str(ring_r))
	verdict("5 посты гарнизона разнесены (не в одной точке)", min_gap > 2.0,
		"минимальный зазор=%.1f м" % min_gap)

# ═════════════════════════════════════════════════════════════════════════════
func _test_assault_and_tactics() -> void:
	print("\n═════ 6. АТАКА И ТАКТИКИ ═════")
	if not ai.army_ready():
		print("  ВНИМАНИЕ: лимит не набран, раскладка проверяется на том, что есть")
	# Игроку нужен замок, иначе ИИ некуда идти
	var pcastle: Castle = null
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b is Castle:
			pcastle = b as Castle
	if pcastle == null:
		pcastle = Castle.new()
		pcastle.faction = Constants.FACTION_PLAYER
		main.world_add(pcastle)
		pcastle.global_position = Vector3(-46.0, 0.0, -46.0)
		await frames(1)
	print("  замок игрока в (%.0f, %.0f)" % [pcastle.global_position.x, pcastle.global_position.z])
	for wave in range(_AICfg.TACTICS.size()):
		ai._wave_index = wave
		ai._tactic = _AICfg.tactic_for_wave(wave)
		# ШТУРМОВАЯ раскладка вызывается НАПРЯМУЮ. При DEFENSIVE_MODE обычный
		# tick() уводит отряды в заслон, и тактики волны никогда бы не строились,
		# хотя сам код раскладки живой и используется для глубины в обороне
		ai._command_squads(_enemy_castle())
		await frames(2)
		var tid: String = String(ai._tactic.get("id", "-"))
		print("    волна %d, тактика «%s»:" % [wave, tid])
		var course: Vector3 = (pcastle.global_position - _enemy_castle().global_position)
		course.y = 0.0
		course = course.normalized()
		var depth_by_type: Dictionary = {}
		var flank_by_type: Dictionary = {}
		var targets: Array = []
		var targets_by_type: Dictionary = {}
		for s in ai.squads:
			var sq: Dictionary = s
			if String(sq["role"]) == ai.ROLE_GUARD:
				continue
			var uid: String = String(sq["type"])
			var t: Vector3 = sq["target"]
			targets.append(t)
			if not targets_by_type.has(uid):
				targets_by_type[uid] = []
			(targets_by_type[uid] as Array).append(t)
			var rel: Vector3 = t - pcastle.global_position
			var depth: float = rel.dot(course)
			var right := Vector3(-course.z, 0.0, course.x)
			var flank: float = rel.dot(right)
			if not depth_by_type.has(uid):
				depth_by_type[uid] = []
				flank_by_type[uid] = []
			(depth_by_type[uid] as Array).append(snappedf(depth, 0.1))
			(flank_by_type[uid] as Array).append(snappedf(flank, 0.1))
			print("      %-9s глубина=%+6.1f м  фланг=%+6.1f м" % [uid, depth, flank])
		if ai.squads.is_empty():
			print("      (отрядов нет)")
			continue
		# Совпадающие цели — признак «все в одну точку».
		# Требование ТЗ: отряды ОДНОГО типа не должны целиться в одну точку.
		# Пересечение РАЗНЫХ типов в one_mass — заявленное поведение тактики,
		# поэтому печатается справочно и вердикт не валит.
		var min_gap := 1.0e9
		var pairs := 0
		for uk in targets_by_type:
			var arr: Array = targets_by_type[String(uk)]
			for i in range(arr.size()):
				for j in range(i + 1, arr.size()):
					var a: Vector3 = arr[i]
					var b2: Vector3 = arr[j]
					min_gap = minf(min_gap, a.distance_to(b2))
					pairs += 1
		if pairs == 0:
			min_gap = -1.0
		var min_any := 1.0e9
		for i in range(targets.size()):
			for j in range(i + 1, targets.size()):
				var a2: Vector3 = targets[i]
				var b3: Vector3 = targets[j]
				min_any = minf(min_any, a2.distance_to(b3))
		if targets.size() < 2:
			min_any = -1.0
		print("      минимальный зазор ВНУТРИ типа=%.1f м (пар %d), между любыми отрядами=%.1f м" % [
			min_gap, pairs, min_any])
		verdict("6 «%s»: отряды одного типа не в одной точке" % tid,
			pairs == 0 or min_gap > 0.5, "минимальный зазор внутри типа=%.1f м" % min_gap)
		var da: float = _avg(depth_by_type.get("archer", []))
		var ds: float = _avg(depth_by_type.get("spearman", []))
		var dw: float = _avg(depth_by_type.get("warrior", []))
		# Тип, у которого ВСЕ отряды сидят в гарнизоне, в волне не участвует —
		# требовать от него глубину нельзя
		var has_a: bool = not (depth_by_type.get("archer", []) as Array).is_empty()
		var has_s: bool = not (depth_by_type.get("spearman", []) as Array).is_empty()
		var has_w: bool = not (depth_by_type.get("warrior", []) as Array).is_empty()
		var all3: bool = has_a and has_s and has_w
		print("      средняя глубина: лучники=%+.1f%s, копейщики=%+.1f%s, рыцари=%+.1f%s" % [
			da, "" if has_a else " (в волне нет)", ds, "" if has_s else " (в волне нет)",
			dw, "" if has_w else " (в волне нет)"])
		if not all3:
			print("      в волне представлены не все типы — проверка глубины пропущена")
		if tid == "archers_front" and all3:
			verdict("6 archers_front: лучники впереди, рыцари сзади",
				da > 0.0 and dw < 0.0 and da > ds and ds > dw,
				"лучники=%+.1f копейщики=%+.1f рыцари=%+.1f" % [da, ds, dw])
		elif tid == "spears_back":
			var fa: Array = flank_by_type.get("archer", [])
			var has_plus := false
			var has_minus := false
			for v in fa:
				if float(v) > 1.0: has_plus = true
				if float(v) < -1.0: has_minus = true
			if all3:
				verdict("6 spears_back: рыцари впереди, копейщики сзади",
					dw > 0.0 and ds < 0.0 and dw > da and da > ds,
					"рыцари=%+.1f лучники=%+.1f копейщики=%+.1f" % [dw, da, ds])
			# Проверка обоих флангов имеет смысл только при 2+ полевых
			# отрядах лучников: один отряд физически не может стоять с двух краёв
			if fa.size() >= 2:
				verdict("6 spears_back: лучники по ОБА фланга",
					has_plus and has_minus, "фланги лучников=%s" % str(fa))
			else:
				print("      полевых отрядов лучников=%d — обоих флангов не набрать, " % fa.size()
					+ "проверка на прогоне с archer>=3; фланги=%s" % str(fa))
		elif tid == "one_mass" and all3:
			verdict("6 one_mass: все на нулевой глубине",
				absf(da) < 0.01 and absf(ds) < 0.01 and absf(dw) < 0.01,
				"лучники=%+.1f копейщики=%+.1f рыцари=%+.1f" % [da, ds, dw])

func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / float(arr.size())

# ═════════════════════════════════════════════════════════════════════════════
## Нагрузка при полной армии ИИ. Монитор TIME_PHYSICS_PROCESS долго держит
## залипшее значение тяжёлого кадра спавна, поэтому: прогрев 240 кадров,
## затем МЕДИАНА по 300 кадрам. По стенным часам не мерить — headless
## главный цикл упирается в 60 fps.
func _test_load() -> void:
	print("\n═════ 8. НАГРУЗКА ПРИ ПОЛНОЙ АРМИИ ═════")
	var units := get_tree().get_nodes_in_group("all_units").size()
	var e_units := get_tree().get_nodes_in_group("enemy_units").size()
	print("  юнитов на карте: всего=%d, из них у ИИ=%d, армия ИИ в отрядах=%d" % [
		units, e_units, ai.army_size()])
	await frames(240)                       # прогрев
	var samples: Array = []
	var orph: Array = []
	for i in range(300):
		await get_tree().process_frame
		samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		orph.append(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	samples.sort()
	var med: float = float(samples[samples.size() / 2])
	var p95: float = float(samples[int(float(samples.size()) * 0.95)])
	print("  TIME_PHYSICS_PROCESS: медиана=%.2f мс, минимум=%.2f мс, максимум=%.2f мс, p95=%.2f мс (%d кадров)" % [
		med, float(samples[0]), float(samples[samples.size() - 1]), p95, samples.size()])
	print("  OBJECT_ORPHAN_NODE_COUNT: начало=%.0f, конец=%.0f" % [
		float(orph[0]), float(orph[orph.size() - 1])])
	print("  прочие мониторы: узлов=%.0f, ресурсов=%.0f" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT)])
	verdict("8 нет утечки осиротевших узлов",
		float(orph[orph.size() - 1]) <= float(orph[0]) + 5.0,
		"было %.0f, стало %.0f" % [float(orph[0]), float(orph[orph.size() - 1])])

# ═════════════════════════════════════════════════════════════════════════════
func _test_recovery() -> void:
	print("\n═════ 7. ВОССТАНОВЛЕНИЕ ПОСЛЕ ПОТЕРИ АРМИИ ═════")
	var before: int = ai.army_size()
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(u) and not (u is Worker):
			(u as Unit)._die()
	var barracks := _enemy_barracks()
	if barracks != null:
		barracks.take_damage(99999.0)
	await frames(3)
	var log_before: int = ai_log.size()
	await ai_tick()
	await frames(2)
	print("  армия была=%d, после зачистки=%d, барак снесён" % [before, ai.army_size()])
	print("  действия ИИ сразу после потери: %s" % ai.last_action)
	# АВАРИЙНЫЙ БАРАК ТОЖЕ СТРОИТСЯ ЧЕРЕЗ ФУНДАМЕНТ. Проверяем, что ИИ его
	# ЗАЛОЖИЛ и довёл до конца, а не что здание возникло в тот же кадр
	var laid: bool = ai._site_in_progress("barracks")
	await _finish_sites()
	var rebuilt: bool = _enemy_barracks() != null
	print("  фундамент заложен=%s, здание достроено=%s" % [str(laid), str(rebuilt)])
	var free_rebuild := false
	for i in range(log_before, ai_log.size()):
		if String(ai_log[i]).find("бесплатно") >= 0:
			free_rebuild = true
	print("  барак восстановлен=%s, бесплатно=%s (REBUILD_BARRACKS_FREE=%s)" % [
		str(rebuilt), str(free_rebuild), str(_AICfg.REBUILD_BARRACKS_FREE)])
	var castle := _enemy_castle()
	for step in range(30):
		await ai_tick()
		await flush(_enemy_barracks(), 60)
		await flush(castle, 60)
		if ai.army_size() > 0:
			break
	print("  ИИ снова набирает: %s" % ai.report())
	print("  ресурсы ИИ: дерево=%.0f золото=%.0f" % [
		ResourceManager.get_amount(Constants.FACTION_ENEMY, Constants.RESOURCE_WOOD),
		ResourceManager.get_amount(Constants.FACTION_ENEMY, Constants.RESOURCE_GOLD)])
	verdict("7 барак отстроен после потери армии", rebuilt)
	verdict("7 аварийный барак выдан бесплатно",
		free_rebuild == _AICfg.REBUILD_BARRACKS_FREE)
	verdict("7 найм возобновлён", ai.army_size() > 0, "бойцов=%d" % ai.army_size())
