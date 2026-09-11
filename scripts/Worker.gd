extends Unit
class_name Worker

## Потолок выпаса у замка и прочие числа стада — в конфиге владельца
const _UCfgW := preload("res://scripts/unit_stats_config.gd")

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
## Только ради константы F_WORKING: сами массивы живут полем GameManager.army
const _Army := preload("res://scripts/army/ArmySoA.gd")

## Последнее записанное в строку значение F_WORKING. Держим у себя, чтобы не
## трогать массив признаков каждый тик — он общий на всю армию
var _soa_working: bool = false

@export var gather_time: float   = 2.0
@export var gather_amount: float = 10.0

# Скорости из unit_stats_config.gd: с грузом рабочий идёт медленнее
var walk_speed_empty: float  = 4.0
var walk_speed_loaded: float = 2.8

var carrying_amount: float = 0.0
var carrying_type: int     = Constants.RESOURCE_WOOD
var gather_target: ResourceNode = null
# Тип ресурса, на который рабочего послали. Переживает исчезновение самого
# узла (дерево срубили в пень и оно освободилось) — по нему ищем следующее
var _gather_res_type: int  = -1
## Номер КУЧИ, на которой рабочий сейчас трудится (ResourceNode.cluster_id).
## 0 — куча неизвестна или её нет вовсе (лес сажается россыпью, а не кучей).
## Переживает исчезновение узла ровно по той же причине, что и _gather_res_type:
## кусок руды при выработке освобождается насовсем, и спросить его номер потом
## уже не у кого — а именно в этот момент он и нужен, чтобы взять СОСЕДНИЙ кусок
## В ТОЙ ЖЕ КУЧЕ, а не первый попавшийся на карте (см. _auto_find_resource)
var _gather_cluster: int   = 0
var _gather_timer: float   = 0.0
var _axe: Node3D           = null
var _pickaxe: Node3D       = null
var _chop_time: float      = 0.0
var _cargo_indicator: MeshInstance3D = null
var _pawn_sprite: AnimatedSprite3D = null

func _ready() -> void:
	# Рабочий читает свой блок вручную (у него свои скорости и добыча), но
	# stat_id обязателен: по нему адресуются бонусы кузницы вида applies_to ["all"]
	stat_id = "worker"
	var s: Dictionary = _UStats.get_stats("worker")
	walk_speed_empty  = s.get("walk_speed_empty", 4.0)
	walk_speed_loaded = s.get("walk_speed_loaded", 2.8)
	gather_time       = s.get("gather_time", gather_time)
	gather_amount     = s.get("gather_amount", gather_amount)
	max_health        = s.get("health", 30.0)
	armor             = s.get("armor", 0.0)
	morale            = s.get("morale", 80.0)
	push_force        = s.get("push_force", 0.5)
	move_speed        = walk_speed_empty
	attack_damage = 0.0
	display_name  = "Рабочий"
	super._ready()
	_setup_worker_visual()
	# Процедурные инструменты нужны только если анимированный Pawn не загрузился
	if _pawn_sprite == null:
		_create_axe()
		_create_pickaxe()
	_create_cargo_indicator()

func _setup_worker_visual() -> void:
	# 1. Анимированный Pawn: инструменты и переноска ресурсов вшиты в спрайт-шиты.
	# Берём набор ЦВЕТА СВОЕЙ ФРАКЦИИ, запасной — общая папка worker/
	var fname := GameManager.race_of(faction)
	var folder := GameManager.unit_sprite_folder(faction, "worker")
	# Проба ПО ФАЙЛУ, а не по каталогу: DirAccess в экспортной сборке отвечает
	# не то же самое, что в редакторе (см. SpriteSheetParser.folder_has)
	var colored := _SSParser.folder_has(folder, "Pawn_Idle.png")
	if not colored:
		folder = "res://assets/factions/%s/units/worker" % fname
	var asp: AnimatedSprite3D = _SSParser.build_sprite_from_map(folder, {
		"idle":       "Pawn_Idle.png",
		"walk":       "Pawn_Run.png",
		"chop":       "Pawn_Interact Axe.png",      # рубка дерева ТОПОРОМ
		"mine":       "Pawn_Interact Pickaxe.png",  # добыча камня/золота КИРКОЙ
		"harvest":    "Pawn_Interact Knife.png",    # сбор еды ножом
		"build":      "Pawn_Interact Hammer.png",   # СТРОЙКА деревянным молотком
		"carry_wood": "Pawn_Run Wood.png",          # несёт брёвна
		"carry_gold": "Pawn_Run Gold.png",          # несёт золото
		"carry_stone": "Pawn_Run_Stone.png",        # несёт камень (есть не у всех цветов)
		"carry_meat": "Pawn_Run Meat.png",          # несёт еду
	})
	if asp:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		# Цветной спрайт уже нужного цвета; оттенок — только для общего набора
		if colored:
			asp.modulate = Color.WHITE
		else:
			asp.modulate = Color(1.0, 0.60, 0.45) if faction == Constants.FACTION_ENEMY else Color.WHITE
		add_child(asp)
		_active_sprite = asp
		_pawn_sprite   = asp
		return

	# 2. Fallback: billboard-квадрат с цветом фракции.
	# Квад создаётся ТОЛЬКО здесь — у рабочего со спрайтом его нет вовсе
	_ensure_body_quad()
	if _sprite_node:
		var mat := _sprite_node.get_active_material(0) as StandardMaterial3D
		if mat == null:
			return
		if faction == Constants.FACTION_PLAYER:
			mat.albedo_color = Color(0.35, 0.80, 0.35)   # зелёный — рабочий игрока
		else:
			mat.albedo_color = Color(0.85, 0.55, 0.20)   # оранжевый — рабочий врага

func _create_cargo_indicator() -> void:
	_cargo_indicator = MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.4, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat; _cargo_indicator.mesh = sm
	_cargo_indicator.position = Vector3(0.0, 2.1, 0.0)
	_cargo_indicator.visible  = false
	add_child(_cargo_indicator)

func _update_cargo_color() -> void:
	if _cargo_indicator == null:
		return
	var mat := _cargo_indicator.get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	match carrying_type:
		Constants.RESOURCE_WOOD:  mat.albedo_color = Color(0.42, 0.26, 0.10)
		Constants.RESOURCE_GOLD:  mat.albedo_color = Color(1.0,  0.80, 0.05)
		Constants.RESOURCE_STONE: mat.albedo_color = Color(0.55, 0.52, 0.50)
		Constants.RESOURCE_FOOD:  mat.albedo_color = Color(0.20, 0.75, 0.20)

func _create_axe() -> void:
	_axe = Node3D.new(); _axe.name = "Axe"
	var handle := MeshInstance3D.new()
	var h_cyl  := CylinderMesh.new()
	h_cyl.top_radius = 0.025; h_cyl.bottom_radius = 0.03; h_cyl.height = 0.55
	var h_mat := StandardMaterial3D.new(); h_mat.albedo_color = Color(0.42, 0.26, 0.10); h_mat.roughness = 0.9
	h_cyl.material = h_mat; handle.mesh = h_cyl
	_axe.add_child(handle)

	var blade := MeshInstance3D.new()
	var b_box  := BoxMesh.new(); b_box.size = Vector3(0.28, 0.22, 0.06)
	var b_mat  := StandardMaterial3D.new(); b_mat.albedo_color = Color(0.70, 0.72, 0.76); b_mat.metallic = 0.85; b_mat.roughness = 0.2
	b_box.material = b_mat; blade.mesh = b_box; blade.position = Vector3(0.14, 0.22, 0.0)
	_axe.add_child(blade)

	_axe.position = Vector3(0.55, 1.1, 0.0)
	_axe.visible  = false
	add_child(_axe)

# Процедурная КИРКА (fallback): для добычи камня и золота
func _create_pickaxe() -> void:
	_pickaxe = Node3D.new(); _pickaxe.name = "Pickaxe"
	var handle := MeshInstance3D.new()
	var h_cyl  := CylinderMesh.new()
	h_cyl.top_radius = 0.025; h_cyl.bottom_radius = 0.03; h_cyl.height = 0.60
	var h_mat := StandardMaterial3D.new(); h_mat.albedo_color = Color(0.42, 0.26, 0.10); h_mat.roughness = 0.9
	h_cyl.material = h_mat; handle.mesh = h_cyl
	_pickaxe.add_child(handle)

	var head := MeshInstance3D.new()
	var head_box := BoxMesh.new(); head_box.size = Vector3(0.42, 0.07, 0.06)
	var head_mat := StandardMaterial3D.new(); head_mat.albedo_color = Color(0.55, 0.56, 0.60); head_mat.metallic = 0.8; head_mat.roughness = 0.3
	head_box.material = head_mat; head.mesh = head_box; head.position = Vector3(0.0, 0.30, 0.0)
	_pickaxe.add_child(head)

	_pickaxe.position = Vector3(0.55, 1.1, 0.0)
	_pickaxe.visible  = false
	add_child(_pickaxe)

# ═════════════════════════════════════════════════════════════════════════════
# АВТО-ЦИКЛ: ВЫРАБОТАЛ — ВЗЯЛ СЛЕДУЮЩЕЕ. РАЗНЫЙ У ИГРОКА И У ИИ
# ═════════════════════════════════════════════════════════════════════════════
# ЧТО БЫЛО. Здесь стоял единственный вызов GameManager.find_nearest_resource,
# то есть «ближайший кусок этого типа НА ВСЕЙ КАРТЕ». Формально авто-цикл был, и
# срубленное дерево действительно сменялось следующим — но границы у поиска не
# было никакой. Выработав кучу у базы, бригада молча уходила за полкарты к
# первой попавшейся жиле: мимо озера, мимо вражеских патрулей, без единого
# приказа игрока и без единого признака в интерфейсе. Простаивающих рабочих при
# этом не появлялось НИКОГДА — счётчик Idle Workers на выработке кучи не
# срабатывал в принципе, потому что рабочий всегда что-то себе находил.
#
# ЧТО СТАЛО — две разные политики, как и заказано:
#   • ИГРОК: следующий кусок берётся только В СВОЕЙ КУЧЕ (руда) или в пределах
#     делянки (лес). Кончилось рядом — рабочий встаёт и попадает в счётчик
#     простаивающих. Куда вести бригаду дальше, решает игрок, а не эвристика.
#   • ИИ: то же самое, но при пустой куче он не встаёт, а уходит на СЛЕДУЮЩУЮ
#     кучу (find_next_cluster_resource). ИИ некому раздать приказ вручную, и
#     застрявшая на выработанной жиле бригада — это просто мёртвая экономика.
#
# Куча опознаётся по номеру (ResourceNode.cluster_id, реестр в Main.res_clusters)
func _auto_find_resource(res_type: int) -> void:
	if res_type < 0:
		state = State.IDLE
		return
	# Недоступная жила исключается ровно на этот поиск (см. _blocked_target)
	var skip: ResourceNode = _blocked_target
	_blocked_target = null
	# 1. Рядом: свой кластер для руды, соседний ствол для леса
	var new_target: ResourceNode = GameManager.find_next_resource_nearby(
		global_position, res_type, _gather_cluster, 1.0, skip)
	# 1б. Не вышло — ищем ЧУТЬ ШИРЕ. Это случай «следующий ствол перекрыт»:
	# рядом стволы есть, но до них не дойти, и стоять столбом посреди делянки
	# рабочий не должен
	if new_target == null and skip != null:
		new_target = GameManager.find_next_resource_nearby(
			global_position, res_type, _gather_cluster, WIDE_SEARCH_SCALE, skip)
	# 2. Рабочий ИИ не имеет права застревать — идёт на следующую кучу
	if new_target == null and faction != Constants.FACTION_PLAYER:
		new_target = GameManager.find_next_cluster_resource(
			global_position, res_type, _gather_cluster)
	if new_target != null:
		command_gather(new_target)
		return
	# ── МОЯ КУЧА ЕЩЁ НЕ ПУСТА — ЗНАЧИТ ДЕЛО НЕ В НЕЙ, А В ДОРОГЕ ─────────────
	# Заказ владельца: «если точка заблокирована, делать повторную попытку, а не
	# сбрасывать рабочий статус». Поиск выше ограничен радиусом вокруг рабочего;
	# рабочего могло вытолкнуть за этот радиус (соседи, обход кучи), и тогда он
	# вставал бездельником при живой жиле в двух шагах. Спрашиваем саму кучу:
	# пока в ней есть запас, у неё есть и якорь — цель, которая переживёт всю
	# выработку (см. MineCluster.anchor)
	if _gather_cluster > 0:
		var anchor: ResourceNode = GameManager.cluster_anchor(_gather_cluster)
		if anchor != null and is_instance_valid(anchor) and anchor.is_gatherable():
			command_gather(anchor)
			return
	# ── РЯДОМ ВСЁ ВЫРАБОТАНО: ВСТАЁМ И ЖДЁМ ПРИКАЗА ─────────────────────────
	# Слот на бывшей жиле обязателен к возврату, иначе он остался бы забронирован
	# за рабочим, который уже ничего не добывает (см. _free_slot)
	_free_slot()
	gather_target    = null
	_gather_res_type = -1
	_gather_cluster  = 0
	state            = State.IDLE

func command_move(target_pos: Vector3, slow_march: bool = false, face_dir: Vector3 = Vector3.ZERO,
		keep_retreat: bool = false, player_order: bool = false, run: bool = false) -> void:
	_drop_sheep_job()
	_free_slot()
	gather_target    = null
	_gather_res_type = -1     # прямой приказ игрока отменяет работу
	_gather_cluster  = 0
	_leave_construction()
	super.command_move(target_pos, slow_march, face_dir, keep_retreat, player_order, run)

## Отдать своё место на кольце жилы. Зовётся отовсюду, где рабочий перестаёт
## быть добытчиком: иначе слот остаётся забронированным за ушедшим, и бригада
## обступает камень реже, чем могла бы
func _free_slot() -> void:
	_gather_slot_valid = false
	if gather_target != null and is_instance_valid(gather_target):
		gather_target.release_slot(self)

# ─────────────────────────────────────────────────────────────────────────────
# СТРОЙКА
# Рабочий идёт к площадке, встаёт у её края и стучит молотком, пока стройка
# не готова. Прогресс копит сама площадка (ConstructionSite), рабочий лишь
# числится на ней «строителем» — так несколько рабочих ускоряют одну стройку.
# ─────────────────────────────────────────────────────────────────────────────
var build_target: Node3D = null

func command_build(site: Node3D) -> void:
	if site == null or not is_instance_valid(site):
		return
	_drop_sheep_job()
	set_attack_target(null)
	_free_slot()
	gather_target    = null
	_gather_res_type = -1
	_gather_cluster  = 0
	_leave_construction()
	build_target = site
	move_target  = site.work_position(global_position)
	state        = State.BUILDING
	_build_settled = false   # новая стройка — новый подход
	# ── СТАРАЯ МЕТКА ПРИКАЗА СНИМАЕТСЯ ВМЕСТЕ С ПРИКАЗОМ ───────────────────
	# Метка точки движения гаснет по ПРИБЫТИЮ отряда (см.
	# GameManager._refresh_order_marks). Рабочий, которого послали в точку, а
	# потом отправили строить, до неё не дойдёт НИКОГДА — и кольцо остаётся
	# висеть в чистом поле. Ровно это владелец и видит как «фантомные круги,
	# которых игрок не задавал». Новая работа отменяет прежний приказ
	GameManager.squad_clear_order(squad_id)
	_wake_process()

func command_gather(node: ResourceNode) -> void:
	if node == null or not is_instance_valid(node):
		return
	# ЦЕЛЬ ДОБЫЧИ У РУДЫ — ВСЯ КУЧА, А НЕ ТОТ КАМУШЕК, ПО КОТОРОМУ КЛИКНУЛИ.
	# gather_anchor() отдаёт кусок, который переживёт всю выработку (см.
	# MineCluster.anchor). Без этого цель пропадала бы на каждом косметически
	# исчезнувшем камушке, и рабочий уходил бы в поиск следующей на ровном месте
	node = node.gather_anchor()
	_drop_sheep_job()
	_leave_construction()
	set_attack_target(null)
	# Слот на прежней жиле отдаём: иначе он остался бы забронирован навсегда
	if gather_target != null and is_instance_valid(gather_target) and gather_target != node:
		gather_target.release_slot(self)
	# Счёт попыток дойти обнуляется ТОЛЬКО при СМЕНЕ цели. Повтор подхода зовёт
	# эту же функцию с той же жилой (см. tick_physics), и безусловный сброс
	# означал бы, что порог APPROACH_GIVE_UP не достигается никогда, — то есть
	# вечный повтор остался бы на месте
	if gather_target != node:
		_approach_fails = 0
	gather_target    = node
	_gather_res_type = node.resource_type
	# Номер кучи запоминается ЗДЕСЬ, а не спрашивается у цели потом: к моменту,
	# когда рабочий доработает кусок, узла уже не будет (руда освобождается
	# насовсем, см. ResourceNode.extract), и спросить будет не у кого
	_gather_cluster  = node.cluster_id
	# ИДЁМ НА КОЛЬЦО, А НЕ В ЦЕНТР ЖИЛЫ. Приказ в global_position камня означал
	# «влезь внутрь спрайта и дрожи там вместе со всеми» — см. ResourceNode.claim_slot
	move_target      = node.claim_slot(self)
	_gather_slot_valid = true
	state            = State.MOVING
	# Новая работа отменяет прежний приказ вместе с его меткой (тот же разбор,
	# что и у command_build выше)
	GameManager.squad_clear_order(squad_id)
	_wake_process()

# Сняться со стройки: площадка перестаёт считать нас строителем
func _leave_construction() -> void:
	if build_target != null and is_instance_valid(build_target):
		if build_target.has_method("remove_builder"):
			build_target.remove_builder(self)
	build_target = null

func _exit_tree() -> void:
	_free_slot()
	_leave_construction()
	_drop_sheep_job()
	super._exit_tree()

# ─────────────────────────────────────────────────────────────────────────────
# КРАЖА ОВЦЫ И РАЗДЕЛКА НА МЯСО (заказ владельца, 10.09.2026)
# Овца (goblin/Sheep.gd) — не ресурс-узел: у неё нет слотов и запаса, рабочий
# уносит её ЦЕЛИКОМ. Фазы: идти к овце (MOVING, лента ходьбы) → взять (овца
# едет над головой, RETURNING с грузом «мясо» — лента Pawn_Run Meat) → у
# склада опустить рядом и РАЗДЕЛАТЬ (GATHERING с ножом, Pawn_Interact Knife):
# SHEEP_CUTS надрезов по SHEEP_CUT_SEC, каждый — MEAT_PER_CUT еды в склад
# (рабочий стоит у стены, относить нечего), последний — овца гибнет и даёт
# ещё MEAT_FINAL. Куда нести — _sheep_dest(): будущий ЗАГОН (группа
# sheep_pens с методом accept_sheep, своей стороны) в приоритете, иначе
# ближайший склад (замок). Любой другой приказ бросает овцу (release_from).
# ─────────────────────────────────────────────────────────────────────────────
const SHEEP_GRAB_DIST := 1.4
## ── СЛЕДУЮЩАЯ ОВЦА БЕРЁТСЯ САМА (заказ спринта 14) ────────────────────────
## «После полного выноса мяса с одной туши рабочий автоматически переключается
## на следующую ближайшую овцу — по аналогии с добычей дерева. Команда не
## должна сбрасываться, а рабочие не должны толпиться у Ратуши.»
## Радиус поиска щедрый: стадо разбредается по выпасу, и «ближайшая» вполне
## может стоять в тридцати метрах — но не через всю карту
const SHEEP_NEXT_RANGE := 40.0
const SHEEP_CARRY_Y := 1.45
## ── РАЗДЕЛКА: ДЕСЯТЬ УДАРОВ НА КУСОК, ПЯТЬ ХОДОК (заказ 10.09.2026) ───
## Было пять надрезов подряд, и всё мясо зачислялось на месте — ходок с грузом
## на экране не возникало вовсе. Теперь цикл повторяется SHEEP_MEAT_TRIPS раз:
## SHEEP_CUTS_PER_MEAT ударов ножом у туши → кусок мяса на руки → ходка к
## складу → возврат к туше. На последней ходке овца выработана и исчезает.
## Итог за тушу тот же (MEAT_PER_TRIP × SHEEP_MEAT_TRIPS = 60 еды)
## ── СНАЧАЛА СМЕРТЬ, ПОТОМ ХОДКИ (заказ спринта 13) ────────────────────────
## «Разделка: 5 ударов ножом → смерть»; «с туши 300 еды за 15-30 ходок, то
## есть 2-3 минуты». Это ДВЕ разные серии ударов, и путать их нельзя:
## SHEEP_KILL_CUTS убивают овцу (она валится на бок, Sheep.kill_flip), а
## дальше идёт цикл «SHEEP_CUTS_PER_MEAT ударов → кусок → ходка на склад →
## возврат», и таких ходок SHEEP_MEAT_TRIPS.
## АРИФМЕТИКА ЗАКАЗА: 20 × 15 = 300 еды, а по времени 20 ходок × (10 × 0.45 с
## ножом + около двух секунд дороги) ≈ 130 с, то есть чуть больше двух минут
const SHEEP_KILL_CUTS := 5
const SHEEP_CUTS_PER_MEAT := 10
const SHEEP_MEAT_TRIPS := 20
const MEAT_PER_TRIP := 15.0
## Удар ножом чаще прежнего: десять ударов по 1.2 с — это двенадцать
## секунд стояния на одну ходку, а таких ходок пять
const SHEEP_CUT_SEC := 0.45
const SHEEP_STAND_PAD := 1.4
## Насколько близко к туше рабочий возвращается за следующим куском
const SHEEP_BACK_PAD := 0.6
## GO — идёт к овце, CARRY — несёт её на голове (дикую — домой, в загон),
## KILL — пять ударов ножом до смерти, BUTCHER — десять ударов на кусок,
## HAUL — несёт кусок на склад, BACK — возвращается к туше
enum SheepPhase { NONE, GO, CARRY, KILL, BUTCHER, HAUL, BACK }
var _sheep: Node3D = null
var _sheep_phase: int = SheepPhase.NONE
var _sheep_dest_node: Node3D = null
var _sheep_cuts: int = 0
## Ударов за всю разделку и сколько кусков уже отнесено (стенды)
var _sheep_cuts_total: int = 0
var _sheep_trips: int = 0
var _sheep_cut_t: float = 0.0
## Куда рабочий положил тушу: к ней он и возвращается за следующим куском
var _sheep_spot: Vector3 = Vector3.ZERO
## Стенды: сколько мяса сдано этим рабочим
var meat_delivered: float = 0.0

func command_steal_sheep(s: Node3D) -> void:
	if s == null or not is_instance_valid(s) or not s.has_method("captured_by"):
		return
	if not bool(s.call("is_free")):
		return
	# ТУШУ ПОВТОРНО НЕ РЕЖЕМ: она уже мертва, мясо с неё вынесет тот, кто её
	# убил (у мёртвой овцы `dead` = true и своих ходок больше нет)
	if bool(s.get("dead")):
		return
	_drop_sheep_job()
	_leave_construction()
	_free_slot()
	set_attack_target(null)
	gather_target = null
	_gather_res_type = -1
	_gather_cluster = 0
	build_target = null
	_sheep = s
	_sheep_phase = SheepPhase.GO
	_sheep_cuts = 0
	_sheep_cuts_total = 0
	_sheep_trips = 0
	move_target = s.global_position
	state = State.MOVING
	GameManager.squad_clear_order(squad_id)
	_wake_process()

func is_stealing_sheep() -> bool:
	return _sheep_phase != SheepPhase.NONE

func sheep_phase() -> int:
	return _sheep_phase

func sheep_cuts() -> int:
	return _sheep_cuts

## Ударов ножом за всю разделку и сколько кусков уже отнесено
func sheep_cuts_total() -> int:
	return _sheep_cuts_total

func sheep_trips() -> int:
	return _sheep_trips

## ── БЛИЖАЙШАЯ СВОБОДНАЯ ОВЦА ПОСЛЕ ВЫРАБОТАННОЙ ТУШИ ──────────────────────
## Отсчёт от МЕСТА ТУШИ, а не от склада: рабочий стоит там, и «ближайшая» для
## него считается оттуда. Предпочтение — овце того же рода, что и прошлая
## (своя из загона или дикая у логова): иначе рабочий, которому велели резать
## СВОЁ стадо, уходил бы воровать к логову тролля и обратно.
## Мёртвых и занятых не берём: у первых мясо уже чьё-то, вторых режет сосед
func _next_sheep(from: Vector3, want_owned: bool) -> Node3D:
	var best: Node3D = null
	var best_d: float = SHEEP_NEXT_RANGE
	var fallback: Node3D = null
	var fallback_d: float = SHEEP_NEXT_RANGE
	for s in get_tree().get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s):
			continue
		if bool(s.get("eaten")) or bool(s.get("dead")):
			continue
		if not bool(s.call("is_free")):
			continue
		var d: float = from.distance_to((s as Node3D).global_position)
		if d >= SHEEP_NEXT_RANGE:
			continue
		if bool(s.call("is_owned")) == want_owned:
			if d < best_d:
				best_d = d
				best = s
		elif d < fallback_d:
			fallback_d = d
			fallback = s
	return best if best != null else fallback

## ── КУДА ВЕСТИ УКРАДЕННУЮ ОВЦУ ────────────────────────────────────────────
## Приоритет — БЛИЖАЙШИЙ ЗАГОН СВОЕЙ СТОРОНЫ, У КОТОРОГО ЕСТЬ МЕСТО. Полный
## загон в выборе не участвует вовсе: довести до него овцу и услышать «мест
## нет» значит потерять всю дорогу. Загонов нет или все полны — ближайший
## склад (замок): там овца либо встанет на выпас (потолок
## CASTLE_GRAZE_LIMIT), либо будет разделана на месте (см. SheepPhase.CARRY)
func _sheep_dest() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for p in get_tree().get_nodes_in_group("sheep_pens"):
		if p == null or not is_instance_valid(p) or not p.has_method("accept_sheep"):
			continue
		if int(p.get("faction")) != faction:
			continue
		if p.has_method("has_room") and not bool(p.call("has_room")):
			continue
		var d: float = global_position.distance_to((p as Node3D).global_position)
		if d < bd:
			bd = d
			best = p
	if best != null:
		return best
	return GameManager.get_nearest_dropoff(faction, global_position)

## Сколько овец уже пасётся у ЭТОГО замка (потолок CASTLE_GRAZE_LIMIT)
func _keep_flock(keep: Node3D) -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s) or bool(s.get("eaten")):
			continue
		if bool(s.get("dead")):
			continue
		if s.get("keep") == keep:
			n += 1
	return n

## Взять овцу на выпас у замка, если потолок позволяет
func _keep_accepts(keep: Node3D) -> bool:
	if keep == null or not is_instance_valid(keep):
		return false
	return _keep_flock(keep) < _UCfgW.CASTLE_GRAZE_LIMIT

func _dest_edge(dest: Node3D, _dir: Vector3) -> float:
	if dest is Building:
		return (dest as Building).ring_radius()
	return 1.0

## Бросить овцу (новый приказ, гибель): взятая — снова свободна на месте
func _drop_sheep_job() -> void:
	if _sheep != null and is_instance_valid(_sheep) and _sheep_phase != SheepPhase.NONE:
		_sheep.call("release_from", self)
	_sheep = null
	_sheep_dest_node = null
	_sheep_phase = SheepPhase.NONE
	if carrying_amount <= 0.0 and carrying_type == Constants.RESOURCE_FOOD:
		carrying_type = Constants.RESOURCE_WOOD

func _cancel_sheep_job() -> void:
	_drop_sheep_job()
	state = State.IDLE
	_wake_process()

func _process_sheep(delta: float) -> void:
	if _sheep == null or not is_instance_valid(_sheep) or bool(_sheep.get("eaten")):
		_sheep = null
		_cancel_sheep_job()
		return
	match _sheep_phase:
		SheepPhase.GO:
			if not bool(_sheep.call("is_free")):
				_cancel_sheep_job()
				return
			var d: Vector3 = _sheep.global_position - global_position
			d.y = 0.0
			var dist: float = d.length()
			if dist <= SHEEP_GRAB_DIST:
				# ── ХОЗЯЙСКУЮ РЕЖЕМ ТАМ, ГДЕ ОНА ПАСЁТСЯ ───────────────────
				# Приказ один и тот же — ПКМ рабочим по овце, — а смысл у него
				# два, и различает их ПРИВЯЗКА: дикая у логова крадётся домой,
				# своя из загона идёт под нож на месте. Тащить свою же овцу к
				# складу незачем, она и так дома
				if bool(_sheep.call("is_owned")):
					_sheep.call("captured_by", self)
					_sheep_spot = _sheep.global_position
					_sheep_phase = SheepPhase.KILL
					_sheep_cut_t = SHEEP_CUT_SEC
					state = State.GATHERING
					_wake_process()
					return
				_sheep_dest_node = _sheep_dest()
				if _sheep_dest_node == null:
					_cancel_sheep_job()
					return
				_sheep.call("captured_by", self)
				carrying_type = Constants.RESOURCE_FOOD
				carrying_amount = 0.0
				_sheep_phase = SheepPhase.CARRY
				state = State.RETURNING
				_wake_process()
				return
			move_target = _sheep.global_position
			var nd: Vector3 = d / maxf(dist, 0.001)
			_facing = nd
			velocity = nd * move_speed
			_tick_stuck(delta, dist)
			_move_blocked(velocity * delta)
		SheepPhase.CARRY:
			if _sheep_dest_node == null or not is_instance_valid(_sheep_dest_node):
				_cancel_sheep_job()
				return
			var d2: Vector3 = _sheep_dest_node.global_position - global_position
			d2.y = 0.0
			var dist2: float = d2.length()
			var edge: float = _dest_edge(_sheep_dest_node, d2)
			_sheep.call("carry_to", global_position + Vector3(0.0, SHEEP_CARRY_Y, 0.0))
			if dist2 <= edge + SHEEP_STAND_PAD + 0.9:
				velocity = Vector3.ZERO
				var out: Vector3 = -d2 / maxf(dist2, 0.001)
				var spot: Vector3 = global_position + Vector3(-out.z, 0.0, out.x) * 1.2
				_sheep.call("drop_at", spot)
				_sheep_spot = spot
				var to_sheep: Vector3 = spot - global_position
				to_sheep.y = 0.0
				if to_sheep.length() > 0.01:
					_facing = to_sheep.normalized()
				# ── ЖИВАЯ ОВЦА В СТАДО, А НЕ ПОД НОЖ ───────────────────────
				# Донесли — сперва пробуем ПОСТАВИТЬ НА ВЫПАС: загон принимает
				# по accept_sheep, замок — по своему потолку. Приняли — работа
				# кончена, овца пасётся и плодится. Мест нет нигде — режем
				# здесь же, у склада: иначе украденная овца была бы потеряна
				var taken := false
				if _sheep_dest_node.has_method("accept_sheep"):
					taken = bool(_sheep_dest_node.call("accept_sheep", _sheep))
				elif _keep_accepts(_sheep_dest_node):
					_sheep.call("bind_to_keep", _sheep_dest_node, faction)
					taken = true
				if taken:
					_sheep.call("release_from", self)
					_sheep = null
					_sheep_phase = SheepPhase.NONE
					_sheep_dest_node = null
					carrying_amount = 0.0
					carrying_type = Constants.RESOURCE_WOOD
					state = State.IDLE
					_wake_process()
					return
				_sheep_phase = SheepPhase.KILL
				_sheep_cut_t = SHEEP_CUT_SEC
				state = State.GATHERING
				_wake_process()
				return
			var nd2: Vector3 = d2 / maxf(dist2, 0.001)
			_facing = nd2
			velocity = nd2 * move_speed
			_tick_stuck(delta, dist2)
			_move_blocked(velocity * delta)
		SheepPhase.KILL:
			# ПЯТЬ УДАРОВ НОЖОМ — И ОВЦА МЕРТВА (прямой заказ спринта 13).
			# Дальше начинается вынос мяса ходками, и мёртвая туша обязана
			# ЛЕЖАТЬ на месте всё это время (Sheep.kill_flip кладёт её на бок)
			velocity = Vector3.ZERO
			_sheep_cut_t -= delta
			if _sheep_cut_t > 0.0:
				return
			_sheep_cut_t = SHEEP_CUT_SEC
			_sheep_cuts += 1
			_sheep_cuts_total += 1
			_sheep.call("wound_flash")
			AudioManager.play_3d("chop", global_position)
			if _sheep_cuts < SHEEP_KILL_CUTS:
				return
			_sheep_cuts = 0
			_sheep.call("kill_flip")
			# Место туши берём У НЕЁ, а не у себя: убитая на выпасе лежит там,
			# где паслась, и возвращаться (SheepPhase.BACK) надо именно туда
			_sheep_spot = _sheep.global_position
			_sheep_phase = SheepPhase.BUTCHER
		SheepPhase.BUTCHER:
			velocity = Vector3.ZERO
			_sheep_cut_t -= delta
			if _sheep_cut_t > 0.0:
				return
			_sheep_cut_t = SHEEP_CUT_SEC
			_sheep_cuts += 1
			_sheep_cuts_total += 1
			_sheep.call("wound_flash")
			AudioManager.play_3d("chop", global_position)
			if _sheep_cuts < SHEEP_CUTS_PER_MEAT:
				return
			# ── КУСОК ОТРЕЗАН: НЕСЁМ ЕГО НА СКЛАД ──────────────────────────
			# Мясо зачисляется НЕ ЗДЕСЬ, а по приходу (SheepPhase.HAUL): это и
			# есть заказанная ходка, иначе груз на руках был бы декорацией
			_sheep_cuts = 0
			carrying_type = Constants.RESOURCE_FOOD
			carrying_amount = MEAT_PER_TRIP
			_sheep_phase = SheepPhase.HAUL
			state = State.RETURNING
			_wake_process()
		SheepPhase.HAUL:
			# МЯСО НЕСЁТСЯ НА СКЛАД, А НЕ В ЗАГОН. Загон — место выпаса, склада
			# у него нет вовсе; и убить овцу могли прямо в нём, за полкарты от
			# замка. Цель ходки поэтому пересчитывается один раз, здесь
			if _sheep_dest_node == null or not is_instance_valid(_sheep_dest_node) \
					or _sheep_dest_node.has_method("accept_sheep"):
				_sheep_dest_node = GameManager.get_nearest_dropoff(faction, global_position)
			if _sheep_dest_node == null or not is_instance_valid(_sheep_dest_node):
				_cancel_sheep_job()
				return
			var dh: Vector3 = _sheep_dest_node.global_position - global_position
			dh.y = 0.0
			var disth: float = dh.length()
			var edgeh: float = _dest_edge(_sheep_dest_node, dh)
			if disth <= edgeh + SHEEP_STAND_PAD:
				velocity = Vector3.ZERO
				ResourceManager.gather_resource(faction, Constants.RESOURCE_FOOD, carrying_amount)
				meat_delivered += carrying_amount
				carrying_amount = 0.0
				_sheep_trips += 1
				if _sheep_trips >= SHEEP_MEAT_TRIPS:
					# ПОСЛЕДНЯЯ ХОДКА — ТУША ВЫРАБОТАНА: она исчезает
					var done_at: Vector3 = _sheep_spot
					var was_owned := false
					if _sheep != null and is_instance_valid(_sheep):
						was_owned = bool(_sheep.call("is_owned"))
						_sheep.call("consume")
					_sheep = null
					_sheep_phase = SheepPhase.NONE
					_sheep_dest_node = null
					carrying_type = Constants.RESOURCE_WOOD
					state = State.IDLE
					# ── И СРАЗУ ЗА СЛЕДУЮЩУЮ ────────────────────────────────
					# Приказ «режь овец» не разовый: рабочий, доевший тушу,
					# сам берётся за ближайшую следующую — ровно как рубщик
					# переходит на соседнее дерево. Без этого он вставал в
					# IDLE у склада, и вся бригада копилась там толпой
					var nxt: Node3D = _next_sheep(done_at, was_owned)
					if nxt != null:
						command_steal_sheep(nxt)
						return
					_wake_process()
					return
				_sheep_phase = SheepPhase.BACK
				state = State.MOVING
				_wake_process()
				return
			var ndh: Vector3 = dh / maxf(disth, 0.001)
			_facing = ndh
			velocity = ndh * move_speed
			_tick_stuck(delta, disth)
			_move_blocked(velocity * delta)
		SheepPhase.BACK:
			var db: Vector3 = _sheep_spot - global_position
			db.y = 0.0
			var distb: float = db.length()
			if distb <= SHEEP_GRAB_DIST + SHEEP_BACK_PAD:
				velocity = Vector3.ZERO
				var to_body: Vector3 = _sheep_spot - global_position
				to_body.y = 0.0
				if to_body.length() > 0.01:
					_facing = to_body.normalized()
				_sheep_phase = SheepPhase.BUTCHER
				_sheep_cut_t = SHEEP_CUT_SEC
				state = State.GATHERING
				_wake_process()
				return
			var ndb: Vector3 = db / maxf(distb, 0.001)
			_facing = ndb
			velocity = ndb * move_speed
			_tick_stuck(delta, distb)
			_move_blocked(velocity * delta)

# Зовёт ConstructionSite, когда здание достроено
func on_construction_finished() -> void:
	build_target = null
	state = State.IDLE
	_wake_process()

## ДОПУСК ПРИХОДА НА СТРОЙКУ, сверх стены здания. Щедрый по той же причине,
## что и SLOT_ARRIVE у жилы: в артели соседи всё время подталкивают друг друга,
## и узкий круг не достигается вовсе. Но «пришёл» и «стоит где надо» — разные
## вещи, добор до стены идёт ниже (см. ConstructionSite.WORK_PAD)
const BUILD_ARRIVE_PAD := 0.9

## Защёлка «я уже на стройке» (разбор — в _process_build).
## Снимается там же и любым новым приказом на стройку
var _build_settled: bool = false

## КУДА рабочий доводит себя, встав на работу: отступ от стены здания.
## ЗЕРКАЛО ConstructionSite.WORK_PAD, а не ссылка на него: Building.gd
## предзагружает Worker.tscn, поэтому preload ConstructionSite.gd отсюда
## замкнул бы цикл Worker → ConstructionSite → Building → Worker.tscn.
## Меняешь одно — поменяй и второе (оба числа названы одинаково)
const BUILD_STAND_PAD := 0.25

func _process_build(delta: float) -> void:
	if build_target == null or not is_instance_valid(build_target):
		build_target = null
		state = State.IDLE
		return
	var dir := build_target.global_position - global_position
	dir.y = 0.0
	var dist := dir.length()
	# СТЕНА, А НЕ ОПИСАННАЯ ОКРУЖНОСТЬ. Раньше порог считался как
	# maxf(size.x, size.z) * 0.5 + 1.6, то есть рабочий вставал в 1.6 м от
	# РАДИУСА КРУГА вокруг здания — с короткой стороны барака это больше двух
	# метров от стены, и молоток стучал по воздуху («стоит на расстоянии»)
	var edge: float = _build_edge(dir)
	# ── ПРИХОД НА СТРОЙКУ ЗАЩЁЛКИВАЕТСЯ ──────────────────────────
	# Жалоба владельца: «второй рабочий подходит, встаёт рядом и
	# визуально ничего не делает». Здесь была КАЧЕЛЯ, та же самая, что
	# ловилась у секторов вокруг здания (см. Unit._ring_done): оба рабочих
	# идут в ОДНУ точку у стены, разбор наложения отталкивает второго на
	# полметра — и тем самым выводит его ЗА порог прихода. Дальше он
	# СНИМАЛ себя с артели (remove_builder) и шёл обратно — то есть и стройку
	# не ускорял, и анимацию имел ходьбы, а не молотка.
	# Защёлка взводится в момент прихода, а снимается только настоящим
	# уходом со стройки (втрое дальше порога) или новым приказом:
	# толчок соседа стройку больше не рвёт
	var leave: float = edge + BUILD_ARRIVE_PAD * (3.0 if _build_settled else 1.0)
	if dist > leave:
		_build_settled = false
		# Ещё идём к стройке
		if build_target.has_method("remove_builder"):
			build_target.remove_builder(self)
		var ndir := dir / maxf(dist, 0.001)
		_facing  = ndir
		velocity = ndir * move_speed
		# ── ДЕТЕКТОР ЗАЦИКЛИВАНИЯ РАБОТАЕТ И ЗДЕСЬ (см. Unit._tick_stuck) ────
		# Дорога на стройку идёт через тот же `_move_blocked`, то есть обход
		# стволов на ней есть — а признать себя наматывающим круги было нечем:
		# детектор жил в `_process_move`, куда эта ветка не заходит вовсе.
		# Рабочий мог обходить один комель по кругу до конца партии
		_tick_stuck(delta, dist)
		# Шаг через _move_blocked: он обходит озеро ПО БЕРЕГУ. Раньше шаг в воду
		# просто отбрасывался, и рабочий, у которого стройка за озером, замирал
		# у кромки навсегда
		_move_blocked(velocity * delta)
		return
	_reset_stuck()
	# Пришли: стоим и машем молотком
	_build_settled = true
	velocity = Vector3.ZERO
	if build_target.has_method("add_builder"):
		build_target.add_builder(self)
	# ── ДОБОР ВПЛОТНУЮ УЖЕ НА РАБОТЕ ────────────────────────────────────────
	# Ровно тот же приём, что и у жилы (_process_gather): приход засчитан щедро,
	# а стоять рабочий обязан у самой стены. Шаг крошечный и velocity не трогает,
	# поэтому анимация остаётся «молоток», а не «бежит», и расталкиванию соседей
	# это не мешает — поправка расталкивания больше этого шага
	var stand: float = edge + BUILD_STAND_PAD
	if dist > stand + SLOT_SETTLE:
		_facing = dir / maxf(dist, 0.001)
		_move_blocked(_facing * (SETTLE_SPEED * delta))

## Расстояние от центра стройки до её стены по направлению dir.
## Считает сама площадка (ConstructionSite.edge_distance) — там же, где
## размечается work_position, поэтому порог и точка стояния не разъезжаются.
## Запасная ветка — для целей без этого метода (обычное здание, стенд)
func _build_edge(dir: Vector3) -> float:
	if build_target.has_method("edge_distance"):
		return float(build_target.edge_distance(dir))
	var bs: Vector3 = build_target.build_size
	return maxf(bs.x, bs.z) * 0.5

# Тип ресурса, с которым сейчас работаем (цель добычи приоритетнее груза)
func _work_res_type() -> int:
	if gather_target != null and is_instance_valid(gather_target):
		return gather_target.resource_type
	return carrying_type

## Ресурс, которым рабочий занят прямо сейчас (добывает или несёт на склад),
## иначе -1. Публичный — читает HUD для счётчика "рабочих на ресурсе" в
## карточке ресурсной панели; вызывается редко (раз в секунду по таймеру),
## так что обход group("player_units") в HUD допустим — это не горячий путь
func active_resource_type() -> int:
	if state == State.GATHERING or state == State.RETURNING:
		return _work_res_type()
	return -1

## К КАКОМУ РЕСУРСУ РАБОЧИЙ ПРИПИСАН — независимо от того, что он делает
## ПРЯМО СЕЙЧАС. В отличие от active_resource_type(), которая отвечает только
## за два состояния из четырёх, эта видит и того, кто ИДЁТ к жиле: за рейс
## рабочий большую часть времени именно шагает, и по «сиюминутному» состоянию
## бригада из пяти человек выглядела то занятой, то пустой (см. HUD-приток).
## -1 — не добытчик: получил прямой приказ, строит, дерётся
func assigned_resource_type() -> int:
	if _gather_res_type >= 0:
		return _gather_res_type
	if carrying_amount > 0.0:
		return carrying_type
	return active_resource_type()

# Выбор анимации Pawn по состоянию: инструмент при добыче, груз при переноске
func _update_sprite_anim() -> void:
	if _pawn_sprite == null:
		super._update_sprite_anim()
		return
	var want := "idle"
	match state:
		State.BUILDING:
			# У самой стройки — МОЛОТОК, по дороге к ней — обычный бег
			# ПО ФАКТУ ПЕРЕМЕЩЕНИЯ, А НЕ ПО velocity: velocity — это
			# НАМЕРЕНИЕ идти, и у рабочего, вставшего вплотную к срубу, оно
			# остаётся ненулевым. Это и есть жалоба «бегут на месте вместо
			# анимации молотка» — та же грабля, что уже ловилась у пехоты
			# МОЛОТОК — ТОЛЬКО ПОСЛЕ ПРИХОДА (заказ 10.09.2026): пока рабочий
			# идёт к площадке, играет ходьба; защёлка _build_settled взводится
			# у самой стены (_process_build). Прежнее «стоит — значит молоток»
			# давало удар киянкой на месте в первый кадр приказа («забивает
			# гвозди в воздух»): окно замера хода ещё пусто
			want = "build" if _build_settled else "walk"
		State.GATHERING:
			# ── РАЗДЕЛКА ОВЦЫ — ВСЕГДА НОЖ, И ЭТО НЕ СОВПАДЕНИЕ ──────────────
			# Лента выбиралась по РЕСУРСУ (_work_res_type), а он у режущего
			# овцу совпадал с едой лишь потому, что фаза переноски выставляла
			# carrying_type = FOOD. Разделка СВОЕЙ овцы на выпасе такой фазы
			# не проходит вовсе (приказ идёт сразу в KILL), и рабочий махал
			# ТОПОРОМ. Спрашиваем сам род работы, а не её побочный признак
			if _sheep_phase == SheepPhase.KILL or _sheep_phase == SheepPhase.BUTCHER:
				want = "harvest"
			else:
				match _work_res_type():
					Constants.RESOURCE_WOOD:
						want = "chop"      # ТОПОР
					Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE:
						want = "mine"      # КИРКА
					_:
						want = "harvest"   # нож (еда/вода)
		State.RETURNING:
			# ── ОВЦУ НЕСУТ НА ГОЛОВЕ, А НЕ КУСКОМ МЯСА (заказ 10.09.2026) ──
			# На время переноски самой овцы лента груза не нужна вовсе: овца
			# едет отдельным спрайтом над головой (Sheep.carry_to), а
			# «Pawn_Run Meat» рисовал ЕЩЁ и кусок мяса в руках
			if _sheep_phase == SheepPhase.CARRY:
				want = "walk"
			else:
				match carrying_type:
					Constants.RESOURCE_WOOD:
						want = "carry_wood"
					Constants.RESOURCE_STONE:
						# Отдельный лист камня есть не во всех цветовых наборах —
						# где его нет, остаётся прежний «мешок» carry_gold
						want = "carry_stone" if _has_anim("carry_stone") else "carry_gold"
					Constants.RESOURCE_GOLD:
						want = "carry_gold"
					Constants.RESOURCE_FOOD:
						want = "carry_meat"
					_:
						want = "walk"
		State.MOVING:
			want = "walk"
		_:
			want = "walk" if moved_recently() else "idle"
	# Через _set_anim: вид бойца живёт числами в Unit, узел спрайта в общей
	# отрисовке не трогается вовсе (см. Unit._look_bind)
	if want != _anim_name:
		_set_anim(want)

## Переопределяет Unit.tick_physics (см. шапку там же — централизованный тик
## через GameManager, метод больше не движковая нотификация)
func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	# С грузом рабочий идёт медленнее (walk_speed_loaded из конфига)
	move_speed = walk_speed_loaded if state == State.RETURNING else walk_speed_empty
	var wt := _work_res_type()
	if _axe:
		_axe.visible = (state == State.GATHERING and wt == Constants.RESOURCE_WOOD)
	if _pickaxe:
		_pickaxe.visible = (state == State.GATHERING and
				(wt == Constants.RESOURCE_GOLD or wt == Constants.RESOURCE_STONE))
	if _cargo_indicator:
		_cargo_indicator.visible = (state == State.RETURNING and carrying_amount > 0.0
				and _pawn_sprite == null)   # у Pawn груз виден в самой анимации
		if _cargo_indicator.visible:
			_update_cargo_color()

	# ── СТРОКА ЯДРА АРМИИ ПИШЕТСЯ И В «РАБОЧИХ» СОСТОЯНИЯХ ─────────────────
	# Здесь стоял GameManager.unit_grid.update(self). После перехода на плоскую
	# сетку (Фаза 2) этот метод — ЗАГЛУШКА: сетка собирается из строк целиком
	# раз в кадр. А строку рабочего в этих трёх ветках не писал никто: базовый
	# tick_physics с его write_pose вызывается только в ветке `else`.
	#
	# Пока по строкам считались лишь соседи, это выглядело как «рабочий иногда
	# стоит не в той ячейке». В Фазе 4 из строки стал браться и КАДР ОТРИСОВКИ —
	# и баг вылез в полный рост: логика уходила к дереву, а спрайт оставался на
	# точке последней записи, то есть у замка, и махал молотком по воздуху.
	# В конце работы боец «телепортировался» — это первая запись строки после
	# возврата в обычное состояние.
	#
	# Рабочий в этих состояниях двигается сам (подход к слоту, доводка
	# SETTLE_SPEED, ход к точке сдачи), поэтому писать надо КАЖДЫЙ тик, а не по
	# порогу
	# ── «Я РАБОТАЮ» — РАЗРЕШЕНИЕ СТОЯТЬ ТЕСНЕЕ ──────────────────────────────
	# Заказ владельца: у одного дерева или у кучи руды бригада должна слипаться,
	# накладываясь примерно на треть спрайта. Признак читает пакетный разбор
	# наложений (ArmySoA.batch_separation, F_WORKING), он же его и единственный
	# читатель. Пишется признак ЗДЕСЬ, в одном месте на все состояния, — иначе
	# его пришлось бы снимать в каждом приказе, и один забытый путь оставил бы
	# бойца «работающим» навсегда
	var working: bool = state == State.GATHERING or state == State.BUILDING
	if working != _soa_working and _soa >= 0:
		_soa_working = working
		GameManager.army.set_flag(_soa, _Army.F_WORKING, working)

	# ── ОКНО ЗАМЕРА РАБОТАЕТ И В «РАБОЧИХ» СОСТОЯНИЯХ ───────────────
	# Две жалобы владельца с ОДНОЙ причиной: «рабочие, неся ресурсы в
	# замок, идут спиной вперёд» и «на стройке бегут на месте вместо
	# анимации молотка». Оба ответа — и «идёт ли», и «куда» — считает
	# окно замера в базовом tick_physics, а три ветки ниже до него НЕ
	# ДОХОДЯТ вовсе — выходят раньше. Значит, у работающего оно не
	# тикало ни разу: _mv_dir оставался направлением К дереву, пока
	# рабочий едет ОТ него, — и зеркало честно рисовало его спиной.
	# Одного вызова хватает на обе беды и на все три ветки
	_sample_movement()
	if _sheep_phase != SheepPhase.NONE:
		_sync_soa_row()
		_process_sheep(delta)
		if state == State.GATHERING:
			_animate_chop(delta)     # нож — тем же замахом
		return
	if state == State.BUILDING:
		_sync_soa_row()
		_process_build(delta)
		if _build_settled:
			_animate_chop(delta)     # тот же замах — только молотком, и только у стены
	elif state == State.GATHERING:
		_sync_soa_row()
		_process_gather(delta)
		_animate_chop(delta)
	elif state == State.RETURNING:
		_sync_soa_row()
		_process_return(delta)
		# РАСТАЛКИВАНИЯ СОЮЗНИКОВ ЗДЕСЬ БОЛЬШЕ НЕТ (см. шапку Unit.gd). Бригада,
		# сходящаяся к одной точке сдачи, теперь просто слипается в кучу и
		# замирает — вместо того чтобы вечно переталкиваться у склада
	else:
		# Цель исчезла, пока рабочий к ней шёл (дерево дорубил сосед) —
		# перенацеливаемся на ближайшее живое дерево, а не идём к пустому месту
		if state == State.MOVING and _gather_res_type >= 0 \
				and (gather_target == null or not is_instance_valid(gather_target)
					or gather_target.remaining <= 0.0):
			gather_target = null
			_auto_find_resource(_gather_res_type)
			return
		# ДОШЁЛ ДО СВОЕГО СЛОТА — БЕРЁМСЯ ЗА ИНСТРУМЕНТ.
		#
		# Порог прихода у базового класса — 30 см, а рабочего в бригаде
		# постоянно подталкивают соседи: в такой круг он мог не попасть НИКОГДА.
		# Отсюда вечный цикл «подошёл — приказ заново — подошёл», то есть
		# топтание у жилы без начала добычи. Здесь порог свой, вдвое шире
		# (SLOT_ARRIVE), и этого хватает, чтобы толчея не мешала приходу.
		#
		# ПРОВЕРЯЕТСЯ ИМЕННО СЛОТ, А НЕ ДИСТАНЦИЯ ДО ЖИЛЫ. Соблазн начать
		# работу «как только дотянулся» проверен и отброшен: бригада подходит
		# к камню с одной стороны, границу дотягивания все пересекают почти в
		# одной точке и там же встают — замер показал просвет 0.32 м вместо
		# положенных 1.1 м по разметке кольца. Свой слот разводит их по кругу
		if state == State.MOVING and _at_gather_slot() and _in_work_reach():
			velocity      = Vector3.ZERO
			state         = State.GATHERING
			_gather_timer = _cycle_time()
			_wake_process()
			return
		super.tick_physics(delta, prof, bm, bonus_ver)
		# ── ЗАСТРЯЛ ПО ДОРОГЕ К СВОЕЙ ТОЧКЕ — БЕРЁМ ДРУГУЮ ─────────────────
		# Первая ступень лечения застревания — выключить стволы (см.
		# Unit.TRUNK_IGNORE_SEC), и почти всегда её хватает. Эта ступень
		# ВТОРАЯ и срабатывает только когда первая уже не помогла: столько
		# проверок подряд без продвижения означает, что держит НЕ ствол —
		# чужое тело, край воды, край карты, — и выключать нечего. Тогда
		# меняется сама цель: место на кольце, а не способ до него дойти.
		# Порог в тактах, а не в кадрах: такт детектора STUCK_CHECK_SEC
		if _stuck_streak >= STUCK_REPATH_TICKS and state == State.MOVING \
				and gather_target != null and is_instance_valid(gather_target):
			_reset_stuck()
			move_target = gather_target.claim_slot(self, true)
			_gather_slot_valid = true
		if state == State.IDLE and gather_target != null and is_instance_valid(gather_target):
			if _in_work_reach():
				state         = State.GATHERING
				_gather_timer = _cycle_time()
				_wake_process()
			else:
				# ЗАСТРЯЛ, НЕ ДОЙДЯ. Раньше здесь не было НИЧЕГО: рабочий с
				# назначенной жилой стоял столбом до конца партии — и в счётчик
				# бездельников не попадал, потому что цель у него формально есть.
				# Ровно это и выглядит как «встал в куче камней и не работает».
				# Подходим заново, но не чаще раза в секунду, чтобы не сыпать
				# приказами каждый кадр.
				#
				# ── НО НЕ БЕСКОНЕЧНО, И ЭТО ВТОРАЯ ПОЛОВИНА ЛЕЧЕНИЯ ─────────────
				# Повтор был ВЕЧНЫМ. Если до жилы не дойти в принципе — ствол за
				# другими стволами, место занято, дорога перекрыта — рабочий раз в
				# секунду получал приказ, делал шаг, упирался, возвращался в IDLE и
				# получал его снова. Это и есть «битый Idle с тиком»: работы нет,
				# в счётчик простаивающих он не попадает (цель-то назначена), и
				# дёргается так до конца партии.
				#
				# Теперь попытки считаются. Исчерпал — жила признаётся недоступной,
				# ИСКЛЮЧАЕТСЯ из поиска и ищется замена в РАСШИРЕННОМ радиусе
				# (заказ владельца: «ищет доступное дерево в чуть большем радиусе»).
				# Не нашлось и там — рабочий честно встаёт бездельником, попадает в
				# счётчик и ждёт приказа, а не топчется
				_approach_retry -= delta
				if _approach_retry <= 0.0:
					_approach_retry = 1.0
					_approach_fails += 1
					if _approach_fails >= APPROACH_GIVE_UP:
						var t: int = _gather_res_type
						_blocked_target = gather_target
						_free_slot()
						gather_target = null
						_approach_fails = 0
						_auto_find_resource(t)
					else:
						command_gather(gather_target)

# ── СКОРОСТЬ ДОБЫЧИ ПО ТИПУ РЕСУРСА ──────────────────────────────────────────
## РУБКА ЛЕСА БЫСТРЕЕ НА 15%. Дерево — самый ходовой ресурс: он уходит и на
## войска, и на постройки, и на улучшения, поэтому лесопилка узким местом быть
## не должна. Камень и золото добываются в прежнем темпе — их ценность как раз
## в том, что достаются они медленнее.
## Пень при этом остаётся на карте, как и раньше (см. ResourceNode._show_stump)
const WOOD_SPEEDUP := 0.85

## НИЖЕ ЭТОГО ЦИКЛ НЕ ОПУСКАЕТСЯ НИКАКИМИ УЛУЧШЕНИЯМИ. Цикл — это ещё и время
## между взмахами инструмента: на десятых долях секунды рабочий перестаёт рубить
## и начинает дрожать, а сама добыча превращается в струю ресурса. Потолок
## прокачки лучше упереть здесь, в одном месте, чем ловить его балансом цен
const MIN_CYCLE_TIME := 1.10

## Длительность одного цикла добычи с учётом типа ресурса и веток кузницы.
##
## bonus_gather — СЕКУНДЫ ДОЛОЙ (см. unit_stats_config.BONUS_KEYS): в конфиге он
## записан положительным, как и все прочие бонусы, а вычитается здесь. Множитель
## леса применяется ДО вычитания — иначе одна и та же ветка давала бы на дереве
## меньше секунд, чем на камне, хотя в описании узла написано одно число
func _cycle_time() -> float:
	var t: float = gather_time
	if _work_res_type() == Constants.RESOURCE_WOOD:
		t *= WOOD_SPEEDUP
	t -= GameManager.unit_bonus(faction, stat_id, "bonus_gather") + vet_gather
	return maxf(t, MIN_CYCLE_TIME)

## Сколько ресурса рабочий уносит за одну ходку. База из конфига плюс ветка
## вместимости в кузнице (bonus_carry)
func carry_capacity() -> float:
	return maxf(1.0, gather_amount
		+ GameManager.unit_bonus(faction, stat_id, "bonus_carry"))

## Насколько близко к своей точке на кольце нужно подойти, чтобы считать, что
## рабочий на месте. Заметно шире базовых 30 см: в бригаде соседи всё время
## подталкивают друг друга, и слишком узкий круг просто не достигается
## Сколько тактов детектора зацикливания подряд без продвижения означает,
## что пора менять САМУ ТОЧКУ, а не способ до неё дойти (см. tick_physics).
## Четыре такта по STUCK_CHECK_SEC = две секунды: выключение стволов длится
## полторы, то есть первая ступень уже отработала и не помогла
const STUCK_REPATH_TICKS := 4
const SLOT_ARRIVE := 0.6

## Насколько точно рабочий доводит себя до слота, уже работая (см. _process_gather).
## Меньше SLOT_ARRIVE: приход засчитывается щедро, а стоять он всё равно будет
## там, где инструмент достаёт до текстуры
const SLOT_SETTLE := 0.12
## Скорость этого доборного шага, м/с. Заведомо медленнее ходьбы: движение
## не читается как «рабочий куда-то пошёл»
const SETTLE_SPEED := 0.8

## Слот у жилы выдан и move_target — это он. Иначе добирать не к чему
var _gather_slot_valid: bool = false

## Рабочий стоит на своём месте у жилы (move_target — это и есть слот кольца,
## его выдал ResourceNode.claim_slot)
func _at_gather_slot() -> bool:
	var dx: float = global_position.x - move_target.x
	var dz: float = global_position.z - move_target.z
	return dx * dx + dz * dz < SLOT_ARRIVE * SLOT_ARRIVE

## Дотягивается ли инструмент до назначенной жилы прямо сейчас.
## Порог берётся У САМОЙ ЖИЛЫ (ResourceNode.work_reach) и потому согласован
## с разметкой кольца слотов: крупный самородок раздвигает и кольцо, и руку
## Вопрос задаётся САМОЙ ЦЕЛИ (ResourceNode.in_work_reach): у одиночного ресурса
## это по-прежнему расстояние до центра, у кучи руды — попадание в её зону.
## У кучи «центра» в осмысленном виде нет: она вытянута, и мерить до середины
## значило бы объявить рабочего на дальнем торце не дотянувшимся
func _in_work_reach() -> bool:
	if gather_target == null or not is_instance_valid(gather_target):
		return false
	return gather_target.in_work_reach(global_position)

## Обратный отсчёт до повторной попытки подойти к жиле
var _approach_retry: float = 0.0

## Сколько раз подряд рабочий пробует дойти до назначенной жилы, прежде чем
## признать её недоступной. Попытка идёт раз в секунду (см. _approach_retry),
## то есть четыре попытки — это четыре секунды: заметно дольше любой толчеи у
## камня и заметно короче «до конца партии»
const APPROACH_GIVE_UP := 4
var _approach_fails: int = 0

## Жила, до которой дойти не удалось. Исключается из ближайшего поиска замены —
## иначе поиск «ближайшего» немедленно вернул бы её же, и цикл пошёл бы заново.
## Ссылка живёт ровно один поиск и тут же гасится
var _blocked_target: ResourceNode = null

## Во сколько раз шире ищется замена, когда ближняя жила оказалась недоступна.
## Именно «чуть шире», а не «по всей карте»: бригада не должна молча уходить за
## полкарты — это ровно та болезнь, от которой авто-цикл и лечили (см. шапку
## _auto_find_resource)
const WIDE_SEARCH_SCALE := 2.5

## ТЕМП ВЗМАХА. Один полный оборот синуса = один удар: по нему заводятся И
## дрожь дерева, И звук топора, поэтому они синхронны по построению.
##
## Было 3.5 (≈0.56 удара в секунду), затем 4.55 (≈0.72). Сейчас 6.30 — это
## РОВНО ОДИН УДАР В СЕКУНДУ (TAU / 6.30 ≈ 1.0 с на полный взмах) и ещё +38% к
## плотности стука: заказ владельца — «звуков топора очень жиденько, хочу
## слышать больше».
##
## ПОЧЕМУ ПОДНИМАЕТСЯ ИМЕННО ТЕМП, А НЕ ЛИМИТЫ ЗВУКА. Ограничитель категории
## (AudioManager.SFX_LIMITS.chop) при пятерых рабочих не срабатывал вовсе:
## пятеро на 0.72 Гц дают ~3.6 удара в секунду, а окно gap = 0.07 пропускает
## четырнадцать. То есть звуков было мало не потому, что их резали, а потому,
## что их СТОЛЬКО И БЫЛО — рубили редко. Лимиты подняты следом (см. там же), но
## они лишь снимают потолок для большой бригады, а слышимую плотность у малой
## задаёт вот это число.
##
## ВЫШЕ ПОДНИМАТЬ НЕЛЬЗЯ: секунда на замах — это ещё замах, а на 8+ инструмент
## начинает дрожать вместо того, чтобы рубить.
##
## На СКОРОСТЬ ДОБЫЧИ это по-прежнему не влияет ВООБЩЕ — она считается таймером
## цикла (_cycle_time), а не числом взмахов. Владелец просил темп добычи не
## трогать, и он не тронут: меняется только «плотность» отдачи, то есть сколько
## раз за один и тот же цикл дёрнется дерево и звякнет топор
const CHOP_SWING_RATE := 6.30

## ТЕМП УДАРА КИРКОЙ — ОТДЕЛЬНЫЙ, И ОН НЕ МЕНЯЛСЯ (прежние 4.55).
## Раньше это была одна константа на весь инструмент, и ускорение топора
## автоматически ускорило бы и кирку — а заказ был именно про лес («больше
## звуков рубящего леса»). По делу они и не должны совпадать: удар киркой по
## камню тяжелее взмаха топором, и на секундном темпе рудник начинает звучать
## отбойным молотком. Молоток строителя идёт по этой же, спокойной ставке
const MINE_SWING_RATE := 4.55

## Темп замаха для того инструмента, который сейчас в руках
func _swing_rate() -> float:
	# Стройка проверяется ПЕРВОЙ: у строителя gather_target пуст, и
	# _work_res_type() отдал бы тип ГРУЗА (по умолчанию — дерево), то есть
	# молоток невольно поехал бы по ставке топора
	if state == State.BUILDING:
		return MINE_SWING_RATE
	return CHOP_SWING_RATE if _work_res_type() == Constants.RESOURCE_WOOD \
		else MINE_SWING_RATE

func _animate_chop(delta: float) -> void:
	var prev := _chop_time
	_chop_time += delta * _swing_rate()
	var swing := -30.0 + sin(_chop_time) * 40.0
	if _axe and _axe.visible:
		_axe.rotation_degrees.x = swing
	if _pickaxe and _pickaxe.visible:
		_pickaxe.rotation_degrees.x = swing
	# Момент касания топора: раз за оборот синуса дёргаем дерево (см. ResourceNode.shake)
	if floori(prev / TAU) != floori(_chop_time / TAU):
		if gather_target != null and is_instance_valid(gather_target):
			if gather_target.resource_type == Constants.RESOURCE_WOOD:
				gather_target.shake()
			# ЗВУК РАБОТЫ — РОВНО В МОМЕНТ КАСАНИЯ инструмента, а не по таймеру
			# добычи: иначе стук расходится с замахом. Слышно только вблизи —
			# 3D-звук плюс слушатель в точке фокуса камеры (см. AudioManager)
			_play_work_sound(gather_target.resource_type)

## Звук инструмента по типу ресурса
func _play_work_sound(res_type: int) -> void:
	var cat := ""
	match res_type:
		Constants.RESOURCE_WOOD:  cat = "chop"
		Constants.RESOURCE_GOLD:  cat = "mine_gold"
		Constants.RESOURCE_STONE: cat = "mine_stone"
		_: return
	AudioManager.play_3d(cat, global_position)

func _process_gather(delta: float) -> void:
	if gather_target == null or not is_instance_valid(gather_target) or gather_target.remaining <= 0.0:
		var search_type := _gather_res_type
		if gather_target != null and is_instance_valid(gather_target):
			search_type = gather_target.resource_type
		elif search_type < 0:
			search_type = carrying_type
		gather_target = null
		_auto_find_resource(search_type)
		return
	velocity      = Vector3.ZERO
	# ── ДОБОР ДО СВОЕЙ ТОЧКИ ПРЯМО ВО ВРЕМЯ РАБОТЫ ───────────────────────────
	# Порог прихода намеренно широкий (SLOT_ARRIVE = 0.6 м): узкий круг
	# рабочий в бригаде не достигает вовсе, его всё время подталкивают соседи.
	# Но «пришёл» и «стоит там, где надо» — разные вещи: засчитав приход на
	# полметра раньше, рабочий так и рубил в полуметре от ствола.
	#
	# Поэтому уже НА РАБОТЕ он тихо подбирается к своей точке. Скорость
	# крошечная, движение незаметно глазом, зато через секунду топор ложится
	# ровно на комель. Расталкиванию это не мешает: шаг меньше его поправки
	if _gather_slot_valid:
		var back := move_target - global_position
		back.y = 0.0
		var bd := back.length()
		if bd > SLOT_SETTLE:
			_move_blocked(back / bd * (SETTLE_SPEED * delta))
	# ── ВНУТРЬ НАВАЛА РАБОЧИЙ НЕ ЗАХОДИТ ────────────────────────────────────
	# Приказ внутрь не выдаётся никогда: цель добычи у кучи — точка на ВНЕШНЕМ
	# периметре (MineCluster.claim_slot). Но затолкать рабочего внутрь могут и
	# чужие силы — расталкивание соседями, обход ствола, подошедшая бригада.
	# Тогда он тихо выдавливается наружу тем же незаметным шагом, что и доводка
	# до слота. Именно этот случай и выглядел как «залез в текстуру и дёргается»
	var push := gather_target.outward_push(global_position)
	if push != Vector3.ZERO:
		_move_blocked(push * (SETTLE_SPEED * 2.0 * delta))
	_gather_timer -= delta
	if _gather_timer <= 0.0:
		if carrying_amount == 0.0:
			var taken       := gather_target.extract(carry_capacity())
			carrying_amount  = taken
			carrying_type    = gather_target.resource_type
		var drop_off := GameManager.get_nearest_dropoff(faction, global_position)
		if drop_off:
			move_target = drop_off.global_position
			state       = State.RETURNING
		else:
			_gather_timer = _cycle_time()

func _process_return(delta: float) -> void:
	var drop_off := GameManager.get_nearest_dropoff(faction, global_position)
	if drop_off == null:
		state = State.IDLE
		return
	var dir := drop_off.global_position - global_position
	dir.y   = 0
	if dir.length() < 1.8:
		velocity = Vector3.ZERO
		# gather_resource, а не add_resource: сдача груза — это ДОБЫЧА, и она
		# обязана попасть в счётчик, по которому HUD считает постоянный приток
		ResourceManager.gather_resource(faction, carrying_type, carrying_amount)
		carrying_amount = 0.0
		if gather_target and is_instance_valid(gather_target) and gather_target.remaining > 0.0:
			# ОБРАТНО — В СВОЙ СЛОТ НА КОЛЬЦЕ, А НЕ В ЦЕНТР ЖИЛЫ.
			# Здесь стояло gather_target.global_position, то есть приказ «влезь
			# внутрь спрайта камня». К жиле рабочий шёл правильно (command_gather
			# ведёт на кольцо, см. ResourceNode.claim_slot), а ПОСЛЕ КАЖДОЙ
			# РАЗГРУЗКИ возвращался ровно в её середину — и топтался там вместе
			# со всей бригадой. Именно этот цикл и выглядел как «рабочие залезли
			# в текстуру золота и дёргаются в одной точке»
			move_target = gather_target.claim_slot(self)
			_gather_slot_valid = true
			state       = State.MOVING
		else:
			# Дерево срублено в пень, пока рабочий нёс груз. Не встаём столбняком:
			# сразу ищем ближайшее живое дерево того же типа и идём рубить его —
			# клик игрока для продолжения работы не нужен
			var next_type := _gather_res_type if _gather_res_type >= 0 else carrying_type
			gather_target = null
			_auto_find_resource(next_type)
	else:
		var ndir := dir.normalized()
		_facing  = ndir
		velocity = ndir * move_speed
		# Тот же детектор, что и на пути к стройке: обратная дорога к складу
		# идёт мимо тех же деревьев (см. Unit._tick_stuck)
		_tick_stuck(delta, dir.length())
		# ВОДА ПРОВЕРЯЕТСЯ И НА ОБРАТНОМ ПУТИ. Здесь стояла прямая интеграция
		# без единой проверки: гружёный рабочий шёл к складу НАПРЯМУЮ ЧЕРЕЗ
		# ОЗЕРО, хотя к ресурсу шёл в обход. _move_blocked ведёт его по берегу
		_move_blocked(velocity * delta)
