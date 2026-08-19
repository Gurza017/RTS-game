extends RefCounted
class_name Constants

const LAYER_GROUND    = 1
const LAYER_UNITS     = 2
const LAYER_BUILDINGS = 4
const LAYER_RESOURCES = 8
## РУИНЫ — СВОЙ СЛОЙ, НЕ LAYER_BUILDINGS.
## Руина обязана ловить ПКМ («послать рабочих отстроить»), но не должна ни
## выделяться левой кнопкой, ни перехватывать луч, ищущий здания: _resolve_node
## вернул бы на ней null, а null в _pick_at означает «дальше грунт, поиск
## закончен» — и всё, что стоит за руиной, стало бы некликабельным
const LAYER_RUINS     = 16

const FACTION_PLAYER = 0
const FACTION_ENEMY  = 1
## ГОБЛИНЫ — ТРЕТЬЯ СТОРОНА, ВРАЖДЕБНАЯ ВСЕМ.
## Не «второй ИИ»: у них нет союзников, они не входят в группы enemy_* (иначе
## EnemyAI записал бы их в свою армию) и не участвуют в условии победы —
## партия по-прежнему решается между синими и красными.
const FACTION_GOBLIN = 2
## Сколько фракций знает игра. Должно совпадать с ArmyCore.Factions (там 4,
## с запасом под нейтралов) — сторожит qa_goblin
const FACTION_COUNT  = 3

## Группы узлов по фракциям. ЕДИНСТВЕННОЕ место, где сопоставлены номер и имя:
## раньше это была развилка `if player then ... else enemy`, и третья сторона
## молча попадала бы в «enemy_*» — то есть в состав армии красного ИИ
const UNIT_GROUPS := {
	FACTION_PLAYER: "player_units",
	FACTION_ENEMY:  "enemy_units",
	FACTION_GOBLIN: "goblin_units",
}
const BUILDING_GROUPS := {
	FACTION_PLAYER: "player_buildings",
	FACTION_ENEMY:  "enemy_buildings",
	FACTION_GOBLIN: "goblin_buildings",
}

static func unit_group(faction: int) -> String:
	return String(UNIT_GROUPS.get(faction, "enemy_units"))

static func building_group(faction: int) -> String:
	return String(BUILDING_GROUPS.get(faction, "enemy_buildings"))

## Все фракции, кроме своей. Нужен всем, кто ищет «чужое»: с двумя сторонами
## это была одна строка `player if enemy else enemy`, с тремя — список
static func other_factions(faction: int) -> Array:
	var out: Array = []
	for f in range(FACTION_COUNT):
		if f != faction:
			out.append(f)
	return out

## Имена групп чужих зданий — для тех, кто ищет цель, а не «врага ИИ»
static func enemy_building_groups(faction: int) -> Array:
	var out: Array = []
	for f in other_factions(faction):
		out.append(building_group(f))
	return out

const RESOURCE_WOOD  = 0
const RESOURCE_GOLD  = 1
const RESOURCE_STONE = 2
const RESOURCE_FOOD  = 3
# Вода УДАЛЕНА как игровой ресурс: её не добывают, не хранят и не показывают
# в интерфейсе. Озеро на карте — чисто декорация (и препятствие для юнитов).
