extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД ФИНАЛИЗИРУЕМОГО МУСОРА (BigStand-5, этап 4; измеритель, вердиктов нет)
## ═══════════════════════════════════════════════════════════════════════════
## qa_bigstand показал 8-43 тысячи объектов, ЖДУЩИХ ФИНАЛИЗАЦИИ, к моменту
## сборки gen1 — и паузы gen1 по 16-19 мс. Финализируемый объект переживает
## gen0 ВСЕГДА (его сперва кладут в очередь финализации), то есть набивает
## gen1 и учащает блокирующие сборки. Зонд гоняет каждый вызов ядра ×N между
## двумя принудительными сборками и печатает, сколько финализируемых объектов
## он оставил и сколько байт выделил — так источник называется по имени.
## Запуск: <godot> --headless --path . res://qa_bigstand/GcProbe.tscn

const N := 5000
var main = null
var _units: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ"); get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _probe(label: String, fn: Callable) -> void:
	var a: PackedFloat64Array = GameManager.army.gc_probe()
	fn.call()
	var b: PackedFloat64Array = GameManager.army.gc_probe()
	print("  %-34s финализ. %6d  выделено %8.1f КБ  (%.2f Б/вызов)" % [
		label, int(b[0]), (b[1] - a[1]) / 1024.0, (b[1] - a[1]) / float(N)])

func _run() -> void:
	seed(7)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	for nm in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var ai = main.get(nm)
		if ai != null and is_instance_valid(ai) and ai is Node:
			(ai as Node).set_process(false)
	GameManager.world_bounds_enabled = false
	for k in range(60):
		_units.append(_spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER,
			Vector3(float(k % 10) * 0.8, 0.0, float(k / 10) * 0.8)))
	for k in range(60):
		_units.append(_spawn("res://scenes/units/GoblinSpearman.tscn", Constants.FACTION_GOBLIN,
			Vector3(float(k % 10) * 0.8, 0.0, 12.0 + float(k / 10) * 0.8)))
	await pframes(30)
	var army = GameManager.army
	var grid = GameManager.unit_grid
	var u: Unit = _units[0]
	var row: int = u._soa
	var p: Vector3 = u.global_position
	print("═════ ЗОНД ФИНАЛИЗИРУЕМОГО МУСОРА (×%d) ═════" % N)
	_probe("(пусто)", func(): pass)
	_probe("army.enemy_near", func():
		for i in range(N): army.enemy_near(p.x, p.z, 0, 6.0))
	_probe("unit_grid.enemy_near", func():
		for i in range(N): grid.enemy_near(p, 0, 6.0))
	_probe("unit_grid.enemy_at", func():
		for i in range(N): grid.enemy_at(p + Vector3(0, 0, 12), 1.0, 0))
	_probe("army.best_enemy_w", func():
		for i in range(N): army.best_enemy_w(row, 20.0, 0.0, false))
	_probe("army.nearest_of_side", func():
		for i in range(N): army.nearest_of_side(p.x, p.z, 2, 30.0))
	_probe("army.trunk_near", func():
		for i in range(N): army.trunk_near(p.x, p.z, 6.0))
	_probe("army.enemy_block", func():
		for i in range(N): army.enemy_block(row, p.x, p.z + 1.0, 0.55, false))
	_probe("army.pos_or", func():
		for i in range(N): army.pos_or(row, Vector3.ZERO))
	_probe("army.height_at", func():
		for i in range(N): army.height_at(p.x, p.z, 1.0))
	_probe("army.set_flag", func():
		for i in range(N): army.set_flag(row, 1 << 3, true))
	_probe("unit.sync_row", func():
		for i in range(N): u.sync_row())
	_probe("army.tick_rows (×N/50)", func():
		for i in range(N / 50): army.tick_rows(4, i % 4, Unit.State.ATTACKING, Unit.State.IDLE, 0.016))
	var rows := PackedInt32Array()
	for k in range(60):
		rows.append((_units[k] as Unit)._soa)
	_probe("army.squad_corridor (×N/50)", func():
		for i in range(N / 50): army.squad_corridor(rows, Unit.State.DEAD, 10.0, 0.8, 2.0))
	_probe("unit_grid.squad_ranks (×N/50)", func():
		for i in range(N / 50): grid.squad_ranks(rows, Vector3(0, 0, -1), 1.5, 0.6))
	_probe("army.squad_melee (×N/50)", func():
		for i in range(N / 50): army.squad_melee(rows, Unit.State.ATTACKING))
	_probe("unit_grid.query_radius (×N/50)", func():
		for i in range(N / 50): grid.query_radius(p, 8.0))
	_probe("unit_grid.query_radius_rows (×N/50)", func():
		for i in range(N / 50): grid.query_radius_rows(p, 8.0))
	_probe("unit_grid.enemy_count (×N/50)", func():
		for i in range(N / 50): grid.enemy_count(p, 8.0, 0))
	_probe("army.rb_slot (×N/10)", func():
		for i in range(N / 10): army.rb_slot(0, 0))
	_probe("GameManager.queue_pose+flush(×N/10)", func():
		for i in range(N / 10):
			for k in range(60):
				GameManager.queue_pose((_units[k] as Unit)._soa, p, Vector3.ZERO, 0, 0, 1.0)
			GameManager._flush_poses())
	_probe("unit.take_damage(0.1) (×N/10)", func():
		for i in range(N / 10): (_units[1] as Unit).take_damage(0.1))
	_probe("unit.command_move (×N/10)", func():
		for i in range(N / 10): (_units[2] as Unit).command_move(p + Vector3(1, 0, 1)))
	_probe("AudioManager.play_3d (×N/10)", func():
		for i in range(N / 10): AudioManager.play_3d("bow_attack", p))
	_probe("Node3D.global_position (×N)", func():
		for i in range(N): var _q = u.global_position)
	print("═════ ИТОГ GcProbe: провалов: 0 (измеритель) ═════")
	get_tree().quit()
