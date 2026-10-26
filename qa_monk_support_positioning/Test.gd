extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД «МОНАХ В ТЫЛУ» (ТЗ 22.10.2026, скриншот 15:57)
## ═══════════════════════════════════════════════════════════════════════════
## Армия (2 отряда копейщиков + отряд монахов) идёт настоящим Attack-Move на
## отряд орды. Каждые 0.25 с: расстояние монаха до ближайшего врага против
## медианы того же у копейщиков. Судится свойство:
##   M1 монах ни разу не подошёл к врагу ближе CONTACT_R (не в рубке)
##   M2 монах держится сзади пехоты: в ≥ 90 % замеров (враг в 30 м) он
##      дальше от врага, чем половина копейщиков
##   M3 монах лечил раненых (healed_total растёт) и жив к концу
## Справочно (-- ab=1) — то же с ручкой perf_config.monk_rear выключенной.
## Запуск: godot --headless --path . res://qa_monk_support_positioning/Test.tscn [-- ab=1]

const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN
const CONTACT_R := 5.0

var main: Node = null
var _pass := 0
var _fail := 0
var _ab := false
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "ab=1":
			_ab = true
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_monk_support_positioning: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3, fac: int = F) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int = F, cols: int = 8) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _clear(at: Vector3, r: float) -> void:
	main._clear_trees(at, r)
	for g in ["all_units", "sheep"]:
		for u in get_tree().get_nodes_in_group(g):
			if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
				u.queue_free()
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and (b as Node3D).global_position.distance_to(at) < r \
				and not (b as Building).is_stronghold():
			b.queue_free()

func _free(men: Array) -> void:
	for m in men:
		if m != null and is_instance_valid(m):
			m.queue_free()

func _alive(men: Array) -> Array:
	var out: Array = []
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	await _case(true)
	if _ab:
		_Opt.monk_rear = false
		await _case(false)
		_Opt.monk_rear = true
	_finish()

func _nearest(p: Vector3, list: Array) -> float:
	var best := INF
	for e in list:
		best = minf(best, p.distance_to((e as Node3D).global_position))
	return best

func _case(on: bool) -> void:
	var tag: String = "M" if on else "M0 (справочно, ручка выключена)"
	print("\n═════ %s. армия с монахом идёт [A] на отряд орды ═════" % tag)
	var at := Vector3(-80, 0, -50)
	_clear(at + Vector3(0, 0, 25), 55.0)
	await pframes(5)
	var spears: Array = []
	spears.append_array(_squad("spearman", at + Vector3(-10, 0, 0), 24))
	spears.append_array(_squad("spearman", at + Vector3(0, 0, 0), 24))
	var monks: Array = _squad("monk", at + Vector3(-4, 0, -4), 1)
	var monk := monks[0] as Unit
	monk.max_health *= 3.0
	monk.current_health = monk.max_health
	var foes: Array = _squad("goblin_spearman", at + Vector3(-6, 0, 36), 18, G, 6)
	for f in foes:
		(f as Unit).max_health *= 2.0
		(f as Unit).current_health = (f as Unit).max_health
		(f as Unit).command_move((f as Node3D).global_position)
	await pframes(10)
	var sm = main.selection_manager
	var all: Array = spears.duplicate()
	all.append_array(monks)
	sm.select_units(all)
	sm._squad_cmd().attack_move(sm, GameManager.land_target(at + Vector3(0, 0, 60)))
	sm.clear_selection()
	var healed0: float = float(monk.get("healed_total"))
	var closest := INF
	var samples := 0
	var behind := 0
	var t := 0
	while t < 60 * 50:
		await pframes(15)
		t += 15
		if not is_instance_valid(monk) or monk.is_dead():
			break
		var live_f: Array = _alive(foes)
		if live_f.is_empty():
			break
		var dm: float = _nearest(monk.global_position, live_f)
		closest = minf(closest, dm)
		if dm > 30.0:
			continue
		var ds: Array = []
		for s in _alive(spears):
			ds.append(_nearest((s as Node3D).global_position, live_f))
		if ds.is_empty():
			continue
		ds.sort()
		var med: float = float(ds[ds.size() / 2])
		samples += 1
		if OS.get_cmdline_user_args().has("trace=1") and (t % 60 == 0 or dm < 6.0):
			print("    TRACE t=%.1f монах-враг %.1f, медиана пехоты %.1f, ближний копейщик %.1f, st=%d, приказ=%s, пациент=%d, mon=(%.1f,%.1f)" % [
				float(t) / 60.0, dm, med, float(ds[0]), monk.state, monk.player_order_active(), int(monk.get("patient_sid")), monk.global_position.x, monk.global_position.z])
		if dm >= med:
			behind += 1
	var alive: bool = is_instance_valid(monk) and not monk.is_dead()
	var healed: float = (float(monk.get("healed_total")) - healed0) if alive else 0.0
	var frac: float = float(behind) / float(maxi(samples, 1))
	print("  %s: ближе всего к врагу %.1f м, позади половины пехоты %d из %d замеров (%.0f %%), вылечил %.0f HP, жив %s" % [
		tag, closest, behind, samples, frac * 100.0, healed, alive])
	if on:
		verdict("M1 монах не входит в рубку (ближе %.0f м к врагу — ни разу)" % CONTACT_R, closest > CONTACT_R,
			"%.1f м" % closest)
		verdict("M2 монах держится за спинами пехоты (≥ 90 % замеров)", samples > 0 and frac >= 0.9,
			"%.0f %% из %d" % [frac * 100.0, samples])
		verdict("M3 монах лечит из тыла и жив", alive and healed > 0.0,
			"вылечил %.0f, жив %s" % [healed, alive])
	_free(spears)
	_free(monks)
	_free(foes)
	await pframes(10)
