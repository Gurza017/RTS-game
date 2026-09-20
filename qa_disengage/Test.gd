extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПРИОРИТЕТ ПРИКАЗА ИГРОКА НАД БОЕМ (Unit._disengaging)
## ═══════════════════════════════════════════════════════════════════════════
##   A ЛУЧНИКИ   — приказ отойти посреди боя не даёт стрелкам развернуться
##                 обратно и продолжить стрельбу
##   B КОПЕЙЩИКИ — то же самое в ближнем бою (никаких «двух шагов назад»)
##   D ОКРУЖЕНИЕ — приказ игрока выводит бойца из свалки ТЕЛОМ: с первого
##                 клика, а не со второго
##   C ФЛАГ СНИМАЕТСЯ — после прихода в точку отряд снова ловит НОВОГО врага
##                 на пути как обычно (march-перехват не сломан навсегда)
##
## Запуск: godot --headless --path . res://qa_disengage/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

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

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	return u

func _squad(kind: String, fac: int, center: Vector3, count: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(count):
		var p := center + Vector3(float(i % 5) * 0.6 - 1.2, 0.0, float(i / 5) * 0.6)
		var u := _new(kind, fac, p)
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

## Срок на дорогу по живой скорости бойцов, а не по потолку с потолка
## (см. CLAUDE.md — «Config is the source of truth»)
func travel_budget_ms(men: Array, to: Vector3) -> int:
	var far := 0.0
	var slow := 1e9
	for m in men:
		if not is_instance_valid(m):
			continue
		var u: Unit = m
		var p: Vector3 = u.global_position
		far = maxf(far, Vector2(p.x - to.x, p.z - to.z).length())
		slow = minf(slow, maxf(u.move_speed, 0.1))
	return int(far / slow * 3000.0) + 2000

func _run() -> void:
	seed(1234)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	GameManager.world_bounds_enabled = false
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  ПРИОРИТЕТ ПРИКАЗА ИГРОКА НАД БОЕМ (отход посреди схватки)        ║")
	print("╚══════════════════════════════════════════════════════════════════╝")
	await _a_archers_disengage()
	await _b_spearmen_disengage()
	await _c_flag_resets()
	await _d_surrounded()

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %s%s" % [_pad(String(row[0]), 58), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== DISENGAGE TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ЛУЧНИКИ ПОД ДАВЛЕНИЕМ КОПЕЙЩИКОВ: ПРИКАЗ ОТОЙТИ ДОЛЖЕН ВЫПОЛНЯТЬСЯ СРАЗУ
# Баг: полшага, march-перехват снова находит того же врага в упор (у лучника
# attack_range ~20 м), боец разворачивается и стреляет дальше — приказ игрока
# невозможно исполнить, пока противник рядом.
# ═════════════════════════════════════════════════════════════════════════════
func _a_archers_disengage() -> void:
	print("\n═════ A. ЛУЧНИКИ: ПРИКАЗ ОТОЙТИ В БОЮ ═════")
	var start := Vector3(0, 0, -500)
	var bows := _squad("archer", Constants.FACTION_PLAYER, start, 6)
	var spears := _squad("spearman", Constants.FACTION_ENEMY, start + Vector3(0, 0, 1.5), 4)

	# Бой заводится напрямую (детерминированно, без ожидания авто-агро):
	# ровно то состояние, в котором игрок жмёт «отойти»
	for i in range(bows.size()):
		var u: Unit = bows[i]
		u.command_attack(spears[i % spears.size()], true)
	await frames(3)
	var engaged := 0
	for u in bows:
		if (u as Unit).attack_target != null:
			engaged += 1
	verdict("A0 бой заведён (подготовка)", engaged == bows.size(),
		"в бою %d из %d" % [engaged, bows.size()])

	var away := start + Vector3(0, 0, -60)
	for u in bows:
		(u as Unit).command_move(away)

	# СРАЗУ ЖЕ: цель снята, состояние — движение
	var cleared := 0
	var moving := 0
	for u in bows:
		var un: Unit = u
		if un.attack_target == null: cleared += 1
		if un.state == Unit.State.MOVING: moving += 1
	verdict("A1 цель снята мгновенно у всех", cleared == bows.size(),
		"снята %d из %d" % [cleared, bows.size()])
	verdict("A1б состояние — марш у всех", moving == bows.size(),
		"марш %d из %d" % [moving, bows.size()])

	# Пара «шальных» попаданий во время отхода — ответный удар на месте должен
	# молчать (see take_damage: not _disengaging)
	var hit_kept_null := true
	for i in range(mini(3, bows.size())):
		var u: Unit = bows[i]
		u.take_damage(4.0, spears[0])
		if u.attack_target != null:
			hit_kept_null = false
	verdict("A2 урон в пути не включает ответный огонь", hit_kept_null)

	# Долго идём и следим: ПОКА БОЕЦ ЕЩЁ В ПУТИ (state MOVING), он не должен
	# развернуться обратно к цели. После прихода (state IDLE) это уже другая
	# история — постового, который дошёл и встал, а потом его догнали, снова
	# трогать можно (см. take_damage IDLE-ветку), это не баг из задания
	var budget := travel_budget_ms(bows, away)
	var t0 := Time.get_ticks_msec()
	var snapped_back := 0
	# ── МЕРИТЬ ПИК, А НЕ КОНЕЦ (17.09.2026) ──────────────────────────────
	# Бюджет втрое щедрее дороги: отряд доходит за ~30 с из 77, встаёт, и
	# дальше его догоняют копейщики — ответ на удар, бой, подход к цели; к
	# концу бюджета двое из шести честно возвращались к точке боя (после
	# прихода это уже другая история, см. выше). Свойство «отряд реально ушёл»
	# — ПИК удаления за окно, а не точка на последнем кадре
	var peak: Dictionary = {}
	while Time.get_ticks_msec() - t0 < budget:
		await get_tree().process_frame
		for u in bows:
			if not is_instance_valid(u):
				continue
			var un: Unit = u
			if un.state == Unit.State.MOVING and un.attack_target != null:
				snapped_back += 1
			var pp: Vector3 = un.global_position
			var dd: float = Vector2(pp.x - start.x, pp.z - start.z).length()
			var key: int = un.get_instance_id()
			if dd > float(peak.get(key, 0.0)):
				peak[key] = dd
	verdict("A3 никто не развернулся обратно к бою НА МАРШЕ", snapped_back == 0,
		"случаев возврата к цели на марше: %d" % snapped_back)

	var progressed := 0
	var at_end := 0
	for u in bows:
		if not is_instance_valid(u):
			continue
		if float(peak.get((u as Unit).get_instance_id(), 0.0)) > 25.0:
			progressed += 1
		var p: Vector3 = (u as Node3D).global_position
		if Vector2(p.x - start.x, p.z - start.z).length() > 25.0:
			at_end += 1
	print("  ушли дальше 25 м от точки боя (пик за окно): %d из %d; на последнем кадре: %d" % [progressed, bows.size(), at_end])
	verdict("A4 отряд реально ушёл, а не топтался на месте",
		progressed >= bows.size() - 1, "ушло %d из %d" % [progressed, bows.size()])

	for u in bows + spears:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. КОПЕЙЩИКИ В БЛИЖНЕМ БОЮ: ТО ЖЕ САМОЕ, НО НА КОРОТКОЙ ДИСТАНЦИИ УДАРА
# ═════════════════════════════════════════════════════════════════════════════
func _b_spearmen_disengage() -> void:
	print("\n═════ B. КОПЕЙЩИКИ: ПРИКАЗ ОТОЙТИ В БОЮ ═════")
	var start := Vector3(60, 0, -500)
	var mine := _squad("spearman", Constants.FACTION_PLAYER, start, 6)
	var foes := _squad("spearman", Constants.FACTION_ENEMY, start + Vector3(0, 0, 1.2), 6)

	for i in range(mine.size()):
		var u: Unit = mine[i]
		u.command_attack(foes[i % foes.size()], true)
	await frames(3)

	var away := start + Vector3(0, 0, -60)
	for u in mine:
		(u as Unit).command_move(away)

	var cleared := 0
	for u in mine:
		if (u as Unit).attack_target == null: cleared += 1
	verdict("B1 цель снята мгновенно у всех", cleared == mine.size(),
		"снята %d из %d" % [cleared, mine.size()])

	var budget := travel_budget_ms(mine, away)
	var t0 := Time.get_ticks_msec()
	var snapped_back := 0
	while Time.get_ticks_msec() - t0 < budget:
		await get_tree().process_frame
		for u in mine:
			if not is_instance_valid(u):
				continue
			var un: Unit = u
			if un.state == Unit.State.MOVING and un.attack_target != null:
				snapped_back += 1
	verdict("B2 никто не развернулся обратно к бою НА МАРШЕ", snapped_back == 0,
		"случаев возврата к цели на марше: %d" % snapped_back)

	var progressed := 0
	for u in mine:
		if not is_instance_valid(u):
			continue
		var p: Vector3 = (u as Node3D).global_position
		if Vector2(p.x - start.x, p.z - start.z).length() > 25.0:
			progressed += 1
	print("  ушли дальше 25 м от точки боя: %d из %d" % [progressed, mine.size()])
	verdict("B3 отряд реально ушёл, а не топтался на месте",
		progressed >= mine.size() - 1, "ушло %d из %d" % [progressed, mine.size()])

	for u in mine + foes:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ФЛАГ _disengaging НЕ ПРОТЕКАЕТ НАВСЕГДА: ПОСЛЕ ПРИХОДА В ТОЧКУ ОТРЯД
# СНОВА ЛОВИТ ВРАГА НА ПУТИ КАК ОБЫЧНО (march-перехват не сломан насовсем)
# ═════════════════════════════════════════════════════════════════════════════
func _c_flag_resets() -> void:
	print("\n═════ C. ФЛАГ СНИМАЕТСЯ ПОСЛЕ ПРИХОДА ═════")
	var start := Vector3(120, 0, -500)
	var mine := _squad("spearman", Constants.FACTION_PLAYER, start, 4)
	var foes := _squad("spearman", Constants.FACTION_ENEMY, start + Vector3(0, 0, 1.2), 4)
	for u in foes:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9

	for i in range(mine.size()):
		var u: Unit = mine[i]
		u.command_attack(foes[i % foes.size()], true)
	await frames(3)

	# Отойти НА ПРИЛИЧНОЕ РАССТОЯНИЕ и встать. Короткий отскок нарочно не берём:
	# на паре метров рядом остаётся живой вражеский строй, и это уже другая,
	# отдельно документированная механика («enemy line is impassable» — CLAUDE.md,
	# _disengaging её намеренно не трогает, в отличие от retreating). Здесь
	# проверяется другое: что флаг сам снимается по приходу, а не «протекает»
	var near := start + Vector3(0, 0, -40)
	for u in mine:
		(u as Unit).command_move(near)
	var settle_budget: int = travel_budget_ms(mine, near)
	var t_settle := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_settle < settle_budget:
		await get_tree().process_frame
		var idle := 0
		for u in mine:
			if is_instance_valid(u) and (u as Unit).state == Unit.State.IDLE:
				idle += 1
		if idle >= mine.size():
			break

	var settled := 0
	for u in mine:
		if is_instance_valid(u) and (u as Unit).state == Unit.State.IDLE:
			settled += 1
	verdict("C1 отряд дошёл и встал", settled >= mine.size() - 1,
		"встали %d из %d" % [settled, mine.size()])

	# Новый заслон дальше по курсу — свежий приказ марша ОБЯЗАН его перехватить,
	# как и любой другой марш (см. qa_aggro/B). Если бы _disengaging тут
	# застряло в true навсегда, боец прошёл бы сквозь заслон не деря
	var wall := _squad("spearman", Constants.FACTION_ENEMY, near + Vector3(0, 0, -30), 4)
	for u in wall:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
	var goal := near + Vector3(0, 0, -60)
	for u in mine:
		if is_instance_valid(u):
			(u as Unit).command_move(goal)

	var t0 := Time.get_ticks_msec()
	var intercept_budget: int = travel_budget_ms(mine, goal)
	var intercepted := 0
	while Time.get_ticks_msec() - t0 < intercept_budget:
		await get_tree().process_frame
		intercepted = 0
		for u in mine:
			if is_instance_valid(u) and (u as Unit).attack_target != null:
				intercepted += 1
		if intercepted >= _alive(mine).size():
			break
	print("  перехватили новый заслон на пути: %d из %d" % [intercepted, _alive(mine).size()])
	verdict("C2 новый заслон на пути перехвачен как обычно",
		intercepted >= maxi(1, _alive(mine).size() - 1),
		"перехватили %d из %d" % [intercepted, _alive(mine).size()])

	for u in mine + foes + wall:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. ПРИКАЗ ИГРОКА ВЫВОДИТ БОЙЦА ИЗ СВАЛКИ ТЕЛОМ, А НЕ ТОЛЬКО ВНИМАНИЕМ
#
# ЖАЛОБА ВЛАДЕЛЬЦА: «отряд в плотной рубке не идёт с первого правого клика,
# приходится кликать второй раз». Блок B этого не ловит: там противник стоит
# ОДНОЙ шеренгой с одной стороны, и вбок боец уходит свободно. Здесь боец
# ОКРУЖЁН — враги вокруг него кольцом, — и шаг упирается в чужие тела с любой
# стороны: лобовая составляющая съедается, боковая упирается на втором проходе,
# и _move_blocked выходит, не сдвинув его ни на сантиметр.
#
# Проверяется СВОЙСТВО, а не число кадров: сдвинулся ли боец с места за секунду
# после ОДНОГО приказа. И второе свойство — что послабление КОНЕЧНО: приказ,
# отданный не игроком (внутренние механики), тел не проходит
# ═════════════════════════════════════════════════════════════════════════════
func _d_surrounded() -> void:
	print("\n═════ D. ПРИКАЗ ИЗ ОКРУЖЕНИЯ ═════")
	var at := Vector3(-300, 0, 300)
	var me: Unit = _new("spearman", Constants.FACTION_PLAYER, at)
	# Кольцо врагов вплотную: радиус берём от личного круга бойца, а не числом —
	# иначе стенд разъедется с SEP_MIN_DIST при первой же правке плотности
	var r: float = Unit.SEP_MIN_DIST * 0.9
	var ring: Array = []
	for i in range(8):
		var ang: float = TAU * float(i) / 8.0
		var foe: Unit = _new("spearman", Constants.FACTION_ENEMY,
			at + Vector3(cos(ang), 0.0, sin(ang)) * r)
		# ── КОЛЬЦО НЕ БЬЁТ, А ТОЛЬКО СТОИТ ТЕЛАМИ ──────────────────────────
		# Проверяется ПРОХОДИМОСТЬ, а не выживание: восемь копейщиков убивают
		# одного за полсекунды, и стенд мерил бы, успел ли он умереть, а не
		# сдвинулся ли он с места. Урон снимаем, тела остаются
		foe.attack_damage = 0.0
		ring.append(foe)
	await frames(6)
	# Боец в бою: цель назначена, он в контакте
	me.command_attack(ring[0], false)
	await frames(20)
	var before: Vector3 = me.global_position
	# ОДИН приказ, и именно ПРИКАЗ ИГРОКА (player_order = true) — только он
	# взводит замок FORCED_MOVE_SEC, от которого и считается послабление
	var goal := at + Vector3(0.0, 0.0, -40.0)
	me.command_move(goal, false, Vector3.ZERO, false, true)
	verdict("D1 приказ принят: цель снята, состояние MOVING",
		me.attack_target == null and me.state == Unit.State.MOVING,
		"цель=%s состояние=%d" % [str(me.attack_target), me.state])
	for _i in range(60):
		await get_tree().physics_frame
	var moved: float = Vector2(me.global_position.x - before.x,
		me.global_position.z - before.z).length()
	# ── РЕШЕНИЕ ВЛАДЕЛЬЦА (03.09.2026): СТРОЙ МОНОЛИТЕН, СКВОЗЬ ТЕЛА НЕ
	# ВЫХОДИТ НИКТО ──────────────────────────────────────────────────────
	# Билет прохода не снимает чужие тела, а сужает их до ядра
	# (Unit.PASS_CORE_FRAC = 0.55 → 0.30 м), и пройти между двумя телами можно
	# только в просвет шире ДВУХ ядер. Соседи этого кольца стоят в
	# 2·r·sin(π/8) = 0.29 м — теснее, чем шеренга в бою (0.33), — и выход из
	# такого кольца означал бы проход сквозь фалангу. Требование «из свалки с
	# первого клика» владелец снял в пользу монолитной фаланги; прежний
	# вердикт (moved > 1.0) утверждал снятое требование. Теперь стенд
	# стережёт ОБЕ стороны решения: сквозь плотное кольцо не выйти (D2a), а
	# из кольца с просветом шире двух ядер — выйти (D2b), то есть билет
	# по-прежнему работает там, где ему положено
	var gap: float = 2.0 * r * sin(PI / 8.0)
	var core: float = Unit.BLOCK_RADIUS * Unit.PASS_CORE_FRAC
	verdict("D2a сквозь плотное кольцо (просвет < 2 ядер) НЕ выходит — строй монолитен",
		moved < 0.5 and gap < 2.0 * core,
		"прошёл %.2f м за секунду; просвет %.3f м, ядро %.3f м" % [moved, gap, core])
	# И послабление кончается вместе с замком: боец не превращается в призрака
	for _i in range(240):
		await get_tree().physics_frame
	verdict("D3 послабление КОНЕЧНО — замок приказа истёк",
		not me._forced_move_pass(),
		"остаток замка %.2f с" % me._move_lock)
	for u in ring:
		if is_instance_valid(u): (u as Node).queue_free()
	if is_instance_valid(me): (me as Node).queue_free()
	await frames(3)

	# ── D2b: ИЗ РЕДКОГО КОЛЬЦА (просвет шире двух ядер) БИЛЕТ ВЫВОДИТ ─────
	var at2 := Vector3(-300, 0, 340)
	var me2: Unit = _new("spearman", Constants.FACTION_PLAYER, at2)
	# Радиус подобран так, чтобы просвет между соседями был шире двух ядер с
	# запасом: 2·r2·sin(π/8) = 2·core·1.3
	var r2: float = (2.0 * core * 1.3) / (2.0 * sin(PI / 8.0))
	var ring2: Array = []
	for i in range(8):
		var ang2: float = TAU * float(i) / 8.0
		var foe2: Unit = _new("spearman", Constants.FACTION_ENEMY,
			at2 + Vector3(cos(ang2), 0.0, sin(ang2)) * r2)
		foe2.attack_damage = 0.0
		ring2.append(foe2)
	await frames(6)
	me2.command_attack(ring2[0], false)
	await frames(20)
	var before2: Vector3 = me2.global_position
	me2.command_move(at2 + Vector3(0.0, 0.0, -40.0), false, Vector3.ZERO, false, true)
	# «Вышел» — это ПОЛОЖЕНИЕ, а не пройденная длина: на прямом пути к цели
	# стоит тело кольца (угол 270°), и боец обходит его скольжением под
	# билетом, теряя на этом путь (замер: 0.72 м за первую секунду). Через две
	# секунды он обязан быть СНАРУЖИ кольца
	for _i in range(120):
		await get_tree().physics_frame
	var moved2: float = Vector2(me2.global_position.x - before2.x,
		me2.global_position.z - before2.z).length()
	var out2: float = Vector2(me2.global_position.x - at2.x, me2.global_position.z - at2.z).length()
	var gap2: float = 2.0 * r2 * sin(PI / 8.0)
	verdict("D2b из редкого кольца (просвет > 2 ядер) с ПЕРВОГО приказа выходит",
		out2 > r2 + 0.3, "через 2 с в %.2f м от центра кольца (радиус %.2f), прошёл %.2f м; просвет %.3f м, ядро %.3f м" % [
			out2, r2, moved2, gap2, core])
	for u in ring2:
		if is_instance_valid(u): (u as Node).queue_free()
	if is_instance_valid(me2): (me2 as Node).queue_free()
	await frames(3)
