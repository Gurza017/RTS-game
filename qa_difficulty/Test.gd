extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СЛОЖНОСТЬ И СОХРАНЕНИЕ ПАРТИИ
## ═══════════════════════════════════════════════════════════════════════════
##   A ПРЕСЕТЫ      — таблица полна, ключи знакомы, порядок задан
##   B НЕЙТРАЛЬНОСТЬ — «Обычная» не меняет НИ ОДНОГО базового числа
##   C МОНОТОННОСТЬ — Easy ≤ Normal ≤ Hard по каждой ручке, и без вырождения
##   D ГРАНИЦЫ      — ранг орды и лимиты не вылезают за границы своих таблиц
##   E ФАЙЛ         — заголовок, версии, чужой файл, пустой слот
##   F КРУГОВОЙ РЕЙС — слепок живой партии → файл → слепок обратно
##   G ВОССТАНОВЛЕНИЕ — слепок применён к живой карте: войско, отряды, ранги
##   H ПОЛНЫЙ ЦИКЛ  — файл → новая сцена Main с тем же зерном → та же партия
##   I ЭКРАНЫ       — меню паузы, слоты сохранения и главное меню строятся
##
## ЧИСЛА НЕ ХАРДКОДЯТСЯ. Стенд не знает, что на Hard лимит в полтора раза выше:
## он читает пресеты и проверяет СВОЙСТВА (нейтральность Normal, монотонность
## ряда, границы). Владелец правит числа — стенд едет за ними сам.

const _Diff  := preload("res://scripts/game_difficulty_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _Save  := preload("res://scripts/SaveLoadManager.gd")

var main = null
var _pass := 0
var _fail := 0
## Что стояло до стенда: сложность — статика, переживающая сцену, и оставить её
## сдвинутой означало бы испортить следующий стенд в том же прогоне
var _saved_difficulty := ""

func _ready() -> void:
	call_deferred("_run")

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	_saved_difficulty = _Diff.current()
	_a_presets()
	_b_normal_is_neutral()
	_c_monotonic()
	_d_bounds()
	_e_file()
	await _f_round_trip()
	await _g_restore()
	await _h_full_cycle()
	await _i_menus()
	_Diff.set_current(_saved_difficulty)
	print("\n═════ ИТОГ ═════")
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("=== QA_DIFFICULTY DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ТАБЛИЦА ПРЕСЕТОВ
# ═════════════════════════════════════════════════════════════════════════════
func _a_presets() -> void:
	print("\n═════ A. ПРЕСЕТЫ ═════")
	var ok1 := _Diff.ORDER.size() >= 3
	for id in _Diff.ORDER:
		if not _Diff.PRESETS.has(String(id)):
			ok1 = false
	verdict("A1 каждый уровень из ORDER есть в таблице", ok1,
		"уровней: %d" % _Diff.ORDER.size())

	# Подпись и подсказка — не для красоты: без них кнопка в меню безымянна
	var ok2 := true
	for id in _Diff.ORDER:
		if _Diff.label(String(id)).is_empty() or _Diff.hint(String(id)).is_empty():
			ok2 = false
	verdict("A2 у каждого уровня есть подпись и подсказка", ok2)

	# Незнакомый ключ обязан схлопываться в DEFAULT, а не оставлять игру без
	# правил: файл настроек правится руками и переживает смену версий
	_Diff.set_current("не-такой-уровень")
	verdict("A3 незнакомый уровень схлопывается в стандартный",
		_Diff.current() == _Diff.DEFAULT, "получили %s" % _Diff.current())

# ═════════════════════════════════════════════════════════════════════════════
# B. «ОБЫЧНАЯ» НЕ МЕНЯЕТ НИЧЕГО
# ═════════════════════════════════════════════════════════════════════════════
# ГЛАВНАЯ ПРОВЕРКА ВСЕГО СТЕНДА. Сложности появились поверх баланса, который
# владелец настраивал без них, и Normal обязан быть в точности прежней игрой.
# Сдвинься здесь хоть один множитель — и все прежние замеры перестали бы
# что-либо значить.
func _b_normal_is_neutral() -> void:
	print("\n═════ B. NORMAL НЕЙТРАЛЕН ═════")
	_Diff.set_current(_Diff.NORMAL)
	var bad: Array = []
	for uid in _AICfg.combat_types():
		var u := String(uid)
		if _Diff.ai_squad_limit(u) != _AICfg.squad_limit(u):
			bad.append("%s %d≠%d" % [u, _Diff.ai_squad_limit(u), _AICfg.squad_limit(u)])
	verdict("B1 лимиты отрядов равны базовым", bad.is_empty(), str(bad))
	verdict("B2 потолок рабочих равен базовому",
		_Diff.ai_worker_limit() == _AICfg.WORKER_LIMIT,
		"%d против %d" % [_Diff.ai_worker_limit(), _AICfg.WORKER_LIMIT])
	verdict("B3 мирная фаза равна базовой",
		is_equal_approx(_Diff.ai_peace_seconds(), _AICfg.PEACE_SECONDS))
	verdict("B4 время найма не тронуто ни у кого",
		is_equal_approx(_Diff.train_time(Constants.FACTION_ENEMY, 30.0), 30.0)
		and is_equal_approx(_Diff.train_time(Constants.FACTION_PLAYER, 30.0), 30.0))
	verdict("B5 спячка орды равна базовой",
		is_equal_approx(_Diff.goblin_dormant_sec(), _GobCfg.DORMANT_UNTIL_SEC))
	verdict("B6 доход хижины равен базовому",
		is_equal_approx(_Diff.goblin_hut_food_per_min(), _GobCfg.HUT_FOOD_PER_MIN))
	# Стартовый состав орды на Normal обязан совпасть с конфигом ПОСТРОЧНО
	var base: Array = _GobCfg.start_squads()
	var got: Array = _Diff.goblin_start_squads()
	var same: bool = base.size() == got.size()
	if same:
		for i in range(base.size()):
			var a: Dictionary = base[i]
			var b: Dictionary = got[i]
			if int(a["vet"]) != int(b["vet"]) or int(a["count"]) != int(b["count"]) \
					or String(a["unit"]) != String(b["unit"]):
				same = false
	verdict("B7 стартовая орда совпадает с конфигом построчно", same,
		"строк %d против %d" % [got.size(), base.size()])
	# Ресурсы игрока сложность не трогает НИ НА ОДНОМ уровне (см. B8 ниже),
	# а на Normal не трогает и ресурсы ИИ
	var ai_base: Dictionary = _UCfg.starting_resources(Constants.FACTION_ENEMY)
	var ai_got: Dictionary = _Diff.starting_resources(Constants.FACTION_ENEMY, ai_base)
	var res_same := true
	for k in ai_base:
		if not is_equal_approx(float(ai_base[k]), float(ai_got.get(k, -1.0))):
			res_same = false
	verdict("B8 стартовый запас ИИ равен базовому", res_same)

# ═════════════════════════════════════════════════════════════════════════════
# C. РЯД МОНОТОНЕН
# ═════════════════════════════════════════════════════════════════════════════
# «Тяжелее» обязано означать «противнику лучше» ПО КАЖДОЙ ручке. Проверяется
# СВОЙСТВО ряда, а не конкретные числа: владелец вправе поменять любое из них,
# но не вправе сделать Hard слабее Easy — это была бы уже опечатка, а не баланс.
func _c_monotonic() -> void:
	print("\n═════ C. EASY ≤ NORMAL ≤ HARD ═════")
	var limits: Array = []
	var workers: Array = []
	var peace: Array = []
	var train: Array = []
	var food: Array = []
	var dormant: Array = []
	for id in [_Diff.EASY, _Diff.NORMAL, _Diff.HARD]:
		_Diff.set_current(String(id))
		limits.append(_Diff.ai_total_squad_limit())
		workers.append(_Diff.ai_worker_limit())
		peace.append(_Diff.ai_peace_seconds())
		train.append(_Diff.train_time(Constants.FACTION_ENEMY, 30.0))
		food.append(_Diff.goblin_hut_food_per_min())
		dormant.append(_Diff.goblin_dormant_sec())
	verdict("C1 лимит армии растёт с сложностью",
		int(limits[0]) < int(limits[1]) and int(limits[1]) < int(limits[2]),
		"отрядов: %s" % str(limits))
	verdict("C2 потолок рабочих растёт",
		int(workers[0]) < int(workers[1]) and int(workers[1]) < int(workers[2]),
		str(workers))
	verdict("C3 мирная фаза укорачивается",
		float(peace[0]) > float(peace[1]) and float(peace[1]) > float(peace[2]),
		str(peace))
	verdict("C4 найм ускоряется (время падает)",
		float(train[0]) > float(train[1]) and float(train[1]) > float(train[2]),
		str(train))
	verdict("C5 доход орды растёт",
		float(food[0]) < float(food[1]) and float(food[1]) < float(food[2]),
		str(food))
	verdict("C6 орда просыпается раньше",
		float(dormant[0]) > float(dormant[1]) and float(dormant[1]) > float(dormant[2]),
		str(dormant))
	# Стартовый гарнизон ИИ появляется не раньше, чем на самой тяжёлой
	_Diff.set_current(_Diff.HARD)
	var hard_start: int = _Diff.ai_start_squads().size()
	_Diff.set_current(_Diff.EASY)
	var easy_start: int = _Diff.ai_start_squads().size()
	verdict("C7 стартовых отрядов у ИИ на Hard не меньше, чем на Easy",
		hard_start >= easy_start, "%d против %d" % [hard_start, easy_start])

# ═════════════════════════════════════════════════════════════════════════════
# D. ГРАНИЦЫ
# ═════════════════════════════════════════════════════════════════════════════
func _d_bounds() -> void:
	print("\n═════ D. ГРАНИЦЫ ═════")
	var lvl_ok := true
	var picks_ok := true
	var newbies_ok := true
	var base: Array = _GobCfg.start_squads()
	for id in _Diff.ORDER:
		_Diff.set_current(String(id))
		var got: Array = _Diff.goblin_start_squads()
		for i in range(got.size()):
			var row: Dictionary = got[i]
			var v: int = int(row["vet"])
			if v < 0 or v > _UCfg.VET_BANNER_TIERS.size():
				lvl_ok = false
			if int(row["picks"]) > maxi(v, 0):
				picks_ok = false
			# НОВОБРАНЕЦ ОСТАЁТСЯ НОВОБРАНЦЕМ НА ЛЮБОЙ СЛОЖНОСТИ: сдвиг ранга
			# двигает заслуженное, а не раздаёт его тем, кому оно не положено
			if int((base[i] as Dictionary)["vet"]) == 0 and v != 0:
				newbies_ok = false
	verdict("D1 ранг орды в границах таблицы знамён", lvl_ok)
	verdict("D2 наград не больше, чем ступеней ранга", picks_ok)
	verdict("D3 отряды без ранга его не получают ни на одной сложности", newbies_ok)

	# Род войск, выключенный в базе (лимит 0), сложность включать не вправе
	var off_ok := true
	for id in _Diff.ORDER:
		_Diff.set_current(String(id))
		for uid in _UCfg.STATS.keys():
			var u := String(uid)
			if _AICfg.squad_limit(u) == 0 and _Diff.ai_squad_limit(u) != 0:
				off_ok = false
	verdict("D4 выключенный род войск сложность не включает", off_ok)
	_Diff.set_current(_Diff.NORMAL)

# ═════════════════════════════════════════════════════════════════════════════
# E. ФАЙЛ СОХРАНЕНИЯ
# ═════════════════════════════════════════════════════════════════════════════
const TEST_SLOT := 3

func _e_file() -> void:
	print("\n═════ E. ФАЙЛ ═════")
	# Чистим слот стенда: прошлый прогон мог его оставить
	if FileAccess.file_exists(_Save.slot_path(TEST_SLOT)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			_Save.slot_path(TEST_SLOT)))
	verdict("E1 пустой слот честно отвечает «нет сохранения»",
		not _Save.has_save(TEST_SLOT))
	var st: Dictionary = _Save.load_state(TEST_SLOT)
	verdict("E2 чтение пустого слота даёт ошибку, а не мусор",
		st.has("__error"), String(st.get("__error", "")))

	# ЧУЖОЙ ФАЙЛ ОТСЕИВАЕТСЯ МАГИЕЙ, А НЕ ПАДЕНИЕМ. Подсунуть вместо
	# сохранения что угодно — обычное дело: игрок копирует файлы руками
	var f := FileAccess.open(_Save.slot_path(TEST_SLOT), FileAccess.WRITE)
	f.store_string("это не сохранение, а просто текст подлиннее шестнадцати байт")
	f.close()
	var st2: Dictionary = _Save.load_state(TEST_SLOT)
	verdict("E3 чужой файл отклонён по магии", st2.has("__error"),
		String(st2.get("__error", "")))
	# Подпись слота не должна падать на битом файле — она рисуется на кнопке
	verdict("E4 подпись битого слота не роняет интерфейс",
		not _Save.slot_label(TEST_SLOT).is_empty(), _Save.slot_label(TEST_SLOT))

# ═════════════════════════════════════════════════════════════════════════════
# F. КРУГОВОЙ РЕЙС: ПАРТИЯ → ФАЙЛ → ПАРТИЯ
# ═════════════════════════════════════════════════════════════════════════════
# Стенд НЕ перезапускает сцену (загрузка партии делает именно это, и внутри
# одного стенда такое не проверить): он сверяет СЛЕПОК. Слепок — то
# единственное, что уезжает в файл, и если он доехал обратно без потерь, то
# доедет и до восстановления.
func _f_round_trip() -> void:
	print("\n═════ F. КРУГОВОЙ РЕЙС ═════")
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	await pframes(4)

	verdict("F1 зерно мира записано и не нулевое", int(main.world_seed) != 0,
		"seed=%d" % int(main.world_seed))

	var before: Dictionary = _Save.capture(main)
	var units: Dictionary = before.get("units", {})
	var n_units: int = (units.get("type", PackedInt32Array()) as PackedInt32Array).size()
	var n_squads: int = (before.get("squads", []) as Array).size()
	var n_bld: int = (before.get("buildings", []) as Array).size()
	print("  слепок: бойцов %d, отрядов %d, построек %d" % [n_units, n_squads, n_bld])
	verdict("F2 в слепке есть войско, отряды и постройки",
		n_units > 0 and n_squads > 0 and n_bld > 0)

	# Колонки обязаны быть согласованы по длине: рассинхрон здесь означал бы
	# бойца без отряда или без точки — и вылет при восстановлении
	var ok3: bool = (units["faction"] as PackedInt32Array).size() == n_units \
		and (units["squad"] as PackedInt32Array).size() == n_units \
		and (units["hp"] as PackedFloat32Array).size() == n_units \
		and (units["pos"] as PackedFloat32Array).size() == n_units * 3
	verdict("F3 колонки бойцов согласованы по длине", ok3)

	var err: String = _Save.save_game(main, TEST_SLOT)
	verdict("F4 запись в слот прошла", err.is_empty(), err)
	verdict("F5 слот теперь занят", _Save.has_save(TEST_SLOT))

	var back: Dictionary = _Save.load_state(TEST_SLOT)
	verdict("F6 файл прочитан без ошибки", not back.has("__error"),
		String(back.get("__error", "")))
	if back.has("__error"):
		return

	var u2: Dictionary = back.get("units", {})
	var n2: int = (u2.get("type", PackedInt32Array()) as PackedInt32Array).size()
	verdict("F7 бойцов доехало столько же, сколько было",
		n2 == n_units, "%d против %d" % [n2, n_units])
	verdict("F8 отрядов доехало столько же",
		(back.get("squads", []) as Array).size() == n_squads)
	verdict("F9 построек доехало столько же",
		(back.get("buildings", []) as Array).size() == n_bld)

	var m1: Dictionary = before.get("meta", {})
	var m2: Dictionary = back.get("meta", {})
	verdict("F10 зерно мира доехало без изменений",
		int(m1.get("world_seed", -1)) == int(m2.get("world_seed", -2)),
		"%d → %d" % [int(m1.get("world_seed", -1)), int(m2.get("world_seed", -2))])
	verdict("F11 сложность доехала",
		String(m1.get("difficulty", "")) == String(m2.get("difficulty", "?")))

	# Точки бойцов доехали ЧИСЛАМИ, а не «примерно»: PackedFloat32Array хранит
	# одинарную точность, и сравнение идёт с её допуском, а не с нулевым
	var pos1: PackedFloat32Array = units["pos"]
	var pos2: PackedFloat32Array = u2["pos"]
	var worst := 0.0
	for i in range(mini(pos1.size(), pos2.size())):
		worst = maxf(worst, absf(pos1[i] - pos2[i]))
	verdict("F12 точки бойцов доехали без потерь", worst < 0.001,
		"худшее расхождение %0.5f м" % worst)

	# Ранги отрядов — то, ради чего вообще стоит городить сохранение: без них
	# загруженная орда вышла бы новобранцами
	var lv1 := 0
	for row in (before.get("squads", []) as Array):
		lv1 += int((row as Dictionary).get("level", 0))
	var lv2 := 0
	for row in (back.get("squads", []) as Array):
		lv2 += int((row as Dictionary).get("level", 0))
	verdict("F13 сумма рангов отрядов доехала", lv1 == lv2 and lv1 > 0,
		"%d → %d" % [lv1, lv2])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		_Save.slot_path(TEST_SLOT)))

# ═════════════════════════════════════════════════════════════════════════════
# G. ВОССТАНОВЛЕНИЕ НА ЖИВОЙ КАРТЕ
# ═════════════════════════════════════════════════════════════════════════════
# Блок F проверил, что слепок доезжает до файла и обратно. Здесь проверяется
# ВТОРАЯ половина пути: что apply() действительно СНОСИТ живое и ставит
# сохранённое. Сцена та же, что и в F, — карта уже пересеяна нужным зерном, и
# это ровно то состояние, в котором apply() зовётся в настоящей загрузке
# (Main.start_game, самым последним делом).
func _g_restore() -> void:
	print("
═════ G. ВОССТАНОВЛЕНИЕ ═════")
	if main == null or not is_instance_valid(main):
		verdict("G0 сцена жива", false, "блок F её не поднял")
		return
	var before: Dictionary = _Save.capture(main)
	var n_before: int = (before["units"]["type"] as PackedInt32Array).size()
	var sq_before: int = (before["squads"] as Array).size()
	var gold_before: float = ResourceManager.get_amount(
		Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD)

	# Портим состояние ЗАМЕТНО: тратим золото и сносим отряд целиком. Если
	# apply() не работает, эти следы останутся и проверки их поймают
	ResourceManager.set_amount(Constants.FACTION_PLAYER,
		Constants.RESOURCE_GOLD, 1.0)
	var victims: Array = []
	for s in GameManager.squads_of_faction(Constants.FACTION_GOBLIN):
		victims = GameManager.squad_members(int((s as Dictionary)["id"]))
		break
	for u in victims:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage((u as Unit).max_health * 1000.0 + 1e6, null)
	await pframes(4)
	var n_hurt: int = (_Save.capture(main)["units"]["type"] as PackedInt32Array).size()
	verdict("G1 порча состояния действительно состоялась",
		n_hurt < n_before, "было %d, стало %d" % [n_before, n_hurt])

	_Save.apply(main, before)
	await pframes(6)

	var after: Dictionary = _Save.capture(main)
	var n_after: int = (after["units"]["type"] as PackedInt32Array).size()
	verdict("G2 войско восстановлено в прежней численности",
		n_after == n_before, "%d против %d" % [n_after, n_before])
	verdict("G3 отрядов столько же",
		(after["squads"] as Array).size() == sq_before,
		"%d против %d" % [(after["squads"] as Array).size(), sq_before])
	verdict("G4 склад восстановлен",
		is_equal_approx(ResourceManager.get_amount(Constants.FACTION_PLAYER,
			Constants.RESOURCE_GOLD), gold_before),
		"%0.0f против %0.0f" % [ResourceManager.get_amount(
			Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD), gold_before])
	verdict("G5 построек столько же",
		(after["buildings"] as Array).size() == (before["buildings"] as Array).size())
	# Ранги — главное, ради чего сохранение и городилось
	var lv_before := 0
	for row in (before["squads"] as Array):
		lv_before += int((row as Dictionary).get("level", 0))
	var lv_after := 0
	for row in (after["squads"] as Array):
		lv_after += int((row as Dictionary).get("level", 0))
	verdict("G6 сумма рангов отрядов восстановлена", lv_after == lv_before,
		"%d против %d" % [lv_after, lv_before])
	# НАГРАДЫ ДОШЛИ ДО САМИХ БОЙЦОВ, а не осели в записи отряда: это разные
	# вещи, и первая версия раздачи наград орде спотыкалась ровно здесь
	var boosted := false
	for s in GameManager.squads_of_faction(Constants.FACTION_GOBLIN):
		var sid: int = int((s as Dictionary)["id"])
		if GameManager.squad_level(sid) <= 0:
			continue
		var men := GameManager.squad_members(sid)
		if men.is_empty():
			continue
		var u := men[0] as Unit
		if u.vet_attack > 0.0 or u.vet_armor > 0.0 				or u.max_health > _UCfg.stat(u.stat_id, "health", 0.0):
			boosted = true
			break
	verdict("G7 ветеранские прибавки дошли до бойцов", boosted)

# ═════════════════════════════════════════════════════════════════════════════
# H. ПОЛНЫЙ ЦИКЛ: ФАЙЛ → НОВАЯ СЦЕНА
# ═════════════════════════════════════════════════════════════════════════════
# Блоки F и G проверили половинки пути порознь. Здесь проверяется ТА САМАЯ
# двухходовка, которой грузится партия в игре: слепок кладётся в
# GameManager.pending_load, поднимается НОВЫЙ экземпляр Main, его _ready()
# берёт зерно из слепка и сеет им мир, а start_game() последним делом зовёт
# apply(). Единственное отличие от настоящей загрузки — сцена не меняется через
# change_scene_to_file (внутри одного стенда это недоступно), а строится руками.
#
# САМОЕ ВАЖНОЕ ЗДЕСЬ — ЗЕРНО. Если оно не доедет, карта будет другой, и
# сохранённые постройки встанут посреди леса и воды. Проверяется не «зерно
# равно», а СЛЕДСТВИЕ: рельеф под одной и той же точкой обязан совпасть.
func _h_full_cycle() -> void:
	print("
═════ H. ПОЛНЫЙ ЦИКЛ ═════")
	if main == null or not is_instance_valid(main):
		verdict("H0 сцена жива", false)
		return
	var state: Dictionary = _Save.capture(main)
	var n_before: int = (state["units"]["type"] as PackedInt32Array).size()
	var seed_before: int = int(main.world_seed)
	# Три пробы рельефа в разных углах: одна точка могла бы совпасть случайно
	var probes: Array = [Vector2(-40.0, -30.0), Vector2(12.0, 55.0),
		Vector2(70.0, -65.0)]
	var h_before: Array = []
	for p in probes:
		h_before.append(main.get_terrain_height((p as Vector2).x, (p as Vector2).y))

	# Старую сцену сносим ЦЕЛИКОМ: два Main в дереве — это две армии в одном
	# ядре и два владельца GameManager.main
	var old = main
	main = null
	get_tree().root.remove_child(old)
	old.queue_free()
	await pframes(3)

	GameManager.pending_load = state
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(14)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	await pframes(4)

	verdict("H1 слепок разобран и очищен",
		GameManager.pending_load.is_empty())
	verdict("H2 новая сцена поднялась с тем же зерном",
		int(main.world_seed) == seed_before,
		"%d против %d" % [int(main.world_seed), seed_before])
	var same_ground := true
	var worst := 0.0
	for i in range(probes.size()):
		var p: Vector2 = probes[i]
		var h: float = main.get_terrain_height(p.x, p.y)
		worst = maxf(worst, absf(h - float(h_before[i])))
		if absf(h - float(h_before[i])) > 0.001:
			same_ground = false
	verdict("H3 рельеф пересеян тот же самый", same_ground,
		"худшее расхождение высоты %0.4f м" % worst)

	var after: Dictionary = _Save.capture(main)
	var n_after: int = (after["units"]["type"] as PackedInt32Array).size()
	verdict("H4 войско восстановлено в новой сцене",
		n_after == n_before, "%d против %d" % [n_after, n_before])
	verdict("H5 отрядов столько же",
		(after["squads"] as Array).size() == (state["squads"] as Array).size())
	verdict("H6 построек столько же",
		(after["buildings"] as Array).size() == (state["buildings"] as Array).size())
	# Часы партии обязаны продолжиться с сохранённого места, иначе орда,
	# поднятая с сороковой минуты, снова уснула бы до тридцатой
	verdict("H7 часы партии продолжились с сохранённого места",
		main.game_clock() >= float((state["meta"] as Dictionary).get("clock", 0.0)),
		"%0.1f с против %0.1f с" % [main.game_clock(),
			float((state["meta"] as Dictionary).get("clock", 0.0))])

# ═════════════════════════════════════════════════════════════════════════════
# I. ЭКРАНЫ МЕНЮ СТРОЯТСЯ
# ═════════════════════════════════════════════════════════════════════════════
# HEADLESS НЕ РИСУЕТ, НО ВЫПОЛНЯЕТ ПОСТРОЕНИЕ — и этого достаточно, чтобы
# поймать то, что здесь ломается чаще всего: опечатку в имени метода, лямбду,
# захватившую то, чего ещё нет, и обращение к узлу, которого в этой сцене не
# бывает. Внешний вид этих экранов судят глазом (они целиком из кода и без
# своего .tscn), а вот «строится ли оно вообще» обязано проверяться стендом:
# меню паузы открывается один раз за партию, и падение в нём игрок увидит
# ровно в тот момент, когда захочет сохраниться.
func _i_menus() -> void:
	print("
═════ I. ЭКРАНЫ МЕНЮ ═════")
	if main == null or not is_instance_valid(main) or main.hud == null:
		verdict("I0 сцена и HUD живы", false)
		return
	var hud = main.hud
	hud._show_pause_menu()
	await pframes(2)
	verdict("I1 меню паузы построено", hud._overlay != null
		and is_instance_valid(hud._overlay))
	hud._show_save_menu(true)
	await pframes(2)
	verdict("I2 экран сохранения построен", hud._overlay != null
		and is_instance_valid(hud._overlay))
	hud._show_save_menu(false)
	await pframes(2)
	verdict("I3 экран загрузки построен", hud._overlay != null
		and is_instance_valid(hud._overlay))
	hud._clear_overlay()
	get_tree().paused = false
	await pframes(2)

	# ГЛАВНОЕ МЕНЮ поднимается отдельно: ряд кнопок сложности живёт там, и
	# именно там он читает сохранённый выбор с диска
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await pframes(4)
	verdict("I4 главное меню построено", is_instance_valid(menu))
	# Клик по кнопке сложности обязан менять текущий выбор, а не только вид
	var was: String = _Diff.current()
	var other: String = _Diff.HARD if was != _Diff.HARD else _Diff.EASY
	var oi: int = 0
	for k in range(_Diff.ORDER.size()):
		if String(_Diff.ORDER[k]) == other:
			oi = k
	menu._diff_opt.select(oi)
	menu._diff_opt.item_selected.emit(oi)
	verdict("I5 клик по кнопке сложности меняет выбор",
		_Diff.current() == other, "%s → %s" % [was, _Diff.current()])
	var wi: int = 0
	for k2 in range(_Diff.ORDER.size()):
		if String(_Diff.ORDER[k2]) == was:
			wi = k2
	menu._diff_opt.select(wi)
	menu._diff_opt.item_selected.emit(wi)
	get_tree().root.remove_child(menu)
	menu.queue_free()
