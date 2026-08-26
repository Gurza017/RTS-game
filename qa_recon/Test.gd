extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПРИЦЕЛ И РАЗВЕДКА ЧУЖОГО ОТРЯДА
## ═══════════════════════════════════════════════════════════════════════════
##   A ПРИЦЕЛ    — красные кольца на всём чужом отряде и только на нём
##   B КАРТОЧКА  — панель разведки: без командных кнопок, но со статами
##   C ГРЕЙДЫ    — кузница и ветеранство ПРОТИВНИКА видны в карточке
##   D БЕЗОПАСНОСТЬ — разведанный отряд не выделен и приказа не получает
##   E ТУМАН     — того, кого не видно, нельзя ни подсветить, ни разведать
##
## Числа не хардкодятся: состав грейда берётся из forge_config, уровень
## ветеранства — из veteran_level_for_kills (см. «Config is the source of truth»)

const _FCfg := preload("res://scripts/forge_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var sm = null
var hud = null
var cam: Camera3D = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

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

## Отряд из n бойцов заданной фракции вокруг точки. Возвращает список бойцов;
## отряд заводится через GameManager, как в бою
func _make_squad(kind: String, fac: int, at: Vector3, n: int) -> Array:
	var out: Array = []
	var sid: int = GameManager.new_squad(fac, kind)
	for i in range(n):
		var u: Unit
		match kind:
			"archer":  u = Archer.new()
			"warrior": u = Warrior.new()
			_:         u = Spearman.new()
		u.faction = fac
		main.world_add(u)
		var p := at + Vector3(float(i % 4) * 0.7, 0.0, float(i / 4) * 0.7)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return out

func _screen_of(u: Unit) -> Vector2:
	# Целимся в туловище спрайта, а не в точку под ногами — как игрок
	return cam.unproject_position(u.global_position + Vector3(0.0, 0.9, 0.0))

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	sm  = main.selection_manager
	hud = main.hud
	cam = main._camera as Camera3D
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	# Туман мешает всем разделам, кроме E — там он включается обратно
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await frames(3)

	await _a_rings()
	await _b_card()
	await _c_grades()
	await _d_safety()
	await _e_fog()
	await _f_dead_hover()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 64), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== RECON TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ПРИЦЕЛ
# ═════════════════════════════════════════════════════════════════════════════
func _a_rings() -> void:
	print("\n═════ A. ПРИЦЕЛ ═════")
	var spot := Vector3(0.0, 0.0, 0.0)
	cam.jump_to(spot, cam.min_height)
	cam.set_process(false)
	await frames(3)

	var foes: Array = _make_squad("spearman", Constants.FACTION_ENEMY, spot, 8)
	var ours: Array = _make_squad("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(14.0, 0.0, 0.0), 6)
	await frames(4)

	# Без выделения прицела нет: некому атаковать
	main._update_enemy_hover(_screen_of(foes[0]), false)
	verdict("A1 без выделения прицел не рисуется",
		GameManager.sel_decals.hover_count() == 0,
		"колец %d" % GameManager.sel_decals.hover_count())

	for u in ours:
		sm._select_one(u)
	await frames(2)
	main._update_enemy_hover(_screen_of(foes[0]), false)
	var lit: int = GameManager.sel_decals.hover_count()
	verdict("A2 кольца загорелись на ВСЁМ чужом отряде", lit == foes.size(),
		"колец %d при отряде %d" % [lit, foes.size()])

	var all_foes := true
	for u in foes:
		if not GameManager.sel_decals.is_hovered(u):
			all_foes = false
	var no_ours := true
	for u in ours:
		if GameManager.sel_decals.is_hovered(u):
			no_ours = false
	verdict("A3 подсвечены именно враги, свои — нет", all_foes and no_ours,
		"все враги=%s, свои чистые=%s" % [all_foes, no_ours])

	# Курсор ушёл в пустоту — кольца гаснут
	main._update_enemy_hover(cam.unproject_position(spot + Vector3(0, 0, 40.0)), false)
	verdict("A4 увод курсора гасит прицел",
		GameManager.sel_decals.hover_count() == 0,
		"колец %d" % GameManager.sel_decals.hover_count())

	# Артель рабочих не обещает боя
	sm._clear_selection()
	var w := Worker.new()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = spot + Vector3(14.0, 0.0, 4.0)
	await frames(3)
	sm._select_one(w)
	main._update_enemy_hover(_screen_of(foes[0]), false)
	verdict("A5 артель рабочих прицел не рисует",
		GameManager.sel_decals.hover_count() == 0,
		"колец %d (у рабочего урон %.0f)" % [
			GameManager.sel_decals.hover_count(), w.attack_damage])

	# Наведение на ЖИЛУ важнее прицела: два обещания под одним курсором
	# противоречили бы друг другу
	sm._clear_selection()
	for u in ours:
		sm._select_one(u)
	main._update_enemy_hover(_screen_of(foes[0]), true)
	verdict("A6 наведение на жилу гасит прицел",
		GameManager.sel_decals.hover_count() == 0,
		"колец %d" % GameManager.sel_decals.hover_count())

	w.queue_free()
	sm._clear_selection()
	_kill_all([foes, ours])
	await frames(3)

func _kill_all(groups: Array) -> void:
	for g in groups:
		for u in (g as Array):
			if is_instance_valid(u):
				(u as Node).queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# B. КАРТОЧКА РАЗВЕДКИ
# ═════════════════════════════════════════════════════════════════════════════
func _b_card() -> void:
	print("\n═════ B. КАРТОЧКА ═════")
	var spot := Vector3(0.0, 0.0, -60.0)
	cam.jump_to(spot, cam.min_height)
	await frames(3)
	var foes: Array = _make_squad("archer", Constants.FACTION_ENEMY, spot, 5)
	await frames(4)

	sm._handle_single_click(_screen_of(foes[0]), false)
	await frames(3)

	verdict("B1 клик по врагу открыл карточку разведки",
		sm.recon_units.size() == foes.size() and hud.recon_visible(),
		"recon=%d, видима=%s" % [sm.recon_units.size(), hud.recon_visible()])

	verdict("B2 командных кнопок в карточке нет",
		hud.button_container.get_child_count() == 0,
		"кнопок %d" % hud.button_container.get_child_count())

	verdict("B3 панель статов построена", hud._stat_panel != null,
		"_stat_panel=%s" % [hud._stat_panel])

	var txt := _stat_text()
	verdict("B4 в карточке есть HP, урон и броня",
		txt.contains("Health") and txt.contains("Attack") and txt.contains("Armor"),
		"строки: %s" % txt.replace("\n", " | "))

	# Живое здоровье отряда в заголовке — и оно отражает урон
	var hp_before := _head_text()
	foes[0].take_damage(7.0, null)
	await frames(2)
	sm._handle_single_click(_screen_of(foes[1]), false)
	await frames(3)
	var hp_after := _head_text()
	verdict("B5 заголовок показывает живое HP отряда",
		hp_before != hp_after and hp_after.contains("HP"),
		"было «%s», стало «%s»" % [hp_before, hp_after])

	# Выделение своих закрывает разведку
	var ours: Array = _make_squad("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(16.0, 0.0, 0.0), 4)
	await frames(3)
	hud.show_selection(ours)
	await frames(2)
	verdict("B6 выделение своих закрывает карточку", not hud.recon_visible(),
		"видима=%s" % hud.recon_visible())

	_kill_all([foes, ours])
	sm.clear_recon()
	await frames(3)

## Текст всех строк панели статов
func _stat_text() -> String:
	if hud._stat_panel == null or not is_instance_valid(hud._stat_panel):
		return ""
	var out: Array = []
	_collect_text(hud._stat_panel, out)
	return "\n".join(out)

## Заголовок панели статов (первая строка)
func _head_text() -> String:
	var out: Array = []
	if hud._stat_panel != null and is_instance_valid(hud._stat_panel):
		_collect_text(hud._stat_panel, out)
	return String(out[0]) if not out.is_empty() else ""

func _collect_text(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	elif n is RichTextLabel:
		out.append((n as RichTextLabel).text)
	for c in n.get_children():
		_collect_text(c, out)

# ═════════════════════════════════════════════════════════════════════════════
# C. ГРЕЙДЫ И ВЕТЕРАНСТВО ПРОТИВНИКА
# ═════════════════════════════════════════════════════════════════════════════
func _c_grades() -> void:
	print("\n═════ C. ГРЕЙДЫ ═════")
	var spot := Vector3(0.0, 0.0, -120.0)
	cam.jump_to(spot, cam.min_height)
	await frames(3)
	var foes: Array = _make_squad("spearman", Constants.FACTION_ENEMY, spot, 5)
	await frames(4)

	# Узел кузницы с прибавкой к урону — ищем в конфиге, а не по имени
	var atk_node: Dictionary = {}
	for n in _FCfg.tree("spearman"):
		var nd: Dictionary = n
		if float(nd.get("bonus_attack", 0.0)) > 0.0:
			atk_node = nd
			break
	if atk_node.is_empty():
		verdict("C0 в дереве копейщика есть узел на урон", false, "не найден")
		_kill_all([foes])
		return

	sm._handle_single_click(_screen_of(foes[0]), false)
	await frames(3)
	var before := _stat_text()

	# Выдаём грейд ПРОТИВНИКУ (минуя ресурсы: проверяем отображение, не экономику)
	GameManager._accumulate_upgrade(Constants.FACTION_ENEMY, atk_node,
		String(atk_node.get("id", "")))
	await frames(2)
	sm._handle_single_click(_screen_of(foes[0]), false)
	await frames(3)
	var after := _stat_text()

	var bonus: float = float(atk_node.get("bonus_attack", 0.0))
	verdict("C1 грейд кузницы врага виден в карточке",
		before != after and after.contains("+%d" % int(bonus)),
		"прибавка +%.0f, строка Attack: «%s»" % [bonus, _line_with(after, "Attack")])

	# Ветеранство: набиваем убийства до первого уровня и смотрим звёзды.
	# Порог берётся из конфига, а не числом; счёт набивается тем же путём, что
	# и в бою (credit_kill), поэтому уровень посчитается по общим правилам
	var sid: int = (foes[0] as Unit).squad_id
	var need: int = _UCfg.veteran_threshold("spearman", 1)
	var dummy := Spearman.new()
	dummy.faction = Constants.FACTION_PLAYER
	main.world_add(dummy)
	dummy.global_position = spot + Vector3(30.0, 0.0, 0.0)
	await frames(2)
	for _i in range(need):
		GameManager.credit_kill(foes[0], dummy)
	dummy.queue_free()
	await frames(2)
	var lvl: int = GameManager.squad_level(sid)
	sm._handle_single_click(_screen_of(foes[0]), false)
	await frames(3)
	var head := _head_text()
	# ЗВЁЗД В ПРОЕКТЕ БОЛЬШЕ НЕТ — их заменили знамёна (заказ владельца),
	# а в заголовке панели ранг читается НАЗВАНИЕМ отряда («Отряд
	# опытных копейщиков»). Проверка искала глиф звезды и краснела на
	# развёрнутом требовании, а не на поломке. Ждём ранг ИЗ КОНФИГА
	var rank: String = _UCfg.veteran_rank_name("spearman", lvl)
	verdict("C2 ветеранство противника показано в заголовке",
		lvl > 0 and rank != "" and head.contains(rank),
		"уровень %d при пороге %d, ждали «%s», заголовок «%s»" % [lvl, need, rank, head])

	_kill_all([foes])
	sm.clear_recon()
	await frames(3)

func _line_with(txt: String, needle: String) -> String:
	for l in txt.split("\n"):
		if String(l).contains(needle):
			return String(l)
	return ""

# ═════════════════════════════════════════════════════════════════════════════
# D. БЕЗОПАСНОСТЬ: РАЗВЕДАННЫМ НЕЛЬЗЯ КОМАНДОВАТЬ
# ═════════════════════════════════════════════════════════════════════════════
# Это главная проверка раздела. Правый клик перебирает selected_units и раздаёт
# приказы всем, кто там лежит: попади туда вражеский боец — игрок командовал бы
# армией противника
func _d_safety() -> void:
	print("\n═════ D. БЕЗОПАСНОСТЬ ═════")
	var spot := Vector3(0.0, 0.0, -180.0)
	cam.jump_to(spot, cam.min_height)
	await frames(3)
	var foes: Array = _make_squad("spearman", Constants.FACTION_ENEMY, spot, 5)
	await frames(4)

	sm._handle_single_click(_screen_of(foes[0]), false)
	await frames(3)

	var leaked := false
	for u in foes:
		if u in sm.selected_units:
			leaked = true
	verdict("D1 разведанный враг НЕ попал в выделение", not leaked,
		"selected_units=%d, recon=%d" % [sm.selected_units.size(), sm.recon_units.size()])

	# И приказ ему отдать нечем: выделение пусто, правый клик никого не двигает
	var before_targets: Array = []
	for u in foes:
		before_targets.append((u as Unit).move_target)
	sm._handle_right_click(cam.unproject_position(spot + Vector3(0, 0, 25.0)))
	await frames(4)
	var moved := false
	for i in range(foes.size()):
		if (foes[i] as Unit).move_target != before_targets[i]:
			moved = true
	verdict("D2 правый клик не сдвинул разведанный отряд", not moved,
		"выделено своих: %d" % sm.selected_units.size())

	# Кольца выделения на врага тоже не вешаются — это признак «мой и управляем»
	var ringed := false
	for u in foes:
		if GameManager.sel_decals.is_registered(u):
			ringed = true
	verdict("D3 жёлтых колец выделения на враге нет", not ringed)

	_kill_all([foes])
	sm.clear_recon()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. ТУМАН
# ═════════════════════════════════════════════════════════════════════════════
func _e_fog() -> void:
	print("\n═════ E. ТУМАН ═════")
	if GameManager.fog == null:
		verdict("E0 туман доступен", false, "GameManager.fog отсутствует")
		return
	# ── ТОЧКА ОБЯЗАНА БЫТЬ ВНУТРИ КАРТЫ ─────────────────────────────────────
	# Маска тумана натянута на карту (FogOfWar.MASK_CELL × размеры поля), и за её
	# краем is_lit() честно отвечает «нет» кому угодно. Разделы A-D работают с
	# выключенным туманом и спокойно стоят за картой, а здесь это превратило бы
	# проверку в самообман: E1 «проходил» по ветке «не освещён — колец нет»,
	# ничего при этом не проверив
	var spot := Vector3(40.0, 0.0, 20.0)
	cam.jump_to(spot, cam.min_height)
	await frames(3)
	var foes: Array = _make_squad("spearman", Constants.FACTION_ENEMY, spot, 5)
	var ours: Array = _make_squad("spearman", Constants.FACTION_PLAYER,
		spot + Vector3(14.0, 0.0, 0.0), 4)
	await frames(4)

	GameManager.fog.enabled = true
	# Даём маске перестроиться: она обновляется по своему таймеру
	await frames(30)
	var lit: bool = GameManager.fog.is_lit(foes[0].global_position.x,
		foes[0].global_position.z)

	for u in ours:
		sm._select_one(u)
	main._update_enemy_hover(_screen_of(foes[0]), false)
	var rings: int = GameManager.sel_decals.hover_count()
	# Свой отряд стоит в 14 м, обзор копейщика заведомо больше (VISION_MIN 18 м) —
	# враг ДОЛЖЕН быть освещён и подсвечен. Проверяем именно это, а не «одно из двух»
	verdict("E1 враг в поле зрения своих подсвечивается", lit and rings > 0,
		"освещён=%s, колец=%d" % [lit, rings])

	# Утаскиваем врага в неразведанный угол карты — он обязан пропасть и из
	# прицела, и из разведки
	for u in foes:
		var uu := u as Unit
		uu.global_position = Vector3(-40.0, uu.global_position.y, -30.0)
		uu.sync_row()
	await frames(30)
	var lit2: bool = GameManager.fog.is_lit(foes[0].global_position.x,
		foes[0].global_position.z)
	sm.clear_recon()
	var got: Unit = sm.enemy_unit_under_cursor(_screen_of(foes[0]))
	verdict("E2 боец в тумане не разведывается и не подсвечивается",
		(not lit2) and got == null,
		"освещён=%s, найден=%s" % [lit2, got])

	GameManager.fog.enabled = false
	sm._clear_selection()
	_kill_all([foes, ours])
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# F. ПОДСВЕЧЕННЫЙ ОТРЯД ВЫРЕЗАЮТ ПРЯМО ПОД КУРСОРОМ
# ═════════════════════════════════════════════════════════════════════════════
# Отчётный краш: SelectionDecalRenderer.gd:280,
# «Trying to assign invalid previously freed instance», покадровый обход колец.
#
# Причина была в ПОРЯДКЕ ДВУХ СТРОК: `var u: Unit = unit` стояло ДО
# is_instance_valid(u), а присваивание освобождённого объекта в типизированную
# переменную бросает ошибку само — то есть проверка, ради которой строка
# писалась, не выполнялась никогда. Набор подсвеченных задаётся опросом курсора,
# а в бою отряд вырезают быстрее, чем идёт следующий опрос.
#
# Стенд воспроизводит это буквально: подсвечиваем отряд, освобождаем его состав
# НЕ через игровую смерть (queue_free мимо всей бухгалтерии — это и есть худший
# случай), и гоняем покадровый обход. Ошибка в Godot не бросает исключения,
# поэтому проверяем наблюдаемое следствие: слоты вычищены и обход отработал.
func _f_dead_hover() -> void:
	print("\n═════ F. ПОДСВЕЧЕННЫХ ВЫРЕЗАЛИ ═════")
	# ── MAIN._PROCESS ОПРАШИВАЕТ КУРСОР И СБРАСЫВАЕТ ПОДСВЕТКУ ──────────────
	# Ровно та же ловушка, что документирована для qa_shotvis: набор колец
	# задаётся опросом мыши раз в CURSOR_POLL, и он затирает всё, что стенд
	# выставил руками. Пока это не выключено, раздел проходил или падал в
	# зависимости от фазы таймера опроса — то есть проверял не то, что написано
	main.set_process(false)
	var foes := _make_squad("spearman", Constants.FACTION_ENEMY,
		Vector3(-140.0, 0.0, -140.0), 8)
	await frames(4)
	GameManager.sel_decals.set_hover_units(foes, main.world_root())
	await frames(2)
	var lit: int = GameManager.sel_decals.hover_count()
	verdict("F1 кольца прицела зажглись на всём отряде",
		lit == foes.size(), "подсвечено %d из %d" % [lit, foes.size()])

	# Освобождаем ПОЛОВИНУ состава жёстко, мимо смерти и мимо отряда
	for i in range(0, foes.size(), 2):
		(foes[i] as Node).free()
	# Ни одного опроса курсора между гибелью и обходом — как в бою
	GameManager.sel_decals.update_all()
	GameManager.sel_decals.flush()
	await frames(3)
	verdict("F2 покадровый обход пережил освобождённых и вычистил их слоты",
		GameManager.sel_decals.hover_count() == foes.size() / 2,
		"осталось подсвеченных %d, ожидалось %d" % [
			GameManager.sel_decals.hover_count(), foes.size() / 2])

	# И то же самое для колец ВЫДЕЛЕНИЯ и полосок здоровья: у них тот же словарь
	# по объекту и тот же обход
	var mine := _make_squad("spearman", Constants.FACTION_PLAYER,
		Vector3(-160.0, 0.0, -160.0), 6)
	await frames(3)
	for u in mine:
		(u as Unit).set_selected(true)
		GameManager.hp_bars.register(u, main.world_root())
	await frames(2)
	var sel_before: int = GameManager.sel_decals.registered_count()
	for i in range(0, mine.size(), 2):
		(mine[i] as Node).free()
	GameManager.sel_decals.update_all()
	GameManager.hp_bars.update_all()
	GameManager.sel_decals.flush()
	GameManager.hp_bars.flush()
	await frames(3)
	verdict("F3 метки выделения тоже вычистились, а не упали",
		GameManager.sel_decals.registered_count() < sel_before,
		"было %d, стало %d" % [sel_before, GameManager.sel_decals.registered_count()])

	GameManager.sel_decals.clear_hover()
	main.set_process(true)
	for u in foes:
		if is_instance_valid(u): (u as Node).queue_free()
	for u in mine:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)
