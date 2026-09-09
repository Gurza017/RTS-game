extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЧЕСТНЫЙ A/B ЧЕРЕДОВАНИЕМ ПО tick_meter
## ═══════════════════════════════════════════════════════════════════════════
## ЗАЧЕМ. Правило проекта: правку меньше миллисекунды нельзя подтвердить ни
## разбивкой по веткам (у ветки, которая идёт тысячу раз в кадр, измеритель
## стоит соизмеримо с ней самой), ни вчерашними числами (уезжает база). Способ
## один — A/B ЧЕРЕДОВАНИЕМ: база и правка снимаются ПОДРЯД, в одном прогоне, на
## одной и той же живой сцене, и не по одному разу, а по нескольку — тогда
## дрейф машины попадает в обе выборки одинаково.
##
## ПОРЯДОК ФАЗ ВНУТРИ РАУНДА ПЕРЕВОРАЧИВАЕТСЯ. Сцена живёт: бойцы сходятся,
## отряды перестраиваются. Если база всегда идёт первой, весь дрейф сцены
## систематически достаётся правке — и замер начинает подсуживать. Чередование
## «база-правка / правка-база» этот перекос снимает.
##
## ТРИ БЛОКА:
##   A — стойка ЗАЩИТА, две стены в виду друг друга, по ним ещё не попали.
##       Худший случай для кэша «отряд в бою»: раннее окно «нас недавно задели»
##       (3 с) молчит, и без кэша платится полный обход состава на каждый вопрос;
##   B — та же сцена в стойке АТАКА, СПЛОШНАЯ РУБКА. Лучший случай для старого
##       кода: по отрядам попадают постоянно, окно не закрывается ни на кадр;
##   C — та же рубка, но мерится perf_config.batch_combat.
##
## В блоках B и C бойцы БЕССМЕРТНЫ. Иначе армия тает прямо во время замера, и
## поздние фазы идут на меньшем составе — то есть меряется убыль, а не правка.
##
## Запуск: godot --headless --path . res://qa_ab/Test.tscn

const _Opt := preload("res://scripts/perf_config.gd")

## Что именно переключаем в этом блоке
const KNOB_COMBAT_CACHE := 0
const KNOB_BATCH_COMBAT := 1
const KNOB_D1 := 7
const KNOB_PRESS := 8
const KNOB_AUTO := 9

## Сколько физических кадров держится одна фаза замера
const PHASE_FRAMES := 90
## Сколько пар фаз (база + правка) снимается
const ROUNDS := 6
## Кадры на прогрев после постановки войск: за это время отряды получают
## коридоры, ряды и разметку, и сцена перестаёт меняться
const WARMUP := 120
## Кадры на сход в рукопашную перед блоками B и C
const MELEE_WARMUP := 240

## Состав: сколько отрядов на сторону и по скольку в отряде
const SQUADS_PER_SIDE := 12
const MEN_PER_SQUAD := 60
const COLS := 12

var main = null
var _all: Array = []
## Снимок точек для блоков, где сцена обязана быть ОДИНАКОВОЙ в каждой фазе
var _snap: PackedVector3Array = PackedVector3Array()

## Запомнить, где все стоят сейчас
func _snapshot_positions() -> void:
	_snap.resize(_all.size())
	for i in range(_all.size()):
		var u = _all[i]
		_snap[i] = (u as Node3D).global_position if is_instance_valid(u) else Vector3.ZERO

## ── СЦЕНА ВОЗВРАЩАЕТСЯ В ИСХОДНОЕ ПЕРЕД КАЖДОЙ ФАЗОЙ ──────────────────────
## Нужно там, где мерится ФАЗА СБЛИЖЕНИЯ: за полторы секунды замера строй
## успевает пройти пару метров, и вторая фаза раунда стартовала бы с другой
## дистанции. Чередование порядка это сгладило бы, но не убрало; возврат в одну
## и ту же точку убирает совсем
func _restore_positions() -> void:
	for i in range(mini(_all.size(), _snap.size())):
		var u = _all[i]
		if not is_instance_valid(u):
			continue
		var uu := u as Unit
		uu.global_position = _snap[i]
		uu.sync_row()

func _ready() -> void:
	call_deferred("_run")

## physics_frame, а не process_frame (правило 11 проекта)
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _squad(scene: String, stat: String, fac: int, at: Vector3) -> Array:
	var sid: int = GameManager.new_squad(fac, stat)
	var men: Array = []
	for i in range(MEN_PER_SQUAD):
		var p := at + Vector3(float(i % COLS) * 0.6 - float(COLS) * 0.3,
			0.0, float(i / COLS) * 0.62)
		var u := _spawn(scene, fac, p)
		GameManager.add_to_squad(sid, u)
		men.append(u)
		_all.append(u)
	return men

func _set_knob(knob: int, on: bool) -> void:
	if knob == KNOB_BATCH_COMBAT:
		_Opt.batch_combat = on
	elif knob == KNOB_D1:
		_Opt.rear_press = on
		_Opt.approach_autopilot = on
	elif knob == KNOB_PRESS:
		_Opt.rear_press = on
	elif knob == KNOB_AUTO:
		_Opt.approach_autopilot = on
	else:
		_Opt.squad_combat_cache = on

## Средний тик за одну фазу, мс
func _measure(knob: int, on: bool, reset: bool = false) -> float:
	if reset:
		_restore_positions()
		await frames(2)
	_set_knob(knob, on)
	_Opt.tick_reset()
	_Opt.tick_meter = true
	await frames(PHASE_FRAMES)
	var ms: float = _Opt.tick_ms()
	_Opt.tick_meter = false
	return ms

func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())

func _live() -> int:
	var n := 0
	for u in _all:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _run() -> void:
	seed(7)
	Engine.max_fps = 0
	_Opt.sprite_lod = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(6)

	# ── ДВЕ СТЕНЫ В ВИДУ ДРУГ ДРУГА ────────────────────────────────────────
	# Разнос по Z подобран так, чтобы противник попадал в радиус внимания
	# (Unit.AGGRO_RADIUS = 10 м) и ход фаланги ЗАПУСКАЛСЯ, но контакта ещё не
	# было: тогда окно «нас недавно задели» молчит, и вопрос «отряд в бою»
	# идёт по дорогому пути — ровно то, что и надо померить
	var sp := "res://scenes/units/Spearman.tscn"
	for s in range(SQUADS_PER_SIDE):
		var x: float = float(s) * 9.0 - float(SQUADS_PER_SIDE) * 4.5
		var mine := _squad(sp, "spearman", Constants.FACTION_PLAYER, Vector3(x, 0.0, -4.0))
		var foes := _squad(sp, "spearman", Constants.FACTION_ENEMY, Vector3(x, 0.0, 4.0))
		for u in mine:
			(u as Unit).set_stance("defense")
		for u in foes:
			(u as Unit).set_stance("defense")
	await frames(WARMUP)

	print("\n=== A/B ЧЕРЕДОВАНИЕМ ===")
	print("  бойцов на поле: %d, отрядов: %d, фаза: %d кадров, раундов: %d"
		% [_live(), SQUADS_PER_SIDE * 2, PHASE_FRAMES, ROUNDS])
	print("  шардов тика: %d" % _Opt.shards_for(GameManager.active_units()))

	await _ab_block("A. КЭШ «ОТРЯД В БОЮ» — стойка ЗАЩИТА, по нам ещё не попали",
		KNOB_COMBAT_CACHE)

	# ── ПЕРЕВОДИМ В СПЛОШНУЮ РУБКУ ────────────────────────────────────────
	# БЕССМЕРТНЫМИ: иначе за двенадцать фаз замера армия выкосит сама себя, и
	# поздние фазы пойдут на меньшем составе — это мерило убыли, а не правки
	for u in _all:
		if is_instance_valid(u):
			var uu := u as Unit
			uu.max_health = 1e9
			uu.current_health = 1e9
			uu.set_stance("attack")
	await frames(MELEE_WARMUP)
	print("\n  (сплошная рубка, бойцы бессмертны, живых: %d)" % _live())

	await _ab_block("B. КЭШ «ОТРЯД В БОЮ» — та же сцена в рубке",
		KNOB_COMBAT_CACHE)
	await _ab_block("C. ПАКЕТНЫЙ ПРОХОД БОЯ (batch_combat) — в рубке",
		KNOB_BATCH_COMBAT)

	# ── ФАЗА СБЛИЖЕНИЯ: ТО, РАДИ ЧЕГО ПАКЕТНЫЙ БОЙ И ЗАВЕДЁН ──────────────
	# BatchCombat считает по колонкам шаг ПОДТЯГИВАНИЯ — то есть работает ровно
	# на тех, у кого цель ЕСТЬ, но до неё ещё не достать: окно от дальности
	# оружия до attack_range + PULL_UP_MAX, а это четырнадцать метров. В
	# сплошной рубке таких почти нет — все в контакте, и пакет всё равно отдаёт
	# их полному автомату. Судить механику только по рубке значило бы мерить её
	# на случае, для которого она не писана.
	# Разводим строй так, чтобы между передними шеренгами осталось около десяти
	# метров: авто-агро цель уже видит (AGGRO_RADIUS = 10), а дотянуться нельзя
	for u in _all:
		if not is_instance_valid(u):
			continue
		var uu := u as Unit
		var p := uu.global_position
		var away: float = -2.0 if uu.faction == Constants.FACTION_PLAYER else 2.0
		uu.global_position = Vector3(p.x, p.y, p.z + away)
		uu.sync_row()
	await frames(60)
	_snapshot_positions()
	await _ab_block("D. ПАКЕТНЫЙ ПРОХОД БОЯ (batch_combat) — фаза сближения",
		KNOB_BATCH_COMBAT, true)

	# ── E. ЭТАП D1 (напор + автопилот) НА ТОЙ ЖЕ ФАЗЕ СБЛИЖЕНИЯ ────────────
	# Ровно сцена, под которую D1 писан: цели видны, дотянуться нельзя — тыл
	# давит, дальние подходят. В сплошной рубке D1 замерен как ноль (все в
	# контакте, их накрывает дрёма) — судить его надо здесь
	await _ab_block("E. ЭТАП D1 (напор+автопилот) — фаза сближения",
		KNOB_D1, true)
	_Opt.rear_press = true
	_Opt.approach_autopilot = true
	# Вклад порознь: у напора и автопилота разные сцены и разные риски
	_Opt.approach_autopilot = false
	await _ab_block("E1. Только ТЫЛОВОЙ НАПОР — фаза сближения",
		KNOB_PRESS, true)
	_Opt.rear_press = false
	_Opt.approach_autopilot = false
	await _ab_block("E2. Только АВТОПИЛОТ — фаза сближения",
		KNOB_AUTO, true)
	_Opt.rear_press = true
	_Opt.approach_autopilot = true

	# Возвращаем ручки к значениям по умолчанию: стенд не вправе оставлять
	# после себя изменённый конфиг
	_Opt.squad_combat_cache = true
	_Opt.batch_combat = false
	print("\n=== AB TEST DONE ===")
	get_tree().quit(0)

## `reset` — возвращать сцену в исходное перед каждой фазой (фаза сближения)
func _ab_block(title: String, knob: int, reset: bool = false) -> void:
	print("\n─── %s ───" % title)
	var base_runs: Array = []
	var opt_runs: Array = []
	for r in range(ROUNDS):
		var b: float
		var o: float
		# ПОРЯДОК ФАЗ ПЕРЕВОРАЧИВАЕТСЯ ЧЕРЕЗ РАУНД (см. шапку стенда)
		if r % 2 == 0:
			b = await _measure(knob, false, reset)
			o = await _measure(knob, true, reset)
		else:
			o = await _measure(knob, true, reset)
			b = await _measure(knob, false, reset)
		base_runs.append(b)
		opt_runs.append(o)
		print("  раунд %d (%s):  выкл %.3f мс   вкл %.3f мс   разница %+.3f мс"
			% [r + 1, "выкл→вкл" if r % 2 == 0 else "вкл→выкл", b, o, o - b])
	var ab := _avg(base_runs)
	var ao := _avg(opt_runs)
	print("  СРЕДНЕЕ:  выкл %.3f мс   вкл %.3f мс" % [ab, ao])
	print("  ВЫИГРЫШ ОТ ВКЛЮЧЕНИЯ:  %.3f мс на физический тик (%.1f %%)"
		% [ab - ao, 0.0 if ab <= 0.0 else (ab - ao) / ab * 100.0])
