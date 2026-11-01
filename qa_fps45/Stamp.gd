extends Node
## Часовой: пишет время входа в свой _process/_physics_process
var t_proc: int = 0
var t_phys: int = 0
func _process(_d: float) -> void:
	t_proc = Time.get_ticks_usec()
func _physics_process(_d: float) -> void:
	t_phys = Time.get_ticks_usec()
