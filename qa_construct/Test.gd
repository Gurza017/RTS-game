extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СТРОЙКА И РУИНЫ (папка process_building_destroeyrs)
## ═══════════════════════════════════════════════════════════════════════════
## Заказ владельца:
##   • Замок ставится БЕЗ списания ресурсов, сначала как стройка
##     (Castle_Construction), по готовности — настоящий Замок, при сносе —
##     Castle_Destroyed;
##   • остальные здания строятся ЗА РЕСУРСЫ, вместо старой процедурной
##     3D-заглушки показывают House_Construction, при сносе — House_Destroyed.
##
## Проверяется вся цепочка на живой сцене: какие узлы и какие текстуры реально
## оказались в дереве. Числа берутся из конфига (CONSTRUCTION_MIN_SEC,
## CASTLE_BUILD_SEC), а не переписываются сюда.
##
## Запуск: godot --headless --path . res://qa_construct/Test.tscn

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _GS    := preload("res://scripts/game_settings.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")

var main = null
var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

## Найти потомка-меш по имени и вернуть его текстуру (null — не нашли)
func _sprite_tex(root: Node, want_name: String) -> Texture2D:
	for c in root.get_children():
		if c is MeshInstance3D and c.name == want_name:
			var q := (c as MeshInstance3D).mesh as QuadMesh
			if q != null and q.material is ShaderMaterial:
				return (q.material as ShaderMaterial).get_shader_parameter("albedo_tex") as Texture2D
		var deep := _sprite_tex(c, want_name)
		if deep != null:
			return deep
	return null

func _find_ruin(name_part: String) -> Node3D:
	for c in main.world_root().get_children():
		if c is Node3D and String(c.name).begins_with("Ruin_") \
				and String(c.name).contains(name_part):
			return c
	return null

func _run() -> void:
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(5)

	_test_assets()
	await _test_castle_free_and_built()
	await _test_house_construction()
	await _test_ruins()

	print("\n=== ИТОГ qa_construct: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ЧЕТЫРЕ КАРТИНКИ НА МЕСТЕ
# ═════════════════════════════════════════════════════════════════════════════
func _test_assets() -> void:
	print("\n═════ A. АССЕТЫ ═════")
	# Не импортированный PNG существует на диске, но ResourceLoader его не видит —
	# именно это правило записано в CLAUDE.md, поэтому проверяем ИМЕННО загрузку
	var want := {
		"стройка замка":  GameManager.construction_sprite_path(Constants.FACTION_PLAYER, "castle"),
		"руины замка":    GameManager.ruin_sprite_path(Constants.FACTION_PLAYER, "castle"),
		"стройка дома":   GameManager.construction_sprite_path(Constants.FACTION_PLAYER, "barracks"),
		"руины дома":     GameManager.ruin_sprite_path(Constants.FACTION_PLAYER, "barracks"),
	}
	for label in want:
		var path: String = want[label]
		verdict("A %s: картинка загружается" % label,
			not path.is_empty() and ResourceLoader.exists(path), path)
	# Кузница и рудник обязаны брать ОБЩИЙ «домовой» набор, а не свой
	verdict("A общий набор для всех, кроме замка",
		GameManager.construction_sprite_path(Constants.FACTION_PLAYER, "smithy")
			== GameManager.construction_sprite_path(Constants.FACTION_PLAYER, "mine"),
		"кузница и рудник берут одну и ту же картинку")
	verdict("A у замка набор СВОЙ",
		GameManager.construction_sprite_path(Constants.FACTION_PLAYER, "castle")
			!= GameManager.construction_sprite_path(Constants.FACTION_PLAYER, "barracks"))

# ═════════════════════════════════════════════════════════════════════════════
# B. ЗАМОК: БЕСПЛАТНО, ЧЕРЕЗ СТРОЙКУ
# ═════════════════════════════════════════════════════════════════════════════
func _test_castle_free_and_built() -> void:
	print("\n═════ B. ЗАМОК ═════")
	var before := {}
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		before[t] = ResourceManager.get_amount(Constants.FACTION_PLAYER, t)

	main.enter_castle_placement(false)      # false = «не стартовый», т.е. платный по-старому
	verdict("B1 переход в режим постановки состоялся",
		main._phase == main.Phase.PLACING_CASTLE, "фаза %d" % main._phase)
	var spent := ""
	for t in before:
		var now: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, t)
		if not is_equal_approx(now, float(before[t])):
			spent += "%d: %.0f→%.0f " % [t, float(before[t]), now]
	verdict("B2 за замок НЕ списано ничего", spent.is_empty(),
		"списано %s" % spent if not spent.is_empty() else "")

	# Ставим замок кликом в центр экрана
	main._try_place_castle(Vector2(640, 360))
	await frames(3)
	var site: Node = null
	for b in get_tree().get_nodes_in_group("construction_sites"):
		if (b as Node).get("target_id") == "castle":
			site = b
	verdict("B3 на карте стоит СТРОЙКА замка, а не готовый замок", site != null)
	if site == null:
		return
	var tex := _sprite_tex(site, "ConstructionSprite")
	var want_path: String = GameManager.construction_sprite_path(Constants.FACTION_PLAYER, "castle")
	verdict("B4 у стройки картинка Castle_Construction",
		tex != null and tex.resource_path == want_path,
		"нарисовано: %s" % (tex.resource_path if tex != null else "ничего"))
	verdict("B5 стройке замка не нужна бригада", bool(site.get("self_building")))
	# Срок берётся из конфига, а не из головы
	var want_time: float = maxf(_UCfg.building_stat("castle", "build_time", 0.0),
		_UCfg.CASTLE_BUILD_SEC)
	verdict("B6 срок стройки взят из конфига",
		is_equal_approx(float(site.get("build_time")), want_time),
		"у площадки %.1f c, в конфиге %.1f c" % [float(site.get("build_time")), want_time])

	# Ждём достройки: срок конечный и известен
	var t0: int = Time.get_ticks_msec()
	var castle: Castle = null
	while Time.get_ticks_msec() - t0 < int(want_time * 1000.0) + 6000:
		await get_tree().physics_frame
		for b in get_tree().get_nodes_in_group("player_buildings"):
			if b is Castle:
				castle = b
				break
		if castle != null:
			break
	verdict("B7 стройка сама превратилась в готовый Замок", castle != null)
	verdict("B8 площадки на карте больше нет",
		not is_instance_valid(site) or site.is_queued_for_deletion())

# ═════════════════════════════════════════════════════════════════════════════
# C. ОБЫЧНОЕ ЗДАНИЕ: КАРТИНКА СТРОЙКИ ВМЕСТО 3D-ЗАГЛУШКИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_house_construction() -> void:
	print("\n═════ C. ОБЫЧНОЕ ЗДАНИЕ ═════")
	var site = _CSite.new()
	site.faction     = Constants.FACTION_PLAYER
	site.target_id   = "barracks"
	site.target_name = "Бараки"
	site.build_size  = _UCfg.building_size("barracks")
	site.build_time  = 0.0            # проверим, что порог из конфига поднимет
	main.world_add(site)
	site.global_position = Vector3(20.0, 0.0, 20.0)
	await frames(4)

	var tex := _sprite_tex(site, "ConstructionSprite")
	var want_path: String = GameManager.construction_sprite_path(Constants.FACTION_PLAYER, "barracks")
	verdict("C1 у стройки картинка House_Construction",
		tex != null and tex.resource_path == want_path,
		"нарисовано: %s" % (tex.resource_path if tex != null else "ничего"))
	# СТАРОЙ ЗАГЛУШКИ БОЛЬШЕ НЕТ: процедурные леса строились из BoxMesh
	var boxes := 0
	for c in site.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
			boxes += 1
	verdict("C2 процедурной 3D-заглушки не осталось", boxes == 0,
		"коробчатых мешей: %d" % boxes)
	verdict("C3 нулевой build_time поднят порогом из конфига",
		is_equal_approx(site.build_time, _UCfg.CONSTRUCTION_MIN_SEC),
		"у площадки %.1f c, порог %.1f c" % [site.build_time, _UCfg.CONSTRUCTION_MIN_SEC])
	# Рамка выделения подогнана по картинке стройки, а не по коробке конфига
	var mark: MeshInstance3D = null
	for c in site.get_children():
		if c is MeshInstance3D and c.name == "SelectionMarker":
			mark = c
	verdict("C4 рамка выделения подогнана под картинку стройки",
		mark != null and mark.rotation.is_equal_approx(Vector3.ZERO)
			and mark.position.y > 0.1,
		"маркер %s" % (str(mark.position) if mark != null else "отсутствует"))
	site.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. РУИНЫ
# ═════════════════════════════════════════════════════════════════════════════
func _test_ruins() -> void:
	print("\n═════ D. РУИНЫ ═════")
	# Бараки: сносим и смотрим, что осталось
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(40.0, 0.0, 40.0)
	await frames(3)
	var at := b.global_position
	b.take_damage(b.max_health * 10.0, null)
	await frames(4)
	var ruin := _find_ruin("barracks")
	verdict("D1 на месте бараков остались руины", ruin != null)
	if ruin != null:
		var tex := _sprite_tex(ruin, "RuinSprite")
		var want: String = GameManager.ruin_sprite_path(Constants.FACTION_PLAYER, "barracks")
		verdict("D2 руины нарисованы House_Destroyed",
			tex != null and tex.resource_path == want,
			"нарисовано: %s" % (tex.resource_path if tex != null else "ничего"))
		verdict("D3 руины стоят там же, где стояло здание",
			ruin.global_position.distance_to(at) < 0.5,
			"смещение %.2f м" % ruin.global_position.distance_to(at))
		# САМОЕ ВАЖНОЕ: руина — декорация. Попади она в группы зданий, её начали
		# бы считать и проверка победы, и ИИ, и клик мышью
		verdict("D4 руины не числятся зданием",
			not ruin.is_in_group("all_buildings")
				and not ruin.is_in_group("player_buildings")
				and not (ruin is Building))
		ruin.queue_free()
	await frames(3)

	# Замок: свой набор руин
	var c := Castle.new()
	c.faction = Constants.FACTION_PLAYER
	main.world_add(c)
	c.global_position = Vector3(-40.0, 0.0, 40.0)
	await frames(3)
	c.take_damage(c.max_health * 10.0, null)
	await frames(4)
	var cruin := _find_ruin("castle")
	verdict("D5 на месте замка остались СВОИ руины", cruin != null)
	if cruin != null:
		var tex := _sprite_tex(cruin, "RuinSprite")
		var want: String = GameManager.ruin_sprite_path(Constants.FACTION_PLAYER, "castle")
		verdict("D6 руины замка нарисованы Castle_Destroyed",
			tex != null and tex.resource_path == want,
			"нарисовано: %s" % (tex.resource_path if tex != null else "ничего"))
		cruin.queue_free()
	await frames(3)
