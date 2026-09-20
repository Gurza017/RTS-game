extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД ЦЕНЫ ПЕРЕСЧЁТА КОРИДОРА (BigStand-5, этап 4; измеритель, вердиктов нет)
## ═══════════════════════════════════════════════════════════════════════════
## squad_corridor держит 0.65-0.8 мс/кадр в замесе после переезда габаритов
## в ядро (этап 2). Зонд гоняет _recalc_corridor на уставном отряде ×N с
## профилем подветок (cor_harvest / cor_core / cor_push / cor_ranks /
## cor_cohesion / cor_sleep) и печатает мкс на отряд по каждой — так видно,
## что именно осталось в GDScript. Два сценария: чужих рядом нет (сон) и
## чужие в дальности внимания (бой).
## Запуск: <godot> --headless --path . res://qa_bigstand/CorProbe.tscn

const N := 3000
const SQUAD := 60
var main = null

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ"); get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(scene: String, fac: int, at: Vector3, sid: int) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	GameManager.add_to_squad(sid, u)
	return u

func _report(label: String, sid: int) -> void:
	var opt = load("res://scripts/perf_config.gd")
	opt.prof_reset()
	opt.profile_physics = true
	var t0: int = Time.get_ticks_usec()
	for i in range(N):
		GameManager._corridors.erase(sid)
		GameManager._recalc_corridor(sid, Time.get_ticks_msec())
	var total: float = float(Time.get_ticks_usec() - t0) / float(N)
	opt.profile_physics = false
	print("── %s: %.1f мкс на отряд из %d (все подветки, с профилем)" % [label, total, SQUAD])
	for r in opt.prof_report():
		var name: String = r[0]
		if not name.begins_with("cor_"):
			continue
		print("   %-14s %6.1f мкс/вызов  худший %5d" % [name, float(r[3]), int(r[4])])

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
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for k in range(SQUAD):
		_spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER,
			Vector3(float(k % 10) * 0.6, 0.0, float(k / 10) * 0.6), sid)
	await pframes(30)
	print("═════ ЗОНД КОРИДОРА (×%d) ═════" % N)
	_report("ЧУЖИХ НЕТ", sid)
	var esid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, "goblin_spearman")
	for k in range(SQUAD):
		_spawn("res://scenes/units/GoblinSpearman.tscn", Constants.FACTION_GOBLIN,
			Vector3(float(k % 10) * 0.6, 0.0, 12.0 + float(k / 10) * 0.6), esid)
	await pframes(30)
	_report("ЧУЖИЕ В 12 м", sid)
	print("═════ ИТОГ CorProbe: провалов: 0 (измеритель) ═════")
	get_tree().quit()
