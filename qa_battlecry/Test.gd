extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: БОЕВОЙ КЛИЧ И ПОДСВЕТКА АКТИВНОЙ СТОЙКИ
## ═══════════════════════════════════════════════════════════════════════════
##   A. ЗВУК ЕСТЬ    — файл на месте, категория заведена, лимиты позволяют хор
##   B. СМЕНА СТОЙКИ — клич на КАЖДЫЙ отряд, но только на РЕАЛЬНУЮ смену
##   C. ПРИКАЗ МАРША — клич на каждый отряд выделения, в т.ч. после Ctrl+1
##   D. ПОДСВЕТКА    — активная кнопка стойки обведена жёлтым, неактивная нет
##
## Считаем не «сыграло ли в динамике» (в headless звука нет вовсе), а сколько
## раз отряд ПОПРОСИЛ звук: AudioManager.sfx_calls растёт на каждый play_3d.
## Это ровно то, что решает игровой код, и оно проверяемо без звуковой карты.

## Сколько ждать выдачи отложенного клича. С запасом больше разброса
## GameManager.CRY_SPREAD_SEC — иначе стенд ловил бы гонку, а не поведение
const CRY_WAIT := 0.6

var main = null
var hud = null
var sm = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

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

func _squad(kind: String, center: Vector3, count: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var men: Array = []
	for i in range(count):
		var u: Unit
		match kind:
			"spearman": u = Spearman.new()
			"archer":   u = Archer.new()
			_:          u = Worker.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = center + Vector3(float(i % 5) * 0.6, 0.0, float(i / 5) * 0.6)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

## Сколько отрядов РЕШИЛО крикнуть за время выполнения действия.
## Считаем решения (GameManager.cry_decisions), а не запуски в AudioManager:
## сам звук уходит с микро-задержкой до CRY_SPREAD_SEC (разводит фазы, см.
## GameManager), и в том же кадре его в sfx_calls ещё нет
func _cries(action: Callable) -> int:
	var before: int = GameManager.cry_decisions
	action.call()
	return GameManager.cry_decisions - before

## Откат клича у отряда сбрасываем, иначе соседние проверки глушат друг друга
func _reset_cooldowns() -> void:
	GameManager._cry_last.clear()

func _run() -> void:
	seed(11)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	hud = main.hud
	sm  = main.selection_manager
	GameManager.world_bounds_enabled = false
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  БОЕВОЙ КЛИЧ И ПОДСВЕТКА СТОЕК                                   ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	# ── A. ЗВУК ЗАВЕДЁН ─────────────────────────────────────────────────────
	var bank: Array = AudioManager.SFX_BANK.get("battle_cry", [])
	verdict("A1 категория battle_cry заведена в банке", not bank.is_empty(),
		"файлов: %s" % str(bank))
	var full: String = AudioManager.DIR_SFX + String(bank[0]) if not bank.is_empty() else ""
	verdict("A2 файл клича реально существует",
		not full.is_empty() and ResourceLoader.exists(full), full)
	var lim: Dictionary = AudioManager.SFX_LIMITS.get("battle_cry", {})
	# Нулевая пауза обязательна: иначе одновременный хор схлопнется в один голос
	verdict("A3 пауза категории нулевая — хор не схлопывается в один голос",
		float(lim.get("gap", 1.0)) <= 0.001, "gap=%s" % str(lim.get("gap", "нет")))
	verdict("A4 голосов хватает на хор из нескольких отрядов",
		int(lim.get("voices", 0)) >= 4, "voices=%s" % str(lim.get("voices", "нет")))

	# ── B. СМЕНА СТОЙКИ ─────────────────────────────────────────────────────
	var s1 := _squad("spearman", Vector3(0, 0, 0), 6)
	var s2 := _squad("spearman", Vector3(20, 0, 0), 6)
	var s3 := _squad("archer",   Vector3(40, 0, 0), 6)
	await frames(3)
	sm.selected_units = (s1 + s2 + s3).duplicate()

	_reset_cooldowns()
	var n_def: int = _cries(func(): sm.set_selection_stance(_UCfg().STANCE_DEFENSE))
	verdict("B1 смена стойки: клич от КАЖДОГО из трёх отрядов", n_def == 3,
		"кличей %d из 3" % n_def)

	# Повторное нажатие той же стойки ничего не меняет — и молчит
	_reset_cooldowns()
	var n_same: int = _cries(func(): sm.set_selection_stance(_UCfg().STANCE_DEFENSE))
	verdict("B2 повторный клик по той же стойке молчит", n_same == 0,
		"кличей %d, ожидали 0" % n_same)

	# Обратное переключение — снова хор
	_reset_cooldowns()
	var n_atk: int = _cries(func(): sm.set_selection_stance(_UCfg().STANCE_ATTACK))
	verdict("B3 обратная смена стойки снова даёт хор", n_atk == 3,
		"кличей %d из 3" % n_atk)

	# Откат: без сброса второй клич подряд не проходит
	var n_fast: int = _cries(func(): sm.set_selection_stance(_UCfg().STANCE_DEFENSE))
	verdict("B4 откат не даёт кричать очередью", n_fast == 0,
		"кличей %d сразу следом, ожидали 0" % n_fast)

	# ── C. ПРИКАЗ МАРША: ТОЛЬКО ГОРЯЧИМ ГРУППАМ ────────────────────────────
	# Обычное выделение (рамкой/кликом) командует МОЛЧА — это самый частый
	# способ управления, и клич на каждый клик превращался в непрерывный ор
	sm.selected_units = (s1 + s2 + s3).duplicate()
	_reset_cooldowns()
	var silent := 0
	for _i in range(12):
		_reset_cooldowns()      # откат заведомо не мешает — проверяем именно гейт
		silent += _cries(func(): sm._issue_formation_move(Vector3(0, 0, 60), false))
	verdict("C1 обычное выделение идёт МОЛЧА", silent == 0,
		"кличей за 12 приказов: %d, ожидали 0" % silent)

	# Горячая группа Ctrl+1 — клич разрешён
	sm._save_group(0)
	sm._recall_group(0)
	await frames(2)
	verdict("C2 выделение опознано как горячая группа",
		sm._selection_is_hotkey_group(), "индекс группы %d" % sm.current_group_index())

	# ── C3. «ЧЕРЕЗ РАЗ»: НИ МОЛЧА, НИ НЕПРЕРЫВНО ────────────────────────────
	# Шанс случайный, поэтому проверяется СВОЙСТВО, а не конкретное число:
	# за много попыток клич обязан и звучать, и пропускаться. Откат сбрасываем
	# перед каждой попыткой — иначе мерили бы откат, а не шанс
	var fired := 0
	var tries := 60
	for _i in range(tries):
		_reset_cooldowns()
		fired += _cries(func(): sm._issue_formation_move(Vector3(0, 0, 60), false))
	# 60 попыток × 3 отряда = 180 бросков жребия; при шансе 0.5 разброс
	# укладывается в эти границы с огромным запасом
	var total: int = tries * 3
	verdict("C3 клич звучит ЧЕРЕЗ РАЗ, а не всегда и не никогда",
		fired > total / 5 and fired < total * 4 / 5,
		"сработал %d раз из %d бросков (ожидали около половины)" % [fired, total])

	# ── C4. ОТКАТ ДЕРЖИТ СПАМ КЛИКОВ ───────────────────────────────────────
	# Без сброса отката подряд идущие приказы обязаны замолчать: даже если
	# первый бросок жребия удался, второй клич в ту же секунду не пройдёт
	_reset_cooldowns()
	var burst := 0
	for _i in range(20):
		burst += _cries(func(): sm._issue_formation_move(Vector3(0, 0, 60), false))
	verdict("C4 спам кликов не даёт очередь кличей", burst <= 3,
		"кличей за 20 кликов подряд: %d (отрядов 3, потолок — по одному)" % burst)

	# Рабочие не кричат: клич принадлежит пехоте
	var w := _squad("worker", Vector3(-40, 0, 0), 3)
	await frames(3)
	sm.selected_units = w.duplicate()
	sm._save_group(1)
	sm._recall_group(1)
	await frames(2)
	_reset_cooldowns()
	var n_w := 0
	for _i in range(12):
		_reset_cooldowns()
		n_w += _cries(func(): sm._issue_formation_move(Vector3(-40, 0, 40), false))
	verdict("C5 артель рабочих молчит даже в горячей группе", n_w == 0,
		"кличей %d, ожидали 0" % n_w)

	# ── E. ЗАЩИТА ОТ ФАЗОВОГО НАЛОЖЕНИЯ («электронный» призвук) ─────────────
	# Три независимые меры; проверяем каждую отдельно, потому что по отдельности
	# ни одна эффект не снимает

	# E1 — ВЫСОТА: у клича диапазон расстройки шире общего
	var cl: Dictionary = AudioManager.SFX_LIMITS.get("battle_cry", {})
	var pr: Array = cl.get("pitch", AudioManager.DEFAULT_PITCH_RANGE)
	verdict("E1 у клича свой, более широкий разброс высоты",
		float(pr[0]) <= 0.92 and float(pr[1]) >= 1.08,
		"диапазон %.2f..%.2f (общий %.2f..%.2f)" % [
			float(pr[0]), float(pr[1]),
			float(AudioManager.DEFAULT_PITCH_RANGE[0]),
			float(AudioManager.DEFAULT_PITCH_RANGE[1])])

	# E1б — и он реально доезжает до голоса, а не лежит в таблице мёртвым.
	# Смотрим pitch_scale у голосов пула: проверять p3.playing нельзя — в
	# headless звуковой карты нет, и «играет» всегда false, хотя play() прошёл
	# и параметры на голос записаны
	# Играем В ТОЧКЕ СЛУШАТЕЛЯ: play_3d отсекает всё дальше SFX_CULL_DISTANCE
	# ещё до выдачи голоса, а слушатель висит в фокусе камеры — далеко от нуля
	# координат. Играя в Vector3.ZERO, стенд мерил бы отсечку, а не высоту
	var lis: Node3D = AudioManager._listener_node()
	var here: Vector3 = lis.global_position if lis != null else Vector3.ZERO
	var uniq: Dictionary = {}
	for _i in range(24):
		AudioManager.play_3d("battle_cry", here)
		for v in AudioManager._pool:
			var p3 := v as AudioStreamPlayer3D
			if p3 != null and p3.stream != null:
				uniq[snappedf(p3.pitch_scale, 0.001)] = true
	var in_range := true
	for k in uniq:
		if float(k) < float(pr[0]) - 0.001 or float(k) > float(pr[1]) + 0.001:
			in_range = false
	verdict("E1б высота реально разная и в заданных пределах",
		uniq.size() >= 3 and in_range,
		"различных значений: %d, все в диапазоне: %s" % [uniq.size(), str(in_range)])

	# E2 — ВРЕМЯ: звук уходит НЕ в тот же кадр, что решение.
	# СНАЧАЛА ДОЖДАТЬСЯ ОТЛОЖЕННЫХ КЛИЧЕЙ ОТ ПРЕДЫДУЩИХ ПРОВЕРОК: в C3/C4 их
	# набралось под сотню, таймеры ещё висят, и без слива они досчитывались бы
	# сюда. Ждём НАСТОЯЩИМ таймером, а не кадрами: в headless кадры идут
	# быстрее реального времени, и «30 кадров» короче разброса в 0.18 с
	await get_tree().create_timer(0.6).timeout
	AudioManager.reset_sfx_stats()
	GameManager._cry_last.clear()
	sm.selected_units = (s1 + s2 + s3).duplicate()
	sm._save_group(2)
	sm._recall_group(2)
	await frames(2)
	var decided := 0
	while decided == 0:
		GameManager._cry_last.clear()
		decided = _cries(func(): sm._issue_formation_move(Vector3(0, 0, 60), false))
	var immediate: int = AudioManager.sfx_calls
	verdict("E2 клич уходит с задержкой, а не в тот же кадр",
		immediate < decided,
		"решений %d, прозвучало сразу %d" % [decided, immediate])
	# ...но обязательно доезжает: ждём дольше разброса, снова настоящим таймером
	await get_tree().create_timer(CRY_WAIT).timeout
	verdict("E2б после задержки звук всё же выдан",
		AudioManager.sfx_calls >= decided,
		"решений %d, прозвучало %d" % [decided, AudioManager.sfx_calls])

	# E3 — ЧИСЛО: сколько бы отрядов ни выделили, кричат не больше потолка
	var many: Array = []
	for i in range(8):
		many.append_array(_squad("spearman", Vector3(100.0 + float(i) * 12.0, 0, 0), 4))
	await frames(3)
	sm.selected_units = many.duplicate()
	sm._save_group(3)
	sm._recall_group(3)
	await frames(2)
	var worst := 0
	for _i in range(10):
		GameManager._cry_last.clear()
		worst = maxi(worst, _cries(func(): sm._issue_formation_move(Vector3(140, 0, 60), false)))
	verdict("E3 из восьми отрядов кричат не больше потолка",
		worst <= GameManager.CRY_MAX_VOICES,
		"максимум за приказ: %d, потолок %d" % [worst, GameManager.CRY_MAX_VOICES])
	for u in many:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(3)

	# ── D. ПОДСВЕТКА АКТИВНОЙ СТОЙКИ ────────────────────────────────────────
	sm.selected_units = s1.duplicate()
	sm.set_selection_stance(_UCfg().STANCE_DEFENSE)
	hud.show_selection(sm.selected_units)
	await frames(3)
	var atk_btn := _find_btn("Attack")
	var def_btn := _find_btn("Defend")
	verdict("D0 обе кнопки стоек на панели (подготовка)",
		atk_btn != null and def_btn != null)
	if atk_btn != null and def_btn != null:
		var def_sb := def_btn.get_theme_stylebox("normal") as StyleBoxFlat
		var atk_sb := atk_btn.get_theme_stylebox("normal") as StyleBoxFlat
		verdict("D1 активная «Защита» обведена жёлтым",
			def_sb != null and def_sb.border_color.is_equal_approx(HUD.ACTIVE_BORDER_COLOR)
				and def_sb.border_width_top == HUD.ACTIVE_BORDER_W,
			"рамка %d px, цвет %s" % [
				def_sb.border_width_top if def_sb != null else -1,
				str(def_sb.border_color) if def_sb != null else "нет"])
		verdict("D2 неактивная «Атака» жёлтой рамки НЕ имеет",
			atk_sb != null and not atk_sb.border_color.is_equal_approx(HUD.ACTIVE_BORDER_COLOR),
			"цвет %s" % (str(atk_sb.border_color) if atk_sb != null else "нет"))
		verdict("D3 у подсветки скруглены углы",
			def_sb != null and def_sb.corner_radius_top_left == HUD.ACTIVE_BORDER_RADIUS,
			"радиус %d" % (def_sb.corner_radius_top_left if def_sb != null else -1))

		# Переключаем — подсветка обязана переехать на другую кнопку
		sm.set_selection_stance(_UCfg().STANCE_ATTACK)
		hud.show_selection(sm.selected_units)
		await frames(3)
		var atk2 := _find_btn("Attack")
		var def2 := _find_btn("Defend")
		var a_sb := atk2.get_theme_stylebox("normal") as StyleBoxFlat if atk2 != null else null
		var d_sb := def2.get_theme_stylebox("normal") as StyleBoxFlat if def2 != null else null
		verdict("D4 после переключения подсветка переехала на «Атаку»",
			a_sb != null and a_sb.border_color.is_equal_approx(HUD.ACTIVE_BORDER_COLOR)
				and d_sb != null and not d_sb.border_color.is_equal_approx(HUD.ACTIVE_BORDER_COLOR),
			"атака %s / защита %s" % [
				str(a_sb.border_color) if a_sb != null else "нет",
				str(d_sb.border_color) if d_sb != null else "нет"])

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %s%s" % [_pad(String(row[0]), 54),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== BATTLE CRY TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

func _UCfg():
	return load("res://scripts/unit_stats_config.gd")

## Кнопка панели по её tooltip_text (в _cmd туда кладётся первая строка подписи)
func _find_btn(title: String) -> Button:
	for c in hud.button_container.get_children():
		var b := c as Button
		if b != null and b.tooltip_text.begins_with(title):
			return b
	return null
