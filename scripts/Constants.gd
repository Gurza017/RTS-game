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

const RESOURCE_WOOD  = 0
const RESOURCE_GOLD  = 1
const RESOURCE_STONE = 2
const RESOURCE_FOOD  = 3
# Вода УДАЛЕНА как игровой ресурс: её не добывают, не хранят и не показывают
# в интерфейсе. Озеро на карте — чисто декорация (и препятствие для юнитов).
