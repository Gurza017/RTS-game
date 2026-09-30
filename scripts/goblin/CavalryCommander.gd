extends Node

## ═══════════════════════════════════════════════════════════════════════════
## КОМАНДИР КОННИЦЫ ОРДЫ (ТЗ 29.09.2026, третье письмо, блок 6)
## ═══════════════════════════════════════════════════════════════════════════
## ОДИН МОЗГ НА ОТРЯД, А НЕ НА ВСАДНИКА. Прежде каждый свиновсадник сам
## охотился: скан 30 м раз в RIDER_HUNT_TICK, никогда не засыпал по физике
## (may_sleep_physics = false) и тикал каждый кадр, даже стоя (замер
## qa_cav_bench «как было»: 9.5 мкс/тик у каждого из 60, 1.3 скана на всадника в
## секунду, отряд в 20 всадников простоял весь бой). Теперь решает командир —
## раз в TICK_SEC по отряду, ОДИН скан на отряд; всадники — исполнители
## (обычный тик бойца со сном и шардами).
##
## СОСТОЯНИЯ ОТРЯДА:
##   IDLE      — чужих в SEEK_R от центра нет: чужой приказ (марш набега,
##               волна) исполняется как есть, командир не вмешивается.
##   RUNUP     — цель выбрана, до неё меньше RUNUP_MIN: разгона не набрать —
##               отъезд на точку разгона (фланг цели, RUNUP_DIST).
##   CHARGE    — таран: всем приказ атаки с разгоном (штатный разгон ядра:
##               charge_range, charge_speed_mult 1.8, charge_min_runup).
##   MELEE     — контакт: рубка, пока не пора отходить (MELEE_MAX_SEC,
##               потери LOSS_FRAC от штата на заходе, копья в лоб, увязли).
##   WITHDRAW  — отход на ВЫХОДНУЮ точку в стороне от цели бегом; приказы
##               атаки от других (ответ на удар, ИИ набега) игнорируются.
##   REFORM    — короткая перегруппировка, затем новый выбор цели и заход
##               с другого фланга (сторона чередуется).
## ПРИОРИТЕТ ЦЕЛЕЙ — вес конницы у бойца (cav_target_weight: лучник 2.2 >
## мечник 1.6 > копейщик 1.0, в «Защите» 0.4), тот же скан ядра BestEnemyPrio.
## РАБОЧИЕ НА ПУТИ в TRAMPLE_R от всадника гибнут сразу (затоптаны).

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")

const TICK_SEC := 0.25
const SEEK_R := 34.0
const RUNUP_MIN := 11.0
const RUNUP_DIST := 17.0
const MELEE_MAX_SEC := 4.0
const LOSS_FRAC := 0.2
const STUCK_FRAC := 0.4
const WITHDRAW_SEC := 5.0
const WITHDRAW_DIST := 18.0
const REFORM_SEC := 1.2
const TRAMPLE_R := 1.5
## Глубина первой линии тарана от головного всадника, м, и срок, на который
## задним запрещён разгон в этой волне
const FRONT_DEPTH := 1.2
const REAR_NO_CHARGE_SEC := 30.0      # до конца волны: снимает отход или новый таран
const TRAMPLE_ZONE := 20.0        # рабочие дальше от центра отряда не проверяются

const ST_IDLE := 0
const ST_RUNUP := 1
const ST_CHARGE := 2
const ST_MELEE := 3
const ST_WITHDRAW := 4
const ST_REFORM := 5
const ST_NAMES := ["idle", "runup", "charge", "melee", "withdraw", "reform"]

## sid → {st, since, target, men0, side, point}
var _sq: Dictionary = {}
var _workers: Array = []
var _t: float = 0.0
var _tick_n: int = 0

## ── СЧЁТЧИКИ ДЛЯ СТЕНДОВ И ОТЧЁТА ─────────────────────────────────────────
var scans: int = 0
var charges: int = 0
var withdrawals: int = 0
var trampled: int = 0
var resumes: int = 0
var front_riders: int = 0
var ticks: int = 0
var usec_total: int = 0
var withdraw_why: Dictionary = {}

func state_of(sid: int) -> String:
	var raw: Variant = _sq.get(sid)
	return ST_NAMES[int((raw as Dictionary)["st"])] if raw != null else "idle"

func _process(delta: float) -> void:
	if not _Opt.cav_commander:
		return
	_t += delta
	if _t < TICK_SEC:
		return
	var dt: float = _t
	_t = 0.0
	_tick_n += 1
	var t0: int = Time.get_ticks_usec()
	var now: float = float(Time.get_ticks_msec()) * 0.001
	# Рабочие не-орды — один обход группы на такт (их десятки, а не тысячи)
	_workers.clear()
	for w in get_tree().get_nodes_in_group("workers"):
		if w != null and is_instance_valid(w) and not (w as Unit).is_dead() \
				and int((w as Unit).faction) != Constants.FACTION_GOBLIN and not (w as Unit).garrisoned:
			_workers.append(w)
	var alive: Dictionary = {}
	# Отряды на особых ролях вожака (охрана рудников, гарнизон, резерв,
	# разведка, месть) командиру не подчиняются: конная охрана рудника с
	# SEEK_R 34 м уходила от рудника на линию красного ИИ (qa_tz0928 B1)
	var gai = GameManager.main.get("goblin_ai") if GameManager.main != null else null
	var gai_ok: bool = gai != null and is_instance_valid(gai) and gai.has_method("is_special_squad")
	for sid in GameManager.squads.keys():
		var sq: Dictionary = GameManager.squads[sid]
		if String(sq.get("type", "")) != "goblin_rider":
			continue
		if gai_ok and bool(gai.is_special_squad(int(sid))):
			continue
		var men: Array = sq["members"]
		if men.is_empty():
			continue
		alive[sid] = true
		_tick_squad(int(sid), men, now, dt)
	for k in _sq.keys():
		if not alive.has(k):
			_sq.erase(k)
	ticks += 1
	usec_total += Time.get_ticks_usec() - t0

func _rec(sid: int) -> Dictionary:
	var raw: Variant = _sq.get(sid)
	if raw == null:
		raw = {"st": ST_IDLE, "since": 0.0, "target": null, "men0": 0, "side": 1.0, "point": Vector3.ZERO,
			"resume": Vector3.INF}
		_sq[sid] = raw
	return raw

func _to_state(r: Dictionary, st: int, now: float) -> void:
	r["st"] = st
	r["since"] = now

## Живой всадник ближе всех к центру: от него идут скан и точки
func _leader(men: Array, c: Vector2) -> Unit:
	var best: Unit = null
	var bd := INF
	for m in men:
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u.is_dead() or u.garrisoned or u.is_panicked():
			continue
		var d: float = Vector2(u.global_position.x - c.x, u.global_position.z - c.y).length_squared()
		if d < bd:
			bd = d
			best = u
	return best

func _valid_target(t) -> bool:
	return t != null and is_instance_valid(t) and t is Unit and not (t as Unit).is_dead() \
		and not (t as Unit).garrisoned

func _tick_squad(sid: int, men: Array, now: float, _dt: float) -> void:
	var c: Vector2 = GameManager.squad_centre_xz(sid)
	if c.x == INF:
		return
	var r: Dictionary = _rec(sid)
	var lead: Unit = _leader(men, c)
	if lead == null:
		return
	var cen := Vector3(c.x, 0.0, c.y)
	var st: int = int(r["st"])
	# Затоптать рабочих на пути (каждый TRAMPLE_EVERY-й такт, по всаднику)
	if not _workers.is_empty():
		_trample(men, cen)
	match st:
		ST_IDLE, ST_REFORM:
			if st == ST_REFORM and now - float(r["since"]) < REFORM_SEC:
				return
			var foe: Node3D = lead._find_nearest_enemy_in_range(SEEK_R, "cav_seek")
			scans += 1
			if foe == null or not _valid_target(foe):
				if st == ST_REFORM:
					_to_state(r, ST_IDLE, now)
				# ── ЧУЖОЙ МАРШ ВОЗВРАЩАЕТСЯ ────────────────────────────────────
				# Командир перехватил отряд с марша (набег, волна) — цели кончились,
				# марш продолжается туда же, а не «встали, где кончилась цель»
				var rs: Vector3 = r["resume"]
				if rs.x != INF:
					r["resume"] = Vector3.INF
					resumes += 1
					_move_squad(men, cen, rs, now, false)
				return
			# Марш, с которого снимаем отряд, — запомнить (только из покоя, не
			# из перегруппировки: там точка уже наша)
			if st == ST_IDLE and lead.state == Unit.State.MOVING and (r["resume"] as Vector3).x == INF:
				r["resume"] = lead._route_goal if lead._route.size() > 0 else lead.move_target
			r["target"] = foe
			var d: float = Vector2(foe.global_position.x - c.x, foe.global_position.z - c.y).length()
			if d < RUNUP_MIN:
				_go_runup(sid, r, men, cen, foe as Unit, now)
			else:
				_go_charge(sid, r, men, foe as Unit, now)
		ST_RUNUP:
			var tg = r["target"]
			if not _valid_target(tg):
				_to_state(r, ST_REFORM, now)
				return
			var p: Vector3 = r["point"]
			if Vector2(p.x - c.x, p.z - c.y).length() < 4.0 or now - float(r["since"]) > WITHDRAW_SEC:
				_go_charge(sid, r, men, tg as Unit, now)
		ST_CHARGE:
			var tg2 = r["target"]
			if not _valid_target(tg2):
				_to_state(r, ST_REFORM, now)
				return
			if GameManager.squad_engaged(sid) > 0 or now - float(r["since"]) > 8.0:
				_to_state(r, ST_MELEE, now)
		ST_MELEE:
			var why: String = _melee_exit(sid, r, men, now)
			if why != "":
				withdraw_why[why] = int(withdraw_why.get(why, 0)) + 1
				_go_withdraw(sid, r, men, cen, now)
		ST_WITHDRAW:
			var p2: Vector3 = r["point"]
			if Vector2(p2.x - c.x, p2.z - c.y).length() < 5.0 or now - float(r["since"]) > WITHDRAW_SEC:
				for m in men:
					if m != null and is_instance_valid(m):
						(m as Unit).set("_cav_withdraw_until_ms", 0)
				r["side"] = -float(r["side"])        # следующий заход — с другого фланга
				_to_state(r, ST_REFORM, now)

## Пора ли выходить из рубки: причина или пустая строка
func _melee_exit(sid: int, r: Dictionary, men: Array, now: float) -> String:
	var alive := 0
	var stuck := 0
	var spear_front := 0
	for m in men:
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u.is_dead():
			continue
		alive += 1
		if u.state == Unit.State.ATTACKING and not u.moved_recently():
			stuck += 1
		var t = u.attack_target
		if t != null and is_instance_valid(t) and t is Unit and (t as Unit).repels_charge():
			var dir: Vector3 = (t as Node3D).global_position - u.global_position
			dir.y = 0.0
			if dir.length() > 0.01 and (t as Unit)._faces_charge(dir.normalized()):
				spear_front += 1
	if alive == 0:
		return ""
	# «Не стоять и не ковырять копейщиков в лоб»: хватает одного всадника,
	# упёршегося в копья лицом, — отряд выходит и заходит с фланга
	if spear_front >= 1 and now - float(r["since"]) > 1.0:
		return "копья в лоб"
	if int(r["men0"]) > 0 and float(int(r["men0"]) - alive) >= float(int(r["men0"])) * LOSS_FRAC:
		return "потери"
	if float(stuck) >= float(alive) * STUCK_FRAC and now - float(r["since"]) > 1.5:
		return "увязли"
	if now - float(r["since"]) > MELEE_MAX_SEC:
		return "время"
	return ""

func _go_charge(sid: int, r: Dictionary, men: Array, foe: Unit, now: float) -> void:
	charges += 1
	r["men0"] = _alive_n(men)
	_to_state(r, ST_CHARGE, now)
	# ── ПЕРВАЯ ЛИНИЯ: кто ближе всех к цели по ходу (в FRONT_DEPTH от
	# головного). Только она бьёт с разгона; остальные в эту волну разгона не
	# взводят — идут следом в рубку и напор (никаких «двойных ударов»)
	var fp: Vector3 = foe.global_position
	var lead_proj := -INF
	var projs: Dictionary = {}
	var c2: Vector2 = GameManager.squad_centre_xz(sid)
	var dirn := Vector3(fp.x - c2.x, 0.0, fp.z - c2.y)
	if dirn.length() > 0.01:
		dirn = dirn.normalized()
	for m0 in men:
		if m0 == null or not is_instance_valid(m0) or (m0 as Unit).is_dead():
			continue
		var pr: float = (m0 as Unit).global_position.dot(dirn)
		projs[m0] = pr
		lead_proj = maxf(lead_proj, pr)
	var no_charge: int = Time.get_ticks_msec() + int(REAR_NO_CHARGE_SEC * 1000.0)
	for m in men:
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u.is_dead() or u.garrisoned:
			continue
		var front: bool = float(projs.get(m, -INF)) >= lead_proj - FRONT_DEPTH
		u.no_charge_until_ms = 0 if front else no_charge
		if not front:
			# Разгон, уже взведённый авто-агро до такта командира, — снять
			u.is_charging = false
			u._charge_ready = false
		if front:
			front_riders += 1
		u.set("_cav_withdraw_until_ms", 0)
		# forced: отряд бьёт отряд (squad_pick_member разберёт по моделям),
		# charge: штатный разгон ядра
		u.command_attack(foe, true, true)

func _go_runup(sid: int, r: Dictionary, men: Array, cen: Vector3, foe: Unit, now: float) -> void:
	var away: Vector3 = cen - foe.global_position
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	away = away.normalized()
	var side := Vector3(-away.z, 0.0, away.x) * float(r["side"])
	var p: Vector3 = foe.global_position + (away + side * 0.8).normalized() * RUNUP_DIST
	r["point"] = GameManager.land_target(p)
	_to_state(r, ST_RUNUP, now)
	_move_squad(men, cen, r["point"], now, false)

func _go_withdraw(sid: int, r: Dictionary, men: Array, cen: Vector3, now: float) -> void:
	withdrawals += 1
	var tg = r["target"]
	var from: Vector3 = (tg as Node3D).global_position if _valid_target(tg) else cen
	var away: Vector3 = cen - from
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	away = away.normalized()
	# Выход вбок и назад: следующий заход — во фланг
	var side := Vector3(-away.z, 0.0, away.x) * float(r["side"])
	var p: Vector3 = cen + (away + side * 1.2).normalized() * WITHDRAW_DIST
	var lim: Vector2 = GameManager.clamp_to_map(p.x, p.z)
	r["point"] = GameManager.land_target(Vector3(lim.x, 0.0, lim.y))
	_to_state(r, ST_WITHDRAW, now)
	_move_squad(men, cen, r["point"], now, true)

## Весь отряд — в точку, СОХРАНЯЯ взаимное расположение (кулак, а не нитка)
func _move_squad(men: Array, cen: Vector3, p: Vector3, now: float, withdraw: bool) -> void:
	var until_ms: int = int((now + WITHDRAW_SEC) * 1000.0) if withdraw else 0
	for m in men:
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u.is_dead() or u.garrisoned:
			continue
		var off: Vector3 = u.global_position - cen
		off.y = 0.0
		u.set("_cav_withdraw_until_ms", 0)
		u.no_charge_until_ms = 0          # волна кончилась — разгон снова свой
		u.set_attack_target(null)
		u.command_move(GameManager.land_target(p + off.limit_length(6.0)), false, Vector3.ZERO, false, false, true)
		u.set("_cav_withdraw_until_ms", until_ms)

## Рабочий в TRAMPLE_R от всадника — затоптан (ТЗ: «рабочих на пути в 1 метре
## истребляют мгновенно»). Скан ядра малого радиуса, без аллокаций
func _trample(men: Array, cen: Vector3) -> void:
	# Рабочие в зоне отряда (центр ± TRAMPLE_ZONE) — только их и проверяем
	var near: Array = []
	for w in _workers:
		if not is_instance_valid(w):
			continue
		var wp: Vector3 = (w as Node3D).global_position
		if absf(wp.x - cen.x) < TRAMPLE_ZONE and absf(wp.z - cen.z) < TRAMPLE_ZONE:
			near.append(w)
	if near.is_empty():
		return
	for m in men:
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u.is_dead() or u.garrisoned or u.state == Unit.State.IDLE:
			continue
		var up: Vector3 = u.global_position
		for w2 in near:
			if not is_instance_valid(w2) or (w2 as Unit).is_dead():
				continue
			var wp2: Vector3 = (w2 as Node3D).global_position
			if Vector2(wp2.x - up.x, wp2.z - up.z).length_squared() <= TRAMPLE_R * TRAMPLE_R:
				trampled += 1
				(w2 as Unit).take_damage((w2 as Unit).max_health * 100.0, u)

func _alive_n(men: Array) -> int:
	var n := 0
	for m in men:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n
