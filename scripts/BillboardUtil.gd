extends RefCounted
## Фабрика материалов «цилиндрического» билборда (см. shaders/cyl_billboard.gdshader):
## спрайт поворачивается к ПОЗИЦИИ камеры вокруг своей собственной оси Y.
## Используется деревьями, пнями, кустами и прочими декорациями вместо
## BILLBOARD_FIXED_Y, который выравнивал всё параллельно экрану («пропеллер»).
## Файл намеренно без class_name — подключать через preload.

const _SHADER := preload("res://shaders/cyl_billboard.gdshader")

# ─────────────────────────────────────────────────────────────────────────────
# ПРИПЛЮСНУТОСТЬ ВСЕГО СПРАЙТОВОГО: ОТКУДА БЕРЁТСЯ И ЧЕМ ЛЕЧИТСЯ
#
# Камера ортографическая и наклонена на RTSCamera.FIXED_PITCH = 45° к горизонту.
# Все спрайты проекта — билборды С МИРОВОЙ ОСЬЮ Y (см. vertex() ниже и
# shaders/mm_unit_sprite.gdshader): квад доворачивается к камере только вокруг
# вертикали, а сама вертикаль остаётся мировой. При таком наклоне метр ВЫСОТЫ
# занимает на экране cos(45°) = 0.707 метра, а метр ШИРИНЫ — целый метр.
# То есть весь спрайтовый мир — бойцы, постройки, деревья, кусты — рисуется
# ужатым по вертикали почти на треть. Это и есть «приплюснутость».
#
# Для НАСТОЯЩЕЙ трёхмерной геометрии такое сжатие правильно: так и выглядит
# предмет, если смотреть на него сверху под 45°. Но арт нарисован уже В РАКУРСЕ
# (фигуры видно «в три четверти»), то есть перспектива в него встроена
# художником — и наклон камеры накладывает её ВТОРОЙ раз.
#
# Лечится компенсацией: высота спрайта умножается на 1/cos(pitch), после чего
# НА ЭКРАНЕ картинка имеет ровно те пропорции, что и в PNG. Ширины и пятна на
# земле (коллизия, кольца выделения, габариты построек) это не касается вовсе —
# они горизонтальные и не сжимались.
#
# ЧИСЛО ВЫВОДИТСЯ ИЗ УГЛА КАМЕРЫ, А НЕ ПОДБИРАЕТСЯ: сменят наклон в
# RTSCamera.FIXED_PITCH — компенсация поедет за ним сама.
# ─────────────────────────────────────────────────────────────────────────────
static var V_STRETCH: float = 1.0 / maxf(cos(deg_to_rad(RTSCamera.FIXED_PITCH)), 0.05)

# Кэш «текстура → число кадров»: скан альфы делается ОДИН раз на путь,
# а не на каждое из сотен деревьев
static var _fc_cache: Dictionary = {}

## Число кадров в горизонтальном спрайт-шите.
## ВАЖНО: кадры НЕ всегда квадратные. Tree1/Tree2 — 1536x256, но кадров 8
## (ширина кадра 192): деление по квадрату давало 6, и в кадр попадала
## полоса соседнего дерева — «срезанная ёлочка». Поэтому основной способ —
## посчитать острова непрозрачных столбцов; квадратная эвристика — запасной.
static func frame_count(tex: Texture2D) -> int:
	var key: String = tex.resource_path
	if key.is_empty():
		return _frame_count_by_ratio(tex)
	if _fc_cache.has(key):
		return _fc_cache[key]
	var n := _detect_frame_count(tex)
	_fc_cache[key] = n
	return n

## Запасной способ: кадры квадратные (ширина / высота = число кадров)
static func _frame_count_by_ratio(tex: Texture2D) -> int:
	var sz := tex.get_size()
	if sz.y <= 0.0:
		return 1
	var ratio := sz.x / sz.y
	var n := int(round(ratio))
	if n >= 2 and absf(ratio - float(n)) < 0.05:
		return n
	return 1

## Считает «острова» непрозрачных столбцов: между кадрами шита всегда есть
## полностью прозрачный зазор. Строки берём с прореживанием — столбец-зазор
## прозрачен на ВСЕХ строках, поэтому 24 выборок достаточно и скан быстрый.
static func _detect_frame_count(tex: Texture2D) -> int:
	var fallback := _frame_count_by_ratio(tex)
	var sz := tex.get_size()
	# Шит кадров — всегда ШИРОКАЯ горизонтальная лента. У почти квадратной
	# картинки (Stump*.png — 192x256) островной скан ловит разрывы внутри
	# самого рисунка и «нарезал» бы одиночный спрайт на половинки.
	if sz.y <= 0.0 or sz.x < sz.y * 1.5:
		return 1
	var img := tex.get_image()
	if img == null:
		return fallback
	if img.is_compressed():
		# detect_3d/compress_to в .import может переимпортировать текстуру
		# в VRAM-сжатие — тогда get_pixel() недоступен без распаковки
		if img.decompress() != OK:
			return fallback
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return fallback

	var row_step: int = maxi(1, h / 24)
	var islands := 0
	var in_island := false
	for x in range(w):
		var opaque := false
		var y := 0
		while y < h:
			if img.get_pixel(x, y).a > 0.02:
				opaque = true
				break
			y += row_step
		if opaque and not in_island:
			islands += 1
			in_island = true
		elif not opaque:
			in_island = false

	# Кадры одинаковой ширины: число островов обязано делить ширину нацело
	if islands >= 1 and islands <= 64 and w % islands == 0:
		return islands
	return fallback

## ═══════════════════════════════════════════════════════════════════════════
## ГДЕ ВНУТРИ КАДРА НА САМОМ ДЕЛЕ ЧТО-ТО НАРИСОВАНО
## ═══════════════════════════════════════════════════════════════════════════
## Возвращает прямоугольник непрозрачной части ПЕРВОГО кадра в долях кадра
## (0..1 по обеим осям, начало отсчёта — левый верхний угол, как у UV).
##
## Нужен рамке выделения постройки: габарит из unit_stats_config («коробка»)
## описывает пятно на земле для коллизии и размещения, а НЕ то, что видит
## игрок. У замка коробка 8×8 м при рисунке 8.6×5.7 м — рамка по коробке
## уходила на 43% высоты здания вперёд от его стены и на столько же врезалась
## внутрь. Рамка обязана обводить РИСУНОК.
##
## Скан прореженный (шаг 2 пикселя) и кэшируется по пути ресурса: текстур
## построек единицы, и считается это один раз за запуск.
static var _rect_cache: Dictionary = {}

const _OPAQUE_STEP := 2       # шаг прореживания скана, пиксели
const _OPAQUE_A    := 0.05    # что считать непрозрачным

static func opaque_rect(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	var key: String = tex.resource_path
	if not key.is_empty() and _rect_cache.has(key):
		return _rect_cache[key]
	var r := _scan_opaque_rect(tex)
	if not key.is_empty():
		_rect_cache[key] = r
	return r

static func _scan_opaque_rect(tex: Texture2D) -> Rect2:
	var full := Rect2(0.0, 0.0, 1.0, 1.0)
	var img := tex.get_image()
	if img == null:
		return full
	if img.is_compressed() and img.decompress() != OK:
		return full
	var fw: int = img.get_width() / maxi(frame_count(tex), 1)
	var h: int = img.get_height()
	if fw <= 0 or h <= 0:
		return full
	var x0: int = fw
	var x1: int = -1
	var y0: int = h
	var y1: int = -1
	var y: int = 0
	while y < h:
		var x: int = 0
		while x < fw:
			if img.get_pixel(x, y).a > _OPAQUE_A:
				if x < x0: x0 = x
				if x > x1: x1 = x
				if y < y0: y0 = y
				if y > y1: y1 = y
			x += _OPAQUE_STEP
		y += _OPAQUE_STEP
	if x1 < x0 or y1 < y0:
		return full        # кадр пуст — считаем, что занят целиком
	# Шаг прореживания мог проскочить крайний столбец/строку: расширяем на него
	x0 = maxi(x0 - _OPAQUE_STEP, 0)
	y0 = maxi(y0 - _OPAQUE_STEP, 0)
	x1 = mini(x1 + _OPAQUE_STEP, fw - 1)
	y1 = mini(y1 + _OPAQUE_STEP, h - 1)
	return Rect2(
		float(x0) / float(fw), float(y0) / float(h),
		float(x1 - x0 + 1) / float(fw), float(y1 - y0 + 1) / float(h))

## Пропорции ОДНОГО кадра (ширина/высота) — для расчёта размера квада
static func frame_aspect(tex: Texture2D) -> float:
	var sz := tex.get_size()
	if sz.y <= 0.0:
		return 1.0
	return (sz.x / float(frame_count(tex))) / sz.y

static func make_material(tex: Texture2D, modulate: Color = Color.WHITE, scissor: float = 0.5, fps: float = 6.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("modulate", modulate)
	mat.set_shader_parameter("alpha_scissor", scissor)
	# НАЗЕМНАЯ ДЕКОРАЦИЯ ВСЕГДА ПОД НОГАМИ БОЙЦА. Этой функцией строятся деревья,
	# кусты, пни и куски руды/камня — все они держат приоритет 0 (значение по
	# умолчанию), а боец рисуется приоритетом 1 (см. FarUnitRenderer._get_or_make_bucket).
	# Без явного числа тут оба билборда сортировались бы по дистанции камере до
	# СВОЕГО начала координат, и куст у самых ног иногда «выигрывал» — боец
	# казался утопленным в декорацию по колено
	mat.render_priority = 0
	# Компенсация наклона камеры (см. V_STRETCH выше). Растягивает шейдер, а НЕ
	# сам квад: мировые габариты остаются честными, и стенд qa_aspect по-прежнему
	# сверяет размер квада с пропорциями картинки один к одному
	mat.set_shader_parameter("v_stretch", V_STRETCH)
	var fc := frame_count(tex)
	mat.set_shader_parameter("frame_count", float(fc))
	mat.set_shader_parameter("frame_fps", fps if fc > 1 else 0.0)
	# Случайная фаза: деревья/кусты не машут листвой синхронно
	mat.set_shader_parameter("frame_phase", randf() * float(maxi(fc, 1)))
	return mat

# ─────────────────────────────────────────────────────────────────────────────
# ВЕТЕР В РАСТИТЕЛЬНОСТИ
#
# У Tree*.png и Bushe*.png в шите лежит ГОТОВОЕ КОЛЫХАНИЕ — 6-8 кадров, ради
# которых лента и нарисована. Проигрывание было отключено (fps = 0): при
# одинаковой скорости у всех лес шевелился одним куском, и это читалось как
# «ползающие кусты», а не как ветер.
#
# Лечится не выключением анимации, а РАЗБРОСОМ. У каждого растения свои:
#   • фаза (frame_phase) — соседи не в такт;
#   • длительность цикла — за минуту деревья расходятся окончательно, и
#     повторяющегося рисунка «волны по лесу» не возникает вовсе.
#
# Скорость задаётся ЦИКЛОМ, а не кадрами в секунду: у ленты 6 кадров и у ленты
# 8 кадров при одинаковом fps качание вышло бы разной длительности, и рощи из
# разных сортов деревьев жили бы в разном темпе.
# ─────────────────────────────────────────────────────────────────────────────

## Сколько секунд занимает ПОЛНЫЙ цикл колыхания. Разброс даёт и разную
## скорость соседям: 2.4-4.0 с — это спокойный ветер, а не трепет на буре
const WIND_CYCLE_MIN := 2.4
const WIND_CYCLE_MAX := 4.0

## Амплитуда программного изгиба (доля высоты квада) для растений БЕЗ своих
## кадров колыхания. Маленькая: крона чуть клонится, ствол стоит
const WIND_SWAY_MIN := 0.012
const WIND_SWAY_MAX := 0.028

## Материал растительности: колышется на ветру.
## Есть кадры в шите — листаем их; нет — гнём квад в шейдере.
## В обоих случаях фаза и темп у каждого растения СВОИ
static func make_wind_material(tex: Texture2D, modulate: Color = Color.WHITE,
		scissor: float = 0.5) -> ShaderMaterial:
	var fc := frame_count(tex)
	var cycle: float = randf_range(WIND_CYCLE_MIN, WIND_CYCLE_MAX)
	if fc > 1:
		# fps подбирается так, чтобы вся лента прокручивалась ровно за cycle
		var mat := make_material(tex, modulate, scissor, float(fc) / cycle)
		# frame_phase выставляет make_material случайно — этого и добиваемся
		return mat
	# Кадров колыхания нет — качаем сам квад
	var m := make_material(tex, modulate, scissor, 0.0)
	m.set_shader_parameter("sway_amount", randf_range(WIND_SWAY_MIN, WIND_SWAY_MAX))
	m.set_shader_parameter("sway_speed",  TAU / cycle)
	m.set_shader_parameter("sway_phase",  randf() * TAU)
	return m

## Материал для ЗДАНИЙ: тот же шейдер, но доворот к камере выключен.
## Постройка стоит в мировых координатах намертво — при орбите камеры она
## не крутится на месте, а честно показывает свой фасад.
static func make_static_material(tex: Texture2D, modulate: Color = Color.WHITE, scissor: float = 0.5) -> ShaderMaterial:
	var mat := make_material(tex, modulate, scissor, 0.0)
	mat.set_shader_parameter("world_fixed", 1.0)
	return mat
