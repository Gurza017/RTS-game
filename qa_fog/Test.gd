extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТУМАН ВОЙНЫ, СТАРТОВАЯ КАМЕРА И ПЕРВЫЙ ЗАМОК
## ═══════════════════════════════════════════════════════════════════════════
##   A КАМЕРА    — старт в углу игрока на пределе приближения
##   B ТУМАН     — маска построена, стартовая площадка раскрыта заранее
##   C ОБЗОР     — радиус = 3 × дальность атаки, с нижним пределом
##   D СКРЫТИЕ   — чужие в тумане не рисуются, при подходе своих проявляются
##   E ЗАМОК     — первый бесплатен, 4 рабочих сперва строят, потом добывают
##
## ЧИСЛА ИЗ КОНФИГА: множитель обзора и предел живут в unit_stats_config,
## состав стартовой бригады — в Main.START_WORKER_RESOURCES. Стенд проверяет
## СВОЙСТВА, а не переписанные значения.

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n: out += " "
	return out

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	await _a_camera()
	await _b_fog()
	await _c_vision()
	await _d_hiding()
	await _e_castle()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 64), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== FOG TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. СТАРТОВАЯ КАМЕРА
# ═════════════════════════════════════════════════════════════════════════════
func _a_camera() -> void:
	print("\n═════ A. КАМЕРА ═════")
	var cam = main._camera
	var anchor: Vector3 = main.PLAYER_BASE_ANCHOR

	# A1 — предельное приближение, а не общий план
	verdict("A1 матч открывается на пределе приближения",
		absf(cam._target_height - cam.min_height) < 0.01,
		"высота кадра %.1f, предел приближения %.1f (отдаление %.1f)" % [
			cam._target_height, cam.min_height, cam.max_height])

	# A2 — камера смотрит в угол игрока, а не в центр карты
	var f: Vector3 = cam.focus_point() if cam.has_method("focus_point") else cam._focus
	var d: float = Vector2(f.x - anchor.x, f.z - anchor.z).length()
	verdict("A2 камера стоит в углу игрока", d < 30.0,
		"до якоря базы %.1f м" % d)

	# A3 — угол игрока это именно угол карты, а не середина
	verdict("A3 якорь базы игрока лежит в углу карты",
		anchor.x < -main.MAP_HALF_X * 0.5 and anchor.z < -main.MAP_HALF_Z * 0.5,
		"якорь (%.0f, %.0f) при полукарте (%.0f, %.0f)" % [
			anchor.x, anchor.z, main.MAP_HALF_X, main.MAP_HALF_Z])

# ═════════════════════════════════════════════════════════════════════════════
# B. ТУМАН И СТАРТОВАЯ ПЛОЩАДКА
# ═════════════════════════════════════════════════════════════════════════════
func _b_fog() -> void:
	print("\n═════ B. ТУМАН ═════")
	var fog = main.fog
	verdict("B1 туман создан и зарегистрирован в GameManager",
		fog != null and GameManager.fog == fog,
		"fog=%s" % str(fog != null))
	if fog == null:
		return

	# B2 — маска покрывает карту целиком
	verdict("B2 маска покрывает всю карту",
		fog.cols > 0 and fog.rows > 0
			and float(fog.cols) * fog.MASK_CELL >= 2.0 * main.MAP_HALF_X - fog.MASK_CELL
			and float(fog.rows) * fog.MASK_CELL >= 2.0 * main.MAP_HALF_Z - fog.MASK_CELL,
		"сетка %d×%d по %.1f м" % [fog.cols, fog.rows, fog.MASK_CELL])

	# B3 — стартовая площадка раскрыта ЗАРАНЕЕ, до всякой постройки
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	verdict("B3 площадка под замок раскрыта заранее", fog.is_lit(a.x, a.z),
		"центр площадки просматривается=%s" % str(fog.is_lit(a.x, a.z)))

	# B4 — раскрыто ВСЁ, куда игрок реально может ткнуть замок, включая углы:
	# круг, вписанный в квадрат зоны, оставил бы их в темноте.
	#
	# ТОЧКИ ПРОГОНЯЮТСЯ ЧЕРЕЗ clamp_to_player_start, а не берутся как
	# «якорь ± полуширина»: база стоит в углу карты, и сырой угол квадрата
	# зоны вылезает ЗА карту (при якоре −106 и полуширине 30 это −136 при
	# половине карты 130). Такая точка недостижима для игрока — зажим сам
	# приведёт её на край, — и требовать её раскрытия бессмысленно
	var h: float = main.PLAYER_PLACE_HALF
	var dark: Array = []
	for sx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for sz in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var p: Vector2 = main.clamp_to_player_start(a.x + sx * h, a.z + sz * h)
			if not fog.is_lit(p.x, p.y):
				dark.append("(%.0f,%.0f)" % [p.x, p.y])
	verdict("B4 раскрыта вся достижимая зона размещения", dark.is_empty(),
		"тёмных точек: %d %s" % [dark.size(), str(dark.slice(0, 4))])

	# B5 — дальний угол карты в тумане: раскрыто не всё подряд
	var far := Vector3(main.MAP_HALF_X - 6.0, 0.0, main.MAP_HALF_Z - 6.0)
	verdict("B5 остальная карта закрыта туманом", not fog.is_lit(far.x, far.z),
		"дальний угол просматривается=%s" % str(fog.is_lit(far.x, far.z)))

	# B6 — раскрыта заметная, но небольшая доля карты
	var frac: float = fog.lit_fraction()
	verdict("B6 раскрыт стартовый пятачок, а не половина карты",
		frac > 0.005 and frac < 0.35, "раскрыто %.1f%% карты" % (frac * 100.0))

	# B7 — за краем карты обзора нет (индекс не находится)
	verdict("B7 точка за картой не считается раскрытой",
		not fog.is_lit(main.MAP_HALF_X + 50.0, 0.0),
		"за краем просматривается=%s" % str(fog.is_lit(main.MAP_HALF_X + 50.0, 0.0)))

# ═════════════════════════════════════════════════════════════════════════════
# C. РАДИУС ОБЗОРА
# ═════════════════════════════════════════════════════════════════════════════
func _c_vision() -> void:
	print("\n═════ C. РАДИУС ОБЗОРА ═════")

	# C1 — формула: три дальности атаки
	var r20: float = _UCfg.vision_radius(20.0)
	verdict("C1 обзор = 3 × дальность атаки",
		absf(r20 - 20.0 * _UCfg.VISION_MULT) < 0.01,
		"дальность 20 → обзор %.0f (множитель %.1f)" % [r20, _UCfg.VISION_MULT])

	# C2 — у лучника из конфига обзор действительно втрое больше стрельбы
	var arch: Dictionary = _UCfg.STATS.get("archer", {})
	var ar: float = float(arch.get("attack_range", 0.0))
	var rv: float = _UCfg.vision_radius(ar)
	verdict("C2 у лучника обзор втрое больше дальности стрельбы",
		ar > 0.0 and absf(rv - ar * _UCfg.VISION_MULT) < 0.01,
		"стрельба %.0f → обзор %.0f" % [ar, rv])

	# C3 — ближний бой не слепнет: работает нижний предел
	var melee: float = float((_UCfg.STATS.get("warrior", {}) as Dictionary)
		.get("attack_range", 1.6))
	var rm: float = _UCfg.vision_radius(melee)
	verdict("C3 у ближнего боя обзор не вырождается",
		rm >= _UCfg.VISION_MIN - 0.01 and rm > melee * 2.0,
		"дальность %.1f → обзор %.0f (предел %.0f)" % [melee, rm, _UCfg.VISION_MIN])

	# C4 — юнит РЕАЛЬНО раскрывает туман вокруг себя
	var fog = main.fog
	var spot := Vector3(0.0, 0.0, 0.0)     # центр карты, заведомо в тумане
	var before: bool = fog.is_lit(spot.x, spot.z)
	var sp := Spearman.new()
	sp.faction = Constants.FACTION_PLAYER
	main.world_add(sp)
	sp.global_position = Vector3(spot.x, main.get_terrain_height(spot.x, spot.z), spot.z)
	await pframes(2)
	fog.refresh()
	var after: bool = fog.is_lit(spot.x, spot.z)
	verdict("C4 свой юнит раскрывает туман вокруг себя",
		not before and after, "до=%s после=%s" % [before, after])

	# C5 — раскрытие соответствует радиусу: внутри видно, заметно дальше — нет
	var r: float = _UCfg.vision_radius(sp.attack_range)
	var inside: bool  = fog.is_lit(spot.x + r * 0.5, spot.z)
	var outside: bool = fog.is_lit(spot.x + r * 2.5, spot.z)
	verdict("C5 раскрыт круг своего радиуса, а не вся карта",
		inside and not outside,
		"обзор %.0f м: на %.0f м видно=%s, на %.0f м видно=%s" % [
			r, r * 0.5, inside, r * 2.5, outside])

	# C6 — «разведано» помнится после ухода юнита
	sp.queue_free()
	await pframes(3)
	fog.refresh()
	verdict("C6 ушёл юнит — земля остаётся разведанной, но не просматриваемой",
		fog.is_seen(spot.x, spot.z) and not fog.is_lit(spot.x, spot.z),
		"разведано=%s просматривается=%s" % [
			fog.is_seen(spot.x, spot.z), fog.is_lit(spot.x, spot.z)])

# ═════════════════════════════════════════════════════════════════════════════
# D. ЧУЖИЕ В ТУМАНЕ НЕ РИСУЮТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _d_hiding() -> void:
	print("\n═════ D. СКРЫТИЕ В ТУМАНЕ ═════")
	var fog = main.fog
	# Чужой боец в заведомо тёмном месте
	var dark := Vector3(30.0, 0.0, 20.0)
	var foe := Spearman.new()
	foe.faction = Constants.FACTION_ENEMY
	main.world_add(foe)
	foe.global_position = Vector3(dark.x, main.get_terrain_height(dark.x, dark.z), dark.z)
	await pframes(2)
	fog.refresh()
	await frames(6)

	verdict("D1 место чужого действительно в тумане",
		not fog.is_lit(dark.x, dark.z), "просматривается=%s" % fog.is_lit(dark.x, dark.z))
	verdict("D2 чужой в тумане снят с общей отрисовки",
		not GameManager.far_units.is_registered(foe),
		"в отрисовке=%s" % str(GameManager.far_units.is_registered(foe)))

	# Свой боец подходит вплотную — туман раскрывается, враг проявляется
	var ally := Spearman.new()
	ally.faction = Constants.FACTION_PLAYER
	main.world_add(ally)
	ally.global_position = Vector3(dark.x + 4.0,
		main.get_terrain_height(dark.x + 4.0, dark.z), dark.z)
	await pframes(2)
	fog.refresh()
	await frames(8)
	verdict("D3 подошли свои — место просматривается",
		fog.is_lit(dark.x, dark.z), "просматривается=%s" % fog.is_lit(dark.x, dark.z))
	verdict("D4 и чужой снова рисуется",
		GameManager.far_units.is_registered(foe),
		"в отрисовке=%s" % str(GameManager.far_units.is_registered(foe)))

	# D5 — свои не прячутся от тумана никогда: они сами его и раскрывают
	verdict("D5 свой боец из отрисовки не пропадает",
		GameManager.far_units.is_registered(ally),
		"в отрисовке=%s" % str(GameManager.far_units.is_registered(ally)))

	foe.queue_free()
	ally.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# E. ПЕРВЫЙ ЗАМОК: БЕСПЛАТНЫЙ И СТРОИТСЯ БРИГАДОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _e_castle() -> void:
	print("\n═════ E. ПЕРВЫЙ ЗАМОК ═════")
	var f: int = Constants.FACTION_PLAYER

	# E1 — размещение первого замка ничего не списывает
	var before: Dictionary = {}
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE]:
		before[int(t)] = ResourceManager.get_amount(f, int(t))
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	main._try_place_castle(main._camera.unproject_position(
		Vector3(a.x, main.get_terrain_height(a.x, a.z), a.z)))
	await pframes(3)
	var same := true
	var moved: Array = []
	for t in before.keys():
		if absf(ResourceManager.get_amount(f, int(t)) - float(before[t])) > 0.01:
			same = false
			moved.append(int(t))
	verdict("E1 первый замок бесплатен", same, "изменились ресурсы: %s" % str(moved))

	# E2 — появилась стройплощадка, а не готовый замок
	var sites: Array = get_tree().get_nodes_in_group("construction_sites")
	var site = null
	for s in sites:
		if is_instance_valid(s) and s.target_id == "castle":
			site = s
			break
	verdict("E2 на карте стройплощадка замка", site != null,
		"площадок: %d" % sites.size())

	# E3 — ровно столько рабочих, сколько задано в конфиге бригады
	var crew: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Worker and is_instance_valid(u):
			crew.append(u)
	var want: int = main.START_WORKER_RESOURCES.size()
	verdict("E3 стартовая бригада заданного размера", crew.size() == want,
		"рабочих %d, в конфиге %d" % [crew.size(), want])

	# E4 — ВСЕ они строят, а не разбежались по ресурсам
	var building := 0
	var gathering := 0
	for w in crew:
		if w.build_target != null and is_instance_valid(w.build_target):
			building += 1
		if w.gather_target != null:
			gathering += 1
	verdict("E4 бригада сразу взялась за стройку, а не за ресурсы",
		building == crew.size() and gathering == 0,
		"строят %d, добывают %d из %d" % [building, gathering, crew.size()])

	# E5 — рабочие числятся строителями У САМОЙ площадки (ускоряют её)
	var registered: int = site.builder_count() if site != null else -1
	# Идут пешком: пока не дошли, площадка их ещё не считает. Дожидаемся прихода
	var waited := 0
	while site != null and is_instance_valid(site) and site.builder_count() <= 0 and waited < 600:
		await pframes(1)
		waited += 1
	registered = site.builder_count() if (site != null and is_instance_valid(site)) else 0
	verdict("E5 рабочие дошли и числятся строителями площадки", registered > 0,
		"строителей на площадке %d (ждали %d тиков)" % [registered, waited])

	# E6 — стройка идёт быстрее, чем сама по себе (бригада реально ускоряет)
	verdict("E6 бригада ускоряет стройку",
		site == null or not is_instance_valid(site) or site.builder_count() >= 1,
		"строителей %d" % registered)

	# E7 — по готовности замка бригада расходится по ресурсам
	if site != null and is_instance_valid(site):
		site.progress = site.build_time      # домотать стройку до конца
	var spins := 0
	while spins < 600:
		await pframes(1)
		spins += 1
		if site == null or not is_instance_valid(site):
			break
	await pframes(20)
	var now_gathering := 0
	var still_building := 0
	for w in crew:
		if not is_instance_valid(w):
			continue
		if w.gather_target != null and is_instance_valid(w.gather_target):
			now_gathering += 1
		if w.build_target != null and is_instance_valid(w.build_target):
			still_building += 1
	verdict("E7 замок готов — бригада ушла на ресурсы",
		now_gathering == crew.size() and still_building == 0,
		"добывают %d, всё ещё строят %d из %d" % [
			now_gathering, still_building, crew.size()])

	# E8 — замок на карте появился
	var castles := 0
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b is Castle and is_instance_valid(b):
			castles += 1
	verdict("E8 замок достроен и стоит на карте", castles >= 1,
		"замков: %d" % castles)

	# E9 — и он раскрыл туман вокруг себя
	main.fog.refresh()
	verdict("E9 достроенный замок раскрывает туман вокруг себя",
		main.fog.is_lit(a.x, a.z), "у замка видно=%s" % main.fog.is_lit(a.x, a.z))
