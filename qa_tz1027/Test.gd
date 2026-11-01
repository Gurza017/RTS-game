extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_TZ1027 — разбор партии 27.10.2026 (performance_log_2026-10-27_1303.json):
## «бег на месте», одинокие куски отряда, ответ под огнём. Headless.
## ═══════════════════════════════════════════════════════════════════════════
## A — засыпающий на ходу встаёт (Unit.set_dormant, ручка dormant_halt)
## B — сон стоящего отряда не усыпляет только что отправленного
##     (_squad_sleep_decide_rows, ручка sleep_live_state)
## C — разъехавшиеся посты собираются (_posts_scattered, reform_post_scatter;
##     дальше зоны — _cohesion_guard, cohesion_post_zone)
## D — под обстрелом и под ударом стоящий отряд отвечает
## Ручки: diag=1, block=X.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const E := Constants.FACTION_ENEMY
const GF := Constants.FACTION_GOBLIN

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _diag := false
var _only := ""
var _live_troll := true
var _c_squads := 1
var _c_kind := "big_goblin"
var _e_research: Array = []
var _last_pos: Dictionary = {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "diag=1":
			_diag = true
		elif a.begins_with("csq="):
			_c_squads = int(a.substr(4))
		elif a.begins_with("res="):
			_e_research = Array(a.substr(4).split(","))
		elif a.begins_with("ckind="):
			_c_kind = a.substr(6)
		elif a == "live=0":
			_live_troll = false
		elif a.begins_with("block="):
			_only = a.substr(6)
	call_deferred("_run")
	get_tree().create_timer(900.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 900 с")
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
	print("\n═════ ИТОГ qa_tz1027: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _want(b: String) -> bool:
	return _only == "" or _only.find(b) >= 0

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Отряд блоком cols × rows, лицом по FORWARD (−Z), разметка закреплена
func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6, sp: float = 0.6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(
			at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0,
			at.z + float(i / cols) * sp))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	for u in men:
		(u as Unit).command_move((u as Unit).global_position, false, Vector3.FORWARD)
	GameManager.squad_close_ranks(sid, true)
	return [sid, men]

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _kill_all(men: Array) -> void:
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

## Вычистить всех чужих и диких в радиусе (ловушка «стенд на случайной карте»)
func _clear_area(c: Vector3, r: float) -> void:
	for u in GameManager._live_units.duplicate():
		if not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu == null or uu.is_dead():
			continue
		if uu.global_position.distance_to(c) < r:
			uu.take_damage(1e12)

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 30.0), Vector3(0.0, 0.0, -30.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
				if GameManager.is_water(p.x + d.x, p.z + d.z):
					h += 100.0
				if not GameManager.is_passable(p.x + d.x, p.z + d.z):
					h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	main = get_tree().current_scene
	if main == null or not main.has_method("world_add"):
		var sc: PackedScene = load("res://scenes/Main.tscn")
		main = sc.instantiate()
		get_tree().root.add_child(main)
	await frames(30)
	_Opt.squad_probes = false
	var base: Vector3 = _flat_spot(Vector3(0.0, 0.0, 40.0))
	_clear_area(base, 90.0)
	await pframes(10)
	if _want("A"):
		await _a_dormant(base)
	if _want("B"):
		await _b_sleep_race(base)
	if _want("C"):
		await _c_posts(base)
	if _want("D"):
		await _d_fire(base)
	_finish()

## Строки ядра «бегут на месте» за ~2 с (тот же замер, что у зонда)
func _stuck_rows(sec: float) -> Dictionary:
	var out: Dictionary = {}
	var t_end: float = Unit.game_sec + sec
	while Unit.game_sec < t_end:
		await pframes(15)
		var rows: PackedInt32Array = GameManager.army.probe_stuck_rows(Unit.game_ms(), 0.15, 500, 2, Unit.State.MOVING)
		for r in rows:
			out[int(r)] = true
	return out

# ═════════════════════════════════════════════════════════════════════════════
# A. ЗАСЫПАЕТ НА ХОДУ — ВСТАЁТ
# ═════════════════════════════════════════════════════════════════════════════
func _a_dormant(base: Vector3) -> void:
	print("\n═════ A. СПЯЧКА НА ХОДУ ═════")
	var sq: Array = _squad("goblin_spearman", GF, base + Vector3(-20.0, 0.0, 0.0), 20, 5, 0.9)
	var men: Array = sq[1]
	await pframes(30)
	# Приказ ИИ (не игрока) на 15 м — и спячка через полсекунды, как у вожака
	for u in men:
		(u as Unit).command_move((u as Unit).global_position + Vector3(0.0, 0.0, -15.0))
	await pframes(30)
	for u in men:
		(u as Unit).set_dormant(true)
	await pframes(60)
	var moving := 0
	for u in _alive(men):
		if (u as Unit).state == Unit.State.MOVING:
			moving += 1
	verdict("A1 уснувший на ходу не остаётся в MOVING", moving == 0, "в MOVING %d из %d" % [moving, men.size()])
	var stuck: Dictionary = await _stuck_rows(2.5)
	var mine := 0
	for u in _alive(men):
		if stuck.has((u as Unit)._soa):
			mine += 1
	verdict("A2 у спящих нет ленты ходьбы на месте (зонд stuck_running)", mine == 0, "бегут на месте %d" % mine)
	for u in men:
		(u as Unit).set_dormant(false)
	_kill_all(men)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# B. СОН СТОЯЩЕГО ОТРЯДА И СВЕЖИЙ ПРИКАЗ ИИ
# ═════════════════════════════════════════════════════════════════════════════
func _asleep_n(men: Array) -> int:
	var n := 0
	for u in _alive(men):
		if (u as Unit)._phys_asleep:
			n += 1
	return n

func _b_sleep_race(base: Vector3) -> void:
	print("\n═════ B. СОН И СВЕЖИЙ ПРИКАЗ ═════")
	var squads: Array = []
	for k in range(12):
		var at: Vector3 = base + Vector3(-33.0 + float(k % 6) * 12.0, 0.0, -15.0 + float(k / 6) * 22.0)
		# Сторона игрока: красных подбирает их ИИ, и они не стоят в покое.
		# Приказ ниже — не игрока (как у сплочённости и смыкания)
		var sq_b: Array = _squad("spearman", F, at, 20, 5, 0.6)
		var sl_b: Array = []
		for u in sq_b[1]:
			sl_b.append((u as Unit).global_position)
		GameManager.squad_set_formation(int(sq_b[0]), sl_b, Vector3.FORWARD, false)
		squads.append(sq_b)
	var all: Array = []
	for s in squads:
		all += (s[1] as Array)
	# Ждём, пока стоящие уснут по физике
	var slept := 0
	for _i in range(40):
		await pframes(15)
		slept = _asleep_n(all)
		if slept > all.size() / 2:
			break
	print("  уснуло по физике %d из %d" % [slept, all.size()])
	var frozen_worst := 0
	for rnd in range(4):
		# Приказ ИИ каждому отряду по очереди, со сдвигом в кадр — так он
		# ложится в разные фазы шардов и пересчёта коридора
		var dz: float = -6.0 if rnd % 2 == 0 else 6.0
		for s in squads:
			for u in _alive(s[1]):
				(u as Unit).command_move((u as Unit).post_pos + Vector3(0.0, 0.0, dz))
			await get_tree().physics_frame
		await pframes(60 * 6)
		var frozen := 0
		for u in _alive(all):
			var uu: Unit = u
			if uu.state == Unit.State.MOVING and not uu.tick_on:
				frozen += 1
		frozen_worst = maxi(frozen_worst, frozen)
		if _diag:
			print("  круг %d: уснули на ходу %d" % [rnd, frozen])
		# Снова дать уснуть
		for _j in range(20):
			await pframes(15)
			if _asleep_n(all) > all.size() / 2:
				break
	verdict("B1 приказ ИИ не засыпает на ходу (MOVING без тика через 6 с)", frozen_worst == 0,
		"худший круг: %d из %d" % [frozen_worst, all.size()])
	_kill_all(all)
	await pframes(10)

# ═════════════════════════════════════════════════════════════════════════════
# C. РАЗЪЕХАВШИЕСЯ ПОСТЫ
# ═════════════════════════════════════════════════════════════════════════════
func _c_case(base: Vector3, off: float) -> float:
	var sq: Array = _squad("spearman", F, base, 30, 6, 0.6)
	var sid: int = sq[0]
	var men: Array = sq[1]
	# Разметка отряда, как после приказа игрока (у отряда без неё смыкания нет)
	var slots: Array = []
	for u in men:
		slots.append((u as Unit).global_position)
	GameManager.squad_set_formation(sid, slots, Vector3.FORWARD, false)
	await pframes(120)
	# Восемь бойцов «встали, где стоят» в стороне: пост — там же
	# (Unit._hold_where_i_stand после исчерпанного замка цели)
	for i in range(8):
		var u: Unit = men[i]
		var p: Vector3 = u.global_position + Vector3(off, 0.0, 0.0)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u._hold_where_i_stand()
		u._settled = true
	var res: Dictionary = {}
	var t_end: float = Unit.game_sec + 40.0
	while Unit.game_sec < t_end:
		await pframes(30)
		res = GameManager.probes.split_of(sid) if GameManager.probes != null else {}
		if _diag and int(Unit.game_sec * 2.0) % 6 == 0:
			var sqd: Dictionary = GameManager.squads.get(sid, {})
			var u0: Unit = men[0]
			var u9: Unit = men[9]
			var sl: Array = sqd.get("slots", [])
			var mv := 0
			var dr := 0
			for mm in _alive(men):
				if (mm as Unit).state == Unit.State.MOVING: mv += 1
				if (mm as Unit).global_position.distance_to((mm as Unit).post_pos) > 0.7: dr += 1
			print("    u0 pos=(%.1f,%.1f) mt=(%.1f,%.1f) post=(%.1f,%.1f) goal=(%.1f,%.1f) route=%d" % [u0.global_position.x, u0.global_position.z, u0.move_target.x, u0.move_target.z, u0.post_pos.x, u0.post_pos.z, u0.march_goal().x, u0.march_goal().z, u0._route.size()])
			print("    moving=%d drift=%d intact=%s inq=%s keys=%d cur=%d" % [mv, dr, GameManager._formation_intact(_alive(men)), GameManager._reform_queue.size(), GameManager._reform_keys.size(), GameManager._reform_cursor])
			print("    slots=%d reshuffled=%s reform_at=%s calm=%s next=%s now=%d settles=%d" % [sl.size(), sqd.get("reshuffled", -1), sqd.get("reform_at", -1), sqd.get("calm_ms", -1), sqd.get("reform_next_ms", -1), Unit.game_ms(), GameManager.formation_settles])
			print("    t=%.1f scat=%s settled=%s fails=%s combat=%s queue=%s | u0 st=%d post_d=%.2f tick=%s sleep=%s | u9 st=%d post_d=%.2f sleep=%s" % [
				Unit.game_sec, GameManager._posts_scattered(sid, _alive(men)), sqd.get("reform_settled", false),
				sqd.get("reform_fails", 0), GameManager.squad_in_combat(sid), GameManager._reform_queue.has(sid),
				u0.state, u0.global_position.distance_to(u0.post_pos), u0.tick_on, u0._phys_asleep,
				u9.state, u9.global_position.distance_to(u9.post_pos), u9._phys_asleep])
	var al: Array = _alive(men)
	var xs: Array = []
	var zs: Array = []
	for u in al:
		xs.append((u as Unit).global_position.x)
		zs.append((u as Unit).global_position.z)
	xs.sort()
	zs.sort()
	var mx: float = xs[xs.size() / 2]
	var mz: float = zs[zs.size() / 2]
	var worst := 0.0
	for u in al:
		worst = maxf(worst, Vector2((u as Unit).global_position.x - mx, (u as Unit).global_position.z - mz).length())
	print("  отрыв %.0f м: через 40 с дальний от медианы %.1f м, разрыв по зонду: %s" % [off, worst, str(not res.is_empty())])
	_kill_all(men)
	await pframes(10)
	return worst

func _c_posts(base: Vector3) -> void:
	print("\n═════ C. РАЗЪЕХАВШИЕСЯ ПОСТЫ ═════")
	var near: float = await _c_case(base, 12.0)
	verdict("C1 кучка в 12 м (ближе зоны сплочённости) вернулась к отряду", near < 7.0, "дальний %.1f м" % near)
	var far: float = await _c_case(base, 22.0)
	# Порог — свойство зонда разрыва (SquadProbes.SPLIT_GAP): кучки нет. Хвост
	# обхода у кромки строя до 7-8 м за 40 с — это ещё идущие, а не стоящие
	verdict("C2 кучка в 22 м (дальше зоны) вернулась к отряду (разрыва нет)", far < 9.0, "дальний %.1f м" % far)

# ═════════════════════════════════════════════════════════════════════════════
# D. ПОД ОГНЁМ И ПОД УДАРОМ
# ═════════════════════════════════════════════════════════════════════════════
func _d_fire(base: Vector3) -> void:
	print("\n═════ D. ОТВЕТ ПОД ОГНЁМ ═════")
	# D1: стоящих копейщиков расстреливают лучники с 18 м
	var mine: Array = _squad("spearman", F, base + Vector3(0.0, 0.0, 10.0), 30, 6, 0.6)
	var arch: Array = _squad("archer", E, base + Vector3(0.0, 0.0, -10.0), 12, 6, 0.7)
	await pframes(90)
	for a in arch[1]:
		(a as Unit).command_attack((mine[1] as Array)[0], false)
	var answered := 0
	var t_end: float = Unit.game_sec + 12.0
	while Unit.game_sec < t_end:
		await pframes(15)
		var n := 0
		for u in _alive(mine[1]):
			var uu: Unit = u
			if uu.attack_target != null or uu.state == Unit.State.ATTACKING:
				n += 1
		answered = maxi(answered, n)
	var hp_lost := 0
	for u in mine[1]:
		if not is_instance_valid(u) or (u as Unit).is_dead() or (u as Unit).current_health < (u as Unit).max_health:
			hp_lost += 1
	print("  задетых стрелами %d, ответили (взяли цель) до %d из 30, лучников живых %d" % [hp_lost, answered, _alive(arch[1]).size()])
	verdict("D1 обстреливаемый отряд отвечает (≥ 2/3 взяли цель)", answered >= 20 or _alive(arch[1]).is_empty(),
		"ответили %d" % answered)
	_kill_all(mine[1])
	_kill_all(arch[1])
	await pframes(10)
	# D2: стоящих лучников бьют мечники вплотную
	var bow: Array = _squad("archer", F, base + Vector3(0.0, 0.0, 6.0), 24, 6, 0.7)
	var sw: Array = _squad("warrior", E, base + Vector3(0.0, 0.0, -8.0), 12, 6, 0.6)
	await pframes(90)
	for w in sw[1]:
		(w as Unit).command_attack((bow[1] as Array)[0], true)
	var ans2 := 0
	t_end = Unit.game_sec + 10.0
	while Unit.game_sec < t_end:
		await pframes(15)
		var n2 := 0
		for u in _alive(bow[1]):
			if (u as Unit).attack_target != null:
				n2 += 1
		ans2 = maxi(ans2, n2)
	verdict("D2 лучников бьют вплотную — отвечают (≥ половины взяли цель)", ans2 * 2 >= _alive(bow[1]).size() and ans2 > 0,
		"ответили %d из %d" % [ans2, _alive(bow[1]).size()])
	_kill_all(bow[1])
	_kill_all(sw[1])
	await pframes(10)
