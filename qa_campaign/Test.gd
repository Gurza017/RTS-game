extends Node

## ═══════════════════════════════════════════════════════════════════════════
## КОМПЛЕКСНЫЙ СТЕНД: ЭКОНОМИКА → АРМИЯ → ATTACK-MOVE ЧЕРЕЗ ВСЮ КАРТУ
## (ТЗ 10.10.2026, блок 6)
## ═══════════════════════════════════════════════════════════════════════════
## A — партия: казна игрока платит за наём (бараки ×2, стрелковая, крепость
##     нанимают НАСТОЯЩИМ queue_unit с ценой конфига, время ×TRAIN_SCALE),
##     дома поднимают лимит, затем ВСЯ армия выделяется и получает Attack-Move
##     на деревню орды тем же входом, что ПКМ/ЛКМ мини-карты
##     (SelectionManager.order_at_world). Путь: проходы в лесной стене базы,
##     охрана рудника орды, брод, стена деревни. Зонды: отставшие (дальше
##     STRAY_M от медианы отряда), застрявшие (отряд идёт, боец стоит),
##     в глубокой воде, сканы командира, A* (худший, построено/провалено),
##     физкадр (стенной интервал: p50/p99/худший) и tick_meter.
## B — удар во фланг: 15 отрядов идут Attack-Move по полю, в тыл врезаются
##     два отряда гоблинов — разворачивается вся группа (и лучники), угроза
##     добита, марш возобновлён, все дошли.
## C — свиновсадники командира конницы против армии на марше: натиск есть,
##     армия добивает и доходит, без ошибок.
## Запуск: godot --headless --path . res://qa_campaign/Test.tscn [-- only=abc]
## Провалы искать по «НЕ ПРОШЛО» / «провалов:».

const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const STRAY_M := 8.0
const TRAIN_SCALE := 0.15
## Зона деревни орды: армия, дошедшая сюда, — у цели (дальше — штурм)
const VILLAGE_R := 90.0

var main = null
var sm = null
var cmd = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abc"
var _diag := false

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(1500.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_campaign: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

# ─────────────────────────────────────────────────────────────────────────────
# СЛУЖЕБНОЕ
# ─────────────────────────────────────────────────────────────────────────────
func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead() and not (m as Unit).garrisoned:
			o.append(m)
	return o

func _median(men: Array) -> Vector3:
	var xs: Array = []
	var zs: Array = []
	for u in men:
		xs.append((u as Unit).global_position.x)
		zs.append((u as Unit).global_position.z)
	xs.sort()
	zs.sort()
	return Vector3(float(xs[xs.size() / 2]), 0.0, float(zs[zs.size() / 2]))

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int, gap: float = 0.6) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var u := _unit(uid, f, at + Vector3(float(i / cols) * gap, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * gap))
		GameManager.add_to_squad(sid, u)
	return sid

func _kill_faction_units(fac: int, keep_near: Vector3 = Vector3.INF, keep_r: float = 0.0) -> void:
	for n0 in get_tree().get_nodes_in_group(Constants.unit_group(fac)):
		if not is_instance_valid(n0) or not (n0 is Unit):
			continue
		var u := n0 as Unit
		if keep_near != Vector3.INF and u.global_position.distance_to(keep_near) < keep_r:
			continue
		u.take_damage(1.0e12)

func _freeze_wilds() -> void:
	for k in ["enemy_ai", "gnoll_ai", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
			n.set_physics_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for n0 in get_tree().get_nodes_in_group("all_units"):
		if not is_instance_valid(n0) or not (n0 is Unit):
			continue
		var u := n0 as Unit
		if u.stat_id == "troll" or u.stat_id == "gnoll":
			u.take_damage(1.0e12)
	# Красный ИИ в кампании не участвует (иначе его армия — случайная переменная)
	_kill_faction_units(Constants.FACTION_ENEMY)

## Зонд строя по набору отрядов: {"stray": худший по отряду, "stray_sum",
## "ext": худший поперечник, "water": бойцов в глубокой воде}
## Отставший считается ТОЛЬКО в отряде на марше (командир не числит стычку),
## и не в панике/отходе: это и есть «разрыв строя», а не рассыпание в бою.
## Причины прочих выносятся отдельно (why)
func _probe(sids: Array) -> Dictionary:
	var worst := 0
	var ssum := 0
	var ext := 0.0
	var water := 0
	var why := {"бой": 0, "паника": 0, "отход": 0, "IDLE": 0, "MOVING": 0}
	var pieces := 0
	var per: Dictionary = {}
	for s in sids:
		var men: Array = _members(int(s))
		if men.size() < 3:
			continue
		var c: Vector3 = _median(men)
		var st := 0
		var fighting: bool = cmd.is_fighting(int(s)) or GameManager.squad_in_combat(int(s))
		var body: Dictionary = _main_body(men)
		for u in men:
			var uu := u as Unit
			var p: Vector3 = uu.global_position
			var d: float = Vector2(p.x - c.x, p.z - c.z).length()
			if main.has_method("is_water") and main.is_water(p.x, p.z) and not main.in_ford(p.z):
				water += 1
			if body.has(uu):
				continue
			# Дальше DETACH_M от ближайшего бойца тела — оторвался; ближе —
			# это просвет внутри колонны (печатается как «куски»)
			var dn := INF
			for bu in body:
				dn = minf(dn, Vector2((bu as Unit).global_position.x - p.x, (bu as Unit).global_position.z - p.z).length())
			if dn <= DETACH_M:
				pieces += 1
				continue
			if uu._panicked:
				why["паника"] += 1
			elif uu.retreating:
				why["отход"] += 1
			elif fighting or uu.state == Unit.State.ATTACKING:
				why["бой"] += 1
			else:
				st += 1
				ext = maxf(ext, d)
				why["IDLE" if uu.state == Unit.State.IDLE else "MOVING"] += 1
		worst = maxi(worst, st)
		ssum += st
		per[int(s)] = st
	why["просвет<10м"] = pieces
	return {"stray": worst, "stray_sum": ssum, "ext": ext, "water": water, "why": why, "per": per}

## РАЗРЫВ — ЭТО ОТРЫВ ОТ ТЕЛА ОТРЯДА, А НЕ ДЛИНА КОЛОННЫ. Тело — самая
## большая компонента связности по звену LINK_M (соседи ближе звена — одно
## целое). Колонна в узкости длинная, но связная; оторвавшиеся 1-3 бойца —
## вне тела. Отставших до LINK_M от тела нет по построению
const LINK_M := 3.0
const DETACH_M := 10.0
func _main_body(men: Array) -> Dictionary:
	var n: int = men.size()
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var px := PackedFloat32Array()
	var pz := PackedFloat32Array()
	px.resize(n); pz.resize(n)
	for i in range(n):
		var p: Vector3 = (men[i] as Unit).global_position
		px[i] = p.x
		pz[i] = p.z
	var best_c := -1
	var best_n := 0
	var cid := 0
	var l2: float = LINK_M * LINK_M
	for i0 in range(n):
		if comp[i0] >= 0:
			continue
		var stack: Array = [i0]
		comp[i0] = cid
		var cnt := 0
		while not stack.is_empty():
			var i: int = stack.pop_back()
			cnt += 1
			for j in range(n):
				if comp[j] >= 0:
					continue
				var dx: float = px[i] - px[j]
				var dz: float = pz[i] - pz[j]
				if dx * dx + dz * dz <= l2:
					comp[j] = cid
					stack.append(j)
		if cnt > best_n:
			best_n = cnt
			best_c = cid
		cid += 1
	var out: Dictionary = {}
	for k in range(n):
		if comp[k] == best_c:
			out[men[k]] = true
	return out

## Диагностика: на какие куски поделился отряд (звено LINK_M)
func _dump_parts(sids: Array, dest: Vector3) -> void:
	for s in sids:
		var men: Array = _members(int(s))
		if men.size() < 3:
			continue
		var body: Dictionary = _main_body(men)
		if men.size() - body.size() < 5:
			continue
		var bc := Vector3.ZERO
		var oc := Vector3.ZERO
		var on := 0
		var st := {}
		var paces := {}
		for u in men:
			var uu := u as Unit
			if body.has(uu):
				bc += uu.global_position
			else:
				oc += uu.global_position
				on += 1
				st[int(uu.state)] = int(st.get(int(uu.state), 0)) + 1
				paces[uu.pace_mult] = int(paces.get(uu.pace_mult, 0)) + 1
		bc /= float(body.size())
		oc /= float(maxi(on, 1))
		print("      куски: отряд %d тело %d в (%.0f, %.0f) до цели %.0f м; вне тела %d в среднем (%.0f, %.0f) до цели %.0f м, состояния %s, темп %s, AM=%s бой=%s" % [
			int(s), body.size(), bc.x, bc.z, Vector2(bc.x - dest.x, bc.z - dest.z).length(), on, oc.x, oc.z,
			Vector2(oc.x - dest.x, oc.z - dest.z).length(), str(st), str(paces), str(cmd.is_attack_moving(int(s))), str(cmd.is_fighting(int(s)))])

## Диагностика: кто дальше 20 м от медианы своего отряда — где и в каком
## состоянии
var f_dump := 0
func _dump_far(sids: Array) -> void:
	f_dump += 1
	for s in sids:
		var men: Array = _members(int(s))
		if men.size() < 3:
			continue
		var c: Vector3 = _median(men)
		var printed := false
		for u in men:
			var uu := u as Unit
			var p: Vector3 = uu.global_position
			var d: float = Vector2(p.x - c.x, p.z - c.z).length()
			if d > (20.0 if f_dump > 1 else 6.0) and not printed and f_dump == 1:
				printed = true
				var near_u: Unit = null
				for u2 in men:
					if (u2 as Unit).global_position.distance_to(c) < 3.0:
						near_u = u2
						break
				if near_u != null and near_u._route.size() > 0:
					var rs := ""
					for q in near_u._route:
						rs += "(%.0f,%.0f) " % [q.x, q.z]
					print("        обычный боец отряда %d: маршрут %s" % [int(s), rs])
				var rs2 := ""
				for q2 in uu._route:
					rs2 += "(%.0f,%.0f) " % [q2.x, q2.z]
				print("        отставший: маршрут %s" % rs2)
			if d > (20.0 if f_dump > 1 else 6.0):
				print("      дальний: отряд %d (%s) боец в (%.1f, %.1f), до медианы %.1f м, состояние %d, пост (%.1f, %.1f), цель %s, путь %d точек" % [
					int(s), uu.stat_id, p.x, p.z, d, int(uu.state), uu.post_pos.x, uu.post_pos.z,
					str(uu.attack_target), uu._route.size()])
				if uu._route.size() > 0:
					print("        маршрут: первая (%.1f, %.1f), последняя (%.1f, %.1f); медиана отряда (%.1f, %.1f)" % [
						uu._route[0].x, uu._route[0].z, uu._route[uu._route.size() - 1].x, uu._route[uu._route.size() - 1].z, c.x, c.z])

## Застрявшие (окно 6 с): см. условие ниже
var _stuck_prev: Dictionary = {}
var _det_run: Dictionary = {}
var _stuck_cprev: Dictionary = {}
func _stuck_count(sids: Array) -> int:
	var n := 0
	for s in sids:
		var men: Array = _members(int(s))
		if men.is_empty():
			continue
		var c: Vector3 = _median(men)
		var cprev: Variant = _stuck_cprev.get(int(s))
		_stuck_cprev[int(s)] = c
		var moved: bool = cprev != null and c.distance_to(cprev as Vector3) > 6.0
		for u in men:
			var p: Vector3 = (u as Unit).global_position
			var prev: Variant = _stuck_prev.get(u)
			_stuck_prev[u] = p
			# ЗАСТРЯЛ — окно 6 с: отряд ушёл дальше 6 м, боец сдвинулся меньше
			# 0.4 м, не в бою и уже ПОЗАДИ тела (дальше 8 м от медианы). Ожидание
			# в заторе у брода (стоит в колонне в 2-3 м от центра) — не застревание
			if moved and prev != null and p.distance_to(prev as Vector3) < 0.4 \
					and (u as Unit).state != Unit.State.ATTACKING \
					and Vector2(p.x - c.x, p.z - c.z).length() > 8.0:
				n += 1
				if n <= 2:
					var uu := u as Unit
					print("      застрял: отряд %d (%s) в (%.1f, %.1f), до медианы %.1f м, состояние %d, пост (%.1f, %.1f), путь %d, темп %.2f, отход %s" % [
						int(s), uu.stat_id, p.x, p.z, Vector2(p.x - c.x, p.z - c.z).length(), int(uu.state),
						uu.post_pos.x, uu.post_pos.z, uu._route.size(), uu.pace_mult, str(uu.retreating)])
	return n

## Стенные интервалы физкадров (мс)
var _ft: PackedFloat32Array = PackedFloat32Array()
var _ft_last: int = 0
func _ft_tick() -> void:
	var now: int = Time.get_ticks_usec()
	if _ft_last > 0:
		_ft.append(float(now - _ft_last) / 1000.0)
	_ft_last = now

func _ft_report(label: String) -> Dictionary:
	if _ft.is_empty():
		return {"p50": 0.0, "p99": 0.0, "max": 0.0}
	var a: Array = Array(_ft)
	a.sort()
	var r := {"p50": float(a[a.size() / 2]), "p99": float(a[int(a.size() * 0.99)]), "max": float(a[a.size() - 1])}
	print("    %s: физкадр p50 %.1f мс, p99 %.1f мс, худший %.1f мс (кадров %d); tick_meter %.2f мс" % [
		label, r["p50"], r["p99"], r["max"], a.size(), _Opt.tick_ms()])
	return r

## ЦЕНА КОМАНДИРА ATTACK-MOVE (A/B адаптивного скана): всего сканов, сканов
## в худшем кадре, мкс командира на кадр, «график» сканов по секундам
func _cmd_report(label: String, game_s: float, n_sq: int) -> Dictionary:
	var us: Array = Array(cmd.frame_usec)
	var sc: Array = Array(cmd.frame_scans)
	var total := 0
	var sc_max := 0
	for v in sc:
		total += int(v)
		sc_max = maxi(sc_max, int(v))
	us.sort()
	var p50: float = float(us[us.size() / 2]) if not us.is_empty() else 0.0
	var p99: float = float(us[int(us.size() * 0.99)]) if not us.is_empty() else 0.0
	var umax: float = float(us[us.size() - 1]) if not us.is_empty() else 0.0
	var graph := ""
	var bars := " ▁▂▃▄▅▆▇█"
	var bs: Array = Array(cmd.scans_by_sec)
	var bmax := 1
	for b in bs:
		bmax = maxi(bmax, int(b))
	for b2 in bs:
		graph += bars[clampi(int(round(float(int(b2)) / float(bmax) * 8.0)), 0, 8)]
	var rate: float = float(total) / maxf(game_s, 1.0) / float(maxi(n_sq, 1))
	print("    КОМАНДИР %s [адаптивно=%s]: сканов %d (%.2f на отряд/с), в худшем кадре %d; цена кадра p50 %.0f мкс, p99 %.0f мкс, худший %.0f мкс" % [
		label, str(_Opt.am_adaptive), total, rate, sc_max, p50, p99, umax])
	print("    сканы по секундам (пик %d/с): %s" % [bmax, graph])
	print("    очередь приказов [вкл=%s]: поставлено %d, роздано %d, снято отменой %d, глубина до %d, ожидание до %d кадров; самый дорогой приказ %d мкс, такт отряда %d мкс" % [
		str(_Opt.am_order_queue), cmd.oq_queued, cmd.oq_issued, cmd.oq_dropped, cmd.oq_depth_max, cmd.oq_wait_max,
		cmd.oq_issue_max_us, cmd.tick_max_us])
	return {"total": total, "rate": rate, "sc_max": sc_max, "p99": p99, "max": umax}

func _ft_reset() -> void:
	_ft = PackedFloat32Array()
	_ft_last = 0
	_Opt.tick_reset()

# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
		if s == "diag=1":
			_diag = true
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	sm = main.selection_manager
	cmd = sm.squad_commander()
	_Opt.tick_meter = true
	_freeze_wilds()
	await pframes(4)
	if _only.contains("a"):
		await _block_a()
	if _only.contains("b"):
		await _block_b()
	if _only.contains("c"):
		await _block_c()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ПАРТИЯ: ЭКОНОМИКА → НАЁМ → ATTACK-MOVE НА ДЕРЕВНЮ ОРДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _place(script_path: String, at: Vector3) -> Building:
	main._clear_area_of_resources(at, 9.0)
	var b: Building = load(script_path).new()
	b.faction = F
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return b

func _block_a() -> void:
	print("\n═════ A. ПАРТИЯ: ЭКОНОМИКА → АРМИЯ → ATTACK-MOVE НА ДЕРЕВНЮ ОРДЫ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR
	var village: Vector3 = main.goblin_village_center()
	village.y = 0.0
	# Постройки: два барака, стрелковая, дома под лимит
	var bar1: Building = _place("res://scripts/Barracks.gd", base + Vector3(22.0, 0, 14.0))
	var bar2: Building = _place("res://scripts/Barracks.gd", base + Vector3(22.0, 0, -6.0))
	var arch: Building = _place("res://scripts/Archery.gd", base + Vector3(8.0, 0, 26.0))
	var hx := 0
	while GameManager.pop_army_cap(F) < 760 and hx < 60:
		_place("res://scripts/House.gd", base + Vector3(-14.0 + float(hx % 6) * 4.0, 0, -26.0 - float(hx / 6) * 4.0))
		hx += 1
	await pframes(10)
	print("    домов %d, лимит армии %d" % [hx, GameManager.pop_army_cap(F)])
	var bank0 := 0.0
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_FOOD, Constants.RESOURCE_STONE]:
		bank0 += ResourceManager.get_amount(F, int(r))
	var plan := [[bar1, "barracks", "spearman", 4], [bar2, "barracks", "spearman", 4],
		[bar1, "barracks", "warrior", 1], [bar2, "barracks", "warrior", 1], [arch, "archery", "archer", 4]]
	# ДОХОД АРТЕЛИ: рабочие партии сдают ресурсы на склад (стенд не ждёт
	# 10 минут добычи — приход начисляется тем же add_resource, что у сдачи)
	for rt in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(F, int(rt), 3000.0)
	bank0 += 9000.0
	var ordered := 0
	for row in plan:
		var b: Building = row[0]
		for i in range(int(row[3])):
			var cfg: Dictionary = _UCfg.train_cfg(String(row[1]), String(row[2]))
			b.squad_size = int(cfg.get("squad", 20))
			b.squad_cols = int(cfg.get("cols", 5))
			if b.queue_unit(String(row[2]), _UCfg.train_cost(String(row[1]), String(row[2])),
					float(cfg.get("time", 20.0)) * TRAIN_SCALE):
				ordered += 1
	var spent := bank0
	for r2 in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_FOOD, Constants.RESOURCE_STONE]:
		spent -= ResourceManager.get_amount(F, int(r2))
	print("    заказано отрядов %d, списано ресурсов %.0f" % [ordered, spent])
	verdict("A1 наём оплачен казной и принят (заказов %d из 14)" % ordered, ordered == 14 and spent > 0.0)
	# Ждём выхода всех (потолок 120 с)
	var sids: Array = []
	var t := 0
	while t < 60 * 120:
		await pframes(30)
		t += 30
		sids.clear()
		for k in GameManager.squads.keys():
			var sq: Dictionary = GameManager.squads[k]
			if int(sq.get("faction", -1)) == F and String(sq.get("type", "")) in ["spearman", "warrior", "archer"]:
				if _members(int(k)).size() > 0:
					sids.append(int(k))
		var busy := false
		for b2 in [bar1, bar2, arch]:
			if not (b2 as Building).production_queue.is_empty():
				busy = true
			if "_pending_spawns" in b2 and not (b2._pending_spawns as Array).is_empty():
				busy = true
		if not busy and sids.size() >= 14:
			break
	await pframes(60)
	var men_n := 0
	for s in sids:
		men_n += _members(int(s)).size()
	print("    вышло отрядов %d, бойцов %d за %.0f с" % [sids.size(), men_n, float(t) / 60.0])
	verdict("A2 армия вышла из зданий (отрядов %d ≥ 14)" % sids.size(), sids.size() >= 14)
	# ── ATTACK-MOVE: тот же вход, что у мини-карты и клика в режиме [A] ──────
	var all_men: Array = []
	for s2 in sids:
		all_men.append_array(_members(int(s2)))
	sm.select_units(all_men)
	await pframes(2)
	sm.set_attack_move_armed(true)
	var ok_order: bool = sm.order_at_world(village, true)
	var am_n := 0
	for s3 in sids:
		if cmd.is_attack_moving(int(s3)):
			am_n += 1
	verdict("A3 Attack-Move отдан всей армии одним приказом (%d из %d)" % [am_n, sids.size()],
		ok_order and am_n == sids.size() and not sm.attack_move_armed)
	# ── МАРШ ──────────────────────────────────────────────────────────────────
	var scans0: int = cmd.scans
	var eng0: int = cmd.engagements
	var nav_b0: int = GameManager.nav_routes_built
	var nav_f0: int = GameManager.nav_routes_failed
	GameManager.nav_worst_usec = 0
	_ft_reset()
	cmd.stat_reset()
	_stuck_prev.clear(); _stuck_cprev.clear()
	var stray_worst := 0
	var stray_ford_worst := 0
	var stuck_worst := 0
	_det_run.clear()
	var det_s := 0.0
	var det_ford_s := 0.0
	var water_worst := 0
	var crossed: Dictionary = {}
	var arrived_t := -1
	var f := 0
	var limit: int = 60 * (185 if _diag else 420)
	var t0_ms: int = Time.get_ticks_msec()
	var rx: float = main.river_x(0.0)
	while f < limit:
		await get_tree().physics_frame
		_ft_tick()
		f += 1
		if f % 30 != 0:
			continue
		var pr: Dictionary = _probe(sids)
		water_worst = maxi(water_worst, int(pr["water"]))
		# У брода (центр отряда в 25 м от середины брода) — отдельный учёт
		var at_ford := false
		var near := 0
		var alive_sq := 0
		for s4 in sids:
			var men4: Array = _members(int(s4))
			if men4.is_empty():
				continue
			alive_sq += 1
			var c4: Vector3 = _median(men4)
			if Vector2(c4.x - rx, c4.z).length() < 25.0:
				at_ford = true
			if c4.x > rx + 3.0:
				crossed[int(s4)] = true
			if Vector2(c4.x - village.x, c4.z - village.z).length() < VILLAGE_R:
				near += 1
		if at_ford:
			stray_ford_worst = maxi(stray_ford_worst, int(pr["stray"]))
		else:
			stray_worst = maxi(stray_worst, int(pr["stray"]))
		if f == 60 * 12 or f == 60 * 2:
			_dump_far(sids)
		if _diag and f % (60 * 15) == 0 and f >= 60 * 60:
			_dump_parts(sids, village)
		# ДЛИТЕЛЬНОСТЬ ОТРЫВА: сколько подряд замеров у отряда есть оторвавшиеся
		for s7 in sids:
			var k7: int = int(s7)
			var det: int = int((pr["per"] as Dictionary).get(k7, 0))
			var run7: int = int(_det_run.get(k7, 0))
			run7 = run7 + 1 if det > 0 else 0
			_det_run[k7] = run7
			if run7 == 16:
				var m7: Array = _members(k7)
				var b7: Dictionary = _main_body(m7)
				var c7: Vector3 = _median(m7)
				for u7 in m7:
					if b7.has(u7):
						continue
					var uu7 := u7 as Unit
					var q7: Vector3 = uu7.global_position
					print("      отрыв 8 с: отряд %d (%s, %d бойцов, тело %d) боец (%.1f, %.1f) до медианы %.1f, состояние %d, пост (%.0f, %.0f), путь %d, темп %.2f, цель %s, отход %s, паника %s, у брода %s" % [
						k7, uu7.stat_id, m7.size(), b7.size(), q7.x, q7.z, Vector2(q7.x - c7.x, q7.z - c7.z).length(), int(uu7.state),
						uu7.post_pos.x, uu7.post_pos.z, uu7._route.size(), uu7.pace_mult, str(uu7.attack_target), str(uu7.retreating), str(uu7._panicked), str(at_ford)])
			if at_ford:
				det_ford_s = maxf(det_ford_s, float(run7) * 0.5)
			else:
				det_s = maxf(det_s, float(run7) * 0.5)
		if f % 360 == 0:
			var stk: int = _stuck_count(sids)
			stuck_worst = maxi(stuck_worst, stk)
			var ac := Vector3.ZERO
			var an := 0
			var men_all: Array = []
			for s6 in sids:
				var m6: Array = _members(int(s6))
				men_all.append_array(m6)
			if not men_all.is_empty():
				ac = _median(men_all)
			var gob := 0
			for g in get_tree().get_nodes_in_group(Constants.unit_group(G)):
				if is_instance_valid(g) and not (g as Unit).is_dead() 						and (g as Unit).global_position.distance_to(ac) < 45.0:
					gob += 1
			print("    t=%3d с: армия (%.0f, %.0f) бойцов %d, гоблинов в 45 м %d, у деревни %d/%d | оторвались (>10 м от тела) худший %d (сумма %d, дальний %.1f м), прочие вне строя %s | застрявших %d, в воде %d, за рекой %d" % [
				f / 60, ac.x, ac.z, men_all.size(), gob, near, alive_sq, int(pr["stray"]), int(pr["stray_sum"]),
				float(pr["ext"]), str(pr["why"]), stk, int(pr["water"]), crossed.size()])
		if arrived_t < 0 and alive_sq > 0 and near >= int(ceil(float(alive_sq) * 0.8)):
			arrived_t = f
			print("    армия у деревни на %d с" % (f / 60))
			break
	var wall_s: float = float(Time.get_ticks_msec() - t0_ms) / 1000.0
	var game_s: float = float(f) / 60.0
	var ft: Dictionary = _ft_report("марш")
	_cmd_report("марш A", game_s, sids.size())
	var scans: int = cmd.scans - scans0
	var sq_n: int = maxi(sids.size(), 1)
	var scan_rate: float = float(scans) / maxf(game_s, 1.0) / float(sq_n)
	print("    сканы командира %d за %.0f с (%.2f на отряд в секунду; такт %.2f с → потолок %.2f), стычек %d" % [
		scans, game_s, scan_rate, cmd.AM_TICK_SEC, 1.0 / cmd.AM_TICK_SEC, cmd.engagements - eng0])
	print("    A*: построено %d, провалено %d, худший %.2f мс; стена %.0f с" % [
		GameManager.nav_routes_built - nav_b0, GameManager.nav_routes_failed - nav_f0,
		float(GameManager.nav_worst_usec) / 1000.0, wall_s])
	verdict("A4 армия дошла до деревни орды через брод (%s, перешли реку %d)" % [
		("за %d с" % (arrived_t / 60)) if arrived_t >= 0 else "не дошла", crossed.size()],
		arrived_t >= 0 and crossed.size() >= int(ceil(float(sids.size()) * 0.8)))
	print("    оторвавшиеся (>10 м от тела): вне брода худший %d, дольше всего %.1f с; у брода худший %d, дольше всего %.1f с" % [
		stray_worst, det_s, stray_ford_worst, det_ford_s])
	verdict("A5 в пути разрыв не держится: оторвавшиеся возвращаются в отряд за ≤ 12 с (дольше всего %.1f с)" % det_s, det_s <= 12.0)
	verdict("A6 брод: строй ужимается и после выхода смыкается — отрыв у брода ≤ 15 с (дольше всего %.1f с)" % det_ford_s, det_ford_s <= 15.0)
	verdict("A7 застрявших бойцов нет (худший %d)" % stuck_worst, stuck_worst == 0)
	verdict("A8 в глубокую воду никто не зашёл (худший %d)" % water_worst, water_worst == 0)
	verdict("A9 скан один на отряд за такт (%.2f/с ≤ %.2f)" % [scan_rate, 1.1 / cmd.AM_TICK_SEC],
		scan_rate <= 1.1 / cmd.AM_TICK_SEC)
	verdict("A10 A* худший %.2f мс (< 15: разовый пик — дорога через всю карту на приказ армии)" % (float(GameManager.nav_worst_usec) / 1000.0),
		GameManager.nav_worst_usec < 15000)
	# Бой у деревни — 40 с: без ошибок, урон нанесён
	_ft_reset()
	# Гоблины в зоне боя (120 м от деревни) на начало штурма — сколько их
	# падёт за 40 с (численность орды врёт: деревня донанимает)
	var watch: Array = []
	for gn in get_tree().get_nodes_in_group(Constants.unit_group(G)):
		if is_instance_valid(gn) and not (gn as Unit).is_dead() 				and (gn as Unit).global_position.distance_to(village) < 120.0:
			watch.append(gn)
	var g0: int = watch.size()
	for _k in range(60 * 40):
		await get_tree().physics_frame
		_ft_tick()
	var g1 := 0
	for gw in watch:
		if not is_instance_valid(gw) or (gw as Unit).is_dead():
			g1 += 1
	_ft_report("бой у деревни")
	print("    гоблинов в зоне боя %d, пало за 40 с %d" % [g0, g1])
	verdict("A11 бой у деревни идёт: орда несёт потери (пало %d из %d)" % [g1, g0], g1 > 0)
	# Чистим перед следующими блоками
	for s5 in sids:
		cmd.cancel_squad(int(s5))
		for u in _members(int(s5)):
			(u as Unit).take_damage(1.0e12)
	sm.clear_selection()
	await pframes(30)

# ═════════════════════════════════════════════════════════════════════════════
# B. УДАР ВО ФЛАНГ: РАЗВОРАЧИВАЕТСЯ ВСЯ ГРУППА
# ═════════════════════════════════════════════════════════════════════════════
func _field() -> Vector3:
	# Сухое поле на нашем берегу, в стороне от баз и рудников
	var p := Vector3(-120.0, 0.0, 10.0)
	main._clear_area_of_resources(p + Vector3(40, 0, 0), 90.0)
	for rn in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(rn) and (rn as Node3D).global_position.distance_to(p + Vector3(40, 0, 0)) < 90.0:
			(rn as Node).queue_free()
	_kill_faction_units(G, main.goblin_village_center(), 70.0)
	# ИИ орды усыновляет отряды стенда и уводит их к деревне — в полевых
	# блоках им командует только сам сценарий (и командир конницы)
	for k in ["goblin_ai", "goblin_reserve"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
			n.set_physics_process(false)
	return p

func _army15(at: Vector3) -> Array:
	var sids: Array = []
	var kinds := ["spearman", "spearman", "spearman", "spearman", "spearman",
		"warrior", "spearman", "warrior", "spearman", "warrior",
		"archer", "archer", "spearman", "archer", "archer"]
	for i in range(15):
		var uid: String = kinds[i]
		var col: int = i % 5
		var row: int = i / 5
		var n: int = 30 if uid == "spearman" else 20
		sids.append(_squad(uid, F, at + Vector3(-float(row) * 12.0, 0.0, -24.0 + float(col) * 12.0), n, 6, 0.65))
	return sids

func _block_b() -> void:
	print("\n═════ B. УДАР ВО ФЛАНГ ИДУЩЕЙ АРМИИ ═════")
	var p: Vector3 = _field()
	await pframes(10)
	var sids: Array = _army15(p)
	await pframes(30)
	var all_men: Array = []
	for s in sids:
		all_men.append_array(_members(int(s)))
	sm.select_units(all_men)
	var dest: Vector3 = p + Vector3(90.0, 0.0, 0.0)
	sm.order_at_world(dest, true)
	var ast0: int = cmd.assists
	var hr0: int = cmd.hit_reacts
	cmd.stat_reset()
	var tb0: int = Time.get_ticks_msec()
	await pframes(60 * 8)
	# Два отряда гоблинов врезаются в ТЫЛ-ФЛАНГ (за последним рядом, сбоку)
	var rear: Vector3 = _median(_members(int(sids[10])))
	var g1: int = _squad("goblin_spearman", G, rear + Vector3(-14.0, 0.0, -20.0), 35, 7, 0.9)
	var g2: int = _squad("goblin_spearman", G, rear + Vector3(-16.0, 0.0, 22.0), 35, 7, 0.9)
	await pframes(2)
	for gs in [g1, g2]:
		var tgt: Array = _members(int(sids[10 + (0 if gs == g1 else 4)]))
		for u in _members(int(gs)):
			(u as Unit).command_attack(tgt[0], true, false, true)
	var turned: Dictionary = {}
	var archers_turned := 0
	var killed_t := -1
	var f := 0
	while f < 60 * 70:
		await pframes(10)
		f += 10
		for s2 in sids:
			if cmd.is_fighting(int(s2)) and not turned.has(int(s2)):
				turned[int(s2)] = true
				if GameManager.squad_type(int(s2)) == "archer":
					archers_turned += 1
		if _members(g1).is_empty() and _members(g2).is_empty():
			killed_t = f
			break
		if f % 300 == 0:
			var gm: Array = _members(g1) + _members(g2)
			var gc: Vector3 = _median(gm) if not gm.is_empty() else Vector3.ZERO
			var fl := ""
			for s9 in sids:
				var m9: Array = _members(int(s9))
				if m9.is_empty():
					fl += "x"
					continue
				var c9: Vector3 = _median(m9)
				fl += "%s%d " % ["F" if cmd.is_fighting(int(s9)) else ("A" if cmd.is_attack_moving(int(s9)) else "-"),
					int(Vector2(c9.x - gc.x, c9.z - gc.z).length())]
			print("      t=%d с: гоблинов %d в (%.0f, %.0f); отряды (режим, до гоблинов м): %s" % [f / 60, gm.size(), gc.x, gc.z, fl])
	print("    развернулось отрядов %d из 15 (лучников %d), помощь группе %d, ответ на удар %d, угроза добита %s" % [
		turned.size(), archers_turned, cmd.assists - ast0, cmd.hit_reacts - hr0,
		("за %.1f с" % (float(killed_t) / 60.0)) if killed_t >= 0 else "нет"])
	_cmd_report("фланг B", float(Time.get_ticks_msec() - tb0) / 1000.0, 15)
	verdict("B1 на удар во фланг развернулась вся группа (%d из 15 ≥ 12)" % turned.size(), turned.size() >= 12)
	verdict("B2 лучники тоже развернулись (%d из 4)" % archers_turned, archers_turned >= 3)
	verdict("B3 угроза подавлена и добита за 70 с", killed_t >= 0)
	# Марш возобновился — все дошли
	var arrived := 0
	var stray_end := 0
	f = 0
	while f < 60 * 90:
		await pframes(30)
		f += 30
		arrived = 0
		for s3 in sids:
			var men: Array = _members(int(s3))
			if men.is_empty():
				continue
			var c: Vector3 = _median(men)
			if _arrived_at(men, c, dest):
				arrived += 1
		if arrived >= 14:
			break
	await pframes(60 * 4)
	stray_end = int(_probe(sids)["stray_sum"])
	print("    дошли %d из 15, отставших в конце %d" % [arrived, stray_end])
	verdict("B4 после стычки марш возобновлён: дошли %d из 15 (≥ 14)" % arrived, arrived >= 14)
	verdict("B5 в точке без разрывов (отставших %d)" % stray_end, stray_end <= 1)
	for s4 in sids:
		cmd.cancel_squad(int(s4))
		for u in _members(int(s4)):
			(u as Unit).take_damage(1.0e12)
	sm.clear_selection()
	await pframes(30)

# ═════════════════════════════════════════════════════════════════════════════
# C. СВИНОВСАДНИКИ ПРОТИВ АРМИИ НА МАРШЕ
# ═════════════════════════════════════════════════════════════════════════════
func _block_c() -> void:
	print("\n═════ C. СВИНОВСАДНИКИ (КОМАНДИР КОННИЦЫ) ПРОТИВ ARMY ATTACK-MOVE ═════")
	var p: Vector3 = _field()
	await pframes(10)
	var sids: Array = _army15(p)
	await pframes(30)
	var all_men: Array = []
	for s in sids:
		all_men.append_array(_members(int(s)))
	var hp0 := 0.0
	for u in all_men:
		hp0 += (u as Unit).current_health
	sm.select_units(all_men)
	var dest: Vector3 = p + Vector3(90.0, 0.0, 0.0)
	sm.order_at_world(dest, true)
	var imp0: int = Unit.cav_impacts_dealt
	var riders: Array = []
	for k in range(2):
		riders.append(_squad("goblin_rider", G, p + Vector3(35.0, 0.0, -48.0 + 96.0 * float(k)), 12, 4, 1.2))
	await pframes(4)
	var cc = main.get("cav_commander")
	var cc_on: bool = cc != null and is_instance_valid(cc) and _Opt.cav_commander
	# Приказов всадникам НЕ даём: цель находит и ведёт командир конницы
	var f := 0
	var riders_dead_t := -1
	while f < 60 * 80:
		await pframes(10)
		f += 10
		var left := 0
		for rs2 in riders:
			left += _members(int(rs2)).size()
		if f % 300 == 0 and cc != null and is_instance_valid(cc):
			var st_s := ""
			for rs4 in riders:
				var mm: Array = _members(int(rs4))
				var cpos: Vector3 = _median(mm) if not mm.is_empty() else Vector3.ZERO
				st_s += "%d:%s@(%.0f,%.0f) " % [int(rs4), cc.state_of(int(rs4)), cpos.x, cpos.z]
			print("      t=%d с: всадники %s; натисков командира %d, сканов %d" % [f / 60, st_s, cc.charges, cc.scans])
		if left == 0:
			riders_dead_t = f
			break
	var hp1 := 0.0
	for u2 in all_men:
		if is_instance_valid(u2) and not (u2 as Unit).is_dead():
			hp1 += (u2 as Unit).current_health
	var left2 := 0
	for rs3 in riders:
		left2 += _members(int(rs3)).size()
	print("    командир конницы %s, натисков %d, урон армии %.0f, всадников осталось %d%s" % [
		"включён" if cc_on else "выключен", Unit.cav_impacts_dealt - imp0, hp0 - hp1, left2,
		(", выбиты за %.1f с" % (float(riders_dead_t) / 60.0)) if riders_dead_t >= 0 else ""])
	verdict("C1 свиновсадники идут в натиск и наносят урон (натисков %d, урон %.0f)" % [
		Unit.cav_impacts_dealt - imp0, hp0 - hp1], hp0 - hp1 > 0.0)
	verdict("C2 армия выбивает конницу: из 24 всадников осталось %d (≤ 12; натиск-отход по замыслу)" % left2, left2 <= 12)
	var arrived := 0
	f = 0
	while f < 60 * 90:
		await pframes(30)
		f += 30
		arrived = 0
		for s3 in sids:
			var men: Array = _members(int(s3))
			if men.is_empty():
				continue
			var c: Vector3 = _median(men)
			if _arrived_at(men, c, dest):
				arrived += 1
		if arrived >= 13:
			break
	print("    дошли %d из 15" % arrived)
	verdict("C3 после конницы армия дошла до точки (%d из 15 ≥ 13)" % arrived, arrived >= 13)

## Дошёл ли отряд: центр у СВОЕЙ точки — середины постов, а не у точки клика.
## С ТЗ 23.10.2026 у каждого отряда [A] своя точка (am_own_dest): группа в
## 15 отрядов приходит своей шириной (~70 м), а «22 м от точки клика»
## засчитывало только тех, кого прежний баг стягивал в центр
func _arrived_at(men: Array, c: Vector3, dest: Vector3) -> bool:
	var pxs: Array = []
	var pzs: Array = []
	for u in men:
		pxs.append((u as Unit).post_pos.x)
		pzs.append((u as Unit).post_pos.z)
	pxs.sort(); pzs.sort()
	var pc := Vector3(float(pxs[pxs.size() / 2]), 0.0, float(pzs[pzs.size() / 2]))
	if Vector2(pc.x - dest.x, pc.z - dest.z).length() > 60.0:
		return false
	return Vector2(c.x - pc.x, c.z - pc.z).length() < 8.0
