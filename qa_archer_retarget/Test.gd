extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЛУЧНИКИ ПРОДОЛЖАЮТ БОЙ ПОСЛЕ ГИБЕЛИ ОДНОЙ МОДЕЛИ ЦЕЛИ
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба игрока: "первые 5 стрел вылетают, убивают ОДНОГО вражеского лучника —
## и наш отряд сбрасывает приказ и тупо останавливается". Проверяет, что
## Unit._process_attack() реально подхватывает СЛЕДУЮЩУЮ цель в радиусе сразу
## же (см. код: "После смерти цели добираем СЛЕДУЮЩУЮ в своём радиусе атаки"),
## а не спустя таймер авто-агро, и не останавливается, пока в отряде
## противника остаётся хоть один боец в радиусе поражения.
##
## Запуск: godot --headless --path . res://qa_archer_retarget/Test.tscn

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

func _run() -> void:
	seed(7)
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
	print("║  ЛУЧНИКИ: ОГОНЬ ПО ОТРЯДУ ДО ПОЛНОГО УНИЧТОЖЕНИЯ                  ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	# НАРОЧНО МЕНЬШЕ ВРАГОВ, ЧЕМ СТРЕЛКОВ: squad_pick_member при 6-на-6 развёл
	# бы каждого лучника на свою жертву, и весь отряд полёг бы за одну волну —
	# перенацеливание ни разу не потребовалось бы. При 6 лучниках на 2 врагов
	# несколько стрелков ГАРАНТИРОВАННО делят одну цель и обязаны перенацелиться,
	# когда она умрёт, а враг ещё жив — ровно сценарий жалобы игрока
	var start := Vector3(0, 0, 0)
	var bows := _squad("archer", Constants.FACTION_PLAYER, start, 6)
	var foes := _squad("spearman", Constants.FACTION_ENEMY, start + Vector3(0, 0, 8.0), 2)

	# Приказ ПО ОТРЯДУ (клик по одной модели -> squad_pick_member внутри
	# command_attack, см. GameManager.squad_pick_member): ровно сценарий жалобы
	for i in range(bows.size()):
		var u: Unit = bows[i]
		u.command_attack(foes[i % foes.size()], true)
	await frames(3)

	var engaged := 0
	for u in bows:
		if (u as Unit).attack_target != null:
			engaged += 1
	verdict("0 весь отряд лучников открыл огонь (подготовка)", engaged == bows.size(),
		"в бою %d из %d" % [engaged, bows.size()])

	var waves := 0
	var stuck_events := 0
	const GRACE_FRAMES := 12   # запас на "добор следующей цели" — не таймер авто-агро
	const MAX_WAVES := 8

	while _alive(foes).size() > 0 and waves < MAX_WAVES:
		waves += 1
		# "Стрела долетела и убила" — РОВНО ОДНУ живую жертву за волну (не всех
		# разом): несколько лучников делят её как цель и обязаны перенацелиться
		var alive_now := _alive(foes)
		if alive_now.is_empty():
			break
		var victim: Unit = alive_now[0]
		victim.take_damage(1e6, bows[0])
		print("  волна %d: убита 1 цель, живых во вражеском отряде %d"
			% [waves, _alive(foes).size()])

		# Если во вражеском отряде ещё есть живые в радиусе поражения — ни один
		# стрелок не должен застрять IDLE без цели дольше GRACE_FRAMES
		for _i in range(GRACE_FRAMES):
			await get_tree().physics_frame

		if _alive(foes).size() > 0:
			for u in bows:
				if not is_instance_valid(u) or (u as Unit).is_dead():
					continue
				var un2: Unit = u
				if un2.state == Unit.State.IDLE and un2.attack_target == null:
					stuck_events += 1

	verdict("1 вражеский отряд уничтожен полностью", _alive(foes).size() == 0,
		"осталось живых %d из %d, волн потребовалось %d" % [_alive(foes).size(), foes.size(), waves])
	verdict("2 ни один стрелок не застрял IDLE, пока враг был в радиусе",
		stuck_events == 0, "случаев зависания: %d" % stuck_events)

	for u in bows + foes:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %-58s%s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== ARCHER RETARGET TEST DONE ===")
	get_tree().quit()
