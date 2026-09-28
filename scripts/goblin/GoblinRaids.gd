extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## НАБЕГИ ОРДЫ ПО РАСПИСАНИЮ (ТЗ 24.09.2026, второе письмо)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: «на десятой минуте у меня ничего нет — и у врага не должно быть,
## он не знает, что я есть. Как только тянусь за золотом, приходит слишком
## мощно». Давление теперь идёт ПО ЧАСАМ ПАРТИИ, соизмеримыми порциями:
##   15-я мин — 2 отряда гоблинов + разведка двумя конными дозорами с флангов;
##   20-я мин — 2 отряда гоблинов;
##   25-я мин — 2 отряда гоблинов + 2 туши;
##   35-я мин — 2 отряда гоблинов + 2 туши + 3 отряда свиновсадников;
##   дальше каждые REPEAT_SEC — последний набег и +1 отряд гоблинов (потолок).
## Набег заводится СВЕЖИМИ отрядами у деревни (армия орды на месте), строится
## СТРОЕМ (пехота фронтом по центру, туши и конница по флангам), подходит на
## STAGE_DIST к цели, выравнивается и бьёт разом; при потере LOSS_RETREAT
## состава или через ATTACK_MAX_SEC отходит домой и отдаётся вожаку.
##
## Без узла и без тика: зовёт GoblinAI из своего такта мышления (tick).

const _GobCfgR := preload("res://scripts/goblin/goblin_config.gd")
const _UCfgR := preload("res://scripts/unit_stats_config.gd")
const _EconR := preload("res://scripts/economy_model.gd")

## Состав: unit → число ОТРЯДОВ; у туш — число ТУШ (одним отрядом)
const SCHEDULE := [
	{"t": 900.0,  "comp": {"goblin_spearman": 2}, "scouts": true},
	{"t": 1200.0, "comp": {"goblin_spearman": 2}},
	{"t": 1500.0, "comp": {"goblin_spearman": 2, "big_goblin": 2}},
	{"t": 2100.0, "comp": {"goblin_spearman": 2, "big_goblin": 2, "goblin_rider": 3}},
]
const REPEAT_SEC := 600.0
const REPEAT_MAX_SPEARMEN := 6
## Размер конного дозора разведки (бойцов)
const SCOUT_SIZE := 6
const STAGE_DIST := 30.0
const SLOT_W := 10.0
const ROW_BACK := 9.0
const ASSEMBLE_SEC := 6.0
const STAGE_MAX_SEC := 60.0
const STAGE_READY_FRAC := 0.75
const ARRIVE_R := 7.0
const ATTACK_MAX_SEC := 150.0
const LOSS_RETREAT := 0.5
const RETREAT_MAX_SEC := 90.0
const REORDER_SEC := 4.0
## ── ТАКТИКИ НАБЕГА (ТЗ 25.09.2026, п. 5) ──────────────────────────────────
## Вместо «все разом на ближайшего» набег идёт по одной из двух схем; выбор —
## по очереди набегов (чётный — А, нечётный — Б), детерминированно: два
## прогона одной партии обязаны играть одно и то же.
##   А «ЖИВОЙ ЩИТ + КОННИЦА»: туши первой линией по центру впитывают стрелы,
##     пехота за ними, конница выжидает CAV_DELAY_SEC и бьёт по флангам.
##     Завязла (в бою дольше CAV_STUCK_SEC и потеряла CAV_STUCK_LOSS) —
##     отходит на своё место в строю «на перезарядку» на CAV_RECHARGE_SEC,
##     пока подтягивается пехота, и бьёт снова.
##   Б «ФЛАНГОВЫЙ УДАР»: конница выходит первой с флангов и связывает армию
##     игрока, центр (пехота и туши) держит линию INF_DELAY_SEC и потом
##     проламывает середину.
## Без конницы схема Б вырождается в А (отвлекать некому).
const TACTIC_A := "A"
const TACTIC_B := "B"
const HEAVY_FRONT := 6.0          # туши в схеме А — на столько впереди пехоты
const CAV_DELAY_SEC := 5.0
const INF_DELAY_SEC := 7.0
const CAV_STUCK_SEC := 8.0
const CAV_STUCK_LOSS := 0.25
const CAV_RECHARGE_SEC := 6.0
## Радиус, в котором набег ищет противника (любой чужой, не только игрок)
const ENGAGE_R := 45.0
## Здание берётся целью, только если стоит рядом с набегом, а не «где-то
## у цели»: иначе отряды шли через полкарты к дальней постройке
const BUILDING_R := 60.0
## Насколько набег продвигается к цели за один переприказ, когда рядом никого
const ADVANCE_STEP := 25.0
## Стендам: сколько раз конница уходила на перезарядку и сколько набегов какой
## тактики запущено
var cav_recharges: int = 0
var tactic_count: Dictionary = {TACTIC_A: 0, TACTIC_B: 0}

var main = null
var village: Vector3 = Vector3.ZERO
## Сколько записей расписания уже отыграно (+ повторы)
var fired: int = 0
var next_repeat_at: float = INF
## Набеги в работе: {"sids": [...], "slots": {sid: Vector3}, "state", "since",
## "target", "peak", "scout": bool}
var raids: Array = []
## Все отряды под рукой набегов — вожак их не водит (GoblinAI._issue_orders)
var owned: Dictionary = {}
## Стендам
var raids_started: int = 0
## ── ВОЛНЫ НА ЗАХВАЧЕННЫЙ РУДНИК (ТЗ 24.09.2026, партия 90 мин) ──────────────
## Рудник, отбитый игроком (Mine.captures > 0), раз в MINE_WAVE_INTERVAL_SEC
## получает волну гоблинов размером economy_model.mine_wave_squads(часы):
## полотряда в начале партии, два отряда к 45-й минуте. Цель волн — не снести
## гарнизон, а дать ему работу (опыт) и держать поток ресурсов под угрозой.
## Волна — обычный набег: сбор строем, удар, отход при потерях
## (instance_id рудника → часы следующей волны)
var _mine_next: Dictionary = {}
var mine_waves_launched: int = 0
var last_mine_wave_men: int = 0
var raids_retreated: int = 0

func setup(p_main, p_village: Vector3) -> void:
	main = p_main
	village = p_village

func reset() -> void:
	fired = 0
	next_repeat_at = INF
	raids.clear()
	owned.clear()
	_mine_next.clear()

## Один такт: запустить набег по часам и вести идущие
func tick(clock: float, target: Vector3) -> void:
	if main == null:
		return
	_schedule(clock, target)
	_mine_waves(clock)
	for r in raids.duplicate():
		_step(r as Dictionary, clock)

# ─────────────────────────────────────────────────────────────────────────────
func _schedule(clock: float, target: Vector3) -> void:
	if target == Vector3.ZERO:
		return
	if fired < SCHEDULE.size():
		var e: Dictionary = SCHEDULE[fired]
		if clock >= float(e["t"]):
			fired += 1
			launch(e["comp"], clock, target, bool(e.get("scouts", false)))
			if fired == SCHEDULE.size():
				next_repeat_at = clock + REPEAT_SEC
		return
	if clock >= next_repeat_at:
		fired += 1
		var comp: Dictionary = (SCHEDULE[SCHEDULE.size() - 1]["comp"] as Dictionary).duplicate()
		var extra: int = fired - SCHEDULE.size()
		comp["goblin_spearman"] = mini(int(comp.get("goblin_spearman", 0)) + extra, REPEAT_MAX_SPEARMEN)
		launch(comp, clock, target, false)
		next_repeat_at = clock + REPEAT_SEC

## Отбитые игроком рудники: первая волна через интервал после захвата
func _mine_waves(clock: float) -> void:
	var seen: Dictionary = {}
	for b in main.get_tree().get_nodes_in_group(Constants.building_group(Constants.FACTION_PLAYER)):
		if b == null or not is_instance_valid(b) or not (b is Mine):
			continue
		var m: Mine = b
		if m.is_dead() or int(m.captures) <= 0:
			continue
		var id: int = m.get_instance_id()
		seen[id] = true
		var nxt: Variant = _mine_next.get(id)
		if nxt == null:
			_mine_next[id] = clock + _EconR.MINE_WAVE_INTERVAL_SEC
			continue
		if clock < float(nxt):
			continue
		_mine_next[id] = clock + _EconR.MINE_WAVE_INTERVAL_SEC
		var r: Dictionary = launch({"goblin_spearman": _EconR.mine_wave_squads(clock)}, clock,
			m.global_position, false)
		r["mine_wave"] = true
		mine_waves_launched += 1
		last_mine_wave_men = _alive(r["sids"])
	# Рудник потерян или снесён — его часы забываются: новый захват = новый отсчёт
	for id2 in _mine_next.keys():
		if not seen.has(id2):
			_mine_next.erase(id2)

## Завести набег: свежие отряды у деревни + разметка строя.
## Число отрядов может быть ДРОБНЫМ (волна рудника: 0.5 — полотряда): целые
## отряды выходят полными, остаток — последним отрядом неполного штата
func launch(comp: Dictionary, clock: float, target: Vector3, scouts: bool) -> Dictionary:
	var sids: Array = []
	var kinds: Dictionary = {}
	var k := 0
	for uid in comp.keys():
		var nf: float = float(comp[uid])
		var n: int = int(ceil(nf - 0.001))
		if n <= 0:
			continue
		var squads_n: int = 1 if String(uid) == "big_goblin" else n
		var men: int = n if String(uid) == "big_goblin" else _UCfgR.squad_size(String(uid))
		for _i in range(squads_n):
			var men_i: int = men
			if String(uid) != "big_goblin" and _i == squads_n - 1:
				var frac: float = nf - float(squads_n - 1)
				men_i = clampi(int(round(float(men) * frac)), 4, men)
			var base: Vector3 = village + Vector3(6.0 * float(k % 4) - 9.0, 0.0, 6.0 * float(k / 4))
			k += 1
			var sid: int = int(main.spawn_goblin_squad(String(uid), men_i, base))
			if sid > 0:
				sids.append(sid)
				kinds[sid] = String(uid)
				owned[sid] = true
	var has_cav := false
	for s0 in sids:
		if String(kinds[s0]) == "goblin_rider":
			has_cav = true
	var tactic: String = TACTIC_B if (has_cav and raids_started % 2 == 1) else TACTIC_A
	tactic_count[tactic] = int(tactic_count[tactic]) + 1
	var r := {"sids": sids, "kinds": kinds, "state": "assemble", "since": clock,
		"target": target, "peak": _alive(sids), "scout": false, "slots": {},
		"tactic": tactic, "cav": {}}
	_layout(r)
	raids.append(r)
	raids_started += 1
	if scouts:
		_launch_scouts(clock, target)
	return r

## Два конных дозора с флангов: дойти до края базы и вернуться
func _launch_scouts(clock: float, target: Vector3) -> void:
	var axis: Vector3 = target - village
	axis.y = 0.0
	axis = axis.normalized() if axis.length() > 1.0 else Vector3.FORWARD
	var side := Vector3(-axis.z, 0.0, axis.x)
	for sgn in [-1.0, 1.0]:
		var sid: int = int(main.spawn_goblin_squad("goblin_rider", SCOUT_SIZE, village + side * 8.0 * float(sgn)))
		if sid <= 0:
			continue
		owned[sid] = true
		var goal: Vector3 = target - axis * 25.0 + side * 35.0 * float(sgn)
		var r := {"sids": [sid], "kinds": {sid: "goblin_rider"}, "state": "scout",
			"since": clock, "target": goal, "peak": _alive([sid]), "scout": true,
			"slots": {sid: goal}}
		_move(sid, goal)
		raids.append(r)

## ── СТРОЙ НАБЕГА ─────────────────────────────────────────────────────────────
## Пехота — фронтом по центру линии в STAGE_DIST перед целью; конница — по
## флангам фронта. Туши — по тактике: в схеме А ПЕРЕД пехотой (живой щит,
## ТЗ 25.09.2026 п. 5), в схеме Б — за центром (второй ряд)
func _layout(r: Dictionary) -> void:
	var target: Vector3 = r["target"]
	var axis: Vector3 = village - target
	axis.y = 0.0
	axis = axis.normalized() if axis.length() > 1.0 else Vector3.BACK
	var side := Vector3(-axis.z, 0.0, axis.x)
	var front: Vector3 = target + axis * STAGE_DIST
	var inf: Array = []
	var heavy: Array = []
	var cav: Array = []
	for s in r["sids"]:
		match String((r["kinds"] as Dictionary).get(s, "")):
			"goblin_rider": cav.append(s)
			"big_goblin", "troll": heavy.append(s)
			_: inf.append(s)
	var slots: Dictionary = r["slots"]
	var w: float = float(inf.size() - 1) * SLOT_W
	for i in range(inf.size()):
		slots[inf[i]] = front + side * (float(i) * SLOT_W - w * 0.5)
	var heavy_off: float = -HEAVY_FRONT if String(r.get("tactic", TACTIC_B)) == TACTIC_A else ROW_BACK
	for j in range(heavy.size()):
		slots[heavy[j]] = front + axis * heavy_off + side * ((float(j) - float(heavy.size() - 1) * 0.5) * SLOT_W)
	for c in range(cav.size()):
		var sgn: float = -1.0 if c % 2 == 0 else 1.0
		var off: float = w * 0.5 + SLOT_W * (1.0 + float(c / 2))
		slots[cav[c]] = front + side * (off * sgn) + axis * 3.0

func _step(r: Dictionary, clock: float) -> void:
	var sids: Array = r["sids"]
	var alive: int = _alive(sids)
	if alive == 0:
		_release(r)
		return
	var st: String = r["state"]
	var t: float = clock - float(r["since"])
	match st:
		"scout":
			var g: Vector3 = r["target"]
			var c: Vector3 = _centre(sids[0])
			if c == Vector3.INF or Vector2(c.x - g.x, c.z - g.z).length() < 8.0 or t > 70.0:
				_go_home(r, clock)
		"assemble":
			if t >= ASSEMBLE_SEC:
				for s in sids:
					_move(int(s), (r["slots"] as Dictionary)[s])
				r["state"] = "stage"
				r["since"] = clock
		"stage":
			var ready := 0
			for s2 in sids:
				var c2: Vector3 = _centre(int(s2))
				var sp: Vector3 = (r["slots"] as Dictionary)[s2]
				if c2 != Vector3.INF and Vector2(c2.x - sp.x, c2.z - sp.z).length() <= ARRIVE_R:
					ready += 1
			var hit := false
			for s3 in sids:
				if GameManager.squad_hit_recently(int(s3)):
					hit = true
			if hit or t >= STAGE_MAX_SEC or float(ready) >= STAGE_READY_FRAC * float(sids.size()):
				r["state"] = "attack"
				r["since"] = clock
				r["order_t"] = -INF
		"attack":
			if float(alive) < float(r["peak"]) * (1.0 - LOSS_RETREAT) or t >= ATTACK_MAX_SEC:
				_go_home(r, clock)
				return
			_cav_recharge(r, clock)
			if clock - float(r.get("order_t", -INF)) >= REORDER_SEC:
				r["order_t"] = clock
				_attack_front(r, t)
		"retreat":
			var c5: Vector3 = _centroid_all(sids)
			if t >= RETREAT_MAX_SEC or (c5 != Vector3.INF
					and Vector2(c5.x - village.x, c5.z - village.z).length() < 20.0):
				_release(r)

func _go_home(r: Dictionary, clock: float) -> void:
	r["state"] = "retreat"
	r["since"] = clock
	raids_retreated += 1
	for s in r["sids"]:
		var sid: int = int(s)
		for m in _members(sid):
			(m as Unit).begin_retreat()
		_move(sid, village, true)

## Отдать уцелевших вожаку: дальше это обычные отряды орды
func _release(r: Dictionary) -> void:
	for s in r["sids"]:
		owned.erase(int(s))
		for m in _members(int(s)):
			if (m as Unit).retreating:
				(m as Unit).end_retreat(true)
	raids.erase(r)

# ── ПРИКАЗЫ ─────────────────────────────────────────────────────────────────
func _members(sid: int) -> Array:
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return []
	var out: Array = []
	for m in (raw as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _alive(sids: Array) -> int:
	var n := 0
	for s in sids:
		n += _members(int(s)).size()
	return n

func _centre(sid: int) -> Vector3:
	var ms: Array = _members(sid)
	if ms.is_empty():
		return Vector3.INF
	var acc := Vector3.ZERO
	for m in ms:
		acc += (m as Node3D).global_position
	return acc / float(ms.size())

func _centroid_all(sids: Array) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for s in sids:
		for m in _members(int(s)):
			acc += (m as Node3D).global_position
			n += 1
	return acc / float(n) if n > 0 else Vector3.INF

func _move(sid: int, goal: Vector3, keep_retreat: bool = false) -> void:
	var ms: Array = _members(sid)
	var n: int = ms.size()
	var slots: Array = []
	for k in range(n):
		var ho: Vector2 = _GobCfgR.horde_offset(k, n, sid)
		slots.append(Vector3(goal.x + ho.x, 0.0, goal.z + ho.y))
	var c: Vector3 = _centre(sid)
	var course: Vector3 = (goal - c) if c != Vector3.INF else Vector3.FORWARD
	course.y = 0.0
	GameManager.squad_set_formation(sid, slots,
		course.normalized() if course.length() > 0.1 else Vector3.FORWARD, false)
	for k2 in range(n):
		(ms[k2] as Unit).command_move(GameManager.land_target(slots[k2]), false,
			Vector3.ZERO, keep_retreat)

## ── УДАР ФРОНТОМ (ТЗ 25.09.2026, п. 1, 4, 5) ────────────────────────────────
## Прежде каждый отряд получал command_attack на ОДНУ модель — ближайшего
## бойца ИГРОКА, — и весь набег сходился в неё («молотилка»), а бойцы
## красного ИИ целью не считались вовсе: набег, забредший к его лагерю, стоял
## под его стрелами, не отвечая, и раз в REORDER_SEC дёргался новым приказом
## на далёкую постройку игрока. Теперь:
##   • враг — любой чужой (игрок И красный ИИ) в ENGAGE_R от набега;
##   • каждый отряд берёт чужой отряд ПРЯМО ПЕРЕД СОБОЙ (front_pairs), бойцы
##     разбирают его по моделям (squad_attack_squad) — «стенка на стенку»;
##   • чужой отряд, перекрывший брод или проход, — такая же пара: набег
##     вступает с ним в бой, а не обтекает его гуськом;
##   • бойцов рядом нет — ближайшая чужая постройка в BUILDING_R; нет и её —
##     набег идёт СТРОЕМ дальше к цели, а не рассыпается.
## Очередь по тактике: кто ещё «ждёт своей очереди» (_waits), стоит на месте
## в строю сбора
var front_engages: int = 0

func _attack_front(r: Dictionary, t: float) -> void:
	var active: Array = []
	for s in r["sids"]:
		var sid: int = int(s)
		if _members(sid).is_empty():
			continue
		if _waits(r, sid, t):
			continue
		active.append(sid)
	if active.is_empty():
		return
	var mid: Vector3 = _centroid_all(active)
	if mid == Vector3.INF:
		return
	var pairs: Dictionary = GameManager.front_pairs(active, mid, ENGAGE_R, Constants.FACTION_GOBLIN)
	var tgt: Vector3 = r["target"]
	var fwd: Vector3 = tgt - mid
	fwd.y = 0.0
	var adv := Vector3.ZERO
	if fwd.length() > 0.1:
		adv = fwd.normalized() * minf(fwd.length(), ADVANCE_STEP)
	var slots: Dictionary = r["slots"]
	for sid2 in active:
		var sid_i: int = int(sid2)
		if GameManager.squad_in_combat(sid_i):
			continue
		var fs: Variant = pairs.get(sid_i)
		if fs != null:
			front_engages += 1
			GameManager.squad_attack_squad(sid_i, int(fs), true)
			continue
		var b: Node3D = _building_near(_centre(sid_i))
		var ms0: Array = _members(sid_i)
		# Постройку, которую орде бить нельзя (крепость ИИ — may_attack_building),
		# приказ отклонил бы молча, и отряд встал бы столбом — идём дальше строем
		if b != null and not ms0.is_empty() and (ms0[0] as Unit).may_attack_building(b as Building):
			for m in ms0:
				(m as Unit).command_attack(b, true)
			continue
		# Никого рядом — строем к цели: место в линии переносится вперёд
		var c: Vector3 = _centre(sid_i)
		if c == Vector3.INF or Vector2(c.x - tgt.x, c.z - tgt.z).length() <= ARRIVE_R:
			continue
		var slot: Vector3 = slots.get(sid_i, tgt)
		slot += adv
		slots[sid_i] = slot
		_move(sid_i, slot)

## Ждёт ли отряд своей очереди по тактике (t — секунд с начала удара)
func _waits(r: Dictionary, sid: int, t: float) -> bool:
	var kind: String = String((r["kinds"] as Dictionary).get(sid, ""))
	var cav: bool = kind == "goblin_rider"
	# Конница на перезарядке — стоит на своём месте
	var cr: Dictionary = r["cav"]
	var rec: Variant = cr.get(sid)
	if rec != null and float((rec as Dictionary).get("until", -INF)) > t:
		return true
	# Кого уже бьют — тот не ждёт: стоять под ударом незачем
	if GameManager.squad_hit_recently(sid):
		return false
	if String(r.get("tactic", TACTIC_A)) == TACTIC_A:
		return cav and t < CAV_DELAY_SEC
	return (not cav) and t < INF_DELAY_SEC

## ── ПЕРЕЗАРЯДКА КОННИЦЫ (схема А) ──────────────────────────────────────────
## Конный отряд в бою дольше CAV_STUCK_SEC, потерявший CAV_STUCK_LOSS состава
## с начала сшибки, — «завяз»: отходит на своё место в строю сбора на
## CAV_RECHARGE_SEC и снова идёт во фланг
func _cav_recharge(r: Dictionary, clock: float) -> void:
	if String(r.get("tactic", TACTIC_A)) != TACTIC_A:
		return
	var t: float = clock - float(r["since"])
	var cr: Dictionary = r["cav"]
	for s in r["sids"]:
		var sid: int = int(s)
		if String((r["kinds"] as Dictionary).get(sid, "")) != "goblin_rider":
			continue
		var n: int = _members(sid).size()
		if n == 0:
			continue
		var rec: Dictionary = cr.get(sid, {})
		cr[sid] = rec
		if float(rec.get("until", -INF)) > t:
			continue
		if rec.has("until"):
			# Перезарядка кончилась — отход снимается, дальше очередь удара
			rec.erase("until")
			for m in _members(sid):
				if (m as Unit).retreating:
					(m as Unit).end_retreat(true)
		if GameManager.squad_in_combat(sid):
			if not rec.has("fight_t"):
				rec["fight_t"] = t
				rec["fight_n"] = n
			elif t - float(rec["fight_t"]) >= CAV_STUCK_SEC \
					and float(n) <= float(rec["fight_n"]) * (1.0 - CAV_STUCK_LOSS):
				rec.erase("fight_t")
				rec["until"] = t + CAV_RECHARGE_SEC
				cav_recharges += 1
				for m2 in _members(sid):
					(m2 as Unit).begin_retreat()
				_move(sid, (r["slots"] as Dictionary).get(sid, village), true)
		else:
			rec.erase("fight_t")

## Ближайшая чужая постройка у отряда (любой чужой стороны), не дальше BUILDING_R
func _building_near(from: Vector3) -> Node3D:
	if from == Vector3.INF:
		return null
	var best: Node3D = null
	var bd: float = BUILDING_R * BUILDING_R
	for grp in Constants.enemy_building_groups(Constants.FACTION_GOBLIN):
		for b in main.get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(b) or not (b is Building) or (b as Building).is_dead():
				continue
			var d2: float = from.distance_squared_to((b as Node3D).global_position)
			if d2 < bd:
				bd = d2
				best = b
	return best
