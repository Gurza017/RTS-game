extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗВУКОВОЙ ДВИЖОК ПРОЕКТА (автозагрузка)
## ═══════════════════════════════════════════════════════════════════════════
## Один вход для всего звука: шины, громкости, музыка, эмбиент, 3D-эффекты
## и ограничитель одновременных звуков.
##
## ШИНЫ создаются В КОДЕ, а не в default_bus_layout.tres: раскладка шин —
## отдельный ресурс, который легко разъезжается с кодом при слиянии правок.
## Здесь же видно и что создаётся, и куда что отправляется:
##     Master ← Music   (музыка и эмбиент)
##            ← SFX     (бой, работа, интерфейс)
##
## СЛУШАТЕЛЬ. Камера в ортографии УНЕСЕНА на 400 м назад (см. RTSCamera.
## ORTHO_DISTANCE), поэтому она НЕ ГОДИТСЯ как точка слуха: любой 3D-звук
## оказался бы за пределами max_distance. Слушателем работает отдельный
## AudioListener3D, стоящий в ТОЧКЕ ФОКУСА камеры на земле (ставит Main).
## Отсюда и требуемое поведение: подвёл камеру к рабочим — слышно топоры,
## увёл на другой конец карты — звук плавно ушёл.
##
## ОГРАНИЧИТЕЛЬ. В свалке на 500 бойцов события идут сотнями в секунду.
## Без ограничителя это каша и перегруз. Поэтому у каждой категории есть
## свой лимит одновременных голосов и своя пауза между запусками, а всего
## голосов в пуле POOL_SIZE — больше физически не зазвучит.

# ── ПУТИ К АССЕТАМ ───────────────────────────────────────────────────────────
# Имена папок в проекте отличаются от тех, что просили в задании
# (environment/main_sound → «environment/Main Sounds», sound/human →
# «factions/humans/Sounds Human»), поэтому пути собраны здесь явно
const DIR_MUSIC := "res://assets/environment/Main Sounds/"
const DIR_SFX   := "res://assets/factions/humans/Sounds Human/"

const MUSIC_BACKGROUND := DIR_MUSIC + "Main sound background.ogg"
const AMBIENCE_FOREST  := DIR_MUSIC + "Forest Day.ogg"

## Категории эффектов: id → список файлов. Из списка каждый раз берётся
## СЛУЧАЙНЫЙ файл — это и есть рандомизация (AudioStreamRandomizer здесь не
## нужен: выбор одной строки из массива дешевле и не плодит ресурсов)
const SFX_BANK := {
	"chop":        ["chop 1.ogg", "chop 2.ogg", "chop 3.ogg", "chop 4.ogg"],
	"mine_gold":   ["mine 1.ogg"],
	"mine_stone":  ["mine 2.ogg"],
	"bow_attack":  ["Bow Attack 1.ogg", "Bow Attack 2.ogg"],
	"bow_impact":  ["Bow Impact Hit 1.ogg", "Bow Impact Hit 2.ogg", "Bow Impact Hit 3.ogg"],
	"bow_block":   ["Bow Blocked 1.ogg", "Bow Blocked 2.ogg", "Bow Blocked 3.ogg"],
	"sword_attack": ["Sword Attack 1.ogg", "Sword Attack 2.ogg", "Sword Attack 3.ogg"],
	"sword_hit":   ["Sword_hit_armor 1.mp3", "Sword_hit_armor 2.mp3",
					"Sword_hit_armor 3.mp3", "Sword_hit_armor 4.mp3"],
	"spear_hit":   ["WHSH_Whoosh_HoveAud_SwordCombat_07.wav",
					"WHSH_Whoosh_HoveAud_SwordCombat_26.wav"],
	"vox_action":  ["VOXEfrt_ActionGrunt_HoveAud_SwordCombat_01.wav",
					"VOXEfrt_ActionGrunt_HoveAud_SwordCombat_07.wav",
					"VOXEfrt_ActionGrunt_HoveAud_SwordCombat_23.wav",
					"VOXEfrt_ActionGrunt_HoveAud_SwordCombat_29.wav",
					"VOXEfrt_ActionGrunt_HoveAud_SwordCombat_54.wav"],
	"vox_death":   ["VOXScrm_DamageGrunt_HoveAudio_SwordCombat_01.wav",
					"VOXScrm_DamageGrunt_HoveAudio_SwordCombat_13.wav",
					"VOXScrm_DamageGrunt_HoveAudio_SwordCombat_22.wav",
					"VOXScrm_DamageGrunt_HoveAudio_SwordCombat_27.wav"],
	# ЗАДЕЛ: звон щитов при толкании. Файл есть, вызов включается одной строкой
	# в Unit._apply_push() — см. play_3d("metal_punch", ...)
	"metal_punch": ["metal_punch_06.wav"],
	# БОЕВОЙ КЛИЧ ОТРЯДА: смена стойки и приказ на марш (см. GameManager.squad_battle_cry).
	# Имя файла на диске — строчными и через дефисы; в ТЗ оно было записано как
	# «Sounds/Human/Soldiers_BattleCry.wav», такого пути в проекте нет вовсе
	"battle_cry":  ["soldiers-battle-cry.wav"],
}

## Настройки категории: сколько голосов ей можно занять одновременно,
## какая минимальная пауза между запусками (сек) и с какой громкостью (дБ).
## Это и есть «сбалансированное переплетение»: редкие и важные звуки (смерть,
## попадание стрелы) получают больше голосов, частый фон — меньше
## СБАЛАНСИРОВАНО ПОД «КАНОНАДУ БОЯ». Пул вырос с 24 голосов до 40, и вместе с
## ним подняты лимиты боевых категорий: раньше на всю рубку приходилось по
## 4-5 голосов, сотня бойцов укладывалась в них за первые же удары, и остальной
## бой шёл в полной тишине. Паузы между запусками (gap) укорочены — из редких
## отдельных ударов складывается сплошной гул, а не метроном.
##
## РАБОЧИЕ ЗВУКИ (chop/mine) НАМЕРЕННО НЕ РАСШИРЕНЫ: у них своё прореживание
## по плотности (work_density), и лишние голоса им ни к чему — иначе стук
## сорока топоров перекроет сражение.
const SFX_LIMITS := {
	# Рубка: голосов и «окна» прибавлено под возросший темп взмаха
	# (Worker.CHOP_SWING_RATE +30%) — иначе лишние удары просто съедались
	# ограничителем и на слух ничего бы не изменилось
	"chop":         {"voices": 6, "gap": 0.07, "db": -3.0},
	"mine_gold":    {"voices": 3, "gap": 0.12, "db": -4.0},
	"mine_stone":   {"voices": 3, "gap": 0.12, "db": -4.0},
	# Свист стрел и залпы — самая частая ткань боя, голосов им нужно больше всех
	"bow_attack":   {"voices": 6, "gap": 0.03,  "db": -7.0},
	"bow_impact":   {"voices": 6, "gap": 0.035, "db": -4.0},
	"bow_block":    {"voices": 4, "gap": 0.06,  "db": -8.0},
	# Сталь: замах тише попадания — так слышно, КТО кого достал.
	# У sword_hit пауза чуть длиннее соседей НЕ на слух, а по цене: его сэмплы
	# лежат в mp3, и каждый такой голос обходится ощутимо дороже, чем wav/ogg
	"sword_attack": {"voices": 6, "gap": 0.035, "db": -8.0},
	"sword_hit":    {"voices": 6, "gap": 0.045, "db": -4.0},
	"spear_hit":    {"voices": 6, "gap": 0.04,  "db": -6.0},
	# Голоса — редкая приправа поверх гула, их лимиты почти не тронуты
	"vox_action":   {"voices": 3, "gap": 0.90,  "db": -8.0},
	"vox_death":    {"voices": 4, "gap": 0.20,  "db": -3.0},
	"metal_punch":  {"voices": 3, "gap": 0.15,  "db": -7.0},
	# ── БОЕВОЙ КЛИЧ: ЕДИНСТВЕННАЯ КАТЕГОРИЯ С НУЛЕВОЙ ПАУЗОЙ ────────────────
	# gap здесь именно 0, и это не небрежность. Пауза в этой таблице —
	# ОБЩЕКАТЕГОРИЙНАЯ: play_3d отбрасывает звук, если с прошлого запуска той же
	# категории прошло меньше gap секунд. Для стука топоров это спасение от
	# метронома, а для клича — прямая помеха: заказан «многоголосый хор», то
	# есть по кличу от КАЖДОГО отряда в один момент, а любая ненулевая пауза
	# оставила бы ровно один голос — первого успевшего.
	# Хор ограничивается не паузой, а числом голосов: шесть отрядов звучат
	# одновременно, седьмой и дальше молча пропускаются, и пул (POOL_SIZE = 28)
	# не съедается кличем целиком в ущерб самому бою.
	# Частота при этом ограничена на уровне отряда (GameManager.CRY_COOLDOWN_MS)
	# pitch шире обычного (см. DEFAULT_PITCH_RANGE): это единственная категория,
	# где ОДИН И ТОТ ЖЕ файл штатно звучит несколькими голосами разом
	"battle_cry":   {"voices": 6, "gap": 0.0,   "db": -4.0, "pitch": [0.92, 1.08]},
}

## Расстройка высоты по умолчанию. Узкая: у остальных категорий по нескольку
## сэмплов, и главное расхождение даёт уже выбор файла, а не питч
const DEFAULT_PITCH_RANGE := [0.94, 1.06]

# ─────────────────────────────────────────────────────────────────────────────
# ДАЛЬНОСТЬ БОЕВОГО ЗВУКА
#
# ПОЧЕМУ ЗВУК ПРОПАДАЛ ОТ МАЛЕЙШЕГО СДВИГА КАМЕРЫ. Слышимость обрывалась на
# 42 метрах, а кадр на максимальном отдалении покрывает 110 метров по вертикали
# и около 195 по горизонтали. То есть бой, который игрок ВИДИТ на краю экрана,
# заведомо лежал за порогом слышимости: подвинул камеру на пару метров — и
# сражение то замолкает целиком, то возвращается. Это не спад громкости, а
# именно обрыв: play_3d отбрасывал такой звук ещё до пула голосов.
#
# Теперь порог накрывает ВЕСЬ видимый кадр с запасом, а спад сделан пологим.
# ─────────────────────────────────────────────────────────────────────────────
## Всего одновременных 3D-голосов. Потолок против перегруза динамиков.
## Поднят с 24: в свалке на 600 бойцов пул из двух десятков разбирался первыми
## же ударами, и вся остальная канонада молчала
const POOL_SIZE := 28
## Дальше этого звук не слышно вовсе. 120 м покрывают ВЕСЬ видимый кадр
## (максимальная видимая высота — RTSCamera.max_height = 110 м) с запасом,
## но остаются меньше полукарты (Main.MAP_HALF_X = 130): слышать сражение
## через весь мир по-прежнему нельзя
const SFX_MAX_DISTANCE := 120.0
## Радиус «ближнего поля», внутри которого громкость почти не падает.
## Поднят с 8 до 20 м вместе с порогом слышимости: их отношение и задаёт форму
## спада. При прежней паре 8/42 громкость в центре кадра и у его края
## отличалась в разы, и панорама камеры слышалась как рывок
const SFX_UNIT_SIZE := 20.0
## ЖЁСТКАЯ ОТСЕЧКА ДО ПУЛА совпадает с порогом слышимости — и это правильно:
## при квадратичном спаде на границе остаётся約 3% громкости, то есть звук там
## и так неразличим. Отсекать ДАЛЬШЕ границы значит жечь голоса пула на то,
## чего всё равно не слышно
const SFX_CULL_DISTANCE := SFX_MAX_DISTANCE

# ── МУЗЫКАЛЬНЫЙ АВТО-ТАЙМЕР ──────────────────────────────────────────────────
## Раз во столько секунд поверх леса тихо поднимается основная тема
const MUSIC_INTERVAL := 600.0     # 10 минут
## Сколько секунд длится плавное появление и затухание темы
const MUSIC_FADE := 6.0
## Насколько тише эмбиента играет подмешанная тема
const MUSIC_UNDER_DB := -14.0
## Громкость темы в меню
const MUSIC_MENU_DB := -6.0
const AMBIENCE_DB := -10.0

const SETTINGS_PATH := "user://audio_settings.cfg"

# ── СОСТОЯНИЕ ────────────────────────────────────────────────────────────────
var _pool: Array = []                  # AudioStreamPlayer3D
var _pool_cat: Array = []              # категория, занятая каждым голосом
var _cat_last: Dictionary = {}         # категория → время последнего запуска
var _streams: Dictionary = {}          # путь → AudioStream (кэш загрузки)
var _music: AudioStreamPlayer = null   # тема (меню и подмешивание)
var _ambience: AudioStreamPlayer = null# лес
var _music_timer: float = 0.0
var _fade: float = 0.0                 # 0..1 текущая громкость подмешанной темы
var _fade_dir: float = 0.0             # +1 нарастание, -1 затухание, 0 покой
var _in_game: bool = false
var _volumes: Dictionary = {"Master": 1.0, "Music": 0.8, "SFX": 0.9}
## Звук вообще возможен? В headless аудио-драйвер пустой, и это НЕ ошибка
var enabled: bool = true

## СЧЁТЧИКИ ДЛЯ СТЕНДОВ. Без них не измерить главное свойство ограничителя —
## какую долю событий он отсекает в свалке. Стоят два инкремента на вызов
var sfx_calls: int = 0     # сколько раз вообще попросили звук
var sfx_played: int = 0    # сколько раз звук реально пошёл в пул

func reset_sfx_stats() -> void:
	sfx_calls = 0
	sfx_played = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # громкость крутится и на паузе
	_ensure_buses()
	_load_settings()
	_build_pool()
	_preload_sfx()
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Music"
	add_child(_ambience)

# ── ШИНЫ И ГРОМКОСТЬ ─────────────────────────────────────────────────────────

func _ensure_buses() -> void:
	for nm in ["Music", "SFX"]:
		var bus_name: String = nm
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

## Громкость шины в долях 0..1. 0 = полная тишина (а не -80 дБ «почти тихо»)
func set_bus_volume(bus_name: String, linear: float) -> void:
	var v: float = clampf(linear, 0.0, 1.0)
	_volumes[bus_name] = v
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))

func get_bus_volume(bus_name: String) -> float:
	return float(_volumes.get(bus_name, 1.0))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _volumes:
		cfg.set_value("audio", String(key), float(_volumes[key]))
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for key in _volumes.keys():
			var k: String = String(key)
			_volumes[k] = float(cfg.get_value("audio", k, _volumes[k]))
	for key in _volumes.keys():
		set_bus_volume(String(key), float(_volumes[key]))

# ── ПУЛ 3D-ГОЛОСОВ ───────────────────────────────────────────────────────────

func _build_pool() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = SFX_MAX_DISTANCE
		p.unit_size = SFX_UNIT_SIZE
		# Спад по обратному квадрату: вблизи громко, у самой границы —
		# около 3% громкости, то есть фактически тишина. Именно поэтому обрыв
		# на max_distance не слышен и отсекать что-то ДАЛЬШЕ границы не нужно.
		#
		# ФОРМУ СПАДА ЗАДАЁТ ОТНОШЕНИЕ unit_size / max_distance, а не сами
		# числа: пара 20/120 даёт ровно ту же кривую, что и прежняя 8/42, —
		# просто растянутую на весь видимый кадр. Плавность панорамы взялась
		# именно отсюда, а не от смены модели спада
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		# ВОЗВРАТ ГОЛОСА В ПУЛ ПО СОБЫТИЮ. Раньше свободный голос искали
		# перебором всего пула на каждый звук; теперь доигравший сам встаёт
		# в очередь свободных (см. _take_voice)
		p.finished.connect(_on_voice_finished.bind(i))
		add_child(p)
		_pool.append(p)
		_pool_cat.append("")
		_free_voices.append(i)

## ── УЧЁТ ГОЛОСОВ ЗА O(1) ────────────────────────────────────────────────────
## Раньше каждый звук перебирал ВЕСЬ пул: считал занятые своей категорией и
## искал первую свободную ячейку. С расширением радиуса слышимости до размеров
## кадра до пула стало доходить втрое больше событий, и этот перебор из мелочи
## превратился в заметную статью расхода кадра (замер qa_audio2, раздел C).
## Теперь свободные ячейки лежат стопкой, а занятость по категориям — счётчиком:
## выдача и возврат голоса стоят одинаково дёшево при любом размере пула.
var _free_voices: Array = []      # индексы свободных ячеек пула
var _cat_busy: Dictionary = {}    # категория → сколько её голосов сейчас играет

func _on_voice_finished(idx: int) -> void:
	var cat: String = String(_pool_cat[idx])
	if cat != "":
		_cat_busy[cat] = maxi(0, int(_cat_busy.get(cat, 0)) - 1)
		_pool_cat[idx] = ""
	if not (idx in _free_voices):
		_free_voices.append(idx)

## Свободный голос или null (пул исчерпан либо категория выбрала свой лимит)
func _take_voice(cat: String, limit: int) -> AudioStreamPlayer3D:
	if int(_cat_busy.get(cat, 0)) >= limit:
		return null
	if _free_voices.is_empty():
		# Стопка пуста — возможно, часть голосов доиграла, но сигнал ещё не
		# дошёл (или его и не будет: голос остановили извне). Пересобираем
		# учёт прямо здесь. Это тот же полный перебор, что делала прежняя
		# версия НА КАЖДЫЙ звук, — только теперь он случается лишь при
		# исчерпании пула, то есть в разы реже
		_sweep_voices()
		if _free_voices.is_empty():
			return null
	var idx: int = _free_voices.pop_back()
	_pool_cat[idx] = cat
	_cat_busy[cat] = int(_cat_busy.get(cat, 0)) + 1
	return _pool[idx]

## Слушатель ищется через вьюпорт (его назначает Main, см. AudioListener3D)
## и кэшируется: спрашивать движок на каждом ударе в свалке дорого
var _listener: Node3D = null

func _listener_node() -> Node3D:
	if is_instance_valid(_listener):
		return _listener
	_listener = null
	var vp := get_viewport()
	if vp != null:
		# Через call(): имя метода вьюпорта не должно ронять компиляцию,
		# если движок соберут без 3D-звука
		var n = vp.call("get_audio_listener_3d")
		_listener = n as Node3D
	return _listener

## ── ПРЕДЗАГРУЗКА БАНКА ЭФФЕКТОВ ─────────────────────────────────────────────
## Файл эффекта грузился ЛЕНИВО — при первом обращении к нему. Обращение это
## случается в разгар первой же стычки, а выбор файла из категории случайный,
## поэтому разовые загрузки размазывались по первым секундам боя и давали
## заметный рывок кадра (замер qa_audio2, раздел C: первый круг стабильно
## в разы дороже последующих).
##
## Банк маленький — три десятка коротких сэмплов, — и грузить его целиком
## на старте дешевле, чем ловить эти рывки в бою.
func _preload_sfx() -> void:
	for cat in SFX_BANK:
		for f in SFX_BANK[cat]:
			_stream(DIR_SFX + String(f))

func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		_streams[path] = null
		return null
	var s := load(path) as AudioStream
	_streams[path] = s
	return s

## ГЛАВНЫЙ ВХОД ДЛЯ БОЕВЫХ И РАБОЧИХ ЗВУКОВ.
## Возвращает true, если звук реально запущен (false — отсекло ограничителем)
## ── АДАПТИВНАЯ ПЛОТНОСТЬ ЗВУКОВ РАБОТЫ ──────────────────────────────────────
## Пятеро рабочих должны звучать КАЖДЫМ ударом — по стуку топоров игрок слышит,
## что база живёт. Сорок рабочих тем же способом превращаются в白 шум и
## перегружают канал. Поэтому доля пропускаемых ударов падает с ростом числа
## работающих: до WORK_DENSITY_FULL слышно всё, к WORK_DENSITY_HALF остаётся
## половина, дальше — не меньше WORK_DENSITY_FLOOR.
## Категории, к которым это применяется (звуки инструмента):
const WORK_CATS := {"chop": true, "mine_gold": true, "mine_stone": true}
const WORK_DENSITY_FULL  := 6      # столько работяг слышно полностью
const WORK_DENSITY_HALF  := 36     # при стольких остаётся половина ударов
const WORK_DENSITY_FLOOR := 0.35   # ниже этой доли не опускаемся

## Сколько рабочих сейчас реально стучат. Считает Worker раз в полсекунды,
## а не AudioManager перебором группы на каждый удар
var active_workers: int = 0

## Доля ударов, которую сейчас пропускаем в динамики
func work_density() -> float:
	if active_workers <= WORK_DENSITY_FULL:
		return 1.0
	var t: float = float(active_workers - WORK_DENSITY_FULL) \
		/ float(maxi(WORK_DENSITY_HALF - WORK_DENSITY_FULL, 1))
	return maxf(lerpf(1.0, 0.5, minf(t, 1.0)) - maxf(t - 1.0, 0.0) * 0.15,
		WORK_DENSITY_FLOOR)

func play_3d(cat: String, at: Vector3) -> bool:
	sfx_calls += 1
	if not enabled:
		return false
	var files: Array = SFX_BANK.get(cat, [])
	if files.is_empty():
		return false
	# ПРОРЕЖИВАНИЕ ПО ПЛОТНОСТИ — до ограничителя голосов: смысл не в том,
	# чтобы занять меньше голосов, а в том, чтобы сорок топоров не били в ухо
	# одновременно. Решение случайное на каждый удар, поэтому стук остаётся
	# живым и рваным, а не превращается в метроном из каждого N-го рабочего
	if WORK_CATS.has(cat) and randf() > work_density():
		return false
	# ДАЛЬНИЙ ЗВУК ОТСЕКАЕТСЯ ДО ПУЛА. Голосов всего POOL_SIZE, а слышно только
	# в радиусе SFX_MAX_DISTANCE. Без этой отсечки свалка на другом конце карты
	# разбирает весь пул себе, и бой ПОД КАМЕРОЙ замолкает — при том, что
	# дальние голоса всё равно звучат в пустоту. Если слушателя нет (меню,
	# стенды без сцены) — не отсекаем ничего
	var lis: Node3D = _listener_node()
	if lis != null and lis.global_position.distance_squared_to(at) \
			> SFX_CULL_DISTANCE * SFX_CULL_DISTANCE:
		return false
	var lim: Dictionary = SFX_LIMITS.get(cat, {})
	var gap: float = float(lim.get("gap", 0.1))
	var now: float = float(Time.get_ticks_msec()) * 0.001
	var last: float = float(_cat_last.get(cat, -999.0))
	if now - last < gap:
		return false
	# ПОТОК РАЗБИРАЕТСЯ ДО ГОЛОСА, А НЕ ПОСЛЕ.
	# Раньше голос сначала забирали из пула и только потом проверяли, нашёлся ли
	# файл. Пока свободную ячейку искали перебором «кто не играет», это сходило
	# с рук: неиспользованный голос тут же считался свободным снова. С учётом
	# занятости по счётчику (см. _take_voice) такой выход УТЕКАЛ БЫ: ячейка
	# помечена занятой, play() на ней не звали, сигнал finished не придёт —
	# и категория навсегда теряет по голосу на каждый пропавший файл.
	# Порядок «сначала поток, потом голос» снимает вопрос целиком.
	var fname: String = String(files[randi() % files.size()])
	var s: AudioStream = _stream(DIR_SFX + fname)
	if s == null:
		return false
	var voice: AudioStreamPlayer3D = _take_voice(cat, int(lim.get("voices", 3)))
	if voice == null:
		return false
	_cat_last[cat] = now
	voice.stream = s
	voice.global_position = at
	voice.volume_db = float(lim.get("db", -6.0))
	# ── РАССТРОЙКА ВЫСОТЫ: ГЛАВНОЕ ЛЕКАРСТВО ОТ «РОБОТА» ────────────────────
	# Один и тот же сэмпл, запущенный несколькими голосами секунда в секунду,
	# складывается сам с собой и даёт гребенчатую фильтрацию — тот самый
	# «электронный» призвук. Разная высота у каждого голоса разводит волны по
	# частоте, и наложение перестаёт быть когерентным.
	#
	# Диапазон берётся ИЗ КАТЕГОРИИ: у боевого клича он шире обычного, потому
	# что клич — единственный звук, который штатно запускается несколькими
	# голосами ОДНОВРЕМЕННО и одним файлом (у прочих категорий сэмплов по
	# нескольку, и они расходятся уже выбором файла).
	# Ставится БЕЗУСЛОВНО на каждый запуск: голоса переиспользуются из пула, и
	# без явной записи следующий звук унаследовал бы чужую расстройку
	var pr: Array = lim.get("pitch", DEFAULT_PITCH_RANGE)
	voice.pitch_scale = randf_range(float(pr[0]), float(pr[1]))
	voice.play()
	sfx_played += 1
	return true

# ── МУЗЫКА И ЭМБИЕНТ ─────────────────────────────────────────────────────────

## Экран выбора расы: играет основная тема
func play_menu_music() -> void:
	if not enabled:
		return
	_in_game = false
	_fade = 0.0
	_fade_dir = 0.0
	_ambience.stop()
	var s: AudioStream = _stream(MUSIC_BACKGROUND)
	if s == null:
		return
	_loop(s)
	_music.stream = s
	_music.volume_db = MUSIC_MENU_DB
	_music.play()

## Старт партии: постоянный лес + таймер подмешивания темы
func start_game_audio() -> void:
	if not enabled:
		return
	_in_game = true
	_music_timer = MUSIC_INTERVAL
	_fade = 0.0
	_fade_dir = 0.0
	_music.stop()
	var s: AudioStream = _stream(AMBIENCE_FOREST)
	if s == null:
		return
	_loop(s)
	_ambience.stream = s
	_ambience.volume_db = AMBIENCE_DB
	_ambience.play()

func stop_all_music() -> void:
	_in_game = false
	_fade_dir = 0.0
	_music.stop()
	_ambience.stop()

# ── ПАУЗА ────────────────────────────────────────────────────────────────────
# Автозагрузка работает в PROCESS_MODE_ALWAYS (иначе на паузе не покрутить
# громкость в меню настроек), поэтому «поставить дерево на паузу» её звук НЕ
# трогает: музыка и лес продолжали играть над замершей картинкой, а начатые
# 3D-голоса — договаривать свои удары. По заказу владельца пауза обязана быть
# и звуковой.
#
# Способ — stream_paused, а не stop/mute:
#   • stop() потерял бы позицию в треке, и после «Продолжить» лес начинался бы
#     заново с первой секунды;
#   • глушение шины оставило бы потоки БЕЖАТЬ молча — снятая пауза попадала бы
#     в середину уже отзвучавшего куска.
# 3D-голоса ставятся на паузу тем же полем, поштучно: их не больше POOL_SIZE.
var _audio_paused: bool = false

## Пауза/продолжение всего звука. Идемпотентна: повторный вызов с тем же
## значением ничего не делает
func set_paused(on: bool) -> void:
	if _audio_paused == on:
		return
	_audio_paused = on
	if _music != null and is_instance_valid(_music):
		_music.stream_paused = on
	if _ambience != null and is_instance_valid(_ambience):
		_ambience.stream_paused = on
	for p in _pool:
		var v: AudioStreamPlayer3D = p
		if v != null and is_instance_valid(v):
			v.stream_paused = on

func is_paused() -> bool:
	return _audio_paused

## Зациклить поток независимо от формата (ogg/mp3/wav — у всех свой флаг)
func _loop(s: AudioStream) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

## ПОДСТРАХОВКА УЧЁТА ГОЛОСОВ. Возврат в пул идёт по сигналу finished, а его
## можно и не дождаться: голос остановили извне, сцену перезапустили, поток
## оказался зациклённым. Раз в секунду сверяем стопку свободных с реальностью —
## иначе одна потерянная ячейка навсегда сужает пул
const VOICE_SWEEP_SEC := 1.0
var _sweep_timer: float = 0.0

func _sweep_voices() -> void:
	_free_voices.clear()
	_cat_busy.clear()
	for i in range(_pool.size()):
		var p: AudioStreamPlayer3D = _pool[i]
		if p.playing:
			var cat: String = String(_pool_cat[i])
			if cat != "":
				_cat_busy[cat] = int(_cat_busy.get(cat, 0)) + 1
		else:
			_pool_cat[i] = ""
			_free_voices.append(i)

func _process(delta: float) -> void:
	# На звуковой паузе крутить нечего: голоса заморожены, а таймер подмешивания
	# темы не должен «пройти» мимо игрока, пока тот стоит на паузе
	if _audio_paused:
		return
	_sweep_timer -= delta
	if _sweep_timer <= 0.0:
		_sweep_timer = VOICE_SWEEP_SEC
		_sweep_voices()
	if not _in_game or not enabled:
		return
	# ТАЙМЕР ПОДМЕШИВАНИЯ. Раз в MUSIC_INTERVAL тема плавно поднимается поверх
	# леса, играет до конца трека и так же плавно уходит
	if _fade_dir == 0.0 and not _music.playing:
		_music_timer -= delta
		if _music_timer <= 0.0:
			_start_music_swell()
	elif _fade_dir > 0.0:
		_fade = minf(_fade + delta / MUSIC_FADE, 1.0)
		_apply_fade()
		if _fade >= 1.0:
			_fade_dir = 0.0
	elif _fade_dir < 0.0:
		_fade = maxf(_fade - delta / MUSIC_FADE, 0.0)
		_apply_fade()
		if _fade <= 0.0:
			_fade_dir = 0.0
			_music.stop()
			_music_timer = MUSIC_INTERVAL
	# Трек доиграл почти до конца — начинаем затухание
	if _music.playing and _fade_dir >= 0.0 and _music.stream != null:
		var left: float = _music.stream.get_length() - _music.get_playback_position()
		if left <= MUSIC_FADE:
			_fade_dir = -1.0

func _start_music_swell() -> void:
	var s: AudioStream = _stream(MUSIC_BACKGROUND)
	if s == null:
		_music_timer = MUSIC_INTERVAL
		return
	_music.stream = s
	_fade = 0.0
	_fade_dir = 1.0
	_apply_fade()
	_music.play()

func _apply_fade() -> void:
	# Тише эмбиента: тема подмешивается фоном, а не забивает лес
	_music.volume_db = MUSIC_UNDER_DB + linear_to_db(maxf(_fade, 0.0001))

## Сколько секунд осталось до следующего подмешивания (для стендов)
func seconds_to_music() -> float:
	return _music_timer

## Форсировать подмешивание прямо сейчас (для стендов)
func force_music_swell() -> void:
	if _in_game:
		_start_music_swell()
