extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_mine_fog — РУДНИКИ ПОД ТУМАНОМ ВОЙНЫ (ТЗ-C 19.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: спрайты золотых рудников видны сквозь неразведанную (чёрную)
## пелену. Причины две: штамп «разведано» вокруг каждого рудника с рождения
## карты (ТЗ 18.09 п. 10, снят: Main.GOLD_MINE_REVEAL_ENABLED = false) и
## группа neutral_buildings, которую обход видимости построек не знал.
##   A — на старте рудник вне обзора бригады не разведан, спрятан (visible =
##       false, слой клика снят); засветов-ориентиров ноль.
##   B — свой рабочий подошёл в обзор — рудник разведан и виден.
##   C — рабочий ушёл — рудник остаётся силуэтом (разведано, не освещено).
##   D — другой рудник, куда никто не ходил, по-прежнему спрятан.
##   E — рудник, захваченный игроком, виден всегда.
## Запуск: godot --headless --path . res://qa_mine_fog/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const F := Constants.FACTION_PLAYER

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_mine_fog: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _mines() -> Array:
	var out: Array = []
	for grp in ["neutral_buildings", "enemy_buildings", "goblin_buildings", "player_buildings"]:
		for b in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(b) and b is Mine and not out.has(b):
				out.append(b)
	return out

func _seen(m: Node3D) -> bool:
	var gp: Vector3 = m.global_position
	return main.fog.is_seen(gp.x, gp.z)

func _lit(m: Node3D) -> bool:
	var gp: Vector3 = m.global_position
	return main.fog.is_lit(gp.x, gp.z)

func _spawn_worker(at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES["worker"].instantiate()
	u.faction = F
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for k in ["goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)
	GameManager.pop_limit_enabled = false
	# Дикие и чужие стоят: площадка у рудника — зона патруля стражи
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction != F:
			(n as Unit).set_tick(false)
	await pframes(4)
	if main.fog == null or not main.fog.enabled:
		verdict("0 туман войны включён", false)
		_finish()
		return
	main.fog.refresh()
	await pframes(2)

	print("\n═════ A. СТАРТ: НЕРАЗВЕДАННЫЙ РУДНИК СПРЯТАН ═════")
	var mines: Array = _mines()
	verdict("A0 рудников на карте не меньше трёх", mines.size() >= 3, "%d" % mines.size())
	verdict("A1 засветов-ориентиров вокруг рудников нет", main.mines_revealed == 0,
		"%d" % main.mines_revealed)
	var hidden: Array = []
	var bad := 0
	for m in mines:
		var mm := m as Node3D
		if _seen(mm):
			continue
		hidden.append(mm)
		if mm.visible or int(mm.get("collision_layer")) != 0:
			bad += 1
	verdict("A2 на старте есть рудники вне разведанной земли", hidden.size() >= 1,
		"неразведанных %d из %d" % [hidden.size(), mines.size()])
	verdict("A3 каждый неразведанный рудник невидим и не ловит клик", bad == 0,
		"светятся %d" % bad)
	if hidden.size() < 2:
		_finish()
		return
	# Самый далёкий от базы — для B/C, второй — контрольный для D
	hidden.sort_custom(func(a, b):
		return (a as Node3D).global_position.distance_to(main.PLAYER_BASE_ANCHOR) \
			> (b as Node3D).global_position.distance_to(main.PLAYER_BASE_ANCHOR))
	var target: Node3D = hidden[0]
	var control: Node3D = hidden[1]

	print("\n═════ B. РАБОЧИЙ ПОДОШЁЛ — РУДНИК ПРОЯВИЛСЯ ═════")
	var vr: float = _UCfg.vision_radius(0.0)
	var wp: Vector3 = target.global_position + Vector3(vr * 0.5, 0.0, 0.0)
	var w: Unit = _spawn_worker(wp)
	await pframes(2)
	main.fog.refresh()
	await pframes(2)
	verdict("B1 рудник в обзоре рабочего разведан и освещён", _seen(target) and _lit(target),
		"seen %s lit %s" % [str(_seen(target)), str(_lit(target))])
	verdict("B2 рудник виден и кликабелен", target.visible and int(target.get("collision_layer")) != 0)

	print("\n═════ C. РАБОЧИЙ УШЁЛ — СИЛУЭТ ПОД ДЫМКОЙ ═════")
	w.global_position = main.PLAYER_BASE_ANCHOR
	w.sync_row()
	await pframes(2)
	main.fog.refresh()
	await pframes(2)
	verdict("C1 обзор ушёл (не освещено), но разведано", _seen(target) and not _lit(target),
		"seen %s lit %s" % [str(_seen(target)), str(_lit(target))])
	verdict("C2 рудник остался виден силуэтом", target.visible)

	print("\n═════ D. КОНТРОЛЬНЫЙ РУДНИК ПО-ПРЕЖНЕМУ СПРЯТАН ═════")
	verdict("D1 рудник, к которому никто не подходил, не разведан и невидим",
		not _seen(control) and not control.visible,
		"seen %s visible %s" % [str(_seen(control)), str(control.visible)])

	print("\n═════ E. СВОЙ РУДНИК ВИДЕН ВСЕГДА ═════")
	control.call("_capture", F)
	await pframes(2)
	main.fog.refresh()
	await pframes(2)
	verdict("E1 захваченный игроком рудник виден без обзора",
		control.visible and int(control.faction) == F)
	_finish()
