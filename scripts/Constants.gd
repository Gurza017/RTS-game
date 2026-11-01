extends RefCounted
class_name Constants
## Общие константы: слои пикинга, фракции и их группы узлов, ресурсы.
## Заметки — docs/config_notes/Constants.md

## ── СЛОИ ПИКИНГА ──
const LAYER_GROUND    = 1
const LAYER_UNITS     = 2
const LAYER_BUILDINGS = 4
const LAYER_RESOURCES = 8
## Руины — свой слой: ловят ПКМ «отстроить», но не выделяются и не перехватывают луч поиска зданий
const LAYER_RUINS     = 16

## ── ФРАКЦИИ ──
const FACTION_PLAYER = 0
const FACTION_ENEMY  = 1
## Третья сторона, враждебная всем; в условии победы не участвует
const FACTION_GOBLIN = 2
## Число сторон партии (нейтралы не входят); ArmyCore.Factions = 4 — с запасом под них
const FACTION_COUNT  = 3
## Ничейные постройки (рудник до захвата): в FACTION_COUNT не входят, строк ядра не имеют
const FACTION_NEUTRAL = 3

## Группы узлов по фракциям — единственное место, где номер сопоставлен имени
const UNIT_GROUPS := {
	FACTION_PLAYER: "player_units",
	FACTION_ENEMY:  "enemy_units",
	FACTION_GOBLIN: "goblin_units",
	FACTION_NEUTRAL: "neutral_units",
}
const BUILDING_GROUPS := {
	FACTION_PLAYER: "player_buildings",
	FACTION_ENEMY:  "enemy_buildings",
	FACTION_GOBLIN: "goblin_buildings",
	FACTION_NEUTRAL: "neutral_buildings",
}

static func unit_group(faction: int) -> String:
	return String(UNIT_GROUPS.get(faction, "enemy_units"))

static func building_group(faction: int) -> String:
	return String(BUILDING_GROUPS.get(faction, "enemy_buildings"))

## Все фракции, кроме своей
static func other_factions(faction: int) -> Array:
	var out: Array = []
	for f in range(FACTION_COUNT):
		if f != faction:
			out.append(f)
	return out

## Группы чужих зданий по фракции — общий справочник, отдаётся тем же объектом (только читать):
## зовётся из поиска цели каждый кадр, новый массив на вызов недопустим
static var _enemy_bld_groups: Array = []

static func enemy_building_groups(faction: int) -> Array:
	if _enemy_bld_groups.is_empty():
		for f in range(FACTION_COUNT):
			var row: Array = []
			for o in other_factions(f):
				row.append(building_group(int(o)))
			_enemy_bld_groups.append(row)
	if faction < 0 or faction >= _enemy_bld_groups.size():
		return []
	return _enemy_bld_groups[faction]

## ── РЕСУРСЫ ──
const RESOURCE_WOOD  = 0
const RESOURCE_GOLD  = 1
const RESOURCE_STONE = 2
const RESOURCE_FOOD  = 3
