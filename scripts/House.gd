extends Building
## ДОМ (House) — дешёвая жилая постройка, даёт пассивный прирост еды.
##
## Все параметры (запас жизни, габарит, цена, время стройки) берутся из
## unit_stats_config.BUILDINGS["house"] — правятся только там.
##
## Файл НАМЕРЕННО без class_name: подключается через preload/load, поэтому не
## зависит от global_script_class_cache.cfg (тот же приём, что у ConstructionSite).

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var _food_timer: float = 0.0

func _ready() -> void:
	building_id  = "house"
	sprite_path  = ""
	max_health   = _UCfg.building_stat("house", "max_hp", 180.0)
	build_size   = _UCfg.building_size("house", Vector3(2.6, 2.2, 2.6))
	display_name = String(_UCfg.building_cfg("house").get("name", "Дом"))
	super._ready()

func _build_visual() -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = build_size
	collider.shape = shape
	collider.position.y = build_size.y / 2.0
	add_child(collider)

	# Процедурный запасной вид: сруб + двускатная крыша. Если цветной спрайт
	# House2.png найден, Building._maybe_load_building_sprite() спрячет эти меши
	var walls := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(build_size.x, build_size.y * 0.65, build_size.z)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.62, 0.50, 0.34)
	wall_mat.roughness = 0.92
	box.material = wall_mat
	walls.mesh = box
	walls.position.y = build_size.y * 0.325
	add_child(walls)

	var roof := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = maxf(build_size.x, build_size.z) * 0.72
	cone.height = build_size.y * 0.5
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.48, 0.22, 0.16)
	roof_mat.roughness = 0.88
	cone.material = roof_mat
	roof.mesh = cone
	roof.position.y = build_size.y * 0.65 + build_size.y * 0.25
	add_child(roof)

	# Единый для всех построек маркер выделения (Cursor_04.png плашмя на земле)
	selection_ring = make_selection_marker()
	add_child(selection_ring)

# Дом капает еду по таймеру — покадровый тик нужен всегда
func _needs_tick() -> bool:
	return true

func _process(delta: float) -> void:
	super._process(delta)
	_food_timer += delta
	if _food_timer >= _UCfg.HOUSE_FOOD_INTERVAL:
		_food_timer = 0.0
		ResourceManager.gather_resource(faction, Constants.RESOURCE_FOOD, _UCfg.HOUSE_FOOD_INCOME)
