extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТРЕСС-СЦЕНА: 700 НА 700 СМЕШАННЫМ СОСТАВОМ + ШТУРМ БАЗЫ
## ═══════════════════════════════════════════════════════════════════════════
## ЗАЧЕМ ЕЩЁ ОДИН МАССОВЫЙ СТЕНД. qa_mass_battle — это две толпы ТОЛЬКО
## копейщиков, без зданий, без кавалерии, без лучников и без ИИ. Все жалобы
## владельца живут ровно на тех стыках, которых там нет: разброс отряда на
## марше, схлопывание нескольких отрядов у одного здания, поза бега у
## застрявших, строй у рабочих. Стерильный стенд их увидеть не мог.
##
## ЭТОТ СТЕНД НЕ СУДИТ, А МЕРЯЕТ. Он печатает ЧИСЛА по каждому симптому, и по
## ним видно, стало лучше или хуже. Вердикты есть только там, где свойство
## однозначно (например «рабочий не строится шеренгой»).
##
## Запуск: godot --headless --path . res://qa_mass_siege/Test.tscn
##         ... -- units=700        (по умолчанию 700 на сторону)

const _OptCfg = preload("res://scripts/perf_config.gd")
const _UCfgS  = preload("res://scripts/unit_stats_config.gd")

## Состав стороны: доли родов войск. Сумма долей не важна — нормируется
const MIX := {
	"res://scenes/units/Spearman.tscn": 0.45,
	"res://scenes/units/Archer.tscn":   0.25,
	"res://scenes/units/Warrior.tscn":  0.20,
	"res://scenes/units/GoblinPigRider.tscn": 0.10,
}
## Сколько бойцов в отряде стенда. Меньше боевого штата: нужно МНОГО отрядов,
## чтобы увидеть межотрядные беды (разброс, схлопывание у здания)
const SQUAD_SIZE := 35
const BUDGET_MS  := 16.6

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _units: Array = []
var _my_squads: Array = []      # отряды игрока: [sid, men]
var _foe_squads: Array = []
var _buildings: Array = []

func _ready() -> void:
	call_deferred("_run")

func pf(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	_units.append(u)
	return u

## Список сцен по долям MIX на n бойцов
func _mix_list(n: int) -> Array:
	var out: Array = []
	var total := 0.0
	for k in MIX: total += float(MIX[k])
	for k in MIX:
		var cnt: int = int(round(float(n) * float(MIX[k]) / total))
		for _i in range(cnt): out.append(k)
	while out.size() < n: out.append("res://scenes/units/Spearman.tscn")
	return out

## Замер тика за n физкадров
func _sample(n: int) -> float:
	_OptCfg.tick_meter = true
	_OptCfg.tick_reset()
	await pf(n)
	_OptCfg.tick_meter = false
	return _OptCfg.tick_ms()

# ── МЕРКИ ────────────────────────────────────────────────────────────────────

## Разброс отряда: [худший радиус от медианы, средний радиус]
func _scatter(men: Array) -> Array:
	var live: Array = []
	for m in men:
		# ПРОВЕРКА ДО ПРИВЕДЕНИЯ ТИПА: `x as Unit` на освобождённом объекте не
		# возвращает null, а БРОСАЕТ исключение (правило проекта)
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u != null and not u.is_dead():
			live.append(u)
	if live.is_empty():
		return [0.0, 0.0]
	var c: Vector3 = GameManager._centroid_of(live)
	var worst := 0.0
	var acc := 0.0
	for u2 in live:
		var d: float = Vector2((u2 as Node3D).global_position.x - c.x,
			(u2 as Node3D).global_position.z - c.z).length()
		worst = maxf(worst, d)
		acc += d
	return [worst, acc / float(live.size())]

## Сколько бойцов В ПОЗЕ БЕГА при фактически нулевом смещении
func _running_in_place() -> Array:
	var before: Dictionary = {}
	for u in _units:
		if not is_instance_valid(u):
			continue
		if not (u as Unit).is_dead():
			before[u] = (u as Node3D).global_position
	await pf(20)
	var stuck := 0
	var total := 0
	for u2 in before:
		if not is_instance_valid(u2) or (u2 as Unit).is_dead():
			continue
		var uu := u2 as Unit
		total += 1
		var moved: float = Vector2(uu.global_position.x - (before[u2] as Vector3).x,
			uu.global_position.z - (before[u2] as Vector3).z).length()
		# «Бежит» — по той же ленте, что видит игрок
		var key: String = String(uu.get("_cur_tex_key")) if uu.get("_cur_tex_key") != null else ""
		var runs: bool = key == "run" or String(uu.get("_anim_name")) == "walk"
		if runs and moved < 0.05:
			stuck += 1
	return [stuck, total]

func _run() -> void:
	var per_side := 700
	for a in _args():
		var s := String(a)
		if s.begins_with("units="):
			per_side = int(s.substr(6))
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(10)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	# Своя армия — со своей раскладкой; чужую базу оставляем, ИИ отключаем,
	# чтобы замер мерил ФИЗИКУ И СТРОЙ, а не решения ИИ
	if main.enemy_ai != null: main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null: main.goblin_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await pf(6)

	print("═════ СТРЕСС-СЦЕНА: ОСАДА %d НА %d ═════" % [per_side, per_side])
	_build_base()
	_build_armies(per_side)
	await pf(20)
	print("  отрядов у игрока %d, у противника %d, построек %d, юнитов всего %d"
		% [_my_squads.size(), _foe_squads.size(), _buildings.size(), _units.size()])

	await _m_march()
	await _m_passthrough()
	await _m_workers()
	# ОСАДА ИДЁТ ПОСЛЕДНЕЙ, И ЭТО ВАЖНО. Она ПЕРЕСТАВЛЯЕТ пять
	# отрядов к базе противника — и если после неё мерить бой, в замер
	# попадают отряды, бредущие обратно через полкарты. Именно это
	# давало разброс B1 то 5.8 м, то 24.6 м на НЕИЗМЕННОМ коде
	await _m_battle()
	await _m_siege()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 62), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== MASS SIEGE DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

## База противника: замок, барак, кузница и три дома
func _build_base() -> void:
	var at := Vector3(60.0, 0.0, 0.0)
	var plan := [
		["res://scripts/Castle.gd",   Vector3(0, 0, 0)],
		["res://scripts/Barracks.gd", Vector3(14, 0, -8)],
		["res://scripts/Smithy.gd",   Vector3(14, 0, 8)],
		["res://scripts/House.gd",    Vector3(-2, 0, -14)],
		["res://scripts/House.gd",    Vector3(-2, 0, 14)],
		["res://scripts/House.gd",    Vector3(26, 0, 0)],
	]
	for p in plan:
		var b = load(String((p as Array)[0])).new()
		b.faction = Constants.FACTION_ENEMY
		main.world_add(b)
		b.global_position = at + ((p as Array)[1] as Vector3)
		_buildings.append(b)

## Две армии смешанного состава, лицом друг к другу
func _build_armies(per_side: int) -> void:
	var mine := _mix_list(per_side)
	var theirs := _mix_list(per_side)
	_my_squads = _fill_side(mine, Constants.FACTION_PLAYER, Vector3(-40.0, 0.0, 0.0), 1.0)
	_foe_squads = _fill_side(theirs, Constants.FACTION_ENEMY, Vector3(20.0, 0.0, 0.0), -1.0)

func _fill_side(list: Array, fac: int, base: Vector3, dir: float) -> Array:
	var out: Array = []
	var i := 0
	var col := 0
	while i < list.size():
		var n: int = mini(SQUAD_SIZE, list.size() - i)
		var kind: String = String(list[i])
		var sid: int = GameManager.new_squad(fac, _stat_of(kind))
		var men: Array = []
		# Отряды в шахматку: несколько колонн в глубину
		var sx: float = base.x - dir * float(col / 6) * 9.0
		var sz: float = -45.0 + float(col % 6) * 15.0
		for k in range(n):
			var u := _spawn(kind, fac,
				Vector3(sx + float(k % 7) * 0.8 * dir, 0.0, sz + float(k / 7) * 0.8))
			GameManager.add_to_squad(sid, u)
			men.append(u)
		out.append([sid, men])
		i += n
		col += 1
	return out

func _stat_of(scene: String) -> String:
	if scene.contains("Archer"): return "archer"
	if scene.contains("Warrior"): return "warrior"
	if scene.contains("PigRider"): return "goblin_rider"
	return "spearman"

# ═════════════════════════════════════════════════════════════════════════════
# МАРШ: РАЗБРОС ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _m_march() -> void:
	print("\n───── МАРШ: РАЗБРОС ОТРЯДА ─────")
	var sm = main.selection_manager
	var before_worst := 0.0
	for rec in _my_squads:
		before_worst = maxf(before_worst, float(_scatter(rec[1])[0]))
	# Приказ каждому отряду отдельно — вперёд, к базе
	for rec2 in _my_squads:
		sm._clear_selection()
		for u in (rec2[1] as Array): sm._select(u)
		await pf(1)
		sm._issue_formation_move(Vector3(0.0, 0.0, 0.0), false)
	sm._clear_selection()
	var t_move := await _sample(240)
	var worst := 0.0
	var mean := 0.0
	for rec3 in _my_squads:
		var sc := _scatter(rec3[1])
		worst = maxf(worst, float(sc[0]))
		mean += float(sc[1])
	mean /= float(maxi(_my_squads.size(), 1))
	print("  разброс от медианы: худший %.1f м, средний %.2f м (до приказа худший %.1f м)"
		% [worst, mean, before_worst])
	print("  тик на марше: %.2f мс (бюджет %.1f)" % [t_move, BUDGET_MS])
	# Отряд из 35 бойцов физически укладывается примерно в 3 м радиуса.
	# Порог с большим запасом: ловим «колбасу», а не тесноту
	verdict("M1 ни один отряд не растянулся дальше 12 м от медианы", worst <= 12.0,
		"худший радиус %.1f м" % worst)

	var rip := await _running_in_place()
	print("  в позе бега при нулевом смещении: %d из %d" % [int(rip[0]), int(rip[1])])
	verdict("M2 «бег на месте» не массовый",
		float(rip[0]) <= float(rip[1]) * 0.08,
		"%d из %d (порог 8%%)" % [int(rip[0]), int(rip[1])])

# ═════════════════════════════════════════════════════════════════════════════
# ОСАДА: НЕСКОЛЬКО ОТРЯДОВ НА ОДНО ЗДАНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _m_siege() -> void:
	print("\n───── ОСАДА: ОТРЯДЫ У ЗДАНИЯ ─────")
	var sm = main.selection_manager
	var target = null
	for b in _buildings:
		if not is_instance_valid(b):
			continue
		if not (b as Building).is_dead():
			target = b
			break
	if target == null:
		print("  построек нет — раздел пропущен")
		return
	# Пять ОТРЯДОВ С ЖИВЫМИ БОЙЦАМИ на одно здание
	var five: Array = []
	for rec0 in _my_squads:
		var alive0: Array = []
		for u0 in (rec0[1] as Array):
			if is_instance_valid(u0) and not (u0 as Unit).is_dead():
				alive0.append(u0)
		if alive0.size() >= 8:
			five.append([int(rec0[0]), alive0])
		if five.size() >= 5:
			break
	if five.size() < 2:
		print("  живых отрядов меньше двух — раздел пропущен")
		return
	# ── ОСАДА МЕРЯЕТСЯ У ЗДАНИЯ, А НЕ ПО ДОРОГЕ К НЕМУ ────────
	# Первая версия отдавала приказ оттуда, где отряды стояли, — а между
	# ними и базой стояла вся чужая армия. До здания никто не доходил
	# (замер: сектора розданы верно, отставание 33-45 м), и «ближайшие
	# центры 1.9 м» описывали ОБЩУЮ СВАЛКУ на полпути, а не кучу у стены.
	# Теперь отряды ставятся ОДНОЙ КУЧЕЙ с тыла базы — то есть в том самом
	# худшем состоянии, на которое жаловался владелец, и вопрос в том,
	# разведёт ли их кольцо секторов по сторонам постройки
	var stage: Vector3 = (target as Node3D).global_position + Vector3(26.0, 0.0, 0.0)
	for recS in five:
		for uS in (recS[1] as Array):
			if not is_instance_valid(uS):
				continue
			var sang: float = randf() * TAU
			var srr: float = sqrt(randf()) * 4.0
			var px: float = stage.x + cos(sang) * srr
			var pz: float = stage.z + sin(sang) * srr
			(uS as Unit).global_position = Vector3(px,
				GameManager.get_terrain_height(px, pz), pz)
	await pf(30)
	# Приказ отдаём ЧЕРЕЗ выделение — так же, как игрок: секторная раскладка
	# живёт в обработчике приказа, а не в самом command_attack
	sm._clear_selection()
	for rec in five:
		for u in (rec[1] as Array):
			if is_instance_valid(u):
				sm._select(u)
	await pf(2)
	sm._ring_squads_around(target as Building)
	for rec9 in five:
		for u9 in (rec9[1] as Array):
			if not is_instance_valid(u9):
				continue
			(u9 as Unit).command_attack(target, true, true, true)
	sm._clear_selection()
	await pf(600)
	var t_siege := await _sample(180)
	# Расстояния между ЦЕНТРАМИ отрядов у здания
	var cs: Array = []
	for rec2 in five:
		cs.append(GameManager.squad_centroid(int(rec2[0])))
	var closest := 1.0e9
	for i2 in range(cs.size()):
		for j in range(i2 + 1, cs.size()):
			var a: Vector3 = cs[i2]
			var b2: Vector3 = cs[j]
			closest = minf(closest, Vector2(a.x - b2.x, a.z - b2.z).length())
	# ДОШЛИ ЛИ ДО СВОИХ СЕКТОРОВ — без этого непонятно, кольцо не раздалось
	# или раздалось, да не сработало
	for recA in five:
		var sidA: int = int(recA[0])
		var ancA: Vector3 = GameManager.squad_attack_anchor(sidA)
		var ctrA: Vector3 = GameManager.squad_centroid(sidA)
		if ancA == Vector3.INF:
			print("    отряд %d: СЕКТОРА НЕТ" % sidA)
		else:
			print("    отряд %d: сектор (%.1f,%.1f), центр (%.1f,%.1f), отставание %.1f м"
				% [sidA, ancA.x, ancA.z, ctrA.x, ctrA.z,
				Vector2(ancA.x - ctrA.x, ancA.z - ctrA.z).length()])
	# И насколько отряды сохранили форму
	var sworst := 0.0
	for rec3 in five:
		sworst = maxf(sworst, float(_scatter(rec3[1])[0]))
	print("  пять отрядов на одно здание: ближайшие центры %.1f м, худший разброс %.1f м"
		% [closest, sworst])
	print("  тик на осаде: %.2f мс" % t_siege)
	# ── ПРОВЕРЯЕТСЯ СВОЙСТВО, А НЕ КРУГЛОЕ ЧИСЛО ──────────────
	# Сначала здесь стояло «ближайшие центры не ближе 4 м», и это
	# требование НЕВЫПОЛНИМО по геометрии: пять отрядов стоят на
	# периметре постройки, а он короткий. При радиусе r и дуге arc
	# соседние центры ФИЗИЧЕСКИ не могут разойтись дальше хорды
	# 2·r·sin(arc/2n). Поэтому сравниваем с НЕЙ, а не с круглым числом:
	# радиус берётся тот, на котором боец РЕАЛЬНО останавливается
	# (стена плюс дальность удара), а не радиус самого кольца.
	# Вторая половина требования важнее первой: каждый отряд стоит У
	# СВОЕГО сектора. Именно это отличает «облепили постройку» от
	# «слились в фарш»: в куче центры тоже разойдутся на метр-другой,
	# но ни один не окажется там, куда его послали
	var bsz: Vector3 = (target as Building).build_size
	var stop_r: float = maxf(bsz.x, bsz.z) * 0.5 + 2.0
	var ideal: float = 2.0 * stop_r * sin(sm.RING_ARC / (2.0 * float(five.size())))
	var lag_worst := 0.0
	var no_anchor := 0
	for recB in five:
		var ancB: Vector3 = GameManager.squad_attack_anchor(int(recB[0]))
		if ancB == Vector3.INF:
			no_anchor += 1
			continue
		var ctrB: Vector3 = GameManager.squad_centroid(int(recB[0]))
		lag_worst = maxf(lag_worst,
			Vector2(ancB.x - ctrB.x, ancB.z - ctrB.z).length())
	print("  геометрический предел разноса центров: %.1f м, худшее отставание от своего сектора: %.1f м"
		% [ideal, lag_worst])
	verdict("S1 отряды облепили здание, а не слились в одну массу",
		no_anchor == 0 and lag_worst <= 3.0 and closest >= ideal * 0.7,
		"без сектора=%d, отставание %.1f м, центры %.1f м при пределе %.1f"
		% [no_anchor, lag_worst, closest, ideal])

# ═════════════════════════════════════════════════════════════════════════════
# РАБОЧИЕ: ТОЧКА СБОРА И ОТСУТСТВИЕ ШЕРЕНГИ
# ═════════════════════════════════════════════════════════════════════════════
func _m_workers() -> void:
	print("\n───── РАБОЧИЕ ─────")
	var castle: Building = null
	for b in _buildings:
		if is_instance_valid(b) and b is Castle:
			castle = b
			break
	if castle == null:
		print("  замка нет — раздел пропущен")
		return
	var flag := castle.global_position + Vector3(-18.0, 0.0, 12.0)
	castle.set_rally_point(flag)
	var ws: Array = []
	var wsid: int = GameManager.new_squad(Constants.FACTION_ENEMY, "worker")
	for i in range(8):
		var w: Unit = load("res://scenes/units/Worker.tscn").instantiate()
		w.faction = Constants.FACTION_ENEMY
		main.world_add(w)
		w.global_position = castle.global_position + Vector3(0.0, 0.0, 6.0)
		GameManager.add_to_squad(wsid, w)
		ws.append(w)
		_units.append(w)
	await pf(4)
	for w2 in ws:
		(w2 as Unit).command_move(flag, false)
	await pf(900)
	var far := 0.0
	for w3 in ws:
		if is_instance_valid(w3):
			far = maxf(far, Vector2((w3 as Node3D).global_position.x - flag.x,
				(w3 as Node3D).global_position.z - flag.z).length())
	print("  восемь рабочих: самый дальний в %.1f м от флажка" % far)
	verdict("W1 рабочие приходят к флажку, а не через полкарты", far <= 10.0,
		"самый дальний %.1f м" % far)
	verdict("W2 рабочий объявлен одиночным агентом",
		GameManager.squad_is_single_agent(wsid),
		"признак у отряда типа worker")
	for w4 in ws:
		if is_instance_valid(w4): (w4 as Node).queue_free()
	await pf(4)

# ═════════════════════════════════════════════════════════════════════════════
# ПРОХОД СКВОЗЬ СТРОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _m_passthrough() -> void:
	print("\n───── ПРОХОД СКВОЗЬ СТРОЙ ─────")
	if _my_squads.size() < 2:
		print("  отрядов мало — раздел пропущен")
		return
	var wall: Array = _my_squads[_my_squads.size() - 1][1]
	var goer: Array = _my_squads[_my_squads.size() - 2][1]
	# Стенка встаёт, идущий отряд получает точку ЗА ней
	var wc: Vector3 = GameManager._centroid_of(wall)
	for u in goer:
		if not is_instance_valid(u):
			continue
		(u as Unit).command_move(wc + Vector3(0.0, 0.0, 18.0), false,
			Vector3.ZERO, false, true)
	# ── МЕРИМ ПЕРЕСЕЧЕНИЕ СТРОЯ, А НЕ «ПОЛОВИНА ДОШЛА» ─────────
	# Первая версия выходила по «дошла половина» и меряла тем самым
	# не затор, а скорость самого быстрого: застрявшие в строю в число
	# не попадали вовсе. Теперь считается ФАКТ ПЕРЕСЕЧЕНИЯ — сколько
	# бойцов оказалось ЗА стенкой и сколько завязло ВНУТРИ неё.
	# Время считается ФИЗИЧЕСКИМИ КАДРАМИ, а не часами: абсолютное
	# время на загруженной машине врёт (правило проекта 12)
	var band: float = 4.0
	var budget: int = 900
	var f_half: int = -1
	var f_most: int = -1
	var crossed := 0
	var frames := 0
	for _i in range(budget):
		await pf(1)
		frames += 1
		crossed = 0
		for u2 in goer:
			# ПРОВЕРКА ДО ПРИВЕДЕНИЯ ТИПА: `x as Unit` на освобождённом
			# объекте не возвращает null, а БРОСАЕТ (правило проекта)
			if not is_instance_valid(u2):
				continue
			if (u2 as Node3D).global_position.z > wc.z + band:
				crossed += 1
		if f_half < 0 and crossed * 2 >= goer.size():
			f_half = frames
		if crossed * 10 >= goer.size() * 9:
			f_most = frames
			break
	# Завязшие — те, кто остался В ПОЛОСЕ самой стенки.
	# Считаются НЕ в момент, когда пересёк девятый десяток, а через две
	# секунды после: отставший на полшага — это не затор, а хвост колонны
	await pf(120)
	var stuck := 0
	crossed = 0
	for u4 in goer:
		if not is_instance_valid(u4):
			continue
		if (u4 as Node3D).global_position.z > wc.z + band:
			crossed += 1
	for u3 in goer:
		if not is_instance_valid(u3):
			continue
		if absf((u3 as Node3D).global_position.z - wc.z) <= band:
			stuck += 1
	var secs: float = float(frames) / 60.0
	var half_s: float = (float(f_half) / 60.0) if f_half > 0 else -1.0
	print("  пересекли строй %d из %d за %.1f с (половина за %.1f с), завязло в стенке %d"
		% [crossed, goer.size(), secs, half_s, stuck])
	verdict("P1 идущий отряд прошёл сквозь союзный строй, а не завяз в нём",
		crossed * 10 >= goer.size() * 9 and stuck == 0,
		"пересекли %d из %d за %.1f с, завязло %d"
		% [crossed, goer.size(), secs, stuck])
	await pf(300)
	var sc := _scatter(wall)
	print("  стенка после прохода: худший съезд от медианы %.1f м" % float(sc[0]))

# ═════════════════════════════════════════════════════════════════════════════
# НАСТОЯЩИЙ БОЙ: «КОЛБАСА» ПОЯВЛЯЕТСЯ ИМЕННО ЗДЕСЬ
# ═════════════════════════════════════════════════════════════════════════════
# Разброс сразу после приказа мал — это стенд и показал. Растягивается отряд
# ПОСЛЕ схватки: часть застряла в свалке, часть ушла добивать, и следующий же
# приказ фиксирует эту форму в разметке. Поэтому мерим ПОСЛЕ боя и ПОСЛЕ
# нового приказа — так, как это видит игрок.
var _worst_who := ""
var _far_why: Array = []

func _m_battle() -> void:
	print("\n───── БОЙ И РАЗБРОС ПОСЛЕ НЕГО ─────")
	var sm = main.selection_manager
	# Обе стороны в бой
	for rec in _my_squads:
		for u in (rec[1] as Array):
			if is_instance_valid(u):
				(u as Unit).set_stance(_UCfgS.STANCE_ATTACK)
	for rec2 in _foe_squads:
		for u2 in (rec2[1] as Array):
			if is_instance_valid(u2):
				(u2 as Unit).set_stance(_UCfgS.STANCE_ATTACK)
	# Своих гоним на чужой строй
	var fc: Vector3 = Vector3(20.0, 0.0, 0.0)
	for rec3 in _my_squads:
		sm._clear_selection()
		for u3 in (rec3[1] as Array):
			if is_instance_valid(u3): sm._select(u3)
		await pf(1)
		sm._issue_formation_move(fc, false)
	sm._clear_selection()
	var t_clash := await _sample(300)
	await pf(900)
	var t_grind := await _sample(300)

	# ВТОРОЙ ПРИКАЗ — тот самый, что фиксирует растянутую форму
	for rec4 in _my_squads:
		sm._clear_selection()
		for u4 in (rec4[1] as Array):
			if is_instance_valid(u4): sm._select(u4)
		await pf(1)
		sm._issue_formation_move(fc + Vector3(-10.0, 0.0, 0.0), false)
	sm._clear_selection()
	# РАЗМЕТКА СРАЗУ ПОСЛЕ ПРИКАЗА И ОНА ЖЕ ЧЕРЕЗ ДЕСЯТЬ СЕКУНД.
	# Разница между двумя числами говорит, где искать виновного:
	# разъехалась сразу — виновата раздача слотов, разъехалась потом —
	# разметку кто-то переписывает уже после приказа
	await pf(2)
	var post0: float = _post_spread()
	await pf(600)
	print("    разметка: сразу после приказа %.1f м, через 10 с %.1f м" % [post0, _post_spread()])

	var worst := 0.0
	var mean := 0.0
	var n := 0
	var worst_post := 0.0
	_worst_who = ""
	for rec5 in _my_squads:
		var men: Array = rec5[1]
		var sc := _scatter(men)
		if float(sc[1]) <= 0.0:
			continue
		worst = maxf(worst, float(sc[0]))
		mean += float(sc[1])
		n += 1
		# И насколько растянута САМА РАЗМЕТКА: post_pos от их медианы
		var live: Array = []
		for m in men:
			if not is_instance_valid(m):
				continue
			if not (m as Unit).is_dead(): live.append(m)
		if live.is_empty(): continue
		var pc := Vector3.ZERO
		var pn := 0
		for m2 in live:
			if (m2 as Unit)._post_valid:
				pc += (m2 as Unit).post_pos
				pn += 1
		# ОГРЫЗКИ ОТРЯДА В ЗАМЕР НЕ ИДУТ. Двое выживших с далёкими слотами
		# дают «растянутую разметку» на пустом месте: сама разметка цела,
		# просто между двумя уцелевшими местами полшеренги
		if pn < 5: continue
		pc /= float(pn)
		for m3 in live:
			if (m3 as Unit)._post_valid:
				var dd3: float = Vector2((m3 as Unit).post_pos.x - pc.x,
					(m3 as Unit).post_pos.z - pc.z).length()
				if dd3 > worst_post:
					worst_post = dd3
					_worst_who = "отряд %d (%s, живых %d/%d): слот (%.1f,%.1f) при центре (%.1f,%.1f), боец в (%.1f,%.1f), state=%d, состав по sid: %s" % [
						int(rec5[0]), (m3 as Unit).get_class(), live.size(), men.size(),
						(m3 as Unit).post_pos.x, (m3 as Unit).post_pos.z, pc.x, pc.z,
						(m3 as Node3D).global_position.x, (m3 as Node3D).global_position.z,
						int((m3 as Unit).state), _sid_census(live)]
	mean /= float(maxi(n, 1))
	var alive := 0
	for u5 in _units:
		if not is_instance_valid(u5):
			continue
		if not (u5 as Unit).is_dead(): alive += 1
	print("  живых %d из %d | тик: свалка %.2f мс, затяжной %.2f мс" % [
		alive, _units.size(), t_clash, t_grind])
	# Сколько бойцов реально ОТОРВАЛОСЬ: среднее может быть отличным при
	# одном улетевшем, и именно он рисует «колбасу» на экране
	var far_cnt := 0
	var live_cnt := 0
	for rec6 in _my_squads:
		var men6: Array = rec6[1]
		var lv: Array = []
		for m6 in men6:
			if not is_instance_valid(m6):
				continue
			if not (m6 as Unit).is_dead(): lv.append(m6)
		if lv.is_empty(): continue
		var c6: Vector3 = GameManager._centroid_of(lv)
		for m7 in lv:
			live_cnt += 1
			if Vector2((m7 as Node3D).global_position.x - c6.x,
					(m7 as Node3D).global_position.z - c6.z).length() > 12.0:
				far_cnt += 1
	print("  ПОСЛЕ БОЯ И НОВОГО ПРИКАЗА: разброс худший %.1f м, средний %.2f м" % [worst, mean])
	print("  оторвавшихся дальше 12 м: %d из %d живых (%.1f%%)" % [
		far_cnt, live_cnt, 100.0 * float(far_cnt) / maxf(float(live_cnt), 1.0)])
	print("  растянутость САМОЙ РАЗМЕТКИ (post_pos): худший %.1f м" % worst_post)
	print("    худший случай: %s" % _worst_who)
	# ── КОЛБАСА — ЭТО БОЕЦ ДАЛЕКО ОТ СВОЕГО СЛОТА, А НЕ ШИРОКИЙ СТРОЙ
	# Сначала здесь стоял СЫРОЙ разброс тел от медианы с порогом 12 м — и он
	# честно краснел на СРАЖАЮЩЕМСЯ отряде: передние сцепились с врагом
	# в десяти метрах впереди, задние стоят на местах — это линия боя, а не
	# развал строя. Жалоба владельца была другой: бойцы УХОДЯТ ОТ СВОИХ
	# МЕСТ через полкарты. Это и мерится: расстояние бойца до ЕГО
	# СОБСТВЕННОГО слота. Сырой разброс остаётся в печати — он полезен
	# глазом, но вердиктом служить не может
	var slot_worst := 0.0
	_far_why.clear()
	var slot_mean := 0.0
	var slot_n := 0
	var slot_far := 0
	for rec8 in _my_squads:
		# Центр СВОЕГО отряда и его зона — вторая половина признака
		# «оторвался» (см. разбор ниже)
		var sid8: int = int(rec8[0])
		var c8: Vector2 = GameManager.squad_centre_xz(sid8)
		var zone8: float = GameManager.squad_zone_radius(sid8)
		for m8 in (rec8[1] as Array):
			if not is_instance_valid(m8):
				continue
			var uu: Unit = m8
			if uu.is_dead() or not uu._post_valid:
				continue
			var dsl: float = Vector2(uu.global_position.x - uu.post_pos.x,
				uu.global_position.z - uu.post_pos.z).length()
			slot_worst = maxf(slot_worst, dsl)
			slot_mean += dsl
			slot_n += 1
			# ── ОТОРВАЛСЯ = ДАЛЕКО И ОТ СЛОТА, И ОТ СВОИХ ────────────
			# Одного удаления от слота мало: когда отряд ЦЕЛИКОМ вошёл
			# в чужой строй, а разметка осталась позади, далеки ОТ СЛОТОВ
			# ВСЕ сразу — и это не развал строя, а линия боя. Развал — это
			# когда боец оторвался И ОТ СВОИХ тоже: именно такого зовёт
			# назад _cohesion_guard, и мерить надо то же самое
			if dsl > 15.0 and c8 != Vector2.INF 					and Vector2(uu.global_position.x - c8.x,
						uu.global_position.z - c8.y).length() > zone8:
				slot_far += 1
				if _far_why.size() < 6:
					_far_why.append("%.0fм state=%d цель=%s замок=%s бег=%s отход=%s" % [
						dsl, int(uu.state), str(is_instance_valid(uu.attack_target)),
						str(uu.target_lock), str(uu.sprinting), str(uu.retreating)])
	slot_mean /= float(maxi(slot_n, 1))
	print("  удалённость бойца от СВОЕГО слота: худшая %.1f м, средняя %.2f м, дальше 15 м: %d из %d"
		% [slot_worst, slot_mean, slot_far, slot_n])
	for w in _far_why:
		print("      ушёл: %s" % str(w))
	# СРЕДНЯЯ УДАЛЁННОСТЬ ОТ ПОСТА ВЕРДИКТОМ СЛУЖИТЬ НЕ МОЖЕТ.
	# Она меряет, КУДА УШЁЛ БОЙ: отряду велели встать в одной точке,
	# он сцепился с противником в десяти метрах впереди — и средняя честно
	# даёт десять метров НА ЦЕЛОМ СТРОЮ. От прогона к прогону она гуляет
	# 4-11 м на НЕИЗМЕННОМ коде. Жалоба же была про ОТОРВАВШИХСЯ,
	# и именно они считаются выше — далеко И от слота, И от своих.
	# Средняя остаётся в печати: она полезна глазом
	verdict("B1 после боя от отрядов никто не оторвался «колбасой»",
		slot_far * 100 <= slot_n,
		"средняя %.2f м, дальше 15 м: %d из %d (сырой разброс %.1f м)"
		% [slot_mean, slot_far, slot_n, worst])
	# ДОПУСК ВЫВОДИТСЯ ИЗ СОСТАВА, А НЕ ЗАДАН ЧИСЛОМ: разметка отряда из
	# n бойцов занимает тот же круг, что задаёт зажим формы при приказе
	# (SelectionManager.SHAPE_CLAMP_SLACK), плюс вмятина от конницы
	# (GameManager.DENT_MAX_TOTAL). Круглое «8 м» не годится: у отряда вдвое
	# большего состава честная разметка шире законно
	# ── МЕРИМ КАНОНИЧЕСКУЮ РАЗМЕТКУ ОТРЯДА, А НЕ ЛИЧНЫЕ ПОСТЫ ───────
	# post_pos у бойца переписывает ЛЮБОЙ command_move — и подзыв
	# сплочённости, и «встать где стою» после исчерпанного приказа.
	# Это НЕ порча строя: пост — это «где меня поставили» для поводка
	# авто-агро, а строевые места лежат ОТДЕЛЬНО — в squads[sid]["slots"],
	# и именно по ним смыкает ряды GameManager. Стенд мерял личные посты
	# и краснел на каждом подзыве отставшего
	var slot_spread := 0.0
	var slot_sq := 0
	for sid9 in GameManager.squads:
		var sq9: Dictionary = GameManager.squads[sid9]
		if int(sq9.get("faction", -1)) != Constants.FACTION_PLAYER:
			continue
		var sl9: Array = sq9.get("slots", [])
		if sl9.size() < 5:
			continue
		var c9 := Vector3.ZERO
		for pt in sl9:
			c9 += (pt as Vector3)
		c9 /= float(sl9.size())
		for pt2 in sl9:
			var v9: Vector3 = pt2
			slot_spread = maxf(slot_spread,
				Vector2(v9.x - c9.x, v9.z - c9.z).length())
		slot_sq += 1
	# ДОПУСК ВЫВОДИТСЯ ИЗ СОСТАВА, А НЕ ЗАДАН ЧИСЛОМ: разметка отряда из
	# n бойцов занимает тот же круг, что задаёт зажим формы при приказе
	# (SelectionManager.SHAPE_CLAMP_SLACK), плюс вмятина от конницы
	# (GameManager.DENT_MAX_TOTAL)
	var allow: float = sqrt(float(SQUAD_SIZE)) * sm.UNIT_SPACING * sm.SHAPE_CLAMP_SLACK 		+ GameManager.DENT_MAX_TOTAL
	print("  разметка отрядов (squads.slots, %d отрядов): худший слот в %.1f м при допуске %.1f"
		% [slot_sq, slot_spread, allow])
	verdict("B2 разметка строя не растянута", slot_sq > 0 and slot_spread <= allow,
		"отрядов %d, худший слот в %.1f м при допуске %.1f" % [slot_sq, slot_spread, allow])
	verdict("B3 затяжной бой укладывается в бюджет физкадра", t_grind <= BUDGET_MS,
		"%.2f мс при бюджете %.1f" % [t_grind, BUDGET_MS])

# Сколько бойцов в КАКОМ отряде числится СЕЙЧАС
func _sid_census(live: Array) -> String:
	var c: Dictionary = {}
	for m in live:
		if not is_instance_valid(m):
			continue
		var sid: int = (m as Unit).squad_id
		c[sid] = int(c.get(sid, 0)) + 1
	return str(c)

# Худшая растянутость разметки по всем своим отрядам
func _post_spread() -> float:
	var w := 0.0
	for rec in _my_squads:
		var live: Array = []
		for m in (rec[1] as Array):
			if not is_instance_valid(m):
				continue
			if not (m as Unit).is_dead() and (m as Unit)._post_valid:
				live.append(m)
		if live.size() < 3:
			continue
		var pc := Vector3.ZERO
		for m2 in live:
			pc += (m2 as Unit).post_pos
		pc /= float(live.size())
		for m3 in live:
			w = maxf(w, Vector2((m3 as Unit).post_pos.x - pc.x,
				(m3 as Unit).post_pos.z - pc.z).length())
	return w
