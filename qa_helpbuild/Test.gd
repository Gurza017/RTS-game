extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД: ВТОРОЙ РАБОЧИЙ НА УЖЕ ИДУЩЕЙ СТРОЙКЕ
## ═══════════════════════════════════════════════════════════════════════════
## ЖАЛОБА ВЛАДЕЛЬЦА (повторно): «второй рабочий встаёт в ступор при помощи на
## стройке». Ровно эта беда уже чинилась однажды — защёлкой прихода
## (`Worker._build_settled`), — и вернулась.
##
## ── ЗАЧЕМ ОТДЕЛЬНЫЙ ЗОНД, А НЕ ЧТЕНИЕ КОДА ────────────────────────────────
## У жалобы ДВА независимых подозреваемых, и по коду их не различить:
##   1. ЛОГИКА стройки — приняв приказ, второй рабочий не встаёт в артель;
##   2. НАВЕДЕНИЕ — приказ до него просто не доходит, потому что правый клик
##      по стройплощадке забирает не её, а РАБОЧЕГО, который на ней стоит.
##      Тогда `_try_join_construction` не срабатывает вовсе, приказ вырождается
##      в «идти в точку», и рабочий честно доходит и встаёт. На экране это
##      неотличимо от «ступора».
##
## Блок A проверяет логику НАПРЯМУЮ (минуя мышь), блок B — наведение тем же
## `_pick_at`, каким его считает игра. Красный ровно в одном из блоков и
## называет виновного.
##
##   godot --headless --path . res://qa_helpbuild/Test.tscn

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")

var main = null
var sm = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	# ── СТОРОЖ ─────────────────────────────────────────────────────────────
	# Ошибка ВНУТРИ корутины убивает её молча: сцена остаётся жить, вывод в
	# трубу буферизован и наружу не попадает вовсе, и прогон висит минутами без
	# единого признака. Поймано на себе: `sm.on_selection_changed()` (метод
	# живёт у GameManager, не у SelectionManager) уронил `_run` после блока B,
	# и два прогона молча жгли машину
	var t := Timer.new()
	t.wait_time = 240.0
	t.one_shot = true
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(t)
	t.timeout.connect(func():
		print("\n=== ЗОНД НЕ УЛОЖИЛСЯ В СРОК, пройдено %d, провалов: %d ==="
			% [_pass, _fail])
		get_tree().quit(2))
	t.start()
	call_deferred("_run")

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _spawn_worker(at: Vector3) -> Unit:
	var u: Unit = load("res://scenes/units/Worker.tscn").instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _state_name(u: Unit) -> String:
	match u.state:
		Unit.State.IDLE: return "IDLE"
		Unit.State.MOVING: return "MOVING"
		Unit.State.ATTACKING: return "ATTACKING"
		Unit.State.GATHERING: return "GATHERING"
		Unit.State.BUILDING: return "BUILDING"
		Unit.State.RETURNING: return "RETURNING"
	return "?" + str(u.state)

func _run() -> void:
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	sm = main.get("selection_manager")
	for node in get_tree().get_nodes_in_group("all_units"):
		(node as Node).queue_free()
	await pframes(6)

	var spot := Vector3(24.0, 0.0, 18.0)
	var site = _CSite.new()
	site.faction     = Constants.FACTION_PLAYER
	site.target_id   = "barracks"
	site.target_name = "Бараки"
	site.build_size  = _UCfg.building_size("barracks")
	site.build_time  = 600.0          # долгая, чтобы не достроилась под замером
	main.world_add(site)
	site.global_position = Vector3(spot.x, GameManager.get_terrain_height(spot.x, spot.z), spot.z)
	await pframes(6)

	# ═══ БЛОК A: ЛОГИКА, МИНУЯ МЫШЬ ═══════════════════════════════════════
	print("\n═════ A. ЛОГИКА АРТЕЛИ (приказ отдаётся напрямую) ═════")
	var a: Unit = _spawn_worker(spot + Vector3(-6.0, 0.0, 0.0))
	(a as Worker).command_build(site)
	await pframes(180)
	verdict("A1 первый рабочий встал на стройку",
		a.state == Unit.State.BUILDING and site.builder_count() >= 1,
		"состояние %s, строителей %d" % [_state_name(a), site.builder_count()])

	# Второй идёт с ДРУГОЙ стороны: work_position отдаёт точку по стороне
	# подхода, и накладываться они не должны
	var b: Unit = _spawn_worker(spot + Vector3(6.0, 0.0, 2.0))
	(b as Worker).command_build(site)
	await pframes(180)
	verdict("A2 второй рабочий тоже встал на стройку",
		b.state == Unit.State.BUILDING and site.builder_count() >= 2,
		"состояние %s, строителей %d, защёлка=%s"
		% [_state_name(b), site.builder_count(), str(b._build_settled)])

	# Приказ ТЕМ ЖЕ ПУТЁМ, каким его отдаёт диспетчер правого клика
	var c: Unit = _spawn_worker(spot + Vector3(0.0, 0.0, 7.0))
	sm.selected_units = [c]
	var joined: bool = sm._try_join_construction(site)
	# ── ЖДЁМ ПРИХОД, А НЕ КРУГЛОЕ ЧИСЛО КАДРОВ ────────────────────────────
	# `builder_count` считает ДОШЕДШИХ, а состояние BUILDING выставляется в миг
	# приказа. Третий рабочий идёт семь метров — при 180 кадрах (3 с) проверка
	# краснела через раз на неизменном коде: это шаткость стенда, а не игры
	await pframes(360)
	verdict("A3 диспетчер клика доводит третьего до артели",
		joined and c.state == Unit.State.BUILDING and site.builder_count() >= 3,
		"принят=%s, состояние %s, строителей %d"
		% [str(joined), _state_name(c), site.builder_count()])

	# ═══ БЛОК B: НАВЕДЕНИЕ ════════════════════════════════════════════════
	# Тот же вопрос, что у qa_keep D1, только цель — СТРОЙПЛОЩАДКА, а
	# заслоняет её СВОЙ ЖЕ рабочий, уже стоящий на ней
	print("\n═════ B. КЛИК ПО СТРОЙКЕ, НА КОТОРОЙ УЖЕ РАБОТАЮТ ═════")
	var cam: Camera3D = main.get("_camera") as Camera3D
	main.focus_camera_on(site.global_position)
	await pframes(8)
	await frames(4)
	# ── КАМЕРУ ЗАМОРАЖИВАЕМ, И ЭТО НЕ ФОРМАЛЬНОСТЬ ────────────────────────
	# Без этого объектив продолжает жить (доводка фокуса, глиссада), и экранная
	# точка, посчитанная один раз, через десять кадров указывает уже в другое
	# место. Ровно на этом зонд трижды «нашёл регрессию»: первый разбор клика
	# брал стройку, а следующий — то пустую траву (цель null), то случайное
	# дерево. Числа противоречили друг другу, потому что мерили РАЗНЫЕ кадры
	main.set_process(false)
	cam.set_process(false)
	await frames(2)
	var mask: int = Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS

	# Прицел — в середину нарисованной части площадки. Высоту берём у КВАДА
	# картинки, а не у коробки: кликают по рисунку
	var quad_h := 1.0
	for ch in site.get_children():
		var mi := ch as MeshInstance3D
		if mi != null and (mi.mesh as QuadMesh) != null and mi.name != "SelectionRing":
			quad_h = maxf(quad_h, (mi.mesh as QuadMesh).size.y)
	var aim: Vector3 = Vector3(site.global_position.x,
		site.global_position.y + site._draw_base_y + quad_h * 0.35,
		site.global_position.z)
	var scr: Vector2 = cam.unproject_position(aim)
	var hit = sm._pick_at(scr, mask).get("target")
	var who: String = "СТРОЙКА" if hit == site else (
		"РАБОЧИЙ" if (hit is Unit) else str(hit))
	verdict("B1 курсор на стройплощадке выбирает ЕЁ, а не рабочего на ней",
		hit == site, "под курсором %s" % who)

	# И то же самое, но целясь в САМЫЙ НИЗ картинки — туда, где игрок обычно
	# и кликает по фундаменту
	var aim2 := Vector3(site.global_position.x,
		site.global_position.y + 0.15, site.global_position.z)
	var scr2: Vector2 = cam.unproject_position(aim2)
	var hit2 = sm._pick_at(scr2, mask).get("target")
	verdict("B2 клик по низу фундамента тоже попадает в стройку",
		hit2 == site, "под курсором %s" % (
			"СТРОЙКА" if hit2 == site else ("РАБОЧИЙ" if (hit2 is Unit) else str(hit2))))

	# ═══ БЛОК C: ВЕСЬ ПУТЬ ПРАВОГО КЛИКА ЦЕЛИКОМ ══════════════════════════
	# Блоки A и B проверяли ЗВЕНЬЯ. Здесь дёргается ровно то, что дёргает мышь
	# игрока, — вместе с настоящей маской клика (order_pick_mask), а она у
	# выделенного РАБОЧЕГО шире: в неё входят ресурсы, то есть деревья вокруг
	# стройки становятся кандидатами наравне с ней
	print("\n═════ C. ПРАВЫЙ КЛИК ЦЕЛИКОМ (как у игрока) ═════")
	# ── ОКРУЖЕНИЕ СТАВИМ САМИ ─────────────────────────────────────────────
	# Первые два прогона этого блока дали РАЗНЫЙ результат на неизменном коде
	# (`<null>` и «ДЕРЕВО»), потому что карта сеется случайно и лес вокруг
	# площадки каждый раз другой. Сценарий, который зависит от окружения,
	# обязан это окружение задавать, иначе он меряет жребий
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn0 := n0 as ResourceNode
		if rn0 != null and is_instance_valid(rn0) \
				and rn0.global_position.distance_to(site.global_position) < 60.0:
			rn0.queue_free()
	await pframes(8)
	var d: Unit = _spawn_worker(spot + Vector3(-9.0, 0.0, 6.0))
	await pframes(4)
	sm.selected_units = [d]
	# Прицел пересчитываем: камера та же, но кандидаты сменились
	scr = cam.unproject_position(aim)
	var clean = sm._pick_at(scr, sm.order_pick_mask()).get("target")
	verdict("C0 без леса вокруг клик берёт стройку", clean == site,
		"под курсором %s" % ("СТРОЙКА" if clean == site
			else ("ДЕРЕВО" if (clean is ResourceNode) else str(clean))))

	# ── ТЕПЕРЬ СТАВИМ ДЕРЕВО РЯДОМ, НО НЕ ПОВЕРХ ──────────────────────────
	# Именно этот случай и живёт в партии: стройка у кромки леса. Дерево
	# СБОКУ не имеет права забирать клик, нацеленный в площадку
	var near_tree := ResourceNode.new()
	near_tree.resource_type = Constants.RESOURCE_WOOD
	near_tree.remaining = 600.0
	near_tree.tree_variant = 2
	main.world_add(near_tree)
	var tx0: float = site.global_position.x + 3.5
	var tz0: float = site.global_position.z + 1.0
	near_tree.global_position = Vector3(tx0, GameManager.get_terrain_height(tx0, tz0), tz0)
	await pframes(10)

	print("  маска клика у выделенного рабочего: %d (общая %d)"
		% [sm.order_pick_mask(), Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS])
	# ── ВСЁ СОСТОЯНИЕ В ОДИН МИГ ──────────────────────────────────────────
	# Прошлые прогоны печатали разные величины в РАЗНЫЕ моменты, и числа
	# начали противоречить друг другу. Снимаем всё сразу, одним кадром
	print("  слой стройки %d (постройки=%d), слой дерева %d (ресурсы=%d)" % [
		site.collision_layer, Constants.LAYER_BUILDINGS,
		near_tree.collision_layer, Constants.LAYER_RESOURCES])
	scr = cam.unproject_position(aim)
	print("  только постройки -> %s | только ресурсы -> %s | полная -> %s" % [
		str(sm._pick_at(scr, Constants.LAYER_BUILDINGS).get("target")),
		str(sm._pick_at(scr, Constants.LAYER_RESOURCES).get("target")),
		str(sm._pick_at(scr, sm.order_pick_mask()).get("target"))])
	# ── ЧТО ЛУЧ ВСТРЕЧАЕТ ПЕРВЫМ ──────────────────────────────────────────
	# `_pick_at` ПРЕКРАЩАЕТ разбор на первом же попадании, которое не
	# разрешается в сущность игры («земля — за ней смотреть нечего»). Если
	# грунт оказывается ближе пластины постройки, дальше цикл не идёт вовсе и
	# цели не будет. Печатаем порядок попаданий обеими масками
	var cam2 := cam
	var ray_from: Vector3 = cam2.project_ray_origin(scr)
	var ray_dir: Vector3 = cam2.project_ray_normal(scr)
	for m_try in [Constants.LAYER_BUILDINGS, Constants.LAYER_RESOURCES,
			sm.order_pick_mask()]:
		var ex: Array[RID] = []
		var line := "  маска %2d: " % int(m_try)
		for _k in range(4):
			var qq := PhysicsRayQueryParameters3D.create(ray_from,
				ray_from + ray_dir * 1000.0)
			qq.collision_mask = int(m_try) & ~Constants.LAYER_UNITS
			qq.exclude = ex
			var hh := cam2.get_world_3d().direct_space_state.intersect_ray(qq)
			if not hh.has("collider"):
				break
			ex.append(hh["rid"])
			var col = hh["collider"]
			var dd: float = (hh["position"] as Vector3).distance_to(ray_from)
			var owner_name := "?"
			var pnt = (col as Node).get_parent() if col is Node else null
			if pnt != null:
				owner_name = pnt.get_class() + ("(СТРОЙКА)" if pnt == site else "")
			line += "%s@%.2f м -> " % [owner_name, dd]
		print(line)
	var hit3 = sm._pick_at(scr, sm.order_pick_mask()).get("target")
	verdict("C1 настоящей маской клик тоже берёт стройку", hit3 == site,
		"под курсором %s" % ("СТРОЙКА" if hit3 == site
			else ("РАБОЧИЙ" if (hit3 is Unit) else ("ДЕРЕВО" if (hit3 is ResourceNode)
			else str(hit3)))))
	sm._handle_right_click(scr)
	await pframes(240)
	verdict("C2 после правого клика рабочий строит",
		d.state == Unit.State.BUILDING and site.builder_count() >= 4,
		"состояние %s, строителей %d, цель стройки=%s"
		% [_state_name(d), site.builder_count(),
			str((d as Worker).build_target == site)])

	# ═══ БЛОК D: РУБИЛ ДЕРЕВО → ОТПРАВИЛИ НА СТРОЙКУ ══════════════════════
	# УТОЧНЕНИЕ ВЛАДЕЛЬЦА: забаговал именно тот рабочий, которого ПЕРЕНАЗНАЧИЛИ
	# С РУБКИ. Это другой сценарий, чем блоки A-C: там рабочий шёл на стройку
	# «с чистого листа», а здесь у него за спиной живая добыча — занятый слот у
	# дерева, возможная ноша и своя ветка тика (Worker переопределяет
	# tick_physics и в GATHERING/RETURNING до базового не доходит).
	#
	# Меряем ДВЕ вещи порознь: принял ли он приказ (состояние) и СДВИНУЛСЯ ЛИ
	# ФИЗИЧЕСКИ. «Ступор» — это именно второе: приказ принят, а тело стоит
	print("\n═════ D. ПЕРЕНАЗНАЧЕНИЕ С РУБКИ НА СТРОЙКУ ═════")
	var tree: ResourceNode = null
	var best := INF
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null or not is_instance_valid(rn):
			continue
		if rn.resource_type != Constants.RESOURCE_WOOD:
			continue
		var dd: float = rn.global_position.distance_to(spot)
		if dd < best:
			best = dd
			tree = rn
	if tree == null:
		verdict("D0 на карте нашлось дерево", false, "деревьев нет")
	else:
		var e: Unit = _spawn_worker(tree.global_position + Vector3(2.0, 0.0, 2.0))
		(e as Worker).command_gather(tree)
		await pframes(240)
		var chopping: bool = e.state == Unit.State.GATHERING \
			or e.state == Unit.State.RETURNING
		verdict("D1 рабочий рубит дерево", chopping,
			"состояние %s, до дерева %.2f м"
			% [_state_name(e), e.global_position.distance_to(tree.global_position)])
		# Переназначаем ТЕМ ЖЕ путём, что и игрок
		sm.selected_units = [e]
		var from_pos: Vector3 = e.global_position
		sm._try_join_construction(site)
		verdict("D2 приказ принят: состояние BUILDING",
			e.state == Unit.State.BUILDING,
			"состояние %s, цель=%s" % [_state_name(e),
				str((e as Worker).build_target == site)])
		# ── СДВИНУЛСЯ ЛИ ОН ВООБЩЕ ────────────────────────────────────────
		await pframes(120)
		var moved2: float = e.global_position.distance_to(from_pos)
		verdict("D3 за две секунды рабочий реально пошёл", moved2 > 1.0,
			"прошёл %.2f м (от дерева %.2f м, до стройки %.2f м)"
			% [moved2, e.global_position.distance_to(tree.global_position),
				e.global_position.distance_to(site.global_position)])
		await pframes(600)
		verdict("D4 дошёл и встал в артель",
			e.state == Unit.State.BUILDING and (e as Worker)._build_settled,
			"состояние %s, защёлка=%s, строителей %d, до стройки %.2f м"
			% [_state_name(e), str((e as Worker)._build_settled),
				site.builder_count(),
				e.global_position.distance_to(site.global_position)])

	# ═══ БЛОК E: ЗАСТРЯВШИЙ В СТВОЛЕ ══════════════════════════════════════
	# ГИПОТЕЗА, ПОДТВЕРЖДЁННАЯ СКРИНШОТОМ ВЛАДЕЛЬЦА: рабочий стоит ВНУТРИ
	# дерева и дёргается на месте. Такой не дойдёт никуда — и «ступор у
	# стройки» это ровно то, как выглядит застрявший, получивший новый приказ.
	#
	# ── ПОЧЕМУ ОН ТУДА ПОПАДАЕТ ────────────────────────────────────────────
	# Запретный круг для ЦЕНТРА бойца = радиус ствола + его личный зазор
	# (TRUNK_RADIUS + Unit.TRUNK_CLEARANCE). Точка рубки обязана лежать
	# СНАРУЖИ него, и с запасом: рабочего постоянно двигают разбор наложения и
	# доводка к стволу. Обход стволов при этом умеет ровно одно — НЕ ПУСКАТЬ
	# внутрь; вытолкнуть уже оказавшегося внутри некому, а рубящий стоит на
	# месте и шага не делает вовсе, то есть и обход не работает
	print("\n═════ E. ЗАСТРЯВШИЙ В СТВОЛЕ ═════")
	var block_r: float = ResourceNode.TRUNK_RADIUS + Unit.TRUNK_CLEARANCE
	var slot_r: float = 0.0
	if tree != null:
		slot_r = tree.slot_radius()
	print("  запретный круг %.2f м (ствол %.2f + зазор %.2f), точка рубки %.2f м"
		% [block_r, ResourceNode.TRUNK_RADIUS, Unit.TRUNK_CLEARANCE, slot_r])
	# Запас в сантиметрах: рабочего сдвигает разбор наложения (до метра в
	# секунду), и щель в пару сантиметров он проскакивает за один тик
	verdict("E0 точка рубки снаружи запретного круга с запасом",
		slot_r >= block_r + 0.20,
		"запас %.2f м (нужно от 0.20)" % (slot_r - block_r))

	if tree != null:
		# Ставим рабочего В ЦЕНТР ствола — худший случай, но достижимый: внутрь
		# его заводит и обгон соседом, и доводка, и выключение стволов
		# детектором зацикливания (Unit.TRUNK_IGNORE_SEC)
		var f: Unit = _spawn_worker(tree.global_position)
		f.global_position = Vector3(tree.global_position.x,
			tree.global_position.y, tree.global_position.z)
		f.sync_row()
		await pframes(4)
		var inside: Vector3 = GameManager.trunk_block(
			f.global_position.x, f.global_position.z, Unit.TRUNK_CLEARANCE)
		verdict("E1 подготовка: рабочий и правда внутри ствола",
			inside.length() > 0.01, "выталкивание %.2f м" % inside.length())
		var start: Vector3 = f.global_position
		(f as Worker).command_build(site)
		await pframes(200)
		var out: Vector3 = GameManager.trunk_block(
			f.global_position.x, f.global_position.z, Unit.TRUNK_CLEARANCE)
		verdict("E2 выбрался из ствола", out.length() <= 0.01,
			"осталось выталкивание %.2f м, прошёл %.2f м"
			% [out.length(), f.global_position.distance_to(start)])
		await pframes(600)
		verdict("E3 дошёл до стройки и встал в артель",
			f.state == Unit.State.BUILDING and (f as Worker)._build_settled,
			"состояние %s, защёлка=%s, до стройки %.2f м"
			% [_state_name(f), str((f as Worker)._build_settled),
				f.global_position.distance_to(site.global_position)])

		# ── СТОЯЩИЙ, А НЕ ИДУЩИЙ ──────────────────────────────────────────
		# E2 проверял бойца С ПРИКАЗОМ: такой выбирается сам, обход стволов
		# работает на его шаге. А на скриншоте владельца рабочий СТОИТ (рубит) —
		# шага нет, обхода нет, и вытолкнуть его было некому вовсе. Сдвиг
		# внутрь имитируем прямой записью: ровно так его туда и заносит разбор
		# наложения, доводка к стволу и выключение стволов детектором
		var g: Unit = _spawn_worker(tree.global_position + Vector3(2.0, 0.0, 0.0))
		(g as Worker).command_gather(tree)
		await pframes(300)
		var chopping2: bool = g.state == Unit.State.GATHERING \
			or g.state == Unit.State.RETURNING
		verdict("E4 подготовка: рабочий рубит и стоит", chopping2,
			"состояние %s" % _state_name(g))
		g.global_position = Vector3(tree.global_position.x,
			g.global_position.y, tree.global_position.z)
		g.sync_row()
		# ── СВЕРЯЕМ СРАЗУ, БЕЗ ОЖИДАНИЯ КАДРОВ ────────────────────────────
		# Первая версия ждала четыре физкадра и краснела на подготовке:
		# выталкивание успевает сработать раньше, чем зонд убедится, что боец
		# внутри. Условие проверяется по ТОЛЬКО ЧТО ЗАПИСАННОЙ точке
		var in2: Vector3 = GameManager.trunk_block(
			g.global_position.x, g.global_position.z, Unit.TRUNK_CLEARANCE)
		verdict("E5 подготовка: сдвинут внутрь ствола", in2.length() > 0.01,
			"выталкивание %.2f м" % in2.length())
		await pframes(180)
		var out2: Vector3 = GameManager.trunk_block(
			g.global_position.x, g.global_position.z, Unit.TRUNK_CLEARANCE)
		verdict("E6 СТОЯЩЕГО тоже выталкивает из ствола", out2.length() <= 0.01,
			"осталось выталкивание %.2f м, до дерева %.2f м"
			% [out2.length(), g.global_position.distance_to(tree.global_position)])

	# ── E0б. ТО ЖЕ ПРАВИЛО ДЛЯ РУДЫ, ПО ВСЕМ ТРЁМ КЛАССАМ КУСКОВ ───────────
	# У дерева запас выведен явно и стережётся E0, а у руды он держался на
	# СОВПАДЕНИИ констант: препятствие 0.5 × size_scale при кольце 1.0 ×.
	# Проверяем СВОЙСТВО — точка добычи снаружи запретного круга, — а не
	# конкретные числа: правка размеров кусков не должна ломать стенд, она
	# должна ломать его только тогда, когда рабочий полезет внутрь жилы
	for sc in [0.62, 1.05, 1.60]:
		var ore := ResourceNode.new()
		ore.resource_type = Constants.RESOURCE_STONE
		ore.remaining = 600.0
		ore.size_scale = float(sc)
		main.world_add(ore)
		ore.global_position = Vector3(spot.x + 40.0, 0.0, spot.z + 40.0)
		var ore_block: float = ResourceNode.ORE_OBSTACLE_RADIUS * float(sc) \
			+ Unit.TRUNK_CLEARANCE
		var ore_slot: float = ore.slot_radius()
		verdict("E0б точка добычи руды (масштаб %.2f) снаружи запретного круга" % sc,
			ore_slot >= ore_block + 0.20,
			"запрет %.2f м, кольцо %.2f м, запас %.2f м"
				% [ore_block, ore_slot, ore_slot - ore_block])
		ore.queue_free()
	await pframes(4)

	# ── E7. ДЕТЕКТОР ЗАЦИКЛИВАНИЯ ТИКАЕТ И НА ПУТИ К СТРОЙКЕ ───────────────
	# ЭТО И БЫЛА ДЫРА. Детектор жил прямо в `Unit._process_move`, а
	# `Worker.tick_physics` в состоянии BUILDING до базового тика НЕ ДОХОДИТ —
	# значит, рабочий, наматывающий круги вокруг комля по дороге на стройку,
	# признать себя застрявшим не мог ВООБЩЕ и обходил дерево до конца партии.
	#
	# Проверяем МЕХАНИЗМ, а не его последствие: последствие (круги вокруг
	# конкретного дерева) зависит от того, где именно встал ствол, и такой
	# стенд мерил бы расстановку. Подделываем опору отсчёта — «полсекунды
	# назад я был в полуметре от цели» — и смотрим, заметит ли рабочий, что
	# продвижения нет. До правки `_trunk_ignore` оставался нулём всегда
	var st: Unit = _spawn_worker(spot + Vector3(-12.0, 0.0, 8.0))
	(st as Worker).command_build(site)
	await pframes(4)
	verdict("E7а подготовка: рабочий идёт на стройку",
		st.state == Unit.State.BUILDING, "состояние %s" % _state_name(st))
	st._stuck_ref_dist = 0.5
	st._stuck_timer    = 0.0
	st._trunk_ignore   = 0.0
	await pframes(40)
	verdict("E7 детектор зацикливания работает и в состоянии BUILDING",
		st._trunk_ignore > 0.0,
		"выключение стволов %.2f с, серия %d" % [st._trunk_ignore, st._stuck_streak])

	print("\n=== ЗОНД ПОМОЩИ НА СТРОЙКЕ: пройдено %d, провалов: %d ==="
		% [_pass, _fail])
	get_tree().quit(0)
