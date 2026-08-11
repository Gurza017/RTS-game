extends Node3D
## Та же работа, что DummyBody с do_work=true, но БЕЗ CharacterBody3D/
## CollisionShape3D — никакой регистрации в PhysicsServer3D. Разница с
## DummyBody(do_work=true) = цена самого физ. тела.

var velocity: Vector3 = Vector3.ZERO
var _grid_pos: Vector3 = Vector3(1e9, 0.0, 1e9)
var _aggro_timer: float = 0.0
var _stance_defense: bool = false

func _physics_process(delta: float) -> void:
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
