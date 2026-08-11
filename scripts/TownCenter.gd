extends Building
class_name TownCenter

const _UCfg := preload("res://scripts/unit_stats_config.gd")

func _ready() -> void:
	building_id = "town_center"
	# Параметры — из единого конфига (BUILDINGS["town_center"])
	max_health = _UCfg.building_stat("town_center", "max_hp", 500.0)
	build_size = _UCfg.building_size("town_center", Vector3(4.0, 2.5, 4.0))
	is_dropoff = true
	# Подпись — тоже из конфига, как у остальных построек: раньше здесь висело
	# захардкоженное английское «Town Center», хотя BUILDINGS["town_center"]
	# задаёт имя «Городской центр»
	display_name = String(_UCfg.building_cfg("town_center").get("name", "Городской центр"))
	super._ready()

func train_worker() -> bool:
	return train_from_config("worker")
