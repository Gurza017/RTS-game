extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СТРОЙ ИИ ВСТАЁТ ПАРАЛЛЕЛЬНО ФРОНТУ ПРОТИВНИКА
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба владельца: отряды ИИ разворачиваются строго по горизонтали или
## вертикали карты, а линия игрока стоит под углом — и подход выходит «углом
## вперёд», когда в бой входят два-три бойца с края, а остальные толпятся.
##
## Причина была не в выборе курса (он считался честно), а в том, что РАЗМЕТКА
## его не читала: смещения складывались прямо по мировым осям X и Z. Стенд
## проверяет обе половины починки:
##   A ФРОНТ  — нормаль к чужой линии находится под любым углом и смотрит НА неё
##   B СЛОТЫ  — места в строю раскладываются по осям строя, а не карты
##   C ОТРЯД  — реальная шеренга ИИ встаёт вдоль реальной шеренги игрока
##   P ФАЛАНГА— в бою «вперёд» у фаланги считается на драку, а не по приказу
##
## Стенд headless и молчит до конца: печатает одну таблицу.

var main: Node = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok, detail])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	await frames(2)

	await _test_front_normal()
	_test_slots()
	await _test_real_squad()
	await _test_phalanx_dir()
	_summary()
	print("\n=== QA_FACING DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ qa_facing ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-58s %s%s" % [String(row[0]),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО",
			("  — " + String(row[2])) if String(row[2]) != "" else ""])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

## Шеренга игрока из n бойцов, вытянутая по направлению dir от точки at
func _player_line(at: Vector3, dir: Vector3, n: int, step: float) -> Array:
	var out: Array = []
	var d := dir.normalized()
	for i in range(n):
		var u := Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = at + d * ((float(i) - float(n - 1) * 0.5) * step)
		u.sync_row()
		out.append(u)
	return out

func _clear(arr: Array) -> void:
	for u in arr:
		if is_instance_valid(u):
			(u as Node).queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# A. НОРМАЛЬ К ЧУЖОЙ ЛИНИИ
# ═════════════════════════════════════════════════════════════════════════════
## Три угла подряд, включая диагональ — ровно тот случай, с которого началась
## жалоба. Требование: нормаль перпендикулярна линии и смотрит НА противника
func _test_front_normal() -> void:
	var ai = main.get("enemy_ai")
	if ai == null:
		verdict("A вожак ИИ доступен стенду", false, "enemy_ai == null")
		return
	var cases := {
		"по оси X":   Vector3(1.0, 0.0, 0.0),
		"по оси Z":   Vector3(0.0, 0.0, 1.0),
		"диагональ":  Vector3(1.0, 0.0, 1.0).normalized(),
	}
	var at := Vector3(-800.0, 0.0, -800.0)
	for name in cases.keys():
		var dir: Vector3 = cases[name]
		var line := _player_line(at, dir, 12, 1.2)
		await pframes(2)
		# Наблюдатель стоит В СТОРОНЕ от линии, по её нормали
		var side := Vector3(-dir.z, 0.0, dir.x)
		var from: Vector3 = at - side * 20.0
		var nrm: Vector3 = ai._enemy_front_normal(at, from)
		var along: float = absf(nrm.dot(dir))
		var toward: float = nrm.dot((at - from).normalized())
		verdict("A %s: нормаль перпендикулярна чужой линии" % name,
			nrm != Vector3.ZERO and along < 0.2,
			"проекция на линию %.3f (ноль — идеальный перпендикуляр)" % along)
		verdict("A %s: нормаль смотрит НА противника, а не от него" % name,
			toward > 0.8, "скалярное произведение %.2f" % toward)
		_clear(line)
		await pframes(2)

	# Толпа, а не шеренга: направления у круглого облака нет, и выдумывать его
	# нельзя — иначе строй разворачивало бы от шума
	var blob: Array = []
	for i in range(16):
		var u := Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var a: float = float(i) * TAU / 16.0
		u.global_position = at + Vector3(cos(a), 0.0, sin(a)) * 4.0
		u.sync_row()
		blob.append(u)
	await pframes(2)
	var nb: Vector3 = ai._enemy_front_normal(at, at - Vector3(0.0, 0.0, 20.0))
	verdict("A4 у круглой толпы фронта нет — угол не выдумывается",
		nb == Vector3.ZERO or absf(nb.length() - 1.0) < 0.01,
		"нормаль %s" % str(nb))
	_clear(blob)
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. МЕСТА В СТРОЮ РАСКЛАДЫВАЮТСЯ ПО ОСЯМ СТРОЯ
# ═════════════════════════════════════════════════════════════════════════════
## Проверяем ровно ту функцию, которой раньше не было вовсе: смещение «поперёк»
## обязано лечь перпендикулярно курсу, смещение «вглубь» — назад по курсу
func _test_slots() -> void:
	var ai = main.get("enemy_ai")
	if ai == null:
		return
	var c := Vector3(100.0, 0.0, 100.0)
	var course := Vector3(1.0, 0.0, 1.0).normalized()
	var across: Vector3 = ai._slot_at(c, course, 3.0, 0.0) - c
	var deep: Vector3 = ai._slot_at(c, course, 0.0, 2.0) - c
	verdict("B1 смещение поперёк перпендикулярно курсу",
		absf(across.normalized().dot(course)) < 0.01,
		"скалярное произведение %.4f" % across.normalized().dot(course))
	verdict("B2 шеренги уходят НАЗАД, а нулевая остаётся передней",
		deep.normalized().dot(course) < -0.99,
		"скалярное произведение %.2f" % deep.normalized().dot(course))
	verdict("B3 длина смещений не искажена поворотом",
		absf(across.length() - 3.0) < 0.01 and absf(deep.length() - 2.0) < 0.01,
		"поперёк %.2f (ждали 3.00), вглубь %.2f (ждали 2.00)"
			% [across.length(), deep.length()])
	# Пустой курс — прежняя раскладка по мировым осям: строй не имеет права
	# схлопнуться в точку, если отряд уже стоит там, куда его послали
	var zero: Vector3 = ai._slot_at(c, Vector3.ZERO, 3.0, 2.0) - c
	verdict("B4 без курса строй не схлопывается в точку",
		absf(zero.x - 3.0) < 0.01 and absf(zero.z - 2.0) < 0.01,
		"смещение %s" % str(zero))

# ═════════════════════════════════════════════════════════════════════════════
# C. ЦЕЛАЯ ШЕРЕНГА ИИ ПРОТИВ ДИАГОНАЛЬНОЙ ШЕРЕНГИ ИГРОКА
# ═════════════════════════════════════════════════════════════════════════════
## Итоговая проверка: собираем настоящие места строя тем же способом, каким их
## раздаёт _issue_plan, и меряем угол получившейся шеренги. Он обязан совпасть
## с углом чужой шеренги, а не с осями карты
func _test_real_squad() -> void:
	var ai = main.get("enemy_ai")
	if ai == null:
		return
	var at := Vector3(-900.0, 0.0, -900.0)
	var dir := Vector3(1.0, 0.0, 1.0).normalized()      # диагональ
	var line := _player_line(at, dir, 14, 1.2)
	await pframes(2)
	var from: Vector3 = at - Vector3(-dir.z, 0.0, dir.x) * 25.0
	var course: Vector3 = ai._enemy_front_normal(at, from)
	if course == Vector3.ZERO:
		verdict("C фронт противника прочитан", false, "нормаль нулевая")
		_clear(line)
		return
	# Первая шеренга: восемь мест поперёк строя
	var cols := 8
	var first: Array = []
	for i in range(cols):
		var off_x: float = (float(i) - float(cols - 1) * 0.5) * 0.5
		first.append(ai._slot_at(at, course, off_x, 0.0))
	var span: Vector3 = (first[cols - 1] as Vector3) - (first[0] as Vector3)
	var along: float = absf(span.normalized().dot(dir))
	verdict("C1 шеренга ИИ легла ВДОЛЬ шеренги игрока", along > 0.98,
		"совпадение направлений %.3f (единица — идеально параллельно)" % along)
	# И проверяем, что это НЕ ось карты: диагональ обязана отличаться от X и Z
	var axis: float = maxf(absf(span.normalized().x), absf(span.normalized().z))
	verdict("C2 строй развернулся, а не лёг по осям карты", axis < 0.95,
		"наибольшая проекция на ось карты %.2f" % axis)
	_clear(line)
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# P. ФАЛАНГА В БОЮ СМОТРИТ НА ДРАКУ, А НЕ ПО СТАРОМУ КУРСУ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца: сцепившаяся фаланга разбредается вперёд, в пустое поле,
## вместо того чтобы повернуться к бою. Причина — «вперёд» у копейщика бралось
## из КУРСА ПОСЛЕДНЕГО ПРИКАЗА (squad_course). Вне боя это правильно: по нему
## считаются ряды и смыкается строй. Но в контакте противник почти никогда не
## стоит ровно на курсе, и незанятые бойцы честно шагали мимо драки.
##
## Проверяем ровно эту развилку: вне боя направление равно курсу, в бою —
## направлению на противника
func _test_phalanx_dir() -> void:
	var at := Vector3(500.0, 0.0, 500.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(6):
		var u := Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = at + Vector3(float(i) * 0.7, 0.0, 0.0)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	# КУРС ПРИКАЗА — на восток. Противник при этом будет СБОКУ, на юге: ровно
	# та геометрия, в которой старый код уводил бойцов мимо драки
	var course := Vector3(1.0, 0.0, 0.0)
	var slots: Array = []
	for i in range(men.size()):
		slots.append(at + Vector3(float(i) * 0.7, 0.0, 0.0))
	GameManager.squad_set_formation(sid, slots, course, false)
	var foes: Array = []
	for i in range(6):
		var e := Spearman.new()
		e.faction = Constants.FACTION_ENEMY
		main.world_add(e)
		e.global_position = at + Vector3(float(i) * 0.7, 0.0, 6.0)
		e.sync_row()
		foes.append(e)
	await pframes(6)

	var probe := men[0] as Unit
	var calm: Vector3 = probe._phalanx_dir()
	verdict("P1 вне боя «вперёд» у фаланги — это курс приказа",
		calm.dot(course) > 0.9,
		"совпадение с курсом %.2f" % calm.dot(course))

	# Отмечаем отряд как ведущий бой тем же способом, каким это делает урон
	GameManager.squad_mark_hit(sid)
	# ОБЩИЙ ВРАГ ОТРЯДА СНИМАЕТСЯ ОДНИМ СКАНОМ, и заказывает его сам боец из
	# своего тика (Unit._update_live_rank → GameManager.squad_enemy_pos).
	# В стенде бойцы стоят без приказа и до этой ветки не доходят, поэтому
	# скан заказываем ровно тем же вызовом, каким его делает живой код
	for _i in range(30):
		await get_tree().physics_frame
		GameManager.squad_mark_hit(sid)
		GameManager.squad_enemy_pos(sid, probe, Unit.AGGRO_RADIUS)
		if GameManager.squad_enemy_dir(sid).length_squared() > 1e-6:
			break
	var shared: Vector3 = GameManager.squad_enemy_dir(sid)
	var hot: Vector3 = probe._phalanx_dir()
	verdict("P2 отряд числится ведущим бой", GameManager.squad_in_combat(sid),
		"в бою: %s" % str(GameManager.squad_in_combat(sid)))
	verdict("P3 в бою «вперёд» повернулось на противника, а не осталось курсом",
		shared.length_squared() > 1e-6 and hot.dot(shared) > 0.9
			and hot.dot(course) < 0.9,
		"на врага %.2f, на курс %.2f" % [hot.dot(shared), hot.dot(course)])

	for u in men + foes:
		if is_instance_valid(u): (u as Node).queue_free()
	await pframes(3)
