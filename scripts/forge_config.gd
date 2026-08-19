extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## КОНФИГУРАЦИЯ КУЗНИЦЫ: ДРЕВО ТЕХНОЛОГИЙ
## ═══════════════════════════════════════════════════════════════════════════
##
## Это БАЛАНСНАЯ ТАБЛИЦА ВЛАДЕЛЬЦА, как и unit_stats_config.gd: цены, время,
## бонусы, тексты, ИКОНКИ и СВЯЗИ правятся здесь и только здесь. Стенды обязаны
## читать числа отсюда, а не хардкодить их у себя.
##
## У каждого типа войск (вкладка в панели кузницы) своя сетка 5 РЯДОВ × 4
## КОЛОНКИ. Колонки A/B/C — ветки характеристик, колонка D — отдельный столбец,
## который открывается не стрелкой, а полностью изученным рядом A+B+C.
##
## ── ОДНА ТАБЛИЦА, А НЕ ДВЕ (переделано по заказу владельца) ─────────────────
## Раньше здесь было ДВЕ таблицы: GRID хранил ФОРМУ графа (иконка, prereq, link)
## одну на все вкладки, а UNITS — только числа. Экономия была настоящая, но у
## неё было следствие, которое и попросили убрать: сетка была ОБЩЕЙ, то есть
## поменять иконку или стрелку у лучника, не тронув мечника, было НЕВОЗМОЖНО в
## принципе — все четыре вкладки рисовались одними и теми же картинками и одним
## и тем же графом. Теперь `icon`, `prereq` и `link` лежат В ЯЧЕЙКЕ каждого
## юнита, рядом со своими числами: дерево каждого рода войск полностью
## самостоятельно, и у рабочего оно честно другой формы, а не копия боевого.
##
## Плата за это известна и принята: форма графа боевых веток повторена четыре
## раза, и при правке САМОГО ДРЕВА её надо править во всех. Взамен любую
## отдельную вкладку можно менять, ничего не ломая у соседей.
##
## ── ID УЗЛА ─────────────────────────────────────────────────────────────────
## "<тип>_<ячейка>": warrior_1a, archer_3d. Идентификатор ГЛОБАЛЬНО уникален,
## поэтому узел древа подставляется в существующую систему исследований как
## обычный слот улучшения (GameManager.researched/researching, накопление
## бонусов, очередь кузницы) без единой дополнительной ветки в их коде.

const ROWS := 5
const COLS := ["a", "b", "c", "d"]
## Колонка спец-способностей: открывается не стрелкой, а полным рядом A+B+C
const ABILITY_COL := "d"

## Порядок вкладок в панели кузницы — он же порядок иконок в верхней полосе.
## РАБОЧИЙ СТОИТ ПЕРВЫМ: экономика раньше войны, и его ветка нужна с первых
## минут партии, тогда как боевые — уже после первой казармы
const UNIT_TABS := ["worker", "warrior", "spearman", "archer", "monk"]

## ═══════════════════════════════════════════════════════════════════════════
## ТАБЛИЦА ВКЛАДОК — ФОРМА И ЧИСЛА ВМЕСТЕ
## ═══════════════════════════════════════════════════════════════════════════
##
## Поля ячейки (любое можно опустить):
##   icon          — файл из unit_stats_config.SMITH_ICONS_DIR (ТОЛЬКО имя!)
##   prereq        — ЯЧЕЙКИ (не id узлов), которые нужно изучить прежде. Пустой
##                   список = узел открыт с самого начала. Разворачивается в
##                   полные id внутри вкладки: "1a" → "warrior_1a".
##                   Условие И: нужны ВСЕ перечисленные, не любой из них.
##   link          — ячейки, с которыми узел соединён ГОРИЗОНТАЛЬНОЙ стрелкой.
##
##                   ЭТО НАСТОЯЩИЙ ПУТЬ ПО ГРАФУ, но АЛЬТЕРНАТИВНЫЙ, а не
##                   дополнительный (заказ владельца: «переход разрешён строго
##                   при наличии видимой стрелки; есть стрелка вбок — можно
##                   шагнуть вбок»). Узел открывается, если изучено ЛИБО всё,
##                   что перечислено в prereq (шаг вниз), ЛИБО хотя бы один
##                   сосед по link (шаг вбок) — см. GameManager.research_blockers.
##
##                   РАЗНИЦА ПРИНЦИПИАЛЬНА. Сделать link ТРЕБОВАНИЕМ (И вместе
##                   с prereq) нельзя: стрелки на макете двусторонние, 2a
##                   требовал бы 2b, а 2b — 2a, и обе ячейки заперты навсегда.
##                   Как АЛЬТЕРНАТИВА (ИЛИ) двусторонность безопасна по
##                   построению: она только разрешает, никогда не запрещает,
##                   поэтому взаимной блокировки не существует в принципе.
##                   Проверяется в qa_forge.
##
##   name          — подпись в карточке и всплывающем окне
##   desc          — строка эффекта («+5 к урону»); показывается крупно
##   cost_gold / cost_wood / cost_stone — цена, списывается при ЗАКАЗЕ
##   research_time — секунды в кузнице
##   bonus_attack / bonus_armor / bonus_health / bonus_speed / bonus_push /
##   bonus_morale / bonus_gather / bonus_carry
##                 — те же ключи, что у обычных улучшений
##                   (unit_stats_config.BONUS_KEYS), копятся так же
##   squad_unlock_cost — сколько золота стоит докупить способность КОНКРЕТНОМУ
##                   отряду уже после её исследования. ИМЕННО ЭТО ПОЛЕ, а не
##                   колонка, делает узел «способностью»: у рабочего колонка D
##                   тоже есть, но покупать её отрядом нечего — это обычные
##                   пассивные улучшения, просто дорогие и за целый ряд
##
## Колонка D зависимостей не перечисляет вовсе: её открывает полный ряд
## (см. ability_row_cells / GameManager.can_research).
##
## Значения ниже — тестовые (заказ владельца: «заполни тестовые параметры»).
const UNITS := {
# ═════════════════════════════════════════════════════════════════════════════
# РАБОЧИЙ — ЭКОНОМИЧЕСКАЯ ВЕТКА
# ═════════════════════════════════════════════════════════════════════════════
# Своя форма графа, а не копия боевой. Экономика ветвится меньше: горизонтальных
# переходов всего две пары (2a↔2b и 4a↔4b) вместо цепочки на каждый ряд —
# «перескочить с вместимости на скорость» это осмысленный размен, а вот прыгать
# туда-сюда каждый ряд незачем.
#
# Колонки: A — ВМЕСТИМОСТЬ (сколько уносит за ходку), B — ТЕМП ДОБЫЧИ (короче
# цикл), C — ХОДЬБА И ЖИВУЧЕСТЬ, D — крупные экономические улучшения за ряд.
"worker": {
	"1a": {"icon": "icon_trader.png", "prereq": [], "link": [],
		"name": "Крепкие корзины", "desc": "+2 к грузу за ходку",
		"cost_gold": 60.0, "cost_wood": 90.0, "cost_stone": 0.0, "research_time": 8.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 2.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_axe.png", "prereq": [], "link": [],
		"name": "Правка инструмента", "desc": "−0.15 с к циклу добычи",
		"cost_gold": 70.0, "cost_wood": 80.0, "cost_stone": 0.0, "research_time": 8.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.15},
	"1c": {"icon": "icon_luck_horseshoe.png", "prereq": [], "link": [],
		"name": "Крепкая обувь", "desc": "+0.2 к скорости",
		"cost_gold": 55.0, "cost_wood": 70.0, "cost_stone": 0.0, "research_time": 7.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.2, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1d": {"icon": "icon_hammer.png", "prereq": [], "link": [],
		"name": "Артельный подряд", "desc": "+3 к грузу, −0.1 с к циклу",
		"cost_gold": 300.0, "cost_wood": 250.0, "cost_stone": 0.0, "research_time": 20.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 3.0, "bonus_gather": 0.1},
	"2a": {"icon": "icon_trader.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Заплечные носилки", "desc": "+3 к грузу за ходку",
		"cost_gold": 140.0, "cost_wood": 180.0, "cost_stone": 0.0, "research_time": 12.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 3.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_hammer.png", "prereq": ["1b"], "link": ["2a"],
		"name": "Закалённые кирки", "desc": "−0.20 с к циклу добычи",
		"cost_gold": 160.0, "cost_wood": 0.0, "cost_stone": 90.0, "research_time": 13.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.2},
	"2c": {"icon": "icon_heart.png", "prereq": ["1c"], "link": [],
		"name": "Сытный паёк", "desc": "+10 к запасу HP",
		"cost_gold": 130.0, "cost_wood": 150.0, "cost_stone": 0.0, "research_time": 11.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 10.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2d": {"icon": "icon_gold.png", "prereq": [], "link": [],
		"name": "Учёт и порядок", "desc": "+4 к грузу, +0.2 к скорости",
		"cost_gold": 420.0, "cost_wood": 320.0, "cost_stone": 0.0, "research_time": 24.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.2, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 4.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_trader.png", "prereq": ["2a"], "link": [],
		"name": "Тачки", "desc": "+4 к грузу за ходку",
		"cost_gold": 260.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 16.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 4.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_axe.png", "prereq": ["2b"], "link": ["3c"],
		"name": "Двуручный топор", "desc": "−0.25 с к циклу добычи",
		"cost_gold": 300.0, "cost_wood": 0.0, "cost_stone": 140.0, "research_time": 17.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.25},
	"3c": {"icon": "icon_luck_horseshoe.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Торные тропы", "desc": "+0.3 к скорости",
		"cost_gold": 240.0, "cost_wood": 260.0, "cost_stone": 0.0, "research_time": 15.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.3, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_drop.png", "prereq": [], "link": [],
		"name": "Артельный обоз", "desc": "+5 к грузу, −0.15 с к циклу",
		"cost_gold": 560.0, "cost_wood": 430.0, "cost_stone": 0.0, "research_time": 28.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 5.0, "bonus_gather": 0.15},
	"4a": {"icon": "icon_gold.png", "prereq": ["3a"], "link": ["4b"],
		"name": "Крытые повозки", "desc": "+5 к грузу за ходку",
		"cost_gold": 420.0, "cost_wood": 400.0, "cost_stone": 0.0, "research_time": 20.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 5.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_hammer.png", "prereq": ["3b"], "link": ["4a"],
		"name": "Рудничный вороток", "desc": "−0.30 с к циклу добычи",
		"cost_gold": 460.0, "cost_wood": 0.0, "cost_stone": 220.0, "research_time": 22.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.3},
	"4c": {"icon": "icon_heart.png", "prereq": ["3c"], "link": [],
		"name": "Артельный лекарь", "desc": "+16 к запасу HP",
		"cost_gold": 380.0, "cost_wood": 340.0, "cost_stone": 0.0, "research_time": 19.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 16.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4d": {"icon": "icon_might.png", "prereq": [], "link": [],
		"name": "Гильдия артелей", "desc": "+6 к грузу, +0.3 к скорости",
		"cost_gold": 760.0, "cost_wood": 600.0, "cost_stone": 0.0, "research_time": 32.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.3, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 6.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_trader.png", "prereq": ["4a"], "link": [],
		"name": "Складские артели", "desc": "+7 к грузу за ходку",
		"cost_gold": 640.0, "cost_wood": 560.0, "cost_stone": 0.0, "research_time": 26.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 7.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_axe.png", "prereq": ["4b"], "link": [],
		"name": "Мастера промысла", "desc": "−0.35 с к циклу добычи",
		"cost_gold": 700.0, "cost_wood": 0.0, "cost_stone": 320.0, "research_time": 28.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.35},
	"5c": {"icon": "icon_luck_horseshoe.png", "prereq": ["4c"], "link": [],
		"name": "Мощёные дороги", "desc": "+0.4 к скорости, +14 HP",
		"cost_gold": 620.0, "cost_wood": 0.0, "cost_stone": 300.0, "research_time": 27.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 14.0, "bonus_speed": 0.4, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_gold.png", "prereq": [], "link": [],
		"name": "Королевский откуп", "desc": "+8 к грузу, −0.2 с к циклу",
		"cost_gold": 1100.0, "cost_wood": 850.0, "cost_stone": 0.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 8.0, "bonus_gather": 0.2},
},
# ═════════════════════════════════════════════════════════════════════════════
# БОЕВЫЕ ВЕТКИ
# ═════════════════════════════════════════════════════════════════════════════
"warrior": {
	"1a": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Щиты", "desc": "+2 к броне",
		"cost_gold": 150.0, "cost_wood": 200.0, "cost_stone": 0.0, "research_time": 10.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 2.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_sword.png", "prereq": [], "link": [],
		"name": "Точило", "desc": "+3 к урону",
		"cost_gold": 180.0, "cost_wood": 0.0, "cost_stone": 60.0, "research_time": 10.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 3.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1c": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Шлемы", "desc": "+15 к запасу HP",
		"cost_gold": 200.0, "cost_wood": 150.0, "cost_stone": 0.0, "research_time": 12.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 15.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1d": {"icon": "icon_dual_sword.png", "prereq": [], "link": [],
		"name": "Град ударов", "desc": "Серия быстрых атак",
		"cost_gold": 900.0, "cost_wood": 0.0, "cost_stone": 300.0, "research_time": 25.0, "squad_unlock_cost": 1000.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_hand.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Наручи", "desc": "+3 к броне",
		"cost_gold": 320.0, "cost_wood": 0.0, "cost_stone": 140.0, "research_time": 14.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 3.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_fire_hand.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Хват огня", "desc": "+5 к урону",
		"cost_gold": 380.0, "cost_wood": 250.0, "cost_stone": 0.0, "research_time": 15.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 5.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_might.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Мощь", "desc": "+1.5 к напору",
		"cost_gold": 340.0, "cost_wood": 0.0, "cost_stone": 120.0, "research_time": 14.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 1.5,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2d": {"icon": "icon_broken_sword.png", "prereq": [], "link": [],
		"name": "Рассечение", "desc": "Удар по площади",
		"cost_gold": 1100.0, "cost_wood": 0.0, "cost_stone": 400.0, "research_time": 28.0, "squad_unlock_cost": 1200.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_luck_horseshoe.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Подкова", "desc": "+0.4 к скорости",
		"cost_gold": 500.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 18.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.4, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_fireball.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Огненный шар", "desc": "+7 к урону",
		"cost_gold": 620.0, "cost_wood": 0.0, "cost_stone": 260.0, "research_time": 20.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 7.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3c": {"icon": "icon_healing_potion.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Зелья", "desc": "+25 к запасу HP",
		"cost_gold": 560.0, "cost_wood": 380.0, "cost_stone": 0.0, "research_time": 19.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 25.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_dual_sword.png", "prereq": [], "link": [],
		"name": "Стальной вихрь", "desc": "Круговой удар",
		"cost_gold": 1400.0, "cost_wood": 0.0, "cost_stone": 520.0, "research_time": 32.0, "squad_unlock_cost": 1500.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_trader.png", "prereq": ["3a"], "link": [],
		"name": "Обозы", "desc": "+20 к морали",
		"cost_gold": 780.0, "cost_wood": 500.0, "cost_stone": 0.0, "research_time": 24.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 20.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_skull.png", "prereq": ["3b"], "link": [],
		"name": "Устрашение", "desc": "+2.5 к напору",
		"cost_gold": 860.0, "cost_wood": 0.0, "cost_stone": 340.0, "research_time": 26.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 2.5,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_gold.png", "prereq": ["3c"], "link": [],
		"name": "Трофеи", "desc": "+30 к запасу HP",
		"cost_gold": 940.0, "cost_wood": 420.0, "cost_stone": 0.0, "research_time": 26.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 30.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4d": {"icon": "icon_demon.png", "prereq": [], "link": [],
		"name": "Кровь берсерка", "desc": "Ярость при ранении",
		"cost_gold": 1700.0, "cost_wood": 0.0, "cost_stone": 700.0, "research_time": 36.0, "squad_unlock_cost": 1800.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_trap.png", "prereq": ["4a"], "link": [],
		"name": "Осадный опыт", "desc": "+5 к броне",
		"cost_gold": 1300.0, "cost_wood": 0.0, "cost_stone": 800.0, "research_time": 34.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 5.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_demon.png", "prereq": ["4b"], "link": [],
		"name": "Чёрный рыцарь", "desc": "+12 к урону",
		"cost_gold": 1600.0, "cost_wood": 0.0, "cost_stone": 900.0, "research_time": 38.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 12.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_dual_sword.png", "prereq": ["4c"], "link": [],
		"name": "Парные клинки", "desc": "+10 урон, +30 мораль",
		"cost_gold": 1800.0, "cost_wood": 700.0, "cost_stone": 0.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 10.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 30.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_trap_spikes.png", "prereq": [], "link": [],
		"name": "Стена копий", "desc": "Отражает натиск",
		"cost_gold": 2200.0, "cost_wood": 0.0, "cost_stone": 1100.0, "research_time": 45.0, "squad_unlock_cost": 2500.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
"spearman": {
	"1a": {"icon": "icon_sword.png", "prereq": [], "link": [],
		"name": "Калёный наконечник", "desc": "+2 к урону",
		"cost_gold": 200.0, "cost_wood": 200.0, "cost_stone": 0.0, "research_time": 20.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Стёганка", "desc": "+2 к броне",
		"cost_gold": 200.0, "cost_wood": 0.0, "cost_stone": 250.0, "research_time": 20.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 2.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1c": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Закалка", "desc": "+12 к запасу HP",
		"cost_gold": 160.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 20.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 12.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1d": {"icon": "icon_trap_spikes.png", "prereq": [], "link": [],
		"name": "Плотный строй", "desc": "Строй держит удар",
		"cost_gold": 200.0, "cost_wood": 0.0, "cost_stone": 360.0, "research_time": 120.0, "squad_unlock_cost": 500.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_hand.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Упор щита", "desc": "+3 к броне",
		"cost_gold": 280.0, "cost_wood": 0.0, "cost_stone": 120.0, "research_time": 13.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 3.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_trap_spears.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Длинное древко", "desc": "+4 к урону",
		"cost_gold": 320.0, "cost_wood": 220.0, "cost_stone": 0.0, "research_time": 14.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 4.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_might.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Слаженность", "desc": "+2 к напору",
		"cost_gold": 300.0, "cost_wood": 0.0, "cost_stone": 100.0, "research_time": 13.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 2.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2d": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Приём копья", "desc": "Контрудар по коннице",
		"cost_gold": 1000.0, "cost_wood": 0.0, "cost_stone": 360.0, "research_time": 27.0, "squad_unlock_cost": 1100.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_luck_horseshoe.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Лёгкий шаг", "desc": "+0.5 к скорости",
		"cost_gold": 460.0, "cost_wood": 280.0, "cost_stone": 0.0, "research_time": 17.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.5, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_fire_hand.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Огненные жала", "desc": "+6 к урону",
		"cost_gold": 580.0, "cost_wood": 0.0, "cost_stone": 240.0, "research_time": 19.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 6.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3c": {"icon": "icon_healing_potion.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Полевой лекарь", "desc": "+22 к запасу HP",
		"cost_gold": 520.0, "cost_wood": 350.0, "cost_stone": 0.0, "research_time": 18.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 22.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_trap.png", "prereq": [], "link": [],
		"name": "Еж", "desc": "Круговая оборона",
		"cost_gold": 1300.0, "cost_wood": 0.0, "cost_stone": 480.0, "research_time": 31.0, "squad_unlock_cost": 1400.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_trader.png", "prereq": ["3a"], "link": [],
		"name": "Снабжение", "desc": "+18 к морали",
		"cost_gold": 720.0, "cost_wood": 460.0, "cost_stone": 0.0, "research_time": 23.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 18.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_might.png", "prereq": ["3b"], "link": [],
		"name": "Боевой клич", "desc": "+3 к напору",
		"cost_gold": 820.0, "cost_wood": 0.0, "cost_stone": 320.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 3.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_gold.png", "prereq": ["3c"], "link": [],
		"name": "Добыча", "desc": "+28 к запасу HP",
		"cost_gold": 900.0, "cost_wood": 400.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 28.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4d": {"icon": "icon_skull.png", "prereq": [], "link": [],
		"name": "Стойкость", "desc": "Не отступает",
		"cost_gold": 1600.0, "cost_wood": 0.0, "cost_stone": 640.0, "research_time": 35.0, "squad_unlock_cost": 1700.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_shield.png", "prereq": ["4a"], "link": [],
		"name": "Ветеранский строй", "desc": "+4 к броне",
		"cost_gold": 1200.0, "cost_wood": 0.0, "cost_stone": 760.0, "research_time": 33.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 4.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_trap_spears.png", "prereq": ["4b"], "link": [],
		"name": "Копьё смерти", "desc": "+10 к урону",
		"cost_gold": 1500.0, "cost_wood": 0.0, "cost_stone": 860.0, "research_time": 37.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 10.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_dual_sword.png", "prereq": ["4c"], "link": [],
		"name": "Двойной удар", "desc": "+8 урон, +25 мораль",
		"cost_gold": 1700.0, "cost_wood": 660.0, "cost_stone": 0.0, "research_time": 39.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 8.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 25.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_trap_spikes.png", "prereq": [], "link": [],
		"name": "Фаланга", "desc": "Неприступный строй",
		"cost_gold": 2100.0, "cost_wood": 0.0, "cost_stone": 1000.0, "research_time": 44.0, "squad_unlock_cost": 2400.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
"archer": {
	"1a": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Лёгкий доспех", "desc": "+1 к броне",
		"cost_gold": 110.0, "cost_wood": 160.0, "cost_stone": 0.0, "research_time": 8.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_bow.png", "prereq": [], "link": [],
		"name": "Тугая тетива", "desc": "+3 к урону",
		"cost_gold": 150.0, "cost_wood": 120.0, "cost_stone": 0.0, "research_time": 9.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 3.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1c": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Выучка", "desc": "+10 к запасу HP",
		"cost_gold": 140.0, "cost_wood": 130.0, "cost_stone": 0.0, "research_time": 9.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 10.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# ── ЗАЛПОВЫЙ ОГОНЬ: ЕДИНСТВЕННАЯ ПОКА СПОСОБНОСТЬ-ПЕРЕКЛЮЧАТЕЛЬ ─────────
	# toggle = true означает, что купленная способность не срабатывает сама, а
	# ВКЛЮЧАЕТСЯ игроком и висит режимом (как «стена щитов» у мечника). Признак
	# держится в конфиге, а не проверкой «если id == archer_1d» в панели: панель
	# не должна знать имён способностей, иначе следующая такая же потребует
	# правки интерфейса
	"1d": {"icon": "icon_rain_of_arrows.png", "prereq": [], "link": [], "toggle": true,
		"name": "Залповый огонь", "desc": "Отряд бьёт разом, кучно, по центру строя",
		"cost_gold": 850.0, "cost_wood": 400.0, "cost_stone": 0.0, "research_time": 24.0, "squad_unlock_cost": 1000.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 5.0,
		"bonus_cooldown": 1.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_hand.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Наручи лучника", "desc": "+2 к броне",
		"cost_gold": 260.0, "cost_wood": 0.0, "cost_stone": 100.0, "research_time": 12.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 2.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_fire_hand.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Зажигательные", "desc": "+5 к урону",
		"cost_gold": 360.0, "cost_wood": 240.0, "cost_stone": 0.0, "research_time": 14.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 5.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_luck_horseshoe.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Твёрдая рука", "desc": "+0.3 к скорости",
		"cost_gold": 280.0, "cost_wood": 180.0, "cost_stone": 0.0, "research_time": 12.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.3, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2d": {"icon": "icon_crossbow.png", "prereq": [], "link": [],
		"name": "Прицельный", "desc": "Выстрел по командиру",
		"cost_gold": 1050.0, "cost_wood": 460.0, "cost_stone": 0.0, "research_time": 27.0, "squad_unlock_cost": 1150.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_luck_horseshoe.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Скорый шаг", "desc": "+0.6 к скорости",
		"cost_gold": 440.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 16.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.6, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_fireball.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Огненный залп", "desc": "+7 к урону",
		"cost_gold": 600.0, "cost_wood": 380.0, "cost_stone": 0.0, "research_time": 19.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 7.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3c": {"icon": "icon_healing_potion.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Настойки", "desc": "+20 к запасу HP",
		"cost_gold": 500.0, "cost_wood": 340.0, "cost_stone": 0.0, "research_time": 17.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 20.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_rain_of_arrows.png", "prereq": [], "link": [],
		"name": "Ливень стрел", "desc": "Обстрел по площади",
		"cost_gold": 1350.0, "cost_wood": 620.0, "cost_stone": 0.0, "research_time": 31.0, "squad_unlock_cost": 1450.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_trader.png", "prereq": ["3a"], "link": [],
		"name": "Обозники", "desc": "+16 к морали",
		"cost_gold": 700.0, "cost_wood": 440.0, "cost_stone": 0.0, "research_time": 22.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 16.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_crossbow.png", "prereq": ["3b"], "link": [],
		"name": "Бронебойные", "desc": "+9 к урону",
		"cost_gold": 880.0, "cost_wood": 0.0, "cost_stone": 300.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 9.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_gold.png", "prereq": ["3c"], "link": [],
		"name": "Награды", "desc": "+24 к запасу HP",
		"cost_gold": 860.0, "cost_wood": 380.0, "cost_stone": 0.0, "research_time": 24.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 24.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4d": {"icon": "icon_drop.png", "prereq": [], "link": [],
		"name": "Отравленные", "desc": "Урон по времени",
		"cost_gold": 1650.0, "cost_wood": 700.0, "cost_stone": 0.0, "research_time": 34.0, "squad_unlock_cost": 1750.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_trap.png", "prereq": ["4a"], "link": [],
		"name": "Мастер засад", "desc": "+3 к броне",
		"cost_gold": 1150.0, "cost_wood": 0.0, "cost_stone": 700.0, "research_time": 32.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 3.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_skull.png", "prereq": ["4b"], "link": [],
		"name": "Тень", "desc": "+13 к урону",
		"cost_gold": 1550.0, "cost_wood": 820.0, "cost_stone": 0.0, "research_time": 36.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 13.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_tripple_arrows_2.png", "prereq": ["4c"], "link": [],
		"name": "Двойной выстрел", "desc": "+11 урон, +20 мораль",
		"cost_gold": 1750.0, "cost_wood": 720.0, "cost_stone": 0.0, "research_time": 38.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 11.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 20.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_tripple_arrows_2.png", "prereq": [], "link": [],
		"name": "Стрелы-шипы", "desc": "Пробивает строй",
		"cost_gold": 2000.0, "cost_wood": 1000.0, "cost_stone": 0.0, "research_time": 43.0, "squad_unlock_cost": 2300.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
"monk": {
	"1a": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Ряса", "desc": "+1 к броне",
		"cost_gold": 130.0, "cost_wood": 150.0, "cost_stone": 0.0, "research_time": 9.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_hand.png", "prereq": [], "link": [],
		"name": "Посох", "desc": "+2 к урону",
		"cost_gold": 150.0, "cost_wood": 110.0, "cost_stone": 0.0, "research_time": 9.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1c": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Пост", "desc": "+14 к запасу HP",
		"cost_gold": 180.0, "cost_wood": 160.0, "cost_stone": 0.0, "research_time": 10.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 14.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1d": {"icon": "icon_healing_potion.png", "prereq": [], "link": [],
		"name": "Исцеление", "desc": "Лечит раненых рядом",
		"cost_gold": 950.0, "cost_wood": 380.0, "cost_stone": 0.0, "research_time": 26.0, "squad_unlock_cost": 1200.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_might.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Вериги", "desc": "+2 к броне",
		"cost_gold": 300.0, "cost_wood": 0.0, "cost_stone": 110.0, "research_time": 13.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 2.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_fire_hand.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Длань огня", "desc": "+4 к урону",
		"cost_gold": 340.0, "cost_wood": 230.0, "cost_stone": 0.0, "research_time": 14.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 4.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_trader.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Проповедь", "desc": "+22 к морали",
		"cost_gold": 320.0, "cost_wood": 200.0, "cost_stone": 0.0, "research_time": 13.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 22.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2d": {"icon": "icon_drop.png", "prereq": [], "link": [],
		"name": "Благословение", "desc": "Щит союзникам",
		"cost_gold": 1150.0, "cost_wood": 420.0, "cost_stone": 0.0, "research_time": 29.0, "squad_unlock_cost": 1300.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_luck_horseshoe.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Странствия", "desc": "+0.5 к скорости",
		"cost_gold": 480.0, "cost_wood": 290.0, "cost_stone": 0.0, "research_time": 17.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.5, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_fireball.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Кара", "desc": "+6 к урону",
		"cost_gold": 590.0, "cost_wood": 0.0, "cost_stone": 230.0, "research_time": 19.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 6.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3c": {"icon": "icon_healing_potion.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Целебный отвар", "desc": "+26 к запасу HP",
		"cost_gold": 540.0, "cost_wood": 360.0, "cost_stone": 0.0, "research_time": 18.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 26.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Воскрешение", "desc": "Поднимает павшего",
		"cost_gold": 1450.0, "cost_wood": 560.0, "cost_stone": 0.0, "research_time": 33.0, "squad_unlock_cost": 1600.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_gold.png", "prereq": ["3a"], "link": [],
		"name": "Обитель", "desc": "+24 к морали",
		"cost_gold": 760.0, "cost_wood": 480.0, "cost_stone": 0.0, "research_time": 23.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 24.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_skull.png", "prereq": ["3b"], "link": [],
		"name": "Изгнание", "desc": "+8 к урону",
		"cost_gold": 840.0, "cost_wood": 0.0, "cost_stone": 310.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 8.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_trader.png", "prereq": ["3c"], "link": [],
		"name": "Пожертвования", "desc": "+32 к запасу HP",
		"cost_gold": 920.0, "cost_wood": 410.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 32.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4d": {"icon": "icon_drop.png", "prereq": [], "link": [],
		"name": "Святая вода", "desc": "Снимает проклятия",
		"cost_gold": 1750.0, "cost_wood": 680.0, "cost_stone": 0.0, "research_time": 35.0, "squad_unlock_cost": 1900.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_shield.png", "prereq": ["4a"], "link": [],
		"name": "Схима", "desc": "+4 к броне",
		"cost_gold": 1250.0, "cost_wood": 0.0, "cost_stone": 740.0, "research_time": 33.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 4.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_demon.png", "prereq": ["4b"], "link": [],
		"name": "Экзорцизм", "desc": "+11 к урону",
		"cost_gold": 1580.0, "cost_wood": 0.0, "cost_stone": 840.0, "research_time": 37.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 11.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_dual_sword.png", "prereq": ["4c"], "link": [],
		"name": "Клинок веры", "desc": "+9 урон, +35 мораль",
		"cost_gold": 1780.0, "cost_wood": 690.0, "cost_stone": 0.0, "research_time": 39.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 9.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 35.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_fireball.png", "prereq": [], "link": [],
		"name": "Небесная кара", "desc": "Удар с небес",
		"cost_gold": 2250.0, "cost_wood": 1050.0, "cost_stone": 0.0, "research_time": 46.0, "squad_unlock_cost": 2600.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
}

## ═══════════════════════════════════════════════════════════════════════════
## СБОРКА
## ═══════════════════════════════════════════════════════════════════════════

## Кэш собранных деревьев: тип → Array узлов в порядке 1a,1b,1c,1d,2a,…
## Собирается один раз за запуск: панель кузницы перестраивается на каждый
## клик по вкладке, а сборка 20 ячеек там ни к чему
static var _tree_cache: Dictionary = {}
## id узла → готовый узел, для быстрого поиска из GameManager
static var _node_cache: Dictionary = {}

## Полный id узла по типу войск и ячейке: ("warrior", "3b") → "warrior_3b"
static func node_id(unit_id: String, cell: String) -> String:
	return "%s_%s" % [unit_id, cell]

## Ячейки в порядке чтения сетки: 1a,1b,1c,1d,2a,…,5d
static func cells() -> Array:
	var out: Array = []
	for r in range(1, ROWS + 1):
		for c in COLS:
			out.append("%d%s" % [r, String(c)])
	return out

## Три ячейки характеристик того же ряда, что и данная ячейка колонки D.
## Именно их полное изучение открывает саму D (см. GameManager.can_research)
static func ability_row_cells(cell: String) -> Array:
	if cell.length() < 2 or not cell.ends_with(ABILITY_COL):
		return []
	var row: String = cell.substr(0, cell.length() - 1)
	var out: Array = []
	for c in COLS:
		var col: String = String(c)
		if col != ABILITY_COL:
			out.append(row + col)
	return out

## Готовое древо одной вкладки: список узлов, каждый — самодостаточный словарь
## в формате слота улучшения (unit_stats_config.get_upgrade_slot вернёт его же).
##
## ЕДИНСТВЕННЫЙ ЧИТАТЕЛЬ UNITS. Панель кузницы, стрелки, всплывающие окна и
## GameManager берут узел ОТСЮДА, а не лазают в таблицу сами: иначе «иконку
## берём из UNITS» пришлось бы повторить в пяти местах и они бы разъехались.
## Разворачивание ячеек в полные id и вычисление ворот ряда живут тоже здесь
static func tree(unit_id: String) -> Array:
	if _tree_cache.has(unit_id):
		return _tree_cache[unit_id]
	var per_unit: Dictionary = UNITS.get(unit_id, {})
	var out: Array = []
	for c in cells():
		var cell: String = String(c)
		var data: Dictionary = per_unit.get(cell, {})
		var node: Dictionary = data.duplicate()
		node["id"]       = node_id(unit_id, cell)
		node["cell"]     = cell
		node["row"]      = int(cell.substr(0, cell.length() - 1))
		node["col"]      = cell.substr(cell.length() - 1, 1)
		node["unit"]     = unit_id
		node["icon"]     = String(data.get("icon", ""))
		# Бонусы копятся ТОЛЬКО своему типу войск: вкладка мечника не должна
		# усиливать лучников (в отличие от старых общих слотов с ["all"])
		node["applies_to"] = [unit_id]
		# Зависимости — полными id, чтобы GameManager не знал про ячейки
		var reqs: Array = []
		for p in data.get("prereq", []):
			reqs.append(node_id(unit_id, String(p)))
		node["prerequisites"] = reqs
		# ГОРИЗОНТАЛЬНЫЕ СТРЕЛКИ — ДВА ПРЕДСТАВЛЕНИЯ ОДНОГО И ТОГО ЖЕ.
		# "link" остаётся ЯЧЕЙКАМИ: по ним рисуются стрелки внутри сетки, а
		# сетка мыслит ячейками. "link_ids" — те же связи ПОЛНЫМИ id: по ним
		# GameManager проверяет доступность (см. research_blockers), а он про
		# ячейки не знает и знать не должен
		var links: Array = []
		var link_ids: Array = []
		for l in data.get("link", []):
			links.append(String(l))
			link_ids.append(node_id(unit_id, String(l)))
		node["link"] = links
		node["link_ids"] = link_ids
		if node["col"] == ABILITY_COL:
			# СПОСОБНОСТЬЮ УЗЕЛ ДЕЛАЕТ ЦЕНА ВЫКУПА, А НЕ КОЛОНКА. У боевых веток
			# это одно и то же (в каждой их ячейке D есть squad_unlock_cost), а
			# вот у рабочего колонка D — обычные пассивные улучшения: покупать
			# способность «артели» отдельным отрядом бессмысленно, и кнопка
			# выкупа за нулевую цену в его панели была бы просто мусором
			if float(data.get("squad_unlock_cost", 0.0)) > 0.0:
				node["is_unit_ability"] = true
			# Ворота ряда — у ВСЕЙ колонки D, независимо от выкупа: это правило
			# раскладки («колонку D открывает закрытый ряд»), а не свойство
			# способности
			var gate: Array = []
			for g in ability_row_cells(cell):
				gate.append(node_id(unit_id, String(g)))
			node["row_gate"] = gate
		out.append(node)
		_node_cache[String(node["id"])] = node
	_tree_cache[unit_id] = out
	return out

## Узел по глобальному id ({} — такого нет). Разбирает id сам, чтобы не
## перебирать все деревья
static func get_node(id: String) -> Dictionary:
	if _node_cache.has(id):
		return _node_cache[id]
	var sep: int = id.rfind("_")
	if sep <= 0:
		return {}
	var unit_id: String = id.substr(0, sep)
	if not UNITS.has(unit_id):
		return {}
	tree(unit_id)               # собирает и наполняет _node_cache
	return _node_cache.get(id, {})

## Все узлы всех вкладок (для стендов и общих проверок)
static func all_nodes() -> Array:
	var out: Array = []
	for u in UNIT_TABS:
		out.append_array(tree(String(u)))
	return out

## Способности колонки D для данного типа войск — то, что отряд может докупить
static func ability_nodes(unit_id: String) -> Array:
	var out: Array = []
	for n in tree(unit_id):
		var d: Dictionary = n
		if bool(d.get("is_unit_ability", false)):
			out.append(d)
	return out

## Сколько золота стоит докупить способность конкретному отряду
static func squad_unlock_cost(node: Dictionary) -> float:
	return maxf(float(node.get("squad_unlock_cost", 0.0)), 0.0)

## СПОСОБНОСТЬ-РЕЖИМ: куплена — и дальше её включает и выключает игрок.
## Обычная способность срабатывает сама; эта висит переключателем на панели
## отряда (см. HUD._maybe_add_ability_buttons и GameManager.squad_ability_on)
static func is_toggle_ability(node: Dictionary) -> bool:
	return bool(node.get("toggle", false))

## Первая купленная способность-режим этого рода войск, или {} — таких нет.
## Нужна тем, кто спрашивает «а есть ли у отряда режим», не зная его id:
## поиск идёт по конфигу, а не по захардкоженному имени
static func toggle_ability_of(unit_id: String) -> Dictionary:
	for n in ability_nodes(unit_id):
		var d: Dictionary = n
		if is_toggle_ability(d):
			return d
	return {}

# ═════════════════════════════════════════════════════════════════════════════
# ЕДИНЫЙ ВИД УЗЛА ДЛЯ ЧТЕНИЯ ИЗВНЕ
#
# Внутри файла узел хранится «плоско»: name/desc, cost_gold/cost_wood/cost_stone,
# bonus_attack/bonus_armor/…, зависимости — ячейками. Так удобно ПРАВИТЬ (узел
# целиком виден глазом в двух строках), но неудобно ЧИТАТЬ снаружи: приходится
# знать, какие именно ключи бывают.
#
# node_view() отдаёт тот же узел в развёрнутом, самоописательном виде:
#   id, title, description, icon, research_time,
#   cost         — {"gold": …, "wood": …, "stone": …} (только ненулевое)
#   prerequisites— ПОЛНЫЕ id узлов, от которых зависит этот (вертикальные стрелки)
#   links        — полные id соседей по горизонтальным стрелкам (шаг вбок)
#   stat_bonus   — {"attack": 2, "armor": 1, …} (только ненулевое)
#
# ЭТО ИМЕННО ВИД, А НЕ ВТОРАЯ КОПИЯ ДАННЫХ. Числа по-прежнему живут в UNITS в
# одном экземпляре — иначе две таблицы разъехались бы при первой же правке
# баланса. Правим UNITS, читаем node_view().
# ═════════════════════════════════════════════════════════════════════════════
## Человеческие имена бонусов: ключ конфига → ключ во «вью»
const _BONUS_VIEW := {
	"bonus_attack": "attack", "bonus_armor": "armor", "bonus_health": "health",
	"bonus_speed": "speed", "bonus_push": "push", "bonus_morale": "morale",
	"bonus_gather": "gather", "bonus_carry": "carry",
}
const _COST_VIEW := {"cost_gold": "gold", "cost_wood": "wood", "cost_stone": "stone"}

static func node_view(id: String) -> Dictionary:
	var n: Dictionary = get_node(id)
	if n.is_empty():
		return {}
	var cost: Dictionary = {}
	for k in _COST_VIEW:
		var cv: float = float(n.get(k, 0.0))
		if cv > 0.0:
			cost[String(_COST_VIEW[k])] = cv
	var bonus: Dictionary = {}
	for b in _BONUS_VIEW:
		var bv: float = float(n.get(b, 0.0))
		if bv != 0.0:
			bonus[String(_BONUS_VIEW[b])] = bv
	return {
		"id":            String(n.get("id", id)),
		"unit_id":       String(n.get("unit", "")),
		"cell":          String(n.get("cell", "")),
		"title":         String(n.get("name", id)),
		"description":   String(n.get("desc", "")),
		"icon":          _UCfgRef().smith_icon_path(String(n.get("icon", ""))),
		"cost":          cost,
		"research_time": float(n.get("research_time", 0.0)),
		"prerequisites": (n.get("prerequisites", []) as Array).duplicate(),
		"links":         (n.get("link_ids", []) as Array).duplicate(),
		"stat_bonus":    bonus,
		"is_unit_ability":   bool(n.get("is_unit_ability", false)),
		"squad_unlock_cost": squad_unlock_cost(n),
	}

## Всё древо одной вкладки в развёрнутом виде — для стендов и внешних читателей
static func tree_view(unit_id: String) -> Array:
	var out: Array = []
	for n in tree(unit_id):
		out.append(node_view(String((n as Dictionary).get("id", ""))))
	return out

## Иконки узлов лежат в папке кузницы и в конфиге записаны ОДНИМ ИМЕНЕМ файла;
## полный путь собирает unit_stats_config.smith_icon_path. Грузим его лениво:
## forge_config подключается из unit_stats_config, и preload в обратную сторону
## замкнул бы цикл
static func _UCfgRef():
	return load("res://scripts/unit_stats_config.gd")
