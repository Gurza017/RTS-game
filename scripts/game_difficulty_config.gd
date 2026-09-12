extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## СЛОЖНОСТЬ ПАРТИИ: ЛЁГКАЯ / ОБЫЧНАЯ / ТЯЖЁЛАЯ
## ═══════════════════════════════════════════════════════════════════════════
## ЕДИНСТВЕННЫЙ файл, который нужно править, чтобы поменять разницу между
## уровнями сложности. Правит владелец, как unit_stats_config.gd и
## ai_start_army_limit.gd; стенды обязаны читать числа отсюда, а не хардкодить.
##
## Файл намеренно без class_name (как остальные конфиги) — подключается через
## preload, поэтому не зависит от кэша глобальных классов Godot.
## Подключение: const _Diff := preload("res://scripts/game_difficulty_config.gd")
##
## ── ЧТО ЗДЕСЬ НЕ ЛЕЖИТ И ПОЧЕМУ ────────────────────────────────────────────
## ЗДЕСЬ НЕТ НИ ОДНОГО БАЗОВОГО ЧИСЛА. Пресет описан МНОЖИТЕЛЯМИ и ЗАМЕНАМИ
## поверх базовых таблиц (ai_start_army_limit, goblin_config,
## unit_stats_config), а не своей копией баланса. Копия неизбежно разъехалась
## бы: владелец правит лимит в ai_start_army_limit, а на «обычной» сложности
## ничего не меняется, потому что там лежит вторая, забытая цифра.
##
## Отсюда правило чтения: НИКТО не читает PRESETS напрямую. Все спрашивают
## функции внизу файла — они принимают базовое значение и возвращают
## изменённое. На «обычной» сложности они возвращают базу БЕЗ ИЗМЕНЕНИЙ
## (все множители = 1.0), то есть выбор Normal обязан быть полностью
## эквивалентен прежней игре без сложностей — это стережёт qa_difficulty.
##
## ── ЧТО ИМЕННО КРУТИТСЯ ────────────────────────────────────────────────────
## Сложность в RTS — это НЕ читы по урону. Ни одна ручка ниже не трогает силу
## удара, запас жизни и броню: боец на Hard дерётся ровно так же, как на Easy.
## Крутятся ТОЛЬКО ЛИМИТЫ И ТЕМП — сколько противник может накопить и как
## быстро он это делает. Тогда «сложнее» означает «больше и раньше», а не
## «у врага другие правила», и любой замер боя остаётся сравнимым.

const _AICfg  := preload("res://scripts/ai_start_army_limit.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _UCfg   := preload("res://scripts/unit_stats_config.gd")

## Идентификаторы уровней. Строки, а не числа: они уходят в файл настроек и
## в сохранение партии, где число «1» через полгода никто не расшифрует
const EASY   := "easy"
const NORMAL := "normal"
const HARD   := "hard"

## Порядок в меню — он же порядок кнопок
const ORDER := [EASY, NORMAL, HARD]

## С чего начинается новая установка игры
const DEFAULT := NORMAL

## ═══════════════════════════════════════════════════════════════════════════
## ПРЕСЕТЫ
## ═══════════════════════════════════════════════════════════════════════════
## ПОЛЯ ЗАПИСИ (любое можно опустить — тогда берётся нейтральное значение,
## то есть множитель 1.0 / пустой список):
##
##   name                — подпись на кнопке в меню
##   hint                — строка под кнопкой: что игрок получит
##
##   ── КРАСНЫЙ ИИ (Constants.FACTION_ENEMY) ──────────────────────────────
##   ai_squad_mult       — множитель ЛИМИТА ОТРЯДОВ каждого рода войск
##                         (ai_start_army_limit.SQUAD_LIMIT). Это и есть
##                         главная ручка масштаба: 0.6 — вдвое меньшая армия
##                         под конец партии, 1.4 — заметно больше
##   ai_worker_mult      — множитель потолка рабочих (WORKER_LIMIT): чем больше
##                         рабочих, тем быстрее ИИ выходит на свой лимит армии
##   ai_resource_mult    — множитель СТАРТОВОГО запаса ИИ
##                         (unit_stats_config.AI_STARTING_RESOURCES)
##   ai_train_mult       — множитель ВРЕМЕНИ найма отряда: 0.8 — на 20% быстрее.
##                         Меньше единицы = быстрее, это множитель ВРЕМЕНИ,
##                         а не темпа. Игрока не касается вовсе
##   ai_build_mult       — то же для ВРЕМЕНИ отстройки зданий ИИ
##   ai_peace_mult       — множитель мирной фазы (AICfg.PEACE_SECONDS): на Hard
##                         ИИ начинает воевать раньше
##   ai_start_squads     — СТАРТОВЫЕ ОТРЯДЫ ИИ. Непустой список ЗАМЕНЯЕТ
##                         ai_start_army_limit.START_SQUADS целиком. Формат
##                         строки тот же: {"unit", "count", "vet", "picks"}
##
##   ── ОРДА ГОБЛИНОВ (Constants.FACTION_GOBLIN) ──────────────────────────
##   goblin_dormant_mult — множитель МИРНОЙ ФАЗЫ орды (goblin_config.PEACE_SEC,
##                         спринт 17; спячки DORMANT_UNTIL_SEC больше нет — 0):
##                         на Easy орда выходит к центру позже, на Hard — раньше
##   goblin_food_mult    — множитель дохода хижины (HUT_FOOD_PER_MIN), то есть
##                         темпа, с которым орда восполняет потери
##   goblin_vet_shift    — СДВИГ РАНГА стартовых отрядов орды: +1 поднимает
##                         ранг каждому, у кого он есть, −1 опускает. Отряды с
##                         рангом 0 (новобранцы) не трогаются НИКОГДА: иначе на
##                         Hard вся орда вышла бы ветеранской, а это уже другой
##                         сценарий, а не сложность
const PRESETS := {
	EASY: {
		"name": "Лёгкая",
		"hint": "Противник копит вдвое меньшую армию и позже идёт в бой",
		# ── красный ИИ ──────────────────────────────────────────────────────
		"ai_squad_mult":    0.55,   # армия ИИ примерно вдвое меньше обычной
		"ai_worker_mult":   0.70,   # экономика слабее — лимит набирается дольше
		"ai_resource_mult": 0.75,   # стартовый запас урезан на четверть
		"ai_train_mult":    1.30,   # найм отряда на 30% дольше
		"ai_build_mult":    1.30,   # стройка на 30% дольше
		"ai_peace_mult":    1.50,   # мирная фаза в полтора раза длиннее
		"ai_start_squads":  [],     # стартовых войск нет (как и в базе)
		# ── орда ────────────────────────────────────────────────────────────
		"goblin_dormant_mult": 1.35,  # орда просыпается позже
		"goblin_food_mult":    0.70,  # и медленнее восполняет потери
		"goblin_vet_shift":   -1,     # ранг стартовых отрядов на ступень ниже
	},
	NORMAL: {
		"name": "Обычная",
		"hint": "Баланс из таблиц: плотный бой к середине партии",
		# ВСЕ РУЧКИ НЕЙТРАЛЬНЫ. Это не заглушка «на потом»: Normal обязан быть
		# в точности прежней игрой, иначе появление сложностей молча сдвинуло
		# бы весь баланс, который владелец настраивал без них
		"ai_squad_mult":    1.0,
		"ai_worker_mult":   1.0,
		"ai_resource_mult": 1.0,
		"ai_train_mult":    1.0,
		"ai_build_mult":    1.0,
		"ai_peace_mult":    1.0,
		"ai_start_squads":  [],
		"goblin_dormant_mult": 1.0,
		"goblin_food_mult":    1.0,
		"goblin_vet_shift":    0,
	},
	HARD: {
		"name": "Тяжёлая",
		"hint": "Противник выходит с гарнизоном, копит больше и давит раньше",
		# ── красный ИИ ──────────────────────────────────────────────────────
		"ai_squad_mult":    1.40,   # армия в полтора раза больше обычной
		"ai_worker_mult":   1.35,   # и набирается она быстрее
		"ai_resource_mult": 1.60,   # фора по стартовому запасу
		"ai_train_mult":    0.80,   # найм на 20% быстрее
		"ai_build_mult":    0.80,   # стройка на 20% быстрее
		"ai_peace_mult":    0.60,   # мирная фаза короче почти вдвое
		# СТАРТОВЫЙ ГАРНИЗОН. Ровно то, ради чего в ai_start_army_limit заведена
		# START_SQUADS: без него «сложнее» означало бы только «дольше ждать»,
		# потому что первые минуты партии у ИИ всё равно пусто
		"ai_start_squads": [
			{"unit": "spearman", "count": 0, "vet": 2, "picks": 2},
			{"unit": "spearman", "count": 0, "vet": 1, "picks": 1},
			{"unit": "archer",   "count": 0, "vet": 1, "picks": 1},
		],
		# ── орда ────────────────────────────────────────────────────────────
		"goblin_dormant_mult": 0.65,  # орда просыпается заметно раньше
		"goblin_food_mult":    1.40,  # и быстрее восполняет потери
		"goblin_vet_shift":    1,     # ранг стартовых отрядов на ступень выше
	},
}

# ═════════════════════════════════════════════════════════════════════════════
# ТЕКУЩИЙ ВЫБОР
# ═════════════════════════════════════════════════════════════════════════════
## ХРАНИТСЯ СТАТИЧЕСКИ, А НЕ В GameManager, и это осознанно: сложность нужна
## ДО того, как автозагрузка успевает что-либо решить (главное меню строится
## первым), и нужна она конфигам — а конфиг, лезущий в автозагрузку за
## значением, тянет за собой всё дерево зависимостей движка в стенд, который
## его и не поднимал. Статика переживает смену сцены: скрипт держится в памяти
## preload'ами и никуда не выгружается.
static var _current: String = DEFAULT

## Куда пишется выбор, чтобы пережить перезапуск игры. Файл крошечный и
## отдельный от аудио-настроек: у них разная судьба при сбросе настроек
const SETTINGS_PATH := "user://difficulty.cfg"

## Текущий уровень сложности. Всегда возвращает ЗНАКОМЫЙ ключ: битый файл
## настроек или опечатка схлопываются в DEFAULT, а не оставляют игру без правил
static func current() -> String:
	return _current if PRESETS.has(_current) else DEFAULT

## Сменить сложность. Действует со следующей НОВОЙ ПАРТИИ: лимиты читаются
## вживую, а стартовые ресурсы и стартовые отряды раздаются один раз при старте
static func set_current(id: String) -> void:
	_current = id if PRESETS.has(id) else DEFAULT

## Запись текущего пресета целиком (нужна меню для подписи и подсказки)
static func preset() -> Dictionary:
	return PRESETS.get(current(), PRESETS[DEFAULT]) as Dictionary

## Подпись уровня сложности для интерфейса
static func label(id: String = "") -> String:
	var key: String = id if PRESETS.has(id) else current()
	return String((PRESETS[key] as Dictionary).get("name", key))

## Строка-подсказка под кнопкой выбора
static func hint(id: String = "") -> String:
	var key: String = id if PRESETS.has(id) else current()
	return String((PRESETS[key] as Dictionary).get("hint", ""))

## Одно поле текущего пресета с нейтральным значением по умолчанию
static func _f(key: String, neutral: float = 1.0) -> float:
	return float(preset().get(key, neutral))

# ═════════════════════════════════════════════════════════════════════════════
# РУЧКИ: базовое значение на входе, изменённое на выходе
# ═════════════════════════════════════════════════════════════════════════════
# ВСЕ ФУНКЦИИ НИЖЕ БЕРУТ БАЗУ АРГУМЕНТОМ. Ни одна не знает базовых чисел сама —
# это и есть гарантия, что правка ai_start_army_limit или goblin_config
# доезжает до всех трёх сложностей разом.

## Лимит отрядов данного рода войск с учётом сложности.
## Округление ВВЕРХ и пол в единицу: на Easy при множителе 0.55 лимит лучников
## (5) даёт 2.75 — округли вниз, и получилось бы 2, а строку конфига «лучники
## нужны» это молча превратило бы в «почти не нужны»
static func ai_squad_limit(unit_id: String) -> int:
	var base: int = _AICfg.squad_limit(unit_id)
	if base <= 0:
		return 0      # род войск выключен в базе — сложность его не включает
	return maxi(int(ceil(float(base) * _f("ai_squad_mult"))), 1)

## Полный лимит армии ИИ В ОТРЯДАХ (по нему он решает, что пора в атаку)
static func ai_total_squad_limit() -> int:
	var total := 0
	for uid in _AICfg.combat_types():
		total += ai_squad_limit(String(uid))
	return total

## Полный лимит армии ИИ В БОЙЦАХ. Нужен решению об отвоевании центра: отряды
## у разных родов войск разного размера, и считать долю по отрядам нельзя
static func ai_total_army_cap() -> int:
	var cap := 0
	for uid in _AICfg.combat_types():
		cap += ai_squad_limit(String(uid)) * _UCfg.squad_size(String(uid))
	return cap

## Потолок рабочих ИИ
static func ai_worker_limit() -> int:
	return maxi(int(round(float(_AICfg.WORKER_LIMIT) * _f("ai_worker_mult"))), 1)

## Длительность мирной фазы ИИ, секунд
static func ai_peace_seconds() -> float:
	return maxf(_AICfg.PEACE_SECONDS * _f("ai_peace_mult"), 0.0)

## Стартовый запас ресурсов фракции с учётом сложности.
## ИГРОКА НЕ КАСАЕТСЯ ВОВСЕ: сложность меняет противника, а не правила игрока —
## иначе «лёгкая» превратилась бы в «дать игроку денег», и сравнить две партии
## между собой стало бы нельзя
static func starting_resources(faction: int, base: Dictionary) -> Dictionary:
	if faction != Constants.FACTION_ENEMY:
		return base
	var m: float = _f("ai_resource_mult")
	if is_equal_approx(m, 1.0):
		return base
	var out: Dictionary = {}
	for k in base:
		out[k] = float(base[k]) * m
	return out

## Время найма ОДНОГО отряда с учётом сложности, секунд.
## Пол в 0.5 с обязателен: множитель правит владелец, и ноль здесь означал бы
## отряд, выходящий в тот же кадр, — то есть очередь найма без очереди
static func train_time(faction: int, base: float) -> float:
	if faction != Constants.FACTION_ENEMY:
		return base
	return maxf(base * _f("ai_train_mult"), 0.5)

## Время отстройки здания с учётом сложности, секунд
static func build_time(faction: int, base: float) -> float:
	if faction != Constants.FACTION_ENEMY:
		return base
	return maxf(base * _f("ai_build_mult"), 0.5)

## Стартовые отряды ИИ: список пресета, если он непуст, иначе базовая таблица.
## ЗАМЕНА, А НЕ ДОБАВКА: «Hard добавляет отряды к тем, что в базе» означало бы,
## что стоит владельцу вписать гарнизон в ai_start_army_limit — и на Hard он
## удвоится. Заменой пресет остаётся предсказуемым
static func ai_start_squads() -> Array:
	var over: Array = preset().get("ai_start_squads", []) as Array
	if over.is_empty():
		return _AICfg.start_squads()
	var out: Array = []
	for row in over:
		var d: Dictionary = row
		var uid: String = String(d.get("unit", ""))
		if uid.is_empty() or not _UCfg.STATS.has(uid):
			continue
		var n: int = int(d.get("count", 0))
		if n <= 0:
			n = _UCfg.squad_size(uid)
		out.append({
			"unit":  uid,
			"count": maxi(n, 1),
			"vet":   maxi(int(d.get("vet", 0)), 0),
			"picks": maxi(int(d.get("picks", 0)), 0),
		})
	return out

## Срок спячки орды, секунд от начала партии (спринт 17: спячки нет, 0)
static func goblin_dormant_sec() -> float:
	return maxf(_GobCfg.DORMANT_UNTIL_SEC * _f("goblin_dormant_mult"), 0.0)

## Мирная фаза орды (отстройка и патруль границ), секунд от начала партии:
## тот же множитель сложности, что прежде крутил спячку
static func goblin_peace_sec() -> float:
	return maxf(_GobCfg.PEACE_SEC * _f("goblin_dormant_mult"), 0.0)

## Доход одной хижины, еды в минуту
static func goblin_hut_food_per_min() -> float:
	return maxf(_GobCfg.HUT_FOOD_PER_MIN * _f("goblin_food_mult"), 0.0)

## Стартовая орда со сдвинутым рангом. Отряды-новобранцы (vet = 0) не трогаются:
## сложность двигает ЗАСЛУЖЕННЫЙ ранг, а не раздаёт его тем, кому он не положен
static func goblin_start_squads() -> Array:
	var shift: int = int(preset().get("goblin_vet_shift", 0))
	var base: Array = _GobCfg.start_squads()
	if shift == 0:
		return base
	var out: Array = []
	for row in base:
		var d: Dictionary = (row as Dictionary).duplicate()
		var v: int = int(d["vet"])
		if v > 0:
			# Пол в единицу, а не в ноль: отряд, задуманный ветеранским,
			# на Easy становится младшим ветераном, но знамя не теряет
			d["vet"] = clampi(v + shift, 1, 7)
			# Наград не может быть больше, чем ступеней ранга
			d["picks"] = mini(int(d["picks"]), int(d["vet"]))
		out.append(d)
	return out

# ═════════════════════════════════════════════════════════════════════════════
# НАСТРОЙКА НА ДИСКЕ
# ═════════════════════════════════════════════════════════════════════════════
## Прочитать сохранённый выбор. Молчалива по построению: нет файла, битый файл,
## незнакомый ключ — всё это означает «играем на обычной», а не ошибку
static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		set_current(DEFAULT)
		return
	set_current(String(cfg.get_value("game", "difficulty", DEFAULT)))

## Записать выбор на диск. Зовётся из меню сразу по клику: файл крошечный, а
## отдельная кнопка «сохранить настройки» — лишний шаг для игрока
static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "difficulty", current())
	cfg.save(SETTINGS_PATH)
