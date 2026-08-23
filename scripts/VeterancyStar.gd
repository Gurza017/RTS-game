extends MeshInstance3D
## ЗВЁЗДОЧКА ВЕТЕРАНА над отрядом.
##
## Маленькая ярко-жёлтая пятиконечная звезда, висящая над головой командира
## отряда. Готовой картинки под неё в ассет-паке нет, поэтому геометрия
## строится процедурно — как и остальные вспомогательные меши проекта.
##
## Узел цепляется ДОЧЕРНИМ к бойцу-носителю: тогда он ездит вместе с ним сам,
## без единой строчки в _process. Носитель погиб — GameManager перевешивает
## звезду на следующего живого (см. _refresh_star).
##
## Файл намеренно без class_name: подключается через preload.

const _UCfg := preload("res://scripts/unit_stats_config.gd")

## Высота над центром юнита, метры
const STAR_HEIGHT := 2.35
## Внешний радиус звезды, метры.
## УВЕЛИЧЕН РОВНО ВДВОЕ (0.098 → 0.196) по заказу владельца. Прежний размер
## подбирался под звезду, висевшую над головой ОДНОГО бойца-командира, — там
## она и должна была быть мелкой, чтобы не закрывать его. Теперь звезда стоит
## над центром масс всего отряда (см. GameManager.refresh_star), то есть
## заметно дальше от глаза при том же зуме, и мелкая просто терялась в строю
const STAR_RADIUS := 0.196
## Отношение внутреннего радиуса к внешнему: чем меньше, тем острее лучи
const INNER_RATIO := 0.45

## Просвет между соседними звёздами ряда. Считается от радиуса, а не задан
## числом: у золотой звезды радиус больше (VET_TIER_SCALE), и фиксированный
## шаг заставил бы её лучи налезать на соседей
const SPACING_RATIO := 2.43

## ── ТОЛЩИНА ТЁМНОЙ ОБВОДКИ ─────────────────────────────────────────────────
## Доля от БАЗОВОГО радиуса, а не от радиуса своего грейда: обводка обязана
## быть одной и той же толщины у всех звёзд. Привяжи её к грейду — и золотая
## получила бы контур в полтора раза жирнее, то есть выглядела бы не крупнее,
## а грязнее. 0.13 от 0.196 м — это около двух экранных пикселей на рабочем
## зуме, ровно тот тонкий кант, который заказан
const OUTLINE_RATIO := 0.13

static func create(level: int) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	root.set_script(load("res://scripts/VeterancyStar.gd"))
	root.name = "VeterancyStar"
	root.build(level)
	return root

## Уровень, под который сейчас построен ряд звёзд. По нему GameManager видит,
## что отряд подрос, и перестраивает мех, не создавая узел заново
var shown_level: int = 0

## ГРЕЙД, ПОД КОТОРЫЙ ПОСТРОЕН РЯД. Число звёзд и цвет берутся не из уровня
## напрямую, а из таблицы конфига (VET_STAR_TIERS): уровень 4 — это ОДНА
## серебряная звезда, а не четыре бронзовых
func build(level: int) -> void:
	shown_level = maxi(level, 1)
	var tier: Dictionary = _UCfg.veteran_star_tier(shown_level)
	if tier.is_empty():
		mesh = null
		return
	mesh = _make_star_row(int(tier["count"]),
		tier["color"] as Color, float(tier["scale"]),
		tier.get("outline", _UCfg.VET_STAR_OUTLINE) as Color)
	position.y = STAR_HEIGHT
	# Поверх спрайтов: звезда не должна тонуть в фигуре бойца
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## ── РЯД ИЗ n ЗВЁЗД ОДНОГО ГРЕЙДА, ЦЕНТРИРОВАННЫЙ ПО X ──────────────────────
## ДВЕ ПОВЕРХНОСТИ, А НЕ ОДНА: сперва весь ряд тёмным контуром, поверх — тот же
## ряд цветом грейда. Обводка нужна затем, что звезда висит над чем угодно —
## над зелёной травой, над тёмной кроной, над светлым шлемом, — и любой один
## цвет на одном из этих фонов пропадает.
##
## ПОРЯДОК РЕШАЕТ render_priority, А НЕ ГЛУБИНА. У звезды снят тест глубины
## (см. _make_material): она индикатор и обязана быть видна поверх спрайтов.
## Значит и внутри самой звезды буфер глубины ничего не упорядочит — контур и
## заливка разведены приоритетами 7 и 8
func _make_star_row(n: int, col: Color, scale_mul: float, outline: Color) -> ArrayMesh:
	var r: float = STAR_RADIUS * scale_mul
	var step: float = r * SPACING_RATIO
	# Толщина контура от БАЗОВОГО радиуса: одна на все грейды (см. OUTLINE_RATIO)
	var grow: float = STAR_RADIUS * OUTLINE_RATIO

	var m := ArrayMesh.new()
	var back := SurfaceTool.new()
	back.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		_add_star(back, (float(i) - float(n - 1) * 0.5) * step, r, grow, outline)
	back.generate_normals()
	back.commit(m)

	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		_add_star(face, (float(i) - float(n - 1) * 0.5) * step, r, 0.0, col)
	face.generate_normals()
	face.commit(m)

	m.surface_set_material(0, _make_material(outline, 7))
	m.surface_set_material(1, _make_material(col, 8))
	return m

## Одна пятиконечная звезда: 10 внешних/внутренних вершин веером от центра.
##
## `grow` РАЗДВИГАЕТ ВЕРШИНЫ ПО РАДИУСУ, а не масштабирует звезду целиком, и
## разница тут принципиальная. Общий масштаб растянул бы и лучи, и впадины
## пропорционально: у луча длиной 0.196 контур вышел бы втрое шире, чем во
## впадине на 0.088, и кант читался бы как клякса на остриях. Прибавка одного
## и того же числа к каждому радиусу даёт кант ровной ширины
func _add_star(st: SurfaceTool, dx: float, r: float, grow: float, col: Color) -> void:
	var points: Array = []
	for i in range(10):
		var ang: float = -PI * 0.5 + TAU * float(i) / 10.0
		var rr: float = (r if i % 2 == 0 else r * INNER_RATIO) + grow
		points.append(Vector3(dx + cos(ang) * rr, sin(ang) * rr, 0.0))
	var center := Vector3(dx, 0.0, 0.0)
	for i in range(10):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % 10]
		st.set_color(col)
		st.add_vertex(center)
		st.set_color(col)
		st.add_vertex(a)
		st.set_color(col)
		st.add_vertex(b)

func _make_material(col: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color            = col
	m.vertex_color_use_as_albedo = true
	m.shading_mode            = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode          = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode               = BaseMaterial3D.CULL_DISABLED
	# Контур задан с альфой (0.9), и без прозрачности она бы просто потерялась
	if col.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Звезда — индикатор, а не часть мира: её видно поверх любых спрайтов
	m.no_depth_test           = true
	m.render_priority         = priority
	return m
