extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## СТРОЙ ОТРЯДА: РАЗМЕТКА МЕСТ И СМЫКАНИЕ РЯДОВ
## ═══════════════════════════════════════════════════════════════════════════
## ЗАЧЕМ ОТДЕЛЬНЫЙ МОДУЛЬ. Раньше строй существовал только как разовый расчёт
## внутри SelectionManager: слоты считались, раздавались приказами и тут же
## забывались. Отряд «помнил» своё построение исключительно тем, что бойцы
## стояли по своим точкам, — а как только первую шеренгу выбивали, её места
## оставались пустыми навсегда. Отряд из тридцати человек после боя выглядел
## как рваная гребёнка с дырами спереди.
##
## Здесь разметка становится СВОЙСТВОМ ОТРЯДА: список мест, курс и режим шага
## лежат в записи отряда (GameManager.squads), переживают потери и позволяют
## сделать то, что и требуется по заданию, — «задняя шеренга переходит вперёд
## на место павших».
##
## ПОРЯДОК МЕСТ ВАЖЕН: slots[0] — крайний в ПЕРВОЙ шеренге, дальше вся первая
## шеренга, затем вторая и так далее (ровно в таком порядке их и строит
## SelectionManager._compute_line_slots). Поэтому «сомкнуть ряды» — это просто
## посадить выживших на первые N мест списка: дыры сами уезжают в хвост строя.
##
## Подключение: const _SqFormation := preload("res://scripts/units/SquadFormation.gd")

const _OptSF := preload("res://scripts/perf_config.gd")

## Не чаще раза в столько миллисекунд отряд перестраивается после потерь.
## В свалке бойцы гибнут пачками, и переиздавать приказ на каждую смерть —
## это и лишний расход кадра, и дёрганый строй, который всё время переступает
const RESHUFFLE_COOLDOWN_MS := 900

## Ниже этой доли потерь ряды не смыкаем: выбило одного из тридцати — строй
## этого даже не заметит, а весь отряд переступит без всякой нужды
const RESHUFFLE_MIN_LOSS := 0.08

## Квадрат допуска «уже в своей ячейке» — тот же ARRIVE_RADIUS, по которому
## боец отчитывается о прибытии: ближе него приказ идти некуда
const ARRIVE_NEAR_SQ := Unit.ARRIVE_RADIUS * Unit.ARRIVE_RADIUS
## Стоящий не дальше этого от своей ячейки закрепляется без приказа: порог
## ТОТ ЖЕ, по которому обход смыкания видит дрейф (GameManager.REFORM_DRIFT).
## Прежние 0.48 (допуск прибытия) были ниже порога дрейфа 0.70: обход не
## трогал бойца в 0.6 м от ячейки, а само смыкание слало ему приказ — и он,
## подвинутый разведением на те же 0.6, получал его снова и снова
const HOLD_NEAR_SQ := 0.70 * 0.70

## Сомкнуть ряды: рассадить выживших по ПЕРВЫМ местам разметки.
##
## members — живые бойцы отряда; slots — исходная разметка (по шеренгам);
## course — куда смотрит фронт; slow — маршевый шаг или быстрый.
##
## Назначение жадное и по близости: каждое место списка по порядку (то есть
## начиная с передовой) достаётся ближайшему ещё не занятому бойцу. Поэтому
## в опустевшую дыру первой шеренги шагает тот, кто стоял прямо за ней, а не
## случайный человек с другого фланга.
static func close_ranks(members: Array, slots: Array,
		course: Vector3, slow: bool) -> int:
	if members.is_empty() or slots.is_empty():
		return 0
	var free_men: Array = []
	var alive_n := 0
	for m in members:
		if m == null or not is_instance_valid(m) or m.is_dead():
			continue
		alive_n += 1
		# ── ПРИКАЗ ИГРОКА СМЫКАНИЕМ НЕ ПЕРЕБИВАЕТСЯ ────────────────────────
		# Смыкание шлёт `command_move` на МЕСТО В РАЗМЕТКЕ, а разметка описывает
		# ПРЕЖНИЙ строй — то есть точку рядом с бойцом. Отряд, которому игрок
		# только что велел уходить, по определению растянут (передние тронулись,
		# задние ещё в телах), и смыкание срабатывает именно тогда, когда мешает
		# больше всего: приказ на отход подменялся приказом «вернись на место».
		# Тот же довод и то же лечение, что у подзыва сплочённости
		# (GameManager._cohesion_guard)
		if m.player_order_active():
			continue
		# ── ДЕРУЩЕГОСЯ СМЫКАНИЕ НЕ ТРОГАЕТ (BigStand, этап 1) ──────────────
		# Отряд выходит из окна «нас били» (squad_in_combat) раньше, чем его
		# последние бойцы кончают драться: `_reform_check` по этому событию
		# слал `command_move` и тем, кто в ATTACKING с живой целью, — боец
		# бросал удар и шёл в строй (зонд qa_bigstand: 34/с у орды в бою).
		# Он достроится следующим обходом, когда действительно освободится
		if m.state == Unit.State.ATTACKING and m.attack_target != null \
				and is_instance_valid(m.attack_target):
			continue
		free_men.append(m)
	if free_men.is_empty():
		return 0
	# Цельный кирпичик: неполная последняя шеренга — по центру (см. centred_tail)
	if _OptSF.formation_centred_tail and alive_n < slots.size():
		slots = centred_tail(slots, alive_n, course)
	var moved := 0
	# ── ПОЗИЦИИ И ШИРИНА ШЕРЕНГИ — ОДИН РАЗ (этап 3, 28.09.2026) ────────────
	# Обе жадные раздачи ниже на каждую ячейку обходили ВСЕХ свободных с
	# чтением global_position (свойство), а _per_row (обход разметки) считался
	# на каждое назначение: отряд в 100 человек — 10⁴ чтений свойства и 10⁴
	# обходов разметки одним кадром (tail_reform худший 9.9 мс). Точки
	# снимаются один раз в PackedVector3Array, ширина шеренги — один раз;
	# выбывший помечается, а не удаляется из массива, чтобы номера не ехали.
	# Порядок разбора и правила ничьих — дословно прежние: результат тот же
	var per_row: int = maxi(_per_row(slots, course), 1)
	var nm: int = free_men.size()
	var pxs := PackedFloat32Array()
	var pzs := PackedFloat32Array()
	var idle := PackedByteArray()
	pxs.resize(nm); pzs.resize(nm); idle.resize(nm)
	for i in range(nm):
		var um = free_men[i]
		var p: Vector3 = (um as Node3D).global_position
		pxs[i] = p.x
		pzs[i] = p.z
		idle[i] = 1 if um.state == Unit.State.IDLE else 0
	var taken := PackedByteArray()    # 1 — боец уже получил место
	taken.resize(nm)
	var left: int = nm
	# ── КТО УЖЕ СТОИТ В ЯЧЕЙКЕ — ОСТАЁТСЯ В НЕЙ (ТЗ 17.09.2026) ─────────────
	# Жадный разбор «ближайший к месту» с одного прохода на строе, где все
	# стоят на своих местах с погрешностью разведения, сажал в ячейку СОСЕДА
	# (тот на пару сантиметров ближе), и дальше цепочкой ехал весь ряд: после
	# каждой стычки 3-5 лучников уходили на 1-3 м «переставиться»
	# (qa_archer_fix A4). Первый проход закрепляет стоящих в своей ячейке,
	# жадный разбор — только для остальных мест и остальных людей
	var slot_taken := PackedByteArray()   # 1 — ячейка занята стоящим на месте
	slot_taken.resize(slots.size())
	# ЗАКРЕПЛЯЮТСЯ ТОЛЬКО ПЕРВЫЕ alive_n ЯЧЕЕК (19.09.2026): места разметки
	# идут спереди назад, и выбитая первая шеренга обязана закрыться
	# задними (qa_spear E2 — «дыры уезжают в хвост»); стоящий в хвостовой
	# ячейке при потерях впереди переезжает вперёд, целый строй по-прежнему
	# не пересаживается (все живые и так стоят в первых alive_n ячейках)
	# Под раздачей по рядам (rank_match) закрепляется только стоящий у СВОЕЙ
	# ячейки (пост = эта ячейка): закрепление любого стоящего у любой ячейки
	# ломало порядок рядов (qa_tz1031 C1), а без закрепления один выбитый
	# боец сдвигал каскадом по бойцу в каждой шеренге (qa_reform_idle C2)
	for si in range(mini(slots.size(), alive_n)):
		var slot: Vector3 = slots[si]
		var near := -1
		var near_d := HOLD_NEAR_SQ
		for i in range(nm):
			if taken[i] == 1 or idle[i] == 0:
				continue
			if _OptSF.rank_match:
				var ou = free_men[i]
				if not ou._post_valid or Vector2(ou.post_pos.x - slot.x, ou.post_pos.z - slot.z).length_squared() > 0.01:
					continue
			var dx: float = pxs[i] - slot.x
			var dz: float = pzs[i] - slot.z
			var d: float = dx * dx + dz * dz
			if d <= near_d:
				near_d = d
				near = i
		if near < 0:
			continue
		var uk = free_men[near]
		taken[near] = 1
		left -= 1
		uk.formation_row = si / per_row
		uk.hold_post(slot, course)
		slot_taken[si] = 1
	# ── РАЗДАЧА ПО РЯДАМ (ТЗ 31.10.2026, ручка rank_match) ────────────────
	# Жадный разбор «место по порядку → ближайший» сажал передового бойца в
	# заднюю шеренгу, а заднего — вперёд: строй собирался крест-накрест,
	# бойцы шли назад сквозь своих (зонд qa_army_front). Теперь передние по
	# курсу берут передние места, в шеренге — по порядку поперёк курса
	var pairs: Array = []
	if _OptSF.rank_match:
		var free_si: Array = []
		for si0 in range(slots.size()):
			if free_si.size() >= left:
				break
			if slot_taken[si0] == 0:
				free_si.append(si0)
		var free_ui: Array = []
		for i0 in range(nm):
			if taken[i0] == 0:
				free_ui.append(i0)
		pairs = rank_pairs(pxs, pzs, free_ui, slots, free_si, course, per_row)
	else:
		for si in range(slots.size()):
			if pairs.size() >= left:
				break
			if slot_taken[si] == 1:
				continue
			var slot0: Vector3 = slots[si]
			var best := -1
			var best_d0 := INF
			for i in range(nm):
				if taken[i] == 1:
					continue
				var dx: float = pxs[i] - slot0.x
				var dz: float = pzs[i] - slot0.z
				var d: float = dx * dx + dz * dz
				if d < best_d0:
					best_d0 = d
					best = i
			if best < 0:
				break
			taken[best] = 1
			pairs.append([si, best])
	for pr0 in pairs:
		var si: int = int(pr0[0])
		var best: int = int(pr0[1])
		var slot: Vector3 = slots[si]
		var bdx: float = pxs[best] - slot.x
		var bdz: float = pzs[best] - slot.z
		var best_d: float = bdx * bdx + bdz * bdz
		var u = free_men[best]
		taken[best] = 1
		left -= 1
		# Ряд пересчитывается вместе с местом: перешедший вперёд боец обязан
		# опустить копьё, а ушедший назад — поднять (см. Spearman._spear_leveled)
		u.formation_row = si / per_row
		# ── КТО УЖЕ В СВОЕЙ ЯЧЕЙКЕ, ПРИКАЗА НЕ ПОЛУЧАЕТ (BigStand, этап 1) ──
		# `command_move` в точку под ногами — это пробуждение, грязная поза,
		# снятый якорь и ноль метров пути. Стоящему бойцу ближе допуска
		# прибытия хватает переехавшего поста (Unit.hold_post): по нему
		# `_sweep_reform` больше не видит дрейфа. Идущий (MOVING) сюда не
		# попадает — он идёт куда-то ещё, и его надо развернуть приказом
		if u.state == Unit.State.IDLE and best_d <= HOLD_NEAR_SQ:
			u.hold_post(slot, course)
			continue
		# ── РАЗРЕШЕНИЕ ЗАЛОЧЕННОМУ СТОЙКОЙ ────────────────────────────────
		# Фаланга стоит намертво (STANCES.defense.lock_position) и обычные
		# приказы на движение не исполняет вовсе. Смыкание рядов —
		# ЕДИНСТВЕННОЕ исключение, и оно обязательно: без него потери и проход
		# союзников сквозь строй оставляли бы в нём вечные дыры, а заказ на
		# смыкание стоит рядом с заказом на замок позиции
		u.allow_reform_move()
		u.command_move(slot, slow, course)
		moved += 1
	# Бойцы, которым места не хватило (пополнение из замка встало в хвост),
	# просто идут за строем — отдельного места для них в разметке нет
	if left > 0 and slots.size() > 0:
		# ── ЛИШНИЕ — ДОПОЛНИТЕЛЬНОЙ ШЕРЕНГОЙ, А НЕ В ОДНУ ТОЧКУ (ТЗ 29.09.2026) ──
		# Все, кому не хватило места, шли в одну точку за последним слотом и
		# сбивались кучей: разведение не даёт им встать, отряд «не собирается»
		var pr: int = maxi(_per_row(slots, course), 1)
		var side := Vector3(-course.z, 0.0, course.x)
		var lr0: int = ((slots.size() - 1) / pr) * pr
		var row_mid: Vector3 = ((slots[lr0] as Vector3) + (slots[slots.size() - 1] as Vector3)) * 0.5
		var k := 0
		for i in range(nm):
			if taken[i] == 1:
				continue
			var extra = free_men[i]
			var rk: int = k / pr
			var ck: int = k % pr
			var p: Vector3 = row_mid - course * (0.9 + 0.7 * float(rk)) + side * ((float(ck) - float(pr - 1) * 0.5) * 0.7)
			extra.allow_reform_move()
			extra.command_move(p, slow, course)
			k += 1
	return moved

## ── ЦЕЛЬНЫЙ КИРПИЧИК (ТЗ 27.10.2026, третье письмо, п. 6) ──────────────────
## «Отряд — комната без окон и дверей: правильный прямоугольник; при потерях
## — цельный кирпичик без огрызков, лишние позиции смещаются к хвосту или
## центру». Смыкание сажает выживших на ПЕРВЫЕ n мест разметки, и неполная
## последняя шеренга ложилась от ЛЕВОГО края — огрызком сбоку. Здесь первые
## n мест берутся как есть, а места неполной последней шеренги сдвигаются
## поперёк курса так, чтобы её центр совпал с центром шеренги разметки:
## пустоты уходят поровну на оба фланга хвоста. Ручка
## perf_config.formation_centred_tail
static func centred_tail(slots: Array, n: int, course: Vector3) -> Array:
	if n <= 0 or slots.is_empty():
		return []
	if n >= slots.size():
		return slots
	var out: Array = slots.slice(0, n)
	var pr: int = maxi(_per_row(slots, course), 1)
	var full: int = (n / pr) * pr
	var rem: int = n - full
	if rem <= 0:
		return out
	var side := Vector3(-course.z, 0.0, course.x)
	if side.length_squared() < 1e-6:
		return out
	side = side.normalized()
	var row_end: int = mini(full + pr, slots.size())
	var c_row := 0.0
	for i in range(full, row_end):
		c_row += (slots[i] as Vector3).dot(side)
	c_row /= float(row_end - full)
	var c_part := 0.0
	for i2 in range(full, n):
		c_part += (slots[i2] as Vector3).dot(side)
	c_part /= float(rem)
	var shift: Vector3 = side * (c_row - c_part)
	for i3 in range(full, n):
		out[i3] = (slots[i3] as Vector3) + shift
	return out

## Раздача мест по рядам: units — индексы бойцов (точки px/pz), slot_idx —
## индексы мест (по порядку разметки, шеренга = индекс / per_row). Самые
## передние по курсу бойцы — первой из шеренг списка, в шеренге пары по
## порядку поперёк курса. Ответ — [[индекс места, индекс бойца], ...]
static func rank_pairs(px: PackedFloat32Array, pz: PackedFloat32Array, units: Array,
		slots: Array, slot_idx: Array, course: Vector3, per_row: int) -> Array:
	var out: Array = []
	var n: int = mini(units.size(), slot_idx.size())
	if n <= 0:
		return out
	var c := Vector3(course.x, 0.0, course.z)
	if c.length_squared() < 1e-6:
		c = Vector3.FORWARD
	c = c.normalized()
	var side := Vector3(-c.z, 0.0, c.x)
	var us: Array = units.duplicate()
	us.sort_custom(func(a, b):
		return px[int(a)] * c.x + pz[int(a)] * c.z > px[int(b)] * c.x + pz[int(b)] * c.z)
	var pr: int = maxi(per_row, 1)
	var k := 0
	while k < n:
		var row: int = int(slot_idx[k]) / pr
		var ss: Array = []
		while k < n and int(slot_idx[k]) / pr == row:
			ss.append(int(slot_idx[k]))
			k += 1
		var uu: Array = us.slice(k - ss.size(), k)
		ss.sort_custom(func(a, b):
			return (slots[int(a)] as Vector3).dot(side) < (slots[int(b)] as Vector3).dot(side))
		uu.sort_custom(func(a, b):
			return px[int(a)] * side.x + pz[int(a)] * side.z < px[int(b)] * side.x + pz[int(b)] * side.z)
		for j in range(ss.size()):
			out.append([ss[j], uu[j]])
	return out

## Сколько бойцов в одной шеренге. Считается по самой разметке: подряд идущие
## места одной шеренги лежат ПОПЕРЁК курса, а первое место следующей шеренги
## уже смещено вдоль него назад
static func _per_row(slots: Array, course: Vector3) -> int:
	if slots.size() < 2 or course.length_squared() < 1e-6:
		return maxi(slots.size(), 1)
	var base: float = (slots[0] as Vector3).dot(course)
	for i in range(1, slots.size()):
		if absf((slots[i] as Vector3).dot(course) - base) > 0.25:
			return i
	return slots.size()
