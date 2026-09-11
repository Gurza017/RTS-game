extends Building
## СТРЕЛКОВАЯ (Archery) — нанимает лучников (заказ владельца, 09.09.2026).
##
## Найм лучников переехал сюда из бараков: там осталась пехота. Цена, время и
## размер отряда — unit_stats_config.TRAINING["archery"]; запас жизни, габарит
## и цена постройки — BUILDINGS["archery"]. Кода найма здесь нет вовсе: всё
## делает Building.train_from_config по конфигу.
##
## Файл НАМЕРЕННО без class_name: подключается через preload/load, поэтому не
## зависит от global_script_class_cache.cfg (тот же приём, что у House).

const _UCfg := preload("res://scripts/unit_stats_config.gd")

func _ready() -> void:
	building_id   = "archery"
	sprite_path   = ""
	max_health    = _UCfg.building_stat("archery", "max_hp", 1800.0)
	build_size    = _UCfg.building_size("archery", Vector3(3.5, 2.2, 3.5))
	display_name  = String(_UCfg.building_cfg("archery").get("name", "Стрелковая"))
	squad_size    = 20
	squad_cols    = 5
	# Точку выхода держит узел SpawnPoint у нарисованных дверей (см. Building)
	super._ready()

func train_archer() -> bool:
	return train_from_config("archer")
