extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПРИКАЗ ИГРОКА НА ОТХОД ИЗ БОЯ (ТЗ 21.10.2026, письмо 4, п. 3)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: «в бою отдаёшь приказ отойти — делают шаг-два, снова агрятся на
## ближайшего, сбрасывают марш и разворачиваются (особенно лучники)».
##   A — копейщики + лучники в рубке с пехотой орды → ПКМ на 30 м назад:
##       дошли до точки, никто не взял новую цель по дороге
##   B — одни лучники под натиском пехоты орды → отход: то же
##   C — справочно: тот же сценарий A с выключенной ручкой
##       perf_config.retreat_squad_lock (прежнее поведение) — вердикта нет
##   D — после прихода в точку бой снова разрешён: враг, подошедший к
##       стоящим, получает ответ
## Механизм: Unit.command_move → _disengaging у всего отряда в бою.
## Запуск: godot --headless --path . res://qa_forced_retreat_in_combat/Test.tscn [-- only=abcd]

const _Opt := preload("res://scripts/perf_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcd"
var _done := false
var _diag := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		if String(a) == "diag=1":
			_diag = true
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_forced_retreat_in_combat: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(kind: String, at: Vector3, fac: int) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, at: Vector3, n: int, fac: int, cols: int = 8) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var out: Array = []
	for k in range(n):
		var u := _spawn(kind, at + Vector3(float(k % cols) * 0.7, 0, float(k / cols) * 0.7), fac)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _clear(at: Vector3, r: float) -> void:
	main._clear_trees(at, r)
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and (u as Node3D).global_position.distance_to(at) < r:
			u.queue_free()

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
	if "a" in _only:
		var r: Dictionary = await _retreat_case(Vector3(-80, 0, -10), true)
		_judge("A", "копейщики + лучники", r)
	if "b" in _only:
		var r2: Dictionary = await _retreat_case(Vector3(-30, 0, -10), false)
		_judge("B", "одни лучники", r2)
	if "c" in _only:
		_Opt.retreat_squad_lock = false
		var r3: Dictionary = await _retreat_case(Vector3(-80, 0, 40), true)
		_Opt.retreat_squad_lock = true
		print("  C справочно, ручка выключена: дошли %d из %d, взяли цель по дороге %d (лучников %d)" % [
			r3.arrived, r3.n, r3.reengaged, r3.reeng_archers])
	if "d" in _only:
		await _d_fight_after()
	_finish()

## Бой → приказ отойти на 30 м. Возвращает: дошли, взяли цель по дороге
## (после 1 с от приказа, до прихода), развернулись назад (удалились от точки
## на 4 м от своего минимума)
func _retreat_case(at: Vector3, with_spears: bool, am: bool = false) -> Dictionary:
	_clear(at, 60.0)
	await pframes(3)
	var mine: Array = []
	if with_spears:
		mine.append_array(_squad("spearman", at + Vector3(-6, 0, 0), 24, F))
		mine.append_array(_squad("spearman", at + Vector3(2, 0, 0), 24, F))
	mine.append_array(_squad("archer", at + Vector3(-2, 0, -6 if with_spears else 0), 24, F))
	var foes: Array = _squad("goblin_spearman", at + Vector3(-6, 0, 7), 30 if with_spears else 12, G, 10)
	if with_spears:
		foes.append_array(_squad("goblin_spearman", at + Vector3(3, 0, 7), 30, G, 10))
	await pframes(10)
	for f in foes:
		(f as Unit).command_attack(mine[randi() % mine.size()], true)
	if am:
		# Attack-Move [A] сквозь противника — настоящим путём игрока
		var sm0 = main.selection_manager
		sm0.select_units(mine)
		sm0.order_at_world(at + Vector3(0, 0, 30), true)
		sm0.clear_selection()
	else:
		for m in mine:
			(m as Unit).command_attack(foes[randi() % foes.size()], true)
	# Рубка завязалась: у большинства живая цель и есть контакт
	var t := 0
	while t < 900:
		await pframes(10)
		t += 10
		var busy := 0
		for m in _alive(mine):
			if (m as Unit).state == Unit.State.ATTACKING:
				busy += 1
		if t >= 300 and busy * 2 >= _alive(mine).size():
			break
	await pframes(60)
	var archers_fired0: int = GameManager.arrows_fired
	# ПРИКАЗ: всем выделенным — ПКМ на 30 м назад, настоящим путём игрока
	var sm = main.selection_manager
	var men: Array = _alive(mine)
	sm.select_units(men)
	var goal := at + Vector3(0, 0, -30)
	var sids: Dictionary = {}
	for m in men:
		sids[(m as Unit).squad_id] = true
	var am_before := 0
	for sid in sids:
		if sm._squad_cmd().is_attack_moving(int(sid)):
			am_before += 1
	sm.order_at_world(goal, false)
	sm.clear_selection()
	var am_after := 0
	for sid in sids:
		if sm._squad_cmd().is_attack_moving(int(sid)):
			am_after += 1
	var post: Dictionary = {}
	var best: Dictionary = {}
	for m in men:
		post[m] = (m as Unit).post_pos
		best[m] = 1e9
	var reeng: Dictionary = {}
	var turned: Dictionary = {}
	var arrived: Dictionary = {}
	t = 0
	while t < 1800:
		await pframes(10)
		t += 10
		if _diag and t in [10, 30, 60, 120, 240, 480]:
			var hist := {}
			for m in _alive(men):
				var u := m as Unit
				var k: String = "%s st=%d dis=%s lock=%.1f cont=%s mv=%s tgt=%s stance=%s" % [u.stat_id, u.state,
					str(u.get("_disengaging")), float(u.get("_move_lock")), str(u.get("_enemy_contact")),
					str(u.moved_recently()), str(u.attack_target != null), str(u.stance)]
				hist[k] = int(hist.get(k, 0)) + 1
			print("    t=%d %s" % [t, str(hist)])
		for m in men:
			if not is_instance_valid(m) or (m as Unit).is_dead() or arrived.has(m):
				continue
			var u := m as Unit
			var d: float = Vector2(u.global_position.x - post[m].x, u.global_position.z - post[m].z).length()
			best[m] = minf(float(best[m]), d)
			if d > float(best[m]) + 4.0:
				turned[m] = true
			if d < 3.0 or (u.state == Unit.State.IDLE and d < 4.5):
				arrived[m] = true
				continue
			if t > 60 and u.attack_target != null and is_instance_valid(u.attack_target) \
					and u.state == Unit.State.ATTACKING:
				reeng[m] = true
		var left := 0
		for m in _alive(men):
			if not arrived.has(m):
				left += 1
		if left == 0:
			break
	var n_alive: int = _alive(men).size()
	var reeng_arch := 0
	for m in reeng:
		if is_instance_valid(m) and (m as Unit).stat_id == "archer":
			reeng_arch += 1
	var res := {"n": n_alive, "arrived": arrived.size(), "reengaged": reeng.size(),
		"reeng_archers": reeng_arch, "turned": turned.size(), "sec": float(t) / 60.0,
		"shots_after": GameManager.arrows_fired - archers_fired0,
		"am_before": am_before, "am_after": am_after, "squads": sids.size()}
	print("  отход: живых %d, дошли %d за %.1f с, взяли цель по дороге %d (лучников %d), развернулись %d, стрел после приказа %d" % [
		n_alive, res.arrived, res.sec, res.reengaged, reeng_arch, res.turned, res.shots_after])
	_free(mine)
	_free(foes)
	await pframes(10)
	return res

func _judge(tag: String, what: String, r: Dictionary) -> void:
	print("\n═════ %s. %s: БОЙ → ПРИКАЗ ОТОЙТИ ═════" % [tag, what])
	var n: int = maxi(1, int(r.n))
	verdict("%s1 %s: до точки дошли ≥ 95 %% живых" % [tag, what],
		float(r.arrived) >= 0.95 * float(n), "%d из %d" % [r.arrived, n])
	verdict("%s2 %s: новую цель по дороге не взял никто из лучников" % [tag, what],
		int(r.reeng_archers) == 0, "лучников %d" % r.reeng_archers)
	verdict("%s3 %s: вернулись в бой по дороге ≤ 5 %% (упор телом законен)" % [tag, what],
		float(r.reengaged) <= 0.05 * float(n), "%d из %d" % [r.reengaged, n])
	verdict("%s4 %s: развернулись назад ≤ 5 %%" % [tag, what],
		float(r.turned) <= 0.05 * float(n), "%d из %d" % [r.turned, n])

## После прихода в точку признак снят: подошедшему врагу — ответ
func _d_fight_after() -> void:
	print("\n═════ D. ПОСЛЕ ОТХОДА БОЙ СНОВА РАЗРЕШЁН ═════")
	var at := Vector3(-30, 0, 40)
	_clear(at, 50.0)
	await pframes(3)
	var men: Array = _squad("spearman", at, 24, F)
	var gob: Array = _squad("goblin_spearman", at + Vector3(0, 0, 4), 6, G, 3)
	await pframes(5)
	for m in men:
		(m as Unit).command_attack(gob[0], true)
	await pframes(240)
	var sm = main.selection_manager
	sm.select_units(_alive(men))
	sm.order_at_world(at + Vector3(0, 0, -25), false)
	sm.clear_selection()
	_free(gob)
	var t := 0
	while t < 1500:
		await pframes(10)
		t += 10
		var idle := 0
		for m in _alive(men):
			if (m as Unit).state == Unit.State.IDLE:
				idle += 1
		if idle == _alive(men).size():
			break
	var dis := 0
	for m in _alive(men):
		if bool(m.get("_disengaging")):
			dis += 1
	verdict("D1 дошли — признак выхода из боя снят у всех", dis == 0, "осталось %d" % dis)
	var foe := _spawn("goblin_spearman", (men[0] as Node3D).global_position + Vector3(0, 0, 1.2), G)
	foe.command_attack(men[0], true)
	var answered := false
	t = 0
	while t < 600 and not answered:
		await pframes(10)
		t += 10
		for m in _alive(men):
			if (m as Unit).attack_target == foe:
				answered = true
	verdict("D2 подошедший враг получает ответ стоящих", answered)
	_free(men)
	if is_instance_valid(foe):
		foe.queue_free()
