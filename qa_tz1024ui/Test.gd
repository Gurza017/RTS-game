extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 24.10.2026, второе письмо (UI/UX, навигация у леса, сохранение)
## ═══════════════════════════════════════════════════════════════════════════
##   A — приказ стрелкам: подтверждение, подмигивание цели, «только стрелки»
##   B — подсказка штандарта: [Недоступно]/ПКМ, описание, абзац о повторе
##   C — укрепление башни: три равных эшелона
##   D — таблица статов: у лучника без Push/Defense, «Cooldown», без «AUT»,
##       флажок ранга вместо «Ранг N → M»
##   E — кузница: у рабочего строки Speed/Carry/Build и проценты, у пехоты
##       растущие строки подсвечены
##   F — лесные карманы залиты при сборке сетки
##   G — сохранения: стенд пишет не в каталог игрока, подпись старой версии
##       короткая
## Запуск: godot --headless --path . res://qa_tz1024ui/Test.tscn [-- only=abcdefg]

const F := Constants.FACTION_PLAYER
const R := Constants.FACTION_ENEMY
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _Relic := preload("res://scripts/RelicButton.gd")
const _Save := preload("res://scripts/SaveLoadManager.gd")
const _CursorArt := preload("res://scripts/CursorArt.gd")
var main: Node = null
var sm = null
var hud = null
var _pass := 0
var _fail := 0
var _only: String = "abcdefg"
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_tz1024ui: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

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
		var p: Vector3 = at + Vector3(float(i / 5) * 0.7, 0.0, (float(i % 5) - 2.0) * 0.7)
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

func _find(root: Node, nm: String) -> Node:
	if root == null:
		return null
	if root.name == nm:
		return root
	for c in root.get_children():
		var r := _find(c, nm)
		if r != null:
			return r
	return null

func _spot(dx: float, dz: float) -> Vector3:
	return main.PLAYER_BASE_ANCHOR + Vector3(dx, 0.0, dz)

func _run() -> void:
	seed(1024)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	sm = main.selection_manager
	hud = main.hud
	if "a" in _only: await _a_confirm()
	if "b" in _only: _b_relic_tip()
	if "c" in _only: _c_forts()
	if "d" in _only: await _d_stat_panel()
	if "e" in _only: await _e_forge()
	if "f" in _only: _f_forest()
	if "g" in _only: _g_saves()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_confirm() -> void:
	print("\n═════ A. ПРИКАЗ СТРЕЛКАМ ═════")
	var arch: int = _squad("archer", F, _spot(40, 10), 10)
	var spear: int = _squad("spearman", F, _spot(40, 20), 10)
	var foe: int = _squad("spearman", R, _spot(60, 10), 10)
	await pframes(3)
	sm.select_units(_members(arch))
	verdict("A1 выделены лучники — «только стрелки»", sm.selection_ranged_only())
	sm.select_units(_members(arch) + _members(spear))
	verdict("A2 лучники с пехотой — не «только стрелки»", not sm.selection_ranged_only())
	verdict("A3 курсор-стрела есть в наборе", _CursorArt.ARROW != _CursorArt.SWORD)
	var fm: Array = _members(foe)
	var w0: int = 0
	for m in fm:
		w0 += (m as Unit).winks
	var c0: int = sm.attack_confirms
	sm._confirm_attack(fm[0], true)
	var w1: int = 0
	for m in fm:
		w1 += (m as Unit).winks
	verdict("A4 приказ по врагу подтверждён и весь отряд цели мигнул",
		sm.attack_confirms == c0 + 1 and w1 - w0 == fm.size(), "мигнуло %d из %d" % [w1 - w0, fm.size()])
	sm.select_units([])
	for s in [arch, spear, foe]:
		for m in _members(int(s)):
			(m as Unit).take_damage(1.0e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _b_relic_tip() -> void:
	print("\n═════ B. ПОДСКАЗКА ШТАНДАРТА ═════")
	var off: String = _Relic.tip_text(false, 10)
	var on: String = _Relic.tip_text(true, 0)
	verdict("B1 не заряжен — «[Недоступно]»", off.begins_with("[Недоступно]"), off.get_slice("\n", 0))
	verdict("B2 заряжен — ПКМ выдать, ЛКМ/Esc отмена", on.contains("Нажмите ПКМ") and on.contains("ЛКМ/Esc"))
	verdict("B3 описание и абзац о повторном использовании",
		off.contains("Штандарт выдаётся отряду за накопленный боевой опыт")
		and off.contains("При повторном использовании"))

# ═════════════════════════════════════════════════════════════════════════════
func _c_forts() -> void:
	print("\n═════ C. УКРЕПЛЕНИЕ БАШНИ ═════")
	var lv: Array = _UCfg.TOWER_FORT_LEVELS
	verdict("C1 эшелонов три", lv.size() == 3, str(lv.size()))
	var same := true
	for l in lv:
		var d: Dictionary = l
		var d0: Dictionary = lv[0]
		for k in ["wood", "stone", "time", "hp_add"]:
			if absf(float(d.get(k, 0)) - float(d0.get(k, 0))) > 0.001:
				same = false
	verdict("C2 эшелоны равные по цене, времени и прибавке", same)

# ═════════════════════════════════════════════════════════════════════════════
func _d_stat_panel() -> void:
	print("\n═════ D. ТАБЛИЦА СТАТОВ ═════")
	var arch: int = _squad("archer", F, _spot(40, -10), 10)
	await pframes(3)
	GameManager.squads[arch]["level"] = 2
	GameManager.squads[arch]["chosen"] = ["auto_1", "auto_2"]
	hud._show_stat_panel(arch, _members(arch))
	await get_tree().process_frame
	var keys: Array = hud._stat_rows.keys()
	verdict("D1 у лучника нет строк Push и Defense", not ("push" in keys) and not ("defense" in keys), str(keys))
	verdict("D2 подпись перезарядки — «Cooldown»", String(hud.STAT_ROW_LABELS["cooldown"]) == "Cooldown")
	var row: Node = _find(hud._stat_panel, "BonusRow")
	var auts := 0
	if row != null:
		for c in row.get_children():
			if String(c.name).begins_with("Bonus_auto"):
				auts += 1
	verdict("D3 служебных значков «AUT» в колонке наград нет", row != null and auts == 0, "AUT: %d" % auts)
	sm.select_units(_members(arch))
	await pframes(4)
	var xr: Node = hud._xp_row
	var flag: Node = xr.get_node_or_null("XpFlag") if xr != null else null
	verdict("D4 флажок ранга вместо «Ранг N → M»", xr != null and flag != null
		and not hud._xp_label.text.contains("Ранг"), hud._xp_label.text)
	sm.select_units([])
	for m in _members(arch):
		(m as Unit).take_damage(1.0e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _e_forge() -> void:
	print("\n═════ E. КУЗНИЦА ═════")
	var wk: Unit = _unit("worker", F, _spot(30, -20))
	await pframes(3)
	sm.select_units([wk])
	await pframes(2)
	hud._forge_preview_begin(_Forge.get_node("worker_2b"))
	await get_tree().process_frame
	var keys: Array = hud._stat_rows.keys()
	keys.sort()
	verdict("E1 у рабочего в таблице только Speed/Carry/Build", keys == ["build", "carry", "speed"], str(keys))
	var crt = hud._stat_rows.get("carry")
	verdict("E2 прибавка груза — процентами", crt != null and String(crt.text).contains("%"),
		String(crt.text) if crt != null else "строки нет")
	verdict("E3 растущая строка рабочего подсвечена", hud.stat_rows_lit >= 1, str(hud.stat_rows_lit))
	hud._forge_preview_end()
	sm.select_units([])
	var sp: int = _squad("spearman", F, _spot(30, -30), 10)
	await pframes(3)
	sm.select_units(_members(sp))
	await pframes(3)
	var lit := 0
	var used := ""
	for cell in (_Forge.UNITS["spearman"] as Dictionary):
		var nd: Dictionary = _Forge.get_node(_Forge.node_id("spearman", String(cell)))
		if _UCfg.nonzero_modifiers(nd).is_empty():
			continue
		hud._forge_preview_begin(nd)
		await get_tree().process_frame
		lit = hud.stat_rows_lit
		used = String(nd.get("id", ""))
		hud._forge_preview_end()
		if lit > 0:
			break
	verdict("E4 у пехоты растущие строки подсвечены при наведении на улучшение", lit > 0,
		"%s: %d строк" % [used, lit])
	verdict("E5 подсветка снимается с уходом курсора", hud.stat_rows_lit == 0)
	sm.select_units([])
	wk.take_damage(1.0e12)
	for m in _members(sp):
		(m as Unit).take_damage(1.0e12)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
func _f_forest() -> void:
	print("\n═════ F. ЛЕСНЫЕ КАРМАНЫ ═════")
	var n: int = GameManager.army.forest_pockets()
	print("  залито карманов: %d" % n)
	verdict("F1 карманы у кромки леса залиты при сборке сетки", n > 0, str(n))

# ═════════════════════════════════════════════════════════════════════════════
func _g_saves() -> void:
	print("\n═════ G. СОХРАНЕНИЯ ═════")
	verdict("G1 стенд пишет сохранения не в каталог игрока", _Save.SAVE_DIR != "user://", _Save.SAVE_DIR)
	# Файл чужой версии карты в слоте 2 каталога стенда
	var path: String = _Save.slot_path(2)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_32(_Save.MAGIC)
	f.store_32(_Save.FORMAT_VERSION)
	f.store_32(_Save.WORLD_GEN_VERSION - 1)
	f.store_32(0)
	f.close()
	var lbl: String = _Save.slot_label(2)
	verdict("G2 подпись несовместимого слота короткая", lbl.length() <= 40 and lbl.contains("старая версия"), lbl)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
