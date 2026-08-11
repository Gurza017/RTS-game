extends Control
class_name QuietTooltipControl

## Control-версия QuietTooltipButton.gd — тот же приём, но для узлов, у
## которых уже есть своя карточка (_show_bonus_tip), а не Button. Смотри
## комментарий в QuietTooltipButton.gd.
func _make_custom_tooltip(_for_text: String) -> Object:
	return Control.new()
