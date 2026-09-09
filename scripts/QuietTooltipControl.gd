extends Control
class_name QuietTooltipControl

## Control-версия QuietTooltipButton.gd — тот же приём, но для узлов, у
## которых уже есть своя карточка (_show_bonus_tip), а не Button. Разбор,
## почему это _get_tooltip, а не _make_custom_tooltip, — там же.
func _get_tooltip(_at_position: Vector2) -> String:
	return ""
