extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_fix_pack — ПАКЕТ ПРАВОК 13.09.2026 (карта, тролли, туши, монахи,
## стрелки, строй, кузница, панель)
## ═══════════════════════════════════════════════════════════════════════════
##   A  КАРТА     — рудника на броде нет, ничейные рудники только на плато
##   B  ТУШИ      — −20 % размера, запас вдвое, стрела бьёт, тонкий обвод и
##                  красная вспышка; упёрлись в копейщиков — бьют копейщиков
##   C  МОНАХ     — поднимает павших, погибших ДО изучения узла, и не ждёт,
##                  пока рядом не останется раненых
##   D  ПАНЕЛЬ    — три иконки найма Крепости строго квадратные, ряд
##                  отцентрован, панель заданного размера
##   E  СТРОЙ     — свободная растяжка у всех по умолчанию, три ряда только у
##                  копейщиков со «Стеной копий»; [2] живёт один растяг
##   F  КУЗНИЦА   — ячейка D открывается своим рядом, стоит ресурсов, клик
##                  списывает и изучает; ряды дороже кверху
##   G  ТРОЛЛИ    — один страж на старте, +1 раз в 5 минут до двух, волна
##                  защиты 3 тролля по удару во второго стража, откат 10 минут
##   H  СТРЕЛКИ   — отрядный радар включён, проходящий мимо отряд получает
##                  залп без задержки
##
## Запуск: <godot> --headless --path . res://qa_fix_pack/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(480.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 480 с")
		_finish())

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
	print("\n═════ ИТОГ qa_fix_pack: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(scene: String, faction: int, at: Vector3) -> Unit:
	var u: Unit = load("res://scenes/units/%s.tscn" % scene).instantiate()
	u.faction = faction
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _squad(scene: String, uid: String, faction: int, n: int, at: Vector3,
		cols: int = 6, sp: float = 0.7) -> int:
	var sid: int = GameManager.new_squad(faction, uid)
	for k in range(n):
		var u: Unit = _spawn(scene, faction,
			at + Vector3(float(k % cols) * sp, 0.0, float(k / cols) * sp))
		GameManager.add_to_squad(sid, u)
	return sid

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _kill_squad(sid: int) -> void:
	for m in GameManager.squad_members(sid):
		if is_instance_valid(m):
			(m as Unit).take_damage(1e12)

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(10):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.pop_limit_enabled = false
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(F, int(t), 90000.0)
	await pframes(4)
	print("\n═════ qa_fix_pack ═════")
	_a_map()
	await _b_big()
	await _c_monk()
	await _d_panel()
	await _e_formation()
	await _f_forge()
	await _g_trolls()
	await _h_archers()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_map() -> void:
	print("\n═════ A. КАРТА ═════")
	var fp: Vector3 = main.ford_point()
	var near_ford := 0
	var all_mines := 0
	for grp in ["neutral_buildings", "player_buildings", "enemy_buildings", "goblin_buildings"]:
		for b in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(b) and b is Mine:
				all_mines += 1
				if _xz((b as Node3D).global_position, fp) < 40.0:
					near_ford += 1
	verdict("A1 на броде рудника нет", near_ford == 0 and not bool(main.FORD_MINE_ENABLED),
		"рудников у брода %d" % near_ford)
	# 14.09.2026: плюс рудник красного ИИ на нижней горушке (Main.AI_MINE_ENABLED)
	var extra: int = 1 + (1 if bool(main.AI_MINE_ENABLED) else 0)
	verdict("A2 ничейных рудников пути — по числу GOLD_MINE_T (два), плюс рудник орды и рудник ИИ",
		main.gold_mine_spots().size() == (main.GOLD_MINE_T as Array).size()
			and all_mines == (main.GOLD_MINE_T as Array).size() + extra,
		"точек %d, рудников на карте %d" % [main.gold_mine_spots().size(), all_mines])
	verdict("A3 центр карты для ИИ — сам брод",
		_xz(main.ai_rally_point(), fp) < 0.5)

# ═════════════════════════════════════════════════════════════════════════════
func _b_big() -> void:
	print("\n═════ B. БОЛЬШИЕ ГОБЛИНЫ ═════")
	var gob_hp: float = _UCfg.stat("goblin_spearman", "health", 0.0)
	var squad: int = int(_GobCfg.SQUAD_SIZE.get("goblin_spearman", 0))
	var hp: float = _UCfg.stat("big_goblin", "health", 0.0)
	# Запас туши — число, которое правит владелец (14.09.2026: 8250 → 3250);
	# стережём направление заказа «не выше половины отряда гоблинов»
	verdict("B1 запас туши не выше половины отряда гоблинов",
		hp <= float(squad) * gob_hp * 0.5 + 1.0 and _UCfg.BIG_GOBLIN_HP_SQUADS <= 0.5,
		"%.0f при потолке %.0f" % [hp, float(squad) * gob_hp * 0.5])
	verdict("B2 спрайт туши уменьшен на 20 % (×2.4 вместо ×3.0)",
		absf(_GobCfg.BIG_SIZE_SCALE - 2.4) < 0.01
			and absf(_GobCfg.BIG_PIXEL_SIZE / 0.0108 - 2.4) < 0.01)
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 30.0)
	main._clear_area_of_resources(spot, 50.0)
	var big: Unit = _spawn("BigGoblin", Constants.FACTION_GOBLIN, spot)
	await pframes(2)
	verdict("B3 обвод туши — тонкий (fine_ring_radius > 0, овал как у тролля)",
		big.fine_ring_radius() > 0.0 and big.ring_oval().x > 1.0)
	var fc: Color = big.hit_flash_color()
	verdict("B4 вспышка удара красная и лёгкая, не белая",
		fc.r > fc.b + 0.5 and fc.r > fc.g + 0.5 and big.hit_flash_peak() < 0.5,
		"цвет %s, пик %.2f" % [str(fc), big.hit_flash_peak()])
	verdict("B5 клик по туше — по всему спрайту (pick_body_h > 0)",
		big.pick_body_h() > 1.0 and big.pick_radius() > 0.5)
	# ── СТРЕЛА БЬЁТ ТУШУ ────────────────────────────────────────────────────
	big.set_tick(false)
	var arch: Unit = _spawn("Archer", F, spot + Vector3(-12.0, 0.0, 0.0))
	await pframes(2)
	var hp0: float = big.current_health
	var shots0: int = GameManager.arrows_fired
	arch.command_attack(big, true, false, true)
	var hurt := false
	for _f in range(60 * 8):
		await get_tree().physics_frame
		if big.current_health < hp0 - 1.0:
			hurt = true
			break
	verdict("B6 стрела наносит туше урон (×%.0f к стрелам)" % big.ranged_damage_mult(),
		hurt and GameManager.arrows_fired > shots0,
		"запас %.0f → %.0f, выстрелов %d" % [hp0, big.current_health, GameManager.arrows_fired - shots0])
	arch.take_damage(1e12)
	big.take_damage(1e12)
	await pframes(4)
	# ── УПЁРЛИСЬ В КОПЕЙЩИКОВ — БЬЮТ КОПЕЙЩИКОВ, А НЕ ЛЕЗУТ К ЛУЧНИКАМ ─────
	var wall_at: Vector3 = spot + Vector3(0.0, 0.0, 0.0)
	var sp_sid: int = _squad("Spearman", "spearman", F, 24, wall_at + Vector3(-4.0, 0.0, 0.0), 12, 0.6)
	var ar_sid: int = _squad("Archer", "archer", F, 6, wall_at + Vector3(-2.0, 0.0, -8.0), 6, 0.7)
	for m in GameManager.squad_members(sp_sid):
		(m as Unit).set_stance(_UCfg.STANCE_DEFENSE)
		(m as Unit).max_health = 1e8
		(m as Unit).current_health = 1e8
		(m as Unit)._soa_push_stats()
	for m in GameManager.squad_members(ar_sid):
		(m as Unit).max_health = 1e8
		(m as Unit).current_health = 1e8
		(m as Unit)._soa_push_stats()
	var big_sid: int = int(main.spawn_goblin_squad("big_goblin", 5, wall_at + Vector3(0.0, 0.0, 16.0)))
	await pframes(4)
	var archer0: Unit = GameManager.squad_members(ar_sid)[0]
	for m in GameManager.squad_members(big_sid):
		(m as Unit).command_attack(archer0, true, false, true)
	var sp_hp0 := 0.0
	for m in GameManager.squad_members(sp_sid):
		sp_hp0 += (m as Unit).current_health
	var on_spears := 0
	var t_hit := -1
	for f in range(60 * 20):
		await get_tree().physics_frame
		on_spears = 0
		for m in GameManager.squad_members(big_sid):
			var u := m as Unit
			if is_instance_valid(u) and u.attack_target != null and is_instance_valid(u.attack_target) \
					and u.attack_target is Spearman:
				on_spears += 1
		var sp_hp := 0.0
		for m in GameManager.squad_members(sp_sid):
			sp_hp += (m as Unit).current_health
		if on_spears >= 3 and sp_hp < sp_hp0 - 1.0:
			t_hit = f
			break
	var sp_hp1 := 0.0
	for m in GameManager.squad_members(sp_sid):
		sp_hp1 += (m as Unit).current_health
	verdict("B7 туши, упёршиеся в копейщиков, бьют копейщиков (не лезут сквозь к лучникам)",
		on_spears >= 3 and sp_hp1 < sp_hp0 - 1.0,
		"на копейщиках %d из %d, урон копейщикам %.0f, кадр %d" % [
			on_spears, GameManager.squad_members(big_sid).size(), sp_hp0 - sp_hp1, t_hit])
	var behind := 0
	for m in GameManager.squad_members(big_sid):
		if is_instance_valid(m) and (m as Unit).global_position.z < wall_at.z - 2.0:
			behind += 1
	verdict("B7б ни одна туша не прошла сквозь строй к лучникам", behind == 0,
		"за линией %d" % behind)
	_kill_squad(big_sid); _kill_squad(sp_sid); _kill_squad(ar_sid)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
func _c_monk() -> void:
	print("\n═════ C. ВОСКРЕШЕНИЕ ПАВШИХ ДО ИЗУЧЕНИЯ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, 60.0)
	main._clear_area_of_resources(spot, 50.0)
	var sid: int = _squad("Spearman", "spearman", F, 20, spot, 10, 0.7)
	await pframes(4)
	# Половина отряда гибнет ДО того, как узел воскрешения изучен
	var members: Array = GameManager.squad_members(sid)
	for i in range(10):
		(members[i] as Unit).take_damage(1e12)
	await pframes(6)
	var corpses0: int = GameManager.corpses.raisable_count(F)
	verdict("C1 павшие лежат телами, тела «поднимаемые»", corpses0 >= 10, "тел %d" % corpses0)
	# Живые — РАНЕНЫ, но не тяжело: раньше это глушило воскрешение навсегда
	for m in GameManager.squad_members(sid):
		var u := m as Unit
		u.current_health = u.max_health * 0.7
		u._soa_push_stats()
	verdict("C2 без узла воскрешения монах павших не поднимает",
		not GameManager.is_researched(F, "monk_2d"))
	GameManager.finish_research(F, "monk_2d")
	var monk: Unit = _spawn("Monk", F, spot + Vector3(-6.0, 0.0, 3.0))
	await pframes(2)
	verdict("C3 узел изучен ПОСЛЕ гибели — монах вправе воскрешать",
		bool(monk.call("can_resurrect")))
	var r0: int = GameManager.resurrected_total
	var t_first := -1
	var wait: int = int(60 * (_UCfg.MONK_RES_SEC + 12.0))
	for f in range(wait):
		await get_tree().physics_frame
		if GameManager.resurrected_total > r0:
			t_first = f
			break
	verdict("C4 монах поднимает павшего, погибшего ДО изучения узла, при раненых рядом",
		t_first >= 0, "поднято %d, кадр %d" % [GameManager.resurrected_total - r0, t_first])
	var r1: int = GameManager.resurrected_total
	for _f in range(int(60 * (_UCfg.MONK_RES_SEC + _UCfg.MONK_RES_COOLDOWN + 10.0))):
		await get_tree().physics_frame
		if GameManager.resurrected_total > r1:
			break
	verdict("C5 и продолжает поднимать следующих (второй за канал + откат)",
		GameManager.resurrected_total > r1, "всего поднято %d" % (GameManager.resurrected_total - r0))
	verdict("C5б поднятый вернулся В СВОЙ отряд",
		GameManager.squad_members(sid).size() >= 12,
		"в отряде %d" % GameManager.squad_members(sid).size())
	monk.take_damage(1e12)
	_kill_squad(sid)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _d_panel() -> void:
	print("\n═════ D. ПАНЕЛЬ КРЕПОСТИ ═════")
	var hud = main.hud
	var castle := Castle.new()
	castle.faction = F
	main.world_add(castle)
	var cp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(20.0, 0.0, 20.0)
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(3)
	var sm = main.selection_manager
	sm._clear_selection()
	sm._select(castle)
	GameManager.on_selection_changed(sm.selected_units, true)
	for _i in range(3):
		await get_tree().process_frame
	var btns: Array = []
	_collect_buttons(hud.button_container, btns)
	var train: Array = []
	for b in btns:
		if (b as Button).name != "KeepRankButton":
			train.append(b)
	var square := true
	var sizes := ""
	for b in train:
		var r: Rect2 = (b as Control).get_global_rect()
		sizes += "%.0f×%.0f " % [r.size.x, r.size.y]
		if absf(r.size.x - r.size.y) > 1.0:
			square = false
	verdict("D1 три иконки найма (рабочий, рыцарь, монах) строго квадратные",
		train.size() == 3 and square, "иконок %d: %s" % [train.size(), sizes])
	var pr: Rect2 = hud._bottom_panel.get_global_rect()
	verdict("D2 панель Крепости заданного размера (%.0f×%.0f)" % [hud.CASTLE_PANEL_W, hud.CASTLE_PANEL_H],
		absf(pr.size.x - hud.CASTLE_PANEL_W) <= 1.0 and absf(pr.size.y - hud.CASTLE_PANEL_H) <= 1.0,
		"панель %.0f×%.0f" % [pr.size.x, pr.size.y])
	var bc: Rect2 = hud.button_container.get_global_rect()
	var qr: Rect2 = hud._queue_frame.get_global_rect()
	var right_gap: float = (pr.position.x + pr.size.x) - (bc.position.x + bc.size.x)
	var left_gap: float = bc.position.x - (qr.position.x + qr.size.x)
	verdict("D3 ряд иконок отцентрован в свободном месте, отступ от края ≥ %.0f px" % hud.CASTLE_BTN_PAD,
		absf(right_gap - left_gap) <= 4.0 and right_gap >= hud.CASTLE_BTN_PAD - 0.5,
		"слева %.1f, справа %.1f" % [left_gap, right_gap])
	var top_gap: float = bc.position.y - pr.position.y
	var bot_gap: float = (pr.position.y + pr.size.y) - (bc.position.y + bc.size.y)
	verdict("D4 ряд иконок по вертикали с отступами не меньше %.0f px" % hud.CASTLE_BTN_PAD,
		top_gap >= hud.CASTLE_BTN_PAD - 0.5 and bot_gap >= hud.CASTLE_BTN_PAD - 0.5
			and absf(top_gap - bot_gap) <= 3.0,
		"сверху %.1f, снизу %.1f" % [top_gap, bot_gap])
	var rank: Button = null
	var knight: Button = null
	for b in btns:
		if (b as Button).name == "KeepRankButton":
			rank = b
	for b in train:
		for ch in (b as Button).get_children():
			if ch is Label and (ch as Label).name == "RankChevrons":
				knight = b
	verdict("D5 кнопка [ I ] стоит под иконкой рыцаря",
		rank != null and knight != null
			and rank.get_global_rect().position.y >= knight.get_global_rect().end.y - 0.5
			and absf(rank.get_global_rect().get_center().x - knight.get_global_rect().get_center().x) <= 2.0)
	sm._clear_selection()
	GameManager.on_selection_changed(sm.selected_units, true)
	castle.take_damage(1e12)
	await pframes(4)

func _collect_buttons(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Button:
			out.append(c)
		if c is Control:
			_collect_buttons(c, out)

# ═════════════════════════════════════════════════════════════════════════════
func _extent(slots: Array, dir: Vector3) -> Vector2:
	var side := Vector3(dir.z, 0.0, -dir.x)
	var lo := INF; var hi := -INF; var lo2 := INF; var hi2 := -INF
	for s in slots:
		var p: Vector3 = s
		lo = minf(lo, p.dot(dir)); hi = maxf(hi, p.dot(dir))
		lo2 = minf(lo2, p.dot(side)); hi2 = maxf(hi2, p.dot(side))
	return Vector2(hi - lo, hi2 - lo2)

func _e_formation() -> void:
	print("\n═════ E. СТРОЙ: СВОБОДНАЯ РАСТЯЖКА ВСЕМ ═════")
	var sm = main.selection_manager
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(90.0, 0.0, 20.0)
	main._clear_area_of_resources(spot, 50.0)
	var ar_sid: int = _squad("Archer", "archer", F, 20, spot, 10, 0.7)
	var wr_sid: int = _squad("Warrior", "warrior", F, 20, spot + Vector3(0.0, 0.0, 8.0), 10, 0.7)
	var sp_sid: int = _squad("Spearman", "spearman", F, 30, spot + Vector3(0.0, 0.0, 16.0), 10, 0.7)
	await pframes(3)
	var a: Vector3 = spot + Vector3(-15.0, 0.0, -20.0)
	var b: Vector3 = spot + Vector3(15.0, 0.0, -20.0)
	var dir: Vector3 = (b - a).normalized()
	sm.formation_mode = sm.FORM_WIDE
	var arch: Array = GameManager.squad_members(ar_sid)
	var war: Array = GameManager.squad_members(wr_sid)
	var ea: Vector2 = _extent(sm._mono_formation_slots(a, b, arch)["slots"], dir)
	var ew: Vector2 = _extent(sm._mono_formation_slots(a, b, war)["slots"], dir)
	# Свободный растяг: одна-две шеренги во всю ширину отряда (20 × UNIT_SPACING),
	# а не три ряда «коробочки»
	var free_w: float = 20.0 * sm.UNIT_SPACING * 0.9
	verdict("E1 по умолчанию лучники и рыцари растягиваются свободно (не глубже двух шеренг)",
		ea.y <= sm.ROW_DEPTH * 1.5 + 0.01 and ew.y <= sm.ROW_DEPTH * 1.5 + 0.01
			and ea.x >= free_w and ew.x >= free_w,
		"лучники %.1f×%.1f, рыцари %.1f×%.1f м" % [ea.x, ea.y, ew.x, ew.y])
	GameManager.finish_research(F, "spearman_1a")
	GameManager.finish_research(F, "spearman_1b")
	GameManager.finish_research(F, "spearman_1c")
	GameManager.finish_research(F, "spearman_1d")
	var spears: Array = GameManager.squad_members(sp_sid)
	var es: Vector2 = _extent(sm._mono_formation_slots(a, b, spears)["slots"], dir)
	verdict("E2 копейщики со «Стеной копий» — ровно в %d шеренги на любом растяге" % GameManager.SPEAR_WALL_ROWS,
		GameManager.spear_wall_ready(sp_sid)
			and absf(es.y - float(GameManager.SPEAR_WALL_ROWS - 1) * sm.ROW_DEPTH) <= 0.05,
		"глубина %.2f м" % es.y)
	var ea2: Vector2 = _extent(sm._mono_formation_slots(a, b, arch)["slots"], dir)
	verdict("E3 «Стена копий» копейщиков НЕ трогает лучников — те по-прежнему свободны",
		ea2.y <= sm.ROW_DEPTH * 1.5 + 0.01, "глубина лучников %.2f м" % ea2.y)
	# [2] в растяге — коробочка на этот растяг; отпустили ПКМ — снова свободно
	sm.selected_units = arch.duplicate()
	sm._rmb_down = true
	sm._rmb_dragging = true
	sm._rmb_press_over_ui = false
	sm._rmb_world_start = a
	sm._rmb_screen_start = Vector2(100, 300)
	var k := InputEventKey.new()
	k.keycode = KEY_2
	k.physical_keycode = KEY_2
	k.pressed = true
	sm._unhandled_input(k)
	var deep_on: bool = sm.formation_mode == sm.FORM_DEEP
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_RIGHT
	rel.pressed = false
	rel.position = Vector2(400, 300)
	sm._unhandled_input(rel)
	# ТЗ 14.09.2026, п. 4 (пятый разворот ручки): режим ЗАПОМИНАЕТСЯ —
	# отпускание ПКМ его не сбрасывает; персистентность — qa_formation_keys E
	verdict("E4 [2] даёт коробочку и она ЗАПОМИНАЕТСЯ: по отпусканию ПКМ режим прежний",
		deep_on and sm.formation_mode == sm.FORM_DEEP, "режим %d" % sm.formation_mode)
	sm.formation_mode = sm.FORM_WIDE
	sm.selected_units = []
	_kill_squad(ar_sid); _kill_squad(wr_sid); _kill_squad(sp_sid)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _f_forge() -> void:
	print("\n═════ F. КУЗНИЦА: БОНУСНЫЕ ЯЧЕЙКИ D ═════")
	var smithy := Smithy.new()
	smithy.faction = F
	main.world_add(smithy)
	var sp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(30.0, 0.0, 10.0)
	smithy.global_position = Vector3(sp.x, GameManager.get_terrain_height(sp.x, sp.z), sp.z)
	await pframes(3)
	# Мечники: ряд 1 нетронут
	verdict("F1 1D закрыта, пока не изучен ряд 1 (A+B+C)",
		not GameManager.can_research(F, "warrior_1d"))
	GameManager.finish_research(F, "warrior_1a")
	GameManager.finish_research(F, "warrior_1b")
	verdict("F1б двух узлов ряда мало", not GameManager.can_research(F, "warrior_1d"))
	GameManager.finish_research(F, "warrior_1c")
	verdict("F2 ряд 1 изучен — 1D открыта", GameManager.can_research(F, "warrior_1d"))
	var slot1: Dictionary = _UCfg.get_upgrade_slot("warrior_1d")
	var cost1: Dictionary = _UCfg.upgrade_cost(slot1)
	var g0: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
	var w0: float = ResourceManager.get_amount(F, Constants.RESOURCE_WOOD)
	verdict("F3 у 1D есть цена (золото и дерево)",
		float(cost1.get(Constants.RESOURCE_GOLD, 0.0)) > 0.0 and float(cost1.get(Constants.RESOURCE_WOOD, 0.0)) > 0.0,
		str(cost1))
	var started: bool = smithy.research("warrior_1d")
	var g1: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
	var w1: float = ResourceManager.get_amount(F, Constants.RESOURCE_WOOD)
	verdict("F4 клик по 1D списывает ресурсы и запускает исследование",
		started and absf((g0 - g1) - float(cost1.get(Constants.RESOURCE_GOLD, 0.0))) < 0.01
			and absf((w0 - w1) - float(cost1.get(Constants.RESOURCE_WOOD, 0.0))) < 0.01,
		"золото −%.0f, дерево −%.0f" % [g0 - g1, w0 - w1])
	# Доводим исследование часами кузницы
	smithy.research_timer = smithy.research_time
	smithy._process(0.01)
	await pframes(2)
	verdict("F5 по истечении времени 1D изучена и активна",
		GameManager.is_researched(F, "warrior_1d"))
	verdict("F6 2D закрыта до ряда 2, хотя 1D изучена",
		not GameManager.can_research(F, "warrior_2d"))
	for c in ["2a", "2b", "2c"]:
		GameManager.finish_research(F, "warrior_" + c)
	verdict("F7 ряд 2 изучен — 2D открыта", GameManager.can_research(F, "warrior_2d"))
	var rising := true
	var prev := 0.0
	for r in range(1, 6):
		var s: Dictionary = _UCfg.get_upgrade_slot("warrior_%dd" % r)
		var g: float = float(s.get("cost_gold", 0.0))
		if g <= prev:
			rising = false
		prev = g
	verdict("F8 цена ячеек D растёт с рядом (1D < 2D < … < 5D по золоту)", rising)
	smithy.take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _g_trolls() -> void:
	print("\n═════ G. ТРОЛЛИ У ПНЯ ═════")
	var lair = GameManager.troll_lair
	verdict("G1 на старте у пня один страж; постоянная охрана — до двух; +1 раз в 5 минут",
		_GobCfg.LAIR_START_TROLLS == 1 and _GobCfg.TROLL_GUARDS_MAX == 2
			and is_equal_approx(_GobCfg.TROLL_RESPAWN_SEC, 300.0),
		"старт %d, потолок %d, период %.0f с" % [_GobCfg.LAIR_START_TROLLS, _GobCfg.TROLL_GUARDS_MAX, _GobCfg.TROLL_RESPAWN_SEC])
	verdict("G2 волна защиты — 3 тролля, откат 10 минут",
		_GobCfg.TROLL_DEFENSE_WAVE == 3 and is_equal_approx(_GobCfg.TROLL_DEFENSE_WAVE_CD, 600.0))
	if lair == null or not is_instance_valid(lair):
		verdict("G0 пень на карте", false)
		return
	# Доводим стражей до двух и бьём обоих
	if lair.trolls_alive() < 2:
		lair.spawn_guards(2 - lair.trolls_alive())
	await pframes(2)
	var alive0: int = lair.trolls_alive()
	var live: Array = []
	for t in lair.trolls:
		if is_instance_valid(t) and not (t as Unit).is_dead():
			live.append(t)
	verdict("G3 стражей двое", live.size() >= 2, "стражей %d" % live.size())
	if live.size() < 2:
		return
	var foe: Unit = _spawn("Spearman", F, (live[0] as Node3D).global_position + Vector3(6.0, 0.0, 0.0))
	foe.max_health = 1e9; foe.current_health = 1e9; foe._soa_push_stats()
	var waves0: int = int(lair.defense_waves)
	(live[0] as Unit).take_damage(5.0, foe)
	await pframes(2)
	verdict("G4 удар по ОДНОМУ стражу волну не зовёт",
		int(lair.defense_waves) == waves0 and lair.trolls_alive() == alive0,
		"троллей %d" % lair.trolls_alive())
	(live[1] as Unit).take_damage(5.0, foe)
	await pframes(3)
	verdict("G5 второй страж получил урон — из пня вышли 3 дополнительных тролля",
		int(lair.defense_waves) == waves0 + 1 and lair.trolls_alive() >= alive0 + 3,
		"троллей %d (было %d), волн %d" % [lair.trolls_alive(), alive0, int(lair.defense_waves)])
	var alive1: int = lair.trolls_alive()
	(live[0] as Unit).take_damage(5.0, foe)
	(live[1] as Unit).take_damage(5.0, foe)
	await pframes(3)
	verdict("G6 повторный удар в откате волну не зовёт (10 минут)",
		int(lair.defense_waves) == waves0 + 1 and lair.trolls_alive() == alive1
			and not lair.defense_wave_ready(lair._lair_clock()))
	foe.take_damage(1e12)
	for t in lair.trolls:
		if is_instance_valid(t):
			(t as Unit).set_tick(false)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _h_archers() -> void:
	print("\n═════ H. СТРЕЛКИ: РАДАР И ПРОХОДЯЩИЙ МИМО ОТРЯД ═════")
	# База лучника — число владельца (ТЗ 14.09.2026: 15 м, кузница до 25);
	# стережём свойство «обнаружение = дальность + 5 м», а не число 20
	verdict("H1 отрядный радар стрелков включён (обнаружение = дальность + 5 м)",
		_Opt.squad_radar and is_equal_approx(GameManager.RADAR_MARGIN, 5.0)
			and _UCfg.stat("archer", "attack_range", 0.0) >= 15.0,
		"радар %s, запас %.0f, дальность %.0f" % [str(_Opt.squad_radar), GameManager.RADAR_MARGIN,
			_UCfg.stat("archer", "attack_range", 0.0)])
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(120.0, 0.0, 40.0)
	main._clear_area_of_resources(spot, 60.0)
	var ar_sid: int = _squad("Archer", "archer", F, 12, spot, 6, 0.8)
	await pframes(60)
	var gob_sid: int = int(main.spawn_goblin_squad("goblin_spearman", 20, spot + Vector3(-40.0, 0.0, 15.0)))
	await pframes(2)
	for m in GameManager.squad_members(gob_sid):
		(m as Unit).max_health = 1e8
		(m as Unit).current_health = 1e8
		(m as Unit)._soa_push_stats()
		(m as Unit).command_move(spot + Vector3(40.0, 0.0, 15.0), false, Vector3.ZERO, false, true)
	var shots0: int = GameManager.arrows_fired
	var t_fire := -1
	var d_fire := 0.0
	for f in range(60 * 30):
		await get_tree().physics_frame
		if GameManager.arrows_fired > shots0:
			t_fire = f
			# Дистанция — БЛИЖАЙШАЯ ПАРА стрелок/гоблин, а не центроиды (те на
			# отряд в 12 и 20 человек врут на несколько метров)
			d_fire = INF
			for a in GameManager.squad_members(ar_sid):
				for g in GameManager.squad_members(gob_sid):
					d_fire = minf(d_fire, _xz((a as Node3D).global_position, (g as Node3D).global_position))
			break
	verdict("H2 отряд, проходящий мимо стрелков в 15 м, получает залп",
		t_fire >= 0, "первый выстрел на кадре %d, дистанция %.1f м" % [t_fire, d_fire])
	verdict("H2б первый выстрел — как только цель вошла в дальность (не дальше 21 м)",
		t_fire >= 0 and d_fire <= 21.0, "%.1f м" % d_fire)
	_kill_squad(ar_sid); _kill_squad(gob_sid)
	await pframes(4)
