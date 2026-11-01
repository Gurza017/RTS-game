extends RefCounted
## ДРЕВО КУЗНИЦЫ ГОБЛИНОВ (ТЗ 28.10.2026): BRANCHES[ветка] × ROWS — узел = слот улучшения.
## Подключение: const _GF := preload("res://scripts/economy/goblin_forge/goblin_forge_config.gd")
## Узел отдаётся тем же словарём, что узел forge_config (id, name, desc, icon, applies_to,
## prerequisites, link_ids, row_gate, cost_*, research_time, bonus_*), поэтому контур
## GameManager.start_research / finish_research / unit_bonus работает без второй копии.
## Заметки и обоснования чисел — docs/config_notes/goblin_forge_config.md.

## Префикс id узла: «gforge_<ветка>_<ряд>»
const ID_PREFIX := "gforge_"
## Рядов (ступеней) в каждой ветке
const ROWS := 3
## Порядок веток — он же порядок колонок в окне
const BRANCH_ORDER := ["hide", "pikes", "howl", "poison", "doping"]
## Каталог иконок (PNG из tools/make_goblin_forge_icons.py)
const ICON_DIR := "res://assets/ui/goblin_forge/"

## Пехота и всадники орды (без диких: тролль, гноллы — не орда)
const HORDE_UNITS := ["goblin_spearman", "goblin_rider", "big_goblin"]

## ── ЦЕНА ──
## Базовая цена ряда: дерево и золото; еда — доля FOOD_SHARE от их суммы
const ROW_COST := {
	1: {"cost_wood": 220.0, "cost_gold": 90.0},
	2: {"cost_wood": 380.0, "cost_gold": 160.0},
	3: {"cost_wood": 600.0, "cost_gold": 260.0},
}
## Время исследования ряда, с
const ROW_TIME := {1: 25.0, 2: 40.0, 3: 60.0}
## Множитель ко всем ценам узла (дерево, золото, еда)
const PRICE_MULT := 1.0
## Доля еды в цене узла от суммы дерева и золота
const FOOD_SHARE := 0.35

## ── ВЕТКИ ──
## name/desc — подпись; icon — файл в ICON_DIR; applies_to — роды; rows — прибавки по рядам
## (ключи bonus_* из unit_stats_config.BONUS_KEYS); stub — заготовка: узел есть, применять некому
const BRANCHES := {
	"hide": {
		"name": "Чёрствая шкура", "icon": "hide.png",
		"desc": "Броня пехоте и свиновсадникам",
		"applies_to": ["goblin_spearman", "goblin_rider"],
		"rows": [
			{"bonus_armor": 1.0},
			{"bonus_armor": 1.5},
			{"bonus_armor": 2.0},
		],
	},
	"pikes": {
		"name": "Зазубренные пики", "icon": "pikes.png",
		"desc": "Урон пехоты и бонус против конницы (цель с разгоном — Unit.giant_class)",
		"applies_to": ["goblin_spearman", "big_goblin"],
		"rows": [
			{"bonus_attack": 1.5, "bonus_giant_melee": 0.15},
			{"bonus_attack": 2.0, "bonus_giant_melee": 0.15},
			{"bonus_attack": 2.5, "bonus_giant_melee": 0.20},
		],
	},
	"howl": {
		"name": "Ночной вой", "icon": "howl.png",
		"desc": "Скорость хода и темп атаки всем гоблинам",
		"applies_to": HORDE_UNITS,
		"rows": [
			{"bonus_speed": 0.12, "bonus_cooldown_pct": 0.05},
			{"bonus_speed": 0.16, "bonus_cooldown_pct": 0.06},
			{"bonus_speed": 0.20, "bonus_cooldown_pct": 0.07},
		],
	},
	# ЗАГОТОВКА: стрелков у орды нет (goblin_archer в STATS/ассетах отсутствует);
	# узел исследуется, бонус ляжет на «goblin_archer», когда тот появится
	"poison": {
		"name": "Ядовитые наконечники", "icon": "poison.png",
		"desc": "Яд на стрелах: урон со временем (заготовка — стрелков у орды пока нет)",
		"applies_to": ["goblin_archer"],
		"stub": true,
		"rows": [
			{"bonus_poison_dps": 2.0, "bonus_poison_sec": 4.0},
			{"bonus_poison_dps": 3.0, "bonus_poison_sec": 4.0},
			{"bonus_poison_dps": 4.0, "bonus_poison_sec": 5.0},
		],
	},
	"doping": {
		"name": "Орочий допинг", "icon": "doping.png",
		"desc": "Запас жизни и мораль всем гоблинам",
		"applies_to": HORDE_UNITS,
		"rows": [
			{"bonus_health": 15.0, "bonus_morale": 8.0},
			{"bonus_health": 20.0, "bonus_morale": 10.0},
			{"bonus_health": 25.0, "bonus_morale": 12.0},
		],
	},
}

## ── ЭКОНОМИКА ОРДЫ ПОД КУЗНИЦУ (GoblinForgeAI) ──
## Дерево и золото в минуту при полном лагере (доля живых хижин + хата); потолки копилок
const HORDE_WOOD_PER_MIN := 40.0
const HORDE_GOLD_PER_MIN := 16.0
const HORDE_WOOD_BANK_MAX := 3000.0
const HORDE_GOLD_BANK_MAX := 1500.0
## Закладка: не раньше этой секунды партии; еды в копилке после оплаты — не меньше
const FORGE_LAY_AFTER_SEC := 240.0
const FORGE_LAY_FOOD_RESERVE := 300.0
## Исследование: еды после оплаты — не меньше; между заказами — не чаще, с
const FORGE_RESEARCH_FOOD_RESERVE := 350.0
const FORGE_RESEARCH_GAP_SEC := 20.0
## Что вожак ценит в узле (сумма bonus × вес, делится на цену дерева+золота); заготовки — пропуск
const FORGE_AI_WEIGHTS := {
	"bonus_armor": 2.5, "bonus_attack": 3.0, "bonus_giant_melee": 10.0,
	"bonus_speed": 6.0, "bonus_cooldown_pct": 30.0,
	"bonus_health": 0.8, "bonus_morale": 0.4,
}
## Место кузницы: смещение от центра лагеря (x, z), м, и запасные смещения, если занято
const CAMP_OFFSET := Vector2(26.0, 2.0)
const CAMP_OFFSET_ALT := [Vector2(-26.0, 2.0), Vector2(26.0, 12.0), Vector2(-26.0, 12.0)]
## Радиус, в котором место считается занятым другой постройкой, м
const SPOT_BUSY_R := 7.0

## ── СБОРКА ──
static var _node_cache: Dictionary = {}
static var _tree_cache: Array = []

static func node_id(branch: String, row: int) -> String:
	return "%s%s_%d" % [ID_PREFIX, branch, row]

static func is_forge_id(id: String) -> bool:
	return id.begins_with(ID_PREFIX)

static func icon_path(file: String) -> String:
	return ICON_DIR + file

static func _build() -> void:
	if not _tree_cache.is_empty():
		return
	for b in BRANCH_ORDER:
		var branch: String = String(b)
		var src: Dictionary = BRANCHES[branch]
		var rows: Array = src.get("rows", [])
		for i in range(mini(ROWS, rows.size())):
			var row: int = i + 1
			var node: Dictionary = {}
			node["id"] = node_id(branch, row)
			node["branch"] = branch
			node["row"] = row
			node["cell"] = "%d%s" % [row, branch]
			node["unit"] = branch
			node["name"] = "%s %s" % [String(src["name"]), _roman(row)]
			node["desc"] = String(src.get("desc", ""))
			node["icon"] = icon_path(String(src.get("icon", "")))
			node["applies_to"] = (src.get("applies_to", []) as Array).duplicate()
			node["stub"] = bool(src.get("stub", false))
			var cost: Dictionary = ROW_COST.get(row, {})
			var w: float = float(cost.get("cost_wood", 0.0)) * PRICE_MULT
			var g: float = float(cost.get("cost_gold", 0.0)) * PRICE_MULT
			node["cost_wood"] = round(w)
			node["cost_gold"] = round(g)
			node["cost_stone"] = 0.0
			node["cost_food"] = round((w + g) * FOOD_SHARE)
			node["research_time"] = float(ROW_TIME.get(row, 30.0))
			var reqs: Array = []
			if row > 1:
				reqs.append(node_id(branch, row - 1))
			node["prerequisites"] = reqs
			node["link_ids"] = []
			node["row_gate"] = []
			for k in (rows[i] as Dictionary):
				node[String(k)] = float((rows[i] as Dictionary)[k])
			_node_cache[String(node["id"])] = node
			_tree_cache.append(node)

static func get_node(id: String) -> Dictionary:
	if not is_forge_id(id):
		return {}
	_build()
	var v: Variant = _node_cache.get(id)
	return v if v != null else {}

## Все узлы в порядке веток и рядов
static func all_nodes() -> Array:
	_build()
	return _tree_cache.duplicate()

## Узлы одной ветки по рядам
static func branch_nodes(branch: String) -> Array:
	var out: Array = []
	for n in all_nodes():
		if String((n as Dictionary).get("branch", "")) == branch:
			out.append(n)
	return out

static func branch_title(branch: String) -> String:
	return String((BRANCHES.get(branch, {}) as Dictionary).get("name", branch))

static func _roman(n: int) -> String:
	match n:
		1: return "I"
		2: return "II"
		3: return "III"
	return str(n)

## Текст цены для окна и стендов
static func cost_text(node: Dictionary) -> String:
	var parts: Array = []
	var w: float = float(node.get("cost_wood", 0.0))
	var g: float = float(node.get("cost_gold", 0.0))
	var f: float = float(node.get("cost_food", 0.0))
	if w > 0.0: parts.append("%d л" % int(w))
	if g > 0.0: parts.append("%d з" % int(g))
	if f > 0.0: parts.append("%d е" % int(f))
	return " + ".join(parts) if not parts.is_empty() else "бесплатно"
