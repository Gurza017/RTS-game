extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПАНЕЛЬ ВЕТЕРАНСТВА ПОСЛЕ РЕДИЗАЙНА (7 ПУНКТОВ ЗАКАЗА)
## ═══════════════════════════════════════════════════════════════════════════
##   A ЗНАЧОК РАНГА — лычки вместо звезды, длинной подписи нет, клик ведёт
##                    камеру и зажигает подсветку
##   B ОДНА ЛЕВАЯ ОСЬ — панель статов и нижняя панель стоят по одной вертикали
##   C НАГРАДЫ СПРАВА — иконки уже выбранных бонусов переехали в таблицу статов
##   D КНОПКИ ВЫБОРА — крупнее на 40%, рамка квадратная и тонкая
##   E ФЛАЖКИ РАНГА — вместо строки «★ Ветеран N — выберите награду»
##   F ПРЕДПРОСМОТР — наведение дописывает будущие числа в таблицу статов
##   G ПЛАШКА — компактная, справа от панели, только иконка и статы из конфига
##
## ЧИСЛА НЕ ХАРДКОДЯТСЯ. Всё, что стенд сверяет, читается из тех же источников,
## что и сам интерфейс: размеры — из констант HUD, значения наград — из
## unit_stats_config. Иначе стенд краснел бы на каждой правке баланса.
##
## Запуск: godot --headless --path . res://qa_vetui/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var hud = null
var sm = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o

func _find_deep(root: Node, nm: String) -> Node:
	if root.name == nm:
		return root
	for c in root.get_children():
		var r := _find_deep(c, nm)
		if r != null:
			return r
	return null

func _labels_of(root: Node) -> Array:
	var out: Array = []
	if root is Label:
		out.append(root)
	for c in root.get_children():
		out += _labels_of(c)
	return out

## Отряд копейщиков, которому есть что выбрать
func _make_squad(n: int, at: Vector3, level: int, pending: int) -> int:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(n):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var p := at + Vector3(float(i % 5) * 0.8, 0.0, float(i / 5) * 0.8)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
	(GameManager.squads[sid] as Dictionary)["level"]   = level
	(GameManager.squads[sid] as Dictionary)["pending"] = pending
	return sid

func _select(sid: int) -> void:
	sm._clear_selection()
	for m in GameManager.squad_members(sid):
		sm._select(m)
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	hud = main.hud
	sm  = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	# ── СКРОЛЛ КРАЕМ ЭКРАНА В СТЕНДЕ ОТКЛЮЧЁН ──────────────────────────────
	# В headless курсор лежит в (0,0), то есть В САМОМ УГЛУ: камера честно
	# считает, что игрок держит мышь у края, и едет туда каждый кадр. Любой
	# замер её положения при этом мерил бы скролл, а не то, что проверяется.
	# В игре этого случая нет: по значку ранга кликают курсором, который лежит
	# НА КНОПКЕ, а над элементом интерфейса край экрана камеру не гонит
	var cam0 = main.get("_camera")
	if cam0 != null:
		cam0.edge_pan_margin = -1.0    # ноль не годится: курсор в (0,0) — это «x <= 0»
	await frames(4)

	await _a_alert()
	await _b_axis()
	await _c_bonus_column()
	await _d_buttons()
	await _e_flags()
	await _f_preview()
	await _g_tip()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 62), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== VETUI TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ЗНАЧОК ЗАСЛУЖЕННОГО РАНГА
# ═════════════════════════════════════════════════════════════════════════════
func _a_alert() -> void:
	print("\n═════ A. ЗНАЧОК РАНГА ═════")
	# Отряд заслужил ВТОРОЙ ранг, имея первый: на значке обязана гореть одна
	# лычка и мигать вторая
	# ТОЧКА — ЗАВЕДОМО ВНУТРИ ХОДА КАМЕРЫ. Фокус зажимается не границей карты, а
	# границей МИНУС видимая полоса (RTSCamera._clamp_focus), то есть у края карты
	# камера физически не может встать на отряд, и стенд мерил бы не глиссаду, а
	# зажим
	var sid: int = _make_squad(6, Vector3(-40.0, 0.0, 20.0), 2, 1)
	await frames(4)
	hud._alert_sig = ""
	hud._refresh_alert_stack()
	await frames(2)
	var btn: Button = hud._alert_box.get_node_or_null("VetAlert_%d" % sid) as Button
	verdict("A1 значок ранга висит в стеке алертов", btn != null)
	if btn == null:
		return
	var row: Node = btn.get_node_or_null("AlertChevrons")
	var labels: Array = _labels_of(row) if row != null else []
	var txt := ""
	for l in labels:
		txt += (l as Label).text
	# Звезды быть не должно вовсе, а лычки обязаны совпасть с тем, что рисует
	# конфиг для СЛЕДУЮЩЕГО ранга (значок показывает «есть + вот-вот»)
	var want: String = _UCfg.veteran_badge_text(2)
	verdict("A2 на значке лычки, а не звезда",
		row != null and not txt.contains("★") and txt == want,
		"на значке «%s», у ранга 2 «%s»" % [txt, want])
	verdict("A3 заслуженная лычка мигает отдельно от заработанных",
		labels.size() == 2, "меток на значке %d" % labels.size())
	verdict("A4 длинной подписи у значка больше нет",
		String(btn.tooltip_text) == "", "«%s»" % String(btn.tooltip_text))

	# Клик: камера переводится ПЛАВНО (глиссада, а не прыжок) и зажигается метка
	var cam = main.get("_camera")
	var before: Vector3 = cam._focus
	hud._on_alert_pressed(sid)
	await frames(1)
	var right_after: Vector3 = cam._focus
	var goal: Vector3 = GameManager.squad_centroid(sid)
	var d0: float = Vector2(before.x - goal.x, before.z - goal.z).length()
	var d1: float = Vector2(right_after.x - goal.x, right_after.z - goal.z).length()
	verdict("A5 камера ПОЕХАЛА к отряду, а не прыгнула",
		d1 < d0 and d1 > 0.5,
		"было %.1f м, через кадр %.1f м" % [d0, d1])
	verdict("A6 по клику зажглась подсветка отряда",
		hud._ping_left > 0.0 and hud._ping_sid == sid
		and hud._ping_tr != null and hud._ping_tr.visible,
		"осталось %.2f с" % hud._ping_left)
	# Доезжает до конца сама
	for _i in range(240):
		await get_tree().process_frame
		if Vector2(cam._focus.x - goal.x, cam._focus.z - goal.z).length() < 1.0:
			break
	verdict("A7 глиссада доводит камеру до отряда",
		Vector2(cam._focus.x - goal.x, cam._focus.z - goal.z).length() < 1.0,
		"осталось %.2f м" % Vector2(cam._focus.x - goal.x, cam._focus.z - goal.z).length())
	# Ручное движение камеры глиссаду отменяет — иначе камера уползала бы
	# из-под пальцев игрока
	cam.glide_to(Vector3(0.0, 0.0, 0.0))
	cam._pan_by(Vector2(1.0, 0.0))
	verdict("A8 ручной пан отменяет глиссаду", cam._glide.x == INF)
	_drop(sid)

func _drop(sid: int) -> void:
	for m in GameManager.squad_members(sid):
		if is_instance_valid(m):
			(m as Node).queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# B. ЕДИНАЯ ЛЕВАЯ ОСЬ
# ═════════════════════════════════════════════════════════════════════════════
func _b_axis() -> void:
	print("\n═════ B. ЛЕВАЯ ОСЬ ═════")
	var sid: int = _make_squad(6, Vector3(-100.0, 0.0, 55.0), 1, 0)
	await _select(sid)
	await frames(3)
	var panel: Control = hud._bottom_panel
	var stats: Control = hud._stat_panel
	verdict("B1 панель статов построена", stats != null)
	if stats == null:
		_drop(sid)
		return
	var dx: float = absf(stats.global_position.x - panel.global_position.x)
	verdict("B2 обе левые панели стоят по одной вертикали", dx < 0.51,
		"расхождение %.1f px (панель %.0f, статы %.0f)" % [
			dx, panel.global_position.x, stats.global_position.x])
	verdict("B3 ось задана ОДНОЙ константой, а не числом в двух местах",
		absf(panel.offset_left - hud.PANEL_LEFT) < 0.01,
		"offset_left=%.1f, PANEL_LEFT=%.1f" % [panel.offset_left, hud.PANEL_LEFT])
	_drop(sid)

# ═════════════════════════════════════════════════════════════════════════════
# C. ИКОНКИ ЗАРАБОТАННЫХ НАГРАД — В ТАБЛИЦЕ СТАТОВ СПРАВА
# ═════════════════════════════════════════════════════════════════════════════
func _c_bonus_column() -> void:
	print("\n═════ C. НАГРАДЫ В ТАБЛИЦЕ ═════")
	var sid: int = _make_squad(6, Vector3(-110.0, 0.0, 60.0), 2, 0)
	(GameManager.squads[sid] as Dictionary)["chosen"] = ["armor", "armor"]
	await _select(sid)
	await frames(3)
	var stats: Control = hud._stat_panel
	var row: Node = _find_deep(stats, "BonusRow") if stats != null else null
	verdict("C1 ряд наград лежит ВНУТРИ панели статов", row != null)
	if row == null:
		_drop(sid)
		return
	var col: Node = _find_deep(stats, "BonusColumn")
	verdict("C2 ряд стоит в ПРАВОЙ колонке таблицы, а не под строками",
		col != null and row.get_parent() == col)
	# Правая колонка обязана быть именно справа: её левый край дальше правого
	# края текстовых строк
	var icon: Control = row.get_child(0) as Control
	var head: Node = null
	for c in stats.get_children():
		head = c
	verdict("C3 иконка награды в правой половине панели",
		icon != null and icon.global_position.x
			> stats.global_position.x + float(hud.STAT_PANEL_W) * 0.5,
		"иконка на x=%.0f при панели %.0f..%.0f" % [
			icon.global_position.x if icon != null else -1.0,
			stats.global_position.x,
			stats.global_position.x + float(hud.STAT_PANEL_W)])
	verdict("C4 стек «взято дважды» на месте",
		icon != null and icon.get_node_or_null("Stack") != null)
	_drop(sid)

# ═════════════════════════════════════════════════════════════════════════════
# D. КНОПКИ ВЫБОРА НАГРАДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _d_buttons() -> void:
	print("\n═════ D. КНОПКИ НАГРАД ═════")
	var sid: int = _make_squad(6, Vector3(-80.0, 0.0, 60.0), 1, 1)
	await _select(sid)
	await frames(3)
	var btns: Array = hud.button_container.get_children()
	verdict("D1 кнопки выбора награды на панели", btns.size() > 0,
		"кнопок %d" % btns.size())
	if btns.is_empty():
		_drop(sid)
		return
	var b: Button = btns[0]
	var want: float = float(hud.BTN_SIZE) * hud.VET_BTN_SCALE
	verdict("D2 иконка награды крупнее обычной кнопки на 40%",
		absf(b.custom_minimum_size.x - want) < 0.01,
		"%.0f px при обычной %d px" % [b.custom_minimum_size.x, hud.BTN_SIZE])
	var st: StyleBoxFlat = b.get_theme_stylebox("normal") as StyleBoxFlat
	verdict("D3 рамка КВАДРАТНАЯ (углы не скруглены)",
		st != null and st.corner_radius_top_left == 0
		and st.corner_radius_bottom_right == 0,
		"радиус %d" % (st.corner_radius_top_left if st != null else -1))
	verdict("D4 рамка тонкая, ровно VET_BTN_BORDER_W",
		st != null and st.border_width_left == hud.VET_BTN_BORDER_W
		and st.border_width_top == hud.VET_BTN_BORDER_W,
		"толщина %d" % (st.border_width_left if st != null else -1))
	var sh: StyleBoxFlat = b.get_theme_stylebox("hover") as StyleBoxFlat
	verdict("D5 под курсором иконка светится, а рамка не толстеет",
		sh != null and st != null
		and sh.bg_color.get_luminance() > st.bg_color.get_luminance()
		and sh.border_width_left == st.border_width_left)
	_drop(sid)

# ═════════════════════════════════════════════════════════════════════════════
# E. ФЛАЖКИ РАНГА ВМЕСТО ТЕКСТА
# ═════════════════════════════════════════════════════════════════════════════
func _e_flags() -> void:
	print("\n═════ E. ФЛАЖКИ РАНГА ═════")
	var sid: int = _make_squad(6, Vector3(-70.0, 0.0, 50.0), 2, 1)
	await _select(sid)
	await frames(3)
	# ── ДВЕ ПОЛОВИНЫ ОДНОГО ТРЕБОВАНИЯ, И ВТОРАЯ ПРИШЛА ПОПРАВКОЙ ──────────
	# Убрать надо было СЛУЖЕБНУЮ строку («★ Ветеран N — выберите награду»), а
	# НАЗВАНИЕ СО ЗВАНИЕМ владелец потребовал вернуть: «эти надписи не надо ни в
	# коем случае убирать». Стенд сторожит обе половины разом — иначе следующая
	# правка снова снесёт подпись целиком
	var caption: String = String(hud.info_label.text)
	verdict("E1 служебной строки «★ Ветеран N — выберите награду» нет",
		not caption.contains("выберите награду") and not caption.contains("★"),
		"«%s»" % caption)
	verdict("E1б звание отряда в подписи ОСТАЛОСЬ",
		hud.info_label.visible
		and caption.contains(_UCfg.veteran_rank_name("spearman", 2)),
		"«%s», ждали «%s»" % [caption, _UCfg.veteran_rank_name("spearman", 2)])
	var row: Control = hud._vet_rank_row
	verdict("E2 ряд флажков показан", row != null and row.visible)
	if row == null:
		_drop(sid)
		return
	# Отряд выбирает награду за ВТОРОЙ ранг: слева знамя первого, справа второго
	verdict("E3 показаны оба знамени: было и стало",
		row.get_node_or_null("VetFlag_1") != null
		and row.get_node_or_null("VetFlag_2") != null,
		"детей %d" % row.get_child_count())
	var arrows := 0
	for l in _labels_of(row):
		if (l as Label).text == "➜":
			arrows += 1
	verdict("E4 между знамёнами жёлтая стрелка", arrows == 1,
		"стрелок %d" % arrows)
	# Картинка знамени — ТА ЖЕ, что у знаменосца в мире (BannerArt), обрезанная
	var flag: TextureRect = row.get_node_or_null("VetFlag_2") as TextureRect
	var at: AtlasTexture = flag.texture as AtlasTexture if flag != null else null
	verdict("E5 флажок — обрезок настоящего знамени, а не свой рисунок",
		at != null and at.atlas == load("res://scripts/BannerArt.gd").texture_for(2),
		"текстура=%s" % str(flag.texture if flag != null else null))
	_drop(sid)

# ═════════════════════════════════════════════════════════════════════════════
# F. ПРЕДПРОСМОТР СТАТОВ ПРИ НАВЕДЕНИИ
# ═════════════════════════════════════════════════════════════════════════════
func _f_preview() -> void:
	print("\n═════ F. ПРЕДПРОСМОТР ═════")
	var sid: int = _make_squad(6, Vector3(-60.0, 0.0, 55.0), 1, 1)
	await _select(sid)
	await frames(3)
	var btns: Array = hud.button_container.get_children()
	if btns.is_empty():
		verdict("F0 кнопки наград есть", false)
		_drop(sid)
		return
	# Берём награду, у которой есть модификатор со СВОЕЙ строкой в таблице
	var choices: Array = _UCfg.veteran_choices("spearman", 1)
	var idx := -1
	var key := ""
	for i in range(choices.size()):
		for k in _UCfg.nonzero_modifiers(choices[i]):
			var st: String = _UCfg.modifier_stat_name(String(k))
			if hud._stat_rows.has(st):
				idx = i; key = String(k)
				break
		if idx >= 0:
			break
	if idx < 0:
		verdict("F0 в конфиге есть награда со строкой в таблице", false)
		_drop(sid)
		return
	var stat: String = _UCfg.modifier_stat_name(key)
	var base: String = String(hud._stat_base[stat])
	var rt = hud._stat_rows[stat]
	(btns[idx] as Button).mouse_entered.emit()
	await frames(2)
	var want: String = hud._mod_amount(float((choices[idx] as Dictionary)[key]))
	verdict("F1 наведение дописало будущее значение в свою строку",
		String(rt.text).contains(want) and String(rt.text).contains(hud.PREVIEW_COLOR),
		"строка «%s», ждали «%s»" % [String(rt.text), want])
	verdict("F2 предпросмотр стоит ПОСЛЕ итога, а не вместо него",
		String(rt.text).begins_with(base),
		"«%s»" % String(rt.text))
	(btns[idx] as Button).mouse_exited.emit()
	await frames(2)
	verdict("F3 курсор ушёл — строка вернулась к прежнему виду",
		String(rt.text) == base, "«%s»" % String(rt.text))
	# Клик фиксирует числа сам: панель пересобирается, и значения приходят из
	# полей бойца, а не из предпросмотра
	var men: Array = GameManager.squad_members(sid)
	var before: float = _vet_sum(men[0] as Unit)
	(btns[idx] as Button).pressed.emit()
	await frames(3)
	var men2: Array = GameManager.squad_members(sid)
	var after: float = _vet_sum(men2[0] as Unit)
	verdict("F4 клик применил награду к бойцам (числа зафиксировались)",
		after > before, "было %.2f, стало %.2f" % [before, after])
	verdict("F5 после выбора предпросмотр не остался висеть",
		hud._vet_tip == null)
	_drop(sid)

# ═════════════════════════════════════════════════════════════════════════════
# G. ПЛАШКА НАГРАДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _g_tip() -> void:
	print("\n═════ G. ПЛАШКА НАГРАДЫ ═════")
	var sid: int = _make_squad(6, Vector3(-50.0, 0.0, 60.0), 1, 1)
	await _select(sid)
	await frames(3)
	var btns: Array = hud.button_container.get_children()
	if btns.is_empty():
		verdict("G0 кнопки наград есть", false)
		_drop(sid)
		return
	var choices: Array = _UCfg.veteran_choices("spearman", 1)
	(btns[0] as Button).mouse_entered.emit()
	await frames(2)
	var tip: Node = _find_deep(hud, "VetTip")
	verdict("G1 при наведении всплывает плашка награды", tip != null)
	if tip == null:
		_drop(sid)
		return
	var texts: Array = []
	for l in _labels_of(tip):
		texts.append((l as Label).text)
	# Внутри — ТОЛЬКО статы: ни «Награда за уровень», ни «Убийств отряда»
	var junk := false
	for t in texts:
		var s: String = String(t)
		if s.contains("Награда") or s.contains("Убийств") or s.contains("Уже выбрано") \
				or s.contains("каждой модели"):
			junk = true
	verdict("G2 служебного текста в плашке нет", not junk, str(texts))
	# Каждый ненулевой модификатор конфига обязан быть строкой плашки
	var mods: Dictionary = _UCfg.nonzero_modifiers(choices[0])
	var all_there := true
	var want_lines: Array = []
	for k in _UCfg.BONUS_KEYS:
		var key: String = String(k)
		if not mods.has(key):
			continue
		var line: String = "%s %s" % [hud._mod_amount(float(mods[key])),
			String(hud.MOD_SHORT_LABELS.get(key, key.to_upper()))]
		want_lines.append(line)
		if not (line in texts):
			all_there = false
	verdict("G3 статы в плашке взяты из конфига, все и дословно", all_there,
		"ждали %s, в плашке %s" % [str(want_lines), str(texts)])
	verdict("G4 лишних строк в плашке нет", texts.size() == want_lines.size(),
		"строк %d при %d модификаторах" % [texts.size(), want_lines.size()])
	verdict("G5 в плашке есть иконка награды",
		_find_deep(tip, "VetTipStats") != null
		and (tip as Control).get_child_count() > 0)
	# Место: справа от нижней панели, а не над ней
	var panel: Control = hud._bottom_panel
	verdict("G6 плашка стоит СПРАВА от панели наград",
		(tip as Control).global_position.x
			>= panel.global_position.x + panel.size.x - 0.5,
		"плашка на x=%.0f, панель кончается на %.0f" % [
			(tip as Control).global_position.x,
			panel.global_position.x + panel.size.x])
	var vp: Vector2 = get_viewport().get_visible_rect().size
	verdict("G7 плашка выровнена по нижней кромке панели",
		absf(((tip as Control).global_position.y + (tip as Control).size.y)
			- (vp.y - float(hud.PANEL_BOTTOM_GAP))) < 2.0,
		"низ плашки %.0f, низ панели %.0f" % [
			(tip as Control).global_position.y + (tip as Control).size.y,
			vp.y - float(hud.PANEL_BOTTOM_GAP)])
	verdict("G8 плашка компактнее прежней карточки",
		float(hud.VET_TIP_W) < float(hud.CARD_W),
		"%.0f px против %.0f" % [float(hud.VET_TIP_W), float(hud.CARD_W)])
	(btns[0] as Button).mouse_exited.emit()
	await frames(2)
	verdict("G9 курсор ушёл — плашка убралась", _find_deep(hud, "VetTip") == null)
	_drop(sid)

## Сумма всего, что даёт ветеранство бойцу. Складывать надо ВСЕ поля: награда
## кладётся не в одно место (урон — в vet_attack, здоровье — прямо в max_health),
## и проверка по одному полю краснела бы на награде, которая трогает другое
func _vet_sum(u: Unit) -> float:
	if u == null or not is_instance_valid(u):
		return -1.0
	return u.max_health + u.vet_attack + u.vet_armor + u.vet_defense + u.vet_speed
