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
## House1..House3. Кузнице своей картинки в паке нет — ей отдан монастырь.
## РУДНИК КАРТИНКИ НЕ ИМЕЕТ ВОВСЕ (09.09.2026): раньше он рисовался как
## House1 — при трёх домах в меню это был бы четвёртый дом, добывающий
## золото; теперь у него процедурный вид (Mine._build_visual)
const BUILDING_SPRITES := {
	"castle":     "Castle",
	"barracks":   "Barracks",
	"archery":    "Archery",
	"smithy":     "Monastery",
	"mine":       "",
	"house":      "House1",
	"house2":     "House2",
	"house3":     "House3",
	"towncenter": "House3",
	"tower":      "Tower",
}

const _UNITS_ROOT     := "res://assets/factions/%s/units/%s Units/%s"
const _BUILDINGS_ROOT := "res://assets/factions/%s/buildings/%s Buildings/%s.png"

## ═══════════════════════════════════════════════════════════════════════════
## СТРОЙКА И РУИНЫ
## ═══════════════════════════════════════════════════════════════════════════
## Картинки стройки и руин. У Замка и у БАШНИ свои, у всех остальных — общие
## «домовые». Цвета у них нет (леса и обломки одинаковы у любой стороны),
## поэтому папка одна, а не «{Цвет} Buildings». Имя папки с опечаткой
## (process_building_destroeyrs) — оставлено как есть, чтобы не ломать пути
const _PROCESS_ROOT := "res://assets/factions/%s/icons/buildings/process_building_destroeyrs/%s.png"
## ── ВТОРОЙ КОРЕНЬ: РЯДОМ С САМИМИ ПОСТРОЙКАМИ ─────────────────────────────
## Спрайты башни (Tower_Construction / Tower_Destroyed) лежат не в папке
## «процессов», а рядом с остальными постройками. Копировать их во вторую
## папку ради единообразия НЕЛЬЗЯ: два файла с одной картинкой неминуемо
## разъедутся при первой же перерисовке, и половина игры покажет старый
const _BUILDINGS_FLAT_ROOT := "res://assets/factions/%s/buildings/%s.png"

## Ключи — ID постройки; чего нет в таблице, берёт общие «домовые» картинки.
## `root` называет, в какой из двух папок лежит файл
const PROCESS_SPRITES := {
	"castle": {"build": "Castle_Construction", "ruin": "Castle_Destroyed"},
	"house":  {"build": "House_Construction",  "ruin": "House_Destroyed"},
	# ── У БАШНИ СВОИ (заказ владельца) ────────────────────────────────────
	# «Домовая» стройка и «домовое» пепелище — широкие и низкие, а башня
	# узкая и высокая: общая картинка лежала шире самой постройки, и её
	# приходилось ужимать долей (construction_scale / ruin_scale 0.6). Со
	# своими спрайтами (128×256, ровно как сам Tower.png) доля не нужна
	"tower":  {"build": "Tower_Construction",  "ruin": "Tower_Destroyed",
		"root": "buildings"},
}

## Картинка стройки для здания building_id ("" — такой нет)
static func construction_sprite(race: String, building_id: String) -> String:
	return _process_sprite(race, building_id, "build")

## Картинка руин для здания building_id ("" — такой нет)
static func ruin_sprite(race: String, building_id: String) -> String:
	return _process_sprite(race, building_id, "ruin")

static func _process_sprite(race: String, building_id: String, kind: String) -> String:
	# СВОЙ НАБОР ИЩЕТСЯ ПО ID ПОСТРОЙКИ, а не списком исключений: заведётся
	# своя картинка у бараков — хватит строки в таблице. Чего в таблице нет,
	# берёт общие «домовые»
	var row: Dictionary = PROCESS_SPRITES.get(building_id, {})
	if row.is_empty():
		row = PROCESS_SPRITES.get("house", {})
	var name: String = String(row.get(kind, ""))
	if name.is_empty():
		return ""
	if String(row.get("root", "")) == "buildings":
		return _BUILDINGS_FLAT_ROOT % [race, name]
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

## ═══════════════════════════════════════════════════════════════════════════
## НАСТРОЙКИ ОТОБРАЖЕНИЯ (заказ владельца 10.09.2026, меню «Опции»)
## ═══════════════════════════════════════════════════════════════════════════
## Две ручки, обе живут на диске и читаются партией при сборке HUD и камеры:
##   show_fps  — плашка FPS в правом верхнем углу (её же переключает F3)
##   edge_pan  — камера едет, когда курсор у края экрана
##
## ФАЙЛ, А НЕ ПОЛЕ В GameManager: настройка нужна ДО того, как автозагрузка
## что-либо решит (меню строится первым), и обязана переживать перезапуск —
## тем же порядком, что сложность (user://difficulty.cfg) и громкость
const VIEW_CFG := "user://view_settings.cfg"

static var _view_loaded: bool = false
static var _show_fps: bool = true
static var _edge_pan: bool = true
## ── ПЕРЕМИРИЕ (ТЗ 14.09.2026, п. 2) ──────────────────────────────────────
## Чекбокс «Перемирие» в опциях и в паузе. Включён — первые TRUCE_SEC партии
## орда в мирной фазе, красный ИИ не рейдит, в HUD плашка с отсчётом.
## Выключен — плашка гаснет, перемирие снимается НЕМЕДЛЕННО: обе стороны
## переходят в боевой режим по своим штатным алгоритмам (GameManager.
## truce_left отвечает нулём, GoblinAI._peace_sec — нулём, EnemyAI —
## AI_TRUCE_SEC = 0). Живёт на диске рядом с остальными ручками вида
static var _armistice: bool = true

static func load_view_settings() -> void:
	_view_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(VIEW_CFG) != OK:
		return
	_show_fps = bool(cfg.get_value("view", "show_fps", _show_fps))
	_edge_pan = bool(cfg.get_value("view", "edge_pan", _edge_pan))
	_armistice = bool(cfg.get_value("game", "armistice", _armistice))

static func save_view_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("view", "show_fps", _show_fps)
	cfg.set_value("view", "edge_pan", _edge_pan)
	cfg.set_value("game", "armistice", _armistice)
	cfg.save(VIEW_CFG)

## Читатели ЛЕНИВО подхватывают файл: партия может запуститься и без меню
## (стенды, --path прямо в Main.tscn), и тогда никто load_view_settings не звал
static func show_fps() -> bool:
	if not _view_loaded:
		load_view_settings()
	return _show_fps

static func set_show_fps(on: bool) -> void:
	_show_fps = on
	save_view_settings()

static func edge_pan() -> bool:
	if not _view_loaded:
		load_view_settings()
	return _edge_pan

static func set_edge_pan(on: bool) -> void:
	_edge_pan = on
	save_view_settings()

static func armistice() -> bool:
	if not _view_loaded:
		load_view_settings()
	return _armistice

static func set_armistice(on: bool) -> void:
	_armistice = on
	save_view_settings()
