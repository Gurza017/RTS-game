extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ПОЛ ПРОИЗВОДИТЕЛЬНОСТИ GDScript: СКОЛЬКО СТОИТ САМ ОБХОД N СУЩНОСТЕЙ
## ═══════════════════════════════════════════════════════════════════════════
## Это НЕ замер игры. Здесь меряется абсолютный нижний предел: во что обойдётся
## кадр, если от юнита не осталось НИЧЕГО, кроме чисел в PackedFloat32Array, и
## работа сведена к минимальной арифметике. Ниже этого числа архитектура
## опуститься не может в принципе — значит, по нему и надо решать, достижима ли
## цель «15000 бойцов при 100-120 кадрах» на GDScript.
##
## Четыре уровня, от самого дешёвого к реалистичному:
##   A. SoA-интеграция позиции      — x += vx*dt; z += vz*dt   (пол пола)
##   B. SoA + ветвление по состоянию + таймеры                 (реалистичный шаг)
##   C. SoA + поиск соседа в плоской сетке (бой/агро, троттлено)
##   D. AoS: массив объектов Node3D, вызов метода на каждом    (текущая схема)
##
## Запуск: godot --headless --path . res://qa_soa_floor/Test.tscn
##         ... -- --count=15000

const DEFAULT_COUNT := 15000
const ITERS := 40          ## сколько раз повторить каждый замер

var _n: int = DEFAULT_COUNT
var _rows: Array = []

func _ready() -> void:
	call_deferred("_run")

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--count="):
			var v := int(s.substr(8))
			if v > 0:
				_n = v
	_bench_a()
	_bench_b()
	_bench_c()
	_bench_d()
	_bench_e()
	_bench_f()
	_report()
	get_tree().quit(0)

# ─────────────────────────────────────────────────────────────────────────────
# A. ЧИСТАЯ SoA-ИНТЕГРАЦИЯ
# ─────────────────────────────────────────────────────────────────────────────
func _bench_a() -> void:
	var n := _n
	var px := PackedFloat32Array(); px.resize(n)
	var pz := PackedFloat32Array(); pz.resize(n)
	var vx := PackedFloat32Array(); vx.resize(n)
	var vz := PackedFloat32Array(); vz.resize(n)
	for i in range(n):
		px[i] = randf() * 200.0
		pz[i] = randf() * 200.0
		vx[i] = 1.0
		vz[i] = 0.5
	var dt := 1.0 / 60.0
	var best := 1e18
	for _it in range(ITERS):
		var t0 := Time.get_ticks_usec()
		for i in range(n):
			px[i] = px[i] + vx[i] * dt
			pz[i] = pz[i] + vz[i] * dt
		var d := float(Time.get_ticks_usec() - t0)
		if d < best:
			best = d
	_rows.append(["A. SoA: только интеграция позиции", best])

# ─────────────────────────────────────────────────────────────────────────────
# B. SoA + СОСТОЯНИЕ, ТАЙМЕРЫ, ПРИБЫТИЕ
#    Это уже похоже на честный шаг: ветка по состоянию, откат таймера,
#    нормировка направления, проверка «дошёл»
# ─────────────────────────────────────────────────────────────────────────────
func _bench_b() -> void:
	var n := _n
	var px := PackedFloat32Array(); px.resize(n)
	var pz := PackedFloat32Array(); pz.resize(n)
	var tx := PackedFloat32Array(); tx.resize(n)
	var tz := PackedFloat32Array(); tz.resize(n)
	var st := PackedInt32Array();   st.resize(n)
	var tm := PackedFloat32Array(); tm.resize(n)
	var sp := PackedFloat32Array(); sp.resize(n)
	for i in range(n):
		px[i] = randf() * 200.0
		pz[i] = randf() * 200.0
		tx[i] = px[i] + 300.0
		tz[i] = pz[i] + 300.0
		st[i] = 1
		tm[i] = randf()
		sp[i] = 4.0
	var dt := 1.0 / 60.0
	var best := 1e18
	for _it in range(ITERS):
		var t0 := Time.get_ticks_usec()
		for i in range(n):
			var s := st[i]
			if s == 1:
				var dx: float = tx[i] - px[i]
				var dz: float = tz[i] - pz[i]
				var d2: float = dx * dx + dz * dz
				if d2 < 0.09:
					st[i] = 0
				else:
					var inv: float = sp[i] * dt / sqrt(d2)
					px[i] = px[i] + dx * inv
					pz[i] = pz[i] + dz * inv
			elif s == 0:
				var t: float = tm[i] - dt
				if t <= 0.0:
					t = 0.5
				tm[i] = t
		var d := float(Time.get_ticks_usec() - t0)
		if d < best:
			best = d
	_rows.append(["B. SoA: состояние + таймеры + шаг", best])

# ─────────────────────────────────────────────────────────────────────────────
# C. B + ПОИСК СОСЕДА В ПЛОСКОЙ СЕТКЕ (ячейки в PackedInt32Array)
#    Троттлено: сосед ищется у 1/30 бойцов за кадр (как AGGRO_INTERVAL_HOT)
# ─────────────────────────────────────────────────────────────────────────────
const CELL := 2.0
const GRID_W := 256
const GRID_H := 256
const BUCKET := 8      ## сколько бойцов помещается в ячейку

func _bench_c() -> void:
	var n := _n
	var px := PackedFloat32Array(); px.resize(n)
	var pz := PackedFloat32Array(); pz.resize(n)
	var fc := PackedInt32Array();   fc.resize(n)
	for i in range(n):
		px[i] = randf() * 400.0
		pz[i] = randf() * 400.0
		fc[i] = i & 1
	# Плоская сетка: cnt[cell] + slots[cell*BUCKET + k]
	var cnt := PackedInt32Array(); cnt.resize(GRID_W * GRID_H)
	var slots := PackedInt32Array(); slots.resize(GRID_W * GRID_H * BUCKET)
	var best_fill := 1e18
	var best_scan := 1e18
	for _it in range(ITERS):
		# ── перестроение сетки целиком ──
		var t0 := Time.get_ticks_usec()
		for i in range(cnt.size()):
			cnt[i] = 0
		for i in range(n):
			var cx: int = int(px[i] / CELL)
			var cz: int = int(pz[i] / CELL)
			if cx < 0 or cz < 0 or cx >= GRID_W or cz >= GRID_H:
				continue
			var c: int = cz * GRID_W + cx
			var k: int = cnt[c]
			if k < BUCKET:
				slots[c * BUCKET + k] = i
				cnt[c] = k + 1
		var d1 := float(Time.get_ticks_usec() - t0)
		if d1 < best_fill:
			best_fill = d1
		# ── поиск соседа у 1/30 армии ──
		var t1 := Time.get_ticks_usec()
		var step := 30
		var i2 := _it % step
		while i2 < n:
			var cx: int = int(px[i2] / CELL)
			var cz: int = int(pz[i2] / CELL)
			var myf: int = fc[i2]
			var bx: float = px[i2]
			var bz: float = pz[i2]
			var best_d := 1e18
			var found := -1
			for oz in range(cz - 1, cz + 2):
				if oz < 0 or oz >= GRID_H:
					continue
				for ox in range(cx - 1, cx + 2):
					if ox < 0 or ox >= GRID_W:
						continue
					var c: int = oz * GRID_W + ox
					var k: int = cnt[c]
					var base: int = c * BUCKET
					for q in range(k):
						var j: int = slots[base + q]
						if fc[j] == myf:
							continue
						var dx: float = px[j] - bx
						var dz: float = pz[j] - bz
						var dd: float = dx * dx + dz * dz
						if dd < best_d:
							best_d = dd
							found = j
			i2 += step
		var d2 := float(Time.get_ticks_usec() - t1)
		if d2 < best_scan:
			best_scan = d2
	_rows.append(["C1. Плоская сетка: полное перестроение", best_fill])
	_rows.append(["C2. Поиск соседа у 1/30 армии", best_scan])

# ─────────────────────────────────────────────────────────────────────────────
# D. ТЕКУЩАЯ СХЕМА: массив узлов, вызов метода на каждом
#    Тело метода — та же арифметика, что в B. Разница только в том, что это
#    объект дерева сцены и обычный вызов метода GDScript
# ─────────────────────────────────────────────────────────────────────────────
class Dummy extends Node3D:
	var st: int = 1
	var tmr: float = 0.5
	var spd: float = 4.0
	var tgx: float = 0.0
	var tgz: float = 0.0
	func step(dt: float) -> void:
		if st == 1:
			var p := global_position
			var dx: float = tgx - p.x
			var dz: float = tgz - p.z
			var d2: float = dx * dx + dz * dz
			if d2 < 0.09:
				st = 0
			else:
				var inv: float = spd * dt / sqrt(d2)
				global_position = Vector3(p.x + dx * inv, p.y, p.z + dz * inv)
		else:
			tmr -= dt
			if tmr <= 0.0:
				tmr = 0.5

func _bench_d() -> void:
	var n := _n
	var arr: Array = []
	arr.resize(n)
	var holder := Node3D.new()
	add_child(holder)
	for i in range(n):
		var d := Dummy.new()
		d.position = Vector3(randf() * 200.0, 0.0, randf() * 200.0)
		d.tgx = d.position.x + 300.0
		d.tgz = d.position.z + 300.0
		holder.add_child(d)
		arr[i] = d
	var dt := 1.0 / 60.0
	var best := 1e18
	for _it in range(ITERS):
		var t0 := Time.get_ticks_usec()
		for u in arr:
			u.step(dt)
		var d := float(Time.get_ticks_usec() - t0)
		if d < best:
			best = d
	_rows.append(["D. Массив узлов Node3D + вызов метода", best])
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_rows.append(["   (узлов в дереве при этом)", nodes])
	holder.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
# E. ЦЕНА ФАСАДА: ОБЫЧНОЕ ПОЛЕ ПРОТИВ СВОЙСТВА С get/set НАД SoA
#
# От этого числа зависит, как строить Фазу 1. Если превратить горячие поля
# Unit (state, faction, current_health) в свойства, читающие строку SoA, то
# КАЖДОЕ обращение в горячем цикле станет вызовом функции. Здесь меряется,
# во что это обойдётся, — чтобы решение было по замеру, а не по вкусу.
# ─────────────────────────────────────────────────────────────────────────────
class Plain extends RefCounted:
	var hp: float = 100.0
	var st: int = 1

class Facade extends RefCounted:
	static var HP := PackedFloat32Array()
	static var ST := PackedInt32Array()
	var idx: int = 0
	var hp: float:
		get: return HP[idx]
		set(v): HP[idx] = v
	var st: int:
		get: return ST[idx]
		set(v): ST[idx] = v

func _bench_e() -> void:
	var n := _n
	var plain: Array = []
	var faca: Array = []
	plain.resize(n)
	faca.resize(n)
	Facade.HP.resize(n)
	Facade.ST.resize(n)
	for i in range(n):
		var p := Plain.new()
		plain[i] = p
		var f := Facade.new()
		f.idx = i
		Facade.HP[i] = 100.0
		Facade.ST[i] = 1
		faca[i] = f

	var best_p := 1e18
	var best_f := 1e18
	for _it in range(ITERS):
		var t0 := Time.get_ticks_usec()
		var acc := 0.0
		for o in plain:
			if o.st == 1:
				acc += o.hp
		var d1 := float(Time.get_ticks_usec() - t0)
		if d1 < best_p:
			best_p = d1
		var t1 := Time.get_ticks_usec()
		var acc2 := 0.0
		for o in faca:
			if o.st == 1:
				acc2 += o.hp
		var d2 := float(Time.get_ticks_usec() - t1)
		if d2 < best_f:
			best_f = d2
	_rows.append(["E1. Обычные поля объекта (чтение 2 шт.)", best_p])
	_rows.append(["E2. Свойства-фасад над SoA (то же самое)", best_f])

# ─────────────────────────────────────────────────────────────────────────────
# F. ИЗ ЧЕГО СКЛАДЫВАЕТСЯ ЦЕНА УЗЛА
#
# Замер D показывает «узлы дороже массивов», но не говорит, ЗА ЧТО платим:
# за существование объекта и вызов метода, за запись локального трансформа
# или за запись МИРОВОГО. Разница принципиальна для плана: если основную долю
# держит трансформ, узел можно оставить в дереве (он ничего не стоит, пока его
# не трогают) и убрать только запись — это несравнимо меньше работы, чем
# выкорчёвывать узлы из всей игры.
#
# F1 — чистый цикл по столбцам (то же, что B, для сравнения в одном прогоне)
# F2 — те же вычисления, но через вызов метода объекта; трансформ НЕ трогаем
# F3 — то же + запись position (локальный трансформ)
# F4 — то же + запись global_position (мировой)
# ─────────────────────────────────────────────────────────────────────────────
class Body extends Node3D:
	static var PX := PackedFloat32Array()
	static var PZ := PackedFloat32Array()
	var idx: int = 0
	## Только счёт, узел не трогаем
	func calc(dt: float) -> void:
		var x: float = PX[idx] + 4.0 * dt
		var z: float = PZ[idx] + 1.0 * dt
		PX[idx] = x
		PZ[idx] = z
	## Счёт + локальный трансформ
	func calc_local(dt: float) -> void:
		var x: float = PX[idx] + 4.0 * dt
		var z: float = PZ[idx] + 1.0 * dt
		PX[idx] = x
		PZ[idx] = z
		position = Vector3(x, 0.0, z)
	## Счёт + мировой трансформ
	func calc_global(dt: float) -> void:
		var x: float = PX[idx] + 4.0 * dt
		var z: float = PZ[idx] + 1.0 * dt
		PX[idx] = x
		PZ[idx] = z
		global_position = Vector3(x, 0.0, z)

func _bench_f() -> void:
	var n := _n
	Body.PX.resize(n)
	Body.PZ.resize(n)
	var holder := Node3D.new()
	add_child(holder)
	var arr: Array = []
	arr.resize(n)
	for i in range(n):
		var b := Body.new()
		b.idx = i
		Body.PX[i] = randf() * 200.0
		Body.PZ[i] = randf() * 200.0
		holder.add_child(b)
		arr[i] = b
	var dt := 1.0 / 60.0
	var b1 := 1e18
	var b2 := 1e18
	var b3 := 1e18
	var b4 := 1e18
	var px := Body.PX
	var pz := Body.PZ
	for _it in range(ITERS):
		var t0 := Time.get_ticks_usec()
		for i in range(n):
			px[i] = px[i] + 4.0 * dt
			pz[i] = pz[i] + 1.0 * dt
		var d1 := float(Time.get_ticks_usec() - t0)
		if d1 < b1: b1 = d1
		var t1 := Time.get_ticks_usec()
		for o in arr:
			o.calc(dt)
		var d2 := float(Time.get_ticks_usec() - t1)
		if d2 < b2: b2 = d2
		var t2 := Time.get_ticks_usec()
		for o in arr:
			o.calc_local(dt)
		var d3 := float(Time.get_ticks_usec() - t2)
		if d3 < b3: b3 = d3
		var t3 := Time.get_ticks_usec()
		for o in arr:
			o.calc_global(dt)
		var d4 := float(Time.get_ticks_usec() - t3)
		if d4 < b4: b4 = d4
	_rows.append(["F1. Столбцы, без объектов вовсе", b1])
	_rows.append(["F2. Вызов метода объекта, трансформ не трогаем", b2])
	_rows.append(["F3.  + запись position (локальный)", b3])
	_rows.append(["F4.  + запись global_position (мировой)", b4])
	holder.queue_free()

func _report() -> void:
	var out := PackedStringArray()
	out.append("")
	out.append("═══ ПОЛ ПРОИЗВОДИТЕЛЬНОСТИ GDScript, N = %d ═══" % _n)
	out.append("Лучшее из %d прогонов, микросекунды за один проход" % ITERS)
	out.append("Бюджет кадра при 120 к/с — 8330 мкс, при 100 к/с — 10000 мкс,")
	out.append("при 60 к/с — 16600 мкс.")
	out.append("")
	for r in _rows:
		var name: String = r[0]
		var us: float = r[1]
		if name.begins_with("   "):
			out.append("%-42s %10d" % [name, int(us)])
		else:
			out.append("%-42s %8d мкс   (%.2f мкс/сущность)" % [name, int(us), us / float(_n)])
	print("\n".join(out))
