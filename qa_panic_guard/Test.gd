extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_panic_guard — ПРЕДОХРАНИТЕЛЬ ПАНИКИ (срочный багфикс 19.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: на записи партии (08:47) отряд лучников впадает в панику ДО боя —
## без урона и без потерь. Причина: относительный порог («мораль вдвое ниже,
## чем у противника») считался, как только squad_in_combat отвечал «да», а тот
## отвечает «да» уже на ПРИКАЗ атаки; лучник с базой морали 45 против конницы
## на 100 срывался в первый же такт.
##   A — 30 лучников получают приказ атаки на конницу орды (мораль 100), никто
##       по ним не бьёт: паники нет 8 с, жребиев паники ноль, живых 30/30.
##   B — по лучникам бьют (урон без потерь): паники нет, жребиев ноль.
##   C — половина отряда выбита под ударами: паники всё ещё нет (порог —
##       критические потери PANIC_ALIVE_FRAC).
##   D — живых ≤ 30 %: жребий брошен; с шансом 0 паники нет, с шансом 1 —
##       паника на следующей же потере; без новой потери повторного жребия нет.
##   E — мораль, записанная в ноль, сама по себе отряд с полным составом не
##       срывает; вне боя она возвращается к базе.
## Запуск: godot --headless --path . res://qa_panic_guard/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN

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
	print("\n═════ ИТОГ qa_panic_guard: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var px: float = at.x + float(i % cols) * 0.6 - float(cols - 1) * 0.3
		var pz: float = at.z + float(i / cols) * 0.6
		var u: Unit = _spawn(kind, fac, Vector3(px, 0.0, pz))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _freeze(arr: Array) -> void:
	for u in arr:
		if is_instance_valid(u):
			(u as Unit).set_tick(false)

## Бессмертная мишень: стенд считает жребии СВОЕГО отряда, а выбитые
## лучниками всадники дали бы жребии чужого (первый прогон: «жребиев 4»)
func _immortal(arr: Array) -> void:
	for u in arr:
		if is_instance_valid(u):
			(u as Unit).max_health = 1.0e9
			(u as Unit).current_health = 1.0e9
			(u as Unit)._soa_push_stats()

func _rolls(sid: int) -> int:
	return int((GameManager.squads.get(sid, {}) as Dictionary).get("panic_rolls", 0))

## Ждать N секунд физкадров, следя за паникой; возвращает true, если сорвались
func _watch_panic(sid: int, sec: float) -> bool:
	for _f in range(int(sec * 60.0)):
		await get_tree().physics_frame
		if GameManager.squad_panicked(sid):
			return true
	return false

## Урон по k живым бойцам отряда от чужого бойца (отряд отмечается «нас бьют»)
func _hit(men: Array, k: int, dmg: float, who: Unit) -> void:
	var n := 0
	for u in _alive(men):
		if n >= k:
			break
		(u as Unit).take_damage(dmg, who)
		n += 1

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for k in ["goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	var base := Vector3(30.0, 0.0, -30.0)
	main._clear_area_of_resources(base, 60.0)

	print("\n═════ A. ПРИКАЗ АТАКИ БЕЗ УРОНА — ПАНИКИ НЕТ ═════")
	var arch: Array = _squad("archer", F, base, 30)
	var sid: int = int(arch[0])
	var men: Array = arch[1]
	# Конница орды — мораль 100 против базы лучника 45: прежний относительный
	# порог (0.45 < 1.0 × 0.5) срывал стрелков в первый же такт. Всадники
	# заморожены: они не должны ни бить, ни уезжать
	var cav: Array = _squad("goblin_rider", GF, base + Vector3(0.0, 0.0, 24.0), 10, 5)
	_freeze(cav[1])
	_immortal(cav[1])
	# Бьющий — замороженный бессмертный гоблин в стороне (лучники его не видят)
	var hit_sq: Array = _squad("goblin_spearman", GF, base + Vector3(-60.0, 0.0, 0.0), 3, 3)
	_freeze(hit_sq[1])
	_immortal(hit_sq[1])
	var hitter: Unit = hit_sq[1][0]
	await pframes(6)
	var m0: float = GameManager.squad_morale(sid)
	for u in men:
		(u as Unit).command_attack(cav[1][0], true, true, true)
	var in_combat_at_order: bool = GameManager.squad_in_combat(sid)
	var pan_a: bool = await _watch_panic(sid, 8.0)
	verdict("A1 отряд лучников с приказом на конницу (мораль 100) не паникует 8 с без урона",
		not pan_a, "мораль %.0f → %.0f, живых %d/30, in_combat по приказу %s" % [
			m0, GameManager.squad_morale(sid), _alive(men).size(), str(in_combat_at_order)])
	verdict("A2 жребиев паники не было", _rolls(sid) == 0,
		"жребиев %d" % _rolls(sid))
	verdict("A3 состав цел (100 % живых)", _alive(men).size() == 30,
		"живых %d" % _alive(men).size())

	print("\n═════ B. УРОН БЕЗ ПОТЕРЬ — ПАНИКИ НЕТ ═════")
	var pan_b := false
	for _s in range(4):
		_hit(men, 10, 8.0, hitter)
		if await _watch_panic(sid, 0.75):
			pan_b = true
			break
	verdict("B1 обстрел без потерь (30/30 живых, «нас бьют») паники не даёт",
		not pan_b, "мораль %.0f, живых %d, hit_recently %s" % [
			GameManager.squad_morale(sid), _alive(men).size(), str(GameManager.squad_hit_recently(sid))])
	verdict("B2 жребиев паники по-прежнему ноль", _rolls(sid) == 0,
		"жребиев %d" % _rolls(sid))

	print("\n═════ C. ПОЛОВИНА ВЫБИТА — ЕЩЁ ДЕРЖАТСЯ ═════")
	GameManager.panic_chance_override = 1.0
	# Выбиваем до 15 живых ударами чужого — «нас бьют» и потери есть
	var pan_c := false
	while _alive(men).size() > 15:
		_hit(men, 1, 1.0e12, hitter)
		if await _watch_panic(sid, 0.3):
			pan_c = true
			break
	if not pan_c:
		_hit(men, 5, 5.0, hitter)
		pan_c = await _watch_panic(sid, 2.0)
	var thr_n: int = int(floor(30.0 * _UCfg.PANIC_ALIVE_FRAC))
	verdict("C1 при 50 %% потерь (живых 15, порог %d) паники нет даже при шансе 1.0" % thr_n,
		not pan_c and _alive(men).size() == 15,
		"живых %d, мораль %.0f, жребиев %d" % [_alive(men).size(), GameManager.squad_morale(sid), _rolls(sid)])
	verdict("C2 жребий выше порога не бросается", _rolls(sid) == 0,
		"жребиев %d" % _rolls(sid))

	print("\n═════ D. КРИТИЧЕСКИЕ ПОТЕРИ — ЖРЕБИЙ ═════")
	GameManager.panic_chance_override = 0.0
	var pan_d := false
	while _alive(men).size() > thr_n:
		_hit(men, 1, 1.0e12, hitter)
		if await _watch_panic(sid, 0.3):
			pan_d = true
			break
	if not pan_d:
		pan_d = await _watch_panic(sid, 1.5)
	var rolls_d1: int = _rolls(sid)
	verdict("D1 живых %d (≤ %.0f %%): жребий брошен, с шансом 0 паники нет" % [_alive(men).size(), _UCfg.PANIC_ALIVE_FRAC * 100.0],
		not pan_d and rolls_d1 >= 1, "жребиев %d, живых %d" % [rolls_d1, _alive(men).size()])
	# Без новой потери повторного жребия нет (иначе шанс за секунду → 1)
	_hit(men, 3, 4.0, hitter)
	await pframes(90)
	verdict("D2 без новой потери жребий не повторяется (обстрел 1.5 с)",
		_rolls(sid) == rolls_d1, "жребиев было %d, стало %d" % [rolls_d1, _rolls(sid)])
	GameManager.panic_chance_override = 1.0
	_hit(men, 1, 1.0e12, hitter)
	var pan_d3: bool = await _watch_panic(sid, 1.5)
	verdict("D3 новая потеря ниже порога при шансе 1.0 — паника", pan_d3,
		"живых %d, жребиев %d, паника %s" % [_alive(men).size(), _rolls(sid), str(pan_d3)])
	var flag = (GameManager.squads[sid] as Dictionary).get("banner")
	verdict("D4 над сорвавшимся отрядом белый флаг",
		flag != null and is_instance_valid(flag) and bool(flag.shown_white))

	print("\n═════ E. МОРАЛЬ САМА ПО СЕБЕ — НЕ ТРИГГЕР ═════")
	GameManager.panic_chance_override = 1.0
	var sp: Array = _squad("spearman", F, base + Vector3(30.0, 0.0, 0.0), 24)
	var sid2: int = int(sp[0])
	await pframes(6)
	(GameManager.squads[sid2] as Dictionary)["morale"] = 1.0
	for u in sp[1]:
		(u as Unit).command_attack(cav[1][1], true, true, true)
	_hit(sp[1], 6, 6.0, hitter)
	var pan_e: bool = await _watch_panic(sid2, 4.0)
	verdict("E1 мораль 1/100 при полном составе под ударами — паники нет",
		not pan_e and _rolls(sid2) == 0,
		"мораль %.0f, жребиев %d" % [GameManager.squad_morale(sid2), _rolls(sid2)])
	# Вне боя (били больше окна назад) мораль возвращается к базе
	for u in sp[1]:
		(u as Unit).command_move((u as Unit).global_position + Vector3(0.0, 0.0, -1.0), false, Vector3.ZERO, false, true)
	await pframes(60 * 5)
	var base_m: float = GameManager._squad_base_morale(sid2)
	var m_e: float = GameManager.squad_morale(sid2)
	verdict("E2 вне боя мораль растёт к базе отряда (%.0f)" % base_m, m_e > 1.0 and m_e <= base_m + 0.01,
		"мораль %.0f" % m_e)
	GameManager.panic_chance_override = -1.0
	_finish()
