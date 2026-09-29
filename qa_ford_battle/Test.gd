extends Node

## ═══════════════════════════════════════════════════════════════════════════
## БОЙ НА БРОДЕ: 1000 ГОБЛИНОВ ПРОТИВ 1000 КОПЕЙЩИКОВ (ТЗ 29.09.2026, блок 7)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: «в узком месте на броде идёт волна гоблинов, ощущение, что они не
## дерутся: тупят, ударят раз или идут на убой». Стенд ставит орду на +X берегу
## и копейщиков игрока на −X, все в полосе брода (|z| < FORD_HALF), орда идёт
## в атаку как в игре (command_attack по ближайшему отряду людей, forced, без
## замка), и раз в полсекунды снимает зонды по сторонам:
##   • удары/с (Δ_strike_count), попадания и промахи отложенного касания;
##   • урон/с (GameManager.tm_damage_out);
##   • «в досягаемости, но не бьёт» дольше 0.3 с;
##   • «в контакте, но цель недосягаема» (упёрся в чужое тело);
##   • интервал ударов против кулдауна у бивших.
## Вердикты — по последним 30 с окна. Headless, ~2 мин.
##   -- secs=N side=goblin|player

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _secs: float = 60.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("secs="):
			_secs = float(s.substr(5))
	call_deferred("_run")
	get_tree().create_timer(400.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_ford_battle: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn_human_squad(uid: String, n: int, cols: int, at: Vector3, dir_x: float) -> int:
	var scene: PackedScene = Building.PRELOAD_SCENES.get(uid)
	if scene == null:
		return 0
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, uid)
	var sp: float = 0.7
	for i in range(n):
		var col: int = i % cols
		var rank: int = i / cols
		var px: float = at.x + dir_x * float(rank) * sp
		var pz: float = at.z + (float(col) - float(cols - 1) * 0.5) * sp
		var u: Unit = scene.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
	return sid

func _members(sid: int) -> Array:
	var rec: Variant = GameManager.squads.get(sid)
	if rec == null:
		return []
	var out: Array = []
	for m in (rec as Dictionary).get("members", []):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n.has_method("set_process"):
			n.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = true
	GameManager.refresh_map_bounds()
	# Чужих партии — прочь: сцена только наша
	for u in GameManager._live_units.duplicate():
		if u != null and is_instance_valid(u):
			(u as Unit).set_tick(false)
			(u as Node).queue_free()
	await pframes(6)
	Engine.max_fps = 0
	var fz: float = main.FORD_Z
	var off: float = main.RIVER_HALF_W + main.RIVER_BANK
	print("\n═════ A. РАССТАНОВКА: орда на +X, копейщики на −X, оба в полосе брода ═════")
	var gob_sids: Array = []
	var k := 0
	for sq in range(34):
		var col: int = sq % 5
		var row: int = sq / 5
		var bx: float = main.river_x(fz) + off + 22.0 + float(row) * 9.0
		var bz: float = fz + (float(col) - 2.0) * 9.0
		var sid: int = main.spawn_goblin_squad("goblin_spearman", 30, Vector3(bx, 0.0, bz))
		if sid > 0:
			gob_sids.append(sid)
			k += 1
	var hum_sids: Array = []
	for sq in range(25):
		var col: int = sq % 5
		var row: int = sq / 5
		var hx: float = main.river_x(fz) - off - 14.0 - float(row) * 7.0
		var hz: float = fz + (float(col) - 2.0) * 8.0
		var sid2: int = _spawn_human_squad("spearman", 40, 8, Vector3(hx, 0.0, hz), -1.0)
		if sid2 > 0:
			hum_sids.append(sid2)
	await pframes(30)
	var gob_n := 0
	for s in gob_sids:
		gob_n += _members(s).size()
	var hum_n := 0
	for s in hum_sids:
		hum_n += _members(s).size()
	print("  орда: отрядов %d, бойцов %d; люди: отрядов %d, бойцов %d" % [gob_sids.size(), gob_n, hum_sids.size(), hum_n])
	verdict("A1 по тысяче с каждой стороны", gob_n >= 900 and hum_n >= 900, "%d / %d" % [gob_n, hum_n])
	# Копейщики стоят стеной лицом к броду (курс +X)
	for s in hum_sids:
		for m in _members(s):
			(m as Unit).set_stance("defense")
			(m as Unit)._facing = Vector3(1.0, 0.0, 0.0)
	# Орда — в атаку по ближайшему отряду людей, как GoblinAI._issue_squad
	var ordered := 0
	for s in gob_sids:
		var men: Array = _members(s)
		if men.is_empty():
			continue
		var c: Vector2 = GameManager.squad_centre_xz(int(s))
		var best_sid := 0
		var bd := INF
		for hs in hum_sids:
			var hc: Vector2 = GameManager.squad_centre_xz(int(hs))
			if hc == Vector2.INF:
				continue
			var d: float = (hc - c).length_squared() if c != Vector2.INF else 0.0
			if d < bd:
				bd = d
				best_sid = int(hs)
		var foes: Array = _members(best_sid)
		if foes.is_empty():
			continue
		for m in men:
			(m as Unit).command_attack(foes[0], true, true)
			ordered += 1
	print("  приказов атаки орде: %d" % ordered)

	print("\n═════ B. ЗОНДЫ (окна по 10 с) ═════")
	_Opt.telemetry = true
	GameManager.tm_reset()
	var all_units: Array = []
	for s in gob_sids + hum_sids:
		all_units += _members(s)
	var last_strike: Dictionary = {}
	var strike_t: Dictionary = {}       # unit → [моменты ударов]
	var noshoot_since: Dictionary = {}  # unit → с какого времени «в досягаемости, но не бьёт»
	var t0: float = Time.get_ticks_msec() * 0.001
	var win_strikes := {Constants.FACTION_GOBLIN: 0, Constants.FACTION_PLAYER: 0}
	var win_samples := 0
	var win_inreach_idle := 0
	var win_inreach := 0
	var win_contact_far := 0
	var win_attacking := 0
	var win_water := 0
	var win_start: float = t0
	var rows: Array = []
	var last_dmg := {Constants.FACTION_GOBLIN: 0.0, Constants.FACTION_PLAYER: 0.0}
	var frames_total: int = int(_secs * 60.0)
	for f in range(frames_total):
		await get_tree().physics_frame
		if f % 30 != 0:
			continue
		var now: float = Time.get_ticks_msec() * 0.001
		win_samples += 1
		for u0 in all_units:
			if u0 == null or not is_instance_valid(u0):
				continue
			var u := u0 as Unit
			if u.is_dead():
				continue
			var sc: int = u._strike_count
			var prev: int = int(last_strike.get(u, sc))
			if sc > prev:
				win_strikes[int(u.faction)] = int(win_strikes[int(u.faction)]) + (sc - prev)
				if not strike_t.has(u):
					strike_t[u] = []
				(strike_t[u] as Array).append(now)
			last_strike[u] = sc
			if main.is_water(u.global_position.x, u.global_position.z):
				win_water += 1
			if u.state != Unit.State.ATTACKING:
				noshoot_since.erase(u)
				continue
			win_attacking += 1
			var tgt = u.attack_target
			if tgt == null or not is_instance_valid(tgt):
				noshoot_since.erase(u)
				continue
			var d: float = u.global_position.distance_to(tgt.global_position)
			var rng: float = u.attack_range + u._target_pad
			if d <= rng + 0.3:
				win_inreach += 1
				# готов, не ждёт касания, не дремлет — и всё равно не бьёт
				if u._attack_timer <= 0.0 and u._hit_pend_ms == 0 and not u._atk_snooze:
					if not noshoot_since.has(u):
						noshoot_since[u] = now
					elif now - float(noshoot_since[u]) > 0.3:
						win_inreach_idle += 1
				else:
					noshoot_since.erase(u)
			else:
				noshoot_since.erase(u)
				if u._enemy_contact or not u.moved_recently():
					win_contact_far += 1
		if now - win_start >= 10.0:
			var dg: float = _dmg_out(Constants.FACTION_GOBLIN)
			var dp: float = _dmg_out(Constants.FACTION_PLAYER)
			var secs: float = now - win_start
			var row := {
				"t": now - t0,
				"gob_strikes": float(win_strikes[Constants.FACTION_GOBLIN]) / secs,
				"hum_strikes": float(win_strikes[Constants.FACTION_PLAYER]) / secs,
				"gob_dmg": (dg - float(last_dmg[Constants.FACTION_GOBLIN])) / secs,
				"hum_dmg": (dp - float(last_dmg[Constants.FACTION_PLAYER])) / secs,
				"attacking": float(win_attacking) / float(maxi(win_samples, 1)),
				"inreach": float(win_inreach) / float(maxi(win_samples, 1)),
				"inreach_idle": float(win_inreach_idle) / float(maxi(win_samples, 1)),
				"contact_far": float(win_contact_far) / float(maxi(win_samples, 1)),
				"water": float(win_water) / float(maxi(win_samples, 1)),
				"gob_alive": _alive(gob_sids), "hum_alive": _alive(hum_sids),
			}
			rows.append(row)
			print("  [%3.0f с] удары/с орда %.0f / люди %.0f; урон/с орда %.0f / люди %.0f; ATTACKING %.0f, в досягаемости %.0f (из них не бьют > 0.3 с: %.1f), в контакте с недосягаемой целью %.0f; в воде %.1f; живых %d / %d" % [
				row["t"], row["gob_strikes"], row["hum_strikes"], row["gob_dmg"], row["hum_dmg"], row["attacking"], row["inreach"], row["inreach_idle"], row["contact_far"], row["water"], row["gob_alive"], row["hum_alive"]])
			last_dmg[Constants.FACTION_GOBLIN] = dg
			last_dmg[Constants.FACTION_PLAYER] = dp
			win_start = now
			win_samples = 0
			win_strikes = {Constants.FACTION_GOBLIN: 0, Constants.FACTION_PLAYER: 0}
			win_inreach_idle = 0
			win_inreach = 0
			win_contact_far = 0
			win_attacking = 0
			win_water = 0
	# Интервал ударов против кулдауна — по бившим не меньше трёх раз
	var ratios: Array = []
	var missed := 0
	var released := 0
	for u1 in strike_t.keys():
		if u1 == null or not is_instance_valid(u1):
			continue
		var ts: Array = strike_t[u1]
		if ts.size() >= 3:
			var mean: float = (float(ts[ts.size() - 1]) - float(ts[0])) / float(ts.size() - 1)
			var cd: float = (u1 as Unit)._effective_cooldown()
			if cd > 0.05:
				ratios.append(mean / cd)
	for u2 in all_units:
		if u2 != null and is_instance_valid(u2):
			missed += (u2 as Unit).hits_missed
			released += (u2 as Unit).hits_released
	ratios.sort()
	var med_ratio: float = float(ratios[ratios.size() / 2]) if not ratios.is_empty() else -1.0
	print("  интервал/кулдаун у бивших (медиана по %d бойцам): %.2f; касаний %d, промахов %d" % [ratios.size(), med_ratio, released, missed])

	print("\n═════ C. ВЕРДИКТЫ (последние окна) ═════")
	var tail: Array = rows.slice(maxi(rows.size() - 3, 0), rows.size())
	var gob_dmg_ok := false
	var hum_dmg_ok := false
	var idle_frac := 0.0
	var contact_frac := 0.0
	var water_max := 0.0
	for r in tail:
		gob_dmg_ok = gob_dmg_ok or float(r["gob_dmg"]) > 50.0
		hum_dmg_ok = hum_dmg_ok or float(r["hum_dmg"]) > 50.0
		if float(r["inreach"]) > 0.0:
			idle_frac = maxf(idle_frac, float(r["inreach_idle"]) / float(r["inreach"]))
		if float(r["attacking"]) > 0.0:
			contact_frac = maxf(contact_frac, float(r["contact_far"]) / float(r["attacking"]))
		water_max = maxf(water_max, float(r["water"]))
	verdict("F1 обе стороны наносят урон в контакте (> 50/с в окне)", gob_dmg_ok and hum_dmg_ok)
	verdict("F2 «в досягаемости, но не бьёт» — меньше 5 %", idle_frac < 0.05, "%.1f %%" % (idle_frac * 100.0))
	verdict("F3 упёршихся в чужое тело с недосягаемой целью — меньше трети атакующих", contact_frac < 0.34, "%.1f %%" % (contact_frac * 100.0))
	# 1.5, а не 1.3: интервал «первый→последний удар / число ударов» включает
	# паузы на смену цели и пробуждение из дрёмы (полутакт до 133 мс)
	verdict("F4 интервал ударов у бивших не больше 1.5 кулдауна", med_ratio > 0.0 and med_ratio <= 1.5, "медиана %.2f" % med_ratio)
	verdict("F5 промахов отложенного касания меньше 10 %", released == 0 or float(missed) / float(released + missed) < 0.10, "%d из %d" % [missed, released + missed])
	verdict("F6 никто не стоит в воде", water_max < 0.5, "макс %.1f бойцов в выборке" % water_max)
	_finish()

func _dmg_out(fac: int) -> float:
	var byrole: Variant = GameManager.tm_damage_out.get(fac)
	if byrole == null:
		return 0.0
	var s := 0.0
	for k in (byrole as Dictionary):
		s += float((byrole as Dictionary)[k])
	return s

func _alive(sids: Array) -> int:
	var n := 0
	for s in sids:
		n += _members(int(s)).size()
	return n

const _Opt := preload("res://scripts/perf_config.gd")
