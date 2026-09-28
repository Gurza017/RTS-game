extends "res://qa_bigstand/Test.gd"
## ═══════════════════════════════════════════════════════════════════════════
## СЦЕНАРИЙ 4000 (ТЗ 25.09.2026, п. 3): 2500 своих ПРОТИВ 1500 орды/гноллов/троллей
## ═══════════════════════════════════════════════════════════════════════════
## Скриншоты владельца 25.09 (1:53-1:56 партии, FPS 28-34): ~1600 своих в
## замесе с ~800 орды у брода. Стенд ставит ЖИВУЮ ПАРТИЮ КАК ЕСТЬ (все ИИ,
## туман, HUD, кольца выделения — как Owner.tscn), армию игрока PLAYER бойцов
## (копейщики 45 %, лучники 25 %, мечники 25 %, монахи — остаток) у пня партии
## и орду HORDE бойцов (гоблины-копейщики 55 %, всадники 30 %, туши, гноллы,
## тролли пня) напротив. Три фазы: A IDLE, B MARCH (25 м туда-обратно),
## C CLASH — стенка на стенку. Метрики — _measure/_summary базового стенда:
## стена кадра, физтик, кадр логики, GC, часы подсистем (sys_meter),
## при detail=1 — разбор по веткам и родам войск. Вердиктов нет.
## Честный FPS — ТОЛЬКО В ОКНЕ (headless не рисует).
## Запуск: `godot --path . res://qa_bigstand/Four.tscn -- secs=20 idle=8
## march=10 cap=0 player=2500 horde=1500 detail=0 [knob=…]`

const OWN_D := 40.0
var PLAYER := 2500
var HORDE := 1500
var _own_big: Array = []
var _own_horde: Array = []
## ЭКСПЕРИМЕНТЫ РАСКЛАДКИ «ПРОЧЕГО» (этап 3): xphys=1 — PhysicsServer3D
## выключен (клики по пластинам не работают — стенду не нужны), xnode=1 —
## _process снят у всех узлов мира, кроме бойцов (деревья, постройки, овцы)
var XPHYS := 0
var XNODE := 0
## xtop=1 — невидимые дочерние Node3D бойцов переводятся в top_level: шаг
## родителя им не рассылается (гипотеза: flush_transform_notifications в
## конце физшага — это и есть «физколбэк вне тика»)
var XTOP := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("player="):
			PLAYER = maxi(int(s.substr(7)), 10)
		elif s.begins_with("horde="):
			HORDE = maxi(int(s.substr(6)), 10)
		elif s.begins_with("xphys="):
			XPHYS = int(s.substr(6))
		elif s.begins_with("xnode="):
			XNODE = int(s.substr(6))
		elif s.begins_with("xtop="):
			XTOP = int(s.substr(5))
	super._ready()

## Применить эксперименты после постановки сцены; печатает, что снято
func _apply_experiments() -> void:
	if XPHYS == 1:
		PhysicsServer3D.set_active(false)
		print("  ЭКСПЕРИМЕНТ: PhysicsServer3D выключен")
	if XTOP == 1:
		var n_top := 0
		var n_units := 0
		for n in get_tree().get_nodes_in_group("all_units"):
			if not (n is Unit):
				continue
			n_units += 1
			for c in (n as Node).get_children():
				var c3 := c as Node3D
				if c3 != null and not c3.visible:
					c3.top_level = true
					n_top += 1
		print("  ЭКСПЕРИМЕНТ: top_level у %d невидимых дочерних Node3D (%d бойцов)" % [n_top, n_units])
	if XNODE == 1:
		var n_off := 0
		var stack: Array = [main]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for c in node.get_children():
				if c is Unit:
					continue
				stack.append(c)
				if c.is_processing() and c != main and c != main.get("hud") and c != main.get("_camera") \
						and c != main.get("enemy_ai") and c != main.get("goblin_ai") and c != main.get("selection_manager"):
					c.set_process(false)
					n_off += 1
		print("  ЭКСПЕРИМЕНТ: _process снят у %d узлов (кроме бойцов, HUD, камеры, ИИ, выделения)" % n_off)
	var on := 0
	var total := 0
	var stack2: Array = [main]
	while not stack2.is_empty():
		var node: Node = stack2.pop_back()
		for c in node.get_children():
			stack2.append(c)
			total += 1
			if c.is_processing():
				on += 1
	print("  узлов в дереве %d, с _process %d; физ. объектов активных %d, пар %d" % [total, on,
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))])

## Пень партии после постановки сцены (нужен фазе CLASH и наследникам)
var _four_lair = null

func _run() -> void:
	if not await _setup():
		get_tree().quit()
		return
	var headless: bool = DisplayServer.get_name() == "headless"
	await pframes(WARM)
	var r_idle: Dictionary = await _measure("A IDLE (4000 стоят)", IDLE_SEC, headless, true)
	var leg: float = MARCH_SEC / 2.0
	_march(_p_all, Vector3(-25.0, 0.0, 0.0), true)
	await pframes(WARM / 2)
	var r_m1: Dictionary = await _measure("B MARCH (строем 25 м)", leg, headless, true)
	_march(_p_all, Vector3(25.0, 0.0, 0.0), true)
	await pframes(WARM / 2)
	var r_m2: Dictionary = await _measure("B MARCH (обратно)", leg, headless, false)
	_stop_all(_p_all)
	await pframes(WARM / 2)
	_start_clash()
	await pframes(WARM)
	var r_clash: Dictionary = await _measure("C CLASH (2500 на 1500)", CLASH_SEC, headless, true)
	_summary([r_idle, r_m1, r_m2, r_clash], headless)
	get_tree().quit()

## Стенка на стенку: армия на орду, туши и стаю пня; орда и туши — на армию
func _start_clash() -> void:
	var foes: Array = _g_all.duplicate()
	for g in _four_lair.get("gnolls"):
		if g != null and is_instance_valid(g):
			foes.append(g)
	_order_attack(_p_sq, foes)
	_order_attack(_own_horde + _own_big, _p_all)

## Постановка сцены: живая партия, армия у пня, орда напротив. false — пня нет
func _setup() -> bool:
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
	GameManager.call_deferred("thaw_lairs_now")
	await frames(8)
	await pframes(6)
	var lair = GameManager.troll_lair
	if lair == null or not is_instance_valid(lair):
		print("  пня партии нет — сценарий не поставить")
		return false
	_four_lair = lair
	var lp: Vector3 = lair.global_position
	# Армия — к западу от пня, орда — к югу; площадка чистится от леса
	var centre := Vector3(lp.x - OWN_D - 20.0, 0.0, lp.z)
	main._clear_area_of_resources(centre, 90.0)
	main._clear_area_of_resources(Vector3(lp.x - OWN_D - 20.0, 0.0, lp.z + 70.0), 70.0)
	var pf: int = Constants.FACTION_PLAYER
	GameManager.pop_limit_enabled = false
	GameManager.finish_research(pf, _Forge.node_id("archer", "1d"))
	GameManager.finish_research(pf, _Forge.node_id("spearman", "1d"))
	var n_sp: int = _UCfg.squad_size("spearman")
	var n_ar: int = _UCfg.squad_size("archer")
	var n_wr: int = _UCfg.squad_size("warrior")
	var k_sp: int = maxi(int(round(float(PLAYER) * 0.45 / float(n_sp))), 1)
	var k_ar: int = maxi(int(round(float(PLAYER) * 0.25 / float(n_ar))), 1)
	var k_wr: int = maxi(int(round(float(PLAYER) * 0.25 / float(n_wr))), 1)
	var k_mk: int = maxi(PLAYER - k_sp * n_sp - k_ar * n_ar - k_wr * n_wr, 1)
	k_mk = mini(k_mk, 40)
	# Эшелоны фронтом на пень (+x): копейщики, за ними мечники, лучники, монахи;
	# ряды вдоль z по 8 м на отряд, второй ряд каждого рода — на 10 м западнее
	var x0: float = lp.x - OWN_D
	var per_row: int = 12
	for k in range(k_sp):
		_p_sq.append(_squad("spearman", pf, Vector3(x0 - float(k / per_row) * 8.0, 0.0,
			lp.z - 48.0 + float(k % per_row) * 8.0), n_sp, 10, 0.6))
	for k in range(k_wr):
		_p_sq.append(_squad("warrior", pf, Vector3(x0 - 18.0 - float(k / per_row) * 8.0, 0.0,
			lp.z - 48.0 + float(k % per_row) * 8.0), n_wr, 6, 0.75))
	for k in range(k_ar):
		_p_sq.append(_squad("archer", pf, Vector3(x0 - 34.0 - float(k / per_row) * 8.0, 0.0,
			lp.z - 48.0 + float(k % per_row) * 8.0), n_ar, 6, 0.75))
	for k in range(k_mk):
		_p_sq.append(_squad("monk", pf, Vector3(x0 - 48.0 - float(k / per_row) * 3.0, 0.0,
			lp.z - 24.0 + float(k % per_row) * 4.0), 1, 1, 1.0))
	for sq in _p_sq:
		_p_all.append_array(sq[0])
	# Орда — в 60 м к югу (за агро), толпами по рядам
	var gs: Dictionary = _GobCfg.SQUAD_SIZE
	var g_sp: int = int(gs["goblin_spearman"])
	var g_rd: int = int(gs["goblin_rider"])
	var g_bg: int = int(gs["big_goblin"])
	var g_gn: int = int(gs["gnoll"])
	var k_gsp: int = maxi(int(round(float(HORDE) * 0.55 / float(g_sp))), 1)
	var k_grd: int = maxi(int(round(float(HORDE) * 0.30 / float(g_rd))), 1)
	var k_gbg: int = 4
	var k_ggn: int = maxi(int(round(float(HORDE - k_gsp * g_sp - k_grd * g_rd - k_gbg * g_bg) / float(g_gn))), 1)
	var zs: float = lp.z + 64.0
	for k in range(k_gsp):
		_own_horde.append(_horde("goblin_spearman", Vector3(x0 - 60.0 + float(k % 8) * 14.0, 0.0, zs + float(k / 8) * 16.0), g_sp))
	for k in range(k_grd):
		_own_horde.append(_horde("goblin_rider", Vector3(x0 - 60.0 + float(k % 8) * 12.0, 0.0, zs + 34.0 + float(k / 8) * 14.0), g_rd))
	for k in range(k_gbg):
		_own_big.append(_horde("big_goblin", Vector3(x0 - 40.0 + float(k) * 12.0, 0.0, zs + 50.0), g_bg))
	for k in range(k_ggn):
		_own_horde.append(_horde("gnoll", Vector3(x0 + 10.0 + float(k % 6) * 6.0, 0.0, zs + 20.0 + float(k / 6) * 6.0), g_gn))
	_trolls = lair.spawn_guards(4)
	for sq in _own_horde + _own_big:
		_g_all.append_array(sq[0])
	_g_all.append_array(_trolls)
	await pframes(6)
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
	print("  сцена 4000: своих %d (отрядов %d: коп %d, меч %d, лук %d, монахов %d), орды %d (гоб %d×%d, всадн %d×%d, туш %d, гноллов %d×%d, троллей %d), всего бойцов на карте %d; ИИ и туман включены" % [
		_alive(_p_all), _p_sq.size(), k_sp, k_wr, k_ar, k_mk, _alive(_g_all),
		k_gsp, g_sp, k_grd, g_rd, k_gbg, k_ggn, g_gn, _trolls.size(), total])
	_apply_experiments()
	return true
