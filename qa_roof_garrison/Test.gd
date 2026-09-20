extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_roof_garrison — ЛУЧНИКИ НА КРЫШАХ БАРАКОВ И КРЕПОСТИ (ТЗ 14.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A БАРАКИ   — отряд из 30 лучников садится на крышу: 30 спрайтов плотной
##                сеткой на скате крыши, огонь с баффом высоты (+30 % дальности
##                и урона), залп и снайперы работают с крыши (прямая быстрая
##                стрела, свой звук, «раз-два-три», цели за дальностью отряда),
##                пехоту крыша не берёт, выгрузка ставит всех на землю у ворот.
##   B КРЕПОСТЬ — два отряда (60): 30 в центре настила, по 15 на флангах выше,
##                ряды назад по Z (сортировка), третий стрелковый — отказ, а
##                пехота в лазарет — да; оба отряда стреляют; ПКМ-выгрузка
##                снимает только крышу.
##   C ЭКОНОМИКА — не больше трёх крепостей, цена ×4 за каждую следующую.
## Числа — из конфига (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_roof_garrison/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _ArrowS := preload("res://scripts/Arrow.gd")
const _ArcherS := preload("res://scripts/Archer.gd")
const _BB := preload("res://scripts/BillboardUtil.gd")

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(500.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 500 с")
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
	print("\n═════ ИТОГ qa_roof_garrison: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var px: float = at.x - float(i / cols) * 0.9
		var pz: float = at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35
		var u: Unit = _spawn(kind, fac, Vector3(px, 0.0, pz))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _kill_all(arr: Array) -> void:
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e12)

func _alive(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _inside(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and (u as Unit).garrisoned:
			n += 1
	return n

func _place(b: Building, at: Vector3) -> void:
	b.faction = F
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

## «Застрял в здании»: глубже линии ворот больше чем на метр (в сторону
## центра постройки) и внутри её ширины по рисунку. Сама точка ворот — законное
## место выхода, по ней и толпится очередь
func _in_walls(b: Building, gp: Vector3) -> bool:
	var bp: Vector3 = b.global_position
	var gate: Vector3 = b._gate_position()
	var g2 := Vector2(gate.x - bp.x, gate.z - bp.z)
	var gd: float = g2.length()
	if gd < 0.01:
		return false
	var dir := g2 / gd
	var rel := Vector2(gp.x - bp.x, gp.z - bp.z)
	var depth: float = rel.dot(dir)
	var lateral: float = absf(rel.x * dir.y - rel.y * dir.x)
	var half_w: float = b._draw_half_w if b._draw_half_w > 0.0 else b.build_size.x * 0.5
	return depth < gd - 1.0 and depth > -gd and lateral < half_w * 0.6

## Иконки найма в панели: unit_id → кнопка (по пути текстуры, как в qa_keep_elite)
func _panel_buttons(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Button:
			out.append(c)
		if c is Control:
			_panel_buttons(c, out)

func _panel_icons(hud) -> Dictionary:
	var res: Dictionary = {}
	var all: Array = []
	_panel_buttons(hud.button_container, all)
	for uid in ["spearman", "warrior", "archer", "worker", "monk"]:
		var path: String = String(hud.UNIT_ICONS.get(uid, ""))
		if path == "":
			continue
		for bt in all:
			for ch in (bt as Button).get_children():
				var tr := ch as TextureRect
				if tr != null and tr.texture != null and tr.texture.resource_path == path:
					res[uid] = bt
	return res

func _rank_button(hud) -> Button:
	var all: Array = []
	_panel_buttons(hud.button_container, all)
	for bt in all:
		if (bt as Button).name == "KeepRankButton":
			return bt as Button
	return null

## Дождаться, пока весь отряд зайдёт (по garrisoned), потолок в физкадрах
func _wait_inside(men: Array, cap_frames: int = 1800) -> int:
	var w := 0
	while w < cap_frames:
		await get_tree().physics_frame
		w += 1
		if _inside(men) == _alive(men):
			break
	return w

func _research(cell: String) -> bool:
	return GameManager.research_upgrade(F, _Forge.node_id("archer", cell))

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	AudioManager.sfx_trace = true
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	# Снайперы и залп — чтобы проверить их с крыши
	for c in ["1a", "1b", "1c", "1d", "2a", "2b", "2c", "2d"]:
		_research(c)
	await _a_barracks()
	await _b_castle()
	await _c_economy()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. БАРАКИ
# ═════════════════════════════════════════════════════════════════════════════
func _a_barracks() -> void:
	print("\n═════ A. КРЫША БАРАКОВ ═════")
	var bp := Vector3(60.0, 0.0, -30.0)
	main._clear_area_of_resources(bp, 50.0)
	var b: Building = Barracks.new()
	_place(b, bp)
	await pframes(6)
	verdict("A0 бараки — Castle-гарнизон, но не крепость, лимит 1 стрелковый отряд",
		b is Castle and not b.is_stronghold() and b.garrison_limit() == 1
		and b.roof_accepts("archer") and not b.garrison_accepts("spearman"))
	# ── ПАНЕЛЬ БАРАКОВ — СВОЯ, НЕ ЗАМКОВАЯ (15.09.2026) ────────────────────
	# Бараки — Castle, и без is_stronghold() в ветке HUD они получали панель
	# крепости: рыцарь с лычками, рабочий, монах, а копейщиков не было вовсе
	var sm0 = main.selection_manager
	sm0._clear_selection()
	sm0._select(b)
	GameManager.on_selection_changed(sm0.selected_units, true)
	await pframes(3)
	var icons: Dictionary = _panel_icons(main.hud)
	verdict("A0б панель бараков: копейщик и мечник есть, рабочего/монаха/кнопки ранга нет",
		icons.has("spearman") and icons.has("warrior") and not icons.has("worker")
		and not icons.has("monk") and _rank_button(main.hud) == null,
		"иконки найма: %s" % str(icons.keys()))
	sm0._clear_selection()
	# Пехоту крыша не берёт
	var sp: Array = _squad("spearman", F, bp + Vector3(0, 0, 10), 8)
	verdict("A1 копейщиков бараки не принимают", not b.request_garrison(int(sp[0])))
	_kill_all(sp[1])
	var ar: Array = _squad("archer", F, bp + Vector3(0, 0, 10), 30)
	await pframes(40)
	verdict("A2 отряд лучников принят", b.request_garrison(int(ar[0])))
	var w: int = await _wait_inside(ar[1])
	verdict("A3 все 30 зашли на крышу", _inside(ar[1]) == 30 and not b.garrison.is_empty(),
		"внутри %d за %d физкадров" % [_inside(ar[1]), w])
	await frames(4)
	var roof = b._roof
	# ТЗ 19.09.2026 (п. 4): на крыше бараков ВИДНЫ ROOF_VISIBLE (15), остальные — резерв
	verdict("A4 на крыше %d спрайтов (резерв внутри)" % int(_UCfg.ROOF_VISIBLE["barracks"]),
		int(roof.shown()) == int(_UCfg.ROOF_VISIBLE["barracks"]), "%d" % int(roof.shown()))
	# Геометрия: все спрайты внутри рисунка по ширине, выше половины рисунка,
	# ряды уходят назад по Z (сортировка), шаг вбок компактный
	var spr := b.get_node_or_null("BuildingSprite") as MeshInstance3D
	var top: float = (spr.mesh as QuadMesh).size.y * _BB.V_STRETCH if spr != null else b.build_size.y * 2.0
	var half_w: float = b._draw_half_w if b._draw_half_w > 0.0 else b.build_size.x * 0.5
	var geo_ok := true
	var worst := ""
	var xs: Array = []
	for i in range(30):
		var p: Vector3 = roof.slot_local(i)
		xs.append(p.x)
		if absf(p.x - b._draw_cx) > half_w * 0.95 or p.y < top * 0.30 or p.y > top:
			geo_ok = false
			worst = "место %d: x=%.2f y=%.2f (top %.2f, half %.2f)" % [i, p.x, p.y, top, half_w]
	var z_ok: bool = roof.slot_local(0).z > roof.slot_local(6).z and roof.slot_local(6).z > roof.slot_local(12).z
	var dx: float = absf(float(xs[1]) - float(xs[0]))
	verdict("A5 сетка на скате крыши: в ширине рисунка, на скате (≥ 0.30 высоты), ряды назад по Z, шаг ≤ 0.5 м",
		geo_ok and z_ok and dx <= 0.5, worst if not geo_ok else "шаг %.2f м, z рядов %.2f/%.2f/%.2f" % [
			dx, roof.slot_local(0).z, roof.slot_local(6).z, roof.slot_local(12).z])
	# Бафф дальности
	var base_r: float = 0.0
	var snipers := 0
	for u in ar[1]:
		if (u as Archer).is_sniper():
			snipers += 1
		else:
			base_r = maxf(base_r, (u as Unit).attack_range)
	verdict("A6 снайперы на крыше сохранены (%d)" % _UCfg.SNIPE_SQUAD_BASE, snipers == _UCfg.SNIPE_SQUAD_BASE, "%d" % snipers)
	var fr: float = float(roof.fire_range())
	verdict("A7 дальность огня с крыши = лук × %.2f (снайпер 25 → %.1f)" % [
		_UCfg.GARRISON_RANGE_MULT, _UCfg.SNIPE_RANGE * _UCfg.GARRISON_RANGE_MULT],
		is_equal_approx(fr, _UCfg.SNIPE_RANGE * _UCfg.GARRISON_RANGE_MULT),
		"огонь %.1f, обычный лук %.1f" % [fr, base_r])
	# Огонь: гоблины на 0.85 обычной дальности с баффом (за голой дальностью)
	var d_foe: float = base_r * _UCfg.GARRISON_RANGE_MULT * 0.85
	var foes: Array = _squad("goblin_spearman", GF, bp + Vector3(d_foe, 0, 0), 12, 4)
	for g in foes[1]:
		(g as Unit).set_tick(false)
	var hp0 := 0.0
	for g in foes[1]:
		hp0 += (g as Unit).current_health
	var shots0: int = int(roof.shots_fired)
	var snipe0: int = _ArcherS.snipe_shots
	var primes0: int = GameManager.volley_primes
	var dmg_ok := true
	var dmg_seen := 0
	var straight_ok := true
	var snipe_seen := 0
	var frames_with_shots: Dictionary = {}
	var last_shots: int = shots0
	for f in range(60 * 6):
		await get_tree().physics_frame
		var now: int = int(roof.shots_fired)
		if now > last_shots:
			frames_with_shots[f] = now - last_shots
			last_shots = now
		# Снаряд без узла (BigStand-5, этап 3): полёт — запись ядра
		for frec in GameManager.flight_records():
			var sh = frec["shooter"]
			if sh == null or not is_instance_valid(sh) or not (sh is Unit) or not (sh as Unit).garrisoned:
				continue
			if bool(frec["snipe"]):
				snipe_seen += 1
				if float(frec["arc"]) != 0.0:
					straight_ok = false
			else:
				dmg_seen += 1
				var base: float = (sh as Unit)._strike_damage() + (sh as Unit)._upgrade_damage_bonus()
				if absf(float(frec["damage"]) - base * _UCfg.GARRISON_DAMAGE_MULT) > 0.05:
					dmg_ok = false
	var hp1 := 0.0
	for g in foes[1]:
		if is_instance_valid(g) and not (g as Unit).is_dead():
			hp1 += (g as Unit).current_health
	verdict("A8 крыша стреляет по цели за голой дальностью лука (бафф +30 %)",
		int(roof.shots_fired) - shots0 > 0 and hp1 < hp0,
		"выстрелов %d, запас врага %.0f → %.0f, цель на %.1f м при луке %.1f" % [
			int(roof.shots_fired) - shots0, hp0, hp1, d_foe, base_r])
	verdict("A9 урон стрелы с крыши = обычный × %.2f" % _UCfg.GARRISON_DAMAGE_MULT,
		dmg_seen > 0 and dmg_ok, "проверено стрел %d" % dmg_seen)
	verdict("A10 залп с крыши: окно залпа открывается, выстрелы пачками",
		GameManager.volley_primes > primes0 and frames_with_shots.size() > 0
		and frames_with_shots.values().max() >= 5,
		"праймов +%d, пиковый кадр %d выстрелов" % [GameManager.volley_primes - primes0,
			frames_with_shots.values().max() if not frames_with_shots.is_empty() else 0])
	verdict("A11 снайперы стреляют с крыши прямой стрелой со своим звуком",
		_ArcherS.snipe_shots > snipe0 and snipe_seen > 0 and straight_ok
		and int(AudioManager.sfx_trace_counts.get("snipe_shot", 0)) > 0,
		"снайперских %d, летящих замечено %d" % [_ArcherS.snipe_shots - snipe0, snipe_seen])
	_kill_all(foes[1])
	await pframes(4)
	# Снайперская дальность с крыши: одиночка-беглец на 30 м — за 25, в 32.5
	var runner: Unit = _spawn("goblin_spearman", GF, bp + Vector3(30.0, 0, 3.0))
	runner.begin_retreat()
	runner.set_tick(false)
	var s0: int = _ArcherS.snipe_shots
	for _f in range(60 * 5):
		await get_tree().physics_frame
		if not is_instance_valid(runner) or runner.is_dead():
			break
	verdict("A12 беглец на 30 м (за 25 снайпера, в %.1f с крыши) снят снайпером" % (
		_UCfg.SNIPE_RANGE * _UCfg.GARRISON_RANGE_MULT),
		(not is_instance_valid(runner) or runner.is_dead()) and _ArcherS.snipe_shots > s0,
		"снайперских +%d" % (_ArcherS.snipe_shots - s0))
	# Выгрузка
	var gate: Vector3 = b._gate_position()
	verdict("A13 выгрузка: release_all отвечает true", b.release_all())
	await pframes(90)
	var on_ground := 0
	var near := 0
	var stuck := 0
	for u in ar[1]:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		if not (u as Unit).garrisoned and (u as Unit).visible:
			on_ground += 1
		var gp: Vector3 = (u as Unit).global_position
		if Vector2(gp.x - gate.x, gp.z - gate.z).length() < 14.0:
			near += 1
		if _in_walls(b, gp):
			stuck += 1
	verdict("A14 все живые на земле у ворот, никто не застрял в здании",
		on_ground == _alive(ar[1]) and near == _alive(ar[1]) and stuck == 0
		and b.garrison.is_empty() and int(roof.shown()) == 0,
		"на земле %d, у ворот %d, в здании %d из %d; спрайтов %d" % [
			on_ground, near, stuck, _alive(ar[1]), int(roof.shown())])
	_kill_all(ar[1])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# B. КРЕПОСТЬ
# ═════════════════════════════════════════════════════════════════════════════
func _b_castle() -> void:
	print("\n═════ B. КРЫША КРЕПОСТИ ═════")
	var cp := Vector3(-60.0, 0.0, -30.0)
	main._clear_area_of_resources(cp, 60.0)
	var c: Castle = Castle.new()
	_place(c, cp)
	await pframes(6)
	verdict("B0 крепость: на крыше до %d стрелковых отрядов, лазарет прежний" % _UCfg.ROOF_SQUADS["castle"],
		c.is_stronghold() and c.roof_squads_max() == 2 and c.garrison_limit() >= 3)
	var a1: Array = _squad("archer", F, cp + Vector3(0, 0, 12), 30)
	var a2: Array = _squad("archer", F, cp + Vector3(6, 0, 12), 30)
	var a3: Array = _squad("archer", F, cp + Vector3(12, 0, 12), 10)
	var sp: Array = _squad("spearman", F, cp + Vector3(-8, 0, 12), 10)
	await pframes(40)
	var ok1: bool = c.request_garrison(int(a1[0]))
	var ok2: bool = c.request_garrison(int(a2[0]))
	var ok3: bool = c.request_garrison(int(a3[0]))
	var oks: bool = c.request_garrison(int(sp[0]))
	verdict("B1 два стрелковых на крышу — да, третий — нет, пехота в лазарет — да",
		ok1 and ok2 and not ok3 and oks, "%s %s %s %s" % [str(ok1), str(ok2), str(ok3), str(oks)])
	_kill_all(a3[1])
	var men: Array = a1[1] + a2[1]
	var w: int = await _wait_inside(men, 2400)
	await _wait_inside(sp[1], 600)
	await frames(4)
	var roof = c._roof
	# ТЗ 19.09.2026 (п. 4): 60 внутри, видимых — ROOF_VISIBLE (40)
	var vis_c: int = int(_UCfg.ROOF_VISIBLE["castle"])
	verdict("B2 все 60 лучников внутри, на крыше видны %d" % vis_c, _inside(men) == 60 and int(roof.shown()) == vis_c,
		"внутри %d, спрайтов %d, за %d физкадров" % [_inside(men), int(roof.shown()), w])
	# Раскладка (ТЗ 19.09): 22 в центре двумя половинками, 9 + 9 по флангам, фланги выше
	var spr := c.get_node_or_null("BuildingSprite") as MeshInstance3D
	var top: float = (spr.mesh as QuadMesh).size.y * _BB.V_STRETCH if spr != null else c.build_size.y * 2.0
	var half_w: float = c._draw_half_w if c._draw_half_w > 0.0 else c.build_size.x * 0.5
	var centre_ok := true
	var left := 0
	var right := 0
	var flank_higher := true
	var cy: float = roof.slot_local(0).y
	var ccols: int = int(roof.KEEP_CENTRE_COLS)
	var cmen: int = int(roof.KEEP_CENTRE_MEN)
	for i in range(vis_c):
		var p: Vector3 = roof.slot_local(i)
		if i < cmen:
			if absf(p.x - c._draw_cx) > half_w * 0.6 or p.y < top * 0.35 or p.y > top:
				centre_ok = false
		else:
			if p.x - c._draw_cx < -half_w * 0.4:
				left += 1
			elif p.x - c._draw_cx > half_w * 0.4:
				right += 1
			if p.y < cy + 0.3:
				flank_higher = false
	verdict("B3 раскладка: %d в центре настила, 9 слева и 9 справа на башнях выше" % cmen,
		centre_ok and cmen == 22 and left == 9 and right == 9 and flank_higher,
		"центр %s, слева %d, справа %d, фланги выше=%s" % [str(centre_ok), left, right, str(flank_higher)])
	var zs_ok: bool = roof.slot_local(0).z > roof.slot_local(ccols).z and roof.slot_local(ccols).z > roof.slot_local(ccols * 2).z
	verdict("B4 ряды центра уходят назад по Z (сортировка перекрытия)", zs_ok,
		"z %.2f / %.2f / %.2f" % [roof.slot_local(0).z, roof.slot_local(ccols).z, roof.slot_local(ccols * 2).z])
	# Оба отряда стреляют
	var fr: float = float(roof.fire_range())
	var foes: Array = _squad("goblin_spearman", GF, cp + Vector3(fr * 0.5, 0, 0), 16, 4)
	for g in foes[1]:
		(g as Unit).set_tick(false)
	var by_sid: Dictionary = {}
	for f in range(60 * 6):
		await get_tree().physics_frame
		for frec in GameManager.flight_records():
			var sh = frec["shooter"]
			if sh == null or not is_instance_valid(sh) or not (sh is Unit):
				continue
			by_sid[(sh as Unit).squad_id] = true
	verdict("B5 стреляют оба отряда с крыши",
		by_sid.has(int(a1[0])) and by_sid.has(int(a2[0])),
		"стреляли отряды %s" % str(by_sid.keys()))
	_kill_all(foes[1])
	await pframes(4)
	# ПКМ-выгрузка снимает только крышу
	var sm = main.selection_manager
	sm._clear_selection()
	var rel: bool = sm._try_release_tower(c)
	await pframes(90)
	verdict("B6 выгрузка с крепости: лучники на земле, копейщики остались в лазарете",
		rel and _inside(men) == 0 and _inside(sp[1]) == _alive(sp[1]) and int(roof.shown()) == 0,
		"лучников внутри %d, копейщиков внутри %d из %d" % [_inside(men), _inside(sp[1]), _alive(sp[1])])
	var stuck := 0
	var where := ""
	var gate: Vector3 = c._gate_position()
	for u in men:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var gp: Vector3 = (u as Unit).global_position
		if _in_walls(c, gp):
			stuck += 1
			where += " (dx %.2f dz %.2f, gar=%s, st=%d)" % [gp.x - cp.x, gp.z - cp.z,
				str((u as Unit).garrisoned), (u as Unit).state]
	verdict("B7 никто из 60 не застрял в стенах крепости", stuck == 0,
		"в стенах %d%s; ворота dz %.2f, полуширина %.2f, глубина %.2f" % [
			stuck, where, gate.z - cp.z, half_w, c.build_size.z])
	c.release_garrison(int(sp[0]))
	_kill_all(men)
	_kill_all(sp[1])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# C. ЭКОНОМИКА КРЕПОСТЕЙ
# ═════════════════════════════════════════════════════════════════════════════
func _c_economy() -> void:
	print("\n═════ C. НЕ БОЛЬШЕ ТРЁХ КРЕПОСТЕЙ, ЦЕНА РАСТЁТ ═════")
	var base: Dictionary = _UCfg.building_cost("castle")
	var n0: int = GameManager.castle_total(F)
	var c1: Dictionary = GameManager.build_cost_for(F, "castle")
	var k1: float = pow(_UCfg.CASTLE_COST_MULT, float(n0))
	var ok1 := true
	for k in base.keys():
		if absf(float(c1[k]) - float(base[k]) * k1) > 0.01:
			ok1 = false
	verdict("C1 цена крепости при %d стоящих = база × %.0f^%d" % [n0, _UCfg.CASTLE_COST_MULT, n0], ok1,
		"золото %.0f при базе %.0f" % [float(c1.get(Constants.RESOURCE_GOLD, 0.0)),
			float(base.get(Constants.RESOURCE_GOLD, 0.0))])
	# Достраиваем до потолка
	var made: Array = []
	while GameManager.castle_total(F) < _UCfg.CASTLE_MAX_COUNT:
		var c: Castle = Castle.new()
		_place(c, Vector3(-120.0 + float(made.size()) * 25.0, 0.0, 40.0))
		made.append(c)
		await pframes(2)
	var c3: Dictionary = GameManager.build_cost_for(F, "castle")
	verdict("C2 при трёх крепостях цена = база × %.0f^3 и строить нельзя" % _UCfg.CASTLE_COST_MULT,
		not GameManager.castle_allowed(F)
		and absf(float(c3.get(Constants.RESOURCE_GOLD, 0.0))
			- float(base.get(Constants.RESOURCE_GOLD, 0.0)) * pow(_UCfg.CASTLE_COST_MULT, 3.0)) < 0.01,
		"золото %.0f, можно=%s" % [float(c3.get(Constants.RESOURCE_GOLD, 0.0)), str(GameManager.castle_allowed(F))])
	var wk: Unit = _spawn("worker", F, Vector3(-40.0, 0.0, 40.0))
	var gold0: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
	GameManager.try_worker_build(wk, "castle", [])
	await pframes(2)
	# Крепости капают золотом каждую секунду — ловим только СПИСАНИЕ
	verdict("C3 заказ четвёртой крепости отклонён: ресурсы не списаны",
		ResourceManager.get_amount(F, Constants.RESOURCE_GOLD) >= gold0 - 0.01)
	for c in made:
		if is_instance_valid(c):
			c.take_damage(1.0e12)
	_kill_all([wk])
	await pframes(4)
