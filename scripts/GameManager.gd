extends Node

var main: Node3D = null
var dropoffs: Dictionary = {}
# Пространственная сетка юнитов (см. SpatialGrid.gd); load() — чтобы не зависеть от кэша классов
var unit_grid = load("res://scripts/SpatialGrid.gd").new()
# Реестр отрисовки дальних юнитов общим MultiMesh (см. FarUnitRenderer.gd)
var far_units = load("res://scripts/FarUnitRenderer.gd").new()
# Кольца и тени выделения — тоже общим MultiMesh (см. SelectionDecalRenderer.gd)
var sel_decals = load("res://scripts/SelectionDecalRenderer.gd").new()
## Деревья и кусты — тоже общим MultiMesh (см. VegetationRenderer.gd).
## Замер qa_veg: до этого одна декорация стоила 1762 вызова отрисовки и
## упирала пустую карту в 75 кадров в секунду
var veg = load("res://scripts/VegetationRenderer.gd").new()
## Полоски здоровья — тоже общим MultiMesh (см. HpBarRenderer.gd). Замер: узлами
## на бойца тумблер Alt стоил +2.8 мс и +720 вызовов отрисовки на 600 бойцах
var hp_bars = load("res://scripts/HpBarRenderer.gd").new()
## Тела павших — тоже общим MultiMesh (см. CorpseRenderer.gd). Труп не юнит:
## ни строки в ядре армии, ни состояния, ни физического тика — он заводится
## уже ПОСЛЕ того, как боец снял с себя всё это в _die()
var corpses = load("res://scripts/CorpseRenderer.gd").new()
## ── ЧТО ОТРЯДУ ПРИКАЗАНО ПРЯМО СЕЙЧАС ──────────────────────────────────────
## sid -> {"kind": ORDER_MOVE | ORDER_ATTACK, "pos": Vector3, "target": Node}.
## Заводится в SelectionManager при ПКМ и живёт до исполнения. Нужен ровно для
## одного: показать игроку, кому и куда он уже приказал, — и показать это СНОВА,
## когда он вернётся к этому отряду через полминуты (см. _refresh_order_marks).
##
## Сама логика боя этот словарь не читает: приказ живёт в бойцах, здесь только
## его отражение для глаз. Иначе получилось бы второе, конкурирующее хранилище
## приказов — а одно уже есть
var squad_orders: Dictionary = {}
const ORDER_MOVE := 0
const ORDER_ATTACK := 1
## ЯДРО АРМИИ В МАССИВАХ (см. scripts/army/ArmySoA.gd). Строку заводит сам боец
## в _ready и отдаёт в _exit_tree; пишет в неё он же, сквозь, из тех мест, где
## и так менял эти величины. Читают — только ПАКЕТНЫЕ обходы: коридоры отрядов
## и сканы соседей в пространственной сетке
var army = load("res://scripts/army/ArmySoA.gd").new()
## Туман войны (см. FogOfWar.gd). Ставит и настраивает Main; до этого — null,
## и все запросы отвечают «видно», чтобы стенды без карты работали как раньше
var fog: Node3D = null

## Просматривается ли точка своими прямо сейчас.
## ГОРЯЧИЙ ПУТЬ: спрашивают только ЧУЖИЕ юниты (свои видны всегда), то есть
## вызов идёт не за каждого бойца армии, а лишь за вражеских — и только на
## визуальном тике, который к тому же поделён на шарды
func fog_lit_at(x: float, z: float) -> bool:
	if fog == null:
		return true
	return (fog as FogOfWar).is_lit(x, z)

## Показать/убрать метки выделения под бойцом (см. Unit.set_selected)
func set_unit_selected_decal(unit: Unit, shown: bool) -> void:
	if shown:
		if main == null:
			return
		sel_decals.register(unit, main.world_root())
	else:
		sel_decals.unregister(unit)

## Поставить юнита в общую отрисовку (см. Unit._sync_far_render).
## Тон и признак движения больше не нужны: бакет определяется ЛЕНТОЙ кадров,
## а она уже несёт и цвет стороны (у сторон разные файлы), и текущую анимацию
## Возвращает слот в общей отрисовке: боец держит на него прямую ссылку и
## двигает себя сам, без поиска по словарю (см. FarUnitRenderer.Slot.move_to)
func register_far(unit: Unit, mirror: bool):
	if main == null:
		return null
	return far_units.register(unit, main.world_root(), mirror)

func unregister_far(unit: Unit) -> void:
	far_units.unregister(unit)

func update_far_transform(unit: Unit, pos: Vector3, mirror: bool) -> void:
	far_units.update_transform(unit, pos, mirror)

# ─────────────────────────────────────────────────────────────────────────────
# ПОДАЧА БУФЕРОВ MultiMesh — ОДИН РАЗ ЗА КАДР, ПОСЛЕ ВСЕХ ЮНИТОВ
#
# Бойцы в своём _process пишут в теневые буферы бакетов (обычная запись в
# массив), а сюда стекается единственный set_buffer на каждый ИЗМЕНИВШИЙСЯ
# бакет. Было по два обращения в RenderingServer на модель в кадр — на 810
# копейщиках это полторы тысячи вызовов, и именно они, а не счёт в GDScript,
# держали кадр (замер: выключение одного лишь Unit._process поднимало кадры
# с 33 до 216 при неизменных 4 мс расчёта).
#
# process_priority — обязателен. Автозагрузка стоит в дереве ПЕРВОЙ, и её
# _process по умолчанию идёт ПЕРЕД юнитами: буфер уезжал бы в сервер до того,
# как бойцы в него написали, то есть картинка отставала бы ровно на кадр
func _ready() -> void:
	process_priority = 1000
	# Номер состояния «мёртв» отдаётся ядру армии ОДИН раз: внутри сканов
	# соседей он сравнивается с каждым кандидатом, а обращение к константе
	# чужого скрипта в таком цикле стоит дороже самого сравнения
	army.dead_state = Unit.State.DEAD

func _process(_delta: float) -> void:
	# ── ВИЗУАЛ АРМИИ — ОДНИМ ЦИКЛОМ, А НЕ ПЯТЬЮ ТЫСЯЧАМИ НОТИФИКАЦИЙ ─────────
	# Тот же приём и тот же реестр, что и у физического тика (см. ниже про
	# _live_units), и то же чередование по кадрам: при shards == 2 боец и
	# шагает через кадр, значит в промежуточном кадре его позиция ЗАВЕДОМО не
	# менялась — гонять ради неё LOD, походку, ракурс и слот отрисовки незачем.
	# Порядок сохранён: сначала бойцы пишут в теневые буферы, потом flush
	var _meter: bool = _Opt.vis_meter
	var _vm0: int
	if _meter: _vm0 = Time.get_ticks_usec()
	var live_n: int = _live_units.size()
	var shards: int = _Opt.shards_for(active_units())
	# ── СГЛАЖИВАНИЕ КАРТИНКИ МЕЖДУ ФИЗИЧЕСКИМИ ШАГАМИ ───────────────────────
	# Боец двигается не каждый кадр отрисовки, а раз в свой физический тик, и при
	# шардировании — раз в `shards` тиков. На тысяче бойцов шардов два, то есть
	# положение меняется ТРИДЦАТЬ раз в секунду шагами двойной длины, а рисуется
	# картинка вдвое-втрое чаще. Глазу это читается как дёрганье, и никакой
	# физики в нём нет — это чистая рассинхронизация частот.
	# Доля сближения считается ЗДЕСЬ, один раз на кадр: внутри бойца это была бы
	# пара делений на каждого. Постоянная времени — примерно один интервал его
	# обновления, тогда картинка догоняет ровно к следующему шагу и не отстаёт
	# ── ПОСТОЯННАЯ БЕРЁТСЯ ОТ ВИЗУАЛЬНОГО ТАКТА, А НЕ ОТ ФИЗИЧЕСКОГО ────────
	# Пока такты совпадали, разницы не было. Но визуальный проход вправе
	# дробиться чаще (vis_shards_extra), и тогда нарисованная точка обновляется
	# реже, чем считает эта формула, — сглаживание оказывается настроенным на
	# более частый шаг и не догоняет. Замер поймал это сразу: «рывок шага»
	# 1.64 → 1.80-2.32 при добавлении одного визуального шарда
	var vsh: int = _Opt.vis_shards_for(live_n)
	var upd: float = float(vsh) / 60.0
	vis_lerp_k = clampf(_delta / maxf(upd * VIS_SMOOTH_TAU, 0.0005), 0.0, 1.0)
	# Номер кадра — ОДИН вызов в движок на всю армию, а не по одному на бойца
	var frame: int = Engine.get_process_frames()
	# Такт пересчёта позы тоже считается ОДИН раз на всю армию и раздаётся
	# аргументом (см. perf_config.anim_every_for и шапку Unit.tick_visual)
	var anim_every: int = _Opt.anim_every_for(live_n)
	# ── ОБЩЕЕ НА АРМИЮ СНИМАЕТСЯ ЗДЕСЬ, ОДИН РАЗ (см. шапку Unit.tick_visual) ─
	# Точка обзора и четыре настройки одинаковы для всех и менялись бы не чаще
	# раза в кадр, а читались из КАЖДОГО бойца в КАЖДОМ кадре — семь обращений
	# к чужим объектам на бойца. Выключенный LOD выражаем бесконечным радиусом:
	# так у бойца исчезает и ветка, и чтение настройки
	var vx0: float = _view_x
	var vz0: float = _view_z
	var vr2: float = _view_r2 if _Opt.sprite_lod else INF
	var lerpk: float = vis_lerp_k if _Opt.visual_smoothing else 1.0
	var mm_all: bool = _Opt.mm_render_all
	var vprof: bool = _Opt.profile_physics
	# Туман спрашивается за ВСЮ армию один раз: при выключенном тумане у бойца
	# исчезают два обращения к чужим объектам на кадр
	var fog_on: bool = fog != null and (fog as FogOfWar).enabled
	# Визуальный проход вправе дробиться ЧАЩЕ физического (см.
	# perf_config.vis_shards_extra): шаг обязан быть верным, картинка — гладкой,
	# и это разные требования
	var vshards: int = vsh
	if vshards <= 1:
		for u in _live_units:
			if is_instance_valid(u) and u.draw_on:
				u.tick_visual(_delta, frame, anim_every, vx0, vz0, vr2,
					lerpk, mm_all, vprof, fog_on)
	else:
		var i: int = frame % vshards
		var d: float = _delta * float(vshards)
		while i < live_n:
			var u = _live_units[i]
			if is_instance_valid(u) and u.draw_on:
				u.tick_visual(d, frame, anim_every, vx0, vz0, vr2,
					lerpk, mm_all, vprof, fog_on)
			i += vshards
	# ── ДОВЕДЕНИЕ КАРТИНКИ — БЕЗ ШАРДИРОВАНИЯ ───────────────────────────────
	# Цикл выше идёт по одному шарду за кадр: при трёх шардах боец получает
	# новую позицию двадцать раз в секунду, а рисуется шестьдесят. Сглаживание
	# сидело ВНУТРИ этого цикла и потому срабатывало ровно в момент шага — то
	# есть не сглаживало ничего, только добавляло отставание. Теперь догон
	# делает отдельный проход КАЖДЫЙ кадр (см. Unit.tick_draw): он состоит из
	# чтения строки, одного умножения и записи трёх float в общий буфер.
	# При одном шарде проход не нужен — там tick_visual и так идёт каждый кадр
	if shards > 1 and _Opt.draw_catchup:
		for u in _live_units:
			if is_instance_valid(u) and u.draw_on:
				u.tick_draw()
	# Метки выделения и полоски здоровья — СРАЗУ ПОСЛЕ бойцов и ДО подачи в
	# рендер: они берут ту же нарисованную точку, которую только что посчитал
	# tick_visual, и обязаны совпасть с ней кадр в кадр
	# ── ХВОСТ КАДРА ЗАМЕРЯЕТСЯ ОТДЕЛЬНЫМИ ВЕТКАМИ ──────────────────────────
	# До этого весь хвост шёл мимо профиля: разбивка показывала только тик
	# бойцов, а «остальное» приходилось считать вычитанием из общего кадра.
	# Между тем подача буферов в рендер (far_units.flush → set_buffer на бакет)
	# растёт прямо с числом бойцов и в тик бойцов не входит вовсе
	var _t1: int
	if vprof: _t1 = Time.get_ticks_usec()
	sel_decals.update_all()
	hp_bars.update_all()
	if vprof: _Opt.prof_add("draw_decals", Time.get_ticks_usec() - _t1)
	if vprof: _t1 = Time.get_ticks_usec()
	far_units.flush()
	sel_decals.flush()
	hp_bars.flush()
	if vprof: _Opt.prof_add("draw_flush", Time.get_ticks_usec() - _t1)
	# Растительность не ходит: flush сам ничего не делает, пока никто ничего не
	# сажал и не рубил (см. VegetationRenderer._dirty_any)
	veg.flush()
	# Тела павших: ход и подача рядом с остальной наземной отрисовкой. Пока
	# никто не растворяется, update() не делает ни одной операции, а flush()
	# молчит, пока в буфер никто не писал
	corpses.update(_delta)
	corpses.flush()
	# Указатели отданных приказов: пересчитываются по выделению и гаснут сами,
	# когда отряд дошёл (см. _refresh_order_marks)
	if vprof: _t1 = Time.get_ticks_usec()
	_refresh_order_marks(_delta)
	sel_decals.flush_orders()
	if vprof: _Opt.prof_add("draw_orders", Time.get_ticks_usec() - _t1)
	# Знамёна ветеранства едут за знаменосцами (см. _update_squad_banners).
	# Стоит ПОСЛЕ тика бойцов: нарисованные точки за этот кадр уже окончательные
	if vprof: _t1 = Time.get_ticks_usec()
	_update_squad_banners()
	if vprof: _Opt.prof_add("draw_stars", Time.get_ticks_usec() - _t1)
	# ── СЧЁТЧИК ЗАКРЫВАЕТСЯ ЗДЕСЬ, А НЕ ПОСЛЕ ЦИКЛА ПО БОЙЦАМ ──────────────
	# Он стоял сразу за обходом армии и не видел ВЕСЬ хвост кадра: метки,
	# подачу буферов в рендер, тела, указатели приказов, звёзды. Из-за этого
	# «цена визуального тика» выходила заведомо заниженной, и в разборе кадра
	# не сходилась примерно треть времени
	if _meter: _Opt.vis_add(Time.get_ticks_usec() - _vm0)

# ─────────────────────────────────────────────────────────────────────────────
# ЦЕНТРАЛИЗОВАННЫЙ ФИЗ. ТИК ЮНИТОВ (см. шапку Unit.tick_physics)
#
# Юнит регистрируется здесь в _ready() и снимается в _exit_tree(). Плоский
# массив, а не get_tree().get_nodes_in_group("all_units") каждый кадр — та
# группа копирует внутренний Array при каждом обращении, а этот обход идёт
# 60 раз в секунду. Группа "all_units" никуда не делась и по-прежнему годится
# для редких точечных обращений (не каждый кадр).
#
# is_physics_processing() — ТОТ ЖЕ тумблер, что и раньше: Castle.absorb_unit/
# release_unit и стенды (qa_guard, qa_formation) зовут set_physics_process()
# на юните, ожидая, что это выключит его тик. Раньше это выключало движковую
# нотификацию; теперь движок этот метод вообще не вызывает (юнит больше не
# переопределяет _physics_process), а тумблер остаётся обычным читаемым
# Node-флагом — здесь он и проверяется вручную. Семантика для вызывающего
# кода не изменилась ни на строку.
var _live_units: Array = []

## ── СНЯТИЕ С УЧЁТА — ЗА ПОСТОЯННОЕ ВРЕМЯ, А НЕ ПОИСКОМ ПО МАССИВУ ───────────
## Здесь стоял `_live_units.erase(u)`. Array.erase — это ЛИНЕЙНЫЙ ПОИСК плюс
## сдвиг хвоста: на пятнадцати тысячах бойцов одна смерть стоит в среднем 7500
## сравнений, а массовая гибель армии — квадрат от её размера. В бою на 15000
## это единственное место во всём проекте с настоящей O(n²).
##
## Теперь боец помнит свой индекс в реестре (_live_idx), выбывший заменяется
## ПОСЛЕДНИМ, и массив укорачивается на единицу. Порядок реестра при этом
## перестаёт быть порядком рождения — это никого не волнует: обход шардами
## идёт по индексу, а не по возрасту (см. _physics_process), и «боец перескочил
## в другой шард на один кадр» уже было штатным следствием прежнего erase.
##
## Индекс — подсказка, а не истина: если он почему-то не сходится (боец пришёл
## из старого сохранения, стенд подменил реестр), падаем на честный find, а не
## портим чужую запись
func register_unit(u: Unit) -> void:
	u._live_idx = _live_units.size()
	_live_units.append(u)

func unregister_unit(u: Unit) -> void:
	# СПЯЩИЙ, КОТОРОГО УБИЛИ, ОБЯЗАН ВЫЙТИ И ИЗ СЧЁТЧИКА СПЯЩИХ. Иначе счётчик
	# растёт над реестром, active_units() уходит в ноль и вся армия сваливается
	# в один шард независимо от размера
	if u.dormant:
		u.dormant = false
		note_dormant(false)
	var n: int = _live_units.size()
	if n == 0:
		return
	var i: int = u._live_idx
	if i < 0 or i >= n or _live_units[i] != u:
		i = _live_units.find(u)
		if i < 0:
			return
	var last: int = n - 1
	if i != last:
		var moved = _live_units[last]
		_live_units[i] = moved
		moved._live_idx = i
	_live_units.resize(last)
	u._live_idx = -1

func _physics_process(delta: float) -> void:
	# ПОЛНАЯ ЦЕНА ОБХОДА ЮНИТОВ, замеренная напрямую (см. perf_config).
	# Монитор Performance.TIME_PHYSICS_PROCESS для этого не годится: при снятом
	# ограничении кадров (Engine.max_fps = 0, все перф-стенды) рендер тикает
	# заметно чаще физики, усреднение по кадрам отрисовки берёт смещённую
	# выборку, и два соседних замера одной и той же неподвижной сцены давали
	# 10.8 и 20.1 мс. Здесь считается ровно то, что нас интересует, — сколько
	# микросекунд ушло на всех бойцов за этот физический тик
	var _prof: bool = _Opt.profile_physics
	var _t0: int
	# ЛЁГКИЙ СЧЁТЧИК: одна пара вызовов НА КАДР (а не на ветку каждого бойца,
	# как у профиля) — им и меряется честный time_per_tick, см. perf_config
	var _meter: bool = _Opt.tick_meter
	var _tm0: int
	if _meter: _tm0 = Time.get_ticks_usec()
	# ── ПЛОСКАЯ СЕТКА СОБИРАЕТСЯ ЦЕЛИКОМ, ОДИН РАЗ ЗА КАДР (см. ArmySoA) ────
	# Раньше учёт был поштучным: каждый сдвинувшийся боец звал
	# unit_grid.update(self) со сборкой ключа Vector2i и двумя словарями.
	# Здесь вместо этого один проход по столбцам — две записи в массив на
	# бойца и ни одной аллокации.
	#
	# ПОРЯДОК ВАЖЕН: сетка строится ДО обхода бойцов, поэтому все сканы в
	# пределах кадра видят согласованный снимок «на начало кадра», а не
	# зависящую от места в реестре смесь старых и новых позиций
	if _prof: _t0 = Time.get_ticks_usec()
	army.rebuild_grid()
	if _prof: _Opt.prof_add("grid_rebuild", Time.get_ticks_usec() - _t0)
	# КОРИДОР ОТРЯДА — ОДИН РАЗ НА ОТРЯД, А НЕ НА БОЙЦА (см. _sweep_corridors)
	if _prof: _t0 = Time.get_ticks_usec()
	_sweep_corridors()
	if _prof: _Opt.prof_add("squad_corridor", Time.get_ticks_usec() - _t0)
	# ── С КЕМ ДЕРЁТСЯ КАЖДЫЙ ОТРЯД (см. _sweep_melee) ───────────────────────
	if _prof: _t0 = Time.get_ticks_usec()
	_sweep_melee()
	if _prof: _Opt.prof_add("squad_melee", Time.get_ticks_usec() - _t0)
	# ── ЗАЛПОВЫЙ ОГОНЬ ЛУЧНИКОВ (см. _sweep_volleys) ───────────────────────
	# ПОСЛЕ разметки боя и ДО обхода бойцов: окно залпа открывается здесь, а
	# стрелки, которых обход застанет уже открытым, отстреляются в этом же кадре
	if _prof: _t0 = Time.get_ticks_usec()
	_sweep_volleys()
	if _prof: _Opt.prof_add("squad_volley", Time.get_ticks_usec() - _t0)
	# ── ОТРЯДЫ, ИДУЩИЕ МАТРИЦЕЙ (Этап 1) ────────────────────────────────────
	# ПОСЛЕ коридоров (они и дают ответ «путь чист») и ДО обхода бойцов: те,
	# кого повела матрица, свой тик пропустят
	if _prof: _t0 = Time.get_ticks_usec()
	_advance_matrices(delta)
	if _prof: _Opt.prof_add("squad_matrix", Time.get_ticks_usec() - _t0)
	# ── ПАКЕТНЫЙ ПРОХОД БОЯ (см. ArmyCore.BatchCombat) ─────────────────────
	# Стоит ДО обхода армии: он решает, кому в этом кадре вообще нужен полный
	# боевой автомат. Всем прочим шаг подтягивания уже посчитан по колонкам, и
	# в интерпретатор они не заходят.
	#
	# Отметка кадром, а не флагом на бойце: гасить флаг у трёх тысяч пришлось бы
	# отдельным проходом, а сравнение с номером кадра само себя обнуляет
	var shards: int = _Opt.shards_for(active_units())
	var _bm_now: bool = _Opt.batch_move
	if _Opt.batch_combat:
		if _prof: _t0 = Time.get_ticks_usec()
		atk_need = army.batch_combat(delta, Unit.State.ATTACKING,
			Unit.PULL_UP_SPEED, Unit.PULL_UP_MAX,
			shards, Engine.get_physics_frames() % maxi(shards, 1))
		if _prof: _Opt.prof_add("batch_combat", Time.get_ticks_usec() - _t0)
	if _prof: _t0 = Time.get_ticks_usec()
	# ── ЧЕРЕДОВАНИЕ ПО КАДРАМ (см. perf_config.shards_for) ──────────────────
	# Кадр держит работа в ОДНОМ кадре, а не за секунду. Пока армия невелика,
	# shards == 1 и это ровно прежний цикл; на пяти тысячах армия делится
	# надвое, и каждый боец опрашивается через кадр — с удвоенной delta, так
	# что путь, откаты ударов и таймеры остаются те же
	if shards <= 1:
		for u in _live_units:
			if is_instance_valid(u) and u.tick_on:
				u.tick_physics(delta, _prof, _bm_now, bonus_version)
	else:
		var n: int = _live_units.size()
		var i: int = Engine.get_physics_frames() % shards
		var d: float = delta * float(shards)
		while i < n:
			var u = _live_units[i]
			if is_instance_valid(u) and u.tick_on:
				u.tick_physics(d, _prof, _bm_now, bonus_version)
			i += shards
	if _prof: _Opt.prof_add("!ВЕСЬ ТИК ЮНИТОВ", Time.get_ticks_usec() - _t0)
	# ── ПАКЕТНЫЙ ШАГ МАРША — ОДНИМ ПРОХОДОМ ПОСЛЕ ВСЕХ (см. ArmySoA.batch_move)
	# Бойцы в своём тике только ЗАЯВИЛИ желаемое смещение; здесь оно проводится
	# через всю геометрию шага. Стоит ДО разбора наложения и ПОСЛЕ обхода: сперва
	# все дошли, куда шли, и лишь потом расталкивание правит итог кадра — тот же
	# порядок, что был у поштучного пути
	if _prof: _t0 = Time.get_ticks_usec()
	_flush_poses()
	if _prof: _Opt.prof_add("pose_flush", Time.get_ticks_usec() - _t0)
	if _Opt.batch_move:
		if _prof: _t0 = Time.get_ticks_usec()
		army.batch_move_queued(_stq_row, _stq_x, _stq_z, _stq_fl,
			map_lim_x, map_lim_z, world_bounds_enabled, water_active,
			Unit.BLOCK_RADIUS, Unit.TRUNK_CLEARANCE, _relief_amp_now(), self)
		_stq_row.resize(0)
		_stq_x.resize(0)
		_stq_z.resize(0)
		_stq_fl.resize(0)
		if _prof: _Opt.prof_add("batch_move", Time.get_ticks_usec() - _t0)
	# ── РАЗБОР НАЛОЖЕНИЯ — ОДНИМ ПРОХОДОМ ПОСЛЕ ВСЕХ (см. ArmySoA) ──────────
	# ПОСЛЕ обхода: к этому моменту все, кто шёл, уже сдвинулись, и поправка
	# считается по итоговым точкам кадра, а не по смеси старых и новых.
	# Идёт КАЖДЫЙ кадр, а не через шард: разбор дешевле самого тика, а его
	# собственный такт задан таймером в столбце (SEP_INTERVAL)
	if _prof: _t0 = Time.get_ticks_usec()
	army.batch_separation(delta, Unit.SEP_MIN_DIST, Unit.SEP_MAX_STEP,
		Unit.SEP_INTERVAL, map_lim_x, map_lim_z,
		Unit.State.MOVING, Unit.State.ATTACKING, water_active, self,
		Unit.SEP_DEADZONE, _relief_amp_now(), Unit.SEP_CROSS_SQUAD,
		Unit.SEP_PASS_RELIEF)
	if _prof: _Opt.prof_add("sep_overlap", Time.get_ticks_usec() - _t0)
	if _meter: _Opt.tick_add(Time.get_ticks_usec() - _tm0)
	# Спящий (_proc_sleeping) дальний юнит не крутит свой _process и потому сам
	# не заметит, что камера подошла и он снова near_view — например, игрок
	# подводит камеру к стоящему на месте вражескому гарнизону. Реестр дальних
	# мал (только то, что сейчас в MultiMesh), обход раз в FAR_WAKE_CHECK_FRAMES
	# дешёвый и достаточно частый, чтобы не быть заметным
	if Engine.get_physics_frames() % FAR_WAKE_CHECK_FRAMES == 0:
		_wake_returned_far_units()
	# Развалившийся строй смыкается сам (см. _sweep_reform). Свой редкий такт,
	# к шардам отношения не имеет: отрядов десятки, а не тысячи
	_sweep_reform(delta)
	# Топот марширующих отрядов (см. _sweep_march_audio) — там же и по той же
	# причине: вопрос задаётся ОТРЯДУ, а не бойцу
	_sweep_march_audio(delta)
	# ── МЕТКИ ПОД НОГАМИ ЖИВУТ В ОТРИСОВОЧНОМ ТИКЕ, А НЕ ЗДЕСЬ ──────────────
	# Кольца, тени и полоски здоровья берут НАРИСОВАННУЮ точку бойца
	# (Unit.draw_position), а она пересчитывается в _process вместе с самим
	# спрайтом. Обновлять их в физическом тике значило бы брать позапрошлое
	# значение — и метка снова разъезжалась бы с картинкой, только уже на
	# другую долю шага. См. _process выше

const FAR_WAKE_CHECK_FRAMES := 15

# ═══════════════════════════════════════════════════════════════════════════
# ДВИЖЕНИЕ ОТРЯДА МАТРИЦЕЙ (Этап 1)
# ═══════════════════════════════════════════════════════════════════════════
# Отряд, идущий по чистому коридору, держит строй — то есть взаимное
# расположение его бойцов НЕ МЕНЯЕТСЯ. Считать каждому шаг заново незачем:
# двигается один якорь, а боец получает точку как «якорь плюс своё смещение,
# повёрнутое на курс» (см. ArmySoA.advance_matrix).
#
# УСЛОВИЯ ВХОДА проверяются каждый кадр и все сразу:
#   • коридор отряда чист И от стволов, И от чужих (это уже считается раз в
#     CORRIDOR_TTL_MS — см. _recalc_corridor, отдельной работы не добавляется);
#   • все живые в State.MOVING, ни у кого нет цели атаки;
#   • никто не отступает, не бежит и не выходит из боя;
#   • в отряде хватает народу (perf_config.squad_matrix_min).
# Достаточно одному условию отпасть — матрица снимается В ТОТ ЖЕ КАДР, и бойцы
# продолжают обычным путём: состояние, цель и приказ у них на месте, ничего
# восстанавливать не нужно.
#
# ПОЧЕМУ ЭТО НЕ МЕНЯЕТ ПОВЕДЕНИЯ. Отряд и раньше шёл строем: каждому выдавалась
# СВОЯ точка (слот), и он шёл в неё по прямой. Матрица делает ровно то же самое
# — просто считает это один раз на всех. Отличие ровно одно, и оно в плюс:
# строй перестал расползаться по дороге, потому что все идут синхронно.
#
# sid -> {rows, ox/oz (смещения), ax/az (якорь), dx/dz (цель), cx/cz (курс), speed}
var _matrix: Dictionary = {}

## ЗА СКОЛЬКО МЕТРОВ ДО ЦЕЛИ МАТРИЦА СНИМАЕТСЯ. Подход и постановка — самая
## тонкая часть марша: там работают расталкивание, прибытие и доворот, и там же
## отряд встречается с теми, кто уже стоит на месте. Матрица чужих не видит,
## поэтому последние метры отдаются обычному шагу; экономия от неё лежит в
## длинной части марша и от этого не страдает (обоснование — в _matrix_step)
const MATRIX_RELEASE_DIST := 3.0

## Амплитуда рельефа, снятая с Main один раз: внутри матричного шага высота
## считается по колонкам, без вызова наружу на каждого бойца
var _relief_amp: float = 0.0

## Доля сближения нарисованной точки с настоящей за один кадр отрисовки.
## Считает GameManager._process, читает Unit.tick_visual (см. там же)
var vis_lerp_k: float = 1.0
## Какую часть интервала между обновлениями бойца занимает догон. Меньше —
## резче и ближе к правде, больше — плавнее, но с заметным отставанием.
## 0.6 подобрано так, чтобы картинка успевала прийти к следующему шагу
const VIS_SMOOTH_TAU := 0.6

# ═══════════════════════════════════════════════════════════════════════════
# ОЧЕРЕДЬ ЗАЯВОК НА ШАГ
# ═══════════════════════════════════════════════════════════════════════════
# Боец не ходит за границу языков сам. Он кладёт свою заявку СЮДА — обычной
# записью в Packed-массивы автозагрузки, — а весь список уходит в солвер ОДНИМ
# вызовом после обхода армии.
#
# ЗАЧЕМ. Замер (qa_fx, 3000, фаза контакта): восемьсот заявок в кадр по одному
# переходу границы каждая, ~2.2 мкс за переход — полторы миллисекунды. При этом
# 93 % заявок приходят из ОДНОЙ ветки боя (подтягивание рядов), то есть это не
# разнородная работа, а один и тот же вызов, повторённый восемьсот раз.
#
# Массивы принадлежат GameManager, и пишет в них ЕГО ЖЕ метод — иначе запись
# через чужую ссылку скопировала бы весь Packed-массив на каждый элемент (та же
# ловушка, что описана у FarUnitRenderer.Bucket).
var _stq_row := PackedInt32Array()
var _stq_x := PackedFloat32Array()
var _stq_z := PackedFloat32Array()
var _stq_fl := PackedInt32Array()

## Подать заявку на шаг. Зовёт Unit._commit_step
func queue_step(row: int, sx: float, sz: float, fl: int) -> void:
	_stq_row.append(row)
	_stq_x.append(sx)
	_stq_z.append(sz)
	_stq_fl.append(fl)

## ── ОЧЕРЕДЬ ПОЗ ─────────────────────────────────────────────────────────────
## Ровно та же причина, что и у очереди шагов: запись позы шла отдельным
## переходом границы на каждого бойца (908 в кадр по 2.14 мкс — 1.9 мс).
## Пропуск неизменившихся поз тут не спасает: в контактном бою подтягиваются
## почти все, то есть поза меняется у всех
var _pq_row := PackedInt32Array()
var _pq_x := PackedFloat32Array()
var _pq_y := PackedFloat32Array()
var _pq_z := PackedFloat32Array()
var _pq_vx := PackedFloat32Array()
var _pq_vz := PackedFloat32Array()
var _pq_st := PackedInt32Array()
var _pq_gate := PackedInt32Array()
## Маска «нужен полный боевой автомат», по строке на бойца. Ноль — пакетный
## проход уже всё за него посчитал (см. ArmyCore.BatchCombat). Отдаётся ОДНИМ
## массивом за кадр: возврат списка объектов стоил дороже, чем экономил
var atk_need := PackedByteArray()
var _pq_eff := PackedFloat32Array()

func queue_pose(row: int, p: Vector3, v: Vector3, state: int,
		gates: int, eff_speed: float) -> void:
	_pq_row.append(row)
	_pq_x.append(p.x)
	_pq_y.append(p.y)
	_pq_z.append(p.z)
	_pq_vx.append(v.x)
	_pq_vz.append(v.z)
	_pq_st.append(state)
	_pq_gate.append(gates)
	_pq_eff.append(eff_speed)

## Отдать накопленные позы солверу. Зовётся ПОСЛЕ обхода армии и ДО пакетного
## шага: иначе позы «на начало кадра» затёрли бы уже посчитанное перемещение
func _flush_poses() -> void:
	if _pq_row.is_empty():
		return
	army.write_pose_batch(_pq_row, _pq_x, _pq_y, _pq_z, _pq_vx, _pq_vz, _pq_st,
		_pq_gate, _pq_eff)
	_pq_row.resize(0)
	_pq_gate.resize(0)
	_pq_eff.resize(0)
	_pq_x.resize(0)
	_pq_y.resize(0)
	_pq_z.resize(0)
	_pq_vx.resize(0)
	_pq_vz.resize(0)
	_pq_st.resize(0)

## Амплитуда рельефа для пакетных проходов. Ноль честно означает и «рельеф
## выключен» — тогда высота везде нулевая, и пересчитывать нечего
func _relief_amp_now() -> float:
	if _relief_amp == 0.0 and main != null:
		_relief_amp = main.RELIEF_AMP if main.TERRAIN_RELIEF else 0.0
	return _relief_amp

func _advance_matrices(delta: float) -> void:
	if not _Opt.squad_matrix or squads.is_empty():
		return
	if _relief_amp == 0.0 and main != null:
		# Ноль здесь честно означает и «рельеф выключен» — тогда пересчёт
		# ничего не стоит и повторная проверка безвредна
		_relief_amp = main.RELIEF_AMP if main.TERRAIN_RELIEF else 0.0
	var min_n: int = _Opt.squad_matrix_min
	for sid in squads:
		var s: int = int(sid)
		var mx: Variant = _matrix.get(s)
		if not _matrix_allowed(s, min_n):
			if mx != null:
				_matrix_release(s)
			continue
		if mx == null:
			mx = _matrix_engage(s)
			if mx == null:
				continue
		_matrix_step(s, mx as Dictionary, delta)

## Годится ли отряд для матрицы прямо сейчас
func _matrix_allowed(sid: int, min_n: int) -> bool:
	var sq: Variant = squads.get(sid)
	if sq == null:
		return false
	# Ответ коридора — тот самый «путь свободен» на уровне отряда
	var row: Variant = _corridors.get(sid)
	if row == null:
		return false
	var r: Array = row
	if not bool(r[1]) or not bool(r[2]):
		return false
	var members: Array = (sq as Dictionary)["members"]
	if members.size() < min_n:
		return false
	var moving := 0
	for m in members:
		# ПРОВЕРКА ЖИВОСТИ ИДЁТ ДО ПРИВЕДЕНИЯ. `m as Unit` на уже освобождённом
		# объекте не даёт null, а бросает «Trying to cast a freed object» — то
		# есть порядок «привести, потом проверить» ловит не всё и печатает
		# ошибку. Обычная смерть чистит состав через remove_from_squad, но
		# queue_free мимо неё (стенды, снос сцены) оставляет в списке мусор
		if not is_instance_valid(m):
			return false
		var u := m as Unit
		if u == null:
			return false
		if u.state == Unit.State.DEAD:
			continue
		# Любой, кто вышел из простого марша, отменяет матрицу для всего отряда
		if u.state != Unit.State.MOVING or u.attack_target != null \
				or u.retreating or u.sprinting or u.garrisoned:
			return false
		if u._soa < 0:
			return false
		moving += 1
	return moving >= min_n

## Собрать матрицу: снять смещения из уже выданных бойцам точек
func _matrix_engage(sid: int):
	var members: Array = (squads[sid] as Dictionary)["members"]
	var rows := PackedInt32Array()
	var live: Array = []
	var mpx: PackedFloat32Array = army.px
	var mpz: PackedFloat32Array = army.pz
	var ax := 0.0
	var az := 0.0
	var dx := 0.0
	var dz := 0.0
	var speed := INF
	for m in members:
		if not is_instance_valid(m):        # см. _matrix_allowed: проверка до приведения
			continue
		var u := m as Unit
		if u == null or u.state != Unit.State.MOVING:
			continue
		var i: int = u._soa
		rows.append(i)
		live.append(u)
		ax += mpx[i]
		az += mpz[i]
		dx += u.move_target.x
		dz += u.move_target.z
		# Отряд идёт со скоростью самого медленного — иначе строй растянется
		var sp: float = u._effective_speed()
		if sp < speed:
			speed = sp
	var n: int = rows.size()
	if n <= 0 or speed <= 0.0 or speed == INF:
		return null
	var inv: float = 1.0 / float(n)
	ax *= inv; az *= inv; dx *= inv; dz *= inv
	var vx: float = dx - ax
	var vz: float = dz - az
	var dist: float = sqrt(vx * vx + vz * vz)
	if dist < 0.05:
		return null                     # уже пришли — матрица не нужна
	var cx: float = vx / dist
	var cz: float = vz / dist
	# Смещения снимаются от ЦЕЛИ, а не от текущей точки: строй, который отряд
	# должен принять, задан именно слотами
	var rxv: float = cz
	var rzv: float = -cx
	for k in range(n):
		var u: Unit = live[k]
		var wx: float = u.move_target.x - dx
		var wz: float = u.move_target.z - dz
		# Мировое смещение в локальную систему строя (обратный поворот)
		army.set_slot(rows[k], wx * rxv + wz * rzv, wx * cx + wz * cz)
		u._matrix_driven = true
		# Скорость нужна походке: спрайт по ней выбирает walk/idle
		u.velocity = Vector3(cx * speed, 0.0, cz * speed)
		u._facing = Vector3(cx, 0.0, cz)
	var mx := {
		"rows": rows, "live": live,
		"ax": ax, "az": az, "dx": dx, "dz": dz,
		"cx": cx, "cz": cz, "speed": speed,
	}
	_matrix[sid] = mx
	return mx

## Один шаг якоря. Пришли — распускаем матрицу и доводим бойцов штатным путём
func _matrix_step(sid: int, mx: Dictionary, delta: float) -> void:
	var ax: float = mx["ax"]
	var az: float = mx["az"]
	var dx: float = mx["dx"]
	var dz: float = mx["dz"]
	var vx: float = dx - ax
	var vz: float = dz - az
	var dist: float = sqrt(vx * vx + vz * vz)
	var step: float = float(mx["speed"]) * delta
	if dist <= maxf(step, MATRIX_RELEASE_DIST):
		# ПОСЛЕДНИЕ МЕТРЫ ОТРЯД ПРОХОДИТ ПОШТУЧНО — и это не небрежность, а
		# замер. Матрица ведёт отряд жёстким блоком и чужих не видит: если в ту
		# же точку идут ещё несколько отрядов, все они ложатся ровно на свои
		# слоты друг сквозь друга, и разгребать получившуюся кучу приходится
		# расталкиванию уже на месте. qa_settle E2 (шесть отрядов по 40 человек
		# в ОДНУ точку) показал это в чистом виде: 0.0044 м дрожания без
		# матрицы против 0.094 м с ней. Попытка «доводить до самых слотов»
		# сделала хуже — 0.122 м, потому что лечила не ту причину.
		# Отпуская отряд за MATRIX_RELEASE_DIST до цели, мы отдаём подход
		# обычному шагу, где работают и расталкивание, и прибытие, а матрица
		# оставляет себе длинную часть марша — там и лежит вся её экономия
		_matrix_release(sid)
		return
	var inv: float = 1.0 / dist
	mx["ax"] = ax + vx * inv * step
	mx["az"] = az + vz * inv * step
	var rows: PackedInt32Array = mx["rows"]
	# Высота считается ПОУНИТНО внутри advance_matrix по амплитуде рельефа:
	# одна высота на весь отряд вешала фланги над травой (см. там же)
	army.advance_matrix(rows, mx["ax"], mx["az"], 0.0, mx["cx"], mx["cz"],
		_relief_amp)
	army.push_to_nodes(rows)

## Снять матрицу: бойцы возвращаются к своему шагу
func _matrix_release(sid: int) -> void:
	var mx: Variant = _matrix.get(sid)
	if mx == null:
		return
	for u in (mx as Dictionary)["live"]:
		var un := u as Unit
		if un != null and is_instance_valid(un):
			un._matrix_driven = false
	_matrix.erase(sid)

## Матрица снимается и извне: приказ, гибель, расформирование
func matrix_invalidate(sid: int) -> void:
	if sid > 0:
		_matrix_release(sid)

## Сколько отрядов сейчас идёт матрицей (стенды и отладка)
func matrix_squads() -> int:
	return _matrix.size()

# ─────────────────────────────────────────────────────────────────────────────
# КОРИДОР ОТРЯДА — БАТЧЕВАЯ ПРОВЕРКА ПОМЕХ НА МАРШЕ
#
# Шаг бойца (Unit._move_blocked) обязан ответить на два вопроса: «есть ли рядом
# ствол дерева» и «есть ли рядом чужой строй». Оба ответа стоили по вызову
# наружу НА КАЖДОГО ИДУЩЕГО В КАЖДОМ КАДРЕ — в профиле марша это mb_trunk 2.4
# мкс и mb_enemyblock 2.1-4.0 мкс на бойца, то есть больше трети всего шага.
# При этом отряд из полусотни человек идёт ПЛОТНОЙ КУЧКОЙ: ответы у всех его
# бойцов одинаковые, и пятьдесят раз в кадр спрашивалось одно и то же.
#
# Теперь вопрос задаётся ОДИН РАЗ НА ОТРЯД по его габаритной окружности, а
# ответ РАЗДАЁТСЯ бойцам полями (Unit._clear_trunk / _clear_enemy) — тем же
# приёмом, что и подтягивание хвоста (_push_catch_up). Пустой коридор = боец
# не делает ни одного вызова наружу за весь шаг: только арифметика и запись
# координаты.
#
# ЗАПАС ОБЯЗАТЕЛЕН И СЧИТАЕТСЯ ЧЕСТНО. За время жизни ответа отряд успевает
# пройти speed×TTL, а встречный враг — столько же навстречу. Радиус проверки
# расширен на CORRIDOR_MARGIN, чего с запасом хватает на обе скорости плюс
# радиус блокировки: при TTL 0.2 с и скорости 4 м/с сближение не превышает
# 1.6 м. Ошибка «сказали чисто, а там враг» означала бы проход сквозь строй,
# поэтому запас взят кратным, а не впритык.
# ─────────────────────────────────────────────────────────────────────────────
const CORRIDOR_TTL_MS := 200
const CORRIDOR_MARGIN := 8.0

## ── СРОКИ ЖИЗНИ КОРИДОРОВ РАЗВОДЯТСЯ ПО ФАЗЕ ────────────────────────────────
## Замер на 15000 (профиль марша): ветка squad_corridor — 11.9% всего тика при
## 12.0 мс НА ВЫЗОВ. Столько она стоить не может: пересчёт одного отряда — это
## полсотни чтений позиции плюс два запроса к сеткам.
##
## Причина не в цене пересчёта, а в СИНХРОННОСТИ. Отряды рождаются пачкой (бой
## начинается с найма, стенд ставит армию одним кадром), корид оры им заводятся
## в один и тот же миллисекунд, и дальше все триста истекают НА ОДНОМ И ТОМ ЖЕ
## кадре — раз в двенадцать кадров вся работа за эти двенадцать кадров
## сваливается в один. Среднее в 12 мс — это и есть размазанный пик в ~144 мс.
##
## Лечится фазой, а не бюджетом: ПЕРВЫЙ срок отряда берётся случайным в
## пределах [TTL/2, TTL], дальше идёт обычный TTL. Фазы разъезжаются один раз
## и держатся сами; пересчёты равномерно размазаны по кадрам навсегда.
## Первый срок только УКОРАЧИВАЕТСЯ — запас CORRIDOR_MARGIN от этого не тратится.
##
## Бюджет на кадр оставлен вторым рубежом на случай, который фаза не покрывает
## (одновременное рождение сотен отрядов в одном кадре). Отложенный отряд
## доживает несколько лишних кадров на прошлом ответе: при 64 отрядах на кадр
## и трёхстах отрядах задержка не превышает 4 кадров (67 мс), то есть сближение
## не более 0.5 м при запасе в 8 м
const CORRIDOR_BUDGET := 64

## sid -> [время истечения, чисто от стволов, чисто от врагов]
var _corridors: Dictionary = {}

func _sweep_corridors() -> void:
	if squads.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var left: int = CORRIDOR_BUDGET
	# `for sid in squads`, а НЕ `squads.keys()`: keys() копирует весь список
	# ключей в новый Array на каждом кадре — на сотне отрядов это сотня
	# аллокаций в кадр ради обхода, который словарь умеет делать сам.
	# _recalc_corridor трогает только _corridors, сам squads не меняет,
	# поэтому обход по живому словарю здесь безопасен
	for sid in squads:
		var row: Variant = _corridors.get(sid)
		if row != null and now < int((row as Array)[0]):
			continue
		_recalc_corridor(int(sid), now)
		left -= 1
		if left <= 0:
			return

func _recalc_corridor(sid: int, now: int) -> void:
	var sq: Variant = squads.get(sid)
	if sq == null:
		_corridors.erase(sid)
		return
	var members: Array = (sq as Dictionary)["members"]
	# Габариты отряда: центр и самый дальний от него боец. Считаем по
	# фактическим позициям, а не по слотам приказа: отряд может растянуться на
	# марше, и коридор обязан накрывать его целиком.
	#
	# ── ВЕСЬ ОБХОД БОЙЦОВ ЖИВЁТ В ЯДРЕ АРМИИ (ArmySoA.harvest_squad) ────────
	# Он же по дороге кладёт снятые точки в строки, поэтому кто угодно (центры
	# масс, звёзды отрядов, пакетный бой Фазы 3) читает их дальше без единого
	# обращения к узлам. Пересчёт идёт раз в CORRIDOR_TTL_MS на отряд, так что
	# это НЕ покадровая работа: обход бойцов здесь был и до ядра армии.
	#
	# Почему цикл переехал внутрь модуля, а не остался тут: записи в
	# Packed-массивы обязаны идти у владельца (снаружи это копирование всего
	# массива), а константы чужих скриптов в цикле по бойцам — поиск по скрипту
	# на каждого. Обе ловушки в этом проекте уже оплачены однажды.
	#
	# ДАЛЬНОСТЬ ВНИМАНИЯ ОТРЯДА (watch). Ответ «чужих рядом нет» отменяет НЕ
	# ТОЛЬКО блокировку строем (BLOCK_RADIUS, меньше метра), но и оба скана
	# врага — перехват марша и авто-агро. У лучника они смотрят на 20 м,
	# поэтому радиус проверки обязан накрывать самый дальнозоркий взгляд в
	# отряде, иначе отряд «ослепнет» ровно там, где раньше стрелял
	# ── СОСТАВ СОБИРАЕТСЯ ЗДЕСЬ, ГАБАРИТЫ СЧИТАЕТ СОЛВЕР ────────────────────
	# Список живых нужен тут же (_push_corridor раздаёт им ответы), а чтение
	# полей своего же объекта в GDScript стоит копейки. Через границу языков,
	# наоборот, каждое такое чтение — обращение через Variant, и прежний
	# harvest_squad, читавший у каждого бойца три свойства, стоил впятеро
	# дороже всего остального коридора. Границу теперь пересекает ОДИН вызов на
	# отряд, а точки солвер берёт из своих же колонок — их ведёт пакетный шаг
	# ── ПОДВЕТКИ ЗАМЕРЯЮТСЯ ПОРОЗНЬ ────────────────────────────────────────
	# Ветка squad_corridor стоила 0.75 мс кадра одним куском, и по этому числу
	# нельзя было понять, что именно в ней дорого: обход состава, габариты в
	# солвере, поиск стволов, поиск чужих или раздача ответа. Пять пар
	# get_ticks_usec на ОТРЯД (а не на бойца) — это доли процента от самой ветки
	var _cp: bool = _Opt.profile_physics
	var _ct: int
	if _cp: _ct = Time.get_ticks_usec()
	# ── СПИСОК ЖИВЫХ ПЕРЕИСПОЛЬЗУЕТСЯ, А НЕ СОБИРАЕТСЯ ЗАНОВО ──────────────
	# Два массива на отряд каждые 200 мс — это две аллокации и обход состава;
	# замер (qa_fps, 4000 юнитов) дал 29 мкс на отряд, 0.33 мс кадра только на
	# сборку. Массивы держатся при отряде и ЧИСТЯТСЯ, а не создаются: у
	# Array.clear() ёмкость сохраняется, то есть повторная сборка идёт без
	# выделения памяти. Валидность при этом проверяется КАЖДЫЙ раз, как и
	# раньше, — кэшируется контейнер, а не его содержимое
	var live: Array = sq.get("live_cache", [])
	var rows: PackedInt32Array = sq.get("rows_cache", PackedInt32Array())
	live.clear()
	rows.clear()
	var dead_st: int = Unit.State.DEAD
	for m in members:
		if not is_instance_valid(m):
			continue
		var mu := m as Unit
		if mu == null or mu.state == dead_st or mu._soa < 0:
			continue
		live.append(mu)
		rows.append(mu._soa)
	(sq as Dictionary)["live_cache"] = live
	(sq as Dictionary)["rows_cache"] = rows
	if _cp: _Opt.prof_add("cor_harvest", Time.get_ticks_usec() - _ct)
	if _cp: _ct = Time.get_ticks_usec()
	var box: Array = army.squad_bounds(rows,
		dead_st, Unit.AGGRO_RADIUS, Unit.INTERCEPT_MARGIN)
	if _cp: _Opt.prof_add("cor_bounds", Time.get_ticks_usec() - _ct)
	var n: int = box[0]
	if n == 0:
		_corridors.erase(sid)
		return
	var cx: float = box[1]
	var cz: float = box[2]
	var watch: float = box[4]
	var fac: int = box[5]
	var radius: float = float(box[3]) + CORRIDOR_MARGIN
	# Стволы мешают только телу бойца — их достаточно искать по габаритам;
	# чужих ищем на всю дальность внимания отряда.
	if _cp: _ct = Time.get_ticks_usec()
	var clear_trunk: bool = not trunk_near(cx, cz, radius)
	if _cp: _Opt.prof_add("cor_trunk", Time.get_ticks_usec() - _ct)
	if _cp: _ct = Time.get_ticks_usec()
	var clear_enemy: bool = not unit_grid.enemy_near(
		Vector3(cx, 0.0, cz), fac, radius + watch)
	if _cp: _Opt.prof_add("cor_enemy", Time.get_ticks_usec() - _ct)
	# ПЕРВЫЙ СРОК — УКОРОЧЕННЫЙ И СВОЙ У КАЖДОГО ОТРЯДА (см. шапку выше про
	# синхронность). Дальше отряд живёт обычным TTL, и разведённые фазы держатся
	# сами. Смещение берётся ОТ НОМЕРА ОТРЯДА, а не случайным: одинаковый прогон
	# стенда обязан давать одинаковые числа
	# Разброс берётся на ВЕСЬ TTL, а не на его половину: половина покрывает лишь
	# шесть кадров из двенадцати, и триста отрядов всё равно ложились по полсотни
	# на кадр (замер: ветка squad_corridor осталась 4.9% при 5.0 мс на вызов).
	# На полном окне те же триста расходятся по двадцать пять на кадр
	var ttl: int = CORRIDOR_TTL_MS
	if not _corridors.has(sid):
		ttl = 1 + (sid * 37) % CORRIDOR_TTL_MS
	_corridors[sid] = [now + ttl, clear_trunk, clear_enemy]
	if _cp: _ct = Time.get_ticks_usec()
	_push_corridor(live, clear_trunk, clear_enemy)
	if _cp: _Opt.prof_add("cor_push", Time.get_ticks_usec() - _ct)
	# ── РЯДЫ ФАЛАНГИ СЧИТАЮТСЯ ЗДЕСЬ ЖЕ, ОДНИМ ВЫЗОВОМ НА ОТРЯД ────────────
	# Состав и строки уже собраны выше — ровно то, что нужно SquadRanks, и
	# ни одной лишней итерации. Персональный allies_ahead стоил 0.96 мс кадра
	# на четырёх тысячах (112 вызовов по 8.6 мкс), причём дорога была не
	# работа, а путь наружу: два прыжка по GDScript и переход границы НА
	# КАЖДОГО бойца. Такт совпадает: коридор пересчитывается раз в 200 мс,
	# ряд требовался раз в 250 мс (Unit.RANK_RECHECK)
	if _cp: _ct = Time.get_ticks_usec()
	_push_squad_ranks(sid, live, dead_st)
	if _cp: _Opt.prof_add("cor_ranks", Time.get_ticks_usec() - _ct)
	# СПЛОЧЁННОСТЬ: габарит отряда солвер уже посчитал (box[3] — самый дальний
	# от центра), поэтому в обычном случае это ОДНО СРАВНЕНИЕ и ни одного
	# лишнего обхода бойцов
	if _cp: _ct = Time.get_ticks_usec()
	# ЦЕНТР ОТРЯДА КЛАДЁТСЯ В КЭШ. Он уже посчитан солвером, и бойцу он нужен,
	# чтобы не убегать за целью из зоны своего отряда (см. Unit.squad_zone_far).
	# Считать его на бойца означало бы обход состава на каждого
	_squad_centre[sid] = Vector2(cx, cz)
	if float(box[3]) > _cohesion_limit(sid):
		_cohesion_guard(sid, live, cx, cz, now)
	if _cp: _Opt.prof_add("cor_cohesion", Time.get_ticks_usec() - _ct)

## ── РЯД КАЖДОГО БОЙЦА ФАЛАНГИ — ОДНИМ СКАНОМ НА ОТРЯД ──────────────────────
## Шеренга обязана смотреть в одну сторону (см. Unit._phalanx_dir), поэтому
## направление одно на всех, а строки уходят в солвер пачкой.
##
## КТО ВЫПАДАЕТ ИЗ ПАЧКИ. Только тот, у кого собственное направление разошлось
## с общим больше чем на несколько градусов: у него нет курса отряда и он
## смотрит на своего врага. Такой боец считает ряд сам, прежним путём — веток
## поведения не прибавилось, прибавилась только пачка для общего случая
func _push_squad_ranks(sid: int, live: Array, dead_st: int) -> void:
	if live.is_empty():
		return
	# ── НАПРАВЛЕНИЕ СНИМАЕТСЯ ОДИН РАЗ НА ОТРЯД, А НЕ У КАЖДОГО БОЙЦА ──────
	# Первая версия спрашивала _phalanx_dir() у каждого члена (и дважды: в
	# поиске ведущего и в фильтре) — а он ходит в этот же автозагрузочный
	# словарь. Полторы сотни межобъектных обращений на отряд съели весь
	# выигрыш и сверх того: замер показал 107 мкс на отряд и ветку
	# squad_corridor 0.78 → 2.19 мс. Здесь те же два обращения, но на ВЕСЬ
	# отряд, и порядок источников тот же, что у Unit._phalanx_dir
	var dir: Vector3 = squad_enemy_dir(sid)
	if not (dir.length_squared() > 1e-6 and squad_in_combat(sid)):
		var course: Vector3 = squad_course(sid)
		if course.length_squared() > 1e-6:
			dir = course
	if dir.length_squared() < 1e-6:
		# У отряда нет ни курса, ни общего врага: у каждого бойца своё
		# направление, и пачкой их не посчитать. Считают сами, прежним путём
		return
	var sub := PackedInt32Array()
	var subu: Array = []
	for m in live:
		var u2: Unit = m
		if u2.state == dead_st or u2._soa < 0 or not u2._stance_holds_ground():
			continue
		sub.append(u2._soa)
		subu.append(u2)
	if sub.is_empty():
		return
	var ranks: PackedInt32Array = unit_grid.squad_ranks(sub, dir,
		Unit.FILE_LOOK_AHEAD, Unit.FILE_HALF_WIDTH)
	if ranks.size() != subu.size():
		return
	for i in range(subu.size()):
		var u3: Unit = subu[i]
		u3._live_rank = ranks[i]
		u3._rank_fresh = true

## ── ЖЁСТКАЯ СПЛОЧЁННОСТЬ ОТРЯДА ─────────────────────────────────────────────
##
## ЗАЧЕМ. Отряд рассыпался на изолированные кучки и больше никогда не собирался:
## смыкание рядов (squad_close_ranks) отказывается работать, пока отряд в бою,
## а «в бою» — это состояние ОТРЯДА, и пока хоть один боец рубится, отставшие на
## другом конце поля стоят вечно. На скриншотах владельца это два-три мечника
## поодиночке в чистом поле и звезда отряда между ними.
##
## КАК. Это НЕ сила и не поле — это разовый ПРИКАЗ на возврат, редкий и с
## остыванием, ровно в том же ключе, что и смыкание рядов. Отряд подзывает
## только тех, кто (а) действительно оторвался, (б) ничем не занят: не дерётся,
## не бежит, не отходит, не выполняет приказ игрока (замок цели) и не работает.
## Занятого бойца не трогаем — иначе приказ на возврат отменил бы его бой и
## получилась бы та самая «пляска», от которой лечит squad_in_combat.
##
## Цена: обход состава раз в SQUAD_COHESION_COOLDOWN_MS на отряд И ТОЛЬКО ЕСЛИ
## отряд действительно растянут сверх нормы.
## ПРЕДЕЛ РАЗЛЁТА ДЛЯ ЭТОГО ОТРЯДА. Базовое число из конфига — но если игрок
## сам растянул отряд в длинную шеренгу (ПКМ с протяжкой), его собственная
## разметка шире, и подзывать по базовому числу означало бы ломать заказанное
## им построение каждые две с половиной секунды. Берём наибольшее из двух
func _cohesion_limit(sid: int) -> float:
	var base: float = _UCfg.SQUAD_COHESION_DIST
	var sq: Variant = squads.get(sid)
	if sq == null:
		return base
	var slots: Array = (sq as Dictionary).get("slots", [])
	if slots.is_empty():
		return base
	var ax := 0.0
	var az := 0.0
	for sl in slots:
		var v: Vector3 = sl
		ax += v.x
		az += v.z
	ax /= float(slots.size())
	az /= float(slots.size())
	var r2 := 0.0
	for sl in slots:
		var v2: Vector3 = sl
		var d2: float = (v2.x - ax) * (v2.x - ax) + (v2.z - az) * (v2.z - az)
		if d2 > r2:
			r2 = d2
	# Запас: боец, идущий на свой слот, ещё не дошёл до него
	return maxf(base, sqrt(r2) + CORRIDOR_MARGIN)

func _cohesion_guard(sid: int, live: Array, cx: float, cz: float, now: int) -> void:
	if int(_cohesion_last.get(sid, 0)) > now:
		return
	_cohesion_last[sid] = now + _UCfg.SQUAD_COHESION_COOLDOWN_MS
	var lim: float = _cohesion_limit(sid)
	var lim2: float = lim * lim
	var idle_st: int = Unit.State.IDLE
	var called := 0
	for m in live:
		var u := m as Unit
		if u == null:
			continue
		# ── ПРИКАЗ ИГРОКА И ОТХОД НЕПРИКОСНОВЕННЫ ──────────────────────────
		if u.target_lock or u.retreating or u.garrisoned:
			continue
		# ── ДЕРУЩЕГОСЯ ВДАЛИ ОТ СВОИХ — ЗОВЁМ ОБРАТНО ──────────────────────
		# Прежде здесь стоял ранний выход по «занят»: не в покое или есть цель —
		# не трогаем. Из-за него отряд и растягивался «колбасой»: боец, за
		# которым авто-агро увело цель, дрался в двадцати метрах от своих и под
		# правило не подпадал ВООБЩЕ. Замер qa_mass_siege: восемь из 426 живых
		# оказывались дальше двенадцати метров от медианы своего отряда, и
		# именно они рисуют на экране растянутый отряд.
		#
		# Теперь «занят» спасает только того, кто занят В ЗОНЕ ОТРЯДА. Ушедший
		# за её пределы по СВОЕЙ инициативе цель бросает и возвращается — врага
		# он найдёт и рядом со своими (авто-агро работает и там), а вот отряд
		# без него разваливается
		var busy_here: bool = u.state == idle_st \
			and u.attack_target == null and not u.sprinting
		var dx: float = u.position.x - cx if u._local_xform else u.global_position.x - cx
		var dz: float = u.position.z - cz if u._local_xform else u.global_position.z - cz
		if dx * dx + dz * dz <= lim2:
			continue
		if not busy_here:
			# Вне зоны и при этом занят: снимаем цель — она увела его от своих
			u.set_attack_target(null)
		# Возврат к своим — обычный приказ на движение. Точка берётся с отступом
		# внутрь: приказ ровно в центр собрал бы отставших в одну точку
		var d: float = sqrt(dx * dx + dz * dz)
		var back: float = maxf(d - lim * 0.5, 0.0)
		var tx: float = u.global_position.x - dx / d * back
		var tz: float = u.global_position.z - dz / d * back
		u.command_move(Vector3(tx, get_terrain_height(tx, tz), tz))
		called += 1
	if called == 0:
		# Никого звать не пришлось — снимаем остывание, чтобы следующая проверка
		# не откладывалась на пустом месте
		_cohesion_last.erase(sid)

## Когда отряду снова разрешено подзывать отставших (sid -> ticks_msec)
var _cohesion_last: Dictionary = {}

## ── ЗОНА ОТРЯДА ────────────────────────────────────────────────────────────
## Центр отряда, снятый солвером в такте коридора (sid -> Vector2 xz).
## Лежит ГОТОВЫМ ЧИСЛОМ, потому что его читают БОЙЦЫ: считать центр поштучно
## означало бы обход состава на каждого, а он уже посчитан один раз на отряд
var _squad_centre: Dictionary = {}

## Центр отряда для бойца. Vector2.INF — отряда нет или центр ещё не считался
func squad_centre_xz(sid: int) -> Vector2:
	if sid <= 0:
		return Vector2.INF
	var c = _squad_centre.get(sid)
	return c if c != null else Vector2.INF

## Насколько далеко от своих боец вправе уйти ПО СОБСТВЕННОЙ ИНИЦИАТИВЕ.
## То же число, что и у сплочённости: два правила про одно и то же расстояние
## обязаны кончаться вместе
func squad_zone_radius(sid: int) -> float:
	return _cohesion_limit(sid)

## ── СЕКТОР ОТРЯДА У АТАКУЕМОГО ЗДАНИЯ ──────────────────────────────────────
## Точка на кольце вокруг постройки, доставшаяся этому отряду при выдаче приказа
## (см. SelectionManager._ring_squads_around). Читается ПОДХОДОМ бойца, поэтому
## лежит готовым числом
var _squad_atk_anchor: Dictionary = {}

func squad_set_attack_anchor(sid: int, at: Vector3) -> void:
	if sid > 0:
		_squad_atk_anchor[sid] = at

func squad_attack_anchor(sid: int) -> Vector3:
	var a = _squad_atk_anchor.get(sid)
	return a if a != null else Vector3.INF

func squad_clear_attack_anchor(sid: int) -> void:
	_squad_atk_anchor.erase(sid)

## `members` здесь — уже отобранные живые бойцы (см. _recalc_corridor):
## повторно проверять ссылку не нужно, между двумя строками никто не умирает
func _push_corridor(members: Array, clear_trunk: bool, clear_enemy: bool) -> void:
	for u in members:
		u._clear_trunk = clear_trunk
		u._clear_enemy = clear_enemy

# ─────────────────────────────────────────────────────────────────────────────
# ЛИНИЯ СОПРИКОСНОВЕНИЯ: КТО ДЕРЁТСЯ, А КТО ЖДЁТ ОЧЕРЕДИ
#
# ЗАЧЕМ. Замер qa_mass_battle (затяжной бой, приказ атаки): на 5000 бойцов до
# цели ДОСТАЮТ оружием 35 %, на 15000 — 52 %. Остальные каждый тик считали
# полный шаг к цели, а бить им некого: впереди спины своих. В долях кадра это
# mb_enemyblock 19 %, mb_trunk 10 %, mb_commit 7 % и ещё около 42 % — сама
# логика подхода. Настоящий бой (поиск цели, удар, урон) занимает 8 %.
#
# КАК. Разметка живёт ВНУТРИ бухгалтерии боя (_recalc_melee -> _assign_rear):
# тот же самый проход по составу, который определяет противника и считает
# занятых, заодно режет отряд на колонны и раздаёт дешёвый шаг. Отдельный обход
# со своим сроком был здесь раньше и не давал ничего, кроме второго прохода по
# тем же бойцам.
#
# ЭТО ЖЕ ЗАКРЫВАЕТ ВТОРУЮ ЗАДАЧУ — РЯД БЕЗ СКАНА. Раньше ряд считал
# Unit._update_live_rank() через SpatialGrid.allies_ahead, то есть скан соседей
# на бойца. Теперь ряд — порядковый номер в своей колонне, посчитанный внутри
# уже существующего прохода по составу.
#
# ЧЕГО ЗДЕСЬ НЕТ НАМЕРЕННО: списка «кто с кем дерётся». Назначение дуэлей сверху
# целится в те самые 8 %, и замер говорит, что кадра оно не вернёт. Это работа
# про поведение боя, и делать её надо отдельно и не ради FPS.
# ─────────────────────────────────────────────────────────────────────────────

func _clear_battle_line(members: Array) -> void:
	for m in members:
		if not is_instance_valid(m):
			continue
		var u := m as Unit
		if u != null:
			u._rear_line = false
			u._line_valid = false

# ─────────────────────────────────────────────────────────────────────────────
# БУХГАЛТЕРИЯ БОЯ НА УРОВНЕ ОТРЯДА (Этап 2, слой B)
#
# ЗАЧЕМ ОНА, ЕСЛИ КАДРА ОНА НЕ ВЕРНЁТ. Замер (qa_mass_battle с настоящим
# приказом атаки) прямо говорит: поиск целей — 4.7 % кадра, урон — 0.9 %. Здесь
# нет денег, и обещать их нечестно. Но слой A (тыл на дешёвом шаге) сломался
# ровно потому, что у отряда НЕТ УЧЁТА: боец, выпавший из боевого автомата,
# оказывался никому не подотчётен и не мог ни сменить цель, ни выйти из боя
# (qa_disengage 4 из 11). Учёт — это то, что делает слой A возможным вообще.
#
# ЧТО В ПРОЕКТЕ УЖЕ БЫЛО, И ЧЕГО НЕ ХВАТАЛО. Счётчик целящихся (Unit.attackers),
# выбор наименее атакованного из чужого отряда (squad_pick_member) и замок
# приказа игрока на ВРАЖЕСКИЙ ОТРЯД (Unit._lock_squad) существуют давно. Не
# хватало одного: связки «мой отряд дерётся вот с тем отрядом» ВНЕ приказа
# игрока. Без неё боец, потерявший цель, шёл искать новую сканом местности —
# каждый сам за себя, и отряд растекался.
#
# ГРАНИЦА ОТВЕТСТВЕННОСТИ. Приказ игрока (target_lock) ВЫШЕ этой бухгалтерии и
# не может быть ею перебит — иерархия приоритетов остаётся ровно та, что описана
# в шапке про Unit.target_lock. Отряд подсказывает цель только тому, у кого
# своего приказа нет.
# ─────────────────────────────────────────────────────────────────────────────

## Как часто отряд пересматривает, с кем он дерётся. Чаще коридора и реже
## разметки линии: смена противника — событие редкое, а вот состав живых у него
## меняется постоянно
## Замер: при 200 мс на две армии по сотне отрядов выходило 22.5 пересчёта в
## кадр по 81 мкс каждый — 1.8 мс кадра на одну только бухгалтерию. Противник у
## отряда меняется куда реже, чем дважды в секунду, так что срок вдвое длиннее
## ничего не теряет, а цену делит пополам
const MELEE_TTL_MS := 400

## sid -> {"t": срок, "foe": номер вражеского отряда, "engaged": в контакте,
##         "free": сколько своих без досягаемой цели}
var _melee: Dictionary = {}

func _sweep_melee() -> void:
	if not _Opt.squad_melee or squads.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var left: int = CORRIDOR_BUDGET
	for sid in squads:
		var row: Variant = _melee.get(sid)
		if row != null and now < int((row as Dictionary)["t"]):
			continue
		_recalc_melee(int(sid), now)
		left -= 1
		if left <= 0:
			return

func _recalc_melee(sid: int, now: int) -> void:
	# Счётчик melee_calc считает ПЕРЕСЧЁТЫ, а не кадры: по нему видно, работает
	# ли троттлинг. Общая ветка squad_melee этого не показывает — она меряет
	# время, а не число отрядов, и «дорого» может значить и «часто», и «долго»
	var _p: bool = _Opt.profile_physics
	var _t: int = Time.get_ticks_usec() if _p else 0
	var sq: Variant = squads.get(sid)
	if sq == null:
		_melee.erase(sid)
		if _p: _Opt.prof_add("melee_calc", Time.get_ticks_usec() - _t)
		return
	var ttl: int = MELEE_TTL_MS
	if not _melee.has(sid):
		ttl = 1 + (sid * 41) % MELEE_TTL_MS
	# ПРОТИВНИК ОПРЕДЕЛЯЕТСЯ БОЛЬШИНСТВОМ, А НЕ ПЕРВЫМ ВСТРЕЧНЫМ. Один боец мог
	# отвлечься на случайного соседа; отряд дерётся с тем, с кем дерётся его
	# основная масса, иначе связка прыгала бы от кадра к кадру
	var votes: Dictionary = {}
	var engaged := 0
	var free := 0
	# Столбцы снимаются ОДИН РАЗ перед циклом. `army.px[i]` внутри цикла — это
	# выборка свойства чужого объекта на каждое обращение, а их здесь четыре на
	# бойца; та же оговорка, что и во всех остальных проходах по составу
	# ── КОЛОНКИ СНИМАЮТСЯ ОДНИМ СНИМКОМ, А НЕ ПОШТУЧНО ──────────────────────
	# Здесь была попытка брать координаты по одной (army.pos_x), и она вышла
	# боком: каждый такой вызов — переход границы GDScript↔C#, а их тут по два
	# на бойца. Замер: ветка melee_calc подорожала с 22 до 251 мкс на пересчёт,
	# то есть 1.8 мс кадра на ровном месте. Снимок отдаёт КОПИЮ массива, но она
	# одна на отряд и делается раз в MELEE_TTL_MS — против трёх тысяч переходов
	# границы это несопоставимо дешевле.
	# Правило, которое отсюда следует: через границу языков ходят ПАКЕТАМИ или
	# один раз, но никогда — в цикле по бойцам
	var apx: PackedFloat32Array = army.px
	var apz: PackedFloat32Array = army.pz
	var live: Array = []
	var free_list: Array = []
	var tgt := Vector3.ZERO
	var have_tgt := false
	var members: Array = (sq as Dictionary)["members"]
	for m in members:
		if not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null:
			continue
		# ── ПРИЗНАК ТЫЛА ГАСИТСЯ У ВСЕХ И ВЫДАЁТСЯ ЗАНОВО ────────────────────
		# Это АРЕНДА, а не флаг: право идти дешёвым шагом действует ровно до
		# следующей разметки отряда и продлевается только явно. Прежняя версия
		# ставила признак и полагалась на то, что все условия его снятия
		# перечислены верно, — их оказалось больше, чем я перечислил, и боец
		# «залипал» в бою навсегда (qa_disengage 4 из 11). При аренде такой
		# ошибки не бывает по построению: не подтвердили — вернулся сам
		u._rear_line = false
		u._line_valid = false
		if u.state != Unit.State.ATTACKING:
			continue
		var t: Node3D = u.attack_target
		if t == null or not is_instance_valid(t):
			free += 1
			continue
		live.append(u)
		if not have_tgt:
			tgt = t.global_position
			have_tgt = true
		# РАССТОЯНИЕ СЧИТАЕТСЯ ПО СТРОКАМ ЯДРА АРМИИ, А НЕ ЧЕРЕЗ УЗЛЫ.
		# global_position — это обращение к узлу, и здесь их два на бойца; на
		# сотне отрядов проход стоил 1.3 мс кадра при том, что те же числа
		# лежат в столбцах, обновлённых в этом же кадре. Здание строки не имеет,
		# для него остаётся узел — их единицы, и это не горячий путь
		var i: int = u._soa
		var ti: int = -1
		var tu := t as Unit
		if tu != null:
			ti = tu._soa
		var d_sq: float
		if i >= 0 and ti >= 0:
			var dx: float = apx[i] - apx[ti]
			var dz: float = apz[i] - apz[ti]
			d_sq = dx * dx + dz * dz
		else:
			d_sq = u.global_position.distance_squared_to(t.global_position)
		if d_sq <= u.attack_range * u.attack_range:
			engaged += 1
		else:
			free += 1
			# СВОБОДНЫЙ — КАНДИДАТ В ТЫЛ, но только если у него нет незаконченного
			# дела помимо драки. Отложенный марш, выход из боя, отход и бег — это
			# ровно те состояния, ради которых боец обязан пройти полный автомат
			if not u._march_pending and not u._disengaging \
					and not u.retreating and not u.sprinting:
				free_list.append(u)
		if tu != null and tu.squad_id > 0:
			votes[tu.squad_id] = int(votes.get(tu.squad_id, 0)) + 1
	var foe := 0
	var best := 0
	for k in votes:
		var v: int = int(votes[k])
		if v > best:
			best = v
			foe = int(k)
	_melee[sid] = {"t": now + ttl, "foe": foe, "engaged": engaged, "free": free}
	# ── РАЗМЕТКА ТЫЛА ИДЁТ ТЕМ ЖЕ ПРОХОДОМ ──────────────────────────────────
	# Раньше это был отдельный обход состава со своим сроком; ничего, кроме
	# второго прохода по тем же бойцам, он не давал. Кандидаты уже отобраны
	# выше (free_list), остаётся разложить их по колоннам и решить, кто из них
	# действительно стоит за спиной своего
	if _Opt.battle_lines and live.size() >= 2 and have_tgt:
		_assign_rear(sid, live, free_list, tgt, apx, apz)
	if _p: _Opt.prof_add("melee_calc", Time.get_ticks_usec() - _t)

## ── СКОЛЬКО БОЙЦОВ ОТРЯДА ПРЯМО СЕЙЧАС ДОСТАЮТ ДО СВОЕЙ ЦЕЛИ ────────────────
## Это и есть «отряд завязался в ближнем бою» в строгом смысле: не «по нам
## стреляют» и не «у кого-то есть цель на горизонте», а оружие достаёт.
## Число уже считается бухгалтерией боя (_recalc_melee, раз в MELEE_TTL_MS на
## отряд), здесь только чтение — своего обхода состава не появляется.
##
## Читатель — EnemyAI._try_retreat: отряд, у которого хоть кто-то в контакте, не
## разворачивается спиной (см. там же). Ответ может отставать до MELEE_TTL_MS
## (0.4 с), и это ровно в нужную сторону: отряд, только что вышедший из
## контакта, ещё полсекунды считается дерущимся и не срывается в бегство на
## последнем ударе
func squad_engaged(sid: int) -> int:
	var row: Variant = _melee.get(sid)
	if row == null:
		return 0
	return int((row as Dictionary).get("engaged", 0))

## Ширина колонны (файла) поперёк курса. Примерно место одного бойца в шеренге:
## уже — и один человек попадёт в два файла, шире — и сосед сбоку сойдёт за
## стоящего впереди (та же ловушка, что у FILE_HALF_WIDTH в подсчёте ряда)
const LINE_FILE_W := 0.9
## Наименьшая глубина, начиная с которой боец считается стоящим ЗА СПИНОЙ своего.
## У самой линии строй рыхлый, и слишком узкая граница перекидывала бы бойцов
## между фронтом и тылом на каждой разметке
const LINE_FRONT_BAND := 1.2
## Запас к дальности оружия при ответе «мой файл уже в контакте». Без запаса файл
## то признавался дошедшим, то нет, и тыл дёргался
const LINE_CONTACT_SLACK := 1.0

## РАСПРЕДЕЛЕНИЕ ТЫЛА — РЕШЕНИЕ ОТРЯДА, А НЕ САМОУПРАВСТВО БОЙЦА.
## `live` — все, кто в бою; `free_list` — те, кто до цели не достаёт и у кого нет
## другого незаконченного дела. Отряд режет себя на колонны поперёк курса, у
## каждой колонны свой передовой, и дешёвый шаг получает лишь тот, у кого в его
## колонне действительно кто-то стоит впереди.
func _assign_rear(sid: int, live: Array, free_list: Array, tgt: Vector3,
		apx: PackedFloat32Array, apz: PackedFloat32Array) -> void:
	if free_list.is_empty():
		return
	# Курс отряда: общий кэш, если он есть, иначе от центра масс к точке удара.
	# Кэш наполняет только пересчёт ряда, а тот работает лишь в стойке «оборона»,
	# поэтому в обычном бою он пуст — на него одного полагаться нельзя
	var course: Vector3 = squad_enemy_dir(sid)
	if course.length_squared() < 1e-6:
		var sx := 0.0
		var sz := 0.0
		for u in live:
			var iu: int = (u as Unit)._soa
			sx += apx[iu]
			sz += apz[iu]
		var inv: float = 1.0 / float(live.size())
		course = Vector3(tgt.x - sx * inv, 0.0, tgt.z - sz * inv)
		var cl: float = course.length()
		if cl < 1e-3:
			return
		course /= cl
	var cx: float = course.x
	var cz: float = course.z
	var rx: float = cz          # вбок = курс, повёрнутый на 90°
	var rz: float = -cx
	# ФРОНТ СЧИТАЕТСЯ ПО КОЛОННАМ, А НЕ ОДИН НА ОТРЯД. С общим фронтом
	# «передовым» оказывался ровно один боец, самый выдвинутый, а вся его шеренга
	# получала глубину и вставала в затылок: замер поймал это сразу — в контакте
	# оставалось 6 % бойцов вместо 33 %, свалка вырождалась в очередь
	var n: int = live.size()
	var projs := PackedFloat32Array()
	var lats := PackedFloat32Array()
	projs.resize(n)
	lats.resize(n)
	var min_lat := INF
	var max_lat := -INF
	for k in range(n):
		var i2: int = (live[k] as Unit)._soa
		var ax: float = apx[i2]
		var az: float = apz[i2]
		projs[k] = ax * cx + az * cz
		var lat: float = ax * rx + az * rz
		lats[k] = lat
		if lat < min_lat: min_lat = lat
		if lat > max_lat: max_lat = lat
	var files: int = int((max_lat - min_lat) / LINE_FILE_W) + 1
	var front := PackedFloat32Array()
	front.resize(files)
	front.fill(-INF)
	for k in range(n):
		var b: int = int((lats[k] - min_lat) / LINE_FILE_W)
		if projs[k] > front[b]:
			front[b] = projs[k]
	var tproj: float = tgt.x * cx + tgt.z * cz
	# РЯД — ПОРЯДКОВЫЙ НОМЕР В СВОЕЙ КОЛОННЕ. Считать его как «глубина, делённая
	# на шаг» нельзя: боец подтягивается к той же величине, из которой ряд и
	# выведен, условие самосбывающееся, и строй не смыкается никогда. Перебором
	# «сколько своих впереди» — тоже нельзя, это квадрат по составу (замер: сама
	# разметка с 2.2 до 8.8 мс на кадр). Колонны короткие, поэтому сортировка
	# ВСТАВКОЙ: она обходится без лямбды-компаратора, а её вызов на каждое
	# сравнение и был бы тут основной ценой
	var by_file: Dictionary = {}
	for k2 in range(n):
		var bf: int = int((lats[k2] - min_lat) / LINE_FILE_W)
		if not by_file.has(bf):
			by_file[bf] = []
		var arr: Array = by_file[bf]
		var pos: int = arr.size()
		while pos > 0 and projs[int(arr[pos - 1])] < projs[k2]:
			pos -= 1
		arr.insert(pos, k2)
	var rank_of := PackedInt32Array()
	rank_of.resize(n)
	for bb in by_file:
		var arr2: Array = by_file[bb]
		for r in range(arr2.size()):
			rank_of[int(arr2[r])] = r
	# Раздаём. Признак получают ТОЛЬКО кандидаты из free_list — то есть решение
	# принято отрядом заранее, а здесь только геометрия
	for k in range(n):
		var u := live[k] as Unit
		var b2: int = int((lats[k] - min_lat) / LINE_FILE_W)
		var gap: float = front[b2] - projs[k]
		u._line_gap = gap
		u._line_course = course
		u._live_rank = rank_of[k]
		# Мой файл уже упёрся во врага — держу строй; иначе иду вместе с ним.
		# Без этого различия тыл вставал там, где его застала разметка: отряд,
		# ещё не дошедший до противника, растворялся в струйку
		u._rear_hold = (tproj - front[b2]) <= u.attack_range + LINE_CONTACT_SLACK
		u._line_valid = true
		# ДВА УСЛОВИЯ, И ОБА ОБЯЗАТЕЛЬНЫ.
		# (1) отряд отнёс меня к свободным (не достаю до цели, дел больше нет);
		# (2) в моей колонне передо мной ДЕЙСТВИТЕЛЬНО кто-то стоит.
		# Второго условия не было в первой версии, и это дорого стоило: мерой
		# служило только расстояние до ОДНОЙ точки на отряд, а в общей свалке
		# рядом стоят чужие из других отрядов — бойцы уходили в тыл и шагали
		# мимо тех, кого могли ударить, урон падал в три с половиной раза.
		# Со спиной своего перед носом такого случиться не может
		if gap > LINE_FRONT_BAND and (u in free_list):
			u._rear_line = true

## С каким отрядом дерётся этот. 0 — связка не установлена
func squad_foe(sid: int) -> int:
	var row: Variant = _melee.get(sid)
	return int((row as Dictionary)["foe"]) if row != null else 0

## Сколько бойцов отряда реально достаёт до противника, и сколько ещё нет.
## Для стендов и для будущего слоя A: именно по этой паре отряд решает, кого
## можно вести дешёвым шагом, а кого нельзя
func melee_counts(sid: int) -> Array:
	var row: Variant = _melee.get(sid)
	if row == null:
		return [0, 0]
	var d: Dictionary = row
	return [int(d["engaged"]), int(d["free"])]

## ПОДСКАЗКА ЦЕЛИ ОТ ОТРЯДА вместо личного скана местности.
## Возвращает null, если связки нет или подходящий противник дальше `max_dist` —
## тогда боец ищет сам, как и раньше. Ограничение по дистанции обязательно:
## без него отряд назначал бы цель на другом конце карты, и боец уходил бы из
## своего боя (та же ошибка, что когда-то дала «отряд растекается по целям»)
func squad_duel_target(sid: int, asker: Node3D, max_dist: float) -> Node3D:
	if not _Opt.squad_melee or sid <= 0 or asker == null:
		return null
	var foe: int = squad_foe(sid)
	if foe <= 0 or not squads.has(foe):
		return null
	var pick: Node3D = squad_pick_member(foe, asker.global_position, null)
	if pick == null or not is_instance_valid(pick):
		return null
	if asker.global_position.distance_to(pick.global_position) > max_dist:
		return null
	return pick

## Связка разорвана: отряд получил приказ, расформирован или вышел из боя
func melee_release(sid: int) -> void:
	if sid > 0:
		_melee.erase(sid)

## Снять разметку немедленно: приказ увёл отряд, и старый фронт больше не фронт
func battle_line_invalidate(sid: int) -> void:
	if sid <= 0:
		return
	_melee.erase(sid)
	var sq: Variant = squads.get(sid)
	if sq != null:
		_clear_battle_line((sq as Dictionary)["members"])

## Немедленно снять «коридор чист» у отряда: приказ мог увести его в другое
## место, и старый ответ там уже ничего не гарантирует
func corridor_invalidate(sid: int) -> void:
	if sid <= 0:
		return
	_corridors.erase(sid)

## СПЯЩИЙ ЮНИТ САМ НИЧЕГО НЕ ЗАМЕЧАЕТ. Он не тикает вовсе, поэтому не увидит
## ни возвращения камеры (LOD), ни наползшего на него тумана. Оба случая
## лечатся одним редким проходом по МАЛОМУ множеству — тем, кто числится в
## общей отрисовке; будить приходится и того, кто снова в кадре, и чужого,
## которого накрыл туман (иначе вражеский гарнизон, заснувший на виду,
## остался бы нарисованным сквозь пелену навсегда)
func _wake_returned_far_units() -> void:
	for u in far_units.registered_units():
		if not is_instance_valid(u):
			continue
		if near_view(u.global_position):
			u.wake_for_lod()
			continue
		if fog != null and u.faction != Constants.FACTION_PLAYER \
				and not fog_lit_at(u.global_position.x, u.global_position.z):
			u.wake_for_lod()

var player_faction_name: String = "humans"
var ai_faction_name: String     = "humans"

# ── ЦВЕТА ФРАКЦИЙ ────────────────────────────────────────────────────────────
# Выбираются в главном меню, читаются юнитами и зданиями при постройке визуала.
# Раскладка папок и допустимые значения — в scripts/game_settings.gd
const _GS := preload("res://scripts/game_settings.gd")
const _Opt := preload("res://scripts/perf_config.gd")
var player_color: String = _GS.DEFAULT_PLAYER_COLOR
var ai_color: String     = _GS.DEFAULT_AI_COLOR

## Цвет стороны: единая точка, чтобы юниты/здания не разбирали фракцию сами
func color_of(faction: int) -> String:
	return player_color if faction == Constants.FACTION_PLAYER else ai_color

## Раса стороны (папка ассетов верхнего уровня)
func race_of(faction: int) -> String:
	return player_faction_name if faction == Constants.FACTION_PLAYER else ai_faction_name

## Папка спрайтов юнита нужной стороны: "spearman"/"archer"/"worker"/"warrior"
func unit_sprite_folder(faction: int, unit_id: String) -> String:
	return _GS.unit_folder(race_of(faction), color_of(faction), unit_id)

## Путь к спрайту здания нужной стороны ("castle"/"barracks"/"smithy"/"mine")
func building_sprite_path(faction: int, building_id: String) -> String:
	return _GS.building_sprite(race_of(faction), color_of(faction), building_id)

## Картинка НЕДОСТРОЯ. Цвета у неё нет: леса одинаковы у любой стороны
func construction_sprite_path(faction: int, building_id: String) -> String:
	return _GS.construction_sprite(race_of(faction), building_id)

## Картинка РУИН на месте снесённой постройки
func ruin_sprite_path(faction: int, building_id: String) -> String:
	return _GS.ruin_sprite(race_of(faction), building_id)

# Апгрейды раздельны по фракциям: кузница игрока не усиливает врага
var upgrades: Dictionary = {
	Constants.FACTION_PLAYER: {"damage": 0.0, "defense": 0.0, "health": 0.0, "arrow_dmg": 0.0},
	Constants.FACTION_ENEMY:  {"damage": 0.0, "defense": 0.0, "health": 0.0, "arrow_dmg": 0.0},
	Constants.FACTION_GOBLIN: {"damage": 0.0, "defense": 0.0, "health": 0.0, "arrow_dmg": 0.0},
}

func apply_upgrade(faction: int, stat: String, value: float) -> void:
	if upgrades.has(faction) and upgrades[faction].has(stat):
		upgrades[faction][stat] += value

func get_upgrade(faction: int, stat: String) -> float:
	if not upgrades.has(faction):
		return 0.0
	return upgrades[faction].get(stat, 0.0)

# ─────────────────────────────────────────────────────────────────────────────
# УЛУЧШЕНИЯ КУЗНИЦЫ (слоты описаны в scripts/unit_stats_config.gd)
# Бонусы копятся по фракции И типу юнита; юниты читают их ВЖИВУЮ при каждом
# ударе/шаге, поэтому апгрейд действует и на уже стоящие на карте отряды.
# ─────────────────────────────────────────────────────────────────────────────
const _UCfg := preload("res://scripts/unit_stats_config.gd")
## Древо технологий: нужно двум местам — разбору условий доступа узла
## (research_blockers) и покупке спец-способности отрядом (squad_buy_ability)
const _Forge := preload("res://scripts/forge_config.gd")

# unit_bonuses[faction][unit_id] = {"bonus_attack": 0.0, ...}
var unit_bonuses: Dictionary = {}
# researched[faction] = {upgrade_id: true}
var researched: Dictionary = {}
# ИДУЩИЕ ИССЛЕДОВАНИЯ: researching[faction] = {upgrade_id: true}.
# Ресурсы за слот уже списаны, но бонус ещё не применён — слот занят и
# повторно заказать его нельзя (см. can_research)
var researching: Dictionary = {}

## Суммарный бонус: unit_bonus(FACTION_PLAYER, "spearman", "bonus_attack")
##
## ГОРЯЧИЙ ПУТЬ: читается вживую на каждый шаг и каждый удар каждого бойца.
## `get(key, {})` создавал ЗДЕСЬ ДВА пустых словаря на вызов — значение по
## умолчанию в GDScript вычисляется всегда, даже когда ключ на месте
func unit_bonus(faction: int, unit_id: String, key: String) -> float:
	var per_faction: Variant = unit_bonuses.get(faction)
	if per_faction == null:
		return 0.0
	var per_unit: Variant = (per_faction as Dictionary).get(unit_id)
	if per_unit == null:
		return 0.0
	return (per_unit as Dictionary).get(key, 0.0)

func is_researched(faction: int, upgrade_id: String) -> bool:
	var done: Dictionary = researched.get(faction, {})
	return done.get(upgrade_id, false)

## Исследуется ли слот прямо сейчас
func is_researching(faction: int, upgrade_id: String) -> bool:
	var busy: Dictionary = researching.get(faction, {})
	return busy.get(upgrade_id, false)

## Доступен ли слот (не куплен, не в работе и выполнено условие requires)
func can_research(faction: int, upgrade_id: String) -> bool:
	var slot: Dictionary = _UCfg.get_upgrade_slot(upgrade_id)
	if slot.is_empty() or is_researched(faction, upgrade_id):
		return false
	if is_researching(faction, upgrade_id):
		return false
	return research_blockers(faction, slot).is_empty()

## ЧЕГО ИМЕННО НЕ ХВАТАЕТ, чтобы узел открылся — список id, а не просто «нельзя».
## Всплывающее окно древа обязано назвать причину («нужно изучить ряд целиком»),
## а не молча показать серую иконку; can_research() — это же самое, сведённое
## к bool. Пустой список = узел доступен.
##
## Виды условий:
##   requires        — одиночный предшественник СТАРЫХ слотов (UPGRADE_SLOTS)
##   prerequisites   — родители узла древа по ВЕРТИКАЛЬНОЙ стрелке, нужны ВСЕ
##   link_ids        — соседи по ГОРИЗОНТАЛЬНОЙ стрелке. АЛЬТЕРНАТИВНЫЙ вход:
##                     любой изученный сосед открывает узел вместо вертикали
##   row_gate        — только колонка D: весь её ряд A+B+C должен быть изучен.
##                     Это не стрелка, а отдельное правило (заказ владельца:
##                     «1D закрыта, пока не исследованы 1A + 1B + 1C»)
##
## ── ПРАВИЛО ГРАФА: ТОЛЬКО ПО ВИДИМОЙ СТРЕЛКЕ ────────────────────────────────
## Заказ владельца: «переход разрешён строго при наличии видимой стрелки; если
## от изученной технологии идёт стрелка вбок — можно шагнуть вбок». То есть
## вертикальная и горизонтальная стрелки равноправны как ПУТИ ВХОДА, и хватает
## ЛЮБОГО из них: узел открыт, если пришли сверху (все prerequisites) ИЛИ сбоку
## (хотя бы один сосед по link_ids).
##
## ИМЕННО ИЛИ, А НЕ И. Горизонтальные стрелки на схеме двусторонние: 2a связан
## с 2b, а 2b — с 2a. Требуй они друг друга, обе ячейки были бы заперты навсегда
## (это и был прежний довод «link — украшение»). Как альтернативный вход
## двусторонность безвредна по построению — она только разрешает.
##
## row_gate складывается с этим как и раньше: колонка D открывается рядом
## целиком, боковых стрелок у неё нет вовсе.
func research_blockers(faction: int, slot: Dictionary) -> Array:
	var missing: Array = []
	var req: String = String(slot.get("requires", ""))
	if not req.is_empty() and not is_researched(faction, req):
		missing.append(req)
	# ШАГ ВБОК: сосед по горизонтальной стрелке уже изучен — вертикаль не нужна
	var sideways := false
	for l in slot.get("link_ids", []):
		if is_researched(faction, String(l)):
			sideways = true
			break
	if not sideways:
		for p in slot.get("prerequisites", []):
			var pid: String = String(p)
			if not is_researched(faction, pid):
				missing.append(pid)
	for g in slot.get("row_gate", []):
		var gid: String = String(g)
		if not is_researched(faction, gid):
			missing.append(gid)
	return missing

## НАЧАТЬ исследование: списывает ресурсы и помечает слот занятым.
## Возвращает время исследования в секундах (0.0 = мгновенно) или -1.0,
## если слот недоступен либо не хватило ресурсов.
## Бонусы применяет finish_research() — его вызывает Кузница по таймеру.
func start_research(faction: int, upgrade_id: String) -> float:
	if not can_research(faction, upgrade_id):
		return -1.0
	var slot: Dictionary = _UCfg.get_upgrade_slot(upgrade_id)
	if not ResourceManager.spend(faction, _UCfg.upgrade_cost(slot)):
		return -1.0
	if not researching.has(faction):
		researching[faction] = {}
	(researching[faction] as Dictionary)[upgrade_id] = true
	return _UCfg.upgrade_research_time(slot)

## ЗАВЕРШИТЬ исследование: копит бонусы и мгновенно поднимает HP уже
## существующим юнитам. Ресурсы списаны раньше, в start_research().
func finish_research(faction: int, upgrade_id: String) -> void:
	var slot: Dictionary = _UCfg.get_upgrade_slot(upgrade_id)
	if slot.is_empty():
		return
	if researching.has(faction):
		(researching[faction] as Dictionary).erase(upgrade_id)
	if is_researched(faction, upgrade_id):
		return
	_accumulate_upgrade(faction, slot, upgrade_id)

## ОТМЕНИТЬ исследование: снимает пометку «в работе» и возвращает 100% цены.
## Возврат полный и без штрафа — по прямому требованию владельца: игрок ткнул
## не в тот слот, и наказывать его за это нечем.
## Уже ЗАВЕРШЁННОЕ исследование не отменяется (бонус уже разошёлся по юнитам —
## откатить его нечем), поэтому false.
func cancel_research(faction: int, upgrade_id: String) -> bool:
	if not is_researching(faction, upgrade_id):
		return false
	(researching[faction] as Dictionary).erase(upgrade_id)
	var slot: Dictionary = _UCfg.get_upgrade_slot(upgrade_id)
	if slot.is_empty():
		return true
	var costs: Dictionary = _UCfg.upgrade_cost(slot)
	for type in costs.keys():
		ResourceManager.add_resource(faction, int(type), float(costs[type]))
	return true

## Мгновенная покупка (без таймера). Оставлено для внешнего кода и тестов.
func research_upgrade(faction: int, upgrade_id: String) -> bool:
	if not can_research(faction, upgrade_id):
		return false
	var slot: Dictionary = _UCfg.get_upgrade_slot(upgrade_id)
	if not ResourceManager.spend(faction, _UCfg.upgrade_cost(slot)):
		return false
	_accumulate_upgrade(faction, slot, upgrade_id)
	return true

## ВЕРСИЯ ТАБЛИЦЫ БОНУСОВ. Бойцы читают бонусы вживую, но меняются те лишь по
## факту купленного улучшения — за всю партию считанные разы. Юнит запоминает
## посчитанную скорость и версию, при которой считал (см. Unit._effective_speed):
## пока номер не сменился, лезть в словари незачем
var bonus_version: int = 0

func _accumulate_upgrade(faction: int, slot: Dictionary, upgrade_id: String) -> void:
	if not unit_bonuses.has(faction):
		unit_bonuses[faction] = {}
	bonus_version += 1
	var per_faction: Dictionary = unit_bonuses[faction]

	for unit_id in _UCfg.STATS.keys():
		var uid: String = String(unit_id)
		if not _UCfg.slot_applies_to(slot, uid):
			continue
		if not per_faction.has(uid):
			per_faction[uid] = {}
		var acc: Dictionary = per_faction[uid]
		for key in _UCfg.BONUS_KEYS:
			var k: String = String(key)
			var v: float  = slot.get(k, 0.0)
			if v != 0.0:
				acc[k] = float(acc.get(k, 0.0)) + v

	if not researched.has(faction):
		researched[faction] = {}
	(researched[faction] as Dictionary)[upgrade_id] = true

	# HP — единственный бонус, который нельзя прочитать «вживую»: поднимаем
	# максимум и текущее здоровье уже существующим юнитам прямо сейчас
	var hp_bonus: float = slot.get("bonus_health", 0.0)
	if hp_bonus != 0.0:
		_apply_health_bonus_now(faction, slot, hp_bonus)
	# ДАЛЬНОСТЬ — ровно тот же случай, что и HP, и по той же причине: она лежит
	# полем и читается в горячих ветках, а не спрашивается у GameManager на
	# каждый скан (см. Unit._ready). Новорождённые получают её сами
	var rng_bonus: float = slot.get("bonus_range", 0.0)
	if rng_bonus != 0.0:
		_apply_range_bonus_now(faction, slot, rng_bonus)

func _apply_health_bonus_now(faction: int, slot: Dictionary, hp_bonus: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("all_units"):
		var u := n as Unit
		if u == null or u.faction != faction or u.is_dead():
			continue
		if not _UCfg.slot_applies_to(slot, u.stat_id):
			continue
		u.max_health     += hp_bonus
		u.current_health += hp_bonus
		u._soa_push_stats()

func _apply_range_bonus_now(faction: int, slot: Dictionary, rng: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("all_units"):
		var u := n as Unit
		if u == null or u.faction != faction or u.is_dead():
			continue
		if not _UCfg.slot_applies_to(slot, u.stat_id):
			continue
		# Потолок держится и здесь: исследование выдаётся уже стоящим на карте,
		# и без зажима именно этот путь и уводил дальность за все пределы
		# (см. Unit.clamp_attack_range)
		u.attack_range = u.clamp_attack_range(u.attack_range + rng)
		u._soa_push_stats()

func register_dropoff(faction: int, building: Node3D) -> void:
	if not dropoffs.has(faction):
		dropoffs[faction] = []
	dropoffs[faction].append(building)

func unregister_dropoff(faction: int, building: Node3D) -> void:
	if dropoffs.has(faction):
		dropoffs[faction].erase(building)

func get_nearest_dropoff(faction: int, from_pos: Vector3) -> Node3D:
	if not dropoffs.has(faction) or dropoffs[faction].is_empty():
		return null
	var nearest: Node3D = null
	var best_dist := INF
	for b in dropoffs[faction]:
		if not is_instance_valid(b):
			continue
		var d = from_pos.distance_to(b.global_position)
		if d < best_dist:
			best_dist = d
			nearest = b
	return nearest

## ── ЩЕЛЧОК ВЫДЕЛЕНИЯ ───────────────────────────────────────────────────────
## Здание и отряд звучат по-разному (click1 / click3). Точка выбрана здесь,
## потому что это ЕДИНСТВЕННАЯ воронка выделения: клик, рамка, горячая группа,
## виджет бездельников и плашка отрядов приходят все сюда. На кнопках панели
## пришлось бы вешать звук пять раз и один всё равно бы забылся.
##
## Звучит только на РЕАЛЬНУЮ смену набора: панель пересобирается и на обычном
## обновлении (например, при потере бойца), а щёлкать на это нельзя
var _sel_sig: String = ""

## Подпись набора + что в нём есть. Возвращает [сменилась ли, есть здание,
## есть юнит] и запоминает подпись
func _selection_sig(units: Array) -> Array:
	var sig := ""
	var has_building := false
	var has_unit := false
	for n in units:
		if not is_instance_valid(n):
			continue
		var nd := n as Node
		if int(nd.get("faction")) != Constants.FACTION_PLAYER:
			continue
		if nd is Building:
			has_building = true
		elif nd is Unit:
			has_unit = true
		sig += str(nd.get_instance_id()) + ","
	var changed: bool = sig != _sel_sig
	_sel_sig = sig
	return [changed, has_building, has_unit]

func _selection_click_sfx(units: Array) -> void:
	var r: Array = _selection_sig(units)
	if not bool(r[0]):
		return
	if bool(r[1]):
		AudioManager.play_ui("pick_building")
	elif bool(r[2]):
		AudioManager.play_ui("pick_squad")

## ── СКОЛЬКО БОЙЦОВ РЕАЛЬНО ХОДЯТ ───────────────────────────────────────────
## Число шардов выводится ОТСЮДА, а не из размера реестра. Спящая деревня
## гоблинов — это восемь сотен бойцов, которые стоят и не тикают вовсе; считая
## их, игра уходила в два шарда с первой секунды партии, то есть все ОСТАЛЬНЫЕ
## начинали двигаться тридцать раз в секунду вместо шестидесяти ни за что.
## Счётчик ведётся событиями (сон/пробуждение), а не обходом армии
var dormant_units: int = 0

func active_units() -> int:
	return maxi(_live_units.size() - dormant_units, 0)

func note_dormant(on: bool) -> void:
	dormant_units = maxi(dormant_units + (1 if on else -1), 0)

## silent = true — выделение произошло НЕ по клику игрока, а само: игра выбрала
## заложенный фундамент, достроенный замок, отряд после награды. Щёлкать на это
## нельзя — звук выделения означает «игрок ткнул в объект», и паразитный клик
## при закладке крепости владелец услышал сразу
func on_selection_changed(units: Array, silent: bool = false) -> void:
	if silent:
		# Подпись всё равно запоминаем: иначе СЛЕДУЮЩЕЕ обновление той же
		# панели прозвучит как новое выделение
		_selection_sig(units)
	else:
		_selection_click_sfx(units)
	if main and main.has_method("on_selection_changed"):
		main.on_selection_changed(units)

## Открылась/закрылась карточка разведки чужого отряда. Отдельный канал от
## выделения намеренно: разведанный отряд НЕ выделен и приказов не получает
## (см. SelectionManager.recon_units)
func on_recon_changed(units: Array) -> void:
	if main and main.has_method("on_recon_changed"):
		main.on_recon_changed(units)

# ─────────────────────────────────────────────────────────────────────────────
# ОТРЯДЫ (SQUADS) — ЕДИНИЦА УПРАВЛЕНИЯ
# ═════════════════════════════════════════════════════════════════════════════
# Игра оперирует ОТРЯДАМИ, а не отдельными бойцами: выделяется отряд целиком,
# приказы получает отряд целиком. Одиночного солдата выделить нельзя.
#
# Отряд заводится ОДИН РАЗ на заказ найма (Building.queue_unit) и живёт, пока
# в нём есть хоть один живой боец. Рабочий — отряд из одного человека
# (так игрок может отдать ему приказ, не ломая правило «только отряды»).
#
# Здесь намеренно НЕТ узлов: отряд — это запись в словаре. Ни _process,
# ни лишних Node3D в дереве на 450 бойцов.
#   squads[id] = {"id", "faction", "type", "members": Array[Unit]}
# ─────────────────────────────────────────────────────────────────────────────
var squads: Dictionary = {}
var _next_squad_id: int = 1

## Завести новый отряд и вернуть его id.
## kills/level/pending/bonuses — система ветеранства (см. ниже)
func new_squad(p_faction: int, unit_type: String) -> int:
	var id := _next_squad_id
	_next_squad_id += 1
	squads[id] = {
		"id": id, "faction": p_faction, "type": unit_type, "members": [],
		"kills": 0,        # общий счёт убийств отряда
		"level": 0,        # заслуженный уровень ветеранства
		"pending": 0,      # сколько улучшений ждут выбора игроком
		"bonuses": {},     # выбранные бонусы: stat -> суммарное значение
		"chosen": [],      # id выбранных улучшений, по уровням
		# ДОКУПЛЕННЫЕ СПОСОБНОСТИ (колонка D древа кузницы): id узла -> true.
		# Исследование в кузнице открывает способность ФРАКЦИИ, но не выдаёт её
		# даром — каждый отряд платит за неё отдельно (см. squad_buy_ability)
		"abilities": {},
		# ── ЗНАМЯ ВЕТЕРАНСТВА (пришло на смену звёздочке) ──
		"banner": null,    # узел знамени в мире (см. SquadBanner)
		"bearer": null,    # боец, на копье которого оно сейчас висит
		# Где отряд видели в последний раз. Нужно ровно один раз — в момент
		# гибели ПОСЛЕДНЕГО бойца: узел к тому времени уже уходит из дерева, а
		# знамя обязано упасть там, где он стоял, а не в начале координат
		"last_pos": Vector3.ZERO,
		# ── РАЗМЕТКА СТРОЯ (см. squad_set_formation) ──
		"slots": [],              # точки построения, по шеренгам от передовой
		# Насколько разметка прогнута ударами тяжёлой конницы (см. squad_dent).
		# Обнуляется вместе с самой разметкой: новый приказ — новая линия
		"dent": 0.0,
		"course": Vector3.ZERO,   # куда смотрит фронт
		"slow": false,            # маршевый шаг или быстрый
		"at_order": 0,            # сколько было бойцов на момент приказа
		"reshuffled": 0,          # когда смыкали ряды в последний раз, ticks_msec
		"counter_ms": 0,          # когда отряд последний раз шёл в контратаку
		# ── ПОДТЯГИВАНИЕ ХВОСТА (см. squad_note_arrival) ──
		"arrived": 0,             # сколько бойцов уже добрались до своих мест
		"catch_up": false,        # хвост получил прибавку к скорости
	}
	return id

## Записать бойца в отряд. Прежняя приписка снимается — боец всегда ровно в одном
func add_to_squad(squad_id: int, unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if not squads.has(squad_id):
		return
	remove_from_squad(unit)
	(squads[squad_id]["members"] as Array).append(unit)
	unit.squad_id = squad_id
	# Номер отряда — в строку ядра армии: приписка редкая, а пакетным обходам
	# Фазы 3 он понадобится без обращения к объекту
	if unit._soa >= 0:
		army.set_squad(unit._soa, squad_id)
	# Пополнение подхватывает текущее состояние прибавки (см. _push_catch_up)
	unit._catch_up = bool((squads[squad_id] as Dictionary).get("catch_up", false))

func remove_from_squad(unit: Node) -> void:
	if unit == null:
		return
	var sid: int = unit.squad_id
	if sid <= 0:
		return
	# ОТВЕТЫ ОТРЯДА ОСТАЮТСЯ В ОТРЯДЕ. Вышедший из строя боец больше никем не
	# обслуживается, и «коридор чист» у него стал бы вечным разрешением ходить
	# сквозь стволы и чужие шеренги (см. _push_corridor)
	unit._clear_trunk = false
	unit._clear_enemy = false
	# Разметка линии — такой же ответ отряда, и по той же причине снимается:
	# «я в тылу» у бойца без отряда означало бы вечное ожидание своей очереди,
	# то есть он просто встал бы столбом (см. _assign_rear)
	unit._rear_line = false
	unit._line_valid = false
	if unit._soa >= 0:
		army.set_squad(unit._soa, 0)
	# Состав отряда изменился — связка боя пересчитывается заново. Не erase
	# ради чистоты, а потому что «engaged/free» посчитаны по прежнему составу
	_melee.erase(sid)
	if not squads.has(sid):
		# Отряд уже расформирован, а боец унёс его номер. Чистим: иначе висячий
		# id мог бы совпасть с номером ЧУЖОГО отряда, выданным позже
		unit.squad_id = 0
		return
	var sq: Dictionary = squads[sid]
	var members: Array = sq["members"]
	members.erase(unit)
	unit.squad_id = 0
	# ── ГДЕ СТОЯЛ ПОСЛЕДНИЙ ─────────────────────────────────────────────────
	# Пишется на КАЖДОМ выбывшем, а не только на последнем: узнать, что боец
	# последний, можно лишь после members.erase, а к моменту гибели последнего
	# его узел уже уходит из дерева. Одна запись Vector3 на выбывшего
	var up: Vector3 = _node_pos_safe(unit)
	if up != Vector3.INF:
		sq["last_pos"] = up
	if members.is_empty():
		# ── ЗНАМЯ РОНЯЕТ ТОЛЬКО ГИБЕЛЬ, А НЕ ПЕРЕВОД ────────────────────────
		# Отряд пустеет ДВУМЯ путями, и выглядят они в коде одинаково:
		# последнего бойца УБИЛИ — или его ПЕРЕВЕЛИ в другой отряд
		# (add_to_squad первым делом зовёт remove_from_squad). ИИ и орда
		# перекладывают бойцов по отрядам каждый такт размышления, и на каждом
		# таком перекладывании на землю падало знамя. Ровно это владелец и
		# видит как «синие флажки по пятам за орками»: тянущийся за отрядом
		# след из упавших знамён его же прежних, живых и здоровых отрядов.
		#
		# Признак берётся у САМОГО выбывшего: он либо мёртв, либо нет
		_disband_squad(sid, unit is Unit and (unit as Unit).is_dead())
		return
	# ── ЗНАМЯ ПЕРЕХОДИТ К БЛИЖАЙШЕМУ ЖИВОМУ ────────────────────────────────
	# Заказ владельца: «при смерти знаменосца знамя переезжает на копьё
	# ближайшего выжившего». Именно ближайшего к ПАВШЕМУ, а не к центру отряда:
	# на экране это читается как «подхватил сосед», а выбор по центру уводил бы
	# знамя в тыл через полстроя
	if sq.get("bearer") == unit:
		sq["bearer"] = null
		_assign_bearer(sid, up if up != Vector3.INF else Vector3.INF)
	# Знамя — узел в МИРЕ (см. refresh_squad_banner), а не ребёнок знаменосца,
	# поэтому гибель бойца его с собой не уносит. Освобождённый узел всё же
	# подчищаем — на него могли сослаться извне
	var bn = sq.get("banner")
	if bn != null and not is_instance_valid(bn):
		sq["banner"] = null
		refresh_squad_banner(sid)

# ═════════════════════════════════════════════════════════════════════════════
# ЗНАМЕНОСЕЦ
# ═════════════════════════════════════════════════════════════════════════════
# Знамя ветеранства — не метка над отрядом, а ПРЕДМЕТ В РУКАХ конкретного бойца
# (см. SquadBanner). Значит у него есть носитель, и за носителем надо следить:
# он гибнет чаще, чем отряд получает новое звание.
#
# ПОЧЕМУ ЗНАМЕНОСЕЦ НЕ ХРАНИТСЯ НА САМОМ БОЙЦЕ. Поле `is_bearer` на юните
# пришлось бы поддерживать в двух местах (снять со старого, поставить новому) и
# оно переживало бы бойца в чужих ссылках. Отряд же и так владеет составом —
# ему и держать, кто из состава несёт знамя.
#
# ЦЕНА: ноль в кадре. Выбор носителя считается только по СОБЫТИЮ — когда отряд
# получил звание, когда носитель выбыл, и когда его почему-то не оказалось.

## Кто сейчас несёт знамя отряда (null — некому или отряд не ветеран)
func squad_bearer(sid: int) -> Node:
	if not squads.has(sid):
		return null
	var b = (squads[sid] as Dictionary).get("bearer")
	if b == null or not is_instance_valid(b) or (b as Unit).is_dead():
		return null
	return b

## Позиция узла, который прямо сейчас может уходить из дерева. Vector3.INF —
## спросить нельзя (уже освобождён): вызывающий обязан это учесть
func _node_pos_safe(n) -> Vector3:
	if n == null or not is_instance_valid(n):
		return Vector3.INF
	var n3 := n as Node3D
	if n3 == null:
		return Vector3.INF
	return n3.global_position

## ── ВЫБРАТЬ ЗНАМЕНОСЦА ─────────────────────────────────────────────────────
## `near` — точка, от которой искать ближайшего. Vector3.INF означает «первое
## назначение», и тогда работает правило владельца: ПЕРВЫЙ РЯД, КРАЙНИЙ ЛЕВЫЙ.
##
## «Первый ряд» считается по курсу отряда: самый выдвинутый вперёд боец задаёт
## линию фронта, и все, кто в полосе ROW_BAND от неё, считаются первой шеренгой.
## Квантовать по номеру шеренги нельзя — в бою разметка уже не действует, и
## номера у выживших любые.
##
## Курса нет (отряд ни разу не получал приказа) — падаем на «крайний левый по
## оси X»: другого понятия «лево» без курса не существует
const BEARER_ROW_BAND := 1.2

## Носит ли этот отряд знамя В СЕРЕДИНЕ строя, а не с краю (разбор — в
## _assign_bearer). Признак РОДА СТРОЯ, а не фракции по существу: у толпы нет
## ни первого ряда, ни левого фланга, и правило шеренги на ней бессмысленно.
## Спрашивается по фракции только потому, что толпой в проекте ходит ровно одна
## сторона — орда
func _bearer_in_middle(sid: int) -> bool:
	if not squads.has(sid):
		return false
	return int((squads[sid] as Dictionary).get("faction", -1)) == Constants.FACTION_GOBLIN

func _assign_bearer(sid: int, near: Vector3 = Vector3.INF) -> Node:
	if not squads.has(sid):
		return null
	var sq: Dictionary = squads[sid]
	var live: Array = []
	for m in (sq["members"] as Array):
		var u := m as Unit
		if u != null and is_instance_valid(u) and not u.is_dead():
			live.append(u)
	if live.is_empty():
		sq["bearer"] = null
		return null
	var best: Unit = null
	if near != Vector3.INF:
		# ПЕРЕДАЧА: ближайший к павшему
		var bd := INF
		for u in live:
			var uu := u as Unit
			var dx: float = uu.global_position.x - near.x
			var dz: float = uu.global_position.z - near.z
			var d: float = dx * dx + dz * dz
			if d < bd:
				bd = d
				best = uu
	elif _bearer_in_middle(sid):
		# ── У ТОЛПЫ ЗНАМЯ В СЕРЕДИНЕ, А НЕ С КРАЮ ──────────────────────────
		# Жалоба владельца: «синие флажки торчат в полях там, где ходили орки».
		# Замерено, что знамёна НЕ утекают и НЕ дублируются: за весь бой узлов
		# ровно столько же, сколько ветеранских отрядов орды (пять из пяти,
		# ни одного бесхозного), и знамя честно сидит на своём знаменосце с
		# точностью до смещения древка.
		#
		# Беда в том, КОГО назначают знаменосцем. Правило «первый ряд, крайний
		# левый» писано под ШЕРЕНГУ: там крайний левый стоит в строю, плечом к
		# плечу с соседом. У орды строя нет вовсе — она ходит ТОЛПОЙ по спирали
		# (см. goblin_config.HORDE_SPOT), и «самый выдвинутый вперёд и самый
		# левый» — это одиночка НА ОБОДЕ толпы: замер дал 5.7 м от центра кучи
		# из сорока гоблинов, а в полном отряде на сотню он ушёл бы дальше.
		# Мелкий тёмный гоблин на зелёной траве почти не читается, а яркое
		# полотнище на длинном древке — читается прекрасно. Отсюда и «флаг,
		# воткнутый в пустое поле».
		#
		# Лечение — не прятать знамя (ветеранство орды заказано владельцем и
		# остаётся), а ДАТЬ ЕГО В СЕРЕДИНУ ТОЛПЫ: там вокруг знаменосца всегда
		# есть тела, и флаг читается как несомый.
		var c := Vector3.ZERO
		for u in live:
			c += _bearer_anchor(u as Unit)
		c /= float(live.size())
		var cd := INF
		for u in live:
			var uc := u as Unit
			var ap2: Vector3 = _bearer_anchor(uc)
			var dx2: float = ap2.x - c.x
			var dz2: float = ap2.z - c.z
			var d2: float = dx2 * dx2 + dz2 * dz2
			if d2 < cd:
				cd = d2
				best = uc
	else:
		# ПЕРВОЕ НАЗНАЧЕНИЕ (и возврат при перестроении): первый ряд, крайний левый
		var course: Vector3 = squad_course(sid)
		if course.length_squared() < 1e-6:
			for u in live:
				var uu2 := u as Unit
				if best == null or _bearer_anchor(uu2).x < _bearer_anchor(best).x:
					best = uu2
		else:
			var fwd := course.normalized()
			# Левая рука строя: поворот курса на 90° против часовой в плане
			var left := Vector3(fwd.z, 0.0, -fwd.x)
			var front := -INF
			for u in live:
				var d: float = _bearer_anchor(u as Unit).dot(fwd)
				if d > front:
					front = d
			var lb := -INF
			for u in live:
				var uu3 := u as Unit
				var ap: Vector3 = _bearer_anchor(uu3)
				if ap.dot(fwd) < front - BEARER_ROW_BAND:
					continue
				var lat: float = ap.dot(left)
				if lat > lb:
					lb = lat
					best = uu3
	sq["bearer"] = best
	return best

# ═════════════════════════════════════════════════════════════════════════════
# СТРОЙ СМЫКАЕТСЯ САМ, КОГДА ЕГО РАЗВАЛИЛИ
# ═════════════════════════════════════════════════════════════════════════════
# Жалоба владельца: рыцари проходят сквозь шеренгу пехоты, после чего пехота
# остаётся с разломанным строем и дырами.
#
# ПОЧЕМУ ПРЕЖНЕЕ СМЫКАНИЕ ЭТОГО НЕ ЛОВИЛО. Оно взводится ТОЛЬКО боем
# (squad_mark_hit → _arm_reform_check): «отряд задели — значит после боя надо
# сомкнуться». Проход СВОИХ сквозь строй боем не является — никто никого не
# бил, отметка не ставилась, и разметка так и оставалась с дырами до первой
# стычки.
#
# ЧТО ДЕЛАЕМ. Редкий обход отрядов: если бойцы стоящего отряда УЕХАЛИ ОТ СВОИХ
# МЕСТ дальше допуска — смыкаемся. Причина отъезда роли не играет вовсе, и это
# главное достоинство решения: ловить «проход союзника» отдельным событием
# значило бы завести детектор прохода, а он ошибался бы и на расталкивании, и
# на толчке конницы, и на возврате из гарнизона — а лечение у всех этих
# случаев одно и то же.
#
# ЦЕНА. Раз в REFORM_SWEEP_SEC (секунда) один проход по отрядам с чтением точки
# каждого бойца. На пяти тысячах бойцов это пять тысяч сравнений В СЕКУНДУ,
# то есть меньше сотни на кадр — на порядок дешевле любого покадрового скана.
# Отряды в бою, на марше и без разметки пропускаются первой же строкой.

## ── ЧЕГО ЭТОМУ ОБХОДУ НЕ ХВАТАЛО ───────────────────────────────────────────
## Жалоба владельца повторилась в новом виде: союзные ЛУЧНИКИ проходят сквозь
## шеренгу копейщиков, строй раздвигается — и назад не сходится.
##
## Обход был написан правильно, но у него было две глухих двери, и обе
## закрывались ровно в тот момент, когда помощь и нужна:
##   • `squad_in_combat(sid)` — ранний выход. Проход своих случается ПОСРЕДИ
##     боя (лучники за тем и идут, чтобы стрелять), а окно «недавно задели»
##     длиной три секунды в свалке не закрывается вовсе. Отряд не смыкался НИ
##     РАЗУ за всю драку;
##   • первый же боец в состоянии MOVING/ATTACKING обрывал проверку всего
##     отряда. В строю, который с кем-то дерётся передней шеренгой, такой боец
##     есть всегда.
##
## ПОЧЕМУ НЕЛЬЗЯ ПРОСТО СНЯТЬ ЭТИ ПРОВЕРКИ. Они охраняют настоящую беду:
## `squad_close_ranks` шлёт `command_move` КАЖДОМУ живому бойцу, а `command_move`
## у бойца с живой целью эту цель снимает — то есть полное смыкание посреди
## рубки выдёргивает из боя тех, кто дерётся. Ровно от этого и заведён
## `squad_in_combat`.
##
## ── ОТКАТ: ЛЁГКОГО ПУТИ БОЛЬШЕ НЕТ ────────────────────────────────────────
## Был заведён второй, «лёгкий» путь — `_reform_nudge`: он слал `command_move`
## ОТДЕЛЬНЫМ бойцам, тем, кто съехал с места и ничем не занят, и работал даже
## посреди боя. Задумка была в том, что дерущихся он не трогает.
##
## НА ЭКРАНЕ ЭТО ОБЕРНУЛОСЬ ХАОСОМ, и владелец прислал скриншоты. Две беды, и
## обе следуют прямо из «поштучно и в бою»:
##   • ОТРЯД РАЗРЫВАЛО. Боец, у которого в свалке на секунду не стало цели,
##     считался бездельником и получал приказ идти на свой `post_pos` — а тот
##     остался там, откуда отряд ВЫШЕЛ, иногда за полкарты. Он разворачивался
##     и уходил из боя, за ним второй, третий: отряд вытягивался цепочкой прочь
##     от схватки и разваливался на куски;
##   • РАБОЧИЕ БРОСАЛИ РАБОТУ. Рабочий числится отрядом из одного человека, и
##     разметка у такого отряда завестись может. `command_move` сбрасывает и
##     рубку, и стройку, и добычу — отсюда «доходят, делают пару процентов и
##     начинают толкаться».
##
## ЛЕЧЕНИЕ — НЕ ТРЕТИЙ КОСТЫЛЬ, А ОТКАЗ ОТ ВТОРОГО. Действие снова ОДНО и
## ОТРЯДНОЕ: `squad_close_ranks` рассаживает выживших по своей же разметке,
## и делает это только вне боя. Рабочих обход не касается вовсе.
##
## Отдельного детектора «прохода союзника» по-прежнему НЕТ и заводить его не
## нужно: «нас не трогают уже REFORM_SETTLE_SEC секунд» — это и есть конец
## любого воздействия, чем бы оно ни было.


## Как часто проверять, не развалился ли строй, секунды.
## Заказ владельца — 0.2–0.3 с вместо секунды: проход отряда сквозь строй длится
## пару секунд, и при секундном такте возврат начинался с заметной задержкой.
## Цена от этого не выросла втрое: обход считает только СТОЯЩИЕ отряды с
## разметкой, а идущий отсекается первым же бойцом
const REFORM_SWEEP_SEC := 0.3

## ── ПОРОГ ВЫВЕДЕН ИЗ ТОГО, ЧТО ДЕЛАЕТ ПРОХОД СОЮЗНИКА ─────────────────────
## Полтора метра были взяты с запасом «чтобы не спорить с расталкиванием», и
## ровно из-за этого жалоба не закрывалась. Замер прохода отряда лучников
## сквозь строй копейщиков: ХУДШИЙ съезд 1.13 м, четверо съехавших дальше
## 0.85 м из двадцати четырёх. То есть проход раздвигает строй ЗАМЕТНО для
## глаза, но заведомо МЕНЬШЕ прежнего порога — обход смотрел на развороченную
## шеренгу и честно отвечал «всё в порядке».
##
## 0.85 м лежит между двумя жёсткими границами и обязан там остаться:
##   • СНИЗУ держит допуск прибытия (ARRIVE_RADIUS = 0.48) и разбор наложения:
##     боец, законно оттеснённый соседом на полметра, стоит в строю, а не
##     выпал из него. Порог ниже допуска дал бы вечное смыкание, спорящее с
##     расталкиванием, — а оно всё равно сильнее;
##   • СВЕРХУ — то, ради чего обход и заведён.
const REFORM_DRIFT := 0.70

## ── ПАУЗА ПОСЛЕ ПРОХОДА ────────────────────────────────────────────────────
## Сколько секунд после того, как давление перестало расти, ждать перед
## смыканием. Два такта обхода: расталкивание доводит оттёртых ещё пару кадров,
## и смыкание, начатое в ту же миллисекунду, спорило бы с ним
const REFORM_SETTLE_SEC := 0.65

## Обход строя рабочих не касается. Признак, а не «просто так написано в коде»:
## это ТРЕБОВАНИЕ (см. разбор у самой проверки в _sweep_reform), и стенд обязан
## иметь возможность его спросить, не разбирая тело функции
const REFORM_SKIPS_WORKERS := true

# ═════════════════════════════════════════════════════════════════════════════
# ОДИНОЧНЫЙ АГЕНТ: ОТРЯД КАК УЧЁТНАЯ ЕДИНИЦА, А НЕ КАК СТРОЙ
# ═════════════════════════════════════════════════════════════════════════════
# Вопрос владельца: «почему рабочие вообще имеют логику отрядного построения?»
# Отряд им заведён НАМЕРЕННО, но по другой причине: игра оперирует только
# отрядами, иначе рабочего нельзя ни выделить, ни посчитать в панели типов
# (см. Main, где создаётся стартовая артель). То есть отряд у рабочего — это
# УЧЁТНАЯ ЕДИНИЦА.
#
# Беда в том, что боевые механизмы не различали эти два смысла и цеплялись к
# любому squad_id: выход из здания раскладывал рабочих боевой шеренгой, а
# смыкание рядов гоняло их строем и сбивало работу. Признак ниже — единственное
# место, где эта разница названа вслух, и спрашивают его ВСЕ три механизма.
const SINGLE_AGENT_TYPES := {"worker": true}

## Отряд этого типа — просто СПИСОК одиночек: ни шеренги, ни смыкания, ни
## разметки строя ему не полагается
func squad_is_single_agent(sid: int) -> bool:
	if not squads.has(sid):
		return false
	return SINGLE_AGENT_TYPES.has(String((squads[sid] as Dictionary).get("type", "")))

var _reform_sweep_t: float = 0.0

# ═════════════════════════════════════════════════════════════════════════════
# ОТРЯДЫ НЕ ВСТАЮТ ДРУГ НА ДРУГА
# ═════════════════════════════════════════════════════════════════════════════
# Жалоба владельца: несколько отрядов, посланных в одну точку (или новобранцы,
# идущие на точку сбора, где уже кто-то стоит), накладываются, начинают
# непрерывно толкаться и пытаются смыкать ряды внутри чужой массы.
#
# ПОЧЕМУ ЭТО НЕ ЛЕЧИТСЯ РАСТАЛКИВАНИЕМ. Разбор наложения разводит ТЕЛА и делает
# это правильно, но он не знает про отряды: две сотни бойцов, которым велено
# стоять в одном и том же месте, он будет разводить вечно — каждый лезет на
# свою точку разметки, а точки совпадают. Отсюда и «дёргаются, не могут встать»:
# приказ и расталкивание тянут в разные стороны, и ни один не уступает.
#
# ЛЕЧИТЬ НАДО ПРИКАЗ, А НЕ ТЕЛА. Точка назначения проверяется ОДИН РАЗ, в
# момент выдачи приказа: занято — отходим в сторону, пока не станет свободно.
# Это ровно то же решение, что и у всей прочей геометрии строя в проекте
# (приказ, а не сила), и стоит оно один проход по отрядам на клик.

## Просвет между габаритами соседних отрядов, метры. Тот же порядок, что у
## SelectionManager.GROUP_CELL_GAP: видимая граница между блоками, а не поле
const SQUAD_SPOT_GAP := 1.2
## Сколько раз уточняем точку. Занятых мест рядом бывает несколько, и уход от
## одного может завести в другое; три прохода снимают почти любой такой случай
const SQUAD_SPOT_PASSES := 3
## Дальше этого от заказанной точки не уводим ни при каких условиях: приказ
## игрока обязан оставаться узнаваемым
const SQUAD_SPOT_MAX_SHIFT := 24.0

## Радиус отряда в плане, метры. Считается по ЧИСЛУ бойцов и строевому
## интервалу, а не обходом состава: обходить его тут пришлось бы для каждого
## отряда на каждый клик, а ответ нужен приблизительный — это габарит для
## разведения, а не геометрия строя
func squad_spot_radius(sid: int) -> float:
	if not squads.has(sid):
		return 0.0
	var n: int = (squads[sid] as Dictionary)["members"].size()
	if n <= 0:
		return 0.0
	# Круг той же площади, что и блок из n бойцов с интервалом SPOT_SPACING
	return sqrt(float(n)) * 0.5 * SQUAD_SPOT_SPACING + 0.4

## Строевой интервал, из которого выводится габарит. Держится здесь, а не
## читается из SelectionManager: этим числом пользуются и приказ игрока, и
## точка сбора здания, а они живут в разных файлах
const SQUAD_SPOT_SPACING := 0.62

## Свободное место рядом с `wanted` для отряда `sid`.
## `ignore` — номера отрядов, которых не считаем помехой (те, кому раздают
## приказ этим же кликом: их разводит между собой сетка блоков).
## `radius` — габарит отряда, если он известен ЗАРАНЕЕ. Нужен точке сбора:
## отряд там ещё не набран (бойцы выходят по одному), и считать его габарит по
## наличному составу значило бы получать РАЗНЫЙ ответ на каждого выходящего —
## первый встал бы в одном месте, десятый в другом
func free_squad_spot(sid: int, wanted: Vector3, ignore: Dictionary = {},
		radius: float = 0.0) -> Vector3:
	var mine: float = radius if radius > 0.0 else squad_spot_radius(sid)
	if mine <= 0.0:
		return wanted
	# Фракция читается ОДИН раз: отряда с таким номером может уже не быть
	# (точка сбора спрашивает про ещё не набранный отряд)
	var my_fac: int = -2
	if squads.has(sid):
		my_fac = int((squads[sid] as Dictionary).get("faction", -2))
	var spot := wanted
	for _pass in range(SQUAD_SPOT_PASSES):
		var moved := false
		for key in squads.keys():
			var other: int = int(key)
			if other == sid or ignore.has(other):
				continue
			var osq: Dictionary = squads[key]
			# Чужие отряды помехой не считаем: сквозь них ходят и дерутся,
			# и уступать им место приказом было бы подсказкой игроку
			if int(osq.get("faction", -1)) != my_fac:
				continue
			var orad: float = squad_spot_radius(other)
			if orad <= 0.0:
				continue
			# Где отряд СТОИТ, а не где ему велели: место занимают тела
			var oc: Vector3 = _squad_spot_centre(other)
			if oc == Vector3.INF:
				continue
			var dx: float = spot.x - oc.x
			var dz: float = spot.z - oc.z
			var need: float = mine + orad + SQUAD_SPOT_GAP
			var d2: float = dx * dx + dz * dz
			if d2 >= need * need:
				continue
			var d: float = sqrt(d2)
			# Точно в центре чужого места — уходим по стабильному направлению,
			# выведенному из номера отряда: два прогона одного боя обязаны
			# дать одну картину
			if d < 0.01:
				var a: float = TAU * fposmod(float(sid) * 0.61803398875, 1.0)
				dx = cos(a)
				dz = sin(a)
				d = 1.0
			spot.x = oc.x + dx / d * need
			spot.z = oc.z + dz / d * need
			moved = true
		if not moved:
			break
	# Не уводим приказ дальше разумного: лучше слегка наложиться, чем увести
	# отряд в другой конец поля
	var sx: float = spot.x - wanted.x
	var sz: float = spot.z - wanted.z
	var shift: float = sqrt(sx * sx + sz * sz)
	if shift > SQUAD_SPOT_MAX_SHIFT:
		var k: float = SQUAD_SPOT_MAX_SHIFT / shift
		spot.x = wanted.x + sx * k
		spot.z = wanted.z + sz * k
	return land_target(spot)

## ── МЕСТО ОТРЯДА — ЭТО КУДА ОН ИДЁТ, А НЕ ГДЕ ОН СЕЙЧАС ───────────────────
## Первая версия брала текущий центр масс, и этого оказалось мало. Жалоба
## описывает ровно тот случай, когда разница решает: игрок шлёт отряды в одну
## точку ОДИН ЗА ДРУГИМ. Второй приказ отдаётся, пока первый отряд ещё в пути и
## физически далеко от точки, — по текущему центру он место НЕ занимает, и
## второй отряд спокойно целится туда же. Через десять секунд оба приходят и
## встают друг на друга (замер: одна перекрывающаяся пара, 1.04 м).
##
## Занятым место делает ПРИКАЗ, а не тело: post_pos бойцов и есть «куда мы
## идём и где будем стоять». Живой центр остаётся запасным ответом — для тех,
## кому приказа на движение не давали ни разу
func _squad_spot_centre(sid: int) -> Vector3:
	var men: Array = (squads[sid] as Dictionary)["members"]
	var live: Array = []
	for m in men:
		if not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead() or u.garrisoned:
			continue
		live.append(u)
	if live.is_empty():
		return Vector3.INF
	var posts: Vector3 = _squad_post_centre(live)
	if posts != Vector3.INF:
		return posts
	return _centroid_of(live)

func _sweep_reform(delta: float) -> void:
	_reform_sweep_t -= delta
	if _reform_sweep_t > 0.0:
		return
	_reform_sweep_t = REFORM_SWEEP_SEC
	var now: int = Time.get_ticks_msec()
	for key in squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = squads[key]
		var slots: Array = sq.get("slots", [])
		if slots.is_empty():
			continue
		# ── РАБОЧИХ НЕ СТРОИМ НИКОГДА ──────────────────────────────────────
		# Рабочий числится отрядом из одного человека, и разметка у такого
		# отряда завестись МОЖЕТ (её достраивает squad_close_ranks). Дальше
		# смыкание слало бы ему command_move — а тот сбрасывает и рубку, и
		# стройку, и добычу. Ровно это владелец и видел: «рабочие доходят до
		# объекта, делают пару процентов и бросают команду». У рабочего своя
		# работа и свой автомат состояний, и строй к нему отношения не имеет
		if String(sq.get("type", "")) == "worker":
			continue
		# ── В БОЮ НЕ СТРОИМСЯ, И ПОСЛЕ БОЯ — НЕ СРАЗУ ──────────────────────
		# Часы «когда нас перестали трогать» взводятся ЗДЕСЬ и только здесь.
		# Бой — это и есть внешнее воздействие; пока он идёт, отряду не до
		# строя, а сразу после него бойцы ещё расходятся с мест
		if squad_in_combat(sid):
			sq["calm_ms"] = now
			continue
		if now - int(sq.get("calm_ms", 0)) < int(REFORM_SETTLE_SEC * 1000.0):
			continue
		var men := squad_members(sid)
		if men.is_empty():
			continue
		var live := 0
		var moving := 0
		var busy := false
		var drift := 0
		for m in men:
			var u := m as Unit
			if u == null or u.is_dead():
				continue
			live += 1
			# Идущий не судится: идут и по приказу, и возвращаясь из этого же
			# смыкания. Отряд НА МАРШЕ (большинство в движении) пропускаем —
			# его посты уже переставлены в новые слоты
			if u.state == Unit.State.MOVING:
				moving += 1
				continue
			# Любой занятый боем отменяет смыкание для ВСЕГО отряда: строй —
			# дело мирное, а command_move снял бы бойцу цель
			if u.state == Unit.State.ATTACKING or u.attack_target != null \
					or u.target_lock or u.retreating:
				busy = true
				break
			if not u._post_valid:
				continue
			var dx: float = u.global_position.x - u.post_pos.x
			var dz: float = u.global_position.z - u.post_pos.z
			if dx * dx + dz * dz > REFORM_DRIFT * REFORM_DRIFT:
				drift += 1
		if busy or live == 0 or moving * 2 > live:
			continue
		if drift == 0:
			continue
		# ВСЁ. Одно действие на отряд, и оно уже написано: squad_close_ranks
		# рассаживает выживших по СВОЕЙ ЖЕ разметке (см. _slots_recentered) —
		# то есть отряд возвращается в свою форму, а не идёт куда-то ещё.
		# Своих остываний и своих проверок у неё достаточно
		squad_close_ranks(sid, true)


# ═════════════════════════════════════════════════════════════════════════════
# ТОПОТ МАРШИРУЮЩИХ ОТРЯДОВ
# ═════════════════════════════════════════════════════════════════════════════
# Вопрос «идёт ли пехота и как быстро» задаётся ОТРЯДУ, а не бойцу, и здесь для
# этого самое место: реестр отрядов лежит тут, а обход отрядов уже заведён
# соседней строкой (_sweep_reform).
#
# ПОЧЕМУ НЕ СОБЫТИЯМИ «ПОШЁЛ» / «ВСТАЛ». Их пришлось бы расставить по КАЖДОМУ
# пути, где отряд начинает и кончает движение: приказ, прибытие, вступление в
# бой, отход, гарнизон, гибель последнего. Любой забытый путь оставляет вечно
# топающий луп над стоящим отрядом — а луп, в отличие от удара мечом, сам не
# кончается никогда. Опрос состояния такой ошибки не допускает в принципе.

## Как часто пересматривать, кто марширует
const MARCH_SWEEP_SEC := 0.25
## Сколько бойцов опрашиваем в отряде. Здесь выборка УМЕСТНА, в отличие от
## смыкания строя (см. _formation_broken): «идёт ли отряд» — это про
## БОЛЬШИНСТВО состава, а не про тонкий коридор из нескольких человек
const MARCH_PROBE_MAX := 8
## Какая доля опрошенных должна идти, чтобы отряд считался марширующим.
## Половина, а не «хоть кто-то»: в стоящем строю всегда есть один-двое, кого
## подравнивает смыкание или расталкивание, и по ним топать всему отряду незачем
const MARCH_MOVING_FRACTION := 0.5

var _march_sweep_t: float = 0.0
## Переиспользуемый массив: пересобирать его четыре раза в секунду незачем
var _march_entries: Array = []

func _sweep_march_audio(delta: float) -> void:
	_march_sweep_t -= delta
	if _march_sweep_t > 0.0:
		return
	_march_sweep_t = MARCH_SWEEP_SEC
	if AudioManager == null or not is_instance_valid(AudioManager):
		return
	_march_entries.clear()
	for key in squads.keys():
		var sid: int = int(key)
		# ── ЧИТАЕМ СОСТАВ НАПРЯМУЮ, А НЕ ЧЕРЕЗ squad_members() ─────────────
		# squad_members() ТОЛЬКО ВЫГЛЯДИТ читателем. Он же — главный путь
		# расформирования: опустевший отряд он РАСПУСКАЕТ прямо в геттере.
		# Обход, который опрашивает ВСЕ отряды подряд, натыкается на пустые
		# постоянно — барак сначала заводит отряд, а бойцов доставляет
		# следующими кадрами, и такой отряд пуст совершенно законно. Первая
		# версия звала здесь squad_members и уничтожала свежие отряды раньше,
		# чем их успевали наполнить: семь заказов давали один отряд вместо
		# семи (поймал qa_squad, проверка 8)
		var men: Array = (squads[key] as Dictionary)["members"]
		var n: int = men.size()
		# Одиночка — не марш. Рабочий числится отрядом из одного человека, и
		# это ровно тот случай, который отсекается здесь заодно
		if n < 2:
			continue
		var stride: int = maxi(1, int(ceil(float(n) / float(MARCH_PROBE_MAX))))
		var live := 0
		var walking := 0
		var running := 0
		var cx := 0.0
		var cz := 0.0
		var i := 0
		while i < n:
			var u := men[i] as Unit
			i += stride
			if u == null or not is_instance_valid(u) or u.is_dead() or u is Worker:
				continue
			live += 1
			cx += u.global_position.x
			cz += u.global_position.z
			# ── ИДУЩИЙ В АТАКУ ТОЖЕ МАРШИРУЕТ ─────────────────────────────
			# Здесь стояло только State.MOVING, и на приказе атаки топот
			# ПРОПАДАЛ целиком: отряд, посланный на противника, идёт к нему в
			# состоянии ATTACKING — цель у него уже назначена, а ног он ещё не
			# донёс. С точки зрения игрока это тот же марш, только злее, и
			# молчать ему не за что.
			#
			# Отличаем «идёт к цели» от «дерётся» по дистанции: пока до цели
			# дальше длины руки, боец шагает. Считается это только по ВЫБОРКЕ
			# (MARCH_PROBE_MAX бойцов на отряд), то есть восемь замеров на
			# отряд четыре раза в секунду
			var afoot: bool = u.state == Unit.State.MOVING
			if not afoot and u.state == Unit.State.ATTACKING \
					and u.attack_target != null and is_instance_valid(u.attack_target):
				var tp: Vector3 = (u.attack_target as Node3D).global_position
				var tdx: float = tp.x - u.global_position.x
				var tdz: float = tp.z - u.global_position.z
				var rr: float = u.reach()
				afoot = tdx * tdx + tdz * tdz > rr * rr
			if afoot:
				walking += 1
				if u.sprinting:
					running += 1
		if live == 0:
			continue
		if float(walking) < float(live) * MARCH_MOVING_FRACTION:
			continue
		# Точка звука — среднее по ВЫБОРКЕ, а не медиана всего отряда. Медиана
		# заведена ради приказов (см. _centroid_of) и стоит полного прохода с
		# сортировкой; источнику звука хватает середины облака, а ошибка в пару
		# метров под ногами марширующей толпы неслышима
		var at := Vector3(cx / float(live), 0.0, cz / float(live))
		at.y = get_terrain_height(at.x, at.z)
		# Бегом — если бежит БОЛЬШИНСТВО идущих: смешанный случай (часть отряда
		# ещё разгоняется) звучит шагом, и это верно — переключаться туда-обратно
		# на каждом обходе хуже, чем чуть опоздать
		_march_entries.append({
			"sid": sid, "at": at, "run": running * 2 > walking,
		})
	AudioManager.march_report(_march_entries)

## ── СЛОЙ «ЗВОН ДОСПЕХОВ» ОТСЮДА СНЯТ (откат, заказ владельца) ──────────────
## Здесь стоял _jingle_armor(): раз в такт обхода он брал случайный из
## марширующих отрядов и запускал на его точке metal_punch с питч-шифтом.
## Владелец: «звучит как регулярный удар по кастрюле, надетой на голову».
##
## Механика была верной по цене (звенел ОТРЯД, а не боец, и не чаще раза в
## треть секунды на всю армию) и неверной по существу: удар металла остаётся
## ударом при любом питче и любой паузе, а поверх непрерывного лупа он ещё и
## слышится метрономом — ухо цепляется за единственное регулярное событие в
## шуме. Звон снаряжения записан ВНУТРИ самого лупа, отдельным слоем его
## изображать нечем — своего сэмпла кольчуги в проекте нет.
##
## Марш от этого не потерял ничего: _march_entries как собирались, так и
## собираются, и уходят в AudioManager.march_report тем же одним пакетом.

# ═════════════════════════════════════════════════════════════════════════════
# ПОГОНЯ — РЕШЕНИЕ ОТРЯДА, А НЕ КАЖДОГО БОЙЦА ПОРОЗНЬ
# ═════════════════════════════════════════════════════════════════════════════
# Жалоба владельца: «при преследовании задние бойцы отстают, теряют цель и
# начинают возвращаться в строй, а передние продолжают бежать. Отряд
# растягивается на полкарты».
#
# Так и было, и причина ровно одна: ПОВОДОК ПОГОНИ БЫЛ ЛИЧНЫМ. Каждый боец
# отсчитывал разрешённые PURSUIT_LIMIT метров от СВОЕЙ точки первого касания
# цели (Unit._pursuit_from). Передние касались раньше и ближе, задние — позже и
# дальше, а кто-то не касался вовсе. Дальше каждый принимал СВОЁ решение:
# передние продолжали гнать (их якорь ещё далеко), задние срывали поводок и
# уходили назад на пост. Отряд честно исполнял два противоположных приказа
# одновременно.
#
# Теперь якорь ОДИН НА ОТРЯД: его ставит тот, кто первым дотянулся до цели, и
# от него меряются все. Значит и поводок кончается у всех разом — отряд гонит
# единым фронтом и разом же возвращается.
#
# ПОЧЕМУ НЕ «ЛИДЕР ПРИНИМАЕТ РЕШЕНИЕ, ОСТАЛЬНЫЕ ИДУТ ЗА НИМ». Лидер — это ещё
# одна сущность, которую надо выбирать, переназначать при его гибели и
# синхронизировать с разметкой строя; ровно эту цену уже платит знаменосец, и
# заводить вторую такую же ради поводка незачем. Общий якорь даёт то же
# поведение (все решают одинаково) одним Vector3 на отряд.
#
# Хранится в отдельном словаре, а не в squads: якорь живёт КОРОЧЕ отряда и
# снимается при каждом новом приказе, а лезть за ним в общий словарь состава
# пришлось бы из горячей ветки подхода
var _pursuit_anchor: Dictionary = {}      # sid -> Vector3

## Якорь погони отряда. Vector3.INF — отряд ещё ни до кого не дотянулся
func squad_pursuit_anchor(sid: int) -> Vector3:
	if sid <= 0:
		return Vector3.INF
	var a: Variant = _pursuit_anchor.get(sid)
	return a if a != null else Vector3.INF

## Поставить якорь, если его ещё нет. Первым касанием и ставится
func squad_pursuit_anchor_set(sid: int, at: Vector3) -> void:
	if sid <= 0 or _pursuit_anchor.has(sid):
		return
	_pursuit_anchor[sid] = at

## Снять якорь: новый приказ, отход, конец погони
func squad_pursuit_release(sid: int) -> void:
	if sid > 0:
		_pursuit_anchor.erase(sid)

## ── ПО КАКОЙ ТОЧКЕ ВЫБИРАТЬ ЗНАМЕНОСЦА ────────────────────────────────────
## ПО МЕСТУ В РАЗМЕТКЕ, а не по тому, где боец стоит сию секунду. Разница
## решающая ровно в тот момент, ради которого возврат и заведён: смыкание рядов
## только что РАЗДАЛО приказы (command_move пишет слот в post_pos), но никто
## ещё не сделал ни шагу — бойцы стоят там, где их разбросала свалка. Выбор по
## текущим точкам дал бы знаменосца из середины кучи, и знамя честно поехало бы
## вместе с ним куда-то в тыл.
##
## Поста нет (боец только что из барака, приказа не было) — остаётся его
## нынешняя точка: другого ответа про «где он будет стоять» просто нет
func _bearer_anchor(u: Unit) -> Vector3:
	if u._post_valid:
		return u.post_pos
	return u.global_position

## ── ЗНАМЯ ПАДАЕТ НА ЗЕМЛЮ ──────────────────────────────────────────────────
## Отряд выбит целиком. Заказ владельца: упавшее копьё со знаменем запекается в
## ТОТ ЖЕ MultiMesh, что и тела, и живёт по их правилам — пятнадцать минут
## целым, потом полминуты разложения, и ни одного лишнего вызова отрисовки.
##
## Именно поэтому знамя с самого начала нарисовано ТЕКСТУРОЙ, а не геометрией
## (см. BannerArt): слой тел кладёт квад с лентой, и знамя ложится туда той же
## строчкой, что и павший копейщик. Ни своего слоя, ни своего срока, ни своего
## узла у него нет.
##
## Не ветеран — падать нечему, и это не особый случай: у отряда без звания
## знамени не было вовсе
func _drop_squad_banner(sid: int) -> void:
	if not squads.has(sid):
		return
	var sq: Dictionary = squads[sid]
	var lvl: int = int(sq.get("level", 0))
	if lvl <= 0 or main == null or not is_instance_valid(main):
		return
	var at: Vector3 = sq.get("last_pos", Vector3.ZERO)
	if at == Vector3.ZERO:
		return
	# ── ЧИТАЕМ СЕЙЧАС, КЛАДЁМ ПОТОМ ────────────────────────────────────────
	# Сюда приходят из Unit._exit_tree — то есть в тот самый момент, когда
	# движок ПЕРЕСТРАИВАЕТ ДЕРЕВО. add_child в этот момент отбивается («Parent
	# node is busy setting up children»), а слою тел он нужен: первое тело
	# каждой ленты заводит свой MultiMeshInstance3D. Обычные трупы этой грабли
	# не знают, потому что ложатся из take_damage, посреди физического тика.
	#
	# Поэтому уровень и точку снимаем ЗДЕСЬ (через кадр записи о них уже не
	# будет — отряд стирается следующей же строкой), а саму укладку откладываем
	if lvl > 0:
		call_deferred("_lay_fallen_banner", lvl, at, sid)

## Положить упавшее знамя. Отложенный хвост _drop_squad_banner — см. разбор там
func _lay_fallen_banner(lvl: int, at: Vector3, seed_id: int) -> void:
	if main == null or not is_instance_valid(main):
		return
	var tex: Texture2D = _BannerArt.texture_for(lvl)
	if tex == null:
		return
	corpses.spawn_prop(tex, 1, _SquadBanner.PIXEL_SIZE, at, seed_id,
		main.world_root(), get_terrain_height(at.x, at.z))

## Живые бойцы отряда (пустой массив — отряда нет). Заодно чистит битые ссылки.
# ═════════════════════════════════════════════════════════════════════════════
# УКАЗАТЕЛИ ОТДАННОГО ПРИКАЗА
# ═════════════════════════════════════════════════════════════════════════════
## Запомнить, что отряду только что приказали. Зовёт SelectionManager из
## обработчика ПКМ — там же, где приказ реально раздаётся бойцам
func squad_note_order(sid: int, kind: int, pos: Vector3, target: Node = null) -> void:
	if sid <= 0:
		return
	squad_orders[sid] = {"kind": kind, "pos": pos, "target": target}

func squad_clear_order(sid: int) -> void:
	squad_orders.erase(sid)

## Насколько близко к точке приказа отряд считается ДОШЕДШИМ. Метка снимается
## по этому радиусу, а не по «все до единого встали»: в строю всегда найдётся
## отстающий, и метка залипала бы навсегда — ровно та жалоба, с которой всё
## началось
const ORDER_MARK_ARRIVE := 3.0

## Пересобрать указатели под ТЕКУЩЕЕ выделение. Каждый кадр, но дёшево:
## выделенных отрядов единицы, а работа на отряд — один медианный центр.
##
## Здесь же приказ и УМИРАЕТ: дошли до точки — метка снята; цель приказа
## погибла — снята тоже. Ничего не надо гасить руками из мест вызова
func _refresh_order_marks(delta: float) -> void:
	_order_phase += delta
	var sm = null
	if main != null:
		sm = main.get("selection_manager")
	if sm == null:
		sel_decals.set_move_marks([], null, 0.0)
		sel_decals.set_order_targets([], null)
		return
	var world = main.world_root()
	# Какие отряды сейчас выделены. Множеством, а не списком: один отряд
	# встречается в выделении столько раз, сколько в нём бойцов
	var sids: Dictionary = {}
	for u in sm.selected_units:
		if u == null or not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu == null or uu.squad_id <= 0:
			continue
		sids[uu.squad_id] = true

	var dests: Array = []
	var foes: Array = []
	var done: Array = []
	for sid in sids:
		var ord: Dictionary = squad_orders.get(sid, {})
		if ord.is_empty():
			continue
		if int(ord.get("kind", ORDER_MOVE)) == ORDER_ATTACK:
			var tgt = ord.get("target")
			# Цель истреблена (или снесена) — приказ исполнен, показывать нечего
			if tgt == null or not is_instance_valid(tgt) 					or (tgt is Unit and (tgt as Unit).is_dead()) 					or (tgt is Building and (tgt as Building).is_dead()):
				done.append(sid)
				continue
			# Кольцами обводится ВЕСЬ отряд цели, а не один боец: приказ отдан
			# по отряду, и подсветка обязана отвечать тем же
			if tgt is Unit and (tgt as Unit).squad_id > 0:
				for m in squad_members((tgt as Unit).squad_id):
					if is_instance_valid(m) and not (m as Unit).is_dead():
						foes.append(m)
			elif tgt is Unit or tgt is Building:
				# ЗДАНИЕ ИДЁТ СЮДА ЖЕ, а не отдельным слоем: приказ «снести вон
				# ту постройку» держится и показывается ровно так же, как приказ
				# по чужому отряду, — кольцо на цели до её гибели. Слой сам
				# растянет кольцо по основанию (SelectionDecalRenderer)
				foes.append(tgt)
			continue
		var goal: Vector3 = ord.get("pos", Vector3.ZERO)
		var alive_men := squad_members(sid)
		# Отряда не осталось — приказу некому исполняться, метку снимаем.
		# Без этого _centroid_of пустого списка отвечает НУЛЁМ, от него до цели
		# заведомо далеко, и кольцо висело бы вечно
		if alive_men.is_empty():
			done.append(sid)
			continue
		var c: Vector3 = _centroid_of(alive_men)
		if Vector2(c.x - goal.x, c.z - goal.z).length() <= ORDER_MARK_ARRIVE:
			done.append(sid)
			continue
		dests.append(Vector3(goal.x, get_terrain_height(goal.x, goal.z), goal.z))
	for sid in done:
		squad_orders.erase(sid)
	sel_decals.set_move_marks(dests, world, _order_phase)
	sel_decals.set_order_targets(foes, world)

var _order_phase: float = 0.0

func squad_members(squad_id: int) -> Array:
	if not squads.has(squad_id):
		return []
	var members: Array = squads[squad_id]["members"]
	var alive: Array = []
	# ── ОТЧЕГО ОТРЯД ОПУСТЕЛ: ПОГИБ ИЛИ РАЗОБРАН ───────────────────────────
	# Это ГЛАВНЫЙ путь расформирования выбитого отряда: последнего убили, и
	# первый же запрос состава это заметил. Но тем же путём отряд пустеет,
	# когда его бойцов просто освободили живыми (стенды, смена сцены), — а
	# знамя на землю ронять полагается только за ПОГИБШИХ, иначе за ордой
	# тянется след из знамён её же живых отрядов
	var had_dead := false
	for m in members:
		if not is_instance_valid(m):
			continue
		if m.is_dead():
			had_dead = true
		else:
			alive.append(m)
	if alive.size() != members.size():
		squads[squad_id]["members"] = alive
	if alive.is_empty():
		_disband_squad(squad_id, had_dead)
	return alive

## Весь отряд, в котором состоит боец. Одиночка без отряда — сам себе отряд:
## так вызывающему не нужно разбирать особый случай
func squad_of(unit: Node) -> Array:
	if unit == null or not is_instance_valid(unit):
		return []
	var sid: int = unit.squad_id
	if sid <= 0:
		return [unit]
	var members := squad_members(sid)
	return members if not members.is_empty() else [unit]

# ─────────────────────────────────────────────────────────────────────────────
# РАЗМЕТКА СТРОЯ КАК СВОЙСТВО ОТРЯДА (см. scripts/units/SquadFormation.gd)
#
# Приказ на построение раздаёт бойцам точки и раньше на этом заканчивался.
# Теперь список точек, курс фронта и режим шага остаются У ОТРЯДА — благодаря
# этому при потерях можно сомкнуть ряды: выживших пересаживают на ПЕРВЫЕ места
# разметки, и задняя шеренга сама переходит вперёд на места павших.
# ─────────────────────────────────────────────────────────────────────────────
const _SqFormation := preload("res://scripts/units/SquadFormation.gd")

## Запомнить разметку строя за отрядом. Зовут SelectionManager и EnemyAI сразу
## после выдачи приказа на построение
func squad_set_formation(sid: int, slots: Array, course: Vector3, slow: bool) -> void:
	if sid <= 0 or not squads.has(sid):
		return
	var sq: Dictionary = squads[sid]
	sq["slots"]      = slots.duplicate()
	# Новая разметка — новая линия: накопленная вмятина от конницы обнуляется,
	# иначе потолок DENT_MAX_TOTAL остался бы выбранным на всю партию
	sq["dent"]       = 0.0
	sq["course"]     = course
	sq["slow"]       = slow
	# Сколько бойцов было на момент приказа: по убыли считается доля потерь
	sq["at_order"]   = squad_members(sid).size()
	sq["reshuffled"] = 0
	# Новый приказ — новый марш: счётчик дошедших обнуляется, прибавка снимается
	sq["arrived"]    = 0
	sq["catch_up"]   = false
	_push_catch_up(sid, false)

## ── ПОДТЯГИВАНИЕ ХВОСТА ─────────────────────────────────────────────────────
## Отряд идёт единым квадратом, но приходит он всегда «рассыпухой»: передние
## шеренги встают на места, а задние ещё тянутся — тем сильнее, чем длиннее был
## марш и чем больше их растащило на обходе деревьев. Квадрат запечатывается
## заметно позже, чем отряд формально дошёл.
##
## Правило: как только доля дошедших переваливает CATCH_UP_TRIGGER, ОСТАВШИЕСЯ
## получают прибавку к скорости и быстро закрывают строй. Прибавка снимается
## сама вместе с приказом (squad_set_formation) — отдельного таймера не нужно.
##
## Порог по ДОЛЕ, а не по числу: у отряда в 4 человека и у отряда в 50 «первые
## ряды встали» наступает в разные моменты
const CATCH_UP_TRIGGER := 0.35

## Боец доложил, что встал на своё место
func squad_note_arrival(sid: int) -> void:
	if sid <= 0 or not squads.has(sid):
		return
	var sq: Dictionary = squads[sid]
	if bool(sq.get("catch_up", false)):
		return
	var n: int = int(sq.get("arrived", 0)) + 1
	sq["arrived"] = n
	var total: int = maxi(squad_members(sid).size(), 1)
	if float(n) / float(total) >= CATCH_UP_TRIGGER:
		squad_set_catch_up(sid, true)

## ── ПРИБАВКА РАЗДАЁТСЯ, А НЕ ОПРАШИВАЕТСЯ ───────────────────────────────────
## Признак общий на весь отряд и переключается ровно дважды за марш (взводится
## здесь, снимается новым приказом), а спрашивал его КАЖДЫЙ идущий боец в
## КАЖДОМ кадре — межобъектный вызов со словарным поиском на ровном месте.
## Теперь отряд сам раскладывает флаг по бойцам в момент переключения, и
## Unit._effective_speed читает своё поле
## ЕДИНСТВЕННАЯ ТОЧКА ПЕРЕКЛЮЧЕНИЯ. Запись прямо в squads[sid]["catch_up"] в
## обход этой функции до бойцов больше НЕ доходит
func squad_set_catch_up(sid: int, value: bool) -> void:
	if sid <= 0 or not squads.has(sid):
		return
	(squads[sid] as Dictionary)["catch_up"] = value
	_push_catch_up(sid, value)

func _push_catch_up(sid: int, value: bool) -> void:
	for m in squad_members(sid):
		var u := m as Unit
		if u != null:
			u._catch_up = value

## Пора ли отстающим прибавить шагу
func squad_catching_up(sid: int) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	return bool((squads[sid] as Dictionary).get("catch_up", false))

## Курс строя отряда: единый для всех «куда у нас перёд».
## Vector3.ZERO — разметки нет, и каждый боец определяет фронт сам
func squad_course(sid: int) -> Vector3:
	if sid <= 0 or not squads.has(sid):
		return Vector3.ZERO
	var sq: Dictionary = squads[sid]
	if (sq.get("slots", []) as Array).is_empty():
		return Vector3.ZERO
	return sq.get("course", Vector3.ZERO)

## Есть ли у отряда действующая разметка строя
func squad_has_formation(sid: int) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	return not (squads[sid].get("slots", []) as Array).is_empty()

## ── ВМЯТИНА В СТРОЮ ОТ УДАРА ТЯЖЁЛОЙ КОННИЦЫ ────────────────────────────────
## Заказ владельца: кабан, влетевший в шеренгу, обязан ЗРИМО прогнуть её, а не
## просто отпихнуть пару моделей.
##
## Почему одного толчка мало. Отброшенный боец держится за своё МЕСТО В
## РАЗМЕТКЕ (`slots`): первое же смыкание рядов вернёт его туда, и от удара не
## останется следа. Гнуть надо саму разметку — тогда строй перестраивается уже
## прогнутым, и вмятина живёт, пока отряд не получит новый приказ.
##
## ЧТО ИМЕННО ДЕЛАЕМ. Места в радиусе DENT_RADIUS от точки удара уезжают НАЗАД
## по направлению удара, с затуханием от центра к краю: получается вмятина, а
## не сдвиг всей линии. Урона это не касается вовсе — двигаются только точки.
##
## ПОЧЕМУ ЕСТЬ ПОТОЛОК. Без него отряд, в который долго бьёт конница, уезжал бы
## разметкой через всю карту, и «сомкнуть ряды» отправляло бы выживших в поле
## за краем боя. Суммарная вмятина одного места ограничена DENT_MAX_TOTAL.
##
## ПОЧЕМУ НЕ ЗОВЁМ ЗДЕСЬ ЖЕ squad_close_ranks. Смыкание шлёт command_move
## КАЖДОМУ бойцу, а он снимает цель атаки: в разгар рубки это остановило бы бой
## (ровно от этого и заведено правило squad_in_combat). Вмятина ждёт своего
## часа — её подхватит первое же штатное смыкание, когда драка закончится
const DENT_RADIUS := 3.0
const DENT_MAX_TOTAL := 4.0

func squad_dent(sid: int, at: Vector3, dirn: Vector3, depth: float) -> void:
	if sid <= 0 or depth <= 0.0 or not squads.has(sid):
		return
	var sq: Dictionary = squads[sid]
	var slots: Array = sq.get("slots", [])
	if slots.is_empty():
		return
	var d := Vector3(dirn.x, 0.0, dirn.z)
	if d.length_squared() < 1e-6:
		return
	d = d.normalized()
	# Сколько эта разметка уже прогнута. Считается отрядом, а не местом:
	# иначе пришлось бы держать по числу на каждый слот
	var used: float = float(sq.get("dent", 0.0))
	if used >= DENT_MAX_TOTAL:
		return
	var step: float = minf(depth, DENT_MAX_TOTAL - used)
	var r2: float = DENT_RADIUS * DENT_RADIUS
	var touched := false
	for i in range(slots.size()):
		var p: Vector3 = slots[i]
		var dx: float = p.x - at.x
		var dz: float = p.z - at.z
		var q: float = dx * dx + dz * dz
		if q > r2:
			continue
		# Затухание от центра удара к краю: в точке удара — полный шаг, на
		# границе радиуса — ноль. Без него вмятина была бы плоской ступенькой
		var k: float = 1.0 - sqrt(q) / DENT_RADIUS
		slots[i] = p + d * (step * k)
		touched = true
	if touched:
		sq["dent"] = used + step

## Насколько разметка отряда уже прогнута ударами конницы (стенды)
func squad_dent_depth(sid: int) -> float:
	if sid <= 0 or not squads.has(sid):
		return 0.0
	return float((squads[sid] as Dictionary).get("dent", 0.0))

## Снять разметку: отряд получил приказ, не связанный со строем (атака, гарнизон)
func squad_clear_formation(sid: int) -> void:
	if sid <= 0 or not squads.has(sid):
		return
	(squads[sid] as Dictionary)["slots"] = []
	(squads[sid] as Dictionary)["dent"] = 0.0

## ── ОТРЯД «В БОЮ» ────────────────────────────────────────────────────────────
## Раньше "сомкнуть ряды" звалось БЕЗУСЛОВНО каждым бойцом, у которого лично
## закончилась стычка — независимо от того, дерутся ли ЕЩЁ другие бойцы того
## же отряда. close_ranks() шлёт command_move() ВСЕМ живым членам отряда, а
## command_move() у бойца с живой целью эту цель снимает — то есть смыкание
## выдёргивало из боя ещё дерущихся соседей. Мгновение спустя авто-агро видело
## рядом живого врага и вело их обратно — та самая "пляска вперёд-назад".
## Здесь — единственная точка правды "идёт ли ещё бой у этого отряда":
## либо жива чья-то персональная цель прямо сейчас, либо был урон недавно
## (лучники бьют издали, в ближний бой ни с кем не вступая).
const RECENT_HIT_WINDOW_MS := 3000

func squad_in_combat(sid: int) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	var sq: Dictionary = squads[sid]
	var last_hit: int = int(sq.get("last_hit_ms", -RECENT_HIT_WINDOW_MS * 10))
	if Time.get_ticks_msec() - last_hit < RECENT_HIT_WINDOW_MS:
		return true
	for m in squad_members(sid):
		var u := m as Unit
		if u != null and not u.is_dead() and u.attack_target != null:
			return true
	return false

## Боец отряда получил урон (см. Unit.take_damage). Отмечает время и, один раз
## на окно, заводит отложенную повторную попытку смыкания — иначе отряд, по
## которому долбят издали без ближнего контакта, никогда САМ не заметит конец
## боя: никто из бойцов не проходит через "цель погибла", чтобы переиздать
## squad_close_ranks
func squad_mark_hit(sid: int) -> void:
	if sid <= 0 or not squads.has(sid):
		return
	var sq: Dictionary = squads[sid]
	sq["last_hit_ms"] = Time.get_ticks_msec()
	if bool(sq.get("reform_check_pending", false)):
		return
	sq["reform_check_pending"] = true
	_arm_reform_check(sid)

func _arm_reform_check(sid: int) -> void:
	get_tree().create_timer(float(RECENT_HIT_WINDOW_MS) / 1000.0 + 0.1).timeout.connect(
		_reform_check.bind(sid))

## ПРОВЕРКА ОТЛОЖЕНА, А НЕ ПОТЕРЯНА. Раньше срабатывание таймера внутри ещё
## незакрытого окна обстрела съедало ЕДИНСТВЕННУЮ попытку: squad_mark_hit при
## уже взведённой проверке только обновляет отметку времени и таймер заново НЕ
## ставит. Отряд, у которого бой кончился сразу после такого холостого
## срабатывания, навсегда оставался в разорванном строю — редко, но
## воспроизводимо (qa_combat_lock, проверка 3). Теперь проверка переносится на
## следующее окно, пока отряд действительно не выйдет из боя
func _reform_check(sid: int) -> void:
	if not squads.has(sid):
		return
	if squad_in_combat(sid):
		_arm_reform_check(sid)
		return
	(squads[sid] as Dictionary)["reform_check_pending"] = false
	squad_close_ranks(sid, true)

## Переносит разметку строя (список абсолютных точек) так, чтобы её
## геометрический центр совпал с ТЕКУЩИМ центром масс живых бойцов — форма и
## интервалы строя не меняются, меняется только точка привязки. Без этого
## победивший на новом месте отряд топал бы обратно к точке ИСХОДНОГО приказа
func _slots_recentered(slots: Array, men: Array) -> Array:
	if slots.is_empty() or men.is_empty():
		return slots
	var old_center := Vector3.ZERO
	for s in slots:
		old_center += (s as Vector3)
	old_center /= float(slots.size())
	var new_center := Vector3.ZERO
	var n := 0
	for m in men:
		var u := m as Unit
		if u != null and not u.is_dead():
			new_center += u.global_position
			n += 1
	if n == 0:
		return slots
	new_center /= float(n)
	var delta := new_center - old_center
	delta.y = 0.0
	var out: Array = []
	for s in slots:
		out.append((s as Vector3) + delta)
	return out

## СОМКНУТЬ РЯДЫ ПОСЛЕ ПОТЕРЬ. Зовётся при гибели бойца и по выходу из боя;
## сама решает, надо ли перестраиваться прямо сейчас (см. пороги в SquadFormation)
func squad_close_ranks(sid: int, force: bool = false) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	var sq: Dictionary = squads[sid]
	var men := squad_members(sid)
	if men.is_empty():
		return false
	# ── ЗАМОК ЦЕЛИ СИЛЬНЕЕ СМЫКАНИЯ ─────────────────────────────────────────
	# Пока отряд исполняет приказ игрока (см. Unit.target_lock), перестраивать
	# его нельзя: close_ranks шлёт command_move КАЖДОМУ бойцу, а command_move
	# снимает замок — приказ игрока отменился бы сам собой на первой же смерти
	# в чужом отряде. Разметка при этом ЦЕЛА и ждёт конца боя
	for m in men:
		var lu := m as Unit
		if lu != null and not lu.is_dead() and lu.target_lock:
			return false
	var slots: Array = sq.get("slots", [])
	# ── СТРОЙ ЕСТЬ ВСЕГДА ───────────────────────────────────────────────────
	# Разметки может не быть вовсе: отряд вышел из барака и сразу пошёл в атаку,
	# ни одного приказа движения ему не давали. Раньше это означало «строиться
	# не во что» — отряд так и оставался стоять бесформенным пятном, повёрнутым
	# кто куда (жалоба владельца про «фантомных солдат с копьями в пустую
	# сторону»). Теперь на этот случай форма достраивается по числу выживших
	if slots.is_empty() and force and not _squad_on_the_move(men):
		slots = _default_block_slots(sid, men)
		if slots.is_empty():
			return false
		sq["slots"] = slots
		# Отряд получил разметку впервые — заодно фиксируем и «численность на
		# момент приказа», иначе следующее смыкание ПО ПОТЕРЯМ (force = false)
		# делило бы на ноль-размер и не срабатывало никогда
		sq["at_order"] = men.size()
	if slots.is_empty():
		return false
	# Потери ещё несущественны — строй переступать незачем.
	# force = true снимает именно ЭТОТ порог (остыв всё равно действует): так
	# просит отряд, ВЫШЕДШИЙ ИЗ БОЯ. Потерь могло не быть вовсе, а строй всё
	# равно смят — свалка растаскивает бойцов с мест ничуть не хуже гибели.
	#
	# at_order («сколько было в отряде на момент приказа») проверяется ТОЛЬКО
	# здесь и только ради этой доли. Раньше на нём стоял общий ранний выход
	# `if at_order <= 0: return false`, и он молча убивал ВЕСЬ возврат в строй у
	# отряда, которому никогда не давали строевого приказа: at_order у такого
	# нулевой, до смыкания дело не доходило вовсе, и после боя он оставался
	# бесформенным пятном — ровно «фантомные солдаты с копьями в пустую
	# сторону» из жалобы (замер зондом: slots построены, а reshuffled = 0).
	# Для force-пути это число не значит ничего, поэтому там его и не спрашиваем
	if not force:
		var at_order: int = int(sq.get("at_order", men.size()))
		if at_order <= 0:
			return false
		var loss: float = float(at_order - men.size()) / float(at_order)
		if loss < _SqFormation.RESHUFFLE_MIN_LOSS:
			return false
	var now: int = Time.get_ticks_msec()
	if now - int(sq.get("reshuffled", 0)) < _SqFormation.RESHUFFLE_COOLDOWN_MS:
		return false
	sq["reshuffled"] = now
	var use_slots: Array = slots
	if force:
		# ГДЕ ИМЕННО СТРОИТЬСЯ ПОСЛЕ БОЯ — ДВА РАЗНЫХ СЛУЧАЯ.
		#
		# 1) ОТРЯД ПОСЛАЛИ (приказ игрока): строится ПО МЕСТУ БОЯ. Иначе отряд,
		#    выигравший драку не там, куда его изначально вели, маршировал бы
		#    обратно на устаревшую точку (это уже чинили — см. _slots_recentered).
		# 2) ОТРЯД УШЁЛ ПОМОГАТЬ САМ (авто-агро, метка "helped"): возвращается на
		#    СВОЙ ПОСТ — «после победы полностью восстанавливает исходную позицию
		#    и шеренгу». Пост у бойцов уже есть (Unit.post_pos), его назначает
		#    последний приказ на движение, поэтому «исходная позиция» — это
		#    именно то место, откуда сосед сорвался на помощь
		var anchor := Vector3.INF
		if bool(sq.get("helped", false)):
			anchor = _squad_post_centre(men)
		if anchor.x != INF:
			use_slots = _slots_moved_to(slots, anchor)
			sq["helped"] = false
		else:
			use_slots = _slots_recentered(slots, men)
	_SqFormation.close_ranks(men, use_slots, sq.get("course", Vector3.ZERO),
		bool(sq.get("slow", false)))
	# ── ЗНАМЯ ВОЗВРАЩАЕТСЯ НА СВОЁ МЕСТО ВМЕСТЕ СО СТРОЕМ ───────────────────
	# Заказ владельца: знамя стоит у бойца ПЕРВОГО РЯДА С КРАЙНЕГО ЛЕВОГО КРАЯ,
	# а если в бою строй перемешался — возвращается туда при перестроении.
	#
	# Именно ЗДЕСЬ, и это единственное правильное место: смыкание рядов и есть
	# «конец экшн-сцены». В бою знаменосец меняется по другому правилу
	# (ближайший к павшему — иначе знамя уезжало бы в тыл через полстроя), и
	# трогать его, пока драка идёт, нельзя.
	#
	# Порядок важен: ПОСЛЕ close_ranks. Она рассаживает выживших по местам
	# разметки, и выбор «кто левее в первом ряду» обязан считаться по НОВЫМ
	# местам, а не по тому, где бойцы стояли в свалке
	if int(sq.get("level", 0)) > 0:
		_assign_bearer(sid)
	return true

## Разметка, перенесённая ЦЕЛИКОМ так, чтобы её центр лёг в точку anchor.
## Форма строя при этом не меняется — сдвигается только место
func _slots_moved_to(slots: Array, anchor: Vector3) -> Array:
	if slots.is_empty():
		return slots
	var c := Vector3.ZERO
	for s in slots:
		c += (s as Vector3)
	c /= float(slots.size())
	var delta := anchor - c
	delta.y = 0.0
	var out: Array = []
	for s in slots:
		out.append((s as Vector3) + delta)
	return out

# ═════════════════════════════════════════════════════════════════════════════
# БОЕВОЙ КЛИЧ ОТРЯДА
#
# Звучит при смене стойки и при получении приказа на марш. Голос принадлежит
# ОТРЯДУ, а не бойцу: один клич на отряд из его центра масс. Выделили пять
# отрядов и переключили стойку — пять кличей из пяти разных точек поля, то
# самое «многоголосье» из задания.
#
# ПОЧЕМУ 3D, А НЕ AudioStreamPlayer2D (как было написано в задании). Игра
# трёхмерная: пул голосов — AudioStreamPlayer3D, слушатель висит в точке
# фокуса камеры (см. _listener_node), спад громкости считается по расстоянию в
# метрах мира. AudioStreamPlayer2D живёт в координатах экрана и о мире не знает
# ничего — он бы не давал ни удаления при отъезде камеры, ни панорамы. Просьба
# «чтобы при отдалении и смещении камеры сохранилась объёмная акустика» именно
# 3D-путём и выполняется, причём он в проекте уже настроен.
# ═════════════════════════════════════════════════════════════════════════════
## Как часто ОДИН отряд вправе крикнуть. Клик мышью ничем не ограничен: без
## этого порога десять приказов подряд дают десять наложенных кличей и кашу в
## динамиках. Полторы секунды — чуть больше длины самого сэмпла.
## Это порог для СМЕНЫ СТОЙКИ: она случается редко и по явному нажатию кнопки,
## поэтому отвечать на неё звуком можно каждый раз
const CRY_COOLDOWN_MS := 1500

## ── ПРИКАЗ НА МАРШ: ОТДЕЛЬНЫЕ, НАМНОГО БОЛЕЕ СТРОГИЕ ОГРАНИЧЕНИЯ ────────────
## Марш — это микроконтроль: игрок кликает по земле десятки раз в минуту, и
## клич на каждый клик превращается в непрерывный ор. Поэтому здесь две меры
## сразу, и они дополняют друг друга:
##   • откат в несколько секунд — отряд молчит между всплесками;
##   • шанс срабатывания — даже когда откат прошёл, клич звучит «через раз»,
##     из-за чего команды перестают звучать одинаково и механически.
## Роль шанса нельзя заменить одним откатом: с чистым откатом клич звучит
## РОВНО раз в N секунд, то есть снова превращается в метроном
const CRY_ORDER_COOLDOWN_MS := 4000
const CRY_ORDER_CHANCE := 0.5

# ── ЛЕКАРСТВО ОТ «ЭЛЕКТРОННОГО» ПРИЗВУКА (гребенчатая фильтрация) ────────────
# Один и тот же файл, запущенный несколькими отрядами В ОДНУ МИЛЛИСЕКУНДУ,
# складывается сам с собой: волны совпадают по фазе, часть частот гасится, и
# вместо хора слышен металлический «робот». Разводим тремя независимыми
# способами сразу — по отдельности ни один не убирает эффект полностью:
#   1) ВЫСОТА  — своя расстройка каждому голосу (AudioManager, "pitch");
#   2) ВРЕМЯ   — эта задержка: отряды кричат вразнобой, а не по команде;
#   3) ЧИСЛО   — кричат не все, а несколько случайных (CRY_MAX_VOICES).
## Разброс момента начала, секунды. Хватает, чтобы фазы разошлись, и мало,
## чтобы клич всё ещё читался как ОДИН общий выкрик, а не перекличка
const CRY_SPREAD_SEC := 0.18
## Сколько отрядов кричит, сколько бы их ни выделили. Больше четырёх голосов
## толпы не добавляют — только загружают микшер и множат наложения
const CRY_MAX_VOICES := 4

## Время последнего клича по отряду. Отдельный словарь, а не поле в squads:
## запись отряда переживает пересборку, а звук — вещь сиюминутная
var _cry_last: Dictionary = {}

## Сколько раз отряд РЕШИЛ крикнуть. Считается в момент решения, а не выдачи:
## сам звук уходит с микро-задержкой (CRY_SPREAD_SEC), и по счётчику
## AudioManager его в тот же кадр уже не видно. Читают стенды
var cry_decisions: int = 0

## КРИКНУТЬ ОДНИМ ОТРЯДОМ. false — не крикнул (рабочие, откат, отряда нет).
## Рабочие молчат намеренно: клич принадлежит пехоте, артель на стройке орать
## «в атаку» не должна
func squad_battle_cry(sid: int, chance: float = 1.0,
		cooldown_ms: int = CRY_COOLDOWN_MS) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	var men := squad_members(sid)
	if men.is_empty():
		return false
	# Отряд без оружия (рабочие) клич не подаёт
	var voice: Unit = null
	for m in men:
		var u := m as Unit
		if u != null and not u.is_dead() and u.attack_damage > 0.0:
			voice = u
			break
	if voice == null:
		return false
	var now: int = Time.get_ticks_msec()
	if now - int(_cry_last.get(sid, -CRY_COOLDOWN_MS * 10)) < cooldown_ms:
		return false
	# ЖРЕБИЙ БРОСАЕТСЯ ПОСЛЕ ОТКАТА И НЕ ТРАТИТ ЕГО.
	# Порядок важен: если бы неудачный бросок взводил откат, отряд молчал бы
	# половину положенного времени ДВАЖДЫ — и шанс, и откат резали бы одно и то
	# же. Сейчас проигранный жребий просто пропускает этот приказ, а следующий
	# клик пробует заново: получается «через раз», а не «раз в четыре секунды
	# с вероятностью половина»
	if chance < 1.0 and randf() > chance:
		return false
	_cry_last[sid] = now
	cry_decisions += 1
	# ── КРИЧИМ НЕ СРАЗУ, А С МИКРО-ЗАДЕРЖКОЙ ────────────────────────────────
	# Разброс до CRY_SPREAD_SEC разводит одновременные кличи по времени, чтобы
	# они не складывались фаза в фазу (см. шапку у CRY_SPREAD_SEC).
	# process_always = false: на паузе игра молчит — иначе отложенный клич
	# выстрелил бы поверх замершей картинки
	var delay: float = randf_range(0.0, CRY_SPREAD_SEC)
	if delay <= 0.001:
		_cry_now(sid)
		return true
	var t := get_tree().create_timer(delay, false)
	t.timeout.connect(_cry_now.bind(sid))
	return true

## Собственно выдача звука. Отдельно от решения: между решением и звуком
## проходит до CRY_SPREAD_SEC, и за это время отряд может погибнуть целиком
func _cry_now(sid: int) -> void:
	if not squads.has(sid) or squad_members(sid).is_empty():
		return
	# Из ЦЕНТРА МАСС, а не от первого попавшегося бойца: отряд — это блок, и
	# его голос должен идти из середины блока, иначе при развороте камеры звук
	# скачет по флангам вслед за тем, кто оказался нулевым в списке.
	# Считается ЗДЕСЬ, а не при решении: за время задержки отряд успевает
	# сдвинуться, и звук должен идти оттуда, где он сейчас
	AudioManager.play_3d("battle_cry", squad_centroid(sid))

## КРИКНУТЬ ВСЕМИ ОТРЯДАМИ ВЫДЕЛЕНИЯ. Возвращает число реально крикнувших.
## Отряды разбираются по squad_id, поэтому двадцать бойцов одного отряда дают
## ОДИН клич, а пять отрядов — пять
func selection_battle_cry(units: Array, chance: float = 1.0,
		cooldown_ms: int = CRY_COOLDOWN_MS) -> int:
	# Сначала собираем отряды выделения — по одному разу каждый
	var sids: Array = []
	for u in units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var sid: int = (u as Unit).squad_id
		if sid > 0 and not (sid in sids):
			sids.append(sid)
	# ── КРИЧАТ НЕ ВСЕ, А НЕСКОЛЬКО СЛУЧАЙНЫХ ────────────────────────────────
	# Выборка именно СЛУЧАЙНАЯ, а не «первые N по списку»: иначе при выделении
	# восьми отрядов голос подавали бы всегда одни и те же четыре, и хор звучал
	# бы одинаково от приказа к приказу. Заодно это снимает нагрузку с микшера
	# и уменьшает число одновременных наложений одного файла
	if sids.size() > CRY_MAX_VOICES:
		sids.shuffle()
		sids.resize(CRY_MAX_VOICES)
	var n := 0
	for sid2 in sids:
		if squad_battle_cry(int(sid2), chance, cooldown_ms):
			n += 1
	return n

## КЛИЧ ПО ПРИКАЗУ (марш / атака) — с шансом и длинным откатом.
## Отдельная функция, а не аргументы по месту вызова: правило «на приказ орут
## реже и через раз» одно на все приказы, и жить оно должно в одном месте
func order_battle_cry(units: Array) -> int:
	return selection_battle_cry(units, CRY_ORDER_CHANCE, CRY_ORDER_COOLDOWN_MS)

## ── «ОТРЯД УХОДИЛ ПОМОГАТЬ СОСЕДУ» ──────────────────────────────────────────
## Ставит авто-агро, когда боец идёт к врагу, а не бьёт с места (Unit.
## _check_auto_aggro); снимает любой приказ игрока на движение. По этой метке
## squad_close_ranks решает, ГДЕ строиться после боя: помогавший сосед
## возвращается на свой пост, а посланный игроком отряд встаёт по месту боя
func squad_mark_helped(sid: int) -> void:
	if sid > 0 and squads.has(sid):
		(squads[sid] as Dictionary)["helped"] = true

func squad_clear_helped(sid: int) -> void:
	if sid > 0 and squads.has(sid):
		(squads[sid] as Dictionary)["helped"] = false

## Центр постов отряда — «исходная позиция», с которой он ушёл помогать.
## Vector3.INF, если постов не назначено (отряд никогда никуда не ставили)
func _squad_post_centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for m in men:
		var u := m as Unit
		if u == null or u.is_dead() or not u._post_valid:
			continue
		c += u.post_pos
		n += 1
	if n == 0:
		return Vector3.INF
	return c / float(n)

## ОТРЯД ПРЯМО СЕЙЧАС КУДА-ТО ИДЁТ? Достаточно одного бойца в пути.
##
## Нужно ровно одному месту — достройке строя «с нуля» (см. squad_close_ranks).
## Возврат в строй придуман для отряда, ЗАКОНЧИВШЕГО бой и вставшего; отряду,
## который прямо сейчас исполняет приказ на движение, строиться нельзя ни в
## коем случае: close_ranks шлёт всем command_move, а тот гасит бег и снимает
## замок игрока. Замер (qa_upd4 D4, было ПРОВАЛ): отряд, посланный БЕГОМ мимо
## врага, получал по дороге стрелу, «недавно били» заводило отложенную попытку
## смыкания, та срабатывала ровно когда отряд поравнялся с противником —
## приказ на бег отменялся, и трое из четверых немедленно ввязывались в драку,
## пробежать мимо которой им и приказывали
func _squad_on_the_move(men: Array) -> bool:
	for m in men:
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		if u.sprinting:
			return true
		if u.state == Unit.State.MOVING and u._march_pending:
			return true
	return false

## ── ИНТЕРВАЛЫ СТРОЯ ПО УМОЛЧАНИЮ ────────────────────────────────────────────
## Те же числа, что у SelectionManager.UNIT_SPACING / ROW_DEPTH. Зеркало, а не
## ссылка: SelectionManager — узел сцены, тянуть его сюда ради двух констант
## значило бы завязать автозагрузку на порядок инициализации сцены
const BLOCK_SPACING := 0.5
const BLOCK_ROW_DEPTH := 0.55

## ФОРМА СТРОЯ, ДОСТРОЕННАЯ ПО ФАКТУ, — для отряда, которому её никогда не
## задавали приказом (вышел из барака и сразу ввязался в бой). Квадратный
## «кирпичик» вокруг ТЕКУЩЕГО центра масс, фронт — по курсу отряда, а если и
## курса нет, то по среднему взгляду выживших: после боя отряд обязан встать
## строем и смотреть в одну сторону, а не замереть тем пятном, в котором его
## оставила рубка.
##
## Порядок мест тот же, что везде в проекте: сначала ВСЯ первая шеренга, потом
## вторая (см. SquadFormation — на этом порядке держится «задняя шеренга
## переходит вперёд на места павших»)
func _default_block_slots(sid: int, men: Array) -> Array:
	var out: Array = []
	if men.is_empty():
		return out
	var centre := Vector3.ZERO
	var look := Vector3.ZERO
	var n := 0
	for m in men:
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		centre += u.global_position
		look += u._facing
		n += 1
	if n == 0:
		return out
	centre /= float(n)
	var course: Vector3 = squad_course(sid)
	if course.length_squared() < 1e-6:
		course = look
	course.y = 0.0
	if course.length_squared() < 1e-6:
		course = Vector3.FORWARD
	course = course.normalized()
	# Курс запоминаем: по нему потом доворачиваются и копья (Spearman), и спрайты
	if squads.has(sid):
		(squads[sid] as Dictionary)["course"] = course
	var across := Vector3(-course.z, 0.0, course.x)
	var cols: int = maxi(1, int(ceil(sqrt(float(n)))))
	for i in range(n):
		var col: int = i % cols
		var row: int = i / cols
		var off_x: float = (float(col) - float(cols - 1) * 0.5) * BLOCK_SPACING
		var off_z: float = float(row) * BLOCK_ROW_DEPTH
		out.append(centre + across * off_x - course * off_z)
	return out

# ─────────────────────────────────────────────────────────────────────────────
# КОНТРАТАКА ВСЕМ ОТРЯДОМ
# ═════════════════════════════════════════════════════════════════════════════
# По отряду ведут огонь — отряд разворачивается и идёт на стрелков ЦЕЛИКОМ.
# Приказ раздаётся через Unit.command_attack(forced), а тот сам разворачивает
# цель по вражескому отряду (squad_pick_member), поэтому бойцы разбирают
# стрелков поштучно, а не сваливаются толпой на одного.
#
# ОГРАНИЧИТЕЛЬ ОБЯЗАТЕЛЕН: в отряд летит не одна стрела, а залп, и без паузы
# приказ переиздавался бы по нескольку раз за кадр — отряд топтался бы на
# месте, каждый раз начиная разворот заново
const COUNTER_CHARGE_COOLDOWN_MS := 1500

func squad_counter_charge(sid: int, threat: Node3D) -> bool:
	if sid <= 0 or not squads.has(sid) or threat == null or not is_instance_valid(threat):
		return false
	var sq: Dictionary = squads[sid]
	var now: int = Time.get_ticks_msec()
	if now - int(sq.get("counter_ms", 0)) < COUNTER_CHARGE_COOLDOWN_MS:
		return false
	sq["counter_ms"] = now
	# Отряд идёт в бой — прежняя разметка строя больше не действует, иначе
	# смыкание рядов начнёт растаскивать бойцов обратно на старые места
	sq["slots"] = []
	var sent := 0
	for m in squad_members(sid):
		var u := m as Unit
		if u == null or u.is_dead() or u.attack_damage <= 0.0:
			continue
		# БОЙЦЫ, КОТОРЫХ ИГРОК ПРЯМО СЕЙЧАС ВЫВОДИТ ИЗ БОЯ, В КОНТРАТАКУ НЕ ИДУТ.
		# Иначе один обстрелянный сосед за пределами дальности удара дёргал
		# command_attack на ВЕСЬ отряд — и бойцы, только что получившие приказ
		# отойти, разворачивались обратно, даже не добежав до точки (см. Unit._disengaging)
		if u.get("_disengaging"):
			continue
		# БОЙЦЫ ПОД ЗАМКОМ ПРИКАЗА ИГРОКА В КОНТРАТАКУ НЕ ИДУТ (приоритет №1
		# против №3, см. Unit.target_lock). Контратака — СТИХИЙНЫЙ ответ на
		# обстрел, и она зовёт command_attack(forced=true), то есть перезаписала бы
		# _atk_pending и увела отряд с указанной игроком цели на случайного стрелка
		if bool(u.get("target_lock")):
			continue
		# МАРШ ПЕРЕЖИВАЕТ КОНТРАТАКУ, ЕСЛИ ОН БЫЛ. command_attack(forced=true)
		# сам гасит _march_pending (это прямой приказ игрока/ИИ, march-перехват
		# так не делает — см. Unit.command_attack) — здесь же контратака СТИХИЙНАЯ,
		# ответ на обстрел, а не решение бросить исходную цель похода. Без
		# восстановления идущий отряд, огрызнувшийся на слабый заслон с
		# нестыковкой дальности оружия, выбивал заслон и НАВСЕГДА замирал на
		# месте стычки вместо того, чтобы продолжить путь (qa_aggro, тест C2)
		var was_pending: bool = bool(u.get("_march_pending"))
		var mt: Vector3 = u.get("_march_target")
		var ms: bool = bool(u.get("_march_slow"))
		var mf: Vector3 = u.get("_march_face")
		u.command_attack(threat, true, true)
		if was_pending:
			u.set("_march_pending", true)
			u.set("_march_target", mt)
			u.set("_march_slow", ms)
			u.set("_march_face", mf)
		sent += 1
	return sent > 0

## Тип отряда ("spearman"/"archer"/"warrior"/"worker")
func squad_type(squad_id: int) -> String:
	if not squads.has(squad_id):
		return ""
	return String(squads[squad_id]["type"])

# ─────────────────────────────────────────────────────────────────────────────
# СПЕЦ-СПОСОБНОСТИ ОТРЯДА (колонка D древа кузницы)
#
# Способность открывается В ДВА ЭТАПА, и это принципиально:
#   1. Кузница исследует узел ряда D за ресурсы и время — с этого момента
#      способность в принципе доступна ФРАКЦИИ (researched[faction][id]).
#   2. Каждый отряд докупает её СЕБЕ за золото (squad_unlock_cost). Даром и
#      всем сразу она не раздаётся — иначе одно исследование мгновенно
#      усиливало бы всю армию, включая ещё не набранные отряды.
#
# Отметка живёт в самом отряде (squads[sid]["abilities"]), поэтому гибель
# отряда её и уносит: новый набор платит заново.
# ─────────────────────────────────────────────────────────────────────────────

## Куплена ли способность ЭТИМ отрядом
func squad_has_ability(sid: int, node_id: String) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	return bool((squads[sid].get("abilities", {}) as Dictionary).get(node_id, false))

## Все купленные отрядом способности (копия — список наружу не редактируется)
func squad_abilities(sid: int) -> Array:
	if sid <= 0 or not squads.has(sid):
		return []
	return (squads[sid].get("abilities", {}) as Dictionary).keys()

## Почему отряд НЕ может купить способность прямо сейчас — строка причины
## ("" = может). Отдельно от bool-версии по той же причине, что и
## research_blockers: кнопке в панели отряда нужно объяснение, а не серый вид.
func squad_ability_blocker(sid: int, node_id: String) -> String:
	if sid <= 0 or not squads.has(sid):
		return "Отряда нет"
	var node: Dictionary = _Forge.get_node(node_id)
	if node.is_empty() or not bool(node.get("is_unit_ability", false)):
		return "Это не способность отряда"
	var sq: Dictionary = squads[sid]
	if String(sq.get("type", "")) != String(node.get("unit", "")):
		return "Способность другого рода войск"
	if squad_has_ability(sid, node_id):
		return "Уже куплена этим отрядом"
	if not is_researched(int(sq.get("faction", Constants.FACTION_PLAYER)), node_id):
		return "Не исследовано в Кузнице"
	var cost: float = _Forge.squad_unlock_cost(node)
	if ResourceManager.get_amount(int(sq.get("faction", Constants.FACTION_PLAYER)),
			Constants.RESOURCE_GOLD) < cost:
		return "Не хватает золота: %d" % int(cost)
	return ""

func squad_can_buy_ability(sid: int, node_id: String) -> bool:
	return squad_ability_blocker(sid, node_id).is_empty()

## Купить способность ЭТОМУ отряду за золото. false — нельзя (причину скажет
## squad_ability_blocker). Золото списывается здесь же, отката нет: способность
## выдаётся в том же вызове.
func squad_buy_ability(sid: int, node_id: String) -> bool:
	if not squad_can_buy_ability(sid, node_id):
		return false
	var sq: Dictionary = squads[sid]
	var f: int = int(sq.get("faction", Constants.FACTION_PLAYER))
	var node: Dictionary = _Forge.get_node(node_id)
	var cost: float = _Forge.squad_unlock_cost(node)
	if cost > 0.0 and not ResourceManager.spend(f, {Constants.RESOURCE_GOLD: cost}):
		return false
	if not sq.has("abilities"):
		sq["abilities"] = {}
	(sq["abilities"] as Dictionary)[node_id] = true
	return true

# ═════════════════════════════════════════════════════════════════════════════
# ЗАЛПОВЫЙ ОГОНЬ ЛУЧНИКОВ
# ═════════════════════════════════════════════════════════════════════════════
# ЧТО ЭТО. Купленная и ВКЛЮЧЁННАЯ способность (forge_config archer_1d, toggle):
# отряд перестаёт стрелять вразнобой по мере перезарядки и бьёт РАЗОМ, кучно, в
# центр масс вражеского строя.
#
# ПОЧЕМУ ЭТО СЧИТАЕТ ОТРЯД, А НЕ БОЕЦ. Синхронность по определению не может быть
# решением одиночки: каждому лучнику надо знать, готовы ли остальные, и это
# ровно тот же случай, что коридор и разметка линии — один ответ на отряд,
# розданный вниз. Боец только СПРАШИВАЕТ (Archer._may_strike_now).
#
# ── ПОЧЕМУ ОКНО, А НЕ ОДИН КАДР ─────────────────────────────────────────────
# Обход армии дробится по кадрам (perf_config.shards_for): на большой армии
# конкретный лучник опрашивается раз в два-три кадра. Признак «залп, огонь!»,
# живущий один кадр, застал бы треть отряда, и «одновременный залп» развалился
# бы на три очереди. Поэтому открывается ОКНО в VOLLEY_WINDOW_MS — заведомо
# длиннее самого редкого опроса и заведомо короче паузы между залпами.
const VOLLEY_WINDOW_MS := 200
## Пауза между залпами. Сверх неё лучник всё равно ждёт СВОЮ перезарядку —
## залп не ускоряет стрельбу, он её синхронизирует
const VOLLEY_COOLDOWN_MS := 900
## Какой доли живого состава хватает, чтобы дать команду. Не «всем»: один
## отставший, которому цель не по дальности, стопорил бы отряд навсегда
## 0.7, а не «все»: один отставший, которому цель не по дальности, стопорил бы
## отряд навсегда. И не 0.5 — при половине залп выходит жидким: тот, кто не
## успел, стреляет уже следующим залпом, а не в этом
const VOLLEY_READY_FRACTION := 0.7

## Включён ли режим у отряда (куплен и не выключен игроком)
func squad_ability_on(sid: int, node_id: String) -> bool:
	if not squad_has_ability(sid, node_id):
		return false
	return bool((squads[sid].get("ability_on", {}) as Dictionary).get(node_id, false))

## Включить/выключить купленный режим. Некупленный не включается
func squad_set_ability(sid: int, node_id: String, on: bool) -> bool:
	if not squad_has_ability(sid, node_id):
		return false
	var sq: Dictionary = squads[sid]
	if not sq.has("ability_on"):
		sq["ability_on"] = {}
	(sq["ability_on"] as Dictionary)[node_id] = on
	if not on:
		# Открытое окно закрываем сразу: иначе выключенный режим успел бы
		# отстреляться ещё раз уже после нажатия
		sq["volley_until"] = 0
	return true

## Идёт ли ПРЯМО СЕЙЧАС окно залпа. Спрашивает лучник перед выстрелом
func squad_volley_open(sid: int) -> bool:
	if not squads.has(sid):
		return false
	return Time.get_ticks_msec() < int((squads[sid] as Dictionary).get("volley_until", 0))

## Точка, в которую бьёт текущий залп (центр масс цели)
func squad_volley_aim(sid: int) -> Vector3:
	if not squads.has(sid):
		return Vector3.ZERO
	return (squads[sid] as Dictionary).get("volley_aim", Vector3.ZERO)

## Радиус вражеского строя, по которому размазывается «туча» (см. Archer)
func squad_volley_spread(sid: int) -> float:
	if not squads.has(sid):
		return 0.0
	return float((squads[sid] as Dictionary).get("volley_spread", 0.0))

## Есть ли у отряда ВКЛЮЧЁННЫЙ залп — по конфигу, без имени способности в коде
func squad_volley_mode(sid: int) -> bool:
	if not squads.has(sid):
		return false
	var node: Dictionary = _Forge.toggle_ability_of(squad_type(sid))
	if node.is_empty():
		return false
	return squad_ability_on(sid, String(node.get("id", "")))

## ТАКТ ЗАЛПОВ. Обходит только те отряды, у которых режим включён: у остальных
## это одна проверка словаря
func _sweep_volleys() -> void:
	var now: int = Time.get_ticks_msec()
	for key in squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = squads[key]
		# Дешёвый отсев: без единой купленной способности отряду тут делать нечего
		if (sq.get("ability_on", {}) as Dictionary).is_empty():
			continue
		if not squad_volley_mode(sid):
			continue
		if now < int(sq.get("volley_until", 0)):
			continue                      # окно ещё открыто — залп идёт
		if now < int(sq.get("volley_next", 0)):
			continue                      # пауза между залпами
		# ── КТО ГОТОВ ────────────────────────────────────────────────────────
		# Готов = перезарядился И держит живую цель в пределах дальности.
		# Заодно копим центр масс ЦЕЛЕЙ: он и есть точка залпа
		var men: Array = squad_members(sid)
		if men.is_empty():
			continue
		var ready := 0
		var alive := 0
		var acc := Vector3.ZERO
		var n_aim := 0
		var foe_sid := 0
		for m in men:
			var u := m as Unit
			if u == null or not is_instance_valid(u) or u.is_dead():
				continue
			alive += 1
			var t := u.attack_target as Unit
			if t == null or not is_instance_valid(t) or t.is_dead():
				continue
			if u.global_position.distance_to(t.global_position) > u.attack_range:
				continue
			if u._attack_timer > 0.0:
				continue
			ready += 1
			acc += t.global_position
			n_aim += 1
			if foe_sid == 0 and t.squad_id > 0:
				foe_sid = t.squad_id
		if alive == 0 or n_aim == 0:
			continue
		if float(ready) < float(alive) * VOLLEY_READY_FRACTION:
			continue
		# ── ТОЧКА ЗАЛПА — ЦЕНТР МАСС ВРАЖЕСКОГО ОТРЯДА ───────────────────────
		# Именно отряда, а не средней из целей: цели выбираются каждым стрелком
		# своим сканом, и их среднее смещено к тому флангу, где стрелков больше.
		# Центр строя противника — то, во что игрок и целится глазами.
		# Если у цели отряда нет (одиночка, здание) — падаем на среднее из целей
		var aim: Vector3 = acc / float(n_aim)
		var spread := 0.0
		if foe_sid > 0:
			var c: Vector3 = squad_centroid(foe_sid)
			if c != Vector3.ZERO:
				aim = c
				spread = _squad_spread_radius(foe_sid)
		sq["volley_aim"]    = aim
		sq["volley_foe"]    = foe_sid          # см. squad_volley_point
		sq["volley_spread"] = spread
		sq["volley_until"]  = now + VOLLEY_WINDOW_MS
		sq["volley_next"]   = now + VOLLEY_WINDOW_MS + VOLLEY_COOLDOWN_MS

## ТОЧКА ЗАЛПА НА МОМЕНТ ВЫСТРЕЛА, а не на момент открытия окна.
##
## Окно живёт VOLLEY_WINDOW_MS (200 мс), и стрелки входят в него вразнобой:
## тот, кого обход армии опросил последним, целился в центр строя, который
## противник покинул полсекунды назад. Если вражеский отряд ещё жив — берём
## его центр СЕЙЧАС; если он выбит или цель была одиночкой/зданием — остаётся
## записанная точка (лучше устаревшая, чем никакой)
func squad_volley_point(sid: int) -> Vector3:
	if not squads.has(sid):
		return Vector3.ZERO
	var sq: Dictionary = squads[sid]
	var foe: int = int(sq.get("volley_foe", 0))
	if foe > 0:
		var c: Vector3 = squad_centroid(foe)
		if c != Vector3.ZERO:
			return c
	return sq.get("volley_aim", Vector3.ZERO)

## Радиус, в котором стоит вражеский отряд — по нему «туча» размазывается ровно
## на строй, а не сходится в одну точку (разбор в Archer._volley_offset).
##
## НИЖНЯЯ ГРАНИЦА ЗДЕСЬ НЕ СТАВИТСЯ НАМЕРЕННО: это честный габарит строя, и
## стенды сравнивают его именно с габаритом. Минимум накрытия накладывает
## стрелок (unit_stats_config.VOLLEY_MIN_SPREAD) — там, где считается туча
func _squad_spread_radius(sid: int) -> float:
	var men: Array = squad_members(sid)
	if men.size() < 2:
		return 0.0
	var c: Vector3 = squad_centroid(sid)
	var r2 := 0.0
	for m in men:
		var u := m as Node3D
		if u == null or not is_instance_valid(u):
			continue
		var dx: float = u.global_position.x - c.x
		var dz: float = u.global_position.z - c.z
		var d2: float = dx * dx + dz * dz
		if d2 > r2:
			r2 = d2
	return sqrt(r2)

## Все отряды фракции: [{"id", "type", "members"}] — только непустые
func squads_of_faction(p_faction: int) -> Array:
	var out: Array = []
	for key in squads.keys():
		var sid: int = key
		if int(squads[sid]["faction"]) != p_faction:
			continue
		if squad_members(sid).is_empty():
			continue
		out.append(squads[sid])
	return out

func reset_squads() -> void:
	# СНАЧАЛА СНИМАЕМ ПРИПИСКУ С ЖИВЫХ. Счётчик id обнуляется, и следующие
	# отряды снова получат номера 1, 2, 3… Если у бойца, пережившего сброс,
	# оставить старый squad_id, он «прирастёт» к чужому новому отряду: клик по
	# такому бойцу выделял бы отряд другой стороны, а add_to_squad портил бы
	# его состав. Здесь узлов немного (сброс делается один раз за партию).
	var tree := get_tree()
	if tree != null:
		for n in tree.get_nodes_in_group("all_units"):
			if is_instance_valid(n):
				n.squad_id = 0
	# Знамёна — отдельные узлы в мире, а не дети бойцов: очистка словаря их не
	# уносит (см. _disband_squad). Новая партия иначе начиналась бы с россыпи
	# знамён прошлой.
	# УРОНИТЬ ИХ НА ЗЕМЛЮ ЗДЕСЬ НЕЛЬЗЯ: это сброс партии, а не гибель отряда —
	# поле и так стирается целиком
	for key in squads.keys():
		var bn = (squads[key] as Dictionary).get("banner", null)
		if bn != null and is_instance_valid(bn):
			bn.queue_free()
	squads.clear()
	# ── ВСЯ ПОБОЧНАЯ БУХГАЛТЕРИЯ ОТРЯДОВ ОБНУЛЯЕТСЯ ВМЕСТЕ С НИМИ ───────────
	# Счётчик id тоже сбрасывается в единицу, поэтому оставленная запись — это
	# не утечка, а ЛОЖНЫЙ ОТВЕТ про отряд НОВОЙ партии с тем же номером:
	# коридор сказал бы свежему отряду №1 «чужих рядом нет» (и тот прошёл бы
	# сквозь вражеский строй до истечения TTL), кэш цели выдал бы освобождённый
	# объект, а остывание боевого клича съело бы первый приказ
	_corridors.clear()
	_cohesion_last.clear()
	_melee.clear()
	_cry_last.clear()
	_squad_target.clear()
	_squad_face.clear()
	_pursuit_anchor.clear()
	# Матрицу снимаем через штатный релиз: он ещё и гасит признак «меня ведёт
	# отряд» у переживших сброс бойцов, чего голый clear() не делает
	for mk in _matrix.keys():
		_matrix_release(int(mk))
	_matrix.clear()
	_next_squad_id = 1

# ─────────────────────────────────────────────────────────────────────────────
# ОПЫТ ОТРЯДА (VETERANCY)
# ═════════════════════════════════════════════════════════════════════════════
# Убийства считаются НА ОТРЯД, а не на бойца: фраг любой модели идёт в общий
# счёт. Пороги и шаблоны улучшений — в unit_stats_config.gd
# (KILL_BONUS_THRESHOLDS, VETERAN_LEVEL_BONUSES).
#
# Дошли до порога → над командиром загорается звёздочка и появляется «долг»
# pending: столько улучшений игрок должен выбрать на панели отряда.
# Выбранный бонус раздаётся КАЖДОЙ модели (плоские поля Unit.vet_*) и
# запоминается в отряде, чтобы пополнение из замка получало его автоматически.
# ─────────────────────────────────────────────────────────────────────────────
## ЗВЕЗДА БОЛЬШЕ НЕ ИСПОЛЬЗУЕТСЯ: её заменили знамёна на копьях (заказ
## владельца, авг. 2026). Файл VeterancyStar.gd оставлен в дереве неиспользуемым
## — тем же порядком, что и gold_shimmer.gdshader, — потому что по нему всё ещё
## меряются стенды прежнего вида и потому что удалять готовую процедурную
## геометрию ради одной строки импорта незачем
const _SquadBanner := preload("res://scripts/SquadBanner.gd")
const _BannerArt   := preload("res://scripts/BannerArt.gd")

## Записать убийство на счёт отряда убийцы.
## victim — кого убили; нужен, чтобы СВОИ в зачёт не шли (дружественный огонь,
## снос собственной постройки). Без цели проверка просто не делается.
func credit_kill(killer: Node, victim: Node = null) -> void:
	if killer == null or not is_instance_valid(killer):
		return
	if not (killer is Unit):
		return
	if victim != null and is_instance_valid(victim) and victim.get("faction") != null:
		if int(victim.faction) == int((killer as Unit).faction):
			return
	var sid: int = killer.squad_id
	if sid <= 0 or not squads.has(sid):
		return
	var sq: Dictionary = squads[sid]
	sq["kills"] = int(sq["kills"]) + 1
	var lvl: int = _UCfg.veteran_level_for_kills(String(sq["type"]), int(sq["kills"]))
	if lvl <= int(sq["level"]):
		return
	# Через несколько порогов разом (добивание большого отряда) — начисляем все
	sq["pending"] = int(sq["pending"]) + (lvl - int(sq["level"]))
	sq["level"]   = lvl
	refresh_squad_banner(sid)

func squad_kills(squad_id: int) -> int:
	if not squads.has(squad_id):
		return 0
	return int(squads[squad_id]["kills"])

func squad_level(squad_id: int) -> int:
	if not squads.has(squad_id):
		return 0
	return int(squads[squad_id]["level"])

## Сколько улучшений ждут выбора игроком
func squad_pending(squad_id: int) -> int:
	if not squads.has(squad_id):
		return 0
	return int(squads[squad_id]["pending"])

## Какой уровень выбирается прямо сейчас (1..max, 0 — выбирать нечего)
func squad_choosing_level(squad_id: int) -> int:
	var p := squad_pending(squad_id)
	if p <= 0:
		return 0
	return squad_level(squad_id) - p + 1

## Суммарный ветеранский бонус отряда по характеристике
## ("attack"/"armor"/"defense"/"speed"/"health")
func squad_bonus(squad_id: int, stat: String) -> float:
	if not squads.has(squad_id):
		return 0.0
	var b: Dictionary = squads[squad_id]["bonuses"]
	return float(b.get(stat, 0.0))

## ЧТО ОТРЯД УЖЕ ВЫБРАЛ: id наград ПО ПОРЯДКУ УРОВНЕЙ (элемент i — выбор,
## сделанный на уровне i+1). Один и тот же id может встретиться несколько раз —
## именно из этого HUD считает стек (II, III, IV) на иконке бонуса.
## Копия, а не сам массив: наружу отдавать внутреннее состояние отряда нельзя
func squad_chosen(squad_id: int) -> Array:
	if not squads.has(squad_id):
		return []
	return (squads[squad_id]["chosen"] as Array).duplicate()

## Применить выбор игрока. choice_index — номер кнопки 0..4.
## false — выбирать нечего или индекс вне списка.
func apply_veteran_choice(squad_id: int, choice_index: int) -> bool:
	var lvl := squad_choosing_level(squad_id)
	if lvl <= 0:
		return false
	var choices: Array = _UCfg.veteran_choices(String(squads[squad_id]["type"]), lvl)
	if choice_index < 0 or choice_index >= choices.size():
		return false
	var c: Dictionary = choices[choice_index]
	var sq: Dictionary = squads[squad_id]
	var b: Dictionary = sq["bonuses"]
	# ── НАГРАДА — ЭТО НАБОР МОДИФИКАТОРОВ, А НЕ ОДНА ПАРА ───────────────────
	# Таблица наград расписана тем же шаблоном, что и узлы кузницы (все ключи,
	# ненужное нулём), и вправе дать сразу несколько прибавок. Раньше здесь
	# читалась одна пара stat/value, то есть вторая прибавка в таблице просто не
	# сработала бы — молча, что хуже всего
	var mods: Dictionary = _UCfg.nonzero_modifiers(c)
	var stat: String = String(c.get("stat", ""))
	for key in mods:
		var short: String = _UCfg.modifier_stat_name(String(key))
		var value: float  = float(mods[key])
		b[short] = float(b.get(short, 0.0)) + value
		for m in squad_members(squad_id):
			_apply_bonus_to_unit(m, short, value)
	(sq["chosen"] as Array).append(String(c.get("id", stat)))
	sq["pending"] = int(sq["pending"]) - 1
	refresh_squad_banner(squad_id)
	return true

## Выдать бойцу ОДИН бонус. HP поднимается сразу и максимуму, и текущему —
## его, в отличие от остальных, нельзя прочитать «вживую» при ударе
func _apply_bonus_to_unit(unit: Node, stat: String, value: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	match stat:
		"attack":  unit.vet_attack  += value
		"armor":   unit.vet_armor   += value
		"defense": unit.vet_defense += value
		"speed":   unit.vet_speed   += value
		"health":
			unit.max_health     += value
			unit.current_health += value
		# ── ОСТАЛЬНЫЕ КЛЮЧИ ШАБЛОНА ─────────────────────────────────────────
		# Пишутся ПРЯМО В ПОЛЯ бойца — тем же приёмом, что и запас HP, и по той
		# же причине: эти числа читаются в горячих ветках, и заводить под каждое
		# отдельное поле vet_* значило бы платить за них в каждом кадре
		"range":    unit.attack_range    += value
		"cooldown": unit.attack_cooldown = maxf(
			unit.attack_cooldown - value, _UCfg.MIN_COOLDOWN)
		"push":     unit.push_force += value
		"morale":   unit.morale     += value
		# Кучность и темп добычи полей не имеют — держим их на бойце числом
		"spread":   unit.vet_spread += value
		"carry":
			if unit.has_method("carry_capacity"):
				unit.gather_amount += value
		"gather":   unit.vet_gather += value
	# Ветеранские прибавки меняют то, что лежит в строке ядра армии
	unit._soa_push_stats()

## Выдать НОВОБРАНЦУ все бонусы, уже заслуженные отрядом.
## Нужно пополнению из замка: доукомплектованные модели не должны быть слабее
func apply_squad_bonuses_to(squad_id: int, unit: Node) -> void:
	if not squads.has(squad_id):
		return
	var b: Dictionary = squads[squad_id]["bonuses"]
	for key in b:
		_apply_bonus_to_unit(unit, String(key), float(b[key]))

## Звезда отряда: создать/перестроить/снять. Узел живёт В МИРЕ, а не на бойце.
##
## РАНЬШЕ звезда была ДОЧЕРНИМ узлом командира (members[0]) — так она ездила
## сама, без единой строчки в _process. Плата за это: висела она над КРАЙНИМ
## бойцом строя, а не над отрядом, и при гибели командира прыгала на другого
## человека — по заказу владельца звезда обязана стоять строго по ЦЕНТРУ МАСС
## (среднее координат всех выживших). Центр масс — величина не от одного узла,
## поэтому родителем стал мир. Со сменой звезды на знамя точка стала точкой
## КОНКРЕТНОГО бойца-знаменосца, и обновляется она каждый кадр
## (см. _update_squad_banners).
## ── ЗАЖЕЧЬ / ОБНОВИТЬ ЗНАМЯ ОТРЯДА ─────────────────────────────────────────
## Зовётся по СОБЫТИЯМ: отряд получил звание, состав изменился, партия
## перезапущена. Покадрового пути здесь нет — за знаменосцем знамя ездит в
## _update_squad_banners.
##
## Здесь была refresh_star, вешавшая звезду над центром масс. Разница не в
## картинке: у знамени есть НОСИТЕЛЬ, и его надо выбрать (см. _assign_bearer)
func refresh_squad_banner(squad_id: int) -> void:
	if not squads.has(squad_id):
		return
	var sq: Dictionary = squads[squad_id]
	var lvl: int = int(sq["level"])
	var banner = sq.get("banner")
	var members := squad_members(squad_id)
	if lvl <= 0 or members.is_empty():
		if banner != null and is_instance_valid(banner):
			banner.queue_free()
		sq["banner"] = null
		sq["bearer"] = null
		return
	# Носитель мог выбыть между событиями (гарнизон, смерть в том же кадре)
	if squad_bearer(squad_id) == null:
		_assign_bearer(squad_id)
	if banner != null and is_instance_valid(banner):
		# Уже висит. Но отряд мог подрасти в звании: тогда картинку надо
		# ПЕРЕСТРОИТЬ, иначе на пятом уровне так и висел бы вымпел первого
		if int(banner.shown_level) != lvl:
			banner.build(lvl)
		return
	var host: Node = main if main != null and is_instance_valid(main) else null
	if host == null:
		# Мира ещё нет (стенд поднимает отряды до сцены) — попробуем в следующий раз
		return
	var fresh: MeshInstance3D = _SquadBanner.create(lvl)
	host.add_child(fresh)
	sq["banner"] = fresh

## Центр масс отряда — СРЕДНЕЕ координат всех выживших, без весов.
## Публичный: тем же числом пользуется HUD (карточка отряда) и стенды
func squad_centroid(squad_id: int) -> Vector3:
	var members := squad_members(squad_id)
	if members.is_empty():
		return Vector3.ZERO
	return _centroid_of(members)

## ЦЕНТР МАСС ОТРЯДА — ПО УЗЛАМ, А НЕ ПО СТРОКАМ ЯДРА АРМИИ.
##
## Пробовалось читать строки: они дешевле, потому что не трогают свойство
## global_position. Но строки обновляются с частотой пересчёта коридоров (раз в
## CORRIDOR_TTL_MS), и звезда отряда начинала отставать от строя примерно на
## 0.2 м — стенд qa_vet #4 это поймал сразу. Выигрыша при этом замер не
## показал вовсе: метка над отрядом двигалась раз в несколько кадров, и в
## массовом бою их вклад теряется в шуме.
##
## Итог: платить отставанием картинки за неизмеримую экономию незачем. Строки
## понадобятся здесь тогда, когда они станут обновляться каждый кадр сами —
## то есть в Фазе 2, когда из них будет перестраиваться пространственная сетка
## ── ЦЕНТР ОТРЯДА — МЕДИАНА, А НЕ СРЕДНЕЕ АРИФМЕТИЧЕСКОЕ (заказ владельца) ───
##
## Среднее устойчиво ровно до тех пор, пока отряд стоит одним куском. Стоит
## строю растянуться или расколоться на две группы — а именно это и происходит
## в бою, когда часть бойцов ушла в свалку, а часть осталась, — и среднее
## уезжает В ПУСТОЕ ПОЛЕ РОВНО МЕЖДУ НИМИ. На скриншотах владельца это видно
## буквально: звёзды ветеранства висят в чистом поле, а отряда под ними нет.
## Туда же попадала точка залпа, точка сбора и цель прицеливания.
##
## Медиана по каждой оси отдельно (не геометрическая) — она стоит одну
## сортировку на отряд вместо итеративного решения, а от выброса защищает так
## же: половина отряда всегда по одну сторону от неё, половина по другую, и
## «пустой середины» между двумя кучами не возникает — точка садится на
## бо́льшую из них.
##
## Цена: сортировка ≤60 чисел раз в несколько кадров на отряд.
func _centroid_of(members: Array) -> Vector3:
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for m in members:
		var u := m as Node3D
		if u == null or not is_instance_valid(u):
			continue
		var p: Vector3 = u.global_position
		xs.append(p.x)
		zs.append(p.z)
	var n: int = xs.size()
	if n == 0:
		return Vector3.ZERO
	if n <= 2:
		# На одном-двух бойцах медиана и среднее совпадают по смыслу, а сортировка
		# только тратит время
		var ax := 0.0
		var az := 0.0
		for i in range(n):
			ax += xs[i]
			az += zs[i]
		var mx0: float = ax / float(n)
		var mz0: float = az / float(n)
		return Vector3(mx0, get_terrain_height(mx0, mz0), mz0)
	xs.sort()
	zs.sort()
	var h: int = n >> 1
	var mx: float
	var mz: float
	if n % 2 == 1:
		mx = xs[h]
		mz = zs[h]
	else:
		mx = (xs[h - 1] + xs[h]) * 0.5
		mz = (zs[h - 1] + zs[h]) * 0.5
	# Высота — у РЕЛЬЕФА под точкой: медиана может прийтись туда, где никто не
	# стоит, и брать высоту у случайного бойца было бы неверно
	return Vector3(mx, get_terrain_height(mx, mz), mz)

## ── СОСТАВ, КОТОРЫЙ ВИДНО НА КАРТЕ ──────────────────────────────────────────
## Гарнизон — это ЖИВЫЕ бойцы: они не павшие, из squad_members не выпадают, и
## центр масс отряда честно уползал к замку вместе с ними. На экране это
## выглядело как «звезда отвязалась от отряда и прилипла к зданию»: половина
## бойцов лечится внутри, а метка стоит над крышей.
##
## Всё, что рисуется НАД отрядом, обязано считаться по тем, кого видно.
## Признак — Unit.garrisoned (его ставит Castle.absorb_unit)
func _on_map_members(members: Array) -> Array:
	var out: Array = []
	for m in members:
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.garrisoned:
			continue
		out.append(u)
	return out

## РАСФОРМИРОВАТЬ ОТРЯД. Единственное место, где запись уходит из `squads`.
##
## Здесь стоял голый squads.erase(), и метка ветеранства ПЕРЕЖИВАЛА отряд: она
## висит отдельным узлом в мире, а не на бойце, поэтому гибель последнего бойца
## её не уносила — она оставалась лежать на камнях навсегда. Это касается ОБОИХ
## случаев из отчёта: и когда награда уже была взята, и когда она только
## появилась, а игрок не успел кликнуть, — узел в обоих один и тот же.
##
## СО ЗНАМЁНАМИ ДОБАВИЛОСЬ ВТОРОЕ ДЕЙСТВИЕ, и порядок в нём важен: узел знамени
## снимается, но САМО ЗНАМЯ остаётся на поле — уже слотом в слое тел
## (см. _drop_squad_banner). Уронить его надо ДО очистки словаря: и уровень
## отряда, и точка, где пал последний, лежат в этом же словаре
## wiped — отряд ВЫБИТ (последний боец погиб), а не расформирован переводом
## или сбросом партии. Знамя падает на землю только в этом случае
func _disband_squad(sid: int, wiped: bool = false) -> void:
	var sq: Variant = squads.get(sid)
	if sq != null:
		if wiped:
			_drop_squad_banner(sid)
		var banner = (sq as Dictionary).get("banner", null)
		if banner != null and is_instance_valid(banner):
			banner.queue_free()
		(sq as Dictionary)["banner"] = null
		(sq as Dictionary)["bearer"] = null
	squads.erase(sid)
	_corridors.erase(sid)
	_cohesion_last.erase(sid)
	# Кэши «на отряд» тоже уходят вместе с ним: id внутри партии не переиспользуются,
	# поэтому это не ошибка ответа, но за длинный бой из сотен расформированных
	# отрядов словари росли и не убывали
	_melee.erase(sid)
	_cry_last.erase(sid)
	# ── МЕТКА ПРИКАЗА НЕ ПЕРЕЖИВАЕТ ОТРЯД ──────────────────────────────────
	# Она гаснет по ПРИБЫТИЮ (см. _refresh_order_marks), а расформированный
	# отряд не придёт никуда. Оставленная запись — это кольцо, висящее в чистом
	# поле, и снять его больше некому
	squad_orders.erase(sid)
	_squad_target.erase(sid)
	_squad_face.erase(sid)
	_pursuit_anchor.erase(sid)
	_matrix_release(sid)

# ═════════════════════════════════════════════════════════════════════════════
# ЗНАМЯ ЕДЕТ ЗА ЗНАМЕНОСЦЕМ
# ═════════════════════════════════════════════════════════════════════════════
# Здесь был _update_squad_stars: он раз в шесть кадров считал центр масс отряда
# и подтягивал к нему звезду с сглаживанием. И то, и другое было нужно ровно
# потому, что звезда висела над ТОЧКОЙ, которую надо было вычислять, — а точка
# эта дёргалась при каждом пересчёте.
#
# У знамени носитель — конкретный боец, и спрашивать у него НАРИСОВАННУЮ точку
# (Unit.draw_position) можно каждый кадр: она уже сглажена между физическими
# шагами тем же механизмом, что и сам спрайт. Поэтому здесь нет ни редкого
# пересчёта, ни догоняющего lerp, ни словаря целей — знамя просто стоит там,
# где нарисован его знаменосец, кадр в кадр.
#
# ЦЕНА: один обход отрядов (их десятки, не тысячи) и одно чтение точки на отряд.
# Прежний вариант обходил ВЕСЬ СОСТАВ каждого отряда ради центра масс.
func _update_squad_banners() -> void:
	for key in squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = squads[key]
		var banner = sq.get("banner", null)
		if banner == null or not is_instance_valid(banner):
			continue
		var bearer = squad_bearer(sid)
		if bearer == null:
			# Носитель выбыл, а событие о том не пришло (гарнизон, туман,
			# гибель вне обычного пути) — берём следующего прямо здесь.
			# Дороже обычного кадра, но случается это раз на смерть носителя
			bearer = _assign_bearer(sid)
			if bearer == null:
				banner.visible = false
				continue
		var u := bearer as Unit
		# ── ЗНАМЯ ВИДНО РОВНО ТОГДА, КОГДА ВИДНО ЗНАМЕНОСЦА ────────────────
		# Жалоба владельца (скриншот): синие флажки ветеранов орды стоят в
		# пустой траве — «спамятся и зависают», хотя ни одного гоблина рядом.
		#
		# Дубликатов при этом нет и не было: узлов в дереве ровно столько,
		# сколько ветеранских отрядов (замер зондом qa_reform/Flags — 5 из 5 за
		# весь бой, бесхозных ноль). Флаг в поле ОДИН И ЗАКОННЫЙ, просто стоит
		# он не там, где его хозяин.
		#
		# ПРИЧИНА — ЗАМЕРШАЯ НАРИСОВАННАЯ ТОЧКА. Боец под пеленой снимается с
		# общей отрисовки и выходит из tick_visual РАНЬШЕ, чем обновит
		# draw_position(): она остаётся равной месту, где его видели последний
		# раз. Знамя же ехало по этой точке И ПО НЕЙ ЖЕ спрашивало туман —
		# то есть спрашивало не «видно ли хозяина», а «освещено ли место, где
		# он когда-то был». Орда уходит под пелену, армия игрока наступает,
		# освещает её вчерашнюю кромку — и над пустой травой загорается флаг,
		# который так и стоит, пока хозяин не выйдет на свет или не погибнет.
		#
		# Спрашиваем поэтому ФАКТ ОТРИСОВКИ (Unit.is_drawn): он покрывает разом
		# и туман, и гарнизон, и уход с карты, и не зависит от того, насколько
		# свежа нарисованная точка. Туман проверяется дополнительно и по
		# ЛОГИЧЕСКОЙ точке бойца — она честна всегда
		if u.garrisoned or not u.is_inside_tree() or not u.is_drawn():
			banner.visible = false
			continue
		var gp: Vector3 = u.global_position
		banner.visible = fog == null or not is_instance_valid(fog) \
			or fog.is_lit(gp.x, gp.z)
		if not banner.visible:
			continue
		# Ставится знамя по-прежнему в НАРИСОВАННУЮ точку: она сглажена между
		# физическими шагами тем же механизмом, что и сам спрайт, и только на
		# ней знамя не дрожит относительно хозяина
		var p: Vector3 = u.draw_position()
		banner.place_at(p, get_terrain_height(p.x, p.z))

# ─────────────────────────────────────────────────────────────────────────────
# СТРОЙКА РАБОЧИМ
# Кнопка на панели рабочего → режим размещения → фундамент → рабочий бежит
# к нему с молотком → по готовности фундамент подменяется зданием.
# Ресурсы списываются В МОМЕНТ РАЗМЕЩЕНИЯ, отмена размещения их возвращает
# (см. Main._placing_refund) — правило то же, что и у постройки из замка.
# ─────────────────────────────────────────────────────────────────────────────
const _CSite := preload("res://scripts/ConstructionSite.gd")
const _ArrowScript := preload("res://scripts/Arrow.gd")
## Только ради констант-признаков (F_*): сами массивы живут в поле `army`
const _Army := preload("res://scripts/army/ArmySoA.gd")

## ЧТО РАБОЧИЙ УМЕЕТ СТРОИТЬ — целиком из конфига.
## Раньше цена, габарит и время дублировались здесь; теперь единственный
## источник правды — unit_stats_config.BUILDINGS (поле worker_buildable).
## Добавили запись в конфиг — кнопка на панели рабочего появилась сама.
var _worker_builds_cache: Dictionary = {}

func worker_buildings() -> Dictionary:
	if not _worker_builds_cache.is_empty():
		return _worker_builds_cache
	for bid in _UCfg.worker_buildable_ids():
		var key: String = String(bid)
		var cfg: Dictionary = _UCfg.building_cfg(key)
		_worker_builds_cache[key] = {
			"name": String(cfg.get("name", key)),
			"time": _UCfg.building_stat(key, "build_time", 12.0),
			"size": _UCfg.building_size(key),
			"cost": _UCfg.building_cost(key),
			"icon": String(cfg.get("icon", "")),
		}
	return _worker_builds_cache

func worker_build_cost(build_id: String) -> Dictionary:
	var d: Dictionary = worker_buildings().get(build_id, {})
	return d.get("cost", {})

## Заказ постройки. worker — заказчик (по нему берётся фракция), crew —
## ВСЯ выделенная артель: на фундамент отправляются все, и каждый следующий
## рабочий ускоряет стройку (см. ConstructionSite.BUILDER_SPEEDUP).
## Пустой crew = работает один заказчик, как было раньше.
func try_worker_build(worker: Node, build_id: String, crew: Array = []) -> void:
	if main == null or worker == null or not is_instance_valid(worker):
		return
	var d: Dictionary = worker_buildings().get(build_id, {})
	if d.is_empty():
		return
	# Кузница у фракции одна
	if build_id == "smithy":
		var grp := Constants.building_group(worker.faction)
		for b in get_tree().get_nodes_in_group(grp):
			if b is Smithy:
				return
	var cost: Dictionary = d.get("cost", {})
	if not ResourceManager.spend(worker.faction, cost):
		return

	var f: int = worker.faction
	var size: Vector3 = d.get("size", Vector3(3.0, 2.0, 3.0))
	var bname: String = String(d.get("name", "Здание"))
	var btime: float  = d.get("time", 12.0)
	# Артель: заказчик + все выделенные рабочие той же фракции, без дублей
	var team: Array = [worker]
	for c in crew:
		if c == null or not is_instance_valid(c) or c == worker:
			continue
		if not c.has_method("command_build"):
			continue
		if c.faction != f:
			continue
		team.append(c)
	main.enter_building_placement(cost, size,
		func(pos: Vector3):
			var site: Building = _CSite.new()
			site.faction     = f
			site.target_id   = build_id
			site.target_name = bname
			site.build_time  = btime
			site.build_size  = size
			main.world_add(site)
			site.global_position = pos
			# ВСЯ артель сразу бежит на стройку
			for b in team:
				if is_instance_valid(b) and b.has_method("command_build"):
					b.command_build(site),
		bname)

# ─────────────────────────────────────────────────────────────────────────────
# ВОССТАНОВЛЕНИЕ РУИН
#
# ПКМ выделенными рабочими по руине своей постройки — на её месте В ТОТ ЖЕ КАДР
# встаёт стройплощадка того же здания, а руина исчезает. Никакого режима
# размещения с фантомом под курсором: место уже выбрано — оно ровно там, где
# стояло здание, и подтверждать его вторым кликом незачем.
#
# ЦЕНА — ОБЫЧНАЯ ЦЕНА ПОСТРОЙКИ, списывается сразу (то же правило, что и у
# найма, и у закладки нового здания). Скидки за «ремонт» нет намеренно: иначе
# выгодно было бы подставлять свои здания под снос. Не хватило ресурсов —
# площадка не ставится и руина остаётся на месте, вызывающий получает null.
# ─────────────────────────────────────────────────────────────────────────────

## Заменить руину стройплощадкой. Возвращает узел площадки или null.
func rebuild_ruin(ruin: Node) -> Node:
	if main == null or ruin == null or not is_instance_valid(ruin):
		return null
	if not ruin.is_in_group("ruins"):
		return null
	var build_id: String = String(ruin.get_meta("ruin_building_id", ""))
	if build_id.is_empty():
		return null
	var f: int = int(ruin.get_meta("ruin_faction", Constants.FACTION_PLAYER))
	var cfg: Dictionary = _UCfg.building_cfg(build_id)
	if cfg.is_empty():
		return null
	if not ResourceManager.spend(f, _UCfg.building_cost(build_id)):
		return null
	var pos: Vector3 = (ruin as Node3D).global_position
	var site: Building = _CSite.new()
	site.faction     = f
	site.target_id   = build_id
	site.target_name = String(cfg.get("name", build_id))
	site.build_time  = _UCfg.building_stat(build_id, "build_time", 12.0)
	site.build_size  = _UCfg.building_size(build_id)
	main.world_add(site)
	site.global_position = pos
	# Руина уходит СРАЗУ: два спрайта на одной клетке читались бы как мусор
	ruin.queue_free()
	return site

func try_build_barracks(castle: Building) -> void:
	if main == null:
		return
	# Цена и габарит — из конфига (BUILDINGS["barracks"])
	var cost := _UCfg.building_cost("barracks")
	if not ResourceManager.spend(castle.faction, cost):
		return
	var f := castle.faction
	main.enter_building_placement(cost, _UCfg.building_size("barracks"),
		func(pos: Vector3):
			var barracks := Barracks.new()
			barracks.faction = f
			main.world_add(barracks)
			barracks.global_position = pos,
		"Бараки")

func try_build_smithy(castle: Building) -> void:
	if main == null:
		return
	var grp := Constants.building_group(castle.faction)
	for b in get_tree().get_nodes_in_group(grp):
		if b is Smithy:
			return  # only one smithy per faction
	var cost := _UCfg.building_cost("smithy")
	if not ResourceManager.spend(castle.faction, cost):
		return
	var f := castle.faction
	main.enter_building_placement(cost, _UCfg.building_size("smithy"),
		func(pos: Vector3):
			var smithy := Smithy.new()
			smithy.faction = f
			main.world_add(smithy)
			smithy.global_position = pos,
		"Кузница")

func try_build_mine(castle: Building) -> void:
	if main == null:
		return
	var cost := _UCfg.building_cost("mine")
	if not ResourceManager.spend(castle.faction, cost):
		return
	var f := castle.faction
	main.enter_building_placement(cost, _UCfg.building_size("mine"),
		func(pos: Vector3):
			var mine := Mine.new()
			mine.faction = f
			main.world_add(mine)
			mine.global_position = pos,
		"Рудник")

# ── КЭШ СПИСКОВ ГРУПП НА ОДИН ФИЗИЧЕСКИЙ КАДР ────────────────────────────────
# get_tree().get_nodes_in_group() КАЖДЫЙ РАЗ строит новый массив. В свалке
# сотни бойцов за один кадр ищут цель, и каждый заново запрашивал список
# вражеских зданий — сотни аллокаций в кадр на список из трёх домов.
# Внутри одного кадра состав группы не меняется (queue_free отложен), поэтому
# массив можно переиспользовать. Проверки is_instance_valid у вызывающих
# остаются на месте.
var _grp_cache: Dictionary = {}
var _grp_frame: int = -1

func nodes_in_group_cached(group_name: String) -> Array:
	var f := Engine.get_physics_frames()
	if f != _grp_frame:
		_grp_frame = f
		_grp_cache.clear()
	if not _grp_cache.has(group_name):
		_grp_cache[group_name] = get_tree().get_nodes_in_group(group_name)
	return _grp_cache[group_name]

# ГОРЯЧИЕ ПРОКСИ К MAIN. Вызовы идут НАПРЯМУЮ (main.is_water(...)), а не через
# Object.call("имя", ...): call() каждый раз ищет метод по строке и упаковывает
# аргументы в Variant-массив. get_terrain_height/is_water дёргаются несколько
# раз за физический кадр КАЖДЫМ юнитом — на тысяче бойцов это десятки тысяч
# строковых поисков в кадр на ровном месте.
func find_nearest_resource(from_pos: Vector3, res_type: int) -> ResourceNode:
	if main == null:
		return null
	return main.find_nearest_resource(from_pos, res_type)

## Следующая жила ПОБЛИЗОСТИ: своя куча (руда) или соседний ствол (лес).
## null — рядом всё выработано; что делать дальше, решает сам рабочий
## (см. Worker._auto_find_resource): игроку положено встать, ИИ — идти дальше
## radius_scale — во сколько раз шире обычного искать (см. Worker.WIDE_SEARCH_SCALE);
## skip — жила, до которой дойти не удалось, её из поиска исключаем
func find_next_resource_nearby(from_pos: Vector3, res_type: int,
		cluster_id: int = 0, radius_scale: float = 1.0,
		skip: ResourceNode = null) -> ResourceNode:
	if main == null:
		return null
	return main.find_next_resource_nearby(from_pos, res_type, cluster_id,
		radius_scale, skip)

## ЯКОРЬ КУЧИ — кусок, который стоит до полной её выработки (MineCluster.anchor).
## Нужен рабочему, чтобы вернуться к работе, когда обычный поиск «рядом» его не
## нашёл: радиус поиска считается от рабочего, а его могло вытолкнуть в сторону
func cluster_anchor(cluster_id: int) -> ResourceNode:
	if main == null or cluster_id <= 0:
		return null
	var info: Dictionary = main.res_clusters.get(cluster_id, {})
	var mine = info.get("mine", null)
	if mine == null or mine.is_empty():
		return null
	return mine.anchor() as ResourceNode

## Ближайший кусок ЛЮБОЙ другой кучи того же типа (рабочие ИИ не застревают)
func find_next_cluster_resource(from_pos: Vector3, res_type: int,
		exclude_cluster: int = 0) -> ResourceNode:
	if main == null:
		return null
	return main.find_next_cluster_resource(from_pos, res_type, exclude_cluster)

func get_terrain_height(x: float, z: float) -> float:
	if main == null:
		return 0.0
	return main.get_terrain_height(x, z)

## Непроходимая вода: озеро и камни в нём. Юниты обходят его по суше.
func is_water(x: float, z: float) -> bool:
	if main == null:
		return false
	return main.is_water(x, z)

## Разрешённый шаг с обходом озера по берегу (Vector3.ZERO — пути нет)
func slide_around_water(from: Vector3, step: Vector3) -> Vector3:
	if main == null:
		return step
	return main.slide_around_water(from, step)

# ─────────────────────────────────────────────────────────────────────────────
# СТВОЛЫ ДЕРЕВЬЕВ КАК ПРЕПЯТСТВИЯ
#
# БАГ: юниты шли сквозь деревья насквозь, как призраки. Физические маски в
# проекте намеренно нулевые (см. README — включённые маски давали дрожание на
# грунте), поэтому обход считается так же, как обход озера и чужого строя:
# геометрией, а не физикой.
#
# Регистр — своя РЕДКАЯ сетка ячейками по OBST_CELL метров. Деревьев на карте
# под тысячу, юнитов — тысячи, поэтому перебирать список на каждый шаг нельзя;
# зато шаг короткий, и достаточно посмотреть 3×3 ячейки вокруг новой точки.
#
# Радиус берётся по КОМЛЮ (ResourceNode.TRUNK_RADIUS), а не по спрайту: квад
# дерева пять метров в поперечнике, и обходить его целиком означало бы, что
# лес физически непроходим. Обходят ствол, сквозь крону ходят свободно.
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# ПУЛ СТРЕЛ (см. шапку у Arrow._life)
#
# Выстрел стоил комплекта из двух узлов, своего QuadMesh, своего ShaderMaterial
# и объекта SceneTreeTimer — и всё это выбрасывалось через секунду полёта. При
# тысячах лучников залпы идут непрерывно, то есть комплект создаётся и гибнет
# сотни раз в секунду.
#
# Отстрелявшая стрела теперь ГАСНЕТ (visible = false, _process off) и ложится
# сюда; следующий выстрел забирает её и переписывает только числа полёта.
# Узел при этом ОСТАЁТСЯ В ДЕРЕВЕ — снятый был бы orphan-узлом и пережил бы
# смену сцены ничьим.
#
# Потолок нужен затем, что пул не должен становиться складом: после одного
# гигантского залпа держать в памяти его пик до конца партии незачем
const ARROW_POOL_MAX := 512

var _arrow_pool: Array = []

## Выдать стрелу под выстрел. Возвращает узел, уже стоящий в дереве под
## `parent` и взведённый на полёт
## Сколько стрел выпущено за партию. Монотонный, только растёт (см. spawn_arrow)
var arrows_fired: int = 0

func spawn_arrow(parent: Node, start: Vector3, end_pos: Vector3, dist: float,
		speed: float, arc_factor: float, dmg: float, who: Node3D,
		p_faction: int) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		return null
	# СЧЁТЧИК ВЫСТРЕЛОВ, монотонный. Стрелы живут в пуле и не состоят ни в одной
	# группе, поэтому «сколько выстрелов сделано» иначе не спросить: стенд
	# qa_volley считает по нему темп стрельбы отряда (залп — это пачки, обычная
	# стрельба — ровный ручеёк). Один int на выстрел
	arrows_fired += 1
	var a: Node3D = null
	# Пул мог пережить смену сцены: узлы из прошлой партии уже освобождены
	while not _arrow_pool.is_empty():
		var cand = _arrow_pool.pop_back()
		if is_instance_valid(cand):
			a = cand
			break
	var fresh: bool = a == null
	if fresh:
		a = _ArrowScript.new()
	a.set("_start_pos",  start)
	a.set("_end_pos",    end_pos)
	a.set("_dist",       dist)
	a.set("_speed",      speed)
	a.set("_arc_factor", arc_factor)
	a.set("damage",      dmg)
	a.set("shooter",     who)
	a.set("faction",     p_faction)
	if fresh:
		# У свежей взведение делает _ready(), уже после add_child
		parent.add_child(a)
	elif a.get_parent() != parent:
		a.get_parent().remove_child(a)
		parent.add_child(a)
	a.global_position = start
	if not fresh:
		a.call("launch")
	return a

# ─────────────────────────────────────────────────────────────────────────────
# ПОТОЛОК ЧИСЛА ТОРЧАЩИХ СТРЕЛ
#
# Здесь ЖЕ раньше жила spawn_stuck_arrow — «рождение декоративной стрелы, уже
# воткнувшейся»: тела, добитые залпом, добирали ею вторую и третью стрелу.
# Её убрали вместе с самим правилом (см. CorpseRenderer.MAX_ARROWS_PER_CORPSE),
# и по той же причине, по которой заведён этот потолок.
#
# ПОЧЕМУ ПОТОЛОК ВООБЩЕ НУЖЕН. Стрела — это УЗЕЛ со своим QuadMesh и своим
# ShaderMaterial, то есть отдельный вызов отрисовки; общего MultiMesh у стрел
# нет (ось у каждой своя, а квад разворачивает вокруг неё шейдер). Считаем:
# кулдаун лучника 4 с, промахом кончается больше половины выстрелов, торчит
# промах STUCK_LIFETIME = 45 с. Значит поле копит примерно N·45/8 торчащих
# стрел на N стрелков — на трёхстах лучниках это под две тысячи вызовов
# отрисовки, лежащих на лугу. Ровно это и роняло кадр в затяжной перестрелке.
#
# ПОЧЕМУ ПОТОЛОК, А НЕ КОРОТКИЙ СРОК. Сорок пять секунд — заказ владельца:
# место обстрела обязано читаться щетиной стрел ещё долго после того, как бой
# ушёл дальше. Срок мы не трогаем; ограничиваем ЧИСЛО. Пока стрел меньше
# потолка, картина ровно та, что заказана; когда больше — самые старые
# истаивают, и щетина остаётся там, где стреляют СЕЙЧАС.
#
# ПРОТИВ ПОТОЛКА СЧИТАЮТСЯ ТОЛЬКО НЕГАСНУЩИЕ. Догорающая остаётся в списке до
# конца растворения, и учёт по всей длине давал бы лавину: каждая новая стрела
# видела бы перебор и отправляла гаснуть ещё одну. Эту самую ошибку стенд
# qa_corpse уже ловил на телах (см. CorpseRenderer.spawn)
const MAX_STUCK_ARROWS := 160
## Насколько быстро истаивает вытесненная потолком. Заметно короче обычного
## растворения (Arrow.STUCK_FADE = 4 с): пока она гаснет, её место считается
## освободившимся, и на длинном растворении поле успевало бы уходить за
## потолок на весь залп
const STUCK_ARROW_EVICT_FADE := 0.6

var _stuck_arrows: Array = []

## Стрела воткнулась (в грунт или в тело) — взять её на учёт и, если поле
## переполнено, отправить догорать самые старые
func note_stuck_arrow(a: Node3D) -> void:
	if a == null or not is_instance_valid(a):
		return
	_stuck_arrows.append(a)
	if _stuck_arrows.size() <= MAX_STUCK_ARROWS:
		return
	# Проход от самых старых. Мусорные записи (узел освобождён мимо пула —
	# смена сцены, стенд) вычищаются здесь же: без этого список рос бы вечно и
	# потолок начал бы гасить живые стрелы вместо давно исчезнувших
	var keep: Array = []
	var over: int = _stuck_arrows.size() - MAX_STUCK_ARROWS
	for old in _stuck_arrows:
		if old == null or not is_instance_valid(old):
			over -= 1
			continue
		if over > 0:
			over -= 1
			# Догорающая место уже освобождает — второй раз её не трогаем
			if not old.is_fading():
				old.fade_out_in(STUCK_ARROW_EVICT_FADE)
		keep.append(old)
	_stuck_arrows = keep

## Стрела ушла с поля (догорела, вытеснена, вернулась в пул)
func forget_stuck_arrow(a: Node3D) -> void:
	if _stuck_arrows.is_empty():
		return
	_stuck_arrows.erase(a)

## Сколько стрел торчит на поле прямо сейчас (стенды)
func stuck_arrow_count() -> int:
	return _stuck_arrows.size()

## Принять погасшую стрелу обратно (зовёт Arrow._despawn)
func recycle_arrow(a: Node3D) -> void:
	if _arrow_pool.size() >= ARROW_POOL_MAX:
		a.queue_free()
		return
	_arrow_pool.append(a)

## Новая партия: узлы прошлой сцены уже недействительны
func clear_arrow_pool() -> void:
	for a in _arrow_pool:
		if is_instance_valid(a):
			a.queue_free()
	_arrow_pool.clear()
	# Реестр торчащих держит узлы прошлой сцены — та же оговорка, что у пула
	_stuck_arrows.clear()

## Сколько стрел лежит наготове (стенды)
func arrow_pool_size() -> int:
	return _arrow_pool.size()

# ═══════════════════════════════════════════════════════════════════════════
# РЕЕСТР СТВОЛОВ ПЕРЕЕХАЛ В СОЛВЕР (csharp/ArmyCore.cs)
# ═══════════════════════════════════════════════════════════════════════════
# Здесь лежала своя редкая сетка ячейками по 4 м со словарём Vector2i → Array.
# Она переехала к колонкам по одной причине: trunk_block был ПОСЛЕДНИМ вызовом
# наружу, остававшимся ВНУТРИ шага бойца. Пока он жил тут, пакетный проход на
# каждого идущего бойца прыгал из C# обратно в GDScript — то есть платил за
# переход границы ровно там, где мы её и убирали.
#
# Имена и сигнатуры сохранены: ResourceNode, Main и стенды зовут их как раньше.
func register_trunk(pos: Vector3, radius: float) -> void:
	army.register_trunk(pos, radius)

func unregister_trunk(pos: Vector3) -> void:
	army.unregister_trunk(pos)

func clear_trunks() -> void:
	army.clear_trunks()

## Сколько стволов на учёте (для стендов)
func trunk_count() -> int:
	return army.trunk_count()

## Наталкивается ли точка на ствол. Возвращает вектор ОТ центра ствола к точке,
## длиной в глубину проникновения; Vector3.ZERO — путь свободен
func trunk_block(x: float, z: float, body_r: float) -> Vector3:
	return army.trunk_block(x, z, body_r)

## Есть ли хоть один ствол в радиусе. Грубый ответ для коридора отряда
func trunk_near(x: float, z: float, radius: float) -> bool:
	return army.trunk_near(x, z, radius)

## Точка приказа, вынесенная на сушу. Приказ, пришедший в озеро (клик по воде,
## точка сбора ИИ у берега), иначе недостижим: юнит упирается в кромку, а
## дистанция до цели никогда не падает ниже порога прибытия — отряд «висит»
func land_target(pos: Vector3) -> Vector3:
	if main == null:
		return pos
	# СНАЧАЛА ГРАНИЦА МИРА: приказ за край карты недостижим так же, как приказ
	# в воду — юнит упрётся в стену, а дистанция до цели не упадёт ниже порога
	# прибытия, и отряд «повиснет»
	var c: Vector2 = clamp_to_map(pos.x, pos.z)
	if not main.is_water(c.x, c.y):
		return Vector3(c.x, main.get_terrain_height(c.x, c.y), c.y)
	var p: Vector2 = main.nearest_land(c.x, c.y)
	return Vector3(p.x, main.get_terrain_height(p.x, p.y), p.y)

## ВЫКЛЮЧАТЕЛЬ ГРАНИЦ МИРА. В игре всегда true. Снимают его ТОЛЬКО стенды:
## им нужна «чистая комната» далеко за картой, где ни ИИ, ни лес, ни чужие
## отряды не мешают замеру. С включённой границей такая площадка схлопывалась
## бы в угол карты, и все юниты стенда сваливались в кучу.
var world_bounds_enabled: bool = true

## ПРЕДЕЛЫ КАРТЫ, СНЯТЫЕ ОДИН РАЗ. Раньше каждый вызов уходил в main.clamp_to_map(),
## то есть на КАЖДЫЙ шаг КАЖДОГО бойца приходился лишний межобъектный вызов с
## чтением четырёх констант. Замер (qa_world2, раздел F): 2.24 мкс на бойца в
## кадр, +14.6% к кадру на 1000 бойцов — при цели в 10 000 это 22 мс, то есть
## весь бюджет кадра. Теперь пределы лежат готовыми числами, и зажим сводится
## к двум clampf.
## ПОЛЯ ОТКРЫТЫЕ: горячий путь (Unit._move_blocked) зажимает точку сам, двумя
## clampf по этим числам, без вызова clamp_to_map — ровно та же экономия
## межобъектного вызова, что и раньше на main.clamp_to_map
var map_lim_x: float = 1e9
var map_lim_z: float = 1e9

## ЕСТЬ ЛИ НА КАРТЕ ВОДА ВООБЩЕ (Main.LAKE_ENABLED). Озеро сейчас отключено, и
## каждый шаг каждого бойца делал ДВА межобъектных вызова (GameManager.is_water
## → main.is_water) ради ответа «нет» по константе. Флаг снимается один раз при
## постройке мира; до этого он true, то есть поведение прежнее
var water_active: bool = true

## ── ТОЧКА ОБЗОРА ДЛЯ ОТСЕЧЕНИЯ ДАЛЬНИХ СПРАЙТОВ ─────────────────────────────
## Фокус камеры обновляется РАЗ В КАДР одним местом, а не спрашивается каждым
## бойцом: обращение к камере через дерево из горячего пути — это тысячи
## лишних поисков узла в секунду
var _view_x: float = 0.0
var _view_z: float = 0.0
var _view_r2: float = 1e18

## ── РАДИУС «ВИДНО» ОБЯЗАН СЛЕДОВАТЬ ЗА ЗУМОМ ────────────────────────────────
## Здесь стоял ОДИН радиус на все случаи — `lod_radius`, девяносто метров от
## точки фокуса. Пока камера подведена близко, это честно. Но отдалённая
## ортокамера показывает на земле полосу в две-три сотни метров, и всё, что
## дальше девяноста от центра экрана, считалось «невидимым», оставаясь при
## этом НА ЭКРАНЕ. Такому бойцу переставали считать позу, кадр ленты и — что
## хуже — перенос его слота в общий буфер. Отсюда все три жалобы разом:
## «пехота едет с замершими ногами», «рабочие рубят без анимации» и «жёлтые
## кольца отстают от бойцов» (кольцо-то берёт нарисованную точку, которую
## сглаживание честно двигает каждый кадр, а сам спрайт стоит).
##
## Теперь радиус — это МАКСИМУМ из настроечного и фактически видимой на земле
## полосы, которую сообщает камера. Экономия LOD остаётся там, где ей и место:
## за краем экрана
## Радиус видимой земли, метры. Тот самый, по которому живёт LOD; им же
## пользуется звук марша, чтобы его слышимость не отставала от зума
func view_radius() -> float:
	return sqrt(_view_r2) if _view_r2 < INF else 0.0

func update_view_point(pos: Vector3, ground_radius: float = 0.0) -> void:
	_view_x = pos.x
	_view_z = pos.z
	var r: float = maxf(_Opt.lod_radius, ground_radius)
	_view_r2 = r * r

## ── ОСИ КАМЕРЫ, СНЯТЫЕ РАЗ В КАДР ───────────────────────────────────────────
## Спрайты — билборды, поэтому «влево/вправо» и выбор ракурса из 8 секторов
## считаются не в мировых осях, а ОТНОСИТЕЛЬНО КАМЕРЫ. Раньше каждый боец
## доставал камеру сам: `get_viewport().get_camera_3d()` — это поиск вьюпорта
## по дереву плюс обращение к движку, и делалось это ДВАЖДЫ за кадр на бойца
## (Unit._update_sprite_flip и Spearman._screen_angle). На 1200 моделях —
## под две с половиной тысячи поисков узла в каждом кадре на ровном месте.
##
## Теперь оси снимаются ОДИН раз за кадр и раздаются готовыми векторами.
## Обновление ленивое (по номеру кадра), поэтому стенды и сцены без RTSCamera
## работают без единой правки: первый спросивший в кадре и обновит кэш.
var _cam_right: Vector3 = Vector3.RIGHT
var _cam_fwd:   Vector3 = Vector3.FORWARD
var _cam_ok:    bool    = false
var _cam_frame: int     = -1

func _refresh_camera_axes() -> void:
	var f := Engine.get_process_frames()
	if f == _cam_frame:
		return
	_cam_frame = f
	var tree := get_tree()
	var cam: Camera3D = null
	if tree != null:
		var vp := tree.root.get_viewport()
		if vp != null:
			cam = vp.get_camera_3d()
	if cam == null:
		_cam_ok = false
		return
	var b := cam.global_transform.basis
	var right := Vector3(b.x.x, 0.0, b.x.z)
	var fwd   := Vector3(-b.z.x, 0.0, -b.z.z)   # куда смотрит камера, по XZ
	if right.length_squared() < 1e-6 or fwd.length_squared() < 1e-6:
		_cam_ok = false
		return
	_cam_right = right.normalized()
	_cam_fwd   = fwd.normalized()
	_cam_ok    = true

## Камера найдена и её оси годны к употреблению
func camera_axes_valid() -> bool:
	_refresh_camera_axes()
	return _cam_ok

## Ось «вправо по экрану» в плоскости XZ (единичная)
func camera_right() -> Vector3:
	_refresh_camera_axes()
	return _cam_right

## Ось «от зрителя вглубь» в плоскости XZ (единичная)
func camera_forward() -> Vector3:
	_refresh_camera_axes()
	return _cam_fwd

## ── ТУМБЛЕР ПОЛОСОК ЗДОРОВЬЯ (ALT) ──────────────────────────────────────────
## По умолчанию полоска появляется над бойцом только когда он ранен: у целого
## отряда на марше лишних узлов нет, и это заметная экономия на 1200 моделях.
## Игроку, однако, регулярно нужен полный срез — кто на исходе, куда бить.
##
## Alt переключает ГЛОБАЛЬНЫЙ флаг: пока он поднят, полоски висят у ВСЕХ живых
## юнитов и построек, включая целых. Флаг хранится здесь, а не в HUD, потому
## что читать его должен каждый вновь заспавненный боец в своём _ready() —
## иначе подкрепление выходило бы из ворот без полосок, пока его не ранят.
var hp_bars_forced: bool = false

## Кто-то переключил тумблер. HUD слушает, чтобы подсветить подсказку
signal hp_bars_toggled(shown: bool)

## Переключить и разослать. Возвращает НОВОЕ состояние флага
func toggle_hp_bars() -> bool:
	set_hp_bars_forced(not hp_bars_forced)
	return hp_bars_forced

func set_hp_bars_forced(value: bool) -> void:
	if hp_bars_forced == value:
		return
	hp_bars_forced = value
	_refresh_all_hp_bars()
	hp_bars_toggled.emit(hp_bars_forced)

## Разовый проход по всем живым сущностям. Дорого, но случается только в момент
## нажатия Alt — в горячем пути кадра этого нет
func _refresh_all_hp_bars() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for g in ["all_units", "all_buildings"]:
		for n in tree.get_nodes_in_group(g):
			if is_instance_valid(n) and n.has_method("refresh_hp_bar"):
				n.refresh_hp_bar()

## Рядом ли точка с тем, куда смотрит игрок. Сравнение КВАДРАТОВ — без корня
func near_view(pos: Vector3) -> bool:
	var dx: float = pos.x - _view_x
	var dz: float = pos.z - _view_z
	return dx * dx + dz * dz <= _view_r2

## ── ОГОНЬ ПО ОТРЯДУ, А НЕ ПО ПИКСЕЛЮ ────────────────────────────────────────
## Игрок кликает по ОДНОЙ модели, но воюют отряды. Здесь клик разворачивается
## в цель для конкретного стрелка: из отряда жертвы берётся боец, по которому
## УЖЕ бьёт меньше всех, а при равенстве — ближайший к стрелку.
##
## Зачем: без этого сорок лучников выпускали залп в одну модель, тридцать пять
## стрел уходили в уже мёртвого, а остальной вражеский отряд стоял целым.
## Штраф за плотность (CROWD_PENALTY) тот же, что в обычном поиске цели, —
## поведение отряда остаётся узнаваемым.
func squad_pick_member(target_squad: int, from_pos: Vector3, fallback: Node3D) -> Node3D:
	if target_squad == 0 or not squads.has(target_squad):
		return fallback
	var best: Node3D = null
	var best_score := INF
	for m in squad_members(target_squad):
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		# Дистанция + штраф за уже целящихся: залп размазывается по шеренге
		var score: float = from_pos.distance_to(u.global_position) \
			+ float(u.attackers) * Unit.CROWD_PENALTY
		if score < best_score:
			best_score = score
			best = u
	return best if best != null else fallback

## ── ОБЩИЙ ПОИСК ЦЕЛИ НА ОТРЯД ───────────────────────────────────────────────
## squad_id → {"r": радиус, "t": время, "n": цель}. Держится ровно один слот на
## отряд: разные радиусы (копьё против лука) кэш просто не переиспользуют.
## Мёртвые цели отсекаются здесь же — в Godot 4 освобождённый объект равен null
var _squad_target: Dictionary = {}

## Готовый ответ или null, если кэш пуст/протух/цель погибла
func squad_target_get(sid: int, radius: float, now: float) -> Node3D:
	var e: Dictionary = _squad_target.get(sid, {})
	if e.is_empty():
		return null
	if absf(float(e.get("r", -1.0)) - radius) > 0.01:
		return null
	if now - float(e.get("t", -999.0)) > _Opt.squad_target_ttl:
		return null
	var n = e.get("n")
	if n == null or not is_instance_valid(n):
		return null
	if n.has_method("is_dead") and n.is_dead():
		return null
	return n

func squad_target_put(sid: int, radius: float, target: Node3D, now: float) -> void:
	_squad_target[sid] = {"r": radius, "t": now, "n": target}

## ── КУДА СМОТРИТ СТРОЙ: ОДИН СКАН НА ОТРЯД ──────────────────────────────────
## Фаланга в стойке ЗАЩИТА пересчитывает свой ряд четыре раза в секунду, и
## каждый боец при этом искал ближайшего врага сам — сканом радиусом 10 м.
## При ячейке сетки 1 м это 441 ячейка НА БОЙЦА: отряд в 50 человек перебирал
## двадцать две тысячи ячеек на один пересчёт, и стойка ЗАЩИТА выходила
## впятеро дороже стойки АТАКА (замер qa_bugpack2, раздел 9b).
##
## Но вся шеренга и так обязана смотреть В ОДНУ СТОРОНУ — иначе ряды считаются
## вкривь (см. SpatialGrid.nearest_enemy_offset). Значит, и скан на отряд нужен
## ОДИН: первый спросивший ищет врага и кладёт его МИРОВУЮ ТОЧКУ в кэш,
## остальные берут готовую и считают от неё своё направление сами.
##
## Хранится именно точка, а не смещение: смещение годится только тому бойцу,
## который его запросил, а точка — всем.
var _squad_face: Dictionary = {}
## Сколько живёт общий ответ. Совпадает с периодом пересчёта ряда
## (Unit.RANK_RECHECK): дольше держать нельзя — строй потеряет разворот врага
const SQUAD_FACE_TTL := 0.25

## Мировая точка ближайшего врага для отряда. Второе значение — нашли ли.
## sid = 0 (боец вне отряда) кэш не использует: делить ему не с кем
func squad_enemy_pos(sid: int, asker: Node3D, radius: float) -> Array:
	if sid <= 0:
		return unit_grid.nearest_enemy_pos(asker, radius)
	var now: float = float(Time.get_ticks_msec()) * 0.001
	var e: Dictionary = _squad_face.get(sid, {})
	if not e.is_empty() and now - float(e.get("t", -999.0)) <= SQUAD_FACE_TTL \
			and absf(float(e.get("r", -1.0)) - radius) < 0.01:
		return [e.get("p", Vector3.ZERO), bool(e.get("ok", false))]
	var res: Array = unit_grid.nearest_enemy_pos(asker, radius)
	# Заодно запоминаем ОДИН КУРС НА ОТРЯД — от спросившего к найденному врагу.
	# Точки мало: каждый боец, считая направление ОТ СЕБЯ к общей точке,
	# получает свой угол, и у отряда шириной в шесть человек крайние колонны
	# расходятся с центром на 15–20°. Полоса подсчёта ряда разворачивается
	# наискось, сосед СБОКУ засчитывается как стоящий впереди, и строй теряет
	# понимание, где у него перёд (см. Unit._phalanx_dir)
	var d := Vector3.ZERO
	if bool(res[1]):
		d = (res[0] as Vector3) - asker.global_position
		d.y = 0.0
		d = d.normalized() if d.length_squared() > 1e-6 else Vector3.ZERO
	_squad_face[sid] = {"t": now, "r": radius, "p": res[0], "ok": res[1], "d": d}
	return res

## Общий курс отряда «на противника», снятый вместе с кэшем ближайшего врага.
## Vector3.ZERO — кэша нет либо врага не видно
func squad_enemy_dir(sid: int) -> Vector3:
	if sid <= 0:
		return Vector3.ZERO
	var e: Dictionary = _squad_face.get(sid, {})
	return e.get("d", Vector3.ZERO)

## Пересчитать пределы. Зовёт Main после постройки мира; стенды — если меняют
## размер карты на лету
func refresh_map_bounds() -> void:
	if main == null:
		map_lim_x = 1e9
		map_lim_z = 1e9
		water_active = false
		return
	map_lim_x = float(main.MAP_HALF_X) - float(main.MAP_EDGE_MARGIN)
	map_lim_z = float(main.MAP_HALF_Z) - float(main.MAP_EDGE_MARGIN)
	water_active = bool(main.LAKE_ENABLED)

## Точка, зажатая в границы карты (Vector2 = x/z). Через неё проходит каждое
## перемещение юнита: за край мира не выходит никто и никогда.
## ГОРЯЧИЙ ПУТЬ — держать без вызовов наружу
func clamp_to_map(x: float, z: float) -> Vector2:
	if not world_bounds_enabled:
		return Vector2(x, z)
	return Vector2(clampf(x, -map_lim_x, map_lim_x),
		clampf(z, -map_lim_z, map_lim_z))
