extends Node

const _BBUtil := preload("res://scripts/BillboardUtil.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for i in range(1, 5):
		var p := "res://assets/environment/menu ui/Cursor_0%d.png" % i
		if not ResourceLoader.exists(p):
			print("Cursor_0%d: НЕТ" % i)
			continue
		var tex := load(p) as Texture2D
		var sz := tex.get_size()
		print("Cursor_0%d: %dx%d  w/h=%.2f  кадров(островной)=%d"
			% [i, int(sz.x), int(sz.y), sz.x / maxf(sz.y, 1.0), _BBUtil.frame_count(tex)])
	print("=== CURSOR PROBE DONE ===")
	get_tree().quit()
