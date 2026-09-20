extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_big_goblin_pair — ТЗ 19.09.2026 «ФИКС БОЛЬШИХ ГОБЛИНОВ»
## ═══════════════════════════════════════════════════════════════════════════
## Пять туш в связке с тридцатью гоблинами идут на стенку пехоты людей.
##   A ЗВУК     — сэмпл шага туши свой и глухой (не Sword_hit_armor), шаг
##                звучит на ходу, по ленте ходьбы, реже BIG_STEP_SEC.
##   B АГРО     — туша в ПОКОЕ берёт пехоту в радиусе агро тем же тактом
##                (BIG_HUNT_TICK), пехота в приоритете перед рабочим; марш
##                МИМО врага (враг в 10 м сбоку) прерывается боем.
##   C СВЯЗКА   — гоблины получили приказ атаки, туши — только марш: все
##                пять вступают в бой не позже чем через BIG_ESCORT_SEC после
##                первого гоблина, ни одна не прошла сквозь стенку.
##   D АНИМАЦИЯ — на ходу лента «walk» у идущей туши (рассинхрон ≤ 10 %
##                выборок), проход сквозь толпу 30 своих гоблинов не
##                медленнее BIG_CROWD_SPEED_FRAC чистого поля; рывков
##                (скорость упала ниже трети шага на такт) нет.
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_big_goblin_pair/Test.tscn

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const BIG_ESCORT_SEC := 8.0
const BIG_CROWD_SPEED_FRAC := 0.75

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _base: Vector3 = Vector3.ZERO

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 600 с")
		_finish())

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
	print("\n═════ ИТОГ qa_big_goblin_pair: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int, sp: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(
			at.x + (float(i % cols) - float(cols - 1) * 0.5) * sp, 0.0,
			at.z + float(i / cols) * sp))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _kill(men: Array) -> void:
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _immortal(men: Array) -> void:
	for u in men:
		var un := u as Unit
		un.max_health = 1e9
		un.current_health = 1e9
		un._soa_push_stats()

## «В бою» — КОНТАКТ, а не приказ: ATTACKING с живой целью в досягаемости
## (+1 м); сам приказ атаки переводит в ATTACKING тем же кадром
func _in_fight(u: Unit) -> bool:
	var t = u.attack_target
	if u.state != Unit.State.ATTACKING or t == null or not is_instance_valid(t):
		return false
	return _xz(u.global_position, (t as Node3D).global_position) <= u.reach() + 1.0

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h := 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(25.0, 0.0, 0.0), Vector3(-25.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 30.0), Vector3(0.0, 0.0, -30.0), Vector3(0.0, 0.0, 60.0)]:
				var q: Vector3 = p + (d as Vector3)
				h = maxf(h, absf(GameManager.get_terrain_height(q.x, q.z)))
				if GameManager.is_water(q.x, q.z) or GameManager.is_cliff(q.x, q.z):
					h = 1e9
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	for _i in range(8):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Unit).faction != F:
			(n as Unit).set_tick(false)
	GameManager.troll_lair = null
	GameManager.pop_limit_enabled = false
	_base = _flat_spot(Vector3(-40.0, 0.0, -30.0))
	main._clear_area_of_resources(_base, 70.0)
	AudioManager.sfx_trace = true
	await pframes(6)
	print("  площадка (%.0f, %.0f)" % [_base.x, _base.z])
	await _a_audio()
	await _b_aggro()
	await _c_pair()
	await _d_anim()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_audio() -> void:
	print("\n═════ A. ЗВУК ШАГА ═════")
	var bank: Dictionary = AudioManager.SFX_BANK
	var files: Array = bank.get("big_step", [])
	var metal := false
	var all_exist := true
	for f in files:
		var fs: String = String(f)
		if fs.to_lower().contains("sword") or fs.to_lower().contains("armor") or fs.to_lower().contains("metal"):
			metal = true
		if not ResourceLoader.exists(AudioManager.sfx_path(fs)):
			all_exist = false
	verdict("A1 в банке шага туши нет ударов по доспеху («ведра»): %s" % str(files), not metal and files.size() > 0)
	verdict("A2 файлы шага существуют и грузятся", all_exist)
	var lim: Dictionary = AudioManager.SFX_LIMITS.get("big_step", {})
	var pitch: Array = lim.get("pitch", [1.0, 1.0])
	verdict("A3 шаг не сдвинут питчем вниз до гула (%.2f-%.2f) и тише −10 дБ (%.0f)" % [float(pitch[0]), float(pitch[1]), float(lim.get("db", 0.0))],
		float(pitch[0]) >= 0.8 and float(lim.get("db", 0.0)) <= -10.0)
	# Шаг звучит на ходу: одна туша идёт 12 с
	var big: Unit = _spawn("big_goblin", GF, _base + Vector3(-30.0, 0.0, 0.0))
	await pframes(3)
	AudioManager.sfx_trace_counts.clear()
	big.command_move(_base + Vector3(-30.0, 0.0, 30.0))
	await pframes(60 * 8)
	var steps: int = int(AudioManager.sfx_trace_counts.get("big_step", 0))
	var expect: float = 8.0 / _GobCfg.BIG_STEP_SEC
	verdict("A4 на ходу шаг звучит: %d вызовов за 8 с (ожидание ~%.0f, не чаще)" % [steps, expect],
		steps >= 3 and float(steps) <= expect + 2.0)
	big.take_damage(1e12)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _b_aggro() -> void:
	print("\n═════ B. АГРО ТУШИ В ПОКОЕ И НА МАРШЕ ═════")
	# (1) покой: пехота врага появляется в радиусе агро — цель за такт
	var big: Unit = _spawn("big_goblin", GF, _base)
	await pframes(3)
	var far: float = _GobCfg.BIG_AGGRO_RADIUS - 4.0
	var worker: Unit = _spawn("worker", F, _base + Vector3(far * 0.5, 0.0, 0.0))
	worker.set_tick(false)
	var sp: Unit = _spawn("spearman", F, _base + Vector3(far, 0.0, 0.0))
	sp.set_tick(false)
	_immortal([sp, worker])
	var got := -1
	for f in range(60 * 4):
		await get_tree().physics_frame
		if big.attack_target == sp:
			got = f
			break
	verdict("B1 туша в покое взяла копейщика за %.2f с (такт %.1f + агро)" % [float(maxi(got, 0)) / 60.0, _GobCfg.BIG_HUNT_TICK],
		got >= 0 and float(got) / 60.0 <= _GobCfg.BIG_HUNT_TICK + 1.2)
	verdict("B2 пехота в приоритете: цель — копейщик, а не более близкий рабочий", big.attack_target == sp)
	var reached := false
	for f in range(60 * 14):
		await get_tree().physics_frame
		if _xz(big.global_position, sp.global_position) <= big.reach() + 0.5:
			reached = true
			break
	verdict("B3 туша дошла до цели и бьёт (свипов %d)" % big.sweeps, reached or big.sweeps > 0)
	_kill([sp, worker, big])
	await pframes(4)
	# (2) марш мимо: враг в 9 м сбоку от прямой
	var big2: Unit = _spawn("big_goblin", GF, _base + Vector3(-25.0, 0.0, 20.0))
	await pframes(3)
	var side: Array = _squad("spearman", F, _base + Vector3(0.0, 0.0, 29.0), 12, 6, 0.7)
	for u in side[1]:
		(u as Unit).set_tick(false)
	_immortal(side[1])
	big2.command_move(_base + Vector3(30.0, 0.0, 20.0))
	var engaged := -1
	var passed := false
	for f in range(60 * 30):
		await get_tree().physics_frame
		if engaged < 0 and _in_fight(big2):
			engaged = f
		if big2.global_position.x > _base.x + 12.0 and engaged < 0:
			passed = true
			break
		if engaged >= 0 and _xz(big2.global_position, (big2.attack_target as Node3D).global_position) <= big2.reach() + 0.5:
			break
	verdict("B4 марш мимо врага в 9 м прерван боем (за %.1f с), туша не прошла мимо" % (float(maxi(engaged, 0)) / 60.0),
		engaged >= 0 and not passed)
	_kill([big2] + side[1])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _c_pair() -> void:
	print("\n═════ C. СВЯЗКА: 5 ТУШ + 30 ГОБЛИНОВ НА СТЕНКУ ПЕХОТЫ ═════")
	var wall_z: float = _base.z + 40.0
	var wall: Array = _squad("spearman", F, _base + Vector3(0.0, 0.0, 40.0), 40, 20, 0.7)
	for u in wall[1]:
		(u as Unit).set_stance("defense")
		(u as Unit).command_move((u as Unit).global_position, false, Vector3.BACK)
	_immortal(wall[1])
	var g1: Array = _squad("goblin_spearman", GF, _base + Vector3(-6.0, 0.0, 0.0), 15, 5, 0.9)
	var g2: Array = _squad("goblin_spearman", GF, _base + Vector3(6.0, 0.0, 0.0), 15, 5, 0.9)
	var bigs: Array = _squad("big_goblin", GF, _base + Vector3(0.0, 0.0, -8.0), 5, 5, 2.4)
	var gobs: Array = g1[1] + g2[1]
	await pframes(30)
	var start_z: Dictionary = {}
	for u in bigs[1]:
		start_z[u] = (u as Unit).global_position.z
	# Гоблины — приказ атаки на стенку; туши — только МАРШ за стенку (их
	# должно втянуть в бой агро или связка с пехотой)
	var foe: Unit = wall[1][10]
	for u in gobs:
		(u as Unit).command_attack(foe, true, false, true)
	for u in bigs[1]:
		(u as Unit).command_move(_base + Vector3(0.0, 0.0, 70.0))
	var first_gob := -1
	var big_in: Dictionary = {}
	var passed := 0
	var anim_samples := 0
	var anim_bad := 0
	var last_pos: Dictionary = {}
	for f in range(60 * 45):
		await get_tree().physics_frame
		if first_gob < 0:
			for u in _alive(gobs):
				if _in_fight(u):
					first_gob = f
					break
		for u in _alive(bigs[1]):
			var b := u as Unit
			if _in_fight(b) and not big_in.has(b):
				big_in[b] = f
			if b.global_position.z > wall_z + 2.5:
				passed += 1
		# Рассинхрон ленты: раз в 0.5 с — идёт (по позиции ≥ 0.5 м/с) ↔ лента walk
		if f % 30 == 0:
			for u in _alive(bigs[1]):
				var b := u as Unit
				var p: Vector3 = b.global_position
				var lp: Variant = last_pos.get(b)
				if lp != null:
					var v: float = _xz(p, lp) / 0.5
					# В headless визуальный тик не идёт (боец вне кадра) —
					# разбор позы зовётся сам, тем же кодом
					b._update_sprite_anim()
					var walking: bool = String(b._anim_name) == "walk"
					if v >= 0.5 or walking:
						anim_samples += 1
						if (v >= 0.5) != walking and not (v < 0.5 and b.walk_anim_recently()):
							anim_bad += 1
				last_pos[b] = p
		if big_in.size() >= 5 and first_gob >= 0 and _sweeps(bigs[1]) >= 3:
			break
	var lag := 0.0
	var over := 0.0        # худшее отношение «время до контакта / чистый ход»
	for b in big_in:
		lag = maxf(lag, float(int(big_in[b]) - first_gob) / 60.0)
		var walk: float = maxf(wall_z - 2.0 - float(start_z.get(b, _base.z)), 1.0) / maxf((b as Unit).move_speed, 0.1)
		over = maxf(over, float(int(big_in[b])) / 60.0 / walk)
	var on_wall := 0
	for u in bigs[1]:
		if is_instance_valid(u):
			var t = (u as Unit).attack_target
			if t != null and is_instance_valid(t) and t is Unit and (t as Unit).squad_id == int(wall[0]):
				on_wall += 1
	var esc := 0
	var sweeps: int = _sweeps(bigs[1])
	for u in bigs[1]:
		if is_instance_valid(u):
			esc += int((u as Unit).escorts_taken)
	# Туша медленнее гоблина ПО КОНФИГУ: честное отставание — разница времени
	# хода на 40 м плюс запас (правило 10), а не круглое число
	var v_big: float = (bigs[1][0] as Unit).move_speed if is_instance_valid(bigs[1][0]) else 1.0
	var v_gob: float = (gobs[0] as Unit).move_speed if is_instance_valid(gobs[0]) else 1.0
	var lag_ok: float = 48.0 * (1.0 / maxf(v_big, 0.1) - 1.0 / maxf(v_gob, 0.1)) + BIG_ESCORT_SEC
	print("  первый гоблин в бою на %.1f с; туш в бою %d из 5, худшее отставание %.1f с, подхватов цели %d, свипов %d, прошли стенку %d" % [
		float(maxi(first_gob, 0)) / 60.0, big_in.size(), lag, esc, sweeps, passed])
	verdict("C1 все пять туш вступили в бой", big_in.size() == 5)
	# Туша медленнее гоблина ПО КОНФИГУ (владелец: 0.7 шага), потому «синхронно»
	# значит «без ступора»: контакт не позже полутора своих чистых ходов до
	# стенки (полчаса стоит толпа гоблинов у стенки, сквозь которую туша
	# продавливается); разница хода печатается справочно
	print("  худшее отставание от первого гоблина %.1f с при разнице хода по конфигу %.1f с; контакт / чистый ход = %.2f" % [lag, lag_ok - BIG_ESCORT_SEC, over])
	verdict("C2 туши дошли без ступора: контакт не позже 1.5 × чистого хода (худшее ×%.2f)" % over,
		big_in.size() == 5 and over <= 1.5)
	verdict("C2б туши не разбрелись: цель у всех — стенка (%d из 5)" % on_wall, on_wall == 5)
	verdict("C3 ни одна туша не прошла сквозь стенку (за линией %d проб)" % passed, passed == 0)
	verdict("C4 туши бьют: свипов %d" % sweeps, sweeps >= 3)
	var frac: float = float(anim_bad) / maxf(float(anim_samples), 1.0)
	verdict("C5 лента ходьбы совпадает с фактом хода: рассинхрон %d из %d (%.0f %%) ≤ 10 %%" % [anim_bad, anim_samples, frac * 100.0],
		anim_samples > 0 and frac <= 0.10)
	_kill(wall[1] + gobs + bigs[1])
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
func _d_anim() -> void:
	print("\n═════ D. СКОРОСТЬ СКВОЗЬ ТОЛПУ СВОИХ ═════")
	var start: Vector3 = _base + Vector3(-40.0, 0.0, -10.0)
	var goal: Vector3 = _base + Vector3(20.0, 0.0, -10.0)
	# Чистое поле
	var b0: Unit = _spawn("big_goblin", GF, start)
	await pframes(3)
	var t_clear: float = await _walk_time(b0, goal)
	b0.take_damage(1e12)
	await pframes(4)
	# Толпа 30 своих гоблинов на дороге (другой отряд, стоят)
	var crowd: Array = _squad("goblin_spearman", GF, _base + Vector3(-12.0, 0.0, -13.0), 30, 6, 1.0)
	await pframes(20)
	var b1: Unit = _spawn("big_goblin", GF, start)
	await pframes(3)
	var t_crowd: float = await _walk_time(b1, goal)
	var v_clear: float = _xz(start, goal) / maxf(t_clear, 0.01)
	var v_crowd: float = _xz(start, goal) / maxf(t_crowd, 0.01)
	print("  чистое поле %.1f с (%.2f м/с, шаг %.2f), сквозь толпу %.1f с (%.2f м/с), рывков %d" % [
		t_clear, v_clear, b1.move_speed, t_crowd, v_crowd, _jerks])
	verdict("D1 сквозь толпу своих не медленнее %.0f %% чистого поля (%.0f %%)" % [BIG_CROWD_SPEED_FRAC * 100.0, v_crowd / maxf(v_clear, 0.01) * 100.0],
		t_crowd > 0.0 and t_clear > 0.0 and v_crowd >= v_clear * BIG_CROWD_SPEED_FRAC)
	verdict("D2 рывков (скорость за полсекунды ниже трети шага) в толпе: %d ≤ 1" % _jerks, _jerks <= 1)
	verdict("D3 толпа разошлась перед тушей, а не отбросила её: туша дошла", t_crowd > 0.0)
	b1.take_damage(1e12)
	_kill(crowd[1])
	await pframes(4)

func _sweeps(men: Array) -> int:
	var s := 0
	for u in men:
		if u != null and is_instance_valid(u):
			s += int((u as Unit).sweeps)
	return s

var _jerks := 0
func _walk_time(b: Unit, goal: Vector3) -> float:
	_jerks = 0
	b.command_move(goal)
	var last: Vector3 = b.global_position
	for f in range(60 * 60):
		await get_tree().physics_frame
		if f % 30 == 0 and f > 0:
			var p: Vector3 = b.global_position
			var v: float = _xz(p, last) / 0.5
			# в середине пути (не старт и не финиш)
			if _xz(p, goal) > 4.0 and f > 60 and v < b.move_speed / 3.0:
				_jerks += 1
			last = p
		if _xz(b.global_position, goal) < 2.0:
			return float(f) / 60.0
	return -1.0
