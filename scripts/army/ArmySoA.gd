extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ЯДРО АРМИИ В ВИДЕ МАССИВОВ (SoA) — Фаза 1
## ═══════════════════════════════════════════════════════════════════════════
## Данные бойца, которые нужны ПАКЕТНЫМ обходам, лежат не в объектах, а в
## плоских Packed-массивах: одна строка на бойца, столбец на величину.
## Боец знает только НОМЕР СВОЕЙ СТРОКИ (Unit._soa).
##
## ── ПОЧЕМУ Unit НЕ СТАЛ НАБОРОМ СВОЙСТВ НАД ЭТИМИ МАССИВАМИ ─────────────────
## Напрашивалось сделать `Unit.current_health` свойством с get/set, читающим
## строку SoA, — тогда хранилище было бы одно. Замерено (qa_soa_floor, E1/E2,
## 15000 сущностей, два чтения на объект):
##     обычные поля объекта        2428 мкс  (0.16 мкс)
##     свойства-фасад над SoA      6304 мкс  (0.42 мкс)
## То есть каждое обращение в горячем цикле подорожало бы в 2.6 раза. Пока
## узлы бойцов живы (до Фазы 4) и логика ходит ПО ОБЪЕКТАМ, такой фасад — это
## гарантированный проигрыш, а не подготовка к выигрышу.
##
## Поэтому правило простое и проверяемое:
##   • СВОИ поля Unit читает у себя — они и есть его публичный интерфейс,
##     который снаружи (SelectionManager, HUD, Castle, EnemyAI) не изменился
##     ни на строку;
##   • строка SoA пишется СКВОЗНЬ в тех же самых местах, где Unit и так меняет
##     эти величины, — лишних проходов по армии не появляется;
##   • ЧИТАЮТ строку только ПАКЕТНЫЕ обходы, которым иначе пришлось бы трогать
##     тысячи объектов подряд (коридоры отрядов, сканы соседей в сетке).
## Выигрыш даёт именно замена «обход объектов» на «обход массива», а не смена
## места хранения сама по себе.
##
## В Фазе 4, когда узел бойца исчезнет, направление станет обратным: строка
## станет единственным хранилищем, а объект-фасад будет создаваться по
## требованию для холодных путей (выделение, панель, гарнизон), где 0.42 мкс
## не значат ничего.
##
## ── ПОЧЕМУ БЕЗ class_name ───────────────────────────────────────────────────
## Ровно как unit_grid / far_units / veg: модуль подключается через load() и
## живёт полем GameManager. Новый class_name требует записи в кэш глобальных
## классов, а его рассинхронизация ломает компиляцию всего проекта.

## Насколько прирастают массивы, когда строки кончились. Отряд — это до 20-50
## бойцов, найм идёт пачками, поэтому шаг крупный: перевыделение массива
## копирует его целиком
const GROW_STEP := 1024

# ── ЧИСЛА С ПЛАВАЮЩЕЙ ТОЧКОЙ ────────────────────────────────────────────────
## Мировая точка бойца. Y хранится тоже: рельеф не плоский, и потребителям
## (звёзды отрядов, центры масс) нужна честная высота
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var pz := PackedFloat32Array()
## Скорость по земле (XZ). Вертикальной у бойцов нет
var vx := PackedFloat32Array()
var vz := PackedFloat32Array()
## Здоровье
var hp     := PackedFloat32Array()
var hp_max := PackedFloat32Array()
## Откаты и таймеры, которыми в Фазе 3 будет заниматься пакетный бой
var atk_cd  := PackedFloat32Array()   # до следующего удара, сек
var aggro_t := PackedFloat32Array()   # до следующего опроса агро, сек
## Боевые характеристики (с учётом улучшений — пишет сам боец)
var atk_dmg   := PackedFloat32Array()
var atk_range := PackedFloat32Array()
var speed     := PackedFloat32Array()

# ── ЦЕЛЫЕ ───────────────────────────────────────────────────────────────────
## Отсчёт до следующего разбора наложения. Живёт здесь, а не на бойце, потому
## что разбор идёт ПАКЕТОМ по всей армии (см. batch_separation)
var sep_t := PackedFloat32Array()

## ── МЕСТО БОЙЦА В МАТРИЦЕ ОТРЯДА (Этап 1) ──────────────────────────────────
## Смещение от якоря отряда в ЕГО СОБСТВЕННОЙ системе координат: sl_x — вбок
## по фронту, sl_z — вглубь строя. Мировая точка получается поворотом этой пары
## на курс отряда и сложением с якорем (см. advance_matrix).
##
## Зачем столбцами, а не полем на бойце: матричный шаг — это цикл по строкам
## отряда, и заглядывать в объект за двумя числами означало бы вернуть ровно ту
## цену, ради устранения которой всё и делается
var sl_x := PackedFloat32Array()
var sl_z := PackedFloat32Array()

var st    := PackedInt32Array()   # Unit.State
var fac   := PackedInt32Array()   # Constants.FACTION_*
var sq    := PackedInt32Array()   # номер отряда, 0 — без отряда
var flags := PackedInt32Array()   # см. F_* ниже

# ── БИТЫ ПРИЗНАКОВ ──────────────────────────────────────────────────────────
## КООРДИНАТА В СТРОКЕ УЖЕ НАСТОЯЩАЯ. До первого тика боец числится в реестре,
## но его позицию узлу ещё не задали (её ставят ПОСЛЕ add_child — тот же
## порядок, из-за которого отложены регистрация ствола и посадка дерева).
## Пакетный обход обязан такую строку пропустить, иначе свежий отряд втянет
## в габариты своего отряда точку (0,0,0) и раздует его коридор на пол-карты
const F_POS_VALID  := 1 << 0
const F_RETREATING := 1 << 1
const F_SPRINTING  := 1 << 2
const F_SETTLED    := 1 << 3
const F_DISENGAGE  := 1 << 4
const F_LOCKED     := 1 << 5
const F_GARRISONED := 1 << 6
const F_CLEAR_TRUNK := 1 << 7
const F_CLEAR_ENEMY := 1 << 8
const F_SELECTED   := 1 << 9

## Строка → сам боец. Нужен ХОЛОДНЫМ путям, которым нужен объект: выбор целей
## возвращает узел, клик мышью возвращает узел. Обычный Array, потому что
## Packed-массивов из объектов не бывает; в горячих циклах он не читается
var unit_of: Array = []

var _capacity: int = 0
var _free: PackedInt32Array = PackedInt32Array()
var _used: int = 0

func capacity() -> int:
	return _capacity

func used() -> int:
	return _used

func _grow() -> void:
	var new_cap: int = _capacity + GROW_STEP
	px.resize(new_cap); py.resize(new_cap); pz.resize(new_cap)
	vx.resize(new_cap); vz.resize(new_cap)
	hp.resize(new_cap); hp_max.resize(new_cap)
	atk_cd.resize(new_cap); aggro_t.resize(new_cap)
	atk_dmg.resize(new_cap); atk_range.resize(new_cap); speed.resize(new_cap)
	sep_t.resize(new_cap)
	sl_x.resize(new_cap); sl_z.resize(new_cap)
	st.resize(new_cap); fac.resize(new_cap); sq.resize(new_cap)
	flags.resize(new_cap)
	unit_of.resize(new_cap)
	_next.resize(new_cap)
	# Свободные строки кладём в обратном порядке: pop_back снимет их по
	# возрастанию, и подряд заспавненный отряд займёт подряд идущие строки —
	# пакетному обходу это ложится в кэш процессора
	var i: int = new_cap - 1
	while i >= _capacity:
		_free.append(i)
		i -= 1
	_capacity = new_cap

## Занять строку. Возвращает её номер; боец хранит его в Unit._soa
func alloc_for(u) -> int:
	var i: int = alloc()
	unit_of[i] = u
	return i

func alloc() -> int:
	if _free.is_empty():
		_grow()
	var i: int = _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	_used += 1
	# Строка могла остаться от прошлого жильца — обнуляем, чтобы чужие числа
	# не «просочились» в свежего бойца
	px[i] = 0.0; py[i] = 0.0; pz[i] = 0.0
	vx[i] = 0.0; vz[i] = 0.0
	hp[i] = 0.0; hp_max[i] = 0.0
	atk_cd[i] = 0.0; aggro_t[i] = 0.0
	atk_dmg[i] = 0.0; atk_range[i] = 0.0; speed[i] = 0.0
	# Фаза разбора наложения разводится по номеру строки: иначе весь отряд,
	# вышедший из барака одним заказом, разбирается в один и тот же кадр
	sep_t[i] = float(i & 7) * 0.008
	st[i] = 0; fac[i] = -1; sq[i] = 0; flags[i] = 0
	return i

## Вернуть строку в оборот. Идемпотентно по отношению к -1
func release(i: int) -> void:
	if i < 0 or i >= _capacity:
		return
	# Признаки гасим сразу: строка не должна отвечать «координата настоящая»,
	# пока её никто не занял
	flags[i] = 0
	st[i] = 0
	fac[i] = -1
	sq[i] = 0
	unit_of[i] = null
	_free.append(i)
	_used -= 1

# ─────────────────────────────────────────────────────────────────────────────
# ЗАПИСЬ. Всё — маленькие методы: их зовёт сам боец из тех мест, где он и так
# менял эту величину, то есть по нескольку раз за кадр на ИДУЩЕГО и ни разу на
# стоящего. Для пакетного ЧТЕНИЯ методы не нужны — массивы открыты, и обход
# идёт по ним напрямую, без единого вызова
# ─────────────────────────────────────────────────────────────────────────────

func set_pos(i: int, x: float, y: float, z: float) -> void:
	px[i] = x; py[i] = y; pz[i] = z
	flags[i] |= F_POS_VALID

func set_vel(i: int, x: float, z: float) -> void:
	vx[i] = x; vz[i] = z

func set_hp(i: int, cur: float, mx: float) -> void:
	hp[i] = cur; hp_max[i] = mx

func set_state(i: int, s: int) -> void:
	st[i] = s

func set_faction(i: int, f: int) -> void:
	fac[i] = f

func set_squad(i: int, s: int) -> void:
	sq[i] = s

func set_combat(i: int, dmg: float, rng: float, spd: float) -> void:
	atk_dmg[i] = dmg; atk_range[i] = rng; speed[i] = spd

## ЕДИНСТВЕННАЯ ЗАПИСЬ БОЙЦА ЗА ТИК — ОДНИМ ВЫЗОВОМ.
##
## Почему не набор мелких сеттеров: вызов метода ЧУЖОГО объекта — самая дорогая
## операция этого проекта (см. шапку «Performance rules» в CLAUDE.md). Пять
## сеттеров на бойца в кадр — это на пяти тысячах опрашиваемых бойцов двадцать
## пять тысяч вызовов, то есть больше, чем всё, что они экономят.
##
## Писать массивы «снаружи» тоже нельзя: Packed-массивы в GDScript копируются
## при записи через чужую ссылку, и `a.px[i] = x` из Unit скопировал бы весь
## массив (тот же капкан, что описан у FarUnitRenderer.Bucket). Отсюда правило:
## ОДИН вызов, а все записи — здесь, внутри владельца.
##
## `fl` — уже собранное слово признаков (боец складывает его у себя чистой
## арифметикой). Признак «координата настоящая» добавляется тут же
## ЗАПИСЬ ПОЗЫ БОЙЦА ЗА ТИК — точка, скорость, состояние. Один вызов наружу
## взамен прежнего unit_grid.update(self), который собирал ключ Vector2i и
## работал с двумя словарями. Признак «координата настоящая» ставится здесь же:
## до первого тика строка в сетку не попадает
func write_pose(i: int, p: Vector3, v: Vector3, state: int) -> void:
	if i < 0:
		return
	px[i] = p.x; py[i] = p.y; pz[i] = p.z
	vx[i] = v.x; vz[i] = v.z
	st[i] = state
	flags[i] |= F_POS_VALID

func sync(i: int, p: Vector3, v: Vector3, state: int, fl: int) -> void:
	px[i] = p.x; py[i] = p.y; pz[i] = p.z
	vx[i] = v.x; vz[i] = v.z
	st[i] = state
	flags[i] = fl | F_POS_VALID

## ═══════════════════════════════════════════════════════════════════════════
## СНЯТЬ ТОЧКИ ОТРЯДА В СТРОКИ И СРАЗУ ПОСЧИТАТЬ ЕГО ГАБАРИТЫ
## ═══════════════════════════════════════════════════════════════════════════
## Единственное место, где координаты попадают из узлов в массивы, — и оно
## НЕ покадровое: зовётся из пересчёта коридоров, то есть раз в
## CORRIDOR_TTL_MS на отряд. Обход бойцов там был и до ядра армии, так что
## новых проходов по армии не появилось.
##
## ПОЧЕМУ НЕ «КАЖДЫЙ БОЕЦ ПИШЕТ СЕБЯ САМ». Пробовалось дважды (на такте сетки
## и по своему порогу в метр) и оба раза замер отверг: ветка grid_update
## 5.8% → 8.4%, марш на 15000 с 59.9 до 62.3 мс. Дорога не запись, а сам факт
## покадровой проверки на бойца — на пятнадцати тысячах это +2.2 мс за шесть
## чтений полей. В этот цикл нельзя добавить ничего.
##
## ПОЧЕМУ ВСЁ СЧИТАЕТСЯ ЗДЕСЬ, А НЕ У ВЫЗЫВАЮЩЕГО. Записи в Packed-массивы
## обязаны идти внутри владельца (снаружи это копирование всего массива —
## см. FarUnitRenderer.Bucket), а константы чужих скриптов (Unit.State.DEAD и
## прочие) в цикле по бойцам — это поиск по скрипту на каждого, поэтому они
## сняты в локальные переменные ДО цикла.
##
## `members` — состав отряда, `out_live` заполняется живыми бойцами (их потом
## получают ответы коридора). Возвращает [n, cx, cz, radius, watch, faction]
func harvest_squad(members: Array, out_live: Array, dead: int,
		aggro_r: float, intercept: float) -> Array:
	var fc := fac
	var n := 0
	var cx := 0.0
	var cz := 0.0
	var fac := 0
	var watch := 0.0
	# Точки складываем в переиспользуемый буфер: радиус считается вторым
	# проходом уже по числам, без единого обращения к объектам
	var need: int = members.size() * 2
	if _hx.size() < need:
		_hx.resize(need)
	for m in members:
		var u := m as Unit
		if u == null or not is_instance_valid(u):
			continue
		var i: int = u._soa
		# ── ЧИТАЕМ СТРОКУ, А НЕ УЗЕЛ (Фаза 2) ──────────────────────────────
		# До плоской сетки строки обновлялись только здесь, поэтому здесь же и
		# снимались точки с узлов. Теперь позу пишет сам тик бойца каждый кадр
		# (Unit.tick_physics → write_pose), значит столбцы уже свежие, и
		# global_position тут не читается вовсе — а это было свойство с
		# пересборкой мировой матрицы на каждого бойца каждого отряда.
		# Отставание — один кадр (сетка и коридоры считаются до обхода бойцов),
		# при запасе коридора CORRIDOR_MARGIN в восемь метров
		if i < 0 or (flags[i] & F_POS_VALID) == 0:
			continue
		if st[i] == dead:
			continue
		var x: float = px[i]
		var z: float = pz[i]
		cx += x
		cz += z
		_hx[n * 2]     = x
		_hx[n * 2 + 1] = z
		out_live.append(u)
		fac = fc[i]
		var w: float = maxf(aggro_r, atk_range[i]) + intercept
		if w > watch:
			watch = w
		n += 1
	if n == 0:
		return [0, 0.0, 0.0, 0.0, 0.0, 0]
	var inv: float = 1.0 / float(n)
	cx *= inv
	cz *= inv
	var r2 := 0.0
	for k in range(n):
		var dx: float = _hx[k * 2] - cx
		var dz: float = _hx[k * 2 + 1] - cz
		var d2: float = dx * dx + dz * dz
		if d2 > r2:
			r2 = d2
	return [n, cx, cz, sqrt(r2), watch, fac]

## Рабочий буфер сбора. Живёт полем, а не создаётся на каждый отряд: иначе это
## аллокация и её сборка на каждый пересчёт коридора
var _hx := PackedFloat32Array()

func set_flag(i: int, bit: int, on: bool) -> void:
	if on:
		flags[i] |= bit
	else:
		flags[i] &= ~bit

func has_flag(i: int, bit: int) -> bool:
	return (flags[i] & bit) != 0

## Координата строки годна для пакетного обхода
func pos_ready(i: int) -> bool:
	return (flags[i] & F_POS_VALID) != 0

# ═══════════════════════════════════════════════════════════════════════════
# ПЛОСКАЯ СЕТКА СОСЕДЕЙ (Фаза 2)
# ═══════════════════════════════════════════════════════════════════════════
# Было: Dictionary<Vector2i, Array[Node3D]>. На каждый скан — сборка ключа
# Vector2i, поиск по словарю и обход Array ОБЪЕКТОВ, у каждого из которых
# читалось свойство global_position (то есть проверка и, при нужде, пересборка
# мировой матрицы). Ветка sep_overlap стоила 5.4 мкс на вызов и 13% всего тика.
#
# Стало: ячейка — это число, а не Vector2i; содержимое ячейки — СВЯЗНЫЙ СПИСОК
# номеров строк (head[cell] → next[row] → …), а координаты берутся из тех же
# массивов, в которых их и держит ядро армии. Ни одной аллокации за кадр, ни
# одного обращения к объекту внутри скана.
#
# ── ПОЧЕМУ СВЯЗНЫЙ СПИСОК, А НЕ ПРЕФИКСНЫЕ СУММЫ ───────────────────────────
# Классическая раскладка «counting sort» (counts → prefix sum → items) требует
# ПРОХОДА ПО ВСЕМ ЯЧЕЙКАМ ради префиксной суммы. Ячеек десятки тысяч, а цикл
# по массиву в GDScript стоит ~0.05 мкс за шаг: на 260 тыс. ячеек это 13 мс в
# кадре — дороже всего, что сетка экономит. Связный список обходится ДВУМЯ
# записями на бойца и ни одним проходом по ячейкам, а очистка head — это
# fill(-1), то есть memset внутри движка, а не цикл интерпретатора.
#
# ── ПОЧЕМУ ГРАНИЦЫ СЧИТАЮТСЯ, А НЕ БЕРУТСЯ ИЗ КАРТЫ ────────────────────────
# Стенды расставляют бойцов на площадках в 300-500 м от центра карты (см.
# qa_settle/qa_formation), то есть далеко за её пределами. Сетка, растянутая по
# map_lim, потеряла бы их или свалила в одну краевую ячейку — и «соседями»
# оказался бы весь стенд разом. Поэтому габариты снимаются с самих строк, а
# размер ячейки растёт только если ячеек иначе выходит больше потолка.
const CELL_BASE := 1.0
## Потолок числа ячеек. 512×512 при метровой ячейке накрывает карту целиком
## (260×146 м) с огромным запасом; больше — только если бойцов растащило по
## области в полкилометра, и тогда дешевле огрубить ячейку, чем держать
## мегабайты пустых голов списка
const MAX_CELLS := 1 << 18

# ── ГРУБЫЙ СЛОЙ ПРИСУТСТВИЯ ФРАКЦИЙ ────────────────────────────────────────
# ЕГО СНОСИЛИ И ПРИШЛОСЬ ВЕРНУТЬ — замер объяснил почему. Метровая ячейка
# хороша для КОРОТКИХ вопросов (разведение — 0.29 м, блокировка строем —
# 0.55 м): там обходится две-три ячейки. Но вопрос «есть ли поблизости хоть
# один чужой» задаётся на РАДИУСЕ ВНИМАНИЯ ОТРЯДА, а это 22 м — то есть почти
# две тысячи метровых ячеек, и каждую надо пройти списком. На карте, где
# врагов нет вовсе, это чистая переплата: ветка squad_corridor выросла с 6.0%
# до 11.9% тика, mb_enemyblock — с 0.38 до 1.24 мкс на вызов.
#
# Поэтому рядом с метровой сеткой живёт РЕДКАЯ: клетки по COARSE_CELL метров,
# и на каждую известно, сколько бойцов КАЖДОЙ стороны в ней стоит. Пока в
# округе нет ни одного чужого, подробный скан не запускается вовсе. Фракции
# ровно две, поэтому счётчик — пара чисел на клетку.
const COARSE_CELL := 16.0

var _coarse := PackedInt32Array()   # (клетка * 2 + фракция) → сколько там бойцов
var _cw: int = 0
var _chh: int = 0
var _cinv: float = 1.0 / COARSE_CELL

var _head := PackedInt32Array()   # ячейка → первая строка в ней (-1 — пусто)
var _next := PackedInt32Array()   # строка → следующая строка в той же ячейке
var _gw: int = 0                  # ячеек по X
var _gh: int = 0                  # ячеек по Z
var _gx0: float = 0.0             # мировая точка ячейки (0,0)
var _gz0: float = 0.0
var _gcell: float = CELL_BASE     # текущий размер ячейки
var _ginv: float = 1.0 / CELL_BASE
var _grid_n: int = 0              # сколько строк попало в сетку

func grid_cells() -> int:
	return _gw * _gh

func grid_units() -> int:
	return _grid_n

func grid_cell_size() -> float:
	return _gcell

## ПЕРЕСТРОИТЬ СЕТКУ ЦЕЛИКОМ. Зовётся РАЗ В КАДР из GameManager._physics_process
## до обхода бойцов. Дешевле поштучных обновлений: прежний unit_grid.update()
## был вызовом наружу со сборкой ключа и двумя словарями НА КАЖДОГО сдвинувшегося
## бойца, а здесь на бойца приходятся две записи в массив.
## ГАБАРИТЫ ПЕРЕСЧИТЫВАЮТСЯ НЕ КАЖДЫЙ КАДР. Проход по всем строкам ради
## min/max стоит примерно столько же, сколько сама раскладка, а нужен он редко:
## бойцы зажаты границами карты (GameManager.map_lim_*), и однажды взятые
## границы им хватает навсегда. Поэтому сначала пробуем разложить по прежним
## границам, и только если кто-то оказался вне сетки — считаем заново и кладём
## второй раз. В установившемся режиме это ОДИН проход вместо двух
func rebuild_grid() -> void:
	if _gw == 0:
		_recompute_bounds()
		if _gw == 0:
			return
	if _fill_grid():
		return
	_recompute_bounds()
	if _gw == 0:
		return
	_fill_grid()

func _recompute_bounds() -> void:
	# ── ГАБАРИТЫ ЖИВЫХ СТРОК ────────────────────────────────────────────────
	var minx := INF
	var minz := INF
	var maxx := -INF
	var maxz := -INF
	var cnt := 0
	for i in range(_capacity):
		if (flags[i] & F_POS_VALID) == 0:
			continue
		var x: float = px[i]
		var z: float = pz[i]
		if x < minx: minx = x
		if x > maxx: maxx = x
		if z < minz: minz = z
		if z > maxz: maxz = z
		cnt += 1
	_grid_n = cnt
	if cnt == 0:
		_gw = 0
		_gh = 0
		return
	# Кайма в одну ячейку с каждой стороны: скан просит соседние ячейки и не
	# должен выходить за массив на крайнем бойце
	var cell := CELL_BASE
	var w := 0
	var h := 0
	while true:
		var inv: float = 1.0 / cell
		w = int((maxx - minx) * inv) + 3
		h = int((maxz - minz) * inv) + 3
		if w * h <= MAX_CELLS or cell > 64.0:
			break
		cell *= 2.0
	_gcell = cell
	_ginv = 1.0 / cell
	_gx0 = minx - cell
	_gz0 = minz - cell
	_gw = w
	_gh = h
	var total: int = w * h
	if _head.size() < total:
		_head.resize(total)
	# Редкая сетка кроет ту же область; клеток в ней в 256 раз меньше
	_cw = int(float(w) * cell * _cinv) + 2
	_chh = int(float(h) * cell * _cinv) + 2
	var ctotal: int = _cw * _chh * 2
	if _coarse.size() < ctotal:
		_coarse.resize(ctotal)

## РАЗЛОЖИТЬ СТРОКИ ПО ЯЧЕЙКАМ ОБЕИХ СЕТОК. Возвращает false, если кто-то
## оказался вне текущих границ — тогда вызывающий пересчитает габариты и
## позовёт ещё раз. Такое бывает на первом кадре и при спавне за пределами
## прежней области; в установившемся режиме проход ровно один
func _fill_grid() -> bool:
	if _gw == 0:
		return false
	# fill — это memset внутри движка, а не цикл интерпретатора (см. шапку)
	_head.fill(-1)
	_coarse.fill(0)
	var gx0 := _gx0
	var gz0 := _gz0
	var inv2 := _ginv
	var cinv := _cinv
	var cw := _cw
	var w := _gw
	var h := _gh
	var n := 0
	for i in range(_capacity):
		if (flags[i] & F_POS_VALID) == 0:
			continue
		var x: float = px[i]
		var z: float = pz[i]
		var cx: int = int((x - gx0) * inv2)
		var cz: int = int((z - gz0) * inv2)
		if cx < 0 or cz < 0 or cx >= w or cz >= h:
			# Вышли за сетку — раскладка недействительна целиком: соседние
			# ячейки у оставшихся тоже могут оказаться не теми
			return false
		var c: int = cz * w + cx
		_next[i] = _head[c]
		_head[c] = i
		var f: int = fac[i]
		if f == 0 or f == 1:
			var qx: int = int((x - gx0) * cinv)
			var qz: int = int((z - gz0) * cinv)
			_coarse[(qz * cw + qx) * 2 + f] += 1
		n += 1
	_grid_n = n
	return true

## Номер ячейки по мировой точке; -1 — за пределами сетки
func _cell_at(x: float, z: float) -> int:
	var cx: int = int((x - _gx0) * _ginv)
	var cz: int = int((z - _gz0) * _ginv)
	if cx < 0 or cz < 0 or cx >= _gw or cz >= _gh:
		return -1
	return cz * _gw + cx

## Границы блока ячеек, накрывающего круг (x, z, r). [cx0, cz0, cx1, cz1];
## пусто, если круг целиком вне сетки
func _cell_box(x: float, z: float, r: float) -> Array:
	if _gw == 0:
		return []
	var cx0: int = int((x - r - _gx0) * _ginv)
	var cz0: int = int((z - r - _gz0) * _ginv)
	var cx1: int = int((x + r - _gx0) * _ginv)
	var cz1: int = int((z + r - _gz0) * _ginv)
	if cx1 < 0 or cz1 < 0 or cx0 >= _gw or cz0 >= _gh:
		return []
	if cx0 < 0: cx0 = 0
	if cz0 < 0: cz0 = 0
	if cx1 >= _gw: cx1 = _gw - 1
	if cz1 >= _gh: cz1 = _gh - 1
	return [cx0, cz0, cx1, cz1]

# ═══════════════════════════════════════════════════════════════════════════
# СКАНЫ СОСЕДЕЙ
# ═══════════════════════════════════════════════════════════════════════════
# Ответы обязаны совпадать с прежним SpatialGrid до знака — на них держатся
# фаланга, блокировка чужим строем и разбор наложения. Отличие ровно одно и
# оно внутреннее: кандидаты берутся из связного списка ячейки и отсеиваются по
# СТОЛБЦАМ (fac/st/px/pz), а не по свойствам объекта.
#
# ОДНО СЛЕДСТВИЕ, О КОТОРОМ НАДО ЗНАТЬ: сетка перестраивается РАЗ В КАДР, до
# обхода бойцов. Значит внутри кадра все видят положение «на начало кадра», а
# не «как сосед успел сдвинуться минуту назад в этом же цикле». Прежний
# порядок был последовательным (кто раньше в массиве — тот двигался первым и
# следующие видели его новую точку). Одновременность здесь ЛУЧШЕ: разбор
# наложения перестаёт зависеть от порядка в реестре. Отставание — один кадр,
# то есть 6.7 см на скорости 4 м/с при пороге разведения 0.29 м.

## Мёртвых и вышедших из игры в скан не берём. Значение State.DEAD передаётся
## снаружи — константа чужого скрипта, прочитанная в цикле, стоит дороже самого
## сравнения (эта ошибка в проекте уже оплачена дважды)
var dead_state: int = 5

## СКОЛЬКО СВОИХ РЯДОМ, но не больше limit
func allies_count_near(row: int, at_x: float, at_z: float, radius: float,
		limit: int) -> int:
	var box := _cell_box(at_x, at_z, radius)
	if box.is_empty():
		return 0
	var myf: int = fac[row]
	var r_sq: float = radius * radius
	var found := 0
	for cz in range(box[1], box[3] + 1):
		var base: int = cz * _gw
		for cx in range(box[0], box[2] + 1):
			var j: int = _head[base + cx]
			while j != -1:
				if j != row and fac[j] == myf and st[j] != dead_state:
					var dx: float = at_x - px[j]
					var dz: float = at_z - pz[j]
					if dx * dx + dz * dz < r_sq:
						found += 1
						if found >= limit:
							return found
				j = _next[j]
	return found

## ЛИЧНЫЙ ОБЪЁМ: куда отойти от слипшихся союзников (см. прежний
## SpatialGrid.ally_overlap — правило и оба его обоснования не изменились)
func ally_overlap(row: int, at_x: float, at_z: float, min_dist: float,
		max_push: float) -> Vector3:
	var box := _cell_box(at_x, at_z, min_dist)
	if box.is_empty():
		return Vector3.ZERO
	var myf: int = fac[row]
	var d_sq: float = min_dist * min_dist
	var pxa := 0.0
	var pza := 0.0
	for cz in range(box[1], box[3] + 1):
		var base: int = cz * _gw
		for cx in range(box[0], box[2] + 1):
			var j: int = _head[base + cx]
			while j != -1:
				if j == row or fac[j] != myf or st[j] == dead_state:
					j = _next[j]
					continue
				var dx: float = at_x - px[j]
				var dz: float = at_z - pz[j]
				var dd: float = dx * dx + dz * dz
				if dd >= d_sq:
					j = _next[j]
					continue
				if dd < 1e-8:
					# РОВНО В ОДНОЙ ТОЧКЕ. Направление обязано быть СВОИМ у
					# каждого, иначе куча не расходится, а разъезжается лучами
					# (см. историю в прежнем SpatialGrid): угол берём из номера
					# строки
					var ang: float = float(row % 251) * (TAU / 251.0)
					dx = cos(ang) * 0.01
					dz = sin(ang) * 0.01
					dd = dx * dx + dz * dz
				var d: float = sqrt(dd)
				var need: float = (min_dist - d) / d
				pxa += dx * need
				pza += dz * need
				j = _next[j]
	var plen_sq: float = pxa * pxa + pza * pza
	if plen_sq <= 1e-10:
		return Vector3.ZERO
	if plen_sq > max_push * max_push:
		var k: float = max_push / sqrt(plen_sq)
		pxa *= k
		pza *= k
	return Vector3(pxa, 0.0, pza)

## ЕСТЬ ЛИ ХОТЬ ОДИН ЧУЖОЙ в округе. Дешёвый предварительный отсев: прежде это
## делал отдельный «грубый слой» из редких клеток по 16 м, потому что обход
## словаря был дорог. Плоской сетке отдельный слой не нужен — обход ячеек здесь
## и есть дешёвая операция
## ОТВЕТ ДАЁТ РЕДКАЯ СЕТКА, А НЕ МЕТРОВАЯ. Радиус здесь — десятки метров
## (габариты отряда плюс дальность его внимания), и подробный обход означал бы
## тысячи ячеек; клеток по 16 м на тот же круг приходится единицы.
## Ответ КОНСЕРВАТИВНЫЙ, ровно как и был: «да» может прозвучать, когда чужой
## стоит чуть за границей круга. Все вызывающие это учитывают — «да» лишь
## отменяет быстрый путь и включает подробную проверку
func enemy_near(x: float, z: float, my_faction: int, radius: float) -> bool:
	if _cw == 0:
		return false
	var foe: int = 1 - my_faction
	if foe < 0 or foe > 1:
		return true      # неизвестная сторона — честно идём в подробный скан
	var cx0: int = int((x - radius - _gx0) * _cinv)
	var cz0: int = int((z - radius - _gz0) * _cinv)
	var cx1: int = int((x + radius - _gx0) * _cinv)
	var cz1: int = int((z + radius - _gz0) * _cinv)
	if cx1 < 0 or cz1 < 0 or cx0 >= _cw or cz0 >= _chh:
		return false
	if cx0 < 0: cx0 = 0
	if cz0 < 0: cz0 = 0
	if cx1 >= _cw: cx1 = _cw - 1
	if cz1 >= _chh: cz1 = _chh - 1
	for cz in range(cz0, cz1 + 1):
		var base: int = cz * _cw
		for cx in range(cx0, cx1 + 1):
			if _coarse[(base + cx) * 2 + foe] > 0:
				return true
	return false

## УПЁРЛИСЬ ВО ВРАЖЕСКИЙ СТРОЙ: суммарная нормаль ОТ чужих к нам.
## Свои не блокируют — союзники проходят друг сквозь друга
func enemy_block(row: int, tx: float, tz: float, min_dist: float) -> Vector3:
	var myf: int = fac[row]
	# ПРЕДВАРИТЕЛЬНЫЙ ОТСЕВ ПО РЕДКОЙ СЕТКЕ. Марш по своей половине карты — это
	# сотни бойцов, каждый кадр перебирающих ячейки, битком набитые СВОИМИ, ради
	# ответа «чужих нет». Одна проверка редкой клетки отвечает на это сразу
	if not enemy_near(tx, tz, myf, min_dist):
		return Vector3.ZERO
	var box := _cell_box(tx, tz, min_dist)
	if box.is_empty():
		return Vector3.ZERO
	var d_sq_limit: float = min_dist * min_dist
	var nx := 0.0
	var nz := 0.0
	for cz in range(box[1], box[3] + 1):
		var base: int = cz * _gw
		for cx in range(box[0], box[2] + 1):
			var j: int = _head[base + cx]
			while j != -1:
				if j == row or fac[j] == myf or st[j] == dead_state:
					j = _next[j]
					continue
				var dx: float = tx - px[j]
				var dz: float = tz - pz[j]
				var d_sq: float = dx * dx + dz * dz
				if d_sq >= d_sq_limit:
					j = _next[j]
					continue
				if d_sq < 0.0001:
					var rv := Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
					nx += rv.x
					nz += rv.z
				else:
					var inv: float = 1.0 / sqrt(d_sq)
					nx += dx * inv
					nz += dz * inv
				j = _next[j]
	return Vector3(nx, 0.0, nz)

## СКОЛЬКО СВОИХ ПРЯМО ПЕРЕДО МНОЙ («в моей колонне») — по этому числу фаланга
## определяет фактический ряд бойца
func allies_ahead(row: int, dx_dir: float, dz_dir: float, look: float,
		half_width: float) -> int:
	var x: float = px[row]
	var z: float = pz[row]
	var mx: float = x + dx_dir * look * 0.5
	var mz: float = z + dz_dir * look * 0.5
	var r: float = look * 0.5 + half_width + _gcell
	var box := _cell_box(mx, mz, r)
	if box.is_empty():
		return 0
	var myf: int = fac[row]
	var count := 0
	for cz in range(box[1], box[3] + 1):
		var base: int = cz * _gw
		for cx in range(box[0], box[2] + 1):
			var j: int = _head[base + cx]
			while j != -1:
				if j == row or fac[j] != myf or st[j] == dead_state:
					j = _next[j]
					continue
				var dx: float = px[j] - x
				var dz: float = pz[j] - z
				var along: float = dx * dx_dir + dz * dz_dir
				if along <= 0.12 or along > look:
					j = _next[j]
					continue
				var lat: float = absf(dx * -dz_dir + dz * dx_dir)
				if lat <= half_width:
					count += 1
				j = _next[j]
	return count

## СМЕЩЕНИЕ ДО ГЕОМЕТРИЧЕСКИ БЛИЖАЙШЕГО ВРАГА (без штрафа за занятость —
## это «куда смотрит строй», а не выбор цели)
func nearest_enemy_offset(row: int, radius: float) -> Vector3:
	var x: float = px[row]
	var z: float = pz[row]
	var myf: int = fac[row]
	# Тот же отсев, что и у enemy_block. Прежняя реализация его здесь НЕ имела,
	# и скан на двадцать метров у лучника шёл полностью даже на пустой округе
	if not enemy_near(x, z, myf, radius):
		return Vector3.ZERO
	var box := _cell_box(x, z, radius)
	if box.is_empty():
		return Vector3.ZERO
	var best_sq: float = radius * radius
	var bx := 0.0
	var bz := 0.0
	var found := false
	for cz in range(box[1], box[3] + 1):
		var base: int = cz * _gw
		for cx in range(box[0], box[2] + 1):
			var j: int = _head[base + cx]
			while j != -1:
				if j == row or fac[j] == myf or st[j] == dead_state:
					j = _next[j]
					continue
				var dx: float = px[j] - x
				var dz: float = pz[j] - z
				var d_sq: float = dx * dx + dz * dz
				if d_sq < best_sq:
					best_sq = d_sq
					bx = dx
					bz = dz
					found = true
				j = _next[j]
	return Vector3(bx, 0.0, bz) if found else Vector3.ZERO

## ЛУЧШАЯ ВРАЖЕСКАЯ ЦЕЛЬ В РАДИУСЕ. Отбор тот же: к расстоянию добавляется
## штраф за каждого, уже атакующего эту цель, — так линия разбирает противников
## почти один к одному, а не сваливается толпой на ближайшего.
## `attackers` живёт на объекте, поэтому читается только у прошедших по
## расстоянию, а не у всех подряд
func best_enemy(row: int, radius: float, crowd_penalty: float):
	var x: float = px[row]
	var z: float = pz[row]
	var myf: int = fac[row]
	# Отсев по редкой сетке: у лучника радиус двадцать метров, и без него скан
	# шёл по сотням метровых ячеек даже когда врагов на карте нет вовсе
	if not enemy_near(x, z, myf, radius):
		return null
	var box := _cell_box(x, z, radius)
	if box.is_empty():
		return null
	var r_sq: float = radius * radius
	var best = null
	var best_score := INF
	for cz in range(box[1], box[3] + 1):
		var base: int = cz * _gw
		for cx in range(box[0], box[2] + 1):
			var j: int = _head[base + cx]
			while j != -1:
				if j == row or fac[j] == myf or st[j] == dead_state:
					j = _next[j]
					continue
				var dx: float = x - px[j]
				var dz: float = z - pz[j]
				var d_sq: float = dx * dx + dz * dz
				if d_sq > r_sq:
					j = _next[j]
					continue
				var u = unit_of[j]
				if u == null or not is_instance_valid(u):
					j = _next[j]
					continue
				var score: float = sqrt(d_sq) + float(u.attackers) * crowd_penalty
				if score < best_score:
					best_score = score
					best = u
				j = _next[j]
	return best

## ВСЕ БОЙЦЫ В РАДИУСЕ, узлами. Холодный путь: клик мышью, попадание стрелы
func query_radius(x: float, z: float, radius: float) -> Array:
	var out: Array = []
	var box := _cell_box(x, z, radius)
	if box.is_empty():
		return out
	var r_sq: float = radius * radius
	for cz in range(box[1], box[3] + 1):
		var base: int = cz * _gw
		for cx in range(box[0], box[2] + 1):
			var j: int = _head[base + cx]
			while j != -1:
				var dx: float = x - px[j]
				var dz: float = z - pz[j]
				if dx * dx + dz * dz <= r_sq:
					var u = unit_of[j]
					if u != null and is_instance_valid(u):
						out.append(u)
				j = _next[j]
	return out

# ═══════════════════════════════════════════════════════════════════════════
# ПАКЕТНЫЙ РАЗБОР НАЛОЖЕНИЯ (Фаза 3)
# ═══════════════════════════════════════════════════════════════════════════
# Было: Unit._resolve_overlap на каждого бойца по своему таймеру. Один вызов —
# это выход в GameManager.unit_grid (фасад) → оттуда в ArmySoA.ally_overlap,
# потом чтения GameManager.map_lim_*, water_active, get_terrain_height и запись
# global_position. Замер на 15000: ветка sep_overlap — 3.71 мкс на вызов при
# 2500 вызовах в кадр, то есть около 9 мс.
#
# Стало: ОДИН проход по строкам. Скан соседей развёрнут прямо здесь (тот же
# код, что в ally_overlap, но без вызова), таймеры — столбец, границы карты
# сняты в локальные переменные до цикла. Наружу выходим ТОЛЬКО за тех, кого
# реально сдвинуло: высота рельефа, проверка воды и пробуждение картинки.
#
# ПРАВИЛО НЕ ИЗМЕНИЛОСЬ НИ НА ЙОТУ (см. историю у SEP_MIN_DIST): поправка
# монотонна (только наружу и только пока есть наложение), у идущего по приказу
# из неё вырезается составляющая ПРОТИВ курса, за край карты она не выталкивает
# и в воду не выдавливает.
#
# `gm` — GameManager: за высотой рельефа и водой всё равно надо выйти наружу,
# но теперь только за сдвинутыми, а не за всеми подряд.
# Возвращает, скольких сдвинуло (для стендов)
## `deadzone` — ниже какой суммарной поправки наложение не разбирается вовсе.
## См. Unit.SEP_DEADZONE: без него плотный строй перетаптывается вечно
func batch_separation(delta: float, min_dist: float, max_step: float,
		interval: float, lim_x: float, lim_z: float, moving_state: int,
		attacking_state: int, water_on: bool, gm, deadzone: float = 0.0) -> int:
	if _gw == 0:
		return 0
	var dead := dead_state
	var d_sq: float = min_dist * min_dist
	var max_sq: float = max_step * max_step
	# ПОРОГ ПРИМЕНЯЕТСЯ К КАЖДОМУ СОСЕДУ, А НЕ К СУММЕ ПОПРАВОК. На сумме он
	# работал слишком грубо: бойца, зажатого симметрично с двух сторон, толчки
	# гасят взаимно, сумма выходит около нуля — и он не двигался вовсе, даже
	# когда оба наложения настоящие. Гарантия минимального зазора при этом
	# терялась (qa_crowd A1: 0.2185 м при пороге 0.2917). На отдельном соседе
	# смысл ровно тот, что и просили: «этот стоит чуть теснее, чем хотелось бы,
	# но это уже не наложение», и нижняя граница зазора становится жёсткой —
	# min_dist минус мёртвая зона
	var near_d: float = maxf(min_dist - deadzone, 0.0)
	var near_sq: float = near_d * near_d
	var moved := 0
	for i in range(_capacity):
		if (flags[i] & F_POS_VALID) == 0:
			continue
		var s: int = st[i]
		if s == dead:
			continue
		var t: float = sep_t[i] - delta
		if t > 0.0:
			sep_t[i] = t
			continue
		sep_t[i] = interval
		# ── СКАН СОСЕДЕЙ, РАЗВЁРНУТЫЙ НА МЕСТЕ ─────────────────────────────
		var x: float = px[i]
		var z: float = pz[i]
		var cx0: int = int((x - min_dist - _gx0) * _ginv)
		var cz0: int = int((z - min_dist - _gz0) * _ginv)
		var cx1: int = int((x + min_dist - _gx0) * _ginv)
		var cz1: int = int((z + min_dist - _gz0) * _ginv)
		if cx0 < 0: cx0 = 0
		if cz0 < 0: cz0 = 0
		if cx1 >= _gw: cx1 = _gw - 1
		if cz1 >= _gh: cz1 = _gh - 1
		var myf: int = fac[i]
		var pxa := 0.0
		var pza := 0.0
		for cz in range(cz0, cz1 + 1):
			var base: int = cz * _gw
			for cx in range(cx0, cx1 + 1):
				var j: int = _head[base + cx]
				while j != -1:
					if j == i or fac[j] != myf or st[j] == dead:
						j = _next[j]
						continue
					var dx: float = x - px[j]
					var dz: float = z - pz[j]
					var dd: float = dx * dx + dz * dz
					# МЁРТВАЯ ЗОНА: сосед, стоящий чуть теснее нормы, в расчёт
					# не идёт. Без этого в плотном строю у каждого всегда
					# находился сосед на доли миллиметра ближе положенного,
					# поправка не обнулялась никогда, и весь строй мелко
					# перетаптывался пятнадцать раз в секунду
					if dd >= near_sq:
						j = _next[j]
						continue
					if dd < 1e-8:
						# Ровно в одной точке: направление своё у каждого,
						# иначе куча разъезжается лучами (см. ally_overlap)
						var ang: float = float(i % 251) * (TAU / 251.0)
						dx = cos(ang) * 0.01
						dz = sin(ang) * 0.01
						dd = dx * dx + dz * dz
					var d: float = sqrt(dd)
					var need: float = (min_dist - d) / d
					pxa += dx * need
					pza += dz * need
					j = _next[j]
		var plen_sq: float = pxa * pxa + pza * pza
		if plen_sq <= 1e-10:
			continue
		if plen_sq > max_sq:
			var k: float = max_step / sqrt(plen_sq)
			pxa *= k
			pza *= k
		# ── ИДУЩЕГО ПО ПРИКАЗУ ПОПРАВКА НЕ ОТБРАСЫВАЕТ НАЗАД ────────────────
		if s == moving_state or s == attacking_state:
			var vxx: float = vx[i]
			var vzz: float = vz[i]
			var vlen: float = sqrt(vxx * vxx + vzz * vzz)
			if vlen > 0.001:
				var nx0: float = vxx / vlen
				var nz0: float = vzz / vlen
				var along: float = pxa * nx0 + pza * nz0
				if along < 0.0:
					pxa -= nx0 * along
					pza -= nz0 * along
					if absf(pxa) < 1e-5 and absf(pza) < 1e-5:
						continue
		# КРАЙ КАРТЫ. Зажим РАСШИРЕН текущей точкой: поправка вправе не пускать
		# за край, но не вправе затаскивать внутрь того, кто уже снаружи (стенды
		# работают на площадках в сотнях метров от центра карты)
		var nx: float = clampf(x + pxa, minf(-lim_x, x), maxf(lim_x, x))
		var nz: float = clampf(z + pza, minf(-lim_z, z), maxf(lim_z, z))
		var u = unit_of[i]
		if u == null or not is_instance_valid(u):
			continue
		# В воду не выдавливаем: оттуда боец сам не выйдет
		if water_on and gm.is_water(nx, nz):
			continue
		var ny: float = gm.get_terrain_height(nx, nz)
		px[i] = nx
		py[i] = ny
		pz[i] = nz
		# Локальный трансформ вдвое дешевле мирового, и под неподвижным World
		# это одно и то же число (см. Unit._local_xform)
		if u._local_xform:
			u.position = Vector3(nx, ny, nz)
		else:
			u.global_position = Vector3(nx, ny, nz)
		# Стоящий боец спит по картинке и своего нового места сам не перерисует
		u.wake_for_lod()
		moved += 1
	return moved

# ═══════════════════════════════════════════════════════════════════════════
# ДВИЖЕНИЕ МАТРИЦЕЙ ОТРЯДА (Этап 1)
# ═══════════════════════════════════════════════════════════════════════════
# Пока отряд идёт по чистому коридору и никто в нём не дерётся, считать шаг
# КАЖДОМУ бойцу незачем: они держат строй, то есть их взаимное расположение не
# меняется вовсе. Отряд двигает ОДИН якорь, а боец получает свою точку как
# «якорь плюс моё смещение, повёрнутое на курс» — три умножения и две записи.
#
# ЧТО ЭТО УБИРАЕТ С КАЖДОГО БОЙЦА: направление и нормировку, множители
# скорости, проверку воды, запрос ствола, проверку чужого строя, зажим по краю
# карты, высоту рельефа и запись координаты через свойство узла. В профиле
# марша это ветки process_move / mb_* — около двух третей физического тика.
#
# ЧЕГО ЭТО НЕ ДЕЛАЕТ И НЕ ДОЛЖНО: решать, МОЖНО ли идти матрицей. Это решает
# вызывающий (см. GameManager) по ответам коридора и состоянию бойцов; здесь
# только сам шаг.

## Записать бойцу его место в матрице отряда. Зовётся при выдаче разметки строя
func set_slot(i: int, off_x: float, off_z: float) -> void:
	if i < 0:
		return
	sl_x[i] = off_x
	sl_z[i] = off_z

## ШАГ ОТРЯДА МАТРИЦЕЙ.
##
## `rows` — строки живых бойцов отряда, `ax/az` — якорь, `cx/cz` — единичный
## курс, `ny` — высота рельефа под якорем (считается ОДИН раз на отряд: на
## габаритах отряда рельеф меняется на сантиметры, самая короткая гармоника
## имеет длину волны около 13 м).
##
## Курс задаёт поворот: локальная ось Z смотрит по курсу, локальная X — вбок.
## Возвращает число расставленных бойцов
## `amp` — амплитуда рельефа (Main.RELIEF_AMP). Ноль означает «высота одна на
## весь отряд и равна ny» — так зовут стенды и так было в первой версии.
##
## ПОЧЕМУ РЕЛЬЕФ СЧИТАЕТСЯ ЗДЕСЬ, А НЕ ВЫЗОВОМ НАРУЖУ. Одна высота на отряд
## расходится с землёй на габаритах строя: три гармоники дают до ~13 см на
## пятиметровом строю и вдвое больше на полусотне бойцов — этого хватает, чтобы
## фланг заметно висел над травой или тонул в ней. Звать GameManager на каждого
## бойца нельзя (ровно та цена, ради ухода от которой матрица и заводилась), но
## сама формула — три синуса, и в теле цикла она бесплатна.
## ЕДИНСТВЕННЫЙ ИСТОЧНИК ВЫСОТЫ по-прежнему Main.get_terrain_height: здесь
## лежит его копия, и меняться они обязаны вместе (сторожит qa_army/Matrix A5)
func advance_matrix(rows: PackedInt32Array, ax: float, az: float, ny: float,
		cx: float, cz: float, amp: float = 0.0) -> int:
	# Правая тройка: вбок = поворот курса на 90°
	var rx: float = cz
	var rz: float = -cx
	var n := 0
	for k in range(rows.size()):
		var i: int = rows[k]
		if i < 0 or i >= _capacity:
			continue
		var ox: float = sl_x[i]
		var oz: float = sl_z[i]
		var wx: float = ax + rx * ox + cx * oz
		var wz: float = az + rz * ox + cz * oz
		px[i] = wx
		pz[i] = wz
		if amp != 0.0:
			py[i] = ny + amp * (
				  0.55 * sin(wx * 0.031 + wz * 0.017)
				+ 0.30 * sin(wx * 0.013 - wz * 0.041 + 1.7)
				+ 0.15 * sin(wx * 0.077 + wz * 0.059 + 3.1))
		else:
			py[i] = ny
		flags[i] |= F_POS_VALID
		n += 1
	return n

## Перенести посчитанные точки в узлы бойцов. Отдельным проходом, потому что
## это ЕДИНСТВЕННОЕ место шага, где приходится выходить наружу: пока у бойца
## есть узел, его трансформ обязан совпадать с колонкой (по нему идут выбор
## мышью, туман и всё остальное). Локальный трансформ вдвое дешевле мирового
## под неподвижным World — см. Unit._local_xform
func push_to_nodes(rows: PackedInt32Array) -> void:
	for k in range(rows.size()):
		var i: int = rows[k]
		if i < 0 or i >= _capacity:
			continue
		var u = unit_of[i]
		if u == null or not is_instance_valid(u):
			continue
		var p := Vector3(px[i], py[i], pz[i])
		if u._local_xform:
			u.position = p
		else:
			u.global_position = p

## Полный сброс (новая партия). Массивы не ужимаем: следующая партия наберёт
## столько же, а resize вниз и обратно — это два копирования
func clear() -> void:
	_free.resize(0)
	var i: int = _capacity - 1
	while i >= 0:
		flags[i] = 0
		fac[i] = -1
		unit_of[i] = null
		_free.append(i)
		i -= 1
	_used = 0
	_gw = 0
	_gh = 0
	_grid_n = 0
