## ═══════════════════════════════════════════════════════════════════════════
## ГОЛОСОВОЕ УПРАВЛЕНИЕ: микрофон → Vosk в фоне → приказ отрядам по типу войск
## ═══════════════════════════════════════════════════════════════════════════
## Изолированный узел: свой аудио-бус с захватом, свой слой интерфейса (иконка
## микрофона, плашка распознанного текста), свой C#-распознаватель в фоновом
## потоке. Главный поток за кадр делает две дешёвые вещи: забирает буфер
## микрофона (копия нескольких сотен пар float) и опрашивает очередь
## результатов. Ни один шаг распознавания в главном потоке не идёт.
##
## Управление: зажать V (push-to-talk), сказать, отпустить. Через 0.3-0.8 с
## плашка внизу показывает текст, отряды откликаются и исполняют.
##
## КТО: «копейщики / фаланга», «лучники / стрелки», «мечники / пехота»,
## «конница / всадники», «все / армия»; ни одна группа не названа — все боевые.
## Групп в одной фразе может быть несколько.
## ЧТО (voice_commands_config.INTENTS):
##   «в атаку»          → марш по курсу на ATTACK_M, звучит ГОРН
##   «вперёд / марш»    → марш по курсу на FORWARD_M, стойка как была
##   «отступать [на N]» → отход назад на N м лицом к противнику; фаланга
##                        поднимает копья на время отхода и опускает по приходу
##   «стоять»           → встать на месте, стойка не меняется
##   «держать позицию»  → стойка «оборона» (копья вниз)
##   «вольно»           → стойка «атака» (копья вверх, просто стоят)
## Приказы идут ТЕМИ ЖЕ функциями, что и мышь (set_stance, command_move с
## player_order); строй переносится целиком одним вектором на всех.
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

var _rec = null                       # VoiceRecognizer (C#)
var _capture: AudioEffectCapture = null
var _player: AudioStreamPlayer = null
var _listening: bool = false
var _tail: int = 0
var _layer: CanvasLayer = null
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
## Фаланги в отходе: sid → {"target": центр назначения, "until_ms"}
var _reform: Dictionary = {}
var _reform_timer: float = 0.0

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
		_last_error = "модель не найдена (voice_models/%s)" % MODEL_DIR
		push_warning("VoiceControl: " + _last_error)
		return
	var grammar: String = JSON.stringify(_Cfg.grammar_words())
	if not _rec.Start(dir, grammar, AudioServer.get_mix_rate()):
		_last_error = String(_rec.GetError())
		push_warning("VoiceControl: " + _last_error)

## Модель ищется рядом с проектом (res://voice_models, папка под .gdignore) и
## рядом с исполняемым файлом (экспорт). PCK её не содержит намеренно: 45 МБ
## и тысячи файлов, которые Godot иначе пытался бы импортировать
static func model_path() -> String:
	var candidates: Array = [
		ProjectSettings.globalize_path("res://voice_models/" + MODEL_DIR),
		OS.get_executable_path().get_base_dir().path_join("voice_models").path_join(MODEL_DIR),
	]
	for c in candidates:
		if DirAccess.dir_exists_absolute(String(c)):
			return String(c)
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
		_mic_bar.size.x = 8.0 + 72.0 * lvl
		var part: String = String(_rec.GetPartial())
		if part != "":
			_show_text(part, Color(0.75, 0.75, 0.75), 0.5)
	else:
		_mic_bar.size.x = 8.0
	# Готовый результат
	var text: String = String(_rec.PollFinal())
	if text != "":
		apply_text(text)
	if _text_panel.visible and Time.get_ticks_msec() > _text_until_ms:
		_text_panel.visible = false

# ─────────────────────────────────────────────────────────────────────────────
# ТЕКСТ → ПРИКАЗ. Отдельная точка входа: стенд кормит её строками без микрофона
# ─────────────────────────────────────────────────────────────────────────────
func apply_text(text: String) -> Dictionary:
	var m: Dictionary = _Cfg.match(text)
	var intent: String = String(m["intent"])
	if intent == "":
		_show_text("не понял: «%s»" % text, Color(1.0, 0.6, 0.6), TEXT_SHOW_SEC)
		return m
	var sids: Array = squads_for(m["groups"])
	# ── «ЗАЩИТА» — ТОЛЬКО КОПЕЙЩИКАМ (четвёртое письмо спринта 18) ────────
	# «Деф / защита / держать строй» — режим фаланги: копейщики выделения
	# смыкаются стеной копий, ВСЕ ОСТАЛЬНЫЕ (лучники, мечники, конница)
	# команду не получают вовсе: ни стойки, ни строя, ни сброса приказа.
	# Выделение пусто — все копейщики армии: команда никого не срывает с
	# места, «срыва армии» из прежней жалобы здесь нет
	if intent == "defense":
		sids = _spearmen_only(sids if not sids.is_empty() else _all_squads_of_type("spearman"))
	if sids.is_empty():
		_show_text("некому: «%s»" % text, Color(1.0, 0.85, 0.5), TEXT_SHOW_SEC)
		return m
	match intent:
		"defense":
			_order_stance(sids, "defense")
		"at_ease":
			_order_stance(sids, "attack")
		"stop":
			_order_stop(sids)
		"forward":
			_order_march(sids, _Cfg.FORWARD_M, false)
		"attack":
			_order_attack(sids)
		"retreat":
			_order_retreat(sids, float(m["distance"]))
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

## ── ГОЛОС — ТОЛЬКО ВЫДЕЛЕННЫМ (спринт 18, второе письмо) ─────────────────
## Жалоба: «голосовые команды выполняет ВСЯ армия на карте». Раньше отряды
## брались по типу из реестра ВСЕЙ армии игрока. Теперь — из текущего
## выделения (рамка ЛКМ, клик по отряду, группа Ctrl+1..9): слово рода войск
## сужает выделение до этого типа, без слова («все» или ничего) — всё
## выделенное боевое. Пусто выделение — пусто и множество: с места никто не
## срывается. Рабочих не трогаем и здесь
func squads_for(groups: Array) -> Array:
	var out: Array = []
	var all: bool = groups.has("all") or groups.is_empty()
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
		var kind: String = GameManager.squad_type(sid)
		if all or groups.has(kind):
			seen[sid] = true
			out.append(sid)
	return out

## Только копейщики из списка отрядов
func _spearmen_only(sids: Array) -> Array:
	var out: Array = []
	for sid in sids:
		if GameManager.squad_type(int(sid)) == "spearman":
			out.append(int(sid))
	return out

## Все отряды игрока данного рода войск (для «защиты» без выделения)
func _all_squads_of_type(kind: String) -> Array:
	var out: Array = []
	for sq in GameManager.squads_of_faction(Constants.FACTION_PLAYER):
		var d := sq as Dictionary
		if String(d["type"]) == kind:
			out.append(int(d["id"]))
	return out

func _selection_manager():
	var mn = GameManager.main
	if mn == null or not is_instance_valid(mn):
		return null
	return mn.get("selection_manager")

## Совместимость со старым стендом
func spearman_squads() -> Array:
	return squads_for(["spearman"])

func _order_stance(sids: Array, stance: String) -> void:
	for sid in sids:
		_reform.erase(int(sid))   # ручная стойка отменяет отложенное опускание копий
		for u in GameManager.squad_members(int(sid)):
			if is_instance_valid(u) and (u as Unit).has_method("set_stance"):
				(u as Unit).set_stance(stance)
		GameManager.on_squad_stance(int(sid), stance)   # стена копий (спринт 18)

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

## Марш всем составом по курсу отряда: каждому бойцу своя точка, смещённая на
## один и тот же вектор, — строй переносится целиком (тот же приём, что у
## стены строя). back = true — назад, лицом к противнику
func _order_march(sids: Array, dist: float, back: bool) -> void:
	for sid in sids:
		_reform.erase(int(sid))
		var course: Vector3 = squad_heading(int(sid))
		var shift: Vector3 = course * (-dist if back else dist)
		for u in GameManager.squad_members(int(sid)):
			if not is_instance_valid(u):
				continue
			var uu := u as Unit
			uu.command_move(uu.global_position + shift, false, course, false, true)

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
		for u in GameManager.squad_members(s):
			if not is_instance_valid(u):
				continue
			var uu := u as Unit
			if uu.has_method("command_attack"):
				# Те же четыре аргумента, что у правого клика (SelectionManager):
				# приказ игрока, разгон разрешён, замок цели
				uu.command_attack(foe, true, true, true)
	if not march_sids.is_empty():
		_order_march(march_sids, _Cfg.ATTACK_M, false)

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

## ОТХОД. Заказ владельца: фаланга не пятится с опущенными копьями. Копья
## поднимаются (стойка «атака»), отряд отходит на N м, по приходу встаёт,
## разворачивается лицом к противнику (face_on_arrive = курс) и снова
## опускает копья (стойка «оборона»). Отряды в другой стойке просто отходят
func _order_retreat(sids: Array, dist: float) -> void:
	for sid in sids:
		var s: int = int(sid)
		var members: Array = GameManager.squad_members(s)
		if members.is_empty():
			continue
		var in_defense := 0
		for u in members:
			if is_instance_valid(u) and (u as Unit).stance == "defense":
				in_defense += 1
		var phalanx: bool = in_defense * 2 > members.size()
		if phalanx:
			for u in members:
				if is_instance_valid(u):
					(u as Unit).set_stance("attack")   # копья вверх на время отхода
		var course: Vector3 = squad_heading(s)
		var shift: Vector3 = course * (-dist)
		for u in members:
			if not is_instance_valid(u):
				continue
			var uu := u as Unit
			uu.command_move(uu.global_position + shift, false, course, false, true)
		if phalanx:
			_reform[s] = {
				"target": GameManager.squad_centroid(s) + shift,
				"until_ms": Time.get_ticks_msec() + int(REFORM_TIMEOUT_SEC * 1000.0),
			}

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
## противника от центра отряда
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
# ИНТЕРФЕЙС: иконка микрофона слева сверху, плашка текста внизу по центру
# ─────────────────────────────────────────────────────────────────────────────
func _setup_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	var mic := HBoxContainer.new()
	mic.position = Vector2(12, 60)
	mic.add_theme_constant_override("separation", 6)
	_layer.add_child(mic)
	_mic_dot = ColorRect.new()
	_mic_dot.custom_minimum_size = Vector2(14, 14)
	_mic_dot.color = Color(0.5, 0.5, 0.5)
	mic.add_child(_mic_dot)
	_mic_bar = ColorRect.new()
	_mic_bar.custom_minimum_size = Vector2(8, 14)
	_mic_bar.size = Vector2(8, 14)
	_mic_bar.color = Color(0.3, 0.9, 0.3)
	mic.add_child(_mic_bar)
	_mic_label = Label.new()
	_mic_label.text = "V — говорить"
	_mic_label.add_theme_font_size_override("font_size", 13)
	mic.add_child(_mic_label)

	_text_panel = PanelContainer.new()
	_text_panel.visible = false
	_text_panel.anchor_left = 0.5
	_text_panel.anchor_right = 0.5
	_text_panel.anchor_top = 1.0
	_text_panel.anchor_bottom = 1.0
	_text_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_text_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_text_panel.offset_bottom = -110
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_text_panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(_text_panel)
	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 20)
	_text_panel.add_child(_text_label)

func _show_text(text: String, color: Color, sec: float) -> void:
	_text_label.text = text
	_text_label.add_theme_color_override("font_color", color)
	_text_panel.visible = true
	_text_panel.reset_size()
	_text_until_ms = Time.get_ticks_msec() + int(sec * 1000.0)

func shown_text() -> String:
	return _text_label.text if _text_panel.visible else ""
