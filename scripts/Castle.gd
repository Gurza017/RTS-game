extends Building
class_name Castle

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Roof := preload("res://scripts/RoofGarrison.gd")

## ── ГАРНИЗОН НА КРЫШЕ (ТЗ 14.09.2026) ─────────────────────────────────────
## Стрелковые отряды, вошедшие в здание, стоят НА КРЫШЕ: видны, стреляют с
## баффом высоты, ловят стрелы противника — общий модуль RoofGarrison для
## башни, бараков и крепости. Крепость держит два отряда на крыше сверх
## обычного лазарета для прочих родов; башня и бараки — по одному, только
## лучников. Хозяин задаёт раскладку через _roof_setup(); null — крыши нет
var _roof = null

func _roof_setup():
	# Крепость: 30 на настиле в центре, по 15 на башнях по краям
	var r = _Roof.new()
	r.setup(self, _Roof.LAYOUT_KEEP, int(_UCfg.ROOF_VISIBLE.get("castle", 60)),
		float(_UCfg.ROOF_FOOT_FRAC.get("castle", 0.66)), _UCfg.CASTLE_FLANK_FOOT_FRAC)
	return r

## Сколько стрелковых отрядов помещается на крышу
func roof_squads_max() -> int:
	return int(_UCfg.ROOF_SQUADS.get(building_id, 0))

## Отряд этого рода войск садится НА КРЫШУ (а не в лазарет)
func roof_accepts(unit_type: String) -> bool:
	return _roof != null and unit_type == "archer" and roof_squads_max() > 0

func has_roof_garrison() -> bool:
	return _roof != null and _roof.squad_id() > 0

## ── ПРЯМОЙ ПРИКАЗ ГАРНИЗОНУ КРЫШИ (ТЗ 19.09.2026) ─────────────────────────
## Здание выделено, ПКМ по чужому отряду или постройке — весь стрелковый
## гарнизон переносит огонь на цель (RoofGarrison.order_fire). false — крыши
## нет, на ней пусто или цель не годится (своя, ничейная, мёртвая)
func order_roof_fire(target: Node3D) -> bool:
	if _roof == null or _roof.squad_id() <= 0:
		return false
	return bool(_roof.order_fire(target))

## Ручная цель гарнизона (null — авто-агро)
func roof_manual_target():
	return _roof.manual_target() if _roof != null else null

## Выпустить всех с крыши (ПКМ пустым выделением / кнопка). false — пусто
func release_roof() -> bool:
	if _roof == null:
		return false
	return bool(_roof.release_all())

const GLB_PATH    := "res://assets/models/castle.glb"
const MODEL_SCALE := 1.0

const GOLD_INCOME   := 5.0
const GOLD_INTERVAL := 10.0

var _gold_timer: float = 0.0

func _ready() -> void:
	_configure()
	_roof = _roof_setup()
	super._ready()

## ── НАСТРОЙКА ПОЛЕЙ ВЫНЕСЕНА ИЗ _ready() РАДИ НАСЛЕДНИКОВ ──────────────────
## Хижина гоблинов наследует Замок ради его гарнизона (принять, спрятать,
## лечить, доукомплектовать, выпустить), но она не замок: у неё своя картинка,
## свой запас жизни и нет склада. GDScript не умеет звать метод «через голову»
## родителя — наследник не может вызвать Building._ready(), минуя Castle._ready().
## Поэтому всё, что наследник обязан заменить, живёт в отдельном методе, а
## _ready() остаётся общим для обоих
func _configure() -> void:
	building_id  = "castle"
	sprite_path  = "res://assets/sprites/buildings/castle.png"
	# Запас жизни и габарит — из единого конфига (BUILDINGS["castle"])
	max_health   = _UCfg.building_stat("castle", "max_hp", 800.0)
	build_size   = _UCfg.building_size("castle", Vector3(8.0, 6.0, 8.0))
	is_dropoff   = true
	display_name = String(_UCfg.building_cfg("castle").get("name", "Замок"))
	squad_size   = 1
	squad_cols   = 4
	squad_spacing = 0.35
	spawn_offset = Vector3(0.0, 0.0, GATE_DISTANCE)

# ─────────────────────────────────────────────────────────────────────────────
# ВОРОТА — ТАМ, ГДЕ ОНИ НАРИСОВАНЫ
#
# ИСТОРИЯ ЭТОГО МЕСТА, ПОТОМУ ЧТО ОНА ПОУЧИТЕЛЬНА. Сначала spawn_offset был
# прибит к (0, 0, +6.5) — жёстко на юг в мировых осях; для замка ИИ, стоящего
# в противоположном углу, это направление ПРОЧЬ от противника, и каждый отряд
# уходил в тыловой лес («войска застревают в лесу за крепостью»). Лечение —
# «ворота к середине карты» (front_dir) — сняло тот симптом и завело новый:
# картинка замка прибита фасадом к мировому +Z и от положения на карте не
# зависит, поэтому ворота уезжали в сторону от НАРИСОВАННОЙ надвратной башни,
# и отряд выходил из угла здания.
#
# Оба раза чинили НАПРАВЛЕНИЕ, тогда как правильный ответ — не направление, а
# ПРИВЯЗКА: ворота стоят там, где они нарисованы, то есть у фасада (+Z), и
# теперь это выражено узлом SpawnPoint (см. Building), а не формулой.
#
# Считается ЛЕНИВО, в момент использования: позиция замка задаётся уже ПОСЛЕ
# add_child(), и в _ready() её ещё нет.
# ─────────────────────────────────────────────────────────────────────────────
const GATE_DISTANCE := 6.5

## У ЗАМКА ОТ БАЗОВОГО ПОВЕДЕНИЯ ОТЛИЧАЕТСЯ ТОЛЬКО ВЫНОС ВОРОТ.
## Направление задаёт нарисованный фасад (Building.facade_dir), а не положение
## замка на карте: правило «фасад к середине карты» здесь и было ошибкой —
## картинка замка прибита к мировому +Z, и ворота уезжали от неё в сторону
## ── НО НЕ ДАЛЬШЕ ПЕРИМЕТРА РИСУНКА (разбор — в Building.gate_depth) ────────
## GATE_DISTANCE выведен из коробки замка (8 м), а нарисован он на 8.66 м в
## ширину, то есть полуширина рисунка 4.33 — на два метра ближе. Отряд честно
## возникал за кольцом, на пустой траве
## …И НЕ ДАЛЬШЕ GATE_MAX_DEPTH ОТ СТЕНЫ (спринт 19, письмо 9): у замка
## рисунок 8.66 м в ширину, и ворота по нему стояли в 4.8 м от центра —
## «точка появления далеко от стены» на скриншоте владельца
func gate_depth() -> float:
	var d: float = GATE_DISTANCE
	if _draw_half_w >= 0.0:
		d = minf(GATE_DISTANCE, _draw_half_w + GATE_CLEARANCE)
	return minf(d, GATE_MAX_DEPTH + GATE_CLEARANCE)

# ═════════════════════════════════════════════════════════════════════════════
# ГАРНИЗОН: ПОПОЛНЕНИЕ И ЛЕЧЕНИЕ ОТРЯДОВ
# ═════════════════════════════════════════════════════════════════════════════
# Отряд, отправленный в Замок, заходит внутрь и пропадает с карты. Там ему
# лечат раненых и МЕДЛЕННО восстанавливают погибшие модели, пока отряд снова
# не станет полным (до unit_stats_config.squad_size).
#
# Числа — в конфиге: GARRISON_SQUAD_LIMIT / GARRISON_HEAL_PER_SEC /
# GARRISON_REVIVE_SECONDS / GARRISON_ENTER_RADIUS.
#
# Записи: {"sid": int, "type": String, "revive": float}
var garrison: Array = []          # отряды ВНУТРИ замка
var _incoming: Array = []         # отряды, которые ещё идут ко входу

## ── БОЕЦ ИСЧЕЗАЕТ У ДВЕРЕЙ, А НЕ ЗА ПЯТЬ МЕТРОВ ДО НИХ ──────────────────────
## Жалоба владельца со скриншотом: «точка входа находится не у ворот крепости, а
## сильно ниже — прямо в чистом поле».
##
## Так и было по арифметике. Ворота стоят на переднем крае НАРИСОВАННОГО
## основания (Building.gate_depth, у замка это 5.23 м от центра), а зачисление
## внутрь шло по допуску GARRISON_ENTER_RADIUS = 5 м ВОКРУГ ворот. Отряд идёт с
## поля, то есть подходит с дальней стороны, — значит боец пропадал с экрана,
## едва оказавшись в 10 м от центра замка, метрах в пяти от его нарисованного
## края. Замер (зонд qa_keep): нарисованная точка вошедшего — (−90, 99) при
## замке в (−90, 90) и воротах в (−90, 95.2).
##
## РАДИУС ДВЕРЕЙ ВЫВЕДЕН, А НЕ ПОДОБРАН. До самой точки ворот доходит только
## ГОЛОВА очереди — остальных держит разбор наложения, — а голове хватает
## допуска прибытия плюс пары строевых интервалов. Очередь при этом не
## застаивается: вошедший освобождает место следующему тем же кадром.
func _door_radius() -> float:
	return Unit.ARRIVE_RADIUS + squad_spacing * 2.0

## ── НО СТОЯТЬ У ДВЕРЕЙ ВЕЧНО НИКТО НЕ ОБЯЗАН ────────────────────────────────
## Тугой радиус — это про КАРТИНКУ, и платить за неё зависшим отрядом нельзя.
## Отставший, которого не пускает к воротам чужая толпа, ствол или собственный
## обоз, через DOOR_PATIENCE секунд зачисляется по прежнему, широкому допуску из
## конфига. То есть GARRISON_ENTER_RADIUS не отменён — он стал СТРАХОВКОЙ, а не
## обычным путём, и мягкой блокировки, от которой тут однажды уже лечились
## (см. «ПРИХОД СЧИТАЕТСЯ ОТ ВОРОТ» ниже), не возвращается
const DOOR_PATIENCE := 8.0

## Когда отряд встал в очередь ко входу, ticks_msec. Ключ — sid
var _incoming_at: Dictionary = {}

func _enter_radius(squad_id: int) -> float:
	var door: float = minf(_door_radius(), _UCfg.GARRISON_ENTER_RADIUS)
	var since: Variant = _incoming_at.get(squad_id)
	if since == null:
		return door
	if float(Time.get_ticks_msec() - int(since)) * 0.001 < DOOR_PATIENCE:
		return door
	return _UCfg.GARRISON_ENTER_RADIUS

## ── РУЧКИ ГАРНИЗОНА, КОТОРЫЕ ПЕРЕОПРЕДЕЛЯЕТ НАСЛЕДНИК ──────────────────────
## Башня (Tower.gd) принимает только лучников, один отряд и не выпускает
## вылеченных сама. Развилок `if building_id == "tower"` внутри замка нет
## намеренно: у каждого наследника свой ответ, а замок о них не знает

## Сколько отрядов помещается внутрь
func garrison_limit() -> int:
	return _UCfg.GARRISON_SQUAD_LIMIT

## Годится ли отряд этого рода войск
func garrison_accepts(_unit_type: String) -> bool:
	return true

## Выходит ли вылеченный и полный отряд сам
func _auto_release() -> bool:
	return _UCfg.GARRISON_AUTO_RELEASE

## КРЕПОСТЬ ЛИ ЭТО. Замок и хижина орды — да; башня — нет. Спрашивают все,
## кому «замок» значит «столица»: зона застройки, кнопка «в замок», условие
## поражения, точка базы у ИИ. Проверка `is Castle` там больше не годится
func is_stronghold() -> bool:
	return true

## ── ОБЗОР КРЕПОСТИ ШИРЕ ОБЫЧНОГО ДОМА (заказ владельца 10.09.2026) ────────
## Башня переопределяет это своим TOWER_VISION, хижина орды — наследует
## крепостной: у неё та же роль центра базы
func vision_radius() -> float:
	return _UCfg.CASTLE_VISION

## Отправить отряд в Замок. false — гарнизон полон или отряд не годится
func request_garrison(squad_id: int) -> bool:
	if squad_id <= 0:
		return false
	if _slot_of(squad_id) >= 0 or _incoming.has(squad_id):
		return true                        # уже идёт или уже внутри
	if garrison.size() + _incoming.size() >= garrison_limit():
		return false
	var utype: String = GameManager.squad_type(squad_id)
	if not garrison_accepts(utype):
		return false
	# Крыша вмещает ограниченное число стрелковых отрядов (ТЗ 14.09.2026)
	if roof_accepts(utype) and _roof.squads() >= roof_squads_max():
		return false
	var members := GameManager.squad_members(squad_id)
	if members.is_empty():
		return false
	_incoming.append(squad_id)
	_incoming_at[squad_id] = Time.get_ticks_msec()
	# РАЗМЕТКА СТРОЯ СНИМАЕТСЯ: отряд отходит, а не марширует квадратом, и
	# смыкание рядов по дороге к воротам только тормозило бы его
	GameManager.squad_clear_formation(squad_id)
	# Отряд идёт ко входу в РЕЖИМЕ ОТХОДА: без стойки, без цели, без перехвата
	# и сквозь чужие строи (см. Unit.begin_retreat)
	var gate := _gate_position()
	for m in members:
		var u := m as Unit
		u.begin_retreat()
		u.command_move(gate, false, Vector3.ZERO, true)
	set_process(true)
	return true

## ПОСАДИТЬ ОТРЯД ВНУТРЬ СРАЗУ, БЕЗ МАРША К ВОРОТАМ (15.09.2026).
## Для стартовой расстановки: башни и крыша крепости красного ИИ выходят на
## карту уже с лучниками. Те же ворота, что у request_garrison (лимит, род
## войск, вместимость крыши), тот же absorb_unit и та же запись в garrison —
## отличие ровно одно: бойцы не идут ко входу, а зачисляются здесь и сейчас.
## false — не годится или места нет; отряд тогда остаётся на карте
func garrison_now(squad_id: int) -> bool:
	if squad_id <= 0 or _slot_of(squad_id) >= 0 or _incoming.has(squad_id):
		return false
	if garrison.size() + _incoming.size() >= garrison_limit():
		return false
	var utype: String = GameManager.squad_type(squad_id)
	if not garrison_accepts(utype):
		return false
	if roof_accepts(utype) and _roof.squads() >= roof_squads_max():
		return false
	var members := GameManager.squad_members(squad_id)
	if members.is_empty():
		return false
	GameManager.squad_clear_formation(squad_id)
	for m in members:
		absorb_unit(m as Unit)
	garrison.append({"sid": squad_id, "type": utype, "revive": 0.0})
	set_process(true)
	return true

## Индекс отряда в гарнизоне (-1 — его там нет)
func _slot_of(squad_id: int) -> int:
	for i in range(garrison.size()):
		if int((garrison[i] as Dictionary)["sid"]) == squad_id:
			return i
	return -1

## Убрать бойца с карты внутрь замка
func absorb_unit(u: Unit) -> void:
	if u == null or not is_instance_valid(u) or u.garrisoned:
		return
	u.garrisoned = true
	# ПРИНУДИТЕЛЬНО: отход кончился ПО ФАКТУ — боец у ворот, дальше идти некуда.
	# Обычный вызов отбился бы о замок времени (см. Unit.end_retreat)
	u.end_retreat(true)      # дошёл — режим отхода больше не нужен
	u.visible = false
	# ОБЯЗАТЕЛЬНО вместе с visible: картинка бойца — слот в общем MultiMesh, а он
	# не под узлом бойца и скрытием узла не гасится (см. Unit.leave_render)
	u.leave_render()
	# ЗДЕСЬ БЫЛО `u.collision_layer = 0`. У бойца больше нет физического тела
	# (Unit наследует Node3D, см. шапку Unit.gd), и присваивание валилось ошибкой
	# «Invalid assignment of property collision_layer» ПОСРЕДИ функции: всё, что
	# ниже, — снятие с тика, вычистка из сетки и из групп фракции — не
	# выполнялось вовсе. Отряд числился в замке, но продолжал жить на карте.
	u.set_draw(false)
	u.set_tick(false)
	# ── ВСЁ, ЧТО РИСУЕТСЯ НАД БОЙЦОМ, СНИМАЕТСЯ ВМЕСТЕ С НИМ ────────────────
	# Кольцо выделения, прицельная подсветка и полоска здоровья — это СЛОТЫ В
	# ОБЩИХ СЛОЯХ, а не дети узла: скрытием узла они не гаснут, а ездят по
	# НАРИСОВАННОЙ точке, которая у снятого с визуального тика бойца замерзает
	# навсегда. Разбор и замер — в GameManager.forget_on_map
	GameManager.forget_on_map(u)
	GameManager.unit_grid.remove(u)
	# Вне групп фракции боец не попадает ни в поиск целей, ни в подсчёты ИИ
	for g in Constants.UNIT_GROUPS.values():
		u.remove_from_group(String(g))
	u.state = Unit.State.IDLE
	u.global_position = global_position
	# ВНЕ КАРТЫ И ДЛЯ ЯДРА ТОЖЕ. GameManager.unit_grid — сетка GDScript, а цели
	# и стрелы ищут по СЕТКЕ ЯДРА (ArmyCore.FillGrid по живым строкам): без
	# снятия признака координаты вошедший оставался в ней на точке у ворот —
	# невидимый, но обстреливаемый (qa_tower B8в). Хозяин запоминается ради
	# переадресации урона (Unit.take_damage → absorb_damage_for)
	u.garrison_host = self
	u.set_off_map(true)

## Вернуть бойца на карту у ворот
func release_unit(u: Unit, at: Vector3) -> void:
	if u == null or not is_instance_valid(u) or not u.garrisoned:
		return
	u.garrisoned = false
	u.garrison_host = null
	u.visible = true
	# СТРОЙ НА ВЫХОДЕ НЕ ДОЛЖЕН ЛЕЧЬ В ОЗЕРО. Бойцы раскладываются по колоннам
	# и рядам от ворот (см. _release_members), и у замка на берегу часть слотов
	# приходится на воду. Поставленный в воду юнит ходьбой оттуда не выберется
	# сам — выносим точку выхода на сушу заранее
	var spot: Vector3 = GameManager.land_target(Vector3(at.x, 0.0, at.z))
	u.global_position = Vector3(spot.x, GameManager.get_terrain_height(spot.x, spot.z), spot.z)
	if u.faction == Constants.FACTION_PLAYER:
		u.add_to_group("player_units")
	else:
		u.add_to_group("enemy_units")
	u.set_draw(true)
	u.set_tick(true)
	# Слот в общей отрисовке выдаётся заново: пока боец сидел внутри, его там не было
	u.enter_render()
	# Строку ядра армии тоже надо поправить руками: бойца перенесли В ОБХОД тика
	# (см. Unit.sync_row), а по ней теперь считается и сетка соседей, и картинка
	u.sync_row()
	# Запас, подлеченный внутри (без пуша в ядро на каждый кадр), уезжает в
	# колонку hp один раз при выходе: монах ищет раненых по ней (14.09.2026)
	u._soa_push_stats()

## УДАР ПО УКРЫТОМУ БОЙЦУ ПРИНИМАЕТ ЗДАНИЕ (заказ владельца, 09.09.2026):
## запас жизни стен — единственное, что можно снести, пока гарнизон внутри.
## Броня бойца здесь не считается: здание её не имеет, а урон уже посчитан
## стрелком по своей формуле. Наследники (башня, хижина) получают то же
## правило без единой развилки
## Прямой удар по укрытому (снаряд, нацеленный до входа; брызги; вызов) —
## целиком в СТЕНЫ, минуя параллельный срез крыши: тот считается на стрелах,
## прилетевших ПО ЗДАНИЮ (Castle.take_damage), а не по бойцу внутри
func absorb_damage_for(_u: Unit, amount: float, attacker: Node3D = null) -> void:
	if is_dead() or amount <= 0.0:
		return
	last_hit_ms = Time.get_ticks_msec()
	super.take_damage(amount, attacker)

## Вытряхнуть наружу тех членов отряда, кто уже успел зайти внутрь, не трогая
## приказов тех, кто остался снаружи. Нужно при ОТМЕНЕ похода в замок: иначе
## вошедшие остаются внутри без записи в `garrison`, то есть навсегда
func _spill_absorbed(squad_id: int) -> void:
	var gate := _gate_position()
	var side := Vector3(-spawn_offset.z, 0.0, spawn_offset.x)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var out: Array = []
	# Куда идти вышедшим — считаем ДО выпуска, по тем, кто остался снаружи:
	# после выпуска они сами стоят у ворот и утянули бы среднее на замок
	var sum := Vector3.ZERO
	var n := 0
	for m in GameManager.squad_members(squad_id):
		var u := m as Unit
		if u == null or not is_instance_valid(u):
			continue
		if u.garrisoned:
			out.append(u)
		else:
			sum += u.global_position
			n += 1
	var to: Vector3 = (sum / float(n)) if n > 0 else gate
	for i in range(out.size()):
		var u: Unit = out[i]
		var off := side * ((float(i) - float(out.size() - 1) * 0.5) * squad_spacing)
		release_unit(u, gate + off)
		u.command_move(to + off, false, Vector3.ZERO)

## Выпустить отряд наружу. Возвращает false, если такого отряда внутри нет
func release_garrison(squad_id: int) -> bool:
	var idx := _slot_of(squad_id)
	if idx < 0:
		return false
	garrison.remove_at(idx)
	_release_members(squad_id)
	return true

## Вернуть бойцов отряда на карту и отправить их от ворот. Слот в garrison
## снимает ВЫЗЫВАЮЩИЙ — так авто-выход может убрать запись до обхода массива
func _release_members(squad_id: int) -> void:
	GameManager.squad_note_healed(squad_id)
	var gate := _gate_position()
	var exit_dir := spawn_offset
	exit_dir.y = 0.0
	exit_dir = exit_dir.normalized() if exit_dir.length() > 0.01 else Vector3.BACK
	# Уходят на точку сбора здания, если она назначена; иначе — от ворот
	var dest := gate + exit_dir * SQUAD_EXIT_DISTANCE
	if has_rally:
		dest = rally_point
		var course := dest - gate
		course.y = 0.0
		if course.length() > 0.01:
			exit_dir = course.normalized()
	var members := GameManager.squad_members(squad_id)
	# КВАДРАТ, а не полоса шириной в squad_cols замка: вылеченный отряд выходит
	# тем же строем, каким его нанимали (см. Building.square_cols)
	var cols: int = square_cols(members.size(), squad_cols)
	var side := Vector3(-exit_dir.z, 0.0, exit_dir.x)
	# ── РАЗМЕТКА ОТДАЁТСЯ ОТРЯДУ, А НЕ ТОЛЬКО РАЗДАЁТСЯ ПОШТУЧНО ────────────
	# Раньше каждый выпущенный получал свою точку, а САМ ОТРЯД оставался без
	# `slots`. Для GameManager это «отряд, которого никогда не строили»: смыкание
	# рядов такому синтезирует форму с нуля, а до первого боя он так и идёт
	# бесформенной кучей — ровно то, что видно на скриншоте выхода из замка
	var slots: Array = []
	for i in range(members.size()):
		var u: Unit = members[i]
		var col: int = i % cols
		var row: int = i / cols
		# Смещение считается в ОСЯХ ВЫХОДА, а не в мировых: иначе отряд,
		# выходящий на восток, разворачивал бы строй боком к направлению марша
		var off := side * ((float(col) - float(cols - 1) * 0.5) * squad_spacing) \
			+ exit_dir * (float(row) * squad_spacing)
		u.formation_row = row
		release_unit(u, gate + off)
		# ПРИКАЗ ПОЛУЧАЮТ ВСЕ ЧЛЕНЫ ОТРЯДА, а не только те, кто сидел внутри:
		# часть могла остаться снаружи (сбилась по дороге, отменённый вход), и
		# без общего приказа отряд остаётся разорванным на две кучки, а знамя
		# уезжает со знаменосцем в одну из них
		u.command_move(dest + off, false, exit_dir)
		slots.append(dest + off)
	GameManager.squad_set_formation(squad_id, slots, exit_dir, false)

# ═════════════════════════════════════════════════════════════════════════════
# ЗАМОК ПАЛ — ГАРНИЗОН ВЫХОДИТ ИЗ РУИН
# ═════════════════════════════════════════════════════════════════════════════
# ЧТО БЫЛО. Building._die() просто освобождал узел здания. Бойцы гарнизона при
# этом ЖИВЫ, но сняты со всего: невидимы, вне тика, вне групп фракции, вне
# сетки, и стоят в точке замка (см. absorb_unit). Здание исчезало — и они
# оставались невидимыми призраками навсегда: ни в бою, ни в подсчёте армии, ни
# на экране. Со стороны это и есть «юниты просто бесследно исчезают». Хуже того, отряд числился живым, и проверка победы его считала.
#
# ЧТО СТАЛО. Гарнизон честно вываливается наружу и продолжает драться. Из двух
# предложенных вариантов («успевают выбежать» / «гибнут в руинах») выбран
# первый: это защитники СВОЕЙ базы, они внутри лечились, а не прятались, и
# бесплатно удалять их — значит награждать нападающего за то, чего он не сделал.
# Кому выйти некуда (узел уже недействителен), тот и правда умирает.
#
# Отряды НА ПОДХОДЕ отменяются здесь же: их вели к воротам, которых больше нет,
# и без отмены они остались бы в режиме отхода, идущими в пустоту
func _die() -> void:
	if is_dead():
		return
	if is_stronghold():
		GameManager.tm_event("castle_fell", {"fac": int(faction)})
	_evacuate_on_death()
	super._die()

## Пассивное золото — только у столицы; бараки и башня наследуют Castle ради
## гарнизона, а не ради казны
func _gives_gold() -> bool:
	return is_stronghold()

## ── КТО ПОЛУЧАЕТ УРОН: ЛУЧНИК НА КРЫШЕ ИЛИ СТЕНЫ ───────────────────────────
## Дальний бой (чужие луки, башни) — в лучника на крыше: погиб — тело у
## подножия со стрелой, на его место встаёт резервист; ближний бой — только
## в стены. Разделитель — дальность оружия нападающего (MELEE_RANGE_MAX)
const MELEE_RANGE_MAX := 5.0
## Сколько стрел укрытие принимает на себя — статистика стендов (ТЗ 19.09.2026)
var roof_hits: int = 0
var roof_hit_damage: float = 0.0
func take_damage(amount: float, attacker: Node = null) -> void:
	if is_dead() or amount <= 0.0:
		return
	# Удар по замку отмечается ДО крыши (охрана ИИ читает «замок под ударом»)
	last_hit_ms = Time.get_ticks_msec()
	# ── ПАРАЛЛЕЛЬНЫЙ УРОН (ТЗ 19.09.2026, Parallel Damage Split) ─────────
	# Дальний бой по укреплению идёт ДВУМЯ РУСЛАМИ независимо: стены получают
	# полный (100 %) урон стрелы, и ТЕ ЖЕ стрелы бьют защитников на крыше со
	# срезом укрытия GARRISON_COVER_FRAC (0.5×). Прежнее «крыша приняла — стены
	# целы» снято: гарнизон гибнет медленнее, а здание ломается параллельно.
	# Ближний бой — только в стены, как и было
	if _roof != null and _ranged_attacker(attacker):
		var share: float = amount * _UCfg.GARRISON_COVER_FRAC
		if share > 0.0 and bool(_roof.absorb_ranged_hit(share, attacker)):
			roof_hits += 1
			roof_hit_damage += share
	super.take_damage(amount, attacker)

func _ranged_attacker(attacker: Node) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	var u := attacker as Unit
	if u == null:
		return attacker is Building
	return u.attack_range > MELEE_RANGE_MAX

func _evacuate_on_death() -> void:
	# Копия списка: release_unit/_release_members трогают состав по ходу
	var inside: Array = garrison.duplicate()
	garrison.clear()
	for rec in inside:
		var sid: int = int((rec as Dictionary).get("sid", 0))
		if sid <= 0:
			continue
		_release_members(sid)
	# Идущим ко входу отменяем отход: ворот больше нет, а режим отхода запрещает
	# им и драться, и получать перехват
	for s in _incoming:
		# У отряда «на подходе» часть бойцов уже могла зайти внутрь: их
		# выпускаем, иначе они останутся невидимыми в руинах — тот же случай,
		# что и при отмене похода
		_spill_absorbed(int(s))
		for m in GameManager.squad_members(int(s)):
			var u := m as Unit
			if u != null and is_instance_valid(u):
				# Ворот больше нет — отход отменяется принудительно: цели у него
				# не осталось, а замок времени держал бы бойца в бесполезном
				# режиме, где он не дерётся и не отвечает
				u.end_retreat(true)
	_incoming.clear()
	_incoming_at.clear()

## Сколько бойцов не хватает отряду до полного состава
func garrison_missing(squad_id: int) -> int:
	var t: String = GameManager.squad_type(squad_id)
	return maxi(_UCfg.squad_size(t) - GameManager.squad_members(squad_id).size(), 0)

func _process_garrison(delta: float) -> void:
	# 1) кто дошёл до ворот — принимаем внутрь
	var still: Array = []
	for s in _incoming:
		var sid: int = s
		var members := GameManager.squad_members(sid)
		if members.is_empty():
			continue
		var all_in := true
		var cancelled := false
		var gate := _gate_position()
		# ── ПРИХОД СЧИТАЕТСЯ ОТ ВОРОТ, А НЕ ОТ ЦЕНТРА ЗДАНИЯ ──────────────────
		# ЗДЕСЬ БЫЛ СОФТЛОК, И ОН БЫЛ ЧИСТО ГЕОМЕТРИЧЕСКИЙ. Бойца ведут в
		# _gate_position(), то есть на GATE_DISTANCE = 6.5 м от центра замка, а
		# зачисление внутрь проверялось по расстоянию ДО ЦЕНТРА с радиусом
		# GARRISON_ENTER_RADIUS = 5.0 м. Дойти до такой отметки, стоя на своей
		# законной точке, невозможно в принципе: 6.5 > 5.0 всегда.
		#
		# Дальше разворачивалась вся картина из отчёта: отряд встаёт у ворот,
		# `all_in` навсегда false, сторож ниже видит IDLE и ПЕРЕВЫДАЁТ приказ
		# идти к воротам — каждый кадр. Боец делает полшага, снова приходит,
		# снова IDLE. Со стороны это «бесконечно шагает на месте», а любой
		# приказ игрока затирается в следующем же кадре — «отряд выпал из
		# логики». Второй отряд вставал рядом ровно по той же причине.
		#
		# Теперь мерим расстояние до ТОЧКИ ВОРОТ — это и есть смысл «дошёл ко
		# входу», и проверка перестала зависеть от GATE_DISTANCE. Константа
		# конфига осталась тем, чем и называется: допуском вокруг входа
		for m in members:
			var u: Unit = m
			if u.garrisoned:
				continue
			if u.global_position.distance_to(gate) <= _enter_radius(sid):
				absorb_unit(u)
				continue
			all_in = false
			# ── СТОРОЖ: ОТРЯД ОБЯЗАН ДОЙТИ ────────────────────────────────────
			# Приказ на вход отдаётся ОДИН раз (request_garrison), и всё, что его
			# сбило по дороге, оставляло бойца стоять в поле навсегда: он числится
			# в _incoming, гарнизон ждёт его вечно, а сам он в IDLE и никем не
			# двигается (см. «ПРОСТАЯ ОСТАНОВКА» в шапке Unit.gd). Сбить может
			# что угодно — чужой приказ, снятый режим отхода, застревание на
			# стволе. Поэтому приказ ПЕРЕВЫДАЁТСЯ каждому, кто встал или потерял
			# режим отхода, пока не окажется внутри радиуса входа.
			# ИГРОК ВПРАВЕ ОТМЕНИТЬ ПОХОД В ЗАМОК. Прежнее условие «встал ИЛИ
			# потерял режим отхода» переотдавало приказ и тому, кого игрок
			# только что послал в другое место: обычный приказ снимает отход
			# (command_move без keep_retreat), и сторож немедленно возвращал
			# бойца к воротам. Отсюда «отряд не реагирует ни на что».
			#
			# Различаем два случая по СОСТОЯНИЮ: боец, который куда-то идёт или
			# дерётся без режима отхода, — это чужой приказ, поход в замок
			# отменяется целиком. Боец, который ПРОСТО ВСТАЛ, — это сбой по
			# дороге (упёрся в ствол, потерял приказ), его дожимаем
			if not u.retreating and u.state != Unit.State.IDLE:
				cancelled = true
				break
			if u.state == Unit.State.IDLE:
				u.begin_retreat()
				u.command_move(gate, false, Vector3.ZERO, true)
		if cancelled:
			# ── ОТМЕНА ВОЗВРАЩАЕТ УЖЕ ВОШЕДШИХ НАРУЖУ ───────────────────────
			# Здесь было «уже вошедшие остаются внутри», и это создавало
			# бойцов-призраков: отряд снят с очереди, в `garrison` он не попал
			# (all_in так и не наступило), значит выпустить его больше НЕКОМУ.
			# Половина отряда навсегда оставалась невидимой внутри — а вторая
			# половина ходила по карте. Отсюда и «отряд разорван на две кучки»,
			# и «бойцы бесследно исчезают при разрушении замка»: обход
			# _evacuate_on_death идёт по `garrison`, где их тоже нет.
			#
			# Выпускаем ТОЛЬКО сидящих внутри и НЕ трогаем приказы остальных:
			# отмену вызвал приказ игрока, и _release_members переписал бы его
			# всем членам отряда — то есть вернул бы отряд к воротам, от которых
			# игрок его только что увёл
			_spill_absorbed(sid)
			continue
		if all_in:
			garrison.append({"sid": sid, "type": GameManager.squad_type(sid), "revive": 0.0})
		else:
			still.append(sid)
	_incoming = still
	# Часы очереди держим ровно на тех, кто ещё идёт: вошедший и отменивший
	# поход обязаны начать отсчёт заново, если их пошлют в замок снова
	for sid_key in _incoming_at.keys():
		if not still.has(sid_key):
			_incoming_at.erase(sid_key)

	# 2) лечение и пополнение тех, кто уже внутри
	var keep: Array = []
	var release: Array = []
	for g in garrison:
		var rec: Dictionary = g
		var sid: int = int(rec["sid"])
		var members := GameManager.squad_members(sid)
		if members.is_empty():
			continue                       # отряд вымер — слот освобождается
		var healed := true
		for m in members:
			var u: Unit = m
			if u.current_health < u.max_health:
				u.current_health = minf(u.current_health
					+ _UCfg.GARRISON_HEAL_PER_SEC * delta, u.max_health)
			if u.current_health < u.max_health - 0.01:
				healed = false
		var missing: int = garrison_missing(sid)
		if missing > 0:
			rec["revive"] = float(rec["revive"]) + delta
			if float(rec["revive"]) >= _UCfg.GARRISON_REVIVE_SECONDS:
				rec["revive"] = 0.0
				_revive_one(sid, String(rec["type"]))
				missing = garrison_missing(sid)
		# АВТО-ВЫХОД: состав полон и все здоровы — отряду в замке делать нечего,
		# он сам выкатывается наружу. Иначе игрок обязан помнить про каждый
		# заведённый отряд и вручную щёлкать по слоту гарнизона
		# Отряд на крыше — это ПОСТ, а не лазарет: сам не выходит
		if _auto_release() and missing <= 0 and healed \
				and not roof_accepts(String(rec["type"])):
			release.append(sid)
			continue
		keep.append(rec)
	garrison = keep
	# Выпуск идёт ПОСЛЕ пересборки списка: release_garrison() сам ищет слот в
	# garrison, и трогать массив во время обхода нельзя
	for sid in release:
		_release_members(int(sid))

## Доукомплектовать отряд одной моделью. Новобранец сразу получает все
## ветеранские награды отряда — иначе пополнение было бы слабее ветеранов
func _revive_one(squad_id: int, unit_type: String) -> void:
	var scene: PackedScene = PRELOAD_SCENES.get(unit_type)
	if scene == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	var u: Unit = scene.instantiate()
	u.faction = faction
	parent.add_child(u)
	u.global_position = global_position
	GameManager.add_to_squad(squad_id, u)
	GameManager.apply_squad_bonuses_to(squad_id, u)
	absorb_unit(u)

# Замок игрока капает золото по таймеру — ему покадровый тик нужен всегда.
# Замок ИИ дохода не имеет, но с гарнизоном тоже обязан тикать
func _needs_tick() -> bool:
	return faction == Constants.FACTION_PLAYER \
		or not garrison.is_empty() or not _incoming.is_empty()

func _process(delta: float) -> void:
	super._process(delta)
	if not garrison.is_empty() or not _incoming.is_empty():
		_process_garrison(delta)
	if _roof != null:
		if not garrison.is_empty():
			_roof.tick(delta)
		elif _roof.shown() > 0:
			_roof.sync()
	if faction == Constants.FACTION_PLAYER and _gives_gold():
		_gold_timer += delta
		if _gold_timer >= GOLD_INTERVAL:
			_gold_timer = 0.0
			# Пассивный доход — тоже добыча: попадает в счётчик притока HUD
			ResourceManager.gather_resource(faction, Constants.RESOURCE_GOLD, GOLD_INCOME)

func _build_visual() -> void:
	# Форму попадания заводит база: её потом подгоняют под рисунок
	# (см. Building._add_pick_shape / _fit_pick_to_sprite)
	_add_pick_shape()

	if ResourceLoader.exists(GLB_PATH):
		var scene := load(GLB_PATH) as PackedScene
		if scene:
			var model := scene.instantiate()
			model.scale = Vector3.ONE * MODEL_SCALE
			add_child(model)
		else:
			_build_procedural_visual()
	else:
		_build_procedural_visual()

	# Маркер выделения общий для всех зданий (Cursor_04.png плашмя на земле)
	selection_ring = make_selection_marker()
	add_child(selection_ring)

func _build_procedural_visual() -> void:
	var fc    := Color(0.2, 0.35, 0.85) if faction == Constants.FACTION_PLAYER else Color(0.75, 0.2, 0.2)
	var keep  := MeshInstance3D.new()
	var k_box := BoxMesh.new(); k_box.size = Vector3(4.0, 5.0, 4.0)
	var k_mat := StandardMaterial3D.new(); k_mat.albedo_color = Color(0.52, 0.50, 0.46); k_box.material = k_mat
	keep.mesh = k_box; keep.position.y = 2.5; add_child(keep)

	for corner in [Vector3(-3.5,0,-3.5), Vector3(3.5,0,-3.5), Vector3(-3.5,0,3.5), Vector3(3.5,0,3.5)]:
		var t  := MeshInstance3D.new()
		var tc := CylinderMesh.new(); tc.top_radius = 1.0; tc.bottom_radius = 1.0; tc.height = 5.5
		var tm := StandardMaterial3D.new(); tm.albedo_color = Color(0.48,0.46,0.42); tc.material = tm
		t.mesh = tc; t.position = corner + Vector3(0, 2.75, 0); add_child(t)

	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = fc; flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flag := MeshInstance3D.new()
	var fb   := BoxMesh.new(); fb.size = Vector3(0.8, 0.5, 0.08); fb.material = flag_mat
	flag.mesh = fb; flag.position = Vector3(0, 6.2, 0); add_child(flag)

# Цена, время и размер отряда — из конфига (TRAINING["castle"])
func train_worker() -> bool:
	return train_from_config("worker")

func train_warrior() -> bool:
	return train_from_config("warrior")

# Оставлены для совместимости с AI (enemy_castle.train_spearman())
func train_spearman() -> bool:
	return train_from_config("spearman")

func train_archer() -> bool:
	return train_from_config("archer")
