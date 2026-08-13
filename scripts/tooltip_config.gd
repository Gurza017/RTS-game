extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## КОНФИГ ВСПЛЫВАЮЩИХ КАРТОЧЕК ЮНИТОВ (Unit Hover Modal / Tooltip)
## ═══════════════════════════════════════════════════════════════════════════
## Что показывает карточка юнита и В КАКОМ ПОРЯДКЕ — настраивается ЗДЕСЬ, а не
## в коде HUD. Подключение:
##   const _TipCfg := preload("res://scripts/tooltip_config.gd")
## (файл намеренно без class_name — не зависит от кэша глобальных классов, тот
## же приём, что у unit_stats_config.gd и forge_config.gd)
##
## ── ГЛАВНОЕ ПРАВИЛО ─────────────────────────────────────────────────────────
## НЕТ ПАРАМЕТРА В visible_stats — НЕТ СТРОКИ В ОКНЕ.
## Список visible_stats у объекта — это исчерпывающий перечень того, что
## рисуется. Убрать «Броню» у Рабочего = удалить строку из его списка; добавить
## «Дальность» Монаху = дописать строку. Кода при этом не касаемся вовсе:
## HUD._unit_card просто идёт по списку сверху вниз и строит, что сказано.
##
## Так и появился этот файл: раньше состав карточки был зашит в код
## последовательностью append'ов, часть строк добавлялась БЕЗУСЛОВНО, и у
## Рабочего в тултипе стояло «Armor 0» — параметра, которого у него по смыслу
## нет вовсе.
##
## ── ПОРЯДОК БЛОКОВ КАРТОЧКИ (его собирает HUD._show_card) ──────────────────
##   1) иконка + название      ← "icon" / "display_name"
##   2) строки параметров      ← "visible_stats" (порядок = порядок в списке)
##   3) описание               ← "description"
##   4) цена                   ← "show_cost" (сама цена приходит от вызывающего)

const _UCfg := preload("res://scripts/unit_stats_config.gd")

# ─────────────────────────────────────────────────────────────────────────────
# ЧТО ЗНАЧИТ value_type У СТРОКИ
#
#   "stat"        — «База + Кузница + Опыт = Итог» цветной формулой. Только для
#                   того, на что бонусы вообще действуют (атака, броня, HP…).
#   "current_max" — «Здоровье: 80/100». Требует ЖИВОГО юнита; в карточке найма
#                   живого нет, и строка честно показывает один максимум.
#   "plain"       — «Дальность: 20.0 м»: одно число по формату fmt.
#   "pair"        — два числа из конфига в одну строку по формату fmt.
#
# "source" — откуда брать число из unit_stats_config.STATS:
#   "stat":  один ключ            "sum_of":  сумма ключей (защита = defense+armor)
#   "max_of": максимум из ключей  "stats":   несколько ключей для "pair"
#
# "bonus" / "upgrade" — ключи прибавок кузницы и старых плоских апгрейдов.
# "digits" — знаков после запятой (у скорости 1, у остального 0).
# ─────────────────────────────────────────────────────────────────────────────

## СЛОВАРЬ ИЗВЕСТНЫХ ПАРАМЕТРОВ. Это «библиотека строк»: как каждая считается и
## как подписана. Сами карточки ниже только СОБИРАЮТ строки из этой библиотеки
static var PARAMS: Dictionary = {
	"attack": {
		"value_type": "stat", "label": "Атака",
		"max_of": ["attack_1", "attack_2"],
		"bonus": "bonus_attack", "upgrade": "damage", "digits": 0,
	},
	"armor": {
		"value_type": "stat", "label": "Броня",
		"sum_of": ["defense", "armor"],
		"bonus": "bonus_armor", "upgrade": "defense", "digits": 0,
	},
	"move_speed": {
		"value_type": "stat", "label": "Скорость",
		"max_of": ["movement_speed", "walk_speed_empty"],
		"bonus": "bonus_speed", "upgrade": "", "digits": 1,
	},
	"hp": {
		"value_type": "stat", "label": "Здоровье",
		"stat": "health", "bonus": "bonus_health", "upgrade": "", "digits": 0,
	},
	## То же здоровье, но «текущее/максимум» — для карточки живого юнита на карте
	"hp_current": {
		"value_type": "current_max", "label": "Здоровье", "stat": "health",
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
	},
	"carry_speed": {
		"value_type": "pair", "stats": ["walk_speed_empty", "walk_speed_loaded"],
		"fmt": "Скорость: %.1f налегке / %.1f с грузом",
	},
	"arrow": {
		"value_type": "pair", "stats": ["arrow_speed", "arrow_arc"],
		"fmt": "Стрела: %.1f м/с, дуга %.1f",
	},
}

# ─────────────────────────────────────────────────────────────────────────────
# КАРТОЧКИ ЮНИТОВ
#
# Ключ верхнего уровня — unit_id, тот же, что в unit_stats_config.STATS и в
# forge_config.UNITS. Правится свободно: и текст, и иконка, и СОСТАВ строк.
#
# Обрати внимание на "worker": в его visible_stats НЕТ ни "attack", ни "armor" —
# рабочий не воюет и брони не носит, и нулевых строк в его карточке не будет.
# ─────────────────────────────────────────────────────────────────────────────
static var TOOLTIPS: Dictionary = {
	"spearman": {
		"display_name": "Копейщик",
		"icon": "res://assets/factions/humans/icons/units/Lancer.png",
		"description": "Основа строя. Держит линию плечом к плечу — копья опускаются сами, когда враг подходит вплотную.",
		"visible_stats": [
			{"key": "hp"}, {"key": "attack"}, {"key": "armor"},
			{"key": "move_speed"}, {"key": "range"}, {"key": "cooldown"},
		],
		"show_cost": true,
	},
	"warrior": {
		"display_name": "Мечник",
		"icon": "res://assets/factions/humans/icons/units/Warrior.png",
		"description": "Тяжёлая пехота. Сильнее всех в прямой рубке и продавливает чужой строй при столкновении.",
		"visible_stats": [
			{"key": "hp"}, {"key": "attack"}, {"key": "armor"},
			{"key": "move_speed"}, {"key": "range"}, {"key": "cooldown"},
		],
		"show_cost": true,
	},
	"archer": {
		"display_name": "Лучник",
		"icon": "res://assets/factions/humans/icons/units/Archer.png",
		"description": "Стрелок. Бьёт далеко и ходит быстро, но в ближнем бою гибнет мгновенно.",
		"visible_stats": [
			{"key": "hp"}, {"key": "attack"}, {"key": "armor"},
			{"key": "move_speed"}, {"key": "range"}, {"key": "cooldown"},
			{"key": "arrow"},
		],
		"show_cost": true,
	},
	"monk": {
		"display_name": "Монах",
		# Готового портрета у монаха нет — берём первый кадр его боевого листа,
		# ровно тот же путь и тот же приём, что и у кнопки найма в Замке
		# (HUD.UNIT_ICONS + FRAME_SHEET_ICONS обрезают кадр по силуэту)
		"icon": "res://assets/factions/humans/units/Blue Units/Monk/Idle.png",
		"description": "Вспомогательный юнит. В бою слаб — держите его за строем.",
		# Брони у монаха нет по конфигу — строки в списке тоже нет
		"visible_stats": [
			{"key": "hp"}, {"key": "attack"},
			{"key": "move_speed"}, {"key": "range"},
		],
		"show_cost": true,
	},
	"worker": {
		"display_name": "Рабочий",
		"icon": "res://assets/factions/humans/icons/units/Avatars_25.png",
		"description": "Добывает ресурсы и строит здания. Безоружен — держите его подальше от боя.",
		# Ни "attack", ни "armor": этих параметров у рабочего нет по смыслу
		"visible_stats": [
			{"key": "hp"}, {"key": "carry_speed"}, {"key": "gather"},
		],
		"show_cost": true,
	},
}

## НАБОР СТРОК ПО УМОЛЧАНИЮ — для unit_id, которого в TOOLTIPS ещё нет.
## Новый юнит получает осмысленную карточку сразу, до того как его опишут здесь.
## "armor" сюда НЕ входит намеренно: это тот параметр, который чаще всего
## оказывается нулевым, и по умолчанию лучше промолчать, чем показать ноль
static var DEFAULT_VISIBLE_STATS: Array = [
	{"key": "hp"}, {"key": "attack"}, {"key": "move_speed"}, {"key": "range"},
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
	}

## Описание одной строки: то, что задано в visible_stats, ПОВЕРХ библиотечного
## описания из PARAMS. Так в самой карточке можно переопределить подпись
## («Здоровье» → «Живучесть»), не трогая библиотеку.
## Пустой словарь — такого параметра в PARAMS нет (опечатка в visible_stats),
## и строка молча не рисуется
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

## БАЗОВОЕ ЗНАЧЕНИЕ ПАРАМЕТРА ИЗ КОНФИГА и признак «оно там вообще есть».
## Возвращает [value, found]. found = false означает «в STATS этого юнита
## такого ключа нет» — строка не рисуется. Это второй рубеж того же правила:
## даже если параметр перечислен в visible_stats, но конфиг юнита его не
## содержит, окно молчит
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
