extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТРОЛЛЬ, ЛОГОВО, МЕСТЬ ГОБЛИНОВ (09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ЛОГОВО — дерево стоит за горой ниже замка, вокруг колья и кости,
##     стартовый страж на месте, площадка расчищена от леса.
##   B ТРОЛЛЬ — запас = 180 копейщиков, ленты подключены, размер ~×4,
##     таран настроен, серия ударов → одышка (стоит, не бьёт) → снова бьёт,
##     брызги дубины по соседям.
##   C ПОЛОВИНА ЗАПАСА — из дерева выходят ещё два тролля.
##   D СМЕРТЬ — нападавшему отряду засчитано 180 убийств.
##   E МЕСТЬ — по зачистке логова вожак выпускает 10 отрядов с ролью
##     «месть» и целью у дерева; повтор не раньше интервала.
##
## Числа — из конфигов (правило 10), ожидание физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_troll/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Troll  := preload("res://scripts/goblin/Troll.gd")

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
	print("\n═════ ИТОГ qa_troll: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn_squad(kind: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var men: Array = []
	var scene: PackedScene = Building.PRELOAD_SCENES[kind]
	for i in range(n):
		var u: Unit = scene.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var px: float = at.x + float(i % 6) * 0.7 - 2.1
		var pz: float = at.z + float(i / 6) * 0.7
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	await _check_lair()
	await _check_troll()
	await _check_revenge()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _check_lair() -> void:
	print("\n═════ A. ЛОГОВО ═════")
	var lair = GameManager.troll_lair
	verdict("A1 логово заведено партией", lair != null and is_instance_valid(lair))
	if lair == null:
		return
	var lp: Vector3 = (lair as Node3D).global_position
	var castle: Vector3 = main.PLAYER_BASE_ANCHOR
	print("  логово в %s, якорь игрока %s" % [str(lp), str(castle)])
	# ТЗ 14.09.2026, п. 3: первый пень — на правом берегу (земля орды),
	# на суше, за бродом от обеих баз людей
	verdict("A2 логово на правом берегу (x > 0), на суше",
		lp.x > 0.0 and not GameManager.is_water(lp.x, lp.z),
		"dz=%.0f, x=%.0f" % [lp.z - castle.z, lp.x])
	var spikes := 0
	var bones := 0
	var sprite := false
	for c in (lair as Node).get_children():
		var nm: String = (c as Node).name
		# Одноимённые дети получают суффиксы (Spike2…): считаем по префиксу
		if nm.begins_with("Spike"): spikes += 1
		elif nm.begins_with("Bones"): bones += 1
		elif nm == "BuildingSprite": sprite = true
	verdict("A3 дерево с картинкой, вокруг колья и кости", sprite
		and spikes == _GobCfg.LAIR_SPIKES and bones == _GobCfg.LAIR_BONES,
		"картинка=%s, кольев %d/%d, костей %d/%d" % [str(sprite), spikes,
			_GobCfg.LAIR_SPIKES, bones, _GobCfg.LAIR_BONES])
	verdict("A4 у дерева стоит стартовый страж", GameManager.trolls_alive() == _GobCfg.LAIR_START_TROLLS,
		"троллей %d" % GameManager.trolls_alive())
	var trees := 0
	for rn in get_tree().get_nodes_in_group("resource_nodes"):
		# Спринт 20: глушь вокруг пня — рощицы с LAIR_GLADE_TREES_R; чистой
		# обязана быть только площадка внутри кольца декора
		if is_instance_valid(rn) and (rn as Node3D).global_position.distance_to(lp) < _GobCfg.LAIR_GLADE_R1 - 1.0:
			trees += 1
	verdict("A5 площадка логова расчищена от леса и руды (внутри %.0f м)" % (_GobCfg.LAIR_GLADE_R1 - 1.0),
		trees == 0, "узлов ресурсов рядом %d" % trees)

# ═════════════════════════════════════════════════════════════════════════════
func _check_troll() -> void:
	print("\n═════ B-D. ТРОЛЛЬ ═════")
	var lair = GameManager.troll_lair
	if lair == null:
		verdict("B0 логова нет", false)
		return
	var lp: Vector3 = (lair as Node3D).global_position
	var troll: Unit = null
	for t in lair.trolls:
		if is_instance_valid(t):
			troll = t
			break
	if troll == null:
		verdict("B0 тролля нет", false)
		return
	# 10.09.2026: запас −30 % от «180 копейщиков» — цена смерти (TROLL_KILL_WORTH)
	# осталась 180, а запас читается из конфига (правило 10)
	var want_hp: float = _UCfg.stat("troll", "health")
	verdict("B1 запас тролля = конфигу и ниже 180 копейщиков (−30 %)",
		is_equal_approx(troll.max_health, want_hp)
			and want_hp < _UCfg.stat("spearman", "health") * 180.0 * 0.75,
		"%.0f при конфиге %.0f" % [troll.max_health, want_hp])
	var anims: Array = []
	for a in ["idle", "walk", "attack", "windup", "recovery", "death"]:
		if troll._has_anim(a):
			anims.append(a)
	verdict("B2 ленты подключены: покой, ходьба, атака, замах, одышка, гибель",
		anims.size() == 6, str(anims))
	var asp := troll._active_sprite as AnimatedSprite3D
	var px: float = asp.pixel_size if asp != null else 0.0
	# СПРИНТ 15: спрайт тролля уменьшен на 15 % (заказ); эталон — TROLL_SIZE_SCALE
	# из конфига, а не число в стенде (правило 10)
	var want_k: float = _GobCfg.TROLL_SIZE_SCALE
	verdict("B3 размер ~×%.1f копейщика (TROLL_SIZE_SCALE)" % want_k,
		px >= _GobCfg.TROLL_PIXEL_SIZE * 0.99
		and _GobCfg.TROLL_PIXEL_SIZE * 211.0 >= 0.0108 * 150.0 * (want_k - 0.5)
		and _GobCfg.TROLL_PIXEL_SIZE * 211.0 <= 0.0108 * 150.0 * (want_k + 0.5),
		"пиксель %.4f, рост %.1f м против %.1f у копейщика" % [px,
			_GobCfg.TROLL_PIXEL_SIZE * 211.0, 0.0108 * 150.0])
	verdict("B4 таран настроен (charge_range, брызги, откидывание)",
		troll.charge_range > 0.0 and troll.charge_splash > 0.0 and troll.charge_knockback > 0.0,
		"range %.0f, splash %.1f, knockback %.1f" % [troll.charge_range, troll.charge_splash, troll.charge_knockback])
	verdict("B4б тролль вне реестра вожака орды", not _in_horde(troll))

	# ── Серия ударов и одышка: ставим копейщиков вплотную ──────────────────
	var sp := _spawn_squad("spearman", lp + Vector3(0.0, 0.0, 24.0), 24)
	var sid: int = int(sp[0])
	for m in sp[1]:
		(m as Unit).set_stance("defense")
	# Тролль сам по себе патрулирует; ведём его к строю приказом.
	# Агро-вызов логова на время серии ВЫКЛЮЧЕН: блок меряет ОДНОГО тролля
	# (три тролля вырезали бы 24 копейщика до одышки), включается перед C
	lair.set("aggro_enabled", false)
	troll.command_attack(sp[1][0], true, false)
	var swings := 0
	var winded_seen := false
	var winded_frames := 0
	var moved_while_winded := 0.0
	var last_pos: Vector3 = troll.global_position
	var struck_after_rest := false
	var hp0: float = 0.0
	for m in sp[1]:
		hp0 += (m as Unit).current_health
	var guard := 0
	while guard < 60 * 40:
		await get_tree().physics_frame
		guard += 1
		if troll.is_dead():
			break
		if troll.is_winded():
			if not winded_seen:
				winded_seen = true
				last_pos = troll.global_position
			winded_frames += 1
			moved_while_winded = maxf(moved_while_winded,
				troll.global_position.distance_to(last_pos))
		elif winded_seen and troll._swings > 0:
			struck_after_rest = true
			break
		swings = maxi(swings, troll._swings)
		if guard % 300 == 0:
			var alive := 0
			for m in sp[1]:
				if is_instance_valid(m) and not (m as Unit).is_dead():
					alive += 1
			if alive == 0:
				break
	var hp1: float = 0.0
	var alive2 := 0
	for m in sp[1]:
		if is_instance_valid(m) and not (m as Unit).is_dead():
			hp1 += (m as Unit).current_health
			alive2 += 1
	print("  ударов до одышки %d (конфиг %d), одышка %s кадров, сдвиг в одышке %.2f м, снова бьёт=%s; копейщиков живо %d, запас %.0f→%.0f"
		% [swings, _GobCfg.TROLL_SWINGS, winded_frames, moved_while_winded, str(struck_after_rest), alive2, hp0, hp1])
	verdict("B5 после серии ударов тролль уходит в одышку", winded_seen,
		"замечено=%s, ударов %d" % [str(winded_seen), swings])
	verdict("B6 в одышке стоит на месте и не бьёт, потом снова бьёт",
		winded_seen and moved_while_winded < 0.5 and struck_after_rest
			and winded_frames >= int(_GobCfg.TROLL_REST_SEC * 60.0 * 0.8),
		"сдвиг %.2f м, кадров одышки %d, снова бьёт=%s" % [moved_while_winded, winded_frames, str(struck_after_rest)])
	verdict("B7 дубина бьёт брызгами: пострадали больше одного", _hurt_count(sp[1]) > 1,
		"раненых/павших %d" % _hurt_count(sp[1]))
	# Вспышка попадания: стандартный путь take_damage → _push_damage_shade
	# Обидчик — ЖИВОЙ боец отряда (правило 5: sp[1][0] к этому кадру мог пасть)
	troll.take_damage(10.0, _alive_of(sp[1]))
	verdict("B8 вспышка попадания взводится стандартным путём", troll._hit_flash > 0.0,
		"flash=%.3f" % troll._hit_flash)

	# ── C. Агро-вызов (10.09.2026): первый удар по стражу при включённом
	# агро — из дерева СРАЗУ выбегают TROLL_AGGRO_HELPERS; повторный удар
	# никого не добавляет. Помощников замораживаем: они только считаются,
	# а отряд копейщиков нужен живым для зачёта убийств (D1)
	lair.set("aggro_enabled", true)
	troll.take_damage(10.0, _alive_of(sp[1]))
	await pframes(2)
	for t in lair.trolls:
		if is_instance_valid(t) and t != troll and not (t as Unit).is_dead():
			(t as Unit).set_tick(false)
	var after: int = GameManager.trolls_alive()
	verdict("C1 после первого удара по стражу из дерева вышли ещё %d тролля" % _GobCfg.TROLL_AGGRO_HELPERS,
		after == _GobCfg.LAIR_START_TROLLS + _GobCfg.TROLL_AGGRO_HELPERS and int(lair.get("aggro_wave")) == 1,
		"троллей %d, волна %d" % [after, int(lair.get("aggro_wave"))])
	troll.current_health = troll.max_health * (_GobCfg.TROLL_REINFORCE_AT + 0.02)
	troll.take_damage(troll.max_health * 0.1, _alive_of(sp[1]))
	await pframes(2)
	verdict("C2 помощники выходят один раз, порог трети запаса у первой группы не действует",
		GameManager.trolls_alive() == after, "троллей %d" % GameManager.trolls_alive())

	# ── D. Смерть: 180 убийств отряду ──────────────────────────────────────
	var kills0: int = GameManager.squad_kills(sid)
	# Урон с этого отряда — почти весь; сносим остаток
	troll.take_damage(1.0e9, _alive_of(sp[1]))
	await pframes(2)
	var kills1: int = GameManager.squad_kills(sid)
	verdict("D1 за смерть тролля отряду засчитано %d убийств" % _GobCfg.TROLL_KILL_WORTH,
		kills1 - kills0 == _GobCfg.TROLL_KILL_WORTH,
		"было %d, стало %d" % [kills0, kills1])
	verdict("D2 отряд поднялся в ранге", GameManager.squad_level(sid) > 0,
		"уровень %d" % GameManager.squad_level(sid))
	# Добиваем остальных троллей — для блока E. Выбитая группа поднимает
	# бонусную пару (агро-цепочка, 10.09.2026), её добиваем вторым кругом
	var rounds := 0
	while rounds < 4 and GameManager.trolls_alive() > 0:
		rounds += 1
		for t in lair.trolls.duplicate():
			if is_instance_valid(t) and not (t as Unit).is_dead():
				(t as Unit).take_damage(1.0e9, _alive_of(sp[1]))
		await pframes(2)
	verdict("D3 логово зачищено (после бонусной пары, кругов %d)" % rounds, GameManager.troll_lair_cleared(),
		"троллей %d" % GameManager.trolls_alive())
	for m in sp[1]:
		if is_instance_valid(m):
			(m as Unit).take_damage(1.0e9)
	await pframes(2)

func _hurt_count(men: Array) -> int:
	var n := 0
	for m in men:
		if not is_instance_valid(m) or (m as Unit).is_dead():
			n += 1
		elif (m as Unit).current_health < (m as Unit).max_health - 0.01:
			n += 1
	return n

func _in_horde(u: Unit) -> bool:
	var ai = main.goblin_ai
	if ai == null:
		return false
	ai._regroup()
	for s in ai.squads:
		for m in (s as Dictionary)["members"]:
			if m == u:
				return true
	return false

# ═════════════════════════════════════════════════════════════════════════════
func _alive_of(men: Array) -> Unit:
	for m in men:
		if is_instance_valid(m) and not (m as Unit).is_dead():
			return m
	return null

func _check_revenge() -> void:
	print("\n═════ E. МЕСТЬ ГОБЛИНОВ ═════")
	var ai = main.goblin_ai
	if ai == null:
		verdict("E0 вожака орды нет", false)
		return
	var lair = GameManager.troll_lair
	var lp: Vector3 = (lair as Node3D).global_position
	var before: int = get_tree().get_nodes_in_group("goblin_units").size()
	ai.clock = _GobCfg.REVENGE_INTERVAL_SEC * 2.0
	ai.tick()
	await pframes(3)
	var after: int = get_tree().get_nodes_in_group("goblin_units").size()
	var per: int = int(_GobCfg.SQUAD_SIZE.get(_GobCfg.REVENGE_UNIT, 20))
	verdict("E1 по зачистке вышли %d отрядов пехоты" % _GobCfg.REVENGE_SQUADS,
		ai.revenge_waves == 1 and after - before == _GobCfg.REVENGE_SQUADS * per,
		"волн %d, гоблинов +%d (ожидалось %d)" % [ai.revenge_waves, after - before,
			_GobCfg.REVENGE_SQUADS * per])
	ai.tick()
	await pframes(2)
	var rev := 0
	var toward := 0
	for s in ai.squads:
		var sq: Dictionary = s
		if String(sq["role"]) == ai.ROLE_REVENGE:
			rev += 1
			var tgt: Vector3 = sq["target"]
			if tgt.distance_to(lp) <= _GobCfg.REVENGE_RING + 1.0:
				toward += 1
	verdict("E2 роль «месть», цели на кольце вокруг дерева", rev == _GobCfg.REVENGE_SQUADS
		and toward == rev, "отрядов мести %d, у дерева %d" % [rev, toward])
	# Идут: через несколько секунд центр ближе к дереву, чем был
	var d0: float = _revenge_dist(ai, lp)
	await pframes(60 * 6)
	var d1: float = _revenge_dist(ai, lp)
	verdict("E3 отряды мести маршируют к дереву", d1 < d0 - 5.0,
		"средняя дистанция %.0f → %.0f м" % [d0, d1])
	ai.clock += 10.0
	ai.tick()
	verdict("E4 повтор не раньше интервала (%d с)" % int(_GobCfg.REVENGE_INTERVAL_SEC),
		ai.revenge_waves == 1, "волн %d" % ai.revenge_waves)
	ai.clock += _GobCfg.REVENGE_INTERVAL_SEC
	ai.tick()
	verdict("E5 через интервал — следующая волна", ai.revenge_waves == 2, "волн %d" % ai.revenge_waves)

func _revenge_dist(ai, lp: Vector3) -> float:
	var sum := 0.0
	var n := 0
	for s in ai.squads:
		var sq: Dictionary = s
		if String(sq["role"]) != ai.ROLE_REVENGE:
			continue
		sum += ai._squad_center(sq).distance_to(lp)
		n += 1
	return sum / float(maxi(n, 1))
