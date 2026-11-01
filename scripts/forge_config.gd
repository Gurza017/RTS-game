extends RefCounted
## ДРЕВО КУЗНИЦЫ: UNITS[unit][cell] — узел = слот улучшения; подключение — preload.
## Заметки — docs/config_notes/forge_config.md (ранние — docs/CONFIG_NOTES_2026-09-14.md)

const ROWS := 5
const COLS := ["a", "b", "c", "d"]
## Колонка спец-способностей: открывается не стрелкой, а полным рядом A+B+C
const ABILITY_COL := "d"

## Порядок вкладок кузницы — он же порядок иконок в верхней полосе («economy» слита в «worker»)
const UNIT_TABS := ["worker", "warrior", "spearman", "archer", "monk"]

## К каким юнитам применяются бонусы вкладки; нет записи — к своему роду войск
const TAB_APPLIES := {
	"economy": ["all"],
}

## ── ЦЕНА РЯДА ──
## Множитель ко всем ценам узла (дерево, золото, камень, еда) по номеру ряда; время исследования не трогает
const ROW_COST_MULT := {1: 0.60, 2: 0.90, 3: 1.30, 4: 2.00, 5: 2.60}
const _COST_KEYS := ["cost_wood", "cost_gold", "cost_stone", "cost_food"]

## Множитель ко всем ценам каждого узла (поверх UNITS и ROW_COST_MULT) и доля еды в цене узла
## (от суммы прочих цен; заданная явно еда берётся, если больше)
const FORGE_PRICE_MULT := 1.6
const FORGE_FOOD_SHARE := 0.35

## ── СТОК ЭНДГЕЙМА (ТЗ 28.10.2026, п. 2) ──
## Множитель «стока» по ряду поверх ROW_COST_MULT (ряды 1-2 — без стока); ручка perf_config.forge_endgame_sink
const ROW_SINK_MULT := {3: 4.0, 4: 6.0, 5: 10.0}
## Вес стока по ресурсу: цена = ядро × (1 + (сток − 1) × вес); дерево копится сильнее всего, камень не трогается
const SINK_RES_WEIGHT := {"cost_wood": 1.0, "cost_gold": 0.5, "cost_food": 0.5, "cost_stone": 0.0}
## Потолок времени исследования любого узла, с (граница владельца — полторы минуты)
const RESEARCH_TIME_MAX := 90.0

const _Opt := preload("res://scripts/perf_config.gd")

static func row_cost_mult(row: int) -> float:
	return float(ROW_COST_MULT.get(row, 1.0))

## Множитель стока ряда (1.0 — сток не действует: ряды 1-2 или ручка выключена)
static func row_sink_mult(row: int) -> float:
	if not _Opt.forge_endgame_sink:
		return 1.0
	return float(ROW_SINK_MULT.get(row, 1.0))

## Множитель стока для одного ключа цены в ряду row
static func sink_mult(row: int, cost_key: String) -> float:
	var s: float = row_sink_mult(row)
	return 1.0 + (s - 1.0) * float(SINK_RES_WEIGHT.get(cost_key, 1.0))

static func tab_applies_to(unit_id: String) -> Array:
	var lst: Variant = TAB_APPLIES.get(unit_id)
	if lst == null:
		return [unit_id]
	return (lst as Array).duplicate()

## ── ДРЕВО ──
## Узел: icon, prereq (ячейки-предпосылки), link (горизонтальные стрелки), name, desc,
## cost_gold/cost_wood/cost_stone[/cost_food], research_time (с), bonus_* (прибавки к статам;
## боевые узлы несут полный список, ненужное — 0.0), toggle (способность-режим),
## squad_unlock_cost (признак способности отряда в колонке D), toggle_lines (строки плашки режима)
const UNITS := {
# ── РАБОЧИЙ — ЭКОНОМИЧЕСКАЯ ВЕТКА ──
"worker": {
	# Все прибавки — доли. Колонки: a — промыслы ПО ОДНОМУ ресурсу на узел (bonus_gather_wood/_stone/_gold),
	# b — мясо (bonus_gather_food — темп ножа, bonus_meat_pct — выход с туши), c — груз и ход с грузом
	# (bonus_carry_pct, bonus_walk_loaded_pct) и стройка (bonus_build), d — найм рабочих (bonus_train,
	# bonus_hire_cost — доля цены в еде) и темп самой Кузницы (bonus_research_pct, все вкладки).
	# Ряды 3-5 — глубокие исследования эндгейма (ТЗ 28.10.2026, блок 2): 60-90 с, не дольше полутора минут
	"1a": {"icon": "icon_axe.png", "prereq": [], "link": [],
		"name": "Лесопилка", "desc": "Рубка дерева быстрее на 15 %",
		"cost_gold": 150.0, "cost_wood": 250.0, "cost_stone": 0.0, "research_time": 20.0,
		"bonus_gather_wood": 0.15},
	"1b": {"icon": "icon_drop.png", "prereq": [], "link": [],
		"name": "Мясницкий нож", "desc": "Разделка мяса быстрее на 15 %",
		"cost_gold": 150.0, "cost_wood": 250.0, "cost_stone": 0.0, "research_time": 20.0,
		"bonus_gather_food": 0.15},
	"1c": {"icon": "icon_luck_horseshoe.png", "prereq": [], "link": [],
		"name": "Крепкие лямки", "desc": "С грузом ходит быстрее на 10 %",
		"cost_gold": 150.0, "cost_wood": 250.0, "cost_stone": 0.0, "research_time": 20.0,
		"bonus_walk_loaded_pct": 0.1},
	"1d": {"icon": "icon_might.png", "prereq": [], "link": [],
		"name": "Артельный подряд", "desc": "Найм рабочих быстрее на 20 %",
		"cost_gold": 150.0, "cost_wood": 250.0, "cost_stone": 0.0, "research_time": 20.0,
		"bonus_train": 0.2},
	"2a": {"icon": "icon_hammer.png", "prereq": ["1a"], "link": [],
		"name": "Каменоломня", "desc": "Добыча камня быстрее на 15 %",
		"cost_gold": 260.0, "cost_wood": 400.0, "cost_stone": 100.0, "research_time": 32.0,
		"bonus_gather_stone": 0.15},
	"2b": {"icon": "icon_trader.png", "prereq": ["1b"], "link": [],
		"name": "Заплечные корзины", "desc": "Груз за ходку больше на 10 % (20 → 22)",
		"cost_gold": 260.0, "cost_wood": 400.0, "cost_stone": 100.0, "research_time": 32.0,
		"bonus_carry_pct": 0.1},
	"2c": {"icon": "icon_luck_horseshoe.png", "prereq": ["1c"], "link": [],
		"name": "Торные тропы", "desc": "С грузом ещё +10 %, стройка быстрее на 15 %",
		"cost_gold": 260.0, "cost_wood": 400.0, "cost_stone": 100.0, "research_time": 32.0,
		"bonus_walk_loaded_pct": 0.1, "bonus_build": 0.15},
	"2d": {"icon": "icon_might.png", "prereq": ["1d"], "link": [],
		"name": "Верстаки Крепости", "desc": "Найм рабочих быстрее ещё на 20 %",
		"cost_gold": 260.0, "cost_wood": 400.0, "cost_stone": 100.0, "cost_food": 60.0, "research_time": 32.0,
		"bonus_train": 0.2},
	"3a": {"icon": "icon_gold.png", "prereq": ["2a"], "link": [],
		"name": "Промывка породы", "desc": "Добыча золота быстрее на 15 %",
		"cost_gold": 420.0, "cost_wood": 620.0, "cost_stone": 200.0, "research_time": 60.0,
		"bonus_gather_gold": 0.15},
	"3b": {"icon": "icon_drop.png", "prereq": ["2b"], "link": [],
		"name": "Разделка туши", "desc": "Выход мяса с туши больше на 10 %: кусок за ходку 6 → 6.6",
		"cost_gold": 420.0, "cost_wood": 620.0, "cost_stone": 200.0, "research_time": 60.0,
		"bonus_meat_pct": 0.1},
	"3c": {"icon": "icon_trader.png", "prereq": ["2c"], "link": [],
		"name": "Тачки", "desc": "Груз за ходку больше ещё на 20 % (до 26)",
		"cost_gold": 420.0, "cost_wood": 620.0, "cost_stone": 200.0, "research_time": 60.0,
		"bonus_carry_pct": 0.2},
	"3d": {"icon": "icon_might.png", "prereq": ["2d"], "link": [],
		"name": "Учёт и порядок", "desc": "Найм ещё +15 %, рабочий дешевле на 10 % мяса",
		"cost_gold": 420.0, "cost_wood": 620.0, "cost_stone": 200.0, "cost_food": 110.0, "research_time": 60.0,
		"bonus_train": 0.15, "bonus_hire_cost": 0.1},
	"4a": {"icon": "icon_gold.png", "prereq": ["3a"], "link": [],
		"name": "Золотые лотки", "desc": "Добыча золота быстрее ещё на 20 %",
		"cost_gold": 800.0, "cost_wood": 1100.0, "cost_stone": 380.0, "research_time": 75.0,
		"bonus_gather_gold": 0.2},
	"4b": {"icon": "icon_drop.png", "prereq": ["3b"], "link": [],
		"name": "Коптильня", "desc": "Выход мяса с туши больше ещё на 20 % (кусок до 7.8)",
		"cost_gold": 800.0, "cost_wood": 1100.0, "cost_stone": 380.0, "research_time": 75.0,
		"bonus_meat_pct": 0.2},
	"4c": {"icon": "icon_luck_horseshoe.png", "prereq": ["3c"], "link": [],
		"name": "Мощёные дороги", "desc": "С грузом ещё +10 %, стройка ещё +15 %",
		"cost_gold": 800.0, "cost_wood": 1100.0, "cost_stone": 380.0, "research_time": 75.0,
		"bonus_walk_loaded_pct": 0.1, "bonus_build": 0.15},
	"4d": {"icon": "icon_might.png", "prereq": ["3d"], "link": [],
		"name": "Чертёжная", "desc": "Кузница исследует быстрее на 20 % (все вкладки)",
		"cost_gold": 800.0, "cost_wood": 1100.0, "cost_stone": 380.0, "cost_food": 220.0, "research_time": 75.0,
		"bonus_research_pct": 0.2},
	"5a": {"icon": "icon_axe.png", "prereq": ["4a"], "link": [],
		"name": "Вековой лес", "desc": "Рубка дерева быстрее ещё на 20 %",
		"cost_gold": 1200.0, "cost_wood": 1700.0, "cost_stone": 560.0, "research_time": 90.0,
		"bonus_gather_wood": 0.2},
	"5b": {"icon": "icon_drop.png", "prereq": ["4b"], "link": [],
		"name": "Солонина", "desc": "Выход мяса с туши больше ещё на 30 % (кусок до 9.6)",
		"cost_gold": 1200.0, "cost_wood": 1700.0, "cost_stone": 560.0, "research_time": 90.0,
		"bonus_meat_pct": 0.3},
	"5c": {"icon": "icon_trader.png", "prereq": ["4c"], "link": [],
		"name": "Крытые повозки", "desc": "Груз за ходку больше ещё на 30 % (до 32)",
		"cost_gold": 1200.0, "cost_wood": 1700.0, "cost_stone": 560.0, "research_time": 90.0,
		"bonus_carry_pct": 0.3},
	"5d": {"icon": "icon_might.png", "prereq": ["4d"], "link": [],
		"name": "Королевская академия", "desc": "Кузница исследует быстрее ещё на 30 % (все вкладки)",
		"cost_gold": 1200.0, "cost_wood": 1700.0, "cost_stone": 560.0, "cost_food": 340.0, "research_time": 90.0,
		"bonus_research_pct": 0.3},
},
# ── БОЕВЫЕ ВЕТКИ ──
"warrior": {
	"1a": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Щиты", "desc": "+1 к броне",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_sword.png", "prereq": [], "link": [],
		"name": "Точило", "desc": "+1.5 к урону",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_attack": 1.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1c": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Шлемы", "desc": "+12 к запасу HP",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 12.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# Яростная Атака — способность отряда (двойной ПКМ)
	"1d": {"icon": "icon_dual_sword.png", "prereq": [], "link": [],
		"name": "Яростная Атака", "desc": "Двойной ПКМ: рывок под щитами и серия из 10 быстрых ударов (15 с «Неистовством»), затем обычный темп; после рывка мечники сами вступают в бой с ближайшим врагом",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0, "squad_unlock_cost": 400.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_hand.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Наручи", "desc": "+1 к броне",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_fire_hand.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Хват огня", "desc": "+2 к урону",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_might.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Мощь", "desc": "+0.9 к напору",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.9,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# Рассечение: bonus_cleave — число задетых соседей цели, bonus_cleave_dmg — доля урона им
	"2d": {"icon": "icon_broken_sword.png", "prereq": ["1d"], "link": [],
		"name": "Рассечение", "desc": "Удар по площади: каждый удар мечника задевает до 2 врагов рядом с целью (50 % урона)",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_cleave": 2.0, "bonus_cleave_dmg": 0.5,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# скорости у мечника в древе нет — броня и напор
	"3a": {"icon": "icon_luck_horseshoe.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Тяжёлые латы", "desc": "+1.5 к броне, +0.4 к напору",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 1.5, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.4,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_fireball.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Огненный шар", "desc": "+2 к урону",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# Последний выживший (ТЗ 28.10.2026, блок 3): механика в Unit._try_last_stand, числа — unit_stats_config.LAST_STAND_*
	"3c": {"icon": "icon_healing_potion.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Последний выживший", "desc": "+16 к запасу HP. Последний боец выбитого отряда с шансом 40 % уцелеет (10 % HP): враги его не замечают, он уходит в крепость, лечится и выходит с отрядом, пополненным до штата",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 16.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# bonus_rage_hits — прибавка ударов к серии «Яростной Атаки»
	"3d": {"icon": "icon_dual_sword.png", "prereq": ["2d"], "link": [],
		"name": "Неистовство", "desc": "«Яростная Атака»: серия длиннее на 5 ударов (10 → 15)",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_rage_hits": 5.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_trader.png", "prereq": ["3a"], "link": [],
		"name": "Муштра мечников", "desc": "Найм мечников вдвое быстрее (−50 % времени), +16 к морали",
		"cost_gold": 2400.0, "cost_wood": 2800.0, "cost_stone": 600.0, "research_time": 60.0,
		"bonus_train": 1.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 16.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_skull.png", "prereq": ["3b"], "link": [],
		"name": "Устрашение", "desc": "+1.2 к напору",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 1.2,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_gold.png", "prereq": ["3c"], "link": [],
		"name": "Трофеи", "desc": "+20 к запасу HP",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 20.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# прибавки к «Рассечению»: +1 цель, +0.25 к доле урона соседям
	"4d": {"icon": "icon_fire_hand.png", "prereq": ["3d"], "link": [],
		"name": "Стальной вихрь", "desc": "«Рассечение»: задевает на одного врага больше (3), соседям 75 % урона",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0,
		"bonus_cleave": 1.0, "bonus_cleave_dmg": 0.25,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_trap.png", "prereq": ["4a"], "link": [],
		"name": "Осадный опыт", "desc": "+2.5 к броне",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_attack": 0.0, "bonus_armor": 2.5, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_demon.png", "prereq": ["4b"], "link": [],
		"name": "Чёрный рыцарь", "desc": "+2.5 к урону",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_attack": 2.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_dual_sword.png", "prereq": ["4c"], "link": [],
		"name": "Парные клинки", "desc": "+2.5 к урону, +16 к морали",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_attack": 2.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 16.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# bonus_berserk — доля усиления удара при запасе ниже половины
	"5d": {"icon": "icon_demon.png", "prereq": ["4d"], "link": [],
		"name": "Кровь берсерка", "desc": "«Яростная Атака»: серия 20 стремительных ударов (15 → 20), затем обычный темп; при запасе ниже половины удары сильнее на 25 %",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_berserk": 0.25, "bonus_rage_hits": 5.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
"spearman": {
	"1a": {"icon": "icon_sword.png", "prereq": [], "link": [],
		"name": "Калёный наконечник", "desc": "+1.5 к урону",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_attack": 1.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Стёганка", "desc": "+1 к броне",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1c": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Закалка", "desc": "+12 к запасу HP",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 12.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# Фаланга — способность-режим (toggle), включает/выключает игрок через [S]
	"1d": {"icon": "icon_trap_spikes.png", "prereq": [], "link": [], "toggle": true,
		"name": "Фаланга", "desc": "«Держать строй» [S] опускает копья — строй становится фалангой: разгон врага гасится (300% урона, остановка конницы). Без улучшения [S] только держит строй",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0, "squad_unlock_cost": 400.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_hand.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Упор щита", "desc": "+1 к броне",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_trap_spears.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Длинное древко", "desc": "+2 к урону",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_might.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Слаженность", "desc": "+0.6 к напору",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.6,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2d": {"icon": "icon_shield.png", "prereq": ["1d"], "link": [],
		"name": "Приём копья", "desc": "Контрудар: урон копейщиков ×2.5 по коннице, тушам и троллям",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_giant_melee": 1.5,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_luck_horseshoe.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Лёгкий шаг", "desc": "+0.2 к скорости",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.2, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_fire_hand.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Огненные жала", "desc": "+2 к урону",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# Последний выживший (ТЗ 28.10.2026, блок 3): механика в Unit._try_last_stand, числа — unit_stats_config.LAST_STAND_*
	"3c": {"icon": "icon_healing_potion.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Последний выживший", "desc": "+16 к запасу HP. Последний боец выбитого отряда с шансом 40 % уцелеет (10 % HP): враги его не замечают, он уходит в крепость, лечится и выходит с отрядом, пополненным до штата",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 16.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_trap.png", "prereq": ["2d"], "link": [],
		"name": "Тяжёлые латы", "desc": "+5 к броне: копейщик становится тяжёлой пехотой",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 5.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_trader.png", "prereq": ["3a"], "link": [],
		"name": "Снабжение", "desc": "+16 к морали",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 16.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_might.png", "prereq": ["3b"], "link": [],
		"name": "Боевой клич", "desc": "+0.8 к напору",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.8,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_gold.png", "prereq": ["3c"], "link": [],
		"name": "Добыча", "desc": "+20 к запасу HP",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 20.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# Натиск Фаланги — способность отряда (двойной ПКМ)
	"4d": {"icon": "icon_skull.png", "prereq": ["3d"], "link": [],
		"name": "Натиск Фаланги", "desc": "Двойной ПКМ: сомкнутый ход, 10 усиленных ударов, затем оттеснение",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0, "squad_unlock_cost": 1200.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_shield.png", "prereq": ["4a"], "link": [],
		"name": "Ветеранский строй", "desc": "+2 к броне",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_attack": 0.0, "bonus_armor": 2.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_trap_spears.png", "prereq": ["4b"], "link": [],
		"name": "Копьё смерти", "desc": "+2.5 к урону",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_attack": 2.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_dual_sword.png", "prereq": ["4c"], "link": [],
		"name": "Двойной удар", "desc": "+2.5 к урону, +16 к морали",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_attack": 2.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 16.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_trap_spikes.png", "prereq": ["4d"], "link": [],
		"name": "Муштра копейщиков", "desc": "Найм копейщиков вдвое быстрее (−50 % времени)",
		"cost_gold": 2400.0, "cost_wood": 2800.0, "cost_stone": 600.0, "research_time": 75.0,
		"bonus_train": 1.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
"archer": {
	# Колонки: A — дальность и бронепробитие, B — темп и урон по крупным, C — урон стрелы,
	# D — залп и снайперы. Доли (0.1 = 10 %): bonus_cooldown_pct, bonus_armor_pen,
	# bonus_giant (+0.5 = ×1.5), bonus_snipers (число), bonus_snipe_cd
	"1a": {"icon": "icon_bow.png", "prereq": [], "link": [],
		"name": "Длинная тетива I", "desc": "+2.5 м к дальности (15 → 17.5)",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_range": 2.5,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_tripple_arrows_2.png", "prereq": [], "link": [],
		"name": "Быстрая рука I", "desc": "Перезарядка −10 %",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_cooldown_pct": 0.1,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1c": {"icon": "icon_fire_hand.png", "prereq": [], "link": [],
		"name": "Тугая тетива", "desc": "+1.5 к урону стрелы",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_attack": 1.5,
		"bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# Залповый огонь — способность-режим (toggle): отряд бьёт разом навесом по области
	"1d": {"icon": "icon_rain_of_arrows.png", "prereq": [], "link": [], "toggle": true, "squad_unlock_cost": 400.0,
		"name": "Залповый огонь", "desc": "Отряд бьёт разом, кучно, навесом; +1 м дальности",
		# toggle_lines — строки плашки режима в HUD, свои у узла
		"toggle_lines": ["Отряд стреляет разом, а не по мере перезарядки",
			"Стрелы ложатся кучно в центр вражеского строя",
			"Выключено — каждый стрелок бьёт сам, с обычным разбросом"],
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_range": 1.0, "bonus_cooldown": 0.12,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_bow.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Длинная тетива II", "desc": "+2.5 м к дальности (17.5 → 20)",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_range": 2.5,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_tripple_arrows_2.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Быстрая рука II", "desc": "Перезарядка −20 % всего",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_cooldown_pct": 0.1,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_fire_hand.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Зажигательные", "desc": "+2 к урону стрелы",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_attack": 2.0,
		"bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# Снайперский выстрел: трое стрелков отряда бьют прямой наводкой на 25 м по отступающим и одиночкам
	"2d": {"icon": "icon_crossbow.png", "prereq": ["1d"], "link": [], "squad_unlock_cost": 700.0,
		"name": "Снайперский выстрел", "desc": "3 снайпера в отряде: прямой выстрел на 25 м, насмерть по пехоте",
		"cost_gold": 345.0, "cost_wood": 474.4, "cost_stone": 129.4, "research_time": 40.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_bow.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Большой лук", "desc": "+5 м к дальности (20 → 25)",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_range": 5.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_tripple_arrows_2.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Быстрая рука III", "desc": "Перезарядка −30 % всего",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_cooldown_pct": 0.1,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3c": {"icon": "icon_fireball.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Огненный залп", "desc": "+2 к урону стрелы",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_attack": 2.0,
		"bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_crossbow.png", "prereq": ["2d"], "link": [], "squad_unlock_cost": 900.0,
		"name": "Частота снайперов", "desc": "Снайперов 3 → 5, их перезарядка −35 %",
		"cost_gold": 507.5, "cost_wood": 710.5, "cost_stone": 203.0, "research_time": 45.0,
		"bonus_snipers": 2.0, "bonus_snipe_cd": 0.35,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_skull.png", "prereq": ["3a"], "link": [],
		"name": "Бронебойные I", "desc": "Стрела игнорирует 25 % брони цели",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0,
		"bonus_armor_pen": 0.25,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_trap.png", "prereq": ["3b"], "link": [],
		"name": "Гроза великанов I", "desc": "Урон ×1.5 по тушам, троллям и коннице",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0,
		"bonus_giant": 0.5,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_fire_hand.png", "prereq": ["3c"], "link": [],
		"name": "Стальные наконечники", "desc": "+2.5 к урону стрелы",
		"cost_gold": 988.0, "cost_wood": 1235.0, "cost_stone": 370.5, "research_time": 60.0,
		"bonus_attack": 2.5,
		"bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4d": {"icon": "icon_drop.png", "prereq": ["3d"], "link": [], "squad_unlock_cost": 1200.0,
		"name": "Школа лучников", "desc": "Найм лучников вдвое быстрее (−50 % времени)",
		"cost_gold": 2400.0, "cost_wood": 2800.0, "cost_stone": 600.0, "research_time": 60.0,
		"bonus_train": 1.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_skull.png", "prereq": ["4a"], "link": [],
		"name": "Бронебойные II", "desc": "Стрела игнорирует 50 % брони цели",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_armor_pen": 0.25,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_trap.png", "prereq": ["4b"], "link": [],
		"name": "Гроза великанов II", "desc": "Урон ×2.0 по тушам, троллям и коннице",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_giant": 0.5,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_gold.png", "prereq": ["4c"], "link": [],
		"name": "Мастер-лучник", "desc": "+2.5 к урону, +16 к морали",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_attack": 2.5, "bonus_morale": 16.0,
		"bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_tripple_arrows_2.png", "prereq": ["4d"], "link": [], "squad_unlock_cost": 1600.0,
		"name": "Стрелы-шипы", "desc": "Пробивает строй",
		"cost_gold": 1440.0, "cost_wood": 1872.0, "cost_stone": 576.0, "research_time": 75.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
"monk": {
	# Колонки: A — радиус ауры (bonus_heal_radius, м), B — темп и объём лечения (bonus_heal_rate,
	# bonus_heal_amount — доли), C — стойкость, D — платная последовательная ветка
	# (открывается рядом A+B+C и предыдущим узлом D)
	"1a": {"icon": "icon_hand.png", "prereq": [], "link": [],
		"name": "Расширение Ауры I", "desc": "+3 м к радиусу ауры (5 → 8 м)",
		"cost_gold": 100.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 15.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 3},
	"1b": {"icon": "icon_fire_hand.png", "prereq": [], "link": [],
		"name": "Быстрое Снадобье I", "desc": "Такт −20 %, +2 HP к исцелению",
		"cost_gold": 100.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 15.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.25, "bonus_heal_amount": 0.1, "bonus_heal_radius": 0.0},
	"1c": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Самохил I", "desc": "Монах лечит себя на 30 % отданного",
		"cost_gold": 100.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 15.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"1d": {"icon": "icon_healing_potion.png", "prereq": [], "link": [],
		"name": "Троичный Поток", "desc": "Лечит троих раненых в ауре разом",
		"cost_gold": 150.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 20.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"2a": {"icon": "icon_luck_horseshoe.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Расширение Ауры II", "desc": "+4 м к радиусу (8 → 12 м), скан вдвое реже",
		"cost_gold": 215.6, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 30.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 4},
	"2b": {"icon": "icon_might.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Сила Веры", "desc": "+50 % к исцелению за такт, такт −15 %",
		"cost_gold": 215.6, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 30.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.176, "bonus_heal_amount": 0.5, "bonus_heal_radius": 0.0},
	"2c": {"icon": "icon_trader.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Подвижность", "desc": "+20 % к шагу монаха, −10 % к отбросу",
		"cost_gold": 215.6, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 30.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.2, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"2d": {"icon": "icon_drop.png", "prereq": ["1d"], "link": [],
		"name": "Первое Чудо", "desc": "Воскрешение: раз в 15 с, павший встаёт с 30 % запаса",
		"cost_gold": 301.9, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 35.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"3a": {"icon": "icon_fireball.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Расширение Ауры III", "desc": "+5 м к радиусу (12 → 17 м)",
		"cost_gold": 507.5, "cost_wood": 50.8, "cost_stone": 0.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 5},
	"3b": {"icon": "icon_rain_of_arrows.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Концентрированное Благословение", "desc": "+100 % к исцелению за такт",
		"cost_gold": 507.5, "cost_wood": 50.8, "cost_stone": 0.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 1, "bonus_heal_radius": 0.0},
	"3c": {"icon": "icon_shield.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Опека Строя", "desc": "+3 к броне монаха, иммунитет к замедлению",
		"cost_gold": 507.5, "cost_wood": 50.8, "cost_stone": 0.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 3, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"3d": {"icon": "icon_heart.png", "prereq": ["2d"], "link": [],
		"name": "Опека и Самовоскрешение", "desc": "Лечит ВЕСЬ отряд разом; одно самовоскрешение за бой (50 % запаса)",
		"cost_gold": 710.5, "cost_wood": 81.2, "cost_stone": 0.0, "research_time": 50.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"4a": {"icon": "icon_gold.png", "prereq": ["3a"], "link": [],
		"name": "Расширение Ауры IV", "desc": "+6 м к радиусу",
		"cost_gold": 1235.0, "cost_wood": 0.0, "cost_stone": 185.2, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 6},
	"4b": {"icon": "icon_trap_spears.png", "prereq": ["3b"], "link": ["4c"],
		"name": "Непрерывный Поток", "desc": "Такт лечения 0.3 с — почти непрерывно",
		"cost_gold": 1235.0, "cost_wood": 0.0, "cost_stone": 185.2, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"4c": {"icon": "icon_shield.png", "prereq": ["3c"], "link": ["4b"],
		"name": "Святой Щит", "desc": "Щит на 150 HP, восстанавливается вне боя",
		"cost_gold": 1235.0, "cost_wood": 0.0, "cost_stone": 185.2, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"4d": {"icon": "icon_skull.png", "prereq": ["3d"], "link": [],
		"name": "Массовое Воскрешение", "desc": "Поднимает двоих разом каждые 12 с (50 % запаса)",
		"cost_gold": 1729.0, "cost_wood": 0.0, "cost_stone": 247.0, "research_time": 70.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"5a": {"icon": "icon_dual_sword.png", "prereq": ["4a"], "link": [],
		"name": "Глобальный Покров", "desc": "Аура на всю карту",
		"cost_gold": 2880.0, "cost_wood": 0.0, "cost_stone": 432.0, "research_time": 90.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"5b": {"icon": "icon_demon.png", "prereq": ["4b"], "link": [],
		"name": "Абсолютное Целительство", "desc": "Каждый такт восполняет живым 100 % запаса",
		"cost_gold": 2880.0, "cost_wood": 0.0, "cost_stone": 432.0, "research_time": 90.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"5c": {"icon": "icon_broken_sword.png", "prereq": ["4c"], "link": [],
		"name": "Второе Дыхание", "desc": "Смертельный удар оставляет 1 HP и 5 с неуязвимости",
		"cost_gold": 2880.0, "cost_wood": 0.0, "cost_stone": 432.0, "research_time": 90.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"5d": {"icon": "icon_fireball.png", "prereq": ["4d"], "link": [],
		"name": "Дух-Спас", "desc": "Пока в отряде жив хоть один — поднимает по 3-4 павших каждые 3 с",
		"cost_gold": 3600.0, "cost_wood": 0.0, "cost_stone": 576.0, "research_time": 90.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
},
}

## ── СБОРКА ДЕРЕВА ──

## Кэш собранных деревьев: тип → Array узлов в порядке 1a,1b,1c,1d,2a,…
static var _tree_cache: Dictionary = {}
## id узла → готовый узел, для быстрого поиска из GameManager
static var _node_cache: Dictionary = {}
## Положение ручки стока, под которое собран кэш (−1 — не собран): переключили — кэш пересобирается
static var _cache_sink: int = -1

static func _sync_cache() -> void:
	var s: int = 1 if _Opt.forge_endgame_sink else 0
	if s != _cache_sink:
		_tree_cache.clear()
		_node_cache.clear()
		_cache_sink = s

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

static func tree(unit_id: String) -> Array:
	_sync_cache()
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
		var rk: float = row_cost_mult(int(node["row"]))
		if rk != 1.0:
			for ck in _COST_KEYS:
				if node.has(ck):
					node[ck] = round(float(node[ck]) * rk)
		if node.has("cost_gold") or node.has("cost_wood"):
			var other: float = float(node.get("cost_wood", 0.0)) + float(node.get("cost_gold", 0.0)) \
				+ float(node.get("cost_stone", 0.0))
			node["cost_food"] = maxf(float(node.get("cost_food", 0.0)), round(other * FORGE_FOOD_SHARE))
			# Ядро цены (без стока) — для модели партии: бригада считается под ядро, сток — под излишек
			var core: Dictionary = {}
			for ck2 in _COST_KEYS:
				if node.has(ck2):
					core[ck2] = round(float(node[ck2]) * FORGE_PRICE_MULT)
					node[ck2] = round(float(node[ck2]) * FORGE_PRICE_MULT * sink_mult(int(node["row"]), String(ck2)))
			node["core_cost"] = core
		node["research_time"] = minf(float(node.get("research_time", 0.0)), RESEARCH_TIME_MAX)
		node["col"]      = cell.substr(cell.length() - 1, 1)
		node["unit"]     = unit_id
		node["icon"]     = String(data.get("icon", ""))
		node["applies_to"] = tab_applies_to(unit_id)
		# Зависимости — полными id, чтобы GameManager не знал про ячейки
		var reqs: Array = []
		for p in data.get("prereq", []):
			reqs.append(node_id(unit_id, String(p)))
		node["prerequisites"] = reqs
		# горизонтальные стрелки: ячейками (link) и полными id (link_ids)
		var links: Array = []
		var link_ids: Array = []
		for l in data.get("link", []):
			links.append(String(l))
			link_ids.append(node_id(unit_id, String(l)))
		node["link"] = links
		node["link_ids"] = link_ids
		if node["col"] == ABILITY_COL:
			if float(data.get("squad_unlock_cost", 0.0)) > 0.0:
				node["is_unit_ability"] = true
			var gate: Array = []
			for g in ability_row_cells(cell):
				gate.append(node_id(unit_id, String(g)))
			node["row_gate"] = gate
		out.append(node)
		_node_cache[String(node["id"])] = node
	_tree_cache[unit_id] = out
	return out

static func get_node(id: String) -> Dictionary:
	_sync_cache()
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

## Доплата золотом за способность конкретному отряду; сейчас 0 — второй оплаты нет
static func squad_unlock_cost(_node: Dictionary) -> float:
	return 0.0

## СПОСОБНОСТЬ-РЕЖИМ: куплена — и дальше её включает и выключает игрок.
static func is_toggle_ability(node: Dictionary) -> bool:
	return bool(node.get("toggle", false))

## Первая купленная способность-режим этого рода войск, или {} — таких нет.
static func toggle_ability_of(unit_id: String) -> Dictionary:
	for n in ability_nodes(unit_id):
		var d: Dictionary = n
		if is_toggle_ability(d):
			return d
	return {}

# ── ВИД УЗЛА ДЛЯ HUD ──
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

static func _UCfgRef():
	return load("res://scripts/unit_stats_config.gd")
