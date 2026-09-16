extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: БОЙ В ТОЛПЕ — СТРОЙ, УПОР В ЧУЖОЙ СТРОЙ И ОСАДА ОДНОГО ЗДАНИЯ
## ═══════════════════════════════════════════════════════════════════════════
## ЗАЧЕМ ЕЩЁ ОДИН БОЕВОЙ СТЕНД. Жалобы владельца звучат так: «вражеская пехота
## протекает сквозь фалангу», «в схватке дерутся два-три крайних копейщика,
## остальные стоят», «отряд, посланный ЗА спины врага, упирается в него и молча
## умирает». Ни одну из них стерильный стенд из десяти бойцов увидеть НЕ МОЖЕТ:
## все они живут на СТЫКАХ, которые появляются только в толпе — общий ответ
## отряда о ближайшем враге (Unit._squad_cached_enemy), глубина строя и замки
## приказа игрока.
##
## Три раздела, и все меряют СВОЙСТВА, а не круглые числа:
##   A — стена копейщиков против отрядов, посланных на лучников ЗА ней;
##   C — марш ЗА спину противнику из уже начатого боя;
##   B — десять отрядов на одной хижине гоблинов.
##
## Запуск: godot --headless --path . res://qa_wall/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## physics_frame, а не process_frame (правило 11 проекта)
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

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

## Отряд из n бойцов ровным прямоугольником шириной cols
func _squad(scene: String, stat: String, fac: int, at: Vector3,
		n: int, cols: int) -> Array:
	var sid: int = GameManager.new_squad(fac, stat)
	var men: Array = []
	for i in range(n):
		var p := at + Vector3(float(i % cols) * 0.6 - float(cols) * 0.3,
			0.0, float(i / cols) * 0.62)
		var u := _spawn(scene, fac, p)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _sid(men: Array) -> int:
	for u in men:
		if is_instance_valid(u):
			return (u as Unit).squad_id
	return 0

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if u == null or not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu != null and not uu.is_dead():
			out.append(uu)
	return out

## Сумма запаса жизни живых
func _total_hp(men: Array) -> float:
	var acc := 0.0
	for u in _alive(men):
		acc += (u as Unit).current_health
	return acc

## Сколько бойцов из `men` дотягиваются оружием хоть до кого-то из `foes`
## и сколько из них ДЕРЖАТ живую цель. Возвращает [дотягиваются, дерутся]
func _contact_stats(men: Array, foes: Array) -> Array:
	var live_foes := _alive(foes)
	var can := 0
	var has := 0
	for u in _alive(men):
		var uu := u as Unit
		var near := INF
		for f in live_foes:
			near = minf(near, uu.global_position.distance_to((f as Node3D).global_position))
		if near > uu.attack_range:
			continue
		can += 1
		var t = uu.attack_target
		if t != null and is_instance_valid(t) and not (t as Unit).is_dead():
			has += 1
	return [can, has]

func _run() -> void:
	seed(7)
	Engine.max_fps = 0
	# ПОЗУ СЧИТАЮТ ТОЛЬКО ВИДИМЫМ (Unit.tick_visual, ветка LOD), а в headless
	# точки обзора нет вовсе — без этого щетина пик не пересчиталась бы ни разу
	preload("res://scripts/perf_config.gd").sprite_lod = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(6)

	await _block_wall()
	await _block_march()
	await _block_siege()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 62), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== WALL TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. СТЕНА КОПЕЙЩИКОВ
# ═════════════════════════════════════════════════════════════════════════════
## Насколько далеко ЗА линию строя должен зайти враг, чтобы считаться
## «протёкшим сквозь». Три с половиной метра — это уже за спинами последней
## шеренги, случайным толчком туда не попасть
const BEHIND_LINE := -3.5
## Доля живого строя, при которой замер прохода ещё что-то значит. Ниже неё
## фаланга уже не забор, а остатки, и пропускать врага она вправе
const WALL_INTACT_FRAC := 0.7

var _wall_men: Array = []
var _foe_men: Array = []

func _block_wall() -> void:
	print("\n═════ A. СТЕНА КОПЕЙЩИКОВ ═════")
	# Три отряда копейщиков вдоль оси X, фронтом на +Z
	var course := Vector3(0.0, 0.0, 1.0)
	for k in range(3):
		var men := _squad("res://scenes/units/Spearman.tscn", "spearman",
			Constants.FACTION_PLAYER, Vector3(-7.0 + float(k) * 7.0, 0.0, -1.2), 24, 8)
		_wall_men.append_array(men)
		var sid := _sid(men)
		# Разметка линии: восемь мест в шеренге, три шеренги
		var slots: Array = []
		for i in range(men.size()):
			slots.append(Vector3(-7.0 + float(k) * 7.0 + float(i % 8) * 0.6 - 2.4,
				0.0, -float(i / 8) * 0.62))
		GameManager.squad_set_formation(sid, slots, course, false)
		for i in range(men.size()):
			(men[i] as Unit).formation_row = i / 8
			(men[i] as Unit).command_move(slots[i], true, course, false, true)
	# Лучники ЗА строем — приманка, ради которой враг и полезет
	var arch := _squad("res://scenes/units/Archer.tscn", "archer",
		Constants.FACTION_PLAYER, Vector3(0.0, 0.0, -9.0), 16, 8)
	await frames(150)
	# Строй встал — переводим в оборону
	for u in _wall_men:
		(u as Unit).set_stance("defense")
	await frames(60)

	# ── ЩЕТИНА ПИК С ПЕРВОГО ПЕРЕКЛЮЧЕНИЯ ──────────────────────────────────
	# Копьё опускают первые две шеренги (Unit.PHALANX_FRONT_RANKS), и это
	# должно случиться СРАЗУ, а не после второго нажатия кнопки
	var front := 0
	var down := 0
	for u in _wall_men:
		var sp := u as Spearman
		if sp == null or sp.is_dead():
			continue
		if sp._live_rank < Unit.PHALANX_FRONT_RANKS:
			front += 1
			if bool(sp.call("_spear_leveled")):
				down += 1
	verdict("A0 фаланга выставила копья с первого переключения стойки",
		front > 0 and down >= int(float(front) * 0.9),
		"опустили %d из %d передних (весь строй %d)" % [down, front, _wall_men.size()])

	# Три отряда врага идут на ЛУЧНИКОВ за строем
	var bait: Unit = arch[0]
	for k in range(3):
		var foes := _squad("res://scenes/units/Warrior.tscn", "warrior",
			Constants.FACTION_ENEMY, Vector3(-7.0 + float(k) * 7.0, 0.0, 18.0), 16, 8)
		_foe_men.append_array(foes)
		for u in foes:
			(u as Unit).command_attack(bait, true, true, true)

	# ── ПРОСОЧИВШИХСЯ СЧИТАЕМ, ПОКА ЦЕЛ ТОТ УЧАСТОК, ЧЕРЕЗ КОТОРЫЙ ИДУТ ─────
	# Разбитая фаланга пропускает противника ЗАКОННО — это не «проход сквозь
	# строй», а победа в бою. Вопрос стенда другой: может ли враг оказаться в
	# тылу у ЖИВОГО строя.
	#
	# ЦЕЛОСТЬ МЕРИТСЯ ПО УЧАСТКУ, А НЕ ПО ВСЕМУ ФРОНТУ, И ЭТО НЕ ПРИДИРКА.
	# Все три вражеских отряда посланы на ОДНУ приманку в центре, то есть
	# сорок восемь мечников сходятся на среднюю треть из двадцати четырёх
	# копейщиков, а фланги стоят почти нетронутыми. Замер: середина выбита до
	# 16 из 24 (67%) при 53 из 72 (74%) по всему строю — то есть общий порог
	# считал целым участок УЖЕ РАЗБИТЫЙ, и законный местный прорыв читался как
	# «прошли сквозь живой строй». Разброс от прогона к прогону был от 0 до 18
	# человек в тылу на НЕИЗМЕННОМ коде: краснела не игра, а критерий.
	var best_ratio := 0.0
	var best_can := 0
	var best_has := 0
	var leaked_intact := 0
	var intact_samples := 0
	var crossed: Dictionary = {}
	for _s in range(24):
		# ── ПЕРЕСЕЧЕНИЕ ЛОВИТСЯ ЧАСТО, А НЕ РАЗ В СЕКУНДУ ──────────────
		# Мечник идёт около трёх метров в секунду: при опросе раз в секунду
		# он успевает уйти от места перехода на три метра, и замер приписал
		# бы прорыв ЧУЖОМУ участку строя. Замер: тринадцать «прорвавшихся»
		# стояли за ЦЕЛОЙ серединой, а перешли линию через РАЗБИТЫЙ левый
		# край и уже за строем сошлись к приманке в центре
		for _q in range(6):
			await frames(10)
			for f in _alive(_foe_men):
				var fp: Vector3 = (f as Node3D).global_position
				if fp.z >= BEHIND_LINE:
					continue
				var fid: int = (f as Object).get_instance_id()
				if crossed.has(fid):
					continue
				# Решение принимается ОДИН РАЗ, в миг перехода линии
				crossed[fid] = _line_manned_at(fp)
		if _line_manned_somewhere():
			intact_samples += 1
			var lk := 0
			for fid2 in crossed:
				if bool(crossed[fid2]):
					lk += 1
			leaked_intact = maxi(leaked_intact, lk)
		var st: Array = _contact_stats(_wall_men, _foe_men)
		var can: int = int(st[0])
		var has: int = int(st[1])
		if can >= 6:
			var r: float = float(has) / float(can)
			if r > best_ratio:
				best_ratio = r
				best_can = can
				best_has = has

	# A1 — СКВОЗЬ ЖИВОЙ СТРОЙ НИКТО НЕ ПРОШЁЛ
	verdict("A1 враг не проходит сквозь ЖИВОЙ строй",
		intact_samples >= 3 and leaked_intact == 0,
		"замеров на целом участке %d, худший — %d в тылу" % [intact_samples, leaked_intact])

	# A2 — ДЕРУТСЯ ВСЕ, КТО ДОСТАЁТ, А НЕ ДВА-ТРИ КРАЙНИХ
	verdict("A2 дерутся все, кто дотягивается до врага", best_ratio >= 0.7,
		"лучший замер %d из %d (%.0f%%)" % [best_has, best_can, best_ratio * 100.0])

	# A3 — БОЙ ВООБЩЕ СОСТОЯЛСЯ. Судим по НАНЕСЁННОМУ УРОНУ, а не по убитым:
	# с отрядным радаром (13.09.2026) стрелы ложатся «наименее обстрелянным»,
	# урон размазан по 48 рыцарям (340 HP каждый), и за 24 с замера ни один
	# не гибнет на исправном коде — база и правка дают −900 HP к 11-й секунде
	var foe_dead: int = _foe_men.size() - _alive(_foe_men).size()
	var foe_hp := 0.0
	for f in _alive(_foe_men):
		foe_hp += (f as Unit).current_health
	var lost: float = float(_foe_men.size()) * (_foe_men[0] as Unit).max_health - foe_hp
	verdict("A3 бой состоялся (у противника потери или снятый запас)", foe_dead > 0 or lost > 500.0,
		"выбито %d из %d, снято %.0f HP" % [foe_dead, _foe_men.size(), lost])

	# Убираем поле боя, чтобы следующие разделы мерили себя, а не остатки
	for u in _wall_men + _foe_men + arch:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(10)

# ═════════════════════════════════════════════════════════════════════════════
# C. МАРШ ЗА СПИНУ ПРОТИВНИКУ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца: «если отправить армию кликом ЗА спины врагов, передние
## ряды упираются во врага, встают в анимацию ходьбы и просто умирают, не
## отвечая на атаку».
##
## Раздел воспроизводит худший вариант: отряды СНАЧАЛА завязывают бой и только
## потом получают приказ идти дальше. Именно в нём взводился признак «выхожу из
## боя» (Unit._disengaging), а снимался он ТОЛЬКО по приходу в точку — куда
## упёршийся в чужой строй боец не приходит никогда. Тем же признаком заглушены
## и перехват марша, и ответ на удар (take_damage).
## ── БЫЛА ЛИ В ТОЧКЕ ПЕРЕХОДА ЖИВАЯ ЛИНИЯ ─────────────────────────────────────
## Целость меряется МЕСТНО, а не долей всего фронта, и это не придирка. Стенд
## ставит ТРИ отряда по восемь в шеренге с шагом 7 м — между ними остаются
## пустые промежутки по 2.8 м, а бой прогрызает в шеренге местные дыры. Замер:
## доля живых по трети 18 из 24 (75%, «цел»), а в двух метрах вокруг точки
## перехода живых 2-4 человека из двенадцати возможных — то есть линии там нет
## вовсе. Общий порог такой прорыв считал проходом сквозь живой строй, и
## проверка краснела через раз на НЕИЗМЕННОМ коде (от 0 до 18 в тылу).
const MANNED_BAND := 0.9      ## полуширина окна по X: три места разметки
const MANNED_MIN := 3         ## меньше — линии в этом месте нет

## Сколько живых стоит ПЕРЕД точкой в полосе MANNED_BAND по X
func _manned_count(at: Vector3) -> int:
	var n := 0
	for w in _alive(_wall_men):
		var wp: Vector3 = (w as Node3D).global_position
		if absf(wp.x - at.x) <= MANNED_BAND and wp.z >= at.z:
			n += 1
	return n

func _line_manned_at(at: Vector3) -> bool:
	return _manned_count(at) >= MANNED_MIN

## Есть ли ВООБЩЕ живая линия — иначе замер бессмыслен: считать проход сквозь
## строй, которого не осталось, нечестно в обе стороны
func _line_manned_somewhere() -> bool:
	return _alive(_wall_men).size() >= int(float(_wall_men.size()) * WALL_INTACT_FRAC)

## Треть фронта, в которой лежит точка: 0 — левая, 1 — средняя, 2 — правая.
## Отряды стоят с шагом 7 м вдоль X, границы — посередине между их центрами
func _third_of(x: float) -> int:
	if x < -3.5:
		return 0
	return 1 if x < 3.5 else 2


func _block_march() -> void:
	print("\n═════ C. МАРШ ЗА СПИНУ ПРОТИВНИКУ ═════")
	var base := Vector3(-220.0, 0.0, 0.0)
	var mine: Array = []
	var foes: Array = []
	# ── СТЕНА ЗАВЕДОМО ГЛУБЖЕ И ШИРЕ ИДУЩИХ ────────────────────────────────
	# Первая версия ставила поровну (48 на 48), и мечники ПРОБИВАЛИСЬ насквозь:
	# упора, ради которого раздел и написан, в замер не попадало вовсе («тактов
	# с упором 0»). Здесь на два отряда мечников приходятся четыре отряда
	# копейщиков в обороне — пройти сквозь такое нельзя, и боец обязан драться
	for k in range(2):
		mine.append_array(_squad("res://scenes/units/Warrior.tscn", "warrior",
			Constants.FACTION_PLAYER, base + Vector3(float(k) * 7.0, 0.0, -2.0), 20, 8))
	for k in range(4):
		foes.append_array(_squad("res://scenes/units/Spearman.tscn", "spearman",
			Constants.FACTION_ENEMY, base + Vector3(-4.0 + float(k) * 6.0, 0.0, 6.0), 30, 8))
	await frames(30)
	for u in foes:
		(u as Unit).set_stance("defense")
	# Сначала СХОДИМСЯ: приказ атаки, чтобы у бойцов появилась живая цель
	var bait: Unit = foes[0]
	for u in mine:
		(u as Unit).command_attack(bait, true, true, true)
	await frames(60 * 5)
	var engaged_before := 0
	for u in _alive(mine):
		if (u as Unit).attack_target != null:
			engaged_before += 1
	verdict("C0 отряды успели завязать бой (подготовка)", engaged_before > 0,
		"с целью %d из %d" % [engaged_before, _alive(mine).size()])

	# А ТЕПЕРЬ — ПРИКАЗ ИДТИ ДАЛЬШЕ, ЗА СПИНЫ ВРАГА. Тот же путь, что у клика:
	# player_order = true
	var hp_foe0 := _total_hp(foes)
	for u in _alive(mine):
		(u as Unit).command_move(base + Vector3(0.0, 0.0, 30.0), false,
			Vector3.ZERO, false, true)

	# ── ЗАМЕР ИДЁТ ВО ВРЕМЯ МАРША, А НЕ ПОСЛЕ НЕГО ─────────────────────────
	# К концу приказа в контакте не остаётся никого: кто пробился — ушёл
	# дальше, кто нет — лежит. Вопрос стенда про МОМЕНТ УПОРА: боец стоит
	# вплотную к чужому строю и дальше идти не может — дерётся ли он?
	# Опрашиваем каждую секунду и берём ХУДШИЙ такт из тех, где упёршихся
	# набралось достаточно для суждения.
	#
	# Первые две секунды пропускаем намеренно: столько длится окно прохода
	# приказа (Unit.FORCED_MOVE_PASS_SEC), и в нём чужие тела бойцу не преграда
	# вовсе — драться там он не обязан, он их проходит
	await frames(120)
	var worst_ratio := 1.0
	var worst_can := 0
	var worst_has := 0
	var samples := 0
	for _s2 in range(10):
		await frames(60)
		var st: Array = _contact_stats(mine, foes)
		var c2: int = int(st[0])
		var h2: int = int(st[1])
		if c2 >= 4:
			samples += 1
			var r2: float = float(h2) / float(c2)
			# Первый годный такт записываем безусловно: иначе при идеальном
			# прогоне (все такты по 100%) в отчёт попадали бы нули-заглушки
			if samples == 1 or r2 < worst_ratio:
				worst_ratio = r2
				worst_can = c2
				worst_has = h2

	verdict("C1 упёршиеся в чужой строй вступают в бой, а не стоят",
		samples >= 3 and worst_ratio >= 0.7,
		"тактов с упором %d, худший — дерутся %d из %d (%.0f%%)"
			% [samples, worst_has, worst_can, worst_ratio * 100.0])

	# C2 — И ПРОТИВНИК ПРИ ЭТОМ ПОЛУЧАЕТ УРОН
	var lost: float = hp_foe0 - _total_hp(foes)
	verdict("C2 противник получает урон от упёршихся", lost > 0.0,
		"снято %.0f HP" % lost)

	# ── C3: ПРИЗНАК «ВЫХОЖУ ИЗ БОЯ» НЕ ОСТАВЛЯЕТ УПЁРШЕГОСЯ БЕЗ БОЯ ─────────
	# Сам признак живёт до прихода в точку приказа, и это правильно: отходящий
	# лучник не должен разворачиваться стрелять (за этим следит qa_disengage).
	# Проверяем ДРУГОЕ — что он не оставляет беззащитным того, кто НИКУДА НЕ
	# ИДЁТ, потому что упёрся в чужие тела. Такой боец обязан иметь цель
	var mute := 0
	var live_foes := _alive(foes)
	for u in _alive(mine):
		var uu := u as Unit
		var nr := INF
		for f in live_foes:
			nr = minf(nr, uu.global_position.distance_to((f as Node3D).global_position))
		if nr > uu.attack_range:
			continue
		# ПАНИКУЮЩИЙ НЕМ ПО ЗАМЫСЛУ (см. Unit._panicked): двадцать секунд он не
		# дерётся вовсе, и считать это провалом нельзя
		if uu.is_panicked():
			continue
		if uu._disengaging and uu.attack_target == null:
			mute += 1
	verdict("C3 упёршийся не остаётся немым из-за выхода из боя", mute == 0,
		"немых в контакте %d" % mute)

	for u in mine + foes:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(10)

# ═════════════════════════════════════════════════════════════════════════════
# B. ДЕСЯТЬ ОТРЯДОВ НА ОДНУ ХИЖИНУ
# ═════════════════════════════════════════════════════════════════════════════
## Сколько отрядов посылаем. Жалоба владельца — про «десяток отрядов»
const SIEGE_SQUADS := 10
const SIEGE_MEN := 15

func _block_siege() -> void:
	print("\n═════ B. ДЕСЯТЬ ОТРЯДОВ НА ОДНУ ХИЖИНУ ═════")
	var at := Vector3(220.0, 0.0, 220.0)
	var hut = load("res://scripts/goblin/GoblinHut.gd").new()
	hut.faction = Constants.FACTION_GOBLIN
	main.world_add(hut)
	hut.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	await frames(5)
	# ── ХИЖИНЕ ВЫДАЁТСЯ БОЛЬШОЙ ЗАПАС ЖИЗНИ ────────────────────────────────
	# Раздел меряет РАССТАНОВКУ, а не скорость сноса. Со штатной тысячей очков
	# сто пятьдесят копейщиков ломают хижину за считанные секунды, и последний
	# замер («устоялись ли») попадал бы уже на разбредающихся победителей
	hut.max_health = 200000.0
	hut.current_health = 200000.0

	var squads: Array = []
	var all: Array = []
	for k in range(SIEGE_SQUADS):
		var men := _squad("res://scenes/units/Spearman.tscn", "spearman",
			Constants.FACTION_PLAYER,
			at + Vector3(-30.0 + float(k % 5) * 2.4, 0.0, -26.0 + float(k / 5) * 4.0),
			SIEGE_MEN, 5)
		squads.append(men)
		all.append_array(men)
	await frames(20)

	# ПУТЬ ТОТ ЖЕ, ЧТО У КЛИКА: сначала сектора, потом приказ атаки
	var sel = main.selection_manager
	sel._clear_selection()
	for u in all:
		sel._select(u)
	sel._ring_squads_around(hut)
	for u in all:
		(u as Unit).command_attack(hut, true, true, true)

	var hp0: float = hut.current_health
	await frames(60 * 18)
	# Снимок центров ДО последних трёх секунд — по нему считаем «перебегают ли»
	var before: Array = []
	for men in squads:
		before.append(GameManager._centroid_of(_alive(men)))
	await frames(60 * 3)

	# B1 — ОТРЯДЫ РАЗВЕДЕНЫ, А НЕ СЛИПЛИСЬ В ТОЧКУ
	var centres: Array = []
	for men in squads:
		var a := _alive(men)
		if a.is_empty():
			continue
		centres.append(GameManager._centroid_of(a))
	var pairs := 0
	var worst := INF
	for i in range(centres.size()):
		for j in range(i + 1, centres.size()):
			var d: float = Vector2((centres[i] as Vector3).x - (centres[j] as Vector3).x,
				(centres[i] as Vector3).z - (centres[j] as Vector3).z).length()
			worst = minf(worst, d)
			if d < 2.0:
				pairs += 1
	verdict("B1 центры отрядов не сливаются в одну точку", pairs == 0,
		"перекрывающихся пар %d, ближайшие центры %.2f м" % [pairs, worst])

	# ── B2: ВТОРАЯ ЛИНИЯ ДЕРЖИТ ПОЗИЦИЮ ────────────────────────────────────
	# Прямое требование владельца: «при отсутствии свободного слота атаки
	# задние ряды должны ожидать или держать позицию». Меряем именно её.
	#
	# ПЕРЕДНЮЮ ЛИНИЮ ЭТОТ ЗАМЕР НЕ СУДИТ, и это не поблажка: у стены хижины
	# места хватает примерно на два десятка человек, а стоят там три отряда, и
	# крайние всё время переступают в поисках просвета. Это теснота боя, а не
	# «перебегают с места на место»; за передними следит B2б
	var held_worst := 0.0
	var held_n := 0
	var front_far := 0.0
	var front_n := 0
	for i in range(squads.size()):
		var a2 := _alive(squads[i])
		if a2.is_empty():
			continue
		var c2: Vector3 = GameManager._centroid_of(a2)
		var w2: Vector3 = before[i]
		var shift: float = Vector2(c2.x - w2.x, c2.z - w2.z).length()
		var to_hut: float = Vector2(c2.x - hut.global_position.x,
			c2.z - hut.global_position.z).length()
		if GameManager.squad_attack_hold(_sid(squads[i])):
			held_n += 1
			held_worst = maxf(held_worst, shift)
		else:
			front_n += 1
			front_far = maxf(front_far, to_hut)
	verdict("B2 вторая линия держит позицию, а не перебегает",
		held_n > 0 and held_worst < 0.6,
		"ждущих отрядов %d, худший сдвиг за 3 с %.2f м" % [held_n, held_worst])

	# B2б — ПЕРЕДНЯЯ ЛИНИЯ СТОИТ У СТЕНЫ, А НЕ КРУЖИТ ВОКРУГ ЗДАНИЯ.
	# Порог считается ГЕОМЕТРИЕЙ: полугабарит постройки плюс дистанция удара
	# плюс глубина отряда — дальше этого центр отряда, который бьёт стену,
	# оказаться не может
	var half_b: float = maxf(hut.build_size.x, hut.build_size.z) * 0.5
	var reach: float = half_b + (all[0] as Unit).attack_range + 2.5
	verdict("B2б передняя линия стоит у стены, а не кружит вокруг",
		front_n > 0 and front_far <= reach,
		"дальний из бьющих %.1f м при пороге %.1f м" % [front_far, reach])

	# B3 — ОСАДА ИДЁТ: постройку действительно бьют
	verdict("B3 хижину действительно бьют", hut.current_health < hp0,
		"снято %.0f HP из %.0f" % [hp0 - hut.current_health, hp0])

	# B4 — ВТОРАЯ ЛИНИЯ ЕСТЬ И ОНА ПОЗАДИ ПЕРВОЙ.
	# Проверяем СВОЙСТВО — разброс расстояний от хижины между отрядами больше
	# глубины одного отряда
	var rmin := INF
	var rmax := 0.0
	for c in centres:
		var d: float = Vector2((c as Vector3).x - hut.global_position.x,
			(c as Vector3).z - hut.global_position.z).length()
		rmin = minf(rmin, d)
		rmax = maxf(rmax, d)
	verdict("B4 у здания есть эшелонирование, а не одна куча",
		rmax - rmin > 3.0,
		"ближний центр %.1f м, дальний %.1f м" % [rmin, rmax])
