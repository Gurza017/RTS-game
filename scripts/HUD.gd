extends CanvasLayer
class_name HUD
const _OptSys := preload("res://scripts/perf_config.gd")

const _UIAssets := preload("res://scripts/UIAssets.gd")
const _GSHud := preload("res://scripts/game_settings.gd")
const _GobCfgH := preload("res://scripts/goblin/goblin_config.gd")   # срок перемирия для подписи чекбокса
const _UCfg     := preload("res://scripts/unit_stats_config.gd")
## Пресеты сложности: подписи и переключение в меню паузы
const _Diff := preload("res://scripts/game_difficulty_config.gd")
## Сохранение и загрузка партии: кнопки в меню паузы
const _SaveLoad := preload("res://scripts/SaveLoadManager.gd")
## Средневековое оформление меню паузы и общее окно настроек (ТЗ 21.10.2026)
const _MUI := preload("res://scripts/ui/MedievalUI.gd")
const _SettingsWin := preload("res://scripts/ui/SettingsWindow.gd")
## Знамёна рангов: те же картинки, что висят на копье знаменосца в мире —
## панель берёт их обрезком, а не своим набором значков (см. _vet_flag)
const _BannerArt := preload("res://scripts/BannerArt.gd")
## Шаблоны тултипов: что и в каком порядке показывает всплывающая карточка
## (см. _unit_card / _tip_row). Отсутствующий в шаблоне параметр не рисуется
const _TipCfg   := preload("res://scripts/tooltip_config.gd")
## Древо технологий кузницы: форма сетки, узлы, цены (см. панель кузницы ниже)
const _Forge    := preload("res://scripts/forge_config.gd")
const _CooldownRadialS := preload("res://scripts/ui/CooldownRadial.gd")

# ── ЖЁСТКАЯ СЕТКА НИЖНЕЙ ПАНЕЛИ ──────────────────────────────────────────────
# Все колонки имеют ФИКСИРОВАННУЮ ширину, а подписи в них — autowrap.
# Иначе длина текста («Производство: Копейщик 45%  (в очереди ещё: 3)»)
# задавала минимальную ширину Label, колонка распухала и толкала соседей —
# панель «ехала» при каждом добавлении юнита в очередь.
# ── МАСШТАБ НИЖНЕЙ ПАНЕЛИ ────────────────────────────────────────────────────
# ВТОРОЙ ПРОХОД: ещё РОВНО ВДВОЕ меньше (заказ владельца «уменьши панель и
# кнопки приказов в 2 раза»). Числа ниже — половина от прежних, которые сами
# были −40% от исходных.
#
# Уменьшена ГЕОМЕТРИЯ; ШРИФТЫ срезаны мягче (11→10, 10→9): половина от 11px —
# это 5px, такую подпись не прочитать ни на каком мониторе, и панель из
# «слишком большой» стала бы «нечитаемой». Помним и про растяжение canvas_items:
# при базовом вьюпорте 720 на мониторе 1386 всё это рисуется ×1.93.
#
# ВЫСОТА ПАНЕЛИ БОЛЬШЕ НЕ КОНСТАНТА. PANEL_H — это МИНИМУМ; фактическую высоту
# считает _sync_panel_height() по содержимому (см. её комментарий): в панель
# высотой 40 не влезают ни второй ряд кнопок кузницы, ни строка производства
const PANEL_SCALE   := 0.60
## +10% К ВЫСОТЕ (40 → 44, заказ владельца). Плашка была ужата вдвое в прошлом
## проходе и на глаз оказалась тесной: в неё надо уместить портрет с бейджем,
## две строки подписи и шкалу опыта. Проценты честные — всё, что задаёт
## внутреннюю раскладку (COL_H, PORTRAIT_W), поднято тем же коэффициентом,
## иначе панель выросла бы одним воздухом
const PANEL_H       := 44      # МИНИМАЛЬНАЯ высота нижней панели (было 40)
## Зазор между панелью и нижней кромкой экрана
const PANEL_BOTTOM_GAP := 4
## ВЕРХНЯЯ КРОМКА ПАНЕЛИ (offset от низа экрана, отрицательный).
## Была константой; стала ПЕРЕМЕННОЙ, потому что высота панели теперь зависит
## от содержимого (_sync_panel_height её и переписывает). К ней привязано всё,
## что «висит над панелью»: подсказка размещения, полоса гарнизона, панель
## статов, всплывающая карточка — им достаточно читать актуальное значение
var PANEL_TOP: int = -(PANEL_H + PANEL_BOTTOM_GAP)
## ── ЕДИНАЯ ЛЕВАЯ ОСЬ ЛЕВОГО БЛОКА ──────────────────────────────────────────
## Жалоба владельца: «две левые нижние панели должны стоять по одной
## вертикали». Так и не было: нижняя панель крепилась к 6, панель статов над
## ней — к 8, полоса гарнизона — тоже к 8. Два пикселя не бросаются в глаза
## поодиночке, но на стыке двух тёмных плашек ступенька видна сразу.
##
## Число теперь ОДНО на весь левый столбец: панель, панель статов, полоса
## гарнизона и панель кузницы читают его, а не свои копии. Правится в одном
## месте — и весь блок едет целиком, не расслаиваясь
## ЛЕВЫЙ КРАЙ НИЖНЕЙ ПАНЕЛИ. С ТЗ 12.10.2026 — ПЕРЕМЕННАЯ: панель стоит ВНИЗУ
## ПО ЦЕНТРУ экрана (_center_bottom_panel), а всё, что крепится к её левой
## кромке (статы, гарнизон, карточки), читает текущее значение
const PANEL_LEFT_MIN := 6.0
var PANEL_LEFT: float = preload("res://scripts/Minimap.gd").dock_right_x()
## Панель по центру (false — прежний левый угол)
const PANEL_CENTERED := true
## ── СТЫКОВКА К МИНИ-КАРТЕ (ТЗ 20.10.2026, блок 2) ───────────────────────────
## Мини-карта переехала в левый нижний угол; панель выделенного объекта
## (здания, отряды, рабочие, ресурсы) встаёт ВПЛОТНУЮ К ЕЁ ПРАВОМУ КРАЮ, а не
## по центру экрана: «миникарта фиксирована слева, сразу за ней — плашка».
## Всё, что крепится к левой кромке панели (статы, гарнизон, карточки), едет
## вместе с ней — тот же механизм, что был у центрирования
const PANEL_DOCK_MINIMAP := true
const _MinimapScript := preload("res://scripts/Minimap.gd")
const COL_H         := 36      # рабочая высота колонок внутри панели (+10%)
const PORTRAIT_W    := 40      # ТЗ 14.10.2026: 33 → 40, портрет отряда заметнее
## Колонка «что выбрано» ШИРЕ на 20%: в ней теперь не только подпись, но и
## ШКАЛА ОПЫТА отряда (см. _update_xp_bar), а узкая колонка резала её в огрызок
const INFO_W        := 132
## ── ОТСТУП СОДЕРЖИМОГО ОТ КРАЁВ ПЛАШКИ ──────────────────────────────────────
## Был нулевым: у StyleBoxFlat content_margin по умолчанию 0, и портрет
## («шлем») прижимался вплотную к рамке — ровно то, на что жаловался владелец.
## 6 px по горизонтали — это «минимум 5» из задания с запасом на рамку
const PANEL_PAD_X   := 6
const PANEL_PAD_Y   := 3
# ОЧЕРЕДЬ НАЙМА — сетка МЕЛКИХ иконок, ОДНА НА КАЖДЫЙ ЗАКАЗ (не на тип),
# в порядке клика: production_queue[0] всегда первая ячейка. До QUEUE_ORDER_MAX
# заказов сразу, прогресс — только на самой первой (активной) ячейке.
# 5 колонок × 2 ряда = 10 ячеек по QUEUE_ORDER_ICON px — фиксированная сетка,
# custom_minimum_size не даёт ей ужаться и вытолкнуть соседей при пустой очереди
const QUEUE_ORDER_ICON := 10    # (было 17)
const QUEUE_ORDER_COLS := 5
## ДВА РЯДА ПО ПЯТЬ (заказ владельца): 5 сверху, 5 снизу. Раньше очередь была
## ОДНОЙ строкой — при пяти-шести заказах ячейки уже жались до нечитаемых
const QUEUE_ORDER_ROWS := 2
## Сколько заказов вообще показывается. Ровно вдвое больше сетки 5×2: сверх
## десяти зона НЕ РАСТЁТ ни вверх, ни в стороны — вместо этого добавляются
## колонки внутри той же ширины, а ячейки пропорционально мельчают
## (см. _queue_grid_cols / _queue_cell_side)
const QUEUE_ORDER_MAX  := 20
const QUEUE_W       := QUEUE_ORDER_COLS * QUEUE_ORDER_ICON \
	+ (QUEUE_ORDER_COLS - 1) * 3 + 6   # колонка очереди найма

# ── ЗОНА ОЧЕРЕДИ ЗАКАЗОВ (ДВА РЯДА, БЕЗ РАМКИ) ───────────────────────────────
# Габарит ФИКСИРОВАН: заказы не двигают панель — это и была жалоба «панель
# шагает под курсором, когда что-то ставишь в очередь». Иконки внутри
# ПРОПОРЦИОНАЛЬНО УМЕНЬШАЮТСЯ, когда их становится много, но за пределы зоны не
# выходят никогда (см. _queue_cell_side).
#
# ЖЁЛТАЯ РАМКА УБРАНА ЦЕЛИКОМ (заказ владельца: она была ориентиром на макете,
# а не элементом интерфейса). Контейнер остался — он и держит тот самый жёсткий
# габарит, — но рисует ровно ничего: ни рамки, ни фона
const QUEUE_FRAME_PAD   := 3
const QUEUE_CELL_GAP    := 3
## Пределы стороны ячейки: крупнее MAX не растём (одинокий заказ не должен быть
## во всю панель), мельче MIN не жмёмся — иконка перестала бы читаться.
## Объявлены ВЫШЕ QUEUE_BOX_INNER: высота зоны считается из них
const QUEUE_CELL_MAX := 20.0
const QUEUE_CELL_MIN := 8.0
## Внутренний размер зоны (без полей). Ширины хватает на 10 колонок минимального
## размера, высоты — ровно на QUEUE_ORDER_ROWS ряда самой крупной ячейки
const QUEUE_BOX_INNER := Vector2(118.0,
	QUEUE_CELL_MAX * float(QUEUE_ORDER_ROWS) + float(QUEUE_CELL_GAP) * float(QUEUE_ORDER_ROWS - 1))

## СКОЛЬКО КОЛОНОК В СЕТКЕ ЗАКАЗОВ.
## До десяти включительно — ровно QUEUE_ORDER_COLS (пять сверху, пять снизу,
## как просил владелец: шесть заказов дают 5 + 1, а не 3 + 3). Сверх десяти
## колонок становится больше, но РЯДОВ всё равно два: зона обязана остаться
## двухрядной, шириной она тоже не растёт — мельчают ячейки
func _queue_grid_cols(n: int) -> int:
	if n <= QUEUE_ORDER_COLS * QUEUE_ORDER_ROWS:
		return QUEUE_ORDER_COLS
	return int(ceil(float(n) / float(QUEUE_ORDER_ROWS)))

## Сторона ячейки под n заказов: делим зону поровну с зазорами ПО ОБЕИМ ОСЯМ и
## берём меньшее. Это и есть «пропорционально уменьшаются, но строго внутри
## границ»: сумма ячеек и зазоров по построению не больше QUEUE_BOX_INNER —
## ни по ширине (cols), ни по высоте (rows)
func _queue_cell_side(n: int) -> float:
	if n <= 0:
		return QUEUE_CELL_MAX
	var cols: int = mini(n, _queue_grid_cols(n))
	var rows: int = int(ceil(float(n) / float(cols)))
	var by_w: float = (QUEUE_BOX_INNER.x - float(cols - 1) * float(QUEUE_CELL_GAP)) / float(cols)
	var by_h: float = (QUEUE_BOX_INNER.y - float(rows - 1) * float(QUEUE_CELL_GAP)) / float(rows)
	return clampf(minf(by_w, by_h), QUEUE_CELL_MIN, QUEUE_CELL_MAX)
## ── СТОРОНА КНОПКИ ПРИКАЗА: +30% ПО ЗАКАЗУ ВЛАДЕЛЬЦА ───────────────────────
## Было 22 (а до того 44). Жалоба по скриншоту: иконки способностей и стоек
## мелкие, а жёлтая обводка вокруг них наоборот толстая — читается рамка, а не
## картинка. Правится ОДНО число: от него считаются и место под ряд кнопок
## (BTN_COLS * BTN_SIZE), и отступ картинки (BTN_ICON_PAD масштабируется в
## _cmd), и размер кнопки награды (BTN_SIZE * VET_BTN_SCALE)
const BTN_SIZE      := 29      # сторона кнопки приказа (было 22, +30%)
const BTN_COLS      := 5
const BTN_GAP       := 3
## Отступ картинки от рамки кнопки приказа. Иконка вписывается в квадрат
## С СОХРАНЕНИЕМ ПРОПОРЦИЙ (см. _stretched_icon), поэтому ей нужен воздух:
## раньше картинка растягивалась на весь квадрат целиком, и высокие домики
## сплющивались в «пеньки»
const BTN_ICON_PAD  := 3.0

# Карточка характеристик при наведении
const CARD_W := 264
const CARD_H := 208

# ── ГЕОМЕТРИЯ ПАНЕЛИ КУЗНИЦЫ ─────────────────────────────────────────────────
# Панель фиксированного размера (заказ владельца) — она НЕ считается по
# содержимому, как обычная нижняя: сетка 5×4 всегда одна и та же, а стрелки
# между ячейками рисуются по координатам и от «дышащей» разметки поехали бы
const FORGE_CELL   := 34    # сторона иконки узла
const FORGE_GAP_X  := 24    # просвет между колонками — в нём живут стрелки
const FORGE_GAP_Y  := 13    # просвет между рядами
## Колонка D отставлена от A/B/C: это не продолжение веток, а отдельный столбец
## спец-способностей, и на макете он визуально отбит
const FORGE_D_GAP  := 22
const FORGE_TAB    := 30    # сторона иконки вкладки (тип войск)
const FORGE_BLD_W  := 96    # крупная иконка самой кузницы слева
## Ширина всплывающего окна описания. Оно КРУПНОЕ по требованию макета: там
## название, эффект, статус, время и цена — карточкой в CARD_W это не влезает
const FORGE_TIP_W  := 300
## Сколько пикселей окно описания отступает вправо от края панели
const FORGE_TIP_GAP := 10
## Высота полоски над первым рядом, в которой рисуется «шина» от вкладки к трём
## верхним узлам. Часть холста стрелок, не самой сетки
const FORGE_ROOT_H := 18

## ── ИНДИКАТОР ТЕКУЩЕГО ИССЛЕДОВАНИЯ (левая колонка панели кузницы) ──────────
## Сторона ячейки очереди исследований. ЗАМЕТНО КРУПНЕЕ узла древа (FORGE_CELL
## = 34) — заказ владельца «сделай чуть больше оригинальной»: индикатор отвечает
## на вопрос «что качается прямо сейчас», и его надо видеть, не приглядываясь.
## Раньше ряд строился размером QUEUE_ORDER_ICON (10 px), и ячейка читалась как
## пустой чёрный прямоугольник под иконкой Кузницы
const FORGE_QUEUE_ICON := 42
## На сколько ряд отжат ВНИЗ от иконки здания (та же просьба — «опусти ниже»)
const FORGE_QUEUE_DROP := 10

## Ширина/высота самой сетки узлов — считаются из констант выше, чтобы правка
## одной из них не требовала пересчёта панели руками
const FORGE_GRID_W := 4 * FORGE_CELL + 3 * FORGE_GAP_X + FORGE_D_GAP
const FORGE_GRID_H := 5 * FORGE_CELL + 4 * FORGE_GAP_Y
## Высота строки подписи «Кузница N/N HP» над содержимым
const FORGE_CAP_H  := 17
## Отступы внутри панели (content_margin стиля) и просветы между блоками
const FORGE_PAD    := 8
const FORGE_SEP    := 6

## ПОЛНАЯ ВЫСОТА ПАНЕЛИ — ЯВНОЕ ЧИСЛО, А НЕ «ПО СОДЕРЖИМОМУ».
## Панель прибита к низу экрана и растёт вверх (GROW_DIRECTION_BEGIN), а сетка
## узлов расставлена АБСОЛЮТНО внутри голого Control — контейнер её размера не
## знает и без явной высоты схлопывает панель, обрезая нижние ряды сетки
## (первый прогон: пятый ряд узлов уезжал за нижнюю кромку). Всё, из чего она
## складывается, — константы выше, поэтому число не разъедется при их правке
const FORGE_PANEL_H := FORGE_CAP_H + FORGE_SEP \
	+ FORGE_TAB + FORGE_SEP \
	+ FORGE_ROOT_H + FORGE_GRID_H \
	+ 2 * FORGE_PAD

# Иконки и подписи юнитов: нужны и кнопкам, и очереди, и карточкам
## worker/spearman/archer/warrior — готовые фракционно-нейтральные портреты.
## У монаха такого нет (проект несёт только цветные боевые спрайт-листы, см.
## assets/factions/humans/units/<Цвет> Units/Monk/), поэтому его иконка —
## сам первый кадр Idle.png одного конкретного цвета (Blue), обрезанный по
## силуэту в _icon_texture (см. FRAME_SHEET_ICONS ниже). Прагматичная заглушка,
## а не «неправильный путь»: портрета для монаха в проекте попросту нет.
const UNIT_ICONS := {
	"worker":   "res://assets/factions/humans/icons/units/Avatars_25.png",
	"spearman": "res://assets/factions/humans/icons/units/Lancer.png",
	"archer":   "res://assets/factions/humans/icons/units/Archer.png",
	"warrior":  "res://assets/factions/humans/icons/units/Warrior.png",
	# Аватарка монаха — из набора Human avatar; ПО ЦВЕТУ СТОРОНЫ (см.
	# MONK_AVATARS), здесь — запасной вариант для цвета без своего портрета
	"monk":     "res://assets/factions/humans/units/Human avatar/Monk_blue.png",
	"troll":    "res://assets/factions/orc/Troll/Troll_Idle.png",
	# Свинобосс (ТЗ 28.10.2026): первый кадр листа наездника
	"pig_boss": "res://assets/factions/Goblin/Pig Rider_Idle.png",
	# ВКЛАДКА КУЗНИЦЫ, А НЕ РОД ВОЙСК (ТЗ 23.09.2026): своего портрета у неё
	# быть не может, поэтому берётся значок ресурса — он и читается как
	# «экономика» без подписи
	"economy":  "res://assets/factions/humans/icons/hud/Gold_Resource.png",
}
## Портрет монаха по цвету стороны (заказ 09.09.2026: у синих Monk_blue,
## у жёлтых Avatars_14, у красных Avatars_09; Avatars_04 в паке нет — только
## его .import). Ключ — цвет в нижнем регистре, как отвечает color_of
const MONK_AVATARS := {
	"blue":   "res://assets/factions/humans/units/Human avatar/Monk_blue.png",
	"yellow": "res://assets/factions/humans/units/Human avatar/Avatars_14.png",
	"red":    "res://assets/factions/humans/units/Human avatar/Avatars_09.png",
}

## Путь иконки типа юнита ДЛЯ СТОРОНЫ: у монаха портрет зависит от цвета
static func unit_icon_path(uid: String, faction: int) -> String:
	if uid == "monk":
		var col: String = String(GameManager.color_of(faction)).to_lower()
		var p: Variant = MONK_AVATARS.get(col)
		if p != null and ResourceLoader.exists(String(p)):
			return String(p)
	return String(UNIT_ICONS.get(uid, ""))
## ── ФИГУРКИ В ПОЛНЫЙ РОСТ ВМЕСТО «ГОЛОВ» (ТЗ 25.10.2026, письмо UI №4, п. 2)
## Карточка выделения, панель отрядов, полоса мульти-выбора и разведка
## показывают бойца целиком: первый кадр ленты покоя из спрайтов игры, по
## цвету стороны (рисует tools/make_unit_figures.py). Ячейку TextureRect
## заполняет по большей стороне (KEEP_ASPECT_CENTERED). Нет фигурки (рабочий,
## тролль, чужой цвет без листа) — прежний портрет unit_icon_path
const UNIT_FIGURE_DIR := "res://assets/ui/unit_figures/"
const UNIT_FIGURE_IDS := ["warrior", "spearman", "archer", "monk"]
static func unit_figure_path(uid: String, faction: int) -> String:
	if UNIT_FIGURE_IDS.has(uid):
		var col: String = String(GameManager.color_of(faction)).capitalize()
		for c in [col, "Blue"]:
			var p: String = UNIT_FIGURE_DIR + c + "/" + uid + ".png"
			if ResourceLoader.exists(p):
				return p
	return unit_icon_path(uid, faction)
const UNIT_TITLES := {
	"worker": "Рабочий", "spearman": "Копейщик",
	"archer": "Лучник",  "warrior": "Мечник", "monk": "Монах",
	"troll": "Тролль", "pig_boss": "Свинобосс",
	"economy": "Экономика: промыслы, найм, стройка",
}
## Иконки, которые на деле являются боевым спрайт-листом (несколько кадров в
## ряд), а не готовым портретом: путь -> сторона квадратного кадра. Первый
## кадр вырезается и обрезается по силуэту в _icon_texture
const FRAME_SHEET_ICONS := {
	"res://assets/factions/humans/units/Blue Units/Monk/Idle.png": 192,
	"res://assets/factions/orc/Troll/Troll_Idle.png": 384,
	"res://assets/factions/Goblin/Pig Rider_Idle.png": 256,
}

# Resource labels
var _res_labels: Dictionary = {}
## Зелёная (или красная при убыли) цифра притока рядом с числом ресурса
var _res_income_labels: Dictionary = {}
## "⛏N" — сколько рабочих сейчас приписано к этому ресурсу
var _res_workers_labels: Dictionary = {}
## "🪓"/"🔪" — глиф у дерева/еды, тот же приём, что и "⛏" в _res_workers_labels
var _res_tool_labels: Dictionary = {}
## Как часто пересчитывать "+N/мин" — не каждый кадр, но и не редко:
## ограничивает частоту обхода all_units
const RES_INCOME_WINDOW_SEC := 1.0
var _res_income_timer: float = 0.0
## ── ИЗМЕРЕНИЕ ПРИТОКА (см. _update_resource_income) ────────────────────────
## Сколько СДАНО в замок с начала окна и сколько это окно длится. Считаем
## именно СДАЧУ (ResourceManager.gathered_total), а не изменение склада: склад
## проседает от найма и стройки, и цифра ныряла в ноль, пока рабочие копали
var _inc_base: Dictionary = {}      # тип -> сколько было сдано на старте окна
var _inc_elapsed: float = 0.0
var _inc_rate: Dictionary = {}      # тип -> текущая оценка, ед./мин
## Красная цифра расхода еды рядом с зелёным притоком (ТЗ 24.09.2026, п. 5)
var _food_upkeep_label: Label = null
## Рудники в секции золота: «иконка с числом рудников + доход в минуту»
var _mine_box: Control = null
var _mine_count_lbl: Label = null
var _mine_income_lbl: Label = null
## Мини-иконка рудника под монетой — доля иконки ресурса
const MINE_ICON_K := 0.8
## Последний снимок рудников игрока (стенды): рудников, рабочих, золота/мин
var mine_stat: Dictionary = {"mines": 0, "workers": 0, "per_min": 0.0}
## Длина окна усреднения. Один рейс рабочего (дойти-накопать-донести) занимает
## десятки секунд, поэтому окно заведомо длиннее рейса: иначе цифра прыгала бы
## между «ноль» и «пик» ровно в такт сдаче груза — та самая жалоба на мигание
const INC_WINDOW_SEC := 20.0
## Сколько окно должно накопить, прежде чем цифре можно верить (см. расчёт)
const INC_MIN_SAMPLE_SEC := 8.0
## Плавающая плашка «рабочие без дела»: висит НАД нижней панелью слева,
## отдельно от бара ресурсов (см. _build_idle_widget)
var _idle_btn: Button = null
var _idle_count_label: Label = null
var _idle_timer: float = 0.0
## Сколько бездельников было при последнем пересчёте — чтобы не трогать
## текст и прозрачность каждые полсекунды впустую
var _idle_last: int = -1
## Указатель обхода: каждый клик показывает СЛЕДУЮЩЕГО бездельника
var _idle_cycle: int = 0

var info_label: Label
## ── ШКАЛА ОПЫТА ОТРЯДА (в колонке «что выбрано») ────────────────────────────
## Заменила вторую строку подписи, дублировавшую заголовок окна статов
var _xp_bar: ProgressBar = null
var _xp_label: Label = null
## Флажок ранга перед числом опыта (ТЗ 24.10.2026, блок 7: вместо «Ранг 3 → 4»)
var _xp_row: HBoxContainer = null
var _xp_flag_lvl: int = -1
const XP_BAR_H := 6
const XP_BAR_COLOR := Color(0.95, 0.74, 0.20)

## Колонка «что выбрано» целиком. Нужна, чтобы схлопывать её, когда она пуста
## (Замок пишет свою строку в шапку панели, а не сюда)
var _info_col: VBoxContainer = null
var portrait: ColorRect
## Иконка того, что выбрано (юнит/здание) — поверх portrait, без рамки
var _portrait_icon: TextureRect = null
## Бейдж количества в правом нижнем углу портрета (виден при группе > 1)
var _portrait_count_lbl: Label = null
## Значок ранга поверх портрета (виден у одиночного юнита с рангом)
var _portrait_rank_lbl: Label = null
var button_container: GridContainer

## ═══════════════════════════════════════════════════════════════════════════
## РЯД КОМАНД ОТРЯДУ: [S] ДЕРЖАТЬ · [C] ВОЛЬНО · [A] АТАКА ПО ПУТИ
## ═══════════════════════════════════════════════════════════════════════════
## ТЗ 23.09.2026. ПОДПИСЬ СТОИТ НАД ЗНАЧКОМ, А НЕ ПОВЕРХ НЕГО, и это прямое
## требование заказа: каждая команда — VBoxContainer из Label и кнопки.
## Положи подпись внутрь кнопки (как сделано у всех прочих кнопок панели —
## _cmd кладёт текст в сам Button), и буква S утонула бы под словом
## «Держать позицию».
##
## ЗНАЧКИ РИСУЮТСЯ КОДОМ, А НЕ БЕРУТСЯ ИЗ АССЕТОВ. Готовых иконок с буквами
## в наборе нет, а буква на цветной плашке и есть самый читаемый значок для
## команды, у которой ГЛАВНОЕ — её горячая клавиша: игрок обязан связать
## кнопку с клавишей с первого взгляда, и картинка щита или ног этой связи
## не даёт вовсе
var _squad_cmd_bar: HBoxContainer = null
var _squad_cmd_btns: Dictionary = {}     # "S"/"C"/"A" -> Button
## ── ТЗ 10.10.2026, блок 4: ЧЕТЫРЕ УНИВЕРСАЛЬНЫЕ КНОПКИ ─────────────────────
## [A] двигаться и атаковать (меч) · [C] вольно · [S] держать позицию (щит) ·
## [F1] отступить в замок (замок). Они ЗАМЕНИЛИ прежние стойки Attack/Defend
## и кнопку «To Castle» — три пары кнопок делали одно и то же. Подпись над
## кнопкой снята: она всплывает подсказкой при наведении («Вольно [C]»).
## Жёлтая рамка — ровно у одной кнопки режима (см. _refresh_squad_cmd_bar).
## Тот же ряд стоит и в полосе мульти-выбора (_ob_cmd_btns): приказ всей армии.
var _ob_cmd_bar: HBoxContainer = null
var _ob_cmd_btns: Dictionary = {}
## Подсказка над кнопкой команды (одна на HUD, top_level)
var _scmd_hint: PanelContainer = null
var _scmd_hint_lbl: Label = null
const SCMD_GAP := 3
const SCMD_BTN := 34                      # сторона кнопки
const SCMD_KEYS := ["A", "C", "S", "F1"]
const SCMD_TITLES := {
	"A": "Двигаться и атаковать",
	"C": "Вольно",
	"S": "Держать строй",   # ТЗ 14.10.2026: так её зовёт владелец
	"F1": "Отступить в замок",
}
const SCMD_LINES := {
	"A": ["Клик по полю или мини-карте — марш с боем", "Встречных бьют, затем идут дальше"],
	"C": ["Обычный режим: свободный бой", "Снимает «держать» и атаку по пути"],
	"S": ["Копейщики — фаланга (шаг −20 %)", "Лучники — с места не сходят"],
	"F1": ["Бегом в ближайшую крепость (+30 % к бегу)", "Лечение и пополнение внутри"],
}
const SCMD_HINT_LINES := false
## ── «ВОЛЬНО» — СИЛУЭТ КОПЕЙЩИКА (ТЗ 25.10.2026, письмо UI №4, п. 1) ─────
## Был рыцарь из ленты покоя (_at_ease_icon — остался запасным, если файла
## нет). Теперь — чистый силуэт копейщика в расслабленной позе: копьё у
## плеча, нога в сторону; рисует tools/make_at_ease_icon.py
const ICON_AT_EASE := "res://assets/ui/icons_units_human/AtEase_spearman.png"
const SCMD_ICONS := {
	"A": ICON_STANCE_ATTACK,
	"C": ICON_AT_EASE,
	"S": ICON_STANCE_DEFENSE,
	"F1": ICON_TO_CASTLE,
}
const SCMD_COLORS := {
	"A": Color(0.52, 0.14, 0.12),   # красный — бой
	"C": Color(0.24, 0.26, 0.34),   # серо-синий — нейтральное состояние
	"S": Color(0.16, 0.42, 0.18),   # зелёный — оборона
	"F1": Color(0.14, 0.38, 0.20),  # зелёный — отход к своим
}
var drag_rect: ColorRect
var progress_bar: ProgressBar
var progress_label: Label

## ЗАМОК: увеличенная панель (+30% к портрету и кнопкам найма), только 2 юнита.
## Постройки (Кузница/Бараки/Домик) убраны из Замка НАВСЕГДА — их место у
## Рабочего (см. _build_worker_menu). _castle_boost взводится в начале ветки
## Замка внутри _refresh_panel и гасится в начале каждого нового вызова —
## иначе следующее (не замковое) выделение унаследовало бы укрупнённые кнопки
## Кнопки найма УКРУПНЕНЫ: 1.3 → 1.55. Панель выросла (+20% высоты / +15%
## ширины), кнопки съехали к вертикальному центру и вправо — освободившееся
## место отдано им, «чтобы смотрелись сочно» (заказ владельца)
## ТЗ 14.10.2026, п. 2: 1.55 → 1.9 — иконки найма крупнее и ОДНОГО размера с
## иконкой здания слева (CASTLE_PORTRAIT_W = BTN_SIZE × 1.9 ≈ 55)
const CASTLE_PANEL_BOOST := 1.9
## Значки Рабочего/Рыцаря/Монаха растут ЕЩЁ на +50% ПОВЕРХ увеличенной кнопки
## (было +20%, владелец попросил агрессивнее) — передаётся в _cmd как
## icon_boost, сжимает отступ картинки, а не сам размер кнопки (см. _cmd)
const CASTLE_ICON_BOOST := 1.5
var _castle_boost: bool = false

## ── ЕДИНЫЙ СТАНДАРТ ПРОИЗВОДСТВЕННЫХ ЗДАНИЙ: СТРОГО ФИКСИРОВАННЫЙ РАЗМЕР ────
## Название констант историческое (стандарт родился на Замке), но действует он
## на ВСЕ здания с очередью найма: Замок, Бараки, TownCenter — все включают один
## и тот же флаг _castle_boost и получают один и тот же вид. Отдельной ветки
## «панель Бараков» нет намеренно: два независимых «стандарта» разъедутся при
## первой же правке одного из них.
##
## Панель НЕ считается по содержимому (в отличие от всех остальных, см.
## _sync_panel_height). Причина в жалобе владельца: каждый новый заказ в очереди
## менял ширину/высоту содержимого, и панель «разъезжалась» прямо под курсором —
## кнопки найма уезжали вправо, и попасть по ним второй раз подряд было нельзя.
## Числа явные, как и FORGE_PANEL_H: они складываются из портрета, бокса очереди
## и ряда кнопок найма, но ПАНЕЛЬ ИМИ НЕ УПРАВЛЯЕТСЯ — она их вмещает
## УВЕЛИЧЕНА: +15% ширины (300 → 345) и +20% высоты (62 → 74) по заказу
## владельца. Прибавка — это ВОЗДУХ вокруг содержимого, а не растяжение
## раскладки: ширину съедает распорка перед кнопками найма (они уезжают вправо),
## высоту — подпись «Замок N/N HP» над опущенной иконкой Замка
## Ширина выросла вслед за кнопками найма: они считаются от BTN_SIZE
## (BTN_SIZE * CASTLE_PANEL_BOOST), а сторона кнопки поднята на 30% по заказу
## владельца. Число по-прежнему ЖЁСТКОЕ — панель Замка не должна дышать от
## содержимого, — просто пересчитано под новый размер иконок
## 13.09.2026: панель раздвинута, ряд иконок стоит по центру свободного места
## с отступами CASTLE_BTN_PAD со всех сторон (колонка рыцаря 45 + 2 + 20 = 67
## по высоте плюс по 10 сверху и снизу)
const CASTLE_PANEL_W := 430.0
const CASTLE_PANEL_H := 88.0
const CASTLE_BTN_PAD := 10.0
## Крупная иконка Замка слева. Больше обычного портрета: заказ владельца
## «иконка Замка слева увеличена»
const CASTLE_PORTRAIT_W := 55.0   # ТЗ 14.10.2026: 52 → 55, вровень с кнопками найма
## Отступ подписи «Замок N/N HP» от верхней кромки панели ВНУТРЬ
const CASTLE_CAPTION_INSET := 3.0
## СКОЛЬКО МЕСТА ПОДПИСЬ ЗАНИМАЕТ СВЕРХУ. Иконка Замка опускается ровно на
## столько: раньше она стояла по вертикальному центру панели (52 px в панели 62),
## то есть занимала её почти целиком, и строка «Замок 1800/1800 HP» ложилась
## прямо на картинку. Теперь подпись НАД иконкой, обе внутри границ панели
const CASTLE_CAPTION_BAND := 17.0
## ОТСТУП КНОПОК НАЙМА ОТ ПРАВОГО КРАЯ ПАНЕЛИ (заказ владельца: ровно 15 px)
const CASTLE_BTN_RIGHT_PAD := 15.0
## Разделитель между колонками нижней панели и толщина её рамки. Названы
## константами, потому что из них вычитается отступ кнопок (см.
## _sync_panel_grid_widths): расстояние до края панели складывается из
## разделителя, распорки и рамки, а не из одной распорки
const PANEL_HBOX_SEP  := 6
const PANEL_BORDER_W  := 2

## РАБОЧИЙ / АРТЕЛЬ: панель построек была слишком тесной — иконки зданий
## микроскопические, портрет мелкий, а бейдж количества («2») наглухо
## закрывал лицо юнита. WORKER_PANEL_W_BOOST/_H_BOOST растягивают саму
## панель (см. _sync_panel_height — там же меряется натуральная ширина/
## высота содержимого и досчитывается сверху), WORKER_ICON_BOOST — отдельно
## иконки построек (тем же приёмом, что и CASTLE_ICON_BOOST — крупнее самой
## кнопки, не просто вместе с ней) и главный портрет слева
## ТЗ 19.09.2026-3 (п. 1): панель рабочего СЖАТА — ширина по содержимому
## (1.0, было 1.2), иконки построек ×1.25 (было 1.5), ряд центрируется
const WORKER_PANEL_W_BOOST := 1.0
## ── ВЫСОТА ПАНЕЛИ РАБОЧЕГО ВЕРНУЛАСЬ К СТАНДАРТНОЙ (заказ владельца) ─────
## Было 2.0 — панель рабочего вдвое выше своего содержимого, «просторно» по
## прежнему заказу. Владелец развернул: «верни стандартную компактную
## высоту». Единица означает «по содержимому», то есть ровно так же, как у
## мечника и копейщика, — а укрупнение ИКОНОК построек (WORKER_ICON_BOOST)
## не тронуто: оно про читаемость мелких картинок зданий, а не про рост
## панели, и высоту задаёт уже само содержимое
const WORKER_PANEL_H_BOOST := 1.0
const WORKER_ICON_BOOST    := 1.25
var _worker_boost: bool = false

## Обёртка портрета — нужна отдельной ссылкой, чтобы менять её размер
## под Замок/Рабочего и возвращать обратно для всех остальных выделений
var _portrait_wrap: Control = null

var _selected_node = null
## instance_id выделенного объекта. Отдельно от ссылки потому, что
## освобождённый объект в Godot 4 равен null, и по самой ссылке отличить
## «ничего не выбрано» от «выбранное снесли» невозможно (см. _process)
var _selected_iid: int = 0
var _overlay: Control = null
var _placement_hint: Control = null
var _bottom_panel: Control = null
var _res_panel: Control = null
## Квадратная плашка "рабочие без дела" — под панелью ресурсов, см. _build_idle_widget
var _idle_widget: Control = null

# ── ОЧЕРЕДЬ НАЙМА ────────────────────────────────────────────────────────────
# Ячейки перестраиваются ТОЛЬКО при смене состава очереди (по «подписи»),
# а шкала активного заказа обновляется каждый кадр без пересборки узлов
## Распорки вокруг ряда кнопок найма: растягивающаяся слева (прижимает кнопки
## вправо) и фиксированная справа (отступ от края). Обе инертны у панелей,
## считающихся по содержимому — см. _sync_panel_grid_widths
var _btn_spacer: Control = null
var _btn_right_pad: Control = null
## Обёртка ряда кнопок: держит зарезервированный габарит и центрирует сетку
## внутри него (см. _sync_panel_grid_widths)
var _btn_slot: CenterContainer = null

var _queue_box: GridContainer = null
## Жёлтая рамка вокруг сетки заказов — задаёт предел, внутрь которого иконки
## обязаны уместиться (см. _queue_cell_side)
var _queue_frame: PanelContainer = null
var _queue_sig: String = ""
var _queue_active_bar: ProgressBar = null

# Всплывающая карточка характеристик (одна на весь HUD)
var _stat_card: Control = null

# ── ПАНЕЛЬ КУЗНИЦЫ (ДРЕВО ТЕХНОЛОГИЙ) ────────────────────────────────────────
# Кузница НЕ пользуется обычной нижней панелью: её сетка 5×4 со стрелками не
# помещается ни в одну колонку, а высота панели считается по содержимому
# (_sync_panel_height) и превратилась бы в полэкрана для всех остальных
# выделений тоже. Поэтому у кузницы своя панель фиксированного размера,
# которая нижнюю на время подменяет
var _forge_panel: Control = null
var _forge_caption: Label = null
var _forge_tabs: HBoxContainer = null
var _forge_grid: Control = null
var _forge_arrows: Control = null
var _forge_queue: GridContainer = null
## Всплывающее окно описания узла — СПРАВА от панели, вне её (по макету)
var _forge_tip: Control = null
## Какая вкладка (тип войск) открыта сейчас
var _forge_unit: String = ""
## Кузница, под которую собрана панель
var _forge_smithy: Smithy = null
## Кнопки узлов: id узла -> Button. Нужны стендам и подсветке
var _forge_nodes: Dictionary = {}

# Что качала выбранная кузница в прошлом кадре: по смене перерисовываем меню
# (доисследованный слот должен позеленеть, зависимые — открыться)
var _last_research_id: String = ""

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_drag_rect()
	ResourceManager.resources_changed.connect(_on_resources_changed)
	GameManager.keep_vet_changed.connect(_on_keep_vet_changed)
	GameManager.research_finished.connect(_on_research_finished)
	GameManager.squad_members_changed.connect(_on_squad_members_changed)
	GameManager.build_unlock_changed.connect(_on_build_unlock_changed)

# ─────────────────────────────────────────────────────────────────────────────
# РЕАКТИВНЫЙ HUD (ТЗ 28.10.2026): кузница и численность — по СОБЫТИЮ, а не по
# опросу. Оба обработчика сами ничего не рисуют: взводят флаг, рисует один
# проход в начале _process_timed — сотня смертей за кадр даёт один пересчёт
# ─────────────────────────────────────────────────────────────────────────────
## Отряды текущего выделения множеством: обработчик гибели сверяется с ним за
## O(1), а не обходит _sel_units на каждого павшего по всей карте
var _sel_sid_set: Dictionary = {}
var _counts_dirty: bool = false
var _forge_dirty: bool = false

## Исследование доехало: открытое окно кузницы перерисовать. ОТЛОЖЕННО — к
## моменту сигнала Smithy ещё не вызвал _start_next(), и следующий заказ
## очереди становится research_id лишь по возврату из finish_research
func _on_research_finished(faction: int, _upgrade_id: String) -> void:
	if not _OptSys.forge_live_refresh or _forge_dirty:
		return
	var s: Smithy = null
	if forge_visible() and _forge_smithy != null and is_instance_valid(_forge_smithy):
		s = _forge_smithy
	elif _selected_node is Smithy and is_instance_valid(_selected_node):
		s = _selected_node as Smithy
	if s == null or s.faction != faction:
		return
	_forge_dirty = true
	call_deferred("_forge_live_rebuild")

func _forge_live_rebuild() -> void:
	_forge_dirty = false
	if forge_visible() and _forge_smithy != null and is_instance_valid(_forge_smithy):
		_last_research_id = _forge_smithy.research_id
		_rebuild_forge()
	elif _selected_node is Smithy and is_instance_valid(_selected_node):
		_last_research_id = (_selected_node as Smithy).research_id
		show_selection([_selected_node])

## Состав отряда сменился: если он в выделении — пересчитать цифры в этом кадре
func _on_squad_members_changed(sid: int) -> void:
	if _counts_dirty or not _OptSys.hud_live_counts:
		return
	if _sel_sid_set.has(sid) or (not _parent_sids.is_empty() and _parent_sids.has(sid)):
		_counts_dirty = true

## Живые цифры без пересборки панели: бейдж портрета, строка «Отрядов: N — M»,
## карточки отрядов (число, полоска здоровья, подсказка), счётчики полосы
## родов. Пропавший отряд/род — пересборка ТОЛЬКО его полосы; полная
## _refresh_panel не зовётся — она гасит подсказки и мигает кнопками
func _refresh_live_counts() -> void:
	_counts_dirty = false
	if _sel_units.is_empty():
		return
	var ids: Array = _selected_squad_ids()
	var g: Dictionary = _selection_groups()
	var order: Array = g["order"]
	var men_by_type: Dictionary = g["men"]
	var squads_by_type: Dictionary = g["squads"]
	var live := 0
	for u in _sel_units:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
			live += 1
	# Портрет: на уровне 2 — бойцы развёрнутого рода, иначе — всё выделение
	if _portrait_count_lbl != null and is_instance_valid(_portrait_count_lbl):
		if _expanded_type != "" and _expanded_type != WORKER_GROUP:
			var men: int = int(men_by_type.get(_expanded_type, 0))
			_portrait_count_lbl.visible = men > 0
			_portrait_count_lbl.text = str(men)
		elif not (_selected_node is Building):
			_portrait_count_lbl.visible = live > 1
			if live > 1:
				_portrait_count_lbl.text = str(live)
			var nsq: int = _army_badge_squads()
			if nsq > 0:
				_portrait_count_lbl.visible = true
				_portrait_count_lbl.text = str(nsq)
	if info_label != null and is_instance_valid(info_label):
		if info_label.text.begins_with("Отрядов: "):
			info_label.text = "Отрядов: %d — %d бойцов" % [ids.size(), live]
		elif info_label.text.begins_with("Выбрано: "):
			info_label.text = "Выбрано: %d юнитов" % live
		elif _expanded_type != "" and _expanded_type != WORKER_GROUP and squads_by_type.has(_expanded_type):
			info_label.text = "%s  (%d отр.)" % [
				_squad_title(_expanded_type), int(squads_by_type[_expanded_type])]
	# Карточки отрядов развёрнутого рода
	if _squad_strip != null and is_instance_valid(_squad_strip) and _expanded_type != "":
		var gone := false
		for c in _squad_strip.get_children():
			var nm: String = c.name
			if not nm.begins_with("SquadCard"):
				continue
			var sid: int = int(nm.substr(9))
			if not _squad_alive(sid):
				gone = true
				break
			_update_squad_card(c, sid)
		if gone:
			_rebuild_squad_strip()
	# Полоса родов: число отрядов на иконке и подсказка; род исчез — пересборка
	if _overbar_row != null and is_instance_valid(_overbar_row) \
			and _overbar_row.get_child_count() > 0:
		if _overbar_row.get_child_count() != order.size():
			_rebuild_overbar(true)
		else:
			for t in order:
				var uid: String = String(t)
				var slot: Node = _overbar_row.get_node_or_null("GroupSlot_" + uid)
				if slot == null:
					_rebuild_overbar(true)
					break
				var badge: Label = slot.find_child("GroupCount", true, false) as Label
				if badge != null:
					badge.text = str(int(squads_by_type[uid]))
				var btn: Button = (badge.get_parent() as Button) if badge != null else null
				if btn != null:
					btn.tooltip_text = "%s: %d отрядов, %d бойцов. Клик или Tab — отряды рода" % [
						_squad_title(uid), int(squads_by_type[uid]), int(men_by_type[uid])]

## Обновить карточку отряда на месте (см. _squad_card: имена узлов там)
func _update_squad_card(card: Node, sid: int) -> void:
	var alive: int = GameManager.squad_members(sid).size()
	var frac: float = _squad_strength(sid)
	var badge: Label = card.find_child("CountBadge", true, false) as Label
	if badge != null:
		badge.text = str(alive)
		var btn: Button = badge.get_parent() as Button
		if btn != null:
			btn.tooltip_text = "%s — %d бойцов (%d%%). Клик — выделить только этот отряд" \
				% [_squad_title_ranked(GameManager.squad_type(sid), GameManager.squad_level(sid)),
					alive, int(round(frac * 100.0))]
	var fill: Control = card.find_child("HpFill", true, false) as Control
	if fill != null:
		fill.custom_minimum_size = Vector2(maxf(SQUAD_CARD * frac, 1.0), SQUAD_HP_H)

# ─────────────────────────────────────────────────────────────────────────────
# PLACEMENT HINT
# ─────────────────────────────────────────────────────────────────────────────

## Высота строки подсказки и её отступ над нижней панелью
const HINT_FONT_SIZE := 18
const HINT_LIFT := 6.0
## Мягкий салатовый
const HINT_COLOR := Color(0.62, 0.95, 0.58)

# ─────────────────────────────────────────────────────────────────────────────
# ПОДСКАЗКА РЕЖИМА ПОСТРОЙКИ
# Была широкая зелёная плашка ВВЕРХУ экрана: она наезжала на панель ресурсов
# и съедала полосу обзора ровно тогда, когда игрок выбирает место и ему важно
# видеть карту. Теперь это одна строка НАД нижней панелью, без фона и рамок.
# ─────────────────────────────────────────────────────────────────────────────
func show_placement_hint(building_name: String = "Замок") -> void:
	hide_placement_hint()
	var lbl := Label.new()
	lbl.name = "PlacementHint"
	lbl.text = "Выберите место для постройки: %s   (ПКМ или ESC — отмена)" % building_name
	lbl.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	lbl.add_theme_color_override("font_color", HINT_COLOR)
	# Тонкая тёмная обводка вместо плашки: строка читается и на светлой траве,
	# и на чёрной зоне за краем карты, но ничего собой не перекрывает
	lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.02, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	# Привязка к НИЗУ экрана: строка садится ровно над нижней панелью
	lbl.anchor_left   = 0.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 1.0
	lbl.anchor_bottom = 1.0
	# PANEL_TOP уже отрицательный (отступ верха панели от низа экрана)
	lbl.offset_bottom = PANEL_TOP - HINT_LIFT
	lbl.offset_top    = lbl.offset_bottom - float(HINT_FONT_SIZE) - 8.0
	lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	_placement_hint = lbl

func hide_placement_hint() -> void:
	if _placement_hint:
		_placement_hint.queue_free()
		_placement_hint = null

# ─────────────────────────────────────────────────────────────────────────────
# КОМПАКТНАЯ ШАПКА ЗАМКА — "Замок 1800/1800 HP" НАД панелью, а не строкой
# внутри неё (там и без того тесно на +30% укрупнённой панели с 3 кнопками
# найма). Тот же приём позиционирования, что и у show_placement_hint —
# привязка к PANEL_TOP, но левым краем к панели, а не по центру экрана
# ─────────────────────────────────────────────────────────────────────────────
var _castle_caption: Label = null

func _update_castle_caption(text: String) -> void:
	if _castle_caption == null or not is_instance_valid(_castle_caption):
		var lbl := Label.new()
		lbl.name = "CastleCaption"
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
		lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.9))
		lbl.add_theme_constant_override("outline_size", 3)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.anchor_left = 0.0; lbl.anchor_right = 0.0
		lbl.anchor_top  = 1.0; lbl.anchor_bottom = 1.0
		add_child(lbl)
		_castle_caption = lbl
	_castle_caption.text = text
	# ЛЕВЫЙ КРАЙ — ОТ ПАНЕЛИ, А НЕ ОТ ЭКРАНА (ТЗ 14.10.2026, п. 2): со дня,
	# когда панель встала по центру, подпись с отступом 8 px висела у левого
	# края экрана («Стрелковая 3800/3800 HP» вне панели на скриншоте).
	# Дальше её двигает _center_bottom_panel вместе с панелью
	_castle_caption.offset_left = PANEL_LEFT + float(PANEL_BORDER_W + PANEL_PAD_X) + 2.0
	_castle_caption.offset_right = _castle_caption.offset_left + 400.0
	# ПОДПИСЬ ВНУТРИ ПАНЕЛИ, А НЕ НАД НЕЙ (заказ владельца: «строго внутри /
	# над иконкой В ГРАНИЦАХ ПАНЕЛИ»). Раньше строка висела снаружи, выше
	# верхней кромки, и на светлой карте читалась как отдельный обрывок текста,
	# не связанный с панелью. Теперь она прижата к верхней кромке ИЗНУТРИ, над
	# крупной иконкой Замка
	_castle_caption.offset_top    = float(PANEL_TOP) + CASTLE_CAPTION_INSET
	_castle_caption.offset_bottom = _castle_caption.offset_top + 15.0
	_castle_caption.visible = true

func _hide_castle_caption() -> void:
	if _castle_caption != null and is_instance_valid(_castle_caption):
		_castle_caption.visible = false

# ─────────────────────────────────────────────────────────────────────────────
# MAIN HUD
# ─────────────────────────────────────────────────────────────────────────────

func show_hud() -> void:
	_build_resource_bar()
	_build_idle_widget()
	# Стек алертов ветеранства — сразу под плашкой бездельников (см. там же)
	_build_alert_stack()
	_build_top_right_widget()
	_build_bottom_panel()
	_build_overbar()
	_refresh_resources()
	show_selection([])

# ═════════════════════════════════════════════════════════════════════════════
# УРОВЕНЬ 1 ВЫДЕЛЕНИЯ: КОМПАКТНАЯ ПОЛОСА ГРУПП ПО ТИПАМ
#
# Двухуровневая схема (заказ владельца):
#
#   УРОВЕНЬ 1 — выделено НЕСКОЛЬКО ТИПОВ (4 отряда копейщиков + 3 лучников).
#     Внизу НЕТ большой детальной панели с кашей из иконок и общей цифрой «260»:
#     показывается ТОЛЬКО эта полоса — иконка копейщиков с цифрой 4 и иконка
#     лучников с цифрой 3. Больше на экране нет ничего.
#
#   УРОВЕНЬ 2 — клик по групповой иконке. Разворачивается нижняя панель ИМЕННО
#     под этот тип: суммарная численность («57 бойцов»), по одной карточке на
#     каждый отряд типа, у карточки — живой состав, шкала здоровья и значок
#     ранга. Клик по карточке сужает выделение до одного отряда.
#     Повторный клик по той же групповой иконке сворачивает обратно в уровень 1.
#
# Выделение при развороте НЕ меняется: игрок разглядывает состав, а не отдаёт
# приказ. Сужает выделение только клик по карточке конкретного отряда.
#
# Полоса живёт постоянно (строится в show_hud), но ВИДНА только когда типов
# в выделении два и больше — на одном типе она дублировала бы портрет панели.
# ═════════════════════════════════════════════════════════════════════════════
const OVERBAR_LEFT   := 8      # отступ полосы от левого края экрана
const OVERBAR_GAP    := 6      # зазор над командной панелью
const IDLE_DIM_ALPHA := 0.35   # прозрачность плашки, когда бездельников нет

## Правый верхний блок (пауза/таймер/FPS/меню). Ссылка нужна только затем,
## чтобы клик по нему не считался кликом по миру (см. point_over_ui)
var _top_right: PanelContainer = null

var _overbar: PanelContainer = null
var _overbar_row: HBoxContainer = null
## Полоса карточек отдельных отрядов внутри нижней панели
var _squad_strip: Container = null
## Какая группа сейчас развёрнута ("" — ни одна)
var _expanded_type: String = ""
## Выделение, по которому нарисован баннер (нужно для разворачивания групп)
var _sel_units: Array = []

func _build_overbar() -> void:
	_overbar = PanelContainer.new()
	_overbar.name = "OverBar"
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.10, 0.92)
	_borders(st); _corners(st, 6)
	st.border_color = Color(0.34, 0.44, 0.58)
	st.content_margin_left = 5; st.content_margin_right = 5
	st.content_margin_top  = 4; st.content_margin_bottom = 4
	_overbar.add_theme_stylebox_override("panel", st)
	# Якоря к НИЖНЕМУ ЛЕВОМУ углу: полоса обязана держаться над панелью при
	# любом разрешении. Ни ШИРИНА, ни ВЫСОТА не задаются числом — обе берёт на
	# себя содержимое: полоса растёт вправо от левого края и ВВЕРХ от своей
	# нижней кромки, а саму кромку двигает _position_group_bar() (высота нижней
	# панели теперь плавает, см. _sync_panel_height)
	_overbar.anchor_left   = 0.0
	_overbar.anchor_right  = 0.0
	_overbar.anchor_top    = 1.0
	_overbar.anchor_bottom = 1.0
	_overbar.offset_left   = OVERBAR_LEFT
	_overbar.grow_horizontal = Control.GROW_DIRECTION_END
	_overbar.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	add_child(_overbar)

	# Ряд типов и ряд команд — РАЗНЫЕ контейнеры: type_slots() считает только
	# сводные иконки (стенды), а четыре кнопки приказа всей армии стоят справа
	var outer := HBoxContainer.new()
	outer.name = "OverBarOuter"
	outer.add_theme_constant_override("separation", 10)
	_overbar.add_child(outer)
	_overbar_row = HBoxContainer.new()
	# ЗАЗОР 3 px МЕЖДУ ИКОНКАМИ РОДОВ (ТЗ 10.10.2026, блок 4)
	_overbar_row.add_theme_constant_override("separation", 3)
	outer.add_child(_overbar_row)
	_ob_cmd_bar = HBoxContainer.new()
	_ob_cmd_bar.name = "OverBarCmd"
	_ob_cmd_bar.add_theme_constant_override("separation", SCMD_GAP)
	_ob_cmd_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(_ob_cmd_bar)
	for k in SCMD_KEYS:
		_ob_cmd_bar.add_child(_build_squad_cmd_col(String(k), _ob_cmd_btns))
	_position_group_bar()
	_rebuild_overbar(true)

## Поставить полосу групп над нижней панелью — или на её место, если панель
## скрыта (уровень 1: детальной панели нет вовсе, и полоса опускается вниз,
## а не висит в воздухе над пустотой)
func _position_group_bar() -> void:
	if _overbar == null or not is_instance_valid(_overbar):
		return
	var bottom: float = float(PANEL_BOTTOM_GAP)
	if _bottom_panel != null and is_instance_valid(_bottom_panel) and _bottom_panel.visible:
		bottom = panel_height() + float(PANEL_BOTTOM_GAP) + float(OVERBAR_GAP)
	_overbar.offset_bottom = -bottom
	_overbar.offset_top    = -bottom      # высоту добавит содержимое (grow BEGIN)
	# Полоса групп — над левой кромкой панели, которая теперь по центру
	if PANEL_CENTERED:
		_overbar.offset_left = PANEL_LEFT + float(OVERBAR_LEFT - PANEL_LEFT_MIN)

## Подпись текущего набора групп. Пересобирать полосу имеет смысл, только
## когда изменился САМ набор: клик по ярлыку рабочих меняет выделение, а значит
## тянет за собой show_selection — и полоса пересобиралась бы прямо под пальцем,
## удаляя ту самую кнопку, которую игрок нажал (в стенде это ловилось как
## «emit_signal на освобождённом узле»)
var _overbar_sig: String = ""

## Пересобрать полосу под текущее выделение и число бездельников
func _rebuild_overbar(force: bool = false) -> void:
	if _overbar_row == null or not is_instance_valid(_overbar_row):
		return
	var sig := "%s|" % _expanded_type
	for sid in (_parent_sids if not _parent_sids.is_empty() else _selected_squad_ids()):
		sig += "%d," % int(sid)
	sig += "w%d" % _group_workers().size()
	if not force and sig == _overbar_sig and _overbar_row.get_child_count() > 0:
		return
	_overbar_sig = sig
	for c in _overbar_row.get_children():
		_overbar_row.remove_child(c)
		c.queue_free()

	# сводные ярлыки войск: сколько отрядов и бойцов каждого типа. Ярлык
	# "рабочие без дела" здесь больше не живёт — это отдельная постоянная
	# плашка под панелью ресурсов (см. _build_idle_widget), не пересобирается
	# при каждой смене выделения
	var g: Dictionary = _selection_groups()
	var order: Array = g["order"]
	var squads_by_type: Dictionary = g["squads"]
	var men_by_type: Dictionary = g["men"]
	for t in order:
		var uid: String = String(t)
		_overbar_row.add_child(
			_filter_slot(uid, int(squads_by_type[uid]), int(men_by_type[uid])))

	# ПОЛОСА ВИДНА ТОЛЬКО НА СМЕШАННОМ ВЫДЕЛЕНИИ (два типа и больше).
	# Один тип полностью описан портретом и подписью самой панели — вторая
	# копия той же цифры рядом и была прежней жалобой на дублирование
	_overbar.visible = order.size() >= GROUP_BAR_MIN_TYPES
	# Детальная панель открыта — кнопки приказа стоят на ней, второй ряд в
	# полосе родов был бы дублем
	if _ob_cmd_bar != null and is_instance_valid(_ob_cmd_bar):
		_ob_cmd_bar.visible = _parent_sids.is_empty()
	_refresh_squad_cmd_bar()
	_position_group_bar()

## Сколько разных ТИПОВ войск в выделении — по этому числу решается,
## показывать ли уровень 1 (компактная полоса) вместо детальной панели
const GROUP_BAR_MIN_TYPES := 2

## Разбор выделения по типам: порядок появления, отрядов и бойцов на тип.
## Один проход на всех потребителей (полоса, панель уровня 2, стенды)
func _selection_groups() -> Dictionary:
	var order: Array = []
	var squads_by_type: Dictionary = {}
	var men_by_type: Dictionary = {}
	var src: Array = _selected_squad_ids()
	if not _parent_sids.is_empty():
		src = []
		for s0 in _parent_sids:
			if _squad_alive(int(s0)):
				src.append(int(s0))
	# Рабочие с армией — одной группой WORKER_GROUP (ниже); их одиночные
	# отряды рода «worker» здесь не считаются, иначе род встал бы дважды
	var wk: Array = _group_workers()
	for sid in src:
		var t: String = GameManager.squad_type(int(sid))
		if t.is_empty():
			continue
		if t == WORKER_GROUP and not wk.is_empty():
			continue
		if not squads_by_type.has(t):
			order.append(t)
			squads_by_type[t] = 0
			men_by_type[t] = 0
		squads_by_type[t] = int(squads_by_type[t]) + 1
		men_by_type[t] = int(men_by_type[t]) + GameManager.squad_members(int(sid)).size()
	# Рабочие — свой «род» полосы (ТЗ 30.10.2026, п. 4): у них нет отряда, и
	# в смешанном выделении они пропадали с панели. Счётчик — число рабочих
	if not wk.is_empty():
		order.append(WORKER_GROUP)
		squads_by_type[WORKER_GROUP] = wk.size()
		men_by_type[WORKER_GROUP] = wk.size()
	_sort_types(order)
	return {"order": order, "squads": squads_by_type, "men": men_by_type}

## ── РАБОЧИЕ В МУЛЬТИ-ВЫБОРЕ (ТЗ 30.10.2026, п. 4, ручка mixed_worker_group) ──
## Ячейка «worker» в полосе родов: фигура рабочего, число рабочих; клик или
## Tab — выделены одни рабочие и их обычная панель построек (артель строит
## вместе), повторный клик — вся армия обратно
const WORKER_GROUP := "worker"
const WORKER_GROUP_FIGURE := "res://assets/ui/unit_figures/%s/worker.png"
var _parent_workers: Array = []

## Свои живые рабочие текущего выделения
func _selected_workers() -> Array:
	var out: Array = []
	if not _OptSys.mixed_worker_group:
		return out
	for u in _sel_units:
		if u != null and is_instance_valid(u) and u is Worker \
				and (u as Worker).faction == Constants.FACTION_PLAYER and not (u as Worker).is_dead():
			out.append(u)
	return out

## Рабочие группы: из родительского набора, если он есть, иначе из выделения.
## Одни рабочие без армии — не мульти-выбор (у них своя панель артели)
func _group_workers() -> Array:
	if not _OptSys.mixed_worker_group:
		return []
	var out: Array = []
	if not _parent_sids.is_empty() or not _parent_workers.is_empty():
		if not _has_army_squad(_parent_sids):
			return []
		for w in _parent_workers:
			if w != null and is_instance_valid(w) and not (w as Worker).is_dead():
				out.append(w)
		return out
	if not _has_army_squad(_selected_squad_ids()):
		return []
	return _selected_workers()

## Есть ли среди отрядов хоть один живой НЕ рабочий (иначе это артель, а не
## мульти-выбор: у одних рабочих своя панель построек)
func _has_army_squad(ids: Array) -> bool:
	for s in ids:
		if GameManager.squad_type(int(s)) != WORKER_GROUP and _squad_alive(int(s)):
			return true
	return false

func _parent_clear() -> void:
	_parent_sids.clear()
	_parent_workers.clear()

func _parent_init() -> void:
	if _parent_sids.is_empty():
		_parent_sids = _selected_squad_ids()
		_parent_workers = _selected_workers() if not _parent_sids.is_empty() else []

## ── СТРОГИЙ ПОРЯДОК РОДОВ (ТЗ 27.10.2026, третье письмо, п. 3) ──────────────
## Копейщик → Лучник → Рыцарь → Монах, прочие — после них в порядке появления.
## Прежде порядок был «как попались в выделении», и роды прыгали местами от
## рамки к рамке. Тот же порядок у Tab (cycle_expanded_type)
const TYPE_ORDER := ["spearman", "archer", "warrior", "monk"]

static func _type_rank(t: String) -> int:
	var i: int = TYPE_ORDER.find(t)
	return i if i >= 0 else TYPE_ORDER.size()

static func _sort_types(order: Array) -> void:
	# Устойчивая сортировка вставкой: роды вне списка сохраняют порядок появления
	for i in range(1, order.size()):
		var v: String = String(order[i])
		var j: int = i - 1
		while j >= 0 and _type_rank(String(order[j])) > _type_rank(v):
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = v

## Бейдж портрета армии (ТЗ 30.10.2026): выделено ≥ 2 отрядов одного рода и
## род не раскрыт — число ОТРЯДОВ, а не бойцов; иначе −1
func _army_badge_squads() -> int:
	if not _OptSys.army_count_badge or _expanded_type != "":
		return -1
	var g: Dictionary = _selection_groups()
	var order: Array = g["order"]
	if order.size() != 1 or String(order[0]) == WORKER_GROUP:
		return -1
	var n: int = int((g["squads"] as Dictionary).get(order[0], 0))
	return n if n >= 2 else -1

## Сколько разных типов войск сейчас выделено (публичный — для стендов)
func selection_type_count() -> int:
	return (_selection_groups()["order"] as Array).size()

## Сколько в баннере сводных ярлыков войск.
## Публичный: раньше стенды спрашивали «есть ли панель разбивки типов» по
## наличию узла `_type_filter`; полоса теперь общая и существует всегда, так
## что вопрос корректно звучит как «сколько типов в ней показано». Ярлык
## бездельников больше не часть полосы (переехал в _build_idle_widget), так
## что счёт больше не нужно уменьшать на 1
func type_slots() -> int:
	if _overbar_row == null or not is_instance_valid(_overbar_row):
		return 0
	return _overbar_row.get_child_count()

## Отряды в текущем выделении (только свои, без повторов, в порядке появления)
func _selected_squad_ids() -> Array:
	var ids: Array = []
	for u in _sel_units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var un := u as Unit
		if un.faction != Constants.FACTION_PLAYER:
			continue
		if un.squad_id > 0 and not (un.squad_id in ids):
			ids.append(un.squad_id)
	return ids

## Сторона квадратной плашки и её отступ от панели ресурсов.
## TOP считается от факта: панель ресурсов однострочная (RES_CARD_SIZE.y=36)
## и укладывается в ~38px высоты + 8px своего верхнего отступа — проверено
## headless-замером get_global_rect() после сборки (см. qa в отчёте)
## ВДВОЕ МЕНЬШЕ (ТЗ 25.10.2026, UI, п. 3): было 52 — плашка спорила с
## мини-картой. Справа от неё — такой же значок рудников (MINE_WIDGET_GAP)
## +50 % (ТЗ 27.10.2026, второе письмо, п. 2): 26 → 39 px — рисунки рабочего
## и шахты читались точками. Цифры подросли пропорционально (IDLE_COUNT_FONT /
## MINE_COUNT_FONT), штандарт под плашкой встаёт сам (RelicButton._place)
const IDLE_WIDGET_SIZE := 39.0
const IDLE_COUNT_FONT := 14
const MINE_COUNT_FONT := 13
const IDLE_WIDGET_TOP  := 50.0
const IDLE_WIDGET_LEFT := 8.0
const MINE_WIDGET_GAP  := 4.0

## Постоянная квадратная плашка «рабочие без дела» — ПРЯМО ПОД панелью
## ресурсов, в левом верхнем углу. Раньше жила внутри over-bar'а и
## пересобиралась заново при КАЖДОЙ смене выделения (_rebuild_overbar чистит
## всех детей полосы) — сама кнопка, по которой только что кликнули, могла
## быть свободна на середине клика. Теперь это независимый узел, строится
## один раз в show_hud() и просто живёт своей жизнью через _apply_idle_state()
## /_update_idle_counter(), никак не завязанные на выделение
func _build_idle_widget() -> void:
	_idle_btn = Button.new()
	_idle_btn.name = "IdleWorkersWidget"
	_idle_btn.position = Vector2(IDLE_WIDGET_LEFT, IDLE_WIDGET_TOP)
	_idle_btn.custom_minimum_size = Vector2(IDLE_WIDGET_SIZE, IDLE_WIDGET_SIZE)
	_idle_btn.size = Vector2(IDLE_WIDGET_SIZE, IDLE_WIDGET_SIZE)
	_idle_btn.clip_contents = true
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color(0.07, 0.07, 0.13, 0.92); _corners(ist, 6)
	_borders(ist, 2); ist.border_color = Color(0.42, 0.46, 0.58)
	var hov := ist.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.13, 0.14, 0.24, 0.96)
	hov.border_color = Color(0.95, 0.88, 0.55)
	_idle_btn.add_theme_stylebox_override("normal", ist)
	_idle_btn.add_theme_stylebox_override("hover",  hov)
	_idle_btn.add_theme_stylebox_override("pressed", ist)
	# ОДИН КЛИК — ВСЕ БЕЗДЕЛЬНИКИ СРАЗУ (заказ владельца).
	# Раньше плашка обходила их по одному (_focus_next_idle_worker): чтобы
	# раздать работу шестерым, нужно было шесть раз кликнуть и шесть раз отдать
	# приказ. Метод обхода оставлен — он пригодится под отдельную горячую клавишу
	_idle_btn.tooltip_text = "Рабочие без дела. Клик — выделить ВСЕХ"
	_idle_btn.pressed.connect(_select_idle_workers)
	add_child(_idle_btn)
	_idle_widget = _idle_btn

	var ipath: String = String(UNIT_ICONS.get("worker", ""))
	var got_icon := false
	if ipath != "" and ResourceLoader.exists(ipath):
		var tex := load(ipath) as Texture2D
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			# EXPAND_IGNORE_SIZE обязателен: иначе TextureRect репортит своим
			# minimum_size НАТУРАЛЬНЫЙ размер текстуры (тут — десятки-сотни px)
			# в обход custom_minimum_size, и MarginContainer-родитель раздувается
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			# mouse_filter=IGNORE обязателен: иначе картинка съест клик и
			# кнопка под ней перестанет нажиматься
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var m := MarginContainer.new()
			m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for side in ["left", "top", "right", "bottom"]:
				m.add_theme_constant_override("margin_" + side, 2)
			m.add_child(tr)
			_idle_btn.add_child(m)
			got_icon = true
	if not got_icon:
		# Ассета нет — не оставлять же плашку пустой: подписываем киркой
		_idle_btn.text = "⛏"
		_idle_btn.add_theme_font_size_override("font_size", 20)

	# СЧЁТЧИК — ГОЛАЯ ЦИФРА В УГЛУ ИКОНКИ, БЕЗ ПОДЛОЖКИ.
	# Раньше цифра сидела в собственном PanelContainer с тёмной заливкой, и на
	# картинке рабочего это читалось как «чёрный квадрат под цифрой» (прямая
	# жалоба владельца). Подложка была нужна только ради читаемости — ту же
	# работу делает чёрная ОБВОДКА самого шрифта, и она не рисует лишней
	# геометрии. Label кладём прямо в кнопку: Button — не PanelContainer, детям
	# раскладку он не навязывает, поэтому якорь на нижний правый угол работает
	_idle_count_label = Label.new()
	_idle_count_label.name = "IdleCount"
	_idle_count_label.text = "0"
	_idle_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Цифра под вдвое меньшую плашку: читается, но не закрывает рисунок
	_idle_count_label.add_theme_font_size_override("font_size", IDLE_COUNT_FONT)
	_idle_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_idle_count_label.add_theme_constant_override("outline_size", 3)
	_idle_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_idle_count_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	_idle_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_idle_count_label.offset_right  = -1
	_idle_count_label.offset_bottom = 1
	_idle_btn.add_child(_idle_count_label)

	_apply_idle_state(_idle_last if _idle_last >= 0 else 0)
	_build_mine_widget()

## ── ЗНАЧОК РУДНИКОВ — РЯДОМ С ПЛАШКОЙ БЕЗДЕЛЬНИКОВ (ТЗ 25.10.2026, UI, п. 3)
## Был мини-шахтой под монетой в панели ресурсов, с крупной цифрой. Теперь —
## такой же маленький квадрат справа от плашки рабочих: рисунок шахты и
## мелкая цифра работающих рудников в углу. Прячется, пока рудников нет;
## подсказка и число — из того же пересчёта (_update_resources)
func _build_mine_widget() -> void:
	var box := Panel.new()
	box.name = "MineBox"
	box.position = Vector2(IDLE_WIDGET_LEFT + IDLE_WIDGET_SIZE + MINE_WIDGET_GAP, IDLE_WIDGET_TOP)
	box.custom_minimum_size = Vector2(IDLE_WIDGET_SIZE, IDLE_WIDGET_SIZE)
	box.size = Vector2(IDLE_WIDGET_SIZE, IDLE_WIDGET_SIZE)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.07, 0.13, 0.92); _corners(st, 6)
	_borders(st, 2); st.border_color = Color(0.42, 0.46, 0.58)
	box.add_theme_stylebox_override("panel", st)
	box.visible = false
	var mic := TextureRect.new()
	mic.texture = _trimmed_icon("res://assets/environment/resources/Gold_mine/GoldMine_Active.png")
	mic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mic.offset_left = 2; mic.offset_top = 2; mic.offset_right = -2; mic.offset_bottom = -2
	box.add_child(mic)
	_mine_count_lbl = Label.new()
	_mine_count_lbl.text = "0"
	_mine_count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Цифра — мельче рисунка (жалоба: «двойка» доминировала над шахтой)
	_mine_count_lbl.add_theme_font_size_override("font_size", MINE_COUNT_FONT)
	_mine_count_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_mine_count_lbl.add_theme_constant_override("outline_size", 3)
	_mine_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mine_count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_mine_count_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mine_count_lbl.offset_right = -1
	_mine_count_lbl.offset_bottom = 1
	box.add_child(_mine_count_lbl)
	_mine_income_lbl = Label.new()
	_mine_income_lbl.visible = false
	box.add_child(_mine_income_lbl)
	add_child(box)
	_mine_box = box

## Натуральный размер исходной иконки ресурса и её отображаемый размер.
## Панель увеличена на +30% ширины / +20% высоты (см. RES_CARD_SIZE) —
## иконка растёт вместе с высотой карточки, тем же множителем, чтобы не
## оказаться карликом в разросшемся ряду. Единый размер для ВСЕХ 4 ресурсов —
## это и есть требование "одинаковый размер иконок", разный ФАЙЛ разного
## аспекта центрируется в одной и той же рамке STRETCH_KEEP_ASPECT_CENTERED
## ПАНЕЛЬ УМЕНЬШЕНА НА 40% ПО ШИРИНЕ, но стала НЕМНОГО ВЫШЕ (заказ владельца):
## иконка и две подписи должны помещаться внутри с воздухом, а не упираться в
## кромку. Поэтому ширина ужимается (0.60 от прежней), а высота карточки задана
## отдельным числом и даже подросла.
## ИКОНКА НЕ УМЕНЬШАЕТСЯ ВМЕСТЕ С ПАНЕЛЬЮ: п.6 требует ровно обратного —
## камень и золото читались точками на фоне дерева и мяса
const RES_ICON_FULL    := 40.0
const RES_PANEL_SCALE_W := 0.60
const RES_PANEL_SCALE_H := 1.00
## Иконка ужимается заметно МЕНЬШЕ панели: рисунок в ней теперь обрезан по
## непрозрачному содержимому (_trimmed_icon), поэтому 21 px «чистой» картинки
## читается лучше, чем прежние 24 px с прозрачными полями по краям
const RES_ICON_DISPLAY := 21.0
## Ширина места под число и под приток. Фиксированные, чтобы секции не
## дёргались при росте чисел — см. комментарий в _build_resource_card.
## Это МИНИМУМ, а не потолок: пятизначное число раздвинет свою секцию само
const RES_AMOUNT_W := 27.0
const RES_INCOME_W := 19.0
## Сколько рабочих сейчас приписано к этому ресурсу — "⛏3", тем же глифом,
## что и заглушка на плашке бездельников (см. _build_idle_widget), так что
## это узнаваемо как "рабочие", а не ещё одно число прироста. Узко: обычно
## 1-2 цифры, ресурсных точек с двузначной толпой рабочих не бывает.
## УЖАТО 11 → 9: хвост вернулся во все четыре секции (заказ владельца), и
## каждый лишний пиксель здесь умножается на четыре — панель и без того выросла
const RES_WORKERS_W := 9.0
## Зазор ВНУТРИ пары приток+рабочие (см. _build_resource_card) — уже RES_INNER_SEP,
## это не отдельная секция, а хвост одной и той же строки
const RES_INC_WK_SEP := 1
## Зазор между иконкой/числом/притоком ВНУТРИ секции и между секциями.
## Держим мелким: разделяет секции тонкий VSeparator, а не воздух вокруг них —
## с крупным зазором панель растягивалась вдвое шире нужного при том же тексте
const RES_INNER_SEP := 3
const RES_OUTER_SEP := 2
## Габарит одной секции (одна строка: иконка + число + [приток+рабочие]).
## Приток и рабочие сидят во вложенном HBox с УЗКИМ зазором (RES_INC_WK_SEP) —
## на уровне row это по-прежнему ДВА зазора (icon-amt, amt-[приток+рабочие]),
## а не три: секция должна обтягивать содержимое, а не оставлять пустоту
## ГАБАРИТ СЕКЦИИ БЕЗ ХВОСТА «ИНСТРУМЕНТ + РАБОЧИЕ».
## Оставлен как база, от которой считается RES_CARD_SIZE_WORKERS: сейчас хвост
## есть у ВСЕХ четырёх секций (владелец попросил вернуть счётчик рабочих на
## каждый ресурс), но пустоты от него больше не бывает — см. _build_resource_card
const RES_CARD_SIZE := Vector2(
	RES_ICON_DISPLAY + RES_AMOUNT_W + RES_INCOME_W \
		+ float(RES_INNER_SEP) * 2.0,
	38.0 * RES_PANEL_SCALE_H)
## Насколько шире секция с хвостом: глифу инструмента и счётчику рабочих нужно
## СВОЁ место, а не отъедаемое у числа запаса.
## УЖАТО 15 → 12 по той же причине, что и RES_WORKERS_W: глиф там ровно один
## символ кегля 12, а секций теперь четыре
const RES_WORKER_GLYPH_W := 12.0
const RES_CARD_SIZE_WORKERS := Vector2(
	RES_CARD_SIZE.x + RES_WORKER_GLYPH_W + RES_WORKERS_W + float(RES_INC_WK_SEP) * 2.0,
	RES_CARD_SIZE.y)

const RES_DEFS := [
	{"key": Constants.RESOURCE_WOOD,  "icon": Color(0.45, 0.28, 0.10), "label": "Wood",  "ipath": "res://assets/factions/humans/icons/hud/Woods.png"},
	{"key": Constants.RESOURCE_STONE, "icon": Color(0.55, 0.52, 0.48), "label": "Stone", "ipath": "res://assets/environment/resources/Rock2.png"},
	{"key": Constants.RESOURCE_GOLD,  "icon": Color(1.00, 0.78, 0.05), "label": "Gold",  "ipath": "res://assets/factions/humans/icons/hud/Gold_Resource.png"},
	{"key": Constants.RESOURCE_FOOD,  "icon": Color(0.20, 0.70, 0.20), "label": "Food",  "ipath": "res://assets/factions/humans/icons/hud/Meat.png"},
]

func _build_resource_bar() -> void:
	var panel := PanelContainer.new()
	panel.name = "ResourceBar"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.08, 0.90)
	style.border_width_bottom = 2; style.border_color = Color(0.30, 0.25, 0.15)
	# ВСЕ ЧЕТЫРЕ УГЛА, как у правой верхней панели. Скруглены были только нижние:
	# панель стояла в 8px от края экрана, то есть не примыкала к нему, и её
	# верхние углы торчали острыми — рядом с аккуратной правой панелью это
	# бросалось в глаза
	_corners(style, 6)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(8, 8)
	add_child(panel)
	_res_panel = panel

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", RES_OUTER_SEP)
	panel.add_child(hbox)

	hbox.add_child(_pad(3, 0))

	# ЕДИНАЯ ПЛАШКА, 4 РАВНЫЕ СЕКЦИИ. Разделитель — только МЕЖДУ карточками
	# (не после последней): дерево | камень | золото | еда. Кнопка "Меню"
	# сюда больше не ставится — её место в правой верхней панели
	# (см. _build_top_right_widget), рядом с паузой/таймером/FPS, единым
	# тёмным стилем без выделяющегося красного пятна
	for i in range(RES_DEFS.size()):
		hbox.add_child(_build_resource_card(RES_DEFS[i]))
		if i < RES_DEFS.size() - 1:
			hbox.add_child(VSeparator.new())

	# ЛИМИТ НАСЕЛЕНИЯ (дома, 09.09.2026): «раб. 4/6 · отр. 2/3». Показывается
	# только когда лимит действует (GameManager.pop_limit_enabled)
	# ── ИКОНКИ ВМЕСТО СЛОВ (ТЗ 24.09.2026, п. 5) ─────────────────────────
	# «раб.» → портрет рабочего, «армия» → портрет копейщика; к числу бойцов
	# добавлено число ОТРЯДОВ. Два Label вместо одного: цвет «полон» у каждой
	# половины свой — упёрся лимит рабочих, армию красить незачем
	_pop_sep = VSeparator.new()
	hbox.add_child(_pop_sep)
	_pop_label = Label.new()      # рабочие: «13/41»
	_pop_army_label = Label.new() # армия: «0/515 · 0 отр.»
	var tip: String = "Лимит населения: рабочие и БОЙЦЫ (ТЗ 23.09.2026 — армия считается головами, не отрядами). Каждый дом даёт +%d рабочих и +%d мест в армии; потолок армии %d, это примерно %d домов" % [
		_UCfg.HOUSE_WORKER_SLOTS, _UCfg.ARMY_HOUSE_UNITS,
		_UCfg.ARMY_HARD_CAP, _UCfg.houses_for_full_army(1)]
	_pop_box = HBoxContainer.new()
	_pop_box.add_theme_constant_override("separation", 3)
	_pop_box.tooltip_text = tip
	_pop_box.mouse_filter = Control.MOUSE_FILTER_PASS
	for pair in [["worker", _pop_label], ["spearman", _pop_army_label]]:
		var ic := TextureRect.new()
		ic.texture = _trimmed_icon(String(UNIT_ICONS.get(String(pair[0]), "")))
		ic.custom_minimum_size = Vector2(RES_ICON_DISPLAY, RES_ICON_DISPLAY)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_pop_box.add_child(ic)
		var lb: Label = pair[1]
		lb.add_theme_font_size_override("font_size", 13)
		lb.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95))
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.tooltip_text = tip
		_pop_box.add_child(lb)
	hbox.add_child(_pop_box)
	_pop_sep.visible = false
	_pop_box.visible = false

	hbox.add_child(_pad(3, 0))

## Одна секция ресурсной панели: ИКОНКА, БЕЛОЕ ЧИСЛО и ЗЕЛЁНЫЙ ПРИТОК на
## ОДНОЙ горизонтальной линии — единый HBoxContainer, никакой вложенной
## VBox+HBox структуры. Раньше иконка с подписью были верхней строкой, а
## число с притоком — нижней; Label внутри HBoxContainer растягивался по
## высоте соседа и рисовал текст прижатым к верху рамки, из-за чего Gold
## заметно "проваливался" относительно своей иконки. Одна строка убирает
## саму возможность такого рассогласования
## ИКОНКА, ОБРЕЗАННАЯ ПО НЕПРОЗРАЧНОМУ СОДЕРЖИМОМУ.
##
## Все 4 иконки рисуются в одинаковой рамке RES_ICON_DISPLAY с сохранением
## пропорций — и всё равно камень с золотом выглядели точками рядом с деревом и
## мясом. Причина не в размере рамки, а в САМИХ ФАЙЛАХ: Woods.png и Meat.png —
## это готовые иконки, у которых рисунок занимает почти весь холст, а
## Rock2.png и Gold_Resource.png взяты из мировых спрайтов, где полезная
## картинка сидит в середине большого прозрачного поля. KEEP_ASPECT_CENTERED
## честно вписывает ВЕСЬ холст, вместе с пустотой, — отсюда и «точки».
##
## Лечим источник: считаем непрозрачный прямоугольник (Image.get_used_rect) и
## отдаём AtlasTexture ровно по нему. Дальше все четыре картинки заполняют свою
## рамку одинаково, и никаких ручных множителей на каждый файл не нужно —
## новая иконка подстроится сама.
func _trimmed_icon(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		# Сжатый в VRAM формат нельзя опрашивать попиксельно
		if img.decompress() != OK:
			return tex
	var used: Rect2i = img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return tex
	# Уже плотная иконка — не трогаем: лишний AtlasTexture ничего не даст
	if used.position == Vector2i.ZERO and used.size == img.get_size():
		return tex
	var atlas := AtlasTexture.new()
	atlas.atlas  = tex
	atlas.region = Rect2(used)
	atlas.filter_clip = true
	return atlas

## Тематические значки профессии у счётчика рабочих на ресурсе: топорик у
## дерева, ножик у мяса. Камень/золото своей иконки инструмента не получают —
## там нет тематического глифа, а "⛏N" сам по себе достаточно читаем.
## ГЛИФ, А НЕ ТЕКСТУРА: единственная реальная иконка-инструмент в проекте
## (icon_axe.png, папка кузницы) — это большая орнаментальная RPG-картинка
## на чёрном фоне с красными лучами и золотой рамкой, рассчитанная на показ
## ~40-56px; при сжатии до 12px рамка с лучами превращаются в нечитаемое
## бурое пятно, а не в узнаваемый топорик. Отдельного файла-ножа в проекте
## нет вовсе. Проверено скриншотом (qa_shot_final_tmp), что проектный шрифт
## честно рисует 🪓/🔪 таким же способом, каким уже рисуется "⛏" — тот же
## приём, тот же размер, никакой возни с обрезкой спрайт-листов
## ═════════════════════════════════════════════════════════════════════════════
## СЧЁТЧИК РАБОЧИХ ЕСТЬ У КАЖДОГО РЕСУРСА (заказ владельца, возврат).
##
## История этого места стоит того, чтобы её помнить, — его переделывали дважды.
## Сначала инструмент и «⛏N» стояли во всех четырёх секциях, но место под них
## резервировалось даже там, где ничего не рисовалось, и владелец попросил убрать
## пустые зазоры — тогда хвост свели в одну секцию (еду). Теперь просьба обратная
## и по делу: игрок должен видеть, СКОЛЬКО РАБОЧИХ КОПАЕТ КАЖДЫЙ РЕСУРС, иначе
## распределить артель по дереву/камню/золоту можно только на память.
##
## Пустоты при этом больше нет: хвост рисуется во всех секциях, значит
## зарезервированная ширина всегда занята. Разница между секциями — только в
## СМЫСЛЕ числа (см. RES_WORKER_SECTION ниже) и в глифе инструмента.
## ═════════════════════════════════════════════════════════════════════════════
## СЕКЦИЯ С ОБЩИМ ЧИСЛОМ РАБОЧИХ — крайняя правая (еда).
## Подушевой счёт «рабочих на еде» здесь был бы мёртвым числом: еду в этой игре
## не добывают, её дают Домики, поэтому «рабочих на еде» всегда ноль. Вместо
## этого секция показывает ОБЩЕЕ число рабочих игрока — тот самый «лимит/число
## всех рабочих» из задания
## ── ОБЩЕГО СЧЁТЧИКА РАБОЧИХ В ПАНЕЛИ БОЛЬШЕ НЕТ (заказ владельца, разворот) ──
## Секция еды показывала ОБЩЕЕ число рабочих игрока — потому что еду в этой игре
## не добывают (её дают Домики), и «рабочих на еде» всегда ноль. Владелец
## попросил обратное: пусть на мясе стоит честный ноль, пока еду никто не
## добывает. Значит все четыре секции отвечают на ОДИН вопрос — «сколько рабочих
## сидит на этом ресурсе», — и исключения не осталось вовсе.
##
## ЧЕСТНОЕ СЛЕДСТВИЕ: числа «всего рабочих» в интерфейсе теперь нет нигде.
## Ближайшее по смыслу — счётчик простаивающих (левый верхний виджет).
## −1 = «такой секции нет»; ветка сохранена, чтобы вернуть общий счётчик было
## правкой одной строки, а не восстановлением удалённого кода
const RES_WORKER_SECTION := -1
## ── ГЛИФ ИНСТРУМЕНТА СВОЙ У КАЖДОГО РЕСУРСА ─────────────────────────────────
## Была одна кирка на дерево, камень и золото. По лесу это просто неправда:
## дерево рубят топором, и на скриншоте владельца ⛏ у брёвен читался как ошибка.
## Инструмент теперь тот же, что у рабочего в анимации (Worker._update_sprite_anim):
## топор на лесе, кирка на камне и золоте, нож на еде
const RES_TOOL_GLYPHS := {
	Constants.RESOURCE_WOOD:  "🪓",
	Constants.RESOURCE_STONE: "⛏",
	Constants.RESOURCE_GOLD:  "⛏",
	# У еды — НОЖ (ТЗ 12.10.2026): мясо режут фермеры загона, кирка у красного
	# расхода читалась как ошибка
	Constants.RESOURCE_FOOD:  "🔪",
}
## Запасной глиф для ресурса, которого нет в таблице
const RES_GATHER_GLYPH := "⛏"

func _build_resource_card(rd: Dictionary) -> Control:
	var row := HBoxContainer.new()
	# ХВОСТ ЕСТЬ У ВСЕХ СЕКЦИЙ — значит и габарит у всех одинаковый.
	# Раньше здесь была развилка (широкая карточка только у еды), и панель
	# ресурсов была из трёх узких секций и одной широкой
	row.custom_minimum_size = RES_CARD_SIZE_WORKERS
	row.add_theme_constant_override("separation", RES_INNER_SEP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ip: String = rd["ipath"]
	var tex: Texture2D = _trimmed_icon(ip)
	var icon_node: Control = null
	if tex != null:
		var tr := TextureRect.new()
		icon_node = tr
		tr.texture = tex
		tr.custom_minimum_size = Vector2(RES_ICON_DISPLAY, RES_ICON_DISPLAY)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Без этого TextureRect навязывает контейнеру НАТУРАЛЬНЫЙ размер файла
		# текстуры (у части иконок — сотня с лишним px) вместо custom_minimum_size:
		# это и раздуло панель ресурсов со ~130px высоты вместо однострочных ~36
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tr)
	else:
		var ic := ColorRect.new()
		ic.color = rd["icon"]
		ic.custom_minimum_size = Vector2(RES_ICON_DISPLAY, RES_ICON_DISPLAY)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)

	# ЧИСЛО И ПРИТОК — БЕЗ clip_text!
	# clip_text=true обнуляет собственную минимальную ширину Label (движок
	# считает, что текст всё равно будет обрезан), а HBoxContainer выдаёт
	# нерастягиваемому ребёнку РОВНО его минимум — обе подписи схлопывались
	# в 1 пиксель, и в панели оставались одни иконки: числа были на месте, но
	# шириной в пиксель. Вместо обрезки держим ФИКСИРОВАННУЮ минимальную
	# ширину: она и не даёт секциям дёргаться, когда 450 превращается в 12500
	# (ради чего clip_text и ставился), и текст при этом виден целиком —
	# перерасти минимум Label может, обрезаться в ноль уже нет
	var amt_lbl := Label.new()
	amt_lbl.text = "0"
	amt_lbl.custom_minimum_size = Vector2(RES_AMOUNT_W, 0)
	amt_lbl.add_theme_font_size_override("font_size", 13)
	amt_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(amt_lbl)
	_res_labels[rd["key"]] = amt_lbl

	# ПРИТОК И РАБОЧИЕ — В ОБЩЕЙ ВЛОЖЕННОЙ HBox, а не прямо в row.
	# row задаёт ОДИН зазор (RES_INNER_SEP) МЕЖДУ ЛЮБЫМИ соседями, а этой паре
	# нужен зазор поуже — иначе секция снова растягивается вдвое шире, чем
	# требуется под текст (та же грабля, что и в комментарии выше про row)
	var inc_wk_box := HBoxContainer.new()
	inc_wk_box.add_theme_constant_override("separation", 1)
	inc_wk_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(inc_wk_box)

	var income_lbl := Label.new()
	income_lbl.text = ""
	income_lbl.visible = false
	income_lbl.custom_minimum_size = Vector2(RES_INCOME_W, 0)
	income_lbl.add_theme_font_size_override("font_size", 11)
	income_lbl.add_theme_color_override("font_color", Color(0.35, 0.9, 0.35))
	income_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	income_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inc_wk_box.add_child(income_lbl)
	_res_income_labels[rd["key"]] = income_lbl
	# ── РАСХОД ЕДЫ — СВОЕЙ КРАСНОЙ ЦИФРОЙ (ТЗ 24.09.2026, п. 5) ─────────────
	# «+52» зелёным, «−26» красным: одним Label двух цветов не нарисовать
	if int(rd["key"]) == Constants.RESOURCE_FOOD:
		_food_upkeep_label = Label.new()
		_food_upkeep_label.text = ""
		_food_upkeep_label.visible = false
		_food_upkeep_label.add_theme_font_size_override("font_size", 11)
		_food_upkeep_label.add_theme_color_override("font_color", Color(0.95, 0.35, 0.30))
		_food_upkeep_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		inc_wk_box.add_child(_food_upkeep_label)

	# ── ХВОСТ «ИНСТРУМЕНТ + РАБОЧИЕ» — В КАЖДОЙ СЕКЦИИ ──────────────────────
	# Одно и то же во всех четырёх: «столько рабочих сидит на ЭТОМ ресурсе».
	# Инструмент свой у каждого — топор на лесе, кирка на камне и золоте, нож на
	# еде (см. RES_TOOL_GLYPHS)
	var tool_lbl := Label.new()
	tool_lbl.text = String(RES_TOOL_GLYPHS.get(int(rd["key"]), RES_GATHER_GLYPH))
	tool_lbl.visible = false
	tool_lbl.add_theme_font_size_override("font_size", 12)
	tool_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tool_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inc_wk_box.add_child(tool_lbl)
	_res_tool_labels[rd["key"]] = tool_lbl

	# ЧИСЛО РАБОЧИХ рядом с инструментом. Скрыт, пока рабочих нет
	var workers_lbl := Label.new()
	workers_lbl.text = ""
	workers_lbl.visible = false
	workers_lbl.custom_minimum_size = Vector2(RES_WORKERS_W, 0)
	workers_lbl.add_theme_font_size_override("font_size", 11)
	workers_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 0.98))
	workers_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	workers_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inc_wk_box.add_child(workers_lbl)
	_res_workers_labels[rd["key"]] = workers_lbl

	# Рудники больше не висят под монетой: значок переехал к плашке
	# бездельников (_build_mine_widget, ТЗ 25.10.2026)

	return row

# ─────────────────────────────────────────────────────────────────────────────
# ТАЙМЕР ПАРТИИ / FPS / ПАУЗА — правый верхний угол
# Таймер копит секунды сам, независимо от паузы меню (см. _update_top_right):
# HUD живёт в PROCESS_MODE_ALWAYS ради самого меню паузы, поэтому счёт нужно
# гасить вручную по get_tree().paused, а не полагаться на остановку _process.
# Пауза здесь — тот же get_tree().paused, что и у "≡ Меню": кнопка и ESC-меню
# читают один и тот же флаг, так что они не могут разойтись по состоянию.
# ─────────────────────────────────────────────────────────────────────────────
## Ширина панели увеличена на 30% (было 210), кнопка паузы — в 2 раза
## (было 26x0), плюс панель через MarginContainer отведена от углов экрана,
## чтобы курсор при клике по кнопке не упирался в самую границу монитора.
## +88 — под кнопку "≡ Меню", переехавшую сюда из панели ресурсов, чтобы вся
## правая верхняя полоса (пауза/таймер/FPS/меню) была одним цельным блоком
## ШИРИНЫ У ПАНЕЛИ БОЛЬШЕ НЕТ — она обтягивает содержимое.
## Раньше здесь стояло фиксированное число (273 + 88), заметно больше суммы
## пауза+таймер+FPS+меню: разница висела пустым чёрным хвостом справа от
## кнопки «Меню» — тем самым, на который жаловались. Панель прижата к правому
## краю (GROW_DIRECTION_BEGIN) и растёт влево ровно настолько, сколько нужно
## содержимому, поэтому хвосту взяться неоткуда ни при каком разрешении.
## Всё внутри уменьшено на 30%
## ЗЕРКАЛО ЛЕВОЙ ПАНЕЛИ: ResourceBar стоит в (8, 8) от угла экрана (см.
## _build_resource_bar, panel.position = Vector2(8, 8)) — раньше здесь было
## 22/16, и правая панель заметно "провисала" ниже левой и была дальше от
## края. 8/8 кладёт обе панели на одну линию Y и с равным отступом от краёв
const TOP_RIGHT_MARGIN_R := 8.0
const TOP_RIGHT_MARGIN_T := 8.0

var _match_seconds: float = 0.0
var _timer_label: Label  = null
var _truce_label: Label  = null
var _fps_label:   Label  = null
## Индикатор режима построения ([1] широкий / [2] коробочка). Заведён вместе
## с тем, что режим стал ЗАПОМИНАТЬСЯ: невидимый запомненный строй читается
## игроком как самоволка игры (разбор — в SelectionManager, у снятого сброса)
var _formation_label: Label = null
var _pause_btn:   Button = null

func _build_top_right_widget() -> void:
	var margin := MarginContainer.new()
	margin.name = "TopRightMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.anchor_left  = 1.0
	margin.anchor_right = 1.0
	margin.offset_right = -TOP_RIGHT_MARGIN_R
	margin.offset_top   = TOP_RIGHT_MARGIN_T
	# offset_left НЕ ЗАДАЁМ: ширину диктует содержимое, а панель растёт ВЛЕВО
	# от правого края. Так исчезает пустой хвост справа (см. TOP_RIGHT_MARGIN_R)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.size_flags_horizontal = Control.SIZE_SHRINK_END
	add_child(margin)

	var panel := PanelContainer.new()
	panel.name = "TopRightWidget"
	_top_right = panel        # держим ссылку: правый блок тоже «держит фокус» (см. point_over_ui)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.08, 0.90)
	style.border_width_bottom = 2; style.border_color = Color(0.30, 0.25, 0.15)
	style.corner_radius_top_left = 6; style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6; style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 7)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	hbox.add_child(_pad(3, 0))

	_pause_btn = Button.new()
	_pause_btn.text = "⏸"
	_pause_btn.custom_minimum_size = Vector2(36, 0)
	_pause_btn.add_theme_font_size_override("font_size", 18)
	_pause_btn.tooltip_text = "Пауза / продолжить  (Z)"
	_pause_btn.pressed.connect(_on_pause_btn_pressed)
	hbox.add_child(_pause_btn)

	_timer_label = Label.new()
	_timer_label.text = "00:00"
	_timer_label.add_theme_font_size_override("font_size", 14)
	_timer_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	hbox.add_child(_timer_label)
	# ── ПЛАШКА ПЕРЕМИРИЯ (ТЗ 14.09.2026, п. 2) ────────────────────────────
	# Своя плашка, а не хвост таймера: чекбокс «Перемирие» гасит её целиком
	# (visible), а таймер партии остаётся. Видна, пока чекбокс включён и
	# отсчёт не истёк; текст ведёт _update_top_right
	_truce_label = Label.new()
	_truce_label.name = "TruceLabel"
	_truce_label.visible = false
	_truce_label.add_theme_font_size_override("font_size", 12)
	_truce_label.add_theme_color_override("font_color", Color(0.75, 0.92, 0.75))
	var truce_style := StyleBoxFlat.new()
	truce_style.bg_color = Color(0.10, 0.22, 0.12, 0.85)
	truce_style.corner_radius_top_left = 4; truce_style.corner_radius_top_right = 4
	truce_style.corner_radius_bottom_left = 4; truce_style.corner_radius_bottom_right = 4
	truce_style.content_margin_left = 6; truce_style.content_margin_right = 6
	truce_style.content_margin_top = 1; truce_style.content_margin_bottom = 1
	_truce_label.add_theme_stylebox_override("normal", truce_style)
	hbox.add_child(_truce_label)

	var sep := VSeparator.new(); hbox.add_child(sep)

	_fps_label = Label.new()
	# ВИДИМОСТЬ — ИЗ НАСТРОЕК МЕНЮ (заказ 10.09.2026, чекбокс «Отображать
	# FPS»); F3 по-прежнему переключает её на ходу
	_fps_label.visible = _GSHud.show_fps()
	_fps_label.text = "FPS: 0"
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	hbox.add_child(_fps_label)

	# ── РЕЖИМ СТРОЯ — БОЛЬШЕ НЕ ТЕКСТОМ ЗДЕСЬ (ТЗ 11.10.2026, ч. 1 п. 6) ─────
	# Режим по-прежнему виден всегда (заказ 13.09.2026), но схемой в окошке над
	# мини-картой (scripts/FormationPanel.gd), а не строкой «строй [1] широкий»
	# в этой панели. _formation_label остаётся null — ветка обновления ниже
	# его пропускает

	var sep2 := VSeparator.new(); hbox.add_child(sep2)

	# "МЕНЮ" — ВСЯ ПРАВАЯ СЕКЦИЯ ПАНЕЛИ ЦЕЛИКОМ, а не кнопка в кнопке.
	# Раньше у неё была своя рамка и свои скругления поверх фона панели: внутри
	# тёмного блока рисовался ещё один блок поменьше, и это читалось как
	# «кнопка внутри кнопки». Теперь стиль normal ПОЛНОСТЬЮ прозрачный и без
	# рамки — секция выглядит частью панели и вся целиком кликабельна, а
	# подсветка появляется только под курсором
	var menu_btn := Button.new()
	menu_btn.name = "MenuButton"
	menu_btn.text = "≡ Меню"
	menu_btn.add_theme_font_size_override("font_size", 13)
	menu_btn.add_theme_color_override("font_color", Color(0.90, 0.92, 0.97))
	menu_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	menu_btn.size_flags_vertical = Control.SIZE_FILL
	var mn := StyleBoxFlat.new()
	mn.bg_color = Color(1, 1, 1, 0.0)
	mn.border_width_left = 0; mn.border_width_right = 0
	mn.border_width_top  = 0; mn.border_width_bottom = 0
	mn.content_margin_left = 8; mn.content_margin_right = 8
	var mh := mn.duplicate() as StyleBoxFlat
	mh.bg_color = Color(1, 1, 1, 0.10)
	_corners(mh, 6)
	menu_btn.add_theme_stylebox_override("normal", mn)
	menu_btn.add_theme_stylebox_override("hover",  mh)
	menu_btn.add_theme_stylebox_override("pressed", mh)
	menu_btn.add_theme_stylebox_override("focus", mn)
	menu_btn.pressed.connect(_show_pause_menu)
	hbox.add_child(menu_btn)

	hbox.add_child(_pad(3, 0))

func _on_pause_btn_pressed() -> void:
	toggle_pause()

## ЕДИНСТВЕННАЯ ТОЧКА ПАУЗЫ ИГРЫ: иконка ⏸ и клавиша Z зовут ровно её.
##
## Пауза теперь ЗВУКОВАЯ ТОЖЕ. AudioManager — автозагрузка в PROCESS_MODE_ALWAYS
## (иначе на паузе не крутились бы ползунки громкости), поэтому get_tree().paused
## его не касался: над замершей картинкой продолжали играть лес и музыка.
##
## Меню настроек (Escape → _show_pause_menu) звук НЕ глушит намеренно: там стоят
## ползунки громкости, и проверять их на слух в тишине невозможно
func toggle_pause() -> void:
	set_paused(not get_tree().paused)

func set_paused(on: bool) -> void:
	get_tree().paused = on
	AudioManager.set_paused(on)
	if _pause_btn != null and is_instance_valid(_pause_btn):
		_pause_btn.text = "▶" if on else "⏸"

## F3 — показать/спрятать счётчик FPS. Сам таймер партии и пауза не гасятся:
## переключается только видимость плашки FPS (см. Main._input)
func toggle_fps_counter() -> void:
	if _fps_label:
		_fps_label.visible = not _fps_label.visible

func _format_match_time(total_seconds: float) -> String:
	var s: int = int(total_seconds)
	var h: int = s / 3600
	var m: int = (s / 60) % 60
	var sec: int = s % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, sec]
	return "%02d:%02d" % [m, sec]

## Вызывается ПЕРВЫМ делом из _process, до всех ранних return по выделению
## Счётчик населения в панели ресурсов (см. _build_resource_bar)
var _pop_label: Label = null
var _pop_army_label: Label = null
var _pop_box: HBoxContainer = null
var _pop_sep: VSeparator = null
var _pop_timer: float = 0.0
const POP_REFRESH_SEC := 0.5

func _refresh_pop(delta: float) -> void:
	if _pop_label == null or not is_instance_valid(_pop_label):
		return
	_pop_timer -= delta
	if _pop_timer > 0.0:
		return
	_pop_timer = POP_REFRESH_SEC
	var on: bool = GameManager.pop_limit_enabled
	if _pop_box != null and is_instance_valid(_pop_box):
		_pop_box.visible = on
	if _pop_sep != null and is_instance_valid(_pop_sep):
		_pop_sep.visible = on
	if not on:
		return
	var f: int = Constants.FACTION_PLAYER
	var wu: int = GameManager.pop_workers_used(f)
	var wc: int = GameManager.pop_worker_cap(f)
	var su: int = GameManager.pop_army_used(f)
	var sc: int = GameManager.pop_army_cap(f)
	# ── ЕДИНЫЙ ФОРМАТ «ЕСТЬ / ЛИМИТ» (ТЗ 24.09.2026, второе письмо) ────────
	# Сырые «181/605 бойцов» убраны: рядом с копейщиком — ОТРЯДЫ и лимит в
	# отрядах. Бойцы и их лимит — во всплывающей подсказке
	var sq: int = GameManager.pop_army_squads(f)
	var sq_cap: int = GameManager.pop_squad_limit(f)
	_pop_label.text = "%d / %d" % [wu, wc]
	_pop_army_label.text = "%d / %d" % [sq, sq_cap]
	_pop_army_label.tooltip_text = "Отряды: %d из %d. Бойцов %d из %d" % [sq, sq_cap, su, sc]
	_pop_label.add_theme_color_override("font_color",
		Color(0.95, 0.60, 0.50) if wu >= wc else Color(0.85, 0.90, 0.95))
	_pop_army_label.add_theme_color_override("font_color",
		Color(0.95, 0.60, 0.50) if (su >= sc or sq >= sq_cap) else Color(0.85, 0.90, 0.95))

func _update_top_right(delta: float) -> void:
	_refresh_pop(delta)
	if _timer_label == null or not is_instance_valid(_timer_label):
		return
	if not get_tree().paused:
		_match_seconds += delta
	_timer_label.text = _format_match_time(_match_seconds)
	# Перемирие первых минут (спринт 20): игрок видит, сколько осталось.
	# Плашка своя и гаснет вместе с чекбоксом (ТЗ 14.09.2026, п. 2)
	if _truce_label != null and is_instance_valid(_truce_label):
		var tl: float = GameManager.truce_left()
		var show: bool = GameManager.truce_enabled() and tl > 0.0
		if _truce_label.visible != show:
			_truce_label.visible = show
		if show:
			_truce_label.text = "перемирие %s" % _format_match_time(tl)
	if _fps_label and _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# ── ИНДИКАТОР СТРОЯ ───────────────────────────────────────────────────
	# Читается ПРЯМО ИЗ КОНТРОЛЛЕРА ВЫДЕЛЕНИЯ, а не дублируется полем в HUD:
	# второй источник правды о текущем режиме разошёлся бы с первым на первом
	# же нажатии клавиши
	if _formation_label != null and is_instance_valid(_formation_label):
		var sm = GameManager.main.selection_manager if GameManager.main != null else null
		if sm != null:
			var deep: bool = int(sm.formation_mode) == int(sm.FORM_DEEP)
			var txt: String = "строй [2] блоки сеткой" if deep else "строй [1] широкий"
			if int(sm.formation_front) != 0:
				txt += " · авангард [3]"
			if _formation_label.text != txt:
				_formation_label.text = txt
				# Коробочка подсвечена: запомненный НЕ-дефолтный режим обязан
				# бросаться в глаза, иначе он и читается как самоволка игры
				_formation_label.add_theme_color_override("font_color",
					Color(1.0, 0.72, 0.25) if deep else Color(0.95, 0.85, 0.55))
	if _pause_btn:
		_pause_btn.text = "▶" if get_tree().paused else "⏸"

func _build_bottom_panel() -> void:
	_bottom_panel = PanelContainer.new()
	# Панель — АККУРАТНЫЙ БЛОК в левом нижнем углу, а не полоса на весь экран:
	# фон раньше растягивался на всю ширину (anchor_right=1) даже когда
	# содержимое (SIZE_SHRINK_BEGIN у всех колонок) жалось к левому краю —
	# отсюда и жалоба на «длинную панель». Теперь ширина = ширине содержимого
	_bottom_panel.anchor_left   = 0.0
	_bottom_panel.anchor_top    = 1.0
	_bottom_panel.anchor_right  = 0.0
	_bottom_panel.anchor_bottom = 1.0
	_bottom_panel.offset_left   = PANEL_LEFT
	_bottom_panel.offset_top    = float(PANEL_TOP)
	_bottom_panel.offset_bottom = -float(PANEL_BOTTOM_GAP)
	_bottom_panel.custom_minimum_size = Vector2(0, PANEL_H)
	# Панель растёт ВВЕРХ от нижней кромки: высота теперь зависит от содержимого
	# (см. _sync_panel_height), а прибита она к низу экрана
	_bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.09, 0.94)
	style.border_width_top = PANEL_BORDER_W; style.border_color = Color(0.30, 0.25, 0.15)
	style.border_width_left = PANEL_BORDER_W; style.border_width_right = PANEL_BORDER_W
	_corners(style, 6)
	# Воздух от рамки до содержимого — иначе портрет прижат к самому краю
	style.content_margin_left  = PANEL_PAD_X
	style.content_margin_right = PANEL_PAD_X
	style.content_margin_top    = PANEL_PAD_Y
	style.content_margin_bottom = PANEL_PAD_Y
	_bottom_panel.add_theme_stylebox_override("panel", style)
	add_child(_bottom_panel)
	_skin_bottom_panel()

	# ── НАЗВАНИЕ ОТРЯДА — ОТДЕЛЬНОЙ СТРОКОЙ ВО ВСЮ ШИРИНУ ПАНЕЛИ ────────────
	# Заказ владельца по скриншоту: «Отряд опытных копейщиков» должен стоять
	# ОДНОЙ строкой от ЛЕВОГО КРАЯ панели. Раньше подпись жила внутри колонки
	# info_vbox — то есть ПОСЛЕ портрета, с отступом в его ширину, и в колонку
	# 132 px длинное звание не влезало: перенос по словам рвал его на две
	# строки («Отряд опытных / копейщиков»).
	#
	# Ширина колонки тут ни при чём — лечится МЕСТОМ подписи. Панель стала
	# двухэтажной: строка названия сверху во всю ширину, а прежний ряд
	# (портрет, колонка, очередь, кнопки) — под ней. Узел подписи остался тем
	# же (info_label): по нему её ищут стенды и все ветки show_selection
	var vroot := VBoxContainer.new()
	vroot.name = "PanelRoot"
	vroot.add_theme_constant_override("separation", 2)
	_bottom_panel.add_child(vroot)

	info_label = Label.new(); info_label.text = "Ничего не выбрано"
	info_label.add_theme_color_override("font_color", Color(0.90, 0.88, 0.80))
	info_label.add_theme_font_size_override("font_size", 11)
	# ОДНА строка: высоту меряем по шрифту (см. _fix_label), а ширину НЕ
	# закрепляем — 0 в минимуме плюс EXPAND_FILL означает «занять ровно ту
	# ширину, которую панель получила от остального содержимого». Иначе
	# подпись сама раздувала бы панель под длину звания
	_fix_label(info_label, 0.0, 1)
	# ПЕРЕНОСА НЕТ ВОВСЕ: строка одна, лишнее срезается многоточием (это уже
	# задано в _fix_label). С включённым переносом Label честно ушёл бы на
	# вторую строку — ровно то, на что жаловался владелец
	info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vroot.add_child(info_label)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", PANEL_HBOX_SEP)
	# РЯД ЗАБИРАЕТ ВСЮ ВЫСОТУ, ОСТАВШУЮСЯ ОТ СТРОКИ НАЗВАНИЯ. Без этого VBox
	# выдаёт ему ровно минимум, ряд прижимается к верхней кромке, и всё, что
	# внутри него центровано или прижато к низу (портрет Замка, кнопки найма),
	# считает «низ» по себе, а не по панели
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vroot.add_child(hbox)

	# Portrait — БЕЗ РАМКИ: чистая иконка того, что выбрано, плюс бейджи
	# количества/ветеранства поверх (см. _update_portrait_badges)
	var pw := PanelContainer.new()
	var ps := StyleBoxFlat.new(); ps.bg_color = Color(0.08, 0.08, 0.12)
	# СКРУГЛЕНИЕ 5 px И РАМКА 1 px — РОВНО КАК У ИКОНОК ЮНИТОВ (заказ владельца
	# про иконку Замка). Числа не выдуманы здесь: это тот же _corners(…, 5) +
	# _borders(…, 1) со светлым кантиком, которым _cmd рисует кнопки найма и
	# приказов, поэтому портрет и иконки читаются как один набор
	_corners(ps, 5)
	_borders(ps, 1)
	ps.border_color = Color(0.30, 0.30, 0.38)
	pw.add_theme_stylebox_override("panel", ps)
	pw.custom_minimum_size = Vector2(PORTRAIT_W, PORTRAIT_W)
	pw.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# SHRINK_CENTER по вертикали: иначе HBox растягивает портрет на всю высоту
	# строки (замер дал 54×70 вместо 54×54), и квадратная иконка юнита начинает
	# плавать в вытянутой рамке, а бейдж количества уезжает от её нижнего края
	pw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(pw)
	_portrait_wrap = pw
	# Наведение на портрет открывает таблицу статов (ТЗ 18.09.2026, п. 6)
	pw.mouse_filter = Control.MOUSE_FILTER_PASS
	pw.mouse_entered.connect(func(): _set_stat_hover_portrait(true))
	pw.mouse_exited.connect(func(): _set_stat_hover_portrait(false))
	portrait = ColorRect.new(); portrait.color = Color(0.10, 0.11, 0.15)
	# ColorRect по умолчанию ГЛОТАЕТ мышь (MOUSE_FILTER_STOP): над подложкой
	# портрета mouse_entered рамки не приходил, и таблица статов открывалась
	# лишь над бейджами (ТЗ-B 19.09.2026, п. 3: «по ВСЕЙ области иконки»)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pw.add_child(portrait)

	_portrait_icon = TextureRect.new()
	_portrait_icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pw.add_child(_portrait_icon)

	_portrait_count_lbl = Label.new()
	_portrait_count_lbl.text = ""
	_portrait_count_lbl.visible = false
	_portrait_count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ШРИФТ УМЕНЬШЕН (15→12) И БЕЙДЖ СЖАТ (см. offsets ниже): при 15px и рамке
	# 21×21 цифра занимала больше половины ширины портрета и закрывала лицо
	# юнита — та самая жалоба "цифра 2 закрывает портрет". Тёмная обводка
	# (outline) держит читаемость и без сплошной плашки под цифрой
	# 12 → 10: на плашке отряда в бейдж пишется ЧИСЛЕННОСТЬ (двузначная — «30»),
	# и двенадцатым кеглем она закрывала шлем целиком. Обводка (outline ниже)
	# держит читаемость и на десятом
	_portrait_count_lbl.add_theme_font_size_override("font_size", 10)
	_portrait_count_lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.75))
	_portrait_count_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_portrait_count_lbl.add_theme_constant_override("outline_size", 4)
	_portrait_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_portrait_count_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	# БЕЙДЖ ПРИБИТ К НИЖНЕМУ ПРАВОМУ УГЛУ — ЧЕРЕЗ ПРОСЛОЙКУ.
	# Портрет лежит в PanelContainer, а тот РАСТЯГИВАЕТ каждого своего ребёнка
	# на весь свой прямоугольник и якоря/офсеты ребёнка просто игнорирует: и
	# цифра, и значок ранга занимали всю площадь портрета, и «угол» получался только
	# за счёт выравнивания текста, из-за чего цифра на глаз висела у правого
	# края посередине. Простой Control раскладку детям не навязывает — внутри
	# него якоря снова работают
	var badge_layer := Control.new()
	badge_layer.name = "PortraitBadges"
	badge_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pw.add_child(badge_layer)

	# КОРОБКА БЕЙДЖА СЖАТА ДО ~15×15 (была ~21×21) — строго в уголок, а не на
	# половину портрета. Якоря все =1 (правый/нижний), офсеты фиксированы в
	# пикселях, поэтому размер коробки не зависит от размера портрета: она
	# остаётся маленькой и на обычном (30px), и на укрупнённом (Артель, 45px)
	_portrait_count_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	# Коробка сжата под меньший кегль: с прежними −15/−14 бейдж занимал угол,
	# рассчитанный на 12 px, и вокруг цифры оставался лишний тёмный ореол
	_portrait_count_lbl.offset_left   = -13
	_portrait_count_lbl.offset_top    = -12
	_portrait_count_lbl.offset_right  = -1
	_portrait_count_lbl.offset_bottom = -1
	badge_layer.add_child(_portrait_count_lbl)

	_portrait_rank_lbl = Label.new()
	_portrait_rank_lbl.text = ""
	_portrait_rank_lbl.visible = false
	_portrait_rank_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_rank_lbl.add_theme_font_size_override("font_size", 11)
	_portrait_rank_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
	# Кант берётся из конфига ветеранства: обводка значка одна на всю игру,
	# и держать её двумя разными числами в двух файлах незачем
	_portrait_rank_lbl.add_theme_color_override("font_outline_color",
		_UCfg.VET_BADGE_OUTLINE)
	_portrait_rank_lbl.add_theme_constant_override("outline_size", 4)
	# ── ЛЫЧКА В ВЕРХНЕМ ЛЕВОМ УГЛУ, А НЕ ПОСЕРЕДИНЕ ЛИЦА ───────────────────
	# Заказ владельца по скриншоту: «шеврон ранга отображается по центру лица
	# юнита; перенести строго в верхний левый угол, единым правилом для всех
	# иконок, карточек и плашек».
	#
	# Правило это в проекте УЖЕ ЕСТЬ и уже соблюдается — карточка отряда в
	# мульти-выделении ставит значок ровно туда (см. «ЗНАЧОК ВЕТЕРАНСТВА ОТРЯДА»
	# ниже, с тем же отступом и той же выключкой). Из общего ряда выбивался
	# только портрет, и выбивался он одной строкой: выключка по центру при
	# растянутой на всю ширину прослойке. Числа отступов взяты оттуда же, чтобы
	# значок стоял одинаково в обоих местах
	_portrait_rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_portrait_rank_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	# Значок — в ТОЙ ЖЕ прослойке, поверху (см. комментарий у бейджа количества)
	_portrait_rank_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_portrait_rank_lbl.offset_left   = 2
	_portrait_rank_lbl.offset_top    = 1
	_portrait_rank_lbl.offset_bottom = 18
	badge_layer.add_child(_portrait_rank_lbl)

	# Info: ширина колонки закреплена, подписи внутри переносятся по словам
	var info_vbox := VBoxContainer.new()
	info_vbox.name = "InfoColumn"
	info_vbox.custom_minimum_size  = Vector2(INFO_W, COL_H)
	info_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(info_vbox)
	_info_col = info_vbox

	# ── РЯД ФЛАЖКОВ РАНГА: «БЫЛО → СТАЛО» ──────────────────────────────────
	# Живёт ровно там, где стояла подпись, и подменяет её на время выбора
	# награды (см. _show_vet_rank_row). Заводится ЗДЕСЬ, один раз: пересоздавать
	# контейнер на каждое открытие панели незачем, наполнение и так сменное
	_vet_rank_row = HBoxContainer.new()
	_vet_rank_row.name = "VetRankRow"
	_vet_rank_row.add_theme_constant_override("separation", 6)
	# ПО ЦЕНТРУ СВОЕЙ КОЛОНКИ (заказ владельца). Прижатый к левому краю флажок
	# висел вплотную к портрету и читался как его продолжение, а не как знак
	# ранга отряда
	_vet_rank_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_vet_rank_row.custom_minimum_size = Vector2(0.0, VET_FLAG_H)
	_vet_rank_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vet_rank_row.visible = false
	info_vbox.add_child(_vet_rank_row)

	progress_label = Label.new(); progress_label.text = ""
	progress_label.add_theme_color_override("font_color", Color(0.65, 0.80, 1.0))
	progress_label.add_theme_font_size_override("font_size", 9)
	_fix_label(progress_label, INFO_W, 1)
	# ПУСТАЯ СТРОКА ПРОИЗВОДСТВА ПРЯЧЕТСЯ ЦЕЛИКОМ. BoxContainer пропускает
	# невидимых детей мимо раскладки, а видимый Label с пустым текстом всё равно
	# держал бы свою минимальную высоту — на панели в 40px это шестая часть её
	# высоты, зарезервированная под ничто (см. _set_progress_text)
	progress_label.visible = false
	info_vbox.add_child(progress_label)

	# ПОДРОБНОСТИ ЗДАНИЯ (ТЗ 12.10.2026): строка названия одна (многоточие), и
	# многострочное описание загона, рудника, дома срезалось до первой строки.
	# Всё, что после первой строки info_label, переезжает сюда (_split_info_detail)
	_detail_label = Label.new()
	_detail_label.name = "DetailLabel"
	_detail_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.76))
	_detail_label.add_theme_font_size_override("font_size", 10)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_label.visible = false
	info_vbox.add_child(_detail_label)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(INFO_W - 8, 5)
	progress_bar.show_percentage = false; progress_bar.visible = false
	var pb_bg := StyleBoxFlat.new(); pb_bg.bg_color = Color(0.10, 0.10, 0.20); _corners(pb_bg, 3)
	var pb_fill := StyleBoxFlat.new(); pb_fill.bg_color = Color(0.28, 0.52, 1.0); _corners(pb_fill, 3)
	progress_bar.add_theme_stylebox_override("background", pb_bg)
	progress_bar.add_theme_stylebox_override("fill", pb_fill)
	info_vbox.add_child(progress_bar)

	# ── ШКАЛА ОПЫТА ОТРЯДА ──────────────────────────────────────────────────
	# Заказ владельца: вместо второй строки «Отряд мечников — 30 бойцов», которая
	# слово в слово повторяла заголовок окна статов прямо над ней, — прогресс до
	# следующего ранга. Дублировался не текст, а ЭКРАННОЕ МЕСТО: одна и та же
	# фраза стояла двумя строками друг под другом.
	#
	# Отдельная шкала, а не переиспользованный progress_bar: тот показывает
	# производство (найм, исследование) и живёт своей жизнью — у выделенного
	# барака с очередью нашлись бы обе, и они дрались бы за одну полоску
	_xp_bar = ProgressBar.new()
	_xp_bar.name = "SquadXP"
	_xp_bar.custom_minimum_size = Vector2(INFO_W - 8, XP_BAR_H)
	_xp_bar.show_percentage = false
	_xp_bar.visible = false
	_xp_bar.max_value = 1.0
	var xp_bg := StyleBoxFlat.new(); xp_bg.bg_color = Color(0.10, 0.09, 0.06); _corners(xp_bg, 3)
	var xp_fl := StyleBoxFlat.new(); xp_fl.bg_color = XP_BAR_COLOR; _corners(xp_fl, 3)
	_xp_bar.add_theme_stylebox_override("background", xp_bg)
	_xp_bar.add_theme_stylebox_override("fill", xp_fl)
	info_vbox.add_child(_xp_bar)

	_xp_label = Label.new()
	_xp_label.text = ""
	_xp_label.visible = false
	_xp_label.add_theme_font_size_override("font_size", 9)
	_xp_label.add_theme_color_override("font_color", Color(0.86, 0.78, 0.52))
	_fix_label(_xp_label, INFO_W - 20.0, 1)
	# ФЛАЖОК РАНГА ВМЕСТО СЛОВ (ТЗ 24.10.2026, блок 7): «Ранг 3 → 4» читалось
	# строкой цифр; теперь — тот же вымпел, что над знаменосцем, и опыт рядом
	_xp_row = HBoxContainer.new()
	_xp_row.name = "XpRow"
	_xp_row.add_theme_constant_override("separation", 4)
	_xp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_row.visible = false
	_xp_row.add_child(_xp_label)
	_xp_label.visible = true
	info_vbox.add_child(_xp_row)

	# ОЧЕРЕДЬ НАЙМА: сетка постоянного размера (5×2 = QUEUE_ORDER_MAX ячеек),
	# одна ячейка на каждый заказ, а не на тип. Пока очередь пуста, сетка
	# просто пустая — соседи от этого не двигаются
	# ЗОНА ОЧЕРЕДИ — контейнер ПОСТОЯННОГО размера вокруг сетки заказов.
	# Смысл его не декоративный: он задаёт ЖЁСТКИЙ предел, внутри которого
	# обязаны уместиться иконки, сколько бы заказов ни стояло. Сетка внутри не
	# растягивает контейнер — вместо этого уменьшаются сами ячейки
	# (см. _queue_cell_side), поэтому панель не «разъезжается» от заказов.
	#
	# ЖЁЛТАЯ РАМКА УБРАНА (заказ владельца: она была ориентиром на макете).
	# Контейнер остаётся, но не рисует НИЧЕГО — ни рамки, ни фона: убрать сам
	# PanelContainer было нельзя, вместе с ним ушёл бы и фиксированный габарит
	_queue_frame = PanelContainer.new()
	_queue_frame.name = "QueueFrame"
	var qf := StyleBoxFlat.new()
	qf.bg_color = Color(0, 0, 0, 0)
	_borders(qf, 0)
	qf.draw_center = false
	qf.content_margin_left = QUEUE_FRAME_PAD; qf.content_margin_right = QUEUE_FRAME_PAD
	qf.content_margin_top  = QUEUE_FRAME_PAD; qf.content_margin_bottom = QUEUE_FRAME_PAD
	_queue_frame.add_theme_stylebox_override("panel", qf)
	_queue_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_queue_frame.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_queue_frame)

	# CenterContainer между рамкой и сеткой: PanelContainer растягивает своего
	# ребёнка на всю себя, и сетка прижимала бы ячейки к верхнему левому углу —
	# при уменьшенных ячейках (8 заказов → 12 px) под ними зияла бы пустая
	# половина бокса. CenterContainer держит ряд по центру при любом размере
	var qcenter := CenterContainer.new()
	qcenter.name = "QueueCenter"
	_queue_frame.add_child(qcenter)

	_queue_box = GridContainer.new()
	_queue_box.columns = QUEUE_ORDER_COLS
	_queue_box.add_theme_constant_override("h_separation", QUEUE_CELL_GAP)
	_queue_box.add_theme_constant_override("v_separation", QUEUE_CELL_GAP)
	qcenter.add_child(_queue_box)

	# ── ПОЛОСА ОТДЕЛЬНЫХ ОТРЯДОВ ─────────────────────────────────────────────
	# Разворачивается по клику на сводную иконку в баннере (см. _expand_type).
	# Пока ничего не развёрнуто — пустой контейнер нулевой ширины, соседние
	# колонки от него не двигаются.
	# СТОИТ ДО РАСПОРКИ: всё, что левее распорки, прижато к левому краю, а
	# правее — к правому. Полоса отрядов принадлежит левой группе; после
	# распорки она отодвигала бы кнопки найма от края на свою ширину
	# СЕТКА, А НЕ РЯД: до SQUAD_ROW_MAX карточек в ряд, зазор 3 px (ТЗ 10.10.2026)
	var strip := GridContainer.new()
	strip.columns = 1
	strip.add_theme_constant_override("h_separation", 3)
	strip.add_theme_constant_override("v_separation", 3)
	_squad_strip = strip
	_squad_strip.name = "SquadStrip"
	_squad_strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_squad_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_squad_strip)

	# ── РАСПОРКА ПЕРЕД КНОПКАМИ НАЙМА ────────────────────────────────────────
	# Пустой растягивающийся Control: он съедает всю ширину, которую панель имеет
	# СВЕРХ своего содержимого, и тем самым прижимает кнопки найма к правому краю
	# (заказ владельца). У панелей, чья ширина считается ПО содержимому (все
	# кроме Замка), лишней ширины нет вовсе — распорка получает свой минимум,
	# то есть ноль, и раскладка остаётся прежней до пикселя
	_btn_spacer = Control.new()
	_btn_spacer.name = "ButtonSpacer"
	_btn_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_btn_spacer)

	# ── КНОПКИ ЦЕНТРИРУЮТСЯ В СВОЁМ МЕСТЕ (заказ владельца) ─────────────────
	# Габарит держит ОБЁРТКА, а не сама сетка. Причина ровно та же, что у рамки
	# очереди заказов: место под кнопки зарезервировано на полный ряд BTN_COLS
	# (это защита от дрожания панели, её трогать нельзя), а кнопок в ряду обычно
	# три-четыре — и GridContainer, получив ширину на пять, честно кладёт их от
	# ЛЕВОГО края, оставляя пустой хвост справа. CenterContainer ставит сетку
	# ровно в середину зарезервированного места, ничего не меняя в её раскладке
	var btn_slot := CenterContainer.new()
	btn_slot.name = "ButtonSlot"
	btn_slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# ПО ВЕРТИКАЛЬНОМУ ЦЕНТРУ ПАНЕЛИ, А НЕ ПОД ЕЁ ВЕРХНЕЙ КРОМКОЙ.
	# По умолчанию контейнер растягивался на всю высоту строки, а GridContainer
	# кладёт детей от верхнего края — из-за этого кнопки и выглядели
	# «задранными вверх» (жалоба владельца)
	btn_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_slot.custom_minimum_size = Vector2(
		BTN_COLS * BTN_SIZE + (BTN_COLS - 1) * BTN_GAP, COL_H)
	hbox.add_child(btn_slot)
	_btn_slot = btn_slot

	button_container = GridContainer.new()
	button_container.columns = BTN_COLS
	# У САМОЙ СЕТКИ МИНИМУМА НЕТ: он на обёртке. Минимум на сетке заставил бы
	# CenterContainer растянуть её на всё место, и центрировать стало бы нечего
	button_container.custom_minimum_size = Vector2.ZERO
	button_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button_container.add_theme_constant_override("h_separation", BTN_GAP)
	button_container.add_theme_constant_override("v_separation", BTN_GAP)
	btn_slot.add_child(button_container)

	# ── КОМАНДЫ ОТРЯДУ [S] [C] [A] (ТЗ 23.09.2026) ─────────────────────────
	# Своя колонка в том же ряду, а НЕ отдельная плашка над панелью. Плашка
	# гарнизона так уже висела и «дёргалась»: она пересобиралась своим тактом,
	# а панель своим (см. ТЗ 20.09.2026, п. 6). Колонка живёт и обновляется
	# вместе с панелью, и разъехаться ей не с чем
	_squad_cmd_bar = HBoxContainer.new()
	_squad_cmd_bar.name = "SquadCmdBar"
	_squad_cmd_bar.add_theme_constant_override("separation", SCMD_GAP)
	_squad_cmd_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_squad_cmd_bar.visible = false
	hbox.add_child(_squad_cmd_bar)

	# ОТСТУП ОТ ПРАВОГО КРАЯ. Фиксированная распорка ПОСЛЕ кнопок: у Замка это
	# ровно CASTLE_BTN_RIGHT_PAD, у остальных выделений — ноль, чтобы не
	# раздувать панель, считающуюся по содержимому (см. _sync_panel_grid_widths)
	_btn_right_pad = Control.new()
	_btn_right_pad.name = "ButtonRightPad"
	_btn_right_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_btn_right_pad)

	# КОЛОНКИ РЕЗЕРВИРУЮТ МЕСТО ТОЛЬКО ПОКА В НИХ ЕСТЬ ЧТО ПОКАЗАТЬ.
	# custom_minimum_size у _queue_box/button_container фиксирован НАРОЧНО (см.
	# комментарий выше "жёсткая сетка") — это защита от дрожания панели, пока
	# в очереди/кнопках идёт активная возня (заказ добавили — заказ выполнили).
	# Но у выделений, которым очередь или кнопки вообще не нужны (Копейщик,
	# вражеский юнит, Кузница без исследований), эти колонки раньше всё равно
	# держали свою максимальную ширину пустыми — и панель превращалась в ту
	# самую "длинную пустую чёрную плашку", на которую жаловались. Синк ниже
	# схлопывает КАЖДУЮ колонку в 0, если в ней прямо сейчас нет ни одного
	# дочернего узла, и возвращает её к фиксированной ширине, как только
	# появляется первый — сама защита от дрожания при этом не трогается
	_sync_panel_grid_widths()

## Строка производства/исследования. Пустая — прячется целиком, иначе держала бы
## свою минимальную высоту в панели, где каждый пиксель на счету
func _set_progress_text(t: String) -> void:
	if progress_label == null or not is_instance_valid(progress_label):
		return
	progress_label.text    = t
	progress_label.visible = t != ""

# ─────────────────────────────────────────────────────────────────────────────
# ВЫСОТА НИЖНЕЙ ПАНЕЛИ — ПО СОДЕРЖИМОМУ, А НЕ КОНСТАНТОЙ
#
# После уменьшения панели вдвое (PANEL_H = 40) фиксированная высота перестала
# годиться: восемь слотов кузницы в сетке из BTN_COLS колонок дают ВТОРОЙ РЯД
# кнопок, карточки отрядов выше кнопок на высоту шкалы, а строка производства
# добавляет свою. Раньше это решалось запасом (панель всегда была высотой в
# максимальный случай) — то есть панель всегда была большой ради редких случаев.
#
# Теперь высоту спрашиваем у самой раскладки: get_combined_minimum_size() уже
# просуммировал минимумы всех видимых детей. Своё custom_minimum_size при этом
# надо ОБНУЛИТЬ — иначе панель мерила бы собственную прошлую высоту и никогда
# не уменьшалась обратно.
#
# Зовётся ТОЛЬКО при пересборке содержимого (show_selection, разворот группы,
# появление/исчезновение строки производства), а не каждый кадр: панель, меняющая
# высоту 60 раз в секунду, — это и есть та самая «дрожащая панель»
# ─────────────────────────────────────────────────────────────────────────────
func _sync_panel_height() -> void:
	if _bottom_panel == null or not is_instance_valid(_bottom_panel):
		return
	# ── ПУСТАЯ СТРОКА НАЗВАНИЯ ПРЯЧЕТСЯ ЦЕЛИКОМ ────────────────────────────
	# Тот же приём и та же причина, что у строки производства (см.
	# _set_progress_text): BoxContainer пропускает невидимых детей мимо
	# раскладки, а видимый Label с пустым текстом всё равно держит свою
	# минимальную высоту. У панели Замка подпись уезжает в шапку НАД панелью
	# (_update_castle_caption), а info_label обнуляется — и пустая строка
	# добавляла панели лишние двадцать пикселей и сбивала центровку кнопок
	if info_label != null and is_instance_valid(info_label):
		info_label.visible = info_label.text != ""
	_bottom_panel.custom_minimum_size = Vector2(0, 0)
	var content: Vector2 = _bottom_panel.get_combined_minimum_size()
	var need: float = maxf(content.y, float(PANEL_H))
	var need_w: float = content.x
	# ЗАМОК: РАЗМЕР ЖЁСТКИЙ, СОДЕРЖИМОЕ НА НЕГО НЕ ВЛИЯЕТ.
	# maxf с содержимым оставлен намеренно как предохранитель: если однажды
	# внутрь положат больше, чем влезает, панель не обрежет содержимое, а
	# вырастет — но от ОЧЕРЕДИ она не растёт уже по построению, потому что
	# жёлтый бокс имеет постоянный габарит (см. _sync_panel_grid_widths)
	if _castle_boost:
		# ПОЛОСА ПОД ПОДПИСЬ — ЧАСТЬ ВЫСОТЫ, А НЕ СЛУЧАЙНЫЙ ЗАПАС.
		# Портрет прижат к нижней кромке (SIZE_SHRINK_END), подпись «Замок N/N HP»
		# стоит над ним; чтобы они не наложились ни при каком изменении иконки,
		# высота панели не может быть меньше «иконка + полоса подписи»
		var castle_h: float = maxf(CASTLE_PANEL_H,
			CASTLE_PORTRAIT_W + CASTLE_CAPTION_BAND + CASTLE_CAPTION_INSET)
		castle_h = maxf(castle_h, content.y)
		# Шапка в две строки (башня: обзор и гарнизон, ТЗ 20.10.2026) — панель
		# выше на строку, чтобы вторая строка не легла на кнопки
		if _castle_caption != null and is_instance_valid(_castle_caption) \
				and _castle_caption.visible and "\n" in _castle_caption.text:
			castle_h += CASTLE_CAPTION_BAND - 2.0
		# ШИРИНА ПО СОДЕРЖИМОМУ (ТЗ 14.10.2026, п. 2: «убрать лишнее пустое
		# место справа, отступы слева и справа одинаковые»). Прежние 430 px
		# держали у стрелковой 300 px пустоты между иконкой и одной кнопкой.
		# Дрожать панели не от чего: очередь у производственных зданий держит
		# место всегда, число кнопок у здания постоянно. Нижний предел — по
		# подписи «Название N/N HP», чтобы та не вылезала за кромку
		var cap_w: float = 0.0
		if _castle_caption != null and is_instance_valid(_castle_caption) and _castle_caption.visible:
			cap_w = _castle_caption.get_combined_minimum_size().x \
				+ 2.0 * float(PANEL_BORDER_W + PANEL_PAD_X) + 8.0
		_panel_w = maxf(content.x, cap_w)
		_bottom_panel.custom_minimum_size = Vector2(_panel_w, castle_h)
		_center_bottom_panel(_panel_w)
		_apply_left_column_width()
		var ct: int = -int(round(castle_h)) - PANEL_BOTTOM_GAP
		var old_ct: int = PANEL_TOP
		PANEL_TOP = ct
		_bottom_panel.offset_top    = float(PANEL_TOP)
		_bottom_panel.offset_bottom = -float(PANEL_BOTTOM_GAP)
		_position_group_bar()
		var dc: float = float(PANEL_TOP - old_ct)
		if dc != 0.0:
			for n in [_garrison_strip, _stat_panel, _stat_card, _bonus_tip]:
				var cc := n as Control
				if cc != null and is_instance_valid(cc):
					cc.offset_top    += dc
					cc.offset_bottom += dc
		return
	# АРТЕЛЬ: панель просили шире на +20% и ВЫШЕ В 2 РАЗА — сверх того, что уже
	# дают увеличенные иконки/портрет (WORKER_ICON_BOOST). Лишняя ширина/высота —
	# это воздух вокруг содержимого (HBox не растягивается на неё сам), а не
	# искажение раскладки: то самое "просторно", которое просил владелец
	if _worker_boost:
		need_w *= WORKER_PANEL_W_BOOST
		need   *= WORKER_PANEL_H_BOOST
	# ОБЩАЯ ШИРИНА ЛЕВОГО СТОЛБЦА (см. _panel_w): пока карточка статов на
	# экране, обе панели тянутся до одного числа. Без карточки навязывать
	# нижней панели ширину в 320 px незачем — «Ничего не выбрано» осталось бы
	# плашкой в треть экрана
	if _stat_panel != null and is_instance_valid(_stat_panel):
		need_w = maxf(need_w, float(STAT_PANEL_W))
	# ── РАЗВЁРНУТЫЙ РОД — ПЛАШКА ФИКСИРОВАННОЙ ШИРИНЫ (ТЗ 11.10.2026) ───────
	# Одна ширина на 1, 3 и 8 отрядов любого рода: сетка карточек держит место
	# под полный ряд (SQUAD_STRIP_W), а запас DETAIL_PANEL_W вмещает до двух
	# кнопок приёмов. Больше двух приёмов — плашка честно растёт (предохранитель)
	# Фиксированная ширина развёрнутого рода (DETAIL_PANEL_W) снята ТЗ
	# 12.10.2026: плашка обтягивает сетку карточек и ряд A/C/S/F1
	_panel_w = need_w
	_apply_left_column_width()
	_bottom_panel.custom_minimum_size = Vector2(need_w, need)
	_center_bottom_panel(need_w)
	var old_top: int = PANEL_TOP
	PANEL_TOP = -int(round(need)) - PANEL_BOTTOM_GAP
	_bottom_panel.offset_top    = float(PANEL_TOP)
	_bottom_panel.offset_bottom = -float(PANEL_BOTTOM_GAP)
	_position_group_bar()
	# ВСЁ, ЧТО ВИСИТ НАД ПАНЕЛЬЮ, ЕДЕТ ВМЕСТЕ С НЕЙ.
	# Полоса гарнизона, панель статов, карточка и подсказка бонуса привязаны к
	# PANEL_TOP, но строятся РАНЬШЕ этого пересчёта (внутри _refresh_panel), то
	# есть с прошлой высотой. Сдвигаем их на разницу, а не пересобираем: высоты
	# у каждой свои, а дельта одна на всех
	var d: float = float(PANEL_TOP - old_top)
	if d != 0.0:
		for n in [_garrison_strip, _stat_panel, _stat_card, _bonus_tip]:
			var c := n as Control
			if c != null and is_instance_valid(c):
				c.offset_top    += d
				c.offset_bottom += d

## ── ПАНЕЛЬ ВНИЗУ ПО ЦЕНТРУ (ТЗ 12.10.2026) ──────────────────────────────
## Левый край = (ширина экрана − ширина панели) / 2. Всё, что висит над
## панелью и крепится к её левой кромке, едет на ту же разницу по X
func _center_bottom_panel(w: float) -> void:
	if not PANEL_CENTERED or _bottom_panel == null or not is_instance_valid(_bottom_panel):
		return
	var vw: float = get_viewport().get_visible_rect().size.x
	var nl: float = maxf(PANEL_LEFT_MIN, round((vw - w) * 0.5))
	if PANEL_DOCK_MINIMAP:
		nl = round(_MinimapScript.dock_right_x())
	var dx: float = nl - PANEL_LEFT
	PANEL_LEFT = nl
	_bottom_panel.offset_left = nl
	_bottom_panel.offset_right = nl + w
	if dx != 0.0:
		for n in [_garrison_strip, _stat_panel, _stat_card, _bonus_tip, _castle_caption]:
			var c := n as Control
			if c != null and is_instance_valid(c) and c.anchor_left == 0.0:
				c.offset_left  += dx
				c.offset_right += dx

## ── ПОРТРЕТ РАБОЧЕГО КРУПНЕЕ КНОПОК ПОСТРОЕК (ТЗ 11.10.2026, ч. 1 п. 5) ───
## Иконка рабочего — главная на этой панели: она крупнее кнопок каталога на
## WORKER_PORTRAIT_K и отделена от них обычным зазором ряда (PANEL_HBOX_SEP).
## Возврат к обычному размеру — в _refresh_panel
const WORKER_PORTRAIT_K := 1.18
func _worker_portrait() -> void:
	if _portrait_wrap == null or not is_instance_valid(_portrait_wrap):
		return
	var side: float = round(BTN_SIZE * WORKER_ICON_BOOST * WORKER_PORTRAIT_K)
	_portrait_wrap.custom_minimum_size = Vector2(side, side)

## Высота панели прямо сейчас (для стендов и позиционирования полосы групп)
func panel_height() -> float:
	if _bottom_panel == null or not is_instance_valid(_bottom_panel):
		return 0.0
	return maxf(_bottom_panel.custom_minimum_size.y, float(PANEL_H))

## Подпись фиксированной ширины: перенос по словам + жёсткий предел строк.
## Ключевое здесь — autowrap: с ним минимальная ширина Label перестаёт
## зависеть от длины текста, и колонка больше не расползается.
func _fix_label(lbl: Label, w: float, lines: int = 1) -> void:
	# clip_text фиксирует ШИРИНУ (текст не растягивает колонку), но заодно
	# обнуляет и минимальную ВЫСОТУ: без явной высоты Label схлопывался в
	# 1 пиксель, и подпись в нижней панели («Ничего не выбрано», «Рабочий
	# 100/100 HP», строка производства) просто не рисовалась — на её месте
	# зияла пустая тёмная полоса шириной в колонку. Высоту считаем из
	# фактического размера шрифта, а не константой: у разных подписей он свой
	var fs: float = float(lbl.get_theme_font_size("font_size"))
	if fs <= 0.0:
		fs = 14.0
	# ВЫСОТУ СТРОКИ СПРАШИВАЕМ У ШРИФТА, а не считаем как fs+4.
	# Прикидка «кегль плюс четыре» занижает межстрочный интервал: при кегле 11
	# она давала 15 px на строку, а шрифту нужно ~16, и в двухстрочный Label
	# помещалась ОДНА строка — вторая молча срезалась многоточием («Артель:
	# 5 рабочих —...»). Симптом: текст в узле есть целиком, на экране обрезан
	var line_h: float = fs + 6.0
	var font: Font = lbl.get_theme_font("font")
	if font != null:
		line_h = maxf(font.get_height(int(fs)), line_h)
	lbl.custom_minimum_size    = Vector2(w, float(lines) * line_h + 2.0)
	lbl.autowrap_mode          = TextServer.AUTOWRAP_WORD_SMART
	lbl.max_lines_visible      = lines
	lbl.text_overrun_behavior  = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.clip_text              = true
	lbl.size_flags_horizontal  = Control.SIZE_SHRINK_BEGIN

# Деревянная подложка нижней панели из ассета BigBar_Base: боковые шапки
# фиксированы, средняя доска тянется на всю ширину экрана (NinePatchRect).
# Кладётся ПОД содержимое панели, поэтому кнопки и текст остаются кликабельными.
func _skin_bottom_panel() -> void:
	var tex := _UIAssets.big_bar_base()
	if tex == null or _bottom_panel == null:
		return
	var np := NinePatchRect.new()
	np.texture = tex
	var cap := _UIAssets.cap_width("BigBar_Base")
	np.patch_margin_left   = cap
	np.patch_margin_right  = cap
	np.patch_margin_top    = 6
	np.patch_margin_bottom = 6
	np.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.show_behind_parent = true
	_bottom_panel.add_child(np)
	_bottom_panel.move_child(np, 0)

# ─────────────────────────────────────────────────────────────────────────────
# SELECTION
# ─────────────────────────────────────────────────────────────────────────────

## ВХОД ПРИ СМЕНЕ ВЫДЕЛЕНИЯ. Запоминает состав, сворачивает разворот группы
## (карточки прежних отрядов к новому выделению отношения не имеют) и заново
## решает, какой уровень показывать
func show_selection(units: Array) -> void:
	if button_container == null:
		return
	_sel_units = units.duplicate()
	_sel_sid_set.clear()
	for sid0 in _selected_squad_ids():
		_sel_sid_set[int(sid0)] = true
	_counts_dirty = false
	# ВЫДЕЛЕНИЕ СВОИХ ЗАКРЫВАЕТ РАЗВЕДКУ. Панель одна на двоих, и держать на ней
	# чужой отряд, пока игрок уже командует своим, значит показывать не тот
	# объект, которым управляют — самая дорогая ошибка, какую может сделать HUD
	_recon_units.clear()
	# ЗВУК ЗАКРЫТИЯ ПАНЕЛИ ЗДАНИЯ (ТЗ 10.10.2026, блок 3): было выделено здание,
	# выделение опустело (клик мимо, Escape, отмена) — короткий щелчок. Смена
	# на другой объект щёлкает своим звуком выбора (qa_goblin J9)
	if _selected_node != null and is_instance_valid(_selected_node) \
			and _selected_node is Building and units.is_empty():
		AudioManager.play_ui("menu_close")
	_expanded_type = ""
	# Родительский набор живёт, только пока выделение остаётся ЕГО частью
	# (разворот рода, клик по карточке отряда); иначе — новое выделение
	if not _parent_sids.is_empty():
		var cur: Array = _selected_squad_ids()
		var cur_w: Array = _selected_workers()
		var keep_par: bool = not cur.is_empty() or not cur_w.is_empty()
		for sid in cur:
			if not _parent_sids.has(int(sid)):
				keep_par = false
				break
		for w in cur_w:
			if not _parent_workers.has(w):
				keep_par = false
				break
		if not keep_par:
			_parent_clear()
	_rebuild_overbar(not _parent_sids.is_empty())
	_refresh_panel()
	_sync_market_panel(units)
	_sync_goblin_forge_panel(units)

# ═════════════════════════════════════════════════════════════════════════════
# ОКНО РЫНКА (ТЗ 27.10.2026, второе письмо, п. 4)
# ═════════════════════════════════════════════════════════════════════════════
## Окно обмена живёт, пока выделен ОДИН свой рынок; стоит над нижней
## панелью у левого края (scripts/ui/MarketPanel.gd)
const _MarketPanelS := preload("res://scripts/ui/MarketPanel.gd")
var _market_panel: Control = null

func _sync_market_panel(units: Array) -> void:
	var mk: Node = null
	if units.size() == 1 and is_instance_valid(units[0]) and units[0] is Building 			and String((units[0] as Building).building_id) == "market" 			and int((units[0] as Building).faction) == Constants.FACTION_PLAYER 			and not (units[0] as Building).is_dead():
		mk = units[0]
	if mk == null:
		if _market_panel != null and is_instance_valid(_market_panel):
			remove_child(_market_panel)
			_market_panel.queue_free()
		_market_panel = null
		return
	if _market_panel == null or not is_instance_valid(_market_panel):
		_market_panel = _MarketPanelS.new()
		add_child(_market_panel)
	_market_panel.set("market", mk)
	_market_panel.call("_refresh")
	_place_market_panel.call_deferred()

## Выделен ровно один свой живой рынок
func _market_selected(units: Array) -> bool:
	return units.size() == 1 and is_instance_valid(units[0]) and units[0] is Building \
		and String((units[0] as Building).building_id) == "market" \
		and int((units[0] as Building).faction) == Constants.FACTION_PLAYER \
		and not (units[0] as Building).is_dead()

func _place_market_panel() -> void:
	if _market_panel == null or not is_instance_valid(_market_panel):
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var ms: Vector2 = _market_panel.get_combined_minimum_size()
	_market_panel.size = ms
	# Нижняя панель на время рынка скрыта — окно стоит на её месте, у низа
	var top: float = vs.y
	if _bottom_panel != null and is_instance_valid(_bottom_panel) and _bottom_panel.visible:
		top = _bottom_panel.get_global_rect().position.y
	var x: float = PANEL_LEFT
	if _bottom_panel != null and is_instance_valid(_bottom_panel):
		x = _bottom_panel.get_global_rect().position.x
	_market_panel.position = Vector2(x, maxf(8.0, top - ms.y - 8.0))

# ═════════════════════════════════════════════════════════════════════════════
# ОКНО КУЗНИЦЫ ГОБЛИНОВ (ТЗ 28.10.2026): живёт, пока выделена ОДНА своя кузница
# орды (игра за гоблинов; сейчас — если игрок владеет таким зданием); стенд и
# отладка открывают окно напрямую (goblin_forge_panel().open_for). Само окно —
# scripts/economy/goblin_forge/GoblinForgePanel.gd, стоит там же, где рынок
# ═════════════════════════════════════════════════════════════════════════════
const _GobForgePanelS := preload("res://scripts/economy/goblin_forge/GoblinForgePanel.gd")
var _gforge_panel: Control = null

func goblin_forge_panel() -> Control:
	if _gforge_panel == null or not is_instance_valid(_gforge_panel):
		_gforge_panel = _GobForgePanelS.new()
		add_child(_gforge_panel)
		_gforge_panel.visible = false
	return _gforge_panel

func _sync_goblin_forge_panel(units: Array) -> void:
	var fg: Node = null
	if units.size() == 1 and units[0] is Building \
			and String((units[0] as Building).building_id) == "goblin_forge" \
			and (units[0] as Building).faction == Constants.FACTION_PLAYER:
		fg = units[0]
	if fg == null:
		if _gforge_panel != null and is_instance_valid(_gforge_panel) and _gforge_panel.visible:
			_gforge_panel.call("close")
		return
	var p: Control = goblin_forge_panel()
	p.call("open_for", fg)
	_place_goblin_forge_panel.call_deferred()

func _place_goblin_forge_panel() -> void:
	if _gforge_panel == null or not is_instance_valid(_gforge_panel) or not _gforge_panel.visible:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var ms: Vector2 = _gforge_panel.get_combined_minimum_size()
	_gforge_panel.size = ms
	var top: float = vs.y - 200.0
	if _bottom_panel != null and is_instance_valid(_bottom_panel) and _bottom_panel.visible:
		top = _bottom_panel.get_global_rect().position.y
	var x: float = PANEL_LEFT
	if _bottom_panel != null and is_instance_valid(_bottom_panel):
		x = _bottom_panel.get_global_rect().position.x
	_gforge_panel.position = Vector2(x, maxf(8.0, top - ms.y - 8.0))

# ═════════════════════════════════════════════════════════════════════════════
# ПАНЕЛЬ РАЗВЕДКИ: ЧУЖОЙ ОТРЯД ПОД ЛУПОЙ
# ═════════════════════════════════════════════════════════════════════════════
# Клик по вражескому отряду открывает его карточку: чем он вооружён, что ему
# дала кузница, какой ранг он выслужил. Командных кнопок здесь нет ВООБЩЕ —
# ни стоек, ни «удерживать позицию», ни найма: чужим отрядом не командуют, и
# кнопка, которая ничего не делает, хуже её отсутствия.
#
# Чужой отряд НЕ ПОПАДАЕТ в selected_units (см. SelectionManager.recon_units) —
# он живёт в отдельном списке. Это не аккуратность, а безопасность: правый клик
# перебирает именно selected_units, и вражеский боец в этом списке получил бы
# приказ от игрока.
#
# Статы, разбор бонусов кузницы и ряд заслуженных наград рисует ТА ЖЕ
# _show_stat_panel, что и для своих: она читает faction у образца, поэтому
# грейды чужой фракции подставляются сами и отдельной ветки не нужно
var _recon_units: Array = []

func show_recon(units: Array) -> void:
	if button_container == null:
		return
	_recon_units = units.duplicate()
	_refresh_panel()

## Живые бойцы разведанного отряда. Отряд могли добить, пока панель открыта
func _recon_alive() -> Array:
	var out: Array = []
	for u in _recon_units:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
			out.append(u)
	return out

func _build_recon_panel(members: Array) -> void:
	var sample: Unit = members[0]
	var sid: int = sample.squad_id
	var uid: String = GameManager.squad_type(sid) if sid > 0 else sample.stat_id

	# Портрет в «вражеской» окраске: бордовый вместо синего — панель обязана
	# отличаться от своей с одного взгляда, до чтения подписи
	portrait.color = Color(0.28, 0.10, 0.12)
	if _portrait_icon != null and is_instance_valid(_portrait_icon):
		var tex := _icon_texture(unit_figure_path(uid, Constants.FACTION_ENEMY))
		_portrait_icon.texture = tex
		_portrait_icon.visible = tex != null
	if _portrait_count_lbl != null and is_instance_valid(_portrait_count_lbl):
		_portrait_count_lbl.visible = true
		_portrait_count_lbl.text = str(members.size())
	if _portrait_rank_lbl != null and is_instance_valid(_portrait_rank_lbl):
		var lvl: int = GameManager.squad_level(sid) if sid > 0 else 0
		_portrait_rank_lbl.visible = lvl > 0
		if lvl > 0:
			_portrait_rank_lbl.text = _UCfg.veteran_badge_text(lvl)
			_portrait_rank_lbl.add_theme_color_override("font_color",
				_UCfg.veteran_badge_color(lvl))
			_portrait_rank_lbl.add_theme_font_size_override("font_size", 13)
			# Полное звание — в подсказке: в строку значка оно не влезает,
			# а игроку нужно уметь его прочесть
			_portrait_rank_lbl.tooltip_text = "%s (уровень %d)" % [
				_UCfg.veteran_rank_name(uid, lvl), lvl]

	info_label.text = "%s (враг)\n%d бойцов — разведка" % [
		_squad_title_ranked(uid, GameManager.squad_level(sid) if sid > 0 else 0),
		members.size()]

	# Кнопок нет вовсе: button_container остался пустым и схлопнется по нулевой
	# ширине (см. _sync_panel_grid_widths). Полоса карточек отрядов — тоже нет:
	# кликом по ней выделяют отряд, а чужой выделять нельзя
	if sid > 0:
		# ЖИВОЕ ЗДОРОВЬЕ — ТОЛЬКО ЗДЕСЬ: ради него карточку разведки и открывают
		_show_stat_panel(sid, members, true)

## Разведка активна прямо сейчас (для стендов и для проверок фокуса)
func recon_visible() -> bool:
	return not _recon_alive().is_empty()

## Отрисовать нижнюю панель под текущие _sel_units / _expanded_type.
## Отдельно от show_selection: разворот группы (уровень 2) перерисовывает
## ТОЛЬКО панель и не трогает ни выделение, ни полосу групп
func _refresh_panel() -> void:
	if button_container == null:
		return
	var units: Array = _sel_units
	# remove_child ПЕРЕД queue_free — иначе старые кнопки ещё числятся детьми
	# (освобождение отложено до конца кадра), и _sync_panel_grid_widths в конце
	# этого же вызова считает их ВМЕСТЕ с новыми. У Замка это давало сетку на
	# 6 колонок вместо 3 и лишние ~95 px пустоты справа — та самая «панель
	# разъезжается». Тот же разбор, что и в _rebuild_forge_grid
	for b in button_container.get_children():
		button_container.remove_child(b)
		b.queue_free()
	_selected_node = null
	_selected_iid  = 0
	_detail_gain = false
	_detail_icon_path = ""
	if progress_bar: progress_bar.visible = false
	_set_progress_text("")
	if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
		_portrait_wrap.visible = true
	# Шкала опыта прошлого отряда не переживает смену выделения на здание
	# (ветки отрядов включают её сами) — иначе у загона висело «Ранг 2 → 3»
	_update_xp_bar(0)

	_clear_queue_ui()
	_hide_card()
	# Плашка награды и флажки ранга живут ровно столько, сколько живёт ряд
	# кнопок выбора: панель пересобирается — снимаем оба, иначе плашка остаётся
	# висеть справа от панели, у которой уже другое содержимое
	_hide_vet_tip()
	_hide_vet_rank_row()
	_hide_garrison()
	_hide_stat_panel()
	_rebuild_squad_strip()
	_refresh_squad_cmd_bar()   # ряд [S]/[C]/[A] — ТЗ 23.09.2026
	_train_badges.clear()   # кнопки пересобираются — старые ярлыки уже мертвы
	_afford_watch.clear()   # и реестр живой доступности вместе с ними
	_keep_rank_ui.clear()   # и кнопка ранга рыцарей с её радаром
	_tower_fort_ui.clear()
	_shelter_ui.clear()
	_free_alert_bell()      # колокол замка висит на HUD, не в ряду кнопок
	_last_research_id = ""

	# УКРУПНЕНИЕ ЗАМКА ГАСИТСЯ ЗДЕСЬ, а не в конце: ветка Замка ниже взводит его
	# заново, и портрет должен вернуться к обычному размеру для ЛЮБОГО другого
	# выделения (в т.ч. когда панель вообще пустая/скрыта уровнем 1)
	_castle_boost = false
	_worker_boost = false
	_hide_castle_caption()
	if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
		_portrait_wrap.custom_minimum_size = Vector2(PORTRAIT_W, PORTRAIT_W)
		# И ВЕРТИКАЛЬНАЯ ПРИВЯЗКА ТОЖЕ ВОЗВРАЩАЕТСЯ К ЦЕНТРУ: опускать портрет
		# к нижней кромке нужно только Замку — под подпись над иконкой
		_portrait_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# ── КУЗНИЦА: СВОЯ ПАНЕЛЬ ВМЕСТО ОБЩЕЙ ───────────────────────────────────
	# Решается ДО всех уровней выделения: панель кузницы подменяет нижнюю
	# целиком, и гонять её содержимое через _sync_panel_height бессмысленно.
	# Гасится безусловно, иначе древо осталось бы висеть поверх следующего
	# выделения
	if units.size() == 1 and units[0] is Smithy \
			and (units[0] as Smithy).faction == Constants.FACTION_PLAYER:
		_selected_node = units[0]
		_selected_iid  = (units[0] as Object).get_instance_id()
		show_forge(units[0] as Smithy)
		return
	hide_forge()

	# ── РАЗВЕДКА ЧУЖОГО ОТРЯДА ──────────────────────────────────────────────
	# Решается сразу после кузницы и ДО обоих уровней своего выделения: свои и
	# чужие в панели не смешиваются никогда, а разведка возможна только при
	# пустом своём выделении (show_selection гасит её сама)
	if not _recon_units.is_empty():
		var alive: Array = _recon_alive()
		if not alive.is_empty():
			if _bottom_panel: _bottom_panel.visible = true
			_build_recon_panel(alive)
			_sync_panel_grid_widths()
			_sync_panel_height()
			return
		# Отряд добили, пока карточка была открыта — молча закрываем её
		_recon_units.clear()

	# РАЗВЁРНУТАЯ ГРУППА МОГЛА ПОГИБНУТЬ ЦЕЛИКОМ, пока панель была открыта
	# (смена выделения при этом не происходит — её некому вызвать). Панель с
	# «0 бойцов (0 отр.)» и пустой полосой карточек — мусор, поэтому молча
	# возвращаемся на уровень 1
	if _expanded_type != "" \
			and int((_selection_groups()["squads"] as Dictionary).get(_expanded_type, 0)) <= 0:
		_expanded_type = ""

	# ── УРОВЕНЬ 2: РАЗВЁРНУТА ОДНА ГРУППА ────────────────────────────────────
	# (рабочие — не род: у них обычная панель артели, ТЗ 30.10.2026)
	if _expanded_type != "" and _expanded_type != WORKER_GROUP:
		if _bottom_panel: _bottom_panel.visible = true
		_build_type_detail(_expanded_type)
		_sync_panel_grid_widths()
		_sync_panel_height()
		return

	# ── УРОВЕНЬ 1: НЕСКОЛЬКО ТИПОВ — ДЕТАЛЬНОЙ ПАНЕЛИ НЕТ ВОВСЕ ──────────────
	# Ровно то, что просили: при смешанном выделении внизу видны только
	# компактные групповые иконки с числом отрядов, и ничего больше
	if selection_type_count() >= GROUP_BAR_MIN_TYPES and _parent_sids.is_empty():
		if _bottom_panel: _bottom_panel.visible = false
		_position_group_bar()
		return

	if units.is_empty():
		# ПУСТОЕ ВЫДЕЛЕНИЕ — ПАНЕЛЬ ПОЛНОСТЬЮ СКРЫТА, никаких пустых рамок
		# или дежурной кнопки «построить Замок». Первый Замок ставится через
		# стартовый флоу (Main.start_game → enter_castle_placement), а не
		# отсюда — см. ЭТАП1 п.4
		if _bottom_panel: _bottom_panel.visible = false
		return
	# ── РЫНОК — ОДНА ПАНЕЛЬ (ТЗ 29.10.2026): карточка здания с текстами снята,
	# окно обмена (_sync_market_panel) встаёт на место нижней панели
	if _market_selected(units):
		_selected_node = units[0]
		if _bottom_panel: _bottom_panel.visible = false
		return
	if _bottom_panel: _bottom_panel.visible = true

	var u = units[0]
	if units.size() == 1:
		_selected_node = u
		_selected_iid  = (u as Object).get_instance_id() if u is Object else 0
		if "current_health" in u and "max_health" in u:
			info_label.text  = "%s  %d/%d HP" % [u.display_name, int(u.current_health), int(u.max_health)]
		else:
			info_label.text = u.display_name if "display_name" in u else "Объект"

		# ── БАШНЯ: ХП и гарнизон, без найма (заказ 09.09.2026) ──────────────
		# Ветка стоит ПЕРЕД замковой: башня — тоже Castle (ради гарнизона), и
		# без неё получала бы кнопки найма рабочих и рыцарей
		if u is Castle and not (u as Castle).is_stronghold() \
				and not (u is Barracks) and u.faction == Constants.FACTION_PLAYER:
			portrait.color = Color(0.16, 0.20, 0.30)
			# ОДНА КНОПКА ГАРНИЗОНА (ТЗ 27.10.2026, второе письмо, п. 7): у башни
			# место на ОДИН отряд, и мини-слот секции «Гарнизон» дублировал
			# крупную «Выпустить» — секция у башни не строится
			if not _OptSys.tower_one_garrison_btn:
				_show_garrison(u as Castle)
			_garrison_vet_menu(u as Castle)
			_castle_boost = true
			# Обзор и гарнизон — второй строкой шапки, а не в info_label: та
			# ложилась поверх шапки (ТЗ 20.10.2026)
			_update_castle_caption(info_label.text + "\n"
				+ _tower_info_text(u as Castle).replace("\n", " · "))
			info_label.text = ""
			if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
				_portrait_wrap.custom_minimum_size = Vector2(
					CASTLE_PORTRAIT_W, CASTLE_PORTRAIT_W)
				_portrait_wrap.size_flags_vertical = Control.SIZE_SHRINK_END
			# Обе кнопки башни — одного размера и с иконкой в рамке
			# (TOWER_BTN_SIZE, TOWER_ICON_BOOST): прежние 55 px с иконкой ×1.5
			# торчали крупнее всей панели
			var tsz: float = TOWER_BTN_SIZE if _OptSys.tower_one_garrison_btn else BTN_SIZE * CASTLE_PANEL_BOOST
			var tib: float = TOWER_ICON_BOOST if _OptSys.tower_one_garrison_btn else CASTLE_ICON_BOOST
			if u.has_method("has_garrison") and bool(u.call("has_garrison")):
				var g_n: int = (u as Castle).garrison.size()
				var rb: Button = _cmd("Выпустить", Color(0.20, 0.28, 0.16),
					func(): _on_tower_release(u as Castle),
					String(UNIT_ICONS.get("archer", "")), {"title": "Выпустить лучников",
					"lines": ["Гарнизон: %d/%d" % [g_n, (u as Castle).garrison_limit()],
						"Отряд выходит из башни к воротам"]},
					tsz, tib)
				rb.name = "TowerReleaseBtn"
			# Укрепление прочности (ТЗ 20.10.2026, блок 4) — у КАЖДОЙ башни
			if u.has_method("fort_start"):
				_tower_fort_cmd(u as Castle, tsz, tib)

		elif u is Castle and (u as Castle).is_stronghold() 				and u.faction == Constants.FACTION_PLAYER:
			# ТОЛЬКО СТОЛИЦА: бараки с 14.09.2026 тоже Castle (крыша для
			# лучников), и без is_stronghold() их панель уезжала в замковую —
			# рыцарь с лычками, рабочий, монах, а копейщиков не было вовсе
			portrait.color = Color(0.12, 0.18, 0.30)
			_show_garrison(u as Castle)
			_garrison_vet_menu(u as Castle)
			# ЗАМОК: ТРИ ЮНИТА (Рабочий, Рыцарь/Мечник, Монах) — постройки
			# зданий убраны навсегда, они делаются Рабочим на карте (см.
			# _build_worker_menu). Панель и портрет увеличены на +30%
			# (CASTLE_PANEL_BOOST); иконки найма растут ЕЩЁ на +50% ПОВЕРХ
			# этого (CASTLE_ICON_BOOST) — крупнее самой кнопки, не просто
			# вместе с ней, чтобы они смотрелись агрессивно и были удобнее
			# для клика, а не просто масштабировались 1:1 с рамкой.
			# "Замок 1800/1800 HP" уезжает в компактную надпись НАД панелью
			# (_update_castle_caption) — внутри строки её дублировать незачем
			_castle_boost = true
			_update_castle_caption(info_label.text)
			info_label.text = ""
			if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
				_portrait_wrap.custom_minimum_size = Vector2(
					CASTLE_PORTRAIT_W, CASTLE_PORTRAIT_W)
				# ИКОНКА ЗАМКА ОПУЩЕНА, ЧТОБЫ ПОДПИСЬ ВСТАЛА НАД НЕЙ.
				# SHRINK_END вместо SHRINK_CENTER прижимает портрет к НИЖНЕЙ
				# кромке панели, освобождая сверху полосу CASTLE_CAPTION_BAND
				# ровно под строку «Замок N/N HP». По центру (как было) иконка
				# 52 px в панели 62 занимала её почти целиком, и подпись ложилась
				# прямо на картинку — жалоба владельца
				_portrait_wrap.size_flags_vertical = Control.SIZE_SHRINK_END
			var big: float = BTN_SIZE * CASTLE_PANEL_BOOST
			_train_cmd(u, "worker",  Color(0.18, 0.32, 0.18), big, CASTLE_ICON_BOOST)
			# РЫЦАРЬ — РОВНО ОДНА ИКОНКА, с лычками на ней; под ней кнопка ранга
			# [ I ] с радаром исследования (разбор — у _knight_column)
			var knight := _train_cmd(u, "warrior", Color(0.30, 0.14, 0.28), big, CASTLE_ICON_BOOST)
			_train_cmd(u, "monk",    Color(0.22, 0.26, 0.14), big, CASTLE_ICON_BOOST)
			_knight_column(u, knight, big)
			# Тревога (ТЗ 20.10.2026, блок 5) — с 21.10.2026 колокол в ПРАВОМ
			# ВЕРХНЕМ УГЛУ панели, а не кнопкой ряда; отдельной кнопки слота
			# укрытых рабочих больше нет — они мини-слотом в «Гарнизоне»
			# (ЛКМ — один, ПКМ — все), см. _shelter_mini
			_alert_corner(u as Castle)

		elif u is TownCenter and u.faction == Constants.FACTION_PLAYER:
			# Тот же единый стандарт производственного здания, что у Замка и Бараков
			portrait.color = Color(0.12, 0.18, 0.30)
			_castle_boost = true
			_update_castle_caption(info_label.text)
			info_label.text = ""
			if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
				_portrait_wrap.custom_minimum_size = Vector2(
					CASTLE_PORTRAIT_W, CASTLE_PORTRAIT_W)
				_portrait_wrap.size_flags_vertical = Control.SIZE_SHRINK_END
			var tbig: float = BTN_SIZE * CASTLE_PANEL_BOOST
			_train_cmd(u, "worker", Color(0.18, 0.32, 0.18), tbig, CASTLE_ICON_BOOST)
			# РУДНИКА В МЕНЮ БОЛЬШЕ НЕТ (заказ спринта 13): ничейные рудники на
			# плато остались, но ставить свои игрок не может — ни рабочим, ни
			# отсюда. Механика Mine.gd не тронута
			_build_cmd("barracks", Color(0.22, 0.20, 0.32), func(): GameManager.try_build_barracks(u))

		elif u is Barracks and u.faction == Constants.FACTION_PLAYER:
			# ЕДИНЫЙ СТАНДАРТ ПРОИЗВОДСТВЕННЫХ ЗДАНИЙ (заказ владельца: «приведи
			# Бараки к панели Замка»). Тот же _castle_boost, что и у Замка, —
			# он и есть весь стандарт: фиксированный размер панели, HP над
			# опущенной иконкой со скруглением, крупные кнопки найма по
			# вертикальному центру с отступом 15 px справа и очередь 2×5 без
			# рамки. Ни одной отдельной ветки под Бараки не заводится — иначе
			# два «стандарта» разъехались бы при первой же правке
			portrait.color = Color(0.14, 0.14, 0.26)
			_castle_boost = true
			_update_castle_caption(info_label.text)
			info_label.text = ""
			if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
				_portrait_wrap.custom_minimum_size = Vector2(
					CASTLE_PORTRAIT_W, CASTLE_PORTRAIT_W)
				_portrait_wrap.size_flags_vertical = Control.SIZE_SHRINK_END
			var bbig: float = BTN_SIZE * CASTLE_PANEL_BOOST
			# БАРАКИ — ПЕХОТА (09.09.2026): копейщики и мечники; лучники в стрелковой
			_train_cmd(u, "spearman", Color(0.14, 0.18, 0.36), bbig, CASTLE_ICON_BOOST)
			_train_cmd(u, "warrior",  Color(0.30, 0.14, 0.28), bbig, CASTLE_ICON_BOOST)
			# ЛУЧНИКИ НА КРЫШЕ (ТЗ 14.09.2026): полоса гарнизона и кнопка выгрузки.
			# ИКОНКА — НЕ ПОРТРЕТ ЛУЧНИКА (ТЗ 18.09.2026, п. 7): с портретом в
			# ряду найма кнопка читалась как «нанять лучников в бараках»; теперь
			# стрелы-вниз, узкая, как кнопка ранга Крепости, — ряд не растёт
			_show_garrison(u as Castle)
			_garrison_vet_menu(u as Castle)
			if (u as Castle).has_roof_garrison():
				_cmd("Выгрузить", Color(0.20, 0.28, 0.16),
					func(): _on_tower_release(u as Castle),
					"icon_rain_of_arrows.png", {"title": "Выгрузить лучников с крыши",
					"lines": ["Отряд сходит с крыши к воротам"]},
					bbig, 1.0)

		elif u is Building and u.building_id == "archery" \
				and u.faction == Constants.FACTION_PLAYER:
			# СТРЕЛКОВАЯ — тот же стандарт производственного здания, что у бараков
			portrait.color = Color(0.16, 0.26, 0.14)
			_castle_boost = true
			_update_castle_caption(info_label.text)
			info_label.text = ""
			if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
				_portrait_wrap.custom_minimum_size = Vector2(
					CASTLE_PORTRAIT_W, CASTLE_PORTRAIT_W)
				_portrait_wrap.size_flags_vertical = Control.SIZE_SHRINK_END
			var abig: float = BTN_SIZE * CASTLE_PANEL_BOOST
			_train_cmd(u, "archer", Color(0.20, 0.28, 0.16), abig, CASTLE_ICON_BOOST)

		elif u is Building and _UCfg.is_house(u.building_id) \
				and u.faction == Constants.FACTION_PLAYER:
			# ДОМ: что даёт (слоты лимита и еда), заказ 09.09.2026
			portrait.color = Color(0.26, 0.24, 0.18)
			info_label.text = _house_info_text(u as Building)

		elif u is Mine and u.faction == Constants.FACTION_PLAYER:
			# РУДНИК (ТЗ 12.10.2026): доход и мини-панель рабочих «5/5» —
			# клик по иконке выводит рабочих (то же, что ПКМ пустым выделением)
			portrait.color = Color(0.30, 0.24, 0.08)
			var mn := u as Mine
			# Тот же компактный вид, что у загона (ТЗ 14.10.2026, п. 2): название,
			# иконка рабочих «N / M», ниже — зелёный итог дохода
			info_label.text = "%s  %d/%d HP\n+%d золота в минуту" % [
				String(mn.get("_base_name")), int(mn.current_health), int(mn.max_health),
				int(round(mn.income_per_sec() * 60.0))]
			_detail_gain = true
			var wb: Button = _count_icon_btn(String(UNIT_ICONS.get("worker", "")),
				"%d/%d" % [mn.workers.size(), Mine.WORKER_CAP],
				{"title": "Рабочие в руднике: %d / %d" % [mn.workers.size(), Mine.WORKER_CAP],
				"lines": ["Клик — вывести рабочих из рудника"]},
				func(): _on_mine_release(mn))
			if wb != null:
				wb.disabled = mn.workers.is_empty()

		elif u is Building and String(u.building_id) == "sheep_pen" and u.faction == Constants.FACTION_PLAYER:
			# ЗАГОН: главное о нём — СКОЛЬКО ОВЕЦ ВЛЕЗЕТ (заказ спринта 13:
			# «Вместимость: X / 20 овец»). Строку собирает САМ ЗАГОН
			# (SheepPen.capacity_text): и потолок, и счёт привязанного стада
			# знает он, а не панель — второго описания вместимости быть не должно
			portrait.color = Color(0.30, 0.26, 0.16)
			info_label.text = _pen_info_text(u as Building)
			_detail_gain = true
			var pen_b := u as Building
			var pw_n: int = int(pen_b.call("workers_here")) if pen_b.has_method("workers_here") else 0
			_count_icon_btn(String(UNIT_ICONS.get("worker", "")),
				"%d/%d" % [pw_n, _UCfg.SHEEP_PEN_WORKERS],
				{"title": "Рабочие на загоне: %d / %d" % [pw_n, _UCfg.SHEEP_PEN_WORKERS],
				"lines": ["Клик — выделить их"]},
				func(): _select_pen_farmers(pen_b))

		elif u is Building and String(u.building_id) == "market" and u.faction == Constants.FACTION_PLAYER:
			# РЫНОК (ТЗ 27.10.2026): окно обмена открывается над панелью само
			# (_sync_market_panel), здесь — подпись
			portrait.color = Color(0.30, 0.22, 0.14)
			info_label.text = "%s  %d/%d HP\nОбмен ресурсов — окно над панелью" % [
				u.display_name, int(u.current_health), int(u.max_health)]

		elif u is Building and String(u.building_id) == "storehouse" and u.faction == Constants.FACTION_PLAYER:
			portrait.color = Color(0.24, 0.22, 0.16)
			info_label.text = "%s  %d/%d HP\nРабочие сдают сюда груз — сразу в казну" % [
				u.display_name, int(u.current_health), int(u.max_health)]

		elif u is Smithy and u.faction == Constants.FACTION_PLAYER:
			portrait.color = Color(0.24, 0.18, 0.10)
			_build_smithy_menu(u)

		elif u is Worker and u.faction == Constants.FACTION_PLAYER:
			portrait.color = Color(0.10, 0.22, 0.12)
			# Сеткой (ТЗ 30.10.2026) — без подписи: панель монолитна
			info_label.text = "" if _OptSys.worker_grid_panel \
				else "Рабочий  %d/%d HP" % [int(u.current_health), int(u.max_health)]
			_worker_boost = true
			_worker_portrait()
			# ПОРТРЕТ У РАБОЧЕГО ТЕПЕРЬ ТАКОЙ ЖЕ, КАК У ВСЕХ (заказ владельца —
			# «шаблон единый для всех типов юнитов»). Его увеличивали заодно с
			# иконками построек, но портрет к каталогу построек отношения не
			# имеет: из-за него плашка рабочего была видимо не такой, как у
			# мечника или лучника. Кнопки построек остаются укрупнёнными —
			# это про читаемость мелких картинок зданий, а не про шаблон
			_build_worker_menu(u, [], BTN_SIZE * WORKER_ICON_BOOST, WORKER_ICON_BOOST)

		elif u is Unit and u.display_name == "Мечник" and u.faction == Constants.FACTION_PLAYER:
			portrait.color = Color(0.26, 0.12, 0.28)
			info_label.text = _unit_stats_text("Мечник", u)

		elif u is Spearman and u.faction == Constants.FACTION_PLAYER:
			portrait.color = Color(0.12, 0.16, 0.28)
			info_label.text = _unit_stats_text("Копейщик", u)

		elif u.faction == Constants.FACTION_ENEMY:
			portrait.color = Color(0.28, 0.08, 0.08)
		else:
			portrait.color = Color(0.12, 0.12, 0.18)
	else:
		# АРТЕЛЬ РАБОЧИХ: рамкой выделили 3-5 человек — панель построек
		# обязана остаться. Раньше она рисовалась только при выделении
		# ровно одного рабочего, и группой строить было нельзя вовсе
		var crew := _player_worker_crew(units)
		if not crew.is_empty():
			portrait.color  = Color(0.10, 0.22, 0.12)
			# Подпись «Артель: N рабочих — строят вместе» снята (ТЗ 11.10.2026):
			# число рабочих стоит бейджем на портрете
			info_label.text = ""
			_worker_boost = true
			_worker_portrait()
			# ПОРТРЕТ У РАБОЧЕГО ТЕПЕРЬ ТАКОЙ ЖЕ, КАК У ВСЕХ (заказ владельца —
			# «шаблон единый для всех типов юнитов»). Его увеличивали заодно с
			# иконками построек, но портрет к каталогу построек отношения не
			# имеет: из-за него плашка рабочего была видимо не такой, как у
			# мечника или лучника. Кнопки построек остаются укрупнёнными —
			# это про читаемость мелких картинок зданий, а не про шаблон
			_build_worker_menu(crew[0], crew, BTN_SIZE * WORKER_ICON_BOOST, WORKER_ICON_BOOST)
		else:
			info_label.text = "Выбрано: %d юнитов" % units.size()
			portrait.color  = Color(0.10, 0.16, 0.24)

	_split_info_detail()
	_update_portrait_badges(units)

	# Панель стоек — для отряда, сохранённого на горячую клавишу Ctrl+1..9
	_maybe_add_stance_buttons(units)
	# АВТО-ЗАЩИТА ЩИТОМ. Вызов стоит ЗДЕСЬ, а не в хвосте _maybe_add_stance_buttons:
	# та выходит досрочно на половине выделений (рабочий или здание в списке,
	# отряд без сохранённого id), и кнопка не появлялась бы у одиночного мечника
	_maybe_add_guard_toggle(units)
	# Докупка спец-способностей отряду (колонка D древа кузницы) — по той же
	# причине отдельным вызовом, а не внутри стоек
	_maybe_add_ability_buttons(units)
	# «В ЗАМОК» — САМОЙ ПОСЛЕДНЕЙ, чтобы встать в правый конец ряда (см.
	# _add_to_castle_button)
	_add_to_castle_button(units)
	# Разбивка по типам — НЕЗАВИСИМО от стоек. Раньше вызов жил внутри
	# _maybe_add_stance_buttons, а та выходит досрочно на рабочем или здании в
	# выделении, — то есть панель не появлялась ровно в смешанном выделении,
	# ради которого она и делалась

	# САМЫЙ ПОСЛЕДНИЙ ШАГ: все ветки выше уже дописали свои кнопки в
	# button_container — теперь можно решить, нужна ли колонка кнопок вообще
	# и какой высоты должна быть панель под получившееся содержимое
	_sync_panel_grid_widths()
	_sync_panel_height()

# ═════════════════════════════════════════════════════════════════════════════
# УРОВЕНЬ 2: ДЕТАЛИЗАЦИЯ ОДНОГО ТИПА ВОЙСК
#
# Панель под конкретный тип из смешанного выделения: суммарная численность,
# по карточке на каждый отряд (состав, шкала здоровья, значок ранга) и
# обычные кнопки приказов. Выделение не меняется — сузить его до одного отряда
# можно кликом по карточке (см. _on_squad_card_pressed).
# ═════════════════════════════════════════════════════════════════════════════
func _build_type_detail(unit_id: String) -> void:
	var g: Dictionary = _selection_groups()
	var men: int    = int((g["men"] as Dictionary).get(unit_id, 0))
	var squads: int = int((g["squads"] as Dictionary).get(unit_id, 0))

	portrait.color = Color(0.12, 0.16, 0.28)
	# ── БОЛЬШОЙ ИКОНКИ РОДА СЛЕВА БОЛЬШЕ НЕТ (ТЗ 12.10.2026, второе письмо) ──
	# Портрет с суммой бойцов повторял то, что и так видно по карточкам, и
	# занимал место: в развороте рода панель — это карточки и ряд A/C/S/F1
	if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
		_portrait_wrap.visible = false
	# Портрет — иконка ТИПА, а не первого попавшегося в выделении юнита
	if _portrait_icon != null and is_instance_valid(_portrait_icon):
		var tex := _icon_texture(unit_figure_path(unit_id, Constants.FACTION_PLAYER))
		_portrait_icon.texture = tex
		_portrait_icon.visible = tex != null
	if _portrait_count_lbl != null and is_instance_valid(_portrait_count_lbl):
		_portrait_count_lbl.visible = men > 0
		_portrait_count_lbl.text = str(men)
	if _portrait_rank_lbl != null and is_instance_valid(_portrait_rank_lbl):
		_portrait_rank_lbl.visible = false

	# ГЛАВНАЯ ЦИФРА УРОВНЯ 2 — «57 бойцов» по этому типу, а не общая по армии
	# ОДНА СТРОКА: численность стоит бейджем на портрете, и повторять её текстом
	# незачем — вторую строку колонки занимает шкала опыта
	info_label.text = "%s  (%d отр.)" % [_squad_title(unit_id), squads]

	# Кнопки приказов — по бойцам ИМЕННО ЭТОГО типа: панель показывает их,
	# логично и стойку показывать их же
	var members: Array = []
	for u in _sel_units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var un := u as Unit
		if un.squad_id > 0 and GameManager.squad_type(un.squad_id) == unit_id:
			members.append(un)
	if not members.is_empty():
		_maybe_add_stance_buttons(members)
		_maybe_add_guard_toggle(members)
		# Приёмы — только у ОДНОГО отряда (см. _maybe_add_ability_buttons)
		_maybe_add_ability_buttons(members)
		_add_to_castle_button(members)
	# _maybe_add_stance_buttons переписывает info_label под ВСЁ выделение
	# (ids он берёт у SelectionManager) — возвращаем подпись типа обратно
	# ОДНА СТРОКА: численность стоит бейджем на портрете, и повторять её текстом
	# незачем — вторую строку колонки занимает шкала опыта
	info_label.text = "%s  (%d отр.)" % [_squad_title(unit_id), squads]

## Путь иконки для портрета выбранного — та же таблица, что и у кнопок найма/
## построек, чтобы портрет и панель приказов всегда показывали одну картинку
func _portrait_icon_path(units: Array) -> String:
	if units.is_empty():
		return ""
	var u = units[0]
	if u is Barracks:
		return _bld_icon("barracks")
	if u is Castle and not (u as Castle).is_stronghold():
		return _bld_icon("tower")
	if u is Castle or u is TownCenter:
		return _bld_icon("castle")
	if u is Smithy:
		return _bld_icon("smithy")
	# Остальные постройки (стрелковая, дома, рудник) — иконка из своей записи
	if u is Building and not (u as Building).building_id.is_empty():
		var bi: String = _bld_icon((u as Building).building_id)
		if not bi.is_empty():
			return bi
	if u is Worker:
		return String(UNIT_ICONS.get("worker", ""))
	if u is Unit:
		var uf: int = int((u as Unit).faction)
		if u is Archer:
			return unit_figure_path("archer", uf)
		if u is Spearman:
			return unit_figure_path("spearman", uf)
		if (u as Unit).display_name == "Мечник":
			return unit_figure_path("warrior", uf)
		if (u as Unit).stat_id == "monk":
			return unit_figure_path("monk", uf)
	return ""

## Иконка + бейджи портрета: количество (группа > 1) и значок ранга
## (одиночный юнит своего отряда с рангом > 0)
func _update_portrait_badges(units: Array) -> void:
	if _portrait_icon == null or not is_instance_valid(_portrait_icon):
		return
	var tex := _icon_texture(_portrait_icon_path(units))
	_portrait_icon.texture = tex
	_portrait_icon.visible = tex != null

	if _portrait_count_lbl != null and is_instance_valid(_portrait_count_lbl):
		_portrait_count_lbl.visible = units.size() > 1
		if units.size() > 1:
			_portrait_count_lbl.text = str(units.size())
		var nsq: int = _army_badge_squads()
		if nsq > 0:
			_portrait_count_lbl.visible = true
			_portrait_count_lbl.text = str(nsq)

	if _portrait_rank_lbl != null and is_instance_valid(_portrait_rank_lbl):
		var lvl := 0
		if units.size() == 1 and units[0] is Unit:
			var uu := units[0] as Unit
			if uu.squad_id > 0:
				lvl = GameManager.squad_level(uu.squad_id)
		_portrait_rank_lbl.visible = lvl > 0
		if lvl > 0:
			# ЛЫЧКИ И ЦВЕТ — ИЗ ТОЙ ЖЕ ТАБЛИЦЫ, ПО КОТОРОЙ НАРИСОВАНО ЗНАМЯ
			# (см. _UCfg.veteran_badge_text). Держать в панели свою шкалу
			# нельзя: она разъедется со знаменем при первой же правке — ровно
			# это уже случалось с прежней шкалой, когда грейд в панели считали
			# отдельно от грейда метки над отрядом
			var rank_id: String = ""
			if units.size() > 0 and units[0] is Unit:
				var ru := units[0] as Unit
				rank_id = GameManager.squad_type(ru.squad_id) if ru.squad_id > 0 \
					else ru.stat_id
			_portrait_rank_lbl.text = _UCfg.veteran_badge_text(lvl)
			_portrait_rank_lbl.add_theme_color_override("font_color",
				_UCfg.veteran_badge_color(lvl))
			_portrait_rank_lbl.add_theme_font_size_override("font_size", 13)
			# Полное звание — в подсказке: в строку значка оно не влезает
			_portrait_rank_lbl.tooltip_text = "%s (уровень %d)" % [
				_UCfg.veteran_rank_name(rank_id, lvl), lvl]

# ─────────────────────────────────────────────────────────────────────────────
# СТОЙКИ ОТРЯДА: [АТАКА] / [ЗАЩИТА]
# Кнопки показываются, только если выделение — сохранённая горячая группа
# (Ctrl+1..9). Активная стойка подсвечена.
# ─────────────────────────────────────────────────────────────────────────────
func _maybe_add_stance_buttons(units: Array) -> void:
	# ГЛАВНОЕ: решение принимается по ТОМУ ЖЕ списку, который сейчас рисуется
	# на панели. Раньше функция смотрела на sm.selected_units, а show_selection
	# вызывается и напрямую (например, из меню Кузницы после покупки апгрейда) —
	# тогда список на панели и выделение в SelectionManager расходились, и
	# кнопки стоек вылезали поверх панели Рудника или Кузницы
	if units.is_empty():
		return
	for u in units:
		if not is_instance_valid(u):
			return
		# Стойки — свойство ПЕХОТЫ. Ни здание, ни рабочий, ни чужой юнит
		# панель стоек не получают
		if u is Building or u is Worker or not (u is Unit):
			return
		if u.faction != Constants.FACTION_PLAYER:
			return
		if not u.has_method("set_stance"):
			return

	var main := GameManager.main
	if main == null:
		return
	var sm = main.selection_manager
	if sm == null or not sm.has_method("current_group_index"):
		return
	# СТОЙКИ ПОЛОЖЕНЫ ЛЮБОМУ ВЫДЕЛЕННОМУ ОТРЯДУ, а не только сохранённой
	# горячей группе. Раньше требовалось совпадение с Ctrl+1..9, и после
	# обычного клика по отряду кнопки [АТАКА]/[ЗАЩИТА] не появлялись вовсе —
	# приходилось сначала назначать группу и нажимать цифру второй раз
	var ids: Array = sm.selected_squad_ids() if sm.has_method("selected_squad_ids") else []
	if ids.is_empty():
		return
	var cur: String = sm.selection_stance()
	var grp: int = sm.current_group_index()
	var sid: int = int(ids[0]) if ids.size() == 1 else 0
	if sid > 0:
		var lvl: int = GameManager.squad_level(sid)
		var tname: String = _squad_title_ranked(GameManager.squad_type(sid), lvl)
		# ── ЧИСЛЕННОСТЬ ОТСЮДА УБРАНА ───────────────────────────────────────
		# Строка «Отряд мечников — 30 бойцов» слово в слово повторяла заголовок
		# окна статов, висящего РОВНО НАД НЕЙ, — дублировалось не столько слово,
		# сколько экранное место. Численность и так стоит бейджем на портрете,
		# а освободившаяся строка отдана шкале опыта
		# ЛЫЧКИ ИЗ ЗАГОЛОВКА УБРАНЫ: звание теперь стоит в самом названии
		# (см. _squad_title_ranked). Значок остался там, где на слова нет
		# места, — на портрете и на карточке отряда
		# ── ЗНАЧОК ЩИТА, ПОКА ИДЁТ СПЕЦПРИЁМ (заказ спринта 13) ─────────
		# «На панели отряда виден значок щита» — прямое требование к
		# «Яростному Набегу». Значок ТЕКСТОВЫЙ, а не картинкой: строка
		# названия собирается одним Label, и лепить в неё TextureRect
		# означало бы разбирать её на контейнер ради одного глифа. Тот же
		# приём, что у лычек ранга в подписи отряда
		info_label.text = "%s%s%s" % [
			tname, _squad_ability_mark(units),
			("  (отряд %d)" % (grp + 1)) if grp >= 0 else ""]
		_update_xp_bar(sid)
		_show_squad_stats(sid, units)
		# Полная раскладка статов с источниками бонусов — отдельной панелью
		_show_stat_panel(sid, units)
	else:
		# ТЗ 30.10.2026: строки «Отрядов: N — M» нет — число отрядов стоит
		# бейджем на портрете, Tab раскрывает их карточками
		info_label.text = "" if _OptSys.army_count_badge \
			else "Отрядов: %d — %d бойцов" % [ids.size(), units.size()]
		_update_xp_bar(0)

	# ВЫБОР ВЕТЕРАНСКОГО БОНУСА важнее стоек: пока игрок не выбрал улучшение,
	# панель показывает пять кнопок выбора ВМЕСТО [АТАКА]/[ЗАЩИТА].
	# Так сделано намеренно: пять кнопок плюс две стойки не влезают в один ряд
	# сетки, а второй ряд вылез бы за нижнюю панель
	if sid > 0 and GameManager.squad_pending(sid) > 0:
		_build_veteran_menu(sid, units)
		return

	var atk_on: bool = (cur == _UCfg.STANCE_ATTACK)
	var def_on: bool = (cur == _UCfg.STANCE_DEFENSE)
	# Образец бойца для «живого» пересчёта параметров стойки в тултипе
	var sample: Unit = null
	for u2 in units:
		if is_instance_valid(u2) and u2 is Unit:
			sample = u2 as Unit
			break
	# ИКОНКИ СТОЕК: меч — атака, щит — защита. Если файла нет, кнопка честно
	# останется с подписью словом (у _cmd пустой путь = текст на кнопке)
	# Последний аргумент — та самая жёлтая обводка активной стойки (см. _cmd).
	# Заливка тоже осталась разной, но полагаться на неё одну нельзя: у «Атаки»
	# оба оттенка тёмно-красные и в глаза разница не бросается
	# ── ПОРЯДОК И ЦВЕТА КНОПОК ЗАДАНЫ ВЛАДЕЛЬЦЕМ ────────────────────────────
	# [Атака (красный)] → [Защита (зелёный)] → [Пассивка (жёлтая)] → [To Castle
	# (тёмно-красный)]. Первые две — здесь; пассивку добавляет
	# _maybe_add_guard_toggle, «в замок» — _add_to_castle_button, и оба зовутся
	# ПОСЛЕ этой функции (см. show_selection), поэтому очередь в сетке выходит
	# ровно та, что заказана.
	#
	# «Защита» была СИНЕЙ. Смена на зелёный — не вкусовщина: синий здесь ничему
	# не соответствовал, а красный/зелёный/жёлтый читаются как «бой / оборона /
	# постоянный эффект» без единой подписи
	# ── КНОПКИ СТОЕК ATTACK/DEFEND СНЯТЫ (ТЗ 10.10.2026, блок 4) ───────────
	# Их работу делают [C] «Вольно» и [S] «Держать позицию» ряда команд
	# (_squad_cmd_bar): две пары кнопок одного смысла рядом читались как разные
	# приказы. Карточка стойки (_stance_card) осталась в коде
	pass

## Иконка замка для кнопки «в замок» — та же картинка, что у кнопки постройки
## замка и у его портрета: одна вещь в интерфейсе выглядит одинаково везде
const ICON_TO_CASTLE := "res://assets/factions/humans/icons/buildings/Castle.png"

## ОТПРАВИТЬ ОТРЯД ЛЕЧИТЬСЯ. Отряд сам бежит к ближайшему своему замку, заходит
## внутрь и выходит, когда здоровье и состав восстановлены.
##
## ОТДЕЛЬНОЙ ФУНКЦИЕЙ И ПОСЛЕДНИМ ВЫЗОВОМ. Раньше кнопка добавлялась внутри
## _maybe_add_stance_buttons сразу за стойками, то есть ВПЕРЕДИ пассивки, и
## оказывалась в середине ряда. «В самый правый угол» из задания достигается не
## якорем (сетка кнопок раскладывает детей по порядку), а тем, что эта кнопка
## добавляется в button_container ПОСЛЕДНЕЙ
func _add_to_castle_button(units: Array) -> void:
	var sm = GameManager.main.selection_manager if GameManager.main != null else null
	if sm == null or not is_instance_valid(sm):
		return
	# Только для СВОИХ боевых юнитов: рабочего в замок отправлять незачем, а
	# чужой отряд (карточка разведки) приказов не принимает вовсе
	var any := false
	for u in units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var un := u as Unit
		if un.faction != Constants.FACTION_PLAYER or un.squad_id <= 0 or un is Worker:
			continue
		# ВЫБОР ВЕТЕРАНСКОЙ НАГРАДЫ ЗАНИМАЕТ ВСЮ СЕТКУ ЦЕЛИКОМ. Пока награда не
		# выбрана, панель показывает пять кнопок выбора ВМЕСТО приказов (см.
		# _maybe_add_stance_buttons — она ради этого выходит досрочно). Шестая
		# кнопка, добавленная в обход того выхода, ломала бы ряд: qa_vet сразу
		# показал «кнопок=6, ожидали 5»
		if GameManager.squad_pending(un.squad_id) > 0:
			return
		any = true
	if not any:
		return
	# Кнопка «To Castle» снята (ТЗ 10.10.2026, блок 4): её место — [F1] в
	# ряду команд (_squad_cmd_bar), та же точка входа _on_send_to_castle
	pass

# ═════════════════════════════════════════════════════════════════════════════
# ШКАЛА ОПЫТА ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
## Прогресс до СЛЕДУЮЩЕГО ранга. Пороги ветеранства берутся из конфига и
## СЧИТАЮТСЯ ПОВТОРЯЮЩИМИСЯ: VET_CONFIG.thresholds вида [40,40,40,40,40,40,50]
## — законная запись (одно убийство даёт сразу несколько уровней), и наивное
## «(kills − порог[lvl−1]) / (порог[lvl] − порог[lvl−1])» делило бы на ноль.
## Поэтому ищем ближайший порог СТРОГО БОЛЬШЕ текущих убийств и наибольший из
## уже взятых — так формула верна при любой форме лестницы
func _xp_progress(unit_id: String, kills: int) -> Dictionary:
	var top: int = _UCfg.max_veteran_level(unit_id)
	var prev: int = 0
	var next: int = -1
	for l in range(1, top + 1):
		var t: int = _UCfg.veteran_threshold(unit_id, l)
		if t <= kills:
			prev = maxi(prev, t)
		elif next < 0 or t < next:
			next = t
	if next < 0:
		return {"frac": 1.0, "have": kills, "need": 0, "maxed": true}
	var span: int = maxi(next - prev, 1)
	return {"frac": clampf(float(kills - prev) / float(span), 0.0, 1.0),
		"have": kills - prev, "need": span, "maxed": false}

## Показать шкалу опыта отряда. sid = 0 — спрятать (сборная солянка из нескольких
## отрядов общего опыта не имеет)
func _update_xp_bar(sid: int) -> void:
	if _xp_bar == null or not is_instance_valid(_xp_bar):
		return
	if sid <= 0 or not GameManager.squads.has(sid):
		_xp_bar.visible = false
		if _xp_row != null and is_instance_valid(_xp_row):
			_xp_row.visible = false
		return
	var uid: String = GameManager.squad_type(sid)
	var p: Dictionary = _xp_progress(uid, GameManager.squad_kills(sid))
	_xp_bar.visible = true
	_xp_bar.value = float(p["frac"])
	if _xp_label != null and is_instance_valid(_xp_label):
		_xp_row.visible = true
		var lvl: int = GameManager.squad_level(sid)
		_set_xp_flag(lvl)
		if bool(p["maxed"]):
			_xp_label.text = "высший ранг"
		else:
			_xp_label.text = "%d/%d" % [int(p["have"]), int(p["need"])]
		_xp_label.tooltip_text = "Ранг %d" % lvl

## Флажок текущего ранга перед числом опыта; пересобирается только на смене
## ранга. Ранг 0 знамени не имеет — флажка нет
func _set_xp_flag(lvl: int) -> void:
	if _xp_row == null or lvl == _xp_flag_lvl:
		return
	_xp_flag_lvl = lvl
	var old: Node = _xp_row.get_node_or_null("XpFlag")
	if old != null:
		_xp_row.remove_child(old)
		old.queue_free()
	if lvl <= 0:
		return
	var fl: Control = _vet_flag(lvl, 1.0, 13.0)
	fl.name = "XpFlag"
	fl.tooltip_text = "Ранг %d" % lvl
	_xp_row.add_child(fl)
	_xp_row.move_child(fl, 0)

## Меч и щит для кнопок стойки
const ICON_STANCE_ATTACK  := "res://assets/ui/icons_units_human/Attacks_human.png"
const ICON_STANCE_DEFENSE := "res://assets/ui/icons_units_human/Deffens_humans.png"

## ── ПОДСВЕТКА АКТИВНОЙ КНОПКИ (стойки) ──────────────────────────────────────
## Жёлтый той же семьи, что и рамка наведения в _cmd и рамка активного заказа в
## очереди, — интерфейс говорит «вот это сейчас включено» одним цветом везде.
## 2 px, а не 1: на кнопке 22-34 px однопиксельная рамка на глаз не отличается
## от обычной обводки, которая есть у ВСЕХ кнопок
const ACTIVE_BORDER_W      := 2
const ACTIVE_BORDER_RADIUS := 5
const ACTIVE_BORDER_COLOR  := Color(1.0, 0.84, 0.25)

# ─────────────────────────────────────────────────────────────────────────────
# КНОПКА-ПЕРЕКЛЮЧАТЕЛЬ «АВТО-ЗАЩИТА ЩИТОМ» (только мечники)
# Горит — включена, потухшая — выключена. Состояние читается у самих юнитов,
# поэтому кнопка всегда показывает правду, даже если отряд собран из бойцов
# с разными настройками (тогда считается «включено, если включён хоть у кого»).
# ─────────────────────────────────────────────────────────────────────────────
## Иконки состояния: включено — «play», выключено — «cancel».
## Берутся из набора главного меню — другого набора значков в проекте нет
const ICON_GUARD_ON  := "res://assets/environment/main menu/iconc_menu/Icon_play_continue.png"
const ICON_GUARD_OFF := "res://assets/environment/main menu/iconc_menu/Icon_cancel.png"
## Текст подсказки — единый для обоих состояний, состояние читается по иконке
const GUARD_TOOLTIP := "Пассивное умение: Стена щитов. Автоматически поднимать щиты при вражеском обстреле."

func _warriors_in(units: Array) -> Array:
	var men: Array = []
	for u in units:
		if not is_instance_valid(u):
			continue
		if u is Warrior and not (u as Warrior).is_dead() \
				and (u as Warrior).faction == Constants.FACTION_PLAYER:
			men.append(u)
	return men

func _maybe_add_guard_toggle(units: Array) -> void:
	var men: Array = _warriors_in(units)
	if men.is_empty():
		return
	var on := false
	for w in men:
		if (w as Warrior).auto_guard:
			on = true
			break
	# ЦВЕТ = СОСТОЯНИЕ, И САМ ЦВЕТ = «ПАССИВКА» (жёлтый, заказ владельца).
	# Включено — тёплый янтарь, выключено — он же, потухший. Синим кнопка спорила
	# с «Защитой», у которой и иконка щита та же самая
	var col: Color = Color(0.74, 0.58, 0.12) if on else Color(0.22, 0.19, 0.10)
	var title: String = "Стена щитов: ВКЛ" if on else "Стена щитов: ВЫКЛ"
	var btn: Button = _cmd("СТЕНА ЩИТОВ", col,
		func(): _on_guard_toggle(units, men, not on),
		ICON_GUARD_ON if on else ICON_GUARD_OFF, {"title": title, "lines": [
			"Мечник сам поднимает щит, когда в него стреляют",
			"и когда стоит без дела",
			"Урон от стрел −%d%%, от ближнего боя −%d%%" % [
				int(Warrior.GUARD_CUT_RANGED * 100.0),
				int(Warrior.GUARD_CUT_MELEE * 100.0)],
			"Удары в спину щит не держит",
			"Под щитом скорость шага −%d%%" % int((1.0 - Warrior.GUARD_SPEED_FACTOR) * 100.0),
			"Выключено — идёт на полной скорости без щита"]})
	# Состояние видно и в подсказке, а не только по цвету: иконка щита у кнопки
	# та же самая, что у стойки «ЗАЩИТА», и без подписи их легко перепутать
	if btn != null:
		btn.tooltip_text = GUARD_TOOLTIP

# ═════════════════════════════════════════════════════════════════════════════
# ПОКУПКА СПЕЦ-СПОСОБНОСТИ ОТРЯДУ (второй этап колонки D древа кузницы)
#
# Исследование в кузнице открывает способность ФРАКЦИИ, но не выдаёт её никому:
# каждый отряд докупает её себе за золото. Поэтому кнопка живёт не в кузнице,
# а в панели ВЫДЕЛЕННОГО ОТРЯДА — именно тому отряду, на который смотрит игрок.
#
# Кнопка появляется, только когда есть что покупать: узел исследован, отряд
# нужного рода войск, и способность у него ещё не куплена. Уже купленная
# показывается погашенной с галочкой — чтобы было видно, что она есть.
# ═════════════════════════════════════════════════════════════════════════════

## Уникальные id отрядов ИГРОКА в выделении, в порядке первого появления
func _player_squad_ids(units: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for u in units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var un := u as Unit
		if un.faction != Constants.FACTION_PLAYER or un.squad_id <= 0:
			continue
		if seen.has(un.squad_id):
			continue
		seen[un.squad_id] = true
		out.append(un.squad_id)
	return out

func _maybe_add_ability_buttons(units: Array) -> void:
	var sids: Array = _player_squad_ids(units)
	# ── ПРИЁМЫ — ТОЛЬКО У ОДНОГО ОТРЯДА (ТЗ 12.10.2026, второе письмо) ──────
	# В общем окне армии («Залп», «Снайпер» на двенадцать отрядов разом) иконки
	# приёмов загромождали панель; их место — при выделении одного отряда
	if sids.size() != 1:
		return
	# Тип берём у ПЕРВОГО отряда: способности привязаны к роду войск, и в
	# смешанном выделении показывать вперемешку копейщицкие и лучничьи нечего —
	# уровень 2 (разворот одной группы) как раз для того и существует
	var unit_id: String = GameManager.squad_type(int(sids[0]))
	if unit_id.is_empty() or not _Forge.UNITS.has(unit_id):
		return
	var mine: Array = []
	for sid in sids:
		if GameManager.squad_type(int(sid)) == unit_id:
			mine.append(int(sid))
	var f: int = Constants.FACTION_PLAYER
	for n in _Forge.ability_nodes(unit_id):
		var node: Dictionary = n
		var nid: String = String(node.get("id", ""))
		if not GameManager.is_researched(f, nid):
			continue                       # ещё не открыто в кузнице — не показываем
		var cost: float = _Forge.squad_unlock_cost(node)
		# Сколько из выделенных отрядов ещё без этой способности
		var need: Array = []
		for sid in mine:
			if not GameManager.squad_has_ability(int(sid), nid):
				need.append(int(sid))
		var owned: int = mine.size() - need.size()
		var title: String = String(node.get("name", nid))
		var col: Color = Color(0.16, 0.30, 0.42) if not need.is_empty() \
			else Color(0.20, 0.34, 0.20)
		# ── ПОДПИСЬ БОЛЬШЕ НЕ ГОВОРИТ О ПОКУПКЕ (спринт 13, блок 4) ─────────
		# Плату за доступ убрали: узел кузницы открывает способность СРАЗУ
		# всем отрядам этого рода. Строки «покупается каждому отряду» и
		# «Цена: 0 золота» врали бы игроку в глаза. Цена остаётся в конфиге
		# историей, и если владелец однажды вернёт её, вернётся и строка
		var lines: Array = [String(node.get("desc", ""))]
		if cost > 0.0:
			lines.append("Цена: %d золота за отряд" % int(cost))
			if owned > 0:
				lines.append("Уже есть у отрядов: %d" % owned)
			if not need.is_empty():
				lines.append("Купить для отрядов: %d  (итого %d з)" % [
					need.size(), int(cost) * need.size()])
		else:
			lines.append("Способность рода войск — открыта в кузнице для всех отрядов")
		# ── «ЯРОСТНАЯ АТАКА»: КНОПКА ВЫЗОВА С КРУГОМ ОТКАТА (ТЗ 23.10.2026, п. 6)
		if nid == GameManager.RAGE_NODE and need.is_empty():
			lines.append("Вызов: кнопка, двойной ПКМ или [R]; сама — на первом ударе в ближнем бою")
			lines.append("Откат %d с на отряд" % int(GameManager.RAGE_ABILITY_COOLDOWN_SEC))
			var mine_r: Array = mine.duplicate()
			var on_rage := func():
				for s_r in mine_r:
					GameManager.squad_start_rage(int(s_r), false)
			var rb: Button = _cmd(title, Color(0.42, 0.16, 0.12), on_rage,
				String(node.get("icon", "")), {"title": title, "lines": lines})
			if rb != null:
				rb.clip_contents = true
				var rad = _CooldownRadialS.new()
				rad.sids = mine.duplicate()
				rb.add_child(rad)
			continue
		var btn: Button = _cmd(title, col,
			func(): _on_buy_squad_ability(units, need, nid),
			String(node.get("icon", "")), {"title": title, "lines": lines})
		if btn == null:
			continue
		if need.is_empty():
			# ── КУПЛЕНО ─────────────────────────────────────────────────────
			# Обычная способность просто гаснет, как изученное улучшение в
			# кузнице. А способность-РЕЖИМ (forge_config toggle) превращается в
			# переключатель — ровно как «стена щитов» у мечника: горит жёлтой
			# рамкой, когда включена. Отличать их по id способности здесь нельзя:
			# панель не должна знать имён, признак живёт в конфиге
			if _Forge.is_toggle_ability(node):
				var on: bool = _ability_mode_on(mine, nid)
				btn.queue_free()
				_add_ability_toggle(units, mine, nid, node, on)
				continue
			_apply_upgrade_state(btn, title, true, false, false)
		else:
			var blocker: String = GameManager.squad_ability_blocker(int(need[0]), nid)
			btn.disabled = not blocker.is_empty()
			btn.tooltip_text = "%s — %s" % [title, blocker] if not blocker.is_empty() \
				else "%s — купить этому отряду за %d з" % [title, int(cost)]

## Включён ли режим хоть у одного из выделенных отрядов. «Хоть у одного», а не
## «у всех», по той же причине, что и у стены щитов: смешанное состояние надо
## показать как включённое, иначе один отряд с выключённым режимом гасил бы
## кнопку и игрок не понимал бы, почему остальные стреляют залпом
func _ability_mode_on(sids: Array, node_id: String) -> bool:
	for sid in sids:
		if GameManager.squad_ability_on(int(sid), node_id):
			return true
	return false

## КНОПКА-ПЕРЕКЛЮЧАТЕЛЬ КУПЛЕННОГО РЕЖИМА. Цвет и рамка — те же, что у стойки:
## жёлтая обводка означает «включено» во всём интерфейсе
func _add_ability_toggle(units: Array, sids: Array, node_id: String,
		node: Dictionary, on: bool) -> void:
	var title: String = String(node.get("name", node_id))
	var col: Color = Color(0.24, 0.40, 0.56) if on else Color(0.13, 0.16, 0.20)
	# Плашка — описание узла и ЕГО строки режима (forge_config toggle_lines);
	# общих строк про залп у переключателя больше нет — у «Стены копий» в
	# плашке стоял текст про лучников (ТЗ 18.09.2026, п. 6)
	var lines: Array = [String(node.get("desc", "")),
		"Режим отряда: %s" % ("ВКЛЮЧЁН" if on else "выключен")]
	var extra: Variant = node.get("toggle_lines")
	if extra != null:
		for ln in (extra as Array):
			lines.append(String(ln))
	var btn: Button = _cmd(title, col,
		func(): _on_ability_toggle(units, sids, node_id, not on),
		String(node.get("icon", "")), {"title": title, "lines": lines},
		0.0, 1.0, on)
	if btn != null:
		btn.tooltip_text = "%s — %s" % [title, "ВКЛ" if on else "ВЫКЛ"]

func _on_ability_toggle(units: Array, sids: Array, node_id: String, on: bool) -> void:
	AudioManager.play_ui("menu_button")
	for sid in sids:
		GameManager.squad_set_ability(int(sid), node_id, on)
	show_selection(units)

func _on_buy_squad_ability(units: Array, sids: Array, node_id: String) -> void:
	var bought := 0
	for sid in sids:
		if GameManager.squad_buy_ability(int(sid), node_id):
			bought += 1
	if bought > 0:
		show_selection(units)

## on — какое состояние ставим. `units` — ТОТ ЖЕ список, по которому нарисована
## панель: перерисовываем именно его, а не sm.selected_units. Списки расходятся
## (панель зовут и напрямую), и по selected_units кнопка после нажатия исчезала
func _on_guard_toggle(units: Array, men: Array, on: bool) -> void:
	AudioManager.play_ui("menu_button")
	for w in men:
		if is_instance_valid(w) and w is Warrior:
			(w as Warrior).set_auto_guard(on)
	# Перерисовать панель, чтобы кнопка сменила подсветку
	show_selection(units)

## Отправить выделенный отряд в ближайший свой замок на лечение
func _on_send_to_castle(sm: SelectionManager) -> void:
	if sm == null:
		return
	var men: Array = []
	for u in sm.selected_units:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
			men.append(u)
	if men.is_empty():
		return
	# Ближайший замок ищем от СЕРЕДИНЫ отряда, а не от первого бойца: иначе
	# растянувшийся строй мог разбежаться по двум разным замкам
	var mid := Vector3.ZERO
	for m in men:
		mid += (m as Node3D).global_position
	mid /= float(men.size())
	var best: Castle = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("player_buildings"):
		var c := b as Castle
		if c == null or c.is_dead():
			continue
		# Башня — тоже Castle, но «в замок» ведёт в крепость: лечить и
		# пополнять любой отряд умеет только она
		if not c.is_stronghold():
			continue
		var d: float = mid.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	if best == null:
		return
	# Заявка на вход — ШТАТНЫМ путём замка: он сам примет отряд, когда тот
	# подойдёт на GARRISON_ENTER_RADIUS, вылечит и выпустит обратно
	# ── ВСЕ ВЫДЕЛЕННЫЕ ОТРЯДЫ, А НЕ ПЕРВЫЙ (ТЗ 29.09.2026, блок 5) ──────────
	# Не принятые (полно) — в очередь лечения: ждут у входа и садятся сами
	var sids: Array = []
	for m in men:
		var s0: int = (m as Unit).squad_id
		if s0 > 0 and not sids.has(s0):
			sids.append(s0)
	# ── ВСЕ ОТРЯДЫ УХОДЯТ С ПЕРВОГО КЛИКА (ТЗ 22.10.2026, блок 2) ──────────
	# Лог партии 22.10, 30:18: девять отрядов одним кликом, в замке 6 + 2 в
	# пути при лимите 8 — семь отрядов получили отказ и ждали в очереди
	# обычным маршем, то есть «тупили» под ударами. Теперь каждый отряд
	# садится в ближайшую крепость, где есть место, а не принятый нигде
	# сразу бежит к воротам в режиме отхода и садится по мере мест
	# (GameManager.squad_to_castle)
	var accepted: bool = false
	for s1 in sids:
		if GameManager.squad_to_castle(int(s1)):
			accepted = true
	# ЗДЕСЬ БЫЛ САМОСАБОТАЖ. После request_garrison() шёл цикл
	#   for m in men: m.command_move(best.global_position)
	# без keep_retreat — а такой приказ ПЕРВЫМ ДЕЛОМ зовёт end_retreat()
	# (см. Unit.command_move). То есть кнопка «в замок» сама же и снимала режим
	# отхода, который только что включил замок: отряд шёл к воротам обычным
	# маршем — с перехватом встречных, ответной агрессией и упором в чужой строй,
	# — и до ворот доходил как получится. Штатный путь (Castle.request_garrison)
	# уже разослал всем нужный приказ, дублировать его нечем.
	if accepted:
		return
	# Замок отряд не принял (гарнизон полон или отряда нет) — ведём людей к нему
	# обычным приказом игрока, чтобы кнопка хотя бы не молчала
	for m in men:
		(m as Unit).command_move(best.global_position, false, Vector3.ZERO, false, true)

## Карточка стойки: множители читаются из конфига стоек, а Defense —
## ЖИВОЙ пересчёт для образца бойца из текущего выделения (defense_bonus
## стойки — плоская добавка, поэтому укладывается в формулу
## База+Кузница+Опыт=Итог наравне с бонусом кузницы)
func _stance_card(sample: Unit, stance_id: String, active: bool) -> Dictionary:
	var lines: Array = []
	if active:
		lines.append("[color=%s]▶ stance active[/color]" % TOTAL_COLOR)
	if sample != null and is_instance_valid(sample):
		var f: int = sample.faction
		var forge: float = GameManager.get_upgrade(f, "defense") \
			+ _UCfg.stance_stat(stance_id, "defense_bonus", 0.0)
		lines.append(_stat_formula(String(STAT_ROW_LABELS["defense"]), sample.defense, forge, sample.vet_defense))
	else:
		lines.append("Defense: +%d" % int(_UCfg.stance_stat(stance_id, "defense_bonus", 0.0)))
	lines.append("Attack speed: x%.2f" % _UCfg.stance_stat(stance_id, "attack_speed_mult", 1.0))
	lines.append("Morale: x%.2f" % _UCfg.stance_stat(stance_id, "morale_mult", 1.0))
	var pm: float = _UCfg.stance_stat(stance_id, "push_mult", 1.0)
	lines.append(("Own push: x%.2f" % pm) if pm > 0.0 else "Cannot push")
	lines.append("Incoming push: x%.2f" % _UCfg.stance_stat(stance_id, "push_resist", 1.0))
	if bool(_UCfg.get_stance(stance_id).get("holds_ground", false)):
		lines.append("Holds formation, ranks 1-2 level spears")
	return {
		"title": String(_UCfg.get_stance(stance_id).get("name", stance_id)),
		"icon": "", "lines": lines,
	}

# ─────────────────────────────────────────────────────────────────────────────
# ПАНЕЛЬ МУЛЬТИ-ВЫБОРА (левый нижний угол)
# Когда рамкой захвачена куча войск, здесь показывается разбивка ПО ТИПАМ:
# «2 отряда копейщиков», «1 отряд лучников», «5 рабочих». Клик по иконке
# оставляет в выделении только этот тип.
# Считаем в ОТРЯДАХ, а не в бойцах: рабочий — отряд из одного, поэтому пять
# рабочих читаются как «5», а отряд копейщиков — как «1».
# ─────────────────────────────────────────────────────────────────────────────
## Сторона групповой иконки уровня 1. Полоса называется «компактной» —
## она уменьшена вместе с остальной панелью (было 52)
const FILTER_SLOT := 34
## ── ЯЧЕЙКА РОДА ВЫШЕ, ФИГУРКА КРУПНЕЕ, ЧИСЛО РЯДОМ (ТЗ 27.10.2026, третье
## письмо, п. 3) ─────────────────────────────────────────────────────────────
## Кнопка FILTER_SLOT_W × FILTER_SLOT_H: фигурка в полный рост занимает левую
## часть (почти без отступа), число отрядов — компактной цифрой в правой
## полосе FILTER_NUM_W, рядом с фигуркой, а не поверх её ног
const FILTER_SLOT_W := 46
const FILTER_SLOT_H := 54
const FILTER_NUM_W := 14
## Ширина ЯЧЕЙКИ под иконкой — шире самой иконки.
## Подпись «32 бойца» в 34 px не влезает и обрезается многоточием («32…»), а
## цифра состава — половина смысла слота: сверху на иконке стоит число ОТРЯДОВ,
## снизу число БОЙЦОВ, и одно без другого читается как загадка. Иконка при этом
## остаётся 34 px и центрируется в ячейке
const FILTER_CELL := 52

## ПАНЕЛЬ РАЗБИВКИ ТИПОВ ПЕРЕЕХАЛА В БАННЕР (см. _build_overbar).
## Раньше это был отдельный плавающий PanelContainer с теми же якорями, что и
## плашка бездельников, — два элемента налезали друг на друга в левом нижнем
## углу. Теперь сводные ярлыки и ярлык рабочих живут слотами ОДНОЙ полосы,
## а слот строится тем же _filter_slot(), что и раньше.

## ТЗ 10.10.2026, блок 4: серые задние плашки сняты, иконки стоят вплотную
## (зазор 3 px), на иконке — число ОТРЯДОВ рода. Развёрнутый род обведён
## жёлтым. Подпись «N бойцов» под иконкой снята (число бойцов — в подсказке)
func _filter_slot(unit_id: String, squads: int, men: int) -> Control:
	var vb := VBoxContainer.new()
	vb.name = "GroupSlot_" + unit_id
	vb.add_theme_constant_override("separation", 0)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(FILTER_SLOT_W, FILTER_SLOT_H)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.clip_contents = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = ""
	var active: bool = unit_id == _expanded_type
	var sn := StyleBoxFlat.new(); sn.bg_color = Color(0, 0, 0, 0)
	_borders(sn, 2); _corners(sn, 4)
	sn.border_color = Color(0.95, 0.85, 0.35) if active else Color(0, 0, 0, 0)
	var sh := StyleBoxFlat.new(); sh.bg_color = Color(1, 1, 1, 0.06)
	_borders(sh, 2); _corners(sh, 4); sh.border_color = Color(0.95, 0.88, 0.55)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover",  sh)
	btn.add_theme_stylebox_override("pressed", sn)
	var ipath: String = unit_figure_path(unit_id, Constants.FACTION_PLAYER)
	if unit_id == WORKER_GROUP:
		ipath = WORKER_GROUP_FIGURE % String(GameManager.color_of(Constants.FACTION_PLAYER)).capitalize()
		if not ResourceLoader.exists(ipath):
			ipath = WORKER_GROUP_FIGURE % "Blue"
	if ipath and ResourceLoader.exists(ipath):
		var tex := load(ipath) as Texture2D
		if tex != null:
			var fig: TextureRect = _stretched_icon(tex, 1.0)
			fig.name = "GroupFigure"
			fig.offset_right = -float(FILTER_NUM_W)
			btn.add_child(fig)
	else:
		btn.text = _squad_title(unit_id).get_slice(" ", 0)
		btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func(): _on_type_filter_pressed(unit_id))
	# Счётчик ОТРЯДОВ — в правой полосе кнопки, рядом с фигуркой
	var badge := _add_badge(btn)
	badge.name = "GroupCount"
	badge.visible = true
	badge.text = str(squads)
	badge.add_theme_font_size_override("font_size", 13)
	badge.offset_left = float(FILTER_SLOT_W - FILTER_NUM_W)
	badge.offset_right = -1
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vb.add_child(btn)

	btn.tooltip_text = "%s: %d отрядов, %d бойцов. Клик или Tab — отряды рода" % [
		_squad_title(unit_id), squads, men]
	if unit_id == WORKER_GROUP:
		btn.tooltip_text = "Рабочие: %d. Клик или Tab — панель построек" % men
	return vb

## Клик по сводному ярлыку: РАЗВЕРНУТЬ группу на нижней панели отдельными
## карточками отрядов. Повторный клик по тому же ярлыку сворачивает обратно.
##
## Выделение при этом НЕ трогается: игрок разглядывает состав, а не отдаёт
## приказ. Сузить выделение можно кликом по конкретной карточке отряда
## (см. _on_squad_card_pressed) — там это как раз и нужно, чтобы одним
## движением отправить в замок именно самый потрёпанный отряд
## Родительское (смешанное) выделение, из которого развёрнут род: полоса родов
## остаётся видна, Tab листает роды, повторный клик возвращает всю армию
var _parent_sids: Array = []

func _on_type_filter_pressed(unit_id: String) -> void:
	AudioManager.play_ui("menu_tab")
	_parent_init()
	# ПОВТОРНЫЙ КЛИК ПО ТОМУ ЖЕ РОДУ ЗАКРЫВАЕТ ДЕТАЛЬНУЮ ПАНЕЛЬ (ТЗ 10.10.2026)
	if _expanded_type == unit_id:
		_restore_parent_selection()
		return
	_expand_type_from_parent(unit_id)

## Tab: следующий род родительского набора (или первый)
func cycle_expanded_type() -> bool:
	_parent_init()
	var order: Array = []
	var gw: Array = _group_workers()
	for s in _parent_sids:
		var t: String = GameManager.squad_type(int(s))
		if t == WORKER_GROUP and not gw.is_empty():
			continue
		if t != "" and not order.has(t) and _squad_alive(int(s)):
			order.append(t)
	if not gw.is_empty():
		order.append(WORKER_GROUP)
	_sort_types(order)
	# Один род, несколько отрядов (ТЗ 30.10.2026): Tab раскрывает их
	# карточками, повторный Tab — сворачивает обратно
	if order.size() == 1 and _OptSys.army_count_badge and _parent_sids.size() >= 2 			and String(order[0]) != WORKER_GROUP:
		AudioManager.play_ui("menu_tab")
		if _expanded_type == String(order[0]):
			_restore_parent_selection()
		else:
			_expand_type_from_parent(String(order[0]))
		return true
	if order.size() < GROUP_BAR_MIN_TYPES:
		_parent_clear()
		return false
	AudioManager.play_ui("menu_tab")
	var i: int = order.find(_expanded_type)
	_expand_type_from_parent(String(order[(i + 1) % order.size()]))
	return true

## Есть ли у отряда живые (читатель, без роспуска — см. squad_members)
func _squad_alive(sid: int) -> bool:
	var sq: Variant = GameManager.squads.get(sid)
	if sq == null:
		return false
	for m in ((sq as Dictionary)["members"] as Array):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			return true
	return false

## Вернуть смешанное выделение целиком (детальная панель закрыта)
func _restore_parent_selection() -> void:
	var keep: Array = _parent_sids.duplicate()
	var keep_w: Array = _parent_workers.duplicate()
	_parent_clear()
	_expanded_type = ""
	var main := GameManager.main
	if main == null or main.selection_manager == null:
		return
	var sm: SelectionManager = main.selection_manager
	sm._clear_selection()
	for sid in keep:
		if not _squad_alive(int(sid)):
			continue
		for m in GameManager.squad_members(int(sid)):
			var u := m as Unit
			if u != null and is_instance_valid(u) and not u.is_dead():
				sm._select_one(u)
	for w in keep_w:
		if w != null and is_instance_valid(w) and not (w as Worker).is_dead():
			sm._select_one(w)
	GameManager.on_selection_changed(sm.selected_units)

func _expand_type_from_parent(unit_id: String) -> void:
	# ── ПОДВЫБОР: КЛИК ПО ИКОНКЕ РОДА СУЖАЕТ ВЫДЕЛЕНИЕ (ТЗ 24.09.2026, второе
	# письмо) ── «кликнул на Монаха — управление только им, армия стоит».
	# Разбор по карточкам остаётся: полоса отрядов этого рода разворачивается,
	# и кликом по карточке выделение сужается дальше, до одного отряда
	var main := GameManager.main
	if unit_id == WORKER_GROUP and main != null and main.selection_manager != null:
		var smw: SelectionManager = main.selection_manager
		var ws: Array = _group_workers()
		if not ws.is_empty():
			var par: Array = _parent_sids.duplicate()
			var parw: Array = _parent_workers.duplicate()
			smw._clear_selection()
			for w in ws:
				smw._select_one(w)
			_parent_sids = par
			_parent_workers = parw
			GameManager.on_selection_changed(smw.selected_units)
			_parent_sids = par
			_parent_workers = parw
		# Панель — обычная панель артели: детальной панели рода у рабочих нет
		_expanded_type = unit_id
		_rebuild_overbar(true)
		return
	if main != null and main.selection_manager != null:
		var sm: SelectionManager = main.selection_manager
		var keep: Array = []
		var src: Array = _parent_sids if not _parent_sids.is_empty() else _selected_squad_ids()
		for s in src:
			if GameManager.squad_type(int(s)) == unit_id and _squad_alive(int(s)):
				keep.append(int(s))
		if not keep.is_empty():
			var parent: Array = _parent_sids.duplicate()
			sm._clear_selection()
			for sid in keep:
				for m in GameManager.squad_members(int(sid)):
					var u := m as Unit
					if u != null and is_instance_valid(u) and not u.is_dead():
						sm._select_one(u)
			# show_selection сбрасывает разворот — родителя возвращаем
			_parent_sids = parent
			GameManager.on_selection_changed(sm.selected_units)
			_parent_sids = parent
	_expanded_type = unit_id
	_rebuild_overbar(true)
	# Панель перерисовывается целиком: уровень 2 — это не «добавить карточки к
	# тому, что было», а совсем другое содержимое (портрет типа, его численность,
	# его стойки). Полосу групп при этом НЕ трогаем: она и есть навигация между
	# уровнями, пересборка освободила бы кнопку прямо под пальцем игрока
	_refresh_panel()

# ─────────────────────────────────────────────────────────────────────────────
# КАРТОЧКИ ОТДЕЛЬНЫХ ОТРЯДОВ НА НИЖНЕЙ ПАНЕЛИ
#
# Под каждой иконкой — ПОСТОЯННАЯ красная шкала: доля от полного состава
# отряда. 50 из 50 бойцов — полная полоса, 25 из 50 — половина. Здоровье живых
# входит туда же, иначе отряд из целых, но израненных бойцов выглядел бы
# нетронутым.
# ─────────────────────────────────────────────────────────────────────────────
## Карточка отряда — единственный элемент, который панель НЕ ужимала вдвое
## вместе с остальным: она и есть содержание уровня 2, и в неё должны читаемо
## помещаться цифра состава, шкала здоровья и значок ранга
const SQUAD_CARD  := 34
const SQUAD_HP_H  := 4     # высота шкалы здоровья
const SQUAD_XP_H  := 2     # тонкая шкала опыта
const SQUAD_FLAG_H := 12.0 # флаг ветеранства над карточкой
## ── ФИКСИРОВАННАЯ СЕТКА КАРТОЧЕК (ТЗ 11.10.2026, второе письмо, п. 1) ──────
## Жалоба: «плашка раздувается на пол-экрана при выделении разных родов».
## Причин было две: (1) старые карточки снимались одним queue_free — до конца
## кадра они ещё числились детьми, и _sync_panel_height в том же вызове мерил
## их ВМЕСТЕ с новыми (смена рода / Tab: 5 копейщиков + 3 лучника = 8 карточек
## в сетке на 3 колонки — панель вырастала в три ряда); (2) колонок было по
## числу отрядов, до 19 — ширина плашки ехала за выделением. Теперь сетка
## всегда SQUAD_ROW_MAX колонок и ПОСТОЯННОЙ ширины (место под полный ряд
## зарезервировано), девятый отряд уходит во второй ряд
## ── РЕЗИНОВАЯ СЕТКА (ТЗ 12.10.2026, второе письмо) ─────────────────────────
## До SQUAD_ROW_MAX карточек в ряд, дальше — следующий ряд (30 отрядов — три
## ряда по десять). Ширина сетки — по ЧИСЛУ карточек в ряду, а не постоянная:
## у одного отряда плашка узкая, у тридцати — по ряду в десять, без пустых дыр
const SQUAD_ROW_MAX := 10
const SQUAD_STRIP_W := SQUAD_ROW_MAX * SQUAD_CARD + (SQUAD_ROW_MAX - 1) * 3
## Ширина плашки развёрнутого рода: рамка и отступы + портрет + сетка
## карточек + две кнопки приёмов + ряд A/C/S/F1 и зазоры ряда
const DETAIL_PANEL_W := 2.0 * (PANEL_PAD_X + PANEL_BORDER_W) + PORTRAIT_W + SQUAD_STRIP_W \
	+ 2.0 * BTN_SIZE + BTN_GAP + 4.0 * SCMD_BTN + 3.0 * SCMD_GAP + 4.0 * PANEL_HBOX_SEP

func _rebuild_squad_strip() -> void:
	if _squad_strip == null or not is_instance_valid(_squad_strip):
		return
	for c in _squad_strip.get_children():
		_squad_strip.remove_child(c)
		c.queue_free()
	_squad_strip.custom_minimum_size = Vector2.ZERO
	if _expanded_type == "":
		return
	var src: Array = _parent_sids if not _parent_sids.is_empty() else _selected_squad_ids()
	var n := 0
	for s in src:
		var sid: int = int(s)
		if GameManager.squad_type(sid) != _expanded_type or not _squad_alive(sid):
			continue
		_squad_strip.add_child(_squad_card(sid))
		n += 1
	var cols: int = clampi(n, 1, SQUAD_ROW_MAX)
	_squad_strip.custom_minimum_size = Vector2(float(cols * SQUAD_CARD + (cols - 1) * 3), 0.0)
	if _squad_strip is GridContainer:
		(_squad_strip as GridContainer).columns = cols

## Доля «живучести» отряда: сколько от полного состава он сейчас стоит.
## Считается по СУММЕ здоровья живых, делённой на здоровье полного отряда, —
## одна цифра честно закрывает и потери, и раны
func _squad_strength(sid: int) -> float:
	var members := GameManager.squad_members(sid)
	if members.is_empty():
		return 0.0
	var full: int = maxi(_UCfg.squad_size(GameManager.squad_type(sid)), members.size())
	var hp := 0.0
	var hp_max := 0.0
	for m in members:
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		hp     += u.current_health
		hp_max  = maxf(hp_max, u.max_health)
	if hp_max <= 0.0:
		return 0.0
	return clampf(hp / (hp_max * float(full)), 0.0, 1.0)

func _squad_card(sid: int) -> Control:
	var vb := VBoxContainer.new()
	vb.name = "SquadCard%d" % sid
	vb.custom_minimum_size = Vector2(SQUAD_CARD, 0)
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_vertical = Control.SIZE_SHRINK_END
	# ФЛАГ ВЕТЕРАНСТВА — СВЕРХУ (ТЗ 10.10.2026, блок 4): флаг → HP → опыт →
	# число. У новобранцев — пустое место той же высоты, ряд не прыгает
	# ── ФЛАГА НАД КАРТОЧКОЙ БОЛЬШЕ НЕТ (ТЗ 12.10.2026, второе письмо) ───────
	# Знамя стало римским штандартом — узкий высокий флаг в строке 12 px
	# читался черточкой, а пустая полоса той же высоты у новобранцев раздвигала
	# ряды сетки. Ранг — «★N» в углу карточки (ниже), как цифра на штандарте

	var uid: String = GameManager.squad_type(sid)
	var alive: int  = GameManager.squad_members(sid).size()
	var frac: float = _squad_strength(sid)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(SQUAD_CARD, SQUAD_CARD)
	btn.clip_contents = true
	var col := Color(0.16, 0.20, 0.30)
	var sn := StyleBoxFlat.new(); sn.bg_color = col.darkened(0.2)
	_borders(sn, 2); _corners(sn, 4); sn.border_color = col.lightened(0.35)
	var sh := StyleBoxFlat.new(); sh.bg_color = col.lightened(0.18)
	_borders(sh, 2); _corners(sh, 4); sh.border_color = Color(0.95, 0.88, 0.55)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover",  sh)
	btn.add_theme_stylebox_override("pressed", sn)
	btn.tooltip_text = "%s — %d бойцов (%d%%). Клик — выделить только этот отряд" \
		% [_squad_title_ranked(uid, GameManager.squad_level(sid)), alive,
			int(round(frac * 100.0))]
	var ipath: String = unit_figure_path(uid, Constants.FACTION_PLAYER)
	if ipath and ResourceLoader.exists(ipath):
		var tex := load(ipath) as Texture2D
		if tex != null:
			btn.add_child(_stretched_icon(tex, 3.0))
	else:
		btn.text = _squad_title(uid).get_slice(" ", 0)
		btn.add_theme_font_size_override("font_size", 10)
	var badge := _add_badge(btn)
	badge.name = "CountBadge"
	badge.visible = true
	badge.text = str(alive)
	badge.add_theme_font_size_override("font_size", 13)

	# ЗНАЧОК ВЕТЕРАНСТВА ОТРЯДА — в ВЕРХНЕМ ЛЕВОМ углу карточки, чтобы не
	# столкнуться с цифрой состава в нижнем правом. Лычки и цвет берутся из той
	# же таблицы, по которой нарисовано знамя над отрядом
	var lvl: int = GameManager.squad_level(sid)
	if lvl > 0:
		var rank := Label.new()
		rank.name = "SquadRank"
		rank.text = "★%d" % lvl
		rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rank.add_theme_font_size_override("font_size", 10)
		rank.add_theme_color_override("font_color", Color(0.96, 0.36, 0.32))
		rank.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		rank.add_theme_constant_override("outline_size", 4)
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rank.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
		rank.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rank.offset_left = 2.0
		rank.offset_top  = 1.0
		btn.add_child(rank)

	btn.pressed.connect(func(): _on_squad_card_pressed(sid))
	vb.add_child(btn)

	# ШКАЛА. Не ProgressBar: нужен ровно один тонкий прямоугольник заданной
	# доли, без темы, отступов и «мигания» на минимальных размерах
	var bar_bg := PanelContainer.new()
	bar_bg.custom_minimum_size = Vector2(SQUAD_CARD, SQUAD_HP_H)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.18, 0.05, 0.05); _corners(bg, 2)
	bar_bg.add_theme_stylebox_override("panel", bg)
	var fill := ColorRect.new()
	fill.name = "HpFill"
	fill.color = Color(0.86, 0.16, 0.14)
	fill.custom_minimum_size = Vector2(maxf(SQUAD_CARD * frac, 1.0), SQUAD_HP_H)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(fill)
	vb.add_child(bar_bg)
	# ТОНКАЯ ШКАЛА ОПЫТА до следующего ранга (та же формула, что у панели)
	var xp: Dictionary = _xp_progress(uid, GameManager.squad_kills(sid))
	var xfrac: float = 1.0
	if int(xp.get("need", 0)) > 0:
		xfrac = clampf(float(xp.get("have", 0)) / float(xp["need"]), 0.0, 1.0)
	var xbg := PanelContainer.new()
	xbg.name = "XpBar"
	xbg.custom_minimum_size = Vector2(SQUAD_CARD, SQUAD_XP_H)
	var xs := StyleBoxFlat.new()
	xs.bg_color = Color(0.16, 0.13, 0.04)
	xbg.add_theme_stylebox_override("panel", xs)
	var xfill := ColorRect.new()
	xfill.color = XP_BAR_COLOR
	xfill.custom_minimum_size = Vector2(maxf(SQUAD_CARD * xfrac, 1.0), SQUAD_XP_H)
	xfill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	xfill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xbg.add_child(xfill)
	vb.add_child(xbg)
	return vb

## Клик по карточке: в выделении остаётся ТОЛЬКО этот отряд — чтобы одним
## следующим нажатием отправить именно его, например, в замок на лечение
func _on_squad_card_pressed(sid: int) -> void:
	var main := GameManager.main
	if main == null or main.selection_manager == null:
		return
	var sm: SelectionManager = main.selection_manager
	sm._clear_selection()
	for m in GameManager.squad_members(sid):
		var u := m as Unit
		if u != null and is_instance_valid(u) and not u.is_dead():
			sm._select_one(u)
	GameManager.on_selection_changed(sm.selected_units)

# ─────────────────────────────────────────────────────────────────────────────
# ГАРНИЗОН ЗАМКА
# Полоса слотов НАД нижней панелью: по слоту на каждый отряд внутри.
# Отдельная плавающая полоса, а не колонка панели: пять слотов по 56 px в
# сетку кнопок не влезают, а второй ряд вылез бы за край панели.
# Клик по слоту выпускает отряд наружу.
# ─────────────────────────────────────────────────────────────────────────────
const GARRISON_SLOT := 56

## ── ТЗ 20.09.2026 (п. 6.2): ГАРНИЗОН — СЕКЦИЯ ПАНЕЛИ, А НЕ ПЛАШКА НАД НЕЙ ──
## Прежняя полоса висела ОТДЕЛЬНЫМ узлом над нижней панелью, привязанным к её
## верхней кромке: панель считает высоту по содержимому и переставляется при
## каждой пересборке, а полоса пересобиралась своим тактом — на экране это
## читалось как «большая дёргающаяся плашка» (скриншот 7). Теперь слоты живут
## В САМОЙ ПАНЕЛИ, последней колонкой ряда кнопок (то есть справа, за монахом):
## подпись «Гарнизон» и до GARRISON_MINI_SLOTS маленьких иконок. Сетка панели
## двигает её вместе со всем остальным — дёргаться нечему.
const GARRISON_MINI := 22          # сторона мелкого слота, px
const GARRISON_MINI_SLOTS := 8     # сколько слотов показываем (ТЗ 29.09.2026: 8)
const GARRISON_MINI_COLS := 4      # два ряда: 4 + 4 — колонка не шире кнопки

var _garrison_strip: Control = null

func _hide_garrison() -> void:
	if _garrison_strip != null and is_instance_valid(_garrison_strip):
		if _garrison_strip.get_parent() != null:
			_garrison_strip.get_parent().remove_child(_garrison_strip)
		_garrison_strip.queue_free()
	_garrison_strip = null

## Компактная секция в ряду кнопок здания. Зовётся из веток панели ДО кнопок
## найма, а вправо её переставляет _sync_panel_grid_widths: порядок веток
## разный (у башни кнопка «Выпустить» идёт после, у замка — три найма), и
## держать вызов последним в каждой значило бы чинить это в трёх местах
func _show_garrison(castle: Castle) -> void:
	_hide_garrison()
	if castle == null or not is_instance_valid(castle):
		return
	# Укрытые рабочие (ТЗ 21.10.2026) — мини-слот этой же секции, только у
	# своей столицы (у башни и бараков убежища нет)
	var shelter: bool = castle.is_stronghold() and castle.faction == Constants.FACTION_PLAYER 		and _shelter_total(castle) > 0
	if castle.garrison.is_empty() and castle._incoming.is_empty() and not shelter:
		return
	if button_container == null or not is_instance_valid(button_container):
		return
	var col := VBoxContainer.new()
	col.name = "GarrisonSection"
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cap := Label.new()
	cap.name = "GarrisonCaption"
	cap.text = "Гарнизон"
	cap.add_theme_font_size_override("font_size", 11)
	cap.add_theme_color_override("font_color", Color(0.78, 0.84, 0.68))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cap)
	var grid := GridContainer.new()
	grid.name = "GarrisonSlots"
	grid.columns = GARRISON_MINI_COLS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	col.add_child(grid)
	var shown: int = 0
	var extra: int = 0
	if shelter:
		grid.add_child(_shelter_mini(castle))
		shown += 1
	for g in castle.garrison:
		var rec: Dictionary = g
		if shown < GARRISON_MINI_SLOTS:
			grid.add_child(_garrison_mini(castle, int(rec["sid"]), String(rec["type"]), true))
			shown += 1
		else:
			extra += 1
	for s in castle._incoming:
		var sid: int = s
		if shown < GARRISON_MINI_SLOTS:
			grid.add_child(_garrison_mini(castle, sid, GameManager.squad_type(sid), false))
			shown += 1
		else:
			extra += 1
	# Пустые места ряда рисуются тускло: восемь слотов, а не «сколько есть», —
	# игрок видит и занятость, и вместимость одним взглядом
	var free_n: int = mini(GARRISON_MINI_SLOTS, castle.garrison_limit()) - shown + (1 if shelter else 0)
	for i in range(maxi(free_n, 0)):
		grid.add_child(_garrison_mini_empty())
	if extra > 0:
		var more := Label.new()
		more.text = "+%d" % extra
		more.add_theme_font_size_override("font_size", 10)
		more.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(more)
	button_container.add_child(col)
	_garrison_strip = col

## Пустое место гарнизона: рамка без иконки и без клика
func _garrison_mini_empty() -> Control:
	var r := PanelContainer.new()
	r.custom_minimum_size = Vector2(GARRISON_MINI, GARRISON_MINI)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.12, 0.14, 0.55)
	_borders(st, 1); _corners(st, 3)
	st.border_color = Color(0.30, 0.34, 0.30, 0.8)
	r.add_theme_stylebox_override("panel", st)
	return r

## Мелкий слот: иконка рода войск, клик выпускает отряд, подсказка — состав
func _garrison_mini(castle: Castle, squad_id: int, unit_type: String, inside: bool) -> Control:
	var btn := QuietTooltipButton.new()
	btn.name = "GarrisonSlot_%d" % squad_id
	btn.custom_minimum_size = Vector2(GARRISON_MINI, GARRISON_MINI)
	btn.clip_contents = true
	btn.text = ""
	var col: Color = Color(0.16, 0.26, 0.18) if inside else Color(0.24, 0.22, 0.12)
	var sn := StyleBoxFlat.new(); sn.bg_color = col.darkened(0.2)
	_borders(sn, 1); _corners(sn, 3)
	sn.border_color = col.lightened(0.3)
	var sh := StyleBoxFlat.new(); sh.bg_color = col.lightened(0.15)
	_borders(sh, 1); _corners(sh, 3)
	sh.border_color = Color(0.95, 0.88, 0.55)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover",  sh)
	btn.add_theme_stylebox_override("pressed", sn)
	var ipath: String = String(UNIT_ICONS.get(unit_type, ""))
	if ipath and ResourceLoader.exists(ipath):
		var tex := load(ipath) as Texture2D
		if tex != null:
			btn.add_child(_stretched_icon(tex, 1.0))
	var have: int = GameManager.squad_members(squad_id).size()
	var want: int = _UCfg.squad_size(unit_type)
	btn.tooltip_text = ("%d/%d" % [have, want]) if inside else "идёт…"
	if inside:
		btn.pressed.connect(func(): _on_garrison_release(castle, squad_id))
		btn.mouse_entered.connect(func(): _show_card(btn,
			{"title": "Гарнизон: %d/%d" % [have, want],
			 "lines": ["Клик — выпустить отряд наружу"]}))
		btn.mouse_exited.connect(_hide_card)
		btn.tree_exiting.connect(_hide_card)
	return btn

## Прежняя плавающая полоса (56 px, над панелью). Не зовётся: заменена
## секцией выше. Оставлена целиком — механизм рабочий, и если крупные слоты
## понадобятся снова, возвращать их не придётся писать заново
func _show_garrison_strip_legacy(castle: Castle) -> void:
	_hide_garrison()
	if castle == null or not is_instance_valid(castle):
		return
	if castle.garrison.is_empty() and castle._incoming.is_empty():
		return

	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.07, 0.11, 0.92)
	_borders(st); _corners(st, 6)
	st.border_color = Color(0.42, 0.50, 0.30)
	st.content_margin_left = 8; st.content_margin_right = 8
	st.content_margin_top  = 6; st.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", st)
	panel.anchor_left = 0.0; panel.anchor_right = 0.0
	panel.anchor_top  = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left   = PANEL_LEFT
	panel.offset_right  = PANEL_LEFT + float(castle.garrison_limit()) * (GARRISON_SLOT + 8) + 16
	panel.offset_bottom = PANEL_TOP - 6
	panel.offset_top    = PANEL_TOP - 6 - (GARRISON_SLOT + 34)
	add_child(panel)
	_garrison_strip = panel

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	for g in castle.garrison:
		var rec: Dictionary = g
		row.add_child(_garrison_slot(castle, int(rec["sid"]), String(rec["type"]), true))
	for s in castle._incoming:
		var sid: int = s
		row.add_child(_garrison_slot(castle, sid, GameManager.squad_type(sid), false))

## Один слот: иконка типа, счётчик состава и кнопка «выпустить»
func _garrison_slot(castle: Castle, squad_id: int, unit_type: String, inside: bool) -> Control:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(GARRISON_SLOT, 0)
	vb.add_theme_constant_override("separation", 2)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(GARRISON_SLOT, GARRISON_SLOT)
	btn.clip_contents = true
	btn.text = ""
	var col: Color = Color(0.16, 0.26, 0.18) if inside else Color(0.24, 0.22, 0.12)
	var sn := StyleBoxFlat.new(); sn.bg_color = col.darkened(0.2)
	_borders(sn, 2); _corners(sn, 4)
	sn.border_color = col.lightened(0.3)
	var sh := StyleBoxFlat.new(); sh.bg_color = col.lightened(0.15)
	_borders(sh, 2); _corners(sh, 4)
	sh.border_color = Color(0.95, 0.88, 0.55)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover",  sh)
	btn.add_theme_stylebox_override("pressed", sn)
	var ipath: String = String(UNIT_ICONS.get(unit_type, ""))
	if ipath and ResourceLoader.exists(ipath):
		var tex := load(ipath) as Texture2D
		if tex != null:
			btn.add_child(_stretched_icon(tex, 3.0))
	if inside:
		btn.pressed.connect(func(): _on_garrison_release(castle, squad_id))
	vb.add_child(btn)

	var have: int = GameManager.squad_members(squad_id).size()
	var want: int = _UCfg.squad_size(unit_type)
	var lbl := Label.new()
	lbl.text = ("%d/%d" % [have, want]) if inside else "идёт…"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color",
		Color(0.75, 0.95, 0.75) if have >= want else Color(0.95, 0.85, 0.55))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fix_label(lbl, GARRISON_SLOT, 1)
	vb.add_child(lbl)
	return vb

func _on_garrison_release(castle: Castle, squad_id: int) -> void:
	if castle == null or not is_instance_valid(castle):
		return
	castle.release_garrison(squad_id)
	show_selection([castle])

## Кнопка «Выпустить» в панели башни
func _on_tower_release(tower: Castle) -> void:
	if tower == null or not is_instance_valid(tower):
		return
	if tower.has_method("release_all"):
		tower.call("release_all")
	show_selection([tower])

## Строка панели башни: обзор и кто внутри
func _tower_info_text(tower: Castle) -> String:
	var s: String = "Обзор %d м" % int(round(tower.vision_radius()))
	var sid: int = 0
	if tower.has_method("garrison_squad_id"):
		sid = int(tower.call("garrison_squad_id"))
	if sid > 0:
		var t: String = GameManager.squad_type(sid)
		var have: int = GameManager.squad_members(sid).size()
		var want: int = _UCfg.squad_size(t)
		s += "\nВнутри: %s %d/%d" % [_squad_title(t), have, want]
	elif not tower._incoming.is_empty():
		s += "\nЛучники идут к воротам"
	else:
		s += "\nПусто — ПКМ лучниками"
	return s

## Строка панели дома: слоты лимита и еда (заказ 09.09.2026)
## Подпись загона для овец: запас жизни и вместимость стада
func _pen_info_text(p: Building) -> String:
	# ── КОМПАКТНО (ТЗ 14.10.2026, п. 2): название сверху, рабочие — иконкой
	# с «N / M» (кнопка в ряду, _pen_workers_btn), ниже — один зелёный итог
	# прироста еды. «Пастбище», «Вместимость», «Мясо с рабочего», «Выработка»
	# сняты: итог уже включает и число фермеров, и кузницу
	# ── ТЗ 24.10.2026 (второе письмо, блок 3): без «400/400 HP» и «еды в
	# минуту» — заголовок «Загон для овец (1/3)» (построено из лимита) и итог
	# «Еда +132» с иконкой мяса (_detail_icon, ставит _split_info_detail)
	var built: int = GameManager.sheep_pen_total(int(p.faction))
	var out: String = "%s (%d/%d)" % [p.display_name, built, int(_UCfg.SHEEP_PEN_MAX_COUNT)]
	var w: int = int(p.call("workers_here")) if p.has_method("workers_here") else 0
	var per_min: float = Worker.farmer_meat_per_sec(int(p.faction)) * 60.0
	out += "\nЕда +%d" % int(round(per_min * float(w)))
	_detail_icon_path = FOOD_ICON_PATH
	return out

## Иконка с подписью-счётчиком «N / M» в правом нижнем углу (рабочие загона,
## рудника). Одна функция на обе панели — подпись у них одна
func _count_icon_btn(icon: String, count_text: String, card: Dictionary, cb: Callable) -> Button:
	# Кнопка крупнее обычной: под ней подпись «N/M», в 29 px она не влезала
	var b: Button = _cmd(String(card.get("title", "")), Color(0.18, 0.32, 0.18), cb, icon, card,
		COUNT_BTN_SIZE, 1.0)
	if b == null:
		return null
	var wl := Label.new()
	wl.name = "CountLabel"
	wl.text = count_text
	wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wl.add_theme_font_size_override("font_size", 12)
	wl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.80))
	wl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	wl.add_theme_constant_override("outline_size", 5)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	wl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wl.offset_right = -3
	wl.offset_bottom = -1
	b.add_child(wl)
	return b

const COUNT_BTN_SIZE := 46.0

## Выделить фермеров загона (клик по иконке рабочих в панели загона)
func _select_pen_farmers(p: Building) -> void:
	if p == null or not is_instance_valid(p):
		return
	var men: Array = []
	for w in get_tree().get_nodes_in_group(Constants.unit_group(p.faction)):
		if w != null and is_instance_valid(w) and w is Worker and (w as Worker).farm_pen() == p:
			men.append(w)
	var sm = GameManager.main.selection_manager if GameManager.main != null else null
	if sm != null and not men.is_empty():
		sm.select_units(men)
		AudioManager.play_ui("menu_button")

## Строка подробностей ЗЕЛЁНАЯ — итог прироста (загон, рудник)
var _detail_gain: bool = false

var _detail_label: Label = null

## Первая строка info_label — название, остальное — в _detail_label
func _split_info_detail() -> void:
	if _detail_label == null or not is_instance_valid(_detail_label):
		return
	var t: String = info_label.text
	var nl: int = t.find("\n")
	if nl < 0:
		_detail_label.text = ""
		_detail_label.visible = false
		return
	info_label.text = t.substr(0, nl)
	_detail_label.text = t.substr(nl + 1)
	_detail_label.visible = true
	_detail_label.add_theme_color_override("font_color",
		Color(0.45, 0.92, 0.40) if _detail_gain else Color(0.86, 0.84, 0.76))
	_detail_label.add_theme_font_size_override("font_size", 12 if _detail_gain else 10)
	_place_detail_icon()

## ── ИКОНКА РЕСУРСА ПОСЛЕ СТРОКИ ПОДРОБНОСТЕЙ (ТЗ 24.10.2026, блок 3) ───────
## «Еда +132 [мясо]»: TextureRect дочерним узлом строки, сразу за текстом.
## Путь ставит тот, кто собирает текст (_pen_info_text), и сбрасывает
## _refresh_panel вместе с _detail_gain
const FOOD_ICON_PATH := "res://assets/factions/humans/icons/hud/Meat.png"
var _detail_icon_path: String = ""
var _detail_icon: TextureRect = null

func _place_detail_icon() -> void:
	if _detail_label == null or not is_instance_valid(_detail_label):
		return
	if _detail_icon == null or not is_instance_valid(_detail_icon):
		_detail_icon = TextureRect.new()
		_detail_icon.name = "DetailIcon"
		_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail_label.add_child(_detail_icon)
	var on: bool = _detail_icon_path != "" and _detail_label.visible \
		and ResourceLoader.exists(_detail_icon_path)
	_detail_icon.visible = on
	if not on:
		return
	_detail_icon.texture = load(_detail_icon_path)
	var fs: int = _detail_label.get_theme_font_size("font_size")
	var font: Font = _detail_label.get_theme_font("font")
	var line: String = _detail_label.text.get_slice("\n", 0)
	var tw: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var isz: float = float(fs) + 4.0
	_detail_icon.size = Vector2(isz, isz)
	_detail_icon.position = Vector2(tw + 4.0, (float(fs) * 1.35 - isz) * 0.5)

## Иконка строки подробностей видна (стенды)
func detail_icon_shown() -> bool:
	return _detail_icon != null and is_instance_valid(_detail_icon) and _detail_icon.visible

## Текст подробностей (стенды)
func detail_text() -> String:
	return _detail_label.text if _detail_label != null and is_instance_valid(_detail_label) and _detail_label.visible else ""

## Вывести рабочих из рудника (кнопка «5/5» мини-панели рудника)
func _on_mine_release(mn: Object) -> void:
	if mn == null or not is_instance_valid(mn) or not (mn is Mine):
		return
	if (mn as Mine).release_all():
		AudioManager.play_ui("menu_button")
	_refresh_panel()

func _house_info_text(h: Building) -> String:
	var s: String = "%s  %d/%d HP" % [h.display_name, int(h.current_health), int(h.max_health)]
	s += "\n+%d рабочих · +%d мест в армии" % [_UCfg.HOUSE_WORKER_SLOTS, _UCfg.ARMY_HOUSE_UNITS]
	s += "\n+%d еды каждые %d c" % [int(_UCfg.HOUSE_FOOD_INCOME), int(_UCfg.HOUSE_FOOD_INTERVAL)]
	return s

# ─────────────────────────────────────────────────────────────────────────────
# ВЕТЕРАНСТВО ОТРЯДА
# Пороги и шаблоны улучшений — в unit_stats_config.gd; здесь только показ.
# ─────────────────────────────────────────────────────────────────────────────

## Полоска здоровья и строка характеристик выделенного отряда.
## Прирост от ветеранства показывается ЧЕРЕЗ ПЛЮС: «Атака: 20 (+5)»
func _show_squad_stats(squad_id: int, units: Array) -> void:
	var sample: Unit = null
	for u in units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		sample = u
		break
	if sample == null or progress_label == null:
		return

	var uid: String = sample.stat_id
	var f: int = sample.faction
	# База из конфига + постоянные бонусы кузницы, отдельно — ветеранский прирост
	var atk_base: float = sample.attack_damage \
		+ GameManager.unit_bonus(f, uid, "bonus_attack") \
		+ GameManager.get_upgrade(f, "damage")
	var def_base: float = sample.defense + sample.armor \
		+ GameManager.unit_bonus(f, uid, "bonus_armor") \
		+ GameManager.get_upgrade(f, "defense")
	var spd_base: float = sample.move_speed \
		+ GameManager.unit_bonus(f, uid, "bonus_speed")

	var parts: Array = []
	parts.append(_plus("Атака", atk_base, sample.vet_attack))
	parts.append(_plus("Защита", def_base, sample.vet_armor + sample.vet_defense))
	parts.append(_plus("Скорость", spd_base, sample.vet_speed, 1))
	var kills: int = GameManager.squad_kills(squad_id)
	var lvl: int   = GameManager.squad_level(squad_id)
	var next_at: int = _UCfg.veteran_threshold(uid, lvl + 1)
	var tail: String = "убийств: %d" % kills
	if next_at > 0:
		tail += " / %d" % next_at
	parts.append(tail)
	progress_label.text = "  ".join(parts)

# ─────────────────────────────────────────────────────────────────────────────
# ПАНЕЛЬ СТАТОВ ОТРЯДА С РАЗБОРОМ БОНУСОВ
#
# Строка info-колонки (232 px) физически не вмещает пять статов с расшифровкой
# откуда взялся прирост, поэтому панель плавающая — как полоса гарнизона и
# фильтр типов. Показывается при выделении ОДНОГО отряда, поэтому с фильтром
# типов (он живёт при двух и более типах) на экране не пересекается.
#
# Формат строки: «Урон: 12 (+3 Кузница, +5 Опыт)» — прирост зелёным.
# Источники разделены сознательно: по панели видно, что дал апгрейд кузницы,
# а что — заслуженный ранг отряда.
# ─────────────────────────────────────────────────────────────────────────────
## ── ПАНЕЛЬ СТАТОВ УМЕНЬШЕНА (заказ владельца: «огромная плашка нечитабельна»)
## Ширина 320 → 268, кегль 12 → 11. Меньше нельзя: подпись «Интервал атаки»
## самая длинная в таблице, и на 250 она уже переносится на вторую строку, от
## чего панель растёт в высоту — то есть «уменьшение» оборачивается ростом
## ТЗ 18.09.2026, п. 6: подпись стала «Кулдаун», и 268 больше не нужно —
## таблица ужата до 232, отступы плашки 10/6 → 6/3, шаг строк 1 → 0
const STAT_PANEL_W := 232
## ── КОМПАКТНАЯ ТАБЛИЦА (ТЗ-B 19.09.2026, п. 3) ────────────────────────────
## Таблица больше НЕ тянется до ширины нижней панели (_panel_w): на экране
## она выходила во всю ширину плашки отряда с полосками по 350 px. Своя
## ширина, полоски фиксированной длины BAR_W, стоит НАД нижней панелью у
## её левого края — меньше самой панели отряда
const STAT_COMPACT_W := 250
## Кегль строк таблицы статов
const STAT_FONT_PX := 11
## Сторона значка стата. Выведена из кегля: значок вровень со строчными
const STAT_ICON_PX := 13
## Ширина правой колонки — той, где итог. Фиксирована намеренно: по ней и
## выравниваются числа всех строк по правому краю
const STAT_TOTAL_W := 46

## ── ЗНАЧКИ СТАТОВ ─────────────────────────────────────────────────────────
## Заказ владельца: сердечко — здоровье, меч — атака, щит — броня и защита,
## часы — интервал атаки. Часов в наборе кузницы нет вовсе, поэтому интервалу
## достался «сломанный меч» — единственный значок, читающийся как «удар, но
## хуже». Стату без своего значка строка достаётся без картинки, и это не
## ошибка: значков четыре, а строк в таблице до девяти
const STAT_ICONS := {
	"health": "icon_heart.png",
	"attack": "icon_sword.png",
	"armor": "icon_shield.png",
	"defense": "icon_shield.png",
	"cooldown": "icon_broken_sword.png",
	"range": "icon_bow.png",
}

## ── ОТМЕТКА ИДУЩЕГО СПЕЦПРИЁМА В ПОДПИСИ ОТРЯДА ───────────────────────────
## Пусто, если приём не идёт. Спрашивается СВОЙСТВО у самих бойцов
## (Warrior.rage_active / Spearman.phalanx_push_active), а не отдельная запись
## в реестре отрядов: второй источник правды о том, идёт ли приём, неминуемо
## разошёлся бы с первым. Достаточно ОДНОГО бойца в приёме — приказ раздаётся
## всему отряду сразу, а погибшие в первые секунды не должны гасить значок
const ABILITY_MARK_SHIELD := "  ⛨"
const ABILITY_MARK_SPEARS := "  ⚔"

func _squad_ability_mark(units: Array) -> String:
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		if u.has_method("rage_active") and bool(u.call("rage_active")):
			return ABILITY_MARK_SHIELD
		if u.has_method("phalanx_push_active") and bool(u.call("phalanx_push_active")):
			return ABILITY_MARK_SPEARS
	return ""

func _stat_icon(key: String) -> Texture2D:
	var nm: String = String(STAT_ICONS.get(key, ""))
	if nm.is_empty():
		return null
	return _icon_texture(nm)

## ── ПОДПИСИ СТРОК ТАБЛИЦЫ: ОДНО МЕСТО НА ВЕСЬ ИНТЕРФЕЙС ────────────────────
## Заказ владельца: «привести названия характеристик к человекочитаемым и
## одинаковым везде». Ключи — те же, что выдаёт modifier_stat_name, поэтому
## строка таблицы, подпись в плашке награды (MOD_SHORT_LABELS) и предпросмотр
## говорят об одном и том же одними словами. Здесь, а не в конфиге: конфиг
## отвечает за ЧИСЛО, интерфейс — за то, как это число НАЗВАТЬ
const STAT_ROW_LABELS := {
	"health": "Health", "attack": "Attack", "defense": "Defense",
	"armor": "Armor", "speed": "Speed", "push": "Push",
	# ── «ИНТЕРВАЛ АТАКИ», И ЭТО ТРЕТЬЕ ИМЯ ОДНОГО И ТОГО ЖЕ ЧИСЛА ──────────
	# В строке стоит ПАУЗА МЕЖДУ УДАРАМИ в секундах, и награда её УМЕНЬШАЕТ.
	# История подписи: «Rate» владелец справедливо назвал непонятным (это не
	# темп и не перезарядка); «Attack speed» не лучше — число рядом с ним
	# падает, и подпись начинает противоречить числу; «Attack delay» падало
	# вместе с числом, но не сообщало, что это ИНТЕРВАЛ, а не задержка замаха —
	# владелец так и спросил, «за что отвечает параметр».
	#
	# «Интервал атаки» отвечает на этот вопрос прямо и падает вместе с числом.
	# ПО-РУССКИ намеренно: карточка статов набрана по-английски, но панель под
	# ней («Отряд опытных копейщиков», «Ранг 1 → 2») и вся остальная игра — по-
	# русски, так что чужеродна здесь как раз английская строка
	# ── «КУЛДАУН» (ТЗ 18.09.2026, п. 6) → «Cooldown» (ТЗ 24.10.2026, блок 7):
	# карточка набрана по-английски, русская строка в ней выбивалась
	"range": "Range", "cooldown": "Cooldown", "morale": "Morale",
	"spread": "Accuracy", "carry": "Carry", "gather": "Gathering",
	"build": "Build",
}

## Выше этой дальности боец считается СТРЕЛКОМ, и строка «Range» ему нужна.
## У пехоты attack_range — это длина руки (2-3 м), и сообщать её незачем
const MELEE_RANGE_MAX := 5.0

## Зелёный прирост / жёлтый итог
const BONUS_COLOR := "#7ee07e"
const TOTAL_COLOR := "#ffe45a"

var _stat_panel: Control = null

## ── ОДНА ШИРИНА НА ВЕСЬ ЛЕВЫЙ СТОЛБЕЦ ──────────────────────────────────────
## Жалоба владельца по скриншоту: «карточка статов сверху и плашка отряда снизу
## обязаны быть ОДНОЙ ширины, а у нижней правый край ещё и вылезает».
## Так и было: у карточки ширина стояла числом (STAT_PANEL_W), а нижняя панель
## считала свою ПО СОДЕРЖИМОМУ — и содержимое почти всегда шире карточки.
##
## Правило теперь одно: ширина = максимум из «сколько нужно содержимому нижней
## панели» и STAT_PANEL_W, и это число получают ОБЕ панели. Одно на двоих —
## значит разъехаться они не могут по построению, как и левая ось (PANEL_LEFT).
## Держится ПОЛЕМ, а не пересчётом на месте: карточка строится РАНЬШЕ, чем
## нижняя панель узнаёт свою ширину (см. _sync_panel_height), и добирает её
## после — тем же приёмом, каким добирает PANEL_TOP
var _panel_w: float = float(STAT_PANEL_W)

## Выдать общую ширину карточке статов. Зовётся из _sync_panel_height, то есть
## после того, как нижняя панель посчитала своё содержимое
func _apply_left_column_width() -> void:
	var c := _stat_panel
	if c == null or not is_instance_valid(c):
		return
	# Таблица компактная (STAT_COMPACT_W), к ширине нижней панели больше не
	# привязана — только к её левому краю (ТЗ-B 19.09.2026, п. 3)
	c.custom_minimum_size = Vector2(STAT_COMPACT_W, c.custom_minimum_size.y)
	c.offset_left  = PANEL_LEFT
	c.offset_right = PANEL_LEFT + STAT_COMPACT_W

## ── РЕЕСТР СТРОК ТАБЛИЦЫ: КЛЮЧ СТАТА → САМА СТРОКА ─────────────────────────
## Нужен ровно для одного — ПРЕДПРОСМОТРА БУДУЩЕЙ НАГРАДЫ (см. _preview_stats):
## навёл курсор на иконку выбора — в строках дописались зелёные прибавки, увёл —
## строки вернулись к исходному тексту. Держим и готовый текст: восстанавливать
## его пересборкой всей панели значило бы моргать таблицей на каждом движении
## мыши вдоль ряда наград.
##
## Ключи те же, что у модификаторов после modifier_stat_name ("attack",
## "armor", ...), — тогда предпросмотр находит свою строку прямым поиском, без
## второй таблицы соответствий
var _stat_rows: Dictionary = {}      # ключ стата -> RichTextLabel
var _stat_base: Dictionary = {}      # ключ стата -> текст без предпросмотра
var _stat_names: Dictionary = {}     # ключ стата -> подпись строки (подсветка)
var _stat_nums: Dictionary = {}      # ключ стата -> [база, кузница, опыт]
var _stat_pulse: Array = []          # твины подсветки растущих строк
## Стенды: сколько строк подсвечено последним предпросмотром
var stat_rows_lit: int = 0

## ── ТАБЛИЦА СТАТОВ — ТОЛЬКО ПО НАВЕДЕНИЮ (ТЗ 18.09.2026, п. 6) ─────────────
## Панель строится при выделении, как прежде (её размеры нужны нижней панели:
## общая ширина, PANEL_TOP), но ПОКАЗЫВАЕТСЯ лишь пока курсор стоит на
## портрете отряда или на карточке награды (там она — экран предпросмотра).
## Карточка разведки (live_hp) видна всегда: нижней панели у чужого отряда
## нет, и наводить некуда. ПРЯЧЕТСЯ ПРОЗРАЧНОСТЬЮ, НЕ visible: у скрытой
## панели контейнеры не раскладывают детей (qa_vetui C3: иконка награды на
## x = 6 вместо правой колонки), а ширину и позиции читают стенды и нижняя
## панель. Прозрачная панель клика не держит (point_over_ui спрашивает
## stat_panel_shown), а ряд наград внутри неё на время прозрачности глушится
## по mouse_filter (_bonus_holders) — чтобы над пустым местом не всплывала
## подсказка награды
var _stat_hover_portrait: bool = false
var _stat_hover_vet: bool = false
var _stat_always: bool = false

func stat_panel_shown() -> bool:
	return _stat_panel != null and is_instance_valid(_stat_panel) \
		and _stat_panel.visible and _stat_panel.modulate.a > 0.01

## Держатели иконок наград: глушатся по mouse_filter, пока таблица прозрачна
var _bonus_holders: Array = []

func _stat_panel_wanted() -> bool:
	return _stat_always or _stat_hover_portrait or _stat_hover_vet or _stat_hover_forge

func _refresh_stat_visibility() -> void:
	if _stat_panel == null or not is_instance_valid(_stat_panel):
		return
	var want: bool = _stat_panel_wanted()
	_stat_panel.modulate = Color(1.0, 1.0, 1.0, 1.0 if want else 0.0)
	for h in _bonus_holders:
		if h != null and is_instance_valid(h):
			(h as Control).mouse_filter = Control.MOUSE_FILTER_PASS if want \
				else Control.MOUSE_FILTER_IGNORE
	if not want:
		_hide_bonus_tip()

## ── ПОДСКАЗКА НЕ МЕРЦАЕТ (ТЗ 12.10.2026) ────────────────────────────────────
## «Наводишь на иконку юнита — подсказка открывается и закрывается сто раз в
## секунду». Петля: таблица статов, ставшая видимой, накрывала портрет своими
## ячейками (у них mouse_filter PASS, пока таблица видна) → портрет получал
## mouse_exited → таблица гасла, ячейки становились IGNORE → мышь снова «на
## портрете» → mouse_entered → и так каждый кадр. Уход мыши теперь судится
## ГЕОМЕТРИЕЙ: пока курсор внутри прямоугольника портрета, событие выхода
## (его подменило перекрытие) не гасит таблицу; настоящий уход ловит
## _check_portrait_hover в _process
var _portrait_exit_held: bool = false

func _set_stat_hover_portrait(on: bool) -> void:
	if not on and _mouse_in_portrait():
		_portrait_exit_held = true
		return
	_portrait_exit_held = false
	if _stat_hover_portrait == on:
		return
	_stat_hover_portrait = on
	_refresh_stat_visibility()

func _mouse_in_portrait() -> bool:
	if _portrait_wrap == null or not is_instance_valid(_portrait_wrap) or not _portrait_wrap.is_visible_in_tree():
		return false
	return _portrait_wrap.get_global_rect().has_point(get_viewport().get_mouse_position())

func _check_portrait_hover() -> void:
	# Судим только удержанный выход: наведение без события выхода живёт как
	# прежде (стенды зовут _set_stat_hover_portrait напрямую)
	if _portrait_exit_held and _stat_hover_portrait and not _mouse_in_portrait():
		_portrait_exit_held = false
		_stat_hover_portrait = false
		_refresh_stat_visibility()

## Всплывающее окно без единой интерактивной части — мышь сквозь него
func _mouse_ignore_all(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_mouse_ignore_all(c)

func _hide_stat_panel() -> void:
	# Подсказка бонуса живёт НАД панелью статов и без неё осиротеет
	_hide_bonus_tip()
	_stat_always = false
	_stat_hover_vet = false
	_forge_preview_own = false
	_stat_sid = 0
	if _stat_panel != null and is_instance_valid(_stat_panel):
		_stat_panel.queue_free()
	_stat_panel = null
	_stat_rows.clear()
	_stat_names.clear()
	_stat_base.clear()
	_stat_bars.clear()
	_bonus_holders.clear()

# ═════════════════════════════════════════════════════════════════════════════
# ЭКВАЛАЙЗЕР СТАТОВ (ТЗ 19.09.2026, блок 4.2-4.3)
# ═════════════════════════════════════════════════════════════════════════════
# Средняя колонка таблицы статов — не текст «база +кузница +опыт =», а ПОЛОСКА
# из цветных отрезков: жёлтый — база юнита, зелёный — прирост кузницы,
# фиолетовый — прирост выбранного ветеранства, красный — отрицательные вклады
# (минус карточки, дебафф). Итог справа по-прежнему числом (его читают стенды
# и предпросмотр: _stat_rows[key] — правая ячейка, как и было).
# Предпросмотр награды (наведение на карточку) ДОРИСОВЫВАЕТ отрезок: плюс —
# ярко-фиолетовый в конец полоски, минус — красная накладка с конца.
# Масштаб у каждой полоски свой (сумма вкладов + запас под предпросмотр):
# полоски разных статов между собой не сравниваются, сравниваются ВКЛАДЫ
# внутри одной
const BAR_BASE_COLOR    := Color(0.95, 0.80, 0.22)
const BAR_FORGE_COLOR   := Color(0.38, 0.80, 0.38)
const BAR_VET_COLOR     := Color(0.66, 0.42, 0.92)
const BAR_NEG_COLOR     := Color(0.90, 0.26, 0.26)
const BAR_PREVIEW_COLOR := Color(0.84, 0.60, 1.00)
const BAR_BG_COLOR      := Color(0.12, 0.13, 0.18, 0.9)
const BAR_H := 8.0
const BAR_MIN_W := 64.0
## Длина полоски фиксирована (ТЗ-B 19.09.2026: «укоротить полоски»)
const BAR_W := 64.0
## Доля ширины под текущие вклады; остаток — под предпросмотр прибавки
const BAR_FILL_FRAC := 0.78

class StatBar extends Control:
	var base: float = 0.0
	var forge: float = 0.0
	var vet: float = 0.0
	var preview: float = 0.0
	var bar_h: float = 10.0
	var col_base := Color(0.95, 0.80, 0.22)
	var col_forge := Color(0.38, 0.80, 0.38)
	var col_vet := Color(0.66, 0.42, 0.92)
	var col_neg := Color(0.90, 0.26, 0.26)
	var col_prev := Color(0.84, 0.60, 1.00)
	var col_bg := Color(0.12, 0.13, 0.18, 0.9)
	var fill_frac: float = 0.78

	func set_parts(p_base: float, p_forge: float, p_vet: float) -> void:
		base = p_base
		forge = p_forge
		vet = p_vet
		queue_redraw()

	func set_preview(v: float) -> void:
		preview = v
		queue_redraw()

	## Отрезки слева направо: [длина в единицах стата, цвет]; отрицательные
	## вклады — отдельно, красной накладкой с конца
	func segments() -> Array:
		var out: Array = []
		if base > 0.0:
			out.append([base, col_base])
		if forge > 0.0:
			out.append([forge, col_forge])
		if vet > 0.0:
			out.append([vet, col_vet])
		return out

	func negative_total() -> float:
		var n := 0.0
		if forge < 0.0:
			n += -forge
		if vet < 0.0:
			n += -vet
		return n

	func _draw() -> void:
		var w: float = size.x
		var h: float = minf(bar_h, size.y) if size.y > 0.0 else bar_h
		var y0: float = maxf((size.y - h) * 0.5, 0.0)
		draw_rect(Rect2(0.0, y0, w, h), col_bg, true)
		var pos_total: float = 0.0
		for sg in segments():
			pos_total += float((sg as Array)[0])
		var span: float = pos_total + maxf(preview, 0.0)
		if span <= 0.0:
			return
		var k: float = w * fill_frac / maxf(pos_total, 1e-6)
		# Прибавка предпросмотра может не влезть в запас — ужимаем всё вместе
		if span * k > w:
			k = w / span
		var x: float = 0.0
		for sg in segments():
			var len_px: float = float((sg as Array)[0]) * k
			draw_rect(Rect2(x, y0 + 1.0, len_px, h - 2.0), (sg as Array)[1], true)
			x += len_px
		var end_x: float = x
		var neg: float = negative_total()
		if neg > 0.0:
			var nl: float = minf(neg * k, end_x)
			draw_rect(Rect2(end_x - nl, y0 + 1.0, nl, h - 2.0), col_neg, true)
		if preview > 0.0:
			draw_rect(Rect2(end_x, y0 + 1.0, preview * k, h - 2.0), col_prev, true)
		elif preview < 0.0:
			var pl: float = minf(-preview * k, end_x)
			draw_rect(Rect2(end_x - pl, y0 + 1.0, pl, h - 2.0), col_neg, true)

## ключ стата → полоска (см. _show_stat_panel); чистится вместе с панелью
var _stat_bars: Dictionary = {}

static var _bb_re: RegEx = null
static func _strip_bbcode(t: String) -> String:
	if _bb_re == null:
		_bb_re = RegEx.new()
		_bb_re.compile("[[]/?[a-z]+(=[^]]*)?[]]")
	return _bb_re.sub(t, "", true)

func _make_stat_bar(base: float, forge: float, vet: float) -> Control:
	var bar := StatBar.new()
	bar.custom_minimum_size = Vector2(BAR_W, BAR_H + 2.0)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.bar_h = BAR_H
	bar.col_base = BAR_BASE_COLOR
	bar.col_forge = BAR_FORGE_COLOR
	bar.col_vet = BAR_VET_COLOR
	bar.col_neg = BAR_NEG_COLOR
	bar.col_prev = BAR_PREVIEW_COLOR
	bar.col_bg = BAR_BG_COLOR
	bar.fill_frac = BAR_FILL_FRAC
	bar.set_parts(base, forge, vet)
	return bar

## Формула боевого стата в разметке BBCode: «Attack: 15 +3 +2 = 20» —
## база белым, вклад кузницы и вклад опыта зелёным (оба безымянные — только
## число со знаком, БЕЗ слов «Forge»/«Bonus»), итог жёлтым через «=».
## Если оба вклада нулевые, «= итог» не печатается — база и есть итог.
func _stat_formula(nm: String, base: float, forge: float, bonus: float,
		digits: int = 0) -> String:
	var p: Array = _stat_parts(nm, base, forge, bonus, digits)
	return "%s %s %s" % [String(p[0]), String(p[1]), String(p[2])]

## ── ТА ЖЕ ФОРМУЛА, РАЗОБРАННАЯ НА ТРИ КОЛОНКИ ─────────────────────────────
## ЗАКАЗ ВЛАДЕЛЬЦА: «колонки цифр съезжают; слева иконка и название, по центру
## модификаторы и знаки „=“ строго друг под другом, справа итог по правому
## краю».
##
## Одной строкой этого не добиться в принципе: ширина имени и числа у каждого
## стата своя, и «=» гуляет по горизонтали от строки к строке. Поэтому строка
## разбирается на ТРИ ЧАСТИ и раскладывается в GridContainer из трёх колонок —
## выравнивание делает контейнер, а не пробелы.
##
## РАЗБОР ЖИВЁТ ЗДЕСЬ, А НЕ В МЕСТЕ СБОРКИ ПАНЕЛИ: ту же формулу печатает
## предпросмотр награды, и два разных способа собрать одну строку разошлись бы
## на первой же правке (ровно это уже случалось с подписями «RATE»).
## Возвращает [подпись, модификаторы, итог]
func _stat_parts(nm: String, base: float, forge: float, bonus: float,
		digits: int = 0) -> Array:
	var fmt: String = "%.1f" if digits > 0 else "%.0f"
	var total: float = base + forge + bonus
	var mid: String = ""
	if absf(forge) > 0.001:
		mid += "[color=%s]%s[/color] " % [BONUS_COLOR, _signed(forge, fmt)]
	if absf(bonus) > 0.001:
		mid += "[color=%s]%s[/color] " % [BONUS_COLOR, _signed(bonus, fmt)]
	# База стоит в СРЕДНЕЙ колонке первой, а итог — в правой. Когда прибавок
	# нет, итог и есть база, и печатать её дважды незачем
	if mid.is_empty():
		return [nm, "", "[color=%s]%s[/color]" % [TOTAL_COLOR, fmt % base]]
	return [nm, "%s %s=" % [fmt % base, mid],
		"[color=%s]%s[/color]" % [TOTAL_COLOR, fmt % total]]

## ── ЗНАК БЕРЁТСЯ У ЧИСЛА, А НЕ ПРИБИВАЕТСЯ В ФОРМАТЕ ──────────────────────
## Жалоба владельца по скриншоту: в карточке стояло «+ -0.1». Здесь был
## литерал «+» и следом само число со своим знаком — на положительных это
## незаметно, а любая отрицательная прибавка (штраф от стойки, отрицательный
## модификатор награды) печаталась двумя знаками подряд.
##
## Одна функция на обе формулы: у перезарядки знак ещё и ПЕРЕВОРАЧИВАЕТСЯ
## (см. _stat_formula_cut), и держать два разных способа печатать знак — верный
## способ однажды разойтись
func _signed(v: float, fmt: String) -> String:
	return ("+" if v >= 0.0 else "-") + (fmt % absf(v))

## ── ФОРМУЛА ДЛЯ ХАРАКТЕРИСТИКИ, У КОТОРОЙ МЕНЬШЕ — ЛУЧШЕ ────────────────────
## Перезарядка удара единственная такая: ключ bonus_cooldown хранится
## ПОЛОЖИТЕЛЬНЫМ, а из поля бойца ВЫЧИТАЕТСЯ (см. Unit._effective_cooldown и
## GameManager._apply_bonus_to_unit). Печатать её обычной формулой значило бы
## показать «1.0 +0.2 = 1.2» там, где боец на самом деле бьёт ЧАЩЕ — то есть
## соврать знаком. Здесь прирост печатается со знаком «−», а итог считается
## вычитанием, с тем же полом MIN_COOLDOWN, что и в бою
## Та же формула на три колонки — для характеристики, у которой меньше лучше
## (см. _stat_parts и _stat_formula_cut)
func _stat_parts_cut(nm: String, base: float, forge: float, bonus: float,
		digits: int = 1, floor_at: float = 0.0) -> Array:
	var fmt: String = "%.1f" if digits > 0 else "%.0f"
	var total: float = maxf(base - forge - bonus, floor_at)
	var mid: String = ""
	# ЗНАК ПЕРЕВЁРНУТ, а не прибит (разбор — в _stat_formula_cut ниже)
	if absf(forge) > 0.001:
		mid += "[color=%s]%s[/color] " % [BONUS_COLOR, _signed(-forge, fmt)]
	if absf(bonus) > 0.001:
		mid += "[color=%s]%s[/color] " % [BONUS_COLOR, _signed(-bonus, fmt)]
	if mid.is_empty():
		return [nm, "", "[color=%s]%s[/color]" % [TOTAL_COLOR, fmt % base]]
	return [nm, "%s %s=" % [fmt % base, mid],
		"[color=%s]%s[/color]" % [TOTAL_COLOR, fmt % total]]

func _stat_formula_cut(nm: String, base: float, forge: float, bonus: float,
		digits: int = 1, floor_at: float = 0.0) -> String:
	var fmt: String = "%.1f" if digits > 0 else "%.0f"
	var total: float = maxf(base - forge - bonus, floor_at)
	var out: String = "[b]%s:[/b] %s" % [nm, fmt % base]
	# ЗНАК ПЕРЕВЁРНУТ, а не прибит: прибавка к перезарядке хранится
	# положительной и ВЫЧИТАЕТСЯ, поэтому «+0.2» в конфиге на экране обязано
	# стать «-0.2 c». Но и отрицательная прибавка (штраф) обязана стать «+»,
	# иначе получится тот же двойной знак, что уже ловился в _stat_formula
	if absf(forge) > 0.001:
		out += " [color=%s]%s[/color]" % [BONUS_COLOR, _signed(-forge, fmt)]
	if absf(bonus) > 0.001:
		out += " [color=%s]%s[/color]" % [BONUS_COLOR, _signed(-bonus, fmt)]
	if absf(forge) > 0.001 or absf(bonus) > 0.001:
		out += " [color=%s]= %s[/color]" % [TOTAL_COLOR, fmt % total]
	return out

## ── ХАРАКТЕРИСТИКИ, У КОТОРЫХ ПРИБАВКА ИДЁТ В МИНУС ────────────────────────
## Читает предпросмотр (см. _preview_stats): «+0,2» к перезарядке на экране
## обязано выглядеть как «−0,2 c», иначе игрок прочтёт награду как ухудшение
const NEGATIVE_STATS := {"cooldown": true, "spread": true}

## live_hp — печатать ли в заголовке живое здоровье отряда. Для СВОИХ отрядов
## не печатается (шум: полоски здоровья и так видны на бойцах), для карточки
## разведки — печатается: это и есть цель разведки
func _show_stat_panel(squad_id: int, units: Array, live_hp: bool = false) -> void:
	_hide_stat_panel()
	var sample: Unit = null
	for u in units:
		if is_instance_valid(u) and u is Unit:
			sample = u
			break
	if sample == null:
		return
	var uid: String = sample.stat_id
	var f: int = sample.faction

	# Прирост от кузницы = адресный бонус слота + общий апгрейд фракции
	var atk_smithy: float = GameManager.unit_bonus(f, uid, "bonus_attack") \
		+ GameManager.get_upgrade(f, "damage")
	if sample is Archer:
		atk_smithy += GameManager.get_upgrade(f, "arrow_dmg")
	# ── HP ИДЁТ ПЕРВЫМ, И БАЗА У НЕГО СЧИТАЕТСЯ ОБРАТНЫМ ХОДОМ ──────────────
	# Все остальные статы прибавляются от кузницы «вживую» при чтении, поэтому
	# у них база — это поле юнита, а прирост — отдельное слагаемое. У ЗДОРОВЬЯ
	# ИНАЧЕ: bonus_health единственный, который нельзя прочитать на лету, и
	# GameManager._apply_health_bonus_now вписывает его прямо в max_health в
	# момент исследования. Написать здесь base = max_health значит показать
	# прирост дважды, поэтому его вычитаем обратно
	var hp_forge: float = GameManager.unit_bonus(f, uid, "bonus_health")
	# ── СТРОКИ ИДУТ ПАРАМИ «КЛЮЧ СТАТА → ТЕКСТ» ────────────────────────────
	# Ключ нужен предпросмотру награды (см. _preview_stats): наведя курсор на
	# иконку выбора, надо дописать зелёную прибавку В СВОЮ строку, а искать её
	# по подписи («Health», «Armor») значило бы завести вторую таблицу
	# соответствий и разъехаться с конфигом при первом же переименовании
	# ── ТЕМП УДАРА И МОРАЛЬ ТЕПЕРЬ ТОЖЕ СТРОКИ ТАБЛИЦЫ ──────────────────────
	# Заказ владельца по скриншотам 5-6: наведя курсор на награду, игрок видел в
	# плашке «+3 ATK, +0,2 RATE, +10 MORALE», а в таблице слева дописывалась
	# ОДНА прибавка — к атаке. Две другие молча исчезали: у них не было своей
	# строки, и _preview_stats честно их пропускал.
	#
	# Прибавки этих двух наград хранятся ПО-РАЗНОМУ, и это надо читать по-разному:
	#   • мораль пишется прямо в поле бойца (Unit.morale), значит «база» — это
	#     поле МИНУС то, что уже добавило ветеранство (squad_bonus);
	#   • перезарядка тоже пишется в поле, но ВЫЧИТАНИЕМ, а от кузницы читается
	#     вживую при каждом ударе — поэтому её строка идёт через _stat_formula_cut.
	var cd_vet: float   = GameManager.squad_bonus(squad_id, "cooldown")
	var cd_forge: float = GameManager.unit_bonus(f, uid, "bonus_cooldown")
	var mo_vet: float   = GameManager.squad_bonus(squad_id, "morale")
	var mo_forge: float = GameManager.unit_bonus(f, uid, "bonus_morale")
	# Ветеранство запаса жизни и напора вписано прямо в поля бойца — вычитаем
	# обратно, чтобы фиолетовый отрезок полоски показал именно его
	var hp_vet: float   = GameManager.squad_bonus(squad_id, "health")
	var pu_vet: float   = GameManager.squad_bonus(squad_id, "push")
	var def_forge: float = GameManager.get_upgrade(f, "defense")
	var ar_forge: float = GameManager.unit_bonus(f, uid, "bonus_armor")
	var pu_forge: float = GameManager.unit_bonus(f, uid, "bonus_push")
	var sp_forge: float = GameManager.unit_bonus(f, uid, "bonus_speed")
	# Числа для полосок эквалайзера: ключ → [база, кузница, ветеранство]
	var nums: Dictionary = {
		"health":   [sample.max_health - hp_forge - hp_vet, hp_forge, hp_vet],
		"attack":   [sample.attack_damage, atk_smithy, sample.vet_attack],
		"defense":  [sample.defense, def_forge, sample.vet_defense],
		"armor":    [sample.armor, ar_forge, sample.vet_armor],
		"push":     [sample.push_force - pu_vet, pu_forge, pu_vet],
		"morale":   [sample.morale - mo_vet, mo_forge, mo_vet],
		"speed":    [sample.move_speed, sp_forge, sample.vet_speed],
		# «Меньше — лучше»: жёлтый — то, что осталось, зелёный и фиолетовый —
		# сколько срезано кузницей и опытом
		"cooldown": [maxf(sample.attack_cooldown - cd_forge, _UCfg.MIN_COOLDOWN), cd_forge, cd_vet],
	}
	var lines: Array = [
		["health", _stat_parts(String(STAT_ROW_LABELS["health"]),  sample.max_health - hp_forge - hp_vet, hp_forge, hp_vet)],
		["attack", _stat_parts(String(STAT_ROW_LABELS["attack"]),  sample.attack_damage, atk_smithy, sample.vet_attack)],
		["defense", _stat_parts("Defense", sample.defense,
			def_forge, sample.vet_defense)],
		["armor", _stat_parts(String(STAT_ROW_LABELS["armor"]),   sample.armor,
			ar_forge, sample.vet_armor)],
		["push", _stat_parts(String(STAT_ROW_LABELS["push"]),    sample.push_force - pu_vet,
			pu_forge, pu_vet, 1)],
		["morale", _stat_parts(String(STAT_ROW_LABELS["morale"]),
			sample.morale - mo_vet, mo_forge, mo_vet)],
		# ── ШЕСТЬ ГЛАВНЫХ СТРОК ВЫШЕ, ОСТАЛЬНОЕ НИЖЕ (заказ владельца) ────────
		# Порядок задан списком: Health, Attack, Defense, Armor, Push, Morale.
		# Скорость и интервал атаки оставлены, но уехали ПОД них — убрать их
		# совсем нельзя: предпросмотр награды дописывает прибавку В СТРОКУ по
		# ключу стата, и награда, качающая темп удара, снова стала бы показывать
		# в плашке модификатор, которого нет в таблице (эта беда уже ловилась)
		["speed", _stat_parts(String(STAT_ROW_LABELS["speed"]),   sample.move_speed,
			GameManager.unit_bonus(f, uid, "bonus_speed"), sample.vet_speed, 1)],
		["cooldown", _stat_parts_cut(String(STAT_ROW_LABELS["cooldown"]),
			sample.attack_cooldown + cd_vet, cd_forge, cd_vet, 1, _UCfg.MIN_COOLDOWN)],
	]
	# У ЛУЧНИКА НЕТ НИ НАПОРА, НИ ЗАЩИТЫ (ТЗ 24.10.2026, блок 7): обе строки
	# у него — вечные «0» и «0.0», место в таблице без смысла
	if uid == "archer":
		lines = lines.filter(func(l): return String(l[0]) != "push" and String(l[0]) != "defense")
	# У РАБОЧЕГО — ТОЛЬКО ЕГО РЕМЕСЛО (ТЗ 24.10.2026, блок 7): ход, груз за
	# ходку и темп стройки. Атака, броня, мораль рабочего в кузнице не растут,
	# и шесть строк про бой при наведении на «Груз» только путали
	if uid == "worker":
		var walk_k: float = GameManager.unit_bonus(f, uid, "bonus_walk_loaded_pct")
		var carry0: float = float(sample.get("gather_amount"))
		var carry1: float = float(sample.call("carry_capacity")) if sample.has_method("carry_capacity") else carry0
		var build_k: float = GameManager.unit_bonus(f, uid, "bonus_build")
		lines = [
			["speed", _stat_parts(String(STAT_ROW_LABELS["speed"]), sample.move_speed,
				sample.move_speed * walk_k, 0.0, 1)],
			["carry", _stat_parts(String(STAT_ROW_LABELS["carry"]), carry0,
				carry1 - carry0, 0.0)],
			["build", _stat_parts(String(STAT_ROW_LABELS["build"]) + " %", 100.0,
				100.0 * build_k, 0.0)],
		]
		nums = {
			"speed": [sample.move_speed, sample.move_speed * walk_k, 0.0],
			"carry": [carry0, carry1 - carry0, 0.0],
			"build": [100.0, 100.0 * build_k, 0.0],
		}
	_stat_nums = nums
	# ДАЛЬНОСТЬ — ТОЛЬКО У ТОГО, КТО СТРЕЛЯЕТ. У копейщика это «длина руки» в
	# два метра: строка с ней ничего не сообщает, зато занимает место в таблице
	# ровно так же, как у лучника
	if sample.attack_range > MELEE_RANGE_MAX and uid != "worker":
		var rg_vet: float = GameManager.squad_bonus(squad_id, "range")
		var rg_forge: float = GameManager.unit_bonus(f, uid, "bonus_range")
		lines.append(["range", _stat_parts(String(STAT_ROW_LABELS["range"]),
			sample.attack_range - rg_vet - rg_forge, rg_forge, rg_vet, 1)])
		nums["range"] = [sample.attack_range - rg_vet - rg_forge, rg_forge, rg_vet]

	# ЗАРАБОТАННЫЕ БОНУСЫ ОТРЯДА: id наград по уровням, одинаковые повторяются —
	# из этого ниже собирается ряд иконок со стеком (II, III, IV)
	var chosen: Array = GameManager.squad_chosen(squad_id)

	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.10, 0.93)
	_borders(st); _corners(st, 6)
	st.border_color = Color(0.34, 0.44, 0.58)
	st.content_margin_left = 6; st.content_margin_right = 6
	st.content_margin_top  = 3;  st.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", st)
	# ШИРИНА СВОЯ, КОМПАКТНАЯ (ТЗ-B 19.09.2026, п. 3) — не _panel_w: таблица
	# меньше панели отряда и стоит над её левым краем
	panel.custom_minimum_size = Vector2(STAT_COMPACT_W, 0)
	_stat_sid = squad_id

	# ── ДВЕ КОЛОНКИ: ТЕКСТ СЛЕВА, ЗАРАБОТАННЫЕ НАГРАДЫ СПРАВА ──────────────
	# Заказ владельца: иконку уже выбранного бонуса перенести из нижней панели
	# в правую часть этой таблицы. Место там и правда пустует — строки статов
	# короткие, а панель широкая, — и перенос убирает лишний ряд снизу, из-за
	# которого нижняя панель росла вверх.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(vb)

	# Колонка наград прижата к ВЕРХУ: строк статов шесть, наград обычно одна-две,
	# и по центру они висели бы в пустоте посреди таблицы
	var side := VBoxContainer.new()
	side.name = "BonusColumn"
	side.size_flags_horizontal = Control.SIZE_SHRINK_END
	side.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	body.add_child(side)

	var lvl_head: int = GameManager.squad_level(squad_id)
	# ── НАЗВАНИЯ ОТРЯДА В КАРТОЧКЕ СТАТОВ БОЛЬШЕ НЕТ (заказ владельца) ──────
	# «Отряд опытных копейщиков» стояло ДВАЖДЫ, одно под другим: в шапке этой
	# таблицы и строкой ниже, в подписи нижней панели. Владелец вычеркнул
	# верхнее — то, что дублирует, — и оставил нижнее (см. info_label, оно
	# теперь идёт во всю ширину панели одной строкой).
	#
	# ИСКЛЮЧЕНИЕ ОДНО — КАРТОЧКА РАЗВЕДКИ (live_hp). Там шапка не дублирует
	# ничего: чужой отряд не выделен, нижней панели с его названием нет вовсе,
	# а «сколько в нём осталось прямо сейчас» и есть то, ради чего карточку
	# открывают
	var head := Label.new()
	# ── ЗАГОЛОВОК ОЧИЩЕН ОТ ДУБЛЕЙ (заказ владельца) ────────────────────────
	# Здесь стояло «Отряд мечников ★ — 30 бойцов  3000/3000 HP». Ровно та же
	# фраза «Отряд мечников — 30 бойцов» стояла строкой ниже, в плашке юнита, а
	# численность вдобавок нарисована бейджем на портрете: одно и то же число
	# сообщалось три раза подряд. Осталось имя и ранг — то, чего больше нигде нет.
	#
	# ЖИВОЕ ЗДОРОВЬЕ ОТРЯДА ОСТАВЛЕНО ТОЛЬКО В КАРТОЧКЕ РАЗВЕДКИ. Для своего
	# отряда это шум (полоски здоровья видны прямо на бойцах), а вот при
	# разведке чужого строя «сколько в нём осталось прямо сейчас» — ЕДИНСТВЕННОЕ,
	# ради чего карточку и открывают: строка Health ниже это паспорт модели, а не
	# состояние отряда
	var title_txt: String = _squad_title_ranked(
		GameManager.squad_type(squad_id), lvl_head)
	if live_hp:
		var hp_now := 0.0
		var hp_max := 0.0
		for u in units:
			var uu := u as Unit
			if uu != null and is_instance_valid(uu) and not uu.is_dead():
				hp_now += uu.current_health
				hp_max += uu.max_health
		title_txt += "   %d/%d HP" % [int(round(hp_now)), int(round(hp_max))]
	head.text = title_txt
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	# Ширина текстовой колонки уменьшена на колонку наград: иначе строки заняли
	# бы всю панель и вытолкнули иконки за её правый край
	var text_w: float = STAT_COMPACT_W - 20.0 - BONUS_COL_W
	_fix_label(head, int(text_w), 1)
	if live_hp:
		vb.add_child(head)
	else:
		head.queue_free()

	# ── ТРИ КОЛОНКИ, А НЕ ОДНА СТРОКА НА СТАТ ──────────────────────────────
	# ЗАКАЗ ВЛАДЕЛЬЦА: «огромная плашка нечитабельна, колонки цифр съезжают».
	# Съезжали они неизбежно: строка была ОДНА («Health: 180 +12 = 192»), а
	# ширина имени и числа у каждого стата своя — «=» гуляло по горизонтали от
	# строки к строке. Пробелами это не лечится, выравнивание обязан делать
	# контейнер. Сетка на три колонки: слева иконка с подписью, посередине
	# модификаторы со знаком «=», справа итог по правому краю
	var grid := GridContainer.new()
	grid.name = "StatGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(grid)
	for rec in lines:
		var pair: Array = rec
		var key: String = String(pair[0])
		var parts: Array = pair[1]
		# ── ЛЕВАЯ КОЛОНКА: ТОЛЬКО ПОДПИСЬ, БЕЗ ЗНАЧКА (заказ владельца) ────
		# Значки здесь были и убраны: их в наборе четыре (сердце, меч, щит,
		# сломанный меч), а строк в таблице до девяти — у скорости, напора и
		# морали значка нет вовсе, и ряд получался рваным: часть строк с
		# картинкой, часть без, подписи из-за этого не выстраивались в колонку.
		# Чистый список читается ровно, а выравнивание по-прежнему делает сетка.
		# STAT_ICONS остались: их читают карточки наград, там значок один на
		# карточку и рваного ряда не возникает
		var name_lbl := Label.new()
		name_lbl.text = String(parts[0])
		name_lbl.add_theme_font_size_override("font_size", STAT_FONT_PX)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(name_lbl)
		_stat_names[key] = name_lbl
		# ── СРЕДНЯЯ: БАЗА, ПРИБАВКИ И ЗНАК «=» ─────────────────────────────
		# Прижата ВПРАВО: тогда «=» всех строк выстраивается в одну вертикаль,
		# сколько бы прибавок ни было в каждой
		# ── СРЕДНЯЯ КОЛОНКА — ЭКВАЛАЙЗЕР (ТЗ 19.09.2026, блок 4.2) ─────────
		# Полоска из отрезков: база (жёлтый), кузница (зелёный), ветеранство
		# (фиолетовый), минусы красным. Прежний текст «база +… =» — в
		# подсказке строки (tooltip), чтобы число не пропало вовсе
		if live_hp:
			# КАРТОЧКА РАЗВЕДКИ — числами: чужой отряд читают «сколько у него
			# грейдов», и текст «+2 =» там и есть ответ (qa_recon C1)
			var mid := RichTextLabel.new()
			mid.bbcode_enabled = true
			mid.fit_content    = true
			mid.scroll_active  = false
			mid.autowrap_mode  = TextServer.AUTOWRAP_OFF
			mid.add_theme_font_size_override("normal_font_size", STAT_FONT_PX)
			mid.add_theme_font_size_override("bold_font_size", STAT_FONT_PX)
			mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mid.text = "[right]%s[/right]" % String(parts[1])
			grid.add_child(mid)
		else:
			var nv: Array = nums.get(key, [0.0, 0.0, 0.0])
			var bar: Control = _make_stat_bar(float(nv[0]), float(nv[1]), float(nv[2]))
			bar.name = "Bar_" + key
			bar.tooltip_text = "%s: %s %s" % [String(parts[0]), _strip_bbcode(String(parts[1])), _strip_bbcode(String(parts[2]))]
			grid.add_child(bar)
			_stat_bars[key] = bar
		# ── ПРАВАЯ: ИТОГ ПО ПРАВОМУ КРАЮ ───────────────────────────────────
		var tot := RichTextLabel.new()
		tot.bbcode_enabled = true
		tot.fit_content    = true
		tot.scroll_active  = false
		tot.autowrap_mode  = TextServer.AUTOWRAP_OFF
		tot.add_theme_font_size_override("normal_font_size", STAT_FONT_PX)
		tot.add_theme_font_size_override("bold_font_size", STAT_FONT_PX)
		tot.custom_minimum_size = Vector2(STAT_TOTAL_W, 14)
		tot.text = "[right]%s[/right]" % String(parts[2])
		grid.add_child(tot)
		# ── РЕЕСТР ДЛЯ ПРЕДПРОСМОТРА — ЭТО ПРАВАЯ ЯЧЕЙКА ───────────────────
		# Предпросмотр награды дописывает прибавку В КОНЕЦ строки
		# (см. _preview_stats), а конец строки теперь здесь. Ни одной правки в
		# самом предпросмотре не понадобилось: он по-прежнему знает про
		# «label по ключу стата» и про его исходный текст
		_stat_rows[key] = tot
		_stat_base[key] = tot.text

	_build_bonus_row(side, chosen, uid)

	# Растёт ВВЕРХ от верхней кромки нижней панели на реальную высоту (см.
	# _pin_floater_above) — раньше высота "24 + lines.size()*17 + bonus_h"
	# не учитывала перенос длинного заголовка на вторую строку, и панель
	# статов наезжала на командную панель ровно под собой
	_stat_panel = panel
	_stat_always = live_hp
	# Прозрачна до наведения (ТЗ 18.09.2026, п. 6); размеры при этом честные
	_refresh_stat_visibility()
	# ЗАЗОРА МЕЖДУ ОКНОМ И ПЛАШКОЙ НЕТ (заказ владельца). Стояло PANEL_TOP − 6:
	# шесть пикселей пустоты, из-за которых два тёмных блока читались как два
	# несвязанных окна, а не как одна панель управления отрядом
	await _pin_floater_above(panel, PANEL_TOP, PANEL_LEFT, STAT_COMPACT_W)
	# ── ВЫСОТА ПАНЕЛИ ПЕРЕСЧИТЫВАЕТСЯ ПОЗЖЕ, ЧЕМ МЫ СЮДА ПОПАЛИ ─────────────
	# _pin_floater_above ждёт кадр (иначе не знает своей высоты), а
	# _sync_panel_height успевает отработать в ЭТОМ же вызове show_selection и
	# сдвинуть PANEL_TOP вверх. Сдвиг «всего, что висит над панелью» там есть, но
	# он применяется ДО нашего пробуждения — и продолжение корутины затирает его
	# устаревшим числом. Пока зазор был 6 px, а панель ниже, это пряталось; с
	# нулевым зазором и шкалой опыта окно статов легло прямо на плашку.
	# Перепривязываемся к ЖИВОМУ PANEL_TOP
	if is_instance_valid(panel) and not panel.is_queued_for_deletion():
		# _pin_floater_above показал панель — прячем до наведения (п. 6)
		_refresh_stat_visibility()
		_apply_left_column_width()
		var hh: float = panel.get_combined_minimum_size().y
		panel.offset_bottom = float(PANEL_TOP)
		panel.offset_top    = float(PANEL_TOP) - hh

# ─────────────────────────────────────────────────────────────────────────────
# РЯД ЗАРАБОТАННЫХ БОНУСОВ ОТРЯДА
#
# Один и тот же бонус можно взять на нескольких уровнях ветеранства, поэтому
# ряд показывает НЕ по иконке за уровень, а по иконке за ВИД бонуса со стеком:
#   1 раз  — просто иконка,
#   2 раза — иконка + «II», 3 раза — «III», 4 — «IV» и так далее.
# Никаких зелёных галочек здесь нет (это не «куплено/не куплено», а «сколько
# раз взято»), иконка идёт в полную яркость.
#
# Наведение открывает МОДУЛЬНОЕ окно-подсказку: название, текущий стек и
# конкретные числа — сколько даёт бонус суммарно и на каких уровнях был взят.
# ─────────────────────────────────────────────────────────────────────────────

## Базовый размер иконки бонуса и он же −30% по заказу владельца
const BONUS_ICON_BASE := 40.0
const BONUS_ICON_SIZE := BONUS_ICON_BASE * 0.7
const BONUS_TIP_W     := 300.0
## Сколько иконок в ряд помещается в правой колонке таблицы статов и какой
## ширины эта колонка. Ширина ВЫВОДИТСЯ из размера иконки, а не задана числом:
## иконку уже уменьшали на 30%, и зашитая ширина оставила бы дыру
const BONUS_COL_COUNT := 2
const BONUS_COL_W := BONUS_ICON_SIZE * float(BONUS_COL_COUNT) + 4.0 * float(BONUS_COL_COUNT - 1)

var _bonus_tip: Control = null

func _hide_bonus_tip() -> void:
	if _bonus_tip != null and is_instance_valid(_bonus_tip):
		_bonus_tip.queue_free()
	_bonus_tip = null

## chosen — id наград ПО ПОРЯДКУ УРОВНЕЙ (см. GameManager.squad_chosen).
## unit_type — боевой тип отряда (stat_id), у каждого свой конфиг наград
## (см. unit_stats_config.VET_CONFIG)
## Ряд наград (ТЗ 19.09.2026, блок 4.4): ВСЕ открытые перки — выбранные
## награды ветеранства (фиолетовый маркер «✓») и изученные узлы кузницы этого
## рода войск (зелёная рамка); у каждой иконки — плашка с описанием
## ── ТЗ 20.09.2026 (п. 6.1): В КАРТОЧКЕ ТОЛЬКО ВЕТЕРАНСТВО ─────────────────
## Заказ: «полностью убрать улучшения из Кузницы, оставить ТОЛЬКО улучшения
## ветеранства». Узлы кузницы одинаковы у ВСЕХ отрядов рода войск — в карточке
## конкретного отряда они ничего о нём не сообщают, а места занимали больше,
## чем сами награды (скриншот 3: две колонки по семь иконок). Смотреть их
## по-прежнему можно в самой кузнице. Сборщик иконки и плашка оставлены:
## механизм рабочий, ручка — одна строка
const BONUS_ROW_SHOWS_FORGE := false

func _build_bonus_row(parent: Control, chosen: Array, unit_type: String) -> void:
	var forge_done: Array = _forge_nodes_done(unit_type) if BONUS_ROW_SHOWS_FORGE else []
	if chosen.is_empty() and forge_done.is_empty():
		return
	# Порядок вывода — по первому появлению бонуса, чтобы ряд не прыгал при
	# каждом новом уровне. Словарь id -> список уровней, на которых он взят
	var order: Array = []
	var levels: Dictionary = {}
	for i in range(chosen.size()):
		var cid: String = String(chosen[i])
		# «auto_N» — служебная запись авто-ветеранства о выданной ступени, не
		# награда: значка у неё нет, и колонка показывала заглушку «AUT»
		# (ТЗ 24.10.2026, блок 7). Ступень видна по флажку ранга внизу
		if cid.is_empty() or cid.begins_with("auto_"):
			continue
		if not levels.has(cid):
			levels[cid] = []
			order.append(cid)
		(levels[cid] as Array).append(i + 1)   # уровень = индекс + 1

	# ── СЕТКА В ДВЕ КОЛОНКИ, А НЕ СТРОКА ───────────────────────────────────
	# Ряд переехал из нижней панели в ПРАВУЮ ЧАСТЬ таблицы статов (заказ
	# владельца), а там ширины на семь иконок подряд нет и быть не может.
	# Две колонки — это шесть-восемь наград в высоту таблицы, то есть весь
	# возможный набор: видов наград в конфиге меньше, чем уровней.
	# Имя узла прежнее: по нему ряд ищут стенды
	var row := GridContainer.new()
	row.name = "BonusRow"
	row.columns = BONUS_COL_COUNT
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	parent.add_child(row)

	for cid_v in order:
		var cid: String = String(cid_v)
		var lvls: Array = levels[cid]
		row.add_child(_bonus_icon(cid, lvls, unit_type))
	for nid_v in forge_done:
		row.add_child(_forge_perk_icon(String(nid_v), unit_type))

## Изученные узлы кузницы этого рода войск (id вида «archer_2b»), в порядке сетки
func _forge_nodes_done(unit_type: String) -> Array:
	var out: Array = []
	var f: int = Constants.FACTION_PLAYER
	var main := GameManager.main
	if main != null and is_instance_valid(main) and main.get("selection_manager") != null:
		for u in main.selection_manager.selected_units:
			if is_instance_valid(u) and u is Unit:
				f = (u as Unit).faction
				break
	for cell in _Forge.cells():
		var nid: String = _Forge.node_id(unit_type, String(cell))
		if GameManager.is_researched(f, nid):
			out.append(nid)
	return out

## Цвета рамок маркеров: ветеранство — фиолетовый, кузница — зелёный
const PERK_VET_COLOR := Color(0.70, 0.45, 0.95)
const PERK_FORGE_COLOR := Color(0.40, 0.80, 0.42)

func _perk_frame(holder: Control, color: Color) -> void:
	var fr := ReferenceRect.new()
	fr.name = "PerkFrame"
	fr.editor_only = false
	fr.border_color = color
	fr.border_width = 2.0
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(fr)

## Иконка изученного узла кузницы в ряду перков; плашка — название и описание
func _forge_perk_icon(node_id: String, unit_type: String) -> Control:
	var view: Dictionary = _Forge.node_view(node_id)
	var holder := QuietTooltipControl.new()
	holder.name = "Forge_" + node_id
	holder.custom_minimum_size = Vector2(BONUS_ICON_SIZE, BONUS_ICON_SIZE)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon_path: String = String(view.get("icon", ""))
	var tex: Texture2D = null
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	if tex != null:
		holder.add_child(_stretched_icon(tex, 2.0))
	else:
		var fb := Label.new()
		fb.text = node_id.get_slice("_", 1).to_upper()
		fb.add_theme_font_size_override("font_size", 11)
		fb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fb.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(fb)
	_perk_frame(holder, PERK_FORGE_COLOR)
	# Маленькая зелёная галочка в правом нижнем углу (ТЗ 14.10.2026, п. 2)
	var ck := Label.new()
	ck.name = "DoneCheck"
	ck.text = "✔"
	ck.add_theme_font_size_override("font_size", 9)
	ck.add_theme_color_override("font_color", UPG_CHECK_COLOR)
	ck.add_theme_color_override("font_outline_color", Color(0.02, 0.10, 0.02))
	ck.add_theme_constant_override("outline_size", 3)
	ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ck.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ck.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	ck.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ck.offset_right = -1.0
	ck.offset_bottom = 1.0
	holder.add_child(ck)
	holder.mouse_entered.connect(func(): _show_forge_perk_tip(holder, node_id, unit_type))
	holder.mouse_exited.connect(_hide_bonus_tip)
	_bonus_holders.append(holder)
	if not _stat_panel_wanted():
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.tree_exiting.connect(_hide_bonus_tip)
	holder.tooltip_text = String(view.get("title", node_id))
	return holder

func _show_forge_perk_tip(anchor: Control, node_id: String, _unit_type: String) -> void:
	_hide_bonus_tip()
	if anchor == null or not is_instance_valid(anchor):
		return
	var view: Dictionary = _Forge.node_view(node_id)
	var lines: Array = []
	var desc: String = String(view.get("description", ""))
	if not desc.is_empty():
		lines.append(desc)
	var sb: Dictionary = view.get("stat_bonus", {})
	for k in sb:
		var amt: float = float(sb[k])
		var lbl: String = String(MOD_SHORT_LABELS.get("bonus_" + String(k), String(k).to_upper()))
		lines.append("%s %s" % [_mod_amount(amt), lbl])
	if lines.is_empty():
		lines.append("Изучено в кузнице")
	var panel := PanelContainer.new()
	panel.name = "BonusTip"
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.10, 0.96)
	_borders(st); _corners(st, 6)
	st.border_color = PERK_FORGE_COLOR
	st.content_margin_left = 10; st.content_margin_right = 10
	st.content_margin_top  = 8;  st.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(BONUS_TIP_W, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	panel.add_child(vb)
	var head := Label.new()
	head.text = "Кузница: " + String(view.get("title", node_id))
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(0.78, 1.0, 0.78))
	_fix_label(head, BONUS_TIP_W - 20.0, 1)
	vb.add_child(head)
	for line in lines:
		var lb := Label.new()
		lb.text = String(line)
		lb.add_theme_font_size_override("font_size", 12)
		lb.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
		_fix_label(lb, BONUS_TIP_W - 20.0, 2)
		vb.add_child(lb)
	var g: Array = _tip_anchor_geometry(anchor, BONUS_TIP_W)
	_bonus_tip = panel
	await _pin_floater_above(panel, float(g[1]), float(g[0]), BONUS_TIP_W)

func _bonus_icon(choice_id: String, lvls: Array, unit_type: String) -> Control:
	var info: Dictionary = _UCfg.veteran_choice_info(unit_type, choice_id)
	# QuietTooltipControl: у значка уже есть своя карточка (_show_bonus_tip
	# ниже) — движковый пузырь по tooltip_text дублировал бы её тем же текстом
	var holder := QuietTooltipControl.new()
	holder.name = "Bonus_" + choice_id
	holder.custom_minimum_size = Vector2(BONUS_ICON_SIZE, BONUS_ICON_SIZE)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP

	var tex: Texture2D = _icon_texture(String(info.get("icon", "")))
	if tex != null:
		holder.add_child(_stretched_icon(tex, 0.0))
	else:
		# Картинки нет — не оставляем пустое место: подписываем видом бонуса
		var fb := Label.new()
		fb.text = choice_id.substr(0, 3).to_upper()
		fb.add_theme_font_size_override("font_size", 11)
		fb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fb.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(fb)

	# СТЕК: римская цифра поверх иконки, начиная со второго взятия
	if lvls.size() >= 2:
		var st_lbl := Label.new()
		st_lbl.name = "Stack"
		st_lbl.text = _roman(lvls.size())
		st_lbl.add_theme_font_size_override("font_size", 14)
		st_lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.70))
		st_lbl.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.02))
		st_lbl.add_theme_constant_override("outline_size", 5)
		st_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		st_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		st_lbl.offset_left   = -22.0
		st_lbl.offset_top    = -18.0
		st_lbl.offset_right  = 0.0
		st_lbl.offset_bottom = 0.0
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		holder.add_child(st_lbl)

	# ФИОЛЕТОВЫЙ МАРКЕР ВЫБРАННОЙ НАГРАДЫ (ТЗ 19.09.2026, блок 4.4): рамка и
	# галочка в углу — «это взято ветеранством», в отличие от узлов кузницы
	_perk_frame(holder, PERK_VET_COLOR)
	var mark := Label.new()
	mark.name = "VetMark"
	mark.text = "✓"
	mark.add_theme_font_size_override("font_size", 12)
	mark.add_theme_color_override("font_color", PERK_VET_COLOR)
	mark.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.12))
	mark.add_theme_constant_override("outline_size", 4)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mark.offset_left = 1.0
	mark.offset_top = -3.0
	holder.add_child(mark)
	holder.mouse_entered.connect(func(): _show_bonus_tip(holder, choice_id, lvls, unit_type))
	holder.mouse_exited.connect(_hide_bonus_tip)
	_bonus_holders.append(holder)
	if not _stat_panel_wanted():
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.tree_exiting.connect(_hide_bonus_tip)
	# Дублируем краткую суть в штатный tooltip: если окно-подсказка почему-то
	# не откроется, игрок всё равно узнает, на что смотрит
	holder.tooltip_text = "%s ×%d" % [String(info.get("name", choice_id)), lvls.size()]
	return holder

## МОДУЛЬНОЕ ОКНО-ПОДСКАЗКА бонуса. Своё, а не общая карточка _show_card:
## та прижата к верхней кромке нижней панели и легла бы ровно на панель статов,
## внутри которой висит сам ряд иконок
func _show_bonus_tip(anchor: Control, choice_id: String, lvls: Array, unit_type: String) -> void:
	_hide_bonus_tip()
	if anchor == null or not is_instance_valid(anchor):
		return
	var info: Dictionary = _UCfg.veteran_choice_info(unit_type, choice_id)
	var stat: String = String(info.get("stat", choice_id))
	var human := {
		"attack": "урон", "armor": "броня", "defense": "защита",
		"speed": "скорость", "health": "максимум HP",
	}
	var digits: int = 1 if stat == "speed" else 0
	var fmt: String = "%.1f" if digits > 0 else "%.0f"

	# Сумма считается ПО УРОВНЯМ, а не «значение × количество»: value одного и
	# того же бонуса на разных уровнях разное (см. VETERAN_LEVEL_BONUSES)
	var total: float = 0.0
	var per_lvl: Array = []
	for l_v in lvls:
		var l: int = int(l_v)
		var c: Dictionary = _UCfg.veteran_choice_at(unit_type, l, choice_id)
		var v: float = float(c.get("value", 0.0))
		total += v
		per_lvl.append("ур.%d: +%s" % [l, fmt % v])

	var lines: Array = [
		"Стек: %s  (взят %d раз)" % [_roman(lvls.size()), lvls.size()],
		"Даёт: +%s к «%s» каждой модели" % [fmt % total, String(human.get(stat, stat))],
		"Уровни — " + ", ".join(per_lvl),
	]

	var panel := PanelContainer.new()
	panel.name = "BonusTip"
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.10, 0.96)
	_borders(st); _corners(st, 6)
	st.border_color = Color(0.62, 0.54, 0.28)
	st.content_margin_left = 10; st.content_margin_right = 10
	st.content_margin_top  = 8;  st.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(BONUS_TIP_W, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	panel.add_child(vb)

	var head := Label.new()
	head.text = String(info.get("name", choice_id))
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
	_fix_label(head, BONUS_TIP_W - 20.0, 1)
	vb.add_child(head)

	for line in lines:
		var lb := Label.new()
		lb.text = String(line)
		lb.add_theme_font_size_override("font_size", 12)
		lb.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
		_fix_label(lb, BONUS_TIP_W - 20.0, 1)
		vb.add_child(lb)

	# СТРОГО НАД САМОЙ ИКОНКОЙ БОНУСА — тем же общим правилом, что и остальные
	# всплывающие окна (см. _tip_anchor_geometry). Раньше окно жёстко прибивалось
	# к левому краю экрана и к верхней кромке панели статов: оно ставало над
	# рядом бонусов целиком, а не над тем значком, на который навели
	var g: Array = _tip_anchor_geometry(anchor, BONUS_TIP_W)
	_bonus_tip = panel
	await _pin_floater_above(panel, float(g[1]), float(g[0]), BONUS_TIP_W)

## Римская запись — для стека бонусов (II, III, IV, ...)
func _roman(n: int) -> String:
	if n <= 0:
		return ""
	var vals: Array = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms: Array = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var left: int = n
	var out: String = ""
	for i in range(vals.size()):
		var v: int = int(vals[i])
		while left >= v:
			out += String(syms[i])
			left -= v
	return out

## «Атака: 20 (+5)» — прирост печатается, только если он есть
func _plus(nm: String, base: float, bonus: float, digits: int = 0) -> String:
	var fmt: String = "%.1f" if digits > 0 else "%.0f"
	var out: String = nm + ": " + (fmt % base)
	if absf(bonus) > 0.001:
		out += " (+%s)" % (fmt % bonus)
	return out

## Кнопки выбора улучшения. Шаблон берётся из конфига по текущему уровню
func _build_veteran_menu(squad_id: int, units: Array) -> void:
	var utype: String = GameManager.squad_type(squad_id)
	var lvl: int = GameManager.squad_choosing_level(squad_id)
	var choices: Array = _UCfg.veteran_choices(utype, lvl)
	if choices.is_empty():
		return
	# ── УБРАНА СЛУЖЕБНАЯ СТРОКА, А НЕ НАЗВАНИЕ ОТРЯДА ──────────────────────
	# Здесь стояло «★ Ветеран 2 — выберите награду (ещё 1)». Владелец вычеркнул
	# именно ЭТО: то же самое нарисовано лычками на флажках рядом, только
	# словами и в две строки, отчего колонка подписи распухала.
	#
	# А ВОТ НАЗВАНИЕ СО ЗВАНИЕМ («Отряд опытных копейщиков») ОСТАЁТСЯ — прямое
	# указание владельца, отданное по ходу правки: «эти надписи не надо ни в
	# коем случае убирать». Его ставит вызывающий (_maybe_add_stance_buttons),
	# и здесь мы его больше не перетираем: подпись живёт своей жизнью, флажки —
	# своей, строкой ниже
	_show_vet_rank_row(lvl)
	for i in range(choices.size()):
		var c: Dictionary = choices[i]
		var idx := i
		var b: Button = _cmd(String(c.get("name", "+")), VET_BTN_COLOR,
			func(): _on_veteran_pressed(squad_id, idx),
			String(c.get("icon", "")), {}, float(BTN_SIZE) * VET_BTN_SCALE, 1.0, false,
			func(): _on_vet_hover(squad_id, c), _on_vet_unhover)
		if b != null:
			_style_vet_button(b)
		# ── ОБУЧАЮЩАЯ ВСПЫШКА ──────────────────────────────────────────────
		# Один импульс на открытие панели: кнопки награды ярко вспыхивают и
		# гаснут. Смысл ровно обучающий — новичок не догадывается, что здесь
		# ЖДУТ его клика, и панель для него выглядит просто ещё одним рядом
		# иконок. Цикла тут быть не должно: мигающая без конца панель под рукой
		# раздражает, в отличие от алерта в углу экрана, который для того и висит
		if b != null:
			_flash_pulses(b, float(i) * VET_FLASH_STAGGER)

## Насколько ярче обычного вспыхивает кнопка награды
const VET_FLASH_PEAK := 2.4
## Сколько длится вспышка (вверх и обратно)
const VET_FLASH_TIME := 0.16
## Сдвиг между соседними кнопками: волна слева направо читается как «вот этот
## РЯД ждёт выбора», тогда как пять одновременных вспышек — как сбой отрисовки
const VET_FLASH_STAGGER := 0.05
## СКОЛЬКО РАЗ ПОВТОРИТЬ (заказ владельца: «от пяти до десяти»). Берём середину
## вилки: восемь импульсов с паузой ниже — это около сорока секунд, за которые
## награду выбирают заведомо
const VET_FLASH_REPEATS := 8
## Пауза между вспышками, секунды (заказ владельца — пять)
const VET_FLASH_PERIOD  := 5.0

## ПОВТОРЯЮЩАЯСЯ ВСПЫШКА узла: VET_FLASH_REPEATS импульсов с паузой
## VET_FLASH_PERIOD между ними. Пивот ставится в центр, иначе увеличение
## масштаба тянет кнопку из своего места в сетке.
##
## Твин привязан к САМОЙ КНОПКЕ: панель пересобирается и при клике по награде,
## и при любой смене выделения, и вместе с кнопкой уходит её твин —
## останавливать его вручную не надо и негде. Пауза стоит ПОСЛЕ импульса, а не
## до: первая вспышка обязана случиться сразу, иначе панель откроется молча
func _flash_pulses(node: Control, delay: float) -> void:
	node.pivot_offset = node.custom_minimum_size * 0.5
	var tw := node.create_tween()
	tw.set_parallel(false)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_loops(VET_FLASH_REPEATS)
	tw.tween_property(node, "modulate", Color(VET_FLASH_PEAK, VET_FLASH_PEAK,
		VET_FLASH_PEAK, 1.0), VET_FLASH_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate", Color.WHITE, VET_FLASH_TIME * 1.6) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_interval(maxf(VET_FLASH_PERIOD - VET_FLASH_TIME * 2.6, 0.1))

# ═════════════════════════════════════════════════════════════════════════════
# НАГРАДА ВЕТЕРАНСТВА: КНОПКА, ПЛАШКА И ПРЕДПРОСМОТР
# ═════════════════════════════════════════════════════════════════════════════
# Здесь стоял _veteran_card — данные для ОБЩЕЙ большой карточки (_show_card).
# Она печатала четыре служебные строки: «Награда за уровень 1», «+1 к урону
# каждой модели», «Убийств отряда: 87», «Уже выбрано: ❯❯». Владелец вычеркнул
# все четыре: первая повторяет флажки ранга слева, вторая врала о наборе
# (награда даёт НЕСКОЛЬКО модификаторов, а строка печатала только первый),
# третья дублирует шкалу опыта, четвёртая — значок на портрете.
#
# Вместо неё две вещи, и обе читают ОДИН источник — набор модификаторов записи
# в unit_stats_config:
#   • миниатюрная плашка справа от панели (см. _show_vet_tip): иконка + список
#     «+15 HP», «+0,1 PUSH», «+0,5 MORALE»;
#   • предпросмотр в таблице статов слева (см. _preview_stats): будущие числа
#     дописываются зелёным прямо в свои строки.
# Правка чисел в конфиге доезжает в оба места сама: ни одно из них не хранит
# ни копии значений, ни своего списка характеристик.

## Крупнее обычной кнопки приказа на 40% (заказ владельца)
const VET_BTN_SCALE := 1.4
## Заливка кнопки награды: тёмное золото, чтобы иконка читалась как «награда»
const VET_BTN_COLOR := Color(0.30, 0.24, 0.06)
## ТОНКАЯ КВАДРАТНАЯ РАМКА, РОВНО В ДВА ПИКСЕЛЯ (заказ владельца по скриншоту:
## «жёлтую обводку вокруг иконок свести к тонкой линии в 2 px»). Три пикселя на
## кнопке в 29 px — это пятая часть её стороны, и на экране читалась именно
## рамка, а не картинка внутри. Число ОДНО и на награды, и на подсветку
## активной кнопки (ACTIVE_BORDER_W): «жёлтый кант» обязан быть одной толщины
## во всей панели, иначе иконки перестают читаться как один набор
const VET_BTN_BORDER_W := 2
const VET_BTN_BORDER   := Color(0.95, 0.78, 0.30)

## ── СТИЛЬ КНОПКИ НАГРАДЫ ───────────────────────────────────────────────────
## Ставится ПОВЕРХ того, что выдал _cmd. Своей ветки в _cmd для этого заводить
## нельзя: там стиль общий на все кнопки панели, и «квадратная рамка у наград»
## расползлась бы на стойки, найм и приказы
func _style_vet_button(btn: Button) -> void:
	var sn := StyleBoxFlat.new()
	sn.bg_color = VET_BTN_COLOR
	_borders(sn, VET_BTN_BORDER_W)
	sn.border_color = VET_BTN_BORDER
	_corners(sn, 0)                       # КВАДРАТНАЯ, без скруглений
	var sh := sn.duplicate() as StyleBoxFlat
	# Наведение — то самое «золотистое свечение»: светлеет заливка и рамка,
	# толщина не растёт (иначе кнопка дёргается под курсором)
	sh.bg_color = VET_BTN_COLOR.lightened(0.22)
	sh.border_color = Color(1.0, 0.92, 0.60)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sn)

# ── ФЛАЖКИ РАНГА ВМЕСТО ЗАГОЛОВКА ────────────────────────────────────────────
# «[флаг с 1 лычкой] → [флаг с 2 лычками]»: чем отряд был и чем станет. Картинки
# — ТЕ ЖЕ, что висят на копье знаменосца в мире (BannerArt), а не отдельный
# набор значков: разойтись они не могут по построению.
#
# Из холста берётся только полотнище с куском древка: BannerArt рисует знамя во
# весь рост (128×160), и в строку панели такая картинка входит спичкой
## −30% ПО ЗАКАЗУ ВЛАДЕЛЬЦА (было 26). Флажок ранга на плашке отряда занимал
## почти всю строку подписи и спорил за внимание с самим названием отряда
const VET_FLAG_H := 18.0
## Прямоугольник холста BannerArt, в котором лежит само полотнище обычного
## знамени (вымпел/гвидон/штандарт шкалы). У красного штандарта элиты обрезок
## свой — узкая высокая полоса вокруг древка (BannerArt.vexillum_crop);
## прежние вымпелы возвращены ТЗ 13.10.2026 (письмо 7), штандарт — только
## отряду с индивидуальным званием (GameManager.squad_elite)
const VET_FLAG_CROP := Rect2(6, 12, 92, 52)

var _vet_rank_row: HBoxContainer = null

func _hide_vet_rank_row() -> void:
	if _vet_rank_row != null and is_instance_valid(_vet_rank_row):
		_vet_rank_row.visible = false
		# remove_child ДО queue_free: освобождение отложено до конца кадра, и
		# без этого одноимённые новые флажки уникализировались бы (VetFlag_2@2),
		# а стенд ищет их по имени
		for c in _vet_rank_row.get_children():
			_vet_rank_row.remove_child(c)
			c.queue_free()

## lvl — уровень, награду за который отряд сейчас выбирает
func _show_vet_rank_row(lvl: int) -> void:
	if _vet_rank_row == null or not is_instance_valid(_vet_rank_row):
		return
	_hide_vet_rank_row()
	_vet_rank_row.visible = true
	# ПОДПИСЬ ОТРЯДА НЕ ПРЯЧЕТСЯ. Первая версия гасила её целиком (в макете
	# владельца на её месте стоят флажки), и он тут же поправил: «отряд опытных
	# копейщиков» и прочие звания убирать нельзя ни в коем случае. Флажки встают
	# ПОД подписью, а не вместо неё
	# Первый уровень: «было» показывать нечем — отряд до него не имел знамени
	# вовсе, и рисовать пустую рамку со стрелкой значило бы врать
	if lvl > 1:
		_vet_rank_row.add_child(_vet_flag(lvl - 1, 0.75))
		var arrow := Label.new()
		arrow.text = "➜"
		arrow.add_theme_font_size_override("font_size", 15)
		arrow.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vet_rank_row.add_child(arrow)
	_vet_rank_row.add_child(_vet_flag(lvl, 1.0))

## Флажок ранга: обрезок холста знамени, вписанный по высоте строки.
## alpha < 1 — прежний ранг: он уже не новость, и спорить за внимание с новым
## флажком ему незачем
## elite — флажок штандарта индивидуального звания (та же картинка, что над
## знаменосцем, свой обрезок холста)
func _vet_flag(lvl: int, alpha: float, h: float = VET_FLAG_H, elite: bool = false) -> Control:
	var tr := TextureRect.new()
	tr.name = "VetFlag_%d" % lvl
	var full: Texture2D = _BannerArt.elite_texture(1, lvl) if elite else _BannerArt.texture_for(lvl)
	# Легендарный золотой квадрат выше вымпела — свой обрезок (crop_for)
	var crop: Rect2 = _BannerArt.elite_crop() if elite else _BannerArt.crop_for(lvl)
	if full != null:
		var at := AtlasTexture.new()
		at.atlas = full
		at.region = crop
		tr.texture = at
	tr.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate.a = alpha
	var w: float = h * (crop.size.x / crop.size.y)
	tr.custom_minimum_size = Vector2(w, h)
	return tr

# ── МИНИАТЮРНАЯ ПЛАШКА НАГРАДЫ ───────────────────────────────────────────────
## ── ПЛАШКА СЖАТА (заказ владельца по скриншоту 4) ──────────────────────────
## Было: кегль 13, иконка 52, зазор строк 2 — плашка вытягивалась выше самой
## панели отряда, а строки «+0,2 ATTACK SPEED» не влезали в её ширину. Стало:
## кегль 11, иконка 44, строки вплотную. Раскладка та же и была — «иконка
## слева, текст справа», — менялись только числа.
## Ширина взята под самую длинную подпись из MOD_SHORT_LABELS
const VET_TIP_W    := 186.0
const VET_TIP_ICON := 44.0
## Кегль строки модификатора в плашке
const VET_TIP_FONT := 11
## Зазор между правым краем нижней панели и плашкой
const VET_TIP_GAP  := 10.0

## Короткая подпись характеристики в плашке. ЗДЕСЬ, А НЕ В КОНФИГЕ: это способ
## НАЗВАТЬ число в интерфейсе, а конфиг отвечает за само число. Ключи — те же,
## что у модификаторов, поэтому новая строка в конфиге просто получит свою
## подпись, а не потребует правки в двух местах
## ── ПОДПИСИ ВЫВЕДЕНЫ ИЗ ТЕХ ЖЕ СЛОВ, ЧТО И СТРОКИ ТАБЛИЦЫ ──────────────────
## Было «RATE» и «SPREAD» — владелец справедливо назвал их непонятными: «RATE»
## это не темп и не перезарядка, а неизвестно что, и в таблице статов такой
## строки не было вовсе. Теперь подпись плашки берётся из STAT_ROW_LABELS
## (капсом), то есть плашка и таблица не могут назвать одно число по-разному
const MOD_SHORT_LABELS := {
	"bonus_attack": "ATTACK", "bonus_armor": "ARMOR", "bonus_defense": "DEFENSE",
	"bonus_health": "HEALTH", "bonus_speed": "SPEED", "bonus_range": "RANGE",
	# ИМЯ ТО ЖЕ, ЧТО В СТРОКЕ ТАБЛИЦЫ: плашка награды и таблица статов стоят на
	# экране ОДНОВРЕМЕННО, и назвать одно число двумя словами нельзя
	"bonus_cooldown": "ИНТЕРВАЛ АТАКИ", "bonus_spread": "SPREAD",
	"bonus_push": "PUSH", "bonus_morale": "MORALE",
	"bonus_carry": "CARRY", "bonus_gather": "GATHERING", "bonus_build": "BUILDING",
	# ── ЭКОНОМИКА (ТЗ 23.09.2026) ─────────────────────────────────────────
	"bonus_gather_wood": "ДОБЫЧА ДЕРЕВА", "bonus_gather_stone": "ДОБЫЧА КАМНЯ",
	"bonus_gather_gold": "ДОБЫЧА ЗОЛОТА", "bonus_gather_food": "РАЗДЕЛКА МЯСА",
	"bonus_carry_pct": "ГРУЗ, ДОЛЯ", "bonus_walk_pct": "ХОДЬБА, ДОЛЯ",
	"bonus_walk_loaded_pct": "ХОД С ГРУЗОМ, ДОЛЯ",
	"bonus_meat_pct": "ВЫХОД МЯСА, ДОЛЯ", "bonus_research_pct": "ТЕМП ИССЛЕДОВАНИЙ, ДОЛЯ",
	"bonus_hire_cost": "ЦЕНА НАЙМА РАБОЧЕГО", "bonus_train_army": "ОБУЧЕНИЕ ВОЙСК",
	"bonus_heal_rate": "ТЕМП ЛЕЧЕНИЯ", "bonus_heal_amount": "ОБЪЁМ ЛЕЧЕНИЯ",
	"bonus_heal_radius": "РАДИУС ЛЕЧЕНИЯ",
	"bonus_train": "ОБУЧЕНИЕ",
	"bonus_aura_armor": "АУРА: БРОНЯ", "bonus_aura_attack": "АУРА: УДАР",
	"bonus_aura_rate": "АУРА: ТЕМП СТРЕЛЬБЫ", "bonus_aura_radius": "АУРА: РАДИУС",
	# ── ВЕТКА ЛУЧНИКА (ТЗ 14.09.2026) ─────────────────────────────────────
	"bonus_cooldown_pct": "ПЕРЕЗАРЯДКА, ДОЛЯ", "bonus_armor_pen": "БРОНЕПРОБИТИЕ",
	"bonus_giant": "УРОН ПО КРУПНЫМ", "bonus_giant_melee": "КОПЬЁМ ПО КРУПНЫМ", "bonus_snipers": "СНАЙПЕРОВ",
	"bonus_snipe_cd": "ПЕРЕЗАРЯДКА СНАЙПЕРА",
}

var _vet_tip: Control = null

## Число со знаком и запятой в дробной части: «+15», «+0,5», «−0,1».
## Целое печатается без хвоста «,0» — «+15,0 HP» читается как опечатка
func _mod_amount(v: float) -> String:
	var s: String = ("%.0f" % v) if absf(v - roundf(v)) < 0.001 else ("%.1f" % v)
	s = s.replace(".", ",")
	return s if s.begins_with("-") else "+" + s

func _hide_vet_tip() -> void:
	if _vet_tip != null and is_instance_valid(_vet_tip):
		_vet_tip.queue_free()
	_vet_tip = null

## Наведение на награду: плашка справа + предпросмотр в таблице статов.
## Одно событие — два следствия, и оба снимаются одним _on_vet_unhover
func _on_vet_hover(squad_id: int, choice: Dictionary) -> void:
	# Таблица статов — экран предпросмотра: показывается на время наведения
	_stat_hover_vet = true
	_refresh_stat_visibility()
	_show_vet_tip(choice)
	_preview_stats(choice)

func _on_vet_unhover() -> void:
	_hide_vet_tip()
	_clear_stat_preview()
	_stat_hover_vet = false
	_refresh_stat_visibility()

## ПЛАШКА: иконка и список того, что награда реально даёт. Всё содержимое —
## ненулевые модификаторы записи, то есть ровно конфиг и ничего кроме
func _show_vet_tip(choice: Dictionary) -> void:
	_hide_vet_tip()
	var mods: Dictionary = _UCfg.nonzero_modifiers(choice)
	if mods.is_empty():
		return
	var panel := PanelContainer.new()
	panel.name = "VetTip"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.10, 0.96)
	_borders(st, 2); _corners(st, 6)
	st.border_color = VET_BTN_BORDER
	st.content_margin_left = 6; st.content_margin_right = 6
	st.content_margin_top  = 4; st.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(VET_TIP_W, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var tex: Texture2D = _icon_texture(String(choice.get("icon", "")))
	if tex != null:
		var frame := Control.new()
		frame.custom_minimum_size = Vector2(VET_TIP_ICON, VET_TIP_ICON)
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.add_child(_stretched_icon(tex))
		row.add_child(frame)

	var col := VBoxContainer.new()
	col.name = "VetTipStats"
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	for k in _UCfg.BONUS_KEYS:
		var key: String = String(k)
		if not mods.has(key):
			continue
		var lb := Label.new()
		# ЗНАК — ПО СМЫСЛУ, А НЕ ПО ЗНАКУ В КОНФИГЕ (см. NEGATIVE_STATS).
		# Плашка и таблица статов стоят на экране ОДНОВРЕМЕННО, и один и тот же
		# модификатор не имеет права показываться в них с разными знаками:
		# у задержки удара и разброса прибавка конфига ВЫЧИТАЕТСЯ
		var amt: float = float(mods[key])
		if NEGATIVE_STATS.has(_UCfg.modifier_stat_name(key)):
			amt = -amt
		lb.text = "%s %s" % [_mod_amount(amt),
			String(MOD_SHORT_LABELS.get(key, key.to_upper()))]
		lb.add_theme_font_size_override("font_size", VET_TIP_FONT)
		lb.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(lb)

	# ── СПРАВА ОТ ПАНЕЛИ, ПО ЕЁ НИЖНЕЙ КРОМКЕ ──────────────────────────────
	# Общее правило интерфейса «окно строго над кнопкой» здесь не годится: над
	# рядом наград висит таблица статов, и плашка легла бы прямо на неё — а
	# именно в таблице сейчас идёт предпросмотр, ради которого игрок и навёл
	# курсор. Поэтому плашка уходит вбок, за правый край панели
	var left_x: float = PANEL_LEFT + 260.0
	if _bottom_panel != null and is_instance_valid(_bottom_panel):
		left_x = _bottom_panel.get_global_rect().end.x + VET_TIP_GAP
	var vp: Vector2 = get_viewport().get_visible_rect().size
	left_x = clampf(left_x, PANEL_LEFT, maxf(vp.x - VET_TIP_W - TIP_SCREEN_PAD, PANEL_LEFT))
	_vet_tip = panel
	await _pin_floater_above(panel, -float(PANEL_BOTTOM_GAP), left_x, VET_TIP_W)

# ── ПРЕДПРОСМОТР БУДУЩИХ СТАТОВ ──────────────────────────────────────────────
# Заказ владельца: «при наведении на награду в таблице слева после жёлтых итогов
# подставляются будущие значения подсвеченным цветом; увёл курсор — исчезли;
# кликнул — зафиксировались».
#
# Фиксировать отдельно ничего не надо и НЕЛЬЗЯ: клик применяет награду, панель
# пересобирается штатным show_selection, и числа приходят уже настоящими — из
# полей бойца. Любая «фиксация» предпросмотра была бы вторым источником правды
# о статах и разъехалась бы с первым в тот же день.
## Цвет будущего значения: зелёный ярче обычного прироста (BONUS_COLOR), чтобы
## отличаться от уже полученных слагаемых в той же строке
const PREVIEW_COLOR := "#5cff8c"

func _clear_stat_preview() -> void:
	for tw in _stat_pulse:
		if tw != null and (tw as Tween).is_valid():
			(tw as Tween).kill()
	_stat_pulse.clear()
	stat_rows_lit = 0
	for k0 in _stat_names:
		for c in [_stat_names[k0], _stat_rows.get(k0)]:
			if c != null and is_instance_valid(c):
				(c as CanvasItem).modulate = Color.WHITE
	for k in _stat_base:
		var rt = _stat_rows.get(k)
		if rt != null and is_instance_valid(rt):
			rt.text = String(_stat_base[k])
	for k2 in _stat_bars:
		var b = _stat_bars[k2]
		if b != null and is_instance_valid(b):
			b.set_preview(0.0)

## Модификаторы ветки рабочего, которые идут ДОЛЕЙ, и строка таблицы под них
const WORKER_PCT_MODS := {"bonus_carry_pct": "carry",
	"bonus_walk_loaded_pct": "speed", "bonus_build": "build"}
## Подсветка растущей строки: мягкая пульсация подписи и итога
const STAT_PULSE_COLOR := Color(1.0, 1.0, 0.55)
const STAT_PULSE_SEC := 0.45

## ПОДСВЕТКА ПРИРАСТАЮЩИХ СТРОК (ТЗ 24.10.2026, блок 7): при наведении на
## улучшение строки, которые оно растит, пульсируют — глаз находит их сразу,
## а не ищет зелёную цифру в конце одной из девяти строк
func _pulse_stat_row(stat: String) -> void:
	stat_rows_lit += 1
	for c in [_stat_names.get(stat), _stat_rows.get(stat)]:
		if c == null or not is_instance_valid(c):
			continue
		var tw := (c as Node).create_tween()
		tw.set_loops()
		tw.tween_property(c, "modulate", STAT_PULSE_COLOR, STAT_PULSE_SEC)
		tw.tween_property(c, "modulate", Color.WHITE, STAT_PULSE_SEC)
		_stat_pulse.append(tw)

func _preview_stats(choice: Dictionary) -> void:
	_clear_stat_preview()
	if _stat_rows.is_empty():
		return
	for key in _UCfg.nonzero_modifiers(choice):
		var stat: String = _UCfg.modifier_stat_name(String(key))
		# Ветка рабочего — ДОЛЯМИ: +25 % груза, а не «+0,3»
		var pct: bool = WORKER_PCT_MODS.has(String(key))
		if pct:
			stat = String(WORKER_PCT_MODS[String(key)])
		var rt = _stat_rows.get(stat)
		if rt == null or not is_instance_valid(rt):
			continue          # у этой строки нет своего поля в таблице
		_pulse_stat_row(stat)
		if pct:
			var base_v: float = float((_stat_nums.get(stat, [0.0]) as Array)[0])
			var pv: float = float(choice[key])
			rt.text = String(_stat_base.get(stat, rt.text)) + " [color=%s]+%d%%[/color]" % [
				PREVIEW_COLOR, roundi(pv * 100.0)]
			var pbar = _stat_bars.get(stat)
			if pbar != null and is_instance_valid(pbar):
				pbar.set_preview(base_v * pv)
			continue
		# ЗНАК — ПО СМЫСЛУ ХАРАКТЕРИСТИКИ, А НЕ ПО ЗНАКУ В КОНФИГЕ.
		# У перезарядки и разброса прибавка ВЫЧИТАЕТСЯ (см. NEGATIVE_STATS), и
		# «+0,2» в строке темпа игрок прочёл бы как «бьёт реже»
		var amount: float = float(choice[key])
		if NEGATIVE_STATS.has(stat):
			amount = -amount
		rt.text = String(_stat_base.get(stat, rt.text)) + " [color=%s]%s[/color]" % [
			PREVIEW_COLOR, _mod_amount(amount)]
		# И полоска: плюс вытягивается фиолетовым, минус подсвечивается красным
		# (у «меньше — лучше» срез — это плюс к полоске остатка со знаком минус:
		# полоска остатка укорачивается, то есть красная накладка)
		var bar = _stat_bars.get(stat)
		if bar != null and is_instance_valid(bar):
			bar.set_preview(-amount if NEGATIVE_STATS.has(stat) else amount)

## ── ВЫБОР НАГРАДЫ ИЗ УКРЕПЛЕНИЯ (ТЗ 19.09.2026, блок 4.1) ─────────────────
## Отряд в башне / бараках / крепости выделить нельзя (укрытые бойцы не
## попадают в selected_units), и панель награды для него не появлялась,
## пока он не выйдет. Панель здания показывает её сама: первый отряд
## гарнизона с невыбранной наградой — таблица статов и карточки выбора,
## клик применяет награду и пересобирает панель здания (следующий отряд)
var garrison_vet_menus: int = 0
func _garrison_vet_menu(c: Castle) -> void:
	if c == null or not is_instance_valid(c):
		return
	for rec in c.garrison:
		var sid: int = int((rec as Dictionary).get("sid", 0))
		if sid <= 0 or GameManager.squad_pending(sid) <= 0:
			continue
		var men: Array = GameManager.squad_members(sid)
		if men.is_empty():
			continue
		garrison_vet_menus += 1
		_show_stat_panel(sid, men)
		_build_veteran_menu(sid, men)
		return

func _on_veteran_pressed(squad_id: int, choice_index: int) -> void:
	if not GameManager.apply_veteran_choice(squad_id, choice_index):
		return
	var main := GameManager.main
	if main != null and main.selection_manager != null:
		# Перерисовать: остались ли ещё награды, обновились ли числа статов
		show_selection(main.selection_manager.selected_units)

## Подпись типа отряда для панели ("Копейщики", "Лучники", ...)
func _squad_title(unit_id: String) -> String:
	match unit_id:
		"spearman": return "Отряд копейщиков"
		"archer":   return "Отряд лучников"
		"warrior":  return "Отряд мечников"
		"worker":   return "Рабочий"
	return "Отряд"

## ── НАЗВАНИЕ ОТРЯДА СО ЗВАНИЕМ: «Отряд закалённых лучников» ────────────────
## Заказ владельца: в заголовках вместо «Отряд лучников ❯❯» должно стоять
## «Отряд закалённых лучников». Лычки — значок для ПОРТРЕТА и КАРТОЧКИ, где на
## текст нет места; в заголовке место есть, и звание там читается словами.
##
## Строка собирается в конфиге (veteran_rank_name): ранг берётся из таблицы
## грейдов, существительное — из STATS.name_genitive_plural того же рода войск.
## Здесь её не составляют по кусочкам намеренно — иначе список званий оказался
## бы в двух местах и разъехался бы при первой правке.
##
## Ранга нет (или род войск вне ветеранства — рабочий) — остаётся прежнее имя
func _squad_title_ranked(unit_id: String, lvl: int) -> String:
	if lvl > 0:
		var named: String = _UCfg.veteran_rank_name(unit_id, lvl)
		if named != "":
			return named
	return _squad_title(unit_id)

func _on_stance_pressed(sm, stance_id: String) -> void:
	sm.set_selection_stance(stance_id)
	show_selection(sm.selected_units)   # перерисовать: подсветка активной стойки

# ─────────────────────────────────────────────────────────────────────────────
# ПАНЕЛЬ РАБОЧЕГО: что он умеет строить.
# Список берётся из GameManager.worker_buildings() — добавили туда запись,
# кнопка появилась сама, править HUD не нужно.
# ─────────────────────────────────────────────────────────────────────────────
# Только оттенок кнопки. Иконка приходит из BUILDINGS[*].icon — своей таблицы
# картинок здесь больше нет: прежний фолбэк указывал руднику на House1.png,
# то есть на картинку ДОМА, и при отсутствии icon в конфиге дал бы чужой рисунок
const _WORKER_BUILD_COLORS := {
	"castle":   Color(0.12, 0.18, 0.30),
	"barracks": Color(0.22, 0.20, 0.32),
	"archery":  Color(0.16, 0.26, 0.14),
	"tower":    Color(0.16, 0.20, 0.30),
	"smithy":   Color(0.28, 0.20, 0.10),
	"mine":     Color(0.28, 0.22, 0.14),
	"sheep_pen": Color(0.30, 0.26, 0.16),
	"market":   Color(0.30, 0.22, 0.14),
	"storehouse": Color(0.24, 0.22, 0.16),
	"house":    Color(0.26, 0.24, 0.18),
	"house2":   Color(0.26, 0.24, 0.18),
	"house3":   Color(0.26, 0.24, 0.18),
}

## Все выделенные — рабочие игрока? Тогда это артель, и ей положена
## панель построек. Хоть один чужой/не-рабочий — пустой список
func _player_worker_crew(units: Array) -> Array:
	var crew: Array = []
	for u in units:
		if not is_instance_valid(u):
			return []
		if not (u is Worker) or u.faction != Constants.FACTION_PLAYER:
			return []
		crew.append(u)
	return crew

# crew — вся артель, которую надо отправить на фундамент (пусто = один worker)
func _build_worker_menu(worker: Worker, crew: Array = [], size: float = 0.0,
		icon_boost: float = 1.0) -> void:
	# Каталог построек рабочего живёт в GameManager.worker_buildings() (кэш поверх
	# unit_stats_config.BUILDINGS). Раньше это была константа WORKER_BUILDINGS —
	# после переноса в метод обращение по старому имени падало SCRIPT ERROR,
	# и панель артели оставалась пустой
	var catalog: Dictionary = GameManager.worker_buildings()
	var build_btns: Array = []
	for build_id in catalog:
		var bid: String = String(build_id)
		# ОДНА КНОПКА «ДОМ» (ТЗ 11.10.2026): ракурс дома выбирает установка
		# (GameManager.next_house_variant), house2/house3 кнопок не получают
		if _UCfg.is_house(bid) and bid != "house":
			continue
		var d: Dictionary = catalog[bid]
		# У крепости цена прогрессивная (ТЗ 14.09.2026): читаем через GameManager
		var cost: Dictionary = GameManager.build_cost_for(worker.faction, bid)
		# ── ФОН КНОПКИ — ДОСТУПНОСТЬ, И ЖИВОЙ (ТЗ 19.09.2026-3, п. 1) ────
		# Зелёный BUILD_OK_BG, если хватает, красный BUILD_LACK_BG, если нет;
		# перекрашивается по сигналу resources_changed через тот же реестр
		# _afford_watch, что у кнопок найма (не хватает — заказ всё равно
		# нажимается и отказывает в try_worker_build с подсказкой)
		var ok0: bool = ResourceManager.can_afford(worker.faction, cost)
		var col: Color = _build_bg(ok0)
		# ── ЗАКРЫТАЯ ПОСТРОЙКА (ТЗ 30.10.2026, ступени разблокировки) ─────
		# Серый фон, приглушённая иконка и полупрозрачный замочек; карточка
		# говорит, что открыть. Клик — плашка-подсказка (try_worker_build)
		var locked: bool = not GameManager.build_unlocked(worker.faction, bid)
		var card: Dictionary = _building_card(bid)
		if locked:
			col = BUILD_LOCK_BG
			card = card.duplicate(true)
			var inf: Array = card.get("info", [])
			inf.append(["Закрыто", GameManager.build_unlock_hint(bid)])
			card["info"] = inf
		# Иконка берётся из конфига здания; цена и темп стройки — в карточке
		var icon: String = String(d.get("icon", ""))
		var btn: Button = _cmd(String(d.get("name", bid)), col,
			func(): GameManager.try_worker_build(worker, bid, crew),
			icon, card, size, icon_boost)
		btn.name = "Build_" + bid
		if locked:
			_lock_build_button(btn)
		else:
			_watch_build_afford(btn, cost, worker.faction, bid)
		build_btns.append(btn)
	# ── «ОТСТУПИТЬ В ЗАМОК» — ЛИЧНАЯ КОМАНДА РАБОЧЕГО (ТЗ 20.10.2026, блок 5) ─
	# Выделенные рабочие бегут в ближайшую крепость и прячутся в её общий
	# слот; колокол тревоги при этом не взводится. Выход — из панели замка
	var who: Array = crew if not crew.is_empty() else [worker]
	var sb: Button = _cmd("В замок", Color(0.30, 0.24, 0.14),
		func(): _on_workers_shelter(who), "", {"title": "Укрыться в замке",
		"icon_tex": _castle_door_texture(),
		"info": [["Тип", "Приказ рабочим"],
			["Эффект", "бегут в ближайшую крепость и прячутся внутри; груз сдают у ворот"],
			["Выход", "в панели замка: ЛКМ по слоту рабочих — один, ПКМ — все; вышедшие возвращаются к работе"]]},
		size, icon_boost)
	sb.name = "WorkerShelterBtn"
	sb.text = ""
	sb.add_child(_stretched_icon(_castle_door_texture(), BTN_ICON_PAD))
	if _OptSys.worker_grid_panel:
		_worker_grid_order(build_btns, sb, size)

## ── ПАНЕЛЬ РАБОЧЕГО СЕТКОЙ (ТЗ 30.10.2026, скриншот 18:17) ─────────────────
## Постройки — сеткой в WORKER_GRID_COLS колонки, «В замок» — справа в верхнем
## ряду, ниже него пустые ячейки: сетка на WORKER_GRID_COLS + 1 колонку
const WORKER_GRID_COLS := 3
const BUILD_LOCK_BG := Color(0.22, 0.23, 0.26)
const LOCK_ICON_ALPHA := 0.85
const LOCK_DIM := Color(0.55, 0.55, 0.58, 0.75)

func _worker_grid_order(build_btns: Array, door: Button, side: float) -> void:
	var all: Array = build_btns.duplicate()
	for b in all:
		button_container.remove_child(b)
	button_container.remove_child(door)
	var rows: int = maxi(1, int(ceil(float(all.size()) / float(WORKER_GRID_COLS))))
	var k := 0
	for r in range(rows):
		for _c in range(WORKER_GRID_COLS):
			if k < all.size():
				button_container.add_child(all[k])
			else:
				button_container.add_child(_grid_spacer(side))
			k += 1
		if r == 0:
			button_container.add_child(door)
		else:
			button_container.add_child(_grid_spacer(side))

func _grid_spacer(side: float) -> Control:
	var c := Control.new()
	c.name = "GridSpacer"
	c.custom_minimum_size = Vector2(side, side)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Замочек поверх закрытой постройки: иконка приглушена, замок в правом
## нижнем углу — полупрозрачный, без размытия
func _lock_build_button(btn: Button) -> void:
	btn.set_meta("locked", true)
	for ch in btn.get_children():
		if ch is TextureRect:
			(ch as TextureRect).modulate = LOCK_DIM
	var lk := TextureRect.new()
	lk.name = "LockIcon"
	lk.texture = _lock_texture()
	lk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lk.modulate = Color(1, 1, 1, LOCK_ICON_ALPHA)
	lk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var s: float = btn.custom_minimum_size.x
	lk.offset_left = s * 0.48
	lk.offset_top = s * 0.44
	lk.offset_right = -s * 0.06
	lk.offset_bottom = -s * 0.06
	btn.add_child(lk)

static var _lock_tex: ImageTexture = null

## Замочек 16×18: дужка и корпус с замочной скважиной, тёмная обводка
static func _lock_texture() -> Texture2D:
	if _lock_tex != null:
		return _lock_tex
	var w := 16
	var h := 18
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color(0.10, 0.08, 0.06, 1.0)
	var metal := Color(0.93, 0.80, 0.42, 1.0)
	var shade := Color(0.74, 0.58, 0.26, 1.0)
	# Дужка: кольцо над корпусом
	for y in range(0, 9):
		for x in range(0, w):
			var dx: float = float(x) - 7.5
			var dy: float = float(y) - 7.5
			var r: float = sqrt(dx * dx + dy * dy)
			if y <= 7 and r >= 3.2 and r <= 6.3:
				img.set_pixel(x, y, edge if (r < 4.1 or r > 5.4) else metal)
	# Корпус
	for y in range(7, h):
		for x in range(1, w - 1):
			var border: bool = y == 7 or y == h - 1 or x == 1 or x == w - 2
			img.set_pixel(x, y, edge if border else (shade if y > h - 5 else metal))
	# Скважина
	for y in range(10, 15):
		img.set_pixel(7, y, edge)
		img.set_pixel(8, y, edge)
	img.set_pixel(6, 11, edge)
	img.set_pixel(9, 11, edge)
	_lock_tex = ImageTexture.create_from_image(img)
	return _lock_tex

## Ступень выросла — открытая панель рабочего перестраивается
func _on_build_unlock_changed(_f: int, _stage: int) -> void:
	if _worker_boost:
		_reselect_now()

## Кнопка НАЙМА: цена, время и размер отряда читаются из конфига
## (unit_stats_config.TRAINING) — и кнопка, и карточка показывают одни числа
## ── ИНДИКАТОР ДОСТУПНОСТИ НА КНОПКЕ НАЙМА (заказ владельца) ──────────────
## Здесь стояло `color.darkened(0.45)`: недоступная кнопка просто темнее.
## На тёмной панели это читается как «иконка потусклее», а не как «денег
## нет», — тем более что у каждого рода войск свой базовый цвет, и «темнее»
## у синего копейщика выглядит не так, как у зелёного рабочего.
##
## Теперь базовый цвет ПОДМЕШИВАЕТСЯ к зелёному или красному. Именно
## подмешивается, а не заменяется: цвет рода войск — способ узнать кнопку с
## одного взгляда, и терять его ради индикатора нельзя. Доля у «нельзя»
## больше, чем у «можно»: доступное состояние обычное и кричать не должно, а
## недоступное обязано останавливать руку
const AFFORD_OK_TINT   := Color(0.16, 0.52, 0.20)
const AFFORD_LACK_TINT := Color(0.55, 0.13, 0.13)
const AFFORD_OK_MIX    := 0.30
const AFFORD_LACK_MIX  := 0.55

func _afford_color(base: Color, ok: bool) -> Color:
	if ok:
		return base.lerp(AFFORD_OK_TINT, AFFORD_OK_MIX)
	return base.lerp(AFFORD_LACK_TINT, AFFORD_LACK_MIX).darkened(0.15)

## Фон кнопки ПОСТРОЙКИ у рабочего — ровно два цвета заказа (ТЗ 19.09.2026-3):
## #2D5A27 «хватает», #5A2727 «не хватает». _style_cmd_button темнит заливку
## на четверть — компенсируем, чтобы на экране стояли числа заказа
const BUILD_OK_BG   := Color("#2D5A27")
const BUILD_LACK_BG := Color("#5A2727")

func _build_bg(ok: bool) -> Color:
	var c: Color = BUILD_OK_BG if ok else BUILD_LACK_BG
	return Color(c.r / 0.75, c.g / 0.75, c.b / 0.75)

## ═══════════════════════════════════════════════════════════════════════════
## РЫЦАРИ КРЕПОСТИ: ОДНА ИКОНКА С ЛЫЧКАМИ И КНОПКА РАНГА [ I ] ПОД НЕЙ
## ═══════════════════════════════════════════════════════════════════════════
## Заказ 13.09.2026 (вторая правка). Первая версия ставила улучшение ранга
## ВТОРОЙ КНОПКОЙ В РЯДУ НАЙМА с той же иконкой Warrior — на панели стояли
## «два рыцаря», покупка была мгновенной и дешёвой (1200 золота при запасе
## 20 000), и три клика по «второму рыцарю» уводили ранг найма в IV: синий
## флаг у первых же рыцарей. Теперь:
##   • иконка рыцаря в ряду ОДНА, лычки ранга нарисованы прямо на ней
##     (_add_rank_chevrons — те же глифы, что у значка ранга в панели отряда);
##   • под ней узкая кнопка [ I ] / [ II ] … (_keep_rank_cmd): клик запускает
##     ИССЛЕДОВАНИЕ (GameManager.keep_vet_buy — золото списано, часы пошли),
##     поверх кнопки крутится круговой радар прогресса (RadarProgress);
##   • цифра меняется по завершении — панель пересобирается по сигналу
##     keep_vet_changed, а не по клику.
## Иконка и кнопка лежат в ОДНОЙ колонке (VBox внутри сетки кнопок): так
## «под иконкой» выполняется по построению, а не подбором отступов.
## Высота кнопки ранга: с иконкой 45 px и просветом колонка обязана уложиться
## в CASTLE_PANEL_H (74) — панель Крепости фиксированного размера (qa_hud5 C1)
const KEEP_RANK_BTN_H := 20.0
const KEEP_RANK_COL_GAP := 2              # просвет иконка — кнопка
const KEEP_RANK_BASE := Color(0.30, 0.24, 0.10)
const KEEP_RANK_DONE := Color(0.20, 0.20, 0.22)
const KEEP_RANK_BUSY := Color(0.22, 0.20, 0.12)
const RANK_CHEVRON_COLOR := Color(1.0, 0.86, 0.36)
const _RadarProgress := preload("res://scripts/RadarProgress.gd")

## Живая кнопка ранга на панели: {btn, radar, faction}; пусто — панель без неё
var _keep_rank_ui: Dictionary = {}

## Колонка «иконка рыцаря + кнопка ранга». Кнопку найма _train_cmd уже
## положил в сетку — переносим её в VBox и ставим VBox на её место
func _knight_column(bld: Building, knight_btn: Button, size: float) -> void:
	if knight_btn == null or not is_instance_valid(knight_btn):
		return
	var idx: int = knight_btn.get_index()
	button_container.remove_child(knight_btn)
	var col := VBoxContainer.new()
	col.name = "KnightColumn"
	col.add_theme_constant_override("separation", KEEP_RANK_COL_GAP)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(knight_btn)
	col.add_child(_keep_rank_cmd(bld, size))
	button_container.add_child(col)
	button_container.move_child(col, idx)

## Лычки ранга ПРЯМО НА ИКОНКЕ найма (верхний левый угол). Глифы — из того же
## veteran_badge_text, что у значка в панели отряда и у флажков наград
func _add_rank_chevrons(btn: Button, vet: int) -> Label:
	var lbl := Label.new()
	lbl.name = "RankChevrons"
	lbl.text = _UCfg.veteran_badge_text(vet)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", RANK_CHEVRON_COLOR)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left = 2
	lbl.offset_top  = 0
	btn.add_child(lbl)
	return lbl

## Кнопка исследования ранга: «[ I ]» — текущий ранг найма. Пока идёт
## исследование — не нажимается, поверх бежит радар; на потолке — подпись
func _keep_rank_cmd(bld: Building, width: float) -> Button:
	var f: int = bld.faction
	var cur: int = GameManager.keep_warrior_vet(f)
	var nxt: int = GameManager.keep_vet_next(f)
	var busy: bool = GameManager.keep_vet_researching(f)
	var btn := QuietTooltipButton.new()
	btn.name = "KeepRankButton"
	btn.custom_minimum_size = Vector2(width, KEEP_RANK_BTN_H)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.clip_contents = true
	btn.text = "[ %s ]" % _UCfg.roman(cur)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.98, 0.92, 0.70))
	btn.add_theme_color_override("font_disabled_color", Color(0.80, 0.76, 0.62))
	var card: Dictionary
	var base: Color = KEEP_RANK_BASE
	if busy:
		var target: int = GameManager.keep_vet_research_target(f)
		btn.tooltip_text = "Ранг рыцарей [ %s ] → [ %s ]: исследуется" % [
			_UCfg.roman(cur), _UCfg.roman(target)]
		card = {"title": btn.tooltip_text,
			"lines": ["Осталось %.0f с" % GameManager.keep_vet_research_left(f),
				"По завершении новые рыцари Крепости выходят рангом %s" % _UCfg.roman(target)]}
		base = KEEP_RANK_BUSY
		btn.disabled = true
	elif nxt == 0:
		btn.tooltip_text = "Ранг рыцарей [ %s ] — предел" % _UCfg.roman(cur)
		card = {"title": btn.tooltip_text,
			"lines": ["Открыт высший ранг найма: %s" % _UCfg.roman(cur),
				"Дальше отряд растёт только в бою"]}
		base = KEEP_RANK_DONE
		btn.disabled = true
	else:
		var cost: Dictionary = GameManager.keep_vet_cost(f)
		btn.tooltip_text = "Исследовать ранг рыцарей [ %s ] → [ %s ]" % [
			_UCfg.roman(cur), _UCfg.roman(nxt)]
		card = {"title": btn.tooltip_text,
			"lines": [
				"Новые рыцари Крепости будут выходить рангом %s (%d %s)" % [
					_UCfg.roman(nxt), nxt, "лычка" if nxt == 1 else "лычки"],
				"Исследование: %.0f с" % GameManager.keep_vet_time(f),
				"Уже нанятые отряды не меняются; рыцари из Бараков — новобранцы",
			],
			"cost": cost}
		_watch_afford(btn, base, cost, f, "", bld)
		base = _afford_color(base, ResourceManager.can_afford(f, cost))
	_style_cmd_button(btn, base, false)
	btn.mouse_entered.connect(func(): _show_card(btn, card))
	btn.mouse_exited.connect(_hide_card)
	btn.tree_exiting.connect(_hide_card)
	btn.pressed.connect(func(): _on_keep_vet_buy(bld))
	# Радар живёт на кнопке всегда, но виден только на время исследования
	var radar: Control = _RadarProgress.new()
	radar.name = "RankRadar"
	radar.visible = busy
	radar.progress = GameManager.keep_vet_progress(f)
	btn.add_child(radar)
	_keep_rank_ui = {"btn": btn, "radar": radar, "faction": f}
	return btn

# ── ТРЕВОГА И УКРЫТИЕ РАБОЧИХ (ТЗ 20.10.2026, блок 5) ────────────────────────
## Колокол: все рабочие бегут в ближайшую крепость, повторный клик — выходят и
## возвращаются к работе. Взведённый колокол — жёлтая рамка. Слот рабочих —
## ОДНА иконка с числом укрытых (и «+N» бегущих): ЛКМ — выпустить одного,
## ПКМ — всех. Число обновляется покадрово без пересборки панели
var _shelter_ui: Dictionary = {}
const ALERT_COL := Color(0.42, 0.30, 0.10)
static var _bell_tex: ImageTexture = null
static var _door_tex: ImageTexture = null

func _on_alert(f: int) -> void:
	GameManager.toggle_worker_alert(f)
	AudioManager.play_ui("alarm_bell")   # мягкий звон (ТЗ 24.10.2026, второе письмо)
	_reselect_now()

# ── КОЛОКОЛ В ПРАВОМ ВЕРХНЕМ УГЛУ ПАНЕЛИ ЗАМКА (ТЗ 21.10.2026) ───────────────
## Было: колокол — кнопкой ряда рядом с наймом, и ещё отдельная кнопка слота
## укрытых рабочих. Стало: одна аккуратная кнопка в углу панели; иконка время
## от времени мягко переливается (взведённая тревога — пульс чаще и ярче).
## Кнопка — НЕ в ряду кнопок: место в ряду расширяло панель замка и сбивало
## центровку найма (qa_hud5 C1/C8г). Она висит на HUD значком НА ВЕРХНЕЙ
## КРОМКЕ рамы в правом углу (часть над рамкой) и каждый кадр ставится по
## панели (_tick_alert_bell); кнопки найма начинаются ниже — не накрывает
## ── ТЗ 22.10.2026, блок 5: КОЛОКОЛ — СТАТИЧНЫЙ КВАДРАТ В САМОМ УГЛУ ────────
## Перелив и свечение сняты (кнопка не мерцает вовсе), круг заменён аккуратным
## квадратом, вписанным в правый верхний угол рамы панели (не над кромкой)
const ALERT_BELL := 24.0
const ALERT_BELL_INSET := 3.0
## Сколько колокола выступает над верхней кромкой панели (0 — внутри рамы)
const ALERT_BELL_LIFT := 0.0
## Перелив снят (ТЗ 22.10.2026); числа оставлены стендам прежних писем
const ALERT_SHIMMER_SEC := 3.2
const ALERT_SHIMMER_LEN := 1.1
var _bell_btn: Button = null
var _bell_glow: Control = null

func _alert_corner(c: Castle) -> void:
	if button_container == null or not is_instance_valid(button_container):
		return
	var f: int = c.faction
	var on: bool = GameManager.worker_alert_on(f)
	_free_alert_bell()
	var btn := Button.new()
	btn.name = "AlertBtn"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(ALERT_BELL, ALERT_BELL)
	btn.size = Vector2(ALERT_BELL, ALERT_BELL)
	var rim: Color = Color(0.98, 0.82, 0.30) if on else Color(0.62, 0.48, 0.22)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.20, 0.13, 0.06, 0.92) if st != "hover" else Color(0.34, 0.23, 0.10, 0.95)
		if st == "pressed":
			sb.bg_color = Color(0.12, 0.08, 0.04, 0.95)
		_borders(sb, 2 if on else 1)
		sb.border_color = rim if st != "hover" else Color(1.0, 0.90, 0.55)
		sb.set_corner_radius_all(3)
		btn.add_theme_stylebox_override(st, sb)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_child(_stretched_icon(_bell_texture(), 2.0))
	var card := {"title": "Тревога! Рабочие в замок" if not on else "Отбой тревоги",
		"icon_tex": _bell_texture(), "status": "взведена" if on else "",
		"status_col": Color(0.98, 0.80, 0.30),
		"info": [["Тип", "Приказ всем рабочим"],
			["Эффект", "бегут в ближайшую крепость и прячутся в ней" if not on
				else "выходят из всех замков и возвращаются к прежней работе"]]}
	btn.mouse_entered.connect(func(): _show_card(btn, card))
	btn.mouse_exited.connect(_hide_card)
	btn.tree_exiting.connect(_hide_card)
	btn.pressed.connect(func(): _on_alert(f))
	add_child(btn)
	_bell_btn = btn
	_bell_glow = null
	_tick_alert_bell()

## Угол и перелив колокола — покадрово, пока панель замка открыта
func _tick_alert_bell() -> void:
	if _bell_btn == null or not is_instance_valid(_bell_btn):
		_bell_btn = null
		return
	if _bottom_panel != null and is_instance_valid(_bottom_panel):
		var r: Rect2 = _bottom_panel.get_global_rect()
		var bx: float = r.end.x - ALERT_BELL - ALERT_BELL_INSET
		var by: float = r.position.y + ALERT_BELL_INSET - ALERT_BELL_LIFT
		# Кнопки найма стоят по нижней кромке и на низкой панели доходят до
		# угла: колокол поднимается над верхней кнопкой своей колонки, чтобы
		# не накрывать её (qa_menu_ui E3) — тогда он ложится на раму
		if button_container != null and is_instance_valid(button_container):
			for b in button_container.get_children():
				var c := b as Control
				if c == null or not c.visible:
					continue
				var cr: Rect2 = c.get_global_rect()
				if cr.end.x > bx and cr.position.x < bx + ALERT_BELL:
					by = minf(by, cr.position.y - ALERT_BELL - 1.0)
		_bell_btn.global_position = Vector2(bx, by)
		_bell_btn.visible = _bottom_panel.is_visible_in_tree()

func _free_alert_bell() -> void:
	if _bell_btn != null and is_instance_valid(_bell_btn):
		_bell_btn.get_parent().remove_child(_bell_btn)
		_bell_btn.queue_free()
	_bell_btn = null
	_bell_glow = null

## Мягкое золотое свечение под колоколом и бегущий по нему блик
class _BellGlow extends Control:
	var sweep: float = 0.0
	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		for i in range(5):
			var k: float = float(i) / 5.0
			draw_circle(c, r * (1.25 - k * 0.5), Color(1.0, 0.80, 0.30, 0.10 + k * 0.08))
		var x: float = lerpf(-r, r, clampf(sweep, 0.0, 1.0))
		draw_line(c + Vector2(x - 4.0, r * 0.6), c + Vector2(x + 4.0, -r * 0.6),
			Color(1.0, 0.98, 0.85, 0.75), 2.0, true)

# ── УКРЫТЫЕ РАБОЧИЕ — МИНИ-СЛОТ В «ГАРНИЗОНЕ» (ТЗ 21.10.2026) ───────────────
## Отдельная крупная кнопка слота из ряда убрана; укрытые рабочие — одним
## слотом в секции «Гарнизон» рядом с отрядами: ЛКМ — выпустить одного,
## ПКМ — всех. Слот есть, пока внутри или в пути хоть один рабочий
func _shelter_mini(c: Castle) -> Control:
	var btn := QuietTooltipButton.new()
	btn.name = "ShelterSlot"
	btn.custom_minimum_size = Vector2(GARRISON_MINI, GARRISON_MINI)
	btn.clip_contents = false
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	var col := Color(0.30, 0.26, 0.10)
	var sn := StyleBoxFlat.new(); sn.bg_color = col.darkened(0.2)
	_borders(sn, 1); _corners(sn, 3)
	sn.border_color = Color(0.92, 0.78, 0.36)
	var sh := StyleBoxFlat.new(); sh.bg_color = col.lightened(0.2)
	_borders(sh, 1); _corners(sh, 3)
	sh.border_color = Color(1.0, 0.92, 0.6)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sn)
	var ipath: String = String(UNIT_ICONS.get("worker", ""))
	if ipath != "" and ResourceLoader.exists(ipath):
		var tex := load(ipath) as Texture2D
		if tex != null:
			btn.add_child(_stretched_icon(tex, 1.0))
	var lbl := Label.new()
	lbl.name = "ShelterCount"
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_right = 2
	lbl.offset_bottom = 3
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)
	btn.pressed.connect(func(): _on_shelter_release(c, 1))
	btn.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_on_shelter_release(c, -1))
	btn.mouse_entered.connect(func(): _show_card(btn,
		{"title": "Рабочие в замке", "icon": ipath,
		 "info": [["ЛКМ", "выпустить одного"], ["ПКМ", "выпустить всех"],
			["После выхода", "возвращаются к прежней работе"]]}))
	btn.mouse_exited.connect(_hide_card)
	btn.tree_exiting.connect(_hide_card)
	_shelter_ui = {"btn": btn, "lbl": lbl, "castle": c, "seen": -1}
	_refresh_shelter_slot()
	return btn

## Сколько рабочих в убежище замка (внутри + в пути); 0 — у здания убежища нет
static func _shelter_total(c: Castle) -> int:
	if c == null or not is_instance_valid(c) or not c.has_method("shelter_count"):
		return 0
	return int(c.call("shelter_count")) + int(c.call("shelter_incoming"))

func _on_workers_shelter(who: Array) -> void:
	if GameManager.shelter_workers(who) > 0:
		AudioManager.play_ui("menu_button")

func _on_shelter_release(c: Castle, n: int) -> void:
	if c == null or not is_instance_valid(c):
		return
	if int(c.call("shelter_release", n)) > 0:
		AudioManager.play_ui("menu_button")
		_refresh_shelter_slot()

func _refresh_shelter_slot() -> void:
	# Слот появляется/исчезает вместе с укрытыми — пересборка панели по смене
	# «есть кто в убежище» (раз на событие, не покадрово)
	var sel = _selected_node
	if sel != null and is_instance_valid(sel) and sel is Castle and (sel as Castle).is_stronghold() 			and (sel as Castle).faction == Constants.FACTION_PLAYER:
		var want: bool = _shelter_total(sel as Castle) > 0
		if want != (not _shelter_ui.is_empty()):
			_shelter_ui.clear()
			_reselect_now()
			return
	_tick_alert_bell()
	if _shelter_ui.is_empty():
		return
	var c = _shelter_ui.get("castle")
	var lbl = _shelter_ui.get("lbl")
	var btn = _shelter_ui.get("btn")
	if c == null or not is_instance_valid(c) or lbl == null or not is_instance_valid(lbl):
		_shelter_ui.clear()
		return
	var inside: int = int(c.call("shelter_count"))
	var going: int = int(c.call("shelter_incoming"))
	var key: int = inside * 1000 + going
	if key == int(_shelter_ui.get("seen", -1)):
		return
	_shelter_ui["seen"] = key
	(lbl as Label).text = (str(inside) if going == 0 else "%d+%d" % [inside, going])
	(lbl as Label).visible = inside > 0 or going > 0
	(btn as Button).modulate = Color(1, 1, 1, 1.0 if inside > 0 else 0.6)

## Колокол, нарисованный кодом (иконки колокола в наборе нет)
static func _bell_texture() -> ImageTexture:
	if _bell_tex != null:
		return _bell_tex
	var n := 32
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var gold := Color(0.95, 0.76, 0.26)
	var dark := Color(0.55, 0.38, 0.10)
	for y in range(5, 25):
		var t: float = float(y - 5) / 19.0
		var half: float = lerpf(4.0, 12.0, pow(t, 1.6))
		for x in range(n):
			var dx: float = absf(float(x) - 15.5)
			if dx <= half:
				img.set_pixel(x, y, dark if dx > half - 1.5 or y >= 23 else gold)
	for x in range(12, 20):
		for y in range(2, 6):
			if Vector2(float(x) - 15.5, float(y) - 4.0).length() <= 3.0:
				img.set_pixel(x, y, dark)
	for x in range(13, 19):
		for y in range(25, 29):
			if Vector2(float(x) - 15.5, float(y) - 26.0).length() <= 2.6:
				img.set_pixel(x, y, dark)
	# Блик
	for y in range(9, 19):
		img.set_pixel(11, y, Color(1, 0.95, 0.75))
	_bell_tex = ImageTexture.create_from_image(img)
	return _bell_tex

## Арка ворот замка — значок команды «в замок» у рабочего
static func _castle_door_texture() -> ImageTexture:
	if _door_tex != null:
		return _door_tex
	var n := 32
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stone := Color(0.70, 0.68, 0.62)
	var shade := Color(0.42, 0.40, 0.36)
	var hole := Color(0.10, 0.07, 0.05)
	for y in range(4, 30):
		for x in range(3, 29):
			var inner: bool = x >= 10 and x <= 21 and y >= 13 \
				and (y >= 18 or Vector2(float(x) - 15.5, float(y) - 18.0).length() <= 6.0)
			var merlon: bool = y < 8 and ((x - 3) / 4) % 2 == 1
			if merlon:
				continue
			img.set_pixel(x, y, hole if inner else (shade if x == 28 or y == 29 else stone))
	_door_tex = ImageTexture.create_from_image(img)
	return _door_tex

# ── КНОПКА «УКРЕПИТЬ БАШНЮ» (ТЗ 20.10.2026, блок 4) ─────────────────────────
## Дерево + камень, ступени — unit_stats_config.TOWER_FORT_LEVELS. Пока идут
## работы — радар поверх кнопки, ПКМ — отменить с возвратом; на пределе кнопка
## гаснет. Укреплённая башня держит больше и получает меньше урона
var _tower_fort_ui: Dictionary = {}
const TOWER_FORT_COL := Color(0.30, 0.28, 0.22)

## Кнопки башни (ТЗ 27.10.2026, второе письмо, п. 7): «Выпустить» и
## «Укрепить» одного размера, иконка вписана в рамку без раздува
const TOWER_BTN_SIZE := 46.0
const TOWER_ICON_BOOST := 1.0

func _tower_fort_cmd(tw: Castle, size: float, icon_boost: float = CASTLE_ICON_BOOST) -> Button:
	var f: int = tw.faction
	var lvl: int = int(tw.get("fort_level"))
	var mx: int = int(tw.call("fort_max"))
	var busy: bool = bool(tw.call("fort_busy"))
	var nxt: Dictionary = tw.call("fort_next")
	var cost: Dictionary = tw.call("fort_cost")
	var base_hp: float = _UCfg.building_stat("tower", "max_hp", 1200.0)
	var card: Dictionary = {"icon": "icon_shield.png",
		"stats": [{"icon": "icon_heart.png", "label": "Прочность",
			"value": "%d" % int(tw.max_health)}]}
	if nxt.is_empty():
		card["title"] = "Башня укреплена полностью"
		card["status"] = "Предел"
		card["status_col"] = UPG_CHECK_COLOR
		card["info"] = [["Тип", "Укрепление"], ["Ступень", "%d из %d" % [lvl, mx]]]
	else:
		card["title"] = "Укрепить: %s" % String(nxt.get("name", ""))
		card["status"] = "Работы идут" if busy else "Ступень %d/%d" % [lvl + 1, mx]
		card["status_col"] = Color(0.56, 0.78, 0.98) if busy else Color(0.80, 0.82, 0.88)
		card["stats"].append({"icon": "icon_heart.png", "label": "Прибавка",
			"value": "+%d" % int(base_hp * float(nxt.get("hp_add", 0.0)))})
		card["stats"].append({"icon": "icon_shield.png", "label": "Урон по башне",
			"value": "−%d %%" % int(round((1.0 - float(nxt.get("dmg_mult", 1.0))) * 100.0))})
		card["info"] = [["Тип", "Укрепление (выживаемость)"],
			["Эффект", "больше прочности, меньше урона под обстрелом и штурмом"],
			["Работы", "%.0f с; гарнизон остаётся внутри%s" % [float(nxt.get("time", 0.0)),
				", ПКМ — отменить" if busy else ""]]]
		if not busy:
			card["cost"] = cost
	var btn := _cmd("Укрепить башню", TOWER_FORT_COL, func(): _on_tower_fort(tw),
		"icon_shield.png", card, size, icon_boost)
	btn.name = "TowerFortBtn"
	btn.disabled = nxt.is_empty() or busy
	if not nxt.is_empty() and not busy:
		_watch_afford(btn, TOWER_FORT_COL, cost, f)
	btn.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT \
				and is_instance_valid(tw) and bool(tw.call("fort_cancel")):
			AudioManager.play_ui("menu_close")
			_reselect_now())
	# Ступень — римской цифрой (видно без наведения). ТЗ 24.10.2026 (второе
	# письмо, блок 4): цифра отодвинута от левого края к центру
	if lvl > 0:
		var rl: Label = _add_rank_chevrons(btn, 0)
		rl.text = _UCfg.roman(lvl)
		rl.offset_left = FORT_ROMAN_INSET
		rl.offset_top = 2
	# Зелёная стрелка апгрейда в правом нижнем углу — есть куда расти; на
	# III (пределе) её нет
	if not nxt.is_empty():
		var ar := TextureRect.new()
		ar.name = "FortUpArrow"
		ar.texture = _upgrade_arrow_texture()
		ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var asz: float = maxf(12.0, size * 0.30)
		ar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		ar.offset_left = -asz - 2.0
		ar.offset_top = -asz - 2.0
		ar.offset_right = -2.0
		ar.offset_bottom = -2.0
		btn.add_child(ar)
	var radar: Control = _RadarProgress.new()
	radar.name = "FortRadar"
	radar.visible = busy
	radar.progress = float(tw.call("fort_progress"))
	btn.add_child(radar)
	_tower_fort_ui = {"btn": btn, "radar": radar, "tower": tw}
	if not tw.is_connected("fortified", _on_tower_fortified):
		tw.connect("fortified", _on_tower_fortified)
	return btn

## Отступ римской цифры ступени от левого края кнопки щита, px
const FORT_ROMAN_INSET := 9.0
static var _up_arrow_tex: ImageTexture = null

## Зелёная стрелка «можно улучшить»: 16×16, тёмная обводка, рисуется один раз
static func _upgrade_arrow_texture() -> ImageTexture:
	if _up_arrow_tex != null:
		return _up_arrow_tex
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var green := Color(0.35, 0.92, 0.32)
	var green_dk := Color(0.16, 0.58, 0.14)
	var line := Color(0.04, 0.10, 0.04, 1.0)
	var fill: Array = []
	for y in range(n):
		for x in range(n):
			var cx: float = float(x) + 0.5 - 8.0
			var yy: float = float(y) + 0.5
			var inside := false
			if yy >= 2.0 and yy <= 8.5:
				inside = absf(cx) <= (yy - 2.0) * 0.95 + 0.5     # наконечник
			elif yy > 8.5 and yy <= 14.0:
				inside = absf(cx) <= 2.6                          # древко
			if inside:
				fill.append(Vector2i(x, y))
				img.set_pixel(x, y, green if cx <= 0.0 else green_dk)
	# Обводка: пустой пиксель рядом с заливкой
	for p in fill:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and img.get_pixelv(q).a == 0.0:
				img.set_pixelv(q, line)
	_up_arrow_tex = ImageTexture.create_from_image(img)
	return _up_arrow_tex

func _on_tower_fort(tw: Castle) -> void:
	if tw == null or not is_instance_valid(tw):
		return
	if bool(tw.call("fort_start")):
		AudioManager.play_ui("smith_pick")
		_reselect_now()

func _on_tower_fortified(_lvl: int) -> void:
	_reselect_now()

## Пересобрать панель текущего выделения (кнопка поменяла состояние)
func _reselect_now() -> void:
	var sm = GameManager.main.selection_manager if GameManager.main != null else null
	if sm != null:
		GameManager.on_selection_changed(sm.selected_units, true)

func _refresh_tower_fort() -> void:
	if _tower_fort_ui.is_empty():
		return
	var radar = _tower_fort_ui.get("radar")
	var tw = _tower_fort_ui.get("tower")
	if radar == null or not is_instance_valid(radar) or tw == null or not is_instance_valid(tw):
		_tower_fort_ui.clear()
		return
	var busy: bool = bool(tw.call("fort_busy"))
	radar.visible = busy
	if busy:
		radar.progress = float(tw.call("fort_progress"))

## Раз в кадр: доля радара по часам исследования (узлы не пересоздаются)
func _refresh_keep_rank() -> void:
	if _keep_rank_ui.is_empty():
		return
	var radar = _keep_rank_ui.get("radar")
	if radar == null or not is_instance_valid(radar):
		_keep_rank_ui.clear()
		return
	var f: int = int(_keep_rank_ui.get("faction", 0))
	var busy: bool = GameManager.keep_vet_researching(f)
	radar.visible = busy
	if busy:
		radar.progress = GameManager.keep_vet_progress(f)

## Ранг сменился (исследование дошло) — панель Крепости пересобирается, чтобы
## цифра на кнопке и лычки на иконке пришли настоящими, из реестра
func _on_keep_vet_changed(faction: int, _level: int) -> void:
	if faction != Constants.FACTION_PLAYER or _keep_rank_ui.is_empty():
		return
	var sm = GameManager.main.selection_manager if GameManager.main != null else null
	if sm != null:
		GameManager.on_selection_changed(sm.selected_units, true)

func _on_keep_vet_buy(bld: Building) -> void:
	if bld == null or not is_instance_valid(bld):
		return
	if GameManager.keep_vet_buy(bld.faction):
		AudioManager.play_ui("smith_pick")
		# Панель пересобирается штатно: кнопка гаснет, радар включается
		var sm = GameManager.main.selection_manager if GameManager.main != null else null
		if sm != null:
			GameManager.on_selection_changed(sm.selected_units, true)

## Ранг, с которым выйдет заказанный отряд (0 — обычный найм).
## Спрашивается СВОЙСТВО здания (is_stronghold), а не его имя: башня и хижина
## орды тоже наследуют Castle, и элиту они не куют
func _keep_vet_for(bld: Building, unit_id: String) -> int:
	if unit_id != "warrior" or bld == null:
		return 0
	if not bld.has_method("is_stronghold") or not bool(bld.call("is_stronghold")):
		return 0
	return GameManager.keep_warrior_vet(bld.faction)

func _train_cmd(bld: Building, unit_id: String, col: Color, size: float = 0.0,
		icon_boost: float = 1.0) -> Button:
	var c: Dictionary = _UCfg.train_cfg(bld.building_id, unit_id)
	if c.is_empty():
		return null
	var cost: Dictionary = _UCfg.train_cost(bld.building_id, unit_id)
	var squad: int = int(c.get("squad", 1))
	# Кнопка краснеет и когда нет денег, и когда упёрлись в лимит населения
	var pop_ok: bool = GameManager.pop_allows(bld.faction, unit_id)
	var color: Color = _afford_color(col,
		ResourceManager.can_afford(bld.faction, cost) and pop_ok)
	var title: String = String(UNIT_TITLES.get(unit_id, unit_id))
	if squad > 1:
		title += " ×%d" % squad
	# ── ЭЛИТА КРЕПОСТИ: РАНГ ВИДЕН ПРЯМО НА КНОПКЕ (заказ 13.09.2026) ──────
	# «Иконка найма должна сразу отображать лычку». Глифы берутся из того же
	# veteran_badge_text, которым рисуется значок ранга в панели отряда и
	# флажки наград: разойтись с знаменем в мире они так не могут
	var keep_vet: int = _keep_vet_for(bld, unit_id)
	var card: Dictionary = _unit_card(unit_id, bld.faction, cost, squad)
	card["title"] = title
	# Ранг — ФЛАГОМ знамени рядом с названием, а не «[ III ] >>I» текстом
	# (ТЗ 29.09.2026, блок 4): тот же холст BannerArt, что у знамени в мире
	if keep_vet > 0:
		card["vet_flag"] = keep_vet
	# ── СТАТУС — В ПЛИТКЕ ИКОНКИ, А НЕ СТРОКАМИ (ТЗ 20.10.2026, блок 3) ─────
	# Сняты «Выходит готовым ветераном: ранг…» (звание — статусом и флажком в
	# плитке) и «Содержание: еды ×… золота …» (расход виден на верхней плашке
	# ресурсов). Лимит рабочих и монахов — тем же статусом, одной цифрой
	card["status"] = _UCfg.rank_title(keep_vet) if unit_id != "worker" and unit_id != "monk" else ""
	if GameManager.pop_limit_enabled and bld.faction == Constants.FACTION_PLAYER \
			and unit_id == "worker":
		card["status"] = "%d / %d" % [GameManager.pop_workers_used(bld.faction),
			GameManager.pop_worker_cap(bld.faction)]
	if unit_id == "monk":
		card["status"] = "не больше %d" % _UCfg.MONK_LIMIT
	# Отказ по лимиту — красная плашка у кнопки (ТЗ 22.10.2026, блок 6):
	# прежде заказ молча не проходил
	var btn := _cmd(title, color, func(): _on_train_click(bld, unit_id),
		String(UNIT_ICONS.get(unit_id, "")), card, size, icon_boost)
	_watch_afford(btn, col, cost, bld.faction, unit_id, bld)
	# ПКМ по иконке снимает последний заказ этого типа и возвращает ресурсы.
	# У Button нет сигнала на правую кнопку, поэтому слушаем сырой ввод
	btn.gui_input.connect(func(e: InputEvent): _on_train_rmb(e, bld, unit_id))
	# ЦИФРА КОЛИЧЕСТВА в углу иконки: сколько заказов этого типа в очереди
	_train_badges[unit_id] = _add_badge(btn)
	# ЛЫЧКИ РАНГА НА САМОЙ ИКОНКЕ (Крепость): «сразу видно, что выходит ветеран»
	if keep_vet > 0:
		_add_rank_chevrons(btn, keep_vet)
	return btn

func _on_train_click(bld: Building, unit_id: String) -> void:
	if bld == null or not is_instance_valid(bld):
		return
	if bld.faction == Constants.FACTION_PLAYER and not GameManager.pop_allows(bld.faction, unit_id):
		_pop_limit_alert(unit_id)
		return
	bld.train_from_config(unit_id)

## ── «ПРЕВЫШЕН ЛИМИТ НАСЕЛЕНИЯ!» (ТЗ 22.10.2026, блок 6) ─────────────────
## Красная плашка у курсора (то есть у нажатой кнопки найма), поднимается и
## гаснет за POP_ALERT_SEC; повторный клик заменяет прежнюю
const POP_ALERT_SEC := 1.8
var _pop_alert: Control = null
var pop_alerts: int = 0      # стендам

func _pop_limit_alert(unit_id: String) -> void:
	var text := "Превышен лимит населения!"
	if unit_id == "worker":
		text = "Превышен лимит рабочих!"
	elif unit_id == "monk" and GameManager.monks_used(Constants.FACTION_PLAYER) >= _UCfg.MONK_LIMIT:
		text = "Монах уже есть (не больше %d)" % _UCfg.MONK_LIMIT
	pop_alerts += 1
	if _pop_alert != null and is_instance_valid(_pop_alert):
		_pop_alert.get_parent().remove_child(_pop_alert)
		_pop_alert.queue_free()
	var pc := PanelContainer.new()
	pc.name = "PopLimitAlert"
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.32, 0.04, 0.04, 0.92)
	sb.border_color = Color(0.95, 0.30, 0.25)
	_borders(sb, 1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.name = "PopLimitText"
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.78))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	pc.add_child(lbl)
	add_child(pc)
	_pop_alert = pc
	var mp: Vector2 = get_viewport().get_mouse_position()
	pc.reset_size()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	pc.position = Vector2(clampf(mp.x - pc.size.x * 0.5, 4.0, vs.x - pc.size.x - 4.0),
		maxf(mp.y - 52.0, 4.0))
	var tw := pc.create_tween()
	tw.tween_property(pc, "position:y", pc.position.y - 16.0, POP_ALERT_SEC)
	tw.parallel().tween_property(pc, "modulate:a", 0.0, POP_ALERT_SEC).set_delay(POP_ALERT_SEC * 0.45)
	tw.tween_callback(pc.queue_free)
	AudioManager.play_ui("menu_close")

## Кнопка ПОСТРОЙКИ из замка: цена и габарит — из конфига
func _build_cmd(build_id: String, col: Color, cb: Callable) -> void:
	var cost: Dictionary = _UCfg.building_cost(build_id)
	var color: Color = _afford_color(col,
		ResourceManager.can_afford(Constants.FACTION_PLAYER, cost))
	var btn := _cmd(String(_UCfg.building_cfg(build_id).get("name", build_id)), color, cb,
		_bld_icon(build_id), _building_card(build_id))
	_watch_afford(btn, col, cost, Constants.FACTION_PLAYER)

func _bld_icon(build_id: String) -> String:
	return String(_UCfg.building_cfg(build_id).get("icon", ""))

# ── ЦИФРА КОЛИЧЕСТВА НА ИКОНКЕ НАЙМА ─────────────────────────────────────────
# Значки живут ровно столько, сколько кнопки: show_selection() пересобирает
# панель и заодно очищает этот словарь
var _train_badges: Dictionary = {}   # unit_id -> Label

## Ярлык в правом нижнем углу кнопки. Прячется, когда заказов нет
func _add_badge(btn: Button) -> Label:
	var lbl := Label.new()
	lbl.text = ""
	lbl.visible = false
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Было 20 — на кнопке 22-34px это была "огромная цифра", закрывавшая саму
	# иконку. 12 всё ещё читается поверх картинки, но не спорит с ней
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.75))
	# Чёрная обводка — цифра читается поверх любой иконки
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	# СТРОГО В НИЖНЕМ ПРАВОМ УГЛУ. Растянутый на всю кнопку Label с выравниванием
	# вправо-вниз прижимает цифру к углу и при этом гарантированно не вылезает за
	# рамку (Control не может быть меньше своего минимального размера, поэтому
	# маленький прямоугольник под цифру распух бы наружу — тот же разбор, что и
	# у _add_done_check). Отступы мелкие: раньше −5 по горизонтали заметно
	# уводило цифру от угла к центру нижней кромки
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_right  = -2
	lbl.offset_bottom = -1
	btn.add_child(lbl)
	return lbl

## ПКМ по иконке найма: −1 к заказу с возвратом ресурсов
func _on_train_rmb(e: InputEvent, bld: Building, unit_id: String) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if bld == null or not is_instance_valid(bld):
		return
	if bld.cancel_order(unit_id):
		AudioManager.play_ui("menu_close")    # отмена заказа (ТЗ 10.10.2026)
		_refresh_train_badges(bld)

## Обновить цифры на иконках. Зовётся каждый кадр из _process — это одна
## проверка на тип юнита, узлы при этом не пересоздаются
func _refresh_train_badges(bld: Building) -> void:
	if _train_badges.is_empty() or bld == null or not is_instance_valid(bld):
		return
	for key in _train_badges:
		var lbl: Label = _train_badges[key]
		if lbl == null or not is_instance_valid(lbl):
			continue
		var n: int = bld.queued_count(String(key))
		lbl.visible = n > 0
		if n > 0:
			lbl.text = str(n)

## Цена в формате «150 л + 80 к» по словарю {тип_ресурса: количество}
## ── ЦЕНА — ИКОНКАМИ РЕСУРСОВ, А НЕ БУКВАМИ (заказ владельца) ─────────────
## Было «Цена: 50 л + 20 з». Однобуквенные суффиксы («л», «з», «к», «е») —
## та же техническая отладка, что «Габарит»: их надо расшифровывать, и в
## одной строке с числами они читаются как опечатка.
##
## ИКОНКИ БЕРУТСЯ ИЗ RES_DEFS — ТОГО ЖЕ МЕСТА, ОТКУДА ИХ БЕРЁТ ВЕРХНЯЯ
## ПОЛОСА РЕСУРСОВ. Это обязательно: заведи здесь свой список путей, и
## однажды значок дерева в цене разойдётся со значком дерева в полосе, а
## игрок читает их как одно и то же. Через тот же `_trimmed_icon`, что и
## полоса, — иначе картинки будут разного видимого размера при одинаковой
## рамке (у исходников очень разная заливка кадра).
##
## ЧИСЛА НЕ ПЕРЕСЧИТЫВАЮТСЯ ЗДЕСЬ ВОВСЕ: `cost` приходит из конфига
## (unit_stats_config.unit_cost / building_cost), правка баланса доезжает
## сама. Цвет числа — ПО КОШЕЛЬКУ: не хватает ресурса, значит красное.
## Порядок строго по RES_DEFS, а не по обходу словаря: у Dictionary порядок
## вставки, и одна и та же цена в разных местах шла бы в разном порядке
## Цвет числа в цене: хватает / не хватает. Не «зелёный и красный», а
## ЗОЛОТОЙ и красный — золотой это цвет ресурсов во всём интерфейсе, и
## подменять его зелёным ради симметрии с кнопками значило бы завести второй
## язык цвета для одного и того же
const COST_OK_COLOR   := Color(1.00, 0.84, 0.35)
const COST_LACK_COLOR := Color(0.95, 0.38, 0.34)
const COST_ICON_PX := 16.0

func _build_cost_row(cost: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var cap := Label.new()
	cap.text = "Цена:"
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", Color(0.72, 0.74, 0.80))
	row.add_child(cap)
	for rd in RES_DEFS:
		var key: int = int(rd["key"])
		if not cost.has(key):
			continue
		var need: float = float(cost[key])
		if need <= 0.0:
			continue
		var ic := TextureRect.new()
		ic.texture = _trimmed_icon(String(rd["ipath"]))
		ic.custom_minimum_size = Vector2(COST_ICON_PX, COST_ICON_PX)
		ic.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Иконки нет в сборке — не оставляем пустую дыру, подписываем словом
		if ic.texture == null:
			ic.queue_free()
			var nm := Label.new()
			nm.text = String(rd["label"])
			nm.add_theme_font_size_override("font_size", 11)
			row.add_child(nm)
		else:
			row.add_child(ic)
		var lb := Label.new()
		lb.text = str(int(need))
		lb.add_theme_font_size_override("font_size", 12)
		var have: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, key)
		lb.add_theme_color_override("font_color",
			COST_OK_COLOR if have >= need else COST_LACK_COLOR)
		lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lb)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(6, 0)
		row.add_child(gap)
	return row


# ═════════════════════════════════════════════════════════════════════════════
# ПАНЕЛЬ КУЗНИЦЫ: ДРЕВО ТЕХНОЛОГИЙ
#
# Кузница получила собственную широкую панель вместо строки кнопок в общей
# нижней. Причина не в красоте: сетка 5×4 со стрелками между ячейками — это
# ~230×230 px жёсткой разметки, а общая панель считает свою высоту по
# содержимому (_sync_panel_height) и растянулась бы на полэкрана; плюс
# стрелки рисуются по КООРДИНАТАМ ячеек, а в BoxContainer их не существует
# до первого кадра раскладки.
#
# Устройство:
#   • слева — крупная иконка кузницы, подпись «Кузница N/N HP» и ряд иконок
#     очереди исследований (тот же _research_slot, что и раньше);
#   • сверху — полоса вкладок по родам войск; клик переключает древо;
#   • справа — сетка 5×4. Колонки A/B/C соединены стрелками зависимостей,
#     колонка D стрелок не имеет: её открывает ПОЛНЫЙ ряд A+B+C;
#   • при наведении на узел СПРАВА ОТ ПАНЕЛИ, вне её, всплывает крупное окно
#     с названием, эффектом, статусом, временем и ценой.
#
# Данные целиком в scripts/forge_config.gd — здесь только отрисовка.
# ═════════════════════════════════════════════════════════════════════════════

## Цвет открытой (пройденной) стрелки и закрытой. Открытая — зелёная, как на
## макете; закрытая приглушена до тёмно-серой, чтобы ветка читалась как
## «сюда пока нельзя», но сама структура древа оставалась видимой
const FORGE_ARROW_ON  := Color(0.42, 0.78, 0.42, 0.95)
const FORGE_ARROW_OFF := Color(0.34, 0.34, 0.38, 0.70)
const FORGE_ARROW_W   := 2.0
const FORGE_ARROW_HEAD := 5.0

func _build_forge_panel() -> void:
	if _forge_panel != null and is_instance_valid(_forge_panel):
		return
	var panel := PanelContainer.new()
	panel.name = "ForgePanel"
	panel.visible = false
	panel.anchor_left = 0.0; panel.anchor_right = 0.0
	panel.anchor_top  = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = PANEL_LEFT
	panel.offset_bottom = -float(PANEL_BOTTOM_GAP)
	# Высота ЯВНАЯ (см. FORGE_PANEL_H): сетка узлов расставлена абсолютно, её
	# размера контейнер не знает, и панель схлопывалась, обрезая нижние ряды
	panel.offset_top = -float(FORGE_PANEL_H + PANEL_BOTTOM_GAP)
	panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.custom_minimum_size = Vector2(0, FORGE_PANEL_H)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.045, 0.09, 0.96)
	_borders(st); _corners(st, 6)
	st.border_color = Color(0.42, 0.34, 0.18)
	st.content_margin_left = FORGE_PAD; st.content_margin_right = FORGE_PAD
	st.content_margin_top  = FORGE_PAD; st.content_margin_bottom = FORGE_PAD
	panel.add_theme_stylebox_override("panel", st)
	add_child(panel)
	_forge_panel = panel

	# Подпись — НАД содержимым и во всю ширину панели, а не в левой колонке:
	# в колонке под иконку (FORGE_BLD_W) «Кузница 250/250 HP» не помещается и
	# обрезалась многоточием на первом же прогоне
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", FORGE_SEP)
	panel.add_child(col)

	_forge_caption = Label.new()
	_forge_caption.name = "ForgeCaption"
	_forge_caption.add_theme_font_size_override("font_size", 12)
	_forge_caption.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	_forge_caption.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.95))
	_forge_caption.add_theme_constant_override("outline_size", 3)
	_forge_caption.custom_minimum_size = Vector2(0, FORGE_CAP_H)
	col.add_child(_forge_caption)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	col.add_child(root)

	# ── ЛЕВЫЙ БЛОК: здание ──────────────────────────────────────────────────
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 5)
	left.custom_minimum_size = Vector2(FORGE_BLD_W, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(left)

	var bld := TextureRect.new()
	bld.name = "ForgeBuildingIcon"
	bld.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	bld.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bld.custom_minimum_size = Vector2(FORGE_BLD_W, FORGE_BLD_W)
	bld.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bld.texture = _icon_texture(_bld_icon("smithy"))
	left.add_child(bld)

	# ── ИНДИКАТОР ТЕКУЩЕГО ИССЛЕДОВАНИЯ ─────────────────────────────────────
	# Заказ владельца: «убери пустой чёрный прямоугольник под иконкой Кузницы,
	# опусти иконку исследуемой технологии ниже и увеличь её».
	#
	# Прямоугольник был не отдельным узлом, а САМОЙ ЯЧЕЙКОЙ очереди: ряд строился
	# размером QUEUE_ORDER_ICON (10 px) — на такой площади иконка технологии
	# нечитаема, и ячейка выглядела пустой тёмной плашкой. Лечится не удалением
	# узла, а размером: ячейки очереди кузницы теперь FORGE_QUEUE_ICON (крупнее
	# самого узла древа, чтобы «что качается прямо сейчас» читалось с одного
	# взгляда), а «ниже» даёт распорка — она отжимает ряд к нижней кромке
	# левой колонки, под иконку здания
	var qgap := Control.new()
	qgap.name = "ForgeQueueGap"
	qgap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qgap.custom_minimum_size = Vector2(0, FORGE_QUEUE_DROP)
	left.add_child(qgap)

	_forge_queue = GridContainer.new()
	_forge_queue.name = "ForgeQueue"
	_forge_queue.columns = 1
	_forge_queue.add_theme_constant_override("h_separation", 3)
	_forge_queue.add_theme_constant_override("v_separation", 3)
	left.add_child(_forge_queue)

	# ── ПРАВЫЙ БЛОК: вкладки + сетка ────────────────────────────────────────
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", FORGE_SEP)
	root.add_child(right)

	_forge_tabs = HBoxContainer.new()
	_forge_tabs.name = "ForgeTabs"
	_forge_tabs.add_theme_constant_override("separation", 8)
	_forge_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(_forge_tabs)

	_forge_grid = Control.new()
	_forge_grid.name = "ForgeGrid"
	_forge_grid.custom_minimum_size = Vector2(FORGE_GRID_W, FORGE_GRID_H + FORGE_ROOT_H)
	_forge_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_forge_grid)

	# Холст стрелок — ПЕРВЫМ ребёнком, то есть под кнопками: иначе он перехватил
	# бы мышь у самих узлов (и MOUSE_FILTER_IGNORE один этого не гарантирует —
	# порядок отрисовки всё равно положил бы линии поверх иконок)
	_forge_arrows = Control.new()
	_forge_arrows.name = "ForgeArrows"
	_forge_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forge_arrows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_forge_arrows.draw.connect(_draw_forge_arrows)
	_forge_grid.add_child(_forge_arrows)

## Левый верхний угол ячейки внутри _forge_grid
func _forge_cell_pos(cell: String) -> Vector2:
	var row_i: int = int(cell.substr(0, cell.length() - 1)) - 1
	var col: String = cell.substr(cell.length() - 1, 1)
	var col_i: int  = maxi(_Forge.COLS.find(col), 0)
	var x: float = float(col_i) * float(FORGE_CELL + FORGE_GAP_X)
	if col == _Forge.ABILITY_COL:
		x += float(FORGE_D_GAP)
	var y: float = float(FORGE_ROOT_H) + float(row_i) * float(FORGE_CELL + FORGE_GAP_Y)
	return Vector2(x, y)

func _forge_cell_center(cell: String) -> Vector2:
	return _forge_cell_pos(cell) + Vector2(FORGE_CELL, FORGE_CELL) * 0.5

## Показать панель кузницы под конкретное здание. Вкладка сохраняется между
## показами, если тип тот же — игрок вернулся к тому же дереву, а не к первому
func show_forge(smithy: Smithy) -> void:
	_build_forge_panel()
	_forge_smithy = smithy
	if _forge_unit.is_empty() or not _Forge.UNITS.has(_forge_unit):
		_forge_unit = String(_Forge.UNIT_TABS[0])
	_forge_panel.visible = true
	if _bottom_panel != null and is_instance_valid(_bottom_panel):
		_bottom_panel.visible = false
	_hide_castle_caption()
	# Валидация очереди по ВСЕЙ фракции, а не по показанной вкладке: сирота
	# на другой вкладке блокировала бы узлы, которые от неё зависят
	var busy_all: Variant = GameManager.researching.get(smithy.faction)
	if busy_all != null:
		for id in (busy_all as Dictionary).keys():
			GameManager.drop_orphan_research(smithy.faction, String(id))
	_rebuild_forge()

func hide_forge() -> void:
	_hide_forge_tip()
	_forge_smithy = null
	if _forge_panel != null and is_instance_valid(_forge_panel):
		_forge_panel.visible = false

func forge_visible() -> bool:
	return _forge_panel != null and is_instance_valid(_forge_panel) \
		and _forge_panel.visible

## Переключить вкладку. Выделение и очередь исследований не трогаются —
## меняется только показанное древо
func forge_set_tab(unit_id: String) -> void:
	if not _Forge.UNITS.has(unit_id):
		return
	# ЩЕЛЧОК ВКЛАДКИ (ТЗ 10.10.2026, блок 3): переход между деревьями
	if unit_id != _forge_unit:
		AudioManager.play_ui("menu_tab")
	_forge_unit = unit_id
	_hide_forge_tip()
	_rebuild_forge()

func _rebuild_forge() -> void:
	if _forge_smithy == null or not is_instance_valid(_forge_smithy):
		return
	var s := _forge_smithy
	_forge_caption.text = "%s  %d/%d HP" % [
		s.display_name, int(s.current_health), int(s.max_health)]
	_rebuild_forge_tabs()
	_rebuild_forge_grid()
	_rebuild_research_queue(s)

func _rebuild_forge_tabs() -> void:
	for c in _forge_tabs.get_children():
		_forge_tabs.remove_child(c)
		c.queue_free()
	for t in _Forge.UNIT_TABS:
		var unit_id: String = String(t)
		var btn := Button.new()
		btn.name = "ForgeTab_" + unit_id
		btn.custom_minimum_size = Vector2(FORGE_TAB, FORGE_TAB)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = String(UNIT_TITLES.get(unit_id, unit_id))
		var active: bool = unit_id == _forge_unit
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0.20, 0.30, 0.18) if active else Color(0.10, 0.10, 0.14)
		_corners(bs, 4); _borders(bs, 2)
		bs.border_color = Color(0.45, 0.85, 0.45) if active else Color(0.26, 0.24, 0.20)
		btn.add_theme_stylebox_override("normal", bs)
		btn.add_theme_stylebox_override("hover", bs)
		btn.add_theme_stylebox_override("pressed", bs)
		var tex := _icon_texture(String(UNIT_ICONS.get(unit_id, "")))
		if tex != null:
			btn.add_child(_stretched_icon(tex, 3.0))
		btn.pressed.connect(func(): forge_set_tab(unit_id))
		_forge_tabs.add_child(btn)

func _rebuild_forge_grid() -> void:
	_forge_nodes.clear()
	_forge_node_avail.clear()
	_forge_node_afford.clear()
	# remove_child перед queue_free — иначе имена узлов уникализируются
	# (см. тот же разбор в _rebuild_research_queue)
	for c in _forge_grid.get_children():
		if c != _forge_arrows:
			_forge_grid.remove_child(c)
			c.queue_free()
	var s := _forge_smithy
	var f: int = s.faction
	for n in _Forge.tree(_forge_unit):
		var node: Dictionary = n
		var nid: String  = String(node.get("id", ""))
		var cell: String = String(node.get("cell", ""))
		var done: bool   = GameManager.is_researched(f, nid)
		# Валидация очереди (ТЗ 11.10.2026): отметка «в работе» без кузницы-
		# владельца — сирота (кузницу снесли, состояние прошлой партии); она
		# снимается здесь же с возвратом цены и не блокирует узел
		if GameManager.is_researching(f, nid):
			GameManager.drop_orphan_research(f, nid)
		var busy: bool   = GameManager.is_researching(f, nid)
		var avail: bool  = GameManager.can_research(f, nid)
		var qpos: int    = s.queue_position(nid)

		# QuietTooltipButton, а не голый Button (ТЗ-B 19.09.2026, п. 1):
		# _apply_upgrade_state пишет в tooltip_text «Название — Требуется
		# предыдущее улучшение», и движок рисовал этот текст СВОИМ пузырём
		# поверх нашей карточки узла («бегущая строка» со скриншота).
		# tooltip_text остаётся — по нему узлы ищут стенды, — а пузыря нет
		var btn := QuietTooltipButton.new()
		btn.name = "ForgeNode_" + nid
		btn.position = _forge_cell_pos(cell)
		btn.size = Vector2(FORGE_CELL, FORGE_CELL)
		btn.custom_minimum_size = btn.size
		btn.focus_mode = Control.FOCUS_NONE
		# Доступный узел без денег — красная рамка, как у кнопок найма;
		# живёт по сигналу склада (_retint_forge_nodes)
		var afford: bool = ResourceManager.can_afford(f, _UCfg.upgrade_cost(node))
		_forge_node_avail[nid] = avail and not done and not busy
		_forge_node_afford[nid] = afford
		var bs := _forge_node_style(done, busy, avail, afford)
		btn.add_theme_stylebox_override("normal", bs)
		btn.add_theme_stylebox_override("hover", bs)
		btn.add_theme_stylebox_override("pressed", bs)
		btn.add_theme_stylebox_override("disabled", bs)
		var tex := _icon_texture(String(node.get("icon", "")))
		if tex != null:
			btn.add_child(_stretched_icon(tex, 2.0))
		else:
			btn.text = cell.to_upper()
		# Состояние (гашение, галочка «изучено», подсказка) — тем же кодом, что и
		# у старых слотов: правило «что значит куплено/идёт/закрыто» одно на весь
		# интерфейс и не должно расходиться между двумя панелями
		_apply_upgrade_state(btn, String(node.get("name", nid)), done, busy, avail, qpos)
		# ЗАКРЫТЫЙ УЗЕЛ ОСТАЁТСЯ ЖИВЫМ. _apply_upgrade_state гасит disabled = true
		# и у изученного, и у недоступного, а отключённая Button не отдаёт
		# mouse_entered — то есть по самому нужному узлу («почему закрыто?»)
		# всплывающее окно бы и не появилось. Клик по нему всё равно безвреден:
		# research() отобьёт заказ сам
		btn.disabled = false
		btn.mouse_entered.connect(_show_forge_tip.bind(nid))
		btn.mouse_exited.connect(_hide_forge_tip)
		btn.pressed.connect(func(): _on_forge_node_pressed(nid))
		if qpos >= 0:
			btn.gui_input.connect(
				func(ev: InputEvent): _on_upgrade_gui_input(ev, s, nid))
		_forge_grid.add_child(btn)
		_forge_nodes[nid] = btn
	if _forge_arrows != null and is_instance_valid(_forge_arrows):
		_forge_arrows.queue_redraw()

## Стрелки зависимостей. Рисуются по координатам ячеек, а не по раскладке
## контейнера: ячейки расставлены абсолютно (см. _forge_cell_pos), поэтому
## линии всегда попадают в иконки, в том числе в самый первый кадр
func _draw_forge_arrows() -> void:
	if _forge_unit.is_empty() or _forge_smithy == null \
			or not is_instance_valid(_forge_smithy):
		return
	var f: int = _forge_smithy.faction
	var half: float = float(FORGE_CELL) * 0.5

	# ШИНА ОТ ВКЛАДКИ К ПЕРВОМУ РЯДУ. На макете иконка рода войск ветвится на
	# 1a/1b/1c — рисуем это как горизонтальную перемычку над рядом и три
	# коротких спуска в узлы. Колонка D в шину не входит: она открывается рядом
	var xa: float = _forge_cell_center("1a").x
	var xc: float = _forge_cell_center("1c").x
	var bus_y: float = float(FORGE_ROOT_H) * 0.45
	_forge_arrows.draw_line(Vector2(xa, bus_y), Vector2(xc, bus_y),
		FORGE_ARROW_ON, FORGE_ARROW_W)
	for cell in ["1a", "1b", "1c"]:
		var cx: float = _forge_cell_center(String(cell)).x
		var top: float = _forge_cell_pos(String(cell)).y
		_forge_arrow(Vector2(cx, bus_y), Vector2(cx, top), FORGE_ARROW_ON)

	for n in _Forge.tree(_forge_unit):
		var node: Dictionary = n
		var cell: String = String(node.get("cell", ""))
		var c: Vector2 = _forge_cell_center(cell)
		# ── Вертикальные стрелки зависимостей: от родителя к этому узлу.
		# Цвет по РОДИТЕЛЮ: изучен — путь открыт (зелёный), нет — закрыт
		for p in node.get("prerequisites", []):
			var par: Dictionary = _Forge.get_node(String(p))
			if par.is_empty():
				continue
			var pc: String = String(par.get("cell", ""))
			var from := Vector2(_forge_cell_center(pc).x,
				_forge_cell_pos(pc).y + float(FORGE_CELL))
			var to := Vector2(c.x, _forge_cell_pos(cell).y)
			# ТОЛЬКО ПРЯМЫЕ СТРЕЛКИ СВЕРХУ ВНИЗ (заказ 13.09.2026): у ветки
			# монаха бонус ряда (колонка D) зависит от всех трёх узлов ряда,
			# и три косые линии в боковую колонку читались как искажённая
			# схема. Зависимость есть, а линии — нет: бонус ряда выдаётся сам
			if absf(from.x - to.x) > 0.5:
				continue
			var col: Color = FORGE_ARROW_ON \
				if GameManager.is_researched(f, String(p)) else FORGE_ARROW_OFF
			_forge_arrow(from, to, col)
		# ── ВОРОТА РЯДА В КОЛОНКУ D (ТЗ-B 19.09.2026, п. 2) ─────────────────
		# Узел D открывается рядом A+B+C: рисуем одну стрелку C → D в его
		# ряду (зелёная, когда ряд изучен целиком). Три косые линии из A, B и
		# C сюда не возвращаются (заказ 13.09.2026) — связь одна, читается
		# как «из ряда в D». Вертикаль D1 → D2 → … рисует общий цикл выше:
		# у колонки D теперь есть предыдущий узел в prerequisites
		if cell.ends_with(_Forge.ABILITY_COL):
			var gate_cell: String = cell.substr(0, cell.length() - 1) + "c"
			var gc: Vector2 = _forge_cell_center(gate_cell)
			var row_done := true
			for g in node.get("row_gate", []):
				if not GameManager.is_researched(f, String(g)):
					row_done = false
					break
			_forge_arrow(Vector2(gc.x + half, gc.y), Vector2(c.x - half, c.y),
				FORGE_ARROW_ON if row_done else FORGE_ARROW_OFF)
		# ── Горизонтальные двусторонние связки: ТОЛЬКО ЛИНИЯ, не зависимость
		# (поле "link" ячейки, forge_config.UNITS). Рисуем один раз на пару — по той
		# стороне, где ячейка «левее», иначе каждая пара рисуется дважды
		for l in node.get("link", []):
			var other: String = String(l)
			if other <= cell:
				continue
			var oc: Vector2 = _forge_cell_center(other)
			if absf(oc.y - c.y) > 0.5:
				continue                       # связка не в одном ряду — пропуск
			var a := Vector2(c.x + half, c.y)
			var b := Vector2(oc.x - half, oc.y)
			var lit: bool = GameManager.is_researched(f, String(node.get("id", ""))) \
				or GameManager.is_researched(f, _Forge.node_id(_forge_unit, other))
			var lcol: Color = FORGE_ARROW_ON if lit else FORGE_ARROW_OFF
			_forge_arrow(a, b, lcol)
			_forge_arrow(b, a, lcol)

## Линия со стрелкой на конце
func _forge_arrow(from: Vector2, to: Vector2, col: Color) -> void:
	_forge_arrows.draw_line(from, to, col, FORGE_ARROW_W)
	var dir: Vector2 = (to - from)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x) * (FORGE_ARROW_HEAD * 0.6)
	var base: Vector2 = to - dir * FORGE_ARROW_HEAD
	_forge_arrows.draw_colored_polygon(
		PackedVector2Array([to, base + side, base - side]), col)

func _on_forge_node_pressed(node_id: String) -> void:
	if _forge_smithy == null or not is_instance_valid(_forge_smithy):
		return
	if _forge_smithy.research(node_id):
		_last_research_id = _forge_smithy.research_id
		_rebuild_forge()
		_show_forge_tip(node_id)     # окно под курсором должно обновить статус

# ── ВСПЛЫВАЮЩЕЕ ОКНО УЗЛА ────────────────────────────────────────────────────
# Своё, а не общий _show_card: общая карточка прибита к верхней кромке нижней
# панели, а панель кузницы стоит ровно там же и накрыла бы собственную
# подсказку. По макету окно висит СПРАВА ОТ ПАНЕЛИ, за её краем.

func _hide_forge_tip() -> void:
	if _forge_tip != null and is_instance_valid(_forge_tip):
		_forge_tip.queue_free()
	_forge_tip = null
	_forge_preview_end()

# ═════════════════════════════════════════════════════════════════════════════
# ПРЕДПРОСМОТР БОНУСА КУЗНИЦЫ НА ПАНЕЛИ ОТРЯДА (ТЗ-B 19.09.2026, п. 3)
# ═════════════════════════════════════════════════════════════════════════════
# Наведение на узел древа дорисовывает его прибавки в таблицу статов ТЕМ ЖЕ
# путём, что предпросмотр награды (_preview_stats): ключи узла — те же
# bonus_*, что у карточек ветеранства. Чей отряд: выделенный отряд этого рода
# войск; нет выделенного — первый живой свой отряд того же рода (панель
# поднимается ради предпросмотра НАД панелью кузницы и гаснет с уходом
# курсора). Рода войск нет на карте — предпросмотра нет
var _stat_sid: int = 0
var _stat_hover_forge: bool = false
## Панель статов поднята ради предпросмотра кузницы — с ним и уходит
var _forge_preview_own: bool = false
## Стенды: сколько раз предпросмотр кузницы дописал прибавку в таблицу
var forge_previews: int = 0

func _forge_preview_begin(node: Dictionary) -> void:
	_forge_preview_end()
	var uid: String = String(node.get("unit", ""))
	if uid.is_empty() or _UCfg.nonzero_modifiers(node).is_empty():
		return
	var sid: int = 0
	for s in _selected_squad_ids():
		if GameManager.squad_type(int(s)) == uid:
			sid = int(s)
			break
	if sid <= 0 and _stat_sid > 0 and GameManager.squads.has(_stat_sid) \
			and GameManager.squad_type(_stat_sid) == uid:
		sid = _stat_sid
	if sid <= 0:
		for key in GameManager.squads:
			var rec: Dictionary = GameManager.squads[key]
			if int(rec.get("faction", -1)) != Constants.FACTION_PLAYER:
				continue
			if String(rec.get("type", "")) != uid:
				continue
			if (rec["members"] as Array).is_empty():
				continue
			sid = int(key)
			break
	# РАБОЧИЕ — НЕ ОТРЯД (squad 0): образец — выделенный рабочий или любой
	# живой свой, таблица — его ремесло (см. _show_stat_panel)
	if sid <= 0 and uid == "worker":
		var wk: Unit = _forge_worker_sample()
		if wk == null:
			return
		_show_stat_panel(0, [wk])
		_forge_preview_own = true
		_stat_hover_forge = true
		_refresh_stat_visibility()
		_preview_stats(node)
		forge_previews += 1
		_lift_stat_panel_over_forge()
		return
	if sid <= 0:
		return
	var fresh: bool = _stat_sid != sid or _stat_panel == null or not is_instance_valid(_stat_panel)
	if fresh:
		var men: Array = GameManager.squad_members(sid)
		if men.is_empty():
			return
		_show_stat_panel(sid, men)
		_forge_preview_own = true
	_stat_hover_forge = true
	_refresh_stat_visibility()
	_preview_stats(node)
	forge_previews += 1
	if fresh:
		_lift_stat_panel_over_forge()

## Рабочий-образец для предпросмотра кузницы: из выделения, иначе любой свой
func _forge_worker_sample() -> Unit:
	var main := GameManager.main
	var pool: Array = []
	if main != null and main.selection_manager != null:
		pool.append_array(main.selection_manager.selected_units)
	pool.append_array(get_tree().get_nodes_in_group(Constants.unit_group(Constants.FACTION_PLAYER)))
	for u in pool:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var w: Unit = u
		if w.stat_id == "worker" and not w.is_dead():
			return w
	return null

## Панель статов, поднятая ради кузницы, встаёт НАД панелью кузницы (та
## занимает место над нижней панелью, где таблица стоит обычно)
func _lift_stat_panel_over_forge() -> void:
	await get_tree().process_frame
	if not _forge_preview_own or _stat_panel == null or not is_instance_valid(_stat_panel):
		return
	if _forge_panel == null or not is_instance_valid(_forge_panel) or not _forge_panel.visible:
		return
	var h: float = _stat_panel.get_combined_minimum_size().y
	var bottom: float = _forge_panel.offset_top - 4.0
	_stat_panel.offset_bottom = bottom
	_stat_panel.offset_top = bottom - h

func _forge_preview_end() -> void:
	if not _stat_hover_forge:
		return
	_stat_hover_forge = false
	_clear_stat_preview()
	if _forge_preview_own:
		_forge_preview_own = false
		_hide_stat_panel()
	else:
		_refresh_stat_visibility()

func _show_forge_tip(node_id: String) -> void:
	_hide_forge_tip()
	var node: Dictionary = _Forge.get_node(node_id)
	if node.is_empty() or _forge_smithy == null or not is_instance_valid(_forge_smithy):
		return
	var f: int = _forge_smithy.faction

	var panel := PanelContainer.new()
	panel.name = "ForgeTip"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.05, 0.04, 0.97)
	_borders(st); _corners(st, 6)
	st.border_color = Color(0.58, 0.48, 0.26)
	st.content_margin_left = 12; st.content_margin_right = 12
	st.content_margin_top  = 10; st.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(FORGE_TIP_W, 0)
	add_child(panel)
	_forge_tip = panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)


	# ── ФОРМАТ КАРТОЧКИ (ТЗ-B 19.09.2026, п. 2): иконка + название, описание
	# человеческим языком, статус, цена. Технических строк («+0.2
	# bonus_heal_rate», «Исследование: 25 с», «Действует: …», «Способность
	# отряда») здесь больше нет — числа бонусов живут в описании узла и в
	# предпросмотре на панели отряда (_forge_preview_begin)
	# ── ТЗ 20.10.2026, блок 3: формат общей карточки — название слева, плитка
	# иконки со статусом справа, «Тип / Эффект», цена. Шапка собирается ниже,
	# когда статус уже известен, и встаёт первой строкой
	var unit_t: String = String(UNIT_TITLES.get(node_id.substr(0, maxi(node_id.rfind("_"), 0)), ""))
	box.add_child(_card_rich("[color=#%s]Тип:[/color] Улучшение%s" % [CARD_LABEL_COL.to_html(false),
		(" · " + unit_t) if not unit_t.is_empty() else ""], FORGE_TIP_W - 24, 13))
	box.add_child(_card_rich("[color=#%s]Эффект:[/color] %s" % [CARD_LABEL_COL.to_html(false),
		String(node.get("desc", ""))], FORGE_TIP_W - 24, 13))

	# ── Статус: Изучено / Исследуется / Доступно (зелёным) / Недоступно
	#    (красным); причина закрытия — отдельной серой строкой
	var nid: String = String(node.get("id", ""))
	var status := ""
	var status_col := Color(0.86, 0.86, 0.90)
	var why := ""
	if GameManager.is_researched(f, nid):
		status = "Изучено"
		status_col = UPG_CHECK_COLOR
	elif GameManager.is_researching(f, nid):
		var qp: int = _forge_smithy.queue_position(nid)
		if qp < 0:
			# Не в этой кузнице: в другой кузнице фракции (ПКМ снимет и там)
			status = "Исследуется в другой кузнице  •  ПКМ — отменить"
		else:
			status = "Исследуется" if qp == 0 else "В очереди (%d)" % qp
		status_col = Color(0.56, 0.78, 0.98)
	else:
		var missing: Array = GameManager.research_blockers(f, node)
		if missing.is_empty():
			status = "Доступно"
			status_col = FORGE_STATUS_OK
		else:
			status = "Недоступно"
			status_col = FORGE_STATUS_LOCK
			if not (node.get("row_gate", []) as Array).is_empty() \
					and _forge_row_locked(f, node):
				# Колонка D закрыта именно рядом — называем причину прямо,
				# иначе игрок ищет несуществующую стрелку к этой иконке
				why = "Нужно изучить ряд %s (A + B + C)" % str(node.get("row", ""))
				var rest: Array = []
				for m in missing:
					if not (String(m) in (node.get("row_gate", []) as Array)):
						rest.append(m)
				if not rest.is_empty():
					why += " и %s" % _forge_names(rest)
			else:
				why = "Нужно: %s" % _forge_names(missing)
				var side_ids: Array = node.get("link_ids", [])
				if not side_ids.is_empty():
					why += " (или сбоку: %s)" % _forge_names(side_ids)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = String(node.get("name", node_id))
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.42))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size = Vector2(FORGE_TIP_W - 24 - CARD_BADGE - 30, 0)
	head.add_child(title)
	head.add_child(_card_badge({"icon": String(node.get("icon", "")),
		"status": status, "status_col": status_col}))
	box.add_child(head)
	box.move_child(head, 0)
	box.add_child(_card_sep(FORGE_TIP_W - 24))
	box.move_child(box.get_child(box.get_child_count() - 1), 1)
	if not why.is_empty():
		_forge_tip_line(box, why, Color(0.70, 0.70, 0.76), 12)

	# ЦЕНА — ИКОНКАМИ РЕСУРСОВ, как в карточке найма (заказ 10.09.2026):
	# тот же _build_cost_row, число краснеет, когда ресурса не хватает
	box.add_child(_build_cost_row(_UCfg.upgrade_cost(node)))

	# ── ЖИВОЙ ПРЕДПРОСМОТР НА ПАНЕЛИ ОТРЯДА (ТЗ-B 19.09.2026, п. 3) ────────
	_forge_preview_begin(node)
	_pin_forge_tip()

const FORGE_STATUS_OK   := Color(0.45, 0.90, 0.45)
const FORGE_STATUS_LOCK := Color(0.95, 0.35, 0.35)

## Заперт ли узел колонки D именно неполным рядом
func _forge_row_locked(f: int, node: Dictionary) -> bool:
	for g in node.get("row_gate", []):
		if not GameManager.is_researched(f, String(g)):
			return true
	return false

const _BONUS_TITLES := {
	"bonus_attack": "к урону", "bonus_armor": "к броне",
	"bonus_defense": "к защите",
	"bonus_health": "к запасу HP", "bonus_speed": "к скорости",
	"bonus_range": "к дальности, м",
	"bonus_cooldown": "с долой с перезарядки",
	"bonus_spread": "к кучности стрельбы",
	"bonus_push": "к напору", "bonus_morale": "к морали",
	# Экономические ключи рабочего. bonus_gather СОКРАЩАЕТ цикл, поэтому подпись
	# читается как «секунды долой», а не «плюс к чему-то» (см. Worker._cycle_time)
	"bonus_gather": "с долой из цикла добычи", "bonus_carry": "к грузу за ходку",
	"bonus_build": "к темпу стройки (доля)",
	# ── ЭКОНОМИКА (ТЗ 23.09.2026): ВСЕ ПЯТЬ — ДОЛИ, и подпись обязана это
	# говорить. «−0.35 с» и «+10 %» стоят в одной панели рядом, и перепутать
	# единицы здесь значит соврать игроку о цене узла
	"bonus_gather_wood": "к темпу рубки дерева (доля)",
	"bonus_gather_stone": "к темпу добычи камня (доля)",
	"bonus_gather_gold": "к темпу добычи золота (доля)",
	"bonus_gather_food": "к темпу разделки мяса (доля)",
	"bonus_carry_pct": "к грузу за ходку (доля)",
	"bonus_walk_pct": "к скорости ходьбы рабочего (доля)",
	"bonus_walk_loaded_pct": "к ходу рабочего с грузом (доля)",
	"bonus_meat_pct": "к выходу мяса с туши (доля)",
	"bonus_research_pct": "к темпу исследований Кузницы (доля)",
	"bonus_hire_cost": "цены найма рабочего долой (доля)",
	"bonus_train_army": "к темпу обучения боевых отрядов (доля)",
}

func _forge_tip_line(box: VBoxContainer, text: String, col: Color, size: int) -> void:
	if text.strip_edges().is_empty():
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(FORGE_TIP_W - 24, 0)
	box.add_child(lbl)

## Человеческие имена узлов через запятую — для строки «нужно …»
func _forge_names(ids: Array) -> String:
	var parts: Array = []
	for i in ids:
		var n: Dictionary = _Forge.get_node(String(i))
		parts.append(String(n.get("name", i)) if not n.is_empty() else String(i))
	return ", ".join(parts)

## «1200 з + 340 л + 200 к» — ровно как на макете
func _forge_cost_text(node: Dictionary) -> String:
	var parts: Array = []
	var g: float = float(node.get("cost_gold", 0.0))
	var w: float = float(node.get("cost_wood", 0.0))
	var s: float = float(node.get("cost_stone", 0.0))
	var f: float = float(node.get("cost_food", 0.0))
	if g > 0.0: parts.append("%d з" % int(g))
	if w > 0.0: parts.append("%d л" % int(w))
	if s > 0.0: parts.append("%d к" % int(s))
	if f > 0.0: parts.append("%d е" % int(f))
	return " + ".join(parts) if not parts.is_empty() else "бесплатно"

## ОКНО ДРЕВА — ИСКЛЮЧЕНИЕ ИЗ ОБЩЕГО ПРАВИЛА «СТРОГО ВВЕРХ», И НАМЕРЕННОЕ.
##
## Общее правило (_tip_anchor_geometry) ставит окно над наведённой кнопкой.
## Здесь это не сработает по геометрии: сетка узлов 5×4 занимает почти всю
## высоту панели кузницы, панель прижата к низу экрана, и окну над узлом
## ВЕРХНЕГО ряда просто некуда расти — оно упёрлось бы в потолок и полезло
## обратно на сетку, закрывая соседние узлы.
##
## Поэтому окно кузницы стоит СПРАВА от панели, за её краем (ровно как на
## макете владельца — там оно нарисовано за красной чертой справа). Требование
## «не наезжать на кнопки» соблюдается строже, чем общим правилом: окно вообще
## не пересекает панель. Если справа не хватает места (узкое окно игры),
## уходит влево от правого края — за экран не вылезает никогда
func _pin_forge_tip() -> void:
	if _forge_tip == null or not is_instance_valid(_forge_tip) \
			or _forge_panel == null or not is_instance_valid(_forge_panel):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var tip_sz: Vector2 = _forge_tip.get_combined_minimum_size()
	var pr: Rect2 = _forge_panel.get_global_rect()
	var x: float = pr.position.x + pr.size.x + float(FORGE_TIP_GAP)
	if x + tip_sz.x > vp.x - 6.0:
		x = maxf(vp.x - tip_sz.x - 6.0, 6.0)
	var y: float = pr.position.y + pr.size.y - tip_sz.y
	y = clampf(y, 6.0, maxf(vp.y - tip_sz.y - 6.0, 6.0))
	_forge_tip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_forge_tip.position = Vector2(x, y)
	_forge_tip.size = tip_sz

# Кнопки строятся ПО КОНФИГУ: добавили слот в unit_stats_config.gd —
# кнопка появилась сама, править HUD не нужно
func _build_smithy_menu(smithy: Smithy) -> void:
	info_label.text = "Кузница — исследования"
	var f := smithy.faction
	for slot in _UCfg.UPGRADE_SLOTS:
		var d: Dictionary = slot
		var upg_id: String = String(d.get("id", ""))
		var done: bool     = GameManager.is_researched(f, upg_id)
		if GameManager.is_researching(f, upg_id):
			GameManager.drop_orphan_research(f, upg_id)   # сирота — снять (ТЗ 11.10.2026)
		var busy: bool     = GameManager.is_researching(f, upg_id)
		var avail: bool    = GameManager.can_research(f, upg_id)

		# Место в очереди кузницы: 0 — качается прямо сейчас, 1.. — ждёт,
		# -1 — не заказано. Нужно и для подписи, и чтобы ПКМ знал, что отменять
		var qpos: int = smithy.queue_position(upg_id)

		# Иконка берётся из папки кузницы по имени файла (см. smith_icon_path).
		# Описание, бонусы, цена, время исследования и статус — во всплывающей
		# карточке, чтобы кнопки не превращались в простыню текста
		var color := Color(0.30, 0.22, 0.10)
		if done:
			# СВЕТЛАЯ зелёная подложка, а не тёмная заливка: изученное улучшение
			# читается по яркой галочке, а не по тому, что кнопка почернела
			color = Color(0.34, 0.52, 0.34)
		elif busy:
			color = Color(0.16, 0.28, 0.40)
		elif not avail:
			color = Color(0.16, 0.16, 0.18)
		var btn := _cmd(String(d.get("name", upg_id)), color,
			func(): _on_research_pressed(smithy, upg_id),
			String(d.get("icon", "")), _upgrade_card(d, f))
		_apply_upgrade_state(btn, String(d.get("name", upg_id)), done, busy, avail, qpos)
		# ПКМ по заказанному улучшению — отмена с полным возвратом ресурсов
		if qpos >= 0:
			btn.gui_input.connect(
				func(ev: InputEvent): _on_upgrade_gui_input(ev, smithy, upg_id))
	# Ряд очереди исследований в левой колонке — СРАЗУ, а не со следующего кадра
	# из _update_queue_ui: панель должна быть готова к моменту выхода отсюда
	_queue_sig = _queue_signature(smithy)
	_rebuild_queue(smithy)

# ─────────────────────────────────────────────────────────────────────────────
# ВИЗУАЛЬНОЕ СОСТОЯНИЕ КНОПКИ УЛУЧШЕНИЯ
#
# Раньше состояние читалось ТОЛЬКО по цвету подложки, а сама кнопка оставалась
# полностью «живой»: изученное улучшение можно было жать сколько угодно (заказ
# молча отбивался в Smithy.research), иконка светилась в полную силу наравне с
# доступными, и статус нигде не подписывался. С появлением картинок у слотов
# это стало особенно заметно — купленное и некупленное выглядели одинаково.
#
# Правило теперь простое:
#   • ИЗУЧЕНО    — приглушено, не нажимается, зелёная галочка поверх иконки;
#   • ИДЁТ       — приглушено слабее, не нажимается (заказ уже в работе);
#   • НЕДОСТУПНО — цвет естественный, но нажать нельзя: не выполнено условие;
#   • ДОСТУПНО   — ровно как было, Color.WHITE и полностью рабочая кнопка.
#
# Приглушение делается через modulate, а не подменой стилей: картинка остаётся
# читаемой (её видно, что это именно «щиты», а не пустая плашка), но по яркости
# купленное сразу отличается от доступного.
# ─────────────────────────────────────────────────────────────────────────────

## Насколько гасим уже изученное. СВЕТЛОЕ приглушение, а не затемнение: кнопка
## слегка блёкнет и уходит на второй план, но не превращается в тёмную плашку —
## признаком «куплено» служит яркая зелёная галочка поверх иконки, а не темнота
const UPG_DONE_MODULATE := Color(0.88, 0.90, 0.88, 1.0)
## Идущее исследование гасим слабее: за ним ещё следят глазами
const UPG_BUSY_MODULATE := Color(0.75, 0.78, 0.85, 1.0)

const UPG_TIP_DONE := "Улучшение уже изучено"
const UPG_TIP_BUSY := "Идёт исследование  •  ПКМ — отменить, ресурсы вернутся"
const UPG_TIP_QUEUE := "В очереди (%d)  •  ПКМ — отменить, ресурсы вернутся"
const UPG_TIP_LOCK := "Требуется предыдущее улучшение"

## queue_pos: 0 — исследуется сейчас, 1.. — ждёт в очереди, -1 — не заказано
func _apply_upgrade_state(btn: Button, title: String,
		done: bool, busy: bool, avail: bool, queue_pos: int = -1) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	if done:
		btn.modulate     = UPG_DONE_MODULATE
		btn.disabled     = true
		btn.tooltip_text = "%s — %s" % [title, UPG_TIP_DONE]
		_add_done_check(btn)
	elif busy:
		# КНОПКА ОСТАЁТСЯ ЖИВОЙ (disabled = false): отключённая Button не
		# пропускает мышь, а по ней должен работать ПКМ-отмена. Левый клик
		# по ней всё равно безвреден — Smithy.research отобьёт повторный заказ
		btn.modulate     = UPG_BUSY_MODULATE
		btn.disabled     = false
		# ЦИФРЫ НА ИКОНКАХ БОЛЬШЕ НЕТ (заказ владельца): порядок исследований
		# показывает отдельный ряд иконок очереди в левом блоке панели
		# (см. _rebuild_research_queue), а на самой кнопке номер только мешал
		if queue_pos > 0:
			btn.tooltip_text = "%s — %s" % [title, UPG_TIP_QUEUE % queue_pos]
		else:
			btn.tooltip_text = "%s — %s" % [title, UPG_TIP_BUSY]
	elif not avail:
		# Цвет ЕСТЕСТВЕННЫЙ: это не купленное улучшение, а просто ещё закрытое.
		# Нажать нельзя — иначе кнопка «нажимается», но ничего не происходит
		btn.modulate     = Color.WHITE
		btn.disabled     = true
		btn.tooltip_text = "%s — %s" % [title, UPG_TIP_LOCK]
	else:
		btn.modulate = Color.WHITE
		btn.disabled = false

## ЦВЕТ ГАЛОЧКИ «ИЗУЧЕНО» — ровно #32CD32 (limegreen), как просил владелец.
## Прежний оттенок (0.20, 1.0, 0.30) был ярче и «кислотнее»; поверх лиловатых
## иконок кузницы он читался как чужеродный, отсюда и жалоба на «фиолетовую»
const UPG_CHECK_COLOR := Color(0.196078, 0.803922, 0.196078)   # #32CD32
## Сторона квадратика галочки в долях кнопки: кнопки уменьшены вдвое, поэтому
## фиксированные пиксели прежней разметки вылезли бы за рамку
const UPG_CHECK_FRAC := 0.36   # ТЗ 14.10.2026: галочка маленькая и аккуратная (было 0.55)

## Зелёная галочка ВНУТРИ УГЛА изученной кнопки. Однозначный признак состояния,
## не зависящий от того, различает ли игрок оттенки подложки.
## Размер и отступы считаются от BTN_SIZE: при кнопке в 22px прежние −18/−20
## означали бы прямоугольник почти во всю кнопку, наполовину за её краем
func _add_done_check(btn: Button) -> void:
	var mark := Label.new()
	mark.name = "DoneCheck"
	mark.text = "✔"
	var side: float = float(BTN_SIZE) * UPG_CHECK_FRAC
	mark.add_theme_font_size_override("font_size", int(maxf(side, 9.0)))
	mark.add_theme_color_override("font_color", UPG_CHECK_COLOR)
	# Тёмная обводка, чтобы галочка читалась и на светлой иконке
	mark.add_theme_color_override("font_outline_color", Color(0.02, 0.10, 0.02))
	mark.add_theme_constant_override("outline_size", 3)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ГАЛОЧКА ПРИЖАТА К УГЛУ ВЫРАВНИВАНИЕМ, А НЕ УЗКИМ ПРЯМОУГОЛЬНИКОМ.
	# Прямоугольник в side×side px глифу мал: Control не может быть меньше своего
	# минимального размера, поэтому Label распухал до размера шрифта и вылезал
	# ЗА рамку кнопки — ровно то, что просили убрать («галочка ВНУТРИ угла»).
	# Растянутый на всю кнопку Label с выравниванием вправо-вниз даёт тот же
	# угол и гарантированно не выходит за её границы (приём из _add_badge)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mark.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.offset_right  = -1.0
	mark.offset_bottom = -1.0
	btn.add_child(mark)

## ПКМ по заказанному улучшению — снять заказ и вернуть 100% цены.
## Ловится через gui_input, а не через отдельную кнопку: Button реагирует
## только на левую клавишу, а второй виджет поверх иконки закрыл бы её
func _on_upgrade_gui_input(ev: InputEvent, smithy: Smithy, upg_id: String) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	if smithy == null or not is_instance_valid(smithy):
		return
	# ОТМЕНА БЕЗУСЛОВНАЯ (ТЗ 11.10.2026): заказ этой кузницы, заказ ДРУГОЙ
	# кузницы фракции или «сирота» без кузницы-владельца — снимается всё, с
	# возвратом цены. Прежде ПКМ знал только очередь открытой кузницы, и слот
	# «В очереди (-1)» не снимался ничем
	var f: int = smithy.faction
	var ok: bool = smithy.cancel_research(upg_id)
	if not ok:
		var owner: Node = GameManager.research_owner(f, upg_id)
		if owner != null:
			ok = (owner as Smithy).cancel_research(upg_id)
		else:
			ok = GameManager.cancel_research(f, upg_id)
	if ok:
		AudioManager.play_ui("menu_close")    # отмена исследования (ТЗ 10.10.2026)
		_hide_card()
		show_selection([smithy])

func _on_research_pressed(smithy: Smithy, upg_id: String) -> void:
	if smithy.research(upg_id):
		# Перерисовать меню: купленный слот гаснет, открытые зависимости — зажигаются
		show_selection([smithy])

# Строка характеристик С УЧЁТОМ купленных улучшений кузницы: показываем
# ровно те числа, с которыми юнит реально дерётся (бонусы читаются вживую)
func _unit_stats_text(title: String, u: Unit) -> String:
	var atk: float = u.attack_damage + u._upgrade_damage_bonus()
	var def: float = u.defense + u.armor \
		+ GameManager.get_upgrade(u.faction, "defense") \
		+ GameManager.unit_bonus(u.faction, u.stat_id, "bonus_armor")
	return "%s  ATK:%d  DEF:%d  %d/%d HP" % [
		title, int(atk), int(def), int(u.current_health), int(u.max_health)]

# ─────────────────────────────────────────────────────────────────────────────
# LIVE UPDATE
# ─────────────────────────────────────────────────────────────────────────────

## Кто из рабочих сейчас без дела: не добывает, не несёт груз, не строит
func _idle_workers() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("player_units"):
		var w := n as Worker
		if w == null or w.is_dead():
			continue
		# БЕЗ ДЕЛА — ЭТО И «НИКУДА НЕ НАЗНАЧЕН», И «НАЗНАЧЕН, НО НЕ РАБОТАЕТ».
		# Раньше условие требовало gather_target == null, и рабочий, застрявший
		# у жилы, в счётчик не попадал: цель у него формально была. Игрок видел
		# «все при деле», а один стоял в куче камней. Стоящий рабочий с целью —
		# это и есть застрявший: при нормальной работе он в GATHERING,
		# MOVING или RETURNING, но не в IDLE
		if w.state != Unit.State.IDLE:
			continue
		if w.carrying_amount > 0.0:
			continue
		# ДОШЁЛ ДО ТОЧКИ СБОРА И ВСТАЛ — ЭТО ТОЖЕ БЕЗДЕЛЬЕ.
		# Именно этот случай и терялся: новый рабочий выходит из замка, идёт
		# к назначенному флажку, приходит — и стоит там без единого задания.
		# Формально он «выполнил приказ», и никакой другой признак его не ловит,
		# поэтому проверяем прямо: нет ни жилы, ни стройки — значит, без дела
		if w.build_target != null and is_instance_valid(w.build_target):
			continue
		out.append(w)
	return out

## ДЕЙСТВИЕ ПЛАШКИ «РАБОЧИЕ БЕЗ ДЕЛА»: выделить ВСЕХ разом и подвести камеру
## к их середине. Один клик — одна раздача работы на всю ораву; прежний обход
## по одному остался отдельным методом (_focus_next_idle_worker)
func _select_idle_workers() -> void:
	var idle: Array = _idle_workers()
	if idle.is_empty():
		return
	var sm: SelectionManager = GameManager.main.selection_manager
	if sm == null:
		return
	sm._clear_selection()
	var acc := Vector3.ZERO
	for w in idle:
		sm._select_one(w)
		acc += (w as Node3D).global_position
	GameManager.on_selection_changed(sm.selected_units)
	# Камера — на СЕРЕДИНУ найденных, а не на первого: бездельники обычно стоят
	# кучей у замка, и центр показывает всю группу разом
	if GameManager.main != null and GameManager.main.has_method("focus_camera_on"):
		GameManager.main.focus_camera_on(acc / float(idle.size()))

## КЛИК ПО ПЛАШКЕ: показать следующего бездельника — выделить его и навести
## камеру. Именно цикл, а не «выделить всех»: игроку нужно РАЗОБРАТЬСЯ с каждым
## по очереди (отправить на жилу, достроить дом), а пачка из шести выделенных
## рабочих на разных концах карты для этого бесполезна.
##
## Указатель обхода живёт между кликами, но список каждый раз строится заново,
## поэтому гибель или занятие рабочего цикл не ломает — индекс просто берётся
## по модулю нового размера
func _focus_next_idle_worker() -> void:
	var idle: Array = _idle_workers()
	if idle.is_empty():
		return
	if _idle_cycle >= idle.size():
		_idle_cycle = 0
	var w: Worker = idle[_idle_cycle]
	_idle_cycle = (_idle_cycle + 1) % idle.size()
	if w == null or not is_instance_valid(w):
		return
	var sm: SelectionManager = GameManager.main.selection_manager
	if sm != null:
		sm._clear_selection()
		sm._select_one(w)
		GameManager.on_selection_changed(sm.selected_units)
	if GameManager.main != null and GameManager.main.has_method("focus_camera_on"):
		GameManager.main.focus_camera_on(w.global_position)

## Внешний вид плашки под текущее число бездельников. Вынесено отдельно, чтобы
## одинаково отработать и при сборке HUD, и при пересчёте
func _apply_idle_state(n: int) -> void:
	if _idle_count_label != null and is_instance_valid(_idle_count_label):
		_idle_count_label.text = str(n)
		# Ноль — тускло, есть бездельники — тревожный жёлтый: цифру видно и
		# боковым зрением, специально смотреть на панель не нужно
		_idle_count_label.add_theme_color_override("font_color",
			Color(0.98, 0.86, 0.35) if n > 0 else Color(0.60, 0.60, 0.60))
	if _idle_btn != null and is_instance_valid(_idle_btn):
		_idle_btn.modulate.a = 1.0 if n > 0 else IDLE_DIM_ALPHA
		# Погашенная плашка не должна ни ловить клики, ни показывать подсказку
		_idle_btn.disabled    = n <= 0
		_idle_btn.mouse_filter = Control.MOUSE_FILTER_STOP if n > 0 \
			else Control.MOUSE_FILTER_IGNORE

# ═════════════════════════════════════════════════════════════════════════════
# СТЕК АЛЕРТОВ ВЕТЕРАНСТВА — ПОД ПЛАШКОЙ БЕЗДЕЛЬНИКОВ
# ═════════════════════════════════════════════════════════════════════════════
# Отряд заслужил ранг, но игрок ещё не выбрал награду — и об этом надо сказать
# так, чтобы не пришлось искать этот отряд по карте. Под плашкой рабочих растёт
# вертикальный список иконок: одна на отряд, клик — камера летит к отряду,
# выделяет его и открывает панель с выбором.
#
# ПУСТО — ЗНАЧИТ ПУСТО. Никаких погашенных заглушек: если наград никто не ждёт,
# под плашкой ничего нет вовсе (заказ владельца). Это принципиально отличает
# стек от плашки бездельников, которая на нуле именно ТУСКНЕЕТ, а не исчезает:
# «рабочих без дела ноль» — это ответ, а «наград никто не ждёт» — это отсутствие
# вопроса.
const ALERT_ICON     := 44.0
const ALERT_GAP      := 6
## Отступ стека от нижней кромки плашки бездельников
const ALERT_TOP_GAP  := 8.0
## Пульсация: между какими значениями прозрачности ходит иконка и за сколько
const ALERT_PULSE_MIN  := 0.55
const ALERT_PULSE_TIME := 0.65

var _alert_box: VBoxContainer = null
## Подпись текущего состава стека: пересобираем ТОЛЬКО когда набор отрядов
## изменился. Иначе пульсация сбрасывалась бы в начало каждые полсекунды
var _alert_sig: String = ""

func _build_alert_stack() -> void:
	_alert_box = VBoxContainer.new()
	_alert_box.name = "VeteranAlerts"
	_alert_box.position = Vector2(IDLE_WIDGET_LEFT,
		IDLE_WIDGET_TOP + IDLE_WIDGET_SIZE + ALERT_TOP_GAP)
	_alert_box.add_theme_constant_override("separation", ALERT_GAP)
	# Сам контейнер кликов не ловит — их ловят кнопки внутри
	_alert_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_alert_box)

## Отряды игрока, ждущие выбора награды
func _alerting_squads() -> Array:
	var out: Array = []
	for key in GameManager.squads.keys():
		var sid: int = int(key)
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) != Constants.FACTION_PLAYER:
			continue
		if GameManager.squad_pending(sid) <= 0:
			continue
		if GameManager.squad_members(sid).is_empty():
			continue        # отряд выбит — алерт вместе с ним
		out.append(sid)
	out.sort()
	return out

func _refresh_alert_stack() -> void:
	if _alert_box == null or not is_instance_valid(_alert_box):
		return
	var sids: Array = _alerting_squads()
	var sig := ""
	for s in sids:
		sig += "%d," % int(s)
	if sig == _alert_sig:
		return
	_alert_sig = sig
	# remove_child ДО queue_free: освобождение отложено до конца кадра, и без
	# этого одноимённые новые узлы уникализируются (тот же разбор, что у
	# _rebuild_research_queue)
	for c in _alert_box.get_children():
		_alert_box.remove_child(c)
		c.queue_free()
	for s in sids:
		var sid: int = int(s)
		_alert_box.add_child(_alert_button(sid))

func _alert_button(sid: int) -> Button:
	var btn := Button.new()
	btn.name = "VetAlert_%d" % sid
	btn.custom_minimum_size = Vector2(ALERT_ICON, ALERT_ICON)
	btn.focus_mode = Control.FOCUS_NONE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.13, 0.04, 0.94)
	_corners(st, 6); _borders(st, 2)
	st.border_color = ACTIVE_BORDER_COLOR
	var hov := st.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.26, 0.21, 0.06, 0.98)
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", st)
	var uid: String = GameManager.squad_type(sid)
	var tex := _icon_texture(String(UNIT_ICONS.get(uid, "")))
	if tex != null:
		btn.add_child(_stretched_icon(tex, 4.0))
	# ── ЛЫЧКИ, А НЕ ОБЩИЙ ЗНАЧОК «ЕСТЬ НАГРАДА» ────────────────────────────
	# Заказ владельца: на значке видно ТЕКУЩИЕ лычки отряда, а ЗАСЛУЖЕННАЯ
	# мигает. Одинаковый на всех рангах значок этого сказать не может вовсе —
	# он отвечает «что-то случилось», а не «отряд идёт со второй лычки на
	# третью»
	# «Есть» — это ранги, за которые награда УЖЕ выбрана: уровень отряда
	# поднимается в момент заслуги, а невыбранные награды висят в pending.
	# Считать «есть» по squad_level значило бы показывать заслуженную лычку уже
	# горящей — то есть ровно то, о чём и просили: «текущая одна, вторая мигает»
	_add_alert_chevrons(btn,
		GameManager.squad_level(sid) - GameManager.squad_pending(sid),
		GameManager.squad_choosing_level(sid))
	# ── ДЛИННОЙ ПОДПИСИ БОЛЬШЕ НЕТ ─────────────────────────────────────────
	# Здесь стояло «Отряд опытных копейщиков — заслужен ранг, выберите награду
	# (клик — показать)». Значок висит в углу экрана, и всплывающая над ним
	# строка растягивалась через полверха карты, закрывая поле боя. Что делать,
	# показывают сами лычки: одна горит, следующая мигает
	btn.pressed.connect(func(): _on_alert_pressed(sid))
	# ── ПОДМИГИВАНИЕ ────────────────────────────────────────────────────────
	# Плавный маятник прозрачности, а не мигание рывком: задача — увести взгляд
	# в угол экрана, а не спорить с боем за внимание. Твин привязан к самой
	# кнопке, поэтому исчезает вместе с ней и не требует ручной остановки
	var tw := btn.create_tween()
	tw.set_loops()
	tw.tween_property(btn, "modulate:a", ALERT_PULSE_MIN, ALERT_PULSE_TIME) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(btn, "modulate:a", 1.0, ALERT_PULSE_TIME) \
		.set_trans(Tween.TRANS_SINE)
	return btn

# ═════════════════════════════════════════════════════════════════════════════
# ПОДСВЕТКИ-РАДАРА ПО КЛИКУ АЛЕРТА БОЛЬШЕ НЕТ (заказ владельца, разворот)
# ═════════════════════════════════════════════════════════════════════════════
# Здесь жило пульсирующее золотое кольцо (_ping_squad / _tick_ping): по клику
# на значок ранга оно сжималось к отряду поверх толпы. Владелец потребовал
# убрать его целиком и заменить ДВУМЯ обычными вещами: камера прыгает на отряд
# сразу, а сам отряд обводится ШТАТНЫМИ жёлтыми кольцами выделения.
#
# Почему кольцо мешало, видно на скриншоте владельца: метка рисовалась по
# МЕДИАНЕ отряда, а плавная глиссада камеры в этот момент ещё ехала — кольцо
# успевало отпульсировать над пустой травой, пока отряд не появился в кадре.
# Мгновенный перевод камеры снимает и это: к первому же кадру отряд уже на
# экране, а под ногами у него — те самые кольца, по которым игрок и привык
# узнавать выделенное.
#
# ЕДИНСТВЕННАЯ ТОНКОСТЬ — ПАУЗА. Слои колец ведёт GameManager._process, а он
# PAUSABLE: награду выбирают на паузе, и без явной подачи буфера кольца
# появились бы только после снятия паузы. Поэтому _on_alert_pressed подаёт их
# ОДИН раз вручную (см. там же) — это ровно тот случай, ради которого кольцо
# в своё время и рисовали в HUD.

## ── ЛЫЧКИ НА ЗНАЧКЕ АЛЕРТА ─────────────────────────────────────────────────
## have — сколько лычек у отряда СЕЙЧАС, want — ранг, награду за который он
## ждёт. Заслуженная лычка мигает отдельно от заработанных: у неё свой твин,
## поэтому «уже моё» и «вот-вот моё» на значке видно порознь.
##
## Глифы берутся из veteran_badge_text — того же места, откуда их берут портрет
## и карточка отряда. Разбирать их посимвольно приходится потому, что грейд
## меняет не только ЧИСЛО лычек: на четвёртом они разворачиваются в другую
## сторону, а третий и шестой добавляют белый наконечник. Общий префикс —
## «что уже есть», хвост — «что прибавится»; префикса нет (разворот) — новый
## значок мигает целиком, и это честно: изменилось всё
const ALERT_CHEV_SIZE := 13
const ALERT_CHEV_BLINK := 0.42
## ── ЛЫЧКА НА ЗНАЧКЕ — БЕЛАЯ, А НЕ ЦВЕТА СВОЕГО ГРЕЙДА ──────────────────────
## Заказ владельца по скриншоту: «красную полоску внутри жёлтой иконки в левом
## верхнем углу сделать чисто белой». Цвет брался из veteran_badge_color, а у
## первых трёх грейдов вымпел КРАСНЫЙ — на золотой рамке значка красная лычка
## читалась как индикатор тревоги, а не как ранг.
##
## Цвет грейда при этом никуда не делся: он по-прежнему красит и знамя в мире,
## и значок на портрете, и флажки «было → стало». Меняется РОВНО значок в углу
## экрана — тот, что висит на золотой плашке
const ALERT_CHEV_COLOR := Color(1, 1, 1)

func _add_alert_chevrons(btn: Button, have_lvl: int, want_lvl: int) -> void:
	var have: String = _UCfg.veteran_badge_text(have_lvl)
	var want: String = _UCfg.veteran_badge_text(maxi(want_lvl, have_lvl + 1))
	var steady: String = have
	var blink: String = want
	if want.begins_with(have) and have != "":
		blink = want.substr(have.length())
	elif have != "":
		steady = ""              # знак сменился целиком — старый не показываем
	var row := HBoxContainer.new()
	row.name = "AlertChevrons"
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	row.offset_left = 2; row.offset_top = 0
	btn.add_child(row)
	if steady != "":
		row.add_child(_alert_chevron_label(steady, ALERT_CHEV_COLOR, false))
	if blink != "":
		row.add_child(_alert_chevron_label(blink, ALERT_CHEV_COLOR, true))

func _alert_chevron_label(txt: String, col: Color, blinking: bool) -> Label:
	var lb := Label.new()
	lb.text = txt
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.add_theme_font_size_override("font_size", ALERT_CHEV_SIZE)
	lb.add_theme_color_override("font_color", col)
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lb.add_theme_constant_override("outline_size", 4)
	if blinking:
		# Мигает ТОЛЬКО новая лычка. Сама кнопка при этом дышит прозрачностью
		# целиком (см. ниже) — два разных ритма на одном значке читаются как
		# «горит» и «вот-вот загорится», а не как сбой отрисовки
		var tw := lb.create_tween()
		tw.set_loops()
		tw.tween_property(lb, "modulate:a", 0.15, ALERT_CHEV_BLINK) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(lb, "modulate:a", 1.0, ALERT_CHEV_BLINK) \
			.set_trans(Tween.TRANS_SINE)
	return lb

## Клик по алерту: камера к отряду, отряд выделен, панель открыта с выбором
func _on_alert_pressed(sid: int) -> void:
	var men: Array = GameManager.squad_members(sid)
	if men.is_empty():
		_alert_sig = ""          # отряд уже выбит — пересобрать стек
		_refresh_alert_stack()
		return
	var main := GameManager.main
	if main == null or not is_instance_valid(main):
		return
	# ── КАМЕРА СТАВИТСЯ НА ОТРЯД СРАЗУ (заказ владельца, разворот) ─────────
	# Здесь была ПЛАВНАЯ глиссада (glide_camera_to): её просили, чтобы объектив
	# не швыряло одним кадром. Владелец требование развернул — «по клику на
	# значок камера должна МГНОВЕННО встать на отряд». Причина видна на его
	# скриншоте: пока камера едет, отряда в кадре ещё нет, а метка над ним уже
	# отгорела — игрок смотрит на пустое поле.
	#
	# Механизм глиссады (RTSCamera.glide_to) при этом остаётся на месте и
	# по-прежнему проверяется стендом: он нужен всему остальному, что переводит
	# камеру мягко, и понадобится, если требование развернут обратно.
	# pan_to пишет фокус камеры прямо, поэтому работает и на паузе
	# ── ОТРЯД В УКРЕПЛЕНИИ: выделяем само здание (ТЗ 19.09.2026, блок 4.1) ──
	# Укрытых бойцов выделить нельзя, панель награды им показывает панель
	# здания (_garrison_vet_menu)
	var host = null
	for m0 in men:
		if is_instance_valid(m0) and (m0 as Unit).garrisoned:
			var h = (m0 as Unit).garrison_host
			if h != null and is_instance_valid(h):
				host = h
			break
	var sm = main.selection_manager
	if host != null:
		main.focus_camera_on((host as Node3D).global_position)
		if sm != null and is_instance_valid(sm):
			sm._clear_selection()
			sm._select(host)
			GameManager.on_selection_changed(sm.selected_units)
		else:
			show_selection([host])
		return
	main.focus_camera_on(GameManager.squad_centroid(sid))
	if sm != null and is_instance_valid(sm):
		sm._clear_selection()
		for m in men:
			if is_instance_valid(m):
				sm._select(m)
		GameManager.on_selection_changed(sm.selected_units)
	else:
		show_selection(men)
	# ── ШТАТНЫЕ ЖЁЛТЫЕ КОЛЬЦА ВМЕСТО СВОЕЙ МЕТКИ ───────────────────────────
	# Выделение выше уже поставило кольца в слой SelectionDecalRenderer, но
	# ведёт этот слой GameManager._process, а он PAUSABLE: награду выбирают на
	# паузе, и до её снятия буфер колец не подавался бы вовсе. Подаём один раз
	# руками — это дешевле собственного слоя подсветки и, главное, показывает
	# игроку РОВНО ТО ЖЕ, что он видит при обычном выделении отряда
	GameManager.sel_decals.update_all()
	GameManager.sel_decals.flush()

func _update_idle_counter(delta: float) -> void:
	if _idle_btn == null or not is_instance_valid(_idle_btn):
		return
	# Перебор группы рабочих — раз в полсекунды: считать его каждый кадр
	# незачем, счётчик и так меняется медленно
	_idle_timer -= delta
	if _idle_timer > 0.0:
		return
	_idle_timer = 0.5
	# Заодно считаем РАБОТАЮЩИХ: по их числу AudioManager прореживает стук
	# топоров. Один перебор группы на полсекунды вместо перебора на каждый удар
	var busy := 0
	for n2 in get_tree().get_nodes_in_group("all_units"):
		var w2 := n2 as Worker
		if w2 != null and not w2.is_dead() and w2.state == Unit.State.GATHERING:
			busy += 1
	AudioManager.active_workers = busy
	# Стек алертов ветеранства живёт на том же полусекундном такте: он тоже
	# меняется медленно, а пересборка узлов на каждый кадр сбрасывала бы
	# пульсацию иконок в начало
	_refresh_alert_stack()
	var n: int = _idle_workers().size()
	if n == _idle_last:
		return          # ничего не поменялось — не трогаем узлы UI
	_idle_last = n
	_apply_idle_state(n)

func _process(_delta: float) -> void:
	# Часы подсистемы (perf_config.sys_meter, qa_bigstand): одна проверка bool
	if not _OptSys.sys_meter:
		_process_timed(_delta)
		return
	var _sys_t0: int = Time.get_ticks_usec()
	_process_timed(_delta)
	_OptSys.sys_add("hud", Time.get_ticks_usec() - _sys_t0)

func _process_timed(_delta: float) -> void:
	if _counts_dirty:
		_refresh_live_counts()
	_check_portrait_hover()
	_update_top_right(_delta)
	_update_idle_counter(_delta)
	_update_resource_income(_delta)
	# ВЫДЕЛЕННЫЙ ОБЪЕКТ СНЕСЛИ — панель обязана уйти вместе с ним.
	# Проверка идёт по ЗАПОМНЕННОМУ instance_id, а не по «_selected_node != null»:
	# в Godot 4 освобождённый объект РАВЕН null, поэтому прежнее условие
	# «!= null and not is_instance_valid()» не срабатывало никогда, и панель
	# мёртвого здания оставалась на экране целиком. Кнопки держат объект в
	# лямбде — клик по такой давал «SCRIPT ERROR: Nonexistent function
	# 'train_from_config' in base 'Nil'», а цифра заказов на иконке навсегда
	# замирала на последнем значении.
	# Пересобираем панель в состояние «ничего не выбрано» — то же самое, что при
	# клике по пустому месту: заодно чистятся ярлыки, очередь, полоса гарнизона
	# и панель фильтра типов
	if _selected_iid != 0 and not is_instance_valid(_selected_node):
		_selected_node = null
		_selected_iid  = 0
		show_selection([])
		return
	if _selected_node == null:
		return
	if "current_health" in _selected_node:
		var hp_text: String = "%s  %d/%d HP" % [_selected_node.display_name,
			int(_selected_node.current_health), int(_selected_node.max_health)]
		if _castle_boost and _selected_node is Building:
			# Производственное здание (Замок / Бараки / TownCenter): строка живёт
			# в компактной шапке панели, а не в info_label (см. _refresh_panel) —
			# но обновлять её живьём всё равно нужно, иначе после урона там
			# застынет старое HP. Проверка по Building, а не по Castle: под единый
			# стандарт попали и Бараки, и у них подпись замирала бы
			# У башни гарнизон и обзор — второй строкой той же шапки (ТЗ
			# 20.10.2026: строка в info_label ложилась на шапку). Меняется,
			# пока отряд заходит, и обновляется вместе с HP. БАРАКИ — НЕ
			# БАШНЯ (ТЗ 18.09.2026, п. 7): у них этой строки нет
			if _selected_node is Castle and not (_selected_node as Castle).is_stronghold() \
					and not (_selected_node is Barracks):
				hp_text += "\n" + _tower_info_text(_selected_node as Castle).replace("\n", " · ")
			_update_castle_caption(hp_text)
		elif _selected_node is Building \
				and _UCfg.is_house((_selected_node as Building).building_id):
			# Дом: слоты лимита и еда, а не голое HP (см. _house_info_text)
			info_label.text = _house_info_text(_selected_node as Building)
		elif forge_visible() and _selected_node is Smithy:
			# У кузницы своя панель: строка «Кузница N/N HP» живёт в её левом
			# блоке, а info_label общей панели сейчас вообще не показан
			if _forge_caption != null and is_instance_valid(_forge_caption):
				_forge_caption.text = hp_text
		elif _selected_node is Worker and _OptSys.worker_grid_panel:
			# Панель рабочего сеткой — без подписи (ТЗ 30.10.2026)
			pass
		elif not (_selected_node is Spearman) and not (_selected_node is Unit and _selected_node.display_name == "Мечник"):
			info_label.text = hp_text
	if not (_selected_node is Building):
		_clear_queue_ui()
		return
	var bld: Building = _selected_node
	if bld is Smithy:
		var cur_id: String = (bld as Smithy).research_id
		if cur_id != _last_research_id:
			_last_research_id = cur_id
			# Исследование сменилось: изученный узел зеленеет, зависимые от
			# него открываются, следующее из очереди получает полосу.
			# Перестраиваем ДРЕВО, а не всё выделение — show_selection()
			# пересобрал бы панель целиком ради одной перекраски.
			# ЛЮБАЯ смена id, а не только на пустой: с очередью id меняется
			# «a → b» в одном кадре, и пустым не бывает вовсе (ТЗ 28.10.2026;
			# основной путь — сигнал research_finished, это страховка)
			if forge_visible():
				_rebuild_forge()
			else:
				show_selection([bld])
				return
	# Состав и прогресс очереди рисует отдельная колонка (иконка + шкала +
	# «В очереди / В ожидании»). Текст в info-колонке остаётся КОРОТКИМ и
	# постоянной длины — именно его рост раньше раздвигал панель
	_update_queue_ui(bld)
	_refresh_keep_rank()
	_refresh_tower_fort()
	_refresh_shelter_slot()
	if progress_bar == null:
		return
	_refresh_train_badges(bld)
	if not bld.production_queue.is_empty():
		# ОДНА ШКАЛА НА ВЕСЬ НАЙМ — та, что нарисована на иконке в колонке
		# очереди (см. _update_queue_ui). Большая шкала в колонке слева
		# показывала ровно то же самое и только дублировала её
		progress_bar.visible = false
		_set_progress_text("")
	elif bld is Smithy and not (bld as Smithy).research_id.is_empty():
		# Кузница качает технологию: та же шкала, но своё время из конфига
		var sm := bld as Smithy
		var slot: Dictionary = _UCfg.get_upgrade_slot(sm.research_id)
		progress_bar.visible   = true
		progress_bar.max_value = 1.0
		progress_bar.value     = sm.research_progress()
		# ТЕКСТ — БЕЗ ПЕРЕСЧЁТА ВЫСОТЫ ПАНЕЛИ КАЖДЫЙ КАДР: строка появляется и
		# исчезает редко, а вот процент в ней меняется постоянно. Высоту трогаем
		# только на СМЕНЕ ВИДИМОСТИ, иначе панель дёргалась бы 60 раз в секунду
		var was: bool = progress_label.visible
		_set_progress_text("Исследование: %s %d%%" % [
			String(slot.get("name", sm.research_id)), int(sm.research_progress() * 100.0)])
		if was != progress_label.visible:
			_sync_panel_height()
	else:
		progress_bar.visible  = false
		var was2: bool = progress_label.visible
		_set_progress_text("")
		if was2:
			_sync_panel_height()

# ─────────────────────────────────────────────────────────────────────────────
# MAIN MENU / PAUSE / VICTORY / DEFEAT
# ─────────────────────────────────────────────────────────────────────────────

func show_main_menu() -> void:
	_clear_overlay()
	_overlay = _full_overlay(Color(0.04, 0.05, 0.12, 0.96))
	var vbox := _center_vbox(_overlay)
	var title := Label.new(); title.text = "⚔  Ten Thousand Spearmen"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.30))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vbox.add_child(title)
	var sub := Label.new(); sub.text = "Стратегия в реальном времени"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vbox.add_child(sub)
	vbox.add_child(_spacer(20))
	vbox.add_child(_make_btn("  Новая игра  ", Color(0.15, 0.35, 0.15), func():
		_clear_overlay(); GameManager.main.start_game()))
	vbox.add_child(_make_btn("  Выход  ", Color(0.35, 0.10, 0.10), func():
		GameManager.main.quit_game()))

# ─────────────────────────────────────────────────────────────────────────────
# НАСТРОЙКИ (звук, V-Sync, сложность, перемирие, автосохранение) — с 21.10.2026
# в общем окне с вкладками scripts/ui/SettingsWindow.gd (его открывает пауза)
# ─────────────────────────────────────────────────────────────────────────────

## Плашка «Игра сохранена» над шапкой — зовёт Autosave по завершении записи.
## Гаснет сама; живёт на паузе (HUD — ALWAYS)
var _autosave_note: Label = null
var _autosave_note_until_ms: int = 0
func show_autosave_note(text: String) -> void:
	if _autosave_note == null or not is_instance_valid(_autosave_note):
		_autosave_note = Label.new()
		_autosave_note.name = "AutosaveNote"
		_autosave_note.add_theme_font_size_override("font_size", 13)
		_autosave_note.add_theme_color_override("font_color", Color(0.86, 0.92, 0.80))
		_autosave_note.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_autosave_note.add_theme_constant_override("shadow_offset_x", 1)
		_autosave_note.add_theme_constant_override("shadow_offset_y", 1)
		_autosave_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_autosave_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_autosave_note.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_autosave_note.position = Vector2(-160.0, 44.0)
		_autosave_note.size = Vector2(320.0, 20.0)
		add_child(_autosave_note)
	_autosave_note.text = text
	_autosave_note.visible = true
	_autosave_note_until_ms = Time.get_ticks_msec() + 2500
	get_tree().create_timer(2.6, true).timeout.connect(func():
		if _autosave_note != null and is_instance_valid(_autosave_note) \
				and Time.get_ticks_msec() >= _autosave_note_until_ms:
			_autosave_note.visible = false)
# ─────────────────────────────────────────────────────────────────────────────
# СЛОЖНОСТЬ В МЕНЮ ПАУЗЫ
#
# ЧТО МЕНЯЕТСЯ СРАЗУ, А ЧТО — СО СЛЕДУЮЩЕЙ ПАРТИИ, И ПОЧЕМУ ЭТО НАПИСАНО ПРЯМО
# НА ЭКРАНЕ. Лимиты армии, потолок рабочих, темп найма и стройки читаются
# ВЖИВУЮ — их смена действует с этой же секунды. А стартовый запас ресурсов и
# стартовые отряды раздаются ОДИН РАЗ, при закладке партии, и задним числом их
# не выдать: игрок, переключивший сложность на двадцатой минуте, гарнизона
# противнику уже не добавит. Молчать об этом нельзя — иначе переключатель
# выглядит сломанным.
# ─────────────────────────────────────────────────────────────────────────────
# СОХРАНЕНИЕ И ЗАГРУЗКА В МЕНЮ ПАУЗЫ
#
# ТРИ СЛОТА, А НЕ ОДНО «БЫСТРОЕ СОХРАНЕНИЕ». Партия здесь длинная, и один слот
# означал бы, что сохранение перед неудачной атакой стирает сохранение перед
# удачной. Подпись слота показывает время и сложность — по ней игрок и узнаёт
# свои сохранения, а не по номеру.
#
# ОБЕ КНОПКИ ЖИВУТ В ОДНОМ ЭКРАНЕ И ПЕРЕСТРАИВАЮТ ЕГО НА МЕСТЕ, а не уводят на
# отдельную страницу: сохранение — действие на две секунды, и «войти в меню
# сохранений, выбрать, вернуться» здесь было бы тремя лишними кликами.
# ─────────────────────────────────────────────────────────────────────────────
const SAVE_SLOT_W := 380.0

func _add_save_slots(parent: Control, saving: bool) -> void:
	# Заголовок «Сохранить/Загрузить игру» — у рамки окна (_modal_frame)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color(0.66, 0.80, 0.68))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# ГЕОМЕТРИЯ ОКНА НЕ ПЛЫВЁТ (ТЗ 24.10.2026, блок 6): ширина и высота
	# строки статуса зарезервированы заранее, переносов нет — «Сохранено в
	# слот N» больше не добавляет строку и не раздвигает раму
	status.name = "SaveStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.custom_minimum_size = Vector2(SAVE_SLOT_W, 18)
	status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Слот автосохранения (0) виден в обоих режимах; на сохранении — только
	# для чтения: руками в него не пишут, его перезаписывает Autosave
	var slots: Array = [_SaveLoad.AUTOSAVE_SLOT]
	for i in range(_SaveLoad.SLOT_COUNT):
		slots.append(i + 1)
	for s in slots:
		var slot: int = int(s)
		var btn := Button.new()
		btn.name = "SaveSlot%d" % slot
		btn.text = _SaveLoad.slot_label(slot)
		btn.custom_minimum_size = Vector2(SAVE_SLOT_W, 38)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		# Текст не раздвигает кнопку: длинная подпись обрезается многоточием
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.focus_mode = Control.FOCUS_NONE
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		_MUI.style_button(btn, "steel", 14)
		# Пустой слот на загрузке гасится, а не прячется: игрок должен видеть,
		# что слотов три, и один из них свободен
		if not saving and not _SaveLoad.has_save(slot):
			btn.disabled = true
		if saving and slot == _SaveLoad.AUTOSAVE_SLOT:
			btn.disabled = true
		parent.add_child(btn)
		btn.pressed.connect(func():
			if saving:
				var err: String = _SaveLoad.save_game(GameManager.main, slot)
				if err.is_empty():
					btn.text = _SaveLoad.slot_label(slot)
					status.text = "Сохранено в слот %d" % slot
				else:
					status.add_theme_color_override("font_color",
						Color(0.92, 0.66, 0.60))
					status.text = err
			else:
				# ЗАГРУЗКА ПЕРЕЗАПУСКАЕТ СЦЕНУ, поэтому дальше этого вызова в
				# этом меню уже ничего не произойдёт: узлы будут другие
				var err2: String = _SaveLoad.request_load(get_tree(), slot)
				if not err2.is_empty():
					status.add_theme_color_override("font_color",
						Color(0.92, 0.66, 0.60))
					status.text = err2)
	parent.add_child(status)
	parent.add_child(_spacer(8))

## Экран сохранения/загрузки поверх паузы. Отдельный экран, а не ряд кнопок в
## главном меню паузы: три слота с подписями занимают всю его высоту
func _show_save_menu(saving: bool) -> void:
	_clear_overlay()
	get_tree().paused = true
	_overlay = _full_overlay(Color(0.02, 0.02, 0.03, 0.62))
	var vbox := _modal_frame(_overlay, "Сохранить игру" if saving else "Загрузить игру")
	_add_save_slots(vbox, saving)
	var back := _make_btn("Назад", Color(0.16, 0.20, 0.30), func():
		_show_pause_menu())
	back.name = "SaveBack"
	vbox.add_child(back)

# ─────────────────────────────────────────────────────────────────────────────
# МЕНЮ ПАУЗЫ: КОМПАКТНОЕ ОКНО В КОВАНОЙ РАМЕ (ТЗ 21.10.2026)
#
# Было: столбец кнопок прямо на затемнении, а «Настройки ▼» разворачивали
# под ним длинную ленту (сложность, громкости, V-Sync, перемирие,
# автосохранение) — меню уезжало за нижнюю кромку, и его крутили колесом.
# Стало: небольшое окно по центру — заголовок «Пауза» и семь кнопок; кнопка
# «Настройки» открывает ПОВЕРХ ПАУЗЫ то же окно с вкладками, что и главное
# меню (scripts/ui/SettingsWindow.gd, режим «в партии»). Закрыли настройки —
# снова окно паузы. Прокрутки нет нигде.
#
# Имена и поля прежние: кнопка «PauseOptions», _pause_options_open (true —
# окно настроек открыто сразу; так его открывают стенды), _overlay.
# ─────────────────────────────────────────────────────────────────────────────

## Открыты ли настройки поверх паузы. Живёт между пересборками меню
var _pause_options_open: bool = false

func _show_pause_menu() -> void:
	_clear_overlay()
	get_tree().paused = true
	_overlay = _full_overlay(Color(0.02, 0.02, 0.03, 0.62))
	var vbox := _modal_frame(_overlay, "Пауза")
	vbox.name = "PauseColumn"
	vbox.add_child(_make_btn("Продолжить", Color(0.10, 0.28, 0.10), func():
		get_tree().paused = false; _clear_overlay()))
	vbox.add_child(_make_btn("Сохранить игру", Color(0.12, 0.24, 0.34), func():
		_show_save_menu(true)))
	vbox.add_child(_make_btn("Загрузить игру", Color(0.12, 0.24, 0.34), func():
		_show_save_menu(false)))
	var opts_btn := _make_btn("Настройки", Color(0.20, 0.20, 0.26), func():
		_open_pause_settings())
	opts_btn.name = "PauseOptions"
	vbox.add_child(opts_btn)
	# ── ТРИ КНОПКИ, ТРИ РАЗНЫХ ДЕЙСТВИЯ (ТЗ 23.09.2026, п. 1) ──────────────
	vbox.add_child(_make_btn("Заново", Color(0.18, 0.28, 0.16), func():
		_clear_overlay()
		GameManager.main.restart_game()))
	vbox.add_child(_make_btn("Выйти в меню", Color(0.25, 0.10, 0.08), func():
		GameManager.main.quit_to_menu()))
	vbox.add_child(_make_btn("Выход из игры", Color(0.30, 0.08, 0.08), func():
		GameManager.main.quit_game()))
	if _pause_options_open:
		_open_pause_settings()

## Окно настроек с вкладками поверх паузы; рама паузы на это время прячется
func _open_pause_settings() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	_pause_options_open = true
	var frame: Node = _overlay.get_node_or_null("ModalCenter")
	if frame != null:
		(frame as CanvasItem).visible = false
	var win = _SettingsWin.new()
	win.name = "PauseOptionsBox"
	win.setup(true)
	win.closed.connect(func():
		_pause_options_open = false
		if frame != null and is_instance_valid(frame):
			(frame as CanvasItem).visible = true)
	_overlay.add_child(win)

## Рама окна по центру оверлея с заголовком; возвращает столбец под кнопки.
## Тема MedievalUI ставится корню рамы — выпадающие списки и подсказки внутри
## наследуют её
func _modal_frame(parent: Control, title: String) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.name = "ModalCenter"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.process_mode = Node.PROCESS_MODE_ALWAYS
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.theme = _MUI.theme()
	parent.add_child(cc)
	var panel := PanelContainer.new()
	panel.name = "ModalPanel"
	panel.add_theme_stylebox_override("panel", _MUI.frame_style(30.0))
	cc.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 9)
	panel.add_child(vbox)
	var lbl := _MUI.title_label(title, 32)
	lbl.name = "ModalTitle"
	vbox.add_child(lbl)
	vbox.add_child(_MUI.divider(220.0))
	return vbox

# ═════════════════════════════════════════════════════════════════════════════
# ФОКУС ПАНЕЛИ ЗДАНИЯ
#
# Заказ владельца: панель Кузницы/Замка/Бараков НЕ закрывается от кликов внутри
# себя (найм, заказ технологии) и закрывается СТРОГО двумя способами — Escape
# либо клик по игровому миру ВНЕ её границ.
#
# Почему это решается ГЕОМЕТРИЕЙ, а не «пусть Control съест событие».
# Съедание уже есть: Button и PanelContainer стоят в MOUSE_FILTER_STOP, и
# _unhandled_input до SelectionManager не доходит. Но дыр в этом ровно столько,
# сколько в панели прозрачных мест: Label'ы и иконки стоят в MOUSE_FILTER_IGNORE
# (иначе они перехватывали бы наведение у кнопок под собой), просветы между
# кнопками не накрыты ничем, а у кузницы холст стрелок и сама сетка узлов —
# голые Control с IGNORE. Клик в любой такой просвет проваливался в мир, там
# читался как «клик по пустой земле» и снимал выделение — то есть панель
# закрывалась от попадания МИМО кнопки, а не от клика по ней.
#
# Поэтому правило формулируется один раз и по прямоугольнику: точка внутри
# видимой панели — событие панели, и мира оно не касается. Спрашивает
# SelectionManager перед разбором клика (см. _handle_single_click).
# ═════════════════════════════════════════════════════════════════════════════

## Панели, которые «держат фокус»: пока точка внутри любой из них, клик
## считается кликом по интерфейсу. Собирается по факту видимости, поэтому
## скрытая панель ничего не перехватывает
func _focus_panels() -> Array:
	var out: Array = []
	# _forge_tip / _stat_card / _bonus_tip — ПЛАВАЮЩИЕ окна ЗА границей своей
	# панели (окно кузницы по макету стоит справа от неё, см. _pin_forge_tip).
	# В прямоугольник панели они не попадают, и без них клик по видимой
	# подсказке проваливался в мир и закрывал ту самую панель, к которой она
	# относится
	for n in [_bottom_panel, _forge_panel, _overbar, _res_panel,
			_top_right, _idle_widget, _stat_panel, _garrison_strip,
			_forge_tip, _stat_card, _bonus_tip, _market_panel, _gforge_panel]:
		var c := n as Control
		if c != null and is_instance_valid(c) and c.visible:
			# Прозрачная (спрятанная до наведения) таблица статов клик не держит
			if c == _stat_panel and not stat_panel_shown():
				continue
			out.append(c)
	return out

## Точка экрана попадает в интерфейс? Публичная — её зовёт SelectionManager
func point_over_ui(p: Vector2) -> bool:
	for c in _focus_panels():
		if (c as Control).get_global_rect().has_point(p):
			return true
	return false

## Открыта ли сейчас панель здания (её и закрывает Escape)
func building_panel_open() -> bool:
	if forge_visible():
		return true
	return _selected_node is Building and _bottom_panel != null \
		and is_instance_valid(_bottom_panel) and _bottom_panel.visible

## Закрыть панель здания и снять выделение. false — закрывать было нечего,
## и тогда Escape отрабатывает как обычно (меню настроек)
func _close_building_panel() -> bool:
	if not building_panel_open():
		return false
	var sm = GameManager.main.selection_manager if GameManager.main != null else null
	if sm != null and is_instance_valid(sm):
		sm.clear_selection()
	else:
		show_selection([])
	return true

## ── TAB ЛОВИТСЯ В _input, А НЕ В _unhandled_input (ТЗ 11.10.2026) ──────────
## Tab в Godot по умолчанию — навигация фокуса GUI (ui_focus_next): если у
## любой кнопки панели был фокус (после клика по ней), движок съедал Tab ДО
## _unhandled_input — переключение родов и вкладок кузницы «то работало, то
## нет». _input идёт раньше GUI, и событие помечается обработанным здесь
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	# ── TAB (ТЗ 10.10.2026, блоки 3-4): в кузнице — следующее древо, при
	# смешанном выделении — следующий род войск (детальная панель отрядов)
	if (k.keycode == KEY_TAB or k.physical_keycode == KEY_TAB) and not k.echo 			and _overlay == null:
		if forge_visible():
			var tabs: Array = _Forge.UNIT_TABS
			var i: int = tabs.find(_forge_unit)
			forge_set_tab(String(tabs[(i + 1) % tabs.size()]))
			get_viewport().set_input_as_handled()
			return
		if cycle_expanded_type():
			get_viewport().set_input_as_handled()
			return

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_ESCAPE:
		if _overlay != null:
			_red_defeat_open = false
			get_tree().paused = false
			AudioManager.set_paused(false)
			_clear_overlay()
			return
		# ── ESCAPE СНАЧАЛА ЗАКРЫВАЕТ ПАНЕЛЬ ЗДАНИЯ ──────────────────────────
		# Заказ владельца: панель здания закрывается СТРОГО по Escape или по
		# клику вне её. Меню настроек при этом никуда не делось — оно открывается
		# следующим нажатием, когда закрывать уже нечего. Порядок именно такой:
		# панель — то, что игрок видит прямо сейчас, и Escape в любой игре
		# сначала убирает верхний слой, а не открывает новый поверх него
		if _close_building_panel():
			get_viewport().set_input_as_handled()
			return
		_show_pause_menu()
		return
	# ── Z: ПАУЗА ИГРЫ И ЗВУКА ────────────────────────────────────────────────
	# Ловится ЗДЕСЬ, а не в Main._input: Main живёт в PROCESS_MODE_INHERIT и на
	# паузе ввод до него не доходит — с паузы было бы не сняться. HUD же стоит
	# в PROCESS_MODE_ALWAYS (см. _ready) и слышит клавиатуру в обоих состояниях.
	# echo отсекаем: зажатая Z иначе мигала бы паузой с частотой автоповтора
	# ПРОБЕЛ — ВТОРАЯ КЛАВИША ТОЙ ЖЕ ПАУЗЫ (заказ владельца). Именно вторая, а не
	# замена: Z уже описан в подсказках и в стендах, а пробел — то, что игрок в
	# тактической игре жмёт не глядя. Обе идут одним путём (toggle_pause), поэтому
	# «пауза с клавиши» и «пауза с иконки» остаются одним поведением
	var pause_key: bool = k.keycode == KEY_Z or k.physical_keycode == KEY_Z \
		or k.keycode == KEY_SPACE or k.physical_keycode == KEY_SPACE
	if pause_key and not k.echo:
		# Пока открыт оверлей (меню/победа/поражение) — Z не трогаем: там своя
		# пауза и свои кнопки, снять её вслепую значило бы продолжить игру
		# под непрозрачным экраном
		if _overlay == null:
			toggle_pause()
			get_viewport().set_input_as_handled()

## ── БАННЕР ПОБЕДЫ (ТЗ 29.10.2026, п. 1) ─────────────────────────────────────
## Не оверлей: мир не затеняется и не блокируется, игрок доигрывает
## песочницу (добивает орду, строит). Сверху по центру — крупное «ПОБЕДА!»,
## под ним одна строка подсказки и ряд из трёх компактных кнопок. Корень
## пропускает мышь (MOUSE_FILTER_IGNORE): клики по карте вокруг баннера
## доходят до игры, ловят их только сами кнопки. Escape и пауза работают
## как обычно — баннер не числится в _overlay
var _victory_banner: Control = null
const VICTORY_BTN_SIZE := Vector2(150, 34)
const VICTORY_TOP := 64.0

func show_victory() -> void:
	hide_victory()
	var root := Control.new()
	root.name = "VictoryBanner"
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(root)
	var vbox := VBoxContainer.new()
	vbox.name = "VictoryBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(vbox)
	var t := Label.new(); t.text = "ПОБЕДА!"
	t.name = "VictoryTitle"
	t.add_theme_font_size_override("font_size", 56)
	t.add_theme_color_override("font_color", Color(0.95, 0.84, 0.18))
	t.add_theme_color_override("font_outline_color", Color(0.10, 0.06, 0.02))
	t.add_theme_constant_override("outline_size", 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(t)
	var row := HBoxContainer.new()
	row.name = "VictoryButtons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var specs: Array = [
		["Играть снова", Color(0.14, 0.32, 0.14), "VictoryRestart",
			func(): GameManager.main.restart_game()],
		["Выход", Color(0.25, 0.10, 0.08), "VictoryMenu",
			func(): GameManager.main.quit_to_menu()],
		["Выход из игры", Color(0.30, 0.08, 0.08), "VictoryQuit",
			func(): GameManager.main.quit_game()],
	]
	for sp in specs:
		var b := _make_btn(String(sp[0]), sp[1], sp[3])
		b.name = String(sp[2])
		b.custom_minimum_size = VICTORY_BTN_SIZE
		_MUI.style_button(b, _menu_kind(sp[1]), 14)
		row.add_child(b)
	# Ширина считается по содержимому; центрируем по горизонтали
	var w: float = vbox.get_combined_minimum_size().x
	vbox.position = Vector2(-w * 0.5, VICTORY_TOP)
	vbox.size = vbox.get_combined_minimum_size()
	_victory_banner = root

## ── ОКНО «КРАСНЫЙ ИГРОК РАЗБИТ» (ТЗ 30.10.2026, скриншот 00:44) ──────────────
## Последний боец и последняя постройка красного пали, а орда ещё жива: партия
## продолжается. Модальное окно с иллюстрацией (assets/ui/red_defeated.png,
## tools/make_red_defeat_art.py), игра на паузе, «Продолжить» — снять окно и
## паузу. Окно в _overlay: Z/пробел его не трогают, Escape закрывает как кнопка
const RED_DEFEAT_ART := "res://assets/ui/red_defeated.png"
const RED_DEFEAT_ART_W := 640.0
var _red_defeat_open: bool = false

func show_red_defeated() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = _full_overlay(Color(0.03, 0.02, 0.02, 0.62))
	_overlay.name = "RedDefeatOverlay"
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	var vbox := _modal_frame(_overlay, "Красный игрок разбит")
	vbox.name = "RedDefeatBox"
	if ResourceLoader.exists(RED_DEFEAT_ART):
		var art := TextureRect.new()
		art.name = "RedDefeatArt"
		art.texture = load(RED_DEFEAT_ART)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var ts: Vector2 = art.texture.get_size()
		art.custom_minimum_size = Vector2(RED_DEFEAT_ART_W, RED_DEFEAT_ART_W * ts.y / maxf(ts.x, 1.0))
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(art)
	var msg := Label.new()
	msg.name = "RedDefeatText"
	msg.text = "Армия и все постройки красного уничтожены.\nИгра продолжается: на карте ещё орда гоблинов."
	msg.add_theme_font_size_override("font_size", 17)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(msg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row)
	var b := _make_btn("Продолжить", Color(0.14, 0.32, 0.14), func(): close_red_defeated())
	b.name = "RedDefeatContinue"
	b.custom_minimum_size = Vector2(200, 40)
	_MUI.style_button(b, _menu_kind(Color(0.14, 0.32, 0.14)), 17)
	row.add_child(b)
	_red_defeat_open = true
	set_paused(true)

func close_red_defeated() -> void:
	if not _red_defeat_open:
		return
	_red_defeat_open = false
	_clear_overlay()
	set_paused(false)

func red_defeat_open() -> bool:
	return _red_defeat_open

## ── УВЕДОМЛЕНИЕ (ТЗ 30.10.2026) ─────────────────────────────────────────────
## Строка над нижней панелью, как подсказка постройки, но без её префикса и
## сама гаснет через sec. Сообщения орды и отказы лимита шли через
## show_placement_hint и висели «Выберите место для постройки: …» до конца партии
var _notice: Label = null
const NOTICE_SEC := 6.0

func show_notice(text: String, sec: float = NOTICE_SEC) -> void:
	if _notice != null and is_instance_valid(_notice):
		_notice.queue_free()
	var lbl := Label.new()
	lbl.name = "Notice"
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color(0.98, 0.90, 0.62))
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.01, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_bottom = PANEL_TOP - HINT_LIFT - float(HINT_FONT_SIZE) - 12.0
	lbl.offset_top = lbl.offset_bottom - float(HINT_FONT_SIZE) - 8.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	_notice = lbl
	# Срок — твином САМОЙ плашки: сменённая следующей плашкой гибнет вместе со
	# своим твином. Таймер дерева с лямбдой, захватившей метку, срабатывал уже
	# на освобождённой — «Lambda capture … was freed» в логе .exe на каждую
	# смену плашки (131 раз за партию 01.11.2026)
	var tw := lbl.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(sec)
	tw.tween_callback(lbl.queue_free)

func hide_victory() -> void:
	if _victory_banner != null and is_instance_valid(_victory_banner):
		_victory_banner.queue_free()
	_victory_banner = null

func show_defeat() -> void:
	hide_victory()
	_clear_overlay()
	_overlay = _full_overlay(Color(0.10, 0.02, 0.02, 0.92))
	var vbox := _center_vbox(_overlay)
	var t := Label.new(); t.text = "ПОРАЖЕНИЕ"
	t.add_theme_font_size_override("font_size", 48)
	t.add_theme_color_override("font_color", Color(0.90, 0.20, 0.15))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vbox.add_child(t)
	vbox.add_child(_spacer(20))
	vbox.add_child(_make_btn("  Попробовать снова  ", Color(0.28, 0.10, 0.10), func(): GameManager.main.restart_game()))
	vbox.add_child(_make_btn("  Выход из игры  ", Color(0.30, 0.08, 0.08), func():
		GameManager.main.quit_game()))

# ─────────────────────────────────────────────────────────────────────────────
# RESOURCES
# ─────────────────────────────────────────────────────────────────────────────

func _on_resources_changed(faction: int) -> void:
	if faction == Constants.FACTION_PLAYER:
		_refresh_resources()
		_refresh_afford()
		_retint_forge_nodes()

## ── ЖИВАЯ ДОСТУПНОСТЬ КНОПОК (заказ 10.09.2026) ──────────────────────────────
## Цвет кнопки найма/постройки считался ОДИН РАЗ при сборке панели, и иконка
## оставалась «нет денег», пока игрок не перевыделит здание. Теперь каждая
## такая кнопка записана в реестр вместе с ценой и правилом лимита, а сигнал
## resources_changed перекрашивает их тем же _afford_color и тем же стилем,
## что при сборке (_style_cmd_button — общий с _cmd). Реестр чистится вместе
## с кнопками (панель пересобирается — старые узлы мертвы, is_instance_valid)
var _afford_watch: Array = []

func _watch_afford(btn: Button, base: Color, cost: Dictionary, faction: int,
		unit_id: String = "", bld: Building = null) -> void:
	_afford_watch.append({"btn": btn, "base": base, "cost": cost, "faction": faction,
		"unit": unit_id, "bld": bld, "ok": _afford_ok(cost, faction, unit_id, bld)})

## Кнопка постройки рабочего: цвет — не подмес к базовому, а два фона заказа
## (см. _build_bg); цена крепости прогрессивная, поэтому в реестре лежит
## id постройки и цена перечитывается на каждую проверку
func _watch_build_afford(btn: Button, cost: Dictionary, faction: int, build_id: String) -> void:
	_afford_watch.append({"btn": btn, "base": Color.WHITE, "cost": cost, "faction": faction,
		"unit": "", "bld": null, "build": build_id,
		"ok": ResourceManager.can_afford(faction, cost)})

func _afford_ok(cost: Dictionary, faction: int, unit_id: String, bld: Building) -> bool:
	var ok: bool = ResourceManager.can_afford(faction, cost)
	if ok and unit_id != "" and bld != null and is_instance_valid(bld):
		ok = GameManager.pop_allows(bld.faction, unit_id)
	return ok

func _refresh_afford() -> void:
	if _afford_watch.is_empty():
		return
	var keep: Array = []
	for e in _afford_watch:
		var d: Dictionary = e
		var btn = d["btn"]
		if btn == null or not is_instance_valid(btn):
			continue
		keep.append(d)
		# Здание могло быть снесено (правило 5): освобождённый объект в
		# типизированный аргумент — ошибка «previously freed», а не null
		var braw = d["bld"]
		# typeof, а не «!= null»: освобождённый объект в Variant РАВЕН null и
		# проскакивал проверку прямо в типизированный аргумент (qa_queue2)
		if typeof(braw) == TYPE_OBJECT and not is_instance_valid(braw):
			braw = null
			d["bld"] = null
		var build_id: String = String(d.get("build", ""))
		var ok: bool
		if build_id != "":
			d["cost"] = GameManager.build_cost_for(int(d["faction"]), build_id)
			ok = ResourceManager.can_afford(int(d["faction"]), d["cost"])
		else:
			ok = _afford_ok(d["cost"], int(d["faction"]), String(d["unit"]), braw)
		if ok == bool(d["ok"]):
			continue
		d["ok"] = ok
		if build_id != "":
			_style_cmd_button(btn as Button, _build_bg(ok), false)
		else:
			_style_cmd_button(btn as Button, _afford_color(d["base"], ok), false)
	_afford_watch = keep
	# ── КАРТОЧКА ПОД КУРСОРОМ ЖИВАЯ (ТЗ 19.09.2026-3, п. 1) ─────────────────
	# Красное/белое число цены в открытой карточке считалось при показе; склад
	# сменился — карточка пересобирается на том же якоре с теми же данными
	# ── ТОЛЬКО КОГДА ДОСТУПНОСТЬ ЦЕНЫ СМЕНИЛАСЬ (ТЗ 14.10.2026, п. 2) ──────
	# Прежде карточка пересобиралась на КАЖДОЕ изменение склада, а рудник и
	# рабочие меняют его несколько раз в секунду: карточка снималась и
	# строилась заново (асинхронно, кадр без неё) — это и было «мерцание
	# тултипа». Цифры цены от склада не зависят, зависит только цвет
	# «хватает / не хватает» — его и сверяем
	if _stat_card != null and is_instance_valid(_stat_card) \
			and _card_anchor != null and is_instance_valid(_card_anchor) \
			and not (_card_data.get("cost", {}) as Dictionary).is_empty():
		var key: String = _card_afford_key(_card_data.get("cost", {}) as Dictionary)
		if key != _card_afford_seen:
			_show_card(_card_anchor, _card_data)

## Какие статьи цены сейчас по карману («1011»); по ней карточка решает,
## перекрашивать ли цену
var _card_afford_seen: String = ""
func _card_afford_key(cost: Dictionary) -> String:
	var out := ""
	var keys: Array = cost.keys()
	keys.sort()
	for k in keys:
		var need: float = float(cost[k])
		var have: float = ResourceManager.get_amount(Constants.FACTION_PLAYER, int(k))
		out += "1" if have >= need else "0"
	return out

## Тот же стиль, что кладёт _cmd при сборке; вынесен, чтобы перекраска не
## разошлась с первичной покраской
func _style_cmd_button(btn: Button, icon_color: Color, active: bool) -> void:
	var sn := StyleBoxFlat.new(); sn.bg_color = icon_color.darkened(0.25)
	_borders(sn, 1)
	sn.border_color = icon_color.lightened(0.10); _corners(sn, 5)
	var sh := StyleBoxFlat.new(); sh.bg_color = icon_color.lightened(0.12)
	_borders(sh, 1)
	sh.border_color = Color(0.95, 0.88, 0.55); _corners(sh, 5)
	if active:
		sn.bg_color = icon_color.lightened(0.06)
		_borders(sn, ACTIVE_BORDER_W)
		sn.border_color = ACTIVE_BORDER_COLOR
		_corners(sn, ACTIVE_BORDER_RADIUS)
		_borders(sh, ACTIVE_BORDER_W)
		sh.border_color = ACTIVE_BORDER_COLOR
		_corners(sh, ACTIVE_BORDER_RADIUS)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover",  sh)
	btn.add_theme_stylebox_override("pressed", sn)

## Узлы кузницы: доступный, но неоплатный — красная рамка; перекрашивается по
## сигналу склада, без пересборки сетки
const FORGE_LACK_BG := Color(0.26, 0.11, 0.09)
const FORGE_LACK_BORDER := Color(0.78, 0.34, 0.28)
var _forge_node_avail: Dictionary = {}
var _forge_node_afford: Dictionary = {}

func _forge_node_style(done: bool, busy: bool, avail: bool, afford: bool) -> StyleBoxFlat:
	var bs := StyleBoxFlat.new()
	if done:
		bs.bg_color = Color(0.20, 0.34, 0.20)
		bs.border_color = Color(0.36, 0.72, 0.36)
	elif busy:
		bs.bg_color = Color(0.12, 0.22, 0.34)
		bs.border_color = Color(0.36, 0.60, 0.84)
	elif avail and not afford:
		bs.bg_color = FORGE_LACK_BG
		bs.border_color = FORGE_LACK_BORDER
	elif avail:
		bs.bg_color = Color(0.22, 0.17, 0.08)
		bs.border_color = Color(0.62, 0.50, 0.24)
	else:
		bs.bg_color = Color(0.09, 0.09, 0.11)
		bs.border_color = Color(0.22, 0.22, 0.26)
	_corners(bs, 3); _borders(bs, 2)
	return bs

func _retint_forge_nodes() -> void:
	if _forge_nodes.is_empty() or _forge_smithy == null or not is_instance_valid(_forge_smithy):
		return
	var f: int = _forge_smithy.faction
	for nid in _forge_nodes.keys():
		var btn = _forge_nodes[nid]
		if btn == null or not is_instance_valid(btn):
			continue
		if not bool(_forge_node_avail.get(nid, false)):
			continue
		var node: Dictionary = _Forge.get_node(String(nid))
		var afford: bool = ResourceManager.can_afford(f, _UCfg.upgrade_cost(node))
		if afford == bool(_forge_node_afford.get(nid, true)):
			continue
		_forge_node_afford[nid] = afford
		var bs := _forge_node_style(false, false, true, afford)
		for st in ["normal", "hover", "pressed", "disabled"]:
			(btn as Button).add_theme_stylebox_override(st, bs)

func forge_node_afford(nid: String) -> bool:
	return bool(_forge_node_afford.get(nid, true))

func _refresh_resources() -> void:
	if _res_labels.is_empty():
		return
	for rd in RES_DEFS:
		var lbl: Label = _res_labels.get(rd["key"])
		if lbl:
			lbl.text = str(int(ResourceManager.get_amount(Constants.FACTION_PLAYER, rd["key"])))

## ПОСТОЯННО ГОРЯЩИЙ ПРИТОК "+N" (единиц в минуту).
##
## Историю стоит держать в голове, тут уже два раза наступали на грабли:
##   1. Сначала приток мерили по ИЗМЕНЕНИЮ СКЛАДА за окно. Любая трата на том
##      же тике (найм, закладка, апгрейд) топила цифру в ноль или в минус,
##      хотя рабочие продолжали копать.
##   2. Потом считали НОМИНАЛ по конфигу: сумму gather_amount/цикл по рабочим
##      в состоянии GATHERING. Но рабочий долбит жилу лишь малую часть рейса —
##      остальное он идёт туда и обратно, — поэтому в состоянии GATHERING в
##      каждый момент почти никого нет, и цифра ВСПЫХИВАЛА в момент сдачи
##      груза и тут же гасла. Это и есть жалоба «приток мигает».
##
## Сейчас берём НАРАСТАЮЩИЙ ИТОГ СДАННОГО (ResourceManager.gathered_total —
## только приходы по добыче, траты туда не попадают по построению) и делим на
## длину окна. Окно INC_WINDOW_SEC заведомо длиннее одного рейса рабочего,
## поэтому отдельные сдачи в него усредняются и цифра стоит ровно. Окно
## скользящее: набрав полную длину, счётчик и время делятся пополам — старое
## плавно теряет вес, а не сбрасывается ступенькой.
##
## Подпись показывается, пока приток есть ИЛИ пока хоть один рабочий приписан
## к этому ресурсу: иначе в первые секунды партии (груз ещё в пути, сдачи не
## было) секция выглядела бы мёртвой
func _update_resource_income(delta: float) -> void:
	if _res_income_labels.is_empty():
		return

	# Окно копится КАЖДЫЙ кадр, независимо от частоты перерисовки подписи
	_inc_elapsed += delta
	if _inc_elapsed >= INC_WINDOW_SEC:
		var half: float = _inc_elapsed * 0.5
		for rd0 in RES_DEFS:
			var k0: int = rd0["key"]
			var total0: float = ResourceManager.gathered_total(Constants.FACTION_PLAYER, k0)
			var got0: float = total0 - float(_inc_base.get(k0, 0.0))
			_inc_base[k0] = total0 - got0 * 0.5
		_inc_elapsed = half

	_res_income_timer -= delta
	if _res_income_timer > 0.0:
		return
	_res_income_timer = RES_INCOME_WINDOW_SEC

	# Кто сейчас приписан к какому ресурсу. Обход группы здесь допустим —
	# раз в секунду, это не горячий путь юнит-тика
	# ── ПРИТОК СТАТИЧЕСКИЙ (ТЗ 24.09.2026, п. 5) ─────────────────────────
	# «Рабочих на ресурсе × доход одного» (Worker.nominal_income_per_sec), а
	# не сданное за окно: по факту сдачи цифра прыгала в миг добегания рабочего
	# до склада. Еде к фермерам добавляется то, что капает с домов
	var busy: Dictionary = {}
	var nominal: Dictionary = {}
	for n in get_tree().get_nodes_in_group("all_units"):
		var w := n as Worker
		if w == null or w.is_dead() or w.faction != Constants.FACTION_PLAYER:
			continue
		var rt: int = w.assigned_resource_type()
		if rt >= 0:
			busy[rt] = int(busy.get(rt, 0)) + 1
			nominal[rt] = float(nominal.get(rt, 0.0)) + w.nominal_income_per_sec()
	var houses := 0
	for b in GameManager.nodes_in_group_cached(Constants.building_group(Constants.FACTION_PLAYER)):
		if b != null and is_instance_valid(b) and b is Building and _UCfg.is_house(String((b as Building).building_id)) and not (b as Building)._dead:
			houses += 1
	var house_food: float = float(houses) * _UCfg.HOUSE_FOOD_INCOME / maxf(_UCfg.HOUSE_FOOD_INTERVAL, 0.1)
	nominal[Constants.RESOURCE_FOOD] = float(nominal.get(Constants.RESOURCE_FOOD, 0.0)) + house_food
	# РУДНИКИ (ТЗ 12.10.2026): рабочие внутри рудника из групп юнитов сняты
	# (Mine._absorb) — без этого счёта «на золоте 0», хотя в двух рудниках 8
	# человек. Доход рудников входит в расчётный приток золота
	var mines := 0
	var mine_workers := 0
	var mine_rate := 0.0
	for b in GameManager.nodes_in_group_cached(Constants.building_group(Constants.FACTION_PLAYER)):
		if b == null or not is_instance_valid(b) or not (b is Mine) or (b as Mine)._dead:
			continue
		var mn := b as Mine
		if mn.is_active():
			mines += 1
			mine_workers += mn.workers.size()
		mine_rate += mn.income_per_sec()
	busy[Constants.RESOURCE_GOLD] = int(busy.get(Constants.RESOURCE_GOLD, 0)) + mine_workers
	nominal[Constants.RESOURCE_GOLD] = float(nominal.get(Constants.RESOURCE_GOLD, 0.0)) + mine_rate
	mine_stat = {"mines": mines, "workers": mine_workers, "per_min": mine_rate * 60.0}
	if _mine_box != null and is_instance_valid(_mine_box):
		_mine_box.visible = mines > 0
		_mine_count_lbl.text = "%d" % mines
		_mine_income_lbl.text = "+%d" % int(round(mine_rate * 60.0))
		_mine_box.tooltip_text = "Рудников работает: %d, рабочих внутри: %d, доход рудников: %d золота в минуту" % [
			mines, mine_workers, int(round(mine_rate * 60.0))]

	for rd in RES_DEFS:
		var key: int = rd["key"]
		var total: float = ResourceManager.gathered_total(Constants.FACTION_PLAYER, key)
		if not _inc_base.has(key):
			_inc_base[key] = total
		var got: float = maxf(total - float(_inc_base[key]), 0.0)
		var rate: float = 0.0
		# ЖДЁМ, ПОКА ОКНО НАБЕРЁТ ДАННЫХ. Делить на первую секунду нельзя: одна
		# сданная ходка (десятки единиц) превращалась бы в четырёхзначные
		# «единиц в минуту», и первые секунды партии показывали бы дичь
		if _inc_elapsed >= INC_MIN_SAMPLE_SEC:
			rate = got / _inc_elapsed * 60.0
		# Показываем РАСЧЁТНЫЙ приток; фактический (rate выше) — запасной, когда
		# расчёта нет вовсе (ресурс пришёл не от рабочих и не от домов)
		var nom: float = float(nominal.get(key, 0.0)) * 60.0
		if nom > 0.0 or int(busy.get(key, 0)) > 0:
			rate = nom
		_inc_rate[key] = rate

		var workers: int = int(busy.get(key, 0))

		# ЧИСЛО РАБОЧИХ — ВЕЗДЕ «НА ЭТОМ РЕСУРСЕ». Секция-исключение с общим
		# счётчиком убрана по заказу владельца: на мясе должен стоять честный
		# ноль, пока еду дают Домики, а не рабочие (см. RES_WORKER_SECTION)
		var is_total: bool = key == RES_WORKER_SECTION
		var shown: int = _total_player_workers() if is_total else workers

		# ДОБЫВАЮЩИЕ СЕКЦИИ ПОКАЗЫВАЮТ СЧЁТЧИК ВСЕГДА, ВКЛЮЧАЯ НОЛЬ.
		# Ради этого его и возвращали: «на камне никого» — такой же нужный ответ,
		# как «на камне трое», и по погасшей секции его не отличить от «секция
		# ничего не умеет показывать». Дёргаться панели не от чего — ширина под
		# число зарезервирована (RES_WORKERS_W), а не считается по тексту.
		# Ноль рисуется приглушённо, чтобы не спорить за внимание с живыми числами
		var wk_lbl: Label = _res_workers_labels.get(key)
		if wk_lbl != null:
			wk_lbl.visible = shown > 0 or not is_total
			wk_lbl.text = "%d" % shown
			wk_lbl.modulate = Color(1, 1, 1, 1.0) if shown > 0 else Color(1, 1, 1, 0.45)

		var tool_lbl: Label = _res_tool_labels.get(key)
		if tool_lbl != null:
			tool_lbl.visible = shown > 0 or not is_total
			tool_lbl.modulate = Color(1, 1, 1, 1.0) if shown > 0 else Color(1, 1, 1, 0.45)

		var inc_lbl: Label = _res_income_labels.get(key)
		if inc_lbl == null:
			continue
		# ЕДА: приток И РАСХОД (содержание армии, 10.09.2026). Красным —
		# когда расход больше притока: склад тает, и игроку пора строить дома
		# или красть овец
		# Приток всегда ЗЕЛЁНЫЙ, расход — отдельной КРАСНОЙ цифрой
		# (ТЗ 24.09.2026, п. 5: «−26 красным, +52 зелёным»)
		if key == Constants.RESOURCE_FOOD:
			var upk: float = ResourceManager.upkeep_rate(Constants.FACTION_PLAYER, key) * 60.0
			if _food_upkeep_label != null and is_instance_valid(_food_upkeep_label):
				_food_upkeep_label.visible = upk > 0.0
				_food_upkeep_label.text = "−%d" % int(round(upk))
				_food_upkeep_label.tooltip_text = "Расход еды: %d в минуту (рабочие и отряды)" % int(round(upk))
			if upk > 0.0:
				inc_lbl.text = "+%d" % int(round(rate))
				inc_lbl.add_theme_color_override("font_color", Color(0.35, 0.9, 0.35))
				inc_lbl.tooltip_text = "Еда: приток %d в минуту, расход %d в минуту (рабочие и отряды)" % [
					int(round(rate)), int(round(upk))]
				inc_lbl.visible = true
				continue
		if rate <= 0.0 and workers <= 0:
			inc_lbl.visible = false
			continue
		inc_lbl.text = "+%d" % int(round(rate))
		inc_lbl.add_theme_color_override("font_color", Color(0.35, 0.9, 0.35))
		inc_lbl.visible = true

## Сколько всего рабочих у игрока — число рядом с топориком в секции еды.
## Через кэш групп: панель обновляется каждый кадр, а get_nodes_in_group()
## копирует свой массив на каждый вызов
func _total_player_workers() -> int:
	var n := 0
	for u in GameManager.nodes_in_group_cached("player_units"):
		if u is Worker and is_instance_valid(u) and not (u as Worker).is_dead():
			n += 1
	return n

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _build_drag_rect() -> void:
	drag_rect = ColorRect.new()
	drag_rect.color = Color(0.40, 0.80, 1.0, 0.12)
	drag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_rect.visible = false
	add_child(drag_rect)

func get_drag_rect() -> ColorRect:
	return drag_rect

# ─────────────────────────────────────────────────────────────────────────────
# КНОПКА ПРИКАЗА
# Иконка растягивается на ВСЮ площадь кнопки (TextureRect с EXPAND_IGNORE_SIZE
# и STRETCH_SCALE), текста на кнопке при этом нет вовсе — характеристики и цена
# уезжают во всплывающую карточку (см. _show_card).
# Подпись остаётся ТОЛЬКО у кнопок без картинки (стойки, апгрейды): пустой
# квадрат без иконки и без текста игрок опознать не смог бы.
#
# card — данные карточки; пустой словарь = собрать её из label_text,
# чтобы ни цена, ни описание не потерялись при переносе текста с кнопки.
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# ЕДИНАЯ ЗАГРУЗКА ИКОНОК ИНТЕРФЕЙСА
#
# Через неё идут ВСЕ картинки кнопок и карточек. В конфиге можно писать как
# полный res://-путь (постройки, найм), так и просто имя файла из папки иконок
# кузницы ("icon_sword.png") — разбирается unit_stats_config.smith_icon_path.
#
# Нет файла или опечатка в имени — интерфейс НЕ падает: возвращается null,
# кнопка рисуется с подписью, а в консоль уходит предупреждение с путём, по
# которому искали. Раньше промах был вообще молчаливым: ResourceLoader.exists()
# возвращал false, ветка пропускалась, и кнопка просто оставалась без картинки —
# отличить «иконка не задумана» от «путь сломан» было нечем.
# ─────────────────────────────────────────────────────────────────────────────
## О каких путях уже пожаловались (см. _icon_texture)
static var _icon_warned: Dictionary = {}
## Заглушка вместо ненайденной иконки. Строится один раз и рисуется процедурно,
## чтобы не зависеть от ещё одного файла, которого тоже может не оказаться:
## тусклая рамка с диагональю — сразу видно, что картинки нет, но кнопка на
## месте и панель не разъезжается
static var _placeholder_tex: Texture2D = null

static func _placeholder_icon() -> Texture2D:
	if _placeholder_tex != null:
		return _placeholder_tex
	const SIDE := 32
	var img := Image.create(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var edge := Color(0.62, 0.60, 0.54, 0.85)
	var fill := Color(0.24, 0.23, 0.21, 0.55)
	for y in range(SIDE):
		for x in range(SIDE):
			var on_edge: bool = x == 0 or y == 0 or x == SIDE - 1 or y == SIDE - 1
			var on_diag: bool = absi(x - y) <= 1
			if on_edge or on_diag:
				img.set_pixel(x, y, edge)
			else:
				img.set_pixel(x, y, fill)
	_placeholder_tex = ImageTexture.create_from_image(img)
	return _placeholder_tex

func _icon_texture(icon_name: String) -> Texture2D:
	if icon_name.is_empty():
		return null                      # иконка не задумана — это не ошибка
	var path: String = _UCfg.smith_icon_path(icon_name)
	if not ResourceLoader.exists(path):
		# ЖАЛУЕМСЯ ОДИН РАЗ НА ПУТЬ, А НЕ НА КАЖДЫЙ ВЫЗОВ. Иконки запрашиваются
		# при каждой пересборке панели, то есть на каждом выделении, — из-за
		# этого одна недостающая картинка давала бесконечный поток одинаковых
		# строк в консоли. Диагностику при этом терять нельзя: молча рисовать
		# пустоту — это как раз то, ради чего предупреждение и заводилось
		if not _icon_warned.has(path):
			_icon_warned[path] = true
			push_warning("HUD: иконка не найдена: %s (в конфиге указано «%s»)"
				% [path, icon_name])
		return _placeholder_icon()
	if FRAME_SHEET_ICONS.has(path):
		return _trimmed_icon_frame(path, int(FRAME_SHEET_ICONS[path]))
	var tex := ResourceLoader.load(path) as Texture2D
	if tex == null:
		push_warning("HUD: файл не читается как текстура: %s" % path)
	return tex

## Первый кадр квадратной спрайт-полосы (frame_side×frame_side), обрезанный
## по непрозрачному силуэту — для UNIT_ICONS, у которых нет готового портрета
## и приходится брать кадр из боевого спрайт-листа (см. FRAME_SHEET_ICONS)
## Разобранные листовые иконки: путь -> готовый AtlasTexture.
## БЕЗ КЭША каждый вызов заново читал Image, при нужде распаковывал его,
## вырезал кадр и искал непрозрачную область — и всё это на КАЖДУЮ пересборку
## панели, то есть на каждое выделение. Побочно это ещё и плодило разные
## объекты текстуры на одну и ту же картинку (стенд qa_icons/Card поймал это
## как «карточка и кнопка дают РАЗНЫЕ картинки» у монаха)
static var _frame_icon_cache: Dictionary = {}

func _trimmed_icon_frame(path: String, frame_side: int) -> Texture2D:
	var hit: Variant = _frame_icon_cache.get(path)
	if hit != null:
		return hit
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return tex
	if img.is_compressed() and img.decompress() != OK:
		return tex
	var frame_rect := Rect2i(0, 0, frame_side, frame_side)
	if frame_rect.size.x > img.get_width() or frame_rect.size.y > img.get_height():
		return tex
	var sub: Image = img.get_region(frame_rect)
	var used: Rect2i = sub.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		used = Rect2i(Vector2i.ZERO, sub.get_size())
	var atlas := AtlasTexture.new()
	atlas.atlas  = tex
	atlas.region = Rect2(used)
	atlas.filter_clip = true
	_frame_icon_cache[path] = atlas
	return atlas

## size: 0 — обычная кнопка приказа (BTN_SIZE). Замок передаёт увеличенный
## размер для своих двух кнопок найма (см. CASTLE_PANEL_BOOST) — отступ иконки
## растёт вместе с кнопкой в той же пропорции, иначе на крупной кнопке воздух
## вокруг картинки выглядел бы непропорционально узким.
## icon_boost: 1.0 — картинка как обычно центрируется в (sz - 2*pad).
## >1.0 сжимает pad так, что рамка картинки становится в icon_boost раз
## больше — картинка растёт БЫСТРЕЕ кнопки, а не просто вместе с ней (Замок
## просит именно это: +20% к иконкам ПОВЕРХ уже увеличенной на +30% панели)
## active — КНОПКА ПОКАЗЫВАЕТ ТЕКУЩЕЕ СОСТОЯНИЕ (сейчас это стойки отряда).
## Такая кнопка обводится жёлтым (см. ACTIVE_BORDER_*), и с одного взгляда
## видно, в какой стойке отряд. Раньше активную стойку выдавала только чуть
## более светлая заливка — на глаз почти неразличимо, особенно у красной
## «Атаки», где обе версии цвета тёмные
## on_hover / on_unhover — СВОЁ поведение наведения вместо общей карточки.
## Заведено ради наград ветеранства: у них теперь и своя миниатюрная плашка
## (см. _show_vet_tip), и предпросмотр будущих статов в таблице слева. Подменять
## сигналы после создания кнопки нельзя — пришлось бы отсоединять чужие
## подключения вслепую, а это ровно тот приём, который ломается при следующей
## правке _cmd
func _cmd(label_text: String, icon_color: Color, callback: Callable,
		icon_path: String = "", card: Dictionary = {}, size: float = 0.0,
		icon_boost: float = 1.0, active: bool = false,
		on_hover: Callable = Callable(), on_unhover: Callable = Callable()) -> Button:
	var sz: float = size if size > 0.0 else float(BTN_SIZE)
	var pad: float = BTN_ICON_PAD * (sz / float(BTN_SIZE))
	if icon_boost != 1.0:
		var base_frame: float = sz - 2.0 * pad
		var boosted_frame: float = clampf(base_frame * icon_boost, 0.0, sz)
		pad = (sz - boosted_frame) * 0.5
	# QuietTooltipButton, а не голый Button: у этой кнопки уже есть своя
	# карточка (_show_card ниже) — движковый пузырь tooltip_text поверх нёе
	# был тем самым "лишним текстом" с жалобы. tooltip_text всё равно
	# ставится (нужен стендам для поиска кнопки), просто не всплывает сам
	var btn := QuietTooltipButton.new()
	btn.custom_minimum_size = Vector2(sz, sz)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# СТРОГО КВАДРАТ (заказ 13.09.2026): в ряду Крепости колонка рыцаря выше
	# квадрата (иконка + кнопка ранга), и GridContainer растягивал соседние
	# кнопки на её высоту — рабочий и монах выходили прямоугольниками
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.clip_contents = true
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))

	var tex: Texture2D = _icon_texture(icon_path)
	if tex != null:
		btn.text = ""
		# НАЗВАНИЕ ОСТАЁТСЯ В tooltip_text даже у кнопки с иконкой: по нему
		# кнопку находят стенды, и оно же всплывает подсказкой у игрока
		btn.tooltip_text = label_text.get_slice("\n", 0)
		# BTN_ICON_PAD, а не 3px: картинка теперь вписывается по пропорциям и ей
		# нужен воздух от рамки, иначе она упирается в неё углами
		btn.add_child(_stretched_icon(tex, pad))
	else:
		# Без иконки: только НАЗВАНИЕ, первой строкой. Цена и описание — в карточке
		btn.text = label_text.get_slice("\n", 0)

	if on_hover.is_valid():
		btn.mouse_entered.connect(on_hover)
		if on_unhover.is_valid():
			btn.mouse_exited.connect(on_unhover)
			btn.tree_exiting.connect(on_unhover)
	else:
		var data: Dictionary = card
		if data.is_empty():
			data = _text_card(label_text, tex)
		btn.mouse_entered.connect(func(): _show_card(btn, data))
		btn.mouse_exited.connect(_hide_card)
		btn.tree_exiting.connect(_hide_card)

	# Тонкая аккуратная рамка вместо жирного цветного кантика (было 2px в тон
	# заливки — на кнопке Рабочего это читалось как толстая зелёная обводка).
	# 1px и мягче светлее — граница обозначена, а не кричит
	var sn := StyleBoxFlat.new(); sn.bg_color = icon_color.darkened(0.25)
	_borders(sn, 1)
	sn.border_color = icon_color.lightened(0.10); _corners(sn, 5)
	var sh := StyleBoxFlat.new(); sh.bg_color = icon_color.lightened(0.12)
	_borders(sh, 1)
	sh.border_color = Color(0.95, 0.88, 0.55); _corners(sh, 5)
	# ── АКТИВНОЕ СОСТОЯНИЕ: ЖЁЛТАЯ РАМКА ────────────────────────────────────
	# Толще обычной и заметно ярче заливки, углы — те же ACTIVE_BORDER_RADIUS,
	# что и у остальных иконок панели, чтобы обводка читалась как подсветка
	# кнопки, а не как второй, чужой элемент поверх неё
	if active:
		sn.bg_color = icon_color.lightened(0.06)
		_borders(sn, ACTIVE_BORDER_W)
		sn.border_color = ACTIVE_BORDER_COLOR
		_corners(sn, ACTIVE_BORDER_RADIUS)
		# Наведение не должно «гасить» подсветку: под курсором активная кнопка
		# обязана остаться обведённой, иначе игрок теряет ответ на вопрос
		# «а какая стойка сейчас» ровно в тот момент, когда целится в кнопку
		_borders(sh, ACTIVE_BORDER_W)
		sh.border_color = ACTIVE_BORDER_COLOR
		_corners(sh, ACTIVE_BORDER_RADIUS)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover",  sh)
	btn.add_theme_stylebox_override("pressed", sn)
	btn.pressed.connect(callback)
	button_container.add_child(btn)
	return btn

## Иконка, вписанная в площадь родителя (inset — отступ под рамку).
## EXPAND_IGNORE_SIZE: собственный размер картинки не участвует в вёрстке —
## без него TextureRect навязывает контейнеру НАТУРАЛЬНЫЙ размер файла и рвёт
## разметку (см. панель ресурсов).
## STRETCH_KEEP_ASPECT_CENTERED, а НЕ STRETCH_SCALE: кнопки приказов
## квадратные, а картинки зданий вытянуты по вертикали — при простом
## растяжении башня, кузница и домик сплющивались в «пеньки». Теперь картинка
## вписывается в квадрат целиком, сохраняя пропорции, и центрируется в нём;
## лишнее место по бокам — это поля, а не искажение.
func _stretched_icon(tex: Texture2D, inset: float = 0.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture      = tex
	tr.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Отступы ставятся ПОСЛЕ пресета: он сбрасывает offsets в нули
	tr.offset_left   =  inset
	tr.offset_top    =  inset
	tr.offset_right  = -inset
	tr.offset_bottom = -inset
	return tr

# ─────────────────────────────────────────────────────────────────────────────
# ЕДИНАЯ ТОЧКА РАЗМЕЩЕНИЯ ВСЕХ ВСПЛЫВАЮЩИХ ОКОН (карточка юнита, панель статов,
# подсказка бонуса). Раньше высота каждого окна СЧИТАЛАСЬ ЗАРАНЕЕ формулой
# (24 + lines.size()*17 и т.п., либо просто константой CARD_H) — формула не
# знает про перенос строк, и как только текст (длинное имя, длинная строка
# бонуса) переносился на второй визуальный ряд, окно оказывалось короче
# настоящего содержимого. Т.к. и верх, и низ окна были жёстко зафиксированы
# offset'ами, лишнее содержимое просто рисовалось ЗА нижней гранью прямоугольника
# — то есть вниз, поверх собственного якоря — и закрывало кнопки под собой.
# Ровно это было в жалобе «тултип перекрывает соседние иконки».
#
# Правило теперь железное: окно ВСЕГДА растёт ВВЕРХ от bottom_y, а высота
# берётся из РЕАЛЬНОГО размера уже наполненной панели.
#
# get_combined_minimum_size() СРАЗУ ПОСЛЕ add_child (или тем более до него)
# для RichTextLabel/Label ВНУТРИ него возвращает ЗАНИЖЕННОЕ число — движок
# считает перенос строк (autowrap) лениво и не гарантирует готовый кэш в тот
# же кадр, когда узел ещё не прошёл ни одного цикла сортировки контейнеров.
# Меряя раньше времени, offset_top ставился недостаточно высоко, а VBox
# внутри всё равно раскладывал детей по их НАСТОЯЩЕЙ высоте — то есть ВНИЗ,
# за нижнюю грань уже зафиксированного прямоугольника, поверх панели под
# ним. Подтверждено стендом qa_ui (карточки перекрывали панель на 61-197 px).
# Лечится ожиданием одного process_frame ПОСЛЕ того как узел встал в дерево:
# панель невидима этот единственный кадр, потом переставляется по-настоящему
# точному размеру и показывается — ни дрожания, ни оверлея.
func _pin_floater_above(panel: PanelContainer, bottom_y: float, left_x: float, width: float) -> void:
	panel.anchor_left = 0.0; panel.anchor_right = 0.0
	panel.anchor_top  = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left   = left_x
	panel.offset_right  = left_x + width
	panel.offset_top    = bottom_y
	panel.offset_bottom = bottom_y
	panel.visible = false
	add_child(panel)
	await get_tree().process_frame
	if not is_instance_valid(panel) or panel.is_queued_for_deletion():
		return
	var h: float = panel.get_combined_minimum_size().y
	panel.offset_bottom = bottom_y
	panel.offset_top    = bottom_y - h
	panel.visible = true
	_ignore_mouse_tree(panel)

# ═════════════════════════════════════════════════════════════════════════════
# ЕДИНЫЙ СТАНДАРТ ВСПЛЫВАЮЩИХ ОКОН: СТРОГО ВВЕРХ НАД НАВЕДЁННОЙ ИКОНКОЙ
#
# Правило одно на весь интерфейс (заказ владельца): окно описания встаёт ровно
# НАД той кнопкой, на которую навели, растёт ВВЕРХ столбиком по мере текста и
# никогда не наезжает ни на саму кнопку, ни на панель под ней.
#
# Раньше горизонталь считалась формулой `bx - (CARD_W - BTN_SIZE) / 2`, где
# BTN_SIZE — КОНСТАНТА обычной кнопки приказа. У Замка кнопки найма увеличены
# (BTN_SIZE × CASTLE_PANEL_BOOST), у Артели — тоже, у форжа свой размер; для
# любой такой кнопки формула промахивалась мимо центра тем сильнее, чем крупнее
# кнопка. Теперь центр берётся из НАСТОЯЩЕГО прямоугольника кнопки
# (get_global_rect), поэтому размер кнопки перестал иметь значение вовсе.
#
# Возвращает [левый край, нижняя кромка] в системе offset'ов от НИЗА экрана —
# ровно в том виде, какой ждёт _pin_floater_above.
# ═════════════════════════════════════════════════════════════════════════════

## Зазор между нижней кромкой окна и верхом кнопки
const TIP_GAP := 6.0
## Отступ от краёв экрана, за который окно не заезжает
const TIP_SCREEN_PAD := 8.0

func _tip_anchor_geometry(anchor: Control, width: float) -> Array:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Запасной вариант — над нижней панелью по центру экрана: так вело себя
	# окно до появления этого правила, и без живой кнопки лучше ничего нет
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return [clampf((vp.x - width) * 0.5, TIP_SCREEN_PAD,
			maxf(vp.x - width - TIP_SCREEN_PAD, TIP_SCREEN_PAD)),
			float(PANEL_TOP) - TIP_GAP]
	var r: Rect2 = anchor.get_global_rect()
	# ── ОКНО ВЫРОВНЕНО ПО ЛЕВОМУ КРАЮ НИЖНЕЙ ПАНЕЛИ ────────────────────────
	# ЗАКАЗ ВЛАДЕЛЬЦА, И ЭТО РАЗВОРОТ ПРЕЖНЕГО ПРАВИЛА («окно строго над
	# наведённой кнопкой»). Жалоба со скриншотом панели Замка: карточка
	# «Мечник ×30» вылезала на середину экрана и висела там косо, ни к чему не
	# привязанная. Так и должно было быть по прежней формуле: кнопки найма
	# прижаты к ПРАВОМУ краю панели, а карточка вдвое шире кнопки и
	# центрировалась на ней — то есть её левый край оказывался где угодно, лишь
	# бы не у панели.
	#
	# Теперь горизонталь у карточки ОДНА и та же, что у самой панели: её левая
	# кромка. Берётся из живого прямоугольника панели, а не из константы
	# PANEL_LEFT, — ширину панели считает содержимое (_panel_w), и левый край
	# обязан совпадать с тем, что реально нарисовано. Константа остаётся
	# запасным ответом, пока панели на экране нет
	var px: float = PANEL_LEFT
	if _bottom_panel != null and is_instance_valid(_bottom_panel) and _bottom_panel.visible:
		px = _bottom_panel.get_global_rect().position.x
	# Отступ от края экрана НЕ ОТТАЛКИВАЕТ окно от панели: панель сама может
	# стоять ближе к кромке (PANEL_LEFT = 6 при TIP_SCREEN_PAD = 8), и общий
	# зажим уводил бы окно правее её края на эти два пикселя — то самое
	# несовпадение, ради устранения которого выравнивание и заведено
	px = clampf(px, minf(TIP_SCREEN_PAD, px),
		maxf(vp.x - width - TIP_SCREEN_PAD, minf(TIP_SCREEN_PAD, px)))
	# Нижняя кромка окна — над ВЕРХОМ кнопки. Переводим экранную координату в
	# offset от низа экрана: _pin_floater_above крепит окно к anchor_top = 1.0
	var bottom_y: float = r.position.y - vp.y - TIP_GAP
	# …НО НЕ НИЖЕ ВЕРХНЕЙ КРОМКИ САМОЙ ПАНЕЛИ.
	# «Над кнопкой» и «над панелью» совпадали, пока кнопки прижимались к верху
	# панели. Теперь ряд найма стоит по ВЕРТИКАЛЬНОМУ ЦЕНТРУ (заказ владельца),
	# то есть его верхняя кромка — глубоко внутри панели, и окно, прицепленное к
	# ней, ложилось на панель сверху (qa_hud5 D3: низ окна 656 при верхе панели
	# 642). Правило интерфейса при этом не изменилось: окно не должно наезжать
	# НИ на кнопку, НИ на панель — берём то из двух ограничений, что выше
	if _bottom_panel != null and is_instance_valid(_bottom_panel) and _bottom_panel.visible:
		bottom_y = minf(bottom_y, float(PANEL_TOP) - TIP_GAP)
	# ── ОКНО НИКОГДА НЕ ЛОЖИТСЯ НА ПАНЕЛЬ СТАТОВ (заказ владельца, критично) ──
	# Панель статов прижата к левому краю и растёт ВВЕРХ от той же кромки, от
	# которой растёт и это окно, — то есть они занимают одну и ту же полосу по
	# вертикали ПО ПОСТРОЕНИЮ, и проверять вертикаль незачем: если прямоугольники
	# пересекаются по горизонтали, они пересекаются. Кнопки способностей стоят в
	# левой половине панели, поэтому наложение случалось на каждом наведении.
	# Сдвигаем окно ВПРАВО за панель статов — ровно то «аккуратно справа», что
	# просили; если правее места нет, упираемся в край экрана и окно всё равно
	# оказывается настолько правее, насколько экран позволяет
	if stat_panel_shown():
		var sp: Rect2 = _stat_panel.get_global_rect()
		var right_of: float = sp.position.x + sp.size.x + TIP_GAP
		if px < right_of:
			px = minf(right_of, maxf(vp.x - width - TIP_SCREEN_PAD, TIP_SCREEN_PAD))
	return [px, bottom_y]

func _ignore_mouse_tree(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse_tree(c)

# ─────────────────────────────────────────────────────────────────────────────
# КАРТОЧКА ХАРАКТЕРИСТИК ПРИ НАВЕДЕНИИ
# Формат данных: {"title", "icon", "hp", "hp_max", "cost", "lines": [строки]}
# Ширина карточки фиксирована (CARD_W), высота — по реальному содержимому
# (см. _pin_floater_above); она висит НАД нижней панелью и никогда не наезжает
# на неё, сколько бы строк characteristики ни принесли.
# ─────────────────────────────────────────────────────────────────────────────
func _hide_card() -> void:
	if _stat_card != null and is_instance_valid(_stat_card):
		_stat_card.queue_free()
	_stat_card = null
	_card_anchor = null
	_card_data = {}

## Якорь и данные открытой карточки — для живого пересчёта цены (см. _refresh_afford)
var _card_anchor: Control = null
var _card_data: Dictionary = {}

func _show_card(anchor: Control, data: Dictionary) -> void:
	_hide_card()
	if data.is_empty() or anchor == null or not is_instance_valid(anchor):
		return
	_card_anchor = anchor
	_card_data = data
	_card_afford_seen = _card_afford_key(data.get("cost", {}) as Dictionary)
	var panel: PanelContainer = _card_panel(data, CARD_W)
	# СТРОГО НАД НАВЕДЁННОЙ ИКОНКОЙ и растёт ВВЕРХ на реальную высоту
	# содержимого (см. _tip_anchor_geometry / _pin_floater_above) — не наедет
	# ни на кнопку, ни на панель, сколько бы строк ни принесли характеристики
	var g: Array = _tip_anchor_geometry(anchor, CARD_W)
	_stat_card = panel
	# Карточка не ловит мышь НИ ОДНОЙ частью (ТЗ 12.10.2026: мерцание): строки
	# RichTextLabel по умолчанию STOP, и карточка, легшая на кнопку, отнимала
	# у неё наведение — mouse_exited → карточка снята → снова над кнопкой
	_mouse_ignore_all(panel)
	await _pin_floater_above(panel, float(g[1]), float(g[0]), CARD_W)

# ═════════════════════════════════════════════════════════════════════════════
# ЕДИНЫЙ ФОРМАТ КАРТОЧКИ (ТЗ 20.10.2026, блок 3 — UI/UX-аудит подсказок)
# ═════════════════════════════════════════════════════════════════════════════
# Одна раскладка на ВСЕ карточки — юниты, здания, улучшения:
#   ┌──────────────────────────────────────┬────────┐
#   │ Название (крупно, золотом)           │ иконка │  ← справа плитка с фоном
#   │ подзаголовок (серым, необязателен)   │ статус │    и статусом под ней
#   ├──────────────────────────────────────┴────────┤
#   │ ♥ Здоровье                               110  │  ← столбик характеристик:
#   │ ⚔ Атака                            +2     30  │    значок, подпись, итог по
#   │ ⛨ Броня                                    1  │    правому краю, прибавка
#   │ ⛀ Скорость                               2.1  │    кузницы зелёным
#   ├───────────────────────────────────────────────┤
#   │ Тип: Штурмовая пехота                         │  ← «Тип / Умения / Особое
#   │ Умения: Стена щитов                           │    умение» — по строке
#   │ Особое умение: Яростная атака (…)             │
#   ├───────────────────────────────────────────────┤
#   │ Цена: дерево / золото / мясо                  │
#   └───────────────────────────────────────────────┘
# Что СНЯТО как мусор: «Выходит готовым ветераном» (ранг — в статусе плитки),
# «Содержание еды/золота» (расход виден на верхней плашке ресурсов),
# «ЛКМ — заказать / ПКМ — отменить» (управление одинаково у всех иконок),
# формула «База + Кузница = Итог» в одну строку (итог и прибавка — колонками).
#
# Формат данных карточки (все поля необязательны):
#   "title", "subtitle", "icon", "status", "status_col", "vet_flag",
#   "stats": [{"icon", "label", "value", "bonus"}],
#   "info":  [[подпись, текст], …],
#   "lines": [строки bbcode] — запасной путь для редких карточек (гарнизон,
#            ранг Крепости), рисуются после info,
#   "cost":  {ресурс: число}
const CARD_LABEL_COL := Color(0.70, 0.62, 0.42)
const CARD_TEXT_COL := Color(0.88, 0.89, 0.92)
const CARD_SEP_COL := Color(0.52, 0.44, 0.24, 0.45)
const CARD_BADGE := 44.0

func _card_panel(data: Dictionary, width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.10, 0.96)
	_borders(st); _corners(st, 6)
	st.border_color = Color(0.52, 0.44, 0.24)
	st.content_margin_left = 10; st.content_margin_right = 10
	st.content_margin_top  = 8;  st.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(width, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var inner_w: float = width - 20.0

	# 1) Шапка: название слева, плитка иконки со статусом справа
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 1)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(tcol)
	var title := Label.new()
	title.text = String(data.get("title", ""))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.98, 0.90, 0.55))
	_fix_label(title, inner_w - CARD_BADGE - 24.0, 2)
	tcol.add_child(title)
	var sub: String = String(data.get("subtitle", ""))
	if not sub.is_empty():
		var sl := Label.new()
		sl.text = sub
		sl.add_theme_font_size_override("font_size", 11)
		sl.add_theme_color_override("font_color", CARD_LABEL_COL)
		_fix_label(sl, inner_w - CARD_BADGE - 24.0, 1)
		tcol.add_child(sl)
	head.add_child(_card_badge(data))

	# 2) Столбик характеристик
	var stats: Array = data.get("stats", [])
	var hp_max: float = float(data.get("hp_max", 0.0))
	if stats.is_empty() and hp_max > 0.0:
		stats = [{"icon": "icon_heart.png", "label": "Прочность", "value": "%d" % int(hp_max)}]
	if not stats.is_empty():
		vb.add_child(_card_sep(inner_w))
		for row in stats:
			vb.add_child(_card_stat_row(row as Dictionary, inner_w))

	# 3) Тип / Умения / Особое умение
	var info: Array = data.get("info", [])
	var shown_info := false
	for pair in info:
		var pr: Array = pair
		if pr.size() < 2 or String(pr[1]).strip_edges().is_empty():
			continue
		if not shown_info:
			vb.add_child(_card_sep(inner_w))
			shown_info = true
		vb.add_child(_card_rich("[color=#%s]%s:[/color] %s" % [
			CARD_LABEL_COL.to_html(false), String(pr[0]), String(pr[1])], inner_w, 12))

	# 4) Запасные строки (редкие карточки)
	var lines: Array = data.get("lines", [])
	if not lines.is_empty():
		if not shown_info and stats.is_empty():
			vb.add_child(_card_sep(inner_w))
		for i in range(mini(lines.size(), 9)):
			var text: String = String(lines[i])
			if text.is_empty():
				vb.add_child(_pad(0, 4))
				continue
			vb.add_child(_card_rich(text, inner_w, 12))

	# 5) Цена
	var cost: Dictionary = data.get("cost", {})
	if not cost.is_empty():
		vb.add_child(_card_sep(inner_w))
		vb.add_child(_build_cost_row(cost))
	return panel

func _card_rich(text: String, w: float, fs: int) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content    = true
	rt.scroll_active  = false
	rt.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(w, 0)
	rt.add_theme_font_size_override("normal_font_size", fs)
	rt.add_theme_font_size_override("bold_font_size", fs)
	rt.add_theme_color_override("default_color", CARD_TEXT_COL)
	rt.text = text
	return rt

func _card_sep(w: float) -> Control:
	var c := ColorRect.new()
	c.color = CARD_SEP_COL
	c.custom_minimum_size = Vector2(w, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Плитка иконки: тёмный фон, рамка, иконка; под ней — статус (ранг отряда,
## «Изучено», «Доступно», лимит). Флаг ранга — в углу плитки
func _card_badge(data: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var tile := PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.12, 0.14, 0.22)
	_borders(ts, 1); _corners(ts, 4)
	ts.border_color = Color(0.62, 0.52, 0.28)
	tile.add_theme_stylebox_override("panel", ts)
	tile.custom_minimum_size = Vector2(CARD_BADGE, CARD_BADGE)
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(tile)
	var tex: Texture2D = data.get("icon_tex") as Texture2D
	if tex == null:
		tex = _icon_texture(String(data.get("icon", "")))
	if tex != null:
		var frame := Control.new()
		frame.custom_minimum_size = Vector2(CARD_BADGE - 4.0, CARD_BADGE - 4.0)
		frame.add_child(_stretched_icon(tex))
		tile.add_child(frame)
	var vf: int = int(data.get("vet_flag", 0))
	if vf > 0:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2.ZERO
		var fl: Control = _vet_flag(vf, 1.0, 14.0)
		fl.position = Vector2(2.0, 2.0)
		holder.add_child(fl)
		tile.add_child(holder)
	var status: String = String(data.get("status", ""))
	if not status.is_empty():
		var sl := Label.new()
		sl.text = status
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.add_theme_font_size_override("font_size", 10)
		sl.add_theme_color_override("font_color", data.get("status_col", Color(0.80, 0.82, 0.88)))
		sl.custom_minimum_size = Vector2(CARD_BADGE + 20.0, 0)
		col.add_child(sl)
	return col

## Строка столбика: [значок] Подпись ……… (+прибавка) итог
func _card_stat_row(row: Dictionary, w: float) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.custom_minimum_size = Vector2(w, 0)
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(STAT_ICON_PX + 1, STAT_ICON_PX + 1)
	ic.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ip: String = String(row.get("icon", ""))
	if not ip.is_empty():
		ic.texture = _icon_texture(ip)
	hb.add_child(ic)
	var lb := Label.new()
	lb.text = String(row.get("label", ""))
	lb.add_theme_font_size_override("font_size", 12)
	lb.add_theme_color_override("font_color", CARD_LABEL_COL.lightened(0.15))
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lb)
	var bonus: String = String(row.get("bonus", ""))
	if not bonus.is_empty():
		var bl := Label.new()
		bl.text = bonus
		bl.add_theme_font_size_override("font_size", 11)
		bl.add_theme_color_override("font_color", Color(BONUS_COLOR))
		hb.add_child(bl)
	var vl := Label.new()
	vl.text = String(row.get("value", ""))
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vl.custom_minimum_size = Vector2(STAT_TOTAL_W, 0)
	vl.add_theme_font_size_override("font_size", 12)
	vl.add_theme_color_override("font_color", Color(0.98, 0.96, 0.88))
	hb.add_child(vl)
	return hb

## Карточка из текста кнопки: первая строка — заголовок, остальные — строки
func _text_card(label_text: String, tex: Texture2D) -> Dictionary:
	var parts: Array = label_text.split("\n")
	var head: String = String(parts[0]) if parts.size() > 0 else ""
	var rest: Array = []
	for i in range(1, parts.size()):
		var s: String = String(parts[i]).strip_edges()
		if not s.is_empty():
			rest.append(s)
	var icon := ""
	if tex != null:
		icon = tex.resource_path
	return {"title": head, "icon": icon, "lines": rest}

## КАРТОЧКА НАЙМА: иконка+имя (рисует _show_card) / статы Attack-Armor-Speed-HP
## посередине формулой База+Кузница+Опыт=Итог / description снизу. Числа
## берутся из конфига и складываются с бонусами кузницы — в карточке видно
## ровно то, с чем юнит выйдет в поле.
## СОСТАВ СТРОК БЕРЁТСЯ ИЗ КОНФИГА ТУЛТИПОВ (scripts/tooltip_config.gd), а не
## из последовательности append'ов здесь. Раньше часть строк добавлялась
## БЕЗУСЛОВНО, и у Рабочего в карточке стояло «Armor 0» — параметра, которого у
## него по смыслу нет вовсе. Теперь список параметров объекта — это и есть
## исчерпывающий перечень строк: нет параметра в конфиге — нет строки в окне
## (см. шапку tooltip_config.gd). Никаких «if unit_id == …» в этой функции
## live — ЖИВОЙ боец на карте, если карточка про него. Нужен только строкам
## value_type = "current_max" («Здоровье: 80/100»); у карточки найма живого нет,
## и такая строка честно покажет один максимум
func _unit_card(unit_id: String, faction: int, cost: Dictionary, squad: int,
		live: Unit = null) -> Dictionary:
	var tip: Dictionary = _TipCfg.tooltip(unit_id)
	var lines: Array = []
	# ПРОСТО ИДЁМ ПО СПИСКУ ИЗ КОНФИГА. Ни одного разбора случаев по unit_id:
	# добавили строку в visible_stats — она появилась, убрали — исчезла
	# ── ТЕЗИСНО (ТЗ 14.10.2026, п. 2): характеристики — ОДНОЙ строкой под
	# названием, описание — коротко (CARD_DESC_MAX), без перечня управления
	# ── ТЗ 20.10.2026, блок 3: характеристики — СТОЛБИКОМ со значками (по
	# строке на параметр, итог по правому краю, прибавка кузницы зелёным),
	# описание — тремя строками «Тип / Умения / Особое умение»
	var stats: Array = []
	for row_v in tip["visible_stats"]:
		var srow: Dictionary = _tip_stat(unit_id, faction, row_v as Dictionary, live)
		if not srow.is_empty():
			stats.append(srow)
	var info: Array = []
	if not String(tip["role"]).is_empty():
		info.append(["Тип", String(tip["role"])])
		info.append(["Умения", String(tip["skills"])])
		info.append(["Особое умение", String(tip["special"])])
	else:
		var desc: String = _card_short(String(tip["description"]))
		if not desc.is_empty():
			lines.append(desc)
	# Имя и иконка — тоже из конфига; UNIT_TITLES/UNIT_ICONS остаются запасным
	# вариантом для юнитов, которых в конфиге ещё не описали
	var title: String = String(tip["display_name"])
	if title == unit_id:
		title = String(UNIT_TITLES.get(unit_id, unit_id))
	# ── ОТКАТ НА РАБОЧУЮ ИКОНКУ КНОПОК, А НЕ ТОЛЬКО НА ПУСТОЕ ЗНАЧЕНИЕ ──────
	# Здесь стояло только `if icon.is_empty()`. Из-за этого карточка молча
	# показывала заглушку, когда путь в конфиге БЫЛ, но вёл в никуда: тултипы
	# ссылались на res://assets/ui/icons_units_human/*.png, которых в проекте
	# нет, тогда как кнопки Замка и отрядов брали иконки из UNIT_ICONS и
	# рисовались правильно. Пути в конфиге исправлены, но проверка нужна и
	# сама по себе: два списка путей на одни и те же картинки обязаны
	# расходиться рано или поздно, и расходиться они должны молча в пользу
	# рабочего, а не в пользу серой палки
	var icon: String = String(tip["icon"])
	if icon.is_empty() or not ResourceLoader.exists(icon):
		var fallback: String = String(UNIT_ICONS.get(unit_id, ""))
		if not fallback.is_empty():
			icon = fallback
	return {
		"title": title,
		"icon":  icon,
		"cost": cost if bool(tip["show_cost"]) else {},
		"stats": stats,
		"info": info,
		"lines": lines,
	}

## Строка столбика характеристик по описанию из конфига: {icon, label, value,
## bonus}. Пустой словарь — параметра у юнита нет (то же правило, что _tip_row)
func _tip_stat(unit_id: String, faction: int, row: Dictionary, live: Unit) -> Dictionary:
	var p: Dictionary = _TipCfg.param(row)
	if p.is_empty():
		return {}
	var icon: String = String(p.get("icon", ""))
	var label: String = String(p.get("label", String(p.get("key", ""))))
	var kind: String = String(p.get("value_type", ""))
	if kind == "pair":
		var pv: Array = _TipCfg.pair_values(unit_id, p)
		if not bool(pv[1]):
			return {}
		return {"icon": icon, "label": label,
			"value": String(p.get("short", p.get("fmt", ""))) % (pv[0] as Array)}
	var bv: Array = _TipCfg.base_value(unit_id, p)
	if not bool(bv[1]):
		return {}
	var base: float = float(bv[0])
	if kind == "plain":
		return {"icon": icon, "label": label, "value": String(p.get("fmt", "")) % base}
	if kind == "current_max":
		if live != null and is_instance_valid(live):
			return {"icon": icon, "label": label,
				"value": "%d/%d" % [int(live.current_health), int(live.max_health)]}
		return {"icon": icon, "label": label, "value": "%d" % int(base)}
	var bonus: float = 0.0
	var bkey: String = String(p.get("bonus", ""))
	if not bkey.is_empty():
		bonus += GameManager.unit_bonus(faction, unit_id, bkey)
	var ukey: String = String(p.get("upgrade", ""))
	if not ukey.is_empty():
		bonus += GameManager.get_upgrade(faction, ukey)
	var fmt: String = "%.1f" if int(p.get("digits", 0)) > 0 else "%.0f"
	return {"icon": icon, "label": label, "value": fmt % (base + bonus),
		"bonus": _signed(bonus, fmt) if absf(bonus) > 0.001 else ""}

## Описание для карточки: целыми предложениями, не длиннее CARD_DESC_MAX
const CARD_DESC_MAX := 110
func _card_short(t: String) -> String:
	t = t.strip_edges()
	if t.length() <= CARD_DESC_MAX:
		return t
	var out := ""
	for sent in t.split(". "):
		var piece: String = String(sent).strip_edges()
		if piece.is_empty():
			continue
		if not piece.ends_with("."):
			piece += "."
		if not out.is_empty() and out.length() + piece.length() + 1 > CARD_DESC_MAX:
			break
		out = piece if out.is_empty() else out + " " + piece
	return out

## ОДНА СТРОКА КАРТОЧКИ по её описанию из конфига. Пустая строка — «не
## рисовать»: параметра нет ни в PARAMS, ни в STATS этого юнита. Именно так
## «отсутствующий параметр» и превращается в отсутствующую строку
func _tip_row(unit_id: String, faction: int, row: Dictionary, live: Unit) -> String:
	var p: Dictionary = _TipCfg.param(row)
	if p.is_empty():
		return ""
	var kind: String = String(p.get("value_type", ""))
	if kind == "pair":
		var pv: Array = _TipCfg.pair_values(unit_id, p)
		if not bool(pv[1]):
			return ""
		return String(p.get("fmt", "")) % (pv[0] as Array)
	var bv: Array = _TipCfg.base_value(unit_id, p)
	if not bool(bv[1]):
		return ""
	var base: float = float(bv[0])
	if kind == "plain":
		return String(p.get("fmt", "")) % base
	if kind == "current_max":
		# У живого бойца — его текущее/максимум; без живого остаётся максимум
		if live != null and is_instance_valid(live):
			return "[b]%s:[/b] %d/%d" % [String(p.get("label", "")),
				int(live.current_health), int(live.max_health)]
		return "[b]%s:[/b] %d" % [String(p.get("label", "")), int(base)]
	# "stat": База + Кузница + Опыт = Итог. Бонусы складываются из слота
	# кузницы (bonus_*) и старого плоского апгрейда (get_upgrade), если он есть
	var bonus: float = 0.0
	var bkey: String = String(p.get("bonus", ""))
	if not bkey.is_empty():
		bonus += GameManager.unit_bonus(faction, unit_id, bkey)
	var ukey: String = String(p.get("upgrade", ""))
	if not ukey.is_empty():
		bonus += GameManager.get_upgrade(faction, ukey)
	return _stat_formula(String(p.get("label", String(p.get("key", "")))),
		base, bonus, 0.0, int(p.get("digits", 0)))

## КАРТОЧКА ПОСТРОЙКИ (ТЗ 20.10.2026, блок 3): столбик «Прочность / Стройка»,
## строки «Тип / Назначение / Особенность», цена. Строки про множитель цены
## сжаты в одну «Особенность»: игрок обязан видеть рост цены до клика
## (ТЗ 23.09.2026), но не таблицей коэффициентов
const BUILDING_INFO := {
	"castle":    ["Главное здание", "Найм рабочих, склад, гарнизон лучников на крыше"],
	"barracks":  ["Производство", "Найм копейщиков и мечников"],
	"archery":   ["Производство", "Найм лучников"],
	"tower":     ["Оборона", "Обзор и стрельба: внутрь садится отряд лучников"],
	"smithy":    ["Исследования", "Улучшения войск и рабочих"],
	"house":     ["Хозяйство", "Еда, места рабочим и армии"],
	"sheep_pen": ["Хозяйство", "Овцы для мяса, фермеры разделывают туши"],
	"market":    ["Торговля", "Обмен дерева, камня, золота и еды по курсу"],
	"storehouse": ["Хозяйство", "Точка сдачи ресурсов: рабочие несут груз к ближайшему складу"],
}

func _building_card(build_id: String) -> Dictionary:
	var cfg: Dictionary = _UCfg.building_cfg(build_id)
	var hp: float = _UCfg.building_stat(build_id, "max_hp", 0.0)
	var bt: float = _UCfg.building_stat(build_id, "build_time", 0.0)
	var stats: Array = []
	if hp > 0.0:
		stats.append({"icon": "icon_heart.png", "label": "Прочность", "value": "%d" % int(hp)})
	if build_id == "sheep_pen":
		stats.append({"icon": "icon_hammer.png", "label": "Стройка",
			"value": ("%.0f с" % bt) if (_OptSys.pen_construct and bt > 0.0) else "сразу"})
		stats.append({"icon": "icon_trader.png", "label": "Овец", "value": "%d" % int(_UCfg.SHEEP_PEN_CAPACITY)})
	elif bt > 0.0:
		stats.append({"icon": "icon_hammer.png", "label": "Стройка", "value": "%.0f с" % bt})
	else:
		stats.append({"icon": "icon_hammer.png", "label": "Стройка", "value": "сразу"})
	if build_id == "tower":
		stats.append({"icon": "icon_bow.png", "label": "Обзор", "value": "%d м" % int(_UCfg.TOWER_VISION)})
	var key: String = "house" if _UCfg.is_house(build_id) else build_id
	var meta: Array = BUILDING_INFO.get(key, ["Постройка", ""])
	var purpose: String = String(meta[1])
	if _UCfg.is_house(build_id):
		purpose = "Еда, +%d мест рабочим и +%d армии" % [
			_UCfg.HOUSE_WORKER_SLOTS, _UCfg.ARMY_HOUSE_UNITS]
	var info: Array = [["Тип", String(meta[0])], ["Назначение", purpose]]
	var mult_now: float = GameManager.build_cost_mult_for(Constants.FACTION_PLAYER, build_id)
	var have_now: int = GameManager.building_total(Constants.FACTION_PLAYER, build_id)
	var special := ""
	if build_id in _UCfg.PROGRESSIVE_BUILDINGS:
		special = "каждое следующее дороже (построено %d, сейчас ×%.0f)" % [have_now, mult_now]
	elif build_id == "tower":
		special = "с %d-й башни цена +%d %% за каждую%s" % [_UCfg.TOWER_FREE_COUNT + 1,
			int(_UCfg.TOWER_COST_STEP * 100.0),
			(" (сейчас ×%.2f)" % mult_now) if mult_now > 1.0 else ""]
	elif _UCfg.is_house(build_id):
		special = "с %d-го дома каждый ×%.1f; лимит сверх %d отрядов — роскошь%s" % [_UCfg.HOUSE_FREE_COUNT + 1,
			_UCfg.HOUSE_COST_GROWTH, int(_UCfg.HOUSE_LUXURY_FROM),
			(" (сейчас ×%.1f)" % mult_now) if mult_now > 1.0 else ""]
	elif build_id == "castle":
		special = "не больше %d крепостей; тревога — укрытие рабочих" % _UCfg.CASTLE_MAX_COUNT
	elif build_id == "barracks":
		special = "лучники на крыше: +30 % к дальности и урону"
	if not special.is_empty():
		info.append(["Особенность", special])
	return {
		"title": String(cfg.get("name", build_id)),
		"icon":  String(cfg.get("icon", "")),
		"stats": stats,
		"info": info,
		"cost": GameManager.build_cost_for(Constants.FACTION_PLAYER, build_id),
		"lines": [],
	}

## КАРТОЧКА УЛУЧШЕНИЯ: что даёт, кому, сколько качается и в каком статусе
func _upgrade_card(slot: Dictionary, faction: int) -> Dictionary:
	var upg_id: String = String(slot.get("id", ""))
	var lines: Array = [String(slot.get("desc", ""))]
	# Ключ, которого здесь нет, раньше ронял карточку на String(null): human[k] у
	# отсутствующего ключа — Nil. Читаем через get с запасным значением, чтобы
	# добавленный в BONUS_KEYS ключ в худшем случае показался своим именем, а не
	# уронил панель
	var human := {
		"bonus_attack": "урону", "bonus_armor": "броне", "bonus_health": "HP",
		"bonus_defense": "защите", "bonus_range": "дальности",
		"bonus_cooldown": "с долой с перезарядки", "bonus_spread": "кучности",
		"bonus_speed": "скорости", "bonus_push": "напору", "bonus_morale": "морали",
		"bonus_carry": "грузу за ходку", "bonus_gather": "с долой из цикла добычи",
		"bonus_build": "к темпу стройки",
		"bonus_gather_wood": "темпу рубки дерева (доля)",
		"bonus_gather_stone": "темпу добычи камня (доля)",
		"bonus_gather_gold": "темпу добычи золота (доля)",
		"bonus_gather_food": "темпу разделки мяса (доля)",
		"bonus_carry_pct": "грузу за ходку (доля)",
		"bonus_walk_pct": "скорости ходьбы (доля)",
		"bonus_walk_loaded_pct": "ходу с грузом (доля)",
		"bonus_meat_pct": "выходу мяса с туши (доля)",
		"bonus_research_pct": "темпу исследований Кузницы (доля)",
		"bonus_hire_cost": "скидке на найм рабочего (доля)",
		"bonus_train_army": "темпу обучения войск (доля)",
	}
	for key in _UCfg.BONUS_KEYS:
		var k: String = String(key)
		var v: float = slot.get(k, 0.0)
		if v == 0.0:
			continue
		var sign_s: String = "+" if v > 0.0 else ""
		lines.append("%s%s к %s" % [sign_s, ("%.1f" % v).trim_suffix(".0"),
			String(human.get(k, k))])
	var who: Array = []
	for e in slot.get("applies_to", []):
		var uid: String = String(e)
		who.append("всем" if uid == "all" else String(UNIT_TITLES.get(uid, uid)))
	# ── ТЗ 20.10.2026, блок 3: «Тип / Эффект / Для», статус — в плитке ─────
	var effect: String = String(lines[0]) if not lines.is_empty() else ""
	var extra: Array = lines.slice(1)
	if not extra.is_empty():
		effect += ("; " if not effect.is_empty() else "") + "; ".join(PackedStringArray(extra))
	var info: Array = [["Тип", "Улучшение"], ["Эффект", effect],
		["Для", ", ".join(who)],
		["Исследование", "%.0f с" % _UCfg.upgrade_research_time(slot)]]
	var status := "Доступно"
	var status_col: Color = FORGE_STATUS_OK
	if GameManager.is_researched(faction, upg_id):
		status = "Изучено"
		status_col = UPG_CHECK_COLOR
	elif GameManager.is_researching(faction, upg_id):
		status = "Исследуется"
		status_col = Color(0.56, 0.78, 0.98)
	elif not GameManager.can_research(faction, upg_id):
		var req: String = String(slot.get("requires", ""))
		var rq: Dictionary = _UCfg.get_upgrade_slot(req)
		status = "Закрыто"
		status_col = FORGE_STATUS_LOCK
		info.append(["Требует", String(rq.get("name", req))])
	return {
		"title": String(slot.get("name", upg_id)),
		"icon":  String(slot.get("icon", "")),
		"status": status, "status_col": status_col,
		"cost": _UCfg.upgrade_cost(slot),
		"info": info,
		"lines": [],
	}

# ─────────────────────────────────────────────────────────────────────────────
# ОЧЕРЕДЬ НАЙМА
# Найм идёт СТРОГО ПОСЛЕДОВАТЕЛЬНО (Building берёт production_queue[0]).
# Панель — сетка до QUEUE_ORDER_MAX мелких иконок, ОДНА НА КАЖДЫЙ ЗАКАЗ, в
# порядке клика: production_queue[0] — первая (и единственная активная) ячейка
# с полоской прогресса. ПКМ по любой ячейке отменяет ИМЕННО ЭТОТ заказ и
# возвращает ресурсы (Building.cancel_order_at).
# ─────────────────────────────────────────────────────────────────────────────

## «Подпись» состава очереди в порядке следования: spearman|spearman|archer.
## Пока она не изменилась, ячейки не пересобираются — каждый кадр обновляется
## только шкала активного заказа
func _queue_signature(bld: Building) -> String:
	if bld == null:
		return ""
	# КУЗНИЦА КЛАДЁТ В ТУ ЖЕ КОЛОНКУ СВОЮ ОЧЕРЕДЬ — исследований, а не найма
	# (см. _rebuild_research_queue). Префикс "R:" разводит два состава: без него
	# пустая очередь найма кузницы и пустая очередь исследований дали бы одну и
	# ту же подпись, и переключение между ними не заметилось бы
	if bld is Smithy:
		var ids: Array = (bld as Smithy).queued_ids()
		return "" if ids.is_empty() else "R:" + "|".join(ids)
	if bld.production_queue.is_empty():
		return ""
	var parts: Array = []
	for item in bld.production_queue:
		parts.append(String((item as Dictionary).get("name", "")))
	return "|".join(parts)

## Схлопывает button_container/_queue_box в 0 ширины и прячет их, если в них
## сейчас нет ни одного дочернего узла; возвращает фиксированную "жёсткую"
## ширину, как только появляется первый ребёнок. Вызывается и после сборки
## кнопок выделения (show_selection), и после пересборки очереди найма
## (_rebuild_queue) — это два независимых источника содержимого этих колонок
## Зарезервированный габарит ряда кнопок. Пишется В ОБЁРТКУ, а не в сетку —
## иначе центрировать было бы нечего (см. _btn_slot)
func _slot_min(sz: Vector2) -> void:
	if _btn_slot != null and is_instance_valid(_btn_slot):
		_btn_slot.custom_minimum_size = sz

func _sync_panel_grid_widths() -> void:
	# ── СЕКЦИЯ ГАРНИЗОНА — ПОСЛЕДНЕЙ В РЯДУ (ТЗ 20.09.2026, п. 6.2) ────────
	# Заказ: «справа, рядом с монахом». Ветки панели зовут _show_garrison до
	# кнопок найма (у башни после него идёт ещё «Выпустить»), поэтому место в
	# ряду выправляется здесь — в общем хвосте сборки, один раз на все ветки
	if _garrison_strip != null and is_instance_valid(_garrison_strip) 			and button_container != null and is_instance_valid(button_container) 			and _garrison_strip.get_parent() == button_container:
		button_container.move_child(_garrison_strip,
			button_container.get_child_count() - 1)
	# ОТСТУП КНОПОК НАЙМА ОТ ПРАВОГО КРАЯ — ТОЛЬКО У ЗАМКА. У остальных панелей
	# ширина считается ПО СОДЕРЖИМОМУ (_sync_panel_height), и фиксированные 15 px
	# просто раздули бы каждую из них пустотой справа
	if _btn_right_pad != null and is_instance_valid(_btn_right_pad):
		# ЗАЗОР СЧИТАЕТСЯ ОТ КРАЯ ПАНЕЛИ, А НЕ ОТ РАСПОРКИ. Между правой кромкой
		# кнопок и кромкой панели лежит ТРИ вещи: разделитель HBox (он есть между
		# любой парой соседей), сама распорка и рамка панели. Ставить в распорку
		# голые 15 px значило бы получить на экране 15 + 6 + 2 = 23 (замер
		# qa_hud5 C8г дал 28.7, когда за распоркой стояла ещё и полоса отрядов).
		# Поэтому распорке достаётся ОСТАТОК, а на экране выходит ровно
		# CASTLE_BTN_RIGHT_PAD
		# …а с появлением внутреннего отступа плашки (PANEL_PAD_X) слагаемых
		# стало четыре: разделитель + распорка + рамка + этот отступ
		# 13.09.2026: у Крепости ряд кнопок ЦЕНТРУЕТСЯ в свободном месте —
		# правая распорка тянется наравне с левой, отступ от края — CASTLE_BTN_PAD
		var pad: float = maxf(0.0,
			CASTLE_BTN_PAD - float(PANEL_HBOX_SEP) - float(PANEL_BORDER_W)
			- float(PANEL_PAD_X))
		# ТЗ 14.10.2026: у производственных зданий отступ справа тот же, что
		# слева (рамка + PANEL_PAD_X), — без добавочной распорки
		_btn_right_pad.custom_minimum_size = Vector2.ZERO
		if pad < 0.0:
			_btn_right_pad.custom_minimum_size = Vector2(pad, 0.0)
		# Распорка-невидимка: видимая, даже нулевой ширины, добавляла справа
		# лишний разделитель HBox (6 px) — отступы выходили 6 слева и 12 справа
		_btn_right_pad.visible = not _castle_boost
		# Рабочий: ряд построек тоже отцентрован (ТЗ 19.09.2026-3, п. 1)
		_btn_right_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL \
			if (_castle_boost or _worker_boost) else Control.SIZE_FILL
	# КОЛОНКА «ЧТО ВЫБРАНО» СХЛОПЫВАЕТСЯ, КОГДА ПУСТА. У Замка строка
	# «Замок N/N HP» живёт в шапке панели (см. _update_castle_caption), а
	# info_label остаётся пустым — но его минимум INFO_W всё равно резервировал
	# 110 px пустоты посреди панели, разгоняя её вширь
	if _info_col != null and is_instance_valid(_info_col):
		var info_empty: bool = _castle_boost and info_label != null \
			and info_label.text.strip_edges().is_empty() \
			and detail_text().is_empty()
		# КОЛОНКА БЕЗ ЕДИНОГО ВИДИМОГО РЕБЁНКА — тоже пустая (ТЗ 11.10.2026):
		# развёрнутый род из нескольких отрядов (шкалы опыта нет) держал 132 px
		# пустоты между портретом и карточками. Панель рабочих колонку не
		# показывает вовсе: каталог построек встаёт сразу за иконкой рабочего
		var any_vis := false
		for ch in _info_col.get_children():
			if (ch as CanvasItem).visible:
				any_vis = true
				break
		# Развёрнутый род: опыт каждого отряда — тонкая шкала на его карточке,
		# колонка с одной общей шкалой только раздвигала плашку
		if not any_vis or _worker_boost or _expanded_type != "":
			info_empty = true
		_info_col.visible = not info_empty
		_info_col.custom_minimum_size = Vector2(0, 0) if info_empty \
			else Vector2(INFO_W, COL_H)
	if button_container != null and is_instance_valid(button_container):
		var has_btns: bool = button_container.get_child_count() > 0
		button_container.visible = has_btns
		# ГАБАРИТ ДЕРЖИТ ОБЁРТКА (см. _btn_slot): сетка внутри центрируется, а
		# зарезервированное место остаётся тем же, что и было
		if _btn_slot != null and is_instance_valid(_btn_slot):
			_btn_slot.visible = has_btns
			# Производственное здание: кнопки найма по НИЖНЕЙ кромке — вровень
			# с иконкой здания, опущенной под подпись (ТЗ 14.10.2026, п. 2)
			_btn_slot.size_flags_vertical = Control.SIZE_SHRINK_END if _castle_boost \
				else Control.SIZE_SHRINK_CENTER
		if has_btns and _castle_boost:
			# ЗАМОК: одна строка укрупнённых кнопок под фактическое число —
			# жёсткая сетка на BTN_COLS тут не нужна, дрожать панели не от чего.
			# Просвет между иконками — CASTLE_BTN_PAD (заказ 13.09.2026)
			var n: int = button_container.get_child_count()
			var big: float = BTN_SIZE * CASTLE_PANEL_BOOST
			button_container.columns = n
			button_container.add_theme_constant_override("h_separation", int(CASTLE_BTN_PAD))
			# КОЛОНКА РЫЦАРЯ ВЫШЕ КВАДРАТА: под иконкой стоит кнопка ранга.
			# Высота ряда — по самому высокому ребёнку, а не по стороне кнопки
			var row_h: float = big
			for ch in button_container.get_children():
				var cc := ch as Control
				if cc != null:
					row_h = maxf(row_h, cc.get_combined_minimum_size().y)
			_slot_min(Vector2(n * big + float(n - 1) * CASTLE_BTN_PAD, row_h))
		elif has_btns and _worker_boost:
			# АРТЕЛЬ: каталог построек (сейчас 4 — Бараки/Кузница/Рудник/Дом)
			# всегда укладывается в один ряд при BTN_COLS=5, поэтому здесь тоже
			# нет смысла в многострочной сетке — как и у Замка, одна строка
			# укрупнённых кнопок под фактическое число построек
			var wn: int = button_container.get_child_count()
			var wbig: float = BTN_SIZE * WORKER_ICON_BOOST
			if _OptSys.worker_grid_panel and button_container.get_node_or_null("WorkerShelterBtn") != null:
				# Сетка 3 + «В замок» (ТЗ 30.10.2026): ряды по WORKER_GRID_COLS + 1
				var gc: int = WORKER_GRID_COLS + 1
				var gr: int = maxi(1, int(ceil(float(wn) / float(gc))))
				button_container.columns = gc
				button_container.add_theme_constant_override("h_separation", BTN_GAP)
				button_container.add_theme_constant_override("v_separation", BTN_GAP)
				_slot_min(Vector2(gc * wbig + float(gc - 1) * BTN_GAP, gr * wbig + float(gr - 1) * BTN_GAP))
			else:
				button_container.columns = wn
				_slot_min(Vector2(wn * wbig + float(wn - 1) * BTN_GAP, wbig))
		elif has_btns and _expanded_type != "":
			# РАЗВЁРНУТЫЙ РОД (ТЗ 11.10.2026): приёмы отряда — одной строкой
			# по фактическому числу кнопок, без резерва на BTN_COLS: плашка
			# держит фиксированную ширину DETAIL_PANEL_W (_sync_panel_height)
			var dn: int = button_container.get_child_count()
			button_container.columns = dn
			button_container.add_theme_constant_override("h_separation", BTN_GAP)
			_slot_min(Vector2(dn * BTN_SIZE + float(dn - 1) * BTN_GAP, COL_H))
		else:
			# ОДНА КНОПКА (рабочие загона, рудника) — сетка в одну колонку, и
			# обёртка ставит её строго по центру правой части панели (ТЗ
			# 24.10.2026, второе письмо, блок 3); при BTN_COLS колонках она
			# прижималась к левому краю сетки
			var one: bool = button_container.get_child_count() == 1
			button_container.columns = 1 if one else BTN_COLS
			button_container.add_theme_constant_override("h_separation", BTN_GAP)
			_slot_min(Vector2(
				(BTN_COLS * BTN_SIZE + (BTN_COLS - 1) * BTN_GAP) if has_btns else 0.0,
				COL_H))
	if _queue_box != null and is_instance_valid(_queue_box) \
			and _queue_frame != null and is_instance_valid(_queue_frame):
		var has_q: bool = _queue_box.get_child_count() > 0
		# ЗАМОК: бокс очереди держит размер ВСЕГДА, даже пустой — иначе он
		# выскакивает из нуля в момент первого заказа и толкает ряд кнопок
		# найма вправо (жалоба "панель шагает при добавлении в очередь").
		# Invisible-контейнер игнорируется родителем целиком (см. комментарий
		# у BoxContainer в CLAUDE.md), поэтому visible тоже держим true
		var keep_reserved: bool = has_q or _castle_boost
		_queue_frame.visible = keep_reserved
		# РАЗМЕР ЗАДАЁТСЯ РАМКЕ, А НЕ СЕТКЕ. Сетка внутри меняет и число колонок,
		# и сторону ячейки (см. _rebuild_queue) — если бы габарит держала она,
		# бокс дышал бы вместе с ней, ради чего всё и затевалось
		_queue_frame.custom_minimum_size = QUEUE_BOX_INNER \
			+ Vector2(QUEUE_FRAME_PAD, QUEUE_FRAME_PAD) * 2.0 if keep_reserved \
			else Vector2.ZERO
		# ── РЯД ЗАКАЗОВ ВЫРОВНЕН ПО ИКОНКЕ ЗДАНИЯ, А НЕ ПО ЦЕНТРУ ПАНЕЛИ ────
		# Жалоба владельца (скриншот панели Замка): «ряд иконок наезжает на
		# текст HP/названия замка». Подпись «Замок N/N HP» лежит ВНУТРИ панели,
		# прижатая к верхней кромке (CASTLE_CAPTION_BAND), и ровно под неё
		# опущена крупная иконка Замка (SHRINK_END). А бокс очереди остался
		# стоять по вертикальному ЦЕНТРУ — его верхний ряд поднимался ВЫШЕ
		# иконки, под самую строку подписи.
		# Прижимаем к нижней кромке тем же способом, что и портрет: у обоих
		# теперь одна опора — низ панели, и ряды заказов идут вровень с иконкой
		_queue_frame.size_flags_vertical = Control.SIZE_SHRINK_END if _castle_boost else Control.SIZE_SHRINK_CENTER
		# У самой сетки минимума НЕТ: её размер — это её ячейки, а габарит бокса
		# держит рамка. Иначе сетка распирала бы CenterContainer до полного
		# размера бокса и центрировать было бы нечего

func _rebuild_queue(bld: Building) -> void:
	_queue_active_bar = null
	for c in _queue_box.get_children():
		_queue_box.remove_child(c)
		c.queue_free()
	_queue_box.columns = QUEUE_ORDER_COLS
	if bld is Smithy:
		_rebuild_research_queue(bld as Smithy)
		_sync_panel_grid_widths()
		return
	if bld != null and not bld.production_queue.is_empty():
		var n: int = mini(bld.production_queue.size(), QUEUE_ORDER_MAX)
		# ДВА РЯДА ПО ПЯТЬ: columns = QUEUE_ORDER_COLS, поэтому шестой заказ
		# переносится под первый (5 сверху, 5 снизу). Сверх десяти колонок
		# становится больше, а рядов — по-прежнему два, и _queue_cell_side
		# ужимает ячейки так, чтобы вся сетка поместилась в зону
		_queue_box.columns = _queue_grid_cols(n)
		var side: float = _queue_cell_side(n)
		for i in range(n):
			var item: Dictionary = bld.production_queue[i]
			var nm: String = String(item.get("name", ""))
			# Первая ячейка — это и есть production_queue[0], активный заказ
			_queue_box.add_child(_order_slot(i, bld, nm, i == 0, side))
	# Очередь опустела/наполнилась — колонка либо схлопывается, либо
	# возвращает себе фиксированную ширину (см. _sync_panel_grid_widths)
	_sync_panel_grid_widths()

# ─────────────────────────────────────────────────────────────────────────────
# ОЧЕРЕДЬ ИССЛЕДОВАНИЙ КУЗНИЦЫ — ГОРИЗОНТАЛЬНЫЙ РЯД МЕЛКИХ ИКОНОК
#
# Живёт в ТОЙ ЖЕ колонке панели, что и очередь найма (_queue_box): у выделенной
# кузницы найма нет, колонка всё равно простаивала. Ряд ровно один — columns
# выставляется по числу заказов, поэтому на второй ряд он не переносится.
#
# Порядок читается слева направо: первая ячейка — то, что качается прямо сейчас
# (у неё рамка золотая и полоска прогресса), дальше — очередь. Именно поэтому с
# самих кнопок улучшений убраны цифры мест: очередь целиком видна здесь.
# ПКМ по ячейке снимает ИМЕННО ЭТОТ заказ с полным возвратом (Smithy.cancel_research)
# ─────────────────────────────────────────────────────────────────────────────
## КОНТЕЙНЕР РЯДА ЗАВИСИТ ОТ ТОГО, КАКАЯ ПАНЕЛЬ ОТКРЫТА. У кузницы теперь своя
## панель (см. show_forge), и её левый блок несёт собственный _forge_queue;
## _queue_box из общей нижней панели в это время не показан вовсе. Сам ряд
## строится одним и тем же _research_slot — разводится только место
func _rebuild_research_queue(smithy: Smithy) -> void:
	if smithy == null or not is_instance_valid(smithy):
		return
	var box: GridContainer = _forge_queue if forge_visible() else _queue_box
	if box == null or not is_instance_valid(box):
		return
	# remove_child ПЕРЕД queue_free, а не один queue_free: освобождение
	# отложено до конца кадра, и до тех пор старая ячейка ещё числится
	# ребёнком — Godot уникализирует имя новой ("ResearchSlot_x" → "@2"),
	# и поиск по имени перестаёт находить актуальную ячейку
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var ids: Array = smithy.queued_ids()
	if ids.is_empty():
		return
	# ЧИСЛО КОЛОНОК. В нижней панели ряд один, как и был. В панели кузницы ячейки
	# крупные (FORGE_QUEUE_ICON), а левая колонка узкая (FORGE_BLD_W) — ряд из
	# пяти таких вылез бы за панель, поэтому там сетка переносится по ширине
	# колонки. Первая ячейка (то, что качается сейчас) при этом всегда сверху слева
	if forge_visible():
		box.columns = maxi(1, int(FORGE_BLD_W / (FORGE_QUEUE_ICON + 3)))
	else:
		box.columns = ids.size()
	for i in range(ids.size()):
		box.add_child(_research_slot(smithy, String(ids[i]), i == 0))

func _research_slot(smithy: Smithy, upg_id: String, active: bool) -> Button:
	var slot: Dictionary = _UCfg.get_upgrade_slot(upg_id)
	var btn := Button.new()
	btn.name = "ResearchSlot_" + upg_id
	# РАЗМЕР ЗАВИСИТ ОТ ПАНЕЛИ. В панели кузницы это КРУПНЫЙ индикатор «что
	# качается сейчас» (FORGE_QUEUE_ICON), в общей нижней панели — мелкая ячейка
	# ряда заказов, как и была. Один виджет, два места (см. _rebuild_research_queue)
	var side: float = float(FORGE_QUEUE_ICON) if forge_visible() \
		else float(QUEUE_ORDER_ICON)
	btn.custom_minimum_size = Vector2(side, side)
	btn.clip_contents = true
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	var col: Color = Color(0.15, 0.19, 0.28) if active else Color(0.11, 0.11, 0.14)
	var sn := StyleBoxFlat.new(); sn.bg_color = col
	_borders(sn, 1); _corners(sn, 3)
	sn.border_color = Color(0.85, 0.72, 0.30) if active else Color(0.32, 0.32, 0.36)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sn)
	btn.add_theme_stylebox_override("pressed", sn)
	btn.tooltip_text = "%s — %s" % [
		String(slot.get("name", upg_id)),
		"исследуется  •  ПКМ отменит" if active else "в очереди  •  ПКМ отменит"]
	var tex := _icon_texture(String(slot.get("icon", "")))
	if tex != null:
		# Отступ картинки от рамки растёт вместе с ячейкой: на крупном
		# индикаторе прежний 1 px читался бы как «иконка распирает рамку»
		btn.add_child(_stretched_icon(tex, 1.0 if side <= float(QUEUE_ORDER_ICON) else 3.0))

	if active:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0; bar.max_value = 1.0
		var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.10, 0.10, 0.18, 0.9)
		var fl := StyleBoxFlat.new(); fl.bg_color = Color(0.34, 0.60, 1.0)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fl)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = -3.0 if side <= float(QUEUE_ORDER_ICON) else -5.0
		btn.add_child(bar)
		_queue_active_bar = bar

	btn.gui_input.connect(func(e: InputEvent): _on_upgrade_gui_input(e, smithy, upg_id))
	return btn

## Одна ячейка визуальной очереди: иконка юнита, у активного заказа (index 0)
## ещё и тонкая полоска прогресса снизу. ПКМ снимает ровно эту заявку.
## side — сторона ячейки, посчитанная под ЧИСЛО заказов (_queue_cell_side):
## чем их больше, тем мельче иконка, но ряд всегда влезает в жёлтый бокс
func _order_slot(index: int, bld: Building, unit_name: String, active: bool,
		side: float = 0.0) -> Button:
	var btn := Button.new()
	if side <= 0.0:
		side = float(QUEUE_ORDER_ICON)
	btn.custom_minimum_size = Vector2(side, side)
	btn.clip_contents = true
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	var col: Color = Color(0.15, 0.19, 0.28) if active else Color(0.11, 0.11, 0.14)
	var sn := StyleBoxFlat.new(); sn.bg_color = col
	_borders(sn, 1); _corners(sn, 3)
	sn.border_color = Color(0.85, 0.72, 0.30) if active else Color(0.32, 0.32, 0.36)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sn)
	btn.add_theme_stylebox_override("pressed", sn)
	btn.tooltip_text = "%s — ПКМ: снять заказ и вернуть ресурсы" \
		% String(UNIT_TITLES.get(unit_name, unit_name))
	var ipath: String = String(UNIT_ICONS.get(unit_name, ""))
	if ipath and ResourceLoader.exists(ipath):
		var tex := load(ipath) as Texture2D
		if tex != null:
			btn.add_child(_stretched_icon(tex, 1.0))

	if active:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0; bar.max_value = 1.0
		var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.10, 0.10, 0.18, 0.9)
		var fl := StyleBoxFlat.new(); fl.bg_color = Color(0.34, 0.60, 1.0)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fl)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = -4
		btn.add_child(bar)
		_queue_active_bar = bar

	btn.gui_input.connect(func(e: InputEvent): _on_queue_slot_rmb(e, bld, index))
	return btn

## ПКМ по ячейке визуальной очереди: снять ИМЕННО ЭТОТ заказ (по месту в
## очереди, не по типу) и вернуть ресурсы
func _on_queue_slot_rmb(e: InputEvent, bld: Building, index: int) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if bld == null or not is_instance_valid(bld):
		return
	if bld.cancel_order_at(index):
		AudioManager.play_ui("menu_close")    # отмена заказа (ТЗ 10.10.2026)
		_refresh_train_badges(bld)
		_queue_sig = ""   # состав изменился — пересобрать сетку немедленно

## Обновление очереди раз в кадр: пересборка только при смене состава
func _update_queue_ui(bld: Building) -> void:
	if _queue_box == null:
		return
	var sig := _queue_signature(bld)
	if sig != _queue_sig:
		_queue_sig = sig
		_rebuild_queue(bld)
	if _queue_active_bar == null or not is_instance_valid(_queue_active_bar):
		return
	if bld is Smithy:
		_queue_active_bar.value = (bld as Smithy).research_progress()
		return
	if bld == null or bld.production_queue.is_empty():
		return
	var item = bld.production_queue[0]
	var t: float = maxf(float(item.get("time", 1.0)), 0.01)
	_queue_active_bar.value = clampf(bld._production_timer / t, 0.0, 1.0)

func _clear_queue_ui() -> void:
	if _queue_box == null or _queue_sig.is_empty():
		return
	_queue_sig = ""
	_rebuild_queue(null)

## ── КНОПКА ПОЛНОЭКРАННОГО МЕНЮ: УЖЕ И ЧИЩЕ (заказ владельца) ───────────────
## Было 220×52 — почти квадрат под однословную подпись, и столбец из шести
## таких занимал пол-экрана. Стало 190×38: подпись та же, воздуха вокруг неё
## вдвое меньше. Скругление тоже убавлено (6 → 4) — крупный радиус на низкой
## кнопке читается как капсула, а не как кнопка
const MENU_BTN_SIZE   := Vector2(250, 44)
const MENU_BTN_RADIUS := 4

func _make_btn(label_text: String, icon_color: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = MENU_BTN_SIZE
	# ПО ЦЕНТРУ СВОЕГО СТОЛБЦА, А НЕ ВО ВСЮ ЕГО ШИРИНУ. Раздел настроек шире
	# кнопки (ползунок 190 плюс подпись 78), и без этого VBox растянул бы под
	# него ВСЕ кнопки — ровно та «широкая» кнопка, на которую жаловались
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.text = label_text.strip_edges()
	# СРЕДНЕВЕКОВЫЕ КНОПКИ (ТЗ 21.10.2026): дерево в бронзовой оправе, оттенок
	# — по роду действия, как и прежний цвет: зелёный — продолжить/заново,
	# синий — сохранение, красный — выход, прочее — дерево. Состояния
	# «обычная / наведение / нажата» и щелчок — из MedievalUI
	_MUI.style_button(btn, _menu_kind(icon_color), 17)
	btn.pressed.connect(callback)
	return btn

## Оттенок средневековой кнопки по прежнему цвету кнопки меню
static func _menu_kind(c: Color) -> String:
	if c.r > c.g * 1.6 and c.r > c.b * 1.6:
		return "red"
	if c.g > c.r * 1.2 and c.g > c.b * 1.2:
		return "green"
	if c.b > c.r * 1.3:
		return "steel"
	return "wood"

func _full_overlay(bg: Color) -> Control:
	var c := ColorRect.new(); c.color = bg
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(c); return c

func _clear_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null

func _center_vbox(parent: Control) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(cc)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	cc.add_child(vbox); return vbox

# ═════════════════════════════════════════════════════════════════════════════
# РЯД КОМАНД ОТРЯДУ: [S] ДЕРЖАТЬ · [C] ВОЛЬНО · [A] АТАКА ПО ПУТИ
# ═════════════════════════════════════════════════════════════════════════════
# Собирается ОДИН РАЗ (три колонки постоянны), а при каждом выделении только
# показывается или прячется и перекрашивается. Пересобирать его вместе с
# панелью нельзя: _refresh_panel сносит и создаёт кнопки заново по нескольку
# раз в секунду, пока идёт найм, — три новых Control на каждый такой проход
# это мусор на ровном месте.

## Кнопка одной команды: иконка (меч/щит/замок) или буква, подсказка над ней
func _build_squad_cmd_col(key: String, into: Dictionary) -> Control:
	var btn := QuietTooltipButton.new()
	btn.name = "SquadCmdBtn_" + key
	btn.tooltip_text = "%s  [%s]" % [String(SCMD_TITLES.get(key, key)), key]
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	btn.custom_minimum_size = Vector2(SCMD_BTN, SCMD_BTN)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ipath: String = String(SCMD_ICONS.get(key, ""))
	var tex: Texture2D = _icon_texture(ipath) if ipath != "" else null
	if key == "C" and tex == null:
		tex = _at_ease_icon()
	# [F1] — та же дверь крепости, что у «В замок» рабочих (ТЗ 30.10.2026)
	if key == "F1" and _OptSys.army_count_badge:
		tex = _castle_door_texture()
	if tex != null:
		btn.text = ""
		btn.add_child(_stretched_icon(tex, 3.0))
	else:
		btn.text = key
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	btn.pressed.connect(func(): _on_squad_cmd(key))
	btn.mouse_entered.connect(func(): _show_scmd_hint(btn, key))
	btn.mouse_exited.connect(func(): _hide_scmd_hint())
	into[key] = btn
	_paint_btn(btn, key, false)
	return btn

## ПОДСКАЗКА НАД КНОПКОЙ: «Вольно [C]» и две строки, что делает
func _show_scmd_hint(btn: Control, key: String) -> void:
	if _scmd_hint == null or not is_instance_valid(_scmd_hint):
		_scmd_hint = PanelContainer.new()
		_scmd_hint.name = "ScmdHint"
		_scmd_hint.top_level = true
		_scmd_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.05, 0.06, 0.10, 0.94)
		_borders(st, 1); _corners(st, 4)
		st.border_color = Color(0.55, 0.50, 0.35)
		st.content_margin_left = 6; st.content_margin_right = 6
		st.content_margin_top = 3; st.content_margin_bottom = 3
		_scmd_hint.add_theme_stylebox_override("panel", st)
		_scmd_hint_lbl = Label.new()
		_scmd_hint_lbl.add_theme_font_size_override("font_size", 11)
		_scmd_hint_lbl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
		_scmd_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_scmd_hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scmd_hint.add_child(_scmd_hint_lbl)
		add_child(_scmd_hint)
	# ТОЛЬКО СУТЬ (ТЗ 12.10.2026): «Вольно [C]» без двух строк пояснения.
	# SCMD_LINES оставлены — вернуть пояснения правкой SCMD_HINT_LINES
	var txt := "%s [%s]" % [String(SCMD_TITLES.get(key, key)), key]
	if SCMD_HINT_LINES:
		for ln in SCMD_LINES.get(key, []):
			txt += "\n" + String(ln)
	if key == "S":
		var note: String = _scmd_spear_note()
		if not note.is_empty():
			txt += "\n" + note
	_scmd_hint_lbl.text = txt
	_scmd_hint.reset_size()
	var sz: Vector2 = _scmd_hint.get_combined_minimum_size()
	var r: Rect2 = btn.get_global_rect()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var x: float = clampf(r.position.x + r.size.x * 0.5 - sz.x * 0.5, 4.0, maxf(vp.x - sz.x - 4.0, 4.0))
	_scmd_hint.global_position = Vector2(x, r.position.y - sz.y - 4.0)
	_scmd_hint.visible = true

## ── ФАЛАНГА В ПОДСКАЗКЕ ЩИТА (ТЗ 14.10.2026, п. 6) ─────────────────────────
## Среди выделенных есть копейщики: с изученной «Фалангой» — «строится
## фалангой» (копья опускаются по [S]); без — что фаланга даётся кузницей.
## Пусто — копейщиков в выделении нет
func _scmd_spear_note() -> String:
	var sm = GameManager.main.selection_manager if GameManager.main != null else null
	if sm == null:
		return ""
	var any_spear := false
	var any_phalanx := false
	for sid in sm.selected_squad_ids():
		if GameManager.squad_type(int(sid)) != "spearman":
			continue
		any_spear = true
		if GameManager.spear_wall_ready(int(sid)):
			any_phalanx = true
			break
	if not any_spear:
		return ""
	if any_phalanx:
		return "Копейщики: фаланга — копья опущены"
	return "Копейщики: фаланга — после улучшения в кузнице"

func _hide_scmd_hint() -> void:
	if _scmd_hint != null and is_instance_valid(_scmd_hint):
		_scmd_hint.visible = false

## Видна ли подсказка ряда команд (стенды)
func scmd_hint_text() -> String:
	if _scmd_hint == null or not is_instance_valid(_scmd_hint) or not _scmd_hint.visible:
		return ""
	return _scmd_hint_lbl.text

## Подсветка кнопки команды (общая для панели и полосы мульти-выбора)
func _paint_btn(btn, key: String, active: bool) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var base: Color = SCMD_COLORS.get(key, Color(0.2, 0.2, 0.25))
	var st := StyleBoxFlat.new()
	st.bg_color = base if active else base.darkened(0.45)
	_corners(st, 5)
	_borders(st, 2)
	st.border_color = Color(0.95, 0.85, 0.35) if active else Color(0.30, 0.28, 0.24)
	var sh: StyleBoxFlat = st.duplicate()
	sh.bg_color = st.bg_color.lightened(0.12)
	(btn as Button).add_theme_stylebox_override("normal", st)
	(btn as Button).add_theme_stylebox_override("hover", sh)
	(btn as Button).add_theme_stylebox_override("pressed", st)
	(btn as Button).set_meta("active", active)

## Заливка и обводка кнопки. active — команда сейчас действует (отряд стоит в
## обороне / режим атаки взведён): игрок обязан видеть СОСТОЯНИЕ, а не только
## «кнопка есть». Тем же приёмом подсвечена активная стойка (см. _cmd)
func _paint_squad_cmd(key: String, active: bool) -> void:
	_paint_btn(_ob_cmd_btns.get(key), key, active)
	_paint_btn(_squad_cmd_btns.get(key), key, active)

## Нажатие кнопки делает РОВНО ТО ЖЕ, что горячая клавиша, и через ту же
## точку входа: две реализации одной команды разошлись бы при первой правке
func _on_squad_cmd(key: String) -> void:
	var m := GameManager.main
	if m == null or not is_instance_valid(m) or m.selection_manager == null:
		return
	var sm = m.selection_manager
	match key:
		"S":
			sm.set_attack_move_armed(false)
			sm.squad_commander().stand_ground(sm)
			AudioManager.play_ui("menu_button")
		"C":
			sm.set_attack_move_armed(false)
			sm.squad_commander().at_ease(sm)
			AudioManager.play_ui("menu_button")
		"A":
			sm.set_attack_move_armed(not sm.attack_move_armed)
		"F1":
			sm.set_attack_move_armed(false)
			sm.squad_commander().call("_cancel_for_selection", sm)
			_on_send_to_castle(sm)
			AudioManager.play_ui("menu_button")
	_refresh_squad_cmd_bar()

## Показать ряд под текущее выделение и перекрасить состояния.
## РЯД ЕСТЬ ТОЛЬКО У СВОИХ БОЕВЫХ ОТРЯДОВ: рабочему «держать позицию» нечего
## держать, а чужим отрядом не командуют вовсе (см. show_recon)
func _refresh_squad_cmd_bar() -> void:
	if _squad_cmd_bar == null or not is_instance_valid(_squad_cmd_bar):
		return
	if _squad_cmd_bar.get_child_count() == 0:
		for k in SCMD_KEYS:
			_squad_cmd_bar.add_child(_build_squad_cmd_col(String(k), _squad_cmd_btns))
	var show := false
	for u in _sel_units:
		if u == null or not is_instance_valid(u) or not (u is Unit):
			continue
		var un := u as Unit
		if un.is_dead() or un.faction != Constants.FACTION_PLAYER:
			continue
		# Признак «боевой» — ТОТ ЖЕ, что у клича и озвучки приказов
		# (is_combatant): список типов пришлось бы дополнять, и забытая
		# строка вернула бы кнопки рабочему
		if un.squad_id > 0 and un.is_combatant():
			show = true
			break
	_squad_cmd_bar.visible = show
	if not show:
		return
	var m2 := GameManager.main
	var sm = m2.selection_manager if m2 != null and is_instance_valid(m2) else null
	var act: String = active_squad_cmd()
	for k in SCMD_KEYS:
		_paint_squad_cmd(String(k), String(k) == act)

## Какая кнопка режима сейчас горит (ровно одна): A → F1 → S → C
func active_squad_cmd() -> String:
	var m2 := GameManager.main
	var sm = m2.selection_manager if m2 != null and is_instance_valid(m2) else null
	if sm == null:
		return "C"
	var holding: bool = String(sm.selection_stance()) == _UCfg.STANCE_DEFENSE
	var armed: bool = bool(sm.attack_move_armed)
	var ids: Array = sm.selected_squad_ids()
	# Атака по пути, уже отданная (а не только взведённая) — тоже режим A
	if not armed and not ids.is_empty():
		var cmd = sm.squad_commander()
		armed = true
		for sid in ids:
			if not cmd.is_attack_moving(int(sid)):
				armed = false
				break
	var to_castle: bool = not ids.is_empty()
	for sid2 in ids:
		if not GameManager.squad_is_to_castle(int(sid2)):
			to_castle = false
			break
	return "A" if armed else ("F1" if to_castle else ("S" if holding else "C"))

func _corners(s: StyleBoxFlat, r: int = 6) -> void:
	s.corner_radius_top_left = r; s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r; s.corner_radius_bottom_right = r

func _borders(s: StyleBoxFlat, w: int = 2) -> void:
	s.border_width_top = w; s.border_width_bottom = w
	s.border_width_left = w; s.border_width_right = w

func _pad(w: float, h: float) -> Control:
	var c := Control.new(); c.custom_minimum_size = Vector2(w, h); return c

func _spacer(h: float) -> Control:
	return _pad(0, h)

## ── ЗНАЧОК «ВОЛЬНО» [C] (ТЗ 23.10.2026, п. 6) ──────────────────────────────
## Была буква «C». Теперь — боец в покое: первый кадр ленты покоя рыцаря
## (щит у ноги, меч опущен), вырезанный по фигуре. Лист игры, не рисунок кодом:
## та же поза, что игрок видит у стоящего отряда «вольно»
const AT_EASE_SHEET := "res://assets/factions/humans/units/Blue Units/Warrior/Warrior_Idle.png"
const AT_EASE_REGION := Rect2(44, 36, 104, 104)
static var _at_ease_tex: Texture2D = null

func _at_ease_icon() -> Texture2D:
	if _at_ease_tex != null:
		return _at_ease_tex
	if not ResourceLoader.exists(AT_EASE_SHEET):
		return null
	var sheet: Texture2D = load(AT_EASE_SHEET)
	if sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = AT_EASE_REGION
	_at_ease_tex = at
	return at
