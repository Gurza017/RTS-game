extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ЗНАМЁНА ВЕТЕРАНСТВА: КАРТИНКА СТРОИТСЯ КОДОМ, А НЕ ЛЕЖИТ В АССЕТАХ
## ═══════════════════════════════════════════════════════════════════════════
## Готовых знамён в ассет-паке нет — рисуем сами.
##
## РИСУЕМ НЕ ГЕОМЕТРИЕЙ, А ТЕКСТУРОЙ, и это принципиально.
## Причина в заказе: упавшее знамя обязано ЗАПЕКАТЬСЯ В ТОТ
## ЖЕ MultiMesh, что и тела павших, и наследовать их срок жизни с разложением.
## Слой тел умеет ровно одно — класть плашмя КВАД С ЛЕНТОЙ (см. CorpseRenderer):
## лента, кадр, зеркало, доля разложения. Знамя-из-треугольников туда не
## положить никак, а знамя-текстура ложится ТОЙ ЖЕ строчкой, что и труп
## копейщика, и получает и потолок, и вытеснение, и дизер даром.
##
## Побочная выгода: живое знамя и упавшее — ОДНА И ТА ЖЕ картинка, поэтому они
## не могут разъехаться по виду при правке.
##
## ── ПОЧЕМУ ПИКСЕЛЬ, А НЕ ВЕКТОР ────────────────────────────────────────────
## Весь арт игры — пиксельный, и фильтрация везде nearest. Гладкая векторная
## обводка рядом со ступенчатым копейщиком читается как чужеродная наклейка.
## Здесь всё рисуется по пикселям и обводится в один пиксель — тем же приёмом,
## что и всё остальное.
##
## Файл намеренно без class_name: подключается через preload.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _OptB := preload("res://scripts/perf_config.gd")

## ── РАЗМЕР ХОЛСТА ──────────────────────────────────────────────────────────
## Пропорции важнее абсолютных чисел: холст обязан вмещать древко во весь рост
## бойца и знамя в его верхней трети. Мировой размер задаёт SquadBanner.PIXEL_SIZE,
## поэтому менять здесь надо ТОЛЬКО пропорции, а масштаб — там
## ── ХОЛСТ РАСШИРЕН ПОД ВЫРОСШИЕ ПОЛОТНИЩА ─────────────────────────────────
## Было 80×160. Заказ владельца: вымпелы и гвидоны +50%, штандарт ×2 — и
## прежний холст их просто обрезал бы по правому краю. Древко и его место на
## холсте не менялись: растёт ПОЛОТНИЩЕ, а не пика
const W := 128
const H := 160

## ── ДРЕВКО ─────────────────────────────────────────────────────────────────
## Заказ владельца: «древко знаменной пики выполняется в цвет серого металла
## копья и сливается с ним». Поэтому цвет взят не «коричневое дерево», а тот же
## холодный металл, каким нарисованы наконечники копий в листах юнитов, и
## навершие у древка — КОПЕЙНОЕ: знаменосец держит не палку с тряпкой, а свою
## же пику, на которую насажено полотнище
const POLE_X := 12          ## левый край древка
const POLE_W := 3           ## толщина древка, пикселей
const POLE_TOP := 16        ## где кончается наконечник и начинается древко
const TIP_H := 16           ## высота копейного навершия
const TIP_HALF := 3         ## половина ширины навершия в самом широком месте

const POLE_COL   := Color(0.62, 0.65, 0.70)
const POLE_SHADE := Color(0.42, 0.45, 0.50)   ## правая грань древка — тень

## ── ПОЛОТНИЩЕ ──────────────────────────────────────────────────────────────
const FLAG_X0 := POLE_X + POLE_W - 1    ## заходит на древко, чтобы не было щели
const FLAG_TOP := 20
## ── ВЫМПЕЛ И ГВИДОН: +50% К ПРЕЖНЕМУ (заказ владельца) ────────────────────
## Было 30×52. На экране рядом с копейщиком знамя читалось значком, а не
## полотнищем — см. жалобу по скриншоту строя
const FLAG_H  := 45                     ## высота вымпела и гвидона
const FLAG_LEN := 78                    ## длина вымпела и гвидона
const NOTCH := 20                       ## глубина «ласточкина хвоста»

## Прямоугольное знамя (грейд 7) — ДРУГИХ пропорций: оно не вымпел, а штандарт,
## и должно читаться как полотнище на перекладине, а не как длинный флажок
## ── ШТАНДАРТ: РОВНО ВДВОЕ К ПРЕЖНЕМУ (заказ владельца) ───────────────────
## Было 38×36. Седьмой грейд — не «вымпел побольше», а другой предмет, и на
## экране он обязан читаться штандартом с герба, а не флажком
const STD_LEN := 76
const STD_TOP := 18
const STD_H   := 72
const FRINGE  := 6                      ## глубина золотой бахромы снизу
## Во сколько раз крупнее рисуется герб. Полотнище выросло вдвое — вырос и он,
## иначе корона осталась бы точкой в углу поля
const EMBLEM_SCALE := 2

## ── ЛЫЧКИ ──────────────────────────────────────────────────────────────────
## Ширина штриха и высота шеврона. Считаются от высоты полотнища: смени FLAG_H —
## лычки поедут за ним сами
const CHEV_T := 6                        ## толщина штриха лычки, пикселей
const CHEV_H := 33                       ## полная высота шеврона
const CHEV_X0 := 10                      ## отступ ПЕРВОЙ ЛЫЧКИ от древка
const CHEV_STEP := 13                    ## расстояние между лычками

## Белый наконечник (грейды 3 и 6): какая доля полотнища от свободного края
## перекрашивается в белый
const TIP_FRAC := 0.22

## Обводка. Тёмно-синеватая, а не чёрная: подобрана под палитру арта и не
## выглядит нарисованной поверх чёрным маркером
const OUTLINE := Color(0.08, 0.08, 0.10, 1.0)

## ── ГЕРБ ЛЕГЕНДАРНОГО ОТРЯДА ───────────────────────────────────────────────
## Корона: три зубца, обруч и камни. Рисуется маской из строк, а не кодом с
## окружностями, ровно затем, чтобы её можно было ПРАВИТЬ ГЛАЗАМИ — на
## одиннадцати пикселях в ширину любая формула всё равно упирается в то, как
## лягут конкретные точки
const EMBLEM := [
	"#.........#",
	"#....#....#",
	"#....#....#",
	"##..###..##",
	"#.#.#.#.#.#",
	"#.#.#.#.#.#",
	"#.##...##.#",
	"###########",
	"###########",
	"#.#.#.#.#.#",
	"###########",
	".#########.",
]

## ГДЕ НА ХОЛСТЕ СТОИТ ДРЕВКО, в пикселях от левого края. Спрашивает узел
## знамени: центр КВАДА и центр ДРЕВКА — разные точки, и сдвиг знамени над
## бойцом считается по этой разнице (см. SquadBanner.POLE_OFFSET_X).
## Числом его держать нельзя: холст расширялся уже дважды, и каждый раз сдвиг
## пришлось бы подбирать заново
static func pole_center_x() -> float:
	return float(POLE_X) + float(POLE_W) * 0.5

## Насколько древко левее центра холста, в пикселях
static func pole_offset_px() -> float:
	return float(W) * 0.5 - pole_center_x()

## Кэш готовых текстур: грейд -> ImageTexture. Рисуется ОДИН раз на партию,
## и лежит здесь, а не в узле знамени: узлов знамён столько же, сколько отрядов
static var _cache: Dictionary = {}

## Текстура знамени для уровня ветеранства (1..7). 0 и меньше — знамени нет
static func texture_for(level: int, side: int = 0) -> Texture2D:
	if level <= 0:
		return null
	var tier: Dictionary = _UCfg.veteran_banner_tier(level)
	if tier.is_empty():
		return null
	_side_tier(tier, side)
	# ── ПРЕЖНИЕ ВЫМПЕЛЫ ВОЗВРАЩЕНЫ (ТЗ 13.10.2026, письмо 7) ─────────────────
	# ТЗ 12.10.2026 подменило ЭТУ функцию римским штандартом, и красное
	# полотнище получал каждый отряд с рангом — «автоматическая выдача всем
	# подряд». Общее ветеранство снова рисуется проверенной шкалой из конфига
	# (вымпел → гвидон → золотой штандарт, VET_BANNER_TIERS); красный
	# штандарт — ТОЛЬКО у отряда с индивидуальным званием (vexillum_texture,
	# решает GameManager.squad_elite)
	var key: int = int(tier.get("key", level)) + side * SIDE_KEY
	if _cache.has(key):
		return _cache[key]
	var tex := _render(tier)
	_cache[key] = tex
	return tex

## ── ЦВЕТ СТОРОНЫ (ТЗ 31.10.2026) ──────────────────────────────────────────
## side 0 — игрок (синее поле), 1 — красный ИИ: то же знамя с красным полем и
## теми же лычками; красная лычка «Ветеранов» на красном поле получает светлый
## кант (rim), иначе она слилась бы с тканью. Орда рисуется своими язычками
const SIDE_KEY := 100000
const SIDE_RED := 1

static func side_of(faction: int) -> int:
	return SIDE_RED if _OptB.faction_banners and faction == 1 else 0

static func _side_tier(tier: Dictionary, side: int) -> void:
	if side != SIDE_RED:
		return
	tier["cloth"] = _UCfg.BANNER_RED
	if (tier.get("chevron_col", Color.WHITE) as Color).is_equal_approx(_UCfg.CHEV_RED):
		tier["rim"] = _UCfg.CHEV_WHITE

## Прямоугольник холста с полотнищем обычного знамени — обрезок для флажка
## в панели (HUD._vet_flag). Для штандарта — vexillum_crop()
static func flag_crop() -> Rect2:
	return Rect2(6, 12, 92, 52)

## Обрезок для флажка ранга lvl в панели: у легендарных — квадратный золотой
## штандарт (выше и шире вымпела), у прочих — прежний VET_FLAG_CROP
static func crop_for(lvl: int) -> Rect2:
	var t: Dictionary = _UCfg.veteran_banner_tier(lvl)
	if int(t.get("shape", _UCfg.BANNER_PENNANT)) == _UCfg.BANNER_STANDARD:
		return Rect2(FLAG_X0 - 4, STD_TOP - 4, STD_LEN + 9, STD_H + FRINGE + 9)
	return flag_crop()

static func vexillum_crop() -> Rect2:
	return Rect2(6, 12, 92, 52)

# ═════════════════════════════════════════════════════════════════════════════
# РИМСКИЙ ШТАНДАРТ — ЗНАМЯ ИНДИВИДУАЛЬНОГО ЗВАНИЯ (ТЗ 12.10.2026 → 13.10.2026)
# ═════════════════════════════════════════════════════════════════════════════
## Заказ: «в стиле римского штандарта — флагшток строго посередине, флаг уже и
## длиннее вниз, без жёлтого, благородный красный, сверху маленькая звёздочка,
## на теле флага — цифра ранга». Полотнище висит на ПЕРЕКЛАДИНЕ и центрировано
## по древку (центр древка остаётся там же, где у прежних вымпелов, — сдвиг
## знамени над бойцом SquadBanner.POLE_OFFSET_X не меняется). Форма одна на
## все уровни: ранг читается ЦИФРОЙ, а не формой и цветом. Белый флаг паники и
## флажок рудника остались вымпелами (это не ранг).
## С 13.10.2026 это знамя ЭЛИТЫ: выдаётся не по рангу, а по признаку
## индивидуального звания отряда (GameManager.squad_elite), и в мире рисуется
## в полтора раза крупнее обычного (SquadBanner.ELITE_SCALE)
const VEX_KEY_BASE := 1000

## Текстура красного штандарта с цифрой ранга. Ключ кэша — уровень со
## сдвигом, чтобы не пересечься ни с грейдами вымпелов, ни с ключами цвета
static func vexillum_texture(level: int) -> Texture2D:
	var lvl: int = maxi(level, 1)
	var key: int = VEX_KEY_BASE + lvl
	if _cache.has(key):
		return _cache[key]
	# ── ЛЕГЕНДАРНЫМ — КРАСНЫЙ ТРЕУГОЛЬНЫЙ ВЫМПЕЛ (ТЗ 21.10.2026, письмо 4) ──
	# «Оставить строго красные/синие треугольные флажки»: вертикальный
	# штандарт со звездой и золотой штандарт с короной сняты. Знамя
	# легендарного отряда — вымпел высшей ступени шкалы (три лычки, белый
	# конец), в мире по-прежнему × SquadBanner.ELITE_SCALE. Ключ кэша свой —
	# узел знамени по нему видит «это знамя элиты». _render_vexillum оставлен
	# для истории и стендов рисунка
	var tex := _render(_UCfg.veteran_banner_tier(_UCfg.VET_BANNER_TIERS.size()))
	_cache[key] = tex
	return tex
# ═════════════════════════════════════════════════════════════════════════════
# БОРДОВЫЙ ШТАНДАРТ ЭЛИТЫ (ТЗ 22.10.2026, блок 1)
# ═════════════════════════════════════════════════════════════════════════════
## Заказ: знамя отряда, которому игрок САМ дал элитный статус (реликвия,
## награда его рукой — GameManager.squad_elite), — прежний вертикальный
## бордовый штандарт (_render_vexillum), но на ~20 % крупнее и чуть шире; по
## центру — римская цифра уровня элиты, внизу — лычки общего ветеранства:
## пятачок всегда ярко-жёлтый (ТЗ 28.10.2026): «Опытные» (1-3) — красные
## лычки, «Ветераны» (4-6) — синие, «Легендарные» — три синие и белая
## кайма.
## Отряд один — флагшток один: штандарт ЗАМЕНЯЕТ вымпел, а реликвия своего
## флага над носителем больше не ставит (золотой штандарт «★N» снят).
## Ни одного жёлтого пикселя.
##
## Древко стоит правее, чем у вымпела (ELITE_POLE_X): полотнище висит по оси
## древка, и у края холста ему было бы тесно. Сдвиг знамени над бойцом
## считается от этого же числа (elite_pole_offset_px)
const ELITE_POLE_X := 26
const ELITE_HALF := 15              ## полуширина полотнища (было 11 — шире)
const ELITE_BAR_Y := 19             ## перекладина
const ELITE_TOP := 21               ## верх полотнища
const ELITE_H := 80                 ## высота полотнища (было 66 — +20 %)
const ELITE_FRINGE := 5
const ELITE_CLOTH := Color(0.47, 0.05, 0.11)       ## бордо
const ELITE_CLOTH_DARK := Color(0.30, 0.02, 0.07)  ## складки и кайма
const ELITE_KEY_BASE := 3000

## Римские цифры 7 строк высотой, засечками сверху и снизу
const ROMAN_GLYPHS := {
	"I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"V": ["#...#", "#...#", "#...#", ".#.#.", ".#.#.", "..#..", "..#.."],
	"X": ["#...#", ".#.#.", ".#.#.", "..#..", ".#.#.", ".#.#.", "#...#"],
}

static func roman(n: int) -> String:
	var v: int = clampi(n, 1, 39)
	var out := ""
	for pair in [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]:
		while v >= int(pair[0]):
			out += String(pair[1])
			v -= int(pair[0])
	return out

## Насколько древко штандарта элиты левее центра холста, в пикселях
static func elite_pole_offset_px() -> float:
	return float(W) * 0.5 - (float(ELITE_POLE_X) + float(POLE_W) * 0.5)

## Обрезок холста с полотнищем штандарта — флажок панели (HUD._vet_flag)
static func elite_crop() -> Rect2:
	var cx: int = ELITE_POLE_X + POLE_W / 2
	return Rect2(cx - ELITE_HALF - 2, ELITE_BAR_Y - 3, ELITE_HALF * 2 + 5,
		ELITE_H + ELITE_FRINGE + 6)

## Текстура бордового штандарта: elite_lvl — уровень элиты (римская цифра),
## vet_lvl — общее ветеранство (лычки внизу)
static func elite_texture(elite_lvl: int, vet_lvl: int = 0, side: int = 0) -> Texture2D:
	var e: int = clampi(elite_lvl, 1, 39)
	var v: int = clampi(vet_lvl, 0, _UCfg.VET_BANNER_TIERS.size())
	var key: int = ELITE_KEY_BASE + e * 10 + v + side * SIDE_KEY
	if _cache.has(key):
		return _cache[key]
	var tex := _render_elite(e, v, side)
	_cache[key] = tex
	return tex

static func _render_elite(elite_lvl: int, vet_lvl: int, side: int = 0) -> ImageTexture:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = ELITE_POLE_X + POLE_W / 2
	# Копейное навершие и древко во весь рост
	for y in range(0, TIP_H):
		var half: int = int(round(float(TIP_HALF) * sin(PI * float(y) / float(TIP_H))))
		for x in range(cx - half, cx + half + 1):
			img.set_pixel(x, y, POLE_COL if x <= cx else POLE_SHADE)
	for y in range(TIP_H, H):
		for x in range(ELITE_POLE_X, ELITE_POLE_X + POLE_W):
			img.set_pixel(x, y, POLE_SHADE if x == ELITE_POLE_X + POLE_W - 1 else POLE_COL)
	# Перекладина
	for y in range(ELITE_BAR_Y, ELITE_BAR_Y + 2):
		for x in range(cx - ELITE_HALF - 3, cx + ELITE_HALF + 4):
			img.set_pixel(x, y, POLE_COL if y == ELITE_BAR_Y else POLE_SHADE)
	# Полотнище: висит с перекладины, центр — ось древка
	var x0: int = cx - ELITE_HALF
	var x1: int = cx + ELITE_HALF
	var y1: int = ELITE_TOP + ELITE_H
	for y in range(ELITE_TOP, y1 + 1):
		for x in range(x0, x1 + 1):
			var edge: bool = x <= x0 + 1 or x >= x1 - 1 or y >= y1 - 1
			var fold: bool = (x == cx - ELITE_HALF / 2 or x == cx + ELITE_HALF / 2) and y > ELITE_TOP + 2
			img.set_pixel(x, y, ELITE_CLOTH_DARK if edge or fold else ELITE_CLOTH)
	# Кисти снизу через пиксель
	for x in range(x0, x1 + 1):
		if (x - x0) % 2 == 1:
			continue
		for y in range(y1 + 1, y1 + 1 + ELITE_FRINGE):
			img.set_pixel(x, y, ELITE_CLOTH_DARK)
	# Римская цифра уровня элиты — по центру верхней части полотнища
	_draw_roman(img, cx, ELITE_TOP + 14, roman(elite_lvl), x1 - x0 - 6)
	# Лычки ветеранства — внизу полотнища
	_draw_elite_rank(img, cx, x0, x1, y1, vet_lvl, side)
	_outline(img)
	return ImageTexture.create_from_image(img)

## Римское число по центру cx, верх y0; масштаб — сколько влезает в max_w
static func _draw_roman(img: Image, cx: int, y0: int, txt: String, max_w: int) -> void:
	var raw: int = 0
	for i in range(txt.length()):
		raw += (ROMAN_GLYPHS[txt[i]][0] as String).length() + (1 if i > 0 else 0)
	var k: int = 3
	while k > 1 and raw * k > max_w:
		k -= 1
	var x: int = cx - raw * k / 2
	for i in range(txt.length()):
		var rows: Array = ROMAN_GLYPHS[txt[i]]
		var gw: int = (rows[0] as String).length()
		for r in range(rows.size()):
			var line: String = rows[r]
			for c in range(gw):
				if line[c] != "#":
					continue
				for dy in range(k):
					for dx in range(k):
						img.set_pixel(x + c * k + dx, y0 + r * k + dy, VEX_SIGN)
		x += (gw + 1) * k

## Низ штандарта игрока (ТЗ 28.10.2026, письмо о знамёнах, п. 3, и
## уточнение владельца): пятачок ВСЕГДА ярко-жёлтый и чуть крупнее прежней
## синей плашки, меняется только цвет лычек — «Опытные» (1-3) красные 1-3,
## «Ветераны» (4-6) синие 1-3, легенда — три синие и белая кайма над пятаком
## (у легендарного отряда в мире висит золотой квадрат — spec SquadBanner;
## сюда легенда попадает из панели HUD)
## Пятак ранга — синий квадрат отряда (ТЗ 30.10.2026), лычки цвета ступени
const ELITE_PLATE := Color(0.16, 0.34, 0.70)
const ELITE_PLATE_DARK := Color(0.08, 0.18, 0.42)
const ELITE_GOLD_STEP := 9                             ## шаг лычек (у прежней синей 7)
const ELITE_GOLD_PAD := 1                              ## пятак шире прежней плашки на пиксель с каждой стороны

## Цвет лычек на пятаке по общему ветеранству — стендам и рисунку
static func elite_chevron_color(vet_lvl: int) -> Color:
	var t: Dictionary = _UCfg.veteran_banner_tier(vet_lvl)
	if bool(t.get("legend", false)):
		return _UCfg.CHEV_ORANGE
	return t.get("chevron_col", _UCfg.CHEV_WHITE) as Color

static func _draw_elite_rank(img: Image, cx: int, x0: int, x1: int, y1: int, vet_lvl: int, side: int = 0) -> void:
	if vet_lvl <= 0:
		return
	var tier: Dictionary = _UCfg.veteran_banner_tier(vet_lvl)
	var legend: bool = bool(tier.get("legend", false))
	# Легенда — три оранжевые лычки в фиолетовой рамке пятака; у красного ИИ
	# пятак красный (ТЗ 31.10.2026)
	var n: int = 3 if legend else clampi(int(tier.get("chevrons", 1)), 1, 3)
	var bottom: int = y1 - 3
	# Пятак ПОСТОЯННОГО размера (под три лычки): при одной лычке он не
	# сжимается в полоску, а лычки стоят по его центру
	var top: int = bottom - ELITE_GOLD_STEP * 3 - 4
	var lead: int = top + 3 + (3 - n) * ELITE_GOLD_STEP / 2
	var gx0: int = x0 + 2 - ELITE_GOLD_PAD
	var gx1: int = x1 - 2 + ELITE_GOLD_PAD
	for y in range(top, bottom + 1):
		for x in range(gx0, gx1 + 1):
			var eg: bool = y == top or y == bottom or x == gx0 or x == gx1
			var red: bool = side == SIDE_RED
			var edge_col: Color = _UCfg.BANNER_PURPLE if legend else (_UCfg.BANNER_RED.darkened(0.45) if red else ELITE_PLATE_DARK)
			img.set_pixel(x, y, edge_col if eg else (_UCfg.BANNER_RED if red else ELITE_PLATE))
	var col: Color = elite_chevron_color(vet_lvl)
	var hw: int = ELITE_HALF - 4
	for k in range(n):
		var yt: int = lead + k * ELITE_GOLD_STEP
		for dx in range(-hw, hw + 1):
			var yy: int = yt + (hw - absi(dx)) / 3
			for t in range(3):
				img.set_pixel(cx + dx, yy + t, col)

const BANNER_CHEVRON_COL := Color(0.97, 0.97, 0.95)

const VEX_HALF := 11                ## полуширина полотнища от оси древка
const VEX_BAR_HALF := 14            ## полуширина перекладины
const VEX_BAR_Y := 15               ## верх перекладины
const VEX_TOP := 17                 ## верх полотнища (под перекладиной)
const VEX_H := 66                   ## высота полотнища
const VEX_FRINGE := 4               ## кисти снизу
const VEX_CLOTH := Color(0.60, 0.07, 0.09)       ## благородный красный
const VEX_CLOTH_DARK := Color(0.42, 0.04, 0.06)  ## складки и кайма
const VEX_SIGN := Color(0.96, 0.95, 0.92)        ## звезда и цифра
const VEX_STAR_R := 6               ## радиус звезды наверху
## Цифры 3×5, растягиваются повтором пикселя (VEX_DIGIT_K)
const VEX_DIGIT_K := 3
const VEX_DIGITS := [
	["###", "#.#", "#.#", "#.#", "###"],
	[".#.", "##.", ".#.", ".#.", "###"],
	["###", "..#", "###", "#..", "###"],
	["###", "..#", "###", "..#", "###"],
	["#.#", "#.#", "###", "..#", "..#"],
	["###", "#..", "###", "..#", "###"],
	["###", "#..", "###", "#.#", "###"],
	["###", "..#", ".#.", ".#.", ".#."],
	["###", "#.#", "###", "#.#", "###"],
	["###", "#.#", "###", "..#", "###"],
]

static func _render_vexillum(level: int) -> ImageTexture:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = POLE_X + POLE_W / 2
	# Древко — во весь рост, от звезды до низа холста
	for y in range(VEX_STAR_R * 2, H):
		for x in range(POLE_X, POLE_X + POLE_W):
			img.set_pixel(x, y, POLE_SHADE if x == POLE_X + POLE_W - 1 else POLE_COL)
	# Перекладина
	for y in range(VEX_BAR_Y, VEX_BAR_Y + 2):
		for x in range(cx - VEX_BAR_HALF, cx + VEX_BAR_HALF + 1):
			if x >= 0 and x < W:
				img.set_pixel(x, y, POLE_COL if y == VEX_BAR_Y else POLE_SHADE)
	# Полотнище поверх древка: висит с перекладины, центр — ось древка
	var y1: int = VEX_TOP + VEX_H
	for y in range(VEX_TOP, y1 + 1):
		for x in range(cx - VEX_HALF, cx + VEX_HALF + 1):
			if x < 0 or x >= W:
				continue
			var edge: bool = x <= cx - VEX_HALF or x >= cx + VEX_HALF or y >= y1 - 1
			# Две вертикальные складки — тканью, а не плоской заливкой
			var fold: bool = (x == cx - VEX_HALF / 2 or x == cx + VEX_HALF / 2) and y > VEX_TOP + 2
			img.set_pixel(x, y, VEX_CLOTH_DARK if edge or fold else VEX_CLOTH)
	# Кисти снизу через пиксель
	for x in range(cx - VEX_HALF, cx + VEX_HALF + 1):
		if (x - (cx - VEX_HALF)) % 2 == 1:
			continue
		for y in range(y1 + 1, y1 + 1 + VEX_FRINGE):
			if x >= 0 and x < W and y < H:
				img.set_pixel(x, y, VEX_CLOTH_DARK)
	# Звезда ранга над перекладиной
	_draw_star(img, cx, VEX_STAR_R, VEX_STAR_R, VEX_SIGN)
	# Цифра ранга на теле флага
	_draw_number(img, cx, VEX_TOP + VEX_H / 2 - 6, maxi(level, 0))
	_outline(img)
	return ImageTexture.create_from_image(img)

## Пятиконечная звезда: точка внутри многоугольника из десяти вершин
static func _draw_star(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in range(10):
		var a: float = -PI * 0.5 + float(k) * PI / 5.0
		var rr: float = float(r) if k % 2 == 0 else float(r) * 0.45
		pts.append(Vector2(float(cx) + 0.5 + cos(a) * rr, float(cy) + 0.5 + sin(a) * rr))
	for y in range(cy - r - 1, cy + r + 2):
		for x in range(cx - r - 1, cx + r + 2):
			if x < 0 or x >= W or y < 0 or y >= H:
				continue
			if Geometry2D.is_point_in_polygon(Vector2(float(x) + 0.5, float(y) + 0.5), pts):
				img.set_pixel(x, y, col)

## Число цифрами 3×5 (VEX_DIGIT_K), центр по cx, верх — y0
static func _draw_number(img: Image, cx: int, y0: int, n: int) -> void:
	var txt: String = str(n)
	var k: int = VEX_DIGIT_K if txt.length() == 1 else 2
	var dw: int = 3 * k
	var gap: int = k
	var total: int = txt.length() * dw + (txt.length() - 1) * gap
	var x0: int = cx - total / 2
	for i in range(txt.length()):
		var d: int = int(txt[i])
		var rows: Array = VEX_DIGITS[clampi(d, 0, 9)]
		for r in range(5):
			var line: String = rows[r]
			for c in range(3):
				if line[c] != "#":
					continue
				for dy in range(k):
					for dx in range(k):
						var x: int = x0 + i * (dw + gap) + c * k + dx
						var y: int = y0 + r * k + dy
						if x >= 0 and x < W and y >= 0 and y < H:
							img.set_pixel(x, y, VEX_SIGN)

## Сбросить кэш (стенды, смена партии). В игре не нужен: картинки постоянны
# ═════════════════════════════════════════════════════════════════════════════
# ЗНАМЯ ОРДЫ — РВАНЫЕ «ЯЗЫЧКИ» (ТЗ 20.10.2026, блок 8)
# ═════════════════════════════════════════════════════════════════════════════
## Заказ: «у гоблинов убрать аккуратные штандарты с номерами, заменить на
## тонкие рваные флажки-язычки». Кривое тёмное древко без навершия, на нём
## 1-3 узкие полосы грязно-рыжей ткани (число растёт с рангом: 1-3, 4-6, 7),
## края неровные, концы изодраны, в ткани дыры. Ни лычек, ни цифр: ранг орды
## читается числом лоскутов. Ось древка — та же, что у людских знамён
## (POLE_X), сдвиг знамени над бойцом SquadBanner.POLE_OFFSET_X общий.
## Рисунок детерминирован (свой RandomNumberGenerator с зерном по рангу) —
## общий поток случайностей партии не сдвигается
const GOB_KEY_BASE := 2000
const GOB_POLE := Color(0.33, 0.24, 0.14)
const GOB_POLE_DARK := Color(0.22, 0.15, 0.08)
## ── ЗЕЛЁНЫЕ ЯЗЫЧКИ И БЕЛЫЙ ФЛАГ ОРДЫ (ТЗ 25.10.2026, блок 3) ─────────────
## Было: бурые лоскуты, а в панике — чужеродный белый ВЫМПЕЛ людей с тремя
## треугольниками. Заказ: «красивый насыщенный зелёный», крупнее
## (SquadBanner.GOBLIN_SCALE), а в панике тот же флаг просто БЕЛЕЕТ —
## та же форма, те же язычки и дыры (рисунок детерминирован зерном), другая
## ткань. Оттенки соседних язычков разные, чтобы лоскуты читались по одному
const GOB_CLOTHS := [Color(0.13, 0.62, 0.16), Color(0.24, 0.74, 0.12), Color(0.08, 0.50, 0.20)]
const GOB_CLOTHS_WHITE := [Color(0.96, 0.96, 0.93), Color(0.90, 0.90, 0.86), Color(0.98, 0.98, 0.96)]

## ── ЗНАМЁНА ОРДЫ ПО СКЕТЧАМ ВЛАДЕЛЬЦА (ТЗ 29.10.2026) ─────────────────────
## Ранги 1-6 — длинный горизонтальный зелёный вымпел с волнистыми краями, у
## древка вертикальные лычки: 1-3 красные (ранги 1-3), 1-3 синие (ранги 4-6).
## Легенда — рваный зелёный штандарт на перекладине (бахрома и дыры снизу) с
## шевронами «^»: красный 1-3, синий 1-3, жёлтый 1-3 — ступень = 1 + престиж
## легенды (goblin_rag_texture). В панике тот же рисунок белеет, без знаков.
## Прежние «язычки» (три лоскута по рангу) сняты. Имя функции оставлено:
## это единая точка выбора картинки знамени орды
static func goblin_tongue_texture(level: int, white: bool = false, extra: int = 0) -> Texture2D:
	var lvl: int = maxi(level, 1)
	if lvl >= _UCfg.VET_BANNER_TIERS.size():
		return goblin_rag_texture(0 if white else 1 + maxi(extra, 0), white)
	return goblin_pennant_texture(lvl, white)

const GOB_PEN_LEN := 96          ## длина вымпела, пикселей
const GOB_PEN_H := 16            ## высота у древка
const GOB_STRIPE_W := 3          ## толщина лычки
const GOB_STRIPE_STEP := 6       ## шаг лычек
const GOB_STRIPE_X0 := 5         ## отступ первой лычки от древка
const GOB_RED := Color(0.80, 0.12, 0.12)
const GOB_BLUE := Color(0.16, 0.36, 0.86)
const GOB_YELLOW := Color(0.98, 0.84, 0.16)

## Цвет знака орды по ступени 1-9: красный 1-3, синий 4-6, жёлтый 7-9
static func goblin_mark_color(step: int) -> Color:
	if step <= 3:
		return GOB_RED
	if step <= 6:
		return GOB_BLUE
	return GOB_YELLOW

static func goblin_pennant_texture(level: int, white: bool = false) -> Texture2D:
	var lvl: int = clampi(level, 1, 9)
	var key: int = GOB_KEY_BASE + lvl + (100 if white else 0)
	if _cache.has(key):
		return _cache[key]
	var cloths: Array = GOB_CLOTHS_WHITE if white else GOB_CLOTHS
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var top_y: Array = []
	var bot_y: Array = []
	for i in range(GOB_PEN_LEN):
		var f: float = float(i) / float(GOB_PEN_LEN)
		# Верх и низ волнятся каждый по-своему, к концу полотно сужается и
		# чуть провисает; самый конец скруглён
		var yt: float = float(FLAG_TOP) + sin(float(i) * 0.13) * 1.4 + f * 3.0
		var hh: float = float(GOB_PEN_H) * (1.0 - 0.30 * f)
		var yb: float = yt + hh + sin(float(i) * 0.21 + 1.3) * 1.3
		if i > GOB_PEN_LEN - 6:
			var k: float = float(i - (GOB_PEN_LEN - 6)) / 6.0
			var mid: float = (yt + yb) * 0.5
			yt = lerpf(yt, mid - 1.0, k * k)
			yb = lerpf(yb, mid + 1.0, k * k)
		top_y.append(int(round(yt)))
		bot_y.append(int(round(yb)))
	for i in range(GOB_PEN_LEN):
		var x: int = FLAG_X0 + i
		if x >= W:
			break
		var y0: int = int(top_y[i])
		var y1: int = int(bot_y[i])
		for y in range(y0, y1 + 1):
			if y < 0 or y >= H:
				continue
			var cloth: Color = cloths[(i / 14) % cloths.size()]
			var shade: Color = cloth.darkened(0.28) if (y == y1 or y == y0) else cloth
			img.set_pixel(x, y, shade)
	if not white:
		var n: int = (lvl - 1) % 3 + 1
		var col: Color = goblin_mark_color(lvl)
		for s in range(n):
			var i0: int = GOB_STRIPE_X0 + s * GOB_STRIPE_STEP
			for w in range(GOB_STRIPE_W):
				var i: int = i0 + w
				var x2: int = FLAG_X0 + i
				for y in range(int(top_y[i]) + 1, int(bot_y[i])):
					# Лычка чуть наклонена — как на скетче
					var xs: int = x2 + (y - int(top_y[i])) / 7
					if xs < W:
						img.set_pixel(xs, y, col)
	_draw_goblin_pole(img, POLE_X, FLAG_TOP - 10)
	_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Кривое древко орды: два пикселя, без копейного навершия, верх обломан
static func _draw_goblin_pole(img: Image, px: int, top: int) -> void:
	for y in range(top, H):
		var off: int = 1 if (y / 23) % 2 == 1 else 0
		for x in range(px + off, px + off + 2):
			img.set_pixel(x, y, GOB_POLE_DARK if x == px + off + 1 else GOB_POLE)

## ── РВАНЫЙ ШТАНДАРТ ОРДЫ (легенда орды и Свинобосс) ──────────────────────
## Ось древка — ELITE_POLE_X (сдвиг над бойцом — elite_pole_offset_px, как у
## бордового штандарта). steps — ступень шевронов 1-9 (0 — без знаков),
## boss — знамя полководца: крупнее рвань и больше дыр, знаков нет
const GOB_RAG_KEY := 6000
const RAG_BAR_Y := 17
const RAG_TOP := 19
const RAG_H := 68
const RAG_HALF_TOP := 19
const RAG_HALF_BOT := 12
const RAG_TATTER := 10

static func goblin_rag_texture(steps: int, white: bool = false, boss: bool = false) -> Texture2D:
	var st: int = clampi(steps, 0, 9)
	var key: int = GOB_RAG_KEY + st * 10 + (1 if white else 0) + (2 if boss else 0)
	if _cache.has(key):
		return _cache[key]
	var cloths: Array = GOB_CLOTHS_WHITE if white else GOB_CLOTHS
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4243 + (17 if boss else 0)
	var cx: int = ELITE_POLE_X + POLE_W / 2
	# Древко — под полотнищем: видно над перекладиной и под бахромой
	_draw_goblin_pole(img, ELITE_POLE_X, RAG_BAR_Y - 9)
	# Навершие — загнутый крючок
	img.set_pixel(ELITE_POLE_X + 2, RAG_BAR_Y - 10, GOB_POLE)
	img.set_pixel(ELITE_POLE_X + 2, RAG_BAR_Y - 11, GOB_POLE)
	img.set_pixel(ELITE_POLE_X + 1, RAG_BAR_Y - 12, GOB_POLE)
	var y_end: int = RAG_TOP + RAG_H
	# Полотнище — трапеция, сужается книзу, бока волнятся
	for y in range(RAG_TOP, y_end + 1):
		var t: float = float(y - RAG_TOP) / float(RAG_H)
		var half: float = lerpf(float(RAG_HALF_TOP), float(RAG_HALF_BOT), t)
		var wl: int = int(round(sin(float(y) * 0.23) * 1.3))
		var wr: int = int(round(sin(float(y) * 0.19 + 2.0) * 1.3))
		var x0: int = cx - int(half) + wl
		var x1: int = cx + int(half) + wr
		for x in range(x0, x1 + 1):
			var cloth: Color = cloths[((x - x0) / 7) % cloths.size()]
			var edge: bool = x <= x0 or x >= x1
			img.set_pixel(x, y, cloth.darkened(0.28) if edge else cloth)
	# Рваный низ: язычки разной длины, местами нитка через пиксель
	var hb: int = RAG_HALF_BOT + 1
	var tat: int = RAG_TATTER + (4 if boss else 0)
	for x in range(cx - hb, cx + hb + 1):
		var ln: int = rng.randi_range(0, tat)
		if rng.randf() < 0.25:
			ln = 0
		var thin: bool = rng.randf() < 0.3
		var cloth2: Color = cloths[((x - cx + hb) / 7) % cloths.size()]
		for y in range(y_end + 1, y_end + 1 + ln):
			if thin and (y % 2 == 0):
				continue
			img.set_pixel(x, y, cloth2.darkened(0.18))
	# Дыры в нижней половине и укусы по краю
	var holes: int = 9 if boss else 5
	for _h in range(holes):
		var hx: int = cx + rng.randi_range(-RAG_HALF_BOT + 2, RAG_HALF_BOT - 5)
		var hy: int = RAG_TOP + RAG_H / 2 + rng.randi_range(0, RAG_H / 2 - 2)
		# Не меньше 3×3: обводка заливает край дыры, сквозной остаётся середина
		var hw: int = rng.randi_range(3, 4)
		var hh: int = rng.randi_range(3, 4)
		for yy in range(hy, hy + hh):
			for xx in range(hx, hx + hw):
				img.set_pixel(xx, yy, Color(0, 0, 0, 0))
	for _b in range(4 if boss else 2):
		var by: int = RAG_TOP + rng.randi_range(RAG_H / 3, RAG_H - 4)
		var side: int = -1 if rng.randf() < 0.5 else 1
		var half2: int = int(lerpf(float(RAG_HALF_TOP), float(RAG_HALF_BOT), float(by - RAG_TOP) / float(RAG_H)))
		for yy in range(by, by + 3):
			for d in range(0, 3):
				img.set_pixel(cx + side * (half2 + 1 - d), yy, Color(0, 0, 0, 0))
	# Перекладина поверх верха полотнища
	for y in range(RAG_BAR_Y, RAG_BAR_Y + 2):
		for x in range(cx - RAG_HALF_TOP - 4, cx + RAG_HALF_TOP + 5):
			img.set_pixel(x, y, GOB_POLE if y == RAG_BAR_Y else GOB_POLE_DARK)
	# Шевроны «^» по центру полотнища
	if st > 0 and not white and not boss:
		var n: int = (st - 1) % 3 + 1
		var col: Color = goblin_mark_color(st)
		var hwc: int = 9
		var y0c: int = RAG_TOP + 14
		for k in range(n):
			var yt: int = y0c + k * 8
			for dx in range(-hwc, hwc + 1):
				var yy2: int = yt + absi(dx) * 2 / 3
				for t2 in range(3):
					img.set_pixel(cx + dx, yy2 + t2, col)
	_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

# ═════════════════════════════════════════════════════════════════════════════
# ЛЕГЕНДАРНЫЕ: ЗОЛОТОЙ КВАДРАТ И ХВОСТ ПРЕСТИЖА (ТЗ 25.10 → 27.10 → 28.10.2026)
# ═════════════════════════════════════════════════════════════════════════════
## Иерархия знамён (ТЗ 28.10.2026, письмо о знамёнах), строго и без лишнего:
##   1. базовые ступени — вымпелы шкалы VET_BANNER_TIERS (красные → синие);
##   2. легенда — ЧИСТЫЙ золотой квадрат, под ним ничего;
##   3. престиж легенды 1-3 (опыт сверх легенды) — под золотом красный хвост
##      СРАЗУ с одной белой лычкой, затем две и три;
##   4. престиж 4-6 — синий хвост с 1-3 лычками.
## Бордовый мини-флажок штандарта игрока под золотом («бордовый отросток»
## на скриншоте владельца) и цветные мини-флажки СНЯТЫ ВОВСЕ: штандарт игрока
## виден на бордовом полотнище до легенды (_draw_elite_rank), а уровень
## элиты у легендарного отряда живёт только в записи (аура реликвии).
## Один флагшток на отряд, как и прежде
const LEGEND_KEY_BASE := 4000

## flags — ступень престижа легенды (GameManager.squad_legend_marks, 0..LEGEND_EXTRA_MAX)
static func legend_texture(flags: int, side: int = 0) -> Texture2D:
	var f: int = clampi(flags, 0, _UCfg.LEGEND_EXTRA_MAX)
	var key: int = LEGEND_KEY_BASE + f + side * SIDE_KEY
	if _cache.has(key):
		return _cache[key]
	# Вымпел той же формы, что у ступеней 1-9: поле стороны в фиолетовой
	# рамке, оранжевые лычки — одна за легенду и по одной за ступень престижа
	# (ТЗ 31.10.2026; золотого флага больше нет)
	var tier: Dictionary = _UCfg.veteran_banner_tier(_UCfg.VET_BANNER_TIERS.size())
	tier["chevrons"] = int(tier.get("chevrons", 1)) + f
	_side_tier(tier, side)
	var tex := _render(tier)
	_cache[key] = tex
	return tex

## ── ЗНАМЯ СВИНОБОССА (ТЗ 28.10.2026 → 29.10.2026) ─────────────────────────
## Рваный зелёный штандарт орды (goblin_rag_texture, boss = true): рвань
## длиннее и дыр больше, знаков нет. Цифра и синий хвост сняты по скетчу

## Знамя Свинобосса — общая шкала (ТЗ 30.10.2026): синий вымпел с лычками
## ранга его отряда, не ниже BOSS_BANNER_MIN_TIER (три белые); легенда — золото
static func boss_texture(level: int = 0) -> Texture2D:
	# Орда — только зелёные знамёна (ТЗ 31.10.2026): язычки ранга отряда
	if _OptB.faction_banners:
		return goblin_tongue_texture(maxi(level, BOSS_BANNER_MIN_TIER))
	if level >= _UCfg.LEGEND_TIER:
		return legend_texture(0)
	return texture_for(maxi(level, BOSS_BANNER_MIN_TIER))

const BOSS_BANNER_MIN_TIER := 3

static func clear_cache() -> void:
	_cache.clear()

## ── БЕЛЫЙ ФЛАГ ПАНИКИ ──────────────────────────────────────────────────────
## Тот же холст, то же древко, тот же вымпел — и НИ ОДНОЙ лычки. Рисуется тем
## же кодом, что и боевые знамёна, ради одного: белый флаг обязан висеть на
## той же высоте, той же ширины и с тем же колыханием, что и знамя
## ветеранства. Своя реализация «картинки над отрядом» разъехалась бы с ними
## при первой же правке PIXEL_SIZE.
##
## Ключ кэша отрицательный: пространство ключей у грейдов положительное, и так
## флаг физически не может затереть чей-то грейд
const WHITE_FLAG_KEY := -1

static func white_flag_texture() -> Texture2D:
	if _cache.has(WHITE_FLAG_KEY):
		return _cache[WHITE_FLAG_KEY]
	# Форма — вымпел (самый узнаваемый силуэт), полотнище белое, лычек нет:
	# «сдаюсь» читается отсутствием любых знаков различия
	var tier: Dictionary = {
		"shape": _UCfg.BANNER_PENNANT,
		"cloth": Color(0.95, 0.95, 0.92),
		"chevrons": 0,
		"chevron_dir": 1,
		"tip": false,
	}
	var tex := _render(tier)
	_cache[WHITE_FLAG_KEY] = tex
	return tex

# ═════════════════════════════════════════════════════════════════════════════
# РИСОВАНИЕ
# ═════════════════════════════════════════════════════════════════════════════
## ── ФЛАЖОК ВЛАДЕЛЬЦА (золотой рудник, 10.09.2026) ──────────────────────────
## Вымпел цвета стороны без лычек и наконечника — «как знамя ветерана, но без
## шевронов». Ключ кэша — цвет целым числом: с уровнями 1-7 и −1 не
## пересекается (у непрозрачного цвета старший байт 255)
static func faction_flag_texture(cloth: Color) -> Texture2D:
	var key: int = int(cloth.to_rgba32())
	if _cache.has(key):
		return _cache[key]
	var tier: Dictionary = {
		"shape": _UCfg.BANNER_PENNANT,
		"cloth": cloth,
		"chevrons": 0,
		"chevron_dir": 1,
		"tip": false,
	}
	var tex := _render(tier)
	_cache[key] = tex
	return tex

static func _render(tier: Dictionary) -> ImageTexture:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	# Прозрачный холст: create_empty не обещает очистку
	img.fill(Color(0, 0, 0, 0))

	var shape: int = int(tier.get("shape", _UCfg.BANNER_PENNANT))
	var cloth: Color = tier.get("cloth", Color.RED) as Color

	match shape:
		_UCfg.BANNER_STANDARD:
			_draw_standard(img, cloth, tier)
		_UCfg.BANNER_GUIDON:
			_draw_guidon(img, cloth, tier)
		_:
			_draw_pennant(img, cloth, tier)

	# Древко ПОСЛЕ полотнища: оно должно лежать поверх его левого края, иначе
	# на стыке видна ступенька, и знамя выглядит приклеенным сбоку, а не
	# насаженным на пику
	_draw_pole(img)
	_outline(img)
	return ImageTexture.create_from_image(img)

## Древко с копейным навершием (см. POLE_COL)
static func _draw_pole(img: Image) -> void:
	for y in range(POLE_TOP, H):
		for x in range(POLE_X, POLE_X + POLE_W):
			# Правый столбец — тень: без неё древко читается плоской полоской
			img.set_pixel(x, y, POLE_SHADE if x == POLE_X + POLE_W - 1 else POLE_COL)
	# Навершие: лист копья — расширяется от острия и снова сужается к древку
	var cx: int = POLE_X + POLE_W / 2
	for y in range(0, TIP_H):
		var t: float = float(y) / float(maxi(TIP_H - 1, 1))
		# Половина ширины: 0 у острия, TIP_HALF на трети высоты, 1 у древка
		var half: int
		if t < 0.45:
			half = int(round(lerpf(0.0, float(TIP_HALF), t / 0.45)))
		else:
			half = int(round(lerpf(float(TIP_HALF), 1.0, (t - 0.45) / 0.55)))
		for x in range(cx - half, cx + half + 1):
			if x >= 0 and x < W:
				img.set_pixel(x, y, POLE_COL if x < cx + half else POLE_SHADE)

## ── ВЫМПЕЛ (грейды 1-3): ЧИСТЫЙ ТРЕУГОЛЬНИК ───────────────────────────────
## ЗДЕСЬ БЫЛ «ВЫМПЕЛ С ГОРИЗОНТАЛЬНОЙ ВЕРХНЕЙ КРОМКОЙ»: сужалась только нижняя
## кромка, верхняя шла прямо до самого конца. На экране это читалось не
## треугольником, а флагом с ОБРЕЗАННЫМ краем — ровно так владелец и описал
## порок («исправить обрезку края»).
##
## Теперь сходятся ОБЕ кромки: верхняя опускается, нижняя поднимается, и обе
## встречаются в острие посередине высоты. Это тот самый треугольный вымпел,
## что нарисован в эталоне
static func _draw_pennant(img: Image, cloth: Color, tier: Dictionary) -> void:
	var x1: int = FLAG_X0 + FLAG_LEN
	var mid: float = float(FLAG_TOP) + float(FLAG_H) * 0.5
	var white_from: int = x1 - int(round(float(FLAG_LEN) * TIP_FRAC))
	var tipped: bool = bool(tier.get("white_tip", false))
	for x in range(FLAG_X0, x1 + 1):
		var t: float = float(x - FLAG_X0) / float(maxi(FLAG_LEN, 1))
		var y_top: int = int(round(lerpf(float(FLAG_TOP), mid, t)))
		var y_bot: int = int(round(lerpf(float(FLAG_TOP + FLAG_H), mid, t)))
		var col: Color = cloth
		if tipped and x >= white_from:
			col = _UCfg.BANNER_TIP_COLOR
		for y in range(y_top, y_bot + 1):
			img.set_pixel(x, y, col)
	if tier.has("edge"):
		_frame_cloth(img, tier["edge"] as Color, FLAG_X0 + POLE_W, FLAG_TOP, x1, FLAG_TOP + FLAG_H)
	_draw_chevrons(img, tier, FLAG_TOP, FLAG_H)

## Рамка полотнища в FRAME_PX пикселей: ткань, у которой в этом радиусе есть
## пустота, — край (фиолетовая рамка легенды, ТЗ 31.10.2026)
const FRAME_PX := 2

static func _frame_cloth(img: Image, col: Color, xa: int, ya: int, xb: int, yb: int) -> void:
	var src := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, img.get_data())
	for y in range(ya, yb + 1):
		for x in range(xa, xb + 1):
			if src.get_pixel(x, y).a <= 0.5:
				continue
			var edge := false
			for dy in range(-FRAME_PX, FRAME_PX + 1):
				for dx in range(-FRAME_PX, FRAME_PX + 1):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or nx >= W or ny < 0 or ny >= H or src.get_pixel(nx, ny).a <= 0.5:
						edge = true
						break
				if edge:
					break
			if edge:
				img.set_pixel(x, y, col)

## ── ГВИДОН, «ЛАСТОЧКИН ХВОСТ» (грейды 4-6) ────────────────────────────────
## Прямоугольник, из свободного края которого вырезан клин. Клин делается
## ВЫРЕЗОМ из готового прямоугольника, а не двумя треугольниками: так у обоих
## хвостов гарантированно одна длина и одна толщина
static func _draw_guidon(img: Image, cloth: Color, tier: Dictionary) -> void:
	var x1: int = FLAG_X0 + FLAG_LEN
	var white_from: int = x1 - int(round(float(FLAG_LEN) * TIP_FRAC))
	var tipped: bool = bool(tier.get("white_tip", false))
	var mid: float = float(FLAG_TOP) + float(FLAG_H) * 0.5
	for x in range(FLAG_X0, x1 + 1):
		var col: Color = cloth
		if tipped and x >= white_from:
			col = _UCfg.BANNER_TIP_COLOR
		# Глубина выреза растёт от нуля на границе клина до половины высоты
		# у самого края
		var cut: float = 0.0
		if x > x1 - NOTCH:
			cut = float(FLAG_H) * 0.5 * float(x - (x1 - NOTCH)) / float(maxi(NOTCH, 1))
		for y in range(FLAG_TOP, FLAG_TOP + FLAG_H + 1):
			if absf(float(y) - mid) < cut:
				continue
			img.set_pixel(x, y, col)
	_draw_chevrons(img, tier, FLAG_TOP, FLAG_H)

## ── ШТАНДАРТ (грейд 7) ─────────────────────────────────────────────────────
## Полотнище, золотая кайма, золотая бахрома снизу и герб посередине.
## Лычек здесь НЕТ намеренно: седьмой грейд — не «две лычки и ещё что-то», а
## другой предмет. Лычки на нём читались бы как продолжение шкалы, а шкала
## кончилась
static func _draw_standard(img: Image, cloth: Color, _tier: Dictionary) -> void:
	var x1: int = FLAG_X0 + STD_LEN
	var y1: int = STD_TOP + STD_H
	# Кайма, бахрома и герб: по умолчанию золото; у золотого полотнища
	# легендарных (ТЗ 25.10.2026) — тёмное золото из tier["edge"], иначе
	# кайма слилась бы с тканью
	var gold: Color = _tier.get("edge", _UCfg.BANNER_GOLD) as Color
	for x in range(FLAG_X0, x1 + 1):
		for y in range(STD_TOP, y1 + 1):
			# Кайма в два пикселя по всем сторонам
			var edge: bool = x <= FLAG_X0 + 1 or x >= x1 - 1 \
				or y <= STD_TOP + 1 or y >= y1 - 1
			img.set_pixel(x, y, gold if edge else cloth)
	# Бахрома: зубцы через один, свисают ниже полотнища
	for x in range(FLAG_X0, x1 + 1):
		if (x - FLAG_X0) % 3 == 0:
			continue
		for y in range(y1 + 1, y1 + 1 + FRINGE):
			if y < H:
				img.set_pixel(x, y, gold)
	# Герб по центру полотнища, крупнее вместе с ним (см. EMBLEM_SCALE)
	_draw_emblem(img, (FLAG_X0 + x1) / 2, (STD_TOP + y1) / 2, gold)

## Маска герба, растянутая в EMBLEM_SCALE раз по обеим осям. Растягиваем
## ПОВТОРОМ ПИКСЕЛЯ, а не интерполяцией: весь арт игры пиксельный, и сглаженная
## корона рядом со ступенчатым копейщиком читалась бы чужеродной наклейкой
static func _draw_emblem(img: Image, cx: int, cy: int, col: Color) -> void:
	var rows: int = EMBLEM.size()
	if rows == 0:
		return
	var cols: int = String(EMBLEM[0]).length()
	var k: int = maxi(EMBLEM_SCALE, 1)
	var x0: int = cx - (cols * k) / 2
	var y0: int = cy - (rows * k) / 2
	for r in range(rows):
		var line: String = EMBLEM[r]
		for c in range(mini(cols, line.length())):
			if line[c] != "#":
				continue
			for dy in range(k):
				for dx in range(k):
					var x: int = x0 + c * k + dx
					var y: int = y0 + r * k + dy
					if x >= 0 and x < W and y >= 0 and y < H:
						img.set_pixel(x, y, col)

## ── ЛЫЧКИ ──────────────────────────────────────────────────────────────────
## Шеврон рисуется по строкам: на строке dy от середины остриё отстоит от базы
## на (половина высоты − |dy|). Направление задаёт конфиг: у красных вымпелов
## лычки смотрят В ПОЛЁТ (`>`), у синих гвидонов — К ДРЕВКУ (`<`).
##
## ЦВЕТ ЛЫЧКИ БЕРЁТСЯ ПО ФОНУ, А НЕ КОНСТАНТОЙ: на белом наконечнике белая
## лычка исчезла бы. Пиксель кладём только туда, где уже есть полотнище, —
## иначе шеврон торчал бы в воздух за краем вымпела
static func _draw_chevrons(img: Image, tier: Dictionary, top: int, h: int) -> void:
	var n: int = int(tier.get("chevrons", 0))
	if n <= 0:
		return
	var dir: int = int(tier.get("chevron_dir", 1))
	var col: Color = tier.get("chevron_col", _UCfg.BANNER_CHEVRON) as Color
	var mid: int = top + h / 2
	var half: int = CHEV_H / 2
	# ── ОТСТУП ОТ ДРЕВКА ОДИН И ТОТ ЖЕ, КУДА БЫ ЛЫЧКА НИ СМОТРЕЛА ──────────
	# База — это ОСНОВАНИЕ шеврона, а остриё уходит от неё на `half` в сторону
	# `dir`. У красных (dir = +1) остриё идёт ВПРАВО, и левый край шеврона
	# совпадает с базой. У синих (dir = -1) остриё идёт ВЛЕВО — то есть на
	# `half` ближе к древку, и при общей базе шеврон упирался в древко и
	# срезался проверкой «только по полотнищу». Ровно это владелец и увидел на
	# «ласточкиных хвостах».
	# Сдвигаем базу левосмотрящих на `half` вправо: теперь у обоих родов знамён
	# лычки стоят на одинаковом отступе от древка и центрированы по полотнищу
	var lead: int = FLAG_X0 + CHEV_X0
	if dir < 0:
		lead += half
	# Кант лычки (красная на красном поле): тот же шеврон шире на пиксель
	# со всех сторон, светлым — под основной
	if tier.has("rim"):
		var rim: Color = tier["rim"] as Color
		for k in range(n):
			var rb: int = lead + k * CHEV_STEP
			for dy in range(-half - 1, half + 2):
				var rr: int = half - absi(dy)
				var rx: int = rb + dir * rr
				for t in range(-1, CHEV_T + 1):
					var rpx: int = rx + dir * t
					var ry: int = mid + dy
					if rpx < 0 or rpx >= W or ry < 0 or ry >= H:
						continue
					if img.get_pixel(rpx, ry).a <= 0.5:
						continue
					img.set_pixel(rpx, ry, rim)
	for k in range(n):
		var base: int = lead + k * CHEV_STEP
		for dy in range(-half, half + 1):
			var reach: int = half - absi(dy)
			var x: int = base + dir * reach
			var y: int = mid + dy
			for t in range(CHEV_T):
				var px: int = x + dir * t
				if px < 0 or px >= W or y < 0 or y >= H:
					continue
				# Только по полотнищу (см. шапку)
				if img.get_pixel(px, y).a <= 0.5:
					continue
				img.set_pixel(px, y, col)

## ── ОБВОДКА В ОДИН ПИКСЕЛЬ ─────────────────────────────────────────────────
## Знамя висит над зелёной травой, над тёмной кроной и над светлым шлемом —
## то есть на любом фоне, какой есть в игре. Без канта
## синий гвидон пропадает в тени леса, а белый наконечник — на светлом.
##
## Считается ПОСТ-ПРОХОДОМ по готовой картинке, а не рисуется вместе с каждой
## фигурой: фигур четыре (древко, навершие, полотнище, бахрома), и обводить
## каждую по отдельности значило бы получить кант ВНУТРИ знамени на их стыках
static func _outline(img: Image) -> void:
	var src := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8,
		img.get_data())
	for y in range(H):
		for x in range(W):
			if src.get_pixel(x, y).a > 0.5:
				continue
			var near: bool = false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or nx >= W or ny < 0 or ny >= H:
						continue
					if src.get_pixel(nx, ny).a > 0.5:
						near = true
						break
				if near:
					break
			if near:
				img.set_pixel(x, y, OUTLINE)
