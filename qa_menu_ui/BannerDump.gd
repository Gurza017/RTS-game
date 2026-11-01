extends Node
## Выгрузка знамён игры по одному PNG для заставки меню (tools/make_menu_art.py):
## -- --dir=<папка>. Картинки — те же BannerArt, что над отрядами в партии:
## вымпелы рангов игрока 1-9, легенда, штандарт элиты, знамёна орды 1-6 и
## рваный штандарт легенды орды
const _BA := preload("res://scripts/BannerArt.gd")

func _ready() -> void:
	var dir := "res://tools/menu_banners"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--dir="):
			dir = String(a).substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var out: Dictionary = {}
	# Шкала ТЗ 30.10.2026: 9 ступеней на синем вымпеле (лычки белые 1-3,
	# красные 4-6, золотые 7-9), легенда — 10-я
	for l in range(1, 10):
		out["human_%d" % l] = _BA.texture_for(l)
	out["human_legend"] = _BA.legend_texture(0)
	out["human_elite"] = _BA.elite_texture(2, 3)
	for l in range(1, 7):
		out["goblin_%d" % l] = _BA.goblin_tongue_texture(l)
	out["goblin_legend"] = _BA.goblin_tongue_texture(7, false, 2)
	for k in out.keys():
		var t: Texture2D = out[k]
		if t == null:
			print("  нет текстуры: ", k)
			continue
		var img: Image = t.get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.save_png(dir.path_join(String(k) + ".png"))
	print("  выгружено знамён: ", out.size(), " в ", dir)
	get_tree().quit()
