extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ЗНАМЁНА ВЕТЕРАНСТВА: КАРТИНКА СТРОИТСЯ КОДОМ, А НЕ ЛЕЖИТ В АССЕТАХ
## ═══════════════════════════════════════════════════════════════════════════
## Готовых знамён в ассет-паке нет — ровно та же ситуация, что была со звездой
## ветерана (см. VeterancyStar.gd), и решается она так же: рисуем сами.
##
## НО РИСУЕМ НЕ ГЕОМЕТРИЕЙ, А ТЕКСТУРОЙ, и это единственное принципиальное
## отличие от звезды. Причина в заказе: упавшее знамя обязано ЗАПЕКАТЬСЯ В ТОТ
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

## Обводка. Тот же тёмно-синеватый, что у канта звезды: он подобран под палитру
## арта и не выглядит нарисованным поверх чёрным маркером
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
static func texture_for(level: int) -> Texture2D:
	if level <= 0:
		return null
	var tier: Dictionary = _UCfg.veteran_banner_tier(level)
	if tier.is_empty():
		return null
	var key: int = int(tier.get("key", level))
	if _cache.has(key):
		return _cache[key]
	var tex := _render(tier)
	_cache[key] = tex
	return tex

## Сбросить кэш (стенды, смена партии). В игре не нужен: картинки постоянны
static func clear_cache() -> void:
	_cache.clear()

# ═════════════════════════════════════════════════════════════════════════════
# РИСОВАНИЕ
# ═════════════════════════════════════════════════════════════════════════════
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
	_draw_chevrons(img, tier, FLAG_TOP, FLAG_H)

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
	var gold: Color = _UCfg.BANNER_GOLD
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
	var col: Color = _UCfg.BANNER_CHEVRON
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
## ровно тот же набор фонов, ради которого обведена звезда ветерана. Без канта
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
