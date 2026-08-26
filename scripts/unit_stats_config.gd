extends RefCounted
## ЕДИНЫЙ КОНФИГ ХАРАКТЕРИСТИК ЮНИТОВ
## ═══════════════════════════════════════════════════════════════════════════
## Меняйте числа здесь — они подхватываются при спавне юнита, код трогать не надо.
## Подключение: const _UStats := preload("res://scripts/unit_stats_config.gd")
## (файл намеренно без class_name — так он не зависит от кэша глобальных классов)
##
## Смысл параметров:
##   health          — здоровье (HP)
##   movement_speed  — скорость движения, м/с
##   attack_1        — урон обычной (слабой) атаки
##   attack_2        — урон мощной атаки (Warrior бьёт: 3 раза attack_1, затем 1 раз attack_2)
##   attack_range    — дальность атаки, м (ближний бой ~1.6-1.8, лучник 18)
##   attack_range_cap— ЖЁСТКИЙ потолок дальности с учётом всех прибавок кузницы.
##                     Нет ключа — потолка нет (у ближнего боя он не нужен)
##   attack_cooldown — пауза между ударами, сек
##   defense         — защита: вычитается из входящего урона (растёт апгрейдами кузницы)
##   armor           — броня: дополнительное плоское снижение урона (базовое, от экипировки)
##   morale          — мораль 0..100: участвует в силе толкания (morale/100 добавляется к push_force)
##   push_force      — сила толкания: при ударе в ближнем бою юнит с большей суммой
##                     (push_force + morale/100) слегка отталкивает противника назад
##
## Только для ударной конницы (все поля необязательные, отсутствие = «не конница»):
##   charge_range       — за сколько метров до цели начинается разгон, м. 0 = разгона нет
##   charge_min_runup   — сколько метров надо РЕАЛЬНО проехать в разгоне, чтобы
##                        удар засчитался. Без этого натиск срабатывал бы и в
##                        плотном бою, где никто никуда не разгонялся
##   charge_speed_mult  — во сколько раз конница ускоряется на разгоне
##   charge_impact_frac — доля МАКСИМАЛЬНОГО запаса жизни цели, снимаемая ударом
##                        с разгона (0.5 = половина). Считается от max_health
##                        ЖЕРТВЫ, а не от урона всадника: это вес и скорость
##                        кабана, а не сила руки седока
##   charge_splash      — радиус первого ряда контакта, м: кого накрывает удар
##   charge_knockback   — на сколько метров разлетаются накрытые, м
##   charge_breakthrough — на сколько метров всадник вклинивается сквозь строй
##                         сразу после удара (0 — «ударил и встал»)
##   charge_counter_frac— доля СВОЕГО запаса жизни, которую конница теряет,
##                        налетев в лоб на стенку копий (см. Unit.repels_charge)
##   charge_push_mult   — множитель ПОСТОЯННОГО толчка в свалке (см. Unit._apply_push).
##                        К разгону отношения не имеет: это продавливание строя,
##                        которое идёт всё время, пока конница жива и бьётся
##
## Только для рабочего:
##   walk_speed_empty  — скорость ходьбы БЕЗ груза
##   walk_speed_loaded — скорость ходьбы С ресурсами (медленнее)
##   gather_time       — сколько секунд занимает один цикл добычи
##   gather_amount     — сколько ресурса приносит за один заход
##
## Только для лучника:
##   arrow_speed — скорость полёта стрелы, м/с (меньше = дольше летит)
##   arrow_arc   — высота дуги как доля дальности (0.5 = навесная траектория)

## Древо технологий кузницы живёт в отдельном файле: это самостоятельная
## балансная таблица на 4 вкладки × 20 узлов, и держать её здесь означало бы
## утопить характеристики юнитов в её объёме. Нужен он только одной функции —
## get_upgrade_slot(), которая отдаёт узлы древа как обычные слоты улучшений
const _Forge := preload("res://scripts/forge_config.gd")

const STATS := {
	# ── МЕЧНИК (Warrior) — тяжёлый боец, сильно толкается ────────────────────
	"warrior": {
		"health": 100.0,
		# Родительный падеж множественного числа — для названия отряда
		# по рангу («Отряд ветеранов КОПЕЙЩИКОВ», см. veteran_rank_name)
		"name_genitive_plural": "мечников",
		"movement_speed": 2.0,
		"attack_1": 20.0,          # три обычных удара...
		"attack_2": 25.0,          # ...затем один мощный (ротация 3+1)
		"attack_range": 1.6,
		"attack_cooldown": 1.5,
		"defense": 0.0,
		"armor": 2.0,
		"morale": 100.0,
		"push_force": 1.5,         # рыцарь продавливает строй
		"description": "Heavy melee fighter. Hits hardest in a straight duel and shoves enemy ranks back on contact.",
	},

	# ── КОПЕЙЩИК (Spearman) — основная пехота ────────────────────────────────
	"spearman": {
		"health": 70.0,
		# Родительный падеж множественного числа — для названия отряда
		# по рангу («Отряд ветеранов КОПЕЙЩИКОВ», см. veteran_rank_name)
		"name_genitive_plural": "копейщиков",
		"movement_speed": 2.0,
		"attack_1": 15.0,
		"attack_2": 18.0,           # у копейщика оба удара одинаковые (тычок копьём)
		"attack_range": 2.0,
		"attack_cooldown": 2.0,
		"defense": 0.0,
		"armor": 0.0,
		"morale": 50.0,
		"push_force": 1.0,
		"description": "Backbone infantry. Holds the line shoulder to shoulder — spears level automatically when the enemy closes in.",
	},

	# ── ЛУЧНИК (Archer) — стрелок, слаб в ближнем бою ────────────────────────
	"archer": {
		"health": 50.0,
		# Родительный падеж множественного числа — для названия отряда
		# по рангу («Отряд ветеранов КОПЕЙЩИКОВ», см. veteran_rank_name)
		"name_genitive_plural": "лучников",
		"movement_speed": 2.0,
		"attack_1": 15,
		"attack_2": 20.0,
		"attack_range": 20.0,
		# ── ЖЁСТКИЙ ПОТОЛОК ДАЛЬНОСТИ (заказ владельца, авг. 2026) ─────────
		# Дальность растёт от кузницы (bonus_range) и вписывается прямо в поле
		# бойца при рождении. Потолка у неё не было вовсе, и на прокачанной
		# кузнице лучник доставал через пол-экрана: «случайные сверхдальние
		# выстрелы через всю карту».
		#
		# Потолок ЖЁСТКИЙ и общий: он ограничивает СУММУ, а не прибавку, —
		# иначе каждое новое исследование пришлось бы согласовывать с ним
		# отдельно. 24 м это +20% к базовым двадцати: прокачка ощутима и при
		# этом не превращает стрелка в осадную машину
		"attack_range_cap": 24.0,
		"attack_cooldown": 4.0,
		"defense": 0.0,
		"armor": 0.0,
		"morale": 70.0,
		"push_force": 0.0,
		"arrow_speed": 20.0,        # замедленная стрела — видно дугу
		"arrow_arc": 0.20,          # навесная траектория (50% дальности в высоту)
		"description": "Ranged skirmisher. Long reach and a fast squad, but folds quickly if caught in melee.",
	},

	# ── МОНАХ (Monk) — вспомогательный юнит, слаб в бою ──────────────────────
	"monk": {
		"health": 60.0,
		# Родительный падеж множественного числа — для названия отряда
		# по рангу («Отряд ветеранов КОПЕЙЩИКОВ», см. veteran_rank_name)
		"name_genitive_plural": "монахов",
		"movement_speed": 2.0,
		"attack_1": 6.0,
		"attack_2": 6.0,
		"attack_range": 1.4,
		"attack_cooldown": 1.2,
		"defense": 0.0,
		"armor": 0.0,
		"morale": 60.0,
		"push_force": 0.3,
		"description": "Support unit. Weak in a fight — keep it behind the line.",
	},

	# ═════════════════════════════════════════════════════════════════════════
	# ГОБЛИНЫ — ТРЕТЬЯ СТОРОНА (Constants.FACTION_GOBLIN)
	# ═════════════════════════════════════════════════════════════════════════
	# Числа здесь, а не в goblin_config: это ХАРАКТЕРИСТИКИ БОЙЦА, и им место в
	# той же таблице, что и людям, — иначе сравнить копейщика с копейщиком
	# нельзя, не открыв два файла. В goblin_config живёт ПОВЕДЕНИЕ фракции
	# (волны, деревня, спячка), а не сила удара.
	#
	# Замысел: гоблин по одному слабее человека и берёт числом (отряд 100 против
	# 20), наездник на кабане — быстрый и бьющий больно, но хрупкий.
	"goblin_spearman": {
		"health": 75.0,
		# Родительный падеж множественного числа — для названия отряда
		# по рангу («Отряд ветеранов КОПЕЙЩИКОВ», см. veteran_rank_name)
		"name_genitive_plural": "гоблинов",
		"movement_speed": 2.2,
		"attack_1": 9.0,            # «Attack Fast» — три быстрых тычка...
		"attack_2": 15.0,           # ...затем один «Attack Strong» (ротация 3+1)
		"attack_range": 2.2,
		"attack_cooldown": 2.0,
		"defense": 0.0,
		"armor": 0.0,
		"morale": 70.0,
		"push_force": 0.8,
		"description": "Goblin spear mob. Weak one on one, dangerous in a hundred.",
	},
	"goblin_rider": {
		"health": 150.0,
		# Родительный падеж множественного числа — для названия отряда
		# по рангу («Отряд ветеранов КОПЕЙЩИКОВ», см. veteran_rank_name)
		"name_genitive_plural": "наездников",
		# ── СКОРОСТЬ КАБАНА: ЗАКАЗ ВЛАДЕЛЬЦА «РАССЕКАТЬ ПОЛЕ» ─────────────
		# Было 3.4 — это 1.55 от пешего гоблина (2.2) и 1.7 от людской пехоты
		# (2.0). Замер (qa_cavalry, блок A) показал, что и в чистом поле, и в
		# плотном строю всадник идёт РОВНО свою скорость, без единого троттля:
		# «едут вровень с пехотой» было впечатлением от самого числа, а не от
		# кода. Поэтому лечится оно числом же.
		#
		# 4.6 — это 2.1 от пешего гоблина и 2.3 от людского копейщика: конница
		# обгоняет строй вдвое, то есть успевает обойти его с фланга за то
		# время, пока фаланга разворачивается
		"movement_speed": 4.6,
		"attack_1": 20.0,
		"attack_2": 22.0,
		"attack_range": 2.2,
		"attack_cooldown": 1.0,
		"defense": 0.0,
		"armor": 2.0,
		"morale": 110.0,
		"push_force": 25.0,          # кабан продавливает строй сильнее рыцаря
		# ── УДАРНАЯ КОННИЦА: ТОЛЧОК ВДВОЕ И ПОЧТИ НА КАЖДЫЙ УДАР ───────────
		# Одного push_force для этого мало, и вот почему. Смещение считается
		# как clampf(разница напора × 0.15, 0.04, 0.4) — то есть ПОТОЛОК 0.4 м
		# срабатывает уже при разнице в три единицы. У кабана против копейщика
		# разница около четырнадцати: пятнадцать в конфиге и три в конфиге
		# давали ОДНО И ТО ЖЕ смещение, потолок съедал всю разницу.
		#
		# charge_push_mult применяется ПОСЛЕ потолка — это и есть заказанное
		# «вдвое». push_every переводит толчок с «раз в десять ударов» на
		# «через один»: при кулдауне 1.0 с прежний строй продавливался на семь
		# сантиметров раз в десять секунд, чего на экране не видно вовсе
		# 3.5, а не 2.0: замер прорыва (qa_cavalry, блок E — три отряда кабанов
		# против трёх отрядов копейщиков) показал, что при двойке стадо в строй
		# ВХОДИТ, но насквозь не проходит — центр массы застревал в двух метрах
		# перед исходной линией. Заказ владельца прямой: «прорывая центр фаланги
		# насквозь», и мерится он именно этим числом
		"charge_push_mult": 5.5,
		# Толчок на КАЖДЫЙ удар. При «через один» кабан с кулдауном 1.0 с давил
		# раз в две секунды — на экране это не напор, а переминание
		"push_every": 1,
		# ── НАТИСК С РАЗГОНА (заказ владельца, авг. 2026) ──────────────────
		# До этого «ударная конница» была только продавливанием: кабан подъезжал
		# обычным шагом и начинал теснить. Самого УДАРА не было вовсе — то есть
		# не было того единственного мгновения, ради которого конницу и держат.
		#
		# Разгон начинается за десять метров: этого хватает, чтобы игрок успел
		# увидеть рывок, и мало, чтобы стадо разгонялось через полкарты.
		# Ускорение 1.8 поверх и без того вдвое большей скорости — на экране
		# это бросок, а не «пошёл побыстрее».
		#
		# УРОН СЧИТАЕТСЯ ОТ ЗАПАСА ЖЕРТВЫ, а не от силы удара седока: сминает
		# не топор, а полтонны кабана на скорости. Половина — заказ владельца.
		"charge_range": 10.0,
		# ── БЕЗ РАЗГОНА НЕТ И ТАРАНА ───────────────────────────────────────
		# Жалоба владельца: «эффект разлёта срабатывает дважды за одно
		# соприкосновение, в том числе когда юниты уже сошлись в плотном бою
		# без разгона». Так и было: натиск взводился по одной лишь ДИСТАНЦИИ
		# до цели, а в свалке цель меняется каждые пару секунд, и новая нередко
		# оказывается за десять метров — то есть условие взвода выполнялось
		# снова, стоя на месте.
		#
		# Теперь мало оказаться далеко: надо ПРОЙТИ это расстояние. Всадник
		# запоминает точку, где начал разгон, и удар засчитывается, только если
		# он реально проехал charge_min_runup метров. В плотном бою столько не
		# проехать — и повторный разлёт не случается вовсе.
		# 5 м из заказанного диапазона «5-10», а не верхняя его граница: разгон
		# начинается за charge_range (10 м), а касание происходит примерно за
		# 2.5 м — то есть на полный проезд остаётся около семи с половиной
		# метров. Порог в шесть метров оставлял полтора метра запаса и на
		# стенде срабатывал через раз: цель успевала подойти сама, всадник
		# взводил разгон позже десяти метров и не добирал своего
		"charge_min_runup": 5.0,
		"charge_speed_mult": 1.8,
		"charge_impact_frac": 0.5,
		"charge_splash": 2.0,
		"charge_knockback": 3.2,
		# Сколько метров кабан проезжает СКВОЗЬ строй сразу после удара.
		# Ноль вернул бы прежнее «ударил и встал в первой шеренге»
		"charge_breakthrough": 1.8,
		# ── ЦЕНА ЛОБОВОГО НАВАЛА НА КОПЬЯ ──────────────────────────────────
		# Треть своего запаса за попытку смять фалангу в лоб. Числом это ровно
		# то же требование, что и «отбрасывания нет»: фронт копейщиков должен
		# быть местом, куда конницу гнать НЕЛЬЗЯ, а не местом, где она теряет
		# часть эффективности
		"charge_counter_frac": 0.35,
		"description": "Pig rider. Fast shock cavalry — hits hard, dies fast.",
	},

	# ── РАБОЧИЙ (Worker / Pawn) — не боец ────────────────────────────────────
	"worker": {
		"health": 30.0,
		"walk_speed_empty": 3.0,   # налегке бегает быстро
		"walk_speed_loaded": 2.1,  # с грузом заметно медленнее
		"defense": 0.0,
		"armor": 0.0,
		"morale": 40.0,
		"push_force": 0.5,
		"gather_time": 4.5,       # +15% к 3.0 — рубка стала ощутимо неторопливее
		"gather_amount": 10.0,
		"description": "Gathers resources and builds structures. Unarmed — keep away from the fighting.",
	},
}

## Размеры гоблинских отрядов лежат в их собственном конфиге (см. squad_size)
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

## ═══════════════════════════════════════════════════════════════════════════
## СТОЙКИ ОТРЯДА (STANCES) — кнопки [АТАКА] / [ЗАЩИТА] на панели отряда
## ═══════════════════════════════════════════════════════════════════════════
## Стойка переключается у КАЖДОГО юнита выделенной горячей группы и читается
## вживую при каждом ударе/шаге — как и бонусы кузницы.
##
##   push_mult         — множитель силы толкания (0.0 = пуш полностью выключен)
##   push_resist       — множитель ВХОДЯЩЕГО толчка (0.5 = отбрасывает вдвое слабее)
##   attack_speed_mult — множитель СКОРОСТИ атаки (кулдаун делится на него)
##   move_speed_mult   — множитель СКОРОСТИ ХОДЬБЫ. У обороны 0.65 (штраф −35%):
##                       строй со щитами и опущенными копьями идёт шагом. Раньше
##                       это число жило константой Unit.PHALANX_ATTACK_FACTOR и
##                       не действовало на бегу — боец в обороне, которому дали
##                       двойной ПКМ, разгонялся до 1.4 базовой, то есть БЫСТРЕЕ
##                       обычной ходьбы. Теперь штраф стойки применяется всегда
##   morale_mult       — множитель морали
##   defense_bonus     — плоская добавка к защите
##   holds_ground      — true: юнит не преследует цель и не подаётся вперёд
##                       при толкании (стоит намертво на своём месте)
##   lock_position     — true: ПОЗИЦИЯ ЗАЛОЧЕНА НАГЛУХО. Ни приказ на движение,
##                       ни приказ атаки, ни смыкание дыр в своём строю не
##                       сдвигают бойца ни на сантиметр; разрешён только разворот
##                       (facing) и удар по тому, кто сам вошёл в дальность.
##                       Единственное исключение — СМЫКАНИЕ РЯДОВ отряда
##                       (Unit.allow_reform_move): без него потери и проход
##                       союзников оставляли бы в строю вечные дыры
const STANCE_ATTACK  := "attack"
const STANCE_DEFENSE := "defense"

## ОБЩИЙ МНОЖИТЕЛЬ СИЛЫ ТОЛЧКА (knockback) для всех юнитов.
## 0.35 = 35% от прежней силы: бойцы больше не разлетаются от каждого тычка,
## шеренга давит плавно. Крутить баланс толкания следует ЗДЕСЬ.
const PUSH_GLOBAL_SCALE := 0.35

const STANCES := {
	"attack": {
		"name":              "Attack",
		"push_mult":         1.0,
		"push_resist":       1.0,
		"attack_speed_mult": 1.0,
		"move_speed_mult":   1.0,
		"morale_mult":       1.0,
		"defense_bonus":     0.0,
		"holds_ground":      false,
		"lock_position":     false,
	},
	"defense": {
		"name":              "Defend",
		"push_mult":         0.0,    # своего пуша у фаланги нет вовсе
		"push_resist":       0.5,    # входящий толчок срезан вдвое (упор щитами)
		"attack_speed_mult": 1.25,   # +25% скорости атаки
		"move_speed_mult":   0.65,   # −35% скорости ходьбы (щит/опущенные копья)
		"morale_mult":       1.30,   # +30% морали
		"defense_bonus":     5.0,    # +5 защиты
		"holds_ground":      true,   # с места не сходят (кроме смыкания рядов)
		# ── ЗАМОК ПОЗИЦИИ СНЯТ ОБРАТНО (заказ владельца, авг. 2026) ────────
		# Короткая история этой ручки, чтобы её не завели в третий раз.
		#
		# Жалоба была: «в обороне крайние копейщики срываются с места и идут
		# вперёд на врага». Первым решением стал ГЛУХОЙ ЗАМОК (true) — не
		# двигаться вообще. Он закрыл жалобу и тут же создал другую: фаланга
		# перестала ходить строем ПО ПРИКАЗУ ИГРОКА, а это её штатная работа.
		#
		# Настоящая причина выбега оказалась не в том, что фаланге вообще
		# разрешено двигаться, а в ТОЧКЕ, куда её посылали: приказ атаки давал
		# КАЖДОМУ бойцу одну и ту же цель — координату врага. Строй честно
		# сходился в неё, то есть схлопывался, и первыми это видно на флангах
		# (им идти дальше всех). Лечится это точкой, а не запретом движения
		# (см. Unit.command_attack и _phalanx_march).
		#
		# Ручка оставлена: поставьте true, если понадобится «стоять намертво».
		# Стенды читают её из конфига и поедут за ней сами
		"lock_position":     false,
	},
}

## Словарь стойки по id; неизвестная стойка → «атака» (стандартные параметры)
static func get_stance(stance_id: String) -> Dictionary:
	return STANCES.get(stance_id, STANCES["attack"])

## Одно поле стойки с дефолтом
static func stance_stat(stance_id: String, key: String, default: float = 0.0) -> float:
	var d: Dictionary = get_stance(stance_id)
	return d.get(key, default)

## Вернуть словарь характеристик юнита ("warrior"/"spearman"/"archer"/"worker")
static func get_stats(unit_id: String) -> Dictionary:
	return STATS.get(unit_id, {})

## Одно значение с дефолтом: stat("warrior", "push_force", 1.0)
static func stat(unit_id: String, key: String, default: float = 0.0) -> float:
	var d: Dictionary = STATS.get(unit_id, {})
	return d.get(key, default)


## ═══════════════════════════════════════════════════════════════════════════
## ПОСТРОЙКИ (BUILDINGS) — ЕДИНАЯ ТАБЛИЦА ПАРАМЕТРОВ
## ═══════════════════════════════════════════════════════════════════════════
## Здесь крутится ВСЁ по зданиям: запас жизни, темп стройки, цена, габарит.
## Значения читаются каждым зданием в _ready() и рабочими при заказе стройки —
## код трогать не надо.
##
##   name             — подпись в интерфейсе
##   max_hp           — запас жизни постройки
##   build_time       — СЕКУНДЫ работы ОДНОГО рабочего до готовности.
##                      Артель ускоряет: n рабочих → ×(1 + (n-1)·0.6)
##                      (см. ConstructionSite.BUILDER_SPEEDUP).
##                      0.0 = здание не строится рабочими (Замок ставится сразу)
##   size             — габарит коллизии и спрайта, метры
##   cost_wood / cost_gold / cost_stone — цена (0.0 = ресурс не тратится)
##   worker_buildable — true: кнопка появляется на панели рабочего сама
##   icon             — картинка для кнопки и карточки характеристик
# ═════════════════════════════════════════════════════════════════════════════
# ИКОНКИ КУЗНИЦЫ (улучшения и бонусы ветеранства)
#
# ЗАЧЕМ ОТДЕЛЬНАЯ КОНСТАНТА. Полный res://-путь, вписанный в каждую строку
# конфига, ломается от любого переезда папки — и ломается МОЛЧА: load()
# возвращает null, кнопка остаётся без картинки, ошибки нет. Ровно так и
# случилось: в VETERAN_LEVEL_BONUSES лежал путь
#   res://assets/factions/humans/buildings/icons/buildings/icons_for_smith/icon_sword
# где «buildings/icons» переставлены местами относительно настоящего
# «icons/buildings», да ещё и без расширения .png.
#
# Теперь в конфиге пишется ТОЛЬКО имя файла ("icon_sword.png"), а каталог
# задаётся здесь одной строкой. Переезд папки — правка одной константы.
# ═════════════════════════════════════════════════════════════════════════════
const SMITH_ICONS_DIR := "res://assets/factions/humans/icons/buildings/icons_for_smith/"

## ═════════════════════════════════════════════════════════════════════════════
## ЁМКОСТЬ РУДНИКА (ОДНОЙ КУЧИ ЗОЛОТА ИЛИ КАМНЯ)
## ═════════════════════════════════════════════════════════════════════════════
## Куча — ЕДИНЫЙ логический объект с общим запасом (см. MineCluster), поэтому
## баланс месторождения меняется здесь ОДНОЙ ЦИФРОЙ. Раньше запас складывался из
## запасов отдельных камушков (Main.PIECE_CLASSES.amount × состав шаблона): чтобы
## «добавить золота», приходилось править раскладку кучи, то есть её ВНЕШНИЙ ВИД,
## и наоборот — правка вида молча меняла баланс.
##
## Числа общие на все кучи своего типа: разброс по величине месторождений — это
## отдельное решение, и делать его случайным побочным эффектом того, сколько
## кусков влезло мимо воды и пятачка базы, точно не стоит
const DEFAULT_CLUSTER_GOLD  := 10000.0
const DEFAULT_CLUSTER_STONE := 10000.0

## Ёмкость кучи по виду ресурса ("gold"/"stone"). Строкой, а не числом
## Constants.RESOURCE_*: конфиг — самостоятельная таблица и про перечисления
## движка ничего не знает, сопоставление делает вызывающий (Main)
static func cluster_stock(kind: String) -> float:
	match kind:
		"gold":  return DEFAULT_CLUSTER_GOLD
		"stone": return DEFAULT_CLUSTER_STONE
	return DEFAULT_CLUSTER_STONE

## Полный путь к иконке кузницы по ИМЕНИ ФАЙЛА.
## Принимает и готовый res://-путь: тогда возвращает его как есть — старые
## записи конфига и чужие иконки продолжают работать без правок.
## Расширение можно не писать: ".png" подставится само
static func smith_icon_path(icon_name: String) -> String:
	if icon_name.is_empty():
		return ""
	if icon_name.begins_with("res://") or icon_name.begins_with("user://"):
		return icon_name
	var f := icon_name
	if f.get_extension().is_empty():
		f += ".png"
	return SMITH_ICONS_DIR + f

## Текстура иконки кузницы. НИКОГДА не роняет интерфейс: нет файла или опечатка
## в имени — вернётся null, а в консоль уйдёт предупреждение с путём, по
## которому искали. Вызывающий рисует кнопку с подписью вместо картинки
static func smith_icon(icon_name: String) -> Texture2D:
	var path := smith_icon_path(icon_name)
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("Иконка кузницы не найдена: %s (искали по имени «%s»)"
			% [path, icon_name])
		return null
	var tex := ResourceLoader.load(path) as Texture2D
	if tex == null:
		push_warning("Иконка кузницы не читается как текстура: %s" % path)
	return tex

# ═════════════════════════════════════════════════════════════════════════════
# СТАРТОВЫЕ РЕСУРСЫ — ОТДЕЛЬНЫМИ БЛОКАМИ ДЛЯ ИГРОКА И ДЛЯ ИИ
#
# Раньше эти числа были ЗАШИТЫ в ResourceManager.reset_resources() — то есть
# балансная настройка жила в коде, а не в балансной таблице, и владельцу
# приходилось править автозагрузку, чтобы поменять стартовый запас.
#
# ДВА БЛОКА, А НЕ ОДИН. До этого запас у ИИ был выражен как
# `resources[ENEMY] = resources[PLAYER].duplicate()` — «равный старт» намеренно,
# потому что до этого у ИИ было на 50 дерева и 50 золота больше, и он закладывал
# постройку раньше, что читалось как «ресурсы падают с неба». Раздельные блоки
# сами по себе баланс НЕ МЕНЯЮТ: значения ниже одинаковы, равный старт сохранён.
# Теперь его просто можно настроить — например, дать ИИ форы на высокой сложности,
# не трогая ни строки кода.
#
# Ключи — Constants.RESOURCE_*. Не указанный ресурс считается нулём
# (см. starting_resources), поэтому убрать позицию можно просто удалив строку
# ═════════════════════════════════════════════════════════════════════════════
const PLAYER_STARTING_RESOURCES := {
	Constants.RESOURCE_WOOD:  24500.0,   # хватает на Замок (300) и запас на первую постройку
	Constants.RESOURCE_GOLD:  22500.0,
	Constants.RESOURCE_STONE: 21000.0,
	Constants.RESOURCE_FOOD:  11000.0,
}

const AI_STARTING_RESOURCES := {
	Constants.RESOURCE_WOOD:  450.0,
	Constants.RESOURCE_GOLD:  350.0,
	Constants.RESOURCE_STONE: 300.0,
	Constants.RESOURCE_FOOD:  300.0,
}

## Стартовый запас фракции. ВСЕГДА возвращает полный набор из четырёх ресурсов:
## в блоке конфига позицию можно опустить, и она будет нулём — иначе пропуск
## строки означал бы «ключа нет вовсе», и всё, что читает склад по ключу,
## получало бы отсутствующее значение вместо нуля
static func starting_resources(faction: int) -> Dictionary:
	var src: Dictionary = AI_STARTING_RESOURCES if faction == Constants.FACTION_ENEMY \
		else PLAYER_STARTING_RESOURCES
	return {
		Constants.RESOURCE_WOOD:  float(src.get(Constants.RESOURCE_WOOD,  0.0)),
		Constants.RESOURCE_GOLD:  float(src.get(Constants.RESOURCE_GOLD,  0.0)),
		Constants.RESOURCE_STONE: float(src.get(Constants.RESOURCE_STONE, 0.0)),
		Constants.RESOURCE_FOOD:  float(src.get(Constants.RESOURCE_FOOD,  0.0)),
	}

const BUILDINGS := {
	"castle": {
		"name": "Замок", "max_hp": 5000.0,
		"build_time": 15.0,                       # ставится готовым с первого клика
		"size": Vector3(8.0, 6.0, 8.0),
		"cost_wood": 300.0, "cost_gold": 300.0, "cost_stone": 300.0,
		"worker_buildable": false,
		"icon": "res://assets/factions/humans/icons/buildings/Castle.png",
	},
	# ХИЖИНА ГОБЛИНОВ. Игроку не строится (worker_buildable = false): это
	# здание третьей стороны, оно расставляется генератором деревни
	"goblin_hut": {
		"name": "Хижина гоблинов", "max_hp": 1000.0, "build_time": 10.0,
		"size": Vector3(4.0, 3.5, 4.0),
		"cost_wood": 0.0, "cost_gold": 0.0, "cost_stone": 0.0,
		"worker_buildable": false,
		"icon": "",
	},
	"barracks": {
		"name": "Бараки", "max_hp": 2000.0, "build_time": 20.0,
		"size": Vector3(3.5, 2.2, 3.5),
		"cost_wood": 1000.0, "cost_gold": 500.0, "cost_stone": 1000.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/Barracks.png",
	},
	"smithy": {
		"name": "Кузница", "max_hp": 2000.0, "build_time": 20.0,
		"size": Vector3(4.0, 3.0, 4.0),
		"cost_wood": 1500.0, "cost_gold": 1000.0, "cost_stone": 500.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/Monastery.png",
	},
	"mine": {
		"name": "Рудник", "max_hp": 250.0, "build_time": 10.0,
		"size": Vector3(3.0, 2.0, 3.0),
		"cost_wood": .0, "cost_gold": 0.0, "cost_stone": 0.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/Tower.png",
	},
	"house": {
		"name": "Дом", "max_hp": 180.0, "build_time": 10.0,
		"size": Vector3(2.6, 2.2, 2.6),
		"cost_wood": 60.0, "cost_gold": 0.0, "cost_stone": 0.0,
		"worker_buildable": true,
		"icon": "res://assets/factions/humans/icons/buildings/House1.png",
	},
	# Служебные: не строятся рабочими, но запас жизни настраивается так же
	"town_center": {
		"name": "Городской центр", "max_hp": 500.0, "build_time": 0.0,
		"size": Vector3(4.0, 2.5, 4.0),
		"cost_wood": 0.0, "cost_gold": 0.0, "cost_stone": 0.0,
		"worker_buildable": false, "icon": "",
	},
	"construction_site": {
		"name": "Стройка", "max_hp": 120.0, "build_time": 0.0,
		"size": Vector3(3.0, 2.0, 3.0),
		"cost_wood": 0.0, "cost_gold": 0.0, "cost_stone": 0.0,
		"worker_buildable": false, "icon": "",
	},
}

## ДОМ: сколько еды капает и с каким интервалом (сек)
const HOUSE_FOOD_INCOME   := 4.0
const HOUSE_FOOD_INTERVAL := 8.0

## ═══════════════════════════════════════════════════════════════════════════
## РАЗМЕР ОТРЯДА (SQUAD SIZE) — СКОЛЬКО МОДЕЛЕЙ В ОДНОМ ОТРЯДЕ
## ═══════════════════════════════════════════════════════════════════════════
## Одна цифра управляет всем: сколько бойцов выходит за один заказ, что
## считается «полным отрядом» у ИИ и до какого числа отряд будет пополняться.
## Меняйте здесь — ни здания, ни HUD, ни ИИ править не нужно.
const SQUAD_SIZE_SPEARMEN  := 60   # копейщики
const SQUAD_SIZE_ARCHERS   := 30   # лучники
const SQUAD_SIZE_SWORDSMEN := 30   # мечники (рыцари)
const SQUAD_SIZE_MONKS     := 10   # монахи — редкий вспомогательный юнит, малый отряд

## Предохранитель от опечатки: заказ больше этого числа обрезается
## (Building.queue_unit). Поднимать вместе с SQUAD_SIZE_*.
## Потолок размера отряда. Поднят с 60 до 100 ради гоблинской орды: у неё в
## отряде сто копейщиков (goblin_config.SQUAD_SIZE). Людей это не касается —
## их размеры заданы своими числами и заметно ниже потолка
const SQUAD_SIZE_HARD_CAP := 100

## ═══════════════════════════════════════════════════════════════════════════
## ОПЫТ ОТРЯДА (VETERANCY) — ЗВЁЗДОЧКИ ЗА УБИЙСТВА, ОТДЕЛЬНО ПО ТИПАМ ЮНИТОВ
## ═══════════════════════════════════════════════════════════════════════════
## Отряд копит убийства ЦЕЛИКОМ: фраг любого бойца идёт в общий счёт.
## Дошли до очередного порога — над отрядом загорается жёлтая звёздочка,
## а на его панели игроку предлагают выбрать одно улучшение из пяти.
##
## У КАЖДОГО БОЕВОГО ТИПА — СВОЙ БЛОК порогов и бонусов (запрос владельца:
## "разделить конфиг ветеранства по 4 типам, чтобы настраивать их порознь").
## Ключ верхнего уровня VET_CONFIG — unit_id, тот же, что в TRAINING/STATS.
## РАБОЧИЙ (worker) сюда НЕ входит вовсе — он полностью исключён из системы
## опыта: veteran_level_for_kills("worker", ...) и любые другие обращения с
## неизвестным/не боевым unit_id ниже просто возвращают "нет ветеранства"
## (0 / пустой массив), а не ошибку — так отсутствие рабочего в конфиге не
## обязано быть отдельной веткой в каждом вызывающем коде.
##
## Внутри каждого блока пока лежит ОДНА И ТА ЖЕ копия прежних общих чисел —
## значения ещё предстоит развести (владелец: "скопируй текущие значения как
## базовые, для будущей точной настройки"). Меняйте их здесь порознь, менять
## код нигде не нужно.
##
## Порогов ровно столько, сколько уровней: седьмой порог — последний.
## Убрать уровень = убрать число из "thresholds" И соответствующий блок из
## "bonuses" (длины должны совпадать).
##
## СЕМЬ ГРЕЙДОВ (как они выглядят над отрядом — см. VET_BANNER_TIERS ниже,
## общие для всех типов). Звёздочки ЗАМЕНЕНЫ ЗНАМЁНАМИ на копьях:
##   1-3 — красный вымпел: одна лычка, две, две с белым наконечником;
##   4-6 — синий «ласточкин хвост»: одна лычка, две, две с белым наконечником;
##   7   — прямоугольный штандарт с золотой бахромой и гербом.
##
## Поля бонуса:
##   id    — ключ выбора (латиницей)
##   name  — подпись кнопки
##   icon  — файл из SMITH_ICONS_DIR
##   далее — ПОЛНЫЙ ШАБЛОН МОДИФИКАТОРОВ (см. MODIFIERS): все двенадцать ключей,
##           ненужное нулём. Награда вправе давать сразу несколько — например
##           «+1 к урону и +0.2 к скорости»: обе строки уже есть, поставьте
##           числа. Бонус выдаётся КАЖДОЙ модели отряда.
##   stat / value — В ТАБЛИЦЕ ИХ НЕТ. Короткая пара выводится из модификаторов
##           при чтении (см. veteran_choices) — держать её здесь вторым
##           описанием того же числа значило бы завести источник расхождений.
##
## ВНИМАНИЕ по скорости: базовая скорость юнита ~2-3 м/с, поэтому +5 к скорости
## это очень много. Значение оставлено как заказано; если бег окажется
## неиграбельным — правьте value у выбора "speed" здесь, код трогать не надо.
## Один блок = пороги на 7 уровней + 7×5 бонусов на выбор. Ниже — четыре
## НЕЗАВИСИМЫХ литерала (не .duplicate() от одного шаблона: GDScript не даёт
## звать методы в инициализаторе const, да и независимые литералы честнее
## отражают "4 блока для будущей настройки порознь" — правка одного блока
## физически не может задеть другой)
const _VET_BONUS_TEMPLATE := [
	# ── УРОВЕНЬ 1 ──────────────────────────────────────────────────────
	[
		{"id": "attack", "name": "+3 урона к Атаке", "icon": "icon_sword.png",
			"bonus_attack": 3.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.2, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 10.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "+3 к Броне", "icon": "icon_shield.png",
			"bonus_attack": 0.3, "bonus_armor": 1.5, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": -0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 5.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "+15 HP", "icon": "icon_heart.png",
			"bonus_attack": 1.0, "bonus_armor": 0.0, "bonus_defense": 2.0,
			"bonus_health": 15.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 1.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── УРОВЕНЬ 2 ──────────────────────────────────────────────────────
	[
		{"id": "attack", "name": "+3 урона к Атаке", "icon": "icon_sword.png",
			"bonus_attack": 3.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.2, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 10.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "+3 к Броне", "icon": "icon_shield.png",
			"bonus_attack": 0.3, "bonus_armor": 1.5, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": -0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 5.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "defense", "name": "+ к Защите", "icon": "icon_might.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 3.0,
			"bonus_health": 0.0, "bonus_speed": 0.3, "bonus_range": 0.0,
			"bonus_cooldown": 0.3, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "+15 HP", "icon": "icon_heart.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 15.0, "bonus_speed": 0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.2, "bonus_spread": 0.0, "bonus_push": 0.5,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── УРОВЕНЬ 3 ──────────────────────────────────────────────────────
	[
		{"id": "attack", "name": "+3 урона к Атаке", "icon": "icon_sword.png",
			"bonus_attack": 3.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.2, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 10.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "+3 к Броне", "icon": "icon_shield.png",
			"bonus_attack": 0.3, "bonus_armor": 3.0, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": -0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 5.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "morale", "name": "+20 к Морале", "icon": "icon_hand.png",
			"bonus_attack": 1.0, "bonus_armor": 1.0, "bonus_defense": 1.0,
			"bonus_health": 5.0, "bonus_speed": 0.3, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.5,
			"bonus_morale": 20.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "+15 HP", "icon": "icon_heart.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 15.0, "bonus_speed": 0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.1, "bonus_spread": 0.0, "bonus_push": 0.5,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── УРОВЕНЬ 4 ──────────────────────────────────────────────────────
	[
		{"id": "attack", "name": "+4 Урон к Атаке", "icon": "icon_sword.png",
			"bonus_attack": 4.0, "bonus_armor": 0.0, "bonus_defense": 0.3,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.2, "bonus_spread": 0.0, "bonus_push": 0.2,
			"bonus_morale": 10.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "+3 к Броне", "icon": "icon_shield.png",
			"bonus_attack": 0.5, "bonus_armor": 3.0, "bonus_defense": 0.5,
			"bonus_health": 0.0, "bonus_speed": -0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 5.0, "bonus_carry": 0.0, "bonus_gather": 0.0},

		{"id": "health", "name": "+20 HP", "icon": "icon_heart.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 20.0, "bonus_speed": 0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.1, "bonus_spread": 0.0, "bonus_push": 0.2,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── УРОВЕНЬ 5 ──────────────────────────────────────────────────────
	[
		{"id": "attack", "name": "+5 Урон к Атаке", "icon": "icon_sword.png",
			"bonus_attack": 5.0, "bonus_armor": 0.0, "bonus_defense": 0.3,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.2, "bonus_spread": 0.0, "bonus_push": 0.3,
			"bonus_morale": 10.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "+3 к Броне", "icon": "icon_shield.png",
			"bonus_attack": 0.3, "bonus_armor": 3.0, "bonus_defense": 0.5,
			"bonus_health": 0.0, "bonus_speed": -0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 5.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "defense", "name": "+3 к Защите", "icon": "icon_might.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 3.0,
			"bonus_health": 0.0, "bonus_speed": 0.3, "bonus_range": 0.0,
			"bonus_cooldown": 0.3, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		
		{"id": "health", "name": "+20 HP", "icon": "icon_heart.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 20.0, "bonus_speed": 0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.2, "bonus_spread": 0.0, "bonus_push": 0.5,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── УРОВЕНЬ 6 ──────────────────────────────────────────────────────
	[
		{"id": "attack", "name": "+5 Урон к Атаке", "icon": "icon_sword.png",
			"bonus_attack": 5.0, "bonus_armor": 0.0, "bonus_defense": 0.5,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.2, "bonus_spread": 0.0, "bonus_push": 0.3,
			"bonus_morale": 10.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "+ к Броне", "icon": "icon_shield.png",
			"bonus_attack": 0.3, "bonus_armor": 3.0, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": -0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "defense", "name": "+ к Защите", "icon": "icon_might.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 6.0,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "speed", "name": "+ к Скорости", "icon": "icon_hand.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": 0.3, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "+ HP", "icon": "icon_heart.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 40.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
	# ── УРОВЕНЬ 7 ──────────────────────────────────────────────────────
	[
		{"id": "attack", "name": "+ Урон к Атаке", "icon": "icon_sword.png",
			"bonus_attack": 6.0, "bonus_armor": 0.0, "bonus_defense": 0.3,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.3, "bonus_spread": 0.0, "bonus_push": 0.5,
			"bonus_morale": 10.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "armor", "name": "+ к Броне", "icon": "icon_shield.png",
			"bonus_attack": 0.3, "bonus_armor": 5.0, "bonus_defense": 0.5,
			"bonus_health": 0.0, "bonus_speed": -0.1, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.5,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "defense", "name": "+ к Защите", "icon": "icon_might.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 8.0,
			"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "speed", "name": "+ к Скорости", "icon": "icon_hand.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 0.0, "bonus_speed": 0.4, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
		{"id": "health", "name": "+ HP", "icon": "icon_heart.png",
			"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
			"bonus_health": 50.0, "bonus_speed": 0.0, "bonus_range": 0.0,
			"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
			"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	],
]

## Копейщики / Рыцари (мечники) / Лучники / Монахи — четыре НЕЗАВИСИМЫХ блока.
## static var, а не const: GDScript не разрешает звать методы (.duplicate) в
## инициализаторе const, а без глубокой копии все четыре ключа указывали бы
## на ОДИН И ТОТ ЖЕ вложенный массив _VET_BONUS_TEMPLATE (Array — ссылочный
## тип), и правка "attack" у Копейщиков задним числом поменяла бы то же
## число у Рыцарей/Лучников/Монахов. static-инициализатор выполняется один
## раз при загрузке скрипта, значения дальше можно менять по каждому ключу
## порознь, ничего не задевая
static var VET_CONFIG: Dictionary = {
	"spearman": {"thresholds": [40, 80, 120, 180, 240, 300, 350], "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"warrior":  {"thresholds": [100, 200, 400, 600, 800, 1000, 1300], "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"archer":   {"thresholds": [100, 200, 400, 600, 800, 1000, 1300], "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"monk":     {"thresholds": [40, 100, 200, 300, 400, 500, 600], "bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	# ── ГОБЛИНЫ: ШКАЛА ЛЮДЕЙ ЦЕЛИКОМ (заказ владельца) ──────────────────────
	# Тот же шаблон наград и та же лестница порогов. Записи отдельные, а не
	# «сослаться на копейщика»: VET_CONFIG — static var, её правят вживую, и
	# общая ссылка означала бы, что правка гоблинам молча меняет людей
	"goblin_spearman": {"thresholds": [100, 200, 400, 600, 800, 1000, 1300],
		"bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
	"goblin_rider":    {"thresholds": [140, 240, 400, 600, 800, 1000, 1600],
		"bonuses": _VET_BONUS_TEMPLATE.duplicate(true)},
}

## ═══════════════════════════════════════════════════════════════════════════
## ГРЕЙДЫ ЗВЁЗД (цвет и число звёзд по уровню)
## ═══════════════════════════════════════════════════════════════════════════
## Единственный источник правды и для 3D-звезды над отрядом (VeterancyStar.gd),
## и для строки звёзд на панели (HUD._portrait_stars_lbl). Формат:
##   count — сколько звёзд рисовать, tier — "bronze" | "silver" | "gold"
## Уровень выше последней записи берёт последнюю (высший грейд не «пропадает»)
## ── ПРЕЖНЯЯ ЗВЁЗДНАЯ ШКАЛА: НАСЛЕДИЕ ───────────────────────────────────────
## Звёзды заменены знамёнами (см. VET_BANNER_TIERS). Таблица оставлена в дереве
## неиспользуемой игрой — по ней ещё меряются стенды прежнего вида, и это
## единственное, что её держит. Новый код обязан читать VET_BANNER_TIERS
const VET_STAR_TIERS := [
	{"count": 1, "tier": "bronze"},
	{"count": 2, "tier": "bronze"},
	{"count": 3, "tier": "bronze"},
	{"count": 1, "tier": "silver"},
	{"count": 2, "tier": "silver"},
	{"count": 3, "tier": "silver"},
	{"count": 1, "tier": "gold"},
]

## ── ЦВЕТА ГРЕЙДОВ ──────────────────────────────────────────────────────────
## Заказ владельца: яркие и контрастные вместо грязной бронзы и вылинявшего
## серебра. Прежние 0.72/0.43/0.20 и 0.78/0.83/0.88 на зелёной траве и на
## светлом шлеме читались одинаково бурыми пятнами.
##
## ВЕРХНИЙ ГРЕЙД НАЗЫВАЕТСЯ "gold", А НЕ "red". Ключ переименован вместе с
## цветом, и это исправление старой неправды: значение у него было янтарное
## (0.95, 0.72, 0.18), а имя и комментарий обещали «бордовую, цвета крови».
## Ключ читается только здесь, в VET_STAR_TIERS и VET_TIER_SCALE
const VET_TIER_COLORS := {
	"bronze": Color(0.95, 0.55, 0.15),
	"silver": Color(0.85, 0.95, 1.00),
	"gold":   Color(1.00, 0.82, 0.10),
}

## ОБВОДКА ЗВЕЗДЫ. Один тёмный контур на все грейды: звезда висит и над
## зелёной травой, и над тёмной кроной, и над светлым шлемом, и без обводки
## любой из ярких цветов выше на одном из этих фонов теряется. Цвет не чёрный,
## а чуть синеватый — так он ложится в общую палитру арта
const VET_STAR_OUTLINE := Color(0.08, 0.08, 0.10, 0.9)

## Во сколько раз звезда грейда крупнее базовой. Золотая — заметно больше
## бронзы и серебра (заказ владельца), остальные в базовом размере
const VET_TIER_SCALE := {
	"bronze": 1.0,
	"silver": 1.0,
	"gold":   1.35,
}

## ═══════════════════════════════════════════════════════════════════════════
## ЗНАМЁНА ВЕТЕРАНСТВА — СЕМЬ ГРЕЙДОВ (заказ владельца, авг. 2026)
## ═══════════════════════════════════════════════════════════════════════════
## Звёздочки над отрядом ЗАМЕНЕНЫ знамёнами на копьях. Таблица ниже — един-
## ственный источник правды: по ней рисуется картинка (BannerArt), по ней же
## подписывается ранг в панели отряда (HUD). Картинки в ассетах нет и не будет —
## она строится кодом, как строилась геометрия звезды.
##
## ЧТО ЗНАЧАТ ПОЛЯ:
##   rank        — ранг отряда в родительном падеже: «Отряд ОПЫТНЫХ копейщиков».
##                 Второе слово подставляется из STATS.name_genitive_plural того
##                 рода войск, которому знамя принадлежит (см. veteran_rank_name)
##   shape       — BANNER_PENNANT / BANNER_GUIDON / BANNER_STANDARD
##   cloth       — цвет полотнища
##   chevrons    — сколько лычек
##   chevron_dir — куда смотрят лычки: +1 в полёт (`>`), -1 к древку (`<`)
##   white_tip   — белый наконечник у свободного края
##
## ПОЧЕМУ ЦВЕТ ЛЫЧЕК И БЕЛОГО НАКОНЕЧНИКА ВЫНЕСЕН ИЗ ТАБЛИЦЫ. Он один на все
## грейды и меняться порознь не должен: разноцветные лычки превратили бы шкалу
## званий в набор непохожих значков, по которому нельзя понять, кто старше.
const BANNER_PENNANT  := 0    ## вымпел: сужается к острию
const BANNER_GUIDON   := 1    ## «ласточкин хвост»: клин вырезан из свободного края
const BANNER_STANDARD := 2    ## прямоугольный штандарт с бахромой и гербом

const BANNER_CHEVRON := Color(0.97, 0.97, 0.95)
const BANNER_TIP_COLOR := Color(0.97, 0.97, 0.95)
const BANNER_GOLD := Color(0.93, 0.76, 0.24)

const VET_BANNER_TIERS := [
	{"rank": "опытных",       "shape": BANNER_PENNANT,  "cloth": Color(0.72, 0.11, 0.13),
		"chevrons": 1, "chevron_dir":  1, "white_tip": false},
	{"rank": "закалённых",    "shape": BANNER_PENNANT,  "cloth": Color(0.72, 0.11, 0.13),
		"chevrons": 2, "chevron_dir":  1, "white_tip": false},
	{"rank": "ветеранов",     "shape": BANNER_PENNANT,  "cloth": Color(0.72, 0.11, 0.13),
		"chevrons": 2, "chevron_dir":  1, "white_tip": true},
	{"rank": "элитных",       "shape": BANNER_GUIDON,   "cloth": Color(0.16, 0.34, 0.70),
		"chevrons": 1, "chevron_dir": -1, "white_tip": false},
	{"rank": "знаменитых",    "shape": BANNER_GUIDON,   "cloth": Color(0.16, 0.34, 0.70),
		"chevrons": 2, "chevron_dir": -1, "white_tip": false},
	{"rank": "прославленных", "shape": BANNER_GUIDON,   "cloth": Color(0.16, 0.34, 0.70),
		"chevrons": 2, "chevron_dir": -1, "white_tip": true},
	{"rank": "легендарных",   "shape": BANNER_STANDARD, "cloth": Color(0.55, 0.09, 0.12),
		"chevrons": 0, "chevron_dir":  1, "white_tip": false},
]

## Описание грейда знамени: то же, что лежит в таблице, плюс "key" (номер
## грейда — по нему кэшируется готовая картинка). lvl <= 0 или выше таблицы —
## зажимается в её границы, потому что «уровень выше седьмого» невозможен по
## построению (порогов ровно семь), но проверять это в каждом вызывающем месте
## незачем
static func veteran_banner_tier(lvl: int) -> Dictionary:
	if lvl <= 0 or VET_BANNER_TIERS.is_empty():
		return {}
	var idx: int = clampi(lvl, 1, VET_BANNER_TIERS.size()) - 1
	var d: Dictionary = (VET_BANNER_TIERS[idx] as Dictionary).duplicate()
	d["key"] = idx + 1
	return d

## ПОЛНОЕ НАЗВАНИЕ ОТРЯДА: «Отряд ветеранов копейщиков».
##
## Собирается из ДВУХ конфигов, а не хранится готовой строкой на каждую пару
## «ранг × род войск»: рангов семь, боевых родов шесть, и таблица из сорока
## двух строк разъехалась бы при первой же правке одного из двух списков.
## Неизвестный род войск (в частности рабочий — он вне ветеранства навсегда)
## даёт пустую строку, а не ошибку
static func veteran_rank_name(unit_id: String, lvl: int) -> String:
	var tier: Dictionary = veteran_banner_tier(lvl)
	if tier.is_empty():
		return ""
	var noun: String = String(stat_str(unit_id, "name_genitive_plural", ""))
	if noun == "":
		return "Отряд %s" % String(tier.get("rank", ""))
	return "Отряд %s %s" % [String(tier.get("rank", "")), noun]

## ── ЗНАЧОК РАНГА В ПАНЕЛИ ──────────────────────────────────────────────────
## Панель не может показать знамя: значок там высотой в строку текста, и
## полотнище на нём превратилось бы в цветное пятно. Поэтому в интерфейсе ранг
## показан ЛЫЧКАМИ — тем единственным, что на знамени и так читается числом.
##
## ВЫВОДИТСЯ ИЗ ТОЙ ЖЕ ТАБЛИЦЫ, что и само знамя, и это главное: иначе значок и
## знамя разъехались бы при первой правке одного из них (ровно эта беда уже
## случалась со звездой, когда число звёзд в панели считали отдельно от числа
## звёзд над отрядом).
##
## Белый наконечник получает свою черту, а не пропадает: без неё второй и
## третий грейды выглядели бы в панели одинаково, хотя это разные звания
static func veteran_badge_text(lvl: int) -> String:
	var t: Dictionary = veteran_banner_tier(lvl)
	if t.is_empty():
		return ""
	if int(t.get("shape", BANNER_PENNANT)) == BANNER_STANDARD:
		return "✪"
	var g: String = "❯" if int(t.get("chevron_dir", 1)) > 0 else "❮"
	var out: String = g.repeat(maxi(int(t.get("chevrons", 1)), 1))
	if bool(t.get("white_tip", false)):
		out += "❙"
	return out

## Цвет значка ранга. СВЕТЛЕЕ полотнища на четверть: знамя видно на траве и на
## небе, а значок лежит на тёмном портрете, и глухой бордовый на нём тонет
static func veteran_badge_color(lvl: int) -> Color:
	var t: Dictionary = veteran_banner_tier(lvl)
	if t.is_empty():
		return Color.WHITE
	if int(t.get("shape", BANNER_PENNANT)) == BANNER_STANDARD:
		return BANNER_GOLD
	return (t.get("cloth", Color.WHITE) as Color).lightened(0.25)

## Строковое поле характеристик с дефолтом (числовой брат — stat() выше)
static func stat_str(unit_id: String, key: String, default: String = "") -> String:
	var d: Dictionary = STATS.get(unit_id, {})
	return String(d.get(key, default))

## Описание грейда уровня lvl: {"count": int, "tier": String,
## "color": Color, "scale": float}. lvl <= 0 — пусто (не ветеран)
static func veteran_star_tier(lvl: int) -> Dictionary:
	if lvl <= 0 or VET_STAR_TIERS.is_empty():
		return {}
	var idx: int = mini(lvl, VET_STAR_TIERS.size()) - 1
	var d: Dictionary = VET_STAR_TIERS[idx]
	var tier: String = String(d.get("tier", "bronze"))
	return {
		"count": int(d.get("count", 1)),
		"tier":  tier,
		"color": VET_TIER_COLORS.get(tier, Color.WHITE) as Color,
		"outline": VET_STAR_OUTLINE,
		"scale": float(VET_TIER_SCALE.get(tier, 1.0)),
	}

## Пороги/бонусы конкретного боевого типа. Неизвестный unit_id (в частности
## "worker" — рабочие исключены из ветеранства навсегда) даёт пустые массивы,
## и все функции ниже честно возвращают "нет ветеранства", а не падают
static func _vet_thresholds(unit_type: String) -> Array:
	return (VET_CONFIG.get(unit_type, {}) as Dictionary).get("thresholds", [])

static func _vet_bonuses(unit_type: String) -> Array:
	return (VET_CONFIG.get(unit_type, {}) as Dictionary).get("bonuses", [])

## Максимальный уровень ветеранства (= число порогов) у данного типа юнита
static func max_veteran_level(unit_type: String) -> int:
	return mini(_vet_thresholds(unit_type).size(), _vet_bonuses(unit_type).size())

## Сколько убийств нужно, чтобы получить уровень level (1..max)
static func veteran_threshold(unit_type: String, level: int) -> int:
	var th: Array = _vet_thresholds(unit_type)
	if level < 1 or level > th.size():
		return 0
	return int(th[level - 1])

## Какой уровень заслужен при данном числе убийств (0 — ещё не ветеран)
static func veteran_level_for_kills(unit_type: String, kills: int) -> int:
	var th: Array = _vet_thresholds(unit_type)
	var lvl := 0
	for i in range(mini(th.size(), max_veteran_level(unit_type))):
		if kills >= int(th[i]):
			lvl = i + 1
	return lvl

## ── СОКРАЩЁННАЯ ФОРМА НАГРАДЫ: stat/value ────────────────────────────────────
## Награда за ветеранство описана ТЕМ ЖЕ шаблоном модификаторов, что и узел
## кузницы (см. MODIFIERS): все двенадцать ключей, ненужное нулём. Но панель,
## ИИ и старые стенды спрашивают у награды короткую пару «какая характеристика
## и на сколько», и держать её в таблице ВТОРОЙ РАЗ нельзя — два описания
## одного числа рано или поздно разъедутся. Поэтому пара ВЫВОДИТСЯ из
## модификаторов при чтении, а в таблице её нет вовсе
const _MOD_TO_STAT := {
	"bonus_attack": "attack", "bonus_armor": "armor", "bonus_defense": "defense",
	"bonus_health": "health", "bonus_speed": "speed", "bonus_range": "range",
	"bonus_cooldown": "cooldown", "bonus_spread": "spread", "bonus_push": "push",
	"bonus_morale": "morale", "bonus_carry": "carry", "bonus_gather": "gather",
}

## Короткое имя характеристики по ключу модификатора ("bonus_attack" → "attack")
static func modifier_stat_name(key: String) -> String:
	return String(_MOD_TO_STAT.get(key, key))

## Только НЕНУЛЕВЫЕ модификаторы записи — то, что она реально даёт
static func nonzero_modifiers(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in BONUS_KEYS:
		var key: String = String(k)
		var v: float = float(src.get(key, 0.0))
		if v != 0.0:
			out[key] = v
	return out

## Пять вариантов улучшения на уровне level (1..max) у данного типа юнита.
## Каждый вариант дополняется выведенными stat/value (см. выше)
static func veteran_choices(unit_type: String, level: int) -> Array:
	var b: Array = _vet_bonuses(unit_type)
	if level < 1 or level > b.size():
		return []
	var lst: Array = b[level - 1]
	# Дополняем ОДИН РАЗ и прямо в записи: VET_CONFIG живёт всю партию, а
	# пересобирать список на каждое открытие панели незачем
	for e in lst:
		var d: Dictionary = e
		if d.has("stat"):
			continue
		var nz: Dictionary = nonzero_modifiers(d)
		var first: String = ""
		for k in nz:
			first = String(k)
			break
		d["stat"]  = modifier_stat_name(first) if first != "" else ""
		d["value"] = float(nz.get(first, 0.0)) if first != "" else 0.0
	return lst

## Описание конкретного выбора НА КОНКРЕТНОМ УРОВНЕ (нужно, чтобы посчитать,
## сколько реально дал бонус: value одного и того же id по уровням разное).
## Пусто — такого id на этом уровне нет
static func veteran_choice_at(unit_type: String, level: int, choice_id: String) -> Dictionary:
	for c in veteran_choices(unit_type, level):
		var d: Dictionary = c
		if String(d.get("id", "")) == choice_id:
			return d
	return {}

## Описание выбора по id БЕЗ привязки к уровню — для картинки и названия
## (они у одного id одинаковы на всех уровнях). Берётся первое совпадение
static func veteran_choice_info(unit_type: String, choice_id: String) -> Dictionary:
	for lvl_list in _vet_bonuses(unit_type):
		for c in (lvl_list as Array):
			var d: Dictionary = c
			if String(d.get("id", "")) == choice_id:
				return d
	return {}

## ═══════════════════════════════════════════════════════════════════════════
## ГАРНИЗОН ЗАМКА (CASTLE REFILL & HEAL)
## ═══════════════════════════════════════════════════════════════════════════
## Отряд можно завести внутрь Замка: там раненые лечатся, а погибшие модели
## медленно восстанавливаются, пока отряд снова не станет полным (до squad_size).
##
## РАСЧЁТ ТЕМПА (заказ владельца): отряд из 30 человек, выбитый наполовину
## (15 потерь), доукомплектуется за 15 × GARRISON_REVIVE_SECONDS = 150 c.
## Лечение идёт параллельно с пополнением, но заметно медленнее пополнения.
const GARRISON_SQUAD_LIMIT   := 5     # сколько отрядов помещается в один Замок
## HP в секунду каждой раненой модели, ОДНОВРЕМЕННО у всех моделей отряда
const GARRISON_HEAL_PER_SEC  := 1.0
const GARRISON_REVIVE_SECONDS := 10.0  # секунд на одну восстановленную модель
## Дистанция до Замка, с которой отряд «входит внутрь»
const GARRISON_ENTER_RADIUS  := 5.0
## АВТО-ВЫХОД: отряд, у которого полный состав И полное здоровье, сам
## выкатывается из Замка наружу. false — сидит внутри до клика по слоту
const GARRISON_AUTO_RELEASE  := true

## ═══════════════════════════════════════════════════════════════════════════
## СТРОЙКА И РУИНЫ
## ═══════════════════════════════════════════════════════════════════════════
## Сколько минимум секунд видна стройплощадка, даже если build_time постройки
## равен нулю. Сейчас в BUILDINGS у ВСЕХ зданий build_time = 0 (отладочная
## настройка «строится мгновенно»), и без этого порога картинку стройки
## увидеть было бы негде. Поставить 0 — вернуть прежнее мгновенное появление
const CONSTRUCTION_MIN_SEC := 6.0
## Замок ставится БЕСПЛАТНО и сразу начинает строиться (заказ владельца).
## Сколько это занимает, если build_time замка равен нулю
const CASTLE_BUILD_SEC     := 8.0
## Сколько секунд лежат руины снесённой постройки. 0 — лежат вечно
const RUIN_LIFETIME_SEC    := 0.0

## Размер отряда по типу юнита; рабочий — всегда «отряд из одного»
static func squad_size(unit_id: String) -> int:
	match unit_id:
		"spearman": return SQUAD_SIZE_SPEARMEN
		"archer":   return SQUAD_SIZE_ARCHERS
		"warrior":  return SQUAD_SIZE_SWORDSMEN
		"monk":     return SQUAD_SIZE_MONKS
	# ГОБЛИНЫ ОТВЕЧАЮТ СВОИМ КОНФИГОМ. Спрашивают отсюда все, кто считает
	# «сколько бойцов положено отряду», — в том числе доукомплектование в
	# гарнизоне (Castle.garrison_missing). Если бы здесь осталась единица,
	# отряд гоблинов, ушедший лечиться, вышел бы обратно составом в одного
	var gs: Variant = _GobCfg.SQUAD_SIZE.get(unit_id)
	if gs != null:
		return int(gs)
	return 1

## ═══════════════════════════════════════════════════════════════════════════
## НАЙМ ЮНИТОВ: где, за сколько и какого размера отряд
## ═══════════════════════════════════════════════════════════════════════════
## Ключ первого уровня — building_id, второго — тип юнита.
##   time  — секунды до выхода отряда
##   squad — сколько бойцов в одном заказе. Ссылается на SQUAD_SIZE_* выше:
##           размер отряда задаётся ровно в одном месте
##   cols  — колонн в строю на выходе
##   cost_wood / cost_gold / cost_stone — цена заказа
const TRAINING := {
	"castle": {
		"worker":   {"cost_wood":  50.0, "cost_gold":  0.0, "time":  10.0, "squad": 1, "cols": 4},
		"warrior":  {"cost_wood":  100.0, "cost_gold": 200.0, "time": 30.0, "squad": SQUAD_SIZE_SWORDSMEN, "cols": 5},
		"monk":     {"cost_wood":  20.0, "cost_gold": 30.0, "time": 14.0, "squad": SQUAD_SIZE_MONKS, "cols": 5},
		# Оставлено для ИИ: он нанимает копейщиков и лучников прямо в замке
		"spearman": {"cost_wood": 100.0, "cost_gold": 60.0, "time": 30.0, "squad": SQUAD_SIZE_SPEARMEN, "cols": 5},
		"archer":   {"cost_wood":  200.0, "cost_gold": 300.0, "time": 30.0, "squad": SQUAD_SIZE_ARCHERS, "cols": 5},
	},
	"barracks": {
		"spearman": {"cost_wood": 100.0, "cost_gold": 60.0, "time": 30.0, "squad": SQUAD_SIZE_SPEARMEN, "cols": 5},
		"archer":   {"cost_wood":  200.0, "cost_gold":300.0, "time": 30.0, "squad": SQUAD_SIZE_ARCHERS, "cols": 5},
	},
	"town_center": {
		"worker":   {"cost_wood":  10.0, "cost_gold":  0.0, "time":  8.0, "squad": 1, "cols": 4},
	},
}

## Настройки одного заказа найма (пустой словарь — здание такого не умеет)
static func train_cfg(building_id: String, unit_id: String) -> Dictionary:
	var per_building: Dictionary = TRAINING.get(building_id, {})
	return per_building.get(unit_id, {})

## Цена заказа найма в формате ResourceManager.spend()
static func train_cost(building_id: String, unit_id: String) -> Dictionary:
	var d: Dictionary = train_cfg(building_id, unit_id)
	var cost: Dictionary = {}
	var w: float = d.get("cost_wood",  0.0)
	var g: float = d.get("cost_gold",  0.0)
	var s: float = d.get("cost_stone", 0.0)
	if w > 0.0: cost[Constants.RESOURCE_WOOD]  = w
	if g > 0.0: cost[Constants.RESOURCE_GOLD]  = g
	if s > 0.0: cost[Constants.RESOURCE_STONE] = s
	return cost

## Настройки одной постройки (пустой словарь, если id незнаком)
static func building_cfg(building_id: String) -> Dictionary:
	return BUILDINGS.get(building_id, {})

## Одно числовое поле постройки с дефолтом
static func building_stat(building_id: String, key: String, default: float = 0.0) -> float:
	var d: Dictionary = BUILDINGS.get(building_id, {})
	return d.get(key, default)

## Габарит постройки
static func building_size(building_id: String, default: Vector3 = Vector3(3.0, 2.0, 3.0)) -> Vector3:
	var d: Dictionary = BUILDINGS.get(building_id, {})
	return d.get("size", default)

## Цена постройки в формате ResourceManager.spend(): {тип_ресурса: количество}
static func building_cost(building_id: String) -> Dictionary:
	var d: Dictionary = BUILDINGS.get(building_id, {})
	var cost: Dictionary = {}
	var w: float = d.get("cost_wood",  0.0)
	var g: float = d.get("cost_gold",  0.0)
	var s: float = d.get("cost_stone", 0.0)
	if w > 0.0: cost[Constants.RESOURCE_WOOD]  = w
	if g > 0.0: cost[Constants.RESOURCE_GOLD]  = g
	if s > 0.0: cost[Constants.RESOURCE_STONE] = s
	return cost

## Что рабочий может строить: id в порядке объявления BUILDINGS
static func worker_buildable_ids() -> Array:
	var out: Array = []
	for key in BUILDINGS:
		var bid: String = String(key)
		var d: Dictionary = BUILDINGS[bid]
		if bool(d.get("worker_buildable", false)):
			out.append(bid)
	return out


## ═══════════════════════════════════════════════════════════════════════════
## КУЗНИЦА (BLACKSMITH)
## ═══════════════════════════════════════════════════════════════════════════
## Оставлено для обратной совместимости: параметры самой постройки живут
## в BUILDINGS["smithy"], здесь только то, что относится к исследованиям.
const SMITHY := {
	"name":       "Кузница",
	"health":     500.0,
	"cost_wood":  500.0,
	"cost_stone": 500.0,
	"cost_gold":  500.0,
}

## Время исследования по умолчанию, если у слота не задан свой research_time.
## 0.0 = мгновенная покупка (прежнее поведение).
const DEFAULT_RESEARCH_TIME := 10.0


## ═══════════════════════════════════════════════════════════════════════════
## СЛОТЫ УЛУЧШЕНИЙ КУЗНИЦЫ (UPGRADE SLOTS)
## ═══════════════════════════════════════════════════════════════════════════
## Купленный апгрейд применяется МГНОВЕННО ко всем ТЕКУЩИМ и БУДУЩИМ юнитам
## указанных типов: бонусы читаются вживую при каждом ударе/шаге.
##
## Чтобы добавить своё улучшение — скопируйте любой блок и поменяйте поля:
##
##   id          — уникальный строковый ключ (латиницей, без пробелов)
##   name        — подпись на кнопке в Кузнице
##   desc        — вторая строка на кнопке (что даёт)
##   applies_to  — СПИСОК типов юнитов: ["spearman"], ["archer","warrior"]
##                 или ["all"] — всем боевым юнитам сразу
##   cost_gold / cost_wood / cost_stone — цена (0.0 = ресурс не тратится)
##   requires    — id апгрейда, который нужно купить раньше ("" = без условий)
##   research_time — СЕКУНДЫ исследования в Кузнице. Ресурсы списываются сразу,
##                 бонус применяется по готовности. Поле можно опустить — тогда
##                 берётся DEFAULT_RESEARCH_TIME; 0.0 = купить мгновенно.
##                 Кузница исследует ПО ОДНОЙ технологии за раз.
##   icon        — картинка кнопки (необязательно; пусто — на кнопке подпись)
##
## Бонусы (любой можно опустить — тогда он равен 0):
##   bonus_attack — + к урону удара
##   bonus_armor  — + к броне (плоское снижение входящего урона)
##   bonus_health — + к максимуму HP (текущим юнитам HP поднимается сразу)
##   bonus_speed  — + к скорости движения, м/с
##   bonus_push   — + к push_force (сила продавливания вражеской шеренги)
##   bonus_morale — + к морали (тоже участвует в силе толкания)
const UPGRADE_SLOTS := [
	{
		"id": "spears", "name": "Копья", "desc": "+3 урон копейщикам",
		"applies_to": ["spearman"], "requires": "Bla bla bla",
		"cost_gold": 120.0, "cost_wood": 300.0, "cost_stone": 50.0,
		"research_time": 120.0, "icon": "icon_trap_spears.png",
		"bonus_attack": 3.0, "bonus_push": 0.5,
	},
	{
		"id": "shields", "name": "Щиты", "desc": "+2 броня пехоте",
		"applies_to": ["spearman", "warrior"], "requires": "",
		"cost_gold": 300.0, "cost_wood": 500.0, "cost_stone": 80.0,
		"research_time": 12.0, "icon": "icon_shield.png",
		"bonus_armor": 2.0, "bonus_speed": -0.1,
	},
	{
		"id": "helmets", "name": "Шлемы", "desc": "+15 HP всем",
		"applies_to": ["all"], "requires": "",
		"cost_gold": 380.0, "cost_wood": 400.0, "cost_stone": 260.0,
		"research_time": 10.0, "icon": "icon_heart.png",
		"bonus_health": 10.0, "bonus_morale": 10.0,
	},
	{
		"id": "armor", "name": "Броня", "desc": "+3 броня, чуть медленнее",
		"applies_to": ["all"], "requires": "shields",
		"cost_gold": 1150.0, "cost_wood": 1000.0, "cost_stone": 1200.0,
		"research_time": 20.0, "icon": "icon_broken_sword.png",
		"bonus_armor": 3.0, "bonus_speed": -0.2, "bonus_health": 10.0,
	},
	{
		"id": "swords", "name": "Мечи", "desc": "+5 урон мечникам",
		"applies_to": ["warrior"], "requires": "",
		"cost_gold": 1200.0, "cost_wood": 340.0, "cost_stone": 200.0,
		"research_time": 18.0, "icon": "icon_dual_sword.png",
		"bonus_attack": 5.0, "bonus_push": 1.0, "bonus_morale": 15.0,
	},
	{
		"id": "arrows", "name": "Стрелы", "desc": "+4 урон лучникам",
		"applies_to": ["archer"], "requires": "",
		"cost_gold": 590.0, "cost_wood": 1000.0, "cost_stone": 0.0,
		"research_time": 14.0, "icon": "icon_rain_of_arrows.png",
		"bonus_attack": 4.0,
	},
	{
		"id": "boots", "name": "Сапоги", "desc": "+0.4 скорость всем",
		"applies_to": ["all"], "requires": "",
		"cost_gold": 600.0, "cost_wood": 80.0, "cost_stone": 0.0,
		"research_time": 10.0, "icon": "icon_luck_horseshoe.png",
		"bonus_speed": 0.4,
	},
	{
		"id": "banner", "name": "Знамя", "desc": "+10 мораль, +2 напор",
		"applies_to": ["all"], "requires": "helmets",
		"cost_gold": 1800.0, "cost_wood": 360.0, "cost_stone": 300.0,
		"research_time": 220.0, "icon": "icon_might.png",
		"bonus_morale": 10.0, "bonus_push": 2.0,
	},
]

## Сколько секунд исследуется слот (поле research_time или DEFAULT_RESEARCH_TIME)
static func upgrade_research_time(slot: Dictionary) -> float:
	return maxf(float(slot.get("research_time", DEFAULT_RESEARCH_TIME)), 0.0)

## Все ключи бонусов — по ним GameManager накапливает суммы.
##
## ДВА ПОСЛЕДНИХ — ЭКОНОМИЧЕСКИЕ, ветка рабочего в кузнице (forge_config.UNITS.worker):
##   bonus_carry  — прибавка к грузу за одну ходку (Worker.gather_amount)
##   bonus_gather — СЕКУНДЫ ДОЛОЙ из цикла добычи (Worker._cycle_time). Знак тут
##                  такой же, как у всех: положительное значение — это хорошо,
##                  просто вычитается, а не прибавляется. Иначе балансная
##                  таблица держала бы один ключ с обратным знаком, и в ней
##                  рано или поздно ошиблись бы
## Список — ЕДИНСТВЕННОЕ место, где ключ объявляется: GameManager копит суммы,
## а всплывающие окна HUD печатают строки, перебирая именно его
## ═══════════════════════════════════════════════════════════════════════════
## ЕДИНЫЙ ШАБЛОН МОДИФИКАТОРОВ — ОДИН НА ВСЮ ИГРУ
## ═══════════════════════════════════════════════════════════════════════════
## Здесь перечислены ВСЕ модификаторы, какие в игре есть. Любой узел кузницы и
## любая награда за ветеранство несут ЭТОТ ЖЕ набор ключей целиком: то, что узел
## не даёт, стоит нулём. Смысл ровно в правке баланса вручную — чтобы добавить
## узлу дальность, не надо помнить, как называется ключ и куда его дописать:
## строка уже есть, в ней ноль, замените его числом.
##
## ЗНАК ВЕЗДЕ ОДИН: положительное значение — это ХОРОШО. Там, где по смыслу надо
## уменьшить (перезарядка, разброс, цикл добычи), число вычитается в коде, а в
## таблице стоит со знаком плюс. Одна колонка с обратным знаком в балансной
## таблице — гарантированная ошибка при правке.
##
##   bonus_attack    — прибавка к урону удара
##   bonus_armor     — прибавка к броне (гасит входящий урон)
##   bonus_defense   — прибавка к защите (второй слагаемый той же формулы)
##   bonus_health    — прибавка к запасу HP (выдаётся сразу и живым бойцам)
##   bonus_speed     — прибавка к скорости передвижения, м/с
##   bonus_range     — прибавка к ДАЛЬНОСТИ атаки, м
##   bonus_cooldown  — СЕКУНД ДОЛОЙ с перезарядки удара (то же, что «скорость
##                     атаки»), пол — MIN_COOLDOWN
##   bonus_spread    — НАСКОЛЬКО ПЛОТНЕЕ ложится стрельба: доля 0..1, на которую
##                     срезается случайный разброс стрелка (0.25 = «на четверть
##                     кучнее»). Ближнего боя не касается
##   bonus_push      — прибавка к напору в свалке стенка-на-стенку
##   bonus_morale    — прибавка к морали
##   bonus_carry     — прибавка к грузу рабочего за одну ходку
##   bonus_gather    — СЕКУНД ДОЛОЙ из цикла добычи, пол — Worker.MIN_CYCLE_TIME
##
## Порядок ключей здесь — это порядок строк во всплывающих окнах.
const MODIFIERS := {
	"bonus_attack":   0.0,
	"bonus_armor":    0.0,
	"bonus_defense":  0.0,
	"bonus_health":   0.0,
	"bonus_speed":    0.0,
	"bonus_range":    0.0,
	"bonus_cooldown": 0.0,
	"bonus_spread":   0.0,
	"bonus_push":     0.0,
	"bonus_morale":   0.0,
	"bonus_carry":    0.0,
	"bonus_gather":   0.0,
}

## Нижний предел перезарядки: bonus_cooldown не может ускорить удар до нуля
const MIN_COOLDOWN := 0.25


## ═══════════════════════════════════════════════════════════════════════════
## БАЛЛИСТИКА ЛУЧНИКА — ВСЕ ЧИСЛА ЗДЕСЬ, В КОДЕ ТОЛЬКО ФОРМУЛА
## ═══════════════════════════════════════════════════════════════════════════
## ARCHER_LEAD_FACTOR — доля честного упреждения, которую стрелок реально
## выносит вперёд: точка = позиция цели + скорость × время_полёта × фактор.
##
## Значение 0.08 — заказ владельца (было 0.65) и оно подтверждается картинкой.
## Полное упреждение при дальности 20 м и скорости стрелы 9 м/с даёт время
## полёта ~2.2 с; бегущая цель за это время проходит ~9 м, и стрелы ложились
## ЗА ПОЛТОРА КОРПУСА ВПЕРЕДИ строя — на скриншотах владельца это «дорога из
## стрел» в чистом поле рядом с противником. Промахи по бегущему при малом
## упреждении никуда не деваются: за них отвечает разброс SCATTER_PER_SPEED,
## и это ровно то, что просили сохранить.
const ARCHER_LEAD_FACTOR := 0.08
## Потолок выноса в метрах. Даже при странных скоростях цели упреждение не
## имеет права увести точку прицеливания в пустое поле
const ARCHER_LEAD_MAX := 2.5

## ── КУЧНОСТЬ И ТЕМП ПО ВЫУЧКЕ ОТРЯДА ───────────────────────────────────────
## Индекс — уровень ветеранства отряда (0 = новобранцы). Значение сверх
## последней записи держится последним, как и в лестнице звёздочек.
##   spread   — МНОЖИТЕЛЬ разброса: у новобранцев шире, у ветеранов кучнее
##   fire     — МНОЖИТЕЛЬ ТЕМПА стрельбы (кулдаун делится на него)
## Это отдельная лестница, а не bonus_spread/bonus_cooldown кузницы: те
## складываются по фракции, а эти зарабатывает КОНКРЕТНЫЙ отряд в бою
const ARCHER_DRILL := [
	{"spread": 1.35, "fire": 0.85},   # 0 — новобранцы: шире и медленнее
	{"spread": 1.20, "fire": 0.92},
	{"spread": 1.08, "fire": 0.97},
	{"spread": 1.00, "fire": 1.00},   # 3 — уставная норма
	{"spread": 0.90, "fire": 1.06},
	{"spread": 0.82, "fire": 1.12},
	{"spread": 0.74, "fire": 1.18},
	{"spread": 0.66, "fire": 1.25},   # 7 — золотая звезда
]

## Один ряд лестницы выучки по уровню отряда
static func archer_drill(level: int) -> Dictionary:
	if ARCHER_DRILL.is_empty():
		return {"spread": 1.0, "fire": 1.0}
	return ARCHER_DRILL[clampi(level, 0, ARCHER_DRILL.size() - 1)]

## ── ЗАЛП: МИНИМАЛЬНОЕ НАКРЫТИЕ ─────────────────────────────────────────────
## Радиус «тучи» берётся по габариту вражеского строя, но НИЖЕ этого не падает
## никогда. Иначе залп по одиночке (и по отряду из одного бойца, и по зданию)
## схлопывался в одну точку: все стрелы входили в первого же встречного, а
## девятнадцать из двадцати списывались в уже мёртвого. Залп — это накрытие
## площади, и площадь у него есть всегда
const VOLLEY_MIN_SPREAD := 1.10

## ── СПЛОЧЁННОСТЬ ОТРЯДА ────────────────────────────────────────────────────
## Дальше этого от центра отряда боец не остаётся: если он ничем не занят,
## отряд его подзывает (см. GameManager._cohesion_guard). Не сила и не поле —
## разовый приказ на возврат, редкий и с остыванием, как смыкание рядов
const SQUAD_COHESION_DIST := 14.0
## Как часто отряду разрешено подзывать отставших, мс
const SQUAD_COHESION_COOLDOWN_MS := 2500

## Все ключи бонусов — по ним GameManager накапливает суммы, а всплывающие окна
## HUD печатают строки. Это ровно ключи MODIFIERS, списком: перебирать словарь
## приходится в горячих местах, а массив ключей строится один раз
const BONUS_KEYS := ["bonus_attack", "bonus_armor", "bonus_defense",
					 "bonus_health", "bonus_speed", "bonus_range",
					 "bonus_cooldown", "bonus_spread",
					 "bonus_push", "bonus_morale",
					 "bonus_carry", "bonus_gather"]

## Шаблон с нулями — КОПИЯ, а не сам словарь: вызывающий волен его править
static func zero_modifiers() -> Dictionary:
	return MODIFIERS.duplicate()

## Дополнить запись недостающими ключами шаблона (значения не трогаются).
## Нужен для узлов, которые ещё не расписаны целиком, и для стендов
static func with_all_modifiers(src: Dictionary) -> Dictionary:
	var out: Dictionary = src.duplicate()
	for k in MODIFIERS:
		if not out.has(k):
			out[k] = 0.0
	return out

## ═══════════════════════════════════════════════════════════════════════════
## ОБЗОР (ТУМАН ВОЙНЫ)
## ═══════════════════════════════════════════════════════════════════════════
## Радиус, на котором юнит раскрывает туман, — ТРИ ДАЛЬНОСТИ ЕГО АТАКИ
## (заказ владельца: у лучника с дальностью 20 обзор 60).
##
## VISION_MIN — нижний предел, и он обязателен. У пехоты attack_range ≈ 1.6-1.8,
## то есть по голой формуле мечник видел бы на 5 метров вокруг себя: армия из
## одних мечников шла бы по карте 260×146 практически вслепую, не замечая
## противника, пока тот не упрётся в неё вплотную. Предел не спорит с формулой,
## а лишь не даёт ей выродиться на ближнем бое; лучник и так далеко выше него.
const VISION_MULT := 3.0
const VISION_MIN  := 18.0
## Обзор постройки. У зданий нет дальности атаки, поэтому число своё —
## примерно как у стрелка, чтобы база видела свои подступы
const BUILDING_VISION := 42.0

## Радиус обзора по дальности атаки
static func vision_radius(attack_range: float) -> float:
	return maxf(attack_range * VISION_MULT, VISION_MIN)

## Найти слот улучшения по id (пустой словарь, если нет).
##
## УЗЛЫ ДРЕВА КУЗНИЦЫ — ТОЖЕ СЛОТЫ. forge_config собирает каждый узел в том же
## формате, что и запись UPGRADE_SLOTS (id/name/desc/icon/cost_*/research_time/
## applies_to/bonus_*), поэтому вся машинерия исследований — списание ресурсов,
## очередь кузницы, накопление бонусов, мгновенная добавка HP — работает с ними
## без единой отдельной ветки. Разница только в условии доступа: у старого слота
## это одиночное поле requires, у узла древа — массив prerequisites плюс, для
## колонки D, полный ряд (разбирается в GameManager.can_research).
static func get_upgrade_slot(upgrade_id: String) -> Dictionary:
	for slot in UPGRADE_SLOTS:
		var d: Dictionary = slot
		if String(d.get("id", "")) == upgrade_id:
			return d
	return _Forge.get_node(upgrade_id)

## Стоимость слота в формате ResourceManager.spend(): {тип_ресурса: количество}
static func upgrade_cost(slot: Dictionary) -> Dictionary:
	var cost: Dictionary = {}
	var g: float = slot.get("cost_gold",  0.0)
	var w: float = slot.get("cost_wood",  0.0)
	var s: float = slot.get("cost_stone", 0.0)
	if g > 0.0: cost[Constants.RESOURCE_GOLD]  = g
	if w > 0.0: cost[Constants.RESOURCE_WOOD]  = w
	if s > 0.0: cost[Constants.RESOURCE_STONE] = s
	return cost

## Действует ли слот на юнита данного типа
static func slot_applies_to(slot: Dictionary, unit_id: String) -> bool:
	var lst: Array = slot.get("applies_to", [])
	for e in lst:
		var s: String = String(e)
		if s == "all" or s == unit_id:
			return true
	return false
