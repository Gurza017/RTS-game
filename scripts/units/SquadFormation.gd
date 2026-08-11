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

## Не чаще раза в столько миллисекунд отряд перестраивается после потерь.
## В свалке бойцы гибнут пачками, и переиздавать приказ на каждую смерть —
## это и лишний расход кадра, и дёрганый строй, который всё время переступает
const RESHUFFLE_COOLDOWN_MS := 900

## Ниже этой доли потерь ряды не смыкаем: выбило одного из тридцати — строй
## этого даже не заметит, а весь отряд переступит без всякой нужды
const RESHUFFLE_MIN_LOSS := 0.08

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
	for m in members:
		if m != null and is_instance_valid(m) and not m.is_dead():
			free_men.append(m)
	if free_men.is_empty():
		return 0
	var moved := 0
	var n: int = mini(free_men.size(), slots.size())
	for si in range(n):
		var slot: Vector3 = slots[si]
		var best := -1
		var best_d := INF
		for i in range(free_men.size()):
			var p: Vector3 = (free_men[i] as Node3D).global_position
			var dx: float = p.x - slot.x
			var dz: float = p.z - slot.z
			var d: float = dx * dx + dz * dz
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			break
		var u = free_men[best]
		free_men.remove_at(best)
		# Ряд пересчитывается вместе с местом: перешедший вперёд боец обязан
		# опустить копьё, а ушедший назад — поднять (см. Spearman._spear_leveled)
		u.formation_row = si / maxi(_per_row(slots, course), 1)
		u.command_move(slot, slow, course)
		moved += 1
	# Бойцы, которым места не хватило (пополнение из замка встало в хвост),
	# просто идут за строем — отдельного места для них в разметке нет
	for extra in free_men:
		if slots.size() > 0:
			extra.command_move(slots[slots.size() - 1] - course * 1.2, slow, course)
	return moved

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
