extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ЗВУКОВОГО ДВИЖКА
## ═══════════════════════════════════════════════════════════════════════════
##   A ШИНЫ      — Master/Music/SFX существуют, громкость реально меняется
##   B АССЕТЫ    — каждый файл из банка реально грузится
##   C ЛИМИТЕР   — перегруза нет: голоса и паузы соблюдаются
##   D 3D        — слушатель в фокусе камеры, дальний звук не слышно
##   E МУЗЫКА    — меню, лес на старте, подмешивание темы раз в 10 минут
##   F БОЙ       — события боя реально дёргают звук нужных категорий
##   G ПОЛЗУНКИ  — меню паузы отдаёт три ручки и они меняют шины

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n:
		out += " "
	return out

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	# ── ТУМАН ВЫКЛЮЧЕН НАМЕРЕННО ────────────────────────────────────────────
	# Пространственный звук и дрожание ствола теперь ГЛУШАТСЯ вне освещённой
	# зоны (защита от «нахожу базу врага на слух», см. AudioManager._audible_at
	# и ResourceNode.shake). Этот стенд проверяет не туман, а сам звук/дрожь, и
	# ставит свои объекты там, где своих юнитов нет, — то есть в темноте.
	# enabled = false заставляет is_lit отвечать «видно везде» (штатный
	# выключатель FogOfWar), и стенд снова меряет то, ради чего написан.
	# Саму отсечку по туману стережёт qa_fog
	if GameManager.fog != null:
		GameManager.fog.enabled = false

	await _a_buses()
	await _b_assets()
	await _c_limiter()
	await _d_spatial()
	await _e_music()
	await _f_combat()
	await _g_sliders()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 62), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== AUDIO TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ШИНЫ
# ═════════════════════════════════════════════════════════════════════════════
func _a_buses() -> void:
	print("\n═════ A. АУДИО-ШИНЫ ═════")
	var names: Array = []
	for i in range(AudioServer.bus_count):
		names.append(AudioServer.get_bus_name(i))
	print("  шины в движке: %s" % str(names))
	verdict("A1 шина Master есть", AudioServer.get_bus_index("Master") >= 0)
	verdict("A2 шина Music создана", AudioServer.get_bus_index("Music") >= 0)
	verdict("A3 шина SFX создана", AudioServer.get_bus_index("SFX") >= 0)

	var mi: int = AudioServer.get_bus_index("Music")
	var si: int = AudioServer.get_bus_index("SFX")
	print("  Music шлёт в «%s», SFX шлёт в «%s»" % [
		AudioServer.get_bus_send(mi), AudioServer.get_bus_send(si)])
	verdict("A4 обе шины уходят в Master",
		String(AudioServer.get_bus_send(mi)) == "Master"
			and String(AudioServer.get_bus_send(si)) == "Master")

	# Громкость: 0 должен быть НАСТОЯЩЕЙ тишиной, а не «-80 дБ почти тихо»
	AudioManager.set_bus_volume("SFX", 0.5)
	var db_half: float = AudioServer.get_bus_volume_db(si)
	AudioManager.set_bus_volume("SFX", 0.0)
	var muted: bool = AudioServer.is_bus_mute(si)
	AudioManager.set_bus_volume("SFX", 1.0)
	var db_full: float = AudioServer.get_bus_volume_db(si)
	print("  SFX: 50%% → %.2f дБ, 0%% → mute=%s, 100%% → %.2f дБ" % [
		db_half, str(muted), db_full])
	verdict("A5 ползунок реально меняет громкость шины",
		db_half < db_full - 3.0, "%.2f против %.2f дБ" % [db_half, db_full])
	verdict("A6 нулевая громкость это полная тишина (mute)", muted)

	# Сохранение и чтение
	AudioManager.set_bus_volume("Music", 0.33)
	AudioManager.save_settings()
	var cfg := ConfigFile.new()
	var ok: int = cfg.load(AudioManager.SETTINGS_PATH)
	var saved: float = float(cfg.get_value("audio", "Music", -1.0)) if ok == OK else -1.0
	print("  сохранено в %s: Music=%.2f" % [AudioManager.SETTINGS_PATH, saved])
	verdict("A7 настройки пишутся на диск", absf(saved - 0.33) < 0.001,
		"прочитали %.2f" % saved)
	AudioManager.set_bus_volume("Music", 0.8)
	AudioManager.save_settings()

# ═════════════════════════════════════════════════════════════════════════════
# B. АССЕТЫ
# ═════════════════════════════════════════════════════════════════════════════
func _b_assets() -> void:
	print("\n═════ B. АССЕТЫ ═════")
	var missing: Array = []
	var total := 0
	for key in AudioManager.SFX_BANK.keys():
		var cat: String = String(key)
		var files: Array = AudioManager.SFX_BANK[cat]
		for f in files:
			total += 1
			var p: String = AudioManager.DIR_SFX + String(f)
			if not ResourceLoader.exists(p):
				missing.append(p)
	print("  файлов эффектов в банке: %d, не найдено: %d" % [total, missing.size()])
	if not missing.is_empty():
		for m in missing:
			print("    НЕТ: %s" % String(m))
	verdict("B1 все звуки боя и работы на месте", missing.is_empty(),
		"нет %d файлов" % missing.size())

	var mus_ok: bool = ResourceLoader.exists(AudioManager.MUSIC_BACKGROUND)
	var amb_ok: bool = ResourceLoader.exists(AudioManager.AMBIENCE_FOREST)
	print("  тема: %s (%s), лес: %s (%s)" % [
		AudioManager.MUSIC_BACKGROUND, str(mus_ok),
		AudioManager.AMBIENCE_FOREST, str(amb_ok)])
	verdict("B2 основная тема на месте", mus_ok)
	verdict("B3 эмбиент леса на месте", amb_ok)

	# Каждая категория обязана иметь и файлы, и настройки лимитера
	var no_limits: Array = []
	for key in AudioManager.SFX_BANK.keys():
		if not AudioManager.SFX_LIMITS.has(key):
			no_limits.append(String(key))
	verdict("B4 у каждой категории есть настройки лимитера", no_limits.is_empty(),
		"без лимитов: %s" % str(no_limits))

	# Категории из задания
	var want := ["chop", "mine_gold", "mine_stone", "bow_attack", "bow_impact",
		"bow_block", "sword_attack", "sword_hit", "spear_hit", "vox_action",
		"vox_death", "metal_punch"]
	var absent: Array = []
	for w in want:
		if not AudioManager.SFX_BANK.has(w):
			absent.append(String(w))
	verdict("B5 заведены все категории из задания", absent.is_empty(),
		"нет: %s" % str(absent))

# ═════════════════════════════════════════════════════════════════════════════
# C. ОГРАНИЧИТЕЛЬ
# ═════════════════════════════════════════════════════════════════════════════
func _c_limiter() -> void:
	print("\n═════ C. ОГРАНИЧИТЕЛЬ ПЕРЕГРУЗА ═════")
	var at := Vector3.ZERO
	if main._camera != null:
		at = main._camera._focus

	# Пауза между запусками одной категории
	var first: bool = AudioManager.play_3d("sword_hit", at)
	var second: bool = AudioManager.play_3d("sword_hit", at)
	print("  два удара подряд в один кадр: первый=%s, второй=%s" % [str(first), str(second)])
	verdict("C1 пауза между звуками одной категории соблюдается",
		first and not second, "первый=%s, второй=%s" % [str(first), str(second)])

	# Залп: сколько бы событий ни пришло, голосов больше пула не станет
	await frames(2)
	var started := 0
	for i in range(400):
		for cat in ["sword_attack", "sword_hit", "bow_attack", "bow_impact",
				"vox_death", "spear_hit"]:
			if AudioManager.play_3d(String(cat), at + Vector3(float(i % 5), 0.0, 0.0)):
				started += 1
	var playing := 0
	for p in AudioManager._pool:
		if (p as AudioStreamPlayer3D).playing:
			playing += 1
	print("  2400 событий залпом: запущено %d, реально звучит %d (пул %d)" % [
		started, playing, AudioManager.POOL_SIZE])
	verdict("C2 лавина событий не создаёт голосов сверх пула",
		playing <= AudioManager.POOL_SIZE,
		"звучит %d при пуле %d" % [playing, AudioManager.POOL_SIZE])
	verdict("C3 ограничитель отсеивает подавляющее большинство событий",
		started < 60, "прошло %d из 2400" % started)

	# Категории с разными лимитами не воруют голоса друг у друга
	var per_cat: Dictionary = {}
	for i in range(AudioManager._pool.size()):
		if (AudioManager._pool[i] as AudioStreamPlayer3D).playing:
			var c: String = String(AudioManager._pool_cat[i])
			per_cat[c] = int(per_cat.get(c, 0)) + 1
	print("  распределение голосов по категориям: %s" % str(per_cat))
	var over: Array = []
	for key in per_cat.keys():
		var c2: String = String(key)
		var lim: Dictionary = AudioManager.SFX_LIMITS.get(c2, {})
		if int(per_cat[c2]) > int(lim.get("voices", 3)):
			over.append(c2)
	verdict("C4 ни одна категория не превысила свой лимит голосов",
		over.is_empty(), "превысили: %s" % str(over))

	# Неизвестная категория не роняет игру и ничего не запускает
	verdict("C5 неизвестная категория молча игнорируется",
		not AudioManager.play_3d("нет_такой_категории", at))
	await frames(30)

# ═════════════════════════════════════════════════════════════════════════════
# D. 3D-ПОЗИЦИОНИРОВАНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _d_spatial() -> void:
	print("\n═════ D. 3D-ЗВУК И СЛУШАТЕЛЬ ═════")
	var listener: Node = null
	for n in get_tree().get_nodes_in_group("all_units"):
		break
	# Слушатель — ребёнок пивота камеры
	var pivot: Node = main.get_node_or_null("CameraPivot")
	if pivot != null:
		listener = pivot.get_node_or_null("Listener")
	print("  слушатель найден: %s, текущий: %s" % [
		str(listener != null),
		str((listener as AudioListener3D).is_current()) if listener != null else "—"])
	verdict("D1 слушатель стоит в пивоте камеры, а не на самой камере",
		listener != null, "узел Listener не найден")
	verdict("D2 слушатель назначен текущим",
		listener != null and (listener as AudioListener3D).is_current())

	# Камера в ортографии унесена далеко — проверяем, что слух остался у земли
	var cam_dist := 0.0
	var lis_dist := 0.0
	if listener != null and main._camera != null:
		var focus: Vector3 = main._camera._focus
		cam_dist = main._camera.global_position.distance_to(focus)
		lis_dist = (listener as Node3D).global_position.distance_to(focus)
	print("  до точки фокуса: камера %.1f м, слушатель %.1f м" % [cam_dist, lis_dist])
	verdict("D3 слушатель у земли, хотя камера унесена в ортографии",
		lis_dist < 5.0 and cam_dist > 100.0,
		"камера %.1f, слушатель %.1f" % [cam_dist, lis_dist])

	# Настройки самих голосов
	var p0: AudioStreamPlayer3D = AudioManager._pool[0]
	print("  голос: шина «%s», max_distance %.1f м, модель спада %d" % [
		p0.bus, p0.max_distance, p0.attenuation_model])
	verdict("D4 эффекты идут через шину SFX", String(p0.bus) == "SFX")
	# РАДИУС ОБЯЗАН НАКРЫВАТЬ ВЕСЬ ВИДИМЫЙ КАДР, но не всю карту.
	# Нижняя граница — максимальная видимая высота кадра (RTSCamera.max_height):
	# пока порог слышимости был меньше неё, бой на краю экрана оказывался за
	# порогом, и любой сдвиг камеры включал-выключал звук рывком.
	# Верхняя граница — половина карты: слышать сражение через весь мир не надо
	var cam_span: float = main._camera.max_height
	verdict("D5 радиус слышимости накрывает кадр, но не всю карту",
		p0.max_distance >= cam_span and p0.max_distance < main.MAP_HALF_X * 1.5,
		"max_distance %.1f, кадр %.1f м" % [p0.max_distance, cam_span])

	# Звук у рабочих слышен рядом с фокусом и не слышен через полкарты
	await frames(5)
	var near_pos: Vector3 = main._camera._focus
	var far_pos := Vector3(main.MAP_HALF_X - 5.0, 0.0, main.MAP_HALF_Z - 5.0)
	var d_near: float = 0.0
	var d_far: float = 0.0
	if listener != null:
		var lp: Vector3 = (listener as Node3D).global_position
		d_near = lp.distance_to(near_pos)
		d_far  = lp.distance_to(far_pos)
	print("  рабочий у фокуса: %.1f м (порог %.1f), рабочий на другом конце: %.1f м" % [
		d_near, p0.max_distance, d_far])
	verdict("D6 работа у камеры попадает в радиус слышимости",
		d_near < p0.max_distance, "%.1f м" % d_near)
	verdict("D7 работа на другом конце карты за радиусом слышимости",
		d_far > p0.max_distance, "%.1f м" % d_far)

# ═════════════════════════════════════════════════════════════════════════════
# E. МУЗЫКА И ЭМБИЕНТ
# ═════════════════════════════════════════════════════════════════════════════
func _e_music() -> void:
	print("\n═════ E. МУЗЫКА И ЭМБИЕНТ ═════")
	# Старт партии уже случился в Main.start_game()
	var amb: AudioStreamPlayer = AudioManager._ambience
	var mus: AudioStreamPlayer = AudioManager._music
	print("  лес: играет=%s, поток=%s, шина «%s»" % [
		str(amb.playing),
		amb.stream.resource_path.get_file() if amb.stream != null else "нет",
		amb.bus])
	verdict("E1 на старте партии играет лес Forest Day",
		amb.playing and amb.stream != null
			and String(amb.stream.resource_path).contains("Forest Day"),
		"играет=%s" % str(amb.playing))
	verdict("E2 эмбиент идёт по шине Music", String(amb.bus) == "Music")
	verdict("E3 лес зациклен",
		amb.stream is AudioStreamOggVorbis and (amb.stream as AudioStreamOggVorbis).loop)

	print("  до подмешивания темы: %.0f с (интервал %.0f с)" % [
		AudioManager.seconds_to_music(), AudioManager.MUSIC_INTERVAL])
	verdict("E4 таймер темы заведён на 10 минут",
		absf(AudioManager.MUSIC_INTERVAL - 600.0) < 0.01
			and AudioManager.seconds_to_music() > 0.0,
		"интервал %.0f с" % AudioManager.MUSIC_INTERVAL)
	verdict("E5 пока таймер не вышел, тема молчит", not mus.playing)

	# Форсируем подмешивание и смотрим, что оно нарастает плавно и ТИШЕ леса
	AudioManager.force_music_swell()
	await frames(2)
	var db0: float = mus.volume_db
	await frames(60)
	var db1: float = mus.volume_db
	print("  подмешивание: играет=%s, громкость %.1f → %.1f дБ (эмбиент %.1f дБ)" % [
		str(mus.playing), db0, db1, amb.volume_db])
	verdict("E6 тема подмешивается поверх леса", mus.playing and amb.playing)
	verdict("E7 тема нарастает плавно (Fade In)", db1 > db0,
		"%.1f → %.1f дБ" % [db0, db1])
	verdict("E8 тема звучит ТИШЕ эмбиента и не перебивает его",
		AudioManager.MUSIC_UNDER_DB < AudioManager.AMBIENCE_DB,
		"тема %.0f дБ против леса %.0f дБ" % [
			AudioManager.MUSIC_UNDER_DB, AudioManager.AMBIENCE_DB])

	# Меню расы: та же тема, но громко и без леса
	AudioManager.play_menu_music()
	await frames(3)
	print("  меню: тема играет=%s (%s), лес играет=%s" % [
		str(mus.playing),
		mus.stream.resource_path.get_file() if mus.stream != null else "нет",
		str(amb.playing)])
	# ── У МЕНЮ ТЕПЕРЬ СВОЯ ТЕМА ────────────────────────────────────────────
	# Здесь стояло «играет main sound background» — требование, которое
	# владелец развернул: меню получило отдельный трек (AudioManager.MUSIC_MENU).
	# Проверка не выброшена, а переписана на НОВОЕ свойство, и специально не
	# на имя файла: имя — вопрос ассета, а утверждение стенда в том, что меню
	# играет ИМЕННО СВОЮ тему, а не первую из игрового плейлиста
	verdict("E9 в меню расы играет своя тема меню",
		mus.playing and mus.stream != null
			and mus.stream == AudioManager._stream(AudioManager.MUSIC_MENU)
			and not (AudioManager.MUSIC_MENU in AudioManager.MUSIC_PLAYLIST),
		"поток %s" % (mus.stream.resource_path.get_file() if mus.stream != null else "нет"))
	verdict("E10 в меню лес не играет", not amb.playing)
	# Возвращаем игровой режим для остальных разделов
	AudioManager.start_game_audio()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# F. БОЕВЫЕ СОБЫТИЯ РЕАЛЬНО ДЁРГАЮТ ЗВУК
# ═════════════════════════════════════════════════════════════════════════════
func _f_combat() -> void:
	print("\n═════ F. СОБЫТИЯ БОЯ И РАБОТЫ ═════")
	# Категории берём из самих классов: так проверяется проводка, а не догадка
	var sp := Spearman.new()
	sp.faction = Constants.FACTION_PLAYER
	main.world_add(sp)
	var wr := Warrior.new()
	wr.faction = Constants.FACTION_PLAYER
	main.world_add(wr)
	var ar := Archer.new()
	ar.faction = Constants.FACTION_PLAYER
	main.world_add(ar)
	await frames(3)
	print("  копейщик: замах «%s», попадание «%s»" % [sp._sfx_swing(), sp._sfx_hit()])
	print("  мечник:   замах «%s», попадание «%s»" % [wr._sfx_swing(), wr._sfx_hit()])
	print("  лучник:   замах «%s», попадание «%s» (весь звук в тетиве и стреле)" % [
		ar._sfx_swing(), ar._sfx_hit()])
	verdict("F1 копейщик бьёт с шелестом древка (WHSH)", sp._sfx_swing() == "spear_hit")
	verdict("F2 мечник звенит сталью", wr._sfx_swing() == "sword_attack"
		and wr._sfx_hit() == "sword_hit")
	verdict("F3 у лучника нет звука ближнего боя",
		ar._sfx_swing() == "" and ar._sfx_hit() == "")

	# Пустая категория не должна ничего запускать
	verdict("F4 пустая категория не занимает голос",
		not AudioManager.play_3d("", sp.global_position))

	# Смерть бойца обязана дать стон
	await frames(40)
	var before := _playing_of("vox_death")
	var victim := Spearman.new()
	victim.faction = Constants.FACTION_ENEMY
	main.world_add(victim)
	victim.global_position = main._camera._focus
	await frames(3)
	victim.take_damage(99999.0, sp)
	await frames(2)
	var after := _playing_of("vox_death")
	print("  гибель бойца: голосов стона было %d, стало %d" % [before, after])
	verdict("F5 гибель бойца даёт предсмертный стон", after > before,
		"было %d, стало %d" % [before, after])

	# Рубка дерева
	await frames(40)
	var tree := ResourceNode.new()
	tree.resource_type = Constants.RESOURCE_WOOD
	main.world_add(tree)
	tree.global_position = main._camera._focus + Vector3(2.0, 0.0, 0.0)
	var w := Worker.new()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = main._camera._focus
	await frames(3)
	w.gather_target = tree
	var chop_before := _playing_of("chop")
	for _i in range(30):
		w._animate_chop(0.25)
	var chop_after := _playing_of("chop")
	print("  рубка: голосов топора было %d, стало %d" % [chop_before, chop_after])
	verdict("F6 рубка дерева звучит топором", chop_after > chop_before,
		"было %d, стало %d" % [chop_before, chop_after])

	sp.queue_free(); wr.queue_free(); ar.queue_free()
	w.queue_free(); tree.queue_free()
	await frames(3)

## Сколько голосов сейчас занято этой категорией
func _playing_of(cat: String) -> int:
	var n := 0
	for i in range(AudioManager._pool.size()):
		if (AudioManager._pool[i] as AudioStreamPlayer3D).playing \
				and String(AudioManager._pool_cat[i]) == cat:
			n += 1
	return n

# ═════════════════════════════════════════════════════════════════════════════
# G. ПОЛЗУНКИ В МЕНЮ ПАУЗЫ
# ═════════════════════════════════════════════════════════════════════════════
func _g_sliders() -> void:
	print("\n═════ G. НАСТРОЙКИ ЗВУКА В МЕНЮ ═════")
	var hud = main.hud
	hud._show_pause_menu()
	await frames(3)
	var sliders: Array = []
	_collect_sliders(hud, sliders)
	print("  ползунков в меню паузы: %d" % sliders.size())
	verdict("G1 меню паузы отдаёт три ползунка", sliders.size() == 3,
		"нашли %d" % sliders.size())

	var all_always := true
	for s in sliders:
		if (s as Control).process_mode != Node.PROCESS_MODE_ALWAYS:
			all_always = false
	verdict("G2 ползунки работают на паузе", all_always)

	# Двигаем первый ползунок и смотрим на шину Master
	if sliders.size() >= 3:
		var sl: HSlider = sliders[0]
		var si: int = AudioServer.get_bus_index("Master")
		sl.value = 0.4
		await frames(2)
		var db_low: float = AudioServer.get_bus_volume_db(si)
		sl.value = 1.0
		await frames(2)
		var db_high: float = AudioServer.get_bus_volume_db(si)
		print("  ползунок Master: 40%% → %.2f дБ, 100%% → %.2f дБ" % [db_low, db_high])
		verdict("G3 движение ползунка меняет громкость шины",
			db_low < db_high - 3.0, "%.2f против %.2f дБ" % [db_low, db_high])
	get_tree().paused = false
	hud._clear_overlay()
	await frames(2)

func _collect_sliders(node: Node, out: Array) -> void:
	if node is HSlider:
		out.append(node)
	for c in node.get_children():
		_collect_sliders(c, out)
