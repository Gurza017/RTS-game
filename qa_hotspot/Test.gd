extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ГДЕ НА САМОМ ДЕЛЕ УХОДИТ КАДР В НАСТОЯЩЕЙ ИГРЕ
## ═══════════════════════════════════════════════════════════════════════════
## Массовые стенды (qa_mass_perf / qa_mass_battle) гоняют ГОЛУЮ армию: без
## тумана войны, без ИИ, без HUD, без зданий и рабочих. Они отвечают на вопрос
## «выдерживает ли логика юнитов масштаб», и отвечают честно — но игрок видит
## другое число, потому что в игре к тику юнитов прибавлено всё остальное.
##
## Этот стенд меряет ИМЕННО ИГРУ: полная сцена Main.tscn со всем содержимым,
## армия нормального боевого размера, камера на войсках. Дальше подсистемы
## ВЫКЛЮЧАЮТСЯ ПО ОДНОЙ, и по разнице видно, чего стоит каждая.
##
## ОКОННЫЙ, не headless: половина вопроса — отрисовка. Вертикальная
## синхронизация снимается, иначе меряется частота монитора (та же ловушка,
## что однажды дала qa_veg ровно 75 к/с до и после четырёхкратного улучшения).
##
## Запуск: godot --path . res://qa_hotspot/Test.tscn -- --count=600

const _OptCfg = preload("res://scripts/perf_config.gd")
const SpearScene = preload("res://scenes/units/Spearman.tscn")
const ArcherScene = preload("res://scenes/units/Archer.tscn")

const SAMPLE_FRAMES := 150

var main = null
var _units: Array = []
var _rows: Array = []
var _n := 600

func _ready() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--count="):
			_n = maxi(1, int(s.substr(8)))
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(20)

	# ── ЗАМЕР 0: ПУСТАЯ КАРТА ───────────────────────────────────────────────
	var cam = main.get("_camera")
	if cam != null:
		cam.set_process(false)
		cam.jump_to(Vector3(0.0, 0.0, 0.0), cam.min_height * 2.0)
	await _frames(20)
	_rows.append(await _sample("0. пустая карта (лес, туман, HUD)"))

	# ── АРМИЯ БОЕВОГО РАЗМЕРА, ДВЕ СТОРОНЫ ──────────────────────────────────
	_spawn(_n)
	await _frames(30)
	_rows.append(await _sample("1. армия стоит"))

	for u in _units:
		var un := u as Unit
		if is_instance_valid(un):
			un.command_move(un.global_position + Vector3(
				30.0 if un.faction == Constants.FACTION_PLAYER else -30.0, 0.0, 0.0))
	await _frames(30)
	_rows.append(await _sample("2. армия идёт"))

	await _frames(120)
	_rows.append(await _sample("3. армия дерётся"))

	# ── УСЛОВИЯ, В КОТОРЫХ ИГРАЕТ ЖИВОЙ ЧЕЛОВЕК ────────────────────────────
	# Отдалённая камера (весь лес в кадре) и выделенная армия — то, как войска
	# водят на самом деле, и то, что видно на скриншотах владельца
	if cam != null:
		cam.jump_to(Vector3(0.0, 0.0, 0.0), cam.max_height)
	await _frames(30)
	_rows.append(await _sample("3a. то же, камера отдалена"))

	# Выделение ставим тем же способом, что и клик игрока: у бойца это
	# set_selected(), а метки рисует общий SelectionDecalRenderer
	for u in _units:
		var un := u as Unit
		if is_instance_valid(un) and un.faction == Constants.FACTION_PLAYER:
			un.set_selected(true)
	await _frames(30)
	_rows.append(await _sample("3b. + армия выделена"))

	# Полоски здоровья над всеми (тумблер Alt)
	GameManager.set_hp_bars_forced(true)
	await _frames(30)
	_rows.append(await _sample("3c. + полоски HP (Alt)"))
	GameManager.set_hp_bars_forced(false)
	if cam != null:
		cam.jump_to(Vector3(0.0, 0.0, 0.0), cam.min_height * 2.0)
	await _frames(20)

	# ── ОТКЛЮЧЕНИЕ ПОДСИСТЕМ ПО ОДНОЙ ───────────────────────────────────────
	# Каждая следующая строка = предыдущая МИНУС ещё одна подсистема. Разница
	# между соседними строками и есть её цена в этом самом бою
	if main.get("enemy_ai") != null:
		main.enemy_ai.set_process(false)
		await _frames(20)
		_rows.append(await _sample("4.   − ИИ противника"))

	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
		await _frames(20)
		_rows.append(await _sample("5.   − туман войны"))

	if main.hud != null:
		main.hud.visible = false
		await _frames(20)
		_rows.append(await _sample("6.   − HUD"))

	# Визуальный тик армии целиком (LOD, поза, запись в MultiMesh)
	for u in _units:
		if is_instance_valid(u):
			(u as Unit).set_process(false)
	await _frames(20)
	_rows.append(await _sample("7.   − визуальный тик юнитов"))

	# И сама логика
	for u in _units:
		if is_instance_valid(u):
			(u as Unit).set_physics_process(false)
	await _frames(20)
	_rows.append(await _sample("8.   − физический тик юнитов"))

	_report()
	get_tree().quit(0)

func _spawn(total: int) -> void:
	var half: int = total / 2
	var world: Node3D = main.world_root()
	for side in range(2):
		var faction: int = Constants.FACTION_PLAYER if side == 0 else Constants.FACTION_ENEMY
		var x0: float = -14.0 if side == 0 else 14.0
		var sid: int = GameManager.new_squad(faction, "spearman")
		for i in range(half):
			# Каждый четвёртый — лучник: у них самый дальнобойный скан целей
			var sc: PackedScene = ArcherScene if (i % 4 == 3) else SpearScene
			var u: Unit = sc.instantiate()
			u.faction = faction
			world.add_child(u)
			u.global_position = Vector3(
				x0 + float(i % 12) * 0.9 * (1.0 if side == 0 else -1.0),
				0.0, float(i / 12) * 0.9 - 12.0)
			u.max_health = 4000.0
			u.current_health = 4000.0
			if i % 40 == 0 and i > 0:
				sid = GameManager.new_squad(faction, "spearman")
			GameManager.add_to_squad(sid, u)
			_units.append(u)

## Один замер: время кадра по часам + счётчики движка + свои метры
func _sample(name: String) -> Dictionary:
	_OptCfg.tick_meter = true
	_OptCfg.vis_meter = true
	_OptCfg.tick_reset()
	_OptCfg.vis_reset()
	var draws := 0.0
	var objs := 0.0
	var t0 := Time.get_ticks_usec()
	for _i in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(SAMPLE_FRAMES)
	_OptCfg.tick_meter = false
	_OptCfg.vis_meter = false
	var alive := 0
	for u in _units:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			alive += 1
	return {
		"name": name, "frame": frame_ms, "fps": 1000.0 / maxf(frame_ms, 0.001),
		"tick": _OptCfg.tick_ms(), "vis": _OptCfg.vis_ms(),
		"draws": draws / float(SAMPLE_FRAMES), "objs": objs / float(SAMPLE_FRAMES),
		"alive": alive,
	}

func _report() -> void:
	var out := PackedStringArray()
	out.append("")
	out.append("═══ КУДА УХОДИТ КАДР В НАСТОЯЩЕЙ ИГРЕ (армия %d, окно, V-Sync снят) ═══" % _n)
	out.append("")
	out.append("  фаза                              кадр    к/с   физтик  визуал  вызовы  живых")
	out.append("  --------------------------------+-------+------+-------+-------+-------+------")
	for r in _rows:
		out.append("  %-32s %5.2f мс %5.0f  %5.2f  %5.2f   %5.0f  %5d" % [
			r["name"], r["frame"], r["fps"], maxf(r["tick"], 0.0),
			maxf(r["vis"], 0.0), r["draws"], r["alive"]])
	out.append("")
	out.append("  «физтик»/«визуал» — только обход армии (лёгкие счётчики).")
	out.append("  Разница между кадром и их суммой — всё остальное: отрисовка,")
	out.append("  туман, ИИ, HUD, здания, звук.")
	out.append("  Строки 4-8: каждая = предыдущая МИНУС одна подсистема.")
	print("\n".join(out))
