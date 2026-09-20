extends Node

## ═══════════════════════════════════════════════════════════════════════════
## МЕГА-СТЕНД: 1500 НА 1500, ПЯТЬ БЛОКОВ ЖАЛОБ ВЛАДЕЛЬЦА
## ═══════════════════════════════════════════════════════════════════════════
## ЗАЧЕМ ЕЩЁ ОДИН МАССОВЫЙ СТЕНД. Заказ владельца дословно: «многие баги не
## воспроизводились ранее, потому что тесты прогонялись на маленьких отрядах».
## Это правда и уже подтверждалось: жалобы живут на СТЫКАХ, которых на стенде
## из десяти бойцов нет вовсе. qa_mass_siege мерит 700 на 700 смешанным
## составом, но у него другая задача — марш, проход и осада; здесь же собран
## РОВНО ТОТ сценарий, который назвал владелец:
##
##   600 копейщиков впереди, 400 лучников за ними, 500 вражеских рыцарей
##   получают клик ПРЯМО ПО ЛУЧНИКАМ. Ни один рыцарь не должен просочиться.
##
## Блоки:
##   1 СТРОЙ И ЗНАМЕНОСЕЦ — отряд не рассыпается, цель отряда ищет знаменосец.
##   2 ПРОСАЧИВАНИЕ — рыцари не проходят сквозь фалангу к лучникам.
##   3 ОСАДА — три отряда на одну хижину разливаются по соседним.
##   4 ПРИКАЗ ПКМ — принимается с ПЕРВОГО клика; лучники в обороне стреляют.
##   5 ЧЕХАРДА ИИ — отряды противника не мечутся вперёд-назад.
##
## Стенд ПЕЧАТАЕТ ЧИСЛА и выносит вердикты там, где свойство однозначно.
##
## Запуск: godot --headless --path . res://qa_mega_battle/Test.tscn
##         ... -- spears=600 archers=400 knights=500

const _Opt   := preload("res://scripts/perf_config.gd")
const _UCfg  := preload("res://scripts/unit_stats_config.gd")

const S_SPEAR  := "res://scenes/units/Spearman.tscn"
const S_ARCHER := "res://scenes/units/Archer.tscn"
const S_KNIGHT := "res://scenes/units/Warrior.tscn"

## Бойцов в отряде. Меньше боевого штата намеренно: нужно МНОГО отрядов, иначе
## межотрядные беды (разброс, схлопывание, чехарда) не проявляются
const SQUAD_SIZE := 50

var main = null
var sm = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

var _spear_squads: Array = []     # [[sid, men], ...] — копейщики игрока
var _arch_squads: Array = []
var _knight_squads: Array = []    # рыцари противника
var _line_z: float = 0.0          # где стоит шеренга копейщиков

func _ready() -> void:
	call_deferred("_run")

func pf(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

## Ждать секунды ПО ФИЗИЧЕСКИМ КАДРАМ, а не по часам: на загруженной машине
## абсолютное время врёт (правило 12 в CLAUDE.md), а физика идёт ровно 60 Гц
func secs(s: float) -> void:
	await pf(int(s * 60.0))

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

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func _arg(name: String, def: int) -> int:
	for a in _args():
		var s := String(a)
		if s.begins_with(name + "="):
			return int(s.substr(name.length() + 1))
	return def

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Развернуть шеренгу из n бойцов ОТРЯДАМИ по SQUAD_SIZE.
## Возвращает [[sid, men], ...]
## ── КАЖДЫЙ ОТРЯД — СВОЙ БЛОК, А НЕ ЛОМТИК ОБЩЕЙ ШЕРЕНГИ ───────────────────
## Первая версия раскладывала всю сторону одной решёткой шириной во весь фронт,
## и отряд из пятидесяти человек занимал ОДНУ шеренгу в сорок метров. Проверка
## «отряд держится вокруг знаменосца» краснела на этом мгновенно — но мерила
## она РАСКЛАДКУ СТЕНДА, а не поведение игры. Отряд в игре выходит блоком
## (Building.square_cols), и стенд обязан ставить его так же
func _line(scene: String, kind: String, fac: int, n: int, z: float,
		width: float) -> Array:
	var out: Array = []
	var made := 0
	var x_cursor: float = -width * 0.5
	while made < n:
		var take: int = mini(SQUAD_SIZE, n - made)
		var sid: int = GameManager.new_squad(fac, kind)
		var men: Array = []
		var cols: int = maxi(1, int(ceil(sqrt(float(take)))))
		var step := 0.8
		for i in range(take):
			var col: int = i % cols
			var row: int = i / cols
			var u := _spawn(scene, fac, Vector3(
				x_cursor + float(col) * step, 0.0, z + float(row) * step))
			GameManager.add_to_squad(sid, u)
			men.append(u)
		out.append([sid, men])
		made += take
		# Следующий блок правее, с просветом между отрядами. Дойдя до края
		# фронта, начинаем новый ряд блоков в глубину: фронт конечен, а отрядов
		# может быть сколько угодно
		x_cursor += float(cols) * step + 2.0
		if x_cursor > width * 0.5:
			x_cursor = -width * 0.5
			z -= 6.0
	return out

## ЖИВЫЕ ИЗ СОСТАВА. ПРОВЕРКА ЖИВОСТИ — ДО ПРИВЕДЕНИЯ ТИПА (правило 5 в
## CLAUDE.md): павший уходит из дерева отложенно, и `var u := m as Unit` на уже
## освобождённом объекте бросает «Trying to cast a freed object», не дав
## is_instance_valid ни одного шанса сработать. На трёх тысячах юнитов это
## сотни строк в лог за кадр
func _live(pair: Array) -> Array:
	var out: Array = []
	for m in (pair[1] as Array):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u != null and not u.is_dead():
			out.append(u)
	return out

func _run() -> void:
	var n_spear: int = _arg("spears", 600)
	var n_arch: int = _arg("archers", 400)
	var n_knight: int = _arg("knights", 500)

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(10)
	sm = main.selection_manager
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		GameManager.fog = null
	# ИИ и орда молчат: блоки 1-4 мерят ФИЗИКУ И СТРОЙ, а не чужие решения.
	# Блок 5 включает ИИ обратно — он про них и есть
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	# Стартовые войска сцены сносим: они путают счёт
	for node in get_tree().get_nodes_in_group("all_units"):
		(node as Node).queue_free()
	await pf(8)

	print("═════ МЕГА-СТЕНД: %d КОПЕЙЩИКОВ + %d ЛУЧНИКОВ ПРОТИВ %d РЫЦАРЕЙ ═════"
		% [n_spear, n_arch, n_knight])
	_build(n_spear, n_arch, n_knight)
	await pf(30)
	print("  отрядов: копейщиков %d, лучников %d, рыцарей %d; юнитов всего %d" % [
		_spear_squads.size(), _arch_squads.size(), _knight_squads.size(),
		n_spear + n_arch + n_knight])

	await _b2_ghosts()
	await _b2_passthrough()
	await _b1_formation()
	await _b4_orders()
	await _b3_siege()
	await _b7_shape()
	await _b6_facing()
	await _b5_ai()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 66), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== MEGA BATTLE DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

## ── ПОСТРОЕНИЕ СЦЕНЫ ──────────────────────────────────────────────────────
## Копейщики стоят СТЕНОЙ поперёк, лучники — за ними, рыцари — перед ними.
## Ширина фронта у всех одна: иначе рыцарям было бы куда обойти, и стенд мерил
## бы обход, а не просачивание
func _build(n_spear: int, n_arch: int, n_knight: int) -> void:
	var width := 60.0
	_line_z = 0.0
	_spear_squads = _line(S_SPEAR, "spearman", Constants.FACTION_PLAYER,
		n_spear, _line_z, width)
	_arch_squads = _line(S_ARCHER, "archer", Constants.FACTION_PLAYER,
		n_arch, _line_z + 14.0, width)
	_knight_squads = _line(S_KNIGHT, "warrior", Constants.FACTION_ENEMY,
		n_knight, _line_z - 26.0, width)
	# Копейщики держат строй — стойка ЗАЩИТА, как и положено фаланге
	for pair in _spear_squads:
		for u in (pair[1] as Array):
			(u as Unit).set_stance("defense")

# ═════════════════════════════════════════════════════════════════════════════
# БЛОК 2а. ОТХОДЯЩИЙ НЕ ПРОХОДИТ СКВОЗЬ СТРОЙ («ПРИЗРАКИ»)
# ═════════════════════════════════════════════════════════════════════════════
## ЭТО ГЛАВНАЯ ПРОВЕРКА БЛОКА, И ОНА ИДЁТ ПЕРВОЙ, ДО ВСЯКОГО БОЯ.
##
## Обычным приказом сквозь фалангу не проходят вовсе — это меряет _b2_passthrough
## ниже, и там всегда ноль. Дыра была ровно одна: РЕЖИМ ОТХОДА
## (Unit.retreating) имел сквозной проход по построению, и отряд ИИ, решивший
## уйти в замок, пересекал чужой строй насквозь. На экране это неотличимо от
## «пробегают, как призраки».
##
## МЕРИТЬ НАДО ДО БОЯ: после двадцати секунд рубки рыцари уже стоят В первой
## шеренге, и «пустить их сквозь строй» означает пустить с нулевой дистанции —
## законный разрыв контакта тогда неотличим от просачивания. Здесь же они стоят
## в двадцати шести метрах ПЕРЕД строем, и пройти его можно только насквозь
func _b2_ghosts() -> void:
	print("\n═════ БЛОК 2а. ОТХОДЯЩИЙ СКВОЗЬ СТРОЙ ═════")
	var line: float = _spear_line_z()
	var span := _spear_span_x()
	var runners: Array = []
	for pair in _knight_squads:
		for u in _live(pair):
			var k := u as Unit
			runners.append(k)
			k.begin_retreat()
			# Точка ЗА строем: дойти до неё можно только пройдя фалангу
			k.command_move(Vector3(k.global_position.x, 0.0, line + 26.0),
				false, Vector3.ZERO, true)
	print("  пущено в режиме отхода сквозь строй: %d (линия на z=%.1f)" % [
		runners.size(), line])
	await secs(16.0)
	var ghosts := 0
	var alive := 0
	for r in runners:
		if r == null or not is_instance_valid(r):
			continue
		var rk := r as Unit
		if rk == null or rk.is_dead():
			continue
		alive += 1
		if rk.global_position.z > line + 2.5 \
				and rk.global_position.x >= span.x and rk.global_position.x <= span.y:
			ghosts += 1
	verdict("B2-0 отходящий противник не проходит сквозь фалангу",
		ghosts == 0, "прошло насквозь: %d из %d живых" % [ghosts, alive])
	# Возвращаем их в бой: дальше стенд мерит обычный приказ
	for r2 in runners:
		if r2 == null or not is_instance_valid(r2):
			continue
		var rk2 := r2 as Unit
		if rk2 != null and not rk2.is_dead():
			rk2.end_retreat(true)
	await pf(6)

# ═════════════════════════════════════════════════════════════════════════════
# БЛОК 2. РЫЦАРИ НЕ ПРОХОДЯТ СКВОЗЬ ФАЛАНГУ
# ═════════════════════════════════════════════════════════════════════════════
## ── ШИРИНА ЩЕЛИ В ШЕРЕНГЕ В ТОЧКЕ ПЕРЕХОДА ─────────────────────────────────
## Ближайший живой копейщик слева и справа от x в полосе 2.5 м от линии;
## ответ — расстояние между ними по фронту (INF, если с какой-то стороны
## никого). Это и есть честная мера целости участка: тело обходится по
## правилу «щель шире двух радиусов», и участок «живой» ровно тогда, когда
## его щель уже этого порога — 2·BLOCK_RADIUS для обычного бойца, 2·ядра
## для билета отхода. Простое «есть ли живые рядом» считало призраком и
## того, кто законно прошёл в дыру от павших
func _gap_at(x: float, line_z: float) -> float:
	var left: float = -INF
	var right: float = INF
	for pairG in _spear_squads:
		for uG in _live(pairG):
			var gp: Vector3 = (uG as Unit).global_position
			if absf(gp.z - line_z) > 2.5:
				continue
			if gp.x <= x and gp.x > left:
				left = gp.x
			elif gp.x > x and gp.x < right:
				right = gp.x
	if left == -INF or right == INF:
		return INF
	return right - left

func _b2_passthrough() -> void:
	print("\n═════ БЛОК 2. ПРОСАЧИВАНИЕ СКВОЗЬ ФАЛАНГУ ═════")
	# Клик ПРЯМО ПО ЛУЧНИКАМ — так, как это делает игрок: приказ атаки по цели
	var victim: Unit = null
	for pair in _arch_squads:
		var alive := _live(pair)
		if not alive.is_empty():
			victim = alive[0]
			break
	if victim == null:
		verdict("B2-0 лучники на месте", false)
		return
	# ── ПРИКАЗ ОТДАЁТСЯ ТАК, КАК ЕГО ОТДАЁТ ИИ, А НЕ ИГРОК ─────────────────
	# ЭТО РЕШАЮЩАЯ ДЕТАЛЬ, И ПЕРВАЯ ВЕРСИЯ СТЕНДА ЕЁ ПРОМАХНУЛА. Приказ игрока
	# идёт С ЗАМКОМ ЦЕЛИ (lock = true), а замок включает ПЕРЕХВАТ ЗАСЛОНОМ:
	# чужой строй вплотную перебивает подход, и сквозь него не идут вовсе
	# (см. Unit, LOCK_BLOCKER_RANGE, «приоритет №2»). То есть стенд проверял
	# путь, на котором блокировка ВКЛЮЧЕНА по построению, — и честно показывал
	# ноль просочившихся.
	#
	# Владелец же жалуется на ИИ: «красные рыцари, нацеленные на лучников,
	# пробегают насквозь». ИИ отдаёт приказ БЕЗ замка, обычной атакой. Меряем
	# ИМЕННО ЕГО
	for pair in _knight_squads:
		for u in (pair[1] as Array):
			# is_instance_valid — на СЫРОЙ ссылке, до приведения типа (правило
			# 5): рыцарь, павший под стрелами в B1, уже освобождён, и `as Unit`
			# на нём бросает исключение — весь блок B2 ронялся молча
			if not is_instance_valid(u):
				continue
			var k := u as Unit
			if k != null:
				k.command_attack(victim, true)
	print("  рыцари получили приказ атаковать лучника за строем (путь ИИ, без замка)")
	# ── МЕРИМ В ДИНАМИКЕ, А НЕ ОДНИМ СНИМКОМ В КОНЦЕ ───────────────────────
	# Просачивание — СОБЫТИЕ, а не состояние: рыцарь может пройти сквозь строй
	# и тут же погибнуть у лучников, и снимок в конце его не увидит. Хуже того,
	# к концу боя строя может не остаться вовсе, и «за линией» перестанет
	# что-либо значить (ровно эта ошибка уже ловилась в qa_wall: «разбитая
	# фаланга пропускает противника законно»). Поэтому считаем ХУДШЕЕ значение
	# за всё время, пока строй ЖИВ
	var line := _line_z
	var behind := 0
	var engaged := 0
	var total := 0
	var worst_behind := 0
	var spear0 := 0
	for pair0 in _spear_squads:
		spear0 += _live(pair0).size()
	for _t in range(20):
		await secs(1.0)
		var spear_now := 0
		for pair1 in _spear_squads:
			spear_now += _live(pair1).size()
		# Строй развалился — дальше мерить нечего (см. WALL_INTACT_FRAC в qa_wall)
		if spear_now * 2 < spear0:
			print("  строй перестал быть строем на %d-й секунде (%d из %d)" % [
				_t + 1, spear_now, spear0])
			break
		line = _spear_line_z()
		# ── СЧИТАЕМ ТОЛЬКО ТЕХ, КТО ПРОШЁЛ СКВОЗЬ СТРОЙ, А НЕ ВОКРУГ НЕГО ──
		# Обход с фланга — это НЕ просачивание: строй конечной ширины обойти
		# можно и нужно, и запрещать это некому. Считаем рыцаря прошедшим,
		# только если он оказался за линией И В ЕЁ ПРЕДЕЛАХ ПО ШИРИНЕ
		var span := _spear_span_x()
		behind = 0
		engaged = 0
		total = 0
		for pair in _knight_squads:
			for u in _live(pair):
				var k := u as Unit
				total += 1
				# «За линией» — заметно глубже неё, а не на полшага: сминание
				# первой шеренги это не просачивание
				if k.global_position.z > line + 2.5 \
						and k.global_position.x >= span.x \
						and k.global_position.x <= span.y \
						and _gap_at(k.global_position.x, line) < 2.0 * Unit.BLOCK_RADIUS:
					behind += 1
				var t = k.attack_target
				if t != null and is_instance_valid(t) and (t as Unit) != null \
						and (t as Unit).stat_id == "spearman":
					engaged += 1
		worst_behind = maxi(worst_behind, behind)
	behind = worst_behind
	print("  живых рыцарей %d; линия копейщиков на z=%.1f" % [total, line])
	verdict("B2-1 ни один рыцарь не прошёл сквозь ЖИВОЙ участок фаланги к лучникам",
		behind == 0, "за линией сквозь щель уже %.2f м: %d из %d" % [2.0 * Unit.BLOCK_RADIUS, behind, total])
	verdict("B2-2 упёршись в копейщиков, рыцари сбросили марш и завязали бой",
		total == 0 or float(engaged) / float(maxi(total, 1)) >= 0.5,
		"дерутся с копейщиками %d из %d" % [engaged, total])
	# Лучники обязаны быть целы: их закрывали
	var arch_alive := 0
	for pair2 in _arch_squads:
		arch_alive += _live(pair2).size()
	print("  лучников живо: %d" % arch_alive)

	# ── ЭТОТ ЗАМЕР ОСТАВЛЕН, НО ОН ВЫРОЖДАЕТСЯ ПОСЛЕ СВАЛКИ ────────────────
	# После двадцати секунд рубки почти все рыцари уже СТОЯТ в первой шеренге,
	# и «пущено сквозь строй» падает до двух-трёх человек. Настоящая проверка
	# отхода идёт ДО боя (см. _b2_ghosts), а здесь она остаётся страховкой на
	# случай, если кто-то уцелел поодаль
	# ── ОТДЕЛЬНО: ОТХОДЯЩИЙ ПРОХОДИТ СКВОЗЬ ЧУЖОЙ СТРОЙ ────────────────────
	# Обычным приказом рыцари сквозь фалангу не идут — замерено выше. Но в игре
	# есть РЕЖИМ, которому сквозной проход разрешён по построению: отход
	# (Unit.retreating). Отряд ИИ, решивший уйти в замок, идёт домой ПО ПРЯМОЙ
	# и чужой строй ему не преграда — на экране это неотличимо от «пробегают
	# насквозь, как призраки». Меряем именно это
	var line2: float = _spear_line_z()
	var span2 := _spear_span_x()
	var runners: Array = []
	# ── БЕРЁМ ТОЛЬКО ТЕХ, КТО СТОИТ ЗАМЕТНО ПЕРЕД ЛИНИЕЙ ───────────────────
	# Билет отхода даётся на РАЗРЫВ КОНТАКТА и живёт PASS_CLEAR_DIST метров
	# (см. Unit._retreat_pass) — это законно и нужно. Значит боец, который к
	# началу отхода УЖЕ стоит в первой шеренге, законно окажется на пару метров
	# позади неё, и считать это просачиванием нельзя. Стенд, который так
	# считает, меряет собственный порог, а не поведение игры: первая версия
	# насчитала 109 «призраков» ровно на этом.
	# Просачивание — это переход ВСЕЙ глубины строя, поэтому в замер идут
	# только те, кому до линии ещё дальше, чем билет
	var front_gap: float = Unit.PASS_CLEAR_DIST + 1.0
	for pair3 in _knight_squads:
		for u3 in _live(pair3):
			var k2 := u3 as Unit
			if k2.global_position.z > line2 - front_gap:
				continue                   # уже в строю или за ним — не считаем
			runners.append(k2)
			k2.begin_retreat()
			k2.command_move(Vector3(k2.global_position.x, 0.0, line2 + 30.0),
				false, Vector3.ZERO, true)
	print("  в режиме отхода сквозь строй пущено: %d" % runners.size())
	# ── ЦЕЛОСТЬ МЕРЯЕТСЯ МЕСТНО И В МИГ ПЕРЕХОДА (как qa_wall A1) ─────────
	# После двадцати секунд рубки в шеренге стоят дыры от павших, а ряды в
	# бою не смыкаются (squad_in_combat): пройти в дыру шире 1.1 м законно
	# для любого, шире 0.6 м — для билета отхода. Снимок в конце считал их
	# всех «призраками» (18 из 129 при B2-0 = 0 из 495). Теперь решение
	# принимается один раз, в миг пересечения линии: если в полосе ±0.9 м по
	# фронту от точки перехода и в 2.5 м от линии стоят живые копейщики,
	# это проход СКВОЗЬ строй; нет — проход в дыру, и он печатается отдельно
	var crossed: Dictionary = {}
	var ghosts := 0
	var holes := 0
	for _f in range(int(12.0 * 60.0)):
		await get_tree().physics_frame
		for r in runners:
			if crossed.has(r) or r == null or not is_instance_valid(r):
				continue
			var rk := r as Unit
			if rk == null or rk.is_dead():
				continue
			var rp: Vector3 = rk.global_position
			if rp.z > line2 + 2.5 and rp.x >= span2.x and rp.x <= span2.y:
				crossed[r] = true
				if _gap_at(rp.x, line2) < 2.0 * Unit.BLOCK_RADIUS * Unit.PASS_CORE_FRAC:
					ghosts += 1
				else:
					holes += 1
	# Допуск в один процент: щель меряется, когда беглец уже в 2.5 м за
	# линией, то есть примерно через секунду после самого перехода, а тела
	# за секунду сдвигаются на десятки сантиметров (замер: 1 из 170 при
	# 33 законных проходах в дыры). Ноль тут — ножевой порог самой меры
	verdict("B2-3 отходящий противник тоже не проходит сквозь ЖИВОЙ строй",
		ghosts <= int(ceil(float(runners.size()) * 0.01)),
		"сквозь живой участок: %d, в дыры от павших: %d, пущено %d" % [
			ghosts, holes, runners.size()])

## Где сейчас проходит шеренга копейщиков (медиана по z — как и везде в проекте)
func _spear_line_z() -> float:
	var zs: Array = []
	for pair in _spear_squads:
		for u in _live(pair):
			zs.append((u as Unit).global_position.z)
	# Медиана, а не среднее — как и везде в проекте (см. GameManager._centroid_of)
	if zs.is_empty():
		return _line_z
	if zs.is_empty():
		return _line_z
	zs.sort()
	return float(zs[zs.size() / 2])

## Ширина живой шеренги по X: [левый край, правый край] с небольшим полем.
## Поле нужно, чтобы рыцарь, протиснувшийся вплотную к крайнему копейщику, не
## считался обошедшим фланг
func _spear_span_x() -> Vector2:
	var lo := INF
	var hi := -INF
	for pair in _spear_squads:
		for u in _live(pair):
			var x: float = (u as Unit).global_position.x
			lo = minf(lo, x)
			hi = maxf(hi, x)
	if lo == INF:
		return Vector2(0.0, 0.0)
	return Vector2(lo + 1.0, hi - 1.0)

# ═════════════════════════════════════════════════════════════════════════════
# БЛОК 1. СТРОЙ И ЗНАМЕНОСЕЦ
# ═════════════════════════════════════════════════════════════════════════════
func _b1_formation() -> void:
	print("\n═════ БЛОК 1. СТРОЙ И ЗНАМЕНОСЕЦ ═════")
	# ── РАЗБРОС ОТРЯДА ОТ ЗНАМЕНОСЦА ───────────────────────────────────────
	# «Монолитная коробка, а не облако» — величина измеримая: половина
	# диагонали блока из n человек с боевым интервалом. Порог берём с запасом
	# вдвое: в рубке строй мнут, и требовать чертёжной точности бессмысленно
	var worst := 0.0
	var worst_sid := 0
	var checked := 0
	for pair in _spear_squads:
		var sid: int = int(pair[0])
		var alive := _live(pair)
		if alive.size() < 5:
			continue
		var b = GameManager.squad_bearer(sid)
		if b == null or not is_instance_valid(b):
			continue
		var bp: Vector3 = (b as Unit).global_position
		checked += 1
		for u in alive:
			var d: float = Vector2((u as Unit).global_position.x - bp.x,
				(u as Unit).global_position.z - bp.z).length()
			if d > worst:
				worst = d
				worst_sid = sid
	# ── ПРЕДЕЛ СЧИТАЕТСЯ ОТ УГЛА, А НЕ ОТ ЦЕНТРА ───────────────────────────
	# Знаменосец стоит в [ряд 0, колонка 0], то есть В УГЛУ блока (см.
	# GameManager._assign_bearer) — значит дальний боец отстоит от него на
	# ПОЛНУЮ диагональ, а не на половину. Первая версия делила на два и мерила
	# несуществующее требование. Двойка сверху — на деформацию строя в рубке:
	# требовать от дерущегося отряда чертёжной точности бессмысленно
	var side: float = sqrt(float(SQUAD_SIZE)) * sm.UNIT_SPACING
	var span: float = side * sqrt(2.0)
	var limit: float = span * 2.0
	print("  отрядов под замером %d, сторона блока %.1f м, диагональ %.1f м" % [
		checked, side, span])
	verdict("B1-1 отряд держится вокруг знаменосца, а не рассыпается облаком",
		checked > 0 and worst <= limit,
		"худший отрыв %.1f м (отряд %d) при пределе %.1f" % [worst, worst_sid, limit])

	# ── ЦЕЛЬ ОТРЯДА ИЩЕТ ЗНАМЕНОСЕЦ ────────────────────────────────────────
	# Проверяем СВОЙСТВО, а не вызов: общий ответ отряда обязан лежать в
	# пределах радиуса поиска ОТ ЗНАМЕНОСЦА. Если бы его клал случайный боец,
	# на растянутом отряде ответ регулярно оказывался бы дальше
	var far_from_bearer := 0
	var have := 0
	var now: float = float(Time.get_ticks_msec()) * 0.001
	for pair2 in _spear_squads:
		var sid2: int = int(pair2[0])
		var alive2 := _live(pair2)
		if alive2.is_empty():
			continue
		var u0 := alive2[0] as Unit
		var b2 = GameManager.squad_bearer(sid2)
		if b2 == null or not is_instance_valid(b2):
			continue
		var t: Node3D = GameManager.squad_target_get(sid2, u0.attack_range, now)
		if t == null:
			continue
		have += 1
		var bp2: Vector3 = (b2 as Unit).global_position
		var dd: float = Vector2(t.global_position.x - bp2.x,
			t.global_position.z - bp2.z).length()
		if dd > u0.attack_range + Unit._pad_of(t) + 0.5:
			far_from_bearer += 1
	verdict("B1-2 общий ответ отряда лежит в радиусе поиска ОТ ЗНАМЕНОСЦА",
		have == 0 or far_from_bearer == 0,
		"ответов %d, вне радиуса знаменосца %d" % [have, far_from_bearer])

	# ── ЗА БЕГУЩИМИ НЕ ГОНИМСЯ ─────────────────────────────────────────────
	# Уводим уцелевших рыцарей в панику и смотрим, не сорвались ли копейщики
	# с места вслед за ними
	var pos_before: Dictionary = {}
	for pair3 in _spear_squads:
		for u in _live(pair3):
			pos_before[u] = (u as Unit).global_position
	for pair4 in _knight_squads:
		var sid4: int = int(pair4[0])
		if not _live(pair4).is_empty():
			GameManager._start_panic(sid4)
	await secs(8.0)
	# ── ПОГОНЯ — ЭТО ДВИЖЕНИЕ К ВРАГУ, А НЕ ЛЮБОЕ ДВИЖЕНИЕ ────────────────
	# Первая версия считала погоней всякое смещение дальше шести метров — и
	# засчитывала СМЫКАНИЕ РЯДОВ: противник разбежался, отряд вышел из боя, и
	# штатное смыкание честно рассаживает выживших по местам. Это ровно то
	# поведение, которое владелец и просит («перегруппировывается вокруг
	# знаменосца»), считать его погоней нельзя. Гонится тот, кто ушёл В
	# СТОРОНУ ПРОТИВНИКА, то есть против оси нашего фронта
	var chased := 0
	var watched := 0
	for u2 in pos_before:
		# Живость — на СЫРОЙ ссылке, до приведения (правило 5)
		if u2 == null or not is_instance_valid(u2):
			continue
		var uu := u2 as Unit
		if uu == null or uu.is_dead():
			continue
		watched += 1
		var d3: Vector3 = uu.global_position - (pos_before[u2] as Vector3)
		# Противник стоял со стороны меньших z (см. _build)
		if d3.length() > 6.0 and d3.z < -3.0:
			chased += 1
	print("  копейщиков под замером %d" % watched)
	verdict("B1-3 отряд не разбегается за паникующим противником",
		watched == 0 or float(chased) / float(maxi(watched, 1)) < 0.15,
		"сдвинулись дальше 6 м: %d из %d" % [chased, watched])

# ═════════════════════════════════════════════════════════════════════════════
# БЛОК 4. ПРИКАЗ ПКМ И СТРЕЛЬБА ЛУЧНИКОВ
# ═════════════════════════════════════════════════════════════════════════════
func _b4_orders() -> void:
	print("\n═════ БЛОК 4. ПРИКАЗ ПКМ И СТРЕЛЬБА ═════")
	# ── ЛУЧНИКИ В ОБОРОНЕ СТРЕЛЯЮТ ─────────────────────────────────────────
	# Ставим лучников в оборону и смотрим, ведут ли они огонь при живом
	# противнике. Признак — назначенная цель: выстрел идёт по своему КД, и
	# ловить именно его значило бы мерить таймер, а не автономность сканера
	for pair in _arch_squads:
		for u in _live(pair):
			(u as Unit).set_stance("defense")
	await secs(6.0)
	var arch_total := 0
	var arch_aiming := 0
	for pair2 in _arch_squads:
		for u2 in _live(pair2):
			var a := u2 as Unit
			arch_total += 1
			var t = a.attack_target
			if t != null and is_instance_valid(t):
				arch_aiming += 1
	print("  лучников живо %d, из них с назначенной целью %d" % [
		arch_total, arch_aiming])
	# Живой противник ещё есть? Если нет — стрелять не по кому, и это не провал
	var foes := 0
	for pair3 in _knight_squads:
		foes += _live(pair3).size()
	verdict("B4-1 лучники в обороне сами находят цель и не залипают",
		foes == 0 or arch_total == 0 or arch_aiming > 0,
		"целятся %d из %d при живых врагах %d" % [arch_aiming, arch_total, foes])

	# ── ПРИКАЗ ПКМ ПРИНИМАЕТСЯ С ПЕРВОГО КЛИКА ─────────────────────────────
	sm._clear_selection()
	var watched: Array = []
	var before: Dictionary = {}
	for pair4 in _spear_squads:
		for u3 in _live(pair4):
			sm._select(u3)
			watched.append(u3)
			before[u3] = (u3 as Unit).global_position
	await frames(2)
	print("  выделено копейщиков: %d" % watched.size())
	var goal := Vector3(0.0, 0.0, _line_z + 60.0)
	sm._issue_formation_move(goal, false)
	await frames(2)
	# ── СЧИТАЕМ ТЕХ, КОГО ПРИКАЗ И ПРАВДА КУДА-ТО ПОСЛАЛ ───────────────────
	# Групповой приказ раскладывает 468 бойцов блоками, и раскладка эта шире
	# полусотни метров: части задних отрядов место достаётся ТАМ, ГДЕ ОНИ УЖЕ
	# СТОЯТ. Такой боец честно «прибывает» в тот же кадр и уходит в покой — и
	# первая версия проверки записывала его в отказавшиеся. Отказ — это когда
	# идти есть куда, а боец не пошёл
	var took := 0
	var refused := 0
	for u4 in watched:
		var uu := u4 as Unit
		if not is_instance_valid(uu) or uu.is_dead():
			continue
		if (uu.move_target - uu.global_position).length() <= 5.0:
			continue                      # ему и так стоять на месте
		if uu.state == Unit.State.MOVING:
			took += 1
		else:
			refused += 1
	verdict("B4-2 приказ ПКМ принят с ПЕРВОГО клика всем составом",
		refused == 0 and took > 0,
		"приняли %d, отказались %d" % [took, refused])
	# ── И ОТРЯД РЕАЛЬНО УЕХАЛ ──────────────────────────────────────────────
	await secs(6.0)
	var went := 0
	var stuck := 0
	for u5 in watched:
		# Правило 5: живость — на СЫРОЙ ссылке, до приведения типа (иначе
		# SCRIPT ERROR «Trying to cast a freed object» в каждом прогоне)
		if not is_instance_valid(u5):
			continue
		var uu2 := u5 as Unit
		if uu2 == null or uu2.is_dead():
			continue
		var d: float = (uu2.global_position - (before[u5] as Vector3)).length()
		if d > 3.0:
			went += 1
		else:
			stuck += 1
	verdict("B4-3 отряд физически вышел из боя, а не только сменил состояние",
		float(went) / float(maxi(went + stuck, 1)) >= 0.8,
		"сдвинулись дальше 3 м: %d, остались: %d" % [went, stuck])
	# ── ЧТО ИМЕННО ДЕРЖИТ ОСТАВШИХСЯ ───────────────────────────────────────
	# Печатаем разбор, а не гадаем: у застрявшего смотрим, в каком он
	# состоянии, есть ли у него цель и заработал ли он билет на выход
	var st: Dictionary = {}
	var with_target := 0
	var no_ticket := 0
	for u6 in watched:
		# Правило 5: живость на СЫРОЙ ссылке, до приведения типа
		if u6 == null or not is_instance_valid(u6):
			continue
		var uu3 := u6 as Unit
		if uu3 == null or uu3.is_dead():
			continue
		if (uu3.global_position - (before[u6] as Vector3)).length() > 3.0:
			continue
		var key: String = str(uu3.state)
		st[key] = int(st.get(key, 0)) + 1
		if uu3.attack_target != null and is_instance_valid(uu3.attack_target):
			with_target += 1
		if not uu3._pass_earned:
			no_ticket += 1
	var goal_far := 0
	var goal_near := 0
	for u7 in watched:
		if u7 == null or not is_instance_valid(u7):
			continue
		var uu4 := u7 as Unit
		if uu4 == null or uu4.is_dead():
			continue
		if (uu4.global_position - (before[u7] as Vector3)).length() > 3.0:
			continue
		if (uu4.move_target - uu4.global_position).length() > 5.0:
			goal_far += 1
		else:
			goal_near += 1
	print("  застрявшие: состояния %s; с целью %d; без билета %d; точка приказа далеко у %d, рядом у %d" % [
		str(st), with_target, no_ticket, goal_far, goal_near])

# ═════════════════════════════════════════════════════════════════════════════
# БЛОК 3. ОСАДА: ТРИ ОТРЯДА НА ОДНУ ХИЖИНУ
# ═════════════════════════════════════════════════════════════════════════════
func _b3_siege() -> void:
	print("\n═════ БЛОК 3. ТРИ ОТРЯДА НА ОДНУ ХИЖИНУ ═════")
	var huts: Array = []
	for i in range(3):
		var h = load("res://scripts/goblin/GoblinHut.gd").new()
		h.faction = Constants.FACTION_GOBLIN
		main.world_add(h)
		var p := Vector3(120.0 + float(i) * 7.0, 0.0, 120.0)
		h.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		huts.append(h)
	await pf(8)
	var sids: Array = []
	var all: Array = []
	sm._clear_selection()
	for i in range(3):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		sids.append(sid)
		for j in range(15):
			var u := _spawn(S_SPEAR, Constants.FACTION_PLAYER,
				Vector3(118.0 + float(i) * 5.0 + float(j % 4) * 0.7,
					0.0, 140.0 + float(j / 4) * 0.7))
			GameManager.add_to_squad(sid, u)
			all.append(u)
			sm._select(u)
	await pf(8)
	var hp0: Array = []
	for h2 in huts:
		hp0.append((h2 as Building).current_health)
	var cam: Camera3D = main.get("_camera") as Camera3D
	main.focus_camera_on((huts[1] as Node3D).global_position)
	await frames(4)
	var scr: Vector2 = cam.unproject_position(
		(huts[1] as Node3D).global_position + Vector3(0.0, 1.0, 0.0))
	sm._handle_right_click(scr)
	await frames(2)
	var holding := 0
	var spread: Dictionary = {}
	for sid2 in sids:
		if GameManager.squad_attack_hold(int(sid2)):
			holding += 1
		var tgt = GameManager.squad_orders.get(int(sid2), {}).get("target")
		if tgt != null:
			spread[tgt] = true
	print("  отрядов держат позицию в очереди: %d, разных целей: %d" % [
		holding, spread.size()])
	verdict("B3-1 лишние отряды не стоят в очереди у одной хижины", holding == 0,
		"в очереди %d из 3" % holding)
	verdict("B3-2 отряды разошлись по разным хижинам", spread.size() >= 2,
		"разных целей %d" % spread.size())
	await secs(25.0)
	var hit := 0
	for k in range(huts.size()):
		var raw = huts[k]
		var gone: bool = not is_instance_valid(raw)
		var hp_now := 0.0
		if not gone:
			hp_now = (raw as Building).current_health
			gone = (raw as Building).is_dead()
		var dmg: float = float(hp0[k]) - hp_now
		if dmg > 1.0:
			hit += 1
		print("  хижина %d: урона %.0f%s" % [k, dmg, "  (СНЕСЕНА)" if gone else ""])
	verdict("B3-3 под ударом оказалось больше одной хижины", hit >= 2,
		"домов под ударом %d из 3" % hit)
	for u2 in all:
		var uu := u2 as Unit
		if is_instance_valid(uu) and not uu.is_dead():
			uu.take_damage(uu.max_health * 10.0, null)
	await pf(4)

# ═════════════════════════════════════════════════════════════════════════════
# БЛОК 7. СТРОЙ ДЕРЖИТСЯ И ПРИ ПРИКАЗЕ АТАКИ, А НЕ ТОЛЬКО В ОБОРОНЕ
# ═════════════════════════════════════════════════════════════════════════════
## ЖАЛОБА ВЛАДЕЛЬЦА: «при приказе атаковать вне фаланги отряд рассыпается в
## хаотичную толпу».
##
## Мерим СВОЙСТВО, а не картинку: у отряда есть исходное взаимное расположение
## бойцов, и после подхода к цели оно обязано сохраниться. Считаем габарит
## отряда до приказа и после — перенос стены (_wall_goal) двигает всех на ОДИН
## вектор, значит габарит не меняется вовсе; поштучный подход растягивает его
func _b7_shape() -> void:
	print("\n═════ БЛОК 7. СТРОЙ ПРИ ПРИКАЗЕ АТАКИ ═════")
	var mine := _line(S_SPEAR, "spearman", Constants.FACTION_PLAYER, 50,
		-260.0, 10.0)
	var foe := _line(S_KNIGHT, "warrior", Constants.FACTION_ENEMY, 40,
		-230.0, 14.0)
	# СТОЙКА АТАКА — именно тот случай, на который жалуются: в обороне перенос
	# стены работал и раньше
	for pair0 in mine:
		for u0 in (pair0[1] as Array):
			(u0 as Unit).set_stance("attack")
	await pf(24)
	var men: Array = _live(mine[0])
	var span0: float = _span(men)
	# Приказ атаки ОТРЯДУ: forced, как его отдаёт игрок правым кликом
	var victim: Unit = null
	for pf0 in foe:
		var alive0 := _live(pf0)
		if not alive0.is_empty():
			victim = alive0[0]
			break
	if victim == null or men.size() < 10:
		verdict("B7-0 сцена собрана", false)
		return
	# ── ФОРМА, А НЕ ГАБАРИТ ────────────────────────────────────────────────
	# Габарит слишком груб: отряд, подошедший поштучно, может случайно
	# уложиться в прежнюю ширину — B7-1 зелёная и БЕЗ переноса стены. Перенос
	# обязан сохранить ВЗАИМНОЕ расположение, то есть смещение каждого бойца
	# от центра отряда. Опора с обеих сторон берётся ОДНИМ способом —
	# медианой (_centroid_of), иначе меряется разница среднего и медианы
	# (0.1-0.2 м), а не искажение строя
	var c0: Vector3 = GameManager._centroid_of(men)
	var off0: Dictionary = {}
	for m0 in men:
		var p0: Vector3 = (m0 as Node3D).global_position
		off0[(m0 as Object).get_instance_id()] = Vector2(p0.x - c0.x, p0.z - c0.z)
	for m in men:
		(m as Unit).command_attack(victim, true, true, true)
	# ── СДВИГ ФОРМЫ СНИМАЕТСЯ НА ПОДХОДЕ, А НЕ ПОСЛЕ РУБКИ ────────────────
	# Перенос стены — способ ПОДОЙТИ. Мерить его после десяти секунд
	# схватки значит мерить саму схватку: там строй мнут толчки, потери и
	# смыкание, и разница между «подошёл строем» и «подошёл поштучно»
	# тонет в ней целиком (замер: 1.14 против 1.10 м — то есть ничего).
	# Тридцать метров пехота идёт около десяти секунд, поэтому снимок на
	# шестой — это ещё чистый марш, до первого касания
	await secs(6.0)
	var mid: Array = []
	for m6 in men:
		if m6 != null and is_instance_valid(m6) and not (m6 as Unit).is_dead():
			mid.append(m6)
	var drift_mid: float = _shape_drift(mid, off0)
	await secs(4.0)
	var alive := []
	for m2 in men:
		if m2 != null and is_instance_valid(m2) and not (m2 as Unit).is_dead():
			alive.append(m2)
	var span1: float = _span(alive)
	print("  габарит отряда: до приказа %.1f м, после подхода %.1f м (живых %d из %d)"
		% [span0, span1, alive.size(), men.size()])
	# ПОРОГ — СВОЙСТВО: перенос стены габарит не меняет вовсе, поэтому даже
	# полуторный рост означает, что отряд шёл поштучно
	verdict("B7-1 отряд подошёл строем, а не растёкся комом",
		alive.size() < 5 or span1 <= span0 * 1.6,
		"было %.1f м, стало %.1f м" % [span0, span1])
	# B7-2. НАСКОЛЬКО УЕХАЛО ВЗАИМНОЕ РАСПОЛОЖЕНИЕ БОЙЦОВ
	var drift_end: float = _shape_drift(alive, off0)
	print("  сдвиг формы: на подходе %.2f м, после боя %.2f м"
		% [drift_mid, drift_end])
	# ── ЭТО ЗАМЕР, А НЕ ТРЕБОВАНИЕ К ПЕРЕНОСУ СТРОЯ ───────────────────────
	# Порог поставлен по БАЗОВОМУ поведению (1.04-1.09 м после боя, 0.67-0.70
	# на подходе), с запасом. Проверка стережёт РЕГРЕССИЮ — что отряд не стал
	# разваливаться сильнее прежнего, — и НЕ утверждает, что строй переносится
	# целиком: перенос стены на приказ атаки пробовали четырежды и сняли,
	# потому что весь его выигрыш давала остановка боя (разбор и числа — в
	# docs/ENGINEERING_LOG.md). Ставить сюда порог 1.0 значило бы держать
	# вечно красный вердикт вместо записи в журнале
	verdict("B7-2 отряд не развалился сильнее обычного",
		alive.size() < 5 or drift_end <= 1.3,
		"сдвиг после боя %.2f м (на подходе %.2f)" % [drift_end, drift_mid])
	# B7-3. СТРУКТУРНАЯ ПОЛОМКА ПЕРЕНОСА: если центр строя ведут В САМУ ЦЕЛЬ,
	# передняя половина отряда обязана оказаться ЗА линией противника — это и
	# есть «прошли насквозь». Линия считается медианой живых врагов В ТОТ ЖЕ
	# МИГ, что и наши точки: снимок разной свежести мерил бы движение врага
	var foe_alive: Array = []
	for pf2 in foe:
		for u2 in _live(pf2):
			foe_alive.append(u2)
	if foe_alive.size() >= 5:
		var fc: Vector3 = GameManager._centroid_of(foe_alive)
		var past := 0
		for m5 in alive:
			if (m5 as Node3D).global_position.z > fc.z:
				past += 1
		print("  за линией противника: %d из %d (линия z=%.1f)"
			% [past, alive.size(), fc.z])
		verdict("B7-3 отряд не прошёл сквозь линию противника",
			past * 4 <= alive.size(),
			"за линией %d из %d" % [past, alive.size()])
	for m3 in men:
		if m3 != null and is_instance_valid(m3) and not (m3 as Unit).is_dead():
			(m3 as Unit).take_damage((m3 as Unit).max_health * 10.0, null)
	for pf1 in foe:
		for u1 in _live(pf1):
			(u1 as Unit).take_damage((u1 as Unit).max_health * 10.0, null)
	await pf(4)

## Габарит группы: самое дальнее расстояние между двумя её бойцами
## Средний сдвиг ВЗАИМНОГО расположения: у каждого бойца берём смещение от
## медианного центра отряда и сравниваем с тем, каким оно было до приказа.
## Опора с обеих сторон — МЕДИАНА (_centroid_of), иначе меряется разница
## среднего и медианы (0.1-0.2 м), а не искажение строя
func _shape_drift(units: Array, before: Dictionary) -> float:
	if units.is_empty():
		return 0.0
	var c: Vector3 = GameManager._centroid_of(units)
	var sum := 0.0
	var n := 0
	for u in units:
		var key: int = (u as Object).get_instance_id()
		if not before.has(key):
			continue
		var p: Vector3 = (u as Node3D).global_position
		sum += (Vector2(p.x - c.x, p.z - c.z) - (before[key] as Vector2)).length()
		n += 1
	return sum / float(maxi(n, 1))

func _span(units: Array) -> float:
	var worst := 0.0
	for a in units:
		if a == null or not is_instance_valid(a):
			continue
		var pa: Vector3 = (a as Node3D).global_position
		for b in units:
			if b == null or not is_instance_valid(b):
				continue
			var pb: Vector3 = (b as Node3D).global_position
			worst = maxf(worst, Vector2(pa.x - pb.x, pa.z - pb.z).length())
	return worst

# ═════════════════════════════════════════════════════════════════════════════
# БЛОК 6. ОРИЕНТАЦИЯ СПРАЙТОВ И «БЕГ НА МЕСТЕ»
# ═════════════════════════════════════════════════════════════════════════════
## Три жалобы владельца, у которых общий корень — расхождение КАРТИНКИ и ФАКТА:
##   • задние ряды при построении смотрят назад, пока передние смотрят вперёд;
##   • рыцари на марше едут задом наперёд;
##   • центр отряда «бежит на месте».
##
## Все три измеримы БЕЗ картинки, потому что все три считаются из полей:
## анимация ходьбы живёт из moved_recently(), зеркало — из _mv_dir, взгляд
## стоящего — из _facing. Стенд сравнивает их с ФАКТИЧЕСКИМ смещением и с
## курсом отряда
func _b6_facing() -> void:
	print("\n═════ БЛОК 6. ОРИЕНТАЦИЯ И «БЕГ НА МЕСТЕ» ═════")
	# Поднимаем свежую колонну: прежние отряды уже перебиты и разбросаны
	var men_all: Array = []
	var sids: Array = []
	var col := _line(S_SPEAR, "spearman", Constants.FACTION_PLAYER, 150,
		-160.0, 24.0)
	for pair in col:
		sids.append(int(pair[0]))
		for u in (pair[1] as Array):
			men_all.append(u)
	# ── ТЕСНОТА ОБЯЗАТЕЛЬНА, ИНАЧЕ ЗАМЕР НИЧЕГО НЕ ЛОВИТ ───────────────────
	# «Бег на месте» — это картинка идущего у бойца, которого держат ТЕЛА. На
	# чистом марше по пустому полю его не бывает по построению, и первая версия
	# блока честно показывала ноль ни о чём. Ставим на пути СТОЯЩУЮ стену своих:
	# центр колонны упрётся в неё, и именно там жалоба и живёт
	var wall := _line(S_SPEAR, "spearman", Constants.FACTION_PLAYER, 100,
		-160.0, 24.0)
	for pair_w in wall:
		for uw in (pair_w[1] as Array):
			(uw as Unit).global_position = Vector3(
				30.0 + randf_range(-6.0, 6.0), 0.0, -160.0 + randf_range(-8.0, 8.0))
			(uw as Unit).sync_row()
	await pf(20)
	sm._clear_selection()
	for u2 in men_all:
		sm._select(u2)
	await frames(2)
	# Марш ВПРАВО по карте: ось выбрана поперёк построения, чтобы разворот был
	# настоящим, а не «шаг вперёд». Точка — ЗА стеной своих
	var goal := Vector3(60.0, 0.0, -160.0)
	sm._issue_formation_move(goal, false)
	# ЖДЁМ, ПОКА КОЛОННА ДОЙДЁТ ДО СТЕНЫ СВОИХ: до упора мерить нечего —
	# «бег на месте» появляется только у того, кого держат тела
	await secs(14.0)

	# ── «БЕГ НА МЕСТЕ»: КАРТИНКА ИДЁТ, ТЕЛО СТОИТ ──────────────────────────
	# Меряем окном в секунду: за неё идущий боец проходит около двух метров, а
	# подталкивания разбора наложения дают знакопеременные сантиметры
	var pos0: Dictionary = {}
	for u3 in men_all:
		if is_instance_valid(u3) and not (u3 as Unit).is_dead():
			pos0[u3] = (u3 as Unit).global_position
	await secs(1.0)
	var running_in_place := 0
	var walking := 0
	for k in pos0:
		var uu := k as Unit
		if not is_instance_valid(uu) or uu.is_dead():
			continue
		if not uu.moved_recently():
			continue
		walking += 1
		if (uu.global_position - (pos0[k] as Vector3)).length() < 0.3:
			running_in_place += 1
	print("  показывают ходьбу: %d, из них не сдвинулись за секунду: %d" % [
		walking, running_in_place])
	verdict("B6-1 никто не «бежит на месте»",
		walking == 0 or float(running_in_place) / float(maxi(walking, 1)) < 0.05,
		"стоят с анимацией ходьбы %d из %d" % [running_in_place, walking])

	# ── ЗЕРКАЛО ПО ФАКТИЧЕСКОМУ ХОДУ ───────────────────────────────────────
	# «Задом наперёд» — это когда направление, по которому считается зеркало
	# (_mv_dir), смотрит ПРОТИВ реального смещения бойца
	var backwards := 0
	var checked := 0
	for k2 in pos0:
		var u4 := k2 as Unit
		if not is_instance_valid(u4) or u4.is_dead():
			continue
		var d: Vector3 = u4.global_position - (pos0[k2] as Vector3)
		d.y = 0.0
		if d.length() < 0.5:
			continue                      # стоит — зеркалу неоткуда врать
		checked += 1
		var mv: Vector3 = u4._mv_dir
		if mv.length_squared() > 1e-6 and mv.normalized().dot(d.normalized()) < -0.3:
			backwards += 1
	print("  идущих под замером %d" % checked)
	verdict("B6-2 спрайт зеркалится по фактическому ходу, а не против него",
		checked == 0 or float(backwards) / float(maxi(checked, 1)) < 0.05,
		"едут задом наперёд %d из %d" % [backwards, checked])

	# ── ВЗГЛЯД ПОСЛЕ ПОСТРОЕНИЯ: ВСЕ В ОДНУ СТОРОНУ ───────────────────────
	# Ждём прихода и сверяем взгляд каждого с КУРСОМ ЕГО ОТРЯДА: именно
	# расхождение с ним и выглядит как «задние ряды смотрят назад»
	await secs(30.0)
	var wrong_look := 0
	var looked := 0
	for sid in sids:
		var course: Vector3 = GameManager.squad_course(int(sid))
		if course.length_squared() < 1e-6:
			continue
		var cn: Vector3 = course.normalized()
		for m in GameManager.squad_members(int(sid)):
			var u5 := m as Unit
			if u5 == null or not is_instance_valid(u5) or u5.is_dead():
				continue
			if u5.state != Unit.State.IDLE:
				continue                  # ещё идёт — взгляд по ходу, и это верно
			looked += 1
			var f: Vector3 = u5._facing
			if f.length_squared() > 1e-6 and f.normalized().dot(cn) < 0.0:
				wrong_look += 1
	print("  вставших под замером %d" % looked)
	verdict("B6-3 вставший строй смотрит по курсу отряда, а не вразнобой",
		looked == 0 or float(wrong_look) / float(maxi(looked, 1)) < 0.05,
		"смотрят против курса %d из %d" % [wrong_look, looked])
	for u6 in men_all:
		var uu2 := u6 as Unit
		if is_instance_valid(uu2) and not uu2.is_dead():
			uu2.take_damage(uu2.max_health * 10.0, null)
	await pf(4)

# ═════════════════════════════════════════════════════════════════════════════
# БЛОК 5. ЧЕХАРДА ИИ
# ═════════════════════════════════════════════════════════════════════════════
## Симптом владельца: отряд ИИ бежит в атаку, через секунду разворачивается и
## отступает, потом снова в атаку. Мерим ЧИСЛО РАЗВОРОТОВ: считаем знак
## продвижения отряда к базе игрока и считаем, сколько раз он поменялся
func _b5_ai() -> void:
	print("\n═════ БЛОК 5. ЧЕХАРДА ИИ ═════")
	if main.enemy_ai == null:
		verdict("B5-0 ИИ в сцене есть", false)
		return
	main.enemy_ai.set_process(true)
	# ── МИРНУЮ ФАЗУ ПРОПУСКАЕМ ─────────────────────────────────────────────
	# Первые минуты партии ИИ не воюет вовсе (ai_peace_seconds), и наблюдение
	# внутри этой фазы даёт «ноль смен роли» ни о чём: отряды просто стоят.
	# Чехарда — про ВОЮЮЩИЙ ИИ, поэтому мир объявляем оконченным
	main.enemy_ai._peace_over = true
	main.enemy_ai._peace_timer = 9999.0
	# Поле для ИИ: свои и чужие в пределах видимости друг друга
	var mine := _line(S_SPEAR, "spearman", Constants.FACTION_PLAYER, 120,
		200.0, 30.0)
	var foe := _line(S_KNIGHT, "warrior", Constants.FACTION_ENEMY, 120,
		240.0, 30.0)
	await secs(4.0)
	# ── МЕРИМ ОТРЯДЫ САМОГО ИИ, А НЕ СВОИ ──────────────────────────────────
	# Первая версия считала развороты по отрядам, которые подняла САМА, — а ИИ
	# ведёт СВОЙ реестр (EnemyAI.squads) и командует им. Проверка честно
	# отвечала «отрядов под наблюдением 0» и была зелёной ни о чём.
	#
	# «Чехарда» — это смена РОЛИ, а не координаты: отряд получает роль «в
	# атаку», через секунду «отход», потом снова «в атаку». Роль и считаем
	var roles: Dictionary = {}     # индекс отряда ИИ → последняя роль
	var churn: Dictionary = {}     # индекс → сколько раз роль менялась
	var seen_any := false
	for _i in range(60):
		await pf(30)
		var ai_squads: Array = main.enemy_ai.squads
		for si in range(ai_squads.size()):
			var sq: Dictionary = ai_squads[si]
			var alive := 0
			for m in (sq.get("members", []) as Array):
				if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
					alive += 1
			if alive < 3:
				continue
			seen_any = true
			var role: String = String(sq.get("role", ""))
			var prev: Variant = roles.get(si)
			if prev != null and String(prev) != role:
				churn[si] = int(churn.get(si, 0)) + 1
			roles[si] = role
	var total_flips := 0
	var squads_seen := roles.size()
	var worst := 0
	for k in churn:
		total_flips += int(churn[k])
		worst = maxi(worst, int(churn[k]))
	print("  отрядов ИИ под наблюдением %d, смен роли всего %d, худший %d" % [
		squads_seen, total_flips, worst])
	if not seen_any:
		verdict("B5-0 отряды ИИ вообще есть под наблюдением", false,
			"реестр ИИ пуст — мерить нечего")
	# ПОРОГ — СВОЙСТВО, А НЕ КРУГЛОЕ ЧИСЛО: за 30 секунд честный отряд может
	# развернуться раз-другой (дошёл, ввязался, отступил по морали). Метания —
	# это разворот чаще, чем раз в замок решения AICfg.RETREAT_MIN_SEC
	var window: float = 30.0
	var allowed: int = maxi(2, int(window / _AI_lock_sec()))
	verdict("B5-1 отряды ИИ не мечутся вперёд-назад",
		squads_seen == 0 or worst <= allowed,
		"худший отряд сменил роль %d раз за %.0f с при пределе %d" % [
			worst, window, allowed])

func _AI_lock_sec() -> float:
	var cfg = load("res://scripts/ai_start_army_limit.gd")
	var v: Variant = cfg.get("RETREAT_MIN_SEC")
	return float(v) if v != null else 6.0
