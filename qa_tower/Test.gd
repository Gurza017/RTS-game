extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: БАШНЯ, СТРЕЛКОВАЯ, ДОМА, ЛИМИТ НАСЕЛЕНИЯ, АУДИО-ОКНО (09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A МЕНЮ ПОСТРОЕК — все здания цветовой папки строятся рабочим, у каждого
##     есть картинка в КАЖДОМ цвете и иконка; башня ведёт на башню, а не на дом.
##   B БАШНЯ — обзор TOWER_VISION в тумане, принимает ТОЛЬКО лучников и один
##     отряд, не выпускает сама, часовой на площадке, ПКМ выпускает, руины в
##     долю ruin_scale, не считается крепостью. ГАРНИЗОН СТРЕЛЯЕТ с площадки
##     (B8б-B8д, 09.09.2026): по врагу в TOWER_FIRE_RANGE летят стрелы, за
##     дальностью — нет; удар по укрытому лучнику уходит в запас башни; укрытый
##     снят из сетки ядра; снесённая башня выпускает отряд, и он снова уязвим.
##   C СТРЕЛКОВАЯ — лучники нанимаются в ней, а в бараках нет.
##   D ДОМА И ЛИМИТ — три дома одного баланса, слоты лимита, ворота найма.
##   E АУДИО-ОКНО — закон громкости марша: 15 м полная, 40 м ноль, зум гасит.
##
## Числа не хардкодятся: всё меряется по конфигу и свойствам (правило 10).
## Ожидание — физкадрами (правило 11).
##
## Запуск: godot --headless --path . res://qa_tower/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GS   := preload("res://scripts/game_settings.gd")
const _Tower := preload("res://scripts/Tower.gd")
const _Archery := preload("res://scripts/Archery.gd")
const _House := preload("res://scripts/House.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")

var main = null
var sm   = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	# Сторож: ошибка внутри корутины убивает её молча (см. CLAUDE.md)
	var t := get_tree().create_timer(240.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	await frames(4)

	var keep := Castle.new()
	keep.faction = Constants.FACTION_PLAYER
	main.world_add(keep)
	keep.global_position = Vector3(-90.0,
		GameManager.get_terrain_height(-90.0, 90.0), 90.0)
	await pframes(6)

	_check_catalog()
	await _check_tower(keep)
	await _check_archery(keep)
	await _check_houses(keep)
	_check_audio_window()
	_finish()

func _finish() -> void:
	print("\n═════ ИТОГ qa_tower: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. МЕНЮ ПОСТРОЕК
# ═════════════════════════════════════════════════════════════════════════════
func _check_catalog() -> void:
	print("\n═════ A. МЕНЮ ПОСТРОЕК РАБОЧЕГО ═════")
	var ids: Array = _UCfg.worker_buildable_ids()
	print("  строит рабочий: %s" % str(ids))
	var want: Array = ["castle", "barracks", "archery", "tower", "smithy",
		"house", "house2", "house3"]
	var missing: Array = []
	for w in want:
		if not ids.has(w):
			missing.append(w)
	verdict("A1 в меню рабочего все здания цветовой папки", missing.is_empty(),
		"нет: %s" % str(missing))
	# У каждого — картинка в КАЖДОМ цвете и иконка
	var bad: Array = []
	for w in want:
		var icon: String = String(_UCfg.building_cfg(w).get("icon", ""))
		if icon.is_empty() or not ResourceLoader.exists(icon):
			bad.append(w + ":icon")
		for c in _GS.COLORS:
			var p: String = _GS.building_sprite("humans", String(c), w)
			if p.is_empty() or not ResourceLoader.exists(p):
				bad.append(w + ":" + String(c))
	verdict("A2 у каждого здания есть иконка и спрайт во всех цветах",
		bad.is_empty(), "нет: %s" % str(bad))
	# Башня ведёт на башню: спрайт Tower, а строится Tower.gd
	var tower_sprite: String = _GS.building_sprite("humans", "Blue", "tower").get_file()
	var site: Building = _CSite.new()
	site.target_id = "tower"
	var made: Building = site._make_target()
	var is_tower: bool = made != null and made.get_script() == _Tower
	if made != null:
		made.free()
	site.free()
	verdict("A3 кнопка башни строит башню, а не дом",
		tower_sprite == "Tower.png" and is_tower,
		"спрайт %s, класс башни=%s" % [tower_sprite, str(is_tower)])
	# У рудника иконка больше не башня
	var mine_icon: String = String(_UCfg.building_cfg("mine").get("icon", "")).get_file()
	verdict("A4 у рудника своя иконка, не Tower.png", mine_icon != "Tower.png",
		"иконка рудника %s" % mine_icon)
	# Три дома — один баланс
	var same := true
	for k in ["max_hp", "build_time", "cost_wood", "cost_gold", "cost_stone"]:
		var a: float = _UCfg.building_stat("house", k)
		if _UCfg.building_stat("house2", k) != a or _UCfg.building_stat("house3", k) != a:
			same = false
	verdict("A5 три дома — разная картинка, один баланс", same
		and _UCfg.building_size("house2") == _UCfg.building_size("house"))

# ═════════════════════════════════════════════════════════════════════════════
# B. БАШНЯ
# ═════════════════════════════════════════════════════════════════════════════
func _spawn_squad(kind: String, at: Vector3, n: int) -> Array:
	return _spawn_squad_of(Constants.FACTION_PLAYER, kind, at, n)

func _spawn_squad_of(fac: int, kind: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var scene: PackedScene = Building.PRELOAD_SCENES[kind]
	for i in range(n):
		var u: Unit = scene.instantiate()
		u.faction = fac
		main.world_add(u)
		u.global_position = at + Vector3(float(i % 5) * 0.7 - 1.4, 0.0, float(i / 5) * 0.7)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _kill_squad(sid: int) -> void:
	for m in GameManager.squad_members(sid):
		var u := m as Unit
		if u != null and is_instance_valid(u):
			u.take_damage(u.max_health * 10.0)

func _check_tower(keep: Castle) -> void:
	print("\n═════ B. БАШНЯ ═════")
	var tower: Castle = _Tower.new()
	tower.faction = Constants.FACTION_PLAYER
	main.world_add(tower)
	# ВНУТРИ КАРТЫ (MAP_HALF_Z = 73): у замка стенда z = 90 лежит за краем, и
	# маска тумана там не существует вовсе — is_lit отвечал false не потому,
	# что темно, а потому, что клетки нет
	var tp := Vector3(30.0, GameManager.get_terrain_height(30.0, -30.0), -30.0)
	tower.global_position = tp
	await pframes(4)

	verdict("B1 башня — не крепость (зона застройки, «в замок», поражение)",
		not tower.is_stronghold() and keep.is_stronghold())
	verdict("B2 обзор башни = TOWER_VISION и выше обзора лучника",
		is_equal_approx(tower.vision_radius(), _UCfg.TOWER_VISION)
			and _UCfg.TOWER_VISION > _UCfg.vision_radius(
				_UCfg.stat("archer", "attack_range", 20.0)),
		"башня %.0f, лучник %.1f, здание %.0f" % [tower.vision_radius(),
			_UCfg.vision_radius(_UCfg.stat("archer", "attack_range", 20.0)),
			_UCfg.BUILDING_VISION])
	# Туман: башня раскрывает круг своего радиуса
	if GameManager.fog != null:
		GameManager.fog.enabled = true
		# Маска пересчитывается раз в UPDATE_INTERVAL — ждём физкадрами с запасом
		await pframes(int(GameManager.fog.UPDATE_INTERVAL * 60.0) * 3 + 6)
		var near_ok: bool = GameManager.fog.is_lit(tp.x + _UCfg.TOWER_VISION * 0.8, tp.z)
		var far_ok: bool = not GameManager.fog.is_lit(tp.x + _UCfg.TOWER_VISION * 1.6
			+ _UCfg.BUILDING_VISION, tp.z)
		verdict("B2б туман: на 0.8 радиуса светло, далеко за ним темно",
			near_ok and far_ok, "близко=%s, далеко темно=%s" % [str(near_ok), str(far_ok)])
		GameManager.fog.enabled = false
		await frames(2)
	else:
		print("  тумана нет — B2б пропущена")

	# Габарит сопоставим с кузницей
	var smithy_h: float = 0.0
	var tex_s := load(_GS.building_sprite("humans", "Blue", "smithy")) as Texture2D
	var tex_t := load(_GS.building_sprite("humans", "Blue", "tower")) as Texture2D
	if tex_s != null and tex_t != null:
		smithy_h = Building.sprite_quad_size(tex_s, _UCfg.building_size("smithy")).y
		var tower_h: float = Building.sprite_quad_size(tex_t, _UCfg.building_size("tower")).y
		verdict("B3 башня по высоте сопоставима с кузницей (±15 %)",
			absf(tower_h - smithy_h) <= smithy_h * 0.15,
			"башня %.2f м, кузница %.2f м" % [tower_h, smithy_h])
	# ── РАЗВОРОТ ТРЕБОВАНИЯ: У БАШНИ ТЕПЕРЬ СВОИ КАРТИНКИ ЭТАПОВ ───────────
	# Здесь проверялось «стройка и руины — общая „домовая“ картинка, ужатая
	# долей 0.6». Владелец заказал башне СВОИ спрайты (Tower_Construction /
	# Tower_Destroyed, 128×256 — ровно как сам Tower.png), и ужимать больше
	# нечего: доля равна единице. Полная проверка цепочки состояний —
	# в стенде qa_tower_states
	var b_path: String = GameManager.construction_sprite_path(
		Constants.FACTION_PLAYER, "tower")
	var r_path: String = GameManager.ruin_sprite_path(
		Constants.FACTION_PLAYER, "tower")
	verdict("B3б у башни СВОИ картинки стройки и руин, в полный размер",
		b_path != GameManager.construction_sprite_path(Constants.FACTION_PLAYER, "house")
			and r_path != GameManager.ruin_sprite_path(Constants.FACTION_PLAYER, "house")
			and ResourceLoader.exists(b_path) and ResourceLoader.exists(r_path)
			and absf(_UCfg.building_stat("tower", "construction_scale", 1.0) - 1.0) < 0.001
			and absf(tower.ruin_scale() - 1.0) < 0.001,
		"%s / %s, доли %.2f и %.2f" % [b_path.get_file(), r_path.get_file(),
			_UCfg.building_stat("tower", "construction_scale", 1.0),
			tower.ruin_scale()])

	# Копейщиков не принимает
	var sp := _spawn_squad("spearman", tp + Vector3(0, 0, 10.0), 8)
	var sp_ok: bool = tower.request_garrison(int(sp[0]))
	verdict("B4 копейщиков башня НЕ принимает", not sp_ok)
	_kill_squad(int(sp[0]))
	await pframes(3)

	# Лучников принимает, один отряд
	var ar := _spawn_squad("archer", tp + Vector3(0, 0, 10.0), 10)
	var ar2 := _spawn_squad("archer", tp + Vector3(6, 0, 10.0), 10)
	var a_ok: bool = tower.request_garrison(int(ar[0]))
	var a2_ok: bool = tower.request_garrison(int(ar2[0]))
	verdict("B5 лучников принимает, но только %d отряд" % _UCfg.TOWER_GARRISON_LIMIT,
		a_ok and not a2_ok, "первый=%s, второй=%s" % [str(a_ok), str(a2_ok)])
	_kill_squad(int(ar2[0]))
	var waited := 0
	while waited < 1800:
		await get_tree().physics_frame
		waited += 1
		if not tower.garrison.is_empty():
			break
	var inside := 0
	for m in ar[1]:
		if is_instance_valid(m) and (m as Unit).garrisoned:
			inside += 1
	verdict("B6 отряд лучников зашёл внутрь", inside == (ar[1] as Array).size()
		and not tower.garrison.is_empty(),
		"внутри %d из %d за %d физкадров" % [inside, (ar[1] as Array).size(), waited])
	await frames(3)
	verdict("B7 с лучниками внутри на площадке стоит часовой",
		tower.sentinel_visible(), "часовой виден=%s" % str(tower.sentinel_visible()))
	# Часовой стоит выше подножия и ниже макушки рисунка
	var sent := tower.get_node_or_null("Sentinel") as Node3D
	var spr := tower.get_node_or_null("BuildingSprite") as MeshInstance3D
	if sent != null and spr != null:
		var top: float = (spr.mesh as QuadMesh).size.y * tower._BBUtilT.V_STRETCH
		verdict("B7б часовой стоит на площадке: между подножием и макушкой",
			sent.position.y > top * 0.3 and sent.position.y < top,
			"y=%.2f при высоте рисунка %.2f" % [sent.position.y, top])
	# Не выходит сам, хотя полон и здоров
	await pframes(90)
	verdict("B8 полный и здоровый отряд остаётся в башне (нет авто-выхода)",
		not tower.garrison.is_empty())

	# ── ГАРНИЗОН СТРЕЛЯЕТ, САМ НЕУЯЗВИМ (09.09.2026) ─────────────────────
	# Враг в 20 м — внутри дальности огня (TOWER_FIRE_RANGE) и вне дальности
	# лучника с земли не обязан быть; меряем СВОЙСТВО: выстрелы пошли и запас
	# врага убыл
	var fr: float = tower.fire_range()
	var arng: float = (ar[1][0] as Unit).attack_range
	# Бафф высоты (ТЗ 14.09.2026): с площадки лук бьёт на ×GARRISON_RANGE_MULT,
	# но всё ещё ближе обзора башни
	verdict("B8а дальность огня башни = дальность лучника × бафф высоты, а не обзор башни",
		is_equal_approx(fr, arng * _UCfg.GARRISON_RANGE_MULT) and fr < _UCfg.TOWER_VISION,
		"огонь %.1f, лук %.1f × %.2f, обзор %.0f" % [fr, arng, _UCfg.GARRISON_RANGE_MULT, _UCfg.TOWER_VISION])
	var foes := _spawn_squad_of(Constants.FACTION_ENEMY, "spearman",
		tp + Vector3(fr * 0.6, 0.0, 0.0), 8)
	var shots0: int = tower.shots_fired
	var foe_hp0 := 0.0
	for m in foes[1]:
		foe_hp0 += (m as Unit).current_health
	await pframes(240)
	var foe_hp := 0.0
	for m in foes[1]:
		if is_instance_valid(m) and not (m as Unit).is_dead():
			foe_hp += (m as Unit).current_health
	verdict("B8б гарнизон стреляет с площадки: выстрелы идут, запас врага убывает",
		tower.shots_fired > shots0 and foe_hp < foe_hp0,
		"выстрелов %d за 4 с, запас врага %.0f → %.0f" % [tower.shots_fired - shots0, foe_hp0, foe_hp])
	# Удар по укрытому лучнику — в стены, а не в лучника
	var a0: Unit = ar[1][0]
	var ahp: float = a0.current_health
	var thp: float = tower.current_health
	a0.take_damage(50.0, foes[1][0])
	verdict("B8в урон по укрытому лучнику уходит в запас башни, лучник цел",
		is_equal_approx(a0.current_health, ahp) and tower.current_health < thp,
		"лучник %.0f → %.0f, башня %.0f → %.0f" % [ahp, a0.current_health, thp, tower.current_health])
	# Укрытый снят из сетки ядра: поиск своих у ворот его не находит
	var found = GameManager.army.nearest_of_side(tp.x, tp.z, Constants.FACTION_PLAYER, 8.0)
	verdict("B8г укрытый лучник не числится в сетке ядра (цели и стрелы его не найдут)",
		found == null, "найден: %s" % str(found))
	_kill_squad(int(foes[0]))
	await pframes(3)
	# За дальностью огня башня молчит
	# Дальше лука, но ВНУТРИ обзора башни: башня видит, а стрелять не вправе
	var far := _spawn_squad_of(Constants.FACTION_ENEMY, "spearman",
		tp + Vector3(minf(fr + 6.0, _UCfg.TOWER_VISION - 2.0), 0.0, 0.0), 6)
	await pframes(30)
	shots0 = tower.shots_fired
	await pframes(180)
	verdict("B8д за дальностью лука (%.0f м), но в обзоре башни — не стреляет" % fr,
		tower.shots_fired == shots0, "выстрелов %d" % (tower.shots_fired - shots0))
	_kill_squad(int(far[0]))
	await pframes(3)

	# Панель башни: ХП и кто внутри
	sm.selected_units.clear()
	sm.selected_units.append(tower)
	sm._sel_rebuild()
	main.hud.show_selection([tower])
	await frames(2)
	var txt: String = String(main.hud.info_label.text)
	var cap_ok: bool = main.hud._castle_boost
	verdict("B9 панель башни: обзор и отряд внутри",
		txt.find("Обзор") >= 0 and txt.to_lower().find("лучник") >= 0 and cap_ok,
		"текст «%s»" % txt.replace("\n", " | "))
	sm.selected_units.clear()
	sm._sel_rebuild()
	main.hud.show_selection([])

	# ПКМ по башне выпускает (без выделения)
	var released: bool = sm._try_release_tower(tower)
	await pframes(4)
	var outside := 0
	for m in ar[1]:
		if is_instance_valid(m) and not (m as Unit).garrisoned:
			outside += 1
	verdict("B10 ПКМ по башне выпускает лучников", released and tower.garrison.is_empty()
		and outside == (ar[1] as Array).size(),
		"снаружи %d из %d" % [outside, (ar[1] as Array).size()])
	await frames(2)
	verdict("B11 без гарнизона часовой спрятан", not tower.sentinel_visible())
	verdict("B11б ПКМ по пустой башне ничего не делает", not sm._try_release_tower(tower))

	# Руины в долю
	var parent := tower.get_parent()
	var before: int = parent.get_child_count()
	tower.take_damage(tower.max_health * 10.0)
	await frames(2)
	var ruin: Node3D = null
	for c in parent.get_children():
		if (c as Node).name == "Ruin_tower":
			ruin = c
	var rw: float = -1.0
	if ruin != null:
		var rs := ruin.get_node_or_null("RuinSprite") as MeshInstance3D
		if rs != null:
			rw = (rs.mesh as QuadMesh).size.x
	var tex_r := load(GameManager.ruin_sprite_path(Constants.FACTION_PLAYER, "tower")) as Texture2D
	var full_w: float = Building.sprite_quad_size(tex_r, _UCfg.building_size("tower")).x if tex_r else 0.0
	verdict("B12 пепелище башни — общее, в долю ruin_scale", ruin != null and rw > 0.0
		and absf(rw - full_w * _UCfg.building_stat("tower", "ruin_scale", 1.0)) < 0.01,
		"ширина руин %.2f при полной %.2f (доля %.2f), детей было %d" % [
			rw, full_w, _UCfg.building_stat("tower", "ruin_scale", 1.0), before])
	_kill_squad(int(ar[0]))
	await pframes(3)

	# ── СНЕСЁННАЯ БАШНЯ ВЫПУСКАЕТ ОТРЯД, И ОН СНОВА УЯЗВИМ ────────────────
	var tower2: Castle = _Tower.new()
	tower2.faction = Constants.FACTION_PLAYER
	main.world_add(tower2)
	var tp2 := Vector3(60.0, GameManager.get_terrain_height(60.0, -30.0), -30.0)
	tower2.global_position = tp2
	await pframes(4)
	var ar3 := _spawn_squad("archer", tp2 + Vector3(0, 0, 8.0), 6)
	tower2.request_garrison(int(ar3[0]))
	var w2 := 0
	while w2 < 1800:
		await get_tree().physics_frame
		w2 += 1
		if not tower2.garrison.is_empty():
			break
	var inside2 := 0
	for m in ar3[1]:
		if is_instance_valid(m) and (m as Unit).garrisoned:
			inside2 += 1
	tower2.take_damage(tower2.max_health * 10.0)
	await pframes(4)
	var out2 := 0
	var hurt := 0
	for m in ar3[1]:
		if not is_instance_valid(m):
			continue
		var u := m as Unit
		if not u.garrisoned:
			out2 += 1
			var h0: float = u.current_health
			u.take_damage(10.0)
			if u.current_health < h0:
				hurt += 1
	verdict("B13 снесённая башня выпускает гарнизон, и он снова получает урон",
		inside2 == (ar3[1] as Array).size() and out2 == inside2 and hurt == out2,
		"внутри было %d, вышло %d, уязвимых %d" % [inside2, out2, hurt])
	_kill_squad(int(ar3[0]))
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. СТРЕЛКОВАЯ
# ═════════════════════════════════════════════════════════════════════════════
func _check_archery(keep: Castle) -> void:
	print("\n═════ C. СТРЕЛКОВАЯ ═════")
	verdict("C1 лучник нанимается в стрелковой, а не в бараках",
		not _UCfg.train_cfg("archery", "archer").is_empty()
			and _UCfg.train_cfg("barracks", "archer").is_empty())
	verdict("C2 в бараках — пехота (копейщики и мечники)",
		not _UCfg.train_cfg("barracks", "spearman").is_empty()
			and not _UCfg.train_cfg("barracks", "warrior").is_empty())
	var ar: Building = _Archery.new()
	ar.faction = Constants.FACTION_PLAYER
	main.world_add(ar)
	ar.global_position = keep.global_position + Vector3(20.0, 0.0, 0.0)
	await pframes(3)
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD, 5000.0)
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD, 5000.0)
	var ok: bool = ar.train_archer()
	var br := Barracks.new()
	br.faction = Constants.FACTION_PLAYER
	main.world_add(br)
	br.global_position = keep.global_position + Vector3(30.0, 0.0, 0.0)
	await pframes(3)
	var b_no: bool = br.train_from_config("archer")
	verdict("C3 заказ лучника: стрелковая принимает, бараки отклоняют", ok and not b_no,
		"стрелковая=%s, бараки=%s" % [str(ok), str(b_no)])
	if ok:
		ar.cancel_order("archer")
	br.queue_free()
	ar.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# D. ДОМА И ЛИМИТ НАСЕЛЕНИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _check_houses(keep: Castle) -> void:
	print("\n═════ D. ДОМА И ЛИМИТ ═════")
	verdict("D0 в стенде лимит выключен сам (Main не текущая сцена)",
		not GameManager.pop_limit_enabled)
	GameManager.pop_limit_enabled = true
	var f: int = Constants.FACTION_PLAYER
	# Чистая база: рабочих и отрядов игрока в стенде нет
	var h0: int = GameManager.house_count(f)
	var c0: int = GameManager.castle_count(f)
	var wc0: int = GameManager.pop_worker_cap(f)
	var sc0: int = GameManager.pop_squad_cap(f)
	# КРЕПОСТЬ ТОЖЕ ДАЁТ ЛИМИТ (заказ 10.09.2026): в стенде на карте стоит
	# замок, поэтому ожидание — база плюс его слоты, а не одна база
	verdict("D1 без домов потолки равны базе плюс крепости",
		h0 == 0 and wc0 == _UCfg.pop_worker_cap(0, c0)
		and sc0 == _UCfg.pop_squad_cap(0, c0),
		"домов %d, крепостей %d, раб. %d, отр. %d" % [h0, c0, wc0, sc0])
	# Три дома разного вида
	var houses: Array = []
	var i := 0
	for hid in _UCfg.HOUSE_IDS:
		var h: Building = _House.new()
		h.variant_id = String(hid)
		h.faction = f
		main.world_add(h)
		h.global_position = keep.global_position + Vector3(-15.0 - 5.0 * float(i), 0.0, 0.0)
		houses.append(h)
		i += 1
	await pframes(3)
	var ids_ok := true
	var sprites: Dictionary = {}
	for h in houses:
		if not _UCfg.is_house((h as Building).building_id):
			ids_ok = false
		var spr := (h as Node).get_node_or_null("BuildingSprite")
		sprites[(h as Building).building_id] = spr != null
	verdict("D2 три дома встали со своими картинками", ids_ok and sprites.size() == 3
		and not sprites.values().has(false), "%s" % str(sprites))
	var wc: int = GameManager.pop_worker_cap(f)
	var sc: int = GameManager.pop_squad_cap(f)
	verdict("D3 каждый дом даёт +%d рабочих и +%d отряда" % [
			_UCfg.HOUSE_WORKER_SLOTS, _UCfg.HOUSE_SQUAD_SLOTS],
		wc == _UCfg.pop_worker_cap(3, GameManager.castle_count(f))
			and sc == _UCfg.pop_squad_cap(3, GameManager.castle_count(f)),
		"раб. %d, отр. %d" % [wc, sc])
	# Панель дома
	main.hud.show_selection([houses[0]])
	await frames(2)
	var txt: String = String(main.hud.info_label.text)
	verdict("D4 панель дома показывает слоты и еду",
		txt.find("рабочих") >= 0 and txt.find("отряда") >= 0 and txt.find("еды") >= 0,
		"текст «%s»" % txt.replace("\n", " | "))
	main.hud.show_selection([])
	# Ворота найма: отряды до потолка принимаются, сверх — нет и не оплачиваются
	var br := Barracks.new()
	br.faction = f
	main.world_add(br)
	br.global_position = keep.global_position + Vector3(30.0, 0.0, 0.0)
	await pframes(3)
	ResourceManager.add_resource(f, Constants.RESOURCE_WOOD, 50000.0)
	ResourceManager.add_resource(f, Constants.RESOURCE_GOLD, 50000.0)
	var accepted := 0
	for _k in range(sc + 3):
		if br.train_from_config("spearman"):
			accepted += 1
	var gold_before: float = ResourceManager.get_amount(f, Constants.RESOURCE_GOLD)
	var extra: bool = br.train_from_config("spearman")
	var gold_after: float = ResourceManager.get_amount(f, Constants.RESOURCE_GOLD)
	verdict("D5 найм отрядов упирается в потолок, лишний не оплачивается",
		accepted == sc and not extra and is_equal_approx(gold_before, gold_after),
		"принято %d при потолке %d, лишний=%s, золото %.0f→%.0f" % [
			accepted, sc, str(extra), gold_before, gold_after])
	verdict("D5б заказанные считаются занятыми слотами",
		GameManager.pop_squads_used(f) == sc, "занято %d" % GameManager.pop_squads_used(f))
	# Рабочие — своя шкала
	# ЧАСТЬ ПОТОЛКА УЖЕ ЗАНЯТА: партия открывается стартовой бригадой
	# (Main.START_WORKER_RESOURCES, пять рабочих), и свободных слотов ровно
	# «потолок минус занятые». Прежнее ожидание w_acc == wc держалось на том,
	# что рабочих у игрока в стенде не было вовсе
	var used0: int = GameManager.pop_workers_used(f)
	var w_acc := 0
	for _k2 in range(wc + 2):
		if keep.train_from_config("worker"):
			w_acc += 1
	verdict("D6 найм рабочих упирается в свой потолок", w_acc == wc - used0,
		"принято %d при потолке %d и занятых %d" % [w_acc, wc, used0])
	# Снос дома снимает слоты
	(houses[2] as Building).take_damage(1e9)
	await frames(2)
	verdict("D7 снесённый дом слотов не даёт",
		GameManager.pop_worker_cap(f) == wc - _UCfg.HOUSE_WORKER_SLOTS,
		"потолок рабочих %d" % GameManager.pop_worker_cap(f))
	# ИИ лимит не касается
	verdict("D8 на ИИ лимит не действует", GameManager.pop_allows(Constants.FACTION_ENEMY, "spearman"))
	# Уборка
	for _k3 in range(sc + 2):
		br.cancel_order("spearman")
	for _k4 in range(wc + 2):
		keep.cancel_order("worker")
	br.queue_free()
	for h in houses:
		if is_instance_valid(h):
			(h as Node).queue_free()
	GameManager.pop_limit_enabled = false
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# E. АУДИО-ОКНО КАМЕРЫ
# ═════════════════════════════════════════════════════════════════════════════
func _check_audio_window() -> void:
	print("\n═════ E. АУДИО-ОКНО МАРША ═════")
	var am = AudioManager
	var full: float = am.MARCH_FULL_RADIUS
	var fade: float = am.MARCH_FADE_RADIUS
	var g_in: float = am._march_gain_at(full * full * 0.9, fade)
	var g_mid: float = am._march_gain_at(((full + fade) * 0.5) * ((full + fade) * 0.5), fade)
	var g_out: float = am._march_gain_at(fade * fade * 1.01, fade)
	verdict("E1 до %.0f м — полная громкость, за %.0f м — ноль, между — спад" % [full, fade],
		is_equal_approx(g_in, 1.0) and g_out == 0.0 and g_mid > 0.0 and g_mid < 1.0,
		"внутри %.2f, середина %.2f, снаружи %.2f" % [g_in, g_mid, g_out])
	verdict("E1б окно не шире видимой полосы", am.march_cutoff() <= fade
		and am.march_cutoff() <= maxf(GameManager.view_radius(), fade),
		"граница %.1f при полосе %.1f" % [am.march_cutoff(), GameManager.view_radius()])
	# Зум
	var z0: float = GameManager._view_zoom
	GameManager._view_zoom = 0.0
	var gz0: float = am.march_zoom_gain()
	GameManager._view_zoom = 0.5
	var gz5: float = am.march_zoom_gain()
	GameManager._view_zoom = 1.0
	var gz1: float = am.march_zoom_gain()
	GameManager._view_zoom = z0
	verdict("E2 зум: вплотную полная, на середине тише, на пределе ноль",
		is_equal_approx(gz0, 1.0) and gz5 < gz0 and gz5 > 0.0 and gz1 == 0.0,
		"0→%.2f, 0.5→%.2f, 1→%.2f" % [gz0, gz5, gz1])
	# На пределе отдаления марш не получает голосов вовсе
	am.march_stop_all()
	GameManager._view_zoom = 1.0
	var focus: Vector3 = am.march_focus()
	am.march_report([{"sid": 970001, "at": focus + Vector3(2.0, 0.0, 0.0), "run": false}])
	var used_far: int = am._march.size()
	GameManager._view_zoom = 0.0
	am.march_report([{"sid": 970001, "at": focus + Vector3(2.0, 0.0, 0.0), "run": false}])
	var used_near: int = am._march.size()
	am.march_stop_all()
	GameManager._view_zoom = z0
	verdict("E3 на пределе отдаления голос не выдаётся, вплотную — выдаётся",
		used_far == 0 and used_near == 1, "далеко %d, близко %d" % [used_far, used_near])
	# Расстояние меряется ОТ ФОКУСА: отряд в 2 м от фокуса звучит, в 1.5 окна — нет
	am.march_report([{"sid": 970002, "at": focus + Vector3(fade * 1.5, 0.0, 0.0), "run": false}])
	var used_out: int = am._march.size()
	am.march_stop_all()
	verdict("E4 отряд за окном от фокуса голоса не получает", used_out == 0,
		"голосов %d" % used_out)
	# Темп: шаг +5..10 %, бег быстрее прежних 1.12 на ~10 %, старт бега без тишины
	verdict("E5 шаг ускорен на 5-10 %, бег — ещё на ~10 %",
		am.MARCH_WALK_PITCH >= 1.05 and am.MARCH_WALK_PITCH <= 1.10
			and am.MARCH_RUN_PITCH >= 1.12 * 1.08 and am.MARCH_RUN_PITCH <= 1.12 * 1.12,
		"шаг %.2f, бег %.2f" % [am.MARCH_WALK_PITCH, am.MARCH_RUN_PITCH])
	am.march_report([{"sid": 970003, "at": focus, "run": true}])
	var run_phase: float = -1.0
	if am._march.has(970003):
		run_phase = float((am._march[970003] as Dictionary)["phase"])
	am.march_stop_all()
	verdict("E6 беговой луп стартует и зацикливается с MARCH_RUN_START_SEC",
		is_equal_approx(run_phase, am.MARCH_RUN_START_SEC) and am.MARCH_RUN_START_SEC > 0.5,
		"старт %.2f с (обмер тишины 0.78 с)" % run_phase)
