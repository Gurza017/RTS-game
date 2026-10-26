extends Node
## Выгрузка штандартов элиты в PNG для глаз (ТЗ 22.10.2026): -- --out=<файл.png>
const _BA := preload("res://scripts/BannerArt.gd")

func _ready() -> void:
	var out := "user://elite_banners.png"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
	var cases := [[0, 2, false], [1, 0, true], [1, 2, true], [2, 3, true], [2, 5, true], [3, 7, true], [0, 5, false]]
	var w: int = _BA.W
	var h: int = _BA.H
	var sheet := Image.create_empty(w * cases.size(), h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.30, 0.55, 0.25))
	for i in range(cases.size()):
		var c: Array = cases[i]
		var tex: Texture2D = _BA.elite_texture(int(c[0]), int(c[1])) if bool(c[2]) else _BA.texture_for(int(c[1]))
		var img: Image = tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("  выгружено: ", out)
	get_tree().quit()
