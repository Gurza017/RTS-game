extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЦЕЛОСТНОСТЬ ЗВУКА, ОТКЛИКИ РАБОЧИХ, ПЛОТНОСТЬ РЕПЛИК (ТЗ 24.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ФАЙЛЫ    — каждый путь, который AudioManager попросит загрузить
##                (all_asset_paths), существует, грузится и совпадает с диском
##                ПО РЕГИСТРУ (PCK регистрозависим, Windows-редактор — нет)
##   B ПУЛЫ     — фразы событий: свои у каждого события, только речь людей,
##                без повтора подряд, марш не говорит «держать строй»
##   C ПЛОТНОСТЬ — order_voice: 1-4 отряда — БЕЗ ГОЛОСА (синтезированные фразы
##                сняты ТЗ 25.10.2026), 5+ — марш / рог, клич после рога
##                только при открытом своём окне
##   D РАБОЧИЕ  — ротация: щелчок → штатный → пауза (голос снят); серия и отдых
##                проверяются подставным временем, без ожидания
##   E ВОРОНКА  — GameManager.on_selection_changed: рабочих озвучивает
##                ротация (и на повторный клик), копейщика — прежний click3
##   F СТОРОНЫ  — люди не звучат голосами орды/тролля, у рыцаря нет рыка
##
## ЧИСЛА НЕ ХАРДКОДЯТСЯ: окна, пороги и пулы читаются из AudioManager.
## Запуск: godot --headless --path . res://qa_voice_ack/Test.tscn

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _done := false

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(180.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 180 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_voice_ack ═════")
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)

func _voice_reset() -> void:
	AudioManager._voice_last.clear()
	AudioManager._voice_last_any = -999.0
	AudioManager._voice_alt.clear()
	AudioManager._voice_queue.clear()
	AudioManager.voice_last = ""

func _run() -> void:
	AudioManager.enabled = true
	_a_files()
	_b_pools()
	_c_density()
	_d_worker()
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	if main.get("enemy_ai") != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	AudioManager.enabled = true
	await _e_funnel()
	_f_factions()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ФАЙЛЫ
# ═════════════════════════════════════════════════════════════════════════════
## Имя файла на диске ТОЧНО в том регистре, в каком его просит код. Перебор
## каталога здесь законен: это стенд в редакторе, а не путь ассета в сборке
func _case_ok(path: String) -> bool:
	var dir: String = path.get_base_dir()
	var fname: String = path.get_file()
	var files := DirAccess.get_files_at(dir)
	if files.is_empty():
		return false
	return fname in files

func _a_files() -> void:
	print("\n═════ A. ФАЙЛЫ ═════")
	var paths: PackedStringArray = AudioManager.all_asset_paths()
	var missing: Array = []
	var bad_case: Array = []
	var no_load: Array = []
	for p in paths:
		if not ResourceLoader.exists(p):
			missing.append(p)
			continue
		if not _case_ok(p):
			bad_case.append(p)
		if AudioManager._stream(p) == null:
			no_load.append(p)
	print("  путей в аудите: %d" % paths.size())
	verdict("A1 каждый путь звука существует", missing.is_empty(), "нет: %s" % str(missing))
	verdict("A2 регистр имени совпадает с диском (PCK)", bad_case.is_empty(), "регистр: %s" % str(bad_case))
	verdict("A3 каждый файл грузится как AudioStream", no_load.is_empty(), "не грузятся: %s" % str(no_load))
	verdict("A4 аудит видит все банки (≥ 80 путей)", paths.size() >= 80, "%d" % paths.size())
	# Процедурные звуки — метки без файла; каждая обязана разбираться
	var proc_dead: Array = []
	for k in AudioManager.UI_BANK:
		var f: String = String(AudioManager.UI_BANK[k])
		if f.begins_with("@proc_") and AudioManager._stream(f) == null:
			proc_dead.append(k)
	verdict("A5 процедурные звуки интерфейса собираются (колокол, тум, перезвон…)",
		proc_dead.is_empty(), str(proc_dead))
	var nolim: Array = []
	for k2 in AudioManager.UI_BANK:
		if not AudioManager.UI_LIMITS.has(k2):
			nolim.append(k2)
	for k3 in AudioManager.VOICE_BANK:
		if not AudioManager.VOICE_LIMITS.has(k3):
			nolim.append(k3)
	verdict("A6 у каждого события интерфейса и реплики есть окно и громкость", nolim.is_empty(), str(nolim))
	# ТЗ 25.10.2026, блок 1: синтезированные реплики удалены целиком — ни
	# файла в прежних папках, ни пути в аудите
	var synth: Array = []
	for sub in ["orders/", "worker/"]:
		for f2 in DirAccess.get_files_at(AudioManager.DIR_VOICE + sub):
			if not String(f2).ends_with(".import"):
				synth.append(sub + String(f2))
		for p2 in paths:
			if String(p2).begins_with(AudioManager.DIR_VOICE + sub):
				synth.append(String(p2))
	verdict("A7 синтезированных реплик нет (orders/, worker/ пусты и не в аудите)", synth.is_empty(), str(synth))

# ═════════════════════════════════════════════════════════════════════════════
# B. ПУЛЫ ФРАЗ
# ═════════════════════════════════════════════════════════════════════════════
func _b_pools() -> void:
	print("\n═════ B. ПУЛЫ ═════")
	var ids: Dictionary = {}
	for r in AudioManager.ORDER_REPLIES:
		ids[String((r as Dictionary)["id"])] = String((r as Dictionary)["file"])
	var unknown: Array = []
	var not_human: Array = []
	for ev in AudioManager.REPLY_POOL_EVENTS:
		for id in AudioManager.REPLY_POOL_EVENTS[ev]:
			if not ids.has(String(id)):
				unknown.append("%s/%s" % [ev, id])
				continue
			var f: String = String(ids[String(id)])
			if not (f.begins_with(AudioManager.DIR_VOICE) or f.begins_with(AudioManager.DIR_SFX)):
				not_human.append(f)
	verdict("B1 каждая фраза пула есть в таблице", unknown.is_empty(), str(unknown))
	verdict("B2 все фразы — из каталогов речи людей", not_human.is_empty(), str(not_human))
	var mm: Array = AudioManager.REPLY_POOL_EVENTS["mass_march"]
	verdict("B3 на массовый марш не звучит «Hold the line»", not ("hold_line" in mm), str(mm))
	var hl: Array = AudioManager.REPLY_POOL_EVENTS["hold_line"]
	verdict("B4 протяжка строя — только «Hold the line»", hl.size() == 1 and String(hl[0]) == "hold_line", str(hl))
	var gone: Array = []
	for ev0 in ["order_move_short", "order_attack_short", "worker_ack"]:
		if AudioManager.REPLY_POOL_EVENTS.has(ev0) or AudioManager.VOICE_BANK.has(ev0):
			gone.append(ev0)
	verdict("B5 событий синтезированных реплик больше нет", gone.is_empty(), str(gone))
	# Без повтора подряд и все фразы пула встречаются — на каждом событии
	var rep_bad: Array = []
	for ev2 in ["mass_march"]:
		var pool: Array = AudioManager.REPLY_POOL_EVENTS[ev2]
		var seen: Dictionary = {}
		var prev: String = ""
		var repeats := 0
		for _i in range(80):
			var id3: String = String((AudioManager._pick_reply(ev2) as Dictionary)["id"])
			if not (id3 in pool):
				repeats += 100
			if id3 == prev:
				repeats += 1
			prev = id3
			seen[id3] = true
		if repeats > 0 or seen.size() != pool.size():
			rep_bad.append("%s: повторов %d, встретилось %d из %d" % [ev2, repeats, seen.size(), pool.size()])
	verdict("B6 фраза события без повтора подряд, весь пул встречается", rep_bad.is_empty(), str(rep_bad))

# ═════════════════════════════════════════════════════════════════════════════
# C. ПЛОТНОСТЬ ПО ЧИСЛУ ОТРЯДОВ
# ═════════════════════════════════════════════════════════════════════════════
func _c_density() -> void:
	print("\n═════ C. ПЛОТНОСТЬ ═════")
	var SM = load("res://scripts/SelectionManager.gd")
	verdict("C1 порог 5+ совпадает с SelectionManager.MASS_ORDER_SQUADS",
		AudioManager.ORDER_VOICE_MASS_SQUADS == int(SM.MASS_ORDER_SQUADS),
		"%d / %d" % [AudioManager.ORDER_VOICE_MASS_SQUADS, int(SM.MASS_ORDER_SQUADS)])
	var mass: int = AudioManager.ORDER_VOICE_MASS_SQUADS
	_voice_reset()
	verdict("C2 ноль отрядов — тишина", AudioManager.order_voice(0, false) == "")
	var short_ok := true
	for n in range(1, mass):
		_voice_reset()
		if AudioManager.order_voice(n, false) != "" or AudioManager.voice_last != "":
			short_ok = false
		_voice_reset()
		if AudioManager.order_voice(n, true) != "" or AudioManager.voice_last != "":
			short_ok = false
	verdict("C3 1-%d отряда: голоса нет (синтезированные фразы сняты)" % (mass - 1), short_ok)
	# Окно повтора массового марша: второй приказ подряд молчит
	_voice_reset()
	var p1: bool = AudioManager.play_voice("mass_march")
	AudioManager._voice_last_any = -999.0
	var p2: bool = AudioManager.play_voice("mass_march")
	verdict("C5 массовый марш не повторяется раньше своего окна (%.0f с)" %
		float((AudioManager.VOICE_LIMITS["mass_march"] as Dictionary)["gap"]), p1 and not p2,
		"%s / %s" % [str(p1), str(p2)])
	_voice_reset()
	verdict("C6 %d+ отрядов, марш — «mass_march»" % mass, AudioManager.order_voice(mass, false) == "mass_march")
	_voice_reset()
	var ev: String = AudioManager.order_voice(mass + 3, true)
	var queued := false
	for q in AudioManager._voice_queue:
		if String((q as Array)[0]) == "war_cry":
			queued = true
	verdict("C7 %d+ на атаку: рог сразу, клич в очереди под его хвост" % mass,
		ev == "horn_attack" and AudioManager.voice_last == "horn_attack" and queued,
		"событие %s, клич в очереди %s" % [ev, str(queued)])
	# Клич РЕДКИЙ: при закрытом окне клича рог звучит один
	_voice_reset()
	AudioManager._voice_last["war_cry"] = float(Time.get_ticks_msec()) * 0.001
	AudioManager.order_voice(mass, true)
	var queued2 := false
	for q2 in AudioManager._voice_queue:
		if String((q2 as Array)[0]) == "war_cry":
			queued2 = true
	verdict("C8 окно клича закрыто — только рог", not queued2 and AudioManager.voice_last == "horn_attack")
	var gap_war: float = float((AudioManager.VOICE_LIMITS["war_cry"] as Dictionary)["gap"])
	var gap_horn: float = float((AudioManager.VOICE_LIMITS["horn_attack"] as Dictionary)["gap"])
	verdict("C9 окно клича длиннее окна рога (клич реже рога)", gap_war > gap_horn * 2.0,
		"клич %.0f с, рог %.0f с" % [gap_war, gap_horn])
	var gaps_ok := true
	for e in ["war_cry"]:
		if float((AudioManager.VOICE_LIMITS[e] as Dictionary)["gap"]) < 9.0:
			gaps_ok = false
	verdict("C10 новые реплики не чаще правила 10.09 (окно ≥ 9 с)", gaps_ok)
	_voice_reset()

# ═════════════════════════════════════════════════════════════════════════════
# D. РОТАЦИЯ ОТКЛИКОВ РАБОЧЕГО
# ═════════════════════════════════════════════════════════════════════════════
func _d_worker() -> void:
	print("\n═════ D. РАБОЧИЕ ═════")
	var R: float = AudioManager.WORKER_ACK_RESET_SEC
	var REST: float = AudioManager.WORKER_ACK_REST_SEC
	_voice_reset()
	AudioManager.worker_ack_reset()
	AudioManager._ui_last.clear()
	var t := 1000.0
	var s1: String = AudioManager.worker_ack("pick", t)
	var ui1: String = AudioManager.ui_last
	var s2: String = AudioManager.worker_ack("pick", t + R * 0.4)
	var ui2: String = AudioManager.ui_last
	var s3: String = AudioManager.worker_ack("pick", t + R * 0.8)
	var v3: String = AudioManager.voice_last
	var s4: String = AudioManager.worker_ack("pick", t + R * 1.2)
	verdict("D1 1-й клик — короткий щелчок (%s)" % ui1, s1 == "click" and ui1 == "worker_pick")
	verdict("D2 2-й клик — штатный щелчок (%s)" % ui2, s2 == "std" and ui2 == "pick_squad")
	verdict("D3 3-й клик — тишина, начало паузы (голос снят)", s3 == "rest" and v3 == "", "%s / %s" % [s3, v3])
	verdict("D4 4-й клик — пауза", s4 == "")
	# Отдых: даже редкие клики молчат, пока не прошёл WORKER_ACK_REST_SEC
	var s5: String = AudioManager.worker_ack("pick", t + R * 0.8 + REST * 0.6)
	verdict("D5 после третьей ступени серия молчит %.0f с, даже при редких кликах" % REST, s5 == "")
	var s6: String = AudioManager.worker_ack("pick", t + R * 0.8 + REST + 0.1)
	verdict("D6 отдых прошёл — серия снова с короткого щелчка", s6 == "click")
	# Серия рвётся паузой между кликами длиннее RESET
	AudioManager.worker_ack_reset()
	var a1: String = AudioManager.worker_ack("pick", 2000.0)
	var a2: String = AudioManager.worker_ack("pick", 2000.0 + R * 0.5)
	var a3: String = AudioManager.worker_ack("pick", 2000.0 + R * 0.5 + R + 0.2)
	verdict("D7 пауза между кликами > %.1f с начинает серию заново" % R, a1 == "click" and a2 == "std" and a3 == "click")
	# Приказ рабочим: вторая ступень — штатный щелчок приказа
	AudioManager.worker_ack_reset()
	AudioManager._ui_last.clear()
	AudioManager.worker_ack("order", 3000.0)
	AudioManager.worker_ack("order", 3000.5)
	verdict("D8 приказ рабочим: 2-я ступень — щелчок приказа (%s)" % AudioManager.ui_last,
		AudioManager.ui_last == "order_move")
	AudioManager.worker_ack_reset()
	_voice_reset()

# ═════════════════════════════════════════════════════════════════════════════
# E. ВОРОНКА ВЫДЕЛЕНИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _spawn(scene: String, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = at
	u.sync_row()
	return u

func _e_funnel() -> void:
	print("\n═════ E. ВОРОНКА ВЫДЕЛЕНИЯ ═════")
	var w: Unit = _spawn("res://scenes/units/Worker.tscn", Vector3(-60.0, 0.0, -60.0))
	var sp: Unit = _spawn("res://scenes/units/Spearman.tscn", Vector3(-64.0, 0.0, -60.0))
	await pframes(3)
	AudioManager.worker_ack_reset()
	_voice_reset()
	var c0: int = AudioManager.worker_ack_calls
	GameManager.on_selection_changed([w])
	var e1: String = AudioManager.worker_ack_last
	GameManager.on_selection_changed([w])
	var e2: String = AudioManager.worker_ack_last
	GameManager.on_selection_changed([w])
	var e3: String = AudioManager.worker_ack_last
	verdict("E1 клики по рабочему идут в ротацию, и повторный тоже (%s/%s/%s)" % [e1, e2, e3],
		AudioManager.worker_ack_calls - c0 == 3 and e1 == "click" and e2 == "std" and e3 == "rest")
	verdict("E2 третий клик — без голоса", AudioManager.voice_last == "", AudioManager.voice_last)
	AudioManager.ui_last = ""
	var c1: int = AudioManager.worker_ack_calls
	GameManager.on_selection_changed([sp])
	verdict("E3 копейщик — прежний click3, не ротация рабочих",
		AudioManager.ui_last == "pick_squad" and AudioManager.worker_ack_calls == c1, AudioManager.ui_last)
	AudioManager.ui_last = ""
	GameManager.on_selection_changed([sp])
	verdict("E4 повторное обновление панели отряда по-прежнему молчит", AudioManager.ui_last == "", AudioManager.ui_last)
	var c2: int = AudioManager.worker_ack_calls
	GameManager.on_selection_changed([w, sp])
	verdict("E5 смешанное выделение (рабочий + воин) — не ротация рабочих", AudioManager.worker_ack_calls == c2)
	AudioManager.worker_ack_reset()
	_voice_reset()

# ═════════════════════════════════════════════════════════════════════════════
# F. СТОРОНЫ: ГОЛОСА ОРДЫ НЕ У ЛЮДЕЙ, РЫКА НЕТ У РЫЦАРЕЙ
# ═════════════════════════════════════════════════════════════════════════════
func _monster_cats() -> Dictionary:
	var out: Dictionary = {}
	for cat in AudioManager.SFX_BANK:
		for f in AudioManager.SFX_BANK[cat]:
			var p: String = AudioManager.sfx_path(String(f))
			if p.begins_with(AudioManager.DIR_GOBLIN_VOICE) or p.begins_with(AudioManager.DIR_TROLL_VOICE) \
					or p.begins_with(AudioManager.DIR_GNOLL_VOICE):
				out[cat] = true
	return out

func _f_factions() -> void:
	print("\n═════ F. СТОРОНЫ ═════")
	var mon: Dictionary = _monster_cats()
	var leak: Array = []
	for scene in ["Spearman", "Archer", "Warrior", "Worker", "Monk"]:
		var u = load("res://scenes/units/%s.tscn" % scene).instantiate()
		for m in ["_sfx_swing", "_sfx_hit", "_sfx_shout", "_sfx_death", "_sfx_grunt", "_sfx_hurt", "_sfx_move_grunt"]:
			if u.has_method(m):
				var c: String = String(u.call(m))
				if mon.has(c):
					leak.append("%s.%s=%s" % [scene, m, c])
		u.free()
	verdict("F1 люди не звучат голосами орды, тролля и гноллов", leak.is_empty(), str(leak))
	var gob_ok := true
	for scene2 in ["GoblinSpearman", "GoblinPigRider"]:
		var g = load("res://scenes/units/%s.tscn" % scene2).instantiate()
		if not mon.has(String(g.call("_sfx_grunt"))):
			gob_ok = false
		g.free()
	verdict("F2 гоблины по-прежнему со своими голосами", gob_ok)
	var ka: Array = AudioManager.SFX_BANK["knight_angry"]
	var growl := false
	for f in ka:
		var p: String = AudioManager.sfx_path(String(f))
		if String(f).begins_with("angry") or mon.has("knight_angry") or not p.begins_with(AudioManager.DIR_SFX):
			growl = true
	verdict("F3 выкрик ярости рыцаря — человеческий, без рыка angry*.wav", not growl and not ka.is_empty(), str(ka))
	verdict("F4 смех орды — только в банке орды",
		not mon.is_empty() and mon.has("goblin_laugh"))
