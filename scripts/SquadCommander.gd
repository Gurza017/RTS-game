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
const _OptSC := preload("res://scripts/perf_config.gd")

## ═══════════════════════════════════════════════════════════════════════════
## АДАПТИВНЫЙ СКАН И ДЕСИНХРОНИЗАЦИЯ (ТЗ 10.10.2026, второе письмо)
## ═══════════════════════════════════════════════════════════════════════════
## Такт командира (AM_TICK_SEC) остаётся — он дешёвый: поводок, колонна,
## прибытие, «кто ударил» (запись в словаре, без сетки). ДОРОГОЙ шаг — скан
## к сетке соседей — идёт по СВОЕМУ расписанию отряда: бой ~0.9 с (скан нужен
## только чтобы выбрать новую цель отряду: бьют бойцы по своей перезарядке и
## сами перенацеливаются после гибели цели), марш ~1.75 с, покой ~3 с.
## Каждый интервал ×SCAN_JITTER (0.8-1.2), стартовая фаза отряда —
## случайная в пределах интервала: тридцать отрядов одного клика не сканируют
## одним кадром. Между сканами действует последний найденный враг (жив и
## рядом — бой продолжается); погиб он в бою — внеочередной скан, но не
## раньше SCAN_MIN_GAP_MS после прошлого. Ручка A/B — perf_config.am_adaptive
const SCAN_COMBAT_MS := 900
const SCAN_MARCH_MS := 1750
const SCAN_IDLE_MS := 3000
const SCAN_JITTER := 0.2
const SCAN_MIN_GAP_MS := 300
## ═══════════════════════════════════════════════════════════════════════════
## ОЧЕРЕДЬ ПРИКАЗОВ БОЙЦАМ (ТЗ 10.10.2026, «растянуть раздачу по кадрам»)
## ═══════════════════════════════════════════════════════════════════════════
## A/B адаптивного скана показал: пики кадра командира (17-27 мс) дают не
## сканы, а РАЗДАЧИ — марш заново всему отряду (60 command_move с постройкой
## дорог), подход к угрозе, атака отряда. Решение принимается сразу, а
## исполнение копится здесь и раздаётся с бюджетом ORDER_BUDGET_USEC на кадр
## (не меньше ORDER_MIN_PER_FRAME приказов, чтобы очередь не стояла на тяжёлом
## кадре). Боец в очереди один: новый приказ заменяет ещё не отданный.
## Отмена режима отряда (новый приказ игрока, прибытие) снимает его приказы.
## Ручка A/B — perf_config.am_order_queue
const ORDER_BUDGET_USEC := 1500
const ORDER_MIN_PER_FRAME := 1
const OQ_MOVE := 0
const OQ_ATTACK := 1
var _oq_ids: Array = []             # порядок (instance_id), без повторов
var _oq: Dictionary = {}            # instance_id -> [unit, kind, sid, a, b, c]
var _oq_pending: Dictionary = {}    # sid -> сколько приказов ждёт
## Стендам: всего поставлено в очередь / роздано / снято отменой, худшая
## глубина очереди и худшее ожидание приказа (кадров)
var oq_queued: int = 0
var oq_issued: int = 0
var oq_dropped: int = 0
var oq_depth_max: int = 0
var oq_wait_max: int = 0
## Самый дорогой одиночный приказ и самый дорогой такт отряда (мкс)
var oq_issue_max_us: int = 0
var tick_max_us: int = 0

func _enqueue(u: Unit, sid: int, kind: int, a, b, c) -> void:
	if not _OptSC.am_order_queue:
		_issue(u, kind, a, b, c)
		return
	var id: int = u.get_instance_id()
	var had: Variant = _oq.get(id)
	if had == null:
		_oq_ids.append(id)
		_oq_pending[sid] = int(_oq_pending.get(sid, 0)) + 1
	elif int((had as Array)[2]) != sid:
		_oq_pending[int((had as Array)[2])] = maxi(int(_oq_pending.get(int((had as Array)[2]), 1)) - 1, 0)
		_oq_pending[sid] = int(_oq_pending.get(sid, 0)) + 1
	# Кадр постановки — для замера ожидания; у заменённого приказа он прежний
	var f0: int = int((had as Array)[6]) if had != null else Engine.get_physics_frames()
	_oq[id] = [u, kind, sid, a, b, c, f0]
	oq_queued += 1
	oq_depth_max = maxi(oq_depth_max, _oq.size())

func _issue(u: Unit, kind: int, a, b, c) -> void:
	if kind == OQ_MOVE:
		u.command_move(a, false, b, false, true, c)
	else:
		u.command_attack(a, bool(b))

func _drain_orders() -> void:
	if _oq_ids.is_empty():
		return
	var t0: int = Time.get_ticks_usec()
	var n := 0
	while not _oq_ids.is_empty():
		if n >= ORDER_MIN_PER_FRAME and Time.get_ticks_usec() - t0 > ORDER_BUDGET_USEC:
			break
		var id: int = int(_oq_ids.pop_front())
		var rec: Variant = _oq.get(id)
		if rec == null:
			continue
		_oq.erase(id)
		var r: Array = rec
		var sid: int = int(r[2])
		_oq_pending[sid] = maxi(int(_oq_pending.get(sid, 1)) - 1, 0)
		var raw = r[0]
		# Правило 5: проверка на СЫРОЙ ссылке до приведения
		if not is_instance_valid(raw) or (raw as Unit).is_dead():
			continue
		var tgt = r[3]
		if int(r[1]) == OQ_ATTACK and (not is_instance_valid(tgt) or (tgt as Unit).is_dead()):
			continue
		var ti: int = Time.get_ticks_usec()
		_issue(raw as Unit, int(r[1]), tgt, r[4], r[5])
		oq_issue_max_us = maxi(oq_issue_max_us, Time.get_ticks_usec() - ti)
		oq_issued += 1
		oq_wait_max = maxi(oq_wait_max, Engine.get_physics_frames() - int(r[6]))
		n += 1

## Снять ещё не отданные приказы отряда (отмена режима, прибытие)
func _drop_orders(sid: int) -> void:
	if int(_oq_pending.get(sid, 0)) <= 0:
		return
	for id in _oq.keys():
		if int((_oq[id] as Array)[2]) == sid:
			_oq.erase(id)
			oq_dropped += 1
	_oq_pending.erase(sid)

func _sid_of(u: Unit) -> int:
	return u.squad_id

func _has_pending(sid: int) -> bool:
	return int(_oq_pending.get(sid, 0)) > 0

## Свой генератор: общий randf() сдвинул бы сеяные жребии партии
var _rng := RandomNumberGenerator.new()
var _atk_sink: Array = []

## ── СТЕНДАМ: ЦЕНА КОМАНДИРА ПО КАДРАМ ─────────────────────────────────────
## frame_usec — мкс _physics_process в кадре, где было что обслуживать;
## frame_scans — сканов в этом кадре; scans_by_sec — сканов по секундам
var stat_on: bool = false
var frame_usec: PackedInt32Array = PackedInt32Array()
var frame_scans: PackedInt32Array = PackedInt32Array()
var scans_by_sec: PackedInt32Array = PackedInt32Array()
var _stat_t0: int = 0
func stat_reset() -> void:
	frame_usec = PackedInt32Array()
	frame_scans = PackedInt32Array()
	scans_by_sec = PackedInt32Array()
	_stat_t0 = Time.get_ticks_msec()
	stat_on = true
	oq_queued = 0; oq_issued = 0; oq_dropped = 0; oq_depth_max = 0; oq_wait_max = 0
	oq_issue_max_us = 0; tick_max_us = 0

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

## ═══════════════════════════════════════════════════════════════════════════
## УДАР ВО ФЛАНГ — РАЗВОРАЧИВАЕТСЯ ВСЯ ГРУППА (ТЗ 10.10.2026, блок 2)
## ═══════════════════════════════════════════════════════════════════════════
## «Во фланг идущей армии из 15 отрядов врезаются 2 — вся армия, включая
## лучников и дальние отряды, разворачивается, подавляет угрозу, добивает и
## возобновляет марш». Раньше каждый отряд видел только врага в длине своего
## оружия: хвост колонны шёл дальше, пока голову рубили. Теперь у ГРУППЫ
## (одного клика [A]) есть общая УГРОЗА: враг, найденный сканом любого отряда
## группы, ИЛИ тот, кто ударил любой её отряд (squad_mark_hit запоминает
## ударившего — так видны и стрелки, бьющие издали). Отряды группы в
## AM_ASSIST_R от угрозы идут на неё: пехота — приказом атаки на её отряд,
## стрелки — подходом на 0.8 дальности, затем обычный скан даёт им цель.
## Поводок такого боя — AM_ASSIST_LEASH, а не 8 м: иначе отряд, пошедший на
## помощь, разворачивался бы обратно на полдороге. Угроза протухает за
## AM_THREAT_SEC без подтверждения; цели нет — отряды возвращаются к маршу
## тем же _resume_march. Сканов не прибавилось: угроза — запись на группу.
## Радиус помощи — не меньше AM_ASSIST_R и не меньше габарита самой группы
## (замер qa_campaign B: голова армии из 15 отрядов была в 47-67 м от удара
## по хвосту, и при 45 м десять отрядов маршировали дальше, пока хвост гиб)
const AM_ASSIST_R := 90.0
const AM_ASSIST_LEASH := 100.0
const AM_THREAT_SEC := 2.0
const AM_HIT_SEC := 1.5

## ── КОЛОННА НЕ РВЁТСЯ (ТЗ 10.10.2026, блок 2; замер qa_campaign) ──────────
## Два вида разрыва на марше после стычки: (1) боец, добивавший врага после
## общего возобновления марша, по исчерпании цели встаёт «где стоит» — и
## остаётся в 100 м позади (его пост не в точке назначения); (2) задержавшиеся
## в бою идут хвостом в 20-40 м. Командир в каждый свой такт (скан не нужен —
## состав уже прочитан) переиздаёт марш «потерянным» и выравнивает ТЕМП:
## голова, ушедшая вперёд медианы дальше PACE_AHEAD при отставшем хвосте,
## идёт на PACE_SLOW; хвост дальше PACE_BEHIND — на PACE_FAST
const PACE_AHEAD := 4.0
const PACE_BEHIND := 6.0
const PACE_SLOW := 0.75
const PACE_FAST := 1.25
## Просвет вдоль хода, с которого колонна считается разорванной (м)
const PACE_GAP := 2.5
## Пост дальше этого от точки назначения (сверх габарита строя) — боец «потерян»
const LOST_SLACK := 12.0
var lost_reissued: int = 0
const LOST_GAP_MS := 3000
const REJOIN_M := 14.0
const REJOIN_GAP_MS := 4000
var rejoins: int = 0
## Стендам: сколько раз отряд пошёл на угрозу группы / на ударившего
var assists: int = 0
var hit_reacts: int = 0
var _grp_threat: Dictionary = {}     # grp -> {"foe": Node3D, "t": мс}

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
## march = false — марш уже отдан вызывающим (строй по линии с боем,
## SelectionManager.attack_move_line): здесь только постановка на учёт
func attack_move(sm: Node, dest: Vector3, run: bool = false, march: bool = true) -> int:
	if sm == null or not is_instance_valid(sm):
		return 0
	dest.y = 0.0
	var sids: Dictionary = _selected_squads(sm)
	if sids.is_empty():
		return 0
	_drop_defense(sids)
	if march:
		sm.march_selection_to(dest, run)
	return _register_am(sids, dest, run, not march)

## Перед протяжкой с боем: снять «защиту», иначе разметка уйдёт в шаг фаланги
func prepare_attack_move(sm: Node) -> void:
	_drop_defense(_selected_squads(sm))

func _drop_defense(sids: Dictionary) -> void:
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

## own_dest — у каждого отряда СВОЯ конечная точка: середина его постов (строй
## по линии с боем). Общая середина линии делала крайние отряды «потерянными»
## (_keep_column: пост дальше разброса от точки) — их переводили маршем в
## центр линии, и строй собирался кучей (зонд qa_tz1012/FormProbe am=1)
func _register_am(sids: Dictionary, dest: Vector3, run: bool, own_dest: bool = false) -> int:
	# Номер клика: отряды одного [A] идут ФРОНТОМ и делят чужую линию между
	# собой (см. _front_target), отряды разных кликов друг другу не соседи
	_group_seq += 1
	for sid2 in sids:
		var d: Vector3 = dest
		if own_dest:
			d = _posts_centre(int(sid2), dest)
		_am[int(sid2)] = {
			"grp": _group_seq,
			"dest": d, "run": run, "clear": 0,
			"wait": 0.0, "fighting": false,
			# Точка, где отряд свернул с марша к врагу. Vector3.INF — не
			# свернул (значением, а не парой: правило 14)
			"hold": Vector3.INF,
			# Случайная фаза: первый скан где-то внутри интервала марша
			"next_scan": Time.get_ticks_msec() + _rng.randi_range(0, SCAN_MARCH_MS),
		}
		GameManager.squad_note_order(int(sid2), GameManager.ORDER_MOVE, d)
	active_count = _am.size()
	return sids.size()

## Середина постов отряда (куда его поставил последний приказ)
func _posts_centre(sid: int, fallback: Vector3) -> Vector3:
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return fallback
	var acc := Vector3.ZERO
	var n := 0
	for m in ((sq as Dictionary)["members"] as Array):
		if m == null or not is_instance_valid(m) or (m as Unit).is_dead():
			continue
		acc += (m as Unit).post_pos
		n += 1
	if n == 0:
		return fallback
	acc /= float(n)
	acc.y = 0.0
	return acc

## Снять режим у отряда (любой новый приказ игрока это делает — см.
## SelectionManager: ПКМ и клавиши стоек зовут cancel_squad)
func cancel_squad(sid: int) -> void:
	_drop_orders(sid)
	if _am.erase(sid):
		active_count = _am.size()
		_pace_reset(sid)

## Снять темп колонны со всех бойцов отряда
func _pace_reset(sid: int) -> void:
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m):
			(m as Unit).pace_mult = 1.0

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
	if _am.is_empty() and _oq_ids.is_empty():
		if not _queue.is_empty():
			_queue.clear()
		if not _grp_pairs.is_empty():
			_grp_pairs.clear()
		if not _grp_threat.is_empty():
			_grp_threat.clear()
		if not _grp_span.is_empty():
			_grp_span.clear()
		return
	var t_us: int = Time.get_ticks_usec() if stat_on else 0
	var sc0: int = scans
	_physics_body(delta)
	if stat_on:
		frame_usec.append(Time.get_ticks_usec() - t_us)
		frame_scans.append(scans - sc0)
		var sec: int = (Time.get_ticks_msec() - _stat_t0) / 1000
		while scans_by_sec.size() <= sec:
			scans_by_sec.append(0)
		scans_by_sec[sec] += scans - sc0

func _physics_body(delta: float) -> void:
	_drain_orders()
	if _am.is_empty():
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
		var tt: int = Time.get_ticks_usec()
		_tick_squad(int(_queue.pop_back()), delta)
		tick_max_us = maxi(tick_max_us, Time.get_ticks_usec() - tt)

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
	var leash: float = float(st.get("leash", AM_LEASH))
	if hold != Vector3.INF and cpos.distance_to(hold) > leash:
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
	# Адаптивно — скан по расписанию отряда, между сканами — последний враг
	var foe: Node3D = null
	var now_s: int = Time.get_ticks_msec()
	var do_scan: bool = true
	if _OptSC.am_adaptive:
		do_scan = now_s >= int(st.get("next_scan", 0))
		if not do_scan:
			var raw_f: Variant = st.get("foe")
			if typeof(raw_f) == TYPE_OBJECT and is_instance_valid(raw_f) \
					and not (raw_f as Unit).is_dead() \
					and Vector2((raw_f as Unit).global_position.x - cpos.x,
						(raw_f as Unit).global_position.z - cpos.z).length() <= _scan_radius(lead) * 1.25:
				foe = raw_f
			elif bool(st["fighting"]) and st.has("foe"):
				# Враг отряда пал или ушёл посреди боя — скан вне очереди
				st.erase("foe")
				if now_s - int(st.get("last_scan", 0)) >= SCAN_MIN_GAP_MS:
					do_scan = true
	if do_scan:
		foe = _scan_enemy(lead, cpos, _scan_radius(lead))
		st["last_scan"] = now_s
		if foe != null:
			st["foe"] = foe
		else:
			st.erase("foe")
		if _OptSC.am_adaptive:
			st["next_scan"] = now_s + _scan_interval_ms(st, lead, foe != null)
	var grp: int = int(st.get("grp", 0))
	var far_threat := false
	if foe != null:
		_grp_threat[grp] = {"foe": foe, "t": Time.get_ticks_msec()}
	else:
		# 2б. Нас бьют издали или во фланг — ударивший и есть угроза группы
		foe = _hit_foe(sid, lead)
		if foe != null:
			hit_reacts += 1
			_grp_threat[grp] = {"foe": foe, "t": Time.get_ticks_msec()}
			far_threat = true
		else:
			# 2в. Угроза группы рядом — разворачиваемся на неё всей армией
			foe = _group_threat_foe(grp, cpos)
			if foe != null:
				far_threat = true
				if not bool(st["fighting"]):
					assists += 1
	if foe != null and far_threat:
		st["leash"] = AM_ASSIST_LEASH
		# ДАЛЬНЯЯ УГРОЗА — ПОДХОД СТРОЕМ, А НЕ ПРИКАЗ АТАКИ. Несфорсированный
		# command_attack на цель в 60 м марш игрока не перебивает (замер B:
		# все 15 «в бою», а голова уходила дальше), а стрелок цель за
		# дальностью бросает вовсе. Отряд идёт к угрозе: стрелок — на 0.8
		# дальности, пехота — вплотную; рубку даёт обычный скан на подходе
		var fpos: Vector3 = foe.global_position
		fpos.y = 0.0
		# Подход — к СВОЕМУ участку чужой линии (раскладка фронт-на-фронт),
		# а не всей группой в одну точку угрозы: иначе фронт сжимался
		# (qa_tz0925 C4: 57 из 108 м)
		var fsid0: int = _front_target(sid, st, cpos, foe)
		if fsid0 > 0:
			var fc: Vector2 = GameManager.squad_centre_xz(fsid0)
			if fc != Vector2.INF:
				fpos = Vector3(fc.x, 0.0, fc.y)
		var reach: float = _scan_radius(lead)
		var stand: float = lead.attack_range * 0.8 if not lead.pursues_target() else 1.0
		if cpos.distance_to(fpos) > reach:
			st["clear"] = 0
			st["wait"] = AM_RESUME_GAP
			if hold == Vector3.INF:
				st["hold"] = cpos
			if not bool(st["fighting"]):
				st["fighting"] = true
				engagements += 1
				_pace_reset(sid)
			# Переприказ — только если угроза сместилась или прошло 2 с:
			# иначе каждый такт (0.3 с) будил бы и перестраивал весь отряд
			var now_a: int = Time.get_ticks_msec()
			var last_p: Variant = st.get("assist_p")
			if last_p == null or (last_p as Vector3).distance_to(fpos) > 6.0 					or now_a - int(st.get("assist_t", 0)) > 2000:
				st["assist_p"] = fpos
				st["assist_t"] = now_a
				_assist_move(sid, alive, cpos, fpos, stand)
			return
	elif foe != null:
		st["leash"] = maxf(float(st.get("leash", AM_LEASH)), AM_LEASH) \
			if bool(st["fighting"]) else AM_LEASH
	if foe != null:
		st["clear"] = 0
		st["wait"] = AM_RESUME_GAP
		if hold == Vector3.INF:
			st["hold"] = cpos
		if not bool(st["fighting"]):
			st["fighting"] = true
			engagements += 1
			_pace_reset(sid)
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
			if _OptSC.am_order_queue:
				_atk_sink.clear()
				GameManager.squad_attack_squad(sid, fsid, false, _atk_sink)
				var k := 0
				while k + 1 < _atk_sink.size():
					_enqueue(_atk_sink[k] as Unit, sid, OQ_ATTACK, _atk_sink[k + 1], false, null)
					k += 2
			else:
				GameManager.squad_attack_squad(sid, fsid, false)
		else:
			for u in alive:
				_enqueue(u as Unit, sid, OQ_ATTACK, foe, false, null)
		GameManager.squad_note_order(sid, GameManager.ORDER_ATTACK,
			foe.global_position, foe)
		return
	# Скана не было, а отряд дерётся — решение «зачищено» ждёт скана: иначе
	# такт без скана выводил бы отряд из боя, пока бойцы ещё рубятся
	if not do_scan and bool(st["fighting"]):
		return
	# Врага в досягаемости нет — место стычки больше ничего не держит
	st["hold"] = Vector3.INF
	st["leash"] = AM_LEASH

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
		_pace_reset(sid)
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
		_keep_column(sid, alive, cpos, dest, bool(st["run"]))
		return
	st["fighting"] = false
	resumes += 1
	_resume_march(sid, alive, dest, bool(st["run"]))

## Колонна на марше: «потерянным» — марш заново (одним разбором мест на весь
## отряд), растянутой — темп. O(n) на такт отряда, без сканов
func _keep_column(sid: int, alive: Array, cpos: Vector3, dest: Vector3, run: bool) -> void:
	var course: Vector3 = dest - cpos
	course.y = 0.0
	var dist: float = course.length()
	if dist < 0.5:
		return
	course /= dist
	# КУРС — ПО ФАКТИЧЕСКОМУ ХОДУ ЦЕНТРА, а не «на цель»: дорога огибает лес
	# и ведёт к броду, и ось «на цель» сжимала просвет колонны вдвое
	var e0: Variant = _am.get(sid)
	if e0 != null:
		var lastc: Variant = (e0 as Dictionary).get("lastc")
		(e0 as Dictionary)["lastc"] = cpos
		if lastc != null:
			var mv: Vector3 = cpos - (lastc as Vector3)
			mv.y = 0.0
			if mv.length() > 0.2:
				course = mv.normalized()
	var spread: float = sqrt(float(alive.size())) * 0.8
	var lost := false
	var behind := false
	for u in alive:
		var un := u as Unit
		if un.state == Unit.State.ATTACKING or un.retreating or un._panicked:
			continue
		var pp: Vector3 = un.post_pos
		if Vector2(pp.x - dest.x, pp.z - dest.z).length() > spread + LOST_SLACK:
			lost = true
			break
		var rel: Vector3 = un.global_position - cpos
		if rel.x * course.x + rel.z * course.z < -PACE_BEHIND:
			behind = true
	# Не чаще раза в LOST_GAP_MS на отряд: пост, сдвинутый от точки (вода,
	# фундамент, занятое место), иначе переиздавал бы марш каждый такт
	var now: int = Time.get_ticks_msec()
	var e: Variant = _am.get(sid)
	if lost and e != null and now - int((e as Dictionary).get("lost_t", -100000)) < LOST_GAP_MS:
		lost = false
	if lost and _has_pending(sid):
		lost = false
	if lost:
		(e as Dictionary)["lost_t"] = now
		lost_reissued += 1
		_pace_reset(sid)
		_resume_march(sid, alive, dest, run)
		return
	# ПРОСВЕТ ВДОЛЬ ХОДА: идущие бойцы раскладываются по оси курса, ищется
	# наибольший разрыв между соседями. Шире PACE_GAP — все впереди него идут
	# на PACE_SLOW, позади — на PACE_FAST, пока колонна не сомкнётся. Мерить
	# от медианы мало: голова и хвост по ±3.5 м от неё с просветом 7 м между
	# собой медиане «не видны» (замер qa_campaign, куски отрядов 68/69)
	var idx: Array = []
	var along := PackedFloat32Array()
	along.resize(alive.size())
	for i in range(alive.size()):
		var un3 := alive[i] as Unit
		var rel3: Vector3 = un3.global_position - cpos
		along[i] = rel3.x * course.x + rel3.z * course.z
		if un3.state == Unit.State.MOVING:
			idx.append(i)
	idx.sort_custom(func(x, y): return along[int(x)] < along[int(y)])
	var gap := 0.0
	var split := INF
	for k in range(1, idx.size()):
		var g: float = along[int(idx[k])] - along[int(idx[k - 1])]
		if g > gap:
			gap = g
			split = along[int(idx[k])]
	# ВОЗВРАТ В КОЛОННУ: боец дальше REJOIN_M от центра на марше идёт СВОЕЙ
	# дорогой (обход с другой стороны рощи, выход из барака за стеной). Тот же
	# приказ заново пересобирает дорогу от его точки с присоединением к дороге
	# отряда (GameManager.squad_leg). Не чаще REJOIN_GAP_MS на бойца
	var now_r: int = Time.get_ticks_msec()
	# Порог — по длине отряда: колонна в узкости (брод, проход в лесу) законно
	# вытягивается, и возвращать её середину значило бы пересобирать дороги
	# всем подряд (замер: +A*, рывки у брода)
	var rejoin_r: float = REJOIN_M + 0.2 * float(alive.size())
	for u4 in alive:
		var un4 := u4 as Unit
		if un4.state == Unit.State.ATTACKING or un4.retreating or un4._panicked:
			continue
		var r4: Vector3 = un4.global_position - cpos
		if Vector2(r4.x, r4.z).length() <= rejoin_r:
			continue
		if now_r - int(un4.get_meta("am_rejoin", -100000)) < REJOIN_GAP_MS:
			continue
		un4.set_meta("am_rejoin", now_r)
		var pp4: Vector3 = un4.post_pos
		pp4.y = 0.0
		_enqueue(un4, sid, OQ_MOVE, pp4, course, run)
		rejoins += 1
	var paced: bool = gap > PACE_GAP or behind
	for i2 in range(alive.size()):
		var un2 := alive[i2] as Unit
		var want := 1.0
		if paced and un2.state == Unit.State.MOVING:
			if gap > PACE_GAP:
				want = PACE_SLOW if along[i2] >= split else PACE_FAST
			elif along[i2] > PACE_AHEAD:
				want = PACE_SLOW
			elif along[i2] < -PACE_BEHIND:
				want = PACE_FAST
		if un2.pace_mult != want:
			un2.pace_mult = want

## Интервал следующего скана по состоянию отряда, с разбросом ×(1±JITTER)
func _scan_interval_ms(st: Dictionary, lead: Unit, found: bool) -> int:
	var base: int = SCAN_MARCH_MS
	if found or bool(st["fighting"]):
		base = SCAN_COMBAT_MS
	elif lead.state != Unit.State.MOVING:
		base = SCAN_IDLE_MS
	return int(float(base) * _rng.randf_range(1.0 - SCAN_JITTER, 1.0 + SCAN_JITTER))

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
			var cdir: Vector3 = course.normalized() if course.length() > 0.1 else Vector3.FORWARD
			GameManager.squad_set_formation(sid, moved, cdir, false)
			# ── СТРОЙ СОБИРАЕТСЯ ЗАНОВО, А НЕ ПЕРЕНОСИТСЯ РАССЫПАННЫМ ──────────
			# (ТЗ 10.10.2026, блок 2; замер qa_campaign A5: до 20 отставших на
			# отряд и 50 м хвоста). Прежде каждый боец шёл в «свою точку +
			# общий вектор», то есть рассыпание стычки маршировало через всю
			# карту как есть. Теперь каждый получает СВОЁ место разметки в
			# точке назначения — тем же жадным разбором «ячейка спереди назад
			# → ближайший боец», что у смыкания рядов (SquadFormation): отряд
			# стягивается в строй на ходу
			if moved.size() >= alive.size():
				_march_to_slots(alive, moved, cdir, run)
				GameManager.squad_note_order(sid, GameManager.ORDER_MOVE, dest)
				return
	for u in alive:
		var un := u as Unit
		if un == null or not un.has_method("command_move"):
			continue
		var p: Vector3 = un.global_position + shift
		p.y = 0.0
		_enqueue(un, sid, OQ_MOVE, p, Vector3.ZERO, run)
	GameManager.squad_note_order(sid, GameManager.ORDER_MOVE, dest)

## Раздать живым места разметки: ячейки по порядку (спереди назад), каждой —
## ближайший ещё не занятый боец. O(n·m) на возобновление марша (60×60 —
## микросекунды, раз на стычку), покадрового пути здесь нет
var regrouped: int = 0
func _march_to_slots(alive: Array, slots: Array, course: Vector3, run: bool) -> void:
	var n: int = alive.size()
	var px := PackedFloat32Array()
	var pz := PackedFloat32Array()
	px.resize(n); pz.resize(n)
	for i in range(n):
		var p0: Vector3 = (alive[i] as Node3D).global_position
		px[i] = p0.x
		pz[i] = p0.z
	var taken := PackedByteArray()
	taken.resize(n)
	var left: int = n
	for si in range(slots.size()):
		if left <= 0:
			break
		var sl: Vector3 = slots[si]
		var best := -1
		var best_d := INF
		for i in range(n):
			if taken[i] == 1:
				continue
			var dx: float = px[i] - sl.x
			var dz: float = pz[i] - sl.z
			var d: float = dx * dx + dz * dz
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			break
		taken[best] = 1
		left -= 1
		var un := alive[best] as Unit
		if un == null or not un.has_method("command_move"):
			continue
		sl.y = 0.0
		_enqueue(un, _sid_of(un), OQ_MOVE, sl, course, run)
	regrouped += 1

## Кто ударил отряд за последние AM_HIT_SEC (squad_mark_hit). Только живой
## чужой БОЕЦ: постройки Attack-Move не штурмует (см. _scan_enemy)
func _hit_foe(sid: int, lead: Unit) -> Node3D:
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return null
	var d: Dictionary = sq
	if Time.get_ticks_msec() - int(d.get("last_hit_ms", -100000)) > int(AM_HIT_SEC * 1000.0):
		return null
	var raw: Variant = d.get("last_hit_by")
	# Правило 5: освобождённый объект — проверка на СЫРОЙ ссылке
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw):
		return null
	var fu := raw as Unit
	if fu == null or fu.is_dead() or fu.faction == lead.faction or fu.garrisoned:
		return null
	return fu

## Угроза группы в радиусе помощи (свежая, живая)
func _group_threat_foe(grp: int, cpos: Vector3) -> Node3D:
	var rec: Variant = _grp_threat.get(grp)
	if rec == null:
		return null
	var r: Dictionary = rec
	if Time.get_ticks_msec() - int(r["t"]) > int(AM_THREAT_SEC * 1000.0):
		_grp_threat.erase(grp)
		return null
	var raw: Variant = r["foe"]
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw):
		_grp_threat.erase(grp)
		return null
	var fu := raw as Unit
	if fu == null or fu.is_dead():
		_grp_threat.erase(grp)
		return null
	var fp: Vector3 = fu.global_position
	if Vector2(fp.x - cpos.x, fp.z - cpos.z).length() > maxf(AM_ASSIST_R, _group_span(grp) * 2.0 + 20.0):
		return null
	return fu

## Габарит группы клика: наибольшее расстояние центра отряда до середины
## группы (раз в такт группы — кэш на AM_TICK_SEC)
var _grp_span: Dictionary = {}
func _group_span(grp: int) -> float:
	var now: int = Time.get_ticks_msec()
	var rec: Variant = _grp_span.get(grp)
	if rec != null and now - int((rec as Array)[0]) < int(AM_TICK_SEC * 1000.0):
		return float((rec as Array)[1])
	var pts: Array = []
	var mid := Vector3.ZERO
	for k in _am.keys():
		if int((_am[k] as Dictionary).get("grp", -1)) != grp:
			continue
		var c: Vector2 = GameManager.squad_centre_xz(int(k))
		if c != Vector2.INF:
			pts.append(Vector3(c.x, 0.0, c.y))
			mid += Vector3(c.x, 0.0, c.y)
	var span := 0.0
	if not pts.is_empty():
		mid /= float(pts.size())
		for q in pts:
			span = maxf(span, (q as Vector3).distance_to(mid))
	_grp_span[grp] = [now, span]
	return span

## Подвести отряд (строем, переносом) так, чтобы центр встал в stand_off от
## точки угрозы — разворот стрелков к флангу
func _assist_move(sid: int, alive: Array, cpos: Vector3, fpos: Vector3, stand_off: float) -> void:
	var dir: Vector3 = fpos - cpos
	dir.y = 0.0
	var dist: float = dir.length()
	if dist < 0.1:
		return
	var goal: Vector3 = cpos + dir / dist * maxf(dist - stand_off, 0.0)
	var shift: Vector3 = goal - cpos
	for u in alive:
		var un := u as Unit
		if un == null or not un.has_method("command_move"):
			continue
		var p: Vector3 = un.global_position + shift
		p.y = 0.0
		_enqueue(un, sid, OQ_MOVE, p, dir / dist, false)
	GameManager.squad_note_order(sid, GameManager.ORDER_MOVE, goal)

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
