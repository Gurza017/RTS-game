extends RefCounted
class_name MineCluster
## ═══════════════════════════════════════════════════════════════════════════
## РУДНИК КАК ЕДИНЫЙ ЛОГИЧЕСКИЙ ОБЪЕКТ
## ═══════════════════════════════════════════════════════════════════════════
##
## ЧТО БЫЛО. Куча золота или камня существовала только на экране: полтора
## десятка отдельных ResourceNode, у каждого свой запас, своё кольцо рабочих
## мест и своя жизнь. Отсюда весь букет жалоб:
##   • рабочие лезли ВНУТРЬ навала — кольца слотов размечены вокруг КАЖДОГО
##     куска, а куски стоят вплотную, значит половина мест приходилась на
##     середину кучи, между камнями;
##   • там они толкались и дёргались: слот занят, сосед выталкивает, приход не
##     засчитывается, приказ выдаётся заново;
##   • выработав свой камушек, рабочий переставал добывать и шёл выбирать
##     следующий — на ровном месте пауза и смена цели;
##   • баланс кучи задавался суммой по кускам, то есть менялся не одной цифрой,
##     а правкой шаблона раскладки.
##
## ЧТО СТАЛО. Куча — ОДИН объект с ОБЩИМ запасом. Куски руды остаются только
## картинкой и мишенью для клика; добыча, рабочие места и остаток живут здесь.
## Рабочие встают по ВНЕШНЕМУ периметру овала и внутрь не заходят вовсе, а
## спрайты кусков усыхают и по одному пропадают по мере выработки общего пула.
##
## ЁМКОСТЬ БЕРЁТСЯ ИЗ КОНФИГА (unit_stats_config.DEFAULT_CLUSTER_GOLD /
## _STONE) — одной цифрой на весь баланс, как и просили.
##
## Класс НЕ УЗЕЛ и намеренно им не является: ему нечего рисовать и незачем
## тикать. Он живёт ссылкой в реестре Main.res_clusters и у своих же кусков.
## ResourceNode он не подключает (preload'ом) — иначе замкнулся бы цикл
## ResourceNode → MineCluster → ResourceNode; методы кусков зовутся по имени.

## ── ГЕОМЕТРИЯ ───────────────────────────────────────────────────────────────
## Насколько кольцо стояния отстоит от нарисованной кромки овала. Рабочий
## встаёт вплотную к жиле, но СНАРУЖИ — это и есть «внутрь заходить нельзя»
const STAND_GAP := 0.55
## Шаг между соседями по периметру — примерно личное пространство рабочего
const SLOT_ARC := 1.0
const SLOT_MIN := 6
## Потолок на кольцо. Периметр большой кучи это два-три десятка метров, и без
## потолка бригаду можно было бы размазать по нему всю
const SLOT_MAX := 24
## Второе кольцо для переполнения: лишние встают за спинами первых, но каждый
## на СВОЕЙ точке. Двое в одну точку не встают никогда — ровно это и было
## причиной дёрганья у старых кусков
const SLOT_RINGS := 2
const RING_STEP := 0.9
## Дотягивается ли инструмент. Считается от кольца стояния, а не отдельной
## константой: сдвинули кольцо — порог поехал следом.
## Запас обязан покрывать И допуск прихода (Unit.ARRIVE_RADIUS), И второе
## кольцо — иначе рабочий во втором ряду встаёт и не начинает работать
const REACH_PAD := 1.5

## ── КОСМЕТИКА ВЫРАБОТКИ ─────────────────────────────────────────────────────
## До какого масштаба усыхают оставшиеся куски на пустой жиле
const FADE_MIN_SCALE := 0.45

var id: int = 0
var resource_type: int = 0
var center: Vector3 = Vector3.ZERO
## Полуоси по ЦЕНТРАМ кусков
var half: Vector2 = Vector2.ZERO
## Полуоси НАРИСОВАННОГО овала (центры + силуэт крайнего куска). Это же число
## рисует подсветка — обещание и приказ обязаны совпадать по геометрии
var outline: Vector2 = Vector2.ZERO
## Полуоси кольца, на котором стоят рабочие
var stand: Vector2 = Vector2.ZERO

var stock: float = 0.0
var max_stock: float = 0.0

## Все куски кучи
var members: Array = []
## ПОРЯДОК КОСМЕТИЧЕСКОГО ИСЧЕЗНОВЕНИЯ: [0] уходит первым. Последний в списке —
## якорь, он стоит до полной выработки (см. anchor)
var _fade_order: Array = []

## instance_id рабочего → сквозной индекс слота
var _slot_owner: Dictionary = {}

func setup(cid: int, res_type: int, mid: Vector3, half_axes: Vector2,
		rim: float, capacity: float, pieces: Array) -> void:
	id = cid
	resource_type = res_type
	center = mid
	half = half_axes
	outline = half_axes + Vector2(rim, rim)
	stand = outline + Vector2(STAND_GAP, STAND_GAP)
	max_stock = maxf(capacity, 1.0)
	stock = max_stock
	members = pieces.duplicate()
	_build_fade_order()
	_apply_depletion()

## Порядок исчезновения: сначала мелочь и то, что дальше от середины, — куча
## худеет с краёв и с самого мелкого, как настоящая осыпь. ЯКОРЬ (последний)
## выбирается противоположным правилом и потому всегда стоит в сердце навала
func _build_fade_order() -> void:
	var scored: Array = []
	for m in members:
		if m == null or not is_instance_valid(m):
			continue
		var sc: float = float(m.size_scale)
		var d: float = Vector2(m.global_position.x - center.x,
			m.global_position.z - center.z).length()
		# Меньше вес — раньше исчезает: мелкий и дальний уходит первым
		scored.append({"n": m, "w": sc * 4.0 - d})
	scored.sort_custom(func(a, b): return float(a["w"]) < float(b["w"]))
	_fade_order.clear()
	for s in scored:
		_fade_order.append(s["n"])

## Кусок, который стоит до самого конца. ИМЕННО ЕГО получает рабочий как цель
## добычи (см. ResourceNode.gather_anchor): цель обязана пережить всю выработку,
## иначе рабочий на каждом исчезнувшем камушке искал бы себе новую
func anchor():
	for i in range(_fade_order.size() - 1, -1, -1):
		var n = _fade_order[i]
		if n != null and is_instance_valid(n):
			return n
	return null

func is_empty() -> bool:
	return stock <= 0.0

# ─────────────────────────────────────────────────────────────────────────────
# РАБОЧИЕ МЕСТА ПО ПЕРИМЕТРУ
# ─────────────────────────────────────────────────────────────────────────────

## Приближение периметра эллипса по Рамануджану. Точная формула — эллиптический
## интеграл; здесь нужна лишь оценка «сколько человек влезет», и приближение
## ошибается меньше чем на промилле
static func _perimeter(a: float, b: float) -> float:
	var s: float = 3.0 * (a + b)
	var t: float = sqrt(maxf((3.0 * a + b) * (a + 3.0 * b), 0.0))
	return PI * (s - t)

func _ring_count(ax: Vector2) -> int:
	return clampi(int(_perimeter(ax.x, ax.y) / SLOT_ARC), SLOT_MIN, SLOT_MAX)

func slot_total() -> int:
	var n: int = 0
	var ax: Vector2 = stand
	for r in range(SLOT_RINGS):
		n += _ring_count(ax)
		ax += Vector2(RING_STEP, RING_STEP)
	return n

## Мировая точка слота по СКВОЗНОМУ индексу.
##
## Точки расставлены равномерно ПО УГЛУ, а не по длине дуги: на вытянутой куче
## это значит, что на её торцах соседи стоят чуть теснее, чем на боках. Разница
## в пределах эксцентриситета наших шаблонов (примерно 2:1) невелика, а
## равномерность по дуге требовала бы численного обращения интеграла на каждый
## слот — то есть заметно дороже ровно там, где выигрыш измеряется сантиметрами
func slot_position(idx: int) -> Vector3:
	var i: int = idx
	var ax: Vector2 = stand
	for r in range(SLOT_RINGS):
		var n: int = _ring_count(ax)
		if i < n:
			# Кольца провёрнуты друг относительно друга на полшага: второй ряд
			# встаёт в просветы первого, а не в затылок ему
			var ang: float = TAU * float(i) / float(n) + (PI / float(n)) * float(r)
			var x: float = center.x + cos(ang) * ax.x
			var z: float = center.z + sin(ang) * ax.y
			return Vector3(x, GameManager.get_terrain_height(x, z), z)
		i -= n
		ax += Vector2(RING_STEP, RING_STEP)
	# Разметка переполнена целиком — персональная точка за внешним кольцом
	var xo: float = center.x + cos(float(idx)) * ax.x
	var zo: float = center.z + sin(float(idx)) * ax.y
	return Vector3(xo, GameManager.get_terrain_height(xo, zo), zo)

## Занять свободное место, ближайшее к рабочему. Кольца набиваются СТРОГО
## ИЗНУТРИ НАРУЖУ: рабочий подходит к куче снаружи, и точка внешнего кольца ему
## всегда ближе внутренней — «ближайший свободный вообще» расставил бы бригаду
## широким хороводом в паре метров от руды (тот же разбор, что в
## ResourceNode.claim_slot)
func claim_slot(who: Node3D) -> Vector3:
	if who == null:
		return center
	var wid: int = who.get_instance_id()
	if _slot_owner.has(wid):
		return slot_position(int(_slot_owner[wid]))
	var taken: Dictionary = {}
	for k in _slot_owner.keys():
		if is_instance_valid(instance_from_id(int(k))):
			taken[int(_slot_owner[k])] = true
		else:
			_slot_owner.erase(k)
	var base: int = 0
	var ax: Vector2 = stand
	var pick: int = -1
	for r in range(SLOT_RINGS):
		var n: int = _ring_count(ax)
		var best: int = -1
		var best_d: float = INF
		for i in range(n):
			var idx: int = base + i
			if taken.has(idx):
				continue
			var d: float = who.global_position.distance_squared_to(slot_position(idx))
			if d < best_d:
				best_d = d
				best = idx
		if best >= 0:
			pick = best
			break
		base += n
		ax += Vector2(RING_STEP, RING_STEP)
	if pick < 0:
		pick = slot_total() + (wid % SLOT_MAX)
	_slot_owner[wid] = pick
	return slot_position(pick)

func release_slot(who: Node3D) -> void:
	if who != null:
		_slot_owner.erase(who.get_instance_id())

# ─────────────────────────────────────────────────────────────────────────────
# ГЕОМЕТРИЯ ЗОНЫ
# ─────────────────────────────────────────────────────────────────────────────

## Доля до границы эллипса с полуосями ax: <1 внутри, 1 на кромке, >1 снаружи.
## Считается по нормированному радиусу, а не по расстоянию: для «внутри или
## снаружи» этого достаточно, и корней извлекать не нужно
func _ellipse_k(p: Vector3, ax: Vector2) -> float:
	var dx: float = (p.x - center.x) / maxf(ax.x, 0.001)
	var dz: float = (p.z - center.z) / maxf(ax.y, 0.001)
	return sqrt(dx * dx + dz * dz)

## Дотягивается ли инструмент до жилы из этой точки. Мерится ОТ КУЧИ ЦЕЛИКОМ, а
## не от какого-то куска: куча и есть цель добычи
func in_reach(p: Vector3) -> bool:
	return _ellipse_k(p, stand + Vector2(REACH_PAD, REACH_PAD)) <= 1.0

## Залез ли рабочий В НАВАЛ — то есть внутрь НАРИСОВАННОГО овала.
##
## Мерится по outline, а не по кольцу стояния: рабочие места размечены ровно на
## stand, и «внутри stand» у точки слота выходит на грани сравнения — 1.0 против
## 1.0, где ответ решает последний бит мантиссы. Стенд qa_res2 F2 («приказ ведёт
## наружу») от этого проходил через раз в зависимости от розыгрыша карты.
## Навал же кончается на outline, до кольца стояния остаётся ещё STAND_GAP —
## запас, которого хватает и коду, и вопросу «зашёл ли он в кучу»
func is_inside(p: Vector3) -> bool:
	return _ellipse_k(p, outline) < 1.0

## Куда вытолкнуть точку, оказавшуюся внутри навала (Vector3.ZERO — всё в
## порядке). Приказы рабочим внутрь кучи не выдаются в принципе (цель — слот на
## периметре), поэтому это СТРАХОВКА от чужих сил: расталкивания соседями,
## обхода ствола, сдвига при появлении новой бригады.
##
## ── МЁРТВАЯ ЗОНА ОБЯЗАТЕЛЬНА, И ИМЕННО ЕЁ ОТСУТСТВИЕ ДАВАЛО «БЕГ НА МЕСТЕ» ──
## Рабочие места размечены РОВНО по кольцу stand, то есть при k = 1.000. Порог
## «выталкивать при k < 1.0» срабатывает от любого шума — доводки до слота
## (SLOT_SETTLE), высоты рельефа, толчка соседа: рабочего выпихивает наружу,
## доводка тянет обратно, и он бесконечно дёргается у кромки кучи, не начиная
## работу. Ровно это и было видно на скриншоте владельца.
##
## Зона в 8% полуоси заведомо шире любого такого шума и заведомо уже, чем
## настоящий заход в навал (кромка нарисованных кусков — на outline, а это на
## STAND_GAP ближе к центру)
const PUSH_DEADBAND := 0.92

func outward_push(p: Vector3) -> Vector3:
	var d := Vector3(p.x - center.x, 0.0, p.z - center.z)
	if _ellipse_k(p, stand) >= PUSH_DEADBAND:
		return Vector3.ZERO
	if d.length_squared() < 1e-6:
		# Ровно в середине направления нет — толкаем по короткой оси, там ближе
		d = Vector3(1.0, 0.0, 0.0) if stand.x <= stand.y else Vector3(0.0, 0.0, 1.0)
	return d.normalized()

# ─────────────────────────────────────────────────────────────────────────────
# ДОБЫЧА И КОСМЕТИКА ВЫРАБОТКИ
# ─────────────────────────────────────────────────────────────────────────────

func extract(amount: float) -> float:
	var taken: float = minf(maxf(amount, 0.0), stock)
	if taken <= 0.0:
		return 0.0
	stock -= taken
	_apply_depletion()
	return taken

## Спрайты усыхают И по одному пропадают в зависимости от доли оставшегося
## общего ресурса. Два эффекта вместе, а не по отдельности: одно только
## исчезновение делает выработку скачкообразной («был камень — нет камня»), а
## одно только усыхание к концу оставляет полный навал крошек
func _apply_depletion() -> void:
	if stock <= 0.0:
		for m in members:
			if m != null and is_instance_valid(m):
				m.queue_free()
		members.clear()
		_fade_order.clear()
		_slot_owner.clear()
		return
	var frac: float = clampf(stock / max_stock, 0.0, 1.0)
	var n: int = _fade_order.size()
	if n == 0:
		return
	# Сколько кусков ещё стоит. Не меньше одного: пока в жиле хоть что-то есть,
	# на карте обязано быть видно, ЧТО именно тут добывают
	var alive: int = maxi(1, int(ceil(frac * float(n))))
	var sc: float = lerpf(FADE_MIN_SCALE, 1.0, frac)
	for i in range(n):
		var m = _fade_order[i]
		if m == null or not is_instance_valid(m):
			continue
		m.set_cluster_visual(sc, i < n - alive)
		# Остаток КУСКА — это остаток КУЧИ. Так все существующие проверки вида
		# `rn.remaining <= 0.0` (поиск следующей цели, отбор кликом, авто-цикл)
		# продолжают отвечать верно, ничего не зная про кластер
		m.remaining = stock
