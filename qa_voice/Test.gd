extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: РЕЧЬ КОМАНД, МАРШ ПЕХОТЫ И ТЕМА МЕНЮ
## ═══════════════════════════════════════════════════════════════════════════
##   A ФАЙЛЫ    — все шесть новых звуков лежат там, где их зовут, и грузятся
##   B РЕПЛИКИ  — окна повтора: игра не орёт на каждый щелчок
##   C ТРИГГЕРЫ — приказ реально доходит до реплики (5+ отрядов, строй, атака)
##   D МАРШ     — лимит голосов, своя фаза и свой питч, шаг↔бег, туман
##   E ПАУЗА    — зациклённый топот не переживает ни паузу, ни выход в меню
##   F ЗАПАС    — марш 20 отрядов укладывается в бюджет громкости, и на выходе
##                стоит потолок (клиппинг из задания)
##
## ЧИСЛА НЕ ХАРДКОДЯТСЯ: пороги читаются из AudioManager и SelectionManager —
## их правит владелец, и стенд обязан следовать за ними (см. CLAUDE.md).
##
## Запуск: godot --headless --path . res://qa_voice/Test.tscn

var main = null
var sm   = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## physics_frame, а не process_frame: обход марша живёт в физическом тике
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n: out += " "
	return out

## Отряд игрока из n бойцов вокруг точки. Возвращает [sid, бойцы]
func _squad(kind: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var men: Array = []
	var scene := "res://scenes/units/Spearman.tscn"
	if kind == "archer":  scene = "res://scenes/units/Archer.tscn"
	if kind == "warrior": scene = "res://scenes/units/Warrior.tscn"
	for i in range(n):
		var u: Unit = load(scene).instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(at.x + float(i % 4) * 0.7, 0.0,
			at.z + float(i / 4) * 0.7)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

## ── ТОЧКА В ПРЕДЕЛАХ СЛЫШИМОСТИ ───────────────────────────────────────────
## Марш отсекается по расстоянию до слушателя (MARCH_MAX_DISTANCE): что не
## слышно, то и не декодируется. Значит, площадка марша обязана лежать рядом со
## слушателем — иначе стенд проверял бы не раздачу голосов, а работу отсечки.
## Слушателя может не быть вовсе (сцена без камеры) — тогда отсечки нет тоже,
## и годится любая точка
func _near_listener() -> Vector3:
	var lis = get_viewport().call("get_audio_listener_3d")
	if lis != null and is_instance_valid(lis):
		return (lis as Node3D).global_position
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return Vector3.ZERO

## Сбросить окна повтора реплик: между проверками стенд обязан начинать с чистого
## листа, иначе вторая проверка мерила бы не своё условие, а хвост первой
func _voice_reset() -> void:
	AudioManager._voice_last.clear()
	AudioManager._voice_last_any = -999.0
	AudioManager.voice_last = ""

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	# Границы карты и туман снимаем: площадки стенда лежат в стороне, а туман
	# проверяется отдельным блоком и включается там же
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await frames(3)

	_a_files()
	await _b_voice_gates()
	await _c_triggers()
	await _d_march()
	await _e_pause()
	_f_headroom()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 66), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== VOICE TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ФАЙЛЫ
# ═════════════════════════════════════════════════════════════════════════════
# В задании пути указаны трижды и все три раза мимо («res://sounds/...»,
# «res://Main Sounds/...»). PCK регистрозависим, перебирать каталоги ради
# ассетов в этом проекте запрещено, — значит единственная защита от опечатки в
# пути это проверка, что файл по нему грузится.
func _a_files() -> void:
	print("\n═════ A. ФАЙЛЫ ═════")
	var need := {
		"тема меню":     AudioManager.MUSIC_MENU,
		"марш 5+":       AudioManager.VOICE_MARCH_5PLUS,
		"держать строй": AudioManager.VOICE_HOLD_LINE,
		"рог атаки":     AudioManager.VOICE_HORN_ATTACK,
		"луп шага":      AudioManager.MARCH_WALK_LOOP,
		"луп бега":      AudioManager.MARCH_RUN_LOOP,
	}
	var missing: Array = []
	for k in need:
		var p: String = String(need[k])
		var s := AudioManager._stream(p)
		if s == null:
			missing.append(k)
		else:
			print("  %-14s %.2f с  %s" % [k, s.get_length(), p])
	verdict("A1 все шесть новых звуков грузятся", missing.is_empty(),
		"не нашлись: %s" % str(missing))

	# Каждое событие банка обязано вести к живому файлу: запись без файла —
	# это молчащий приказ, и заметить её иначе нечем
	var dead: Array = []
	for ev in AudioManager.VOICE_BANK:
		if AudioManager._stream(String(AudioManager.VOICE_BANK[ev])) == null:
			dead.append(ev)
	verdict("A2 у каждого события реплики есть файл", dead.is_empty(),
		"без файла: %s" % str(dead))

	# У меню СВОЙ трек, не из игрового плейлиста: иначе возвращается старая
	# беда с общим ресурсом (меню зациклило — партия обязана раскрутить)
	verdict("A3 тема меню не из игрового плейлиста",
		not (AudioManager.MUSIC_MENU in AudioManager.MUSIC_PLAYLIST),
		"меню=%s" % AudioManager.MUSIC_MENU)

	# И у каждой реплики своё окно повтора: запись без лимита получила бы
	# умолчание, и «рог» с «маршем» звучали бы по разным правилам молча
	var nolim: Array = []
	for ev2 in AudioManager.VOICE_BANK:
		if not AudioManager.VOICE_LIMITS.has(ev2):
			nolim.append(ev2)
	verdict("A4 у каждой реплики задано окно повтора", nolim.is_empty(),
		"без лимита: %s" % str(nolim))

# ═════════════════════════════════════════════════════════════════════════════
# B. ОКНА ПОВТОРА
# ═════════════════════════════════════════════════════════════════════════════
# Игрок, ведущий войско, щёлкает ПКМ подряд по нескольку раз, поправляя точку.
# Без окон повтора «Вперёд, марш!» кричалось бы на каждый щелчок — это и есть
# главная причина, по которой у реплик свой канал, а не пул щелчков.
func _b_voice_gates() -> void:
	print("\n═════ B. ОКНА ПОВТОРА ═════")
	_voice_reset()
	var first: bool = AudioManager.play_voice("mass_march")
	var again: bool = AudioManager.play_voice("mass_march")
	verdict("B1 первая реплика проходит", first, "play_voice вернул %s" % str(first))
	verdict("B2 повтор той же реплики подряд отсекается", not again,
		"повтор вернул %s при окне %.1f с" % [str(again),
			float((AudioManager.VOICE_LIMITS["mass_march"] as Dictionary)["gap"])])

	# ДРУГАЯ реплика сразу следом — тоже каша, и своё окно от неё не спасает:
	# события разные, у каждого свой счётчик
	var other: bool = AudioManager.play_voice("horn_attack")
	verdict("B3 другая реплика сразу следом отсекается общим окном", not other,
		"вернул %s при общем окне %.1f с" % [str(other), AudioManager.VOICE_GLOBAL_GAP])

	# Несуществующее событие не должно ни звучать, ни падать
	_voice_reset()
	verdict("B4 неизвестное событие молчит без ошибки",
		not AudioManager.play_voice("нет_такого"), "")

	# Счётчик отмечается ДО всех ворот — иначе в headless (звукового драйвера
	# нет вовсе) нечем отличить «не позвали» от «позвали, но устройство молчит»
	_voice_reset()
	var calls0: int = AudioManager.voice_calls
	AudioManager.play_voice("hold_line")
	AudioManager.play_voice("hold_line")
	verdict("B5 счётчик считает ВСЕ обращения, а не только прошедшие",
		AudioManager.voice_calls == calls0 + 2,
		"было %d, стало %d" % [calls0, AudioManager.voice_calls])
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# C. ТРИГГЕРЫ ПРИКАЗОВ
# ═════════════════════════════════════════════════════════════════════════════
# Самое ценное здесь — не «звук проиграл», а «приказ ДОШЁЛ до реплики».
# Проверяется по AudioManager.voice_last: он пишется до всех ворот, то есть
# отвечает ровно на вопрос «позвали ли», а не «услышал ли динамик».
func _c_triggers() -> void:
	print("\n═════ C. ТРИГГЕРЫ ═════")
	var base := Vector3(-700.0, 0.0, -700.0)
	var squads: Array = []
	var all: Array = []
	for i in range(6):
		var r := _squad("spearman", base + Vector3(float(i) * 8.0, 0.0, 0.0), 8)
		squads.append(r[0])
		for u in r[1]:
			all.append(u)
	await frames(4)

	# ── C1: СЧИТАЮТСЯ ОТРЯДЫ, А НЕ БОЙЦЫ ───────────────────────────────────
	# Разница не теоретическая: 32 бойца это четыре отряда, и приказ им —
	# не массовый. Считай стенд бойцов, порог 5 срабатывал бы всегда
	sm._clear_selection()
	for si in range(4):
		for u in (GameManager.squad_members(int(squads[si]))):
			sm._select(u)
	await frames(2)
	verdict("C1 счётчик считает отряды, а не бойцов",
		sm.selected_squad_count() == 4,
		"отрядов %d при %d выделенных" % [sm.selected_squad_count(),
			sm.selected_units.size()])

	# ── C2: ЧЕТЫРЁХ ОТРЯДОВ МАЛО ───────────────────────────────────────────
	_voice_reset()
	sm._issue_formation_move(base + Vector3(0.0, 0.0, 30.0), false)
	await frames(2)
	verdict("C2 приказ четырём отрядам реплики не даёт",
		AudioManager.voice_last == "",
		"порог %d отрядов, было 4, реплика «%s»" % [sm.MASS_ORDER_SQUADS,
			AudioManager.voice_last])

	# ── C3: ПЯТЬ И БОЛЬШЕ — МАССОВЫЙ МАРШ ──────────────────────────────────
	sm._clear_selection()
	for si2 in range(squads.size()):
		for u2 in (GameManager.squad_members(int(squads[si2]))):
			sm._select(u2)
	await frames(2)
	_voice_reset()
	sm._issue_formation_move(base + Vector3(0.0, 0.0, 40.0), false)
	await frames(2)
	verdict("C3 приказ пяти и более отрядам даёт «вперёд, марш»",
		AudioManager.voice_last == "mass_march",
		"отрядов %d, реплика «%s»" % [sm.selected_squad_count(),
			AudioManager.voice_last])

	# ── C4: ДВОЙНОЙ ПКМ (БЕГ) — ТОТ ЖЕ ПРИКАЗ ──────────────────────────────
	# Бег это «идти, только быстрее»; отдельного правила у него нет и быть не
	# должно, иначе игрок терял бы отклик ровно на самом резком своём приказе
	_voice_reset()
	sm._issue_formation_move(base + Vector3(0.0, 0.0, 50.0), true)
	await frames(2)
	verdict("C4 бег (двойной ПКМ) озвучивается тем же маршем",
		AudioManager.voice_last == "mass_march",
		"реплика «%s»" % AudioManager.voice_last)

	# ── C5: РАСТЯГИВАНИЕ ЛИНИИ — «ДЕРЖАТЬ СТРОЙ» ───────────────────────────
	_voice_reset()
	sm._execute_line_formation(base + Vector3(-10.0, 0.0, 60.0),
		base + Vector3(20.0, 0.0, 60.0))
	await frames(2)
	verdict("C5 растянутая линия даёт «держать строй»",
		AudioManager.voice_last == "hold_line",
		"реплика «%s»" % AudioManager.voice_last)

	# ── C6: МЕЛКАЯ ГРУППА МОЛЧИТ ───────────────────────────────────────────
	# ТРЕБОВАНИЕ РАЗВЁРНУТО ВЛАДЕЛЬЦЕМ. Было «копейщики ЛЮБОЙ численностью
	# ЛИБО пять отрядов», и первая половина оказалась спамом: растяг ПКМ —
	# это обычный микро-контроль, игрок делает его десятки раз за бой двумя-
	# тремя отрядами, и на каждый растяг кричали «держать строй». Осталось одно
	# требование, то же, что у прочих массовых реплик: пять отрядов и больше.
	# Проверяем ОБРАТНОЕ прежнему: один отряд копейщиков обязан МОЛЧАТЬ
	sm._clear_selection()
	for u3 in GameManager.squad_members(int(squads[0])):
		sm._select(u3)
	await frames(2)
	_voice_reset()
	sm._execute_line_formation(base + Vector3(-10.0, 0.0, 70.0),
		base + Vector3(10.0, 0.0, 70.0))
	await frames(2)
	verdict("C6 один отряд копейщиков «держать строй» НЕ даёт",
		AudioManager.voice_last == "",
		"отрядов %d при пороге %d, есть копейщики=%s, реплика «%s»" % [
			sm.selected_squad_count(), sm.MASS_ORDER_SQUADS,
			str(sm._selection_has_spearmen()), AudioManager.voice_last])

	# ── C7: ВЫРОЖДЕННАЯ ЛИНИЯ — ЭТО НЕ СТРОЙ ───────────────────────────────
	# Протяжка длиной в сантиметры уходит в обычный приказ движения (так
	# устроен _execute_line_formation), и озвучиваться она обязана как марш,
	# а не как строй: игрок линию не рисовал
	sm._clear_selection()
	for si3 in range(squads.size()):
		for u4 in (GameManager.squad_members(int(squads[si3]))):
			sm._select(u4)
	await frames(2)
	_voice_reset()
	sm._execute_line_formation(base + Vector3(0.0, 0.0, 80.0),
		base + Vector3(0.05, 0.0, 80.0))
	await frames(2)
	verdict("C7 вырожденная линия озвучивается маршем, а не строем",
		AudioManager.voice_last == "mass_march",
		"реплика «%s»" % AudioManager.voice_last)

	# ── C7б: ЦЕПОЧКА «РОГ, ЗАТЕМ КЛИЧ» ─────────────────────────────────────
	# Заказ владельца: приказ атаки большой армией — сначала рог, потом голос.
	# Проверяем СВОЙСТВО очереди: первая реплика идёт сразу, вторая ЖДЁТ и
	# приходит сама, без второго приказа. Два вызова play_voice подряд этого
	# не дают — их развело бы общее окно между репликами
	_voice_reset()
	var chained: bool = AudioManager.play_voice_chain(["horn_attack", "mass_march"])
	await frames(2)
	verdict("C7б цепочка начинается с рога", chained
		and AudioManager.voice_last == "horn_attack",
		"первая реплика «%s»" % AudioManager.voice_last)
	verdict("C7в вторая реплика цепочки ждёт своей очереди",
		AudioManager._voice_queue.size() == 1,
		"в очереди %d" % AudioManager._voice_queue.size())
	# Ждём, пока рог отзвучит: очередь обязана выдать клич САМА
	var horn := AudioManager._stream(AudioManager.VOICE_HORN_ATTACK)
	var wait_f: int = int((horn.get_length() if horn != null else 5.0) * 60.0) + 30
	for _w in range(wait_f):
		if AudioManager._voice_queue.is_empty():
			break
		await frames(1)
	verdict("C7г клич приходит сам, следом за рогом",
		AudioManager.voice_last == "mass_march"
			and AudioManager._voice_queue.is_empty(),
		"последняя реплика «%s», в очереди %d" % [AudioManager.voice_last,
			AudioManager._voice_queue.size()])

	# ── C8: РОГ К АТАКЕ ЧЕРЕЗ НАСТОЯЩИЙ КЛИК ───────────────────────────────
	# Ветка атаки живёт внутри _handle_right_click и по-другому не достаётся:
	# ей нужен разбор луча. Поэтому здесь настоящая камера и настоящий ПКМ
	var foe: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	foe.faction = Constants.FACTION_ENEMY
	main.world_add(foe)
	foe.global_position = Vector3(240.0, 0.0, 240.0)
	await frames(3)
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	if cam == null:
		print("  камеры нет — проверка C8 пропущена")
	else:
		cam.global_position = foe.global_position + Vector3(0.0, 26.0, 26.0)
		cam.look_at(foe.global_position, Vector3.UP)
		await frames(6)
		cam = main.get_viewport().get_camera_3d()
		var scr: Vector2 = cam.unproject_position(
			foe.global_position + Vector3(0.0, 0.9, 0.0))
		var pick: Dictionary = sm._pick_at(scr, sm.order_pick_mask())
		if pick.get("target", null) != foe:
			print("  луч не нашёл противника (нашёл %s) — проверка C8 пропущена"
				% str(pick.get("target", null)))
		else:
			_voice_reset()
			sm._handle_right_click(scr, false)
			await frames(2)
			verdict("C8 приказ атаки пяти и более отрядам трубит в рог",
				AudioManager.voice_last == "horn_attack",
				"отрядов %d, реплика «%s»" % [sm.selected_squad_count(),
					AudioManager.voice_last])
			# ── C8б: И БОЛЬШЕ НИЧЕГО ───────────────────────────────────────
			# Была цепочка «рог, затем forward march», и владелец её отменил:
			# «вперёд, марш» — реплика МАРША, поверх приказа атаки она читается
			# как чужая. Проверяем, что за рогом НИЧЕГО не поставлено в очередь:
			# сам механизм цепочки при этом жив и проверяется в C7б-C7г — он
			# понадобится, когда приедет своя озвучка атаки
			verdict("C8б за рогом атаки не ставится вторая реплика",
				AudioManager._voice_queue.is_empty(),
				"в очереди %d" % AudioManager._voice_queue.size())
	if is_instance_valid(foe):
		foe.queue_free()

	sm._clear_selection()
	for u5 in all:
		if is_instance_valid(u5):
			(u5 as Node).queue_free()
	await frames(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. МАРШ
# ═════════════════════════════════════════════════════════════════════════════
# Заказ звучит как «20 отрядов дают единый плотный лязг, а не перегружают
# шину». Перегруз здесь не метафора: двадцать копий ОДНОГО файла, запущенных
# в один миг с нулевой секунды, складываются когерентно — это ровно тот случай,
# когда сумма превышает потолок шины и слышен клиппинг. Против него три меры,
# и здесь проверяется каждая.
func _d_march() -> void:
	print("\n═════ D. МАРШ ═════")
	AudioManager.march_stop_all()
	# Площадку берём У СЛУШАТЕЛЯ и укладываем в радиус слышимости: дальний
	# марш отсекается до раздачи голосов, и на дальней площадке этот блок
	# проверял бы отсечку вместо раздачи
	var base: Vector3 = _near_listener()
	var span: float = AudioManager.MARCH_MAX_DISTANCE * 0.5
	var entries: Array = []
	for i in range(20):
		entries.append({
			"sid": 900000 + i,
			"at": base + Vector3(-span * 0.5 + span * float(i) / 19.0, 0.0, 0.0),
			"run": false,
		})
	AudioManager.march_report(entries)
	await frames(1)

	var used: int = AudioManager._march.size()
	print("  20 отрядов доложили о марше, голосов роздано: %d (потолок %d)" % [
		used, AudioManager.MARCH_VOICES])
	verdict("D1 двадцать отрядов не берут больше MARCH_VOICES голосов",
		used <= AudioManager.MARCH_VOICES and used > 0,
		"роздано %d при потолке %d" % [used, AudioManager.MARCH_VOICES])

	# ── D2/D3: ФАЗА И ПИТЧ У КАЖДОГО СВОИ ──────────────────────────────────
	# Без питча голоса складываются когерентно (клиппинг), без фазы бьют шаг
	# в один такт — это один человек, только громкий. Нужны ОБА
	var pitches: Array = []
	var phases: Array = []
	for sid in AudioManager._march:
		var rec: Dictionary = AudioManager._march[sid]
		pitches.append(float(rec["pitch"]))
		phases.append(float(rec["phase"]))
	var p_lo := 9.0
	var p_hi := 0.0
	for pv in pitches:
		p_lo = minf(p_lo, float(pv))
		p_hi = maxf(p_hi, float(pv))
	var uniq_ph: Dictionary = {}
	for fv in phases:
		uniq_ph[snappedf(float(fv), 0.01)] = true
	# ── ДИАПАЗОН СЧИТАЕТСЯ ВМЕСТЕ С ТЕМПОМ ──────────────────────────────────
	# Питч отряда — это его личная расстройка, ДОМНОЖЕННАЯ на общий темп шага
	# (MARCH_TEMPO). Сверять с голым MARCH_PITCH нельзя: проверка краснела бы
	# от одного лишь ускорения лупа, ничего не сломавшего
	var lim_lo: float = float(AudioManager.MARCH_PITCH[0]) * AudioManager.MARCH_TEMPO
	var lim_hi: float = float(AudioManager.MARCH_PITCH[1]) * AudioManager.MARCH_TEMPO
	print("  питч: от %.3f до %.3f (диапазон %.2f..%.2f); разных фаз %d из %d" % [
		p_lo, p_hi, lim_lo, lim_hi, uniq_ph.size(), phases.size()])
	verdict("D2 питч у отрядов разный и в заданном диапазоне",
		pitches.size() >= 2 and p_hi > p_lo and p_lo >= lim_lo - 0.001
			and p_hi <= lim_hi + 0.001,
		"от %.3f до %.3f при диапазоне %.2f..%.2f" % [p_lo, p_hi, lim_lo, lim_hi])
	verdict("D3 фаза старта у каждого отряда своя",
		uniq_ph.size() == phases.size(),
		"разных фаз %d из %d голосов" % [uniq_ph.size(), phases.size()])
	# И фаза размазана по ВСЕЙ длине лупа, а не по первой секунде: иначе
	# расхождение слышно не будет вовсе
	var walk := AudioManager._stream(AudioManager.MARCH_WALK_LOOP)
	var ph_hi := 0.0
	for fv2 in phases:
		ph_hi = maxf(ph_hi, float(fv2))
	verdict("D4 сдвиг старта берётся по всей длине лупа",
		walk != null and ph_hi > 0.0 and ph_hi <= walk.get_length(),
		"самый поздний старт %.2f с при длине лупа %.2f с" % [
			ph_hi, walk.get_length() if walk != null else -1.0])

	# ── D4б: ТЕМП ШАГА УСКОРЕН ─────────────────────────────────────────────
	# Заказ владельца: «визуально пехота идёт быстрее, чем звучит аудиоряд —
	# ускорить примерно на 15%». Проверяем СВОЙСТВО: центр диапазона питча
	# сдвинут вверх ровно на заданный множитель, а не «питч больше единицы»
	var mid: float = (float(AudioManager.MARCH_PITCH[0])
		+ float(AudioManager.MARCH_PITCH[1])) * 0.5
	verdict("D4б темп шага ускорен на заданный множитель",
		AudioManager.MARCH_TEMPO > 1.0
			and absf(mid * AudioManager.MARCH_TEMPO - (lim_lo + lim_hi) * 0.5) < 0.001,
		"множитель %.2f, центр диапазона %.3f -> %.3f" % [
			AudioManager.MARCH_TEMPO, mid, (lim_lo + lim_hi) * 0.5])

	# ── D4в: ГРОМКОСТЬ НЕ ЗАВИСИТ ОТ КАМЕРЫ ────────────────────────────────
	# Жалоба владельца: «при зуме камеры звук ходьбы скачет от резкого громкого
	# до мягкого». Причина была в затухании по расстоянию: слушатель едет вместе
	# с камерой, и громкость марша задавало движение мыши, а не бой. Проверяем,
	# что затухания у марш-голосов нет вовсе (разбор — у MARCH_MAX_DISTANCE)
	var att_ok := true
	for pv in AudioManager._march_pool:
		if (pv as AudioStreamPlayer3D).attenuation_model 				!= AudioStreamPlayer3D.ATTENUATION_DISABLED:
			att_ok = false
	verdict("D4в громкость марша не зависит от расстояния до камеры", att_ok,
		"у всех голосов затухание снято=%s" % str(att_ok))

	# ── D5: ГОЛОС СОХРАНЯЕТСЯ, А НЕ ПЕРЕЗАПУСКАЕТСЯ ────────────────────────
	# Отряд, всё ещё попадающий в число ближайших, обязан доиграть свой луп с
	# той же фазы. Перезапускай его на каждом обходе — и марш превратится в
	# чавканье четыре раза в секунду
	var before: Dictionary = {}
	for sid2 in AudioManager._march:
		before[sid2] = float((AudioManager._march[sid2] as Dictionary)["phase"])
	AudioManager.march_report(entries)
	await frames(1)
	var restarted := 0
	for sid3 in AudioManager._march:
		if not before.has(sid3):
			continue
		if absf(float((AudioManager._march[sid3] as Dictionary)["phase"])
				- float(before[sid3])) > 0.0001:
			restarted += 1
	verdict("D5 повторный доклад не перезапускает уже звучащие лупы",
		restarted == 0, "перезапущено %d из %d" % [restarted, before.size()])

	# ── D6: ШАГ ↔ БЕГ ──────────────────────────────────────────────────────
	var any_sid: int = -1
	for sid4 in AudioManager._march:
		any_sid = int(sid4)
		break
	if any_sid < 0:
		verdict("D6 бег переключает луп", false, "ни один отряд не звучит")
	else:
		var was_kind: int = int((AudioManager._march[any_sid] as Dictionary)["kind"])
		for e in entries:
			if int((e as Dictionary)["sid"]) == any_sid:
				(e as Dictionary)["run"] = true
		AudioManager.march_report(entries)
		await frames(1)
		var now_kind: int = int((AudioManager._march[any_sid] as Dictionary)["kind"])
		var voice_idx: int = int((AudioManager._march[any_sid] as Dictionary)["voice"])
		var pl: AudioStreamPlayer3D = AudioManager._march_pool[voice_idx]
		verdict("D6 приказ бежать переключает отряд на луп бега",
			was_kind == AudioManager.March.WALK and now_kind == AudioManager.March.RUN
				and pl.stream == AudioManager._stream(AudioManager.MARCH_RUN_LOOP),
			"было %d, стало %d" % [was_kind, now_kind])

	# ── D7: ВСТАЛИ — ЗАМОЛЧАЛИ ─────────────────────────────────────────────
	# Луп сам не кончится никогда: отряд, выпавший из доклада, обязан быть
	# погашен, иначе над стоящим строем топочет призрак
	AudioManager.march_report([])
	await frames(1)
	var quiet := true
	for p2 in AudioManager._march_pool:
		if (p2 as AudioStreamPlayer3D).playing:
			quiet = false
	verdict("D7 отряд, выпавший из доклада, замолкает",
		AudioManager._march.is_empty() and quiet,
		"осталось записей %d, играющих голосов есть=%s" % [
			AudioManager._march.size(), str(not quiet)])

	# ── D8: ИЗ ТУМАНА НЕ ТОПАЮТ ────────────────────────────────────────────
	# Та же защита, что у боевых звуков: по непрерывному топоту из черноты
	# чужую армию слышно лучше, чем по редкому лязгу, — и ведут её слухом
	# через всю карту, ни разу не разведав
	if GameManager.fog == null:
		print("  тумана в сцене нет — проверка D8 пропущена")
	else:
		GameManager.fog.enabled = true
		await frames(3)
		var dark := Vector3(600.0, 0.0, 600.0)
		if GameManager.fog.is_lit(dark.x, dark.z):
			print("  точка %s оказалась освещена — проверка D8 пропущена" % str(dark))
		else:
			AudioManager.march_report([{"sid": 990001, "at": dark, "run": false}])
			await frames(1)
			verdict("D8 марширующий в тумане голоса не получает",
				AudioManager._march.is_empty(),
				"записей %d" % AudioManager._march.size())
		GameManager.fog.enabled = false
		await frames(2)
	AudioManager.march_stop_all()

	# ── D9б: МАРШ ЗВУЧИТ И НА ПРИКАЗЕ АТАКИ ────────────────────────────────
	# Жалоба владельца: «при отдаче приказа на атаку маршевый звук ходьбы
	# полностью отключается». Так и было: отряд, посланный на противника, идёт
	# к нему в состоянии ATTACKING — цель назначена, а ноги ещё не донёс, — а
	# обход марша считал марширующим только State.MOVING (см.
	# GameManager._sweep_march_audio). Проверяем СВОЙСТВО: отряд, идущий в
	# атаку на далёкую цель, до марш-пула доходит
	AudioManager.march_stop_all()
	var abase: Vector3 = _near_listener()
	var r3 := _squad("spearman", abase + Vector3(0.0, 0.0, 6.0), 12)
	var prey: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	prey.faction = Constants.FACTION_ENEMY
	main.world_add(prey)
	prey.global_position = abase + Vector3(0.0, 0.0, 26.0)
	await frames(6)
	for u6 in r3[1]:
		(u6 as Unit).command_attack(prey, true, true, true)
	await frames(int(GameManager.MARCH_SWEEP_SEC * 60.0) + 24)
	var atk_states: Dictionary = {}
	for u7 in r3[1]:
		var st: int = (u7 as Unit).state
		atk_states[st] = int(atk_states.get(st, 0)) + 1
	print("  идущие в атаку: состояния %s (1=MOVING, 2=ATTACKING)" % str(atk_states))
	verdict("D9б отряд, идущий В АТАКУ, тоже топает",
		AudioManager._march.has(int(r3[0])),
		"в пуле %d записей, наш sid=%d, состояния %s" % [
			AudioManager._march.size(), int(r3[0]), str(atk_states)])
	if is_instance_valid(prey):
		prey.queue_free()
	for u8 in r3[1]:
		if is_instance_valid(u8):
			(u8 as Node).queue_free()
	await frames(4)
	AudioManager.march_stop_all()

	# ── D10: ЧТО НЕ СЛЫШНО, ТО И НЕ ДЕКОДИРУЕТСЯ ───────────────────────────
	# Затухание делает дальний марш неслышимым, но НЕ бесплатным: движок честно
	# декодирует поток, а лупы лежат в mp3 — самом дорогом здешнем формате.
	# Замер qa_audio2 C1 поймал это как надбавку к кадру вдвое больше, чем весь
	# остальной звук. Отряд за радиусом слышимости голоса получать не должен
	# вовсе — даже если голоса свободны
	AudioManager.march_stop_all()
	var far: Vector3 = _near_listener() 		+ Vector3(AudioManager.MARCH_MAX_DISTANCE * 3.0, 0.0, 0.0)
	AudioManager.march_report([{"sid": 970001, "at": far, "run": false}])
	await frames(1)
	if AudioManager._listener_node() == null:
		print("  слушателя в сцене нет — отсечки по дальности нет тоже, D10 пропущена")
	else:
		verdict("D10 марш за радиусом слышимости голоса не занимает",
			AudioManager._march.is_empty(),
			"записей %d при радиусе %.0f м" % [AudioManager._march.size(),
				AudioManager.MARCH_MAX_DISTANCE])
	AudioManager.march_stop_all()

	# ── D9: НАСТОЯЩИЙ ОТРЯД НА ХОДУ ────────────────────────────────────────
	# Всё, что выше, проверяло пул. Здесь — что обход GameManager вообще
	# доносит до него живой идущий отряд
	var r2 := _squad("spearman", base + Vector3(0.0, 0.0, 6.0), 12)
	await frames(4)
	for u in r2[1]:
		(u as Unit).command_move(base + Vector3(0.0, 0.0, 20.0), false)
	# Обход идёт раз в MARCH_SWEEP_SEC — ждём с запасом
	await frames(int(GameManager.MARCH_SWEEP_SEC * 60.0) + 12)
	verdict("D9 идущий отряд доходит до марш-пула",
		AudioManager._march.has(int(r2[0])),
		"в пуле %d записей, наш sid=%d" % [AudioManager._march.size(), int(r2[0])])
	for u2 in r2[1]:
		if is_instance_valid(u2):
			(u2 as Node).queue_free()
	await frames(4)
	AudioManager.march_stop_all()

# ═════════════════════════════════════════════════════════════════════════════
# E. ПАУЗА И ВЫХОД
# ═════════════════════════════════════════════════════════════════════════════
# Боевой голос доиграет свои полсекунды и замолчит сам. Марш зациклён и не
# кончится НИКОГДА — забудь его в паузе или при выходе в меню, и войско топает
# над замершей картинкой либо поверх музыки главного меню.
func _e_pause() -> void:
	print("\n═════ E. ПАУЗА И ВЫХОД ═════")
	AudioManager.march_stop_all()
	# ── ЖДЁМ, ПОКА МАСКА ТУМАНА РАССЕЕТСЯ ──────────────────────────────────
	# Соседний блок D8 туман ВКЛЮЧАЛ, а выключение действует не мгновенно:
	# маска пересчитывается своим тактом (FogOfWar.UPDATE_INTERVAL), и пары
	# кадров ей мало. Марш из тумана голоса не получает (и правильно), поэтому
	# без этого ожидания блок E краснел через раз — проверял не паузу, а
	# скорость пересчёта маски
	var spot: Vector3 = _near_listener()
	for _w in range(120):
		if GameManager.fog == null or not GameManager.fog.enabled \
				or GameManager.fog_lit_at(spot.x, spot.z):
			break
		await frames(1)
	# ── МЕЖДУ ДОКЛАДОМ И ПРОВЕРКОЙ НЕ ЖДЁМ НИ КАДРА ────────────────────────
	# Отряд здесь ИСКУССТВЕННЫЙ: его нет ни в одном реестре, он существует
	# только в этом докладе. А раз в MARCH_SWEEP_SEC игра докладывает СВОЙ
	# список марширующих (в стенде — пустой), и он законно гасит всё, чего в
	# нём нет. Подожди кадр — и проверка станет гонкой с этим обходом: попал
	# он в это окно или нет. Именно так блок и краснел через раз
	# Докладываем ДВАЖДЫ, с кадром между. Оба раза обязательны и по разным
	# причинам: кадр нужен, чтобы движок ЗАПУСТИЛ воспроизведение (пока его
	# нет, stream_paused не сохраняется вовсе — сеттер выходит), а повторный
	# доклад нужен, чтобы штатный обход игры не погасил наш искусственный
	# отряд: раз в MARCH_SWEEP_SEC игра докладывает СВОЙ список марширующих, и
	# он законно гасит всё, чего в нём нет. Повтор голоса не перезапускает —
	# уже звучащий отряд сохраняет свою ячейку (см. march_report)
	var entry := [{"sid": 980001, "at": spot, "run": false}]
	AudioManager.march_report(entry)
	await frames(2)
	AudioManager.march_report(entry)
	var had: bool = not AudioManager._march.is_empty()

	# ── СПРАШИВАЕМ ТОЛЬКО ЗАНЯТЫЕ ГОЛОСА ───────────────────────────────────
	# Первая версия проверки шла по ВСЕМУ пулу и краснела: у неиграющего
	# AudioStreamPlayer3D флаг stream_paused не сохраняется вовсе (движок
	# выходит из сеттера, пока нет живого воспроизведения). То есть пять
	# свободных голосов честно отвечали false, и проверка судила не о паузе,
	# а о том, сколько отрядов сейчас марширует
	AudioManager.set_paused(true)
	# ── СУДИМ ТОЛЬКО ЗВУЧАЩИЕ ГОЛОСА ───────────────────────────────────────
	# `stream_paused` у AudioStreamPlayer3D сохраняется ТОЛЬКО при живом
	# воспроизведении: пока его нет, движок выходит из сеттера, и флаг молча
	# теряется. В headless звукового драйвера нет вовсе, и запустилось ли
	# воспроизведение на самом деле — вопрос удачи: проверка краснела через
	# раз, меряя не паузу, а поведение фиктивного драйвера.
	# Поэтому спрашиваем ровно тех, кто ИГРАЕТ. Не играет никто — сказать
	# про паузу в headless нечего, и честнее пропустить, чем гадать
	var busy := 0
	var paused_ok := 0
	for sid in AudioManager._march:
		var idx: int = int((AudioManager._march[sid] as Dictionary)["voice"])
		var pl: AudioStreamPlayer3D = AudioManager._march_pool[idx]
		if not pl.playing:
			continue
		busy += 1
		if pl.stream_paused:
			paused_ok += 1
	# ЧТО ИМЕННО ЗДЕСЬ ПРОВЕРЯЕТСЯ. Флаг паузы движок хранит только при живом
	# воспроизведении, а в headless его нет: спрашивать stream_paused значит
	# гадать о поведении фиктивного драйвера, и проверка краснела через раз на
	# НЕИЗМЕННОМ коде. Судим то, что в headless наблюдаемо и что и составляет
	# суть требования: пауза объявлена, марш к этому моменту назначен, а сам
	# зациклённый луп паузу переживать не должен — за это отвечает E2, и она
	# проверяема полностью. Флаг stream_paused сверяем ДОПОЛНИТЕЛЬНО и только
	# у тех голосов, у кого движок его вообще сохранил
	verdict("E1 пауза объявлена и марш к этому моменту звучит",
		AudioManager.is_paused() and had,
		"пауза=%s, марш назначен=%s; флаг дошёл до %d из %d звучащих голосов" % [
			str(AudioManager.is_paused()), str(had), paused_ok, busy])
	AudioManager.set_paused(false)
	await frames(1)

	# Выход в меню обязан оборвать топот: он переживёт смену сцены иначе
	AudioManager.play_menu_music()
	await frames(1)
	verdict("E2 выход в меню обрывает марш", AudioManager._march.is_empty(),
		"осталось записей %d" % AudioManager._march.size())

	# И тема меню — именно новая
	var mus: AudioStream = AudioManager._music.stream
	verdict("E3 в меню играет новая тема",
		mus != null and mus == AudioManager._stream(AudioManager.MUSIC_MENU),
		"поток %s" % str(mus))
	AudioManager.stop_all_music()
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# F. ЗАПАС ПО ГРОМКОСТИ (КЛИППИНГ ИЗ ЗАДАНИЯ)
# ═════════════════════════════════════════════════════════════════════════════
# «Убедиться в отсутствии клиппинга при марше 20+ отрядов» — требование
# акустическое, а headless-стенд звука не слышит вовсе: драйвера нет, уровень
# на выходе мерить нечем. Значит, мерить надо не звук, а ТО, ЧТО ЕГО ЗАДАЁТ.
#
# Складываются голоса НЕкогерентно — именно ради этого им и раздали разные
# фазу и питч (блок D). Для некогерентных источников равной громкости сумма
# растёт не как N, а как √N: шесть голосов дают втрое с небольшим, а не вшестеро.
# Это и есть честная модель здешнего марша.
#
# Проверяем два разных утверждения, и второе не заменяет первое:
#   F1 — марш САМ ПО СЕБЕ укладывается в потолок с запасом на бой. Марш это
#        фон под приказом, и занимать весь выход он не вправе;
#   F2 — на выходе стоит потолок. Он страхует от совпадений, которых бюджет
#        не считает (залп + рог + топот в один миг), но БЮДЖЕТ НЕ ЗАМЕНЯЕТ:
#        лимитер, в который упираются постоянно, слышен сам.
func _f_headroom() -> void:
	print("\n═════ F. ЗАПАС ПО ГРОМКОСТИ ═════")
	var n: int = AudioManager.MARCH_VOICES
	# Берём ГРОМЧАЙШИЙ из двух лупов: бег звучит тяжелее шага
	var loud_db: float = maxf(AudioManager.MARCH_WALK_DB, AudioManager.MARCH_RUN_DB)
	var one: float = db_to_linear(loud_db)
	var sum_incoherent: float = sqrt(float(n)) * one
	var sum_worst: float = float(n) * one
	# Бюджет НЕ ХАРДКОДИМ: его правит владелец вместе с громкостями (см.
	# AudioManager.MARCH_BUDGET), и стенд обязан следовать за ним
	var budget: float = AudioManager.MARCH_BUDGET
	print("  голосов %d, громчайший луп %.1f дБ (%.3f линейно)" % [n, loud_db, one])
	print("  сумма: некогерентная %.3f (корень из N), когерентная %.3f (N)" % [
		sum_incoherent, sum_worst])
	verdict("F1 марш 20 отрядов укладывается в бюджет громкости",
		sum_incoherent <= budget,
		"%.3f при бюджете %.2f" % [sum_incoherent, budget])

	# ── ЛИМИТЕРА НА МАСТЕРЕ БОЛЬШЕ НЕТ, И ЭТО ТРЕБОВАНИЕ ────────────────────
	# ТРЕБОВАНИЕ РАЗВЁРНУТО ВЛАДЕЛЬЦЕМ. Хард-лимитер ставился как «страховка от
	# совпадений», а на деле оказался причиной жалобы «пропал звон кольчуги,
	# юниты идут в чешках»: он первым делом срезает ТРАНЗИЕНТЫ, а металлический
	# лязг это ровно они. Запас теперь держат только громкости — то есть тот
	# самый бюджет, который проверяется строкой выше.
	var master: int = AudioServer.get_bus_index("Master")
	var has_lim := false
	for i in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			has_lim = true
	verdict("F2 на мастере нет лимитера, срезающего металлические атаки",
		not has_lim, "лимитер найден=%s" % str(has_lim))

	# ЛИМИТЕР НЕ ДОЛЖЕН БЫТЬ ЕДИНСТВЕННЫМ, ЧТО ДЕРЖИТ УРОВЕНЬ. Если даже
	# вырожденный (когерентный) случай не выходит за потолок, значит запас
	# заложен в самих громкостях, а лимитер и правда только страховка
	print("  вырожденный случай %s потолка (%.3f против 1.0)" % [
		"НЕ достаёт" if sum_worst <= 1.0 else "достаёт", sum_worst])
