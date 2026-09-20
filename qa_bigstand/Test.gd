extends Node

## ═══════════════════════════════════════════════════════════════════════════
## BIGSTAND — qa_bigstand (16.09.2026): ~4000 бойцов, зонды по категориям
## ═══════════════════════════════════════════════════════════════════════════
## Заказ: критическое падение FPS в партии (22-27 в бою, 31-42 после боя) при
## ордах гноллов, свиноконнице, троллях, монахах и красном ИИ на карте. Стенд
## поднимает ЖИВУЮ сцену партии (Main: рельеф, река, туман, HUD) и ставит на
## правом берегу ~4000 бойцов трёх сторон:
##   игрок / красный ИИ — по 10 отрядов копейщиков, 8 лучников, 8 мечников,
##   6 монахов; орда — 8 отрядов гоблинов, 8 свиноконницы, 2 туш, 50 отрядов
##   гноллов при своём пне, 4 тролля.
## Фазы на одних и тех же бойцах:
##   IDLE_FAR    — все стоят, между сторонами 50+ м;
##   MARCH       — марш вбок туда-обратно (без контакта);
##   CLASH       — стенка на стенку, трёхсторонний замес (детальный профиль);
##   AFTER       — «стоп» всем где стоят: покой после боя, отряды перемешаны;
##   GNOLL_HEAP  — все гноллы сжаты в круг у пня, рядом два отряда копейщиков:
##                 кайт / фланг / патруль в плотной куче (детальный профиль).
## В каждой фазе: физтик армии (tick_meter), кадр логики (vis_meter), стенные
## интервалы кадра (худший / p95), FPS (только окно), вызовы отрисовки, число
## тел, сдвинутых расталкиванием за кадр (sep_meter), приказы движения в
## секунду ПО ИСТОЧНИКАМ (cmd_meter), сканы целей по местам вызова
## (scan_meter), навигация, время тика ПО СОСТОЯНИЯМ и по родам войск
## (class_meter), ветки профиля, сгруппированные по категориям заказа, и
## ЗОНД ДРОЖАНИЯ: сколько стоящих (IDLE) сдвинулось за полсекунды, сколько
## «идущих» (MOVING) не сдвинулось, сколько спит по картинке, сколько вне
## кадра / в тумане.
## Запуск: `godot --path . res://qa_bigstand/Test.tscn -- secs=20 cap=0 scale=1.0`
## Вердиктов нет — это измеритель («провалов: 0»). FPS честен только в окне.
##
## ── ЧЕСТНЫЙ РЕЖИМ ПО УМОЛЧАНИЮ (BigStand-5, этап 0) ─────────────────────
## `detail=0` (умолчание): profile_physics и class_meter ВЫКЛЮЧЕНЫ — они
## стоили 3.4-5.0 мс физтика на кадр (4-5 меток по ~1 мкс на тик бойца), и
## числа этапов 1-4 в docs/BIGSTAND_2026-09-16.md сняты с этой надбавкой.
## A/B, FPS и гейты снимать ТОЛЬКО так. `detail=1` — прежний разбор по веткам
## и родам войск (ранжирование, не бюджет). В обоих режимах печатаются: стена
## среднего кадра и её раскладка (физтик + логика + хвост физики + прочий
## _process + рендер/движок), распределение кадров (≤16.7 / ≤33.3 / дольше,
## p50/p95/p99), GC (КБ/кадр, сборки gen0/1/2), стрелы (выстрелов, в полёте,
## торчащих, пул), ВЕДОМЫЕ ЯДРОМ (автопилот, напор, матрица, дрёма, сон
## физики; сколько строк ядро оставило себе — ArmyCore.TickSkipped) и, по
## ручке `sephist=1`, гистограмма соседей расталкивания (снимок середины
## фазы: 7000 вызовов через границу — один тяжёлый кадр, в FPS-прогоне не
## включать). В headless стена среднего кадра не опускается ниже 16.7 мс
## (физшаг ждёт реального времени) — «прочее» читать только там, где она
## больше 16.7.

const _Opt := preload("res://scripts/perf_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Lair := preload("res://scripts/goblin/TrollLair.gd")

var CLASH_SEC := 20.0
var IDLE_SEC := 6.0
var MARCH_SEC := 10.0
var AFTER_SEC := 8.0
var HEAP_SEC := 10.0
var CAP_FPS := 0
var SCALE := 1.0
## 0 — честный режим (профиль и class_meter выключены), 1 — разбор по веткам
var DETAIL := 0
## 1 — снимок гистограммы соседей расталкивания в середине каждой фазы
var SEPHIST := 0
## Площадка — правый берег, между плато (70,-80), деревней (162,-91) и пнём
## партии (105, 85)
const CX := 115.0
const CZ := 2.0
const CLEAR_R := 120.0
## Ширина ряда орды по x (ряды от CX − W/2 до CX + W/2; правее — диск гноллов)
const HORDE_ROW_W := 100.0
const WARM := 90
## Окно зонда дрожания, физкадров (0.5 с)
const JIT_FRAMES := 30
## Порог «стоящий сдвинулся» за окно и «идущий не сдвинулся»
const JIT_IDLE_MOVE := 0.03
const JIT_MOVING_STUCK := 0.20

var main = null
var _p_sq: Array = []     # [[men, sid, uid], ...]
var _r_sq: Array = []
var _g_sq: Array = []
var _gn_sq: Array = []    # гноллы отдельно (фаза кучи)
var _p_all: Array = []
var _r_all: Array = []
var _g_all: Array = []
var _all: Array = []
var _trolls: Array = []
var _lair = null
var _knobs: Dictionary = {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(a).split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"secs": CLASH_SEC = float(kv[1])
			"idle": IDLE_SEC = float(kv[1])
			"march": MARCH_SEC = float(kv[1])
			"after": AFTER_SEC = float(kv[1])
			"heap": HEAP_SEC = float(kv[1])
			"cap": CAP_FPS = int(kv[1])
			"scale": SCALE = maxf(float(kv[1]), 0.1)
			"detail": DETAIL = int(kv[1])
			"sephist": SEPHIST = int(kv[1])
			"knob":
				var nv: PackedStringArray = kv[1].split(":")
				if nv.size() == 2:
					_knobs[nv[0]] = nv[1]
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		get_tree().quit())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = _g(at)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Прямоугольный блок: cols колонок, интервал gap; at — центр ПЕРВОЙ шеренги
func _squad(uid: String, fac: int, at: Vector3, n: int, cols: int, gap: float) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	for i in range(n):
		var p := at + Vector3((float(i % cols) - float(cols - 1) * 0.5) * gap, 0.0, float(i / cols) * gap)
		var u := _spawn(uid, fac, p)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [men, sid, uid]

## Толпа орды по спирали (как spawn_goblin_squad)
func _horde(uid: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_GOBLIN, uid)
	var men: Array = []
	for k in range(n):
		var ho: Vector2 = _GobCfg.horde_offset(k, n, sid)
		var u := _spawn(uid, Constants.FACTION_GOBLIN, at + Vector3(ho.x, 0.0, ho.y))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [men, sid, uid]

func _alive(list: Array) -> int:
	var n := 0
	for u in list:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _nearest_live(from: Vector3, list: Array) -> Unit:
	var best: Unit = null
	var bd := INF
	for u in list:
		if u == null or not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var d: float = from.distance_to((u as Unit).global_position)
		if d < bd:
			bd = d
			best = u
	return best

func _stop_all(list: Array) -> void:
	for u in list:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).command_move((u as Unit).global_position)

func _order_attack(squads: Array, foes: Array) -> void:
	for sq in squads:
		var men: Array = sq[0]
		if men.is_empty():
			continue
		var c: Vector2 = GameManager.squad_centre_xz(int(sq[1]))
		var first: Unit = _nearest_live(Vector3(c.x, 0.0, c.y) if c.x != INF else Vector3.ZERO, men)
		if first == null:
			continue
		var from := Vector3(c.x, 0.0, c.y) if c.x != INF else first.global_position
		var t: Unit = _nearest_live(from, foes)
		if t == null:
			continue
		for u in men:
			if is_instance_valid(u) and not (u as Unit).is_dead():
				(u as Unit).command_attack(t, true, false, false)

## Марш всей стороны на вектор d (каждый — из своей точки, строй цел)
func _march(list: Array, d: Vector3, player: bool) -> void:
	for u in list:
		if u == null or not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var p: Vector3 = (u as Unit).global_position
		if player:
			(u as Unit).command_move(Vector3(p.x + d.x, 0.0, p.z + d.z), false, Vector3.ZERO, false, true)
		else:
			(u as Unit).command_move(Vector3(p.x + d.x, 0.0, p.z + d.z))

## Переставить всех по раскладке: люди в два ряда на своих z, орда на своих
func _place(z_p: float, z_r: float, z_g: float) -> void:
	_place_side(_p_sq, z_p, -1.0)
	_place_side(_r_sq, z_r, 1.0)
	# Орда: толпы по своим центрам, рядами внутри карты (ряд шире
	# HORDE_ROW_W переносится ниже; первый прогон уводил хвост ряда за
	# край карты, и зажим границы давал ложное «дрожание» всадников)
	var x := CX - HORDE_ROW_W * 0.5
	var zr := z_g
	for sq in _g_sq:
		var men: Array = sq[0]
		var n: int = men.size()
		var rmax: float = sqrt(float(n) / PI) * _GobCfg.HORDE_SPOT + 1.0
		if x + rmax * 2.0 > CX + HORDE_ROW_W * 0.5:
			x = CX - HORDE_ROW_W * 0.5
			zr += 17.0
		var cxg: float = x + rmax
		for k in range(n):
			if not is_instance_valid(men[k]):
				continue
			var u := men[k] as Unit
			if u.is_dead():
				continue
			var ho: Vector2 = _GobCfg.horde_offset(k, n, int(sq[1]))
			u.global_position = _g(Vector3(cxg + ho.x, 0.0, zr + ho.y))
			u.sync_row()
			u.post_pos = u.global_position
		x += rmax * 2.0 + 2.0
	# Гноллы — при своём пне, отрядами по кольцу вокруг него (как их
	# выпускает сам пень): зона, патруль, фланг, кайт — как в партии
	_place_gnolls(_GobCfg.GNOLL_PATROL_RADIUS * 0.85, 1.0)

## Отряды гноллов — по диску вокруг пня (смещённому от базы людей, чтобы
## лежать внутри зоны GnollAI), внутри отряда — толпа; spread — сжатие толпы
func _place_gnolls(disc_r: float, spread: float) -> void:
	var lp: Vector3 = _lair.global_position
	var centre: Vector3 = lp + Vector3(10.0, 0.0, 0.0)
	var m: int = _gn_sq.size()
	for si in range(m):
		var sq: Array = _gn_sq[si]
		var men: Array = sq[0]
		var n: int = men.size()
		var a: float = float(si) * 2.399963
		var r: float = disc_r * sqrt((float(si) + 0.5) / float(maxi(m, 1)))
		var c: Vector3 = centre + Vector3(cos(a) * r, 0.0, sin(a) * r)
		for k in range(n):
			if not is_instance_valid(men[k]):
				continue
			var u := men[k] as Unit
			if u.is_dead():
				continue
			var ho: Vector2 = _GobCfg.horde_offset(k, n, int(sq[1])) * spread
			u.global_position = _g(Vector3(c.x + ho.x, 0.0, c.z + ho.y))
			u.sync_row()
			u.post_pos = u.global_position
			u.set("lair", _lair)
			u.set("home_pos", lp)

## Люди: копейщики первым рядом, лучники и мечники вторым, монахи за ними.
## dirz = -1: второй ряд ДАЛЬШЕ от центра (z меньше); +1 — наоборот
func _place_side(sqs: Array, z0: float, dirz: float) -> void:
	var x1 := CX - 62.0
	var x2 := CX - 62.0
	var xm := CX - 20.0
	for sq in sqs:
		var men: Array = sq[0]
		var uid: String = String(sq[2])
		var cols: int
		var gap: float
		var z: float
		match uid:
			"spearman":
				cols = 12; gap = 0.7
				z = z0
			"monk":
				cols = 1; gap = 1.0
				z = z0 + dirz * 22.0
			_:
				cols = 8; gap = 0.75
				z = z0 + dirz * 11.0
		var x: float
		if uid == "spearman":
			x = x1
		elif uid == "monk":
			x = xm
		else:
			x = x2
		for i in range(men.size()):
			if not is_instance_valid(men[i]):
				continue
			var u := men[i] as Unit
			if u.is_dead():
				continue
			var p := Vector3(x + float(i % cols) * gap, 0.0, z + dirz * float(i / cols) * gap)
			u.global_position = _g(p)
			u.sync_row()
			u.post_pos = u.global_position
		if uid == "spearman":
			x1 += float(cols) * gap + 3.5
		elif uid == "monk":
			xm += 4.0
		else:
			x2 += float(cols) * gap + 2.5

func _run() -> void:
	seed(7)
	Engine.max_fps = CAP_FPS
	if not DisplayServer.get_name().begins_with("headless"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var opt_inst = _Opt.new()
	for k in _knobs:
		var v: String = String(_knobs[k])
		var cur: Variant = opt_inst.get(k)
		if cur == null:
			print("  ручки %s в perf_config нет" % k)
			continue
		if cur is bool:
			opt_inst.set(k, v == "1" or v == "true")
		elif cur is int:
			opt_inst.set(k, int(v))
		elif cur is float:
			opt_inst.set(k, float(v))
		else:
			opt_inst.set(k, v)
		print("  ручка %s = %s" % [k, str(opt_inst.get(k))])
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(8)
	# ИИ всех сторон молчат: фазы задаёт стенд, а не мышление ИИ
	for nm in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var ai = main.get(nm)
		if ai != null and is_instance_valid(ai) and ai is Node:
			(ai as Node).set_process(false)
			(ai as Node).set_physics_process(false)
	await pframes(4)
	# Стартовых бойцов партии — прочь (рабочие, орда, охрана, стражи пней)
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	# Площадка чистится от леса; сухость и обрывы — по факту
	var centre := Vector3(CX, 0.0, CZ)
	main._clear_area_of_resources(centre, CLEAR_R)
	var wet := 0
	var cliff := 0
	var probes := 0
	for ix in range(-70, 91, 5):
		for iz in range(-50, 121, 5):
			probes += 1
			if GameManager.is_water(CX + float(ix), CZ + float(iz)):
				wet += 1
			if GameManager.is_cliff(CX + float(ix), CZ + float(iz)):
				cliff += 1
	print("  площадка (%.0f, %.0f) [-70,90]×[-50,120]: проб %d, воды %d, обрывов %d" % [CX, CZ, probes, wet, cliff])
	# Камера — на центр замеса и замерзает (край-панорама в headless уводит
	# фокус); точку обзора ставим сами, чтобы LOD и туман работали как в партии
	main.focus_camera_on(centre)
	if main._camera != null:
		main._camera._update_position()
		main._camera.set_process(false)
	GameManager.update_view_point(centre, 110.0, 0.5)
	var pf: int = Constants.FACTION_PLAYER
	var rf: int = Constants.FACTION_ENEMY
	var gf: int = Constants.FACTION_GOBLIN
	GameManager.pop_limit_enabled = false
	for fac in [pf, rf]:
		GameManager.finish_research(fac, _Forge.node_id("archer", "1d"))
		GameManager.finish_research(fac, _Forge.node_id("spearman", "1d"))
		GameManager.finish_research(fac, _Forge.node_id("monk", "2d"))
		GameManager.finish_research(fac, _Forge.node_id("monk", "3d"))
	var n_sp: int = _UCfg.squad_size("spearman")
	var n_ar: int = _UCfg.squad_size("archer")
	var n_wr: int = _UCfg.squad_size("warrior")
	var k_sp: int = maxi(int(round(10.0 * SCALE)), 1)
	var k_ar: int = maxi(int(round(8.0 * SCALE)), 1)
	var k_wr: int = maxi(int(round(8.0 * SCALE)), 1)
	var k_mk: int = maxi(int(round(6.0 * SCALE)), 1)
	# ── ЛЮДИ: игрок и красный ИИ (одинаковый состав) ──────────────────────
	for side in [[pf, _p_sq], [rf, _r_sq]]:
		var fac: int = side[0]
		var out: Array = side[1]
		for k in range(k_sp):
			out.append(_squad("spearman", fac, Vector3(CX - 60.0 + float(k) * 12.0, 0.0, -300.0 - 20.0 * float(fac)), n_sp, 12, 0.7))
		for k in range(k_ar):
			out.append(_squad("archer", fac, Vector3(CX - 60.0 + float(k) * 9.0, 0.0, -310.0 - 20.0 * float(fac)), n_ar, 8, 0.75))
		for k in range(k_wr):
			out.append(_squad("warrior", fac, Vector3(CX - 60.0 + float(k) * 9.0, 0.0, -315.0 - 20.0 * float(fac)), n_wr, 8, 0.75))
		for k in range(k_mk):
			var msq: Array = _squad("monk", fac, Vector3(CX - 20.0 + float(k) * 4.0, 0.0, -320.0 - 20.0 * float(fac)), 1, 1, 1.0)
			out.append(msq)
			var b: Dictionary = GameManager.squads[int(msq[1])]["bonuses"]
			b["aura_armor"] = 1.0
			b["aura_attack"] = 1.0
			b["aura_rate"] = 0.08
	for sq in _p_sq:
		_p_all.append_array(sq[0])
	for sq in _r_sq:
		_r_all.append_array(sq[0])
	# ── ОРДА ──────────────────────────────────────────────────────────────
	var gs: Dictionary = _GobCfg.SQUAD_SIZE
	var k_gb: int = maxi(int(round(10.0 * SCALE)), 1)
	var k_rd: int = maxi(int(round(8.0 * SCALE)), 1)
	var k_bg: int = maxi(int(round(2.0 * SCALE)), 1)
	var k_gn: int = maxi(int(round(25.0 * SCALE)), 1)
	var k_tr: int = maxi(int(round(4.0 * SCALE)), 1)
	for k in range(k_gb):
		_g_sq.append(_horde("goblin_spearman", Vector3(CX - 60.0 + float(k) * 16.0, 0.0, -360.0), int(gs["goblin_spearman"])))
	for k in range(k_rd):
		_g_sq.append(_horde("goblin_rider", Vector3(CX - 60.0 + float(k) * 14.0, 0.0, -380.0), int(gs["goblin_rider"])))
	for k in range(k_bg):
		_g_sq.append(_horde("big_goblin", Vector3(CX + 40.0 + float(k) * 10.0, 0.0, -380.0), int(gs["big_goblin"])))
	_lair = _Lair.new()
	_lair.faction = gf
	main.world_add(_lair)
	_lair.global_position = _g(Vector3(CX + 57.0, 0.0, CZ + 96.0))
	await pframes(4)
	# Стая и стражи пня ПАРТИИ, рождённые самим пнём, — прочь: состав задаёт стенд
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and not _p_all.has(n) and not _r_all.has(n):
			var own := false
			for sq in _g_sq:
				if (sq[0] as Array).has(n):
					own = true
					break
			if not own:
				(n as Unit).take_damage(1.0e12)
	await pframes(4)
	for k in range(k_gn):
		_gn_sq.append(_horde("gnoll", Vector3(CX - 60.0 + float(k % 10) * 12.0, 0.0, -400.0 - float(k / 10) * 8.0), int(gs["gnoll"])))
	_trolls = _lair.spawn_guards(k_tr)
	for t in _trolls:
		(t as Node).set("home_pos", Vector3.INF)
	for sq in _gn_sq:
		for g in sq[0]:
			(g as Node).set("lair", _lair)
			(g as Node).set("home_pos", _lair.global_position)
	var _gn_all: Array = []
	for sq in _g_sq:
		_g_all.append_array(sq[0])
	for sq in _gn_sq:
		_gn_all.append_array(sq[0])
	_g_all.append_array(_trolls)
	# Орда без гноллов маршем ходит; гноллы зону пня не покидают
	var _g_march: Array = _g_all.duplicate()
	_g_all.append_array(_gn_all)
	_all = _p_all + _r_all + _g_all
	await pframes(6)
	print("  сцена: игрок %d (отрядов %d), красный ИИ %d (%d), орда %d (отрядов %d + гноллов %d отр. + %d тролля); всего %d  (стенные часы %d с)" % [
		_alive(_p_all), _p_sq.size(), _alive(_r_all), _r_sq.size(), _alive(_g_all), _g_sq.size(), _gn_sq.size(), _trolls.size(), _alive(_all), Time.get_ticks_msec() / 1000])
	var headless: bool = DisplayServer.get_name() == "headless"
	# ── ФАЗА IDLE_FAR ───────────────────────────────────────────────────
	_place(CZ - 32.0, CZ + 16.0, CZ + 70.0)
	await pframes(4)
	_stop_all(_all)
	await pframes(WARM)
	var r_idle: Dictionary = await _measure("IDLE_FAR (стоят, 50+ м)", IDLE_SEC, headless, true)
	# ── ФАЗА MARCH: вбок туда и обратно, без контакта ───────────────────
	var legs: int = 2
	var leg_sec: float = MARCH_SEC / float(legs)
	var r_march: Dictionary = {}
	_march(_p_all, Vector3(14.0, 0.0, 0.0), true)
	_march(_r_all, Vector3(-14.0, 0.0, 0.0), false)
	_march(_g_march, Vector3(-14.0, 0.0, 0.0), false)
	await pframes(WARM / 2)
	r_march = await _measure("MARCH (марш вбок, без контакта)", leg_sec, headless, true)
	_march(_p_all, Vector3(-14.0, 0.0, 0.0), true)
	_march(_r_all, Vector3(14.0, 0.0, 0.0), false)
	_march(_g_march, Vector3(14.0, 0.0, 0.0), false)
	await pframes(WARM / 2)
	var r_march2: Dictionary = await _measure("MARCH (обратно)", leg_sec, headless, false)
	_stop_all(_all)
	# ── ФАЗА CLASH: стенка на стенку, три стороны ───────────────────────
	_place(CZ - 14.0, CZ + 2.0, CZ + 34.0)
	await pframes(4)
	for sq in _p_sq:
		if String(sq[2]) == "spearman" and _p_sq.find(sq) % 2 == 0:
			for u in sq[0]:
				if is_instance_valid(u):
					(u as Unit).set_stance("defense")
	# Два отряда копейщиков и два лучников красного ИИ — к пню гноллов, на
	# край их диска: гноллы дерутся только в своей зоне, к ним приходят
	var to_gnolls: Array = []
	var got := {"spearman": 0, "archer": 0}
	for sq in _r_sq:
		var uid: String = String(sq[2])
		if got.has(uid) and int(got[uid]) < 2 and _alive(sq[0]) > 10:
			got[uid] = int(got[uid]) + 1
			to_gnolls.append(sq)
	var lp0: Vector3 = _lair.global_position
	var gx := lp0.x - 30.0
	for sq in to_gnolls:
		var men: Array = sq[0]
		var i := 0
		var cols: int = 12 if String(sq[2]) == "spearman" else 8
		for m in men:
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u.is_dead():
				continue
			u.global_position = _g(Vector3(gx - float(i / cols) * 0.7, 0.0, lp0.z - 8.0 + float(i % cols) * 0.7))
			u.sync_row()
			u.post_pos = u.global_position
			i += 1
		gx -= 6.0 if cols == 12 else 5.0
	var others_r: Array = []
	for sq in _r_sq:
		if not to_gnolls.has(sq):
			others_r.append(sq)
	_order_attack(_p_sq, _r_all + _g_march)
	_order_attack(others_r, _p_all + _g_march)
	_order_attack(to_gnolls, _gn_all)
	_order_attack(_g_sq, _r_all + _p_all)
	for t in _trolls:
		var foe: Unit = _nearest_live((t as Unit).global_position, _r_all + _p_all)
		if foe != null:
			(t as Unit).command_attack(foe, true, true, false)
	await pframes(WARM)
	var r_clash: Dictionary = await _measure("CLASH (замес трёх сторон)", CLASH_SEC, headless, true)
	# ── ФАЗА AFTER: стоп всем где стоят — покой после боя ───────────────
	_stop_all(_all)
	await pframes(WARM)
	var r_after: Dictionary = await _measure("AFTER (стоп после боя, отряды перемешаны)", AFTER_SEC, headless, true)
	# ── ФАЗА GNOLL_HEAP: гноллы сжаты у пня, рядом копейщики ────────────
	var lp: Vector3 = _lair.global_position
	var gn_alive := 0
	for sq in _gn_sq:
		gn_alive += _alive(sq[0])
	# Куча: диск на всех живых гноллов при 0.9 м на гнолла (плотнее HORDE_SPOT)
	var heap_r: float = maxf(sqrt(float(gn_alive) / PI) * 0.9, 6.0)
	_place_gnolls(heap_r * 0.8, 0.55)
	for sq in _gn_sq:
		for g in sq[0]:
			if is_instance_valid(g) and not (g as Unit).is_dead():
				(g as Unit).command_move((g as Unit).global_position)
	# Два живых отряда копейщиков игрока — в 6 м от края кучи, приказ атаки
	var spear_sq: Array = []
	for sq in _p_sq:
		if String(sq[2]) == "spearman" and _alive(sq[0]) > 20:
			spear_sq.append(sq)
		if spear_sq.size() >= 2:
			break
	var sx := lp.x + 10.0 - heap_r - 14.0
	for sq in spear_sq:
		var men: Array = sq[0]
		var i := 0
		for m in men:
			if m == null or not is_instance_valid(m):
				continue
			var u := m as Unit
			if u.is_dead():
				continue
			u.global_position = _g(Vector3(sx - float(i / 12) * 0.7, 0.0, lp.z - 6.0 + float(i % 12) * 0.7))
			u.sync_row()
			u.post_pos = u.global_position
			i += 1
		sx -= 12.0
	await pframes(4)
	_order_attack(spear_sq, _gn_all)
	await pframes(WARM / 2)
	var r_heap: Dictionary = await _measure("GNOLL_HEAP (куча гноллов у пня + копейщики)", HEAP_SEC, headless, true)
	_summary([r_idle, r_march, r_march2, r_clash, r_after, r_heap], headless)
	get_tree().quit()

## ── ЗОНД ДРОЖАНИЯ: снимок всей армии раз в JIT_FRAMES физкадров ──────────
## Считает по живым: состояние, сдвиг за окно, признаки сна/отрисовки
func _jitter_sample(prev: Dictionary, acc: Dictionary) -> Dictionary:
	var cur: Dictionary = {}
	var idle := 0
	var idle_jit := 0
	var idle_walk := 0
	var moving := 0
	var moving_stuck := 0
	var attacking := 0
	var sleeping := 0
	var draw_off := 0
	var unseen := 0
	var fogged := 0
	var settled := 0
	var snoozing := 0
	var autop := 0
	var rearp := 0
	var matrixd := 0
	var physasleep := 0
	var tickoff := 0
	var by_class: Dictionary = acc.get("by_class", {})
	for raw in _all:
		if raw == null or not is_instance_valid(raw):
			continue
		var u := raw as Unit
		if u == null or u.is_dead():
			continue
		var p: Vector3 = u.position if u._local_xform else u.global_position
		var id: int = u.get_instance_id()
		cur[id] = p
		var moved: float = -1.0
		var pv: Variant = prev.get(id)
		if pv != null:
			var q: Vector3 = pv
			moved = Vector2(p.x - q.x, p.z - q.z).length()
		var cls: String = u.stat_id
		var row: Variant = by_class.get(cls)
		if row == null:
			row = {"n": 0, "idle": 0, "idle_jit": 0, "idle_walk": 0, "moving": 0, "moving_stuck": 0, "attacking": 0, "sleep": 0, "jit_sum": 0.0}
			by_class[cls] = row
		var rc: Dictionary = row
		rc["n"] = int(rc["n"]) + 1
		match u.state:
			Unit.State.IDLE:
				idle += 1
				rc["idle"] = int(rc["idle"]) + 1
				if moved > JIT_IDLE_MOVE:
					idle_jit += 1
					rc["idle_jit"] = int(rc["idle_jit"]) + 1
					rc["jit_sum"] = float(rc["jit_sum"]) + moved
				if u._mv_moving:
					idle_walk += 1
					rc["idle_walk"] = int(rc["idle_walk"]) + 1
			Unit.State.MOVING:
				moving += 1
				rc["moving"] = int(rc["moving"]) + 1
				if moved >= 0.0 and moved < JIT_MOVING_STUCK:
					moving_stuck += 1
					rc["moving_stuck"] = int(rc["moving_stuck"]) + 1
			Unit.State.ATTACKING:
				attacking += 1
				rc["attacking"] = int(rc["attacking"]) + 1
				if u._atk_snooze:
					snoozing += 1
		if u._auto_pilot: autop += 1
		if u._rear_press: rearp += 1
		if u._matrix_driven: matrixd += 1
		if u._phys_asleep: physasleep += 1
		if not u.tick_on: tickoff += 1
		if u._proc_sleeping:
			sleeping += 1
			rc["sleep"] = int(rc["sleep"]) + 1
		if not u.draw_on:
			draw_off += 1
		if not u._seen:
			unseen += 1
		if not u._far_registered:
			fogged += 1
		if u._settled:
			settled += 1
	acc["samples"] = int(acc.get("samples", 0)) + 1
	for k in ["idle", "idle_jit", "idle_walk", "moving", "moving_stuck", "attacking", "sleeping", "draw_off", "unseen", "fogged", "settled", "snoozing"]:
		pass
	acc["idle"] = int(acc.get("idle", 0)) + idle
	acc["idle_jit"] = int(acc.get("idle_jit", 0)) + idle_jit
	acc["idle_walk"] = int(acc.get("idle_walk", 0)) + idle_walk
	acc["moving"] = int(acc.get("moving", 0)) + moving
	acc["moving_stuck"] = int(acc.get("moving_stuck", 0)) + moving_stuck
	acc["attacking"] = int(acc.get("attacking", 0)) + attacking
	acc["sleeping"] = int(acc.get("sleeping", 0)) + sleeping
	acc["draw_off"] = int(acc.get("draw_off", 0)) + draw_off
	acc["unseen"] = int(acc.get("unseen", 0)) + unseen
	acc["fogged"] = int(acc.get("fogged", 0)) + fogged
	acc["settled"] = int(acc.get("settled", 0)) + settled
	acc["snoozing"] = int(acc.get("snoozing", 0)) + snoozing
	acc["autop"] = int(acc.get("autop", 0)) + autop
	acc["rearp"] = int(acc.get("rearp", 0)) + rearp
	acc["matrixd"] = int(acc.get("matrixd", 0)) + matrixd
	acc["physasleep"] = int(acc.get("physasleep", 0)) + physasleep
	acc["tickoff"] = int(acc.get("tickoff", 0)) + tickoff
	acc["by_class"] = by_class
	return cur

## Снимок смыкания: у скольких отрядов есть разметка и сколько бойцов
## отстоят от своего поста дальше REFORM_DRIFT (те, кого сведёт _sweep_reform)
func _reform_diag() -> Dictionary:
	var with_slots := 0
	var drifted := 0
	var squads_drift := 0
	# Разбивка дрейфующих отрядов ПО ПРИЧИНЕ, по которой обход их не сводит:
	# в бою (окно «нас били»), большинство идёт, откат после неудачного
	# смыкания, и СВОБОДНЫЕ — те, кого обход обязан свести и не свёл
	var in_combat := 0
	var on_move := 0
	var backoff := 0
	var free_drift := 0
	var now: int = Time.get_ticks_msec()
	for key in GameManager.squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = GameManager.squads[key]
		var slots: Array = sq.get("slots", [])
		if slots.is_empty():
			continue
		with_slots += 1
		var d := 0
		var live := 0
		var moving := 0
		var fighting := 0
		for m in sq.get("members", []):
			if m == null or not is_instance_valid(m):
				continue
			var u := m as Unit
			if u == null or u.is_dead():
				continue
			live += 1
			if u.state == Unit.State.MOVING:
				moving += 1
			elif u.state == Unit.State.ATTACKING or u.attack_target != null:
				fighting += 1
			if not u._post_valid:
				continue
			var up: Vector3 = u.position if u._local_xform else u.global_position
			if Vector2(up.x - u.post_pos.x, up.z - u.post_pos.z).length() > GameManager.REFORM_DRIFT:
				d += 1
		if d > 0:
			squads_drift += 1
			drifted += d
			if GameManager.squad_in_combat(sid) or fighting > 0:
				in_combat += 1
			elif moving * 2 > live:
				on_move += 1
			elif now < int(sq.get("reform_next_ms", 0)):
				backoff += 1
			else:
				free_drift += 1
	return {"with_slots": with_slots, "squads_drift": squads_drift, "drifted": drifted, "total": GameManager.squads.size(),
		"in_combat": in_combat, "on_move": on_move, "backoff": backoff, "free": free_drift}

## Гистограмма соседей расталкивания по живым строкам (BigStand-5, этап 0):
## соседей в радиусе скана (личная норма × SEP_CROSS_SQUAD у отрядных) и
## внутри порога толчка (норма − мёртвая зона). Дорогой снимок — по ручке
func _sep_hist() -> Dictionary:
	var army = GameManager.army
	var rows := 0
	var scan := 0
	var push := 0
	var push_rows := 0
	var lonely := 0
	var gt6 := 0
	var gt6_push := 0
	var hist: Array = [0, 0, 0, 0, 0]
	var base: float = Unit.SEP_MIN_DIST
	var dz: float = Unit.SEP_DEADZONE
	for raw in _all:
		if raw == null or not is_instance_valid(raw):
			continue
		var u := raw as Unit
		if u == null or u.is_dead() or u._soa < 0:
			continue
		var p: Vector3 = u.position if u._local_xform else u.global_position
		var own: float = army.get_sep_radius(u._soa)
		var my: float = own if own > 0.0 else base
		var cross: float = my * Unit.SEP_CROSS_SQUAD if u.squad_id != 0 else my
		var n_scan: int = army.allies_count_near(u._soa, p.x, p.z, cross, 200)
		var n_push: int = army.allies_count_near(u._soa, p.x, p.z, maxf(my - dz, 0.0), 200)
		rows += 1
		scan += n_scan
		push += n_push
		if n_push > 0: push_rows += 1
		if n_scan == 0: lonely += 1
		elif n_scan <= 3: hist[1] += 1
		elif n_scan <= 6: hist[2] += 1
		elif n_scan <= 12: hist[3] += 1
		else: hist[4] += 1
		if n_scan > 6:
			gt6 += 1
			gt6_push += n_push
	hist[0] = lonely
	return {"rows": rows, "scan": scan, "push": push, "push_rows": push_rows, "lonely": lonely, "hist": hist, "gt6": gt6, "gt6_push": gt6_push}

## Один замер фазы: секунды по физкадрам. detail — классы, состояния, ветки
func _measure(label: String, secs: float, headless: bool, detail0: bool = false) -> Dictionary:
	# Разбор по веткам — только по ручке detail=1: профиль сам стоит 3-5 мс
	var detail: bool = detail0 and DETAIL == 1
	_Opt.tick_meter = true; _Opt.tick_reset()
	_Opt.vis_meter = true; _Opt.vis_reset()
	_Opt.class_meter = detail; _Opt.class_reset()
	_Opt.profile_physics = detail; _Opt.prof_reset()
	_Opt.sep_meter = true; _Opt.sep_reset()
	_Opt.cmd_meter = true; _Opt.cmd_reset()
	_Opt.scan_meter = true; _Opt.scan_reset()
	_Opt.sys_meter = true; _Opt.sys_reset()
	var frames_total: int = int(secs * 60.0)
	var fps_min := 1.0e9
	var fps_sum := 0.0
	var fps_n := 0
	var wall_prev: int = Time.get_ticks_usec()
	var walls: PackedFloat32Array = PackedFloat32Array()
	var phys_all: PackedFloat32Array = PackedFloat32Array()
	var proc_all: PackedFloat32Array = PackedFloat32Array()
	var draw_peak := 0
	var gc_alloc0: int = GameManager.army.gc_allocated()
	var obj0: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var alive0: int = _alive(_all)
	var spikes: Array = []
	var tick_prev: int = _Opt._tick_usec
	var vis_prev: int = _Opt._vis_usec
	var prof_prev: Dictionary = _Opt._prof_usec.duplicate() if detail else {}
	var nav_prev: int = _Opt.nav_usec
	var nav0: int = _Opt.nav_usec
	var navc0: int = _Opt.nav_calls
	var navf0: int = GameManager.nav_routes_failed
	var navmk0: int = GameManager.nav_miss_key
	var navmr0: int = GameManager.nav_miss_reuse
	var navu0: int = GameManager.army.nav_unreach() if GameManager.army != null else 0
	GameManager.nav_worst_usec = 0
	var jit_prev: Dictionary = {}
	var jit: Dictionary = {}
	var arrows_sum := 0
	var fired0: int = GameManager.arrows_fired
	var stuck_max := 0
	var sephist: Dictionary = {}
	var gc0_0: int = GameManager.army.gc_count(0)
	var gc0_1: int = GameManager.army.gc_count(1)
	var gc0_2: int = GameManager.army.gc_count(2)
	var skipped_sum := 0
	var listed_sum := 0
	# ── СБОРКИ GEN2 ПО КАДРАМ (BigStand-5, этап 4) ────────────────────────
	# Кадр, в котором число сборок gen2 выросло: стена кадра, пауза сборки
	# (GC.GetGCMemoryInfo), куча до/после, LOH — чтобы назвать причину числом
	var gen2_log: Array = []
	var gen2_prev: int = GameManager.army.gc_count(2)
	var gen1_prev: int = GameManager.army.gc_count(1)
	var gc_frames: Array = []
	for f in range(frames_total):
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		var wall_ms: float = float(now - wall_prev) * 0.001
		walls.append(wall_ms)
		wall_prev = now
		var g2: int = GameManager.army.gc_count(2)
		var g1: int = GameManager.army.gc_count(1)
		if g2 != gen2_prev or g1 != gen1_prev:
			var gi: PackedFloat64Array = GameManager.army.gc_info()
			gc_frames.append([f, wall_ms, int(gi[0]), gi[2], gi[3], gi[6], gi[7], gi[9], int(gi[11]), int(gi[10]), gi[5], gi[14],
				gi[15], gi[16], gi[17], int(gi[18]), int(gi[19])])
			if g2 != gen2_prev:
				gen2_log.append(f)
			gen2_prev = g2
			gen1_prev = g1
		var t_ms: float = float(_Opt._tick_usec - tick_prev) * 0.001
		var v_ms: float = float(_Opt._vis_usec - vis_prev) * 0.001
		tick_prev = _Opt._tick_usec
		vis_prev = _Opt._vis_usec
		var branches: Array = []
		if detail:
			var nav_d: int = _Opt.nav_usec - nav_prev
			nav_prev = _Opt.nav_usec
			if nav_d > 300:
				branches.append(["nav_route", float(nav_d) * 0.001])
			var cur: Dictionary = _Opt._prof_usec.duplicate()
			for kb in cur:
				var d_us: int = int(cur[kb]) - int(prof_prev.get(kb, 0))
				if d_us > 300:
					branches.append([String(kb), float(d_us) * 0.001])
			branches.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
			prof_prev = cur
		if f >= 5:
			spikes.append([wall_ms, t_ms, v_ms, f, branches.slice(0, 6)])
		phys_all.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		proc_all.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		var fps: float = float(Performance.get_monitor(Performance.TIME_FPS))
		if not headless and fps > 0.0:
			fps_min = minf(fps_min, fps)
			fps_sum += fps
			fps_n += 1
		draw_peak = maxi(draw_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		arrows_sum += GameManager.army.arrow_flights()
		stuck_max = maxi(stuck_max, GameManager.stuck_arrow_count())
		skipped_sum += GameManager.army.tick_skipped()
		listed_sum += GameManager.army.tick_listed()
		if SEPHIST == 1 and f == frames_total / 2:
			sephist = _sep_hist()
		if f % JIT_FRAMES == JIT_FRAMES - 1:
			jit_prev = _jitter_sample(jit_prev, jit)
	var r := {}
	r["label"] = label
	r["frames"] = frames_total
	r["tick"] = _Opt.tick_ms()
	r["vis"] = _Opt.vis_ms()
	r["fps_min"] = fps_min if fps_n > 0 else 0.0
	r["fps_avg"] = (fps_sum / float(fps_n)) if fps_n > 0 else 0.0
	r["wall_worst"] = _max(walls)
	r["wall_p95"] = _pct(walls, 0.95)
	r["wall_avg"] = _avg(walls)
	r["phys_p95"] = _pct(phys_all, 0.95)
	r["proc_p95"] = _pct(proc_all, 0.95)
	r["phys_avg"] = _avg(phys_all)
	r["proc_avg"] = _avg(proc_all)
	r["wall_p50"] = _pct(walls, 0.50)
	r["wall_p99"] = _pct(walls, 0.99)
	var b16 := 0
	var b33 := 0
	var bover := 0
	for w in walls:
		if w <= 16.7: b16 += 1
		elif w <= 33.4: b33 += 1
		else: bover += 1
	r["buckets"] = [b16, b33, bover]
	r["fired"] = GameManager.arrows_fired - fired0
	r["stuck_max"] = stuck_max
	r["pool"] = GameManager.arrow_pool_size()
	r["sephist"] = sephist
	r["gc"] = [GameManager.army.gc_count(0) - gc0_0, GameManager.army.gc_count(1) - gc0_1, GameManager.army.gc_count(2) - gc0_2]
	r["core_skipped"] = float(skipped_sum) / float(frames_total)
	r["core_listed"] = float(listed_sum) / float(frames_total)
	r["draw"] = draw_peak
	r["gc_kb_frame"] = float(GameManager.army.gc_allocated() - gc_alloc0) / 1024.0 / float(frames_total)
	r["gc_frames"] = gc_frames
	r["gc_mode"] = GameManager.army.gc_info()
	r["obj_delta"] = int(Performance.get_monitor(Performance.OBJECT_COUNT)) - obj0
	r["alive0"] = alive0
	r["alive1"] = _alive(_all)
	r["sep_per_frame"] = float(_Opt.sep_moved) / float(maxi(_Opt.sep_frames, 1))
	r["cmd_per_sec"] = float(_Opt.cmd_total) / secs
	r["cmd"] = _Opt.cmd_report()
	r["cmd_sids"] = _Opt.cmd_sid_report()
	r["reform"] = _reform_diag()
	r["scan_per_sec"] = float(_Opt.scan_calls) / secs
	r["scan"] = _Opt.scan_report()
	r["sys"] = _Opt.sys_report()
	r["sys_frames"] = frames_total
	_Opt.sys_meter = false
	r["nav_ms_frame"] = float(_Opt.nav_usec - nav0) / 1000.0 / float(frames_total)
	r["nav_calls"] = _Opt.nav_calls - navc0
	r["nav_failed"] = GameManager.nav_routes_failed - navf0
	r["nav_unreach"] = (GameManager.army.nav_unreach() if GameManager.army != null else 0) - navu0
	r["nav_worst_ms"] = float(GameManager.nav_worst_usec) / 1000.0
	r["nav_miss_key"] = GameManager.nav_miss_key - navmk0
	r["nav_miss_reuse"] = GameManager.nav_miss_reuse - navmr0
	r["arrows_avg"] = float(arrows_sum) / float(frames_total)
	r["shards"] = _Opt.shards_for(GameManager.active_units())
	r["jit"] = jit
	spikes.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	r["spikes"] = spikes.slice(0, 4)
	if detail:
		r["classes"] = _Opt.class_report()
		r["states"] = _Opt.state_report()
		r["prof"] = _Opt.prof_report()
	_Opt.class_meter = false
	_Opt.profile_physics = false
	_Opt.sep_meter = false
	_Opt.cmd_meter = false
	_Opt.scan_meter = false
	print("  [%s] физтик %.2f мс, кадр логики %.2f мс, физкадр p95 %.1f / худший %.1f мс, живых %d → %d, расталк. %.0f тел/кадр, приказов %.0f/с, сканов %.0f/с, шардов %d  (стенные часы %d с)" % [
		label, r["tick"], r["vis"], r["wall_p95"], r["wall_worst"], alive0, r["alive1"], r["sep_per_frame"], r["cmd_per_sec"], r["scan_per_sec"], r["shards"], Time.get_ticks_msec() / 1000])
	return r

func _max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a: m = maxf(m, v)
	return m
func _avg(a: PackedFloat32Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for v in a: s += v
	return s / float(a.size())
func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty(): return 0.0
	var s: Array = Array(a)
	s.sort()
	return float(s[int(float(s.size() - 1) * q)])

func _class_label(id: String) -> String:
	match id:
		"archer": return "Лучники"
		"spearman": return "Копейщики"
		"warrior": return "Мечники"
		"monk": return "Монахи"
		"goblin_spearman": return "Гоблины"
		"goblin_rider": return "Свиноконница"
		"big_goblin": return "Большие гоблины"
		"gnoll": return "Гноллы"
		"troll": return "Тролли"
	return id

func _state_label(s: int) -> String:
	match s:
		Unit.State.IDLE: return "IDLE"
		Unit.State.MOVING: return "MOVING"
		Unit.State.ATTACKING: return "ATTACKING"
		Unit.State.DEAD: return "DEAD"
	return str(s)

## Категории заказа: куда относится ветка профиля. Ветки с точкой в скобках —
## ПОДветки (внутри process_move / process_attack), их не суммируем дважды
const CAT := {
	"sep_overlap": "Физика/расталкивание", "batch_move": "Физика/расталкивание",
	"pose_flush": "Физика/расталкивание", "grid_rebuild": "Физика/расталкивание",
	"grid_update": "Физика/расталкивание", "rear_press": "Физика/расталкивание",
	"squad_matrix": "Физика/расталкивание", "rear_step": "Физика/расталкивание",
	"mb_trunk": "Навигация/обход", "mb_water": "Навигация/обход", "mb_enemyblock": "Навигация/обход",
	"mb_commit": "Навигация/обход", "nav_route": "Навигация/обход",
	"check_auto_aggro": "Скан целей/зрение", "atk_find_enemy": "Скан целей/зрение",
	"mv_intercept": "Скан целей/зрение", "squad_corridor": "Скан целей/зрение",
	"squad_radar": "Скан целей/зрение", "squad_melee": "Скан целей/зрение",
	"rank_recompute": "Скан целей/зрение", "cor_enemy": "Скан целей/зрение",
	"process_move": "FSM/микро-шаги", "process_attack": "FSM/микро-шаги",
	"phalanx_advance": "FSM/микро-шаги", "atk_snooze": "FSM/микро-шаги",
	"batch_combat": "FSM/микро-шаги", "tick_tail": "FSM/микро-шаги",
	"mv_speed": "FSM/микро-шаги", "matrix_skip": "FSM/микро-шаги", "rear_press_skip": "FSM/микро-шаги",
	"atk_strike": "Бой/урон", "atk_damage": "Бой/урон", "squad_volley": "Бой/урон",
	"die_signal": "Бой/урон", "die_rest": "Бой/урон", "die_credit": "Бой/урон", "die_corpse": "Бой/урон",
	"vis_row": "Отрисовка/анимация", "vis_fog": "Отрисовка/анимация", "vis_walk": "Отрисовка/анимация",
	"vis_pose": "Отрисовка/анимация", "vis_far": "Отрисовка/анимация", "vis_core": "Отрисовка/анимация",
	"arrow_core": "Отрисовка/анимация", "draw_decals": "Отрисовка/анимация", "draw_flush": "Отрисовка/анимация",
	"draw_orders": "Отрисовка/анимация", "draw_banners": "Отрисовка/анимация",
}
## Подветки: лежат внутри родителя, в сумму категорий по верхнему уровню не идут
const SUB := ["mv_intercept", "mv_speed", "mb_trunk", "mb_water", "mb_enemyblock", "mb_commit",
	"atk_find_enemy", "atk_strike", "atk_damage", "cor_harvest", "cor_bounds", "cor_trunk",
	"cor_enemy", "cor_push", "cor_ranks", "cor_cohesion", "tail_wake", "tail_reform",
	"tail_phalanx", "tail_morale", "tail_food_audio", "melee_calc", "monk_pulse", "monk_res",
	"monk_raise", "monk_pick", "monk_walk", "monk_find_corpse", "monk_build_vfx", "rank_allies",
	"rank_enemypos", "die_signal", "die_rest", "die_credit", "die_corpse"]

func _summary(rs: Array, headless: bool) -> void:
	print("\n📊 **BIGSTAND (qa_bigstand)** — сцена %s, режим %s; живых на старте %d" % [
		"headless (FPS не показателен)" if headless else "окно",
		"ЧЕСТНЫЙ (профиль выключен)" if DETAIL == 0 else "детальный (с профилем, физтик завышен на 3-5 мс)",
		int(rs[0]["alive0"])])
	print("| Фаза | физтик армии | кадр логики | физкадр p95 / худший | TIME_PHYS p95 | TIME_PROC p95 | FPS мин / ср | вызовов отрисовки | расталк. тел/кадр | приказов/с | сканов/с | нав. мс/кадр | стрел в полёте | шардов | живых |")
	print("| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	for r in rs:
		var d: Dictionary = r
		print("| %s | %.2f мс | %.2f мс | %.1f / %.1f мс | %.1f мс | %.1f мс | %s | %d | %.0f | %.0f | %.0f | %.3f | %.0f | %d | %d → %d |" % [
			String(d["label"]), float(d["tick"]), float(d["vis"]), float(d["wall_p95"]), float(d["wall_worst"]),
			float(d["phys_p95"]), float(d["proc_p95"]),
			("%.0f / %.0f" % [float(d["fps_min"]), float(d["fps_avg"])]) if not headless else "—",
			int(d["draw"]), float(d["sep_per_frame"]), float(d["cmd_per_sec"]), float(d["scan_per_sec"]),
			float(d["nav_ms_frame"]), float(d["arrows_avg"]), int(d["shards"]), int(d["alive0"]), int(d["alive1"])])
	for r in rs:
		var d: Dictionary = r
		print("\n═══ %s ═══" % String(d["label"]))
		# Дрожание
		var j: Dictionary = d["jit"]
		var ns: float = float(maxi(int(j.get("samples", 0)), 1))
		print("  ДРОЖАНИЕ (среднее по %d снимкам раз в %.1f с): IDLE %.0f, из них сдвинулись > %.0f см %.0f, с анимацией ходьбы %.0f; MOVING %.0f, из них на месте (< %.2f м за окно) %.0f; ATTACKING %.0f (дремлют %.0f); спят по картинке %.0f, картинка выключена %.0f, вне LOD %.0f, скрыты туманом/сняты с отрисовки %.0f, якорь settled %.0f" % [
			int(ns), float(JIT_FRAMES) / 60.0, float(j.get("idle", 0)) / ns, JIT_IDLE_MOVE * 100.0, float(j.get("idle_jit", 0)) / ns,
			float(j.get("idle_walk", 0)) / ns, float(j.get("moving", 0)) / ns, JIT_MOVING_STUCK, float(j.get("moving_stuck", 0)) / ns,
			float(j.get("attacking", 0)) / ns, float(j.get("snoozing", 0)) / ns, float(j.get("sleeping", 0)) / ns,
			float(j.get("draw_off", 0)) / ns, float(j.get("unseen", 0)) / ns, float(j.get("fogged", 0)) / ns, float(j.get("settled", 0)) / ns])
		print("  ВЕДОМЫЕ ЯДРОМ (ср. по снимкам): автопилот %.0f, тыловой напор %.0f, матрица %.0f, дремлют %.0f, спят по физике %.0f, тик выключен %.0f; ядро оставило себе %.0f строк/кадр, в GDScript-тик ушло %.0f строк/кадр" % [
			float(j.get("autop", 0)) / ns, float(j.get("rearp", 0)) / ns, float(j.get("matrixd", 0)) / ns, float(j.get("snoozing", 0)) / ns,
			float(j.get("physasleep", 0)) / ns, float(j.get("tickoff", 0)) / ns, float(d["core_skipped"]), float(d["core_listed"])])
		# Раскладка кадра: физтик армии + логика армии + всё остальное (хвост
		# физшага, прочий _process, рендер, движок, а в лёгких фазах headless —
		# простой до следующего физшага). Мониторы Performance.TIME_* при снятом
		# ограничении кадров усредняются по кадрам отрисовки и для раскладки не
		# годятся (CLAUDE.md, «Разбор кадра»), поэтому здесь их нет
		var wall: float = float(d["wall_avg"])
		var tick: float = float(d["tick"])
		var vis: float = float(d["vis"])
		print("  КАДР: стена ср. %.2f мс (p50 %.1f, p95 %.1f, p99 %.1f, худший %.1f) = физтик армии %.2f + логика армии %.2f + рендер/движок/прочее %.2f; кадров <=16.7 мс %d, <=33.4 мс %d, дольше %d" % [
			wall, float(d["wall_p50"]), float(d["wall_p95"]), float(d["wall_p99"]), float(d["wall_worst"]),
			tick, vis, maxf(wall - tick - vis, 0.0),
			int(d["buckets"][0]), int(d["buckets"][1]), int(d["buckets"][2])])
		print("  GC: %.1f КБ/кадр, сборок gen0/1/2 %s, OBJECT_COUNT %+d; СТРЕЛЫ: выстрелов %d (%.1f/с), в полёте ср. %.0f, торчащих макс %d, пул %d" % [
			float(d["gc_kb_frame"]), str(d["gc"]), int(d["obj_delta"]),
			int(d["fired"]), float(int(d["fired"])) / (float(int(d["frames"])) / 60.0), float(d["arrows_avg"]), int(d["stuck_max"]), int(d["pool"])])
		var gm: PackedFloat64Array = d["gc_mode"]
		var lat_names := ["Batch", "Interactive", "LowLatency", "SustainedLowLatency", "NoGCRegion"]
		print("  GC-РЕЖИМ: задержка %s, серверный %s, куча %.1f МБ (gen0 %.1f, gen1 %.1f, gen2 %.1f, LOH %.1f, POH %.1f), фрагментация %.1f МБ" % [
			lat_names[clampi(int(gm[12]), 0, 4)], str(int(gm[13]) == 1), gm[3], gm[4], gm[5], gm[6], gm[7], gm[8], gm[14]])
		for gf in d["gc_frames"]:
			print("    сборка gen%d в кадре %d: стена кадра %.1f мс, пауза GC %.2f мс, куча %.1f МБ (gen1 %.1f, gen2 %.1f, LOH %.1f, фрагм. %.1f), продвинуто %.2f МБ, фоновая %s, уплотняющая %s" % [
				int(gf[2]), int(gf[0]), float(gf[1]), float(gf[3]), float(gf[4]), float(gf[10]), float(gf[5]), float(gf[6]), float(gf[11]), float(gf[7]), str(int(gf[8]) == 1), str(int(gf[9]) == 1)])
			print("        до сборки: gen0 %.1f, gen1 %.1f, gen2 %.1f МБ; ждущих финализации %d, закреплённых %d" % [
				float(gf[12]), float(gf[13]), float(gf[14]), int(gf[15]), int(gf[16])])
		var sh: Dictionary = d["sephist"]
		if not sh.is_empty():
			print("  РАСТАЛКИВАНИЕ (снимок середины фазы): строк %d; соседей в радиусе скана %d (ср. %.1f/строку), внутри порога толчка %d (ср. %.2f); строк с толчком %d; без соседей %d; гистограмма 0/1-3/4-6/7-12/13+ = %s; строк с >6 соседями %d (толчков у них %d)" % [
				int(sh["rows"]), int(sh["scan"]), float(sh["scan"]) / float(maxi(int(sh["rows"]), 1)), int(sh["push"]), float(sh["push"]) / float(maxi(int(sh["rows"]), 1)),
				int(sh["push_rows"]), int(sh["lonely"]), str(sh["hist"]), int(sh["gt6"]), int(sh["gt6_push"])])
		var bc: Dictionary = j.get("by_class", {})
		var keys: Array = bc.keys()
		keys.sort()
		for k in keys:
			var c: Dictionary = bc[k]
			var jn: int = int(c["idle_jit"])
			print("    %-18s n %5.0f | IDLE %5.0f дрожат %4.0f (в ср. %4.1f см/0.5 с) ходьба %4.0f | MOVING %5.0f на месте %4.0f | ATTACK %5.0f | спят %5.0f" % [
				_class_label(String(k)), float(c["n"]) / ns, float(c["idle"]) / ns, float(jn) / ns,
				(float(c["jit_sum"]) / float(jn) * 100.0) if jn > 0 else 0.0, float(c["idle_walk"]) / ns,
				float(c["moving"]) / ns, float(c["moving_stuck"]) / ns, float(c["attacking"]) / ns, float(c["sleep"]) / ns])
		# Приказы движения по источникам
		var cmd: Array = d["cmd"]
		var by_src: Dictionary = {}
		for row in cmd:
			var key: String = "%s → %s из %s" % [String(row[0]), _class_label(String(row[1])), _state_label(int(row[2]))]
			by_src[key] = int(by_src.get(key, 0)) + int(row[3])
		var srows: Array = []
		for k in by_src:
			srows.append([k, int(by_src[k])])
		srows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
		var secs: float = float(int(d["frames"])) / 60.0
		print("  ПРИКАЗЫ ДВИЖЕНИЯ (command_move): всего %.0f/с" % float(d["cmd_per_sec"]))
		for i in range(mini(srows.size(), 10)):
			print("    %-52s %7.1f/с" % [String(srows[i][0]), float(int(srows[i][1])) / secs])
		var sids: Array = d["cmd_sids"]
		var sline := ""
		for i in range(mini(sids.size(), 8)):
			sline += "%s#%d ×%d; " % [String(sids[i][0]), int(sids[i][1]), int(sids[i][2])]
		print("    по отрядам (источник#sid ×вызовов): %s" % sline)
		var rf: Dictionary = d["reform"]
		print("  СМЫКАНИЕ на конец фазы: отрядов %d, с разметкой %d, с дрейфом > %.2f м — %d отрядов / %d бойцов (в бою %d, идут %d, откат %d, СВОБОДНЫХ %d)" % [
			int(rf["total"]), int(rf["with_slots"]), GameManager.REFORM_DRIFT, int(rf["squads_drift"]), int(rf["drifted"]),
			int(rf.get("in_combat", 0)), int(rf.get("on_move", 0)), int(rf.get("backoff", 0)), int(rf.get("free", 0))])
		# Подсистемы _process (аудит 19.09): что сидит в «прочем» кадра
		var sysr: Array = d.get("sys", [])
		var sfr: float = float(maxi(int(d.get("sys_frames", 1)), 1))
		var sys_sum := 0.0
		for row in sysr:
			sys_sum += float(int(row[1])) / 1000.0 / sfr
		print("  НАВИГАЦИЯ: A* вызовов %d (не найдено %d, отбито компонентами %d; мимо кэша: ячейка %d, концы %d), %.2f мс/кадр, худший вызов %.2f мс" % [
			int(d.get("nav_calls", 0)), int(d.get("nav_failed", 0)), int(d.get("nav_unreach", 0)),
			int(d.get("nav_miss_key", 0)), int(d.get("nav_miss_reuse", 0)),
			float(d.get("nav_ms_frame", 0.0)), float(d.get("nav_worst_ms", 0.0))])
		print("  ПОДСИСТЕМЫ _process (мс/кадр, худший вызов): всего %.2f мс/кадр" % sys_sum)
		for row in sysr:
			var ncalls: int = int(row[3]) if row.size() > 3 else 0
			print("    %-12s %6.2f мс/кадр   худший %6.1f мс   вызовов %6d, по %6.1f мкс" % [String(row[0]),
				float(int(row[1])) / 1000.0 / sfr, float(int(row[2])) / 1000.0, ncalls,
				float(int(row[1])) / float(maxi(ncalls, 1))])
		# Сканы по местам
		var sc: Array = d["scan"]
		print("  СКАНЫ ЦЕЛЕЙ (_find_nearest_enemy_in_range): всего %.0f/с" % float(d["scan_per_sec"]))
		for i in range(mini(sc.size(), 8)):
			print("    %-28s %7.1f/с" % [String(sc[i][0]), float(int(sc[i][1])) / secs])
		if not d.has("prof"):
			continue
		var frames_total: int = int(d["frames"])
		# Состояния
		print("  ВРЕМЯ ТИКА ПО СОСТОЯНИЯМ (class_meter, мс кадра / мкс на тик / тиков за замер):")
		for row in d["states"]:
			print("    %-10s %6.2f мс/кадр  %6.1f мкс/тик  %8d тиков" % [_state_label(int(row[0])), float(row[1]), float(row[2]), int(row[3])])
		print("  ПО РОДАМ ВОЙСК (мс/кадр, мкс/тик, худший тик мкс (состояние)):")
		for row in d["classes"]:
			var mx: Array = _Opt.class_max(String(row[0]))
			print("    %-18s %6.2f  %6.1f  %6d (%s)" % [_class_label(String(row[0])), float(row[1]), float(row[2]), int(mx[0]), _state_label(int(mx[1]))])
		# Категории
		var cats: Dictionary = {}
		var prof: Array = d["prof"]
		for row in prof:
			var name: String = String(row[0])
			if name.begins_with("!") or SUB.has(name):
				continue
			var cat: String = String(CAT.get(name, "Прочее"))
			cats[cat] = float(cats.get(cat, 0.0)) + float(int(row[1])) / 1000.0 / float(frames_total)
		var nav_ms: float = float(d["nav_ms_frame"])
		cats["Навигация/обход"] = float(cats.get("Навигация/обход", 0.0)) + nav_ms
		var crow: Array = []
		for k in cats:
			crow.append([k, float(cats[k])])
		crow.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
		print("  КАТЕГОРИИ (мс на кадр, верхний уровень веток; профиль завышает ~1.5-1.8× — ранжирование):")
		for c in crow:
			print("    %-24s %6.2f мс/кадр" % [String(c[0]), float(c[1])])
		print("  ВЕТКИ ФИЗТИКА (топ-16):")
		var k := 0
		for row in prof:
			var name: String = String(row[0])
			if name.begins_with("!"):
				continue
			k += 1
			if k > 16:
				break
			print("    %2d. %-22s %6.2f мс/кадр  (%d вызовов, %.1f мкс каждый, худший %d)" % [
				k, name, float(int(row[1])) / 1000.0 / float(maxi(frames_total, 1)), int(row[2]), float(row[3]), int(row[4])])
		# Подветки пересчёта коридора (BigStand-5, этап 4): что осталось в GDScript
		var cor_any := false
		for row in prof:
			var cn: String = String(row[0])
			if not (cn.begins_with("cor_") or cn.begins_with("tail_")):
				continue
			if not cor_any:
				print("  ПОДВЕТКИ КОРИДОРА И ХВОСТА ТИКА (мс/кадр, мкс/вызов):")
				cor_any = true
			print("      %-14s %6.3f мс/кадр  (%d вызовов, %.1f мкс каждый, худший %d)" % [
				cn, float(int(row[1])) / 1000.0 / float(maxi(frames_total, 1)), int(row[2]), float(row[3]), int(row[4])])
		for sp in d["spikes"]:
			var br := ""
			for b in sp[4]:
				br += "%s %.1f; " % [String(b[0]), float(b[1])]
			print("    пик кадр %4d: интервал %.1f мс = физтик %.1f + логика %.1f + прочее %.1f  [%s]" % [
				int(sp[3]), float(sp[0]), float(sp[1]), float(sp[2]), float(sp[0]) - float(sp[1]) - float(sp[2]), br])
	print("═════ ИТОГ qa_bigstand: провалов: 0 (измеритель, вердиктов нет) ═════")
