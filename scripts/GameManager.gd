extends Node

var main: Node3D = null
var dropoffs: Dictionary = {}
# Пространственная сетка юнитов (см. SpatialGrid.gd); load() — чтобы не зависеть от кэша классов
var unit_grid = load("res://scripts/SpatialGrid.gd").new()
# Реестр отрисовки дальних юнитов общим MultiMesh (см. FarUnitRenderer.gd)
var far_units = load("res://scripts/FarUnitRenderer.gd").new()
# Кольца и тени выделения — тоже общим MultiMesh (см. SelectionDecalRenderer.gd)
var sel_decals = load("res://scripts/SelectionDecalRenderer.gd").new()
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
	var shards: int = _Opt.shards_for(_live_units.size())
	# Номер кадра — ОДИН вызов в движок на всю армию, а не по одному на бойца
	var frame: int = Engine.get_process_frames()
	if shards <= 1:
		for u in _live_units:
			if is_instance_valid(u) and u.is_processing():
				u.tick_visual(_delta, frame)
	else:
		var n: int = _live_units.size()
		var i: int = frame % shards
		var d: float = _delta * float(shards)
		while i < n:
			var u = _live_units[i]
			if is_instance_valid(u) and u.is_processing():
				u.tick_visual(d, frame)
			i += shards
	if _meter: _Opt.vis_add(Time.get_ticks_usec() - _vm0)
	far_units.flush()
	sel_decals.flush()
	# Звёзды ветеранства едут за центрами масс отрядов (см. _update_squad_stars).
	# Стоит ПОСЛЕ тика бойцов: позиции за этот кадр уже окончательные
	_update_squad_stars()

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

func register_unit(u: Unit) -> void:
	_live_units.append(u)

func unregister_unit(u: Unit) -> void:
	_live_units.erase(u)

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
	# КОРИДОР ОТРЯДА — ОДИН РАЗ НА ОТРЯД, А НЕ НА БОЙЦА (см. _sweep_corridors)
	if _prof: _t0 = Time.get_ticks_usec()
	_sweep_corridors()
	if _prof: _Opt.prof_add("squad_corridor", Time.get_ticks_usec() - _t0)
	if _prof: _t0 = Time.get_ticks_usec()
	# ── ЧЕРЕДОВАНИЕ ПО КАДРАМ (см. perf_config.shards_for) ──────────────────
	# Кадр держит работа в ОДНОМ кадре, а не за секунду. Пока армия невелика,
	# shards == 1 и это ровно прежний цикл; на пяти тысячах армия делится
	# надвое, и каждый боец опрашивается через кадр — с удвоенной delta, так
	# что путь, откаты ударов и таймеры остаются те же
	var shards: int = _Opt.shards_for(_live_units.size())
	if shards <= 1:
		for u in _live_units:
			if is_instance_valid(u) and u.is_physics_processing():
				u.tick_physics(delta)
	else:
		var n: int = _live_units.size()
		var i: int = Engine.get_physics_frames() % shards
		var d: float = delta * float(shards)
		while i < n:
			var u = _live_units[i]
			if is_instance_valid(u) and u.is_physics_processing():
				u.tick_physics(d)
			i += shards
	if _prof: _Opt.prof_add("!ВЕСЬ ТИК ЮНИТОВ", Time.get_ticks_usec() - _t0)
	if _meter: _Opt.tick_add(Time.get_ticks_usec() - _tm0)
	# Спящий (_proc_sleeping) дальний юнит не крутит свой _process и потому сам
	# не заметит, что камера подошла и он снова near_view — например, игрок
	# подводит камеру к стоящему на месте вражескому гарнизону. Реестр дальних
	# мал (только то, что сейчас в MultiMesh), обход раз в FAR_WAKE_CHECK_FRAMES
	# дешёвый и достаточно частый, чтобы не быть заметным
	if Engine.get_physics_frames() % FAR_WAKE_CHECK_FRAMES == 0:
		_wake_returned_far_units()
	# Метки выделения едут за своими бойцами. Раньше это делало дерево сцены
	# (кольцо и тень были детьми юнита), теперь — один проход по выделенным;
	# неподвижных он пропускает
	sel_decals.update_all()

const FAR_WAKE_CHECK_FRAMES := 15

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

## sid -> [время истечения, чисто от стволов, чисто от врагов]
var _corridors: Dictionary = {}

func _sweep_corridors() -> void:
	if squads.is_empty():
		return
	var now: int = Time.get_ticks_msec()
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
	# ПЕРВЫЙ ПРОХОД — ЕДИНСТВЕННЫЙ, КТО ТРОГАЕТ ОБЪЕКТЫ. Раньше проходов по
	# членам отряда было три (центр, радиус, раздача), и каждый заново
	# проверял ссылку, звал is_dead() и читал свойство global_position — на
	# сотне отрядов это тысячи обращений наружу в кадр. Теперь координаты
	# снимаются один раз в плоский массив чисел, радиус считается по нему
	# чистой арифметикой, а раздача идёт по уже отобранным живым
	var n := 0
	var cx := 0.0
	var cz := 0.0
	var fac := 0
	# ДАЛЬНОСТЬ ВНИМАНИЯ ОТРЯДА. Ответ «чужих рядом нет» отменяет НЕ ТОЛЬКО
	# блокировку строем (BLOCK_RADIUS, меньше метра), но и оба скана врага —
	# перехват марша и авто-агро. У лучника они смотрят на 20 м, поэтому
	# радиус проверки обязан накрывать самый дальнозоркий взгляд в отряде,
	# иначе отряд «ослепнет» ровно там, где раньше стрелял
	var watch := 0.0
	var live: Array = []
	var xz := PackedFloat32Array()
	for m in members:
		var u := m as Unit
		# state вместо is_dead(): тот же ответ, но без вызова наружу —
		# в этом цикле он делался на каждого бойца каждого отряда
		if u == null or not is_instance_valid(u) or u.state == Unit.State.DEAD:
			continue
		var p := u.global_position
		cx += p.x
		cz += p.z
		xz.append(p.x)
		xz.append(p.z)
		live.append(u)
		fac = u.faction
		var w: float = maxf(Unit.AGGRO_RADIUS, u.attack_range) + Unit.INTERCEPT_MARGIN
		if w > watch:
			watch = w
		n += 1
	if n == 0:
		_corridors.erase(sid)
		return
	cx /= float(n)
	cz /= float(n)
	var r2 := 0.0
	for i in range(n):
		var dx: float = xz[i * 2] - cx
		var dz: float = xz[i * 2 + 1] - cz
		var d2: float = dx * dx + dz * dz
		if d2 > r2:
			r2 = d2
	var radius: float = sqrt(r2) + CORRIDOR_MARGIN
	# Стволы мешают только телу бойца — их достаточно искать по габаритам;
	# чужих ищем на всю дальность внимания отряда.
	var clear_trunk: bool = not trunk_near(cx, cz, radius)
	var clear_enemy: bool = not unit_grid.enemy_near(
		Vector3(cx, 0.0, cz), fac, radius + watch)
	_corridors[sid] = [now + CORRIDOR_TTL_MS, clear_trunk, clear_enemy]
	_push_corridor(live, clear_trunk, clear_enemy)

## `members` здесь — уже отобранные живые бойцы (см. _recalc_corridor):
## повторно проверять ссылку не нужно, между двумя строками никто не умирает
func _push_corridor(members: Array, clear_trunk: bool, clear_enemy: bool) -> void:
	for u in members:
		u._clear_trunk = clear_trunk
		u._clear_enemy = clear_enemy

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

func on_selection_changed(units: Array) -> void:
	if main and main.has_method("on_selection_changed"):
		main.on_selection_changed(units)

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
		"star": null,      # узел звёздочки (висит на командире)
		# ── РАЗМЕТКА СТРОЯ (см. squad_set_formation) ──
		"slots": [],              # точки построения, по шеренгам от передовой
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
	if not squads.has(sid):
		# Отряд уже расформирован, а боец унёс его номер. Чистим: иначе висячий
		# id мог бы совпасть с номером ЧУЖОГО отряда, выданным позже
		unit.squad_id = 0
		return
	var members: Array = squads[sid]["members"]
	members.erase(unit)
	unit.squad_id = 0
	if members.is_empty():
		squads.erase(sid)
		return
	# Звезда висит в МИРЕ по центру масс (см. refresh_star), а не на командире,
	# поэтому гибель бойца её больше не уносит. Освобождённый узел всё же
	# подчищаем — на него могли сослаться извне
	var star = squads[sid]["star"]
	if star != null and not is_instance_valid(star):
		squads[sid]["star"] = null
		refresh_star(sid)

## Живые бойцы отряда (пустой массив — отряда нет). Заодно чистит битые ссылки.
func squad_members(squad_id: int) -> Array:
	if not squads.has(squad_id):
		return []
	var members: Array = squads[squad_id]["members"]
	var alive: Array = []
	for m in members:
		if is_instance_valid(m) and not m.is_dead():
			alive.append(m)
	if alive.size() != members.size():
		squads[squad_id]["members"] = alive
	if alive.is_empty():
		squads.erase(squad_id)
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

## Снять разметку: отряд получил приказ, не связанный со строем (атака, гарнизон)
func squad_clear_formation(sid: int) -> void:
	if sid <= 0 or not squads.has(sid):
		return
	(squads[sid] as Dictionary)["slots"] = []

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
	squads.clear()
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
const _VetStar := preload("res://scripts/VeterancyStar.gd")

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
	refresh_star(sid)

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
	var stat: String  = String(c.get("stat", ""))
	var value: float  = float(c.get("value", 0.0))
	var sq: Dictionary = squads[squad_id]
	var b: Dictionary = sq["bonuses"]
	b[stat] = float(b.get(stat, 0.0)) + value
	(sq["chosen"] as Array).append(String(c.get("id", stat)))
	sq["pending"] = int(sq["pending"]) - 1
	for m in squad_members(squad_id):
		_apply_bonus_to_unit(m, stat, value)
	refresh_star(squad_id)
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
## поэтому родителем стал мир, а положение обновляет _update_squad_stars()
## с частотой 10 Гц (см. STAR_UPDATE_FRAMES).
func refresh_star(squad_id: int) -> void:
	if not squads.has(squad_id):
		return
	var sq: Dictionary = squads[squad_id]
	var lvl: int = int(sq["level"])
	var star = sq["star"]
	var members := squad_members(squad_id)
	if lvl <= 0 or members.is_empty():
		if star != null and is_instance_valid(star):
			star.queue_free()
		sq["star"] = null
		return
	if star != null and is_instance_valid(star):
		# Уже висит. Но отряд мог подрасти в звании: тогда ряд звёзд надо
		# ПЕРЕСТРОИТЬ, иначе на пятом уровне так и висела бы одна звезда
		if int(star.shown_level) != lvl:
			star.build(lvl)
		_place_star(star, members)
		return
	var host: Node = main if main != null and is_instance_valid(main) else null
	if host == null:
		# Мира ещё нет (стенд поднимает отряды до сцены) — попробуем в следующий раз
		return
	var fresh: MeshInstance3D = _VetStar.create(lvl)
	host.add_child(fresh)
	sq["star"] = fresh
	_place_star(fresh, members)

## Центр масс отряда — СРЕДНЕЕ координат всех выживших, без весов.
## Публичный: тем же числом пользуется HUD (карточка отряда) и стенды
func squad_centroid(squad_id: int) -> Vector3:
	var members := squad_members(squad_id)
	if members.is_empty():
		return Vector3.ZERO
	var acc := Vector3.ZERO
	for m in members:
		acc += (m as Node3D).global_position
	return acc / float(members.size())

## Поставить узел звезды над центром масс переданного состава
func _place_star(star: Node3D, members: Array) -> void:
	if star == null or not is_instance_valid(star) or members.is_empty():
		return
	var acc := Vector3.ZERO
	for m in members:
		acc += (m as Node3D).global_position
	var c: Vector3 = acc / float(members.size())
	# Высоту берём у РЕЛЬЕФА под центром, а не у случайного бойца: центр масс
	# может прийтись на точку, где никто не стоит (отряд обтекает дерево)
	star.global_position = Vector3(c.x,
		get_terrain_height(c.x, c.z) + _VetStar.STAR_HEIGHT, c.z)

## Как часто пересчитывать центры масс. 6 кадров ≈ 10 Гц: звезда не участвует
## в прицеливании, её достаточно двигать «на глаз», а обход отрядов со всеми
## их бойцами каждый кадр был бы честной прибавкой к кадру в массовом бою
const STAR_UPDATE_FRAMES := 6
var _star_tick: int = 0

## Двигать звёзды за отрядами. Вызывается из _process ПОСЛЕ тика бойцов
func _update_squad_stars() -> void:
	_star_tick += 1
	if _star_tick < STAR_UPDATE_FRAMES:
		return
	_star_tick = 0
	for key in squads.keys():
		var sq: Dictionary = squads[key]
		var star = sq.get("star", null)
		if star == null or not is_instance_valid(star):
			continue
		_place_star(star, squad_members(int(key)))

# ─────────────────────────────────────────────────────────────────────────────
# СТРОЙКА РАБОЧИМ
# Кнопка на панели рабочего → режим размещения → фундамент → рабочий бежит
# к нему с молотком → по готовности фундамент подменяется зданием.
# Ресурсы списываются В МОМЕНТ РАЗМЕЩЕНИЯ, отмена размещения их возвращает
# (см. Main._placing_refund) — правило то же, что и у постройки из замка.
# ─────────────────────────────────────────────────────────────────────────────
const _CSite := preload("res://scripts/ConstructionSite.gd")

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
		var grp := "player_buildings" if worker.faction == Constants.FACTION_PLAYER else "enemy_buildings"
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
	var grp := "player_buildings" if castle.faction == Constants.FACTION_PLAYER else "enemy_buildings"
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
const OBST_CELL := 4.0

var _trunks: Dictionary = {}          # Vector2i -> Array[Vector3(x, z, r)]


## Самый толстый комель из поставленных на учёт. Нужен trunk_block, чтобы
## сузить обход до реально досягаемых клеток: дерево лежит в СВОЕЙ клетке, но
## дотянуться до нас может из соседней на величину своего радиуса. Только
## растёт — стволы все одного калибра (ResourceNode.TRUNK_RADIUS), и терять
## запас на пересчёт при вырубке незачем
var _trunk_max_r: float = 0.0

func _trunk_cell(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / OBST_CELL)), int(floor(z / OBST_CELL)))

## Поставить ствол на учёт. Зовёт ResourceNode при появлении дерева
func register_trunk(pos: Vector3, radius: float) -> void:
	var key := _trunk_cell(pos.x, pos.z)
	if not _trunks.has(key):
		_trunks[key] = []
	(_trunks[key] as Array).append(Vector3(pos.x, pos.z, radius))
	_trunk_max_r = maxf(_trunk_max_r, radius)

## Снять с учёта: дерево срублено (пень не мешает) либо выгружено
func unregister_trunk(pos: Vector3) -> void:
	var key := _trunk_cell(pos.x, pos.z)
	if not _trunks.has(key):
		return
	var arr: Array = _trunks[key]
	for i in range(arr.size()):
		var t: Vector3 = arr[i]
		if absf(t.x - pos.x) < 0.01 and absf(t.y - pos.z) < 0.01:
			arr.remove_at(i)
			return

func clear_trunks() -> void:
	_trunks.clear()
	_trunk_max_r = 0.0

## Сколько стволов на учёте (для стендов)
func trunk_count() -> int:
	var n := 0
	for k in _trunks:
		n += (_trunks[k] as Array).size()
	return n

## Наталкивается ли точка на ствол. Возвращает вектор ОТ центра ствола к точке,
## длиной в глубину проникновения; Vector3.ZERO — путь свободен.
## ГОРЯЧИЙ ПУТЬ: зовётся на каждый шаг каждого юнита — без аллокаций и
## обращений наружу
## ЕСТЬ ЛИ ХОТЬ ОДИН СТВОЛ В РАДИУСЕ. Грубый ответ для коридора отряда
## (см. _recalc_corridor): проверяем только НЕПУСТЫЕ клетки, до содержимого
## доходим лишь тогда, когда клетка вообще существует. Радиус здесь десятки
## метров, поэтому клеток может быть много — но зовётся это раз в 0.2 с на
## отряд, а не 60 раз в секунду на бойца
func trunk_near(x: float, z: float, radius: float) -> bool:
	if _trunks.is_empty():
		return false
	var reach: float = radius + _trunk_max_r
	var inv: float = 1.0 / OBST_CELL
	var cx0: int = int(floor((x - reach) * inv))
	var cz0: int = int(floor((z - reach) * inv))
	var cx1: int = int(floor((x + reach) * inv))
	var cz1: int = int(floor((z + reach) * inv))
	var lim: float = reach * reach
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var cell: Variant = _trunks.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for t in (cell as Array):
				var tv: Vector3 = t
				var dx: float = x - tv.x
				var dz: float = z - tv.y
				if dx * dx + dz * dz < lim:
					return true
	return false

func trunk_block(x: float, z: float, body_r: float) -> Vector3:
	if _trunks.is_empty():
		return Vector3.ZERO
	# ОБХОДИМ ТОЛЬКО ТЕ КЛЕТКИ, ДО КОТОРЫХ РЕАЛЬНО ДОТЯГИВАЕМСЯ. Раньше здесь
	# стояли жёсткие 3×3 вокруг точки — девять словарных поисков на каждый шаг
	# каждого бойца. Но клетка тут 4 м, а тело вместе с комлем — меньше метра:
	# соседняя клетка нужна, только когда боец стоит вплотную к её границе.
	# По диапазону [x-r, x+r] почти всегда выходит ровно одна клетка, у границы
	# две, и лишь в углу четыре — вместо девяти всегда
	var reach: float = body_r + _trunk_max_r
	# Ключи клеток считаем ЗДЕСЬ, а не через _trunk_cell: два вызова
	# GDScript-функции на каждый шаг каждого бойца ради двух делений
	var inv: float = 1.0 / OBST_CELL
	var cx0: int = int(floor((x - reach) * inv))
	var cz0: int = int(floor((z - reach) * inv))
	var cx1: int = int(floor((x + reach) * inv))
	var cz1: int = int(floor((z + reach) * inv))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			# Пустую ячейку пропускаем БЕЗ аллокации: `get(key, [])` создавал
			# новый пустой Array на каждую из девяти ячеек на каждый шаг каждого
			# юнита (замер: ветка mb_trunk — 2.4 мкс на юнита в кадр)
			var cell: Variant = _trunks.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for t in (cell as Array):
				var tv: Vector3 = t
				var dx: float = x - tv.x
				var dz: float = z - tv.y
				var rr: float = tv.z + body_r
				var d2: float = dx * dx + dz * dz
				if d2 >= rr * rr:
					continue
				if d2 < 1e-8:
					# РОВНО В ЦЕНТРЕ СТВОЛА направление «наружу» не определено.
					# Молча пропускать нельзя: точка внутри дерева считалась бы
					# свободной. Выталкиваем в произвольную, но постоянную
					# сторону — лишь бы вывести наружу
					return Vector3(rr, 0.0, 0.0)
				var d: float = sqrt(d2)
				return Vector3(dx / d, 0.0, dz / d) * (rr - d)
	return Vector3.ZERO

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

func update_view_point(pos: Vector3) -> void:
	_view_x = pos.x
	_view_z = pos.z
	_view_r2 = _Opt.lod_radius * _Opt.lod_radius

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
