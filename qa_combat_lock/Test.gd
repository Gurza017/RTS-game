extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ОТРЯД НЕ ВЫХОДИТ ИЗ БОЯ ПОСРЕДИ БОЯ ("ПЛЯСКА ВПЕРЁД-НАЗАД")
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба игрока: убил ОДНОГО бойца во вражеском отряде — весь свой отряд
## срывается "смыкать ряды", включая ещё дерущихся, авто-агро тут же ведёт их
## обратно в бой — отряд пляшет туда-сюда, пока враг не выбит целиком.
##
## Корень (найден по коду, не по догадке): GameManager.squad_close_ranks()
## раньше звалась БЕЗУСЛОВНО каждым бойцом, у которого лично кончился бой
## (_die() при гибели соседа, ЛИБО null-attack_target у самого бойца) —
## независимо от того, дерутся ли ЕЩЁ другие. close_ranks() шлёт command_move
## ВСЕМ живым членам отряда на СТАРЫЕ слоты разметки, а command_move снимает
## живую цель. Фикс: squad_in_combat(sid) — правда, пока жив хоть один личный
## attack_target ИЛИ был урон недавно (RECENT_HIT_WINDOW_MS) — гейтит оба вызова
## (_die() и _process_attack), и слоты при реальном смыкании переносятся на
## ТЕКУЩИЙ центр масс отряда (_slots_recentered), а не на старую точку приказа.
##
## Запуск: godot --headless --path . res://qa_combat_lock/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## physics_frame, А НЕ process_frame: при Engine.max_fps=0 рендер-кадры могут
## тикать намного чаще физики (60 Гц реального времени фиксированно), и тогда
## "подождать N process_frame" перестаёт значить "N/60 сек игрового времени" —
## бо́льшая часть render-кадров проходит вовсе без физ. тика между ними.
## physics_frame жёстко привязан к тику _physics_process, поэтому счётчик
## кадров надёжно соответствует игровому времени независимо от скорости рендера
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	return u

func _squad(kind: String, fac: int, center: Vector3, count: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(count):
		var p := center + Vector3(float(i % 4) * 0.7, 0.0, float(i / 4) * 0.7)
		var u := _new(kind, fac, p)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _centroid(arr: Array) -> Vector3:
	var alive := _alive(arr)
	if alive.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for u in alive:
		c += (u as Unit).global_position
	return c / float(alive.size())

func _squad_id_of(arr: Array) -> int:
	for u in arr:
		if is_instance_valid(u):
			return (u as Unit).squad_id
	return 0

func _reshuffled_ms(sid: int) -> int:
	if not GameManager.squads.has(sid):
		return 0
	return int((GameManager.squads[sid] as Dictionary).get("reshuffled", 0))

func _run() -> void:
	seed(23)
	Engine.max_fps = 0
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
	print("║  ОТРЯД НЕ ВЫХОДИТ ИЗ БОЯ ПОСРЕДИ БОЯ                               ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	# Бойцы ФИЗИЧЕСКИ стоят у z=0 (реальное место боя), но разметка строя
	# (см. squad_set_formation) запоминается ТАК, как будто отряд шёл сюда
	# издалека и его исходная точка приказа — z=-20. Если "смыкание рядов"
	# после победы уводит бойцов НА СТАРУЮ разметку — они окажутся у z=-20,
	# а не у места, где реально закончился бой (проверка ПЕРЕАНКЕРОВКИ)
	var origin := Vector3(0, 0, 0)
	var men  := _squad("spearman", Constants.FACTION_PLAYER, origin, 8)
	var foes := _squad("spearman", Constants.FACTION_ENEMY, origin + Vector3(0, 0, 2.5), 5)

	var sid := _squad_id_of(men)
	var stale_slots: Array = []
	for i in range(men.size()):
		var u: Unit = men[i]
		stale_slots.append(u.global_position + Vector3(0, 0, -20.0))
	GameManager.squad_set_formation(sid, stale_slots, Vector3.BACK, false)

	for i in range(men.size()):
		var u: Unit = men[i]
		u.command_attack(foes[i % foes.size()], true, true)
	await frames(3)

	var engaged := 0
	for u in men:
		if (u as Unit).attack_target != null:
			engaged += 1
	verdict("0 весь отряд принял бой (подготовка)", engaged == men.size(),
		"в бою %d из %d" % [engaged, men.size()])

	# ── ПОКА ХОТЬ КТО-ТО ЖИВ У ВРАГА: смыкание НЕ должно срабатывать ──────────
	const CHECK_EVERY := 30
	const MAX_FRAMES   := 3600
	var frames_done := 0
	var yanked_mid_fight := false
	var last_alive_foes := foes.size()

	while _alive(foes).size() > 0 and frames_done < MAX_FRAMES:
		await frames(CHECK_EVERY)
		frames_done += CHECK_EVERY
		var alive_now := _alive(foes).size()
		if alive_now != last_alive_foes:
			print("  t=%ds  живых во вражеском отряде: %d  живых в своём: %d"
				% [frames_done / 60, alive_now, _alive(men).size()])
			last_alive_foes = alive_now
		if _reshuffled_ms(sid) != 0:
			yanked_mid_fight = true
			print("    (!) squad_close_ranks сработал, пока враг ещё жив (t=%ds)" % (frames_done / 60))
			break

	verdict("1 враг вообще уничтожен (подготовка)", _alive(foes).size() == 0,
		"живых осталось %d из %d" % [_alive(foes).size(), foes.size()])
	verdict("2 смыкание НЕ срабатывало, пока враг был жив",
		not yanked_mid_fight)

	# ── ПОСЛЕ ПОЛНОЙ ПОБЕДЫ: смыкание срабатывает, и на ТЕКУЩЕМ месте ────────
	# squad_mark_hit планирует повтор через РЕАЛЬНЫЕ RECENT_HIT_WINDOW_MS (таймер
	# движка, не счётчик кадров) — при Engine.max_fps=0 в лёгкой сцене кадры
	# летят намного быстрее 60/сек, и фиксированное число await-кадров может
	# кончиться раньше, чем реально пройдут эти 3+ сек. Ждём по РЕАЛЬНЫМ часам
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().physics_frame
	var sq: Dictionary = GameManager.squads.get(sid, {})
	print("  ДИАГНОСТИКА: in_combat=%s last_hit_ms=%s now=%d reform_pending=%s reshuffled=%s"
		% [GameManager.squad_in_combat(sid), sq.get("last_hit_ms", "?"), Time.get_ticks_msec(),
			sq.get("reform_check_pending", "?"), sq.get("reshuffled", "?")])
	for u in men:
		if is_instance_valid(u):
			print("    боец: state=%s attack_target=%s" % [(u as Unit).state, (u as Unit).attack_target])
	verdict("3 смыкание сработало после полной победы",
		_reshuffled_ms(sid) != 0)

	var final_pos := _centroid(men)
	var dist_to_battle: float = final_pos.distance_to(origin)
	var dist_to_stale:  float = final_pos.distance_to(origin + Vector3(0, 0, -20.0))
	verdict("4 отряд перестроился У МЕСТА БОЯ, а не у старой точки приказа",
		dist_to_battle < dist_to_stale,
		"до места боя %.1f м, до старой точки %.1f м" % [dist_to_battle, dist_to_stale])

	for u in men + foes:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %-58s%s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== COMBAT LOCK TEST DONE ===")
	get_tree().quit()
