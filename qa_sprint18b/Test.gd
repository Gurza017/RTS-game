extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СПРИНТ 18, ВТОРОЕ ПИСЬМО (headless)
## ═══════════════════════════════════════════════════════════════════════════
##   A — щелчки по зданиям (крепость — лук, бараки — рычаг, кузница — дверь,
##       прочие — сундук), марш на 20 % тише;
##   B — «Стена копий»: режим, три шеренги в «Защите», конница/тролль/бегущая
##       пехота о копья: 300 % урона, остановка, замедление −30 %; без режима
##       разгон работает как прежде;
##   C — VFX лечения: размер фиксирован (копейщик и лучник — одинаково), аура
##       0.8 м, цвет ярко-зелёный;
##   E — второе логово у красного ИИ, вспышка тролля мягкая, отара заново,
##       рейд за овцами (> 30: съесть 3, увести 5), ратуша неприкосновенна,
##       рудник ИИ/орды восстанавливается сам;
##   F — скалы: маска непроходимых склонов, обрыв плато непроходим, спуск —
##       проходим, приказ на скалу уводится, боец на скалу не заходит.
## Запуск: godot --headless --path . res://qa_sprint18b/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _SheepScript := preload("res://scripts/goblin/Sheep.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(420.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
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
	print("\n═════ ИТОГ qa_sprint18b: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _block(uid: String, fac: int, at: Vector3, cols: int, ranks: int, gap: float) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	for i in range(cols * ranks):
		var col: int = i % cols
		var rank: int = i / cols
		var p := at + Vector3((float(col) - float(cols - 1) * 0.5) * 0.6, 0.0, float(rank) * gap)
		var u := _spawn(uid, fac, p)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _kill(u) -> void:
	if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
		(u as Unit).take_damage(1e9)

func _kill_all(men: Array) -> void:
	for u in men:
		_kill(u)

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	if main._camera != null:
		main._camera.set_process(false)
	await pframes(4)

	print("\n═════ A. ЩЕЛЧКИ ПО ЗДАНИЯМ И МАРШ ═════")
	verdict("A1 крепость — «bow and arrow shot»", GameManager.pick_event_for("castle") == "pick_castle"
		and AudioManager.ui_path(String(AudioManager.UI_BANK["pick_castle"])).get_file() == "bow_and_arrow_shot.mp3")
	verdict("A2 бараки — «lever pull» (тот самый Lever_pull #4)", GameManager.pick_event_for("barracks") == "pick_barracks"
		and AudioManager.ui_path(String(AudioManager.UI_BANK["pick_barracks"])).get_file() == "lever_pull.mp3")
	verdict("A3 кузница — «Door Close»", GameManager.pick_event_for("smithy") == "pick_smithy"
		and AudioManager.ui_path(String(AudioManager.UI_BANK["pick_smithy"])).get_file() == "Door Close 1.wav")
	verdict("A4 дом и башня — общий «Chest Close»", GameManager.pick_event_for("house") == "pick_building"
		and GameManager.pick_event_for("tower") == "pick_building")
	var files_ok := true
	for ev in ["pick_castle", "pick_barracks", "pick_smithy", "pick_building"]:
		if not ResourceLoader.exists(AudioManager.ui_path(String(AudioManager.UI_BANK[ev]))):
			files_ok = false
	verdict("A5 файлы щелчков на месте", files_ok)
	AudioManager._ui_last.clear()
	verdict("A6 щелчок крепости реально запускается", AudioManager.play_ui("pick_castle"))
	verdict("A7 марш тише на 20 % (−16.0 / −14.1 дБ)",
		AudioManager.MARCH_WALK_DB <= -16.0 + 0.01 and AudioManager.MARCH_RUN_DB <= -14.1 + 0.01,
		"%.1f / %.1f" % [AudioManager.MARCH_WALK_DB, AudioManager.MARCH_RUN_DB])

	print("\n═════ B. СТЕНА КОПИЙ ═════")
	GameManager.world_bounds_enabled = false
	var node: Dictionary = _UCfg if false else {}
	verdict("B0 узел spearman_1d — «Стена копий», режим-переключатель",
		String((load("res://scripts/forge_config.gd").UNITS["spearman"]["1d"] as Dictionary)["name"]) == "Стена копий"
		and bool((load("res://scripts/forge_config.gd").UNITS["spearman"]["1d"] as Dictionary).get("toggle", false)))
	var p0 := Vector3(-1300.0, 0.0, -1300.0)
	# Без исследования: разгон конницы работает как прежде (стены нет)
	var blk0: Array = _block("spearman", Constants.FACTION_PLAYER, p0, 4, 3, 0.7)
	for u in blk0[1]:
		(u as Unit).set_stance("defense")
		(u as Unit)._facing = Vector3(0.0, 0.0, -1.0)
	await pframes(4)
	verdict("B1 без исследования стена не активна", not (blk0[1][0] as Unit).spear_wall_active())
	_kill_all(blk0[1])
	await pframes(3)
	GameManager.finish_research(Constants.FACTION_PLAYER, "spearman_1d")
	var blk: Array = _block("spearman", Constants.FACTION_PLAYER, p0, 4, 3, 0.7)
	var sid: int = blk[0]
	var men: Array = blk[1]
	verdict("B2 режим виден отряду и включён по умолчанию", GameManager.spear_wall_ready(sid))
	# ── «ЗАЩИТА» У СТОЯЩЕГО ОТРЯДА — БЕЗ ПЕРЕСТРОЕНИЯ (ТЗ 14.09.2026, п. 8) ──
	# Прежде стена копий по переходу в «Защиту» заново раскладывала три
	# шеренги и слала command_move каждому — «копейщики переступают ногами и
	# только потом опускают копья». Стоящий отряд теперь получает стойку на
	# месте: построений ноль, никто не тронулся; три шеренги — дело растяга
	# ПКМ (_block_formation_slots, спринт 20)
	var sm = main.selection_manager
	sm.select_units(men)
	var forms0: int = GameManager.spear_wall_forms
	sm.set_selection_stance("defense")
	await pframes(2)
	var moving := 0
	var in_def := 0
	for u in men:
		if (u as Unit).state == Unit.State.MOVING:
			moving += 1
		if (u as Unit).stance == "defense":
			in_def += 1
	verdict("B3 «Защита» у стоящего отряда — стойка у всех сразу, перестроения нет",
		GameManager.spear_wall_forms == forms0 and moving == 0 and in_def == men.size(),
		"построений %d, идут %d, в обороне %d из %d" % [GameManager.spear_wall_forms - forms0, moving, in_def, men.size()])
	# Растяг ПКМ у копейщиков со стеной ложится в три шеренги (спринт 20)
	var la := p0 + Vector3(-3.0, 0.0, 12.0)
	var lb := p0 + Vector3(3.0, 0.0, 12.0)
	var plan: Dictionary = sm._block_formation_slots(la, lb, men)
	var slots: Array = plan.get("slots", [])
	var rows_max := -1
	for r in plan.get("rows", []):
		rows_max = maxi(rows_max, int(r))
	verdict("B3б растяг ПКМ у стены копий — ТРИ шеренги (SPEAR_WALL_ROWS %d)" % GameManager.SPEAR_WALL_ROWS,
		slots.size() == men.size() and rows_max + 1 == GameManager.SPEAR_WALL_ROWS,
		"мест %d, шеренг %d" % [slots.size(), rows_max + 1])
	await pframes(60 * 4)
	for u in men:
		(u as Unit)._facing = Vector3(0.0, 0.0, -1.0)
	verdict("B4 копейщик в «Защите» отвечает: стена активна", (men[0] as Unit).spear_wall_active())
	# Конница с разгона
	var rng: float = _UCfg.stat("goblin_rider", "charge_range", 0.0)
	var pos0: Dictionary = {}
	for u in men:
		pos0[u] = (u as Unit).global_position
	var rider := _spawn("goblin_rider", Constants.FACTION_GOBLIN, p0 + Vector3(0.0, 0.0, -(rng + 12.0)))
	rider.current_health = rider.max_health * 100.0
	rider._soa_push_stats()
	await pframes(4)
	var hp_r0: float = rider.current_health
	var hits0: int = 0
	for u in men:
		hits0 += (u as Unit).spear_wall_hits
	rider.command_attack(men[1], true, true, true)
	var impacted := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if not is_instance_valid(rider) or rider.is_dead():
			break
		if not rider.is_charging and rider._charge_ready == false:
			impacted = true
			break
	await pframes(4)
	var hits1 := 0
	for u in men:
		hits1 += (u as Unit).spear_wall_hits
	verdict("B5 всадник налетел на стену — контакт засчитан копейщику", impacted and hits1 == hits0 + 1,
		"ударов стены %d" % (hits1 - hits0))
	var dead := 0
	var moved := 0
	for u in men:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			dead += 1
		elif (u as Unit).global_position.distance_to(pos0[u]) > 0.3:
			moved += 1
	verdict("B6 чардж погашен целиком: строй цел и не сдвинут", dead == 0 and moved == 0,
		"погибло %d, сдвинуто %d" % [dead, moved])
	var alive_r: bool = is_instance_valid(rider) and not rider.is_dead()
	var lost: float = hp_r0 - rider.current_health if alive_r else 0.0
	var arm: float = (rider.armor + rider.defense) if alive_r else 0.0
	var one_hit: float = _UCfg.damage_after_armor((men[0] as Unit).attack_damage, arm) if alive_r else 0.0
	# Обычный укол копий с разгона (charge_counter_frac от запаса всадника)
	# идёт ПОМИМО стены — вычитаем его и судим о добавке стены
	var back_dmg: float = _UCfg.damage_after_armor(rider.max_health * rider.charge_counter_frac, arm) if alive_r else 0.0
	var wall_dmg: float = lost - back_dmg
	verdict("B7 урон контакта стены — 300 %% удара копейщика (%.0f при обычном %.0f, укол копий %.0f отдельно)" % [wall_dmg, one_hit, back_dmg],
		alive_r and wall_dmg >= one_hit * 2.5 and wall_dmg <= one_hit * 3.6, "снято всего %.1f" % lost)
	verdict("B8 всадник остановлен: разгон и напор сняты", alive_r and rider._push_after_cap() == 0.0
		and not rider.is_charging and rider._counter_hit_until_ms > Unit.now_ms)
	var slow_ratio: float = 0.0
	if alive_r:
		var spd_slow: float = rider._effective_speed()
		rider._slow_until_ms = 0
		var spd_norm: float = rider._effective_speed()
		rider._slow_until_ms = Unit.now_ms + 5000
		slow_ratio = spd_slow / maxf(spd_norm, 0.001)
	verdict("B9 замедление −30 %% (скорость ×%.2f)" % slow_ratio, alive_r and rider.is_slowed()
		and absf(slow_ratio - 0.7) < 0.02)
	_kill(rider)
	await pframes(3)
	# Тролль с разгона — тоже остановлен (прежде копья тролля не держали)
	var troll: Unit = Building.PRELOAD_SCENES["troll"].instantiate()
	troll.faction = Constants.FACTION_GOBLIN
	main.world_add(troll)
	var tp := p0 + Vector3(0.0, 0.0, -30.0)
	troll.global_position = Vector3(tp.x, GameManager.get_terrain_height(tp.x, tp.z), tp.z)
	troll.sync_row()
	troll.post_pos = troll.global_position
	await pframes(4)
	var hits2: int = 0
	for u in men:
		hits2 += (u as Unit).spear_wall_hits
	troll.command_attack(men[1], true, true, true)
	var t_imp := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if not is_instance_valid(troll) or troll.is_dead():
			break
		if not troll.is_charging and troll._charge_ready == false and troll.global_position.distance_to(men[1].global_position) < 8.0:
			t_imp = true
			break
	await pframes(4)
	var hits3 := 0
	for u in men:
		hits3 += (u as Unit).spear_wall_hits
	var t_alive: bool = is_instance_valid(troll) and not troll.is_dead()
	verdict("B10 тролль с разгона о стену — остановлен и замедлен (топтания нет)",
		t_imp and hits3 == hits2 + 1 and t_alive and troll.is_slowed() and troll._push_after_cap() == 0.0,
		"контакт=%s, ударов стены %d, замедлен=%s" % [str(t_imp), hits3 - hits2, str(troll.is_slowed() if t_alive else false)])
	_kill(troll)
	await pframes(3)
	# Бегущая пехота (двойной ПКМ = бег) о стену
	var w := _spawn("warrior", Constants.FACTION_GOBLIN, p0 + Vector3(0.0, 0.0, -14.0))
	w.current_health = w.max_health * 100.0
	w._soa_push_stats()
	await pframes(2)
	var hits4 := 0
	for u in men:
		hits4 += (u as Unit).spear_wall_hits
	w.command_move(p0 + Vector3(0.0, 0.0, 6.0), false, Vector3.ZERO, false, true, true)
	var ran := false
	for _i in range(60 * 10):
		await get_tree().physics_frame
		if not is_instance_valid(w) or w.is_dead():
			break
		if w._wall_struck:
			ran = true
			break
	await pframes(3)
	var hits5 := 0
	for u in men:
		hits5 += (u as Unit).spear_wall_hits
	verdict("B11 бегущий пехотинец налетел на стену — остановлен и замедлен",
		ran and hits5 == hits4 + 1 and is_instance_valid(w) and not w.is_dead() and not w.sprinting and w.is_slowed(),
		"контакт=%s, ударов %d, бег=%s" % [str(ran), hits5 - hits4, str(w.sprinting if is_instance_valid(w) else false)])
	_kill(w)
	verdict("B12 прежней контратаки («Плотный строй») в коде нет",
		not (men[0] as Unit).has_method("_counter_charge_ready"))
	_kill_all(men)
	await pframes(3)

	print("\n═════ C. VFX ЛЕЧЕНИЯ: ФИКСИРОВАННЫЙ, ТОНКИЙ, ЗЕЛЁНЫЙ ═════")
	var pc := p0 + Vector3(80.0, 0.0, 0.0)
	var monk: Unit = _spawn("monk", Constants.FACTION_PLAYER, pc)
	var hurt_s: Unit = _spawn("spearman", Constants.FACTION_PLAYER, pc + Vector3(1.5, 0.0, 0.0))
	await pframes(3)
	hurt_s.current_health = hurt_s.max_health * 0.3
	hurt_s._soa_push_stats()
	await pframes(60 * 2)
	var vfx_s: Node = monk.heal_vfx_target()
	var q_s: QuadMesh = (monk._heal_vfx.mesh as QuadMesh) if monk._heal_vfx != null else null
	var qa_s: QuadMesh = (monk._heal_aura.mesh as QuadMesh) if monk._heal_aura != null else null
	# Овал на земле вырезан ТЗ 19.09.2026 (п. 1): его отсутствие — свойство
	verdict("C1 на копейщике: эффект есть, квад %.2f м (фикс. %.2f), овала на земле нет" % [
		q_s.size.y if q_s != null else -1.0, monk.HEAL_VFX_SIZE_M],
		vfx_s == hurt_s and q_s != null and is_equal_approx(q_s.size.y, monk.HEAL_VFX_SIZE_M)
		and qa_s == null)
	hurt_s.current_health = hurt_s.max_health
	hurt_s._soa_push_stats()
	var hurt_a: Unit = _spawn("archer", Constants.FACTION_PLAYER, pc + Vector3(-1.5, 0.0, 0.0))
	await pframes(3)
	hurt_a.current_health = hurt_a.max_health * 0.3
	hurt_a._soa_push_stats()
	await pframes(60 * 2)
	var q_a: QuadMesh = (monk._heal_vfx.mesh as QuadMesh) if monk._heal_vfx != null else null
	verdict("C2 на лучнике — тот же размер (не зависит от роста цели)",
		monk.heal_vfx_target() == hurt_a and q_a != null and is_equal_approx(q_a.size.y, monk.HEAL_VFX_SIZE_M))
	# СПРИНТ 19 (письмо 12): аура КРУПНЕЕ (1.4 м) и с флуоресцентным свечением
	# — прежние «0.8 м и тонко» развёрнуты владельцем; цвет по-прежнему
	# ярко-зелёный (G = 1, R и B малы)
	# СПРИНТ 20 (модуль 1): аура — малый ОВАЛ под ногами (1.0 м шириной,
	# AURA_OVAL_K ниже), без креста и заливки; цвет по-прежнему ярко-зелёный
	verdict("C3 аура — овал %.1f м, ниже ширины (k=%.2f) и ярко-зелёная" % [monk.AURA_DIAM_M, monk.AURA_OVAL_K],
		monk.AURA_DIAM_M >= 0.9 and monk.AURA_OVAL_K < 0.7
		and monk.AURA_COLOR.g >= 0.99 and monk.AURA_COLOR.r < 0.35 and monk.AURA_COLOR.b < 0.45)
	# Тонкость: доля закрашенных пикселей кадра ауры мала
	var tex: Texture2D = monk._aura_texture()
	var img: Image = tex.get_image()
	var painted := 0
	for y in range(monk.AURA_PX):
		for x in range(monk.AURA_PX):
			if img.get_pixel(x, y).a > 0.5:
				painted += 1
	var frac: float = float(painted) / float(monk.AURA_PX * monk.AURA_PX)
	# Свечение внутри кольца — дизером (каждый второй/четвёртый пиксель):
	# закрашено больше прежних 12 %, но меньше сплошной заливки диска
	# Только тонкий контур: закрашено меньше прежних 12 %, центр прозрачен
	var cpx: int = monk.AURA_PX / 2
	# 14.09.2026: контур — круг (квад плашмя), пикселей у круга больше, чем
	# у сжатого овала: потолок 25 % кадра, центр по-прежнему прозрачен
	verdict("C4 только контур, без креста и заливки (закрашено %.1f %% кадра: 2…25 %%)" % (frac * 100.0),
		frac >= 0.02 and frac < 0.25 and img.get_pixel(cpx, cpx).a < 0.5)
	_kill(monk); _kill(hurt_s); _kill(hurt_a)
	await pframes(3)

	print("\n═════ E. ЛОГОВА, ТРОЛЛЬ, ОВЦЫ, РУДНИКИ ═════")
	var lairs: Array = GameManager.troll_lairs
	verdict("E1 логов два", lairs.size() == 2, "%d" % lairs.size())
	if lairs.size() == 2:
		var l1: Node3D = lairs[0]
		var l2: Node3D = lairs[1]
		var ea: Vector3 = main.ENEMY_BASE_ANCHOR
		# ТЗ 14.09.2026, п. 3: обе базы людей на левом берегу (x < 0);
		# «красный пень» (второй) — строго посередине между ними по Z,
		# напротив брода; первый — на правом берегу (земля орды)
		var pa: Vector3 = main.PLAYER_BASE_ANCHOR
		var mid_z: float = (pa.z + ea.z) * 0.5
		verdict("E2 первое — на берегу орды (x>0), второе — между базами напротив брода (x<0, z у середины)",
			l1.global_position.x > 0.0 and l2.global_position.x < 0.0
			and absf(l2.global_position.z - mid_z) < 5.0 and absf(l2.global_position.z - main.FORD_Z) < 8.0,
			"1: (%.0f, %.0f), 2: (%.0f, %.0f)" % [l1.global_position.x, l1.global_position.z, l2.global_position.x, l2.global_position.z])
		verdict("E3 у обоих есть тролли и овцы", int(l1.call("trolls_alive")) > 0 and int(l2.call("trolls_alive")) > 0
			and int(l1.call("sheep_alive")) > 0 and int(l2.call("sheep_alive")) > 0,
			"тролли %d/%d, овцы %d/%d" % [int(l1.call("trolls_alive")), int(l2.call("trolls_alive")), int(l1.call("sheep_alive")), int(l2.call("sheep_alive"))])
		verdict("E4 GameManager.troll_lair — первое (у игрока)", GameManager.troll_lair == l1)
		# Вспышка мягкая
		var tr0: Unit = (l2.get("trolls") as Array)[0]
		verdict("E5 вспышка урона тролля едва заметна (пик ≤ 0.1)", tr0.hit_flash_peak() <= 0.1, "%.2f" % tr0.hit_flash_peak())
		# Отара заново: съедаем всё стадо второго логова
		for sh in (l2.get("sheep") as Array).duplicate():
			if sh != null and is_instance_valid(sh):
				sh.call("eat")
		await pframes(3)
		var left: float = float(l2.call("flock_respawn_left"))
		verdict("E6 стадо вырезано — взведён таймер новой отары (%.0f с)" % left, int(l2.call("sheep_alive")) == 0 and left > 0.0)
		l2.call("_on_flock_respawn")
		await pframes(2)
		verdict("E7 новая отара из пяти", int(l2.call("sheep_alive")) == _GobCfg.SHEEP_RESPAWN_COUNT
			and int(l2.get("flocks_respawned")) == 1, "овец %d" % int(l2.call("sheep_alive")))
		# Ратуша неприкосновенна
		var castle := Castle.new()
		castle.faction = Constants.FACTION_PLAYER
		main.world_add(castle)
		castle.global_position = tr0.global_position + Vector3(8.0, 0.0, 0.0)
		await pframes(2)
		tr0.set_attack_target(null)
		tr0.command_move(tr0.global_position)
		await pframes(2)
		tr0.command_attack(castle, true)
		verdict("E8 тролль не берёт крепость целью", tr0.attack_target == null)
		# Рейд: у игрока 31 овца у «загона» рядом с троллем
		var keep := Node3D.new()
		main.world_add(keep)
		var kp: Vector3 = tr0.global_position + Vector3(0.0, 0.0, 30.0)
		keep.global_position = kp
		var flock: Array = []
		for i in range(_GobCfg.TROLL_RAID_SHEEP + 1):
			var s: Node3D = _SheepScript.new()
			main.world_add(s)
			var sp := kp + Vector3(float(i % 8) * 1.2, 0.0, float(i / 8) * 1.2)
			s.global_position = Vector3(sp.x, GameManager.get_terrain_height(sp.x, sp.z), sp.z)
			s.call("bind_to_keep", keep, Constants.FACTION_PLAYER)
			flock.append(s)
		await pframes(2)
		verdict("E9 у игрока > 30 овец", GameManager.faction_sheep_count(Constants.FACTION_PLAYER) > _GobCfg.TROLL_RAID_SHEEP,
			"%d" % GameManager.faction_sheep_count(Constants.FACTION_PLAYER))
		tr0.command_move(tr0.global_position)
		tr0._raid_check_t = 0.0
		tr0._raid_cool_t = 0.0
		var phase_seen: Dictionary = {}
		var done := false
		for _i in range(60 * 120):
			await get_tree().physics_frame
			var ph: String = tr0.raid_phase()
			if ph != "":
				phase_seen[ph] = true
			if tr0.raids_done >= 1:
				done = true
				break
		verdict("E10 тролль вышел в рейд: шёл к стаду, ел, повёл домой", phase_seen.has("go") and phase_seen.has("home"),
			str(phase_seen.keys()))
		verdict("E11 съел три", tr0.raid_eaten == _GobCfg.TROLL_RAID_EAT, "%d" % tr0.raid_eaten)
		verdict("E12 увёл пять", tr0.raid_herded == _GobCfg.TROLL_RAID_HERD, "%d" % tr0.raid_herded)
		var adopted := 0
		for sh2 in flock:
			if sh2 != null and is_instance_valid(sh2) and sh2.get("lair") == l2:
				adopted += 1
		verdict("E13 рейд завершён у пня, уведённые овцы стали его стадом", done and adopted == _GobCfg.TROLL_RAID_HERD,
			"готово=%s, у пня %d" % [str(done), adopted])
		verdict("E13б удачный рейд — пень выпустил ещё %d троллей" % _GobCfg.TROLL_RAID_REWARD,
			int(l2.get("raid_rewards")) == 1 and int(l2.call("trolls_alive")) >= 1 + _GobCfg.TROLL_RAID_REWARD,
			"троллей %d" % int(l2.call("trolls_alive")))
		# ── ДАВЛЕНИЕ ОВЕЦ: пень игрока без троллей → тролль-вор; снесённый пень
		# восстанавливается (стадо игрока по-прежнему > 30: уведено 5, съедено 3
		# из 31 — добавим ещё)
		for i in range(10):
			var s2: Node3D = _SheepScript.new()
			main.world_add(s2)
			var sp2 := kp + Vector3(float(i) * 1.2, 0.0, -3.0)
			s2.global_position = Vector3(sp2.x, GameManager.get_terrain_height(sp2.x, sp2.z), sp2.z)
			s2.call("bind_to_keep", keep, Constants.FACTION_PLAYER)
			flock.append(s2)
		l1.set("aggro_enabled", false)   # иначе гибель стражи зовёт бонусную пару
		for t in (l1.get("trolls") as Array).duplicate():
			_kill(t)
		await pframes(3)
		var spawned0: int = GameManager.raid_trolls_spawned
		GameManager._sheep_pressure_check()
		await pframes(2)
		verdict("E17 у игрока 30+ овец, троллей в его пне нет — вышел тролль-вор",
			GameManager.raid_trolls_spawned == spawned0 + 1 and int(l1.call("trolls_alive")) == _GobCfg.TROLL_RAID_SPAWN,
			"троллей у пня игрока %d" % int(l1.call("trolls_alive")))
		for t2 in (l1.get("trolls") as Array).duplicate():
			_kill(t2)
		(l1 as Building).take_damage(1e9)
		await pframes(3)
		var restores0: int = GameManager.lair_restores
		# СПРИНТ 20: сразу после сноса пень не восстанавливается — таймаут
		# LAIR_REGEN_SEC; часы партии переводим вперёд
		GameManager._sheep_pressure_check()
		await pframes(2)
		verdict("E17б сразу после сноса пень НЕ восстановлен (таймаут %.0f с, отказов %d)" % [_GobCfg.LAIR_REGEN_SEC, GameManager.lair_regen_refusals],
			GameManager.lair_restores == restores0 and GameManager.lair_regen_refusals >= 1)
		main.set_game_clock(main.game_clock() + _GobCfg.LAIR_REGEN_SEC + 1.0)
		GameManager._sheep_pressure_check()
		await pframes(4)
		var nl: Node = GameManager.lair_for(Constants.FACTION_PLAYER)
		verdict("E18 снесённый пень при 30+ овцах восстановлен и выпустил вора",
			GameManager.lair_restores == restores0 + 1 and nl != null and nl != l1
			and int(nl.call("trolls_alive")) == _GobCfg.TROLL_RAID_SPAWN and GameManager.troll_lair == nl,
			"восстановлений %d" % GameManager.lair_restores)
		for sh3 in flock:
			if sh3 != null and is_instance_valid(sh3):
				sh3.call("eat")
		castle.queue_free()
		keep.queue_free()
	# Рудник орды восстанавливается сам
	var gm: Node = GameManager.goblin_mine
	if gm != null and is_instance_valid(gm):
		var at: Vector3 = (gm as Node3D).global_position
		var pend0: int = GameManager.mine_restore_pending
		var rs0: int = GameManager.mine_restores
		(gm as Building).take_damage(1e9)
		await pframes(3)
		verdict("E14 снос рудника орды взводит восстановление (60 с)", GameManager.mine_restore_pending == pend0 + 1
			and (not is_instance_valid(gm) or (gm as Building).is_dead()) and is_equal_approx(Mine.MINE_RESTORE_SEC, 60.0))
		GameManager._restore_mine_at(at, Constants.FACTION_GOBLIN)
		await pframes(2)
		var back: Node = null
		for b in get_tree().get_nodes_in_group("goblin_buildings"):
			if b is Mine and (b as Node3D).global_position.distance_to(at) < 2.0 and not (b as Building).is_dead():
				back = b
		verdict("E15 по таймеру руина снова рудник орды", back != null and GameManager.mine_restores == rs0 + 1
			and int((back as Building).faction) == Constants.FACTION_GOBLIN)
		var ruins_left := 0
		for r in get_tree().get_nodes_in_group("ruins"):
			if is_instance_valid(r) and String(r.get_meta("ruin_building_id", "")) == "mine" and (r as Node3D).global_position.distance_to(at) < 2.0:
				ruins_left += 1
		verdict("E16 руина снята", ruins_left == 0)

	print("\n═════ F. СКАЛЫ ═════")
	GameManager.world_bounds_enabled = true
	verdict("F1 маска скал построена (ячеек %d)" % GameManager.cliff_cells, GameManager.cliff_cells > 0)
	var plats: Array = main.plateau_list()
	if not plats.is_empty():
		var pl: Array = plats[0]
		var cx: float = float(pl[0]); var cz: float = float(pl[1]); var rf: float = float(pl[2]); var ang: float = float(pl[4])
		var back_dir := Vector3(-cos(ang), 0.0, -sin(ang))
		var ramp_dir := Vector3(cos(ang), 0.0, sin(ang))
		var wall_p: Vector3 = Vector3(cx, 0.0, cz) + back_dir * (rf + main.PLATEAU_RAMP_STEEP * 0.5)
		var ramp_p: Vector3 = Vector3(cx, 0.0, cz) + ramp_dir * (rf + main.PLATEAU_RAMP_GENTLE * 0.5)
		var top_p := Vector3(cx, 0.0, cz)
		verdict("F2 обрыв плато — скала", GameManager.is_cliff(wall_p.x, wall_p.z), "(%.0f, %.0f)" % [wall_p.x, wall_p.z])
		verdict("F3 пологий спуск и вершина — проходимы", not GameManager.is_cliff(ramp_p.x, ramp_p.z)
			and not GameManager.is_cliff(top_p.x, top_p.z))
		var lt: Vector3 = GameManager.land_target(wall_p)
		verdict("F4 приказ на скалу уводится на проходимую точку", not GameManager.is_cliff(lt.x, lt.z)
			and _xz(lt, wall_p) < GameManager.CLIFF_SEARCH_R + 0.1, "сдвиг %.1f м" % _xz(lt, wall_p))
		# Боец, посланный сквозь обрыв, на скалу не заходит
		var start: Vector3 = Vector3(cx, 0.0, cz) + back_dir * (rf + main.PLATEAU_RAMP_STEEP + 8.0)
		var u2 := _spawn("spearman", Constants.FACTION_PLAYER, start)
		await pframes(2)
		u2.command_move(top_p, false, Vector3.ZERO, false, true)
		var on_cliff := 0
		for _i in range(60 * 8):
			await get_tree().physics_frame
			if GameManager.is_cliff(u2.global_position.x, u2.global_position.z):
				on_cliff += 1
		verdict("F5 боец у обрыва скользит вдоль него, на скалу не заходит (кадров на скале %d)" % on_cliff, on_cliff == 0)
		_kill(u2)
		# Отряд НА ВЕРШИНЕ, посланный сквозь обрыв: обходит кольцо вдоль стены
		# до спуска и выходит (без поиска пути — «следование стене» с памятью
		# стороны, см. ArmyCore.BatchMoveRows)
		var top_sq: Array = _block("spearman", Constants.FACTION_PLAYER, top_p + back_dir * (rf - 4.0), 4, 3, 0.8)
		await pframes(3)
		var far_goal: Vector3 = Vector3(cx, 0.0, cz) + back_dir * (rf + main.PLATEAU_RAMP_STEEP + 25.0)
		for u3 in top_sq[1]:
			(u3 as Unit).command_move(GameManager.land_target(far_goal), false, Vector3.ZERO, false, true)
		var out_n := 0
		var stuck_frames := 0
		for _i in range(60 * 150):
			await get_tree().physics_frame
			if _i % 60 == 0:
				out_n = 0
				for u4 in top_sq[1]:
					var rr: float = _xz((u4 as Unit).global_position, Vector3(cx, 0.0, cz))
					if rr > rf + main.PLATEAU_RAMP_STEEP + 1.0:
						out_n += 1
					if GameManager.is_cliff((u4 as Unit).global_position.x, (u4 as Unit).global_position.z):
						stuck_frames += 1
				if out_n == top_sq[1].size():
					break
		verdict("F6 отряд с вершины обходит кольцо по стене и выходит через спуск (вышло %d из %d)" % [out_n, top_sq[1].size()],
			out_n >= top_sq[1].size() - 1 and stuck_frames == 0, "замеров на скале %d" % stuck_frames)
		_kill_all(top_sq[1])
	GameManager.world_bounds_enabled = false
	_finish()
