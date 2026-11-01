extends Node
## Зонд qa_fps45/Dispatch — цена рассылки NOTIFICATION_PROCESS/PHYSICS_PROCESS
## узлам с включёнными флагами, но без методов _process/_physics_process
## (так устроены бойцы: флаги — признаки «тикает/рисуется»). Меряется между
## двумя часовыми (приоритет −10⁶ и +10⁶). Вердиктов нет.
## Запуск: godot --headless --path . res://qa_fps45/Dispatch.tscn [-- n=5000]

const _Empty := preload("res://qa_fps45/Empty.gd")
const _Stamp := preload("res://qa_fps45/Stamp.gd")
var nodes: Array = []
var a: Node
var b: Node

func _ready() -> void:
	var n := 5000
	for x in OS.get_cmdline_user_args():
		if String(x).begins_with("n="):
			n = int(String(x).substr(2))
	a = _Stamp.new(); a.process_priority = -1000000; a.process_physics_priority = -1000000
	b = _Stamp.new(); b.process_priority = 1000000; b.process_physics_priority = 1000000
	add_child(a)
	for i in range(n):
		var x := Node3D.new()
		x.set_script(_Empty)
		add_child(x)
		nodes.append(x)
	add_child(b)
	call_deferred("_run")

func _span(k: int = 300) -> Vector2:
	for _i in range(20):
		await get_tree().process_frame
	var sp := 0.0
	var sph := 0.0
	for _i in range(k):
		await get_tree().process_frame
		sp += float(b.t_proc - a.t_proc)
		sph += float(b.t_phys - a.t_phys)
	return Vector2(sp, sph) / float(k) / 1000.0

func _flags(p: bool, ph: bool) -> void:
	for x in nodes:
		(x as Node).set_process(p)
		(x as Node).set_physics_process(ph)

func _run() -> void:
	for r in range(3):
		_flags(false, false)
		var off: Vector2 = await _span()
		_flags(true, true)
		var on: Vector2 = await _span()
		print("  раунд %d: %d узлов — рассылка _process %.3f → %.3f мс, _physics %.3f → %.3f мс" % [
			r, nodes.size(), off.x, on.x, off.y, on.y])
	get_tree().quit()
