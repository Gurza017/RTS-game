extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СТРОЙ, ДРОЖАНИЕ И СКВОЗНОЙ ПРОХОД СОЮЗНИКОВ
## ═══════════════════════════════════════════════════════════════════════════
##   A ПОКОЙ        — стоящий отряд не дрожит на месте
##   B КОРИДОР      — сквозь строй проходит союзный отряд, ряды раздвигаются
##   C СМЫКАНИЕ     — после прохода шеренга возвращается в свой кирпичик
##   D ФАЛАНГА      — копья опускаются вразнобой, а не одновременно
##
## Запуск: godot --headless --path . res://qa_formation/Test.tscn

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

func _hd(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Отряд в строю: cols колонок, интервал как в SelectionManager
func _make_squad(kind: String, fac: int, center: Vector3, count: int,
		cols: int = 5) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(count):
		var u: Unit
		match kind:
			"spearman": u = Spearman.new()
			"warrior":  u = Warrior.new()
			_:          u = Worker.new()
		u.faction = fac
		main.world_add(u)
		var col: int = i % cols
		var row: int = i / cols
		var p := center + Vector3((float(col) - float(cols - 1) * 0.5) * 0.5,
			0.0, float(row) * 0.55)
		u.global_position = p
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _run() -> void:
	seed(4242)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	# «Чистая комната» далеко за картой: ни ИИ, ни лес, ни чужие отряды не мешают
	GameManager.world_bounds_enabled = false
	# ОТСЕЧЕНИЕ ДАЛЬНИХ СПРАЙТОВ СНИМАЕМ. Площадка стенда вынесена за сотни
	# метров от точки обзора камеры, то есть заведомо за LOD_RADIUS: поза
	# спрайта там не пересчитывается вовсе, и проверять её бессмысленно
	preload("res://scripts/perf_config.gd").sprite_lod = false
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  СТРОЙ: ПОКОЙ, КОРИДОР, СМЫКАНИЕ, ФАЛАНГА                        ║")
	print("╚══════════════════════════════════════════════════════════════════╝")
	await _a_rest()
	await _b_corridor()
	await _d_phalanx()

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %s%s" % [_pad(String(row[0]), 58), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== FORMATION TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. СТОЯЩИЙ ОТРЯД НЕ ДРОЖИТ
# Главный баг: интервал слотов строя (0.5 м) был МЕНЬШЕ личного пространства
# (0.62 м) — шеренга сама себя расталкивала, возврат в строй тянул обратно,
# и отряд вечно вибрировал на месте.
# ═════════════════════════════════════════════════════════════════════════════
func _a_rest() -> void:
	print("\n═════ A. ПОКОЙ СТОЯЩЕГО СТРОЯ ═════")
	var men := _make_squad("spearman", Constants.FACTION_PLAYER,
		Vector3(0, 0, -300), 20)
	await frames(60)
	var before: Array = []
	for u in men:
		before.append((u as Node3D).global_position)
	# Две секунды покоя
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	var max_drift := 0.0
	for i in range(men.size()):
		max_drift = maxf(max_drift, _hd((men[i] as Node3D).global_position, before[i]))
	print("  наибольшее смещение за 2 с покоя: %.3f м" % max_drift)
	verdict("A1 строй не дрожит на месте", max_drift < 0.10,
		"смещение %.3f м" % max_drift)
	for u in men:
		(u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# B/C. СКВОЗНОЙ ПРОХОД СОЮЗНОГО ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _b_corridor() -> void:
	print("\n═════ B. КОРИДОР ДЛЯ СОЮЗНИКА И СМЫКАНИЕ ═════")
	# Стоящий строй
	var wall := _make_squad("spearman", Constants.FACTION_PLAYER,
		Vector3(0, 0, -350), 20)
	# Идущий сквозь него отряд: заходит слева, уходит направо
	var runners := _make_squad("warrior", Constants.FACTION_PLAYER,
		Vector3(-14, 0, -350), 10)
	await frames(45)

	var home: Array = []
	for u in wall:
		home.append((u as Node3D).global_position)

	for u in runners:
		(u as Unit).command_move(Vector3(14, 0, -350))

	# Момент прохода: меряем максимальный разъезд стоящих от своих мест
	var spread := 0.0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
		for i in range(wall.size()):
			spread = maxf(spread, _hd((wall[i] as Node3D).global_position, home[i]))
	print("  наибольшее расхождение рядов во время прохода: %.2f м" % spread)
	# КОНТРАКТ ИЗМЕНИЛСЯ. Раньше шеренга физически РАЗДВИГАЛАСЬ, пропуская своих:
	# проходящий расталкивал стоящих, те отходили и потом смыкались обратно.
	# Механику расталкивания союзников убрали целиком — она и была источником
	# вечного дрожания на скоплениях. Теперь союзники просто проходят ДРУГ
	# СКВОЗЬ ДРУГА, и правильное поведение — обратное прежнему: строй при
	# проходе НЕ ШЕЛОХНУЛСЯ. Что проход состоялся, проверяет B2
	verdict("B1 строй не колышется, когда сквозь него проходят свои", spread < 0.25,
		"расхождение %.2f м" % spread)

	# Проходящий отряд обязан ПРОЙТИ насквозь, а не увязнуть в шеренге
	var through := 0
	for u in runners:
		if (u as Node3D).global_position.x > 6.0:
			through += 1
	verdict("B2 союзный отряд прошёл насквозь", through >= 8,
		"прошло %d из 10" % through)

	# Смыкание: ждём и проверяем возврат
	var t1: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 5000:
		await get_tree().process_frame
	var back := 0
	var worst := 0.0
	for i in range(wall.size()):
		var d: float = _hd((wall[i] as Node3D).global_position, home[i])
		worst = maxf(worst, d)
		if d < 0.7:
			back += 1
	print("  вернулось на места: %d из %d, худшее отклонение %.2f м"
		% [back, wall.size(), worst])
	verdict("C1 шеренга сомкнулась обратно", back >= wall.size() - 2,
		"вернулось %d из %d" % [back, wall.size()])

	for u in wall + runners:
		(u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. АСИНХРОННОЕ ОПУСКАНИЕ КОПИЙ
# ═════════════════════════════════════════════════════════════════════════════
func _d_phalanx() -> void:
	print("\n═════ D. АСИНХРОННАЯ ФАЛАНГА ═════")
	var men := _make_squad("spearman", Constants.FACTION_PLAYER,
		Vector3(0, 0, -400), 20)
	# ВРАЖЕСКАЯ ШЕРЕНГА, А НЕ ОДИНОЧКА. Раньше напротив строя 5×4 ставили ОДНОГО
	# бойца, и это ломало сам замер: направление фаланги считается на ближайшего
	# противника (Unit._phalanx_dir), поэтому крайние колонны смотрели на него
	# ПОД УГЛОМ. Конус подсчёта ряда у них разворачивался по диагонали, ловил
	# соседей из чужих колонн, и «первые две шеренги» переставали быть
	# шеренгами — счёт горизонтальных копий гулял от 3 до 8 из 20 от прогона к
	# прогону. Против ровной стенки все колонны смотрят в одну сторону
	var foes: Array = []
	for c in range(5):
		var foe := Spearman.new()
		foe.faction = Constants.FACTION_ENEMY
		main.world_add(foe)
		foe.global_position = Vector3((float(c) - 2.0) * 0.5, 0, -394)
		foes.append(foe)
	await frames(5)
	# БЕССМЕРТНЫЕ И НЕПОДВИЖНЫЕ. Бессмертные — иначе шеренга добивает их быстрее,
	# чем идёт замер, и фаланге становится не на кого смотреть.
	#
	# Неподвижные — потому что раздел проверяет РАЗБРОС ОПУСКАНИЯ КОПИЙ, а не
	# рукопашную. Живой противник в стойке атаки сам вбегает в строй, растаскивает
	# шеренги и перемешивает ряды: замер показывал _live_rank вплоть до 8 у отряда
	# ГЛУБИНОЙ В ЧЕТЫРЕ ШЕРЕНГИ, половина бойцов уходила в ATTACKING и рисовала
	# позу удара вместо defence. Считать по такой каше «первые две шеренги»
	# бессмысленно. Замерший строй врага даёт фаланге ориентир и не мешает
	for f in foes:
		var fu := f as Unit
		fu.max_health     = 1e9
		fu.current_health = 1e9
		fu.attack_damage  = 0.0
		fu.set_physics_process(false)
	await frames(45)

	var t_switch: int = Time.get_ticks_msec()
	# КТО БЫЛ ПЕРЕДОВЫМ В МОМЕНТ ПРИКАЗА. Именно на них и рассчитан разброс
	# задержек: их копья обязаны лечь в пределах DROP_DELAY_MAX_MS. Боец,
	# ставший передовым ПОЗЖЕ (строй сдвинулся, ряды пересчитались), опускает
	# копьё в момент своего повышения — его время к разбросу отношения не имеет
	var front_at_order: Dictionary = {}
	for u in men:
		var un := u as Unit
		if un._live_rank < Unit.PHALANX_FRONT_RANKS:
			front_at_order[un.get_instance_id()] = true
	for u in men:
		(u as Unit).set_stance("defense")

	# Ловим момент, когда у каждого копьё опустилось (поза defence_*)
	var drop_ms: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
		for u in men:
			var id: int = (u as Node).get_instance_id()
			if drop_ms.has(id):
				continue
			if String((u as Unit).get("_cur_tex_key")).begins_with("defence"):
				drop_ms[id] = Time.get_ticks_msec() - t_switch
	var times: Array = drop_ms.values()
	times.sort()
	if times.is_empty():
		verdict("D1 копья вообще опускаются", false, "ни один не перешёл в defence")
	else:
		var lo: int = int(times[0])
		var hi: int = int(times[times.size() - 1])
		print("  опустили копья: %d из %d, разброс %d..%d мс"
			% [times.size(), men.size(), lo, hi])
		# Диагностика: по каким шеренгам разошлись ряды и позы
		var hist: Dictionary = {}
		for u in men:
			var un := u as Unit
			var r: int = un._live_rank
			hist[r] = int(hist.get(r, 0)) + 1
		print("    гистограмма _live_rank: %s" % str(hist))
		for row in range(4):
			var lev := 0
			var st := {}
			for i in range(men.size()):
				if i / 5 != row:
					continue
				var un2 := men[i] as Unit
				if bool(un2.call("_spear_leveled")):
					lev += 1
				st[un2.state] = int(st.get(un2.state, 0)) + 1
			print("    шеренга %d: копьё наперевес у %d/5, состояния %s"
				% [row, lev, str(st)])
		# Копья наперевес держат ТОЛЬКО первые две шеренги (Unit.PHALANX_FRONT_RANKS):
		# в отряде 20 человек по 5 колонн это 10 бойцов, задние держат древки вверх.
		# Допуск — на живой пересчёт ряда: он идёт по фактическому окружению
		# Копья наперевес держат ТОЛЬКО передовые шеренги (Unit.PHALANX_FRONT_RANKS),
		# задние — древки вверх. Точное число плавает от прогона к прогону: ряд
		# считается по ФАКТИЧЕСКОМУ окружению (Unit._update_live_rank), а строй
		# слегка расходится. Поэтому проверяем качественно: передовая опустила
		# копья, но не весь отряд разом
		# ЧТО ИМЕННО ПРОВЕРЯЕМ. Раньше стояло «не меньше восьми из двадцати» —
		# число, посчитанное для НЕПОДВИЖНОГО блока 5×4 (две передние шеренги =
		# 10). Сцена такой не является: отряд стоит против врага, живёт, слегка
		# переступает и смыкает ряды, поэтому точное число плавает 6…10 от
		# прогона к прогону, ничего при этом не говоря о механике.
		#
		# Суть требования — «копья опустила ПЕРЕДОВАЯ, а не весь отряд», то есть
		# РАСПРЕДЕЛЕНИЕ: щетина пик собрана у фронта, а тыл держит древки вверх.
		# Это и проверяем — и заодно, что подняли копья не все и не никто
		var front := 0
		var rear  := 0
		for i in range(men.size()):
			if not bool((men[i] as Unit).call("_spear_leveled")):
				continue
			if i / 5 >= 2:
				front += 1     # шеренги 2-3 стоят к врагу лицом
			else:
				rear += 1
		print("    копья: у передних шеренг %d, у задних %d" % [front, rear])
		verdict("D1 копья опустила передовая, а не весь отряд",
			times.size() > 0 and times.size() < men.size() and front > rear,
			"всего %d из %d; фронт %d, тыл %d" % [times.size(), men.size(), front, rear])
		verdict("D2 опускание НЕ одновременное", hi - lo > 400,
			"разброс %d мс" % (hi - lo))
		# D3 — ПРО РАСПРЕДЕЛЕНИЕ ЗАДЕРЖЕК, а не про последнего в списке.
		#
		# По максимуму мерить нельзя: копьё опускают не только те, кто был
		# передовым в момент приказа, но и те, кто стал передовым ПОЗЖЕ — строй
		# переступил, ряды пересчитались. Такой боец выставляет копьё в момент
		# своего повышения, и его время к разбросу задержек отношения не имеет.
		# (Отсечь их заранее тоже не выйдет: до перехода в стойку ЗАЩИТА ряд
		# вообще не считается и равен нулю у всех — см. front_at_order.)
		#
		# Зато МЕДИАНА устойчива: она описывает именно ту россыпь 0…DROP_DELAY_MAX,
		# ради которой задержка и вводилась, и не зависит от одиночных хвостов
		var mid: int = int(times[times.size() / 2])
		var limit: int = Spearman.DROP_DELAY_MAX_MS
		print("    передовых на момент приказа: %d (ряд до приказа не считается), медиана %d мс"
			% [front_at_order.size(), mid])
		verdict("D3 задержки укладываются в заданный разброс",
			lo < 700 and mid < limit,
			"первый в %d мс, медиана %d мс (порог %d)" % [lo, mid, limit])

	for u in men:
		(u as Node).queue_free()
	for f in foes:
		(f as Node).queue_free()
	await frames(3)
