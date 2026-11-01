extends Node
## ЗОНД: «бег на месте» в живой партии владельца до/после валидатора прибытия.
## Поднимает автосейв владельца (user://autosave.tts), пускает партию со всеми
## ИИ на minutes игровых минут (ускорение speed) и считает ДВУМЯ способами:
##   • сводки SquadProbes (stuck_running: сводок, бойцов) — как в телеметрии;
##   • свой замер раз в 0.5 с: бойцов в MOVING, сместившихся меньше 0.15 м
##     за окно («бойцо-окон бега на месте»), отдельно — ближе 1 м к цели хода.
## Вердиктов нет. Запуск:
##   godot --headless --path . res://qa_squad_arrival/Probe.tscn -- [minutes=4 speed=3 knob=squad_arrive_validate:0]
const _Opt := preload("res://scripts/perf_config.gd")
var main: Node
var _minutes: float = 4.0
var _speed: float = 3.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("minutes="):
			_minutes = float(s.substr(8))
		elif s.begins_with("speed="):
			_speed = float(s.substr(6))
	call_deferred("_run")

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

func _run() -> void:
	var st: Dictionary = _read("user://autosave.tts")
	if st.is_empty():
		print("  автосейва нет — зонд не запущен")
		get_tree().quit()
		return
	print("слепок: ключей %d, зерно %s; ручка squad_arrive_validate = %s" % [st.size(), str(st.get("meta", {}).get("world_seed", "?")), str(_Opt.squad_arrive_validate)])
	_Opt.squad_probes = true
	GameManager.pending_load = st
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(60):
		await get_tree().physics_frame
	Engine.time_scale = _speed
	var t0: int = Unit.game_ms()
	var rep0: int = GameManager.probes.stuck_reports
	var units0: int = GameManager.probes.stuck_units_total
	var stall0: int = Unit.stall_arrivals
	var zone0: int = Unit.zone_arrivals
	var val0: int = GameManager.squad_arrive_validations
	var set0: int = GameManager.squad_arrive_settled
	var unst0: int = Unit.unstuck_total
	var trap0: int = GameManager.trap_pushes
	var give0: int = Unit.unstuck_giveups
	var cure0: int = GameManager.probes.rip_cures
	var prev: Dictionary = {}          # instance_id → позиция прошлого окна
	var why: Dictionary = {}           # разбор застрявших у цели по признакам
	var by_sid: Dictionary = {}        # sid → [окон, род]
	var dump: Array = []               # образцы застрявших у цели
	var trace_u: Unit = null
	var trace_lines: Array = []
	var stuck_windows := 0
	var stuck_near := 0
	var stuck_by_fac: Dictionary = {}
	var samples := 0
	var frames := 0
	var next_min := 1
	while Unit.game_ms() - t0 < int(_minutes * 60000.0):
		await get_tree().physics_frame
		frames += 1
		if trace_u != null and is_instance_valid(trace_u) and trace_lines.size() < 40:
			var tu: Unit = trace_u
			trace_lines.append("f%d now=%d st=%d core=%d pos=(%.3f, %.3f) tgt=(%.3f, %.3f) d=%.3f vel=(%.2f, %.2f) mv=%.2f smp=%d prev=(%.3f, %.3f) pend=%s told=%s arrived=%s cmds=%d" % [
				frames, Unit.now_ms, tu.state, GameManager.army.state_of(tu._soa) if tu._soa >= 0 else -1,
				tu.position.x, tu.position.z, tu.move_target.x, tu.move_target.z,
				Vector2(tu.move_target.x - tu.position.x, tu.move_target.z - tu.position.z).length(),
				tu.velocity.x, tu.velocity.z, tu._mv_speed, tu._mv_sample_ms, tu._mv_prev.x, tu._mv_prev.z,
				str(tu._march_pending), str(tu._zone_told), str(tu._squad_arrived), tu.zone_returns + tu.kite_blocked])
		if frames % 30 != 0:
			continue
		samples += 1
		var cur: Dictionary = {}
		for raw in GameManager._live_units:
			if raw == null or not is_instance_valid(raw):
				continue
			var u := raw as Unit
			if u == null or u.is_dead() or u.garrisoned:
				continue
			var id: int = u.get_instance_id()
			var p: Vector3 = u.global_position
			cur[id] = p
			if u.state != Unit.State.MOVING:
				continue
			var p0: Variant = prev.get(id)
			if p0 == null:
				continue
			if p.distance_to(p0 as Vector3) < 0.15:
				stuck_windows += 1
				stuck_by_fac[u.faction] = int(stuck_by_fac.get(u.faction, 0)) + 1
				if Vector2(u.move_target.x - p.x, u.move_target.z - p.z).length() < 1.0:
					stuck_near += 1
					_why_tally(u, why)
					var ratio: float = u._mv_speed / maxf(u._effective_speed(), 0.01)
					var bucket: String = "<0.25" if ratio < 0.25 else ("<0.5" if ratio < 0.5 else ("<1" if ratio < 1.0 else ">=1"))
					why["ratio" + bucket] = int(why.get("ratio" + bucket, 0)) + 1
					if trace_u == null and samples > 40 and u.stat_id == "gnoll":
						trace_u = u
					if dump.size() < 8 and samples > 40:
						dump.append("%s sid=%d d=%.2f mv=%.2f eff=%.2f vel=%.2f net=%.3f route=%d/%d pass=%s core=%d sep=%.2f" % [
							String(u.stat_id), u.squad_id, Vector2(u.move_target.x - p.x, u.move_target.z - p.z).length(),
							u._mv_speed, u._effective_speed(), Vector2(u.velocity.x, u.velocity.z).length(), p.distance_to(p0 as Vector3),
							u._route_i, u._route.size(), str(GameManager.is_passable(u.move_target.x, u.move_target.z)),
							GameManager.army.state_of(u._soa) if u._soa >= 0 else -1, u.sep_radius()])
						dump.append("      pos=%s gpos=%s mv_prev=%s smp=%d now=%d core_led=%s phys=%s matrix=%s idle_wait=%s march_pend=%s parent=%s corepos=%s" % [
							str(u.position), str(u.global_position), str(u._mv_prev), u._mv_sample_ms, Unit.now_ms,
							str(u._core_led()), str(u.is_physics_processing()), str(u._matrix_driven), str(u._idle_wait),
							str(u._march_pending), u.get_parent().name, str(GameManager.army.pos_of(u._soa) if u._soa >= 0 else Vector3.ZERO)])
						dump.append("      pass_here=%s pass_prev=%s pass_tgt=%s forest_here=%s forest_tgt=%s tgt=%s" % [
							str(GameManager.is_passable(p.x, p.z)), str(GameManager.is_passable(u._mv_prev.x, u._mv_prev.z)),
							str(GameManager.is_passable(u.move_target.x, u.move_target.z)),
							str(GameManager.army.forest_at(p.x, p.z)) if GameManager.army.has_method("forest_at") else "?",
							str(GameManager.army.forest_at(u.move_target.x, u.move_target.z)) if GameManager.army.has_method("forest_at") else "?",
							str(u.move_target)])
					var sk: int = u.squad_id
					var rec: Variant = by_sid.get(sk)
					if rec == null:
						rec = [0, String(u.stat_id)]
						by_sid[sk] = rec
					(rec as Array)[0] = int((rec as Array)[0]) + 1
		prev = cur
		if Unit.game_ms() - t0 >= next_min * 60000:
			print("  [%d мин] бойцо-окон бега на месте: %d (ближе 1 м к цели %d); сводок зонда %d; зоной %d, упёрся %d, проходов %d" % [
				next_min, stuck_windows, stuck_near, GameManager.probes.stuck_reports - rep0,
				Unit.zone_arrivals - zone0, Unit.stall_arrivals - stall0, GameManager.squad_arrive_validations - val0])
			next_min += 1
	Engine.time_scale = 1.0
	print("\n═════ ЗОНД qa_squad_arrival/Probe: %.1f игровых мин, ручка squad_arrive_validate = %s ═════" % [_minutes, str(_Opt.squad_arrive_validate)])
	print("  бойцо-окон бега на месте (MOVING, < 0.15 м за 0.5 с): %d за %d выборок, из них ближе 1 м к цели хода: %d; по сторонам %s" % [stuck_windows, samples, stuck_near, str(stuck_by_fac)])
	print("  сводок stuck_running зонда: %d (бойцов %d); лечений run_in_place_cure %d" % [
		GameManager.probes.stuck_reports - rep0, GameManager.probes.stuck_units_total - units0, GameManager.probes.rip_cures - cure0])
	print("  валидатор: проходов %d, остановлено проходом %d, по флагу в тике %d; лестница stall_arrive %d; вызволений %d, сдач %d" % [
		GameManager.squad_arrive_validations - val0, GameManager.squad_arrive_settled - set0,
		Unit.zone_arrivals - zone0 - (GameManager.squad_arrive_settled - set0), Unit.stall_arrivals - stall0,
		Unit.unstuck_total - unst0, Unit.unstuck_giveups - give0])
	print("  вытеснений из непроходимого (trap_pushes): %d" % (GameManager.trap_pushes - trap0))
	print("  разбор застрявших ближе 1 м к цели (бойцо-окон по признакам): %s" % str(why))
	for line in dump:
		print("    образец: " + String(line))
	for line in trace_lines:
		print("    след: " + String(line))
	var sids: Array = by_sid.keys()
	sids.sort_custom(func(x, y): return int((by_sid[x] as Array)[0]) > int((by_sid[y] as Array)[0]))
	for i in range(mini(6, sids.size())):
		var sid: int = int(sids[i])
		var sq: Variant = GameManager.squads.get(sid)
		var alive := 0
		var told := 0
		var moving := 0
		var arrived := false
		if sq != null:
			arrived = bool((sq as Dictionary).get("arrived_zone", false))
			for m in ((sq as Dictionary)["members"] as Array):
				if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
					alive += 1
					if (m as Unit)._zone_told:
						told += 1
					if (m as Unit).state == Unit.State.MOVING:
						moving += 1
		print("    отряд %d (%s): окон %d; живых %d, доложили о зоне %d, в MOVING %d, отряд прибыл %s" % [
			sid, String((by_sid[sid] as Array)[1]), int((by_sid[sid] as Array)[0]), alive, told, moving, str(arrived)])
	get_tree().quit()

func _why_tally(u: Unit, why: Dictionary) -> void:
	var keys: Array = []
	if not u.tick_on: keys.append("tick_off")
	if u.dormant: keys.append("dormant")
	if u.squad_id <= 0: keys.append("no_squad")
	if u._route_i < u._route.size(): keys.append("route_pending")
	if u.retreating: keys.append("retreating")
	if u._hunt_sheep != null: keys.append("sheep")
	if u.attack_target != null and is_instance_valid(u.attack_target): keys.append("has_target")
	if u._zone_told: keys.append("zone_told")
	if u._squad_arrived: keys.append("squad_arrived")
	if u._mv_sample_ms > u._zone_ms: keys.append("sample_after_zone")
	if u._mv_speed < 0.5 * u._effective_speed(): keys.append("slow")
	if u._soa >= 0 and GameManager.army.state_of(u._soa) != Unit.State.MOVING: keys.append("core_not_moving")
	for k in keys:
		why[k] = int(why.get(k, 0)) + 1
