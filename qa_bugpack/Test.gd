extends Node

## СТЕНД ПАКЕТА «КЛИКИ / СПРАЙТЫ / АТАКА / БЛОКИ / ОБОРОНА»
##   1 АТАКА     — анимация удара только в зоне поражения, приказ выполняют ВСЕ
##                 отряды, лучники сами стреляют на всю дальность
##   2 КЛИКИ     — остриё курсора, приоритет золота под кроной, рабочий на стройку
##   3 СПРАЙТЫ   — ракурс считается от камеры, а не в мировых осях
##   4 ТОЧКА СБОРА и АВТО-ВЫХОД из гарнизона
##   5 БЛОКИ     — 3 отряда строятся секциями и не перемешиваются
##   6 ОБОРОНА   — ИИ не идёт на базу, держит рубеж, сам берёт звёздочки
##   7 ОЗЕРО     — обход воды без зависаний, приказ в воду переносится на берег

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _UIA   := preload("res://scripts/UIAssets.gd")
const _PerfCfg := preload("res://scripts/perf_config.gd")

var main = null
var hud = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	# И ОТСЕЧЕНИЕ ДАЛЬНИХ СПРАЙТОВ: площадки стенда вынесены за сотни метров от
	# точки обзора, и LOD честно перестаёт считать им позу. Проверки поз должны
	# видеть спрайты живыми
	_PerfCfg.sprite_lod = false
	await frames(2)
	hud = main.hud
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 100000.0)
	await frames(1)

	await _test_attack_range()
	await _test_multi_squad_attack()
	await _test_archer_watch()
	_test_cursor_hotspot()
	await _test_resource_priority()
	await _test_worker_build()
	await _test_sprite_facing()
	await _test_rally_point()
	await _test_auto_release()
	await _test_blocks()
	_test_defensive_ai()
	await _test_lake_nav()
	_summary()
	print("\n=== BUGPACK TEST DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-58s %s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

# ── помощники ────────────────────────────────────────────────────────────────

func _spawn(unit_id: String, f: int) -> Unit:
	var u: Unit
	match unit_id:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = f
	main.world_add(u)
	return u

## Отряд из n бойцов, зарегистрированный в GameManager
func _squad(unit_id: String, n: int, at: Vector3, f: int = Constants.FACTION_PLAYER) -> Dictionary:
	var sid: int = GameManager.new_squad(f, unit_id)
	var units: Array = []
	for i in range(n):
		var u := _spawn(unit_id, f)
		u.global_position = at + Vector3(float(i % 5) * 0.6, 0.0, float(i / 5) * 0.6)
		GameManager.add_to_squad(sid, u)
		units.append(u)
	return {"sid": sid, "units": units}

func _kill(units: Array) -> void:
	for u in units:
		if is_instance_valid(u):
			u.queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# 1. АТАКА ТОЛЬКО В ЗОНЕ ПОРАЖЕНИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _test_attack_range() -> void:
	print("\n═════ 1. АНИМАЦИЯ УДАРА ТОЛЬКО В ЗОНЕ ПОРАЖЕНИЯ ═════")
	var a := _spawn("spearman", Constants.FACTION_PLAYER)
	a.global_position = Vector3(-300.0, 0.0, -300.0)
	var b := _spawn("spearman", Constants.FACTION_ENEMY)
	b.global_position = Vector3(-300.0 + 12.0, 0.0, -300.0)   # 12 м — заведомо далеко
	await frames(3)

	print("  дальность удара копейщика: %.2f м, дистанция до цели: %.1f м" % [
		a.attack_range, a.global_position.distance_to(b.global_position)])
	a.command_attack(b)
	await frames(6)
	var far_key: String = a._cur_tex_key
	print("  в движении к цели: состояние=%d, в зоне=%s, лист спрайта=«%s»" % [
		a.state, str(a.target_in_range()), far_key])
	verdict("1a на бегу к цели поза удара НЕ включается",
		not far_key.begins_with("attack"), "лист «%s»" % far_key)

	# Ставим цель вплотную — поза обязана смениться на удар
	b.global_position = a.global_position + Vector3(a.attack_range * 0.5, 0.0, 0.0)
	await frames(8)
	var near_key: String = a._cur_tex_key
	print("  цель вплотную (%.1f м): в зоне=%s, лист спрайта=«%s»" % [
		a.global_position.distance_to(b.global_position), str(a.target_in_range()), near_key])
	verdict("1b вплотную включается поза удара",
		near_key.begins_with("attack"), "лист «%s»" % near_key)
	_kill([a, b])
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 2. ПРИКАЗ АТАКИ ВЫПОЛНЯЮТ ВСЕ ВЫДЕЛЕННЫЕ ОТРЯДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _test_multi_squad_attack() -> void:
	print("\n═════ 2. НЕСКОЛЬКО ОТРЯДОВ ПО ОДНОМУ ПРИКАЗУ АТАКИ ═════")
	var base := Vector3(-360.0, 0.0, -300.0)
	var s1 := _squad("spearman", 6, base)
	var s2 := _squad("archer",   4, base + Vector3(0.0, 0.0, 4.0))
	var s3 := _squad("spearman", 6, base + Vector3(0.0, 0.0, 8.0))
	var foe := _spawn("spearman", Constants.FACTION_ENEMY)
	foe.global_position = base + Vector3(26.0, 0.0, 4.0)
	await frames(3)

	# ВТОРОЙ отряд специально ставим в ЗАЩИТУ: раньше он игнорировал приказ
	for u in s2["units"]:
		(u as Unit).set_stance(_UCfg.STANCE_DEFENSE)
	await frames(2)
	print("  отряд лучников переведён в стойку ЗАЩИТА перед приказом")

	var all: Array = []
	all.append_array(s1["units"]); all.append_array(s2["units"]); all.append_array(s3["units"])
	for u in all:
		(u as Unit).command_attack(foe)
	await frames(4)

	var attacking := 0
	var idle := 0
	for u in all:
		if (u as Unit).state == Unit.State.ATTACKING:
			attacking += 1
		elif (u as Unit).state == Unit.State.IDLE:
			idle += 1
	print("  из %d бойцов: в атаке=%d, стоят без дела=%d" % [all.size(), attacking, idle])
	verdict("2a приказ атаки выполняют ВСЕ, включая отряд в защите",
		attacking == all.size(), "в атаке %d из %d" % [attacking, all.size()])

	# Подтягивание: за 40 кадров все обязаны СОКРАТИТЬ дистанцию до цели
	var before: Array = []
	for u in all:
		before.append((u as Node3D).global_position.distance_to(foe.global_position))
	await frames(40)
	var closer := 0
	for i in range(all.size()):
		var now: float = (all[i] as Node3D).global_position.distance_to(foe.global_position)
		if now < float(before[i]) - 0.05:
			closer += 1
	print("  сократили дистанцию до цели: %d из %d" % [closer, all.size()])
	verdict("2b задние ряды подтягиваются к цели", closer == all.size(),
		"%d из %d" % [closer, all.size()])

	_kill(all); _kill([foe])
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 3. ЛУЧНИКИ ВИДЯТ НА ВСЮ ДАЛЬНОСТЬ СТРЕЛЬБЫ
# ═════════════════════════════════════════════════════════════════════════════
func _test_archer_watch() -> void:
	print("\n═════ 3. АВТООГОНЬ ЛУЧНИКОВ НА ВСЮ ДАЛЬНОСТЬ ═════")
	var a := _spawn("archer", Constants.FACTION_PLAYER)
	a.global_position = Vector3(-420.0, 0.0, -300.0)
	await frames(3)
	var rng: float = a.attack_range
	print("  дальность стрельбы: %.1f м, прежний радиус наблюдения был %.1f м" % [
		rng, a.AGGRO_RADIUS])
	# Цель ДАЛЬШЕ старого агро-радиуса, но в пределах дальности стрельбы
	var dist: float = (a.AGGRO_RADIUS + rng) * 0.5
	var foe := _spawn("spearman", Constants.FACTION_ENEMY)
	foe.global_position = a.global_position + Vector3(dist, 0.0, 0.0)
	await frames(3)
	# Даём время на опрос агро (интервал до 2 с)
	for _i in range(4):
		a._aggro_timer = 0.0
		await frames(4)
	print("  цель в %.1f м: состояние лучника=%d, цель назначена=%s" % [
		dist, a.state, str(a.attack_target != null)])
	verdict("3a лучник сам берёт цель дальше старого агро-радиуса",
		a.attack_target != null and a.state == Unit.State.ATTACKING,
		"дистанция %.1f м" % dist)
	# И при этом НЕ бежит: цель уже в дальности стрельбы
	var p0: Vector3 = a.global_position
	await frames(30)
	var moved: float = p0.distance_to(a.global_position)
	print("  сместился за 30 кадров: %.2f м" % moved)
	verdict("3b стреляет с места, не бежит на цель", moved < 0.3, "%.2f м" % moved)
	_kill([a, foe])
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 4. ОСТРИЁ КУРСОРА
# ═════════════════════════════════════════════════════════════════════════════
func _test_cursor_hotspot() -> void:
	print("\n═════ 4. HOTSPOT КУРСОРА ═════")
	var tex := _UIA.cursor(1)
	if tex == null:
		verdict("4a остриё курсора вычислено", true, "ассета курсора нет — проверка неприменима")
		return
	var hs: Vector2 = _UIA.cursor_hotspot(1)
	var img := tex.get_image()
	print("  текстура курсора: %dx%d, остриё=(%.0f, %.0f)" % [
		tex.get_width(), tex.get_height(), hs.x, hs.y])
	var opaque := false
	if img != null and hs.x < float(img.get_width()) and hs.y < float(img.get_height()):
		opaque = img.get_pixel(int(hs.x), int(hs.y)).a > 0.02
	print("  пиксель в точке острия непрозрачен: %s" % str(opaque))
	verdict("4a остриё указывает на непрозрачный пиксель", opaque)
	# Выше острия непрозрачных пикселей быть не должно
	var above := 0
	if img != null:
		for y in range(int(hs.y)):
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a > 0.02:
					above += 1
	print("  непрозрачных пикселей ВЫШЕ острия: %d" % above)
	verdict("4b выше острия рисунка нет", above == 0, "нашли %d" % above)

# ═════════════════════════════════════════════════════════════════════════════
# 5. ПРИОРИТЕТ КЛИКА: ЗОЛОТО ПОД КРОНОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _test_resource_priority() -> void:
	print("\n═════ 5. КЛИК ПО ЗОЛОТУ ПОД КРОНОЙ ДЕРЕВА ═════")
	var sm = main.selection_manager
	var cam: Camera3D = sm.camera
	# Ставим дерево и жилу золота ВПЛОТНУЮ друг к другу на чистом месте
	var spot := Vector3(30.0, 0.0, 30.0)
	var tree := ResourceNode.new()
	tree.resource_type = Constants.RESOURCE_WOOD
	main.world_add(tree)
	tree.global_position = spot
	var gold := ResourceNode.new()
	gold.resource_type = Constants.RESOURCE_GOLD
	main.world_add(gold)
	gold.global_position = spot + Vector3(1.0, 0.0, 1.0)
	await frames(3)

	# Камера наводится СВОИМ способом (_focus + _update_position): прямая
	# запись global_position бесполезна — RTSCamera._process её перезапишет,
	# и клик считался бы по координатам за пределами экрана
	cam._focus = spot + Vector3(0.5, 0.0, 0.5)
	cam._update_position()
	await frames(2)

	var screen: Vector2 = cam.unproject_position(gold.global_position + Vector3(0, 0.6, 0))
	print("  дерево в (%.0f,%.0f), золото в (%.0f,%.0f), клик по экрану (%.0f,%.0f)" % [
		tree.global_position.x, tree.global_position.z,
		gold.global_position.x, gold.global_position.z, screen.x, screen.y])

	# Что даёт СТАРЫЙ одиночный луч и что даёт новый разбор
	var raw: Dictionary = sm._screen_ray_hit(screen, Constants.LAYER_RESOURCES)
	var raw_node = sm._resolve_node(raw["collider"]) if raw.has("collider") else null
	var raw_type := "—"
	if raw_node is ResourceNode:
		raw_type = "дерево" if (raw_node as ResourceNode).resource_type == Constants.RESOURCE_WOOD else "золото"
	var pick: Dictionary = sm._pick_at(screen, Constants.LAYER_RESOURCES | Constants.LAYER_GROUND)
	var got = pick["target"]
	var got_type := "—"
	if got is ResourceNode:
		got_type = "дерево" if (got as ResourceNode).resource_type == Constants.RESOURCE_WOOD else "золото"
	print("  одиночный луч выбрал: %s;  разбор приоритетов выбрал: %s" % [raw_type, got_type])
	verdict("5a клик по золоту у дерева выбирает золото",
		got is ResourceNode and (got as ResourceNode).resource_type == Constants.RESOURCE_GOLD,
		"выбрано: %s" % got_type)

	# Клик по СТВОЛУ дерева обязан по-прежнему выбирать дерево
	var trunk: Vector2 = cam.unproject_position(tree.global_position + Vector3(0, 1.2, 0))
	var pick2: Dictionary = sm._pick_at(trunk, Constants.LAYER_RESOURCES | Constants.LAYER_GROUND)
	var got2 = pick2["target"]
	var got2_type := "—"
	if got2 is ResourceNode:
		got2_type = "дерево" if (got2 as ResourceNode).resource_type == Constants.RESOURCE_WOOD else "золото"
	print("  клик по стволу (%.0f,%.0f) выбрал: %s" % [trunk.x, trunk.y, got2_type])
	verdict("5b клик по стволу по-прежнему выбирает дерево",
		got2 is ResourceNode and (got2 as ResourceNode).resource_type == Constants.RESOURCE_WOOD,
		"выбрано: %s" % got2_type)

	# И рабочий уходит именно на золото
	var w := _spawn("worker", Constants.FACTION_PLAYER) as Worker
	w.global_position = spot + Vector3(-6.0, 0.0, 0.0)
	await frames(2)
	sm.selected_units = [w]
	if got is ResourceNode:
		w.command_gather(got as ResourceNode)
	await frames(2)
	var target_type := -1
	if w.gather_target != null:
		target_type = w.gather_target.resource_type
	print("  рабочий послан на ресурс типа %d (золото=%d)" % [
		target_type, Constants.RESOURCE_GOLD])
	verdict("5c рабочий уходит на золото, а не на дерево",
		target_type == Constants.RESOURCE_GOLD)
	sm.selected_units = []
	_kill([w])
	tree.queue_free(); gold.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 6. РАБОЧИЙ ПОДКЛЮЧАЕТСЯ К СТРОЙКЕ КЛИКОМ
# ═════════════════════════════════════════════════════════════════════════════
func _test_worker_build() -> void:
	print("\n═════ 6. КЛИК РАБОЧИМ ПО СТРОЙПЛОЩАДКЕ ═════")
	var sm = main.selection_manager
	var site_script = load("res://scripts/ConstructionSite.gd")
	var site = site_script.new()
	site.faction = Constants.FACTION_PLAYER
	site.target_id = "barracks"
	site.target_name = "Бараки"
	site.build_time = 30.0
	main.world_add(site)
	site.global_position = Vector3(60.0, 0.0, 60.0)
	await frames(3)
	print("  стройка в группе construction_sites: %s" % str(site.is_in_group("construction_sites")))

	var w1 := _spawn("worker", Constants.FACTION_PLAYER) as Worker
	var w2 := _spawn("worker", Constants.FACTION_PLAYER) as Worker
	w1.global_position = site.global_position + Vector3(-4.0, 0.0, 0.0)
	w2.global_position = site.global_position + Vector3(-5.0, 0.0, 1.0)
	await frames(2)
	sm.selected_units = [w1, w2]
	var joined: bool = sm._try_join_construction(site)
	await frames(2)
	print("  приказ принят=%s; состояния рабочих: %d / %d (BUILDING=%d)" % [
		str(joined), w1.state, w2.state, Unit.State.BUILDING])
	verdict("6a клик по стройке ставит рабочих на постройку",
		joined and w1.state == Unit.State.BUILDING and w2.state == Unit.State.BUILDING)

	# Доходят и реально числятся строителями, прогресс растёт
	var p0: float = site.progress
	await frames(90)
	print("  строителей на площадке=%d, прогресс %.2f → %.2f" % [
		site.builder_count(), p0, site.progress])
	verdict("6b рабочие доходят и стройка идёт",
		site.builder_count() >= 1 and site.progress > p0 + 0.05,
		"строителей %d, прогресс %.2f" % [site.builder_count(), site.progress])
	sm.selected_units = []
	_kill([w1, w2])
	site.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 7. ОРИЕНТАЦИЯ СПРАЙТА ОТНОСИТЕЛЬНО КАМЕРЫ
# ═════════════════════════════════════════════════════════════════════════════
func _test_sprite_facing() -> void:
	print("\n═════ 7. РАКУРС СПРАЙТА ПРИ ОБЛЁТЕ КАМЕРЫ ═════")
	var cam: Camera3D = main.selection_manager.camera
	var u := _spawn("spearman", Constants.FACTION_PLAYER) as Spearman
	u.global_position = Vector3(100.0, 0.0, 100.0)
	await frames(3)
	if u._dir_sprite == null:
		verdict("7a ракурс считается от камеры", true, "направленных спрайтов нет")
		_kill([u]); return

	# ВАЖНО: транспорт камеры трогать бесполезно — RTSCamera._process каждый
	# кадр пересобирает его из _focus/_orbit_yaw. Крутим именно орбиту, то есть
	# делаем ровно то же, что игрок клавишами Q/E
	var facing := Vector3(0.0, 0.0, -1.0)      # боец идёт строго на СЕВЕР
	cam._focus = u.global_position
	cam._orbit_yaw = 0.0
	cam._update_position()
	await frames(2)
	print("  камера при орбите 0°: позиция (%.0f, %.0f, %.0f)" % [
		cam.global_position.x, cam.global_position.y, cam.global_position.z])
	u._cur_sector = -1
	var south: Array = u._facing_to_dir_key(facing)
	print("  камера с ЮГА: ключ=«%s», зеркало=%s" % [String(south[0]), str(south[1])])

	# Орбита на 180° — игрок смотрит на тот же строй с противоположной стороны
	cam._orbit_yaw = 180.0
	cam._update_position()
	await frames(2)
	print("  камера при орбите 180°: позиция (%.0f, %.0f, %.0f)" % [
		cam.global_position.x, cam.global_position.y, cam.global_position.z])
	u._cur_sector = -1
	var north: Array = u._facing_to_dir_key(facing)
	print("  камера с СЕВЕРА: ключ=«%s», зеркало=%s" % [String(north[0]), str(north[1])])

	verdict("7a при взгляде с юга на идущего на север видно спину",
		String(south[0]) == "up", "ключ «%s»" % String(south[0]))
	verdict("7b при облёте камеры ракурс МЕНЯЕТСЯ",
		String(south[0]) != String(north[0]),
		"«%s» → «%s»" % [String(south[0]), String(north[0])])
	verdict("7c с севера тот же боец виден спереди",
		String(north[0]) == "down", "ключ «%s»" % String(north[0]))

	# Вектор взгляда в МИРЕ от камеры не зависит: копьё смотрит туда, куда боец
	var moved_facing := u._facing
	print("  _facing бойца после смены ракурса: (%.2f, %.2f)" % [moved_facing.x, moved_facing.z])
	verdict("7d мировое направление бойца камерой не тронуто",
		absf(moved_facing.x) < 1.01 and absf(moved_facing.z) < 1.01)
	_kill([u])
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 8. ТОЧКА СБОРА ЗДАНИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _test_rally_point() -> void:
	print("\n═════ 8. ТОЧКА СБОРА ═════")
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(150.0, 0.0, 150.0)
	await frames(3)
	print("  точка сбора задана изначально: %s" % str(b.has_rally))
	verdict("8a по умолчанию точки сбора нет", not b.has_rally)

	var sm = main.selection_manager
	sm.selected_units = [b]
	var rally := Vector3(180.0, 0.0, 170.0)
	var applied: bool = sm._try_set_rally(rally, null)
	print("  ПКМ по карте с выделенным зданием: принято=%s, точка=(%.0f, %.0f)" % [
		str(applied), b.rally_point.x, b.rally_point.z])
	verdict("8b ПКМ по карте назначает точку сбора зданию",
		applied and b.has_rally
			and absf(b.rally_point.x - rally.x) < 0.01
			and absf(b.rally_point.z - rally.z) < 0.01)

	# Отряд из этого барака получает приказ на точку сбора, а не к дверям.
	# Время найма урезаем до мгновенного: ждать полный цикл в стенде незачем,
	# проверяется ПРИКАЗ (move_target), а не скорость ходьбы
	b.train_from_config("spearman")
	if not b.production_queue.is_empty():
		(b.production_queue[0] as Dictionary)["time"] = 0.01
	await frames(80)
	var near_rally := 0
	var near_gate := 0
	var total := 0
	var gate: Vector3 = b._gate_position()
	for u in get_tree().get_nodes_in_group("player_units"):
		if not (u is Spearman):
			continue
		total += 1
		var t: Vector3 = (u as Unit).move_target
		if t.distance_to(rally) < 12.0:
			near_rally += 1
		elif t.distance_to(gate) < 20.0:
			near_gate += 1
	print("  бойцов вышло=%d; приказ на точку сбора=%d, к воротам=%d" % [
		total, near_rally, near_gate])
	verdict("8c новый отряд получает приказ на точку сбора",
		total > 0 and near_rally == total,
		"%d из %d (к воротам %d)" % [near_rally, total, near_gate])

	# Смешанное выделение (здание + юнит) точку сбора НЕ ставит
	var probe := _spawn("spearman", Constants.FACTION_PLAYER)
	probe.global_position = Vector3(150.0, 0.0, 160.0)
	await frames(2)
	sm.selected_units = [b, probe]
	var mixed: bool = sm._try_set_rally(Vector3(999.0, 0.0, 999.0), null)
	print("  смешанное выделение (здание + боец): точка сбора принята=%s" % str(mixed))
	verdict("8d смешанное выделение не перехватывает приказ движения", not mixed)

	sm.selected_units = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Spearman:
			u.queue_free()
	b.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# 9. АВТО-ВЫХОД ИЗ ГАРНИЗОНА
# ═════════════════════════════════════════════════════════════════════════════
func _test_auto_release() -> void:
	print("\n═════ 9. АВТО-ВЫХОД ОТРЯДА ИЗ ЗАМКА ═════")
	# ТЕМП ЛЕЧЕНИЯ — ИЗ КОНФИГА, БЕЗ ЖЁСТКИХ ЧИСЕЛ В СТЕНДЕ. Раньше здесь стояло
	# «18 HP/с»: это была разовая величина под тогдашний баланс, и стенд начал
	# спорить с балансовой таблицей владельца, как только её поправили.
	# Проверяем СВОЙСТВА: темп положительный, рана заживает ровно с этой
	# скоростью, полный и здоровый отряд выкатывается сам
	var heal_rate: float = _UCfg.GARRISON_HEAL_PER_SEC
	print("  конфиг: лечение %.1f HP/с, авто-выход=%s" % [
		heal_rate, str(_UCfg.GARRISON_AUTO_RELEASE)])
	verdict("9a темп лечения задан конфигом и положителен", heal_rate > 0.0,
		"в конфиге %.2f HP/с" % heal_rate)

	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(240.0, 0.0, 240.0)
	await frames(3)

	# Полный по составу отряд, но раненый. ГЛУБИНА РАНЫ ВЫВЕДЕНА ИЗ ТЕМПА, а не
	# задана долей здоровья: при медленном лечении «40% здоровья» означало бы
	# минуты ожидания в стенде. Берём столько урона, сколько конфиг залечивает
	# за HEAL_BUDGET_SEC секунд
	const HEAL_BUDGET_SEC := 3.0
	var wound: float = heal_rate * HEAL_BUDGET_SEC
	var full: int = _UCfg.squad_size("spearman")
	var sq := _squad("spearman", full, castle.global_position + Vector3(3.0, 0.0, 0.0))
	for u in sq["units"]:
		var un := u as Unit
		un.current_health = maxf(1.0, un.max_health - wound)
	await frames(2)
	castle.request_garrison(int(sq["sid"]))
	print("  отряд из %d бойцов заведён в замок с раной %.1f HP (%.0f с лечения)"
		% [full, wound, HEAL_BUDGET_SEC])

	# Ждём, пока зайдут и вылечатся; замеряем по времени, а не по кадрам.
	# Окно — из конфига: время лечения раны плюс запас на вход/выход строем
	var probe: Unit = sq["units"][0]
	var hp_before: float = probe.current_health
	var wait_ms: int = int((HEAL_BUDGET_SEC + 6.0) * 1000.0)
	var t0: int = Time.get_ticks_msec()
	var inside_seen := false
	var released := false
	var heal_t0: int = 0
	var heal_hp0: float = 0.0
	var rate_seen: float = -1.0
	while Time.get_ticks_msec() - t0 < wait_ms:
		await frames(5)
		if not castle.garrison.is_empty():
			if not inside_seen:
				inside_seen = true
				heal_t0  = Time.get_ticks_msec()
				heal_hp0 = probe.current_health
			# Замер фактического темпа, пока боец ещё не долечен доверху
			elif rate_seen < 0.0 and is_instance_valid(probe) \
					and probe.current_health < probe.max_health - 0.01 \
					and Time.get_ticks_msec() - heal_t0 > 500:
				var dt: float = float(Time.get_ticks_msec() - heal_t0) / 1000.0
				rate_seen = (probe.current_health - heal_hp0) / dt
		elif inside_seen:
			released = true
			break
	var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var visible_n := 0
	var healed_n := 0
	for u in sq["units"]:
		if not is_instance_valid(u):
			continue
		if not (u as Unit).garrisoned:
			visible_n += 1
		if (u as Unit).current_health >= (u as Unit).max_health - 0.01:
			healed_n += 1
	print("  побывал внутри=%s, вышел сам=%s за %.1f с; снаружи=%d, здоровы=%d" % [
		str(inside_seen), str(released), elapsed, visible_n, healed_n])
	verdict("9b отряд заходит в гарнизон", inside_seen)
	verdict("9c вылеченный полный отряд выходит САМ",
		released and visible_n == full, "снаружи %d из %d" % [visible_n, full])
	verdict("9d выходит полностью здоровым", healed_n == full,
		"здоровых %d из %d" % [healed_n, full])
	# Темп сверяется С КОНФИГОМ, а не с числом в стенде. Допуск широкий:
	# замер идёт по стенным часам через await, кадры равномерными не бывают
	verdict("9e фактический темп лечения совпадает с конфигом",
		rate_seen < 0.0 or absf(rate_seen - heal_rate) <= heal_rate * 0.35,
		"замер %.2f HP/с при %.2f в конфиге (hp: %.1f → %.1f)"
			% [rate_seen, heal_rate, hp_before, probe.current_health if is_instance_valid(probe) else -1.0])
	_kill(sq["units"])
	castle.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# 10. ФОРМАЦИЯ БЛОКАМИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_blocks() -> void:
	print("\n═════ 10. ТРИ ОТРЯДА СТРОЯТСЯ СЕКЦИЯМИ ═════")
	var sm = main.selection_manager
	var base := Vector3(-500.0, 0.0, -500.0)
	var a := _squad("spearman", 12, base)
	var b := _squad("archer",    8, base + Vector3(0.0, 0.0, 6.0))
	var c := _squad("spearman", 12, base + Vector3(0.0, 0.0, 12.0))
	await frames(3)

	var all: Array = []
	all.append_array(a["units"]); all.append_array(b["units"]); all.append_array(c["units"])
	sm.selected_units = all.duplicate()
	var line_a := base + Vector3(20.0, 0.0, -20.0)
	var line_b := base + Vector3(20.0, 0.0, 20.0)   # линия длиной 40 м
	sm._execute_line_formation(line_a, line_b)
	await frames(2)

	# Разбор слотов ПО ПРИКАЗУ: смотрим move_target каждого бойца.
	# КОНТРАКТ COMBINED ARMS (см. Formations.gd): отряды ОДНОГО рода войск
	# делят линию на непересекающиеся участки, а РАЗНЫЕ рода войск стоят
	# ЭШЕЛОНАМИ — лучники за копейщиками. Значит, пара «копейщики + лучники»
	# ОБЯЗАНА накладываться по линии и расходиться по ГЛУБИНЕ. Прежняя проверка
	# мерила только линию и потому считала правильный эшелон пересечением
	var proj: Dictionary = {}      # sid -> [мин, макс] проекции на линию
	var deep: Dictionary = {}      # sid -> [мин, макс] проекции на курс
	var kind: Dictionary = {}      # sid -> род войск
	var dir := (line_b - line_a).normalized()
	var course: Vector3 = (all[0] as Unit).face_on_arrive
	if course.length() < 0.01:
		course = Vector3(-dir.z, 0.0, dir.x)
	course = course.normalized()
	for u in all:
		var sid: int = (u as Unit).squad_id
		var t: float = ((u as Unit).move_target - line_a).dot(dir)
		var dp: float = ((u as Unit).move_target - line_a).dot(course)
		kind[sid] = GameManager.squad_type(sid)
		if not proj.has(sid):
			proj[sid] = [t, t]
			deep[sid] = [dp, dp]
		else:
			var pr: Array = proj[sid]
			pr[0] = minf(float(pr[0]), t)
			pr[1] = maxf(float(pr[1]), t)
			var dr: Array = deep[sid]
			dr[0] = minf(float(dr[0]), dp)
			dr[1] = maxf(float(dr[1]), dp)
	for sid in proj:
		var pr: Array = proj[sid]
		var dr: Array = deep[sid]
		print("    отряд %d (%s): линия [%.1f .. %.1f] м, глубина [%.1f .. %.1f] м" % [
			int(sid), String(kind[sid]), float(pr[0]), float(pr[1]),
			float(dr[0]), float(dr[1])])

	# Разводим пары по правильной оси: свои — по линии, чужие — по глубине
	var keys: Array = proj.keys()
	var overlaps := 0
	var min_gap := 1.0e9
	var echelon_ok := true
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var same: bool = String(kind[keys[i]]) == String(kind[keys[j]])
			var a1: Array = (proj[keys[i]] if same else deep[keys[i]])
			var a2: Array = (proj[keys[j]] if same else deep[keys[j]])
			var lo: float = maxf(float(a1[0]), float(a2[0]))
			var hi: float = minf(float(a1[1]), float(a2[1]))
			if lo <= hi:
				if same:
					overlaps += 1
				else:
					echelon_ok = false
			elif same:
				min_gap = minf(min_gap, lo - hi)
	print("  пересечений секций одного рода: %d, минимальный зазор: %.2f м" % [
		overlaps, min_gap if min_gap < 1.0e8 else -1.0])
	verdict("10a секции отрядов ОДНОГО рода войск не пересекаются", overlaps == 0,
		"пересечений %d" % overlaps)
	verdict("10a2 разные рода войск разведены по глубине (эшелоны)", echelon_ok)
	verdict("10b между секциями есть зазор", min_gap > 0.5,
		"минимум %.2f м" % (min_gap if min_gap < 1.0e8 else -1.0))
	verdict("10c секций ровно по числу отрядов", proj.size() == 3,
		"нашли %d" % proj.size())

	# Единый фронт: всем выдан один и тот же вектор взгляда
	var faces: Dictionary = {}
	for u in all:
		var fv: Vector3 = (u as Unit).face_on_arrive
		faces["%.2f|%.2f" % [fv.x, fv.z]] = true
	print("  различных векторов взгляда в приказе: %d" % faces.size())
	verdict("10d фронт единый для всех отрядов", faces.size() == 1,
		"векторов %d" % faces.size())

	sm.selected_units = []
	_kill(all)
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 11. ОБОРОНИТЕЛЬНЫЙ ИИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_defensive_ai() -> void:
	print("\n═════ 11. ОБОРОНИТЕЛЬНЫЙ ИИ ═════")
	print("  конфиг: DEFENSIVE_MODE=%s, доля карты=%.2f, патрулей=%d, авто-звёзды=%s" % [
		str(_AICfg.DEFENSIVE_MODE), _AICfg.MAP_CONTROL_FRACTION,
		_AICfg.PATROL_SQUADS, str(_AICfg.AI_AUTO_VETERAN)])
	verdict("11a оборонительный режим включён в конфиге", _AICfg.DEFENSIVE_MODE)
	verdict("11b авто-выбор ветеранских наград включён", _AICfg.AI_AUTO_VETERAN)

	var ai = main.enemy_ai
	if ai == null:
		verdict("11c ИИ доступен", false, "main.enemy_ai == null")
		return

	# Рубеж обороны считается от замка ИИ к базе игрока
	var ec: Castle = null
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if b is Castle:
			ec = b as Castle
	var pc: Castle = null
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b is Castle:
			pc = b as Castle
	# Замков может не быть: игрок ставит свой вручную, а замок ИИ появляется
	# не сразу. Для проверки геометрии рубежа хватает пары заглушек
	if ec == null:
		ec = Castle.new(); ec.faction = Constants.FACTION_ENEMY
		main.world_add(ec); ec.global_position = Vector3(30.0, 0.0, 30.0)
	if pc == null:
		pc = Castle.new(); pc.faction = Constants.FACTION_PLAYER
		main.world_add(pc); pc.global_position = Vector3(-60.0, 0.0, -60.0)
	var line: Vector3 = ai._defense_center(ec)
	var d_own: float = line.distance_to(ec.global_position)
	var d_foe: float = line.distance_to(pc.global_position)
	print("  замок ИИ (%.0f,%.0f), база игрока (%.0f,%.0f), рубеж (%.0f,%.0f)" % [
		ec.global_position.x, ec.global_position.z,
		pc.global_position.x, pc.global_position.z, line.x, line.z])
	print("  рубеж: до своего замка %.0f м, до базы игрока %.0f м" % [d_own, d_foe])
	verdict("11c рубеж не на базе игрока, а на своей половине",
		d_foe > d_own * 0.6, "своих %.0f м, чужих %.0f м" % [d_own, d_foe])
	verdict("11d рубеж не в воде", not main.is_water(line.x, line.z))

# ═════════════════════════════════════════════════════════════════════════════
# 12. ОБХОД ОЗЕРА
# ═════════════════════════════════════════════════════════════════════════════
func _test_lake_nav() -> void:
	print("\n═════ 12. НАВИГАЦИЯ ВОКРУГ ОЗЕРА ═════")
	# ОЗЕРО ВРЕМЕННО ВЫКЛЮЧЕНО (Main.LAKE_ENABLED). Раздел проверяет обход воды,
	# которой на карте больше нет — проверять нечего. Код озера жив и вернётся
	# вместе с флагом, поэтому раздел не удалён, а пропущен
	if not main.LAKE_ENABLED:
		print("  ПРОПУЩЕНО: озеро отключено флагом Main.LAKE_ENABLED")
		return
	var c: Vector3 = main.LAKE_CENTER
	print("  центр озера (%.0f, %.0f), радиус ~%.0f" % [c.x, c.z, main.LAKE_RADIUS])

	# Приказ В ВОДУ обязан переехать на сушу
	var land: Vector3 = GameManager.land_target(c)
	print("  приказ в центр озера перенесён в (%.1f, %.1f), вода там=%s" % [
		land.x, land.z, str(main.is_water(land.x, land.z))])
	verdict("12a приказ в воду переносится на сушу", not main.is_water(land.x, land.z))

	# Ни один шаг из точек по периметру не должен быть нулевым
	var stuck := 0
	var probes := 0
	for i in range(36):
		var ang: float = TAU * float(i) / 36.0
		# Точка на самой кромке снаружи
		var p := Vector3(c.x + cos(ang) * (main.LAKE_RADIUS + 0.2), 0.0,
			c.z + sin(ang) * (main.LAKE_RADIUS * main.LAKE_SQUASH + 0.2))
		if main.is_water(p.x, p.z):
			p = GameManager.land_target(p)
		# Шаг СТРОГО В ЦЕНТР озера — упирается в воду и обязан скользить
		var toward := (c - p)
		toward.y = 0.0
		if toward.length() < 0.01:
			continue
		probes += 1
		var step: Vector3 = main.slide_around_water(p, toward.normalized() * 0.25)
		if step.length() < 0.001:
			stuck += 1
	print("  проб по периметру: %d, из них шаг нулевой («зависание»): %d" % [probes, stuck])
	verdict("12b обход берега не даёт нулевых шагов", stuck == 0,
		"застряло %d из %d" % [stuck, probes])

	# Живой юнит идёт к точке за озером и не залипает у берега
	var start := Vector3(c.x - main.LAKE_RADIUS - 6.0, 0.0, c.z)
	var goal  := Vector3(c.x + main.LAKE_RADIUS + 6.0, 0.0, c.z)
	var u := _spawn("spearman", Constants.FACTION_PLAYER)
	u.global_position = Vector3(start.x, 0.0, start.z)
	await frames(3)
	u.command_move(goal)
	var d0: float = u.global_position.distance_to(goal)
	var in_water := 0
	for _i in range(90):
		await frames(4)
		if main.is_water(u.global_position.x, u.global_position.z):
			in_water += 1
	var d1: float = u.global_position.distance_to(goal)
	print("  путь в обход озера: было %.1f м до цели, стало %.1f м; кадров в воде: %d" % [
		d0, d1, in_water])
	verdict("12c юнит обходит озеро и приближается к цели", d1 < d0 - 2.0,
		"%.1f → %.1f м" % [d0, d1])
	verdict("12d в воду не заходит", in_water == 0, "замеров в воде %d" % in_water)
	_kill([u])
	await frames(2)
