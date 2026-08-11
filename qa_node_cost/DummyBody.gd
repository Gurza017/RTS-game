extends CharacterBody3D
## Стадия 0 диагностики (см. план): изолирует цену PhysicsServer3D (наличие
## CharacterBody3D+CollisionShape3D в дереве) от цены GDScript-логики внутри
## _physics_process. do_work=false — пустой callback, do_work=true — тот же
## объём работы, что IDLE-ветка Unit._physics_process (без спрайтов/боя).

var do_work: bool = false

var _grid_pos: Vector3 = Vector3(1e9, 0.0, 1e9)
var _aggro_timer: float = 0.0
var _stance_defense: bool = false

func _physics_process(delta: float) -> void:
	if not do_work:
		return
	var gdx: float = global_position.x - _grid_pos.x
	var gdz: float = global_position.z - _grid_pos.z
	if gdx * gdx + gdz * gdz > 0.04:
		_grid_pos = global_position
	if _stance_defense:
		return
	velocity = Vector3.ZERO
	_aggro_timer -= delta
	if _aggro_timer <= 0.0:
		_aggro_timer = 0.5
