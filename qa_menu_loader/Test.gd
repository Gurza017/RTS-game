extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: КУРСОР В МЕНЮ И ИГРОВОЙ ЭКРАН ЗАГРУЗКИ (спринт 17, второе письмо)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: «первый клик по Старту только меняет системный курсор на игровой,
## второй — запускает; на время загрузки ОС показывает синий кружок».
##   A — игровой курсор ставится уже в меню (UIAssets.cursor_installed после
##       _ready меню), курсор видим;
##   B — экран загрузки: слой LoadingLayer на КОРНЕ дерева (переживает смену
##       сцены) с фоном, полосой и надписью этапа, поверх всего (layer 100),
##       счётчик loader_shown;
##   C — полоса растёт с этапом.
## РАЗВОРОТ ТЗ 21.10.2026: кольцо-спиннер снято, вместо него арт и полоса с
## процентами (scripts/ui/LoadingScreen.gd); подробно — qa_menu_ui, блок C.
## Сам щелчок по «Старт» и системный курсор в headless не проверить — курсор
## живёт в окне; здесь стережётся контракт, из которого следует первый клик.
## Запуск: godot --headless --path . res://qa_menu_loader/Test.tscn

const _UIAssets := preload("res://scripts/UIAssets.gd")
const _Loading := preload("res://scripts/ui/LoadingScreen.gd")

var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(60.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 60 с")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_menu_loader: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _run() -> void:
	print("\n═════ A. КУРСОР СТАВИТСЯ В МЕНЮ ═════")
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	verdict("A1 игровой курсор установлен уже в меню", bool(_UIAssets.cursor_installed))
	verdict("A2 курсор видим (не спрятан до старта)", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"mouse_mode=%d" % Input.mouse_mode)
	verdict("A3 у меню есть метод показа экрана загрузки", menu.has_method("_show_loader"))

	print("\n═════ B. ЭКРАН ЗАГРУЗКИ ═════")
	var before: int = int(menu.loader_shown)
	menu._show_loader()
	await get_tree().process_frame
	var layer: Node = get_tree().root.get_node_or_null("LoadingLayer")
	verdict("B1 слой загрузки появился (на корне дерева)", layer != null and layer is CanvasLayer)
	if layer == null:
		_finish()
		return
	verdict("B2 слой поверх всего интерфейса", (layer as CanvasLayer).layer >= 100,
		"layer=%d" % (layer as CanvasLayer).layer)
	var back: Node = layer.find_child("LoadingBack", true, false)
	var bar: Node = layer.find_child("LoadingBar", true, false)
	var lbl: Node = layer.find_child("LoadingLabel", true, false)
	verdict("B3 фон, полоса и надпись этапа на месте, кольца нет", back is ColorRect
		and bar is Control and lbl is Label
		and layer.find_child("LoadingSpinner", true, false) == null)
	verdict("B4 фон непрозрачный (меню под ним не видно)",
		back != null and (back as ColorRect).color.a >= 0.9,
		"альфа %.2f" % ((back as ColorRect).color.a if back != null else 0.0))
	verdict("B5 надпись этапа по-русски", lbl != null and String((lbl as Label).text).length() > 3,
		"«%s»" % (String((lbl as Label).text) if lbl != null else ""))
	verdict("B6 счётчик показов вырос на один", int(menu.loader_shown) == before + 1)

	print("\n═════ C. ПОЛОСА ДВИЖЕТСЯ ═════")
	var t0: float = float(layer.call("progress"))
	_Loading.stage("Генерация рельефа…", 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	var t1: float = float(layer.call("progress"))
	verdict("C1 доля полосы растёт с этапом", t1 > t0, "%.3f → %.3f" % [t0, t1])
	verdict("C2 полоса рисуется кодом (есть _draw), картинки не требует", bar.has_method("_draw"))
	_Loading.finish()
	menu.queue_free()
	for _i in range(120):
		await get_tree().process_frame
	_finish()
