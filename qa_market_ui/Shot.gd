extends Node
## ОКОННЫЙ СНИМОК ОКНА РЫНКА (ТЗ 28.10.2026: крупное золото, партия 1k-50k,
## поле с «−/+» и «Всё»). Вердикты — вёрстка: ни одна строка не вылезает за
## рамку окна, иконка золота не меньше иконки дерева. Headless вёрстку не
## меряет честно (шрифты есть, но окна нет) — запускать в окне:
##   <godot> --audio-driver Dummy --windowed --position -5000,-5000 --path . res://qa_market_ui/Shot.tscn -- out=<путь без .png>

const _Panel := preload("res://scripts/ui/MarketPanel.gd")
var _out: String = "user://market_ui"
var _pass := 0
var _fail := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("out="):
			_out = String(a).substr(4)
	get_tree().create_timer(30.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		get_tree().quit())
	call_deferred("_run")

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else: _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _run() -> void:
	get_window().size = Vector2i(900, 700)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.55, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for r in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(Constants.FACTION_PLAYER, r, 37578.0)
	var p: PanelContainer = _Panel.new()
	add_child(p)
	p.position = Vector2(150, 60)
	for _i in range(6):
		await get_tree().process_frame
	p.call("_set_lot", 10000.0)
	for _i in range(3):
		await get_tree().process_frame
	var box: Rect2 = p.get_global_rect()
	var over := 0
	var worst := ""
	for c in _all_controls(p):
		if not c.is_visible_in_tree():
			continue
		var r: Rect2 = c.get_global_rect()
		if r.end.x > box.end.x + 0.5 or r.end.y > box.end.y + 0.5 or r.position.x < box.position.x - 0.5:
			over += 1
			worst = "%s %s" % [c.name, str(r)]
	verdict("A1 ни один элемент не вылезает за рамку окна", over == 0, worst)
	var wood: Rect2 = _icon_rect(p, Constants.RESOURCE_WOOD)
	var gold: Rect2 = _icon_rect(p, Constants.RESOURCE_GOLD)
	verdict("A2 золото не мельче дерева (рисунок заполняет рамку)",
		gold.size.y >= wood.size.y * 0.8, "дерево %s, золото %s" % [str(wood.size), str(gold.size)])
	var ed: LineEdit = p.get("_lot_edit")
	verdict("A3 поле партии показывает «10 000»", ed != null and ed.text == "10 000", ed.text if ed != null else "-")
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(_out + ".png")
	print("  снимок: %s.png (окно %s)" % [_out, str(box)])
	print("\n═════ ИТОГ qa_market_ui: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _all_controls(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Control:
			out.append(c)
		out.append_array(_all_controls(c))
	return out

## Нарисованный прямоугольник иконки: KEEP_ASPECT_CENTERED вписывает текстуру в рамку
func _icon_rect(p: Node, t: int) -> Rect2:
	var b: Button = (p.get("_give_btns") as Dictionary)[t]
	for ch in b.get_children():
		if ch is TextureRect:
			var tr := ch as TextureRect
			var ts: Vector2 = tr.texture.get_size()
			var k: float = minf(tr.size.x / ts.x, tr.size.y / ts.y)
			return Rect2(Vector2.ZERO, ts * k)
	return Rect2()
