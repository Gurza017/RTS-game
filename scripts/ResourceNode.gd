extends StaticBody3D
class_name ResourceNode

const _BBUtil := preload("res://scripts/BillboardUtil.gd")

@export var resource_type: int = Constants.RESOURCE_WOOD
@export var remaining: float   = 200.0

# Для деревьев: 1-4 соответствует Tree1.png / Stump 1.png.
# Устанавливается снаружи ДО add_child(), 0 = случайный.
var tree_variant: int = 0
# Для золота/камня: вариант спрайта (золото 1-6 → «Gold Stone N.png»,
# камень 1-4 → «RockN.png»). 0 = случайный. Ставится ДО add_child().
var res_variant: int = 0
# Множитель размера: 1.0 — обычная жила, 1.6 — крупный самородок/валун,
# 0.65 — мелкий осколок. Позволяет собирать живописные кластеры.
var size_scale: float = 1.0

## ── НОМЕР КУЧИ, В КОТОРОЙ СТОИТ ЭТОТ КУСОК ───────────────────────────────────
## Куча (кластер) — это то, что игрок видит и на что показывает: полтора десятка
## самородков, лежащих вместе. Раньше её существование было чисто визуальным —
## куски рождались одной функцией и тут же теряли всякую связь друг с другом, а
## рабочий, выработав свой кусок, искал следующий ЧЕРЕЗ ВСЮ КАРТУ
## (Main.find_nearest_resource идёт по всей группе). Отсюда и «бригада внезапно
## ушла за горизонт»: ближайший по прямой кусок мог оказаться в чужой куче за
## озером, и это не было ошибкой поиска — самого понятия «моя куча» не было.
##
## Номер выдаёт Main._spawn_resource_cluster, он же кладёт габариты кучи в
## реестр (Main.cluster_bounds). 0 — одиночный узел вне кучи: так рождаются
## деревья, и для них «сосед» считается радиусом, а не номером
var cluster_id: int = 0

## ── КУЧА, КОТОРОЙ ЭТОТ КУСОК ПРИНАДЛЕЖИТ ─────────────────────────────────────
## MineCluster или null. У ЖИЛЫ В КУЧЕ (золото/камень) добыча, рабочие места и
## остаток живут НЕ ЗДЕСЬ, а в куче: сам кусок остаётся только картинкой и
## мишенью для клика. Всё, что ниже помечено «делегирует», перенаправляется туда.
##
## Тип намеренно НЕ указан. MineCluster объявляет class_name, но ссылаться на
## него аннотацией отсюда — значит завязаться на кэш глобальных классов, который
## в этом проекте уже ломал сборку (см. память проекта про
## global_script_class_cache). Поле выставляет Main._spawn_resource_cluster
var _mine = null

var mesh_instance: MeshInstance3D
var _visual_root: Node3D
## ── ДЕРЕВО РИСУЕТСЯ БЕЗ СОБСТВЕННОГО УЗЛА ───────────────────────────────────
## Место в общем MultiMesh растительности (см. VegetationRenderer). Только у
## деревьев со спрайтом: процедурное дерево, золото, камень и еда по-прежнему
## строят узлы — их немного, а у руды поверх лежат обрезка, блеск и подсветка
var _veg_slot = null
var _veg_tex: Texture2D = null
## Мировая точка, на которую посажено дерево. Дрожание рубки считается от неё
var _veg_base: Vector3 = Vector3.ZERO
## Высота квада дерева в метрах. Была локальной переменной tree_h в _build_tree;
## вынесена, потому что теперь ею же задаётся масштаб экземпляра
const TREE_HEIGHT := 5.0
var _max_remaining: float
var _stump_node: MeshInstance3D = null
var _shake_power: float = 0.0
var _shake_time: float  = 0.0
## Настоящая полуширина НАРИСОВАННОГО куска в метрах (не полуширина холста
## квада — там есть прозрачные поля). 0.0, пока _maybe_load_sprite() не
## отработал (дерево туда не заходит вовсе). См. slot_radius()
var _visual_half_width: float = 0.0
## Сколько кадров в ленте нарисованного спрайта (1 — статичная картинка).
## Заполняет _maybe_load_sprite; читает стенд пропорций
var sprite_frames_drawn: int = 1

func _ready() -> void:
	_max_remaining = remaining
	collision_layer = Constants.LAYER_RESOURCES
	collision_mask  = 0
	add_to_group("resource_nodes")
	_build_visual()
	_register_trunk()

## Дерево И жила золота/камня — препятствие: юниты обходят ствол/кусок руды,
## а не идут напролом (см. GameManager.register_trunk). Раньше это работало
## только у деревьев — collision_mask = 0 у всех ресурсов, поэтому по жилам
## можно было пройти насквозь, а отряды рассекали кучу камня как воздух.
## Куски внутри кучи стоят плотно (PIECE_MIN_GAP), поэтому уже одно только
## включение их в общий реестр стволов даёт кучу целиком непроходимой —
## отдельного "обстакла на кластер" заводить не нужно.
## Регистрация отложенная — позицию узлу задают уже ПОСЛЕ add_child, и в
## _ready она ещё нулевая
## ── МЕЛОЧЬ И СРЕДНИЕ КУСКИ РУДЫ БОЛЬШЕ НЕ ПРЕПЯТСТВИЕ ───────────────────────
## Заказ владельца: «по мелким/средним камням рабочие пусть просто проходят».
## Шестнадцать кусков в куче, каждый со своим обстаклом, — это лабиринт из
## полуметровых столбиков вплотную друг к другу; рабочий, обходящий один, тут же
## упирался в соседа и топтался у кромки вместо работы. Теперь непроходимы
## только КРУПНЫЕ куски (класс "big", scale 1.60): куча по-прежнему читается как
## препятствие и отряд сквозь неё не марширует, но щели между мелочью перестали
## быть тупиками. Дерево непроходимо всегда — там ствол один и он настоящий
const ORE_OBSTACLE_MIN_SCALE := 1.3

func _register_trunk() -> void:
	if resource_type == Constants.RESOURCE_WOOD:
		call_deferred("_register_trunk_now")
		return
	if resource_type != Constants.RESOURCE_GOLD and resource_type != Constants.RESOURCE_STONE:
		return
	if size_scale < ORE_OBSTACLE_MIN_SCALE:
		return
	call_deferred("_register_trunk_now")

func _register_trunk_now() -> void:
	if not is_inside_tree() or _trunk_registered:
		return
	GameManager.register_trunk(global_position, _obstacle_radius())
	_trunk_pos = global_position
	_trunk_registered = true

## Радиус препятствия. У золота/камня заметно меньше кольца добычи
## (slot_radius = 1.0×size_scale + SLOT_GAP), поэтому рабочий на своём месте
## у жилы никогда не стоит НА обстакле — он подходит к его краю, ровно как
## лесоруб к стволу
func _obstacle_radius() -> float:
	if resource_type == Constants.RESOURCE_WOOD:
		return TRUNK_RADIUS
	return ORE_OBSTACLE_RADIUS * size_scale

func _drop_trunk() -> void:
	if not _trunk_registered:
		return
	GameManager.unregister_trunk(_trunk_pos)
	_trunk_registered = false

func _exit_tree() -> void:
	_drop_trunk()
	# Место в общей отрисовке надо вернуть явно: картинка дерева живёт не под
	# его узлом, и вместе с ним не исчезнет (тот же случай, что у бойца в
	# Unit._exit_tree)
	_drop_veg()

var _trunk_registered: bool = false
var _trunk_pos: Vector3 = Vector3.ZERO

# ─────────────────────────────────────────────────────────────────────────────
# КОЛЬЦО РАБОЧИХ МЕСТ ВОКРУГ ЖИЛЫ (MINING SLOTS RING)
#
# ЗАЧЕМ. Раньше Worker.command_gather вёл рабочего в global_position жилы —
# то есть В ЦЕНТР камня. Все посланные на одну жилу шли в одну и ту же точку,
# влезали внутрь спрайта и там дрожали, расталкивая друг друга: со стороны
# «рабочий залез в текстуру золота и дёргается».
#
# СТАЛО. Вокруг жилы размечено кольцо точек подхода чуть за силуэтом. Рабочий
# занимает СВОБОДНЫЙ слот (ближайший к себе) и идёт именно туда. Слоты
# закреплены за конкретным рабочим и освобождаются при смене цели или смерти,
# поэтому бригада равномерно обступает камень по периметру и не толкается.
# ─────────────────────────────────────────────────────────────────────────────

## Зазор от силуэта: рабочий встаёт вплотную, но НЕ внутри. Уменьшен с 0.55 —
## бригада стояла заметно поодаль от жилы/ствола, теперь инструмент почти
## касается текстуры. SLOT_ARRIVE (Worker.gd) от этого не зависит: это допуск
## прихода к слоту, а не расстояние самого слота до центра ресурса
const SLOT_GAP := 0.30
## Шаг между соседями по кольцу — примерно личное пространство рабочего
const SLOT_ARC := 0.9
const SLOT_MIN := 4
const SLOT_MAX := 12
## ВТОРОЕ И ТРЕТЬЕ КОЛЬЦА. Раньше при переполнении первого кольца claim_slot()
## отдавал УЖЕ ЗАНЯТЫЙ слот — двое вставали в одну точку, взаимное
## расталкивание тут же растаскивало их с неё, приход в слот не засчитывался,
## и рабочий бесконечно «подходил заново». Со стороны это и есть то самое
## дёрганье в одной точке у камня. Теперь лишние встают на кольцо шире:
## бригада обступает жилу в два-три слоя, но каждый — на СВОЕЙ точке
const SLOT_RINGS := 3
## Насколько каждое следующее кольцо шире предыдущего, метры
const RING_STEP := 0.85

## instance_id рабочего → индекс занятого слота (сквозной по всем кольцам)
var _slot_owner: Dictionary = {}

## Радиус ПЕРВОГО кольца: за краем силуэта жилы
## РАДИУС САМОГО СТВОЛА (комель). Спрайт дерева — квад пять на пять метров,
## но ДЕРЕВО в нём занимает только узкую полосу по центру: всё остальное крона
## и прозрачный фон. По этому числу считаются и места рубки, и коллизия ствола
## (см. GameManager.register_trunk), поэтому оно живёт одной константой
const TRUNK_RADIUS := 0.35
## ── ГАБАРИТ КЛИКАБЕЛЬНОГО СТВОЛА ────────────────────────────────────────────
## Заметно шире физического комля (TRUNK_RADIUS): по 35 сантиметрам мышью не
## попасть, а задача — «кликбокс по стволу», а не «кликбокс в толщину коры».
## Высота — нижняя треть спрайта: там ствол, выше начинается крона
const TRUNK_PICK_RADIUS := 0.60
const TRUNK_PICK_HEIGHT := 1.80
## Радиус препятствия одного куска руды/камня (до size_scale) — меньше его
## кликабельного коллайдера (0.85×size_scale), чтобы обстакл не выпирал за
## видимый силуэт куска
const ORE_OBSTACLE_RADIUS := 0.5

## Радиус ПЕРВОГО кольца: за краем силуэта жилы
##
## ЗОЛОТО/КАМЕНЬ: раньше это было ВСЕГДА `1.0 * size_scale` — предположение,
## что нарисованный кусок укладывается в круг такого радиуса. На деле разные
## варианты спрайта заливают свой квадратный холст очень неравномерно
## (Gold Stone 1/2.png — только ~6% площади кадра, Gold Stone 6.png — уже
## ~45%), а с приходом _visual_half_width (см. _maybe_load_sprite — квад
## теперь раздувается так, чтобы САМ РИСУНОК стабильно занимал 2.5×size_scale
## метра, а не holst целиком) настоящая полуширина рисунка у мелких по заливке
## вариантов стала БОЛЬШЕ прежнего предположения. Рабочий, вставший на старое
## кольцо, оказывался внутри собственной картинки жилы — та самая жалоба
## «заходит прямо внутрь текстуры». Берём БОЛЬШЕЕ из предположения и замера:
## запасное предположение остаётся страховкой на случай, если спрайт ещё не
## успел собраться (_visual_half_width == 0.0 до _maybe_load_sprite)
func slot_radius() -> float:
	if resource_type == Constants.RESOURCE_WOOD:
		# ВПЛОТНУЮ К СТВОЛУ. Было 1.1 + зазор = 1.65 м от центра дерева, то
		# есть рабочий вставал под кроной и рубил воздух в метре от комля —
		# топор до текстуры ствола просто не доставал. Теперь кольцо считается
		# от толщины СТВОЛА, а не от габарита спрайта: 0.35 + 0.55 = 0.9 м,
		# и лезвие ложится ровно на дерево
		return TRUNK_RADIUS + SLOT_GAP
	return maxf(1.0 * size_scale, _visual_half_width) + SLOT_GAP

## Сколько мест на одном кольце заданного радиуса
func _ring_count(r: float) -> int:
	return clampi(int(TAU * r / SLOT_ARC), SLOT_MIN, SLOT_MAX)

func slot_count() -> int:
	return _ring_count(slot_radius())

## Всего мест по всем кольцам
func slot_total() -> int:
	var n := 0
	for ring in range(SLOT_RINGS):
		n += _ring_count(slot_radius() + float(ring) * RING_STEP)
	return n

## Мировая позиция слота по СКВОЗНОМУ индексу: сначала внутреннее кольцо,
## затем следующие. Кольца ещё и провёрнуты друг относительно друга на
## полшага — второй слой встаёт в просветы первого, а не в затылок ему
func slot_position(idx: int) -> Vector3:
	var i: int = idx
	var r: float = slot_radius()
	for ring in range(SLOT_RINGS):
		var n: int = _ring_count(r)
		if i < n:
			var ang: float = TAU * float(i) / float(n) + (PI / float(n)) * float(ring)
			var x: float = global_position.x + cos(ang) * r
			var z: float = global_position.z + sin(ang) * r
			return Vector3(x, GameManager.get_terrain_height(x, z), z)
		i -= n
		r += RING_STEP
	# Индекс за пределами разметки — отдаём место на внешнем кольце
	var xo: float = global_position.x + cos(float(idx)) * r
	var zo: float = global_position.z + sin(float(idx)) * r
	return Vector3(xo, GameManager.get_terrain_height(xo, zo), zo)

## Дистанция от ЦЕНТРА жилы, с которой инструмент уже достаёт. Считается от
## кольца слотов, а не отдельной константой: подошёл на своё место — работаешь.
## Раньше порог жил в Worker.GATHER_REACH и с разметкой колец не был связан
## вовсе, отсюда и рабочие, «не дотягивающиеся» до крупного самородка
func work_reach() -> float:
	# ЗАПАС ОБЯЗАН ПОКРЫВАТЬ ДОПУСК ПРИБЫТИЯ. Рабочий считает себя пришедшим,
	# не доходя до слота на Unit.ARRIVE_RADIUS, — и если инструмент с этого
	# места уже не достаёт, он встаёт рядом и не начинает работать вовсе
	# (замер qa_mine, D: вставал в 1.70 м при дотягивании 1.65).
	# Поэтому запас считается ОТ допуска прибытия, а не отдельным числом:
	# поменяют один — второй поедет следом
	return slot_radius() + Unit.ARRIVE_RADIUS + 0.2

## Занять свободное место, ближайшее к рабочему.
## Все места заняты — отдаём место на внешнем кольце по остатку от id:
## СВОЮ точку получает каждый, двое в одну не встают никогда
func claim_slot(who: Node3D) -> Vector3:
	# ДЕЛЕГИРУЕТ КУЧЕ. Разметка вокруг ОТДЕЛЬНОГО куска и была причиной того, что
	# рабочие лезли в середину навала: куски стоят вплотную, значит половина
	# точек «вокруг куска» приходится на промежутки МЕЖДУ соседями. У кучи места
	# размечены по внешнему периметру и внутрь не попадают по построению
	if _mine != null:
		return _mine.claim_slot(who)
	if who == null:
		return global_position
	var id: int = who.get_instance_id()
	if _slot_owner.has(id):
		var kept: int = _slot_owner[id]
		return slot_position(kept)
	# Чужие слоты — те, что заняты ЖИВЫМИ рабочими
	var taken: Dictionary = {}
	for k in _slot_owner.keys():
		var owner_id: int = int(k)
		if is_instance_valid(instance_from_id(owner_id)):
			taken[int(_slot_owner[k])] = true
		else:
			_slot_owner.erase(k)
	# КОЛЬЦА ЗАПОЛНЯЮТСЯ СТРОГО ИЗНУТРИ НАРУЖУ. Искать «ближайший свободный слот
	# вообще» нельзя: рабочий подходит к жиле СНАРУЖИ, и точка внешнего кольца
	# для него всегда ближе точки внутреннего — бригада вставала бы широким
	# хороводом в трёх метрах от камня, ни разу не дотянувшись до него.
	# Поэтому сначала целиком набивается ближнее кольцо, и только когда в нём
	# не осталось мест, открывается следующее.
	var base: int = 0
	var r: float = slot_radius()
	var pick: int = -1
	for ring in range(SLOT_RINGS):
		var n: int = _ring_count(r)
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
		r += RING_STEP
	# Разметка переполнена целиком: место за внешним кольцом, но персональное —
	# двое в одну точку не встают никогда
	if pick < 0:
		pick = slot_total() + (id % SLOT_MAX)
	_slot_owner[id] = pick
	return slot_position(pick)

func release_slot(who: Node3D) -> void:
	if _mine != null:
		_mine.release_slot(who)
		return
	if who != null:
		_slot_owner.erase(who.get_instance_id())

# ─────────────────────────────────────────────────────────────────────────────
# ЖИЛА В КУЧЕ: ЧТО ИМЕННО ПЕРЕЕХАЛО В MineCluster
# ─────────────────────────────────────────────────────────────────────────────

## ЦЕЛЬ ДОБЫЧИ. Кликнуть можно по любому камушку, а работать рабочий будет по
## КУЧЕ — и держать в качестве цели он обязан кусок, который переживёт всю
## выработку. Иначе на каждом косметически исчезнувшем камушке цель бы пропадала
## и рабочий уходил в поиск следующей на ровном месте
func gather_anchor() -> ResourceNode:
	if _mine != null:
		var a = _mine.anchor()
		if a != null and is_instance_valid(a):
			return a
	return self

## Дотягивается ли инструмент до этой цели из точки p. У кучи мерится ОТ ВСЕЙ
## КУЧИ (эллипс кольца стояния плюс запас), у одиночного ресурса — по-старому,
## расстоянием до центра. Один вопрос, два честных ответа: у кучи «центра» в
## осмысленном виде просто нет
func in_work_reach(p: Vector3) -> bool:
	if remaining <= 0.0:
		return false
	if _mine != null:
		return _mine.in_reach(p)
	var dx: float = p.x - global_position.x
	var dz: float = p.z - global_position.z
	var r: float = work_reach()
	return dx * dx + dz * dz < r * r

## Единичный вектор «выйти из навала» (Vector3.ZERO — рабочий и так снаружи).
## Приказ внутрь кучи не выдаётся никогда, так что это страховка от ЧУЖИХ сил —
## расталкивания соседями и обхода препятствий
func outward_push(p: Vector3) -> Vector3:
	if _mine == null:
		return Vector3.ZERO
	return _mine.outward_push(p)

## Косметика выработки: общий масштаб оставшихся кусков и скрытие тех, чей черёд
## уже прошёл. Зовёт только MineCluster._apply_depletion.
##
## СКРЫТЫЙ КУСОК ПЕРЕСТАЁТ БЫТЬ ВСЕМ, ЧЕМ БЫЛ: уходит из группы (значит его не
## найдёт ни поиск следующей цели, ни разбор клика), обнуляет слой (значит по
## нему нельзя попасть лучом) и снимается с реестра обхода (иначе на месте
## пропавшего камня осталась бы невидимая стена — ровно тот же случай, что у пня
## в extract). Узел при этом ЖИВ: список кусков кучи должен оставаться целым,
## а шестнадцать спящих узлов на кучу — не та цена, ради которой стоит городить
## работу с дырами в массиве
func set_cluster_visual(sc: float, hidden: bool) -> void:
	if hidden:
		if _cluster_hidden:
			return
		_cluster_hidden = true
		if _visual_root != null:
			_visual_root.visible = false
		collision_layer = 0
		_drop_trunk()
		remove_from_group("resource_nodes")
		set_process(false)
		return
	if _visual_root != null and not is_equal_approx(_visual_root.scale.x, sc):
		_visual_root.scale = Vector3.ONE * sc

var _cluster_hidden: bool = false

func _build_visual() -> void:
	var collider := CollisionShape3D.new()
	var shape    := CylinderShape3D.new()
	if resource_type == Constants.RESOURCE_WOOD:
		# ── КЛИКБОКС ДЕРЕВА — ЭТО СТВОЛ, А НЕ ВЕСЬ СПРАЙТ ────────────────────
		# Было: цилиндр 1.35 × 4.8 м на весь пятиметровый спрайт, «клик по любой
		# ветке отправляет рубить». Заказ владельца это разворачивает, и по делу:
		# крона нарисована широкой и полупрозрачной, а её коллайдер — сплошной
		# столб воздуха, который камера под 45° кладёт на несколько метров ЗЕМЛИ
		# ПЕРЕД деревом. Приказ соседнему отряду, отданный по чистой поляне рядом
		# с лесом, регулярно проваливался в это дерево.
		#
		# ЧЕСТНОЕ СЛЕДСТВИЕ: попасть по дереву стало ТРУДНЕЕ — цель ужалась
		# вчетверо по радиусу. Компенсируется двумя вещами, обе обязательны:
		# ствол теперь получает поправку на наклон камеры (pick_body_h ниже —
		# раньше она была нулевой ИМЕННО потому, что коллайдер был широким), и
		# кликать надо в комель, куда игрок и целится, глядя на кольцо подсветки
		shape.radius = TRUNK_PICK_RADIUS
		shape.height = TRUNK_PICK_HEIGHT
		collider.position.y = TRUNK_PICK_HEIGHT * 0.5
	else:
		# Коллайдер тянется за размером куска: крупный самородок кликабелен
		# по всей своей площади, мелкий осколок не перехватывает клики соседей
		shape.radius = 0.85 * size_scale
		shape.height = 1.6 * size_scale
		collider.position.y = 0.8 * size_scale
	collider.shape = shape
	add_child(collider)

	_visual_root = Node3D.new()
	add_child(_visual_root)

	match resource_type:
		Constants.RESOURCE_WOOD:
			_build_tree()
		Constants.RESOURCE_GOLD:
			_build_gold()
			_maybe_load_sprite()
		Constants.RESOURCE_STONE:
			_build_stone()
			_maybe_load_sprite()
		Constants.RESOURCE_FOOD:
			_build_food()
			_maybe_load_sprite()

# ─────────────────────────────────────────────────────────────────────────────
# ДЕРЕВЬЯ
# ─────────────────────────────────────────────────────────────────────────────

func _build_tree() -> void:
	if tree_variant == 0:
		tree_variant = randi_range(1, 4)

	var sprite_path := "res://assets/environment/resources/Tree%d.png" % tree_variant
	if ResourceLoader.exists(sprite_path):
		var tex := load(sprite_path) as Texture2D
		if tex:
			# ── ДЕРЕВО РИСУЕТСЯ ОБЩИМ MultiMesh, А НЕ СВОИМ УЗЛОМ ────────────
			# Здесь строился MeshInstance3D со СВОИМ QuadMesh и СВОИМ
			# ShaderMaterial. Материал был личным не от хорошей жизни: в нём
			# сидели фаза и длительность колыхания, а без разброса лес машет
			# единым куском («ползущие деревья»). Личный материал = отдельный
			# вызов отрисовки на каждое дерево, и на двух тысячах стволов это
			# 1762 вызова и потолок в 75 кадров в секунду на ПУСТОЙ карте
			# (замер qa_veg). Разброс переехал в instance-цвет
			# (см. VegetationRenderer), картинка осталась прежней.
			#
			# ВАЖНО: Tree*.png — горизонтальные спрайт-шиты (6-8 кадров
			# анимации). Пропорции берутся у ОДНОГО кадра; кадр выбирает
			# шейдер. (Квад по всему шиту давал ширину 30-40 м — «забор из
			# деревьев», крутившийся при повороте камеры как пропеллер.)
			# Цилиндрический билборд — тоже в шейдере: дерево доворачивается к
			# камере вокруг СВОЕГО ствола, а не всем лесом параллельно экрану.
			#
			# ПОСАДКА ОТЛОЖЕНА ПО ТОЙ ЖЕ ПРИЧИНЕ, ЧТО И РЕГИСТРАЦИЯ СТВОЛА
			# (см. _register_trunk): позицию узлу задают уже ПОСЛЕ add_child, а
			# в _ready она ещё нулевая. Узел-владелец картинки исчез, значит
			# мировая точка обязана попасть в буфер верной с первого раза —
			# «сама подтянется» тут больше некому
			_veg_tex = tex
			call_deferred("_plant_tree_now")
			return

	_build_tree_procedural()

## Отложенная посадка дерева в общую отрисовку (см. _build_tree)
func _plant_tree_now() -> void:
	if _veg_tex == null or _veg_slot != null or not is_inside_tree():
		return
	if _stump_node != null:
		return          # успели срубить до посадки
	var root: Node3D = null
	if GameManager.main != null and is_instance_valid(GameManager.main):
		root = GameManager.main.world_root()
	if root == null:
		root = get_parent() as Node3D
	if root == null:
		return
	_veg_base = global_position
	_veg_slot = GameManager.veg.plant(_veg_tex, _veg_base, TREE_HEIGHT, root)

## Снять дерево с общей отрисовки (срубили, выгрузили карту). Идемпотентно
## ── ПОДСВЕТКА ПРИ НАВЕДЕНИИ ─────────────────────────────────────────────────
## «Лёгкий виз-эффект на дереве» из заказа: сам ствол чуть зеленеет, а кольцо у
## комля рисует Main. Для руды здесь делать нечего — её подсвечивает ОВАЛ ПОД
## ВСЕЙ КУЧЕЙ, а не отдельный кусок: игрок показывает на месторождение, а не на
## конкретный самородок, и подсветка обязана отвечать тем же.
##
## Идемпотентно и дёшево: VegetationRenderer.set_highlight не трогает буфер,
## если значение не изменилось, а наведение опрашивается по таймеру
func set_hover_highlight(on: bool) -> void:
	if _veg_slot == null:
		return
	GameManager.veg.set_highlight(_veg_slot, 1.0 if on else 0.0)

## ЕСТЬ ЛИ ЗДЕСЬ ЕЩЁ ЧТО ДОБЫВАТЬ. Пень остаётся на карте навсегда, но выходит
## из группы resource_nodes и обнуляет слой (см. extract) — «живой» узел обязан
## проверяться по обоим признакам, иначе рабочий раз за разом идёт к пню
func is_gatherable() -> bool:
	return remaining > 0.0 and is_in_group("resource_nodes")

## ВЫСОТА, НА КОТОРОЙ НАРИСОВАН ЦЕНТР ЭТОЙ ЖИЛЫ. Нужна разбору клика: камера
## смотрит под 45°, поэтому точка ЗЕМЛИ под курсором уходит за основание объекта
## примерно на его высоту. Для бойца эта поправка в SelectionManager есть давно
## (UNIT_BODY_H), а у жил её не было вовсе — отсюда и промахи по мелким кускам
func pick_body_h() -> float:
	if resource_type == Constants.RESOURCE_WOOD:
		# РАНЬШЕ ЗДЕСЬ БЫЛ НОЛЬ, и это было верно: коллайдер накрывал весь
		# пятиметровый спрайт, то есть цель и так была шириной с крону, и
		# сдвигать её было незачем. Теперь кликбокс — узкий ствол, и без
		# поправки на наклон камеры точка земли уходила бы за комель ровно на
		# его высоту: игрок целится в ствол, а приказ уходит на землю за ним
		return TRUNK_PICK_HEIGHT * 0.5
	# Кусок руды нарисован высотой примерно PIECE_TARGET_H * size_scale;
	# центр рисунка — на его половине
	return 0.64 * size_scale

## ── НА СКОЛЬКО ПОДНЯТЬ КОЛЬЦО ПОДСВЕТКИ, ЧТОБЫ ОНО ОБНЯЛО КОМЕЛЬ ────────────
## Квад дерева стоит нижней кромкой ровно на грунте, поэтому «кольцо на земле в
## точке дерева» геометрически безупречно — и всё равно выглядит лежащим НА
## ТРАВЕ ПОД деревом. Причина в арте: у Tree*.png под стволом есть прозрачные
## поля, и НАРИСОВАННЫЙ комель начинается заметно выше нижней кромки кадра.
##
## Поле меряется у самой текстуры (Image.get_used_rect), а не задаётся числом:
## новый спрайт дерева с другим отступом подхватится сам, а константа
## разъехалась бы с ним молча. Кэш на текстуру — деревьев тысячи, а лент четыре
static var _base_pad_cache: Dictionary = {}

func hover_ring_lift() -> float:
	if resource_type != Constants.RESOURCE_WOOD or _veg_tex == null:
		return 0.0
	var key: String = _veg_tex.resource_path
	if not key.is_empty() and _base_pad_cache.has(key):
		return float(_base_pad_cache[key]) * TREE_HEIGHT
	var frac := 0.0
	var img: Image = _veg_tex.get_image()
	if img != null:
		if img.is_compressed() and img.decompress() != OK:
			img = null
	if img != null and img.get_height() > 0:
		var used: Rect2i = img.get_used_rect()
		if used.size.y > 0:
			# Пустая полоса ПОД рисунком, в долях высоты кадра
			var pad_px: float = float(img.get_height() - (used.position.y + used.size.y))
			frac = clampf(pad_px / float(img.get_height()), 0.0, 0.4)
	if not key.is_empty():
		_base_pad_cache[key] = frac
	return frac * TREE_HEIGHT

func _drop_veg() -> void:
	if _veg_slot == null:
		return
	GameManager.veg.remove(_veg_slot)
	_veg_slot = null

func _build_tree_procedural() -> void:
	var trunk := MeshInstance3D.new()
	var trunk_cyl := CylinderMesh.new()
	trunk_cyl.top_radius    = 0.18
	trunk_cyl.bottom_radius = 0.30
	trunk_cyl.height = 3.2
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.32, 0.20, 0.10)
	trunk_mat.roughness    = 0.95
	trunk_cyl.material = trunk_mat
	trunk.mesh = trunk_cyl
	trunk.position.y = 1.6
	_visual_root.add_child(trunk)

	mesh_instance = MeshInstance3D.new()
	var leaves := SphereMesh.new()
	leaves.radius = randf_range(1.5, 2.1)
	leaves.height = leaves.radius * 1.8
	var leaves_mat := StandardMaterial3D.new()
	leaves_mat.albedo_color = Color(
		randf_range(0.07, 0.14),
		randf_range(0.36, 0.52),
		randf_range(0.09, 0.18)
	)
	leaves_mat.roughness = 0.9
	leaves.material = leaves_mat
	mesh_instance.mesh = leaves
	mesh_instance.position.y = 3.2 + leaves.radius * 0.7
	_visual_root.add_child(mesh_instance)

func _show_stump() -> void:
	# Пень ставится РОВНО ОДИН РАЗ и навсегда: повторные вызовы extract()
	# по исчерпанному дереву раньше пересоздавали узел — отсюда мигание
	if _stump_node != null:
		return

	# Сбросить дрожание рубки, иначе пень унаследует смещение ствола
	_shake_power = 0.0
	set_process(false)
	if _visual_root:
		_visual_root.position = Vector3.ZERO
		_visual_root.visible  = false
	# Крону дерева убираем из общей отрисовки — прятать там нечего, слот просто
	# освобождается и достаётся следующему растению
	_drop_veg()

	var stump_path := "res://assets/environment/terrain/Stump %d.png" % tree_variant
	if ResourceLoader.exists(stump_path):
		var tex := load(stump_path) as Texture2D
		if tex:
			# Stump*.png — ОДИНОЧНАЯ картинка 192x256, где сам пенёк занимает
			# лишь нижние ~13% кадра. Кадрируем по непрозрачной области, иначе
			# большую часть квада занимает пустота и пенёк кажется крошечным.
			var cropped := _crop_to_content(tex)
			if cropped != null:
				tex = cropped
			_stump_node = MeshInstance3D.new()
			var quad := QuadMesh.new()
			var st_sz := tex.get_size()
			var aspect: float = (st_sz.x / st_sz.y) if st_sz.y > 0.0 else 1.0
			quad.size = Vector2(STUMP_HEIGHT * aspect, STUMP_HEIGHT)
			# fps = 0 — статичный кадр, никакой анимации и мигания
			quad.material = _BBUtil.make_material(tex, Color.WHITE, 0.5, 0.0)
			_stump_node.mesh = quad
			# Низ пня ровно на земле (после кадрирования пустоты снизу нет)
			_stump_node.position.y = STUMP_HEIGHT * 0.5
			add_child(_stump_node)
			return

	# Процедурный пенёк если нет спрайта
	_stump_node = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius    = 0.2592   # −10% к 0.288 (те, в свою очередь, −10% к 0.32)
	cyl.bottom_radius = 0.3078   # −10% к 0.342
	cyl.height = 0.2835          # −10% к 0.315
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.24, 0.12)
	mat.roughness    = 0.9
	cyl.material = mat
	_stump_node.mesh = cyl
	_stump_node.position.y = 0.14175   # половина высоты: низ ровно на грунте
	add_child(_stump_node)

# ─────────────────────────────────────────────────────────────────────────────
# Остальные ресурсы
# ─────────────────────────────────────────────────────────────────────────────

func _build_gold() -> void:
	mesh_instance = MeshInstance3D.new()
	var gold_sphere := SphereMesh.new()
	gold_sphere.radius = 0.7
	gold_sphere.height = 1.4
	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.9, 0.75, 0.1)
	gold_mat.metallic     = 0.65
	gold_mat.roughness    = 0.2
	gold_sphere.material  = gold_mat
	mesh_instance.mesh    = gold_sphere
	mesh_instance.position.y = 0.7
	_visual_root.add_child(mesh_instance)

func _build_stone() -> void:
	for i in range(3):
		var rock := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var r := randf_range(0.45, 0.80)
		sphere.radius = r
		sphere.height = r * 1.3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(randf_range(0.42, 0.55), randf_range(0.40, 0.52), randf_range(0.38, 0.50))
		mat.roughness    = 0.92
		mat.metallic     = 0.05
		sphere.material  = mat
		rock.mesh = sphere
		rock.position = Vector3(randf_range(-0.6, 0.6), r * 0.5, randf_range(-0.6, 0.6))
		_visual_root.add_child(rock)
	mesh_instance = _visual_root.get_child(0)

func _build_food() -> void:
	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_color = Color(0.10, 0.45, 0.10)
	bush_mat.roughness    = 0.9
	var bush := MeshInstance3D.new()
	var b_mesh := SphereMesh.new()
	b_mesh.radius = 0.6; b_mesh.height = 0.9
	b_mesh.material = bush_mat
	bush.mesh = b_mesh; bush.position.y = 0.45
	_visual_root.add_child(bush)
	for i in range(5):
		var berry := MeshInstance3D.new()
		var bm := SphereMesh.new(); bm.radius = 0.10; bm.height = 0.20
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.75, 0.08, 0.08)
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.material = bmat; berry.mesh = bm
		var angle := TAU * float(i) / 5.0
		berry.position = Vector3(cos(angle) * 0.55, 0.55, sin(angle) * 0.55)
		_visual_root.add_child(berry)
	mesh_instance = bush

# Вода как ресурс УДАЛЕНА из игры: колодцев на карте нет, рабочие её не
# добывают, в интерфейсе её тоже нет. Озеро осталось декорацией и препятствием.

# Сколько вариантов спрайта есть у каждого типа ресурса
const GOLD_VARIANTS  := 6    # Gold Stone 1..6
const STONE_VARIANTS := 4    # Rock1..4

## Аддитивный перелив золота. Проверено вручную (2026-08-07) поперёк всех
## 6 вариантов и всех 6 кадров каждого: непрозрачная область *_Highlight.png
## попиксельно СОВПАДАЕТ с непрозрачной областью базового Gold Stone N.png —
## никакого гало шире самородка в текущих файлах уже нет (см. подробный
## разбор в _maybe_load_sprite — эта заметка описывала более раннюю версию
## арта). Включаем обратно
## ── ПОКАДРОВАЯ ОБРЕЗКА ЛЕНТЫ ───────────────────────────────────────────────
## Обычный спрайт обрезается по нарисованному через AtlasTexture: он вырезает
## ОДИН прямоугольник, и лишние прозрачные поля не тянутся вместе с рисунком.
## На ЛЕНТЕ этот приём не работает — один прямоугольник захватил бы все кадры
## разом, и анимация превратилась бы в бегущую строку.
##
## Поэтому лента пересобирается: считается общая на все кадры область
## нарисованного, и из неё складывается новая, узкая лента. Дальше по коду всё
## считается как для обычного спрайта — размер квада, посадка на грунт,
## slot_radius, — а кадры листает штатный cyl_billboard.
##
## Общая обрезка, а не своя у каждого кадра, — обязательна: у кадров разный
## рисунок (по самородку ходит глянец), и обрежь каждый по себе, жила дёргалась
## бы в такт анимации.
##
## Результат кэшируется по пути исходника: вариантов золота шесть, а кусков в
## кучах — десятки
static var _sheet_cache: Dictionary = {}

## Возвращает [ImageTexture, Rect2i обрезки в пикселях ОДНОГО кадра]
## или пустой массив, если обрезать нечего
static func _crop_sheet(tex: Texture2D, frames: int) -> Array:
	var key: String = tex.resource_path
	if not key.is_empty() and _sheet_cache.has(key):
		return _sheet_cache[key]
	var img: Image = tex.get_image()
	if img == null:
		return []
	if img.is_compressed() and img.decompress() != OK:
		return []
	var fw: int = int(img.get_width() / maxi(frames, 1))
	var fh: int = img.get_height()
	if fw <= 0 or fh <= 0:
		return []
	# Общая на все кадры область нарисованного
	var lo := Vector2i(fw, fh)
	var hi := Vector2i(-1, -1)
	for f in range(frames):
		var frame_img: Image = img.get_region(Rect2i(f * fw, 0, fw, fh))
		var r: Rect2i = frame_img.get_used_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		lo.x = mini(lo.x, r.position.x)
		lo.y = mini(lo.y, r.position.y)
		hi.x = maxi(hi.x, r.position.x + r.size.x)
		hi.y = maxi(hi.y, r.position.y + r.size.y)
	if hi.x <= lo.x or hi.y <= lo.y:
		return []
	var used := Rect2i(lo, hi - lo)
	if used.position == Vector2i.ZERO and used.size == Vector2i(fw, fh):
		return []      # обрезать нечего — лента и так плотная
	var out := Image.create(used.size.x * frames, used.size.y, false,
		Image.FORMAT_RGBA8)
	for f in range(frames):
		out.blit_rect(img,
			Rect2i(f * fw + used.position.x, used.position.y,
				used.size.x, used.size.y),
			Vector2i(f * used.size.x, 0))
	var res: Array = [ImageTexture.create_from_image(out), used]
	if not key.is_empty():
		_sheet_cache[key] = res
	return res

## Мировой размер ПОЛНОГО кадра исходника. Ключ к «нерастянутым» спрайтам:
## плотность текселей на метр постоянна, а величина куска берётся из того,
## сколько он занимает в кадре, и из класса (см. Main.PIECE_CLASSES).
## Золото нарисовано вдвое подробнее камня (128×128 против 64×64), поэтому
## числа разные — на экране кадры при этом одного порядка
##
## ЧИСЛА ПОДОБРАНЫ ПО КАРТИНКЕ и остаются единственной ручкой размера кусков:
## поднять их — вся руда станет крупнее, не теряя резкости, потому что растёт
## мировой размер, а не коэффициент растяжения рисунка. Куски одного класса у
## РАЗНЫХ вариантов получаются разной величины — это не дефект, а прямое
## следствие того, что варианты по-разному заполняют свой кадр (у Gold Stone 1
## рисунок занимает ~23% высоты, у Gold Stone 6 — ~45%), и как раз оно даёт
## «самородки разного размера» из задания
const FRAME_METRES_STONE := 3.8
const FRAME_METRES_GOLD  := 4.4

## Целевая высота куска класса 1.0 (см. Main.PIECE_CLASSES: big 1.6, mid 1.05,
## small 0.62 — то есть примерно 2.0 / 1.3 / 0.8 м). Это и есть «ручка размера»
const PIECE_TARGET_H := 1.28
## Насколько разрешено отходить от родной высоты рисунка ради целевой.
## ZOOM_MAX держим умеренным: именно многократное увеличение и превращало
## пиксельный камень в мыло
const ZOOM_MIN := 0.55
const ZOOM_MAX := 1.75

func _maybe_load_sprite() -> void:
	var path := ""
	match resource_type:
		Constants.RESOURCE_GOLD:
			if res_variant <= 0:
				res_variant = randi_range(1, GOLD_VARIANTS)
			# ── АНИМАЦИЯ ЗОЛОТА — ЭТО САМ СПРАЙТ, А НЕ ПОДСВЕТКА ПОВЕРХ ─────
			# `Gold Stone N.png` — ОДИН кадр 128x128, никакого перелива в нём
			# нет. Анимация лежит в парном `_Highlight.png` (768x128), и это
			# НЕ слой блика: все шесть кадров — целый самородок, по которому
			# ходит глянец. То есть это и есть анимированная версия жилы.
			#
			# Раньше её рисовали ВТОРЫМ квадом поверх базового, аддитивным
			# шейдером — отсюда и жёлтое пятно на траве, из-за которого перелив
			# сперва выключили целиком, а потом чинили порогом отсечки. Ни того,
			# ни другого не нужно: лента играется штатным кадровым путём
			# (cyl_billboard листает кадры сам, им же анимированы деревья)
			path = "res://assets/environment/resources/Gold Stone %d_Highlight.png" % res_variant
		Constants.RESOURCE_STONE:
			if res_variant <= 0:
				res_variant = randi_range(1, STONE_VARIANTS)
			path = "res://assets/environment/resources/Rock%d.png" % res_variant
		Constants.RESOURCE_FOOD:
			path = "res://assets/sprites/resources/Meat Resource.png"
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	for child in _visual_root.get_children():
		child.free()
	var quad := QuadMesh.new()
	# ПРОПОРЦИИ — ПО КАДРУ ТЕКСТУРЫ, а не жёстким числом. Стояло (2.0, 2.5),
	# то есть соотношение 0.8, при том что все жилы и камни нарисованы КВАДРАТНЫМИ
	# (Gold Stone*.png — 128×128, Rock*.png — 64×64): рисунок вытягивался вверх
	# на четверть. Теперь высота ведущая, ширина считается от неё
	#
	# ОБРЕЗКА ДО РИСУНКА, А НЕ РАЗДУВАНИЕ ХОЛСТА. Кусок закрашивает свой
	# квадратный кадр очень неровно: у Gold Stone 1/2.png самородок — это
	# ~6% площади кадра, у Gold Stone 6.png — уже ~45%, у Rock1.png — ~20%.
	# При одинаковом size_scale (одном и том же классе "big"/"mid"/"small")
	# на карте оказывались то микроскопическая крупинка, то заметный кусок —
	# по мелким вариантам золота вся куча читалась как «горстка искр».
	# Первая попытка лечения раздувала ВЕСЬ холст (вместе с прозрачными
	# полями) так, чтобы рисунок дотягивал до 2.5×size_scale м — и на
	# скудно закрашенных вариантах (Gold1: высота рисунка 23% кадра) холст
	# улетал за 17 метров, а вместе с ним и невидимый квад: несколько таких
	# соседей схлопывались в одну гигантскую вертикальную свечку задолго до
	# своих пикселей. ПРАВИЛЬНЫЙ приём — тот же, что у HUD._trimmed_icon для
	# плоских иконок ресурсов: обрезать AtlasTexture по факту нарисованного
	# (Image.get_used_rect) и масштабировать квад ПО ОБРЕЗКЕ, а не по кадру —
	# тогда лишние прозрачные поля не тянутся вместе с рисунком
	var img: Image = tex.get_image()
	if img != null and img.is_compressed():
		if img.decompress() != OK:
			img = null
	var draw_tex: Texture2D = tex
	# Сколько кадров в исходнике: один у камня и мяса, шесть у золота
	var frames: int = _BBUtil.frame_count(tex)
	# ── ЧИСЛО КАДРОВ ЗАПОМИНАЕМ ПОЛЕМ ──────────────────────────────────────
	# У пересобранной ленты нет resource_path, и BillboardUtil.frame_count по
	# ней падает на угадывание по пропорции — при неквадратной обрезке оно
	# отвечает «один кадр». Рендеру это не мешает (число кадров уходит в
	# материал явно), а вот стенду пропорций (qa_aspect) без него не с чем
	# сравнивать: он делил бы ширину ВСЕЙ ленты на высоту одного кадра
	sprite_frames_drawn = frames
	# used_rect в пикселях ОДНОГО кадра — по нему считается размер квада
	var used_rect := Rect2i(Vector2i.ZERO, tex.get_size())
	var crop_w: float = tex.get_width()
	var crop_h: float = tex.get_height()
	if frames > 1:
		# ── ЛЕНТУ ОБРЕЗАЕМ ПОКАДРОВО, А НЕ ЦЕЛИКОМ ──────────────────────────
		# AtlasTexture вырезает ОДИН прямоугольник, и на ленте он захватил бы
		# все шесть кадров разом — анимация превратилась бы в бегущую строку.
		# Поэтому лента пересобирается: берётся общая на все кадры обрезка, из
		# неё складывается новая узкая лента, и дальше по коду всё считается
		# как для обычного спрайта — cyl_billboard листает её сам
		used_rect = Rect2i(Vector2i.ZERO, Vector2i(tex.get_height(), tex.get_height()))
		crop_w = float(used_rect.size.x)
		crop_h = float(used_rect.size.y)
		var packed: Array = _crop_sheet(tex, frames)
		if not packed.is_empty():
			draw_tex = packed[0]
			used_rect = packed[1]
			crop_w = float(used_rect.size.x)
			crop_h = float(used_rect.size.y)
	elif img != null:
		var used: Rect2i = img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0 \
				and not (used.position == Vector2i.ZERO and used.size == img.get_size()):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(used)
			atlas.filter_clip = true
			draw_tex = atlas
			used_rect = used
			crop_w = float(used.size.x)
			crop_h = float(used.size.y)
	# ── РАЗМЕР БЕРЁТСЯ ИЗ ПИКСЕЛЕЙ ИСХОДНИКА, А НЕ РАСТЯГИВАЕТСЯ ДО ЧИСЛА ────
	# Здесь стояло `lump_h = 2.5 * size_scale`, то есть квад имел ФИКСИРОВАННУЮ
	# мировую высоту независимо от того, сколько пикселей нарисовано. Rock*.png
	# — это 64×64, и его вырезанная часть (обычно 40-50 px) растягивалась на
	# 2.5-4 м: увеличение в разы, и вместе с линейной фильтрацией (её убрали в
	# cyl_billboard.gdshader) это и давало «сильно растянутый камень, пиксели
	# плывут и мылятся».
	#
	# Теперь у КАДРА исходника есть постоянный мировой размер (FRAME_METRES), а
	# вырезанный кусок занимает свою долю от него. Плотность текселей на метр
	# одинакова у всех вариантов и всех куч; разные по величине самородки
	# получаются оттого, что они РАЗНЫЕ В АРТЕ и стоят в разных классах, а не
	# оттого, что один и тот же рисунок надули сильнее другого
	var frame_m: float = FRAME_METRES_GOLD if resource_type == Constants.RESOURCE_GOLD \
		else FRAME_METRES_STONE
	var frame_px: float = maxf(float(tex.get_height()), 1.0)
	# «Родная» высота: рисунок в масштабе один к одному с плотностью текселей
	# кадра. Растяжения нет ровно при ней
	var natural_h: float = crop_h * frame_m / frame_px
	# ── РАЗБРОС РАЗМЕРОВ ОГРАНИЧЕН ──────────────────────────────────────────
	# Чистая пропорция «сколько нарисовано — столько и метров» дала разлёт в
	# десять раз: варианты заполняют свой кадр от ~6% до ~45%, и рядом с
	# нормальным самородком ложились точки в пиксель. Поэтому у класса есть
	# ЦЕЛЕВАЯ высота, но дотягиваться до неё разрешено лишь в пределах
	# ZOOM_MIN..ZOOM_MAX от родной: размер получается читаемым и предсказуемым,
	# а пересэмплирование остаётся мягким — при нежёстком увеличении
	# nearest-фильтр не рвёт рисунок так, как рвал прежний апскейл в разы
	var target_h: float = PIECE_TARGET_H * size_scale
	var h: float = clampf(target_h, natural_h * ZOOM_MIN, natural_h * ZOOM_MAX)
	var aspect: float = crop_w / crop_h if crop_h > 0.0 else 1.0
	quad.size = Vector2(h * aspect, h)
	var res_mat := _BBUtil.make_material(draw_tex)
	if frames > 1:
		# ЧИСЛО КАДРОВ ЗАДАЁМ ЯВНО. У пересобранной ленты нет resource_path, и
		# BillboardUtil.frame_count падает на угадывание по пропорции — при
		# неквадратной обрезке оно ошиблось бы. Темп и фаза у каждой жилы свои,
		# иначе вся куча переливается одним тактом
		res_mat.set_shader_parameter("frame_count", float(frames))
		res_mat.set_shader_parameter("frame_fps", randf_range(5.0, 8.0))
		res_mat.set_shader_parameter("frame_phase", randf() * float(frames))
	quad.material = res_mat
	# Квад теперь И ЕСТЬ рисунок (без полей) — читает slot_radius(), чтобы
	# рабочий вставал за краем НАРИСОВАННОГО куска, а не за краем прозрачного
	# квада
	_visual_half_width = quad.size.x * 0.5
	var billboard := MeshInstance3D.new()
	billboard.mesh = quad
	# КУСОК СТОИТ НА ЗЕМЛЕ, А НЕ ВИСИТ НАД НЕЙ.
	# QuadMesh центрируется в своём начале координат, поэтому подъём равен
	# ПОЛОВИНЕ высоты квада — тогда нижняя кромка спрайта ложится ровно на y=0.
	# Раньше стояло 1.5 × size_scale при высоте квада 2.5 × size_scale: низ
	# оказывался на 0.25 × size_scale выше грунта, и крупные жилы (scale 1.6)
	# заметно парили в воздухе
	billboard.position.y = quad.size.y * 0.5
	_visual_root.add_child(billboard)
	mesh_instance = billboard

	# ── АДДИТИВНОГО БЛИКА ВТОРЫМ КВАДОМ ЗДЕСЬ БОЛЬШЕ НЕТ ───────────────────
	# Стоял второй MeshInstance3D с *_Highlight.png на аддитивном шейдере
	# (shaders/gold_shimmer.gdshader) — и вся возня вокруг него (порог отсечки
	# каймы, crop_rect в шейдере, отдельный такт кадров) была решением задачи,
	# которой нет. `_Highlight.png` — не слой блика поверх жилы, а САМА ЖИЛА,
	# нарисованная шестью кадрами с ходящим глянцем. Её и рисуем, штатным
	# кадровым путём (см. выбор `path` в начале функции): один квад, один
	# обычный материал, никакого аддитивного смешивания и никаких пятен на траве

func extract(amount: float) -> float:
	# ЖИЛА В КУЧЕ ЧЕРПАЕТ ИЗ ОБЩЕГО ПУЛА. Кусок своего запаса больше не имеет:
	# его `remaining` — это зеркало остатка кучи, которое MineCluster обновляет
	# у всех кусков сразу (см. _apply_depletion). Косметику усыхания и удаление
	# выработанных кусков делает тоже куча — здесь этой ветки нет намеренно,
	# иначе два места решали бы одно и то же по-разному
	if _mine != null:
		return _mine.extract(amount)
	var taken: float = min(amount, remaining)
	remaining -= taken

	if remaining > 0.0:
		# Деревья НЕ уменьшаются при рубке: масштабирование дёргало спрайт и
		# смещало ствол. Прочие ресурсы по-прежнему «оседают».
		if resource_type != Constants.RESOURCE_WOOD and _visual_root:
			var factor: float = max(remaining / _max_remaining, 0.15)
			_visual_root.scale = Vector3.ONE * factor
	else:
		if resource_type == Constants.RESOURCE_WOOD:
			# Пень остаётся на карте НАВСЕГДА (так просили), но перестаёт быть
			# ресурсом: снимаем с группы, гасим физику и покадровый тик.
			# Иначе каждый рабочий при выборе следующего дерева перебирал
			# сотни пней (find_nearest_resource идёт по группе), а сам узел
			# продолжал числиться живым объектом на слое ресурсов
			_show_stump()
			collision_layer = 0  # не мешает движению рабочих
			# ПЕНЬ НЕ ПРЕПЯТСТВИЕ: через него переступают. Ствола больше нет —
			# снимаем его с учёта обхода, иначе на месте вырубки осталась бы
			# невидимая стена (см. GameManager.register_trunk)
			_drop_trunk()
			remove_from_group("resource_nodes")
			set_process(false)
			set_physics_process(false)
		else:
			queue_free()

	return taken

# ─────────────────────────────────────────────────────────────────────────────
# ВИБРАЦИЯ ПРИ РУБКЕ
# Вызывается рабочим на каждый взмах топора: дерево вздрагивает по X/Z и само
# успокаивается. Пень не трясётся.
#
# АМПЛИТУДА ПОДНЯТА С 0.02 ДО 0.06. Прежние «1-2 пикселя на экране» на рабочем
# отдалении камеры не читались вообще: удар был, а дерево стояло как вкопанное.
# Втрое больше — это по-прежнему сантиметры, дерево не ходит ходуном, но сруб
# ощущается. Частота ударов задаётся не здесь, а темпом взмаха
# (Worker.CHOP_SWING_RATE): дрожь заводится на каждое касание топора.
#
# ЗАТУХАНИЕ ЗАМЕДЛЕНО (3.0 → 2.2): при возросшей частоте ударов дрожь от
# соседних взмахов теперь перекрывается, и дерево трясётся непрерывно, пока
# его рубят, а не вздрагивает отдельными рывками
# ─────────────────────────────────────────────────────────────────────────────
const SHAKE_AMPLITUDE := 0.06
const SHAKE_DECAY     := 2.2

# Высота ВИДИМОЙ части пня. Раньше квад был 1.2 м, но пенёк занимал в нём
# лишь ~13% (0.19 м) — после кадрирования по содержимому 0.95 м это ровно
# в 5 раз крупнее прежнего и соответствует комлю срубленного дерева.
# 0.95 → 0.855 (−10%, диаметр пенька ровно под срез ствола) → 0.7695 (ещё −10%,
# заказ владельца: «уменьшить размер спрайта пеньков после вырубки на 10%»).
# Пропорции при этом не трогаются: ширина квада считается от высоты по аспекту
# ОБРЕЗАННОЙ текстуры (см. _show_stump), поэтому одно число масштабирует пенёк
# целиком. Процедурный запасной пенёк ниже уменьшен тем же множителем — иначе
# карта без спрайтов пней выглядела бы иначе, чем с ними
const STUMP_HEIGHT := 0.7695

# Обрезать текстуру по непрозрачной области (кэш общий на вариант пня)
static var _crop_cache: Dictionary = {}

static func _crop_to_content(tex: Texture2D) -> Texture2D:
	var key: String = tex.resource_path
	if not key.is_empty() and _crop_cache.has(key):
		return _crop_cache[key]
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed() and img.decompress() != OK:
		return null
	var rect := img.get_used_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return null
	var out := ImageTexture.create_from_image(img.get_region(rect))
	if not key.is_empty():
		_crop_cache[key] = out
	return out

func shake() -> void:
	if _stump_node != null:
		return
	# ── В ТУМАНЕ ДЕРЕВО НЕ ДРОЖИТ ───────────────────────────────────────────
	# Дрожь ствола — это анимация «его прямо сейчас рубят», и под дымкой
	# «разведано, но не видно» она выдаёт чужого лесоруба ровно так же, как выдал
	# бы стук топора (см. AudioManager._audible_at). Плюс это чистая экономия:
	# невидимое дерево заводило покадровый тик и писало в общий буфер отрисовки
	if GameManager.fog != null and is_instance_valid(GameManager.fog) \
			and not GameManager.fog.is_lit(global_position.x, global_position.z):
		return
	# У дерева со спрайтом собственного узла картинки больше нет — трясётся его
	# место в общей отрисовке (_veg_slot). У остальных ресурсов трясётся, как и
	# раньше, _visual_root
	if _visual_root == null and _veg_slot == null:
		return
	_shake_power = 1.0
	set_process(true)

func _process(delta: float) -> void:
	if (_visual_root == null and _veg_slot == null) or _shake_power <= 0.0:
		set_process(false)
		return
	_shake_power = maxf(0.0, _shake_power - delta * SHAKE_DECAY)
	_shake_time += delta * 34.0
	var amp := SHAKE_AMPLITUDE * _shake_power
	var ox: float = sin(_shake_time) * amp
	var oz: float = cos(_shake_time * 0.7) * amp * 0.5
	var done: bool = _shake_power <= 0.0
	if done:
		# Возврат ТОЧНО в исходную точку — ствол не «уползает» от рубки
		ox = 0.0
		oz = 0.0
	if _veg_slot != null:
		GameManager.veg.move(_veg_slot,
			Vector3(_veg_base.x + ox, _veg_base.y, _veg_base.z + oz))
	elif _visual_root != null:
		_visual_root.position.x = ox
		_visual_root.position.z = oz
	if done:
		set_process(false)
