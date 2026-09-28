extends Node
class_name SquadCommander
## ═══════════════════════════════════════════════════════════════════════════
## КОМАНДЫ ОТРЯДУ: ДЕРЖАТЬ ПОЗИЦИЮ [S] · ВОЛЬНО [C] · АТАКА ПО ПУТИ [A]
## ═══════════════════════════════════════════════════════════════════════════
## ТЗ 23.09.2026. Три команды на выделение целиком: выделен один отряд —
## применяется к нему, выделено десять — ко всем десяти одновременно.
##
## ДВЕ ИЗ ТРЁХ КОМАНД УЖЕ БЫЛИ В ИГРЕ, И ЗАВОДИТЬ ИМ ВТОРУЮ МЕХАНИКУ НЕЛЬЗЯ.
## «Держать позицию» — это стойка ЗАЩИТА (STANCES.defense.holds_ground: боец
## с места не сходит, бьёт только то, до чего достаёт), «Вольно» — стойка
## АТАКА (свободное авто-агро). Заведи я под них третье состояние — в проекте
## стало бы два независимых источника правды о том, преследует боец врага или
## нет, и разошлись бы они на первой же правке. Поэтому S и C — ТОНКИЕ
## ОБЁРТКИ над set_selection_stance, а вся новая логика здесь — только третья
## команда, Attack-Move.
##
## ── ЧТО ТАКОЕ ATTACK-MOVE И ЧЕМ ОН ОТЛИЧАЕТСЯ ОТ ОБЫЧНОГО МАРША ───────────
## Обычный ПКМ: отряд идёт в точку и по дороге дерётся только с тем, кто сам
## на него полез (авто-агро от поста, AGGRO_RADIUS 5 м). Attack-Move: отряд
## идёт в точку, но САМ ищет противника в радиусе своего оружия, вступает в
## бой, а зачистив — возвращается к маршу в ТУ ЖЕ точку и встаёт там В ТОЙ ЖЕ
## формации, в какой вышел.
##
## ── ПОЧЕМУ СКАН ЖИВЁТ ЗДЕСЬ, А НЕ У БОЙЦА (требование ТЗ, п. 3) ───────────
## «Каждому юниту делать area_scan каждый кадр запрещено». В этом проекте так
## никто и не делает — но соблазн велик, и вот цена: отряд копейщиков это
## 60 моделей, пятнадцать отрядов — 900 сканов в кадр, 54 000 в секунду.
## Здесь скан ОДИН НА ОТРЯД и идёт от его центра (медианы), раз в AM_TICK_SEC,
## и даже эти редкие сканы разложены по кадрам очередью: за один период
## обслуживается вся очередь, но в каждом кадре — только её доля. Тем же
## приёмом считается мораль (GameManager._sweep_morale), и заведён он ровно
## по этой причине: два десятка отрядов в одном кадре давали видимый горб.
##
## ── ЦЕЛЬ РАЗДАЁТСЯ ОТРЯДУ, А НЕ БОЙЦУ ────────────────────────────────────
## Найдя врага, командир отдаёт ОДИН command_attack всем членам отряда — ту
## же самую цель. Разбор чужого строя по моделям делает Unit.command_attack
## через GameManager.squad_pick_member: отряд бьёт назначенный отряд сообща,
## но не сваливается всей толпой на одну модель. Это дословно то же правило,
## по которому работает ПКМ игрока (см. SelectionManager._handle_right_click),
## и другого правила у приказа атаки в проекте быть не должно.

const _UCfgSC := preload("res://scripts/unit_stats_config.gd")

## ── ЧАСТОТА ОТРЯДНОГО СКАНА ──────────────────────────────────────────────
## ТЗ просит 0.2-0.4 с. Взято 0.3: на 0.2 отряд дёргается между целями в
## свалке (цель меняется чаще, чем боец успевает до неё дойти), на 0.4
## лучник успевает пройти мимо цели, стоящей на краю его дальности
const AM_TICK_SEC := 0.3

## ═══════════════════════════════════════════════════════════════════════════
## РАДИУС ВСТУПЛЕНИЯ В БОЙ — ЭТО ДЛИНА ОРУЖИЯ, А НЕ «СКОЛЬКО ВИДНО»
## ═══════════════════════════════════════════════════════════════════════════
## ЖАЛОБА ВЛАДЕЛЬЦА (23.09.2026): «марширует три отряда, видят одного гоблина
## — вся армия бросает марш и толпой бежит за ним». Причин было ДВЕ, и каждой
## хватало по отдельности:
##   1) ПОЛ РАДИУСА 14 м. Он писался как «пехота видит перед собой», но
##      вступление в бой — это не зрение, а ДОСЯГАЕМОСТЬ: копейщик с копьём
##      в 2 м, увидев цель за четырнадцать, шёл к ней. Три отряда видели
##      одного и того же гоблина и шли втроём.
##   2) ЦЕЛЬ НЕ ОТПУСКАЛАСЬ. Взяв её один раз, отряд держал её, пока она
##      жива, — то есть гнался. Убегающий гнолл уводил за собой всю армию.
##
## Теперь радиус = дальность оружия плюс один шаг запаса, с полом по
## СОБСТВЕННОМУ радиусу инициативы бойца (AGGRO_RADIUS 5 м, ТЗ 20.09.2026).
## У копейщика выходит 5 м, у лучника — его 25: стрелок бьёт с места ровно
## настолько, насколько достаёт, и никуда не идёт.
const AM_SCAN_MULT := 1.15        # запас поверх дальности оружия
const AM_ENGAGE_MARGIN := 2.0     # плюс шаг: цель у самой кромки не мигает
const AM_SCAN_MAX := 40.0         # дальше отряд на марше не отвлекается

## ПОВОДОК БОЯ: насколько отряд вправе сойти с маршрута ради драки.
## Без него «не гнаться» невыполнимо в принципе: цель, отступившая на шаг,
## каждый такт остаётся в радиусе — и отряд идёт за ней бесконечно малыми
## шагами. Мерится от точки, где бой ЗАВЯЗАЛСЯ (st["hold"]), а не от линии
## марша: линия у отряда, уже свернувшего к врагу, ничего не ограничивает.
## Восемь метров — это глубина боевого построения плюс пара шагов
const AM_LEASH := 8.0

## Насколько близко к точке назначения считается «пришёл». Шире ARRIVE_RADIUS
## бойца: судим о ЦЕНТРЕ отряда, а он у шеренги в 60 человек гуляет
const AM_ARRIVE := 4.0

## ПОСЛЕ БОЯ МАРШ ВОЗОБНОВЛЯЕТСЯ НЕ МГНОВЕННО. Между «последний враг упал» и
## «отряд пошёл» нужна пауза: цель гибнет в одном такте, а соседний враг
## попадает в скан на следующем, и без паузы отряд успел бы отдать приказ на
## марш и тут же его отменить — на экране это читается как топтание
const AM_RESUME_GAP := 0.6

## Сколько ПОДРЯД тактов без единого врага нужно, чтобы счесть участок
## зачищенным. Один такт — это 0.3 с, и в свалке цель пропадает из скана на
## такт просто потому, что умерла последняя модель ближнего отряда
const AM_CLEAR_TICKS := 2

## sid -> {"dest": Vector3, "run": bool, "clear": int, "wait": float,
##         "fighting": bool}
var _am: Dictionary = {}
## Очередь обслуживания: та же схема, что у _sweep_morale
var _queue: Array = []
var _tick_t: float = 0.0

## Стендам и интерфейсу: сколько отрядов сейчас идут в режиме атаки
var active_count: int = 0
## Счётчики для стендов: сколько раз командир завязал бой и возобновил марш
var engagements: int = 0
var resumes: int = 0
## Сколько раз отряд оборвал погоню по поводку — стенд судит по этому числу
var leash_breaks: int = 0
## Сколько сканов сделано всего — стенд производительности сверяет с числом
## бойцов: он обязан расти от ЧИСЛА ОТРЯДОВ, а не от числа моделей
var scans: int = 0

# ═════════════════════════════════════════════════════════════════════════════
# ПУБЛИЧНЫЙ ВХОД: ТРИ КОМАНДЫ
# ═════════════════════════════════════════════════════════════════════════════

## [S] ДЕРЖАТЬ ПОЗИЦИЮ. Отряд встаёт, бросает преследование и бьёт только то,
## до чего достаёт с места. Attack-Move при этом снимается: это прямо
## противоположные приказы, и оставить оба означало бы, что отряд «стоит и
## одновременно идёт»
func stand_ground(sm: Node) -> void:
	if sm == null or not is_instance_valid(sm):
		return
	_cancel_for_selection(sm)
	sm.set_selection_stance(_UCfgSC.STANCE_DEFENSE)

## [C] ВОЛЬНО. Возврат к обычному поведению: свободное авто-агро, приказы
## исполняются как всегда. Тоже снимает Attack-Move — «вольно» и есть отмена
func at_ease(sm: Node) -> void:
	if sm == null or not is_instance_valid(sm):
		return
	_cancel_for_selection(sm)
	sm.set_selection_stance(_UCfgSC.STANCE_ATTACK)

## [A] АТАКА ПО ПУТИ. Точку даёт следующий клик (см. SelectionManager), сюда
## приходит уже готовая.
##
## ФОРМАЦИЮ ПЕРЕНОСИТ ТОТ ЖЕ КОД, ЧТО И ОБЫЧНЫЙ ПРИКАЗ. Марш вызывается через
## SelectionManager.march_selection_to — то есть через сетку блоков и перенос
## строя целиком (_issue_march_keeping_shape). Своей раскладки здесь нет и не
## должно быть: заведи её — и отряд, отправленный по [A], встал бы иначе, чем
## тот же отряд, отправленный ПКМ
func attack_move(sm: Node, dest: Vector3, run: bool = false) -> int:
	if sm == null or not is_instance_valid(sm):
		return 0
	dest.y = 0.0
	var sids: Dictionary = _selected_squads(sm)
	if sids.is_empty():
		return 0
	# Отряд, которому велели идти с боем, обязан быть вправе идти: в стойке
	# ЗАЩИТА ход запрещён на уровне move_speed_mult, и приказ молча пропал бы
	for sid in sids:
		var sq: Variant = GameManager.squads.get(int(sid))
		if sq == null:
			continue
		for m in ((sq as Dictionary)["members"] as Array):
			if m != null and is_instance_valid(m) and m.has_method("set_stance"):
				if String((m as Unit).stance) == _UCfgSC.STANCE_DEFENSE:
					(m as Unit).set_stance(_UCfgSC.STANCE_ATTACK)
	sm.march_selection_to(dest, run)
	# Номер клика: отряды одного [A] идут ФРОНТОМ и делят чужую линию между
	# собой (см. _front_target), отряды разных кликов друг другу не соседи
	_group_seq += 1
	for sid2 in sids:
		_am[int(sid2)] = {
			"grp": _group_seq,
			"dest": dest, "run": run, "clear": 0,
			"wait": 0.0, "fighting": false,
			# Точка, где отряд свернул с марша к врагу. Vector3.INF — не
			# свернул (значением, а не парой: правило 14)
			"hold": Vector3.INF,
		}
		GameManager.squad_note_order(int(sid2), GameManager.ORDER_MOVE, dest)
	active_count = _am.size()
	return sids.size()

## Снять режим у отряда (любой новый приказ игрока это делает — см.
## SelectionManager: ПКМ и клавиши стоек зовут cancel_squad)
func cancel_squad(sid: int) -> void:
	if _am.erase(sid):
		active_count = _am.size()

func is_attack_moving(sid: int) -> bool:
	return _am.has(sid)

## В стычке ли отряд Attack-Move (false — идёт маршем или режима нет)
func is_fighting(sid: int) -> bool:
	var e: Variant = _am.get(sid)
	return e != null and bool((e as Dictionary)["fighting"])

## Куда идёт отряд в режиме атаки (Vector3.INF — не идёт). Значением, а не
## парой: правило 14 (ответ парой — тоже аллокация)
func attack_move_dest(sid: int) -> Vector3:
	var e: Variant = _am.get(sid)
	if e == null:
		return Vector3.INF
	return (e as Dictionary)["dest"]

# ═════════════════════════════════════════════════════════════════════════════
# ТИК: ОДИН СКАН НА ОТРЯД, ОЧЕРЕДЬЮ ПО КАДРАМ
# ═════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if _am.is_empty():
		if not _queue.is_empty():
			_queue.clear()
		if not _grp_pairs.is_empty():
			_grp_pairs.clear()
		return
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = AM_TICK_SEC
		# Не разобранный остаток прежнего такта дорабатывается сейчас же:
		# никто не обслуживается реже раза в период
		_queue = _am.keys() if _queue.is_empty() else _queue + _am.keys()
	if _queue.is_empty():
		return
	# Доля очереди на этот кадр — вся очередь укладывается в период такта
	var per: int = maxi(int(ceil(float(_am.size()) * delta / AM_TICK_SEC)), 1)
	while per > 0 and not _queue.is_empty():
		per -= 1
		_tick_squad(int(_queue.pop_back()), delta)

func _tick_squad(sid: int, _delta: float) -> void:
	var e: Variant = _am.get(sid)
	if e == null:
		return
	var st: Dictionary = e
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		cancel_squad(sid)
		return
	# СОСТАВ ЧИТАЕТСЯ НАПРЯМУЮ: squad_members() не читатель — опустевший отряд
	# он РАСПУСКАЕТ прямо в геттере (см. CLAUDE.md)
	var members: Array = (sq as Dictionary)["members"]
	var alive: Array = []
	for m in members:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			alive.append(m)
	if alive.is_empty():
		cancel_squad(sid)
		return
	var lead: Unit = alive[0]
	var centre: Vector2 = GameManager.squad_centre_xz(sid)
	if centre == Vector2.INF:
		return
	var cpos := Vector3(centre.x, 0.0, centre.y)

	# ── 1. ПОВОДОК: ДАЛЕКО ЛИ ОТРЯД УШЁЛ ОТ МЕСТА СТЫЧКИ ──────────────────
	# Стоит ПЕРВЫМ, до скана: отряд, уже утянутый за убегающим, обязан
	# вернуться к маршу, даже если враг всё ещё в радиусе. Иначе «не гнаться»
	# не выполняется ни при каком радиусе — цель просто пятится
	var hold: Vector3 = st["hold"]
	if hold != Vector3.INF and cpos.distance_to(hold) > AM_LEASH:
		st["hold"] = Vector3.INF
		st["clear"] = AM_CLEAR_TICKS
		st["wait"] = 0.0
		leash_breaks += 1
		if bool(st["fighting"]):
			st["fighting"] = false
			resumes += 1
			_resume_march(sid, alive, st["dest"], bool(st["run"]))
		return

	# ── 2. ВРАГ В ДОСЯГАЕМОСТИ? ОДИН СКАН, ОТ ЦЕНТРА ОТРЯДА ───────────────
	var foe: Node3D = _scan_enemy(lead, cpos, _scan_radius(lead))
	if foe != null:
		st["clear"] = 0
		st["wait"] = AM_RESUME_GAP
		if hold == Vector3.INF:
			st["hold"] = cpos
		if not bool(st["fighting"]):
			st["fighting"] = true
			engagements += 1
		# Приказ ОДИН на отряд и не «forced»: замок цели игрока здесь не
		# ставится намеренно. Замок снимается только новым приказом, а отряд
		# обязан ВЕРНУТЬСЯ к маршу сам, как только врага не станет.
		# ЦЕЛЬ ПЕРЕНАЗНАЧАЕТСЯ КАЖДЫЙ ТАКТ, И ЭТО НЕ РАСТОЧИТЕЛЬСТВО: ушедшая
		# за радиус цель просто перестаёт приходить из скана, и бойцы
		# остаются без неё — то есть отпускают её сами, без отдельной ветки
		# «прекратить погоню»
		# ── ФРОНТ НА ФРОНТ (ТЗ 25.09.2026, п. 4) ─────────────────────────
		# Цель — не «ближайший враг», а чужой отряд ПРЯМО ПЕРЕД этим отрядом
		# (раскладка по ширине фронта на всю группу клика), и каждый боец
		# берёт из него СВОЮ жертву. Прежде здесь стоял command_attack(foe,
		# false) каждому: у НЕфорсированного приказа нет разбора по моделям
		# (squad_pick_member — только при forced), и весь отряд шёл в одну
		# модель — пять отрядов сплющивались в одну молотилку
		var fsid: int = _front_target(sid, st, cpos, foe)
		if fsid > 0:
			GameManager.squad_attack_squad(sid, fsid, false)
		else:
			for u in alive:
				(u as Unit).command_attack(foe, false)
		GameManager.squad_note_order(sid, GameManager.ORDER_ATTACK,
			foe.global_position, foe)
		return
	# Врага в досягаемости нет — место стычки больше ничего не держит
	st["hold"] = Vector3.INF

	# ── 3. ВРАГА НЕТ. ЗАЧИЩЕНО ЛИ? ─────────────────────────────────────────
	st["clear"] = int(st["clear"]) + 1
	if int(st["clear"]) < AM_CLEAR_TICKS:
		return
	var wait: float = float(st["wait"]) - AM_TICK_SEC
	st["wait"] = wait
	if wait > 0.0:
		return

	# ── 4. ДОШЛИ? ──────────────────────────────────────────────────────────
	var dest: Vector3 = st["dest"]
	if cpos.distance_to(dest) <= AM_ARRIVE:
		# ПРИБЫЛИ — СМЫКАЕМ СТРОЙ И СНИМАЕМ РЕЖИМ. Смыкание, а не новая
		# разметка: разметка отряда не стиралась на время боя (её только
		# блокировали), и close_ranks вернёт выживших ровно в ту форму, в
		# которой отряд выходил, — это и есть заказанное «перестраиваются
		# точно в ту формацию»
		GameManager.squad_close_ranks(sid)
		GameManager.squad_clear_order(sid)
		cancel_squad(sid)
		return

	# ── 5. НЕ ДОШЛИ — ПРОДОЛЖАЕМ МАРШ ──────────────────────────────────────
	# Только если отряд действительно ДРАЛСЯ: иначе командир слал бы приказ
	# на марш каждые 0.3 с всю дорогу, а каждый command_move будит бойца,
	# метит позу грязной и отнимает у него сон (см. CLAUDE.md, «цена костыля
	# была не там, где её мерили»: 175 FPS против 134 на 2010 юнитах)
	if not bool(st["fighting"]):
		return
	st["fighting"] = false
	resumes += 1
	_resume_march(sid, alive, dest, bool(st["run"]))

## Номер клика [A] (см. attack_move) и кэш раскладки фронта на группу:
## grp → {"t": мс, "pairs": {sid: чужой sid}}. Раскладка одна на группу за
## такт, а не своя у каждого отряда: иначе соседи считали бы её по разным
## моментам и могли бы взять одного противника
var _group_seq: int = 0
var _grp_pairs: Dictionary = {}
## Стендам: сколько раз отряд получил цель раскладкой фронта
var front_assigns: int = 0

func _front_target(sid: int, st: Dictionary, cpos: Vector3, foe: Node3D) -> int:
	var fu := foe as Unit
	var fallback: int = fu.squad_id if fu != null else 0
	var grp: int = int(st.get("grp", 0))
	var now: int = Time.get_ticks_msec()
	var cache: Variant = _grp_pairs.get(grp)
	if cache == null or now - int((cache as Dictionary)["t"]) > int(AM_TICK_SEC * 1000.0):
		var sids: Array = []
		for k in _am.keys():
			if int((_am[k] as Dictionary).get("grp", -1)) == grp:
				sids.append(int(k))
		# Радиус — габарит группы плюс досягаемость: чужая линия перед
		# крайним отрядом тоже обязана попасть в раскладку
		var mid := Vector3.ZERO
		var n := 0
		for s in sids:
			var c: Vector2 = GameManager.squad_centre_xz(int(s))
			if c != Vector2.INF:
				mid += Vector3(c.x, 0.0, c.y)
				n += 1
		if n == 0:
			return fallback
		mid /= float(n)
		var span := 0.0
		for s2 in sids:
			var c2: Vector2 = GameManager.squad_centre_xz(int(s2))
			if c2 != Vector2.INF:
				span = maxf(span, Vector2(c2.x - mid.x, c2.y - mid.z).length())
		var lead: Unit = null
		var sq: Variant = GameManager.squads.get(sid)
		if sq != null:
			for m in (sq as Dictionary)["members"]:
				if m != null and is_instance_valid(m):
					lead = m
					break
		var reach: float = _scan_radius(lead) if lead != null else 10.0
		var pairs: Dictionary = GameManager.front_pairs(sids, mid, span + reach + 6.0,
			Constants.FACTION_PLAYER)
		cache = {"t": now, "pairs": pairs}
		_grp_pairs[grp] = cache
	var got: Variant = ((cache as Dictionary)["pairs"] as Dictionary).get(sid)
	if got == null:
		return fallback
	front_assigns += 1
	return int(got)

## Возобновить марш отряда в точку. Строй переносится ЦЕЛИКОМ — тем же
## приёмом, что и приказ игрока (см. GameManager.squad_set_formation через
## SelectionManager). Здесь его нет под рукой, поэтому шлём command_move
## каждому со смещением от центра: взаимное расположение не меняется
func _resume_march(sid: int, alive: Array, dest: Vector3, run: bool) -> void:
	var centroid: Vector3 = GameManager._centroid_of(alive)
	centroid.y = 0.0
	var shift: Vector3 = dest - centroid
	# ── РАЗМЕТКА ЕДЕТ ВМЕСТЕ С МАРШЕМ (ТЗ 25.09.2026, найдено qa_attack_move B3) ─
	# Бойцы шли к точке, а места строя (squads[sid]["slots"]) оставались там,
	# где отряд застал бой. Через три секунды окно боя закрывалось, штатное
	# смыкание рядов раздавало бойцам эти места — и отряд вставал в 37 м от
	# точки навсегда (режим Attack-Move висел, возобновлять его было не с чего:
	# «дрались» уже не числилось). Разметка переносится тем же вектором, что
	# и бойцы: форма строя та же, смыкание ведёт к точке, а не назад
	var sq: Variant = GameManager.squads.get(sid)
	if sq != null:
		var old: Array = (sq as Dictionary).get("slots", [])
		if not old.is_empty():
			var sc := Vector3.ZERO
			for p0 in old:
				sc += p0 as Vector3
			sc /= float(old.size())
			sc.y = 0.0
			var moved: Array = []
			for p1 in old:
				moved.append((p1 as Vector3) + (dest - sc))
			var course: Vector3 = shift
			course.y = 0.0
			GameManager.squad_set_formation(sid, moved,
				course.normalized() if course.length() > 0.1 else Vector3.FORWARD, false)
	for u in alive:
		var un := u as Unit
		if un == null or not un.has_method("command_move"):
			continue
		var p: Vector3 = un.global_position + shift
		p.y = 0.0
		un.command_move(p, false, Vector3.ZERO, false, true, run)
	GameManager.squad_note_order(sid, GameManager.ORDER_MOVE, dest)

## Радиус ВСТУПЛЕНИЯ В БОЙ по роду войск вожака. Пол — собственный радиус
## инициативы бойца (AGGRO_RADIUS): ниже него отряд перестал бы замечать тех,
## на кого и без всякого Attack-Move бросился бы сам
func _scan_radius(lead: Unit) -> float:
	var r: float = lead.attack_range * AM_SCAN_MULT + AM_ENGAGE_MARGIN
	return clampf(maxf(r, lead.aggro_radius()), 1.0, AM_SCAN_MAX)

## ОДИН СКАН НА ОТРЯД. Ищем ближайшего живого чужого к центру отряда.
## ЗДАНИЯ СЮДА НЕ ПОПАДАЮТ НАМЕРЕННО: Attack-Move — это «иди и дерись с тем,
## кто мешает», а снос построек по дороге превратил бы марш в осаду всякий
## раз, когда путь прошёл мимо чужого сарая
func _scan_enemy(lead: Unit, at: Vector3, radius: float) -> Node3D:
	if GameManager.unit_grid == null:
		return null
	scans += 1
	var foe: Node3D = GameManager.unit_grid.enemy_at(at, radius, lead.faction)
	if foe == null:
		return null
	# Правило 5: проверка на СЫРОЙ ссылке, до приведения типа
	if not is_instance_valid(foe):
		return null
	var fu := foe as Unit
	if fu == null or fu.is_dead():
		return null
	return fu

# ═════════════════════════════════════════════════════════════════════════════
# СЛУЖЕБНОЕ
# ═════════════════════════════════════════════════════════════════════════════

## Отряды выделения: sid -> true. Рабочие и одиночки (sid 0) не в счёт —
## команды строя к ним не относятся
func _selected_squads(sm: Node) -> Dictionary:
	var out: Dictionary = {}
	for u in (sm.selected_units as Array):
		if u == null or not is_instance_valid(u) or not (u is Unit):
			continue
		var un := u as Unit
		if un.is_dead() or un.squad_id <= 0:
			continue
		if un.faction != Constants.FACTION_PLAYER:
			continue
		out[un.squad_id] = true
	return out

func _cancel_for_selection(sm: Node) -> void:
	for sid in _selected_squads(sm):
		cancel_squad(int(sid))
