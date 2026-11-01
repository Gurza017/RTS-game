extends RefCounted
## КАРТОЧКИ ЮНИТОВ (hover/tooltip): состав и порядок строк задаются здесь, а не в HUD.
## Подключение: const _TipCfg := preload("res://scripts/tooltip_config.gd") (без class_name намеренно).
## Заметки — docs/config_notes/tooltip_config.md
##
## Правило: нет параметра в visible_stats — нет строки в окне (HUD._unit_card идёт по списку).
## Блоки карточки (HUD._show_card): icon + display_name → visible_stats → role / skills / special
## (description — запасной текст) → show_cost (цену даёт вызывающий).

const _UCfg := preload("res://scripts/unit_stats_config.gd")

# ── ФОРМАТ СТРОКИ ──
# value_type: "stat" — «База + Кузница + Опыт = Итог» (только то, на что действуют бонусы);
#   "current_max" — «80/100» (у карточки найма — один максимум); "plain" — одно число по fmt;
#   "pair" — два числа конфига по fmt.
# Источник из unit_stats_config.STATS: "stat" — ключ, "sum_of" — сумма ключей,
#   "max_of" — максимум из ключей, "stats" — ключи для "pair".
# "bonus" / "upgrade" — ключи прибавок кузницы и плоских апгрейдов; "digits" — знаков после запятой.

## Библиотека строк: как каждая считается и подписана; карточки ниже только собирают из неё
static var PARAMS: Dictionary = {
	"attack": {
		"value_type": "stat", "label": "Атака", "icon": "icon_sword.png",
		"max_of": ["attack_1", "attack_2"],
		"bonus": "bonus_attack", "upgrade": "damage", "digits": 0,
	},
	"armor": {
		"value_type": "stat", "label": "Броня", "icon": "icon_shield.png",
		"sum_of": ["defense", "armor"],
		"bonus": "bonus_armor", "upgrade": "defense", "digits": 0,
	},
	"move_speed": {
		"value_type": "stat", "label": "Скорость", "icon": "icon_luck_horseshoe.png",
		"max_of": ["movement_speed", "walk_speed_empty"],
		"bonus": "bonus_speed", "upgrade": "", "digits": 1,
	},
	"hp": {
		"value_type": "stat", "label": "Здоровье", "icon": "icon_heart.png",
		"stat": "health", "bonus": "bonus_health", "upgrade": "", "digits": 0,
	},
	## То же здоровье, но «текущее/максимум» — для карточки живого юнита на карте
	"hp_current": {
		"value_type": "current_max", "label": "Здоровье", "icon": "icon_heart.png", "stat": "health",
	},
	"range": {
		"value_type": "plain", "stat": "attack_range", "fmt": "Дальность: %.1f м",
	},
	"cooldown": {
		"value_type": "plain", "stat": "attack_cooldown", "fmt": "Удар раз в %.2f с",
	},
	"morale": {
		"value_type": "plain", "stat": "morale", "fmt": "Мораль: %.0f",
	},
	"gather": {
		"value_type": "pair", "stats": ["gather_amount", "gather_time"],
		"fmt": "Добыча: %.0f за %.1f с",
		"label": "Добыча", "short": "%.0f за %.1f с", "icon": "icon_axe.png",
	},
	"carry_speed": {
		"value_type": "pair", "stats": ["walk_speed_empty", "walk_speed_loaded"],
		"fmt": "Скорость: %.1f налегке / %.1f с грузом",
		"label": "Скорость", "short": "%.1f / %.1f с грузом", "icon": "icon_luck_horseshoe.png",
	},
	"arrow": {
		"value_type": "pair", "stats": ["arrow_speed", "arrow_arc"],
		"fmt": "Стрела: %.1f м/с, дуга %.1f",
	},
}

# ── КАРТОЧКИ ──
# Ключ — unit_id (как в unit_stats_config.STATS и forge_config.UNITS); текст, иконка и состав строк правятся свободно
static var TOOLTIPS: Dictionary = {
	"spearman": {
		"display_name": "Копейщик",
		"role": "Строевая пехота",
		"skills": "Держать строй, Фаланга (кузница)",
		"special": "Натиск фаланги (сомкнутый удар копьями)",
		"icon": "res://assets/factions/humans/icons/units/Lancer.png",
		"description": "Основа строя. Могут строиться в фалангу и делать стену копий. Эффективен против конницы и крупных целей (троллей, гоблинов). Сдерживающий мясной щит.",
		# дальности и темпа удара нет намеренно — отладочные числа, не сведения для игрока
		"visible_stats": [
			{"key": "hp"}, {"key": "attack"}, {"key": "armor"},
			{"key": "move_speed"},
		],
		"show_cost": true,
	},
	"warrior": {
		"display_name": "Мечник",
		"role": "Штурмовая пехота",
		"skills": "Стена щитов",
		"special": "Яростная атака (серия стремительных ударов)",
		"icon": "res://assets/factions/humans/icons/units/Warrior.png",
		"description": "Штурмовая пехота. Строится в стену щитов. Эффективен для быстрых атак с флангов, отлично режет копейщиков и стрелков.",
		# без дальности и темпа удара (как у копейщика)
		"visible_stats": [
			{"key": "hp"}, {"key": "attack"}, {"key": "armor"},
			{"key": "move_speed"},
		],
		"show_cost": true,
	},
	"archer": {
		"display_name": "Лучник",
		"role": "Стрелки",
		"skills": "Стрельба из укрытия, Залповый огонь (кузница)",
		"special": "Снайперский выстрел",
		"icon": "res://assets/factions/humans/icons/units/Archer.png",
		"description": "Дальнобойный юнит. Может стрелять залпом по скоплениям врагов. Способен занимать башни, крепости и бараки для стрельбы с укрытия (+дальность и урон).",
		"visible_stats": [
			{"key": "hp"}, {"key": "attack"}, {"key": "armor"},
			{"key": "move_speed"},
		],
		"show_cost": true,
	},
	"monk": {
		"display_name": "Монах",
		"role": "Поддержка",
		"skills": "Исцеление раненых",
		"special": "Возвращение павших в строй",
		# портрета нет — первый кадр боевого листа (как у кнопки найма в Замке)
		"icon": "res://assets/factions/humans/units/Blue Units/Monk/Idle.png",
		"description": "Вспомогательный юнит. Исцеляет раненых бойцов и воскрешает павших прямо на поле боя. Эффективность сильно возрастает с улучшениями в Кузнице.",
		# Брони у монаха нет по конфигу — строки в списке тоже нет
		"visible_stats": [
			{"key": "hp"}, {"key": "attack"},
			{"key": "move_speed"},
		],
		"show_cost": true,
	},
	"worker": {
		"display_name": "Рабочий",
		"role": "Хозяйство",
		"skills": "Добыча, стройка, ремонт",
		"special": "Укрытие в замке по тревоге",
		"icon": "res://assets/factions/humans/icons/units/Avatars_25.png",
		"description": "Добывает ресурсы и строит здания. Безоружен — держите его подальше от боя.",
		# Ни "attack", ни "armor": этих параметров у рабочего нет по смыслу
		"visible_stats": [
			{"key": "hp"}, {"key": "carry_speed"}, {"key": "gather"},
		],
		"show_cost": true,
	},
}

## Строки по умолчанию для unit_id без карточки; "armor" намеренно не входит (чаще всего ноль)
static var DEFAULT_VISIBLE_STATS: Array = [
	{"key": "hp"}, {"key": "attack"}, {"key": "move_speed"},
]

## Описание карточки объекта. Пустым не возвращается никогда: неизвестный id
## получает набор по умолчанию и имя из unit_stats_config
static func tooltip(unit_id: String) -> Dictionary:
	var t: Dictionary = TOOLTIPS.get(unit_id, {})
	return {
		"unit_id":       unit_id,
		"display_name":  String(t.get("display_name", unit_id)),
		"icon":          String(t.get("icon", "")),
		"description":   String(t.get("description",
							_UCfg.get_stats(unit_id).get("description", ""))),
		"visible_stats": t.get("visible_stats", DEFAULT_VISIBLE_STATS),
		"show_cost":     bool(t.get("show_cost", true)),
		"role":          String(t.get("role", "")),
		"skills":        String(t.get("skills", "")),
		"special":       String(t.get("special", "")),
	}

## Строка карточки поверх библиотечной записи PARAMS (подпись/формат можно переопределить на месте);
## {} — такого ключа в PARAMS нет, строка не рисуется
static func param(row: Dictionary) -> Dictionary:
	var key: String = String(row.get("key", ""))
	var base: Dictionary = PARAMS.get(key, {})
	if base.is_empty():
		return {}
	var out: Dictionary = base.duplicate(true)
	for k in row:
		if k != "key":
			out[k] = row[k]      # локальное переопределение подписи/формата
	out["key"] = key
	return out

## Базовое значение из конфига: [value, found]; found = false — у юнита нет такого ключа, строка не рисуется
static func base_value(unit_id: String, p: Dictionary) -> Array:
	if p.is_empty():
		return [0.0, false]
	var s: Dictionary = _UCfg.get_stats(unit_id)
	if p.has("max_of"):
		var best: float = 0.0
		var got := false
		for k in p["max_of"]:
			if s.has(k):
				best = maxf(best, float(s[k]))
				got = true
		return [best, got]
	if p.has("sum_of"):
		var total: float = 0.0
		var got2 := false
		for k in p["sum_of"]:
			if s.has(k):
				total += float(s[k])
				got2 = true
		return [total, got2]
	var key: String = String(p.get("stat", ""))
	if key.is_empty() or not s.has(key):
		return [0.0, false]
	return [float(s[key]), true]

## Числа для строки "pair". [values, found]: found = false, если хотя бы одного
## ключа в конфиге нет — половинчатая строка хуже отсутствующей
static func pair_values(unit_id: String, p: Dictionary) -> Array:
	var keys: Array = p.get("stats", [])
	if keys.is_empty():
		return [[], false]
	var s: Dictionary = _UCfg.get_stats(unit_id)
	var out: Array = []
	for k in keys:
		if not s.has(k):
			return [[], false]
		out.append(float(s[k]))
	return [out, true]
