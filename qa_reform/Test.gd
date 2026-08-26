extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СМЫКАНИЕ СТРОЯ ПОСЛЕ ПРОХОДА СОЮЗНИКА И ЗНАМЯ ОРДЫ
## ═══════════════════════════════════════════════════════════════════════════
##   A ПРОХОД  — союзный отряд раздвигает строй; строй обязан сомкнуться сам
##   B ЗНАМЯ   — знамёна орды не плодятся, не сиротеют и не отстают от хозяина
##   C ЛАГЕРЬ  — приказ снести постройки не слетает после первой и не разгоняет
##               отряд по карте
##   D РАБОЧИЙ — строй не касается рабочего и не сбивает ему работу
##
## ОБА БЛОКА ВЫРОСЛИ ИЗ ЖАЛОБ, И ОБА СТЕРЕГУТ УЖЕ ДОПУЩЕННЫЕ ОШИБКИ:
##   • порог смыкания стоял ВЫШЕ того, что делает проход (1.6 м против 1.13 м),
##     а зонд оценивал долю по выборке и промахивал узкий коридор;
##   • «синие флажки в полях» оказались не утечкой узлов ДВАЖДЫ: сперва
##     знаменосцем на ободе толпы (стережёт B3), потом замершей нарисованной
##     точкой бойца под пеленой (стережёт B7). Число узлов при обеих жалобах
##     было верным — это и стережёт B4, чтобы не чинить утечку, которой нет.
##
## Числа не хардкодятся: пороги читаются из GameManager и Unit.
## Запуск: godot --headless --path . res://qa_reform/Test.tscn

var main = null
var sm = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func pf(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Съезд бойцов от своих постов: [худший, сколько дальше порога, живых]
func _drift(men: Array) -> Array:
	var worst := 0.0
	var off := 0
	var live := 0
	for m in men:
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		live += 1
		if not u._post_valid:
			continue
		var d: float = Vector2(u.global_position.x - u.post_pos.x,
			u.global_position.z - u.post_pos.z).length()
		worst = maxf(worst, d)
		if d > GameManager.REFORM_DRIFT:
			off += 1
	return [worst, off, live]

## Сколько узлов-знамён висит в дереве мира
func _banner_nodes() -> int:
	var scr = load("res://scripts/SquadBanner.gd")
	var n := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for ch in node.get_children():
			stack.append(ch)
		if node is MeshInstance3D and node.get_script() == scr:
			n += 1
	return n

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pf(4)

	await _a_pass_through()
	await _b_banner()
	await _c_camp()
	await _d_worker()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 64), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== REFORM TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ПРОХОД СОЮЗНИКА СКВОЗЬ СТРОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _a_pass_through() -> void:
	print("\n═════ A. ПРОХОД СОЮЗНИКА ═════")
	var base := Vector3(-700.0, 0.0, -700.0)
	var wall_sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var wall: Array = []
	for i in range(24):
		var u := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER,
			base + Vector3(float(i % 12) * 0.7, 0.0, float(i / 12) * 0.7))
		GameManager.add_to_squad(wall_sid, u)
		wall.append(u)
	await pf(4)
	sm._clear_selection()
	for u2 in wall:
		sm._select(u2)
	await pf(2)
	# Настоящий строевой приказ — так у отряда появляется разметка, как в игре
	sm._execute_line_formation(base + Vector3(-6.0, 0.0, 0.0),
		base + Vector3(6.0, 0.0, 0.0))
	for _i in range(900):
		var mv := 0
		for u3 in wall:
			if (u3 as Unit).state == Unit.State.MOVING:
				mv += 1
		if mv == 0:
			break
		await pf(1)
	sm._clear_selection()
	await pf(30)
	var d0 := _drift(wall)
	verdict("A1 строй встал по своим местам", int(d0[1]) == 0,
		"худший съезд %.2f м, дальше порога %.2f м: %d из %d" % [
			float(d0[0]), GameManager.REFORM_DRIFT, int(d0[1]), int(d0[2])])
	verdict("A2 у отряда есть разметка строя",
		(GameManager.squads[wall_sid]["slots"] as Array).size() == wall.size(),
		"мест %d на %d бойцов" % [
			(GameManager.squads[wall_sid]["slots"] as Array).size(), wall.size()])

	# СОЮЗНЫЕ ЛУЧНИКИ ИДУТ НАСКВОЗЬ
	var arch_sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var arch: Array = []
	for i in range(20):
		var a := _spawn("res://scenes/units/Archer.tscn", Constants.FACTION_PLAYER,
			base + Vector3(float(i % 5) * 0.7 - 1.5, 0.0, -10.0 + float(i / 5) * 0.7))
		GameManager.add_to_squad(arch_sid, a)
		arch.append(a)
	await pf(4)
	sm._clear_selection()
	for a2 in arch:
		sm._select(a2)
	await pf(2)
	sm._issue_formation_move(base + Vector3(0.0, 0.0, 10.0), false)
	sm._clear_selection()
	await pf(600)          # лучники прошли насквозь и ушли
	await pf(360)          # и время на смыкание
	var d1 := _drift(wall)
	print("  после прохода: худший съезд %.2f м, дальше порога %.2f м: %d из %d" % [
		float(d1[0]), GameManager.REFORM_DRIFT, int(d1[1]), int(d1[2])])
	# ГЛАВНОЕ УТВЕРЖДЕНИЕ СТЕНДА
	verdict("A3 после прохода союзника строй сомкнулся сам", int(d1[1]) == 0,
		"дальше порога осталось %d из %d, худший съезд %.2f м" % [
			int(d1[1]), int(d1[2]), float(d1[0])])
	# Порог обязан оставаться в своих границах, иначе смыкание либо не
	# сработает вовсе, либо будет вечно спорить с расталкиванием
	verdict("A4 порог смыкания больше допуска прибытия",
		GameManager.REFORM_DRIFT > Unit.ARRIVE_RADIUS,
		"порог %.2f м при допуске %.2f м" % [
			GameManager.REFORM_DRIFT, Unit.ARRIVE_RADIUS])
	for u4 in wall + arch:
		if is_instance_valid(u4):
			(u4 as Node).queue_free()
	await pf(4)

# ═════════════════════════════════════════════════════════════════════════════
# B. ЗНАМЯ ОРДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _b_banner() -> void:
	print("\n═════ B. ЗНАМЯ ОРДЫ ═════")
	var base := Vector3(-600.0, 0.0, -600.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_spearman")
	var men: Array = []
	for i in range(40):
		# Толпа по золотому углу — тот же строй, каким ходит орда
		var a: float = TAU * 0.381966 * float(i)
		var rr: float = 1.23 * sqrt(float(i)) * 0.9
		var u := _spawn("res://scenes/units/GoblinSpearman.tscn",
			Constants.FACTION_GOBLIN, base + Vector3(cos(a) * rr, 0.0, sin(a) * rr))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	var sq: Dictionary = GameManager.squads[sid]
	sq["level"] = 4
	GameManager.refresh_squad_banner(sid)
	await pf(20)
	var b = sq.get("banner", null)
	verdict("B1 ветеранский отряд орды несёт знамя",
		b != null and is_instance_valid(b), "знамя=%s" % str(b != null))

	# ── B2: ЗНАМЯ НЕ ОТСТАЁТ ОТ ХОЗЯИНА НА МАРШЕ ───────────────────────────
	for m in men:
		(m as Unit).command_move(base + Vector3(30.0, 0.0, 20.0), false)
	await pf(240)
	var br = GameManager.squad_bearer(sid)
	var lag := 999.0
	if br != null and b != null:
		lag = Vector2((b as Node3D).global_position.x - (br as Node3D).global_position.x,
			(b as Node3D).global_position.z - (br as Node3D).global_position.z).length()
	verdict("B2 знамя едет вместе со знаменосцем, а не остаётся в поле",
		lag < 1.5, "отставание %.2f м" % lag)

	# ── B3: ЗНАМЕНОСЕЦ ТОЛПЫ — В СЕРЕДИНЕ, А НЕ НА ОБОДЕ ───────────────────
	# Ради этого блок и написан. «Флажки торчат в полях» оказались знаменем на
	# одиноком гоблине с края толпы: правило «первый ряд, крайний левый» писано
	# под шеренгу, а у орды строя нет вовсе
	var c: Vector3 = GameManager.squad_centroid(sid)
	var from_c := 999.0
	if br != null:
		from_c = Vector2((br as Node3D).global_position.x - c.x,
			(br as Node3D).global_position.z - c.z).length()
	# Радиус толпы считаем по самому дальнему бойцу: порог относительный, чтобы
	# стенд не зависел ни от размера отряда, ни от плотности толпы
	var rmax := 0.0
	for m2 in men:
		var u2 := m2 as Unit
		if u2 == null or not is_instance_valid(u2) or u2.is_dead():
			continue
		rmax = maxf(rmax, Vector2(u2.global_position.x - c.x,
			u2.global_position.z - c.z).length())
	verdict("B3 знаменосец орды идёт в середине толпы, а не по её ободу",
		from_c <= rmax * 0.5,
		"знаменосец в %.1f м от центра при радиусе толпы %.1f м" % [from_c, rmax])

	# ── B4: ОДИН ОТРЯД — ОДНО ЗНАМЯ ────────────────────────────────────────
	var nodes := _banner_nodes()
	var owned := 0
	for key in GameManager.squads.keys():
		var bb = (GameManager.squads[key] as Dictionary).get("banner", null)
		if bb != null and is_instance_valid(bb):
			owned += 1
	verdict("B4 узлов знамён ровно столько, сколько у отрядов (нет бесхозных)",
		nodes == owned, "узлов %d, у отрядов %d" % [nodes, owned])

	# ── B5: ВЫБИТЫЙ ОТРЯД УНОСИТ СВОЙ УЗЕЛ ─────────────────────────────────
	# Знамя при этом остаётся на поле — но уже слотом в слое тел, а не узлом
	for m3 in men:
		if is_instance_valid(m3):
			(m3 as Unit).take_damage(1e9, null)
	await pf(8)
	verdict("B5 после гибели отряда его знамя не остаётся висеть узлом",
		_banner_nodes() == nodes - 1,
		"было узлов %d, стало %d" % [nodes, _banner_nodes()])
	await pf(4)

	# ── B6/B7: ЗНАМЯ НЕ ОСТАЁТСЯ ГОРЕТЬ НА КРОМКЕ ТУМАНА ───────────────────
	# Жалоба владельца со скриншотом: «синий флажок стоит в пустой траве, и там
	# ни одного гоблина». Дубликатов узлов при этом нет (это стережёт B4) —
	# флаг ОДИН и законный, но стоит он не там, где его хозяин.
	#
	# Разбор. Боец под пеленой снимается с отрисовки и выходит из tick_visual
	# РАНЬШЕ, чем обновит свою нарисованную точку: draw_position() у него
	# ЗАМИРАЕТ на месте последнего появления. Знамя ехало по этой точке и по ней
	# же спрашивало туман — то есть спрашивало «освещено ли место, где хозяин
	# когда-то был». Орда уходит в темноту, армия игрока наступает и освещает её
	# вчерашнюю кромку — над пустой травой загорается флаг.
	#
	# ПОРЯДОК ДЕЙСТВИЙ В СТЕНДЕ ЗНАЧИМ, и первая его версия была неверной.
	# Мало увести орду в темноту: пока действует отсрочка FOG_HIDE_GRACE, боец
	# ещё тикает и честно переносит свою нарисованную точку ЗА собой — то есть
	# замирает она уже в темноте, и знамя гаснет само собой. Жалоба владельца
	# описывает другой порядок:
	#   1) орду видели ЗДЕСЬ (нарисованная точка — здесь);
	#   2) свет ушёл, орда под пеленой ушла отсюда — точка осталась ЗДЕСЬ;
	#   3) армия игрока НАСТУПИЛА и осветила это место снова.
	# На третьем шаге старый код и зажигал знамя над пустой травой.
	var fog_was: bool = GameManager.fog != null and GameManager.fog.enabled
	if GameManager.fog != null:
		GameManager.fog.enabled = true
	# ТОЧКА В ГРАНИЦАХ КАРТЫ: маска тумана покрывает только её, и вне карты
	# is_lit отвечает «темно» всегда — стенд мерил бы не туман, а свой промах
	var lit := Vector3(-112.0, 0.0, 58.0)
	var eye := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, lit + Vector3(3.0, 0.0, 0.0))
	var sid2: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_spearman")
	var horde: Array = []
	for i in range(12):
		var g := _spawn("res://scenes/units/GoblinSpearman.tscn",
			Constants.FACTION_GOBLIN,
			lit + Vector3(float(i % 4) * 0.8, 0.0, float(i / 4) * 0.8))
		GameManager.add_to_squad(sid2, g)
		horde.append(g)
	(GameManager.squads[sid2] as Dictionary)["level"] = 5
	GameManager.refresh_squad_banner(sid2)
	if GameManager.fog != null:
		GameManager.fog.refresh()
	await pf(30)
	var b2 = (GameManager.squads[sid2] as Dictionary).get("banner", null)
	var lit_ok: bool = b2 != null and is_instance_valid(b2) and (b2 as MeshInstance3D).visible
	var br1 = GameManager.squad_bearer(sid2)
	var diag := "знаменосца нет"
	if br1 != null:
		var bu := br1 as Unit
		diag = "рисуется=%s, освещён=%s" % [str(bu.is_drawn()),
			str(GameManager.fog_lit_at(bu.global_position.x, bu.global_position.z))]
	verdict("B6 на свету знамя орды видно", lit_ok,
		"видимо=%s, %s" % [str(lit_ok), diag])

	# ШАГ 1. Свет уходит: глаз уезжает на другой край карты. Орда стоит на
	# месте, гаснет по истечении отсрочки — и её нарисованная точка замирает
	# ЗДЕСЬ, на освещаемом впоследствии месте
	var away := Vector3(100.0, 0.0, -58.0)
	eye.global_position = Vector3(away.x, GameManager.get_terrain_height(away.x, away.z), away.z)
	eye.sync_row()
	if GameManager.fog != null:
		GameManager.fog.refresh()
	await pf(int(Unit.FOG_HIDE_GRACE * 60.0) + 40)

	# ШАГ 2. Под пеленой орда уходит совсем. Тикает она по-прежнему, но из
	# визуального такта выходит рано — нарисованная точка так и остаётся там,
	# где её видели в последний раз
	for g2 in horde:
		var uu := g2 as Unit
		var to: Vector3 = Vector3(-560.0, 0.0, -560.0)
		uu.global_position = Vector3(to.x, GameManager.get_terrain_height(to.x, to.z), to.z)
		uu.sync_row()
	await pf(30)

	# ШАГ 3. АРМИЯ ИГРОКА НАСТУПАЕТ и освещает вчерашнюю кромку
	eye.global_position = Vector3(lit.x + 3.0,
		GameManager.get_terrain_height(lit.x + 3.0, lit.z), lit.z)
	eye.sync_row()
	if GameManager.fog != null:
		GameManager.fog.refresh()
	await pf(30)
	var shown: bool = b2 != null and is_instance_valid(b2) and (b2 as MeshInstance3D).visible
	var gap := 0.0
	var br2 = GameManager.squad_bearer(sid2)
	if shown and br2 != null:
		gap = Vector2((b2 as Node3D).global_position.x - (br2 as Node3D).global_position.x,
			(b2 as Node3D).global_position.z - (br2 as Node3D).global_position.z).length()
	# Требование-СВОЙСТВО: видимое знамя стоит НА своём знаменосце. Погашенное
	# знамя ему удовлетворяет тоже — рисовать нечего
	verdict("B7 знамя ушедшего под пелену отряда не горит на его прежнем месте",
		(not shown) or gap <= 2.0,
		"видимо=%s, до знаменосца %.1f м" % [str(shown), gap])
	for g3 in horde:
		if is_instance_valid(g3):
			(g3 as Unit).take_damage(1e9, null)
	if is_instance_valid(eye):
		(eye as Unit).take_damage(1e9, null)
	if GameManager.fog != null:
		GameManager.fog.enabled = fog_was
	await pf(6)

# ═════════════════════════════════════════════════════════════════════════════
# C. ЛАГЕРЬ ПОСТРОЕК
# ═════════════════════════════════════════════════════════════════════════════
# Жалоба владельца: «отряды сносят одно здание, после чего приказ слетает, и они
# разбегаются в разные стороны».
#
# Причин было две, и обе стерегутся здесь:
#   • замок держался за КОНКРЕТНЫЙ узел — павший дом не оставлял следующей цели;
#   • ПОВОДОК ПОГОНИ (7 м) рвался на пути к соседнему дому, снимал замок и гнал
#     бойца на пост — а пост остался там, откуда отряд вышел.
func _c_camp() -> void:
	print("\n═════ C. ЛАГЕРЬ ПОСТРОЕК ═════")
	var camp := Vector3(-620.0, 0.0, -620.0)
	var huts: Array = []
	for i in range(3):
		var h = load("res://scripts/goblin/GoblinHut.gd").new()
		h.faction = Constants.FACTION_GOBLIN
		main.world_add(h)
		h.global_position = camp + Vector3(float(i) * 7.0, 0.0, 0.0)
		huts.append(h)
	await pf(8)
	# Пост отряда ЗАВЕДОМО в стороне: именно туда его и утаскивало
	var home := camp + Vector3(0.0, 0.0, -40.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "warrior")
	var men: Array = []
	for i in range(16):
		var u := _spawn("res://scenes/units/Warrior.tscn", Constants.FACTION_PLAYER,
			home + Vector3(float(i % 4) * 0.8, 0.0, float(i / 4) * 0.8))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pf(6)
	for u1 in men:
		(u1 as Unit).command_move(home, false, Vector3.ZERO, false, true)
	await pf(120)
	var post: Vector3 = (men[0] as Unit).post_pos
	for u2 in men:
		(u2 as Unit).command_attack(huts[0], true, true, true)
	# Ждём, пока лагерь снесут (или пока не кончится терпение стенда)
	var alive := 3
	for _i in range(2400):
		await pf(1)
		alive = 0
		for h2 in huts:
			if is_instance_valid(h2) and not (h2 as Building).is_dead():
				alive += 1
		if alive == 0:
			break
	verdict("C1 отряд снёс ВЕСЬ лагерь, а не одну постройку", alive == 0,
		"осталось построек %d из 3" % alive)
	await pf(180)
	var c: Vector3 = GameManager.squad_centroid(sid)
	var to_camp: float = Vector2(c.x - camp.x, c.z - camp.z).length()
	var to_post: float = Vector2(c.x - post.x, c.z - post.z).length()
	print("  после сноса: центр отряда в %.0f м от лагеря и в %.0f м от старого поста"
		% [to_camp, to_post])
	verdict("C2 отряд остался НА МЕСТЕ, а не ушёл на старый пост",
		to_camp < to_post, "до лагеря %.0f м, до поста %.0f м" % [to_camp, to_post])
	# И не рассыпался
	var far := 0.0
	for u3 in men:
		if is_instance_valid(u3):
			far = maxf(far, Vector2((u3 as Node3D).global_position.x - c.x,
				(u3 as Node3D).global_position.z - c.z).length())
	verdict("C3 отряд не разбежался кусками", far < 12.0,
		"самый дальний в %.1f м от центра" % far)
	for u4 in men:
		if is_instance_valid(u4):
			(u4 as Node).queue_free()
	await pf(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. РАБОЧИЙ
# ═════════════════════════════════════════════════════════════════════════════
# Жалоба владельца: «рабочие доходят до объекта, делают пару процентов работы,
# сбрасывают команду и начинают толкаться». Причина была в возврате в строй: он
# слал command_move ОТДЕЛЬНЫМ бойцам, а рабочий числится отрядом из одного
# человека — и command_move сбрасывает ему и рубку, и стройку, и добычу.
func _d_worker() -> void:
	print("\n═════ D. РАБОЧИЙ ═════")
	verdict("D1 обход строя рабочих не касается",
		GameManager.REFORM_SKIPS_WORKERS,
		"признак в GameManager")
	var w: Unit = load("res://scenes/units/Worker.tscn").instantiate()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = Vector3(-560.0, GameManager.get_terrain_height(-560.0, -560.0), -560.0)
	var wsid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "worker")
	GameManager.add_to_squad(wsid, w)
	await pf(6)
	# Даём отряду рабочего разметку — раньше именно она и открывала дорогу
	# смыканию: сложись она у рабочего, и command_move сбил бы ему работу
	(GameManager.squads[wsid] as Dictionary)["slots"] = [w.global_position]
	# Отправляем рубить
	var tree_node: ResourceNode = null
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(n) and (n as ResourceNode).resource_type == Constants.RESOURCE_WOOD:
			tree_node = n
			break
	if tree_node == null:
		print("  дерева на карте не нашлось — D2 пропущена")
	else:
		w.command_gather(tree_node)
		await pf(600)
		var st: int = w.state
		var has_job: bool = w.get("gather_target") != null
		print("  рабочий: состояние %d, цель добычи %s" % [st, str(has_job)])
		verdict("D2 рабочий не потерял работу за десять секунд", has_job,
			"состояние %d, цель %s" % [st, str(has_job)])
	if is_instance_valid(w):
		w.queue_free()
	await pf(4)
