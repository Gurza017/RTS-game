extends Building
class_name Barracks

const _UCfg := preload("res://scripts/unit_stats_config.gd")

func _ready() -> void:
	building_id  = "barracks"
	sprite_path   = "res://assets/sprites/buildings/barracks.png"
	# Запас жизни, габарит и подпись — из единого конфига (BUILDINGS["barracks"])
	max_health    = _UCfg.building_stat("barracks", "max_hp", 300.0)
	build_size    = _UCfg.building_size("barracks", Vector3(3.5, 2.2, 3.5))
	display_name  = String(_UCfg.building_cfg("barracks").get("name", "Бараки"))
	squad_size    = 20
	squad_cols    = 5
	squad_spacing = 0.35
	spawn_offset  = Vector3(0.0, 0.0, 6.0)
	super._ready()

# Цена, время и размер отряда — из конфига (TRAINING["barracks"])
func train_spearman() -> bool:
	return train_from_config("spearman")

func train_archer() -> bool:
	return train_from_config("archer")
