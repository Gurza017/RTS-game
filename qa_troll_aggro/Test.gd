extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: АГРО-ЦЕПОЧКА ЛОГОВА ТРОЛЛЕЙ И СКОРОСТЬ В БОЮ (заказ 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A СКОРОСТЬ — на патруле шаг из конфига, с целью ×TROLL_COMBAT_SPEED_MULT,
##     без цели снова обычный.
##   B СОЛИДАРНОСТЬ (спринт 20) — задели одного стража: дерётся только он,
##     из пня никто не выходит; задели двоих в TROLL_SOLIDARITY_SEC — все
##     тролли логова идут на обидчика.
##   C ПОВОДОК ПОГОНИ (спринт 20) — TROLL_CHASE_SEC без удара: цель брошена,
##     тролль возвращается к пню; агро только в TROLL_AGGRO_RADIUS.
##   D ЗАЧИСТКА — выбили всех: логово зачищено, бонусной пары нет.
## Запуск: godot --headless --path . res://qa_troll_aggro/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с"); _finish())

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
	print("\n═════ ИТОГ qa_troll_aggro: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn_squad(kind: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var men: Array = []
	var scene: PackedScene = Building.PRELOAD_SCENES[kind]
	for i in range(n):
		var u: Unit = scene.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var px: float = at.x + float(i % 6) * 0.7
		var pz: float = at.z + float(i / 6) * 0.7
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _alive_trolls(lair) -> Array:
	var out: Array = []
	for t in lair.get("trolls"):
		if t != null and is_instance_valid(t) and not (t as Unit).is_dead():
			out.append(t)
	return out

func _kill_all(lair) -> void:
	for t in _alive_trolls(lair):
		(t as Unit).take_damage(1.0e9)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	var lair = GameManager.troll_lair
	if lair == null or not is_instance_valid(lair):
		verdict("A0 логова нет", false)
		_finish()
		return
	var guards: Array = _alive_trolls(lair)
	if guards.is_empty():
		verdict("A0 стража нет", false)
		_finish()
		return
	var troll: Unit = guards[0]
	# Овцы не отвлекают: обед выключен на время стенда (голод далеко)
	troll.set("_hunger_t", 1.0e6)

	# ── A. Скорость ────────────────────────────────────────────────────────
	print("\n═════ A. СКОРОСТЬ В БОЮ ═════")
	var base_spd: float = _UCfg.stat("troll", "movement_speed", 0.0)
	await pframes(3)
	verdict("A1 на патруле шаг из конфига (%.2f)" % base_spd, is_equal_approx(troll.move_speed, base_spd),
		"move_speed %.2f" % troll.move_speed)
	var lp: Vector3 = (lair as Node3D).global_position
	var far: Array = _spawn_squad("spearman", lp + Vector3(40.0, 0.0, 0.0), 1)
	var bait: Unit = far[0]
	bait.set_tick(false)
	troll.command_attack(bait, true, true)
	await pframes(3)
	var want: float = base_spd * _GobCfg.TROLL_COMBAT_SPEED_MULT
	verdict("A2 с целью — ×%.1f (%.2f)" % [_GobCfg.TROLL_COMBAT_SPEED_MULT, want],
		is_equal_approx(troll.move_speed, want) and troll._base_speed() >= want - 0.01,
		"move_speed %.2f, кэш %.2f" % [troll.move_speed, troll._base_speed()])
	var p0: Vector3 = troll.global_position
	await pframes(60)
	var run: float = Vector2(troll.global_position.x - p0.x, troll.global_position.z - p0.z).length()
	verdict("A3 за секунду прошёл не меньше 0.8 × ускоренного шага", run >= want * 0.8,
		"прошёл %.2f м при шаге %.2f м/с" % [run, want])
	bait.take_damage(1.0e9)
	await pframes(3)
	troll.command_move(troll.global_position)
	await pframes(3)
	verdict("A4 цели нет — снова обычный шаг", is_equal_approx(troll.move_speed, base_spd),
		"move_speed %.2f" % troll.move_speed)

	# ── B. Солидарность стражей (спринт 20) ────────────────────────────────
	# Задели ОДНОГО — дерётся только он; задели ДВОИХ в TROLL_SOLIDARITY_SEC —
	# все тролли логова идут на обидчика. Помощников из пня по удару больше
	# не выходит (TROLL_AGGRO_HELPERS = 0)
	print("\n═════ B. СОЛИДАРНОСТЬ СТРАЖЕЙ ═════")
	lair.call("spawn_guards", 2)
	await pframes(2)
	var all_t: Array = _alive_trolls(lair)
	for t in all_t:
		(t as Unit).set("_hunger_t", 1.0e6)
		(t as Unit).command_move((t as Unit).global_position)
	await pframes(2)
	var n0: int = all_t.size()
	var hitters: Array = _spawn_squad("spearman", troll.global_position + Vector3(6.0, 0.0, 0.0), 2)
	for h in hitters:
		(h as Unit).set_tick(false)
	var hitter: Unit = hitters[0]
	troll.take_damage(50.0, hitter)
	await pframes(2)
	var after: Array = _alive_trolls(lair)
	verdict("B1 удар по одному стражу: из пня НИКТО не выходит (помощников %d)" % _GobCfg.TROLL_AGGRO_HELPERS,
		after.size() == n0 and _GobCfg.TROLL_AGGRO_HELPERS == 0,
		"было %d, стало %d" % [n0, after.size()])
	verdict("B2 ужаленный страж агрится на обидчика", troll.attack_target == hitter)
	var others_idle := 0
	var second: Unit = null
	for t in after:
		if t == troll:
			continue
		if second == null:
			second = t
		var tg = (t as Unit).attack_target
		if tg == null or not is_instance_valid(tg) or not (tg is Unit) \
				or (tg as Unit).squad_id != hitter.squad_id:
			others_idle += 1
	verdict("B3 остальные стражи в бой не рвутся (%d из %d без цели на обидчика)" % [others_idle, after.size() - 1],
		others_idle == after.size() - 1)
	# Второй удар — по ДРУГОМУ троллю в окне солидарности
	if second != null:
		second.take_damage(50.0, hitter)
	await pframes(2)
	var on_foe := 0
	for t in _alive_trolls(lair):
		var tg2 = (t as Unit).attack_target
		if tg2 != null and is_instance_valid(tg2) and tg2 is Unit and (tg2 as Unit).squad_id == hitter.squad_id:
			on_foe += 1
	verdict("B4 задели двоих — ВСЕ стражи логова идут на обидчика", on_foe == _alive_trolls(lair).size()
		and int(lair.get("solidarity_calls")) >= 1,
		"на обидчика %d из %d, вызовов %d" % [on_foe, _alive_trolls(lair).size(), int(lair.get("solidarity_calls"))])
	troll.take_damage(50.0, hitter)
	await pframes(2)
	verdict("B5 повторные удары никого не добавляют", _alive_trolls(lair).size() == after.size(),
		"троллей %d" % _alive_trolls(lair).size())

	# ── C. Поводок погони и малый радиус агро ──────────────────────────────
	print("\n═════ C. ПОВОДОК ПОГОНИ ═════")
	for t in _alive_trolls(lair):
		if t != troll:
			(t as Unit).set_tick(false)
	for h in hitters:
		(h as Unit).take_damage(1.0e9)
	await pframes(3)
	troll.command_move(troll.global_position)
	await pframes(3)
	# Недосягаемая приманка: бессмертный копейщик за TROLL_CHASE_SEC × скорость
	var far_bait: Array = _spawn_squad("spearman", troll.global_position + Vector3(60.0, 0.0, 0.0), 1)
	var fb: Unit = far_bait[0]
	fb.set_tick(false)
	troll.command_attack(fb, true, true)
	await pframes(30)
	verdict("C1 тролль гонится за целью", troll.attack_target == fb and troll.chase_left() < _GobCfg.TROLL_CHASE_SEC,
		"осталось %.1f с" % troll.chase_left())
	var lp2: Vector3 = (lair as Node3D).global_position
	await pframes(int(_GobCfg.TROLL_CHASE_SEC * 60.0) + 10)
	verdict("C2 через %.0f с без удара агро сброшено" % _GobCfg.TROLL_CHASE_SEC,
		troll.attack_target == null and troll.chase_resets == 1,
		"цель %s, сбросов %d" % [str(troll.attack_target), troll.chase_resets])
	var d_mid: float = Vector2(troll.global_position.x - lp2.x, troll.global_position.z - lp2.z).length()
	await pframes(90)
	var d_home: float = Vector2(troll.global_position.x - lp2.x, troll.global_position.z - lp2.z).length()
	verdict("C3 …и возвращается к пню (%.1f → %.1f м от пня)" % [d_mid, d_home], d_home < d_mid - 1.0)
	verdict("C4 приманка в 60 м агро не взводит (радиус %.0f м)" % _GobCfg.TROLL_AGGRO_RADIUS,
		troll.attack_target == null and troll.aggro_radius() == _GobCfg.TROLL_AGGRO_RADIUS)
	fb.take_damage(1.0e9)
	# Остывание после сброса (TROLL_CHASE_COOL_SEC) — тролль стоит и ждёт
	await pframes(int(troll.TROLL_CHASE_COOL_SEC * 60.0) + 10)
	troll.command_move(troll.global_position)
	await pframes(3)
	var near_bait: Array = _spawn_squad("spearman", troll.global_position + Vector3(_GobCfg.TROLL_AGGRO_RADIUS - 4.0, 0.0, 0.0), 1)
	var nb: Unit = near_bait[0]
	nb.set_tick(false)
	var got := false
	for _w in range(240):
		await get_tree().physics_frame
		if troll.attack_target == nb:
			got = true
			break
	verdict("C5 враг внутри радиуса агро — тролль берёт его сам", got)
	nb.take_damage(1.0e9)
	await pframes(3)

	# ── D. Зачистка ────────────────────────────────────────────────────────
	print("\n═════ D. ЗАЧИСТКА ═════")
	var rounds := 0
	while rounds < 5 and not _alive_trolls(lair).is_empty():
		rounds += 1
		_kill_all(lair)
		await pframes(3)
	verdict("D1 выбили всех — логово зачищено, бонусной пары нет (TROLL_AGGRO_BONUS %d)" % _GobCfg.TROLL_AGGRO_BONUS,
		GameManager.troll_lair_cleared() and _alive_trolls(lair).is_empty() and rounds == 1,
		"кругов %d, троллей %d" % [rounds, _alive_trolls(lair).size()])
	verdict("D2 стражей у пня не больше %d (спавн −20 %%)" % _GobCfg.TROLL_GUARDS_MAX,
		_GobCfg.TROLL_GUARDS_MAX == 2)
	_finish()
