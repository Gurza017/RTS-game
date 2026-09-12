extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: КАРТА ×3, РЕКА С БРОДОМ, ГОРА, ТАЙЛЫ (09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A РАЗМЕР — площадь поля втрое против прежней (×2.25 по осям), базы в
##     своих углах, туман и камера знают новый размер.
##   B РЕКА — по центру карты вода (непроходима), посередине брод (суша,
##     мелководье), дно просажено, берега целы; лес и руда не в русле.
##   C ПЕРЕХОД — отряд, посланный на другой берег без поиска пути, доходит:
##     берег ведёт его к броду.
##   D ГОРА — холм у замка игрока выше окрестностей; логово за ним и ниже.
##   E ТАЙЛЫ — земля, вода, гора и камни брода собраны из папки Tileset.
##
## Числа — из констант Main (правило 10), ожидание физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_map/Test.tscn

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
	print("\n═════ ИТОГ qa_map: прошло %d, провалов: %d ═════" % [_pass, _fail])
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
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	_check_size()
	_check_river()
	await _check_crossing()
	_check_hill()
	_check_plateaus()
	_check_tiles()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _check_size() -> void:
	print("\n═════ A. РАЗМЕР ═════")
	var area: float = main.MAP_HALF_X * main.MAP_HALF_Z * 4.0
	var legacy: float = 130.0 * 73.125 * 4.0
	print("  поле %.0f × %.0f м, площадь %.0f м² (прежняя %.0f)" % [
		main.MAP_HALF_X * 2.0, main.MAP_HALF_Z * 2.0, area, legacy])
	verdict("A1 площадь поля втрое против прежней (±5 %)", absf(area / legacy - 3.0) < 0.15,
		"×%.2f" % (area / legacy))
	verdict("A2 форма 16:9 сохранена", absf(main.MAP_HALF_X / main.MAP_HALF_Z - 16.0 / 9.0) < 0.01)
	var pa: Vector3 = main.PLAYER_BASE_ANCHOR
	var ea: Vector3 = main.ENEMY_BASE_ANCHOR
	verdict("A3 базы в противоположных углах", pa.x < -main.MAP_HALF_X * 0.7 and pa.z < -main.MAP_HALF_Z * 0.6
		and ea.x > main.MAP_HALF_X * 0.7 and ea.z > main.MAP_HALF_Z * 0.6,
		"игрок %s, ИИ %s" % [str(pa), str(ea)])
	var fog = GameManager.fog
	verdict("A4 маска тумана накрывает всё поле", fog != null
		and fog.cell_index(main.MAP_HALF_X - 1.0, main.MAP_HALF_Z - 1.0) >= 0
		and fog.cell_index(-main.MAP_HALF_X + 1.0, -main.MAP_HALF_Z + 1.0) >= 0)

# ═════════════════════════════════════════════════════════════════════════════
func _check_river() -> void:
	print("\n═════ B. РЕКА И БРОД ═════")
	var deep_z: float = main.FORD_Z + main.FORD_HALF + 30.0
	var rx: float = main.river_x(deep_z)
	verdict("B1 середина русла — вода", main.is_water(rx, deep_z))
	# ── СУША НАЧИНАЕТСЯ ЗА ОТКОСОМ, А НЕ В ДВУХ МЕТРАХ ОТ РУСЛА ───────────
	# Стояло RIVER_HALF_W + 2.0, то есть 11 м от оси. Со спринта 15 вода — это
	# «грунт ушёл под зеркало» (Main.SHORE_DRY), и в 11 м от оси он под ним
	# честно: откос тянется до RIVER_HALF_W + RIVER_BANK = 12.5 м. Проверка
	# утверждала прежнюю МЕРУ берега, а не его существование, — берём точку за
	# кромкой откоса, где суша обязана быть по построению
	var dry_off: float = main.RIVER_HALF_W + main.RIVER_BANK + 0.5
	verdict("B2 берега — суша", not main.is_water(rx + dry_off, deep_z)
		and not main.is_water(rx - dry_off, deep_z))
	# ── И НОГИ У НЕЁ СУХИЕ (заказ спринта 15) ─────────────────────────────
	# Жалоба со скриншотом: «юниты сидят ногами в воде у береговой линии».
	# Свойство: НИ ОДНА проходимая точка не лежит ниже зеркала воды. Меряем
	# поперёк русла с мелким шагом на нескольких широтах
	var wet_steps := 0
	var worst := 0.0
	for zi in range(6):
		var zz: float = deep_z + float(zi) * 7.0
		for xi in range(400):
			var xx: float = main.river_x(zz) - 20.0 + float(xi) * 0.1
			if main.is_water(xx, zz):
				continue
			var sink: float = main.water_surface_y(xx, zz) - main.get_terrain_height(xx, zz)
			if sink > 0.0:
				wet_steps += 1
				worst = maxf(worst, sink)
	verdict("B2б проходимой земли под водой нет", wet_steps == 0,
		"точек под зеркалом %d, глубже всего %.2f м" % [wet_steps, worst])
	verdict("B3 брод — проходимая суша посреди русла", not main.is_water(main.river_x(main.FORD_Z), main.FORD_Z)
		and not main.is_water(main.river_x(main.FORD_Z) + main.RIVER_HALF_W * 0.8, main.FORD_Z))
	var h_deep: float = main.get_terrain_height(rx, deep_z)
	var h_bank: float = main.get_terrain_height(rx + main.RIVER_HALF_W + main.RIVER_BANK + 1.0, deep_z)
	var h_ford: float = main.get_terrain_height(main.river_x(main.FORD_Z), main.FORD_Z)
	var h_fbank: float = main.get_terrain_height(main.river_x(main.FORD_Z) + main.RIVER_HALF_W + main.RIVER_BANK + 1.0, main.FORD_Z)
	verdict("B4 дно реки просажено, брод мельче русла",
		h_bank - h_deep > main.RIVER_DEPTH * 0.8 and h_fbank - h_ford > main.FORD_DEPTH * 0.5
			and h_fbank - h_ford < h_bank - h_deep,
		"глубина %.2f, брод %.2f" % [h_bank - h_deep, h_fbank - h_ford])
	# Ширина брода — заказано «широкий»: не меньше отряда в шеренге
	verdict("B5 брод широкий (≥ 30 м вдоль реки)", main.FORD_HALF * 2.0 >= 30.0,
		"%.0f м" % (main.FORD_HALF * 2.0))
	var wet := 0
	for rn in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(rn):
			continue
		var p: Vector3 = (rn as Node3D).global_position
		if main.is_water(p.x, p.z):
			wet += 1
	verdict("B6 ни дерева, ни руды в воде", wet == 0, "в воде %d" % wet)
	# Обход берега ведёт к броду: шаг в воду с северного берега уходит на +Z
	# ── НАЧИНАТЬ НАДО С СУХОГО БЕРЕГА, А ШАГАТЬ — В ВОДУ ─────────────────
	# Из воды slide_around_water уводит кратчайшим путём на сушу (своя ветка,
	# заведена против выхода из гарнизона в озеро), и вдоль берега к броду он
	# тогда не ведёт вовсе. А если шаг в воду НЕ попал, функция честно вернёт
	# его как есть. Прежняя точка (RIVER_HALF_W + 1) со спринта 15 лежит в
	# воде сама. Поэтому кромку ИЩЕМ, а не назначаем числом: сушу берём на
	# полметра снаружи от неё, шаг делаем ровно до неё
	var shore: float = dry_off
	for i in range(200):
		var dd: float = dry_off - float(i) * 0.1
		if main.is_water(rx - dd, deep_z):
			shore = dd
			break
	var from := Vector3(rx - shore - 0.5, 0.0, deep_z)
	var step := Vector3(1.0, 0.0, 0.0)
	var got: Vector3 = main.slide_around_water(from, step)
	verdict("B7 шаг в воду скользит вдоль берега к броду",
		got.length() > 0.5 and (got.z < 0.0) == (main.FORD_Z < deep_z),
		"шаг %s" % str(got))
	var land: Vector2 = main.nearest_land(rx, deep_z)
	verdict("B8 ближайшая суша из русла — поперёк, на берегу", not main.is_water(land.x, land.y)
		and absf(land.y - deep_z) < 0.01, "%s" % str(land))

# ═════════════════════════════════════════════════════════════════════════════
func _check_crossing() -> void:
	print("\n═════ C. ПЕРЕХОД ЧЕРЕЗ РЕКУ ═════")
	GameManager.world_bounds_enabled = true
	var z0: float = main.FORD_Z - main.FORD_HALF - 40.0
	var start := Vector3(main.river_x(z0) - 28.0, 0.0, z0)
	var goal := Vector3(main.river_x(z0) + 28.0, 0.0, z0)
	var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(start.x, GameManager.get_terrain_height(start.x, start.z), start.z)
	u.sync_row()
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	GameManager.add_to_squad(sid, u)
	await pframes(2)
	u.command_move(GameManager.land_target(goal), false, Vector3.ZERO, false, true)
	var crossed := false
	var in_water_frames := 0
	var waited := 0
	var best_d: float = 1e9
	var path_len: float = 0.0
	var prev: Vector3 = u.global_position
	while waited < 60 * 150:
		await get_tree().physics_frame
		waited += 1
		if not is_instance_valid(u):
			break
		var p: Vector3 = u.global_position
		path_len += Vector2(p.x - prev.x, p.z - prev.z).length()
		prev = p
		if main.is_water(p.x, p.z):
			in_water_frames += 1
		var d: float = Vector2(p.x - goal.x, p.z - goal.z).length()
		best_d = minf(best_d, d)
		if d < 3.0:
			crossed = true
			break
	print("  переход: %d физкадров, путь %.0f м, ближе всего %.1f м, кадров в воде %d" % [
		waited, path_len, best_d, in_water_frames])
	verdict("C1 боец без поиска пути доходит на другой берег (через брод)", crossed,
		"ближе всего %.1f м за %d физкадров" % [best_d, waited])
	verdict("C2 ни одного кадра в глубокой воде", in_water_frames == 0, "%d" % in_water_frames)
	if is_instance_valid(u):
		u.take_damage(1e9)
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
## ── F. ПЛАТО, СПУСКИ, НИЗИНА РЕКИ (10.09.2026) ─────────────────────────────
func _check_plateaus() -> void:
	print("\n═════ F. ПЛАТО, СПУСКИ, НИЗИНА РЕКИ ═════")
	var list: Array = main.plateau_list()
	verdict("F1 на карте не меньше трёх плато", list.size() >= 3, "плато %d" % list.size())
	var ok_top := true
	var worst_slope := 0.0
	var max_dh := 0.0
	var worst_top := INF
	for p in list:
		var cx: float = float(p[0])
		var cz: float = float(p[1])
		var rf: float = float(p[2])
		var h: float = float(p[3])
		var dir: float = float(p[4])
		var top: float = main.get_terrain_height(cx, cz)
		# Подножие — с крутой стороны (напротив спуска), сразу за откосом
		var fd: float = rf + main.PLATEAU_RAMP_STEEP + 3.0
		var foot: float = main.get_terrain_height(cx + cos(dir + PI) * fd, cz + sin(dir + PI) * fd)
		worst_top = minf(worst_top, top - foot)
		if top - foot < h * 0.75:
			ok_top = false
		# Спуск: вдоль dir от вершины до подножия шагом полметра
		var prev: float = top
		var steps: int = int((rf + main.PLATEAU_RAMP_GENTLE + 4.0) / 0.5)
		for s in range(1, steps + 1):
			var d: float = float(s) * 0.5
			var hh: float = main.get_terrain_height(cx + cos(dir) * d, cz + sin(dir) * d)
			worst_slope = maxf(worst_slope, absf(hh - prev) / 0.5)
			prev = hh
		# Ядро — та же высота
		for pt in [Vector2(cx, cz), Vector2(cx + cos(dir) * (rf + 5.0), cz + sin(dir) * (rf + 5.0)),
				Vector2(cx - rf - 2.0, cz), Vector2(cx + 3.0, cz + rf + 2.5)]:
			var dh: float = absf(GameManager.army.height_at(pt.x, pt.y, float(main.RELIEF_AMP)) \
				- main.get_terrain_height(pt.x, pt.y))
			max_dh = maxf(max_dh, dh)
	verdict("F2 вершина каждого плато выше подножия не меньше чем на 0.75 h", ok_top,
		"худшая разница %.2f м" % worst_top)
	verdict("F3 спуск плавный и проходимый: уклон вдоль спуска не круче HILL_CLIFF_SLOPE (+гармоники)",
		worst_slope <= main.HILL_CLIFF_SLOPE + 0.12, "худший уклон %.2f" % worst_slope)
	verdict("F4 ядро считает высоту плато как GDScript (обе копии формулы совпадают)",
		max_dh < 0.01, "расхождение %.4f м" % max_dh)
	var zq: float = main.FORD_Z + main.FORD_HALF + 30.0
	var rx: float = main.river_x(zq)
	var bed: float = main.get_terrain_height(rx, zq)
	var bank: float = main.get_terrain_height(rx + main.RIVER_HALF_W + main.RIVER_BANK + 1.0, zq)
	verdict("F5 русло вне брода лежит в низине: берег выше дна не меньше чем на 1 м",
		bank - bed >= 1.0, "берег %.2f, дно %.2f" % [bank, bed])
	var wy: float = main.water_surface_y(rx, zq)
	verdict("F6 зеркало воды выше дна и ниже кромки берега", wy > bed + 0.5 and wy < bank,
		"зеркало %.2f" % wy)
	var fx: float = main.river_x(main.FORD_Z)
	var fbed: float = main.get_terrain_height(fx, main.FORD_Z)
	var fwy: float = main.water_surface_y(fx, main.FORD_Z)
	verdict("F7 брод по щиколотку: вода над дном не глубже FORD_DEPTH", fwy > fbed and fwy - fbed <= main.FORD_DEPTH + 0.03,
		"%.2f м" % (fwy - fbed))
	var tc = main.get_node_or_null("TerrainColor%d" % main.COLOR_PLATEAU)
	verdict("F8 плато текстурированы травяным листом Tilemap_color (свой меш)",
		tc != null and (tc as MeshInstance3D).mesh != null)
	var n_col := 0
	for k in range(1, 6):
		if main.get_node_or_null("TerrainColor%d" % k) != null:
			n_col += 1
	verdict("F9 у травы не меньше двух оттенков поверх основного", n_col >= 2, "листов %d" % n_col)
	# Мины на плато: рудник стоит на вершине
	var on_top := 0
	var mines := 0
	for b in get_tree().get_nodes_in_group("neutral_buildings"):
		if b is Mine:
			mines += 1
			var bp: Vector3 = (b as Node3D).global_position
			if main.plateau_height(bp.x, bp.z) >= main.PLATEAU_MINE_H * 0.99:
				on_top += 1
	verdict("F10 ничейные рудники стоят на вершинах своих плато", mines > 0 and on_top == mines,
		"%d из %d" % [on_top, mines])

func _check_hill() -> void:
	print("\n═════ D. ГОРА И ЛОГОВО ═════")
	var hc: Vector2 = main.hill_center()
	var top: float = main.get_terrain_height(hc.x, hc.y)
	var castle: Vector3 = main.PLAYER_BASE_ANCHOR
	var h_castle: float = main.get_terrain_height(castle.x, castle.z)
	var far: float = main.get_terrain_height(hc.x + main.HILL_RADIUS * 2.0, hc.y)
	print("  вершина %.2f м, у замка %.2f, вдали %.2f; центр горы %s, замок %s" % [top, h_castle, far, str(hc), str(castle)])
	verdict("D1 гора возвышается над окрестностью не меньше чем на %.0f м" % (main.HILL_HEIGHT * 0.8),
		top - far >= main.HILL_HEIGHT * 0.8 and top - h_castle >= main.HILL_HEIGHT * 0.6,
		"над полем %.2f, над замком %.2f" % [top - far, top - h_castle])
	verdict("D2 гора рядом с замком игрока (ближе трети карты)",
		Vector2(hc.x - castle.x, hc.y - castle.z).length() < main.MAP_HALF_Z * 0.7,
		"%.0f м" % Vector2(hc.x - castle.x, hc.y - castle.z).length())
	var lair = GameManager.troll_lair
	if lair == null:
		verdict("D3 логово за горой", false, "логова нет")
		return
	var lp: Vector3 = (lair as Node3D).global_position
	verdict("D3 порядок по экрану: замок → гора → логово (по Z)",
		castle.z < hc.y and hc.y < lp.z, "z: %.0f → %.0f → %.0f" % [castle.z, hc.y, lp.z])
	verdict("D4 логово ниже вершины горы", lp.y < top - main.HILL_HEIGHT * 0.5,
		"логово %.2f, вершина %.2f" % [lp.y, top])

# ═════════════════════════════════════════════════════════════════════════════
func _check_tiles() -> void:
	print("\n═════ E. ТАЙЛСЕТ ═════")
	var field := main.get_node_or_null("Playfield") as MeshInstance3D
	var hill := main.get_node_or_null("Hill") as MeshInstance3D
	var river := main.world_root().get_node_or_null("River") as MeshInstance3D
	var rocks: Node = main.world_root().get_node_or_null("FordRocks")
	var foam: Node = main.world_root().get_node_or_null("RiverFoam")
	var fmat := field.material_override as StandardMaterial3D if field != null else null
	verdict("E1 земля текстурирована тайлами Tilemap_Flat", fmat != null and fmat.albedo_texture != null
		and fmat.albedo_texture.resource_path.get_file() == "Tilemap_Flat.png"
		and fmat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
		str(fmat.albedo_texture.resource_path if fmat != null and fmat.albedo_texture else "нет"))
	var hmat := hill.material_override as StandardMaterial3D if hill != null else null
	verdict("E2 гора — тайлами Tilemap_Elevation", hmat != null and hmat.albedo_texture != null
		and hmat.albedo_texture.resource_path.get_file() == "Tilemap_Elevation.png")
	var rmat := river.material_override as StandardMaterial3D if river != null else null
	verdict("E3 река — Water.png повтором", rmat != null and rmat.albedo_texture != null
		and rmat.albedo_texture.resource_path.get_file() == "Water.png")
	# ── КАМНИ И ПЕНА — ПАКЕТНО (09.09.2026) ─────────────────────────────────
	# Камни брода — MultiMesh на лист (узел на камень был вызовом отрисовки на
	# камень), пена — ОДИН меш на всё русло. Считаются экземпляры и квады, а
	# не дети узла; вызовов отрисовки у них теперь не больше числа листов + 1
	var rock_n: int = _rock_instances(rocks)
	verdict("E4 камни в воде брода стоят в полосе брода (MultiMesh, <= %d вызовов)" % 4,
		rocks != null and rock_n == main.FORD_ROCKS and _rocks_in_ford(rocks)
		and rocks.get_child_count() <= 4,
		"камней %d в %d узлах" % [rock_n, rocks.get_child_count() if rocks != null else 0])
	var foam_quads: int = 0
	var fm := foam as MeshInstance3D
	if fm != null and fm.mesh != null and fm.mesh.get_surface_count() > 0:
		foam_quads = int(fm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 6)
	verdict("E5 пена вдоль берегов вне брода — одним мешем", fm != null and foam_quads > 20,
		"лоскутов %d в одном меше" % foam_quads)
	# Земля не рисует клетки под водой (их рисует река)
	var mesh: Mesh = field.mesh if field != null else null
	verdict("E6 меш земли собран", mesh != null and mesh.get_surface_count() == 1)

func _rock_instances(root: Node) -> int:
	if root == null:
		return 0
	var n := 0
	for c in root.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			n += mmi.multimesh.instance_count
	return n

func _rocks_in_ford(root: Node) -> bool:
	for c in root.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			return false
		for j in range(mmi.multimesh.instance_count):
			var p: Vector3 = mmi.global_position + mmi.multimesh.get_instance_transform(j).origin
			if not main.in_ford(p.z) or not main.near_river(p.x, p.z, 0.0):
				return false
	return true
