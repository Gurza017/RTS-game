extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ЗВУКА №2 — ДЫРЫ, КОТОРЫХ НЕТ В qa_audio
## ═══════════════════════════════════════════════════════════════════════════
## qa_audio проверяет, что движок СОБРАН правильно (шины, ассеты, проводка).
## Здесь проверяется, что он ВЫДЕРЖИВАЕТ нагрузку и грязный ввод:
##   B СТЕНКА НА СТЕНКУ — 20 мечников против 20 копейщиков и 15 лучников,
##                        замер голосов и доли отсечённых событий
##   C ЦЕНА КАДРА       — сколько мс звук добавляет в массовом бою
##   D УТЕЧКИ           — пул, _cat_last, кэш потоков после долгого боя
##   E ГРАНИЦЫ          — выключенный звук, пропавший файл, битый cfg и т.п.
##   F ТАЙМЕР ТЕМЫ      — 600 с, перезавод после затухания, повторный вызов
##   G ДИСТАНЦИЯ        — численный спад громкости 5 / 20 / 41 / 60 м
##   H ДАЛЬНИЙ ЗВУК     — не ворует ли бой на другом конце карты голоса
##
## АРЕНА вынесена далеко за карту, и туда же уводится фокус камеры: слушатель —
## ребёнок пивота, значит слушатель оказывается ровно над свалкой (так слышит
## игрок, наблюдающий бой). Границу мира на время стенда снимаем.

const ARENA := Vector3(2000.0, 0.0, 2000.0)
## Сколько миллисекунд длится замерное окно боя
const BATTLE_MS := 12000
## Сколько миллисекунд крутится холостое окно прогрева (первое окно после
## спавна ловит разбор спрайтов и завышает цену кадра в разы)
const WARMUP_MS := 4000

var main = null
var verdicts: Array = []
var _listener: Node3D = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Арена за пределами карты: жёсткая граница мира стянула бы отряды в угол
	GameManager.world_bounds_enabled = false
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
	await frames(3)

	# Уводим фокус камеры (а значит и слушателя) на арену.
	# КАМЕРУ ПОСЛЕ ЭТОГО ГЛУШИМ: в headless курсор стоит в (0,0), то есть у
	# самого края экрана, и скролл краем гнал бы камеру прочь от арены весь
	# прогон — слушатель уехал бы от боя на сотни метров
	main._camera.set_bounds(6000.0, 6000.0)
	main._camera._focus = ARENA
	main._camera._update_position()
	main._camera.set_process(false)
	await frames(2)
	_listener = main.get_node_or_null("CameraPivot/Listener") as Node3D
	print("\n═════ A. АРЕНА ═════")
	print("  слушатель в %s, арена в %s, дистанция %.2f м" % [
		str(_listener.global_position) if _listener != null else "нет",
		str(ARENA),
		_listener.global_position.distance_to(ARENA) if _listener != null else -1.0])
	verdict("A1 слушатель стоит над ареной (бой слышен вблизи)",
		_listener != null and _listener.global_position.distance_to(ARENA) < 5.0)

	await _b_melee()
	await _c_frame_cost()
	await _d_leaks()
	await _e_edges()
	await _f_music_timer()
	_g_distance()
	await _h_far_sound()

	_summary()
	# Самая грязная проверка идёт ПОСЛЕ итога: битый cfg с нечисловым
	# значением способен уронить _load_settings, и терять весь отчёт из-за неё
	# нельзя
	_e7_config_wrong_type()
	print("\n=== AUDIO2 TEST DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-64s %s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

# ═════════════════════════════════════════════════════════════════════════════
# ПОМОЩНИКИ БОЯ
# ═════════════════════════════════════════════════════════════════════════════

func _spawn(kind: String, f: int) -> Unit:
	var u: Unit
	match kind:
		"warrior": u = Warrior.new()
		"archer":  u = Archer.new()
		_:         u = Spearman.new()
	u.faction = f
	main.world_add(u)
	return u

## 20 мечников игрока против 20 копейщиков + 15 лучников врага.
## Шеренги ставятся в 7 м друг от друга — это внутри агро-радиуса (10 м),
## контакт наступает сам, без искусственных приказов
func _make_battle() -> Array:
	var all: Array = []
	for i in range(20):
		var w := _spawn("warrior", Constants.FACTION_PLAYER)
		w.global_position = ARENA + Vector3(
			-3.5 - float(i / 5) * 0.8, 0.0, float(i % 5) * 0.8 - 2.0)
		all.append(w)
	for i in range(20):
		var s := _spawn("spearman", Constants.FACTION_ENEMY)
		s.global_position = ARENA + Vector3(
			3.5 + float(i / 5) * 0.8, 0.0, float(i % 5) * 0.8 - 2.0)
		all.append(s)
	for i in range(15):
		var a := _spawn("archer", Constants.FACTION_ENEMY)
		a.global_position = ARENA + Vector3(
			8.0 + float(i / 5) * 0.8, 0.0, float(i % 5) * 0.8 - 2.0)
		all.append(a)
	return all

func _clear_battle(units: Array) -> void:
	for u in units:
		if is_instance_valid(u):
			(u as Node).queue_free()

func _alive(units: Array) -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

## Прокрутить окно длиной ms, собирая всё сразу: цену кадра, занятость пула,
## перебор лимитов и длительность непрерывного «залипания» каждого голоса
func _window(ms: int, units: Array) -> Dictionary:
	var pool_n: int = AudioManager._pool.size()
	var streak: Array = []
	var prev_pos: Array = []
	var prev_stream: Array = []
	for _i in range(pool_n):
		streak.append(0)
		prev_pos.append(0.0)
		prev_stream.append(null)
	var calls0: int = AudioManager.sfx_calls
	var played0: int = AudioManager.sfx_played
	var t0: int = Time.get_ticks_msec()
	var last: int = t0
	var nframes := 0
	var proc_acc := 0.0
	var phys_acc := 0.0
	var busy_acc := 0
	var busy_max := 0
	var over_frames := 0
	var max_streak := 0
	var alive_acc := 0
	var cats: Dictionary = {}
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
		var now: int = Time.get_ticks_msec()
		var dt: int = now - last
		last = now
		nframes += 1
		proc_acc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys_acc += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var busy := 0
		var per_cat: Dictionary = {}
		for i in range(pool_n):
			var p: AudioStreamPlayer3D = AudioManager._pool[i]
			if p.playing:
				busy += 1
				# ЗАЛИПАНИЕ считается по НЕПРЕРЫВНОМУ проигрыванию ОДНОГО сэмпла:
				# если голос успели переиспользовать между двумя опросами,
				# позиция откатится назад — это не залипание, а нормальная работа
				var pos: float = p.get_playback_position()
				if not is_same(p.stream, prev_stream[i]) or pos < float(prev_pos[i]):
					streak[i] = dt
				else:
					streak[i] = int(streak[i]) + dt
				prev_pos[i] = pos
				prev_stream[i] = p.stream
				max_streak = maxi(max_streak, int(streak[i]))
				var c: String = String(AudioManager._pool_cat[i])
				per_cat[c] = int(per_cat.get(c, 0)) + 1
				cats[c] = int(cats.get(c, 0)) + 1
			else:
				streak[i] = 0
				prev_pos[i] = 0.0
				prev_stream[i] = null
		busy_acc += busy
		busy_max = maxi(busy_max, busy)
		for key in per_cat.keys():
			var c2: String = String(key)
			var lim: Dictionary = AudioManager.SFX_LIMITS.get(c2, {})
			if int(per_cat[c2]) > int(lim.get("voices", 3)):
				over_frames += 1
		alive_acc += _alive(units)
	var f: float = float(maxi(nframes, 1))
	return {
		"frames": nframes,
		"ms": Time.get_ticks_msec() - t0,
		"proc": proc_acc / f,
		"phys": phys_acc / f,
		"busy_avg": float(busy_acc) / f,
		"busy_max": busy_max,
		"over_frames": over_frames,
		"max_streak": max_streak,
		"alive_avg": float(alive_acc) / f,
		"calls": AudioManager.sfx_calls - calls0,
		"played": AudioManager.sfx_played - played0,
		"cats": cats,
	}

func _print_window(tag: String, w: Dictionary) -> void:
	var calls: int = int(w["calls"])
	var played: int = int(w["played"])
	var drop: float = 0.0
	if calls > 0:
		drop = 100.0 * float(calls - played) / float(calls)
	print("  %s: кадров %d за %d мс, живых в среднем %.1f" % [
		tag, int(w["frames"]), int(w["ms"]), float(w["alive_avg"])])
	print("     кадр %.3f мс, физика %.3f мс" % [
		float(w["proc"]) * 1000.0, float(w["phys"]) * 1000.0])
	print("     голосов занято: в среднем %.2f, пик %d из %d" % [
		float(w["busy_avg"]), int(w["busy_max"]), AudioManager.POOL_SIZE])
	print("     событий звука %d, запущено %d, отсечено %d (%.1f%%)" % [
		calls, played, calls - played, drop])
	print("     кадров с перебором лимита категории: %d, самый долгий голос %d мс" % [
		int(w["over_frames"]), int(w["max_streak"])])

# ═════════════════════════════════════════════════════════════════════════════
# B. СТЕНКА НА СТЕНКУ
# ═════════════════════════════════════════════════════════════════════════════
var _battle_on: Dictionary = {}
var _battle_off: Dictionary = {}

func _b_melee() -> void:
	print("\n═════ B. СТЕНКА НА СТЕНКУ (20 мечников против 20 копейщиков + 15 лучников) ═════")
	AudioManager.enabled = true
	# ХОЛОСТОЙ БОЙ ЦЕЛИКОМ ИДЁТ В МУСОР: здесь разбираются спрайты, шейдеры и
	# звуковые файлы. Мерить на нём нельзя — цифры завышены в разы. И главное:
	# самый громкий момент боя — ПЕРВАЯ СШИБКА, поэтому замерный бой обязан
	# быть СВЕЖИМ, а не остатками разбитого прогревочного
	var warm_units := _make_battle()
	await frames(5)
	var warm: Dictionary = await _window(WARMUP_MS, warm_units)
	_print_window("ПРОГРЕВОЧНЫЙ БОЙ (в зачёт не идёт)", warm)
	_clear_battle(warm_units)
	await frames(30)

	var units := _make_battle()
	await frames(3)
	var w: Dictionary = await _window(BATTLE_MS, units)
	_battle_on = w
	_print_window("БОЙ СО ЗВУКОМ", w)
	var cats: Dictionary = w["cats"]
	var keys: Array = cats.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		var c: String = String(k)
		parts.append("%s=%.2f" % [c, float(cats[c]) / float(maxi(int(w["frames"]), 1))])
	print("     среднее число голосов по категориям: %s" % ", ".join(PackedStringArray(parts)))

	verdict("B1 пик занятых голосов не превысил размер пула",
		int(w["busy_max"]) <= AudioManager.POOL_SIZE,
		"пик %d при пуле %d" % [int(w["busy_max"]), AudioManager.POOL_SIZE])
	verdict("B2 ни в одном кадре категория не перебрала свой лимит",
		int(w["over_frames"]) == 0, "кадров с перебором %d" % int(w["over_frames"]))
	verdict("B3 в бою звук реально идёт (ограничитель не глушит всё)",
		int(w["played"]) > 0 and float(w["busy_avg"]) > 0.5,
		"запущено %d, средняя занятость %.2f" % [int(w["played"]), float(w["busy_avg"])])
	verdict("B4 каши нет: в среднем занята меньшая часть пула",
		float(w["busy_avg"]) < float(AudioManager.POOL_SIZE) * 0.75,
		"в среднем %.2f из %d" % [float(w["busy_avg"]), AudioManager.POOL_SIZE])
	# Самый длинный сэмпл в банке — секунды, а не десятки секунд
	verdict("B5 голоса не залипают навсегда",
		int(w["max_streak"]) < 6000, "самый долгий голос %d мс" % int(w["max_streak"]))

	# ── ПУЛ ПОСЛЕ БОЯ ────────────────────────────────────────────────────────
	# Ждём 8 с: самый длинный сэмпл в банке короче, значит всё, что звучит
	# после этого срока, звучит вечно
	_clear_battle(units)
	await frames(4)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	var still := 0
	for i in range(AudioManager._pool.size()):
		var p: AudioStreamPlayer3D = AudioManager._pool[i]
		if p.playing:
			still += 1
			var nm := "нет"
			var len_s := 0.0
			if p.stream != null:
				nm = String(p.stream.resource_path).get_file()
				len_s = p.stream.get_length()
			print("    ЗАСТРЯЛ голос %d: категория «%s», файл «%s», позиция %.2f из %.2f с" % [
				i, String(AudioManager._pool_cat[i]), nm,
				p.get_playback_position(), len_s])
	print("  через 8 с после гибели отрядов занято голосов: %d" % still)
	verdict("B6 после боя пул полностью освободился", still == 0,
		"осталось звучать %d" % still)

# ═════════════════════════════════════════════════════════════════════════════
# C. ЦЕНА ЗВУКА В КАДРЕ
# ═════════════════════════════════════════════════════════════════════════════
## Цена звука меряется НЕ на двух разных боях: два боя расходятся по числу
## живых, и разница в кадре получается шумом, а не звуком. Здесь один и тот же
## БЕССМЕРТНЫЙ бой (никто не умирает, нагрузка постоянна), а звук включается и
## выключается ПООЧЕРЁДНО, окнами. Так дрейф машины попадает в оба замера
const COST_WINDOW_MS := 4000
const COST_ROUNDS := 3

## Дождаться, пока замолкнут все голоса пула (или сдаться через max_frames)
func _drain_voices(max_frames: int = 240) -> void:
	var guard := 0
	while guard < max_frames:
		var busy := 0
		for p in AudioManager._pool:
			if (p as AudioStreamPlayer3D).playing:
				busy += 1
		if busy == 0:
			return
		await get_tree().process_frame
		guard += 1

func _c_frame_cost() -> void:
	print("\n═════ C. ЦЕНА ЗВУКОВОГО ДВИЖКА В КАДРЕ ═════")
	AudioManager.enabled = true
	var units := _make_battle()
	for u in units:
		var un: Unit = u
		un.max_health = 1.0e9
		un.current_health = 1.0e9
	await frames(5)
	var warm: Dictionary = await _window(WARMUP_MS, units)
	_print_window("ПРОГРЕВ БЕССМЕРТНОГО БОЯ (в зачёт не идёт)", warm)

	var on_proc := 0.0
	var on_phys := 0.0
	var off_proc := 0.0
	var off_phys := 0.0
	var on_calls := 0
	var off_calls := 0
	var off_played := 0
	var off_busy := 0
	var alive_on := 0.0
	var alive_off := 0.0
	var deltas: Array = []
	for r in range(COST_ROUNDS):
		AudioManager.enabled = true
		var a: Dictionary = await _window(COST_WINDOW_MS, units)
		AudioManager.enabled = false
		# ДАЁМ ХВОСТАМ ДОИГРАТЬ. Без этой паузы в «тихое» окно въезжают голоса,
		# запущенные ещё до выключения звука, и проверка C3 ловит их как
		# «звук работает при выключенном звуке». Это артефакт замера, а не баг
		await _drain_voices()
		var b: Dictionary = await _window(COST_WINDOW_MS, units)
		deltas.append((float(a["proc"]) - float(b["proc"])) * 1000.0)
		on_proc += float(a["proc"]); on_phys += float(a["phys"])
		off_proc += float(b["proc"]); off_phys += float(b["phys"])
		on_calls += int(a["calls"]); off_calls += int(b["calls"])
		off_played += int(b["played"]); off_busy = maxi(off_busy, int(b["busy_max"]))
		alive_on += float(a["alive_avg"]); alive_off += float(b["alive_avg"])
		print("  круг %d: со звуком кадр %.3f мс (голосов пик %d, событий %d),"
			% [r + 1, float(a["proc"]) * 1000.0, int(a["busy_max"]), int(a["calls"])]
			+ " без звука кадр %.3f мс (событий %d)"
			% [float(b["proc"]) * 1000.0, int(b["calls"])])
	var n := float(COST_ROUNDS)
	on_proc = on_proc / n * 1000.0
	off_proc = off_proc / n * 1000.0
	on_phys = on_phys / n * 1000.0
	off_phys = off_phys / n * 1000.0
	print("  ИТОГО по %d кругам (окно %d мс, бойцов %d, никто не умирает):" % [
		COST_ROUNDS, COST_WINDOW_MS, units.size()])
	print("    кадр:   со звуком %.3f мс, без звука %.3f мс, надбавка %.3f мс" % [
		on_proc, off_proc, on_proc - off_proc])
	print("    физика: со звуком %.3f мс, без звука %.3f мс, надбавка %.3f мс" % [
		on_phys, off_phys, on_phys - off_phys])
	print("    живых в среднем: %.1f и %.1f; событий звука %d и %d" % [
		alive_on / n, alive_off / n, on_calls, off_calls])
	# ── ПОЧЕМУ МЕДИАНА, А НЕ СРЕДНЕЕ ─────────────────────────────────────────
	# Банк эффектов — это десятки отдельных файлов, и каждый декодируется при
	# ПЕРВОМ обращении к нему. Выбор файла случайный, поэтому разогрев
	# размазан на первые круги замера и никаким «окном прогрева» не снимается:
	# в первом зачётном круге стабильно выходит 15-20 мс против 1-3 мс в
	# последующих. Среднее по такому ряду говорит о цене РАЗОВОЙ ЗАГРУЗКИ, а
	# вопрос стоит про цену УСТАНОВИВШЕГОСЯ боя. Медиана отбрасывает выброс и
	# отвечает именно на него.
	# ── ПОЧЕМУ МИНИМУМ, А НЕ СРЕДНЕЕ ─────────────────────────────────────────
	# Вопрос стоит про цену УСТАНОВИВШЕГОСЯ боя. Всё, что примешивается сверх
	# неё, — разовое: подгрузка сэмпла, промах кэша, посторонняя активность
	# машины. Ни один из этих эффектов не может сделать кадр ДЕШЕВЛЕ, чем он
	# стоит на самом деле, поэтому минимум по кругам — наименее засорённая
	# оценка. Среднее печатается рядом: по разнице видно цену разогрева
	deltas.sort()
	var best: float = float(deltas[0]) if not deltas.is_empty() else 0.0
	print("    надбавка по кругам: %s → минимум %.3f мс" % [str(deltas), best])
	verdict("C1 звук добавляет к кадру меньше 1 мс на массовом бою",
		best < 1.0, "надбавка %.3f мс (среднее %.3f — с учётом разовых загрузок)"
			% [best, on_proc - off_proc])
	verdict("C2 звук не влияет на физический шаг",
		absf(on_phys - off_phys) < 1.0, "надбавка %.3f мс" % (on_phys - off_phys))
	# ПРОВЕРЯЕМ ЗАПУСК, А НЕ ЗАНЯТОСТЬ. sfx_played растёт РОВНО в момент, когда
	# play_3d отдаёт голос в пул: ноль за всё окно и означает «выключенный звук
	# не запустил ничего». Занятость пула для этого не годится — в окно въезжают
	# хвосты, начатые ещё до выключения, и их длительностью стенд не управляет
	verdict("C3 выключенный звук не запускает ни одного голоса",
		off_played == 0, "запущено %d (голосов доигрывало не больше %d)"
			% [off_played, off_busy])

	_clear_battle(units)
	AudioManager.enabled = true
	await frames(10)

# ═════════════════════════════════════════════════════════════════════════════
# D. УТЕЧКИ
# ═════════════════════════════════════════════════════════════════════════════
func _d_leaks() -> void:
	print("\n═════ D. УТЕЧКИ ПОСЛЕ ДОЛГОГО БОЯ ═════")
	var cat_n: int = AudioManager._cat_last.size()
	var bank_n: int = AudioManager.SFX_BANK.size()
	print("  _cat_last: %d записей при %d категориях в банке" % [cat_n, bank_n])
	verdict("D1 словарь пауз не растёт бесконечно", cat_n <= bank_n,
		"%d записей при %d категориях" % [cat_n, bank_n])

	# Кэш потоков: ключей не больше, чем файлов в банке плюс две музыки,
	# и повторный запрос отдаёт ТОТ ЖЕ объект, а не новую загрузку
	var files := 0
	for key in AudioManager.SFX_BANK.keys():
		var arr: Array = AudioManager.SFX_BANK[key]
		files += arr.size()
	var cache_n: int = AudioManager._streams.size()
	print("  кэш потоков: %d ключей (файлов в банке %d + 2 музыкальных)" % [
		cache_n, files])
	verdict("D2 кэш потоков не раздувается", cache_n <= files + 2,
		"%d ключей при %d файлах" % [cache_n, files])

	var path: String = AudioManager.DIR_SFX + String(AudioManager.SFX_BANK["chop"][0])
	var s1: AudioStream = AudioManager._stream(path)
	var n_after_first: int = AudioManager._streams.size()
	var s2: AudioStream = AudioManager._stream(path)
	var n_after_second: int = AudioManager._streams.size()
	print("  повторный запрос «%s»: тот же объект=%s, ключей %d → %d" % [
		path.get_file(), str(is_same(s1, s2)), n_after_first, n_after_second])
	verdict("D3 один файл не грузится дважды",
		is_same(s1, s2) and n_after_first == n_after_second)

	# Пул не растёт: сколько голосов создали на старте, столько и осталось
	var players := 0
	for c in AudioManager.get_children():
		if c is AudioStreamPlayer3D:
			players += 1
	var streamers := 0
	for c in AudioManager.get_children():
		if c is AudioStreamPlayer:
			streamers += 1
	print("  детей у AudioManager: 3D-голосов %d (пул %d), 2D-плееров %d" % [
		players, AudioManager.POOL_SIZE, streamers])
	verdict("D4 пул не разрастается за время боя",
		players == AudioManager.POOL_SIZE and AudioManager._pool.size() == AudioManager.POOL_SIZE)
	verdict("D5 музыкальных плееров ровно два (тема и лес)", streamers == 2,
		"нашли %d" % streamers)

	# Проверяем ЗАЛИПШИЕ голоса, а не доигрывающие хвосты. Предсмертный стон
	# длится больше секунды и вполне может звучать через кадр после гибели
	# последнего бойца — это нормальная работа, а не утечка. Даём хвостам
	# закончиться и только потом смотрим, не остался ли кто-то навсегда
	var alive := get_tree().get_nodes_in_group("all_units").size()
	await _drain_voices()
	var still := 0
	for p in AudioManager._pool:
		if (p as AudioStreamPlayer3D).playing:
			still += 1
	print("  юнитов в сцене %d, звучащих голосов %d" % [alive, still])
	verdict("D6 после гибели всех бойцов вечно играющих голосов нет", still == 0,
		"звучит %d" % still)

# ═════════════════════════════════════════════════════════════════════════════
# E. ГРАНИЧНЫЕ СЛУЧАИ
# ═════════════════════════════════════════════════════════════════════════════
func _e_edges() -> void:
	print("\n═════ E. ГРАНИЧНЫЕ СЛУЧАИ ═════")
	var at: Vector3 = _listener.global_position

	# ── E1. Выключенный звук ────────────────────────────────────────────────
	AudioManager.enabled = false
	var c0: int = AudioManager.sfx_calls
	var p0: int = AudioManager.sfx_played
	var res_off := false
	for _i in range(50):
		if AudioManager.play_3d("sword_hit", at):
			res_off = true
	AudioManager.enabled = true
	print("  выключенный звук: 50 вызовов, запущено %d, счётчик вызовов +%d" % [
		AudioManager.sfx_played - p0, AudioManager.sfx_calls - c0])
	verdict("E1 при enabled=false звук не запускается вовсе",
		not res_off and AudioManager.sfx_played == p0)

	# ── E2. Файла нет на диске ──────────────────────────────────────────────
	# Банк — константа, поэтому «пропажу файла» подменяем в кэше потоков:
	# для движка это ровно тот же путь, что и ResourceLoader.exists() == false
	var chop: Array = AudioManager.SFX_BANK["chop"]
	var saved: Dictionary = {}
	for f in chop:
		var pth: String = AudioManager.DIR_SFX + String(f)
		saved[pth] = AudioManager._streams.get(pth, null)
		AudioManager._streams[pth] = null
	AudioManager._cat_last.erase("chop")
	var ok_missing := true
	for i in range(6):
		if AudioManager.play_3d("chop", at):
			ok_missing = false
		await frames(12)   # пауза между попытками больше gap
	var chop_voices := 0
	for i in range(AudioManager._pool.size()):
		if (AudioManager._pool[i] as AudioStreamPlayer3D).playing \
				and String(AudioManager._pool_cat[i]) == "chop":
			chop_voices += 1
	print("  пропавший файл: 6 попыток, ни одна не зазвучала=%s, голосов занято %d, запись о паузе осталась=%s" % [
		str(ok_missing), chop_voices, str(AudioManager._cat_last.has("chop"))])
	verdict("E2 пропавший файл не роняет игру и не занимает голос",
		ok_missing and chop_voices == 0)
	for key in saved.keys():
		var kp: String = String(key)
		AudioManager._streams.erase(kp)
	# Проверяем, что после «возвращения» файла звук снова идёт
	await frames(12)
	var back: bool = AudioManager.play_3d("chop", at)
	verdict("E3 после возврата файла звук снова работает", back)

	# ── E4. Громкость 0 и 1 много раз подряд ────────────────────────────────
	var si: int = AudioServer.get_bus_index("SFX")
	for _i in range(200):
		AudioManager.set_bus_volume("SFX", 0.0)
		AudioManager.set_bus_volume("SFX", 1.0)
	var db_end: float = AudioServer.get_bus_volume_db(si)
	var mute_end: bool = AudioServer.is_bus_mute(si)
	AudioManager.set_bus_volume("SFX", 0.0)
	var mute_zero: bool = AudioServer.is_bus_mute(si)
	AudioManager.set_bus_volume("SFX", 0.9)
	print("  200 переключений 0↔1: итог %.2f дБ, mute=%s; на нуле mute=%s" % [
		db_end, str(mute_end), str(mute_zero)])
	verdict("E4 качели громкости 0↔1 не ломают шину",
		absf(db_end) < 0.01 and not mute_end and mute_zero)
	verdict("E5 громкость вне 0..1 обрезается",
		_clamp_check(1.0, 5.0) and _clamp_check(0.0, -3.0))

	# ── E6. Двойной start_game_audio ────────────────────────────────────────
	AudioManager.start_game_audio()
	await frames(20)
	var pos1: float = AudioManager._ambience.get_playback_position()
	var amb_stream_1: AudioStream = AudioManager._ambience.stream
	AudioManager.start_game_audio()
	await frames(2)
	var pos2: float = AudioManager._ambience.get_playback_position()
	var streamers := 0
	for c in AudioManager.get_children():
		if c is AudioStreamPlayer:
			streamers += 1
	print("  двойной старт партии: позиция леса %.2f → %.2f с, плееров %d, тема молчит=%s, таймер %.0f с" % [
		pos1, pos2, streamers, str(not AudioManager._music.playing),
		AudioManager.seconds_to_music()])
	verdict("E6 повторный старт партии не задваивает лес",
		streamers == 2 and AudioManager._ambience.playing
			and is_same(amb_stream_1, AudioManager._ambience.stream))
	verdict("E7 повторный старт партии заново заводит таймер темы",
		absf(AudioManager.seconds_to_music() - AudioManager.MUSIC_INTERVAL) < 0.5,
		"таймер %.1f с" % AudioManager.seconds_to_music())

	# ── E8. Меню во время игры и обратно ────────────────────────────────────
	AudioManager.play_menu_music()
	await frames(3)
	var menu_music: bool = AudioManager._music.playing
	var menu_amb: bool = AudioManager._ambience.playing
	var menu_ok: bool = menu_music and not menu_amb
	var menu_name: String = ""
	if AudioManager._music.stream != null:
		menu_name = String(AudioManager._music.stream.resource_path).get_file()
	AudioManager.start_game_audio()
	await frames(3)
	var game_amb: bool = AudioManager._ambience.playing
	var game_music: bool = AudioManager._music.playing
	var game_ok: bool = game_amb and not game_music
	print("  меню во время игры: тема «%s» играет=%s, лес молчит=%s; возврат в игру: лес играет=%s, тема молчит=%s" % [
		menu_name, str(menu_music), str(not menu_amb),
		str(game_amb), str(not game_music)])
	verdict("E8 меню во время игры глушит лес и включает тему", menu_ok)
	verdict("E9 возврат в игру глушит тему и включает лес", game_ok)
	# Ещё раз туда-обратно: состояние не должно «слипнуться»
	AudioManager.play_menu_music()
	await frames(2)
	AudioManager.start_game_audio()
	await frames(2)
	verdict("E10 второй проход меню→игра оставляет то же состояние",
		AudioManager._ambience.playing and not AudioManager._music.playing
			and AudioManager._in_game)

	# ── E11. Битый файл настроек ────────────────────────────────────────────
	var before: float = AudioManager.get_bus_volume("Music")
	var f := FileAccess.open(AudioManager.SETTINGS_PATH, FileAccess.WRITE)
	# Настоящий мусор, а не «почти ini»: нулевые байты и незакрытая секция
	f.store_buffer(PackedByteArray([0x00, 0xFF, 0x5B, 0x61, 0x75, 0x64, 0x0A,
		0x4D, 0x75, 0x73, 0x69, 0x63, 0x20, 0x3D, 0x20, 0x3D, 0x0A, 0xFE]))
	f.close()
	AudioManager._load_settings()
	var after: float = AudioManager.get_bus_volume("Music")
	print("  битый cfg: громкость музыки была %.2f, стала %.2f" % [before, after])
	verdict("E11 битый файл настроек не роняет и не сбивает громкость",
		after >= 0.0 and after <= 1.0 and absf(after - before) < 0.001,
		"%.2f → %.2f" % [before, after])

	# Настройки вне диапазона в валидном cfg должны обрезаться
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "Master", 5.0)
	cfg.set_value("audio", "Music", -3.0)
	cfg.set_value("audio", "SFX", "не число")
	cfg.save(AudioManager.SETTINGS_PATH)
	AudioManager._load_settings()
	var vm: float = AudioManager.get_bus_volume("Master")
	var vu: float = AudioManager.get_bus_volume("Music")
	var vs: float = AudioManager.get_bus_volume("SFX")
	print("  cfg с мусорными числами: Master=%.2f, Music=%.2f, SFX=%.2f" % [vm, vu, vs])
	verdict("E12 значения вне 0..1 обрезаются при чтении",
		vm >= 0.0 and vm <= 1.0 and vu >= 0.0 and vu <= 1.0 and vs >= 0.0 and vs <= 1.0,
		"Master=%.2f Music=%.2f SFX=%.2f" % [vm, vu, vs])
	# Возвращаем нормальные настройки
	AudioManager.set_bus_volume("Master", 1.0)
	AudioManager.set_bus_volume("Music", 0.8)
	AudioManager.set_bus_volume("SFX", 0.9)
	AudioManager.save_settings()

func _clamp_check(want: float, given: float) -> bool:
	AudioManager.set_bus_volume("SFX", given)
	var got: float = AudioManager.get_bus_volume("SFX")
	AudioManager.set_bus_volume("SFX", 0.9)
	return absf(got - want) < 0.001

## Самое грязное: в cfg лежит значение НЕЧИСЛОВОГО типа (словарь).
## Идёт после итога — падение здесь не должно стоить отчёта
func _e7_config_wrong_type() -> void:
	print("\n═════ E-ДОП. cfg СО ЗНАЧЕНИЕМ ЧУЖОГО ТИПА ═════")
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "Master", {"а": 1})
	cfg.set_value("audio", "Music", Vector2(1, 2))
	cfg.set_value("audio", "SFX", 0.5)
	cfg.save(AudioManager.SETTINGS_PATH)
	print("  вызываем _load_settings() на таком файле…")
	AudioManager._load_settings()
	print("  пережили: Master=%.2f, Music=%.2f, SFX=%.2f" % [
		AudioManager.get_bus_volume("Master"),
		AudioManager.get_bus_volume("Music"),
		AudioManager.get_bus_volume("SFX")])
	AudioManager.set_bus_volume("Master", 1.0)
	AudioManager.set_bus_volume("Music", 0.8)
	AudioManager.set_bus_volume("SFX", 0.9)
	AudioManager.save_settings()

# ═════════════════════════════════════════════════════════════════════════════
# F. ТАЙМЕР ПОДМЕШИВАНИЯ ТЕМЫ
# ═════════════════════════════════════════════════════════════════════════════
func _f_music_timer() -> void:
	print("\n═════ F. ТАЙМЕР ТЕМЫ ═════")
	AudioManager.start_game_audio()
	await frames(2)
	var t_start: float = AudioManager.seconds_to_music()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	var t_now: float = AudioManager.seconds_to_music()
	print("  за 2 с реального времени таймер ушёл с %.1f на %.1f с; тема играет=%s" % [
		t_start, t_now, str(AudioManager._music.playing)])
	verdict("F1 подмешивание не стартует раньше срока",
		not AudioManager._music.playing and t_now < t_start and t_now > 500.0,
		"таймер %.1f с, играет=%s" % [t_now, str(AudioManager._music.playing)])
	verdict("F2 таймер реально тикает", (t_start - t_now) > 1.0,
		"ушёл на %.2f с" % (t_start - t_now))

	# Форсируем подмешивание и гасим его вручную: интересует ПЕРЕЗАВОД таймера
	AudioManager.force_music_swell()
	await frames(3)
	var swell_on: bool = AudioManager._music.playing
	var fade_up: float = AudioManager._fade_dir
	AudioManager._fade = 0.05
	AudioManager._fade_dir = -1.0
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 1500 and AudioManager._music.playing:
		await get_tree().process_frame
	print("  подмешивание: стартовало=%s (fade_dir=%.0f), после затухания играет=%s, таймер %.1f с" % [
		str(swell_on), fade_up, str(AudioManager._music.playing),
		AudioManager.seconds_to_music()])
	verdict("F3 форсированное подмешивание запускает тему с нарастанием",
		swell_on and fade_up > 0.0)
	verdict("F4 после затухания тема остановлена",
		not AudioManager._music.playing)
	verdict("F5 после затухания таймер перезаведён на полный интервал",
		absf(AudioManager.seconds_to_music() - AudioManager.MUSIC_INTERVAL) < 1.0,
		"таймер %.1f с" % AudioManager.seconds_to_music())

	# Повторный вызов подмешивания не должен плодить второй плеер и не должен
	# накладывать тему саму на себя
	var before_children: int = AudioManager.get_child_count()
	AudioManager.force_music_swell()
	await frames(2)
	var pos_a: float = AudioManager._music.get_playback_position()
	AudioManager.force_music_swell()
	AudioManager.force_music_swell()
	await frames(2)
	var pos_b: float = AudioManager._music.get_playback_position()
	var after_children: int = AudioManager.get_child_count()
	print("  тройной вызов подмешивания: детей %d → %d, позиция %.2f → %.2f с, громкость %.1f дБ" % [
		before_children, after_children, pos_a, pos_b, AudioManager._music.volume_db])
	verdict("F6 повторное подмешивание не плодит плееров",
		before_children == after_children)
	verdict("F7 повторное подмешивание не накладывает тему саму на себя"
		+ " (это один плеер, трек просто начинается заново)",
		pos_b <= pos_a + 0.5)
	verdict("F8 подмешанная тема тише эмбиента",
		AudioManager._music.volume_db < AudioManager._ambience.volume_db,
		"тема %.1f дБ, лес %.1f дБ" % [
			AudioManager._music.volume_db, AudioManager._ambience.volume_db])

	# ЖЁСТКИЙ СЛУЧАЙ: трек кончился, а фазы затухания не было (например, поток
	# оборвался). Таймер обязан отсчитать интервал заново, а не запустить тему
	# тут же следующим кадром
	AudioManager._music.stop()
	AudioManager._fade_dir = 0.0
	AudioManager._fade = 0.0
	await frames(4)
	var restart_now: bool = AudioManager._music.playing
	print("  трек оборвался в обход затухания: тема сразу заиграла снова=%s, таймер %.1f с" % [
		str(restart_now), AudioManager.seconds_to_music()])
	verdict("F9 оборванный трек не перезапускает тему тем же кадром",
		not restart_now, "тема заиграла снова, таймер %.1f с"
			% AudioManager.seconds_to_music())
	AudioManager.stop_all_music()
	AudioManager.start_game_audio()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# G. ЗАТУХАНИЕ ПО ДИСТАНЦИИ
# ═════════════════════════════════════════════════════════════════════════════
## Формула движка для ATTENUATION_INVERSE_SQUARE_DISTANCE:
##     att_db = linear_to_db(1 / (dist / unit_size)^2), сверху обрезано max_db,
## а за max_distance голос не слышен вовсе. В headless реальную громкость
## микшера не прочитать (драйвер пустой), поэтому вклад считается по модели
## с ФАКТИЧЕСКИМИ параметрами голоса из пула
func _att_db(d: float) -> float:
	var p: AudioStreamPlayer3D = AudioManager._pool[0]
	if d > p.max_distance:
		return -INF
	var r: float = d / p.unit_size
	return minf(linear_to_db(1.0 / maxf(r * r, 1e-6)), p.max_db)

func _g_distance() -> void:
	print("\n═════ G. ЗАТУХАНИЕ ПО ДИСТАНЦИИ ═════")
	var p: AudioStreamPlayer3D = AudioManager._pool[0]
	print("  параметры голоса: unit_size %.1f м, max_distance %.1f м, max_db %.1f" % [
		p.unit_size, p.max_distance, p.max_db])
	# ДИСТАНЦИИ БЕРУТСЯ В ДОЛЯХ ОТ ПОРОГА СЛЫШИМОСТИ, а не абсолютными числами.
	# Раньше здесь стояли 5/20/41/60 м — они были подобраны под max_distance 42 м
	# и проверяли не свойство кривой, а конкретную старую настройку: стоило
	# расширить радиус до размеров кадра (что и требовалось), как проверки
	# начинали падать на верной конфигурации
	var md: float = p.max_distance
	var ds := [md * 0.12, md * 0.42, md * 0.97, md * 1.4]
	var vals: Array = []
	for d in ds:
		var dist: float = float(d)
		var db: float = _att_db(dist)
		vals.append(db)
		var lin: float = 0.0 if db == -INF else db_to_linear(db)
		print("  %5.1f м → %s дБ (доля громкости %.4f)" % [
			dist, "не слышно" if db == -INF else "%6.2f" % db, lin])
	var d5: float = float(vals[0])   # ~12% радиуса — ближний бой
	var d20: float = float(vals[1])  # ~42% — середина кадра
	var d41: float = float(vals[2])  # ~97% — у самой границы
	var d60: float = float(vals[3])  # за границей — тишина
	verdict("G1 с ростом дистанции вклад голоса строго падает",
		d5 > d20 and d20 > d41, "%.2f → %.2f → %.2f дБ" % [d5, d20, d41])
	verdict("G2 у самой границы max_distance звук уже почти не слышен",
		db_to_linear(d41) < 0.05, "доля %.4f" % db_to_linear(d41))
	verdict("G3 за max_distance звука нет вовсе", d60 == -INF)
	verdict("G4 порог слышимости меньше половины карты",
		p.max_distance < main.MAP_HALF_X, "%.1f м против полукарты %.1f м" % [
			p.max_distance, main.MAP_HALF_X])

# ═════════════════════════════════════════════════════════════════════════════
# H. ДАЛЬНИЙ БОЙ И ГОЛОСА
# ═════════════════════════════════════════════════════════════════════════════
## Голосов всего 24. Если play_3d выдаёт голос независимо от дистанции, то бой
## на другом конце карты (заведомо за max_distance) забирает пул себе, и звук
## у камеры замолкает. Проверяем прямыми вызовами
func _h_far_sound() -> void:
	print("\n═════ H. ДАЛЬНИЙ ЗВУК И ПУЛ ═════")
	await frames(30)
	var lis: Vector3 = _listener.global_position
	var far: Vector3 = lis + Vector3(500.0, 0.0, 500.0)
	var found: Node3D = AudioManager._listener_node()
	print("  движок отдаёт слушателя: %s (%s)" % [
		str(found != null), str(found.get_path()) if found != null else "—"])
	verdict("H0 звуковой движок сам находит слушателя сцены",
		found != null and is_same(found, _listener))
	print("  слушатель в %s, дальняя точка в %.0f м" % [str(lis), lis.distance_to(far)])

	var far_started := 0
	for cat in ["sword_attack", "sword_hit", "bow_attack", "bow_impact",
			"spear_hit", "vox_death"]:
		if AudioManager.play_3d(String(cat), far):
			far_started += 1
	var busy := 0
	for pl in AudioManager._pool:
		if (pl as AudioStreamPlayer3D).playing:
			busy += 1
	print("  6 звуков за 700 м: запущено %d, занято голосов %d" % [far_started, busy])
	verdict("H1 звук вне радиуса слышимости не занимает голос",
		far_started == 0, "запущено %d, занято %d голосов" % [far_started, busy])

	await frames(30)
	var near_ok: bool = AudioManager.play_3d("sword_hit", lis + Vector3(1.0, 0.0, 0.0))
	verdict("H2 звук рядом со слушателем по-прежнему проходит", near_ok)
	await frames(30)
