extends CanvasLayer
class_name HUD

const _UIAssets := preload("res://scripts/UIAssets.gd")
const _UCfg     := preload("res://scripts/unit_stats_config.gd")
## Шаблоны тултипов: что и в каком порядке показывает всплывающая карточка
## (см. _unit_card / _tip_row). Отсутствующий в шаблоне параметр не рисуется
const _TipCfg   := preload("res://scripts/tooltip_config.gd")
## Древо технологий кузницы: форма сетки, узлы, цены (см. панель кузницы ниже)
const _Forge    := preload("res://scripts/forge_config.gd")

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
const PANEL_H       := 40      # МИНИМАЛЬНАЯ высота нижней панели (было 72)
## Зазор между панелью и нижней кромкой экрана
const PANEL_BOTTOM_GAP := 4
## ВЕРХНЯЯ КРОМКА ПАНЕЛИ (offset от низа экрана, отрицательный).
## Была константой; стала ПЕРЕМЕННОЙ, потому что высота панели теперь зависит
## от содержимого (_sync_panel_height её и переписывает). К ней привязано всё,
## что «висит над панелью»: подсказка размещения, полоса гарнизона, панель
## статов, всплывающая карточка — им достаточно читать актуальное значение
var PANEL_TOP: int = -(PANEL_H + PANEL_BOTTOM_GAP)
const COL_H         := 32      # рабочая высота колонок внутри панели (было 60)
const PORTRAIT_W    := 30      # (было 54)
const INFO_W        := 110     # колонка «что выбрано» (было 152)
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
const BTN_SIZE      := 22      # сторона кнопки приказа (было 44)
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
	"monk":     "res://assets/factions/humans/units/Blue Units/Monk/Idle.png",
}
const UNIT_TITLES := {
	"worker": "Рабочий", "spearman": "Копейщик",
	"archer": "Лучник",  "warrior": "Мечник", "monk": "Монах",
}
## Иконки, которые на деле являются боевым спрайт-листом (несколько кадров в
## ряд), а не готовым портретом: путь -> сторона квадратного кадра. Первый
## кадр вырезается и обрезается по силуэту в _icon_texture
const FRAME_SHEET_ICONS := {
	"res://assets/factions/humans/units/Blue Units/Monk/Idle.png": 192,
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
## Колонка «что выбрано» целиком. Нужна, чтобы схлопывать её, когда она пуста
## (Замок пишет свою строку в шапку панели, а не сюда)
var _info_col: VBoxContainer = null
var portrait: ColorRect
## Иконка того, что выбрано (юнит/здание) — поверх portrait, без рамки
var _portrait_icon: TextureRect = null
## Бейдж количества в правом нижнем углу портрета (виден при группе > 1)
var _portrait_count_lbl: Label = null
## Звёздочки ветеранства поверх портрета (виден у одиночного юнита с рангом)
var _portrait_stars_lbl: Label = null
var button_container: GridContainer
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
const CASTLE_PANEL_BOOST := 1.55
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
const CASTLE_PANEL_W := 345.0
const CASTLE_PANEL_H := 74.0
## Крупная иконка Замка слева. Больше обычного портрета: заказ владельца
## «иконка Замка слева увеличена»
const CASTLE_PORTRAIT_W := 52.0
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
const WORKER_PANEL_W_BOOST := 1.2
const WORKER_PANEL_H_BOOST := 2.0
const WORKER_ICON_BOOST    := 1.5
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
		lbl.offset_left = 8.0
		add_child(lbl)
		_castle_caption = lbl
	_castle_caption.text = text
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
#     каждый отряд типа, у карточки — живой состав, шкала здоровья и звезда
#     ветеранства. Клик по карточке сужает выделение до одного отряда.
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
var _squad_strip: HBoxContainer = null
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

	_overbar_row = HBoxContainer.new()
	_overbar_row.add_theme_constant_override("separation", 6)
	_overbar.add_child(_overbar_row)
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
	var sig := ""
	for sid in _selected_squad_ids():
		sig += "%d," % int(sid)
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
	for sid in _selected_squad_ids():
		var t: String = GameManager.squad_type(int(sid))
		if t.is_empty():
			continue
		if not squads_by_type.has(t):
			order.append(t)
			squads_by_type[t] = 0
			men_by_type[t] = 0
		squads_by_type[t] = int(squads_by_type[t]) + 1
		men_by_type[t] = int(men_by_type[t]) + GameManager.squad_members(int(sid)).size()
	return {"order": order, "squads": squads_by_type, "men": men_by_type}

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
const IDLE_WIDGET_SIZE := 52.0
const IDLE_WIDGET_TOP  := 50.0
const IDLE_WIDGET_LEFT := 8.0

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
				m.add_theme_constant_override("margin_" + side, 5)
			m.add_child(tr)
			_idle_btn.add_child(m)
			got_icon = true
	if not got_icon:
		# Ассета нет — не оставлять же плашку пустой: подписываем киркой
		_idle_btn.text = "⛏"
		_idle_btn.add_theme_font_size_override("font_size", 26)

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
	_idle_count_label.add_theme_font_size_override("font_size", 16)
	_idle_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_idle_count_label.add_theme_constant_override("outline_size", 5)
	_idle_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_idle_count_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	_idle_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_idle_count_label.offset_right  = -4
	_idle_count_label.offset_bottom = -2
	_idle_btn.add_child(_idle_count_label)

	_apply_idle_state(_idle_last if _idle_last >= 0 else 0)

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
const RES_WORKER_SECTION := Constants.RESOURCE_FOOD
## Глиф общей секции — топорик (остаётся, как и просили)
const RES_WORKER_GLYPH := "🪓"
## Глиф добывающих секций — КИРКА: это «рабочие на этом ресурсе», а не итог.
## Разные глифы разводят два разных по смыслу числа без единой подписи
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
	if tex != null:
		var tr := TextureRect.new()
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

	# ── ХВОСТ «ИНСТРУМЕНТ + РАБОЧИЕ» — В КАЖДОЙ СЕКЦИИ ──────────────────────
	# Кирка и число у дерева/камня/золота — «столько рабочих копает ЭТОТ ресурс»;
	# топорик у еды — «столько рабочих всего» (см. RES_WORKER_SECTION)
	var is_total: bool = int(rd["key"]) == RES_WORKER_SECTION
	var tool_lbl := Label.new()
	tool_lbl.text = RES_WORKER_GLYPH if is_total else RES_GATHER_GLYPH
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
var _fps_label:   Label  = null
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

	var sep := VSeparator.new(); hbox.add_child(sep)

	_fps_label = Label.new()
	_fps_label.text = "FPS: 0"
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	hbox.add_child(_fps_label)

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
func _update_top_right(delta: float) -> void:
	if _timer_label == null or not is_instance_valid(_timer_label):
		return
	if not get_tree().paused:
		_match_seconds += delta
	_timer_label.text = _format_match_time(_match_seconds)
	if _fps_label and _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
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
	_bottom_panel.offset_left   = 6
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
	_bottom_panel.add_theme_stylebox_override("panel", style)
	add_child(_bottom_panel)
	_skin_bottom_panel()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", PANEL_HBOX_SEP)
	_bottom_panel.add_child(hbox)

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
	portrait = ColorRect.new(); portrait.color = Color(0.10, 0.11, 0.15)
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
	_portrait_count_lbl.add_theme_font_size_override("font_size", 12)
	_portrait_count_lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.75))
	_portrait_count_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_portrait_count_lbl.add_theme_constant_override("outline_size", 4)
	_portrait_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_portrait_count_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	# БЕЙДЖ ПРИБИТ К НИЖНЕМУ ПРАВОМУ УГЛУ — ЧЕРЕЗ ПРОСЛОЙКУ.
	# Портрет лежит в PanelContainer, а тот РАСТЯГИВАЕТ каждого своего ребёнка
	# на весь свой прямоугольник и якоря/офсеты ребёнка просто игнорирует: и
	# цифра, и звёзды занимали всю площадь портрета, и «угол» получался только
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
	_portrait_count_lbl.offset_left   = -15
	_portrait_count_lbl.offset_top    = -14
	_portrait_count_lbl.offset_right  = -2
	_portrait_count_lbl.offset_bottom = -1
	badge_layer.add_child(_portrait_count_lbl)

	_portrait_stars_lbl = Label.new()
	_portrait_stars_lbl.text = ""
	_portrait_stars_lbl.visible = false
	_portrait_stars_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_stars_lbl.add_theme_font_size_override("font_size", 11)
	_portrait_stars_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
	_portrait_stars_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_portrait_stars_lbl.add_theme_constant_override("outline_size", 4)
	_portrait_stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_stars_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	# Звёзды — в ТОЙ ЖЕ прослойке, поверху (см. комментарий у бейджа количества)
	_portrait_stars_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_portrait_stars_lbl.offset_top    = 2
	_portrait_stars_lbl.offset_bottom = 18
	badge_layer.add_child(_portrait_stars_lbl)

	# Info: ширина колонки закреплена, подписи внутри переносятся по словам
	var info_vbox := VBoxContainer.new()
	info_vbox.name = "InfoColumn"
	info_vbox.custom_minimum_size  = Vector2(INFO_W, COL_H)
	info_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(info_vbox)
	_info_col = info_vbox

	info_label = Label.new(); info_label.text = "Ничего не выбрано"
	info_label.add_theme_color_override("font_color", Color(0.90, 0.88, 0.80))
	info_label.add_theme_font_size_override("font_size", 10)
	# ДВЕ строки, не три. _fix_label задаёт МИНИМАЛЬНУЮ высоту в lines строк, а
	# VBox складывает минимумы детей — три строки подписи плюс две строки
	# производства плюс шкала давали в сумме больше PANEL_H, и панель вылезала
	# за нижнюю кромку экрана (замер: 79 px при заданных 72)
	_fix_label(info_label, INFO_W, 2)
	info_vbox.add_child(info_label)

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

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(INFO_W - 8, 5)
	progress_bar.show_percentage = false; progress_bar.visible = false
	var pb_bg := StyleBoxFlat.new(); pb_bg.bg_color = Color(0.10, 0.10, 0.20); _corners(pb_bg, 3)
	var pb_fill := StyleBoxFlat.new(); pb_fill.bg_color = Color(0.28, 0.52, 1.0); _corners(pb_fill, 3)
	progress_bar.add_theme_stylebox_override("background", pb_bg)
	progress_bar.add_theme_stylebox_override("fill", pb_fill)
	info_vbox.add_child(progress_bar)

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
	_squad_strip = HBoxContainer.new()
	_squad_strip.name = "SquadStrip"
	_squad_strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_squad_strip.add_theme_constant_override("separation", 6)
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

	button_container = GridContainer.new()
	button_container.columns = BTN_COLS
	# Минимум под полный ряд кнопок: сетка не «дышит» при смене их числа
	button_container.custom_minimum_size = Vector2(
		BTN_COLS * BTN_SIZE + (BTN_COLS - 1) * BTN_GAP, COL_H)
	button_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# ПО ВЕРТИКАЛЬНОМУ ЦЕНТРУ ПАНЕЛИ, А НЕ ПОД ЕЁ ВЕРХНЕЙ КРОМКОЙ.
	# По умолчанию контейнер растягивался на всю высоту строки, а GridContainer
	# кладёт детей от верхнего края — из-за этого кнопки найма и выглядели
	# «задранными вверх» (жалоба владельца). SHRINK_CENTER даёт контейнеру ровно
	# его собственную высоту и ставит её в середину панели
	button_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button_container.add_theme_constant_override("h_separation", BTN_GAP)
	button_container.add_theme_constant_override("v_separation", BTN_GAP)
	hbox.add_child(button_container)

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
		_bottom_panel.custom_minimum_size = Vector2(
			maxf(CASTLE_PANEL_W, content.x), castle_h)
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
	_bottom_panel.custom_minimum_size = Vector2(need_w, need)
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
	_expanded_type = ""
	_rebuild_overbar()
	_refresh_panel()

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
	if progress_bar: progress_bar.visible = false
	_set_progress_text("")

	_clear_queue_ui()
	_hide_card()
	_hide_garrison()
	_hide_stat_panel()
	_rebuild_squad_strip()
	_train_badges.clear()   # кнопки пересобираются — старые ярлыки уже мертвы
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

	# РАЗВЁРНУТАЯ ГРУППА МОГЛА ПОГИБНУТЬ ЦЕЛИКОМ, пока панель была открыта
	# (смена выделения при этом не происходит — её некому вызвать). Панель с
	# «0 бойцов (0 отр.)» и пустой полосой карточек — мусор, поэтому молча
	# возвращаемся на уровень 1
	if _expanded_type != "" \
			and int((_selection_groups()["squads"] as Dictionary).get(_expanded_type, 0)) <= 0:
		_expanded_type = ""

	# ── УРОВЕНЬ 2: РАЗВЁРНУТА ОДНА ГРУППА ────────────────────────────────────
	if _expanded_type != "":
		if _bottom_panel: _bottom_panel.visible = true
		_build_type_detail(_expanded_type)
		_sync_panel_grid_widths()
		_sync_panel_height()
		return

	# ── УРОВЕНЬ 1: НЕСКОЛЬКО ТИПОВ — ДЕТАЛЬНОЙ ПАНЕЛИ НЕТ ВОВСЕ ──────────────
	# Ровно то, что просили: при смешанном выделении внизу видны только
	# компактные групповые иконки с числом отрядов, и ничего больше
	if selection_type_count() >= GROUP_BAR_MIN_TYPES:
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
	if _bottom_panel: _bottom_panel.visible = true

	var u = units[0]
	if units.size() == 1:
		_selected_node = u
		_selected_iid  = (u as Object).get_instance_id() if u is Object else 0
		if "current_health" in u and "max_health" in u:
			info_label.text  = "%s  %d/%d HP" % [u.display_name, int(u.current_health), int(u.max_health)]
		else:
			info_label.text = u.display_name if "display_name" in u else "Объект"

		if u is Castle and u.faction == Constants.FACTION_PLAYER:
			portrait.color = Color(0.12, 0.18, 0.30)
			_show_garrison(u as Castle)
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
			_train_cmd(u, "warrior", Color(0.30, 0.14, 0.28), big, CASTLE_ICON_BOOST)
			_train_cmd(u, "monk",    Color(0.22, 0.26, 0.14), big, CASTLE_ICON_BOOST)

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
			_build_cmd("barracks", Color(0.22, 0.20, 0.32), func(): GameManager.try_build_barracks(u))
			_build_cmd("mine",     Color(0.28, 0.22, 0.14), func(): GameManager.try_build_mine(u))

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
			_train_cmd(u, "spearman", Color(0.14, 0.18, 0.36), bbig, CASTLE_ICON_BOOST)
			_train_cmd(u, "archer",   Color(0.20, 0.28, 0.16), bbig, CASTLE_ICON_BOOST)

		elif u is Smithy and u.faction == Constants.FACTION_PLAYER:
			portrait.color = Color(0.24, 0.18, 0.10)
			_build_smithy_menu(u)

		elif u is Worker and u.faction == Constants.FACTION_PLAYER:
			portrait.color = Color(0.10, 0.22, 0.12)
			info_label.text = "Рабочий  %d/%d HP" % [int(u.current_health), int(u.max_health)]
			_worker_boost = true
			if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
				var wpw_sz: float = PORTRAIT_W * WORKER_ICON_BOOST
				_portrait_wrap.custom_minimum_size = Vector2(wpw_sz, wpw_sz)
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
			info_label.text = "Артель: %d рабочих — строят вместе (быстрее)" % crew.size()
			_worker_boost = true
			if _portrait_wrap != null and is_instance_valid(_portrait_wrap):
				var wpw_sz: float = PORTRAIT_W * WORKER_ICON_BOOST
				_portrait_wrap.custom_minimum_size = Vector2(wpw_sz, wpw_sz)
			_build_worker_menu(crew[0], crew, BTN_SIZE * WORKER_ICON_BOOST, WORKER_ICON_BOOST)
		else:
			info_label.text = "Выбрано: %d юнитов" % units.size()
			portrait.color  = Color(0.10, 0.16, 0.24)

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
# по карточке на каждый отряд (состав, шкала здоровья, звезда ветеранства) и
# обычные кнопки приказов. Выделение не меняется — сузить его до одного отряда
# можно кликом по карточке (см. _on_squad_card_pressed).
# ═════════════════════════════════════════════════════════════════════════════
func _build_type_detail(unit_id: String) -> void:
	var g: Dictionary = _selection_groups()
	var men: int    = int((g["men"] as Dictionary).get(unit_id, 0))
	var squads: int = int((g["squads"] as Dictionary).get(unit_id, 0))

	portrait.color = Color(0.12, 0.16, 0.28)
	# Портрет — иконка ТИПА, а не первого попавшегося в выделении юнита
	if _portrait_icon != null and is_instance_valid(_portrait_icon):
		var tex := _icon_texture(String(UNIT_ICONS.get(unit_id, "")))
		_portrait_icon.texture = tex
		_portrait_icon.visible = tex != null
	if _portrait_count_lbl != null and is_instance_valid(_portrait_count_lbl):
		_portrait_count_lbl.visible = men > 0
		_portrait_count_lbl.text = str(men)
	if _portrait_stars_lbl != null and is_instance_valid(_portrait_stars_lbl):
		_portrait_stars_lbl.visible = false

	# ГЛАВНАЯ ЦИФРА УРОВНЯ 2 — «57 бойцов» по этому типу, а не общая по армии
	# ДВЕ СТРОКИ ЯВНО, а не по переносу: колонка узкая (INFO_W), и одна длинная
	# строка ломалась в произвольном месте — «Отряд лучников: 24 / бойцов…»
	info_label.text = "%s\n%d бойцов (%d отр.)" % [
		_squad_title(unit_id), men, squads]

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
		_maybe_add_ability_buttons(members)
	# _maybe_add_stance_buttons переписывает info_label под ВСЁ выделение
	# (ids он берёт у SelectionManager) — возвращаем подпись типа обратно
	# ДВЕ СТРОКИ ЯВНО, а не по переносу: колонка узкая (INFO_W), и одна длинная
	# строка ломалась в произвольном месте — «Отряд лучников: 24 / бойцов…»
	info_label.text = "%s\n%d бойцов (%d отр.)" % [
		_squad_title(unit_id), men, squads]

## Путь иконки для портрета выбранного — та же таблица, что и у кнопок найма/
## построек, чтобы портрет и панель приказов всегда показывали одну картинку
func _portrait_icon_path(units: Array) -> String:
	if units.is_empty():
		return ""
	var u = units[0]
	if u is Castle or u is TownCenter:
		return _bld_icon("castle")
	if u is Barracks:
		return _bld_icon("barracks")
	if u is Smithy:
		return _bld_icon("smithy")
	if u is Worker:
		return String(UNIT_ICONS.get("worker", ""))
	if u is Archer:
		return String(UNIT_ICONS.get("archer", ""))
	if u is Spearman:
		return String(UNIT_ICONS.get("spearman", ""))
	if u is Unit and (u as Unit).display_name == "Мечник":
		return String(UNIT_ICONS.get("warrior", ""))
	return ""

## Иконка + бейджи портрета: количество (группа > 1) и звёздочки ветеранства
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

	if _portrait_stars_lbl != null and is_instance_valid(_portrait_stars_lbl):
		var lvl := 0
		if units.size() == 1 and units[0] is Unit:
			var uu := units[0] as Unit
			if uu.squad_id > 0:
				lvl = GameManager.squad_level(uu.squad_id)
		_portrait_stars_lbl.visible = lvl > 0
		if lvl > 0:
			# ЧИСЛО И ЦВЕТ ЗВЁЗД — ИЗ ТАБЛИЦЫ ГРЕЙДОВ, а не lvl штук подряд:
			# 4-й уровень это ОДНА серебряная звезда, а не четыре бронзовых
			# (см. _UCfg.VET_STAR_TIERS). Раньше на 7-м уровне рисовалось
			# семь одинаковых жёлтых звёзд в одну строку
			var tier: Dictionary = _UCfg.veteran_star_tier(lvl)
			_portrait_stars_lbl.text = "★".repeat(int(tier.get("count", 1)))
			_portrait_stars_lbl.add_theme_color_override("font_color",
				tier.get("color", Color(1.0, 0.86, 0.25)) as Color)
			# Красная звезда высшего грейда крупнее прочих и на панели тоже
			_portrait_stars_lbl.add_theme_font_size_override("font_size",
				int(round(13.0 * float(tier.get("scale", 1.0)))))
			_portrait_stars_lbl.tooltip_text = "Ветеранство: уровень %d" % lvl

## ЗВЁЗДЫ ГРЕЙДА ТЕКСТОМ (для заголовков и карточек, где нет цветного Label).
## Столько звёзд, сколько предписывает грейд, а НЕ lvl штук подряд:
## уровень 4 — одна серебряная, уровень 7 — одна красная
func _stars_text(lvl: int) -> String:
	if lvl <= 0:
		return ""
	var tier: Dictionary = _UCfg.veteran_star_tier(lvl)
	return "★".repeat(int(tier.get("count", 1)))

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
		var tname: String = _squad_title(GameManager.squad_type(sid))
		var lvl: int = GameManager.squad_level(sid)
		info_label.text = "%s%s — %d бойцов%s" % [
			tname, ("  " + _stars_text(lvl)) if lvl > 0 else "",
			units.size(), ("  (отряд %d)" % (grp + 1)) if grp >= 0 else ""]
		_show_squad_stats(sid, units)
		# Полная раскладка статов с источниками бонусов — отдельной панелью
		_show_stat_panel(sid, units)
	else:
		info_label.text = "Отрядов: %d — %d бойцов" % [ids.size(), units.size()]

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
	_cmd("Attack",
		Color(0.42, 0.14, 0.12) if atk_on else Color(0.24, 0.12, 0.11),
		func(): _on_stance_pressed(sm, _UCfg.STANCE_ATTACK),
		ICON_STANCE_ATTACK, _stance_card(sample, _UCfg.STANCE_ATTACK, atk_on),
		0.0, 1.0, atk_on)
	_cmd("Defend",
		Color(0.14, 0.30, 0.46) if def_on else Color(0.11, 0.18, 0.28),
		func(): _on_stance_pressed(sm, _UCfg.STANCE_DEFENSE),
		ICON_STANCE_DEFENSE, _stance_card(sample, _UCfg.STANCE_DEFENSE, def_on),
		0.0, 1.0, def_on)
	# ОТПРАВИТЬ ОТРЯД ЛЕЧИТЬСЯ. Отряд сам бежит к ближайшему своему замку,
	# заходит внутрь и выходит, когда здоровье и состав восстановлены
	_cmd("To Castle",
		Color(0.16, 0.34, 0.16),
		func(): _on_send_to_castle(sm),
		"", {"title": "Send to castle", "lines": [
			"The squad marches to the nearest castle",
			"Heals and refills its ranks inside",
			"Marches back out on its own when ready"]})

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
	# ЦВЕТ = СОСТОЯНИЕ. Включено — светлая синь с яркой рамкой, выключено —
	# приглушённый серо-синий: кнопка «тухнет», как и просили
	var col: Color = Color(0.20, 0.44, 0.62) if on else Color(0.13, 0.15, 0.18)
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
	if sids.is_empty():
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
		var lines: Array = [String(node.get("desc", "")),
			"Способность отряда — покупается каждому отряду отдельно",
			"Цена: %d золота за отряд" % int(cost)]
		if owned > 0:
			lines.append("Уже есть у отрядов: %d" % owned)
		if not need.is_empty():
			lines.append("Купить для отрядов: %d  (итого %d з)" % [
				need.size(), int(cost) * need.size()])
		var btn: Button = _cmd(title, col,
			func(): _on_buy_squad_ability(units, need, nid),
			String(node.get("icon", "")), {"title": title, "lines": lines})
		if btn == null:
			continue
		if need.is_empty():
			# Всем выделенным отрядам уже куплено — гасим той же схемой, что и
			# изученное улучшение в кузнице, чтобы «куплено» выглядело одинаково
			_apply_upgrade_state(btn, title, true, false, false)
		else:
			var blocker: String = GameManager.squad_ability_blocker(int(need[0]), nid)
			btn.disabled = not blocker.is_empty()
			btn.tooltip_text = "%s — %s" % [title, blocker] if not blocker.is_empty() \
				else "%s — купить этому отряду за %d з" % [title, int(cost)]

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
		var d: float = mid.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	if best == null:
		return
	# Заявка на вход — ШТАТНЫМ путём замка: он сам примет отряд, когда тот
	# подойдёт на GARRISON_ENTER_RADIUS, вылечит и выпустит обратно
	var sid: int = (men[0] as Unit).squad_id
	var accepted: bool = sid != 0 and best.request_garrison(sid)
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
		lines.append(_stat_formula("Defense", sample.defense, forge, sample.vet_defense))
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

func _filter_slot(unit_id: String, squads: int, men: int) -> Control:
	var vb := VBoxContainer.new()
	vb.name = "GroupSlot_" + unit_id
	vb.custom_minimum_size = Vector2(FILTER_CELL, 0)
	vb.add_theme_constant_override("separation", 2)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(FILTER_SLOT, FILTER_SLOT)
	# Иконка уже подписи: центрируем её в ячейке, а не растягиваем на всю ширину
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.clip_contents = true
	btn.text = ""
	var col := Color(0.16, 0.20, 0.30)
	var sn := StyleBoxFlat.new(); sn.bg_color = col.darkened(0.2)
	_borders(sn, 2); _corners(sn, 4); sn.border_color = col.lightened(0.35)
	var sh := StyleBoxFlat.new(); sh.bg_color = col.lightened(0.18)
	_borders(sh, 2); _corners(sh, 4); sh.border_color = Color(0.95, 0.88, 0.55)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover",  sh)
	btn.add_theme_stylebox_override("pressed", sn)
	var ipath: String = String(UNIT_ICONS.get(unit_id, ""))
	if ipath and ResourceLoader.exists(ipath):
		var tex := load(ipath) as Texture2D
		if tex != null:
			btn.add_child(_stretched_icon(tex, 3.0))
	else:
		btn.text = _squad_title(unit_id).get_slice(" ", 0)
		btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func(): _on_type_filter_pressed(unit_id))
	# Счётчик ОТРЯДОВ в углу иконки
	var badge := _add_badge(btn)
	badge.visible = true
	badge.text = str(squads)
	vb.add_child(btn)

	btn.tooltip_text = "%s: %d отрядов, %d бойцов. Клик — разобрать по отрядам" % [
		_squad_title(unit_id), squads, men]

	var lbl := Label.new()
	lbl.text = "%d бойцов" % men
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.78, 0.84, 0.94))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fix_label(lbl, FILTER_CELL, 1)
	vb.add_child(lbl)
	return vb

## Клик по сводному ярлыку: РАЗВЕРНУТЬ группу на нижней панели отдельными
## карточками отрядов. Повторный клик по тому же ярлыку сворачивает обратно.
##
## Выделение при этом НЕ трогается: игрок разглядывает состав, а не отдаёт
## приказ. Сузить выделение можно кликом по конкретной карточке отряда
## (см. _on_squad_card_pressed) — там это как раз и нужно, чтобы одним
## движением отправить в замок именно самый потрёпанный отряд
func _on_type_filter_pressed(unit_id: String) -> void:
	_expanded_type = "" if _expanded_type == unit_id else unit_id
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
## помещаться цифра состава, шкала здоровья и звезда ветеранства
const SQUAD_CARD  := 32
const SQUAD_HP_H  := 4     # высота шкалы под иконкой

func _rebuild_squad_strip() -> void:
	if _squad_strip == null or not is_instance_valid(_squad_strip):
		return
	for c in _squad_strip.get_children():
		c.queue_free()
	if _expanded_type == "":
		return
	for s in _selected_squad_ids():
		var sid: int = int(s)
		if GameManager.squad_type(sid) != _expanded_type:
			continue
		_squad_strip.add_child(_squad_card(sid))

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
	vb.add_theme_constant_override("separation", 3)
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER

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
		% [_squad_title(uid), alive, int(round(frac * 100.0))]
	var ipath: String = String(UNIT_ICONS.get(uid, ""))
	if ipath and ResourceLoader.exists(ipath):
		var tex := load(ipath) as Texture2D
		if tex != null:
			btn.add_child(_stretched_icon(tex, 3.0))
	else:
		btn.text = _squad_title(uid).get_slice(" ", 0)
		btn.add_theme_font_size_override("font_size", 10)
	var badge := _add_badge(btn)
	badge.visible = true
	badge.text = str(alive)
	badge.add_theme_font_size_override("font_size", 13)

	# ЗВЕЗДА ВЕТЕРАНСТВА ОТРЯДА — в ВЕРХНЕМ ЛЕВОМ углу карточки, чтобы не
	# столкнуться с цифрой состава в нижнем правом. Число и цвет звёзд берутся
	# из таблицы грейдов (уровень 4 — одна СЕРЕБРЯНАЯ, а не четыре бронзовых)
	var lvl: int = GameManager.squad_level(sid)
	if lvl > 0:
		var tier: Dictionary = _UCfg.veteran_star_tier(lvl)
		var star := Label.new()
		star.name = "SquadStar"
		star.text = "★".repeat(int(tier.get("count", 1)))
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.add_theme_font_size_override("font_size",
			int(round(11.0 * float(tier.get("scale", 1.0)))))
		star.add_theme_color_override("font_color",
			tier.get("color", Color(1.0, 0.86, 0.25)) as Color)
		star.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		star.add_theme_constant_override("outline_size", 4)
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		star.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
		star.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		star.offset_left = 2.0
		star.offset_top  = 1.0
		btn.add_child(star)

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
	fill.color = Color(0.86, 0.16, 0.14)
	fill.custom_minimum_size = Vector2(maxf(SQUAD_CARD * frac, 1.0), SQUAD_HP_H)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(fill)
	vb.add_child(bar_bg)
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

var _garrison_strip: Control = null

func _hide_garrison() -> void:
	if _garrison_strip != null and is_instance_valid(_garrison_strip):
		_garrison_strip.queue_free()
	_garrison_strip = null

func _show_garrison(castle: Castle) -> void:
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
	panel.offset_left   = 8
	panel.offset_right  = 8 + float(_UCfg.GARRISON_SQUAD_LIMIT) * (GARRISON_SLOT + 8) + 16
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
# а что — заслуженная звёздочка отряда.
# ─────────────────────────────────────────────────────────────────────────────
const STAT_PANEL_W := 320
## Зелёный прирост / жёлтый итог
const BONUS_COLOR := "#7ee07e"
const TOTAL_COLOR := "#ffe45a"

var _stat_panel: Control = null

func _hide_stat_panel() -> void:
	# Подсказка бонуса живёт НАД панелью статов и без неё осиротеет
	_hide_bonus_tip()
	if _stat_panel != null and is_instance_valid(_stat_panel):
		_stat_panel.queue_free()
	_stat_panel = null

## Формула боевого стата в разметке BBCode: «Attack: 15 +3 +2 = 20» —
## база белым, вклад кузницы и вклад опыта зелёным (оба безымянные — только
## число со знаком, БЕЗ слов «Forge»/«Bonus»), итог жёлтым через «=».
## Если оба вклада нулевые, «= итог» не печатается — база и есть итог.
func _stat_formula(nm: String, base: float, forge: float, bonus: float,
		digits: int = 0) -> String:
	var fmt: String = "%.1f" if digits > 0 else "%.0f"
	var total: float = base + forge + bonus
	var out: String = "[b]%s:[/b] %s" % [nm, fmt % base]
	if absf(forge) > 0.001:
		out += " [color=%s]+%s[/color]" % [BONUS_COLOR, fmt % forge]
	if absf(bonus) > 0.001:
		out += " [color=%s]+%s[/color]" % [BONUS_COLOR, fmt % bonus]
	if absf(forge) > 0.001 or absf(bonus) > 0.001:
		out += " [color=%s]= %s[/color]" % [TOTAL_COLOR, fmt % total]
	return out

func _show_stat_panel(squad_id: int, units: Array) -> void:
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
	var lines: Array = [
		_stat_formula("Attack",  sample.attack_damage, atk_smithy, sample.vet_attack),
		_stat_formula("Defense", sample.defense,
			GameManager.get_upgrade(f, "defense"), sample.vet_defense),
		_stat_formula("Armor",   sample.armor,
			GameManager.unit_bonus(f, uid, "bonus_armor"), sample.vet_armor),
		_stat_formula("Speed",   sample.move_speed,
			GameManager.unit_bonus(f, uid, "bonus_speed"), sample.vet_speed, 1),
		_stat_formula("Push",    sample.push_force,
			GameManager.unit_bonus(f, uid, "bonus_push"), 0.0, 1),
	]

	# ЗАРАБОТАННЫЕ БОНУСЫ ОТРЯДА: id наград по уровням, одинаковые повторяются —
	# из этого ниже собирается ряд иконок со стеком (II, III, IV)
	var chosen: Array = GameManager.squad_chosen(squad_id)

	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.10, 0.93)
	_borders(st); _corners(st, 6)
	st.border_color = Color(0.34, 0.44, 0.58)
	st.content_margin_left = 10; st.content_margin_right = 10
	st.content_margin_top  = 6;  st.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(STAT_PANEL_W, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	panel.add_child(vb)

	var lvl_head: int = GameManager.squad_level(squad_id)
	var head := Label.new()
	head.text = "%s%s — %d бойцов" % [_squad_title(GameManager.squad_type(squad_id)),
		("  " + _stars_text(lvl_head)) if lvl_head > 0 else "", units.size()]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	_fix_label(head, STAT_PANEL_W - 20, 1)
	vb.add_child(head)

	for line in lines:
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content    = true
		rt.scroll_active  = false
		rt.autowrap_mode  = TextServer.AUTOWRAP_OFF
		rt.custom_minimum_size = Vector2(STAT_PANEL_W - 20, 16)
		rt.add_theme_font_size_override("normal_font_size", 12)
		rt.add_theme_font_size_override("bold_font_size", 12)
		rt.text = String(line)
		vb.add_child(rt)

	_build_bonus_row(vb, chosen, uid)

	# Растёт ВВЕРХ от верхней кромки нижней панели на реальную высоту (см.
	# _pin_floater_above) — раньше высота "24 + lines.size()*17 + bonus_h"
	# не учитывала перенос длинного заголовка на вторую строку, и панель
	# статов наезжала на командную панель ровно под собой
	_stat_panel = panel
	await _pin_floater_above(panel, PANEL_TOP - 6, 8.0, STAT_PANEL_W)

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

var _bonus_tip: Control = null

func _hide_bonus_tip() -> void:
	if _bonus_tip != null and is_instance_valid(_bonus_tip):
		_bonus_tip.queue_free()
	_bonus_tip = null

## chosen — id наград ПО ПОРЯДКУ УРОВНЕЙ (см. GameManager.squad_chosen).
## unit_type — боевой тип отряда (stat_id), у каждого свой конфиг наград
## (см. unit_stats_config.VET_CONFIG)
func _build_bonus_row(parent: Control, chosen: Array, unit_type: String) -> void:
	if chosen.is_empty():
		return
	# Порядок вывода — по первому появлению бонуса, чтобы ряд не прыгал при
	# каждом новом уровне. Словарь id -> список уровней, на которых он взят
	var order: Array = []
	var levels: Dictionary = {}
	for i in range(chosen.size()):
		var cid: String = String(chosen[i])
		if cid.is_empty():
			continue
		if not levels.has(cid):
			levels[cid] = []
			order.append(cid)
		(levels[cid] as Array).append(i + 1)   # уровень = индекс + 1

	var row := HBoxContainer.new()
	row.name = "BonusRow"
	row.add_theme_constant_override("separation", 5)
	row.custom_minimum_size = Vector2(0.0, BONUS_ICON_SIZE)
	parent.add_child(row)

	for cid_v in order:
		var cid: String = String(cid_v)
		var lvls: Array = levels[cid]
		row.add_child(_bonus_icon(cid, lvls, unit_type))

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

	holder.mouse_entered.connect(func(): _show_bonus_tip(holder, choice_id, lvls, unit_type))
	holder.mouse_exited.connect(_hide_bonus_tip)
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

## Пять кнопок выбора улучшения. Шаблон берётся из конфига по текущему уровню
func _build_veteran_menu(squad_id: int, units: Array) -> void:
	var lvl: int = GameManager.squad_choosing_level(squad_id)
	var choices: Array = _UCfg.veteran_choices(GameManager.squad_type(squad_id), lvl)
	if choices.is_empty():
		return
	var left: int = GameManager.squad_pending(squad_id)
	info_label.text = "★ Ветеран %d — выберите награду%s" % [
		lvl, ("  (ещё %d)" % (left - 1)) if left > 1 else ""]
	for i in range(choices.size()):
		var c: Dictionary = choices[i]
		var idx := i
		_cmd(String(c.get("name", "+")), Color(0.42, 0.34, 0.08),
			func(): _on_veteran_pressed(squad_id, idx),
			String(c.get("icon", "")), _veteran_card(squad_id, c, lvl))

func _veteran_card(squad_id: int, choice: Dictionary, lvl: int) -> Dictionary:
	var stat: String = String(choice.get("stat", ""))
	var human := {
		"attack": "урону", "armor": "броне", "defense": "защите",
		"speed": "скорости", "health": "максимуму HP",
	}
	var lines: Array = [
		"Награда за уровень %d" % lvl,
		"+%s к %s каждой модели" % [
			("%.1f" % float(choice.get("value", 0.0))).trim_suffix(".0"),
			String(human.get(stat, stat))],
		"Убийств отряда: %d" % GameManager.squad_kills(squad_id),
		"Уже выбрано: %s" % _stars_text(GameManager.squad_level(squad_id)),
	]
	var have: float = GameManager.squad_bonus(squad_id, stat)
	if have > 0.0:
		lines.append("Уже получено по этой строке: +%.0f" % have)
	return {"title": String(choice.get("name", "")), "icon": String(choice.get("icon", "")),
		"hp": 0.0, "hp_max": 0.0, "lines": lines}

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
	"barracks": Color(0.22, 0.20, 0.32),
	"smithy":   Color(0.28, 0.20, 0.10),
	"mine":     Color(0.28, 0.22, 0.14),
	"house":    Color(0.26, 0.24, 0.18),
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
	for build_id in catalog:
		var bid: String = String(build_id)
		var d: Dictionary = catalog[bid]
		var cost: Dictionary = d.get("cost", {})
		var col: Color = _WORKER_BUILD_COLORS.get(bid, Color(0.24, 0.22, 0.26))
		# Не хватает ресурсов — кнопка гаснет, но остаётся нажимаемой:
		# заказ просто не пройдёт проверку в try_worker_build
		if not ResourceManager.can_afford(worker.faction, cost):
			col = col.darkened(0.45)
		# Иконка берётся из конфига здания; цена и темп стройки — в карточке
		var icon: String = String(d.get("icon", ""))
		_cmd(String(d.get("name", bid)), col,
			func(): GameManager.try_worker_build(worker, bid, crew),
			icon, _building_card(bid), size, icon_boost)

## Кнопка НАЙМА: цена, время и размер отряда читаются из конфига
## (unit_stats_config.TRAINING) — и кнопка, и карточка показывают одни числа
func _train_cmd(bld: Building, unit_id: String, col: Color, size: float = 0.0,
		icon_boost: float = 1.0) -> void:
	var c: Dictionary = _UCfg.train_cfg(bld.building_id, unit_id)
	if c.is_empty():
		return
	var cost: Dictionary = _UCfg.train_cost(bld.building_id, unit_id)
	var squad: int = int(c.get("squad", 1))
	var color := col
	if not ResourceManager.can_afford(bld.faction, cost):
		color = color.darkened(0.45)
	var title: String = String(UNIT_TITLES.get(unit_id, unit_id))
	if squad > 1:
		title += " ×%d" % squad
	var card: Dictionary = _unit_card(unit_id, bld.faction, cost, squad)
	card["title"] = title
	var lines: Array = card.get("lines", [])
	lines.append("ЛКМ — заказать, ПКМ — отменить (с возвратом)")
	card["lines"] = lines
	var btn := _cmd(title, color, func(): bld.train_from_config(unit_id),
		String(UNIT_ICONS.get(unit_id, "")), card, size, icon_boost)
	# ПКМ по иконке снимает последний заказ этого типа и возвращает ресурсы.
	# У Button нет сигнала на правую кнопку, поэтому слушаем сырой ввод
	btn.gui_input.connect(func(e: InputEvent): _on_train_rmb(e, bld, unit_id))
	# ЦИФРА КОЛИЧЕСТВА в углу иконки: сколько заказов этого типа в очереди
	_train_badges[unit_id] = _add_badge(btn)

## Кнопка ПОСТРОЙКИ из замка: цена и габарит — из конфига
func _build_cmd(build_id: String, col: Color, cb: Callable) -> void:
	var cost: Dictionary = _UCfg.building_cost(build_id)
	var color := col
	if not ResourceManager.can_afford(Constants.FACTION_PLAYER, cost):
		color = color.darkened(0.45)
	_cmd(String(_UCfg.building_cfg(build_id).get("name", build_id)), color, cb,
		_bld_icon(build_id), _building_card(build_id))

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
func _res_cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for key in cost:
		var amount: float = cost[key]
		var suffix := "?"
		match int(key):
			Constants.RESOURCE_WOOD:  suffix = "л"
			Constants.RESOURCE_GOLD:  suffix = "з"
			Constants.RESOURCE_STONE: suffix = "к"
			Constants.RESOURCE_FOOD:  suffix = "е"
		parts.append("%d %s" % [int(amount), suffix])
	return " + ".join(parts)

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
	panel.offset_left = 6
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
		var busy: bool   = GameManager.is_researching(f, nid)
		var avail: bool  = GameManager.can_research(f, nid)
		var qpos: int    = s.queue_position(nid)

		var btn := Button.new()
		btn.name = "ForgeNode_" + nid
		btn.position = _forge_cell_pos(cell)
		btn.size = Vector2(FORGE_CELL, FORGE_CELL)
		btn.custom_minimum_size = btn.size
		btn.focus_mode = Control.FOCUS_NONE
		var bs := StyleBoxFlat.new()
		if done:
			bs.bg_color = Color(0.20, 0.34, 0.20)
			bs.border_color = Color(0.36, 0.72, 0.36)
		elif busy:
			bs.bg_color = Color(0.12, 0.22, 0.34)
			bs.border_color = Color(0.36, 0.60, 0.84)
		elif avail:
			bs.bg_color = Color(0.22, 0.17, 0.08)
			bs.border_color = Color(0.62, 0.50, 0.24)
		else:
			bs.bg_color = Color(0.09, 0.09, 0.11)
			bs.border_color = Color(0.22, 0.22, 0.26)
		_corners(bs, 3); _borders(bs, 2)
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
			var col: Color = FORGE_ARROW_ON \
				if GameManager.is_researched(f, String(p)) else FORGE_ARROW_OFF
			_forge_arrow(from, to, col)
		# ── Горизонтальные двусторонние связки: ТОЛЬКО ЛИНИЯ, не зависимость
		# (см. GRID.link в forge_config). Рисуем один раз на пару — по той
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

	# ── Заголовок: крупная иконка + название
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var tex := _icon_texture(String(node.get("icon", "")))
	if tex != null:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(48, 48)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(ic)
	var title := Label.new()
	title.text = String(node.get("name", node_id))
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.42))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(FORGE_TIP_W - 76, 0)
	head.add_child(title)

	# ── Эффект
	_forge_tip_line(box, String(node.get("desc", "")), Color(0.92, 0.92, 0.88), 14)
	# Числовые бонусы — по тем же ключам, что копит GameManager
	for key in _UCfg.BONUS_KEYS:
		var k: String = String(key)
		var v: float = float(node.get(k, 0.0))
		if v != 0.0:
			_forge_tip_line(box, "%s %s" % [
				("+" if v > 0.0 else ""), "%s %s" % [
					("%.1f" % v).trim_suffix(".0"), _BONUS_TITLES.get(k, k)]],
				Color(0.80, 0.90, 0.80), 13)

	_forge_tip_line(box, "Действует: %s" % String(
		UNIT_TITLES.get(String(node.get("unit", "")), "—")),
		Color(0.86, 0.86, 0.90), 13)

	# ── Статус: он же объясняет, ПОЧЕМУ узел закрыт
	var nid: String = String(node.get("id", ""))
	var status := ""
	var status_col := Color(0.86, 0.86, 0.90)
	if GameManager.is_researched(f, nid):
		status = "Статус: изучено"
		status_col = UPG_CHECK_COLOR
	elif GameManager.is_researching(f, nid):
		var qp: int = _forge_smithy.queue_position(nid)
		status = "Статус: исследуется" if qp == 0 else "Статус: в очереди (%d)" % qp
		status_col = Color(0.56, 0.78, 0.98)
	else:
		var missing: Array = GameManager.research_blockers(f, node)
		if missing.is_empty():
			status = "Статус: доступно"
			status_col = Color(0.60, 0.90, 0.60)
		elif not (node.get("row_gate", []) as Array).is_empty() \
				and _forge_row_locked(f, node):
			# Колонка D закрыта именно рядом — называем причину прямо, иначе
			# игрок ищет несуществующую стрелку к этой иконке
			status = "Закрыто: изучите весь ряд %s (A + B + C)" % str(node.get("row", ""))
			status_col = Color(0.92, 0.66, 0.40)
		else:
			# ДВА ПУТИ ВХОДА — И ОБА НАЗЫВАЕМ. Узел открывается либо сверху (все
			# prerequisites), либо сбоку (любой сосед по горизонтальной стрелке,
			# см. GameManager.research_blockers). Показать только вертикаль значило
			# бы соврать: игрок видит стрелку вбок, а подсказка про неё молчит
			status = "Закрыто: нужно %s" % _forge_names(missing)
			var side_ids: Array = node.get("link_ids", [])
			if not side_ids.is_empty():
				status += "\nили сбоку по стрелке: %s" % _forge_names(side_ids)
			status_col = Color(0.92, 0.66, 0.40)
	_forge_tip_line(box, status, status_col, 13)

	_forge_tip_line(box, "Исследование: %d с" % int(_UCfg.upgrade_research_time(node)),
		Color(0.86, 0.86, 0.90), 13)
	_forge_tip_line(box, "Цена: %s" % _forge_cost_text(node),
		Color(0.98, 0.86, 0.42), 14)

	# ── Спец-способность: сколько будет стоить докупить её отряду
	if bool(node.get("is_unit_ability", false)):
		_forge_tip_line(box,
			"Способность отряда: %d з за отряд" % int(_Forge.squad_unlock_cost(node)),
			Color(0.72, 0.88, 0.98), 13)

	_pin_forge_tip()

## Заперт ли узел колонки D именно неполным рядом
func _forge_row_locked(f: int, node: Dictionary) -> bool:
	for g in node.get("row_gate", []):
		if not GameManager.is_researched(f, String(g)):
			return true
	return false

const _BONUS_TITLES := {
	"bonus_attack": "к урону", "bonus_armor": "к броне",
	"bonus_health": "к запасу HP", "bonus_speed": "к скорости",
	"bonus_push": "к напору", "bonus_morale": "к морали",
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
	if g > 0.0: parts.append("%d з" % int(g))
	if w > 0.0: parts.append("%d л" % int(w))
	if s > 0.0: parts.append("%d к" % int(s))
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
const UPG_CHECK_FRAC := 0.55

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
	if smithy.cancel_research(upg_id):
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
	var n: int = _idle_workers().size()
	if n == _idle_last:
		return          # ничего не поменялось — не трогаем узлы UI
	_idle_last = n
	_apply_idle_state(n)

func _process(_delta: float) -> void:
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
			_update_castle_caption(hp_text)
		elif forge_visible() and _selected_node is Smithy:
			# У кузницы своя панель: строка «Кузница N/N HP» живёт в её левом
			# блоке, а info_label общей панели сейчас вообще не показан
			if _forge_caption != null and is_instance_valid(_forge_caption):
				_forge_caption.text = hp_text
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
			if cur_id.is_empty():
				# Исследование только что закончилось: изученный узел зеленеет,
				# зависимые от него открываются. Перестраиваем ДРЕВО, а не всё
				# выделение — show_selection() пересобрал бы панель целиком
				# ради одной перекраски
				if forge_visible():
					_rebuild_forge()
				else:
					show_selection([bld])
					return
	# Состав и прогресс очереди рисует отдельная колонка (иконка + шкала +
	# «В очереди / В ожидании»). Текст в info-колонке остаётся КОРОТКИМ и
	# постоянной длины — именно его рост раньше раздвигал панель
	_update_queue_ui(bld)
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
	vbox.add_child(_make_btn("  Выход  ", Color(0.35, 0.10, 0.10), func(): get_tree().quit()))

# ─────────────────────────────────────────────────────────────────────────────
# НАСТРОЙКИ ЗВУКА: ТРИ ПОЛЗУНКА
# Шины Master / Music / SFX заводит AudioManager; здесь только ручки к ним.
# Меню паузы работает при get_tree().paused = true, поэтому и панель, и сам
# AudioManager обязаны иметь PROCESS_MODE_ALWAYS — иначе ползунок двигается,
# а звук на паузе не меняется.
# ─────────────────────────────────────────────────────────────────────────────
const AUDIO_BUSES := [
	{"bus": "Master", "name": "Общая"},
	{"bus": "Music",  "name": "Музыка"},
	{"bus": "SFX",    "name": "Эффекты"},
]

func _add_audio_sliders(parent: Control) -> void:
	parent.add_child(_spacer(10))
	var head := Label.new()
	head.text = "Звук"
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color(0.80, 0.84, 0.92))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(head)
	for entry in AUDIO_BUSES:
		var e: Dictionary = entry
		var bus: String = String(e["bus"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		parent.add_child(row)
		var cap := Label.new()
		cap.text = String(e["name"])
		cap.custom_minimum_size = Vector2(78, 0)
		cap.add_theme_font_size_override("font_size", 13)
		cap.add_theme_color_override("font_color", Color(0.78, 0.80, 0.86))
		row.add_child(cap)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step      = 0.01
		sl.value     = AudioManager.get_bus_volume(bus)
		sl.custom_minimum_size = Vector2(190, 20)
		sl.process_mode = Node.PROCESS_MODE_ALWAYS
		row.add_child(sl)
		var pct := Label.new()
		pct.text = "%d%%" % int(sl.value * 100.0)
		pct.custom_minimum_size = Vector2(44, 0)
		pct.add_theme_font_size_override("font_size", 13)
		pct.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86))
		row.add_child(pct)
		# Громкость применяется НА ЛЕТУ, а на диск пишется тем же обработчиком:
		# файл крошечный, а отдельная кнопка «Сохранить» — лишний шаг для игрока
		sl.value_changed.connect(func(v: float):
			AudioManager.set_bus_volume(bus, v)
			pct.text = "%d%%" % int(v * 100.0)
			AudioManager.save_settings())
	parent.add_child(_spacer(10))

func _show_pause_menu() -> void:
	_clear_overlay()
	get_tree().paused = true
	_overlay = _full_overlay(Color(0.02, 0.03, 0.08, 0.85))
	var vbox := _center_vbox(_overlay)
	var lbl  := Label.new(); lbl.text = "Пауза"
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vbox.add_child(lbl)
	_add_audio_sliders(vbox)
	vbox.add_child(_make_btn("  Продолжить  ", Color(0.10, 0.28, 0.10), func():
		get_tree().paused = false; _clear_overlay()))
	vbox.add_child(_make_btn("  Выйти в меню  ", Color(0.25, 0.10, 0.08), func():
		GameManager.main.restart_game()))
	vbox.add_child(_make_btn("  Выход из игры  ", Color(0.30, 0.08, 0.08), func(): get_tree().quit()))

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
			_forge_tip, _stat_card, _bonus_tip]:
		var c := n as Control
		if c != null and is_instance_valid(c) and c.visible:
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

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_ESCAPE:
		if _overlay != null:
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
	if (k.keycode == KEY_Z or k.physical_keycode == KEY_Z) and not k.echo:
		# Пока открыт оверлей (меню/победа/поражение) — Z не трогаем: там своя
		# пауза и свои кнопки, снять её вслепую значило бы продолжить игру
		# под непрозрачным экраном
		if _overlay == null:
			toggle_pause()
			get_viewport().set_input_as_handled()

func show_victory() -> void:
	_clear_overlay()
	_overlay = _full_overlay(Color(0.02, 0.10, 0.04, 0.92))
	var vbox := _center_vbox(_overlay)
	var t := Label.new(); t.text = "ПОБЕДА!"
	t.add_theme_font_size_override("font_size", 52)
	t.add_theme_color_override("font_color", Color(0.9, 0.82, 0.15))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vbox.add_child(t)
	vbox.add_child(_spacer(20))
	vbox.add_child(_make_btn("  Играть снова  ", Color(0.14, 0.32, 0.14), func(): GameManager.main.restart_game()))
	vbox.add_child(_make_btn("  Выход из игры  ", Color(0.30, 0.08, 0.08), func(): get_tree().quit()))

func show_defeat() -> void:
	_clear_overlay()
	_overlay = _full_overlay(Color(0.10, 0.02, 0.02, 0.92))
	var vbox := _center_vbox(_overlay)
	var t := Label.new(); t.text = "ПОРАЖЕНИЕ"
	t.add_theme_font_size_override("font_size", 48)
	t.add_theme_color_override("font_color", Color(0.90, 0.20, 0.15))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vbox.add_child(t)
	vbox.add_child(_spacer(20))
	vbox.add_child(_make_btn("  Попробовать снова  ", Color(0.28, 0.10, 0.10), func(): GameManager.main.restart_game()))
	vbox.add_child(_make_btn("  Выход из игры  ", Color(0.30, 0.08, 0.08), func(): get_tree().quit()))

# ─────────────────────────────────────────────────────────────────────────────
# RESOURCES
# ─────────────────────────────────────────────────────────────────────────────

func _on_resources_changed(faction: int) -> void:
	if faction == Constants.FACTION_PLAYER:
		_refresh_resources()

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
	var busy: Dictionary = {}
	for n in get_tree().get_nodes_in_group("all_units"):
		var w := n as Worker
		if w == null or w.is_dead() or w.faction != Constants.FACTION_PLAYER:
			continue
		var rt: int = w.assigned_resource_type()
		if rt >= 0:
			busy[rt] = int(busy.get(rt, 0)) + 1

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
		_inc_rate[key] = rate

		var workers: int = int(busy.get(key, 0))

		# ЧИСЛО РАБОЧИХ: В ДОБЫВАЮЩИХ СЕКЦИЯХ — НА ЭТОМ РЕСУРСЕ, В СЕКЦИИ ЕДЫ —
		# ВСЕГО. Разные по смыслу числа, поэтому и глифы разные: кирка против
		# топорика (см. RES_WORKER_SECTION / RES_GATHER_GLYPH)
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
func _icon_texture(icon_name: String) -> Texture2D:
	if icon_name.is_empty():
		return null                      # иконка не задумана — это не ошибка
	var path: String = _UCfg.smith_icon_path(icon_name)
	if not ResourceLoader.exists(path):
		push_warning("HUD: иконка не найдена: %s (в конфиге указано «%s»)"
			% [path, icon_name])
		return null
	if FRAME_SHEET_ICONS.has(path):
		return _trimmed_icon_frame(path, int(FRAME_SHEET_ICONS[path]))
	var tex := ResourceLoader.load(path) as Texture2D
	if tex == null:
		push_warning("HUD: файл не читается как текстура: %s" % path)
	return tex

## Первый кадр квадратной спрайт-полосы (frame_side×frame_side), обрезанный
## по непрозрачному силуэту — для UNIT_ICONS, у которых нет готового портрета
## и приходится брать кадр из боевого спрайт-листа (см. FRAME_SHEET_ICONS)
func _trimmed_icon_frame(path: String, frame_side: int) -> Texture2D:
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
func _cmd(label_text: String, icon_color: Color, callback: Callable,
		icon_path: String = "", card: Dictionary = {}, size: float = 0.0,
		icon_boost: float = 1.0, active: bool = false) -> Button:
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
	var cx: float = r.position.x + r.size.x * 0.5
	var px: float = clampf(cx - width * 0.5, TIP_SCREEN_PAD,
		maxf(vp.x - width - TIP_SCREEN_PAD, TIP_SCREEN_PAD))
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

func _show_card(anchor: Control, data: Dictionary) -> void:
	_hide_card()
	if data.is_empty() or anchor == null or not is_instance_valid(anchor):
		return

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.10, 0.96)
	_borders(st); _corners(st, 6)
	st.border_color = Color(0.52, 0.44, 0.24)
	st.content_margin_left = 10; st.content_margin_right = 10
	st.content_margin_top  = 8;  st.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(CARD_W, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# 1) Иконка + название
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var tex := _icon_texture(String(data.get("icon", "")))
	if tex != null:
		var frame := Control.new()
		frame.custom_minimum_size = Vector2(56, 56)
		frame.add_child(_stretched_icon(tex))
		head.add_child(frame)
	var title := Label.new()
	title.text = String(data.get("title", ""))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.98, 0.90, 0.55))
	_fix_label(title, CARD_W - 90, 2)
	head.add_child(title)

	# 2) Здоровье — ТЕКСТОМ, без полоски (никаких «красных линий» в тултипах)
	var hp_max: float = data.get("hp_max", 0.0)
	if hp_max > 0.0:
		var hp_lbl := Label.new()
		hp_lbl.text = "Health: %d" % int(hp_max)
		hp_lbl.add_theme_font_size_override("font_size", 12)
		hp_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		_fix_label(hp_lbl, CARD_W - 24, 1)
		vb.add_child(hp_lbl)

	# 3) Характеристики и бонусы. RichTextLabel + bbcode: строки могут быть
	# либо простым текстом (постройки, апгрейды — рендерится как обычно),
	# либо формулой База+Кузница+Опыт=Итог с цветными плюсами (см. _stat_formula)
	var lines: Array = data.get("lines", [])
	for i in range(mini(lines.size(), 9)):
		var text: String = String(lines[i])
		if text.is_empty():
			vb.add_child(_pad(0, 4))
			continue
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content    = true
		rt.scroll_active  = false
		rt.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
		rt.custom_minimum_size = Vector2(CARD_W - 24, 0)
		rt.add_theme_font_size_override("normal_font_size", 12)
		rt.add_theme_font_size_override("bold_font_size", 12)
		rt.add_theme_color_override("default_color", Color(0.86, 0.88, 0.92))
		rt.text = text
		vb.add_child(rt)

	var cost: Dictionary = data.get("cost", {})
	if not cost.is_empty():
		var cl := Label.new()
		cl.text = "Цена: " + _res_cost_text(cost)
		cl.add_theme_font_size_override("font_size", 12)
		cl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
		_fix_label(cl, CARD_W - 24, 1)
		vb.add_child(cl)

	# СТРОГО НАД НАВЕДЁННОЙ ИКОНКОЙ и растёт ВВЕРХ на реальную высоту
	# содержимого (см. _tip_anchor_geometry / _pin_floater_above) — не наедет
	# ни на кнопку, ни на панель, сколько бы строк ни принесли характеристики
	var g: Array = _tip_anchor_geometry(anchor, CARD_W)
	_stat_card = panel
	await _pin_floater_above(panel, float(g[1]), float(g[0]), CARD_W)

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
	for row_v in tip["visible_stats"]:
		var line: String = _tip_row(unit_id, faction, row_v as Dictionary, live)
		if not line.is_empty():
			lines.append(line)
	if squad > 1:
		lines.append("Отряд: %d" % squad)
	var desc: String = String(tip["description"])
	if not desc.is_empty():
		lines.append("")   # визуальный отступ перед описанием
		lines.append(desc)
	# Имя и иконка — тоже из конфига; UNIT_TITLES/UNIT_ICONS остаются запасным
	# вариантом для юнитов, которых в конфиге ещё не описали
	var title: String = String(tip["display_name"])
	if title == unit_id:
		title = String(UNIT_TITLES.get(unit_id, unit_id))
	var icon: String = String(tip["icon"])
	if icon.is_empty():
		icon = String(UNIT_ICONS.get(unit_id, ""))
	return {
		"title": title,
		"icon":  icon,
		"cost": cost if bool(tip["show_cost"]) else {},
		"lines": lines,
	}

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

## КАРТОЧКА ПОСТРОЙКИ: запас жизни и темп стройки — прямо из конфига
func _building_card(build_id: String) -> Dictionary:
	var cfg: Dictionary = _UCfg.building_cfg(build_id)
	var hp: float = _UCfg.building_stat(build_id, "max_hp", 0.0)
	var bt: float = _UCfg.building_stat(build_id, "build_time", 0.0)
	var lines: Array = []
	if bt > 0.0:
		lines.append("Стройка: %.0f c одним рабочим" % bt)
		lines.append("Артель: 2 раб. — %.0f c, 3 — %.0f c" % [bt / 1.6, bt / 2.2])
	else:
		lines.append("Ставится сразу, без стройки")
	var sz: Vector3 = _UCfg.building_size(build_id)
	lines.append("Габарит: %.1f × %.1f м" % [sz.x, sz.z])
	if build_id == "house":
		lines.append("Даёт %d еды каждые %d c" % [
			int(_UCfg.HOUSE_FOOD_INCOME), int(_UCfg.HOUSE_FOOD_INTERVAL)])
	return {
		"title": String(cfg.get("name", build_id)),
		"icon":  String(cfg.get("icon", "")),
		"hp": hp, "hp_max": hp,
		"cost": _UCfg.building_cost(build_id),
		"lines": lines,
	}

## КАРТОЧКА УЛУЧШЕНИЯ: что даёт, кому, сколько качается и в каком статусе
func _upgrade_card(slot: Dictionary, faction: int) -> Dictionary:
	var upg_id: String = String(slot.get("id", ""))
	var lines: Array = [String(slot.get("desc", ""))]
	var human := {
		"bonus_attack": "урону", "bonus_armor": "броне", "bonus_health": "HP",
		"bonus_speed": "скорости", "bonus_push": "напору", "bonus_morale": "морали",
	}
	for key in _UCfg.BONUS_KEYS:
		var k: String = String(key)
		var v: float = slot.get(k, 0.0)
		if v == 0.0:
			continue
		var sign_s: String = "+" if v > 0.0 else ""
		lines.append("%s%s к %s" % [sign_s, ("%.1f" % v).trim_suffix(".0"), String(human[k])])
	var who: Array = []
	for e in slot.get("applies_to", []):
		var uid: String = String(e)
		who.append("всем" if uid == "all" else String(UNIT_TITLES.get(uid, uid)))
	lines.append("Действует: " + ", ".join(who))
	lines.append("Исследование: %.0f c" % _UCfg.upgrade_research_time(slot))
	if GameManager.is_researched(faction, upg_id):
		lines.append("✓ уже изучено")
	elif GameManager.is_researching(faction, upg_id):
		lines.append("… исследуется")
	elif not GameManager.can_research(faction, upg_id):
		var req: String = String(slot.get("requires", ""))
		var rq: Dictionary = _UCfg.get_upgrade_slot(req)
		lines.append("Требует: " + String(rq.get("name", req)))
	return {
		"title": String(slot.get("name", upg_id)),
		"icon":  String(slot.get("icon", "")),
		"hp": 0.0, "hp_max": 0.0,
		"cost": _UCfg.upgrade_cost(slot),
		"lines": lines,
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
func _sync_panel_grid_widths() -> void:
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
		var pad: float = maxf(0.0,
			CASTLE_BTN_RIGHT_PAD - float(PANEL_HBOX_SEP) - float(PANEL_BORDER_W))
		_btn_right_pad.custom_minimum_size = \
			Vector2(pad, 0.0) if _castle_boost else Vector2.ZERO
	# КОЛОНКА «ЧТО ВЫБРАНО» СХЛОПЫВАЕТСЯ, КОГДА ПУСТА. У Замка строка
	# «Замок N/N HP» живёт в шапке панели (см. _update_castle_caption), а
	# info_label остаётся пустым — но его минимум INFO_W всё равно резервировал
	# 110 px пустоты посреди панели, разгоняя её вширь
	if _info_col != null and is_instance_valid(_info_col):
		var info_empty: bool = _castle_boost and info_label != null \
			and info_label.text.strip_edges().is_empty()
		_info_col.visible = not info_empty
		_info_col.custom_minimum_size = Vector2(0, 0) if info_empty \
			else Vector2(INFO_W, COL_H)
	if button_container != null and is_instance_valid(button_container):
		var has_btns: bool = button_container.get_child_count() > 0
		button_container.visible = has_btns
		if has_btns and _castle_boost:
			# ЗАМОК: РОВНО 2 кнопки укрупнённого размера, ВСЕГДА (найм рабочего
			# и рыцаря есть у любого своего Замка) — жёсткая сетка на BTN_COLS
			# тут не нужна, дрожать панели не от чего
			var n: int = button_container.get_child_count()
			var big: float = BTN_SIZE * CASTLE_PANEL_BOOST
			button_container.columns = n
			button_container.custom_minimum_size = \
				Vector2(n * big + float(n - 1) * BTN_GAP, big)
		elif has_btns and _worker_boost:
			# АРТЕЛЬ: каталог построек (сейчас 4 — Бараки/Кузница/Рудник/Дом)
			# всегда укладывается в один ряд при BTN_COLS=5, поэтому здесь тоже
			# нет смысла в многострочной сетке — как и у Замка, одна строка
			# укрупнённых кнопок под фактическое число построек
			var wn: int = button_container.get_child_count()
			var wbig: float = BTN_SIZE * WORKER_ICON_BOOST
			button_container.columns = wn
			button_container.custom_minimum_size = \
				Vector2(wn * wbig + float(wn - 1) * BTN_GAP, wbig)
		else:
			button_container.columns = BTN_COLS
			button_container.custom_minimum_size = Vector2(
				(BTN_COLS * BTN_SIZE + (BTN_COLS - 1) * BTN_GAP) if has_btns else 0.0,
				COL_H)
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

func _make_btn(label_text: String, icon_color: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(220, 52)
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	var s  := StyleBoxFlat.new(); s.bg_color  = icon_color.darkened(0.2);   _borders(s);  _corners(s, 6)
	var sh := StyleBoxFlat.new(); sh.bg_color = icon_color.lightened(0.15); _borders(sh); _corners(sh, 6)
	s.border_color  = icon_color.lightened(0.25)
	sh.border_color = Color(0.95, 0.88, 0.55)
	btn.add_theme_stylebox_override("normal",  s)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", s)
	btn.pressed.connect(callback)
	return btn

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
