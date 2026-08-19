extends Node

## Балансная таблица: стартовые запасы игрока и ИИ (см. reset_resources)
const _UCfg := preload("res://scripts/unit_stats_config.gd")

signal resources_changed(faction)

var resources: Dictionary = {}

func _ready() -> void:
	for f in range(Constants.FACTION_COUNT):
		_init_faction(f)

func _init_faction(f: int) -> void:
	resources[f] = {
		Constants.RESOURCE_WOOD:  0.0,
		Constants.RESOURCE_GOLD:  0.0,
		Constants.RESOURCE_STONE: 0.0,
		Constants.RESOURCE_FOOD:  0.0,
	}

func reset_resources() -> void:
	# ЧИСЛА ЖИВУТ В КОНФИГЕ, А НЕ ЗДЕСЬ. Стартовый запас — балансная настройка,
	# и её место в балансной таблице: _UCfg.PLAYER_STARTING_RESOURCES /
	# AI_STARTING_RESOURCES. Блока два, но значения в них одинаковые — РАВНЫЙ
	# СТАРТ сохранён специально: когда у ИИ было на 50 дерева и 50 золота больше,
	# он закладывал постройку раньше игрока, и это читалось как «ресурсы падают
	# с неба». Раздельные блоки нужны, чтобы фору МОЖНО было дать осознанно
	for f in range(Constants.FACTION_COUNT):
		resources[f] = _UCfg.starting_resources(f)
	gathered.clear()          # новая партия — новый счёт добытого
	resources_changed.emit(Constants.FACTION_PLAYER)

func add_resource(faction: int, type: int, amount: float) -> void:
	if not resources.has(faction):
		_init_faction(faction)
	resources[faction][type] = resources[faction].get(type, 0.0) + amount
	resources_changed.emit(faction)

## ── СЧЁТЧИК ДОБЫТОГО ЗА ПАРТИЮ ───────────────────────────────────────────────
## Нарастающий итог того, что РЕАЛЬНО принесли в замок (и накапали пассивные
## источники). Нужен HUD'у, чтобы показывать постоянный приток: изменение
## самого склада для этого не годится — найм отряда или закладка постройки
## вычитают сотни разом, и приток на глазах у игрока проваливался в ноль,
## пока рабочие продолжали копать. Здесь вычитаний нет по построению
var gathered: Dictionary = {}

## Приход ПО ДОБЫЧЕ: тот же add_resource плюс отметка в счётчике.
## Зовётся отовсюду, где ресурс ПОЯВЛЯЕТСЯ в мире (сдача груза, пассивный
## доход замка/рудника/дома). Возвраты (отмена стройки, отмена исследования)
## идут мимо — это не добыча, а откат траты
func gather_resource(faction: int, type: int, amount: float) -> void:
	if not gathered.has(faction):
		gathered[faction] = {}
	var per: Dictionary = gathered[faction]
	per[type] = float(per.get(type, 0.0)) + amount
	add_resource(faction, type, amount)

## Сколько всего добыто с начала партии (0, если ещё ничего)
func gathered_total(faction: int, type: int) -> float:
	var per: Variant = gathered.get(faction)
	if per == null:
		return 0.0
	return float((per as Dictionary).get(type, 0.0))

func can_afford(faction: int, costs: Dictionary) -> bool:
	if not resources.has(faction):
		return false
	for type in costs.keys():
		if resources[faction].get(type, 0.0) < costs[type]:
			return false
	return true

func spend(faction: int, costs: Dictionary) -> bool:
	if not can_afford(faction, costs):
		return false
	for type in costs.keys():
		resources[faction][type] -= costs[type]
	resources_changed.emit(faction)
	return true

func get_amount(faction: int, type: int) -> float:
	if not resources.has(faction):
		return 0.0
	return resources[faction].get(type, 0.0)
