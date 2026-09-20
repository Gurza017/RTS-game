extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: НАБЕГ СВИНОКОННИЦЫ И КОНТРАТАКА КОПЕЙЩИКОВ (спринт 15, блок 6)
## ═══════════════════════════════════════════════════════════════════════════
## ЗАКАЗ ВЛАДЕЛЬЦА:
##   • чардж — ТОЛЬКО после прямолинейного бега на 10+ м; вплотную из стоячего
##     положения запрещён (Double Charge Bug);
##   • удар по рядам: первая ячейка — гибель, вторая — отлёт, падение и 30 %
##     макс. запаса, третья и дальше — плавный толчок назад;
##   • копейщики в «Защите» со «Стеной копий» (forge spearman_1d, спринт 18)
##     гасят чардж целиком: ноль толчка, всадник встаёт и получает от копий
##     вдвое, фаланга его медленно отталкивает.
##
## Числа — из конфига (правило 10), ожидание — физкадрами (правило 11). Ряды
## ставятся с шагом charge_row_depth ВДОЛЬ удара, чтобы ряд стенда совпадал с
## рядом механики, а не размазывался по двум.
## Запуск: godot --headless --path . res://qa_boar_rider_charge/Test.tscn

const _UStats := preload("res://scripts/unit_stats_config.gd")
const RIDER := "res://scenes/units/GoblinPigRider.tscn"
const WARRIOR := "res://scenes/units/Warrior.tscn"
const SPEAR := "res://scenes/units/Spearman.tscn"
const COLS := 4
const RANKS := 3

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
	print("\n═════ ИТОГ qa_boar_rider_charge: прошло %d, провалов: %d ═════"
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

## Блок COLS × RANKS: колонны поперёк удара (по X), шеренги вдоль (по Z),
## шаг шеренг — ровно глубина ряда механики. Возвращает [men, sid]
func _block(path: String, fac: int, kind: String, at: Vector3, rank_gap: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(COLS * RANKS):
		var col: int = i % COLS
		var rank: int = i / COLS
		var p := at + Vector3((float(col) - float(COLS - 1) * 0.5) * 0.7, 0.0,
			float(rank) * rank_gap)
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
	# Площадка далеко за краем карты, как у qa_cavalry: ни воды, ни рельефа
	# плато, ни чужих отрядов — границы мира выключены
	GameManager.world_bounds_enabled = false
	await pframes(4)
	_check_config()
	await _check_runup()
	await _check_rows()
	await _check_counter()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _check_config() -> void:
	print("\n═════ A. КОНФИГ ═════")
	var runup: float = _UStats.stat("goblin_rider", "charge_min_runup", 0.0)
	var rng: float = _UStats.stat("goblin_rider", "charge_range", 0.0)
	var reach: float = _UStats.stat("goblin_rider", "attack_range", 0.0)
	verdict("A1 разгон засчитывается только после 10+ м", runup >= 10.0 - 1e-6,
		"charge_min_runup %.1f" % runup)
	# Разгон начинается за charge_range и кончается касанием на attack_range:
	# набрать 10 м можно только если между ними эти метры вообще есть
	verdict("A2 дистанция начала разгона вмещает нужный пробег",
		rng - reach >= runup, "разгон с %.1f м, касание на %.1f м → пробег %.1f"
			% [rng, reach, rng - reach])
	verdict("A3 ряды заданы: гибель первой ячейки, доля второй, глубина ряда",
		int(_UStats.stat("goblin_rider", "charge_row_kill", 0)) >= 1
		and _UStats.stat("goblin_rider", "charge_row2_frac", 0.0) > 0.0
		and _UStats.stat("goblin_rider", "charge_row_depth", 0.0) > 0.0)

# ═════════════════════════════════════════════════════════════════════════════
func _check_runup() -> void:
	print("\n═════ B. РАЗГОН: ТОЛЬКО ПОСЛЕ 10 м ПО ПРЯМОЙ ═════")
	var runup: float = _UStats.stat("goblin_rider", "charge_min_runup", 0.0)
	var rng: float = _UStats.stat("goblin_rider", "charge_range", 0.0)
	var depth: float = _UStats.stat("goblin_rider", "charge_row_depth", 1.1)
	var p0 := Vector3(-1200.0, 0.0, -1200.0)
	var blk: Array = _block(WARRIOR, Constants.FACTION_PLAYER, "warrior", p0, depth)
	var men: Array = blk[0]
	for u in men:
		(u as Unit).set_tick(false)
	var rider := _spawn(RIDER, Constants.FACTION_GOBLIN, p0 + Vector3(0.0, 0.0, -(rng + 12.0)))
	await pframes(4)
	rider.command_attack(men[0], true, true, true)
	var impacted := false
	var from := Vector3.ZERO
	var at := Vector3.ZERO
	var seen_charge := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if not is_instance_valid(rider):
			break
		if rider.is_charging:
			seen_charge = true
			from = rider._charge_from
		if seen_charge and not rider.is_charging and rider._charge_ready == false:
			impacted = true
			at = rider.global_position
			break
	var ran: float = Vector2(at.x - from.x, at.z - from.z).length()
	print("  разгон от %s до %s: пробег %.1f м" % [str(from), str(at), ran])
	verdict("B1 удар с разгона состоялся", impacted)
	verdict("B2 перед ударом всадник ПРОБЕЖАЛ не меньше 10 м", impacted and ran >= runup - 0.5,
		"пробег %.1f при пороге %.1f" % [ran, runup])
	# ── DOUBLE CHARGE: из упора второго удара нет ─────────────────────────
	var kills0: int = rider._trample_kills
	var alive_before: int = 0
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			alive_before += 1
	await pframes(int(Unit.FLING_SEC * 60.0) + 10)
	# Новая цель — живой боец того же блока, всадник стоит в двух шагах
	var next_t: Unit = null
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			next_t = u
			break
	if next_t != null and is_instance_valid(rider):
		rider.command_attack(next_t, true, true, true)
	var second := false
	for _j in range(60 * 5):
		await get_tree().physics_frame
		if not is_instance_valid(rider):
			break
		if rider.is_charging:
			second = true
			break
	verdict("B3 вплотную из стоячего положения разгон НЕ взводится (Double Charge Bug)",
		not second and rider._trample_kills == kills0,
		"повторный разгон=%s, раздавлено ещё %d" % [str(second), rider._trample_kills - kills0])
	if is_instance_valid(rider):
		rider.take_damage(1e9)
	_kill_all(men)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _check_rows() -> void:
	print("\n═════ C. УДАР ПО РЯДАМ ═════")
	var rng: float = _UStats.stat("goblin_rider", "charge_range", 0.0)
	var depth: float = _UStats.stat("goblin_rider", "charge_row_depth", 1.1)
	var kill_n: int = int(_UStats.stat("goblin_rider", "charge_row_kill", 1))
	var frac2: float = _UStats.stat("goblin_rider", "charge_row2_frac", 0.3)
	var p0 := Vector3(-1300.0, 0.0, -1300.0)
	# Третий ряд обязан лежать ВНУТРИ круга брызг (charge_splash): накрывает
	# удар только его — шаг шеренг берётся так, чтобы ряд 2 попал в круг, а
	# округление по charge_row_depth по-прежнему давало ряды 0/1/2
	var splash: float = _UStats.stat("goblin_rider", "charge_splash", 2.0)
	var gap: float = minf(depth, splash * 0.45)
	var blk: Array = _block(WARRIOR, Constants.FACTION_PLAYER, "warrior", p0, gap)
	var men: Array = blk[0]
	for u in men:
		(u as Unit).set_tick(false)
	var pos0: Dictionary = {}
	for u in men:
		pos0[u] = (u as Unit).global_position
	var rider := _spawn(RIDER, Constants.FACTION_GOBLIN, p0 + Vector3(0.0, 0.0, -(rng + 12.0)))
	await pframes(4)
	# Цель — середина первой шеренги: удар приходит строго вдоль рядов
	rider.command_attack(men[1], true, true, true)
	var impacted := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if not is_instance_valid(rider):
			break
		if not rider.is_charging and rider._charge_ready == false and rider._trample_kills > 0:
			impacted = true
			break
	verdict("C0 удар состоялся", impacted)
	if not impacted:
		_kill_all(men)
		return
	# ── ПОСЛЕ УДАРА ВСЕМ ВОЗВРАЩАЕТСЯ ТИК ──────────────────────────────────
	# Отлёт и плавный толчок — СКОРОСТЬ, которую интегрирует тик самой жертвы
	# (та же ловушка, что у зонда толчка в qa_knights_push: замороженный
	# стоит на 0.00 м). Замораживали их только ради геометрии рядов в миг удара
	for u in men:
		if is_instance_valid(u):
			(u as Unit).set_tick(true)
	await pframes(3)
	# Ряды по номеру шеренги стенда: 0 — первая, 1 — вторая, 2 — третья
	var dead_r := [0, 0, 0]
	var down_r := [0, 0, 0]
	var hurt_r := [0, 0, 0]
	for i in range(men.size()):
		var raw = men[i]
		var rank: int = i / COLS
		# Правило 5: погибший первого ряда уже освобождён — сырая ссылка первой
		if raw == null or not is_instance_valid(raw) or (raw as Unit).is_dead():
			dead_r[rank] += 1
			continue
		var u: Unit = raw
		if u._down_until_ms > 0:
			down_r[rank] += 1
		var lost: float = 1.0 - u.current_health / u.max_health
		if lost > 0.08:
			hurt_r[rank] += 1
	print("  погибли по рядам %s, лежат %s, ранены %s" % [str(dead_r), str(down_r), str(hurt_r)])
	verdict("C1 первая ячейка: ровно %d погиб на месте" % kill_n, dead_r[0] == kill_n,
		"в первом ряду погибло %d" % dead_r[0])
	verdict("C2 второй ряд: живы, сбиты с ног и ранены (не погиб никто)",
		dead_r[1] == 0 and down_r[1] >= COLS - 1 and hurt_r[1] >= COLS - 1,
		"лежат %d из %d, ранены %d" % [down_r[1], COLS, hurt_r[1]])
	# Доля второго ряда: через броню, поэтому «около 30 %» — коридор
	var lost2: Array = []
	for i in range(COLS, COLS * 2):
		var raw2 = men[i]
		if raw2 != null and is_instance_valid(raw2) and not (raw2 as Unit).is_dead():
			var u: Unit = raw2
			lost2.append(1.0 - u.current_health / u.max_health)
	var lost_mid: float = 0.0
	if not lost2.is_empty():
		lost2.sort()
		lost_mid = float(lost2[lost2.size() / 2])
	verdict("C3 второй ряд потерял около %.0f %% запаса (через броню)" % (frac2 * 100.0),
		lost_mid > frac2 * 0.4 and lost_mid <= frac2 + 0.02,
		"медиана потерь %.0f %%" % (lost_mid * 100.0))
	verdict("C4 третий ряд: не погиб и не упал", dead_r[2] == 0 and down_r[2] == 0,
		"погибло %d, лежат %d" % [dead_r[2], down_r[2]])
	# Плавный толчок третьего ряда — смещение назад за время разлёта
	await pframes(int(Unit.FLING_SEC * 60.0) + 10)
	var pushed := 0
	for i in range(COLS * 2, COLS * 3):
		var raw3 = men[i]
		if raw3 == null or not is_instance_valid(raw3) or (raw3 as Unit).is_dead():
			continue
		var u: Unit = raw3
		var dz: float = u.global_position.z - (pos0[u] as Vector3).z
		if dz > 0.25:
			pushed += 1
	verdict("C5 третий ряд плавно оттолкнут назад", pushed >= 1,
		"сдвинуто назад %d из %d" % [pushed, COLS])
	# Второй ряд встаёт и возвращается в бой
	for u in men:
		if is_instance_valid(u):
			(u as Unit).set_tick(true)
	await pframes(int(Unit.CHARGE_ROW_KNOCKDOWN_SEC * 60.0) + 40)
	var up := 0
	var fighting := 0
	for i in range(COLS, COLS * 2):
		var raw4 = men[i]
		if raw4 == null or not is_instance_valid(raw4) or (raw4 as Unit).is_dead():
			continue
		var u: Unit = raw4
		if u._down_until_ms == 0:
			up += 1
		if u.attack_target != null or u.state == Unit.State.ATTACKING:
			fighting += 1
	verdict("C6 второй ряд встал и снова в бою", up >= 1 and fighting >= 1,
		"встали %d, в бою %d" % [up, fighting])
	if is_instance_valid(rider):
		rider.take_damage(1e9)
	_kill_all(men)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _check_counter() -> void:
	print("\n═════ D. КОНТРАТАКА КОПЕЙЩИКОВ ═════")
	var rng: float = _UStats.stat("goblin_rider", "charge_range", 0.0)
	GameManager.finish_research(Constants.FACTION_PLAYER, "spearman_1d")
	var p0 := Vector3(-1400.0, 0.0, -1400.0)
	var blk: Array = _block(SPEAR, Constants.FACTION_PLAYER, "spearman", p0, 0.7)
	var men: Array = blk[0]
	var sid: int = blk[1]
	verdict("D0 «Стена копий» изучена и виден отряду (режим включён по умолчанию)",
		GameManager.spear_wall_ready(sid))
	for u in men:
		var uu := u as Unit
		uu.set_stance("defense")
		uu._facing = Vector3(0.0, 0.0, -1.0)   # лицом к всаднику (он идёт с −Z)
	await pframes(6)
	verdict("D0б копейщик в обороне со стеной отвечает «стена активна»",
		(men[0] as Unit).spear_wall_active())
	var pos0: Dictionary = {}
	for u in men:
		pos0[u] = (u as Unit).global_position
	var rider := _spawn(RIDER, Constants.FACTION_GOBLIN, p0 + Vector3(0.0, 0.0, -(rng + 12.0)))
	await pframes(4)
	var hp_r0: float = rider.current_health
	rider.command_attack(men[1], true, true, true)
	var impacted := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if not is_instance_valid(rider) or rider.is_dead():
			break
		if not rider.is_charging and rider._charge_ready == false:
			impacted = true
			break
	verdict("D1 навал на фалангу состоялся (и потрачен)", impacted)
	await pframes(6)
	var dead := 0
	var down := 0
	var moved := 0
	for u in men:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			dead += 1
			continue
		if (u as Unit)._down_until_ms > 0:
			down += 1
		if (u as Unit).global_position.distance_to(pos0[u]) > 0.3:
			moved += 1
	verdict("D2 чардж погашен целиком: никто не погиб, не упал и не отлетел",
		dead == 0 and down == 0 and moved == 0,
		"погибло %d, лежат %d, сдвинуто %d" % [dead, down, moved])
	var alive_r: bool = is_instance_valid(rider) and not rider.is_dead()
	verdict("D3 всадник остановлен: помечен стеной и получил урон копий",
		alive_r and rider._counter_hit_until_ms > rider.now_ms and rider.current_health < hp_r0,
		"запас %.0f → %.0f" % [hp_r0, rider.current_health if alive_r else -1.0])
	verdict("D4 напор остановленного всадника — ноль",
		alive_r and rider._push_after_cap() == 0.0,
		"множитель после потолка %.2f" % (rider._push_after_cap() if alive_r else -1.0))
	if alive_r:
		# СПРИНТ 18: вместо «×2 от копий» — замедление −30 % на SPEAR_WALL_SLOW_SEC
		var spd_slow: float = rider._effective_speed()
		var until: int = rider._slow_until_ms
		rider._slow_until_ms = 0
		var spd_norm: float = rider._effective_speed()
		rider._slow_until_ms = until
		verdict("D5 налетевший на стену замедлен на 30 %",
			rider.is_slowed() and absf(spd_slow / maxf(spd_norm, 0.001) - (1.0 - Unit.SPEAR_WALL_SLOW)) < 0.02,
			"×%.2f" % (spd_slow / maxf(spd_norm, 0.001)))
	if is_instance_valid(rider):
		rider.take_damage(1e9)
	_kill_all(men)
	await pframes(4)
