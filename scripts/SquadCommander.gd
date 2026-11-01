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
const _SqFormSC := preload("res://scripts/units/SquadFormation.gd")

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
	if Unit.dbg_order_src:
		var stk: Array = get_stack()
		_dbg_enq[id] = "%s@%d" % [String((stk[1] as Dictionary).get("function", "?")) if stk.size() > 1 else "?",
			Engine.get_physics_frames()]
	oq_queued += 1
	oq_depth_max = maxi(oq_depth_max, _oq.size())

## Отладка стендов (Unit.dbg_order_src): кто поставил приказ в очередь
var _dbg_enq: Dictionary = {}

func _issue(u: Unit, kind: int, a, b, c) -> void:
	# Метка источника для зонда order_override_bug: в экспорте get_stack()
	# пуст, и марш [A] с перехватом по дороге считался снятием приказа игрока
	GameManager.probes.ctx = "attack_move"
	if kind == OQ_MOVE:
		if _OptSC.cmd_meter: _OptSC.cmd_src = "attack_move"
		u.command_move(a, false, b, false, true, c)
		if _OptSC.cmd_meter: _OptSC.cmd_src = ""
	else:
		u.command_attack(a, bool(b))
	GameManager.probes.ctx = ""
	if Unit.dbg_order_src:
		var src: Variant = _dbg_enq.get(u.get_instance_id())
		if src != null:
			var parts: PackedStringArray = String(src).split("@")
			u.dbg_src = "q:%s ждал %d кадр" % [parts[0], Engine.get_physics_frames() - int(parts[1])]
			_dbg_enq.erase(u.get_instance_id())

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
		if int(r[1]) == OQ_ATTACK and (not is_instance_valid(tgt) \
				or (tgt is Unit and (tgt as Unit).is_dead()) \
				or (tgt is Building and (tgt as Building).is_dead())):
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
	_stat_t0 = Unit.game_ms()
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
## Сколько раз отряд группы Ctrl+N встал держать фронт (стендам)
var line_halts: int = 0
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
	# ── У КАЖДОГО ОТРЯДА СВОЯ ТОЧКА И ПРИ КЛИКЕ (ТЗ 23.10.2026, п. 2-3) ────
	# Клик [A] группой раскладывает отряды сеткой/схемой Ctrl+N, а точкой
	# назначения у всех стояла точка клика: крайние отряды широкой группы
	# (пост дальше LOST_SLACK от неё) считались «потерянными», и командир
	# переводил их маршем В ЦЕНТР — армия на марше с боем стягивалась в одну
	# круглую кашу (скриншоты 23.10). Теперь точка — середина своих постов,
	# как у протяжки с боем
	var n_reg: int = _register_am(sids, dest, run, (not march) or _OptSC.am_own_dest)
	# Группа Ctrl+N со схемой — линия держит фронт (см. _tick_squad, 2в)
	var gi: int = int(sm.call("current_group_index")) if sm.has_method("current_group_index") else -1
	if gi >= 0 and not (sm.get("_group_layouts")[gi] as Dictionary).is_empty():
		for sid_l in sids:
			var e_l: Variant = _am.get(int(sid_l))
			if e_l != null:
				(e_l as Dictionary)["line"] = true
	return n_reg

## Перед протяжкой с боем: снять «защиту», иначе разметка уйдёт в шаг фаланги
func prepare_attack_move(sm: Node) -> void:
	_drop_defense(_selected_squads(sm))

## Прежняя стойка отрядов, снятая _drop_defense и ещё не положенная в запись
## режима (_register_am идёт следом за prepare_attack_move / attack_move)
var _stance0: Dictionary = {}
var stance_restores: int = 0

func _drop_defense(sids: Dictionary) -> void:
	# ── [A] — НАДСТРОЙКА НАД СТОЙКОЙ (ТЗ 31.10.2026) ───────────────────────
	# «В Защите через атаку он должен идти, как если бы стоял, а я кликнул по
	# ближнему отряду, — и фаланга пошла». Стойка не меняется; встреченного
	# фаланга бьёт прямым приказом (_def_forced) — переносом стены
	if _OptSC.am_keep_defense:
		return
	# Отряд, которому велели идти с боем, обязан быть вправе идти: в стойке
	# ЗАЩИТА нет инициативы (авто-агро только перед фронтом), и марш с боем
	# вырождался бы в марш. Стойка ВОЗВРАЩАЕТСЯ при снятии режима (ТЗ
	# 28.10.2026, пятое письмо: «после прибытия — прежнее состояние»)
	for sid in sids:
		var sq: Variant = GameManager.squads.get(int(sid))
		if sq == null:
			continue
		var was: String = ""
		for m in ((sq as Dictionary)["members"] as Array):
			if m != null and is_instance_valid(m) and m.has_method("set_stance"):
				if was == "":
					was = String((m as Unit).stance)
				if String((m as Unit).stance) == _UCfgSC.STANCE_DEFENSE:
					(m as Unit).set_stance(_UCfgSC.STANCE_ATTACK)
		# Повторный [A] поверх действующего: прежняя стойка уже в записи —
		# нести её дальше, а не «атаку», в которую отряд переведён режимом
		var old: Variant = _am.get(int(sid))
		if old != null and String((old as Dictionary).get("stance0", "")) != "":
			was = String((old as Dictionary)["stance0"])
		if was != "" and not _stance0.has(int(sid)):
			_stance0[int(sid)] = was

## Вернуть отряду стойку, в которой он был до [A] (ручка am_stance_restore).
## Без клича: это не новый приказ игрока, а возврат к его прежнему
func _restore_stance(sid: int, st: Dictionary) -> void:
	if not _OptSC.am_stance_restore:
		return
	var was: String = String(st.get("stance0", ""))
	if was == "" or was == _UCfgSC.STANCE_ATTACK:
		return
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return
	var changed := false
	for m in ((sq as Dictionary)["members"] as Array):
		if m == null or not is_instance_valid(m) or not m.has_method("set_stance"):
			continue
		if (m as Unit).is_dead() or String((m as Unit).stance) == was:
			continue
		(m as Unit).set_stance(was)
		changed = true
	if changed:
		GameManager.on_squad_stance(sid, was)
		stance_restores += 1

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
		# Повторный [A]: остаток очереди и темп прежнего режима — долой
		if _am.has(int(sid2)):
			_drop_orders(int(sid2))
			_pace_reset(int(sid2))
		var st0: String = String(_stance0.get(int(sid2), ""))
		_stance0.erase(int(sid2))
		_am[int(sid2)] = {
			"grp": _group_seq,
			"stance0": st0,
			"dest": d, "run": run, "clear": 0,
			"wait": 0.0, "fighting": false,
			# Точка, где отряд свернул с марша к врагу. Vector3.INF — не
			# свернул (значением, а не парой: правило 14)
			"hold": Vector3.INF,
			# Случайная фаза: первый скан где-то внутри интервала марша
			"next_scan": Unit.game_ms() + _rng.randi_range(0, SCAN_MARCH_MS),
		}
		GameManager.squad_note_order(int(sid2), GameManager.ORDER_MOVE, d)
		GameManager.am_group_of[int(sid2)] = _group_seq
		GameManager.am_marching[int(sid2)] = d
	_stance0.clear()
	active_count = _am.size()
	_update_group_centres()
	return sids.size()

## Центр каждой группы [A] — медиана центров её отрядов; читает
## GameManager.squad_leg (одна дорога на группу, ручка am_group_route)
var _grp_centre_t: float = 0.0
const GRP_CENTRE_SEC := 0.5

func _update_group_centres() -> void:
	# Array, а не Packed: Packed-массив из словаря читается КОПИЕЙ, и append
	# в него терялся (зонд qa_am_map: 411 ошибок «index -1»)
	var xs: Dictionary = {}
	var zs: Dictionary = {}
	for sid in _am.keys():
		var c: Vector2 = GameManager.squad_centre_xz(int(sid))
		if c == Vector2.INF:
			continue
		var g: int = int((_am[sid] as Dictionary).get("grp", 0))
		if not xs.has(g):
			xs[g] = []
			zs[g] = []
		(xs[g] as Array).append(c.x)
		(zs[g] as Array).append(c.y)
	GameManager.am_group_centre.clear()
	for g in xs.keys():
		var ax: Array = xs[g]
		var az: Array = zs[g]
		ax.sort()
		az.sort()
		var n: int = ax.size()
		if n == 0:
			continue
		var h: int = n / 2
		var mx: float = float(ax[h]) if n % 2 == 1 else (float(ax[h - 1]) + float(ax[h])) * 0.5
		var mz: float = float(az[h]) if n % 2 == 1 else (float(az[h - 1]) + float(az[h])) * 0.5
		GameManager.am_group_centre[g] = Vector3(mx, 0.0, mz)

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
	var e: Variant = _am.get(sid)
	if e != null:
		_am.erase(sid)
		GameManager.am_group_of.erase(sid)
		GameManager.am_marching.erase(sid)
		active_count = _am.size()
		_pace_reset(sid)
		_restore_stance(sid, e as Dictionary)

## Снять темп колонны со всех бойцов отряда
func _pace_reset(sid: int) -> void:
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m):
			(m as Unit).pace_mult = 1.0

## Отряд держит «Защиту» под [A] (am_keep_defense): приказ атаки ему — прямой
func _def_forced(lead: Unit) -> bool:
	return _OptSC.am_keep_defense and lead.stance == _UCfgSC.STANCE_DEFENSE and lead.is_combatant() and lead.pursues_target()

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
		var sec: int = (Unit.game_ms() - _stat_t0) / 1000
		while scans_by_sec.size() <= sec:
			scans_by_sec.append(0)
		scans_by_sec[sec] += scans - sc0

func _physics_body(delta: float) -> void:
	_drain_orders()
	if _am.is_empty():
		if not GameManager.am_group_of.is_empty():
			GameManager.am_group_of.clear()
			GameManager.am_group_centre.clear()
		if not GameManager.am_marching.is_empty():
			GameManager.am_marching.clear()
		return
	_grp_centre_t -= delta
	if _grp_centre_t <= 0.0:
		_grp_centre_t = GRP_CENTRE_SEC
		_update_group_centres()
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
	# Направление хода к точке — сектор марша для дошедшего (см. _in_march_cone)
	if _OptSC.am_own_dest:
		var dd: Vector3 = (st["dest"] as Vector3) - cpos
		dd.y = 0.0
		if dd.length() >= AM_ARRIVE * 2.0:
			st["mdir"] = Vector2(dd.x, dd.z).normalized()

	# ── 0. МОНАХИ — ПОДДЕРЖКА, А НЕ БОЙ (ТЗ 22.10.2026) ────────────────────
	# Отряд монахов в [A] шёл на угрозу группы «как пехота — вплотную»
	# (_assist_move, stand 1 м: у монаха pursues_target = да), а пока армия
	# рубилась, продолжал марш к точке приказа и обгонял её — гиб первым
	if _OptSC.monk_rear and not lead.is_combatant():
		_support_tick(sid, st, alive, cpos)
		return

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
	var now_s: int = Unit.game_ms()
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
				# ── ЗАПОМНЕННЫЙ ВРАГ ТОЖЕ ПРОХОДИТ СЕКТОР (ТЗ 29.10.2026, п. 4) ──
				# Между сканами отряд держал последнего врага без проверки
				# сектора: беглец орды, проскочивший мимо отряда (в 6 м он
				# «вплотную»), уводил весь отряд за спину на 6-10 м — отряд
				# в [A], вышедший из [S], «откатывался» за остатком волны
				if _OptSC.am_cone_memory and not _in_march_cone(st, cpos, foe):
					foe = null
					st.erase("foe")
					do_scan = now_s - int(st.get("last_scan", 0)) >= SCAN_MIN_GAP_MS
			elif bool(st["fighting"]) and st.has("foe"):
				# Враг отряда пал или ушёл посреди боя — скан вне очереди
				st.erase("foe")
				if now_s - int(st.get("last_scan", 0)) >= SCAN_MIN_GAP_MS:
					do_scan = true
	if do_scan:
		foe = _scan_enemy(lead, cpos, _scan_radius(lead))
		if foe != null and not _in_march_cone(st, cpos, foe):
			foe = null
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
		_grp_threat[grp] = {"foe": foe, "t": Unit.game_ms()}
	else:
		# 2б. Нас бьют издали или во фланг — ударивший и есть угроза группы
		foe = _hit_foe(sid, lead)
		if foe != null and not _in_march_cone(st, cpos, foe, AM_HIT_CONE_COS):
			foe = null
		if foe != null:
			hit_reacts += 1
			_grp_threat[grp] = {"foe": foe, "t": Unit.game_ms()}
			far_threat = true
		else:
			# 2в. Угроза группы рядом — разворачиваемся на неё всей армией
			foe = _group_threat_foe(grp, cpos)
			if foe != null and not _in_march_cone(st, cpos, foe) and not _group_fight_near(foe, cpos):
				foe = null
			# ── ЛИНИЯ ДЕРЖИТ ФРОНТ (ТЗ 23.10.2026, п. 3) ─────────────────
			# Группа со схемой Ctrl+N: центр упёрся в противника — остальные
			# отряды НЕ бегут к нему, а встают на месте строем и держат фронт;
			# свой враг в досягаемости (скан выше) или удар по отряду берут
			# их в бой штатно. Угроза ушла — марш дальше той же схемой
			if foe != null and _OptSC.group_line_hold and bool(st.get("line", false)):
				st["clear"] = 0
				st["wait"] = AM_RESUME_GAP
				if hold == Vector3.INF:
					st["hold"] = cpos
				if not bool(st["fighting"]):
					st["fighting"] = true
					engagements += 1
					line_halts += 1
					_pace_reset(sid)
					var fwd: Vector3 = GameManager.squad_course(sid)
					for u_h in alive:
						var uh := u_h as Unit
						if uh.state == Unit.State.MOVING:
							var hp: Vector3 = uh.global_position
							hp.y = 0.0
							_enqueue(uh, sid, OQ_MOVE, hp, fwd, false)
				return
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
			var now_a: int = Unit.game_ms()
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
		# Фаланга в «Защите» (am_keep_defense) без прямого приказа с места не
		# сходит: встреченного бьёт прямым — перенос стены (Unit._wall_goal)
		var dforced: bool = _def_forced(lead)
		if fsid > 0:
			if _OptSC.am_order_queue:
				_atk_sink.clear()
				GameManager.squad_attack_squad(sid, fsid, dforced, _atk_sink)
				var k := 0
				while k + 1 < _atk_sink.size():
					_enqueue(_atk_sink[k] as Unit, sid, OQ_ATTACK, _atk_sink[k + 1], dforced, null)
					k += 2
			else:
				GameManager.squad_attack_squad(sid, fsid, dforced)
		else:
			for u in alive:
				_enqueue(u as Unit, sid, OQ_ATTACK, foe, dforced, null)
		GameManager.squad_note_order(sid, GameManager.ORDER_ATTACK,
			foe.global_position, foe)
		# ── СТРЕЛКИ ВНЕ ДАЛЬНОСТИ ПОДТЯГИВАЮТСЯ ПОШТУЧНО (ТЗ 28.10.2026) ────
		# Скан берёт врага на 1.15 дальности + 2 м, а нефорсированный приказ
		# атаки стрелок за дальностью бросает («гнаться не буду») и стоит без
		# цели до следующего такта: задние ряды и дальний фланг замирали, не
		# стреляя. Кому до цели дальше дальности — шаг на 0.8 дальности (вместо
		# приказа атаки в очереди), кто достаёт — стреляет, не сходя с места
		if _OptSC.am_archer_standoff and not lead.pursues_target() and lead.is_combatant():
			_archers_close_in(sid, st, alive, fsid, foe)
		return
	# ── 2г. ПОСТРОЙКИ ПО ХОДУ (ТЗ 22.10.2026) ────────────────────────────
	# Чужих бойцов рядом нет, а в секторе марша стоит чужая постройка —
	# отряд встаёт и сносит её, потом марш продолжается (прежде здания
	# Attack-Move не замечал вовсе). Приказ — принудительный: несфорсированный
	# бросает цель за досягаемостью, а до стены надо дойти
	if _OptSC.am_buildings and lead.is_combatant():
		var bld: Building = null
		var rb: Variant = st.get("bld")
		if rb != null and is_instance_valid(rb) and not (rb as Building).is_dead():
			bld = rb
		elif do_scan or rb != null:
			bld = _scan_building(st, lead, cpos)
		if bld != null:
			st["bld"] = bld
			st["clear"] = 0
			st["wait"] = AM_RESUME_GAP
			st["leash"] = AM_ASSIST_LEASH
			if hold == Vector3.INF:
				st["hold"] = cpos
			if not bool(st["fighting"]):
				st["fighting"] = true
				engagements += 1
				bld_engages += 1
				_pace_reset(sid)
			var now_b: int = Unit.game_ms()
			if now_b - int(st.get("bld_t", -100000)) > 3000:
				st["bld_t"] = now_b
				for u in alive:
					if (u as Unit).attack_target != bld:
						_enqueue(u as Unit, sid, OQ_ATTACK, bld, true, null)
				GameManager.squad_note_order(sid, GameManager.ORDER_ATTACK, bld.global_position, bld)
			return
		st.erase("bld")
	# Скана не было, а отряд дерётся — решение «зачищено» ждёт скана: иначе
	# такт без скана выводил бы отряд из боя, пока бойцы ещё рубятся
	if not do_scan and bool(st["fighting"]):
		return
	# ── КТО-ТО ЕЩЁ РУБИТСЯ — НЕ ЗАЧИЩЕНО (29.10.2026) ─────────────────────
	# Скан идёт от ЦЕНТРА отряда на 1.15 дальности + 2 м и не видит врага у
	# передней кромки строя: командир объявлял «зачищено» при живой первой
	# волне, _resume_march слал command_move всем (цели сброшены, разметка
	# переехала), бойцы отходили от врага в упор и тут же брали его снова
	# (qa_no_retreat A-deep: откат 4.5 м, 52 эпизода «от врага»). Отряд
	# выходит из боя, когда ни у кого нет живой цели
	if bool(st["fighting"]) and _any_engaged(alive):
		st["clear"] = 0
		st["wait"] = AM_RESUME_GAP
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
	var fought: bool = bool(st["fighting"])
	# ── ГРУППА ПРИБЫВАЕТ ЦЕЛИКОМ (ТЗ 23.10.2026, к am_own_dest) ──────────────
	# У каждого отряда своя точка, и первый дошедший снимал режим раньше
	# соседей: дальше обычные правила (ответ на обстрел) уводили его за
	# стрелками во фланге (qa_attack_move_vector_test A3: увод 25 м). Дошедший
	# смыкается и ЖДЁТ в режиме [A] (сектор марша, поводок), пока не дойдут
	# все отряды клика, — тогда режим снимается со всех разом
	# ── ПРИБЫВШИЙ НЕ ВОЗВРАЩАЕТСЯ В ТОЧКУ ПОСЛЕ БОЯ (29.10.2026) ────────────
	# Отряд, дошедший и ждущий группу, после стычки оказывался дальше
	# AM_ARRIVE от точки и шёл в неё маршем назад (_resume_march к старой
	# разметке). Приказ уже исполнен: строй собирается там, где кончился бой,
	# разметка едет за ним (squad_close_ranks с перецентровкой)
	# ── ПРОШЁЛ СВОЮ ТОЧКУ — ТОЖЕ ДОШЁЛ (ТЗ 31.10.2026) ─────────────────────
	# Стычка уносит отряд вперёд за его место в строю группы (задний эшелон
	# глубокого строя рубится в первой линии): марш к точке был бы маршем
	# НАЗАД. Отряд строится там, где кончился бой
	var passed: bool = false
	if _OptSC.am_no_reform and fought:
		var md0: Variant = st.get("mdir")
		if md0 != null:
			passed = (dest.x - cpos.x) * (md0 as Vector2).x + (dest.z - cpos.z) * (md0 as Vector2).y <= 0.0
	if _OptSC.am_own_dest and (bool(st.get("arrived", false)) or cpos.distance_to(dest) <= AM_ARRIVE or passed):
		st["fighting"] = false
		if not bool(st.get("arrived", false)):
			st["arrived"] = true
			GameManager.am_marching.erase(sid)
			_pace_reset(sid)
			GameManager.squad_close_ranks(sid, fought)
		elif fought:
			_pace_reset(sid)
			GameManager.squad_close_ranks(sid, true)
		var grp_a: int = int(st.get("grp", 0))
		if not _group_arrived(grp_a):
			return
		for sid_g in _am.keys():
			if int((_am[sid_g] as Dictionary).get("grp", -1)) == grp_a:
				GameManager.squad_clear_order(int(sid_g))
				cancel_squad(int(sid_g))
		return
	if cpos.distance_to(dest) <= AM_ARRIVE or passed:
		# ПРИБЫЛИ — СМЫКАЕМ СТРОЙ И СНИМАЕМ РЕЖИМ. Смыкание, а не новая
		# разметка: разметка отряда не стиралась на время боя (её только
		# блокировали), и close_ranks вернёт выживших ровно в ту форму, в
		# которой отряд выходил, — это и есть заказанное «перестраиваются
		# точно в ту формацию». После боя — по месту боя (force), не назад
		_pace_reset(sid)
		GameManager.am_marching.erase(sid)
		GameManager.squad_close_ranks(sid, fought)
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

## ── СЕКТОР МАРША (ТЗ 22.10.2026, скриншот 15:54) ──────────────────────────
## Армия в [A] на юг раскалывалась: правое крыло сворачивало на 90° за
## одиночкой на фланге — скан, удар издали и угроза группы брали любого
## врага вокруг. Теперь берётся только враг в секторе ±60° по ходу к точке
## приказа или вплотную (AM_SIDE_CONTACT); у самой точки сектора нет
const AM_CONE_COS := 0.5
## «Кто ударил» издали (стрелок) разворачивает отряд в [A] только из
## сектора ±45°: у каждого отряда своя точка, ход крайнего — прямо вперёд, и
## стрелки во фланге на 50-60° уводили его вбок (qa_attack_move_vector_test A3)
const AM_HIT_CONE_COS := 0.7
const AM_SIDE_CONTACT := 6.0
var cone_skips: int = 0
var archer_standoffs: int = 0

## Угроза отряду, идущему [A], — в секторе его марша? (контратака на обстрел
## GameManager.squad_counter_charge спрашивает: иначе стрелки с фланга
## уводили отряд вбок мимо командира). Не в [A] — да
func threat_in_cone(sid: int, foe: Node3D) -> bool:
	var e: Variant = _am.get(sid)
	if e == null or foe == null:
		return true
	var c2: Vector2 = GameManager.squad_centre_xz(sid)
	if c2.x == INF:
		return true
	return _in_march_cone(e, Vector3(c2.x, 0.0, c2.y), foe, AM_HIT_CONE_COS)

func _in_march_cone(st: Dictionary, cpos: Vector3, foe: Node3D, cos_min: float = AM_CONE_COS) -> bool:
	if not _OptSC.am_march_cone or foe == null:
		return true
	var dest: Vector3 = st["dest"]
	var cx: float = dest.x - cpos.x
	var cz: float = dest.z - cpos.z
	var cl: float = sqrt(cx * cx + cz * cz)
	if cl < AM_ARRIVE * 2.0:
		# Дошедший и ждущий группу держит сектор ПОСЛЕДНЕГО хода, а не
		# «без сектора»: иначе стрелки во фланге уводили его вбок (A3)
		# (и подходящий к своей точке тоже: у каждого отряда она своя, и
		# крайний отряд у неё — у стрелков во фланге, а не в центре группы)
		var md: Variant = st.get("mdir")
		if md == null:
			return true
		cx = (md as Vector2).x
		cz = (md as Vector2).y
		cl = 1.0
	elif _OptSC.am_own_dest:
		st["mdir"] = Vector2(cx / cl, cz / cl)
	var fp: Vector3 = foe.global_position
	var fx: float = fp.x - cpos.x
	var fz: float = fp.z - cpos.z
	var fl: float = sqrt(fx * fx + fz * fz)
	if fl <= AM_SIDE_CONTACT:
		# Бегущий в панике «вплотную» не угроза: за ним отряд не
		# разворачивается (ТЗ 29.10.2026, п. 4); рубят его бойцы сами
		if not (_OptSC.am_cone_memory and foe is Unit and (foe as Unit).is_panicked()):
			return true
	if (cx * fx + cz * fz) / (cl * fl) >= cos_min:
		return true
	cone_skips += 1
	return false

## Сосед по группе уже рубится с НАСТОЯЩИМ отрядом врага рядом — помочь ему
## можно и вне сектора: отряд, прошедший мимо свалки, иначе уходил к точке и
## бросал своих (qa_monk_support_positioning: половина пехоты в 15-20 м от
## боя). Одиночку и мелочь на фланге сектор по-прежнему отсекает
const GROUP_FIGHT_MIN := 6
const GROUP_FIGHT_R := 30.0
func _group_fight_near(foe: Node3D, cpos: Vector3) -> bool:
	var fu := foe as Unit
	if fu == null or fu.squad_id <= 0:
		return false
	var fp: Vector3 = fu.global_position
	if Vector2(fp.x - cpos.x, fp.z - cpos.z).length() > GROUP_FIGHT_R:
		return false
	var sq: Variant = GameManager.squads.get(fu.squad_id)
	if sq == null:
		return false
	var n := 0
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
			if n >= GROUP_FIGHT_MIN:
				return true
	return false

## ── ПОСТРОЙКИ ПО ХОДУ ─────────────────────────────────────────────────────
## Радиус от центра отряда до СТЕНЫ постройки, в котором [A] её сносит
const AM_BLD_R := 12.0
var bld_engages: int = 0
var _bld_list: Array = []
var _bld_list_f: int = -1
var _bld_list_fac: int = -1

func _enemy_buildings(fac: int) -> Array:
	var f: int = Engine.get_physics_frames()
	if f == _bld_list_f and fac == _bld_list_fac:
		return _bld_list
	_bld_list_f = f
	_bld_list_fac = fac
	_bld_list = []
	for g in Constants.enemy_building_groups(fac):
		for n in get_tree().get_nodes_in_group(String(g)):
			if n == null or not is_instance_valid(n) or not (n is Building):
				continue
			var b := n as Building
			# Как условие победы: не рудники, не пни, не руины
			if b.is_dead() or b is Mine or String(b.building_id) == "troll_lair" \
					or b.is_in_group("ruins"):
				continue
			_bld_list.append(b)
	return _bld_list

func _scan_building(st: Dictionary, lead: Unit, cpos: Vector3) -> Building:
	var best: Building = null
	var bd: float = INF
	for n in _enemy_buildings(lead.faction):
		var b := n as Building
		if b == null or not is_instance_valid(b) or b.is_dead():
			continue
		var bp: Vector3 = b.global_position
		var half: float = maxf(b.build_size.x, b.build_size.z) * 0.5
		var d: float = Vector2(bp.x - cpos.x, bp.z - cpos.z).length() - half
		if d > AM_BLD_R or d >= bd:
			continue
		if d > AM_SIDE_CONTACT and not _in_march_cone(st, cpos, b):
			continue
		bd = d
		best = b
	return best

## ── ОТРЯД ПОДДЕРЖКИ В [A] (монахи) ────────────────────────────────────────
## Группа дерётся (угроза группы свежая) — отряд встаёт там, где он есть
## (за спинами: он идёт последним эшелоном), монах сам лечит из тыла
## (Monk._walk_to_patient встаёт со стороны, противоположной врагу).
## Угроза снята — марш продолжается вместе со всеми
const SUPPORT_THREAT_MS := 2500
## Не ближе этого к угрозе группы, м (ТЗ: «5-8 м за ближайшим боевым отрядом»
## — линия рубки сама в 1-2 м от врага)
const SUPPORT_KEEP := 9.0
var support_holds: int = 0

func _support_tick(sid: int, st: Dictionary, alive: Array, cpos: Vector3) -> void:
	var th: Variant = _grp_threat.get(int(st.get("grp", 0)))
	var hot: bool = th != null and Unit.game_ms() - int((th as Dictionary)["t"]) < SUPPORT_THREAT_MS
	if hot:
		# Тыловая дистанция: от угрозы группы не ближе SUPPORT_KEEP — отряд
		# поддержки встаёт (или отходит) на неё за спинами дерущихся
		var foe_raw: Variant = (th as Dictionary).get("foe")
		var back := Vector3.ZERO
		if typeof(foe_raw) == TYPE_OBJECT and is_instance_valid(foe_raw):
			var fp: Vector3 = (foe_raw as Node3D).global_position
			var away := Vector3(cpos.x - fp.x, 0.0, cpos.z - fp.z)
			var dl: float = away.length()
			if dl < SUPPORT_KEEP - 1.0:
				away = away / dl if dl > 0.1 else Vector3(0, 0, -1)
				back = away * (SUPPORT_KEEP - dl)
		if not bool(st["fighting"]) or back != Vector3.ZERO:
			var now_h: int = Unit.game_ms()
			if not bool(st["fighting"]) or now_h - int(st.get("keep_t", 0)) > 1500:
				st["keep_t"] = now_h
				if not bool(st["fighting"]):
					st["fighting"] = true
					support_holds += 1
				_drop_orders(sid)
				for u in alive:
					var un := u as Unit
					_enqueue(un, sid, OQ_MOVE, GameManager.land_target(un.global_position + back), Vector3.ZERO, false)
		return
	if bool(st["fighting"]):
		st["fighting"] = false
		resumes += 1
		_resume_march(sid, alive, st["dest"], bool(st["run"]))
		return
	var dest: Vector3 = st["dest"]
	if cpos.distance_to(dest) <= AM_ARRIVE:
		_pace_reset(sid)
		GameManager.squad_clear_order(sid)
		cancel_squad(sid)
		return
	_keep_column(sid, alive, cpos, dest, bool(st["run"]))

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
	var now: int = Unit.game_ms()
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
	var now_r: int = Unit.game_ms()
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
		# Ушедший ВПЕРЁД колонны назад не идёт — его догонят (темп колонны);
		# пост позади бойца тоже не зовёт его назад
		if _OptSC.am_no_reform and (r4.x * course.x + r4.z * course.z > 0.0
				or (un4.post_pos.x - un4.global_position.x) * course.x
				+ (un4.post_pos.z - un4.global_position.z) * course.z < 0.0):
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
	var now: int = Unit.game_ms()
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
	if _OptSC.am_front_guard and int(got) != fallback and not _pair_near(st, cpos, foe, int(got)):
		front_rejects += 1
		return fallback
	front_assigns += 1
	return int(got)

## ── ПАРА ФРОНТА НЕ УВОДИТ В СТОРОНУ (ТЗ 30.10.2026, скриншот 01:29) ──────
## front_pairs раскладывает по оси фронта ВСЕ чужие отряды в радиусе «габарит
## группы + досягаемость + 6 м» (у армии из 10-15 отрядов это 60-75 м) и
## раздаёт их нашим по порядку слева направо: крайний отряд получал крайнего
## врага — волну, идущую мимо в 50-70 м сбоку, — хотя свой враг стоял в
## досягаемости и в секторе марша. Подмена не проверялась ничем, а
## несфорсированная атака на отряд-пару (или подход к угрозе с поводком
## AM_ASSIST_LEASH 100 м) срывала отряд с линии. Пара годится, если её центр
## рядом с найденным врагом, либо не дальше него и в секторе марша
const FRONT_PAIR_NEAR := 12.0
const FRONT_PAIR_SLACK := 6.0
var front_rejects: int = 0

func _pair_near(st: Dictionary, cpos: Vector3, foe: Node3D, fsid: int) -> bool:
	var pc: Vector2 = GameManager.squad_centre_xz(fsid)
	if pc == Vector2.INF or foe == null:
		return false
	var fp: Vector3 = foe.global_position
	if Vector2(pc.x - fp.x, pc.y - fp.z).length() <= FRONT_PAIR_NEAR:
		return true
	var df: float = Vector2(fp.x - cpos.x, fp.z - cpos.z).length()
	var dp: float = Vector2(pc.x - cpos.x, pc.y - cpos.z).length()
	if dp > df + FRONT_PAIR_SLACK:
		return false
	# Сектор марша — тот же, что у скана (_in_march_cone), по центру пары
	var dest: Vector3 = st["dest"]
	var cx: float = dest.x - cpos.x
	var cz: float = dest.z - cpos.z
	var cl: float = sqrt(cx * cx + cz * cz)
	if cl < AM_ARRIVE * 2.0:
		var md: Variant = st.get("mdir")
		if md == null:
			return true
		cx = (md as Vector2).x
		cz = (md as Vector2).y
		cl = 1.0
	var px: float = pc.x - cpos.x
	var pz: float = pc.y - cpos.z
	var pl: float = sqrt(px * px + pz * pz)
	if pl <= AM_SIDE_CONTACT:
		return true
	return (cx * px + cz * pz) / (cl * pl) >= AM_CONE_COS

## Возобновить марш отряда в точку. Строй переносится ЦЕЛИКОМ — тем же
## приёмом, что и приказ игрока (см. GameManager.squad_set_formation через
## SelectionManager). Здесь его нет под рукой, поэтому шлём command_move
## каждому со смещением от центра: взаимное расположение не меняется
func _resume_march(sid: int, alive: Array, dest: Vector3, run: bool) -> void:
	var centroid: Vector3 = GameManager._centroid_of(alive)
	centroid.y = 0.0
	var shift: Vector3 = dest - centroid
	# ── ТОЧКА ПОЗАДИ — СТРОИМСЯ НА МЕСТЕ (ТЗ 31.10.2026) ────────────────────
	# Бой (или погоня по поводку) унёс отряд за его точку в строю группы:
	# марш к ней — марш НАЗАД. Отряд считается дошедшим и строится там, где
	# стоит (смыкание с перецентровкой), режим ждёт группу как у дошедших
	var e_r: Variant = _am.get(sid)
	if _OptSC.am_no_reform and e_r != null:
		var md_r: Variant = (e_r as Dictionary).get("mdir")
		# «Позади» — и «почти здесь»: точка ближе AM_REGROUP_AHEAD по ходу
		# раздала бы передним места за спиной (строй глубже этого запаса)
		if md_r != null and shift.x * (md_r as Vector2).x + shift.z * (md_r as Vector2).y <= AM_REGROUP_AHEAD:
			(e_r as Dictionary)["arrived"] = true
			(e_r as Dictionary)["fighting"] = false
			GameManager.am_marching.erase(sid)
			passed_dest += 1
			GameManager.squad_close_ranks(sid, true)
			return
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
## Отрядов, построенных на месте: бой унёс их за свою точку (ТЗ 31.10.2026)
var passed_dest: int = 0
## Точка ближе этого по ходу, м, — строимся на месте, а не маршем к ней
const AM_REGROUP_AHEAD := 4.0
func _march_to_slots(alive: Array, slots: Array, course: Vector3, run: bool) -> void:
	var n: int = alive.size()
	var px := PackedFloat32Array()
	var pz := PackedFloat32Array()
	px.resize(n); pz.resize(n)
	for i in range(n):
		var p0: Vector3 = (alive[i] as Node3D).global_position
		px[i] = p0.x
		pz[i] = p0.z
	# Раздача по рядам (ручка rank_match, см. SquadFormation.rank_pairs):
	# передние — в передние шеренги, без хода назад сквозь своих
	if _OptSC.rank_match:
		var ui: Array = range(n)
		var si_l: Array = range(mini(n, slots.size()))
		var pr: int = maxi(_SqFormSC._per_row(slots, course), 1)
		for pp in _SqFormSC.rank_pairs(px, pz, ui, slots, si_l, course, pr):
			var un0 := alive[int(pp[1])] as Unit
			if un0 == null or not un0.has_method("command_move"):
				continue
			var sl0: Vector3 = slots[int(pp[0])]
			sl0.y = 0.0
			_enqueue(un0, _sid_of(un0), OQ_MOVE, sl0, course, run)
		regrouped += 1
		return
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
	if Unit.game_ms() - int(d.get("last_hit_ms", -100000)) > int(AM_HIT_SEC * 1000.0):
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
	if Unit.game_ms() - int(r["t"]) > int(AM_THREAT_SEC * 1000.0):
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
	var now: int = Unit.game_ms()
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

## Стрелки отряда, не достающие до цели, идут к ней на 0.8 своей дальности
## (ручка am_archer_standoff). Точка цели — центр чужого отряда-цели (fsid) или
## сам враг. Не чаще раза в 2 с на отряд: приказ будит бойца и метит позу
func _archers_close_in(sid: int, st: Dictionary, alive: Array, fsid: int, foe: Node3D) -> void:
	var now_a: int = Unit.game_ms()
	if now_a - int(st.get("adv_t", -100000)) < 2000:
		return
	var fpos: Vector3 = foe.global_position
	if fsid > 0:
		var fc: Vector2 = GameManager.squad_centre_xz(fsid)
		if fc != Vector2.INF:
			fpos = Vector3(fc.x, 0.0, fc.y)
	fpos.y = 0.0
	var sent := 0
	for u in alive:
		var un := u as Unit
		if un.state == Unit.State.ATTACKING or un.retreating or un._panicked:
			continue
		var mp: Vector3 = un.global_position
		mp.y = 0.0
		var d: float = mp.distance_to(fpos)
		var rng: float = un.attack_range
		if d <= rng * 0.95 or d < 0.1:
			continue
		var dir: Vector3 = (fpos - mp) / d
		var goal: Vector3 = mp + dir * (d - rng * 0.8)
		_enqueue(un, sid, OQ_MOVE, goal, dir, false)
		sent += 1
	if sent > 0:
		st["adv_t"] = now_a
		archer_standoffs += 1

## Радиус ВСТУПЛЕНИЯ В БОЙ по роду войск вожака. Пол — собственный радиус
## инициативы бойца (AGGRO_RADIUS): ниже него отряд перестал бы замечать тех,
## на кого и без всякого Attack-Move бросился бы сам
## Есть ли у кого-то из отряда живая цель — отряд ещё в бою, «зачищено»
## объявлять рано. O(n) раз в такт на отряд (0.3 с), покадрового пути нет
func _any_engaged(alive: Array) -> bool:
	for u in alive:
		var un := u as Unit
		if un == null or un.state != Unit.State.ATTACKING:
			continue
		var t = un.attack_target
		if t != null and is_instance_valid(t) and not t.is_dead():
			return true
	return false

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

## Все отряды клика grp дошли до своих точек (выбитые и снятые не ждут)
func _group_arrived(grp: int) -> bool:
	for sid in _am.keys():
		var e: Dictionary = _am[sid]
		if int(e.get("grp", -1)) == grp and not bool(e.get("arrived", false)):
			return false
	return true
