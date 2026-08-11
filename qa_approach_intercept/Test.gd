extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПРЯМОЙ ПРИКАЗ АТАКИ, А ПО ПУТИ — ЧУЖОЙ ЗАСЛОН (пункт 2б жалобы)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба игрока: приказываю отряду атаковать дальнюю вражескую цель — по
## дороге натыкаемся на ДРУГОЙ вражеский отряд, и вместо того чтобы сцепиться
## с ним и добить, а потом идти дальше к исходной цели, отряд "три шага вперёд,
## разворот, бег назад, снова вперёд" либо просто трётся вдоль чужого строя,
## ни разу не ударив.
##
## Это ПРОВЕРКА, а не заведомо рабочий сценарий: механизм "заслон -> добить ->
## продолжить марш" (_march_pending/_resume_march, см. Unit.gd) подключён
## только к обычному command_move → авто-перехвату в _process_move. Прямой
## command_attack(forced=true) ЯВНО гасит _march_pending (см. комментарий
## "ПРЯМОЙ ПРИКАЗ ОТМЕНЯЕТ НЕЗАКОНЧЕННЫЙ МАРШ") и ведёт бойца к цели через
## _process_attack (dist > attack_range → _flank_step/_move_blocked), а этот
## путь НЕ читает _enemy_contact и не подбирает блокирующий отряд как новую
## цель. Стенд должен эмпирически показать, воюет ли отряд с заслоном вообще.
##
## Запуск: godot --headless --path . res://qa_approach_intercept/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## physics_frame, а не process_frame: при Engine.max_fps=0 рендер может тикать
## быстрее фиксированных 60 Гц физики, и "N process_frame" перестаёт значить
## "N/60 сек игрового времени" (см. qa_combat_lock — там это дало ложный провал)
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
		var p := center + Vector3(float(i % 5) * 0.6, 0.0, float(i / 5) * 0.6)
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

func _hp_lost(arr: Array) -> float:
	var lost: float = 0.0
	for u in arr:
		if is_instance_valid(u):
			var un: Unit = u
			lost += maxf(0.0, un.max_health - un.current_health)
	return lost

func _centroid_z(arr: Array) -> float:
	var alive := _alive(arr)
	if alive.is_empty():
		return -1.0
	var z: float = 0.0
	for u in alive:
		z += (u as Unit).global_position.z
	return z / float(alive.size())

func _run() -> void:
	seed(11)
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
	print("║  ПРЯМОЙ ПРИКАЗ АТАКИ + ЗАСЛОН НА ПУТИ                              ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	var p0 := Vector3(0, 0, 0)
	var men  := _squad("spearman", Constants.FACTION_PLAYER, p0, 6)
	var block := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0, 0, 8.0), 6)
	var goal  := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0, 0, 25.0), 4)

	# ПРЯМОЙ ПРИКАЗ ПО ОТРЯДУ на ДАЛЬНУЮ цель (goal), с "боевым навалом"
	# (charge = true — как ПКМ игрока), а не авто-агро
	for i in range(men.size()):
		var u: Unit = men[i]
		u.command_attack(goal[i % goal.size()], true, true)
	await frames(3)

	var engaged := 0
	for u in men:
		if (u as Unit).attack_target != null:
			engaged += 1
	verdict("0 весь отряд принял приказ атаки дальней цели (подготовка)",
		engaged == men.size(), "приняли %d из %d" % [engaged, men.size()])

	# Наблюдаем длительный марш: заслон стоит в 8 м, цель — в 25 м.
	# Эффективная скорость на марше у копейщика ~1.0 м/с (см. _effective_speed,
	# march ×0.5 от 2.0 м/с) — 3000 кадров (50 сек симуляции) с большим запасом
	# покрывают и подход к заслону, и любой возможный бой с ним, и добивание цели
	const SAMPLE_EVERY := 120   # раз в ~2 сек
	const TOTAL_FRAMES := 6000
	var samples: Array = []
	var frames_done := 0
	var block_engaged_ever := false
	var retreat_events := 0
	var prev_z := _centroid_z(men)
	var max_z_seen := prev_z

	while frames_done < TOTAL_FRAMES:
		var step: int = mini(SAMPLE_EVERY, TOTAL_FRAMES - frames_done)
		await frames(step)
		frames_done += step
		if _alive(men).is_empty():
			break
		var z := _centroid_z(men)
		samples.append(z)
		print("  t=%ds  z-отряда=%.2f  урон-заслону=%.0f  урон-цели=%.0f  живых-заслон=%d  живых-цель=%d"
			% [frames_done / 60, z, _hp_lost(block), _hp_lost(goal), _alive(block).size(), _alive(goal).size()])
		if _hp_lost(block) > 0.5:
			block_engaged_ever = true
		# ОТКАТ НАЗАД: центр отряда откатился больше чем на метр относительно
		# максимума, хотя приказ прямой и retreating никто не выставлял —
		# ровно "3 шага вперёд, назад" из жалобы игрока
		if z > max_z_seen:
			max_z_seen = z
		elif max_z_seen - z > 1.0:
			retreat_events += 1
			print("    (!) откат: было %.2f, максимум был %.2f" % [z, max_z_seen])
		prev_z = z
		if _alive(goal).is_empty():
			break

	verdict("1 заслон получил урон (отряд сцепился с ним, а не прошёл насквозь)",
		block_engaged_ever, "суммарный урон заслону: %.0f" % _hp_lost(block))
	verdict("2 исходная цель в итоге атакована/уничтожена",
		_alive(goal).size() < goal.size() or _hp_lost(goal) > 0.0,
		"живых в исходной цели: %d из %d, урон: %.0f" % [_alive(goal).size(), goal.size(), _hp_lost(goal)])
	verdict("3 без откатов назад по пути (без 'три шага вперёд-назад')",
		retreat_events == 0, "случаев отката: %d" % retreat_events)

	for u in men + block + goal:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %-58s%s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== APPROACH INTERCEPT TEST DONE ===")
	get_tree().quit()
