extends PanelContainer
## ═══════════════════════════════════════════════════════════════════════════
## ОКНО КУЗНИЦЫ ГОБЛИНОВ (ТЗ 28.10.2026, п. 3)
## ═══════════════════════════════════════════════════════════════════════════
## Открывается HUD-ом при выделении СВОЕЙ кузницы гоблинов (игра за гоблинов;
## сейчас — если игрок владеет таким зданием) и закрывается со сменой
## выделения; стенд и отладка зовут open_for(forge) напрямую. Стиль —
## MedievalUI (рамка, кнопки «wood», шрифт), пять колонок веток × три ряда.
## Статус узла — РЕАКТИВНЫЙ: сигнал GameManager.research_finished (ручка
## perf_config.forge_live_refresh, как у кузницы людей) перестраивает окно
## отложенно (к моменту сигнала кузница ещё не взяла следующий заказ);
## опрос research_id раз в кадр — страховка, полоса прогресса живёт каждый кадр.
## Окно стоит над нижней панелью у левого края и попадает в HUD._focus_panels:
## клик по нему не проваливается в мир и не снимает выделение.

const _GF := preload("res://scripts/economy/goblin_forge/goblin_forge_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _MUI := preload("res://scripts/ui/MedievalUI.gd")
const _Opt := preload("res://scripts/perf_config.gd")

## Подписи статусов (их ищут стенды)
const ST_DONE := "Изучено"
const ST_BUSY := "Изучается"
const ST_QUEUED := "В очереди"
const ST_AVAIL := "Доступно"
const ST_LOCK := "Закрыто"
const ST_STUB := "Заготовка"

const CELL := 48.0
const COL_W := 118.0

var forge: Node = null
## id узла → Button / Label статуса / ProgressBar (стендам)
var node_buttons: Dictionary = {}
var node_status: Dictionary = {}
var node_bars: Dictionary = {}
var caption: Label = null
var _grid: HBoxContainer = null
var _last_rid: String = ""
var _dirty: bool = false
var rebuilds: int = 0

func _ready() -> void:
	name = "GoblinForgePanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", _MUI.frame_style(16.0))
	theme = _MUI.theme()
	var v := VBoxContainer.new()
	v.name = "Column"
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	caption = _MUI.title_label("Кузница гоблинов", 22)
	caption.name = "Caption"
	v.add_child(caption)
	_grid = HBoxContainer.new()
	_grid.name = "Branches"
	_grid.add_theme_constant_override("separation", 8)
	v.add_child(_grid)
	var hint := _MUI.hint_label("ЛКМ — заказать, ПКМ — снять заказ (полный возврат)", 11)
	hint.name = "Hint"
	v.add_child(hint)
	GameManager.research_finished.connect(_on_research_finished)
	ResourceManager.resources_changed.connect(_on_resources)

func open_for(f: Node) -> void:
	forge = f
	_last_rid = String(forge.get("research_id")) if _valid() else ""
	visible = true
	_rebuild()

func close() -> void:
	forge = null
	visible = false

func _valid() -> bool:
	return forge != null and is_instance_valid(forge) and not (forge as Building).is_dead()

## Исследование доехало — перерисовать отложенно (как HUD._on_research_finished)
func _on_research_finished(faction: int, _id: String) -> void:
	if not _Opt.forge_live_refresh or _dirty or not visible or not _valid():
		return
	if int(forge.faction) != faction:
		return
	_dirty = true
	call_deferred("_live_rebuild")

func _live_rebuild() -> void:
	_dirty = false
	if not visible or not _valid():
		return
	_last_rid = String(forge.get("research_id"))
	_rebuild()

func _on_resources(faction: int) -> void:
	if not visible or not _valid() or int(forge.faction) != faction:
		return
	_retint()

func _process(_delta: float) -> void:
	if not visible:
		return
	if not _valid():
		close()
		return
	var rid: String = String(forge.get("research_id"))
	if rid != _last_rid:
		# Страховка опроса: любая смена заказа (a → b в одном кадре) перерисовывает
		_last_rid = rid
		_rebuild()
		return
	if not rid.is_empty() and node_bars.has(rid):
		var bar: ProgressBar = node_bars[rid]
		if bar != null and is_instance_valid(bar):
			bar.value = float(forge.call("research_progress"))
			var lbl: Label = node_status.get(rid)
			if lbl != null and is_instance_valid(lbl):
				lbl.text = "%s %d%%" % [ST_BUSY, int(round(bar.value * 100.0))]

func _rebuild() -> void:
	rebuilds += 1
	node_buttons.clear()
	node_status.clear()
	node_bars.clear()
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	if not _valid():
		return
	var f: int = int(forge.faction)
	caption.text = "%s  %d/%d HP" % [String(forge.display_name),
		int(forge.current_health), int(forge.max_health)]
	for b in _GF.BRANCH_ORDER:
		var branch: String = String(b)
		var col := VBoxContainer.new()
		col.name = "Branch_" + branch
		col.custom_minimum_size = Vector2(COL_W, 0)
		col.add_theme_constant_override("separation", 4)
		var head := Label.new()
		head.text = _GF.branch_title(branch)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_theme_font_size_override("font_size", 12)
		head.add_theme_color_override("font_color", _MUI.GOLD_TITLE)
		col.add_child(head)
		for n in _GF.branch_nodes(branch):
			col.add_child(_node_cell(n, f))
		_grid.add_child(col)

func _node_cell(node: Dictionary, f: int) -> VBoxContainer:
	var nid: String = String(node.get("id", ""))
	var cell := VBoxContainer.new()
	cell.name = "Cell_" + nid
	cell.add_theme_constant_override("separation", 2)
	var btn := Button.new()
	btn.name = "Node_" + nid
	btn.custom_minimum_size = Vector2(CELL, CELL)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	_MUI.style_button(btn, "wood", 12)
	var ipath: String = String(node.get("icon", ""))
	if not ipath.is_empty() and ResourceLoader.exists(ipath):
		var tr := TextureRect.new()
		tr.texture = load(ipath) as Texture2D
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 4; tr.offset_top = 4; tr.offset_right = -4; tr.offset_bottom = -4
		btn.add_child(tr)
	else:
		btn.text = _GF._roman(int(node.get("row", 1)))
	var done: bool = GameManager.is_researched(f, nid)
	var busy: bool = GameManager.is_researching(f, nid)
	var avail: bool = GameManager.can_research(f, nid)
	var qpos: int = int(forge.call("queue_position", nid))
	var afford: bool = ResourceManager.can_afford(f, _UCfg.upgrade_cost(node))
	var stub: bool = bool(node.get("stub", false))
	var st := Label.new()
	st.name = "Status_" + nid
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_font_size_override("font_size", 10)
	st.text = _status_text(done, busy, avail, qpos, stub)
	st.add_theme_color_override("font_color", _status_color(done, busy, avail, afford))
	btn.modulate = Color(0.55, 0.55, 0.55) if (not done and not busy and not avail) else Color.WHITE
	if done:
		btn.modulate = Color(0.75, 1.0, 0.75)
	btn.tooltip_text = "%s\n%s\nЦена: %s, %d с\n%s" % [String(node.get("name", nid)),
		String(node.get("desc", "")), _GF.cost_text(node), int(node.get("research_time", 0.0)), st.text]
	btn.pressed.connect(func(): _on_node_pressed(nid))
	btn.gui_input.connect(func(ev: InputEvent): _on_node_input(ev, nid))
	cell.add_child(btn)
	cell.add_child(st)
	if busy and qpos == 0:
		var bar := ProgressBar.new()
		bar.name = "Bar_" + nid
		bar.show_percentage = false
		bar.min_value = 0.0; bar.max_value = 1.0
		bar.value = float(forge.call("research_progress"))
		bar.custom_minimum_size = Vector2(CELL, 6)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.10, 0.08, 0.06, 0.9)
		var fg := StyleBoxFlat.new(); fg.bg_color = Color(0.55, 0.85, 0.35)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		cell.add_child(bar)
		node_bars[nid] = bar
	node_buttons[nid] = btn
	node_status[nid] = st
	return cell

func _status_text(done: bool, busy: bool, avail: bool, qpos: int, stub: bool) -> String:
	var t: String
	if done:
		t = ST_DONE
	elif busy and qpos == 0:
		t = "%s %d%%" % [ST_BUSY, int(round(float(forge.call("research_progress")) * 100.0))]
	elif busy:
		t = "%s (%d)" % [ST_QUEUED, qpos]
	elif avail:
		t = ST_AVAIL
	else:
		t = ST_LOCK
	if stub and not done:
		t += " · " + ST_STUB
	return t

func _status_color(done: bool, busy: bool, avail: bool, afford: bool) -> Color:
	if done:
		return Color(0.55, 0.9, 0.5)
	if busy:
		return Color(0.55, 0.75, 1.0)
	if avail and not afford:
		return Color(0.95, 0.45, 0.4)
	if avail:
		return _MUI.TEXT
	return _MUI.TEXT_HINT

## Доступный узел без денег краснеет по сигналу склада — без перестройки окна
func _retint() -> void:
	if not _valid():
		return
	var f: int = int(forge.faction)
	for nid in node_status.keys():
		var lbl: Label = node_status[nid]
		if lbl == null or not is_instance_valid(lbl):
			continue
		var node: Dictionary = _GF.get_node(String(nid))
		var done: bool = GameManager.is_researched(f, String(nid))
		var busy: bool = GameManager.is_researching(f, String(nid))
		var avail: bool = GameManager.can_research(f, String(nid))
		var afford: bool = ResourceManager.can_afford(f, _UCfg.upgrade_cost(node))
		lbl.add_theme_color_override("font_color", _status_color(done, busy, avail, afford))

func _on_node_pressed(nid: String) -> void:
	if not _valid():
		return
	if bool(forge.call("research", nid)):
		_last_rid = String(forge.get("research_id"))
		_rebuild()

func _on_node_input(ev: InputEvent, nid: String) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed or not _valid():
		return
	if bool(forge.call("cancel_research", nid)):
		_last_rid = String(forge.get("research_id"))
		_rebuild()

## Статус узла словом (стендам)
func status_of(nid: String) -> String:
	var lbl: Label = node_status.get(nid)
	return String(lbl.text) if lbl != null and is_instance_valid(lbl) else ""
