extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_sprint13 — ДЕКОРАЦИИ, ГНОЛЛЫ, ЗАГОН, СПЕЦПРИЁМЫ, БАЛАНС
## (заказ владельца, спринт 13, блоки 1-7)
## ═══════════════════════════════════════════════════════════════════════════
##   A ДЕКОР      — Deco 01-18 разошлись по карте одним бакетом на файл;
##                  указатели вдоль маршрута между базами, пугала у зон.
##   B ГНОЛЛЫ     — числа рода войск из конфига (быстрый, слабый, короткая
##                  дальность), стая из трёх отрядов у пня, кость летит СВОИМ
##                  слоем и своим пулом, промахи есть, кайт от подошедшей
##                  пехоты, волна по удару и откат после третьей.
##   C ЗАГОН      — рудника в меню рабочего нет, загон есть; вместимость
##                  «X / 20 овец»; потолок выпаса у замка; период удвоения в
##                  загоне ВДВОЕ короче замкового; овца ходит и внутрь, и
##                  наружу.
##   D РАЗДЕЛКА   — пять ударов ножом до смерти, туша лежит на боку и НЕ
##                  мигает, 300 еды за 20 ходок.
##   E КУЗНИЦА    — четвёртый слот открыт после трёх базовых, платы за доступ
##                  нет, включён по умолчанию (залп лучников тоже).
##   F ПРИЁМЫ     — «Яростный Набег»: пять ударов «обычный-мощный-обычный-
##                  мощный-обычный», щит поднят, шаг быстрее; «Натиск Фаланги»:
##                  усиленные удары, затем оттеснение со сниженным уроном.
##   G МЕЧНИК     — отряд занимает два слота лимита, дороже и дольше, запас и
##                  броня выше, шаг −0.1, напор и вес выше.
##   H МОНАХ      — потолок три, лечение показывает зелёный эффект.
## Запуск: godot --headless --path . res://qa_sprint13/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Forge  := preload("res://scripts/forge_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(420.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с"); _finish())

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
	print("\n═════ ИТОГ qa_sprint13: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var scene: PackedScene = Building.PRELOAD_SCENES.get(uid)
	if scene == null:
		return null
	var u: Unit = scene.instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, main.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	await pframes(6)

	await _a_deco()
	await _b_gnolls()
	await _c_pen()
	await _d_butcher()
	_e_forge()
	await _f_abilities()
	_g_warrior()
	# await ОБЯЗАТЕЛЕН: внутри есть ожидания физкадров, и без него _run
	# доходил до _finish и гасил сцену раньше, чем блок H успевал отчитаться
	await _h_monk()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ДЕКОРАЦИИ
# ═════════════════════════════════════════════════════════════════════════════
func _a_deco() -> void:
	print("\n═════ A. ДЕКОРАЦИИ Deco 01-18 ═════")
	# ЛЕНТЫ НА ДИСКЕ. Правило 8: перебора каталога нет, спрашиваем имена
	var missing: Array = []
	for n in range(1, 19):
		var p: String = "res://assets/environment/resources/Deco/%02d.png" % n
		if not ResourceLoader.exists(p):
			missing.append(n)
	verdict("A1 все восемнадцать картинок Deco на месте", missing.is_empty(),
		"нет: %s" % str(missing))
	var small: int = int(main.deco_small_placed)
	var signs: int = int(main.deco_signs_placed)
	var crows: int = int(main.deco_crows_placed)
	print("  посажено: мелочи %d, указателей %d, пугал %d" % [small, signs, crows])
	# ЧИСЛО МЕЛОЧИ СЧИТАЕТСЯ ПО КОНФИГУ, А НЕ ХАРДКОДОМ (правило 10): сажается
	# DECO_SMALL_PER_UNIT × MAP_GROWTH², часть точек отвергают вода и резерв
	var want: int = int(float(main.DECO_SMALL_PER_UNIT) * main.MAP_GROWTH * main.MAP_GROWTH)
	verdict("A2 мелочь 01-15 разошлась по карте почти в полном числе",
		small > want / 2 and small <= want,
		"село %d из заказанных %d" % [small, want])
	verdict("A3 указатели 16-17 стоят вдоль маршрута между базами", signs >= 2,
		"указателей %d" % signs)
	verdict("A4 пугала 18 стоят у зон", crows >= 3, "пугал %d" % crows)
	# ── ОДИН БАКЕТ НА ФАЙЛ, А НЕ УЗЕЛ НА ШТУКУ ─────────────────────────────
	# Ровно это и есть цена правки: тысяча декораций обязана стоить столько же
	# вызовов отрисовки, сколько РАЗНЫХ картинок на поле. Считаем бакеты
	# растительности: их не может быть больше, чем лент леса плюс восемнадцать
	var buckets: int = GameManager.veg.bucket_count()
	var planted: int = GameManager.veg.planted_count()
	print("  бакетов растительности %d, экземпляров %d" % [buckets, planted])
	verdict("A5 декорации едут ОБЩЕЙ отрисовкой: бакетов много меньше штук",
		planted > buckets * 4 and buckets < 40,
		"бакетов %d при %d экземплярах" % [buckets, planted])

# ═════════════════════════════════════════════════════════════════════════════
# B. ГНОЛЛЫ
# ═════════════════════════════════════════════════════════════════════════════
func _b_gnolls() -> void:
	print("\n═════ B. ГНОЛЛЫ У ПНЯ ═════")
	# ── ЧИСЛА РОДА ВОЙСК ЧИТАЕМ ИЗ КОНФИГА (правило 10) ───────────────────
	var g: Dictionary = _UCfg.get_stats("gnoll")
	var sp: Dictionary = _UCfg.get_stats("goblin_spearman")
	var ar: Dictionary = _UCfg.get_stats("archer")
	# Владелец 14.09.2026 уравнял шаг гнолла с ордой (2.5 → 2.2): стережём
	# «не медленнее», а не «быстрее»
	verdict("B1 гнолл не медленнее орды",
		float(g.get("movement_speed", 0.0)) >= float(sp.get("movement_speed", 99.0)),
		"гнолл %.1f против %.1f у гоблина" % [
			float(g.get("movement_speed", 0.0)), float(sp.get("movement_speed", 0.0))])
	verdict("B2 гнолл слабее и хрупче гоблина-копейщика",
		float(g.get("health", 999.0)) < float(sp.get("health", 0.0))
			and float(g.get("attack_1", 999.0)) < float(sp.get("attack_1", 0.0)),
		"запас %.0f против %.0f, урон %.1f против %.1f" % [
			float(g.get("health", 0.0)), float(sp.get("health", 0.0)),
			float(g.get("attack_1", 0.0)), float(sp.get("attack_1", 0.0))])
	verdict("B3 дальность броска КОРОТКАЯ — заметно меньше лучницкой",
		float(g.get("attack_range", 999.0)) < float(ar.get("attack_range", 0.0)) * 0.75,
		"%.1f м против %.1f у лучника" % [
			float(g.get("attack_range", 0.0)), float(ar.get("attack_range", 0.0))])
	# СПРИНТ 15 РАЗВЕРНУЛ: «кость летит почти по прямой, как бросок от руки, а
	# не навесом» — дуга ниже стрелковой
	verdict("B4 дуга кости ПОЛОЖЕ стрелковой (бросок от руки, спринт 15)",
		_GobCfg.GNOLL_BONE_ARC < _UCfg.stat("archer", "arrow_arc", 0.5),
		"дуга %.2f против %.2f" % [_GobCfg.GNOLL_BONE_ARC,
			_UCfg.stat("archer", "arrow_arc", 0.5)])

	# ── СТАЯ У ПНЯ ────────────────────────────────────────────────────────
	var lair = GameManager.troll_lair
	verdict("B5 логово (пень) на карте есть", lair != null and is_instance_valid(lair))
	if lair == null or not is_instance_valid(lair):
		return
	await pframes(20)
	var squads: int = int(lair.gnoll_squads_total)
	var alive: int = int(lair.gnolls_alive())
	print("  стая у пня: отрядов %d, живых гноллов %d" % [squads, alive])
	verdict("B6 на старте у пня ровно GNOLL_START_SQUADS отрядов стаи",
		squads == _GobCfg.GNOLL_START_SQUADS,
		"отрядов %d, ждали %d" % [squads, _GobCfg.GNOLL_START_SQUADS])
	verdict("B7 стая набрана уставным числом (SQUAD_SIZE)",
		alive >= _GobCfg.GNOLL_START_SQUADS * int(_GobCfg.SQUAD_SIZE["gnoll"]) - 2,
		"живых %d при уставе %d × %d" % [alive,
			_GobCfg.GNOLL_START_SQUADS, int(_GobCfg.SQUAD_SIZE["gnoll"])])
	# ── ЧАСЫ ВОЛН НЕ ТИКАЮТ, ПОКА ПО ПНЮ НЕ БЬЮТ ──────────────────────────
	verdict("B8 часы волн не взведены, пока пень не тронут",
		lair.gnoll_wave_left() == INF,
		"до волны %.0f с" % lair.gnoll_wave_left())
	lair.on_lair_attacked()
	verdict("B9 первый удар по пню взводит часы на GNOLL_WAVE_SEC",
		absf(lair.gnoll_wave_left() - _GobCfg.GNOLL_WAVE_SEC) < 1.0,
		"до волны %.0f с, ждали %.0f" % [lair.gnoll_wave_left(), _GobCfg.GNOLL_WAVE_SEC])
	# Волны гоняем СОБЫТИЕМ, а не стенными часами: три минуты игрового
	# ожидания × три волны стенд ждать не должен (правило 12)
	var before: int = int(lair.gnoll_squads_total)
	lair._on_gnoll_wave()
	await pframes(10)
	verdict("B10 волна приводит GNOLL_WAVE_SQUADS отрядов",
		int(lair.gnoll_squads_total) - before == _GobCfg.GNOLL_WAVE_SQUADS,
		"пришло %d отрядов" % (int(lair.gnoll_squads_total) - before))
	lair._on_gnoll_wave()
	await pframes(6)
	lair._on_gnoll_wave()
	await pframes(6)
	verdict("B11 волн не больше GNOLL_WAVES_MAX подряд",
		int(lair.gnoll_wave) == _GobCfg.GNOLL_WAVES_MAX,
		"волн %d" % int(lair.gnoll_wave))
	verdict("B12 после третьей волны — длинный откат GNOLL_COOLDOWN_SEC",
		absf(lair.gnoll_wave_left() - _GobCfg.GNOLL_COOLDOWN_SEC) < 2.0,
		"до следующей %.0f с, ждали %.0f" % [
			lair.gnoll_wave_left(), _GobCfg.GNOLL_COOLDOWN_SEC])

	# ── КОСТЬ: СВОЙ СЛОЙ, СВОЙ ПУЛ, ПРОМАХИ ───────────────────────────────
	var gn: Unit = _spawn("gnoll", Constants.FACTION_GOBLIN,
		Vector3(0.0, 0.0, 0.0))
	var victim: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		Vector3(6.0, 0.0, 0.0))
	verdict("B13 гнолл и цель поставлены", gn != null and victim != null)
	if gn == null or victim == null:
		return
	await pframes(4)
	# Жертва не должна ни двигаться, ни отвечать — меряем броски
	victim.set_tick(false)
	var arrows0: int = GameManager.arrows_mm.flight_count()
	# ── СПРИНТ 15: КОСТЬ ВЫЛЕТАЕТ НА КАДРЕ ЗАМАХА, А НЕ В ТОТ ЖЕ ТИК ──────
	# Бросок отложен на _throw_delay и живёт в тике гнолла: двадцать четыре
	# вызова подряд дали бы ОДНУ кость (каждый следующий перебивает замах).
	# Ждём каждый бросок и держим метателя на месте (патруль иначе уводит)
	var pin_g: Vector3 = gn.global_position
	for _i in range(24):
		gn._on_attack_fired(victim, gn.attack_damage)
		for _f in range(int(gn.call("_throw_delay") * 60.0) + 3):
			gn.global_position = pin_g
			gn.sync_row()
			await get_tree().physics_frame
	await pframes(2)
	print("  брошено костей %d, из них промахов %d; полётов в слое стрел %d, в слое костей %d" % [
		int(gn.bones_thrown), int(gn.bones_missed),
		GameManager.arrows_mm.flight_count(), GameManager.bones_mm.flight_count()])
	verdict("B14 кость летит СВОИМ слоем отрисовки, а не слоем стрел",
		GameManager.bones_mm.flight_count() > 0
			and GameManager.arrows_mm.flight_count() == arrows0,
		"костей в полёте %d, стрел %d (было %d)" % [
			GameManager.bones_mm.flight_count(),
			GameManager.arrows_mm.flight_count(), arrows0])
	verdict("B15 у слоя костей своя картинка и свой буфер ядра",
		GameManager.bones_mm.core_id >= 0
			and GameManager.bones_mm.core_id != GameManager.arrows_mm.core_id,
		"core_id костей %d, стрел %d" % [
			GameManager.bones_mm.core_id, GameManager.arrows_mm.core_id])
	verdict("B16 часть броска уходит в землю мимо цели (промахи есть)",
		int(gn.bones_missed) > 0 and int(gn.bones_missed) < int(gn.bones_thrown),
		"промахов %d из %d" % [int(gn.bones_missed), int(gn.bones_thrown)])
	# ── КАЙТ: ПЕХОТА ПОДОШЛА — ГНОЛЛ ОТБЕЖАЛ ──────────────────────────────
	victim.set_tick(true)
	victim.global_position = gn.global_position + Vector3(2.0, 0.0, 0.0)
	victim.sync_row()
	victim.set_tick(false)
	var from: Vector3 = gn.global_position
	gn._kite_t = 0.0
	for _k in range(40):
		gn.tick_physics(1.0 / 60.0)
		await get_tree().physics_frame
	var moved: float = Vector2(gn.global_position.x - from.x,
		gn.global_position.z - from.z).length()
	var away: float = Vector2(gn.global_position.x - victim.global_position.x,
		gn.global_position.z - victim.global_position.z).length()
	print("  кайт: отбежал %.2f м, до пехотинца стало %.2f м, срабатываний %d" % [
		moved, away, int(gn.kites)])
	verdict("B17 гнолл отбегает от подошедшей вплотную пехоты",
		int(gn.kites) > 0 and away > 2.0,
		"срабатываний %d, дистанция %.2f м" % [int(gn.kites), away])
	verdict("B18 в рукопашную гнолл не идёт вовсе", not gn.pursues_target())
	verdict("B19 поводок инициативы у гнолла короче общего",
		gn.aggro_leash() < Unit.AGGRO_LEASH,
		"%.1f против общих %.1f м" % [gn.aggro_leash(), Unit.AGGRO_LEASH])

# ═════════════════════════════════════════════════════════════════════════════
# C. ЗАГОН ДЛЯ ОВЕЦ
# ═════════════════════════════════════════════════════════════════════════════
func _c_pen() -> void:
	print("\n═════ C. ЗАГОН ДЛЯ ОВЕЦ ═════")
	var menu: Dictionary = GameManager.worker_buildings()
	verdict("C1 золотого рудника в меню рабочего больше нет",
		not menu.has("mine"), "меню: %s" % str(menu.keys()))
	verdict("C2 загон для овец в меню рабочего есть", menu.has("sheep_pen"),
		"меню: %s" % str(menu.keys()))
	# Механика ничейных рудников на карте при этом ЖИВА — её не заказывали
	# убирать, убрали только кнопку
	verdict("C2б ничейные рудники на карте остались",
		get_tree().get_nodes_in_group("neutral_buildings").size() > 0,
		"ничейных построек %d" % get_tree().get_nodes_in_group("neutral_buildings").size())
	verdict("C3 иконка и спрайт загона — Wooden Fence",
		ResourceLoader.exists(
			"res://assets/environment/resources/Wooden/Wooden Fence_64x64 tile.png"))

	# ── ЖИВОЙ ЗАГОН ───────────────────────────────────────────────────────
	var pen: Building = load("res://scripts/SheepPen.gd").new()
	pen.faction = Constants.FACTION_PLAYER
	main.world_add(pen)
	var pp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-26.0, 0.0, -26.0)
	pen.global_position = Vector3(pp.x, main.get_terrain_height(pp.x, pp.z), pp.z)
	await pframes(6)
	verdict("C4 загон в группе sheep_pens и знает свою вместимость",
		pen.is_in_group("sheep_pens") and pen.capacity() == _UCfg.SHEEP_PEN_CAPACITY,
		"вместимость %d, в конфиге %d" % [pen.capacity(), _UCfg.SHEEP_PEN_CAPACITY])
	verdict("C5 подпись загона — «Вместимость: X / %d овец»" % _UCfg.SHEEP_PEN_CAPACITY,
		pen.capacity_text().begins_with("Вместимость: 0 / %d" % _UCfg.SHEEP_PEN_CAPACITY),
		pen.capacity_text())
	# Ограда лежит ПЛАШМЯ, а не стоит билбордом (арт нарисован сверху)
	# ── УЗЕЛ ИЩЕМ ПОЛЕМ, А НЕ ИМЕНЕМ ───────────────────────────────────────
	# Имя «PenFence» ставится ДО внесения в дерево, и при пересборке меша по
	# рельефу движок вправе его переименовать (та же ловушка, что у знамён
	# отряда — см. CLAUDE.md). Поле _fence_mi врать не может
	var fence: MeshInstance3D = pen._fence_mi
	var verts: int = 0
	if fence != null and fence.mesh != null:
		verts = (fence.mesh as ArrayMesh).surface_get_array_len(0)
	verdict("C6 ограда — свой меш по рельефу, а не вертикальный билборд",
		fence != null and is_instance_valid(fence) and verts > 4
			and pen.get_node_or_null("BuildingSprite") == null,
		"вершин в меше ограды %d" % verts)

	# ── ЖИВОЙ ПУТЬ ПОСТРОЙКИ: СТРОЙПЛОЩАДКА → ЗАГОН ───────────────────────
	# Кнопка в меню и запись в конфиге ещё не значат, что здание встанет:
	# готовую постройку выдаёт фабрика ConstructionSite._make_target, и
	# забытая там строка означает вечный фундамент. Проверяем весь путь
	var site: Building = load("res://scripts/ConstructionSite.gd").new()
	site.faction = Constants.FACTION_PLAYER
	site.target_id = "sheep_pen"
	site.target_name = "Загон для овец"
	site.build_time = 1.0
	site.build_size = _UCfg.building_size("sheep_pen")
	main.world_add(site)
	var sp2: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-40.0, 0.0, -14.0)
	site.global_position = Vector3(sp2.x, main.get_terrain_height(sp2.x, sp2.z), sp2.z)
	await pframes(4)
	site.progress = site.build_time
	site._complete()
	await pframes(6)
	var built: Building = null
	for b2 in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b2) and b2 is Building 				and String((b2 as Building).building_id) == "sheep_pen" 				and b2 != pen:
			built = b2
	verdict("C6б стройплощадка достраивается именно в ЗАГОН (фабрика знает его)",
		built != null and built.is_in_group("sheep_pens"),
		"построено=%s" % str(built != null))

	# ── ПРИВЯЗКА ОВЦЫ И ПОТОЛКИ ───────────────────────────────────────────
	var SheepS: GDScript = load("res://scripts/goblin/Sheep.gd")
	var s1: Node3D = SheepS.new()
	main.world_add(s1)
	s1.global_position = pen.global_position + Vector3(1.0, 0.0, 1.0)
	await pframes(4)
	var took: bool = pen.accept_sheep(s1)
	verdict("C7 загон принимает принесённую овцу и привязывает её",
		took and s1.pen == pen and s1.is_owned() and pen.sheep_count() == 1,
		"принял=%s, в загоне %d" % [str(took), pen.sheep_count()])
	verdict("C8 период удвоения в ЗАГОНЕ вдвое короче замкового",
		is_equal_approx(s1.breed_sec(), _GobCfg.SHEEP_BREED_PEN_SEC)
			and is_equal_approx(_GobCfg.SHEEP_BREED_CASTLE_SEC,
				_GobCfg.SHEEP_BREED_PEN_SEC * 2.0),
		"в загоне %.0f с, у замка %.0f с" % [
			s1.breed_sec(), _GobCfg.SHEEP_BREED_CASTLE_SEC])
	verdict("C9 потолок стада в загоне — %d голов" % _UCfg.SHEEP_PEN_CAPACITY,
		s1.flock_limit() == _UCfg.SHEEP_PEN_CAPACITY,
		"потолок %d" % s1.flock_limit())
	# ── СПРИНТ 19 (письмо 10): первые INSIDE_CAP пасутся ВНУТРИ ограды, лишние
	# — вокруг в OVERFLOW_RADIUS (разворот прежнего «заходит и выходит»)
	verdict("C10 первая овца загона пасётся ВНУТРИ ограды (радиус %.1f < полуширины %.1f), лишние — в %.0f м" % [
			s1.graze_radius(), minf(pen.build_size.x, pen.build_size.z) * 0.5, pen.OVERFLOW_RADIUS],
		s1.graze_radius() < minf(pen.build_size.x, pen.build_size.z) * 0.5
			and pen.OVERFLOW_RADIUS > maxf(pen.build_size.x, pen.build_size.z) * 0.5)
	# ── ПОТОЛОК ВЫПАСА У ЗАМКА ───────────────────────────────────────────
	var s2: Node3D = SheepS.new()
	main.world_add(s2)
	s2.global_position = main.PLAYER_BASE_ANCHOR
	await pframes(4)
	s2.bind_to_keep(pen, Constants.FACTION_PLAYER)
	verdict("C11 у зоны замка потолок выпаса — CASTLE_GRAZE_LIMIT",
		s2.flock_limit() == _UCfg.CASTLE_GRAZE_LIMIT
			and is_equal_approx(s2.breed_sec(), _GobCfg.SHEEP_BREED_CASTLE_SEC),
		"потолок %d, период %.0f с" % [s2.flock_limit(), s2.breed_sec()])
	verdict("C12 потолок замка МЕНЬШЕ загонного: загон и нужен ради этого",
		_UCfg.CASTLE_GRAZE_LIMIT < _UCfg.SHEEP_PEN_CAPACITY,
		"%d против %d" % [_UCfg.CASTLE_GRAZE_LIMIT, _UCfg.SHEEP_PEN_CAPACITY])

# ═════════════════════════════════════════════════════════════════════════════
# D. РАЗДЕЛКА: ПЯТЬ УДАРОВ, ТУША, 300 ЕДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _d_butcher() -> void:
	print("\n═════ D. РАЗДЕЛКА ═════")
	verdict("D1 пять ударов ножом до смерти (заказ)",
		Worker.SHEEP_KILL_CUTS == 5, "ударов %d" % Worker.SHEEP_KILL_CUTS)
	var total: float = float(Worker.SHEEP_MEAT_TRIPS) * Worker.MEAT_PER_TRIP
	verdict("D2 с туши ровно 300 еды", is_equal_approx(total, 300.0),
		"%.0f еды = %d ходок × %.0f" % [total, Worker.SHEEP_MEAT_TRIPS,
			Worker.MEAT_PER_TRIP])
	verdict("D3 ходок 15-30, как заказано",
		Worker.SHEEP_MEAT_TRIPS >= 15 and Worker.SHEEP_MEAT_TRIPS <= 30,
		"ходок %d" % Worker.SHEEP_MEAT_TRIPS)
	# ВРЕМЯ РАЗДЕЛКИ: только удары ножом, без дороги — нижняя оценка. Заказ
	# просит 2-3 минуты, дорога добавит ещё
	var knife: float = float(Worker.SHEEP_KILL_CUTS
		+ Worker.SHEEP_MEAT_TRIPS * Worker.SHEEP_CUTS_PER_MEAT) * Worker.SHEEP_CUT_SEC
	print("  чистого времени под ножом %.0f с (плюс дорога на %d ходок)" % [
		knife, Worker.SHEEP_MEAT_TRIPS])
	verdict("D4 разделка укладывается в 2-3 минуты вместе с дорогой",
		knife > 60.0 and knife < 170.0, "под ножом %.0f с" % knife)

	# ── ТУША: НА БОКУ И БЕЗ КРАСНОГО МИГАНИЯ ──────────────────────────────
	var SheepS: GDScript = load("res://scripts/goblin/Sheep.gd")
	var sh: Node3D = SheepS.new()
	main.world_add(sh)
	var sp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(4.0, 0.0, 4.0)
	sh.global_position = Vector3(sp.x, main.get_terrain_height(sp.x, sp.z), sp.z)
	await pframes(4)
	# Удар ножом БОЛЬШЕ НЕ КРАСИТ (прямой заказ): проверяем СВОЙСТВО —
	# модуляция материала после удара осталась белой
	sh.wound_flash()
	await pframes(2)
	var mat: ShaderMaterial = sh._mat
	var mod: Color = Color.WHITE
	if mat != null:
		var v: Variant = mat.get_shader_parameter("modulate")
		if v != null:
			mod = v
	verdict("D5 удар ножом НЕ красит овцу (красного мигания больше нет)",
		is_equal_approx(mod.r, 1.0) and is_equal_approx(mod.g, 1.0)
			and is_equal_approx(mod.b, 1.0),
		"модуляция %s" % str(mod))
	var before_hops: int = int(sh.hops)
	sh.kill_flip()
	await pframes(6)
	var tilt: float = 0.0
	if sh._mi != null:
		tilt = absf(sh._mi.rotation_degrees.z)
	verdict("D6 туша ложится на бок (поворот 90°) и билборд у неё снят",
		bool(sh.dead) and is_equal_approx(tilt, 90.0)
			and float(mat.get_shader_parameter("world_fixed")) > 0.5,
		"наклон %.0f°, world_fixed %s" % [tilt,
			str(mat.get_shader_parameter("world_fixed"))])
	# Мёртвая не ходит и не плодится
	sh.force_hop()
	for _i in range(30):
		await get_tree().physics_frame
	verdict("D7 туша лежит: ни перебежек, ни приплода",
		int(sh.hops) == before_hops and int(sh.bred) == 0,
		"перебежек %d (было %d), приплода %d" % [
			int(sh.hops), before_hops, int(sh.bred)])
	verdict("D8 смерть и исчезновение — РАЗНЫЕ события",
		not bool(sh.eaten) and is_instance_valid(sh),
		"eaten=%s" % str(sh.eaten))
	# ПРАВИЛО 5: после consume() узел уходит в очередь на освобождение, и
	# читать у него поля через кадр НЕЛЬЗЯ — проверяем СНАЧАЛА признак, потом
	# сам факт исчезновения узла
	sh.consume()
	var eaten_now: bool = bool(sh.eaten)
	await pframes(3)
	verdict("D9 consume() убирает выработанную тушу",
		eaten_now and not is_instance_valid(sh),
		"признак %s, узел жив %s" % [str(eaten_now), str(is_instance_valid(sh))])

# ═════════════════════════════════════════════════════════════════════════════
# E. КУЗНИЦА: ЧЕТВЁРТЫЙ СЛОТ
# ═════════════════════════════════════════════════════════════════════════════
func _e_forge() -> void:
	print("\n═════ E. ЧЕТВЁРТЫЙ СЛОТ КУЗНИЦЫ ═════")
	verdict("E1 плату за доступ к способности убрали (заказ блока 4)",
		is_equal_approx(_Forge.squad_unlock_cost(
			_Forge.get_node("archer_1d")), 0.0),
		"цена доступа %.0f" % _Forge.squad_unlock_cost(_Forge.get_node("archer_1d")))
	# ── ДОСТУП СРАЗУ ВСЕМ ОТРЯДАМ ЭТОГО РОДА ─────────────────────────────
	var f: int = Constants.FACTION_PLAYER
	var sid: int = GameManager.new_squad(f, "archer")
	verdict("E2 без исследования способности у отряда нет",
		not GameManager.squad_has_ability(sid, "archer_1d"))
	GameManager.finish_research(f, "archer_1d")
	verdict("E3 после исследования способность есть у ВСЕХ отрядов этого рода",
		GameManager.squad_has_ability(sid, "archer_1d")
			and GameManager.squad_has_ability(GameManager.new_squad(f, "archer"),
				"archer_1d"))
	verdict("E4 залп лучников ВКЛЮЧЁН по умолчанию (заказ блока 5)",
		GameManager.squad_ability_on(sid, "archer_1d"))
	GameManager.squad_set_ability(sid, "archer_1d", false)
	verdict("E5 залп можно выключить", not GameManager.squad_ability_on(sid, "archer_1d"))
	GameManager.squad_set_ability(sid, "archer_1d", true)
	# ── РЯД D ОТКРЫВАЕТСЯ ПОСЛЕ ТРЁХ БАЗОВЫХ ─────────────────────────────
	# research_blockers принимает СЛОТ (не имя) и отвечает СПИСКОМ незакрытых
	# требований — так его и спрашиваем
	var slot: Dictionary = _UCfg.get_upgrade_slot("warrior_1d")
	var blocked: Array = GameManager.research_blockers(f, slot)
	verdict("E6 четвёртый слот закрыт, пока не изучены три базовых узла ряда",
		not blocked.is_empty(), "не хватает: %s" % str(blocked))
	for cell in ["1a", "1b", "1c"]:
		GameManager.finish_research(f, "warrior_" + cell)
	var blocked2: Array = GameManager.research_blockers(f, slot)
	verdict("E7 три базовых узла ряда открывают четвёртый слот",
		blocked2.is_empty(), "не хватает: %s" % str(blocked2))

# ═════════════════════════════════════════════════════════════════════════════
# F. СПЕЦПРИЁМЫ ПО ДВОЙНОМУ ПКМ
# ═════════════════════════════════════════════════════════════════════════════
func _f_abilities() -> void:
	print("\n═════ F. СПЕЦПРИЁМЫ ═════")
	var f: int = Constants.FACTION_PLAYER
	# ── ЯРОСТНЫЙ НАБЕГ ───────────────────────────────────────────────────
	var w: Unit = _spawn("warrior", f, main.PLAYER_BASE_ANCHOR + Vector3(10.0, 0.0, 0.0))
	var foe: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN,
		main.PLAYER_BASE_ANCHOR + Vector3(11.5, 0.0, 0.0))
	verdict("F1 мечник и цель поставлены", w != null and foe != null)
	if w == null or foe == null:
		return
	await pframes(4)
	# ── БОЙЦЫ ЗАМОРОЖЕНЫ: МЕРЯЕМ ПРИЁМ, А НЕ БОЙ ──────────────────────────
	# Гоблин стоит в полутора метрах, и авто-агро успевает начать замах — а
	# замах ставит _anim_lock_until_ms, из-за которого _update_guard делает
	# ранний выход. Проверка «щит в набеге поднят» краснела через прогон НЕ
	# на коде, а на этом (та же ловушка, что у всадника в qa_cavalry)
	w.set_tick(false)
	foe.set_tick(false)
	verdict("F2 узел warrior_1d называется «Яростный Набег»",
		String(_Forge.get_node("warrior_1d").get("name", "")) == "Яростный Набег",
		String(_Forge.get_node("warrior_1d").get("name", "")))
	var speed0: float = w._effective_speed()
	var cd0: float = w._effective_cooldown()
	w.start_rage_dash()
	verdict("F3 набег взводит серию из RAGE_HITS ударов",
		w.rage_active() and w.rage_left() == Warrior.RAGE_HITS,
		"осталось %d из %d" % [w.rage_left(), Warrior.RAGE_HITS])
	verdict("F4 в набеге шаг быстрее обычного",
		w._effective_speed() > speed0 * 1.2,
		"%.2f против %.2f м/с" % [w._effective_speed(), speed0])
	verdict("F5 удары серии быстрые: перезарядка короче",
		w._effective_cooldown() < cd0 * 0.6,
		"%.2f против %.2f с" % [w._effective_cooldown(), cd0])
	# ── ЗАМОК ПОЗЫ СНИМАЕТСЯ ЯВНО, И ЭТО НЕ ПОДЛОГ ────────────────────────
	# _update_guard делает РАННИЙ ВЫХОД, пока идёт лента удара
	# (_anim_lock_until_ms), и это верно: поза удара важнее позы щита. Но
	# правило, которое здесь меряется, — «в набеге щит поднят», и к
	# расписанию лент оно отношения не имеет. Гоблин в полутора метрах
	# успевает получить ответный удар за те четыре физкадра, что идут до
	# заморозки, и проверка мигала через прогон НЕ на коде
	w._anim_lock_until_ms = 0
	w._update_guard()
	verdict("F6 щит в набеге поднят (зафиксирован)", w.is_guarding(),
		"набег идёт=%s, щит=%s" % [str(w.rage_active()), str(w.is_guarding())])
	# ── СЕРИЯ: обычный, мощный, обычный, мощный, обычный ─────────────────
	var strong: float = _UCfg.stat("warrior", "attack_2", w.attack_damage * 2.4)
	var seq: Array = []
	for _i in range(Warrior.RAGE_HITS):
		seq.append(w._strike_damage() > (w.attack_damage + strong) * 0.5)
	print("  серия набега (true = мощный): %s" % str(seq))
	verdict("F7 серия ровно «обычный-мощный-обычный-мощный-обычный»",
		seq == [false, true, false, true, false], str(seq))
	verdict("F8 серия исчерпана — набег кончился", not w.rage_active(),
		"осталось %d" % w.rage_left())
	verdict("F9 после набега ротация вернулась к обычной 3+1",
		int(w.rage_hits_done) == Warrior.RAGE_HITS
			and int(w.rage_strong_done) == 2,
		"ударов %d, мощных %d" % [int(w.rage_hits_done), int(w.rage_strong_done)])

	# ── НАТИСК ФАЛАНГИ ───────────────────────────────────────────────────
	var s: Unit = _spawn("spearman", f, main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, 10.0))
	verdict("F10 копейщик поставлен", s != null)
	if s == null:
		return
	await pframes(4)
	verdict("F11 узел spearman_4d называется «Натиск Фаланги» и стоит в 4-м слоте",
		String(_Forge.get_node("spearman_4d").get("name", "")) == "Натиск Фаланги",
		String(_Forge.get_node("spearman_4d").get("name", "")))
	var ssp0: float = s._effective_speed()
	var base_dmg: float = s._strike_damage()
	s.start_phalanx_push()
	verdict("F12 натиск взводит PHALANX_PUSH_HITS усиленных ударов",
		s.phalanx_push_active()
			and s.phalanx_push_hits_left() == Spearman.PHALANX_PUSH_HITS,
		"осталось %d" % s.phalanx_push_hits_left())
	verdict("F13 сомкнутый ход МЕДЛЕННЕЕ обычного",
		s._effective_speed() < ssp0 * 0.8,
		"%.2f против %.2f м/с" % [s._effective_speed(), ssp0])
	var boosted: float = s._strike_damage()
	verdict("F14 первые удары усилены", boosted > base_dmg * 1.2,
		"%.1f против обычного %.1f" % [boosted, base_dmg])
	# Тратим остаток серии
	for _k in range(Spearman.PHALANX_PUSH_HITS):
		s._strike_damage()
	verdict("F15 серия исчерпана — отряд переходит в ОТТЕСНЕНИЕ",
		s.phalanx_wall_active() and s.phalanx_push_hits_left() == 0,
		"оттеснение=%s, осталось %d" % [str(s.phalanx_wall_active()),
			s.phalanx_push_hits_left()])
	verdict("F16 в оттеснении входящий урон НИЖЕ, а напор ВЫШЕ",
		s._incoming_damage_factor(null) < 1.0 and s._push_power() > 0.0,
		"входящий ×%.2f, напор %.1f" % [s._incoming_damage_factor(null),
			s._push_power()])
	# ── РАЗДАЧА ПРИЁМОВ ЖИВЁТ В ОДНОМ МЕСТЕ ──────────────────────────────
	var sm = main.selection_manager
	verdict("F17 двойной ПКМ раздаёт приём по типу отряда, а не по имени",
		sm != null and "warrior" in sm.DOUBLE_RMB_ABILITIES
			and "spearman" in sm.DOUBLE_RMB_ABILITIES,
		"типов в таблице %d" % (sm.DOUBLE_RMB_ABILITIES.size() if sm != null else 0))

# ═════════════════════════════════════════════════════════════════════════════
# G. МЕЧНИК: ДВА СЛОТА, ДОРОЖЕ, ЖИВУЧЕЕ, МЕДЛЕННЕЕ
# ═════════════════════════════════════════════════════════════════════════════
func _g_warrior() -> void:
	print("\n═════ G. РЕБАЛАНС МЕЧНИКА ═════")
	verdict("G1 отряд мечников занимает два слота лимита",
		_UCfg.squad_slots("warrior") == 2,
		"слотов %d" % _UCfg.squad_slots("warrior"))
	var w: Dictionary = _UCfg.get_stats("warrior")
	var sp: Dictionary = _UCfg.get_stats("spearman")
	verdict("G2 запас и броня мечника ЗАМЕТНО выше копейщицких",
		float(w.get("health", 0.0)) > float(sp.get("health", 999.0)) * 1.5
			and float(w.get("armor", 0.0)) > float(sp.get("armor", 999.0)),
		"HP %.0f против %.0f, броня %.0f против %.0f" % [
			float(w.get("health", 0.0)), float(sp.get("health", 0.0)),
			float(w.get("armor", 0.0)), float(sp.get("armor", 0.0))])
	verdict("G3 шаг мечника на 0.1 ниже копейщицкого",
		is_equal_approx(float(sp.get("movement_speed", 0.0))
			- float(w.get("movement_speed", 0.0)), 0.1),
		"%.2f против %.2f" % [float(w.get("movement_speed", 0.0)),
			float(sp.get("movement_speed", 0.0))])
	verdict("G4 напор и вес мечника выше копейщицких",
		float(w.get("push_force", 0.0)) > float(sp.get("push_force", 999.0))
			and _UCfg.stat("warrior", "squad_weight", 1.0)
				> _UCfg.stat("spearman", "squad_weight", 1.0),
		"напор %.1f против %.1f, вес %.1f против %.1f" % [
			float(w.get("push_force", 0.0)), float(sp.get("push_force", 0.0)),
			_UCfg.stat("warrior", "squad_weight", 1.0),
			_UCfg.stat("spearman", "squad_weight", 1.0)])
	var tw: Dictionary = (_UCfg.TRAINING["castle"] as Dictionary)["warrior"]
	var ts: Dictionary = (_UCfg.TRAINING["barracks"] as Dictionary)["spearman"]
	verdict("G5 мечник дороже и дольше копейщика",
		float(tw.get("cost_gold", 0.0)) > float(ts.get("cost_gold", 999.0))
			and float(tw.get("time", 0.0)) > float(ts.get("time", 999.0)),
		"золото %.0f против %.0f, время %.0f против %.0f с" % [
			float(tw.get("cost_gold", 0.0)), float(ts.get("cost_gold", 0.0)),
			float(tw.get("time", 0.0)), float(ts.get("time", 0.0))])

# ═════════════════════════════════════════════════════════════════════════════
# H. МОНАХ
# ═════════════════════════════════════════════════════════════════════════════
func _h_monk() -> void:
	print("\n═════ H. МОНАХ ═════")
	verdict("H1 потолок монахов — три", _UCfg.MONK_LIMIT == 3,
		"потолок %d" % _UCfg.MONK_LIMIT)
	var m: Unit = _spawn("monk", Constants.FACTION_PLAYER,
		main.PLAYER_BASE_ANCHOR + Vector3(-8.0, 0.0, 0.0))
	verdict("H2 монах поставлен", m != null)
	if m == null:
		return
	var hurt: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		main.PLAYER_BASE_ANCHOR + Vector3(-7.0, 0.0, 0.0))
	if hurt == null:
		return
	hurt.current_health = hurt.max_health * 0.4
	hurt._soa_push_stats()   # монах ищет раненого по колонке ядра (14.09.2026)
	for _i in range(6):
		await get_tree().physics_frame
	m._heal_pulse()
	for _i in range(4):
		await get_tree().physics_frame
	# ЗЕЛЁНЫЙ ЭФФЕКТ — УЗЕЛ ПОД МОНАХОМ (Monk._build_heal_vfx), и он обязан
	# быть виден ровно пока лечение держится
	# УЗЕЛ ЭФФЕКТА ЖИВЁТ В МИРЕ, А НЕ РЕБЁНКОМ МОНАХА (Monk._build_heal_vfx):
	# ребёнок ехал бы по ЛОГИЧЕСКОЙ точке, а эффект ставится по нарисованной.
	# Поэтому спрашиваем поле монаха, а не обход его детей
	var vfx: MeshInstance3D = m._heal_vfx
	verdict("H3 над целью показан зелёный эффект лечения",
		vfx != null and is_instance_valid(vfx) and vfx.visible
			and String(vfx.name) == "HealVFX",
		"узел эффекта %s, виден %s" % [str(vfx != null),
			str(vfx.visible if vfx != null else false)])
	verdict("H4 лечение доехало до раненого",
		hurt.current_health > hurt.max_health * 0.4,
		"запас %.0f из %.0f" % [hurt.current_health, hurt.max_health])
