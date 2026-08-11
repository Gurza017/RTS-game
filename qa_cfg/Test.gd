extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: КОНФИГИ КАРТОЧЕК ЮНИТОВ И ДРЕВА КУЗНИЦЫ
## ═══════════════════════════════════════════════════════════════════════════
##   A. КАРТОЧКА  — состав окна берётся ИЗ КОНФИГА, а не из кода
##   B. ЖИВОЕ РЕДАКТИРОВАНИЕ — правка visible_stats меняет окно без правки кода
##   C. ДРЕВО     — у каждого узла все запрошенные поля, и они не выдуманы,
##                  а совпадают с рабочей таблицей (одна копия данных)
##
## Запуск: godot --headless --path . res://qa_cfg/Test.tscn

const _TipCfg := preload("res://scripts/tooltip_config.gd")
const _Forge  := preload("res://scripts/forge_config.gd")
const _UCfg   := preload("res://scripts/unit_stats_config.gd")

var main = null
var hud = null
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

## Строки карточки найма для юнита
func _card_lines(unit_id: String) -> Array:
	return hud._unit_card(unit_id, Constants.FACTION_PLAYER, {}, 0)["lines"]

func _has_line(lines: Array, needle: String) -> bool:
	for l in lines:
		if needle in String(l):
			return true
	return false

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	hud = main.hud
	await frames(3)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  КОНФИГИ: КАРТОЧКИ ЮНИТОВ И ДРЕВО КУЗНИЦЫ                        ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	# ── A. КАРТОЧКА СОБИРАЕТСЯ ПО КОНФИГУ ───────────────────────────────────
	var need := ["unit_id", "display_name", "icon", "description", "visible_stats"]
	var miss: Array = []
	for uid in ["spearman", "warrior", "archer", "monk", "worker"]:
		var t: Dictionary = _TipCfg.tooltip(String(uid))
		for k in need:
			if not t.has(k):
				miss.append("%s.%s" % [uid, k])
	verdict("A1 у каждой карточки есть все поля структуры", miss.is_empty(),
		"не хватает: %s" % str(miss))

	# Имя и описание в окне — ИЗ КОНФИГА, а не из кода
	var sp: Dictionary = _TipCfg.tooltip("spearman")
	var card: Dictionary = hud._unit_card("spearman", Constants.FACTION_PLAYER, {}, 0)
	verdict("A2 название окна берётся из конфига",
		String(card["title"]) == String(sp["display_name"]),
		"окно «%s», конфиг «%s»" % [String(card["title"]), String(sp["display_name"])])
	verdict("A3 описание из конфига попало в окно",
		_has_line(card["lines"], String(sp["description"]).substr(0, 20)),
		"описание: «%s…»" % String(sp["description"]).substr(0, 30))

	# ГЛАВНОЕ ПРАВИЛО: нет параметра в конфиге — нет строки в окне
	var w_stats: Array = _TipCfg.tooltip("worker")["visible_stats"]
	var w_keys: Array = []
	for r in w_stats:
		w_keys.append(String((r as Dictionary).get("key", "")))
	var w_lines: Array = _card_lines("worker")
	verdict("A4 у Рабочего в конфиге нет брони — и строки нет",
		not ("armor" in w_keys) and not _has_line(w_lines, "Броня"),
		"ключи рабочего: %s" % str(w_keys))
	verdict("A5 у Копейщика броня есть — и строка есть",
		_has_line(_card_lines("spearman"), "Броня"))

	# ── B. ПРАВКА КОНФИГА ПЕРЕСТРАИВАЕТ ОКНО ────────────────────────────────
	# Ровно то, ради чего конфиг и заводился: меняем СПИСОК параметров и
	# смотрим, что окно перестроилось само, без единой правки кода
	var before: Array = _card_lines("monk")
	var had_range: bool = _has_line(before, "Дальность")
	# Убираем «Дальность» у Монаха прямо в рантайме
	var monk_cfg: Dictionary = _TipCfg.TOOLTIPS["monk"]
	var orig: Array = (monk_cfg["visible_stats"] as Array).duplicate(true)
	var trimmed: Array = []
	for r in orig:
		if String((r as Dictionary).get("key", "")) != "range":
			trimmed.append(r)
	monk_cfg["visible_stats"] = trimmed
	var after: Array = _card_lines("monk")
	verdict("B1 убрали параметр из конфига — строка пропала из окна",
		had_range and not _has_line(after, "Дальность"),
		"было %d строк, стало %d" % [before.size(), after.size()])

	# Добавляем параметр, которого у Монаха не было
	trimmed.append({"key": "morale"})
	monk_cfg["visible_stats"] = trimmed
	var after2: Array = _card_lines("monk")
	verdict("B2 добавили параметр в конфиг — строка появилась в окне",
		_has_line(after2, "Мораль"), "строк стало %d" % after2.size())

	# Подпись можно переопределить прямо в карточке, не трогая библиотеку
	trimmed.append({"key": "cooldown", "fmt": "СВОЙ ФОРМАТ: %.2f"})
	monk_cfg["visible_stats"] = trimmed
	verdict("B3 формат строки переопределяется в самой карточке",
		_has_line(_card_lines("monk"), "СВОЙ ФОРМАТ"))
	monk_cfg["visible_stats"] = orig      # вернуть конфиг как был

	# Опечатка в ключе не роняет окно, а просто не рисует строку
	var bogus: Array = orig.duplicate(true)
	bogus.append({"key": "такого_параметра_нет"})
	monk_cfg["visible_stats"] = bogus
	var safe: Array = _card_lines("monk")
	verdict("B4 неизвестный ключ не роняет окно", safe.size() == before.size(),
		"строк %d (было %d)" % [safe.size(), before.size()])
	monk_cfg["visible_stats"] = orig

	# ── C. ДРЕВО КУЗНИЦЫ ────────────────────────────────────────────────────
	var need_n := ["id", "title", "description", "icon", "cost",
		"research_time", "prerequisites", "stat_bonus"]
	var miss_n: Array = []
	var checked := 0
	for u in _Forge.UNIT_TABS:
		for v in _Forge.tree_view(String(u)):
			var d: Dictionary = v
			checked += 1
			for k in need_n:
				if not d.has(k):
					miss_n.append("%s.%s" % [String(d.get("id", "?")), k])
	verdict("C1 у каждого узла древа есть все запрошенные поля",
		miss_n.is_empty() and checked == 80,
		"проверено узлов %d, не хватает: %s" % [checked, str(miss_n.slice(0, 5))])

	# Данные во «вью» — те же самые, что в рабочей таблице (одна копия)
	var v1: Dictionary = _Forge.node_view("warrior_1a")
	var raw: Dictionary = _Forge.get_node("warrior_1a")
	verdict("C2 вью не выдумывает данные, а разворачивает рабочую таблицу",
		String(v1["title"]) == String(raw.get("name", ""))
			and float(v1["cost"].get("gold", -1.0)) == float(raw.get("cost_gold", -2.0))
			and float(v1["stat_bonus"].get("armor", -1.0)) == float(raw.get("bonus_armor", -2.0)),
		"title «%s», gold %s, armor %s" % [String(v1["title"]),
			str(v1["cost"].get("gold", "нет")), str(v1["stat_bonus"].get("armor", "нет"))])

	# Нулевые позиции во вью не попадают: пустых «0 золота» в карточке не будет
	var zero_ok := true
	for c in v1["cost"].values():
		if float(c) <= 0.0:
			zero_ok = false
	for b in v1["stat_bonus"].values():
		if float(b) == 0.0:
			zero_ok = false
	verdict("C3 нулевые цены и бонусы во вью не попадают", zero_ok,
		"цена %s, бонусы %s" % [str(v1["cost"]), str(v1["stat_bonus"])])

	# Связи развёрнуты в ПОЛНЫЕ id — по ним GameManager и проверяет доступность
	var v2: Dictionary = _Forge.node_view("warrior_2a")
	var links_full := true
	for l in v2["links"]:
		if not String(l).begins_with("warrior_"):
			links_full = false
	verdict("C4 зависимости и связи развёрнуты в полные id",
		links_full and not (v2["prerequisites"] as Array).is_empty(),
		"prereq %s, links %s" % [str(v2["prerequisites"]), str(v2["links"])])

	# Иконка — готовый путь, а не голое имя файла
	verdict("C5 иконка узла — полный путь res://",
		String(v1["icon"]).begins_with("res://"), String(v1["icon"]))

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %s%s" % [_pad(String(row[0]), 54),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== CONFIG TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)
