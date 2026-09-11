extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: АГРО-ЦЕПОЧКА ЛОГОВА ТРОЛЛЕЙ И СКОРОСТЬ В БОЮ (заказ 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A СКОРОСТЬ — на патруле шаг из конфига, с целью ×TROLL_COMBAT_SPEED_MULT,
##     без цели снова обычный.
##   B АГРО-ВЫЗОВ — первый удар по стражу: он агрится на обидчика, из логова
##     сразу выходят TROLL_AGGRO_HELPERS с приказом на обидчика; второй удар
##     никого не добавляет.
##   C БОНУСНАЯ ПАРА — вся группа выбита → мгновенно ещё TROLL_AGGRO_BONUS,
##     логово НЕ считается зачищенным.
##   D СТАНДАРТ — у бонусной пары действует прежняя подмога на трети запаса
##     (один тролль), повторного агро-вызова нет; выбили всех — логово зачищено.
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

	# ── B. Агро-вызов ──────────────────────────────────────────────────────
	print("\n═════ B. АГРО-ВЫЗОВ ═════")
	var n0: int = _alive_trolls(lair).size()
	var hitters: Array = _spawn_squad("spearman", troll.global_position + Vector3(6.0, 0.0, 0.0), 2)
	for h in hitters:
		(h as Unit).set_tick(false)
	var hitter: Unit = hitters[0]
	troll.take_damage(50.0, hitter)
	await pframes(2)
	var after: Array = _alive_trolls(lair)
	verdict("B1 первый удар — из логова сразу вышли ещё %d тролля" % _GobCfg.TROLL_AGGRO_HELPERS,
		after.size() == n0 + _GobCfg.TROLL_AGGRO_HELPERS and int(lair.get("aggro_wave")) == 1,
		"было %d, стало %d, волна %d" % [n0, after.size(), int(lair.get("aggro_wave"))])
	verdict("B2 ужаленный страж агрится на обидчика", troll.attack_target == hitter)
	# Приказ атаки раздаётся ПО ОТРЯДУ обидчика (squad_pick_member выбирает
	# наименее обстрелянного) — считаем цели из его отряда
	var helpers_on_foe := 0
	for t in after:
		var tg = (t as Unit).attack_target
		if t != troll and tg != null and is_instance_valid(tg) and tg is Unit and (tg as Unit).squad_id == hitter.squad_id:
			helpers_on_foe += 1
	verdict("B3 помощники выходят с приказом на обидчика", helpers_on_foe == _GobCfg.TROLL_AGGRO_HELPERS,
		"на обидчика %d" % helpers_on_foe)
	troll.take_damage(50.0, hitter)
	(after[1] as Unit).take_damage(50.0, hitter)
	await pframes(2)
	verdict("B4 повторные удары по группе никого не добавляют",
		_alive_trolls(lair).size() == after.size(), "троллей %d" % _alive_trolls(lair).size())
	troll.current_health = troll.max_health * 0.2
	troll._soa_push_stats()
	troll.take_damage(10.0, hitter)
	await pframes(2)
	verdict("B5 у первой группы порог трети запаса подмогу не зовёт",
		_alive_trolls(lair).size() == after.size(), "троллей %d" % _alive_trolls(lair).size())

	# ── C. Бонусная пара ───────────────────────────────────────────────────
	print("\n═════ C. БОНУСНАЯ ПАРА ═════")
	var spawns_before: int = int(lair.get("aggro_spawns"))
	_kill_all(lair)
	await pframes(3)
	var bonus: Array = _alive_trolls(lair)
	verdict("C1 группа выбита — мгновенно вышли ещё %d тролля" % _GobCfg.TROLL_AGGRO_BONUS,
		bonus.size() == _GobCfg.TROLL_AGGRO_BONUS and int(lair.get("aggro_wave")) == 2
			and int(lair.get("aggro_spawns")) == spawns_before + _GobCfg.TROLL_AGGRO_BONUS,
		"троллей %d, волна %d" % [bonus.size(), int(lair.get("aggro_wave"))])
	verdict("C2 логово ещё не зачищено", not GameManager.troll_lair_cleared())
	var on_foe := 0
	for b in bonus:
		var tg2 = (b as Unit).attack_target
		if tg2 != null and is_instance_valid(tg2) and tg2 is Unit and (tg2 as Unit).squad_id == hitter.squad_id:
			on_foe += 1
	verdict("C3 бонусная пара идёт на последнего обидчика", on_foe == bonus.size(), "на обидчика %d" % on_foe)

	# ── D. Стандартный алгоритм и зачистка ─────────────────────────────────
	print("\n═════ D. СТАНДАРТ И ЗАЧИСТКА ═════")
	var b0: Unit = bonus[0]
	var n_before: int = _alive_trolls(lair).size()
	b0.take_damage(50.0, hitter)
	await pframes(2)
	verdict("D1 удар по бонусному троллю повторного агро-вызова не даёт",
		_alive_trolls(lair).size() == n_before, "троллей %d" % _alive_trolls(lair).size())
	b0.current_health = b0.max_health * (_GobCfg.TROLL_REINFORCE_AT + 0.02)
	b0._soa_push_stats()
	b0.take_damage(b0.max_health * 0.1, hitter)
	await pframes(3)
	verdict("D2 …а прежняя подмога на трети запаса у него действует (+%d)" % _GobCfg.TROLL_REINFORCE_COUNT,
		_alive_trolls(lair).size() == n_before + _GobCfg.TROLL_REINFORCE_COUNT,
		"троллей %d" % _alive_trolls(lair).size())
	var rounds := 0
	while rounds < 5 and not _alive_trolls(lair).is_empty():
		rounds += 1
		_kill_all(lair)
		await pframes(3)
	verdict("D3 выбили всех — логово зачищено, новых спавнов нет",
		GameManager.troll_lair_cleared() and _alive_trolls(lair).is_empty() and rounds <= 2,
		"кругов %d, троллей %d" % [rounds, _alive_trolls(lair).size()])
	_finish()
