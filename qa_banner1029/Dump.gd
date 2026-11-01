extends Node
## Выгрузка знамён орды и штандарта легенды в PNG для глаз (ТЗ 29.10.2026): -- --out=<файл.png>
const _BA := preload("res://scripts/BannerArt.gd")

func _ready() -> void:
	var out := "user://banners_1029.png"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
	var texs: Array = []
	for l in range(1, 7):
		texs.append(_BA.goblin_tongue_texture(l))
	for e in [0, 2, 3, 6]:
		texs.append(_BA.goblin_tongue_texture(7, false, e))
	texs.append(_BA.boss_texture())
	texs.append(_BA.goblin_tongue_texture(3, true))
	texs.append(_BA.elite_texture(1, 1))
	texs.append(_BA.elite_texture(4, 4))
	var w: int = _BA.W
	var h: int = _BA.H
	var cols := 8
	var rows: int = (texs.size() + cols - 1) / cols
	var sheet := Image.create_empty(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.42, 0.58, 0.30))
	for i in range(texs.size()):
		var img: Image = (texs[i] as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("  выгружено: ", out)
	get_tree().quit()
