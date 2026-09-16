extends RefCounted
## ДРЕВО КУЗНИЦЫ: UNITS[unit][cell] — узел = слот улучшения.
## Только параметры; снятые пояснения — docs/CONFIG_NOTES_2026-09-14.md

const ROWS := 5
const COLS := ["a", "b", "c", "d"]
## Колонка спец-способностей: открывается не стрелкой, а полным рядом A+B+C
const ABILITY_COL := "d"

## Порядок вкладок в панели кузницы — он же порядок иконок в верхней полосе.
const UNIT_TABS := ["worker", "warrior", "spearman", "archer", "monk"]

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════
##   ── МОДИФИКАТОРЫ: ЧТО ИМЕННО КРУТИТ КАЖДЫЙ КЛЮЧ ────────────────────────
const UNITS := {
# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# РАБОЧИЙ — ЭКОНОМИЧЕСКАЯ ВЕТКА
"worker": {
	"1a": {"icon": "icon_trader.png", "prereq": [], "link": [],
		"name": "Крепкие корзины", "desc": "+2 к грузу за ходку",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 2.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_axe.png", "prereq": [], "link": [],
		"name": "Правка инструмента", "desc": "−0.25 с к циклу добычи",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.25},
	"1c": {"icon": "icon_luck_horseshoe.png", "prereq": [], "link": [],
		"name": "Крепкая обувь", "desc": "+0.15 к скорости",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.15, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# ── КОЛОНКА D — ОБУЧЕНИЕ И СТРОЙКА (письмо 12) ────────────────────────
	"1d": {"icon": "icon_hammer.png", "prereq": [], "link": [],
		"name": "Артельный подряд", "desc": "+20 % к темпу обучения рабочих",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_train": 0.20,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_trader.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Заплечные носилки", "desc": "+3 к грузу за ходку",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 3.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_hammer.png", "prereq": ["1b"], "link": ["2a"],
		"name": "Закалённые кирки", "desc": "−0.35 с к циклу добычи",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.35},
	"2c": {"icon": "icon_heart.png", "prereq": ["1c"], "link": [],
		"name": "Сытный паёк", "desc": "+16 к запасу HP",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 16.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2d": {"icon": "icon_gold.png", "prereq": [], "link": [],
		"name": "Учёт и порядок", "desc": "+25 % к темпу стройки, +15 % к темпу обучения",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "cost_food": 120.0, "research_time": 40.0,
		"bonus_build": 0.25, "bonus_train": 0.15,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.2, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 3.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_trader.png", "prereq": ["2a"], "link": [],
		"name": "Тачки", "desc": "+3 к грузу за ходку",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 3.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_axe.png", "prereq": ["2b"], "link": ["3c"],
		"name": "Двуручный топор", "desc": "−0.35 с к циклу добычи",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.35},
	"3c": {"icon": "icon_luck_horseshoe.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Торные тропы", "desc": "+0.2 к скорости, +1 к удару",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 1.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.2, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_drop.png", "prereq": [], "link": [],
		"name": "Артельный обоз", "desc": "+40 % к темпу стройки, +25 % к темпу обучения",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "cost_food": 180.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_build": 0.40, "bonus_train": 0.25, "bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_gold.png", "prereq": ["3a"], "link": ["4b"],
		"name": "Крытые повозки", "desc": "+4 к грузу за ходку",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 4.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_hammer.png", "prereq": ["3b"], "link": ["4a"],
		"name": "Рудничный вороток", "desc": "−0.45 с к циклу добычи",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.45},
	"4c": {"icon": "icon_heart.png", "prereq": ["3c"], "link": [],
		"name": "Артельный лекарь", "desc": "+20 к запасу HP, +1 к удару",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 1.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 20.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4d": {"icon": "icon_might.png", "prereq": [], "link": [],
		"name": "Гильдия артелей", "desc": "+60 % к темпу стройки, +35 % к темпу обучения",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "cost_food": 300.0, "research_time": 60.0,
		"bonus_build": 0.60,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_train": 0.35, "bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_trader.png", "prereq": ["4a"], "link": [],
		"name": "Складские артели", "desc": "+4 к грузу за ходку",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 4.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_axe.png", "prereq": ["4b"], "link": [],
		"name": "Мастера промысла", "desc": "−0.45 с к циклу добычи",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.45},
	"5c": {"icon": "icon_luck_horseshoe.png", "prereq": ["4c"], "link": [],
		"name": "Мощёные дороги", "desc": "+20 к запасу HP, +0.25 к скорости, +2 к удару",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 20.0, "bonus_speed": 0.25, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_gold.png", "prereq": [], "link": [],
		"name": "Королевский откуп", "desc": "+80 % к темпу стройки, +50 % к темпу обучения",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_build": 0.80, "bonus_train": 0.50, "bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# БОЕВЫЕ ВЕТКИ
"warrior": {
	"1a": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Щиты", "desc": "+1 к броне",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_sword.png", "prereq": [], "link": [],
		"name": "Точило", "desc": "+1.5 к урону",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 1.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1c": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Шлемы", "desc": "+12 к запасу HP",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 12.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# ── ЯРОСТНЫЙ НАБЕГ (заказ спринта 13) ─────────────────────────────────
	"1d": {"icon": "icon_dual_sword.png", "prereq": [], "link": [],
		"name": "Яростный Набег", "desc": "Двойной ПКМ: рывок под щитами и серия из 5 ударов",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0, "squad_unlock_cost": 400.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_hand.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Наручи", "desc": "+1 к броне",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_fire_hand.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Хват огня", "desc": "+2 к урону",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_might.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Мощь", "desc": "+0.6 к напору",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.6,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2d": {"icon": "icon_broken_sword.png", "prereq": [], "link": [],
		"name": "Рассечение", "desc": "Удар по площади",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0, "squad_unlock_cost": 700.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_luck_horseshoe.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Подкова", "desc": "+0.2 к скорости",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.2, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_fireball.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Огненный шар", "desc": "+2 к урону",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3c": {"icon": "icon_healing_potion.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Зелья", "desc": "+16 к запасу HP",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 16.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_dual_sword.png", "prereq": [], "link": [],
		"name": "Стальной вихрь", "desc": "Круговой удар",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0, "squad_unlock_cost": 900.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_trader.png", "prereq": ["3a"], "link": [],
		"name": "Обозы", "desc": "+16 к морали",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 16.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_skull.png", "prereq": ["3b"], "link": [],
		"name": "Устрашение", "desc": "+0.8 к напору",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.8,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_gold.png", "prereq": ["3c"], "link": [],
		"name": "Трофеи", "desc": "+20 к запасу HP",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 20.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4d": {"icon": "icon_demon.png", "prereq": [], "link": [],
		"name": "Кровь берсерка", "desc": "Ярость при ранении",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0, "squad_unlock_cost": 1200.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_trap.png", "prereq": ["4a"], "link": [],
		"name": "Осадный опыт", "desc": "+2 к броне",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 2.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_demon.png", "prereq": ["4b"], "link": [],
		"name": "Чёрный рыцарь", "desc": "+2.5 к урону",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_dual_sword.png", "prereq": ["4c"], "link": [],
		"name": "Парные клинки", "desc": "+2.5 к урону, +16 к морали",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 16.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_trap_spikes.png", "prereq": [], "link": [],
		"name": "Стена копий", "desc": "Отражает натиск",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0, "squad_unlock_cost": 1600.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
"spearman": {
	"1a": {"icon": "icon_sword.png", "prereq": [], "link": [],
		"name": "Калёный наконечник", "desc": "+1.5 к урону",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 1.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1b": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Стёганка", "desc": "+1 к броне",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"1c": {"icon": "icon_heart.png", "prereq": [], "link": [],
		"name": "Закалка", "desc": "+12 к запасу HP",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 12.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# ── СПРИНТ 18: «СТЕНА КОПИЙ» — режим-переключатель (как залп у лучников).
	"1d": {"icon": "icon_trap_spikes.png", "prereq": [], "link": [], "toggle": true,
		"name": "Стена копий", "desc": "В «Защите» три шеренги и копья вперёд: разгон врага гасится — 300 % урона, остановка, замедление",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0, "squad_unlock_cost": 400.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_hand.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Упор щита", "desc": "+1 к броне",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 1.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_trap_spears.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Длинное древко", "desc": "+2 к урону",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_might.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Слаженность", "desc": "+0.6 к напору",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.6,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2d": {"icon": "icon_shield.png", "prereq": [], "link": [],
		"name": "Приём копья", "desc": "Контрудар по коннице",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0, "squad_unlock_cost": 700.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_luck_horseshoe.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Лёгкий шаг", "desc": "+0.2 к скорости",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.2, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_fire_hand.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Огненные жала", "desc": "+2 к урону",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3c": {"icon": "icon_healing_potion.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Полевой лекарь", "desc": "+16 к запасу HP",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 16.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_trap.png", "prereq": [], "link": [],
		"name": "Еж", "desc": "Круговая оборона",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0, "squad_unlock_cost": 900.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_trader.png", "prereq": ["3a"], "link": [],
		"name": "Снабжение", "desc": "+16 к морали",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 16.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_might.png", "prereq": ["3b"], "link": [],
		"name": "Боевой клич", "desc": "+0.8 к напору",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.8,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_gold.png", "prereq": ["3c"], "link": [],
		"name": "Добыча", "desc": "+20 к запасу HP",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 20.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# ── НАТИСК ФАЛАНГИ (заказ спринта 13, ЧЕТВЁРТЫЙ слот) ─────────────────
	"4d": {"icon": "icon_skull.png", "prereq": [], "link": [],
		"name": "Натиск Фаланги", "desc": "Двойной ПКМ: сомкнутый ход, 10 усиленных ударов, затем оттеснение",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0, "squad_unlock_cost": 1200.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_shield.png", "prereq": ["4a"], "link": [],
		"name": "Ветеранский строй", "desc": "+2 к броне",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 2.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_trap_spears.png", "prereq": ["4b"], "link": [],
		"name": "Копьё смерти", "desc": "+2.5 к урону",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_dual_sword.png", "prereq": ["4c"], "link": [],
		"name": "Двойной удар", "desc": "+2.5 к урону, +16 к морали",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 2.5, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 16.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_trap_spikes.png", "prereq": [], "link": [],
		"name": "Фаланга", "desc": "Неприступный строй",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0, "squad_unlock_cost": 1600.0,
		# ── МОДИФИКАТОРЫ: полный список, ненужное — нулём ─────────────────
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0,
		"bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0,
		"bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0,
		"bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
"archer": {
	# ══ ВЕТКА ЛУЧНИКА — ТЗ 14.09.2026 (Archer Tech Tree & Snipe Shot) ═════════
	# Колонка A: дальность (база 15 м → 25) и бронепробитие; B: темп стрельбы и
	# урон по крупным (туша, тролль, конница); C: урон стрелы; D: залп,
	# снайперский выстрел, частота снайперов. Доли (0.1 = 10 %) — свойства,
	# читаются через unit_bonus: bonus_cooldown_pct, bonus_armor_pen,
	# bonus_giant (+0.5 = ×1.5), bonus_snipers, bonus_snipe_cd
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
	# ── ЗАЛПОВЫЙ ОГОНЬ: способность-переключатель (toggle) ──────────────────
	# Отряд бьёт разом и кучно по указанной области навесом (GameManager._sweep_volleys)
	"1d": {"icon": "icon_rain_of_arrows.png", "prereq": [], "link": [], "toggle": true, "squad_unlock_cost": 400.0,
		"name": "Залповый огонь", "desc": "Отряд бьёт разом, кучно, навесом; +1 м дальности",
		"cost_gold": 200.0, "cost_wood": 300.0, "cost_stone": 0.0, "research_time": 25.0,
		"bonus_range": 1.0, "bonus_cooldown": 0.12,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2a": {"icon": "icon_bow.png", "prereq": ["1a"], "link": ["2b"],
		"name": "Длинная тетива II", "desc": "+2.5 м к дальности (17.5 → 20)",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		"bonus_range": 2.5,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2b": {"icon": "icon_tripple_arrows_2.png", "prereq": ["1b"], "link": ["2a", "2c"],
		"name": "Быстрая рука II", "desc": "Перезарядка −20 % всего",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		"bonus_cooldown_pct": 0.1,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"2c": {"icon": "icon_fire_hand.png", "prereq": ["1c"], "link": ["2b"],
		"name": "Зажигательные", "desc": "+2 к урону стрелы",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		"bonus_attack": 2.0,
		"bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	# ── СНАЙПЕРСКИЙ ВЫСТРЕЛ: трое стрелков отряда бьют по прямой на 25 м,
	# быстрее на 30 %, по отступающим и одиночкам, насмерть (Archer/Arrow) ──
	"2d": {"icon": "icon_crossbow.png", "prereq": [], "link": [], "squad_unlock_cost": 700.0,
		"name": "Снайперский выстрел", "desc": "3 снайпера в отряде: прямой выстрел на 25 м, насмерть по пехоте",
		"cost_gold": 400.0, "cost_wood": 550.0, "cost_stone": 150.0, "research_time": 40.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3a": {"icon": "icon_bow.png", "prereq": ["2a"], "link": ["3b"],
		"name": "Большой лук", "desc": "+5 м к дальности (20 → 25)",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		"bonus_range": 5.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3b": {"icon": "icon_tripple_arrows_2.png", "prereq": ["2b"], "link": ["3a", "3c"],
		"name": "Быстрая рука III", "desc": "Перезарядка −30 % всего",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		"bonus_cooldown_pct": 0.1,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3c": {"icon": "icon_fireball.png", "prereq": ["2c"], "link": ["3b"],
		"name": "Огненный залп", "desc": "+2 к урону стрелы",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		"bonus_attack": 2.0,
		"bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"3d": {"icon": "icon_crossbow.png", "prereq": ["2d"], "link": [], "squad_unlock_cost": 900.0,
		"name": "Частота снайперов", "desc": "Снайперов 3 → 5, их перезарядка −35 %",
		"cost_gold": 500.0, "cost_wood": 700.0, "cost_stone": 200.0, "research_time": 45.0,
		"bonus_snipers": 2.0, "bonus_snipe_cd": 0.35,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4a": {"icon": "icon_skull.png", "prereq": ["3a"], "link": [],
		"name": "Бронебойные I", "desc": "Стрела игнорирует 25 % брони цели",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		"bonus_armor_pen": 0.25,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4b": {"icon": "icon_trap.png", "prereq": ["3b"], "link": [],
		"name": "Гроза великанов I", "desc": "Урон ×1.5 по тушам, троллям и коннице",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		"bonus_giant": 0.5,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4c": {"icon": "icon_fire_hand.png", "prereq": ["3c"], "link": [],
		"name": "Стальные наконечники", "desc": "+2.5 к урону стрелы",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		"bonus_attack": 2.5,
		"bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"4d": {"icon": "icon_drop.png", "prereq": [], "link": [], "squad_unlock_cost": 1200.0,
		"name": "Отравленные", "desc": "Урон по времени",
		"cost_gold": 800.0, "cost_wood": 1000.0, "cost_stone": 300.0, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5a": {"icon": "icon_skull.png", "prereq": ["4a"], "link": [],
		"name": "Бронебойные II", "desc": "Стрела игнорирует 50 % брони цели",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		"bonus_armor_pen": 0.25,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5b": {"icon": "icon_trap.png", "prereq": ["4b"], "link": [],
		"name": "Гроза великанов II", "desc": "Урон ×2.0 по тушам, троллям и коннице",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		"bonus_giant": 0.5,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5c": {"icon": "icon_gold.png", "prereq": ["4c"], "link": [],
		"name": "Мастер-лучник", "desc": "+2.5 к урону, +16 к морали",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		"bonus_attack": 2.5, "bonus_morale": 16.0,
		"bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
	"5d": {"icon": "icon_tripple_arrows_2.png", "prereq": [], "link": [], "squad_unlock_cost": 1600.0,
		"name": "Стрелы-шипы", "desc": "Пробивает строй",
		"cost_gold": 1000.0, "cost_wood": 1300.0, "cost_stone": 400.0, "research_time": 75.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0},
},
"monk": {
	## ── ВЕТКА МОНАХА: 3 СТОЛБЦА × 5 РЯДОВ + БОНУСНЫЙ СТОЛБЕЦ ──────────────
	## Заказ владельца 13.09.2026. Столбцы: A — АУРА (радиус), B — ТЕМП И
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
	"1d": {"icon": "icon_healing_potion.png", "prereq": ["1a", "1b", "1c"], "link": [],
		"name": "Троичный Поток", "desc": "Лечит троих раненых в ауре разом",
		"cost_gold": 0.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 0.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"2a": {"icon": "icon_luck_horseshoe.png", "prereq": ["1a"], "link": [],
		"name": "Расширение Ауры II", "desc": "+4 м к радиусу (8 → 12 м), скан вдвое реже",
		"cost_gold": 250.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 30.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 4},
	"2b": {"icon": "icon_might.png", "prereq": ["1b"], "link": [],
		"name": "Сила Веры", "desc": "+50 % к исцелению за такт, такт −15 %",
		"cost_gold": 250.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 30.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.176, "bonus_heal_amount": 0.5, "bonus_heal_radius": 0.0},
	"2c": {"icon": "icon_trader.png", "prereq": ["1c"], "link": [],
		"name": "Подвижность", "desc": "+20 % к шагу монаха, −10 % к отбросу",
		"cost_gold": 250.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 30.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.2, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"2d": {"icon": "icon_drop.png", "prereq": ["2a", "2b", "2c"], "link": [],
		"name": "Первое Чудо", "desc": "Воскрешение: раз в 15 с, павший встаёт с 30 % запаса",
		"cost_gold": 0.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 0.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"3a": {"icon": "icon_fireball.png", "prereq": ["2a"], "link": [],
		"name": "Расширение Ауры III", "desc": "+5 м к радиусу (12 → 17 м)",
		"cost_gold": 500.0, "cost_wood": 50.0, "cost_stone": 0.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 5},
	"3b": {"icon": "icon_rain_of_arrows.png", "prereq": ["2b"], "link": [],
		"name": "Концентрированное Благословение", "desc": "+100 % к исцелению за такт",
		"cost_gold": 500.0, "cost_wood": 50.0, "cost_stone": 0.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 1, "bonus_heal_radius": 0.0},
	"3c": {"icon": "icon_shield.png", "prereq": ["2c"], "link": [],
		"name": "Опека Строя", "desc": "+3 к броне монаха, иммунитет к замедлению",
		"cost_gold": 500.0, "cost_wood": 50.0, "cost_stone": 0.0, "research_time": 45.0,
		"bonus_attack": 0.0, "bonus_armor": 3, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"3d": {"icon": "icon_heart.png", "prereq": ["3a", "3b", "3c"], "link": [],
		"name": "Опека и Самовоскрешение", "desc": "Лечит ВЕСЬ отряд разом; одно самовоскрешение за бой (50 % запаса)",
		"cost_gold": 0.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 0.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"4a": {"icon": "icon_gold.png", "prereq": ["3a"], "link": [],
		"name": "Расширение Ауры IV", "desc": "+6 м к радиусу",
		"cost_gold": 1000.0, "cost_wood": 0.0, "cost_stone": 150.0, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 6},
	"4b": {"icon": "icon_trap_spears.png", "prereq": ["3b"], "link": [],
		"name": "Непрерывный Поток", "desc": "Такт лечения 0.3 с — почти непрерывно",
		"cost_gold": 1000.0, "cost_wood": 0.0, "cost_stone": 150.0, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"4c": {"icon": "icon_shield.png", "prereq": ["3c"], "link": [],
		"name": "Святой Щит", "desc": "Щит на 150 HP, восстанавливается вне боя",
		"cost_gold": 1000.0, "cost_wood": 0.0, "cost_stone": 150.0, "research_time": 60.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"4d": {"icon": "icon_skull.png", "prereq": ["4a", "4b", "4c"], "link": [],
		"name": "Массовое Воскрешение", "desc": "Поднимает двоих разом каждые 12 с (50 % запаса)",
		"cost_gold": 0.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 0.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"5a": {"icon": "icon_dual_sword.png", "prereq": ["4a"], "link": [],
		"name": "Глобальный Покров", "desc": "Аура на всю карту",
		"cost_gold": 2000.0, "cost_wood": 0.0, "cost_stone": 300.0, "research_time": 90.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"5b": {"icon": "icon_demon.png", "prereq": ["4b"], "link": [],
		"name": "Абсолютное Целительство", "desc": "Каждый такт восполняет живым 100 % запаса",
		"cost_gold": 2000.0, "cost_wood": 0.0, "cost_stone": 300.0, "research_time": 90.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"5c": {"icon": "icon_broken_sword.png", "prereq": ["4c"], "link": [],
		"name": "Второе Дыхание", "desc": "Смертельный удар оставляет 1 HP и 5 с неуязвимости",
		"cost_gold": 2000.0, "cost_wood": 0.0, "cost_stone": 300.0, "research_time": 90.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
	"5d": {"icon": "icon_fireball.png", "prereq": ["5a", "5b", "5c"], "link": [],
		"name": "Дух-Спас", "desc": "Пока в отряде жив хоть один — поднимает по 3-4 павших каждые 3 с",
		"cost_gold": 0.0, "cost_wood": 0.0, "cost_stone": 0.0, "research_time": 0.0,
		"bonus_attack": 0.0, "bonus_armor": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_range": 0.0, "bonus_cooldown": 0.0, "bonus_spread": 0.0, "bonus_push": 0.0, "bonus_morale": 0.0, "bonus_carry": 0.0, "bonus_gather": 0.0, "bonus_build": 0.0, "bonus_train": 0.0, "bonus_heal_rate": 0.0, "bonus_heal_amount": 0.0, "bonus_heal_radius": 0.0},
},
}

## ═══════════════════════════════════════════════════════════════════════════
## ═══════════════════════════════════════════════════════════════════════════

## Кэш собранных деревьев: тип → Array узлов в порядке 1a,1b,1c,1d,2a,…
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
		node["applies_to"] = [unit_id]
		# Зависимости — полными id, чтобы GameManager не знал про ячейки
		var reqs: Array = []
		for p in data.get("prereq", []):
			reqs.append(node_id(unit_id, String(p)))
		node["prerequisites"] = reqs
		# ГОРИЗОНТАЛЬНЫЕ СТРЕЛКИ — ДВА ПРЕДСТАВЛЕНИЯ ОДНОГО И ТОГО ЖЕ.
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

## ── ВТОРОЙ ОПЛАТЫ ЗА СПОСОБНОСТЬ БОЛЬШЕ НЕТ (заказ владельца 10.09.2026) ──
## Сколько золота стоит докупить способность конкретному отряду
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

# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
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
