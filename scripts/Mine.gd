extends Building
class_name Mine

const _UCfg := preload("res://scripts/unit_stats_config.gd")

const MINE_INTERVAL := 5.0
const MINE_AMOUNT := 8.0

var _mine_timer: float = 0.0

func _ready() -> void:
	building_id  = "mine"
	sprite_path  = "res://assets/sprites/buildings/mine.png"
	# Запас жизни, габарит и подпись — из единого конфига (BUILDINGS["mine"])
	max_health   = _UCfg.building_stat("mine", "max_hp", 250.0)
	build_size   = _UCfg.building_size("mine", Vector3(3.0, 2.0, 3.0))
	display_name = String(_UCfg.building_cfg("mine").get("name", "Рудник"))
	super._ready()

func _build_visual() -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = build_size
	collider.shape = shape
	collider.position.y = build_size.y / 2.0
	add_child(collider)

	var base_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = build_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.32, 0.26)
	mat.roughness = 0.95
	box.material = mat
	base_mesh.mesh = box
	base_mesh.position.y = build_size.y / 2.0
	add_child(base_mesh)

	var gold_orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.42
	sphere.height = 0.84
	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(1.0, 0.82, 0.12)
	gold_mat.metallic = 0.85
	gold_mat.roughness = 0.15
	sphere.material = gold_mat
	gold_orb.mesh = sphere
	gold_orb.position = Vector3(0.0, build_size.y + 0.45, 0.0)
	add_child(gold_orb)

	# Единый для всех построек маркер выделения (Cursor_04.png плашмя на земле)
	selection_ring = make_selection_marker()
	add_child(selection_ring)

# Рудник добывает золото по таймеру — тикает всегда
func _needs_tick() -> bool:
	return true

func _process(delta: float) -> void:
	super._process(delta)
	_mine_timer += delta
	if _mine_timer >= MINE_INTERVAL:
		_mine_timer = 0.0
		ResourceManager.gather_resource(faction, Constants.RESOURCE_GOLD, MINE_AMOUNT)
