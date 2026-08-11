extends Node

## Замер ориентации спрайта стрелы: где наконечник, а где оперение.
## Стрела нарисована ГОРИЗОНТАЛЬНО (used_rect 43x12), значит смотрим
## толщину по СТОЛБЦАМ: у оперения она максимальна, у древка минимальна.

const PATH := "res://assets/factions/humans/units/archer/Arrow-Sheet.png"

func _ready() -> void:
	var tex := load(PATH) as Texture2D
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var r := img.get_used_rect()
	print("used_rect: ", r)
	var line := ""
	for x in range(r.position.x, r.position.x + r.size.x):
		var cnt := 0
		for y in range(r.position.y, r.position.y + r.size.y):
			if img.get_pixel(x, y).a > 0.05:
				cnt += 1
		line += "%d " % cnt
	print("толщина по столбцам (слева направо): ", line)
	# Суммарная площадь левой и правой трети
	var third: int = r.size.x / 3
	var left := 0
	var right := 0
	for x in range(r.position.x, r.position.x + third):
		for y in range(r.position.y, r.position.y + r.size.y):
			if img.get_pixel(x, y).a > 0.05:
				left += 1
	for x in range(r.position.x + r.size.x - third, r.position.x + r.size.x):
		for y in range(r.position.y, r.position.y + r.size.y):
			if img.get_pixel(x, y).a > 0.05:
				right += 1
	print("площадь левой трети=%d, правой трети=%d" % [left, right])
	print("→ оперение там, где площадь БОЛЬШЕ; наконечник — где меньше")
	get_tree().quit()
