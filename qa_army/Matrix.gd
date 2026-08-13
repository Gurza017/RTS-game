extends Node

## ЭТАП 1, СЛОЙ ДАННЫХ: МАТРИЧНЫЙ ШАГ ОТРЯДА.
##
## Проверяется сама геометрия, в изоляции от игры: строй, посчитанный как
## «якорь + повёрнутое смещение», обязан сохранять форму при любом курсе и
## совпадать с прямым построением по тем же слотам. Переключатель режима в
## Unit ставится следующим шагом — сначала это должно быть зелёным.
##
## Запуск: godot --headless --path . res://qa_army/Matrix.tscn

const _Army := preload("res://scripts/army/ArmySoA.gd")

var _fail := 0
var _checks := 0

func _ready() -> void:
	call_deferred("_run")

func ok(name: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fail += 1
	print("  [%s] %s%s" % ["OK " if cond else "НЕ ПРОШЛО", name,
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	var a = _Army.new()
	# Строй: 5 в ряд, 4 шеренги, шаг 0.9 м. Смещения — от центра квадрата
	var rows := PackedInt32Array()
	var want_off: Array = []
	for r in range(4):
		for c in range(5):
			var i: int = a.alloc()
			var ox: float = (float(c) - 2.0) * 0.9
			var oz: float = (float(r) - 1.5) * 0.9
			a.set_slot(i, ox, oz)
			rows.append(i)
			want_off.append(Vector2(ox, oz))

	print("\n───── A. СТРОЙ СОБИРАЕТСЯ ПО ЯКОРЮ И КУРСУ ─────")
	# Курс «на север»: локальная Z совпадает с мировой Z
	var n: int = a.advance_matrix(rows, 10.0, 20.0, 1.0, 0.0, 1.0)
	ok("A1 расставлены все", n == rows.size(), "%d из %d" % [n, rows.size()])
	var worst := 0.0
	for k in range(rows.size()):
		var i: int = rows[k]
		var o: Vector2 = want_off[k]
		# При курсе (0,1) вбок = (1,0): x = ax + ox, z = az + oz
		var d: float = Vector2(a.px[i] - (10.0 + o.x), a.pz[i] - (20.0 + o.y)).length()
		if d > worst:
			worst = d
	ok("A2 при курсе на север смещения ложатся один в один", worst < 1e-4,
		"худшее расхождение %.6f" % worst)
	ok("A3 высота взята от якоря", is_equal_approx(a.py[rows[0]], 1.0))
	ok("A4 координата помечена настоящей", a.pos_ready(rows[0]))

	# КОПИЯ ФОРМУЛЫ РЕЛЬЕФА. Внутри матричного шага высота считается по колонкам,
	# без вызова наружу на каждого бойца, — то есть три гармоники Main.get_terrain_height
	# продублированы в ArmySoA.advance_matrix. Дубль обязан совпадать с оригиналом:
	# разойдясь, он бесшумно посадит отряд под землю или подвесит над ней
	var amp: float = 0.85          # Main.RELIEF_AMP
	a.advance_matrix(rows, 12.0, -37.0, 0.0, 0.0, 1.0, amp)
	var worst_h := 0.0
	for k in range(rows.size()):
		var i: int = rows[k]
		var want: float = amp * (
			  0.55 * sin(a.px[i] * 0.031 + a.pz[i] * 0.017)
			+ 0.30 * sin(a.px[i] * 0.013 - a.pz[i] * 0.041 + 1.7)
			+ 0.15 * sin(a.px[i] * 0.077 + a.pz[i] * 0.059 + 3.1))
		worst_h = maxf(worst_h, absf(a.py[i] - want))
	ok("A5 высота считается поунитно по формуле рельефа", worst_h < 1e-5,
		"худшее расхождение %.7f м" % worst_h)
	# И она обязана РАЗЛИЧАТЬСЯ внутри строя — иначе проверка выше сошлась бы
	# на плоскости и ничего не значила
	var hmin := INF
	var hmax := -INF
	for k in range(rows.size()):
		hmin = minf(hmin, a.py[rows[k]])
		hmax = maxf(hmax, a.py[rows[k]])
	ok("A6 высота внутри строя различается (проверка не вырождена)",
		hmax - hmin > 0.005, "разброс по строю %.4f м" % (hmax - hmin))

	print("\n───── B. ПОВОРОТ НЕ ЛОМАЕТ ФОРМУ ─────")
	# Форма строя — это ВСЕ попарные расстояния. Они обязаны сохраняться при
	# любом курсе: строй поворачивается целиком, а не деформируется
	var base: Array = []
	a.advance_matrix(rows, 0.0, 0.0, 0.0, 0.0, 1.0)
	for k in range(rows.size()):
		base.append(Vector2(a.px[rows[k]], a.pz[rows[k]]))
	var worst_shape := 0.0
	for ang in [0.3, 1.1, 2.4, -0.8, PI]:
		var cx: float = sin(ang)
		var cz: float = cos(ang)
		a.advance_matrix(rows, -30.0, 45.0, 0.0, cx, cz)
		for p in range(rows.size()):
			for q in range(p + 1, rows.size()):
				var d_now: float = Vector2(
					a.px[rows[p]] - a.px[rows[q]],
					a.pz[rows[p]] - a.pz[rows[q]]).length()
				var d_was: float = (base[p] as Vector2).distance_to(base[q])
				var err: float = absf(d_now - d_was)
				if err > worst_shape:
					worst_shape = err
	ok("B1 попарные расстояния сохраняются при любом курсе", worst_shape < 1e-3,
		"худшее искажение %.6f м" % worst_shape)

	print("\n───── C. ЯКОРЬ ДВИГАЕТ ВЕСЬ ОТРЯД РОВНО НА ШАГ ─────")
	a.advance_matrix(rows, 0.0, 0.0, 0.0, 0.0, 1.0)
	var before: Array = []
	for k in range(rows.size()):
		before.append(Vector2(a.px[rows[k]], a.pz[rows[k]]))
	a.advance_matrix(rows, 0.0, 2.5, 0.0, 0.0, 1.0)
	var worst_step := 0.0
	for k in range(rows.size()):
		var moved: float = Vector2(
			a.px[rows[k]] - (before[k] as Vector2).x,
			a.pz[rows[k]] - (before[k] as Vector2).y).length()
		var err: float = absf(moved - 2.5)
		if err > worst_step:
			worst_step = err
	ok("C1 все сдвинулись ровно на шаг якоря", worst_step < 1e-4,
		"худшее отклонение %.6f м" % worst_step)

	print("\n───── D. ЧУЖИЕ СТРОКИ НЕ ЗАДЕТЫ ─────")
	var outsider: int = a.alloc()
	a.set_pos(outsider, 100.0, 0.0, 100.0)
	a.advance_matrix(rows, 5.0, 5.0, 0.0, 1.0, 0.0)
	ok("D1 боец вне отряда остался на месте",
		is_equal_approx(a.px[outsider], 100.0) and is_equal_approx(a.pz[outsider], 100.0))

	print("\n=== МАТРИЦА ОТРЯДА: провалов: %d из %d ===" % [_fail, _checks])
	get_tree().quit(1 if _fail > 0 else 0)
