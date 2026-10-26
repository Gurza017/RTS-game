extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: АВТОСОХРАНЕНИЕ И ЗНАМЁНА ВЕТЕРАНСТВА (ТЗ 13.10.2026, письмо 7)
## ═══════════════════════════════════════════════════════════════════════════
##   A — настройка интервала: файл settings.cfg, круговой рейс, нормализация,
##       список в опциях главного меню и в паузе;
##   B — таймер: срабатывание ровно на 5-й и 10-й минуте, ОДИН файл слота,
##       перезапись, стоит на паузе, стоит вне живой партии, «Выключено»
##       не пишет, файл читается load_state(0) и совпадает с партией;
##   C — фризы: цена слепка на главном потоке и худший кадр во время фоновой
##       записи на ~3000 бойцов;
##   D — знамёна: общее ветеранство — прежние вымпелы (штандарт НЕ рисуется
##       вовсе), реликвия/награда рукой — красный штандарт × 1.5, высший
##       ранг — по ручке, флажок панели, слепок переносит признак.
## Запуск: godot --headless --path . res://qa_autosave/Test.tscn [-- only=abcd]

const _Save := preload("res://scripts/SaveLoadManager.gd")
const _GS := preload("res://scripts/game_settings.gd")
const _BannerArt := preload("res://scripts/BannerArt.gd")
const _Banner := preload("res://scripts/SquadBanner.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

const F := Constants.FACTION_PLAYER

var main: Node = null
var _pass := 0
var _fail := 0
var _only: String = "abcd"

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

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_autosave: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _find(root: Node, nm: String) -> Node:
	if root.name == nm:
		return root
	for c in root.get_children():
		var r := _find(c, nm)
		if r != null:
			return r
	return null

func _unit(uid: String, f: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = f
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(uid: String, f: int, at: Vector3, n: int, cols: int, gap: float = 0.65) -> int:
	var sid: int = GameManager.new_squad(f, uid)
	for i in range(n):
		var u := _unit(uid, f, at + Vector3(float(i / cols) * gap, 0.0, (float(i % cols) - float(cols - 1) * 0.5) * gap))
		GameManager.add_to_squad(sid, u)
	return sid

## Живые на карте плюс укрытые в зданиях (гарнизон снят с карты и из групп —
## Castle.absorb_unit, — а в слепок идёт: иначе лучники в башне пропадали бы)
func _live_count() -> int:
	var n := 0
	for f in range(Constants.FACTION_COUNT):
		for u in get_tree().get_nodes_in_group(Constants.unit_group(f)):
			if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
				n += 1
		for b in get_tree().get_nodes_in_group(Constants.building_group(f)):
			if not is_instance_valid(b) or not (b is Castle):
				continue
			for rec in (b as Castle).garrison:
				var sid: int = int((rec as Dictionary).get("sid", 0))
				if sid <= 0 or not GameManager.squads.has(sid):
					continue
				for m in GameManager.squads[sid]["members"]:
					if is_instance_valid(m) and (m as Unit).garrisoned and not (m as Unit).is_dead():
						n += 1
	return n

func _autosave_files() -> Array:
	var out: Array = []
	var d := DirAccess.open(_Save.SAVE_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if String(f).begins_with("autosave"):
			out.append(String(f))
	return out

func _saved_at(slot: int) -> String:
	var st: Dictionary = _Save.load_state(slot)
	if st.has("__error"):
		return ""
	return String((st.get("meta", {}) as Dictionary).get("saved_at", ""))

# ═════════════════════════════════════════════════════════════════════════════
func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	# Чистый лист: чужое автосохранение и чужая настройка не должны судиться
	var keep_min: int = _GS.autosave_minutes()
	for f in _autosave_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_Save.SAVE_DIR + f))

	if "a" in _only:
		await _block_a()

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	# Замок игрока и живая партия: при прямой загрузке Main.tscn игрок ещё
	# расставляет крепость (ловушка стендов 13.10)
	var cp: Vector3 = main.PLAYER_BASE_ANCHOR
	main._clear_area_of_resources(cp, 12.0)
	main._clear_trees(cp, 12.0)
	var cb: Building = load("res://scripts/Castle.gd").new()
	cb.faction = F
	main.world_add(cb)
	cb.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	main._phase = main.Phase.PLAYING
	await pframes(4)
	var auto: Node = main.autosave
	verdict("0 узел автосохранения поднят Main и партия «живая»", auto != null and bool(main.is_playing()))

	if "b" in _only:
		await _block_b(auto)
	if "c" in _only:
		await _block_c(auto)
	if "d" in _only:
		await _block_d()

	_GS.set_autosave_minutes(keep_min)
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. НАСТРОЙКА
# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. НАСТРОЙКА ИНТЕРВАЛА ═════")
	_GS.set_autosave_minutes(5)
	var cfg := ConfigFile.new()
	var ok_file: bool = cfg.load(_GS.SETTINGS_CFG) == OK
	verdict("A1 выбор пишется в %s [gameplay] autosave_minutes" % _GS.SETTINGS_CFG,
		ok_file and int(cfg.get_value("gameplay", "autosave_minutes", -1)) == 5,
		"в файле %s" % str(cfg.get_value("gameplay", "autosave_minutes", null)))
	# Круговой рейс: сброс статики и чтение «как при запуске игры»
	_GS._autosave_loaded = false
	_GS._autosave_min = 99
	verdict("A2 при запуске значение читается из файла (5)", _GS.autosave_minutes() == 5,
		"прочитано %d" % _GS.autosave_minutes())
	verdict("A3 варианты ровно Выключено/5/10/15, чужое число схлопывается",
		_GS.AUTOSAVE_CHOICES == [0, 5, 10, 15] and _GS.normalize_autosave(7) == 5
		and _GS.normalize_autosave(12) == 10 and _GS.normalize_autosave(-3) == 0
		and _GS.normalize_autosave(40) == 15)
	# Опции главного меню
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	if menu.has_method("show_page"):
		menu.show_page("options")
	await get_tree().process_frame
	var opt := _find(menu, "AutosaveOption") as OptionButton
	verdict("A4 в опциях главного меню есть список «Автосохранение» (4 пункта, выбран «5 минут»)",
		opt != null and opt.item_count == 4 and opt.selected == 1,
		("пунктов %d, выбран %d" % [opt.item_count, opt.selected]) if opt != null else "списка нет")
	if opt != null:
		# Клик по пункту «15 минут» — через сигнал, как делает OptionButton
		opt.select(3)
		opt.item_selected.emit(3)
		verdict("A5 выбор в меню уезжает в настройку и файл", _GS.autosave_minutes() == 15
			and (func():
				var c2 := ConfigFile.new()
				return c2.load(_GS.SETTINGS_CFG) == OK and int(c2.get_value("gameplay", "autosave_minutes", -1)) == 15).call())
	remove_child(menu)
	menu.queue_free()
	await get_tree().process_frame

# ═════════════════════════════════════════════════════════════════════════════
# B. ТАЙМЕР И СЛОТ
# ═════════════════════════════════════════════════════════════════════════════
func _block_b(auto: Node) -> void:
	print("\n═════ B. ТАЙМЕР И ПЕРЕЗАПИСЬ СЛОТА ═════")
	# Небольшая армия, чтобы слепку было что писать
	for i in range(4):
		_squad("spearman", F, Vector3(-90.0 + float(i) * 8.0, 0.0, -30.0), 45, 9)
	await pframes(4)
	_GS.set_autosave_minutes(5)
	auto.reset_timer()
	verdict("B1 интервал 5 мин: отсчёт %.0f с" % auto.seconds_left, absf(auto.seconds_left - 300.0) < 0.01)
	# Минуты скармливаются отсчёту напрямую (поминутно, как ход часов)
	for m in range(4):
		auto._process(60.0)
	await pframes(2)
	verdict("B2 на 4-й минуте записи нет", auto.saves_done == 0 and not _Save.has_save(0))
	auto._process(60.0)
	await pframes(2)
	auto.flush()
	await pframes(2)
	var files1: Array = _autosave_files()
	var live1: int = _live_count()
	var at1: String = _saved_at(0)
	verdict("B3 на 5-й минуте записан слот автосохранения (%s)" % _Save.AUTOSAVE_PATH,
		auto.saves_done == 1 and auto.last_error == "" and _Save.has_save(0),
		"ошибка «%s», файлы %s" % [auto.last_error, str(files1)])
	var st1: Dictionary = _Save.load_state(0)
	var n1: int = (st1.get("units", {}) as Dictionary).get("type", PackedInt32Array()).size() if not st1.has("__error") else -1
	verdict("B4 автосохранение читается и совпадает с партией (бойцов %d / живых %d)" % [n1, live1],
		not st1.has("__error") and n1 == live1)
	verdict("B5 подпись слота — «Автосохранение — <время>, <сложность>»",
		_Save.slot_label(0).begins_with("Автосохранение — ") and not _Save.slot_label(0).ends_with("пусто"),
		_Save.slot_label(0))
	# Вторая запись — 10-я минута, ТОТ ЖЕ файл
	OS.delay_msec(1100)   # чтобы saved_at (секунды) точно отличался
	_squad("archer", F, Vector3(-60.0, 0.0, -30.0), 30, 6)
	await pframes(4)
	for m in range(5):
		auto._process(60.0)
	await pframes(2)
	auto.flush()
	await pframes(2)
	var files2: Array = _autosave_files()
	var at2: String = _saved_at(0)
	var st2: Dictionary = _Save.load_state(0)
	var n2: int = (st2.get("units", {}) as Dictionary).get("type", PackedInt32Array()).size() if not st2.has("__error") else -1
	verdict("B6 на 10-й минуте слот ПЕРЕЗАПИСАН: файл один (%s), время %s → %s, бойцов %d → %d" % [
		str(files2), at1, at2, n1, n2],
		auto.saves_done == 2 and files2.size() == 1 and at2 != at1 and n2 == _live_count() and n2 > n1)
	verdict("B7 временного файла после записи не остаётся", not FileAccess.file_exists(_Save.AUTOSAVE_PATH + ".tmp"))
	# Пауза: отсчёт стоит
	var left0: float = auto.seconds_left
	get_tree().paused = true
	for m in range(10):
		auto._process(60.0)
	get_tree().paused = false
	verdict("B8 на паузе отсчёт стоит (осталось %.0f → %.0f с), записи нет" % [left0, auto.seconds_left],
		absf(auto.seconds_left - left0) < 0.01 and auto.saves_done == 2)
	# Вне живой партии (победа) — стоит
	main._phase = main.Phase.VICTORY
	for m in range(10):
		auto._process(60.0)
	main._phase = main.Phase.PLAYING
	verdict("B9 вне живой партии (победа/поражение/расстановка) отсчёт стоит",
		absf(auto.seconds_left - left0) < 0.01 and auto.saves_done == 2)
	# Выключено
	_GS.set_autosave_minutes(0)
	auto.reset_timer()
	for m in range(30):
		auto._process(60.0)
	await pframes(2)
	auto.flush()
	verdict("B10 «Выключено» — за 30 минут ни одной записи", auto.saves_done == 2)
	# Смена интервала в паузе начинает отсчёт заново
	_GS.set_autosave_minutes(15)
	auto.reset_timer()
	verdict("B11 смена интервала — отсчёт заново (%.0f с)" % auto.seconds_left, absf(auto.seconds_left - 900.0) < 0.01)
	# Строка в меню паузы
	var hud = main.hud
	hud._pause_options_open = true
	hud._show_pause_menu()
	await get_tree().process_frame
	var opt := _find(hud, "AutosaveOption") as OptionButton
	verdict("B12 в настройках паузы есть список «Автосохранение» (выбран «15 минут»)",
		opt != null and opt.item_count == 4 and opt.selected == 3,
		("пунктов %d, выбран %d" % [opt.item_count, opt.selected]) if opt != null else "списка нет")
	hud._clear_overlay()
	get_tree().paused = false
	# Слот в списке загрузки паузы
	hud._show_save_menu(false)
	await get_tree().process_frame
	var slot_btn := _find(hud, "SaveSlot0") as Button
	verdict("B13 в «Загрузить игру» первым стоит слот автосохранения и он нажимаем",
		slot_btn != null and not slot_btn.disabled and slot_btn.text.begins_with("Автосохранение"),
		slot_btn.text if slot_btn != null else "кнопки нет")
	hud._show_save_menu(true)
	await get_tree().process_frame
	await get_tree().process_frame
	# ТЗ 24.10.2026, блок 6: автосохранение видно и на экране сохранения, но
	# писать в него руками нельзя — кнопка погашена
	var save_btn0 := _find(hud._overlay, "SaveSlot0") as Button
	verdict("B14 в «Сохранить игру» слот автосохранения виден, но погашен",
		save_btn0 != null and save_btn0.disabled and save_btn0.text.begins_with("Автосохранение")
		and not save_btn0.text.contains("несовмест"),
		save_btn0.text if save_btn0 != null else "кнопки нет")
	# Геометрия рамы не плывёт: сохранение в слот (смена подписи и строка
	# статуса) не меняет размер окна
	var frame := _find(hud._overlay, "ModalPanel") as Control
	var size0: Vector2 = frame.size if frame != null else Vector2.ZERO
	var b3 := _find(hud._overlay, "SaveSlot3") as Button
	if b3 != null:
		b3.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var size1: Vector2 = frame.size if frame != null else Vector2.ONE
	verdict("B15 сохранение в слот не меняет размер окна",
		frame != null and b3 != null and size0.is_equal_approx(size1),
		"%s → %s" % [size0, size1])
	verdict("B16 сохранения стенда — не в каталоге игрока", _Save.SAVE_DIR != "user://",
		_Save.SAVE_DIR)
	hud._clear_overlay()
	get_tree().paused = false
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. ФРИЗЫ
# ═════════════════════════════════════════════════════════════════════════════
func _block_c(auto: Node) -> void:
	print("\n═════ C. ЦЕНА СОХРАНЕНИЯ НА ~3000 БОЙЦАХ ═════")
	var want: int = 3000
	var have: int = _live_count()
	var k := 0
	while _live_count() < want:
		_squad("spearman", F, Vector3(-120.0 + float(k % 10) * 7.0, 0.0, 10.0 + float(k / 10) * 7.0), 60, 10)
		k += 1
		if k % 5 == 0:
			await pframes(1)
	await pframes(20)
	var n: int = _live_count()
	print("  бойцов на карте: %d (было %d)" % [n, have])
	# Фон: худший кадр за 60 кадров без записи
	var worst_bg: int = 0
	var t_prev: int = Time.get_ticks_usec()
	for i in range(60):
		await get_tree().process_frame
		var t: int = Time.get_ticks_usec()
		worst_bg = maxi(worst_bg, t - t_prev)
		t_prev = t
	# Запись: главный поток — capture; фон — кодирование и диск
	_GS.set_autosave_minutes(5)
	# Счёт — В ТОМ ЖЕ КАДРЕ, что слепок: за 60 кадров фона на карту успевает
	# выйти стартовый резерв орды (565 бойцов, первый такт GoblinAI идёт по
	# игровым часам, а на 3000 бойцах физика отстаёт от стены)
	n = _live_count()
	var t0: int = Time.get_ticks_usec()
	var why: String = auto.trigger()
	var t_main: int = Time.get_ticks_usec() - t0
	var was_bg: bool = auto.writing()
	var worst_during: int = 0
	var frames_during := 0
	t_prev = Time.get_ticks_usec()
	while auto.writing() and frames_during < 600:
		await get_tree().process_frame
		var t: int = Time.get_ticks_usec()
		worst_during = maxi(worst_during, t - t_prev)
		t_prev = t
		frames_during += 1
	auto.flush()
	await pframes(2)
	print("  главный поток (слепок + запуск потока): %.1f мс, из них capture %.1f мс; фоновая запись %d мс (%d кадров); худший кадр фон %.1f мс / во время записи %.1f мс; размер файла %d КБ" % [
		float(t_main) / 1000.0, float(auto.last_capture_usec) / 1000.0, auto.last_write_ms, frames_during,
		float(worst_bg) / 1000.0, float(worst_during) / 1000.0,
		FileAccess.get_file_as_bytes(_Save.AUTOSAVE_PATH).size() / 1024])
	verdict("C1 сохранение запущено и дописано в фоне без ошибки", why == "" and auto.last_error == "")
	verdict("C2 слепок на главном потоке ≤ 16 мс на %d бойцах (%.1f мс)" % [n, float(t_main) / 1000.0],
		t_main <= 16000)
	verdict("C3 кодирование и диск — в фоновом потоке (writing() сразу после запуска: %s)" % str(was_bg), was_bg)
	verdict("C4 худший кадр во время фоновой записи не хуже фона × 2 + 8 мс (%.1f против %.1f)" % [
		float(worst_during) / 1000.0, float(worst_bg) / 1000.0],
		worst_during <= worst_bg * 2 + 8000)
	var st: Dictionary = _Save.load_state(0)
	var nn: int = (st.get("units", {}) as Dictionary).get("type", PackedInt32Array()).size() if not st.has("__error") else -1
	verdict("C5 файл после фоновой записи читается, бойцов %d / %d" % [nn, n], nn == n)
	# Повторный запуск, пока пишется, — пропуск, а не второй поток
	auto.trigger()
	var second: String = auto.trigger()
	auto.flush()
	verdict("C6 второй запуск во время записи пропускается (%s)" % second, second != "" and auto.saves_skipped >= 1)
	_GS.set_autosave_minutes(0)

# ═════════════════════════════════════════════════════════════════════════════
# D. ЗНАМЁНА
# ═════════════════════════════════════════════════════════════════════════════
func _block_d() -> void:
	print("\n═════ D. ЗНАМЁНА: ВЫМПЕЛЫ ОБЩЕГО ВЕТЕРАНСТВА, ШТАНДАРТ — ЭЛИТЕ ═════")
	_BannerArt.clear_cache()
	var base := Vector3(-30.0, 0.0, -60.0)
	var s_auto: int = _squad("spearman", F, base, 20, 5)
	var s_relic: int = _squad("spearman", F, base + Vector3(0, 0, 10), 20, 5)
	var s_top: int = _squad("spearman", F, base + Vector3(0, 0, 20), 20, 5)
	await pframes(2)
	# Общее ветеранство — порог убийств (тот же путь, что credit_kill)
	GameManager._grant_auto_veterancy(s_auto, 0, 2)
	await pframes(2)
	var b_auto = GameManager.squads[s_auto].get("banner")
	var ok_auto: bool = b_auto != null and is_instance_valid(b_auto)
	var q_auto: QuadMesh = (b_auto.mesh as QuadMesh) if ok_auto else null
	var base_w: float = float(_BannerArt.W) * _Banner.PIXEL_SIZE
	var base_h: float = float(_BannerArt.H) * _Banner.PIXEL_SIZE
	verdict("D1 отряд общего ветеранства (ранг 2) носит ПРЕЖНИЙ вымпел: не элита, квад обычного размера",
		ok_auto and not bool(b_auto.shown_elite) and int(b_auto.shown_level) == 2 and q_auto != null
		and absf(q_auto.size.x - base_w) < 1e-4 and absf(q_auto.size.y - base_h) < 1e-4,
		("elite=%s lvl=%d size=%s" % [str(b_auto.shown_elite), int(b_auto.shown_level), str(q_auto.size if q_auto else null)]) if ok_auto else "знамени нет")
	var tier2: Dictionary = _UCfg.veteran_banner_tier(2)
	verdict("D2 картинка ранга 2 — вымпел шкалы конфига (ключ %d в кэше), штандарт (ключ %d) НЕ рисовался вовсе" % [
		int(tier2.get("key", 2)), _BannerArt.VEX_KEY_BASE + 2],
		_BannerArt._cache.has(int(tier2.get("key", 2))) and not _BannerArt._cache.has(_BannerArt.VEX_KEY_BASE + 2)
		and _BannerArt.texture_for(2) != _BannerArt.vexillum_texture(2))
	verdict("D3 после общего ветеранства отряд не элита (squad_elite=false)", not GameManager.squad_elite(s_auto))
	# Реликвия — решение игрока об этом отряде
	var granted: bool = GameManager.grant_squad_level(s_relic)
	await pframes(2)
	var b_rel = GameManager.squads[s_relic].get("banner")
	var ok_rel: bool = b_rel != null and is_instance_valid(b_rel)
	var q_rel: QuadMesh = (b_rel.mesh as QuadMesh) if ok_rel else null
	# ── РАЗВОРОТ ТЗ 22.10.2026 (блок 1): штандарт — ТОЛЬКО по личной награде
	# игрока (реликвия, награда рукой, set_squad_elite), ранг шкалы — вымпел.
	# Прежние D4-D8 утверждали «штандарт только легендарным» (ТЗ 20.10)
	var q_w: float = q_rel.size.x if q_rel != null else 0.0
	verdict("D4 отряд с реликвией — бордовый штандарт элиты, шире вымпела (разворот ТЗ 22.10.2026)",
		granted and ok_rel and bool(b_rel.shown_elite) and GameManager.squad_elite(s_relic)
		and q_rel != null and q_w > base_w * 1.05, "elite=%s квад %.3f против %.3f" % [
		str(b_rel.shown_elite) if ok_rel else "-", q_w, base_w])
	var top_rel: int = _UCfg.max_veteran_level("spearman")
	GameManager._grant_auto_veterancy(s_relic, 1, top_rel)
	await pframes(2)
	verdict("D5 штандарт элиты переживает рост ранга (лычки ранга %d на нём же)" % top_rel,
		ok_rel and bool(b_rel.shown_elite) and int(b_rel.shown_level) == top_rel)
	verdict("D6 штандарт несёт уровень элиты (римская цифра ≥ 1)",
		ok_rel and int(b_rel.shown_elite_lvl) >= 1 and int(b_rel.shown_elite_lvl) == GameManager.squad_elite_level(s_relic))
	# Снятие признака — штандарт снимается (он и есть награда)
	GameManager.set_squad_elite(s_relic, false)
	await pframes(1)
	verdict("D7 снятие признака «elite» снимает штандарт", ok_rel and not bool(b_rel.shown_elite)
		and not GameManager.squad_elite(s_relic))
	GameManager.set_squad_elite(s_relic, true)
	# Высший ранг без награды — вымпел
	var top: int = _UCfg.max_veteran_level("spearman")
	GameManager._grant_auto_veterancy(s_top, 0, top)
	await pframes(2)
	var b_top = GameManager.squads[s_top].get("banner")
	var ok_top: bool = b_top != null and is_instance_valid(b_top)
	verdict("D8 высший ранг %d по убийствам без награды — вымпел, не штандарт" % top,
		ok_top and not bool(b_top.shown_elite) and not GameManager.squad_elite(s_top))
	# Промежуточный ранг без решения игрока — не элита (6 из 7)
	var s_mid: int = _squad("spearman", F, base + Vector3(0, 0, 30), 20, 5)
	await pframes(1)
	GameManager._grant_auto_veterancy(s_mid, 0, top - 1)
	await pframes(2)
	var b_mid = GameManager.squads[s_mid].get("banner")
	verdict("D9 ранг %d по убийствам — вымпел шкалы, не штандарт" % (top - 1),
		b_mid != null and is_instance_valid(b_mid) and not bool(b_mid.shown_elite))
	# Флажок панели
	var hud = main.hud
	var fl: Control = hud._vet_flag(2, 1.0)
	var fe: Control = hud._vet_flag(2, 1.0, 18.0, true)
	var at_l := (fl as TextureRect).texture as AtlasTexture
	var at_e := (fe as TextureRect).texture as AtlasTexture
	verdict("D10 флажок панели: ранг — обрезок вымпела %s, элита — обрезок штандарта %s" % [
		str(at_l.region if at_l else null), str(at_e.region if at_e else null)],
		at_l != null and at_e != null and at_l.region == hud.VET_FLAG_CROP and at_e.region == _BannerArt.elite_crop()
		and at_l.atlas == _BannerArt.texture_for(2) and at_e.atlas == _BannerArt.elite_texture(1, 2))
	fl.queue_free(); fe.queue_free()
	# Слепок переносит признак
	var st: Dictionary = _Save.capture(main)
	var rec_rel: Dictionary = {}
	var rec_auto: Dictionary = {}
	for r in (st.get("squads", []) as Array):
		if int((r as Dictionary).get("id", -1)) == s_relic:
			rec_rel = r
		if int((r as Dictionary).get("id", -1)) == s_auto:
			rec_auto = r
	verdict("D11 слепок: у отряда с реликвией elite=true, у общего ветерана — false",
		bool(rec_rel.get("elite", false)) and not bool(rec_auto.get("elite", true)))
	var map: Dictionary = _Save._restore_squads([rec_rel, rec_auto])
	var nr: int = int(map.get(s_relic, -1))
	var na: int = int(map.get(s_auto, -1))
	verdict("D12 восстановление из слепка возвращает признак элиты",
		nr > 0 and na > 0 and bool(GameManager.squads[nr].get("elite", false))
		and not bool(GameManager.squads[na].get("elite", false)))
	# Прежние потребители: белый флаг паники и флажок рудника — вымпелы
	verdict("D13 белый флаг и флажок владельца по-прежнему вымпелы (не штандарт)",
		_BannerArt.white_flag_texture() != null and _BannerArt.white_flag_texture() != _BannerArt.vexillum_texture(1)
		and _BannerArt.faction_flag_texture(Color.RED) != _BannerArt.vexillum_texture(1))
	# Упавшее знамя элиты — штандарт того же масштаба
	var dropped0: int = GameManager.banners_dropped
	for m in GameManager.squads[s_relic]["members"].duplicate():
		if is_instance_valid(m):
			(m as Unit).take_damage(1.0e12)
	await pframes(4)
	verdict("D14 выбитый элитный отряд роняет знамя (banners_dropped %d → %d)" % [dropped0, GameManager.banners_dropped],
		GameManager.banners_dropped == dropped0 + 1)
