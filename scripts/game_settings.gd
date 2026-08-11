extends RefCounted
## НАСТРОЙКИ ПАРТИИ: ЦВЕТА ФРАКЦИЙ
## ═══════════════════════════════════════════════════════════════════════════
## Единственное место, где собраны пути к цветным ассетам. Юниты и здания
## спрашивают путь ОТСЮДА, а не склеивают строки у себя — поменяли раскладку
## папок здесь, и её подхватили все.
## Файл намеренно без class_name (как unit_stats_config.gd) — так он не зависит
## от кэша глобальных классов Godot.
##
## Подключение: const _GS := preload("res://scripts/game_settings.gd")

## Цвета, доступные для выбора. Значение — имя папки на диске.
const COLORS := ["Black", "Blue", "Purple", "Red", "Yellow"]

## Подписи для меню (в том же порядке, что COLORS)
const COLOR_LABELS := ["Чёрные", "Синие", "Фиолетовые", "Красные", "Жёлтые"]

## Цвет для подсветки в UI (рамка кнопки выбора, оттенок выделения)
const COLOR_TINTS := {
	"Black":  Color(0.30, 0.32, 0.38),
	"Blue":   Color(0.28, 0.45, 0.85),
	"Purple": Color(0.55, 0.32, 0.78),
	"Red":    Color(0.80, 0.25, 0.22),
	"Yellow": Color(0.88, 0.75, 0.20),
}

const DEFAULT_PLAYER_COLOR := "Blue"
const DEFAULT_AI_COLOR     := "Red"

## Тип юнита → имя подпапки внутри «{Цвет} Units»
const UNIT_FOLDERS := {
	"spearman": "Lancer",
	"archer":   "Archer",
	"worker":   "Pawn",
	"warrior":  "Warrior",
	"monk":     "Monk",
}

## Тип здания → имя PNG внутри «{Цвет} Buildings» (без расширения).
## Набор готовых спрайтов: Castle, Barracks, Archery, Monastery, Tower,
## House1..House3. Кузнице и руднику своих картинок в паке нет, поэтому им
## подобраны ближайшие по смыслу — поменять можно прямо здесь.
const BUILDING_SPRITES := {
	"castle":     "Castle",
	"barracks":   "Barracks",
	"archery":    "Archery",
	"smithy":     "Monastery",
	"mine":       "House1",
	"house":      "House2",
	"towncenter": "House3",
	"tower":      "Tower",
}

const _UNITS_ROOT     := "res://assets/factions/%s/units/%s Units/%s"
const _BUILDINGS_ROOT := "res://assets/factions/%s/buildings/%s Buildings/%s.png"

## ═══════════════════════════════════════════════════════════════════════════
## СТРОЙКА И РУИНЫ
## ═══════════════════════════════════════════════════════════════════════════
## Четыре картинки на все постройки: у Замка свои, у всех остальных — общие.
## Цвета у них нет (леса и обломки одинаковы у любой стороны), поэтому папка
## одна, а не «{Цвет} Buildings». Имя папки на диске написано с опечаткой
## (process_building_destroeyrs) — оставлено как есть, чтобы не ломать пути
const _PROCESS_ROOT := "res://assets/factions/%s/icons/buildings/process_building_destroeyrs/%s.png"

## Ключи: castle → свои картинки, всё остальное → общие «домовые»
const PROCESS_SPRITES := {
	"castle": {"build": "Castle_Construction", "ruin": "Castle_Destroyed"},
	"house":  {"build": "House_Construction",  "ruin": "House_Destroyed"},
}

## Картинка стройки для здания building_id ("" — такой нет)
static func construction_sprite(race: String, building_id: String) -> String:
	return _process_sprite(race, building_id, "build")

## Картинка руин для здания building_id ("" — такой нет)
static func ruin_sprite(race: String, building_id: String) -> String:
	return _process_sprite(race, building_id, "ruin")

static func _process_sprite(race: String, building_id: String, kind: String) -> String:
	# Замок — единственный со своим набором; для всего прочего берётся «дом»
	var key: String = "castle" if building_id == "castle" else "house"
	var row: Dictionary = PROCESS_SPRITES.get(key, {})
	var name: String = String(row.get(kind, ""))
	if name.is_empty():
		return ""
	return _PROCESS_ROOT % [race, name]

## Нормализует цвет: неизвестное значение схлопывается в первый доступный,
## чтобы опечатка в настройках не оставляла юнита вовсе без спрайта
static func normalize_color(color: String) -> String:
	return color if color in COLORS else String(COLORS[0])

## Папка со спрайтами юнита данного типа и цвета.
## Пример: unit_folder("humans", "Black", "spearman")
##         → res://assets/factions/humans/units/Black Units/Lancer
static func unit_folder(race: String, color: String, unit_id: String) -> String:
	var sub: String = String(UNIT_FOLDERS.get(unit_id, ""))
	if sub.is_empty():
		return ""
	return _UNITS_ROOT % [race, normalize_color(color), sub]

## Путь к спрайту здания данного типа и цвета ("" — типа нет в раскладке)
static func building_sprite(race: String, color: String, building_id: String) -> String:
	var name: String = String(BUILDING_SPRITES.get(building_id, ""))
	if name.is_empty():
		return ""
	return _BUILDINGS_ROOT % [race, normalize_color(color), name]

static func color_tint(color: String) -> Color:
	return COLOR_TINTS.get(normalize_color(color), Color.WHITE)
