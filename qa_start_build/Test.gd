extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СТАРТ ПАРТИИ, ЗАСТРОЙКА ПО ТУМАНУ, БАШНЯ, ТРОЛЛЬ, ОВЦА
## (заказ владельца 10.09.2026, блоки 1-3 и 5)
## ═══════════════════════════════════════════════════════════════════════════
##   A СТАРТ      — крепости на карте нет, пять рабочих, старт сдвинут от угла,
##                  туман раскрыт только вокруг бригады, зелёной плашки и
##                  зелёной рамки края карты нет.
##   B ЗАСТРОЙКА  — строить можно там, где нет тумана, и нельзя в тумане;
##                  правило одно для замка и для любой постройки.
##   C ЛИМИТЫ     — база = пять рабочих и ноль отрядов; крепость даёт +10/+5;
##                  крепость расширяет круг обзора (CASTLE_VISION).
##   D БАШНЯ      — прочная и дорогая, до TOWER_VISIBLE_ARCHERS спрайтов на
##                  настиле; стрела бьёт ЛУЧНИКА (труп у подножия, резервист
##                  встаёт на место), копьё — только стены.
##   E ТРОЛЛЬ     — тени под ним нет, кольцо овальное и шире, прицел стрелка в
##                  туше, стрелы торчат в спрайте, окружение пробивается.
##   F ОВЦА       — рабочий несёт саму овцу (обычная ходьба), десять ударов на
##                  кусок, пять ходок, овца исчезает на пятой; мигает мягко.
## Запуск: godot --headless --path . res://qa_start_build/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _GS := preload("res://scripts/game_settings.gd")

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

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_start_build: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for c in node.get_children():
		var f := _find(c, name)
		if f != null:
			return f
	return null

func _player_workers() -> Array:
	var out: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(u) and u is Worker and not (u as Unit).is_dead():
			out.append(u)
	return out

func _player_castles() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if not is_instance_valid(b):
			continue
		var c := b as Castle
		if c != null and not c.is_dead() and c.is_stronghold():
			out.append(c)
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	await pframes(6)

	# ══ A. СТАРТ ПАРТИИ ═══════════════════════════════════════════════════════
	print("\n═════ A. СТАРТ ПАРТИИ ═════")
	var castles: Array = _player_castles()
	var workers: Array = _player_workers()
	verdict("A1 крепости на старте нет, на карте пять рабочих",
		castles.is_empty() and workers.size() == main.START_WORKER_RESOURCES.size()
			and workers.size() == 5,
		"крепостей %d, рабочих %d" % [castles.size(), workers.size()])
	var a: Vector3 = main.PLAYER_BASE_ANCHOR
	var inset_x: float = a.x + main.MAP_HALF_X
	var inset_z: float = a.z + main.MAP_HALF_Z
	verdict("A2 старт сдвинут от угла на PLAYER_START_SHIFT (%.0f м)" % main.PLAYER_START_SHIFT,
		is_equal_approx(inset_x, main.BASE_CORNER_INSET + main.PLAYER_START_SHIFT)
			and is_equal_approx(inset_z, main.BASE_CORNER_INSET + main.PLAYER_START_SHIFT),
		"отступ от угла %.1f / %.1f м" % [inset_x, inset_z])
	verdict("A3 зелёной плашки зоны застройки на карте нет",
		_find(main, "StartZone") == null and not main.START_ZONE_SHOWN)
	verdict("A4 зелёной рамки края карты нет, чернота осталась",
		_find(main, "WorldBevel") == null and _find(main, "WorldVoid") != null
			and not main.WORLD_BEVEL_SHOWN)
	# ── ТУМАН: КРУГ ВОКРУГ БРИГАДЫ, А НЕ ПОЛ-КАРТЫ ──────────────────────────
	var fog = GameManager.fog
	if fog != null:
		fog.enabled = true
		fog.refresh()
	var lit_here: bool = fog == null or fog.is_lit(a.x, a.z)
	var far: Vector3 = Vector3(0.0, 0.0, 0.0)
	var lit_far: bool = fog != null and fog.is_lit(far.x, far.z)
	var frac: float = fog.lit_fraction() if fog != null else 1.0
	verdict("A5 на старте видно только пятачок вокруг рабочих",
		lit_here and not lit_far and frac < 0.06,
		"у бригады видно=%s, центр карты видно=%s, доля карты %.3f" % [
			str(lit_here), str(lit_far), frac])

	# ══ B. ЗАСТРОЙКА ПО ТУМАНУ ════════════════════════════════════════════════
	print("\n═════ B. ЗАСТРОЙКА ПО ТУМАНУ ═════")
	verdict("B1 у бригады строить можно", main.can_build_at(a.x, a.z))
	verdict("B2 в тумане (центр карты) строить нельзя", not main.can_build_at(0.0, 0.0))
	verdict("B3 правило одно на все постройки (in_build_radius = can_build_at)",
		main.in_build_radius(a.x, a.z) == main.can_build_at(a.x, a.z)
			and main.in_build_radius(0.0, 0.0) == main.can_build_at(0.0, 0.0))
	if fog != null:
		fog.enabled = false
	verdict("B4 туман выключен (стенды, отладка) — разрешено всё поле",
		main.can_build_at(0.0, 0.0))

	# ══ C. ЛИМИТЫ И ОБЗОР КРЕПОСТИ ════════════════════════════════════════════
	print("\n═════ C. ЛИМИТЫ И ОБЗОР ═════")
	var f: int = Constants.FACTION_PLAYER
	var base_w: int = GameManager.pop_worker_cap(f)
	var base_s: int = GameManager.pop_squad_cap(f)
	verdict("C1 без крепости потолки — стартовая бригада (%d рабочих, %d отрядов)" % [
			_UCfg.POP_BASE_WORKERS, _UCfg.POP_BASE_SQUADS],
		base_w == _UCfg.POP_BASE_WORKERS and base_s == _UCfg.POP_BASE_SQUADS
			and _UCfg.POP_BASE_WORKERS == 5,
		"раб. %d, отр. %d" % [base_w, base_s])
	var castle := Castle.new()
	castle.faction = f
	main.world_add(castle)
	var cp: Vector3 = a + Vector3(12.0, 0.0, 6.0)
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await frames(3)
	verdict("C2 крепость даёт +%d рабочих и +%d отрядов" % [
			_UCfg.CASTLE_WORKER_SLOTS, _UCfg.CASTLE_SQUAD_SLOTS],
		GameManager.pop_worker_cap(f) == base_w + _UCfg.CASTLE_WORKER_SLOTS
			and GameManager.pop_squad_cap(f) == base_s + _UCfg.CASTLE_SQUAD_SLOTS,
		"раб. %d, отр. %d" % [GameManager.pop_worker_cap(f), GameManager.pop_squad_cap(f)])
	verdict("C3 обзор крепости шире обычной постройки (%.0f против %.0f м)" % [
			_UCfg.CASTLE_VISION, _UCfg.BUILDING_VISION],
		is_equal_approx(castle.vision_radius(), _UCfg.CASTLE_VISION)
			and _UCfg.CASTLE_VISION > _UCfg.BUILDING_VISION,
		"обзор %.0f м" % castle.vision_radius())
	if fog != null:
		fog.enabled = true
		fog.refresh()
		var edge: Vector3 = castle.global_position + Vector3(_UCfg.BUILDING_VISION + 6.0, 0.0, 0.0)
		verdict("C4 круг тумана вокруг крепости расширился",
			fog.is_lit(edge.x, edge.z),
			"точка в %.0f м от крепости освещена=%s" % [_UCfg.BUILDING_VISION + 6.0,
				str(fog.is_lit(edge.x, edge.z))])
		fog.enabled = false
	# Настройки отображения из меню
	verdict("C5 настройки отображения читаются с диска (FPS, край экрана)",
		typeof(_GS.show_fps()) == TYPE_BOOL and typeof(_GS.edge_pan()) == TYPE_BOOL)

	# ══ D. БАШНЯ ══════════════════════════════════════════════════════════════
	print("\n═════ D. БАШНЯ ═════")
	verdict("D1 башня прочная и дорогая",
		_UCfg.building_stat("tower", "max_hp", 0.0) >= 5000.0
			and _UCfg.building_cost("tower").get(Constants.RESOURCE_STONE, 0.0) >= 500.0,
		"запас %.0f, камень %.0f" % [_UCfg.building_stat("tower", "max_hp", 0.0),
			_UCfg.building_cost("tower").get(Constants.RESOURCE_STONE, 0.0)])
	var tower = load("res://scripts/Tower.gd").new()
	tower.faction = f
	main.world_add(tower)
	var tp: Vector3 = a + Vector3(0.0, 0.0, 30.0)
	tower.global_position = Vector3(tp.x, GameManager.get_terrain_height(tp.x, tp.z), tp.z)
	await frames(3)
	# Отряд лучников (30) — внутрь
	var sid: int = GameManager.new_squad(f, "archer")
	var archers: Array = []
	var ascene: PackedScene = Building.PRELOAD_SCENES["archer"]
	for i in range(_UCfg.SQUAD_SIZE_ARCHERS):
		var u: Unit = ascene.instantiate()
		u.faction = f
		main.world_add(u)
		var px: float = tp.x + float(i % 6) * 0.7
		var pz: float = tp.z + 4.0 + float(i / 6) * 0.7
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		archers.append(u)
	await pframes(3)
	verdict("D2 в башню входит отряд лучников (%d человек)" % _UCfg.SQUAD_SIZE_ARCHERS,
		tower.garrison_accepts("archer") and tower.request_garrison(sid)
			and archers.size() == 30, "бойцов %d" % archers.size())
	# Досылаем всех внутрь принудительно (обычно они идут к воротам сами)
	for u in archers:
		tower.absorb_unit(u)
	tower._sync_sentinel()
	await frames(2)
	verdict("D3 на настиле видно не больше %d лучников, остальные — резерв" % _UCfg.TOWER_VISIBLE_ARCHERS,
		tower.garrison_men() == 30 and tower.archers_shown() == _UCfg.TOWER_VISIBLE_ARCHERS,
		"внутри %d, на настиле %d" % [tower.garrison_men(), tower.archers_shown()])
	# ── УРОН: СТРЕЛА БЬЁТ ЛУЧНИКА, КОПЬЁ — СТЕНЫ ───────────────────────────
	var hp0: float = tower.current_health
	var far_archer: Unit = ascene.instantiate()
	far_archer.faction = Constants.FACTION_ENEMY
	main.world_add(far_archer)
	far_archer.global_position = tower.global_position + Vector3(18.0, 0.0, 0.0)
	var spear: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
	spear.faction = Constants.FACTION_ENEMY
	main.world_add(spear)
	spear.global_position = tower.global_position + Vector3(3.0, 0.0, 0.0)
	await pframes(3)
	var men0: int = tower.garrison_men()
	tower.take_damage(9000.0, far_archer)     # смертельный выстрел по лучнику
	await pframes(3)
	var men1: int = tower.garrison_men()
	verdict("D4 стрела бьёт ЛУЧНИКА на настиле, а не стены",
		men1 == men0 - 1 and is_equal_approx(tower.current_health, hp0),
		"внутри %d → %d, запас башни %.0f → %.0f" % [men0, men1, hp0, tower.current_health])
	# Труп лежит у подножия: точка падения считается самой башней
	var dead_spot: Vector3 = tower.corpse_spot(0)
	verdict("D5 труп падает у подножия башни (не в ней и не за 10 м)",
		Vector2(dead_spot.x - tower.global_position.x,
			dead_spot.z - tower.global_position.z).length() <= tower.ring_radius() + 1.5,
		"точка падения в %.1f м от центра" % Vector2(dead_spot.x - tower.global_position.x,
			dead_spot.z - tower.global_position.z).length())
	tower._sync_sentinel()
	await frames(2)
	verdict("D6 на место павшего встал резервист (спрайтов снова %d)" % _UCfg.TOWER_VISIBLE_ARCHERS,
		tower.archers_shown() == _UCfg.TOWER_VISIBLE_ARCHERS,
		"на настиле %d при %d внутри" % [tower.archers_shown(), tower.garrison_men()])
	var men2: int = tower.garrison_men()
	tower.take_damage(500.0, spear)           # пехота бьёт СТЕНЫ
	await pframes(2)
	verdict("D7 пехота бьёт только стены, укрытых достать не может",
		tower.garrison_men() == men2 and tower.current_health < hp0,
		"внутри %d, запас %.0f" % [tower.garrison_men(), tower.current_health])

	# ══ E. ТРОЛЛЬ ═════════════════════════════════════════════════════════════
	print("\n═════ E. ТРОЛЛЬ ═════")
	var lair = GameManager.troll_lair
	var troll: Unit = null
	if lair != null and is_instance_valid(lair):
		lair.set("aggro_enabled", false)
		var fresh: Array = lair.call("spawn_guards", 1)
		if not fresh.is_empty():
			troll = fresh[0]
	if troll == null:
		verdict("E0 тролля нет", false)
		_finish()
		return
	troll.set("_hunger_t", 1.0e6)
	await pframes(3)
	verdict("E1 тени под троллем нет вовсе, кольцо — овал и шире круга",
		is_equal_approx(troll.shadow_scale(), 0.0)
			and troll.ring_oval().x > 1.0 and troll.ring_oval().x > troll.ring_oval().y,
		"тень %.1f, овал %.2f×%.2f при кольце %.1f" % [troll.shadow_scale(),
			troll.ring_oval().x, troll.ring_oval().y, troll.ring_scale()])
	verdict("E2 стрелок целится в тушу, а не в точку на земле",
		troll.aim_height() >= 2.0 and troll.aim_height() > 0.8,
		"высота прицела %.1f м" % troll.aim_height())
	# Стрелы торчат в спрайте
	var stuck0: int = troll._arrows.size()
	var shots := 0
	for i in range(6):
		var arr: Node3D = GameManager.spawn_arrow(main.world_root(),
			troll.global_position + Vector3(6.0, 3.0, 0.0),
			troll.global_position + Vector3(0.0, troll.aim_height(), 0.0),
			6.0, 12.0, 0.0, 1.0, null, Constants.FACTION_PLAYER)
		if arr == null:
			continue
		if troll.stick_arrow(arr):
			shots += 1
	await pframes(2)
	verdict("E3 стрелы застревают в туше (до %d штук)" % troll.arrow_sockets(),
		shots >= 5 and troll._arrows.size() >= 5
			and troll._arrows.size() <= troll.arrow_sockets(),
		"воткнулось %d, держится %d при %d гнёздах" % [shots, troll._arrows.size(),
			troll.arrow_sockets()])
	# Окружение: кольцо копейщиков — тролль пробивает тела и расталкивает
	var ring: Array = []
	var rsid: int = GameManager.new_squad(f, "spearman")
	for i in range(12):
		var ang: float = TAU * float(i) / 12.0
		var u2: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
		u2.faction = f
		main.world_add(u2)
		var px2: float = troll.global_position.x + cos(ang) * 2.0
		var pz2: float = troll.global_position.z + sin(ang) * 2.0
		u2.global_position = Vector3(px2, GameManager.get_terrain_height(px2, pz2), pz2)
		u2.sync_row()
		GameManager.add_to_squad(rsid, u2)
		u2.set_stance("defense")
		ring.append(u2)
	await pframes(4)
	var d0: Array = []
	for u3 in ring:
		d0.append(Vector2((u3 as Unit).global_position.x - troll.global_position.x,
			(u3 as Unit).global_position.z - troll.global_position.z).length())
	await pframes(60)
	var pushed := 0
	for i in range(ring.size()):
		var u4 := ring[i] as Unit
		if not is_instance_valid(u4) or u4.is_dead():
			pushed += 1
			continue
		var d1: float = Vector2(u4.global_position.x - troll.global_position.x,
			u4.global_position.z - troll.global_position.z).length()
		if d1 > float(d0[i]) + 0.25:
			pushed += 1
	verdict("E4 в окружении тролль пробивает тела и расталкивает кольцо",
		troll.breaks_bodies and pushed >= 4,
		"пробивает=%s, раздвинуто %d из %d" % [str(troll.breaks_bodies), pushed, ring.size()])
	# Углы падения туши: тело кренится, а не стоит вертикально
	troll.take_damage(1.0e9, ring[0] if is_instance_valid(ring[0]) else null)
	await frames(3)
	var corpse: Node = _find(main, "TrollCorpse")
	var tilt: float = 0.0
	if corpse != null:
		tilt = float((corpse as Node3D).rotation_degrees.z)
	verdict("E5 туша падает под углом (крен до ±%.0f°), а не строго вертикально" % _GobCfg.TROLL_DEATH_TILT,
		corpse != null and absf(tilt) > 1.0 and absf(tilt) <= _GobCfg.TROLL_DEATH_TILT + 0.5,
		"крен %.1f°" % tilt)

	# ══ F. ОВЦА ═══════════════════════════════════════════════════════════════
	print("\n═════ F. ОВЦА И МЯСО ═════")
	# ── ЧИСЛА РАЗДЕЛКИ РАЗВЁРНУТЫ СПРИНТОМ 13 ──────────────────────────────
	# Было «десять ударов на кусок, ПЯТЬ ходок, туша 60 еды». Заказ: «пять
	# ударов ножом → смерть; с туши 300 еды за 15-30 ходок, то есть 2-3
	# минуты». Проверяем СВОЙСТВА заказа, а не запомненные числа: пять ударов
	# до смерти, итог ровно триста, число ходок в заказанной вилке
	var per_carcass: float = Worker.MEAT_PER_TRIP * float(Worker.SHEEP_MEAT_TRIPS)
	verdict("F1 пять ударов до смерти, туша = %.0f еды за %d ходок" % [
			per_carcass, Worker.SHEEP_MEAT_TRIPS],
		Worker.SHEEP_KILL_CUTS == 5 and is_equal_approx(per_carcass, 300.0)
			and Worker.SHEEP_MEAT_TRIPS >= 15 and Worker.SHEEP_MEAT_TRIPS <= 30,
		"убить %d удара, ходок %d по %.0f еды = %.0f" % [
			Worker.SHEEP_KILL_CUTS, Worker.SHEEP_MEAT_TRIPS,
			Worker.MEAT_PER_TRIP, per_carcass])
	verdict("F2 овца размножается сама (таймер покоя в конфиге)",
		_GobCfg.SHEEP_SELF_BREED_SEC > 0.0 and _GobCfg.SHEEP_CALM_SEC > 0.0,
		"раз в %.0f с при покое %.0f с" % [_GobCfg.SHEEP_SELF_BREED_SEC, _GobCfg.SHEEP_CALM_SEC])
	var s0 = lair.call("nearest_sheep", (lair as Node3D).global_position)
	if s0 != null and is_instance_valid(s0):
		var born0: int = int(lair.call("sheep_alive"))
		s0.set("_breed_t", 0.01)
		s0.set("_calm_t", _GobCfg.SHEEP_CALM_SEC + 1.0)
		await frames(4)
		verdict("F3 спокойная овца привела ещё одну",
			int(lair.call("sheep_alive")) >= born0 + 1 or int(s0.get("bred")) >= 1,
			"стадо %d → %d, порождено %d" % [born0, int(lair.call("sheep_alive")),
				int(s0.get("bred"))])
		# Удар сбрасывает покой: раненая овца не плодится
		s0.call("wound_flash")
		verdict("F4 удар сбрасывает покой (раненая овца не размножается)",
			float(s0.get("_calm_t")) <= 0.01 and float(s0.get("_breed_t")) > 0.0,
			"покой %.2f с, до приплода %.1f с" % [float(s0.get("_calm_t")),
				float(s0.get("_breed_t"))])
	_finish()
