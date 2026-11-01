extends Node

## ═══════════════════════════════════════════════════════════════════════════
## НОВАЯ ОРДА (ТЗ 11.10.2026, часть 2): ЛАГЕРЬ, ЭКОНОМИКА, ВОЛНЫ, ОХРАНА
## ═══════════════════════════════════════════════════════════════════════════
## A — старт: стартовой орды и резерва нет; охрана: рудник лагеря 8 отрядов
##     (2 пехоты 2 лычки, 3 туши 2 лычки, 3 конницы 4 лычки), ничейные
##     рудники по 4 (2 пехоты + 2 конницы); вся охрана спит (F_DORMANT, тик
##     снят); главная хата вдвое больше хижины, 20 000 запаса; хижин 10,
##     все выше хаты (серп).
## B — охрана стоит: за 90 с ни одного вызволения и ни одного сдвига поста.
## C — экономика: еда растёт; отряд покупается за цену конфига, рождается в
##     слоте площадки сбора, засыпает; диски толп соседних слотов не
##     накладываются.
## D — потолок: Main.spawn_goblin_squad урезает отряд до остатка HORDE_CAP.
## E — побудка: чужой у рудника — охрана просыпается и бьёт; чужой исчез —
##     идёт на пост и засыпает.
## F — волна: после перемирия набранная волна уходит (проснулась, идёт).
## G — хата чинится сама; снесли все хижины — орда разбита, покупок нет.
## Запуск: godot --headless --path . res://qa_horde2/Test.tscn [-- only=abcdefg]

const G := Constants.FACTION_GOBLIN
const P := Constants.FACTION_PLAYER
const _Spawn := preload("res://scripts/spawn_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var main = null
var gai = null
var _pass := 0
var _fail := 0
var _only := "abcdefg"

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_horde2: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _alive(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in (sq as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _all_dormant(sid: int) -> bool:
	for m in _alive(sid):
		if not (m as Unit).dormant:
			return false
	return not _alive(sid).is_empty()

func _run() -> void:
	# Площадку сбора/спавн у пня стенд проверяет на точке: вход орды из-за
	# кромки (ТЗ 31.10.2026, стережёт qa_tz1031c) увёл бы отряды к краю карты
	preload("res://scripts/perf_config.gd").horde_edge_entry = false
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	gai = main.goblin_ai
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("cav_commander") != null:
		main.cav_commander.set_process(false)
	if _only.contains("a"): await _block_a()
	if _only.contains("b"): await _block_b()
	if _only.contains("c"): await _block_c()
	if _only.contains("d"): _block_d()
	if _only.contains("e"): await _block_e()
	if _only.contains("f"): await _block_f()
	if _only.contains("g"): await _block_g()
	_finish()

# ── A. СТАРТ ─────────────────────────────────────────────────────────────────
func _block_a() -> void:
	print("\n═════ A. СТАРТ ЛАГЕРЯ ═════")
	var wave_sq := 0
	var gsq := 0
	for sid in GameManager.squads:
		if int((GameManager.squads[sid] as Dictionary)["faction"]) != G:
			continue
		var t: String = GameManager.squad_type(int(sid))
		if t == "gnoll" or t == "troll" or t == "sheep":
			continue
		gsq += 1
		# Стартовый резерв волн спит на площадке (ТЗ 12.10.2026, второе письмо)
		if not gai.guards.has(int(sid)) and not gai._muster_slot.has(int(sid)):
			wave_sq += 1
	verdict("A1 на старте у орды только охрана рудников и резерв на площадке", wave_sq == 0,
		"отрядов орды %d, охраны %d, на площадке %d" % [gsq, gai.guards.size(), gai._muster_slot.size()])
	var by_mine: Dictionary = {}
	for sid in gai.guards:
		var m = gai.guards[sid]["mine"]
		if not by_mine.has(m):
			by_mine[m] = []
		(by_mine[m] as Array).append(int(sid))
	var camp: Array = by_mine.get(GameManager.goblin_mine, [])
	var comp: Dictionary = {}
	for sid in camp:
		var key: String = "%s/%d" % [GameManager.squad_type(int(sid)), GameManager.squad_level(int(sid))]
		comp[key] = int(comp.get(key, 0)) + 1
	verdict("A2 рудник лагеря: 2 пехоты (2), 3 туши (2), 3 конницы (4)",
		int(comp.get("goblin_spearman/2", 0)) == 2 and int(comp.get("big_goblin/2", 0)) == 3 and int(comp.get("goblin_rider/4", 0)) == 3,
		str(comp))
	var terr_ok := true
	var terr_n := 0
	for m in by_mine:
		if m == GameManager.goblin_mine:
			continue
		terr_n += 1
		var c2: Dictionary = {}
		for sid in by_mine[m]:
			var t2: String = GameManager.squad_type(int(sid))
			c2[t2] = int(c2.get(t2, 0)) + 1
		if int(c2.get("goblin_spearman", 0)) != 2 or int(c2.get("goblin_rider", 0)) != 2:
			terr_ok = false
	verdict("A3 ничейные рудники: по 2 пехоты + 2 конницы", terr_ok and terr_n == 2, "рудников %d" % terr_n)
	var sleeping := 0
	for sid in gai.guards:
		if _all_dormant(int(sid)):
			sleeping += 1
	verdict("A4 вся охрана спит", sleeping == gai.guards.size(), "%d из %d" % [sleeping, gai.guards.size()])
	var chief: Building = gai.chief
	var hut_size: Vector3 = Vector3(4.0, 3.5, 4.0)
	var huts_above := 0
	var huts := 0
	for b in get_tree().get_nodes_in_group("goblin_buildings"):
		if b is Building and String((b as Building).building_id) == "goblin_hut":
			huts += 1
			if (b as Node3D).global_position.z < chief.global_position.z:
				huts_above += 1
	verdict("A5 главная хата: вдвое больше, 20 000 запаса", chief != null
		and absf(chief.build_size.x - hut_size.x * 2.0) < 0.01 and absf(chief.max_health - _Spawn.CHIEF_HUT_HP) < 0.5,
		"размер %s, запас %.0f" % [chief.build_size, chief.max_health])
	verdict("A6 хижины серпом выше хаты", huts == _Spawn.CAMP_HUTS and huts_above == huts, "хижин %d, выше хаты %d" % [huts, huts_above])

# ── B. ОХРАНА СТОИТ ──────────────────────────────────────────────────────────
func _block_b() -> void:
	print("\n═════ B. ОХРАНА НЕ ВЫЗВОЛЯЕТСЯ И НЕ ХОДИТ ═════")
	var u0: int = Unit.unstuck_total
	var c0: Dictionary = {}
	for sid in gai.guards:
		c0[sid] = GameManager.squad_centre_xz(int(sid))
	var ticking0 := 0
	for sid in gai.guards:
		for m in _alive(int(sid)):
			if (m as Unit).tick_on:
				ticking0 += 1
	await pframes(60 * 90)
	var moved := 0
	for sid in gai.guards:
		var c1: Vector2 = GameManager.squad_centre_xz(int(sid))
		if (c0[sid] as Vector2).distance_to(c1) > 0.5:
			moved += 1
	verdict("B1 за 90 с охрана ни разу не вызволялась", Unit.unstuck_total - u0 == 0, "вызволений %d" % (Unit.unstuck_total - u0))
	verdict("B2 посты не сдвинулись", moved == 0, "сдвинулось отрядов %d" % moved)
	verdict("B3 спящая охрана не тикает", ticking0 == 0, "тикают %d" % ticking0)

# ── C. ЭКОНОМИКА И ПЛОЩАДКА СБОРА ────────────────────────────────────────────
func _block_c() -> void:
	print("\n═════ C. ЭКОНОМИКА, ПОКУПКА, СЛОТЫ ═════")
	# Стартовый резерв (ТЗ 12.10.2026) занимает площадку и закрывает планы
	# даром — для проверки покупки площадку освобождаем
	for sid0 in gai._muster_slot.keys():
		for m0 in _alive(int(sid0)):
			(m0 as Unit).take_damage(1e12)
	await pframes(90)
	ResourceManager.set_amount(G, Constants.RESOURCE_FOOD, 0.0)
	await pframes(60 * 20)
	var f1: float = ResourceManager.get_amount(G, Constants.RESOURCE_FOOD)
	verdict("C1 хижины дают еду", f1 > 30.0, "за 20 с: %.0f" % f1)
	var bought0: int = gai.squads_bought
	ResourceManager.set_amount(G, Constants.RESOURCE_FOOD, 1500.0)
	await pframes(60 * 12)
	var bought: int = gai.squads_bought - bought0
	var f2: float = ResourceManager.get_amount(G, Constants.RESOURCE_FOOD)
	verdict("C2 отряды покупаются за еду", bought >= 2 and f2 < 1500.0, "куплено %d, еды %.0f" % [bought, f2])
	await pframes(60 * 3)
	var sleeping := 0
	var cents: Array = []
	for sid in gai._muster_slot:
		if _all_dormant(int(sid)):
			sleeping += 1
		var c: Vector2 = GameManager.squad_centre_xz(int(sid))
		cents.append([c, _GobCfg.horde_radius(_alive(int(sid)).size())])
	verdict("C3 купленные отряды на площадке спят", sleeping == gai._muster_slot.size() and sleeping > 0,
		"%d из %d" % [sleeping, gai._muster_slot.size()])
	var overlap := 0
	for i in range(cents.size()):
		for j in range(i + 1, cents.size()):
			var d: float = (cents[i][0] as Vector2).distance_to(cents[j][0])
			if d < float(cents[i][1]) + float(cents[j][1]):
				overlap += 1
	verdict("C4 диски толп на площадке не накладываются", overlap == 0, "пар внахлёст %d из %d отрядов" % [overlap, cents.size()])

# ── D. ПОТОЛОК ───────────────────────────────────────────────────────────────
func _block_d() -> void:
	print("\n═════ D. ПОТОЛОК ОРДЫ ═════")
	var alive: int = main.horde_alive()
	var left: int = _Spawn.HORDE_CAP - alive
	var far := Vector3(150.0, 0.0, 100.0)
	var sid: int = 0
	if left > 0:
		sid = main.spawn_goblin_squad("goblin_spearman", left + 50, far)
	var got: int = _alive(sid).size() if sid > 0 else 0
	verdict("D1 отряд урезан до остатка потолка", got <= maxi(left, 0), "остаток %d, родилось %d" % [left, got])
	var sid2: int = main.spawn_goblin_squad("goblin_spearman", 20, far)
	verdict("D2 сверх потолка отряд не рождается", sid2 == 0, "sid %d" % sid2)
	for m in _alive(sid):
		(m as Unit).take_damage(1.0e9, null)

# ── E. ПОБУДКА ОХРАНЫ ────────────────────────────────────────────────────────
func _block_e() -> void:
	print("\n═════ E. ПОБУДКА ОХРАНЫ ═════")
	await pframes(10)
	var m: Node3D = GameManager.goblin_mine
	var mp: Vector3 = m.global_position
	var sid: int = GameManager.new_squad(P, "spearman")
	var men: Array = []
	for i in range(12):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = P
		main.world_add(u)
		var p := mp + Vector3(float(i % 4) * 0.8, 0.0, 5.0 + float(i / 4) * 0.8)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(60 * 4)
	var awake := 0
	var fighting := 0
	for gs in gai.guards:
		if gai.guards[gs]["mine"] != m:
			continue
		if String(gai.guards[gs]["st"]) == "fight":
			awake += 1
		for gm in _alive(int(gs)):
			if (gm as Unit).state == Unit.State.ATTACKING or (gm as Unit).state == Unit.State.MOVING:
				fighting += 1
				break
	verdict("E1 чужой у рудника — охрана проснулась и пошла в бой", awake >= 1 and fighting >= 1,
		"проснулось %d, в деле %d" % [awake, fighting])
	for u2 in men:
		if is_instance_valid(u2) and not (u2 as Unit).is_dead():
			(u2 as Unit).take_damage(1.0e9, null)
	await pframes(60 * int(_Spawn.GUARD_CALM_SEC + _Spawn.GUARD_HOME_TIMEOUT_SEC + 6.0))
	var sleeping := 0
	var total := 0
	for gs2 in gai.guards:
		if gai.guards[gs2]["mine"] != m:
			continue
		total += 1
		if String(gai.guards[gs2]["st"]) == "sleep" and _all_dormant(int(gs2)):
			sleeping += 1
	verdict("E2 отбились — охрана на посту и снова спит", sleeping == total, "%d из %d" % [sleeping, total])

# ── F. ВОЛНА ─────────────────────────────────────────────────────────────────
func _block_f() -> void:
	print("\n═════ F. ВОЛНА ПОСЛЕ ПЕРЕМИРИЯ ═════")
	GameManager.truce_override = 0          # перемирие выключено — мирной фазы нет
	gai.clock = maxf(gai.clock, _Spawn.GOBLIN_PEACE_SEC + 1.0)
	ResourceManager.set_amount(G, Constants.RESOURCE_FOOD, _Spawn.FOOD_BANK_MAX)
	var l0: int = gai.waves_launched
	for _i in range(60):
		await pframes(60)
		ResourceManager.set_amount(G, Constants.RESOURCE_FOOD, _Spawn.FOOD_BANK_MAX)
		if gai.waves_launched > l0:
			break
	verdict("F1 волна вышла", gai.waves_launched > l0, "волн %d → %d" % [l0, gai.waves_launched])
	if gai.waves.is_empty():
		return
	await pframes(60 * 3)
	var w: Dictionary = gai.waves[0]
	var awake := 0
	var going := 0
	for sid in (w["sids"] as Array):
		if not _all_dormant(int(sid)):
			awake += 1
		for m in _alive(int(sid)):
			if (m as Unit).state == Unit.State.MOVING:
				going += 1
				break
	verdict("F2 волна проснулась и идёт по сценарию «%s»" % String(w["name"]), awake == (w["sids"] as Array).size() and going >= 1,
		"проснулось %d из %d, идут %d" % [awake, (w["sids"] as Array).size(), going])

# ── G. ХАТА И РАЗГРОМ ЛАГЕРЯ ─────────────────────────────────────────────────
func _block_g() -> void:
	print("\n═════ G. ПОЧИНКА ХАТЫ, РАЗГРОМ ЛАГЕРЯ ═════")
	var chief: Building = gai.chief
	chief.current_health = chief.max_health * 0.5
	chief.last_hit_ms = Unit.game_ms() - 60000
	await pframes(60 * 3)
	verdict("G1 хата чинится сама, если по ней не бьют", chief.current_health > chief.max_health * 0.5 + 50.0,
		"запас %.0f" % chief.current_health)
	for b in get_tree().get_nodes_in_group("goblin_buildings"):
		if b is Building and (String((b as Building).building_id) == "goblin_hut" or String((b as Building).building_id) == "goblin_chief_hut"):
			(b as Building).take_damage(1.0e9, null)
	await pframes(60 * 3)
	var b0: int = gai.squads_bought
	ResourceManager.set_amount(G, Constants.RESOURCE_FOOD, 5000.0)
	await pframes(60 * 15)
	verdict("G2 хижин нет — орда разбита, покупок больше нет", String(gai.phase) == "defeated" and gai.squads_bought == b0,
		"фаза %s, куплено за 15 с %d" % [gai.phase, gai.squads_bought - b0])
