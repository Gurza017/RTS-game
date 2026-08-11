extends Node

## СТЕНД: ИКОНКИ КУЗНИЦЫ (пути, загрузка, защита от опечаток)
##
## Разделы:
##   A — базовый путь: папка существует и читается через res://
##   B — хелпер: имя файла разворачивается в путь, полный путь проходит как есть
##   C — конфиг: все имена иконок в таблицах реально загружаются
##   D — защита: опечатка и отсутствующий файл не роняют интерфейс
##   E — кузница в игре: кнопки улучшений получают текстуры

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main: Node = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	_test_dir()
	_test_helper()
	_test_config_icons()
	_test_fallback()
	await _test_smithy_ui()

	print("\n=== ИТОГ qa_icons: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. БАЗОВЫЙ ПУТЬ
# ═════════════════════════════════════════════════════════════════════════════
func _test_dir() -> void:
	print("\n═════ A. БАЗОВЫЙ ПУТЬ ═════")
	var dir: String = _UCfg.SMITH_ICONS_DIR
	print("  SMITH_ICONS_DIR = %s" % dir)
	verdict("A1 путь объявлен через res://", dir.begins_with("res://"), dir)
	verdict("A2 путь заканчивается разделителем (склейка не слипнется)",
		dir.ends_with("/"), dir)
	var d := DirAccess.open(dir)
	verdict("A3 папка открывается", d != null, "DirAccess.open вернул null")
	if d == null:
		return
	var pngs := 0
	for f in d.get_files():
		if String(f).to_lower().ends_with(".png"):
			pngs += 1
	print("  картинок в папке: %d" % pngs)
	verdict("A4 в папке есть иконки", pngs > 0, "нашли %d" % pngs)

# ═════════════════════════════════════════════════════════════════════════════
# B. ХЕЛПЕР
# ═════════════════════════════════════════════════════════════════════════════
func _test_helper() -> void:
	print("\n═════ B. ХЕЛПЕР ПОДСТАНОВКИ ПУТИ ═════")
	var p1: String = _UCfg.smith_icon_path("icon_sword.png")
	verdict("B1 имя файла разворачивается в полный путь",
		p1 == _UCfg.SMITH_ICONS_DIR + "icon_sword.png", p1)
	var p2: String = _UCfg.smith_icon_path("icon_sword")
	verdict("B2 расширение .png подставляется само",
		p2 == _UCfg.SMITH_ICONS_DIR + "icon_sword.png", p2)
	var full := "res://assets/factions/humans/icons/buildings/Castle.png"
	verdict("B3 готовый res://-путь проходит как есть",
		_UCfg.smith_icon_path(full) == full, _UCfg.smith_icon_path(full))
	verdict("B4 пустая строка остаётся пустой",
		_UCfg.smith_icon_path("") == "")
	var tex: Texture2D = _UCfg.smith_icon("icon_sword.png")
	verdict("B5 иконка реально грузится в текстуру", tex != null,
		"путь %s" % p1)
	if tex != null:
		print("  icon_sword.png: %dx%d" % [int(tex.get_size().x), int(tex.get_size().y)])

# ═════════════════════════════════════════════════════════════════════════════
# C. ИМЕНА ИЗ КОНФИГА
# ═════════════════════════════════════════════════════════════════════════════
func _test_config_icons() -> void:
	print("\n═════ C. ИКОНКИ, ЗАПИСАННЫЕ В КОНФИГЕ ═════")
	var bad: Array = []
	var checked := 0

	# 1) улучшения кузницы
	for slot in _UCfg.UPGRADE_SLOTS:
		var s: Dictionary = slot
		var name: String = String(s.get("icon", ""))
		if name.is_empty():
			continue
		checked += 1
		if not ResourceLoader.exists(_UCfg.smith_icon_path(name)):
			bad.append("улучшение «%s» → %s" % [String(s.get("id", "?")), name])
	# 2) бонусы ветеранства — теперь отдельно по 4 боевым типам (VET_CONFIG)
	for utype in _UCfg.VET_CONFIG:
		for level in (_UCfg.VET_CONFIG[utype]["bonuses"] as Array):
			for ch in (level as Array):
				var c: Dictionary = ch
				var n2: String = String(c.get("icon", ""))
				if n2.is_empty():
					continue
				checked += 1
				if not ResourceLoader.exists(_UCfg.smith_icon_path(n2)):
					bad.append("ветеранство[%s] «%s» → %s" % [String(utype), String(c.get("id", "?")), n2])

	print("  проверено записей: %d, битых: %d" % [checked, bad.size()])
	for b in bad:
		print("    БИТАЯ ССЫЛКА: %s" % String(b))
	verdict("C1 иконки в конфиге вообще заданы", checked > 0,
		"записей с иконкой: %d" % checked)
	verdict("C2 все указанные иконки загружаются", bad.is_empty(),
		"битых ссылок: %d" % bad.size())

	# Ни одна запись не должна тащить полный путь: он и ломается при переезде
	var hardcoded: Array = []
	for slot2 in _UCfg.UPGRADE_SLOTS:
		var n3: String = String((slot2 as Dictionary).get("icon", ""))
		if n3.begins_with("res://") and n3.contains("icons_for_smith"):
			hardcoded.append(n3)
	verdict("C3 в конфиге кузницы записаны ИМЕНА, а не полные пути",
		hardcoded.is_empty(), "полных путей: %d" % hardcoded.size())

# ═════════════════════════════════════════════════════════════════════════════
# D. ЗАЩИТА ОТ ОПЕЧАТОК
# ═════════════════════════════════════════════════════════════════════════════
func _test_fallback() -> void:
	print("\n═════ D. ОПЕЧАТКИ И ПРОПУЩЕННЫЕ ФАЙЛЫ ═════")
	# Само по себе то, что мы досюда дошли без краша, и есть проверка:
	# smith_icon на несуществующем имени обязан вернуть null, а не упасть
	var missing: Texture2D = _UCfg.smith_icon("icon_definitely_not_here.png")
	verdict("D1 отсутствующая иконка возвращает null, а не роняет игру",
		missing == null)
	var typo: Texture2D = _UCfg.smith_icon("iocn_sword.png")
	verdict("D2 опечатка в имени тоже безопасна", typo == null)
	var empty: Texture2D = _UCfg.smith_icon("")
	verdict("D3 пустое имя безопасно", empty == null)
	# И HUD на этом не спотыкается
	var hud = main.hud
	verdict("D4 у HUD есть единая точка загрузки иконок",
		hud != null and hud.has_method("_icon_texture"))
	if hud != null:
		verdict("D5 HUD на битом имени возвращает null, а не падает",
			hud._icon_texture("icon_definitely_not_here.png") == null)
		verdict("D6 HUD разворачивает короткое имя из папки кузницы",
			hud._icon_texture("icon_sword.png") != null)

# ═════════════════════════════════════════════════════════════════════════════
# E. КУЗНИЦА В ИГРЕ
# ═════════════════════════════════════════════════════════════════════════════
func _test_smithy_ui() -> void:
	print("\n═════ E. ПАНЕЛЬ КУЗНИЦЫ ═════")
	var sm := Smithy.new()
	sm.faction = Constants.FACTION_PLAYER
	main.world_add(sm)
	sm.global_position = Vector3(-400, 0, -400)
	await frames(3)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 100000.0)
	var hud = main.hud
	hud.show_selection([sm])
	await frames(3)

	# КНОПКИ КУЗНИЦЫ ЖИВУТ В ЕЁ СОБСТВЕННОЙ ПАНЕЛИ (древо технологий,
	# 2026-08-07), а не в общей нижней: button_container для кузницы теперь
	# пуст по построению. Требование к иконкам осталось прежним — сменилось
	# место, где их искать
	var btns: Array = []
	for c in hud._forge_grid.get_children():
		if c is Button:
			btns.append(c)
	print("  кнопок на панели кузницы: %d" % btns.size())
	verdict("E1 панель кузницы собралась", btns.size() > 0,
		"кнопок %d" % btns.size())
	var with_icon := 0
	for b in btns:
		for c in (b as Button).get_children():
			if c is TextureRect and (c as TextureRect).texture != null:
				with_icon += 1
				break
	print("  из них с картинкой: %d" % with_icon)
	verdict("E2 кнопки улучшений получили текстуры из папки кузницы",
		with_icon > 0, "с иконками %d из %d" % [with_icon, btns.size()])
	sm.queue_free()
	await frames(2)
