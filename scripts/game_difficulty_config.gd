extends RefCounted
## СЛОЖНОСТЬ: множители поверх базовых таблиц (Normal = 1.0 везде).
## Только параметры; снятые пояснения — docs/CONFIG_NOTES_2026-09-14.md

const _AICfg  := preload("res://scripts/ai_start_army_limit.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _UCfg   := preload("res://scripts/unit_stats_config.gd")

const EASY   := "easy"
const NORMAL := "normal"
const HARD   := "hard"

## Порядок в меню — он же порядок кнопок
const ORDER := [EASY, NORMAL, HARD]

## С чего начинается новая установка игры
const DEFAULT := NORMAL

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
##   ── КРАСНЫЙ ИИ (Constants.FACTION_ENEMY) ──────────────────────────────
##   ── ОРДА ГОБЛИНОВ (Constants.FACTION_GOBLIN) ──────────────────────────
## ПРЕСЕТЫ
const PRESETS := {
	EASY: {
		"name": "Лёгкая",
		"hint": "Противник копит вдвое меньшую армию и позже идёт в бой",
		# ── красный ИИ ──────────────────────────────────────────────────────
		"ai_squad_mult":    0.55,   # армия ИИ примерно вдвое меньше обычной
		"ai_worker_mult":   0.70,   # экономика слабее — лимит набирается дольше
		"ai_resource_mult": 0.75,   # стартовый запас урезан на четверть
		"ai_train_mult":    1.30,   # найм отряда на 30% дольше
		"ai_build_mult":    1.30,   # стройка на 30% дольше
		"ai_peace_mult":    1.50,   # мирная фаза в полтора раза длиннее
		"ai_start_squads":  [],     # стартовых войск нет (как и в базе)
		# ── орда ────────────────────────────────────────────────────────────
		"goblin_dormant_mult": 1.35,  # орда просыпается позже
		"goblin_food_mult":    0.70,  # и медленнее восполняет потери
		"goblin_vet_shift":   -1,     # ранг стартовых отрядов на ступень ниже
	},
	NORMAL: {
		"name": "Обычная",
		"hint": "Баланс из таблиц: плотный бой к середине партии",
		"ai_squad_mult":    1.0,
		"ai_worker_mult":   1.0,
		"ai_resource_mult": 1.0,
		"ai_train_mult":    1.0,
		"ai_build_mult":    1.0,
		"ai_peace_mult":    1.0,
		"ai_start_squads":  [],
		"goblin_dormant_mult": 1.0,
		"goblin_food_mult":    1.0,
		"goblin_vet_shift":    0,
	},
	HARD: {
		"name": "Тяжёлая",
		"hint": "Противник выходит с гарнизоном, копит больше и давит раньше",
		# ── красный ИИ ──────────────────────────────────────────────────────
		"ai_squad_mult":    1.40,   # армия в полтора раза больше обычной
		"ai_worker_mult":   1.35,   # и набирается она быстрее
		"ai_resource_mult": 1.60,   # фора по стартовому запасу
		"ai_train_mult":    0.80,   # найм на 20% быстрее
		"ai_build_mult":    0.80,   # стройка на 20% быстрее
		"ai_peace_mult":    0.60,   # мирная фаза короче почти вдвое
		# СТАРТОВЫЙ ГАРНИЗОН. Ровно то, ради чего в ai_start_army_limit заведена
		"ai_start_squads": [
			{"unit": "spearman", "count": 0, "vet": 2, "picks": 2},
			{"unit": "spearman", "count": 0, "vet": 1, "picks": 1},
			{"unit": "archer",   "count": 0, "vet": 1, "picks": 1},
		],
		# ── орда ────────────────────────────────────────────────────────────
		"goblin_dormant_mult": 0.65,  # орда просыпается заметно раньше
		"goblin_food_mult":    1.40,  # и быстрее восполняет потери
		"goblin_vet_shift":    1,     # ранг стартовых отрядов на ступень выше
	},
}

# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# ТЕКУЩИЙ ВЫБОР
static var _current: String = DEFAULT

const SETTINGS_PATH := "user://difficulty.cfg"

static func current() -> String:
	return _current if PRESETS.has(_current) else DEFAULT

static func set_current(id: String) -> void:
	_current = id if PRESETS.has(id) else DEFAULT

## Запись текущего пресета целиком (нужна меню для подписи и подсказки)
static func preset() -> Dictionary:
	return PRESETS.get(current(), PRESETS[DEFAULT]) as Dictionary

## Подпись уровня сложности для интерфейса
static func label(id: String = "") -> String:
	var key: String = id if PRESETS.has(id) else current()
	return String((PRESETS[key] as Dictionary).get("name", key))

## Строка-подсказка под кнопкой выбора
static func hint(id: String = "") -> String:
	var key: String = id if PRESETS.has(id) else current()
	return String((PRESETS[key] as Dictionary).get("hint", ""))

## Одно поле текущего пресета с нейтральным значением по умолчанию
static func _f(key: String, neutral: float = 1.0) -> float:
	return float(preset().get(key, neutral))

# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════

## Лимит отрядов данного рода войск с учётом сложности.
static func ai_squad_limit(unit_id: String) -> int:
	var base: int = _AICfg.squad_limit(unit_id)
	if base <= 0:
		return 0      # род войск выключен в базе — сложность его не включает
	return maxi(int(ceil(float(base) * _f("ai_squad_mult"))), 1)

## Полный лимит армии ИИ В ОТРЯДАХ (по нему он решает, что пора в атаку)
static func ai_total_squad_limit() -> int:
	var total := 0
	for uid in _AICfg.combat_types():
		total += ai_squad_limit(String(uid))
	return total

static func ai_total_army_cap() -> int:
	var cap := 0
	for uid in _AICfg.combat_types():
		cap += ai_squad_limit(String(uid)) * _UCfg.squad_size(String(uid))
	return cap

## Потолок рабочих ИИ
static func ai_worker_limit() -> int:
	return maxi(int(round(float(_AICfg.WORKER_LIMIT) * _f("ai_worker_mult"))), 1)

## Длительность мирной фазы ИИ, секунд
static func ai_peace_seconds() -> float:
	return maxf(_AICfg.PEACE_SECONDS * _f("ai_peace_mult"), 0.0)

## Стартовый запас ресурсов фракции с учётом сложности.
static func starting_resources(faction: int, base: Dictionary) -> Dictionary:
	if faction != Constants.FACTION_ENEMY:
		return base
	var m: float = _f("ai_resource_mult")
	if is_equal_approx(m, 1.0):
		return base
	var out: Dictionary = {}
	for k in base:
		out[k] = float(base[k]) * m
	return out

## Время найма ОДНОГО отряда с учётом сложности, секунд.
static func train_time(faction: int, base: float) -> float:
	if faction != Constants.FACTION_ENEMY:
		return base
	return maxf(base * _f("ai_train_mult"), 0.5)

## Время отстройки здания с учётом сложности, секунд
static func build_time(faction: int, base: float) -> float:
	if faction != Constants.FACTION_ENEMY:
		return base
	return maxf(base * _f("ai_build_mult"), 0.5)

## Стартовые отряды ИИ: список пресета, если он непуст, иначе базовая таблица.
static func ai_start_squads() -> Array:
	var over: Array = preset().get("ai_start_squads", []) as Array
	if over.is_empty():
		return _AICfg.start_squads()
	var out: Array = []
	for row in over:
		var d: Dictionary = row
		var uid: String = String(d.get("unit", ""))
		if uid.is_empty() or not _UCfg.STATS.has(uid):
			continue
		var n: int = int(d.get("count", 0))
		if n <= 0:
			n = _UCfg.squad_size(uid)
		out.append({
			"unit":  uid,
			"count": maxi(n, 1),
			"vet":   maxi(int(d.get("vet", 0)), 0),
			"picks": maxi(int(d.get("picks", 0)), 0),
		})
	return out

## Срок спячки орды, секунд от начала партии (спринт 17: спячки нет, 0)
static func goblin_dormant_sec() -> float:
	return maxf(_GobCfg.DORMANT_UNTIL_SEC * _f("goblin_dormant_mult"), 0.0)

## Мирная фаза орды (отстройка и патруль границ), секунд от начала партии:
static func goblin_peace_sec() -> float:
	return maxf(_GobCfg.PEACE_SEC * _f("goblin_dormant_mult"), 0.0)

## Доход одной хижины, еды в минуту
static func goblin_hut_food_per_min() -> float:
	return maxf(_GobCfg.HUT_FOOD_PER_MIN * _f("goblin_food_mult"), 0.0)

## Стартовая орда со сдвинутым рангом. Отряды-новобранцы (vet = 0) не трогаются:
static func goblin_start_squads() -> Array:
	var shift: int = int(preset().get("goblin_vet_shift", 0))
	var base: Array = _GobCfg.start_squads()
	if shift == 0:
		return base
	var out: Array = []
	for row in base:
		var d: Dictionary = (row as Dictionary).duplicate()
		var v: int = int(d["vet"])
		if v > 0:
			d["vet"] = clampi(v + shift, 1, 7)
			# Наград не может быть больше, чем ступеней ранга
			d["picks"] = mini(int(d["picks"]), int(d["vet"]))
		out.append(d)
	return out

# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# НАСТРОЙКА НА ДИСКЕ
static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		set_current(DEFAULT)
		return
	set_current(String(cfg.get_value("game", "difficulty", DEFAULT)))

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "difficulty", current())
	cfg.save(SETTINGS_PATH)
