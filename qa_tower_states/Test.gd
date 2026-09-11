extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tower_states — БАШНЯ: СТРОЙКА → ГОТОВОЕ ЗДАНИЕ → РУИНЫ
## ═══════════════════════════════════════════════════════════════════════════
## Заказ владельца: у башни свои спрайты этапов. Пока её строит рабочий, на
## месте стоит `Tower_Construction`; достроилась — спрайт меняется на саму
## башню; снесли — на месте остаётся `Tower_Destroyed`, а не пустая трава.
##
##   A ПУТИ      — обе картинки находятся по ID постройки и отличаются от
##                 общих «домовых»; у построек без своих картинок всё как было.
##   B СТРОЙКА   — площадка башни рисуется картинкой СТРОЙКИ БАШНИ, в полный
##                 размер (доля больше не нужна).
##   C ГОТОВО    — площадка достраивается, превращается в настоящую башню, и
##                 та рисуется своим спрайтом Tower.png.
##   D РУИНЫ     — снесённая башня оставляет пепелище СВОЕЙ картинкой, а не
##                 исчезает; руина отстраивается обратно.
##   E ЦЕПОЧКА   — все три состояния подряд на одном месте.
##
## Числа — из конфига и самих текстур (правило 10), ожидание — физкадрами
## (правило 11). Запуск: godot --headless --path . res://qa_tower_states/Test.tscn

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _GS    := preload("res://scripts/game_settings.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")
const _Tower := preload("res://scripts/Tower.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(300.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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

func _finish() -> void:
	print("\n═════ ИТОГ qa_tower_states: прошло %d, провалов: %d ═════" % [
		_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)

	await _a_paths()
	await _b_c_d_chain()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ПУТИ К КАРТИНКАМ
# ═════════════════════════════════════════════════════════════════════════════
func _a_paths() -> void:
	print("\n═════ A. СВОИ КАРТИНКИ У БАШНИ ═════")
	var f: int = Constants.FACTION_PLAYER
	var b_tower: String = GameManager.construction_sprite_path(f, "tower")
	var r_tower: String = GameManager.ruin_sprite_path(f, "tower")
	var b_house: String = GameManager.construction_sprite_path(f, "house")
	var r_house: String = GameManager.ruin_sprite_path(f, "house")
	print("  стройка башни: %s" % b_tower)
	print("  руины башни:   %s" % r_tower)
	verdict("A1 картинка СТРОЙКИ башни есть на диске",
		not b_tower.is_empty() and ResourceLoader.exists(b_tower), b_tower)
	verdict("A2 картинка РУИН башни есть на диске",
		not r_tower.is_empty() and ResourceLoader.exists(r_tower), r_tower)
	verdict("A3 это НЕ общие «домовые» картинки",
		b_tower != b_house and r_tower != r_house,
		"дом: %s / %s" % [b_house.get_file(), r_house.get_file()])
	verdict("A4 стройка и руины — разные файлы", b_tower != r_tower)
	# ── ОСТАЛЬНЫЕ ПОСТРОЙКИ НЕ ЗАДЕТЫ ──────────────────────────────────────
	# Выбор строки по ID — правка общего резолвера, и она обязана оставить
	# прежним всё, у чего своей картинки нет
	verdict("A5 у замка по-прежнему свой набор",
		GameManager.construction_sprite_path(f, "castle") != b_house
			and ResourceLoader.exists(GameManager.construction_sprite_path(f, "castle")))
	verdict("A6 у бараков и кузницы по-прежнему общий «домовой»",
		GameManager.construction_sprite_path(f, "barracks") == b_house
			and GameManager.ruin_sprite_path(f, "smithy") == r_house)
	# ── ПРОПОРЦИИ: КАРТИНКИ НАРИСОВАНЫ ПО БАШНЕ ────────────────────────────
	var tex_b := load(b_tower) as Texture2D
	var tex_r := load(r_tower) as Texture2D
	var tex_t := load(_GS.building_sprite(GameManager.race_of(f),
		GameManager.color_of(f), "tower")) as Texture2D
	if tex_b != null and tex_r != null and tex_t != null:
		print("  листы: стройка %s, руины %s, сама башня %s" % [
			str(tex_b.get_size()), str(tex_r.get_size()), str(tex_t.get_size())])
		verdict("A7 картинки этапов нарисованы в пропорции самой башни",
			absf(tex_b.get_size().aspect() - tex_t.get_size().aspect()) < 0.01
				and absf(tex_r.get_size().aspect() - tex_t.get_size().aspect()) < 0.01,
			"пропорции %.2f / %.2f при башне %.2f" % [
				tex_b.get_size().aspect(), tex_r.get_size().aspect(),
				tex_t.get_size().aspect()])
	# ── ДОЛЯ БОЛЬШЕ НЕ НУЖНА ───────────────────────────────────────────────
	# Прежние 0.6 ужимали ЧУЖУЮ картинку; своя нарисована по башне
	print("  доли: стройка %.2f, руины %.2f" % [
		_UCfg.building_stat("tower", "construction_scale", 1.0),
		_UCfg.building_stat("tower", "ruin_scale", 1.0)])
	verdict("A8 своя картинка рисуется в полный размер, без ужимания",
		absf(_UCfg.building_stat("tower", "construction_scale", 1.0) - 1.0) < 0.001
			and absf(_UCfg.building_stat("tower", "ruin_scale", 1.0) - 1.0) < 0.001,
		"стройка %.2f, руины %.2f" % [
			_UCfg.building_stat("tower", "construction_scale", 1.0),
			_UCfg.building_stat("tower", "ruin_scale", 1.0)])

# ═════════════════════════════════════════════════════════════════════════════
# B, C, D. ЦЕПОЧКА СОСТОЯНИЙ НА ОДНОМ МЕСТЕ
# ═════════════════════════════════════════════════════════════════════════════
func _b_c_d_chain() -> void:
	print("\n═════ B. СТРОЙКА ═════")
	var f: int = Constants.FACTION_PLAYER
	var at: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(28.0, 0.0, 28.0)
	at.y = GameManager.get_terrain_height(at.x, at.z)
	var size: Vector3 = _UCfg.building_size("tower")

	var site = _CSite.new()
	site.faction     = f
	site.target_id   = "tower"
	site.target_name = String(_UCfg.building_cfg("tower").get("name", "Башня"))
	site.build_time  = float(_UCfg.building_cfg("tower").get("build_time", 30.0))
	site.build_size  = size
	main.world_add(site)
	site.global_position = at
	await pframes(6)

	var spr := site.get_node_or_null("ConstructionSprite") as MeshInstance3D
	verdict("B1 у площадки башни есть спрайт стройки", spr != null)
	var b_path: String = GameManager.construction_sprite_path(f, "tower")
	var tex_b := load(b_path) as Texture2D
	if spr != null and tex_b != null:
		var q: QuadMesh = spr.mesh as QuadMesh
		var mat := q.material as ShaderMaterial
		var shown: Variant = mat.get_shader_parameter("albedo_tex") if mat != null else null
		verdict("B2 и это ИМЕННО картинка стройки БАШНИ",
			shown != null and (shown as Texture2D).get_size() == tex_b.get_size()
				and absf((shown as Texture2D).get_size().aspect()
					- tex_b.get_size().aspect()) < 0.001,
			"лист %s" % (str((shown as Texture2D).get_size()) if shown != null else "нет"))
		var full: Vector2 = Building.sprite_quad_size(tex_b, size)
		print("  квад стройки %.2f × %.2f м при полном %.2f × %.2f" % [
			q.size.x, q.size.y, full.x, full.y])
		verdict("B3 рисуется в полный размер, без ужимания долей",
			absf(q.size.x - full.x) < 0.01 and absf(q.size.y - full.y) < 0.01,
			"%.2f×%.2f против %.2f×%.2f" % [q.size.x, q.size.y, full.x, full.y])
		verdict("B4 низ картинки стоит на грунте, а не в воздухе",
			absf(spr.position.y - q.size.y * 0.5) < 0.01,
			"подъём %.2f при полувысоте %.2f" % [spr.position.y, q.size.y * 0.5])
	# ── ГОТОВОЙ БАШНИ НА МЕСТЕ ЕЩЁ НЕТ ─────────────────────────────────────
	verdict("B5 пока идёт стройка, готовой башни на месте нет",
		_tower_at(at) == null)

	print("\n═════ C. ГОТОВОЕ ЗДАНИЕ ═════")
	# ── ДОСТРАИВАЕМ ШТАТНЫМ ПУТЁМ, ТОЛЬКО БЫСТРО ───────────────────────────
	# `self_building` — это «стройка идёт сама, без артели» (им пользуется ИИ);
	# прогресс доводим до порога и отдаём кадр, чтобы _complete отработал своим
	# кодом, а не подменой узла руками
	site.self_building = true
	site.progress = site.build_time
	await frames(4)
	await pframes(6)
	var tower = _tower_at(at)
	verdict("C1 площадка превратилась в НАСТОЯЩУЮ башню", tower != null,
		"на месте %s" % ("башня" if tower != null else "ничего"))
	verdict("C2 площадки на месте больше нет", _site_at(at) == null)
	if tower == null:
		return
	var tspr := (tower as Node).get_node_or_null("BuildingSprite") as MeshInstance3D
	var tex_t := load(_GS.building_sprite(GameManager.race_of(f),
		GameManager.color_of(f), "tower")) as Texture2D
	verdict("C3 башня рисуется СВОИМ спрайтом, а не картинкой стройки",
		tspr != null and tex_t != null
			and _tex_of(tspr) != null
			and (_tex_of(tspr) as Texture2D).resource_path == tex_t.resource_path,
		"спрайт %s" % (String((_tex_of(tspr) as Texture2D).resource_path).get_file()
			if tspr != null and _tex_of(tspr) != null else "нет"))
	verdict("C4 и это башня со своим запасом жизни из конфига",
		absf(float(tower.max_health) - _UCfg.building_stat("tower", "max_hp", 0.0)) < 1.0,
		"запас %.0f" % float(tower.max_health))

	print("\n═════ D. РУИНЫ ═════")
	var parent: Node = (tower as Node).get_parent()
	(tower as Object).call("take_damage", float(tower.max_health) * 10.0)
	await frames(3)
	await pframes(3)
	var ruin: Node3D = null
	for c in parent.get_children():
		if is_instance_valid(c) and String((c as Node).name).begins_with("Ruin_tower"):
			ruin = c as Node3D
	verdict("D1 на месте снесённой башни осталось ПЕПЕЛИЩЕ, а не пустая трава",
		ruin != null)
	verdict("D2 самой башни на месте больше нет", _tower_at(at) == null)
	if ruin == null:
		return
	var rs := ruin.get_node_or_null("RuinSprite") as MeshInstance3D
	var tex_r := load(GameManager.ruin_sprite_path(f, "tower")) as Texture2D
	verdict("D3 пепелище нарисовано СВОЕЙ картинкой руин башни",
		rs != null and tex_r != null and _tex_of(rs) != null
			and (_tex_of(rs) as Texture2D).resource_path == tex_r.resource_path,
		"спрайт %s" % (String((_tex_of(rs) as Texture2D).resource_path).get_file()
			if rs != null and _tex_of(rs) != null else "нет"))
	if rs != null and tex_r != null:
		var q2: QuadMesh = rs.mesh as QuadMesh
		var full2: Vector2 = Building.sprite_quad_size(tex_r,
			_UCfg.building_size("tower"))
		print("  квад руин %.2f × %.2f м при полном %.2f × %.2f" % [
			q2.size.x, q2.size.y, full2.x, full2.y])
		verdict("D4 пепелище в полный размер своей картинки",
			absf(q2.size.x - full2.x) < 0.01 and absf(q2.size.y - full2.y) < 0.01,
			"%.2f×%.2f против %.2f×%.2f" % [q2.size.x, q2.size.y, full2.x, full2.y])
	verdict("D5 руина помнит, что тут стояла именно БАШНЯ и чья",
		String(ruin.get_meta("ruin_building_id", "")) == "tower"
			and int(ruin.get_meta("ruin_faction", -1)) == f,
		"%s / сторона %d" % [str(ruin.get_meta("ruin_building_id", "")),
			int(ruin.get_meta("ruin_faction", -1))])

	print("\n═════ E. ЦЕПОЧКА ЗАМКНУЛАСЬ ═════")
	# Отстройка руины: на её месте снова встаёт ПЛОЩАДКА, то есть цикл
	# «стройка → здание → руины» замыкается, а не упирается в пепелище
	GameManager.rebuild_ruin(ruin, f)
	await pframes(8)
	verdict("E1 пепелище можно отстроить — на его месте снова стройка",
		_site_at(at) != null,
		"на месте %s" % ("площадка" if _site_at(at) != null else "ничего"))

# ═════════════════════════════════════════════════════════════════════════════
# СЛУЖЕБНОЕ
# ═════════════════════════════════════════════════════════════════════════════
## Текстура, которую держит материал квада (шейдерный параметр, а не поле)
func _tex_of(mi: MeshInstance3D) -> Variant:
	if mi == null or not is_instance_valid(mi):
		return null
	var q := mi.mesh as QuadMesh
	if q == null:
		return null
	var sm := q.material as ShaderMaterial
	if sm != null:
		return sm.get_shader_parameter("albedo_tex")
	var std := q.material as StandardMaterial3D
	return std.albedo_texture if std != null else null

## Готовая башня рядом с точкой (площадки не считаются)
func _tower_at(at: Vector3) -> Node3D:
	for b in get_tree().get_nodes_in_group(
			Constants.building_group(Constants.FACTION_PLAYER)):
		if b == null or not is_instance_valid(b):
			continue
		if b is _CSite:
			continue
		if b is _Tower and (b as Node3D).global_position.distance_to(at) < 4.0:
			return b
	return null

## Стройплощадка рядом с точкой
func _site_at(at: Vector3) -> Node3D:
	for b in get_tree().get_nodes_in_group(
			Constants.building_group(Constants.FACTION_PLAYER)):
		if b == null or not is_instance_valid(b):
			continue
		if b is _CSite and (b as Node3D).global_position.distance_to(at) < 4.0:
			return b
	return null
