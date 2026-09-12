extends Node3D
## Подставной снаряд для проверки обхода сроком полёта
var despawned: bool = false
func _despawn() -> void:
	despawned = true
