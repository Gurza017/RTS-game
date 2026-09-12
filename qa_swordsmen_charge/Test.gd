extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: МЕЧНИКИ — РАЗБЕГ СО СТЕНОЙ ЩИТОВ И ШИРОКАЯ ЛИНИЯ БОЯ (спринт 15, блок 3)
## ═══════════════════════════════════════════════════════════════════════════
## ЗАКАЗ ВЛАДЕЛЬЦА:
##   • базовая скорость ~1.9-2.0; по двойному ПКМ / набегу мечник бежит, а за
##     5-10 м до цели включает «Стену щитов» (+30 % к скорости) и влетает во врага;
##   • пехота на марше цепляет врага с флангов / по касательной в радиусе агро,
##     а не только строго перед собой.
##
## Числа — из конфига и констант Warrior/Unit (правило 10), ожидание —
## физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_swordsmen_charge/Test.tscn

const _UStats := preload("res://scripts/unit_stats_config.gd")
const WARRIOR := "res://scenes/units/Warrior.tscn"
const ARCHER := "res://scenes/units/Archer.tscn"
const SPEAR := "res://scenes/units/Spearman.tscn"

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(240.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
		_finish())

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
	print("\n═════ ИТОГ qa_swordsmen_charge: прошло %d, провалов: %d ═════"
		% [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(path: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _squad(path: String, fac: int, kind: String, at: Vector3, n: int, cols: int,
		gap: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var p := at + Vector3((float(i % cols) - float(cols - 1) * 0.5) * gap, 0.0,
			float(i / cols) * gap)
		var u := _spawn(path, fac, p)
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [men, sid]

func _kill_all(men: Array) -> void:
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e9)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	await pframes(4)
	_check_config()
	await _check_dash()
	await _check_wide_line()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _check_config() -> void:
	print("\n═════ A. КОНФИГ ═════")
	var spd: float = _UStats.stat("warrior", "movement_speed", 0.0)
	verdict("A1 базовая скорость мечника ~1.9-2.0", spd >= 1.85 and spd <= 2.05,
		"%.2f" % spd)
	verdict("A2 стена щитов включается за 5-10 м до цели",
		Warrior.SHIELD_WALL_RANGE >= 5.0 and Warrior.SHIELD_WALL_RANGE <= 10.0,
		"%.1f м" % Warrior.SHIELD_WALL_RANGE)
	verdict("A3 стена щитов даёт +30 %% к скорости",
		absf(Warrior.SHIELD_WALL_SPEED_MULT - 1.3) < 0.01,
		"×%.2f" % Warrior.SHIELD_WALL_SPEED_MULT)

# ═════════════════════════════════════════════════════════════════════════════
func _check_dash() -> void:
	print("\n═════ B. РАЗБЕГ СО СТЕНОЙ ЩИТОВ ═════")
	var p0 := Vector3(-1200.0, 0.0, -1200.0)
	# Цель — заморожённый лучник в 22 м: разбег длинный, стена щитов — ближе
	var prey := _spawn(ARCHER, Constants.FACTION_ENEMY, p0)
	prey.set_tick(false)
	prey.current_health = prey.max_health * 50.0
	var w := _spawn(WARRIOR, Constants.FACTION_PLAYER, p0 + Vector3(0.0, 0.0, 22.0)) as Warrior
	await pframes(4)
	var base: float = w._effective_speed()
	w.start_rage_dash()
	w.command_attack(prey, true, true, true)
	var far_speed := 0.0
	var far_wall := 0
	var far_n := 0
	var near_speed := 0.0
	var near_wall := 0
	var near_guard := 0
	var near_n := 0
	var contact := false
	var prey_z0: float = prey.global_position.z
	var hp0: float = prey.current_health
	for _i in range(60 * 25):
		await get_tree().physics_frame
		if not is_instance_valid(w) or not is_instance_valid(prey):
			break
		var d: float = w.global_position.distance_to(prey.global_position)
		var sp: float = w._effective_speed()
		if d > Warrior.SHIELD_WALL_RANGE + 1.5:
			far_n += 1
			far_speed = maxf(far_speed, sp)
			if w.shield_wall_active():
				far_wall += 1
		elif d <= Warrior.SHIELD_WALL_RANGE - 0.3 and d > w.attack_range + 0.5:
			near_n += 1
			near_speed = maxf(near_speed, sp)
			if w.shield_wall_active():
				near_wall += 1
			if w.is_guarding():
				near_guard += 1
		if prey.current_health < hp0:
			contact = true
			# Отлёт — скорость, её интегрирует тик жертвы: размораживаем
			prey.set_tick(true)
			break
	print("  скорость: база %.2f, на разбеге %.2f, у стены щитов %.2f (кадров далеко %d, близко %d)"
		% [base, far_speed, near_speed, far_n, near_n])
	verdict("B1 до стены щитов мечник БЕЖИТ (набег), стены ещё нет",
		far_n > 0 and far_speed > base * 1.2 and far_wall == 0,
		"×%.2f к базе, стена на %d кадрах из %d" % [far_speed / maxf(base, 0.01), far_wall, far_n])
	verdict("B2 в последних метрах стена щитов ВКЛЮЧЕНА и щит поднят",
		near_n > 0 and near_wall >= near_n * 0.8 and near_guard >= near_n * 0.8,
		"стена %d, щит %d из %d кадров" % [near_wall, near_guard, near_n])
	verdict("B3 и скорость ещё на ~30 %% выше разбега",
		near_speed >= far_speed * 1.25,
		"%.2f против %.2f (×%.2f)" % [near_speed, far_speed, near_speed / maxf(far_speed, 0.01)])
	verdict("B4 влетел во врага: удар нанесён", contact)
	# Отлёт врага от удара с набега — тем же множителем после потолка
	await pframes(int(Unit.FLING_SEC * 60.0) + 10)
	var shoved: float = prey.global_position.z - prey_z0 if is_instance_valid(prey) else 0.0
	verdict("B5 враг заметно отброшен ударом с разбега", shoved < -0.3,
		"сдвиг %.2f м" % shoved)
	if is_instance_valid(w):
		w.take_damage(1e9)
	if is_instance_valid(prey):
		prey.take_damage(1e9)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _check_wide_line() -> void:
	print("\n═════ C. ШИРОКАЯ ЛИНИЯ БОЯ НА МАРШЕ ═════")
	# Марш вдоль +Z на 40 м; чужой отряд стоит СБОКУ от дороги на полпути —
	# в радиусе агро, но много дальше прежнего перехвата «в упор»
	var flank_off: float = Unit.AGGRO_RADIUS * 0.6
	var res: Array = await _march_past(Vector3(-1300.0, 0.0, -1300.0), flank_off)
	verdict("C1 враг на фланге в радиусе агро втянут в бой на марше",
		int(res[0]) >= 3, "в бою с фланговыми %d из 6" % int(res[0]))
	# Контроль: тот же марш мимо отряда ДАЛЬШЕ радиуса агро — идут мимо
	var res2: Array = await _march_past(Vector3(-1400.0, 0.0, -1400.0), Unit.AGGRO_RADIUS + 4.0)
	verdict("C2 враг за пределами радиуса агро марш не прерывает",
		int(res2[0]) == 0 and bool(res2[1]),
		"в бою %d, дошли %s" % [int(res2[0]), str(res2[1])])

## Возвращает [сколько мечников бьют фланговых, дошёл ли отряд до точки]
func _march_past(p0: Vector3, flank_off: float) -> Array:
	var mine: Array = _squad(WARRIOR, Constants.FACTION_PLAYER, "warrior", p0, 6, 3, 0.7)
	var men: Array = mine[0]
	var foe: Array = _squad(SPEAR, Constants.FACTION_ENEMY, "spearman",
		p0 + Vector3(flank_off, 0.0, 18.0), 6, 3, 0.7)
	var foes: Array = foe[0]
	for u in foes:
		(u as Unit).set_tick(false)
	await pframes(4)
	var goal := p0 + Vector3(0.0, 0.0, 40.0)
	for u in men:
		var uu := u as Unit
		uu.command_move(goal + (uu.global_position - p0), false, Vector3(0, 0, 1), false, true)
	var engaged := 0
	var arrived := false
	for _i in range(60 * 30):
		await get_tree().physics_frame
		engaged = 0
		var near_goal := 0
		for u in men:
			var uu := u as Unit
			if not is_instance_valid(uu) or uu.is_dead():
				continue
			var t = uu.attack_target
			if t != null and is_instance_valid(t) and foes.has(t):
				engaged += 1
			if uu.global_position.distance_to(goal) < 4.0:
				near_goal += 1
		if engaged >= 3:
			break
		if near_goal >= 5:
			arrived = true
			break
	_kill_all(men)
	_kill_all(foes)
	await pframes(4)
	return [engaged, arrived]
