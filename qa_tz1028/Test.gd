extends Node
## ═══════════════════════════════════════════════════════════════════════════
## QA_TZ1028 — ТЗ 28.10.2026, реактивный HUD: кузница и численность по событию.
## ═══════════════════════════════════════════════════════════════════════════
## A — окно кузницы ОТКРЫТО, в очереди два узла. Первый доучился: его кнопка
##     тут же «Изучено» (галочка, цвет), второй — «в работе» с живой
##     полосой прогресса — БЕЗ перезахода в окно. Опрос `_process_timed`
##     обезоружен (`_last_research_id` заранее = следующий id), чтобы сработал
##     именно сигнал `GameManager.research_finished`. Ручка `forge_live_refresh`
##     выключена и опрос обезоружен — старое поведение (узел стоит «в работе»).
## B — выделен отряд 60: бойцы гибнут — бейдж портрета 60 → 58 → 55 без
##     перевыделения; смешанное выделение — строка «Отрядов: N — M бойцов» и
##     подсказка полосы родов; развёрнутый род — число на карточке и полоска
##     здоровья; род вымер — его слот уходит из полосы; отряд вымер — карточка
##     снимается. Ручка `hud_live_counts` выключена — цифра стоит (старое).
## Запуск: godot --headless --path . res://qa_tz1028/Test.tscn [-- only=ab]
const F := Constants.FACTION_PLAYER
const _Forge := preload("res://scripts/forge_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")

var main: Node = null
var hud = null
var _pass := 0
var _fail := 0
var _only: String = "ab"
var _done := false
var _sig_research: Array = []
var _sig_members: int = 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
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
	print("\n═════ ИТОГ qa_tz1028: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _give(v: float) -> void:
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_STONE, Constants.RESOURCE_GOLD, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(F, int(t), v)

func _spot(dx: float, dz: float) -> Vector3:
	return main.PLAYER_BASE_ANCHOR + Vector3(dx, 0.0, dz)

func _smithy(at: Vector3) -> Smithy:
	var s := Smithy.new()
	s.faction = F
	main.world_add(s)
	s.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return s

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var p: Vector3 = at + Vector3(float(i / 6) * 0.7, 0.0, (float(i % 6) - 2.5) * 0.7)
		GameManager.add_to_squad(sid, _unit(uid, f, p))
	return sid

func _members(sid: int) -> Array:
	var o: Array = []
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return o
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			o.append(m)
	return o

func _kill_n(sid: int, n: int) -> void:
	var ms: Array = _members(sid)
	for i in range(mini(n, ms.size())):
		(ms[i] as Unit).take_damage(1e12)

func _portrait_text() -> String:
	var l = hud._portrait_count_lbl
	if l == null or not is_instance_valid(l) or not l.visible:
		return "<скрыт>"
	return String(l.text)

func _node_btn(nid: String) -> Button:
	var v: Variant = hud._forge_nodes.get(nid)
	return v as Button if v != null and is_instance_valid(v) else null

## «Изучено» в древе: галочка и приглушённый цвет. disabled у узлов кузницы
## всегда false — отключённая Button не пропускает мышь к подсказке
func _is_done(btn: Button) -> bool:
	return btn != null and btn.find_child("DoneCheck", true, false) != null 		and btn.modulate.is_equal_approx(hud.UPG_DONE_MODULATE)

func _group_tip(uid: String) -> String:
	var row = hud._overbar_row
	if row == null or not is_instance_valid(row):
		return ""
	var slot: Node = row.get_node_or_null("GroupSlot_" + uid)
	if slot == null:
		return ""
	var badge: Node = slot.find_child("GroupCount", true, false)
	if badge == null:
		return ""
	return String((badge.get_parent() as Button).tooltip_text)

func _card(sid: int) -> Node:
	var strip = hud._squad_strip
	if strip == null or not is_instance_valid(strip):
		return null
	return strip.get_node_or_null("SquadCard%d" % sid)

func _boot() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	hud = main.hud
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	await frames(3)
	GameManager.research_finished.connect(func(f: int, id: String): _sig_research.append([f, id]))
	GameManager.squad_members_changed.connect(func(_sid: int): _sig_members += 1)

func _run() -> void:
	await _boot()
	if "a" in _only:
		await _block_a()
	if "b" in _only:
		await _block_b()
	_finish()

# ── A. КУЗНИЦА ПРИ ОТКРЫТОМ ОКНЕ ─────────────────────────────────────────────
func _block_a() -> void:
	print("\n── A. Кузница: завершение исследования при открытом окне ──")
	_give(100000.0)
	var n1: String = _Forge.node_id("spearman", "1a")
	var n2: String = _Forge.node_id("spearman", "1b")
	var s := _smithy(_spot(28.0, 24.0))
	await frames(3)
	hud.show_selection([s])
	await frames(3)
	verdict("A1 окно кузницы открыто по выделению", hud.forge_visible())
	hud.forge_set_tab("spearman")   # _forge_nodes держит узлы ТОЛЬКО активной вкладки
	await frames(1)
	var ok1: bool = s.research(n1)
	var ok2: bool = s.research(n2)
	await frames(3)
	verdict("A2 два заказа: первый в работе, второй в очереди",
		ok1 and ok2 and s.research_id == n1 and s.queue_position(n2) == 1,
		"research_id=%s, позиция второго=%d" % [s.research_id, s.queue_position(n2)])
	# Опрос обезоружен: после финиша research_id станет n2, и «смены» он не увидит
	hud._last_research_id = n2
	_sig_research.clear()
	s.research_timer = s.research_time - 0.001
	await frames(2)
	verdict("A3 сигнал research_finished пришёл (F, n1)",
		_sig_research.size() == 1 and int(_sig_research[0][0]) == F and String(_sig_research[0][1]) == n1,
		str(_sig_research))
	verdict("A4 очередь пошла дальше: research_id = второй узел", s.research_id == n2, s.research_id)
	verdict("A5 изученный узел «Изучено» без перезахода (галочка, цвет)", _is_done(_node_btn(n1)),
		"is_researched=%s, галочка=%s" % [str(GameManager.is_researched(F, n1)),
			str(_node_btn(n1).find_child("DoneCheck", true, false) != null) if _node_btn(n1) != null else "нет кнопки"])
	var b2 := _node_btn(n2)
	verdict("A6 второй узел подсвечен «в работе»",
		b2 != null and not b2.disabled and b2.modulate.is_equal_approx(hud.UPG_BUSY_MODULATE)
			and b2.tooltip_text.ends_with(hud.UPG_TIP_BUSY),
		"modulate=%s" % [str(b2.modulate) if b2 != null else "нет"])
	s.research_timer = s.research_time * 0.5
	await frames(2)
	var bar = hud._queue_active_bar
	verdict("A7 полоса прогресса второго узла живая (≈50 %)",
		bar != null and is_instance_valid(bar) and bar.is_visible_in_tree() and absf(float(bar.value) - 0.5) < 0.1,
		"value=%s" % [str(bar.value) if bar != null and is_instance_valid(bar) else "нет полосы"])
	verdict("A8 окно так и не закрывалось", hud.forge_visible() and hud._forge_smithy == s)

	# Ручка выключена + опрос обезоружен — старое поведение воспроизводится
	var n3: String = _Forge.node_id("archer", "1a")
	var n4: String = _Forge.node_id("archer", "1b")
	s.cancel_research(n2)
	await frames(2)
	s.research(n3)
	s.research(n4)
	hud.forge_set_tab("archer")
	await frames(3)
	_Opt.forge_live_refresh = false
	hud._last_research_id = n4
	s.research_timer = s.research_time - 0.001
	await frames(2)
	verdict("A9 ручка выкл: узел остаётся «в работе» (старое поведение)",
		s.research_id == n4 and not _is_done(_node_btn(n3)),
		"done=%s" % str(_is_done(_node_btn(n3))))
	_Opt.forge_live_refresh = true
	# Опрос на страже: любая смена id перерисовывает окно в следующий кадр
	hud._last_research_id = "x"
	await frames(2)
	verdict("A10 опрос «любая смена id» дорисовал окно и без сигнала", _is_done(_node_btn(n3)))
	s.cancel_research(n4)
	hud.show_selection([])
	await frames(2)

# ── B. ЖИВАЯ ЧИСЛЕННОСТЬ ─────────────────────────────────────────────────────
func _block_b() -> void:
	print("\n── B. Численность выделения тикает по гибели ──")
	var sid: int = _squad("spearman", F, _spot(30.0, -20.0), 60)
	await pframes(2)
	var all: Array = _members(sid)
	hud.show_selection(all)
	await frames(2)
	verdict("B1 бейдж портрета — 60", _portrait_text() == "60", _portrait_text())
	_sig_members = 0
	_kill_n(sid, 2)
	await frames(2)
	verdict("B2 двое пали — 58 в том же выделении", _portrait_text() == "58", _portrait_text())
	_kill_n(sid, 3)
	await frames(2)
	verdict("B3 ещё трое — 55", _portrait_text() == "55", _portrait_text())
	verdict("B4 один сигнал squad_members_changed на павшего", _sig_members == 5, str(_sig_members))

	# Смешанное выделение: строка «Отрядов» и подсказка полосы родов
	var sid2: int = _squad("archer", F, _spot(30.0, -12.0), 20)
	await pframes(2)
	var mix: Array = _members(sid) + _members(sid2)
	hud.show_selection(mix)
	await frames(2)
	var t0: String = String(hud.info_label.text)
	_kill_n(sid2, 5)
	await frames(2)
	verdict("B5 строка выделения после потерь — 70 бойцов",
		"70" in String(hud.info_label.text), "%s → %s" % [t0, hud.info_label.text])
	verdict("B6 подсказка слота лучников — 15 бойцов", "15 бойцов" in _group_tip("archer"), _group_tip("archer"))

	# Развёрнутый род: карточка и полоска здоровья
	hud._on_type_filter_pressed("spearman")
	await frames(2)
	var card: Node = _card(sid)
	var badge: Label = card.find_child("CountBadge", true, false) as Label if card != null else null
	var fill: Control = card.find_child("HpFill", true, false) as Control if card != null else null
	var w0: float = fill.custom_minimum_size.x if fill != null else -1.0
	verdict("B7 карточка отряда — 55", badge != null and String(badge.text) == "55",
		String(badge.text) if badge != null else "нет карточки")
	_kill_n(sid, 5)
	await frames(2)
	verdict("B8 карточка — 50 без перевыделения", badge != null and is_instance_valid(badge) and String(badge.text) == "50",
		String(badge.text) if badge != null and is_instance_valid(badge) else "нет")
	verdict("B9 полоска здоровья карточки ужалась", fill != null and is_instance_valid(fill)
		and fill.custom_minimum_size.x < w0 - 0.5,
		"%.1f → %.1f" % [w0, fill.custom_minimum_size.x if fill != null and is_instance_valid(fill) else -1.0])
	verdict("B10 портрет уровня 2 — 50", _portrait_text() == "50", _portrait_text())

	# Род вымер — слот уходит; отряд вымер — карточка уходит
	_kill_n(sid2, 99)
	await frames(2)
	var row = hud._overbar_row
	verdict("B11 лучники вымерли — слота в полосе родов нет",
		row != null and row.get_node_or_null("GroupSlot_archer") == null and row.get_node_or_null("GroupSlot_spearman") != null)
	_kill_n(sid, 99)
	await frames(2)
	verdict("B12 отряд вымер — карточки нет", _card(sid) == null)
	hud.show_selection([])
	await frames(2)

	# Ручка выключена — цифра стоит (старое поведение)
	_Opt.hud_live_counts = false
	var sid3: int = _squad("spearman", F, _spot(38.0, -20.0), 30)
	await pframes(2)
	hud.show_selection(_members(sid3))
	await frames(2)
	_kill_n(sid3, 3)
	await frames(2)
	verdict("B13 ручка выкл: бейдж стоит на 30 (старое поведение)", _portrait_text() == "30", _portrait_text())
	_Opt.hud_live_counts = true
	hud.show_selection(_members(sid3))
	await frames(2)
	_kill_n(sid3, 3)
	await frames(2)
	verdict("B14 ручка вкл снова — 24", _portrait_text() == "24", _portrait_text())
	hud.show_selection([])
