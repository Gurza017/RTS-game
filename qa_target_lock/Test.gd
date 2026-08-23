extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ИЕРАРХИЯ ПРИОРИТЕТОВ ПРИКАЗА (Unit.target_lock)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба владельца: кликаю по вражескому отряду — свой отряд ДЕЛИТСЯ, часть
## бойцов уходит на соседние цели, часть отвлекается на обстрел, лучники ползут
## к цели вместо того чтобы дойти нормальным шагом.
##
## Проверяется ровно объявленная иерархия:
##   A. ЗАМОК ЦЕЛИ  — приказ игрока держит ОДИН вражеский отряд: все бойцы
##      воюют с ним и не разбредаются по чужим отрядам поблизости;
##   B. ГИБЕЛЬ ЖЕРТВЫ — когда конкретная модель падает, замена берётся ИЗ ТОГО
##      ЖЕ отряда, а не «ближайшая на карте»;
##   C. СКОРОСТЬ    — под замком лучник идёт к цели БАЗОВОЙ скоростью, а не на
##      PULL_UP_SPEED (это и было «ползание лучников»);
##   D. ОБСТРЕЛ НЕ СБИВАЕТ — стрелок сбоку не разворачивает запертый отряд
##      (приоритет №1 против №3, авто-агро);
##   E. ЗАМОК СНИМАЕТСЯ — приказом движения и по истреблении вражеского отряда,
##      после чего снова работает обычное авто-агро;
##   F. ЛУЧНИК НЕ ПЕРЕВОДИТ ЗАЛП НА БЛИЖНИХ — приказ по дальнему отряду
##      стрелков держится, даже когда чужие копейщики стоят вдвое ближе и
##      даже когда назначенная цель на время выходит из дальности выстрела.
##
## Запуск: godot --headless --path . res://qa_target_lock/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## physics_frame, а не process_frame: при Engine.max_fps=0 рендер тикает
## быстрее фиксированных 60 Гц физики, и «N process_frame» перестаёт значить
## «N/60 сек игрового времени» (см. CLAUDE.md, ловушка таймингов стендов)
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n: out += " "
	return out

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	return u

func _squad(kind: String, fac: int, center: Vector3, count: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(count):
		var p := center + Vector3(float(i % 5) * 0.6, 0.0, float(i / 5) * 0.6)
		var u := _new(kind, fac, p)
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _sid_of(arr: Array) -> int:
	for u in arr:
		if is_instance_valid(u):
			return (u as Unit).squad_id
	return 0

## Сколько бойцов из men целятся В ОТРЯД sid (а не в кого попало)
func _aiming_at_squad(men: Array, sid: int) -> int:
	var n := 0
	for u in men:
		if not is_instance_valid(u):
			continue
		var t := (u as Unit).attack_target as Unit
		if t != null and is_instance_valid(t) and t.squad_id == sid:
			n += 1
	return n

## Сколько бойцов целятся ХОТЬ В КОГО-ТО ВНЕ отряда sid — это и есть «отряд
## поделился»: ради этого числа стенд и написан
func _aiming_elsewhere(men: Array, sid: int) -> int:
	var n := 0
	for u in men:
		if not is_instance_valid(u):
			continue
		var t := (u as Unit).attack_target
		if t == null or not is_instance_valid(t):
			continue
		var tu := t as Unit
		if tu == null or tu.squad_id != sid:
			n += 1
	return n

func _cleanup(groups: Array) -> void:
	for g in groups:
		for u in g:
			if is_instance_valid(u):
				(u as Node).queue_free()
	await frames(3)

func _run() -> void:
	seed(4242)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	GameManager.world_bounds_enabled = false
	# Туман войны выключаем: половина сцен стенда стоит в неразведанной зоне,
	# а проверяется здесь боевая логика, а не видимость (тот же приём, что в
	# qa_far_wire)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  ИЕРАРХИЯ ПРИОРИТЕТОВ: ЗАМОК ЦЕЛИ ПО ПРИКАЗУ ИГРОКА              ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	await _a_no_split()
	await _b_retarget_within_squad()
	await _c_archer_speed()
	await _d_ignores_harassment()
	await _e_lock_releases()
	await _f_archer_keeps_order()

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %s%s" % [_pad(String(row[0]), 58),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== TARGET LOCK TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ОТРЯД НЕ ДЕЛИТСЯ: рядом с назначенной целью стоит ВТОРОЙ вражеский отряд,
#    к части бойцов он ближе. До замка каждый боец получал СВОЮ ближайшую цель
#    из общего списка врагов (см. SelectionManager._handle_right_click), и
#    выделение расползалось по обоим отрядам
# ═════════════════════════════════════════════════════════════════════════════
func _a_no_split() -> void:
	print("\n═════ A. ОТРЯД НЕ ДЕЛИТСЯ МЕЖДУ ЦЕЛЯМИ ═════")
	var p0 := Vector3(0, 0, 0)
	var men := _squad("spearman", Constants.FACTION_PLAYER, p0, 8)
	# НАЗНАЧЕННАЯ цель — дальше; ОТВЛЕКАЮЩИЙ отряд — заметно ближе и сбоку,
	# чтобы «ближайший враг» и «указанный враг» гарантированно расходились
	var target := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0, 0, 26.0), 8)
	var decoy  := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(14.0, 0, 6.0), 8)
	for u in decoy:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
	var tsid := _sid_of(target)
	var dsid := _sid_of(decoy)

	# ПРИКАЗ ИГРОКА: lock = true, ровно как из SelectionManager по ПКМ
	for u in men:
		(u as Unit).command_attack(target[0], true, true, true)
	await frames(3)

	var locked := 0
	for u in men:
		if bool((u as Unit).target_lock):
			locked += 1
	verdict("A1 замок взведён у всего отряда", locked == men.size(),
		"с замком %d из %d" % [locked, men.size()])

	var on_target := _aiming_at_squad(men, tsid)
	verdict("A2 все нацелены на УКАЗАННЫЙ отряд, а не на ближайший",
		on_target == men.size(),
		"на цель %d из %d, на отвлекающий %d" % [
			on_target, men.size(), _aiming_at_squad(men, dsid)])

	# Наблюдаем весь подход: если отряд «делится», это видно именно в динамике —
	# по дороге кто-то переключается на отвлекающий отряд
	var strayed := 0
	var decoy_hit := 0.0
	for _i in range(1800):
		await get_tree().physics_frame
		strayed = maxi(strayed, _aiming_elsewhere(men, tsid))
		if _alive(target).is_empty():
			break
	for u in decoy:
		if is_instance_valid(u):
			decoy_hit += maxf(0.0, (u as Unit).max_health - (u as Unit).current_health)

	verdict("A3 никто не ушёл на посторонние цели за весь подход",
		strayed == 0, "уходов на чужие цели: %d" % strayed)
	verdict("A4 отвлекающий отряд не получил урона вовсе",
		decoy_hit <= 0.01, "урон отвлекающему: %.1f" % decoy_hit)
	verdict("A5 назначенный отряд действительно разбит",
		_alive(target).size() < 8, "выжило %d из 8" % _alive(target).size())

	await _cleanup([men, target, decoy])

# ═════════════════════════════════════════════════════════════════════════════
# B. ПАЛА ЖЕРТВА — ЗАМЕНА ИЗ ТОГО ЖЕ ОТРЯДА.
#    Раньше замену искал _find_nearest_enemy_in_range, то есть «ближайший на
#    карте», и после первой же смерти отряд начинал растекаться
# ═════════════════════════════════════════════════════════════════════════════
func _b_retarget_within_squad() -> void:
	print("\n═════ B. ЗАМЕНА ЖЕРТВЫ БЕРЁТСЯ ИЗ ЗАПЕРТОГО ОТРЯДА ═════")
	var p0 := Vector3(200, 0, 0)
	var men := _squad("spearman", Constants.FACTION_PLAYER, p0, 6)
	var target := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0, 0, 3.0), 6)
	# Приманка ВПЛОТНУЮ сбоку: после гибели жертвы она была бы ближайшей
	var decoy := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(5.0, 0, 0.0), 4)
	for u in decoy:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
	var tsid := _sid_of(target)

	for u in men:
		(u as Unit).command_attack(target[0], true, true, true)
	await frames(5)

	# Убиваем ровно ту модель, по которой шёл приказ
	if is_instance_valid(target[0]):
		(target[0] as Unit).take_damage(1e9, men[0])
	await frames(30)

	var still_on_squad := _aiming_at_squad(men, tsid)
	var elsewhere := _aiming_elsewhere(men, tsid)
	verdict("B1 после гибели жертвы отряд остался на том же вражеском отряде",
		still_on_squad >= _alive(men).size() - 1 and elsewhere == 0,
		"на отряде %d из %d, на стороне %d" % [
			still_on_squad, _alive(men).size(), elsewhere])

	var kept := 0
	for u in men:
		if is_instance_valid(u) and bool((u as Unit).target_lock):
			kept += 1
	verdict("B2 замок пережил смерть жертвы", kept == _alive(men).size(),
		"с замком %d из %d" % [kept, _alive(men).size()])

	await _cleanup([men, target, decoy])

# ═════════════════════════════════════════════════════════════════════════════
# C. ЛУЧНИК ПОД ЗАМКОМ ИДЁТ БАЗОВОЙ СКОРОСТЬЮ.
#    Это и был «баг ползающих лучников»: _should_pull_up ловит любого бойца
#    отряда, чья цель дальше дистанции удара но ближе attack_range + PULL_UP_MAX,
#    а у лучника это до 34 м — весь путь он шёл на PULL_UP_SPEED (55%)
# ═════════════════════════════════════════════════════════════════════════════
func _c_archer_speed() -> void:
	print("\n═════ C. СКОРОСТЬ ЛУЧНИКА ПОД ПРИКАЗОМ ═════")
	var p0 := Vector3(400, 0, 0)
	var men := _squad("archer", Constants.FACTION_PLAYER, p0, 5)
	# Цель ЗА пределами дальности стрельбы, чтобы был именно ПОДХОД
	var far_z: float = float(_UStatsRange()) + 12.0
	var target := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0, 0, far_z), 5)
	for u in target:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9

	for u in men:
		(u as Unit).command_attack(target[0], true, true, true)
	await frames(5)

	# Мерим ФАКТИЧЕСКУЮ путевую скорость на участке подхода
	var z0: float = (men[0] as Unit).global_position.z
	var t_frames := 120                      # 2 секунды симуляции
	await frames(t_frames)
	var z1: float = (men[0] as Unit).global_position.z
	var got: float = (z1 - z0) / (float(t_frames) / 60.0)
	var base: float = (men[0] as Unit)._base_speed()
	var crawl: float = base * Unit.PULL_UP_SPEED

	print("  прошёл %.2f м/с при базовой %.2f и «ползком» %.2f"
		% [got, base, crawl])
	# Порог посередине между ползком и базовой: попадание в верхнюю половину
	# однозначно отличает «идёт нормально» от «подтягивается рядами»
	verdict("C1 лучник под замком идёт базовой скоростью, а не ползёт",
		got > (base + crawl) * 0.5,
		"фактически %.2f м/с (база %.2f, ползок %.2f)" % [got, base, crawl])

	# ЗАЛП: все стрелки обязаны войти в зону огня и открыть стрельбу
	var fired := 0
	for _i in range(2400):
		await get_tree().physics_frame
		fired = 0
		for u in men:
			if is_instance_valid(u) and (u as Unit).target_in_range():
				fired += 1
		if fired >= men.size():
			break
	verdict("C2 весь отряд лучников вошёл в зону огня (залп)",
		fired >= men.size(), "в зоне огня %d из %d" % [fired, men.size()])

	await _cleanup([men, target])

## Дальность стрельбы лучника из конфига — числа в стенде не хардкодим
func _UStatsRange() -> float:
	var cfg = load("res://scripts/unit_stats_config.gd")
	return float(cfg.stat("archer", "attack_range", 18.0))

# ═════════════════════════════════════════════════════════════════════════════
# D. ОБСТРЕЛ СБОКУ НЕ РАЗВОРАЧИВАЕТ ЗАПЕРТЫЙ ОТРЯД.
#    take_damage поднимал ВЕСЬ отряд в контратаку на стрелка
#    (squad_counter_charge → command_attack(forced) перезаписывал _atk_pending),
#    и приказ игрока тихо подменялся стихийной стычкой
# ═════════════════════════════════════════════════════════════════════════════
func _d_ignores_harassment() -> void:
	print("\n═════ D. ОБСТРЕЛ НЕ СБИВАЕТ С ПРИКАЗА ═════")
	var p0 := Vector3(600, 0, 0)
	var men := _squad("spearman", Constants.FACTION_PLAYER, p0, 6)
	var target := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0, 0, 30.0), 6)
	for u in target:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
	# Стрелки СБОКУ, в пределах COUNTER_CHARGE_RANGE — именно они раньше
	# разворачивали весь отряд на себя
	var snipers := _squad("archer", Constants.FACTION_ENEMY, p0 + Vector3(8.0, 0, 0.0), 4)
	for u in snipers:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
	var tsid := _sid_of(target)
	var ssid := _sid_of(snipers)

	for u in men:
		(u as Unit).command_attack(target[0], true, true, true)
	await frames(3)

	# Бьём отряд «издали» напрямую — тот же путь, что и попадание стрелы.
	# Урон НАРОЧНО символический (1 HP): проверяется реакция на факт обстрела,
	# а не выживаемость. При «честных» 3 HP отряд успевал полечь за время
	# наблюдения, и D2 проходила вхолостую на пустом списке («0 из 0»)
	var switched := 0
	for i in range(900):
		await get_tree().physics_frame
		if i % 30 == 0:
			for u in men:
				if is_instance_valid(u) and is_instance_valid(snipers[0]):
					(u as Unit).take_damage(1.0, snipers[0])
		switched = maxi(switched, _aiming_at_squad(men, ssid))

	verdict("D1 никто не развернулся на стрелков под обстрелом",
		switched == 0, "переключились на стрелков: %d" % switched)
	# ЖИВОЙ ОТРЯД — ЧАСТЬ УСЛОВИЯ, а не фон: без него проверка проходит на
	# пустом списке и ничего не значит
	var d_alive: int = _alive(men).size()
	verdict("D2 отряд жив и всё ещё нацелен на указанную цель",
		d_alive > 0 and _aiming_at_squad(men, tsid) >= d_alive - 1,
		"на цели %d из %d живых" % [_aiming_at_squad(men, tsid), d_alive])

	await _cleanup([men, target, snipers])

# ═════════════════════════════════════════════════════════════════════════════
# E. ЗАМОК СНИМАЕТСЯ: приказом движения (игрок передумал) и по истреблении
#    вражеского отряда (приказ выполнен) — после чего снова работает авто-агро
# ═════════════════════════════════════════════════════════════════════════════
func _e_lock_releases() -> void:
	print("\n═════ E. СНЯТИЕ ЗАМКА ═════")
	var p0 := Vector3(800, 0, 0)
	var men := _squad("spearman", Constants.FACTION_PLAYER, p0, 4)
	var target := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0, 0, 20.0), 4)
	for u in target:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9

	for u in men:
		(u as Unit).command_attack(target[0], true, true, true)
	await frames(3)

	# E1 — ПРИКАЗ ДВИЖЕНИЯ ОТМЕНЯЕТ ЗАМОК
	for u in men:
		(u as Unit).command_move(p0 + Vector3(0, 0, -20.0))
	await frames(2)
	var still := 0
	for u in men:
		if bool((u as Unit).target_lock):
			still += 1
	verdict("E1 приказ движения снимает замок", still == 0,
		"осталось с замком %d из %d" % [still, men.size()])

	# E2 — ИСТРЕБЛЕНИЕ ОТРЯДА СНИМАЕТ ЗАМОК САМО
	for u in men:
		(u as Unit).command_attack(target[0], true, true, true)
	await frames(3)
	for u in target:
		if is_instance_valid(u):
			(u as Unit).max_health = 10.0
			(u as Unit).current_health = 10.0
			(u as Unit).take_damage(1e9, men[0])
	await frames(60)
	var released := 0
	for u in men:
		if is_instance_valid(u) and not bool((u as Unit).target_lock):
			released += 1
	verdict("E2 замок снят сам, когда вражеский отряд выбит",
		released == _alive(men).size(),
		"без замка %d из %d" % [released, _alive(men).size()])

	# E3 — И АВТО-АГРО СНОВА РАБОТАЕТ (приоритет №3 вернулся в силу)
	var fresh := _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0, 0, 3.0), 3)
	for u in fresh:
		(u as Unit).max_health = 1e9
		(u as Unit).current_health = 1e9
	var caught := 0
	for _i in range(600):
		await get_tree().physics_frame
		caught = 0
		for u in men:
			if is_instance_valid(u) and (u as Unit).attack_target != null:
				caught += 1
		if caught >= _alive(men).size():
			break
	verdict("E3 после снятия замка авто-агро снова цепляет врага",
		caught >= maxi(1, _alive(men).size() - 1),
		"зацепили %d из %d" % [caught, _alive(men).size()])

	await _cleanup([men, target, fresh])

# ═════════════════════════════════════════════════════════════════════════════
# F. ЛУЧНИКИ ДЕРЖАТ ПРИКАЗ, А НЕ БЬЮТ ПО БЛИЖНИМ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца дословно: выделяю лучников, ПКМ по вражескому отряду
## лучников — а мои стреляют по копейщикам, которые ближе.
##
## Механизм был такой. Стрелок не преследует (Archer.pursues_target = false):
## стоит назначенной цели отойти за дальность выстрела, и _process_attack
## бросает её и переводит бойца в ПОКОЙ. Замок приказа при этом ОСТАЁТСЯ
## взведённым, но покой обслуживает авто-агро — а оно замка не читало вовсе и
## честно выдавало ближайшего противника. Приказ игрока подменялся молча.
##
## Проверяется поэтому не «сразу после клика» (так работало и раньше), а
## именно этот стык: цель ушла из дальности, рядом стоит кто-то ближе.
func _f_archer_keeps_order() -> void:
	print("
═════ F. ЛУЧНИК НЕ ПЕРЕВОДИТ ЗАЛП НА БЛИЖНИХ ═════")
	var rng: float = _UStatsRange()
	var p0 := Vector3(900, 0, 0)
	var men := _squad("archer", Constants.FACTION_PLAYER, p0, 6)
	# НАЗНАЧЕННЫЙ отряд — вражеские лучники, в пределах выстрела
	var target := _squad("archer", Constants.FACTION_ENEMY,
		p0 + Vector3(0, 0, rng * 0.8), 6)
	# ОТВЛЕЧЕНИЕ — копейщики ВДВОЕ ближе и сбоку: ровно то, во что стрелки
	# начинали бить вместо приказа
	var decoy := _squad("spearman", Constants.FACTION_ENEMY,
		p0 + Vector3(rng * 0.35, 0, 0.0), 6)
	# БЕССМЕРТНЫ ВСЕ ТРОЕ, и свои в том числе. Первый прогон стенда шёл без
	# этого: вражеские лучники и копейщики выбивали наблюдаемый отряд за время
	# наблюдения, и проверки F3-F5 честно проходили на пустом списке («0 из 0»)
	for arr in [men, target, decoy]:
		for u in arr:
			(u as Unit).max_health = 1e9
			(u as Unit).current_health = 1e9
	var tsid := _sid_of(target)
	var dsid := _sid_of(decoy)

	for u in men:
		(u as Unit).command_attack(target[0], true, true, true)
	await frames(60)
	verdict("F1 залп ушёл по назначенному отряду, а не по ближним",
		_aiming_at_squad(men, tsid) == _alive(men).size()
			and _aiming_at_squad(men, dsid) == 0,
		"на цели %d, на отвлечении %d из %d" % [
			_aiming_at_squad(men, tsid), _aiming_at_squad(men, dsid),
			_alive(men).size()])

	# ── ЦЕЛЬ ОТОШЛА ЗА ДАЛЬНОСТЬ ВЫСТРЕЛА ──────────────────────────────────
	# Переносим её руками: важно не КАК она ушла, а что стрелок остался без
	# цели, имея под боком чужой отряд ближе
	for u in target:
		if is_instance_valid(u):
			(u as Unit).global_position += Vector3(0, 0, rng * 0.9)
			(u as Unit).sync_row()
	var stolen := 0
	var lock_kept := 0
	for i in range(600):
		await get_tree().physics_frame
		stolen = maxi(stolen, _aiming_at_squad(men, dsid))
	for u in men:
		if is_instance_valid(u) and bool((u as Unit).target_lock):
			lock_kept += 1
	verdict("F2 ушедшая за дальность цель не отдаёт залп ближним",
		stolen == 0, "переключились на копейщиков: %d" % stolen)
	verdict("F3 замок приказа пережил выход цели из дальности",
		lock_kept == _alive(men).size(),
		"замок держат %d из %d" % [lock_kept, _alive(men).size()])

	# ── ЦЕЛЬ ВЕРНУЛАСЬ — ОГОНЬ ВОЗОБНОВЛЯЕТСЯ САМ ──────────────────────────
	for u in target:
		if is_instance_valid(u):
			(u as Unit).global_position -= Vector3(0, 0, rng * 0.9)
			(u as Unit).sync_row()
	await frames(240)
	verdict("F4 вернувшаяся цель снова принимает залп",
		_aiming_at_squad(men, tsid) >= _alive(men).size() - 1,
		"на цели %d из %d" % [_aiming_at_squad(men, tsid), _alive(men).size()])

	# ── ОТРЯД ИСТРЕБЛЁН — ПРИКАЗ ИСЧЕРПАН, АВТО-АГРО СНОВА РАБОТАЕТ ────────
	for u in target:
		if is_instance_valid(u):
			(u as Unit).queue_free()
	await frames(300)
	verdict("F5 после истребления цели лучники сами берут ближних",
		_aiming_at_squad(men, dsid) > 0,
		"на отвлечении %d из %d" % [_aiming_at_squad(men, dsid), _alive(men).size()])

	await _cleanup([men, decoy])
