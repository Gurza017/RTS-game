extends Node

## СТЕНД: КОЛЫХАНИЕ РАСТИТЕЛЬНОСТИ НА ВЕТРУ
##
## Разделы:
##   A — аудит ассетов: у каких растений есть свои кадры качания
##   B — деревья: анимация включена, фаза и темп у каждого свои
##   C — кусты: то же самое
##   D — запасной путь: программный изгиб там, где кадров нет
##   E — что качаться НЕ должно (здания, пни)

const _BB := preload("res://scripts/BillboardUtil.gd")

var main: Node = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

## Значение uniform-а с запасом на ПУСТО. get_shader_parameter отдаёт null,
## если параметр никогда не выставляли из кода: шейдер в этом случае берёт своё
## значение по умолчанию, а float(null) — ошибка времени выполнения
func _param(sm: ShaderMaterial, name: String) -> float:
	var v = sm.get_shader_parameter(name)
	return 0.0 if v == null else float(v)

## Собрать материалы всех квадов под узлом
func _mats(n: Node, out: Array) -> Array:
	for c in n.get_children():
		if c is MeshInstance3D:
			var q := (c as MeshInstance3D).mesh as QuadMesh
			if q != null and q.material is ShaderMaterial:
				out.append(q.material)
		_mats(c, out)
	return out

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	_test_assets()
	await _test_trees()
	await _test_bushes()
	_test_fallback_sway()
	await _test_static()

	print("\n=== ИТОГ qa_wind: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. АУДИТ АССЕТОВ
# ═════════════════════════════════════════════════════════════════════════════
func _test_assets() -> void:
	print("\n═════ A. КАДРЫ КОЛЫХАНИЯ В АССЕТАХ ═════")
	var paths := [
		"res://assets/environment/resources/Tree1.png",
		"res://assets/environment/resources/Tree2.png",
		"res://assets/environment/resources/Tree3.png",
		"res://assets/environment/resources/Tree4.png",
	]
	# Кусты лежат отдельным паком — путь берём тем же перебором, что и Main
	var bush_dir := "res://assets/environment/terrain"
	var d := DirAccess.open(bush_dir)
	if d != null:
		for f in d.get_files():
			if String(f).begins_with("Bushe"):
				paths.append(bush_dir + "/" + String(f))
	var animated := 0
	for p in paths:
		var path: String = String(p)
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var fc: int = _BB.frame_count(tex)
		print("  %-52s кадров=%d" % [path.get_file(), fc])
		if fc > 1:
			animated += 1
	verdict("A1 у растительности нашлись кадры колыхания", animated >= 4,
		"лент с кадрами: %d" % animated)

# ═════════════════════════════════════════════════════════════════════════════
# B. ДЕРЕВЬЯ
# ═════════════════════════════════════════════════════════════════════════════
func _test_trees() -> void:
	print("\n═════ B. ДЕРЕВЬЯ ═════")
	var nodes: Array = []
	for i in range(24):
		var t := ResourceNode.new()
		t.resource_type = Constants.RESOURCE_WOOD
		t.tree_variant  = (i % 4) + 1
		main.world_add(t)
		t.global_position = Vector3(-300 + float(i) * 3.0, 0, -300)
		nodes.append(t)
	await frames(4)

	var fps_vals: Array = []
	var phases: Array = []
	for t in nodes:
		var ms: Array = _mats(t, [])
		for m in ms:
			var sm: ShaderMaterial = m
			if _param(sm, "frame_count") <= 1.0:
				continue
			fps_vals.append(_param(sm, "frame_fps"))
			phases.append(_param(sm, "frame_phase"))
	print("  деревьев с анимацией: %d из %d" % [fps_vals.size(), nodes.size()])
	verdict("B1 у деревьев анимация колыхания ВКЛЮЧЕНА",
		fps_vals.size() == nodes.size(), "анимировано %d из %d"
			% [fps_vals.size(), nodes.size()])
	var all_moving := true
	for f in fps_vals:
		if float(f) <= 0.0:
			all_moving = false
	verdict("B2 скорость положительная у всех", all_moving)

	# АСИНХРОННОСТЬ: и фазы, и темпы обязаны различаться
	var uniq_ph := {}
	for p in phases:
		uniq_ph[snappedf(float(p), 0.001)] = true
	var uniq_fps := {}
	for f in fps_vals:
		uniq_fps[snappedf(float(f), 0.001)] = true
	print("  различных фаз: %d, различных темпов: %d" % [
		uniq_ph.size(), uniq_fps.size()])
	verdict("B3 фаза у каждого дерева своя (не машут в такт)",
		uniq_ph.size() >= nodes.size() - 1,
		"различных фаз %d из %d" % [uniq_ph.size(), nodes.size()])
	verdict("B4 и темп тоже свой — со временем расходятся окончательно",
		uniq_fps.size() >= nodes.size() - 2,
		"различных темпов %d из %d" % [uniq_fps.size(), nodes.size()])

	# Темп «спокойный»: полный цикл в заданных пределах, без трепета
	var worst_cycle := 0.0
	var best_cycle := 1e9
	for i in range(fps_vals.size()):
		var ms2: Array = _mats(nodes[i], [])
		for m in ms2:
			var sm2: ShaderMaterial = m
			var fc: float = _param(sm2, "frame_count")
			var fp: float = _param(sm2, "frame_fps")
			if fc > 1.0 and fp > 0.0:
				var cyc: float = fc / fp
				worst_cycle = maxf(worst_cycle, cyc)
				best_cycle  = minf(best_cycle, cyc)
	print("  длительность цикла: от %.2f до %.2f с" % [best_cycle, worst_cycle])
	verdict("B5 качание спокойное, а не трепет",
		best_cycle >= _BB.WIND_CYCLE_MIN - 0.01 \
			and worst_cycle <= _BB.WIND_CYCLE_MAX + 0.01,
		"цикл %.2f…%.2f с при пределах %.1f…%.1f"
			% [best_cycle, worst_cycle, _BB.WIND_CYCLE_MIN, _BB.WIND_CYCLE_MAX])

	for t in nodes:
		(t as Node).queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. КУСТЫ
# ═════════════════════════════════════════════════════════════════════════════
func _test_bushes() -> void:
	print("\n═════ C. КУСТЫ ═════")
	# Кусты расставляет сам Main при старте — ищем их среди узлов мира
	var mats: Array = []
	var world: Node = main.get_node_or_null("World")
	if world != null:
		_mats(world, mats)
	var bush_like: Array = []
	for m in mats:
		var sm: ShaderMaterial = m
		var tex := sm.get_shader_parameter("albedo_tex") as Texture2D
		if tex == null:
			continue
		if String(tex.resource_path).get_file().begins_with("Bushe"):
			bush_like.append(sm)
	print("  кустов на карте: %d" % bush_like.size())
	if bush_like.is_empty():
		verdict("C1 кусты найдены", false, "ни одного куста на карте")
		return
	verdict("C1 кусты найдены", true, "%d штук" % bush_like.size())
	var moving := 0
	var ph := {}
	for sm in bush_like:
		var m2: ShaderMaterial = sm
		if _param(m2, "frame_fps") > 0.0:
			moving += 1
		ph[snappedf(_param(m2, "frame_phase"), 0.001)] = true
	verdict("C2 у кустов анимация включена", moving == bush_like.size(),
		"качается %d из %d" % [moving, bush_like.size()])
	verdict("C3 кусты не в такт друг другу",
		ph.size() >= mini(bush_like.size(), 8),
		"различных фаз %d из %d" % [ph.size(), bush_like.size()])

# ═════════════════════════════════════════════════════════════════════════════
# D. ЗАПАСНОЙ ПУТЬ ДЛЯ РАСТЕНИЙ БЕЗ КАДРОВ
# ═════════════════════════════════════════════════════════════════════════════
func _test_fallback_sway() -> void:
	print("\n═════ D. ПРОГРАММНЫЙ ИЗГИБ (нет своих кадров) ═════")
	# Берём заведомо ОДНОКАДРОВУЮ картинку
	var path := "res://assets/environment/resources/Rock1.png"
	if not ResourceLoader.exists(path):
		verdict("D1 одиночная картинка для проверки найдена", false, path)
		return
	var tex := load(path) as Texture2D
	verdict("D1 картинка действительно однокадровая",
		_BB.frame_count(tex) == 1, "кадров %d" % _BB.frame_count(tex))
	var a: ShaderMaterial = _BB.make_wind_material(tex)
	var b: ShaderMaterial = _BB.make_wind_material(tex)
	var amt: float = _param(a, "sway_amount")
	var spd: float = _param(a, "sway_speed")
	print("  изгиб=%.4f, скорость=%.3f рад/с" % [amt, spd])
	verdict("D2 включён программный изгиб вместо листания кадров",
		amt > 0.0 and _param(a, "frame_fps") == 0.0,
		"изгиб %.4f, fps %.1f" % [amt, _param(a, "frame_fps")])
	verdict("D3 изгиб лёгкий, а не размашистый",
		amt <= _BB.WIND_SWAY_MAX + 0.001, "амплитуда %.4f" % amt)
	verdict("D4 у двух экземпляров фазы разные",
		absf(_param(a, "sway_phase")
			- _param(b, "sway_phase")) > 0.0001)

# ═════════════════════════════════════════════════════════════════════════════
# E. ЧТО КАЧАТЬСЯ НЕ ДОЛЖНО
# ═════════════════════════════════════════════════════════════════════════════
func _test_static() -> void:
	print("\n═════ E. НЕПОДВИЖНОЕ ═════")
	var b := Barracks.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3(-350, 0, -350)
	await frames(3)
	var ms: Array = _mats(b, [])
	var ok := true
	for m in ms:
		var sm: ShaderMaterial = m
		if _param(sm, "frame_fps") > 0.0:
			ok = false
		if _param(sm, "sway_amount") > 0.0:
			ok = false
	verdict("E1 постройки не качаются", ok and not ms.is_empty(),
		"материалов %d" % ms.size())
	b.queue_free()
	await frames(1)

	# Пень: дерева больше нет, качаться нечему
	var t := ResourceNode.new()
	t.resource_type = Constants.RESOURCE_WOOD
	t.remaining = 3.0
	main.world_add(t)
	t.global_position = Vector3(-360, 0, -360)
	await frames(3)
	t.extract(999.0)
	await frames(3)
	var st: Node3D = t.get("_stump_node")
	var stump_ok := true
	if st != null:
		var q := (st as MeshInstance3D).mesh as QuadMesh
		if q != null and q.material is ShaderMaterial:
			var sm3: ShaderMaterial = q.material
			stump_ok = _param(sm3, "frame_fps") == 0.0 \
				and _param(sm3, "sway_amount") == 0.0
	verdict("E2 пень стоит неподвижно", stump_ok)
	t.queue_free()
	await frames(1)
