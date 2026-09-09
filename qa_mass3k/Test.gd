extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ПРОФИЛЬ ПАРТИИ НА ТРЁХ ТЫСЯЧАХ: СВАЛКА ПЛЮС ЖИВАЯ ЭКОНОМИКА
## ═══════════════════════════════════════════════════════════════════════════
## ЧЕМ ОТЛИЧАЕТСЯ ОТ qa_fps. Тот меряет ДВЕ СТОЯЩИЕ АРМИИ копейщиков, разведённые
## по углам: ни боя, ни рабочих, ни смешанного состава. Владелец же видит 41 кадр
## в СВАЛКЕ, где 1200 бойцов игрока, 1000 гоблинов и 800 у красного ИИ, и у
## каждой стороны по четыре десятка рабочих на добыче. Три отличия — состав,
## контакт и экономика — и каждое меняет, какая ветка тика становится главной.
##
## ЗАМЕР ЧЕСТНЫЙ, А НЕ ПО ПРОФИЛЮ ВЕТОК (см. docs/PERF_6000.md, раздел 6):
## подсистема ГАСИТСЯ и ВОЗВРАЩАЕТСЯ, цена считается против среднего двух
## базовых замеров вокруг неё. Лестницей «гасим и не возвращаем» мерить нельзя —
## мир между ступенями живёт.
##
## СЧИТАЕМ МИЛЛИСЕКУНДЫ. Кадры не складываются: «минус 10 FPS» на 120 и на 45 —
## разные затраты.
##
## Запуск (ОКНО ОБЯЗАТЕЛЬНО: в headless отрисовки нет вовсе, и FPS там — темп
## главного цикла, а не кадр игрока):
##   godot --path . res://qa_mass3k/Test.tscn -- res=1920x1080
## Аргументы: player=N goblin=N ai=N workers=N res=WxH phase=idle|melee|both

const _Opt = preload("res://scripts/perf_config.gd")

var main = null
var _rows: Array = []
var _mine: Array = []
var _foes: Array = []
var _horde: Array = []
var _workers: Array = []

var N_PLAYER := 1200
var N_GOBLIN := 1000
var N_AI := 800
var N_WORKERS := 40
var RES := Vector2i(1920, 1080)

## Состав армии игрока и красного — как в партии, а не «одни копейщики»
const MIX := {
	"res://scenes/units/Spearman.tscn": 0.45,
	"res://scenes/units/Archer.tscn":   0.25,
	"res://scenes/units/Warrior.tscn":  0.20,
	"res://scenes/units/GoblinPigRider.tscn": 0.10,
}
const SQUAD_SIZE := 40
const COLS := 8
const GAP := 0.75

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

## Один замер кадра. Прогрев обязателен: смена настройки почти всегда стоит
## одного тяжёлого кадра, а TIME_FPS усредняется по последней секунде и тянет
## этот кадр за собой ещё много замеров подряд
func _sample(warm: int = 40, n: int = 45) -> Dictionary:
	# ── СТЕНД МЕРЯЕТ, А НЕ ИГРАЕТ: СЛУЧАЙНАЯ ПАУЗА СНИМАЕТСЯ ────────────────
	# Пауза партии висит на ПРОБЕЛЕ, оконный стенд забирает фокус при старте,
	# и случайное нажатие (машина под управлением агента печатает команды)
	# замораживает дерево: все метры дальше честно меряют мёртвую сцену.
	# Поймано на живом прогоне: физтик −1 (ноль замеров), 393-430 «FPS» свалки
	if get_tree().paused:
		get_tree().paused = false
	await frames(warm)
	_Opt.tick_reset()
	_Opt.vis_reset()
	var fps := 0.0
	var draws := 0
	for _i in range(n):
		await get_tree().process_frame
		fps += Performance.get_monitor(Performance.TIME_FPS)
		draws = maxi(draws, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var f: float = fps / float(n)
	return {
		"fps": f,
		"ms": 1000.0 / maxf(f, 0.001),
		"tick": _Opt.tick_ms(),
		"vis": _Opt.vis_ms(),
		"draws": draws,
	}

## Цена подсистемы: гасим — меряем — возвращаем — меряем базу снова
func _cost(label: String, off: Callable, on: Callable,
		base_before: Dictionary) -> Dictionary:
	off.call()
	var without: Dictionary = await _sample()
	on.call()
	var base_after: Dictionary = await _sample()
	var base_ms: float = (float(base_before["ms"]) + float(base_after["ms"])) * 0.5
	var base_tick: float = (float(base_before["tick"]) + float(base_after["tick"])) * 0.5
	_rows.append([label, base_ms - float(without["ms"]),
		base_tick - float(without["tick"]),
		float(without["fps"]), int(base_before["draws"]) - int(without["draws"])])
	return base_after

# ─────────────────────────────────────────────────────────────────────────────
# СБОРКА СЦЕНЫ
# ─────────────────────────────────────────────────────────────────────────────

func _mix_list(n: int) -> Array:
	var out: Array = []
	var total := 0.0
	for k in MIX: total += float(MIX[k])
	for k in MIX:
		var cnt: int = int(round(float(n) * float(MIX[k]) / total))
		for _i in range(cnt): out.append(k)
	while out.size() < n: out.append("res://scenes/units/Spearman.tscn")
	return out

func _stat_of(scene: String) -> String:
	if scene.contains("Archer"): return "archer"
	if scene.contains("Warrior"): return "warrior"
	if scene.contains("PigRider"): return "goblin_rider"
	return "spearman"

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Армия отрядами по SQUAD_SIZE, с РАЗМЕТКОЙ строя: без курса пакетный пересчёт
## рядов (GameManager._push_squad_ranks) отказывается работать и каждый боец
## считает ряд сам — путь, которым игра почти не ходит
func _spawn_army(list: Array, fac: int, at: Vector3, course: Vector3) -> Array:
	var out: Array = []
	var i := 0
	var col := 0
	while i < list.size():
		var n: int = mini(SQUAD_SIZE, list.size() - i)
		var kind: String = String(list[i])
		var sid: int = GameManager.new_squad(fac, _stat_of(kind))
		var bx: float = at.x + float(col % 6) * 9.0
		var bz: float = at.z + float(col / 6) * 8.0
		var slots: Array = []
		for k in range(n):
			var u := _spawn(kind, fac,
				Vector3(bx + float(k % COLS) * GAP, 0.0, bz + float(k / COLS) * GAP))
			GameManager.add_to_squad(sid, u)
			out.append(u)
			slots.append(u.global_position)
		GameManager.squad_set_formation(sid, slots, course, false)
		i += n
		col += 1
	return out

## Рабочие НА ДОБЫЧЕ: экономика обязана крутиться, иначе стенд меряет не ту
## сцену. Каждому даётся ближайшее к нему дерево — тот же путь, что у приказа
## игрока (Worker.command_gather)
func _spawn_workers(fac: int, at: Vector3, n: int) -> Array:
	var out: Array = []
	var trees: Array = GameManager.nodes_in_group_cached("resource_nodes")
	for i in range(n):
		var u := _spawn("res://scenes/units/Worker.tscn", fac,
			at + Vector3(float(i % 8) * 1.2, 0.0, float(i / 8) * 1.2))
		out.append(u)
		var best: Node3D = null
		var bd := INF
		for t in trees:
			var rn := t as ResourceNode
			if rn == null or not rn.is_gatherable():
				continue
			var d: float = Vector2(rn.global_position.x - u.global_position.x,
				rn.global_position.z - u.global_position.z).length_squared()
			if d < bd:
				bd = d
				best = rn
		if best != null and u.has_method("command_gather"):
			u.command_gather(best)
	return out

## Раздвинуть ортокамеру так, чтобы бой помещался в кадр целиком: иначе стенд
## меряет отсечение пирамидой видимости, а не отрисовку
func _fit_camera(on: Array) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or on.is_empty():
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var mid := Vector3.ZERO
	var cnt := 0
	for u in on:
		if not is_instance_valid(u):
			continue
		var p: Vector3 = (u as Node3D).global_position
		mid += p
		cnt += 1
		lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.z)
	if cnt == 0:
		return
	mid /= float(cnt)
	main.focus_camera_on(Vector3(mid.x, 0.0, mid.z))
	await frames(2)
	if main._camera != null:
		(main._camera as Node).set_process(false)
	(cam as Camera3D).size = maxf(maxf((hi.x - lo.x) * 1.15,
		(hi.y - lo.y) * 1.7) + 10.0, 24.0)
	var half: Vector2 = Vector2((hi.x - lo.x) * 0.5, (hi.y - lo.y) * 0.5)
	GameManager.update_view_point(Vector3(mid.x, 0.0, mid.z), half.length() + 4.0)

func _run() -> void:
	var phase := "both"
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("player="):   N_PLAYER = int(s.substr(7))
		elif s.begins_with("goblin="): N_GOBLIN = int(s.substr(7))
		elif s.begins_with("ai="):     N_AI = int(s.substr(3))
		elif s.begins_with("workers="): N_WORKERS = int(s.substr(8))
		elif s.begins_with("phase="):  phase = s.substr(6)
		elif s.begins_with("res="):
			var p := s.substr(4).split("x")
			if p.size() == 2:
				RES = Vector2i(int(p[0]), int(p[1]))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(RES)
	get_tree().root.content_scale_size = RES
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(11)

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	GameManager.world_bounds_enabled = false

	# ── АРМИИ СХОДЯТСЯ ЛОБ В ЛОБ ───────────────────────────────────────────
	# Гоблины ставятся ТРЕТЬЕЙ стороной там же: в партии свалка на центре карты
	# и есть общая куча, а не два аккуратных строя
	_mine  = _spawn_army(_mix_list(N_PLAYER), Constants.FACTION_PLAYER,
		Vector3(-46.0, 0.0, -22.0), Vector3(1, 0, 0))
	_foes  = _spawn_army(_mix_list(N_AI), Constants.FACTION_ENEMY,
		Vector3(20.0, 0.0, -18.0), Vector3(-1, 0, 0))
	_horde = _spawn_army(_mix_list(N_GOBLIN), Constants.FACTION_GOBLIN,
		Vector3(20.0, 0.0, 16.0), Vector3(-1, 0, 0))
	# Рабочие обеих сторон — на добыче, у своих углов карты
	_workers = _spawn_workers(Constants.FACTION_PLAYER, Vector3(-95.0, 0.0, -45.0), N_WORKERS)
	_workers.append_array(_spawn_workers(Constants.FACTION_ENEMY, Vector3(80.0, 0.0, 45.0), N_WORKERS))
	await pframes(40)
	await _fit_camera(_mine)
	# ── ДЛИННЫЙ ПРОГРЕВ ПОСЛЕ СПАВНА ───────────────────────────────────────
	# Рождение трёх тысяч бойцов стоит секунд десять ОДНОГО кадра, а TIME_FPS
	# усредняется по последней секунде
	await frames(200)

	_Opt.tick_meter = true
	_Opt.vis_meter = true

	var idle: Dictionary = {}
	if phase != "melee":
		idle = await _sample()
		print("\n───── ФАЗА 1: СТОЯТ (армии разведены, экономика идёт) ─────")
		_print_frame(idle)

	# ── ФАЗА 2: СВАЛКА ─────────────────────────────────────────────────────
	# Приказ атаки каждой стороне на ближайшего чужого: через полминуты это
	# одна общая куча в центре — ровно то, на что жалуется владелец
	_charge(_mine, _foes)
	_charge(_foes, _mine)
	_charge(_horde, _mine)
	await frames(60 * 6)
	await _fit_camera(_mine)
	# ── СВАЛКА ЗАМОРАЖИВАЕТСЯ ПО ЧИСЛЕННОСТИ ───────────────────────────────
	# Без этого стенд меряет РАЗНЫЕ сцены: за минуту A/B армия редеет с 3500 до
	# 2000, тик падает сам собой, и «вариант B» получает фору просто потому,
	# что мерился позже. Первая версия так и намеряла отрицательный прирост
	# кадров при явно более дешёвом тике.
	# Запас жизни поднимается всем разом: бой при этом идёт как шёл (удары,
	# продавливание, выбор целей, строй), меняется только то, что никто не
	# выбывает — то есть нагрузка держится постоянной
	_freeze_losses()
	await frames(60)
	var melee: Dictionary = await _sample()
	print("\n───── ФАЗА 2: СВАЛКА ─────")
	_print_frame(melee)
	var base: Dictionary = melee

	base = await _cost("туман войны",
		func():
			if GameManager.fog != null:
				GameManager.fog.enabled = false
				(GameManager.fog as Node3D).visible = false,
		func():
			if GameManager.fog != null:
				GameManager.fog.enabled = true
				(GameManager.fog as Node3D).visible = true,
		base)
	base = await _cost("HUD",
		func():
			if main.hud != null:
				(main.hud as CanvasLayer).visible = false
				(main.hud as Node).set_process(false),
		func():
			if main.hud != null:
				(main.hud as CanvasLayer).visible = true
				(main.hud as Node).set_process(true),
		base)
	base = await _cost("мышление ИИ (красный + гоблины)",
		func(): _ai_process(false), func(): _ai_process(true), base)
	base = await _cost("растительность (отрисовка)",
		func(): _veg_visible(false), func(): _veg_visible(true), base)
	base = await _cost("спрайты армии (отрисовка)",
		func(): _army_visible(false), func(): _army_visible(true), base)
	base = await _cost("ФИЗИЧЕСКИЙ ТИК АРМИИ",
		func(): _army_ticking(false), func(): _army_ticking(true), base)
	base = await _cost("визуальный тик армии",
		func(): _army_drawing(false), func(): _army_drawing(true), base)
	# ── СТРЕЛЫ — ЭТО УЗЛЫ, И КАЖДАЯ ЭТО ОТДЕЛЬНЫЙ ВЫЗОВ ОТРИСОВКИ ──────────
	# У стрелы своя ось и свой материал, общего MultiMesh у них нет и быть не
	# может (см. CorpseRenderer.MAX_ARROWS_PER_CORPSE). В свалке с лучниками
	# их на поле под две сотни — столько же вызовов
	# Список собирается ОДИН РАЗ: обход мира стоит дорого, а стенду нужен один
	# и тот же набор в обеих половинах замера
	_arrow_cache = _find_arrows()
	base = await _cost("стрелы (узлы, у каждой свой вызов отрисовки)",
		func(): _arrows_visible(false), func(): _arrows_visible(true), base)
	base = await _cost("тела павших (слой)",
		func(): _corpses_visible(false), func(): _corpses_visible(true), base)

	# ── A/B ЧЕРЕДОВАНИЕМ: ЧЕТВЁРТЫЙ ШАРД ФИЗИКИ ────────────────────────────
	# Правило проекта: правку меньше чем на миллисекунду одиночным сравнением
	# двух ЗАПУСКОВ подтвердить нельзя — разброс прогонов шире эффекта.
	# База и вариант меряются ПОДРЯД, несколько раундов
	await _ab("шардов физики 3 против 4",
		func(): _Opt.tick_shards_force = 3,
		func(): _Opt.tick_shards_force = 4)
	await _ab("шардов физики 4 против 5",
		func(): _Opt.tick_shards_force = 4,
		func(): _Opt.tick_shards_force = 5)
	_Opt.tick_shards_force = 0
	await _ab("лишних визуальных шардов 2 против 4",
		func(): _Opt.vis_shards_extra = 2,
		func(): _Opt.vis_shards_extra = 4)
	_Opt.vis_shards_extra = 2
	await _ab("такт позы (anim_every_max) 5 против 8",
		func(): _Opt.anim_every_max = 5,
		func(): _Opt.anim_every_max = 8)
	_Opt.anim_every_max = 5
	# ── ДРЁМА БОЯ: ЕДИНСТВЕННО ЧЕСТНАЯ МЕРКА — ЧЕРЕДОВАНИЕ ─────────────────
	# Межпрогонные сравнения тут врали: фаза «стоят» (без всякой дрёмы)
	# уплывала на 7 FPS между прогонами одного и того же кода
	await _ab("дрёма боя: ВЫКЛ против ВКЛ",
		func(): _Opt.atk_snooze = false,
		func(): _Opt.atk_snooze = true, 4)
	_Opt.atk_snooze = true
	# ── ТИК АРМИИ 60 ПРОТИВ 30 Гц (этап C.2) ───────────────────────────────
	# Меняется делитель тика армии; лестница шардов сама даёт бойцу ту же
	# личную частоту (perf_config.shards_for от army_hz), так что меряется
	# именно цена ТАКТОВЫХ статей (сетка, проходы, свипы, обвязка), а не другое
	# поведение армии. ВНИМАНИЕ к прочтению: физтик печатается ЗА ТИК, а тиков
	# при делителе вдвое меньше — сравнивать надо кадр и FPS
	await _ab("тик армии 60 Гц против 30 Гц",
		func(): _Opt.army_tick_div = 1,
		func(): _Opt.army_tick_div = 2, 4)
	_Opt.army_tick_div = 1
	# ── ДОГОН КАРТИНКИ: GDScript ПРОТИВ ЯДРА (этап C.1) ────────────────────
	# Обе стороны пишут в буферы через ядро; меряется именно «кто считает
	# сглаживание и когда» — за такт бойца или C#-проходом каждый кадр
	await _ab("догон картинки: GDScript против ядра",
		func(): _Opt.vis_core_path = false,
		func(): _Opt.vis_core_path = true, 4)
	_Opt.vis_core_path = true
	# ── ЭТАП D1: ТЫЛОВОЙ НАПОР + АВТОПИЛОТ ПОДХОДА ─────────────────────────
	# Выключение гасит только ВЗВОД: уже арендованные строки штатно вернутся
	# через пересчёт melee (аренда) и пробуждения — дренаж на прогреве замера
	await _ab("D1 (напор+автопилот): ВЫКЛ против ВКЛ",
		func():
			_Opt.rear_press = false
			_Opt.approach_autopilot = false,
		func():
			_Opt.rear_press = true
			_Opt.approach_autopilot = true, 4)
	_Opt.rear_press = true
	_Opt.approach_autopilot = true
	# ── ЭТАП D2: ПОТОКИ ПАКЕТНЫХ ПРОХОДОВ ──────────────────────────────────
	await _ab("D2 потоки ядра: 1 против 3",
		func(): _Opt.core_threads = 1,
		func(): _Opt.core_threads = 3, 4)
	_Opt.core_threads = 3
	# ── ЭТАП D3: МАСКА ТУМАНА В ЯДРЕ ───────────────────────────────────────
	await _ab("D3 туман: GDScript против ядра",
		func(): _Opt.fog_core = false,
		func(): _Opt.fog_core = true, 4)
	_Opt.fog_core = true

	# ── РАЗБИВКА ФИЗ. ТИКА ПО ВЕТКАМ ───────────────────────────────────────
	# Профиль носит на себе свой же замер и завышает сумму примерно вдвое:
	# сравнивать его строки можно только ДРУГ С ДРУГОМ (ранжирование), а не с
	# базой выше (см. docs/PERF_6000.md, раздел 6)
	_Opt.profile_physics = true
	_Opt.prof_reset()
	await pframes(120)
	await frames(1)
	var prof: Array = _Opt.prof_report()
	_Opt.profile_physics = false

	# ── ФАЗА 3: РЕАЛЬНЫЕ ПОТЕРИ (30-я минута партии) ────────────────────────
	# Замер намеренно ПОСЛЕДНИЙ: он разбирает сцену. Все предыдущие цены и A/B
	# мерились на замороженной численности; здесь смертность возвращается,
	# с края карты заходит свежая волна гоблинов, и кадр меряется В РАЗГАР
	# массовой гибели — с работающим ветеранством (счёт убийств, заслуги
	# отрядов), укладкой тел, передачей знамён и паникой. Сравнение с фазой 2
	# и отвечает на вопрос «что стоит сама гибель»: сцена та же, добавились
	# только смерти
	print("\n───── ФАЗА 3: РЕАЛЬНЫЕ ПОТЕРИ + ВОЛНА С КРАЯ ─────")
	var wave: Array = _spawn_army(_mix_list(200), Constants.FACTION_GOBLIN,
		Vector3(100.0, 0.0, 8.0), Vector3(-1, 0, 0))
	_charge(wave, _mine)
	# Смертность: каждому оставляется малый запас, чтобы гибель шла массово
	# и непрерывно всё окно замера (2-3 удара на смерть)
	for u in GameManager._live_units:
		if not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu == null or uu.is_dead():
			continue
		uu.max_health = 40.0
		uu.current_health = 40.0
	var live0: int = GameManager._live_units.size()
	var corpses0: int = GameManager.corpses.count() if GameManager.corpses != null else 0
	await frames(30)
	var death: Dictionary = await _sample(10, 45)
	var live1: int = GameManager._live_units.size()
	var corpses1: int = GameManager.corpses.count() if GameManager.corpses != null else 0
	_print_frame(death)
	var span_s: float = 45.0 / maxf(float(death["fps"]), 1.0) + 10.0 / maxf(float(death["fps"]), 1.0)
	print("  погибло за окно замера: %d (%.0f смертей/с) | тел на поле: %d → %d"
		% [live0 - live1, float(live0 - live1) / maxf(span_s, 0.01), corpses0, corpses1])
	print("  против фазы 2 (свалка без потерь): кадр %+.2f мс, физтик %+.2f мс"
		% [float(death["ms"]) - float(melee["ms"]),
			float(death["tick"]) - float(melee["tick"])])

	_Opt.tick_meter = false
	_Opt.vis_meter = false

	print("\n═════ ЦЕНА ПОДСИСТЕМ В КАДРЕ (свалка) ═════")
	print("  подсистема                          кадр, мс   физтик, мс   без неё, FPS   вызовов")
	print("  ──────────────────────────────────+──────────+────────────+─────────────+─────────")
	for r in _rows:
		var row: Array = r
		print("  %-34s %8.2f %12.2f %13.1f %9d" % [String(row[0]), float(row[1]),
			float(row[2]), float(row[3]), int(row[4])])

	print("\n─── РАЗБИВКА ФИЗ. ТИКА (профиль завышает сумму ~вдвое) ───")
	var sum_us := 0
	for row in prof:
		if not String(row[0]).begins_with("!"):
			sum_us += int(row[1])
	for row in prof:
		var bucket: String = String(row[0])
		var total_us: int = int(row[1])
		var calls: int = int(row[2])
		if bucket.begins_with("!"):
			print("  %-18s %8.2f мс/кадр НА ВСЮ АРМИЮ"
				% [bucket, float(total_us) / 1000.0 / float(maxi(calls, 1))])
			continue
		print("  %-18s %7.2f мс/кадр (%5.1f%%) | %8d вызовов | %6.2f мкс"
			% [bucket, float(total_us) / 1000.0 / 120.0,
			   100.0 * float(total_us) / float(maxi(sum_us, 1)),
			   calls, float(row[3])])
	print("\n=== QA_MASS3K DONE ===")
	get_tree().quit()

## ── A/B ЧЕРЕДОВАНИЕМ ───────────────────────────────────────────────────────
## Разброс между прогонами на НЕИЗМЕННОМ коде — единицы кадров, и одиночное
## сравнение «до/после» ничего не доказывает. Здесь база и вариант меряются
## подряд, по нескольку раундов, и печатается среднее по каждому
func _ab(label: String, set_a: Callable, set_b: Callable, rounds: int = 3) -> void:
	var a_tick := 0.0
	var a_fps := 0.0
	var b_tick := 0.0
	var b_fps := 0.0
	var a_vis := 0.0
	var b_vis := 0.0
	for _r in range(rounds):
		set_a.call()
		var sa: Dictionary = await _sample(30, 40)
		set_b.call()
		var sb: Dictionary = await _sample(30, 40)
		a_tick += float(sa["tick"]); a_fps += float(sa["fps"]); a_vis += float(sa["vis"])
		b_tick += float(sb["tick"]); b_fps += float(sb["fps"]); b_vis += float(sb["vis"])
	var n := float(rounds)
	print("
─── A/B: %s (по %d раунда чередованием) ───" % [label, rounds])
	print("  A: физтик %.2f мс, кадр логики %.2f мс, %.1f FPS"
		% [a_tick / n, a_vis / n, a_fps / n])
	print("  B: физтик %.2f мс, кадр логики %.2f мс, %.1f FPS"
		% [b_tick / n, b_vis / n, b_fps / n])
	print("  разница: физтик %+.2f мс, кадр логики %+.2f мс, %+.1f FPS"
		% [a_tick / n - b_tick / n, a_vis / n - b_vis / n, b_fps / n - a_fps / n])

func _print_frame(s: Dictionary) -> void:
	var live: int = GameManager.active_units()
	var fps: float = float(s["fps"])
	# Тик АРМИИ идёт на своей частоте (perf_config.army_hz, этап C.2): при
	# FPS ниже неё на кадр приходится больше одного тика армии, и цена тика
	# НА КАДР выше самого тика
	var phys_hz: float = _Opt.army_hz()
	var per_frame: float = float(s["tick"]) * (phys_hz / maxf(fps, 1.0))
	print("  юнитов живых %d (ходячих %d) | окно %dx%d | вызовов отрисовки %d"
		% [GameManager._live_units.size(), live, RES.x, RES.y, int(s["draws"])])
	print("  шардов физики %d, визуальных %d, такт позы %d кадров" % [
		_Opt.shards_for(live), _Opt.vis_shards_for(live), _Opt.anim_every_for(live)])
	print("  %.1f FPS (%.2f мс на кадр) | тик армии %.0f Гц" % [fps, float(s["ms"]),
		_Opt.army_hz()])
	print("  физтик %.2f мс x %.2f = %.2f мс | кадр логики %.2f мс | итого логика %.2f мс"
		% [float(s["tick"]), phys_hz / maxf(fps, 1.0), per_frame, float(s["vis"]),
			per_frame + float(s["vis"])])

## Приказ атаки: цель — ближайший чужой, чтобы армии реально сошлись
func _charge(from: Array, to: Array) -> void:
	if to.is_empty():
		return
	var c := Vector3.ZERO
	var n := 0
	for u in to:
		if is_instance_valid(u):
			c += (u as Node3D).global_position
			n += 1
	if n == 0:
		return
	c /= float(n)
	for u in from:
		if is_instance_valid(u):
			(u as Unit).command_move(c, false, Vector3.ZERO, false, true)

## Заморозить потери: сцена обязана оставаться одной и той же от первого
## замера до последнего, иначе A/B сравнивает разные армии
func _freeze_losses() -> void:
	for u in GameManager._live_units:
		if not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu == null or uu.is_dead():
			continue
		uu.max_health = 1.0e7
		uu.current_health = 1.0e7

## ── СТРЕЛЫ ИЩУТСЯ ОБХОДОМ МИРА ─────────────────────────────────────────────
## Своей группы у них нет и заводить её ради стенда нельзя: add_to_group идёт
## на КАЖДЫЙ выстрел, а в свалке с лучниками их сотни в секунду
var _arrow_cache: Array = []

func _find_arrows() -> Array:
	var out: Array = []
	var root: Node = main.get("_world")
	if root == null:
		root = main
	for c in root.get_children():
		var n3 := c as Node3D
		if n3 == null:
			continue
		var sc: Variant = n3.get_script()
		if sc != null and String((sc as Script).resource_path).ends_with("Arrow.gd"):
			out.append(n3)
	return out

func _arrows_visible(on: bool) -> void:
	# Картинка стрел теперь в общем MultiMesh (этап D3) — гасится слоем
	GameManager.arrows_mm.set_layer_visible(on)
	for a in _arrow_cache:
		if is_instance_valid(a):
			(a as Node3D).visible = on

func _group_visible(g: String, on: bool) -> void:
	for n in get_tree().get_nodes_in_group(g):
		var n3 := n as Node3D
		if n3 != null:
			n3.visible = on

func _corpses_visible(on: bool) -> void:
	var c = GameManager.corpses
	if c == null:
		return
	for f in ["_buckets", "_layers", "_sheets"]:
		if not (f in c):
			continue
		var d = c.get(f)
		if d is Dictionary:
			for b in d.values():
				if b != null and ("mmi" in b) and b.mmi != null:
					(b.mmi as Node3D).visible = on

func _ai_process(on: bool) -> void:
	for f in ["enemy_ai", "goblin_ai"]:
		var n = main.get(f)
		if n == null:
			continue
		(n as Node).set_process(on)
		(n as Node).set_physics_process(on)

func _army_visible(on: bool) -> void:
	var far = GameManager.far_units
	if far == null or not ("_buckets" in far):
		return
	for b in (far.get("_buckets") as Dictionary).values():
		if b != null and ("mmi" in b) and b.mmi != null:
			(b.mmi as Node3D).visible = on

func _army_ticking(on: bool) -> void:
	for u in GameManager._live_units:
		if is_instance_valid(u):
			(u as Unit).set_tick(on)

func _army_drawing(on: bool) -> void:
	for u in GameManager._live_units:
		if is_instance_valid(u):
			(u as Unit).set_draw(on)

func _veg_visible(on: bool) -> void:
	var v = GameManager.veg
	if v == null:
		return
	for f in ["_buckets", "_layers"]:
		if not (f in v):
			continue
		var d = v.get(f)
		if d is Dictionary:
			for b in d.values():
				if b != null and ("mmi" in b) and b.mmi != null:
					(b.mmi as Node3D).visible = on
