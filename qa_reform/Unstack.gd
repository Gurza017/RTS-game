extends Node
## Зонд: пять отрядов, посланных В ОДНУ ТОЧКУ, не должны накладываться.

var main = null
var sm = null
var recs: Array = []      # [sid, men]

func _ready() -> void: call_deferred("_run")
func pf(n: int) -> void:
	for _i in range(n): await get_tree().physics_frame

func _spawn(at: Vector3) -> Unit:
	var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _report(tag: String) -> void:
	print("  ── %s ──" % tag)
	var cs: Array = []
	for rec in recs:
		var sid: int = int(rec[0])
		cs.append([sid, GameManager.squad_centroid(sid),
			GameManager.squad_spot_radius(sid)])
	var worst_over := 0.0
	var pairs := 0
	for i in range(cs.size()):
		for j in range(i + 1, cs.size()):
			var a: Array = cs[i]
			var b: Array = cs[j]
			var d: float = Vector2((a[1] as Vector3).x - (b[1] as Vector3).x,
				(a[1] as Vector3).z - (b[1] as Vector3).z).length()
			var need: float = float(a[2]) + float(b[2])
			if d < need:
				pairs += 1
				worst_over = maxf(worst_over, need - d)
	for c in cs:
		print("    отряд %d: центр (%.1f, %.1f), радиус %.1f м" % [
			int(c[0]), (c[1] as Vector3).x, (c[1] as Vector3).z, float(c[2])])
	print("    ПЕРЕКРЫВАЮЩИХСЯ ПАР: %d, худшее перекрытие %.2f м" % [pairs, worst_over])

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(8)
	sm = main.selection_manager
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null: GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"): (n as Node).queue_free()
	await pf(4)
	print("=== ЗОНД: ПЯТЬ ОТРЯДОВ В ОДНУ ТОЧКУ ===")

	var base := Vector3(-700.0, 0.0, -700.0)
	for s in range(5):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		var men: Array = []
		for i in range(30):
			var u := _spawn(base + Vector3(float(s) * 18.0 + float(i % 6) * 0.7,
				0.0, float(i / 6) * 0.7))
			GameManager.add_to_squad(sid, u)
			men.append(u)
		recs.append([sid, men])
	await pf(8)
	_report("исходно, врозь")

	# ── КАЖДЫЙ ОТРЯД ОТДЕЛЬНЫМ КЛИКОМ В ОДНУ И ТУ ЖЕ ТОЧКУ ─────────────────
	# Именно так и жалуются: не «выделил все и кликнул» (там их разводит сетка
	# блоков), а «послал один, потом второй туда же»
	var spot := Vector3(-700.0, 0.0, -640.0)
	for rec in recs:
		sm._clear_selection()
		for u2 in (rec[1] as Array): sm._select(u2)
		await pf(2)
		sm._issue_formation_move(spot, false)
		await pf(60)
	sm._clear_selection()
	await pf(900)
	_report("все пятеро посланы в одну точку")
	await pf(600)
	_report("+10 с")
	get_tree().quit(0)
