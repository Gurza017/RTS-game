# Заметки к scripts/ai_start_army_limit.gd (сняты 27.10.2026)

Поведение красного ИИ (люди): лимиты, тактики, отход, рейды, башни, кузница.
Только параметры, без `class_name` — подключение
`const _AICfg := preload("res://scripts/ai_start_army_limit.gd")`. Спавн и
тайминги живут в `scripts/spawn_config.gd`, сюда приходят ссылками
`const X := _Spawn.AI_X`. Первый съём пояснений был 14.09.2026 — полный текст
тех комментариев лежит в `docs/CONFIG_NOTES_2026-09-14.md`, раздел
`scripts/ai_start_army_limit.gd`; здесь — то, что оставалось в файле до
27.10.2026, плюс карта дублей-ссылок.

## Дубли-ссылки на spawn_config (кандидаты на упрощение; удалять нельзя)
Каждая пара — `ai_start_army_limit.X := _Spawn.Y`, числа живут только в
`spawn_config`. Читатели (`EnemyAI`, `RedAI`, `HomeGuard`, `Main`,
`game_difficulty_config`) ходят через `_AICfg.X`, поэтому ссылки — не мусор,
а точка подключения; упрощать можно лишь переводом читателей на `_Spawn`.

| ai_start_army_limit | spawn_config |
|---|---|
| SQUAD_LIMIT | AI_SQUAD_LIMIT |
| WORKER_LIMIT | AI_WORKER_LIMIT |
| START_WORKERS | AI_START_WORKERS |
| START_SQUADS | AI_START_SQUADS |
| AI_ASSAULT_AT_SEC | AI_ASSAULT_AT_SEC |
| AI_TRUCE_SEC | AI_TRUCE_SEC |
| MINE_SQUADS | AI_MINE_SQUADS |
| AI_TOWERS | AI_TOWERS |
| AI_HOUSES | AI_HOUSES |
| AI_FOOD_RESERVE | AI_FOOD_RESERVE |
| AI_WORKER_FLOOR | AI_WORKER_FLOOR |
| AI_WORKER_REBUILD_MIN | AI_WORKER_REBUILD_MIN |
| AI_REBUILD_SITES | AI_REBUILD_SITES |
| AI_REBUILD_CREW | AI_REBUILD_CREW |
| AI_REBUILD_CASTLE_FREE | AI_REBUILD_CASTLE_FREE |
| AI_REBUILD_REFUGEE_WAVES | AI_REBUILD_REFUGEE_WAVES |
| RETALIATION_LEND_MIN_LEVEL | AI_RETALIATION_LEND_MIN_LEVEL |
| HOME_DEFENSE_ENABLED | AI_HOME_DEFENSE_ENABLED |
| HOME_TOWERS | AI_HOME_TOWERS |
| HOME_TOWER_ARCHERS | AI_HOME_TOWER_ARCHERS |
| HOME_CASTLE_ARCHERS | AI_HOME_CASTLE_ARCHERS |
| HOME_GUARD_SQUADS | AI_HOME_GUARD_SQUADS |
| HOME_GUARD_DEPTH | AI_HOME_GUARD_DEPTH |
| HOME_GUARD_GAP | AI_HOME_GUARD_GAP |
| HOME_GUARD_ZONE | AI_HOME_GUARD_ZONE |
| HOME_GUARD_WAKE_FOES | AI_HOME_GUARD_WAKE_FOES |
| HOME_GUARD_HIT_SEC | AI_HOME_GUARD_HIT_SEC |
| HOME_GUARD_CALM_SEC | AI_HOME_GUARD_CALM_SEC |
| HOME_GUARD_TICK_SEC | AI_HOME_GUARD_TICK_SEC |
| HOME_GUARD_HOME_R | AI_HOME_GUARD_HOME_R |
| HOME_GUARD_HOME_RETRY_SEC | AI_HOME_GUARD_HOME_RETRY_SEC |
| HOME_GUARD_HEAL_FRAC | AI_HOME_GUARD_HEAL_FRAC |
| HOME_GUARD_WAVE_SQUADS | AI_HOME_GUARD_WAVE_SQUADS |
| HOME_GUARD_WAVE_GAP_SEC | AI_HOME_GUARD_WAVE_GAP_SEC |
| HOME_RING_DIST | AI_HOME_RING_DIST |
| HOME_RING_CLEAR | AI_HOME_RING_CLEAR |
| HOME_LINE_DIST | AI_HOME_LINE_DIST |
| HOME_LINE_SQUADS | AI_HOME_LINE_SQUADS |
| HOME_LINE_ROWS | AI_HOME_LINE_ROWS |
| HOME_LINE_GAP | AI_HOME_LINE_GAP |
| HOME_LINE_ROW_GAP | AI_HOME_LINE_ROW_GAP |
| HOME_TOWER_POST_DIST | AI_HOME_TOWER_POST_DIST |
| HOME_GUARD_POST_ZONE | AI_HOME_GUARD_POST_ZONE |
| RETALIATION_LOSSES | AI_RETALIATION_LOSSES |
| RETALIATION_SEC | AI_RETALIATION_SEC |
| RETALIATION_COOLDOWN_SEC | AI_RETALIATION_COOLDOWN_SEC |
| RETALIATION_MIN_SQUADS | AI_RETALIATION_MIN_SQUADS |
| RETALIATION_ADVANTAGE | AI_RETALIATION_ADVANTAGE |
| RETALIATION_SCAN_R | AI_RETALIATION_SCAN_R |
| RETALIATION_HOME_R | AI_RETALIATION_HOME_R |
| RETALIATION_RECHECK_SEC | AI_RETALIATION_RECHECK_SEC |
| REINFORCE_AT_SEC | AI_REINFORCE_AT_SEC |
| REINFORCE_SQUADS | AI_REINFORCE_SQUADS |
| REINFORCE_UNIT | AI_REINFORCE_UNIT |
| REINFORCE_VET | AI_REINFORCE_VET |
| REINFORCE_COLS | AI_REINFORCE_COLS |
| RAID_INTERVAL_SEC | AI_RAID_INTERVAL_SEC |

Итого 57 ссылок из 157 констант файла. Из них четыре не читает никто,
кроме самого определения: `MINE_SQUADS`, `HOME_GUARD_DEPTH`,
`HOME_GUARD_GAP`, `REINFORCE_COLS` (расстановка колонной снята 25.09.2026).

## Разделы файла (старая нумерация)
До 27.10.2026 файл делился линейками на «1. ЛИМИТЫ», «1а. СТАРТОВЫЕ ОТРЯДЫ»,
«2. ГАРНИЗОН И ИЗЛИШКИ», «2b. ОБОРОНИТЕЛЬНЫЙ РЕЖИМ», «3. ТЕМП», «ГЛАВНЫЙ ЦИКЛ
ИИ ЛЮДЕЙ (спринт 17)», «4. ТАКТИКИ», «5. ТАКТИКА НА УРОВНЕ ОТРЯДА», «ХЕЛПЕРЫ»,
«СЦЕНАРИЙ ГЛОБАЛЬНОГО ИИ КАРТЫ (заказ владельца, 13.09.2026) — RedAI.gd».
Пустые двойные линейки сняты, заголовки свёрнуты в одну строку.

## SQUAD_LIMIT / WORKER_LIMIT / START_WORKERS
Единственная ручка масштаба боя: выше лимиты — ИИ копит больше и позже идёт
в атаку. Размер отряда задаётся не здесь, а в `unit_stats_config`
(`squad_size`). `START_WORKERS` — ровно столько же, сколько у игрока: старт
обязан быть равным.

## START_SQUADS / START_VETERAN_PREFERENCE / start_squads()
Пусто по умолчанию — задуманный баланс: ИИ начинает как игрок, армия только
через найм; ранние бесплатные «волны усиления» удалены, стережёт `qa_ai`
(проверка 2). Таблица нужна сценариям и пресету Hard
(`game_difficulty_config`, ключ `ai_start_squads`). Формат строки тот же,
что у орды, раздача наград одна — `Main.grant_squad_veterancy`.
`START_VETERAN_PREFERENCE` — ключи-модификаторы (`MODIFIERS`), читается при
спавне; `AI_VETERAN_PREFERENCE` — короткие имена статов, читается вживую по
ходу партии (`EnemyAI`). Два списка, потому что читаются в разных местах.
`start_squads()` разворачивает `count = 0` в уставной размер, чтобы спавн и
стенды читали одно и то же.

## USE_LAKE_AS_RALLY / RALLY_POINT_OVERRIDE
Старый комментарий обрывался на «Vector3.INF-подобного значения нет,
поэтому» — смысл: нет значения «не задано», поэтому выбор точки сбора сделан
булевой ручкой: true — `Main.ai_rally_point` (центр карты / озеро), false —
`RALLY_POINT_OVERRIDE`.

## AI_MUSTER_BEFORE_ATTACK / MUSTER_FRACTION / MUSTER_RADIUS
«Волна выходит целиком, а не по одному»: отряды рождались по одному и шли на
базу игрока своим ходом — противник перемалывал их поштучно. Атака
начинается, когда 0.75 боевых отрядов стоят в 26 м от точки сбора; признак
«волна пошла» защёлкивается и не рассыпается из-за одного отставшего.

## AI_RECAP_CENTER / RECAP_ARMY_FRACTION / RECAP_ABORT_FRACTION / RECAP_HOME_GUARD
Жалоба владельца: игрок берёт центр, ИИ уходит в глухую оборону навсегда.
Третье макро-состояние `ROLE_RECAP`: центр под игроком и армия набрана (0.8
лимита в бойцах — «от 80 % до 100 %», как заказано) — весь фронт идёт
отбивать центр, дома остаётся 1 отряд на род. Откат в оборону ниже 0.45 —
зазор против метаний на каждом такте.

## AI_ASSAULT_AT_SEC / AI_TRUCE_SEC
13.09.2026: генеральный штурм на 30-й минуте (было 2100 с). Перемирие —
спринт 20, одно число с `goblin_config.PEACE_SEC`; с ТЗ 24.09.2026 — 900 с
(числа в `spawn_config`).

## AI_BUILD_TOWERS / TOWER_BORDER_FRACTION / TOWER_SIDE
Башни на границе: `AI_TOWERS` штук на 0.3 пути от замка к базе игрока,
разнесены вбок на 14 м по очереди слева и справа; строятся после стрелковой.
С 25.10.2026 вышки ИИ ставятся в слоты у двух проходов стены базы
(`Main.ai_base_exits`, `EnemyAI._tower_slots`) — см. CLAUDE.md.

## Восстановление после потерь
ТЗ 14.10.2026, п. 2 — числа и разбор в `docs/config_notes/spawn_config.md`
(`AI_WORKER_REBUILD_MIN`, `AI_REBUILD_*`).

## Стартовая оборона крепости / три уровня / ответный удар
15.09.2026, ТЗ 25.09.2026 и ТЗ 19.09.2026-3 — всё в заметках
`spawn_config.md`; здесь только ссылки.

## AI_RAIDS / RAID_*
Рейды по экономике игрока: раз в `RAID_INTERVAL_SEC` один отряд (мечники —
первыми) идёт бить рабочих и одиночные постройки у базы игрока; при сильном
сопротивлении (12 боевых игрока в 18 м) или по сроку 60 с — отход в замок
лечиться (тот же путь, что у разбитого отряда). Рейд идёт, пока после рудника
остаётся хоть один свободный отряд (`RAID_MIN_FIELD`), а всего отрядов не
меньше 3 (`RAID_MIN_ARMY`) — замок без охраны не оставляем. Добыча ищется в
60 м (`RAID_HUNT_RADIUS`, читает и `RedAI`).

## MAX_QUEUED_ORDERS / REBUILD_BARRACKS_FREE / ARMY_LOST_THRESHOLD
1 заказ — отряды выходят чередой, а не пачкой. Аварийное восстановление:
армия выбита (меньше 10 боевых) — барак отстраивается в приоритете и
бесплатно, чтобы ИИ не залип без войск навсегда.

## TACTICS / FLANK_SPREAD / TACTICS_IN_ORDER
«Боевой порядок один для всех тактик» — заказ владельца, авг. 2026. Прежняя
таблица меняла местами рода («archers_front», «spears_back», «one_mass»);
теперь порядок «копья — луки — фланги» инвариант (проверяет `qa_ai` #6), а
тактики различаются глубиной и шириной. depth > 0 — ближе к игроку вдоль
курса; flank — доля `FLANK_SPREAD` (14 м), знак чередуется по отрядам одного
рода («по обоим краям»). `TACTICS_IN_ORDER` true — по кругу (предсказуемо для
стендов), false — случайно.

## AI_FACE_PLAYER_ARMY / ARMY_AIM_RADIUS
«Фронтом к армии, а не к зданию»: курс волны считался от своего замка к замку
игрока, и в поле стена копий встречала противника боком. Теперь строй
разворачивается относительно армии игрока в 100 м; не видно — цель база.

## AI_RESEARCH_FORGE / AI_FORGE_WEIGHTS / AI_FORGE_EXTRA_BRANCHES
ИИ покупал только плоские слоты и не трогал древо кузницы; теперь оценивает
узлы суммой бонусов с весами и берёт лучший доступный. Веса подобраны так,
чтобы узел любой ветки давал сопоставимый балл (боевой «+3 к урону» — 9,
«+3 к грузу» — 6, «−0.2 с к циклу» — 5). ТЗ 24.09.2026: добавлены доли
промыслов и груза рабочего (`bonus_gather_wood/stone/gold/food`,
`bonus_carry_pct`, `bonus_walk_pct`, `bonus_walk_loaded_pct`; вес — за 0.10
узла). Ветка рабочего качается сверх нанимаемых родов — единственная, что
приносит пользу с первой минуты.

## AI_RESEARCH_GOLD_RESERVE / AI_RESEARCH_WOOD_RESERVE
Золото 300 — резерв под найм, иначе ИИ вкладывал всё в науку.
Дерево 500 — ТЗ 29.09.2026, п. 1: узлы кузницы стоят и дерево, и после
починки еды армию держало оно — склад дерева сидел у нуля
(`qa_red_economy`: 50-110 с 6-й минуты). После мира исследования ждут, пока
на складе не наберётся столько дерева; в мир — не ждут (армии ещё нет).

## AI_BUY_SQUAD_ABILITIES / AI_ABILITY_GOLD_RESERVE
Исследование открывает способность фракции, но каждый отряд докупает её за
золото; без этого ИИ качал бы «Залповый огонь» и не применял. Резерв 500 —
отдельный от исследовательского: способность разовая и дорогая, найм важнее.

## AI_WARRIOR_FLANK / FLANK_* / RANGED_ATTACK_RANGE
Мечник в лоб на строй копейщиков — размен, который ИИ всегда проигрывает; его
дело — обойти стену по дуге 24 м и добраться до стрелков в тылу (ищутся в 55 м
от цели волны, обход начинается с 22 м). Стрелок определяется порогом
дальности 6 м, а не списком типов: новый род стрелков подхватится сам.

## AI_ARCHER_KITE / KITE_*
Лучник в ближнем бою бесполезен: пехота ближе 13 м — отряд отходит на 8 м за
спину прикрывающего отряда и стреляет оттуда.

## AI_SQUAD_RETREAT / RETREAT_STRENGTH / RETREAT_STRENGTH_VETERAN / RETREAT_VETERAN_LEVEL / RETREAT_THREAT_RADIUS
Выбитый отряд в поле доедают бесплатно; в замке он лечится и пополняется
(`Castle.request_garrison`). Порог — доля полного отряда (живые × здоровье)
0.35. «Ветеранов ИИ бережёт раньше, чем новобранцев» — заказ владельца:
«опытный отряд не должен тупо гибнуть; около 30 % и не зажат в плотном бою —
организованно отходить». Отдельное число, а не поднятый общий порог: ранг —
мера вложенного, одно число на двоих означало бы либо разбазаривание
ветеранов, либо оборону, разбегающуюся от царапины. Порог по рангу с уровня
1. Без противника в 26 м отряд не отступает.

## AI_NO_RETREAT_IN_MELEE / AI_NO_RETREAT_RANGE
Завязался в рукопашной — дерётся до конца: отход из контакта глушит авто-агро
и ответный удар, отряд спиной гибнет бесплатно (читает и `ArmyCore`).
`AI_NO_RETREAT_RANGE` — заказ владельца «запрети отмену атаки ближе 15 м к
игроку»; правило заведено, но выключено (0), и это не лень: включённым оно
ломает `qa_ai2` E3/E4 («под угрозой выбитый отряд уходит в замок») по
существу — отступление у ИИ ровно одно, спасение разбитого остатка, и домолотят
его как раз в 15 м от чужой шеренги. Цикл «атака — отход — атака» закрыт
другим: замком `RETREAT_MIN_SEC` и запретом из контакта; замер
`qa_mega_battle` B5 — ноль смен роли за 30 с у двадцати отрядов. Увидит
владелец метания снова — поднимать это число, решая, чем платит спасение
разбитых.

## PHALANX_RANKS / AI_SPEAR_PHALANX_ON_MARCH / CONTACT_RADIUS
4 шеренги; колонки выводятся (`cols = ceil(людей / шеренг)`) — ряды ровные
при любом размере отряда. Стойка ЗАЩИТА на марше опускает копья
(`Spearman._spear_leveled`); без этого блок шёл щетиной вверх. Контакт 24 м:
копейщики в атаку, лучники в кайт.

## RETREAT_MIN_SEC
«Отступление фиксируется по времени»: жалоба владельца на качели «отходим —
снова в атаку — стрелы в спину». Решение держится 12 с; отменяют только
навязанный ближний бой и срок. То же число, что `Unit.RETREAT_LOCK_SEC`:
решение одно, два его замка обязаны кончаться вместе.

## AI_BASE_SCREEN / SCREEN_*
Заслон у базы лицом к противнику: копья в 13 м от замка, луки в 7 м, мечники
в 10 м и на 12 м вбок. «Ширина заслона задаётся не числом, а шагом между
отрядами»: прежняя `SCREEN_WIDTH` 18 м на весь фронт при 7 отрядах давала
центры в 2.6 м — четыреста бойцов сходились в одну точку, цикл «сжатие →
выталкивание → сжатие». Теперь шаг не меньше ширины отряда плюс просвет 2.2 м
(`EnemyAI._screen_step`); фронт не шире 64 м, лишние — вторым эшелоном на 7 м
позади.

## total_army_cap()
Лимит в бойцах, а не в отрядах: доля «80 % лимита» для отвоевания центра
обязана считаться по людям — отряды разных родов разного размера.

## Сценарий глобального ИИ (SORTIE_*, PERIMETER_*, FORD_*, HUNT_*, RECON_*)
Заказ владельца 13.09.2026, `RedAI.gd`. Фазы партии: мир 0-PEACE_SECONDS
(экономика, башни, мелкие вылазки не больше 0.30 армии и только вне баз),
затем борьба за рудник у брода (группа 3 копейщиков + 1 лучники, формируется
при армии не меньше 6 тактических отрядов — иначе съедала бы рудник и рейд у
маленькой армии, `qa_ai_loop` D: рейдов 0), после — «кошмарить соседей»
рейдами; генеральный штурм не раньше `AI_ASSAULT_AT_SEC`. Периметр: пары
копейщики/лучники у башен (копья на 6 м вперёд, луки на 4 м назад, разнос 7 м).
Строй группы: на марше 2 шеренги, ближе 45 м к броду — `PHALANX_RANKS`;
лучники позади на дистанции прикрытия (`tactic_offset`). Вылазки на троллей
ради опыта: раз в 120 с, первая не раньше 240 с (сперва экономика и башни),
не дольше 90 с, запас ниже 0.5 — в замок; разрешены и в мир («стычка вне
баз»). Разведка боем 2 : 1 — каждый 3-й рейд чистая разведка (добежать на
30 м к базе игрока, вскрыть туман, уйти; «дошёл» — 14 м), остальные — по
самым слабым: рабочие, одиночные и раненые отряды.
