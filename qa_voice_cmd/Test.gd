extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ГОЛОСОВОЕ УПРАВЛЕНИЕ БЕЗ МИКРОФОНА (headless)
## ═══════════════════════════════════════════════════════════════════════════
## Микрофона в headless нет, и это не мешает проверить всё, кроме самого
## распознавания: словарь и сопоставление (текст → намерение и группы),
## привязку к отрядам по типу войск, исполнение шести команд, последовательность
## отхода фаланги (копья вверх → отход → встали → копья вниз), горн на атаку,
## обратную связь и живость распознавателя (модель грузится в фоне, поток не
## роняет главный). Сам звук проверяется ушами в окне: V, сказать, отпустить.
##   A  словарь и сопоставление
##   B  распознаватель: объект, модель, готовность, без ошибок
##   C  команды на живой сцене по типам войск
##   D  отход фаланги как последовательность
##   E  границы: чужие не тронуты, непонятая фраза
##   F  распознавание по WAV-образцам (если есть)

const _Cfg := preload("res://scripts/voice_commands_config.gd")
## Через preload, а не по class_name: новое имя класса попадает в кэш только
## после импорта редактором, а стенд без скрипта висит молча (см. память)
const _Voice := preload("res://scripts/VoiceControl.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _ready() -> void:
	call_deferred("_run")

func _mk_squad(kind: String, scene: String, fac: int, at: Vector3, n: int, course: Vector3) -> Dictionary:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var slots: Array = []
	for i in range(n):
		var u: Unit = load(scene).instantiate()
		u.faction = fac
		main.world_add(u)
		u.global_position = Vector3(at.x + float(i % 4) * 0.7, 0.0, at.z + float(i / 4) * 0.7)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
		slots.append(u.global_position)
	GameManager.squad_set_formation(sid, slots, course, false)
	return {"sid": sid, "men": men}

func _centroid(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var k := 0
	for u in men:
		if is_instance_valid(u):
			c += (u as Node3D).global_position
			k += 1
	return c / maxf(float(k), 1.0)

func _count(men: Array, pred: Callable) -> int:
	var k := 0
	for u in men:
		if is_instance_valid(u) and pred.call(u as Unit):
			k += 1
	return k

func _run() -> void:
	var guard := Timer.new()
	guard.wait_time = 150.0
	guard.one_shot = true
	guard.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 150 с")
		print("  провалов: %d из %d" % [_fail + 1, _pass + _fail + 1])
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	print("\n═════ A. СЛОВАРЬ И СОПОСТАВЛЕНИЕ ═════")
	# фраза, намерение, группы
	var table: Array = [
		["копейщики держать позицию", "defense", ["spearman"]],
		["фаланга к бою", "defense", ["spearman"]],
		["копейщики держать строй", "defense", ["spearman"]],
		["копейщики в атаку", "attack", ["spearman"]],
		["лучники в атаку", "attack", ["archer"]],
		["стрелки бей", "attack", ["archer"]],
		["мечники напасть", "attack", ["warrior"]],
		["пехота вперёд в атаку", "attack", ["warrior"]],
		["копейщики вперёд", "forward", ["spearman"]],
		["фаланга марш", "forward", ["spearman"]],
		["все вперёд", "forward", ["all"]],
		["вперёд", "forward", ["all"]],
		["копейщики отступать", "retreat", ["spearman"]],
		["копейщики отступать на двадцать метров", "retreat", ["spearman"]],
		["лучники назад на тридцать метров", "retreat", ["archer"]],
		["все стоять", "stop", ["all"]],
		["копейщики стой", "stop", ["spearman"]],
		["мечники стоп", "stop", ["warrior"]],
		["копейщики вольно", "at_ease", ["spearman"]],
		["фаланга отбой", "at_ease", ["spearman"]],
		["копейщики и лучники в атаку", "attack", ["spearman", "archer"]],
		["конница в атаку", "attack", ["goblin_rider"]],
		["принеси кофе", "", ["all"]],
	]
	var ok_all := true
	var bad := ""
	for row in table:
		var m: Dictionary = _Cfg.match(String(row[0]))
		var g: Array = m["groups"]
		var want: Array = row[2]
		var g_ok: bool = g.size() == want.size()
		for w in want:
			if not g.has(w): g_ok = false
		if String(m["intent"]) != String(row[1]) or not g_ok:
			ok_all = false
			bad += " [«%s» → %s %s, ждали %s %s]" % [String(row[0]), String(m["intent"]), str(g), String(row[1]), str(want)]
	verdict("A1 таблица фраз даёт ожидаемые намерения и группы (%d фраз)" % table.size(), ok_all, bad)
	var m20: Dictionary = _Cfg.match("копейщики отступать на двадцать метров")
	var m30: Dictionary = _Cfg.match("копейщики назад на тридцать метров")
	var mdef: Dictionary = _Cfg.match("копейщики отступать")
	verdict("A2 число метров разбирается", float(m20["distance"]) == 20.0 and float(m30["distance"]) == 30.0
		and float(mdef["distance"]) == _Cfg.RETREAT_DEFAULT_M,
		"20→%.0f, 30→%.0f, умолчание→%.0f" % [float(m20["distance"]), float(m30["distance"]), float(mdef["distance"])])
	var gw: Array = _Cfg.grammar_words()
	var dup := false
	var seen: Dictionary = {}
	for w in gw:
		if seen.has(w): dup = true
		seen[w] = true
	verdict("A3 грамматика собрана из того же словаря: слов %d, [unk] есть, дублей нет" % gw.size(),
		gw.size() >= 60 and gw.has("[unk]") and not dup)
	verdict("A4 короткие основы требуют точного слова",
		String(_Cfg.match("всегда стойкость")["intent"]) == "")
	verdict("A5 пустая фраза — не приказ", String(_Cfg.match("")["intent"]) == ""
		and (_Cfg.match("")["groups"] as Array).is_empty())

	print("\n═════ B. РАСПОЗНАВАТЕЛЬ ═════")
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	GameManager.world_bounds_enabled = false
	var voice = main.voice
	verdict("B1 узел голосового управления поднят вместе с партией", voice != null)
	var model_dir: String = _Voice.model_path()
	verdict("B2 модель найдена на диске", model_dir != "", model_dir)
	if voice != null:
		voice.start_recognizer()   # в headless он не стартует сам
	var t0: int = Time.get_ticks_msec()
	var ready := false
	while Time.get_ticks_msec() - t0 < 30000:
		await frames(5)
		if voice != null and voice.recognizer_ready():
			ready = true
			break
	verdict("B3 модель загрузилась в фоновом потоке", ready,
		"за %.1f с, ошибка: «%s»" % [float(Time.get_ticks_msec() - t0) / 1000.0, String(voice.recognizer_error()) if voice != null else "нет узла"])
	verdict("B4 ошибок распознавателя нет", voice != null and (String(voice.recognizer_error()) == "" or ready),
		String(voice.recognizer_error()) if voice != null else "")

	print("\n═════ C. КОМАНДЫ ПО ТИПАМ ВОЙСК ═════")
	# ИИ противника глушим: он сам ставит свой гарнизон в оборону, и «противник
	# не тронут» иначе меряет его такт, а не наш приказ
	for f in ["enemy_ai", "goblin_ai"]:
		var ai = main.get(f)
		if ai != null:
			(ai as Node).set_process(false)
			(ai as Node).set_physics_process(false)
	var course := Vector3(1, 0, 0)
	var sp: Dictionary = _mk_squad("spearman", "res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, Vector3(-20, 0, -30), 12, course)
	var ar: Dictionary = _mk_squad("archer", "res://scenes/units/Archer.tscn",
		Constants.FACTION_PLAYER, Vector3(-30, 0, -20), 8, course)
	var wr: Dictionary = _mk_squad("warrior", "res://scenes/units/Warrior.tscn",
		Constants.FACTION_PLAYER, Vector3(-20, 0, -10), 8, course)
	var wk: Dictionary = _mk_squad("worker", "res://scenes/units/Worker.tscn",
		Constants.FACTION_PLAYER, Vector3(-40, 0, -10), 2, course)
	var en: Dictionary = _mk_squad("spearman", "res://scenes/units/Spearman.tscn",
		Constants.FACTION_ENEMY, Vector3(40, 0, -25), 8, Vector3(-1, 0, 0))
	await pframes(10)
	for u in sp["men"]:
		(u as Unit).set_stance("attack")
	var en_def0: int = _count(en["men"], func(u): return u.stance == "defense")
	var is_moving := func(u): return u.state == Unit.State.MOVING
	var in_def := func(u): return u.stance == "defense"

	verdict("C0 группы разбираются по типу отряда: копейщики 1, лучники 1, мечники 1, все боевые 3 (рабочие вне)",
		voice.squads_for(["spearman"]).size() == 1 and voice.squads_for(["archer"]).size() == 1
		and voice.squads_for(["warrior"]).size() == 1 and voice.squads_for(["all"]).size() == 3,
		"все: %s" % str(voice.squads_for(["all"])))

	# 1. Оборона только копейщикам
	voice.apply_text("копейщики держать позицию")
	await pframes(3)
	verdict("C1 «копейщики держать позицию» → копейщики в обороне, остальные нет",
		_count(sp["men"], in_def) == 12 and _count(ar["men"], in_def) == 0 and _count(wr["men"], in_def) == 0,
		"копейщики %d/12, лучники %d, мечники %d" % [_count(sp["men"], in_def), _count(ar["men"], in_def), _count(wr["men"], in_def)])
	verdict("C1б плашка показала распознанный текст", String(voice.shown_text()) == "копейщики держать позицию")

	# 2. Вольно — копья вверх
	voice.apply_text("копейщики вольно")
	await pframes(3)
	verdict("C2 «вольно» → копейщики снова в стойке атаки", _count(sp["men"], in_def) == 0)

	# 3. Лучники в атаку: только лучники, горн
	var ar_c0: Vector3 = _centroid(ar["men"])
	voice.apply_text("лучники в атаку")
	await pframes(3)
	var ar_ahead: int = _count(ar["men"], func(u): return u.move_target.x > u.global_position.x + 30.0)
	verdict("C3 «лучники в атаку» → идут только лучники, цель в 40 м по курсу",
		_count(ar["men"], is_moving) == 8 and ar_ahead == 8 and _count(sp["men"], is_moving) == 0 and _count(wr["men"], is_moving) == 0,
		"лучники идут %d/8 (цель впереди у %d), копейщики %d, мечники %d" % [_count(ar["men"], is_moving), ar_ahead, _count(sp["men"], is_moving), _count(wr["men"], is_moving)])
	verdict("C3б на атаку звучит горн", String(voice.last_voice_event) == "horn_attack", String(voice.last_voice_event))
	await pframes(120)
	verdict("C3в лучники реально продвинулись", _centroid(ar["men"]).x - ar_c0.x > 2.0,
		"сдвиг %.1f м" % (_centroid(ar["men"]).x - ar_c0.x))

	# 4. Все стоять — лучники встают
	voice.apply_text("все стоять")
	await pframes(6)
	verdict("C4 «все стоять» → никто не идёт", _count(ar["men"], is_moving) == 0 and _count(sp["men"], is_moving) == 0
		and _count(wr["men"], is_moving) == 0, "идут: лучники %d, копейщики %d, мечники %d" % [
			_count(ar["men"], is_moving), _count(sp["men"], is_moving), _count(wr["men"], is_moving)])
	verdict("C4б «стоять» не трогает стойку", _count(sp["men"], in_def) == 0)
	verdict("C4в на «стоять» — клич, не горн", String(voice.last_voice_event) == "battle_cry")

	# 5. Мечники вперёд — 20 м, стойка как была
	voice.apply_text("мечники вперёд")
	await pframes(3)
	var wr_20: int = _count(wr["men"], func(u): return absf((u.move_target.x - u.global_position.x) - _Cfg.FORWARD_M) < 1.0)
	verdict("C5 «мечники вперёд» → мечники идут ровно на 20 м, остальные стоят",
		_count(wr["men"], is_moving) == 8 and wr_20 == 8 and _count(ar["men"], is_moving) == 0 and _count(sp["men"], is_moving) == 0,
		"мечники идут %d (20 м у %d)" % [_count(wr["men"], is_moving), wr_20])
	voice.apply_text("все стоять")
	await pframes(6)

	print("\n═════ D. ОТХОД ФАЛАНГИ ═════")
	voice.apply_text("копейщики держать позицию")
	await pframes(3)
	var sp_c0: Vector3 = _centroid(sp["men"])
	voice.apply_text("копейщики отступать на двадцать метров")
	await pframes(3)
	var back20: int = _count(sp["men"], func(u): return absf((u.global_position.x - u.move_target.x) - 20.0) < 1.0)
	verdict("D1 сразу после приказа копья подняты (стойка атаки) и цель в 20 м позади",
		_count(sp["men"], in_def) == 0 and back20 == 12 and bool(voice.reform_pending(int(sp["sid"]))),
		"в обороне %d, цель в 20 м у %d, ожидание опускания=%s" % [_count(sp["men"], in_def), back20, str(voice.reform_pending(int(sp["sid"])))])
	# Ждём прихода по СВОЙСТВУ: все встали, с потолком в физкадрах
	var arrived := false
	for _i in range(60 * 25):
		await get_tree().physics_frame
		if _count(sp["men"], is_moving) == 0 and not bool(voice.reform_pending(int(sp["sid"]))):
			arrived = true
			break
	await pframes(5)
	var sp_c1: Vector3 = _centroid(sp["men"])
	var faced: int = _count(sp["men"], func(u): return u._facing.dot(course) > 0.9)
	verdict("D2 отряд отошёл назад примерно на 20 м", arrived and absf((sp_c0.x - sp_c1.x) - 20.0) < 3.0,
		"сдвиг %.1f м, пришли=%s" % [sp_c0.x - sp_c1.x, str(arrived)])
	verdict("D3 по приходу копья снова опущены (стойка обороны)", _count(sp["men"], in_def) == 12,
		"в обороне %d из 12" % _count(sp["men"], in_def))
	verdict("D4 по приходу отряд смотрит на противника (по курсу)", faced >= 10, "лицом по курсу %d из 12" % faced)

	print("\n═════ E. ГРАНИЦЫ ═════")
	verdict("E1 рабочие не получили ни одного приказа",
		_count(wk["men"], func(u): return u.state == Unit.State.MOVING) == 0)
	var en_def: int = _count(en["men"], in_def)
	verdict("E2 копейщики противника не тронуты (стойки как до приказов)", en_def == en_def0,
		"в обороне было %d, стало %d" % [en_def0, en_def])
	var n_before: int = int(voice.commands_applied)
	var r4: Dictionary = voice.apply_text("принеси кофе")
	verdict("E3 непонятая фраза не даёт приказа и честно показывается",
		int(voice.commands_applied) == n_before and String(r4["intent"]) == ""
		and String(voice.shown_text()).begins_with("не понял"),
		"плашка: «%s»" % String(voice.shown_text()))

	print("\n═════ F. РАСПОЗНАВАНИЕ ПО ЗАПИСЯМ (если есть образцы) ═════")
	var samples: Array = _wav_samples()
	if samples.is_empty():
		print("  образцов нет — блок пропущен (положите WAV PCM16 моно 16 кГц в qa_voice_cmd/samples)")
	elif not ready:
		verdict("F0 распознаватель готов для образцов", false)
	else:
		var hits := 0
		var detail := ""
		for smp in samples:
			var pcm: PackedInt32Array = _read_wav16(String(smp["path"]))
			var text: String = String(voice.recognize_pcm16k(pcm))
			var m: Dictionary = _Cfg.match(text)
			var okp: bool = String(m["intent"]) == String(smp["intent"])
			if okp: hits += 1
			detail += " [%s → «%s» → %s%s]" % [String(smp["name"]), text, String(m["intent"]), "" if okp else " ✗"]
		verdict("F1 записи распознаются в нужные намерения (%d из %d)" % [hits, samples.size()],
			hits == samples.size(), detail)

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 78), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_VOICE_CMD DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

## Образцы: имя файла до .wav — фраза с подчёркиваниями, намерение из словаря
func _wav_samples() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://qa_voice_cmd/samples")
	if dir == null:
		return out
	for f in dir.get_files():
		var fn: String = String(f)
		if not fn.ends_with(".wav"):
			continue
		var phrase: String = fn.trim_suffix(".wav").replace("_", " ")
		out.append({"name": fn, "path": "res://qa_voice_cmd/samples/" + fn,
			"intent": String(_Cfg.match(phrase)["intent"])})
	return out

## PCM16 моно 16 кГц из простого RIFF: ищем чанк data, читаем int16
func _read_wav16(path: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	var pos := 12
	while pos + 8 <= bytes.size():
		var tag: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(pos + 4)
		if tag == "data":
			var n: int = size / 2
			out.resize(n)
			for i in range(n):
				out[i] = bytes.decode_s16(pos + 8 + i * 2)
			break
		pos += 8 + size + (size & 1)
	return out

func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o
