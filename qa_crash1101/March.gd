extends Node
## ЗОНД МАРША ОРД НА ЖИВОЙ ПАРТИИ (разбор 01.11.2026). Поднимает слепок, гонит
## партию со всеми ИИ и раз в игровую секунду раскладывает ИДУЩИХ (MOVING):
## ведёт ли строку ядро (F_AUTOPILOT — аренда march_core и прочие), а если нет —
## какая из ворот Unit._arm_march её не пускает. Плюс приказы на движение по
## источникам (cmd_meter) — «частые пересчёты точек». Вердиктов нет.
##   godot --headless --path . res://qa_crash1101/March.tscn -- save=<путь> minutes=6 speed=1 out=<путь>
const _Opt := preload("res://scripts/perf_config.gd")
const _Soa := preload("res://scripts/army/ArmySoA.gd")
var main: Node
var _save := "user://autosave.tts"
var _minutes := 6.0
var _speed := 1.0
var _out := ""
var _log: FileAccess = null
var _tab: Dictionary = {}     # "фракция|род" → {причина: число}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("save="):
			_save = s.substr(5)
		elif s.begins_with("minutes="):
			_minutes = float(s.substr(8))
		elif s.begins_with("speed="):
			_speed = float(s.substr(6))
		elif s.begins_with("out="):
			_out = s.substr(4)
	call_deferred("_run")

func _note(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.get_32()
	f.get_32()
	f.get_32()
	var d: Variant = f.get_var(false)
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

## Первая ворота _arm_march, которая не пускает бойца (повтор порядка проверок)
func _why(u: Unit) -> String:
	if u._soa < 0:
		return "нет строки"
	if GameManager.army.has_flag(u._soa, _Soa.F_DORMANT):
		return "спит"
	if GameManager.army.has_flag(u._soa, _Soa.F_AUTOPILOT):
		return "ЯДРО"
	if not u._bm_on:
		return "не пакетный шаг (_bm_on)"
	if u.retreating:
		return "отход"
	if u._panicked:
		return "паника"
	if u._sprint_after_pass:
		return "бег после прохода"
	if u._hunt_sheep != null:
		return "охота на овцу"
	if u.breaks_bodies:
		return "ломает тела (гигант)"
	if u._trunk_ignore > 0.0:
		return "сквозь стволы"
	if u._fling_vel.x != 0.0 or u._fling_vel.z != 0.0 or u._down_until_ms > 0:
		return "разлёт/сбит"
	if u._matrix_driven:
		return "матрица"
	if u._forced_move_pass() or u._retreat_pass():
		return "билет прохода"
	if u._route_i < u._route.size() and u._route_i == u._route_ford_i:
		return "угол брода"
	if u._route_i < u._route.size():
		return "маршрут: между арендами (у угла / срок)"
	return "к точке: между арендами (зона прибытия / срок / упор)"

func _sample() -> void:
	for u in GameManager._live_units:
		if not is_instance_valid(u):
			continue
		var un := u as Unit
		if un.is_dead() or un.state != Unit.State.MOVING:
			continue
		var key := "%d|%s" % [un.faction, String(un.stat_id)]
		if not _tab.has(key):
			_tab[key] = {}
		var w := _why(un)
		var t: Dictionary = _tab[key]
		t[w] = int(t.get(w, 0)) + 1

func _run() -> void:
	if _out != "":
		_log = FileAccess.open(_out, FileAccess.WRITE)
	var st: Dictionary = _read(_save)
	if st.is_empty():
		_note("слепка нет: " + _save)
		get_tree().quit()
		return
	GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(60):
		await get_tree().physics_frame
	Engine.time_scale = _speed
	_Opt.cmd_meter = true
	_Opt.cmd_reset()
	var t0: int = Unit.game_ms()
	var next_s := 1
	while Unit.game_ms() - t0 < int(_minutes * 60000.0):
		await get_tree().physics_frame
		if Unit.game_ms() - t0 >= next_s * 1000:
			_sample()
			next_s += 1
			if next_s % 60 == 0:
				_note("  … %d с, бойцов %d" % [next_s, GameManager._live_units.size()])
	var secs: float = float(Unit.game_ms() - t0) / 1000.0
	_note("═══ ИДУЩИЕ ПО РОДАМ (бойцо-выборок раз в секунду за %.0f с; ЯДРО = арендован) ═══" % secs)
	var keys: Array = _tab.keys()
	keys.sort_custom(func(a, b):
		var sa := 0
		var sb := 0
		for v in (_tab[a] as Dictionary).values(): sa += int(v)
		for v in (_tab[b] as Dictionary).values(): sb += int(v)
		return sa > sb)
	for k in keys:
		var t: Dictionary = _tab[k]
		var tot := 0
		for v in t.values():
			tot += int(v)
		var parts: Array = []
		var rk: Array = t.keys()
		rk.sort_custom(func(a, b): return int(t[a]) > int(t[b]))
		for r in rk:
			parts.append("%s %.0f%%" % [r, 100.0 * float(t[r]) / float(tot)])
		_note("%-28s в среднем идущих %6.1f | %s" % [k, float(tot) / secs, ", ".join(parts)])
	_note("═══ ПРИКАЗЫ command_move ЗА ПРОГОН: всего %d (%.0f/с) ═══" % [_Opt.cmd_total, float(_Opt.cmd_total) / secs])
	var rows: Array = _Opt.cmd_report()
	for i in range(mini(25, rows.size())):
		var r: Array = rows[i]
		_note("  %-22s %-18s из состояния %d: %6d (%.1f/с)" % [r[0], r[1], int(r[2]), int(r[3]), float(r[3]) / secs])
	var sr: Array = _Opt.cmd_sid_report()
	_note("  чаще всего дёргаемые отряды:")
	for i in range(mini(12, sr.size())):
		var r: Array = sr[i]
		var sq: Variant = GameManager.squads.get(int(r[1]))
		var ty: String = String((sq as Dictionary).get("type", "?")) if sq != null else "(распущен)"
		var n: int = ((sq as Dictionary)["members"] as Array).size() if sq != null else 0
		_note("    %-20s отряд %5d %-16s бойцов %3d: %6d приказов (%.1f/с, %.2f на бойца в секунду)" % [r[0], int(r[1]), ty, n, int(r[2]), float(r[2]) / secs, float(r[2]) / secs / maxf(float(n), 1.0)])
	_note("=== ГОТОВО ===")
	get_tree().quit()
