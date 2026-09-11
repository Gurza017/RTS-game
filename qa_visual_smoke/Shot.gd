extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СТЕНД С ВЕРДИКТОМ: ВИДЕН ЛИ ОБЪЕКТ НА ЭКРАНЕ ВООБЩЕ
## ═══════════════════════════════════════════════════════════════════════════
## ЗАЧЕМ ЗАВЕДЁН. Правка глубины спрайтов («Y-sort» по точке на земле) утопила
## всю армию в грунт — у рабочих торчали макушки, у копейщиков одни острия пик,
## — и ШЛЮЗ ИЗ ТРИДЦАТИ ПЯТИ СТЕНДОВ ОСТАЛСЯ ЗЕЛЁНЫМ. Он весь headless, а в
## headless буфер глубины не заполняется вовсе и не компилируется ни один
## шейдер; у утонувшего бойца при этом не меняется НИ ОДНО число, которое
## стенды проверяют, — та же позиция, та же строка в ядре, тот же запас жизни.
## Поломка живёт целиком во фрагментном шейдере, в переменной DEPTH.
##
## Оконные стенды поломку видели, но промолчали: все двадцать три сохраняют
## PNG и не печатают НИ ОДНОГО вердикта — судит их глаз, и только по тому, за
## чем этот глаз пришёл. Здесь вердикт есть.
##
## ── ЧТО МЕРИМ ─────────────────────────────────────────────────────────────
## ДВА СНИМКА ОДНОГО КАДРА: без объектов (фон) и с объектами. Видимая часть
## объекта — это пиксели, которые между снимками ИЗМЕНИЛИСЬ, внутри экранного
## прямоугольника его собственного квада. Так метрика не зависит ни от цвета
## травы, ни от того, что ещё стоит на карте.
##
## ВЕРДИКТА НА ОБЪЕКТ ДВА, и они ловят разное:
##   А. «НОГИ НА ЗЕМЛЕ» — где лежит НИЖНЯЯ видимая кромка силуэта относительно
##      его точки на грунте, В МЕТРАХ. Это СВОЙСТВО, а не круглое число: у
##      утонувшего копейщика кромка поднята ровно на пустое поле кадра под
##      ступнями (замер: 1.85 м), у рабочего на 0.87 м. Проверка не требует
##      никакого эталона вовсе — только проекцию его собственной точки земли.
##   Б. «СИЛУЭТ ЦЕЛ» — доля видимых пикселей от ожидаемых. Ожидание считается
##      из САМОГО СПРАЙТА: покрытие ленты умножается на экранную площадь квада.
##
## ── ПОЧЕМУ ОЖИДАНИЕ СЧИТАЕТСЯ ЧЕРЕЗ ПОКРЫТИЕ, А НЕ ЧЕРЕЗ СЧЁТ ПИКСЕЛЕЙ ─────
## Экранная площадь квада считается ПРОЕКЦИЕЙ ЕГО УГЛОВ, а не арифметикой с
## косинусами: у бойца компенсация наклона камеры вшита в размер меша, у дерева
## её делает шейдер, и вывести одну формулу на оба случая нельзя. Камера же
## знает правду про оба.
##
## Покрытие ленты — не просто «сколько непрозрачных». У бойца порог среза 0.15,
## а впечатанная в арт тень под ногами идёт ДИЗЕРОМ: её пиксели рисуются с
## вероятностью, равной их альфе (~0.27). Поэтому у бойца покрытие = СУММА
## альфы прошедших срез, а у декорации (срез 0.5, дизера нет) — их СЧЁТ.
##
## ── ОГРАНИЧЕНИЯ, О КОТОРЫХ НАДО ЗНАТЬ ─────────────────────────────────────
## Доля силуэта может выйти больше 100 %: сглаживания нет, но модель покрытия
## приблизительна. Метрика отвечает на вопрос «объект не пропал», а не «пиксель
## в пиксель» — точную кромку меряет вердикт А.
##
##   godot --path . res://qa_visual_smoke/Shot.tscn -- --out=<абс. путь без .png>

# ── Пороги ─────────────────────────────────────────────────────────────────
## Насколько нижняя видимая кромка вправе отстоять от точки на грунте, метры.
## Не ноль: впечатанная в арт тень заходит НИЖЕ ступней, а её дизер оставляет
## от неё дырявый край. Поломка, ради которой стенд заведён, даёт 0.87-1.85 м —
## на порядок больше любого такого допуска
const FOOT_TOL_M := 0.35
## Доля видимого силуэта, ниже которой объект считается пропавшим
const SILHOUETTE_MIN := 0.80
## Порог различия пикселей между фоном и кадром с объектом (сумма по каналам)
const DIFF_EPS := 0.02
## Запас вокруг экранного прямоугольника квада, пикселей. Нужен вниз: кромка
## обязана быть измерима и НИЖЕ ног, иначе «ноги утонули» не отличить от
## «ноги ровно на месте»
const RECT_PAD := 10

## Тем же способом, каким его берёт весь проект: глобального имени у него нет
const _BB = preload("res://scripts/BillboardUtil.gd")

var _out := ""
var main = null
var cam: RTSCamera = null
var _img_bg: Image = null
var _img_fg: Image = null
var _hidden: Array[Node3D] = []      # узлы и слои, которые прячем на фоне
var _unit_layers: Array[MultiMeshInstance3D] = []   # слои армии
var _veg_layers: Array[MultiMeshInstance3D] = []    # слои растительности
var _checks := 0
var _fails := 0

## Описание объекта под замером. Всё, что нужно, снимается ОДИН РАЗ, до снимков:
## после паузы дерева ничего уже не меняется
class Probe:
	var name: String = ""
	var foot: Vector3 = Vector3.ZERO      # точка на грунте под объектом
	var centre: Vector3 = Vector3.ZERO    # центр квада в мире
	var half_w: float = 0.0
	var half_h: float = 0.0               # ЭФФЕКТИВНАЯ, уже с растяжением
	var draw_bottom: float = 0.0          # мировая высота НИЖНЕЙ НАРИСОВАННОЙ кромки
	var coverage: float = 0.0             # доля покрытия ленты, 0..1
	var sheet: String = ""

func _ready() -> void:
	# СТОРОЖ. Оконный стенд, зависший в ожидании кадра, молчит и держит машину:
	# вывод в трубу буферизован и до выхода из процесса наружу не попадает
	# вовсе. Режим ALWAYS обязателен — дерево на время снимков ставится на паузу
	var t := Timer.new()
	t.wait_time = 300.0
	t.one_shot = true
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(t)
	t.timeout.connect(_on_deadline)
	t.start()
	call_deferred("_run")

func _on_deadline() -> void:
	push_error("НЕ ПРОШЛО: стенд не уложился в срок")
	print("\n=== ВИЗУАЛЬНЫЙ ДЫМ: стенд не уложился в срок, провалов: 1 ===")
	get_tree().paused = false
	get_tree().quit(2)

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

# ─────────────────────────────────────────────────────────────────────────────
# ВЕРДИКТЫ
# ─────────────────────────────────────────────────────────────────────────────
func _ok(title: String, cond: bool, detail: String) -> void:
	_checks += 1
	if cond:
		print("    [ПРОШЛО]    %-34s %s" % [title, detail])
	else:
		_fails += 1
		print("    [НЕ ПРОШЛО] %-34s %s" % [title, detail])

# ─────────────────────────────────────────────────────────────────────────────
# ПОКРЫТИЕ ЛЕНТЫ
# ─────────────────────────────────────────────────────────────────────────────
## Средняя доля покрытия ОДНОГО кадра ленты.
## dither = true — модель отрисовки бойца: пиксель, прошедший срез, рисуется с
## вероятностью, равной своей альфе (упорядоченный дизер в mm_unit_sprite).
## dither = false — декорация: прошедший срез рисуется целиком.
##
## Считается по ВСЕЙ ленте, а не по одному кадру: какой кадр показан в миг
## снимка, стенду знать неоткуда (у направленных листов копейщика sheet_frame
## всегда отвечает нулём), а между кадрами покоя разница в проценты.
## Шаг 2 по обеим осям — лента копейщика это 3840x320, полный обход всех девяти
## объектов стоил бы секунд, а доля от прореживания не меняется
func _coverage(tex: Texture2D, scissor: float, dither: bool) -> float:
	if tex == null:
		return 0.0
	var img: Image = tex.get_image()
	if img == null:
		return 0.0
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return 0.0
	var data: PackedByteArray = img.get_data()
	var sum: float = 0.0
	var n: int = 0
	var y: int = 0
	while y < h:
		var row: int = y * w
		var x: int = 0
		while x < w:
			var a: float = float(data[(row + x) * 4 + 3]) / 255.0
			if a >= scissor:
				sum += a if dither else 1.0
			n += 1
			x += 2
		y += 2
	if n == 0:
		return 0.0
	return sum / float(n)

## Доля высоты кадра от НИЗА КВАДА до самого нижнего НАРИСОВАННОГО пикселя.
##
## ЗАЧЕМ. Мерить кромку от «точки на грунте» верно только у бойца: у него
## привязка ног к земле и есть определение SPRITE_BASE_Y. У постройки и дерева
## под нарисованными стенами лежит прозрачное поле кадра, и честная нижняя
## кромка стоит ВЫШЕ грунта — замер дал замку +0.30 м при допуске 0.35, то есть
## исправный объект чуть не покраснел на пустом месте. Спрашивать надо у самого
## рисунка: где у него низ, там ему и быть
func _bottom_frac(tex: Texture2D, scissor: float) -> float:
	if tex == null:
		return 0.0
	var img: Image = tex.get_image()
	if img == null:
		return 0.0
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return 0.0
	var data: PackedByteArray = img.get_data()
	var y: int = h - 1
	while y >= 0:
		var row: int = y * w
		var x: int = 0
		while x < w:
			if float(data[(row + x) * 4 + 3]) / 255.0 >= scissor:
				return float(h - 1 - y) / float(h)
			x += 1
		y -= 1
	return 0.0

# ─────────────────────────────────────────────────────────────────────────────
# СНЯТИЕ ОПИСАНИЯ С ЖИВОГО ОБЪЕКТА
# ─────────────────────────────────────────────────────────────────────────────
## Боец. Геометрию берём ИЗ ТОГО ЖЕ МЕСТА, откуда её берёт общая отрисовка
## (Unit.sheet_frame), — иначе стенд судил бы об одном квадре, а рисовался бы
## другой. Компенсация наклона у бойца ВШИТА В РАЗМЕР МЕША, поэтому здесь она
## домножается явно (см. FarUnitRenderer._get_or_make_bucket)
func _probe_unit(u: Unit, title: String) -> Probe:
	var sf: Array = u.sheet_frame()
	if sf.is_empty():
		push_error("у %s нет ленты" % title)
		return null
	var tex: Texture2D = sf[0]
	var frames_n: int = int(sf[2])
	var px: float = sf[3]
	var base_y: float = sf[4]
	var v: float = _BB.V_STRETCH
	var fw: float = float(tex.get_width()) / float(maxi(frames_n, 1))
	var fh: float = float(tex.get_height())
	var p := Probe.new()
	p.name = title
	p.foot = u.global_position
	p.centre = u.global_position + Vector3(0.0, base_y * v, 0.0)
	p.half_w = fw * px * 0.5
	p.half_h = fh * px * v * 0.5
	p.coverage = _coverage(tex, 0.15, true)
	# ── НИЖНЮЮ КРОМКУ СУДИМ ПО ПЛОТНОМУ СИЛУЭТУ (0.5), А НЕ ПО СРЕЗУ (0.15) ──
	# Ниже ступней в арт впечатана тень — краска с альфой ~0.27, и шейдер
	# рисует её ДИЗЕРОМ, то есть примерно каждым четвёртым пикселем. Разность
	# снимков такой край ловит неохотно, и у целого бойца выходило «кромка
	# поднята на +0.30 м» на ровном месте. Порог 0.5 тень отсекает, оставляя
	# настоящие ступни
	p.draw_bottom = (p.centre.y - p.half_h) + _bottom_frac(tex, 0.5) * p.half_h * 2.0
	p.sheet = "%dx%d, кадров %d" % [int(fw), int(fh), frames_n]
	# ── ЧТО ИМЕННО ДОЕХАЛО ДО ШЕЙДЕРА ──────────────────────────────────────
	# Печатается всегда: при разборе следующей поломки глубины это первое, на
	# что надо смотреть, и добывается оно только на живой сцене
	var slot = GameManager.far_units.slot_of(u)
	if slot != null and slot.bucket != null:
		var qm := slot.bucket.mm.mesh as QuadMesh
		p.sheet += ", квад %.2fx%.2f м, base_y %.3f, foot_drop %.3f" % [
			qm.size.x, qm.size.y, slot.base_y, slot.bucket._foot]
	return p

## Декорация или постройка. Узел здесь не при чём: у постройки рисунок — свой
## MeshInstance3D, а у дерева его нет ВОВСЕ (лес рисуется общим MultiMesh
## VegetationRenderer, и узел-владелец картинки исчезает сразу после посадки).
## Общее у них одно — КВАД, лежащий низом на грунте, который растягивает
## ШЕЙДЕР от нижней кромки вверх. Его и принимаем
## `scale` — во сколько раз квад бакета растянут ТРАНСФОРМОМ ЭКЗЕМПЛЯРА. У
## постройки это единица (квад построен в метрах), а у растительности бакет
## держит квад ЕДИНИЧНОЙ ВЫСОТЫ и настоящий размер приходит масштабом слота —
## без этого дерево описывалось прямоугольником 0.75x1.00 м вместо пятиметрового,
## и «видно 388 % силуэта» было арифметикой стенда, а не картинкой
func _probe_billboard(q: QuadMesh, mat: ShaderMaterial, base: Vector3,
		scale: Vector2, title: String) -> Probe:
	if q == null or mat == null:
		push_error("у %s нет квада с шейдерным материалом" % title)
		return null
	var tex: Texture2D = mat.get_shader_parameter("albedo_tex") as Texture2D
	var vs_raw: Variant = mat.get_shader_parameter("v_stretch")
	var vs: float = float(vs_raw) if vs_raw != null else 1.0
	var sc_raw: Variant = mat.get_shader_parameter("alpha_scissor")
	var sc: float = float(sc_raw) if sc_raw != null else 0.5
	var qw: float = q.size.x * scale.x
	var qh: float = q.size.y * scale.y
	var top: float = base.y + qh * vs
	var p := Probe.new()
	p.name = title
	p.foot = base
	p.centre = Vector3(base.x, (base.y + top) * 0.5, base.z)
	p.half_w = qw * 0.5
	p.half_h = (top - base.y) * 0.5
	p.coverage = _coverage(tex, sc, false)
	p.draw_bottom = base.y + _bottom_frac(tex, sc) * p.half_h * 2.0
	p.sheet = "квад %.2fx%.2f м, растяжение %.2f" % [qw, qh, vs]
	return p

## Первый MeshInstance3D с QuadMesh в поддереве — так находится рисунок и у
## постройки (BuildingSprite), и у дерева, не завися от имён узлов
func _find_quad(n: Node) -> MeshInstance3D:
	var mi := n as MeshInstance3D
	if mi != null and mi.visible and (mi.mesh as QuadMesh) != null:
		var q := mi.mesh as QuadMesh
		if (q.material as ShaderMaterial) != null:
			return mi
	for c in n.get_children():
		var got := _find_quad(c)
		if got != null:
			return got
	return null

# ─────────────────────────────────────────────────────────────────────────────
# СНИМКИ И РАЗБОР
# ─────────────────────────────────────────────────────────────────────────────
func _grab() -> Image:
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _show_probes(on: bool) -> void:
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = on
	for l in _unit_layers:
		if is_instance_valid(l):
			l.visible = on

## Материал общего слоя (MultiMesh) или null.
##
## ШЕЙДЕР ОПОЗНАЁТСЯ ПО resource_path, А НЕ ПО ТЕКСТУ КОДА. Первая версия
## искала имя файла подстрокой в `shader.code` — и не нашла НИ ОДНОГО слоя
## армии: имя файла внутри самого файла упоминаться не обязано. Стенд честно
## отработал, ничего не спрятал, и разность двух ОДИНАКОВЫХ снимков дала
## «видно 0 px» у всех бойцов сразу — вердикт красный по неверной причине
func _layer_mat(n: Node) -> ShaderMaterial:
	var mm := n as MultiMeshInstance3D
	if mm == null or mm.multimesh == null or mm.multimesh.mesh == null:
		return null
	return mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial

func _uses_shader(sm: ShaderMaterial, path: String) -> bool:
	return sm != null and sm.shader != null and sm.shader.resource_path == path

## Слои армии и растительности. Обход идёт от КОРНЯ дерева, а не от Main:
## владелец слоёв — автозагрузка, и куда именно она их вешает, стенду знать
## незачем
func _collect_layers(n: Node) -> void:
	var sm := _layer_mat(n)
	if sm != null:
		if _uses_shader(sm, "res://shaders/mm_unit_sprite.gdshader"):
			_unit_layers.append(n as MultiMeshInstance3D)
		elif _uses_shader(sm, "res://shaders/veg_multimesh.gdshader"):
			_veg_layers.append(n as MultiMeshInstance3D)
	for c in n.get_children():
		_collect_layers(c)

## Текстура слоя растительности: по ней и опознаётся «слой моего дерева».
## Бакеты у VegetationRenderer заведены ПО ТЕКСТУРЕ, поэтому у Tree2.png свой
## слой, и в нём после чистки карты стоит ровно один экземпляр — наш
func _layer_tex_path(sm: ShaderMaterial) -> String:
	var t: Texture2D = sm.get_shader_parameter("albedo_tex") as Texture2D
	return t.resource_path if t != null else ""

func _screen_rect(p: Probe) -> Rect2i:
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var pts: Array[Vector3] = [
		p.centre + right * p.half_w + Vector3.UP * p.half_h,
		p.centre - right * p.half_w + Vector3.UP * p.half_h,
		p.centre + right * p.half_w - Vector3.UP * p.half_h,
		p.centre - right * p.half_w - Vector3.UP * p.half_h]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for w in pts:
		var s: Vector2 = cam.unproject_position(w)
		mn.x = minf(mn.x, s.x); mn.y = minf(mn.y, s.y)
		mx.x = maxf(mx.x, s.x); mx.y = maxf(mx.y, s.y)
	return Rect2i(Vector2i(int(floor(mn.x)), int(floor(mn.y))),
		Vector2i(int(ceil(mx.x - mn.x)), int(ceil(mx.y - mn.y))))

func _judge(p: Probe) -> void:
	var quad := _screen_rect(p)
	var scan := quad.grow(RECT_PAD)
	scan = scan.intersection(Rect2i(Vector2i.ZERO, _img_fg.get_size()))
	if scan.size.x <= 0 or scan.size.y <= 0:
		_ok(p.name + ": в кадре", false, "прямоугольник объекта вне экрана")
		return
	var seen := 0
	var y_bot := -1
	var x0: int = scan.position.x
	var x1: int = scan.position.x + scan.size.x
	var y0: int = scan.position.y
	var y1: int = scan.position.y + scan.size.y
	for y in range(y0, y1):
		for x in range(x0, x1):
			var a: Color = _img_bg.get_pixel(x, y)
			var b: Color = _img_fg.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > DIFF_EPS:
				seen += 1
				y_bot = y
	var expect: float = p.coverage * float(quad.size.x) * float(quad.size.y)
	var frac: float = (float(seen) / expect) if expect > 1.0 else 0.0
	# Экранных пикселей на метр ВЫСОТЫ: то же, что и наклон камеры, только
	# спрошенное у самой камеры, а не выведенное из косинуса
	var edge := Vector3(p.foot.x, p.draw_bottom, p.foot.z)
	var foot_px: Vector2 = cam.unproject_position(edge)
	var up_px: Vector2 = cam.unproject_position(edge + Vector3.UP)
	var per_m: float = maxf(absf(foot_px.y - up_px.y), 0.001)
	var lift: float = (foot_px.y - float(y_bot)) / per_m if y_bot >= 0 else INF

	print("  %-16s %s, низ рисунка на %.2f м" % [p.name, p.sheet,
		p.draw_bottom - p.foot.y])
	print("      покрытие ленты %.3f, ожидалось %d px, видно %d px"
		% [p.coverage, int(expect), seen])
	_ok(p.name + ": силуэт цел", frac >= SILHOUETTE_MIN,
		"видно %.1f%% силуэта (порог %.0f%%)" % [frac * 100.0, SILHOUETTE_MIN * 100.0])
	if y_bot < 0:
		_ok(p.name + ": низ рисунка на месте", false, "объекта на экране нет вовсе")
	else:
		_ok(p.name + ": низ рисунка на месте", absf(lift) <= FOOT_TOL_M,
			"кромка поднята на %+.2f м (допуск %.2f)" % [lift, FOOT_TOL_M])

## Один кадр: фон, объекты, вердикты
func _measure(title: String, probes: Array, centre: Vector3, tag: String) -> void:
	var lo := INF
	var hi := -INF
	var tall := 0.0
	for pr in probes:
		var p: Probe = pr
		lo = minf(lo, p.centre.x - p.half_w)
		hi = maxf(hi, p.centre.x + p.half_w)
		tall = maxf(tall, p.centre.y + p.half_h - p.foot.y)
	var width: float = hi - lo
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	# ── КАДР ОБЯЗАН ВМЕСТИТЬ И ШИРИНУ РЯДА, И САМЫЙ ВЫСОКИЙ КВАД ───────────
	# Первая версия считала только ширину, и замок (квад 7 м, растянутый до
	# 9.9) не влез в кадр высотой 9 м: у него срезало верх, а стенд посчитал
	# это потерей силуэта — 73.9 % и красный вердикт на исправном объекте.
	# Точка фокуса лежит в ЦЕНТРЕ экрана, объект стоит НАД ней, и по вертикали
	# метр мира занимает cos(45°) кадра — отсюда запас 1.7, а не 1.0
	var height: float = maxf((width + 4.0) / maxf(aspect, 0.1), tall * 1.7)
	height = maxf(height, 9.0)
	cam.jump_to(Vector3((lo + hi) * 0.5, 0.0, centre.z), height)
	await frames(4)

	print("\n── %s (кадр %.0f м по вертикали) ──" % [title, height])
	_show_probes(false)
	_img_bg = await _grab()
	_img_bg.save_png("%s_%s_bg.png" % [_out, tag])
	_show_probes(true)
	_img_fg = await _grab()
	_img_fg.save_png("%s_%s.png" % [_out, tag])
	for pr in probes:
		_judge(pr)

# ─────────────────────────────────────────────────────────────────────────────
# ПОСТАНОВКА СЦЕНЫ
# ─────────────────────────────────────────────────────────────────────────────
## Место без воды и подальше от края: лес и камни отсюда всё равно вырубаются
func _clear_spot() -> Vector3:
	for r in range(0, 70, 4):
		for a in range(0, 16):
			var ang: float = TAU * float(a) / 16.0
			var p := Vector3(cos(ang) * float(r), 0.0, sin(ang) * float(r))
			if absf(p.x) > 60.0 or absf(p.z) > 40.0:
				continue
			if main.is_water(p.x, p.z):
				continue
			# РЕКА В НИЗИНЕ (10.09.2026): зеркало воды на метр выше дна, и ряд,
			# поставленный в русло или на откос, уходит под воду. Все три ряда
			# (z ± 30) и их ширина (x ± 12) обязаны лежать вне откосов
			var wet := false
			for dz in [-30.0, 0.0, 30.0]:
				for dx in [-12.0, 0.0, 12.0]:
					if main.near_river(p.x + dx, p.z + dz, main.RIVER_BANK + 2.0):
						wet = true
					# …и вне склонов плато: на обрыве часть силуэта прячет грунт
					if main.plateau_height(p.x + dx, p.z + dz) > 0.05:
						wet = true
			if wet:
				continue
			return p
	return Vector3.ZERO

func _spawn_unit(path: String, at: Vector3, fac: int) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	if _out == "":
		_out = ProjectSettings.globalize_path("user://vsmoke")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1600, 900)

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	# ── АНИМИРОВАННЫЕ КАМНИ БРОДА ПРЯЧЕМ (09.09.2026) ──────────────────────
	# Площадка стенда стоит в центре карты, а с новой картой центр — это брод
	# с камнями, которые листают ленту (8 кадров, 6 к/с). Метрика — РАЗНОСТЬ
	# двух снимков; всё, что сменило кадр между ними, засчитывается объекту,
	# в чей экранный прямоугольник попало. Камень под квадом копейщика (у
	# того 122 px пустого поля под ступнями) давал «кромка опущена на 1.93 м»
	# на целом бойце. Стенд обязан задавать окружение сам (правило стендов)
	var rocks := main.world_root().get_node_or_null("FordRocks") as Node3D
	if rocks != null:
		rocks.visible = false
	main.set_process(false)
	cam = main.get("_camera") as RTSCamera
	if cam == null:
		push_error("камера не найдена")
		get_tree().quit(1)
		return
	cam.set_process(false)
	cam.min_height = 5.0
	cam.max_height = 200.0

	# Карту чистим: на замер идут ТОЛЬКО наши объекты, всё остальное обязано
	# уйти из кадра — иначе доля силуэта меряет чужую крону перед бойцом
	for node in get_tree().get_nodes_in_group("all_units"):
		(node as Node).queue_free()
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		(node as Node).queue_free()
	await pframes(8)

	var spot := _clear_spot()
	print("\n=== ВИЗУАЛЬНЫЙ ДЫМ: точка %s ===" % str(spot))

	# ── ТРИ РЯДА: люди, орда, декорации ────────────────────────────────────
	# Разнесены по Z, чтобы соседний ряд не попал в кадр и не перепутал разбор
	var humans: Array[Unit] = []
	var horde: Array[Unit] = []
	var step := 5.5
	var human_paths := [
		["res://scenes/units/Worker.tscn", "Рабочий"],
		["res://scenes/units/Spearman.tscn", "Копейщик"],
		["res://scenes/units/Archer.tscn", "Лучник"],
		["res://scenes/units/Warrior.tscn", "Мечник"],
		["res://scenes/units/Monk.tscn", "Монах"]]
	for i in range(human_paths.size()):
		var row: Array = human_paths[i]
		humans.append(_spawn_unit(String(row[0]),
			spot + Vector3(float(i) * step - 11.0, 0.0, 0.0), Constants.FACTION_PLAYER))
	# ГНОЛЛ ДОБАВЛЕН СПРИНТОМ 13: свой размер пикселя (GNOLL_PIXEL_SIZE) и
	# своя привязка ног по ленте — то есть ровно тот случай, который здешняя
	# метрика и ловит («низ рисунка на месте, в метрах»)
	var horde_paths := [
		["res://scenes/units/GoblinSpearman.tscn", "Гоблин"],
		["res://scenes/units/GoblinPigRider.tscn", "Кабан"],
		["res://scenes/units/Gnoll.tscn", "Гнолл"]]
	for i in range(horde_paths.size()):
		var row2: Array = horde_paths[i]
		horde.append(_spawn_unit(String(row2[0]),
			spot + Vector3(float(i) * step - 3.0, 0.0, -30.0), Constants.FACTION_GOBLIN))

	# Постройка и дерево — обычные жильцы мира, ставятся тем же способом, что и
	# в партии (см. SaveLoadManager._restore_buildings и Main._spawn_tree_cluster)
	var keep := Castle.new()
	keep.faction = Constants.FACTION_PLAYER
	main.world_add(keep)
	var kx: float = spot.x - 8.0
	var kz: float = spot.z + 30.0
	keep.global_position = Vector3(kx, GameManager.get_terrain_height(kx, kz), kz)
	var tree := ResourceNode.new()
	tree.resource_type = Constants.RESOURCE_WOOD
	tree.remaining = 600.0
	tree.tree_variant = 2
	main.world_add(tree)
	var tx: float = spot.x + 9.0
	var tz: float = spot.z + 30.0
	tree.global_position = Vector3(tx, GameManager.get_terrain_height(tx, tz), tz)

	await pframes(20)
	await frames(6)
	# Замок мог успеть выпустить рабочих: на замер идут только наши
	for node in get_tree().get_nodes_in_group("all_units"):
		var u := node as Unit
		if u == null:
			continue
		if not humans.has(u) and not horde.has(u):
			u.queue_free()
	await pframes(6)
	await frames(4)

	# ── ПАУЗА ДЕРЕВА: дальше ничего не шевелится ───────────────────────────
	# Иначе кадр ленты, покачивание при ходьбе и разбор наложения сдвигают
	# картинку МЕЖДУ фоновым снимком и рабочим, и разность мерила бы это
	get_tree().paused = true

	_collect_layers(get_tree().root)
	print("  слоёв армии: %d, растительности: %d"
		% [_unit_layers.size(), _veg_layers.size()])
	# Стенд, которому нечего спрятать, ничего и не измерит: разность двух
	# одинаковых снимков — ноль у ЛЮБОГО объекта. Это провал самого стенда, и
	# он обязан называться своим именем, а не «боец пропал»
	_ok("Стенд: слои армии найдены", _unit_layers.size() > 0,
		"слоёв %d" % _unit_layers.size())

	# ── СЛОЙ НАШЕГО ДЕРЕВА ─────────────────────────────────────────────────
	# Растительность гасим ВСЮ, кроме него: трава стоит на земле и вправе
	# закрыть ступни, а её пиксели между снимками не меняются — то есть
	# закрытая ею часть силуэта честно пропала бы из замера
	var tree_path := "res://assets/environment/resources/Tree%d.png" % tree.tree_variant
	var tree_layer: MultiMeshInstance3D = null
	var tree_quad: QuadMesh = null
	var tree_mat: ShaderMaterial = null
	var tree_scale := Vector2.ONE
	var tree_base := tree.global_position
	for l in _veg_layers:
		var sm := _layer_mat(l)
		if tree_layer == null and _layer_tex_path(sm) == tree_path:
			tree_layer = l
			tree_quad = l.multimesh.mesh as QuadMesh
			tree_mat = sm
			# ── МАСШТАБ БЕРЁМ У САМОГО ДЕРЕВА, А НЕ ИЩЕМ В БУФЕРЕ ──────────
			# Первая версия искала «ближайший по земле экземпляр» и промахнулась:
			# освобождённые слоты бакета остаются в буфере со своими старыми
			# координатами, и ближайшим оказался чужой. Узел дерева и так держит
			# ссылку на свой слот (ResourceNode._veg_slot) — у него и спрашиваем
			var slot = tree._veg_slot
			if slot != null:
				tree_scale = Vector2(slot.scale, slot.scale)
				tree_base = Vector3(slot.pos.x,
					slot.pos.y - tree_quad.size.y * slot.scale * 0.5, slot.pos.z)
		else:
			l.visible = false
	if tree_layer != null:
		_hidden.append(tree_layer)

	var keep_quad := _find_quad(keep)
	if keep_quad != null:
		_hidden.append(keep_quad)

	var p_humans: Array = []
	for i in range(humans.size()):
		var pr := _probe_unit(humans[i], String((human_paths[i] as Array)[1]))
		if pr != null:
			p_humans.append(pr)
	var p_horde: Array = []
	for i in range(horde.size()):
		var pr2 := _probe_unit(horde[i], String((horde_paths[i] as Array)[1]))
		if pr2 != null:
			p_horde.append(pr2)
	var p_props: Array = []
	if keep_quad != null:
		var kq := keep_quad.mesh as QuadMesh
		var pk := _probe_billboard(kq, kq.material as ShaderMaterial,
			keep.global_position, Vector2.ONE, "Замок")
		if pk != null:
			p_props.append(pk)
	if tree_quad != null:
		var pt := _probe_billboard(tree_quad, tree_mat, tree_base, tree_scale, "Дерево")
		if pt != null:
			p_props.append(pt)

	await _measure("ПЕХОТА И РАБОЧИЕ", p_humans, spot, "units")
	await _measure("ОРДА", p_horde, spot + Vector3(0.0, 0.0, -30.0), "horde")
	await _measure("ПОСТРОЙКА И ДЕРЕВО", p_props, spot + Vector3(0.0, 0.0, 30.0), "props")

	print("\n=== ВИЗУАЛЬНЫЙ ДЫМ: проверок %d, провалов: %d ===" % [_checks, _fails])
	print("снимки: %s_{units,horde,props}.png" % _out)
	get_tree().paused = false
	get_tree().quit(1 if _fails > 0 else 0)
