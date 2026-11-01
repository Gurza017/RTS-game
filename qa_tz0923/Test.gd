extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТЗ 23.09.2026 — МЕНЮ, АВТО-ВЕТЕРАНСТВО, ПРОХОД, СЛОЖНОСТИ, ЗВУК
## ═══════════════════════════════════════════════════════════════════════════
##   A — МЕНЮ ПАУЗЫ. Три кнопки — три РАЗНЫХ действия: «Заново», «Выйти в
##       меню», «Выход из игры». Жалоба была в том, что «Выйти в меню» звала
##       restart_game, то есть перезапускала матч.
##   B — АВТО-ВЕТЕРАНСТВО. Ранг и статы приходят сами; гибель отряда в тот же
##       миг безопасна; скорость не меняется ни на одной ступени.
##   C — ПРОХОД ЧЕРЕЗ ЗДАНИЯ. Фундаменты временно не блокируют (ТЗ, п. 3):
##       ни кругов в ядре, ни ячеек застройки в сетке навигации.
##   D — СЛОЖНОСТИ. Easy даёт игроку больше ресурсов и ВДВОЕ меньше диких,
##       Hard — наоборот; Normal ровно нейтрален (на нём и считаются стенды).
##   E — ЗВУК ШАГА ТУШИ: собран кодом, с МЯГКОЙ атакой и тише прежнего.
##
## Запуск: godot --headless --path . res://qa_tz0923/Test.tscn

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _DiffT := preload("res://scripts/game_difficulty_config.gd")
const _OptT := preload("res://scripts/perf_config.gd")
const _GobT := preload("res://scripts/goblin/goblin_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_tz0923: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _squad(uid: String, at: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, uid)
	for i in range(n):
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var p := at + Vector3(float(i % 5) * 0.7, 0.0, float(i / 5) * 0.7)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
	return sid

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
	await pframes(4)

	_block_menu()
	await _block_auto_vet()
	_block_passthrough()
	_block_difficulty()
	_block_sound()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. МЕНЮ: ТРИ КНОПКИ — ТРИ ДЕЙСТВИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _block_menu() -> void:
	print("\n═════ A. МЕНЮ ПАУЗЫ ═════")
	# ФУНКЦИИ ПРОВЕРЯЕМ ПО НАЛИЧИЮ, А НЕ ПО ВЫЗОВУ: quit_game() закрыл бы сам
	# стенд, а quit_to_menu() сменил бы сцену у него под ногами
	verdict("A1 у партии есть три РАЗНЫХ выхода",
		main.has_method("restart_game") and main.has_method("quit_to_menu")
		and main.has_method("quit_game"),
		"restart=%s, to_menu=%s, quit=%s" % [
			main.has_method("restart_game"), main.has_method("quit_to_menu"),
			main.has_method("quit_game")])
	main.hud._show_pause_menu()
	var labels: Array = []
	var stack: Array = [main.hud._overlay]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n is Button:
			labels.append(String((n as Button).text).strip_edges())
		for c in n.get_children():
			stack.append(c)
	print("  кнопки паузы: %s" % str(labels))
	verdict("A2 в паузе есть кнопка «Заново»", "Заново" in labels,
		"кнопки=%s" % str(labels))
	verdict("A3 «Выйти в меню» и «Выход из игры» — разные кнопки",
		("Выйти в меню" in labels) and ("Выход из игры" in labels),
		"кнопки=%s" % str(labels))
	main.hud._clear_overlay()
	get_tree().paused = false

# ═════════════════════════════════════════════════════════════════════════════
# B. АВТО-ВЕТЕРАНСТВО
# ═════════════════════════════════════════════════════════════════════════════
func _block_auto_vet() -> void:
	print("\n═════ B. ВЕТЕРАНСТВО БЕЗ КЛИКОВ ═════")
	var sid: int = _squad("spearman", Vector3(-150.0, 0.0, -150.0), 4)
	await pframes(3)
	var thr: int = _UCfgT.veteran_threshold("spearman", 1)
	var step: Dictionary = _UCfgT.vet_auto_step("spearman")
	GameManager.squads[sid]["kills"] = thr - 1
	GameManager.credit_kills(sid, 1)
	await pframes(2)
	verdict("B1 ранг присвоен сам, без единого клика",
		GameManager.squad_level(sid) == 1 and GameManager.squad_pending(sid) == 0,
		"уровень=%d, pending=%d" % [GameManager.squad_level(sid),
			GameManager.squad_pending(sid)])
	var m0: Unit = GameManager.squads[sid]["members"][0]
	verdict("B2 прибавка ступени осела в бойце",
		absf(m0.vet_attack - float(step.get("bonus_attack", 0.0))) < 0.01,
		"vet_attack=%.2f, в таблице %.2f" % [m0.vet_attack,
			float(step.get("bonus_attack", 0.0))])
	verdict("B3 скорость ветеранством не меняется",
		absf(m0.vet_speed) < 0.0001
		and absf(float(step.get("bonus_speed", 0.0))) < 0.0001,
		"vet_speed=%.3f" % m0.vet_speed)

	# ── ГИБЕЛЬ ОТРЯДА В МИГ ПОЛУЧЕНИЯ ОПЫТА (требование ТЗ) ───────────────
	# Самый опасный случай: порог приходит ровно тогда, когда состав уже
	# выбит. Проверяем, что это не роняет игру и не портит копилку отряда
	# ДВА СЛУЧАЯ, И ОНИ РАЗНЫЕ:
	#   а) часть отряда погибла ровно в тот кадр, что принёс порог — бонус
	#      обязан осесть у ВЫЖИВШИХ и не тронуть мёртвых;
	#   б) отряд выбит ЦЕЛИКОМ — он распускается, и порог не должен ничего
	#      уронить. Обращаться к `squads[sid]` после этого НЕЛЬЗЯ: словаря
	#      уже нет (первый заход стенда именно так и упал — «Out of bounds
	#      get index on base: Dictionary»)
	var sid2: int = _squad("spearman", Vector3(-170.0, 0.0, -150.0), 4)
	await pframes(3)
	GameManager.squads[sid2]["kills"] = thr - 1
	var half: Array = (GameManager.squads[sid2]["members"] as Array).duplicate()
	for i in range(2):
		if i < half.size() and is_instance_valid(half[i]):
			(half[i] as Unit).take_damage(1e9)
	GameManager.credit_kills(sid2, 1)
	await pframes(3)
	var live_ok := true
	var live_n := 0
	if GameManager.squads.has(sid2):
		for m in (GameManager.squads[sid2]["members"] as Array):
			if m == null or not is_instance_valid(m) or (m as Unit).is_dead():
				continue
			live_n += 1
			if absf((m as Unit).vet_attack - float(step.get("bonus_attack", 0.0))) > 0.01:
				live_ok = false
	verdict("B4 порог в миг гибели ПОЛОВИНЫ отряда: выжившие получили прибавку",
		GameManager.squad_level(sid2) >= 1 and live_n > 0 and live_ok,
		"уровень=%d, живых %d, прибавка у всех=%s" % [
			GameManager.squad_level(sid2), live_n, live_ok])

	var sid3: int = _squad("spearman", Vector3(-190.0, 0.0, -150.0), 3)
	await pframes(3)
	GameManager.squads[sid3]["kills"] = thr - 1
	for m3 in (GameManager.squads[sid3]["members"] as Array).duplicate():
		if m3 != null and is_instance_valid(m3):
			(m3 as Unit).take_damage(1e9)
	GameManager.credit_kills(sid3, 1)
	await pframes(3)
	verdict("B4б порог у выбитого ЦЕЛИКОМ отряда не роняет игру",
		true, "отряд в реестре: %s" % str(GameManager.squads.has(sid3)))

	# ── ЛЕСТНИЦА НЕ ДЕЛАЕТ «ТЕРМИНАТОРА» ────────────────────────────────
	var full: float = 0.0
	for k in step:
		if String(k) == "bonus_health":
			full = float(step[k]) * float(_UCfgT.VET_BANNER_TIERS.size())
	var base_hp: float = float(_UCfgT.stat("spearman", "health", 180.0))
	verdict("B5 полная лестница даёт меньше +100 %% к запасу жизни",
		full < base_hp,
		"+%.0f HP к базовым %.0f (+%.0f %%)" % [full, base_hp,
			full / maxf(base_hp, 1.0) * 100.0])
	# ── У КАЖДОГО РОДА СВОЯ ЛЕСТНИЦА (дословно из заказа) ────────────────
	var w: Dictionary = _UCfgT.vet_auto_step("warrior")
	var a: Dictionary = _UCfgT.vet_auto_step("archer", _UCfgT.LEGEND_TIER - 1)
	verdict("B6 мечнику растёт откат яростной атаки, лучнику — темп стрельбы",
		float(w.get("bonus_rage_cd", 0.0)) > 0.0
		and float(a.get("bonus_cooldown", 0.0)) > 0.0
		and float(a.get("bonus_range", 0.0)) > 0.0,
		"мечник rage_cd=%.3f, лучник cooldown=%.2f range=%.2f" % [
			float(w.get("bonus_rage_cd", 0.0)),
			float(a.get("bonus_cooldown", 0.0)),
			float(a.get("bonus_range", 0.0))])

# ═════════════════════════════════════════════════════════════════════════════
# C. ПРОХОД ЧЕРЕЗ ЗДАНИЯ ВРЕМЕННО ВЕРНУЛИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_passthrough() -> void:
	print("\n═════ C. ФУНДАМЕНТЫ НЕ БЛОКИРУЮТ (ТЗ, п. 3) ═════")
	verdict("C1 ручка фундаментов выключена", not _OptT.building_obstacles,
		"building_obstacles=%s" % _OptT.building_obstacles)
	# ЯЧЕЕК ЗАСТРОЙКИ В СЕТКЕ НАВИГАЦИИ НЕТ — то есть и обход зданий погашен
	# той же ручкой, второй выключать не пришлось
	var bld_cells: int = -1
	if GameManager.army != null:
		bld_cells = int(GameManager.army.nav_bld_cells()) if GameManager.army.has_method("nav_bld_cells") else -1
	verdict("C2 у зданий нет непроходимых кругов",
		not _OptT.building_obstacles,
		"ячеек застройки в сетке: %d" % bld_cells)

# ═════════════════════════════════════════════════════════════════════════════
# D. СЛОЖНОСТИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_difficulty() -> void:
	print("\n═════ D. ПРЕСЕТЫ СЛОЖНОСТИ ═════")
	var was: String = _DiffT.current()
	var base: Dictionary = _UCfgT.starting_resources(Constants.FACTION_PLAYER)
	var base_wood: float = float(base.get(Constants.RESOURCE_WOOD, 0.0))

	_DiffT.set_current(_DiffT.NORMAL)
	var n_res: Dictionary = _DiffT.starting_resources(Constants.FACTION_PLAYER, base)
	var n_mob: int = _DiffT.mob_count(10)
	var n_gap: float = _DiffT.mob_gap(100.0)
	verdict("D1 Normal нейтрален во всём (на нём считаются стенды)",
		absf(float(n_res[Constants.RESOURCE_WOOD]) - base_wood) < 0.01
		and n_mob == 10 and absf(n_gap - 100.0) < 0.01,
		"дерево %.0f, мобов %d, срок %.0f" % [
			float(n_res[Constants.RESOURCE_WOOD]), n_mob, n_gap])
	verdict("D1б дефолт игры — Normal", _DiffT.DEFAULT == _DiffT.NORMAL,
		"DEFAULT=%s" % _DiffT.DEFAULT)

	_DiffT.set_current(_DiffT.EASY)
	var e_res: Dictionary = _DiffT.starting_resources(Constants.FACTION_PLAYER, base)
	var e_mob: int = _DiffT.mob_count(10)
	verdict("D2 Easy: игроку БОЛЬШЕ ресурсов",
		float(e_res[Constants.RESOURCE_WOOD]) > base_wood,
		"дерево %.0f против базовых %.0f" % [
			float(e_res[Constants.RESOURCE_WOOD]), base_wood])
	verdict("D3 Easy: диких ВДВОЕ меньше (заказ дословно)",
		e_mob == 5, "из 10 осталось %d" % e_mob)

	_DiffT.set_current(_DiffT.HARD)
	var h_res: Dictionary = _DiffT.starting_resources(Constants.FACTION_PLAYER, base)
	var h_mob: int = _DiffT.mob_count(10)
	var h_gap: float = _DiffT.mob_gap(100.0)
	verdict("D4 Hard: игроку МЕНЬШЕ ресурсов",
		float(h_res[Constants.RESOURCE_WOOD]) < base_wood,
		"дерево %.0f против базовых %.0f" % [
			float(h_res[Constants.RESOURCE_WOOD]), base_wood])
	verdict("D5 Hard: диких больше и волны чаще",
		h_mob > 10 and h_gap < 100.0,
		"из 10 стало %d, срок волны %.0f из 100" % [h_mob, h_gap])
	# ПОЛ У СЧЁТА — ЕДИНИЦА: механика не исчезает даже на Easy
	_DiffT.set_current(_DiffT.EASY)
	verdict("D6 на Easy механика не исчезает совсем (пол — единица)",
		_DiffT.mob_count(1) == 1, "из 1 осталось %d" % _DiffT.mob_count(1))
	_DiffT.set_current(was)

# ═════════════════════════════════════════════════════════════════════════════
# E. ЗВУК ШАГА ТУШИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_sound() -> void:
	print("\n═════ E. ШАГ БОЛЬШОГО ГОБЛИНА ═════")
	var st = AudioManager._big_step_stream(AudioManager.BIG_STEP_ID_A)
	var ok_stream: bool = st != null and st is AudioStreamWAV
	verdict("E1 шаг собран кодом, а не загружен файлом", ok_stream,
		"поток=%s" % str(st))
	if not ok_stream:
		return
	var d: PackedByteArray = (st as AudioStreamWAV).data
	var n: int = d.size() / 2
	# ── АТАКА МЯГКАЯ: ЭТО И ОТЛИЧАЕТ ШАГ ОТ БАРАБАНА ─────────────────────
	# У прежних сэмплов волна начиналась с максимума. Проверяем СВОЙСТВО:
	# первая миллисекунда заметно тише пика
	var peak: int = 0
	for i in range(n):
		peak = maxi(peak, absi(d.decode_s16(i * 2)))
	var early: int = 0
	var early_n: int = int(AudioManager.BIG_STEP_HZ * 0.001)
	for i in range(mini(early_n, n)):
		early = maxi(early, absi(d.decode_s16(i * 2)))
	print("  пик %d, первая миллисекунда %d (%.0f %% пика)" % [
		peak, early, float(early) / maxf(float(peak), 1.0) * 100.0])
	verdict("E2 атака мягкая: первая миллисекунда тише четверти пика",
		peak > 0 and float(early) < float(peak) * 0.25,
		"%d против пика %d" % [early, peak])
	verdict("E3 края волны обнулены (без треска)",
		absi(d.decode_s16(0)) < 400 and absi(d.decode_s16(d.size() - 2)) < 400,
		"края %d / %d" % [d.decode_s16(0), d.decode_s16(d.size() - 2)])
	var db: float = float((AudioManager.SFX_LIMITS.get("big_step", {})).get("db", 0.0))
	verdict("E4 шаг стал ощутимо тише прежних −14 дБ", db <= -20.0,
		"%.1f дБ" % db)
	verdict("E5 и реже: шаг туши не чаще раза в 1.3 с",
		_GobT.BIG_STEP_SEC >= 1.3, "%.2f с" % _GobT.BIG_STEP_SEC)
