extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ОБЩИЕ ВИЗУАЛЬНЫЕ РЕСУРСЫ ЮНИТА
## ═══════════════════════════════════════════════════════════════════════════
## ЗАЧЕМ ЭТОТ МОДУЛЬ СУЩЕСТВУЕТ.
##
## Раньше Unit._build_visual() создавал КАЖДОМУ бойцу свой комплект ресурсов:
##   • TorusMesh кольца выделения (32×32 сегмента ≈ 2 тыс. треугольников);
##   • GradientTexture2D + Gradient мягкой тени под ногами;
##   • по StandardMaterial3D на каждый из них;
##   • QuadMesh запасного «тела», которое подкласс тут же прятал.
##
## На отряд в 50 копейщиков это 300 ресурсов, на армию в 600 бойцов — три с
## лишним тысячи. Отсюда два наблюдаемых эффекта:
##   1) ФРИЗ ПРИ НАЙМЕ: GradientTexture2D растеризуется на CPU в момент
##      создания, и полсотни таких за пару кадров видны глазом как рывок;
##   2) НУЛЕВОЕ ПАКЕТИРОВАНИЕ: у одинаковых с виду колец разные материалы,
##      поэтому рендер не может слить их в один вызов отрисовки.
##
## РЕШЕНИЕ — ДВА ПРАВИЛА:
##   • ресурс, одинаковый у всех бойцов, создаётся ОДИН РАЗ и раздаётся
##     ссылкой (ленивые статические поля ниже);
##   • узел, нужный не всегда, не создаётся заранее (кольцо и тень появляются
##     при первом выделении бойца, полоска HP — при первом уроне).
##
## ПОЧЕМУ СТАТИЧЕСКИЕ ПОЛЯ, А НЕ АВТОЗАГРУЗКА: обращение идёт из _ready()
## каждого юнита, и лишний поиск узла в дереве здесь не нужен. Подключение:
##     const _Vis := preload("res://scripts/units/UnitVisuals.gd")

# ── КОЛЬЦО ВЫДЕЛЕНИЯ ─────────────────────────────────────────────────────────
## Тонкое кольцо у ступней. Радиус не масштабируется вместе с юнитом: в плотном
## строю крупные кольца сливались бы в сплошное пятно
const RING_INNER := 0.26
const RING_OUTER := 0.29
const RING_Y     := 0.03

static var _ring_mesh: TorusMesh = null

## Общий меш кольца выделения. Материал вшит в сам меш — он тоже общий
static func ring_mesh() -> TorusMesh:
	if _ring_mesh != null:
		return _ring_mesh
	var torus := TorusMesh.new()
	torus.inner_radius = RING_INNER
	torus.outer_radius = RING_OUTER
	# СЕГМЕНТОВ ВТРОЕ МЕНЬШЕ, ЧЕМ ПО УМОЛЧАНИЮ. Кольцо диаметром 58 см на
	# экране занимает десяток пикселей: 32×32 сегмента там неразличимы, а
	# треугольников дают вдесятеро больше нужного
	torus.rings = 12
	torus.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color    = Color(1, 1, 0, 0.55)
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 1
	torus.material = mat
	_ring_mesh = torus
	return _ring_mesh

# ── КРАСНОЕ КОЛЬЦО ПРИЦЕЛИВАНИЯ (НАВЕДЕНИЕ НА ЧУЖОЙ ОТРЯД) ───────────────────
## То же кольцо, но красное и чуть шире жёлтого. Шире НАМЕРЕННО: свой выделенный
## отряд и наведённый чужой могут оказаться в кадре рядом, и различать их только
## по оттенку в плотном строю тяжело — разный радиус читается мгновенно.
## Заметно плотнее по альфе, чем жёлтое: красное кольцо живёт долю секунды, пока
## курсор над врагом, и обязано прочитаться сразу
const RING_HOVER_INNER := 0.31
const RING_HOVER_OUTER := 0.35

static var _hover_ring_mesh: TorusMesh = null

## Общий меш кольца прицеливания. Ровно один на всю партию — как и жёлтый
static func hover_ring_mesh() -> TorusMesh:
	if _hover_ring_mesh != null:
		return _hover_ring_mesh
	var torus := TorusMesh.new()
	torus.inner_radius = RING_HOVER_INNER
	torus.outer_radius = RING_HOVER_OUTER
	torus.rings = 12
	torus.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color    = Color(1.0, 0.16, 0.14, 0.78)
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Приоритет выше жёлтого: если под бойцом почему-то оба кольца, сверху
	# должно лежать то, которое отвечает на действие игрока прямо сейчас
	mat.render_priority = 2
	torus.material = mat
	_hover_ring_mesh = torus
	return _hover_ring_mesh

# ── МЕТКА ТОЧКИ НАЗНАЧЕНИЯ ───────────────────────────────────────────────────
## Отдельный меш, а не кольцо выделения в увеличенном масштабе, и вот почему.
## Метка ставится масштабом трансформа, а масштаб тянет ВСЁ кольцо разом —
## вместе с толщиной. Кольцо выделения при пятикратном увеличении давало
## жирный обруч в полтора метра: на траве это читалось как площадь, куда
## отряд встанет, а не как точка, куда он идёт.
##
## Здесь толщина задана В МЕШЕ и специально нитяная: 0.006 против 0.03 у
## выделения. При рабочем масштабе (SelectionDecalRenderer.DEST_SCALE) выходит
## аккуратная окружность в полметра с волосяной линией
const DEST_INNER := 0.294
const DEST_OUTER := 0.300

static var _dest_ring_mesh: TorusMesh = null

static func dest_ring_mesh() -> TorusMesh:
	if _dest_ring_mesh != null:
		return _dest_ring_mesh
	var torus := TorusMesh.new()
	torus.inner_radius = DEST_INNER
	torus.outer_radius = DEST_OUTER
	# Сегментов по кольцу БОЛЬШЕ, чем у выделения: та окружность живёт под
	# ногами и её край не разглядеть, а эта лежит на пустой траве одна
	torus.rings = 24
	torus.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color    = Color(1, 1, 0.35, 0.62)
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 1
	torus.material = mat
	_dest_ring_mesh = torus
	return _dest_ring_mesh

# ── МЯГКАЯ ТЕНЬ ПОД НОГАМИ ───────────────────────────────────────────────────
## Приплюснута по Z и прижата к земле — читается как тень у ступней,
## а не как диск, над которым юнит «висит»
const SHADOW_SIZE := Vector2(0.78, 0.50)
const SHADOW_Y    := 0.012

static var _shadow_mesh: QuadMesh = null

## Общий меш тени. Градиентная текстура строится РОВНО ОДИН РАЗ на всю партию
static func shadow_mesh() -> QuadMesh:
	if _shadow_mesh != null:
		return _shadow_mesh
	var tex := GradientTexture2D.new()
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to   = Vector2(0.5, 0.0)
	# Текстура крошечная: тень размыта по определению, разрешение ей не нужно,
	# а растеризация 64×64 против стандартных 2048×2048 дешевле в тысячу раз
	tex.width  = 64
	tex.height = 64
	var grad := Gradient.new()
	# ── ВОЗВРАТ К ИСХОДНОЙ ПЛОТНОСТИ 0.28 ──────────────────────────────────
	# Её понизили до 0.11, разбирая «чёрные пятна под бойцами». Разбор оказался
	# неверным: пятна давала не эта тень, а ВПЕЧАТАННЫЙ В АРТ овал под ступнями,
	# который непрозрачный материал печатал плотной кляксой (лечится в
	# mm_unit_sprite.gdshader). Эту же тень носит только ВЫДЕЛЕННЫЙ боец, и на
	# траве под жёлтым кольцом 0.11 почти не читалась — то есть понижение
	# ослабило не то, что мешало
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.28))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	tex.gradient = grad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode      = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size     = SHADOW_SIZE
	quad.material = mat
	_shadow_mesh = quad
	return _shadow_mesh

# ── ТЕНЬ ПОД ЛЕЖАЩИМ ТЕЛОМ ───────────────────────────────────────────────────
## СВОЙ материал, а не общий с тенью выделения, и это не дублирование.
##
## Тень стоящего — овал под ступнями, её носит только выделенный боец. Тень
## лежащего есть у КАЖДОГО тела и лежит она под туловищем, поэтому у неё две
## своих задачи и своя плотность.
##
## ПОЧЕМУ БЛЕДНЕЕ ЖИВОЙ. На завале тела перекрываются, и пятна складываются
## друг с другом: при плотности, годной для одиночки, куча превращается в
## чёрную кляксу. 0.10 — это заметная «посадка на грунт» для одиночного тела и
## терпимое сгущение там, где их лежит десяток.
##
## ПОЧЕМУ НЕ ЕЩЁ БЛЕДНЕЕ. Впечатанный в арт овал под ступнями у трупа теперь
## срезается целиком (см. mm_corpse.gdshader), и это пятно осталось у тела
## ЕДИНСТВЕННОЙ тенью. На 0.055 завал выглядел наклейкой на траве.
static var _corpse_shadow_mesh: QuadMesh = null

static func corpse_shadow_mesh() -> QuadMesh:
	if _corpse_shadow_mesh != null:
		return _corpse_shadow_mesh
	var tex := GradientTexture2D.new()
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to   = Vector2(0.5, 0.0)
	tex.width  = 64
	tex.height = 64
	var grad := Gradient.new()
	# Вдвое бледнее тени живого — см. разбор про складывание теней на завале.
	# 0.10 замеряли на снимке: под одиночным телом трава темнела на 6%, то есть
	# пятна на экране не было вовсе. 0.16 даёт под одиночкой едва заметную
	# посадку на грунт, а на завале, где пятна ложатся по два-три внахлёст, —
	# ту самую глубину, без которой куча читается наклейкой
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.16))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	tex.gradient = grad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode      = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size     = Vector2(1.0, 1.0)
	quad.material = mat
	_corpse_shadow_mesh = quad
	return _corpse_shadow_mesh

# ── ФОРМА СТОЛКНОВЕНИЯ ───────────────────────────────────────────────────────
## Капсула у всех бойцов одна и та же (масштаб юнита общий), а маски в проекте
## нулевые — ни один юнит ни с чем не сталкивается. Форма нужна ТОЛЬКО как
## мишень для луча выбора, поэтому её смело можно разделить на всех
static var _capsule: CapsuleShape3D = null

static func capsule(unit_scale: float) -> CapsuleShape3D:
	if _capsule != null:
		return _capsule
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28 * unit_scale
	shape.height = 1.5 * unit_scale
	_capsule = shape
	return _capsule

# ── ПОЛОСКА ЗДОРОВЬЯ ─────────────────────────────────────────────────────────
## Материал полоски одинаков у всех: цвет, билборд, отключённая глубина.
## Сам QuadMesh общим быть НЕ МОЖЕТ — у каждого бойца своя доля здоровья,
## а она задаётся размером меша (см. Unit._apply_hp_bar_fraction)
static var _hp_mat: StandardMaterial3D = null

static func hp_bar_material() -> StandardMaterial3D:
	if _hp_mat != null:
		return _hp_mat
	var m := StandardMaterial3D.new()
	m.albedo_color    = Color(0.86, 0.12, 0.12)
	m.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode  = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode       = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test   = true       # полоска не тонет в спрайте юнита
	m.render_priority = 4
	_hp_mat = m
	return _hp_mat

# ── СБОРКА УЗЛОВ ─────────────────────────────────────────────────────────────

## Кольцо выделения как готовый узел. Зовётся ЛЕНИВО — при первом выделении
static func make_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "SelectionRing"
	mi.mesh = ring_mesh()
	# Вплотную к земле — кольцо лежит у основания ног, юнит «стоит», а не «летает»
	mi.position.y = RING_Y
	return mi

## Мини-тень как готовый узел. Тоже ленивая: у невыделенного бойца её нет
static func make_shadow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "SelectionShadow"
	mi.mesh = shadow_mesh()
	mi.rotation_degrees.x = -90.0
	mi.position.y = SHADOW_Y
	return mi
