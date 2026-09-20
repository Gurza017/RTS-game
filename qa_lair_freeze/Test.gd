extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_lair_freeze — ЗАМОРОЖЕННЫЙ ПЕНЬ ЗА РЕКОЙ (ТЗ 19.09.2026, блок 3.2)
## ═══════════════════════════════════════════════════════════════════════════
##   A — на старте пень на чужом берегу заморожен: ни тролля, ни гнолла, ни
##       овцы у него нет (0 нод), счётчики «всухую» = стартовым числам конфига;
##       пень своего берега («красный», у брода) — живой, не заморожен.
##   B — калькулятор: таймеры зовут те же spawn_*, при заморозке растут
##       счётчики с теми же потолками (стражи ≤ TROLL_GUARDS_MAX, овцы ≤ SHEEP_MAX).
##   C — разморозка: боец игрока перешёл брод — пень оттаивает ПОРЦИЯМИ (одна
##       порция за шаг: отара, затем по троллю, по стае, по отряду туш), нод
##       за один шаг прибавляется не больше одной порции; в конце frozen=false.
##   D — удар по замороженному пню тоже размораживает.
## Запуск: godot --headless --path . res://qa_lair_freeze/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const F := Constants.FACTION_PLAYER

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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
	print("\n═════ ИТОГ qa_lair_freeze: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

## Живые ноды у пня: тролли, гноллы, туши (юниты орды в LAIR_CLEAR) и овцы
func _nodes_near(lair: Node3D) -> Dictionary:
	var out := {"troll": 0, "gnoll": 0, "big_goblin": 0, "sheep": 0}
	var c: Vector3 = lair.global_position
	var r: float = _GobCfg.LAIR_CLEAR + 12.0
	for n in get_tree().get_nodes_in_group("goblin_units"):
		if n == null or not is_instance_valid(n) or not (n is Unit):
			continue
		var u := n as Unit
		if u.is_dead():
			continue
		if Vector2(u.global_position.x - c.x, u.global_position.z - c.z).length() > r:
			continue
		var k: String = u.stat_id
		if out.has(k):
			out[k] = int(out[k]) + 1
	for s in get_tree().get_nodes_in_group("sheep"):
		if s == null or not is_instance_valid(s) or not (s is Node3D):
			continue
		if Vector2((s as Node3D).global_position.x - c.x, (s as Node3D).global_position.z - c.z).length() <= r:
			out["sheep"] = int(out["sheep"]) + 1
	return out

func _sum(d: Dictionary) -> int:
	var s := 0
	for k in d:
		s += int(d[k])
	return s

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(10)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for k in ["goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(10)

	print("\n═════ A. СТАРТ: ПЕНЬ ЗА РЕКОЙ ЗАМОРОЖЕН ═════")
	var frozen_lair = null
	var live_lair = null
	for l in GameManager.troll_lairs:
		if l == null or not is_instance_valid(l):
			continue
		if bool(l.get("frozen")):
			frozen_lair = l
		else:
			live_lair = l
	verdict("A0 пней два: один заморожен, другой живой", frozen_lair != null and live_lair != null,
		"пней %d" % GameManager.troll_lairs.size())
	if frozen_lair == null or live_lair == null:
		_finish()
		return
	var home_side: int = int(main.river_side(main.PLAYER_BASE_ANCHOR))
	var fz_side: int = int(main.river_side(frozen_lair.global_position))
	var lv_side: int = int(main.river_side(live_lair.global_position))
	verdict("A1 заморожен именно пень на ЧУЖОМ берегу от базы игрока, живой — на своём",
		fz_side != 0 and fz_side != home_side and lv_side == home_side,
		"база %d, замороженный %d, живой %d" % [home_side, fz_side, lv_side])
	var near0: Dictionary = _nodes_near(frozen_lair)
	verdict("A2 у замороженного пня 0 нод: ни троллей, ни гноллов, ни туш, ни овец", _sum(near0) == 0, str(near0))
	verdict("A3 калькулятор: стражей %d, стай %d, овец %d — как стартовые числа конфига" % [
		_GobCfg.LAIR_START_TROLLS, _GobCfg.GNOLL_START_SQUADS, _GobCfg.SHEEP_START],
		int(frozen_lair.virt_trolls) == _GobCfg.LAIR_START_TROLLS
		and int(frozen_lair.virt_gnoll_squads) == _GobCfg.GNOLL_START_SQUADS
		and int(frozen_lair.virt_sheep) == _GobCfg.SHEEP_START,
		"virt: тролли %d, стаи %d, овцы %d, туши %d" % [int(frozen_lair.virt_trolls),
			int(frozen_lair.virt_gnoll_squads), int(frozen_lair.virt_sheep), int(frozen_lair.virt_big_squads)])
	var near_live: Dictionary = _nodes_near(live_lair)
	verdict("A4 живой пень родил стражей и стаю как обычно", int(near_live["troll"]) >= _GobCfg.LAIR_START_TROLLS
		and int(near_live["gnoll"]) > 0, str(near_live))

	print("\n═════ B. КАЛЬКУЛЯТОР ПОД ТАЙМЕРАМИ ═════")
	# Респавн стража «всухую»: потолок держится числом, а не нодами
	var vt0: int = int(frozen_lair.virt_trolls)
	for i in range(5):
		frozen_lair._on_troll_respawn()
	verdict("B1 респавн стражей всухую упирается в потолок %d (нод по-прежнему 0)" % _GobCfg.TROLL_GUARDS_MAX,
		int(frozen_lair.virt_trolls) == _GobCfg.TROLL_GUARDS_MAX and _sum(_nodes_near(frozen_lair)) == 0,
		"было %d, стало %d" % [vt0, int(frozen_lair.virt_trolls)])
	for i in range(6):
		frozen_lair.breed_sheep()
	verdict("B2 отара всухую растёт до потолка %d" % _GobCfg.SHEEP_MAX, int(frozen_lair.virt_sheep) == _GobCfg.SHEEP_MAX,
		"овец всухую %d" % int(frozen_lair.virt_sheep))
	var vg0: int = int(frozen_lair.virt_gnoll_squads)
	frozen_lair.spawn_gnoll_squads(2)
	verdict("B3 волна гноллов всухую: +2 стаи, нод 0", int(frozen_lair.virt_gnoll_squads) == vg0 + 2
		and _sum(_nodes_near(frozen_lair)) == 0, "стай %d" % int(frozen_lair.virt_gnoll_squads))
	var expect_portions: int = int(frozen_lair.virt_total())

	print("\n═════ C. РАЗМОРОЗКА ПОРЦИЯМИ ═════")
	# Боец игрока на берегу пня — за сухой кромкой русла
	var lp: Vector3 = frozen_lair.global_position
	var rx: float = float(main.river_x(lp.z))
	var side_sign: float = 1.0 if fz_side > 0 else -1.0
	var px: float = rx + side_sign * (float(main.RIVER_HALF_W) + float(main.RIVER_BANK) + _GobCfg.LAIR_THAW_BANK_MARGIN + 6.0)
	var sp: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
	sp.faction = F
	main.world_add(sp)
	sp.global_position = Vector3(px, GameManager.get_terrain_height(px, lp.z), lp.z)
	sp.sync_row()
	sp.set_tick(false)
	await pframes(2)
	verdict("C0 боец игрока на берегу пня виден (player_on_bank)", bool(main.player_on_bank(fz_side)))
	var thaws0: int = int(GameManager.lair_thaws)
	GameManager._lair_thaw_check()
	verdict("C1 обход разморозки поднял пень (thawing)", bool(frozen_lair.thawing) and GameManager.lair_thaws == thaws0 + 1,
		"thawing=%s" % str(frozen_lair.thawing))
	# Первая порция вышла сразу (отара)
	await pframes(3)
	var n1: Dictionary = _nodes_near(frozen_lair)
	verdict("C2 первая порция — отара: овец %d, прочих нод 0" % _GobCfg.SHEEP_MAX,
		int(n1["sheep"]) == _GobCfg.SHEEP_MAX and int(n1["troll"]) == 0 and int(n1["gnoll"]) == 0, str(n1))
	# Дальше — по одной порции на шаг (шаги двигаем сами, таймер по стене)
	var steps_ok := true
	var worst := ""
	var prev: Dictionary = n1
	var steps := 0
	for i in range(expect_portions + 2):
		if not bool(frozen_lair.thawing):
			break
		frozen_lair._thaw_step()
		steps += 1
		await pframes(3)
		var now: Dictionary = _nodes_near(frozen_lair)
		var dt: int = int(now["troll"]) - int(prev["troll"])
		var dg: int = int(now["gnoll"]) - int(prev["gnoll"])
		var db: int = int(now["big_goblin"]) - int(prev["big_goblin"])
		var gsz: int = int(_GobCfg.SQUAD_SIZE.get("gnoll", 12))
		var bsz: int = int(_GobCfg.SQUAD_SIZE.get("big_goblin", 5))
		# Одна порция: либо один тролль, либо одна стая, либо один отряд туш
		var portions: int = dt + int(dg / maxi(gsz, 1)) + int(db / maxi(bsz, 1))
		if portions > 1:
			steps_ok = false
			worst = "шаг %d: троллей +%d, гноллов +%d, туш +%d" % [steps, dt, dg, db]
		prev = now
	var fin: Dictionary = _nodes_near(frozen_lair)
	verdict("C3 каждый шаг выводит не больше ОДНОЙ порции", steps_ok, worst)
	verdict("C4 по окончании: тролли %d, стаи %d — все накопленные вышли, пень оттаял" % [
		_GobCfg.TROLL_GUARDS_MAX, vg0 + 2],
		not bool(frozen_lair.frozen) and not bool(frozen_lair.thawing)
		and int(fin["troll"]) == _GobCfg.TROLL_GUARDS_MAX
		and int(fin["gnoll"]) == (vg0 + 2) * int(_GobCfg.SQUAD_SIZE.get("gnoll", 12))
		and int(frozen_lair.virt_total()) == 0,
		"нод: %s; frozen=%s thawing=%s virt=%d, шагов %d" % [str(fin), str(frozen_lair.frozen), str(frozen_lair.thawing),
			int(frozen_lair.virt_total()), steps])
	# Оттаявший пень рождает как живой
	var vt_after: int = int(frozen_lair.virt_trolls)
	frozen_lair.spawn_guards(1)
	await pframes(2)
	verdict("C5 после разморозки спавн — нодами, а не всухую", int(frozen_lair.virt_trolls) == vt_after
		and int(_nodes_near(frozen_lair)["troll"]) == _GobCfg.TROLL_GUARDS_MAX + 1)

	print("\n═════ D. УДАР ПО ЗАМОРОЖЕННОМУ ПНЮ ═════")
	# Живой пень своего берега замораживаем руками и бьём
	live_lair.freeze()
	live_lair.spawn_gnoll_squads(1)
	var vg_live: int = int(live_lair.virt_gnoll_squads)
	var g_before: int = int(_nodes_near(live_lair)["gnoll"])
	live_lair.take_damage(10.0, sp)
	await pframes(3)
	# Одна порция всухую — первый же шаг разморозки её выводит, и пень оттаял
	var g_after: int = int(_nodes_near(live_lair)["gnoll"])
	verdict("D1 удар по замороженному пню начинает разморозку: стая вышла, пень оттаял",
		vg_live == 1 and g_after == g_before + int(_GobCfg.SQUAD_SIZE.get("gnoll", 12))
		and not bool(live_lair.frozen) and int(live_lair.virt_total()) == 0,
		"стай всухую было %d, гноллов %d → %d, frozen=%s" % [vg_live, g_before, g_after, str(live_lair.frozen)])
	_finish()
