extends Node

const _OptCfgG = preload("res://scripts/perf_config.gd")

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЦЕНА МАССОВОГО БОЯ В ОТРИСОВКЕ (ОКОННЫЙ)
## ═══════════════════════════════════════════════════════════════════════════
## qa_mass_battle меряет ФИЗИКУ и делает это headless — то есть не рисует ничего.
## Владелец же сообщает о падении до 43 к/с на ~1400 бойцах и о мерцании армии,
## а это по определению происходит в кадре ОТРИСОВКИ. Поэтому стенд оконный.
##
## Меряется:
##   • время кадра ПО ЧАСАМ (Time.get_ticks_usec), а не Performance.TIME_FPS —
##     тот при выключенной вертикальной синхронизации врёт (см. qa_veg);
##   • вызовы отрисовки и число объектов в кадре;
##   • ПЕРЕЕЗДЫ МЕЖДУ БАКЕТАМИ общей отрисовки (FarUnitRenderer.migrations):
##     смена анимации переселяет бойца из одного буфера MultiMesh в другой, и в
##     свалке это происходит постоянно. Именно эта величина отвечает, во что
##     обходится бой сверх марша.
##
## Запуск: godot --path . res://qa_fx/Test.tscn [-- --count=1400] [--secs=6]
## Вертикальная синхронизация снимается: иначе стенд измерит монитор.

const _Opt := preload("res://scripts/perf_config.gd")

var main = null
var _count := 1400
var _secs := 6.0
var _log: Array = []
var _prof := false
## Фоновый режим: окно не перехватывает фокус и уведено с рабочей области.
## По умолчанию ВКЛЮЧЁН — замеры не должны мешать работать
var _bg := true
var _fog := false
var _seed := 0
## Полная экономика: рабочие на ресурсах + работающие здания у обеих сторон.
## Жалоба пришла именно из такой партии, а не из чистого боя
var _workers := 0
var _eco := false

func _ready() -> void:
	call_deferred("_run")

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

## Худший за прогон разрыв «живых, но НЕ НАРИСОВАННЫХ» бойцов
var _worst_gap := 0
var _worst_blink := 0
var _blink_sum := 0
var _blink_n := 0
var _prev_drawn := -1
var _all_units: Array = []

## Средняя длительность кадра ОТРИСОВКИ за n кадров, миллисекунды.
## Попутно считает пропавших из отрисовки: это и есть мерцание, только
## измеримое. Живой боец без слота в общем MultiMesh на экране отсутствует,
## и если такие появляются и исчезают, армия «мигает»
func _frame_ms(n: int) -> float:
	await get_tree().process_frame
	var t0: int = Time.get_ticks_usec()
	for _i in range(n):
		await get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / float(n) / 1000.0

## ── ДЁРГАНЬЕ ШАГА ───────────────────────────────────────────────────────────
## «Мерцание» из отчёта — это два разных явления, и мерить их надо порознь.
## Первое (пропал/появился) считает _scan_gap. Второе — РВАНЫЙ ШАГ: спрайт
## двигается не равномерно, а рывками, потому что логика шагает раз в несколько
## кадров, а рисуется каждый. Мера — разброс длины шага НАРИСОВАННОЙ точки за
## кадр: у ровного движения он около нуля, у рывков шаг чередуется «ноль —
## двойной». Берём выборку бойцов, а не всех: проход по армии сам стоит кадра
var _jit_worst := 0.0

func _step_jitter(units: Array, n: int) -> float:
	var sample: Array = []
	var step: int = maxi(units.size() / 40, 1)
	var i := 0
	while i < units.size() and sample.size() < 40:
		# ПРОВЕРКА ДО ПРИВЕДЕНИЯ: `x as Unit` на освобождённом объекте — ошибка
		# времени выполнения, а бойцы в свалке гибнут прямо по ходу замера
		if is_instance_valid(units[i]):
			var u := units[i] as Unit
			if u != null and not u.is_dead():
				sample.append(u)
		i += step
	if sample.is_empty():
		return 0.0
	var prev: Array = []
	var sum: Array = []
	var sum2: Array = []
	var cnt: Array = []
	for u in sample:
		prev.append((u as Unit).draw_position())
		sum.append(0.0)
		sum2.append(0.0)
		cnt.append(0)
	for _f in range(n):
		await get_tree().process_frame
		for k in range(sample.size()):
			if not is_instance_valid(sample[k]):
				continue
			var u := sample[k] as Unit
			if u == null or u.is_dead():
				continue
			var p: Vector3 = u.draw_position()
			var q: Vector3 = prev[k]
			var d: float = Vector2(p.x - q.x, p.z - q.z).length()
			prev[k] = p
			sum[k] = float(sum[k]) + d
			sum2[k] = float(sum2[k]) + d * d
			cnt[k] = int(cnt[k]) + 1
	# СЧИТАЕМ ТОЛЬКО ИДУЩИХ. Стоящий боец даёт нулевой средний шаг, и разброс,
	# делённый на этот ноль, взлетает до небес — метрика мерила бы долю
	# неподвижных в выборке, а не ровность движения
	var acc := 0.0
	var used := 0
	for k in range(sample.size()):
		var c: int = int(cnt[k])
		if c < 10:
			continue
		var mean: float = float(sum[k]) / float(c)
		if mean < 0.005:
			continue                    # стоит на месте — дёргаться нечему
		var var_: float = maxf(float(sum2[k]) / float(c) - mean * mean, 0.0)
		acc += sqrt(var_) / mean
		used += 1
	return (acc / float(used)) if used > 0 else 0.0

## Проход по армии ВНЕ замера времени: он сам O(n) на кадр и испортил бы
## измеряемое число (проверено — приписывал шесть миллисекунд на ровном месте)
func _scan_gap(n: int) -> void:
	# Счётчик дрожания сбрасывается на КАЖДЫЙ замер: между фазами проходят сотни
	# кадров (отряды получают приказы, сходятся, гибнут), и разница «сколько было
	# нарисовано тогда и сейчас» — это не мерцание, а другая фаза боя. Без сброса
	# в «худшем скачке» стабильно оказывалась именно она
	_prev_drawn = -1
	for _i in range(n):
		await get_tree().process_frame
		var alive := 0
		for u in GameManager._live_units:
			var uu := u as Unit
			if uu != null and is_instance_valid(uu) and not uu.is_dead() 					and not uu.garrisoned:
				alive += 1
		var gap: int = alive - GameManager.far_units.registered_count()
		if gap > _worst_gap:
			_worst_gap = gap
		# Дрожание: насколько число нарисованных скачет от кадра к кадру.
		# Именно это видно глазом как мерцание — не сам факт, что кто-то скрыт
		var drawn: int = GameManager.far_units.registered_count()
		if _prev_drawn >= 0:
			var d: int = absi(drawn - _prev_drawn)
			if d > _worst_blink:
				_worst_blink = d
			_blink_sum += d
			_blink_n += 1
		_prev_drawn = drawn

func _spawn_army(fac: int, at: Vector3, n: int, kind: String) -> Array:
	var out: Array = []
	var cols: int = int(ceil(sqrt(float(n))))
	var sid: int = GameManager.new_squad(fac, kind)
	var in_squad := 0
	for i in range(n):
		var u: Unit
		match kind:
			"archer":   u = Archer.new()
			"warrior":  u = Warrior.new()
			_:          u = Spearman.new()
		u.faction = fac
		main.world_add(u)
		u.global_position = Vector3(
			at.x + float(i % cols) * 0.75, 0.0, at.z + float(i / cols) * 0.75)
		# Отряды по 40: столько же, сколько даёт настоящий найм, — от размера
		# отряда зависят и коридоры, и разметка линии соприкосновения
		if in_squad >= 40:
			sid = GameManager.new_squad(fac, kind)
			in_squad = 0
		GameManager.add_to_squad(sid, u)
		in_squad += 1
		out.append(u)
	return out

## ── ПРОФИЛЬ СНИМАЕТСЯ НА КАЖДОЙ ФАЗЕ, А НЕ ОДИН РАЗ В КОНЦЕ ──────────────────
## Раньше --prof включался ПОСЛЕ всех замеров, то есть в затяжном бою, а таблица
## подписывалась «доли веток в свалке». Читать её как профиль марша или стояния
## было прямой ошибкой: в затяжном бою половина армии уже мертва, идущих почти
## нет, и process_move там заведомо не тот, что на сближении. Кадр держат ровно
## фазы «стоят» и «сближение», и профиль нужен именно по ним.
func _phase_profile(title: String) -> void:
	if not _prof:
		return
	_Opt.profile_physics = true
	_Opt.prof_reset()
	await frames(90)
	var rep: Array = _Opt.prof_report()
	_Opt.profile_physics = false
	print("\n  ── доли веток физтика: %s ──" % title)
	for row in rep:
		print("    %s" % str(row))

func _measure(title: String, secs: float) -> void:
	GameManager.far_units.reset_counters()
	# Лёгкие счётчики проекта: «тик» — весь обход армии в физкадре, «визуал» —
	# он же в кадре отрисовки. Оба стоят по одной паре usec на кадр
	_Opt.tick_meter = true
	_Opt.vis_meter = true
	_Opt.tick_reset()
	_Opt.vis_reset()
	var frames_n: int = int(secs * 60.0)
	var ms: float = await _frame_ms(frames_n)
	var tick: float = _Opt.tick_ms()
	await _scan_gap(30)
	var vis: float = _Opt.vis_ms()
	var calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var mig: int = GameManager.far_units.migrations
	var reg: int = GameManager.far_units.reg_calls
	var jit: float = await _step_jitter(_all_units, 60)
	_jit_worst = maxf(_jit_worst, jit)
	_log.append("  %-14s %6.2f мс (%5.1f к/с) | тик %5.2f | визуал %5.2f | прочее %5.2f | вызовов %4d | переездов %5.1f | рывок шага %.2f" % [
		title, ms, 1000.0 / maxf(ms, 0.001), tick, vis,
		maxf(ms - tick - vis, 0.0), calls,
		float(mig) / float(frames_n), jit])

## ── ПОЛНАЯ ЭКОНОМИКА ────────────────────────────────────────────────────────
## Замок, казарма и кузница у каждой стороны + бригады рабочих на ближайших
## ресурсах. Ресурсы обеим сторонам выдаются с запасом: стенд меряет нагрузку,
## а не борьбу с балансом
var _worker_n := 0

func _build_economy() -> void:
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		ResourceManager.add_resource(f, Constants.RESOURCE_WOOD, 900000.0)
		ResourceManager.add_resource(f, Constants.RESOURCE_GOLD, 900000.0)
		ResourceManager.add_resource(f, Constants.RESOURCE_STONE, 900000.0)
		ResourceManager.add_resource(f, Constants.RESOURCE_FOOD, 900000.0)
	var side := 0
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		var sx: float = -46.0 if side == 0 else 46.0
		side += 1
		var c := Castle.new()
		c.faction = f
		main.world_add(c)
		c.global_position = Vector3(sx, GameManager.get_terrain_height(sx, -34.0), -34.0)
		var b := Barracks.new()
		b.faction = f
		main.world_add(b)
		b.global_position = Vector3(sx, GameManager.get_terrain_height(sx, -26.0), -26.0)
		var sm := Smithy.new()
		sm.faction = f
		main.world_add(sm)
		sm.global_position = Vector3(sx, GameManager.get_terrain_height(sx, -18.0), -18.0)
		await frames(4)
		# Производство идёт ВСЮ ДОРОГУ: спавн новых бойцов — это переезды между
		# бакетами и рост реестра прямо во время боя, а именно так и играют
		for _i in range(6):
			b.train_from_config("spearman")
			c.train_from_config("worker")
		# Бригады на ближайшую руду и лес
		var per: int = _workers / 2
		var res := _nearest_resources(Vector3(sx, 0.0, -30.0), per)
		for i in range(per):
			var w := Worker.new()
			w.faction = f
			main.world_add(w)
			var wx: float = sx + float(i % 8) * 0.9 - 3.6
			var wz: float = -30.0 + float(i / 8) * 0.9
			w.global_position = Vector3(wx, GameManager.get_terrain_height(wx, wz), wz)
			w.sync_row()
			_worker_n += 1
			if res.size() > 0:
				w.command_gather(res[i % res.size()])

func _nearest_resources(from: Vector3, want: int) -> Array:
	var all := get_tree().get_nodes_in_group("resource_nodes")
	var scored: Array = []
	for n in all:
		var r := n as ResourceNode
		if r == null or not is_instance_valid(r):
			continue
		scored.append([r.global_position.distance_to(from), r])
	scored.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for i in range(mini(want, scored.size())):
		out.append(scored[i][1])
	return out

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--count="):
			_count = int(s.substr(8))
		elif s.begins_with("--secs="):
			_secs = float(s.substr(7))
		elif s == "--nobc":
			_Opt.batch_combat = false
		elif s == "--prof":
			_prof = true
		elif s.begins_with("--visx="):
			_Opt.vis_shards_extra = int(s.substr(7))
			_Opt.vis_extra_from = 0
		elif s == "--show":
			# Показать окно как обычно (для глазной проверки картинки)
			_bg = false
		elif s == "--fog":
			_fog = true
		elif s.begins_with("--seed="):
			_seed = int(s.substr(7))
		elif s.begins_with("--workers="):
			_workers = int(s.substr(10))
			_eco = _workers > 0
		elif s == "--nocatchup":
			# А/Б: выключить покадровый догон картинки (Unit.tick_draw)
			_Opt.draw_catchup = false
		elif s == "--eco":
			_eco = true
			if _workers == 0:
				_workers = 80
	# ── КАРТА ДОЛЖНА БЫТЬ ОДНА И ТА ЖЕ ──────────────────────────────────────
	# Лес и руда расставляются случайно, а бой идёт в середине карты: без
	# фиксации зерна два прогона меряют разные поля боя, и разброс (46-93 к/с на
	# одном и том же коде) перекрывает любой выигрыш, который хочется сравнить
	if _seed != 0:
		seed(_seed)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	# ── ОКНО НЕ ЛЕЗЕТ НА ГЛАВНЫЙ ЭКРАН И НЕ ОТБИРАЕТ ФОКУС ──────────────────
	# Требование владельца: замеры не должны мешать работе. Свернуть окно нельзя
	# — свёрнутое окно движок не отрисовывает, и стенд измерил бы пустоту вместо
	# кадра. Поэтому окно остаётся отрисовываемым, но: не берёт фокус
	# (WINDOW_FLAG_NO_FOCUS), не всплывает поверх чужих окон и уводится за
	# нижний край рабочего стола.
	# --nofocus=0 возвращает обычное поведение, когда картинку надо посмотреть
	if _bg:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		var scr: Vector2i = DisplayServer.screen_get_size()
		DisplayServer.window_set_position(Vector2i(scr.x - 240, scr.y - 120))
	# БЕЗ ЭТОГО СТЕНД МЕРЯЕТ МОНИТОР, а не игру (тот же разбор, что в qa_veg)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	# ДЕРЕВНЯ ГОБЛИНОВ ВЫКЛЮЧЕНА: стенд меряет ровно ту армию, которую
	# заявляет, и не растягивает габарит сетки на свой угол карты
	_OptCfgG.goblin_village = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	# Туман гасит чужих целиком, и половина армии просто не рисовалась бы —
	# стенд мерит цену ВИДИМОГО боя
	# ── ТУМАН: ПО УМОЛЧАНИЮ ВЫКЛЮЧЕН, С --fog ВКЛЮЧЁН ───────────────────────
	# Выключенный меряет цену ВИДИМОГО боя. Включённый нужен для другого вопроса:
	# чужие бойцы под пеленой не рисуются вовсе, и на кромке видимости они
	# гаснут и загораются при каждом пересчёте маски — это и есть «мерцание
	# армии». Разрыв «жив, но не нарисован» тут законно ненулевой (враги в
	# темноте), поэтому в этом режиме считается ДРОЖАНИЕ этого разрыва, а не он сам
	if GameManager.fog != null and not _fog:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false

	var half: int = _count / 2
	var blue: Array = _spawn_army(Constants.FACTION_PLAYER, Vector3(-14.0, 0.0, 0.0), half, "spearman")
	var red: Array = _spawn_army(Constants.FACTION_ENEMY, Vector3(14.0, 0.0, 0.0), half, "warrior")
	_all_units = blue + red
	if _eco:
		await _build_economy()
	await frames(10)

	# Камеру прибиваем на середину поля: её краевая прокрутка увела бы обзор,
	# и стенд мерил бы пустой экран (разбор в qa_march_perf)
	main.focus_camera_on(Vector3.ZERO)
	await get_tree().process_frame
	if main._camera != null:
		main._camera.set_process(false)
		main._camera.jump_to(Vector3.ZERO, main._camera.max_height * 0.55)
	GameManager.update_view_point(Vector3.ZERO)
	await frames(6)

	print("\n═══ ЦЕНА МАССОВОГО БОЯ В ОТРИСОВКЕ | %d бойцов ═══" % _count)
	await _measure("стоят", _secs)
	await _phase_profile("стоят")

	# ПРОВЕРКА ЖИВОСТИ ОБЯЗАТЕЛЬНА: армии стоят в 28 м друг от друга, а сторона
	# каждого каре под 27 м — их края соприкасаются, и первые бойцы гибнут уже
	# в фазе «стоят». `x as Unit` на освобождённом объекте — ошибка выполнения
	for u in blue:
		if is_instance_valid(u):
			(u as Unit).command_move(Vector3(14.0, 0.0, 0.0), false, Vector3.RIGHT)
	for u in red:
		if is_instance_valid(u):
			(u as Unit).command_move(Vector3(-14.0, 0.0, 0.0), false, Vector3.LEFT)
	await frames(60)
	await _measure("сближение", _secs)
	await _phase_profile("сближение")
	await frames(180)
	await _measure("свалка", _secs)
	await _phase_profile("свалка")
	await frames(240)
	await _measure("затяжной бой", _secs)

	# ── РАЗБИВКА ПО ВЕТКАМ ──────────────────────────────────────────────────
	# Профиль носит на себе свой же замер (пара usec на КАЖДУЮ ветку КАЖДОГО
	# бойца) и завышает итог примерно вдвое — поэтому он включается ОТДЕЛЬНОЙ
	# фазой и читается только как ДОЛИ, а абсолютные числа берутся из счётчиков
	# выше (см. CLAUDE.md, «Profiling — two instruments»)
	await _phase_profile("затяжной бой")

	for s in _log:
		print(s)
	var alive := 0
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and not (n as Unit).is_dead():
			alive += 1
	print("  живых: %d" % alive)
	print("  МЕРЦАНИЕ: скачок числа нарисованных за кадр — худший %d, средний %.1f" % [
		_worst_blink, float(_blink_sum) / float(maxi(_blink_n, 1))])
	print("  ХУДШИЙ РАЗРЫВ «жив, но не нарисован»: %d %s" % [
		_worst_gap, "— МЕРЦАНИЕ" if _worst_gap > 0 else "(мерцания нет)"])
	print("  ХУДШИЙ РЫВОК ШАГА: %.2f %s" % [_jit_worst,
		"— ДЁРГАЕТСЯ" if _jit_worst > 0.5 else "(движение ровное)"])
	if _eco:
		print("  экономика: рабочих %d, зданий %d, ресурсов на карте %d" % [
			_worker_n, get_tree().get_nodes_in_group("all_buildings").size(),
			get_tree().get_nodes_in_group("resource_nodes").size()])
	print("\n=== QA_FX DONE ===")
	get_tree().quit(0)
