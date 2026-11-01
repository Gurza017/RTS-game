extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_VICTORY — ТЗ 29.10.2026, п. 1: победа не останавливает партию.
## ═══════════════════════════════════════════════════════════════════════════
## Настоящий путь: у красного вырезаны бойцы и снесены постройки, у орды —
## постройки лагеря; Main._check_victory объявляет победу. Проверяется:
## V1 фаза VICTORY и флаг; V2 нет непрозрачного оверлея, дерево не на паузе;
## V3 баннер «ПОБЕДА!» и ровно три кнопки (Играть снова / Выход / Выход из
## игры); V4 баннер компактный и прижат к верху (≤ 22 % высоты экрана);
## V5 мир живёт (игровые часы идут, is_playing); V6 точка карты вне кнопок не
## числится интерфейсом (клик доходит до игры); V7 расстановка постройки
## доступна и возвращает фазу VICTORY; V8 повторная проверка не пересоздаёт
## баннер; V9 Escape открывает паузу, баннер остаётся.
## Окно: godot --audio-driver Dummy --windowed --position -5000,-5000 --path .
##   res://qa_victory/Test.tscn -- --out=<путь без .png> bg=1 — сохранит снимок.
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
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_victory: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _find(root: Node, nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)

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
	# ── Разгром красного и лагеря орды ──
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
		for gb in get_tree().get_nodes_in_group("goblin_buildings"):
			if is_instance_valid(gb) and main.counts_for_victory(gb) and not (gb as Building).is_dead():
				rest.append(gb)
		if rest.is_empty():
			break
		for b in rest:
			(b as Building).take_damage(1e9)
		await pframes(3)
	main._ai_castle_placed = true
	main._check_victory()
	await frames(3)
	verdict("V1 победа объявлена (фаза VICTORY)", main._phase == main.Phase.VICTORY and bool(main._victory_won),
		"фаза %d" % int(main._phase))
	verdict("V2 мир не затенён и не на паузе (оверлея нет)",
		hud._overlay == null and not get_tree().paused)
	var banner: Control = hud._victory_banner
	var title := _find(banner, "VictoryTitle") as Label
	var row := _find(banner, "VictoryButtons") as HBoxContainer
	var names: Array = []
	if row != null:
		for c in row.get_children():
			if c is Button:
				names.append((c as Button).text)
	verdict("V3 баннер «ПОБЕДА!» и три кнопки", banner != null and title != null and title.text == "ПОБЕДА!"
		and names == ["Играть снова", "Выход", "Выход из игры"], str(names))
	var vh: float = get_viewport().get_visible_rect().size.y
	var vw: float = get_viewport().get_visible_rect().size.x
	var box := _find(banner, "VictoryBox") as Control
	var r: Rect2 = box.get_global_rect() if box != null else Rect2()
	verdict("V4 баннер компактный, сверху по центру (высота ≤ 22 %%, центр ±5 %%)",
		box != null and r.size.y <= vh * 0.22 and r.position.y < vh * 0.15
			and absf(r.get_center().x - vw * 0.5) <= vw * 0.05,
		"rect %s, экран %.0f×%.0f" % [r, vw, vh])
	var t0: int = Unit.game_ms()
	await pframes(30)
	verdict("V5 мир живёт: игровые часы идут, партия «играется»",
		Unit.game_ms() > t0 and main.is_playing(), "%d → %d мс" % [t0, Unit.game_ms()])
	var map_pt := Vector2(vw * 0.5, vh * 0.6)
	verdict("V6 точка карты под баннером не интерфейс (клик доходит до игры)",
		not hud.point_over_ui(map_pt) and banner.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var id0: int = banner.get_instance_id()
	main._victory_timer = 999.0
	await frames(3)
	main._check_victory()
	await frames(2)
	verdict("V8 повторная проверка не пересоздаёт баннер",
		hud._victory_banner != null and hud._victory_banner.get_instance_id() == id0 and main._phase == main.Phase.VICTORY)
	main.enter_castle_placement(true)
	var placing: bool = main._phase == main.Phase.PLACING_CASTLE
	main._cancel_placement()
	verdict("V7 после победы можно ставить постройку, отмена возвращает VICTORY",
		placing and main._phase == main.Phase.VICTORY, "фаза %d" % int(main._phase))
	if _out != "":
		await frames(20)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out + ".png")
		print("  снимок %s.png" % _out)
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	hud._unhandled_input(ev)
	await frames(2)
	verdict("V9 Escape открывает паузу, баннер остаётся",
		hud._overlay != null and hud._victory_banner != null and is_instance_valid(hud._victory_banner))
	get_tree().paused = false
	_finish()
