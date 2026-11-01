extends Building
## СКЛАД (ТЗ 27.10.2026, п. 5) — уличный навес: крыша дома на четырёх столбах
## над помостом с грузом. Точка сдачи ресурсов наравне с крепостью
## (is_dropoff → GameManager.register_dropoff): рабочий несёт груз к
## БЛИЖАЙШЕЙ точке сдачи (GameManager.get_nearest_dropoff), и дерево, камень,
## золото и мясо, сданные здесь, сразу уходят в общую казну
## (ResourceManager.gather_resource — тот же путь, что у замка). Своего
## запаса у склада нет.
##
## Склад — НЕ крепость: гарнизона, найма, выпаса овец у него нет
## (Castle-ветки его не видят). Файл без class_name (preload/load).

const _UCfg := preload("res://scripts/unit_stats_config.gd")

func _ready() -> void:
	building_id  = "storehouse"
	sprite_path  = ""
	is_dropoff   = true
	max_health   = _UCfg.building_stat("storehouse", "max_hp", 1200.0)
	build_size   = _UCfg.building_size("storehouse", Vector3(2.6, 2.2, 2.6))
	display_name = String(_UCfg.building_cfg("storehouse").get("name", "Склад"))
	super._ready()

## СДАЧА С ЛЮБОЙ СТОРОНЫ: навес открыт на все четыре стороны, ворот у него
## нет — рабочий идёт к ближайшей к нему точке кромки, а не в обход к
## «двери» (Worker._dest_point спрашивает этот метод, если он есть).
## Точка — внутри круга сдачи Building.at_deposit (ring_radius + WALL_PAD)
func deposit_point_from(p: Vector3) -> Vector3:
	var c: Vector3 = ring_center()
	var d := Vector3(p.x - c.x, 0.0, p.z - c.z)
	if d.length_squared() < 0.01:
		return deposit_point()
	return c + d.normalized() * (ring_radius() + DEPOSIT_WALL_PAD * 0.5)
