extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТЕЛА ПАВШИХ И СТРЕЛЫ, ОСТАЮЩИЕСЯ НА ПОЛЕ
## ═══════════════════════════════════════════════════════════════════════════
##   A ПОЯВЛЕНИЕ  — тело ложится при гибели, и у ЛЮБОГО рода войск
##   B НЕ ЮНИТ    — труп не тикает, не занимает узел и не лезет в ядро армии
##   C ЛИМИТ      — больше MAX_CORPSES тел на поле не бывает
##   D УГАСАНИЕ   — вытесненные не пропадают рывком, а растворяются
##   E РАСКЛАДКА  — тела лежат по-разному (угол и зеркало)
##   F СТРЕЛЫ     — сроки жизни торчащей стрелы и её растворения
##   G БЕЗ КРОВИ  — в подсистеме нет ни одного кровавого эффекта
##   H ПОКОЙ      — поза павшего, ступенька высоты, тень и стрелы в теле
##   I СТРЕЛА     — одна стрела в теле убитого стрелой, ноль в рукопашной
##   J ПОТОЛОК    — число торчащих на поле стрел ограничено, без лавины
##   K ГАШЕНИЕ    — растворение стрелы не рисует чёрный прямоугольник
##   L ОБЪЁМ      — завал не плоский: слои притенены, тела разного калибра
##   M СРОК ЖИЗНИ — тело лежит целым заказанные пятнадцать минут, потом
##                  полминуты разлагается; часы у слоя свои
##   N РАСФОРМИРОВАНИЕ — Delete по выделенным отрядам оставляет тела на поле
##   O ЗНАМЯ       — упавшее знамя ветеранов ложится тем же слотом, что и тело,
##                  и живёт по тем же правилам: срок, разложение, потолок
##
## ЧИСЛА НЕ ХАРДКОДЯТСЯ: лимит, срок растворения и сроки стрел читаются из
## самого кода (CorpseRenderer / Arrow) — стенд проверяет СВОЙСТВО, а не
## конкретную цифру, которую владелец вправе переставить.
##
## Стенд headless и МОЛЧИТ ДО КОНЦА: печатает одну таблицу вердиктов, как и
## положено любому новому стенду в этом проекте.

const _Corpses := preload("res://scripts/CorpseRenderer.gd")

var main: Node = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

## Ждём именно ФИЗИЧЕСКИЕ кадры там, где что-то должно успеть произойти:
## при Engine.max_fps = 0 отрисовка обгоняет физику (правило проекта)
func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok, detail])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Стенд работает далеко за краем карты, чтобы ни ИИ, ни лес не мешали
	GameManager.world_bounds_enabled = false
	await frames(2)

	await _test_spawn()
	await _test_not_a_unit()
	await _test_limit_and_fade()
	_test_lay()
	await _test_arrow_timing()
	await _test_arrow_in_corpse()
	await _test_pose_and_layers()
	await _test_arrows_in_body()
	await _test_stuck_arrow_cap()
	await _test_fade_and_volume()
	_test_no_blood()
	await _test_lifetime()
	await _test_disband()
	await _test_fallen_banner()
	_summary()
	print("\n=== QA_CORPSE DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ qa_corpse ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-58s %s%s" % [String(row[0]),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО",
			("  — " + String(row[2])) if String(row[2]) != "" else ""])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

# ─────────────────────────────────────────────────────────────────────────────
# Вспомогательное: поставить бойца и убить его
# ─────────────────────────────────────────────────────────────────────────────
func _spawn(path: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	u.sync_row()
	return u

func _kill(u: Unit) -> void:
	if is_instance_valid(u) and not u.is_dead():
		u.take_damage(u.max_health * 10.0 + 1000.0, null)

# ═════════════════════════════════════════════════════════════════════════════
# M. СРОК ЖИЗНИ ТЕЛА И ФАЗА РАЗЛОЖЕНИЯ
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: пятнадцать минут при полной видимости, затем тридцать секунд
## медленного разложения.
##
## ЖДАТЬ ПЯТНАДЦАТЬ МИНУТ НЕЛЬЗЯ — и не нужно: у слоя тел СВОИ часы (они же
## обеспечивают, что на паузе тела не доживают свой срок за спиной у игрока), и
## стенд подкручивает их вперёд через age_shift. Проверяется при этом ровно то,
## что и требовалось: до порога тело лежит целым, после — уходит в разложение и
## растворяется за заказанный срок, а не за срок вытеснения.
func _test_lifetime() -> void:
	var lim_life: float = _Corpses.LIFE_SEC
	var lim_diss: float = _Corpses.DISSOLVE_SEC
	verdict("M0 сроки заказаны в коде слоя, а не разбросаны по вызовам",
		lim_life >= 600.0 and lim_diss >= 20.0 and lim_diss <= 60.0,
		"лежит %.0f c, разлагается %.0f c" % [lim_life, lim_diss])
	verdict("M0б потолок тел поднят до заказанного",
		_Corpses.MAX_CORPSES >= 5000,
		"MAX_CORPSES = %d" % _Corpses.MAX_CORPSES)

	GameManager.corpses.clear()
	await pframes(2)
	var u := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER,
		Vector3(-1500.0, 0.0, -1500.0))
	await pframes(3)
	_kill(u)
	await pframes(3)
	var idx: int = GameManager.corpses.count() - 1
	verdict("M1 свежее тело лежит целым и не растворяется",
		float(GameManager.corpses.dissolve_of(idx)[0]) < 0.0,
		"осталось гаснуть %.1f c" % float(GameManager.corpses.dissolve_of(idx)[0]))

	# ── ПОЧТИ ДОЖИЛО, НО ЕЩЁ НЕ ПОРА ────────────────────────────────────────
	GameManager.corpses.age_shift(lim_life * 0.9)
	await pframes(3)
	verdict("M2 до порога тело всё ещё целое",
		float(GameManager.corpses.dissolve_of(idx)[0]) < 0.0,
		"возраст %.0f c из %.0f" % [GameManager.corpses.age_of(idx), lim_life])

	# ── ПОРОГ ПРОЙДЕН ───────────────────────────────────────────────────────
	GameManager.corpses.age_shift(lim_life * 0.2)
	await pframes(3)
	var d: Array = GameManager.corpses.dissolve_of(idx)
	verdict("M3 за порогом тело уходит в разложение", float(d[0]) > 0.0,
		"осталось %.1f c" % float(d[0]))
	verdict("M4 разлагается заказанные полминуты, а не срок вытеснения",
		absf(float(d[1]) - lim_diss) < 0.01,
		"длительность %.1f c при заказе %.0f c (вытеснение — %.1f c)"
			% [float(d[1]), lim_diss, _Corpses.FADE_SEC])
	# Доля, уезжающая в буфер, обязана считаться от СВОЕЙ длительности
	verdict("M5 доля разложения считается от своего срока",
		float(GameManager.corpses.lay_of(idx)[2]) > 0.9,
		"доля %.3f сразу после начала" % float(GameManager.corpses.lay_of(idx)[2]))

	# ── ДОЖИВАЕТ И УХОДИТ С ПОЛЯ ────────────────────────────────────────────
	var was: int = GameManager.corpses.count()
	var waited := 0.0
	while GameManager.corpses.fading_count() > 0 and waited < lim_diss + 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	verdict("M6 разложившееся тело освободило место",
		GameManager.corpses.count() < was and GameManager.corpses.fading_count() == 0,
		"было %d, стало %d за %.1f c" % [was, GameManager.corpses.count(), waited])
	GameManager.corpses.clear()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# N. РАСФОРМИРОВАНИЕ ВЫДЕЛЕННЫХ ОТРЯДОВ (клавиша Delete)
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: «бойцы спавнят трупы в MultiMesh, а узлы отрядов мгновенно
## удаляются из памяти». Проверяем оба конца: узлов не осталось, тела на поле
## появились. И отдельно — что чужого расформирование не трогает
func _test_disband() -> void:
	var sel = main.selection_manager
	GameManager.corpses.clear()
	await pframes(2)
	var mine: Array = []
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(8):
		var u := _spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER,
			Vector3(-1600.0 + float(i) * 0.8, 0.0, -1600.0))
		GameManager.add_to_squad(sid, u)
		mine.append(u)
	var foe := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_ENEMY,
		Vector3(-1600.0, 0.0, -1590.0))
	await pframes(4)

	sel._clear_selection()
	for u in mine:
		sel._select(u)
	# Чужого в выделение не пустит сам менеджер, но проверим и на входе метода:
	# selected_units — это набор СВОИХ по построению (см. recon_units)
	var before: int = GameManager.corpses.count()
	var killed: int = sel.disband_selected()
	await pframes(4)
	verdict("N1 Delete расформировал ровно выделенных", killed == mine.size(),
		"расформировано %d из %d" % [killed, mine.size()])
	var alive := 0
	for u in mine:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			alive += 1
	verdict("N2 узлов расформированных бойцов не осталось", alive == 0,
		"живых осталось %d" % alive)
	verdict("N3 на поле остались их тела",
		GameManager.corpses.count() - before == mine.size(),
		"тел прибавилось %d, ожидалось %d"
			% [GameManager.corpses.count() - before, mine.size()])
	verdict("N4 чужого расформирование не тронуло",
		is_instance_valid(foe) and not (foe as Unit).is_dead(),
		"чужой жив=%s" % str(is_instance_valid(foe) and not (foe as Unit).is_dead()))
	# И на пустом выделении метод обязан молчать, а не падать
	sel._clear_selection()
	verdict("N5 на пустом выделении Delete ничего не делает",
		sel.disband_selected() == 0)
	if is_instance_valid(foe):
		(foe as Node).queue_free()
	GameManager.corpses.clear()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# O. УПАВШЕЕ ЗНАМЯ ВЕТЕРАНОВ
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: когда гибнет последний боец отряда, упавшее копьё со
## знаменем «запекается в единый статичный MultiMesh трупов» и наследует ВСЕ их
## параметры — пятнадцать минут целым, тридцать секунд разложения, без
## добавочных вызовов отрисовки.
##
## ПОЧЕМУ ЭТА ПРОВЕРКА ЖИВЁТ ЗДЕСЬ, А НЕ В qa_vet. В qa_vet проверяется ЛОГИКА
## знаменосца (кто подхватил, когда упало). Здесь — что упавшее стало ОБЫЧНЫМ
## ЖИЛЬЦОМ СЛОЯ ТЕЛ: у него та же очередь, тот же счётчик, тот же срок и то же
## разложение. Если завтра знамя заведёт себе отдельный слой со своим таймером,
## красным станет именно этот блок.
func _test_fallen_banner() -> void:
	GameManager.corpses.clear()
	await pframes(2)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(6):
		var u := _spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER,
			Vector3(-1700.0 + float(i) * 0.9, 0.0, -1700.0))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	# Отряд-ветеран: без звания знамени нет вовсе, и падать нечему
	(GameManager.squads[sid] as Dictionary)["level"] = 5
	GameManager.refresh_squad_banner(sid)
	await pframes(4)
	verdict("O0 у ветеранского отряда есть знамя",
		(GameManager.squads[sid] as Dictionary).get("banner") != null)
	# ── БАКЕТ ЛЕНТЫ КОПЕЙЩИКА ЗАВОДИМ ЗАРАНЕЕ ──────────────────────────────
	# Считать бакеты сразу после clear() нельзя: их ноль, и гибель отряда
	# добавит СРАЗУ ДВА — свой лист копейщика и лист знамени. Проверять надо
	# прибавку ОТ ЗНАМЕНИ, поэтому одиночное тело кладётся первым, и к моменту
	# замера лист копейщика уже свой бакет имеет
	var lone := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, Vector3(-1720.0, 0.0, -1720.0))
	await pframes(2)
	_kill(lone)
	await pframes(3)
	var buckets0: int = GameManager.corpses.bucket_count()
	var corpses0: int = GameManager.corpses.count()

	for u in men:
		if is_instance_valid(u):
			(u as Unit).take_damage((u as Unit).max_health * 10.0 + 1000.0, null)
	# Укладка отложена на кадр (см. GameManager._drop_squad_banner)
	await pframes(6)
	var total: int = GameManager.corpses.count() - corpses0
	print("  павших %d, прибавилось %d (тела + знамя), бакетов %d → %d"
		% [men.size(), total, buckets0, GameManager.corpses.bucket_count()])
	verdict("O1 знамя легло тем же слотом, что и тела",
		total == men.size() + 1,
		"прибавилось %d, ждали %d" % [total, men.size() + 1])
	# Лента знамени — свой бакет, и это ОДИН вызов отрисовки на все упавшие
	# знамёна поля, а не по одному на каждое
	verdict("O2 знамя стоит одного бакета, а не узла на штуку",
		GameManager.corpses.bucket_count() == buckets0 + 1,
		"бакетов %d → %d" % [buckets0, GameManager.corpses.bucket_count()])

	# Знамя — последнее, что легло. Срок и разложение у него общие с телами
	var idx: int = GameManager.corpses.count() - 1
	verdict("O3 знамя лежит целым, а не гаснет сразу",
		float(GameManager.corpses.dissolve_of(idx)[0]) < 0.0,
		"осталось гаснуть %.1f c" % float(GameManager.corpses.dissolve_of(idx)[0]))
	# Переводим часы слоя за порог — знамя обязано пойти в разложение вместе
	# с телами, тем же сроком
	GameManager.corpses.age_shift(_Corpses.LIFE_SEC + 1.0)
	await pframes(3)
	var d: Array = GameManager.corpses.dissolve_of(idx)
	verdict("O4 у знамени тот же срок жизни, что у тел",
		float(d[0]) > 0.0, "осталось %.1f c" % float(d[0]))
	verdict("O5 и та же длительность разложения",
		absf(float(d[1]) - _Corpses.DISSOLVE_SEC) < 0.01,
		"%.1f c при заказе %.0f c" % [float(d[1]), _Corpses.DISSOLVE_SEC])
	# Своё пятно тени у знамени тоже есть — оно лежит на земле, как и тела
	verdict("O6 под упавшим знаменем есть тень",
		GameManager.corpses.has_shadow(idx))
	GameManager.corpses.clear()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# A. ТЕЛО ЛОЖИТСЯ ПРИ ГИБЕЛИ — И У ЛЮБОГО РОДА ВОЙСК
# ═════════════════════════════════════════════════════════════════════════════
## Три разных рода намеренно: человек, гоблин и конница. Своей ветки для них в
## CorpseRenderer нет вовсе — лента и масштаб берутся из самого бойца, — и
## проверяется здесь именно это: что «поддержка всех фракций» не требует кода
func _test_spawn() -> void:
	var kinds := {
		"человек-копейщик": "res://scenes/units/Spearman.tscn",
		"гоблин-копейщик":  "res://scenes/units/GoblinSpearman.tscn",
		"наездник на кабане": "res://scenes/units/GoblinPigRider.tscn",
	}
	var x := -600.0
	for name in kinds.keys():
		var before: int = GameManager.corpses.count()
		var u := _spawn(String(kinds[name]), Constants.FACTION_GOBLIN,
			Vector3(x, 0.0, -600.0))
		# Спрайт строится в _ready, но снимок ленты берётся при первом обращении;
		# пары кадров хватает, чтобы боец точно был готов
		await pframes(3)
		_kill(u)
		await pframes(2)
		var after: int = GameManager.corpses.count()
		verdict("A %s оставляет тело" % name, after == before + 1,
			"тел было %d, стало %d" % [before, after])
		x += 8.0

# ═════════════════════════════════════════════════════════════════════════════
# B. ТРУП — НЕ ЮНИТ
# ═════════════════════════════════════════════════════════════════════════════
## Главное требование задания: тело исключено из физики, автомата состояний и
## покадрового обсчёта. Проверяем это НЕ по комментарию, а по трём следам,
## которые оставил бы настоящий юнит: ходящий боец в счётчике GameManager,
## строка в ядре армии и узел в дереве мира
func _test_not_a_unit() -> void:
	var live0: int = GameManager.active_units()
	var rows0: int = GameManager.army.used()
	var kids0: int = main.world_root().get_child_count()
	var corpses0: int = GameManager.corpses.count()

	var mob: Array = []
	for i in range(12):
		mob.append(_spawn("res://scenes/units/Spearman.tscn",
			Constants.FACTION_GOBLIN, Vector3(-500.0 + float(i) * 2.0, 0.0, -500.0)))
	await pframes(3)
	for u in mob:
		_kill(u)
	# queue_free отложен: даём кадр на фактическое освобождение узлов
	await pframes(4)

	var live1: int = GameManager.active_units()
	var rows1: int = GameManager.army.used()
	var kids1: int = main.world_root().get_child_count()
	var got: int = GameManager.corpses.count() - corpses0

	verdict("B1 все двенадцать легли телами", got == 12, "тел прибавилось %d" % got)
	verdict("B2 павшие ушли из числа ходящих", live1 <= live0,
		"ходящих было %d, стало %d" % [live0, live1])
	verdict("B3 строк в ядре армии за трупами не осталось", rows1 <= rows0,
		"строк было %d, стало %d" % [rows0, rows1])
	# Узлов могло ПРИБАВИТЬСЯ ровно на число бакетов отрисовки (один
	# MultiMeshInstance3D на ленту), но никак не на число тел
	verdict("B4 узла на тело не заведено",
		kids1 - kids0 <= GameManager.corpses.bucket_count(),
		"узлов было %d, стало %d, бакетов %d"
			% [kids0, kids1, GameManager.corpses.bucket_count()])

# ═════════════════════════════════════════════════════════════════════════════
# C+D. ЛИМИТ И РАСТВОРЕНИЕ ВЫТЕСНЕННЫХ
# ═════════════════════════════════════════════════════════════════════════════
## Заваливаем поле заведомо сверх лимита. Тел не должно стать больше потолка —
## но и пропадать они обязаны не рывком: пока идёт растворение, вытесненные
## ещё числятся, и это ОСОЗНАННЫЙ запас, а не просчёт (см. CorpseRenderer.spawn)
func _test_limit_and_fade() -> void:
	var lim: int = _Corpses.MAX_CORPSES
	var fade: float = _Corpses.FADE_SEC
	var have: int = GameManager.corpses.count()
	# НАСКОЛЬКО ПЕРЕБИРАЕМ ПОТОЛОК. Держится переменной, а не двумя одинаковыми
	# числами: этим же числом ниже проверяется, что гаснет ровно перебор
	var over_by: int = 40
	var need: int = lim - have + over_by

	# Один и тот же боец не годится: тело берёт кадр и позу из живого. Ставим
	# и убиваем пачками, чтобы стенд не растянулся на минуты
	var made := 0
	while made < need:
		var batch: Array = []
		var n: int = mini(60, need - made)
		for i in range(n):
			batch.append(_spawn("res://scenes/units/Spearman.tscn",
				Constants.FACTION_GOBLIN,
				Vector3(-400.0 + float(i) * 1.5, 0.0, -400.0 - float(made) * 0.1)))
		await pframes(2)
		for u in batch:
			_kill(u)
		await pframes(2)
		made += n

	var fading: int = GameManager.corpses.fading_count()
	var staying: int = GameManager.corpses.count() - fading
	verdict("C1 вытеснение началось, а не молча обрезало список", fading > 0,
		"растворяется %d тел" % fading)
	# ГЛАВНАЯ ПРОВЕРКА ВСЕГО РАЗДЕЛА. Гаснуть обязан РОВНО перебор: считали
	# лимит по всей длине списка (вместе с догорающими) — и каждая новая смерть
	# видела перебор заново, отправляя гаснуть ещё одно тело. Лавина съедала
	# поле целиком, оставляя после боя чистый луг
	verdict("D1 гаснет ровно перебор, а не всё поле", fading <= over_by,
		"растворяется %d при переборе %d" % [fading, over_by])
	verdict("D1б под потолком поле остаётся полным", staying >= lim - over_by,
		"не гаснет %d тел при потолке %d" % [staying, lim])

	# Ждём, пока догорят. Растворение считает _process, а не физика
	var waited := 0.0
	while GameManager.corpses.fading_count() > 0 and waited < fade * 3.0 + 1.0:
		await frames(4)
		waited += 4.0 / 60.0
	var cnt: int = GameManager.corpses.count()
	verdict("C2 после растворения тел ровно по потолку",
		cnt <= lim and cnt >= lim - over_by,
		"тел %d при потолке %d" % [cnt, lim])
	verdict("D2 растворение закончилось само",
		GameManager.corpses.fading_count() == 0,
		"осталось гаснуть %d" % GameManager.corpses.fading_count())
	verdict("C3 старых вытеснили, новые остались",
		GameManager.corpses.spawned_total > lim,
		"всего положено %d тел" % GameManager.corpses.spawned_total)

# ═════════════════════════════════════════════════════════════════════════════
# E. КАЖДОЕ ТЕЛО ЛЕЖИТ ПО-СВОЕМУ
# ═════════════════════════════════════════════════════════════════════════════
## Требование «случайный поворот и зеркализация». Проверяем не «есть ли вызов
## rand», а результат: углы у тел разные и зеркало досталось не всем подряд
func _test_lay() -> void:
	var n: int = mini(120, GameManager.corpses.count())
	if n < 8:
		verdict("E раскладка тел", false, "тел слишком мало для замера: %d" % n)
		return
	var angles: Dictionary = {}
	var mirrored := 0
	for i in range(n):
		var lay: Array = GameManager.corpses.lay_of(i)
		if lay.is_empty():
			continue
		# Округляем до пяти градусов: считаем РАЗНЫЕ направления, а не разные
		# числа с плавающей точкой
		angles[int(round(rad_to_deg(float(lay[0])) / 5.0))] = true
		if bool(lay[1]):
			mirrored += 1
	# ── РАЗБРОС СЧИТАЕТСЯ ПО РАЗРЕШЁННОМУ ДИАПАЗОНУ, А НЕ ПО ВСЕМУ КРУГУ ───
	# Угол лежащего тела намеренно ограничен: голова смотрит вбок по экрану,
	# отклонение не больше COFFIN_SPREAD в каждую сторону, и таких секторов два
	# (головой вправо и головой влево). Это 4*COFFIN_SPREAD радиан из полного
	# круга — по пять градусов на корзину столько и выходит. Мерить разброс по
	# всем 72 корзинам круга значило бы требовать ровно того, что запрещено
	var bins: int = mini(n, int(round(rad_to_deg(4.0 * _Corpses.COFFIN_SPREAD) / 5.0)))
	var frac: float = float(angles.size()) / float(maxi(bins, 1))
	verdict("E1 тела лежат под разными углами в разрешённом секторе", frac > 0.6,
		"различных направлений %d из %d возможных" % [angles.size(), bins])
	# ── ГЛАВНОЕ ТРЕБОВАНИЕ: НИ ОДНО ТЕЛО НЕ ЧИТАЕТСЯ КАК СТОЯЩЕЕ ──────────
	# Тело лежит плашмя, но рисунок на нём — стоящая фигура. Совпади её
	# продольная ось с вертикалью экрана — и лежащий неотличим от стоящего.
	# Меряем: продольная ось обязана уходить от экранной вертикали не меньше
	# чем на (90° - COFFIN_SPREAD)
	var base: float = _Corpses._screen_side_yaw(main.world_root())
	var upright := 0
	var worst := 0.0
	for i in range(n):
		var lay3: Array = GameManager.corpses.lay_of(i)
		if lay3.is_empty():
			continue
		# Ось тела относительно «поперёк экрана»: ноль — идеально боком
		var d: float = absf(cos(float(lay3[0]) - base))
		worst = maxf(worst, absf(sin(float(lay3[0]) - base)))
		if d < cos(_Corpses.COFFIN_SPREAD) - 0.001:
			upright += 1
	verdict("E1б ни одно тело не стоит вертикально", upright == 0,
		"вертикальных %d из %d, худшее отклонение от «боком» %.0f°"
			% [upright, n, rad_to_deg(asin(minf(worst, 1.0)))])
	verdict("E2 зеркалена примерно половина тел",
		mirrored > n / 5 and mirrored < n * 4 / 5,
		"отражённых %d из %d" % [mirrored, n])

# ═════════════════════════════════════════════════════════════════════════════
# F. СРОКИ ЖИЗНИ ТОРЧАЩЕЙ СТРЕЛЫ
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца — 30-60 секунд и плавное исчезновение. Оба конца вилки в
## проверке, потому что заказана именно вилка
func _test_arrow_timing() -> void:
	verdict("F1 воткнувшаяся стрела лежит заказанные 30-60 секунд",
		Arrow.STUCK_LIFETIME >= 30.0 and Arrow.STUCK_LIFETIME <= 60.0,
		"STUCK_LIFETIME = %.1f c" % Arrow.STUCK_LIFETIME)
	verdict("F2 растворение стрелы укладывается в её срок",
		Arrow.STUCK_FADE > 0.0 and Arrow.STUCK_FADE < Arrow.STUCK_LIFETIME,
		"растворение %.1f c из %.1f c" % [Arrow.STUCK_FADE, Arrow.STUCK_LIFETIME])
	# Срок ЛЕТЯЩЕЙ — отдельный и короткий: это страховка от зависшей стрелы,
	# и путать её со сроком торчащей нельзя
	verdict("F3 у летящей стрелы срок свой и заметно короче",
		Arrow.MAX_FLIGHT_SEC > 0.0 and Arrow.MAX_FLIGHT_SEC < Arrow.STUCK_LIFETIME,
		"полёт %.1f c против %.1f c" % [Arrow.MAX_FLIGHT_SEC, Arrow.STUCK_LIFETIME])
	# ── ВОТКНУВШАЯСЯ СТОИТ КРУТО, А НЕ ЛЕЖИТ ──────────────────────────────
	# Проверяем ПОВЕДЕНИЕ, а не константу: даём самый настильный выстрел из
	# возможных (дуги нет вовсе, стрела приходит строго горизонтально), даём ей
	# воткнуться и спрашиваем УЖЕ ПРИМЕНЁННУЮ ось у её материала. Пологая
	# стрела при камере в 45° читается не как воткнувшаяся, а как зависшая в
	# воздухе — ровно та жалоба, ради которой доворот и ужесточён
	var flat := Arrow.new()
	flat._start_pos  = Vector3(-700.0, 0.4, -700.0)
	flat._end_pos    = Vector3(-699.0, 0.4, -700.0)
	flat._dist       = 1.0
	flat._arc_factor = 0.0
	main.world_add(flat)
	flat.global_position = flat._start_pos
	await frames(1)
	flat._stick_into_ground()
	var axis: Vector3 = flat._mat.get_shader_parameter("axis")
	var deg: float = rad_to_deg(asin(clampf(-axis.normalized().y, -1.0, 1.0)))
	verdict("F7 воткнувшаяся стрела стоит круто, а не лежит плашмя",
		deg >= 30.0, "наклон вниз %.0f°" % deg)
	# Заодно: воткнулась она В ГРУНТ, а не осталась на высоте выстрела
	var gy: float = GameManager.get_terrain_height(
		flat.global_position.x, flat.global_position.z)
	verdict("F8 воткнувшаяся стрела сидит в грунте, а не висит в воздухе",
		absf(flat.global_position.y - gy) < Arrow.ARROW_LENGTH,
		"центр на %.2f м от грунта" % (flat.global_position.y - gy))
	flat.queue_free()
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# G. НИКАКОЙ КРОВИ
# ═════════════════════════════════════════════════════════════════════════════
## Прямое ограничение задания первой очереди. Проверяем не по комментарию, а
## по двум структурным следам, которые кровь оставила бы неизбежно: вторую
## текстуру в шейдере тела (пятно поверх ленты бойца) и слово в исходниках
func _test_no_blood() -> void:
	var sh := FileAccess.open("res://shaders/mm_corpse.gdshader", FileAccess.READ)
	if sh == null:
		verdict("G1 шейдер тела на месте", false, "не открыть mm_corpse.gdshader")
		return
	var src: String = sh.get_as_text()
	# Одна-единственная текстура — сама лента бойца. Второй sampler2D означал
	# бы наложение поверх неё, а накладывать в первой очереди нечего
	var samplers := 0
	for line in src.split("
"):
		var l: String = line
		if l.begins_with("uniform sampler2D"):
			samplers += 1
	verdict("G1 тело рисуется лентой бойца и ничем сверх неё", samplers == 1,
		"текстур в шейдере: %d" % samplers)

	var files := ["res://scripts/CorpseRenderer.gd", "res://shaders/mm_corpse.gdshader"]
	var bad := ""
	for p2 in files:
		var f := FileAccess.open(String(p2), FileAccess.READ)
		if f == null:
			bad = "не открыть %s" % p2
			break
		var low: String = f.get_as_text().to_lower()
		for w in ["blood", "gore", "splatter"]:
			if low.find(String(w)) != -1:
				bad = "%s содержит «%s»" % [p2, w]
				break
		if bad != "":
			break
	verdict("G2 кровавых эффектов в подсистеме тел не заведено", bad == "", bad)

# ═════════════════════════════════════════════════════════════════════════════
# F. СТРЕЛА, УБИВШАЯ БОЙЦА, ОСТАЁТСЯ В ТЕЛЕ
# ═════════════════════════════════════════════════════════════════════════════
## Проверяем не константу, а поведение: стрела со смертельным уроном обязана
## после попадания ОСТАТЬСЯ на поле, а не уйти в пул, как уходила всегда
func _test_arrow_in_corpse() -> void:
	var pool0: int = GameManager.arrow_pool_size()
	var target := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_GOBLIN, Vector3(-300.0, 0.0, -300.0))
	await pframes(3)
	var tp: Vector3 = target.global_position
	var corpses0: int = GameManager.corpses.count()

	var a := Arrow.new()
	a.faction = Constants.FACTION_PLAYER
	a.damage  = target.max_health * 10.0 + 1000.0
	a._start_pos = tp + Vector3(-6.0, 1.6, 0.0)
	a._end_pos   = tp
	a._dist      = 6.0
	a._speed     = 12.0
	main.world_add(a)
	a.global_position = a._start_pos

	# Ждём попадания: полёт считает _process, поэтому кадры отрисовки
	var waited := 0
	while waited < 240 and is_instance_valid(a) and not a._spent:
		await frames(4)
		waited += 4

	verdict("F4 боец, убитый стрелой, лёг телом",
		GameManager.corpses.count() == corpses0 + 1,
		"тел было %d, стало %d" % [corpses0, GameManager.corpses.count()])
	verdict("F5 стрела осталась в теле, а не ушла в пул",
		is_instance_valid(a) and a._spent and not a._pooled
			and GameManager.arrow_pool_size() == pool0,
		"воткнулась=%s, в пуле=%s, размер пула %d был %d"
			% [str(is_instance_valid(a) and a._spent),
				str(is_instance_valid(a) and a._pooled),
				GameManager.arrow_pool_size(), pool0])
	verdict("F6 торчащая стрела считает СВОЙ срок, а не срок полёта",
		is_instance_valid(a) and a._stuck_life < a._life,
		"торчит %.2f c при общем возрасте %.2f c"
			% [a._stuck_life if is_instance_valid(a) else -1.0,
				a._life if is_instance_valid(a) else -1.0])
	if is_instance_valid(a):
		a.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# H. ПОЗА ПАВШЕГО, СЛОИ, ТЕНЬ И СТРЕЛЫ В ТЕЛЕ
# ═════════════════════════════════════════════════════════════════════════════
## Четыре разные придирки владельца к виду поля боя, и все четыре проверяются
## по следам в данных, а не по картинке
func _test_pose_and_layers() -> void:
	# ── H1. МЁРТВЫЙ НЕ МАШЕТ ОРУЖИЕМ ───────────────────────────────────────
	# Загоняем бойца в БОЕВУЮ позу и смотрим, что поза павшего от неё
	# отличается и стоит на нулевом кадре. Именно застывший замах давал на
	# завале «клочья тумана»: у ленты удара нарисован белый след
	var man := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, Vector3(-250.0, 0.0, -250.0))
	var foe := _spawn("res://scenes/units/GoblinSpearman.tscn",
		Constants.FACTION_GOBLIN, Vector3(-249.0, 0.0, -250.0))
	await pframes(3)
	# Поза павшего, снятая с бойца В ПОКОЕ, — эталон
	var calm: Array = man.corpse_frame()
	# ПОЗУ СТАВИМ НАПРЯМУЮ, а не ждём, пока её выберет бой. Выбор позы живёт в
	# ВИЗУАЛЬНОМ тике и работает только у бойца, которого видно; headless без
	# камеры не видит никого, и ждать смены ленты здесь можно вечно. Нам и не
	# нужен бой — нужна боевая ЛЕНТА, а ставит её ровно этот вызов
	man.command_attack(foe, true, true)
	man._apply_dir_tex("attack_right")
	await pframes(1)
	var live: Array = man.sheet_frame()
	var changed: bool = (not live.is_empty() and not calm.is_empty()
		and live[0] != calm[0])
	var dead: Array = man.corpse_frame()
	verdict("H1 проба дошла до боевой позы", changed,
		"лента в бою %s ленты покоя" % ("отличается от" if changed else "совпала с"))
	verdict("H1б поза павшего берётся с нулевого кадра",
		not dead.is_empty() and int(dead[1]) == 0,
		"кадр павшего %d, живого %d" % [int(dead[1]) if not dead.is_empty() else -1,
			int(live[1]) if not live.is_empty() else -1])
	# ГЛАВНОЕ: поза павшего НЕ ЗАВИСИТ от того, на чём бойца застала смерть.
	# Это и есть требование «труп не застывает в замахе»
	verdict("H1в поза павшего не зависит от позы, в которой застала смерть",
		not dead.is_empty() and not calm.is_empty()
			and dead[0] == calm[0] and dead[0] != live[0],
		"павший=%s покой=%s бой=%s" % [
			str(dead[0] if not dead.is_empty() else null),
			str(calm[0] if not calm.is_empty() else null),
			str(live[0] if not live.is_empty() else null)])
	_kill(foe)
	_kill(man)
	await pframes(2)

	# ── H2. ЗАВАЛ НЕ ДРОЖИТ: У КАЖДОГО ТЕЛА СВОЯ ВЫСОТА ────────────────────
	var n: int = mini(24, GameManager.corpses.count())
	var lifts: Dictionary = {}
	var with_shadow := 0
	for i in range(GameManager.corpses.count() - n, GameManager.corpses.count()):
		var lay: Array = GameManager.corpses.lay_of(i)
		if lay.is_empty():
			continue
		lifts[snappedf(float(lay[3]), 0.0001)] = true
		if GameManager.corpses.has_shadow(i):
			with_shadow += 1
	verdict("H2 соседние по времени тела легли на разной высоте",
		lifts.size() >= n - 1,
		"различных высот %d на %d тел" % [lifts.size(), n])
	# ── H3. ТЕНЬ ЕСТЬ У КАЖДОГО ───────────────────────────────────────────
	verdict("H3 под каждым телом своё пятно тени", with_shadow == n,
		"с тенью %d из %d" % [with_shadow, n])

	# ── H4. СТРЕЛА ГАСНЕТ ВМЕСТЕ С ТЕЛОМ ──────────────────────────────────
	# Не «через сорок пять секунд, что бы ни случилось»: тело, вытесненное
	# лимитом, обязано унести свои стрелы с собой
	var victim := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_GOBLIN, Vector3(-260.0, 0.0, -260.0))
	await pframes(3)
	var tp: Vector3 = victim.global_position
	var a := Arrow.new()
	a.faction = Constants.FACTION_PLAYER
	a.damage  = victim.max_health * 10.0 + 1000.0
	a._start_pos = tp + Vector3(-6.0, 1.6, 0.0)
	a._end_pos   = tp
	a._dist      = 6.0
	a._speed     = 12.0
	main.world_add(a)
	a.global_position = a._start_pos
	var waited := 0
	while waited < 240 and is_instance_valid(a) and not a._spent:
		await frames(4)
		waited += 4
	var idx: int = GameManager.corpses.count() - 1
	var lay2: Array = GameManager.corpses.lay_of(idx)
	verdict("H4 стрела числится за конкретным телом",
		not lay2.is_empty() and int(lay2[4]) == 1,
		"стрел в теле: %d" % (int(lay2[4]) if not lay2.is_empty() else -1))
	# Просим стрелу истаять за тот же срок, что и тело: оставшийся срок обязан
	# укоротиться, а не остаться сорокапятисекундным
	var before: float = Arrow.STUCK_LIFETIME - a._stuck_life
	a.fade_out_in(_Corpses.FADE_SEC)
	var after: float = Arrow.STUCK_LIFETIME - a._stuck_life
	verdict("H5 тело укорачивает срок своей стреле",
		after < before and after <= _Corpses.FADE_SEC + 0.01,
		"оставалось %.1f c, стало %.1f c при сроке тела %.1f c"
			% [before, after, _Corpses.FADE_SEC])
	if is_instance_valid(a):
		a.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# I. СТРЕЛА В ТЕЛЕ: ОДНА, НА ТЕЛЕ И РОВНО ПОКА ВИДНО ТЕЛО
# ═════════════════════════════════════════════════════════════════════════════
## ПЕРЕСМОТРЕННЫЙ заказ владельца: убит стрелой — в теле остаётся РОВНО ОДНА
## стрела, та самая; убит в рукопашной — ни одной. Прежнее правило (одна-две
## при одиночном попадании, две-три при залпе) требовало РОЖДАТЬ недостающие
## стрелы отдельными узлами, а каждая торчащая стрела — это отдельный вызов
## отрисовки, живущий на поле десятками секунд.
func _test_arrows_in_body() -> void:
	verdict("I1 в теле держится ровно одна стрела",
		_Corpses.MAX_ARROWS_PER_CORPSE == 1,
		"MAX_ARROWS_PER_CORPSE = %d" % _Corpses.MAX_ARROWS_PER_CORPSE)

	# ── УБИТЫЙ В РУКОПАШНОЙ ЛЕЖИТ БЕЗ СТРЕЛ ────────────────────────────────
	# Отдельной ветки «не втыкать стрелу копейщику» в коде нет и быть не должно:
	# втыкает её сама стрела, а в рукопашной стрелы нет. Проверяем именно это
	var melee := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_GOBLIN, Vector3(-300.0, 0.0, -300.0))
	await pframes(3)
	_kill(melee)
	await pframes(2)
	var mlay: Array = GameManager.corpses.lay_of(GameManager.corpses.count() - 1)
	verdict("I2 павший в рукопашной лежит без единой стрелы",
		not mlay.is_empty() and int(mlay[4]) == 0,
		"стрел в теле: %d" % (int(mlay[4]) if not mlay.is_empty() else -1))

	var victim := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_GOBLIN, Vector3(-280.0, 0.0, -280.0))
	await pframes(3)
	var tp: Vector3 = victim.global_position
	var a := Arrow.new()
	a.faction = Constants.FACTION_PLAYER
	a.damage  = victim.max_health * 10.0 + 1000.0
	a._start_pos = tp + Vector3(-6.0, 1.6, 0.0)
	a._end_pos   = tp
	a._dist      = 6.0
	a._speed     = 12.0
	main.world_add(a)
	a.global_position = a._start_pos
	var waited := 0
	while waited < 240 and is_instance_valid(a) and not a._spent:
		await frames(4)
		waited += 4

	var idx: int = GameManager.corpses.count() - 1
	var lay: Array = GameManager.corpses.lay_of(idx)
	var n_arrows: int = int(lay[4]) if not lay.is_empty() else -1
	verdict("I3 убитый стрелой лежит ровно с одной стрелой",
		n_arrows == 1, "стрел в теле: %d" % n_arrows)

	# ── СТРЕЛЫ ЛЕЖАТ НА ТЕЛЕ, А НЕ РЯДОМ С НИМ ─────────────────────────────
	# Меряем расстояние от точки тела: стрела обязана попасть в габарит
	# туловища, иначе она висит в воздухе поодаль
	var far := 0.0
	if is_instance_valid(a):
		far = Vector2(a.global_position.x - tp.x, a.global_position.z - tp.z).length()
	verdict("I4 стрела лежит в габарите тела, а не поодаль", far < 1.5,
		"удалена от тела на %.2f м" % far)

	# ── ВИДНА, ПОКА ВИДНО ТЕЛО ─────────────────────────────────────────────
	# У воткнувшейся В ГРУНТ есть свой срок; у торчащей В ТЕЛЕ его нет — иначе
	# на поле оставались бы тела, из которых стрелы пропали
	var life0: float = a._stuck_life
	await frames(60)
	var life1: float = a._stuck_life
	verdict("I5 стрела в теле не стареет сама — её срок задаёт тело",
		is_instance_valid(a) and a._in_corpse and absf(life1 - life0) < 0.01,
		"счётчик был %.2f, стал %.2f" % [life0, life1])
	# А когда тело просит истаять — начинает
	a.fade_out_in(_Corpses.FADE_SEC)
	verdict("I6 просьба тела включает стреле растворение",
		not a._in_corpse
			and absf((Arrow.STUCK_LIFETIME - a._stuck_life) - _Corpses.FADE_SEC) < 0.01,
		"осталось %.2f c при сроке тела %.2f c"
			% [Arrow.STUCK_LIFETIME - a._stuck_life, _Corpses.FADE_SEC])
	if is_instance_valid(a):
		a.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# J. ПОТОЛОК ЧИСЛА ТОРЧАЩИХ СТРЕЛ
# ═════════════════════════════════════════════════════════════════════════════
## Стрела — это УЗЕЛ со своим мешем и своим материалом, то есть отдельный вызов
## отрисовки. Срок её жизни владелец заказал длинный (30-60 с), и без потолка
## затяжная перестрелка укладывала на луг тысячи таких узлов. Потолок трогает
## только ЧИСЛО, срок остаётся заказанным.
##
## Здесь же проверяется ГЛАВНАЯ ловушка вытеснения: догорающая стрела остаётся
## в списке до конца растворения, и если считать её занимающей место, каждая
## новая отправит гаснуть ещё одну — лавина, при которой поле пустеет целиком.
## Ровно эту ошибку стенд уже ловил на телах (см. блок C+D)
func _test_stuck_arrow_cap() -> void:
	var cap: int = GameManager.MAX_STUCK_ARROWS
	var over_by: int = 40
	var made: Array = []
	for i in range(cap + over_by):
		var s := Arrow.new()
		s._start_pos  = Vector3(-800.0 + float(i % 40), 0.6, -800.0 + float(i / 40))
		s._end_pos    = s._start_pos + Vector3(0.5, -0.5, 0.0)
		s._dist       = 0.7
		s._arc_factor = 0.0
		main.world_add(s)
		s.global_position = s._start_pos
		s._stick_into_ground()
		made.append(s)
	# Считаем НЕ ДОГОРАЮЩИЕ: они и есть «занятые места»
	var alive := 0
	var fading := 0
	for s in made:
		if not is_instance_valid(s):
			continue
		if s.is_fading():
			fading += 1
		else:
			alive += 1
	verdict("J1 торчащих стрел на поле не больше потолка", alive <= cap,
		"негаснущих %d при потолке %d" % [alive, cap])
	# Гаснуть обязан ТОЛЬКО перебор, а не всё поле
	verdict("J2 вытеснение не превращается в лавину",
		fading > 0 and fading <= over_by + 20,
		"догорает %d, перебор был %d" % [fading, over_by])
	for s in made:
		if is_instance_valid(s):
			s.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# K+L. ГАШЕНИЕ СТРЕЛЫ И ОБЪЁМ ЗАВАЛА
# ═════════════════════════════════════════════════════════════════════════════
## K. ЧЁРНЫЙ ПРЯМОУГОЛЬНИК ПОД ГАСНУЩЕЙ СТРЕЛОЙ. Гашение делалось так: альфа
## modulate падала до нуля, а ПОРОГ СРЕЗА снимался в ноль — «срез не умеет
## гасить плавно». Но материал со срезом Godot относит к НЕПРОЗРАЧНОМУ проходу,
## записанную ALPHA там не читают, и порог оставался единственным, что отсекало
## пустоту вокруг стрелы. Обнулили порог — весь квад поехал на экран своим
## цветом (0,0,0). Теперь гасит дизер, а порог не трогают никогда.
##
## L. ЗАВАЛ ОБЯЗАН ЧИТАТЬСЯ ОБЪЁМОМ. Одинаково яркие тела одного размера
## выглядят повторённой наклейкой; притенение нижних слоёв и разнокалиберность
## дают глубину, не стоя ни одного лишнего вызова отрисовки
func _test_fade_and_volume() -> void:
	var a := Arrow.new()
	a._start_pos = Vector3(-900.0, 0.5, -900.0)
	a._end_pos   = Vector3(-899.0, 0.5, -900.0)
	a._dist      = 1.0
	a._arc_factor = 0.0
	main.world_add(a)
	a.global_position = a._start_pos
	await frames(1)
	var scissor_full: float = a._mat.get_shader_parameter("alpha_scissor")
	a._set_fade(0.5)
	var scissor_fade: float = a._mat.get_shader_parameter("alpha_scissor")
	verdict("K1 гашение НЕ снимает порог среза (иначе весь квад — чёрный)",
		absf(scissor_fade - scissor_full) < 0.0001 and scissor_fade > 0.0,
		"порог был %.2f, стал %.2f" % [scissor_full, scissor_fade])
	verdict("K2 гашение идёт покрытием, а не альфой",
		absf(float(a._mat.get_shader_parameter("fade")) - 0.5) < 0.0001,
		"fade = %.2f" % float(a._mat.get_shader_parameter("fade")))
	a.queue_free()
	await frames(1)

	# ── K3. УГОЛ ВТЫКАНИЯ У КАЖДОЙ СТРЕЛЫ СВОЙ ─────────────────────────────
	# Одинаковый наклон читается штампом, а не полем после обстрела
	var axes: Array = []
	for i in range(12):
		var st := Arrow.new()
		st._start_pos  = Vector3(-880.0 + float(i) * 1.7, 0.5, -880.0)
		st._end_pos    = st._start_pos + Vector3(1.0, -0.4, 0.0)
		st._dist       = 1.1
		st._arc_factor = 0.0
		main.world_add(st)
		st.global_position = st._start_pos
		st._stick_into_ground()
		axes.append((st._mat.get_shader_parameter("axis") as Vector3).normalized())
	var min_dot := 1.0
	for i in range(axes.size()):
		for j in range(i + 1, axes.size()):
			min_dot = minf(min_dot, (axes[i] as Vector3).dot(axes[j] as Vector3))
	var spread_deg: float = rad_to_deg(acos(clampf(min_dot, -1.0, 1.0)))
	verdict("K3 воткнувшиеся стрелы стоят под разными углами",
		spread_deg > 8.0, "самая большая разница углов %.0f°" % spread_deg)
	for st2 in _stuck_probe_cleanup():
		pass

	# ── L. ОБЪЁМ ЗАВАЛА ────────────────────────────────────────────────────
	var n: int = mini(30, GameManager.corpses.count())
	var tints: Dictionary = {}
	var scales: Dictionary = {}
	var dark := 1.0
	var bright := 0.0
	for i in range(GameManager.corpses.count() - n, GameManager.corpses.count()):
		var lay: Array = GameManager.corpses.lay_of(i)
		if lay.size() < 7:
			continue
		var t: float = float(lay[5])
		tints[snappedf(t, 0.01)] = true
		scales[snappedf(float(lay[6]), 0.01)] = true
		dark = minf(dark, t)
		bright = maxf(bright, t)
	verdict("L1 тела в завале притенены по-разному (глубина читается)",
		tints.size() >= 5 and bright - dark > 0.1,
		"оттенков %d, от %.2f до %.2f" % [tints.size(), dark, bright])
	verdict("L2 ни одно тело не уходит в черноту",
		dark >= _Corpses.TINT_DARKEST - 0.001,
		"самое тёмное %.2f при пороге %.2f" % [dark, _Corpses.TINT_DARKEST])
	verdict("L3 тела разного калибра, а не штампованные клоны",
		scales.size() >= 5,
		"различных размеров %d из %d тел" % [scales.size(), n])

## Стрелы пробы K3 уходят в пул сами (они торчащие и учтены потолком); здесь
## только снимаем их с поля, чтобы не мешали следующим блокам
func _stuck_probe_cleanup() -> Array:
	return []
