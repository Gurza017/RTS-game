extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ПОВОДКА ОТРЯДА (ТЗ 22.10.2026): боец не отрывается от строя за агро
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба по скриншотам: у пня 3-8 бойцов отряда уходили «за полэкрана»
## вправо/вверх без приказа, пока строй стоял. Каждый блок ставит отряд
## копейщиков ПКМ-приказом (настоящая разметка строя), ждёт, пока встанет, и
## пускает раздражитель. Судится свойство: НИ ОДИН боец не дальше поводка
## (Unit.CHASE_LEASH + запас на шаг) от своего поста строя, и через
## RETURN_SEC после ухода врага все снова на постах.
##   A — стоящий отряд [C], одиночный гоблин проходит по касательной в 15 м
##   B — то же, гоблин в 6 м (попадает в агро): дерутся, но не уходят за ним
##   C — стоящий отряд, гнолл мечет кости с 10-12 м и отбегает (кайтит)
##   D — отряд на марше, гоблин по касательной в 15 м
##   E — после стычки выживший отряд орды разбегается врассыпную (паника)
##   F — лучники стоят, гоблин проходит в 13 м по касательной
##   G — стойка [C] «Вольно»: враг в 6.5 м от БЛИЖНЕГО бойца (копейщики,
##       мечники) — ни один не трогается с поста и не берёт цель
## Запуск: godot --headless --path . res://qa_squad_leash_test/Test.tscn [-- only=abcdef]

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

## Запас сверх поводка: боец в рубке стоит на длине оружия от поста цели
const SLACK := 2.5
## За сколько после ухода раздражителя отряд обязан стоять на постах
const RETURN_SEC := 12.0
## «На посту» — ближе этого к своему посту
const HOME_R := 3.0

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcdefg"
var _done := false
var _diag := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
		if String(a) == "diag=1":
			_diag = true
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
	print("\n═════ ИТОГ qa_squad_leash_test: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(kind: String, at: Vector3, n: int, fac: int = F, cols: int = 6) -> Array:
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
	var leash: float = float((load("res://scripts/Unit.gd") as Script).get_script_constant_map().get("CHASE_LEASH", 8.0))
	print("  поводок отряда %.1f м (+ запас %.1f)" % [leash, SLACK])
	if "a" in _only: await _case("A", "стоит, гоблин по касательной в 15 м", "spearman", 15.0, "pass", false, leash)
	if "b" in _only: await _case("B", "стоит, гоблин в 6 м (агро)", "spearman", 6.0, "pass", false, leash)
	if "c" in _only: await _case("C", "стоит, гнолл мечет и кайтит", "spearman", 11.0, "kite", false, leash)
	if "d" in _only: await _case("D", "марш, гоблин по касательной в 15 м", "spearman", 15.0, "pass", true, leash)
	if "e" in _only: await _case("E", "разбитый отряд орды разбегается", "spearman", 5.0, "rout", false, leash)
	if "f" in _only: await _case("F", "лучники стоят, гоблин в 13 м", "archer", 13.0, "pass", false, leash)
	if "g" in _only:
		await _case_g("spearman")
		await _case_g("warrior")
	_finish()

## Стойка [C]: прохожий в 6.5 м от ближнего бойца строя
func _case_g(kind: String) -> void:
	print("
═════ G. [C] %s: враг в 6.5 м от ближнего бойца ═════" % kind)
	var at := Vector3(-40, 0, 10)
	_clear(at, 60.0)
	await pframes(5)
	var men: Array = await _form(kind, at, 30)
	var sm = main.selection_manager
	sm.select_units(men)
	sm._squad_cmd().at_ease(sm)
	sm.clear_selection()
	await pframes(10)
	var max_x := -INF
	for m in _alive(men):
		max_x = maxf(max_x, (m as Node3D).global_position.x)
	var g := _spawn("goblin_spearman", Vector3(max_x + 6.5, 0, at.z - 24.0), G)
	g.max_health *= 3.0
	g.current_health = g.max_health
	g.command_move(GameManager.land_target(Vector3(max_x + 6.5, 0, at.z + 30.0)), false, Vector3.ZERO, false, true)
	var moved := 0.0
	var took := 0
	var closest := INF
	var t := 0
	while t < 60 * 16:
		await pframes(10)
		t += 10
		if is_instance_valid(g):
			for m2 in _alive(men):
				closest = minf(closest, (m2 as Node3D).global_position.distance_to(g.global_position))
		for m3 in _alive(men):
			var u := m3 as Unit
			moved = maxf(moved, Vector2(u.global_position.x - u.post_pos.x, u.global_position.z - u.post_pos.z).length())
			if u.attack_target != null and is_instance_valid(u.attack_target):
				took += 1
	print("  G %s: ближе всего враг прошёл %.1f м, худший уход с поста %.2f м, брали цель %d раз" % [kind, closest, moved, took])
	verdict("G %s: [C] держит пост при враге в 6+ м" % kind, closest >= 6.0 and moved <= 1.0 and took == 0,
		"враг %.1f м, уход %.2f м, целей %d" % [closest, moved, took])
	_free(men)
	if is_instance_valid(g):
		g.queue_free()
	await pframes(10)

## Поставить отряд ПКМ-приказом (настоящая разметка), дождаться постов
func _form(kind: String, at: Vector3, n: int) -> Array:
	var men: Array = _squad(kind, at + Vector3(-6, 0, 0), n, F, 10)
	await pframes(5)
	var sm = main.selection_manager
	sm.select_units(men)
	sm.order_at_world(at, false)
	sm.clear_selection()
	var t := 0
	while t < 900:
		await pframes(15)
		t += 15
		var home := 0
		for m in _alive(men):
			var u := m as Unit
			if u.global_position.distance_to(u.post_pos) < HOME_R and u.state == Unit.State.IDLE:
				home += 1
		if home >= int(0.9 * float(men.size())):
			break
	return men

func _case(tag: String, title: String, kind: String, dist: float, mode: String,
		march: bool, leash: float) -> void:
	print("\n═════ %s. %s ═════" % [tag, title])
	var at := Vector3(-40, 0, -30 + (tag.unicode_at(0) - 65) * 4.0)
	_clear(at, 60.0)
	await pframes(5)
	var men: Array = await _form(kind, at, 30)
	var sm = main.selection_manager
	if march:
		sm.select_units(men)
		sm.order_at_world(at + Vector3(0, 0, 26), false)
		sm.clear_selection()
		await pframes(20)
	# Раздражитель
	var foes: Array = []
	var foe_goal := Vector3.ZERO
	if mode == "pass":
		var g := _spawn("goblin_spearman", at + Vector3(dist, 0, -22), G)
		g.max_health *= 3.0
		g.current_health = g.max_health
		foe_goal = at + Vector3(dist, 0, 40)
		g.command_move(GameManager.land_target(foe_goal), false, Vector3.ZERO, false, true)
		foes.append(g)
	elif mode == "kite":
		var gn := _spawn("gnoll", at + Vector3(dist, 0, 0), G)
		gn.max_health *= 4.0
		gn.current_health = gn.max_health
		foes.append(gn)
	elif mode == "rout":
		foes = _squad("goblin_spearman", at + Vector3(dist, 0, -2), 9, G, 3)
		for f in foes:
			(f as Unit).current_health = (f as Unit).max_health * 0.25
	var worst := 0.0
	var worst_cnt := 0
	var t := 0
	var gone_t := -1
	var rout_done := false
	while t < 60 * 30:
		await pframes(10)
		t += 10
		# Гнолл кайтит: раз в 2 с отбегает от ближайшего бойца на 8 м
		if mode == "kite" and t % 120 == 0 and not _alive(foes).is_empty():
			var gn2 := foes[0] as Unit
			var away: Vector3 = gn2.global_position - at
			away.y = 0.0
			away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
			gn2.command_move(GameManager.land_target(gn2.global_position + away * 8.0 + Vector3(0, 0, 6)), false, Vector3.ZERO, false, true)
		# Разгром: через 3 с контакта выжившие бегут врассыпную
		if mode == "rout" and not rout_done and t >= 180:
			rout_done = true
			var k := 0
			for f2 in _alive(foes):
				var ang: float = float(k) * 0.9
				(f2 as Unit).command_move(GameManager.land_target((f2 as Node3D).global_position \
					+ Vector3(cos(ang), 0, sin(ang)) * 40.0 + Vector3(25, 0, 0)), false, Vector3.ZERO, false, true)
				k += 1
		var cnt := 0
		for m in _alive(men):
			var u := m as Unit
			var d: float = Vector2(u.global_position.x - u.post_pos.x, u.global_position.z - u.post_pos.z).length()
			if march:
				# На марше пост уезжает вперёд — меряем от центра отряда
				var c: Vector3 = GameManager.squad_centroid(u.squad_id)
				d = maxf(0.0, Vector2(u.global_position.x - c.x, u.global_position.z - c.z).length() - 8.0)
			if d > leash + SLACK:
				cnt += 1
				if _diag:
					var bx: Dictionary = GameManager.box.box_of(u.squad_id)
					print("    BOX t=%.2f d=%.1f st=%d goal=%s row=%d F=%s home=%s anchor=%s course=%s" % [float(t) / 60.0, d, u.state, u._box_goal, u._box_row,
						bx.get("F"), bx.get("home"), bx.get("anchor"), bx.get("course")])
				if _diag and t % 60 == 0:
					var tg = u.attack_target
					print("    DIAG t=%.1f d=%.1f st=%d tgt=%s lock=%s forced=%s leash_from=%s ret=%s dis=%s" % [float(t) / 60.0, d, u.state,
						(tg.name if tg != null and is_instance_valid(tg) else "-"), u.target_lock, u._attack_is_forced, u.get("_leash_from"), u.retreating, u._disengaging])
					print("      box_goal=%s row=%d pos=%s post=%s" % [u._box_goal, u._box_row, u.global_position, u.post_pos])
			worst = maxf(worst, d)
		worst_cnt = maxi(worst_cnt, cnt)
		# Раздражитель ушёл: дальше 30 м от отряда или погиб
		var near := false
		for f3 in _alive(foes):
			if (f3 as Node3D).global_position.distance_to(at) < 30.0:
				near = true
		if not near and gone_t < 0 and t > 120:
			gone_t = t
		if gone_t >= 0 and t - gone_t > int(RETURN_SEC * 60.0):
			break
	var home := 0
	var alive: Array = _alive(men)
	for m in alive:
		var u := m as Unit
		if u.global_position.distance_to(u.post_pos) < HOME_R or march:
			home += 1
		elif _diag:
			print("    NOTHOME d=%.1f st=%d pos=%s post=%s mt=%s rip=%d tgt=%s" % [u.global_position.distance_to(u.post_pos), u.state,
				u.global_position, u.post_pos, u.move_target, Unit.game_ms() - u._rip_last_ms,
				("y" if u.attack_target != null and is_instance_valid(u.attack_target) else "-")])
	if _diag:
		print("    RIP halts=%d repaths=%d poses=%d" % [Unit.rip_halts, Unit.rip_repaths, Unit.rip_poses])
	print("  %s: худший отрыв от поста %.1f м, оторвавшихся (> %.1f) в пике %d из %d; на постах после ухода врага %d из %d" % [
		tag, worst, leash + SLACK, worst_cnt, men.size(), home, alive.size()])
	verdict("%s %s: никто не отрывается" % [tag, title], worst_cnt == 0,
		"худший %.1f м, в пике %d" % [worst, worst_cnt])
	if not march:
		verdict("%s %s: все вернулись на посты" % [tag, title], home >= alive.size() - 1,
			"%d из %d" % [home, alive.size()])
	_free(men)
	_free(foes)
	await pframes(10)
