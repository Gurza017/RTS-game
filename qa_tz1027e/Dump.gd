extends SceneTree
## Снимки курсоров (CursorArt) в PNG для глаз — ТЗ 27.10.2026, UI/UX:
## godot --headless --path . -s res://qa_tz1027e/Dump.gd -- out=<папка>
## Пишет sword.png, arrow.png, arrow_far.png (32×32) и их же ×8 (nearest).
const _CursorArt := preload("res://scripts/CursorArt.gd")

func _init() -> void:
	var out := "user://cursor_dump"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("out="):
			out = String(a).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	for pair in [["sword", _CursorArt.SWORD], ["arrow", _CursorArt.ARROW], ["arrow_far", _CursorArt.ARROW_FAR], ["arrows_x", _CursorArt.ARROWS_X], ["arrows_x_far", _CursorArt.ARROWS_X_FAR]]:
		var tex: ImageTexture = _CursorArt.texture(int(pair[1]))
		if tex == null:
			print("  нет картинки %s" % String(pair[0]))
			continue
		var img: Image = tex.get_image()
		img.save_png(out.path_join(String(pair[0]) + ".png"))
		var big: Image = img.duplicate()
		big.resize(256, 256, Image.INTERPOLATE_NEAREST)
		big.save_png(out.path_join(String(pair[0]) + "_x8.png"))
		print("  %s: %dx%d, горячая точка %s" % [String(pair[0]), img.get_width(), img.get_height(), str(_CursorArt.hotspot(int(pair[1])))])
	quit()
