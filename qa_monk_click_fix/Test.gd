extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_monk_click_fix — ПКМ МОНАХОМ ПО ОТРЯДУ И ФОКУСНОЕ ЛЕЧЕНИЕ (15.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A. ПКМ (настоящий ввод: нажатие + отпускание) монахом по раненому отряду
##      мечников читается как приказ лечить, монах подходит на дистанцию каста.
##   B. Лечение ФОКУСНОЕ: самый раненый вылечивается до 100 % раньше, чем
##      остальные; потом монах переключается на следующего; в конце все целы.
##   C. Монах сопровождает отряд приказа: отряд ушёл на 26 м — монах догнал,
##      нового раненого лечит без нового приказа; приказ на движение снимает.
##   D. Многоцелевой такт даёт КАЖДОЙ цели полный квант одиночного лечения.
## Числа — из конфига (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_monk_click_fix/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const F := Constants.FACTION_PLAYER

var main = null
var sm = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_monk_click_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 4) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x - float(i / cols) * 0.8, 0.0,
			at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _wound(u: Unit, frac: float) -> void:
	u.current_health = u.max_health * frac
	u._soa_push_stats()

func _mouse(btn: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	# В ЛОКАЛЬНЫХ координатах вьюпорта: без второго аргумента корень применяет
	# обратное растяжение окна, и точка (640, 360) уезжала в (17928, 12209)
	get_tree().root.push_input(e, true)

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(14.0, 0.0, 0.0), Vector3(-14.0, 0.0, 0.0), Vector3(0.0, 0.0, 8.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
			if GameManager.is_water(p.x, p.z) or GameManager.is_water(p.x + 14.0, p.z):
				h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _all_full(men: Array) -> bool:
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead() \
				and (u as Unit).current_health < (u as Unit).max_health - 0.01:
			return false
	return true

func _centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			c += (u as Unit).global_position
			n += 1
	return c / float(maxi(n, 1))

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	var base: Vector3 = _flat_spot(Vector3(-60.0, 0.0, -30.0))
	main._clear_area_of_resources(base, 40.0)
	await frames(2)
	print("  площадка: %s" % str(base))

	# ── A. ПКМ МОНАХОМ ПО РАНЕНОМУ ОТРЯДУ ─────────────────────────────────
	print("\n═════ A. ПКМ МОНАХОМ ПО СВОЕМУ ОТРЯДУ ═════")
	var monk: Unit = _spawn("monk", F, base + Vector3(-12.0, 0.0, 0.0))
	var sq: Array = _squad("warrior", F, base + Vector3(4.0, 0.0, 0.0), 8)
	var men: Array = sq[1]
	await pframes(10)
	# Раненые по-разному: самый тяжёлый — men[3]
	var fracs := [0.7, 0.55, 0.8, 0.35, 0.6, 0.9, 0.5, 0.75]
	for i in range(men.size()):
		_wound(men[i], float(fracs[i]))
	var worst: Unit = men[3]
	sm._clear_selection()
	sm._select_one(monk)
	await frames(2)
	verdict("A1 монах выделен", sm.selected_units.size() == 1 and sm.selected_units[0] == monk)
	# Камера над площадкой и ЗАМОРОЖЕНА: точка экрана считается тем же кадром
	main.set_process(false)
	var cam: Camera3D = sm.camera
	cam.get_parent().set_process(false)
	main._camera.pan_to(Vector3(base.x, 0.0, base.z))
	main._camera._update_position()
	await frames(2)
	var tgt: Unit = men[1]
	var scr: Vector2 = cam.unproject_position(tgt.global_position + Vector3(0.0, 0.8, 0.0))
	var pick = sm._pick_at(scr, sm.order_pick_mask())["target"]
	verdict("A2 луч ПКМ находит под курсором своего мечника",
		pick != null and pick is Unit and (pick as Unit).squad_id == int(sq[0]),
		"под курсором: %s" % (String((pick as Node).name) if pick != null else "ничего"))
	var orders0: int = int(sm.monk_heal_orders)
	var ho0: int = int(monk.get("heal_orders"))
	_mouse(MOUSE_BUTTON_RIGHT, true, scr)
	await frames(1)
	_mouse(MOUSE_BUTTON_RIGHT, false, scr)
	await frames(3)
	main.set_process(true)
	cam.get_parent().set_process(true)
	verdict("A3 ПКМ прочитан как приказ лечить (SelectionManager → Monk.command_heal)",
		int(sm.monk_heal_orders) == orders0 + 1 and int(monk.get("heal_orders")) == ho0 + 1
		and int(monk.get("_order_sid")) == int(sq[0]),
		"приказов %d → %d, у монаха %d → %d, отряд приказа %d (ждали %d)" % [
			orders0, int(sm.monk_heal_orders), ho0, int(monk.get("heal_orders")),
			int(monk.get("_order_sid")), int(sq[0])])
	# Монах подходит на дистанцию каста к самому раненому
	var came := false
	var w := 0
	while w < 60 * 12:
		await get_tree().physics_frame
		w += 1
		if _xz(monk.global_position, worst.global_position) <= _UCfg.MONK_CAST_RANGE + 0.6:
			came = true
			break
	verdict("A4 монах подошёл к отряду на дистанцию каста", came,
		"за %d физкадров, каст %.1f м" % [w, _UCfg.MONK_CAST_RANGE])

	# ── B. ФОКУСНОЕ ЛЕЧЕНИЕ ───────────────────────────────────────────────
	print("\n═════ B. ФОКУС: САМЫЙ РАНЕНЫЙ — ДО 100 %, ПОТОМ СЛЕДУЮЩИЙ ═════")
	var first_full: Unit = null
	var others_still_hurt := false
	var switched := false
	var t := 0
	var healed_all := false
	while t < 60 * 120:
		await get_tree().physics_frame
		t += 1
		if first_full == null:
			for u in men:
				if (u as Unit).current_health >= (u as Unit).max_health - 0.01:
					first_full = u
					others_still_hurt = not _all_full(men)
					break
		elif not switched:
			var ht = monk.get("heal_target")
			if ht != null and is_instance_valid(ht) and ht != first_full:
				switched = true
		if _all_full(men):
			healed_all = true
			break
	verdict("B1 первый вылеченный до 100 % — самый раненый (фокус, а не размазывание)",
		first_full == worst and others_still_hurt,
		"первым вылечен %s, остальные ещё ранены=%s" % [
			("самый раненый" if first_full == worst else "другой"), str(others_still_hurt)])
	verdict("B2 после первого монах переключился на следующего", switched)
	verdict("B3 весь отряд доведён до 100 %", healed_all, "за %d физкадров" % t)
	verdict("B4 приказ лечить не снят — монах сопровождает отряд",
		int(monk.get("_order_sid")) == int(sq[0]))

	# ── C. СОПРОВОЖДЕНИЕ ──────────────────────────────────────────────────
	print("\n═════ C. ОТРЯД УШЁЛ — МОНАХ СЛЕДОМ ═════")
	var far: Vector3 = base + Vector3(26.0, 0.0, 0.0)
	for i in range(men.size()):
		(men[i] as Unit).command_move(GameManager.land_target(far + Vector3(0.0, 0.0, float(i) * 0.6 - 2.0)),
			false, Vector3.ZERO, true)
	var followed := false
	var w2 := 0
	while w2 < 60 * 40:
		await get_tree().physics_frame
		w2 += 1
		var c: Vector3 = _centre(men)
		if _xz(c, far) < 4.0 and _xz(monk.global_position, c) < _UCfg.MONK_HEAL_RADIUS:
			followed = true
			break
	verdict("C1 монах догнал ушедший отряд (в радиусе лечения)", followed,
		"за %d физкадров, до центра %.1f м" % [w2, _xz(monk.global_position, _centre(men))])
	_wound(men[5], 0.5)
	var re := false
	var w3 := 0
	while w3 < 60 * 25:
		await get_tree().physics_frame
		w3 += 1
		if (men[5] as Unit).current_health > (men[5] as Unit).max_health * 0.6:
			re = true
			break
	verdict("C2 раненого в сопровождаемом отряде лечит без нового приказа", re, "за %d физкадров" % w3)
	monk.command_move(GameManager.land_target(base + Vector3(-10.0, 0.0, 8.0)), false, Vector3.ZERO, false, true)
	await pframes(2)
	verdict("C3 приказ на движение снимает приказ лечить", int(monk.get("_order_sid")) == 0)

	# ── D. МНОГОЦЕЛЕВОЙ ТАКТ — ПОЛНЫЙ КВАНТ КАЖДОМУ ───────────────────────
	print("\n═════ D. МНОГОЦЕЛЕВОЙ ТАКТ ═════")
	for c in ["1a", "1b", "1c", "1d", "2a", "2b", "2c", "2d"]:
		GameManager.research_upgrade(F, _Forge.node_id("monk", c))
	var spot2: Vector3 = base + Vector3(-20.0, 0.0, 10.0)
	var sq2: Array = _squad("spearman", F, spot2, 4)
	var men2: Array = sq2[1]
	await pframes(4)
	monk.global_position = GameManager.land_target(spot2 + Vector3(1.6, 0.0, 0.0))
	monk.sync_row()
	await pframes(2)
	for u in men2:
		_wound(u, 0.3)
	monk.call("command_heal", men2[0])
	var quantum: float = (men2[0] as Unit).max_health * float(monk.call("heal_tick_sec")) \
		/ _UCfg.MONK_HEAL_SEC_PER_MAN * float(monk.call("heal_amount_mult"))
	var before: Array = []
	for u in men2:
		before.append((u as Unit).current_health)
	var gains: Array = []
	var w4 := 0
	while w4 < 60 * 10:
		await get_tree().physics_frame
		w4 += 1
		var any := false
		gains = []
		for i in range(men2.size()):
			var g: float = (men2[i] as Unit).current_health - float(before[i])
			gains.append(snappedf(g, 0.01))
			if g > 0.01:
				any = true
		if any:
			break
	var touched := 0
	var full_quantum := true
	for g in gains:
		if float(g) > 0.01:
			touched += 1
			if absf(float(g) - quantum) > quantum * 0.15:
				full_quantum = false
	verdict("D1 «Благодать»: за один такт лечатся несколько целей", touched >= 2,
		"целей %d, прибавки %s" % [touched, str(gains)])
	verdict("D2 каждой цели — ПОЛНЫЙ квант одиночного лечения (%.1f), а не доля" % quantum,
		full_quantum and touched >= 2, "прибавки %s" % str(gains))
	_finish()
