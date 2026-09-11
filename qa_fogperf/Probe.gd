extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД: ЦЕНА ОДНОГО ПЕРЕСЧЁТА ТУМАНА ВОЙНЫ НА 4000 БОЙЦОВ (09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Пересчёт маски идёт раз в UPDATE_INTERVAL, а не покадрово, поэтому его цена
## в среднем FPS почти не видна — зато целиком ложится в ОДИН кадр и читается
## глазом как микролаг. Зонд меряет этот кадр по частям: сбор источников по
## бойцам (GDScript), штампы и сборка RGBA (ядро), заливка текстуры.
## Вердиктов не печатает — это измеритель. Headless годится: тут нет отрисовки.
##
## Запуск: godot --headless --path . res://qa_fogperf/Probe.tscn -- units=2000

var main = null
var UNITS := 2000
const SQUAD_SIZE := 50
const COLS := 10
const GAP := 0.9

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(180.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился за 180 с")
		get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn_side(fac: int, at: Vector3, scene: String) -> void:
	var squads: int = maxi(UNITS / SQUAD_SIZE, 1)
	var per_row: int = int(ceil(sqrt(float(squads))))
	for s in range(squads):
		var sid: int = GameManager.new_squad(fac, "spearman")
		var bx: float = at.x + float(s % per_row) * 12.0
		var bz: float = at.z + float(s / per_row) * 10.0
		for i in range(SQUAD_SIZE):
			var u: Unit = load(scene).instantiate()
			u.faction = fac
			main.world_add(u)
			u.global_position = Vector3(bx + float(i % COLS) * GAP, 0.0,
				bz + float(i / COLS) * GAP)
			u.sync_row()
			GameManager.add_to_squad(sid, u)

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("units="):
			UNITS = maxi(int(s.substr(6)), 50)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(10)
	_spawn_side(Constants.FACTION_PLAYER, Vector3(-60.0, 0.0, -30.0),
		"res://scenes/units/Spearman.tscn")
	_spawn_side(Constants.FACTION_ENEMY, Vector3(60.0, 0.0, 40.0),
		"res://scenes/units/Spearman.tscn")
	await pframes(30)
	var fog = GameManager.fog
	if fog == null:
		print("тумана нет")
		get_tree().quit()
		return
	fog.enabled = true
	var reps := 20
	# Полный пересчёт
	var t0: int = Time.get_ticks_usec()
	for _i in range(reps):
		fog.refresh()
	var full_us: float = float(Time.get_ticks_usec() - t0) / float(reps)
	# Только сбор источников по бойцам
	var n_src := 0
	t0 = Time.get_ticks_usec()
	for _i in range(reps):
		var d: Dictionary = {}
		fog._collect_unit_sources(d)
		n_src = d.size()
	var collect_us: float = float(Time.get_ticks_usec() - t0) / float(reps)
	# Только ядро (штампы + RGBA) на тех же источниках
	var d2: Dictionary = {}
	fog._collect_unit_sources(d2)
	fog._collect_building_sources(d2)
	var src := PackedFloat32Array()
	src.resize(d2.size() * 3)
	var w := 0
	for key in d2.keys():
		var sa: Array = d2[key]
		src[w] = float(sa[0]); src[w + 1] = float(sa[1]); src[w + 2] = float(sa[2]); w += 3
	t0 = Time.get_ticks_usec()
	var res: Array = []
	for _i in range(reps):
		res = GameManager.army.fog_refresh(src)
	var core_us: float = float(Time.get_ticks_usec() - t0) / float(reps)
	t0 = Time.get_ticks_usec()
	for _i in range(reps):
		fog._upload_rgba(res[2])
	var upload_us: float = float(Time.get_ticks_usec() - t0) / float(reps)
	print("\n═════ ЗОНД ТУМАНА: %d бойцов игрока, %d всего, маска %dx%d = %d ячеек, источников %d ═════" % [
		UNITS, GameManager._live_units.size(), fog.cols, fog.rows, fog.cols * fog.rows, d2.size()])
	print("  полный refresh():            %8.2f мс (источников по ядру %d)" % [full_us * 0.001, GameManager.army.fog_source_count()])
	print("  сбор источников по бойцам:   %8.2f мс (GDScript, %d ячеек-источников)" % [collect_us * 0.001, n_src])
	print("  ядро (штампы + RGBA + маршал): %6.2f мс" % (core_us * 0.001))
	print("  заливка текстуры:            %8.2f мс" % (upload_us * 0.001))
	print("=== QA_FOGPERF DONE ===")
	get_tree().quit()
