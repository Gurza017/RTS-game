extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 25.09.2026: СПАВН У ИИ, ТЕЛА В ВОДЕ, ЗНАМЯ, ФРОНТ НА ФРОНТ,
## МЕЧНИКИ, ТАКТИКИ ОРДЫ, РУДНИК
## ═══════════════════════════════════════════════════════════════════════════
##   A — НАБЕГ ОРДЫ У ЛАГЕРЯ ИИ (п. 1). «Гоблины у базы ИИ» — это набег,
##       чья цель считалась средним ВСЕХ построек игрока. Цель — крепость;
##       бойцы красного ИИ для набега — враги (раньше — пустое место).
##   B — ФРОНТ НА ФРОНТ (п. 4): front_pairs сохраняет порядок по ширине
##       фронта, пять на пять — пары один к одному.
##   C — ATTACK-MOVE 10 НА 10 (п. 4): отряды игрока сходятся «стенка на
##       стенку», каждый со своим противником, ширина фронта держится.
##   D — ВОЛНА ОРДЫ (п. 4-5): WaveStager при выпуске делит чужую линию.
##   E — МЕЧНИКИ (п. 5): после рывка без цели — окно горячки, боец берёт
##       врага в 10 м, а не стоит.
##   F — ЗНАМЯ (п. 3 + поправка): носитель гибнет — знамя тут же у соседа;
##       пока жив хоть один — на землю не падает; выбит последний — лежит.
##   G — ТЕЛА В ВОДЕ (п. 2): линия воды вдоль тела; второе тело на первом
##       не тонет.
##   H — ТАКТИКИ НАБЕГА (п. 5): схема А — туши впереди, схема Б — конница
##       первой; перезарядка конницы.
##
## Запуск: godot --headless --path . res://qa_tz0925/Test.tscn [-- only=abcdefgh]

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _RaidsT := preload("res://scripts/goblin/GoblinRaids.gd")
const _StagerT := preload("res://scripts/goblin/WaveStager.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _only: String = "abcdefgh"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
	call_deferred("_run")
	get_tree().create_timer(420.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

var _finished := false
func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\n═════ ИТОГ qa_tz0925: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

## Отряд строем 4 в ширину
func _squad(uid: String, at: Vector3, n: int, fac: int) -> int:
	var sid: int = GameManager.new_squad(fac, uid)
	for i in range(n):
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = fac
		main.world_add(u)
		var p := at + Vector3(float(i % 4) * 0.8 - 1.2, 0.0, float(i / 4) * 0.8)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
	return sid

func _members(sid: int) -> Array:
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return []
	var out: Array = []
	for m in (raw as Dictionary)["members"]:
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _kill_sid(sid: int) -> void:
	for m in _members(sid):
		(m as Unit).take_damage(1.0e9)

## Большинство целей отряда: номер чужого отряда (0 — целей нет)
func _target_squad(sid: int) -> int:
	var votes: Dictionary = {}
	for m in _members(sid):
		var t = (m as Unit).attack_target
		if t != null and is_instance_valid(t) and t is Unit and not (t as Unit).is_dead():
			var ts: int = (t as Unit).squad_id
			votes[ts] = int(votes.get(ts, 0)) + 1
	var best := 0
	var bn := 0
	for k in votes.keys():
		if int(votes[k]) > bn:
			bn = int(votes[k])
			best = int(k)
	return best

func _clear_site(c: Vector3, r: float) -> void:
	main._clear_area_of_resources(c, r)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	# Дикие и ИИ вмешиваются в замер — глушим (правило стендов)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if main.get("goblin_reserve") != null and main.goblin_reserve != null:
		main.goblin_reserve.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.pop_limit_enabled = false
	await pframes(4)
	if _only.contains("a"): await _block_a()
	GameManager.world_bounds_enabled = false
	if _only.contains("b"): await _block_b()
	if _only.contains("c"): await _block_c()
	if _only.contains("d"): await _block_d()
	if _only.contains("e"): await _block_e()
	if _only.contains("f"): await _block_f()
	if _only.contains("g"): await _block_g()
	if _only.contains("h"): await _block_h()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. НАБЕГ У ЛАГЕРЯ ИИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. НАБЕГ ОРДЫ: ЦЕЛЬ И ВРАГИ ═════")
	var ga = main.goblin_ai
	var castle: Node3D = null
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b is Building and String((b as Building).building_id) == "castle":
			castle = b
	if castle == null:
		castle = Castle.new()
		castle.faction = Constants.FACTION_PLAYER
		main.world_add(castle)
		var cp: Vector3 = main.PLAYER_BASE_ANCHOR
		castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	# Далёкая постройка игрока — рудник у базы ИИ: прежде она тянула «базу»
	# (среднее) к лагерю ИИ
	var far_m := Mine.new()
	far_m.faction = Constants.FACTION_NEUTRAL
	main.world_add(far_m)
	var fp: Vector3 = main.ENEMY_BASE_ANCHOR + Vector3(30.0, 0.0, -20.0)
	far_m.global_position = Vector3(fp.x, GameManager.get_terrain_height(fp.x, fp.z), fp.z)
	far_m.set_owner_faction(Constants.FACTION_PLAYER)
	await pframes(2)
	var pb: Vector3 = ga._player_base()
	if castle != null:
		verdict("A1 цель набега — крепость игрока, а не среднее всех построек",
			Vector2(pb.x - castle.global_position.x, pb.z - castle.global_position.z).length() < 1.0,
			"цель (%.0f,%.0f), крепость (%.0f,%.0f)" % [pb.x, pb.z, castle.global_position.x, castle.global_position.z])
	else:
		verdict("A1 цель набега — ближе к базе игрока, чем к базе ИИ",
			pb.distance_to(main.PLAYER_BASE_ANCHOR) < pb.distance_to(main.ENEMY_BASE_ANCHOR))
	far_m.release_all()
	# Набег у лагеря ИИ: рядом только бойцы красного ИИ
	var site := Vector3(-300.0, 0.0, 250.0)
	GameManager.world_bounds_enabled = false
	_clear_site(site, 70.0)
	var gr = _RaidsT.new()
	gr.setup(main, site)
	var r: Dictionary = gr.launch({"goblin_spearman": 3}, 0.0, site + Vector3(0.0, 0.0, 80.0), false)
	var reds: Array = []
	for i in range(3):
		reds.append(_squad("spearman", site + Vector3(-14.0 + 14.0 * float(i), 0.0, 24.0), 12,
			Constants.FACTION_ENEMY))
	await pframes(3)
	r["state"] = "attack"
	r["since"] = 0.0
	r["order_t"] = -INF
	gr._step(r, 20.0)
	await pframes(2)
	var hits_enemy := 0
	var total := 0
	var tsq: Dictionary = {}
	for s in r["sids"]:
		for m in _members(int(s)):
			total += 1
			var t = (m as Unit).attack_target
			if t != null and is_instance_valid(t) and t is Unit \
					and (t as Unit).faction == Constants.FACTION_ENEMY:
				hits_enemy += 1
		var ts: int = _target_squad(int(s))
		if ts > 0:
			tsq[ts] = true
	verdict("A2 набег у лагеря ИИ бьёт бойцов ИИ, а не стоит под их стрелами",
		total > 0 and hits_enemy >= int(total * 0.9), "с целью-бойцом ИИ %d из %d" % [hits_enemy, total])
	verdict("A3 три отряда набега — на три разных отряда ИИ (фронт на фронт)",
		tsq.size() == 3, "разных целей %d" % tsq.size())
	for s2 in r["sids"]:
		_kill_sid(int(s2))
	for rs in reds:
		_kill_sid(int(rs))
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. РАСКЛАДКА ФРОНТА
# ═════════════════════════════════════════════════════════════════════════════
func _block_b() -> void:
	print("\n═════ B. ФРОНТ НА ФРОНТ: РАСКЛАДКА ═════")
	var base := Vector3(-300.0, 0.0, -300.0)
	_clear_site(base + Vector3(30.0, 0.0, 10.0), 60.0)
	var mine: Array = []
	var foes: Array = []
	for i in range(5):
		mine.append(_squad("spearman", base + Vector3(12.0 * float(i), 0.0, 0.0), 8, Constants.FACTION_PLAYER))
	# Чужие вразнобой по порядку создания, но по ширине — тем же порядком
	var order := [3, 0, 4, 1, 2]
	var foe_by_x: Dictionary = {}
	for j in order:
		var fs: int = _squad("goblin_spearman", base + Vector3(12.0 * float(j), 0.0, 22.0), 8,
			Constants.FACTION_GOBLIN)
		foes.append(fs)
		foe_by_x[j] = fs
	for u in get_tree().get_nodes_in_group("goblin_units"):
		(u as Unit).set_tick(false)
	await pframes(2)
	var pairs: Dictionary = GameManager.front_pairs(mine, base + Vector3(24.0, 0.0, 11.0), 50.0,
		Constants.FACTION_PLAYER)
	var ok := pairs.size() == 5
	var distinct: Dictionary = {}
	for i2 in range(5):
		var got: int = int(pairs.get(mine[i2], -1))
		distinct[got] = true
		if got != int(foe_by_x[i2]):
			ok = false
	verdict("B1 пять на пять: каждый наш — чужой отряд прямо перед собой", ok and distinct.size() == 5,
		"пар %d, разных %d" % [pairs.size(), distinct.size()])
	# Пять на два — каждый чужой получает соседей со СВОЕЙ стороны
	_kill_sid(int(foe_by_x[1]))
	_kill_sid(int(foe_by_x[2]))
	_kill_sid(int(foe_by_x[3]))
	await pframes(3)
	var p2: Dictionary = GameManager.front_pairs(mine, base + Vector3(24.0, 0.0, 11.0), 50.0,
		Constants.FACTION_PLAYER)
	var left_ok: bool = int(p2.get(mine[0], -1)) == int(foe_by_x[0]) and int(p2.get(mine[4], -1)) == int(foe_by_x[4])
	verdict("B2 пять на два: левые берут левый чужой отряд, правые — правый", left_ok and p2.size() == 5)
	for s in mine + foes:
		_kill_sid(int(s))
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ATTACK-MOVE 10 НА 10
# ═════════════════════════════════════════════════════════════════════════════
func _block_c() -> void:
	print("\n═════ C. ATTACK-MOVE 10 НА 10: СТЕНКА НА СТЕНКУ ═════")
	var base := Vector3(-200.0, 0.0, -320.0)
	_clear_site(base + Vector3(55.0, 0.0, 25.0), 110.0)
	var sm = main.selection_manager
	var mine: Array = []
	var foes: Array = []
	var sel: Array = []
	for i in range(10):
		var sid: int = _squad("spearman", base + Vector3(12.0 * float(i), 0.0, 0.0), 16, Constants.FACTION_PLAYER)
		mine.append(sid)
		sel += _members(sid)
		foes.append(_squad("goblin_spearman", base + Vector3(12.0 * float(i), 0.0, 36.0), 16,
			Constants.FACTION_GOBLIN))
	await pframes(3)
	var w0: float = _front_width(mine)
	sm.selected_units = sel
	GameManager.on_selection_changed(sm.selected_units)
	await pframes(2)
	var sc = sm.squad_commander()
	var fa0: int = int(sc.front_assigns)
	sc.attack_move(sm, base + Vector3(54.0, 0.0, 70.0), false)
	# Ждём, пока в бой вступит большинство наших отрядов
	var g := 0
	var fighting := 0
	while g < 60 * 30:
		await get_tree().physics_frame
		g += 1
		if g % 20 != 0:
			continue
		fighting = 0
		for s in mine:
			if _target_squad(int(s)) > 0:
				fighting += 1
		if fighting >= 8:
			break
	await pframes(60 * 2)
	var per_foe: Dictionary = {}
	var engaged := 0
	for s2 in mine:
		var ts: int = _target_squad(int(s2))
		if ts > 0:
			engaged += 1
			per_foe[ts] = int(per_foe.get(ts, 0)) + 1
	var worst := 0
	for k in per_foe.keys():
		worst = maxi(worst, int(per_foe[k]))
	var w1: float = _front_width(mine)
	print("    в бою %d из 10 за %d физкадров, разных целей %d, худший — %d на один, ширина %.1f → %.1f м, раскладок %d" % [
		engaged, g, per_foe.size(), worst, w0, w1, int(sc.front_assigns) - fa0])
	verdict("C1 Attack-Move раздаёт цели раскладкой фронта", int(sc.front_assigns) > fa0)
	verdict("C2 отряды бьют РАЗНЫХ противников (не меньше 7 из 10)", per_foe.size() >= 7,
		"разных %d при %d в бою" % [per_foe.size(), engaged])
	verdict("C3 ни на один чужой отряд не навалились больше двух наших", worst <= 2, "худший %d" % worst)
	verdict("C4 фронт не сплющился: ширина линии держится (≥ 70 %)", w1 >= 0.7 * w0,
		"%.1f из %.1f м" % [w1, w0])
	sm.selected_units = []
	GameManager.on_selection_changed(sm.selected_units)
	for s3 in mine + foes:
		_kill_sid(int(s3))
	await pframes(3)

## Ширина линии отрядов: размах центров по X
func _front_width(sids: Array) -> float:
	var lo := INF
	var hi := -INF
	for s in sids:
		var c: Vector2 = GameManager.squad_centre_xz(int(s))
		if c == Vector2.INF:
			continue
		lo = minf(lo, c.x)
		hi = maxf(hi, c.x)
	return hi - lo if hi > lo else 0.0

# ═════════════════════════════════════════════════════════════════════════════
# D. ВОЛНА ОРДЫ ДЕЛИТ ЧУЖУЮ ЛИНИЮ
# ═════════════════════════════════════════════════════════════════════════════
func _block_d() -> void:
	print("\n═════ D. ВОЛНА ОРДЫ: ФРОНТ НА ФРОНТ ═════")
	var base := Vector3(-300.0, 0.0, -150.0)
	_clear_site(base + Vector3(24.0, 0.0, 15.0), 60.0)
	var gob: Array = []
	var ply: Array = []
	for i in range(5):
		gob.append(_squad("goblin_spearman", base + Vector3(12.0 * float(i), 0.0, 0.0), 8, Constants.FACTION_GOBLIN))
		ply.append(_squad("spearman", base + Vector3(12.0 * float(i), 0.0, 30.0), 8, Constants.FACTION_PLAYER))
	for u in get_tree().get_nodes_in_group("goblin_units") + get_tree().get_nodes_in_group("player_units"):
		(u as Unit).set_tick(false)
	await pframes(2)
	var st = _StagerT.new()
	# Вся волна увидела ОДНОГО врага — средний отряд игрока (прежде это и был
	# ключ «все пятеро в него»)
	var focus: Unit = _members(int(ply[2]))[0]
	# Такт владельца — каждые 2 с (все отряды группы свежие), сбор истекает
	# по MAX_STAGE_SEC: отряды стоят не на местах линии
	var got: Dictionary = {}
	var now := 0.0
	while now <= _StagerT.MAX_STAGE_SEC + 2.0:
		got.clear()
		for s in gob:
			var c: Vector2 = GameManager.squad_centre_xz(int(s))
			var ans: Dictionary = st.gate(int(s), Vector3(c.x, 0.0, c.y), focus, now)
			if ans.has("foe") and is_instance_valid(ans["foe"]):
				got[(ans["foe"] as Unit).squad_id] = true
		now += 2.0
	verdict("D1 выпущенная волна делит чужую линию: пять отрядов — пять разных целей",
		got.size() == 5, "разных %d, пар выдано %d" % [got.size(), st.pairs_assigned])
	for s3 in gob + ply:
		_kill_sid(int(s3))
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. МЕЧНИКИ ПОСЛЕ РЫВКА
# ═════════════════════════════════════════════════════════════════════════════
func _block_e() -> void:
	print("\n═════ E. МЕЧНИКИ: КОНЕЦ РЫВКА ═════")
	var base := Vector3(-350.0, 0.0, -80.0)
	_clear_site(base, 30.0)
	var sid: int = _squad("warrior", base, 4, Constants.FACTION_PLAYER)
	await pframes(3)
	var ws: Array = _members(sid)
	for w in ws:
		(w as Warrior).start_rage_dash()
		(w as Warrior)._rage_until_ms = 0
		(w as Warrior)._rush_aggro()
	var w0 := ws[0] as Warrior
	verdict("E1 рывок кончился без цели — окно горячки, радиус агро = радиус рывка",
		w0.rush_hot_count == 1 and is_equal_approx(w0.aggro_radius(), Warrior.RUSH_AGGRO_R),
		"горячек %d, радиус %.1f" % [w0.rush_hot_count, w0.aggro_radius()])
	# Враг в 10 м: при обычных 5 м мечник стоял бы
	var gs: int = _squad("goblin_spearman", base + Vector3(0.0, 0.0, 10.0), 2, Constants.FACTION_GOBLIN)
	for g in _members(gs):
		(g as Unit).set_tick(false)
	var f := 0
	var att := 0
	while f < 60 * 4:
		await get_tree().physics_frame
		f += 1
		att = 0
		for w2 in ws:
			if (w2 as Unit).state == Unit.State.ATTACKING:
				att += 1
		if att == ws.size():
			break
	verdict("E2 мечники не замирают: враг в 10 м взят в бой сам", att == ws.size(),
		"в бою %d из %d за %d физкадров" % [att, ws.size(), f])
	w0._rush_hot_until_ms = 0
	verdict("E3 горячка кончилась — радиус агро снова 5 м", is_equal_approx(w0.aggro_radius(), Warrior.WARRIOR_AGGRO_RADIUS))
	_kill_sid(sid)
	_kill_sid(gs)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# F. ЗНАМЯ
# ═════════════════════════════════════════════════════════════════════════════
func _block_f() -> void:
	print("\n═════ F. ЗНАМЯ ОТРЯДА ═════")
	var base := Vector3(-350.0, 0.0, -30.0)
	_clear_site(base, 30.0)
	var sid: int = _squad("spearman", base, 6, Constants.FACTION_PLAYER)
	main.grant_squad_veterancy(sid, 2, 0, [])
	GameManager.refresh_squad_banner(sid)
	await pframes(3)
	var drop0: int = GameManager.banners_dropped
	var b0 = GameManager.squad_bearer(sid)
	var bn = GameManager.squads[sid].get("banner")
	verdict("F0 у ветерана есть знамя и знаменосец", b0 != null and bn != null and is_instance_valid(bn))
	if b0 == null:
		return
	(b0 as Unit).take_damage(1.0e9)
	# МГНОВЕННО — в том же кадре, без ожидания
	var b1 = GameManager.squad_bearer(sid)
	verdict("F1 носитель пал — знамя в том же кадре у живого соседа",
		b1 != null and is_instance_valid(b1) and b1 != b0 and not (b1 as Unit).is_dead())
	await pframes(2)
	var ms: Array = _members(sid)
	for k in range(ms.size() - 1):
		(ms[k] as Unit).take_damage(1.0e9)
		await pframes(1)
	await pframes(2)
	var bn2 = GameManager.squads.get(sid, {}).get("banner") if GameManager.squads.has(sid) else null
	verdict("F2 пока жив хоть один — знамя не падает и у отряда",
		GameManager.banners_dropped == drop0 and bn2 != null and is_instance_valid(bn2)
		and GameManager.squad_bearer(sid) != null, "упало %d" % (GameManager.banners_dropped - drop0))
	var last: Array = _members(sid)
	for m in last:
		(m as Unit).take_damage(1.0e9)
	await pframes(4)
	verdict("F3 выбит последний — знамя легло на землю (слой тел), узел знамени снят",
		GameManager.banners_dropped == drop0 + 1 and not GameManager.squads.has(sid)
		and (bn == null or not is_instance_valid(bn)),
		"упало %d" % (GameManager.banners_dropped - drop0))
	# Перевод последнего бойца в другой отряд — не гибель: знамя не падает
	var sid2: int = _squad("spearman", base + Vector3(8.0, 0.0, 0.0), 1, Constants.FACTION_PLAYER)
	main.grant_squad_veterancy(sid2, 2, 0, [])
	GameManager.refresh_squad_banner(sid2)
	var sid3: int = _squad("spearman", base + Vector3(14.0, 0.0, 0.0), 1, Constants.FACTION_PLAYER)
	await pframes(2)
	var d1: int = GameManager.banners_dropped
	GameManager.add_to_squad(sid3, _members(sid2)[0])
	await pframes(3)
	verdict("F4 перевод последнего бойца в другой отряд знамя на землю не роняет",
		GameManager.banners_dropped == d1)
	_kill_sid(sid3)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# G. ТЕЛА В ВОДЕ
# ═════════════════════════════════════════════════════════════════════════════
func _block_g() -> void:
	print("\n═════ G. ТЕЛА В ВОДЕ ═════")
	GameManager.world_bounds_enabled = true
	var wp := Vector3.INF
	var x := -400.0
	while x <= 400.0 and wp == Vector3.INF:
		var z := -300.0
		while z <= 300.0:
			if bool(main.call("in_water_mesh", x, z)) \
					and float(main.call("water_surface_y", x, z)) > GameManager.get_terrain_height(x, z) + 0.1:
				wp = Vector3(x, 0.0, z)
				break
			z += 4.0
		x += 4.0
	GameManager.world_bounds_enabled = false
	verdict("G0 на карте нашлась вода для тел", wp != Vector3.INF)
	if wp == Vector3.INF:
		return
	var cr = GameManager.corpses
	var l2_0: int = int(cr.wet_layer2)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var us: Array = []
	for i in range(2):
		var u: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(wp.x + 0.05 * float(i), GameManager.get_terrain_height(wp.x, wp.z), wp.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		us.append(u)
	await pframes(2)
	(us[0] as Unit).take_damage(1.0e9)
	await pframes(2)
	# Мокрый бакет: полоса фигуры по ШИРИНЕ кадра задана и уже кадра
	var wet_mat: ShaderMaterial = null
	for k in cr._buckets.keys():
		if String(k).contains("|wet"):
			var bk = cr._buckets[k]
			wet_mat = (bk.mm.mesh as QuadMesh).material as ShaderMaterial
	var fl: Variant = wet_mat.get_shader_parameter("fig_left") if wet_mat != null else null
	var fr: Variant = wet_mat.get_shader_parameter("fig_right") if wet_mat != null else null
	verdict("G1 тело в воде: линия воды вдоль тела — полоса фигуры по ширине кадра",
		wet_mat != null and fl != null and fr != null and float(fl) >= 0.0 and float(fr) <= 1.0
		and float(fr) > float(fl) and float(wet_mat.get_shader_parameter("submerge")) > 0.0,
		"слева %s, справа %s" % [str(fl), str(fr)])
	(us[1] as Unit).take_damage(1.0e9)
	await pframes(2)
	verdict("G2 второе тело на первом в воде не тонет — лежит сухим поверх",
		int(cr.wet_layer2) == l2_0 + 1, "вторым слоем %d" % (int(cr.wet_layer2) - l2_0))

# ═════════════════════════════════════════════════════════════════════════════
# H. ТАКТИКИ НАБЕГА
# ═════════════════════════════════════════════════════════════════════════════
func _block_h() -> void:
	print("\n═════ H. ТАКТИКИ НАБЕГА ═════")
	var site := Vector3(-150.0, 0.0, -300.0)
	_clear_site(site, 80.0)
	var gr = _RaidsT.new()
	gr.setup(main, site)
	var tgt: Vector3 = site + Vector3(0.0, 0.0, 90.0)
	# Набег №0 — схема А (туши впереди пехоты)
	var ra: Dictionary = gr.launch({"goblin_spearman": 1, "big_goblin": 2, "goblin_rider": 2}, 0.0, tgt, false)
	var inf_d := 0.0
	var hv_d := 0.0
	for s in ra["slots"].keys():
		var d: float = (ra["slots"][s] as Vector3).distance_to(tgt)
		match String(ra["kinds"][s]):
			"big_goblin": hv_d = d
			"goblin_spearman": inf_d = d
	verdict("H1 схема А: туши первой линией — ближе к цели, чем пехота",
		String(ra["tactic"]) == _RaidsT.TACTIC_A and hv_d < inf_d, "туши %.1f, пехота %.1f" % [hv_d, inf_d])
	verdict("H2 схема А: конница выжидает, пехота и туши идут сразу",
		gr._waits(ra, _sid_of(ra, "goblin_rider"), 1.0) and not gr._waits(ra, _sid_of(ra, "goblin_spearman"), 1.0)
		and not gr._waits(ra, _sid_of(ra, "goblin_rider"), _RaidsT.CAV_DELAY_SEC + 0.5))
	# Набег №1 — схема Б (конница первой)
	var rb: Dictionary = gr.launch({"goblin_spearman": 1, "big_goblin": 2, "goblin_rider": 2}, 0.0, tgt, false)
	verdict("H3 схема Б: конница первой, центр держит линию",
		String(rb["tactic"]) == _RaidsT.TACTIC_B
		and not gr._waits(rb, _sid_of(rb, "goblin_rider"), 1.0)
		and gr._waits(rb, _sid_of(rb, "goblin_spearman"), 1.0)
		and not gr._waits(rb, _sid_of(rb, "goblin_spearman"), _RaidsT.INF_DELAY_SEC + 0.5))
	# Перезарядка конницы: завязла и потеряла четверть — отходит на место
	var cav: int = _sid_of(ra, "goblin_rider")
	var foe: int = _squad("spearman", site + Vector3(20.0, 0.0, 20.0), 4, Constants.FACTION_PLAYER)
	for m in _members(cav):
		(m as Unit).command_attack(_members(foe)[0], true)
	await pframes(2)
	GameManager.squad_mark_hit(cav)
	ra["state"] = "attack"
	ra["since"] = 0.0
	gr._cav_recharge(ra, 10.0)
	var ms: Array = _members(cav)
	for k in range(int(ceil(ms.size() * 0.3))):
		(ms[k] as Unit).take_damage(1.0e9)
	await pframes(2)
	GameManager.squad_mark_hit(cav)
	var rc0: int = gr.cav_recharges
	gr._cav_recharge(ra, 10.0 + _RaidsT.CAV_STUCK_SEC + 0.5)
	verdict("H4 завязшая конница уходит на перезарядку и выжидает",
		gr.cav_recharges == rc0 + 1 and gr._waits(ra, cav, 10.0 + _RaidsT.CAV_STUCK_SEC + 1.0),
		"перезарядок %d" % (gr.cav_recharges - rc0))
	for r in [ra, rb]:
		for s2 in r["sids"]:
			_kill_sid(int(s2))
	_kill_sid(foe)
	await pframes(3)

func _sid_of(r: Dictionary, kind: String) -> int:
	for s in r["sids"]:
		if String(r["kinds"][s]) == kind:
			return int(s)
	return -1
