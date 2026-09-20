extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ГОЛОСОВОЕ УПРАВЛЕНИЕ БЕЗ МИКРОФОНА (headless)
## ═══════════════════════════════════════════════════════════════════════════
## Микрофона в headless нет, и это не мешает проверить всё, кроме самого
## распознавания: словарь и сопоставление (текст → намерение и группы),
## словарь малой модели Vosk (таблица символов graph/Gr.fst), область действия
## (выделение, иначе кадр камеры) и фильтр рода войск поверх неё, крестовину
## по осям экрана с единым шагом, «отступать» обратно последнему вектору,
## «держать строй» всем родам области (оборона + остановка + смыкание),
## последовательность отхода фаланги, горн на атаку, обратную связь,
## положение иконки V и плашки (правый нижний угол, шрифт 24) и живость
## распознавателя (модель грузится в фоне, поток не роняет главный).
## Сам звук проверяется ушами в окне: V, сказать, отпустить.
##   A  словарь, сопоставление, словарь модели
##   B  распознаватель: объект, модель, готовность, без ошибок, модуль подключён
##   C  область действия и фильтр рода; «держать строй» всем родам; «вольно»
##   D  крестовина: четыре направления по осям экрана, единый шаг, строй целиком
##   E  «отступать»: обратно последнему вектору, повтор, без вектора — от врага,
##      фаланга: копья вверх → отход → копья вниз
##   F  интерфейс: иконка и плашка в правом нижнем углу
##   G  границы: рабочие и чужие не тронуты, непонятая фраза
##   H  распознавание по WAV-образцам (если есть)

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

func _mk_squad(kind: String, scene: String, fac: int, at: Vector3, n: int, course: Vector3,
		with_formation: bool = true) -> Dictionary:
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
	if with_formation:
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

## Сколько бойцов получили цель хода со смещением (dx, dz) ± tol от своей точки
func _shifted(men: Array, dx: float, dz: float, tol: float = 1.0) -> int:
	return _count(men, func(u):
		var d: Vector3 = u.move_target - u.global_position
		return absf(d.x - dx) < tol and absf(d.z - dz) < tol)

## Разброс вектора сдвига по составу (строй переносится целиком — ноль)
func _shift_spread(men: Array) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for u in men:
		if not is_instance_valid(u):
			continue
		var d: Vector3 = (u as Unit).move_target - (u as Unit).global_position
		lo = Vector2(minf(lo.x, d.x), minf(lo.y, d.z))
		hi = Vector2(maxf(hi.x, d.x), maxf(hi.y, d.z))
	return maxf(hi.x - lo.x, hi.y - lo.y)

## Словарь модели: таблица символов OpenFST в graph/Gr.fst (магическое число,
## имя, available_key, size, затем size записей «строка с 4-байтовым префиксом
## длины + int64»). Именно так 19.09.2026 сверялся словарь; «мечники» и
## «вперед» без ё в нём нет — это известные факты, по ним проба и проверена
func _model_vocab() -> Dictionary:
	var out: Dictionary = {}
	var dir: String = _Voice.model_path()
	if dir == "":
		return out
	var f := FileAccess.open(dir.path_join("graph").path_join("Gr.fst"), FileAccess.READ)
	if f == null:
		return out
	var data: PackedByteArray = f.get_buffer(mini(f.get_length(), 12 * 1024 * 1024))
	f.close()
	var magic := PackedByteArray([0x74, 0xFB, 0xB2, 0x7E])   # 2125658996 LE
	var pos := -1
	for i in range(0, mini(data.size() - 4, 4096)):
		if data[i] == magic[0] and data[i + 1] == magic[1] and data[i + 2] == magic[2] and data[i + 3] == magic[3]:
			pos = i
			break
	if pos < 0:
		return out
	pos += 4
	var nlen: int = data.decode_s32(pos); pos += 4 + nlen
	pos += 8   # available_key
	var size: int = int(data.decode_s64(pos)); pos += 8
	for _k in range(size):
		if pos + 4 > data.size():
			break
		var ln: int = data.decode_s32(pos); pos += 4
		if ln < 0 or pos + ln + 8 > data.size():
			break
		var w: String = data.slice(pos, pos + ln).get_string_from_utf8()
		pos += ln + 8
		out[w] = true
	return out

func _run() -> void:
	var guard := Timer.new()
	guard.wait_time = 180.0
	guard.one_shot = true
	guard.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 180 с")
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
		["копья держать строй", "defense", ["spearman"]],
		["лучники держать строй", "defense", ["archer"]],
		["держать строй", "defense", ["all"]],
		["копейщики в атаку", "attack", ["spearman"]],
		["лучники в атаку", "attack", ["archer"]],
		["луки в атаку", "attack", ["archer"]],
		["стрелки бей", "attack", ["archer"]],
		["мечники напасть", "attack", ["warrior"]],
		["мечи в атаку", "attack", ["warrior"]],
		["рыцари в атаку", "attack", ["warrior"]],
		["пехота вперёд в атаку", "attack", ["warrior"]],
		["вверх в атаку", "attack", ["all"]],
		["копейщики вперёд", "forward", ["spearman"]],
		["фаланга марш", "forward", ["spearman"]],
		["все вперёд", "forward", ["all"]],
		["вперёд", "forward", ["all"]],
		["вправо", "forward", ["all"]],
		["право", "forward", ["all"]],
		["лук вправо", "forward", ["archer"]],
		["назад", "back", ["all"]],
		["влево", "back", ["all"]],
		["лево", "back", ["all"]],
		["мечи назад", "back", ["warrior"]],
		["вверх", "up", ["all"]],
		["наверх", "up", ["all"]],
		["копья вверх", "up", ["spearman"]],
		["вниз", "down", ["all"]],
		["рыцари вниз", "down", ["warrior"]],
		["копейщики отступать", "retreat", ["spearman"]],
		["отступать назад", "retreat", ["all"]],
		["копейщики отступать на двадцать метров", "retreat", ["spearman"]],
		["лучники назад на тридцать метров", "back", ["archer"]],
		["все стоять", "stop", ["all"]],
		["копейщики стой", "stop", ["spearman"]],
		["мечники стоп", "stop", ["warrior"]],
		["копейщики вольно", "at_ease", ["spearman"]],
		["фаланга отбой", "at_ease", ["spearman"]],
		["поднять копья", "at_ease", ["spearman"]],
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
	var mfwd: Dictionary = _Cfg.match("вперёд")
	verdict("A2 число метров разбирается, без числа — единый шаг VOICE_STEP_M",
		float(m20["distance"]) == 20.0 and float(m30["distance"]) == 30.0
		and float(mdef["distance"]) == _Cfg.VOICE_STEP_M and float(mfwd["distance"]) == _Cfg.VOICE_STEP_M,
		"20→%.0f, 30→%.0f, умолчание→%.0f, вперёд→%.0f" % [float(m20["distance"]), float(m30["distance"]),
			float(mdef["distance"]), float(mfwd["distance"])])
	verdict("A2б единый шаг: FORWARD_M = RETREAT_DEFAULT_M = VOICE_STEP_M > 0",
		_Cfg.FORWARD_M == _Cfg.VOICE_STEP_M and _Cfg.RETREAT_DEFAULT_M == _Cfg.VOICE_STEP_M and _Cfg.VOICE_STEP_M > 0.0,
		"VOICE_STEP_M = %.0f" % _Cfg.VOICE_STEP_M)
	var gw: Array = _Cfg.grammar_words()
	var dup := false
	var seen: Dictionary = {}
	for w in gw:
		if seen.has(w): dup = true
		seen[w] = true
	verdict("A3 грамматика собрана из того же словаря: слов %d, [unk] есть, дублей нет" % gw.size(),
		gw.size() >= 60 and gw.has("[unk]") and not dup)
	verdict("A4 короткие основы требуют точного слова",
		String(_Cfg.match("всегда стойкость")["intent"]) == "" and String(_Cfg.match("лукавый")["intent"]) == ""
		and not (_Cfg.match("лукавый вперёд")["groups"] as Array).has("archer"))
	verdict("A5 пустая фраза — не приказ", String(_Cfg.match("")["intent"]) == ""
		and (_Cfg.match("")["groups"] as Array).is_empty())
	var vocab: Dictionary = _model_vocab()
	if vocab.is_empty():
		print("  словарь модели не прочитан — A6 пропущена (модели нет или формат графа другой)")
	else:
		var missing: Array = []
		for w in gw:
			if String(w) != "[unk]" and not vocab.has(String(w)):
				missing.append(w)
		verdict("A6 каждое слово грамматики есть в словаре модели (слов в модели %d)" % vocab.size(),
			missing.is_empty() and vocab.has("копейщики") and not vocab.has("мечники"),
			"нет в модели: %s" % str(missing))

	print("\n═════ B. РАСПОЗНАВАТЕЛЬ И ПОДКЛЮЧЕНИЕ МОДУЛЯ ═════")
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	GameManager.world_bounds_enabled = false
	var voice = main.voice
	verdict("B1 узел голосового управления поднят вместе с партией", voice != null and voice is _Voice)
	var model_dir: String = _Voice.model_path()
	verdict("B2 модель найдена на диске", model_dir != "", model_dir)
	verdict("B2б кнопка V, ввод микрофона включён в проекте, нативная libvosk рядом со сборкой",
		int(voice.PTT_KEY) == KEY_V and bool(ProjectSettings.get_setting("audio/driver/enable_input", false))
		and FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join(".godot/mono/temp/bin/Debug/libvosk.dll")))
	# ── МОДЕЛЬ В СОБРАННОЙ ИГРЕ (хотфикс 20.09.2026) ───────────────────────
	# PCK модель не содержит: нативной libvosk нужен настоящий путь на диске.
	# Значит, поиск ОБЯЗАН смотреть рядом с .exe и в папке данных экспорта —
	# иначе в раздаче голос молча исчезает, что однажды и случилось
	var dirs: Array = _Voice.model_dirs()
	var exe_root: String = OS.get_executable_path().get_base_dir().path_join("voice_models")
	verdict("B2в модель ищется и рядом с .exe, и в папке данных экспорта, и в user://",
		dirs.size() >= 3 and dirs.has(exe_root)
		and String(dirs[dirs.size() - 1]).ends_with("voice_models"),
		"мест поиска %d" % dirs.size())
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

	print("\n═════ C. ОБЛАСТЬ ДЕЙСТВИЯ И ФИЛЬТР РОДА ═════")
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
	# Отряд ВНЕ КАДРА: в ста метрах по Z от фокуса камеры
	var far: Dictionary = _mk_squad("spearman", "res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, Vector3(-25, 0, 80), 8, course)
	var en: Dictionary = _mk_squad("spearman", "res://scenes/units/Spearman.tscn",
		Constants.FACTION_ENEMY, Vector3(40, 0, -25), 8, Vector3(-1, 0, 0))
	await pframes(10)
	for u in sp["men"]:
		(u as Unit).set_stance("attack")
	for u in far["men"]:
		(u as Unit).set_stance("attack")
	var en_def0: int = _count(en["men"], func(u): return u.stance == "defense")
	var is_moving := func(u): return u.state == Unit.State.MOVING
	var in_def := func(u): return u.stance == "defense"
	# Камера — над тремя отрядами, зум средний: полоса земли ~70 × 56 м
	var cam = get_viewport().get_camera_3d()
	verdict("C0 камера партии есть", cam != null)
	if cam != null:
		cam.jump_to(Vector3(-25, 0, -20), 40.0)
	await frames(3)
	var sm = main.selection_manager
	sm.select_units([])
	var in_view_sids: Array = voice.squads_for(["all"])
	verdict("C0а выделение пусто — область = боевые отряды В КАДРЕ: копейщики, лучники, мечники (3), без рабочих и без отряда за кадром",
		in_view_sids.size() == 3 and in_view_sids.has(int(sp["sid"])) and in_view_sids.has(int(ar["sid"]))
		and in_view_sids.has(int(wr["sid"])) and not in_view_sids.has(int(far["sid"])) and not in_view_sids.has(int(wk["sid"]))
		and String(voice.last_area) == "view",
		"в кадре: %s (sp %d, ar %d, wr %d, far %d, wk %d), область=%s" % [str(in_view_sids), int(sp["sid"]), int(ar["sid"]),
			int(wr["sid"]), int(far["sid"]), int(wk["sid"]), String(voice.last_area)])
	verdict("C0б проверка кадра честная: центр копейщиков виден, центр дальнего отряда — нет",
		bool(voice.in_view(_centroid(sp["men"]))) and not bool(voice.in_view(_centroid(far["men"]))))
	verdict("C0в фильтр рода поверх кадра: «лучники» — один отряд, «копейщики» — один (дальний вне кадра)",
		voice.squads_for(["archer"]).size() == 1 and int(voice.squads_for(["archer"])[0]) == int(ar["sid"])
		and voice.squads_for(["spearman"]).size() == 1 and int(voice.squads_for(["spearman"])[0]) == int(sp["sid"]))
	sm.select_units(sp["men"])
	verdict("C0г выделены одни копейщики — «все» это они, «лучники» пусто (в кадр не падаем), область=selection",
		voice.squads_for(["all"]).size() == 1 and int(voice.squads_for(["all"])[0]) == int(sp["sid"])
		and voice.squads_for(["archer"]).is_empty() and String(voice.last_area) == "selection")
	sm.select_units(wk["men"])
	verdict("C0д выделены одни рабочие — боевого выделения нет, область снова кадр (3)",
		voice.squads_for(["all"]).size() == 3 and String(voice.last_area) == "view")
	var everyone: Array = []
	everyone.append_array(sp["men"]); everyone.append_array(ar["men"])
	everyone.append_array(wr["men"]); everyone.append_array(wk["men"])
	sm.select_units(everyone)
	verdict("C0е полное выделение: копейщики 1, лучники 1, мечники 1, все боевые 3 (рабочие вне)",
		voice.squads_for(["spearman"]).size() == 1 and voice.squads_for(["archer"]).size() == 1
		and voice.squads_for(["warrior"]).size() == 1 and voice.squads_for(["all"]).size() == 3,
		"все: %s" % str(voice.squads_for(["all"])))

	# 1. Оборона только копейщикам — по слову рода
	voice.apply_text("копейщики держать позицию")
	await pframes(3)
	verdict("C1 «копейщики держать позицию» → копейщики в обороне, остальные нет",
		_count(sp["men"], in_def) == 12 and _count(ar["men"], in_def) == 0 and _count(wr["men"], in_def) == 0,
		"копейщики %d/12, лучники %d, мечники %d" % [_count(sp["men"], in_def), _count(ar["men"], in_def), _count(wr["men"], in_def)])
	verdict("C1б плашка показала распознанный текст", String(voice.shown_text()) == "копейщики держать позицию")

	# 1в. «ДЕРЖАТЬ СТРОЙ» БЕЗ РОДА — ВСЕМ ОТРЯДАМ ОБЛАСТИ (ТЗ 19.09.2026, блок 6;
	# разворот спринта 18, письмо 4 «защита только копейщикам»): лучники
	# бросают марш и встают, мечники бросают цель, все три в обороне
	voice.apply_text("копейщики вольно")
	await pframes(3)
	var ar_goal := Vector3(0.0, 0.0, 60.0)
	for ua in ar["men"]:
		(ua as Unit).command_move(ar_goal, false, Vector3.ZERO, false, true)
	for uw in wr["men"]:
		(uw as Unit).command_attack(en["men"][0], true, false, true)
	await pframes(3)
	var wr_tgt0: int = _count(wr["men"], func(u): return u.attack_target != null)
	voice.apply_text("держать строй")
	await pframes(3)
	var ar_far: int = _count(ar["men"], func(u): return u.state == Unit.State.MOVING and u.move_target.distance_to(ar_goal) < 1.0)
	var wr_tgt: int = _count(wr["men"], func(u): return u.attack_target != null)
	verdict("C1в «держать строй» без рода: ВСЕ три отряда в обороне, лучники бросили дальний марш, мечники бросили цель",
		_count(sp["men"], in_def) == 12 and _count(ar["men"], in_def) == 8 and _count(wr["men"], in_def) == 8
		and ar_far == 0 and wr_tgt == 0 and wr_tgt0 == 8,
		"в обороне: копейщики %d/12, лучники %d/8, мечники %d/8; лучников в дальнем марше %d, целей у мечников %d (было %d)" % [
			_count(sp["men"], in_def), _count(ar["men"], in_def), _count(wr["men"], in_def), ar_far, wr_tgt, wr_tgt0])
	verdict("C1г «деф» тоже понимается как защита", String(_Cfg.match("деф")["intent"]) == "defense")
	await pframes(60)
	# 1д. Смыкание: четверо копейщиков сдвинуты на 6 м вбок — «держать строй»
	# зовёт их на места разметки
	voice.apply_text("копейщики вольно")
	await pframes(60)
	var moved4: Array = []
	for i in range(4):
		var um := sp["men"][i * 3] as Unit
		um.global_position = um.global_position + Vector3(0, 0, 6.0)
		um.sync_row()
		moved4.append(um)
	await pframes(2)
	voice.apply_text("копейщики держать строй")
	await pframes(3)
	# Смыкание (squad_close_ranks → _slots_recentered) переносит разметку на
	# СРЕДНИЙ сдвиг состава, а не на медиану: считаем тот же сдвиг и сверяем
	# цели хода с перенесёнными местами
	var slots_sp: Array = (GameManager.squads[int(sp["sid"])] as Dictionary).get("slots", [])
	var mean_men := Vector3.ZERO
	for um2 in sp["men"]:
		mean_men += (um2 as Node3D).global_position
	mean_men /= float(sp["men"].size())
	var mean_slots := Vector3.ZERO
	for s0 in slots_sp:
		mean_slots += (s0 as Vector3)
	mean_slots /= maxf(float(slots_sp.size()), 1.0)
	var delta_sl: Vector3 = mean_men - mean_slots
	delta_sl.y = 0.0
	var to_slot: int = _count(moved4, func(u):
		if u.state != Unit.State.MOVING:
			return false
		for s in slots_sp:
			var t2: Vector3 = (s as Vector3) + delta_sl
			if Vector2(t2.x - u.move_target.x, t2.z - u.move_target.z).length() < 1.5:
				return true
		return false)
	verdict("C1д «держать строй» смыкает строй: сдвинутые бойцы идут на места разметки (%d из 4)" % to_slot,
		to_slot >= 3 and _count(sp["men"], in_def) == 12, "идут на место %d из 4, в обороне %d/12" % [to_slot, _count(sp["men"], in_def)])
	for _w in range(60 * 8):
		await get_tree().physics_frame
		if _count(moved4, is_moving) == 0:
			break
	await pframes(3)
	# 1е. Фильтр рода внутри выделения: «вольно» всем, потом оборона одним лучникам
	voice.apply_text("вольно")
	await pframes(3)
	verdict("C1е «вольно» → все три отряда в стойке атаки",
		_count(sp["men"], in_def) == 0 and _count(ar["men"], in_def) == 0 and _count(wr["men"], in_def) == 0)
	voice.apply_text("лучники держать строй")
	await pframes(3)
	verdict("C1ж «лучники держать строй» при полном выделении — в обороне только лучники",
		_count(ar["men"], in_def) == 8 and _count(sp["men"], in_def) == 0 and _count(wr["men"], in_def) == 0,
		"лучники %d/8, копейщики %d, мечники %d" % [_count(ar["men"], in_def), _count(sp["men"], in_def), _count(wr["men"], in_def)])
	voice.apply_text("вольно")
	await pframes(3)
	verdict("C2 «вольно» → лучники снова в стойке атаки", _count(ar["men"], in_def) == 0)

	# 3. Лучники в атаку: только лучники, горн
	voice.apply_text("лучники в атаку")
	await pframes(3)
	var ar_ahead: int = _count(ar["men"], func(u): return u.move_target.x > u.global_position.x + 30.0)
	verdict("C3 «лучники в атаку» → идут только лучники, цель в 40 м по курсу (врага в 34 м нет — марш)",
		_count(ar["men"], is_moving) == 8 and ar_ahead == 8 and _count(sp["men"], is_moving) == 0 and _count(wr["men"], is_moving) == 0,
		"лучники идут %d/8 (цель впереди у %d), копейщики %d, мечники %d" % [_count(ar["men"], is_moving), ar_ahead, _count(sp["men"], is_moving), _count(wr["men"], is_moving)])
	verdict("C3б на атаку звучит горн", String(voice.last_voice_event) == "horn_attack", String(voice.last_voice_event))
	await pframes(120)
	var ar_c0: Vector3 = _centroid(ar["men"])
	verdict("C3в лучники реально продвинулись", ar_c0.x - (-30.0) > 2.0,
		"центр x = %.1f (старт −30)" % ar_c0.x)
	voice.apply_text("все стоять")
	await pframes(6)
	verdict("C4 «все стоять» → никто не идёт", _count(ar["men"], is_moving) == 0 and _count(sp["men"], is_moving) == 0
		and _count(wr["men"], is_moving) == 0, "идут: лучники %d, копейщики %d, мечники %d" % [
			_count(ar["men"], is_moving), _count(sp["men"], is_moving), _count(wr["men"], is_moving)])
	verdict("C4б «стоять» не трогает стойку", _count(sp["men"], in_def) == 0)
	verdict("C4в на «стоять» — клич, не горн", String(voice.last_voice_event) == "battle_cry")

	print("\n═════ D. КРЕСТОВИНА ПО ОСЯМ ЭКРАНА ═════")
	var right: Vector3 = voice.screen_right()
	var up: Vector3 = voice.screen_up()
	verdict("D0 оси экрана взяты у камеры: право = X+ мира, верх = Z− (ракурс зафиксирован)",
		right.distance_to(Vector3(1, 0, 0)) < 0.01 and up.distance_to(Vector3(0, 0, -1)) < 0.01,
		"right=%s up=%s" % [str(right), str(up)])
	var step: float = _Cfg.VOICE_STEP_M
	sm.select_units(sp["men"])
	voice.apply_text("копейщики вперёд")
	await pframes(2)
	var f_ok: int = _shifted(sp["men"], step * right.x, step * right.z)
	verdict("D1 «вперёд» → сдвиг ВПРАВО по экрану на VOICE_STEP_M у всех (%d/12), строй целиком (разброс %.2f м)" % [f_ok, _shift_spread(sp["men"])],
		f_ok == 12 and _shift_spread(sp["men"]) < 0.5 and _count(sp["men"], is_moving) == 12
		and voice.last_vec(int(sp["sid"])).distance_to(right) < 0.01
		and GameManager.squad_course(int(sp["sid"])).distance_to(right) < 0.01,
		"last_vec=%s, курс=%s" % [str(voice.last_vec(int(sp["sid"]))), str(GameManager.squad_course(int(sp["sid"])))])
	voice.apply_text("копейщики стоять")
	await pframes(6)
	voice.apply_text("копейщики вверх")
	await pframes(2)
	var u_ok: int = _shifted(sp["men"], step * up.x, step * up.z)
	verdict("D2 «вверх» → сдвиг вверх по экрану на тот же шаг (%d/12)" % u_ok, u_ok == 12
		and voice.last_vec(int(sp["sid"])).distance_to(up) < 0.01)
	voice.apply_text("копейщики стоять")
	await pframes(6)
	voice.apply_text("копейщики вниз")
	await pframes(2)
	var d_ok: int = _shifted(sp["men"], -step * up.x, -step * up.z)
	verdict("D3 «вниз» → сдвиг вниз по экрану на тот же шаг (%d/12)" % d_ok, d_ok == 12)
	voice.apply_text("копейщики стоять")
	await pframes(6)
	voice.apply_text("копейщики назад")
	await pframes(2)
	var b_ok: int = _shifted(sp["men"], -step * right.x, -step * right.z)
	verdict("D4 «назад» → сдвиг ВЛЕВО по экрану на тот же шаг (%d/12)" % b_ok, b_ok == 12)
	voice.apply_text("копейщики стоять")
	await pframes(6)
	voice.apply_text("копейщики вправо на десять метров")
	await pframes(2)
	var r10: int = _shifted(sp["men"], 10.0 * right.x, 10.0 * right.z)
	verdict("D5 «вправо на десять метров» — алиас «вперёд», названное число перебивает шаг (%d/12)" % r10, r10 == 12)
	voice.apply_text("копейщики стоять")
	await pframes(6)
	# «Мечники вперёд» при выделении одних копейщиков — некому
	var n_app: int = int(voice.commands_applied)
	voice.apply_text("мечники вперёд")
	await pframes(2)
	verdict("D6 «мечники вперёд» при выделенных копейщиках — некому, мечники стоят",
		int(voice.commands_applied) == n_app and _count(wr["men"], is_moving) == 0 and String(voice.shown_text()).begins_with("некому"))

	print("\n═════ E. ОТСТУПАТЬ: ОБРАТНО ПОСЛЕДНЕМУ ВЕКТОРУ ═════")
	voice.apply_text("копейщики вверх")
	await pframes(2)
	voice.apply_text("копейщики отступать")
	await pframes(2)
	var re1: int = _shifted(sp["men"], -step * up.x, -step * up.z)
	var faced_up: int = _count(sp["men"], func(u): return u.face_on_arrive.distance_to(up) < 0.05)
	verdict("E1 шёл вверх — «отступать» ведёт ВНИЗ на тот же шаг (%d/12), лицом туда, откуда отходит (%d/12)" % [re1, faced_up],
		re1 == 12 and faced_up == 12)
	voice.apply_text("копейщики отступать")
	await pframes(2)
	var re2: int = _shifted(sp["men"], -step * up.x, -step * up.z)
	verdict("E2 повторное «отступать» ведёт дальше в ту же сторону, а не разворачивает (%d/12)" % re2, re2 == 12)
	voice.apply_text("копейщики стоять")
	await pframes(6)
	voice.apply_text("копейщики вперёд")
	await pframes(2)
	voice.apply_text("копейщики стоять")
	await pframes(6)
	voice.apply_text("копейщики отступать")
	await pframes(2)
	var re3: int = _shifted(sp["men"], -step * right.x, -step * right.z)
	verdict("E3 шёл вправо — отходит влево (%d/12)" % re3, re3 == 12)
	voice.apply_text("копейщики стоять")
	await pframes(6)
	# Отряд без голосового вектора и без курса разметки: прочь от ближайшего врага
	var st: Dictionary = _mk_squad("warrior", "res://scenes/units/Warrior.tscn",
		Constants.FACTION_PLAYER, Vector3(-10, 0, -60), 6, Vector3.ZERO, false)
	var en2: Dictionary = _mk_squad("spearman", "res://scenes/units/Spearman.tscn",
		Constants.FACTION_ENEMY, Vector3(-10, 0, -35), 6, Vector3(0, 0, -1))
	await pframes(3)
	sm.select_units(st["men"])
	var course_st: Vector3 = GameManager.squad_course(int(st["sid"]))
	voice.apply_text("отступать")
	await pframes(2)
	var re4: int = _shifted(st["men"], 0.0, -step, 1.5)
	verdict("E4 стоял без курса — «отступать» уводит прочь от ближайшего врага (враг на +Z, ушли на −Z: %d/6)" % re4,
		re4 == 6 and course_st.length_squared() < 1e-6, "курс до приказа %s" % str(course_st))
	voice.apply_text("стоять")
	await pframes(6)
	for u in en2["men"]:
		if is_instance_valid(u):
			(u as Unit).set_tick(false)
	for u in st["men"]:
		if is_instance_valid(u):
			(u as Unit).set_tick(false)

	print("═════ E5. ОТХОД ФАЛАНГИ КАК ПОСЛЕДОВАТЕЛЬНОСТЬ ═════")
	sm.select_units(sp["men"])
	voice.apply_text("копейщики вперёд")
	await pframes(2)
	voice.apply_text("копейщики стоять")
	await pframes(6)
	voice.apply_text("копейщики держать позицию")
	await pframes(3)
	var sp_c0: Vector3 = _centroid(sp["men"])
	voice.apply_text("копейщики отступать на двадцать метров")
	await pframes(3)
	var back20: int = _shifted(sp["men"], -20.0 * right.x, -20.0 * right.z)
	verdict("E5а сразу после приказа копья подняты (стойка атаки) и цель в 20 м позади (обратно «вперёд»)",
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
	var faced: int = _count(sp["men"], func(u): return u._facing.dot(right) > 0.9)
	verdict("E5б отряд отошёл влево примерно на 20 м", arrived and absf((sp_c0.x - sp_c1.x) - 20.0) < 3.0,
		"сдвиг %.1f м, пришли=%s" % [sp_c0.x - sp_c1.x, str(arrived)])
	verdict("E5в по приходу копья снова опущены (стойка обороны)", _count(sp["men"], in_def) == 12,
		"в обороне %d из 12" % _count(sp["men"], in_def))
	verdict("E5г по приходу отряд смотрит туда, откуда отошёл (вправо)", faced >= 10, "лицом вправо %d из 12" % faced)

	print("\n═════ F. ИНТЕРФЕЙС: ПРАВЫЙ НИЖНИЙ УГОЛ ═════")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	voice.apply_text("копейщики вольно")
	await frames(3)
	var mr: Rect2 = voice.mic_rect()
	var tr: Rect2 = voice.text_rect()
	print("  [F] столбик %s, плашка %s, иконка %s, экран %s" % [str(voice._ui_box.get_global_rect()), str(tr), str(mr), str(vp)])
	verdict("F1 иконка V в правом нижнем углу (внутри экрана, правее и ниже середины)",
		mr.size.x > 0.0 and mr.end.x <= vp.x + 0.5 and mr.end.y <= vp.y + 0.5
		and mr.position.x > vp.x * 0.5 and mr.position.y > vp.y * 0.5,
		"иконка %s, экран %s" % [str(mr), str(vp)])
	verdict("F2 плашка текста рядом с иконкой: у правого края, над иконкой, не ниже её",
		tr.size.x > 0.0 and tr.end.x <= vp.x + 0.5 and tr.end.y <= mr.position.y + 0.5
		and tr.position.x > vp.x * 0.5 and tr.position.y > vp.y * 0.5,
		"плашка %s, иконка %s" % [str(tr), str(mr)])
	verdict("F3 шрифт плашки компактный — 24 px", int(voice.text_font_px()) == 24, "%d px" % int(voice.text_font_px()))
	var hud = main.hud
	var bp = hud.get("_bottom_panel") if hud != null else null
	var bp_rect: Rect2 = (bp as Control).get_global_rect() if bp != null and is_instance_valid(bp) else Rect2()
	verdict("F4 с нижней панелью выделения (слева) не пересекаются ни иконка, ни плашка",
		bp != null and not bp_rect.intersects(mr) and not bp_rect.intersects(tr),
		"панель %s" % str(bp_rect))

	print("\n═════ G. ГРАНИЦЫ ═════")
	verdict("G1 рабочие не получили ни одного приказа",
		_count(wk["men"], func(u): return u.state == Unit.State.MOVING) == 0)
	var en_def: int = _count(en["men"], in_def)
	verdict("G2 копейщики противника не тронуты (стойки как до приказов)", en_def == en_def0,
		"в обороне было %d, стало %d" % [en_def0, en_def])
	verdict("G3 отряд за кадром без выделения ни разу не сдвинулся",
		_count(far["men"], func(u): return u.global_position.distance_to(Vector3(-25, 0, 80)) > 6.0) == 0)
	var n_before: int = int(voice.commands_applied)
	var r4: Dictionary = voice.apply_text("принеси кофе")
	verdict("G4 непонятая фраза не даёт приказа и честно показывается",
		int(voice.commands_applied) == n_before and String(r4["intent"]) == ""
		and String(voice.shown_text()).begins_with("не понял"),
		"плашка: «%s»" % String(voice.shown_text()))

	print("\n═════ H. РАСПОЗНАВАНИЕ ПО ЗАПИСЯМ (если есть образцы) ═════")
	var samples: Array = _wav_samples()
	if samples.is_empty():
		print("  образцов нет — блок пропущен (положите WAV PCM16 моно 16 кГц в qa_voice_cmd/samples)")
	elif not ready:
		verdict("H0 распознаватель готов для образцов", false)
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
		verdict("H1 записи распознаются в нужные намерения (%d из %d)" % [hits, samples.size()],
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
