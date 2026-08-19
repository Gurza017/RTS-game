extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТАКТИЧЕСКАЯ ПАУЗА И АЛЕРТЫ ВЕТЕРАНСТВА
## ═══════════════════════════════════════════════════════════════════════════
##   A ПАУЗА   — мир стоит, интерфейс и ввод живут (process_mode по веткам)
##   B ПРИКАЗЫ — отданные на паузе не выполняются раньше времени и не теряются
##   C АЛЕРТЫ  — стек под плашкой рабочих: пусто/появился/клик/исчез
##   D ПЛАШКА  — на нуле бездельников иконка остаётся, но гаснет
##
## Пауза проверяется НЕ по флагу дерева, а по последствиям: боец не сдвинулся,
## а кнопка нажалась. Флаг мог бы стоять и при мёртвом интерфейсе — с этого всё
## и началось.

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## ОТРИСОВОЧНЫЕ кадры: на паузе физических не бывает вовсе, и ожидание
## physics_frame повисло бы навсегда
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n: out += " "
	return out

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(6)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await pframes(3)

	await _a_modes()
	await _b_orders()
	await _c_alerts()
	await _d_idle()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 60), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_PAUSE DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. РЕЖИМЫ ПАУЗЫ ПО ВЕТКАМ
# ═════════════════════════════════════════════════════════════════════════════
func _a_modes() -> void:
	print("\n═════ A. РЕЖИМЫ ═════")
	verdict("A1 Main работает на паузе (в нём призрак постройки и курсор)",
		main.process_mode == Node.PROCESS_MODE_ALWAYS)
	verdict("A2 интерфейс и ввод работают на паузе",
		main.hud.process_mode == Node.PROCESS_MODE_ALWAYS
			and main.selection_manager.process_mode == Node.PROCESS_MODE_ALWAYS
			and main._camera.process_mode == Node.PROCESS_MODE_ALWAYS,
		"hud=%d sm=%d cam=%d" % [main.hud.process_mode,
			main.selection_manager.process_mode, main._camera.process_mode])
	# ГЛАВНОЕ: мир под Main обязан остаться ПАУЗУЕМЫМ, иначе ALWAYS на Main
	# протёк бы вниз по дереву и игра не вставала бы вовсе
	verdict("A3 мир, ИИ и туман — паузуемые (ALWAYS не протёк вниз)",
		main._world.process_mode == Node.PROCESS_MODE_PAUSABLE
			and main.enemy_ai.process_mode == Node.PROCESS_MODE_PAUSABLE
			and (GameManager.fog as Node).process_mode == Node.PROCESS_MODE_PAUSABLE,
		"world=%d ai=%d fog=%d" % [main._world.process_mode,
			main.enemy_ai.process_mode, (GameManager.fog as Node).process_mode])

# ═════════════════════════════════════════════════════════════════════════════
# B. ПРИКАЗЫ НА ПАУЗЕ
# ═════════════════════════════════════════════════════════════════════════════
func _b_orders() -> void:
	print("\n═════ B. ПРИКАЗЫ НА ПАУЗЕ ═════")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(4):
		var u := Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(-300.0 + float(i) * 0.8, 0.0, 300.0)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(4)
	var u0: Unit = men[0]
	var start: Vector3 = u0.global_position

	main.hud.set_paused(true)
	verdict("B1 пауза взведена", get_tree().paused)
	# Приказ отдаём УЖЕ НА ПАУЗЕ
	for m in men:
		(m as Unit).command_move(Vector3(-260.0, 0.0, 300.0), false, Vector3.RIGHT)
	await frames(60)
	var moved_paused: float = u0.global_position.distance_to(start)
	verdict("B2 на паузе боец не сдвинулся, хотя приказ отдан",
		moved_paused < 0.05 and u0.move_target.x > -270.0,
		"сдвиг %.3f м, цель приказа x=%.1f" % [moved_paused, u0.move_target.x])

	# Интерфейс при этом ЖИВОЙ: панель перерисовывается и кнопки отвечают
	main.hud.show_selection(men)
	await frames(2)
	verdict("B3 панель юнита открывается на паузе",
		main.hud._bottom_panel != null and main.hud._bottom_panel.visible)

	main.hud.set_paused(false)
	await pframes(40)
	var moved_after: float = u0.global_position.distance_to(start)
	verdict("B4 после снятия паузы приказ вступил в силу сам",
		moved_after > 0.5, "прошёл %.2f м" % moved_after)
	for m in men:
		(m as Node).queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. СТЕК АЛЕРТОВ ВЕТЕРАНСТВА
# ═════════════════════════════════════════════════════════════════════════════
func _c_alerts() -> void:
	print("\n═════ C. АЛЕРТЫ ═════")
	var hud = main.hud
	hud._alert_sig = ""
	hud._refresh_alert_stack()
	verdict("C1 наград никто не ждёт — под плашкой ПУСТО, без заглушек",
		hud._alert_box != null and hud._alert_box.get_child_count() == 0,
		"иконок %d" % (hud._alert_box.get_child_count() if hud._alert_box != null else -1))

	# Три отряда с невыбранной наградой
	var sids: Array = []
	for k in range(3):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		for i in range(3):
			var u := Spearman.new()
			u.faction = Constants.FACTION_PLAYER
			main.world_add(u)
			# ВНУТРИ КАРТЫ, а не «где-нибудь подальше»: камера зажимает свой фокус
			# границами поля (RTSCamera._clamp_focus), и до отряда за краем она
			# доехать не может в принципе — проверка C5 мерила бы этот зажим,
			# а не наведение по клику
			u.global_position = Vector3(-40.0 + float(k) * 14.0 + float(i) * 0.8, 0.0, 20.0)
			GameManager.add_to_squad(sid, u)
		GameManager.squads[sid]["pending"] = 1
		GameManager.squads[sid]["level"] = 1
		sids.append(sid)
	await pframes(3)
	hud._refresh_alert_stack()
	await frames(2)
	verdict("C2 три отряда ждут награду — три иконки в стеке",
		hud._alert_box.get_child_count() == 3,
		"иконок %d" % hud._alert_box.get_child_count())
	verdict("C3 стек стоит ПОД плашкой бездельников",
		hud._alert_box.position.y > hud._idle_btn.position.y + hud._idle_btn.size.y - 1.0,
		"стек y=%.0f, плашка y=%.0f h=%.0f" % [hud._alert_box.position.y,
			hud._idle_btn.position.y, hud._idle_btn.size.y])

	# Подмигивание: у иконки заведён живой твин по прозрачности
	var first: Control = hud._alert_box.get_child(0)
	var tweens: int = first.get_tree().get_processed_tweens().size() if first != null else 0
	verdict("C4 иконка алерта подмигивает (твин заведён)",
		first != null and tweens > 0, "живых твинов в дереве: %d" % tweens)

	# ── КЛИК: КАМЕРА К ОТРЯДУ, ОТРЯД ВЫДЕЛЕН, ПАНЕЛЬ ОТКРЫТА ────────────────
	var target_sid: int = int(sids[1])
	var c: Vector3 = GameManager.squad_centroid(target_sid)
	(first.get_parent().get_child(1) as Button).emit_signal("pressed")
	await frames(3)
	var cam = main._camera
	verdict("C5 клик по алерту навёл камеру на отряд",
		Vector2(cam._focus.x - c.x, cam._focus.z - c.z).length() < 3.0,
		"фокус (%.1f, %.1f), отряд (%.1f, %.1f)" % [cam._focus.x, cam._focus.z, c.x, c.z])
	var sel: Array = main.selection_manager.selected_units
	var same := 0
	for u in sel:
		if is_instance_valid(u) and (u as Unit).squad_id == target_sid:
			same += 1
	verdict("C6 и выделил именно этот отряд",
		same > 0 and same == sel.size(), "выделено %d, из них наши %d" % [sel.size(), same])
	verdict("C7 панель отряда открыта с выбором награды",
		main.hud._bottom_panel.visible
			and main.hud.button_container.get_child_count() >= 3,
		"кнопок в панели %d" % main.hud.button_container.get_child_count())

	# ── ВЫБРАЛИ НАГРАДУ — АЛЕРТ ПРОПАЛ ─────────────────────────────────────
	GameManager.apply_veteran_choice(target_sid, 0)
	hud._refresh_alert_stack()
	await frames(2)
	verdict("C8 после выбора награды иконка ушла из стека",
		hud._alert_box.get_child_count() == 2,
		"иконок %d" % hud._alert_box.get_child_count())

	# ── ОТРЯД ВЫБИТ — АЛЕРТ ТОЖЕ ПРОПАЛ ────────────────────────────────────
	for m in GameManager.squad_members(int(sids[0])):
		(m as Unit)._die()
	await pframes(3)
	hud._refresh_alert_stack()
	await frames(2)
	verdict("C9 у выбитого отряда алерта нет",
		hud._alert_box.get_child_count() == 1,
		"иконок %d" % hud._alert_box.get_child_count())

	for s in sids:
		for m in GameManager.squad_members(int(s)):
			if is_instance_valid(m):
				(m as Node).queue_free()
	await pframes(3)
	hud._refresh_alert_stack()

# ═════════════════════════════════════════════════════════════════════════════
# D. ПЛАШКА БЕЗДЕЛЬНИКОВ НА НУЛЕ
# ═════════════════════════════════════════════════════════════════════════════
func _d_idle() -> void:
	print("\n═════ D. ПЛАШКА РАБОЧИХ ═════")
	var hud = main.hud
	hud._apply_idle_state(0)
	await frames(2)
	verdict("D1 бездельников нет — иконка на месте, но плашка притушена",
		hud._idle_btn.visible and hud._idle_btn.modulate.a < 1.0,
		"видима=%s, прозрачность %.2f" % [str(hud._idle_btn.visible),
			hud._idle_btn.modulate.a])
	hud._apply_idle_state(3)
	await frames(2)
	verdict("D2 появились бездельники — плашка в полную яркость",
		is_equal_approx(hud._idle_btn.modulate.a, 1.0),
		"прозрачность %.2f" % hud._idle_btn.modulate.a)
