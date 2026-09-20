extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД ЦЕНЫ ВЫСТРЕЛА ПО ЧАСТЯМ (BigStand-5, этап 3; измеритель, вердиктов нет)
## ═══════════════════════════════════════════════════════════════════════════
## Один лучник, одна цель. Каждая часть _on_attack_fired гоняется ×N подряд и
## печатается в мкс на вызов: анимация, звук тетивы, упреждение, словари залпа,
## разброс, fire_projectile целиком. Так видно, ЧТО осталось дорогим в запуске
## после переезда снаряда в ядро (сам снаряд — 8 мкс).
## Запуск: <godot> --headless --path . res://qa_arrow_bench/LaunchProbe.tscn

const _Opt := preload("res://scripts/perf_config.gd")
const _UStats := preload("res://scripts/unit_stats_config.gd")
const N := 2000

var main = null

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

func _us(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / float(N)

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
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	var a: Unit = _spawn("res://scenes/units/Archer.tscn", Constants.FACTION_PLAYER, Vector3(0, 0, 0))
	var t: Unit = _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_ENEMY, Vector3(0, 0, -12))
	a.set_tick(false); t.set_tick(false)
	t.current_health = t.max_health * 1000.0
	t._soa_push_stats()
	await pframes(4)
	var parent: Node = a.get_parent()
	var from_pos: Vector3 = a.global_position + Vector3(0, 1.2, 0)
	var speed: float = _UStats.stat("archer", "arrow_speed", 9.0)
	print("═════ ЗОНД ЗАПУСКА (×%d, мкс на вызов; projectile_core = %s) ═════" % [N, str(_Opt.projectile_core)])
	var t0: int
	t0 = Time.get_ticks_usec()
	for i in range(N): a._play_attack_anim("attack", 600)
	print("  _play_attack_anim            %.2f" % _us(t0))
	t0 = Time.get_ticks_usec()
	for i in range(N): AudioManager.play_3d("bow_attack", a.global_position)
	print("  play_3d(bow_attack)          %.2f" % _us(t0))
	t0 = Time.get_ticks_usec()
	for i in range(N): t.notify_incoming_fire(a.global_position)
	print("  notify_incoming_fire         %.2f" % _us(t0))
	var tb: Vector3 = t.global_position + Vector3(0, t.aim_height(), 0)
	t0 = Time.get_ticks_usec()
	for i in range(N): a._lead_point(from_pos, tb, Vector3(1, 0, 0), speed)
	print("  _lead_point                  %.2f" % _us(t0))
	t0 = Time.get_ticks_usec()
	for i in range(N):
		GameManager.squad_volley_open(a.squad_id)
		GameManager.squad_volley_mode(a.squad_id)
	print("  squad_volley_open+mode       %.2f" % _us(t0))
	t0 = Time.get_ticks_usec()
	for i in range(N): GameManager.unit_bonus(a.faction, a.stat_id, "bonus_spread")
	print("  unit_bonus(bonus_spread)     %.2f" % _us(t0))
	t0 = Time.get_ticks_usec()
	for i in range(N): _UStats.archer_drill(a._drill_level())
	print("  archer_drill(_drill_level)   %.2f" % _us(t0))
	t0 = Time.get_ticks_usec()
	for i in range(N): _UStats.stat("archer", "arrow_speed", 9.0)
	print("  _UStats.stat(строки)         %.2f" % _us(t0))
	t0 = Time.get_ticks_usec()
	for i in range(N): t.aim_miss_chance()
	print("  aim_miss_chance              %.2f" % _us(t0))
	t0 = Time.get_ticks_usec()
	for i in range(N):
		GameManager.fire_projectile(parent, from_pos, tb, 12.0, speed, 0.5, 10.0, a, a.faction)
	print("  fire_projectile              %.2f" % _us(t0))
	await pframes(60)
	t0 = Time.get_ticks_usec()
	for i in range(N): a._on_attack_fired(t, a.attack_damage)
	print("  _on_attack_fired ЦЕЛИКОМ     %.2f" % _us(t0))
	await pframes(60)
	print("═════ ИТОГ LaunchProbe: провалов: 0 (измеритель) ═════")
	get_tree().quit()
