extends Node

## ШПИОН НЕОБРАБОТАННОГО ВВОДА.
## Считает события мыши, которые ДОШЛИ до _unhandled_input, то есть НЕ были
## съедены интерфейсом. Тем же каналом ловит ввод SelectionManager, поэтому
## «шпион не увидел ПКМ» == «SelectionManager не выдал приказ».
var rmb_press: int = 0
var rmb_release: int = 0
var lmb_press: int = 0

func reset() -> void:
	rmb_press = 0
	rmb_release = 0
	lmb_press = 0

func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			rmb_press += 1
		else:
			rmb_release += 1
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		lmb_press += 1
