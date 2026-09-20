## ═══════════════════════════════════════════════════════════════════════════
## ГОЛОСОВОЕ УПРАВЛЕНИЕ: микрофон → Vosk в фоне → приказ отрядам области
## ═══════════════════════════════════════════════════════════════════════════
## Изолированный узел: свой аудио-бус с захватом, свой слой интерфейса (иконка
## микрофона и плашка распознанного текста — обе в ПРАВОМ НИЖНЕМ углу, ТЗ
## 19.09.2026), свой C#-распознаватель в фоновом потоке. Главный поток за кадр
## делает две дешёвые вещи: забирает буфер микрофона (копия нескольких сотен
## пар float) и опрашивает очередь результатов. Ни один шаг распознавания в
## главном потоке не идёт.
##
## Управление: зажать V (push-to-talk), сказать, отпустить. Через 0.3-0.8 с
## плашка показывает текст, отряды откликаются и исполняют.
##
## ОБЛАСТЬ ДЕЙСТВИЯ (ТЗ 19.09.2026, блок 2): есть выделенные боевые отряды —
## команда ТОЛЬКО им; никто не выделен — всем своим боевым отрядам В КАДРЕ
## (центр отряда в усечённой пирамиде камеры). Прежнее «пусто — вся армия»
## (03.09.2026) и «пусто — никому» (спринт 18) сняты этим ТЗ.
## ФИЛЬТР РОДА (блок 3): «копья / копейщики / фаланга», «луки / лучники /
## стрелки», «мечи / рыцари / мечников / пехота», «конница / всадники» —
## сужают область до рода; «все» или ничего — вся область.
## ЧТО (voice_commands_config.INTENTS):
##   «в атаку»               → приказ атаки на ближайшего врага, звучит ГОРН;
##                             врага нет — марш на ATTACK_M по курсу
##   «вперёд / вправо»       → сдвиг ВПРАВО по экрану на VOICE_STEP_M
##   «назад / влево»         → сдвиг ВЛЕВО по экрану
##   «вверх», «вниз»         → сдвиг вверх / вниз по экрану
##   «отступать [на N]»      → вектор, ОБРАТНЫЙ последнему движению отряда;
##                             фаланга поднимает копья на время отхода и
##                             опускает по приходу
##   «стоять»                → встать на месте, стойка не меняется
##   «держать строй / деф»   → стойка «оборона» ВСЕМ отрядам области: встать,
##                             бросить цели, сомкнуть строй (блок 6)
##   «вольно»                → стойка «атака» (авто-агро, копья вверх)
## Приказы идут ТЕМИ ЖЕ функциями, что и мышь (set_stance, command_move с
## player_order, squad_close_ranks); строй переносится целиком одним вектором.
extends Node
class_name VoiceControl

const _Cfg := preload("res://scripts/voice_commands_config.gd")
const _Recognizer := preload("res://csharp/VoiceRecognizer.cs")

const BUS_NAME := "Record"
const MODEL_DIR := "vosk-model-small-ru-0.22"
const PTT_KEY := KEY_V
## Сколько ещё кадров после отпускания кнопки досылать буфер: хвост слова
const TAIL_FRAMES := 6
const TEXT_SHOW_SEC := 1.0
## Отход фаланги: как часто сверять приход и предельное ожидание
const REFORM_CHECK_SEC := 0.25
const REFORM_TIMEOUT_SEC := 25.0
## Отряд «пришёл», когда его центр в этом радиусе от точки назначения
const REFORM_ARRIVE_M := 2.0
## Интерфейс: отступ от правого и нижнего края экрана, размер шрифта плашки
## распознанного текста (компактный, заказ ~24 px), просвет между иконкой и
## плашкой. Правый нижний угол пуст: нижняя панель выделения живёт слева
## (HUD.PANEL_LEFT), панель ресурсов и подпись строя — сверху
const UI_MARGIN := 12.0
const TEXT_FONT_PX := 24
const MIC_TEXT_GAP := 8.0
## «Отступать» без вектора движения: прочь от ближайшего врага в этом радиусе
const RETREAT_FOE_SEARCH_M := 60.0

var _rec = null                       # VoiceRecognizer (C#)
var _capture: AudioEffectCapture = null
var _player: AudioStreamPlayer = null
var _listening: bool = false
var _tail: int = 0
var _layer: CanvasLayer = null
var _ui_box: VBoxContainer = null
var _mic_box: HBoxContainer = null
var _mic_dot: ColorRect = null
var _mic_bar: ColorRect = null
var _mic_label: Label = null
var _text_panel: PanelContainer = null
var _text_label: Label = null
var _text_until_ms: int = 0
var _last_error: String = ""
## Окна для стендов
var last_command: Dictionary = {}
var last_voice_event: String = ""
var commands_applied: int = 0
## Откуда взята область последней команды: "selection" / "view" / ""
var last_area: String = ""
## Фаланги в отходе: sid → {"target": центр назначения, "until_ms"}
var _reform: Dictionary = {}
var _reform_timer: float = 0.0
## Последний вектор движения, выданный отряду голосом: sid → единичный
## вектор XZ. По нему «отступать» строит обратный вектор (блок 5)
var _last_vec: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_bus()
	_setup_ui()
	# В headless микрофона нет, а модель весит 45 МБ и грузится секунду в
	# своём потоке: каждому стенду шлюза это ни к чему. Там распознаватель
	# поднимается только явным start_recognizer() (так делает qa_voice_cmd)
	if DisplayServer.get_name() != "headless":
		start_recognizer()

# ─────────────────────────────────────────────────────────────────────────────
# ЗВУК: свой бус с захватом; громкость в минус — себя слышать не нужно, а
# эффект захвата стоит ДО регулятора громкости и получает полный сигнал
# ─────────────────────────────────────────────────────────────────────────────
func _setup_bus() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var idx: int = AudioServer.get_bus_index(BUS_NAME)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, -80.0)
	_capture = null
	for i in range(AudioServer.get_bus_effect_count(idx)):
		var e := AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectCapture:
			_capture = e
			break
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(idx, _capture)
	_player = AudioStreamPlayer.new()
	_player.name = "Microphone"
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS_NAME
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	_player.play()

func start_recognizer() -> void:
	if _rec != null:
		return
	_rec = _Recognizer.new()
	var dir: String = model_path()
	if dir == "":
		# Называем КУДА смотрели: в собранной игре это единственный способ
		# понять, что рядом с .exe забыли папку voice_models
		_last_error = "модель не найдена (%s); искали: %s" % [MODEL_DIR, ", ".join(model_dirs())]
		push_warning("VoiceControl: " + _last_error)
		_mic_label.text = "V — нет модели"
		return
	var grammar: String = JSON.stringify(_Cfg.grammar_words())
	if not _rec.Start(dir, grammar, AudioServer.get_mix_rate()):
		_last_error = String(_rec.GetError())
		push_warning("VoiceControl: " + _last_error)
		_mic_label.text = "V — ошибка"

## ── ГДЕ ИЩЕТСЯ МОДЕЛЬ ──────────────────────────────────────────────────────
## PCK её не содержит НАМЕРЕННО: 88 МБ и тысячи файлов, которые Godot иначе
## пытался бы импортировать, — а главное, нативной libvosk нужен НАСТОЯЩИЙ
## путь на диске: читать из pck она не умеет вовсе. Значит, в собранной игре
## модель обязана лежать отдельной папкой рядом с .exe, и если её забыли
## скопировать, голосового управления в билде нет совсем (ровно эта потеря и
## чинилась 20.09.2026 — в редакторе всё работало, в Alfa 1.0x модели рядом
## не оказалось).
##
## Обход каталога здесь ЗАКОННЫЙ и правилу 8 («не перебирать DirAccess ради
## ассетов») не противоречит: там речь о res:// и .import, у которых в
## экспорте другие имена, а тут — обычная папка на диске, вне ресурсов.
##
## Порядок кандидатов: проект → рядом с .exe → папка данных экспорта
## (data_<имя>_<платформа>, туда же едут нативные DLL) → user://.
static func model_dirs() -> Array:
	var exe: String = OS.get_executable_path().get_base_dir()
	var roots: Array = [
		ProjectSettings.globalize_path("res://voice_models"),
		exe.path_join("voice_models"),
	]
	var d := DirAccess.open(exe)
	if d != null:
		d.list_dir_begin()
		var nm: String = d.get_next()
		while nm != "":
			if d.current_is_dir() and nm.begins_with("data_"):
				roots.append(exe.path_join(nm).path_join("voice_models"))
			nm = d.get_next()
		d.list_dir_end()
	roots.append(ProjectSettings.globalize_path("user://voice_models"))
	return roots

static func model_path() -> String:
	for r in model_dirs():
		var root: String = String(r)
		var exact: String = root.path_join(MODEL_DIR)
		if DirAccess.dir_exists_absolute(exact):
			return exact
		# Игрок мог положить ДРУГУЮ версию модели: берём первую vosk-model-*.
		# Имя папки в неё не зашито — зашит только порядок поиска
		var dd := DirAccess.open(root)
		if dd == null:
			continue
		dd.list_dir_begin()
		var nm: String = dd.get_next()
		var found: String = ""
		while nm != "":
			if dd.current_is_dir() and nm.begins_with("vosk-model"):
				found = root.path_join(nm)
				break
			nm = dd.get_next()
		dd.list_dir_end()
		if found != "":
			return found
	return ""

func recognizer_ready() -> bool:
	return _rec != null and bool(_rec.IsReady())

## Для стендов: готовый сигнал PCM16 моно 16 кГц → текст (блокирующе)
func recognize_pcm16k(pcm: PackedInt32Array) -> String:
	if _rec == null:
		return ""
	return String(_rec.RecognizeBlocking(pcm))

func recognizer_error() -> String:
	if _last_error != "":
		return _last_error
	return String(_rec.GetError()) if _rec != null else "нет распознавателя"

func _exit_tree() -> void:
	if _rec != null:
		_rec.Stop()

# ─────────────────────────────────────────────────────────────────────────────
# КНОПКА
# ─────────────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or k.keycode != PTT_KEY or k.echo:
		return
	if k.pressed:
		_begin()
	else:
		_end()

func _begin() -> void:
	if _listening or _rec == null:
		return
	_listening = true
	_tail = 0
	if _capture != null:
		_capture.clear_buffer()
	_rec.BeginUtterance()
	_mic_dot.color = Color(0.95, 0.2, 0.2)
	_mic_label.text = "слушаю…"

func _end() -> void:
	if not _listening:
		return
	_listening = false
	_tail = TAIL_FRAMES
	_mic_dot.color = Color(0.5, 0.5, 0.5)
	_mic_label.text = "V — говорить"

func _process(delta: float) -> void:
	_tick_reform(delta)
	# Плашка гаснет по сроку и без распознавателя (headless, стенды)
	if _text_panel.visible and Time.get_ticks_msec() > _text_until_ms:
		_text_panel.visible = false
		_layout_corner()
	if _rec == null:
		return
	# Кадры микрофона — пока кнопка зажата и ещё TAIL_FRAMES после
	if _capture != null and (_listening or _tail > 0):
		var n: int = _capture.get_frames_available()
		if n > 0:
			_rec.Push(_capture.get_buffer(n))
		if not _listening:
			_tail -= 1
			if _tail == 0:
				_rec.EndUtterance()
	elif _tail > 0:
		_tail = 0
		_rec.EndUtterance()
	# Уровень и частичный текст — только пока слушаем
	if _listening:
		var lvl: float = clampf(float(_rec.GetLevel()) * 6.0, 0.0, 1.0)
		_mic_bar.custom_minimum_size.x = 8.0 + 72.0 * lvl
		var part: String = String(_rec.GetPartial())
		if part != "":
			_show_text(part, Color(0.75, 0.75, 0.75), 0.5)
	else:
		_mic_bar.custom_minimum_size.x = 8.0
	# Готовый результат
	var text: String = String(_rec.PollFinal())
	if text != "":
		apply_text(text)

# ─────────────────────────────────────────────────────────────────────────────
# ТЕКСТ → ПРИКАЗ. Отдельная точка входа: стенд кормит её строками без микрофона
# ─────────────────────────────────────────────────────────────────────────────
func apply_text(text: String) -> Dictionary:
	var m: Dictionary = _Cfg.match(text)
	var intent: String = String(m["intent"])
	if intent == "":
		_show_text("не понял: «%s»" % text, Color(1.0, 0.6, 0.6), TEXT_SHOW_SEC)
		return m
	# ── ОБЛАСТЬ: ВЫДЕЛЕНИЕ, ИНАЧЕ КАДР; ПОВЕРХ — ФИЛЬТР РОДА ─────────────
	# «Защита только копейщикам» (спринт 18, письмо 4) РАЗВЁРНУТА ТЗ 19.09.2026,
	# блок 6: «держать строй» переводит в оборону ВСЕ отряды области (с
	# фильтром рода, если он назван) — оборона это остановка, снятие целей и
	# смыкание строя, а не только копья вниз
	var sids: Array = squads_for(m["groups"])
	if sids.is_empty():
		_show_text("некому: «%s»" % text, Color(1.0, 0.85, 0.5), TEXT_SHOW_SEC)
		return m
	var dist: float = float(m["distance"])
	match intent:
		"defense":
			_order_hold(sids)
		"at_ease":
			_order_stance(sids, "attack")
		"stop":
			_order_stop(sids)
		"forward":
			_order_dir(sids, screen_right(), dist)
		"back":
			_order_dir(sids, -screen_right(), dist)
		"up":
			_order_dir(sids, screen_up(), dist)
		"down":
			_order_dir(sids, -screen_up(), dist)
		"attack":
			_order_attack(sids)
		"retreat":
			_order_retreat(sids, dist)
	# Отклик: на атаку — горн, на остальное — один клич первого отряда, не хор
	if intent == "attack":
		AudioManager.play_voice("horn_attack")
		last_voice_event = "horn_attack"
	else:
		GameManager.squad_battle_cry(int(sids[0]))
		last_voice_event = "battle_cry"
	commands_applied += 1
	last_command = m
	_show_text(text, Color(1, 1, 1), TEXT_SHOW_SEC)
	return m

# ─────────────────────────────────────────────────────────────────────────────
# ОБЛАСТЬ ДЕЙСТВИЯ
# ─────────────────────────────────────────────────────────────────────────────
## Отряды, которым адресована команда (ТЗ 19.09.2026, блоки 2-3).
## Есть выделенные боевые отряды игрока (рамка ЛКМ, клик, Ctrl+1..9) —
## команда ТОЛЬКО им; выделение пусто (или в нём одни постройки и рабочие) —
## всем своим боевым отрядам, чей центр В КАДРЕ. Слово рода войск сужает
## область до этого рода; без слова («все» или ничего) — вся область.
## Рабочие и монахи — не боевые (squad_is_combat), их не трогаем нигде
func squads_for(groups: Array) -> Array:
	var all: bool = groups.has("all") or groups.is_empty()
	var area: Array = selected_squads()
	last_area = "selection"
	if area.is_empty():
		area = squads_in_view()
		last_area = "view"
	var out: Array = []
	for sid in area:
		var s: int = int(sid)
		if all or groups.has(GameManager.squad_type(s)):
			out.append(s)
	if out.is_empty() and area.is_empty():
		last_area = ""
	return out

## Боевые отряды игрока в текущем выделении, без повторов, в порядке выделения
func selected_squads() -> Array:
	var out: Array = []
	var sm = _selection_manager()
	if sm == null:
		return out
	var seen: Dictionary = {}
	for u in sm.selected_units:
		if u == null or not is_instance_valid(u) or not (u is Unit):
			continue
		var uu := u as Unit
		if uu.faction != Constants.FACTION_PLAYER or uu.is_dead():
			continue
		var sid: int = uu.squad_id
		if sid <= 0 or seen.has(sid):
			continue
		if not GameManager.squad_is_combat(sid):
			continue
		seen[sid] = true
		out.append(sid)
	return out

## Боевые отряды игрока, чей центр (медиана) попадает в кадр камеры.
## Один обход реестра отрядов на команду — покадрового пути здесь нет
func squads_in_view() -> Array:
	var out: Array = []
	for sq in GameManager.squads_of_faction(Constants.FACTION_PLAYER):
		var d := sq as Dictionary
		var sid: int = int(d["id"])
		if not GameManager.squad_is_combat(sid):
			continue
		var c: Vector3 = GameManager.squad_centroid(sid)
		if in_view(c):
			out.append(sid)
	return out

## Видна ли точка мира на экране. Камера ортографическая с фиксированным
## ракурсом, усечённая пирамида — честный ответ «в кадре ли»; камеры нет
## (стенд без сцены) — по точке фокуса и радиусу видимой земли, а нет и её —
## считаем видимым всё
func in_view(p: Vector3) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and is_instance_valid(cam):
		return cam.is_position_in_frustum(p)
	if GameManager.has_view_point():
		var vp: Vector3 = GameManager.view_point()
		var r: float = GameManager.view_radius()
		return Vector2(p.x - vp.x, p.z - vp.z).length() <= r
	return true

## ── ОСИ ЭКРАНА В МИРЕ (ТЗ 19.09.2026, блок 4) ─────────────────────────────
## «Вперёд» — вправо по экрану, «вверх» — вверх по экрану. Ракурс камеры
## зафиксирован (RTSCamera.FIXED_YAW 0: X+ мира = экранное право, Z− = верх
## экрана), но оси берутся у самой камеры — из её базиса, спроецированного на
## землю, — и не разойдутся с картинкой, если ракурс когда-нибудь подвинут
func screen_right() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and is_instance_valid(cam):
		var r: Vector3 = cam.global_transform.basis.x
		r.y = 0.0
		if r.length_squared() > 1e-6:
			return r.normalized()
	return Vector3(1, 0, 0)

func screen_up() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and is_instance_valid(cam):
		var u: Vector3 = -cam.global_transform.basis.z
		u.y = 0.0
		if u.length_squared() > 1e-6:
			return u.normalized()
	return Vector3(0, 0, -1)

## Последний вектор движения отряда, выданный голосом (окно для стендов)
func last_vec(sid: int) -> Vector3:
	var v: Variant = _last_vec.get(sid)
	return (v as Vector3) if v != null else Vector3.ZERO

func _selection_manager():
	var mn = GameManager.main
	if mn == null or not is_instance_valid(mn):
		return null
	return mn.get("selection_manager")

## Совместимость со старым стендом
func spearman_squads() -> Array:
	return squads_for(["spearman"])

# ─────────────────────────────────────────────────────────────────────────────
# ПРИКАЗЫ
# ─────────────────────────────────────────────────────────────────────────────
func _order_stance(sids: Array, stance: String) -> void:
	for sid in sids:
		_reform.erase(int(sid))   # ручная стойка отменяет отложенное опускание копий
		for u in GameManager.squad_members(int(sid)):
			if is_instance_valid(u) and (u as Unit).has_method("set_stance"):
				(u as Unit).set_stance(stance)
		GameManager.on_squad_stance(int(sid), stance)   # стена копий (спринт 18)

## ── «ДЕРЖАТЬ СТРОЙ» = ОБОРОНА С МЕСТА ВСЕМ ОТРЯДАМ ОБЛАСТИ (блок 6) ──────
## Три действия, и порядок между ними важен:
##  1. СМЫКАНИЕ СТРОЯ — первым. Штатное squad_close_ranks(force) судит о
##     целости строя по посту бойца (post_pos), а остановка (command_move в
##     собственную точку) переносит пост под ноги — сомкни после неё, и
##     растянутый строй читался бы целым. Смыкание само не трогает ни
##     дерущихся, ни идущих по приказу игрока — их останавливает шаг 2.
##  2. ОСТАНОВКА тех, кто дерётся (цель снята — преследование кончилось) или
##     идёт по прежнему приказу игрока: встать где стоят.
##  3. СТОЙКА «оборона» каждому и отрядная точка входа on_squad_stance — тот
##     же путь, что у кнопки [ЗАЩИТА] панели: копейщикам со «Стеной копий»
##     достаётся стена, стоящему отряду — разметка «где стоим»
##     (_formation_in_place), без единого шага (ТЗ 14.09.2026, п. 8).
## РАЗВОРОТ: до ТЗ 19.09.2026 голосовая «защита» шла ТОЛЬКО копейщикам
## (спринт 18, письмо 4); теперь — всем родам области, с фильтром рода,
## если он назван («лучники держать строй» — только лучникам)
func _order_hold(sids: Array) -> void:
	for sid in sids:
		var s: int = int(sid)
		_reform.erase(s)
		var members: Array = GameManager.squad_members(s)
		if members.is_empty():
			continue
		GameManager.squad_close_ranks(s, true)
		for u in members:
			if not is_instance_valid(u):
				continue
			var uu := u as Unit
			if uu.attack_target != null or uu.player_order_active() or uu.target_lock:
				uu.command_move(uu.global_position, false, Vector3.ZERO, false, true)
		for u2 in members:
			if is_instance_valid(u2) and (u2 as Unit).has_method("set_stance"):
				(u2 as Unit).set_stance("defense")
		GameManager.on_squad_stance(s, "defense")

## Встать на месте: приказ идти в собственную точку — прибытие мгновенное,
## боец переходит в покой, цель атаки снята; стойка и курс не меняются
func _order_stop(sids: Array) -> void:
	for sid in sids:
		_reform.erase(int(sid))
		for u in GameManager.squad_members(int(sid)):
			if not is_instance_valid(u):
				continue
			var uu := u as Unit
			uu.command_move(uu.global_position, false, Vector3.ZERO, false, true)

## ── СДВИГ ПО ОСИ ЭКРАНА (блоки 4-5) ───────────────────────────────────────
## Марш всем составом на dist по единичному вектору dir: каждому бойцу своя
## точка, смещённая на один и тот же вектор, — строй переносится целиком (тот
## же приём, что у стены строя и у марша мышью). Разметка отряда переезжает
## вместе с людьми, курс = направление хода: по нему считаются ряды фаланги и
## смыкание после боя. face — куда смотреть по приходу (по умолчанию по ходу;
## отход смотрит НАЗАД, на противника). Вектор запоминается — по нему строит
## обратный «отступать» (remember = false — сам отход: повторное «отступать»
## обязано вести ДАЛЬШЕ в ту же сторону, а не разворачивать отряд обратно)
func _order_dir(sids: Array, dir: Vector3, dist: float, face: Vector3 = Vector3.ZERO,
		remember: bool = true) -> void:
	dir.y = 0.0
	if dir.length_squared() < 1e-6:
		return
	dir = dir.normalized()
	var face_dir: Vector3 = face if face.length_squared() > 1e-6 else dir
	var shift: Vector3 = dir * dist
	for sid in sids:
		var s: int = int(sid)
		_reform.erase(s)
		var members: Array = GameManager.squad_members(s)
		if members.is_empty():
			continue
		_shift_formation(s, members, shift, face_dir)
		for u in members:
			if not is_instance_valid(u):
				continue
			var uu := u as Unit
			uu.command_move(uu.global_position + shift, false, face_dir, false, true)
		if remember:
			_last_vec[s] = dir

## Разметка отряда, перенесённая на тот же вектор: места — текущие точки
## бойцов плюс сдвиг, порядок от передовой к тылу по курсу (так требует
## смыкание рядов, см. SelectionManager._issue_march_keeping_shape)
func _shift_formation(sid: int, members: Array, shift: Vector3, course: Vector3) -> void:
	var ordered: Array = []
	for u in members:
		if is_instance_valid(u):
			ordered.append(u)
	ordered.sort_custom(func(a, b):
		return (a as Node3D).global_position.dot(course) > (b as Node3D).global_position.dot(course))
	var slots: Array = []
	for u in ordered:
		var p: Vector3 = (u as Node3D).global_position + shift
		p.y = 0.0
		slots.append(p)
	GameManager.squad_set_formation(sid, slots, course, false)

## ── «В АТАКУ» — ЭТО ПРИКАЗ АТАКИ, А НЕ МАРШ ВСЛЕПУЮ ─────────────────────────
## ЖАЛОБА ВЛАДЕЛЬЦА (спринт 15): «лучники по команде "в атаку" должны выдвигаться
## вперёд, но строго при входе на дистанцию атаки ближайшего противника
## останавливаться и открывать огонь». Прежде команда была маршем на ATTACK_M
## по курсу — а МАРШ ИДЁТ МИМО ВРАГА: авто-агро работает только в покое, и
## отряд лучников честно проходил свои сорок метров сквозь дистанцию выстрела,
## не выпустив ни одной стрелы, и вставал где-то за противником.
##
## Теперь команда ищет ближайшего чужого у центра отряда и раздаёт ТОТ ЖЕ
## приказ атаки, что и правый клик мышью (command_attack с замком цели): к нему
## подходят на дистанцию своего оружия и бьют — стрелок встаёт и стреляет
## (Archer.pursues_target = false), пехота доходит до рукопашной. Врага в
## пределах видимости нет — остаётся прежний марш по курсу: команда «в атаку»
## в чистом поле обязана хоть что-то делать.
##
## РАДИУС ПОИСКА ЧУТЬ МЕНЬШЕ ATTACK_M, И ЭТО НЕ ОКРУГЛЕНИЕ: замок цели дальше
## Unit._lock_sight_range() (у лучника 2 × дальность = 40 м) сбрасывается на
## подходе как исчерпанный (замер спринта 14), а задняя шеренга стоит на
## несколько метров дальше центра отряда. Запас — на глубину строя
const VOICE_ATTACK_SEARCH_K := 0.85

func _order_attack(sids: Array) -> void:
	var march_sids: Array = []
	for sid in sids:
		var s: int = int(sid)
		_reform.erase(s)
		var c: Vector2 = GameManager.squad_centre_xz(s)
		var foe: Node3D = null
		if c.x != INF:
			foe = _nearest_foe(Vector3(c.x, 0.0, c.y), _Cfg.ATTACK_M * VOICE_ATTACK_SEARCH_K)
		if foe == null:
			march_sids.append(s)
			continue
		var fp: Vector3 = foe.global_position
		var to_foe := Vector3(fp.x - c.x, 0.0, fp.z - c.y)
		if to_foe.length_squared() > 1e-6:
			_last_vec[s] = to_foe.normalized()   # «отступать» после атаки — прочь от неё
		for u in GameManager.squad_members(s):
			if not is_instance_valid(u):
				continue
			var uu := u as Unit
			if uu.has_method("command_attack"):
				# Те же четыре аргумента, что у правого клика (SelectionManager):
				# приказ игрока, разгон разрешён, замок цели
				uu.command_attack(foe, true, true, true)
	# Врага рядом нет — марш по курсу отряда (курс, а не ось экрана: «в атаку»
	# оставлено как было, ТЗ 19.09.2026)
	for s2 in march_sids:
		_order_dir([s2], squad_heading(int(s2)), _Cfg.ATTACK_M)

## Ближайший живой чужой боец в радиусе от точки — по сетке соседей, а не
## перебором армии. Зовётся ИЗ ПРИКАЗА (раз на команду), не из кадра
func _nearest_foe(at: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for n in GameManager.unit_grid.query_radius(at, radius):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.garrisoned:
			continue
		# Свои и нейтралы (рабочие ничейного рудника) — не враги
		if u.faction == Constants.FACTION_PLAYER or u.faction == Constants.FACTION_NEUTRAL:
			continue
		var d: float = at.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

## ── ОТХОД: СТРОГО ОБРАТНО ПОСЛЕДНЕМУ ДВИЖЕНИЮ (блок 5) ────────────────────
## Шёл вправо — отходит влево, шёл вверх — вниз. Вектор берётся: (1) из
## последнего голосового приказа отряду, (2) иначе из курса разметки
## (последний приказ мышью — squad_course), (3) отряд стоял и курса нет —
## прочь от ближайшего врага в RETREAT_FOE_SEARCH_M, (4) врага нет — назад
## от направления на чужую базу (squad_heading). Лицом — на то, откуда
## отходим. Заказ владельца: фаланга не пятится с опущенными копьями. Копья
## поднимаются (стойка «атака»), отряд отходит, по приходу встаёт лицом к
## противнику (face_on_arrive) и снова опускает копья (стойка «оборона»).
## Отряды в другой стойке просто отходят
func _order_retreat(sids: Array, dist: float) -> void:
	for sid in sids:
		var s: int = int(sid)
		var members: Array = GameManager.squad_members(s)
		if members.is_empty():
			continue
		var back: Vector3 = retreat_dir(s)
		var in_defense := 0
		for u in members:
			if is_instance_valid(u) and (u as Unit).stance == "defense":
				in_defense += 1
		var phalanx: bool = in_defense * 2 > members.size()
		if phalanx:
			for u in members:
				if is_instance_valid(u):
					(u as Unit).set_stance("attack")   # копья вверх на время отхода
		var centre_before: Vector3 = GameManager.squad_centroid(s)
		_order_dir([s], back, dist, -back, false)
		if phalanx:
			_reform[s] = {
				"target": centre_before + back * dist,
				"until_ms": Time.get_ticks_msec() + int(REFORM_TIMEOUT_SEC * 1000.0),
			}

## Куда отходит отряд (единичный вектор XZ) — см. _order_retreat
func retreat_dir(sid: int) -> Vector3:
	var lv: Vector3 = last_vec(sid)
	if lv.length_squared() > 1e-6:
		return -lv.normalized()
	var course: Vector3 = GameManager.squad_course(sid)
	course.y = 0.0
	if course.length_squared() > 1e-6:
		return -course.normalized()
	var mid: Vector3 = GameManager.squad_centroid(sid)
	var foe: Node3D = _nearest_foe(mid, RETREAT_FOE_SEARCH_M)
	if foe != null:
		var fp: Vector3 = foe.global_position
		var away := Vector3(mid.x - fp.x, 0.0, mid.z - fp.z)
		if away.length_squared() > 1e-6:
			return away.normalized()
	return -squad_heading(sid)

## Такт отхода: отряд пришёл (центр у цели или все встали) — копья вниз
func _tick_reform(delta: float) -> void:
	if _reform.is_empty():
		return
	_reform_timer -= delta
	if _reform_timer > 0.0:
		return
	_reform_timer = REFORM_CHECK_SEC
	var now: int = Time.get_ticks_msec()
	for sid in _reform.keys():
		var s: int = int(sid)
		var rec: Dictionary = _reform[s]
		var members: Array = GameManager.squad_members(s)
		if members.is_empty():
			_reform.erase(s)
			continue
		var c: Vector3 = GameManager.squad_centroid(s)
		var t: Vector3 = rec["target"]
		var arrived: bool = Vector2(c.x - t.x, c.z - t.z).length() <= REFORM_ARRIVE_M
		if not arrived:
			var moving := 0
			for u in members:
				if is_instance_valid(u) and (u as Unit).state == Unit.State.MOVING:
					moving += 1
			arrived = moving == 0
		if arrived or now >= int(rec["until_ms"]):
			for u in members:
				if is_instance_valid(u) and (u as Unit).has_method("set_stance"):
					(u as Unit).set_stance("defense")
			_reform.erase(s)

## Есть ли отложенное опускание копий у отряда (окно для стендов)
func reform_pending(sid: int) -> bool:
	return _reform.has(sid)

## Курс отряда: курс последнего строевого приказа; без него — на замок
## противника от центра отряда. Читает марш «в атаку» без врага рядом
static func squad_heading(sid: int) -> Vector3:
	var c: Vector3 = GameManager.squad_course(sid)
	c.y = 0.0
	if c.length_squared() > 1e-6:
		return c.normalized()
	var mid: Vector3 = GameManager.squad_centroid(sid)
	var enemy: Vector3 = Vector3(GameManager.map_lim_x, 0.0, GameManager.map_lim_z)
	var keep = GameManager.get_nearest_dropoff(Constants.FACTION_ENEMY, mid)
	if keep != null and is_instance_valid(keep):
		enemy = (keep as Node3D).global_position
	var d := Vector3(enemy.x - mid.x, 0.0, enemy.z - mid.z)
	return d.normalized() if d.length_squared() > 1e-6 else Vector3(1, 0, 0)

# ─────────────────────────────────────────────────────────────────────────────
# ИНТЕРФЕЙС: иконка микрофона и плашка текста — В ПРАВОМ НИЖНЕМ УГЛУ
# (ТЗ 19.09.2026, блок 1). В левом верхнем иконка перекрывала панель
# выделенного рабочего, плашка по центру низа — панель выделения. Оба узла
# привязаны к правому нижнему углу якорями (1, 1) и растут ВЛЕВО и ВВЕРХ
# (grow BEGIN): контейнер сам берёт размер по содержимому, а угол остаётся
# на месте при любом тексте и любом размере окна
# ─────────────────────────────────────────────────────────────────────────────
func _setup_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	# Один столбик у правого нижнего угла: сверху плашка текста (пока видна),
	# снизу иконка микрофона. Оба прижаты к правому краю столбика, столбик
	# растёт влево и вверх — перекрыться им нечем по построению
	_ui_box = VBoxContainer.new()
	_ui_box.name = "VoiceCorner"
	_ui_box.alignment = BoxContainer.ALIGNMENT_END
	_ui_box.add_theme_constant_override("separation", int(MIC_TEXT_GAP))
	_pin_bottom_right(_ui_box, UI_MARGIN, UI_MARGIN)
	_layer.add_child(_ui_box)
	# Столбик кладётся в угол ЯВНО по каждому изменению размера: у Control под
	# CanvasLayer рост минимального размера двигает размер, но не позицию
	# (grow BEGIN не срабатывает — проверено зондом), а сжатия по скрытию
	# плашки у контейнера нет вовсе
	_ui_box.resized.connect(_layout_corner)
	get_viewport().size_changed.connect(_layout_corner)

	_text_panel = PanelContainer.new()
	_text_panel.name = "VoiceText"
	_text_panel.visible = false
	_text_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_text_panel.add_theme_stylebox_override("panel", style)
	_ui_box.add_child(_text_panel)
	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", TEXT_FONT_PX)
	_text_panel.add_child(_text_label)

	_mic_box = HBoxContainer.new()
	_mic_box.name = "MicBox"
	_mic_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	_mic_box.add_theme_constant_override("separation", 6)
	_ui_box.add_child(_mic_box)
	_mic_dot = ColorRect.new()
	_mic_dot.custom_minimum_size = Vector2(14, 14)
	_mic_dot.color = Color(0.5, 0.5, 0.5)
	_mic_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mic_box.add_child(_mic_dot)
	_mic_bar = ColorRect.new()
	_mic_bar.custom_minimum_size = Vector2(8, 14)
	_mic_bar.color = Color(0.3, 0.9, 0.3)
	_mic_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mic_box.add_child(_mic_bar)
	_mic_label = Label.new()
	_mic_label.text = "V — говорить"
	_mic_label.add_theme_font_size_override("font_size", 13)
	_mic_box.add_child(_mic_label)

## Якоря правого нижнего угла: узел растёт влево и вверх от точки
## (−right, −bottom) относительно кромок экрана
static func _pin_bottom_right(c: Control, bottom: float, right: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_left = -right
	c.offset_right = -right
	c.offset_top = -bottom
	c.offset_bottom = -bottom

## Столбик — размером в своё содержимое, правым нижним углом в точке
## (экран − UI_MARGIN). Сначала размер (это снова зовёт resized), потом позиция
func _layout_corner() -> void:
	if _ui_box == null or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ms: Vector2 = _ui_box.get_combined_minimum_size()
	if _ui_box.size != ms:
		_ui_box.size = ms
		return
	_ui_box.position = vp - Vector2(UI_MARGIN, UI_MARGIN) - ms

func _show_text(text: String, color: Color, sec: float) -> void:
	_text_label.text = text
	_text_label.add_theme_color_override("font_color", color)
	_text_panel.visible = true
	_text_until_ms = Time.get_ticks_msec() + int(sec * 1000.0)
	_layout_corner()

func shown_text() -> String:
	return _text_label.text if _text_panel.visible else ""

## Окна для стендов: прямоугольники иконки и плашки на экране, размер шрифта
func mic_rect() -> Rect2:
	return _mic_box.get_global_rect() if _mic_box != null else Rect2()

func text_rect() -> Rect2:
	return _text_panel.get_global_rect() if _text_panel != null else Rect2()

func text_font_px() -> int:
	return _text_label.get_theme_font_size("font_size") if _text_label != null else 0
