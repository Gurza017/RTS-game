extends Node

## ═══════════════════════════════════════════════════════════════════════════
## A/B ЧЕРЕДОВАНИЕМ: ВИЗУАЛЬНЫЙ ПРОХОД АРМИИ В ЯДРЕ (этап E, 09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Тот же метод, что у qa_ab (правка меньше миллисекунды подтверждается
## только чередованием база/правка на одной живой сцене), но мерится КАДР
## ЛОГИКИ (perf_config.vis_meter — весь GameManager._process с тиком бойцов,
## догоном, кольцами, полосками и подачей буферов), а не физтик.
##
## Сцена: 2000 копейщиков игрока маршем туда-обратно + 2000 стоящих чужих;
## ВСЯ армия игрока выделена (2000 колец и теней), полоски здоровья подняты
## по Alt (4000 полосок). Это худший случай прежнего GDScript-пути: каждый
## кадр — draw_position и запись 24 float на каждого выделенного.
##
## Ручки: anim_core (кадр ленты листает ядро), decal_core (кольца/тени/
## полоски ведёт ядро). Порядок фаз в раунде переворачивается.
## Запуск: godot --headless --path . res://qa_visab/Test.tscn -- units=2000

const _Opt := preload("res://scripts/perf_config.gd")

const KNOB_ANIM := 0
const KNOB_DECAL := 1
const KNOB_BOTH := 2
const KNOB_POSE := 3
const PHASE_FRAMES := 120
const ROUNDS := 4
const SQUAD_SIZE := 50
const COLS := 10
const GAP := 0.9

var main = null
var UNITS := 2000
var _units: Array = []
var _foes: Array = []
var _march_t: int = 0
var _march_dir: int = 1

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с"); get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn_side(fac: int, at: Vector3, scene: String) -> Array:
	var out: Array = []
	var squads: int = maxi(UNITS / SQUAD_SIZE, 1)
	var per_row: int = int(ceil(sqrt(float(squads))))
	for s in range(squads):
		var sid: int = GameManager.new_squad(fac, "spearman")
		var bx: float = at.x + float(s % per_row) * 12.0
		var bz: float = at.z + float(s / per_row) * 10.0
		var slots: Array = []
		for i in range(SQUAD_SIZE):
			var u: Unit = load(scene).instantiate()
			u.faction = fac
			main.world_add(u)
			u.global_position = Vector3(bx + float(i % COLS) * GAP, 0.0, bz + float(i / COLS) * GAP)
			u.sync_row()
			GameManager.add_to_squad(sid, u)
			out.append(u)
			slots.append(u.global_position)
		GameManager.squad_set_formation(sid, slots, Vector3(0, 0, 1), false)
	return out

func _set_knob(knob: int, on: bool) -> void:
	match knob:
		KNOB_ANIM: _Opt.anim_core = on
		KNOB_DECAL: _Opt.decal_core = on
		KNOB_BOTH:
			_Opt.anim_core = on
			_Opt.decal_core = on
		KNOB_POSE: _Opt.pose_events = on

## Марш туда-обратно: приказ раз в 6 с, чтобы армия всё время шла
func _keep_marching() -> void:
	_march_t -= 1
	if _march_t > 0:
		return
	_march_t = 360
	_march_dir = -_march_dir
	var off := Vector3(float(_march_dir) * 25.0, 0.0, 0.0)
	for u in _units:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).command_move((u as Node3D).global_position + off)

func _measure(knob: int, on: bool) -> Array:
	_set_knob(knob, on)
	await pframes(20)
	_Opt.vis_reset()
	_Opt.tick_reset()
	var t0: int = Time.get_ticks_usec()
	for _i in range(PHASE_FRAMES):
		await get_tree().process_frame
		_keep_marching()
	var wall: float = float(Time.get_ticks_usec() - t0) / float(PHASE_FRAMES) * 0.001
	return [_Opt.vis_ms(), wall, _Opt.tick_ms()]

func _avg(a: Array) -> float:
	var s := 0.0
	for v in a: s += float(v)
	return s / maxf(float(a.size()), 1.0)

func _sleeping() -> int:
	var n := 0
	for u in _units:
		if is_instance_valid(u) and not (u as Unit).draw_on:
			n += 1
	return n

func _ab_block(title: String, knob: int) -> void:
	print("\n═════ %s ═════" % title)
	var base_vis: Array = []; var fix_vis: Array = []
	var base_wall: Array = []; var fix_wall: Array = []
	var base_sleep: Array = []; var fix_sleep: Array = []
	for r in range(ROUNDS):
		var first_on: bool = (r % 2) == 1
		for k in range(2):
			var on: bool = first_on if k == 0 else not first_on
			var m: Array = await _measure(knob, on)
			var sl: int = _sleeping()
			print("  раунд %d %s: кадр логики %.3f мс, кадр стенных часов %.3f мс, физтик %.3f, спят по картинке %d" % [
				r + 1, "ПРАВКА" if on else "база  ", float(m[0]), float(m[1]), float(m[2]), sl])
			if on:
				fix_vis.append(m[0]); fix_wall.append(m[1]); fix_sleep.append(sl)
			else:
				base_vis.append(m[0]); base_wall.append(m[1]); base_sleep.append(sl)
	print("  ИТОГ %s: кадр логики база %.3f → правка %.3f мс (%+.3f); кадр стенных часов %.3f → %.3f мс; спят %d → %d" % [
		title, _avg(base_vis), _avg(fix_vis), _avg(fix_vis) - _avg(base_vis),
		_avg(base_wall), _avg(fix_wall), int(_avg(base_sleep)), int(_avg(fix_sleep))])

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("units="):
			UNITS = maxi(int(s.substr(6)), 50)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(10)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	_units = _spawn_side(Constants.FACTION_PLAYER, Vector3(-80.0, 0.0, -30.0),
		"res://scenes/units/Spearman.tscn")
	_foes = _spawn_side(Constants.FACTION_ENEMY, Vector3(60.0, 0.0, 40.0),
		"res://scenes/units/Spearman.tscn")
	await pframes(30)
	# Вся армия игрока выделена — кольца и тени на каждого
	var sm = main.selection_manager
	sm._clear_selection()
	for u in _units:
		if is_instance_valid(u):
			sm._select(u)
	GameManager.on_selection_changed(sm.selected_units)
	# Полоски — по Alt, на всех
	GameManager.hp_bars_forced = true
	if GameManager.has_method("_refresh_all_hp_bars"):
		GameManager._refresh_all_hp_bars()
	# Прогрев: слоты, привязки, разметка
	_Opt.vis_meter = true
	_Opt.tick_meter = true
	await pframes(120)
	print("\n═════ qa_visab: %d бойцов игрока (выделены все), %d чужих; колец %d, полосок %d ═════" % [
		_units.size(), _foes.size(), GameManager.sel_decals.registered_count(),
		GameManager.hp_bars.registered_count()])
	await _ab_block("A: кадр ленты листает ядро (anim_core)", KNOB_ANIM)
	await _ab_block("B: кольца, тени и полоски ведёт ядро (decal_core)", KNOB_DECAL)
	await _ab_block("C: обе ручки разом", KNOB_BOTH)
	_set_knob(KNOB_BOTH, true)
	await _ab_block("D: поза по событию, а не по расписанию (pose_events)", KNOB_POSE)
	_set_knob(KNOB_POSE, true)
	print("\n=== QA_VISAB DONE ===")
	get_tree().quit()
