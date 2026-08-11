extends Node

const _BBUtil := preload("res://scripts/BillboardUtil.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var folder := "res://assets/environment/resources"
	var dir := DirAccess.open(folder)
	if dir == null:
		print("нет папки")
		get_tree().quit()
		return
	var names: Array = []
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".png"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()

	print("%-34s %10s %8s %10s %10s" % ["файл", "размер", "w/h", "по островам", "по квадрату"])
	for n in names:
		var nm: String = n
		if not (nm.begins_with("Gold") or nm.begins_with("Rock")):
			continue
		var path: String = folder.path_join(nm)
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var sz := tex.get_size()
		var islands: int = _BBUtil.frame_count(tex)
		var by_ratio: int = int(round(sz.x / maxf(sz.y, 1.0)))
		print("%-34s %5dx%-4d %8.3f %10d %10d"
			% [nm, int(sz.x), int(sz.y), sz.x / maxf(sz.y, 1.0), islands, by_ratio])
	print("=== PROBE DONE ===")
	get_tree().quit()
