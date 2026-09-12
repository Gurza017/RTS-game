extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## СОХРАНЕНИЕ И ЗАГРУЗКА ПАРТИИ
## ═══════════════════════════════════════════════════════════════════════════
## Файл намеренно без class_name и без автозагрузки: подключается через preload
## (const _Save := preload("res://scripts/SaveLoadManager.gd")), всё внутри —
## статическое. Автозагрузка тут ничего не дала бы: у подсистемы нет своего
## состояния между вызовами, она целиком «снять слепок — записать — вернуть».
##
## ── ГЛАВНОЕ РЕШЕНИЕ: МИР НЕ СОХРАНЯЕТСЯ, ОН ПЕРЕСЕВАЕТСЯ ───────────────────
## Карта — рельеф, лес, кусты, вода, облака, россыпи руды — строится ГЕНЕРАТОРОМ
## по случайным числам (Main._ready → _setup_terrain, Main.start_game →
## _spawn_resource_nodes). Тысячи деревьев и камней в файле сохранения весили бы
## больше всей остальной партии вместе взятой, а читались бы дольше, чем
## генерируются.
##
## Поэтому сохраняется ЗЕРНО (Main.world_seed), а мир пересевается из него —
## тот же seed даёт ту же карту до последнего куста. Это же и есть ответ на
## вопрос «безопасно ли к изменениям версий»: если генератор карты в новой
## версии изменится, старое сохранение даст ДРУГУЮ карту, и это надо ловить, а
## не молча грузить. Для того в заголовке и лежит WORLD_GEN_VERSION — её
## поднимает тот, кто правит генератор.
##
## ── ЧТО ИМЕННО ЛОЖИТСЯ В ФАЙЛ ──────────────────────────────────────────────
##   • зерно мира, расы и цвета сторон, сложность, время партии;
##   • склад каждой фракции (четыре числа);
##   • изученное в кузнице и накопленные бонусы фракций;
##   • постройки: тип, сторона, точка, запас жизни;
##   • отряды: род войск, ранг, счёт убийств, невыбранные награды, СПИСОК уже
##     выбранных наград и докупленные способности;
##   • бойцы: род войск, сторона, отряд, точка, текущий запас жизни.
##
## ── ЧТО НЕ ЛОЖИТСЯ И ПОЧЕМУ ────────────────────────────────────────────────
## Всё, что живёт секунды и восстанавливается само:
##   • стрелы в полёте и воткнувшиеся, тела павших, вмятины строя;
##   • туман войны (разведка восстановится за первый же обход);
##   • незавершённые стройплощадки и незаконченные заказы найма — их
##     сохранение потребовало бы хранить ещё и уплаченную цену, чтобы отмена
##     возвращала ровно списанное (см. Building.queue_unit), а выигрыш нулевой:
##     игрок закажет заново;
##   • приказы и цели: после загрузки войско СТОИТ. Это осознанно — приказ
##     ссылается на конкретный узел цели, а узлы после загрузки другие, и
##     восстановленная ссылка указывала бы в пустоту.
##
## ── ФОРМАТ ─────────────────────────────────────────────────────────────────
## Бинарный, через FileAccess. Заголовок: магия + версия формата + версия
## генератора мира, дальше ОДИН store_var со словарём состояния.
##
## ПОЧЕМУ НЕ JSON. Бойцов на карте до шести тысяч, и в JSON каждый — это
## отдельный объект с именами полей: файл на десятки мегабайт и разбор в
## секунды. Здесь бойцы лежат КОЛОНКАМИ (PackedInt32Array / PackedFloat32Array)
## — ровно так же, как в ядре армии, — и store_var кладёт их одним блоком
## памяти. Шесть тысяч бойцов это 6000×(4+4+4+12+4) байт ≈ 170 КБ.
##
## ПОЧЕМУ ЭТО ВСЁ РАВНО БЕЗОПАСНО К ВЕРСИЯМ. Словарь состояния читается ТОЛЬКО
## по именам ключей и всегда с умолчанием (см. _get). Добавили поле — старые
## сохранения читаются, новое берётся из умолчания. Переименовали или сменили
## смысл — поднимается FORMAT_VERSION, и старый файл честно отклоняется с
## внятным сообщением вместо тихой порчи партии.

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _Diff  := preload("res://scripts/game_difficulty_config.gd")

## Магия файла: «TTSS» (Ten Thousand Spearmen Save). Первое, что читается, и
## первое, что отсеивает чужой файл, подсунутый вместо сохранения
const MAGIC := 0x54545353

## ВЕРСИЯ ФОРМАТА. Поднимается, когда меняется СМЫСЛ уже существующих полей.
## Добавление нового поля версию НЕ поднимает — оно читается с умолчанием
const FORMAT_VERSION := 1

## ВЕРСИЯ ГЕНЕРАТОРА МИРА. Поднимает тот, кто правит генерацию карты в Main:
## рельеф, лес, кусты, воду, россыпи руды, места баз. Если она не совпадает,
## зерно даст ДРУГУЮ карту — постройки и войска встанут посреди леса и воды,
## поэтому такое сохранение отклоняется, а не грузится «как получится»
## 2 — по краям рудных гряд теперь растут кусты (Main._scatter_cluster_bushes).
## Сама расстановка руды не изменилась, но кусты берут числа из ТОГО ЖЕ
## генератора случайных, что и всё остальное: поток сдвинулся, и одно зерно
## даёт другой лес и другое озеро. Старое сохранение легло бы постройками на
## чужой рельеф, поэтому версия поднята и такие файлы честно отклоняются
## 3 — вариант рисунка куска руды выбирается по классу прямо при спавне кучи
## (Main.ORE_VARIANT_POOLS): на каждый кусок добавился вызов randi(), поток
## генератора сдвинулся — то же зерно даёт другой лес и другое озеро
## 4 (10.09.2026): плато, река в низине, ничейные рудники с резервом площадок,
## кусты на плато — то же зерно даёт другой мир
## 4 → 5 (спринт 13): в генерацию мира добавлен рассев декораций Deco 01-18
## (Main._scatter_deco). Сама расстановка леса и руды не менялась, но
## декорации берут числа из ТОГО ЖЕ генератора случайных — поток сдвинулся, и
## одно зерно даёт другой лес. Старое сохранение легло бы постройками на
## чужой рельеф (та же причина, что у версий 2 и 3)
## 6 (спринт 18): площадка второго пня у ИИ резервируется от леса — лес
## сеется иначе, то же зерно даёт другую карту
const WORLD_GEN_VERSION := 6

## Сколько слотов сохранения показывает интерфейс
const SLOT_COUNT := 3

## Путь к файлу слота. user:// — единственное место, куда игра вправе писать:
## каталог игры в экспорте может лежать в Program Files и быть только для чтения
static func slot_path(slot: int) -> String:
	return "user://save_%d.tts" % clampi(slot, 1, SLOT_COUNT)

# ═════════════════════════════════════════════════════════════════════════════
# СНЯТЬ СЛЕПОК
# ═════════════════════════════════════════════════════════════════════════════
## Слепок ЖИВОЙ партии. Ничего не пишет на диск и ничего не меняет в игре:
## отделено намеренно, потому что этим же слепком пользуется стенд, сверяя
## состояние до и после загрузки без единого обращения к файловой системе
static func capture(main: Node) -> Dictionary:
	var state: Dictionary = {
		"meta": _capture_meta(main),
		"resources": _capture_resources(),
		"research": _capture_research(),
		"squads": _capture_squads(),
		"buildings": _capture_buildings(main),
	}
	# Бойцы идут ПОСЛЕ отрядов: колонка squad ссылается на номера, которые
	# отряды уже перечислили, и порядок делает файл читаемым глазами
	state["units"] = _capture_units(main)
	return state

static func _capture_meta(main: Node) -> Dictionary:
	return {
		"format": FORMAT_VERSION,
		"world_gen": WORLD_GEN_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"world_seed": int(main.world_seed) if main != null else 0,
		"difficulty": _Diff.current(),
		"player_faction": GameManager.player_faction_name,
		"ai_faction": GameManager.ai_faction_name,
		"player_color": GameManager.player_color,
		"ai_color": GameManager.ai_color,
		# Часы партии нужны орде: её расписание (спячка, волны) считается от
		# начала матча, и без этого числа загруженная на сороковой минуте
		# партия начиналась бы с проснувшейся ордой заново
		"clock": float(main.game_clock()),
	}

static func _capture_resources() -> Dictionary:
	var out: Dictionary = {}
	for f in range(Constants.FACTION_COUNT):
		var row: Dictionary = {}
		for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
				Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
			row[int(t)] = ResourceManager.get_amount(f, int(t))
		out[f] = row
	return out

## Изученное в кузнице — СПИСКОМ ID, а не готовыми бонусами. Бонусы фракции
## пересчитываются из списка при загрузке (тем же путём, каким их даёт кузница),
## поэтому правка чисел в forge_config доезжает и до старых сохранений
static func _capture_research() -> Dictionary:
	var out: Dictionary = {}
	for f in GameManager.researched:
		var ids: Array = []
		for k in (GameManager.researched[f] as Dictionary):
			if bool((GameManager.researched[f] as Dictionary)[k]):
				ids.append(String(k))
		out[int(f)] = ids
	return out

static func _capture_squads() -> Array:
	var out: Array = []
	for sid in GameManager.squads:
		var sq: Dictionary = GameManager.squads[sid]
		# Пустой отряд в файл не идёт: он и в игре живёт до ближайшего
		# обращения (squad_members распускает такие прямо в геттере)
		if (sq["members"] as Array).is_empty():
			continue
		out.append({
			"id":       int(sid),
			"faction":  int(sq["faction"]),
			"type":     String(sq["type"]),
			"kills":    int(sq["kills"]),
			"level":    int(sq["level"]),
			"pending":  int(sq["pending"]),
			"chosen":   (sq["chosen"] as Array).duplicate(),
			"bonuses":  (sq["bonuses"] as Dictionary).duplicate(),
			"abilities": (sq["abilities"] as Dictionary).keys(),
		})
	return out

static func _capture_buildings(main: Node) -> Array:
	var out: Array = []
	if main == null:
		return out
	for f in range(Constants.FACTION_COUNT):
		for b in main.get_tree().get_nodes_in_group(Constants.building_group(f)):
			if not is_instance_valid(b):
				continue
			var bld := b as Building
			if bld == null or String(bld.building_id).is_empty():
				continue
			# Стройплощадка в файл не идёт: её building_id пуст по построению
			# (см. ConstructionSite._ready), и эта же проверка её и отсеивает
			out.append({
				"id":      String(bld.building_id),
				"faction": int(bld.faction),
				"pos":     bld.global_position,
				"hp":      float(bld.current_health),
			})
	return out

## БОЙЦЫ ЛОЖАТСЯ КОЛОНКАМИ, А НЕ СПИСКОМ СЛОВАРЕЙ.
## Шесть тысяч словарей по пять ключей — это шесть тысяч аллокаций при чтении
## и вчетверо больший файл. Колонка — один блок памяти, который store_var
## пишет и читает целиком (тот же приём, что в ядре армии: см. ArmySoA).
static func _capture_units(main: Node) -> Dictionary:
	var types: Array = []          # словарь типов: индекс → строка
	var type_ix: Dictionary = {}   # обратный: строка → индекс
	var col_type := PackedInt32Array()
	var col_fac  := PackedInt32Array()
	var col_sid  := PackedInt32Array()
	var col_pos  := PackedFloat32Array()
	var col_hp   := PackedFloat32Array()
	if main == null:
		return {"types": types, "type": col_type, "faction": col_fac,
			"squad": col_sid, "pos": col_pos, "hp": col_hp}
	for u in _live_units(main):
		var unit := u as Unit
		var t: String = String(unit.stat_id)
		if not type_ix.has(t):
			type_ix[t] = types.size()
			types.append(t)
		col_type.append(int(type_ix[t]))
		col_fac.append(int(unit.faction))
		col_sid.append(int(unit.squad_id))
		var p: Vector3 = unit.global_position
		col_pos.append(p.x); col_pos.append(p.y); col_pos.append(p.z)
		col_hp.append(float(unit.current_health))
	return {"types": types, "type": col_type, "faction": col_fac,
		"squad": col_sid, "pos": col_pos, "hp": col_hp}

# ═════════════════════════════════════════════════════════════════════════════
# ЗАПИСЬ И ЧТЕНИЕ ФАЙЛА
# ═════════════════════════════════════════════════════════════════════════════
## Записать слепок в слот. Возвращает пустую строку при успехе и текст ошибки
## для интерфейса — не bool: игроку надо показать ПРИЧИНУ, а не «не вышло»
static func save_game(main: Node, slot: int) -> String:
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		return "Не удалось открыть файл сохранения (код %d)" % FileAccess.get_open_error()
	f.store_32(MAGIC)
	f.store_32(FORMAT_VERSION)
	f.store_32(WORLD_GEN_VERSION)
	# full_objects = false НАМЕРЕННО: в слепке нет и не должно быть ссылок на
	# узлы. Разреши их — и в файл уехал бы кусок дерева сцены, а чтение такого
	# файла означало бы исполнение чужого кода
	f.store_var(capture(main), false)
	f.close()
	return ""

## Прочитать слот. Пустой словарь — файла нет, он битый или чужой версии;
## причина уходит в err (второй возвращаемый смысл через ключ "__error")
static func load_state(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"__error": "Сохранение не найдено"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"__error": "Файл сохранения не читается"}
	if f.get_length() < 12 or f.get_32() != MAGIC:
		f.close()
		return {"__error": "Это не файл сохранения игры"}
	var fmt: int = f.get_32()
	var wgen: int = f.get_32()
	if fmt != FORMAT_VERSION:
		f.close()
		return {"__error": "Сохранение версии %d, игра читает %d" % [fmt, FORMAT_VERSION]}
	if wgen != WORLD_GEN_VERSION:
		f.close()
		return {"__error": "Карта этой версии генерируется иначе — сохранение несовместимо"}
	var data: Variant = f.get_var(false)
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return {"__error": "Файл сохранения повреждён"}
	return data as Dictionary

## Есть ли что грузить в слоте
static func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

## Короткая подпись слота для кнопки: когда сохранено и на какой сложности.
## Читает ВЕСЬ файл — и это осознанно: подпись нужна трём кнопкам раз в жизни
## меню, а отдельный «заголовочный» блок в файле означал бы второй формат,
## который рано или поздно разъедется с основным
static func slot_label(slot: int) -> String:
	if not has_save(slot):
		return "Слот %d — пусто" % slot
	var st := load_state(slot)
	if st.has("__error"):
		return "Слот %d — %s" % [slot, String(st["__error"])]
	var meta: Dictionary = st.get("meta", {})
	return "Слот %d — %s, %s" % [slot, String(meta.get("saved_at", "?")),
		_Diff.label(String(meta.get("difficulty", _Diff.DEFAULT)))]

# ═════════════════════════════════════════════════════════════════════════════
# ВОССТАНОВЛЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
## ЗАГРУЗКА ИДЁТ В ДВА ХОДА, И ИНАЧЕ НЕ ВЫЙДЕТ.
##
## Ход первый (здесь): слепок кладётся в GameManager.pending_load и сцена
## перезапускается. Ход второй: Main._ready() видит слепок, берёт из него ЗЕРНО
## и сеет им мир, а start_game() в самом конце зовёт apply().
##
## Почему нельзя одним ходом: карта строится в Main._ready(), то есть ДО того,
## как кто-либо успел бы что-то восстановить. Подсунуть зерно позже — значит
## получить чужой рельеф под сохранёнными постройками.
static func request_load(tree: SceneTree, slot: int) -> String:
	var st := load_state(slot)
	if st.has("__error"):
		return String(st["__error"])
	GameManager.pending_load = st
	# Сложность ставится ДО пересева: от неё зависят стартовые величины, а
	# главное — она обязана быть той же, на которой партию сохраняли
	var meta: Dictionary = st.get("meta", {})
	_Diff.set_current(String(meta.get("difficulty", _Diff.DEFAULT)))
	GameManager.player_faction_name = String(meta.get("player_faction", GameManager.player_faction_name))
	GameManager.ai_faction_name     = String(meta.get("ai_faction", GameManager.ai_faction_name))
	GameManager.player_color        = String(meta.get("player_color", GameManager.player_color))
	GameManager.ai_color            = String(meta.get("ai_color", GameManager.ai_color))
	tree.paused = false
	tree.change_scene_to_file("res://scenes/Main.tscn")
	return ""

## Применить слепок к УЖЕ СОЗДАННОЙ карте. Зовётся из Main.start_game() в самом
## конце: к этому моменту мир пересеян тем же зерном, а стартовые замки, рабочие
## и орда уже расставлены — их и надо снести, чтобы поставить сохранённые.
static func apply(main: Node, state: Dictionary) -> void:
	if main == null or state.is_empty():
		return
	_wipe_live_world(main)
	_restore_resources(state.get("resources", {}))
	_restore_research(state.get("research", {}))
	var sid_map: Dictionary = _restore_squads(state.get("squads", []))
	_restore_buildings(main, state.get("buildings", []))
	_restore_units(main, state.get("units", {}), sid_map)
	# Часы партии — последними: орда читает их каждый такт, и до расстановки
	# войск ей нечего было бы будить
	var meta: Dictionary = state.get("meta", {})
	if main.has_method("set_game_clock"):
		main.set_game_clock(float(meta.get("clock", 0.0)))

## СНЕСТИ ВСЁ ЖИВОЕ, ОСТАВИВ КАРТУ. Ресурсные жилы, деревья и рельеф не
## трогаются вовсе — они пересеяны зерном и уже правильные.
##
## Бойцы уходят через die(), а не queue_free: смерть — единственный путь, на
## котором боец снимает с себя строку в ядре армии, место в сетке соседей и
## место в отряде (то же правило, что у расформирования отряда, см.
## SelectionManager.disband_selected). Прямое удаление узла обошло бы всё это.
static func _wipe_live_world(main: Node) -> void:
	# Список снимается ДО первой смерти: гибель дёргает remove_from_squad и
	# правит те самые группы, по которым мы идём (та же грабля, что и у
	# расформирования отряда — см. SelectionManager.disband_selected)
	var doomed: Array = _live_units(main)
	for u in doomed:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			# СМЕРТЬ, А НЕ queue_free: только на этом пути боец снимает с себя
			# строку в ядре армии, место в сетке соседей и место в отряде
			(u as Unit).take_damage((u as Unit).max_health * 1000.0 + 1e6, null)
	for f in range(Constants.FACTION_COUNT):
		for b in main.get_tree().get_nodes_in_group(Constants.building_group(f)):
			if is_instance_valid(b):
				# Здание сносится тихо: _die() оставил бы руины и звук, а мы
				# не рушим базу, а подменяем её сохранённой
				(b as Node).get_parent().remove_child(b)
				(b as Node).queue_free()
	for s in main.get_tree().get_nodes_in_group("construction_sites"):
		if is_instance_valid(s):
			(s as Node).get_parent().remove_child(s)
			(s as Node).queue_free()
	GameManager.reset_squads()
	# Тела прошлой партии на новой карте — мусор: они лежали бы там, где никто
	# не погибал. Заодно снимается и всё, что к ним подшито (стрелы в телах)
	GameManager.corpses.clear()

## ЖИВЫЕ БОЙЦЫ ВСЕХ ФРАКЦИЙ, ОДНИМ СПИСКОМ.
## Идём по группам узлов, а не по внутреннему реестру ядра армии: реестр —
## приватная кухня тика, и снимать с него слепок означало бы завязать формат
## файла на порядок обхода
static func _live_units(main: Node) -> Array:
	var out: Array = []
	for f in range(Constants.FACTION_COUNT):
		for u in main.get_tree().get_nodes_in_group(Constants.unit_group(f)):
			if not is_instance_valid(u):
				continue
			var unit := u as Unit
			if unit == null or unit.is_dead():
				continue
			out.append(unit)
	return out

static func _restore_resources(src: Dictionary) -> void:
	for f in src:
		var row: Dictionary = src[f]
		for t in row:
			ResourceManager.set_amount(int(f), int(t), float(row[t]))


## Изученное возвращается ТЕМ ЖЕ путём, каким его выдаёт кузница
## (GameManager.grant_research): бонусы фракции пересчитываются из таблиц, а не
## читаются из файла. Иначе правка баланса в forge_config не доехала бы до
## загруженной партии, и две одинаковые партии отличались бы историей
static func _restore_research(src: Dictionary) -> void:
	for f in src:
		for id in (src[f] as Array):
			# finish_research применяет узел БЕЗ списания цены — ровно то, что
			# нужно: за него уже заплачено в сохранённой партии
			GameManager.finish_research(int(f), String(id))

## Отряды создаются ЗАНОВО, и их номера меняются: старый id 7 может быть занят.
## Поэтому возвращается карта «старый id → новый», по ней бойцы и разбираются
static func _restore_squads(src: Array) -> Dictionary:
	var map: Dictionary = {}
	for row in src:
		var d: Dictionary = row
		var sid: int = GameManager.new_squad(int(d["faction"]), String(d["type"]))
		var sq: Dictionary = GameManager.squads[sid]
		sq["kills"]   = int(d.get("kills", 0))
		sq["level"]   = int(d.get("level", 0))
		sq["pending"] = int(d.get("pending", 0))
		sq["chosen"]  = (d.get("chosen", []) as Array).duplicate()
		sq["bonuses"] = (d.get("bonuses", {}) as Dictionary).duplicate()
		var ab: Dictionary = {}
		for k in (d.get("abilities", []) as Array):
			ab[String(k)] = true
		sq["abilities"] = ab
		map[int(d["id"])] = sid
	return map

static func _restore_buildings(main: Node, src: Array) -> void:
	for row in src:
		var d: Dictionary = row
		var b: Building = _make_building(String(d["id"]))
		if b == null:
			continue
		b.faction = int(d["faction"])
		main.world_add(b)
		b.global_position = d["pos"] as Vector3
		# Запас жизни ставится ПОСЛЕ входа в дерево: _ready() здания сам берёт
		# максимум из конфига и затёр бы сохранённое число
		b.current_health = float(d.get("hp", b.max_health))

## Фабрика зданий по id. ЗДЕСЬ ЖЕ, А НЕ В ConstructionSite: та строит только то,
## что можно заказать рабочим, а сохранение обязано вернуть и хижину гоблинов,
## и городской центр — всё, что вообще стоит на карте
static func _make_building(id: String) -> Building:
	match id:
		"castle":     return Castle.new()
		"barracks":   return Barracks.new()
		"smithy":     return Smithy.new()
		"mine":       return Mine.new()
		"archery":    return load("res://scripts/Archery.gd").new()
		"tower":      return load("res://scripts/Tower.gd").new()
		"town_center": return load("res://scripts/TownCenter.gd").new()
		"goblin_hut": return load("res://scripts/goblin/GoblinHut.gd").new()
		"troll_lair": return load("res://scripts/goblin/TrollLair.gd").new()
	# Три дома — один скрипт, картинка по ключу (House.variant_id)
	if _UCfg.is_house(id):
		var h: Building = load("res://scripts/House.gd").new()
		h.variant_id = id
		return h
	return null

## Бойцы разбираются из колонок. Порядок восстановления внутри отряда тот же,
## в каком они лежали при снятии слепка, — а значит и знаменосец достанется
## тому же бойцу (его выбирает разметка, см. GameManager._assign_bearer)
static func _restore_units(main: Node, src: Dictionary, sid_map: Dictionary) -> void:
	var types: Array = src.get("types", []) as Array
	var col_type: PackedInt32Array = src.get("type", PackedInt32Array())
	var col_fac:  PackedInt32Array = src.get("faction", PackedInt32Array())
	var col_sid:  PackedInt32Array = src.get("squad", PackedInt32Array())
	var col_pos:  PackedFloat32Array = src.get("pos", PackedFloat32Array())
	var col_hp:   PackedFloat32Array = src.get("hp", PackedFloat32Array())
	var n: int = col_type.size()
	for i in range(n):
		var tname: String = String(types[col_type[i]]) if col_type[i] < types.size() else ""
		var scene: PackedScene = Building.PRELOAD_SCENES.get(tname)
		if scene == null:
			continue
		var u: Unit = scene.instantiate()
		u.faction = col_fac[i]
		main.world_add(u)
		u.global_position = Vector3(col_pos[i * 3], col_pos[i * 3 + 1], col_pos[i * 3 + 2])
		u.sync_row()
		var old_sid: int = col_sid[i]
		if sid_map.has(old_sid):
			var new_sid: int = int(sid_map[old_sid])
			GameManager.add_to_squad(new_sid, u)
			# Ветеранские прибавки выдаются ТЕМ ЖЕ путём, каким их получает
			# пополнение из замка: сохранённый список наград отряда уже лежит
			# в его записи, и второй реализации раздачи заводить нельзя
			GameManager.apply_squad_bonuses_to(new_sid, u)
		# Запас жизни — ПОСЛЕ наград: награда на здоровье поднимает и максимум,
		# и текущее, и порядок наоборот затёр бы сохранённые раны
		u.current_health = minf(float(col_hp[i]), u.max_health)
	for old_sid in sid_map:
		GameManager.refresh_squad_banner(int(sid_map[old_sid]))
