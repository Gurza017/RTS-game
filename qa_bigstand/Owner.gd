extends "res://qa_bigstand/Test.gd"
## ═══════════════════════════════════════════════════════════════════════════
## СЦЕНАРИЙ ВЛАДЕЛЬЦА (аудит 19.09.2026): ~1000 своих У ПНЯ С ГНОЛЛАМИ И ТУШАМИ
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: «FPS падает с 60 до 15-20, когда на карте ~10 отрядов (~1000
## юнитов) просто стоят рядом с гноллами или тушами, и в бою». Отличие от
## qa_bigstand: ЖИВАЯ ПАРТИЯ КАК ЕСТЬ — все ИИ (красный, орда, гноллы, резерв,
## охрана) работают, туман включён, стартовые бойцы партии (орда, стражи пней,
## рабочие, овцы) на месте, HUD и выделение армии игрока (кольца). Армия
## игрока — состав qa_bigstand ×scale (10 копейщиков, 8 лучников, 8 мечников,
## 6 монахов ≈ 1090 при scale=1) — ставится в OWN_D метрах от пня партии
## (36 гноллов, 2 тролля), рядом две туши. Три режима ТЗ:
##   A IDLE   — стоят (цель 70 FPS);
##   B MARCH  — марш строем 25 м и обратно (цель 60+);
##   C CLASH  — стенка на стенку: орда (8 отрядов гоблинов, 4 конных) + туши +
##              стая пня против армии игрока (цель 50-60).
## Метрики — те же, что у qa_bigstand (_measure/_summary). Вердиктов нет.
## Запуск: `godot --path . res://qa_bigstand/Owner.tscn -- secs=15 idle=10
## march=10 cap=0 scale=1.0 detail=0 [knob=…]`

const OWN_D := 32.0
var _own_big: Array = []
var _own_horde: Array = []

func _run() -> void:
	seed(7)
	Engine.max_fps = CAP_FPS
	if not DisplayServer.get_name().begins_with("headless"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var opt_inst = _Opt.new()
	for k in _knobs:
		var v: String = String(_knobs[k])
		var cur: Variant = opt_inst.get(k)
		if cur == null:
			print("  ручки %s в perf_config нет" % k)
			continue
		if cur is bool:
			opt_inst.set(k, v == "1" or v == "true")
		elif cur is int:
			opt_inst.set(k, int(v))
		elif cur is float:
			opt_inst.set(k, float(v))
		else:
			opt_inst.set(k, v)
		print("  ручка %s = %s" % [k, str(opt_inst.get(k))])
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(8)
	await pframes(6)
	var headless: bool = DisplayServer.get_name() == "headless"
	var lair = GameManager.troll_lair
	if lair == null or not is_instance_valid(lair):
		print("  пня партии нет — сценарий не поставить")
		get_tree().quit()
		return
	var lp: Vector3 = lair.global_position
	# Армия — к западу от пня (сторона карты), на ровном: чистим лес
	var centre := Vector3(lp.x - OWN_D - 12.0, 0.0, lp.z)
	main._clear_area_of_resources(centre, 60.0)
	var pf: int = Constants.FACTION_PLAYER
	GameManager.pop_limit_enabled = false
	GameManager.finish_research(pf, _Forge.node_id("archer", "1d"))
	GameManager.finish_research(pf, _Forge.node_id("spearman", "1d"))
	var n_sp: int = _UCfg.squad_size("spearman")
	var n_ar: int = _UCfg.squad_size("archer")
	var n_wr: int = _UCfg.squad_size("warrior")
	var k_sp: int = maxi(int(round(10.0 * SCALE)), 1)
	var k_ar: int = maxi(int(round(8.0 * SCALE)), 1)
	var k_wr: int = maxi(int(round(8.0 * SCALE)), 1)
	var k_mk: int = maxi(int(round(6.0 * SCALE)), 1)
	# Три эшелона фронтом на пень (+x): копейщики ближе, за ними мечники,
	# лучники; ширина ряда по z вокруг пня
	var x0: float = lp.x - OWN_D
	for k in range(k_sp):
		_p_sq.append(_squad("spearman", pf, Vector3(x0, 0.0, lp.z - 40.0 + float(k) * 8.0), n_sp, 5, 0.7))
	for k in range(k_wr):
		_p_sq.append(_squad("warrior", pf, Vector3(x0 - 10.0, 0.0, lp.z - 36.0 + float(k) * 9.0), n_wr, 5, 0.75))
	for k in range(k_ar):
		_p_sq.append(_squad("archer", pf, Vector3(x0 - 18.0, 0.0, lp.z - 36.0 + float(k) * 9.0), n_ar, 5, 0.75))
	for k in range(k_mk):
		_p_sq.append(_squad("monk", pf, Vector3(x0 - 24.0, 0.0, lp.z - 12.0 + float(k) * 4.0), 1, 1, 1.0))
	for sq in _p_sq:
		_p_all.append_array(sq[0])
	# Туши — в 30 м к югу от армии (за пределами их агро 18 м)
	var gs: Dictionary = _GobCfg.SQUAD_SIZE
	for k in range(2):
		_own_big.append(_horde("big_goblin", Vector3(x0 - 10.0 + float(k) * 12.0, 0.0, lp.z + 42.0), int(gs["big_goblin"])))
	for sq in _own_big:
		_g_all.append_array(sq[0])
	await pframes(6)
	# Разметка и покой — как после приказа игрока; армия выделена (кольца)
	for sq in _p_sq:
		for u in sq[0]:
			if is_instance_valid(u):
				(u as Unit).command_move((u as Unit).global_position, false, Vector3(1.0, 0.0, 0.0))
	var sm = main.selection_manager
	if sm != null:
		sm.selected_units.clear()
		for u in _p_all:
			sm.selected_units.append(u)
		sm._sel_rebuild()
		GameManager.on_selection_changed(sm.selected_units, true)
	main.focus_camera_on(centre)
	if main._camera != null:
		main._camera._update_position()
		main._camera.set_process(false)
	GameManager.update_view_point(centre, 110.0, 0.5)
	_all = _p_all + _g_all
	var total := 0
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and not (n as Unit).is_dead():
			total += 1
	print("  сцена владельца: своих %d (отрядов %d), туш %d, всего бойцов на карте %d; пень в %.0f м, гноллов у пня %d, троллей %d; ИИ и туман включены" % [
		_alive(_p_all), _p_sq.size(), _alive(_g_all), total, OWN_D,
		int(lair.call("gnolls_alive")), int(lair.call("trolls_alive"))])
	await pframes(WARM)
	# ── A. IDLE ─────────────────────────────────────────────────────────
	var r_idle: Dictionary = await _measure("A IDLE (стоят у пня с гноллами и тушами)", IDLE_SEC, headless, true)
	# ── B. MARCH: 25 м на запад и обратно ───────────────────────────────
	var leg: float = MARCH_SEC / 2.0
	_march(_p_all, Vector3(-25.0, 0.0, 0.0), true)
	await pframes(WARM / 2)
	var r_m1: Dictionary = await _measure("B MARCH (строем 25 м)", leg, headless, true)
	_march(_p_all, Vector3(25.0, 0.0, 0.0), true)
	await pframes(WARM / 2)
	var r_m2: Dictionary = await _measure("B MARCH (обратно)", leg, headless, false)
	_stop_all(_p_all)
	await pframes(WARM / 2)
	# ── C. CLASH: орда с юга + туши + стая пня против армии ─────────────
	for k in range(8):
		_own_horde.append(_horde("goblin_spearman", Vector3(x0 - 40.0 + float(k) * 10.0, 0.0, lp.z + 48.0), int(gs["goblin_spearman"])))
	for k in range(4):
		_own_horde.append(_horde("goblin_rider", Vector3(x0 - 30.0 + float(k) * 12.0, 0.0, lp.z + 60.0), int(gs["goblin_rider"])))
	for sq in _own_horde:
		_g_all.append_array(sq[0])
	_all = _p_all + _g_all
	await pframes(6)
	var foes: Array = _g_all.duplicate()
	for g in lair.get("gnolls"):
		if g != null and is_instance_valid(g):
			foes.append(g)
	_order_attack(_p_sq, foes)
	_order_attack(_own_horde + _own_big, _p_all)
	await pframes(WARM)
	var r_clash: Dictionary = await _measure("C CLASH (стенка на стенку у пня)", CLASH_SEC, headless, true)
	_summary([r_idle, r_m1, r_m2, r_clash], headless)
	get_tree().quit()
