extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 10.10.2026: СКОРОСТЬ ШАГА, БЕГ СНЯТ, КАМЕРА, ПАНЕЛЬ A/C/S/F1,
## МУЛЬТИ-ВЫБОР И КАРТОЧКИ, TAB, ЗВУКИ, КУРСОР, СМЕХ ОРДЫ
## ═══════════════════════════════════════════════════════════════════════════
## A — скорость: шаг пехоты и монаха = бег × 0.85, рабочий и гоблин без
##     изменений, бег (абсолютный) прежний, отход в замок = бег × 1.3,
##     фаланга [S] = шаг × 0.8, темп ленты ходьбы вырос вместе с шагом.
## B — двойной ПКМ (настоящий ввод) больше не включает бег.
## C — камера: WASD не двигает, стрелки двигают.
## D — панель отряда: четыре кнопки A, C, S, F1 в этом порядке, жёлтая рамка
##     ровно у одной, подсказка «Вольно [C]», стойки Attack/Defend и «To Castle»
##     сняты, [F1] (клавиша) шлёт отряд в замок бегом.
## E — мульти-выбор: иконки родов без плашек, зазор 3 px, число = отряды,
##     четыре кнопки справа; Tab разворачивает род (карточки: флаг, HP, опыт,
##     число), повторный клик закрывает и возвращает всю армию.
## F — звук и курсор: щелчки вкладки кузницы, Tab, кнопок, закрытия панели
##     здания; низкий стерео-щелчок Attack-Move; курсор скрещённых мечей в [A];
##     смех орды выключен.
## Запуск: godot --headless --path . res://qa_tz1010/Test.tscn [-- only=abcdef]

const F := Constants.FACTION_PLAYER
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var main = null
var sm = null
var hud = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only := "abcdef"

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_tz1010: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _unit(uid: String, at: Vector3, f: int = F) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, at: Vector3, n: int, lvl: int = 0) -> int:
	var sid: int = GameManager.new_squad(F, uid)
	for i in range(n):
		GameManager.add_to_squad(sid, _unit(uid, at + Vector3(float(i % 5) * 0.8, 0.0, float(i / 5) * 0.8)))
	if lvl > 0:
		GameManager.squads[sid]["level"] = lvl
	return sid

func _men(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _select(sids: Array) -> void:
	var all: Array = []
	for s in sids:
		all.append_array(_men(int(s)))
	sm.select_units(all)
	await frames(3)

func _mouse(btn: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	get_tree().root.push_input(e, true)

func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	get_tree().root.push_input(e, true)

func _tap(code: Key) -> void:
	_key(code, true)
	await frames(1)
	_key(code, false)
	await frames(2)

func _freeze_cam(at: Vector3) -> void:
	main.set_process(false)
	main._camera.set_process(false)
	main._camera.pan_to(Vector3(at.x, 0.0, at.z))
	main._camera._update_position()
	await frames(2)

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("only="):
			_only = s.substr(5)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	sm = main.selection_manager
	hud = main.hud
	for k in ["enemy_ai", "goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard", "cav_commander"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n):
			n.set_process(false)
	for lair in GameManager.troll_lairs:
		if lair != null and is_instance_valid(lair):
			(lair as Node).process_mode = Node.PROCESS_MODE_DISABLED
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	if _only.contains("a"): await _block_a()
	if _only.contains("b"): await _block_b()
	if _only.contains("c"): await _block_c()
	if _only.contains("d"): await _block_d()
	if _only.contains("e"): await _block_e()
	if _only.contains("f"): await _block_f()
	_finish()

const AT := Vector3(-120.0, 0.0, 10.0)

# ═════════════════════════════════════════════════════════════════════════════
func _moving_speed(u: Unit, to: Vector3, run: bool = false) -> float:
	u.command_move(to, false, Vector3.ZERO, false, true, run)
	return u._effective_speed()

func _block_a() -> void:
	print("\n═════ A. СКОРОСТЬ ШАГА И БЕГА ═════")
	var run_k: float = _UCfg.RUN_SPEED_FACTOR
	var ok_walk := true
	var det := ""
	for uid in ["spearman", "archer", "warrior", "monk"]:
		var u := _unit(uid, AT + Vector3(0, 0, 0))
		var base: float = float(_UCfg.get_stats(uid).get("movement_speed", 1.0))
		var walk: float = _moving_speed(u, AT + Vector3(40, 0, 0))
		var want: float = base * run_k * _UCfg.WALK_FROM_RUN
		det += "%s %.2f→%.2f (ждём %.2f) " % [uid, base, walk, want]
		if absf(walk - want) > 0.02:
			ok_walk = false
		u.take_damage(1e12)
	verdict("A1 шаг копейщика, лучника, мечника, монаха = бег × 0.85", ok_walk, det)
	var wk := _unit("worker", AT)
	var wbase: float = wk.move_speed
	var wwalk: float = _moving_speed(wk, AT + Vector3(30, 0, 0))
	verdict("A2 скорость рабочего не изменилась (%.2f = %.2f)" % [wwalk, wbase], absf(wwalk - wbase) < 0.02)
	wk.take_damage(1e12)
	var gb := _unit("goblin_spearman", AT, Constants.FACTION_GOBLIN)
	verdict("A3 гоблину шаг не менялся (множитель %.2f)" % _UCfg.walk_boost("goblin_spearman"),
		_UCfg.walk_boost("goblin_spearman") == 1.0)
	gb.take_damage(1e12)
	# Бег — абсолютный прежний: прежний шаг × 1.35
	var sp := _unit("spearman", AT)
	var sbase: float = float(_UCfg.get_stats("spearman").get("movement_speed", 2.0))
	sp.command_move(AT + Vector3(40, 0, 0), false, Vector3.ZERO, false, true, true)
	var run_v: float = sp._effective_speed()
	verdict("A4 бег прежний: %.2f = прежний шаг × %.2f (%.2f)" % [run_v, run_k, sbase * run_k],
		absf(run_v - sbase * run_k) < 0.02)
	# Отход в замок: бег × 1.3
	sp.begin_retreat()
	sp.command_move(AT + Vector3(40, 0, 0), false, Vector3.ZERO, true, false, true)
	# Пока боец в зоне выхода из контакта (PASS_CLEAR_DIST), бег отложен по
	# замыслу (ТЗ 29.09); за ней он бежит — меряем бегущего в отходе
	sp._set_sprinting(true)
	var ret_v: float = sp._effective_speed()
	verdict("A5 отход в замок бегом +30 %%: %.2f = %.2f" % [ret_v, sbase * run_k * _UCfg.RETREAT_RUN_MULT],
		absf(ret_v - sbase * run_k * _UCfg.RETREAT_RUN_MULT) < 0.03)
	sp.end_retreat()
	# Фаланга: шаг × 0.8
	sp.set_stance(_UCfg.STANCE_DEFENSE)
	var ph_v: float = _moving_speed(sp, AT + Vector3(-30, 0, 0))
	var walk_sp: float = sbase * run_k * _UCfg.WALK_FROM_RUN
	verdict("A6 фаланга [S] на 20 %% медленнее шага: %.2f = %.2f" % [ph_v, walk_sp * 0.8], absf(ph_v - walk_sp * 0.8) < 0.02)
	sp.take_damage(1e12)
	# Темп ленты ходьбы вырос вместе с шагом (лучник — лента из SpriteFrames)
	var ar := _unit("archer", AT)
	await frames(3)
	var asp := ar._active_sprite as AnimatedSprite3D
	var wname := "walk"
	if asp != null and asp.sprite_frames != null and not asp.sprite_frames.has_animation("walk"):
		for an in asp.sprite_frames.get_animation_names():
			if String(an).begins_with("run"):
				wname = String(an)
				break
	# Таблица лент строится при первой привязке к общей отрисовке (в headless
	# её может не быть) — проверяем ту же функцию, которой она строится
	var tbl: Dictionary = Unit._sheet_table(asp.sprite_frames, _UCfg.walk_boost("archer")) if asp != null else {}
	var row: Variant = tbl.get(StringName(wname))
	print("    ленты лучника: %s, таблица: %s" % [str(asp.sprite_frames.get_animation_names() if asp != null and asp.sprite_frames != null else []), str(ar._look_table.keys())])
	var fps_w: float = float((row as Array)[2]) if row != null else -1.0
	var fps0: float = asp.sprite_frames.get_animation_speed(wname) if asp != null and asp.sprite_frames != null and asp.sprite_frames.has_animation(wname) else -1.0
	verdict("A7 темп ленты ходьбы лучника × %.3f (%.2f → %.2f к/с)" % [_UCfg.walk_boost("archer"), fps0, fps_w],
		fps0 > 0.0 and absf(fps_w - fps0 * _UCfg.walk_boost("archer")) < 0.05)
	ar.take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _block_b() -> void:
	print("\n═════ B. ДВОЙНОЙ ПКМ — БЕГА НЕТ ═════")
	var at := AT + Vector3(0, 0, 30)
	main._clear_area_of_resources(at, 40.0)
	var sid := _squad("spearman", at, 10)
	await pframes(4)
	await _select([sid])
	await _freeze_cam(at + Vector3(10, 0, 0))
	var scr: Vector2 = (sm.camera as Camera3D).unproject_position(at + Vector3(14, 0, 0))
	for _k in range(2):
		_mouse(MOUSE_BUTTON_RIGHT, true, scr)
		await frames(1)
		_mouse(MOUSE_BUTTON_RIGHT, false, scr)
		await frames(2)
	await pframes(2)
	var run_n := 0
	var moving := 0
	for u in _men(sid):
		if (u as Unit).sprinting:
			run_n += 1
		if (u as Unit).state == Unit.State.MOVING or (u as Unit).post_pos.distance_to(at) > 5.0:
			moving += 1
	verdict("B1 двойной ПКМ: отряд пошёл (%d из 10), бегущих нет (%d)" % [moving, run_n], moving >= 8 and run_n == 0)
	main.set_process(true)
	main._camera.set_process(true)
	for u2 in _men(sid):
		(u2 as Unit).take_damage(1e12)
	sm.clear_selection()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _block_c() -> void:
	print("\n═════ C. КАМЕРА — СТРЕЛКИ, НЕ WASD ═════")
	sm.clear_selection()
	var cam = main._camera
	cam.set_process(true)
	# Мышь headless стоит в углу экрана — край экрана вёз бы камеру сам
	cam.edge_pan_margin = -100000.0
	cam.jump_to(AT)
	await frames(3)
	var f0: Vector3 = cam._focus
	Input.parse_input_event(_ke(KEY_W, true))
	Input.parse_input_event(_ke(KEY_D, true))
	await frames(20)
	Input.parse_input_event(_ke(KEY_W, false))
	Input.parse_input_event(_ke(KEY_D, false))
	await frames(2)
	var f1: Vector3 = cam._focus
	Input.parse_input_event(_ke(KEY_UP, true))
	await frames(20)
	Input.parse_input_event(_ke(KEY_UP, false))
	await frames(2)
	var f2: Vector3 = cam._focus
	verdict("C1 W/D камеру не двигают (сдвиг %.2f м)" % f0.distance_to(f1), f0.distance_to(f1) < 0.05)
	verdict("C2 стрелка вверх двигает камеру (сдвиг %.2f м)" % f1.distance_to(f2), f1.distance_to(f2) > 0.5)

func _ke(code: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e

# ═════════════════════════════════════════════════════════════════════════════
func _active_keys(d: Dictionary) -> Array:
	var out: Array = []
	for k in d.keys():
		var b = d[k]
		if b != null and is_instance_valid(b) and bool((b as Button).get_meta("active", false)):
			out.append(String(k))
	return out

func _block_d() -> void:
	print("\n═════ D. ПАНЕЛЬ ОТРЯДА: A · C · S · F1 ═════")
	var at := AT + Vector3(0, 0, -30)
	var sid := _squad("spearman", at, 12)
	await pframes(3)
	await _select([sid])
	var bar = hud._squad_cmd_bar
	var order: Array = []
	for c in bar.get_children():
		order.append(String(c.name).replace("SquadCmdBtn_", ""))
	verdict("D1 четыре кнопки по порядку A, C, S, F1 (%s)" % str(order), order == ["A", "C", "S", "F1"] and bar.visible)
	verdict("D2 жёлтая рамка ровно у одной — «Вольно» (%s)" % str(_active_keys(hud._squad_cmd_btns)),
		_active_keys(hud._squad_cmd_btns) == ["C"])
	await _tap(KEY_A)
	verdict("D3 [A] взводит атаку по пути: рамка у A (%s), курсор мечи %s" % [str(_active_keys(hud._squad_cmd_btns)), str(sm.swords_cursor_on)],
		_active_keys(hud._squad_cmd_btns) == ["A"] and sm.attack_move_armed and sm.swords_cursor_on)
	await _tap(KEY_S)
	verdict("D4 [S] держать: рамка у S (%s), [A] снят, курсор обычный" % str(_active_keys(hud._squad_cmd_btns)),
		_active_keys(hud._squad_cmd_btns) == ["S"] and not sm.attack_move_armed and not sm.swords_cursor_on)
	await _tap(KEY_C)
	verdict("D5 [C] вольно: рамка у C (%s)" % str(_active_keys(hud._squad_cmd_btns)), _active_keys(hud._squad_cmd_btns) == ["C"])
	# Подсказка над кнопкой
	var cb = hud._squad_cmd_btns["C"]
	(cb as Control).mouse_entered.emit()
	await frames(1)
	var hint: String = hud.scmd_hint_text()
	(cb as Control).mouse_exited.emit()
	verdict("D6 подсказка над кнопкой «Вольно [C]» (%s)" % hint.get_slice("\n", 0), hint.begins_with("Вольно [C]"))
	# Стойки Attack/Defend и «To Castle» сняты из сетки кнопок
	var dup := 0
	for b in hud.button_container.get_children():
		var tt: String = String((b as Control).tooltip_text)
		if tt == "Attack" or tt == "Defend" or tt.begins_with("В замок") or tt == "To Castle":
			dup += 1
	verdict("D7 прежних кнопок стоек и «в замок» в сетке нет (%d)" % dup, dup == 0)
	# [F1] — в замок, бегом +30 %
	var castle: Castle = null
	for b2 in get_tree().get_nodes_in_group("player_buildings"):
		if b2 is Castle and (b2 as Castle).is_stronghold():
			castle = b2
			break
	if castle == null:
		# Крепость игрок ставит сам — стенд ставит её за него
		castle = Castle.new()
		castle.faction = F
		main.world_add(castle)
		var cp: Vector3 = at + Vector3(-30.0, 0.0, 0.0)
		main._clear_area_of_resources(cp, 12.0)
		castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
		await pframes(4)
	print("    крепость игрока: %s" % str(castle))
	await _tap(KEY_F1)
	await pframes(60 * 3)
	print("    после [F1]: to_castle=%s, в отходе %d, бегут %d" % [str(GameManager.squads[sid].get("to_castle", false)),
		_men(sid).filter(func(x): return (x as Unit).retreating).size(), _men(sid).filter(func(x): return (x as Unit).sprinting).size()])
	var runners := 0
	for u in _men(sid):
		if (u as Unit).retreating and (u as Unit).sprinting:
			runners += 1
	verdict("D8 [F1] — отряд бегом в крепость (бегут %d из 12), рамка у F1 (%s)" % [runners, str(_active_keys(hud._squad_cmd_btns))],
		castle != null and runners >= 1 and GameManager.squad_is_to_castle(sid) \
		and _active_keys(hud._squad_cmd_btns) == ["F1"])
	for u2 in _men(sid):
		(u2 as Unit).take_damage(1e12)
	sm.clear_selection()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _block_e() -> void:
	print("\n═════ E. МУЛЬТИ-ВЫБОР И КАРТОЧКИ ОТРЯДОВ ═════")
	var at := AT + Vector3(10, 0, 0)
	var sids: Array = []
	for i in range(3):
		sids.append(_squad("spearman", at + Vector3(i * 6.0, 0, 0), 10, i))
	for i2 in range(2):
		sids.append(_squad("archer", at + Vector3(i2 * 6.0, 0, 8), 8, 1))
	sids.append(_squad("warrior", at + Vector3(0, 0, 16), 6))
	await pframes(3)
	await _select(sids)
	var sep: int = hud._overbar_row.get_theme_constant("separation")
	var plates := 0
	for slot in hud._overbar_row.get_children():
		var btn: Button = (slot as Control).get_child(0) as Button
		var st := btn.get_theme_stylebox("normal") as StyleBoxFlat
		if st != null and st.bg_color.a > 0.05:
			plates += 1
	verdict("E1 полоса родов: 3 рода, зазор %d px, серых плашек %d, панель отряда скрыта" % [sep, plates],
		hud.type_slots() == 3 and sep == 3 and plates == 0 and hud._overbar.visible and not hud._bottom_panel.visible)
	var badge_ok: bool = false
	var sp_slot: Control = hud._overbar_row.get_child(0)
	for ch in (sp_slot.get_child(0) as Control).get_children():
		if ch is Label and (ch as Label).visible and (ch as Label).text == "3":
			badge_ok = true
	verdict("E2 на иконке рода — число отрядов (копейщики: 3)", badge_ok)
	var ob_keys: Array = []
	for c in hud._ob_cmd_bar.get_children():
		ob_keys.append(String(c.name).replace("SquadCmdBtn_", ""))
	verdict("E3 четыре кнопки приказа всей армии справа (%s)" % str(ob_keys), ob_keys == ["A", "C", "S", "F1"] and hud._ob_cmd_bar.visible)
	# Tab — разворот рода
	var ui0: int = AudioManager.ui_calls
	await _tap(KEY_TAB)
	var exp1: String = hud._expanded_type
	var cards: int = hud._squad_strip.get_child_count()
	verdict("E4 Tab разворачивает род «%s»: карточек %d, полоса родов видна, щелчок %s" % [exp1, cards, AudioManager.ui_last],
		exp1 != "" and cards >= 1 and hud._overbar.visible and hud.type_slots() == 3 and AudioManager.ui_calls > ui0)
	# Карточка: флаг (или место под него), кнопка с числом, HP, опыт
	var card: Control = hud._squad_strip.get_child(0)
	var names: Array = []
	for ch2 in card.get_children():
		names.append(String(ch2.name))
	var has_xp: bool = card.get_node_or_null("XpBar") != null
	# РАЗВОРОТ ТЗ 12.10.2026 (второе письмо): флага над карточкой нет (ранг —
	# «★N» в углу кнопки): кнопка → HP → опыт
	verdict("E5 карточка: иконка с числом → HP → опыт (%s)" % str(names), card.get_child_count() == 3 and has_xp)
	await _tap(KEY_TAB)
	var exp2: String = hud._expanded_type
	verdict("E6 второй Tab — следующий род (%s → %s)" % [exp1, exp2], exp2 != "" and exp2 != exp1)
	# Повторный клик по иконке развёрнутого рода — закрыть, вся армия снова
	hud._on_type_filter_pressed(exp2)
	await frames(3)
	verdict("E7 повторный клик закрывает панель: разворота нет, выделено отрядов %d из 6" % sm.selected_squad_ids().size(),
		hud._expanded_type == "" and sm.selected_squad_ids().size() == 6 and not hud._bottom_panel.visible)
	# Клик по карте (пустое выделение) закрывает
	await _tap(KEY_TAB)
	sm.clear_selection()
	await frames(3)
	verdict("E8 клик мимо (снятие выделения) закрывает детальную панель", hud._expanded_type == "" and hud._parent_sids.is_empty())
	for s in sids:
		for u in _men(int(s)):
			(u as Unit).take_damage(1e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _block_f() -> void:
	print("\n═════ F. ЗВУКИ, КУРСОР, СМЕХ ═════")
	var smithy := Smithy.new()
	smithy.faction = F
	main.world_add(smithy)
	smithy.global_position = Vector3(AT.x, 0.0, AT.z - 50.0)
	await pframes(4)
	sm.select_units([smithy])
	await frames(3)
	hud.forge_set_tab("archer")
	var l1: String = AudioManager.ui_last
	await _tap(KEY_TAB)
	var l2: String = AudioManager.ui_last
	verdict("F1 смена древа в кузнице и Tab — щелчок вкладки (%s, %s)" % [l1, l2], l1 == "menu_tab" and l2 == "menu_tab")
	sm.clear_selection()
	await frames(2)
	verdict("F2 закрытие панели здания — щелчок (%s)" % AudioManager.ui_last, AudioManager.ui_last == "menu_close")
	var st: AudioStream = AudioManager._stream(AudioManager.ATTACK_CLICK_ID)
	var wav := st as AudioStreamWAV
	var len_s: float = float(wav.data.size()) / 4.0 / float(wav.mix_rate) if wav != null else 0.0
	verdict("F3 щелчок Attack-Move низкий и объёмный: стерео %s, %.2f с" % [str(wav != null and wav.stereo), len_s],
		wav != null and wav.stereo and len_s > 0.1)
	var sid := _squad("spearman", AT + Vector3(0, 0, 40), 6)
	await pframes(2)
	await _select([sid])
	sm.set_attack_move_armed(true)
	var armed_snd: String = AudioManager.ui_last
	var cur_on: bool = sm.swords_cursor_on
	sm.order_at_world(AT + Vector3(30, 0, 40), true)
	verdict("F4 [A]: курсор мечи (%s), звук взвода и приказа «%s»/«%s», режим снят после приказа" % [str(cur_on), armed_snd, AudioManager.ui_last],
		cur_on and armed_snd == "order_attack_move" and AudioManager.ui_last == "order_attack_move" \
		and not sm.attack_move_armed and not sm.swords_cursor_on)
	verdict("F5 смех орды при убийствах выключен", not _GobCfg.LAUGH_ENABLED)
	for u in _men(sid):
		(u as Unit).take_damage(1e12)
	smithy.queue_free()
	await pframes(2)
