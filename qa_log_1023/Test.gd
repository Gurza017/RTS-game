extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД РАЗБОРА ПАРТИИ 23.10.2026 (performance_log_2026-10-23_1338.json)
## ═══════════════════════════════════════════════════════════════════════════
##   A — часы партии (_match_clock: время событий телеметрии, срок победы)
##       идут и пока игрок ставит постройку (лог: к концу партии отставали от
##       часов ИИ и бойцов на 62 с, ступеньками на каждой расстановке)
##   B — выход из непроходимого (GameManager.passable_exit): за кромку и
##       вразнос, а не все в одну точку кольца (лог: по 2-3 вызволенных на
##       одинаковых координатах у стены базы красных, повторные вызволения)
## Зонд точек лога — Probe.tscn (вердиктов нет).
## Запуск: godot --headless --path . res://qa_log_1023/Test.tscn [-- only=ab]

const F := Constants.FACTION_PLAYER
const MainS := preload("res://scripts/Main.gd")
const _OptL := preload("res://scripts/perf_config.gd")
var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "ab"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_log_1023: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if "a" in _only: await _a_clock_placing()
	if "b" in _only: await _b_exit()
	_finish()

# ─────────────────────────────────────────────────────────────────────────────
func _a_clock_placing() -> void:
	print("\n═════ A. ЧАСЫ ПАРТИИ ПРИ РАССТАНОВКЕ ПОСТРОЙКИ ═════")
	main._phase = MainS.Phase.PLAYING
	await pframes(5)
	var m0: float = float(main._match_clock)
	var g0: int = Unit.game_ms()
	await pframes(60)
	var dm_play: float = float(main._match_clock) - m0
	var dg_play: float = float(Unit.game_ms() - g0) * 0.001
	main._phase = MainS.Phase.PLACING_BUILDING
	m0 = float(main._match_clock)
	g0 = Unit.game_ms()
	await pframes(120)
	var dm: float = float(main._match_clock) - m0
	var dg: float = float(Unit.game_ms() - g0) * 0.001
	main._phase = MainS.Phase.PLAYING
	print("  играем: часы партии +%.3f с, игровые +%.3f с; расстановка: +%.3f / +%.3f с" % [dm_play, dg_play, dm, dg])
	verdict("A1 в расстановке постройки часы партии идут вровень с игровыми", dg > 1.0 and absf(dm - dg) < 0.1,
		"+%.3f против +%.3f с" % [dm, dg])
	var t0: int = GameManager.tm_events.size()
	GameManager.tm_event("qa_probe", {})
	var ev: Array = GameManager.tm_events[GameManager.tm_events.size() - 1]
	verdict("A2 время события телеметрии — часы партии", absf(float(ev[0]) - float(main._match_clock)) < 0.11 and GameManager.tm_events.size() > t0,
		"%.1f против %.1f" % [float(ev[0]), float(main._match_clock)])

# ─────────────────────────────────────────────────────────────────────────────
func _find_pocket() -> Vector2:
	# Точка в просвете лесной стены у базы красных: клетка навигации закрыта,
	# ствола под ней нет (как у бойцов лога x≈−127, z≈29)
	var a: Vector3 = main.ENEMY_BASE_ANCHOR
	var x: float = a.x - 40.0
	while x < a.x + 60.0:
		var z: float = a.z - 70.0
		while z < a.z - 30.0:
			# Со сплошной лес-стеной (perf_config.forest_nav_solid, ТЗ 23.10.2026,
			# третье письмо) просветов «маска свободна, клетка закрыта» нет вовсе —
			# выход судится из точки В закрытой клетке у кромки стены
			var pocket: bool = GameManager.nav_pocket(x, z) and not GameManager.is_cliff(x, z)
			if _OptL.forest_nav_solid and GameManager.is_cliff(x, z) and GameManager.nav_pocket(x, z):
				pocket = true
			if pocket:
				return Vector2(x, z)
			z += 0.3
		x += 1.1
	return Vector2.INF

func _b_exit() -> void:
	print("\n═════ B. ВЫХОД ИЗ НЕПРОХОДИМОГО — ЗА КРОМКУ И ВРАЗНОС ═════")
	var p: Vector2 = _find_pocket()
	if not p.is_finite():
		verdict("B0 нашлась точка в просвете стены", false)
		return
	print("  точка в просвете: (%.1f, %.1f)" % [p.x, p.y])
	var edge: Vector2 = GameManager.nearest_passable(p.x, p.y)
	var outs: Array = []
	var all_ok := true
	for s in range(7):
		var o: Vector2 = GameManager.passable_exit(p.x, p.y, GameManager.NP_WHO_OTHER, s)
		outs.append(o)
		if not o.is_finite() or not GameManager.is_passable(o.x, o.y):
			all_ok = false
	verdict("B1 каждая точка выхода проходима единым предикатом", all_ok, str(outs))
	var distinct := 0
	for i in range(outs.size()):
		var lone := true
		for j in range(outs.size()):
			if i != j and (outs[i] as Vector2).distance_to(outs[j]) < 0.15:
				lone = false
		if lone:
			distinct += 1
	var cmp_p: int = 0
	for o2 in outs:
		if Vector2(o2).distance_to(edge) < 0.05:
			cmp_p += 1
	verdict("B2 соседи по затору выходят в разные точки, а не в одну", distinct >= 5,
		"разных %d из 7, ровно на кромке %d (кромка (%.1f, %.1f))" % [distinct, cmp_p, edge.x, edge.y])
	# Живые бойцы: шестеро в просвете, вызволение каждого
	var sid: int = GameManager.new_squad(F, "spearman")
	var men: Array = []
	for k in range(6):
		var u: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
		u.faction = F
		main.world_add(u)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.y), p.y)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(2)
	for u2 in men:
		var uu := u2 as Unit
		uu.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.y), p.y)
		uu.sync_row()
		uu._unstick()
	var free_n := 0
	var spots: Array = []
	for u3 in men:
		var q: Vector3 = (u3 as Unit).global_position
		if GameManager.is_passable(q.x, q.z):
			free_n += 1
		var key := Vector2(snappedf(q.x, 0.1), snappedf(q.z, 0.1))
		if not spots.has(key):
			spots.append(key)
	verdict("B3 вызволенные из просвета стоят на проходимом", free_n == 6, "%d из 6" % free_n)
	verdict("B4 вызволенные не легли в одну точку", spots.size() >= 4, "разных точек %d из 6" % spots.size())
	for u4 in men:
		if is_instance_valid(u4):
			(u4 as Unit).queue_free()
