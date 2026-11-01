extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_RED_DEFEAT — ТЗ 30.10.2026 (скриншот 00:44): красный разбит, орда жива.
## ═══════════════════════════════════════════════════════════════════════════
## Настоящий путь: у красного вырезаны бойцы и снесены постройки, лагерь орды
## стоит — Main._check_victory открывает окно «Красный игрок разбит».
##   R1 окно: заголовок, иллюстрация, текст «игра продолжается», «Продолжить»;
##      пауза; фаза не VICTORY
##   R2 «Продолжить» — окно снято, пауза снята
##   R3 повторная проверка окно не открывает
##   R4 ручка red_defeat_modal=false — окна нет (прежнее поведение)
##   R5 лагерь орды снесён: «ПОБЕДА!» без подписи «Красный игрок уничтожен…»,
##      сообщение орды — уведомлением, без «Выберите место для постройки»
## Окно: godot --audio-driver Dummy --windowed --position -5000,-5000 --path .
##   res://qa_red_defeat/Test.tscn -- --out=<путь без .png> bg=1 — снимок окна.
const _Opt := preload("res://scripts/perf_config.gd")

var main: Node = null
var hud = null
var _pass := 0
var _fail := 0
var _done := false
var _out := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")
	get_tree().create_timer(240.0, true).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	get_tree().paused = false
	print("\n═════ ИТОГ qa_red_defeat: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _find(root: Node, nm: String) -> Node:
	if root == null or not is_instance_valid(root):
		return null
	return root.find_child(nm, true, false)

func _kill_red() -> void:
	var victims: Array = get_tree().get_nodes_in_group("enemy_units").duplicate()
	for lu in GameManager._live_units:
		if is_instance_valid(lu) and lu is Unit and int((lu as Unit).faction) == Constants.FACTION_ENEMY:
			victims.append(lu)
	for u in victims:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
			if (u as Unit).garrisoned:
				(u as Unit).garrisoned = false
			(u as Unit).take_damage(1e9)
	await pframes(3)
	for _i in range(6):
		var rest: Array = []
		for b in get_tree().get_nodes_in_group("enemy_buildings"):
			if is_instance_valid(b) and b is Building and not (b as Building).is_dead():
				rest.append(b)
		if rest.is_empty():
			break
		for b in rest:
			(b as Building).take_damage(1e9)
		await pframes(3)

func _kill_goblin_camp() -> void:
	for _i in range(6):
		var rest: Array = []
		for gb in get_tree().get_nodes_in_group("goblin_buildings"):
			if is_instance_valid(gb) and main.counts_for_victory(gb) and not (gb as Building).is_dead():
				rest.append(gb)
		if rest.is_empty():
			break
		for b in rest:
			(b as Building).take_damage(1e9)
		await pframes(3)

func _shot(suffix: String) -> void:
	if _out == "":
		return
	await frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

func _all_text(root: Node) -> String:
	var out := ""
	if root is Label:
		out += (root as Label).text + "\n"
	elif root is Button:
		out += (root as Button).text + "\n"
	for c in root.get_children():
		out += _all_text(c)
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	hud = main.hud
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	await pframes(10)
	var gob0: int = main._victory_buildings(Constants.building_group(Constants.FACTION_GOBLIN))
	print("  построек орды: %d" % gob0)
	main._red_had_buildings = true
	await _kill_red()
	main._ai_castle_placed = true
	main._check_victory()
	await frames(3)
	var ov: Node = _find(hud, "RedDefeatOverlay")
	var txt: String = _all_text(ov) if ov != null else ""
	verdict("R1 окно «Красный игрок разбит»: иллюстрация, «игра продолжается», «Продолжить»; пауза; не победа",
		ov != null and txt.find("Красный игрок разбит") >= 0 and txt.find("продолжается") >= 0
		and _find(ov, "RedDefeatArt") != null and _find(ov, "RedDefeatContinue") != null
		and get_tree().paused and not bool(main._victory_won) and gob0 > 0,
		"орда построек %d, пауза %s, текст: %s" % [gob0, str(get_tree().paused), txt.replace("\n", " | ")])
	await _shot("modal")
	var btn := _find(ov, "RedDefeatContinue") as Button
	if btn != null:
		btn.pressed.emit()
	await frames(3)
	verdict("R2 «Продолжить» снимает окно и паузу",
		_find(hud, "RedDefeatOverlay") == null and not get_tree().paused and not hud.red_defeat_open())
	main._check_victory()
	await frames(2)
	verdict("R3 повторная проверка окно не открывает", _find(hud, "RedDefeatOverlay") == null)
	main.red_defeat_shown = false
	_Opt.red_defeat_modal = false
	main._check_victory()
	await frames(2)
	verdict("R4 ручка red_defeat_modal=false: окна нет", _find(hud, "RedDefeatOverlay") == null)
	_Opt.red_defeat_modal = true
	main.red_defeat_shown = true
	await _kill_goblin_camp()
	if main.goblin_ai != null and main.goblin_ai.has_method("_defeat"):
		main.goblin_ai._defeat()
	main._check_victory()
	await frames(3)
	var vb: Node = _find(hud, "VictoryBanner")
	var vtxt: String = _all_text(vb) if vb != null else ""
	var notice: Node = _find(hud, "Notice")
	var hint: Node = _find(hud, "PlacementHint")
	verdict("R5 «ПОБЕДА!» без подписи о красном; сообщение орды — уведомлением, без подсказки постройки",
		vb != null and vtxt.find("ПОБЕДА!") >= 0 and vtxt.find("Красный игрок") < 0
		and notice != null and (notice as Label).text.find("Лагерь орды") >= 0
		and (notice as Label).text.find("Выберите место") < 0 and hint == null,
		"баннер: %s | уведомление: %s" % [vtxt.replace("\n", " | "),
			(notice as Label).text if notice != null else "нет"])
	await _shot("victory")
	_finish()
