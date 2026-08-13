extends Node

## ИКОНКА В КАРТОЧКЕ ЮНИТА — ТА ЖЕ, ЧТО НА КНОПКЕ.
## Жалоба: в тултипе серая заглушка, на кнопках Замка те же юниты с нормальными
## иконками. Проверяем ровно эту пару: что отдаёт путь карточки (_unit_card →
## _icon_texture) и что отдаёт путь кнопки (UNIT_ICONS → _icon_texture).
##
## Запуск: godot --headless --path . res://qa_icons/Card.tscn

var _fail := 0
var _checks := 0

func _ready() -> void:
	call_deferred("_run")

func ok(name: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fail += 1
	print("  [%s] %s%s" % ["OK " if cond else "НЕ ПРОШЛО", name,
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(4):
		await get_tree().process_frame
	var hud = main.hud
	ok("HUD построен", hud != null)
	if hud == null:
		get_tree().quit(1)
		return

	var placeholder = hud._placeholder_icon()
	print("\n───── ИКОНКА КАРТОЧКИ ПРОТИВ ИКОНКИ КНОПКИ ─────")
	for uid in ["worker", "spearman", "archer", "warrior", "monk"]:
		var card: Dictionary = hud._unit_card(uid, Constants.FACTION_PLAYER, {}, 0, null)
		var card_path: String = String(card.get("icon", ""))
		var btn_path: String = String(hud.UNIT_ICONS.get(uid, ""))
		var card_tex = hud._icon_texture(card_path)
		var btn_tex = hud._icon_texture(btn_path)
		var is_ph: bool = card_tex == placeholder
		print("  %-9s карточка=%s" % [uid, card_path])
		print("            кнопка  =%s" % btn_path)
		ok("%s: в карточке НЕ заглушка" % uid, card_tex != null and not is_ph,
			"заглушка" if is_ph else "иконка есть")
		ok("%s: карточка и кнопка дают одну картинку" % uid, card_tex == btn_tex,
			"совпали" if card_tex == btn_tex else "РАЗНЫЕ")

	print("\n=== ИКОНКИ КАРТОЧЕК: провалов: %d из %d ===" % [_fail, _checks])
	get_tree().quit(1 if _fail > 0 else 0)
