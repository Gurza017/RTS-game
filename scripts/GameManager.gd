extends Node

var main: Node3D = null
var dropoffs: Dictionary = {}
# Пространственная сетка юнитов (см. SpatialGrid.gd); load() — чтобы не зависеть от кэша классов
var unit_grid = load("res://scripts/SpatialGrid.gd").new()
## Общий MultiMesh стрел (этап D3): картинка всех стрел одним вызовом отрисовки
var arrows_mm = load("res://scripts/ArrowRenderer.gd").new()
## ── КОСТЬ ГНОЛЛА — ВТОРОЙ ЭКЗЕМПЛЯР ТОГО ЖЕ СЛОЯ ──────────────────────────
## ArrowRenderer держит ОДНУ текстуру на весь свой MultiMesh (материал общий
## на бакет), поэтому кость нельзя подмешать в слой стрел ни модуляцией, ни
## подменой картинки: у первой же стрелы изменился бы вид. Второй экземпляр
## слоя стоит ровно один дополнительный вызов отрисовки на все кости в воздухе
## и достаёт из ядра тот же пакетный проход полёта (у него свой rb_create и
## свой core_id, а arrow_launch принимает его номером аргумента)
var bones_mm = load("res://scripts/ArrowRenderer.gd").new()
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

## ── БОЕЦ УШЁЛ С КАРТЫ ЖИВЫМ (ГАРНИЗОН) ──────────────────────────────────────
## СМЕРТЬ снимает с бойца все надстроенные слои разом (см. Unit._unhook), а уход
## В ЗАМОК — нет: боец жив, узел на месте, из отряда не выбыл, и всё, что
## рисуется НАД ним, продолжало числиться как ни в чём не бывало.
##
## Больнее всего это било по кольцу выделения. Кольцо ездит по НАРИСОВАННОЙ
## точке (см. SelectionDecalRenderer.update_all), а нарисованная точка ЗАМЕРЗАЕТ
## в тот самый кадр, когда бойцу гасят визуальный тик, — то есть у ворот. Игрок
## отправляет побитый отряд в замок, бойцы исчезают, а на их месте остаётся
## кучка жёлтых колец в чистом поле — ровно то, что на скриншоте владельца.
## Замер (зонд qa_keep, шесть копейщиков): внутри 6 из 6, колец на карте 6,
## нарисованная точка (−90, 99) при замке в (−90, 90) — девять метров пустой
## травы.
##
## Снимаем БЕЗУСЛОВНО, а не по флагу выделения: снятие идемпотентно, а флаг —
## всего лишь второе описание того же факта, и разойтись они уже могут (та же
## оговорка, что в Unit._unhook)
func forget_on_map(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	# ИЗ ВЫДЕЛЕНИЯ — ПЕРВЫМ ДЕЛОМ. Иначе панель показывает отряд, которого на
	# карте нет, а следующий приказ игрока уходит бойцу, сидящему в замке
	var sm = main.get("selection_manager") if main != null else null
	if sm != null and is_instance_valid(sm) and sm.has_method("forget_unit"):
		sm.forget_unit(unit)
	unit.set_selected(false)
	sel_decals.unregister(unit)
	sel_decals.drop_hover(unit)
	# Полоска здоровья своего гейта на гарнизон УЖЕ имеет (см. Unit._update_hp_bar),
	# но сама она к нему не сходит: боец снят с тика. Дёргаем явно
	unit.refresh_hp_bar()

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
	# ЧАСЫ АРМИИ — ОДНО ЧТЕНИЕ НА КАДР (см. Unit.now_ms). Их спрашивали шесть
	# горячих мест, и каждое — на бойца
	Unit.now_ms = Time.get_ticks_msec()
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
	# Событийная поза (этап E3): расписание остаётся страховкой, в разы реже
	if _Opt.pose_events:
		anim_every *= maxi(_Opt.pose_safety_mult, 1)
	# Поворот камеры — событие на всю армию: оси снимаются раз в кадр
	_refresh_camera_axes()
	var cam_ep: int = _cam_epoch
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
					lerpk, mm_all, vprof, fog_on, cam_ep)
	else:
		var i: int = frame % vshards
		var d: float = _delta * float(vshards)
		while i < live_n:
			var u = _live_units[i]
			if is_instance_valid(u) and u.draw_on:
				u.tick_visual(d, frame, anim_every, vx0, vz0, vr2,
					lerpk, mm_all, vprof, fog_on, cam_ep)
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
		# Доля сближения — ОДНА НА ВСЮ АРМИЮ и уже посчитана выше: читать её у
		# автозагрузки из каждого бойца значило бы три с половиной тысячи
		# обращений к чужому объекту в кадр (см. Unit.tick_draw)
		var ck: float = lerpk
		for u in _live_units:
			if is_instance_valid(u) and u.draw_on:
				u.tick_draw(ck)
	# Метки выделения и полоски здоровья — СРАЗУ ПОСЛЕ бойцов и ДО подачи в
	# рендер: они берут ту же нарисованную точку, которую только что посчитал
	# tick_visual, и обязаны совпасть с ней кадр в кадр
	# ── ХВОСТ КАДРА ЗАМЕРЯЕТСЯ ОТДЕЛЬНЫМИ ВЕТКАМИ ──────────────────────────
	# До этого весь хвост шёл мимо профиля: разбивка показывала только тик
	# бойцов, а «остальное» приходилось считать вычитанием из общего кадра.
	# Между тем подача буферов в рендер (far_units.flush → set_buffer на бакет)
	# растёт прямо с числом бойцов и в тик бойцов не входит вовсе
	var _t1: int
	# ── ПОКАДРОВЫЙ ДОГОН КАРТИНКИ — ОДИН C#-ПРОХОД (этап C.1) ───────────────
	# ПОСЛЕ тика бойцов (события поз/лент уже записаны) и ДО меток с подачей:
	# кольца и полоски берут ту же нарисованную точку. Догон идёт КАЖДЫЙ кадр
	# отрисовки, а не раз в визуальный такт, поэтому доля сближения считается
	# от интервала обновления ЛОГИЧЕСКОЙ точки (шарды физики): картинка
	# догоняет тело ровно к его следующему шагу — та же постоянная времени,
	# что и была, только шаг догона мельче и чаще
	if vprof: _t1 = Time.get_ticks_usec()
	var psh: int = _Opt.shards_for(live_n)
	var core_k: float = clampf(
		_delta / maxf(float(psh) / float(Engine.physics_ticks_per_second)
			* VIS_SMOOTH_TAU, 0.0005), 0.0, 1.0) \
		if _Opt.visual_smoothing else 1.0
	if _Opt.vis_core_path:
		army.batch_visual(_delta, core_k, Unit.VIS_SNAP_SQ,
			Unit.BOB_AMPLITUDE * Unit.UNIT_SCALE, Unit.BOB_SPRINT_MULT,
			_Opt.anim_core, _Opt.decal_core)
	if vprof: _Opt.prof_add("vis_core", Time.get_ticks_usec() - _t1)
	# ── ПОЛЁТ СТРЕЛ — ОДИН ПРОХОД ЯДРА (хак физтика №1) ────────────────────
	# В кадре отрисовки, как и прежний Arrow._process: на паузе стрелы стоят
	if vprof: _t1 = Time.get_ticks_usec()
	if _Opt.arrow_core and (arrows_mm.flight_count() > 0 or bones_mm.flight_count() > 0):
		# ПРОХОД ЯДРА ОДИН НА ОБА СЛОЯ: полёты лежат в общем реестре ядра, а
		# слои различаются только тем, в чей буфер писать. Второй вызов
		# batch_arrows посчитал бы кадр полёта дважды
		army.batch_arrows(_delta, _ArrowScript.HIT_RADIUS)
		# События — ОДНИМ забором на оба слоя (см. ArrowRenderer.dispatch_events)
		_ArrowRendererScript.dispatch_events(army.take_arrow_events(), [arrows_mm, bones_mm])
		# Страховка: полёт без события старше MAX_FLIGHT_SEC гасится
		_flight_sweep_t -= _delta
		if _flight_sweep_t <= 0.0:
			_flight_sweep_t = 1.0
			arrows_mm.sweep_flights(_ArrowScript.MAX_FLIGHT_SEC)
			bones_mm.sweep_flights(_ArrowScript.BONE_MAX_FLIGHT_SEC)
	if vprof: _Opt.prof_add("arrow_core", Time.get_ticks_usec() - _t1)
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
	# Торчащие стрелы — той же строкой и по той же причине, что тела: своего
	# покадрового тика у декорации нет (см. _sweep_stuck_arrows)
	if not _stuck_arrows.is_empty():
		_sweep_stuck_arrows(_delta)
	# Указатели отданных приказов: пересчитываются по выделению и гаснут сами,
	# когда отряд дошёл (см. _refresh_order_marks)
	if vprof: _t1 = Time.get_ticks_usec()
	_refresh_order_marks(_delta)
	sel_decals.flush_orders()
	if vprof: _Opt.prof_add("draw_orders", Time.get_ticks_usec() - _t1)
	# Знамёна ветеранства едут за знаменосцами (см. _update_squad_banners).
	# Стоит ПОСЛЕ тика бойцов: нарисованные точки за этот кадр уже окончательные
	if vprof: _t1 = Time.get_ticks_usec()
	# Белый флаг паники ездит ТЕМ ЖЕ обходом: он и есть знамя отряда, только с
	# другой лентой (см. _show_panic_flag). Отдельного прохода по реестру
	# больше нет — вместе с ним ушла и вторая точка, по которой флаг мог
	# разъехаться со знаменем
	_update_squad_banners()
	if vprof: _Opt.prof_add("draw_banners", Time.get_ticks_usec() - _t1)
	# ── СЧЁТЧИК ЗАКРЫВАЕТСЯ ЗДЕСЬ, А НЕ ПОСЛЕ ЦИКЛА ПО БОЙЦАМ ──────────────
	# Он стоял сразу за обходом армии и не видел ВЕСЬ хвост кадра: метки,
	# подачу буферов в рендер, тела, указатели приказов, знамёна. Из-за этого
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

## Накопитель пропущенных тактов армии (см. perf_config.army_tick_div)
var _army_acc: float = 0.0
var _army_phase: int = 0
## СЧЁТЧИК ТАКТОВ АРМИИ — фазы шардов считаются ОТ НЕГО, а не от номера кадра
## движка: при army_tick_div = 2 армия тикает только по чётным кадрам, и
## «get_physics_frames() % shards» при чётном числе шардов давал ВЕЧНО ОДНУ
## фазу — половина армии не тикала вовсе (поймал qa_mega_battle B4-3:
## «сдвинулись 300, остались 300» — ровно половина)
var army_ticks: int = 0

func _physics_process(delta: float) -> void:
	# ── ТИК АРМИИ НА ПОЛОВИННОЙ ЧАСТОТЕ (этап C.2) ──────────────────────────
	# Весь обход армии идёт каждый army_tick_div-й такт движка с НАКОПЛЕННОЙ
	# дельтой: вся логика ниже дельта-честная, и для неё это неотличимо от
	# редкого движка, а стрелы, камера и часы стендов остаются на 60 Гц.
	# Личную частоту бойца держит лестница шардов (perf_config.shards_for от
	# army_hz). Картинку между тактами армии догоняет BatchVisual в _process
	_army_acc += delta
	_army_phase += 1
	if _army_phase < _Opt.army_tick_div:
		return
	_army_phase = 0
	delta = _army_acc
	_army_acc = 0.0
	army_ticks += 1
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
	# ЧАСЫ АРМИИ И НОМЕР КАДРА — ОДНО ЧТЕНИЕ НА ТИК (см. Unit.now_ms/phys_frame)
	army.set_threads(_Opt.core_threads)
	Unit.now_ms = Time.get_ticks_msec()
	Unit.phys_frame = army_ticks
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
	# ── МНОЖИТЕЛЬ ОТРЯДНЫХ СРОКОВ СНИМАЕТСЯ РАЗ В КАДР ────────────────────
	# Правило проекта: всё, что одинаково для всей армии, читается один раз за
	# кадр и передаётся дальше. Здесь это особенно важно — множитель спрашивают
	# два обхода, и оба заходят в него десятками отрядов за кадр
	_ttl_scale = _Opt.squad_ttl_scale(active_units())
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
	# ── ТАКТ ЗАЛПА — РАЗ В VOLLEY_SWEEP_EVERY КАДРОВ (спринт 19, стресс-отчёт) ─
	# Обход всех отрядов с разбором способности (toggle_ability_of по типу,
	# squad_ability_on) стоил 0.42 мс КАЖДЫЙ кадр при двух отрядах лучников
	# (qa_stress_report: 420 мкс на вызов). Окно залпа и так живёт по часам в
	# миллисекундах (volley_until / volley_next), и точность в 50 мс ему не
	# мешает: три кадра — меньше разброса личной перезарядки
	if _prof: _t0 = Time.get_ticks_usec()
	if army_ticks % VOLLEY_SWEEP_EVERY == 0:
		_sweep_volleys()
	if _prof: _Opt.prof_add("squad_volley", Time.get_ticks_usec() - _t0)
	# ── ЦЕНТРОВЫЕ НОДЫ СТРЕЛКОВЫХ ОТРЯДОВ (см. _sweep_squad_radar) ─────────
	# ДО обхода бойцов: открытый здесь огонь стрелки застанут в этом же кадре.
	# Свои часы в миллисекундах, поэтому такт свода кадрам не подчинён
	if _prof: _t0 = Time.get_ticks_usec()
	_sweep_squad_radar()
	_sweep_march_radar()
	if _prof: _Opt.prof_add("squad_radar", Time.get_ticks_usec() - _t0)
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
	# ── ДРЁМА ПЕРЕЗАРЯДКИ: ТАЙМЕРЫ И СТРАЖА ЦЕЛИ ТИКАЮТ В ЯДРЕ (этап C) ─────
	# ДО обхода армии: проснувшийся в этом кадре обязан получить свой полный
	# боевой автомат этим же тиком. Список проснувшихся забирается ТОЛЬКО при
	# ненулевом счёте — в тихий кадр здесь один переход границы и ноль
	# аллокаций. Рабочее правило пробуждения — в шапке ArmyCore.TickSnooze
	if _prof: _t0 = Time.get_ticks_usec()
	if army.tick_snooze(delta, Unit.ATK_SNOOZE_SPARE) > 0:
		var woken: Array = army.take_woken()
		var wi := 0
		while wi < woken.size():
			var raw: Variant = woken[wi]
			# Живость — на сырой ссылке, до приведения типа (правило 5)
			if raw != null and is_instance_valid(raw):
				var wu := raw as Unit
				if wu != null:
					wu._atk_wake(float(woken[wi + 1]))
			wi += 2
	if _prof: _Opt.prof_add("atk_snooze", Time.get_ticks_usec() - _t0)
	var shards: int = _Opt.shards_for(active_units())
	var _bm_now: bool = _Opt.batch_move
	if _Opt.batch_combat:
		if _prof: _t0 = Time.get_ticks_usec()
		atk_need = army.batch_combat(delta, Unit.State.ATTACKING,
			Unit.PULL_UP_SPEED, Unit.PULL_UP_MAX,
			shards, army_ticks % maxi(shards, 1))
		if _prof: _Opt.prof_add("batch_combat", Time.get_ticks_usec() - _t0)
	if _prof: _t0 = Time.get_ticks_usec()
	# ── ЧЕРЕДОВАНИЕ ПО КАДРАМ (см. perf_config.shards_for) ──────────────────
	# Кадр держит работа в ОДНОМ кадре, а не за секунду. Пока армия невелика,
	# shards == 1 и это ровно прежний цикл; на пяти тысячах армия делится
	# надвое, и каждый боец опрашивается через кадр — с удвоенной delta, так
	# что путь, откаты ударов и таймеры остаются те же
	if _Opt.class_meter:
		# Измеритель по родам войск (стресс-отчёт): та же раскладка по шардам,
		# плюс часы вокруг каждого тика. Отдельная ветка, чтобы штатный цикл
		# не платил за проверку внутри
		_Opt.class_frame()
		var cn: int = _live_units.size()
		var ci: int = 0 if shards <= 1 else army_ticks % shards
		var cstep: int = maxi(shards, 1)
		var cd: float = delta * float(cstep)
		while ci < cn:
			var cu = _live_units[ci]
			if is_instance_valid(cu) and cu.tick_on:
				var ct: int = Time.get_ticks_usec()
				cu.tick_physics(cd, _prof, _bm_now, bonus_version)
				_Opt.class_add(String(cu.stat_id), Time.get_ticks_usec() - ct)
			ci += cstep
	elif shards <= 1:
		for u in _live_units:
			if is_instance_valid(u) and u.tick_on:
				u.tick_physics(delta, _prof, _bm_now, bonus_version)
	else:
		var n: int = _live_units.size()
		var i: int = army_ticks % shards
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
	# ── ТЫЛОВОЙ НАПОР: ЗАЯВКИ НА ШАГ ОТ ЯДРА (этап D1) ──────────────────────
	# ПОСЛЕ подачи поз (велосити напора перепишет свежие) и ДО пакетного шага:
	# заявки идут той же геометрией BatchMoveRows, что и очередь бойцов
	if _Opt.rear_press:
		if _prof: _t0 = Time.get_ticks_usec()
		army.rear_press_pass(delta, shards, army_ticks % maxi(shards, 1))
		if _prof: _Opt.prof_add("rear_press", Time.get_ticks_usec() - _t0)
	# ── АВТОПИЛОТ ПОДХОДА: ШАГИ ОТ ЯДРА (этап D1) ───────────────────────────
	# Стража «враг в длине руки» — каждые 12 тактов на строку (5 Гц при 60):
	# та же редкость, что у личного опроса перехвата в полном автомате
	if _Opt.approach_autopilot:
		if _prof: _t0 = Time.get_ticks_usec()
		army.autopilot_pass(delta, shards, army_ticks % maxi(shards, 1),
			army_ticks, 12, Unit.LOCK_BLOCKER_RANGE + Unit.INTERCEPT_MARGIN)
		if _prof: _Opt.prof_add("autopilot", Time.get_ticks_usec() - _t0)
	if _Opt.batch_move:
		if _prof: _t0 = Time.get_ticks_usec()
		army.batch_move_queued(_stq_row, _stq_x, _stq_z, _stq_fl,
			map_lim_x, map_lim_z, world_bounds_enabled,
			water_active and world_bounds_enabled,
			Unit.BLOCK_RADIUS, Unit.TRUNK_CLEARANCE, _relief_amp_now(), self)
		_stq_row.resize(0)
		_stq_x.resize(0)
		_stq_z.resize(0)
		_stq_fl.resize(0)
		if _prof: _Opt.prof_add("batch_move", Time.get_ticks_usec() - _t0)
	# Пробуждения тылового напора: упор в чужое тело нашёл пакетный шаг, приход
	# к точке боя — сам проход. Забираем только при ненулевом счёте — обычным
	# приёмом дрёмы (ноль аллокаций в тихий кадр здесь не выйдет, счёт при
	# живом напоре почти всегда ненулевой, но событий единицы)
	if _Opt.rear_press or _Opt.approach_autopilot:
		var pwoken: Array = army.take_press_woken()
		for raw in pwoken:
			# Живость — на сырой ссылке, до приведения типа (правило 5)
			if raw != null and is_instance_valid(raw):
				var wu := raw as Unit
				if wu != null:
					wu._rear_wake()
	# ── РАЗБОР НАЛОЖЕНИЯ — ОДНИМ ПРОХОДОМ ПОСЛЕ ВСЕХ (см. ArmySoA) ──────────
	# ПОСЛЕ обхода: к этому моменту все, кто шёл, уже сдвинулись, и поправка
	# считается по итоговым точкам кадра, а не по смеси старых и новых.
	# Идёт КАЖДЫЙ кадр, а не через шард: разбор дешевле самого тика, а его
	# собственный такт задан таймером в столбце (SEP_INTERVAL)
	if _prof: _t0 = Time.get_ticks_usec()
	army.batch_separation(delta, Unit.SEP_MIN_DIST, Unit.SEP_MAX_STEP,
		Unit.SEP_INTERVAL, map_lim_x, map_lim_z,
		Unit.State.MOVING, Unit.State.ATTACKING, water_active and world_bounds_enabled, self,
		Unit.SEP_DEADZONE, _relief_amp_now(), Unit.SEP_CROSS_SQUAD,
		# Последним — зазор до ствола: этот проход единственный обходит ВСЕХ
		# живых, включая стоящих, и потому единственный, кто может вытолкнуть
		# застрявшего в дереве (см. ArmyCore.BatchSeparation)
		Unit.SEP_PASS_RELIEF, Unit.TRUNK_CLEARANCE)
	if _prof: _Opt.prof_add("sep_overlap", Time.get_ticks_usec() - _t0)
	if _meter: _Opt.tick_add(Time.get_ticks_usec() - _tm0)
	# Спящий (_proc_sleeping) дальний юнит не крутит свой _process и потому сам
	# не заметит, что камера подошла и он снова near_view — например, игрок
	# подводит камеру к стоящему на месте вражескому гарнизону. Реестр дальних
	# мал (только то, что сейчас в MultiMesh), обход раз в FAR_WAKE_CHECK_FRAMES
	# дешёвый и достаточно частый, чтобы не быть заметным
	if army_ticks % FAR_WAKE_CHECK_FRAMES == 0:
		_wake_returned_far_units()
	# Развалившийся строй смыкается сам (см. _sweep_reform). Свой редкий такт,
	# к шардам отношения не имеет: отрядов десятки, а не тысячи
	_sweep_reform(delta)
	# Фаланга в обороне подаётся к врагу ЦЕЛИКОМ (спринт 20, модуль 4.3)
	_sweep_phalanx_press(delta)
	# Мораль и паника — тоже вопрос ОТРЯДА (см. _sweep_morale), и такт у них
	# свой, редкий: отрядов десятки
	_sweep_morale(delta)
	_sweep_food(delta)
	# Давление овец: пень и тролли-воры (спринт 18, уточнение владельца)
	_sheep_pressure_t -= delta
	if _sheep_pressure_t <= 0.0:
		_sheep_pressure_t = _GobCfgGM.SHEEP_PRESSURE_CHECK_SEC
		_sheep_pressure_check()
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

# ── ПОЧЕМУ ЗДЕСЬ append, А НЕ ЗАПИСЬ ПО ИНДЕКСУ ────────────────────────────
# Пробовали держать ёмкость с курсором и передавать солверу число записей
# отдельным аргументом — это выглядит дешевле, потому что убирает проверку
# ёмкости с каждого элемента. ЗАМЕР ВЫИГРЫША НЕ ПОКАЗАЛ (qa_mass_battle 6000:
# ветка grid_update 1.03 против 1.05 мкс на вызов, то есть в пределах
# разброса): цена этой ветки — не append, а сам вызов метода автозагрузки и
# сравнения перед ним. Откачено, чтобы не держать усложнение без выгоды

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

## Во сколько раз растянуты отрядные сроки при нынешней численности армии.
## Снимается раз в кадр в _physics_process (см. perf_config.squad_ttl_scale)
var _ttl_scale: float = 1.0

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
	# масс, знамёна отрядов, пакетный бой Фазы 3) читает их дальше без единого
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
	# ── СРОК РАСТЯГИВАЕТСЯ НА БОЛЬШОЙ АРМИИ (см. perf_config.squad_ttl_scale) ─
	# Множитель снимается ОДИН РАЗ ЗА КАДР в _physics_process, а не здесь: это
	# вызов через границу скриптов, а сюда заходят десятки отрядов в кадр
	var ttl: int = int(CORRIDOR_TTL_MS * _ttl_scale)
	if not _corridors.has(sid):
		ttl = 1 + (sid * 37) % ttl
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
	# ── РЯД СЧИТАЕТСЯ ВСЕМУ ОТРЯДУ, А НЕ ТОЛЬКО ОБОРОНЕ ────────────────────
	# ЗДЕСЬ СТОЯЛ ФИЛЬТР `not u2._stance_holds_ground()`, и он был корнем
	# жалобы «копейщики идут в атаку с копьями строго вверх». Кого считать
	# передовым, знает `_live_rank`; вне стойки ЗАЩИТА его не считал НИКТО, и
	# он оставался нулевым у всех. Первая попытка опустить копья по признаку
	# «отряд в бою» на этом и провалилась: гистерезис по ряду пропустил
	# поголовно, и древко опустили 19 из 20 (замер qa_formation D1).
	#
	# СНЯТИЕ ФИЛЬТРА НИЧЕГО НЕ СТОИТ: это ПАКЕТНЫЙ путь — один вызов солвера
	# на отряд по уже собранному составу. Дорог был личный allies_ahead (8.3
	# мкс на бойца, и почти всё — дорога наружу), а он остаётся ровно там, где
	# и был: в фаланге, по таймеру. Здесь просто удлиняется массив строк.
	#
	# Условие «есть куда смотреть» выше не тронуто: отряд без курса и без
	# общего врага по-прежнему пропускается целиком — ряды у него не от чего
	# отсчитывать
	for m in live:
		var u2: Unit = m
		if u2.state == dead_st or u2._soa < 0:
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
## поодиночке в чистом поле и знамя отряда где-то между ними.
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
		# ── ПРИКАЗ ИГРОКА ПОДЗЫВОМ НЕ ПЕРЕБИВАЕТСЯ ─────────────────────────
		# Сплочённость шлёт `command_move` в точку В ДВУХ ШАГАХ от бойца — и
		# ровно этим перетирала только что отданный приказ на отход. Отряд,
		# которому велели уходить, ПО ОПРЕДЕЛЕНИЮ растягивается: передние
		# тронулись, задние ещё в телах, — то есть подзыв срабатывает именно
		# тогда, когда мешает больше всего. Замер qa_mega_battle B4-3: у 49 из
		# 50 оставшихся на месте точка приказа лежала рядом с ними
		if u.player_order_active():
			continue
		# ── ИДУЩЕГО ДАЛЁКИМ МАРШЕМ НЕ ЗОВЁМ (спринт 18) ─────────────────────
		# Отряд, огибающий обрыв плато (скользит вдоль стены к спуску),
		# растягивается по кольцу: передние уже за поворотом, задние ещё у
		# начала. Замок приказа держится три секунды, а обход — десятки, и
		# подзыв возвращал каждого «отставшего» к медиане — отряд бросал марш
		# и вставал у стены (зонд qa_cliff_probe/Probe3). Боец, у которого до
		# своей точки приказа дальше зоны отряда, — не отставший, а идущий
		if u.state == Unit.State.MOVING and not u.sprinting:
			var mdx: float = u.move_target.x - (u.position.x if u._local_xform else u.global_position.x)
			var mdz: float = u.move_target.z - (u.position.z if u._local_xform else u.global_position.z)
			if mdx * mdx + mdz * mdz > lim2:
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

## ── ВТОРАЯ ЛИНИЯ ЖДЁТ, А НЕ ЛЕЗЕТ В ЗАНЯТОЕ МЕСТО ──────────────────────────
## Отряд, которому места на рабочей дуге не хватило (см.
## SelectionManager._ring_squads_around), доходит до своей точки и ОСТАНАВЛИВАЕТСЯ
## там. Без этого сектор помогал только на подходе: дойдя до кольца, отряд всё
## равно шёл к стене, и десять отрядов снова оказывались в одной точке.
##
## ЖДЁТ ОН НЕ ВЕЧНО. Срок жёсткий: если передняя линия выбита или увязла, вторая
## обязана прийти на её место, а других способов узнать об этом у отряда нет —
## постройка о своих обидчиках ничего не сообщает. Срок отсчитывается от выдачи
## приказа и живёт в том же словаре, что и сама точка: одно событие — одна запись
const RING_HOLD_SEC := 25.0

func squad_set_attack_anchor(sid: int, at: Vector3, hold: bool = false) -> void:
	if sid > 0:
		_squad_atk_anchor[sid] = at
		if hold:
			_squad_atk_hold[sid] = Time.get_ticks_msec() + int(RING_HOLD_SEC * 1000.0)
		else:
			_squad_atk_hold.erase(sid)

## sid -> момент (ticks_msec), до которого отряд стоит на своём месте второй линии
var _squad_atk_hold: Dictionary = {}

func squad_attack_anchor(sid: int) -> Vector3:
	var a = _squad_atk_anchor.get(sid)
	return a if a != null else Vector3.INF

## Держит ли этот отряд позицию у своего сектора (вторая линия осады)
func squad_attack_hold(sid: int) -> bool:
	var t = _squad_atk_hold.get(sid)
	if t == null:
		return false
	if Time.get_ticks_msec() >= int(t):
		_squad_atk_hold.erase(sid)
		return false
	return true

func squad_clear_attack_anchor(sid: int) -> void:
	_squad_atk_anchor.erase(sid)
	_squad_atk_hold.erase(sid)

## ── ПРИКАЗ ИГРОКА НА ДВИЖЕНИЕ СНОСИТ ВСЮ ОТРЯДНУЮ ПАМЯТЬ О БОЕ ─────────────
## ЖАЛОБА ВЛАДЕЛЬЦА: «в долгом бою при клике ПКМ на отход войска игнорируют
## приказ и остаются на месте, срабатывает только с третьего клика».
##
## `Unit.command_move` честно чистит ЛИЧНУЮ память бойца — цель, замок, сцепку,
## сектор, погоню. Но у отряда есть и СВОЯ, общая на всех, и она переживала
## приказ:
##   • ТОЧКА У СТЕНЫ и признак «держать позицию» (осада). Приказ переводил
##     бойца в MOVING, но первое же авто-агро возвращало его в ATTACKING — и
##     подход читал СТАРЫЙ сектор, то есть тянул отряд обратно к зданию;
##   • ОБЩИЙ ОТВЕТ ОТРЯДА О БЛИЖАЙШЕМ ВРАГЕ. Он живёт свой срок (squad_target_ttl)
##     и раздаётся ВСЕМ спросившим: боец, только что получивший приказ уходить,
##     на первом же тике получал готовую цель и снова ввязывался.
## На экране обе беды выглядят одинаково — «приказ отдан, отряд остался».
##
## Чистится ОДНИМ вызовом и по СОБЫТИЮ приказа: покадрового пути здесь нет
func squad_forget_combat(sid: int) -> void:
	if sid <= 0:
		return
	squad_clear_attack_anchor(sid)
	_squad_target.erase(sid)
	squad_pursuit_release(sid)

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
	# Тот же множитель, что и у коридора (см. perf_config.squad_ttl_scale)
	var ttl: int = int(MELEE_TTL_MS * _ttl_scale)
	if not _melee.has(sid):
		ttl = 1 + (sid * 41) % ttl
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
		# ── ТЫЛОВОЙ НАПОР — ТОЖЕ АРЕНДА (этап D1) ───────────────────────────
		# Гасится у ВСЕХ здесь и выдаётся заново ниже, только годным: не
		# подтвердили — боец вернулся в полный автомат сам, залипнуть нечему
		# (тот же урок, что у _rear_line: условий снятия всегда больше, чем
		# перечислишь)
		if u._rear_press:
			u._rear_press = false
			if u._soa >= 0:
				army.rear_press_clear(u._soa)
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
				# ── АРЕНДА ТЫЛОВОГО НАПОРА (этап D1) ─────────────────────────
				# Пехотинец с рангом >= 2, чья цель дальше оружия: решать ему
				# нечего — он давит к своей свалке. Шаг считает ядро, тик
				# пропускается. Только рукопашная АТАКА (у стрелков тыл
				# СТРЕЛЯЕТ через головы, в обороне подтягивания нет вовсе),
				# только без замка (под приказом игрока подтягивания нет —
				# «баг ползающих лучников»), без разгона конницы и паники.
				# И НЕ НА КОННИЦУ: навал принимают стоя, а толпа, давящая
				# навстречу разгону, съедала кабанам пробег — qa_cavalry E2
				# терял вмятину от тарана (замер: без напора 1 из 3 стабильно)
				if _Opt.rear_press and i >= 0 and ti >= 0 \
						and u._live_rank >= 2 and u.attack_range <= 3.0 \
						and u.attack_damage > 0.0 \
						and u.charge_range <= 0.0 and not u.target_lock \
						and (tu == null or tu.charge_range <= 0.0) \
						and not u._stance_holds_ground() \
						and not u._panicked and not u._matrix_driven:
					u._rear_press = true
					army.rear_press_arm(i, apx[ti], apz[ti],
						u._effective_speed() * Unit.PULL_UP_SPEED,
						u.attack_range + u._target_pad)
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
const _GobCfgGM := preload("res://scripts/goblin/goblin_config.gd")   # обзор орды для смеха (спринт 18)
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
	_grant_row_bonuses(faction, upgrade_id)

## ── БОНУСНЫЙ СТОЛБЕЦ ВЫДАЁТСЯ САМ, ДАРОМ И МГНОВЕННО ──────────────────────
## Заказ 13.09.2026 (ветка монаха): изучены все три узла ряда — четвёртый
## открывается без цены и без времени. Проверка идёт ПО ФАКТУ (изучены ли все
## три ячейки ряда), а не по событию «закончился третий»: вторым способом
## бонус терялся бы у того, кто изучал ряд не по порядку или загрузил партию
## с двумя узлами из трёх.
##
## ПЛАТНЫЙ УЗЕЛ СЮДА НЕ ПОПАДАЕТ ВОВСЕ. Если владелец однажды впишет в
## бонусную ячейку цену, выдача даром стала бы подарком в обход склада —
## поэтому нулевая цена здесь не предположение, а условие
func _grant_row_bonuses(faction: int, just_done: String) -> void:
	var sep: int = just_done.rfind("_")
	if sep <= 0:
		return
	var tab: String = just_done.substr(0, sep)
	for cell in _Forge.cells():
		var c: String = String(cell)
		if not c.ends_with("d"):
			continue
		var bid: String = _Forge.node_id(tab, c)
		if is_researched(faction, bid):
			continue
		var slot: Dictionary = _UCfg.get_upgrade_slot(bid)
		if slot.is_empty():
			continue
		if float(slot.get("cost_gold", 0.0)) > 0.0 \
			or float(slot.get("cost_wood", 0.0)) > 0.0 \
			or float(slot.get("cost_stone", 0.0)) > 0.0:
			continue
		var ready := true
		for need in _Forge.ability_row_cells(c):
			if not is_researched(faction, _Forge.node_id(tab, String(need))):
				ready = false
				break
		if not ready:
			continue
		if researching.has(faction):
			(researching[faction] as Dictionary).erase(bid)
		_accumulate_upgrade(faction, slot, bid)

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
	_sel_building_id = ""
	for n in units:
		if not is_instance_valid(n):
			continue
		var nd := n as Node
		if int(nd.get("faction")) != Constants.FACTION_PLAYER:
			continue
		if nd is Building:
			has_building = true
			if _sel_building_id == "":
				_sel_building_id = String((nd as Building).building_id)
		elif nd is Unit:
			has_unit = true
		sig += str(nd.get_instance_id()) + ","
	var changed: bool = sig != _sel_sig
	_sel_sig = sig
	return [changed, has_building, has_unit]

## Первое здание последнего выделения — по нему выбирается щелчок
var _sel_building_id: String = ""
## Щелчок по типу здания (спринт 18): крепость — лук, бараки — рычаг, кузница —
## дверь, остальные — общий. Таблица — событие банка интерфейса
const PICK_BY_BUILDING := {
	"castle": "pick_castle", "barracks": "pick_barracks", "smithy": "pick_smithy",
}
static func pick_event_for(building_id: String) -> String:
	return String(PICK_BY_BUILDING.get(building_id, "pick_building"))

func _selection_click_sfx(units: Array) -> void:
	var r: Array = _selection_sig(units)
	if not bool(r[0]):
		return
	if bool(r[1]):
		AudioManager.play_ui(pick_event_for(_sel_building_id))
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
# ═════════════════════════════════════════════════════════════════════════════
# СЛЕПОК, ЖДУЩИЙ ЗАГРУЗКИ
# ═════════════════════════════════════════════════════════════════════════════
# ЛЕЖИТ В АВТОЗАГРУЗКЕ, ПОТОМУ ЧТО ПЕРЕЖИВАЕТ СМЕНУ СЦЕНЫ. Загрузка партии — это
# перезапуск Main.tscn с заранее известным зерном мира: положить слепок в саму
# сцену нельзя, её как раз и сносят. Пустой словарь означает «обычный старт».
# Читает и очищает его Main (см. Main._ready / start_game).
var pending_load: Dictionary = {}

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
		# Те же выборы СЛОВОМ БИТОВ — только легендарные перки, только для
		# быстрой проверки из горячего пути (см. squad_has_perk). Истина
		# по-прежнему в "chosen": сохранение пишет и читает именно его, а слово
		# ПЕРЕСОБИРАЕТСЯ САМО, когда список изменил длину. -1 означает «ещё ни
		# разу не считали»
		"perk_bits": 0,
		"perk_n": -1,
		"perk_src": null,
		# ДОКУПЛЕННЫЕ СПОСОБНОСТИ (колонка D древа кузницы): id узла -> true.
		# Исследование в кузнице открывает способность ФРАКЦИИ, но не выдаёт её
		# даром — каждый отряд платит за неё отдельно (см. squad_buy_ability)
		"abilities": {},
		# ── ЗНАМЯ ВЕТЕРАНСТВА ──
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
		# ── МОРАЛЬ И ПАНИКА (см. _sweep_morale) ──
		# −1 означает «ещё не заведена»: базовое значение берётся из состава,
		# а состав в момент создания отряда пуст (бойцов доставляют кадрами
		# позже, см. Building.queue_unit)
		"morale": -1.0,
		"full": 0,                # наибольший состав за жизнь (см. squad_full_size)
		"panic_until": 0,         # ticks_msec, 0 — паники нет
		# ЗДЕСЬ БЫЛ "panic_marker" — ВТОРОЙ узел флага, живший над центром
		# отряда. Он и давал «юнита с двумя флагами» и «флаг, застывший в
		# пустом поле»: разбор — в _show_panic_flag. Белое полотнище теперь
		# состояние ЕДИНСТВЕННОГО знамени отряда ("banner" выше)
	}
	return id

## Записать бойца в отряд. Прежняя приписка снимается — боец всегда ровно в одном
func add_to_squad(squad_id: int, unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if not squads.has(squad_id):
		return
	remove_from_squad(unit)
	var mem: Array = squads[squad_id]["members"]
	mem.append(unit)
	# ── ПОЛНЫЙ ШТАТ ЗАПОМИНАЕТСЯ ЗДЕСЬ ─────────────────────────────────────
	# По нему считается ДОЛЯ потерь, а по доле — падение морали (см.
	# credit_kill). Брать штат из конфига нельзя: отряд бывает неполным
	# (последние из барака, огрызок после боя, отряд стенда из двенадцати
	# человек), и тогда гибель ВСЕГО состава снимала бы пятую часть морали —
	# паника не наступала бы никогда. Это ровно тот случай, который поймал
	# qa_balance C1
	squads[squad_id]["full"] = maxi(int(squads[squad_id].get("full", 0)), mem.size())
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
		var wiped: bool = unit is Unit and (unit as Unit).is_dead()
		if wiped:
			_on_squad_wiped(sid, sq, unit as Unit, up)
		_disband_squad(sid, wiped)
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
## ── ЗНАМЕНОСЕЦ ЕСТЬ У КАЖДОГО ОТРЯДА, А НЕ ТОЛЬКО У ВЕТЕРАНОВ ──────────────
## ЭТО ВЫЯСНИЛОСЬ НА МЕГА-СТЕНДЕ И ОБЪЯСНЯЕТ, ПОЧЕМУ «АГРО ОТ ЗНАМЕНОСЦА»
## НИЧЕГО НЕ МЕНЯЛО. Знаменосец назначался ровно там, где заводится ЗНАМЯ
## (refresh_squad_banner), а знамя есть только у отряда со званием. У свежего
## отряда `bearer` был null всегда — то есть весь таргетинг «от знаменосца»
## молча уходил на запасной путь и работал по-старому. Замер qa_mega_battle
## B1-1: отрядов под замером НОЛЬ из трёх.
##
## Знаменосец — это ЛИДЕР ОТРЯДА (место [ряд 0, колонка 0]), а знамя — всего
## лишь предмет, который он МОЖЕТ нести. Поэтому назначаем ЛЕНИВО, по первому
## спросу: событий на это заводить не нужно, а спрашивают его редко —
## авто-агро раз в свой таймер и промах отрядного кэша цели.
##
## Назначение стоит один обход состава и случается заново только когда прежний
## лидер выбыл, то есть примерно раз на его смерть
func squad_bearer(sid: int) -> Node:
	if not squads.has(sid):
		return null
	var b = (squads[sid] as Dictionary).get("bearer")
	if b == null or not is_instance_valid(b) or (b as Unit).is_dead():
		return _assign_bearer(sid)
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
## ── И У ПАНИКУЮЩЕГО ТОЖЕ: СТРОЯ У НЕГО БОЛЬШЕ НЕТ ──────────────────────────
## Правило «первый ряд, крайний левый» писано под ШЕРЕНГУ. Паникующий отряд
## шеренгой не является: разметку у него снимает сам срыв (squad_clear_formation
## в _start_panic), и «крайний левый» вырождается в того, кого выбросило дальше
## всех — то есть флаг уезжает на обод рассыпавшейся кучи. Ровно та же беда и
## ровно то же лечение, что у толпы орды абзацем ниже
func _bearer_in_middle(sid: int) -> bool:
	if not squads.has(sid):
		return false
	if squad_panicked(sid):
		return true
	return int((squads[sid] as Dictionary).get("faction", -1)) == Constants.FACTION_GOBLIN

## ── ГДЕ У ОТРЯДА [РЯД 0, КОЛОНКА 0] ────────────────────────────────────────
## Первое место разметки. Порядок мест задан раскладкой строя раз и навсегда:
## сначала вся передняя шеренга от левого фланга к правому, потом вторая и так
## далее (SelectionManager._compute_line_slots, шапка SquadFormation). Поэтому
## «передний левый угол» — это буквально slots[0], и искать его геометрией не
## нужно вовсе.
##
## Vector3.INF — разметки нет: отряд ни разу не строился (пополнение из барака,
## одиночки, толпа орды со своими спиральными местами)
func _bearer_slot0(sid: int) -> Vector3:
	if not squads.has(sid):
		return Vector3.INF
	var slots: Array = (squads[sid] as Dictionary).get("slots", [])
	if slots.is_empty():
		return Vector3.INF
	return slots[0] as Vector3

## slot0_in — ЯВНОЕ место [ряд 0, колонка 0], если вызывающий знает его лучше
## реестра. Нужно ровно одному месту: смыкание рядов рассаживает бойцов по
## ПЕРЕНЕСЁННОЙ разметке (_slots_recentered / _slots_moved_to), а в записи
## отряда лежит исходная. Разница — сдвиг всей линии, и по исходной точке
## ближайшим оказывался сосед по колонке (замер qa_vet 4г: −301.62 вместо
## −302.42, то есть ровно один интервал строя)
func _assign_bearer(sid: int, near: Vector3 = Vector3.INF,
		slot0_in: Vector3 = Vector3.INF) -> Node:
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
	# ── ЗНАМЯ СТОИТ В [РЯД 0, КОЛОНКА 0], И ЭТО СИЛЬНЕЕ ВСЕХ ПРОЧИХ ПРАВИЛ ──
	# Заказ владельца (скриншот с флагами посреди отрядов): знаменосец ВСЕГДА
	# занимает передний левый угол строя относительно его фронта.
	#
	# ПОЧЕМУ ПО РАЗМЕТКЕ, А НЕ ПО ГЕОМЕТРИИ ЖИВЫХ. Прежнее правило («самый
	# выдвинутый вперёд, из них самый левый») считает угол по ФАКТИЧЕСКИМ
	# точкам, а они в бою и сразу после него не описывают строй вовсе: отряд
	# стоит пятном, «передний» — это тот, кого вынесло вперёд свалкой, и флаг
	# честно уезжал к нему в середину или за спину. Разметка отряда
	# (squads[sid]["slots"]) знает угол ТОЧНО: slots[0] по построению — крайнее
	# место ПЕРВОЙ шеренги со стороны левого фланга (см.
	# SelectionManager._compute_line_slots и шапку SquadFormation).
	#
	# ПЕРЕДАЧА ПАВШЕГО ЗНАМЕНИ ТЕПЕРЬ ИДЁТ ТУДА ЖЕ. Раньше знамя подхватывал
	# ближайший к убитому — на экране это читалось как «подхватил сосед», но
	# ровно из-за этого за бой флаг расползался по всему отряду и обратно уже
	# не возвращался (смыкание рядов зовётся не после каждой смерти). Правило
	# владельца одно и без исключений, поэтому исключения здесь нет.
	var slot0: Vector3 = slot0_in if slot0_in != Vector3.INF else _bearer_slot0(sid)
	if slot0 != Vector3.INF and not _bearer_in_middle(sid):
		var sd := INF
		for u in live:
			var us := u as Unit
			var ap0: Vector3 = _bearer_anchor(us)
			var sx: float = ap0.x - slot0.x
			var sz: float = ap0.z - slot0.z
			var s2: float = sx * sx + sz * sz
			if s2 < sd:
				sd = s2
				best = us
		sq["bearer"] = best
		return best
	if near != Vector3.INF:
		# ПЕРЕДАЧА БЕЗ РАЗМЕТКИ: ближайший к павшему. Остаётся только там, где
		# угла строя не существует — у толпы орды и у отряда, ни разу не
		# получавшего приказа на построение
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

## ── ГРУППОВОЕ ПРОДВИЖЕНИЕ ФАЛАНГИ (спринт 20, модуль 4.3) ──────────────────
## Раз в PHALANX_PRESS_SEC отряд копейщиков в стойке «Защита» смотрит на
## PHALANX_PRESS_RANGE вперёд от своего фронта: враг там есть, а дотянуться до
## него не может никто — ВСЯ фаланга делает шаг PHALANX_PRESS_STEP вперёд по
## курсу, сохраняя строй (каждый — на свою точку, сдвинутую на тот же вектор;
## разметка сдвигается вместе). Отдельный боец из шеренги не выбегает (см.
## Unit._check_auto_aggro, PHALANX_PULL_UP_SINGLE). Под приказом игрока
## (замок цели, марш) отряд не трогается — приказ важнее
const PHALANX_PRESS_SEC := 0.3
const PHALANX_PRESS_RANGE := 5.0
const PHALANX_PRESS_STEP := 1.0
var _phalanx_press_t: float = 0.0
var phalanx_presses: int = 0

func _sweep_phalanx_press(delta: float) -> void:
	_phalanx_press_t -= delta
	if _phalanx_press_t > 0.0:
		return
	_phalanx_press_t = PHALANX_PRESS_SEC
	for key in squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = squads[key]
		if String(sq.get("type", "")) != "spearman":
			continue
		var mem: Array = sq.get("members", [])
		if mem.is_empty():
			continue
		var course: Vector3 = squad_course(sid)
		if course.length_squared() < 1e-6:
			continue
		var live: Array = []
		var front_d: float = -INF
		var reach: float = 0.0
		var hold := false
		var busy := false
		for m in mem:
			if m == null or not is_instance_valid(m):
				continue
			var u := m as Unit
			if u == null or u.is_dead() or u.garrisoned:
				continue
			if u.target_lock or u.player_order_active() or u.state == Unit.State.MOVING:
				busy = true
				break
			if not u._stance_holds_ground():
				break
			hold = true
			live.append(u)
			reach = maxf(reach, u.attack_range)
			var pp: Vector3 = u.position if u._local_xform else u.global_position
			front_d = maxf(front_d, pp.x * course.x + pp.z * course.z)
		if busy or not hold or live.is_empty():
			continue
		var c: Vector3 = _centroid_of(live)
		var fc: Vector3 = c + course * (front_d - (c.x * course.x + c.z * course.z))
		var probe: Vector3 = fc + course * (PHALANX_PRESS_RANGE * 0.5)
		var f: int = int(sq.get("faction", -1))
		var best_d := INF
		for of in range(Constants.FACTION_COUNT):
			if of == f:
				continue
			var e = army.nearest_of_side(probe.x, probe.z, of, PHALANX_PRESS_RANGE * 0.5 + 1.0)
			if e == null or not is_instance_valid(e):
				continue
			var eu := e as Unit
			if eu == null or eu.is_dead():
				continue
			var ep: Vector3 = eu.global_position
			var ahead: float = (ep.x - fc.x) * course.x + (ep.z - fc.z) * course.z
			if ahead <= 0.0 or ahead > PHALANX_PRESS_RANGE:
				continue
			# НАВСТРЕЧУ НАБЕГАЮЩЕМУ НЕ ШАГАЕМ: конница с разгона и бегущая
			# пехота сами приходят на копья, а шаг навстречу разваливал бы
			# стенку ровно в миг удара (qa_sprint18b B6: «сдвинуто 12»)
			if eu.velocity.x * course.x + eu.velocity.z * course.z < -0.2 or eu.is_charging:
				continue
			best_d = minf(best_d, ahead)
		if best_d == INF or best_d <= reach:
			continue
		var step: float = minf(PHALANX_PRESS_STEP, best_d - reach * 0.8)
		if step <= 0.05:
			continue
		var shift: Vector3 = course * step
		var slots: Array = sq.get("slots", [])
		for i in range(slots.size()):
			slots[i] = (slots[i] as Vector3) + shift
		for u2 in live:
			var uu := u2 as Unit
			uu.command_move(land_target(uu.global_position + shift), false, course)
		phalanx_presses += 1

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
			# Точка бойца — ОДНИМ чтением и по дешёвому пути (правило 2).
			# Здесь стояли ДВА обращения к global_position подряд, а свойство
			# это, а не поле: каждое проверяет мировую матрицу. Обход идёт по
			# ВСЕМУ составу всех отрядов трижды в секунду
			var up: Vector3 = u.position if u._local_xform else u.global_position
			var dx: float = up.x - u.post_pos.x
			var dz: float = up.z - u.post_pos.z
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
		_ranged_engaged.erase(sid)

# ─────────────────────────────────────────────────────────────────────────────
# ОТРЯД СТРЕЛКОВ ВСТАЁТ ЦЕЛИКОМ, КАК ТОЛЬКО ДОСТРЕЛИЛ ПЕРВЫЙ
#
# ЗАКАЗ ДОСЛОВНО: «как только первая модель выходит на дистанцию атаки — весь
# отряд останавливается и начинает вести огонь».
#
# ПОЧЕМУ ЭТО ОТРЯДНАЯ ВЕЛИЧИНА, А НЕ ЛИЧНАЯ. Признак «я уже дострелил»
# (Unit._engaged_once) у каждого свой, и это верно для него самого: передний
# стрелок встаёт, задний в трёх метрах позади — ещё нет, и продолжает идти.
# На экране отряд втягивается в противника ниткой по одному, теряя залп и
# подставляя головных. Ответ на вопрос «дострелили ли МЫ» — один на отряд, и
# живёт он здесь, рядом с якорем погони: у них общий жизненный цикл (оба
# снимаются новым приказом и обоими правит первый дотянувшийся).
#
# ХРАНИТСЯ ОТДЕЛЬНО ОТ ЯКОРЯ, А НЕ ЕГО НАЛИЧИЕМ: якорь ставится и рукопашной
# пехоте, а «встать и стрелять» — правило ТОЛЬКО дальнобойных. Одно поле на
# два смысла разошлось бы на первой же правке
var _ranged_engaged: Dictionary = {}

## Первый стрелок отряда вышел на дистанцию. Идемпотентно
func squad_ranged_engaged_set(sid: int) -> void:
	if sid > 0:
		_ranged_engaged[sid] = true

## Дострелил ли отряд (для всех его бойцов)
func squad_ranged_engaged(sid: int) -> bool:
	return sid > 0 and bool(_ranged_engaged.get(sid, false))

## Новый приказ — отметка снимается: отряду снова можно подходить
func squad_ranged_release(sid: int) -> void:
	if sid > 0:
		_ranged_engaged.erase(sid)

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

## Порядковый номер бойца в составе отряда (−1 — не в отряде). Читается по
## событию (выстрел), не покадрово: линейный поиск по составу допустим
func squad_member_ordinal(sid: int, u: Node) -> int:
	var sq: Variant = squads.get(sid)
	if sq == null:
		return -1
	var members: Array = (sq as Dictionary)["members"]
	return members.find(u)

## Размер состава (с ещё не выбывшими мёртвыми — как и ordinal выше)
func squad_member_count(sid: int) -> int:
	var sq: Variant = squads.get(sid)
	if sq == null:
		return 0
	return ((sq as Dictionary)["members"] as Array).size()

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
	# `get("slots", [])` создавало НОВЫЙ пустой массив на каждый вызов —
	# умолчание вычисляется безусловно, до поиска ключа. А курс спрашивает
	# _phalanx_dir, то есть каждый копейщик обороны на каждом ходу строя
	var sl: Variant = sq.get("slots")
	if sl == null or (sl as Array).is_empty():
		return Vector3.ZERO
	return sq.get("course", Vector3.ZERO)

## Есть ли у отряда действующая разметка строя
func squad_has_formation(sid: int) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	var sl: Variant = (squads[sid] as Dictionary).get("slots")
	return sl != null and not (sl as Array).is_empty()

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

## ── ОТВЕТ ЗАПОМИНАЕТСЯ НА ФИЗИЧЕСКИЙ КАДР, И ЭТО НЕ УДОБСТВО, А НЕОБХОДИМОСТЬ ─
##
## ЧТО БЫЛО. Вопрос задаётся ИЗ ПОКАДРОВОГО ПУТИ КАЖДОГО БОЙЦА: `_phalanx_dir`
## зовёт его на каждом ходу фаланги (то есть каждый тик у всякого копейщика
## обороны, у которого рядом враг), `_check_auto_aggro` — на каждом такте агро,
## `_update_live_rank` — четырежды в секунду. А ответ считался ПОЛНЫМ ОБХОДОМ
## СОСТАВА, да ещё через squad_members(), который на каждый вызов СТРОИТ НОВЫЙ
## массив живых. Отряд из шестидесяти человек, спрашивающий сам себя шестьдесят
## раз в секунду, — это три тысячи шестьсот посещений и шестьдесят массивов В
## СЕКУНДУ НА ОДИН ОТРЯД, то есть честная квадратичность по размеру отряда.
## Дёшево это выглядело только потому, что окно «нас недавно задели» (3 с)
## закрывает разгар свалки ранним выходом — а вот на сближении и в перестрелке,
## когда враг рядом, но по нам ещё не попали, платился полный обход.
##
## ПОЧЕМУ КАДР — ПРАВИЛЬНЫЙ СРОК. Величина и так грубая: она построена на окне
## в ТРИ СЕКУНДЫ. Ответ, устаревший на один физический шаг (16 мс), не может
## изменить ни одного решения, которое на нём стоит. Тот же приём и тот же срок,
## что у кэша групп (nodes_in_group_cached) и снимка зданий.
##
## СОСТАВ ЧИТАЕТСЯ НАПРЯМУЮ, А НЕ ЧЕРЕЗ squad_members(): тот НЕ ЧИТАТЕЛЬ —
## он переписывает список членов и РАСПУСКАЕТ опустевший отряд прямо в геттере
## (см. его шапку и разбор марш-обхода в CLAUDE.md). Здесь нужен ответ, а не
## побочные действия.
func squad_in_combat(sid: int) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	var sq: Dictionary = squads[sid]
	# Номер кадра снят один раз за тик на всю армию (см. _physics_process).
	# Ноль означает «тика ещё не было» — стенд, поднявший отряды до первого
	# кадра, обязан получать честный ответ, а не общий кэш
	var f: int = Unit.phys_frame
	if not _Opt.squad_combat_cache:
		f = 0                        # ручка для A/B, см. perf_config, пункт 1б
	if f > 0 and int(sq.get("combat_f", -1)) == f:
		return bool(sq["combat_v"])
	var res: bool = false
	# ── ЧАСЫ БЕРУТСЯ У АРМИИ, А НЕ У ДВИЖКА ───────────────────────────────
	# Правило проекта: всё, что одинаково для всей армии, читается ОДИН РАЗ за
	# кадр (Unit.now_ms снимается в начале и физического, и отрисовочного тика).
	# На попадании в кэш эта строка и раньше не выполнялась — выход стоит выше,
	# — но на промахе она шла у КАЖДОГО отряда в кадре, а это вызов в движок
	# ради числа, которое уже снято.
	# Часы ТЕ ЖЕ САМЫЕ, что пишет squad_mark_hit (Time.get_ticks_msec), поэтому
	# сравнение остаётся честным: now_ms отстаёт от настоящего времени не
	# больше чем на кадр, а окно здесь — три секунды.
	# Ноль означает «тика ещё не было»: стенд, спрашивающий бой до первого
	# кадра, обязан получить настоящее время (та же оговорка, что и в
	# squad_enemy_point)
	var nms: int = Unit.now_ms
	if nms == 0:
		nms = Time.get_ticks_msec()
	var last_hit: int = int(sq.get("last_hit_ms", -RECENT_HIT_WINDOW_MS * 10))
	if nms - last_hit < RECENT_HIT_WINDOW_MS:
		res = true
	else:
		var roster: Array = sq["members"]
		var live := 0
		for m in roster:
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u == null or u.is_dead():
				continue
			live += 1
			if u.attack_target != null:
				res = true
				break
		# ── ЖИВЫХ НЕ ОСТАЛОСЬ: ЗОВЁМ squad_members() РАДИ ЕГО ПОБОЧНОГО
		# ДЕЙСТВИЯ, А НЕ РАДИ ОТВЕТА ───────────────────────────────────────
		# Здесь и была цена перехода на прямое чтение состава, и она НЕ
		# теоретическая: главный путь роспуска ВЫБИТОГО отряда — именно
		# squad_members(), который замечает «все мертвы» и распускает отряд с
		# признаком wiped, а тот роняет знамя на землю (см. CLAUDE.md, «Знамя
		# роняет только гибель»). Убрав отсюда его вызов, я убрал и этот
		# триггер: стенд qa_bugpass O3 поймал ровно это — тело на поле
		# появилось, а упавшего знамени рядом с ним не стало.
		# Путь ХОЛОДНЫЙ: он проходится один раз за всю жизнь отряда, в тот
		# кадр, когда в нём не осталось никого живого
		if live == 0 and not roster.is_empty():
			squad_members(sid)
			if not squads.has(sid):
				return false
	if f > 0 and squads.has(sid):
		sq["combat_f"] = f
		sq["combat_v"] = res
	return res

## ── СБРОСИТЬ ЗАПОМНЕННЫЙ ОТВЕТ «ОТРЯД В БОЮ» ───────────────────────────────
## Кэш держится один физический кадр (см. squad_in_combat), и этого достаточно
## для всего, что читает величину покадрово. Но есть два СОБЫТИЯ, которые
## переводят отряд в бой ВНУТРИ кадра, и после них ответ обязан стать честным
## немедленно: по отряду попали и боец взял цель. Иначе тот, кто спросит следом
## в том же кадре, получит «не в бою» — и это не теория: стенд qa_goblin E5
## («удар по спящей деревне будит орду досрочно») ловит ровно этот случай,
## потому что бьёт по орде и спрашивает вожака БЕЗ промежуточного кадра.
##
## Обратная сторона (кэш говорит «в бою», а бой уже кончился) безобидна:
## величина и так построена на окне в три секунды.
func squad_combat_invalidate(sid: int) -> void:
	if sid <= 0 or not squads.has(sid):
		return
	(squads[sid] as Dictionary)["combat_f"] = -1

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
	# ОТВЕТ «В БОЮ» СТАЛ ДРУГИМ ПРЯМО СЕЙЧАС — запомненный за этот кадр
	# больше не годится (см. squad_combat_invalidate)
	sq["combat_f"] = -1
	# Обстрел точит мораль по крохе. Отдельного вызова под это не заводим:
	# «по нам попали» уже отмечается здесь, и второе такое место разъехалось бы
	# с этим при первой же правке
	squad_add_morale(sid, -_UCfg.MORALE_LOSS_PER_HIT)
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
		# Место [ряд 0, колонка 0] берём из ТОЙ разметки, по которой только что
		# рассадили людей, а не из записи отряда: она могла быть перенесена
		_assign_bearer(sid, Vector3.INF,
			(use_slots[0] as Vector3) if not use_slots.is_empty() else Vector3.INF)
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
## ── БОЕВОЙ ЛИ ЭТО ОТРЯД ────────────────────────────────────────────────────
## ЖАЛОБА ВЛАДЕЛЬЦА: «выделяю рамкой пять крестьян — они издают громкий боевой
## клич, будто это фаланга копейщиков».
##
## Признак — ОРУЖИЕ (`attack_damage > 0`), а не род войск и не список типов.
## Рабочий обнуляет урон явно (Worker._ready), и то же правило само собой
## накроет любого будущего невооружённого — обозника, лекаря, поселенца, —
## не потребовав ни строчки. Список типов пришлось бы дополнять, и забытая
## строка означала бы вернувшийся клич.
## СПРИНТ 19: у рабочего появился топор (письмо 10), и урон перестал быть
## признаком солдата. Спрашивается Unit.is_combatant() — база отвечает по
## урону, рабочий переопределяет в false; правило по-прежнему одно на клич,
## реплики и голос
##
## ЖИВЫХ, А НЕ ВСЕХ: у выбитого отряда из одних трупов кличу взяться неоткуда,
## а `attack_damage` у павшего в поле остаётся прежним
func squad_is_combat(sid: int) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	for m in (squads[sid] as Dictionary)["members"]:
		var u := m as Unit
		if u != null and is_instance_valid(u) and not u.is_dead() \
				and u.is_combatant():
			return true
	return false

func squad_battle_cry(sid: int, chance: float = 1.0,
		cooldown_ms: int = CRY_COOLDOWN_MS) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	var men := squad_members(sid)
	if men.is_empty():
		return false
	# Отряд без оружия (рабочие) клич не подаёт
	if not squad_is_combat(sid):
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
## ── СТЕНА КОПИЙ (спринт 18) ─────────────────────────────────────────────────
## Отряд копейщиков с изученной и включённой «Стеной копий» по переходу в
## «Защиту» смыкается в SPEAR_WALL_ROWS шеренги (плотный интервал блока) лицом
## по курсу; копья опускает сама стойка. В бою не перестраивается — смыкание
## посреди свалки выдёргивало бы дерущихся (то же правило, что у close_ranks)
const SPEAR_WALL_ROWS := 3
var spear_wall_forms: int = 0        # стендам: сколько раз строились

func spear_wall_ready(sid: int) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	if String((squads[sid] as Dictionary).get("type", "")) != "spearman":
		return false
	return squad_has_ability(sid, "spearman_1d") and squad_ability_on(sid, "spearman_1d")

## Смена стойки отряда: точка подключения для всех, кто ставит стойку отрядом
## (кнопки панели, голос). Возвращает true, если стена построилась
func on_squad_stance(sid: int, stance_id: String) -> bool:
	if stance_id != "defense" or not spear_wall_ready(sid):
		return false
	return spear_wall_form(sid)

func spear_wall_form(sid: int) -> bool:
	if sid <= 0 or not squads.has(sid) or squad_in_combat(sid):
		return false
	var sq: Dictionary = squads[sid]
	var men: Array = []
	for m in sq["members"]:
		if is_instance_valid(m) and not (m as Unit).is_dead() and not (m as Unit).garrisoned:
			men.append(m)
	var n: int = men.size()
	if n == 0:
		return false
	var centre: Vector3 = _centroid_of(men)
	var course: Vector3 = squad_course(sid)
	if course.length_squared() < 1e-6:
		for m2 in men:
			course += (m2 as Unit)._facing
	course.y = 0.0
	if course.length_squared() < 1e-6:
		course = Vector3.FORWARD
	course = course.normalized()
	var across := Vector3(-course.z, 0.0, course.x)
	var cols: int = maxi(1, int(ceil(float(n) / float(SPEAR_WALL_ROWS))))
	var slots: Array = []
	for i in range(n):
		var col: int = i % cols
		var row: int = i / cols
		var off_x: float = (float(col) - float(cols - 1) * 0.5) * BLOCK_SPACING
		var off_z: float = float(row) * BLOCK_ROW_DEPTH
		slots.append(centre + across * off_x - course * off_z)
	squad_set_formation(sid, slots, course, false)
	for i2 in range(n):
		var u := men[i2] as Unit
		u.command_move(land_target(slots[i2]), false, course)
	spear_wall_forms += 1
	return true

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
		if u == null or u.is_dead() or not u.is_combatant():
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
## ── ИССЛЕДОВАНО В КУЗНИЦЕ = ЕСТЬ У ВСЕХ ОТРЯДОВ ЭТОГО РОДА ────────────────
## Заказ владельца (10.09.2026): «спец-бонус открывается сразу для всех юнитов
## соответствующего типа, повторную оплату убрать». Прежде способность
## считалась своей ТОЛЬКО после покупки её этим отрядом (словарь `abilities`),
## и панель показывала кнопку «купить» у каждого нового отряда. Теперь право
## даёт САМО ИССЛЕДОВАНИЕ, а словарь остался: по нему читаются старые
## сохранения и он же годится для будущих «личных» способностей
func squad_has_ability(sid: int, node_id: String) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	if bool((squads[sid].get("abilities", {}) as Dictionary).get(node_id, false)):
		return true
	var sq: Dictionary = squads[sid]
	var node: Dictionary = _Forge.get_node(node_id)
	if node.is_empty() or String(sq.get("type", "")) != String(node.get("unit", "")):
		return false
	return is_researched(int(sq.get("faction", Constants.FACTION_PLAYER)), node_id)

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
## ── ЗАЛП ОБЯЗАН СОСТОЯТЬСЯ, ДАЖЕ ЕСЛИ «ГОТОВЫХ» НЕ НАБРАЛОСЬ ─────────────
## ЖАЛОБА ВЛАДЕЛЬЦА (спринт 15): «улучшение залпа сейчас БЛОКИРУЕТ стрельбу —
## лучники должны регулярно выпускать тучу стрел». Так и было, и запирал отряд
## не сам залп, а порог готовности: пока окно закрыто, стрелок не бьёт вовсе
## (Archer._may_strike_now), а окно открывалось только при доле готовых от
## ЧИСЛА ЖИВЫХ. В бою половина отряда цели в дальности не имеет никогда —
## стоит во втором ряду, добивает разбежавшихся, только что потеряла цель, —
## и доля 0.7 от всего состава не набиралась ни разу. Отряд с купленной
## способностью молчал всю партию.
##
## Лечение из двух половин, и нужны обе:
##   • доля считается от тех, кому ЕСТЬ В КОГО стрелять, а не от всех живых;
##   • и есть потолок ожидания: отряд, у которого готовые есть, а доля всё не
##     набирается, стреляет по истечении VOLLEY_FORCE_MS в любом случае.
## Второе — гарантия «регулярно», а не подпорка: без неё достаточно одного
## вечно неготового стрелка, чтобы залп не случился никогда.
const VOLLEY_FORCE_MS := 2500

## Включён ли режим у отряда (куплен и не выключен игроком)
## ── РЕЖИМ ВКЛЮЧЁН ПО УМОЛЧАНИЮ (заказ владельца 10.09.2026) ──────────────
## «Бонус сразу активен, горит жёлтая рамка на иконке; можно выключить
## вручную». Раньше умолчанием было ВЫКЛЮЧЕНО, и залп лучников после
## исследования приходилось включать каждому отряду руками. Отсутствие ключа
## означает «игрок не трогал» — то есть включено; выключение пишет false
func squad_ability_on(sid: int, node_id: String) -> bool:
	if not squad_has_ability(sid, node_id):
		return false
	var d: Dictionary = squads[sid].get("ability_on", {})
	if not d.has(node_id):
		return true
	return bool(d[node_id])

## Включить/выключить купленный режим. Некупленный не включается
func squad_set_ability(sid: int, node_id: String, on: bool) -> bool:
	if sid <= 0 or not squads.has(sid) or not squad_has_ability(sid, node_id):
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

## Приказ игрока стрелкам (спринт 20): окно залпа открывается СРАЗУ — готовые
## стреляют на своём тике, а не ждут такта залпов и его порога
var volley_primes: int = 0

## ═══════════════════════════════════════════════════════════════════════════
## ЦЕНТРОВОЙ НОД ОТРЯДА (SQUAD RADAR) — ОДИН СКАН НА ОТРЯД, ДВЕ ФАЗЫ
## ═══════════════════════════════════════════════════════════════════════════
## Заказ владельца (13.09.2026): скан целей переносится с бойца на отряд,
## ровно 2 раза в секунду, радиус обнаружения 25 м при дальности лука 20 м;
## засёк на 21-25 м — отряд разворачивается и ЖДЁТ (`TARGET_LOCKED`), враг
## пересёк 20 м — залп всем отрядом в тот же кадр.
##
## ПОЧЕМУ ЭТО СВОД, А НЕ УЗЕЛ-НА-ОТРЯД. Сто отрядов узлами — это сто входов
## из движка в GDScript каждый кадр ради одного таймера; ровно от этого в
## проекте уже отказались у торчащих стрел (`_sweep_stuck_arrows`) и у тел
## павших. Состояние «нода» живёт в записи отряда, а обходит их один свод —
## снаружи это тот же центровой нод, только без платы за нотификацию.
##
## РАДИУС ОБНАРУЖЕНИЯ ВЫВОДИТСЯ, А НЕ СТОИТ ЧИСЛОМ: дальность лука растёт от
## кузницы (см. `STATS.archer.attack_range_cap`), и вписанные в код 25 м
## означали бы, что у прокачанного отряда упреждение исчезло, а у
## подрезанного — стало вдвое больше дальности. Упреждение — это НАДБАВКА.
const RADAR_INTERVAL_MS := 500          # ровно 2 Гц (прямой заказ)
const RADAR_MARGIN := 5.0               # 25 м при луке 20 м
const RADAR_IDLE := 0
const RADAR_LOCKED := 1
const RADAR_FIRE := 2
## Счётчики для бенчмарка: сколько сканов сделал свод и сколько залпов открыл
var radar_scans: int = 0
var radar_fires: int = 0

## ═══════════════════════════════════════════════════════════════════════════
## ЭЛИТА КРЕПОСТИ: ДО КАКОГО РАНГА ПРОКАЧАН НАЙМ МЕЧНИКОВ
## ═══════════════════════════════════════════════════════════════════════════
## Одно число на фракцию — «докуда открыто», а не список купленных узлов:
## ранги идут лестницей, и второй способ описать то же самое разошёлся бы с
## первым на первой же загрузке партии
signal keep_vet_changed(faction: int, level: int)

var keep_vet_level: Dictionary = {}

func keep_warrior_vet(faction: int) -> int:
	return int(keep_vet_level.get(faction, _UCfg.KEEP_WARRIOR_VET))

## Следующий доступный ранг (0 — потолок уже взят)
func keep_vet_next(faction: int) -> int:
	var nxt: int = keep_warrior_vet(faction) + 1
	if nxt > _UCfg.KEEP_WARRIOR_VET_MAX or not _UCfg.KEEP_VET_UPGRADES.has(nxt):
		return 0
	return nxt

## Цена следующего ранга в том же виде, в каком её принимает склад
func keep_vet_cost(faction: int) -> Dictionary:
	var nxt: int = keep_vet_next(faction)
	if nxt == 0:
		return {}
	var cfg: Dictionary = _UCfg.KEEP_VET_UPGRADES[nxt]
	return {
		Constants.RESOURCE_WOOD: float(cfg.get("cost_wood", 0.0)),
		Constants.RESOURCE_GOLD: float(cfg.get("cost_gold", 0.0)),
		Constants.RESOURCE_STONE: float(cfg.get("cost_stone", 0.0)),
	}

## Купить следующий ранг. true — списали и подняли
func keep_vet_buy(faction: int) -> bool:
	var nxt: int = keep_vet_next(faction)
	if nxt == 0:
		return false
	var costs: Dictionary = keep_vet_cost(faction)
	if not ResourceManager.can_afford(faction, costs):
		return false
	ResourceManager.spend(faction, costs)
	keep_vet_level[faction] = nxt
	emit_signal("keep_vet_changed", faction, nxt)
	return true

## ═══════════════════════════════════════════════════════════════════════════
## ТРЁХТОЧЕЧНЫЙ РЛС ОТРЯДА НА МАРШЕ (заказ владельца, 13.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Проверка заслона на марше (`Unit` — метка скана `blocker_reach`) идёт у
## КАЖДОГО идущего раз в AGGRO_INTERVAL_HOT. Заказ: заменить её двухфазной
## схемой — отряд щупает фронт раз в 2-3 с из трёх точек, и пока там пусто,
## личный скан не зовёт никто.
##
## ТРИ ТОЧКИ, А НЕ ДВЕ (уточнение заказа): растянутый отряд широк, и помеха
## ровно по центру строя между двумя угловыми лучами пролезает. Точки —
## левый фланг, центр, правый фланг; берутся ПРОЕКЦИЕЙ мест бойцов на ось,
## поперечную курсу, то есть работают при любой ширине и любом повороте.
##
## ЩУП — ДИСК, А НЕ ЛУЧ. Луч в проекте пускать нечем: физтел у бойцов нет
## (`collision_mask` = 0), и «трассировка» обернулась бы своим перебором
## сетки, то есть тем же сканом. Диск радиусом MARCH_RADAR_RANGE вокруг точки
## ещё и надёжнее: он не может пропустить помеху, стоящую чуть в стороне.
## ПЕРИОД УДВОЕН ПОСЛЕ ПРИЁМКИ (заказ 13.09.2026: «снизь частоту с 2.5 до
## 4-5 с»). Ценой этому — запаздывание касательного перехвата на один щуп:
## замер qa_infantry_radar блок E меряет его прямо (первый контакт на ходу)
const MARCH_RADAR_SEC := 5.0            # было 2.5; заказ: 4.0-5.0 с
const MARCH_RADAR_RANGE := 10.0         # заказ: дальний РЛС 10 м
const MARCH_RADAR_CONTACT := 4.0        # заказ: ближний контакт 3-5 м
const MARCH_RADAR_CLEAR := 0
const MARCH_RADAR_OBSTACLE := 1
## Счётчики для бенчмарка
var march_radar_scans: int = 0

func _sweep_march_radar() -> void:
	if not _Opt.march_radar:
		return
	var now: int = Time.get_ticks_msec()
	var step: int = int(MARCH_RADAR_SEC * 1000.0)
	for key in squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = squads[key]
		var due: Variant = sq.get("mradar_next")
		if due == null:
			# Фазы отрядов разведены по номеру — иначе сто отрядов щупают
			# фронт в один и тот же кадр и горб съезжает, а не исчезает
			sq["mradar_next"] = now + (sid * 53) % step
			continue
		if now < int(due):
			continue
		sq["mradar_next"] = now + step
		_march_radar_scan(sid, sq)

## Три точки фронта: левый фланг, центр, правый фланг
func _march_radar_points(sq: Dictionary, course: Vector3) -> Array:
	var side := Vector3(-course.z, 0.0, course.x)
	var lo: float = INF
	var hi: float = -INF
	var lo_p := Vector3.ZERO
	var hi_p := Vector3.ZERO
	var acc := Vector3.ZERO
	var n := 0
	for m in sq.get("members", []):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		var p: Vector3 = u.position if u._local_xform else u.global_position
		var t: float = p.x * side.x + p.z * side.z
		if t < lo:
			lo = t
			lo_p = p
		if t > hi:
			hi = t
			hi_p = p
		acc += p
		n += 1
	if n == 0:
		return []
	# Центр — СРЕДНЕЕ мест, а не медиана: здесь это щуп, а не точка приказа,
	# и расколотому отряду среднее между кучами тоже полезно прощупать
	return [lo_p, acc / float(n), hi_p]

func _march_radar_scan(sid: int, sq: Dictionary) -> void:
	# Щупаем только ИДУЩИЙ отряд: стоящему заслон на марше не грозит, а его
	# округу и так стережёт коридорный ответ `_clear_enemy`
	var course: Vector3 = squad_course(sid)
	var moving := false
	for m in sq.get("members", []):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u != null and not u.is_dead() and u.state == Unit.State.MOVING:
			moving = true
			break
	if not moving:
		sq["mradar_phase"] = MARCH_RADAR_OBSTACLE   # не наше дело — старый путь
		return
	if course.length_squared() < 1e-4:
		course = Vector3(0.0, 0.0, -1.0)
	course = course.normalized()
	var pts: Array = _march_radar_points(sq, course)
	if pts.is_empty():
		sq["mradar_phase"] = MARCH_RADAR_OBSTACLE
		return
	var fac: int = int(sq.get("faction", 0))
	var best: float = INF
	for p in pts:
		var pp: Vector3 = p
		march_radar_scans += 1
		for f in Constants.other_factions(fac):
			var cand = army.nearest_of_side(pp.x, pp.z, int(f), MARCH_RADAR_RANGE)
			if cand == null or not is_instance_valid(cand):
				continue
			var cu := cand as Unit
			if cu == null or cu.is_dead():
				continue
			var q: Vector3 = cu.position if cu._local_xform else cu.global_position
			var d: float = Vector2(q.x - pp.x, q.z - pp.z).length()
			if d < best:
				best = d
	sq["mradar_dist"] = best
	# ── ФАЗА 2 ВЗВОДИТСЯ ЗАРАНЕЕ, А НЕ ПО ФАКТУ КОНТАКТА ──────────────────
	# Между щупами проходит MARCH_RADAR_SEC, и за это время отряд успевает
	# пройти несколько метров. Поэтому в фазу 2 переходим, когда помеха
	# ближе «контакта плюс путь до следующего щупа»: иначе помеха, замеченная
	# на 6 м, была бы пропущена до самого упора телом
	var lead: float = MARCH_RADAR_CONTACT + MARCH_RADAR_SEC * 3.0
	sq["mradar_phase"] = MARCH_RADAR_OBSTACLE if best <= lead else MARCH_RADAR_CLEAR

## Пусто ли впереди у отряда по данным РЛС. false — старый путь (в том числе
## у бойца без отряда и пока РЛС ни разу не щупал)
func squad_march_clear(sid: int) -> bool:
	if not _Opt.march_radar or sid <= 0:
		return false
	var raw: Variant = squads.get(sid)
	if raw == null:
		return false
	return int((raw as Dictionary).get("mradar_phase", MARCH_RADAR_OBSTACLE)) \
		== MARCH_RADAR_CLEAR

## Свод центровых нодов. Зовётся из _physics_process рядом с тактом залпов
func _sweep_squad_radar() -> void:
	if not _Opt.squad_radar:
		return
	var now: int = Time.get_ticks_msec()
	for key in squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = squads[key]
		# Дешёвый отсев ПО ТИПУ до всего прочего — тот же приём, что у такта
		# залпов: у пехоты и рабочих упреждающего радиуса нет
		if String(sq.get("type", "")) != "archer":
			continue
		var due: Variant = sq.get("radar_next")
		if due == null:
			# ФАЗЫ ОТРЯДОВ РАЗВЕДЕНЫ ПО НОМЕРУ: сто отрядов, заведённых одним
			# кадром, иначе сканируют в один и тот же кадр — горб просто
			# съезжает, а не исчезает (та же грабля, что у фаз анимации)
			sq["radar_next"] = now + (sid * 37) % RADAR_INTERVAL_MS
			continue
		if now < int(due):
			continue
		sq["radar_next"] = now + RADAR_INTERVAL_MS
		_radar_scan(sid, sq)

func _radar_scan(sid: int, sq: Dictionary) -> void:
	# ── СКАНИРУЕТ ЗНАМЕНОСЕЦ ───────────────────────────────────────────────
	# Та же точка отсчёта, что у прежнего отрядного кэша и у поводка агро:
	# медиана у расколотого отряда садится в пустое поле между кучами, а
	# знаменосец — живое тело в середине строя (см. _squad_cached_enemy)
	var scout: Unit = _radar_scout(sid)
	if scout == null:
		sq["radar_foe"] = null
		sq["radar_phase"] = RADAR_IDLE
		return
	var detect: float = scout.attack_range + RADAR_MARGIN
	radar_scans += 1
	var foe: Node3D = scout.radar_scan(detect)
	var was: int = int(sq.get("radar_phase", RADAR_IDLE))
	if foe == null:
		sq["radar_foe"] = null
		sq["radar_phase"] = RADAR_IDLE
		return
	sq["radar_foe"] = foe
	var sp: Vector3 = scout.position if scout._local_xform else scout.global_position
	var fu := foe as Unit
	var fp: Vector3 = fu.position if (fu != null and fu._local_xform) \
		else foe.global_position
	var d: float = Vector2(fp.x - sp.x, fp.z - sp.z).length()
	if d <= scout.fire_range_to(foe):
		sq["radar_phase"] = RADAR_FIRE
		# ЗАЛП ОТДАЁТСЯ НА ПЕРЕСЕЧЕНИИ ГРАНИЦЫ, А НЕ КАЖДЫЙ ТАКТ: повторная
		# раздача command_attack всем тридцати каждые полсекунды перетирала бы
		# личные цели, набранные боем, и стоила бы ровно того, что экономит.
		# НО ТЕХ, КТО ЦЕЛЬ ПОТЕРЯЛ, ДОБИРАТЬ ОБЯЗАТЕЛЬНО: жертва гибнет или
		# выходит из дальности, боец остаётся ни с чем, а сам он больше не
		# сканирует — это же и есть смысл центрового нода. Без добора отряд
		# после первого залпа замолкал: точка залпа считается по центру масс
		# ЦЕЛЕЙ, и без целей она вырождается в ноль (qa_volley D1)
		_radar_open_fire(sid, foe, was == RADAR_FIRE)
	else:
		sq["radar_phase"] = RADAR_LOCKED
		if was != RADAR_LOCKED:
			_radar_face(sid, foe)

## Кто ведёт скан за отряд: знаменосец, а если его нет — первый живой
func _radar_scout(sid: int) -> Unit:
	var b = squad_bearer(sid)
	if b != null and is_instance_valid(b):
		var bu := b as Unit
		if bu != null and not bu.is_dead():
			return bu
	var raw: Variant = squads.get(sid)
	if raw == null:
		return null
	var sq: Dictionary = raw
	# Состав читается НАПРЯМУЮ: squad_members() не читатель — он распускает
	# опустевший отряд прямо в геттере (см. разбор такта марша)
	for m in sq.get("members", []):
		if m != null and is_instance_valid(m):
			var u := m as Unit
			if u != null and not u.is_dead():
				return u
	return null

## Фаза 1: отряд развернулся на цель, но не стреляет
func _radar_face(sid: int, foe: Node3D) -> void:
	var raw: Variant = squads.get(sid)
	if raw == null:
		return
	var sq: Dictionary = raw
	var fp: Vector3 = foe.global_position
	for m in sq.get("members", []):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead() or u.target_lock:
			continue
		u.face_towards(fp)

## Фаза 2: враг пересёк дистанцию огня — залп всем отрядом В ЭТОТ ЖЕ КАДР
func _radar_open_fire(sid: int, foe: Node3D, only_idle: bool = false) -> void:
	var raw: Variant = squads.get(sid)
	if raw == null:
		return
	var sq: Dictionary = raw
	radar_fires += 1
	# ── ЦЕЛЬ ОДНА НА ОТРЯД, НО ЖЕРТВА У КАЖДОГО СВОЯ ──────────────────────
	# ПЕРВАЯ ВЕРСИЯ ДАВАЛА ВСЕМ ТРИДЦАТИ ОДНУ И ТУ ЖЕ МОДЕЛЬ, И ЭТО ЛОМАЛО
	# ЗАЛП: точка залпа считается по центру масс ЦЕЛЕЙ (squad_volley_point), а
	# когда цель у всех одна, туча схлопывается в неё — замер qa_volley D1/D5:
	# «залп (0,0), ранено 2 из 16» вместо накрытия чужого строя.
	# Жертву внутри вражеского отряда разбирает тот же squad_pick_member
	# («наименее обстрелянный»), которым её разбирает приказ игрока: один
	# способ выбирать жертву на все источники приказа, а не второй свой
	var foe_sq: int = 0
	var fu := foe as Unit
	if fu != null:
		foe_sq = fu.squad_id
	for m in sq.get("members", []):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		# Приказ игрока центровой нод не перебивает: замок цели — приоритет №1
		if u.target_lock:
			continue
		# Добор: трогаем только тех, у кого цели нет вовсе или она мертва
		if only_idle:
			var cur: Node3D = u.attack_target
			if cur != null and is_instance_valid(cur):
				var cu := cur as Unit
				if cu == null or not cu.is_dead():
					continue
		var victim: Node3D = foe
		if foe_sq != 0:
			victim = squad_pick_member(foe_sq, u.global_position, foe)
		u.command_attack(victim, false)
	# ── ОКНО ЗАЛПА ОТКРЫВАЕТСЯ ТОЛЬКО НА ПЕРЕХОДЕ ─────────────────────────
	# Праймить его на КАЖДОМ такте радара нельзя: пока окно открыто, такт
	# залпов пропускает отряд целиком (`now < volley_until` → continue) и не
	# успевает посчитать ТОЧКУ ЗАЛПА — она считается по центру масс целей
	# именно там. Отряд стрелял, но туча вырождалась в ноль (qa_volley D1).
	# На переходе окно нужно: готовые отстреляются на своём же тике, не
	# дожидаясь такта залпов (раз в VOLLEY_SWEEP_EVERY кадров)
	# ОКНО ЗАЛПА РАДАР НЕ ОТКРЫВАЕТ ВОВСЕ — ЭТО ДЕЛО ТАКТА ЗАЛПОВ.
	# Прайм отсюда пробовали и сняли: окно, открытое мимо `_sweep_volleys`,
	# уносит с собой и расчёт ТОЧКИ залпа (он живёт там же), а после такого
	# залпа отряд больше не набирал «готовых» и замолкал навсегда — замер
	# qa_volley: able=12, ready=0 на каждом такте. Такт залпов идёт раз в
	# VOLLEY_SWEEP_EVERY кадров, то есть открывает окно в пределах 50 мс
	# после того, как радар раздал цели: «мгновенно» от этого не страдает

## Есть ли у отряда живой центровой нод (иначе боец опрашивает по-старому)
func squad_radar_active(sid: int) -> bool:
	if not _Opt.squad_radar:
		return false
	var raw: Variant = squads.get(sid)
	if raw == null:
		return false
	return String((raw as Dictionary).get("type", "")) == "archer"

## Цель, по которой отряду РАЗРЕШЕНО стрелять. В фазе прицеливания ответ
## пустой намеренно: отряд смотрит на врага и ждёт, пока тот войдёт в дальность
func squad_radar_foe(sid: int) -> Node3D:
	var raw: Variant = squads.get(sid)
	if raw == null:
		return null
	var sq: Dictionary = raw
	if int(sq.get("radar_phase", RADAR_IDLE)) != RADAR_FIRE:
		return null
	var n: Variant = sq.get("radar_foe")
	if n == null or not is_instance_valid(n):
		return null
	var u := n as Unit
	if u != null and u.is_dead():
		return null
	return n

func squad_radar_phase(sid: int) -> int:
	var raw: Variant = squads.get(sid)
	if raw == null:
		return RADAR_IDLE
	return int((raw as Dictionary).get("radar_phase", RADAR_IDLE))

## СБРОС ПО КЛИКУ ИГРОКА: такт обнуляется, цель приказа становится целью
## отряда немедленно — ждать своего такта после явного приказа нельзя
func squad_radar_kick(sid: int, target: Node3D = null) -> void:
	if not _Opt.squad_radar:
		return
	var raw: Variant = squads.get(sid)
	if raw == null:
		return
	var sq: Dictionary = raw
	sq["radar_next"] = 0
	if target != null and is_instance_valid(target):
		sq["radar_foe"] = target
		sq["radar_phase"] = RADAR_FIRE

func squad_volley_prime(sid: int) -> void:
	if sid <= 0 or not squads.has(sid):
		return
	if not squad_volley_mode(sid):
		return
	var sq: Dictionary = squads[sid]
	var now: int = Time.get_ticks_msec()
	if now < int(sq.get("volley_until", 0)):
		return
	sq["volley_until"] = now + VOLLEY_WINDOW_MS
	sq["volley_next"] = 0
	sq["volley_wait"] = 0
	volley_primes += 1

## ТАКТ ЗАЛПОВ. Обходит только те отряды, у которых режим включён: у остальных
## это одна проверка словаря
const VOLLEY_SWEEP_EVERY := 3

func _sweep_volleys() -> void:
	var now: int = Time.get_ticks_msec()
	for key in squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = squads[key]
		# Дешёвый отсев ПО ТИПУ до разбора способности: у копейщиков, рабочих
		# и орды залпа нет, а toggle_ability_of + squad_ability_on на каждый
		# отряд в каждом кадре — это и была цена такта
		if String(sq.get("type", "")) != "archer":
			continue
		# ── ОТСЕВА ПО ПУСТОМУ СЛОВАРЮ БОЛЬШЕ НЕТ, И ЭТО БЫЛО «ЛУЧНИКИ СТОЯТ
		# И НЕ СТРЕЛЯЮТ» (спринт 16) ──────────────────────────────────────
		# Здесь стояло «ability_on пуст — отряду тут делать нечего». Но со
		# спринта 13 способность ВКЛЮЧЕНА ПО УМОЛЧАНИЮ: при отсутствии ключа
		# squad_ability_on отвечает «да», а ключ появляется только когда игрок
		# щёлкнул переключатель. Отряд с изученным залпом, которого никто не
		# трогал, жил в режиме залпа (стрелок ждёт окна — Archer._may_strike_now)
		# при том, что окно ему не открывал никто. Выключить залп руками —
		# «по готовности» — и стрельба возвращалась: ровно то, что видел
		# владелец. Решает один вопрос — squad_volley_mode: у отряда без
		# изученного узла он и так отвечает «нет» (см. squad_has_ability)
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
		# СКОЛЬКО ИХ ВООБЩЕ МОЖЕТ СТРЕЛЯТЬ СЕЙЧАС (живая цель в дальности,
		# независимо от перезарядки) — знаменатель доли готовности
		var able := 0
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
			able += 1
			if u._attack_timer > 0.0:
				continue
			ready += 1
			acc += t.global_position
			n_aim += 1
			if foe_sid == 0 and t.squad_id > 0:
				foe_sid = t.squad_id
		if alive == 0 or n_aim == 0 or able == 0:
			continue
		# ── ПОРОГ СЧИТАЕТСЯ ОТ ТЕХ, КОМУ ЕСТЬ В КОГО СТРЕЛЯТЬ ────────────────
		# Разбор — у VOLLEY_FORCE_MS. Отдельно отмечаем МОМЕНТ, с которого отряд
		# ждёт залпа: по нему и работает потолок ожидания
		if int(sq.get("volley_wait", 0)) == 0:
			sq["volley_wait"] = now
		var overdue: bool = now - int(sq.get("volley_wait", now)) >= VOLLEY_FORCE_MS
		# ── СИНХРОННОСТЬ — ОТ ВСЕГО ОТРЯДА, ГАРАНТИЯ — ОТ ТЕХ, КОМУ ЕСТЬ В КОГО ──
		# Спринт 15 считал долю от `able` — и залп открывался, едва трое из
		# десяти нашли цель: пачка из трёх, остальные семь ждали следующего
		# окна (qa_volley C1: «пик 3 при 10 стрелках»). Кучность залпа — это
		# как раз ожидание ВСЕГО отряда, поэтому штатный порог снова от живых.
		# А чтобы залп не молчал, когда часть отряда без цели, — потолок
		# ожидания: просрочено и готовы почти все, кому есть в кого стрелять
		var whole: bool = float(ready) >= float(alive) * VOLLEY_READY_FRACTION
		var forced: bool = overdue and float(ready) >= float(able) * VOLLEY_READY_FRACTION
		if not whole and not forced:
			continue
		# Ждать больше нечего: отсчёт ожидания начнётся заново со следующего раза
		sq["volley_wait"] = 0
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
# Дошли до порога → отряд получает следующее звание (знамя знаменосца меняет
# грейд) и «долг» pending: столько улучшений игрок должен выбрать на панели.
# Выбранный бонус раздаётся КАЖДОЙ модели (плоские поля Unit.vet_*) и
# запоминается в отряде, чтобы пополнение из замка получало его автоматически.
# ─────────────────────────────────────────────────────────────────────────────
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
	# ── МОРАЛЬ ХОДИТ ЗА УБИЙСТВАМИ ─────────────────────────────────────────
	# Здесь единственное место, которое знает ОБЕ стороны размена: чей отряд
	# потерял человека и чей его убил. Считать потери отдельным обходом
	# состава значило бы завести второй источник правды о том же событии.
	# Потеря считается ДОЛЕЙ ПОЛНОГО ШТАТА: смерть одного из шестидесяти
	# заметна слабее, чем одного из десяти, и это верно по существу
	squad_add_morale(sid, _UCfg.MORALE_GAIN_PER_KILL)
	# ── «КРОВЬ ЗА КРОВЬ»: ЛЕГЕНДА ЛЕЧИТСЯ УБИЙСТВОМ ────────────────────────
	# Лечится ТОТ, КТО УБИЛ, а не весь отряд: иначе перк вытягивал бы из ямы
	# шестьдесят человек за одну смерть противника
	if squad_has_perk(sid, "legend_bloodthirst"):
		var ku := killer as Unit
		if ku != null and not ku.is_dead():
			ku.current_health = minf(ku.max_health,
				ku.current_health + ku.max_health * _UCfg.LEGEND_HEAL_FRAC)
			ku._soa_push_stats()
	if victim != null and is_instance_valid(victim) and victim is Unit:
		var vsid: int = (victim as Unit).squad_id
		if vsid > 0 and squads.has(vsid):
			squad_add_morale(vsid,
				-_UCfg.MORALE_LOSS_PER_DEATH / float(squad_full_size(vsid)))
	var lvl: int = _UCfg.veteran_level_for_kills(String(sq["type"]), int(sq["kills"]))
	if lvl <= int(sq["level"]):
		return
	# Через несколько порогов разом (добивание большого отряда) — начисляем все
	sq["pending"] = int(sq["pending"]) + (lvl - int(sq["level"]))
	sq["level"]   = lvl
	refresh_squad_banner(sid)

## ЗАСЧИТАТЬ ОТРЯДУ СРАЗУ n УБИЙСТВ — цена смерти босса (Troll._award_kills).
## Тот же учёт, что у credit_kill: счёт, мораль и пороги ветеранства, только
## одним вызовом, а не n обходами. Лечение «кровь за кровь» не идёт: некому —
## убийца здесь не боец, а отряд целиком
func credit_kills(sid: int, n: int, victim: Node = null) -> void:
	if n <= 0 or sid <= 0 or not squads.has(sid):
		return
	var sq: Dictionary = squads[sid]
	if victim != null and is_instance_valid(victim) and victim.get("faction") != null:
		if int(victim.faction) == int(sq["faction"]):
			return
	sq["kills"] = int(sq["kills"]) + n
	squad_add_morale(sid, _UCfg.MORALE_GAIN_PER_KILL * float(n))
	var lvl: int = _UCfg.veteran_level_for_kills(String(sq["type"]), int(sq["kills"]))
	if lvl <= int(sq["level"]):
		return
	sq["pending"] = int(sq["pending"]) + (lvl - int(sq["level"]))
	sq["level"]   = lvl
	refresh_squad_banner(sid)

## Логово тролля (TrollLair) текущей партии; null — не заведено.
## СПРИНТ 18: логов ДВА (у игрока и у красного ИИ) — troll_lair остаётся
## ПЕРВЫМ зарегистрированным (у базы игрока: месть орды, стенды), полный
## список — troll_lairs; ближайшее — nearest_lair
var troll_lair: Node = null
var troll_lairs: Array = []

func register_lair(l: Node) -> void:
	if l == null or troll_lairs.has(l):
		return
	troll_lairs.append(l)
	if troll_lair == null or not is_instance_valid(troll_lair):
		troll_lair = l

func nearest_lair(from: Vector3) -> Node:
	var best: Node = null
	var bd := INF
	for l in troll_lairs:
		if l == null or not is_instance_valid(l):
			continue
		var d: float = from.distance_squared_to((l as Node3D).global_position)
		if d < bd:
			bd = d
			best = l
	return best

## ── ДАВЛЕНИЕ ОВЕЦ: САМОВОЗОБНОВЛЯЕМЫЙ РЕСУРС (уточнение владельца) ────────
## Раз в SHEEP_PRESSURE_CHECK_SEC: у стороны больше TROLL_RAID_SHEEP овец —
## её пень (lair_spots, ставит Main) восстанавливается, если снесён, а если
## живых троллей в нём нет — выходит TROLL_RAID_SPAWN троллей-воров; дальше
## рейд ведёт сам тролль (Troll._tick_raid), успех — ещё трое (TrollLair)
var lair_spots: Dictionary = {}       # сторона → точка пня
var lair_restores: int = 0
var raid_trolls_spawned: int = 0
var _sheep_pressure_t: float = 0.0

## Когда пень стороны был снесён (часы партии) — восстановление не раньше
## LAIR_REGEN_SEC после (спринт 20)
var lair_fell_at: Dictionary = {}
var lair_regen_refusals: int = 0

func note_lair_fell(f: int) -> void:
	var t: float = float(main.call("game_clock")) if (main != null and is_instance_valid(main)
		and main.has_method("game_clock")) else 0.0
	lair_fell_at[f] = t

func lair_regen_ready(f: int) -> bool:
	if not lair_fell_at.has(f):
		return true
	var t: float = float(main.call("game_clock")) if (main != null and is_instance_valid(main)
		and main.has_method("game_clock")) else 0.0
	return t - float(lair_fell_at[f]) >= _GobCfgGM.LAIR_REGEN_SEC

func lair_for(f: int) -> Node:
	for l in troll_lairs:
		if l != null and is_instance_valid(l) and int(l.get("side_faction")) == f \
				and not (l as Building).is_dead():
			return l
	return null

func _sheep_pressure_check() -> void:
	if main == null or not is_instance_valid(main):
		return
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		if not lair_spots.has(f):
			continue
		if faction_sheep_count(f) <= _GobCfgGM.TROLL_RAID_SHEEP:
			continue
		var l: Node = lair_for(f)
		if l == null:
			# ТАЙМАУТ ВОССТАНОВЛЕНИЯ (спринт 20): снесённый пень ждёт
			# LAIR_REGEN_SEC, сколько бы овец ни было у стороны
			if not lair_regen_ready(f):
				lair_regen_refusals += 1
				continue
			l = restore_lair(f)
			if l == null:
				continue
		if int(l.call("trolls_alive")) == 0:
			l.call("spawn_guards", _GobCfgGM.TROLL_RAID_SPAWN)
			raid_trolls_spawned += 1

## Поставить пень заново на его точке: руина снимается, логово новое (со
## своей отарой из _start_flock), стражей не выпускает — их даст давление овец
func restore_lair(f: int) -> Node:
	if main == null or not lair_spots.has(f):
		return null
	var at: Vector3 = lair_spots[f]
	for r in get_tree().get_nodes_in_group("ruins"):
		if r == null or not is_instance_valid(r):
			continue
		if String(r.get_meta("ruin_building_id", "")) == "troll_lair" \
				and (r as Node3D).global_position.distance_to(at) < 4.0:
			r.get_parent().remove_child(r)
			r.queue_free()
	var lair: Building = load("res://scripts/goblin/TrollLair.gd").new()
	lair.faction = Constants.FACTION_GOBLIN
	lair.set("side_faction", f)
	main.world_add(lair)
	lair.global_position = Vector3(at.x, main.get_terrain_height(at.x, at.z), at.z)
	# Первое логово партии обязано остаться «логовом игрока» (месть орды, стенды)
	troll_lairs = troll_lairs.filter(func(x): return x != null and is_instance_valid(x))
	register_lair(lair)
	if f == Constants.FACTION_PLAYER:
		troll_lair = lair
	lair_restores += 1
	return lair

## Живые овцы стороны (загоны и выпас у замка) — для рейда тролля
func faction_sheep_count(f: int) -> int:
	var n := 0
	for sh in get_tree().get_nodes_in_group("sheep"):
		if sh == null or not is_instance_valid(sh):
			continue
		if bool(sh.get("eaten")) or bool(sh.get("dead")):
			continue
		if int(sh.get("owner_faction")) == f and bool(sh.call("is_owned")):
			n += 1
	return n
## ── РУДНИК ОРДЫ (спринт 17) ────────────────────────────────────────────────
## Гоблинский золотой рудник у деревни: ставит Main._spawn_goblin_mine, читают
## GoblinAI (тревога, охрана) и стенды
var goblin_mine: Node = null

## ── ПЕРЕМИРИЕ ПЕРВЫХ МИНУТ (спринт 20, модуль 6.1) ──────────────────────
## Первые TRUCE_SEC партии ни орда, ни красный ИИ не выходят на чужих: орда
## в мирной фазе (goblin_config.PEACE_SEC — то же число), ИИ не рейдит.
## Считается по часам партии, стенды без Main перемирия не знают
func truce_left() -> float:
	if main == null or not is_instance_valid(main) or not main.has_method("game_clock"):
		return 0.0
	return maxf(_GobCfgGM.TRUCE_SEC - float(main.call("game_clock")), 0.0)

func truce_active() -> bool:
	return truce_left() > 0.0

## Куда бежит обстреливаемый гоблин: деревня орды, а без неё — логово тролля.
## Vector3.INF — лагеря нет (стенд без деревни)
func goblin_camp_point(_from: Vector3) -> Vector3:
	if main != null and main.get("goblin_ai") != null and _Opt.goblin_village:
		return main.goblin_ai.village
	if troll_lair != null and is_instance_valid(troll_lair):
		return (troll_lair as Node3D).global_position
	return Vector3.INF

## Живых троллей логова
func trolls_alive() -> int:
	if troll_lair == null or not is_instance_valid(troll_lair):
		return 0
	return int(troll_lair.call("trolls_alive"))

## Живых троллей по всем логовам
## ── ВОСКРЕШЕНИЕ ПАВШЕГО (спринт 19, письмо 12) ─────────────────────────────
## Тело из слоя тел (CorpseRenderer) становится бойцом: та же сцена, что у
## найма, сторона и род войск — из записи тела, запас MONK_RES_HP, отряд —
## прежний, если он ещё в реестре (иначе новый). Тело снимается без
## растворения. Возвращает бойца или null
var resurrected_total: int = 0

func raise_fallen(corpse, monk: Node = null) -> Unit:
	if corpse == null or main == null or corpses == null:
		return null
	if not bool(corpse.get("raisable")) or int(corpse.get("index")) < 0:
		return null
	var uid: String = String(corpse.get("unit_id"))
	if not Building.PRELOAD_SCENES.has(uid):
		return null
	var fac: int = int(corpse.get("faction"))
	var at: Vector3 = corpse.get("pos")
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	u.current_health = minf(_UCfg.MONK_RES_HP, u.max_health)
	u._soa_push_stats()
	var sid: int = int(corpse.get("squad_id"))
	if sid > 0 and squads.has(sid) and int(squads[sid].get("faction", -1)) == fac:
		add_to_squad(sid, u)
		apply_squad_bonuses_to(sid, u)
	else:
		var nsid: int = new_squad(fac, uid)
		add_to_squad(nsid, u)
	corpses.remove_now(corpse)
	resurrected_total += 1
	if monk != null and is_instance_valid(monk) and monk.has_method("_res_flash"):
		monk.call("_res_flash", u.global_position)
	return u

## ── АВТО-ЗАЩИТА БАЗЫ АРТЕЛЬЮ (спринт 19, письмо 12) ────────────────────────
## Рабочего ударили (или он сам взял врага) — соседи в WORKER_RALLY_RADIUS,
## занятые добычей или стоящие без дела, бросают работу и идут на обидчика.
## Только против МАЛОЙ угрозы (не больше WORKER_RALLY_MAX_FOES чужих бойцов
## рядом с обидчиком): на армию толпой с ножами не бросаются. Не чаще раза в
## WORKER_RALLY_GAP_SEC на сторону — иначе каждый удар заново дёргал бы всю
## артель. Строители со стройки не снимаются: стройка дороже
const WORKER_RALLY_RADIUS := 14.0
const WORKER_RALLY_MAX_FOES := 4
const WORKER_RALLY_GAP_SEC := 3.0
var _worker_rally_ms: Dictionary = {}
var worker_rallies: int = 0

func workers_rally(faction_id: int, foe: Node3D, caller: Node = null) -> int:
	if foe == null or not is_instance_valid(foe) or not (foe is Unit):
		return 0
	var fu := foe as Unit
	if fu.is_dead() or fu.faction == faction_id:
		return 0
	var last: int = int(_worker_rally_ms.get(faction_id, -100000))
	if Time.get_ticks_msec() - last < int(WORKER_RALLY_GAP_SEC * 1000.0):
		return 0
	# Малая ли угроза: чужих бойцов у обидчика
	var fp: Vector3 = fu.global_position
	var foes := 0
	for n in unit_grid.query_radius(fp, 12.0):
		if n == null or not is_instance_valid(n):
			continue
		var nu := n as Unit
		if nu == null or nu.is_dead() or nu.faction == faction_id:
			continue
		foes += 1
		if foes > WORKER_RALLY_MAX_FOES:
			return 0
	_worker_rally_ms[faction_id] = Time.get_ticks_msec()
	var sent := 0
	for n2 in unit_grid.query_radius(fp, WORKER_RALLY_RADIUS):
		if n2 == null or not is_instance_valid(n2) or n2 == caller:
			continue
		var w := n2 as Worker
		if w == null or w.is_dead() or w.faction != faction_id or w.garrisoned:
			continue
		if w.state == Unit.State.BUILDING or w.attack_target != null:
			continue
		w.command_attack(fu, true)
		sent += 1
	if sent > 0:
		worker_rallies += 1
	return sent

## ── ОРДА НЕ СНОСИТ КРЕПОСТЬ ИИ-ЛЮДЕЙ (спринт 18, письмо 8) ─────────────────
## Заказ владельца: гоблины бьют отряды, экономику и любые постройки ИИ, но
## его КРЕПОСТЬ (Castle.is_stronghold, не башня) остаётся целой — снос замка
## красного ИИ это прерогатива ИГРОКА (условие победы). Правило ОДНО и
## спрашивается из четырёх мест: приказ атаки бойца (Unit.command_attack и
## переход замка на соседний дом), выбор цели вожаком и командиром штурма и —
## страховкой — сам урон по постройке (Building.take_damage: брызги, снаряд,
## дубина тролля). Крепость игрока орде по-прежнему доступна
static func goblin_may_raze(b: Node) -> bool:
	if b == null or not is_instance_valid(b) or not (b is Building):
		return true
	var bld := b as Building
	if bld.faction != Constants.FACTION_ENEMY:
		return true
	return not (bld.has_method("is_stronghold") and bool(bld.call("is_stronghold")))

func trolls_alive_all() -> int:
	var n := 0
	for l in troll_lairs:
		if l != null and is_instance_valid(l):
			n += int(l.call("trolls_alive"))
	return n

## Логово зачищено (тролли были и все пали)
func troll_lair_cleared() -> bool:
	if troll_lair == null or not is_instance_valid(troll_lair):
		return false
	return bool(troll_lair.call("is_cleared"))

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

## УЗЕЛ ЗНАМЕНИ ЖИВЁТ В МИРЕ, А НЕ НА БОЙЦЕ (почему — см. SquadBanner). Точка
## у него — точка КОНКРЕТНОГО бойца-знаменосца, и обновляется она каждый кадр
## (см. _update_squad_banners).
## ── ЗАЖЕЧЬ / ОБНОВИТЬ ЗНАМЯ ОТРЯДА ─────────────────────────────────────────
## Зовётся по СОБЫТИЯМ: отряд получил звание, состав изменился, партия
## перезапущена. Покадрового пути здесь нет — за знаменосцем знамя ездит в
## _update_squad_banners.
##
## У знамени есть НОСИТЕЛЬ, и его надо выбрать (см. _assign_bearer): знамя стоит
## не над отрядом, а в руках конкретного бойца
func refresh_squad_banner(squad_id: int) -> void:
	if not squads.has(squad_id):
		return
	var sq: Dictionary = squads[squad_id]
	var lvl: int = int(sq["level"])
	var banner = sq.get("banner")
	var members := squad_members(squad_id)
	# ── БЕЛЫЙ ФЛАГ — СОСТОЯНИЕ ЭТОГО ЖЕ УЗЛА, А НЕ ВТОРОЙ ФЛАГШТОК ──────────
	# Разбор жалобы «юнит с двумя флагами» — в шапке SquadBanner.shown_white.
	# Здесь важно другое: узел нужен отряду в ДВУХ случаях, а не в одном —
	# у ветерана он есть всегда, у новобранца заводится на время паники и
	# исчезает вместе с ней. Отсюда и оба условия ниже
	var white: bool = squad_panicked(squad_id)
	if (lvl <= 0 and not white) or members.is_empty():
		if banner != null and is_instance_valid(banner):
			banner.queue_free()
		sq["banner"] = null
		sq["bearer"] = null
		return
	# Носитель мог выбыть между событиями (гарнизон, смерть в том же кадре)
	if squad_bearer(squad_id) == null:
		_assign_bearer(squad_id)
	if banner != null and is_instance_valid(banner):
		# Уже висит. Но отряд мог подрасти в звании (тогда картинку надо
		# ПЕРЕСТРОИТЬ, иначе на пятом уровне так и висел бы вымпел первого)
		# или запаниковать/успокоиться — тогда меняется лента
		if white:
			banner.show_white(lvl)
		elif bool(banner.shown_white) or int(banner.shown_level) != lvl:
			banner.build(lvl)
		return
	var host: Node = main if main != null and is_instance_valid(main) else null
	if host == null:
		# Мира ещё нет (стенд поднимает отряды до сцены) — попробуем в следующий раз
		return
	var fresh: MeshInstance3D = _SquadBanner.create(maxi(lvl, 1))
	if white:
		fresh.show_white(lvl)
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
## CORRIDOR_TTL_MS), и метка отряда начинала отставать от строя примерно на
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
## буквально: метка отряда стоит в чистом поле, а отряда под ней нет.
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
## выглядело как «метка отвязалась от отряда и прилипла к зданию»: половина
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
## ── ОТРЯД ВЫБИТ: КТО НАД НИМ СМЕЁТСЯ (спринт 18) ─────────────────────────
## Зовётся ДО _disband_squad — словарь отряда ещё цел (тип, сторона).
## Хор орды: последний ВОИН отряда игрока (не рабочий) погиб в обзоре
## какого-нибудь гоблина — четыре смеха разом в точке гибели. Звук идёт ТЕПЕРЬ,
## пока точка освещена обзором павшего: маска тумана закроется тактом позже.
## Клич тролля: отряд или рабочий противника добит троллем — «ха-ха» у туши
var laugh_events: int = 0           # для стендов
var troll_victory_events: int = 0
var laugh_suppressed: int = 0
func _on_squad_wiped(sid: int, sq: Dictionary, last: Unit, at: Vector3) -> void:
	if at == Vector3.INF or last == null:
		return
	var fac: int = int(sq.get("faction", -1))
	var kind: String = String(sq.get("type", ""))
	var killer_raw: Variant = last._slain_by
	if killer_raw != null and is_instance_valid(killer_raw) and killer_raw is Unit:
		var ku := killer_raw as Unit
		if ku.stat_id == "troll" and fac != Constants.FACTION_GOBLIN and not ku.is_dead():
			troll_victory_events += 1
			AudioManager.play_3d("troll_victory", ku.global_position)
	if fac != Constants.FACTION_PLAYER or SINGLE_AGENT_TYPES.has(kind):
		return
	# ── СМЕХ — ТОЛЬКО ЗА УБИЙСТВО ГОБЛИНОМ И ТОЛЬКО В МАЛОЙ СТЫЧКЕ (спринт 20) ─
	# Прежде хор звучал над любым выбитым отрядом игрока, у которого в обзоре
	# оказался хоть один гоблин, — то есть и над тем, кого добил красный ИИ
	# или тролль. Теперь добивший — ГОБЛИН (сторона орды, не тролль), а орды
	# рядом не больше LAUGH_MAX_SQUADS отрядов: это диверсанты и стычки, а не
	# генеральное сражение, где хор глушил бы бой
	if killer_raw == null or not is_instance_valid(killer_raw) or not (killer_raw is Unit):
		return
	var kg := killer_raw as Unit
	if int(kg.faction) != Constants.FACTION_GOBLIN or kg.stat_id == "troll":
		return
	var r: float = _GobCfgGM.LAUGH_SIGHT
	var near_sq := 0
	for key in squads.keys():
		var gsq: Dictionary = squads[key]
		if int(gsq.get("faction", -1)) != Constants.FACTION_GOBLIN:
			continue
		var mem: Array = gsq.get("members", [])
		if mem.is_empty():
			continue
		var c: Vector3 = _centroid_of(mem)
		if Vector2(c.x - at.x, c.z - at.z).length() <= r:
			near_sq += 1
	if near_sq == 0 or near_sq > _GobCfgGM.LAUGH_MAX_SQUADS:
		laugh_suppressed += 1
		return
	laugh_events += 1
	AudioManager.play_chorus("goblin_laugh", at)

## wiped — отряд ВЫБИТ (последний боец погиб), а не расформирован переводом
## или сбросом партии. Знамя падает на землю только в этом случае
func _disband_squad(sid: int, wiped: bool = false) -> void:
	var sq: Variant = squads.get(sid)
	if sq != null:
		# ── ПАВШИЙ В ПАНИКЕ РОНЯЕТ БОЕВОЙ ШТАНДАРТ, А НЕ БЕЛУЮ ТРЯПКУ ──────
		# Заказ владельца. Выходит это САМО, и на это стоит опереться
		# сознательно: упавшее знамя собирается по УРОВНЮ отряда
		# (_lay_fallen_banner → BannerArt.texture_for), а не по той ленте,
		# что висела на древке в последнюю секунду. У отряда БЕЗ звания
		# уровень ноль — _drop_squad_banner выходит сразу, и на земле не
		# остаётся ничего, как и заказано для новобранцев
		if wiped:
			_drop_squad_banner(sid)
		# ── ФЛАГ НЕ ПЕРЕЖИВАЕТ СВОЙ ОТРЯД ──────────────────────────────────
		# Жалоба владельца со скриншотом: «после уничтожения паникующего отряда
		# белый флаг остаётся вертикально торчать из земли». Причина не в самом
		# флаге, а в том, ЧЕРЕЗ ЧТО он гаснет: за точку ему каждый кадр
		# отвечает обход РЕЕСТРА отрядов, а расформированного в реестре уже
		# нет — обход до него не доходит НИКОГДА, и узел остаётся в мире
		# бесхозным и видимым. Поэтому узел снимается ЗДЕСЬ, руками, и снимать
		# его надо было бы даже если бы он был один-единственный
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
	# ── ТРИ КЭША, КОТОРЫЕ ЗДЕСЬ ЗАБЫЛИ, И ОНИ РОСЛИ ВСЮ ПАРТИЮ ─────────────
	# Соседние строки заведены ровно этим доводом («за длинный бой из сотен
	# расформированных отрядов словари росли и не убывали»), а эти три под него
	# не попали. Точка подхода к постройке и её срок снимаются только явным
	# squad_clear_attack_anchor, а центр отряда не снимался вообще ничем: его
	# пишет каждый пересчёт коридора, то есть запись заводится КАЖДОМУ отряду,
	# который хоть раз куда-то шёл. Ошибки ответа тут нет (номера отрядов
	# внутри партии не переиспользуются), есть чистый рост памяти
	_squad_atk_anchor.erase(sid)
	_squad_atk_hold.erase(sid)
	_squad_centre.erase(sid)
	_matrix_release(sid)

# ═════════════════════════════════════════════════════════════════════════════
# МОРАЛЬ И ПАНИКА ОТРЯДА («БЕЛЫЙ ФЛАГ»)
# ═════════════════════════════════════════════════════════════════════════════
# ПОЧЕМУ МОРАЛЬ — ЧИСЛО ОТРЯДА, А НЕ БОЙЦА. Паникует и бежит ОТРЯД целиком:
# поодиночке этого не бывает ни в жизни, ни в игре, где единица управления —
# отряд. Держать её на бойце значило бы усреднять шестьдесят чисел на каждую
# проверку и заводить шестьдесят таймеров ступора вместо одного.
#
# ЧТО РОНЯЕТ И ЧТО ПОДНИМАЕТ — всё в конфиге (unit_stats_config, блок МОРАЛЬ И
# ПАНИКА). Здесь только механика.
#
# ПОРОГОВ ПАНИКИ ДВА, И ОБА ОБЯЗАТЕЛЬНЫ (заказ владельца):
#   • АБСОЛЮТНЫЙ — мораль упала ниже PANIC_THRESHOLD от максимума. Он ловит
#     отряд, который просто перемололи;
#   • ОТНОСИТЕЛЬНЫЙ — мораль стала вдвое ниже, чем у того отряда, с которым
#     идёт бой. Он ловит другое: свежий отряд против ветеранов ломается ДО
#     того, как потеряет половину состава, и это и есть «психология боя».
# Одного абсолютного мало: без относительного новобранцы дрались бы с
# легендой на равных до последнего человека.
#
# СТУПОР — ЭТО ПОТЕРЯ УПРАВЛЕНИЯ, А НЕ СМЕРТЬ. Двадцать секунд отряд не
# слушает приказов, не атакует и получает срезанную защиту (см.
# Unit._panicked). Добить его в это время можно и нужно — в этом весь смысл
# механики: бой выигрывается не полным истреблением, а сломом.
# ═════════════════════════════════════════════════════════════════════════════

## Как часто пересчитывается мораль. Не каждый кадр: отрядов десятки, а
## величина меняется событиями (гибель, попадание), а не непрерывно
const MORALE_SWEEP_SEC := 0.25
var _morale_timer: float = 0.0

## ПОЛНЫЙ ШТАТ ОТРЯДА — наибольшее число бойцов, какое в нём когда-либо было
## (см. add_to_squad). Именно от него считается ДОЛЯ потерь: у отряда из
## двенадцати человек гибель одного весит впятеро больше, чем у отряда из
## шестидесяти, и это верно по существу
func squad_full_size(sid: int) -> int:
	if sid <= 0 or not squads.has(sid):
		return 1
	var sq: Dictionary = squads[sid]
	return maxi(int(sq.get("full", 0)), maxi((sq["members"] as Array).size(), 1))

## СИЛА ОТРЯДА В ПЕХОТИНЦАХ, а не в головах (заказ владельца:
## «1 всадник = 2 пехотинца при расчёте морали и силы отряда»;
## сам вес — в unit_stats_config.squad_weight, то есть в таблице, а не в коде).
## full = true — по ПОЛНОМУ штату, false — по ЖИВЫМ.
##
## Вес берётся ОДИН РАЗ по роду войск ОТРЯДА, а не у каждого бойца:
## один заказ — один отряд — один род, а чтение таблицы на каждого из
## шестидесяти стоило бы шестидесяти поисков четыре раза в секунду
func _weight_of_squad(sid: int, full: bool) -> float:
	if sid <= 0 or not squads.has(sid):
		return 0.0
	var w: float = _UCfg.squad_weight(String(squads[sid].get("type", "")))
	var n: int = squad_full_size(sid) if full else _alive_in_squad(sid)
	return float(n) * w

## Сколько бойцов отряда ещё живы. По ним считается третий порог паники
## (PANIC_LAST_MEN), и состав здесь берётся НАПРЯМУЮ из записи, а не через
## squad_members(): тот РАСПУСКАЕТ опустевший отряд прямо в геттере, а сюда
## приходят из покадрового обхода морали, который перебирает все отряды подряд
## (та же грабля, что поймал qa_squad на марш-обходе).
## Павший уходит из списка не мгновенно (queue_free отложен), поэтому живых
## считаем проверкой is_dead(), а не размером массива
func _alive_in_squad(sid: int) -> int:
	if sid <= 0 or not squads.has(sid):
		return 0
	var n := 0
	for m in (squads[sid]["members"] as Array):
		if m == null or not is_instance_valid(m):
			continue
		if not (m as Unit).is_dead():
			n += 1
	return n

## Базовая мораль отряда — средняя по СОСТАВУ. Считается один раз, когда в
## отряде появился первый боец: до этого состава нет вовсе
func _squad_base_morale(sid: int) -> float:
	var men: Array = (squads[sid] as Dictionary)["members"]
	var acc := 0.0
	var n := 0
	for m in men:
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		acc += u.morale
		n += 1
	if n == 0:
		return _UCfg.MORALE_MAX
	return clampf(acc / float(n), 1.0, _UCfg.MORALE_MAX)

## Текущая мораль отряда, 0..MORALE_MAX. Ленивая инициализация: −1 в записи
## означает «состава ещё не было, брать неоткуда»
func squad_morale(sid: int) -> float:
	if sid <= 0 or not squads.has(sid):
		return _UCfg.MORALE_MAX
	var sq: Dictionary = squads[sid]
	var m: float = float(sq.get("morale", -1.0))
	if m < 0.0:
		m = _squad_base_morale(sid)
		sq["morale"] = m
	return m

## Доля морали от полной: по ней считается абсолютный порог паники
func squad_morale_frac(sid: int) -> float:
	return squad_morale(sid) / _UCfg.MORALE_MAX

## Изменить мораль. ЕДИНСТВЕННАЯ точка записи: все события боя ходят сюда
func squad_add_morale(sid: int, delta: float) -> void:
	if sid <= 0 or not squads.has(sid) or delta == 0.0:
		return
	var sq: Dictionary = squads[sid]
	var m: float = squad_morale(sid) + delta
	sq["morale"] = clampf(m, 0.0, _UCfg.MORALE_MAX)

## Паникует ли отряд прямо сейчас
func squad_panicked(sid: int) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	return Time.get_ticks_msec() < int((squads[sid] as Dictionary).get("panic_until", 0))

## ── ЛЕГЕНДАРНЫЙ ОТРЯД РЯДОМ ────────────────────────────────────────────────
## Возвращает множитель морали для отряда: +50 % от своей легенды поблизости,
## −25 % НОВОБРАНЦУ (отряд без единой лычки), если рядом чужая легенда.
##
## Считается по ЦЕНТРАМ отрядов, а не по бойцам: аура — свойство отряда, и
## обходить состав ради неё значило бы платить сотнями сравнений за число,
## которое меняется раз в четверть секунды. Центры уже посчитаны коридором
## (см. _squad_centre)
func _legend_morale_mult(sid: int) -> float:
	var sq: Dictionary = squads[sid]
	var c: Vector2 = squad_centre_xz(sid)
	if c == Vector2.INF:
		return 1.0
	var my_fac: int = int(sq.get("faction", -1))
	var rookie: bool = int(sq.get("level", 0)) == 0
	var r2: float = _UCfg.LEGEND_AURA_RADIUS * _UCfg.LEGEND_AURA_RADIUS
	var mult := 1.0
	for key in squads:
		var other: Dictionary = squads[key]
		if int(other.get("level", 0)) < _UCfg.LEGEND_TIER:
			continue
		if int(key) == sid:
			continue
		var oc: Vector2 = squad_centre_xz(int(key))
		if oc == Vector2.INF:
			continue
		var dx: float = oc.x - c.x
		var dz: float = oc.y - c.y
		if dx * dx + dz * dz > r2:
			continue
		if int(other.get("faction", -1)) == my_fac:
			mult = maxf(mult, _UCfg.LEGEND_AURA_ALLY_MULT)
		elif rookie:
			mult = minf(mult, _UCfg.LEGEND_AURA_FOE_MULT)
	return mult

## ── ЕДИНСТВЕННЫЙ ТАКТ МОРАЛИ ───────────────────────────────────────────────
## Здесь три дела и все три — отрядные: снять ступор с тех, у кого срок вышел;
## вернуть мораль тем, кто вышел из боя; сорвать в панику тех, кто дошёл до
## порога. Порядок именно такой: отряд, только что вышедший из ступора, не
## должен в тот же такт сорваться обратно (за это отвечает PANIC_RECOVER_MORALE)
## ── СОДЕРЖАНИЕ ЕДОЙ (заказ владельца, 10.09.2026) ────────────────────────────
## Раз в FOOD_UPKEEP_TICK: живые рабочие (отряды-одиночки) и боевые отряды
## стороны едят по unit_stats_config.FOOD_UPKEEP_*; списание — из склада не
## ниже нуля, недостача = голод (food_starving), его читает обход морали.
## Расход в секунду отдаётся складу (ResourceManager.set_upkeep) — HUD
## показывает его рядом с притоком еды
var _food_timer: float = 0.0
var food_starving: Dictionary = {}
var food_upkeep_rate: Dictionary = {}
var food_upkeep_workers: Dictionary = {}
var food_upkeep_squads: Dictionary = {}

func _sweep_food(delta: float) -> void:
	_food_timer -= delta
	if _food_timer > 0.0:
		return
	_food_timer = _UCfg.FOOD_UPKEEP_TICK
	for f0 in _UCfg.FOOD_UPKEEP_FACTIONS:
		var f: int = int(f0)
		var workers := 0
		var combat := 0
		var food_extra := 0.0
		var gold_rate := 0.0
		for key in squads.keys():
			var sq: Dictionary = squads[key]
			if int(sq["faction"]) != f:
				continue
			var alive := 0
			for m in (sq["members"] as Array):
				if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
					alive += 1
			if alive == 0:
				continue
			var sid: int = int(key)
			if squad_is_single_agent(sid):
				workers += alive
			elif squad_is_combat(sid):
				combat += 1
				# ── ЭЛИТА ЕСТ БОЛЬШЕ, И ЕЩЁ ЗОЛОТО (заказ 13.09.2026) ──────
				# Отряд с лычками содержится дороже новобранца: еды больше на
				# долю за лычку, плюс отдельная статья золотом. Ранг берётся у
				# САМОГО ОТРЯДА — правило накрывает и элиту Крепости, и отряд,
				# доросший до лычек в бою: платят за ОПЫТ, а не за место найма
				var vet: int = int(sq.get("level", 0))
				if vet > 0:
					food_extra += _UCfg.FOOD_UPKEEP_SQUAD_PER_SEC \
						* (_UCfg.keep_food_mult(vet) - 1.0)
					gold_rate += _UCfg.keep_gold_rate(vet)
		var rate: float = float(workers) * _UCfg.FOOD_UPKEEP_WORKER_PER_SEC \
			+ float(combat) * _UCfg.FOOD_UPKEEP_SQUAD_PER_SEC + food_extra
		food_upkeep_rate[f] = rate
		food_upkeep_workers[f] = workers
		food_upkeep_squads[f] = combat
		ResourceManager.set_upkeep(f, Constants.RESOURCE_FOOD, rate)
		var short: float = ResourceManager.consume(f, Constants.RESOURCE_FOOD, rate * _UCfg.FOOD_UPKEEP_TICK)
		food_starving[f] = short > 0.0
		# ЗОЛОТО ЗА СОДЕРЖАНИЕ ЭЛИТЫ. Нехватка золота — НЕ голод: мораль
		# она не трогает (это дело еды), а бьёт по кошельку — платить
		# нечем, значит нечем и нанимать
		gold_upkeep_rate[f] = gold_rate
		ResourceManager.set_upkeep(f, Constants.RESOURCE_GOLD, gold_rate)
		if gold_rate > 0.0:
			ResourceManager.consume(f, Constants.RESOURCE_GOLD,
				gold_rate * _UCfg.FOOD_UPKEEP_TICK)

## Сколько золота в секунду уходит на содержание элиты (для панели ресурсов)
var gold_upkeep_rate: Dictionary = {}

func is_starving(faction: int) -> bool:
	return bool(food_starving.get(faction, false))

func _sweep_morale(delta: float) -> void:
	_morale_timer -= delta
	if _morale_timer > 0.0:
		return
	_morale_timer = MORALE_SWEEP_SEC
	var now: int = Time.get_ticks_msec()
	for key in squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = squads[sid]
		if (sq["members"] as Array).is_empty():
			continue
		# 1. СРОК СТУПОРА ВЫШЕЛ — ОТРЯД СНОВА СЛУШАЕТ ПРИКАЗЫ
		var until: int = int(sq.get("panic_until", 0))
		if until > 0:
			if now >= until:
				_end_panic(sid)
			else:
				# Связность отряда держится тактом морали, а не одной раздачей
				# точек в момент срыва (см. _panic_regroup)
				_panic_regroup(sid)
			continue                     # паникующему остальное не считаем
		# 2. ВНЕ БОЯ МОРАЛЬ ВОЗВРАЩАЕТСЯ
		if not squad_in_combat(sid):
			# ГОЛОД (10.09.2026): склад еды пуст — мораль вне боя не
			# восстанавливается, а тает до пола (выше порога паники)
			if bool(food_starving.get(int(sq["faction"]), false)):
				if squad_morale_frac(sid) > _UCfg.STARVE_MORALE_FLOOR:
					squad_add_morale(sid, -_UCfg.STARVE_MORALE_PER_SEC * MORALE_SWEEP_SEC)
				continue
			squad_add_morale(sid, _UCfg.MORALE_REGEN_PER_SEC * MORALE_SWEEP_SEC)
			continue
		# 3. ПОРОГ ПАНИКИ. Аура легенды входит МНОЖИТЕЛЕМ В ПОРОГ, а не в саму
		#    мораль: иначе уход легенды с поля резал бы отряду накопленное
		#    число, и он паниковал бы от одного её отъезда
		var mult: float = _legend_morale_mult(sid)
		var frac: float = squad_morale_frac(sid) * mult
		var broke: bool = frac < _UCfg.PANIC_THRESHOLD
		# ── ТРЕТИЙ ПОРОГ: «НАС ПОЧТИ НЕ ОСТАЛОСЬ» ──────────────────
		# Заказ владельца: «паника от потерь срабатывает не на 50 % отряда,
		# а когда остаётся буквально три-семь моделек». Это условие
		# НЕВЫРАЗИМО через мораль: мораль долевая, а требование абсолютное,
		# и у отрядов разного размера оно наступает на разных долях.
		# Счёт ведётся В ПЕХОТИНЦАХ, а не в головах (см. _weight_of_squad):
		# отряд кабанов — десять моделей, и порог «осталось шестеро» без веса
		# срывал бы его после четырёх потерь
		if not broke and _weight_of_squad(sid, true) >= float(_UCfg.PANIC_LAST_MEN_MIN_ROSTER):
			broke = _weight_of_squad(sid, false) <= float(_UCfg.PANIC_LAST_MEN)
		if not broke:
			# ОТНОСИТЕЛЬНЫЙ ПОРОГ: вдвое ниже того, с кем деремся
			var foe: int = squad_melee_foe(sid)
			if foe > 0 and squads.has(foe):
				var fm: float = squad_morale_frac(foe) * _legend_morale_mult(foe)
				broke = frac < fm * _UCfg.PANIC_RATIO
		if broke:
			_start_panic(sid)

## ── СРЫВ ───────────────────────────────────────────────────────────────────
## Отряд бросает бой и разбегается ВО ВСЕ СТОРОНЫ. Врассыпную, а не строем: у
## паники нет строя по определению, и разлёт по спирали золотого угла — тот же
## приём, которым в проекте уже расставлена толпа орды (goblin_config.horde_offset)
func _start_panic(sid: int) -> void:
	# ── «НЕПРЕКЛОННЫЕ» НЕ ПАНИКУЮТ ВОВСЕ ───────────────────────────────────
	# Легендарный перк, и проверка стоит ЗДЕСЬ, в единственной точке срыва:
	# разбросай её по условиям порога — и второй порог (относительный) её
	# однажды обойдёт
	if squad_has_perk(sid, "legend_steadfast"):
		return
	var sq: Dictionary = squads[sid]
	sq["panic_until"] = Time.get_ticks_msec() + int(_UCfg.PANIC_STUN_SEC * 1000.0)
	var c: Vector2 = squad_centre_xz(sid)
	var base := Vector3(c.x, 0.0, c.y) if c != Vector2.INF else Vector3.ZERO
	var men: Array = squad_members(sid)
	# Разметка строя после паники не значит ничего: отряд её бросил
	squad_clear_formation(sid)
	# ── БЕГУТ ВРАССЫПНУЮ ВО ВСЕ СТОРОНЫ, А НЕ «ПРОЧЬ ОТ ВРАГА» ──────────
	# РАЗВОРОТ ТРЕБОВАНИЯ (заказ владельца по скриншоту): было «весь отряд
	# уходит по вектору от противника с небольшим разбросом», стало
	# «случайный вектор во все стороны». На экране прежнее решение
	# читалось не как паника, а как ОРГАНИЗОВАННЫЙ ОТХОД: шестьдесят
	# человек ехали одной толпой в одну сторону — ровно то, что владелец
	# описал словами «а не только вверх».
	#
	# ПОЧЕМУ НЕ `randf()`. Два прогона одного боя обязаны давать одно
	# поле, иначе стенд не проверить (то же правило, что у угла
	# втыкания стрелы и у фазы анимации). Золотой угол по номеру
	# бойца даёт равномерный веер без двух одинаковых направлений, а
	# начало веера сбито номером узла — два отряда не разлетятся одинаково
	var spin: float = 0.0
	if not men.is_empty() and is_instance_valid(men[0]):
		spin = float(int((men[0] as Node).get_instance_id()) % 360) * (TAU / 360.0)
	# ── КУДА БЕЖИТ ОТРЯД КАК ЦЕЛОЕ ─────────────────────────────────────────
	# ПОПРАВКА ВЛАДЕЛЬЦА, и это ВОЗВРАТ прежнего требования: «паникующие бойцы
	# должны двигаться в одном направлении (от источника угрозы), но с
	# сохранением связности отряда». Разбег «во все стороны» отменяется не
	# целиком — он остаётся РАЗБРОСОМ вокруг общей точки, а не самим бегством.
	# Разница на экране решающая: раньше диск разлёта равнялся дальности
	# бегства, и отряд рвало пополам; теперь отряд уезжает кучей, а внутри
	# кучи у каждого своё направление и своя дистанция.
	var away: Vector3 = -squad_enemy_dir(sid)
	away.y = 0.0
	if away.length_squared() < 1e-6:
		# Противник неизвестен (сорвались от потерь, а не от того, с кем
		# дерёмся): бежим от середины карты, то есть к своему краю
		away = base - Vector3.ZERO
		away.y = 0.0
	if away.length_squared() < 1e-6:
		away = Vector3.BACK
	away = away.normalized()
	# ── ОТ КРАЯ КАРТЫ ОТВОРАЧИВАЕМ (заказ 13.09.2026) ──────────────────────
	away = _panic_slide_from_edge(base, away)
	var herd: Vector3 = _panic_inside(base + away * _UCfg.PANIC_FLEE_DIST)
	# Ось конуса и его половина в радианах
	var ax: float = atan2(away.z, away.x)
	var half: float = deg_to_rad(_UCfg.PANIC_CONE_DEG)
	for i in range(men.size()):
		var u := men[i] as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		# ── КОНУС, А НЕ ПОЛНЫЙ КРУГ ────────────────────────────────────────
		# Направление внутри ±PANIC_CONE_DEG от вектора бегства. Жребий
		# детерминированный (золотой угол по номеру бойца, сбитый номером
		# узла): два прогона одного боя обязаны давать одно поле
		var t: float = fmod(spin + float(i) * 2.39996, TAU) / TAU   # 0..1
		var ang: float = ax + (t * 2.0 - 1.0) * half
		# Разброс ВНУТРИ круга связности, а не на всю дальность бегства
		var r: float = _UCfg.PANIC_SPREAD * sqrt(
			float((i * 7 + 3) % maxi(men.size(), 1) + 1) / float(maxi(men.size(), 1)))
		var spot := herd + Vector3(cos(ang), 0.0, sin(ang)) * r
		u.panic_flee(land_target(_panic_inside(spot)))
	_show_panic_flag(sid, true)

## ── ТОЧКА БЕГСТВА ДЕРЖИТСЯ ПОДАЛЬШЕ ОТ КРОМКИ МИРА ─────────────────────────
## `land_target` зажимает приказ границей карты, и отряд, бегущий наружу,
## получал точку РОВНО НА КРОМКЕ — все до одного. Здесь запас берётся ДО
## зажима: беглец уходит вдоль края, а не втыкается в него
func _panic_inside(p: Vector3) -> Vector3:
	if map_lim_x >= 1e8:
		return p                     # границы сняты (стенды) — не наше дело
	var m: float = _UCfg.PANIC_EDGE_MARGIN
	var lx: float = maxf(map_lim_x - m, 1.0)
	var lz: float = maxf(map_lim_z - m, 1.0)
	return Vector3(clampf(p.x, -lx, lx), p.y, clampf(p.z, -lz, lz))

## Вектор бегства, смотрящий за край, ЗАВАЛИВАЕТСЯ ВДОЛЬ границы.
## Просто зажать точку мало: тогда весь отряд получает одну и ту же кромку и
## копится на ней. Снимаем составляющую, направленную наружу; если после
## этого не осталось ничего (угол карты), уходим по касательной к ближней
## стороне — «беги по краю», а не «беги в угол»
func _panic_slide_from_edge(base: Vector3, away: Vector3) -> Vector3:
	if map_lim_x >= 1e8:
		return away
	var m: float = _UCfg.PANIC_EDGE_MARGIN
	var v := Vector3(away.x, 0.0, away.z)
	if base.x > map_lim_x - m and v.x > 0.0: v.x = 0.0
	if base.x < -(map_lim_x - m) and v.x < 0.0: v.x = 0.0
	if base.z > map_lim_z - m and v.z > 0.0: v.z = 0.0
	if base.z < -(map_lim_z - m) and v.z < 0.0: v.z = 0.0
	if v.length_squared() > 1e-6:
		return v.normalized()
	# Угол карты: обе составляющие срезаны. Идём вдоль ТОЙ стороны, до которой
	# дальше — так беглец уходит в поле, а не вдоль короткой кромки обратно
	var dx: float = map_lim_x - absf(base.x)
	var dz: float = map_lim_z - absf(base.z)
	if dx > dz:
		return Vector3(-signf(base.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, -signf(base.z))

## ── ПАНИКУЮЩИХ, УЕХАВШИХ СЛИШКОМ ДАЛЕКО, ЗОВЁМ ОБРАТНО ─────────────────────
## Точки бегства раздаются ОДИН раз, в момент срыва, и внутри круга связности —
## но за двадцать секунд ступора бойца успевает утащить что угодно: чужая
## конница, толчок в свалке, разбор наложения на краю карты. Без подзыва
## связность держалась бы только на честном слове раздачи.
##
## ЗОВЁМ ТЕМ ЖЕ panic_flee, А НЕ command_move: паникующий приказов не слушает
## (гейт в Unit.command_move), и panic_flee — единственная дверь, которая для
## него открыта (см. разбор порядка в Unit.panic_flee)
func _panic_regroup(sid: int) -> void:
	var c: Vector2 = squad_centre_xz(sid)
	if c == Vector2.INF:
		return
	var centre := Vector3(c.x, 0.0, c.y)
	var limit: float = _UCfg.PANIC_SPREAD * _UCfg.PANIC_REGROUP_MULT
	for m in (squads[sid]["members"] as Array):
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		var p: Vector3 = u.global_position
		var d := Vector2(p.x - centre.x, p.z - centre.z)
		if d.length() <= limit:
			continue
		# Возвращаем НЕ в центр, а на границу круга связности со своей стороны:
		# в центр сошлись бы все разом, и паника читалась бы как построение
		var back: Vector3 = centre + Vector3(d.x, 0.0, d.y).normalized() \
			* (_UCfg.PANIC_SPREAD * 0.8)
		u.panic_flee(land_target(back))

## ── ПОРЯДОК ВОССТАНОВЛЕН ───────────────────────────────────────────────────
## Мораль возвращается НЕ в ноль и НЕ в максимум: с нулём отряд сорвался бы
## повторно в ту же секунду, с максимумом он выходил бы из разгрома свежим
func _end_panic(sid: int) -> void:
	var sq: Dictionary = squads[sid]
	sq["panic_until"] = 0
	sq["morale"] = _UCfg.MORALE_MAX * _UCfg.PANIC_RECOVER_MORALE
	for m in squad_members(sid):
		var u := m as Unit
		if u != null and is_instance_valid(u):
			u.set_panicked(false)
	_show_panic_flag(sid, false)

## Кого отряд сейчас считает своим противником (для относительного порога).
## Берётся из уже готовой боевой бухгалтерии, своего скана здесь нет
func squad_melee_foe(sid: int) -> int:
	var e = _melee.get(sid)
	if e == null:
		return 0
	return int((e as Dictionary).get("foe", 0))

## ── БЕЛЫЙ ФЛАГ: ДВА СЦЕНАРИЯ, ОДИН УЗЕЛ ────────────────────────────────────
## ЗАКАЗ ВЛАДЕЛЬЦА, поправка по скриншотам:
##   А. ОТРЯД БЕЗ ЗВАНИЯ (новобранцы). Своего флага у него нет: на время паники
##      флаг ЗАВОДИТСЯ, а по её окончании или по гибели отряда — исчезает
##      бесследно. На земле не остаётся ничего (у отряда без звания и падать
##      нечему — см. _drop_squad_banner, он выходит на lvl <= 0).
##   Б. ОТРЯД СО ЗВАНИЕМ (ветераны). Флаг у него уже есть, и ВТОРОЙ НЕ
##      ЗАВОДИТСЯ: родное знамя меняет ЛЕНТУ на белую, а по окончании паники
##      возвращает боевую. Погиб в панике — на земле остаётся БОЕВОЙ штандарт,
##      а не белая тряпка: упавшее знамя собирается по УРОВНЮ отряда
##      (_lay_fallen_banner → BannerArt.texture_for), а не по тому, что висело
##      на древке в последнюю секунду.
##
## ЗДЕСЬ БЫЛ ВТОРОЙ УЗЕЛ, И ОН ДАВАЛ РАЗОМ ДВЕ ЖАЛОБЫ. «Юнит с двумя флагами»
## — прямое следствие: знамя ветеранства висит на знаменосце, белый флаг висел
## над ЦЕНТРОМ отряда, и на экране они сходились в одну точку. «Белый флаг
## застыл в воздухе, вместо того чтобы следовать за юнитом» — следствие того же
## выбора точки: центр отряда это МЕДИАНА, а паникующий отряд разбегается, и
## медиана садится в пустое поле МЕЖДУ разбежавшимися (замер зондом qa_panic:
## 12.22 м до ближайшего бойца). Теперь флаг ездит на знаменосце, как и знамя,
## то есть всегда на живом бойце
func _show_panic_flag(sid: int, _on: bool) -> void:
	refresh_squad_banner(sid)

## ── ЛЕГЕНДАРНЫЕ ПЕРКИ ──────────────────────────────────────────────────────
## Седьмой уровень ветеранства даёт не цифры, а ПРАВИЛО: иммунитет к панике,
## пробитие брони, щит от стрел. Хранится тем же списком, что и обычные
## выборы (squads[sid]["chosen"]), поэтому сохранение партии подхватывает их
## само — отдельного поля и отдельной ветки в SaveLoadManager не нужно
## ── ПРОВЕРКА ЗА ОДНО СРАВНЕНИЕ ЦЕЛЫХ ───────────────────────────────────────
## Здесь стояло `perk_id in chosen` — ЛИНЕЙНЫЙ ПЕРЕБОР СТРОК по списку всех
## выбранных наград отряда. А спрашивают отсюда из `squad_armor_pierce`, то
## есть из `Unit.take_damage` жертвы, — на КАЖДОЕ списание урона. Список растёт
## с рангом: чем дольше живёт отряд, тем дороже становился каждый удар.
##
## Слово битов ведёт `apply_veteran_choice` по событию выбора награды
## (см. `_UCfg.perk_bit`). ИСТИНА ПРИ ЭТОМ ОСТАЛАСЬ В "chosen": сохранение
## пишет и читает именно его, и второго хранилища наград в проекте не заводим.
##
## ЗАПАСНОЙ ПЕРЕБОР ОБЯЗАТЕЛЕН для id, которого нет в `LEGEND_PERK_IDS`: бита у
## него не будет никогда, а молчаливое «перка нет» обошлось бы дороже перебора —
## легендарное правило просто перестало бы работать, и заметить это можно было
## бы только по числам.
func squad_has_perk(sid: int, perk_id: String) -> bool:
	if sid <= 0 or not squads.has(sid):
		return false
	var sq: Dictionary = squads[sid]
	var bit: int = _UCfg.perk_bit(perk_id)
	if bit != 0:
		return (_perk_bits_of(sq) & bit) != 0
	return perk_id in (sq["chosen"] as Array)

## ── СЛОВО ПЕРКОВ ВЫВОДИТСЯ ИЗ СПИСКА, А НЕ ВЕДЁТСЯ ПО СОБЫТИЮ ──────────────
## ЗДЕСЬ БЫЛО ДВЕ НЕВЕРНЫХ ВЕРСИИ ПОДРЯД, и обе стоит помнить.
##
## ПЕРВАЯ ВЕЛА СЛОВО ПО СОБЫТИЮ — из `apply_veteran_choice`. Но список наград
## пишут не только оттуда: его ставит загрузка партии и, главное, ЕГО СТАВЯТ
## СТЕНДЫ НАПРЯМУЮ (`squads[sid]["chosen"] = ["legend_pierce"]` — так делает
## qa_balance). У такого отряда слово оставалось нулём, и легендарный перк не
## работал вовсе.
##
## ВТОРАЯ СВЕРЯЛА ДЛИНУ СПИСКА — и пропускала ПОДМЕНУ РАВНОЙ ДЛИНЫ. Тот же
## qa_balance меняет `["legend_steadfast"]` на `["legend_pierce"]`: длина та
## же, перк другой, слово устарело. D5 покраснел ровно на этом.
##
## Верный признак свежести — САМА ССЫЛКА НА МАССИВ ПЛЮС ЕГО РАЗМЕР. Присвоение
## кладёт в словарь НОВЫЙ массив (ссылка другая), append правит прежний
## (ссылка та же, размер другой) — вместе это покрывает все три пути записи:
## событие, загрузку и стенд. Второго источника правды при этом не заводится:
## истина по-прежнему в `chosen`, слово только выводится из него.
##
## На горячем пути это два чтения словаря и два сравнения; пересборка идёт
## несколько раз за партию на отряд
func _perk_bits_of(sq: Dictionary) -> int:
	var chosen: Array = sq["chosen"]
	if not is_same(sq.get("perk_src"), chosen) \
			or int(sq.get("perk_n", -1)) != chosen.size():
		sq["perk_bits"] = _UCfg.perk_mask_of(chosen)
		sq["perk_n"] = chosen.size()
		sq["perk_src"] = chosen
	return int(sq["perk_bits"])

## Проверка ПО ГОТОВОМУ БИТУ, без единого обращения к строке. Для тех, кто
## спрашивает один и тот же перк постоянно: бит у них снимается один раз и
## лежит полем (см. _bit_pierce)
func squad_has_perk_bit(sid: int, bit: int) -> bool:
	if bit == 0 or sid <= 0 or not squads.has(sid):
		return false
	return (_perk_bits_of(squads[sid]) & bit) != 0

## Бит «пробития брони», снятый один раз. Даже словарный поиск по строке —
## это ХЭШ СТРОКИ, а эту функцию зовут на каждое списание урона
var _bit_pierce: int = -1

## Доля чужой брони, которую игнорирует этот НАПАДАЮЩИЙ. Спрашивается из
## take_damage жертвы, поэтому принимает узел, а не номер отряда
func squad_armor_pierce(attacker: Node) -> float:
	if attacker == null or not is_instance_valid(attacker) or not (attacker is Unit):
		return 0.0
	var sid: int = (attacker as Unit).squad_id
	if sid <= 0:
		return 0.0
	if _bit_pierce < 0:
		_bit_pierce = _UCfg.perk_bit("legend_pierce")
	return _UCfg.LEGEND_PIERCE_FRAC if squad_has_perk_bit(sid, _bit_pierce) else 0.0

# ═════════════════════════════════════════════════════════════════════════════
# ЗНАМЯ ЕДЕТ ЗА ЗНАМЕНОСЦЕМ
# ═════════════════════════════════════════════════════════════════════════════
# У знамени носитель — конкретный боец, и спрашивать у него НАРИСОВАННУЮ точку
# (Unit.draw_position) можно каждый кадр: она уже сглажена между физическими
# шагами тем же механизмом, что и сам спрайт. Поэтому здесь нет ни редкого
# пересчёта, ни догоняющего lerp, ни словаря целей — знамя просто стоит там,
# где нарисован его знаменосец, кадр в кадр.
#
# ЦЕНА: один обход отрядов (их десятки, не тысячи) и одно чтение точки на отряд.
# Прежний вариант обходил ВЕСЬ СОСТАВ каждого отряда ради центра масс.
## Как часто проверять, что знамя всё ещё стоит в переднем левом углу.
## Проверка — это обход состава ОДНОГО отряда, и делать её каждый кадр незачем:
## строй сам собой в порядок не приходит, а после смыкания рядов знаменосца и
## так переназначают событием
const BEARER_RECHECK_SEC := 1.0
var _bearer_recheck_at: float = 0.0

func _update_squad_banners() -> void:
	# ── ЗНАМЯ ВОЗВРАЩАЕТСЯ В УГОЛ САМО ─────────────────────────────────────
	# Событий недостаточно: знаменосца назначают при смыкании рядов и при
	# гибели носителя, а отряд теряет форму и без того и без другого (проход
	# союзников, толчок конницы, возврат из гарнизона). Раз в секунду сверяем
	# носителя с местом [ряд 0, колонка 0] и, если он там уже не лучший,
	# переназначаем. В БОЮ не трогаем: там знамя переходит по гибели, и дёргать
	# его посреди рубки означало бы гонять флаг сквозь свалку
	var now_s: float = float(Time.get_ticks_msec()) * 0.001
	var recheck: bool = now_s >= _bearer_recheck_at
	if recheck:
		_bearer_recheck_at = now_s + BEARER_RECHECK_SEC
	for key in squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = squads[key]
		var banner = sq.get("banner", null)
		if banner == null or not is_instance_valid(banner):
			continue
		# СВЕРКА ИДЁТ И БЕЗ РАЗМЕТКИ, если знамя носят В СЕРЕДИНЕ (толпа орды,
		# паникующий отряд): у них угол строя не при чём, а середина кучи
		# уезжает на каждом шаге — без сверки флаг остался бы на том, кто был
		# посередине двадцать секунд назад, то есть уже на ободе
		if recheck and not squad_in_combat(sid) \
				and (_bearer_slot0(sid) != Vector3.INF or _bearer_in_middle(sid)):
			_assign_bearer(sid)
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
var _flight_sweep_t: float = 1.0
const _ArrowRendererScript := preload("res://scripts/ArrowRenderer.gd")
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

# ─────────────────────────────────────────────────────────────────────────────
# ЛИМИТ НАСЕЛЕНИЯ ИГРОКА (дома, заказ 09.09.2026)
#
# Каждый дом даёт слоты рабочих и боевых отрядов (unit_stats_config.POP_* /
# HOUSE_*_SLOTS). Ворота — Building.queue_unit: заказ сверх лимита не
# принимается и не оплачивается. Считаются ЖИВЫЕ плюс ЗАКАЗАННЫЕ, иначе
# десять заказов подряд обходили бы лимит.
#
# ВКЛЮЧАЕТ ПАРТИЯ, А НЕ КОНФИГ САМ ПО СЕБЕ (см. Main.start_game): стенды
# собирают сцену руками и нанимают так, как ни один игрок не нанимает —
# семь отрядов из одного барака без единого дома. Правило партии, а не
# бойца, поэтому и живёт оно у партии. Стенд лимита включает его явно.
# На ИИ не действует: у красного свои потолки (ai_start_army_limit), орда
# домов не строит
# ─────────────────────────────────────────────────────────────────────────────
var pop_limit_enabled: bool = false

## Сколько ДОСТРОЕННЫХ домов у фракции
func house_count(p_faction: int) -> int:
	var n := 0
	for b in nodes_in_group_cached(Constants.building_group(p_faction)):
		# Правило 5: снесённый дом в кэше группы ещё лежит, а приводить
		# освобождённый объект к типу нельзя — сначала is_instance_valid
		if b == null or not is_instance_valid(b):
			continue
		var bl := b as Building
		if bl == null or bl.is_dead():
			continue
		if _UCfg.is_house(bl.building_id):
			n += 1
	return n

## Сколько живых КРЕПОСТЕЙ у стороны. Башня — тоже Castle (ради гарнизона), но
## столицей не является и лимита не даёт: спрашиваем is_stronghold()
func castle_count(p_faction: int) -> int:
	var n := 0
	for b in nodes_in_group_cached(Constants.building_group(p_faction)):
		# Правило 5: снесённая крепость в кэше группы ещё лежит
		if b == null or not is_instance_valid(b):
			continue
		var c := b as Castle
		if c == null or c.is_dead():
			continue
		if c.is_stronghold():
			n += 1
	return n

func pop_worker_cap(p_faction: int) -> int:
	return _UCfg.pop_worker_cap(house_count(p_faction), castle_count(p_faction))

func pop_squad_cap(p_faction: int) -> int:
	return _UCfg.pop_squad_cap(house_count(p_faction), castle_count(p_faction))

## Живые монахи плюс заказанные
func monks_used(p_faction: int) -> int:
	var n := 0
	for u in nodes_in_group_cached(Constants.unit_group(p_faction)):
		if u == null or not is_instance_valid(u):
			continue
		if u is Monk and not (u as Unit).is_dead():
			n += 1
	for b in nodes_in_group_cached(Constants.building_group(p_faction)):
		if b == null or not is_instance_valid(b):
			continue
		var bl := b as Building
		if bl == null:
			continue
		n += bl.in_progress_count("monk")
	return n

## Живые рабочие плюс заказанные
func pop_workers_used(p_faction: int) -> int:
	var n := 0
	for u in nodes_in_group_cached(Constants.unit_group(p_faction)):
		if u == null or not is_instance_valid(u):
			continue
		if u is Worker and not (u as Unit).is_dead():
			n += 1
	for b in nodes_in_group_cached(Constants.building_group(p_faction)):
		if b == null or not is_instance_valid(b):
			continue
		var bl := b as Building
		if bl == null:
			continue
		n += bl.in_progress_count("worker")
	return n

## Живые боевые отряды (с хотя бы одним живым бойцом) плюс заказанные.
## Состав читается напрямую, а не через squad_members(): тот распускает
## опустевший отряд прямо в геттере (см. CLAUDE.md, раздел про марш)
## ── ОТРЯД МОЖЕТ ЗАНИМАТЬ БОЛЬШЕ ОДНОГО СЛОТА ─────────────────────────────
## Заказ владельца (10.09.2026): отряд рыцарей стоит двух пехотных
## (unit_stats_config.squad_slots). Считается это И у живых, И у заказанных:
## иначе десять заказов рыцарей обошли бы лимит, как когда-то обходили его
## десять заказов подряд вообще
func pop_squads_used(p_faction: int) -> int:
	var n := 0
	for key in squads.keys():
		var sq: Dictionary = squads[key]
		if int(sq["faction"]) != p_faction or String(sq["type"]) == "worker":
			continue
		for m in (sq["members"] as Array):
			if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
				n += _UCfg.squad_slots(String(sq["type"]))
				break
	for b in nodes_in_group_cached(Constants.building_group(p_faction)):
		if b == null or not is_instance_valid(b):
			continue
		var bl := b as Building
		if bl == null:
			continue
		for order in bl.production_queue:
			var oname: String = String((order as Dictionary).get("name", ""))
			if oname != "worker":
				n += _UCfg.squad_slots(oname)
	return n

## Можно ли ещё заказать такого бойца. Ворота найма (Building.queue_unit)
func pop_allows(p_faction: int, unit_name: String) -> bool:
	if p_faction != Constants.FACTION_PLAYER:
		return true
	# МОНАХ — ОДИН НА ИГРОКА (unit_stats_config.MONK_LIMIT), и это правило
	# бойца, а не партии: действует и в стендах, в отличие от лимита домов
	if unit_name == "monk":
		return monks_used(p_faction) < _UCfg.MONK_LIMIT
	if not pop_limit_enabled:
		return true
	if unit_name == "worker":
		return pop_workers_used(p_faction) < pop_worker_cap(p_faction)
	# МЕСТО НУЖНО ПОД ВЕСЬ ОТРЯД: рыцарям — два слота, остальным один
	return pop_squads_used(p_faction) + _UCfg.squad_slots(unit_name) \
		<= pop_squad_cap(p_faction)

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
	# ── ЗДАНИЕ БЕЗ СТАДИИ СТРОЙКИ (unit_stats_config `instant_build`) ──────
	# Ресурсы уже списаны выше, в момент заказа: постановка отличается только
	# тем, что на карту встаёт ГОТОВАЯ постройка, а не площадка с артелью.
	# Фабрику зовём ТУ ЖЕ, что достраивает обычные здания
	# (ConstructionSite._make_target) — второго списка «id → класс» в проекте
	# быть не должно, забытая там строка означала бы вечный фундамент
	var instant: bool = bool(_UCfg.building_cfg(build_id).get("instant_build", false))
	main.enter_building_placement(cost, size,
		func(pos: Vector3):
			if instant:
				var made: Building = _CSite.make_building(build_id)
				if made == null:
					return
				made.faction = f
				main.world_add(made)
				made.global_position = pos
				return
			var site: Building = _CSite.new()
			site.faction     = f
			site.target_id   = build_id
			site.target_name = bname
			site.build_time  = btime
			site.build_size  = size
			main.world_add(site)
			site.global_position = pos
			# Очередь Shift (письмо 12): занятый строитель ставит площадку в
			# очередь, свободный идёт сразу
			var queue: bool = Input.is_key_pressed(KEY_SHIFT)
			# ВСЯ артель сразу бежит на стройку
			for b in team:
				if is_instance_valid(b) and b.has_method("command_build"):
					b.command_build(site, queue),
		bname, build_id,
		func():
			try_worker_build(worker, build_id, crew))

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
## ── АВТО-ВОССТАНОВЛЕНИЕ РУДНИКА ИИ / ОРДЫ (спринт 18) ────────────────────
## Таймер на точку: по истечении руина рудника в этой точке снимается, и на
## её месте встаёт рудник прежнего владельца. Руины нет (отстроил рабочий) —
## ничего не делаем. Цены нет: восстановление ИИ идёт мимо склада
var mine_restores: int = 0           # стендам
var mine_restore_pending: int = 0

func schedule_mine_restore(at: Vector3, f: int, sec: float) -> void:
	if main == null:
		return
	mine_restore_pending += 1
	var t := get_tree().create_timer(sec)
	t.timeout.connect(_restore_mine_at.bind(at, f))

func _restore_mine_at(at: Vector3, f: int) -> void:
	mine_restore_pending = maxi(mine_restore_pending - 1, 0)
	if main == null or not is_instance_valid(main):
		return
	var ruin: Node = null
	for r in get_tree().get_nodes_in_group("ruins"):
		if r == null or not is_instance_valid(r):
			continue
		if String(r.get_meta("ruin_building_id", "")) != "mine":
			continue
		if (r as Node3D).global_position.distance_to(at) < 2.0:
			ruin = r
			break
	if ruin == null:
		return
	ruin.get_parent().remove_child(ruin)
	ruin.queue_free()
	var m := Mine.new()
	m.faction = Constants.FACTION_NEUTRAL
	main.world_add(m)
	m.global_position = Vector3(at.x, main.get_terrain_height(at.x, at.z), at.z)
	m.set_owner_faction(f)
	if f == Constants.FACTION_GOBLIN and goblin_mine != null \
			and not is_instance_valid(goblin_mine):
		goblin_mine = m
		if main.get("goblin_ai") != null:
			main.goblin_ai.attach_mine(m)
	mine_restores += 1

func rebuild_ruin(ruin: Node, faction_override: int = -1) -> Node:
	if main == null or ruin == null or not is_instance_valid(ruin):
		return null
	if not ruin.is_in_group("ruins"):
		return null
	var build_id: String = String(ruin.get_meta("ruin_building_id", ""))
	if build_id.is_empty():
		return null
	var f: int = int(ruin.get_meta("ruin_faction", Constants.FACTION_PLAYER))
	# Общая руина (золотой рудник): достаётся тому, кто отстраивает
	if faction_override >= 0 and bool(ruin.get_meta("ruin_any_faction", false)):
		f = faction_override
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
		"Бараки", "barracks")

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
		"Кузница", "smithy")

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
		"Рудник", "mine")

# ── КЭШ СПИСКОВ ГРУПП НА ОДИН ФИЗИЧЕСКИЙ КАДР ────────────────────────────────
# get_tree().get_nodes_in_group() КАЖДЫЙ РАЗ строит новый массив. В свалке
# сотни бойцов за один кадр ищут цель, и каждый заново запрашивал список
# вражеских зданий — сотни аллокаций в кадр на список из трёх домов.
# Внутри одного кадра состав группы не меняется (queue_free отложен), поэтому
# массив можно переиспользовать. Проверки is_instance_valid у вызывающих
# остаются на месте.
var _grp_cache: Dictionary = {}
var _grp_frame: int = -1

# ═════════════════════════════════════════════════════════════════════════════
# СНИМОК ЧУЖИХ ЗДАНИЙ: КООРДИНАТЫ ПЛОСКИМ МАССИВОМ, РАЗ В КАДР
# ═════════════════════════════════════════════════════════════════════════════
# ЗАЧЕМ. Поиск цели (Unit._find_nearest_enemy_in_range) — одно из самых горячих
# мест игры: в большом бою сотня с лишним вызовов в кадр. Каждый из них
# перебирал группы чужих зданий и читал у каждого здания global_position, то
# есть свойство с проверкой и пересборкой мировой матрицы. Координаты при этом
# не меняются ВООБЩЕ: здание стоит там, где его поставили.
#
# Снимок собирается раз в физический кадр на фракцию и отдаётся парой
# «узлы + плоские координаты XZ». Дистанция считается по массиву float, а к
# самому узлу обращаются только у победителя — то есть один раз вместо всех.
#
# ЖИВЁТ РОВНО КАДР, как и кэш групп рядом: постройка может пасть в любой момент,
# и держать снимок дольше означало бы стрелять по руинам
var _bld_snap: Dictionary = {}
var _bld_snap_frame: int = -1

func enemy_buildings_snapshot(faction: int) -> Array:
	var f := Engine.get_physics_frames()
	if f != _bld_snap_frame:
		_bld_snap_frame = f
		_bld_snap.clear()
	var got: Variant = _bld_snap.get(faction)
	if got != null:
		return got as Array
	var nodes: Array = []
	var xz := PackedFloat32Array()
	for b_grp in Constants.enemy_building_groups(faction):
		for node in nodes_in_group_cached(String(b_grp)):
			if not is_instance_valid(node):
				continue
			var p: Vector3 = (node as Node3D).global_position
			nodes.append(node)
			xz.append(p.x)
			xz.append(p.z)
	var row: Array = [nodes, xz]
	_bld_snap[faction] = row
	return row

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
	# ВОДА — ПРАВИЛО ПАРТИИ, КАК И ГРАНИЦЫ МИРА (09.09.2026). Стенды снимают
	# границы, когда собирают сцену руками в любой точке поля; река по центру
	# карты обратила бы половину их площадок в воду (qa_panic: отряд на оси
	# русла разлетался по берегам). Снят world_bounds_enabled — снята и вода
	if not world_bounds_enabled:
		return false
	return main.is_water(x, z)

## Разрешённый шаг с обходом озера по берегу (Vector3.ZERO — пути нет)
## Дорога через брод (Main.ford_route). Зовётся ИЗ ПРИКАЗА, а не из кадра:
## игрок щёлкает разы в секунду, и цена перехода границы здесь не при чём
func ford_route(from_p: Vector3, to_p: Vector3, lane_dz: float) -> Array:
	if not water_active or not world_bounds_enabled or main == null:
		return []
	return main.ford_route(from_p, to_p, lane_dz)

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
## ПОТОЛОК СЧИТАЕТСЯ ОТ ЗАЛПА, А НЕ «ЧТОБЫ БЫЛО». Две тысячи лучников при
## кулдауне 4 с и секундном полёте держат в воздухе ~500 стрел разом, плюс
## 160 торчащих: при прежних 512 каждый залп на большом бою упирался в
## потолок, и стрелы шли через queue_free/new — ровно та работа, ради
## которой пул заведён. Узел стрелы теперь голый (картинка в общем
## MultiMesh, этап D3), три тысячи спящих узлов стоят копейки
const ARROW_POOL_MAX := 3000

var _arrow_pool: Array = []
## ── КОСТИ В СВОЁМ ПУЛЕ, И ЭТО НЕ ПРИДИРКА ─────────────────────────────────
## Слот общего MultiMesh стрела берёт ОДИН РАЗ, в _build_visual, и держит его
## всю жизнь узла (см. Arrow._slot_i). Значит, узел навсегда принадлежит своему
## слою: выдай стрелу из общего пула под кость — и кость нарисуется стрелой
var _bone_pool: Array = []

## Выдать стрелу под выстрел. Возвращает узел, уже стоящий в дереве под
## `parent` и взведённый на полёт
## Сколько стрел выпущено за партию. Монотонный, только растёт (см. spawn_arrow)
var arrows_fired: int = 0

## p_bone — снаряд ГНОЛЛА (кость): свой слой отрисовки и свой пул, всё
## остальное (полёт, попадание, урон, срок) в точности как у стрелы
func spawn_arrow(parent: Node, start: Vector3, end_pos: Vector3, dist: float,
		speed: float, arc_factor: float, dmg: float, who: Node3D,
		p_faction: int, p_bone: bool = false) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		return null
	# СЧЁТЧИК ВЫСТРЕЛОВ, монотонный. Стрелы живут в пуле и не состоят ни в одной
	# группе, поэтому «сколько выстрелов сделано» иначе не спросить: стенд
	# qa_volley считает по нему темп стрельбы отряда (залп — это пачки, обычная
	# стрельба — ровный ручеёк). Один int на выстрел
	arrows_fired += 1
	var a: Node3D = null
	# Пул мог пережить смену сцены: узлы из прошлой партии уже освобождены
	var pool: Array = _bone_pool if p_bone else _arrow_pool
	while not pool.is_empty():
		var cand = pool.pop_back()
		if is_instance_valid(cand):
			a = cand
			break
	var fresh: bool = a == null
	if fresh:
		a = _ArrowScript.new()
		# ВИД РЕШАЕТСЯ ДО _ready(): картинку и слой берёт _build_visual, а он
		# идёт из _ready — поставь признак позже, и кость улетит стрелой
		a.set("bone", p_bone)
	a.set("_start_pos",  start)
	a.set("_end_pos",    end_pos)
	a.set("_dist",       dist)
	a.set("_speed",      speed)
	a.set("_arc_factor", arc_factor)
	a.set("damage",      dmg)
	a.set("shooter",     who)
	a.set("faction",     p_faction)
	if fresh:
		# У свежей взведение делает _ready(), уже после add_child — и ТОЧКА
		# обязана стоять ДО него: launch() пишет слот общего MultiMesh по
		# текущей позиции, и стрела, взведённая в начале координат, один кадр
		# рисовалась в центре карты. Стрелы живут под World с нулевой
		# трансформацией, поэтому локальная точка здесь и есть мировая
		a.position = start
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

## ── СРОК ТОРЧАЩИХ СТРЕЛ СЧИТАЕТ ОДИН ОБХОД, А НЕ СТО ШЕСТЬДЕСЯТ УЗЛОВ ──────
## Каждая воткнувшаяся стрела держала СВОЙ `_process` ради одного сложения
## float — до MAX_STUCK_ARROWS нотификаций движка в кадр на чистую декорацию.
## Реестр торчащих здесь уже есть (он держит потолок), и обойти его циклом
## дешевле, чем сто шестьдесят раз войти в GDScript из движка. Тот же приём и
## та же причина, что у тел павших: декорация не заводит своего тика.
##
## ОБХОД ИДЁТ С КОНЦА. Истёкшая стрела уходит в пул сама (`Arrow._despawn`), а
## тот зовёт `forget_stuck_arrow`, то есть ПРАВИТ ЭТОТ ЖЕ МАССИВ прямо посреди
## цикла. При счёте сверху вниз удаление сдвигает только то, что уже пройдено.
##
## Живёт в `_process`, а не в физике: здесь считается растворение, то есть
## КАРТИНКА, и на паузе стрелы обязаны стоять — ровно так же вёл себя их
## собственный `_process` до переезда
func _sweep_stuck_arrows(delta: float) -> void:
	var i: int = _stuck_arrows.size() - 1
	while i >= 0:
		var a = _stuck_arrows[i]
		if a == null or not is_instance_valid(a):
			_stuck_arrows.remove_at(i)
		else:
			a.tick_stuck(delta)
		i -= 1

## Сколько стрел торчит на поле прямо сейчас (стенды)
func stuck_arrow_count() -> int:
	return _stuck_arrows.size()

## Принять погасшую стрелу обратно (зовёт Arrow._despawn).
## Кость возвращается в СВОЙ пул: слот слоя отрисовки у узла пожизненный
func recycle_arrow(a: Node3D) -> void:
	var pool: Array = _bone_pool if bool(a.get("bone")) else _arrow_pool
	if pool.size() >= ARROW_POOL_MAX:
		a.queue_free()
		return
	pool.append(a)

## Новая партия: узлы прошлой сцены уже недействительны
func clear_arrow_pool() -> void:
	for a in _arrow_pool:
		if is_instance_valid(a):
			a.queue_free()
	_arrow_pool.clear()
	for b in _bone_pool:
		if is_instance_valid(b):
			b.queue_free()
	_bone_pool.clear()
	# Реестр торчащих держит узлы прошлой сцены — та же оговорка, что у пула
	_stuck_arrows.clear()

## Сколько стрел лежит наготове (стенды)
func arrow_pool_size() -> int:
	return _arrow_pool.size()

## Сколько костей лежит наготове (стенды)
func bone_pool_size() -> int:
	return _bone_pool.size()

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
	if not is_water(c.x, c.y):
		# Приказ на скалу недостижим так же, как в воду (спринт 18)
		var q: Vector2 = nearest_passable(c.x, c.y)
		return Vector3(q.x, main.get_terrain_height(q.x, q.y), q.y)
	var p: Vector2 = main.nearest_land(c.x, c.y)
	var p2: Vector2 = nearest_passable(p.x, p.y)
	return Vector3(p2.x, main.get_terrain_height(p2.x, p2.y), p2.y)

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

## Доля зума камеры: 0 — вплотную (min_height), 1 — предел отдаления.
## Докладывает RTSCamera раз в кадр; читает окно марша (AudioManager)
var _view_zoom: float = 0.0
var _view_reported: bool = false

func view_zoom() -> float:
	return _view_zoom

## Точка фокуса камеры — центр экрана на земле
func view_point() -> Vector3:
	return Vector3(_view_x, 0.0, _view_z)

## Докладывала ли камера о себе хоть раз (стенды без сцены — нет)
func has_view_point() -> bool:
	return _view_reported

func update_view_point(pos: Vector3, ground_radius: float = 0.0,
		zoom_t: float = -1.0) -> void:
	_view_x = pos.x
	_view_z = pos.z
	var r: float = maxf(_Opt.lod_radius, ground_radius)
	_view_r2 = r * r
	if zoom_t >= 0.0:
		_view_zoom = clampf(zoom_t, 0.0, 1.0)
	_view_reported = true

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
## Сколько раз ось экрана менялась (этап E3, событийная поза)
var _cam_epoch: int = 0
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
	var nr: Vector3 = right.normalized()
	# Ракурс сменился — поза всех бойцов устарела (зеркало и направленные
	# листы считаются от оси экрана). Эпоху читает Unit.tick_visual
	if (nr - _cam_right).length_squared() > 1.0e-6:
		_cam_epoch += 1
	_cam_right = nr
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
## ── УМОЛЧАНИЕ У `get` — ЭТО АЛЛОКАЦИЯ НА КАЖДЫЙ ВЫЗОВ ───────────────────────
## Здесь стояло `_squad_target.get(sid, {})`. Второй аргумент вычисляется
## БЕЗУСЛОВНО, до всякого поиска ключа: литерал `{}` создаёт новый пустой
## словарь и на попадании в кэш, и на промахе. А зовут эту функцию из
## `Unit._squad_cached_enemy` — то есть из авто-агро и из боевого автомата,
## сотни раз в кадр. Проверка на null стоит одного сравнения и не выделяет
## ничего (правило 4: ни String, ни Array, ни Dictionary в покадровом пути)
func squad_target_get(sid: int, radius: float, now: float) -> Node3D:
	var got: Variant = _squad_target.get(sid)
	if got == null:
		return null
	var e: Dictionary = got
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

## ── ГОРЯЧИЙ ВХОД: ТОЧКА БЕЗ ЕДИНОЙ АЛЛОКАЦИИ ───────────────────────────────
## Возвращает МИРОВУЮ точку ближайшего врага отряда либо Vector3.INF, если
## врага нет. Заведён вместо `squad_enemy_pos` в покадровом пути и ровно ради
## этого: прежний ответ парой «[точка, нашли ли]» строил НОВЫЙ Godot-массив на
## каждый вызов, а вызывают его все копейщики в стойке ЗАЩИТА четыре раза в
## секунду (Unit._update_live_rank). На трёх тысячах это две сотни массивов и
## две сотни словарей-умолчаний в КАЖДОМ кадре — при том, что дальше от ответа
## нужны ровно три float.
##
## Vector3.INF как «нет ответа» — тот же приём, что уже используется у
## squad_centre_xz (Vector2.INF) и у ArmyCore.PosOr: значение вместо пары
func squad_enemy_point(sid: int, asker: Node3D, radius: float) -> Vector3:
	if sid <= 0:
		var solo: Array = unit_grid.nearest_enemy_pos(asker, radius)
		return (solo[0] as Vector3) if bool(solo[1]) else Vector3.INF
	# ЧАСЫ БЕРУТСЯ У АРМИИ, А НЕ У ДВИЖКА. Time.get_ticks_msec() — вызов в
	# движок, и он стоял здесь НА КАЖДОГО спросившего, хотя внутри одного тика
	# ответ один и тот же и уже снят один раз (см. Unit.now_ms). Запасной путь
	# нужен стендам, поднимающим отряды до первого кадра
	var nms: int = Unit.now_ms
	if nms == 0:
		nms = Time.get_ticks_msec()
	var now: float = float(nms) * 0.001
	var got: Variant = _squad_face.get(sid)
	if got != null:
		var e: Dictionary = got
		if now - float(e["t"]) <= SQUAD_FACE_TTL \
				and absf(float(e["r"]) - radius) < 0.01:
			return e["p"] if bool(e["ok"]) else Vector3.INF
	var res: Array = unit_grid.nearest_enemy_pos(asker, radius)
	var ok: bool = bool(res[1])
	var p: Vector3 = res[0]
	# Заодно запоминаем ОДИН КУРС НА ОТРЯД — от спросившего к найденному врагу.
	# Точки мало: каждый боец, считая направление ОТ СЕБЯ к общей точке,
	# получает свой угол, и у отряда шириной в шесть человек крайние колонны
	# расходятся с центром на 15–20°. Полоса подсчёта ряда разворачивается
	# наискось, сосед СБОКУ засчитывается как стоящий впереди, и строй теряет
	# понимание, где у него перёд (см. Unit._phalanx_dir)
	var d := Vector3.ZERO
	if ok:
		var ap: Vector3 = asker.global_position
		var au := asker as Unit
		if au != null and au._local_xform:
			ap = au.position
		d = Vector3(p.x - ap.x, 0.0, p.z - ap.z)
		d = d.normalized() if d.length_squared() > 1e-6 else Vector3.ZERO
	# ЗАПИСЬ ИДЁТ В УЖЕ ЗАВЕДЁННЫЙ СЛОВАРЬ, А НЕ В НОВЫЙ ЛИТЕРАЛ. Промах кэша
	# случается раз в SQUAD_FACE_TTL на отряд, но отрядов десятки, а литерал —
	# это ещё и пять новых ключей-строк на каждую пересборку
	if got != null:
		var e2: Dictionary = got
		e2["t"] = now
		e2["r"] = radius
		e2["p"] = p
		e2["ok"] = ok
		e2["d"] = d
	else:
		_squad_face[sid] = {"t": now, "r": radius, "p": p, "ok": ok, "d": d}
	return p if ok else Vector3.INF

## Мировая точка ближайшего врага для отряда. Второе значение — нашли ли.
## sid = 0 (боец вне отряда) кэш не использует: делить ему не с кем
## ── ХОЛОДНАЯ ОБЁРТКА. Покадровый путь зовёт squad_enemy_point (см. выше);
## этот вид ответа остался ради стендов и внешних вызовов, которым удобнее пара
func squad_enemy_pos(sid: int, asker: Node3D, radius: float) -> Array:
	var p: Vector3 = squad_enemy_point(sid, asker, radius)
	if p == Vector3.INF:
		return [Vector3.ZERO, false]
	return [p, true]

## Общий курс отряда «на противника», снятый вместе с кэшем ближайшего врага.
## Vector3.ZERO — кэша нет либо врага не видно
func squad_enemy_dir(sid: int) -> Vector3:
	if sid <= 0:
		return Vector3.ZERO
	var got: Variant = _squad_face.get(sid)
	if got == null:
		return Vector3.ZERO
	return (got as Dictionary).get("d", Vector3.ZERO)

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
	# Вода есть, если есть озеро ИЛИ река (09.09.2026)
	water_active = bool(main.LAKE_ENABLED) or bool(main.RIVER_ENABLED)
	# ГОРА И РЕКА — В ЯДРО: высота и вода считаются там же, где шаг (см.
	# ArmyCore.Height / RiverWater), иначе боец на холме уходил бы под землю,
	# а каждый шаг платил бы за is_water межъязыковым вызовом
	if army != null:
		var hc: Vector2 = main.hill_center()
		army.set_hill(hc.x, hc.y, float(main.HILL_HEIGHT), float(main.HILL_RADIUS))
		army.set_river(bool(main.RIVER_ENABLED), float(main.RIVER_HALF_W),
			float(main.RIVER_MEANDER), float(main.RIVER_MEANDER_K), float(main.FORD_Z),
			float(main.FORD_HALF), float(main.RIVER_DEPTH), float(main.FORD_DEPTH),
			float(main.RIVER_BANK), float(main.LAKE_MARGIN), float(main.MAP_HALF_Z),
			float(main.wet_depth()))
		# Плато — теми же числами (10.09.2026)
		army.set_plateaus(main.plateau_params(), float(main.PLATEAU_RAMP_GENTLE),
			float(main.PLATEAU_RAMP_STEEP), float(main.PLATEAU_RAMP_CONE))
		# ── СКАЛЫ (спринт 18): маска непроходимых склонов ────────────────────
		# Строится ядром по своей высоте (та же Height, что у шага) один раз
		# на карту; порог — стена плато (PLATEAU_WALL_SLOPE). Действует как
		# вода: только при включённых границах мира (правило партии)
		if bool(main.CLIFFS_ENABLED):
			var cell: float = float(main.CLIFF_CELL)
			var cols: int = int(ceil(2.0 * float(main.MAP_HALF_X) / cell))
			var rows: int = int(ceil(2.0 * float(main.MAP_HALF_Z) / cell))
			cliff_cells = army.build_cliff_mask(-float(main.MAP_HALF_X), -float(main.MAP_HALF_Z),
				cell, cols, rows, _relief_amp_now(), float(main.CLIFF_SLOPE))
			# ── СЕТКА НАВИГАЦИИ (спринт 19, письмо 11) ──────────────────────
			# Из маски скал и воды реки вне брода; по ней ядро ищет обход
			nav_cells_blocked = army.build_nav_grid(NAV_CELL)
			_nav_cache.clear()
		else:
			army.set_cliff_enabled(false)
			army.set_nav_enabled(false)
			cliff_cells = 0
			nav_cells_blocked = 0

## ── СКАЛЫ ──────────────────────────────────────────────────────────────────
## Сколько ячеек маски непроходимы (стендам); 0 — скал нет
var cliff_cells: int = 0

## Непроходимый склон в точке. Как вода — правило партии: снятые границы мира
## снимают и скалы (стенды строят площадки где угодно)
func is_cliff(x: float, z: float) -> bool:
	if not world_bounds_enabled or army == null or cliff_cells <= 0:
		return false
	return army.is_cliff(x, z)

## ── НАВИГАЦИЯ ВОКРУГ СКАЛ И ВОДЫ (спринт 19, письмо 11) ───────────────────
## Поиска пути в игре не было — боец шёл по прямой и скользил вдоль стены.
## Теперь у ядра есть коарс-сетка проходимости (NAV_CELL) и A* по ней
## (ArmyCore.NavPath): маршрут запрашивает ПРИКАЗ (Unit.command_move) и
## подход к цели раз в NAV_RECHECK (Unit._atk_waypoint); в покадровый путь
## сетка не входит. Кэш на ОДИН физкадр по огрублённым ячейкам (NAV_KEY_CELL):
## шестьдесят бойцов одного приказа стоят в паре ячеек и получают один ответ.
## Правило партии, как вода и скалы: снятые границы мира снимают и маршрут
const NAV_CELL := 2.0
const NAV_KEY_CELL := 4.0
var nav_cells_blocked: int = 0
var _nav_cache: Dictionary = {}
var _nav_cache_frame: int = -1
var nav_routes_built: int = 0

func nav_on() -> bool:
	return world_bounds_enabled and army != null and nav_cells_blocked > 0

## Прямая между точками упирается в скалу или воду?
func nav_blocked(a: Vector3, b: Vector3) -> bool:
	if not nav_on():
		return false
	return army.nav_line_blocked(a.x, a.z, b.x, b.z)

func nav_free(p: Vector3) -> bool:
	if not nav_on():
		return true
	return army.nav_free(p.x, p.z)

func _nav_key(a: Vector3, b: Vector3) -> int:
	var ax: int = int(floor(a.x / NAV_KEY_CELL)) + 2048
	var az: int = int(floor(a.z / NAV_KEY_CELL)) + 2048
	var bx: int = int(floor(b.x / NAV_KEY_CELL)) + 2048
	var bz: int = int(floor(b.z / NAV_KEY_CELL)) + 2048
	return ((ax * 4096 + az) * 4096 + bx) * 4096 + bz

## Ответ ядра за этот физкадр: [найден ли путь, длина нити, точки]
func _nav_query(a: Vector3, b: Vector3) -> Array:
	var f: int = Engine.get_physics_frames()
	if f != _nav_cache_frame:
		_nav_cache.clear()
		_nav_cache_frame = f
	var key: int = _nav_key(a, b)
	var got: Variant = _nav_cache.get(key)
	if got != null:
		return got
	var nt: int = Time.get_ticks_usec() if _Opt.class_meter else 0
	var flat: PackedFloat32Array = army.nav_path(a.x, a.z, b.x, b.z)
	if _Opt.class_meter:
		_Opt.nav_usec += Time.get_ticks_usec() - nt
		_Opt.nav_calls += 1
	var pts := PackedVector3Array()
	var i := 0
	while i + 1 < flat.size():
		pts.append(Vector3(flat[i], 0.0, flat[i + 1]))
		i += 2
	var res: Array = [army.nav_last_found(), army.nav_last_length(), pts]
	_nav_cache[key] = res
	nav_routes_built += 1
	return res

## Промежуточные точки обхода от a к b (пусто — идти прямо или пути нет)
func nav_route(a: Vector3, b: Vector3) -> PackedVector3Array:
	if not nav_on():
		return PackedVector3Array()
	return _nav_query(a, b)[2]

## Цель за обрывом/рекой недостижима для инициативы: прямой нет, а обход
## либо не найден, либо длиннее прямой больше чем на leash
func nav_unreachable(a: Vector3, b: Vector3, leash: float) -> bool:
	if not nav_on():
		return false
	if not army.nav_line_blocked(a.x, a.z, b.x, b.z):
		return false
	var q: Array = _nav_query(a, b)
	if not bool(q[0]):
		return true
	var straight: float = Vector2(b.x - a.x, b.z - a.z).length()
	return float(q[1]) > straight + leash

## Полный маршрут приказа: брод (своя полоса) плюс обходы скал до брода и
## после него; без реки на пути — один обход. lat — смещение бойца от центра
## отряда (XZ): промежуточные точки раздвигаются поперёк хода, чтобы отряд
## шёл через проход КОЛОННОЙ в несколько человек, а не ниткой в одну точку
const NAV_LAT_MAX := 3.5
func build_route(from_p: Vector3, goal: Vector3, lane_dz: float, lat: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array()
	var ford: Array = ford_route(from_p, goal, lane_dz)
	if ford.size() == 2:
		out.append_array(_nav_spread(from_p, nav_route(from_p, ford[0]), lat))
		out.append(ford[0])
		out.append(ford[1])
		out.append_array(_nav_spread(ford[1], nav_route(ford[1], goal), lat))
	else:
		out.append_array(_nav_spread(from_p, nav_route(from_p, goal), lat))
	return out

func _nav_spread(from_p: Vector3, pts: PackedVector3Array, lat: Vector2) -> PackedVector3Array:
	if pts.is_empty() or (absf(lat.x) < 0.05 and absf(lat.y) < 0.05):
		return pts
	var out := PackedVector3Array()
	var prev: Vector3 = from_p
	for i in range(pts.size()):
		var p: Vector3 = pts[i]
		var d := Vector2(p.x - prev.x, p.z - prev.z)
		var l: float = d.length()
		var q: Vector3 = p
		if l > 0.05:
			var perp := Vector2(-d.y / l, d.x / l)
			var off: float = clampf(lat.dot(perp), -NAV_LAT_MAX, NAV_LAT_MAX)
			var cand := Vector3(p.x + perp.x * off, 0.0, p.z + perp.y * off)
			if nav_free(cand) and not army.nav_line_blocked(prev.x, prev.z, cand.x, cand.z):
				q = cand
			else:
				cand = Vector3(p.x + perp.x * off * 0.5, 0.0, p.z + perp.y * off * 0.5)
				if nav_free(cand) and not army.nav_line_blocked(prev.x, prev.z, cand.x, cand.z):
					q = cand
		out.append(q)
		prev = q
	return out

## Ближайшая проходимая точка (не скала): кольцами по CLIFF_SEARCH_STEP до
## CLIFF_SEARCH_R; не нашлась — исходная
const CLIFF_SEARCH_STEP := 1.0
const CLIFF_SEARCH_R := 24.0
func nearest_passable(x: float, z: float) -> Vector2:
	if not is_cliff(x, z):
		return Vector2(x, z)
	var r: float = CLIFF_SEARCH_STEP
	while r <= CLIFF_SEARCH_R:
		var n: int = maxi(8, int(TAU * r / CLIFF_SEARCH_STEP))
		for i in range(n):
			var a: float = TAU * float(i) / float(n)
			var px: float = x + cos(a) * r
			var pz: float = z + sin(a) * r
			if not is_cliff(px, pz) and not is_water(px, pz):
				return Vector2(px, pz)
		r += CLIFF_SEARCH_STEP
	return Vector2(x, z)

## Точка, зажатая в границы карты (Vector2 = x/z). Через неё проходит каждое
## перемещение юнита: за край мира не выходит никто и никогда.
## ГОРЯЧИЙ ПУТЬ — держать без вызовов наружу
func clamp_to_map(x: float, z: float) -> Vector2:
	if not world_bounds_enabled:
		return Vector2(x, z)
	return Vector2(clampf(x, -map_lim_x, map_lim_x),
		clampf(z, -map_lim_z, map_lim_z))
