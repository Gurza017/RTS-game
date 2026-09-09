extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ИЗМЕРИТЕЛЬ СПЕКТРА: ЧТО ИМЕННО ТЕРЯЕТ МАРШ ПО ДОРОГЕ ДО ДИНАМИКА
## ═══════════════════════════════════════════════════════════════════════════
## ЖАЛОБА ВЛАДЕЛЬЦА: «в файле чёткий лязг доспехов и тяжёлый марш, а в игре
## слышна только лёгкая ходьба».
##
## ГАДАТЬ ЗДЕСЬ НЕЛЬЗЯ. Подозреваемых сразу несколько — фильтр самого
## AudioStreamPlayer3D, сведение стерео в точечный источник, громкость, импорт
## mp3, — и все они «объясняют» жалобу одинаково убедительно. Спектр отвечает
## числом: какая полоса и на сколько децибел просела ОТНОСИТЕЛЬНО того же файла,
## сыгранного без обработки.
##
## ── ЧЕТЫРЕ РЕЖИМА В ОДНОМ ПРОГОНЕ ─────────────────────────────────────────
##   ЭТАЛОН   — обычный AudioStreamPlayer (без 3D вообще);
##   3D 30 м  — ровно как в игре (настройки взяты из AudioManager);
##   3D 0 м   — то же, но слушатель стоит В источнике: отделяет то, что зависит
##              от РАССТОЯНИЯ, от того, что режется всегда;
##   3D 30 м + срез 20500 — то же, что второй, но фильтр дальности отключён.
##
## Разница второго и четвёртого — цена ФИЛЬТРА. Разница первого и третьего —
## цена самого 3D-тракта (сведение каналов). Одним прогоном закрываются обе
## гипотезы, и ни одна не остаётся на веру.
##
## ── ЗАПУСКАТЬ ТОЛЬКО В ОКНЕ ───────────────────────────────────────────────
## В headless движок ставит ПУСТОЙ звуковой драйвер: анализатор читает тишину,
## и стенд намерил бы «срезано всё». Это тот же класс слепоты, что у буфера
## глубины (см. qa_visual_smoke).
##
##   godot --path . res://qa_audio3/Test.tscn

const AM := preload("res://scripts/AudioManager.gd")

## Полосы разбора. Лязг металла живёт выше 4 кГц — там же, где режет и фильтр
## дальности (его умолчание 5000 Гц), и любой лимитер
const BANDS := [
	[31.0, 63.0], [63.0, 125.0], [125.0, 250.0], [250.0, 500.0],
	[500.0, 1000.0], [1000.0, 2000.0], [2000.0, 4000.0],
	[4000.0, 8000.0], [8000.0, 16000.0], [16000.0, 20000.0]]

## Сколько кадров усредняем и сколько пропускаем на раскачку анализатора
const WARM_FRAMES := 12
const TAKE_FRAMES := 90

## Ниже этого порога полоса считается срезанной (дБ относительно эталона)
const CUT_DB := 3.0

var _bus := -1
var _fx: AudioEffectSpectrumAnalyzerInstance = null
var _cam: Camera3D = null
var _checks := 0
var _fails := 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _ok(title: String, cond: bool, detail: String) -> void:
	_checks += 1
	if cond:
		print("    [ПРОШЛО]    %-40s %s" % [title, detail])
	else:
		_fails += 1
		print("    [НЕ ПРОШЛО] %-40s %s" % [title, detail])

## Средняя по времени энергия каждой полосы, в дБ.
##
## СЧИТАЕМ СРЕДНЕЕ, А НЕ МАКСИМУМ: луп непрерывен и неоднороден, максимум
## поймает случайный удар и от прогона к прогону будет прыгать. Сравниваются
## режимы на ОДНОМ И ТОМ ЖЕ отрезке ленты — все играются с нуля
func _measure() -> Array:
	var sum: Array = []
	for _b in BANDS:
		sum.append(0.0)
	await frames(WARM_FRAMES)
	for _i in range(TAKE_FRAMES):
		await get_tree().process_frame
		for k in range(BANDS.size()):
			var band: Array = BANDS[k]
			var m: Vector2 = _fx.get_magnitude_for_frequency_range(
				float(band[0]), float(band[1]),
				AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
			# Каналы складываем по энергии: сведение стерео в моно — одна из
			# проверяемых гипотез, и терять его на этом шаге нельзя
			sum[k] += (m.x + m.y) * 0.5
	var out: Array = []
	for k in range(BANDS.size()):
		out.append(linear_to_db(maxf(float(sum[k]) / float(TAKE_FRAMES), 1e-9)))
	return out

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(640, 360))

	# ── ШИНА И АНАЛИЗАТОР ──────────────────────────────────────────────────
	# Шину заводим ту же, что в игре: если срез окажется на ней, он попадёт в
	# замер сам собой
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_bus = AudioServer.get_bus_index("SFX")
	var an := AudioEffectSpectrumAnalyzer.new()
	an.buffer_length = 0.2
	an.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(_bus, an)
	_fx = AudioServer.get_bus_effect_instance(_bus,
		AudioServer.get_bus_effect_count(_bus) - 1)
	if _fx == null:
		push_error("анализатор не встал на шину")
		get_tree().quit(1)
		return

	# Слушатель. Без камеры 3D-звук вообще не позиционируется
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.global_position = Vector3.ZERO
	# ── СЛУШАТЕЛЬ НУЖЕН ЯВНЫЙ ─────────────────────────────────────────────
	# AudioManager ищет его через `Viewport.get_audio_listener_3d()`, а тот
	# отвечает ТОЛЬКО про явно назначенный AudioListener3D: камера слушателем
	# работает, но этим методом не возвращается. В партии узел ставит Main;
	# без него отсечка по расстоянию и сортировка по близости не работают
	# вовсе — то есть стенд мерил бы марш, у которого нет ни того ни другого
	var lst := AudioListener3D.new()
	add_child(lst)
	lst.global_position = Vector3.ZERO
	lst.make_current()

	var path: String = AM.MARCH_WALK_LOOP
	var s: AudioStream = load(path) as AudioStream
	if s == null:
		push_error("не читается %s" % path)
		get_tree().quit(1)
		return
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	print("\n=== СПЕКТР МАРША: %s ===" % path.get_file())
	print("  поток: %s, каналов %d, длина %.2f с" % [
		s.get_class(),
		2 if (s.get_class() == "AudioStreamMP3") else 1,
		s.get_length()])

	# ── ЭТАЛОН: БЕЗ 3D ВООБЩЕ ──────────────────────────────────────────────
	var flat := AudioStreamPlayer.new()
	flat.bus = "SFX"
	flat.stream = s
	flat.volume_db = AM.MARCH_WALK_DB
	add_child(flat)
	flat.play(0.0)
	var ref: Array = await _measure()
	flat.stop()
	await frames(6)

	# ── ТРИ РЕЖИМА 3D, НА НАСТОЯЩЕМ ГОЛОСЕ МАРША ───────────────────────────
	# Берём голос ИЗ ПУЛА AudioManager, а не строим свой. Свой отвечал бы за
	# себя: закрой кто-нибудь срез обратно в игре — стенд остался бы зелёным.
	# Пул на это время свободен (ни одного отчёта о марше ещё не было)
	var p: AudioStreamPlayer3D = AudioManager._march_pool[0]
	p.stream = s
	p.volume_db = AM.MARCH_WALK_DB
	var open_hz: float = p.attenuation_filter_cutoff_hz
	print("  срез у голоса марша в игре: %.0f Гц, глубина %.1f дБ"
		% [open_hz, p.attenuation_filter_db])
	# «До» — движковое умолчание, ради которого всё и разбиралось
	p.attenuation_filter_cutoff_hz = 5000.0

	p.global_position = Vector3(0.0, 0.0, -30.0)
	p.play(0.0)
	var far_now: Array = await _measure()
	p.stop()
	await frames(6)

	p.global_position = Vector3.ZERO
	p.play(0.0)
	var near_now: Array = await _measure()
	p.stop()
	await frames(6)

	# Возвращаем ровно то, что стоит в игре, и мерим ЕЁ
	p.attenuation_filter_cutoff_hz = open_hz
	p.global_position = Vector3(0.0, 0.0, -30.0)
	p.play(0.0)
	var far_open: Array = await _measure()
	p.stop()
	p.stream = null
	await frames(6)

	# ── БОЕВОЙ ПУЛ ТОЙ ЖЕ ПРОВЕРКОЙ ────────────────────────────────────────
	# Срез стоит УМОЛЧАНИЕМ, то есть достаётся ВСЕМ трёхмерным голосам проекта,
	# а не одному маршу. У боевых голосов другая модель спада, и фильтр там
	# может вести себя иначе — проверяем, а не переносим вывод по аналогии
	var q: AudioStreamPlayer3D = AudioManager._pool[0]
	var q_open: float = q.attenuation_filter_cutoff_hz
	q.stream = s
	q.volume_db = AM.MARCH_WALK_DB
	q.global_position = Vector3(0.0, 0.0, -30.0)
	q.attenuation_filter_cutoff_hz = 5000.0
	q.play(0.0)
	var sfx_now: Array = await _measure()
	q.stop()
	await frames(6)
	q.attenuation_filter_cutoff_hz = q_open
	q.play(0.0)
	var sfx_open: Array = await _measure()
	q.stop()
	q.stream = null
	print("\n  БОЕВОЙ ПУЛ (обратный квадрат, 30 м): умолчание 5000 против игры")
	for k in range(BANDS.size()):
		var b2: Array = BANDS[k]
		print("  %5.0f-%-6.0f Гц  %6.1f  %6.1f  |  %+6.1f дБ" % [
			float(b2[0]), float(b2[1]), float(sfx_now[k]), float(sfx_open[k]),
			float(sfx_open[k]) - float(sfx_now[k])])

	# ── ТАБЛИЦА ────────────────────────────────────────────────────────────
	print("\n  полоса          эталон   3D 30м   3D 0м   3D 30м+20500   |  Δ(3D 30м − эталон)")
	for k in range(BANDS.size()):
		var band: Array = BANDS[k]
		print("  %5.0f-%-6.0f Гц  %6.1f  %6.1f  %6.1f  %9.1f      |  %+6.1f дБ" % [
			float(band[0]), float(band[1]),
			float(ref[k]), float(far_now[k]), float(near_now[k]),
			float(far_open[k]), float(far_now[k]) - float(ref[k])])

	# ── ВЕРДИКТЫ ───────────────────────────────────────────────────────────
	print("")
	# Верх — это и есть лязг. Считаем полосы от 4 кГц
	var hi_from := 7
	# ── СУДИМ ТО, ЧТО СТОИТ В ИГРЕ ─────────────────────────────────────────
	# Столбец «3D 30 м» — это ДИАГНОЗ (движковое умолчание 5000 Гц), он обязан
	# быть плохим и вердиктом не является: вечно красная проверка ничего не
	# стережёт. Красным должно становиться то, что режет ИГРА.
	#
	# ── МЕРИМ НАКЛОН, А НЕ УРОВЕНЬ ─────────────────────────────────────────
	# Трёхмерный голос тише плоского эталона во ВСЕХ полосах сразу: у него своя
	# панорама, а у боевого ещё и спад по расстоянию. Это УРОВЕНЬ, к тембру
	# отношения не имеющий. Срез же — вещь избирательная: он валит верх и не
	# трогает низ. Поэтому у каждого режима вычитается его собственный сдвиг по
	# низу и середине, и сравнивается только то, насколько верх отстал ОТ НИХ.
	# Без этого поправкой на 3 дБ краснел бы исправный тракт
	_ok("Марш: верх не срезан против эталона",
		_tilt(far_open, ref, hi_from) >= -CUT_DB,
		"верх отстал от низа на %+.1f дБ (допуск −%.0f)"
		% [_tilt(far_open, ref, hi_from), CUT_DB])
	_ok("Боевой пул: верх не срезан",
		_tilt(sfx_open, ref, hi_from) >= -CUT_DB,
		"верх отстал от низа на %+.1f дБ" % _tilt(sfx_open, ref, hi_from))
	print("  для сравнения, с движковым умолчанием наклон был %+.1f дБ"
		% _tilt(far_now, ref, hi_from))

	var filt := 0.0
	for k in range(hi_from, BANDS.size() - 1):
		filt += float(far_open[k]) - float(far_now[k])
	filt /= float(BANDS.size() - 1 - hi_from)
	print("  цена движкового умолчания 5000 Гц вверху: %+.1f дБ" % filt)

	var dist := 0.0
	for k in range(hi_from, BANDS.size() - 1):
		dist += float(near_now[k]) - float(far_now[k])
	dist /= float(BANDS.size() - 1 - hi_from)
	_ok("Срез не зависел от расстояния (он был всегда)", absf(dist) <= CUT_DB,
		"вплотную верх выше на %+.1f дБ" % dist)

	flat.queue_free()
	await frames(4)
	await _live_checks()

	print("\n=== СПЕКТР МАРША: проверок %d, провалов: %d ===" % [_checks, _fails])
	get_tree().quit(0)

## ═════════════════════════════════════════════════════════════════════════
## ПРОВЕРКИ ПО ЖИВОМУ AudioManager
## ═════════════════════════════════════════════════════════════════════════
## Спектр выше меряет ТРАКТ; здесь проверяется, что игра этим трактом
## пользуется правильно: срез снят у всех голосов, громкость падает с
## расстоянием, а остановка идёт затуханием, а не обрывом
func _live_checks() -> void:
	print("\n── ЖИВОЙ AudioManager ──")
	var am = AudioManager
	if am == null:
		_ok("Автозагрузка звука есть", false, "AudioManager не найден")
		return
	# ── ГЛУШИМ ОБХОД МАРША У GameManager ──────────────────────────────────
	# Автозагрузка живёт и в пустой сцене: четыре раза в секунду она шлёт
	# ПУСТОЙ отчёт (отрядов-то нет) и гасит отряд, только что заведённый
	# стендом. Первая версия ловила на этом «голос не выдан» и обвиняла код
	GameManager.set_physics_process(false)
	await frames(2)

	# 1) Срез снят у ВСЕХ трёхмерных голосов, а не только у марша
	var worst := 0.0
	var total := 0
	for arr in [am._march_pool, am._pool]:
		for v in arr:
			var pl := v as AudioStreamPlayer3D
			if pl == null:
				continue
			total += 1
			if worst <= 0.0 or pl.attenuation_filter_cutoff_hz < worst:
				worst = pl.attenuation_filter_cutoff_hz
	_ok("Срез верха снят у всех 3D-голосов", worst >= 20500.0,
		"голосов %d, самый узкий срез %.0f Гц" % [total, worst])

	# 2) Панорама остаётся: голос трёхмерный, но громкость от зума не зависит
	var m0 := am._march_pool[0] as AudioStreamPlayer3D
	_ok("Марш остаётся трёхмерным", m0 != null,
		"голос %s" % ("AudioStreamPlayer3D" if m0 != null else "нет"))
	_ok("Зум громкость марша не крутит",
		m0.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED,
		"модель спада — отключена, спад считается по земле")

	# 3) Затухание по наземному расстоянию. Слушатель — наша камера в нуле
	var far: float = maxf(am.MARCH_MAX_DISTANCE, GameManager.view_radius())
	var near_at := Vector3(0.0, 0.0, -2.0)
	var mid_at := Vector3(0.0, 0.0, -far * 0.8)
	var out_at := Vector3(0.0, 0.0, -far * 1.5)

	am.march_report([{"sid": 1, "at": near_at, "run": false}])
	var g_near: float = _target_of(am, 1)
	am.march_report([{"sid": 1, "at": mid_at, "run": false}])
	var g_mid: float = _target_of(am, 1)
	_ok("Вблизи марш в полную силу", is_equal_approx(g_near, 1.0),
		"доля %.2f" % g_near)
	_ok("У края слышимости марш тише", g_mid < g_near - 0.05,
		"на %.0f%% радиуса доля %.2f против %.2f" % [80.0, g_mid, g_near])
	am.march_report([{"sid": 1, "at": out_at, "run": false}])
	_ok("За радиусом марша нет вовсе", not am._march.has(1),
		"голосов занято %d" % am._march.size())

	# 4) Остановка идёт ЗАТУХАНИЕМ, а не обрывом. Это и есть жалоба «бах»
	am.march_stop_all()
	await frames(2)
	am.march_report([{"sid": 7, "at": near_at, "run": false}])
	await frames(30)
	if not am._march.has(7):
		_ok("Отряд под замером зазвучал", false,
			"голос не выдан: свободных %d, хвостов %d"
			% [am._march_free.size(), am._march_tail.size()])
		return
	var idx: int = int((am._march[7] as Dictionary)["voice"])
	var pl7 := am._march_pool[idx] as AudioStreamPlayer3D
	var db_before: float = pl7.volume_db
	am.march_report([])          # отряд встал
	await frames(2)
	_ok("Остановка не рвёт луп", pl7.playing,
		"голос продолжает звучать, хвостов %d" % am._march_tail.size())
	# ── СМОТРИМ НА РАЗУМНОМ ОТРЕЗКЕ, А НЕ ЧЕРЕЗ ДВА КАДРА ─────────────────
	# Затухание длится MARCH_FADE_OUT; за два кадра оно честно даёт меньше
	# децибела, и порог «упало больше чем на дБ» краснел на исправном коде.
	# Берём треть затухания: там падение уже слышимое и однозначное
	await frames(int(am.MARCH_FADE_OUT * 60.0 / 3.0) + 1)
	_ok("Остановка гасит громкость", pl7.volume_db < db_before - 2.0,
		"было %.1f дБ, через треть затухания %.1f дБ" % [db_before, pl7.volume_db])
	# Досушиваем и убеждаемся, что голос всё-таки замолкает и возвращается
	await frames(int(am.MARCH_FADE_OUT * 70.0) + 20)
	_ok("Догоревший голос возвращается в пул", not pl7.playing
		and am._march_tail.is_empty(),
		"хвостов %d, свободных %d" % [am._march_tail.size(), am._march_free.size()])
	am.march_stop_all()

## Насколько ВЕРХ режима отстал от эталона СВЕРХ его общего сдвига по низу и
## середине. Ноль — тембр не тронут, минус — верх срезан
func _tilt(mode: Array, ref: Array, hi_from: int) -> float:
	var lo := 0.0
	for k in range(0, hi_from):
		lo += float(mode[k]) - float(ref[k])
	lo /= float(hi_from)
	var worst := 0.0
	for k in range(hi_from, BANDS.size() - 1):
		var d: float = (float(mode[k]) - float(ref[k])) - lo
		if d < worst:
			worst = d
	return worst

func _target_of(am, sid: int) -> float:
	if not am._march.has(sid):
		return -1.0
	return float((am._march[sid] as Dictionary)["target"])
