extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_vet_ui2 — ВЕТЕРАНСТВО ИЗ ГАРНИЗОНА, ЭКВАЛАЙЗЕР, ПРЕДПРОСМОТР, ПЕРКИ
## (ТЗ 19.09.2026, блок 4)
## ═══════════════════════════════════════════════════════════════════════════
##   A — отряд лучников в башне заслужил ранг: выделение башни показывает
##       карточки награды и таблицу статов; клик по карточке применяет награду
##       (pending −1) и панель пересобирается; клик по значку алерта выделяет
##       башню (укрытых бойцов выделить нельзя).
##   B — эквалайзер: у каждой строки статов — полоска (Bar_<key>) с отрезками
##       база / кузница / ветеранство; после исследования кузницы у полоски
##       появляется зелёный отрезок, после награды — фиолетовый; минус
##       карточки — красным.
##   C — предпросмотр: наведение на карточку вытягивает полоску (preview > 0)
##       и подсвечивает минус (preview < 0 у стата с минусом); уход курсора
##       возвращает 0.
##   D — ряд перков: выбранные награды с фиолетовым маркером (VetMark),
##       изученные узлы кузницы (Forge_<id>) с плашкой-описанием по наведению.
## Запуск: godot --headless --path . res://qa_vet_ui2/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const F := Constants.FACTION_PLAYER

var main = null
var hud = null
var sm = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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

func _finish() -> void:
	print("\n═════ ИТОГ qa_vet_ui2: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _find_deep(root: Node, nm: String) -> Node:
	if root == null:
		return null
	if root.name == nm:
		return root
	for c in root.get_children():
		var r := _find_deep(c, nm)
		if r != null:
			return r
	return null

func _find_prefix(root: Node, prefix: String, out: Array) -> void:
	if root == null:
		return
	if String(root.name).begins_with(prefix):
		out.append(root)
	for c in root.get_children():
		_find_prefix(c, prefix, out)

func _squad(kind: String, at: Vector3, n: int, level: int, pending: int) -> Array:
	var sid: int = GameManager.new_squad(F, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
		u.faction = F
		main.world_add(u)
		var p := at + Vector3(float(i % 5) * 0.8, 0.0, float(i / 5) * 0.8)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	(GameManager.squads[sid] as Dictionary)["level"] = level
	(GameManager.squads[sid] as Dictionary)["pending"] = pending
	return [sid, men]

func _vet_buttons() -> Array:
	var out: Array = []
	for b in hud.button_container.get_children():
		if b is Button and not String((b as Button).name).begins_with("VetAlert_") \
				and absf((b as Button).custom_minimum_size.x - float(hud.BTN_SIZE) * hud.VET_BTN_SCALE) < 0.01:
			out.append(b)
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	hud = main.hud
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for k in ["goblin_ai", "gnoll_ai", "goblin_reserve", "enemy_guard"]:
		var n = main.get(k)
		if n != null and is_instance_valid(n) and n is Node:
			(n as Node).set_process(false)
	GameManager.world_bounds_enabled = false
	GameManager.pop_limit_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	var cam0 = main.get("_camera")
	if cam0 != null:
		cam0.edge_pan_margin = -1.0
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	var base := Vector3(-60.0, 0.0, 55.0)
	main._clear_area_of_resources(base, 40.0)

	print("\n═════ A. НАГРАДА ОТРЯДУ В БАШНЕ ═════")
	var tower: Building = load("res://scripts/Tower.gd").new()
	tower.faction = F
	main.world_add(tower)
	tower.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z)
	await pframes(4)
	var ar: Array = _squad("archer", base + Vector3(0, 0, 8), 10, 1, 1)
	await pframes(3)
	var sat: bool = (tower as Castle).garrison_now(int(ar[0]))
	await pframes(3)
	verdict("A0 лучники сели в башню, у отряда невыбранная награда", sat and GameManager.squad_pending(int(ar[0])) == 1)
	sm._clear_selection()
	sm._select(tower)
	GameManager.on_selection_changed(sm.selected_units, true)
	await frames(4)
	var btns: Array = _vet_buttons()
	verdict("A1 панель башни показывает карточки награды (%d)" % btns.size(), btns.size() >= 3 and int(hud.garrison_vet_menus) >= 1,
		"карточек %d, меню %d" % [btns.size(), int(hud.garrison_vet_menus)])
	verdict("A2 таблица статов отряда на крыше собрана", hud._stat_panel != null and is_instance_valid(hud._stat_panel)
		and hud._stat_rows.has("attack"))
	var rank_row_ok: bool = hud._vet_rank_row != null and is_instance_valid(hud._vet_rank_row) and hud._vet_rank_row.visible
	verdict("A3 флажки ранга показаны", rank_row_ok)
	# Клик по карточке — награда применена, панель здания пересобрана
	if not btns.is_empty():
		(btns[0] as Button).pressed.emit()
	await frames(4)
	verdict("A4 клик по карточке применил награду отряду в башне (pending 0, выбрано 1)",
		GameManager.squad_pending(int(ar[0])) == 0 and GameManager.squad_chosen(int(ar[0])).size() == 1
		and _vet_buttons().is_empty(),
		"pending %d, выбрано %d, карточек %d" % [GameManager.squad_pending(int(ar[0])),
			GameManager.squad_chosen(int(ar[0])).size(), _vet_buttons().size()])
	# Алерт: ещё одна награда → значок; клик по нему выделяет БАШНЮ
	(GameManager.squads[int(ar[0])] as Dictionary)["level"] = 2
	(GameManager.squads[int(ar[0])] as Dictionary)["pending"] = 1
	sm._clear_selection()
	GameManager.on_selection_changed(sm.selected_units, true)
	hud._alert_sig = ""
	hud._refresh_alert_stack()
	await frames(3)
	var alert: Node = _find_deep(hud, "VetAlert_%d" % int(ar[0]))
	verdict("A5 значок заслуженного ранга есть у отряда в башне", alert != null)
	if alert != null:
		hud._on_alert_pressed(int(ar[0]))
		await frames(4)
	var sel_tower: bool = sm.selected_units.size() == 1 and sm.selected_units[0] == tower
	verdict("A6 клик по значку выделяет башню и открывает карточки", sel_tower and _vet_buttons().size() >= 3,
		"выделено %s, карточек %d" % [str(sm.selected_units), _vet_buttons().size()])
	sm._clear_selection()
	GameManager.on_selection_changed(sm.selected_units, true)
	await frames(2)

	print("\n═════ B. ЭКВАЛАЙЗЕР ═════")
	var sp: Array = _squad("spearman", base + Vector3(20.0, 0.0, 0.0), 6, 1, 1)
	await pframes(3)
	sm._clear_selection()
	for m in sp[1]:
		sm._select(m)
	GameManager.on_selection_changed(sm.selected_units, true)
	await frames(4)
	var bars: Array = []
	_find_prefix(hud._stat_panel, "Bar_", bars)
	verdict("B1 у каждой строки статов — полоска эквалайзера", bars.size() >= 6 and bars.size() == hud._stat_rows.size(),
		"полосок %d, строк %d" % [bars.size(), hud._stat_rows.size()])
	var bar_atk = hud._stat_bars.get("attack")
	verdict("B2 полоска атаки: база жёлтая (> 0), кузницы и ветеранства нет (0)",
		bar_atk != null and float(bar_atk.base) > 0.0 and is_zero_approx(float(bar_atk.forge)) and is_zero_approx(float(bar_atk.vet)),
		"база %.1f кузн %.1f вет %.1f" % [float(bar_atk.base), float(bar_atk.forge), float(bar_atk.vet)] if bar_atk != null else "нет")
	# Кузница: узел копейщика с прибавкой атаки
	var atk_node := ""
	for cell in _Forge.cells():
		var nid: String = _Forge.node_id("spearman", String(cell))
		var v: Dictionary = _Forge.node_view(nid)
		if float((v.get("stat_bonus", {}) as Dictionary).get("attack", 0.0)) > 0.0 and v.get("prerequisites", []).is_empty():
			atk_node = nid
			break
	if atk_node == "":
		for cell in _Forge.cells():
			var nid2: String = _Forge.node_id("spearman", String(cell))
			var v2: Dictionary = _Forge.node_view(nid2)
			if float((v2.get("stat_bonus", {}) as Dictionary).get("attack", 0.0)) > 0.0:
				atk_node = nid2
				break
	GameManager.finish_research(F, atk_node)
	GameManager.on_selection_changed(sm.selected_units, true)
	await frames(4)
	bar_atk = hud._stat_bars.get("attack")
	verdict("B3 после исследования «%s» у полоски атаки зелёный отрезок кузницы" % atk_node,
		bar_atk != null and float(bar_atk.forge) > 0.0, "кузн %.1f" % (float(bar_atk.forge) if bar_atk != null else -1.0))
	# Награда: карточка с плюсом к атаке (attack) и минусом к чему-то
	var choices: Array = _UCfg.veteran_choices("spearman", 1)
	var idx := -1
	var neg_key := ""
	for i in range(choices.size()):
		var c: Dictionary = choices[i]
		if float(c.get("bonus_attack", 0.0)) > 0.0:
			idx = i
			for k in _UCfg.nonzero_modifiers(c):
				if float(c[k]) < 0.0:
					neg_key = _UCfg.modifier_stat_name(String(k))
			break
	verdict("B4 в конфиге есть карточка «атака» с минусом к другому стату", idx >= 0 and neg_key != "", "минус: %s" % neg_key)

	print("\n═════ C. ПРЕДПРОСМОТР НА ПОЛОСКЕ ═════")
	var vbtns: Array = _vet_buttons()
	if idx >= 0 and idx < vbtns.size():
		(vbtns[idx] as Button).mouse_entered.emit()
		await frames(2)
		var b_atk = hud._stat_bars.get("attack")
		var b_neg = hud._stat_bars.get(neg_key)
		verdict("C1 наведение: полоска атаки вытянулась (preview > 0)", b_atk != null and float(b_atk.preview) > 0.0,
			"preview %.2f" % (float(b_atk.preview) if b_atk != null else 0.0))
		verdict("C2 наведение: у стата с минусом полоска подсвечена красным (preview < 0)",
			b_neg != null and float(b_neg.preview) < 0.0, "preview %s %.2f" % [neg_key, float(b_neg.preview) if b_neg != null else 0.0])
		(vbtns[idx] as Button).mouse_exited.emit()
		await frames(2)
		verdict("C3 курсор ушёл — предпросмотр снят (0)", b_atk != null and is_zero_approx(float(b_atk.preview))
			and (b_neg == null or is_zero_approx(float(b_neg.preview))))
		(vbtns[idx] as Button).pressed.emit()
		await frames(4)
		var b_atk2 = hud._stat_bars.get("attack")
		var b_neg2 = hud._stat_bars.get(neg_key)
		verdict("C4 после выбора: фиолетовый отрезок ветеранства у атаки, минус — красным",
			b_atk2 != null and float(b_atk2.vet) > 0.0 and b_neg2 != null and float(b_neg2.negative_total()) > 0.0,
			"вет атаки %.1f, минус %s %.1f" % [float(b_atk2.vet) if b_atk2 != null else 0.0, neg_key,
				float(b_neg2.negative_total()) if b_neg2 != null else 0.0])
	else:
		verdict("C0 карточки наград на панели", false, "кнопок %d, idx %d" % [vbtns.size(), idx])

	print("\n═════ D. РЯД ПЕРКОВ ═════")
	var row: Node = _find_deep(hud._stat_panel, "BonusRow")
	verdict("D1 ряд перков есть", row != null)
	if row != null:
		var vet_holders: Array = []
		var forge_holders: Array = []
		for c in row.get_children():
			if String(c.name).begins_with("Bonus_"):
				vet_holders.append(c)
			elif String(c.name).begins_with("Forge_"):
				forge_holders.append(c)
		verdict("D2 выбранная награда — с фиолетовым маркером VetMark", vet_holders.size() == 1
			and (vet_holders[0] as Node).get_node_or_null("VetMark") != null and (vet_holders[0] as Node).get_node_or_null("PerkFrame") != null,
			"наград %d" % vet_holders.size())
		# ── РАЗВОРОТ (ТЗ 20.09.2026, п. 6.1) ──────────────────────────────
		# Заказ: «полностью убрать улучшения из Кузницы, оставить ТОЛЬКО
		# улучшения ветеранства». Прежние D3-D5 утверждали ровно снятое
		# требование (узел кузницы в ряду и плашка по наведению на него);
		# теперь проверяется обратное свойство — их там нет ни одного
		verdict("D3 узлов кузницы в ряду перков НЕТ (ТЗ 20.09.2026)",
			forge_holders.is_empty() and not HUD.BONUS_ROW_SHOWS_FORGE,
			"узлов %d, ручка %s" % [forge_holders.size(), str(HUD.BONUS_ROW_SHOWS_FORGE)])
		verdict("D4 ряд перков не пуст: награда ветеранства осталась",
			vet_holders.size() >= 1, "наград %d" % vet_holders.size())
	_finish()

func _all_labels(root: Node) -> Array:
	var out: Array = []
	if root is Label:
		out.append(root)
	for c in root.get_children():
		out += _all_labels(c)
	return out
